"""tools/voice_raw/*.wav（gen_voice.ps1 の出力）を無線らしい音質にして audio/voice/ へ書き出し、
ゲームが字幕から音声を引く表 scripts/voice_lines.gd を作る。

    py -3.10 tools/gen_voice_fx.py

艦内の声（艦長・砲術長・航法）は艦内通話：帯域広め・雑音少なめ。
他艦からの声（旗艦・艦隊通信）は無線：帯域を絞り、歪みと空電を足す。
"""
import csv
import os
import wave
import numpy as np
from scipy import signal

ROOT = os.path.join(os.path.dirname(__file__), "..")
RAW = os.path.join(os.path.dirname(__file__), "voice_raw")
OUT = os.path.join(ROOT, "audio", "voice")
SR = 22050
rng = np.random.default_rng(7)

# 話者 → (低域, 高域, 歪み, 雑音, 低音の持ち上げ)
FX = {
    "旗艦": (220, 3600, 2.2, 0.018, 1.25),
    "艦隊通信": (320, 3300, 2.6, 0.028, 1.0),
    "艦長": (130, 5500, 1.4, 0.006, 1.2),
    "砲術長": (150, 5200, 1.5, 0.006, 1.1),
    "航法": (170, 5500, 1.3, 0.005, 1.0),
}


def read(path):
    with wave.open(path, "rb") as w:
        n = w.getnframes()
        ch = w.getnchannels()
        sr = w.getframerate()
        x = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float64) / 32768.0
    if ch > 1:
        x = x.reshape(-1, ch).mean(axis=1)
    return x, sr


def write(path, x):
    x = np.clip(x, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def squelch(n, amp):
    t = np.arange(n) / SR
    return signal.sosfilt(signal.butter(2, [900 / (SR / 2), 5000 / (SR / 2)], "band", output="sos"),
                          rng.standard_normal(n)) * np.exp(-t / 0.02) * amp


def process(x, sr, speaker):
    lo, hi, drive, hiss, bass = FX[speaker]
    x = signal.resample_poly(x, SR, sr)
    # 無音部分を詰める
    env = np.abs(x) > 0.01
    if env.any():
        a = max(0, np.argmax(env) - int(0.03 * SR))
        b = min(len(x), len(x) - np.argmax(env[::-1]) + int(0.08 * SR))
        x = x[a:b]
    x = x / (np.max(np.abs(x)) + 1e-9)
    # 渋さ：低めの帯域を少し持ち上げる
    if bass > 1.0:
        low = signal.sosfilt(signal.butter(2, [110 / (SR / 2), 400 / (SR / 2)], "band", output="sos"), x)
        x = x + low * (bass - 1.0) * 2.0
    x = signal.sosfilt(signal.butter(3, [lo / (SR / 2), hi / (SR / 2)], "band", output="sos"), x)
    x = np.tanh(x * drive) / np.tanh(drive)
    # 空電（声の大きさに少し追従）
    n = len(x)
    e = signal.sosfilt(signal.butter(1, 8 / (SR / 2), "low", output="sos"), np.abs(x))
    noise = signal.sosfilt(signal.butter(2, [lo / (SR / 2), hi / (SR / 2)], "band", output="sos"), rng.standard_normal(n))
    x = x + noise * hiss * (0.6 + e * 3.0)
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
    pre = int(0.06 * SR)
    post = int(0.12 * SR)
    y = np.zeros(pre + n + post)
    y[pre:pre + n] = x
    y[:pre] += squelch(pre, 0.25)
    y[pre + n:] += squelch(post, 0.35)
    return y


def main():
    os.makedirs(OUT, exist_ok=True)
    rows = list(csv.DictReader(open(os.path.join(os.path.dirname(__file__), "voice_lines.tsv"), encoding="utf-8"), delimiter="\t"))
    done = []
    for r in rows:
        src = os.path.join(RAW, r["id"] + ".wav")
        if not os.path.exists(src):
            print("missing", r["id"])
            continue
        x, sr = read(src)
        y = process(x, sr, r["speaker"])
        write(os.path.join(OUT, r["id"] + ".wav"), y)
        done.append(r)
        print(f"{r['id']:9s} {len(y) / SR:5.2f}s  {r['speaker']}")
    # ゲーム側の表
    lines = ["# 自動生成：tools/gen_voice_fx.py（元は tools/voice_lines.tsv）。手で書き換えない",
             "class_name VoiceLines", "", "## 字幕（日本語）または鍵 → 音声ファイルの id", "const BY_TEXT := {"]
    for r in done:
        key = r["id"] if r["id"].startswith("escort_") else r["jp"]
        lines.append(f'\t"{key}": "{r["id"]}",')
    lines += ["}", "", "## id → 英語のセリフ（字幕の下に小さく出す）", "const EN := {"]
    for r in done:
        en = r["en"].replace('"', '\\"')
        lines.append(f'\t"{r["id"]}": "{en}",')
    lines.append("}")
    open(os.path.join(ROOT, "scripts", "voice_lines.gd"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print(len(done), "lines")


main()

"""無線のセリフを Azure AI Speech（有料 S0・既定のニューラル音声）で読み上げて tools/voice_raw/ へ書き出す。

    py -3.10 tools/gen_voice_azure.py            # 全セリフ
    py -3.10 tools/gen_voice_azure.py v01 v07    # 指定のセリフだけ
    py -3.10 tools/gen_voice_azure.py --samples  # 声の聞き比べ用（tools/voice_samples/）
    py -3.10 tools/gen_voice_fx.py               # 無線らしい音質にして audio/voice/ へ

キーとリージョンは Windows のユーザー環境変数 AZURE_SPEECH_KEY / AZURE_SPEECH_REGION から読む。
キーはファイルにも出力にも書かない。
"""
import csv
import os
import sys
import time
import urllib.request
import winreg
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "voice_raw")
SAMPLES = os.path.join(HERE, "voice_samples")

# 話者 → 声・話し方・高さ・速さ（style は声が対応している場合のみ）
CAST = {
    "旗艦": {"voice": "en-US-DavisNeural", "style": "", "pitch": "-8%", "rate": "-6%"},
    "艦長": {"voice": "en-US-GuyNeural", "style": "", "pitch": "-6%", "rate": "-2%"},
    "砲術長": {"voice": "en-US-TonyNeural", "style": "", "pitch": "-4%", "rate": "+4%"},
    "航法": {"voice": "en-US-AriaNeural", "style": "", "pitch": "-2%", "rate": "+4%"},
    "艦隊通信": {"voice": "en-US-JennyNeural", "style": "", "pitch": "+0%", "rate": "+8%"},
}


def env(name):
    v = os.environ.get(name)
    if v:
        return v
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as k:
        return winreg.QueryValueEx(k, name)[0]


def ssml(text, voice, style="", pitch="+0%", rate="+0%"):
    body = f"<prosody pitch='{pitch}' rate='{rate}'>{escape(text)}</prosody>"
    if style:
        body = f"<mstts:express-as style='{style}'>{body}</mstts:express-as>"
    return ("<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' "
            "xmlns:mstts='https://www.w3.org/2001/mstts' xml:lang='en-US'>"
            f"<voice name='{voice}'>{body}</voice></speak>")


def synth(doc, out_path):
    key = env("AZURE_SPEECH_KEY")
    region = env("AZURE_SPEECH_REGION")
    req = urllib.request.Request(
        f"https://{region}.tts.speech.microsoft.com/cognitiveservices/v1",
        data=doc.encode("utf-8"), method="POST",
        headers={"Ocp-Apim-Subscription-Key": key, "Content-Type": "application/ssml+xml",
                 "X-Microsoft-OutputFormat": "riff-24khz-16bit-mono-pcm", "User-Agent": "hiruyasumi-gunner"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            with open(out_path, "wb") as f:
                f.write(data)
            return len(data)
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 3:
                time.sleep(2 + attempt * 2)
                continue
            raise SystemExit(f"Azure エラー {e.code}: {e.read()[:300]!r}")


def samples():
    os.makedirs(SAMPLES, exist_ok=True)
    line = "Enemy line, dead ahead. All ships, open fire. Knock out those turrets!"
    male = [
        ("en-US-DavisNeural", ""), ("en-US-DavisNeural", "unfriendly"), ("en-US-GuyNeural", ""),
        ("en-US-TonyNeural", ""), ("en-US-JasonNeural", ""), ("en-US-ChristopherNeural", ""),
        ("en-US-RogerNeural", ""), ("en-US-SteffanNeural", ""), ("en-US-BrianNeural", ""),
        ("en-GB-ThomasNeural", ""),
    ]
    female = [("en-US-AriaNeural", ""), ("en-US-JennyNeural", ""), ("en-US-SaraNeural", "")]
    n = 0
    for v, st in male:
        name = f"m_{v.replace('Neural', '').split('-')[-1]}{'_' + st if st else ''}"
        synth(ssml(line, v, st, "-8%", "-4%"), os.path.join(SAMPLES, name + ".wav"))
        n += 1
        print(name)
    fl = "Entering the minefield. Only shoot the mines in our path."
    for v, st in female:
        name = f"f_{v.replace('Neural', '').split('-')[-1]}"
        synth(ssml(fl, v, st, "-2%", "+4%"), os.path.join(SAMPLES, name + ".wav"))
        n += 1
        print(name)
    print(n, "samples ->", SAMPLES)


def main():
    if "--samples" in sys.argv:
        samples()
        return
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    os.makedirs(RAW, exist_ok=True)
    rows = list(csv.DictReader(open(os.path.join(HERE, "voice_lines.tsv"), encoding="utf-8"), delimiter="\t"))
    chars = 0
    for r in rows:
        if only and r["id"] not in only:
            continue
        c = CAST[r["speaker"]]
        synth(ssml(r["en"], c["voice"], c["style"], c["pitch"], c["rate"]), os.path.join(RAW, r["id"] + ".wav"))
        chars += len(r["en"])
        print(f"{r['id']:9s} {c['voice']:22s} {r['en']}")
    print(f"{chars} 文字を合成")


main()

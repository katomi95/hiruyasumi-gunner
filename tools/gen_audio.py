"""昼休みの宇宙戦争：GUNNER — 効果音をプログラム合成して audio/ に WAV で書き出す。

    py -3.10 tools/gen_audio.py

宇宙空間だがゲーム演出として音を鳴らす。巨大レーザーは
「低音のチャージ → 一瞬の静寂 → 強烈な発射音」の三段で使う（静寂はゲーム側で作る）。
"""
import os
import wave
import numpy as np
from scipy import signal

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
rng = np.random.default_rng(20260923)


def save(name, x, peak=0.9):
    x = np.asarray(x, dtype=np.float64)
    x = np.tanh(x / (np.max(np.abs(x)) + 1e-9) * 1.2) / np.tanh(1.2)
    x = x * peak
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    print(f"{name:16s} {len(x) / SR:.2f}s")


def T(d):
    return np.arange(int(d * SR)) / SR


def noise(n):
    return rng.standard_normal(n)


def brown(n):
    x = np.cumsum(rng.standard_normal(n))
    return signal.sosfilt(signal.butter(1, 15 / (SR / 2), "high", output="sos"), x) * 0.05


def lp(x, f, o=2):
    return signal.sosfilt(signal.butter(o, min(f, SR / 2 - 100) / (SR / 2), "low", output="sos"), x)


def hp(x, f, o=2):
    return signal.sosfilt(signal.butter(o, f / (SR / 2), "high", output="sos"), x)


def bp(x, lo, hi, o=2):
    return signal.sosfilt(signal.butter(o, [lo / (SR / 2), min(hi, SR / 2 - 100) / (SR / 2)], "band", output="sos"), x)


def sweep(f0, f1, d, curve="exp"):
    t = T(d)
    if curve == "exp":
        f = f0 * (f1 / f0) ** (t / d)
    else:
        f = f0 + (f1 - f0) * t / d
    return np.cumsum(f) / SR * 2 * np.pi


def env(n, a, d, sustain=0.0):
    t = np.arange(n) / SR
    e = np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-np.maximum(t - a, 0) / d)
    return e * (1 - sustain) + sustain * np.minimum(t / max(a, 1e-4), 1.0)


def loopify(x, fade=0.5):
    f = int(fade * SR)
    head, body, tail = x[:f], x[f:-f], x[-f:]
    t = np.linspace(0, 1, f)
    return np.concatenate([body, tail * np.cos(t * np.pi / 2) + head * np.sin(t * np.pi / 2)])


def varlp(x, f0, f1):
    """区間ごとにカットオフを変える簡易可変ローパス"""
    out = np.zeros_like(x)
    n = len(x)
    seg = 512
    zi = None
    sos_prev = None
    for i in range(0, n, seg):
        k = i / n
        f = f0 * (f1 / f0) ** k
        sos = signal.butter(2, min(f, SR / 2 - 200) / (SR / 2), "low", output="sos")
        if zi is None:
            zi = signal.sosfilt_zi(sos) * 0
        out[i:i + seg], zi = signal.sosfilt(sos, x[i:i + seg], zi=zi)
    return out


def boom(d, f_lo=60, bright=2000, crack=0.6, sub=1.0):
    n = int(d * SR)
    nz = noise(n)
    body = varlp(nz, bright, 120) * env(n, 0.004, d * 0.28)
    rum = lp(brown(n), 160) * env(n, 0.02, d * 0.45) * 8
    t = T(d)
    thump = np.sin(sweep(f_lo * 1.8, f_lo * 0.6, d)) * env(n, 0.003, 0.25) * sub
    cr = hp(nz, 2500) * env(n, 0.001, 0.05) * crack
    # 細かい破裂
    pops = np.zeros(n)
    for _ in range(int(d * 14)):
        i = int(rng.uniform(0.02, 0.7) * n)
        m = int(0.02 * SR)
        if i + m < n:
            pops[i:i + m] += noise(m) * np.exp(-np.arange(m) / (0.004 * SR)) * rng.uniform(0.2, 0.6)
    pops = bp(pops, 400, 4000) * env(n, 0.05, d * 0.3)
    return body * 1.2 + rum + thump + cr + pops * 0.8


os.makedirs(OUT, exist_ok=True)

# ---- 自砲 ---------------------------------------------------------------
d = 0.2
n = int(d * SR)
ph = sweep(2600, 520, d)
x = (np.sin(ph) + 0.35 * np.sign(np.sin(ph * 1.5))) * env(n, 0.001, 0.045)
x += np.sin(sweep(900, 140, d)) * env(n, 0.001, 0.03) * 0.7
x += hp(noise(n), 3000) * env(n, 0.0005, 0.008) * 0.8
save("shot", x, 0.8)

d = 1.1
n = int(d * SR)
x = np.sin(sweep(420, 36, d)) * env(n, 0.002, 0.35) * 1.3
x += varlp(noise(n), 6000, 200) * env(n, 0.001, 0.25)
x += np.sin(sweep(3000, 300, d)) * env(n, 0.001, 0.08) * 0.5
x += hp(noise(n), 2000) * env(n, 0.0005, 0.02)
save("heavy", x, 0.95)

d = 0.12
n = int(d * SR)
x = bp(noise(n), 1500, 7000) * env(n, 0.0005, 0.018)
x += np.sin(2 * np.pi * 3400 * T(d)) * env(n, 0.0005, 0.03) * 0.5
save("hit", x, 0.7)

d = 0.3
n = int(d * SR)
x = sum(np.sin(2 * np.pi * f * T(d)) * env(n, 0.0005, dd) * a for f, dd, a in
        [(830, 0.12, 1), (1370, 0.08, 0.8), (2210, 0.06, 0.6), (3150, 0.04, 0.5), (4700, 0.02, 0.4)])
x += hp(noise(n), 1500) * env(n, 0.0005, 0.012) * 1.5
save("armor", x, 0.6)

d = 0.9
n = int(d * SR)
t = T(d)
x = np.sign(np.sin(sweep(620, 90, d))) * env(n, 0.005, 0.25) * 0.4
x += bp(noise(n), 2000, 7000) * np.linspace(1, 0, n) ** 2 * 0.8
x += np.sin(2 * np.pi * 50 * t) * (np.sin(2 * np.pi * 23 * t) > 0) * env(n, 0.01, 0.3) * 0.3
save("overheat", x, 0.6)

d = 0.07
n = int(d * SR)
x = np.sin(2 * np.pi * 2300 * T(d)) * env(n, 0.001, 0.02)
save("lock", x, 0.35)

# ---- 爆発 ---------------------------------------------------------------
save("explo_s", boom(0.9, 90, 5000, 0.8, 0.8), 0.85)
save("explo_m", boom(1.8, 60, 3500, 0.7, 1.0), 0.95)
save("explo_l", boom(4.0, 40, 2500, 0.5, 1.3), 1.0)
x = boom(2.6, 45, 700, 0.0, 1.2)
save("far_boom", lp(x, 500), 0.9)

d = 2.2
n = int(d * SR)
x = boom(d, 38, 1800, 0.9, 1.6)
x += np.sin(sweep(80, 30, d)) * env(n, 0.001, 0.6) * 1.5
save("cannon", x, 1.0)

# 質量兵器の崩壊：長い地鳴りと亀裂音
d = 7.0
n = int(d * SR)
x = lp(brown(n), 120) * env(n, 0.8, 3.0) * 14
for _ in range(40):
    i = int(rng.uniform(0.0, 0.8) * n)
    m = int(rng.uniform(0.05, 0.3) * SR)
    if i + m < n:
        x[i:i + m] += bp(noise(m), 200, 3000) * np.exp(-np.arange(m) / (0.05 * SR)) * rng.uniform(0.3, 1.0)
x += boom(d, 30, 1500, 0.8, 2.0)
save("break", x, 1.0)

# ---- 敵 -----------------------------------------------------------------
d = 0.32
n = int(d * SR)
ph = sweep(1100, 180, d)
x = np.sign(np.sin(ph)) * env(n, 0.002, 0.08) * 0.6 + np.sin(ph * 0.5) * env(n, 0.002, 0.1)
save("enemy_shot", lp(x, 5000), 0.6)

d = 1.4
n = int(d * SR)
x = varlp(noise(n), 900, 5000) * env(n, 0.05, 0.6) + np.sin(sweep(160, 90, d)) * env(n, 0.02, 0.4) * 0.5
save("missile_launch", x, 0.7)

d = 0.14
n = int(d * SR)
x = np.sign(np.sin(2 * np.pi * 1450 * T(d))) * env(n, 0.002, 0.05)
save("missile_warn", lp(x, 6000), 0.4)

d = 1.6
n = int(d * SR)
t = T(d)
fc = 400 + 1800 * np.exp(-((t - 0.7) / 0.25) ** 2)
x = np.zeros(n)
nz = noise(n)
seg = 256
for i in range(0, n, seg):
    f = fc[i]
    x[i:i + seg] = bp(nz[max(0, i - 2048):i + seg], f * 0.6, f * 1.5)[-len(x[i:i + seg]):]
amp = np.exp(-((t - 0.7) / 0.35) ** 2)
x = x * amp + np.sin(sweep(520, 170, d)) * amp * 0.35
save("flyby", x, 0.7)

d = 0.12
n = int(d * SR)
x = np.sin(2 * np.pi * 2900 * T(d)) * env(n, 0.001, 0.03) + np.sin(2 * np.pi * 1450 * T(d)) * env(n, 0.001, 0.05) * 0.5
save("mine_beep", x, 0.35)

# ---- 自艦 ---------------------------------------------------------------
d = 0.8
n = int(d * SR)
x = boom(d, 70, 4000, 1.0, 1.0)
x += sum(np.sin(2 * np.pi * f * T(d)) * env(n, 0.001, 0.15) * 0.3 for f in (310, 470, 755))
save("player_hit", x, 1.0)

d = 0.6
n = int(d * SR)
t = T(d)
f = np.where(t < 0.3, 880, 660)
x = np.sign(np.sin(np.cumsum(f) / SR * 2 * np.pi)) * (np.minimum(t * 60, 1)) * np.minimum((d - t) * 40, 1)
save("alarm", lp(x, 3500), 0.35)

# ---- 巨大レーザー --------------------------------------------------------
# 充填ループ（4秒・整数周期でつながる）
d = 4.0
n = int(d * SR)
t = T(d)
x = np.sin(2 * np.pi * 41 * t) + 0.6 * np.sin(2 * np.pi * 41.5 * t) + 0.5 * np.sin(2 * np.pi * 82 * t + np.sin(2 * np.pi * 0.5 * t))
x += 0.25 * np.sin(2 * np.pi * 123 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 2 * t))
x += 0.08 * np.sin(2 * np.pi * 1640 * t + 3 * np.sin(2 * np.pi * 7 * t)) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.25 * t))
save("charge_loop", x, 0.8)

# 充填の最終段：上昇するうなり
d = 3.2
n = int(d * SR)
t = T(d)
x = np.sin(sweep(90, 900, d)) * (t / d) ** 1.5
x += np.sin(sweep(45, 180, d)) * 0.8
x += bp(noise(n), 300, 3000) * (t / d) ** 3 * 0.8
x *= np.minimum((d - t) * 30, 1)
save("charge_final", x, 0.9)

# 発射音：鋭い立ち上がり＋極低音＋長い轟き
d = 6.5
n = int(d * SR)
t = T(d)
x = np.sin(sweep(95, 26, d)) * env(n, 0.003, 2.2) * 1.6
x += np.tanh(varlp(noise(n), 9000, 180) * 3) * env(n, 0.001, 1.6) * 0.9
x += lp(brown(n), 200) * env(n, 0.05, 2.5) * 16
x += hp(noise(n), 3000) * env(n, 0.0005, 0.06) * 1.2
save("laser_fire", x, 1.0)

# 照射中のループ（掃射で使う）
d = 3.0
n = int(d * SR) + int(0.5 * SR)
t = np.arange(n) / SR
x = np.tanh(bp(noise(n), 80, 1400) * 2.5) * 0.7 + np.sin(2 * np.pi * 55 * t) * 0.6 + np.sin(2 * np.pi * 110.5 * t) * 0.25
save("beam_loop", loopify(x, 0.5), 0.8)

# ---- 環境 ---------------------------------------------------------------
# 艦内の低い唸りと遠い砲声のざわめき（8秒ループ）
d = 8.0
n = int(d * SR) + int(1.0 * SR)
t = np.arange(n) / SR
x = np.sin(2 * np.pi * 38 * t) * 0.5 + np.sin(2 * np.pi * 76 * t) * 0.15 + np.sin(2 * np.pi * 57 * t) * 0.1
x += lp(brown(n), 90) * 10
x += bp(noise(n), 150, 600) * 0.06 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.13 * t))
save("amb_loop", loopify(x, 1.0), 0.55)

# ---- UI -----------------------------------------------------------------
d = 0.2
n = int(d * SR)
x = bp(noise(n), 800, 5000) * env(n, 0.002, 0.03) + np.sin(2 * np.pi * 1200 * T(d)) * env(n, 0.001, 0.02) * 0.3
save("radio", x, 0.35)

d = 1.8
n = int(d * SR)
t = T(d)
x = np.zeros(n)
for i, f in enumerate([220, 330, 440, 660]):
    s = int(i * 0.09 * SR)
    m = n - s
    x[s:] += (np.sin(2 * np.pi * f * T(m / SR)) + 0.3 * np.sin(2 * np.pi * f * 2 * T(m / SR))) * env(m, 0.01, 0.6)
save("start", x, 0.6)

d = 3.5
n = int(d * SR)
x = np.zeros(n)
for i, f in enumerate([262, 330, 392, 523, 659, 784]):
    s = int(i * 0.12 * SR)
    m = n - s
    x[s:] += (np.sin(2 * np.pi * f * T(m / SR)) + 0.25 * np.sin(2 * np.pi * f * 3 * T(m / SR))) * env(m, 0.01, 1.2)
save("clear", x, 0.6)

d = 3.0
n = int(d * SR)
x = np.zeros(n)
for i, f in enumerate([392, 311, 262, 196]):
    s = int(i * 0.28 * SR)
    m = n - s
    x[s:] += np.sin(2 * np.pi * f * T(m / SR)) * env(m, 0.01, 0.9)
save("gameover", x, 0.55)

# ---- ハイパージャンプ ----------------------------------------------------
# 充填：低い唸りが上昇していく
d = 3.2
n = int(d * SR)
t = T(d)
x = np.sin(sweep(55, 420, d)) * (t / d) ** 1.2 + 0.5 * np.sin(sweep(110, 840, d)) * (t / d) ** 2
x += bp(noise(n), 400, 4000) * (t / d) ** 3 * 0.9
x *= np.minimum((d - t) * 20, 1)
save("jump_charge", x, 0.8)

# 突入：一瞬で吸い込まれる轟音
d = 2.4
n = int(d * SR)
x = varlp(noise(n), 12000, 300) * env(n, 0.002, 0.5) * 1.2
x += np.sin(sweep(900, 40, d)) * env(n, 0.001, 0.6) * 1.2
x += np.sin(sweep(60, 25, d)) * env(n, 0.01, 1.0) * 1.4
save("jump_in", x, 1.0)

# 跳躍中：トンネルの唸り（ループ）
d = 3.0
n = int(d * SR) + int(0.5 * SR)
tt = np.arange(n) / SR
x = bp(noise(n), 200, 2500) * (0.6 + 0.4 * np.sin(2 * np.pi * 3 * tt)) * 0.6
x += np.sin(2 * np.pi * 72 * tt) * 0.5 + np.sin(2 * np.pi * 144.5 * tt) * 0.2
save("jump_loop", loopify(x, 0.5), 0.6)

# 離脱：逆向きの膨らみと鈍い衝撃
d = 2.2
n = int(d * SR)
t = T(d)
sw = np.exp(-((t - 0.25) / 0.18) ** 2)
x = bp(noise(n), 300, 6000) * sw * 1.2 + np.sin(sweep(30, 120, d)) * sw
x += np.sin(sweep(90, 30, d)) * env(n, 0.25, 0.6) * 1.2 * (t > 0.2)
save("jump_out", x, 0.95)

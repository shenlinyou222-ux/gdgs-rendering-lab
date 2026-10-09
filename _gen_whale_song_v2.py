# -*- coding: utf-8 -*-
"""终局鲸歌 v2 (~36s, stereo): 对比 v1 更"活" ——
  1) 双声部对位(母鲸低吟 + 幼鲸高应答), 频率由控制点三次样条插值, 滑音更自然
  2) 声部带合唱层(微失谐 x3)与呼吸噪声, 泛音随音高动态加权(共鸣腔感)
  3) 深海垫底 pad(低频三和弦缓慢呼吸) + 稀疏气泡/叩击点缀
  4) 双通道差异化混响(宽立体声), 轻限幅归一化
产物: assets/sfx/whale_song.wav (44.1kHz/16bit/stereo)
"""
import os
import wave

import numpy as np
from scipy.signal import butter, fftconvolve, sosfilt

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "sfx", "whale_song.wav")
DUR = 36.0
rng = np.random.default_rng(7)


def freq_curve(pts, n):
    """控制点 (t, f) 三次样条 -> 平滑频率轨迹."""
    ts = np.array([p[0] for p in pts], dtype=float)
    fs = np.array([p[1] for p in pts], dtype=float)
    t = np.linspace(0.0, ts[-1], n)
    f = np.interp(t, ts, fs)
    # 两轮三点平滑近似样条(避免引入 scipy.interpolate 依赖差异)
    for _ in range(60):
        f = np.convolve(np.pad(f, 1, mode="edge"), [0.25, 0.5, 0.25], mode="valid")
    return t, f


def voice(pts, dur, amp, vib_hz, vib_depth, breath=0.10):
    n = int(dur * SR)
    t, f = freq_curve(pts, n)
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.zeros(n)
    for k, a in ((1, 1.0), (2, 0.42), (3, 0.20), (4, 0.08), (5, 0.05)):
        w = a * (1.0 + 0.6 * np.exp(-((f - 180.0) / 260.0) ** 2) / k)  # 共振峰加权
        y += w * np.sin(k * ph + rng.uniform(0, 6.28))
    vib = 1.0 + vib_depth * np.sin(2 * np.pi * vib_hz * t + rng.uniform(0, 6.28))
    y *= vib
    # 合唱层: 两路微失谐
    for det in (-0.7, 0.9):
        ph2 = 2 * np.pi * np.cumsum(f * (1.0 + det / 1000.0)) / SR
        y += 0.30 * np.sin(ph2 + rng.uniform(0, 6.28))
    # 呼吸噪声(高通轻混)
    nz = rng.standard_normal(n)
    nz = sosfilt(butter(2, 1500, "hp", fs=SR, output="sos"), nz)
    y += breath * nz * (0.5 + 0.5 * np.sin(2 * np.pi * 0.5 * t))
    env = np.minimum(t / 1.4, 1.0) * np.minimum((dur - t) / 2.4, 1.0)
    return amp * y * np.clip(env, 0, 1) / 2.2


def reverb(x, taps_s=4.6, seed=0):
    r = np.random.default_rng(seed)
    wet = np.zeros_like(x)
    for delay, decay in ((0.149, 0.62), (0.233, 0.52), (0.367, 0.44), (0.521, 0.36)):
        d = int(delay * SR)
        taps = int(taps_s * SR / d) + 1
        imp = np.zeros(taps * d)
        imp[::d] = decay ** np.arange(taps)
        imp += 0.25 * r.standard_normal(imp.size) * decay ** np.arange(imp.size)  # 色散尾
        wet += fftconvolve(x, imp)[: len(x)]
    return wet


def main():
    total = int(DUR * SR)
    t = np.arange(total) / SR
    L = np.zeros(total)
    # ---- 声部1: 母鲸(低) 呼唤-长吟-叹息 ----
    L[0:int(8.5*SR)] += voice([(0, 160), (1.5, 240), (4.0, 190), (6.0, 120), (8.0, 95)], 8.5, 0.42, 3.1, 0.045)[:int(8.5*SR)]
    L[int(9.5*SR):int(18.0*SR)] += voice([(0, 110), (3.0, 150), (5.0, 210), (6.5, 170), (8.0, 100)], 8.5, 0.36, 2.4, 0.05)[:int(8.5*SR)]
    L[int(27.0*SR):] += voice([(0, 150), (2.0, 90), (5.0, 70), (8.5, 62)], 9.0, 0.40, 1.8, 0.04)[: total - int(27.0*SR)]
    # ---- 声部2: 幼鲸(高) 应答对位 ----
    R = np.zeros(total)
    R[int(3.0*SR):int(8.0*SR)] += voice([(0, 520), (1.2, 640), (3.0, 480), (5.0, 560)], 5.0, 0.20, 5.2, 0.06)[:int(5.0*SR)]
    R[int(12.0*SR):int(16.5*SR)] += voice([(0, 700), (1.0, 560), (2.8, 640), (4.2, 430)], 4.5, 0.17, 5.6, 0.06)[:int(4.5*SR)]
    R[int(18.5*SR):int(26.5*SR)] += voice([(0, 400), (2.0, 540), (4.0, 460), (6.0, 620), (7.6, 380)], 8.0, 0.22, 4.4, 0.055)[:int(8.0*SR)]
    R[int(30.0*SR):] += voice([(0, 460), (1.5, 340), (4.0, 300), (5.8, 250)], 6.0, 0.16, 4.0, 0.05)[: total - int(30.0*SR)]
    # ---- 深海 pad: A1-E2-B2 缓慢呼吸 ----
    pad = np.zeros(total)
    for f0, a in ((55.0, 0.30), (82.4, 0.22), (123.5, 0.13)):
        pad += a * np.sin(2 * np.pi * f0 * t + rng.uniform(0, 6.28)) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.07 * t + f0))
    pad = sosfilt(butter(2, 400, "lp", fs=SR, output="sos"), pad)
    # ---- 稀疏气泡/叩击 ----
    fx = np.zeros(total)
    for _ in range(9):
        p = rng.uniform(1.0, DUR - 2.0)
        i = int(p * SR)
        n = int(0.05 * SR)
        bl = np.exp(-np.arange(n) / (0.008 * SR)) * np.sin(2 * np.pi * rng.uniform(900, 2400) * np.arange(n) / SR)
        fx[i:i + n] += 0.05 * bl
    # ---- 森林式合成: pad/声部进入混响 ----
    Lm = L + 0.5 * pad + fx
    Rm = R + 0.5 * pad + 0.7 * fx
    Lw = Lm + 0.62 * reverb(Lm, seed=11)
    Rw = Rm + 0.62 * reverb(Rm, seed=23)
    # 轻微交叉串音加宽
    mixL = Lw + 0.18 * Rw
    mixR = Rw + 0.18 * Lw
    out = np.stack([mixL, mixR], axis=1)
    # 后处理: 低通去毛刺 + 高通去直流 + 软限幅归一
    for ch in range(2):
        out[:, ch] = sosfilt(butter(3, 8000, "lp", fs=SR, output="sos"), out[:, ch])
        out[:, ch] = sosfilt(butter(2, 26, "hp", fs=SR, output="sos"), out[:, ch])
    out = np.tanh(out * 1.1)
    peak = max(float(np.max(np.abs(out))), 1e-9)
    out = out / peak * 0.88
    with wave.open(OUT, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((out * 32767).astype("<i2").tobytes())
    print("whale_song v2 %.0fs stereo -> %s" % (DUR, OUT))


if __name__ == "__main__":
    main()

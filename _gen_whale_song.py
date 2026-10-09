# -*- coding: utf-8 -*-
"""终局鲸歌合成器(~28s): 分层座头鲸式鸣唱 + 巨型混响尾, numpy 纯合成.
产物: assets/sfx/whale_song.wav (44.1kHz/16bit/mono)
铺垫用短促远歌复用既有 whale_distant.wav; 本曲只在 BOSS 陨落后的终局剧情播放.
"""
import os
import wave

import numpy as np
from scipy.signal import butter, fftconvolve, sosfilt

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "sfx", "whale_song.wav")
DUR = 28.0
rng = np.random.default_rng(20260914)


def moan(t0, dur, f0, f1, amp, vib_hz=4.5, vib_depth=0.035, harm=(1.0, 0.5, 0.22)):
    """下滑+颤音的鲸鸣: 基频指数下滑, 叠加弱泛音列."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f0 * (f1 / f0) ** (t / max(dur - 0.2, 1e-6))          # 指数滑频
    f = f * (1.0 + vib_depth * np.sin(2 * np.pi * vib_hz * t)) # 颤音
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.zeros(n)
    for k, a in enumerate(harm, start=1):
        y += a * np.sin(k * ph + rng.uniform(0, 6.28))
    env = np.minimum(t / 1.2, 1.0) * np.minimum((dur - t) / 1.8, 1.0)  # 攻释
    return t0, amp * y * np.clip(env, 0, 1)


def main():
    total = int(DUR * SR)
    buf = np.zeros(total)
    # 乐句结构: 呼唤(高)->应答(低)->长吟->三连短叹->终结长音(渐隐)
    calls = [
        moan(0.5, 5.0, 420, 180, 0.50, vib_hz=5.0),
        moan(6.5, 4.0, 300, 150, 0.42, vib_hz=3.8),
        moan(11.0, 7.0, 180, 240, 0.55, vib_hz=2.6, vib_depth=0.05),   # 上行长吟
        moan(19.0, 1.6, 500, 320, 0.30, vib_hz=6.0),
        moan(20.8, 1.6, 480, 300, 0.28, vib_hz=6.0),
        moan(22.6, 5.0, 260, 96, 0.50, vib_hz=3.0),                    # 终结低吟
    ]
    for t0, y in calls:
        i = int(t0 * SR)
        buf[i:i + len(y)] += y[:max(0, total - i)]
    # 亚声部: 18Hz-30Hz 次声脉动(体积感, 听感为"压力")
    t = np.arange(total) / SR
    buf += 0.06 * np.sin(2 * np.pi * 24 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.11 * t))
    # 巨型混响: 三组指数衰减梳 + 低通(FFT 卷积, 直线卷积在 28s×4sIR 下不可行)
    wet = np.zeros(total)
    for delay, decay in ((0.162, 0.62), (0.247, 0.5), (0.393, 0.42)):
        d = int(delay * SR)
        taps = int(4.0 * SR / d) + 1
        imp = np.zeros(taps * d)
        imp[::d] = decay ** np.arange(taps)
        wet += fftconvolve(buf, imp)[:total]
    buf = buf + 0.55 * wet
    buf = sosfilt(butter(3, 7000, "lp", fs=SR, output="sos"), buf)
    buf = sosfilt(butter(2, 28, "hp", fs=SR, output="sos"), buf)
    peak = max(float(np.max(np.abs(buf))), 1e-9)
    buf = buf / peak * 0.85
    with wave.open(OUT, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((buf * 32767).astype("<i2").tobytes())
    print(f"whale_song.wav {DUR:.0f}s -> {OUT}")


if __name__ == "__main__":
    main()

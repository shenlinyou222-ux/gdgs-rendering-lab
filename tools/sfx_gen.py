#!/usr/bin/env python3
# sfx_gen.py - 程序化音效合成器(零依赖纯DSP)
# 用法: python sfx_gen.py <preset> [输出.wav]
#   preset: whale_roar | whale_distant | whale_greet | missile_launch | explode_big
# 产物直接写 assets/sfx/, 生成后需 Godot --headless --import
import sys, math, random, struct, wave

SR = 44100
OUT = "assets/sfx"

def render(dur, fn):
    n = int(SR * dur)
    out = [0.0] * n
    st = {"ph": 0.0, "ph2": 0.0, "lp": 0.0, "lp2": 0.0}
    peak = 1e-9
    for i in range(n):
        t = i / SR
        v = fn(t, st)
        out[i] = v
        peak = max(peak, abs(v))
    g = 0.85 / peak
    return [v * g for v in out]

def env(t, dur, atk, rel):
    if t < atk: return t / atk
    if t > dur - rel: return max(0.0, (dur - t) / rel)
    return 1.0

def whale_roar():
    # 三乐章: 30-60Hz苏醒轰鸣 -> 60冲180再滑落70Hz长啸 -> 回荡远去; 颤音+呼吸调制+深混响
    D = 14.0
    def f(t, st):
        p = t / D
        if p < 0.2: fr, amp = 30 + 30 * (p / 0.2), 0.4 + 0.6 * (p / 0.2)
        elif p < 0.65:
            q = (p - 0.2) / 0.45
            fr = 60 * (180 / 60) ** (q / 0.4) if q < 0.4 else 180 * (70 / 180) ** ((q - 0.4) / 0.6)
            amp = 1.0
        else:
            q = (p - 0.65) / 0.35
            fr, amp = 70 * (45 / 70) ** q, 1.0 - 0.8 * q
        vib = math.sin(2 * math.pi * 3.5 * t) * 7
        st["ph"] += 2 * math.pi * (fr + vib) / SR
        st["ph2"] += 2 * math.pi * (fr * 0.5 + vib * 0.5) / SR
        breath = 0.85 + 0.15 * math.sin(2 * math.pi * 0.8 * t)
        return (math.sin(st["ph"]) * 0.55 + math.sin(st["ph2"]) * 0.35
                + math.sin(st["ph"] * 2) * 0.12) * amp * breath * env(t, D, 0.3, 1.5)
    out = render(D, f)
    # 深空混响: 多抽头回声
    taps = [(0.09, 0.4), (0.21, 0.3), (0.38, 0.22), (0.61, 0.16), (0.95, 0.11), (1.4, 0.08), (2.0, 0.05)]
    res = out[:]
    for dt, g in taps:
        off = int(dt * SR)
        for i in range(off, len(out)):
            res[i] += out[i - off] * g
    peak = max(abs(v) for v in res)
    return [v * 0.85 / peak for v in res]

def whale_distant():
    D = 18.0
    def f(t, st):
        p = t / D
        fr = 100 * (140 / 100) ** min(p / 0.3, 1.0) * (45 / 140) ** max(0.0, (p - 0.3) / 0.7)
        vib = math.sin(2 * math.pi * 2.5 * t) * 4
        st["ph"] += 2 * math.pi * (fr + vib) / SR
        st["ph2"] += 2 * math.pi * (fr * 0.5 + vib) / SR
        return (math.sin(st["ph"]) * 0.7 + math.sin(st["ph2"]) * 0.3) * env(t, D, 2.0, 6.0)
    return render(D, f)

def whale_greet():
    D = 6.0
    def f(t, st):
        p = t / D
        fr = 90 * (130 / 90) ** (p / 0.4) * (340 / 130) ** (max(0.0, p - 0.4) / 0.6) if p < 0.4 else 130 * (340 / 130) ** ((p - 0.4) / 0.6)
        vib = math.sin(2 * math.pi * 6 * t) * 8
        st["ph"] += 2 * math.pi * (fr + vib) / SR
        st["ph2"] += 2 * math.pi * (fr * 0.5) / SR
        return (math.sin(st["ph"]) * 0.7 + math.sin(st["ph2"]) * 0.3) * env(t, D, 0.4, 1.5)
    return render(D, f)

def missile_launch():
    D = 0.4
    def f(t, st):
        ignite = math.exp(-t * 45)
        hiss = math.exp(-((t - 0.06) / 0.16) ** 2)
        thrust = min(1.0, t / 0.05) * math.exp(-t * 5.5)
        n = random.random() * 2 - 1
        st["lp"] += 0.45 * (n - st["lp"])
        st["lp2"] += 0.07 * (n - st["lp2"])
        st["ph"] += 2 * math.pi * (70 - 40 * t) / SR
        return n * ignite * 0.5 + st["lp"] * hiss * 0.9 + st["lp2"] * thrust * 1.7 + math.sin(st["ph"]) * thrust * 0.7
    return render(D, f)

def explode_big():
    D = 1.6
    def f(t, st):
        boom = math.exp(-t * 3.2)
        crack = math.exp(-((t - 0.06) / 0.12) ** 2) + (1.5 if (random.random() < 0.02 and t < 0.8) else 0)
        n = random.random() * 2 - 1
        st["lp"] += (0.2 - 0.16 * min(t, 1)) * (n - st["lp"])
        st["ph"] += 2 * math.pi * 48 * (0.5 ** (t * 2)) / SR
        st["ph2"] += 2 * math.pi * 110 * (0.4 ** (t * 2)) / SR
        return (math.sin(st["ph"]) * 1.1 * boom + math.sin(st["ph2"]) * 0.5 * boom + st["lp"] * 1.2 * boom + n * crack * 0.7) * env(t, D, 0.001, 0.5)
    return render(D, f)

PRESETS = {
    "whale_roar": whale_roar, "whale_distant": whale_distant, "whale_greet": whale_greet,
    "missile_launch": missile_launch, "explode_big": explode_big,
}

def save(name, samples):
    path = sys.argv[2] if len(sys.argv) > 2 else f"{OUT}/{name}.wav"
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", max(-32768, min(32767, int(v * 32767)))) for v in samples))
    print("saved", path, f"{len(samples)/SR:.1f}s")

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in PRESETS:
        print(__doc__); sys.exit(1)
    save(sys.argv[1], PRESETS[sys.argv[1]]())

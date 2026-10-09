# -*- coding: utf-8 -*-
"""太空战斗 SFX 合成器: 纯标准库, 44.1kHz/16bit/mono, 峰值归一 0.8"""
import math, random, struct, wave, os

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "sfx")
random.seed(20260910)

def write_wav(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    k = 0.8 / peak
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * k)) * 32767)) for s in samples))
    print(name, f"{len(samples)/SR:.2f}s")

def n_samples(sec): return int(SR * sec)

def env_ad(n, attack, tau):
    out, a = [], n_samples(attack)
    for i in range(n):
        g = i / a if i < a else 1.0
        out.append(g * math.exp(-i / (tau * SR)))
    return out

def sweep_freq(n, f0, f1):
    """指数扫频瞬时频率表"""
    r = (f1 / f0) ** (1 / max(n - 1, 1))
    fs, f = [], f0
    for _ in range(n):
        fs.append(f); f *= r
    return fs

def osc(fs, drive=1.0):
    out, ph = [], 0.0
    for f in fs:
        ph += 2 * math.pi * f / SR
        out.append(math.tanh(drive * math.sin(ph)))
    return out

def noise(n):
    return [random.uniform(-1, 1) for _ in range(n)]

def lowpass(xs, a=0.15):
    out, y = [], 0.0
    for x in xs:
        y += a * (x - y); out.append(y)
    return out

def mix(*layers):
    n = max(len(l) for l in layers)
    return [sum(l[i] if i < len(l) else 0.0 for l in layers) for i in range(n)]

def mul(a, b): return [x * y for x, y in zip(a, b)]

def beep(f, sec, tau=None):
    n = n_samples(sec)
    e = env_ad(n, 0.008, tau or sec * 0.35)
    return mul([math.sin(2 * math.pi * f * i / SR) for i in range(n)], e)

# 1) 机炮: 短促激光 zap
n = n_samples(0.09)
cannon = mul(mix(osc(sweep_freq(n, 1600, 280), 2.5),
                 mul(noise(n), [1.0 if i < SR * 0.008 else 0.12 for i in range(n)])),
             env_ad(n, 0.002, 0.030))
write_wav("cannon.wav", cannon)

# 2) 等离子: 低频 whoomp
n = n_samples(0.28)
plasma = mul(mix(osc(sweep_freq(n, 420, 70), 3.0),
                 mul(lowpass(noise(n), 0.08), [0.35] * n)),
             env_ad(n, 0.010, 0.110))
write_wav("plasma.wav", plasma)

# 3) 玩家受击: 噪声撞击 + 低频铃振
n = n_samples(0.18)
hitp = mul(mix(mul(lowpass(noise(n), 0.5), [1.0 if i < SR * 0.02 else 0.4 for i in range(n)]),
               [math.sin(2 * math.pi * 180 * i / SR) * 0.7 for i in range(n)]),
           env_ad(n, 0.002, 0.060))
write_wav("hit_player.wav", hitp)

# 4) 命中敌机: 高频短 tick
n = n_samples(0.11)
hite = mul(mix(osc(sweep_freq(n, 950, 480), 1.5), mul(noise(n), [0.25] * n)),
           env_ad(n, 0.002, 0.035))
write_wav("hit_enemy.wav", hite)

# 5) 爆炸: 褐噪声衰减 + 次声 thump
n = n_samples(0.65)
wn = noise(n); br, acc = [], 0.0
for x in wn:
    acc = acc * 0.985 + x * 0.015; br.append(acc)
pk = max(abs(b) for b in br); br = [b / pk for b in br]
expl = mul(mix(mul(br, [1.0] * n), [math.sin(2 * math.pi * 55 * i / SR) * 0.9 for i in range(n)]),
           env_ad(n, 0.004, 0.170))
write_wav("explode.wav", expl)

# 6) 过热: 双蜂鸣 880/660
oh = beep(880, 0.09) + [0.0] * n_samples(0.06) + beep(660, 0.11)
write_wav("overheat.wav", oh)

# 7) 锁定: 单 blip
write_wav("lock.wav", beep(1250, 0.07, 0.02))

# 8) 开门: 上行琶音 523/659/784
gate = []
for f in (523.25, 659.25, 783.99):
    gate += beep(f, 0.10, 0.04)
gate += beep(1046.5, 0.16, 0.07)
write_wav("gate.wav", gate)
print("done ->", OUT)

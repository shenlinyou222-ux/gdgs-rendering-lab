import os
import numpy as np

# 星鲸烘焙器 v1: 座头鲸外形 ~45万高斯球 (gdgs 标准 14 属性 PLY)
# 朝向: 头 = -Z(前), 背 = +Y, 尾鳍 = +Z(后), 左右 = ±X
rng = np.random.default_rng(20260912)
SH_C0 = 0.28209479177387814
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "whale", "whale_humpback.ply")
Z_HEAD = 520.0


def profile(z):
    t = np.clip((Z_HEAD - z) / 940.0, 0.0, 1.0)
    r = 250.0 * np.power(np.sin(np.pi * np.power(t, 0.52)), 0.45) * (1.0 - 0.12 * t)
    return np.maximum(r, 30.0 * (1.0 - t) + 26.0)


def squash(z):
    t = np.clip((Z_HEAD - z) / 940.0, 0.0, 1.0)
    return np.clip(0.9 - 0.35 * np.power(t, 1.1), 0.3, 1.0)


def surface(n, z0, z1, rmin=None, keep=None):
    z = rng.uniform(z0, z1, n)
    r = profile(z)
    if rmin is not None:
        rr = r * (rmin + (1.0 - rmin) * rng.random(n))
    else:
        rr = r * (0.97 + 0.03 * rng.random(n))
    sq = squash(z)
    th = rng.uniform(0, 2 * np.pi, n)
    x = np.cos(th) * rr
    y = np.sin(th) * rr * sq
    p = np.stack([x, y, z], axis=1)
    if keep is not None:
        m = keep(p)
        p = p[m]
    return p


P, C, S = [], [], []


def add(p, col, sz):
    P.append(p)
    C.append(np.broadcast_to(np.asarray(col, dtype=np.float64), (len(p), 3)).copy())
    S.append(np.broadcast_to(np.asarray(sz, dtype=np.float64), len(p)).copy())


# 体背(深靛蓝)
add(surface(150000, -420.0, 520.0), [0.10, 0.22, 0.38], rng.uniform(10.0, 22.0, 150000))
# 体腹(青白辉光)
belly = surface(90000, -420.0, 460.0, keep=lambda p: p[:, 1] < 0.0)
add(belly, [0.42, 0.68, 0.74], rng.uniform(12.0, 24.0, len(belly)))
# 内层稀疏填充
add(surface(30000, -380.0, 480.0, rmin=0.25), [0.09, 0.20, 0.34], rng.uniform(16.0, 30.0, 30000))
# 头部钝圆
z = rng.uniform(330.0, 520.0, 40000)
r = profile(z)
sq = squash(z)
th = rng.uniform(0, 2 * np.pi, 40000)
add(np.stack([np.cos(th) * r, np.sin(th) * r * sq * 1.05, z], axis=1), [0.16, 0.30, 0.45], rng.uniform(12.0, 26.0, 40000))
# 头部封口(收口圆盘, 消除空心)
zcap = rng.uniform(495.0, 522.0, 9000)
rcap = np.maximum(28.0 * np.sqrt(np.clip((522.0 - zcap) / 30.0, 0.0, 1.0)), 1.5)
thc = rng.uniform(0, 2 * np.pi, 9000)
add(np.stack([np.cos(thc) * rcap, np.sin(thc) * rcap * squash(zcap), zcap], axis=1),
    [0.10, 0.19, 0.30], rng.uniform(12.0, 20.0, 9000))

# 尾柄
z = rng.uniform(-420.0, -80.0, 35000)
r = profile(z)
sq = squash(z)
th = rng.uniform(0, 2 * np.pi, 35000)
add(np.stack([np.cos(th) * r, np.sin(th) * r * sq, z], axis=1), [0.10, 0.21, 0.34], rng.uniform(10.0, 18.0, 35000))


def fluke(n):
    t = rng.random(n) ** 0.8
    z = -430.0 - 190.0 * t
    sgn = np.sign(rng.integers(0, 2, n) - 0.5)
    x = sgn * (50.0 + 330.0 * np.power(t, 0.9)) * (0.85 + 0.15 * rng.random(n))
    y = rng.uniform(-14.0, 14.0, n) * (1.0 - 0.4 * t)
    return np.stack([x, y, z], axis=1)


# 尾鳍(荧光青, 后缘更亮)
p = fluke(42000)
t = np.clip((p[:, 2] - 430.0) / 190.0, 0.0, 1.0)
col = np.zeros((len(p), 3))
col[:, 0] = 0.10 + 0.16 * t
col[:, 1] = 0.45 + 0.35 * t
col[:, 2] = 0.60 + 0.30 * t
add(p, col, rng.uniform(14.0, 26.0, len(p)))


def pectoral(n, sgn):
    t = rng.random(n)
    d = np.array([sgn * 0.55, -0.52, -0.65])
    d = d / np.linalg.norm(d)
    pos = np.array([0.0, -120.0, 260.0])[None, :] + d[None, :] * (t * 640.0)[:, None]
    pos[:, 0] += sgn * 40.0 * t
    pos += rng.normal(0, 7.0, (n, 3)) * (0.3 + t[:, None])
    return pos


# 胸鳍×2
p = np.concatenate([pectoral(7500, 1.0), pectoral(7500, -1.0)])
add(p, [0.30, 0.70, 0.85], rng.uniform(12.0, 22.0, len(p)))


def dorsal(n):
    t = rng.random(n)
    z = -60.0 + 260.0 * t
    x = rng.normal(0, 12.0, n) * (1.0 - 0.5 * t)
    y = profile(z) * squash(z) + rng.uniform(6.0, 26.0, n) * (1.0 - 0.4 * t)
    return np.stack([x, y, z], axis=1)


add(dorsal(12000), [0.22, 0.45, 0.60], rng.uniform(8.0, 14.0, 12000))


def glow_rows(n):
    sgn = np.sign(rng.integers(0, 2, n) - 0.5)
    row = rng.integers(0, 4, n)
    z = rng.uniform(-300.0, 380.0, n)
    frac = np.clip((Z_HEAD - z) / 940.0, 0.05, 0.95)
    r = profile(z)
    zoff = (0.55 + 0.12 * (row % 2)) * r
    y = -(0.30 + 0.16 * (row // 2)) * r * squash(z)
    x = sgn * zoff
    return np.stack([x, y, z], axis=1)


p = glow_rows(16000)
add(p, [0.30, 0.90, 1.0], rng.uniform(7.0, 13.0, len(p)))

# 眼×2
for sgn in (1.0, -1.0):
    z = rng.uniform(380.0, 400.0, 40)
    x = sgn * (95.0 + rng.uniform(-6.0, 6.0, 40))
    y = -40.0 + rng.uniform(-10.0, 10.0, 40)
    p = np.stack([x, y, z], axis=1)
    add(p, [0.85, 0.98, 1.0], rng.uniform(3.0, 6.0, 40))

pos = np.concatenate(P)
col = np.concatenate(C)
sz = np.concatenate(S)
n = len(pos)
order = rng.permutation(n)
pos, col, sz = pos[order], col[order], sz[order]

f_dc = (col - 0.5) / 0.28209479177387814
opacity = np.full(n, np.log(0.97 / 0.03), dtype=np.float64)
data = np.zeros((n, 14), dtype=np.float32)
data[:, 0:3] = pos
data[:, 3:6] = f_dc
data[:, 6] = opacity
data[:, 7:10] = np.log(sz)[:, None]
data[:, 10] = 1.0   # 单位四元数(球状高斯)

names = ["x", "y", "z", "f_dc_0", "f_dc_1", "f_dc_2", "opacity",
         "scale_0", "scale_1", "scale_2", "rot_0", "rot_1", "rot_2", "rot_3"]
header = "ply\nformat binary_little_endian 1.0\ncomment star whale (procedural humpback)\nelement vertex %d\n" % n
header += "".join("property float %s\n" % nm for nm in names)
header += "end_header\n"

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "wb") as f:
    f.write(header.encode("ascii"))
    f.write(data.tobytes())
print("baked", OUT)
print("splats:", n, " bytes:", os.path.getsize(OUT))
print("z: %.0f..%.0f  x: ±%.0f  y: %.0f..%.0f" % (pos[:, 2].min(), pos[:, 2].max(), np.abs(pos[:, 0]).max(), pos[:, 1].min(), pos[:, 1].max()))

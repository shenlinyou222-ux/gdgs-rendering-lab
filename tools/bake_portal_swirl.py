# bake_portal_swirl.py — 程序化传送门漩涡高斯(螺旋涡流盘, 轻量 ~9k 点)
import os, numpy as np
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "props", "portal_swirl.ply")
SH_C0 = 0.28209479177387814
rng = np.random.default_rng(20260913)
N = 9000
# 双臂螺旋盘: 半径平方均匀(盘面均匀), 角度沿半径扭转, 厚度向边缘变薄, 中心有核
r = np.sqrt(rng.random(N)) * 0.5
arm = rng.integers(0, 2, N)
TAU_ = 6.2831853
ang = arm * np.pi + r * 9.0 + rng.normal(0, 0.25 + 0.5 * (1 - r * 2), N)
x = np.cos(ang) * r
z = np.sin(ang) * r
y = rng.normal(0, 0.035 * (1.0 - r) + 0.006, N)
P = np.stack([x, y, z], 1)
# 颜色: 内白外青, 边缘泛紫
t = np.clip(r * 2.0, 0, 1)
col = np.stack([0.85 - 0.45 * t, 0.95 - 0.15 * t, 1.0 - 0.1 * t], 1)
col += rng.normal(0, 0.03, (N, 3))
col = np.clip(col, 0, 1)
sz = np.clip(0.012 + 0.02 * (1 - t) + rng.normal(0, 0.004, N), 0.006, 0.05)
data = np.zeros((N, 14), dtype=np.float32)
data[:, 0:3] = P
data[:, 3:6] = (col - 0.5) / SH_C0
data[:, 6] = np.log(0.95 / 0.05)
data[:, 7:10] = np.log(sz)[:, None]
data[:, 10] = 1.0
names = ["x","y","z","f_dc_0","f_dc_1","f_dc_2","opacity","scale_0","scale_1","scale_2","rot_0","rot_1","rot_2","rot_3"]
hdr = "ply\nformat binary_little_endian 1.0\nelement vertex %d\n" % N
hdr += "".join("property float %s\n" % nm for nm in names) + "end_header\n"
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "wb") as f:
    f.write(hdr.encode()); f.write(data.tobytes())
print("baked", OUT, "points:", N)


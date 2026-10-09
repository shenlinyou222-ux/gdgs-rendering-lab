# bake_goldfish_obj.py v1.4 — OBJ→高斯PLY, 密度法剔倒刺(不伤真鳍)
import os, numpy as np
from PIL import Image
Image.MAX_IMAGE_PIXELS = None   # 4x 贴图 16k×16k 超过 PIL 防炸弹阈值, 本地可信文件
from collections import Counter

BASE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(BASE, "..", "assets", "goldfish_src")
OBJ = os.path.join(SRC, "21f88e23dca954163e70e125c4f78457.obj")
TEX = os.path.join(SRC, "texture_pbr_4x.png")
if not os.path.exists(TEX):
    TEX = os.path.join(SRC, "texture_pbr_20250901.png")
OUT = os.path.join(BASE, "..", "assets", "goldfish", "goldfish_obj_3dgs.ply")
N_TARGET = 650000
SH_C0 = 0.28209479177387814
ROLL_DEG = 30.0
REMOVE_BARBS = False
REMOVE_SMALL_COMP = True

vs, vts, faces = [], [], []
with open(OBJ, "r", errors="ignore") as f:
    for line in f:
        p = line.split()
        if not p: continue
        if p[0] == "v": vs.append((float(p[1]), float(p[2]), float(p[3])))
        elif p[0] == "vt": vts.append((float(p[1]), float(p[2])))
        elif p[0] == "f":
            idx = []
            for tok in p[1:]:
                a = tok.split("/")
                vi = int(a[0]) - 1
                ti = int(a[1]) - 1 if len(a) > 1 and a[1] else -1
                idx.append((vi, ti))
            for k in range(1, len(idx) - 1):
                faces.append((idx[0], idx[k], idx[k + 1]))
V = np.array(vs, dtype=np.float64)
VT = np.array(vts, dtype=np.float64) if vts else np.zeros((0, 2))
F = np.array(faces, dtype=np.int64)
Fv = F[:, :, 0]
print("OBJ: v=%d vt=%d tri=%d" % (len(V), len(VT), len(F)))

# 主轴对齐: 头=+a0, 背=+a2, 左右=±a1 (ASCII 轮廓实证)
c = (V.min(0) + V.max(0)) * 0.5
Vc = V - c
w, U = np.linalg.eigh(Vc.T @ Vc / len(Vc))
o = np.argsort(w)[::-1]
U = U[:, o]
if np.linalg.det(U) < 0: U[:, 2] *= -1
Q = Vc @ U
P = np.stack([Q[:, 1], Q[:, 2], Q[:, 0]], axis=1)
th = np.deg2rad(ROLL_DEG)
ct, st = np.cos(th), np.sin(th)
P = P @ np.array([[ct, -st, 0.0], [st, ct, 0.0], [0.0, 0.0, 1.0]])
print("roll %.0f deg" % ROLL_DEG)
ext = P.max(0) - P.min(0)

if REMOVE_SMALL_COMP:
    parent = np.arange(len(V))
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]; x = parent[x]
        return x
    for t in Fv:
        a, b, c2 = find(int(t[0])), find(int(t[1])), find(int(t[2]))
        if a != b: parent[a] = b
        if b != c2: parent[b] = c2
    roots = np.array([find(i) for i in range(len(V))])
    cnt = Counter(roots[np.unique(Fv)])
    small = roots != cnt.most_common(1)[0][0]
    keep_f = ~small[Fv[:, 0]] & ~small[Fv[:, 1]] & ~small[Fv[:, 2]]
    print("small comp: %d verts / %d faces removed" % (small.sum(), (~keep_f).sum()))
    F = F[keep_f]; Fv = F[:, :, 0]

# (倒刺剔除: 归一化后盒子法, 见下)
P -= (P.min(0) + P.max(0)) * 0.5
sc = 1.0 / ext[2]
P *= sc
SPACING = 1.0   # v2.0 整体放大改为节点缩放(WHALE_LEN), 坐标不特殊处理
P *= SPACING

# 倒刺剔除 v1.5 盒子法(切片实证: 真鳍 x>=-0.09, 孤立刺 x<-0.09 & z>0.22 & y<0):
if REMOVE_BARBS:
    barb = (P[:, 0] < -0.09) & (P[:, 2] > 0.22) & (P[:, 1] < 0.0)
    keep_f = ~barb[Fv[:, 0]] & ~barb[Fv[:, 1]] & ~barb[Fv[:, 2]]
    print("barb removed: %d verts / %d faces" % (barb.sum(), (~keep_f).sum()))
    F = F[keep_f]; Fv = F[:, :, 0]

tri = P[Fv]
e0 = tri[:, 1] - tri[:, 0]; e1 = tri[:, 2] - tri[:, 0]
area = 0.5 * np.linalg.norm(np.cross(e0, e1), axis=1)
# ---- v1.6 自适应密度: 二面角(曲率) + 贴图梯度(花纹细节) 加权 ----
n1 = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
n1 /= (np.linalg.norm(n1, axis=1, keepdims=True) + 1e-12)
edge_faces = {}
for fi in range(len(Fv)):
    a, b_, c2 = Fv[fi]
    for v1, v2 in ((a, b_), (b_, c2), (c2, a)):
        key = (min(int(v1), int(v2)), max(int(v1), int(v2)))
        edge_faces.setdefault(key, []).append(fi)
dihed = np.zeros(len(Fv))
for key, fl in edge_faces.items():
    if len(fl) == 2:
        d = 1.0 - max(0.0, float(n1[fl[0]] @ n1[fl[1]]))   # 0=平, 2=折
        dihed[fl[0]] += d; dihed[fl[1]] += d
dihed /= 3.0
_img_pre = np.asarray(Image.open(TEX).convert("RGB"), dtype=np.float32) / 255.0
_H, _W = _img_pre.shape[:2]
tuv = VT[F[:, :, 1]]
_ok = (F[:, :, 1] >= 0).all(axis=1)
tcol = np.zeros((len(F), 3, 3), dtype=np.float32)
if _ok.any():
    uu = np.clip((tuv[_ok, :, 0] % 1.0) * _W, 0, _W - 1).astype(np.int64)
    vv = np.clip((1.0 - (tuv[_ok, :, 1] % 1.0)) * _H, 0, _H - 1).astype(np.int64)
    tcol[_ok] = np.stack([_img_pre[vv[:, k], uu[:, k]] for k in range(3)], axis=1)
tgrad = np.zeros(len(F))
m2 = _ok & (np.abs(tcol[:, 0] - tcol[:, 1]).sum(1) > 0) | _ok
tgrad = np.maximum(np.abs(tcol[:, 0] - tcol[:, 1]).max(1), np.abs(tcol[:, 1] - tcol[:, 2]).max(1)) * _ok
detail = 1.0 + 3.0 * np.clip(dihed / 0.35, 0.0, 1.0) + 2.0 * np.clip(tgrad / 0.35, 0.0, 1.0)
print("detail weight: mean=%.2f p95=%.2f" % (detail.mean(), np.quantile(detail, 0.95)))
prob = area * detail
prob = prob / prob.sum()

cnt2 = np.maximum((prob * N_TARGET).astype(np.int64), 0)
pick = np.repeat(np.arange(len(F)), cnt2)
rng = np.random.default_rng(20260913)
r1, r2 = rng.random(len(pick)), rng.random(len(pick))
s = np.sqrt(r1)
b0, b1, b2 = 1 - s, s * (1 - r2), s * r2
tp = b0[:, None] * tri[pick, 0] + b1[:, None] * tri[pick, 1] + b2[:, None] * tri[pick, 2]
edge = (np.linalg.norm(e0[pick], axis=1) + np.linalg.norm(e1[pick], axis=1) + np.linalg.norm((tri[pick,1]-tri[pick,2]), axis=1)) / 3.0
sz = np.clip(edge * 0.45 * sc / np.sqrt(np.clip(detail[pick], 1.0, 5.0)), 0.0003, 0.003)

img = np.asarray(Image.open(TEX).convert("RGB"))   # uint8 (4x 贴图 768MB, 转 float 会爆内存)
H, W = img.shape[:2]
tidx = F[pick][:, :, 1]
ok = (tidx >= 0).all(axis=1)
uv = b0[:, None] * VT[tidx[:, 0]] + b1[:, None] * VT[tidx[:, 1]] + b2[:, None] * VT[tidx[:, 2]]
u = np.clip((uv[:, 0] % 1.0) * W, 0, W - 1).astype(np.int64)
v = np.clip((1.0 - (uv[:, 1] % 1.0)) * H, 0, H - 1).astype(np.int64)
col = np.ones((len(tp), 3)) * 0.7
col[ok] = img[v[ok], u[ok]].astype(np.float64) / 255.0

f_dc = (col - 0.5) / SH_C0
opacity = np.full(len(tp), np.log(0.97 / 0.03))
data = np.zeros((len(tp), 14), dtype=np.float32)
data[:, 0:3] = tp
data[:, 3:6] = f_dc
data[:, 6] = opacity
data[:, 7:10] = np.log(sz)[:, None]
data[:, 10] = 1.0
names = ["x","y","z","f_dc_0","f_dc_1","f_dc_2","opacity","scale_0","scale_1","scale_2","rot_0","rot_1","rot_2","rot_3"]
hdr = "ply\nformat binary_little_endian 1.0\ncomment goldfish from OBJ (density barb removal)\nelement vertex %d\n" % len(tp)
hdr += "".join("property float %s\n" % nm for nm in names) + "end_header\n"
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "wb") as f:
    f.write(hdr.encode()); f.write(data.tobytes())
print("baked", OUT, os.path.getsize(OUT), "bytes, splats=%d" % len(tp))

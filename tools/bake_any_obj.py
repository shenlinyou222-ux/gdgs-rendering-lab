# bake_any_obj.py — 通用 OBJ→高斯 PLY(雷达/中转站/八棱柱等道具)
# 用法: python bake_any_obj.py <obj> <out.ply> [点数]
import os, sys, numpy as np
from PIL import Image
Image.MAX_IMAGE_PIXELS = None

SH_C0 = 0.28209479177387814

def bake(obj_path, out_path, n_target=150000):
    src_dir = os.path.dirname(obj_path)
    tex = None
    for f in os.listdir(src_dir):
        if f.startswith("texture_pbr") and f.endswith(".png") and "metallic" not in f and "normal" not in f and "roughness" not in f:
            tex = os.path.join(src_dir, f); break
    vs, vts, faces = [], [], []
    with open(obj_path, "r", errors="ignore") as f:
        for line in f:
            p = line.split()
            if not p: continue
            if p[0] == "v": vs.append((float(p[1]), float(p[2]), float(p[3])))
            elif p[0] == "vt": vts.append((float(p[1]), float(p[2])))
            elif p[0] == "f":
                idx = []
                for tok in p[1:]:
                    a = tok.split("/")
                    idx.append((int(a[0]) - 1, int(a[1]) - 1 if len(a) > 1 and a[1] else -1))
                for k in range(1, len(idx) - 1):
                    faces.append((idx[0], idx[k], idx[k + 1]))
    V = np.array(vs); VT = np.array(vts) if vts else np.zeros((0, 2)); F = np.array(faces, dtype=np.int64)
    Fv = F[:, :, 0]
    print("%s: v=%d tri=%d tex=%s" % (os.path.basename(obj_path), len(V), len(F), tex))
    # 主轴: 最长→Z, 次长→X, 最短→Y(道具直立)
    c = (V.min(0) + V.max(0)) * 0.5
    Vc = V - c
    w, U = np.linalg.eigh(Vc.T @ Vc / len(Vc))
    o_ = np.argsort(w)[::-1]; U = U[:, o_]
    if np.linalg.det(U) < 0: U[:, 2] *= -1
    Q = Vc @ U
    P = np.stack([Q[:, 1], Q[:, 2], Q[:, 0]], axis=1)
    ext = P.max(0) - P.min(0)
    P /= ext[2]  # 最长轴=1, 居中(PCA 中心即几何中心附近)
    P -= (P.min(0) + P.max(0)) * 0.5
    tri = P[Fv]
    e0 = tri[:, 1] - tri[:, 0]; e1 = tri[:, 2] - tri[:, 0]
    area = 0.5 * np.linalg.norm(np.cross(e0, e1), axis=1)
    prob = area / area.sum()
    _x = prob * n_target
    _rng0 = np.random.default_rng(7)
    cnt = np.floor(_x).astype(np.int64) + (_rng0.random(len(_x)) < (_x - np.floor(_x))).astype(np.int64)  # 随机舍入(无截断偏差)
    pick = np.repeat(np.arange(len(F)), cnt)
    rng = np.random.default_rng(20260913)
    r1, r2 = rng.random(len(pick)), rng.random(len(pick))
    s = np.sqrt(r1)
    b0, b1, b2 = 1 - s, s * (1 - r2), s * r2
    tp = b0[:, None] * tri[pick, 0] + b1[:, None] * tri[pick, 1] + b2[:, None] * tri[pick, 2]
    edge = (np.linalg.norm(e0[pick], axis=1) + np.linalg.norm(e1[pick], axis=1) + np.linalg.norm(tri[pick,1]-tri[pick,2], axis=1)) / 3.0
    sz = np.clip(edge * 0.5, 0.0008, 0.006)
    col = np.ones((len(tp), 3)) * 0.6
    if tex is not None and len(VT):
        img = np.asarray(Image.open(tex).convert("RGB"))
        H, W = img.shape[:2]
        tidx = F[pick][:, :, 1]
        ok = (tidx >= 0).all(axis=1)
        uv = b0[:, None] * VT[tidx[:, 0]] + b1[:, None] * VT[tidx[:, 1]] + b2[:, None] * VT[tidx[:, 2]]
        u = np.clip((uv[:, 0] % 1.0) * W, 0, W - 1).astype(np.int64)
        v = np.clip((1.0 - (uv[:, 1] % 1.0)) * H, 0, H - 1).astype(np.int64)
        col[ok] = img[v[ok], u[ok]].astype(np.float64) / 255.0
    data = np.zeros((len(tp), 14), dtype=np.float32)
    data[:, 0:3] = tp
    data[:, 3:6] = (col - 0.5) / SH_C0
    data[:, 6] = np.log(0.97 / 0.03)
    data[:, 7:10] = np.log(sz)[:, None]
    data[:, 10] = 1.0
    names = ["x","y","z","f_dc_0","f_dc_1","f_dc_2","opacity","scale_0","scale_1","scale_2","rot_0","rot_1","rot_2","rot_3"]
    hdr = "ply\nformat binary_little_endian 1.0\nelement vertex %d\n" % len(tp)
    hdr += "".join("property float %s\n" % nm for nm in names) + "end_header\n"
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(hdr.encode()); f.write(data.tobytes())
    print("  -> %s  splats=%d" % (out_path, len(tp)))

if __name__ == "__main__":
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 150000
    bake(sys.argv[1], sys.argv[2], n)


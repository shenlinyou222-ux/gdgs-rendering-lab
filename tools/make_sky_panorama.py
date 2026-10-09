# -*- coding: utf-8 -*-
"""用 NASA 公版星云照片拼接 360° 等距圆柱全景星空(8192x4096)。
产出: assets/textures/nasa_sky_panorama_8k.jpg (+preview)
可重复运行(固定种子);调 placements / BAND / 星点参数后重跑即可。"""
import numpy as np
from PIL import Image
import os

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, "..", "assets", "textures")
W, H = 8192, 4096
rng = np.random.default_rng(20260909)

canvas = np.zeros((H, W, 3), dtype=np.float32)

def load_src(name):
    img = Image.open(os.path.join(TEX, "nebula", name)).convert("RGB")
    return np.asarray(img, dtype=np.float32) / 255.0

SRC = {
    "P": load_src("PIA03096.jpg"),    # 创造之柱
    "O": load_src("PIA25434.jpg"),    # 猎户座红外
    "C": load_src("carina_nebula.jpg"),  # JWST 宇宙悬崖
}

def feather(h, w, frac=0.22):
    """边缘羽化遮罩:边缘 0,中心 1(正弦缓落)。"""
    fy = np.minimum(np.arange(h) / (h * frac), (h - 1 - np.arange(h)) / (h * frac)).clip(0, 1)
    fx = np.minimum(np.arange(w) / (w * frac), (w - 1 - np.arange(w)) / (w * frac)).clip(0, 1)
    return (np.sin(np.minimum(fy[:, None], fx[None, :]) * np.pi / 2) ** 0.8).astype(np.float32)

def add_patch(canvas, patch, x0, y0):
    """加法混合贴补丁,x 方向自动环绕。"""
    Hp, Wp = canvas.shape[:2]
    h, w = patch.shape[:2]
    x0 = int(x0) % Wp
    y0 = int(y0)
    def blit(cx0):
        sx0, sy0 = max(cx0, 0), max(y0, 0)
        sx1, sy1 = min(cx0 + w, Wp), min(y0 + h, Hp)
        if sx0 >= sx1 or sy0 >= sy1:
            return
        canvas[sy0:sy1, sx0:sx1] += patch[sy0 - y0:sy1 - y0, sx0 - cx0:sx1 - cx0]
    blit(x0)
    if x0 + w > Wp:
        blit(x0 - Wp)

def place(key, lon_deg, lat_deg, scale, flip, tint, gain, base_w=1500.0):
    img = SRC[key]
    if flip:
        img = img[:, ::-1]
    tw = int(base_w * scale)
    th = int(tw * img.shape[0] / img.shape[1])
    patch = np.asarray(Image.fromarray((img * 255).astype(np.uint8)).resize((tw, th), Image.LANCZOS),
                       dtype=np.float32) / 255.0
    patch = patch * feather(th, tw)[..., None] * np.asarray(tint, dtype=np.float32) * gain
    x = lon_deg / 360.0 * W - tw / 2
    y = H / 2 - lat_deg / 90.0 * (H / 2) - th / 2
    add_patch(canvas, patch, x, y)

# ---- 星云马赛克:14 块,沿银道带分布,镜像/染色制造多样性 ----
BAND = [0.62, 0.72, 0.88]
PLACE = [
    ("C",  10,   2, 1.15, False, (1.00, 0.92, 0.85), 0.95),
    ("P",  55,  -8, 0.90, True,  (0.85, 0.90, 1.00), 0.90),
    ("O", 100,  12, 1.00, False, (1.00, 1.00, 1.00), 0.90),
    ("C", 140, -15, 0.80, True,  (0.95, 0.90, 1.00), 0.80),
    ("P", 185,   5, 1.00, False, (1.00, 0.95, 0.90), 0.90),
    ("O", 225, -20, 0.85, True,  (0.90, 0.95, 1.00), 0.85),
    ("C", 265,  10, 1.05, False, (1.00, 0.90, 0.85), 0.90),
    ("P", 305,  18, 0.75, True,  (0.85, 0.92, 1.00), 0.80),
    ("O", 330,  25, 0.60, False, (0.95, 1.00, 1.00), 0.70),
    ("P",  75,  30, 0.55, False, (0.90, 0.95, 1.00), 0.65),
    ("C", 340, -28, 0.70, True,  (1.00, 0.88, 0.80), 0.75),
    ("O",  35, -30, 0.60, True,  (0.90, 0.90, 1.00), 0.60),
    ("P", 160,  32, 0.50, True,  (0.88, 0.94, 1.00), 0.60),
    ("C", 210,  28, 0.55, False, (1.00, 0.92, 0.85), 0.60),
    # 高纬补丁:保证抬头/低头也有内容
    ("O", 120,  42, 0.45, True,  (0.90, 0.95, 1.00), 0.55),
    ("C", 290, -40, 0.50, False, (1.00, 0.90, 0.85), 0.55),
    ("P",  15,  48, 0.40, False, (0.88, 0.94, 1.00), 0.50),
    ("O", 250,  40, 0.42, True,  (0.92, 0.90, 1.00), 0.50),
]
for p in PLACE:
    place(*p)

# ---- 银道带辉光:双层高斯带 + 沿经度的低频起伏(压暗,只做氛围) ----
ys = np.arange(H, dtype=np.float32)
band = np.exp(-0.5 * ((ys - H / 2) / 340.0) ** 2) * 0.30 + np.exp(-0.5 * ((ys - H / 2) / 110.0) ** 2) * 0.20
xs = np.arange(W, dtype=np.float32)
wobble = (0.72 + 0.28 * (0.5 * np.sin(xs / 8192 * 6.3 + 1.0)
                         + 0.3 * np.sin(xs / 8192 * 17.0 + 2.7)
                         + 0.2 * np.sin(xs / 8192 * 41.0 + 0.4))).astype(np.float32)
band_gain = (band[:, None] * wobble[None, :])[..., None]
canvas += band_gain * np.asarray(BAND, dtype=np.float32)

# ---- 程序化星点:三档,密度向银道带聚拢 ----
def gauss_dot(size, sigma_frac=0.30):
    r = np.arange(size, dtype=np.float32) - (size - 1) / 2
    d2 = r[:, None] ** 2 + r[None, :] ** 2
    return np.exp(-d2 / (2 * (size * sigma_frac) ** 2)).astype(np.float32)

PALETTE = [(1, 1, 1), (0.75, 0.82, 1.0), (1.0, 0.95, 0.80), (1.0, 0.78, 0.55), (1.0, 0.55, 0.45)]
WEIGHTS = [0.55, 0.20, 0.12, 0.08, 0.05]

def star_color():
    c = PALETTE[rng.choice(len(PALETTE), p=WEIGHTS)]
    return np.asarray(c, dtype=np.float32)

def lat_reject(n):
    """拒绝采样:银道带更密,但高纬也保留足够星点(修复'上下没星图')。"""
    out = []
    while len(out) < n:
        m = n - len(out)
        y = rng.uniform(0, H, m)
        keep = rng.uniform(0, 1, m) < (0.55 + 0.45 * np.exp(-((y - H / 2) / (H * 0.34)) ** 2))
        out.extend(y[keep].tolist())
    return np.array(out[:n])

def stamp(layer, y, x, img, gain):
    s = img.shape[0]
    y0, x0 = int(y - s / 2), int(x - s / 2)
    ys0, xs0 = max(y0, 0), max(x0, 0)
    ys1, xs1 = min(y0 + s, H), min(x0 + s, W)
    if ys0 >= ys1 or xs0 >= xs1:
        return
    layer[ys0:ys1, xs0:xs1] += img[ys0 - y0:ys1 - y0, xs0 - x0:xs1 - x0] * gain

def draw_stars():
    for count, size, gmin, gmax in [(22000, 1, 0.40, 0.95), (4000, 2, 0.55, 1.05), (320, 7, 0.85, 1.35)]:
        dot = gauss_dot(size) if size > 1 else np.ones((1, 1), dtype=np.float32)
        ys = lat_reject(count)
        xs = rng.uniform(0, W, count)
        for i in range(count):
            c = star_color()
            stamp(canvas, ys[i], xs[i], dot[..., None] * c, rng.uniform(gmin, gmax))

# ---- 全天空微星云雾:双倍频值噪声,确保任何方向都不是纯黑 ----
def value_noise(w, h, freq_x, freq_y, seed):
    r = np.random.default_rng(seed)
    g = r.uniform(0, 1, (freq_y, freq_x)).astype(np.float32)
    img = Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(img, dtype=np.float32) / 255.0

fog = value_noise(W, H, 24, 12, 7) * 0.65 + value_noise(W, H, 96, 48, 8) * 0.35
fog = (fog - fog.min()) / (fog.max() - fog.min())
canvas += (fog ** 2.2)[:, :, None] * np.asarray([0.45, 0.52, 0.70], dtype=np.float32) * 0.055

draw_stars()

draw_stars()

# ---- 收尾:截断、极区渐暗、微噪声防色带 ----
canvas = np.clip(canvas, 0.0, 1.0)
polar = np.minimum(1.0, np.minimum(np.arange(H), H - 1 - np.arange(H)) / (H * 0.05)).astype(np.float32)
canvas *= (0.94 + 0.06 * polar)[:, None, None]
canvas += rng.normal(0, 0.006, canvas.shape).astype(np.float32)
canvas = np.clip(canvas, 0.0, 1.0)

out8 = (canvas * 255 + 0.5).astype(np.uint8)
full = os.path.join(TEX, "nasa_sky_panorama_8k.jpg")
Image.fromarray(out8).save(full, quality=88)
Image.fromarray(out8).resize((2048, 1024), Image.LANCZOS).save(
    os.path.join(TEX, "nasa_sky_panorama_preview.jpg"), quality=90)
print("saved:", full, os.path.getsize(full) // 1024, "KB")

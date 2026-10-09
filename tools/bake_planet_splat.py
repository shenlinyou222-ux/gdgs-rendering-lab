#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""行星"烤死"烘焙器: 等距柱状贴图 + 半径 -> 表面高斯 PLY (太阳已烘进 SH band-0)

设计对应 research/16·太阳系战场 与 2026-09-10 会话结论:
  - 太阳固定在世界系 -> 行星光照整颗烤死(f_dc=颜色, f_rest=0), 运行时零着色成本;
  - 烘焙太阳轴 = 本地 -Z, Godot 侧 look_at(太阳) 对齐 —— 平移自由, 朝向锁定(1 自由度自转绕太阳轴);
  - 两级 LOD (L0 近密 / L1 远疏), 每级单文件, 运行时按角径切换(带迟滞);
  - 切向扁平圆盘高斯: scale=(s, s, 0.15s), 覆盖重叠 1.25x;
  - 输出标准 INRIA 3DGS binary PLY(小端 f32, scale=log / opacity=logit / color=0.5+C0*f_dc),
    省略 nx/ny/nz 与 f_rest_*(gdgs 解码器按缺省 0 处理)。

用法:
  python bake_planet_splat.py --tex assets/textures/8k_jupiter.jpg --radius 803 \
      --name jupiter --counts 160000,20000 --out-dir assets/splat_planets
"""
import argparse
import math
import os
import struct
import sys

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None  # 8k 贴图安全

SH_C0 = 0.28209479177387814
FLAT = 0.15          # 法向厚度 / 切向半径
OVERLAP = 1.25       # 切向覆盖重叠系数
AMBIENT = 0.05          # (弃用,保留兼容)
TERMINAL_SOFT = 0.18    # v6.12d: 以下三项 = planet_surface.gdshader 的运行时光照
DAY_POW = 1.25
DAY_GAIN = 1.08
NIGHT_AMB = 0.07
OPACITY = 0.98            # v6.12e: 概率非logit; 0.98×覆盖1.56 → 内部净不透明~99.9%(与网格无亮度差,维持原值)
SUN_LOCAL = np.array([0.0, 0.0, -1.0])  # 烘焙太阳方向(本地系), 与 Godot 侧 look_at 对齐


def fib_sphere(n: int):
    """Fibonacci 球面均匀采样 -> (极角 phi, 方位角 theta)"""
    i = np.arange(n, dtype=np.float64) + 0.5
    phi = np.arccos(1.0 - 2.0 * i / n)
    theta = math.pi * (1.0 + 5.0 ** 0.5) * i
    return phi, theta


def basis_and_quat(n):
    """法线 -> 右手切向基 [t1, t2, n] 与对应四元数 (w,x,y,z), 全程向量化"""
    n = n / np.linalg.norm(n, axis=1, keepdims=True)
    ref = np.zeros_like(n)
    ref[np.abs(n[:, 1]) < 0.9, 1] = 1.0          # 多数点用 UP
    ref[np.abs(n[:, 1]) >= 0.9, 0] = 1.0         # 极区附近用 X
    t1 = np.cross(ref, n)
    t1 /= np.linalg.norm(t1, axis=1, keepdims=True)
    t2 = np.cross(n, t1)
    # 旋转矩阵 m 的列 = [t1, t2, n], Shepperd 法求四元数
    m = np.stack([t1, t2, n], axis=1)            # (N,3,3), m[:, :, 0]=t1 ...
    tr = m[:, 0, 0] + m[:, 1, 1] + m[:, 2, 2]
    q = np.zeros((len(n), 4))
    # 分支向量化: 逐点按最大对角元选公式(三点分支, 简洁起见用循环掩码)
    for i in range(len(n)):
        mm = m[i]
        t = tr[i]
        if t > 0.0:
            s = math.sqrt(t + 1.0) * 2.0
            w = 0.25 * s
            x = (mm[2, 1] - mm[1, 2]) / s
            y = (mm[0, 2] - mm[2, 0]) / s
            z = (mm[1, 0] - mm[0, 1]) / s
        elif mm[0, 0] > mm[1, 1] and mm[0, 0] > mm[2, 2]:
            s = math.sqrt(1.0 + mm[0, 0] - mm[1, 1] - mm[2, 2]) * 2.0
            w = (mm[2, 1] - mm[1, 2]) / s
            x = 0.25 * s
            y = (mm[0, 1] + mm[1, 0]) / s
            z = (mm[0, 2] + mm[2, 0]) / s
        elif mm[1, 1] > mm[2, 2]:
            s = math.sqrt(1.0 + mm[1, 1] - mm[0, 0] - mm[2, 2]) * 2.0
            w = (mm[0, 2] - mm[2, 0]) / s
            x = (mm[0, 1] + mm[1, 0]) / s
            y = 0.25 * s
            z = (mm[1, 2] + mm[2, 1]) / s
        else:
            s = math.sqrt(1.0 + mm[2, 2] - mm[0, 0] - mm[1, 1]) * 2.0
            w = (mm[1, 0] - mm[0, 1]) / s
            x = (mm[0, 2] + mm[2, 0]) / s
            y = (mm[1, 2] + mm[2, 1]) / s
            z = 0.25 * s
        q[i] = (w, x, y, z)
    q /= np.linalg.norm(q, axis=1, keepdims=True)
    return n, t1, t2, q


def sample_equirect(img: np.ndarray, n: np.ndarray):
    """单位球法线 -> 等距柱状 UV 双线性采样. v=0 为图顶(北), u 沿赤道环绕"""
    h, w, _ = img.shape
    u = (np.arctan2(n[:, 0], n[:, 2]) / (2.0 * np.pi) + 0.5) * (w - 1)
    v = (0.5 - np.arcsin(np.clip(n[:, 1], -1.0, 1.0)) / np.pi) * (h - 1)
    x0 = np.floor(u).astype(np.int64)
    y0 = np.floor(v).astype(np.int64)
    fx = (u - x0)[:, None]
    fy = (v - y0)[:, None]
    x0w = np.mod(x0, w)
    x1w = np.mod(x0 + 1, w)
    y0c = np.clip(y0, 0, h - 1)
    y1c = np.clip(y0 + 1, 0, h - 1)
    c00 = img[y0c, x0w]
    c01 = img[y0c, x1w]
    c10 = img[y1c, x0w]
    c11 = img[y1c, x1w]
    return (c00 * (1 - fx) * (1 - fy) + c01 * fx * (1 - fy)
            + c10 * (1 - fx) * fy + c11 * fx * fy)


def bake_level(img: np.ndarray, radius: float, count: int, flat: bool = False):
    phi, theta = fib_sphere(count)
    ny = np.cos(phi)
    nx = np.sin(phi) * np.sin(theta)
    nz = -np.sin(phi) * np.cos(theta)            # -Z 半球即朝阳面(与 SUN_LOCAL 一致)
    normal, t1, t2, quat = basis_and_quat(np.stack([nx, ny, nz], axis=1))
    pos = normal * radius

    texel = sample_equirect(img, normal)
    if flat:
        # v6.14: 纯反照率(不烤太阳) —— 光照交给 gdgs relight(法线=位置归一化, 太阳=场景光源),
        # 行星可绕真实自转轴旋转且晨昏线始终正确; 与网格共用同一运行时光照模型, 切层零亮度差
        shade = np.ones(count, dtype=np.float64)
        color = np.clip(texel, 0.0, 1.0)
    else:
        ndl_raw = normal[:, 0] * SUN_LOCAL[0] + normal[:, 1] * SUN_LOCAL[1] + normal[:, 2] * SUN_LOCAL[2]
        # v6.12d: 与 planet_surface.gdshader 完全一致(wrap 0.18 / pow 1.25 / gain 1.08 / night 0.07)
        wrap = np.clip((ndl_raw + TERMINAL_SOFT) / (1.0 + TERMINAL_SOFT), 0.0, 1.0)
        shade = np.power(wrap, DAY_POW) * DAY_GAIN + NIGHT_AMB
        color = np.clip(texel * shade[:, None], 0.0, 1.0)
    f_dc = (color - 0.5) / SH_C0

    spacing = math.sqrt(4.0 * math.pi * radius * radius / count)
    s = spacing * OVERLAP
    scales = np.full((count, 3), math.log(s), dtype=np.float64)
    scales[:, 2] = math.log(s * FLAT)            # 法向轴压扁
    opacity = math.log(OPACITY / (1.0 - OPACITY))

    return pos, f_dc, opacity, scales, quat, shade


def write_ply(path: str, pos, f_dc, opacity, scales, quat):
    n = len(pos)
    data = np.zeros((n, 14), dtype=np.float32)
    data[:, 0:3] = pos
    data[:, 3:6] = f_dc
    data[:, 6] = opacity
    data[:, 7:10] = scales
    data[:, 10:14] = quat
    names = (["x", "y", "z"]
             + ["f_dc_0", "f_dc_1", "f_dc_2"]
             + ["opacity"]
             + ["scale_0", "scale_1", "scale_2"]
             + ["rot_0", "rot_1", "rot_2", "rot_3"])
    assert len(names) == data.shape[1], (len(names), data.shape[1])
    header_lines = ["ply", "format binary_little_endian 1.0", f"element vertex {n}"]
    header_lines += [f"property float {nm}" for nm in names]
    header_lines += ["end_header"]
    header = ("\n".join(header_lines) + "\n").encode("ascii")
    with open(path, "wb") as f:
        f.write(header)
        f.write(data.tobytes())
    return os.path.getsize(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tex", required=True)
    ap.add_argument("--radius", type=float, required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--counts", default="160000,20000", help="逗号分隔, 从细到粗")
    ap.add_argument("--out-dir", default="assets/splat_planets")
    ap.add_argument("--flat", action="store_true",
                    help="v6.14: 纯反照率烘焙(不烤太阳), 光照交给 gdgs relight 运行时计算")
    args = ap.parse_args()

    img = np.asarray(Image.open(args.tex).convert("RGB"), dtype=np.float32) / 255.0
    print(f"[bake] tex={args.tex} {img.shape[1]}x{img.shape[0]} radius={args.radius}m flat={args.flat}")
    os.makedirs(args.out_dir, exist_ok=True)

    lit_ref = None
    for idx, cnt in enumerate(args.counts.split(",")):
        cnt = int(cnt.strip())
        pos, f_dc, opacity, scales, quat, shade = bake_level(img, args.radius, cnt, args.flat)
        out = os.path.join(args.out_dir, f"{args.name}_l{idx}.ply")
        size = write_ply(out, pos, f_dc, opacity, scales, quat)
        print(f"[bake] L{idx}: {cnt} pts spacing="
              f"{math.sqrt(4*math.pi*args.radius**2/cnt):.2f}m "
              f"lit_frac={float(np.mean(shade > 0.05)):.3f} "
              f"mean_rgb={f_dc[:, :].mean():.3f}(f_dc) -> {out} ({size/1e6:.1f} MB)")


if __name__ == "__main__":
    sys.exit(main())

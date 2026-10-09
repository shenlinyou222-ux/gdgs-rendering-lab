# -*- coding: utf-8 -*-
# HY 多视图还原器: front/left/back(可选right) 视图 -> Hunyuan3D-2mv-turbo -> GLB mesh
# 用法:
#   python tools/hy3d_mv_recon.py --front views/front.png --left views/left.png --back views/back.png --out assets/whale/hy_whale.glb
# 视图规格(重要):
#   - 同一缩放/同一视线高度, 正交感(长焦或正交投影), 物体居中轮廓完整
#   - 纯白或透明背景; RGBA 最佳(RGB 自动走 rembg 抠底, 需 pip install rembg)
#   - 每张 512~1024px; 各视图间形状必须一致(MV 一致性由输入决定)
#   - 只需剪影正确, 无需上色(上色走我们的程序化涂装/面绑定采样器)
import argparse, os, sys

def fail(msg, hint=""):
    print("[HY-MV] FAIL:", msg)
    if hint:
        print("  hint:", hint)
    sys.exit(1)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--front", required=True)
    ap.add_argument("--left", default=None)
    ap.add_argument("--back", default=None)
    ap.add_argument("--right", default=None)
    ap.add_argument("--out", default="hy_out.glb")
    ap.add_argument("--seed", type=int, default=20260912)
    ap.add_argument("--steps", type=int, default=5, help="turbo=5; 普通版用 50")
    ap.add_argument("--octree", type=int, default=380, help="体素分辨率, 越大越细越慢")
    args = ap.parse_args()

    # 依赖检查(缺什么提示装什么)
    missing = []
    for m in ("torch", "PIL", "trimesh", "hy3dgen"):
        try:
            __import__(m)
        except ImportError:
            missing.append(m)
    if missing:
        fail("缺依赖: " + ",".join(missing),
             "pip install hy3dgen trimesh  (hy3dgen 来自 Tencent-Hunyuan/Hunyuan3D-2 仓库)")

    for k, p in [("front", args.front), ("left", args.left), ("back", args.back), ("right", args.right)]:
        if p and not os.path.isfile(p):
            fail("视图不存在: %s (%s)" % (k, p))
    if not any([args.left, args.back, args.right]):
        print("[HY-MV] 警告: 只有 front 单视图, 建议至少加 left/back 发挥 MV 优势")

    import torch
    from PIL import Image
    if not torch.cuda.is_available():
        fail("CUDA 不可用", "RTX 5060 需要 cu128+ 版 torch (当前环境曾验证 2.14.0+cu130 OK)")
    print("[HY-MV] GPU:", torch.cuda.get_device_name(0))

    # 载入视图(统一 RGBA)
    from hy3dgen.rembg import BackgroundRemover
    images = {}
    for k, p in [("front", args.front), ("left", args.left), ("back", args.back), ("right", args.right)]:
        if not p:
            continue
        im = Image.open(p).convert("RGBA")
        # 判定是否需要抠底: 四角全透明则视为已抠底
        w, h = im.size
        corners = [im.getpixel(a) for a in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]]
        if all(c[3] > 250 for c in corners):
            print("[HY-MV] %s: 背景不透明 -> rembg 抠底" % k)
            im = BackgroundRemover()(im)
        images[k] = im
    print("[HY-MV] 视图:", {k: v.size for k, v in images.items()})

    from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline
    pipe = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(
        "tencent/Hunyuan3D-2mv", subfolder="hunyuan3d-dit-v2-mv-turbo", variant="fp16")
    pipe.enable_flashvdm()

    mesh = pipe(image=images, num_inference_steps=args.steps, octree_resolution=args.octree,
                num_chunks=20000, generator=torch.manual_seed(args.seed), output_type="trimesh")[0]

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    mesh.export(args.out)
    lo, hi = mesh.bounds
    print("[HY-MV] DONE %s" % args.out)
    print("  三角面: %d | AABB: (%.1f, %.1f, %.1f)" % (len(mesh.faces), hi[0]-lo[0], hi[1]-lo[1], hi[2]-lo[2]))
    print("  显存峰值: %.1f GB / 8.0 GB" % (torch.cuda.max_memory_allocated() / 1e9))

if __name__ == "__main__":
    main()


# upscale_texture.py - Real-ESRGAN x4 (torch RRDBNet, tiled)
import os, numpy as np, torch, torch.nn as nn, torch.nn.functional as F
from PIL import Image

class ResidualDenseBlock(nn.Module):
    def __init__(self, nf=64, gc=32):
        super().__init__()
        self.conv1 = nn.Conv2d(nf, gc, 3, 1, 1)
        self.conv2 = nn.Conv2d(nf + gc, gc, 3, 1, 1)
        self.conv3 = nn.Conv2d(nf + 2 * gc, gc, 3, 1, 1)
        self.conv4 = nn.Conv2d(nf + 3 * gc, gc, 3, 1, 1)
        self.conv5 = nn.Conv2d(nf + 4 * gc, nf, 3, 1, 1)
        self.lrelu = nn.LeakyReLU(0.2, inplace=True)
    def forward(self, x):
        x1 = self.lrelu(self.conv1(x))
        x2 = self.lrelu(self.conv2(torch.cat((x, x1), 1)))
        x3 = self.lrelu(self.conv3(torch.cat((x, x1, x2), 1)))
        x4 = self.lrelu(self.conv4(torch.cat((x, x1, x2, x3), 1)))
        x5 = self.conv5(torch.cat((x, x1, x2, x3, x4), 1))
        return x5 * 0.2 + x

class RRDB(nn.Module):
    def __init__(self, nf, gc=32):
        super().__init__()
        self.RDB1 = ResidualDenseBlock(nf, gc)
        self.RDB2 = ResidualDenseBlock(nf, gc)
        self.RDB3 = ResidualDenseBlock(nf, gc)
    def forward(self, x):
        out = self.RDB1(x)
        out = self.RDB2(out)
        out = self.RDB3(out)
        return out * 0.2 + x

class RRDBNet(nn.Module):
    def __init__(self, in_nc=3, out_nc=3, nf=64, nb=23, gc=32):
        super().__init__()
        self.conv_first = nn.Conv2d(in_nc, nf, 3, 1, 1)
        self.RRDB_trunk = nn.Sequential(*[RRDB(nf, gc) for _ in range(nb)])
        self.trunk_conv = nn.Conv2d(nf, nf, 3, 1, 1)
        self.upconv1 = nn.Conv2d(nf, nf, 3, 1, 1)
        self.upconv2 = nn.Conv2d(nf, nf, 3, 1, 1)
        self.HRconv = nn.Conv2d(nf, nf, 3, 1, 1)
        self.conv_last = nn.Conv2d(nf, out_nc, 3, 1, 1)
        self.lrelu = nn.LeakyReLU(0.2, inplace=True)
    def forward(self, x):
        fea = self.conv_first(x)
        trunk = self.trunk_conv(self.RRDB_trunk(fea))
        fea = fea + trunk
        fea = self.lrelu(self.upconv1(F.interpolate(fea, scale_factor=2, mode="nearest")))
        fea = self.lrelu(self.upconv2(F.interpolate(fea, scale_factor=2, mode="nearest")))
        return self.conv_last(self.lrelu(self.HRconv(fea)))

BASE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(BASE, "..", "assets", "goldfish_src")
IN_T = os.path.join(SRC, "texture_pbr_20250901.png")
OUT_T = os.path.join(SRC, "texture_pbr_4x.png")
W_PTH = os.path.join(SRC, "RealESRGAN_x4plus.pth")
TILE = 384
PAD = 16

model = RRDBNet()
sd = torch.load(W_PTH, map_location="cpu", weights_only=True)["params_ema"]
remap = {}
for k in sd:
    nk = k
    if k.startswith("body."):
        parts = k.split(".")
        parts[0], parts[1], parts[2] = "RRDB_trunk", parts[1], "RDB" + parts[2][3:]
        nk = ".".join(parts)
    nk = (nk.replace("conv_body", "trunk_conv").replace("conv_up1", "upconv1")
             .replace("conv_up2", "upconv2").replace("conv_hr", "HRconv"))
    remap[nk] = sd[k]
sd = remap
model.load_state_dict(sd, strict=True)
model.eval().cuda()
torch.set_grad_enabled(False)
img = Image.open(IN_T).convert("RGB")
W, H = img.size
print("input:", img.size)
arr = np.asarray(img, dtype=np.float32) / 255.0
out = np.zeros((H * 4, W * 4, 3), dtype=np.float32)
cnt = 0
total = ((H + TILE - 1) // TILE) * ((W + TILE - 1) // TILE)
for y0 in range(0, H, TILE):
    for x0 in range(0, W, TILE):
        y1, x1 = min(y0 + TILE, H), min(x0 + TILE, W)
        yp0, xp0 = max(y0 - PAD, 0), max(x0 - PAD, 0)
        yp1, xp1 = min(y1 + PAD, H), min(x1 + PAD, W)
        tile = torch.from_numpy(arr[yp0:yp1, xp0:xp1]).permute(2, 0, 1)[None].cuda()
        up = model(tile)[0].permute(1, 2, 0).clamp_(0, 1).cpu().numpy()
        oy0, ox0 = (y0 - yp0) * 4, (x0 - xp0) * 4
        out[y0*4:y1*4, x0*4:x1*4] = up[oy0:oy0+(y1-y0)*4, ox0:ox0+(x1-x0)*4]
        cnt += 1
        if cnt % 8 == 0 or cnt == total:
            print("tiles %d/%d" % (cnt, total), flush=True)
Image.fromarray((out * 255 + 0.5).astype(np.uint8)).save(OUT_T)
print("saved", OUT_T, (W * 4, H * 4))


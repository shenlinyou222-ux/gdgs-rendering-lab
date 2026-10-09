#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen_fx_splats.py -- procedural Gaussian-splat FX frame sequences for gdgs (Godot).

Generates per-frame binary PLY "gaussian splat" animations in the spirit of
SplatVFX / PhysGaussian-style particle dynamics: each splat is a particle with
an initial radial velocity field v0 = dir * (speed / (1 + d*falloff)) + jitter,
integrated per frame with pos += v*dt, v *= (1 - drag*dt), opacity *= exp(-fade*t),
scale *= (1 + expand*dt). Particle identity is continuous across frames (the same
batch of particles is integrated over time, never re-sampled per frame).

PLY layout (byte-identical convention to jet_gs_pipeline/P2_splats.ply):
    binary_little_endian, 17 x float32 per vertex:
    x y z nx ny nz f_dc_0 f_dc_1 f_dc_2 opacity scale_0 scale_1 scale_2
    rot_0 rot_1 rot_2 rot_3
Conventions:
    color c in [0,1]      -> f_dc = (c - 0.5) / SH_C0
    opacity a in (0,1)    -> logit(a) = ln(a / (1 - a))
    scale (meters)        -> ln(scale)
    rot                   -> unit quaternion (w, x, y, z); local +Z is the
                             splat normal (the scale_2 axis), so nx,ny,nz is
                             the world-space local +Z axis of the rotation.

Outputs (26 files):
    assets/fx/muzzle_00..05.ply      6 frames  ~400 splats   gun muzzle flash
    assets/fx/blast_00..11.ply       12 frames ~1400 splats  explosion fireball
    assets/fx/laser_hit_00..07.ply    8 frames ~700 splats   laser impact sparks
    assets/fx/charge_00..05.ply      6 frames ~520 splats   laser charge swirl (v0.9)

Run:  python tools/gen_fx_splats.py
"""

import os
import numpy as np

# ---------------------------------------------------------------- constants
SH_C0 = 0.28209479177387814          # 1/(2*sqrt(pi/4)); SH DC basis coefficient
STRIDE = 68                          # 17 * 4 bytes
FIELD_NAMES = ["x", "y", "z", "nx", "ny", "nz",
               "f_dc_0", "f_dc_1", "f_dc_2", "opacity",
               "scale_0", "scale_1", "scale_2",
               "rot_0", "rot_1", "rot_2", "rot_3"]
PLY_DTYPE = np.dtype([(n, "<f4") for n in FIELD_NAMES])

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "fx")

SEED = 20260910

# ---------------------------------------------------------------- conversions
def logit(a):
    """alpha in (0,1) -> logit; clamped away from the singularities."""
    a = np.clip(a, 0.004, 0.996)
    return np.log(a / (1.0 - a))

def sigmoid_logit(o):
    return 1.0 / (1.0 + np.exp(-o))

def colors_to_f_dc(col):
    return (np.clip(col, 0.0, 1.0) - 0.5) / SH_C0

# ---------------------------------------------------------------- quaternions
def random_quats(n, rng):
    """Uniform random unit quaternions, (n,4) as (w,x,y,z) -- Shoemake method."""
    u1, u2, u3 = rng.random(n), rng.random(n), rng.random(n)
    s1, s2 = np.sqrt(1.0 - u1), np.sqrt(u1)
    return np.stack([s1 * np.cos(2 * np.pi * u2), s1 * np.sin(2 * np.pi * u2),
                     s2 * np.cos(2 * np.pi * u3), s2 * np.sin(2 * np.pi * u3)], axis=1)

def quat_to_mat(q):
    """(n,4) (w,x,y,z) -> (n,3,3) rotation matrix; columns = local axes in world."""
    w, x, y, z = q[:, 0], q[:, 1], q[:, 2], q[:, 3]
    m = np.empty((q.shape[0], 3, 3))
    m[:, 0, 0] = 1 - 2 * (y * y + z * z); m[:, 0, 1] = 2 * (x * y - w * z); m[:, 0, 2] = 2 * (x * z + w * y)
    m[:, 1, 0] = 2 * (x * y + w * z); m[:, 1, 1] = 1 - 2 * (x * x + z * z); m[:, 1, 2] = 2 * (y * z - w * x)
    m[:, 2, 0] = 2 * (x * z - w * y); m[:, 2, 1] = 2 * (y * z + w * x); m[:, 2, 2] = 1 - 2 * (x * x + y * y)
    return m

def mat_to_quat(m):
    """(n,3,3) rotation matrix -> (n,4) unit quaternion (w,x,y,z)."""
    eps = 1e-9
    tr = m[:, 0, 0] + m[:, 1, 1] + m[:, 2, 2]
    s = 2.0 * np.sqrt(np.maximum(tr + 1.0, eps))
    b0 = np.stack([0.25 * s, (m[:, 2, 1] - m[:, 1, 2]) / s,
                   (m[:, 0, 2] - m[:, 2, 0]) / s, (m[:, 1, 0] - m[:, 0, 1]) / s], axis=1)
    s = 2.0 * np.sqrt(np.maximum(1.0 + m[:, 0, 0] - m[:, 1, 1] - m[:, 2, 2], eps))
    b1 = np.stack([(m[:, 2, 1] - m[:, 1, 2]) / s, 0.25 * s,
                   (m[:, 0, 1] + m[:, 1, 0]) / s, (m[:, 0, 2] + m[:, 2, 0]) / s], axis=1)
    s = 2.0 * np.sqrt(np.maximum(1.0 - m[:, 0, 0] + m[:, 1, 1] - m[:, 2, 2], eps))
    b2 = np.stack([(m[:, 0, 2] - m[:, 2, 0]) / s, (m[:, 0, 1] + m[:, 1, 0]) / s,
                   0.25 * s, (m[:, 1, 2] + m[:, 2, 1]) / s], axis=1)
    s = 2.0 * np.sqrt(np.maximum(1.0 - m[:, 0, 0] - m[:, 1, 1] + m[:, 2, 2], eps))
    b3 = np.stack([(m[:, 1, 0] - m[:, 0, 1]) / s, (m[:, 0, 2] + m[:, 2, 0]) / s,
                   (m[:, 1, 2] + m[:, 2, 1]) / s, 0.25 * s], axis=1)
    use0 = tr > 0.0
    use1 = (~use0) & (m[:, 0, 0] > m[:, 1, 1]) & (m[:, 0, 0] > m[:, 2, 2])
    use2 = (~use0) & (~use1) & (m[:, 1, 1] > m[:, 2, 2])
    use3 = (~use0) & (~use1) & (~use2)
    q = (b0 * use0[:, None] + b1 * use1[:, None] + b2 * use2[:, None] + b3 * use3[:, None])
    return q / np.linalg.norm(q, axis=1, keepdims=True)

def elongated_quats(dirs):
    """Quaternions orienting a 'needle' splat: local +X (scale_0) along dirs
    (the long tangential axis), local +Z (scale_2, the normal axis) perpendicular
    and thin -- i.e. normal axis small, tangential axis big, pointing radially."""
    n = dirs.shape[0]
    ax = dirs / np.maximum(np.linalg.norm(dirs, axis=1, keepdims=True), 1e-12)
    helper = np.zeros((n, 3))
    helper[:, 1] = 1.0
    flip = np.abs(ax[:, 1]) > 0.9          # axis nearly parallel to +Y
    helper[flip, 0], helper[flip, 1] = 1.0, 0.0
    yv = np.cross(helper, ax)
    yv /= np.maximum(np.linalg.norm(yv, axis=1, keepdims=True), 1e-12)
    zv = np.cross(ax, yv)
    return mat_to_quat(np.stack([ax, yv, zv], axis=2))

# ---------------------------------------------------------------- PLY I/O
def write_ply(path, pos, col, alpha, scale_m, quat):
    """Write one binary PLY frame. pos(n,3) m, col(n,3) [0,1], alpha(n,) [0,1],
    scale_m(n,3) meters, quat(n,4) unit (w,x,y,z)."""
    n = pos.shape[0]
    normals = quat_to_mat(quat)[:, :, 2]           # local +Z = splat normal
    arr = np.zeros(n, dtype=PLY_DTYPE)
    arr["x"], arr["y"], arr["z"] = pos[:, 0], pos[:, 1], pos[:, 2]
    arr["nx"], arr["ny"], arr["nz"] = normals[:, 0], normals[:, 1], normals[:, 2]
    fdc = colors_to_f_dc(col)
    arr["f_dc_0"], arr["f_dc_1"], arr["f_dc_2"] = fdc[:, 0], fdc[:, 1], fdc[:, 2]
    arr["opacity"] = logit(alpha)
    logs = np.log(np.clip(scale_m, 1e-5, None))
    arr["scale_0"], arr["scale_1"], arr["scale_2"] = logs[:, 0], logs[:, 1], logs[:, 2]
    arr["rot_0"], arr["rot_1"], arr["rot_2"], arr["rot_3"] = quat[:, 0], quat[:, 1], quat[:, 2], quat[:, 3]
    props = "".join("property float %s\n" % nm for nm in FIELD_NAMES)
    header = ("ply\n"
              "format binary_little_endian 1.0\n"
              "comment gdgs fx frame %s\n"
              "element vertex %d\n" % (os.path.basename(path), n) + props + "end_header\n").encode("ascii")
    with open(path, "wb") as f:
        f.write(header)
        f.write(arr.tobytes())
    return n

def read_ply(path):
    """Parse a binary PLY exactly the way write_ply produced it."""
    with open(path, "rb") as f:
        raw = f.read()
    end = raw.find(b"end_header\n")
    if end < 0:
        raise ValueError("%s: no end_header" % path)
    hdr_len = end + len(b"end_header\n")
    fmt, nverts, props = None, None, []
    for ln in raw[:end].decode("ascii").splitlines():
        if ln.startswith("format "):
            fmt = ln
        elif ln.startswith("element vertex "):
            nverts = int(ln.split()[-1])
        elif ln.startswith("property float "):
            props.append(ln.split()[-1])
    arr = np.frombuffer(raw, dtype=PLY_DTYPE, count=nverts, offset=hdr_len)
    return arr, fmt, nverts, hdr_len, len(raw)

# ---------------------------------------------------------------- simulation
class Pop(object):
    """One particle population with continuous identity across frames."""
    def __init__(self, pos, vel, alpha0, scale0, quat, color_fn,
                 drag=0.0, fade=0.0, expand=0.0):
        self.pos, self.vel = pos, vel
        self.alpha, self.scale = alpha0, scale0
        self.quat = quat
        self.color_fn = color_fn
        self.drag, self.fade, self.expand = drag, fade, expand

    def snapshot(self, t, total):
        return dict(pos=self.pos, col=self.color_fn(t / max(total, 1e-9)),
                    alpha=self.alpha, scale=self.scale, quat=self.quat)

    def step(self, dt):
        self.pos = self.pos + self.vel * dt
        self.vel = self.vel * (1.0 - self.drag * dt)
        self.alpha = np.clip(self.alpha * np.exp(-self.fade * dt), 0.004, 0.999)
        self.scale = self.scale * (1.0 + self.expand * dt)

def write_frames(out_dir, prefix, frames, pops, dt):
    os.makedirs(out_dir, exist_ok=True)
    total = (frames - 1) * dt
    n_written = []
    for f in range(frames):
        t = f * dt
        snaps = [p.snapshot(t, total) for p in pops]
        pos = np.concatenate([s["pos"] for s in snaps])
        col = np.clip(np.concatenate([s["col"] for s in snaps]), 0.0, 1.0)
        alpha = np.clip(np.concatenate([s["alpha"] for s in snaps]), 0.004, 0.999)
        scale = np.clip(np.concatenate([s["scale"] for s in snaps]), 1e-5, None)
        quat = np.concatenate([s["quat"] for s in snaps])
        path = os.path.join(out_dir, "%s_%02d.ply" % (prefix, f))
        n_written.append(write_ply(path, pos, col, alpha, scale, quat))
        if f < frames - 1:
            for p in pops:
                p.step(dt)
    return n_written

def isotropic_dirs(n, rng):
    d = rng.normal(size=(n, 3))
    return d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-12)

def lerp(a, b, u):
    u = np.clip(u, 0.0, 1.0)
    return a * (1.0 - u) + b * u

# ---------------------------------------------------------------- 1. muzzle
def gen_muzzle(out_dir, rng):
    frames, fps = 6, 30
    dt = 1.0 / fps
    # -- bright warm-white core (near-spherical splats) --------------------
    n_core = 300
    pos = rng.normal(0.0, 0.030, (n_core, 3))
    d = pos / np.maximum(np.linalg.norm(pos, axis=1, keepdims=True), 1e-9)
    vel = d * rng.uniform(0.5, 1.4, (n_core, 1)) + rng.normal(0.0, 0.25, (n_core, 3))
    warm = np.array([1.00, 0.965, 0.86]); orange = np.array([1.00, 0.60, 0.22])
    mix = rng.random((n_core, 1))
    col0 = warm[None, :] * (1 - mix) + orange[None, :] * mix
    alpha0 = rng.uniform(0.85, 0.99, n_core)
    scale0 = rng.uniform(0.018, 0.042, (n_core, 3)) * rng.uniform(0.85, 1.15, (n_core, 3))
    orange_t = np.tile(orange, (n_core, 1))
    core = Pop(pos, vel, alpha0, scale0, random_quats(n_core, rng),
               color_fn=lambda tn: lerp(col0, orange_t, 0.5 * tn),
               drag=1.2, fade=12.0, expand=1.8)
    # -- radial streaks: thin elongated splats pointing outward ------------
    n_dirs, per = 20, 5
    dirs = isotropic_dirs(n_dirs, rng)
    s_pos, s_vel, s_col, s_al, s_sc = [], [], [], [], []
    for i in range(n_dirs):
        r0 = rng.uniform(0.05, 0.15, per)
        jitter = rng.normal(0.0, 0.012, (per, 3))
        s_pos.append(dirs[i][None, :] * r0[:, None] + jitter)
        s_vel.append(dirs[i][None, :] * rng.uniform(0.6, 1.0, (per, 1)))
        s_col.append(np.tile(np.array([1.0, 0.72, 0.30]), (per, 1)))
        s_al.append(rng.uniform(0.80, 0.95, per))
        long_ax = rng.uniform(0.06, 0.11, per)
        thin = rng.uniform(0.010, 0.016, per)
        s_sc.append(np.stack([long_ax, thin, thin * 0.8], axis=1))
    n_streak = n_dirs * per
    s_pos, s_vel = np.concatenate(s_pos), np.concatenate(s_vel)
    s_col0, s_al0, s_sc0 = np.concatenate(s_col), np.concatenate(s_al), np.concatenate(s_sc)
    s_end = np.tile(np.array([0.80, 0.30, 0.07]), (n_streak, 1))
    streak = Pop(s_pos, s_vel, s_al0, s_sc0,
                 elongated_quats(s_vel),
                 color_fn=lambda tn: lerp(s_col0, s_end, tn),
                 drag=1.5, fade=16.0, expand=0.6)
    n_written = write_frames(out_dir, "muzzle", frames, [core, streak], dt)
    return dict(name="muzzle", frames=frames, fps=fps, dt=dt,
                n_per_frame=n_written[0],
                v0="core 0.5-1.4 m/s outward; streaks 0.6-1.0 m/s",
                fade="core 12/s, streaks 16/s (exp)", expand="core 1.8/s, streaks 0.6/s",
                drag="core 1.2/s, streaks 1.5/s", scale="0.02-0.11 m", size_note="~0.4 m")

# ---------------------------------------------------------------- 2. blast
FIRE_STOPS = [(0.00, (1.00, 1.00, 0.97)),
              (0.18, (1.00, 0.90, 0.50)),
              (0.42, (1.00, 0.50, 0.12)),
              (0.68, (0.55, 0.12, 0.04)),
              (1.00, (0.24, 0.22, 0.21))]

def palette(tn, stops):
    """tn: (n,) normalized time -> (n,3) colors, piecewise-linear on stops."""
    tn = np.clip(tn, 0.0, 1.0)
    ts = np.array([s[0] for s in stops])
    cs = np.array([s[1] for s in stops])
    idx = np.clip(np.searchsorted(ts, tn, side="right") - 1, 0, len(ts) - 2)
    u = ((tn - ts[idx]) / (ts[idx + 1] - ts[idx]))[:, None]
    return cs[idx] * (1.0 - u) + cs[idx + 1] * u

def gen_blast(out_dir, rng):
    frames, fps = 12, 25
    dt = 1.0 / fps
    R0, SPEED, FALLOFF = 0.5, 34.0, 1.2
    pops = []

    def fire_color(heat, bright, rate=1.0):
        """white -> yellow -> orange -> dark red -> gray smoke, per-particle heat offset."""
        def fn(tn):
            tt = np.clip(tn * rate + 0.20 * (1.0 - heat), 0.0, 1.0)
            return np.clip(palette(tt, FIRE_STOPS) * bright[:, None], 0.0, 1.0)
        return fn

    # shell: 800 splats, radius 0.5 m -> ~7 m
    n_shell = 800
    u = rng.uniform(0.72, 1.0, n_shell) * R0
    dirs = isotropic_dirs(n_shell, rng)
    v0 = SPEED / (1.0 + u * FALLOFF)
    heat_shell = 1.0 - u / R0
    shell = Pop(dirs * u[:, None],
                dirs * v0[:, None] + rng.normal(0.0, 1.2, (n_shell, 3)),
                rng.uniform(0.88, 1.0, n_shell),
                rng.uniform(0.10, 0.22, (n_shell, 3)) * rng.uniform(0.85, 1.2, (n_shell, 3)),
                random_quats(n_shell, rng),
                color_fn=fire_color(heat_shell, rng.uniform(0.88, 1.0, n_shell)),
                drag=1.9, fade=2.2 + 1.6 * (1.0 - heat_shell), expand=2.2)
    # hot inner core: 350 splats, stays whiter longer
    n_core = 350
    uc = R0 * rng.random(n_core) ** 1.8
    dirsc = isotropic_dirs(n_core, rng)
    vc = 0.55 * SPEED / (1.0 + uc * FALLOFF)
    core = Pop(dirsc * uc[:, None],
               dirsc * vc[:, None] + rng.normal(0.0, 0.8, (n_core, 3)),
               rng.uniform(0.95, 1.0, n_core),
               rng.uniform(0.08, 0.18, (n_core, 3)) * rng.uniform(0.85, 1.2, (n_core, 3)),
               random_quats(n_core, rng),
               color_fn=fire_color(np.ones(n_core), rng.uniform(0.92, 1.0, n_core), rate=0.85),
               drag=1.9, fade=2.0, expand=1.8)
    # outer dark smoke: 250 big, dim gray puffs, slower
    n_smoke = 250
    us = rng.uniform(0.55, 0.75, n_smoke)
    dirss = isotropic_dirs(n_smoke, rng)
    vs = 10.0 / (1.0 + us * FALLOFF)
    smoke_rate = rng.uniform(0.8, 1.3, n_smoke)     # darkening speed
    lit = np.array([0.36, 0.33, 0.30]); dark = np.array([0.13, 0.12, 0.12])
    def smoke_fn(tn):
        u_ = np.clip(tn * smoke_rate, 0.0, 1.0)
        return lerp(lit[None, :], dark[None, :], u_[:, None])
    smoke = Pop(dirss * us[:, None],
                dirss * vs[:, None] + rng.normal(0.0, 2.0, (n_smoke, 3)),
                rng.uniform(0.30, 0.48, n_smoke),
                rng.uniform(0.24, 0.48, (n_smoke, 3)) * rng.uniform(0.85, 1.2, (n_smoke, 3)),
                random_quats(n_smoke, rng),
                color_fn=smoke_fn,
                drag=2.4, fade=1.2, expand=2.8)

    pops = [shell, core, smoke]
    n_written = write_frames(out_dir, "blast", frames, pops, dt)
    return dict(name="blast", frames=frames, fps=fps, dt=dt,
                n_per_frame=n_written[0],
                v0="v0=dir*(34/(1+1.2*d)) m/s + jitter (shell), 0.55x (core), 10/(1+1.2d) (smoke)",
                drag="1.9/s fire, 2.4/s smoke", fade="2.0-3.8/s fire (exp), 1.2/s smoke",
                expand="2.2/s fire, 2.8/s smoke",
                scale="0.08-0.48 m", size_note="R0=0.5 m -> ~7 m over %.2f s" % ((frames - 1) * dt))

# ---------------------------------------------------------------- 3. laser_hit
def gen_laser_hit(out_dir, rng):
    frames, fps = 8, 30
    dt = 1.0 / fps
    # -- cyan-white hot core ------------------------------------------------
    n_core = 430
    pos = rng.normal(0.0, 0.060, (n_core, 3))
    pos = np.clip(pos, -0.14, 0.14)
    d = pos / np.maximum(np.linalg.norm(pos, axis=1, keepdims=True), 1e-9)
    vel = d * rng.uniform(0.4, 1.0, (n_core, 1))
    cyanw = np.array([0.82, 0.96, 1.00]); blue = np.array([0.45, 0.65, 1.00])
    mix = rng.random((n_core, 1)) * 0.6
    col0 = cyanw[None, :] * (1 - mix) + blue[None, :] * mix
    blue_t = np.tile(blue, (n_core, 1))
    core = Pop(pos, vel, rng.uniform(0.90, 1.0, n_core),
               rng.uniform(0.016, 0.038, (n_core, 3)) * rng.uniform(0.9, 1.1, (n_core, 3)),
               random_quats(n_core, rng),
               color_fn=lambda tn: lerp(col0, blue_t, tn),
               drag=1.5, fade=15.0, expand=1.5)
    # -- radial spikes: 10 directions, elongated splats along the ray -------
    n_dirs, per = 10, 27
    dv = rng.normal(size=(n_dirs, 3))
    dv[:, 2] *= 0.55                     # flatten slightly toward the plane
    dirs = dv / np.linalg.norm(dv, axis=1, keepdims=True)
    s_pos, s_vel, s_al, s_sc = [], [], [], []
    for i in range(n_dirs):
        r0 = 0.06 + 0.36 * rng.random(per) ** 0.8
        e1 = np.cross(dirs[i], [0.0, 0.0, 1.0] if abs(dirs[i][2]) < 0.9 else [1.0, 0.0, 0.0])
        e1 /= np.linalg.norm(e1)
        e2 = np.cross(dirs[i], e1)
        off = e1[None, :] * rng.normal(0, 0.018, (per, 1)) + e2[None, :] * rng.normal(0, 0.018, (per, 1))
        s_pos.append(dirs[i][None, :] * r0[:, None] + off)
        s_vel.append(dirs[i][None, :] * (0.30 + 1.00 * (r0 / 0.42))[:, None])
        s_al.append(rng.uniform(0.78, 0.92, per))
        long_ax = rng.uniform(0.09, 0.15, per)
        thin = rng.uniform(0.011, 0.018, per)
        s_sc.append(np.stack([long_ax, thin, thin * 0.8], axis=1))
    n_spk = n_dirs * per
    s_pos, s_vel = np.concatenate(s_pos), np.concatenate(s_vel)
    s_al0, s_sc0 = np.concatenate(s_al), np.concatenate(s_sc)
    spk0 = np.tile(np.array([0.72, 0.90, 1.00]), (n_spk, 1))
    spk1 = np.tile(np.array([0.30, 0.52, 1.00]), (n_spk, 1))
    spikes = Pop(s_pos, s_vel, s_al0, s_sc0,
                 elongated_quats(s_vel),
                 color_fn=lambda tn: lerp(spk0, spk1, tn),
                 drag=1.2, fade=12.0, expand=0.4)
    n_written = write_frames(out_dir, "laser_hit", frames, [core, spikes], dt)
    return dict(name="laser_hit", frames=frames, fps=fps, dt=dt,
                n_per_frame=n_written[0],
                v0="core 0.4-1.0 m/s; spikes 0.30+1.0*(r/0.42) m/s",
                fade="core 15/s, spikes 12/s (exp)",
                expand="core 1.5/s, spikes 0.4/s",
                drag="core 1.5/s, spikes 1.2/s", scale="0.016-0.15 m", size_note="~1 m")

# ---------------------------------------------------------------- 4. charge (v0.9)
def gen_charge(out_dir, rng):
    """Converging swirl played across the whole laser recharge window:
    tangential arcs spiral inward, brightening cyan->white as they collapse."""
    frames = 6
    total = 2.2                      # = weapon_laser.recharge (playback fps stretches it)
    n = 520
    r0 = rng.uniform(0.5, 1.3, n)
    th0 = rng.uniform(0.0, 2.0 * np.pi, n)
    z0 = rng.normal(0.0, 0.25, n)
    omega = rng.uniform(3.5, 7.0, n)
    vin = rng.uniform(0.28, 0.55, n)
    vz = rng.normal(0.0, 0.15, n)
    long0 = rng.uniform(0.10, 0.17, n)
    cyan = np.array([0.35, 0.80, 1.00])
    white = np.array([0.88, 0.97, 1.00])
    n_written = []
    for f in range(frames):
        t = total * f / max(frames - 1, 1)
        u = t / total
        r = np.maximum(r0 - vin * t, 0.05)
        th = th0 + omega * t
        pos = np.stack([r * np.cos(th), z0 * (1.0 - 0.7 * u) + vz * t, r * np.sin(th)], axis=1)
        tang = np.stack([-np.sin(th), np.zeros(n), np.cos(th)], axis=1)
        tang /= np.maximum(np.linalg.norm(tang, axis=1, keepdims=True), 1e-12)
        col = lerp(np.tile(cyan, (n, 1)), np.tile(white, (n, 1)), np.full((n, 1), 0.15 + 0.85 * u * u))
        alpha = np.clip(0.35 + 0.60 * u * u, 0.05, 0.95)
        long_ax = long0 * (1.0 - 0.45 * u)
        thin = np.full(n, 0.02) * (1.0 - 0.3 * u)
        scale = np.stack([long_ax, thin, thin], axis=1)
        path = os.path.join(out_dir, "charge_%02d.ply" % f)
        n_written.append(write_ply(path, pos, col, alpha, scale, elongated_quats(tang)))
    return dict(name="charge", frames=frames, fps=frames / total, dt=total / max(frames - 1, 1),
                n_per_frame=n_written[0],
                v0="spiral 3.5-7 rad/s tangential + 0.28-0.55 m/s inward",
                fade="alpha ramps 0.35->0.95 (u^2)", expand="shrink 45% long axis",
                drag="n/a (kinematic)", scale="0.02-0.17 m", size_note="~2.6 m collapse")

# ---------------------------------------------------------------- validation
def validate_dir(out_dir, expected_names):
    print("\n== validation ==")
    all_ok = True
    rows = []
    for fn in expected_names:
        path = os.path.join(out_dir, fn)
        problems = []
        try:
            arr, fmt, n, hdr_len, fsize = read_ply(path)
        except Exception as exc:                      # noqa: BLE001
            rows.append((fn, "-", "-", "-", "-", "-", "-", "READ FAIL: %s" % exc))
            all_ok = False
            continue
        if fmt != "format binary_little_endian 1.0":
            problems.append("format")
        if len(arr.dtype.names) != 17 or arr.dtype.itemsize != STRIDE:
            problems.append("stride=%d" % arr.dtype.itemsize)
        if fsize != hdr_len + n * STRIDE:
            problems.append("filesize=%d!=%d+%d*68" % (fsize, hdr_len, n))
        flat = np.stack([arr[nm] for nm in FIELD_NAMES], axis=1).astype(np.float64)
        if not np.isfinite(flat).all():
            problems.append("nonfinite")
        q = np.stack([arr["rot_0"], arr["rot_1"], arr["rot_2"], arr["rot_3"]], axis=1).astype(np.float64)
        qn = np.sqrt((q ** 2).sum(axis=1))
        if np.abs(qn - 1.0).max() > 1e-3:
            problems.append("|q|=%.4f" % np.abs(qn - 1.0).max())
        col = flat[:, 6:9] * SH_C0 + 0.5
        if col.min() < -1e-3 or col.max() > 1.0 + 1e-3:
            problems.append("color[%.3f,%.3f]" % (col.min(), col.max()))
        alpha = 1.0 / (1.0 + np.exp(-flat[:, 9]))
        if alpha.min() <= 0.0 or alpha.max() >= 1.0:
            problems.append("alpha")
        sc = np.exp(flat[:, 10:13])
        if sc.min() <= 0.0:
            problems.append("scale<=0")
        pos = flat[:, 0:3]
        bbox_r = float(np.linalg.norm(pos, axis=1).max())
        status = "OK" if not problems else "FAIL:" + ",".join(problems)
        all_ok &= not problems
        rows.append((fn, str(n), "%.3f" % bbox_r,
                     "%.4f" % sc.min(), "%.4f" % sc.max(), "%.4f" % float(np.median(sc)),
                     "(%.2f,%.2f,%.2f)" % tuple(col.mean(axis=0)), status))
    print("%-18s %6s %8s %9s %9s %9s  %-16s %s"
          % ("file", "N", "bbox_r(m)", "sc_min", "sc_max", "sc_med", "avg_rgb", "status"))
    for r in rows:
        print("%-18s %6s %8s %9s %9s %9s  %-16s %s" % r)
    print("validation: %s (%d files)" % ("PASS" if all_ok else "FAIL", len(rows)))
    return all_ok

# ---------------------------------------------------------------- main
def main():
    rng = np.random.default_rng(SEED)
    os.makedirs(OUT_DIR, exist_ok=True)
    params = []
    params.append(gen_muzzle(OUT_DIR, np.random.default_rng(SEED + 1)))
    params.append(gen_blast(OUT_DIR, np.random.default_rng(SEED + 2)))
    params.append(gen_laser_hit(OUT_DIR, np.random.default_rng(SEED + 3)))
    params.append(gen_charge(OUT_DIR, np.random.default_rng(SEED + 4)))

    print("== generated ==")
    for p in params:
        print("%-10s: %2d frames @ %.1f fps (dt=%.4f s), %d splats/frame, T=%.3f s"
              % (p["name"], p["frames"], p["fps"], p["dt"], p["n_per_frame"], (p["frames"] - 1) * p["dt"]))
        print("            v0: %s" % p["v0"])
        print("            drag: %s | fade: %s | expand: %s | scale: %s | %s"
              % (p["drag"], p["fade"], p["expand"], p["scale"], p["size_note"]))

    expected = (["muzzle_%02d.ply" % i for i in range(6)]
                + ["blast_%02d.ply" % i for i in range(12)]
                + ["laser_hit_%02d.ply" % i for i in range(8)]
                + ["charge_%02d.ply" % i for i in range(6)])
    ok = validate_dir(OUT_DIR, expected)
    return 0 if ok else 1

if __name__ == "__main__":
    raise SystemExit(main())

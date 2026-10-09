#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ply_to_compressed.py -- pure-Python (numpy) converter from standard INRIA 3DGS
binary PLY to the gdgs plugin ".compressed.ply" format, plus a simulated decoder
that mirrors addons/gdgs/importers/decoders/compressed_ply_decoder.gd exactly,
for numerical round-trip verification.

Target layout (reverse-engineered from the plugin, confirmed against
assets/demo.compressed.ply produced by splat-transform 1.8.2):

    ply
    format binary_little_endian 1.0
    element chunk  <ceil(vertex_count / 256)>
    property float min_x min_y max_x ... max_b     (18 x float32, stride 72)
    element vertex <vertex_count>
    property uint packed_position                  (u32, stride 16 total)
    property uint packed_rotation
    property uint packed_scale
    property uint packed_color
    element sh <vertex_count>                      (optional; K = props/3, 0..15)
    property uchar f_rest_0 ...                    (3K x uchar, planar layout)

Usage:
    python tools/ply_to_compressed.py                       # convert + verify earth_l0
    python tools/ply_to_compressed.py --input PATH [--output PATH]
    python tools/ply_to_compressed.py --inspect PATH        # decode-only sanity dump
"""

import argparse
import math
import os
import sys

import numpy as np

SH_C0 = 0.28209479177387814          # compressed_ply_decoder.gd SH_C0
SQRT2 = 1.4142135623730951           # SQRT2
SQRT1_2 = 0.7071067811865476
SH_COEFF_COUNT = 48
CHUNK_SIZE = 256                     # vertices per chunk record

# PLY type name -> (numpy dtype char, byte size)
PLY_TYPES = {
    "char": ("i1", 1), "int8": ("i1", 1),
    "uchar": ("u1", 1), "uint8": ("u1", 1),
    "short": ("i2", 2), "int16": ("i2", 2),
    "ushort": ("u2", 2), "uint16": ("u2", 2),
    "int": ("i4", 4), "int32": ("i4", 4),
    "uint": ("u4", 4), "uint32": ("u4", 4),
    "float": ("f4", 4), "float32": ("f4", 4),
    "double": ("f8", 8), "float64": ("f8", 8),
}


# ---------------------------------------------------------------------------
# Generic binary_little_endian PLY reader (mirrors binary_ply_reader.gd)
# ---------------------------------------------------------------------------

class PlyElement:
    def __init__(self, name, count):
        self.name = name
        self.count = count
        self.properties = []          # list of (name, type_name, offset, size)
        self.stride = 0
        self.data = None              # raw bytes

    def prop(self, name):
        for p in self.properties:
            if p[0] == name:
                return p
        return None

    def column(self, name):
        """Decode one property into a numpy array (stride-aware)."""
        p = self.prop(name)
        if p is None:
            return None
        _, type_name, offset, size = p
        dt = np.dtype("<" + PLY_TYPES[type_name][0])
        if self.stride == size:
            return np.ascontiguousarray(
                np.frombuffer(self.data, dtype=dt, count=self.count,
                              offset=offset))
        raw = np.frombuffer(self.data, dtype=np.uint8,
                            count=self.count * self.stride)
        raw = raw.reshape(self.count, self.stride)
        cell = np.ascontiguousarray(raw[:, offset:offset + size])
        return cell.view(dt).reshape(-1)


def parse_ply(path):
    """Parse a binary_little_endian PLY. Returns (elements, header_size)."""
    with open(path, "rb") as f:
        magic = f.readline().strip()
        if magic != b"ply":
            raise ValueError("missing PLY magic")
        fmt = None
        elements = []
        cur = None
        while True:
            line = f.readline()
            if not line:
                raise ValueError("unexpected EOF in header")
            text = line.decode("ascii", "replace").strip()
            if not text:
                continue
            if text == "end_header":
                break
            parts = text.split(" ")
            tok = parts[0]
            if tok in ("comment", "obj_info"):
                continue
            if tok == "format":
                fmt = parts[1]
            elif tok == "element":
                cur = PlyElement(parts[1], int(parts[2]))
                elements.append(cur)
            elif tok == "property":
                if parts[1] == "list":
                    raise ValueError("list properties unsupported")
                if cur is None:
                    raise ValueError("property before element")
                tname = parts[1]
                if tname not in PLY_TYPES:
                    raise ValueError("unsupported PLY type %r" % tname)
                cur.properties.append((parts[2], tname, cur.stride,
                                       PLY_TYPES[tname][1]))
                cur.stride += PLY_TYPES[tname][1]
            else:
                raise ValueError("unsupported header token %r" % tok)
        if fmt != "binary_little_endian":
            raise ValueError("only binary_little_endian supported, got %r" % fmt)
        for el in elements:
            need = el.count * el.stride
            el.data = f.read(need)
            if len(el.data) != need:
                raise ValueError("truncated data for element %r" % el.name)
    return elements


# ---------------------------------------------------------------------------
# Source (standard INRIA 3DGS PLY) loading into plugin "canonical" form
# ---------------------------------------------------------------------------

def _need(prop_map, names):
    missing = [n for n in names if n not in prop_map]
    if missing:
        raise ValueError("source PLY missing required properties: %s"
                         % ", ".join(missing))


def _default(vertex, name, default, count):
    col = vertex.column(name)
    if col is None:
        return np.full(count, default, dtype=np.float64)
    return col.astype(np.float64)


def load_standard(path):
    """Return canonical dict equivalent to StandardPlyDecoder.decode()."""
    elements = parse_ply(path)
    vertex = next((e for e in elements if e.name == "vertex"), None)
    if vertex is None:
        raise ValueError("no 'vertex' element")
    cols = {p[0]: vertex.column(p[0]) for p in vertex.properties}
    n = vertex.count
    _need(cols, ["x", "y", "z", "f_dc_0", "f_dc_1", "f_dc_2", "opacity",
                 "scale_0", "scale_1", "rot_0", "rot_1", "rot_2", "rot_3"])

    positions = np.stack([_default(vertex, k, 0.0, n) for k in "xyz"], axis=1)
    log_scales = np.stack([
        _default(vertex, "scale_0", 0.0, n),
        _default(vertex, "scale_1", 0.0, n),
        _default(vertex, "scale_2", math.log(1e-6), n)], axis=1)
    scales_linear = np.exp(log_scales)

    # rot_0..3 stored as (w, x, y, z) in the file
    quat_wxyz = np.stack([
        _default(vertex, "rot_0", 1.0, n),
        _default(vertex, "rot_1", 0.0, n),
        _default(vertex, "rot_2", 0.0, n),
        _default(vertex, "rot_3", 0.0, n)], axis=1)
    norm = np.linalg.norm(quat_wxyz, axis=1, keepdims=True)
    norm[norm == 0.0] = 1.0
    quat_wxyz = quat_wxyz / norm

    opacity_logit = _default(vertex, "opacity", 0.0, n)
    opacities = 1.0 / (1.0 + np.exp(-opacity_logit))

    f_dc = np.stack([_default(vertex, "f_dc_%d" % i, 0.0, n)
                     for i in range(3)], axis=1)

    # f_rest_* -> canonical layout: coeff c of channel ch at index 3 + c*3 + ch
    rest_names = ["f_rest_%d" % i for i in range(45) if ("f_rest_%d" % i) in cols]
    sh = np.zeros((n, SH_COEFF_COUNT), dtype=np.float64)
    if rest_names:
        k = len(rest_names) // 3
        for c in range(k):
            sh[:, 3 + c * 3 + 0] = _default(vertex, "f_rest_%d" % c, 0.0, n)
            sh[:, 3 + c * 3 + 1] = _default(vertex, "f_rest_%d" % (c + 15), 0.0, n)
            sh[:, 3 + c * 3 + 2] = _default(vertex, "f_rest_%d" % (c + 30), 0.0, n)

    return {
        "count": n,
        "positions": positions,
        "log_scales": log_scales,
        "scales_linear": scales_linear,
        "quat_wxyz": quat_wxyz,
        "opacities": opacities,
        "f_dc": f_dc,
        "sh": sh,
        "sh_coeffs_per_channel": len(rest_names) // 3 if rest_names else 0,
    }


# ---------------------------------------------------------------------------
# Encoder: canonical -> packed chunks (inverse of compressed_ply_decoder.gd)
# ---------------------------------------------------------------------------

def _chunk_bounds(values_padded):
    """values_padded: (nchunks*256, 3) float64 -> (min, max) float32 arrays."""
    v = values_padded.reshape(-1, CHUNK_SIZE, values_padded.shape[1])
    mins = v.min(axis=1).astype(np.float32)
    maxs = v.max(axis=1).astype(np.float32)
    return mins, maxs


def _quantize(values, mins32, maxs32, levels):
    """Index = floor((v - min) / (max - min) * levels + 0.5), clipped.

    mins/maxs are float32 (exactly what the plugin will read back);
    all math in float64. Degenerate ranges map to index 0.
    """
    mins = mins32.astype(np.float64)
    maxs = maxs32.astype(np.float64)
    rng = maxs - mins
    safe = np.where(rng > 0.0, rng, 1.0)
    v = values.reshape(mins.shape[0], CHUNK_SIZE, values.shape[-1])
    idx = np.floor((v - mins[:, None, :]) / safe[:, None, :] * levels + 0.5)
    idx = np.clip(idx, 0, levels)
    idx = np.where(rng[:, None, :] > 0.0, idx, 0.0)
    return idx.astype(np.int64)


def pack_rotations(quat_wxyz):
    """2:10:10:10 rotation packing (mirrors splat-transform packRot).

    Decoder: largest=(v>>30)&3; the three non-largest components (ascending
    index order) are d=((p/1023)-0.5)*sqrt2, i.e. the RAW normalized
    quaternion components (10-bit unorm, step sqrt(2)/1023); the largest
    component is reconstructed as +sqrt(1 - sum d^2). Sign is fixed so the
    largest component is positive. The gdgs decoder builds
    Quaternion(c1, c2, c3, c0), so component index 0 is 'w' == quat_wxyz
    column 0 here.
    """
    q = quat_wxyz.astype(np.float64)
    q = q / np.linalg.norm(q, axis=1, keepdims=True)
    largest = np.argmax(np.abs(q), axis=1)                    # (N,) in 0..3
    rows = np.arange(q.shape[0])
    sign = np.where(q[rows, largest] < 0.0, -1.0, 1.0)        # largest positive
    q = q * sign[:, None]
    # reference writer quantizes the raw component: (a*sqrt(2)/2 + 0.5) -> 10 bit
    p = np.floor((q * SQRT1_2 + 0.5) * 1023.0 + 0.5)          # 0..1023
    p = np.clip(p, 0.0, 1023.0).astype(np.int64)
    # gather the three non-largest components in ascending index order,
    # exactly as the decoder scatters packed[0..2] into the free slots
    pvals = np.zeros((q.shape[0], 3), dtype=np.int64)
    for j in range(4):
        mask = largest == j
        if not mask.any():
            continue
        for k, ci in enumerate(i for i in range(4) if i != j):
            pvals[mask, k] = p[mask, ci]
    packed = ((largest.astype(np.int64) << 30)
              | (pvals[:, 0] << 20) | (pvals[:, 1] << 10) | pvals[:, 2])
    return packed.astype(np.uint32)


def pack_colors(f_dc, opacity):
    """DC SH -> display color space; opacity -> 8-bit. Returns (color, alpha).

    Like the reference writer, the display color is NOT clamped to [0, 1]:
    chunk min/max adapt to the actual range, so extreme f_dc survive
    (up to 8-bit resolution within the chunk).
    """
    color = f_dc * SH_C0 + 0.5
    alpha = np.clip(np.floor(opacity * 255.0 + 0.5), 0.0, 255.0).astype(np.int64)
    return color, alpha


def quantize_sh(sh_coeffs):
    """Inverse of ((v+0.5)/256 - 0.5)*8 for canonical-layout coeffs.

    Returns (bytes (N, 3K) planar, K). Input sh_coeffs uses canonical layout
    [3 + c*3 + channel]; output planar layout [channel*K + c].
    """
    n, total = sh_coeffs.shape
    k = (total - 3) // 3
    if k == 0:
        return np.zeros((n, 0), dtype=np.uint8), 0
    vals = np.empty((n, 3, k), dtype=np.float64)
    for c in range(k):
        for ch in range(3):
            vals[:, ch, c] = sh_coeffs[:, 3 + c * 3 + ch]
    idx = np.floor((vals / 8.0 + 0.5) * 256.0 - 0.5 + 0.5)    # nearest
    idx = np.clip(idx, 0.0, 255.0).astype(np.uint8)
    return idx.reshape(n, 3 * k), k


def encode(src_path, dst_path):
    canon = load_standard(src_path)
    n = canon["count"]
    n_chunks = (n + CHUNK_SIZE - 1) // CHUNK_SIZE
    padded = n_chunks * CHUNK_SIZE

    def pad(a, fill="edge"):
        if a.shape[0] == padded:
            return a
        tail = np.repeat(a[-1:], padded - a.shape[0], axis=0)
        return np.concatenate([a, tail], axis=0)

    pos = pad(canon["positions"])
    log_s = pad(np.clip(canon["log_scales"], -20.0, 20.0))   # reference writer clamps
    color, alpha = pack_colors(canon["f_dc"], canon["opacities"])
    color = pad(color)

    # chunk metadata (float32 on purpose: that is exactly what is stored)
    pos_min, pos_max = _chunk_bounds(pos)
    scl_min, scl_max = _chunk_bounds(log_s)
    col_min, col_max = _chunk_bounds(color)

    packed_pos = _quantize(pos, pos_min, pos_max, 2047)
    packed_scale = _quantize(log_s, scl_min, scl_max, 2047)
    # bit layout: x 11 bits @21, y 10 bits @11, z 11 bits @0
    pp = ((packed_pos[:, :, 0] << 21) | (packed_pos[:, :, 1] << 11)
          | packed_pos[:, :, 2]).reshape(-1).astype(np.uint32)
    ps = ((packed_scale[:, :, 0] << 21) | (packed_scale[:, :, 1] << 11)
          | packed_scale[:, :, 2]).reshape(-1).astype(np.uint32)

    pr = pack_rotations(pad(canon["quat_wxyz"]))[:n]

    idx_col = _quantize(color, col_min, col_max, 255)         # (nchunks,256,3)
    idx_col = idx_col.reshape(-1, 3)[:n]
    alpha_full = np.zeros(padded, dtype=np.int64)
    alpha_full[:n] = alpha
    packed_color = ((idx_col[:, 0] << 24) | (idx_col[:, 1] << 16)
                    | (idx_col[:, 2] << 8) | alpha_full[:n]).astype(np.uint32)

    sh_bytes, sh_k = quantize_sh(canon["sh"]) if canon["sh_coeffs_per_channel"] \
        else (np.zeros((n, 0), dtype=np.uint8), 0)

    # ---- write file ----
    lines = ["ply", "format binary_little_endian 1.0",
             "comment converted by tools/ply_to_compressed.py",
             "element chunk %d" % n_chunks]
    for name in ["min_x", "min_y", "min_z", "max_x", "max_y", "max_z",
                 "min_scale_x", "min_scale_y", "min_scale_z",
                 "max_scale_x", "max_scale_y", "max_scale_z",
                 "min_r", "min_g", "min_b", "max_r", "max_g", "max_b"]:
        lines.append("property float %s" % name)
    lines.append("element vertex %d" % n)
    for name in ["packed_position", "packed_rotation", "packed_scale",
                 "packed_color"]:
        lines.append("property uint %s" % name)
    if sh_k > 0:
        lines.append("element sh %d" % n)
        for i in range(3 * sh_k):
            lines.append("property uchar f_rest_%d" % i)
    lines.append("end_header")
    header = ("\n".join(lines) + "\n").encode("ascii")

    chunk_rec = np.zeros((n_chunks, 18), dtype=np.float32)
    chunk_rec[:, 0:3] = pos_min
    chunk_rec[:, 3:6] = pos_max
    chunk_rec[:, 6:9] = scl_min
    chunk_rec[:, 9:12] = scl_max
    chunk_rec[:, 12:15] = col_min
    chunk_rec[:, 15:18] = col_max

    vert_rec = np.zeros((n, 4), dtype="<u4")
    vert_rec[:, 0] = pp[:n]
    vert_rec[:, 1] = pr
    vert_rec[:, 2] = ps[:n]
    vert_rec[:, 3] = packed_color

    with open(dst_path, "wb") as f:
        f.write(header)
        f.write(chunk_rec.tobytes())
        f.write(vert_rec.tobytes())
        if sh_k > 0:
            f.write(np.ascontiguousarray(sh_bytes).tobytes())

    return canon, dst_path


# ---------------------------------------------------------------------------
# Simulated decoder: exact mirror of CompressedPlyDecoder.decode()
# ---------------------------------------------------------------------------

def decode_compressed(path):
    """Return canonical dict equivalent to CompressedPlyDecoder.decode()."""
    elements = parse_ply(path)
    by_name = {e.name: e for e in elements}
    chunk_el = by_name.get("chunk")
    vertex_el = by_name.get("vertex")
    if chunk_el is None or vertex_el is None:
        raise ValueError("compressed PLY must contain 'chunk' and 'vertex'")

    for p in ["packed_position", "packed_rotation", "packed_scale",
              "packed_color"]:
        if vertex_el.prop(p) is None:
            raise ValueError("missing vertex property %r" % p)
    for p in ["min_x", "min_y", "min_z", "max_x", "max_y", "max_z",
              "min_scale_x", "min_scale_y", "min_scale_z",
              "max_scale_x", "max_scale_y", "max_scale_z",
              "min_r", "min_g", "min_b", "max_r", "max_g", "max_b"]:
        if chunk_el.prop(p) is None:
            raise ValueError("missing chunk property %r" % p)

    n = vertex_el.count
    expected = (n + CHUNK_SIZE - 1) // CHUNK_SIZE
    if chunk_el.count < expected:
        raise ValueError("not enough chunk records (%d < %d)"
                         % (chunk_el.count, expected))

    def chunk_cols(names):
        cols = []
        for nm in names:
            col = chunk_el.column(nm)
            if col is None:
                raise ValueError("missing chunk property %r" % nm)
            cols.append(col.astype(np.float64))
        return np.stack(cols, axis=1)

    c_pos_min = chunk_cols(["min_x", "min_y", "min_z"])
    c_pos_max = chunk_cols(["max_x", "max_y", "max_z"])
    c_scl_min = chunk_cols(["min_scale_x", "min_scale_y", "min_scale_z"])
    c_scl_max = chunk_cols(["max_scale_x", "max_scale_y", "max_scale_z"])
    c_col_min = chunk_cols(["min_r", "min_g", "min_b"])
    c_col_max = chunk_cols(["max_r", "max_g", "max_b"])

    sh_el = by_name.get("sh")
    sh_k = 0
    sh_data = None
    if sh_el is not None:
        if sh_el.count != n:
            raise ValueError("sh element count != vertex count")
        sh_k = len(sh_el.properties) // 3
        if not 0 <= sh_k <= 15:
            raise ValueError("unsupported sh payload size")
        sh_data = sh_el.data

    pos_min = c_pos_min[np.arange(n) // CHUNK_SIZE]
    pos_max = c_pos_max[np.arange(n) // CHUNK_SIZE]
    scl_min = c_scl_min[np.arange(n) // CHUNK_SIZE]
    scl_max = c_scl_max[np.arange(n) // CHUNK_SIZE]
    col_min = c_col_min[np.arange(n) // CHUNK_SIZE]
    col_max = c_col_max[np.arange(n) // CHUNK_SIZE]

    pp = vertex_el.column("packed_position").astype(np.uint32)
    ps = vertex_el.column("packed_scale").astype(np.uint32)
    pr = vertex_el.column("packed_rotation").astype(np.uint32)
    pc = vertex_el.column("packed_color").astype(np.uint32)

    # _unpack_111011: x 11 bits @21, y 10 bits @11, z 11 bits @0
    def unpack_111011(v):
        nx = ((v >> np.uint32(21)) & np.uint32(0x7FF)).astype(np.float64) / 2047.0
        ny = ((v >> np.uint32(11)) & np.uint32(0x3FF)).astype(np.float64) / 1023.0
        nz = (v & np.uint32(0x7FF)).astype(np.float64) / 2047.0
        return np.stack([nx, ny, nz], axis=1)

    positions = pos_min + (pos_max - pos_min) * unpack_111011(pp)
    log_scales = scl_min + (scl_max - scl_min) * unpack_111011(ps)
    scales_linear = np.exp(log_scales)

    # rotations
    largest = ((pr >> np.uint32(30)) & np.uint32(3)).astype(np.int64)
    p0 = ((pr >> np.uint32(20)) & np.uint32(0x3FF)).astype(np.float64)
    p1 = ((pr >> np.uint32(10)) & np.uint32(0x3FF)).astype(np.float64)
    p2 = (pr & np.uint32(0x3FF)).astype(np.float64)
    d = np.stack([p0, p1, p2], axis=1)
    d = (d / 1023.0 - 0.5) * SQRT2
    comps = np.zeros((n, 4), dtype=np.float64)                # [w, x, y, z]
    rows = np.arange(n)
    for j in range(4):
        mask = largest == j
        if not mask.any():
            continue
        others = [i for i in range(4) if i != j]
        for k, ci in enumerate(others):
            comps[mask, ci] = d[mask, k]
        comps[mask, j] = np.sqrt(np.maximum(
            0.0, 1.0 - np.sum(d[mask] ** 2, axis=1)))
    quat_xyzw = comps[:, [1, 2, 3, 0]]
    qn = np.linalg.norm(quat_xyzw, axis=1, keepdims=True)
    qn[qn == 0.0] = 1.0
    quat_xyzw = quat_xyzw / qn

    # packed color 8888
    r = ((pc >> np.uint32(24)) & np.uint32(0xFF)).astype(np.float64) / 255.0
    g = ((pc >> np.uint32(16)) & np.uint32(0xFF)).astype(np.float64) / 255.0
    b = ((pc >> np.uint32(8)) & np.uint32(0xFF)).astype(np.float64) / 255.0
    a = (pc & np.uint32(0xFF)).astype(np.float64) / 255.0
    dc = np.stack([r, g, b], axis=1)
    dc = col_min + (col_max - col_min) * dc
    f_dc = (dc - 0.5) / SH_C0

    sh = np.zeros((n, SH_COEFF_COUNT), dtype=np.float64)
    if sh_k > 0:
        raw = np.frombuffer(sh_data, dtype=np.uint8, count=n * 3 * sh_k)
        raw = raw.reshape(n, 3 * sh_k)
        for c in range(sh_k):
            for ch in range(3):
                v = raw[:, ch * sh_k + c].astype(np.float64)
                sh[:, 3 + c * 3 + ch] = ((v + 0.5) / 256.0 - 0.5) * 8.0

    return {
        "count": n,
        "positions": positions,
        "log_scales": log_scales,
        "scales_linear": scales_linear,
        "quat_wxyz": quat_xyzw[:, [3, 0, 1, 2]],
        "opacities": a,
        "f_dc": f_dc,
        "sh": sh,
        "sh_coeffs_per_channel": sh_k,
    }


# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------

def verify(orig, dec):
    n = orig["count"]
    assert dec["count"] == n, "point count mismatch"

    print("=" * 64)
    print("Round-trip verification (simulated gdgs decoder vs source PLY)")
    print("=" * 64)

    # ---- positions (meters) ----
    d = np.linalg.norm(dec["positions"] - orig["positions"], axis=1)
    print("\nposition error        [m]      mean %.6f   max %.6f   p99 %.6f"
          % (d.mean(), d.max(), np.percentile(d, 99)))
    ok_pos = d.mean() < 0.18
    print("  criterion: mean < 0.18 m (0.5 x 0.36 m point spacing) -> %s"
          % ("PASS" if ok_pos else "FAIL"))

    # ---- display colors (reported in 1/255 units) ----
    col_src = 0.5 + SH_C0 * orig["f_dc"]                      # unclamped, like the format
    out_of_range = int(np.sum(np.any(col_src < 0.0, axis=1)
                              | np.any(col_src > 1.0, axis=1)))
    dc_dec = dec["f_dc"] * SH_C0 + 0.5
    cerr = np.abs(dc_dec - col_src) * 255.0                  # per channel
    print("\ncolor error          [1/255]   mean %.4f   max %.4f"
          % (cerr.mean(), cerr.max()))
    for i, ch in enumerate("RGB"):
        print("  %s: mean %.4f  max %.4f" % (ch, cerr[:, i].mean(),
                                            cerr[:, i].max()))
    ok_col = cerr.mean() < 2.0
    print("  criterion: mean < 2/255 -> %s%s"
          % ("PASS" if ok_col else "FAIL",
             "" if out_of_range == 0 else "  (%d source splats have display color outside [0,1]; kept unclamped like the reference writer)" % out_of_range))

    # ---- opacity ----
    oerr = np.abs(dec["opacities"] - orig["opacities"])
    print("\nopacity error         [0..1]   mean %.6f   max %.6f   (max 1/510 = %.6f)"
          % (oerr.mean(), oerr.max(), 1.0 / 510.0))

    # ---- scales ----
    serr = np.abs(dec["scales_linear"] - orig["scales_linear"])
    rel = serr / np.maximum(orig["scales_linear"], 1e-12)
    print("\nscale error           [m abs]  mean %.6f   max %.6f"
          % (serr.mean(), serr.max()))
    print("scale rel error         [%%]     mean %.4f   max %.4f"
          % (rel.mean() * 100.0, rel.max() * 100.0))

    # ---- rotations ----
    q1 = orig["quat_wxyz"]
    q2 = dec["quat_wxyz"]
    dot = np.abs(np.sum(q1 * q2, axis=1))
    ang = 2.0 * np.degrees(np.arccos(np.clip(dot, 0.0, 1.0)))
    print("\nrotation angle error  [deg]    mean %.6f   max %.6f"
          % (ang.mean(), ang.max()))

    # ---- SH (if any) ----
    if orig["sh_coeffs_per_channel"] > 0:
        sherr = np.abs(dec["sh"] - orig["sh"])
        print("\nSH coeff error                 mean %.6f   max %.6f   (quant step 8/256 = %.6f)"
              % (sherr.mean(), sherr.max(), 8.0 / 256.0))
    else:
        print("\nSH coeffs beyond DC: none in source (compressed file omits "
              "'sh' element; plugin leaves them at 0, matching the standard path)")

    print("\n" + "=" * 64)
    print("PASS conditions: position mean %s, color mean %s"
          % ("PASS" if ok_pos else "FAIL", "PASS" if ok_col else "FAIL"))
    return ok_pos and ok_col


def size_report(src_path, dst_path):
    a = os.path.getsize(src_path)
    b = os.path.getsize(dst_path)
    print("\n" + "=" * 64)
    print("file size:  %s  = %d bytes" % (os.path.basename(src_path), a))
    print("file size:  %s  = %d bytes" % (os.path.basename(dst_path), b))
    print("compression ratio: %.4f  (%.2fx smaller, %.1f%% saved)"
          % (b / a, a / b, (1.0 - b / a) * 100.0))


# ---------------------------------------------------------------------------
# Independent sanity check against the bundled demo file (splat-transform output)
# ---------------------------------------------------------------------------

def inspect(path):
    dec = decode_compressed(path)
    n = dec["count"]
    print("decoded %s: %d splats, %d SH coeffs/channel" %
          (os.path.basename(path), n, dec["sh_coeffs_per_channel"]))
    print("position range : min %s" % np.round(dec["positions"].min(axis=0), 3))
    print("                 max %s" % np.round(dec["positions"].max(axis=0), 3))
    print("scale range    : %.5f .. %.5f (m)"
          % (dec["scales_linear"].min(), dec["scales_linear"].max()))
    print("opacity range  : %.4f .. %.4f"
          % (dec["opacities"].min(), dec["opacities"].max()))
    dc = dec["f_dc"] * SH_C0 + 0.5
    print("dc color range : %.4f .. %.4f" % (dc.min(), dc.max()))
    qn = np.linalg.norm(dec["quat_wxyz"], axis=1)
    print("quat |norm-1|  : max %.2e (unit quaternions expected)" %
          np.abs(qn - 1.0).max())
    if dec["sh_coeffs_per_channel"] > 0:
        shn = dec["sh"][:, 3:]   # DC lives in f_dc; slots 0..2 stay zero
        print("SH range       : %.4f .. %.4f" % (shn.min(), shn.max()))


# ---------------------------------------------------------------------------

def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    default_in = os.path.join(root, "assets", "splat_planets", "earth_l0.ply")
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--input", default=default_in)
    ap.add_argument("--output", default=None)
    ap.add_argument("--inspect", metavar="PATH", default=None,
                    help="decode a .compressed.ply and dump sanity stats only")
    args = ap.parse_args()

    if args.inspect:
        inspect(args.inspect)
        return

    src = os.path.abspath(args.input)
    if args.output:
        dst = os.path.abspath(args.output)
    else:
        base, ext = os.path.splitext(src)
        dst = base + ".compressed.ply" if ext == ".ply" else src + ".compressed.ply"
    if os.path.abspath(dst) == os.path.abspath(src):
        raise SystemExit("refusing to overwrite the source file")

    print("converting:\n  src: %s\n  dst: %s" % (src, dst))
    canon, _ = encode(src, dst)
    print("  %d splats, %d chunk records, %d SH coeffs/channel"
          % (canon["count"], (canon["count"] + 255) // 256,
             canon["sh_coeffs_per_channel"]))

    dec = decode_compressed(dst)
    ok = verify(canon, dec)
    size_report(src, dst)
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()

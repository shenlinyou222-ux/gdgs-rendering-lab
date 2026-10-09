# -*- coding: utf-8 -*-
# v7.8: BOSS 渐次现身(分摊 GPU 上传) + 帧率骤降监控 + BOSS 资源预解析
import io

import os

# 仓库根目录（本脚本位于 tools/ 下，故取其上一级）
BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMBAT = BASE + "/solar_combat.gd"
PROPS = BASE + "/solar_props.gd"
NL = chr(10)

def indent_of(line):
    n = 0
    while n < len(line) and line[n] == chr(9):
        n += 1
    return chr(9) * n

def find_line(lines, needle, start=0):
    for i in range(start, len(lines)):
        if needle in lines[i]:
            return i
    return -1

# ---------- solar_props.gd ----------
with io.open(PROPS, "r", encoding="utf-8") as f:
    p = f.read()

if "reveal_i" not in p:
    lines = p.split(NL)
    # 1) 声明
    i = find_line(lines, "var w_t := 3.0")
    assert i >= 0
    ind = indent_of(lines[i])
    lines[i+1:i+1] = [ind + "var reveal_t := 0.0", ind + "var reveal_i := 0   # v7.8:渐次现身索引"]
    # 2) 初始隐藏
    i = find_line(lines, "add_child(g)")
    assert i >= 0
    ind = indent_of(lines[i])
    lines[i+1:i+1] = [ind + "g.visible = false   # v7.8:创建即隐藏, 由 tick 渐次点亮"]
    # 3) parts dict 加 sc/on/born
    i = find_line(lines, "parts.append({")
    assert i >= 0
    old = lines[i]
    assert old.count('"tier": tier,') == 1
    lines[i] = old.replace('"tier": tier, ', '"tier": tier, "sc": sc, "on": false, "born": 0.0, ')
    # 4) tick 循环改造(行区间替换, 缩进取 for 行)
    a = find_line(lines, "for p in parts:")
    assert a >= 0
    b = find_line(lines, "ar.monitoring = n.visible", a)
    assert b >= 0 and b - a < 20
    ind = indent_of(lines[a])
    ind2 = chr(9) * (len(ind) + 1)
    ind3 = chr(9) * (len(ind) + 2)
    newblock = [
        ind + "# v7.8 渐次现身:每 0.3s 点亮一个高斯部件(0.5s 弹入缩放) —— 分摊 GPU 上传, 出场不卡顿",
        ind + "reveal_t -= dt",
        ind + "if reveal_t <= 0.0 and reveal_i < parts.size():",
        ind2 + "reveal_t = 0.3",
        ind2 + "var pp: Dictionary = parts[reveal_i]",
        ind2 + "pp[" + chr(34) + "on" + chr(34) + "] = true",
        ind2 + "pp[" + chr(34) + "born" + chr(34) + "] = tt",
        ind2 + "reveal_i += 1",
        ind + "for p in parts:",
        ind2 + "var n: Node3D = p[" + chr(34) + "n" + chr(34) + "]",
        ind2 + "var spd: float = p[" + chr(34) + "w" + chr(34) + "] * (1.0 + (1.0 - hp_frac) * 2.0)",
        ind2 + "var ph: float = p[" + chr(34) + "ph" + chr(34) + "] + tt * spd * 0.25",
        ind2 + "var rr: float = p[" + chr(34) + "r" + chr(34) + "]",
        ind2 + "n.position = Vector3(cos(ph) * rr, sin(ph * 2.0) * 40.0 * float(p[" + chr(34) + "tier" + chr(34) + "] > 0), sin(ph) * rr)",
        ind2 + "n.rotate_y(dt * spd)",
        ind2 + "var on: bool = bool(p.get(" + chr(34) + "on" + chr(34) + ", true)) and hp_frac > float(p[" + chr(34) + "tier" + chr(34) + "]) * 0.28",
        ind2 + "var born: float = float(p.get(" + chr(34) + "born" + chr(34) + ", 0.0))",
        ind2 + "var pop: float = clampf((tt - born) / 0.5, 0.0, 1.0) if born > 0.0 else 1.0",
        ind2 + "pop = pop * pop * (3.0 - 2.0 * pop)   # smoothstep 弹入",
        ind2 + "n.visible = on",
        ind2 + "n.scale = Vector3.ONE * float(p[" + chr(34) + "sc" + chr(34) + "]) * (0.3 + 0.7 * pop)",
        ind2 + "var ar: Area3D = p[" + chr(34) + "ar" + chr(34) + "]",
        ind2 + "if is_instance_valid(ar):",
        ind3 + "ar.position = n.position",
        ind3 + "ar.monitoring = on and pop >= 1.0   # v7.8:弹入完成才有判定",
    ]
    lines[a:b+1] = newblock
    p = NL.join(lines)
    with io.open(PROPS, "w", encoding="utf-8", newline="") as f:
        f.write(p)
    print("OK props")
else:
    print("skip props")

# ---------- solar_combat.gd ----------
with io.open(COMBAT, "r", encoding="utf-8") as f:
    t = f.read()

if "_perf_fps" not in t:
    lines = t.split(NL)
    # 1) 监控变量
    i = find_line(lines, "var _crowd_lod_dbg := 0")
    assert i >= 0
    ind = indent_of(lines[i])
    lines[i+1:i+1] = [ind + "var _perf_t := 0.0            # v7.8:帧率监控采样计时",
                       ind + "var _perf_fps := 0.0          # v7.8:帧率平滑值",
                       ind + "var _perf_feed_cd := 0.0      # v7.8:帧率警告节流"]
    # 2) 监控逻辑(挂在 _ui_tick(dt) 调用后)
    i = find_line(lines, "_ui_tick(dt)")
    assert i >= 0
    ind = indent_of(lines[i])
    lines[i+1:i+1] = [
        ind + "_perf_t += dt   # v7.8:帧率骤降监控(0.5s 采样)",
        ind + "if _perf_t >= 0.5:",
        ind + chr(9) + "_perf_t = 0.0",
        ind + chr(9) + "var fps_now := float(Engine.get_frames_per_second())",
        ind + chr(9) + "if _perf_fps < 1.0:",
        ind + chr(9) + chr(9) + "_perf_fps = fps_now",
        ind + chr(9) + "if fps_now < 55.0 and fps_now < _perf_fps * 0.65:",
        ind + chr(9) + chr(9) + "print(" + chr(34) + "[PERF] fps骤降 %.0f->%.0f | level=%d phase=%d enemies=%d ebolt=%d fbolt=%d boss=%s whale=%s" + chr(34) + " % [_perf_fps, fps_now, level, phase, enemies.size(), enemy_bolts.size(), friendly_bolts.size(), str(boss != null and is_instance_valid(boss)), str(_whale != null and is_instance_valid(_whale))])",
        ind + chr(9) + chr(9) + "_perf_feed_cd -= 0.5",
        ind + chr(9) + chr(9) + "if _perf_feed_cd <= 0.0:",
        ind + chr(9) + chr(9) + chr(9) + "_perf_feed_cd = 8.0",
        ind + chr(9) + chr(9) + chr(9) + "_feed(" + chr(34) + "⚠ 性能:帧率骤降 %.0f→%.0f(上下文见日志[PERF])" + chr(34) + " % [_perf_fps, fps_now])",
        ind + chr(9) + "_perf_fps = lerpf(_perf_fps, fps_now, 0.4)",
    ]
    # 3) BOSS 资源预解析(启动期)
    i = find_line(lines, "_precreate_gate()")
    assert i >= 0
    ind = indent_of(lines[i])
    lines[i+1:i+1] = [ind + "load(" + chr(34) + "res://assets/props/octa.ply" + chr(34) + ")   # v7.8:BOSS 高斯资源提前解析(出场只剩 GPU 上传, 且已渐次分摊)"]
    t = NL.join(lines)
    with io.open(COMBAT, "w", encoding="utf-8", newline="") as f:
        f.write(t)
    print("OK combat")
else:
    print("skip combat")
print("ALL v7.8 PATCHED")

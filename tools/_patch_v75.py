# -*- coding: utf-8 -*-
# v7.5: GPU LOD 预算 —— 全局最近 K 架高斯, 其余低模剪影; splat_range 收敛
import io

BASE = r"C:\Users\user\Desktop\ds harness\experiment\gdgs_lab"
COMBAT = BASE + "/solar_combat.gd"
CROWD = BASE + "/crowd.gd"
BAL = BASE + "/data/balance.txt"
NL = chr(10)

with io.open(CROWD, "r", encoding="utf-8") as f:
    c = f.read()

OLD_CULL = '''		cull_cd -= dt
		if cull_cd <= 0.0:
			cull_cd = 0.3
			var cam_pos: Vector3 = root.cam.global_position if root.cam != null else Vector3.ZERO
			var rng: float = root._b("crowd", "splat_range") if root != null else 1800.0
			for m in members:
				if not is_instance_valid(m):
					continue
				var near: bool = cam_pos.distance_to(m.global_position) < rng
				m.gs_node.visible = near
				m.mesh_node.visible = not near
'''
NEW_CULL = '''		cull_cd -= dt
		# v7.5: 逐流 LOD 已上移到 root._crowd_lod() —— 全局高斯预算(最近 K 架), 避免 260 架全高斯绘制
		if cull_cd <= 0.0:
			cull_cd = 0.3
			pass
'''

if "_crowd_lod" not in c:
    assert c.count(OLD_CULL) == 1, "crowd cull block not found"
    c = c.replace(OLD_CULL, NEW_CULL)
    with io.open(CROWD, "w", encoding="utf-8", newline="") as f:
        f.write(c)
    print("OK crowd")
else:
    print("skip crowd")

VAR_DECL = '''var _crowd_lod_cd := 0.0       # v7.5:全局高斯 LOD 裁决节流
var _crowd_lod_dbg := 0
'''

LOD_FN = '''
# ==================== v7.5 全局高斯 LOD 预算: GPU 绘制数封顶 ====================
func _crowd_lod() -> void:
	# 空间复用省的是显存(同型共享 GaussianResource); 但每架仍是独立绘制调用。
	# 260 架全高斯 = 260 次半透明 splat 绘制+排序, GPU 顶不住。
	# 这里按距离排序, 只有最近 gauss_cap 架保留高斯, 其余切换低模剪影(视觉密度不变)。
	if cam == null:
		return
	var cam_pos := cam.global_position
	var rng := _b("crowd", "splat_range")
	var cap := _bi("crowd", "gauss_cap")
	var arr: Array = []
	for e in enemies:
		if is_instance_valid(e) and (e as Enemy).gs_node != null:
			arr.append([cam_pos.distance_squared_to((e as Node3D).global_position), e])
	arr.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	var used := 0
	for it in arr:
		var e: Enemy = it[1]
		var near: bool = float(it[0]) < rng * rng and used < cap
		if near:
			used += 1
		if is_instance_valid(e.gs_node):
			e.gs_node.visible = near
		if is_instance_valid(e.mesh_node):
			e.mesh_node.visible = not near
	_crowd_lod_dbg += 1
	if _crowd_lod_dbg >= 20:
		_crowd_lod_dbg = 0
		print("[LOD] gauss=%d lowmesh=%d enemies=%d" % [used, arr.size() - used, enemies.size()])
'''

WIRE_OLD = "func _tick_streams(dt: float) -> void:" + NL
WIRE_NEW = "func _tick_streams(dt: float) -> void:" + NL + "	_crowd_lod_cd -= dt   # v7.5:全局高斯 LOD(0.3s 节流)" + NL + "	if _crowd_lod_cd <= 0.0:" + NL + "		_crowd_lod_cd = 0.3" + NL + "		_crowd_lod()" + NL

with io.open(COMBAT, "r", encoding="utf-8") as f:
    t = f.read()

if "func _crowd_lod" not in t:
    anchor = "var mega_mi: MeshInstance3D = null"
    assert t.count(anchor) == 1
    idx = t.index(anchor)
    line_end = t.index(NL, idx) + 1
    t = t[:line_end] + VAR_DECL + t[line_end:]
    assert t.count(WIRE_OLD) == 1
    t = t.replace(WIRE_OLD, WIRE_NEW)
    t = t.rstrip(NL) + LOD_FN + NL
    Q = chr(34)
    old_crowd = Q + "crowd" + Q + ": { " + Q + "members" + Q + ": 64.0, " + Q + "attack_tokens" + Q + ": 10.0, " + Q + "splat_range" + Q + ": 1800.0, " + Q + "jet_scale" + Q + ": 0.45 }"
    new_crowd = Q + "crowd" + Q + ": { " + Q + "members" + Q + ": 64.0, " + Q + "attack_tokens" + Q + ": 10.0, " + Q + "splat_range" + Q + ": 900.0, " + Q + "gauss_cap" + Q + ": 96.0, " + Q + "jet_scale" + Q + ": 0.45 }"
    assert t.count(old_crowd) == 1, "default crowd line mismatch"
    t = t.replace(old_crowd, new_crowd)
    with io.open(COMBAT, "w", encoding="utf-8", newline="") as f:
        f.write(t)
    print("OK combat")
else:
    print("skip combat")

with io.open(BAL, "r", encoding="utf-8") as f:
    b = f.read()
if "gauss_cap" not in b:
    assert b.count("splat_range = 1800") == 1
    b = b.replace("splat_range = 1800", "splat_range = 900")
    anchor2 = "jet_scale = 0.45"
    assert b.count(anchor2) == 1
    idx2 = b.index(anchor2)
    line_end2 = b.index(NL, idx2) + 1
    b = b[:line_end2] + "gauss_cap = 96         # v7.5:全局高斯绘制预算(最近 K 架高斯, 其余低模)" + NL + b[line_end2:]
    with io.open(BAL, "w", encoding="utf-8", newline="") as f:
        f.write(b)
    print("OK balance")
else:
    print("skip balance")
print("ALL v7.5 PATCHED")

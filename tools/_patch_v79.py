# -*- coding: utf-8 -*-
# v7.9: 敌机机群流/僚机 渐次出厂 —— 创建成本(节点+trimesh+高斯上传)按 0.12s/架 摊平
import io

import os

# 仓库根目录（本脚本位于 tools/ 下，故取其上一级）
BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMBAT = BASE + "/solar_combat.gd"
NL = chr(10)

with io.open(COMBAT, "r", encoding="utf-8") as f:
    t = f.read()

if "_tick_spawn_q" not in t:
    OLD_LOOP = '''	var origin := _core_spawn_pos() + Vector3(randf_range(-80, 80), randf_range(-30, 30), randf_range(-80, 80))
	for i in s.members_n:
		var e := Enemy.new()
		add_child(e)
		e.setup_jet(self, s, i, origin)
		e.speed = 42.0 * float(Crowd.TYPES[type_id]["speed_mul"]) * enemy_speed_mul   # v0.8:关卡速度倍率
		e.hp = int(round(float(e.hp) * enemy_hp_mul * float(Crowd.TYPES[type_id]["hp_mul"])))
		e.hp_max = e.hp
		enemies.append(e)
		s.members.append(e)
'''
    NEW_LOOP = '''	var origin := _core_spawn_pos() + Vector3(randf_range(-80, 80), randf_range(-30, 30), randf_range(-80, 80))
	# v7.9:整流成员不再一次性创建 —— 入队渐次出厂(0.12s/架), 分摊节点+trimesh+高斯上传的创建尖峰
	_spawn_q.append({"s": s, "i": 0, "cd": randf_range(0.0, 0.12), "origin": origin})
'''
    assert t.count(OLD_LOOP) == 1, "spawn loop mismatch"
    t = t.replace(OLD_LOOP, NEW_LOOP)

    # 变量声明(streams 声明后)
    anchor = "var streams: Array = []"
    # 可能带注释, 找行
    lines = t.split(NL)
    idx = -1
    for i, ln in enumerate(lines):
        if ln.startswith(anchor):
            idx = i
            break
    assert idx >= 0, "streams decl not found"
    lines[idx+1:idx+1] = ["var _spawn_q: Array = []          # v7.9:机群流出厂队列(渐次创建)"]
    t = NL.join(lines)

    # 接线: _tick_streams 调用后
    wire_anchor = chr(9) + "_tick_streams(dt)"
    assert t.count(wire_anchor) == 1, "tick_streams call anchor"
    t = t.replace(wire_anchor, wire_anchor + NL + chr(9) + "_tick_spawn_q(dt)   # v7.9:渐次出厂")

    # 僚机渐次出厂
    OLD_WM = '''func _spawn_wingmen() -> void:
	for i in _bi("wingman", "count"):
		_make_wingman(i)
	_feed("僚机 x%d 就位, 与敌机交战中(友伤已关闭)" % [_bi("wingman", "count")])
'''
    NEW_WM = '''func _spawn_wingmen() -> void:
	# v7.9:僚机渐次出厂(0.7s/架) —— 与敌机同样分摊创建成本
	_feed("僚机中队跃迁抵达 — 陆续就位(友伤已关闭)")
	_wingman_stagger()

func _wingman_stagger() -> void:
	if wingmen.size() >= _bi("wingman", "count"):
		return
	_make_wingman(wingmen.size())
	get_tree().create_timer(0.7).timeout.connect(_wingman_stagger)
'''
    assert t.count(OLD_WM) == 1, "wingmen block mismatch"
    t = t.replace(OLD_WM, NEW_WM)

    # 新函数追加
    TICKFN = '''

func _tick_spawn_q(dt: float) -> void:
	# v7.9:机群流渐次出厂 —— 每条流每 0.12s 生成 1 架(43 架约 5s 铺满), 创建成本摊平不再有波次尖峰
	var keep: Array = []
	for it in _spawn_q:
		var s = it["s"]
		if not is_instance_valid(s):
			continue
		it["cd"] = float(it["cd"]) - dt
		while float(it["cd"]) <= 0.0 and int(it["i"]) < s.members_n:
			var e := Enemy.new()
			add_child(e)
			e.setup_jet(self, s, int(it["i"]), it["origin"])
			e.speed = 42.0 * float(Crowd.TYPES[s.type_id]["speed_mul"]) * enemy_speed_mul
			e.hp = int(round(float(e.hp) * enemy_hp_mul * float(Crowd.TYPES[s.type_id]["hp_mul"])))
			e.hp_max = e.hp
			enemies.append(e)
			s.members.append(e)
			it["i"] = int(it["i"]) + 1
			it["cd"] = float(it["cd"]) + 0.12
		if int(it["i"]) < s.members_n:
			keep.append(it)
	_spawn_q = keep
'''
    t = t.rstrip(NL) + TICKFN + NL
    with io.open(COMBAT, "w", encoding="utf-8", newline="") as f:
        f.write(t)
    print("OK combat")
else:
    print("skip combat")
print("ALL v7.9 PATCHED")

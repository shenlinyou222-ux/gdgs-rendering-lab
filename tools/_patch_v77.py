# -*- coding: utf-8 -*-
# v7.7: radar spin off / whale-song-first finale / BGM louder / L1 guidance / EVA ack panel
import io

import os

# 仓库根目录（本脚本位于 tools/ 下，故取其上一级）
BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMBAT = BASE + "/solar_combat.gd"
PROPS = BASE + "/solar_props.gd"
NL = chr(10)

# ---------- solar_props.gd: radar antenna spin off ----------
with io.open(PROPS, "r", encoding="utf-8") as f:
    p = f.read()
OLD_SPIN = '''		for d in dishes:
			(d.get_meta("ant") as Node3D).rotate_object_local(Vector3.UP, dt * 0.8)
'''
NEW_SPIN = '''		# v7.7:相阵停止旋转 —— 天线保持固定朝向(轨道运行保留)
'''
if "v7.7" not in p:
    assert p.count(OLD_SPIN) == 1, "radar spin block not found"
    p = p.replace(OLD_SPIN, NEW_SPIN)
    with io.open(PROPS, "w", encoding="utf-8", newline="") as f:
        f.write(p)
    print("OK props")
else:
    print("skip props")

# ---------- solar_combat.gd ----------
ACK_VARS = '''var _ack_lbl: Label              # v7.7:EVA 应答表情面板(右侧)
var _ack_ttl := 0.0
'''

ACK_UI = '''	# --- v7.7 EVA 应答面板(右侧居中) ---
	_ack_lbl = Label.new()
	_ack_lbl.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_ack_lbl.anchor_left = 1.0
	_ack_lbl.anchor_right = 1.0
	_ack_lbl.offset_left = -460
	_ack_lbl.offset_right = -70
	_ack_lbl.offset_top = 190
	_ack_lbl.offset_bottom = 252
	_ack_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ack_lbl.add_theme_font_size_override("font_size", 24)
	_ack_lbl.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	_ack_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_ack_lbl.add_theme_constant_override("shadow_offset_y", 2)
	_ack_lbl.text = ""
	_ack_lbl.visible = false
	layer.add_child(_ack_lbl)
'''

ACK_TICK = '''	if _ack_lbl != null and _ack_lbl.visible:
		_ack_ttl -= dt
		_ack_lbl.modulate.a = clampf(_ack_ttl, 0.0, 1.0)
		if _ack_ttl <= 0.0:
			_ack_lbl.visible = false
'''

FINALE_OLD = '''	_eva_announce_key("l3_boss_down", true)
	_feed("🐋 星鲸现身 — 深空传来跨越千里的鲸歌…")
	_story_play([
		{"sp": "EVA", "tx": _eva_key_text("whale_line1"), "voice": "whale_line1"},
		{"sp": "", "tx": "那是什么？？？", "choice": true},
		{"sp": "EVA", "tx": _eva_key_text("finale_answer"), "voice": "finale_answer"},
		{"sp": "EVA", "tx": _eva_key_text("demo_complete"), "voice": "demo_complete", "done": true},
	])
'''
FINALE_NEW = '''	_feed("🐋 星鲸现身 — 深空传来跨越千里的鲸歌…")
	get_tree().create_timer(12.0).timeout.connect(_finale_voice)   # v7.7:先听 12s 鲸歌 → 再 EVA 播报 → 剧情语音
'''

NEW_FUNCS = '''
# ==================== v7.7 EVA 应答 / 终局时序 / L1 引导 ====================
func _eva_ack(tx: String = "收到，已完成") -> void:
	# 指令执行后的 EVA 应答: 字幕 + 右侧表情面板 + 文字频道
	_sub_transient("EVA", tx)
	_eva_say("好的, " + tx)
	if _ack_lbl != null:
		_ack_lbl.text = "٩( 'ω' )و  " + tx
		_ack_lbl.visible = true
		_ack_lbl.modulate.a = 1.0
		_ack_ttl = 2.6

func _finale_voice() -> void:
	# v7.7:鲸歌先行 12s 后才进入 EVA 播报 + 剧情语音(原实现击杀即触发太突兀)
	_eva_announce_key("l3_boss_down", true)
	_story_play([
		{"sp": "EVA", "tx": _eva_key_text("whale_line1"), "voice": "whale_line1"},
		{"sp": "", "tx": "那是什么？？？", "choice": true},
		{"sp": "EVA", "tx": _eva_key_text("finale_answer"), "voice": "finale_answer"},
		{"sp": "EVA", "tx": _eva_key_text("demo_complete"), "voice": "demo_complete", "done": true},
	])

func _l1_intro() -> void:
	# v7.7:L1 开场引导 —— 背景介绍 + 操作/超级武器/语音指挥教学(剧情字幕推进)
	if level != 1 or phase >= 3 or _story_on:
		return
	_story_play([
		{"sp": "EVA", "tx": "欢迎登机,飞行员。这里是近地防线 —— 星门失守后,敌军机群不断从虫洞涌出,你是这条轨道上最后一架截击机。"},
		{"sp": "EVA", "tx": "我是 EVA,你的舰载 AI。按 [1/E/空格] 或点击鼠标推进对话。"},
		{"sp": "EVA", "tx": "操作指引: 主激光常驻照射; [F] 全自动火控; [鼠标右键] 追踪导弹; 弹体炮自动连射; [T] 直接锁定导航; [WASD+QE] 飞行, [Shift] 加力。"},
		{"sp": "EVA", "tx": "超级武器: [X] 湮灭光束 —— 充能 60 秒,释放后巨型光束随视角扫射 2 秒,范围杀伤随距离衰减。开局已充能完毕,找机群密集处试试!"},
		{"sp": "EVA", "tx": "语音指挥: 按住 [V] 对我说话,例如 调高音量 / 查看状态 / 打开轨道线 —— 指令完成后我会回复 收到,已完成。"},
	])
'''

with io.open(COMBAT, "r", encoding="utf-8") as f:
    t = f.read()

if "func _eva_ack" not in t:
    # 1) 应答面板变量
    anchor = "var _crowd_lod_dbg := 0"
    assert t.count(anchor) == 1
    i = t.index(anchor); e = t.index(NL, i) + 1
    t = t[:e] + ACK_VARS + t[e:]
    # 2) 面板 UI(挂在设施血条后)
    anchor2 = "_fac_bar_bg.add_child(_fac_bar)"
    assert t.count(anchor2) == 1
    i = t.index(anchor2); e = t.index(NL, i) + 1
    t = t[:e] + ACK_UI + t[e:]
    # 3) 淡出 tick
    anchor3 = chr(9) + chr(9) + "_fac_lbl.text = " + chr(34) + "雷达相阵 结构"
    assert t.count(anchor3) == 1, "fac label anchor not found"
    i = t.index(anchor3); e = t.index(NL, i) + 1
    t = t[:e] + ACK_TICK + t[e:]
    # 4) 终局时序
    assert t.count(FINALE_OLD) == 1, "finale block mismatch"
    t = t.replace(FINALE_OLD, FINALE_NEW)
    # 5) L1 引导接线
    anchor5 = chr(9) + "_eva_announce_key(" + chr(34) + "l1_start" + chr(34) + ", true)"
    assert t.count(anchor5) == 1, "l1_start anchor"
    i = t.index(anchor5); e = t.index(NL, i) + 1
    t = t[:e] + chr(9) + "get_tree().create_timer(6.0).timeout.connect(_l1_intro)   # v7.7:开场 6s 后背景介绍+教学" + NL + t[e:]
    # 6) BGM 增益
    old6 = "lerpf(-40.0, -11.0 if duck else -1.0"
    assert t.count(old6) == 1
    t = t.replace(old6, "lerpf(-40.0, -8.0 if duck else 3.0")
    # 7) 结算购买应答
    anchor7 = chr(9) + chr(9) + "hp = hp_max" + NL + chr(9) + chr(9) + "_result_lbl.text = _settlement_text()"
    assert t.count(anchor7) == 1, "buy anchor"
    t = t.replace(anchor7, anchor7 + NL + chr(9) + chr(9) + "_eva_ack(" + chr(34) + "强化模块已安装" + chr(34) + ")")
    # 8) 指令执行应答
    anchor8 = chr(9) + chr(9) + "print(" + chr(34) + "[CMDSRV] %s -> %s" + chr(34) + " % [ctype, res])"
    assert t.count(anchor8) == 1, "cmd anchor"
    t = t.replace(anchor8, anchor8 + NL + chr(9) + chr(9) + "_eva_ack()   # v7.7:EVA 指令应答")
    # 9) 新函数追加
    t = t.rstrip(NL) + NEW_FUNCS + NL
    with io.open(COMBAT, "w", encoding="utf-8", newline="") as f:
        f.write(t)
    print("OK combat")
else:
    print("skip combat")
print("ALL v7.7 PATCHED")

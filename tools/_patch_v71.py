# -*- coding: utf-8 -*-
# v7.1 patch: 通关判定/虫洞/无敌/BOSS/升级系统
import re, io, sys

import os

# 仓库根目录（本脚本位于 tools/ 下，故取其上一级）
BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMBAT = BASE + r"\solar_combat.gd"
PROPS = BASE + r"\solar_props.gd"
BAL = BASE + r"\data\balance.txt"

def apply(path, repls):
    with io.open(path, "r", encoding="utf-8") as f:
        t = f.read()
    for pat, rep, cnt in repls:
        found = len(re.findall(pat, t, re.S))
        if found == 0:
            print("skip (already applied?): %r" % pat[:50])
            continue
        if found != cnt:
            print("FAIL [%s] pattern %r expected %d found %d" % (path, pat[:60], cnt, found))
            sys.exit(1)
        t = re.sub(pat, rep, t, flags=re.S)
    with io.open(path, "w", encoding="utf-8", newline="") as f:
        f.write(t)
    print("OK %s (%d rules)" % (path, len(repls)))

# ---------- solar_combat.gd ----------
AB_VARS = ("var ab_fire := 0\t\t# 能力树·火力控制 档位(0-3):每档全伤害+12%\n"
"var ab_armor := 0\t\t# 能力树·装甲掌控 档位(0-3):每档HP上限+30\n"
"var ab_engine := 0\t\t# 能力树·矢量机动 档位(0-3):每档速度/加速+10%\n"
"var rf_weapon := 0\t\t# 改造·武器系统 档位(0-3):每档全伤害+15%\n"
"var rf_airframe := 0\t# 改造·机体结构 档位(0-3):每档HP上限+60\n"
"var rf_engine := 0\t\t# 改造·推进器   档位(0-3):每档速度/加速+15%\n")

BOSSVARS = ("var _boss_lbl: Label\nvar _boss_bar_bg: Panel\n"
"var _boss_bar: ColorRect\nvar _boss_notches: Array = []\n")

BOSS_UI = """\t# --- BOSS 血条(L3 BOSS战, 顶部居中, v7.1) ---
\t_boss_lbl = Label.new()
\t_boss_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
\t_boss_lbl.anchor_left = 0.5
\t_boss_lbl.anchor_right = 0.5
\t_boss_lbl.offset_left = -320
\t_boss_lbl.offset_right = 320
\t_boss_lbl.offset_top = 26
\t_boss_lbl.offset_bottom = 50
\t_boss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
\t_boss_lbl.add_theme_font_size_override("font_size", 16)
\t_boss_lbl.add_theme_color_override("font_color", Color(1.0, 0.62, 0.66))
\t_boss_lbl.add_theme_color_override("font_shadow_color", Color(0.35, 0.0, 0.05, 0.9))
\t_boss_lbl.add_theme_constant_override("shadow_offset_y", 2)
\t_boss_lbl.text = "⚠ 八棱柱集群 · 湮灭核心"
\t_boss_lbl.visible = false
\tlayer.add_child(_boss_lbl)
\t_boss_bar_bg = Panel.new()
\t_boss_bar_bg.set_anchors_preset(Control.PRESET_CENTER_TOP)
\t_boss_bar_bg.anchor_left = 0.5
\t_boss_bar_bg.anchor_right = 0.5
\t_boss_bar_bg.offset_left = -300
\t_boss_bar_bg.offset_right = 300
\t_boss_bar_bg.offset_top = 54
\t_boss_bar_bg.offset_bottom = 70
\tvar sbf := StyleBoxFlat.new()
\tsbf.bg_color = Color(0.04, 0.05, 0.10, 0.82)
\tsbf.border_color = Color(0.90, 0.25, 0.35, 0.85)
\tsbf.set_border_width_all(2)
\tsbf.set_corner_radius_all(6)
\t_boss_bar_bg.add_theme_stylebox_override("panel", sbf)
\t_boss_bar_bg.visible = false
\tlayer.add_child(_boss_bar_bg)
\t_boss_bar = ColorRect.new()
\t_boss_bar.color = Color(1.0, 0.28, 0.32)
\t_boss_bar.position = Vector2(3, 3)
\t_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
\t_boss_bar_bg.add_child(_boss_bar)
\tfor i in 9:
\t\tvar notch := ColorRect.new()
\t\tnotch.color = Color(0, 0, 0, 0.35)
\t\tnotch.size = Vector2(2, 12)
\t\tnotch.mouse_filter = Control.MOUSE_FILTER_IGNORE
\t\t_boss_bar_bg.add_child(notch)
\t\t_boss_notches.append(notch)
"""

BOSS_TICK = """\tif _boss_bar_bg != null:
\t\tvar bshow: bool = level == 3 and boss != null and is_instance_valid(boss) and phase == 1 and not dead
\t\t_boss_bar_bg.visible = bshow
\t\t_boss_lbl.visible = bshow
\t\tif bshow:
\t\t\tvar bf := clampf(core_hp / maxf(core_hp_max, 1.0), 0.0, 1.0)
\t\t\t_boss_bar.size = Vector2(maxf((_boss_bar_bg.size.x - 6.0) * bf, 0.0), _boss_bar_bg.size.y - 6.0)
\t\t\t_boss_bar.color = Color(1.0, 0.28, 0.32) if bf > 0.5 else (Color(1.0, 0.55, 0.18) if bf > 0.25 else Color(0.95, 0.20, 0.70))
\t\t\t_boss_lbl.text = "⚠ 八棱柱集群 · 湮灭核心  %d / %d" % [maxi(int(core_hp), 0), int(core_hp_max)]
\t\t\tfor k in _boss_notches.size():
\t\t\t\t(_boss_notches[k] as ColorRect).position = Vector2(3.0 + (k + 1) * (_boss_bar_bg.size.x - 6.0) / 10.0, 2.0)
"""

NEW_FUNCS = """
# ==================== v7.1 结算升级:能力树 + 改造升级(双轨分档) ====================
func _tier_str(t: int) -> String:
\tvar s := ""
\tfor i in 3:
\t\ts += "▰" if i < t else "▱"
\treturn s

func _ab_cost(t: int) -> int:
\treturn 80 * (t + 1)   # 能力树档位价:80/160/240

func _rf_cost(t: int) -> int:
\treturn 150 * (t + 1)  # 改造档位价:150/300/450

func _settlement_text() -> String:
\tvar mission_name := "歼灭战" if level == 1 else ("保卫战" if level == 2 else "BOSS战")
\tvar lines: Array = []
\tlines.append("══ 任 务 完 成 ══   第 %d 关 · %s" % [level, mission_name])
\tlines.append("击毁 %d    用时 %ds    持有资源 %d" % [kills, int(mission_time), parts])
\tlines.append("─".repeat(46))
\tlines.append("◆ 能力树(战斗领悟)")
\tlines.append("[1] 火力控制 %s  全伤害+12%%/档   需 %d" % [_tier_str(ab_fire), (0 if ab_fire >= 3 else _ab_cost(ab_fire))])
\tlines.append("[2] 装甲掌控 %s  HP上限+30/档     需 %d" % [_tier_str(ab_armor), (0 if ab_armor >= 3 else _ab_cost(ab_armor))])
\tlines.append("[3] 矢量机动 %s  速度+10%%/档      需 %d" % [_tier_str(ab_engine), (0 if ab_engine >= 3 else _ab_cost(ab_engine))])
\tlines.append("◆ 改造升级(机库档位)")
\tlines.append("[4] 武器系统 %s  全伤害+15%%/档   需 %d" % [_tier_str(rf_weapon), (0 if rf_weapon >= 3 else _rf_cost(rf_weapon))])
\tlines.append("[5] 机体结构 %s  HP上限+60/档     需 %d" % [_tier_str(rf_airframe), (0 if rf_airframe >= 3 else _rf_cost(rf_airframe))])
\tlines.append("[6] 推进器   %s  速度+15%%/档      需 %d" % [_tier_str(rf_engine), (0 if rf_engine >= 3 else _rf_cost(rf_engine))])
\tlines.append("─".repeat(46))
\tlines.append("当前: 伤害×%.2f   装甲 %d/%d   机动×%.2f" % [dmg_mult, hp, hp_max, speed_mult])
\tlines.append("[1-6] 购买强化(可连续)      [Enter] 跃迁下一关")
\treturn "\n".join(lines)

func _recalc_stats() -> void:
\tdmg_mult = 1.0 + 0.12 * float(ab_fire) + 0.15 * float(rf_weapon)
\thp_max = 100 + 30 * ab_armor + 60 * rf_airframe
\tspeed_mult = 1.0 + 0.10 * float(ab_engine) + 0.15 * float(rf_engine)
\thp = clampi(hp, 0, hp_max)

func _settlement_buy(idx: int) -> void:
\tvar bought := false
\tmatch idx:
\t\t1:
\t\t\tif ab_fire < 3 and parts >= _ab_cost(ab_fire):
\t\t\t\tparts -= _ab_cost(ab_fire)
\t\t\t\tab_fire += 1
\t\t\t\t_feed("◆ 能力树·火力控制 → 第 %d 档(全伤害 +12%%)" % ab_fire)
\t\t\t\tbought = true
\t\t2:
\t\t\tif ab_armor < 3 and parts >= _ab_cost(ab_armor):
\t\t\t\tparts -= _ab_cost(ab_armor)
\t\t\t\tab_armor += 1
\t\t\t\t_feed("◆ 能力树·装甲掌控 → 第 %d 档(HP 上限 +30)" % ab_armor)
\t\t\t\tbought = true
\t\t3:
\t\t\tif ab_engine < 3 and parts >= _ab_cost(ab_engine):
\t\t\t\tparts -= _ab_cost(ab_engine)
\t\t\t\tab_engine += 1
\t\t\t\t_feed("◆ 能力树·矢量机动 → 第 %d 档(速度 +10%%)" % ab_engine)
\t\t\t\tbought = true
\t\t4:
\t\t\tif rf_weapon < 3 and parts >= _rf_cost(rf_weapon):
\t\t\t\tparts -= _rf_cost(rf_weapon)
\t\t\t\trf_weapon += 1
\t\t\t\t_feed("🔧 改造·武器系统 → 第 %d 档(全伤害 +15%%)" % rf_weapon)
\t\t\t\tbought = true
\t\t5:
\t\t\tif rf_airframe < 3 and parts >= _rf_cost(rf_airframe):
\t\t\t\tparts -= _rf_cost(rf_airframe)
\t\t\t\trf_airframe += 1
\t\t\t\t_feed("🔧 改造·机体结构 → 第 %d 档(HP 上限 +60)" % rf_airframe)
\t\t\t\tbought = true
\t\t6:
\t\t\tif rf_engine < 3 and parts >= _rf_cost(rf_engine):
\t\t\t\tparts -= _rf_cost(rf_engine)
\t\t\t\trf_engine += 1
\t\t\t\t_feed("🔧 改造·推进器 → 第 %d 档(速度 +15%%)" % rf_engine)
\t\t\t\tbought = true
\tif bought:
\t\t_recalc_stats()
\t\thp = hp_max
\t\t_result_lbl.text = _settlement_text()
\telse:
\t\t_feed("无法购买(档位已满或资源不足)")
"""

combat_rules = [
 ("var god_mode := true",
  "var god_mode := false            # v7.1:默认关闭免伤 — 真实承伤(G 键仍可手动切换)", 1),
 (r"hp = mini\(hp \+ 20, hp_max\)",
  "hp = mini(hp + 5, hp_max)", 1),
 (r"fov_mul = lerpf\(fov_mul, 1\.35, clampf\(dt \* 1\.8, 0\.0, 1\.0\)\)",
  "fov_mul = lerpf(fov_mul, 1.0, clampf(dt * 2.5, 0.0, 1.0))  # v7.1:返航/虫洞不再改变视角(原机体缩小模拟已删)", 1),
 (r"fov_mul = lerpf\(fov_mul, 2\.1, clampf\(dt \* 2\.0, 0\.0, 1\.0\)\)\s*# 虫洞吸入感",
  "pass   # v7.1:虫洞吸入感(FOV 拉伸=机体缩小错觉)代码已删除", 1),
 (r"gate_stash\.position = arena_anchor \+ Vector3\(350, 54, -3460\)",
  "gate_stash.position = earth_pos + Vector3(-980.0, 300.0, 640.0)   # v7.1:虫洞核心移至近地轨道(约1.1km高度,与中转站同层)", 1),
 (r"sh\.radius = 90\.0",
  "sh.radius = 140.0   # v7.1:虫洞入口判定球=高斯球体内部", 1),
 (r"clampf\(900\.0 / maxf\(gs_ext, 0\.001\), 0\.5, 400\.0\)",
  "clampf(430.0 / maxf(gs_ext, 0.001), 0.25, 200.0)   # v7.1:虫洞尺寸收敛(展开约430m)", 1),
 (r"distance_to\(core\.global_position\) < 260\.0:",
  "distance_to(core.global_position) < 140.0:   # v7.1:飞入虫洞高斯球体内部=通关判定", 1),
 (r"(?m)^(\t*)core_hp -= int\(round\(dmg\)\)$",
  lambda m: m.group(1) + "if level <= 2:\n" + m.group(1) + "\treturn   # v7.1:L1/L2 虫洞入口不可破坏 —— 只能飞入球体内部通关\n" + m.group(1) + "core_hp -= int(round(dmg))", 1),
 (r"_wormhole_jump\(\)\s*# 兜底[^\n]*",
  "pass   # v7.1:打爆核心不再视为通关(进入虫洞内部才结算)", 1),
 ('2: ph = "结算 — \[1\]火力 \[2\]装甲 \[3\]引擎 / \[Enter\]直接跃迁"',
  '2: ph = "结算 — 能力树[1-3] 改造[4-6] / [Enter]跃迁"', 1),
 ('4: ph = "返航!进入中转站核心跃迁"',
  '4: ph = "返航!飞入虫洞球体内部即通关"', 1),
 (r'"l1_quota": 8\.0, "l2_quota": 10\.0, "l3_quota": 4\.0',
  '"l1_quota": 16.0, "l2_quota": 18.0, "l3_quota": 8.0', 1),
 (r'"quota_base": 8\.0, "quota_per_level": 2\.0, "survival_time": 90\.0',
  '"quota_base": 8.0, "quota_per_level": 2.0, "survival_time": 150.0', 1),
 (r"(var speed_mult := 1\.0\n)",
  lambda m: m.group(1) + "# ===== v7.1 双轨成长:能力树(战斗领悟) + 改造升级(机库档位), 各3档 =====\n" + AB_VARS, 1),
 (r"(var _fac_lbl: Label\n)",
  lambda m: m.group(1) + "# v7.1: BOSS 血条(L3 专用, 不再展示雷达相阵血条)\n" + BOSSVARS, 1),
 (r"(\t# --- 字幕条\(底部居中: 说话人 \+ 打字机文本 \+ 选项提示\) ---)",
  lambda m: BOSS_UI + m.group(1), 1),
 (r'(_fac_lbl\.text = "雷达相阵 结构[^\n]*\n\n?)',
  lambda m: m.group(1) + BOSS_TICK, 1),
 (r'_result_lbl\.text = "══.*?upgrade_cost"\)\]',
  '_result_lbl.text = _settlement_text()   # v7.1:能力树+改造 双轨升级界面', 1),
 (r'elif phase == 2 and event\.keycode in \[KEY_1, KEY_2, KEY_3\]:.*?_feed\("资源不足\(需要 %d\)" % _bi\("economy", "upgrade_cost"\)\)',
  lambda m: "\t\telif phase == 2 and event.keycode in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]:\n\t\t\t_settlement_buy(int(event.keycode) - int(KEY_0))   # v7.1:能力树[1-3]/改造[4-6], 可连续购买, Enter 跃迁", 1),
]

with io.open(COMBAT, "r", encoding="utf-8") as f:
    t = f.read()
if "_settlement_text" not in t:
    t = t.rstrip("\n") + "\n" + NEW_FUNCS
else:
    print("funcs already appended, skip")
with io.open(COMBAT, "w", encoding="utf-8", newline="") as f:
    f.write(t)
apply(COMBAT, combat_rules)

# ---------- solar_props.gd ----------
W_MATCH = """w = (w + 1) % 5
\t\t\tmatch w:
\t\t\t\t0:   # 环形弹幕(全方位扩散)
\t\t\t\t\tfor i in 14:
\t\t\t\t\t\tvar a0 := TAU * i / 14.0
\t\t\t\t\t\t_spawn_bolt(Vector3(cos(a0), 0.0, sin(a0)), Color(1.0, 0.4, 0.2))
\t\t\t\t\tw_t = 2.4
\t\t\t\t1:   # 双臂螺旋弹幕
\t\t\t\t\tfor i in 24:
\t\t\t\t\t\tvar a1 := TAU * i / 24.0 + tt
\t\t\t\t\t\tvar arm := 0.0 if i % 2 == 0 else PI
\t\t\t\t\t\t_spawn_bolt(Vector3(cos(a1 + arm), sin(a1 + arm) * 0.35, sin(a1 + arm)), Color(1.0, 0.7, 0.2))
\t\t\t\t\tw_t = 3.0
\t\t\t\t2:   # 主炮激光(持续照射)
\t\t\t\t\tlaser_t = 2.4
\t\t\t\t\tw_t = 3.8
\t\t\t\t3:   # 瞄准霰弹(直射玩家, 高速)
\t\t\t\t\tvar sp0 := (player - global_position).normalized()
\t\t\t\t\tfor i in 7:
\t\t\t\t\t\tvar sd := sp0.rotated(Vector3.UP, randf_range(-0.22, 0.22)).rotated(sp0.cross(Vector3.UP).normalized(), randf_range(-0.14, 0.14))
\t\t\t\t\t\t_spawn_bolt(sd.normalized(), Color(0.6, 0.9, 1.0), 210.0)
\t\t\t\t\tw_t = 2.0
\t\t\t\t4:   # 追踪鱼雷(缓慢转向, 高伤)
\t\t\t\t\tfor i in 4:
\t\t\t\t\t\tvar a4 := TAU * i / 4.0
\t\t\t\t\t\tvar tp := (player - global_position).normalized().rotated(Vector3.UP, a4)
\t\t\t\t\t\t_spawn_bolt(tp, Color(0.8, 0.5, 1.0), 55.0, true)
\t\t\t\t\tw_t = 3.4"""

HOMING = """mi.position += b["vel"] * dt
\t\t\t\tif b.get("home", false):
\t\t\t\t\tvar hd := (player - mi.global_position).normalized()
\t\t\t\t\tvar vvec: Vector3 = b["vel"]
\t\t\t\t\tb["vel"] = vvec.lerp(hd * vvec.length(), clampf(dt * 1.1, 0.0, 1.0))"""

props_rules = [
 (r"const BOLT_SPEED := 130\.0", "const BOLT_SPEED := 150.0", 1),
 (r"func _spawn_bolt\(dir: Vector3, col: Color\) -> void:",
  "func _spawn_bolt(dir: Vector3, col: Color, spd: float = BOLT_SPEED, home := false) -> void:", 1),
 (r'bolts\.append\(\{"mi": mi, "vel": dir \* BOLT_SPEED, "life": 7\.0\}\)',
  'bolts.append({"mi": mi, "vel": dir * spd, "life": 9.0, "home": home})', 1),
 (r"w = \(w \+ 1\) % 3.*?w_t = 4\.0", lambda m: W_MATCH, 1),
 (r"(?m)^(\t*)if laser_t > 0\.0:",
  lambda m: m.group(1) + "w_t *= 1.0 - 0.35 * (1.0 - hp_frac)   # v7.1:血量越低攻击节奏越快\n" + m.group(0), 1),
 (r"dmg \+= 30\.0 \* dt", "dmg += 42.0 * dt", 1),
 (r"perp\.length\(\) < 8\.0", "perp.length() < 11.0", 1),
 (r"cyl\.top_radius = 5\.0", "cyl.top_radius = 6.5", 1),
 (r"cyl\.bottom_radius = 5\.0", "cyl.bottom_radius = 6.5", 1),
 (r"if mi\.global_position\.distance_to\(player\) < 12\.0:",
  "if mi.global_position.distance_to(player) < 14.0:", 1),
 (r"dmg \+= 16\.0", "dmg += 22.0", 1),
 (r'mi\.position \+= b\["vel"\] \* dt', lambda m: HOMING, 1),
]
apply(PROPS, props_rules)

# ---------- balance.txt ----------
with io.open(BAL, "r", encoding="utf-8") as f:
    b = f.read()
for old, new in [("l1_quota = 8", "l1_quota = 16"), ("l2_quota = 10", "l2_quota = 18"),
                 ("l3_quota = 4", "l3_quota = 8"), ("survival_time = 90", "survival_time = 150")]:
    if b.count(old) != 1:
        print("FAIL balance: %r count=%d" % (old, b.count(old))); sys.exit(1)
    b = b.replace(old, new)
with io.open(BAL, "w", encoding="utf-8", newline="") as f:
    f.write(b)
print("OK balance.txt")
print("ALL PATCHED")

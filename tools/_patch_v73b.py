# -*- coding: utf-8 -*-
# v7.3: 取消回血 / 雷达阵承伤 / 弹体炮 / 激光增强 (literal-string version)
import io, re, sys

BASE = r"C:\Users\user\Desktop\ds harness\experiment\gdgs_lab"
COMBAT = BASE + r"\solar_combat.gd"
BAL = BASE + r"\data\balance.txt"
BS = chr(92)

def apply(path, pairs, regex_pairs):
    with io.open(path, "r", encoding="utf-8") as f:
        t = f.read()
    for old, new in pairs:
        n = t.count(old)
        if n != 1:
            print("FAIL [%s] literal %r count=%d" % (path, old[:60], n))
            sys.exit(1)
        t = t.replace(old, new)
    for pat, rep, cnt in regex_pairs:
        found = len(re.findall(pat, t, re.S))
        if found != cnt:
            print("FAIL [%s] regex %r expected %d found %d" % (path, pat[:60], cnt, found))
            sys.exit(1)
        t = re.sub(pat, rep, t, flags=re.S)
    with io.open(path, "w", encoding="utf-8", newline="") as f:
        f.write(t)
    print("OK %s" % path)

BOLT_FN = """

# ==================== v7.3 弹体炮:敌机同款实体弹(主武器火力补充) ====================
func _fire_bolts() -> void:
	if dead or bolt_cd > 0.0:
		return
	var tgt: Object = null
	if hover_enemy != null and is_instance_valid(hover_enemy) and (hover_enemy as Enemy).hp > 0:
		tgt = hover_enemy
	elif lock_target != null and is_instance_valid(lock_target):
		tgt = lock_target
	elif lock_valid and core != null and is_instance_valid(core):
		tgt = core
	bolt_cd = _b("playergun", "fire_interval")
	var from := cam.global_position - cam.basis.z * 1.6
	var dir: Vector3
	if tgt is Node3D:
		dir = ((tgt as Node3D).global_position - from).normalized()
	else:
		dir = _aim_dir()
	var mi := _bolt_acquire(_bolt_pool_w, from, _bolt_mat_res())   # 敌机同款弹体(红色曳光)
	mi.look_at(from + dir * 10.0, Vector3.UP)
	friendly_bolts.append({"mi": mi, "vel": dir * _b("playergun", "speed"), "life": _b("playergun", "life"), "tgt": tgt, "dmg": _b("playergun", "damage") * dmg_mult})
	_play_sfx("cannon", -14.0, 1.6)
"""

OLD_REGEN = """	if not dead and hp < hp_max:
		hp = mini(hp + 5, hp_max)  # 近似无限自回血:20/s,免伤关闭后仍兜底
"""
NEW_REGEN = """	# v7.3:取消自动回血 —— 结构完整度只在结算/购买装甲时修复
"""

OLD_TB = '''		var tb = b.get("tgt")   # 只判自己的目标: O(弹x敌) -> O(弹), 压测帧率保护
		if tb != null and is_instance_valid(tb) and tb.hp > 0 and _point_line_dist(tb.global_position, prev, cur) < 4.0:
			_damage_enemy(tb, dmg)
			_hit_sparks(cur, Color(0.5, 0.9, 1.0))
			consumed = true
'''
NEW_TB = '''		var tb = b.get("tgt")   # 只判自己的目标: O(弹x敌) -> O(弹), 压测帧率保护
		var dmg2: float = float(b.get("dmg", dmg))   # v7.3:弹体炮弹自带伤害
		if tb == core and core != null and is_instance_valid(core) and _point_line_dist(core.global_position, prev, cur) < 100.0:
			_damage_core(dmg2)
			_hit_sparks(cur, Color(1.0, 0.45, 0.3))
			consumed = true
		elif tb != null and is_instance_valid(tb) and tb.hp > 0 and _point_line_dist(tb.global_position, prev, cur) < 4.0:
			_damage_enemy(tb, dmg2)
			_hit_sparks(cur, Color(0.5, 0.9, 1.0))
			consumed = true
'''

RE_CANNON = "(?m)^(" + BS + "t*)_fire_cannon" + BS + "(" + BS + ")" + chr(13) + "?$"

combat_pairs = [
 (OLD_REGEN, NEW_REGEN),
 ("var spread_cd := 0.0          # v0.8:散弹炮装填\n",
  "var spread_cd := 0.0          # v0.8:散弹炮装填\nvar bolt_cd := 0.0              # v7.3:弹体炮射击间隔\n"),
 ("spread_cd = maxf(spread_cd - dt, 0.0)",
  """spread_cd = maxf(spread_cd - dt, 0.0)
	bolt_cd = maxf(bolt_cd - dt, 0.0)"""),
 (OLD_TB, NEW_TB),
 ('"core": { "hp_base": 12000.0, "hp_per_level": 4000.0 }',
  '"core": { "hp_base": 18000.0, "hp_per_level": 6000.0 }'),
 ('''"firecontrol": { "auto_cone": 30.0 },
''',
  '''"firecontrol": { "auto_cone": 30.0 },
		"playergun": { "damage": 22.0, "fire_interval": 0.18, "speed": 520.0, "life": 3.0 },   # v7.3:弹体炮(敌机同款弹体)
'''),
 ('"raid_interval": 9.0, "raid_base": 40.0, "raid_per_enemy": 10.0',
  '"raid_interval": 8.0, "raid_base": 40.0, "raid_per_enemy": 1.5'),
]

combat_regex = [
 (RE_CANNON,
  lambda m: m.group(0) + chr(10) + m.group(1) + "_fire_bolts()   # v7.3:弹体炮", 2),
]

with io.open(COMBAT, "r", encoding="utf-8") as f:
    t = f.read()
if "_fire_bolts" not in t:
    t = t.rstrip(chr(10)) + BOLT_FN + chr(10)
    with io.open(COMBAT, "w", encoding="utf-8", newline="") as f:
        f.write(t)
else:
    print("bolt fn exists, skip")
apply(COMBAT, combat_pairs, combat_regex)

PGUN = """[playergun]           # v7.3 弹体炮: 敌机同款实体弹, 自动/手动与机炮同步开火
damage = 22           # 单发伤害(x dmg_mult)
fire_interval = 0.18  # 射击间隔(秒) -> ~5.6 发/s
speed = 520           # 弹速(m/s)
life = 3.0            # 弹体存活(秒), 有效射程 ~1.5km

"""
bal_pairs = [
 ("dps = 150", "dps = 220"),
 ("hp_base = 12000", "hp_base = 18000"),
 ("hp_per_level = 4000", "hp_per_level = 6000"),
 ("raid_interval = 14.0", "raid_interval = 8.0"),
 ("raid_base = 25", "raid_base = 40"),
 ("raid_per_enemy = 0.5", "raid_per_enemy = 1.5"),
 ("[firecontrol]", PGUN + "[firecontrol]"),
]
apply(BAL, bal_pairs, [])
print("ALL v7.3 PATCHED")

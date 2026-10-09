# -*- coding: utf-8 -*-
# v7.4 line-based patch (no regex)
import io

BASE = r"C:\Users\user\Desktop\ds harness\experiment\gdgs_lab"
COMBAT = BASE + "\solar_combat.gd"
BAL = BASE + "/data/balance.txt"
NL = chr(10)
Q = chr(34)

MEGA_VARS = """var mega_cd := 0.0                # v7.4 mega beam charge left (0=ready)
var mega_t := -1.0               # v7.4 beam active timer (-1=off)
var mega_p_t := 0.0              # v7.4 damage pulse timer
var mega_mi: MeshInstance3D = null   # v7.4 beam mesh
"""

MEGA_WIRE = """		if not dead and mega_t < 0.0 and mega_cd > 0.0:
			mega_cd = maxf(mega_cd - dt, 0.0)
			if mega_cd <= 0.0:
				_feed("MEGA READY [X]")
				_play_sfx("lock", -2.0)
		if mega_t >= 0.0:
			_mega_tick(dt)
"""

MEGA_INPUT = """		elif event.keycode == KEY_X:
			_mega_fire()   # v7.4 mega beam
"""

MEGA_FN = '''

# ==================== v7.4 mega beam ====================
func _mega_fire() -> void:
	if dead or mega_t >= 0.0:
		return
	if mega_cd > 0.0:
		_feed("mega charging %d%%" % int(100.0 * (1.0 - mega_cd / _b("megabeam", "cooldown"))))
		return
	mega_t = 0.0
	mega_p_t = 0.0
	_play_sfx("gate", -2.0, 0.7)
	_play_sfx("explode_big", -4.0, 0.6)
	_feed("MEGA BEAM FIRE")
	mega_mi = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = _b("megabeam", "radius")
	cyl.bottom_radius = _b("megabeam", "radius")
	cyl.height = _b("megabeam", "range")
	cyl.radial_segments = 24
	mega_mi.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.70, 0.90, 1.0, 0.85)
	m.emission_enabled = true
	m.emission = Color(0.80, 0.95, 1.0)
	m.emission_energy_multiplier = 6.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mega_mi.material_override = m
	add_child(mega_mi)
	shake = 1.2

func _mega_tick(dt: float) -> void:
	mega_t += dt
	var dir := -cam.basis.z
	var from := cam.global_position
	var R := _b("megabeam", "range")
	if mega_mi == null or not is_instance_valid(mega_mi):
		mega_t = -1.0
		return
	mega_mi.global_position = from + dir * (R * 0.5)
	mega_mi.look_at(from + dir * R, Vector3.UP)
	mega_mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	var breath := 1.0 + 0.15 * sin(fx_time * 30.0)
	mega_mi.scale = Vector3(breath, 1.0, breath)
	mega_p_t -= dt
	if mega_p_t <= 0.0:
		mega_p_t = 0.1
		var dps := _b("megabeam", "dps") * dmg_mult
		var far_r := _b("megabeam", "far_range")
		var far_f := _b("megabeam", "far_factor")
		var rad := _b("megabeam", "radius")
		for e in enemies:
			if is_instance_valid(e) and (e as Enemy).hp > 0:
				var rel: Vector3 = (e as Node3D).global_position - from
				var along := rel.dot(dir)
				if along > 0.0 and along < R:
					var perp := (rel - dir * along).length()
					if perp < rad + 12.0:
						var mul := 1.0 if along < far_r else far_f
						_damage_enemy(e, dps * 0.1 * mul)
						if randf() < 0.2:
							_hit_sparks((e as Node3D).global_position, Color(0.8, 0.95, 1.0))
		if core != null and is_instance_valid(core):
			var relc: Vector3 = core.global_position - from
			var alongc := relc.dot(dir)
			if alongc > 0.0 and alongc < R:
				var perpc := (relc - dir * alongc).length()
				if perpc < rad + 100.0:
					var mulc := 1.0 if alongc < far_r else far_f
					_damage_core(dps * 0.1 * mulc * _b("megabeam", "core_mult"))
	if mega_t >= _b("megabeam", "duration"):
		mega_t = -1.0
		mega_cd = _b("megabeam", "cooldown")
		mega_mi.queue_free()
		mega_mi = null
		_feed("mega beam spent, recharge %ds" % int(_b("megabeam", "cooldown")))
'''

MEGA_DFLT = Q + "megabeam" + Q + ": { " + Q + "cooldown" + Q + ": 60.0, " + Q + "duration" + Q + ": 2.0, " + Q + "dps" + Q + ": 4000.0, " + Q + "range" + Q + ": 4000.0, " + Q + "radius" + Q + ": 14.0, " + Q + "far_range" + Q + ": 1500.0, " + Q + "far_factor" + Q + ": 0.35, " + Q + "core_mult" + Q + ": 2.0 },"

MEGA_BAL = "[megabeam]\ncooldown = 60\nduration = 2.0\ndps = 4000\nrange = 4000\nradius = 14\nfar_range = 1500\nfar_factor = 0.35\ncore_mult = 2.0\n\n"

def find_idx(lines, needle, start=0):
    for i in range(start, len(lines)):
        if needle in lines[i]:
            return i
    return -1

with io.open(COMBAT, "r", encoding="utf-8") as f:
    t = f.read()

if "_mega_fire" not in t:
    lines = t.split(NL)
    i = find_idx(lines, "var bolt_cd :=")
    assert i >= 0
    lines[i+1:i+1] = MEGA_VARS.rstrip(NL).split(NL)
    i = find_idx(lines, "_tick_laser(dt)")
    assert i >= 0
    lines[i+1:i+1] = MEGA_WIRE.rstrip(NL).split(NL)
    i = find_idx(lines, "elif event.keycode == KEY_G:")
    assert i >= 0
    j = find_idx(lines, "_feed(", i)
    assert j >= 0 and j - i <= 3
    lines[j+1:j+1] = MEGA_INPUT.rstrip(NL).split(NL)
    i = find_idx(lines, Q + "playergun" + Q + ": {")
    assert i >= 0
    lines[i+1:i+1] = [chr(9) + chr(9) + MEGA_DFLT]
    t = NL.join(lines).rstrip(NL) + MEGA_FN + NL
    with io.open(COMBAT, "w", encoding="utf-8", newline="") as f:
        f.write(t)
    print("OK combat")
else:
    print("skip combat")

with io.open(BAL, "r", encoding="utf-8") as f:
    b = f.read()
if "megabeam" not in b:
    assert b.count("[firecontrol]") == 1
    b = b.replace("[firecontrol]", MEGA_BAL.replace("\\n", NL) + "[firecontrol]")
    with io.open(BAL, "w", encoding="utf-8", newline="") as f:
        f.write(b)
    print("OK balance")
else:
    print("skip balance")
print("ALL v7.4 PATCHED")

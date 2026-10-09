extends Node3D
## 探针 v7: 修改后视觉验收 — 出生/贴地/木星/太阳(autopilot 关闭,视角不再被拽)
var game: Node3D
var cam: Camera3D
var t := 0.0
var step := 0
var spawn_pos := Vector3.ZERO
var jup := Vector3.ZERO

func _ready() -> void:
	process_priority = 100
	game = (load("res://solar_combat.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	cam = _find_cam(self)
	game.autopilot = false   # 关直接锁定导航,探针自己控制视角
	spawn_pos = cam.global_position
	for sp in game.splat_planets:
		if float(sp["radius"]) > 700.0:
			jup = (sp["near"] as Node3D).global_position
	print("PROBE7 spawn=%s jupiter=%s d_jup=%.0fm" % [str(spawn_pos), str(jup), spawn_pos.distance_to(jup)])
	_ang_report()

func _aim_at(target: Vector3) -> void:
	var d := (target - cam.global_position).normalized()
	game._pitch = asin(clampf(d.y, -1.0, 1.0))
	game._yaw = atan2(-d.x, -d.z)

func _ang_report() -> void:
	var vs: float = game._b("enemy", "visual_size")
	for e in game.enemies:
		if is_instance_valid(e):
			var d: float = cam.global_position.distance_to((e as Node3D).global_position)
			var ang := rad_to_deg(2.0 * atan(vs * 0.5 / maxf(d, 0.1)))
			print("  enemy d=%.0fm -> 视角径 %.2f° ≈ %.0f px" % [d, ang, ang / 70.0 * 720.0])
			break

func _process(dt: float) -> void:
	t += dt
	match step:
		0:
			if t >= 2.0: step = 1; _shot("res://shots/v7_a_spawn.png")
		1:
			if t >= 3.5:
				step = 2
				var ep: Vector3 = game.earth_pos
				var dir: Vector3 = (spawn_pos - ep).normalized()
				cam.position = ep + dir * 150.0
				_aim_at(ep)
		2:
			if t >= 5.0: step = 3; _shot("res://shots/v7_b_earth150.png")
		3:
			if t >= 6.5:
				step = 4
				var ep2: Vector3 = game.earth_pos
				var dir2: Vector3 = (spawn_pos - ep2).normalized()
				cam.position = ep2 + dir2 * 64.0
				_aim_at(ep2)
		4:
			if t >= 8.0: step = 5; _shot("res://shots/v7_c_earth64.png")
		5:
			if t >= 9.5:
				step = 6
				cam.position = spawn_pos
				_aim_at(jup)
		6:
			if t >= 11.0: step = 7; _shot("res://shots/v7_d_jupiter.png")
		7:
			if t >= 12.5:
				step = 8
				_aim_at(Vector3.ZERO)
		8:
			if t >= 14.0:
				step = 9
				_shot("res://shots/v7_e_sun.png")
				print("PROBE7-DONE")
				get_tree().quit()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	var s := 0.0
	var n := 0
	var cy := int(img.get_height() * 0.5)
	var cx := int(img.get_width() * 0.5)
	for y in range(cy - 120, cy + 120, 2):
		for x in range(cx - 120, cx + 120, 2):
			var p: Color = img.get_pixel(x, y)
			s += p.r * 0.3 + p.g * 0.6 + p.b * 0.1
			n += 1
	print("SHOT %s center240=%.3f" % [path.get_file(), s / float(n)])

func _find_cam(n: Node) -> Camera3D:
	if n is Camera3D: return n as Camera3D
	for c in n.get_children():
		var r := _find_cam(c)
		if r != null: return r
	return null

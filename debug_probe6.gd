extends Node3D
## 探针 v6: 地球渲染差分测试 — 显示/隐藏 splat 节点前后截图对比
var game: Node3D
var cam: Camera3D
var t := 0.0
var step := 0
var spawn_pos := Vector3.ZERO

func _ready() -> void:
	process_priority = 100
	game = (load("res://solar_combat.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	cam = _find_cam(self)
	spawn_pos = cam.global_position

func _set_earth(vis: bool) -> void:
	var ep: Vector3 = game.earth_pos
	for sp in game.splat_planets:
		var n: Node3D = sp["near"]
		if n.global_position.distance_to(ep) < 1.0:
			n.visible = vis
			(sp["far"] as Node3D).visible = false
			print("  earth nodes -> vis=%s (ang=%.1f deg)" % [str(vis), _earth_ang()])

func _earth_ang() -> float:
	var ep: Vector3 = game.earth_pos
	var r: float = 63.7
	return rad_to_deg(asin(clampf(r / maxf(ep.distance_to(cam.global_position), r + 0.1), 0.0, 1.0)))

func _process(dt: float) -> void:
	t += dt
	match step:
		0:
			if t >= 2.0: step = 1; _shot("res://shots/dbg6_spawn_on.png")
		1:
			if t >= 3.0: step = 2; _set_earth(false); _shot("res://shots/dbg6_spawn_off.png")
		2:
			if t >= 4.0:
				step = 3
				_set_earth(true)
				var ep: Vector3 = game.earth_pos
				var dir: Vector3 = (spawn_pos - ep).normalized()
				cam.position = ep + dir * 150.0
				print("  moved to 150m, aim yaw=%.2f pitch=%.2f" % [float(game._yaw), float(game._pitch)])
		3:
			if t >= 5.0: step = 4; _shot("res://shots/dbg6_d150_on.png")
		4:
			if t >= 6.0: step = 5; _set_earth(false); _shot("res://shots/dbg6_d150_off.png")
		5:
			if t >= 7.0:
				print("PROBE6-DONE rot=%s vel? yaw=%.3f pitch=%.3f" % [str(cam.rotation), float(game._yaw), float(game._pitch)])
				get_tree().quit()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	var cy := int(img.get_height() * 0.5)
	var cx := int(img.get_width() * 0.5)
	var s := 0.0
	var n := 0
	var blue := 0
	for y in range(cy - 120, cy + 120, 2):
		for x in range(cx - 120, cx + 120, 2):
			var p: Color = img.get_pixel(x, y)
			s += p.r * 0.3 + p.g * 0.6 + p.b * 0.1
			if p.b > p.r + 0.08 and p.b > 0.25:
				blue += 1
			n += 1
	print("SHOT %s center240=%.3f blue_frac=%.3f" % [path.get_file(), s / float(n), float(blue) / float(n)])

func _find_cam(n: Node) -> Camera3D:
	if n is Camera3D: return n as Camera3D
	for c in n.get_children():
		var r := _find_cam(c)
		if r != null: return r
	return null

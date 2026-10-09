extends Node3D
## 探针 v5: 隔离测试 — 时间 vs 相机位移 vs 状态破坏
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
	print("PROBE5 spawn=%s earth=%s d=%.0f" % [str(spawn_pos), str(game.earth_pos), game.earth_pos.distance_to(spawn_pos)])

func _process(dt: float) -> void:
	t += dt
	match step:
		0:
			if t >= 1.2: step = 1; _shot("res://shots/dbg5_t12_spawn.png")
		1:
			if t >= 3.0: step = 2; _shot("res://shots/dbg5_t30_spawn.png")
		2:
			if t >= 4.5:
				step = 3
				var ep: Vector3 = game.earth_pos
				var dir: Vector3 = (spawn_pos - ep).normalized()
				cam.position = ep + dir * 400.0
				_shot("res://shots/dbg5_d400.png")
		3:
			if t >= 6.0:
				step = 4
				var ep2: Vector3 = game.earth_pos
				var dir2: Vector3 = (spawn_pos - ep2).normalized()
				cam.position = ep2 + dir2 * 150.0
				_shot("res://shots/dbg5_d150.png")
		4:
			if t >= 7.5:
				step = 5
				cam.position = spawn_pos
				_shot("res://shots/dbg5_back_spawn.png")
		5:
			if t >= 9.0:
				print("PROBE5-DONE")
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
	print("SHOT %s center240=%.1f cam=%s d_earth=%.0f" % [path.get_file(), s / float(n), str(cam.position), game.earth_pos.distance_to(cam.position)])

func _find_cam(n: Node) -> Camera3D:
	if n is Camera3D: return n as Camera3D
	for c in n.get_children():
		var r := _find_cam(c)
		if r != null: return r
	return null

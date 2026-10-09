extends Node3D
## 诊断探针 v2: 视野角度对比(朝地球/背对地球)+ P1 gate 可见性验证

var game: Node3D
var cam: Camera3D
var t := 0.0
var step := 0

func _ready() -> void:
	process_priority = 100
	game = (load("res://solar_combat.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	cam = _find_cam(self)
	print("PROBE2 start yaw=%.2f pitch=%.2f" % [float(game._yaw), float(game._pitch)])

func _process(dt: float) -> void:
	t += dt
	match step:
		0:
			if t >= 2.5:
				step = 1
				_shot("res://shots/dbg2_a_spawn_earth.png")
		1:
			if t >= 4.0:
				step = 2
				game._yaw += PI  # 掉头,背对地球
		2:
			if t >= 5.5:
				step = 3
				_shot("res://shots/dbg2_b_back_away.png")
		3:
			if t >= 7.0:
				step = 4
				game._open_gate()
				print("PROBE2 gate opened, enemies=%d" % [int((game.enemies as Array).size())])
		4:
			if t >= 8.5:
				step = 5
				var gp: Vector3 = game.gate.global_position
				var ap: Vector3 = game.arena_anchor
				var d := ap.distance_to(gp)
				var dir := (gp - ap).normalized()
				game._pitch = asin(clampf(dir.y, -1.0, 1.0))
				game._yaw = atan2(-dir.x, -dir.z)
				var gres = game.gate.gaussian
				print("PROBE2 gate pos=%s dist_from_anchor=%.0fm scale=%s aabb=%s pts=%s" % [str(gp), d, str(game.gate.scale), str(gres.aabb), str(gres.point_count)])
				_shot("res://shots/dbg2_c_gate_from_spawn.png")
		5:
			if t >= 10.0:
				step = 6
				var gp2: Vector3 = game.gate.global_position
				var back: Vector3 = (game.arena_anchor - gp2).normalized()
				cam.position = gp2 + back * 260.0 + Vector3.UP * 40.0
				game._pitch = asin(clampf(-back.y, -1.0, 1.0))
				game._yaw = atan2(back.x, back.z)
		6:
			if t >= 11.5:
				step = 7
				_shot("res://shots/dbg2_d_gate_close.png")
				print("PROBE2-DONE")
				get_tree().quit()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	var s := 0.0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var p: Color = img.get_pixel(x, y)
			s += p.r * 0.3 + p.g * 0.6 + p.b * 0.1
			n += 1
	print("SHOT %s mean=%.4f" % [path.get_file(), s / float(maxi(n, 1))])
	var w := 64
	var h := int(float(img.get_height()) * 64.0 / float(img.get_width()) * 0.5)
	for yy in range(h):
		var row := ""
		for xx in range(w):
			var p2: Color = img.get_pixel(int(float(xx) * float(img.get_width()) / float(w)), int(float(yy) * float(img.get_height()) / float(h)))
			var v2 := p2.r * 0.3 + p2.g * 0.6 + p2.b * 0.1
			row += " .:-=+*#%@"[clampi(int(v2 * 10.0), 0, 9)]
		print(row)

func _find_cam(n: Node) -> Camera3D:
	if n is Camera3D:
		return n as Camera3D
	for c in n.get_children():
		var r := _find_cam(c)
		if r != null:
			return r
	return null

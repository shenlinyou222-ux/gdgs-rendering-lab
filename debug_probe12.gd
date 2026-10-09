extends Node3D
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
	game.autopilot = false
	var jp: Vector3 = game.jupiter_pos
	print("PROBE12 earth_d=%.0f jup_d=%.0f sun_d=%.0f" % [game.earth_pos.distance_to(cam.global_position), jp.distance_to(cam.global_position), cam.global_position.length()])
	print("PROBE12 角径: 地球 %.1f° 木星 %.2f° 太阳 %.1f°" % [rad_to_deg(asin(100.0 / game.earth_pos.distance_to(cam.global_position))), rad_to_deg(asin(1121.0 / maxf(jp.distance_to(cam.global_position), 1.0))), rad_to_deg(asin(10920.0 / cam.global_position.length()))])

func _aim_at(target: Vector3) -> void:
	var d := (target - cam.global_position).normalized()
	game._pitch = asin(clampf(d.y, -1.0, 1.0))
	game._yaw = atan2(-d.x, -d.z)

func _process(dt: float) -> void:
	t += dt
	match step:
		0:
			if t >= 2.0: step = 1; _shot("res://shots/v12_earth.png")
		1:
			if t >= 3.5: step = 2; _aim_at(Vector3.ZERO)
		2:
			if t >= 5.0: step = 3; _shot("res://shots/v12_sun.png")
		3:
			if t >= 6.5: step = 4; _aim_at(game.jupiter_pos)
		4:
			if t >= 8.0: step = 5; _shot("res://shots/v12_jupiter.png")
		5:
			if t >= 9.0:
				print("PROBE12-DONE")
				get_tree().quit()

func _shot(p: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(p)
	var s := 0.0
	var n := 0
	var cy := int(img.get_height() * 0.5)
	var cx := int(img.get_width() * 0.5)
	for y in range(cy - 100, cy + 100, 2):
		for x in range(cx - 100, cx + 100, 2):
			var c: Color = img.get_pixel(x, y)
			s += c.r * 0.3 + c.g * 0.6 + c.b * 0.1
			n += 1
	print("SHOT %s center200=%.3f" % [p.get_file(), s / float(n)])

func _find_cam(n: Node) -> Camera3D:
	if n is Camera3D: return n as Camera3D
	for c in n.get_children():
		var r := _find_cam(c)
		if r != null: return r
	return null

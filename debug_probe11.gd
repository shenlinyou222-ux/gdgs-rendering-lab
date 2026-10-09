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

func _aim_at(target: Vector3) -> void:
	var d := (target - cam.global_position).normalized()
	game._pitch = asin(clampf(d.y, -1.0, 1.0))
	game._yaw = atan2(-d.x, -d.z)

func _process(dt: float) -> void:
	t += dt
	match step:
		0:
			if t >= 2.0: step = 1; _shot("res://shots/v11_spawn_earth.png")
		1:
			if t >= 3.5:
				step = 2
				_aim_at(Vector3.ZERO)   # 朝太阳(原点)
		2:
			if t >= 5.0: step = 3; _shot("res://shots/v11_sun.png")
		3:
			if t >= 6.0:
				print("PROBE11-DONE")
				get_tree().quit()

func _shot(p: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(p)
	var mx := 0.0
	var s := 0.0
	var n := 0
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			var c: Color = img.get_pixel(x, y)
			var v := c.r * 0.3 + c.g * 0.6 + c.b * 0.1
			s += v
			if v > mx: mx = v
			n += 1
	print("SHOT %s mean=%.3f max=%.3f" % [p.get_file(), s / float(n), mx])

func _find_cam(n: Node) -> Camera3D:
	if n is Camera3D: return n as Camera3D
	for c in n.get_children():
		var r := _find_cam(c)
		if r != null: return r
	return null

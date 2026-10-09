extends Node3D
var game: Node3D
var cam: Camera3D
var t := 0.0

func _ready() -> void:
	process_priority = 100
	game = (load("res://solar_combat.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	cam = _find_cam(self)
	game.autopilot = false

func _process(dt: float) -> void:
	t += dt
	if t >= 2.5:
		_shot()
		print("PROBE10-DONE")
		get_tree().quit()

func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/v10_spawn.png")
	var s := 0.0
	var n := 0
	var cy := int(img.get_height() * 0.5)
	var cx := int(img.get_width() * 0.5)
	for y in range(cy - 150, cy + 150, 2):
		for x in range(cx - 150, cx + 150, 2):
			var p: Color = img.get_pixel(x, y)
			s += p.r * 0.3 + p.g * 0.6 + p.b * 0.1
			n += 1
	print("SHOT v10_spawn center300=%.3f" % (s / float(n)))

func _find_cam(n: Node) -> Camera3D:
	if n is Camera3D: return n as Camera3D
	for c in n.get_children():
		var r := _find_cam(c)
		if r != null: return r
	return null

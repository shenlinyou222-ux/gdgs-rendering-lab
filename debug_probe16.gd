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
	if t >= 3.0:
		var vm := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED))
		var tm := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED))
		print("IN-GAME VMEM = %d MB, TEXTURE_MEM = %d MB" % [vm / 1048576, tm / 1048576])
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://shots/v16_spawn.png")
		var cy := int(img.get_height() * 0.5)
		var cx := int(img.get_width() * 0.5)
		var sl := 0.0
		var sr := 0.0
		var n := 0
		for y in range(cy - 80, cy + 80, 2):
			for x in range(cx - 140, cx + 140, 2):
				var p: Color = img.get_pixel(x, y)
				var v := p.r * 0.3 + p.g * 0.6 + p.b * 0.1
				if x < cx: sl += v
				else: sr += v
				n += 1
		print("SHOT spawn 左半=%.3f 右半=%.3f(有晨昏线则两侧应明显不等)" % [sl / n, sr / n])
		print("PROBE16-DONE")
		get_tree().quit()

func _find_cam(n: Node) -> Camera3D:
	if n is Camera3D: return n as Camera3D
	for c in n.get_children():
		var r := _find_cam(c)
		if r != null: return r
	return null

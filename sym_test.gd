extends Node3D
## 半镜对称 A/B: 原件 @z=-45 vs 对称件 @z=+45, 同机位对比 + 缝特写
func _ready() -> void:
	var orig := GaussianSplatNode.new(); add_child(orig)
	orig.gaussian = load("res://assets/hy_cell01.ply")
	orig.position = Vector3(0, 0, -45)
	var sym := GaussianSplatNode.new(); add_child(sym)
	sym.gaussian = load("res://assets/hy_cell01_sym.ply")
	sym.position = Vector3(0, 0, 45)
	print("orig+sym 就绪")

	var cam := Camera3D.new(); cam.fov = 60.0; add_child(cam)
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw

	cam.position = Vector3(0, 4, -3)
	await _shot("sym_00_original.png", cam, Vector3(0, 0, -45))
	cam.position = Vector3(0, 4, 3)
	await _shot("sym_01_symmetric.png", cam, Vector3(0, 0, 45))
	cam.position = Vector3(0.06, 2, 27); cam.fov = 55.0
	await _shot("sym_02_seam.png", cam, Vector3(0.06, 0, 45))
	get_tree().quit()

func _shot(name: String, cam: Camera3D, target: Vector3) -> void:
	cam.look_at(target, Vector3.UP)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/" + name)
	var s := 0.0; var s2 := 0.0; var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var p: Color = img.get_pixel(x, y)
			var v: float = p.r * 0.3 + p.g * 0.6 + p.b * 0.1
			s += v; s2 += v * v; n += 1
	var mean: float = s / n
	print("SHOT ", name, " mean=", "%.3f" % mean, " std=", "%.3f" % sqrt(max(s2 / n - mean * mean, 0.0)))

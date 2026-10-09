extends Node3D
## 双 splat 物体组合验证: bonsai(3.7m,MIT) + HY-World(28m) 同场景
func _ready() -> void:
	# 物体A: HY-World 贴片, 原生28m, 放在 +45m
	var res_a: GaussianResource = load("res://assets/hy_cell01.ply")
	var a := GaussianSplatNode.new()
	add_child(a)
	a.gaussian = res_a
	a.position = Vector3(45, 0, 0)
	print("A(hy_world): points=", res_a.point_count, " aabb=", res_a.aabb)

	# 物体B: bonsai, 原生~3.7m, 缩放x2 放在原点
	var res_b: GaussianResource = load("res://assets/demo.compressed.ply")
	var b := GaussianSplatNode.new()
	add_child(b)
	b.gaussian = res_b
	b.scale = Vector3(2, 2, 2)
	print("B(bonsai): points=", res_b.point_count, " aabb=", res_b.aabb)

	var cam := Camera3D.new()
	add_child(cam)
	for i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	# 机位1: 双物体全景(从侧面看两者)
	cam.position = Vector3(22, 6, 48)
	cam.fov = 60.0
	await _shot("two_splats_00.png", cam, Vector3(22, 2, 0))
	# 机位2: B 在前遮挡 A(深度交互)
	cam.position = Vector3(2, 3, 12)
	await _shot("two_splats_01.png", cam, Vector3(45, 0, 0))
	# 机位3: A 前 B 后(反序)
	cam.position = Vector3(45, 3, 20)
	await _shot("two_splats_02.png", cam, Vector3(0, 2, 0))
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

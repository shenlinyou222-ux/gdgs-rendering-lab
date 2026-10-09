extends Node3D
## 镜像拼接验证: 原件 + 数据级镜像(万花筒缝) + 负scale懒人法对照
func _ready() -> void:
	var a: GaussianResource = load("res://assets/hy_cell01.ply")
	var orig := GaussianSplatNode.new()
	add_child(orig)
	orig.gaussian = a
	print("orig: ", a.point_count, " aabb=", a.aabb)

	var m: GaussianResource = load("res://assets/hy_cell01_mirror.ply")
	var mir := GaussianSplatNode.new()
	add_child(mir)
	mir.gaussian = m
	mir.position = Vector3(28.51645, 0, 0)  # 右缘对右缘 → 镜像连续缝 @x=14.26
	print("mirror: ", m.point_count, " aabb=", m.aabb)

	# 懒人法: 同一资源, 负 scale
	var lazy := GaussianSplatNode.new()
	add_child(lazy)
	lazy.gaussian = a
	lazy.scale = Vector3(-1, 1, 1)
	lazy.position = Vector3(0, 32, 0)

	var cam := Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw

	cam.position = Vector3(14.26, 2, 46)
	await _shot("mirror_00_junction.png", cam, Vector3(14.26, 0, 0))
	cam.position = Vector3(14.26, 34, 52)
	await _shot("mirror_01_lazy.png", cam, Vector3(0, 32, 0))
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

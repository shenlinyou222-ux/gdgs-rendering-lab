extends Node3D
## 镜像表达设计画廊: 边缘特写 / 镜缝特写 / 对置双壁峡谷 / 万花筒条带远景
func _ready() -> void:
	var a: GaussianResource = load("res://assets/hy_cell01.ply")
	var b: GaussianResource = load("res://assets/hy_cell01_mirror.ply")

	# 布景A: 缝 @x=14.26 的条带(原+镜)
	var s1 := GaussianSplatNode.new(); add_child(s1); s1.gaussian = a
	var s2 := GaussianSplatNode.new(); add_child(s2); s2.gaussian = b; s2.position = Vector3(28.51645, 0, 0)
	# 布景B: 对置双壁峡谷: 原@(-20,0,0) 镜(+20,0,0) → 11m 缝隙走廊
	var s3 := GaussianSplatNode.new(); add_child(s3); s3.gaussian = a; s3.position = Vector3(-20, 0, 0)
	var s4 := GaussianSplatNode.new(); add_child(s4); s4.gaussian = b; s4.position = Vector3(20, 0, 0)
	print("4 节点就绪: 总点数 ", a.point_count * 4)

	var cam := Camera3D.new(); cam.fov = 65.0; add_child(cam)
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw

	# 00 边缘噪声特写: 距质心 6m 逼近表面
	var c: Vector3 = a.aabb.get_center()
	cam.position = c + Vector3(0.3, 0.15, 1).normalized() * 6.0
	await _shot("gallery_00_edge_closeup.png", cam, c)
	# 01 镜缝特写: 缝平面近观
	cam.position = Vector3(14.26, 1.5, 16)
	await _shot("gallery_01_seam_closeup.png", cam, Vector3(14.26, 0, 2))
	# 02 对置双壁峡谷: 相机在缝中央沿走廊看向 -z
	cam.position = Vector3(0, 2.0, 8)
	await _shot("gallery_02_mirror_canyon.png", cam, Vector3(0, 1.5, -12))
	# 03 万花筒条带远景
	cam.position = Vector3(14.26, 9, 75); cam.fov = 55.0
	await _shot("gallery_03_kaleido_strip.png", cam, Vector3(14.26, 0, 0))
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

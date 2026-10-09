extends Node3D
## 行星烘焙 splat 探针: 远/近机位截图 + 亮度统计 + LOD visible 切换验证(隐藏窗口渲染冒烟)
## 验证点: ① PLY 解码正确(点数/AABB) ② 烘焙太阳产生晨昏线(朝阳面亮) ③ far/near 两节点切换渲染正常

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.02)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var res_l0: GaussianResource = load("res://assets/splat_planets/jupiter_l0.ply")
	var res_l1: GaussianResource = load("res://assets/splat_planets/jupiter_l1.ply")
	print("probe: L0=", res_l0.point_count, " L1=", res_l1.point_count, " aabb=", res_l0.aabb)
	var n_far := GaussianSplatNode.new()
	add_child(n_far)
	n_far.gaussian = res_l1
	var n_near := GaussianSplatNode.new()
	add_child(n_near)
	n_near.gaussian = res_l0
	n_near.visible = false

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 60000.0
	add_child(cam)
	var R := 803.0
	var dir := Vector3(0.35, 0.25, -1.0).normalized()  # 烘焙太阳轴=本地-Z, 相机放 -Z 侧看朝阳面
	var names := ["far_l1", "near_l0"]
	for i in range(2):
		var d := R / sin(deg_to_rad([4.0, 30.0][i]))
		cam.position = dir * d
		cam.look_at(Vector3.ZERO, Vector3.UP)
		n_far.visible = i == 0
		n_near.visible = i == 1
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://shots/planet_probe_%s.png" % names[i])
		var s := 0.0
		var s2 := 0.0
		var n := 0
		for y in range(0, img.get_height(), 4):
			for x in range(0, img.get_width(), 4):
				var p: Color = img.get_pixel(x, y)
				var v := p.r * 0.3 + p.g * 0.6 + p.b * 0.1
				s += v
				s2 += v * v
				n += 1
		var mean: float = s / n
		print("SHOT %s mean=%.4f std=%.4f" % [names[i], mean, sqrt(max(s2 / n - mean * mean, 0.0))])
		print("flush_%d" % i)
	get_tree().quit()

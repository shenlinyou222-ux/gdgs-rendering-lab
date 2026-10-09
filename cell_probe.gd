extends Node3D
# hy_cell01 渲染探针:三机位截图 + 亮度统计(判定 opacity/色值约定是否兼容)
func _ready() -> void:
	var res: GaussianResource = load("res://assets/hy_cell01.ply")
	print("probe: points=", res.point_count, " aabb=", res.aabb)
	var splat := GaussianSplatNode.new()
	add_child(splat)
	splat.gaussian = res
	var cam := Camera3D.new()
	add_child(cam)
	var a: AABB = res.aabb
	var c: Vector3 = a.get_center()
	var dist: float = (a.size.length() * 0.5) / tan(deg_to_rad(35.0)) * 1.15
	for i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for i in range(3):
		var ang: float = [0.0, PI * 0.25, PI * 0.5][i]
		cam.position = c + Vector3(cos(ang), 0.35, sin(ang)) * dist
		cam.look_at(c, Vector3.UP)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://shots/hy_cell01_%02d.png" % i)
		var s := 0.0
		var s2 := 0.0
		var n := 0
		for y in range(0, img.get_height(), 4):
			for x in range(0, img.get_width(), 4):
				var p: Color = img.get_pixel(x, y)
				var v: float = p.r * 0.3 + p.g * 0.6 + p.b * 0.1
				s += v
				s2 += v * v
				n += 1
		var mean: float = s / n
		print("SHOT ", i, " mean=", "%.4f" % mean, " std=", "%.4f" % sqrt(max(s2 / n - mean * mean, 0.0)))
		print("flush_", i)
	get_tree().quit()

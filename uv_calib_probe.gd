extends Node3D
## v6.14 UV 标定探针(隐藏窗口渲染): 网格 SphereMesh 与 splat PLY 各自的 (u,v)->本地方向 映射差
## 贴图: 白点(u=.625,v=.4) + 灰点(u=.8125,v=.65); 同一单位姿态渲染, 找点->反投影->单位向量
## 用法: Godot_console.exe --path . res://uv_calib_probe.tscn -- --align=qx,qy,qz,qw  (可选: splat 预乘四元数)

const R := 100.0
const D := 600.0

var cam: Camera3D
var nodes: Dictionary = {}

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var q := Quaternion()
	var have_align := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--align="):
			var p: Array = a.split("=")[1].split(",")
			q = Quaternion(float(p[0]), float(p[1]), float(p[2]), float(p[3])).normalized()
			have_align = true
	print("CALIB align=%s q=(%.4f,%.4f,%.4f,%.4f)" % [str(have_align), q.x, q.y, q.z, q.w])

	var mesh := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = R
	s.height = R * 2.0
	s.radial_segments = 96
	s.rings = 48
	mesh.mesh = s
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/planet_surface.gdshader")
	m.set_shader_parameter("tex", load("res://assets/textures/uv_calib.png"))
	m.set_shader_parameter("sun_dir", Vector3(0.0, 0.0, 1.0))
	m.set_shader_parameter("night_ambient", 1.0)
	m.set_shader_parameter("day_gain", 0.0)
	mesh.material_override = m
	add_child(mesh)
	mesh.quaternion = Quaternion()
	nodes["mesh"] = mesh

	var n := GaussianSplatNode.new()
	add_child(n)
	n.gaussian = load("res://assets/splat_planets/uv_calib_l0.ply")
	n.scale = Vector3.ONE * (R / maxf(n.gaussian.aabb.size.x * 0.5, 0.001))
	n.quaternion = q
	nodes["splat"] = n

	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 5000.0
	add_child(cam)
	cam.make_current()

	var cams := { "A+": [Vector3(0.0, 0.0, D), Vector3.UP], "B+": [Vector3(D, 0.0, 0.0), Vector3.UP], "C+": [Vector3(0.0, D, 0.0), Vector3(0.0, 0.0, -1.0)] }
	for rep in ["mesh", "splat"]:
		nodes["mesh"].visible = rep == "mesh"
		nodes["splat"].visible = rep == "splat"
		for ck in cams:
			cam.position = cams[ck][0]
			cam.look_at(Vector3.ZERO, cams[ck][1])
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var w := img.get_width()
			var h := img.get_height()
			var d1: Variant = _find_dot(img, null)
			var d2: Variant = _find_dot(img, d1)
			img.save_png("res://shots/uv_calib_%s_%s.png" % [rep, ck])
			if d1 == null or d2 == null:
				print("DOTS %s@%s: NOT FOUND (d1=%s d2=%s) size=%dx%d" % [rep, ck, str(d1), str(d2), w, h])
				continue
			var v1 := _dir_from_px(d1)
			var v2 := _dir_from_px(d2)
			print("DOTS %s@%s: d1=(%.1f,%.1f)->(%.4f,%.4f,%.4f)  d2=(%.1f,%.1f)->(%.4f,%.4f,%.4f)" % [
				rep, ck, d1.x, d1.y, v1.x, v1.y, v1.z, d2.x, d2.y, v2.x, v2.y, v2.z])
	print("flush")
	get_tree().quit()

func _lum(c: Color) -> float:
	return c.r * 0.3 + c.g * 0.6 + c.b * 0.1

func _find_dot(img: Image, exclude: Variant) -> Variant:
	# 亮度最大质心(可选: 排除 exclude 半径 70px 内), 40px 窗口内加权质心
	var w := img.get_width()
	var h := img.get_height()
	var best := -1.0
	var bp := Vector2(-1.0, -1.0)
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			if exclude != null and Vector2(x, y).distance_to(exclude) < 70.0:
				continue
			var v := _lum(img.get_pixel(x, y))
			if v > best:
				best = v
				bp = Vector2(x, y)
	if bp.x < 0.0:
		return null
	var sx := 0.0
	var sy := 0.0
	var sw := 0.0
	for y in range(int(bp.y) - 40, int(bp.y) + 41):
		for x in range(int(bp.x) - 40, int(bp.x) + 41):
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			if exclude != null and Vector2(x, y).distance_to(exclude) < 60.0:
				continue
			var v := _lum(img.get_pixel(x, y))
			if v <= 0.02:
				continue
			sx += x * v
			sy += y * v
			sw += v
	if sw <= 0.0:
		return null
	return Vector2(sx / sw, sy / sw)

func _dir_from_px(p: Vector2) -> Vector3:
	var o := cam.project_ray_origin(p)
	var d := cam.project_ray_normal(p)
	var b := o.dot(d)
	var c := o.dot(o) - R * R
	var disc := b * b - c
	if disc < 0.0:
		return Vector3(INF, INF, INF)
	var t := -b - sqrt(disc)
	return (o + d * t).normalized()

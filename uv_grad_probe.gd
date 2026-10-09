extends Node3D
## v6.14 UV 梯度标定探针(隐藏窗口): 6 轴向相机读圆盘中心 (R,G)=(u,v) -> 各自的 方向->UV 映射
## 网格 SphereMesh vs splat PLY(可选 --align=qx,qy,qz,qw 预转) 输出 6 组 (u,v), 离线解出对齐四元数

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
	print("GRADCAL align=%s q=(%.6f,%.6f,%.6f,%.6f)" % [str(have_align), q.x, q.y, q.z, q.w])

	var mesh := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = R
	s.height = R * 2.0
	s.radial_segments = 96
	s.rings = 48
	mesh.mesh = s
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/planet_surface.gdshader")
	m.set_shader_parameter("tex", load("res://assets/textures/uv_grad.png"))
	m.set_shader_parameter("sun_dir", Vector3(0.0, 0.0, 1.0))
	m.set_shader_parameter("night_ambient", 1.0)
	m.set_shader_parameter("day_gain", 0.0)
	mesh.material_override = m
	add_child(mesh)
	mesh.quaternion = Quaternion()
	nodes["mesh"] = mesh

	var n := GaussianSplatNode.new()
	add_child(n)
	n.gaussian = load("res://assets/splat_planets/uv_grad_l0.ply")
	n.scale = Vector3.ONE * (R / maxf(n.gaussian.aabb.size.x * 0.5, 0.001))
	n.quaternion = q
	nodes["splat"] = n

	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 5000.0
	add_child(cam)
	cam.make_current()

	var cams := {
		"X+": [Vector3(D, 0.0, 0.0), Vector3.UP], "X-": [Vector3(-D, 0.0, 0.0), Vector3.UP],
		"Y+": [Vector3(0.0, D, 0.0), Vector3(0.0, 0.0, -1.0)], "Y-": [Vector3(0.0, -D, 0.0), Vector3(0.0, 0.0, 1.0)],
		"Z+": [Vector3(0.0, 0.0, D), Vector3.UP], "Z-": [Vector3(0.0, 0.0, -D), Vector3.UP],
	}
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
			var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
			var c2 := img.get_pixel(img.get_width() / 2 + 3, img.get_height() / 2 - 2)
			print("GRAD %s@%s: u=%.4f v=%.4f  (u2=%.3f v2=%.3f)" % [rep, ck, c.r, c.g, c2.r, c2.g])
	print("flush")
	get_tree().quit()

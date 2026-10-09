extends Node3D
## v6.14 LOD 对齐探针(隐藏窗口渲染): 同一姿态下渲染 网格/L0/L1 三级地球, 互相关测贴图经度偏差
## 用法: Godot_console.exe --path . res://lod_align_probe.tscn -- --phi=0   (phi=splat 节点绕本地Y预转角, 度)
## 输出: mesh vs L0/L1 的水平/垂直 strip 相关位移(px)与换算角度, 用于标定 SPLAT_UV_ALIGN_RAD

const R := 100.0
const D := 600.0

var cam: Camera3D
var nodes: Dictionary = {}   # name -> Node3D(三者同位置同姿态)

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var q := Quaternion()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--phi="):
			q = Quaternion(Vector3.UP, deg_to_rad(float(a.split("=")[1])))
		elif a.begins_with("--align="):
			var pp: Array = a.split("=")[1].split(",")
			q = Quaternion(float(pp[0]), float(pp[1]), float(pp[2]), float(pp[3])).normalized()
	print("PROBE q=(%.4f,%.4f,%.4f,%.4f)" % [q.x, q.y, q.z, q.w])

	# 网格地球: FLAT 渲染(day_gain=0, night=1 -> ALBEDO=tex), 与纯反照率 splat 可直接比对
	var mesh := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = R
	s.height = R * 2.0
	s.radial_segments = 96
	s.rings = 48
	mesh.mesh = s
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/planet_surface.gdshader")
	m.set_shader_parameter("tex", load("res://assets/textures/planets/earth.jpg"))
	m.set_shader_parameter("sun_dir", Vector3(0.0, 0.0, 1.0))
	m.set_shader_parameter("night_ambient", 1.0)
	m.set_shader_parameter("day_gain", 0.0)
	mesh.material_override = m
	add_child(mesh)
	mesh.quaternion = Quaternion()
	nodes["mesh"] = mesh

	# splat L0/L1: 纯反照率 PLY + phi 预转角
	for lvl in ["l0", "l1"]:
		var n := GaussianSplatNode.new()
		add_child(n)
		n.gaussian = load("res://assets/splat_planets/earth_%s.ply" % lvl)
		n.scale = Vector3.ONE * (R / maxf(n.gaussian.aabb.size.x * 0.5, 0.001))
		n.quaternion = q
		nodes[lvl] = n

	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 5000.0
	add_child(cam)
	cam.make_current()

	var cams := { "A": Vector3(0.0, 0.0, D), "B": Vector3(D, 0.0, 0.0) }
	var strips := {}   # "%s@%s" % [rep, cam] -> {"h": [...], "v": [...], "img": Image}
	for rep in ["mesh", "l0", "l1"]:
		for ck in cams:
			nodes["mesh"].visible = rep == "mesh"
			nodes["l0"].visible = rep == "l0"
			nodes["l1"].visible = rep == "l1"
			cam.position = cams[ck]
			cam.look_at(Vector3.ZERO, Vector3.UP)
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png("res://shots/lod_align_%s_%s.png" % [rep, ck])
			strips["%s@%s" % [rep, ck]] = _strips(img)
		print("SHOT %s done" % rep)
	# 相关分析: mesh 为基准
	for ck in cams:
		var base: Dictionary = strips["mesh@" + ck]
		for rep in ["l0", "l1"]:
			var s2: Dictionary = strips[rep + "@" + ck]
			var hs: float = _ncc_shift(base["h"], s2["h"])
			var vf: float = _ncc_shift(base["v"], s2["v"])
			var vr: float = _ncc_shift(base["v"], _reverse(s2["v"]))
			var deg_per_px := 180.0 / float(base["h"].size())
			print("ALIGN %s vs %s: h_shift=%+.1fpx (%+.1fdeg)  v_shift=%+.1fpx  v_flip_score=%.3f (flip<same? %s)" % [
				ck, rep, hs, hs * deg_per_px, vf, vr, "YES-FLIPPED" if vr > vf + 0.05 else "no"])
	print("flush")
	get_tree().quit()

func _strips(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var cx := w / 2
	var cy := h / 2
	# 圆盘半径(px): asin(R/D) 对 fov/2
	var r_px := (tan(asin(R / D)) / tan(deg_to_rad(35.0))) * (h / 2.0)
	var ri := int(r_px * 0.92)
	var hstrip := []
	for x in range(cx - ri, cx + ri):
		var acc := 0.0
		for y in range(cy - 6, cy + 7):
			var c: Color = img.get_pixel(x, y)
			acc += c.r * 0.3 + c.g * 0.6 + c.b * 0.1
		hstrip.append(acc / 13.0)
	var vstrip := []
	for y in range(cy - ri, cy + ri):
		var acc := 0.0
		for x in range(cx - 6, cx + 7):
			var c: Color = img.get_pixel(x, y)
			acc += c.r * 0.3 + c.g * 0.6 + c.b * 0.1
		vstrip.append(acc / 13.0)
	return { "h": hstrip, "v": vstrip }

func _reverse(arr: Array) -> Array:
	var out := []
	out.resize(arr.size())
	for i in arr.size():
		out[i] = arr[arr.size() - 1 - i]
	return out

func _ncc_shift(a: Array, b: Array) -> float:
	# 归一化互相关, 返回使 b 平移后与 a 最匹配的位移(正值=b 需右移)
	var n := a.size()
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += a[i]
		mb += b[i]
	ma /= n
	mb /= n
	var best_d := 0.0
	var best_s := -2.0
	for d in range(-n + 8, n - 7):
		var sab := 0.0
		var saa := 0.0
		var sbb := 0.0
		var cnt := 0
		for i in n:
			var j := i + d
			if j < 0 or j >= n:
				continue
			var av: float = a[i] - ma
			var bv: float = b[j] - mb
			sab += av * bv
			saa += av * av
			sbb += bv * bv
			cnt += 1
		if cnt < n * 0.5:
			continue
		var s := sab / sqrt(max(saa * sbb, 1e-9))
		if s > best_s:
			best_s = s
			best_d = float(d)
	print("    ncc peak=%+.2f at %+.0fpx" % [best_s, best_d])
	return best_d

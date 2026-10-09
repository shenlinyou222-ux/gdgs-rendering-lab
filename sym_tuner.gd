extends Node3D
## 交互对称面调面器:运行时解码+重建,无需编辑器导入
## ←/→ 法向方位角 | ↑/↓ 俯仰 | Z/X 平移面 | K 换保留侧 | SPACE 重建 | O 原件对照 | ENTER 导出参数 | Esc 退出

const StdDecoder = preload("res://addons/gdgs/importers/decoders/standard_ply_decoder.gd")
const Builder = preload("res://addons/gdgs/importers/builders/gaussian_resource_builder.gd")

var cam: Camera3D
var _yaw := 0.0
var _pitch := 0.0
var _mouse_free := false
var _info: Label
var _plane_quad: MeshInstance3D

# 平面参数(球坐标法向)
var az := deg_to_rad(-12.9)   # 初始=NN精修结果
var el := deg_to_rad(-3.4)
var off := -0.97
var keep_positive := true

var orig_canonical: Dictionary
var orig_res # GaussianResource
var sym_node: GaussianSplatNode
var ghost_node: GaussianSplatNode
var _busy := false
# 两线定面协议
var line_locked := 0      # 0=自由 1=已锁线1(1自由度) 2=两面线锁定(完全确定)
var u1 := Vector3.UP
var locked_n := Vector3.RIGHT
var theta := 0.0
var centroid := Vector3.ZERO

func _perp_of(u: Vector3) -> Vector3:
	var a := Vector3.UP
	if absf(u.dot(a)) > 0.9:
		a = Vector3.FORWARD
	return u.cross(a).normalized()

func _normal() -> Vector3:
	if line_locked == 1:
		return _perp_of(u1).rotated(u1, theta).normalized()
	elif line_locked == 2:
		return locked_n
	return Vector3(cos(el) * cos(az), sin(el), cos(el) * sin(az)).normalized()

func _plane_point() -> Vector3:
	return centroid + _normal() * off

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.014, 0.02)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 800.0
	add_child(cam)
	cam.position = Vector3(18, 8, 38)

	var layer := CanvasLayer.new()
	add_child(layer)
	_info = Label.new()
	_info.position = Vector2(14, 10)
	_info.add_theme_font_size_override("font_size", 15)
	layer.add_child(_info)

	# 半透明面片可视化
	_plane_quad = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(42, 42)
	_plane_quad.mesh = q
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.2, 0.9, 1.0, 0.13)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_plane_quad.material_override = m
	add_child(_plane_quad)

	_decode_and_build()

func _decode_and_build() -> void:
	_busy = true
	_set_info("解码 hy_cell01.ply(60.8万点,GDScript 需要数十秒)…")
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var dec: Dictionary = StdDecoder.decode("res://assets/hy_cell01.ply")
	if not dec.get("ok", false):
		_set_info("解码失败: " + str(dec.get("message", "?")))
		return
	orig_canonical = dec["canonical"]
	var _pp: PackedVector3Array = orig_canonical["positions"]
	for i in _pp.size():
		centroid += _pp[i]
	centroid /= float(_pp.size())
	print("centroid=", centroid)
	var build: Dictionary = Builder.build(orig_canonical)
	orig_res = build["resource"]
	print("decode+build ", Time.get_ticks_msec() - t0, "ms  points=", orig_res.point_count)

	ghost_node = GaussianSplatNode.new()
	add_child(ghost_node)
	ghost_node.gaussian = orig_res
	ghost_node.visible = false

	sym_node = GaussianSplatNode.new()
	add_child(sym_node)
	_rebuild()
	_set_info("就绪")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	DisplayServer.window_set_title("调面器·两线定面 — 把分界线转到画面竖直方向→按L | 转90°找第二条→再按L | SPACE重建 K换侧 O对照 ENTER导出 C清除 Esc退出")
	_busy = false

func _rebuild() -> void:
	_busy = true
	_set_info("重建半镜(约 10–20s)…")
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var pos_in: PackedVector3Array = orig_canonical["positions"]
	var scl_in: PackedVector3Array = orig_canonical["scales_linear"]
	var rot_in: Array = orig_canonical["rotations"]
	var op_in: PackedFloat32Array = orig_canonical["opacities"]
	var sh_in: PackedFloat32Array = orig_canonical["sh_coeffs"]
	var n := _normal()
	var p0 := _plane_point()

	var keep_idx: Array[int] = []
	for i in pos_in.size():
		var s := (pos_in[i] - p0).dot(n) > 0.0
		if s == keep_positive:
			keep_idx.append(i)

	var M: int = keep_idx.size() * 2
	var canon: Dictionary = Builder.create_canonical(M)
	var pos: PackedVector3Array = canon["positions"]
	var scl: PackedVector3Array = canon["scales_linear"]
	var rot: Array = canon["rotations"]
	var op: PackedFloat32Array = canon["opacities"]
	var sh: PackedFloat32Array = canon["sh_coeffs"]

	# F = I - 2nn^T (列为 e_j - 2 n n_j)
	var F := Basis(
		Vector3(1, 0, 0) - 2.0 * n * n.x,
		Vector3(0, 1, 0) - 2.0 * n * n.y,
		Vector3(0, 0, 1) - 2.0 * n * n.z
	)
	var D := Basis.from_scale(Vector3(1, -1, 1))
	var FD := F * D

	for k in keep_idx.size():
		var src: int = keep_idx[k]
		var v: Vector3 = pos_in[src]
		# 保留侧
		pos[k] = v
		scl[k] = scl_in[src]
		rot[k] = rot_in[src]
		op[k] = op_in[src]
		for j in 48:
			sh[k * 48 + j] = sh_in[src * 48 + j]
		# 镜像侧
		var d2: int = keep_idx.size() + k
		var t := 2.0 * (v - p0).dot(n)
		pos[d2] = v - n * t
		scl[d2] = scl_in[src]
		op[d2] = op_in[src]
		var R: Basis = Basis(rot_in[src])
		rot[d2] = Quaternion(FD * R).normalized()
		for j in 48:
			sh[d2 * 48 + j] = sh_in[src * 48 + j]

	var b: Dictionary = Builder.build(canon)
	sym_node.gaussian = b["resource"]
	print("rebuild ", Time.get_ticks_msec() - t0, "ms  M=", M)
	_busy = false

func _set_info(s: String) -> void:
	_info.text = s + "\n" + _plane_text()

func _plane_text() -> String:
	return "模式%s az=%.1f° el=%.1f° th=%.1f° off=%.2fm 保留%s侧 | %s" % [
		["自由(←→↑↓)", "线1已锁(←→旋转面)", "两面锁定"][line_locked],
		rad_to_deg(az), rad_to_deg(el), rad_to_deg(theta), off,
		"正" if keep_positive else "负",
		"重建中" if _busy else "SPACE=重建"]

func _process(dt: float) -> void:
	if not _mouse_free and orig_canonical.is_empty() == false:
		_fly(dt)
	_update_plane_visual()
	_info.text = "FPS %d | %s" % [Engine.get_frames_per_second(), _plane_text()]
	# 按住连调
	if _busy:
		return
	var da := deg_to_rad(1.0)
	if line_locked == 1:
		if Input.is_physical_key_pressed(KEY_LEFT): theta -= da * 60.0 * dt
		if Input.is_physical_key_pressed(KEY_RIGHT): theta += da * 60.0 * dt
	elif line_locked == 0:
		if Input.is_physical_key_pressed(KEY_LEFT): az -= da * 60.0 * dt
		if Input.is_physical_key_pressed(KEY_RIGHT): az += da * 60.0 * dt
		if Input.is_physical_key_pressed(KEY_UP): el += da * 60.0 * dt
		if Input.is_physical_key_pressed(KEY_DOWN): el -= da * 60.0 * dt
	if Input.is_physical_key_pressed(KEY_Z): off -= 1.5 * dt
	if Input.is_physical_key_pressed(KEY_X): off += 1.5 * dt

func _lock_line() -> void:
	var up: Vector3 = cam.global_transform.basis.y.normalized()
	if line_locked == 0:
		u1 = up
		theta = 0.0
		off = 0.0
		line_locked = 1
		print("LINE1 dir=(", u1.x, ", ", u1.y, ", ", u1.z, ") cam_pos=", cam.global_position, " yaw=", _yaw, " pitch=", _pitch)
		_rebuild()
	elif line_locked == 1:
		var n: Vector3 = u1.cross(up)
		if n.length() < 0.15:
			print("LINE2 rejected near-parallel ", n.length())
			_info.text = "两条视线太接近平行,换个角度再按 L"
			return
		locked_n = n.normalized()
		off = 0.0
		line_locked = 2
		print("LINE2 dir=(", up.x, ", ", up.y, ", ", up.z, ") final_n=(", locked_n.x, ", ", locked_n.y, ", ", locked_n.z, ")")
		_rebuild()

func _update_plane_visual() -> void:
	var n := _normal()
	var p0 := _plane_point()
	_plane_quad.position = p0
	_plane_quad.look_at(p0 + n, Vector3.UP if absf(n.y) < 0.99 else Vector3.FORWARD)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if _mouse_free: get_tree().quit()
			else:
				_mouse_free = true
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_L and not _busy and not orig_canonical.is_empty():
			_lock_line()
		elif event.keycode == KEY_C:
			line_locked = 0
			theta = 0.0
			print("lines cleared")
		elif event.keycode == KEY_SPACE and not _busy and not orig_canonical.is_empty():
			_rebuild()
		elif event.keycode == KEY_O:
			ghost_node.visible = not ghost_node.visible
		elif event.keycode == KEY_K:
			keep_positive = not keep_positive
		elif event.keycode == KEY_ENTER and not _busy:
			var f := FileAccess.open("res://_sym_plane_user.json", FileAccess.WRITE)
			f.store_string(JSON.stringify({"mode": line_locked, "az_deg": rad_to_deg(az), "el_deg": rad_to_deg(el), "theta_deg": rad_to_deg(theta), "offset": off, "keep_positive": keep_positive, "n": [locked_n.x, locked_n.y, locked_n.z]}))
			f.close()
			print("EXPORTED plane -> res://_sym_plane_user.json")
			_info.text = "✅ 平面已导出 _sym_plane_user.json"
	elif event is InputEventMouseButton and event.pressed and _mouse_free and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_free = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and not _mouse_free:
		_yaw -= event.relative.x * 0.0022
		_pitch = clampf(_pitch - event.relative.y * 0.0022, -1.45, 1.45)

func _fly(dt: float) -> void:
	cam.rotation = Vector3(_pitch, _yaw, 0.0)
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): move -= cam.basis.z
	if Input.is_physical_key_pressed(KEY_S): move += cam.basis.z
	if Input.is_physical_key_pressed(KEY_A): move -= cam.basis.x
	if Input.is_physical_key_pressed(KEY_D): move += cam.basis.x
	if Input.is_physical_key_pressed(KEY_E): move += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q): move -= Vector3.UP
	if move != Vector3.ZERO:
		var speed := 26.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 8.0
		cam.position += move.normalized() * speed * dt

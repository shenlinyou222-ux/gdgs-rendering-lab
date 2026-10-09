extends Node3D
## 第二幕预演:星空天空球 + 木星 + 3DGS 前景 + billboard 敌机编队
## 截图模式:Godot_console.exe --path . res://space.tscn      → 自动截 2 图后退出
## 实况模式:Godot_console.exe --path . res://space_live.tscn → 自由飞行,Esc 退出

const SHOT_DIR := "res://shots"

@export var live := false

var cam: Camera3D
var jupiter: MeshInstance3D
var center: Vector3 = Vector3.ZERO
var radius: float = 1.0
var _yaw := 0.0
var _pitch := 0.0
var _mouse_free := false

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	_build_sky()
	_build_star_layers()
	_build_nebulae()
	_build_light()
	_build_splat()
	_build_jupiter()
	_build_enemies()
	cam = Camera3D.new()
	cam.fov = 70
	cam.far = 12000.0
	add_child(cam)
	cam.current = true
	if live:
		_setup_live()
	_run()

func _process(dt: float) -> void:
	if jupiter:
		jupiter.rotate_y(dt * 0.02)
	if live and not _mouse_free:
		_fly(dt)

func _setup_live() -> void:
	DisplayServer.window_set_title("第二幕预演 · 太空场景 — 鼠标视角 | WASD/QE 飞行 | Shift 加速 | Esc 退出")
	var layer := CanvasLayer.new()
	var lbl := Label.new()
	lbl.text = "鼠标=视角   W/A/S/D=前后左右   Q/E=降/升   Shift=加速   Esc=松开鼠标(再按退出)"
	var ls := LabelSettings.new()
	ls.font_size = 15
	ls.font_color = Color(1, 1, 1, 0.9)
	ls.shadow_size = 5
	ls.shadow_color = Color(0, 0, 0, 0.75)
	lbl.label_settings = ls
	lbl.position = Vector2(16, 12)
	layer.add_child(lbl)
	add_child(layer)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not live:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _mouse_free:
			get_tree().quit()
		else:
			_mouse_free = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and _mouse_free \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_free = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and not _mouse_free:
		_yaw -= event.relative.x * 0.0022
		_pitch = clampf(_pitch - event.relative.y * 0.0022, -1.45, 1.45)

func _fly(dt: float) -> void:
	cam.rotation = Vector3(_pitch, _yaw, 0.0)
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move -= cam.basis.z
	if Input.is_physical_key_pressed(KEY_S):
		move += cam.basis.z
	if Input.is_physical_key_pressed(KEY_A):
		move -= cam.basis.x
	if Input.is_physical_key_pressed(KEY_D):
		move += cam.basis.x
	if Input.is_physical_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q):
		move -= Vector3.UP
	if move != Vector3.ZERO:
		var speed := 26.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 9.0
		cam.position += move.normalized() * speed * dt

func _build_sky() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var smat := ShaderMaterial.new()
	smat.shader = load("res://shaders/dual_panorama_sky.gdshader")
	smat.set_shader_parameter("pan_mosaic", load("res://assets/textures/nasa_sky_panorama_8k.jpg"))
	smat.set_shader_parameter("pan_nasa", load("res://assets/textures/nasa_svs/starmap_2020_4k.exr"))
	sky.sky_material = smat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

## 视差星层:全景天空球在无穷远,平移无视差;点星/尘埃放在有限距离上,
## 飞行时产生位移与速度感(Elite/EVE 手法)。每层 = 1 个 MultiMesh = 1 个 draw call。
func _build_star_layers() -> void:
	_add_star_layer(1500, 1600.0, 3200.0, 3.0, 8.0, 0.95)   # 远星层:缓慢视差
	_add_star_layer(600, 500.0, 1000.0, 1.8, 4.5, 1.0)      # 中星层:明显视差
	_add_star_layer(350, 25.0, 90.0, 0.15, 0.4, 0.5)        # 近距尘埃:强烈速度感

func _add_star_layer(count: int, r_min: float, r_max: float, s_min: float, s_max: float, alpha: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260909
	var palette := [
		Color(0.72, 0.78, 1.0),
		Color(1.0, 1.0, 1.0),
		Color(1.0, 0.93, 0.78),
		Color(1.0, 0.75, 0.55),
		Color(1.0, 0.55, 0.45),
	]
	for i in count:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if dir.length() < 0.001:
			dir = Vector3.RIGHT
		dir = dir.normalized()
		var pos := dir * rng.randf_range(r_min, r_max)
		var s := rng.randf_range(s_min, s_max)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), pos))
		var c: Color = palette[rng.randi_range(0, palette.size() - 1)]
		c.a = alpha * rng.randf_range(0.5, 1.0)
		mm.set_instance_color(i, c)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/star_billboard.gdshader")
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## 星云层:NASA 公版星云照片做加法混合 billboard,放在比星层更远处,
## 给银河补上大尺度的色彩结构(纯全景图缺少的"深空辉光")。
func _build_nebulae() -> void:
	var defs := [
		# [贴图, 方向×距离, 尺寸, 染色, 强度] — 前两块对准默认取景(木星背后/下方)
		["res://assets/textures/nebula/PIA03096.jpg", Vector3(-0.45, 0.12, -0.88), 5200.0, 3400.0, Color(0.8, 0.9, 1.0), 0.5],
		["res://assets/textures/nebula/carina_nebula.jpg", Vector3(-0.2, -0.35, -0.91), 5600.0, 4200.0, Color(1.0, 0.72, 0.85), 0.55],
		["res://assets/textures/nebula/PIA25434.jpg", Vector3(0.62, 0.25, -0.74), 4800.0, 3000.0, Color(0.8, 0.9, 1.0), 0.45],
		["res://assets/textures/nebula/PIA03096.jpg", Vector3(0.85, 0.1, 0.51), 5000.0, 3200.0, Color(1.0, 0.85, 0.7), 0.45],
		["res://assets/textures/nebula/carina_nebula.jpg", Vector3(-0.1, 0.75, 0.65), 5200.0, 3800.0, Color(0.75, 0.85, 1.0), 0.45],
		["res://assets/textures/nebula/PIA25434.jpg", Vector3(0.15, -0.9, -0.4), 5400.0, 3600.0, Color(0.85, 0.8, 1.0), 0.4],
	]
	for d in defs:
		_add_nebula(d[0], d[1].normalized() * d[2], d[3], d[4], d[5])

func _add_nebula(tex_path: String, pos: Vector3, size: float, tint: Color, strength: float) -> void:
	var t: Texture2D = load(tex_path)
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	var aspect := t.get_size().x / maxf(t.get_size().y, 1.0)
	quad.size = Vector2(size * aspect, size)
	mi.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/nebula_billboard.gdshader")
	mat.set_shader_parameter("tex", t)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("strength", strength)
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _build_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 55, 0)
	sun.light_energy = 1.3
	add_child(sun)

func _build_splat() -> void:
	var res: GaussianResource = load("res://assets/demo.compressed.ply")
	if res == null:
		push_error("FATAL: gaussian resource failed to load")
		get_tree().quit(1)
		return
	var splat := GaussianSplatNode.new()
	add_child(splat)
	splat.gaussian = res
	var aabb: AABB = res.aabb
	if aabb.size != Vector3.ZERO:
		center = aabb.get_center()
		radius = maxf(aabb.size.length() * 0.5, 0.5)
	print("splat loaded: points=", res.point_count)

func _build_jupiter() -> void:
	jupiter = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 55.0
	sphere.height = 110.0
	sphere.radial_segments = 96
	sphere.rings = 48
	jupiter.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/8k_jupiter.jpg")
	mat.roughness = 1.0
	jupiter.material_override = mat
	jupiter.position = Vector3(-260, 90, -420)
	add_child(jupiter)

func _build_enemies() -> void:
	var tex := _ship_texture()
	var dir := Vector3(-0.4, 0.12, -0.9).normalized()
	var right := dir.cross(Vector3.UP).normalized()
	var leader := center + dir * 120.0
	for i in 9:
		for side in [-1.0, 1.0]:
			if i == 0 and side == 1.0:
				continue
			var e := _make_enemy(tex, 3.2)
			e.position = leader + right * side * 5.0 * i + dir * (-1.8 * i) + Vector3(0, 0.8 * i, 0)
			add_child(e)

func _make_enemy(tex: Texture2D, size: float) -> Area3D:
	var root := Area3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size, size, size * 0.5)
	cs.shape = shape
	root.add_child(cs)
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = tex
	mi.material_override = mat
	root.add_child(mi)
	return root

func _ship_texture() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(s / 2.0, s / 2.0)
	for y in s:
		for x in s:
			var p := Vector2(x - c.x, y - c.y)
			var body := absf(p.x) < 5.0 and absf(p.y) < 20.0
			var wing := absf(p.x) * 0.8 + absf(p.y) < 26.0
			if body:
				img.set_pixel(x, y, Color(1.0, 0.92, 0.75))
			elif wing:
				img.set_pixel(x, y, Color(1.0, 0.32, 0.12))
	return ImageTexture.create_from_image(img)

func _pos_a() -> Vector3:
	return center + Vector3(0.75, 0.3, 1.1).normalized() * radius * 2.6

func _pos_b() -> Vector3:
	return center + Vector3(-0.9, 0.5, 0.6).normalized() * radius * 2.2

func _shot(fname: String) -> void:
	for i in 15:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SHOT_DIR + "/" + fname))
	print("SAVED ", fname, " fps=", Engine.get_frames_per_second())

func _run() -> void:
	for i in 90:
		await get_tree().process_frame
	cam.position = _pos_a()
	cam.look_at(center)
	_yaw = cam.rotation.y
	_pitch = cam.rotation.x
	if live:
		for i in 120:
			await get_tree().process_frame
		print("LIVE mode 启动 | 稳态 fps=", Engine.get_frames_per_second())
		return
	await _shot("space_01_ruins_milkyway_enemies.png")
	cam.position = _pos_b()
	cam.look_at(jupiter.global_position)
	await _shot("space_02_jupiter_and_fleet.png")
	# 极区验证:抬头 / 低头
	cam.position = _pos_a()
	cam.rotation = Vector3(-1.45, _yaw, 0.0)
	await _shot("space_03_sky_up.png")
	cam.rotation = Vector3(1.45, _yaw, 0.0)
	await _shot("space_04_sky_down.png")
	get_tree().quit()

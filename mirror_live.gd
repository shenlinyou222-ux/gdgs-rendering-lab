extends Node3D
## 镜像峡谷实况:第二幕全套环境(星空/星层/星云/木星/敌机) + 一次生成×镜像 = 对置双壁走廊
## Godot_console.exe --path . res://mirror_live.tscn → 自由飞行,Esc 退出

var cam: Camera3D
var jupiter: MeshInstance3D
var center: Vector3 = Vector3.ZERO
var radius: float = 1.0
var _yaw := 0.0
var _pitch := 0.0
var _mouse_free := false
var _fps_lbl: Label

func _ready() -> void:
	_build_sky()
	_build_star_layers()
	_build_nebulae()
	_build_light()
	_build_mirror_canyon()
	_build_jupiter()
	_build_enemies()
	cam = Camera3D.new()
	cam.fov = 70
	cam.far = 12000.0
	add_child(cam)
	cam.current = true
	_setup_live()
	_run()

func _process(dt: float) -> void:
	if jupiter:
		jupiter.rotate_y(dt * 0.02)
	if _fps_lbl:
				_fps_lbl.text = "FPS %d | 点数:壁122万+远条14万" % [Engine.get_frames_per_second()]
	if not _mouse_free:
		_fly(dt)

func _setup_live() -> void:
	DisplayServer.window_set_title("镜像峡谷实况 — 1次生成×镜像=双壁走廊 | WASD/QE 飞行 | Esc 退出")
	var layer := CanvasLayer.new()
	var lbl := Label.new()
	lbl.text = "鼠标=视角  W/A/S/D=移动  Q/E=降/升  Shift=加速  前方走廊尽头=万花筒条带  Esc=松开鼠标(再按退出)"
	var ls := LabelSettings.new()
	ls.font_size = 15
	ls.font_color = Color(1, 1, 1, 0.9)
	ls.shadow_size = 5
	ls.shadow_color = Color(0, 0, 0, 0.75)
	lbl.label_settings = ls
	lbl.position = Vector2(16, 12)
	layer.add_child(lbl)
	_fps_lbl = Label.new()
	_fps_lbl.position = Vector2(16, 36)
	_fps_lbl.label_settings = ls
	layer.add_child(_fps_lbl)
	add_child(layer)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _mouse_free:
			get_tree().quit()
		else:
			_mouse_free = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
		var speed := 26.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 9.0
		cam.position += move.normalized() * speed * dt

## 镜像峡谷: 原件@(-20,0,0) + 数据级镜像@(+20,0,0) → 中央 ~11m 飞行走廊(沿 -z)
## 走廊尽头(0,0,150)放万花筒条带(原+镜右缘相接)
func _build_mirror_canyon() -> void:
	var a: GaussianResource = load("res://assets/hy_cell01.ply")
	var b: GaussianResource = load("res://assets/hy_cell01_mirror.ply")
	var af: GaussianResource = load("res://assets/hy_cell01_far.ply")
	var bf: GaussianResource = load("res://assets/hy_cell01_mirror_far.ply")
	for r in [[a, Vector3(-35, 0, 0)], [b, Vector3(35, 0, 0)],
			[af, Vector3(0, 0, 150)], [bf, Vector3(28.51645, 0, 150)]]:
		var s := GaussianSplatNode.new()
		add_child(s)
		s.gaussian = r[0]
		s.position = r[1]
	print("mirror canyon: walls=", a.point_count * 2, " far_strip=", af.point_count * 2, " total=", a.point_count * 2 + af.point_count * 2)

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

func _build_star_layers() -> void:
	_add_star_layer(1500, 1600.0, 3200.0, 3.0, 8.0, 0.95)
	_add_star_layer(600, 500.0, 1000.0, 1.8, 4.5, 1.0)
	_add_star_layer(350, 25.0, 90.0, 0.15, 0.4, 0.5)

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
	var palette := [Color(0.72, 0.78, 1.0), Color(1, 1, 1, 1), Color(1, 0.93, 0.78), Color(1, 0.75, 0.55), Color(1, 0.55, 0.45)]
	for i in count:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if dir.length() < 0.001: dir = Vector3.RIGHT
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

func _build_nebulae() -> void:
	var defs := [
		["res://assets/textures/nebula/PIA03096.jpg", Vector3(-0.45, 0.12, -0.88), 5200.0, 3400.0, Color(0.8, 0.9, 1.0), 0.5],
		["res://assets/textures/nebula/carina_nebula.jpg", Vector3(-0.2, -0.35, -0.91), 5600.0, 4200.0, Color(1.0, 0.72, 0.85), 0.55],
		["res://assets/textures/nebula/PIA25434.jpg", Vector3(0.62, 0.25, -0.74), 4800.0, 3000.0, Color(0.8, 0.9, 1.0), 0.45],
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

## 敌机编队: 摆进走廊, 沿 -z 列队
func _build_enemies() -> void:
	var tex := _ship_texture()
	var leader := Vector3(0, 2, -70)
	for i in 9:
		for side in [-1.0, 1.0]:
			if i == 0 and side == 1.0: continue
			var e := _make_enemy(tex, 3.2)
			e.position = leader + Vector3(side * 4.5 * i, 0.6 * i, 1.8 * i)
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
			if body: img.set_pixel(x, y, Color(1.0, 0.92, 0.75))
			elif wing: img.set_pixel(x, y, Color(1.0, 0.32, 0.12))
	return ImageTexture.create_from_image(img)

func _run() -> void:
	for i in 60:
		await get_tree().process_frame
	cam.position = Vector3(0, 3.0, 55.0)
	cam.look_at(Vector3(0, 1.0, -30.0))
	_yaw = cam.rotation.y
	_pitch = cam.rotation.x
	print("LIVE 启动 | fps=", Engine.get_frames_per_second())
	for i in 300:
		await get_tree().process_frame
	print("LIVE 300帧后 | fps=", Engine.get_frames_per_second())

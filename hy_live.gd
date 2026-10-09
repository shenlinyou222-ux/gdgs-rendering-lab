extends Node3D
## HY-World 贴片实况查看器:鼠标视角 | WASD/QE | Shift 加速 | Esc 退出
var cam: Camera3D
var _yaw := 0.0
var _pitch := 0.0
var _mouse_free := false
var _fps_lbl: Label
var _info := ""

func _ready() -> void:
	var res: GaussianResource = load("res://assets/hy_cell01.ply")
	print("hy_live: points=", res.point_count, " aabb=", res.aabb)
	var splat := GaussianSplatNode.new()
	add_child(splat)
	splat.gaussian = res
	_info = "60.8万点 | 28.5m 原生尺度 | Raster"

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.014, 0.02)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	cam = Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 800.0
	add_child(cam)
	var a: AABB = res.aabb
	var c: Vector3 = a.get_center()
	var dist: float = a.size.length() * 0.9
	cam.position = c + Vector3(0.55, 0.32, 0.77).normalized() * dist
	_yaw = atan2(cam.position.x - c.x, cam.position.z - c.z) + PI
	cam.look_at(c, Vector3.UP)

	var layer := CanvasLayer.new()
	add_child(layer)
	_fps_lbl = Label.new()
	_fps_lbl.position = Vector2(12, 8)
	_fps_lbl.add_theme_font_size_override("font_size", 16)
	layer.add_child(_fps_lbl)
	var help := Label.new()
	help.position = Vector2(12, 32)
	help.text = "鼠标=视角  WASD=移动  Q/E=降/升  Shift=加速(×3.3)  Esc=松开鼠标(再按退出)"
	help.add_theme_font_size_override("font_size", 14)
	layer.add_child(help)

	DisplayServer.window_set_title("HY-World 贴片实况 · " + _info)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(dt: float) -> void:
	if not _mouse_free:
		_fly(dt)
	_fps_lbl.text = "FPS %d | %s" % [Engine.get_frames_per_second(), _info]

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
		_pitch = clamp(_pitch - event.relative.y * 0.0022, -1.55, 1.55)

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
		var speed := 20.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 6.0
		cam.position += move.normalized() * speed * dt

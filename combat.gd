extends Node3D
## 第三幕战斗原型:星图环境 + HUD + 玩家激光射击判定 + 敌机路径/行为树
## 鼠标=视角 W/A/S/D=移动 Q/E=升降 Shift=加速 LMB/SPACE=射击 R=重开 Esc=退出

var cam: Camera3D
var jupiter: MeshInstance3D
var _yaw := 0.0
var _pitch := 0.0
var _mouse_free := false

var hp := 100
var score := 0
var fire_cd := 0.0
const FIRE_RATE := 0.12
const DMG := 34
var dead := false

var enemies: Array = []
var tracers: Array = []
var hud: Control
var lbl_main: Label
var lbl_feed: Label
var vignette: ColorRect
var hitmark_ttl := 0.0
var aim := Vector2.ZERO          # 准星偏移(浮动瞄准)
var mode_follow := true          # true=准星随鼠标+视角跟随; false=准星居中
const AIM_SENS := 0.85
var wave := 1
var wave_clear_ttl := 0.0

func _ready() -> void:
	_build_sky(); _build_star_layers(); _build_nebulae(); _build_light(); _build_jupiter()
	cam = Camera3D.new()
	cam.fov = 70; cam.far = 12000.0
	add_child(cam)
	cam.position = Vector3(0, 2, 70)
	_build_hud()
	_spawn_wave()
	DisplayServer.window_set_title("第三幕战斗原型 — 鼠标视角 | LMB 射击 | R 重开")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("combat ready")

func _spawn_wave() -> void:
	var path_a := _make_loop_path(Vector3(0, 0, -120), 90.0, 12.0)
	var path_b := _make_loop_path(Vector3(40, 15, -60), 70.0, -8.0)
	for i in 3:
		_spawn_enemy(path_a, 0.33 * i)
	for i in 3:
		_spawn_enemy(path_b, 0.33 * i)

func _make_loop_path(center: Vector3, radius: float, tilt: float) -> Curve3D:
	var c := Curve3D.new()
	for i in 8:
		var a := TAU * i / 8.0
		var p := center + Vector3(cos(a) * radius, sin(a * 2.0) * tilt, sin(a) * radius)
		c.add_point(p)
	c.add_point(c.get_point_position(0))
	return c

func _spawn_enemy(path: Curve3D, t0: float) -> void:
	var e := Enemy.new()
	add_child(e)
	e.setup(self, path, t0)
	enemies.append(e)

func _tick_enemy(e: Enemy, dt: float) -> void:
	if e.hp <= 0:
		return
	e.bt_tick(dt)

func _act_patrol(e: Enemy, dt: float) -> int:
	e.path_t = fmod(e.path_t + dt * e.speed / maxf(e.path.get_baked_length(), 1.0), 1.0)
	var target: Vector3 = e.path.sample_baked(e.path_t * e.path.get_baked_length())
	e.steer_to(target, dt)
	return 2

func _act_engage(e: Enemy, dt: float) -> int:
	var to_p: Vector3 = cam.global_position - e.global_position
	var orbit := to_p.normalized().cross(Vector3.UP).normalized() * 45.0 * e.orbit_dir
	var target: Vector3 = cam.global_position - to_p.normalized() * 90.0 + orbit
	e.steer_to(target, dt)
	e.gun_cd -= dt
	if e.gun_cd <= 0.0:
		e.gun_cd = 0.9 + randf() * 0.6
		_enemy_fire(e)
	return 2

func _act_evade(e: Enemy, dt: float) -> int:
	var away: Vector3 = (e.global_position - cam.global_position).normalized()
	var target: Vector3 = e.global_position + away * 60.0 + Vector3.UP * sin(Time.get_ticks_msec() * 0.003 + e.rseed) * 25.0
	e.steer_to(target, dt)
	e.heal_cd -= dt
	if e.heal_cd <= 0.0:
		e.hp = mini(e.hp + 8, 100)
		e.heal_cd = 1.0
	return 2

func _enemy_fire(e: Enemy) -> void:
	var from := e.global_position
	var to := cam.global_position + cam.basis.z * 10.0
	to += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (2.0 + from.distance_to(to) * 0.015)
	_add_tracer(from, to, Color(1.0, 0.35, 0.2))
	var d := _point_line_dist(cam.global_position, from, to)
	if d < 2.2 and not dead:
		hp -= 8
		vignette.color = Color(1, 0.1, 0.05, 0.35)
		if hp <= 0:
			hp = 0
			dead = true
			_feed("任务失败 — 按 R 重启")

func _point_line_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _fire() -> void:
	if dead or fire_cd > 0.0:
		return
	fire_cd = FIRE_RATE
	var from := cam.global_position + cam.basis.z * -1.0
	var to := from + _aim_dir() * 600.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 2)
	q.collide_with_areas = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	var endp := to
	if hit.has("collider") and hit["collider"] is Enemy:
		var e: Enemy = hit["collider"]
		endp = hit["position"]
		e.hp -= DMG
		hitmark_ttl = 0.12
		if e.hp <= 0:
			_explode(e.global_position)
			_feed("击落 +100")
			score += 100
			enemies.erase(e)
			e.queue_free()
			if enemies.is_empty():
				wave_clear_ttl = 3.0
	elif hit.has("position"):
		endp = hit["position"]
	_add_tracer(from + cam.basis.x * 0.6 - cam.basis.y * 0.4, endp, Color(0.5, 1.0, 0.8))

func _explode(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 42
	p.one_shot = true
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 26.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 2.2
	var qm := QuadMesh.new()
	qm.size = Vector2(0.8, 0.8)
	p.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.6, 0.2)
	p.material_override = m
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)

func _add_tracer(a: Vector3, b: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	mi.mesh = im
	add_child(mi)
	tracers.append({ "mi": mi, "ttl": 0.08 })

func _process(dt: float) -> void:
	if jupiter:
		jupiter.rotate_y(dt * 0.02)
	fire_cd = maxf(fire_cd - dt, 0.0)
	hitmark_ttl = maxf(hitmark_ttl - dt, 0.0)
	if not _mouse_free and not dead:
		_fly(dt)
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(KEY_SPACE):
			_fire()
	for i in range(tracers.size() - 1, -1, -1):
		tracers[i]["ttl"] -= dt
		if tracers[i]["ttl"] <= 0.0:
			(tracers[i]["mi"] as Node).queue_free()
			tracers.remove_at(i)
	if wave_clear_ttl > 0.0:
		wave_clear_ttl -= dt
		if wave_clear_ttl <= 0.0:
			wave += 1
			_feed("第 %d 波来袭" % wave)
			_spawn_wave()
	vignette.color.a = maxf(vignette.color.a - dt * 1.2, 0.0)
	hud.queue_redraw()
	lbl_main.text = "HP %d   得分 %d   敌机 %d   FPS %d" % [hp, score, enemies.size(), Engine.get_frames_per_second()]

func _feed(s: String) -> void:
	lbl_feed.text = s

func _aim_radius() -> float:
	var vp := get_viewport().get_visible_rect().size
	return minf(vp.x, vp.y) * 0.30

func _steer_follow(dt: float) -> void:
	var r := _aim_radius()
	if r <= 1.0:
		return
	var off := aim / r
	if off.length() > 0.12:
		var t := clampf((off.length() - 0.12) / 0.88, 0.0, 1.0)
		var rate := off.normalized() * t * 2.4 * dt
		_yaw -= rate.x
		_pitch = clampf(_pitch - rate.y, -1.45, 1.45)

func _aim_dir() -> Vector3:
	var vp := get_viewport().get_visible_rect().size
	if mode_follow:
		return cam.project_ray_normal(vp * 0.5 + aim)
	return cam.project_ray_normal(vp * 0.5)

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
		var speed := 60.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 26.0
		cam.position += move.normalized() * speed * dt

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if _mouse_free: get_tree().quit()
			else:
				_mouse_free = true
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_R:
			get_tree().reload_current_scene()
	elif event is InputEventMouseButton and event.pressed and _mouse_free and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_free = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and not _mouse_free:
		_yaw -= event.relative.x * 0.0022
		_pitch = clampf(_pitch - event.relative.y * 0.0022, -1.45, 1.45)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HUDCanvas.new()
	hud.root = self
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(hud)
	lbl_main = Label.new()
	lbl_main.position = Vector2(16, 10)
	lbl_main.add_theme_font_size_override("font_size", 16)
	layer.add_child(lbl_main)
	lbl_feed = Label.new()
	lbl_feed.position = Vector2(16, 34)
	lbl_feed.add_theme_font_size_override("font_size", 15)
	lbl_feed.modulate = Color(1, 0.9, 0.5)
	layer.add_child(lbl_feed)
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(1, 0, 0, 0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(vignette)
	vignette.z_index = -1

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
	var palette := [Color(0.72, 0.78, 1.0), Color(1, 1, 1), Color(1, 0.93, 0.78), Color(1, 0.75, 0.55), Color(1, 0.55, 0.45)]
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
	sphere.radius = 55.0; sphere.height = 110.0
	sphere.radial_segments = 96; sphere.rings = 48
	jupiter.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/8k_jupiter.jpg")
	mat.roughness = 1.0
	jupiter.material_override = mat
	jupiter.position = Vector3(-260, 90, -420)
	add_child(jupiter)

func _ship_texture() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(s / 2.0, s / 2.0)
	for y in s:
		for x in s:
			var p := Vector2(x - c.x, y - c.y)
			if absf(p.x) < 5.0 and absf(p.y) < 20.0:
				img.set_pixel(x, y, Color(1.0, 0.92, 0.75))
			elif absf(p.x) * 0.8 + absf(p.y) < 26.0:
				img.set_pixel(x, y, Color(1.0, 0.32, 0.12))
	return ImageTexture.create_from_image(img)

class Enemy extends Area3D:
	var root: Node3D
	var path: Curve3D
	var path_t := 0.0
	var speed := 42.0
	var hp := 100
	var vel := Vector3.ZERO
	var gun_cd := 1.0
	var heal_cd := 1.0
	var orbit_dir := 1.0
	var rseed := 0.0
	var bt_root: RefCounted
	var _bt_sel: RefCounted

	func setup(r: Node3D, p: Curve3D, t0: float) -> void:
		root = r
		path = p
		path_t = t0
		rseed = randf() * 100.0
		orbit_dir = 1.0 if randf() > 0.5 else -1.0
		collision_layer = 2
		collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(6.0, 6.0, 6.0)
		cs.shape = sh
		add_child(cs)
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(6.0, 6.0)
		mi.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_texture = root._ship_texture()
		mi.material_override = mat
		add_child(mi)
		position = p.sample_baked(t0 * p.get_baked_length())
		_bt_sel = BTSel.new([
			BTSeq.new([BTCond.new(func() -> bool: return hp < 30), BTAct.new(Callable(root, "_act_evade"))]),
			BTSeq.new([BTCond.new(func() -> bool: return root.cam.global_position.distance_to(global_position) < 260.0), BTAct.new(Callable(root, "_act_patrol_or_engage"))]),
			BTAct.new(Callable(root, "_act_patrol")),
		])

	func _process(_dt: float) -> void:
		if hp <= 0:
			return
		_bt_sel.tick(self, _dt)

	func steer_to(target: Vector3, dt: float) -> void:
		var want := (target - global_position).normalized() * speed
		vel = vel.lerp(want, clampf(dt * 1.6, 0.0, 1.0))
		global_position += vel * dt

func _act_patrol_or_engage(e: Enemy, dt: float) -> int:
	if cam.global_position.distance_to(e.global_position) < 260.0:
		return _act_engage(e, dt)
	return _act_patrol(e, dt)

const BT_SUCCESS := 0
const BT_FAILURE := 1
const BT_RUNNING := 2

class BTNode extends RefCounted:
	func tick(_e: Enemy, _dt: float) -> int:
		return BT_FAILURE

class BTSeq extends BTNode:
	var children: Array
	func _init(c: Array) -> void: children = c
	func tick(e: Enemy, dt: float) -> int:
		for ch in children:
			var s: int = ch.tick(e, dt)
			if s != BT_SUCCESS:
				return s
		return BT_SUCCESS

class BTSel extends BTNode:
	var children: Array
	func _init(c: Array) -> void: children = c
	func tick(e: Enemy, dt: float) -> int:
		for ch in children:
			var s: int = ch.tick(e, dt)
			if s != BT_FAILURE:
				return s
		return BT_FAILURE

class BTCond extends BTNode:
	var cond: Callable
	func _init(c: Callable) -> void: cond = c
	func tick(_e: Enemy, _dt: float) -> int:
		var r: bool = cond.call()
		return BT_SUCCESS if r else BT_FAILURE

class BTAct extends BTNode:
	var act: Callable
	func _init(a: Callable) -> void: act = a
	func tick(e: Enemy, dt: float) -> int:
		return act.call(e, dt)

class HUDCanvas extends Control:
	var root: Node3D = null

	func _draw() -> void:
		if root == null or root.cam == null:
			return
		var vp := get_viewport_rect().size
		var c := vp * 0.5
		var col := Color(0.6, 1.0, 0.8, 0.9)
		var spread := 10.0
		if root.fire_cd > 0.0:
			spread += 6.0
		draw_line(c + Vector2(-spread - 8, 0), c + Vector2(-spread, 0), col, 1.5)
		draw_line(c + Vector2(spread, 0), c + Vector2(spread + 8, 0), col, 1.5)
		draw_line(c + Vector2(0, -spread - 8), c + Vector2(0, -spread), col, 1.5)
		draw_line(c + Vector2(0, spread), c + Vector2(0, spread + 8), col, 1.5)
		if root.hitmark_ttl > 0.0:
			var h := 7.0
			var mc: Vector2 = c + (root.aim as Vector2)
			draw_line(mc + Vector2(-h, -h), mc + Vector2(-3, -3), Color(1, 0.3, 0.2), 2.0)
			draw_line(mc + Vector2(h, -h), mc + Vector2(3, -3), Color(1, 0.3, 0.2), 2.0)
			draw_line(mc + Vector2(-h, h), mc + Vector2(-3, 3), Color(1, 0.3, 0.2), 2.0)
			draw_line(mc + Vector2(h, h), mc + Vector2(3, 3), Color(1, 0.3, 0.2), 2.0)
		for e in root.enemies:
			if not is_instance_valid(e):
				continue
			var wp: Vector3 = e.global_position
			if root.cam.is_position_behind(wp):
				continue
			var sp: Vector2 = root.cam.unproject_position(wp)
			if sp.x < -50 or sp.y < -50 or sp.x > vp.x + 50 or sp.y > vp.y + 50:
				continue
			var d := wp.distance_to(root.cam.global_position)
			var sz := clampf(1600.0 / maxf(d, 1.0), 10.0, 46.0)
			var bc := Color(1.0, 0.45, 0.3, 0.85) if d < 200.0 else Color(1.0, 0.8, 0.4, 0.6)
			var p1 := sp + Vector2(-sz, -sz) * 0.5
			var p2 := sp + Vector2(sz, -sz) * 0.5
			var p3 := sp + Vector2(sz, sz) * 0.5
			var p4 := sp + Vector2(-sz, sz) * 0.5
			var L := sz * 0.35
			draw_line(p1, p1 + Vector2(L, 0), bc, 1.5)
			draw_line(p1, p1 + Vector2(0, L), bc, 1.5)
			draw_line(p2, p2 + Vector2(-L, 0), bc, 1.5)
			draw_line(p2, p2 + Vector2(0, L), bc, 1.5)
			draw_line(p3, p3 + Vector2(-L, 0), bc, 1.5)
			draw_line(p3, p3 + Vector2(0, -L), bc, 1.5)
			draw_line(p4, p4 + Vector2(L, 0), bc, 1.5)
			draw_line(p4, p4 + Vector2(0, -L), bc, 1.5)
			var font := ThemeDB.fallback_font
			draw_string(font, sp + Vector2(-sz * 0.5, sz * 0.5 + 14), "%dm" % int(d), HORIZONTAL_ALIGNMENT_CENTER, sz, 11, bc)

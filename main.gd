extends Node3D
## gdgs_lab: 验证 3DGS(gdgs 插件) + 公告板敌人 + 代理碰撞 + 深度遮挡 共存
## 运行后自动截 3 张图到 res://shots/,打印射线检测结果,然后退出。

const SHOT_DIR := "res://shots"

var cam: Camera3D
var center: Vector3
var radius: float = 1.0
var target_enemy: Area3D
var wall_body: StaticBody3D
var occluder: MeshInstance3D

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	_build_environment()
	_build_splat()
	_build_props()
	_run()

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.45)
	env.ambient_light_energy = 0.7

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# The Compute backend attaches its own CompositorEffect on first node
	# registration (see gaussian_compute_backend.gd); nothing to do here.

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	add_child(sun)

	cam = Camera3D.new()
	cam.fov = 70
	add_child(cam)
	cam.current = true

func _build_splat() -> void:
	var res: GaussianResource = load("res://assets/demo.compressed.ply")
	if res == null:
		push_error("FATAL: gaussian resource failed to load")
		get_tree().quit(1)
		return
	print("splat loaded: points=", res.point_count, " aabb=", res.aabb)
	var splat := GaussianSplatNode.new()
	add_child(splat)
	splat.gaussian = res
	var aabb: AABB = res.aabb
	if aabb.size != Vector3.ZERO:
		center = aabb.get_center()
		radius = maxf(aabb.size.length() * 0.5, 0.5)

func _pos_a() -> Vector3:
	return center + Vector3(0.75, 0.35, 1.1).normalized() * radius * 2.4

func _pos_b() -> Vector3:
	return center + Vector3(-0.6, 0.25, 0.9).normalized() * radius * 1.6

func _build_props() -> void:
	var cam_a := _pos_a()
	var to_cam := (cam_a - center).normalized()

	# --- 代理碰撞墙(代替 splat 承接物理/射线),半可见 ---
	var wall_pos := center + to_cam * radius * 1.1
	wall_body = StaticBody3D.new()
	wall_body.position = wall_pos
	var wcs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(radius * 1.6, radius * 1.6, 0.06)
	wcs.shape = box
	wall_body.add_child(wcs)
	var wmesh := MeshInstance3D.new()
	var wbox := BoxMesh.new()
	wbox.size = Vector3(radius * 1.6, radius * 1.6, 0.06)
	wmesh.mesh = wbox
	var wmat := StandardMaterial3D.new()
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wmat.albedo_color = Color(0.25, 0.55, 1.0, 0.16)
	wmesh.material_override = wmat
	wall_body.add_child(wmesh)
	add_child(wall_body)
	wall_body.look_at(center, Vector3.UP)

	# --- 不透明遮挡箱:验证 splat 与普通网格的深度互相遮挡 ---
	occluder = MeshInstance3D.new()
	var om := BoxMesh.new()
	om.size = Vector3(radius * 0.55, radius * 0.55, radius * 0.55)
	occluder.mesh = om
	var omat := StandardMaterial3D.new()
	omat.albedo_color = Color(0.55, 0.55, 0.6)
	omat.roughness = 0.6
	occluder.material_override = omat
	occluder.position = center + to_cam.rotated(Vector3.UP, 0.15) * radius * 1.25
	add_child(occluder)

	# --- 公告板敌机 x3 ---
	var tex := _ship_texture()
	for i in 3:
		var e := _make_enemy(tex, radius * (0.28 if i == 0 else 0.2))
		if i == 0:
			e.position = center + to_cam * radius * 1.5 + to_cam.cross(Vector3.UP) * radius * 0.45
			target_enemy = e
		elif i == 1:
			e.position = center + to_cam * radius * 1.5 - to_cam.cross(Vector3.UP) * radius * 0.5
		else:
			e.position = center + to_cam * radius * 0.5
		add_child(e)

func _make_enemy(tex: Texture2D, size: float) -> Area3D:
	var root := Area3D.new()
	root.monitorable = true
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

func _shot(fname: String) -> void:
	for i in 15:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(SHOT_DIR + "/" + fname)
	img.save_png(path)
	print("SAVED ", fname, " ", img.get_size(), " fps=", Engine.get_frames_per_second())

func _run() -> void:
	for i in 90:
		await get_tree().process_frame
	occluder.visible = false
	cam.position = _pos_a()
	cam.look_at(center)
	await _shot("01_overview_splat_plus_billboard_enemies.png")

	cam.position = _pos_b()
	cam.look_at(center)
	await _shot("02_closeup_other_angle.png")

	occluder.visible = true
	cam.position = _pos_a()
	cam.look_at(center)
	await _shot("03_occluder_blocks_splat.png")

	_run_rays()
	get_tree().quit()

func _run_rays() -> void:
	var space := get_world_3d().direct_space_state
	var from := cam.global_position

	# 射线1: 打向敌机(期待先命中 Area3D)
	var q1 := PhysicsRayQueryParameters3D.create(from, target_enemy.global_position)
	q1.collide_with_areas = true
	q1.collide_with_bodies = true
	var h1 := space.intersect_ray(q1)
	if h1.is_empty():
		print("RAY_ENEMY: MISS")
	else:
		print("RAY_ENEMY: hit ", h1["collider"].get_class(), " name=", h1["collider"].name,
			" at ", h1["position"])

	# 射线2: 打向 splat 中心(期待被代理墙 StaticBody3D 挡住 -> 证明 splat 本身不参与物理,需要代理)
	var q2 := PhysicsRayQueryParameters3D.create(from, center)
	q2.collide_with_areas = false
	q2.exclude.append(target_enemy.get_rid())
	var h2 := space.intersect_ray(q2)
	if h2.is_empty():
		print("RAY_CENTER: MISS (splat 本体无碰撞,符合预期之外,需检查代理)")
	else:
		print("RAY_CENTER: hit ", h2["collider"].get_class(), " name=", h2["collider"].name,
			" at ", h2["position"], " <- 由代理碰撞墙挡住,而非 splat")

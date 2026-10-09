extends Node3D
## v0.7 crowd 展示探针(隐藏窗口渲染):
##  - 3 条机群流 = 3 种机型 × 3 种编队行为(p1 VEE / p2 SNAKE / p3 RING)
##  - 验证:低模+高斯绑定外观、编队几何、朝向/侧倾、高斯↔低模 LOD 互斥切换
##  - 输出 shots/crowd_show_*.png + CULL/POSE 校验行

var cam: Camera3D
var streams: Array = []
var far_jet: Area3D = null
var t := 0.0
var shot_idx := 0

class Jet extends Area3D:
	var stream  # Crowd.Stream
	var slot_i := 0
	var vel := Vector3.ZERO
	var speed := 40.0
	var hp := 100
	var engaging := false
	var gs_node: GaussianSplatNode
	var mesh_node: MeshInstance3D

	func _process(dt: float) -> void:
		var target: Vector3 = stream.slot_pos(slot_i)
		var want := (target - global_position).normalized() * speed
		vel = vel.lerp(want, clampf(dt * 1.6, 0.0, 1.0))
		global_position += vel * dt
		if vel.length_squared() > 9.0:
			var tb := Basis.looking_at(vel.normalized(), Vector3.UP)
			basis = basis.slerp(tb, clampf(dt * 4.0, 0.0, 1.0)).orthonormalized()

func _b(_sec: String, key: String) -> float:
	return 1800.0 if key == "splat_range" else 0.0

func _bi(_sec: String, key: String) -> int:
	return 4 if key == "attack_tokens" else 0

func _make_stream(type_id: String, behavior: int, center: Vector3, radius: float, n: int) -> Crowd.Stream:
	var s := Crowd.Stream.new()
	s.root = self
	s.behavior = behavior
	s.type_id = type_id
	s.members_n = n
	s.leader_t = 0.0
	s.dir = 1.0
	s.speed = 42.0 * float(Crowd.TYPES[type_id]["speed_mul"]) * 0.8
	var c := Curve3D.new()
	for i in 16:
		var a := TAU * i / 16.0
		c.add_point(center + Vector3(cos(a) * radius, sin(a * 2.0) * 6.0, sin(a) * radius))
	c.add_point(c.get_point_position(0))
	s.path = c
	for i in n:
		var e := Jet.new()
		e.stream = s
		e.slot_i = i
		e.speed = 42.0 * float(Crowd.TYPES[type_id]["speed_mul"])
		var built: Dictionary = Crowd.build_jet(e, type_id)
		e.gs_node = built["gs"]
		e.mesh_node = built["mesh"]
		add_child(e)
		e.global_position = s.slot_pos(i)   # 出生即在编队位(照片立即可见)
		s.members.append(e)
	streams.append(s)
	return s

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.014, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.65)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 25, 0)
	sun.light_energy = 1.3
	add_child(sun)

	# 3 流:不同机型 × 不同行为 × 不同环心(p1 VEE / p2 SNAKE / p3 RING)
	_make_stream("p1", Crowd.Stream.VEE, Vector3(0, 0, 0), 80.0, 21)
	_make_stream("p2", Crowd.Stream.SNAKE, Vector3(150, 18, 60), 60.0, 21)
	_make_stream("p3", Crowd.Stream.RING, Vector3(-150, -12, 90), 55.0, 20)

	# 远距个体:验证 高斯→低模 剪影 LOD 互斥
	far_jet = Jet.new()
	far_jet.stream = streams[0]
	far_jet.slot_i = 0
	far_jet.speed = 40.0
	var b2: Dictionary = Crowd.build_jet(far_jet, "p1")
	far_jet.gs_node = b2["gs"]
	far_jet.mesh_node = b2["mesh"]
	add_child(far_jet)
	far_jet.global_position = Vector3(0, 0, 2400)
	far_jet.vel = Vector3(0, 0, 5)   # 保持微动,避开 Raster 静止节点疑点

	cam = Camera3D.new()
	cam.fov = 65.0
	cam.far = 8000.0
	add_child(cam)

func _process(dt: float) -> void:
	t += dt
	for s in streams:
		s.tick(dt)
	var plan := [
		[1.0, Vector3(90, 55, 210), Vector3(0, 0, 0)],          # 全景:三条流编队
		[4.0, Vector3(150, 40, 175), Vector3(150, 18, 60)],     # 近景:p2 SNAKE 蛇形纵队
		[7.0, Vector3(-60, 45, -160), Vector3(0, 0, 0)],        # 尾后:p1 VEE 箭头
		[9.5, Vector3(-240, 120, 240), Vector3(-150, -12, 90)], # 斜俯:p3 RING 环形包围
	]
	if shot_idx < plan.size() and t >= float(plan[shot_idx][0]):
		var p: Array = plan[shot_idx]
		cam.global_position = p[1]
		cam.look_at(p[2], Vector3.UP)
		_shoot("crowd_show_%d" % (shot_idx + 1))
		shot_idx += 1
		if shot_idx >= plan.size():
			_report_and_quit()

func _shoot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/%s.png" % nm)
	print("SHOT saved %s (t=%.1f)" % [nm, t])

func _report_and_quit() -> void:
	var d := cam.global_position.distance_to(far_jet.global_position)
	print("CULL far_jet dist=%.0f gs_visible=%s mesh_visible=%s (expect false/true beyond 1800m)" % [d, far_jet.gs_node.visible, far_jet.mesh_node.visible])
	var rendered := 0
	for s in streams:
		for m in s.members:
			if m.gs_node.visible:
				rendered += 1
		print("POSE stream %s:%s members=%d leader_t=%.3f slot0=%s" % [s.type_id, Crowd.Stream.behavior_name(s.behavior), s.alive_count(), s.leader_t, s.members[0].global_position])
	print("GS VISIBLE %d / %d" % [rendered, streams.reduce(func(a, s): return a + s.alive_count(), 0)])
	get_tree().quit()

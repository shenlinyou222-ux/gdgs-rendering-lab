extends Node3D
## 探针 v8: 隔离复现 — 仅地球 L0 splat, 不同距离渲染测试
var cam: Camera3D
var t := 0.0
var step := 0
var steps := [290.0, 150.0, 100.0, 64.0, 30.0]
var angles := [12.7, 25.2, 39.6, 85.0, 88.0]

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.02)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var res: GaussianResource = load("res://assets/splat_planets/earth_l0.ply")
	print("EARTH L0 points=", res.point_count, " aabb=", res.aabb)
	var n := GaussianSplatNode.new()
	add_child(n)
	n.gaussian = res
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 60000.0
	add_child(cam)

func _process(dt: float) -> void:
	t += dt
	if step < steps.size() and t >= 1.0 + float(step) * 1.5:
		var d: float = steps[step]
		cam.position = Vector3(0.411, 0.137, 0.891).normalized() * d
		cam.look_at(Vector3.ZERO, Vector3.UP)
		_shot(d, angles[step])
		step += 1
		if step >= steps.size():
			print("PROBE8-DONE")
			get_tree().quit()

func _shot(d: float, ang: float) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/dbg8_d%03d.png" % int(d))
	var s := 0.0
	var n := 0
	var cy := int(img.get_height() * 0.5)
	var cx := int(img.get_width() * 0.5)
	for y in range(cy - 120, cy + 120, 2):
		for x in range(cx - 120, cx + 120, 2):
			var p: Color = img.get_pixel(x, y)
			s += p.r * 0.3 + p.g * 0.6 + p.b * 0.1
			n += 1
	print("SHOT d=%dm 角径%.1f° center240=%.3f" % [int(d), ang, s / float(n)])

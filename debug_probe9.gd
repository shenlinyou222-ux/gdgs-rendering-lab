extends Node3D
## 探针 v9: 方向矩阵 — 相机在 ±Z 侧 × 节点 look_at 与否, 距离 290/150/64
var cam: Camera3D
var node: GaussianSplatNode
var t := 0.0
var idx := 0
# [相机侧符号, 节点是否look_at(-Z), 距离]
var cases := [
	[1.0, false, 290.0], [-1.0, false, 290.0],
	[-1.0, true, 290.0], [1.0, true, 290.0],
	[-1.0, false, 150.0], [-1.0, true, 150.0],
	[-1.0, false, 64.0], [-1.0, true, 64.0],
]

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.02)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	node = GaussianSplatNode.new()
	add_child(node)
	node.gaussian = load("res://assets/splat_planets/earth_l0.ply")
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 60000.0
	add_child(cam)

func _process(dt: float) -> void:
	t += dt
	if idx < cases.size() and t >= 1.0 + float(idx) * 1.2:
		var c: Array = cases[idx]
		var side: float = c[0]
		var use_look: bool = c[1]
		var d: float = c[2]
		if use_look:
			node.look_at(Vector3(0.0, 0.0, -1000.0), Vector3.UP)
		else:
			node.rotation = Vector3.ZERO
		cam.position = Vector3(0.0, 0.0, side * d)
		cam.look_at(Vector3.ZERO, Vector3.UP)
		_shot(idx, side, use_look, d)
		idx += 1
		if idx >= cases.size():
			print("PROBE9-DONE")
			get_tree().quit()

func _shot(idx: int, side: float, use_look: bool, d: float) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/dbg9_%02d.png" % idx)
	var s := 0.0
	var n := 0
	var cy := int(img.get_height() * 0.5)
	var cx := int(img.get_width() * 0.5)
	for y in range(cy - 120, cy + 120, 2):
		for x in range(cx - 120, cx + 120, 2):
			var p: Color = img.get_pixel(x, y)
			s += p.r * 0.3 + p.g * 0.6 + p.b * 0.1
			n += 1
	print("CASE%02d side=%+d look=%s d=%dm center240=%.3f" % [idx, int(side), str(use_look), int(d), s / float(n)])

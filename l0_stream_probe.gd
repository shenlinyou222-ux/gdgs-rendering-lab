extends Node3D
## v0.8 L0 流式验证探针: 线程加载地球 L0 → 显存增量 → gaussian=null 卸载 → 显存回收?
## 通过标准: 卸载后 vram 回落到接近基线(±30MB), 加载后增量 ≈ 资源大小

var cam: Camera3D
var node: GaussianSplatNode
var node2: GaussianSplatNode
var t := 0.0
var step := 0

func _vram() -> float:
	return Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0

func _ready() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.02)
	we.environment = env
	add_child(we)
	cam = Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	node = GaussianSplatNode.new()
	add_child(node)
	node.position = Vector3(0, 0, -260)
	node.look_at(Vector3.ZERO, Vector3.UP)
	_probe_base = _vram()
	print("PROBE baseline vram=%.0fMB" % _vram())

func _process(dt: float) -> void:
	t += dt
	match step:
		0:
			if t > 1.0:
				print("PROBE t=1 vram=%.0fMB" % _vram())
				ResourceLoader.load_threaded_request("res://assets/splat_planets/earth_l0.ply")
				print("PROBE L0 threaded load requested")
				step = 1
		1:
			var sts: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status("res://assets/splat_planets/earth_l0.ply")
			if sts == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_LOADED:
				var res: GaussianResource = ResourceLoader.load_threaded_get("res://assets/splat_planets/earth_l0.ply")
				node.scale = Vector3.ONE * (100.0 * 0.996 / maxf(res.aabb.size.x * 0.5, 0.001))
				node.gaussian = res
				print("PROBE L0 loaded(%dk) vram=%.0fMB t=%.1fs" % [res.point_count / 1000, _vram(), t])
				step = 2
			elif sts == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_FAILED or sts == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_INVALID_RESOURCE:
				print("PROBE L0 LOAD FAILED")
				step = 5
		2:
			if t > 8.0:
				print("PROBE after dwell vram=%.0fMB" % _vram())
				node.gaussian = null   # 关键假设: 置空即回收
				step = 3
		3:
			if t > 10.0:
				print("PROBE after gaussian=null vram=%.0fMB" % _vram())
				node.queue_free()   # 第二种卸载策略: 整节点释放
				step = 4
		4:
			if t > 12.0:
				print("PROBE after node free vram=%.0fMB" % _vram())
				node2 = GaussianSplatNode.new()
				add_child(node2)
				node2.position = Vector3(0, 0, -260)
				node2.look_at(Vector3.ZERO, Vector3.UP)
				ResourceLoader.load_threaded_request("res://assets/splat_planets/earth_l0.ply")
				step = 7
		7:
			var sts2: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status("res://assets/splat_planets/earth_l0.ply")
			if sts2 == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_LOADED:
				var res2: GaussianResource = ResourceLoader.load_threaded_get("res://assets/splat_planets/earth_l0.ply")
				node2.scale = Vector3.ONE * (100.0 * 0.996 / maxf(res2.aabb.size.x * 0.5, 0.001))
				node2.gaussian = res2
				print("PROBE 2nd load vram=%.0fMB t=%.1fs" % [_vram(), t])
				step = 8
		8:
			if t > 16.0:
				print("PROBE FINAL vram=%.0fMB (基线 %.0fMB) 泄漏=%s" % [_vram(), _probe_base, "NO" if _vram() < 223.0 else "YES"])
				get_tree().quit()
		5:
			get_tree().quit()

var _probe_base := 0.0

func _unhandled_input(_e: InputEvent) -> void:
	pass

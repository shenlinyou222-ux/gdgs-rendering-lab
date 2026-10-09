extends Node3D
## gdgs-bench 评测内核 v0.1 —— 学习成果展示用评测工具
##
## 用法（由 Python 编排器调用）:
##   godot --path <gdgs_lab> res://bench/bench_runner.tscn -- --bench-config=<abs.json>
##
## 行为:
##   1. 关闭垂直同步 / 取消帧率上限（暴露真实帧时间）
##   2. 按配置搭建确定性场景（fleet = 战机编队，静态、无随机；whale = 星鲸，仅性能）
##   3. 预热 N 帧后测量 M 帧：逐帧帧时间(墙钟) + process_ms + VRAM + FPS
##   4. 按配置在固定机位截图（A/B 像素级对比用，确定性）
##   5. 写出 report.json / frames.csv / shot_*.png 后退出

const BACKEND_SELECTOR := preload("res://addons/gdgs/runtime/render/backend/gaussian_backend_selector.gd")

var _cfg: Dictionary = {}
var _out_dir := ""
var _warmup := 90
var _measure := 180
var _cam: Camera3D
var _scene_center := Vector3.ZERO
var _scene_radius := 100.0
var _cam_radius := 300.0
var _deg_per_frame := 0.15
var _orbit_seed := 0.0
var _whale: Node3D = null
var _splat_nodes: Array = []
var _node_resources: Array = []
var _shots: Array = []
var _deterministic := true
var _scene_name := "fleet"
var _total_points := 0

func _ready() -> void:
	_parse_args()
	if _cfg.is_empty():
		push_error("BENCH-FATAL: no valid --bench-config")
		get_tree().quit(2)
		return
	_out_dir = str(_cfg.get("out_dir", "res://bench/out"))
	_warmup = int(_cfg.get("warmup_frames", 90))
	_measure = int(_cfg.get("measure_frames", 180))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var win: Dictionary = _cfg.get("window", {})
	DisplayServer.window_set_size(Vector2i(int(win.get("w", 1280)), int(win.get("h", 720))))
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_apply_toggles()
	_build_environment()
	_scene_name = str(_cfg.get("scene", "fleet"))
	match _scene_name:
		"whale":
			_deterministic = false
			_build_whale()
		_:
			_build_fleet(_cfg)
	_setup_camera(_cfg)
	for i in 4:
		await get_tree().process_frame
	print("BENCH scene=%s deterministic=%s splat_nodes=%d" % [_scene_name, _deterministic, _splat_nodes.size()])
	var frames: Array = await _measure_frames()
	var stats: Dictionary = _compute_stats(frames)
	await _take_shots()
	_write_report(frames, stats)
	_print_summary(stats)
	get_tree().quit(0)

# ---------------------------------------------------------------- args/config
func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bench-config="):
			var p := a.substr("--bench-config=".length())
			p = p.replace("\\", "/")
			if not p.is_absolute_path():
				p = ProjectSettings.globalize_path(p)
			var f := FileAccess.open(p, FileAccess.READ)
			if f == null:
				push_error("BENCH-FATAL: cannot open config " + p)
				return
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_cfg = parsed
			else:
				push_error("BENCH-FATAL: bad JSON in " + p)

# A/B toggles: config may carry a `toggles` map of project-setting overrides
# (e.g. {"gdgs/opt/sh_dc_force": 3}) applied before the scene is built, so the
# same binary can run the pre-optimisation baseline and the fast path.
func _apply_toggles() -> void:
	var toggles: Dictionary = _cfg.get("toggles", {})
	for key in toggles:
		ProjectSettings.set_setting(str(key), toggles[key])
		print("BENCH toggle %s = %s" % [str(key), str(toggles[key])])

# ---------------------------------------------------------------- scene build
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.01, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.5)
	env.ambient_light_energy = 0.5
	we.environment = env
	# M5-D: the Compute backend renders through a CompositorEffect attached to the
	# WorldEnvironment. Attach it unconditionally — on Raster the effect's manager
	# lookup fails and it is a no-op, while on Compute it is required. This used to
	# be scene-side (main.gd) which the 4.7 compositor bug hit (research/06 踩坑4);
	# keeping it in the bench scene makes the Compute path testable end-to-end.
	add_child(we)
	# M5-D: the Compute backend attaches its own CompositorEffect (idempotent
	# singleton) when it is selected, so the bench scene stays backend-agnostic
	# and Raster runs do not allocate compute-only compositor resources.

func _build_fleet(cfg: Dictionary) -> void:
	var fleet: Dictionary = cfg.get("fleet", {})
	var types: Array = ["P1", "P2", "P3"]
	var counts := {
		"P1": int(fleet.get("P1", 20)),
		"P2": int(fleet.get("P2", 15)),
		"P3": int(fleet.get("P3", 15)),
	}
	var scale := float(fleet.get("scale", 1.0))
	var spacing_factor := float(fleet.get("spacing", 1.6))
	var max_span := 0.0
	var total_points := 0
	for t in types:
		var count: int = counts[t]
		if count <= 0:
			continue
		var res: GaussianResource = load("res://assets/jets/%s_splats.ply" % t)
		if res == null:
			push_error("BENCH: failed to load jet " + t)
			continue
		var size := maxf(res.aabb.size.length(), 1.0)
		var spacing := size * spacing_factor
		var cols := int(ceil(sqrt(float(count))))
		var rows := int(ceil(float(count) / float(cols)))
		for i in count:
			var row := i / cols
			var col := i % cols
			var pos := Vector3(
				(float(col) - float(cols - 1) * 0.5) * spacing,
				(float(row) - float(rows - 1) * 0.5) * spacing * 0.55,
				0.0)
			var node := GaussianSplatNode.new()
			add_child(node)
			node.position = pos
			node.scale = Vector3.ONE * scale
			node.gaussian = res
			_splat_nodes.append(node)
			_node_resources.append(res)
		total_points += res.point_count * count
		_total_points += res.point_count * count
		max_span = maxf(max_span, float(cols) * spacing)
	_scene_center = Vector3.ZERO
	_scene_radius = maxf(max_span * 0.55, 0.5)
	print("BENCH fleet points=%d radius=%.1f" % [total_points, _scene_radius])

func _build_whale() -> void:
	var w: Node3D = StarWhale.create(Vector3.ZERO)
	add_child(w)
	if w.has_method("start_reveal"):
		w.start_reveal()
	_whale = w
	_scene_radius = 2600.0
	_splat_nodes.append(w)
	var gs: Variant = w.get("_gs_node")
	if gs != null:
		var res: Variant = gs.get("gaussian")
		if res != null:
			_total_points = int(res.get("point_count"))
	print("BENCH whale built")

func _setup_camera(cfg: Dictionary) -> void:
	var cc: Dictionary = cfg.get("camera", {})
	_cam = Camera3D.new()
	_cam.fov = float(cc.get("fov", 65.0))
	_cam.near = 0.1
	_cam.far = float(cc.get("far", 60000.0))
	add_child(_cam)
	_cam.make_current()
	_deg_per_frame = float(cc.get("deg_per_frame", 0.15))
	_orbit_seed = float(cc.get("seed", 0.0))
	var tr: Array = cc.get("target", [0.0, 0.0, 0.0])
	_scene_center = _v3(tr)
	_cam_radius = float(cc.get("radius", 0.0))
	if _cam_radius <= 0.0:
		_cam_radius = maxf(_scene_radius * 1.9, 5.0)

func _tick_orbit(idx: int) -> void:
	var a := deg_to_rad(float(idx) * _deg_per_frame + _orbit_seed)
	if _whale != null:
		var wp: Vector3 = _whale.call("current_pos")
		_cam.position = wp + Vector3(cos(a), 0.30, sin(a)) * _cam_radius
		_cam.look_at(wp + Vector3(0.0, 5.0, 0.0), Vector3.UP)
	else:
		_cam.position = _scene_center + Vector3(cos(a), 0.30, sin(a)) * _cam_radius
		_cam.look_at(_scene_center, Vector3.UP)

func _v3(arr: Array) -> Vector3:
	if arr.size() < 3:
		return Vector3.ZERO
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))

# ---------------------------------------------------------------- measurement
func _measure_frames() -> Array:
	for i in _warmup:
		_tick_orbit(i)
		await get_tree().process_frame
	var frames: Array = []
	var prev := Time.get_ticks_usec()
	for i in _measure:
		_tick_orbit(i)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt_ms := float(now - prev) / 1000.0
		prev = now
		frames.append({
			"f": i,
			"frame_ms": dt_ms,
			"process_ms": Performance.get_monitor(Performance.TIME_PROCESS),
			"vram_mb": float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0,
			"fps": Engine.get_frames_per_second(),
			"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		})
	return frames

func _take_shots() -> void:
	for s in _cfg.get("shots", []):
		var dist := float(s.get("dist", 2.5))
		var az := deg_to_rad(float(s.get("azimuth", 0.0)))
		var el := float(s.get("elevation", 0.25))
		var r := _cam_radius * dist
		# Aim at the whale's current position (like _tick_orbit) so whale shots
		# frame the whale; static scenes keep the origin target.
		var target: Vector3 = _whale.call("current_pos") if _whale != null else _scene_center
		var pos: Vector3 = target + Vector3(sin(az) * r, el * r, cos(az) * r)
		_cam.position = pos
		_cam.look_at(target + (Vector3(0.0, 5.0, 0.0) if _whale != null else Vector3.ZERO), Vector3.UP)
		var settle := int(s.get("settle_frames", 20))
		for i in settle:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img == null:
			push_error("BENCH: screenshot failed for " + str(s.get("name")))
			continue
		var nm := str(s.get("name", "shot"))
		var p := _out_dir + "/shot_" + nm + ".png"
		img.save_png(p)
		_shots.append({"name": nm, "path": p, "size": [img.get_width(), img.get_height()]})
		print("BENCH shot=%s saved %dx%d" % [nm, img.get_width(), img.get_height()])

# ---------------------------------------------------------------- stats/report
static func _percentile(arr: Array, p: float) -> float:
	if arr.is_empty():
		return 0.0
	var s := arr.duplicate()
	s.sort()
	var idx := clampi(int(round(float(s.size() - 1) * p)), 0, s.size() - 1)
	return float(s[idx])

static func _stats_of(arr: Array) -> Dictionary:
	if arr.is_empty():
		return {"mean": 0.0, "p50": 0.0, "p95": 0.0, "p99": 0.0, "min": 0.0, "max": 0.0}
	var sum := 0.0
	for v in arr:
		sum += float(v)
	return {
		"mean": sum / float(arr.size()),
		"p50": _percentile(arr, 0.5),
		"p95": _percentile(arr, 0.95),
		"p99": _percentile(arr, 0.99),
		"min": float(arr.min()),
		"max": float(arr.max()),
	}

func _compute_stats(frames: Array) -> Dictionary:
	var fms: Array = []
	var pms: Array = []
	var vms: Array = []
	for fr in frames:
		fms.append(float(fr["frame_ms"]))
		pms.append(float(fr["process_ms"]))
		vms.append(float(fr["vram_mb"]))
	var fps_vals: Array = []
	var fps_derived: Array = []
	for fr in frames:
		fps_vals.append(float(fr["fps"]))
		fps_derived.append(1000.0 / maxf(float(fr["frame_ms"]), 0.001))
	return {
		"frame_ms": _stats_of(fms),
		"process_ms": _stats_of(pms),
		"vram_mb": _stats_of(vms),
		"fps": _stats_of(fps_vals),
		"fps_derived": _stats_of(fps_derived),
	}

func _write_report(frames: Array, stats: Dictionary) -> void:
	var total_points := _total_points
	var per_type := {}
	var backend_name := "unknown"
	var backend := BACKEND_SELECTOR.get_backend(self)
	if backend != null and backend.has_method("get_display_name"):
		backend_name = str(backend.get_display_name())
	var report := {
		"tool": "gdgs-bench v0.1",
		"godot": Engine.get_version_info().get("string", "?"),
		"backend": backend_name,
		"scene": _scene_name,
		"deterministic": _deterministic,
		"window": {"w": DisplayServer.window_get_size().x, "h": DisplayServer.window_get_size().y},
		"vsync": "disabled",
		"max_fps": 0,
		"splats": {"nodes": _splat_nodes.size(), "points": total_points, "per_type": per_type},
		"warmup_frames": _warmup,
		"measure_frames": _measure,
		"stats": stats,
		"frames": frames,
		"shots": _shots,
	}
	var f := FileAccess.open(_out_dir + "/report.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
	var csv := FileAccess.open(_out_dir + "/frames.csv", FileAccess.WRITE)
	if csv != null:
		csv.store_line("f,frame_ms,process_ms,vram_mb,fps")
		for fr in frames:
			csv.store_line("%d,%.3f,%.3f,%.2f,%.1f" % [
				int(fr["f"]), float(fr["frame_ms"]), float(fr["process_ms"]), float(fr["vram_mb"]), float(fr["fps"])])
		csv.close()
	print("BENCH report written to " + _out_dir)

func _print_summary(stats: Dictionary) -> void:
	var fm: Dictionary = stats["frame_ms"]
	var fp: Dictionary = stats["fps"]
	var fpd: Dictionary = stats.get("fps_derived", fp)
	var backend_name := "unknown"
	var backend := BACKEND_SELECTOR.get_backend(self)
	if backend != null and backend.has_method("get_display_name"):
		backend_name = str(backend.get_display_name())
	print("BENCH_RESULT fps_mean=%.1f fps_p95=%.1f frame_ms_mean=%.2f frame_ms_p95=%.2f frame_ms_p99=%.2f vram_max=%.0fMB scene=%s backend=%s" % [
		fpd["mean"], fpd["p95"], fm["mean"], fm["p95"], fm["p99"], stats["vram_mb"]["max"], _scene_name, backend_name])

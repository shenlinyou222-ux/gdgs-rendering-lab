extends Node3D
## v0.9 星鲸展示探针: 相机在鲸下方仰拍, 记录 渐显→成形→游动 三个阶段
## 验证: 384k 高斯球渲染、渐显线性扫描、游泳波、球形战机外壳近景

var cam: Camera3D
var whale: StarWhale
var t := 0.0
var shot := 0

func _ready() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.01, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.5)
	env.ambient_light_energy = 0.5
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 20, 0)
	sun.light_energy = 1.4
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 65.0
	cam.far = 8000.0
	add_child(cam)
	whale = StarWhale.create(Vector3(0, 0, 0))
	add_child(whale)
	whale.start_reveal()

func _process(dt: float) -> void:
	t += dt
	var wp: Vector3 = whale.current_pos()

	var hd: Vector3 = whale.heading()
	# 相机: 垂直于航向的侧面机位(固定世界轴偏移会撞上尾轴透视, 全身被压缩成一簇)
	var side: Vector3 = hd.cross(Vector3.UP).normalized()
	var back: float = [1200.0, 1600.0, 2000.0, 2400.0][shot] if shot < 4 else 1600.0
	var oa := t * 0.12 + shot * 1.35
	cam.position = wp + Vector3(cos(oa), 0.30, sin(oa)) * (1300.0 + 500.0 * shot)
	cam.look_at(wp + Vector3(0.0, 5.0, 0.0), Vector3.UP)
	var plan := [[2.0, "whale_reveal"], [7.0, "whale_forming"], [13.0, "whale_swim"], [20.0, "whale_side"]]
	if shot < plan.size() and t >= float(plan[shot][0]):
		var sp: Vector2 = cam.unproject_position(wp)
		print("DIAG shot=%d t=%.1f dist=%.0f screen=(%.0f,%.0f) reveal=%.2f" % [shot, t, back, sp.x, sp.y, whale.get_reveal()])
		_shoot(String(plan[shot][1]))
		shot += 1
	if t > 22.0:
		print("WHALE-PROBE vram=%.0fMB fps=%d" % [Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Engine.get_frames_per_second()])
		get_tree().quit()

func _shoot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/%s.png" % nm)
	print("SHOT saved %s (t=%.1f)" % [nm, t])

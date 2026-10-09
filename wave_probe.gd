extends Node3D
## v1.3 波形验证探针: 跟踪机位锁定金鱼, reveal 完成后以半周期间隔连拍 3 帧
## 判定: 帧差 A-B、B-C 显著(形变在动), A-C 差 << A-B(周期回弹) => 波传导连续

var cam: Camera3D
var fish: StarWhale
var t := 0.0
var shot := 0

func _ready() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.8
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 15, 0)
	sun.light_energy = 1.3
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 8000.0
	add_child(cam)
	fish = StarWhale.create(Vector3(0, 0, 0))
	add_child(fish)
	fish.start_reveal()

func _process(dt: float) -> void:
	t += dt
	var wp: Vector3 = fish.current_pos()
	var hd: Vector3 = fish.heading()
	var side: Vector3 = hd.cross(Vector3.UP).normalized()
	cam.position = wp + side * 1450.0 + Vector3.UP * 120.0
	cam.look_at(wp, Vector3.UP)
	var plan := [[11.0, "wave_A"], [11.3, "wave_B"], [11.6, "wave_C"]]
	if shot < plan.size() and t >= float(plan[shot][0]):
		_shoot(String(plan[shot][1]))
		shot += 1
	if t > 12.5:
		print("WAVE-PROBE done shots=%d fps=%d" % [shot, Engine.get_frames_per_second()])
		get_tree().quit()

func _shoot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/%s.png" % nm)
	print("SHOT saved %s (t=%.2f)" % [nm, t])


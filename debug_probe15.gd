extends Node3D
## 探针 v15: 显存分解 — 逐资源测量 RENDERING_INFO_VIDEO_MEM_USED 增量
var t := 0.0
var step := 0
var base_mem := 0
var report: Array = []

func _vmem() -> int:
	return int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED))

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.02)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var cam := Camera3D.new()
	add_child(cam)

func _process(dt: float) -> void:
	t += dt
	match step:
		0:
			if t >= 1.0:
				step = 1
				base_mem = _vmem()
			print("VMEM baseline(空场景) = %d MB" % (base_mem / 1048576))
		1:
			if t >= 2.5:
				step = 2
				var m0 := _vmem()
				var res: GaussianResource = load("res://assets/hy_cell01_sym2.ply")
				var n := GaussianSplatNode.new()
				add_child(n)
				n.gaussian = res
				n.position = Vector3(0, 0, -500)
				await get_tree().process_frame
				await get_tree().process_frame
				print("VMEM +gate PLY(66.9万点) = %d MB" % ((_vmem() - m0) / 1048576))
		2:
			if t >= 4.0:
				step = 3
				var m1 := _vmem()
				var tex1: Texture2D = load("res://assets/textures/nasa_sky_panorama_8k.jpg")
				var mi := MeshInstance3D.new()
				var q := QuadMesh.new()
				q.size = Vector2(1, 1)
				mi.mesh = q
				mi.material_override = StandardMaterial3D.new()
				(mi.material_override as BaseMaterial3D).albedo_texture = tex1
				add_child(mi)
				mi.position = Vector3(0, 0, -50)
				await get_tree().process_frame
				await get_tree().process_frame
				print("VMEM +8k 天空全景 = %d MB  (%s)" % [((_vmem() - m1) / 1048576), tex1.get_class()])
		3:
			if t >= 5.5:
				step = 4
				var m2 := _vmem()
				var tex2: Texture2D = load("res://assets/textures/nasa_svs/starmap_2020_4k.exr")
				var mi2 := MeshInstance3D.new()
				var q2 := QuadMesh.new()
				q2.size = Vector2(1, 1)
				mi2.mesh = q2
				mi2.material_override = StandardMaterial3D.new()
				(mi2.material_override as BaseMaterial3D).albedo_texture = tex2
				add_child(mi2)
				mi2.position = Vector3(0, 5, -50)
				await get_tree().process_frame
				await get_tree().process_frame
				print("VMEM +EXR 星图 4k = %d MB" % ((_vmem() - m2) / 1048576))
		4:
			if t >= 7.0:
				step = 5
				var m3 := _vmem()
				var tex3: Texture2D = load("res://assets/textures/8k_jupiter.jpg")
				var mi3 := MeshInstance3D.new()
				var q3 := QuadMesh.new()
				q3.size = Vector2(1, 1)
				mi3.mesh = q3
				mi3.material_override = StandardMaterial3D.new()
				(mi3.material_override as BaseMaterial3D).albedo_texture = tex3
				add_child(mi3)
				mi3.position = Vector3(0, 10, -50)
				await get_tree().process_frame
				await get_tree().process_frame
				print("VMEM +8k 木星贴图 = %d MB" % ((_vmem() - m3) / 1048576))
		5:
			if t >= 8.5:
				step = 6
				var m4 := _vmem()
				var tex4: Texture2D = load("res://assets/textures/earth.jpg")
				var mi4 := MeshInstance3D.new()
				var q4 := QuadMesh.new()
				q4.size = Vector2(1, 1)
				mi4.mesh = q4
				mi4.material_override = StandardMaterial3D.new()
				(mi4.material_override as BaseMaterial3D).albedo_texture = tex4
				add_child(mi4)
				mi4.position = Vector3(0, 15, -50)
				await get_tree().process_frame
				await get_tree().process_frame
				print("VMEM +earth.jpg = %d MB  尺寸 %dx%d" % [((_vmem() - m4) / 1048576), tex4.get_width(), tex4.get_height()])
				print("VMEM 总计 = %d MB" % (_vmem() / 1048576))
				print("PROBE15-DONE")
				get_tree().quit()

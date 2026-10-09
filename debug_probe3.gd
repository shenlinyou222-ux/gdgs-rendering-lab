extends Node3D
## 探针 v3: A/B 验证 cam.near 对 create_frustum_points 报错的影响
var game: Node3D
var t := 0.0

func _ready() -> void:
	game = (load("res://solar_combat.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	var cam := _find_cam(self)
	var args := " ".join(OS.get_cmdline_user_args())
	if cam != null and args.contains("nearfix"):
		cam.near = 0.5
	if cam != null and args.contains("farfix"):
		cam.far = 2.5e7
		cam.near = 0.5
	print("PROBE3 near=%s far=%s mode=%s" % [str(cam.near if cam else -1), str(cam.far if cam else -1), args])

func _process(dt: float) -> void:
	t += dt
	if t >= 5.0:
		print("PROBE3-DONE")
		get_tree().quit()

func _find_cam(n: Node) -> Camera3D:
	if n is Camera3D:
		return n as Camera3D
	for c in n.get_children():
		var r := _find_cam(c)
		if r != null:
			return r
	return null

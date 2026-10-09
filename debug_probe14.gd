extends Node3D
## 探针 v14:三级 LOD 分档验证 — 网格(1.5°)/L1(5°)/L0(12°)/出生(16.6°)
var game: Node3D
var cam: Camera3D
var t := 0.0
var step := 0
var steps := [3820.0, 1147.0, 481.0, 350.0]
var names := ["mesh_1d5", "L1_5", "L0_12", "spawn_16d6"]
var spawn_dir := Vector3.ZERO

func _ready() -> void:
	process_priority = 100
	game = (load("res://solar_combat.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	cam = _find_cam(self)
	game.autopilot = false
	spawn_dir = (cam.global_position - game.earth_pos).normalized()

func _process(dt: float) -> void:
	t += dt
	if step < steps.size() and t >= 1.5 + float(step) * 1.6:
		var d: float = steps[step]
		cam.position = game.earth_pos + spawn_dir * d
		var aim := -spawn_dir
		game._pitch = asin(clampf(aim.y, -1.0, 1.0))
		game._yaw = atan2(-aim.x, -aim.z)
		_shot(names[step], d)
		step += 1
		if step >= steps.size():
			print("PROBE14-DONE")
			get_tree().quit()

func _shot(nm: String, d: float) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/v14_%s.png" % nm)
	var s := 0.0
	var cnt := 0
	var cy := int(img.get_height() * 0.5)
	var cx := int(img.get_width() * 0.5)
	for y in range(cy - 100, cy + 100, 2):
		for x in range(cx - 100, cx + 100, 2):
			var p: Color = img.get_pixel(x, y)
			s += p.r * 0.3 + p.g * 0.6 + p.b * 0.1
			cnt += 1
	var lvl := -1
	var vis := ""
	for sp in game.splat_planets:
		if float(sp["radius"]) < 200.0:
			lvl = int(sp["level"])
			vis = "near=%s far=%s mesh=%s" % [str((sp["near"] as Node3D).visible), str((sp["far"] as Node3D).visible), str((sp["mesh"] as Node3D).visible)]
	print("TIER %s d=%.0fm -> level=L%d [%s] center200=%.3f" % [nm, d, lvl, vis, s / float(cnt)])

func _find_cam(n: Node) -> Camera3D:
	if n is Camera3D: return n as Camera3D
	for c in n.get_children():
		var r := _find_cam(c)
		if r != null: return r
	return null

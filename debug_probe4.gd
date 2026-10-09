extends Node3D
## 探针 v4: 沿地球方向逐步逼近, 验证近距离 splat 渲染
var game: Node3D
var cam: Camera3D
var steps := [400.0, 250.0, 150.0, 100.0, 80.0, 64.0, 40.0]
var i := 0
var t := 0.0

func _ready() -> void:
	process_priority = 100
	game = (load("res://solar_combat.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	cam = _find_cam(self)

func _process(dt: float) -> void:
	t += dt
	if cam == null:
		return
	var ep: Vector3 = game.earth_pos
	var dir: Vector3 = (game.arena_anchor - ep).normalized()
	var want: float = steps[i]
	var target: Vector3 = ep + dir * want
	cam.position = target
	var d := ep.distance_to(target)
	game._pitch = asin(clampf(-dir.y, -1.0, 1.0))
	game._yaw = atan2(dir.x, dir.z)
	if t >= 1.2:
		t = 0.0
		_shot(want)
		var lv := 99
		for sp in game.splat_planets:
			lv = int(sp["level"])
		print("FLY d=%.0fm lod=L%s near_vis=%s far_vis=%s sun=%.2f" % [d, str(lv), str(_vis(true)), str(_vis(false)), float(game._sun_visibility(cam.global_position))])
		i += 1
		if i >= steps.size():
			print("PROBE4-DONE")
			get_tree().quit()

func _vis(near: bool) -> String:
	for sp in game.splat_planets:
		var n3: Node3D = sp["near" if near else "far"]
		return str(n3.visible)
	return "-"

func _shot(want: float) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/dbg4_d%03d.png" % int(want))
	var s := 0.0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var p: Color = img.get_pixel(x, y)
			s += p.r * 0.3 + p.g * 0.6 + p.b * 0.1
			n += 1
	print("  SHOT d=%d mean=%.4f" % [int(want), s / float(maxi(n, 1))])

func _find_cam(n: Node) -> Camera3D:
	if n is Camera3D:
		return n as Camera3D
	for c in n.get_children():
		var r := _find_cam(c)
		if r != null:
			return r
	return null

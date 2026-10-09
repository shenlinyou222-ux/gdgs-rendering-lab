extends Node3D
## 临时诊断探针(不改动 solar_combat 任何文件):
## 3s 后截玩家出生视角;随后环绕机位,6.5s 截全局俯瞰;输出几何/缩放审计

var game: Node3D
var cam: Camera3D
var phase := 0
var t := 0.0

func _ready() -> void:
	process_priority = 100
	game = (load("res://solar_combat.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	cam = _find_cam(self)
	if cam != null:
		print("PROBE cam near=%s far=%s fov=%s" % [str(cam.near), str(cam.far), str(cam.fov)])
	else:
		print("PROBE no camera found")
	_dump_diag("spawn")
	_audit()

func _process(dt: float) -> void:
	t += dt
	if phase == 0:
		if t >= 3.0:
			phase = 1
			_shot("res://shots/debug_player_view.png")
			_dump_diag("t3s")
	else:
		if cam != null:
			var ang := (t - 3.0) * 0.5
			var anchor: Vector3 = game.arena_anchor
			cam.position = anchor + Vector3(sin(ang) * 430.0, 190.0, cos(ang) * 430.0)
			cam.look_at(anchor, Vector3.UP)
		if t >= 6.5:
			_shot("res://shots/debug_overview.png")
			_dump_diag("t6s")
			print("PROBE-DONE")
			get_tree().quit()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	var s := 0.0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var p: Color = img.get_pixel(x, y)
			s += p.r * 0.3 + p.g * 0.6 + p.b * 0.1
			n += 1
	print("SHOT %s mean=%.4f size=%dx%d" % [path.get_file(), s / float(maxi(n, 1)), img.get_width(), img.get_height()])
	var w := 64
	var h := int(float(img.get_height()) * 64.0 / float(img.get_width()) * 0.5)
	for yy in range(h):
		var row := ""
		for xx in range(w):
			var p2: Color = img.get_pixel(int(float(xx) * float(img.get_width()) / float(w)), int(float(yy) * float(img.get_height()) / float(h)))
			var v2 := p2.r * 0.3 + p2.g * 0.6 + p2.b * 0.1
			row += " .:-=+*#%@"[clampi(int(v2 * 10.0), 0, 9)]
		print(row)

func _find_cam(n: Node) -> Camera3D:
	if n is Camera3D:
		return n as Camera3D
	for c in n.get_children():
		var r := _find_cam(c)
		if r != null:
			return r
	return null

func _dump_diag(tag: String) -> void:
	var ep: Vector3 = game.earth_pos
	var anchor: Vector3 = game.arena_anchor
	print("DIAG[%s] earth=%s anchor=%s d=%.1f" % [tag, str(ep), str(anchor), ep.distance_to(anchor)])
	var enemies: Array = game.enemies
	var pts: Array = []
	for e in enemies:
		if is_instance_valid(e) and e is Node3D:
			pts.append((e as Node3D).global_position)
	var min_pair := 1e9
	for i in range(pts.size()):
		for j in range(i + 1, pts.size()):
			min_pair = minf(min_pair, (pts[i] as Vector3).distance_to(pts[j] as Vector3))
	var min_e := 1e9
	var max_e := 0.0
	for p in pts:
		var d: float = (p as Vector3).distance_to(ep)
		min_e = minf(min_e, d)
		max_e = maxf(max_e, d)
	print("DIAG[%s] enemies=%d min_pair=%.1fm dist_to_earth_center=[%.1f, %.1f]m" % [tag, pts.size(), min_pair, min_e, max_e])

func _audit() -> void:
	var out: Array = []
	_audit_rec(game, out, 0)
	print("AUDIT nodes=%d findings=%d" % [_count_rec(game), out.size()])
	for line in out.slice(0, 60):
		print("  " + str(line))

func _audit_rec(n: Node, out: Array, depth: int) -> void:
	if n is Node3D:
		var n3 := n as Node3D
		var s := n3.scale
		var p := n3.global_position
		var sm := maxf(absf(s.x), maxf(absf(s.y), absf(s.z)))
		var pm := p.length()
		var finite := is_finite(s.x) and is_finite(s.y) and is_finite(s.z) and is_finite(p.x) and is_finite(p.y) and is_finite(p.z)
		var tag := ""
		if n is GaussianSplatNode:
			tag = " [SPLAT visible=%s node_scale=%.3g]" % [str(n3.visible), sm]
		if not finite:
			out.append("!!NaN/INF scale/pos: %s%s" % [n.name, tag])
		elif sm > 500.0:
			out.append("!!SCALE %.3g : %s%s" % [sm, n.name, tag])
		elif pm > 2.5e8:
			out.append("!!POS %.3g (>far 2.5e8) : %s%s" % [pm, n.name, tag])
		elif tag != "" and depth < 3:
			out.append("splat: %s%s" % [n.name, tag])
	for c in n.get_children():
		_audit_rec(c, out, depth + 1)

func _count_rec(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_rec(ch)
	return c

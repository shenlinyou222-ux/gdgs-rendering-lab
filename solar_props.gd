# solar_props.gd —— v3.1 场景道具(中转站/雷达相阵=传统mesh+PBR, 八棱柱BOSS=splat)
extends Node3D

static func mesh_inst(path: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var res: Resource = load(path)
	if res is Mesh:
		mi.mesh = res
	elif res is PackedScene:
		var sc: Node3D = (res as PackedScene).instantiate()
		if sc is MeshInstance3D:
			mi = sc
		else:
			mi.add_child(sc)
	mi.layers = 2   # 只被道具太阳光(light_cull_mask=2)照亮
	return mi

class Station:
	# 中转站: 传统 mesh(下载模型+PBR贴图), 近距离细节完好
	extends Node3D
	static func mesh_inst(path: String) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var res: Resource = load(path)
		if res is Mesh:
			mi.mesh = res
		elif res is PackedScene:
			var sc: Node3D = (res as PackedScene).instantiate()
			if sc is MeshInstance3D:
				mi = sc
			else:
				mi.add_child(sc)
		mi.layers = 2   # 只被道具太阳光(light_cull_mask=2)照亮
		return mi
	var body: MeshInstance3D
	static func _new_at(pos: Vector3) -> Station:
		var s := Station.new()
		s.position = pos
		return s
	var portal_ring: MeshInstance3D
	var portal_ring2: MeshInstance3D
	# v6.15.1 炮口截面: 环心(局部) + 环轴向, 巨型光束从这里贴截面射出
	var portal_center_local := Vector3(0.0, 58.0, 42.0)
	var portal_axis := Vector3(0.05, -0.19, 0.98).normalized()

	func muzzle_origin() -> Vector3:
		return global_position + global_transform.basis * portal_center_local

	func portal_axis_global() -> Vector3:
		return (global_transform.basis * portal_axis).normalized()
	var swirl: GaussianSplatNode

	func _ready() -> void:
		body = mesh_inst("res://assets/props_mesh/station/station.obj")
		var aabb: AABB = body.get_aabb()
		var sc: float = 340.0 / maxf(aabb.size.y, 0.01)   # 高约 170u, 立式
		body.scale = Vector3.ONE * sc
		body.position = -aabb.get_center() * sc   # 底部近似贴 0
		add_child(body)
		# v3.3 传送门(替代原中央飞机): 双反向旋转发光环 + 能量盘 + 光
		var pc := (Vector3(-0.0023, 0.1727, 0.1233) - aabb.get_center()) * sc
		# v3.8 环轴向实测(宽壳层 14-25万点): 洞口基本朝 +Z 水平, 带 11° 倾角
		var ax := Vector3(0.05, -0.19, 0.98).normalized()
		portal_center_local = pc
		portal_axis = ax
		var B := Basis()
		B.y = ax
		var ref := Vector3.FORWARD if absf(ax.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		B.x = ax.cross(ref).normalized()
		B.z = B.x.cross(ax).normalized()   # v3.6 原飞机所在的中央环位置(模型坐标换算) 4f20900195e857287ad94f536b634e2d5fc3
		portal_ring = MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 68.0
		tor.outer_radius = 84.0
		portal_ring.mesh = tor
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.emission_enabled = true
		pm.emission = Color(0.4, 0.9, 1.0)
		pm.emission_energy_multiplier = 4.0
		portal_ring.material_override = pm
		portal_ring.basis = B
		portal_ring.position = pc
		add_child(portal_ring)
		portal_ring2 = MeshInstance3D.new()
		var tor2 := TorusMesh.new()
		tor2.inner_radius = 48.0
		tor2.outer_radius = 54.0
		portal_ring2.mesh = tor2
		portal_ring2.material_override = pm
		portal_ring2.basis = B
		portal_ring2.position = pc
		add_child(portal_ring2)
		var disc := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(120.0, 120.0)
		disc.mesh = qm
		var dm := StandardMaterial3D.new()
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		dm.albedo_color = Color(0.35, 0.8, 1.0, 0.30)
		dm.emission_enabled = true
		dm.emission = Color(0.4, 0.9, 1.0)
		dm.emission_energy_multiplier = 2.0
		dm.cull_mode = BaseMaterial3D.CULL_DISABLED
		disc.material_override = dm
		var B2 := Basis()
		B2.z = ax
		B2.x = B.x
		B2.y = ax.cross(B.x)
		disc.basis = B2
		disc.position = pc
		add_child(disc)
		# v3.4 高斯漩涡传送门核心(裂隙高斯, 双轴旋转)
		swirl = GaussianSplatNode.new()
		var sres: GaussianResource = load("res://assets/props/portal_swirl.ply")   # v3.6 程序化螺旋涡(9k点)
		swirl.gaussian = sres
		swirl.scale = Vector3.ONE * (78.0 / maxf(maxf(sres.aabb.size.x, sres.aabb.size.z), 0.01))   # v3.7 按盘面直径缩放(78u < 洞径96u)
		swirl.basis = B
		swirl.position = pc
		add_child(swirl)
		var lt := OmniLight3D.new()
		lt.light_color = Color(0.5, 1.0, 0.9)
		lt.omni_range = 260.0
		lt.light_energy = 1.2
		lt.position = pc
		add_child(lt)

	func _process(dt: float) -> void:
		rotate_y(dt * 0.06)
		if portal_ring != null and is_instance_valid(portal_ring):
			portal_ring.rotate_object_local(Vector3.UP, dt * 0.8)
			portal_ring2.rotate_object_local(Vector3.UP, -dt * 1.4)
		if swirl != null and is_instance_valid(swirl):
			swirl.rotate_object_local(Vector3.UP, dt * 0.8)

class RadarRing:
	# 相阵: 16 面雷达(传统mesh) 环绕阵心(地球外独立轨道点); 巨型激光直径52u
	extends Node3D
	static func mesh_inst(path: String) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var res: Resource = load(path)
		if res is Mesh:
			mi.mesh = res
		elif res is PackedScene:
			var sc: Node3D = (res as PackedScene).instantiate()
			if sc is MeshInstance3D:
				mi = sc
			else:
				mi.add_child(sc)
		mi.layers = 2   # 只被道具太阳光(light_cull_mask=2)照亮
		return mi
	var dishes: Array = []
	var state := 0
	var t := 26.0
	var beam: MeshInstance3D
	var beam_light: OmniLight3D
	var beam_origin := Vector3.ZERO
	var beam_dir := Vector3.FORWARD
	const BEAM_R := 26.0
	const RANGE := 9000.0
	var target := Vector3.ZERO
	# v6.15 相阵改为可保护目标: 拆除巨型激光, 增加血量
	var hp := 6000.0
	var hp_max := 6000.0
	signal destroyed()

	func take_damage(d: float) -> void:
		hp = maxf(hp - d, 0.0)
		if hp <= 0.0 and not is_queued_for_deletion():
			emit_signal("destroyed")
			queue_free()

	func setup(center: Vector3, radius: float, count: int, aim: Vector3) -> void:
		position = center   # 阵心=地球外轨道点(由调用方给), 不再用地心!
		target = aim
		for i in count:
			# v4.1 底座静止 + 天线单独旋转(平台不动!)
			var d := Node3D.new()
			var base_m := mesh_inst("res://assets/props_mesh/radar_tower/radar_base.obj")
			d.add_child(base_m)
			var ant := mesh_inst("res://assets/props_mesh/radar_tower/radar_antenna.obj")
			d.add_child(ant)
			dishes.append(d)
			d.set_meta("ant", ant)
			var a := TAU * i / count
			var off := Vector3(cos(a) * radius, sin(a * 3.0) * 40.0, sin(a) * radius)
			d.position = off
			var aabb: AABB = base_m.get_aabb().merge(ant.get_aabb())   # 全塔高度
			d.scale = Vector3.ONE * (55.0 / maxf(aabb.size.y, 0.01))   # 雷达塔高约 55u
			d.look_at(center + off * 3.0, Vector3.UP)
			add_child(d)
			dishes.append(d)
		beam = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.0
		cyl.bottom_radius = 1.0
		cyl.height = 1.0
		beam.mesh = cyl
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.albedo_color = Color(0.6, 0.9, 1.0, 0.0)
		bm.emission_enabled = true
		bm.emission = Color(0.7, 0.95, 1.0)
		bm.emission_energy_multiplier = 4.0
		beam.material_override = bm
		beam.visible = false
		add_child(beam)
		beam_light = OmniLight3D.new()
		beam_light.light_color = Color(0.7, 0.95, 1.0)
		beam_light.omni_range = 900.0
		beam_light.visible = false
		add_child(beam_light)

	func _aim_seg() -> void:
		beam_origin = global_position
		var to_t := (target - global_position)
		to_t.y += sin(Time.get_ticks_msec() * 0.0006) * 300.0
		beam_dir = to_t.normalized()

	func _upd_beam(r: float, alpha: float) -> void:
		beam.visible = alpha > 0.01
		var cyl := beam.mesh as CylinderMesh
		cyl.top_radius = r
		cyl.bottom_radius = r
		cyl.height = RANGE
		beam.global_position = beam_origin + beam_dir * (RANGE * 0.5)
		beam.look_at(beam_origin + beam_dir * RANGE, Vector3.UP)
		beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		(beam.material_override as StandardMaterial3D).albedo_color.a = alpha
		beam_light.visible = beam.visible
		beam_light.global_position = beam_origin + beam_dir * 300.0
		beam_light.light_energy = 6.0 * alpha

	func beam_hit(p: Vector3, dt: float) -> float:
		if state != 2:
			return 0.0
		var rel := p - beam_origin
		var along := rel.dot(beam_dir)
		if along < 0.0 or along > RANGE:
			return 0.0
		var perp := rel - beam_dir * along
		if perp.length() < BEAM_R:
			return 55.0 * dt
		return 0.0

	func tick(dt: float, aim: Vector3) -> float:
		# v6.15: 只保留天线扫描旋转, 不再对玩家开火
		target = aim
		t -= dt
		# v7.7:相阵停止旋转 —— 天线保持固定朝向(轨道运行保留)
		if t <= 0.0:
			t = randf_range(6.0, 12.0)
		return 0.0

class OctaBoss:
	# 八棱柱集群 BOSS: splat 实例(23×百万面mesh过重), 三武器轮换, HP挂核心
	extends Node3D
	var parts: Array = []
	var bolts: Array = []
	var laser: MeshInstance3D
	var laser_t := 0.0
	var laser_dir := Vector3.FORWARD
	var w := 0
	var w_t := 3.0
	var reveal_t := 0.0
	var reveal_i := 0   # v7.8:渐次现身索引
	var hp_frac := 1.0
	const BOLT_SPEED := 150.0

	func setup() -> void:
		var res: GaussianResource = load("res://assets/props/octa.ply")
		var defs := [[1, 130.0, 0.0, 0], [8, 55.0, 105.0, 1], [14, 30.0, 190.0, 2]]
		for d in defs:
			var n: int = d[0]
			var sc: float = d[1]
			var rr: float = d[2]
			var tier: int = d[3]
			for i in n:
				var g := GaussianSplatNode.new()
				g.gaussian = res
				g.scale = Vector3.ONE * sc
				var ph := TAU * i / float(n)
				g.position = Vector3(cos(ph) * rr, sin(ph * 2.0 + tier) * 40.0 * float(tier > 0), sin(ph) * rr)
				add_child(g)
				g.visible = false   # v7.8:创建即隐藏, 由 tick 渐次点亮
				# v3.2 低模物理代理(战机式): Area3D + 圆柱碰撞体, 供射线武器判定, meta 路由到核心伤害
				var ar := Area3D.new()
				ar.collision_layer = 2
				ar.collision_mask = 0
				var csh := CollisionShape3D.new()
				var cyl := CylinderShape3D.new()
				cyl.radius = sc * 0.55
				cyl.height = sc
				csh.shape = cyl
				ar.add_child(csh)
				ar.position = g.position
				ar.set_meta("boss", true)
				add_child(ar)
				parts.append({"n": g, "ar": ar, "r": rr, "ph": ph, "tier": tier, "sc": sc, "on": false, "born": 0.0, "w": randf_range(0.6, 1.6) * (1.0 + 0.5 * tier)})
		laser = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.0
		cyl.bottom_radius = 1.0
		cyl.height = 1.0
		laser.mesh = cyl
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lm.albedo_color = Color(1.0, 0.3, 0.2, 0.0)
		lm.emission_enabled = true
		lm.emission = Color(1.0, 0.35, 0.2)
		lm.emission_energy_multiplier = 5.0
		laser.material_override = lm
		laser.visible = false
		add_child(laser)

	func _spawn_bolt(dir: Vector3, col: Color, spd: float = BOLT_SPEED, home := false) -> void:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 4.0
		sm.height = 8.0
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col * 3.0
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 3.0
		mi.material_override = m
		mi.position = global_position + dir * 160.0
		add_child(mi)
		bolts.append({"mi": mi, "vel": dir * spd, "life": 9.0, "home": home})

	func tick(dt: float, player: Vector3, frac: float) -> float:
		var dmg := 0.0
		hp_frac = frac
		var tt := Time.get_ticks_msec() * 0.001
		# v7.8 渐次现身:每 0.3s 点亮一个高斯部件(0.5s 弹入缩放) —— 分摊 GPU 上传, 出场不卡顿
		reveal_t -= dt
		if reveal_t <= 0.0 and reveal_i < parts.size():
			reveal_t = 0.3
			var pp: Dictionary = parts[reveal_i]
			pp["on"] = true
			pp["born"] = tt
			reveal_i += 1
		for p in parts:
			var n: Node3D = p["n"]
			var spd: float = p["w"] * (1.0 + (1.0 - hp_frac) * 2.0)
			var ph: float = p["ph"] + tt * spd * 0.25
			var rr: float = p["r"]
			n.position = Vector3(cos(ph) * rr, sin(ph * 2.0) * 40.0 * float(p["tier"] > 0), sin(ph) * rr)
			n.rotate_y(dt * spd)
			var on: bool = bool(p.get("on", true)) and hp_frac > float(p["tier"]) * 0.28
			var born: float = float(p.get("born", 0.0))
			var pop: float = clampf((tt - born) / 0.5, 0.0, 1.0) if born > 0.0 else 1.0
			pop = pop * pop * (3.0 - 2.0 * pop)   # smoothstep 弹入
			n.visible = on
			n.scale = Vector3.ONE * float(p["sc"]) * (0.3 + 0.7 * pop)
			var ar: Area3D = p["ar"]
			if is_instance_valid(ar):
				ar.position = n.position
				ar.monitoring = on and pop >= 1.0   # v7.8:弹入完成才有判定
		w_t -= dt
		var to_p := (player - global_position).normalized()
		if w_t <= 0.0:
			w = (w + 1) % 5
			match w:
				0:   # 环形弹幕(全方位扩散)
					for i in 14:
						var a0 := TAU * i / 14.0
						_spawn_bolt(Vector3(cos(a0), 0.0, sin(a0)), Color(1.0, 0.4, 0.2))
					w_t = 2.4
				1:   # 双臂螺旋弹幕
					for i in 24:
						var a1 := TAU * i / 24.0 + tt
						var arm := 0.0 if i % 2 == 0 else PI
						_spawn_bolt(Vector3(cos(a1 + arm), sin(a1 + arm) * 0.35, sin(a1 + arm)), Color(1.0, 0.7, 0.2))
					w_t = 3.0
				2:   # 主炮激光(持续照射)
					laser_t = 2.4
					w_t = 3.8
				3:   # 瞄准霰弹(直射玩家, 高速)
					var sp0 := (player - global_position).normalized()
					for i in 7:
						var sd := sp0.rotated(Vector3.UP, randf_range(-0.22, 0.22)).rotated(sp0.cross(Vector3.UP).normalized(), randf_range(-0.14, 0.14))
						_spawn_bolt(sd.normalized(), Color(0.6, 0.9, 1.0), 210.0)
					w_t = 2.0
				4:   # 追踪鱼雷(缓慢转向, 高伤)
					for i in 4:
						var a4 := TAU * i / 4.0
						var tp := (player - global_position).normalized().rotated(Vector3.UP, a4)
						_spawn_bolt(tp, Color(0.8, 0.5, 1.0), 55.0, true)
					w_t = 3.4
		w_t *= 1.0 - 0.35 * (1.0 - hp_frac)   # v7.1:血量越低攻击节奏越快
		if laser_t > 0.0:
			laser_t -= dt
			laser_dir = laser_dir.lerp(to_p, clampf(dt * 2.0, 0.0, 1.0))
			laser.visible = true
			var R := 7000.0
			laser.global_position = global_position + laser_dir * (R * 0.5)
			laser.look_at(global_position + laser_dir * R, Vector3.UP)
			laser.rotate_object_local(Vector3.RIGHT, PI * 0.5)
			var cyl := laser.mesh as CylinderMesh
			cyl.top_radius = 6.5
			cyl.bottom_radius = 6.5
			cyl.height = R
			var rel := player - global_position
			var along := rel.dot(laser_dir)
			if along > 0.0:
				var perp := rel - laser_dir * along
				if perp.length() < 11.0:
					dmg += 42.0 * dt
		else:
			laser.visible = false
		for i in range(bolts.size() - 1, -1, -1):
			var b: Dictionary = bolts[i]
			var mi: MeshInstance3D = b["mi"]
			if not is_instance_valid(mi):
				bolts.remove_at(i)
				continue
			mi.position += b["vel"] * dt
			if b.get("home", false):
				var hd := (player - mi.global_position).normalized()
				var vvec: Vector3 = b["vel"]
				b["vel"] = vvec.lerp(hd * vvec.length(), clampf(dt * 1.1, 0.0, 1.0))
			b["life"] -= dt
			if b["life"] <= 0.0:
				mi.queue_free()
				bolts.remove_at(i)
				continue
			if mi.global_position.distance_to(player) < 14.0:
				dmg += 22.0
				mi.queue_free()
				bolts.remove_at(i)
		return dmg

	func die() -> void:
		for b in bolts:
			if is_instance_valid(b["mi"]):
				(b["mi"] as MeshInstance3D).queue_free()
		queue_free()

	func hit_test(p: Vector3, extra: float) -> bool:
		# 实体弹(等离子/导弹)低模判定: 任一仍在场的棱柱圆柱体内
		for pr in parts:
			var ar: Area3D = pr["ar"]
			if is_instance_valid(ar) and ar.monitoring:
				var n: Node3D = pr["n"]
				var sc3: float = n.scale.x
				var d := p - n.global_position
				if absf(d.y) < sc3 * 0.5 + extra and Vector2(d.x, d.z).length() < sc3 * 0.55 + extra:
					return true
		return false

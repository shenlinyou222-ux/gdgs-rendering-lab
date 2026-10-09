class_name Crowd
extends RefCounted
# v0.7 敌机 crowd 系统:
#  - 机型(P1/P2/P3):低模 OBJ = 物理判定(trimesh) + 远景剪影;高斯 PLY = 渲染外观
#  - 流(Stream):一波 ≥20 架共用 同一机型高斯模板 + 统一轨迹与编队行为(VEE/SNAKE/RING/PINCER)
#  - 空间复用:同型所有个体引用同一 GaussianResource(内存/GPU 一份);超出 splat_range 的个体
#    从 splat 渲染中整体剔除(每流批量裁决),换低模剪影 —— 近景高斯/远景低模互斥 LOD

const TYPES := {
	"p1": {
		"name": "falcon", "mesh": "res://assets/jets/P1_lowpoly.obj", "splat": "res://assets/jets/P1_splats.ply",
		"hp_mul": 1.0, "speed_mul": 1.0, "dmg_mul": 1.0, "length": 10.0,
		"tint": Color(0.72, 0.34, 0.14),
	},
	"p2": {
		"name": "sabre", "mesh": "res://assets/jets/P2_lowpoly.obj", "splat": "res://assets/jets/P2_splats.ply",
		"hp_mul": 0.6, "speed_mul": 1.55, "dmg_mul": 0.75, "length": 12.0,
		"tint": Color(0.45, 0.08, 0.07),
	},
	"p3": {
		"name": "bulwark", "mesh": "res://assets/jets/P3_lowpoly.obj", "splat": "res://assets/jets/P3_splats.ply",
		"hp_mul": 2.6, "speed_mul": 0.7, "dmg_mul": 1.7, "length": 14.5,
		"tint": Color(0.16, 0.2, 0.15),
	},
}

# 模板缓存:每机型只 load 一次 —— 一"流"内全部个体共用同一高斯模板资源
static var _mesh_cache: Dictionary = {}
static var _gs_cache: Dictionary = {}

static func build_jet(area: Area3D, type_id: String, scale_mul: float = 1.0) -> Dictionary:
	var t: Dictionary = TYPES[type_id]
	var mesh: Mesh = _mesh_cache.get(type_id)
	if mesh == null:
		mesh = load(t["mesh"])
		_mesh_cache[type_id] = mesh
	var gs_res: GaussianResource = _gs_cache.get(type_id)
	if gs_res == null:
		gs_res = load(t["splat"])
		_gs_cache[type_id] = gs_res
	# v0.7.1:scale_mul 来自 balance [crowd].jet_scale(0.22 → 2m 级机体);低模网格/碰撞体/高斯三者同步缩放
	var s: float = float(t["length"]) / maxf(mesh.get_aabb().size.z, 0.01) * scale_mul
	# 低模:物理判定体 + 远景剪影(近景隐藏,由流统一裁决与高斯互斥切换)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = t["tint"]
	mat.metallic = 0.4
	mat.roughness = 0.6
	mi.material_override = mat
	mi.scale = Vector3.ONE * s
	mi.visible = false
	var vis := Node3D.new()
	vis.rotation.y = PI   # 导入网格机头在 +Z,转到 Godot 前向 -Z(与高斯同一包裹,保持对齐)
	vis.add_child(mi)
	# 高斯外观:basis 先置非单位阵 → 插件默认 RotZ 校正跳过;RotX(-90°) = Blender Z-up → Godot Y-up(与 OBJ 导入同轴)
	var gs := GaussianSplatNode.new()
	gs.gaussian = gs_res
	gs.basis = Basis(Vector3.RIGHT, -PI * 0.5)
	gs.scale = Vector3.ONE * s
	gs.visible = true
	vis.add_child(gs)
	area.add_child(vis)
	# 物理判定 = 低模三角网格(hitscan 射线/射线门控直接命中真实外形)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	cs.scale = Vector3.ONE * s
	area.add_child(cs)
	return { "vis": vis, "gs": gs, "mesh": mi, "scale": s }


class Stream extends RefCounted:
	const VEE := 0      # V 形箭头突击
	const SNAKE := 1    # 蛇形纵队迂回
	const RING := 2     # 环形包围轨道
	const PINCER := 3   # 双钳夹击(左右两臂)
	const BEHAVIOR_NAMES := ["VEE", "SNAKE", "RING", "PINCER"]
	const BEHAVIOR_N := 4

	var root: Node3D
	var behavior := VEE
	var path: Curve3D
	var members: Array = []     # Enemy(弱持有:死亡由 tick 惰性剪除)
	var members_n := 20
	var leader_t := 0.0
	var speed := 34.0
	var dir := 1.0
	var type_id := "p1"
	var time_s := 0.0
	var cull_cd := 0.0

	static func behavior_name(b: int) -> String:
		return BEHAVIOR_NAMES[clampi(b, 0, BEHAVIOR_NAMES.size() - 1)]

	func _sample(t01: float) -> Vector3:
		var L := maxf(path.get_baked_length(), 1.0)
		var d := fposmod(t01, 1.0) * L
		return path.sample_baked(d)

	func _tangent(t01: float) -> Vector3:
		var p0 := _sample(t01)
		var p1 := _sample(t01 + 0.004)
		var v := p1 - p0
		return v.normalized() if v.length() > 0.001 else Vector3.FORWARD

	# 成员 i 在流坐标系中的编队目标点(世界系)
	func slot_pos(i: int) -> Vector3:
		var n := maxi(members_n, 1)
		match behavior:
			VEE:
				var fwd := _tangent(leader_t)
				var side := fwd.cross(Vector3.UP).normalized()
				var rank := (i + 1) / 2
				var sgn := 1.0 if i % 2 == 0 else -1.0
				var jit := Vector3(fmod(i * 0.61, 1.0) - 0.5, fmod(i * 0.37, 1.0) - 0.5, fmod(i * 0.83, 1.0) - 0.5) * 2.2
				return _sample(leader_t) - fwd * (10.0 + rank * 11.0) + side * sgn * (4.0 + rank * 7.0) + Vector3.UP * (rank * 1.2) + jit
			SNAKE:
				var gap := 0.011
				var base := _sample(leader_t - i * gap)
				var fwd := _tangent(leader_t - i * gap)
				var side := fwd.cross(Vector3.UP).normalized()
				var sway := sin(time_s * 2.0 + i * 0.55) * 7.0
				var bob := sin(time_s * 1.4 + i * 0.8) * 2.5
				return base + side * sway + Vector3.UP * bob
			RING:
				var ang := TAU * float(i) / float(n) + time_s * 0.25
				var center := _sample(leader_t)
				var r := 46.0 + float(i % 3) * 7.0
				return center + Vector3(cos(ang) * r, sin(ang * 2.0) * 2.2, sin(ang) * r)   # v0.7.1:垂直起伏 5→2.2m(减少俯仰抖动)
			PINCER:
				var sgn2 := 1.0 if i % 2 == 0 else -1.0
				var rank2 := i / 2
				var t2 := leader_t - float(rank2) * 0.008
				var fwd2 := _tangent(t2)
				var side2 := fwd2.cross(Vector3.UP).normalized()
				return _sample(t2) + side2 * sgn2 * (9.0 + float(rank2) * 6.5) - fwd2 * (float(rank2) * 3.0) + Vector3.UP * (fmod(i * 0.53, 1.0) - 0.5) * 3.0
		return _sample(leader_t)

	func tick(dt: float) -> void:
		time_s += dt
		members = members.filter(func(m): return is_instance_valid(m) and m.hp > 0)
		var L := maxf(path.get_baked_length(), 1.0)
		leader_t = fposmod(leader_t + dt * speed * dir / L, 1.0)
		# 空间复用/LOD:每 0.3s 整流批量裁决一次 —— 范围内高斯,范围外低模剪影(互斥,零双重渲染)
		cull_cd -= dt
		# v7.5: 逐流 LOD 已上移到 root._crowd_lod() —— 全局高斯预算(最近 K 架), 避免 260 架全高斯绘制
		if cull_cd <= 0.0:
			cull_cd = 0.3
			pass

	# 交战令牌:限制每流同时开火的机数(其余保持编队) → crowd 也能压住总火力
	func request_attack(e) -> bool:
		# v0.8:交战令牌随关卡抬台阶 4 → L7:5 → L13:6(设计稿)
		var cap: int = root._bi("crowd", "attack_tokens") if root != null else 4
		if root != null and root.level >= 13:
			cap += 2
		elif root != null and root.level >= 7:
			cap += 1
		var used := 0
		for m in members:
			if is_instance_valid(m) and m.engaging:
				used += 1
		if used >= cap:
			return false
		e.engaging = true
		return true

	func release_attack(e) -> void:
		e.engaging = false

	func alive_count() -> int:
		return members.size()

extends Node
## v6.14 relight 法线资源生成器(headless): 球面行星 -> 法线=位置归一化, AO=1, 置信度=1
## 为 4 个行星 PLY 生成配对的 GaussianLightingResource(<名>_l<N>.lighting.res)
## 用法: Godot_console.exe --headless --path . res://lighting_gen.tscn

const TARGETS := [
	"res://assets/splat_planets/earth_l0.ply",
	"res://assets/splat_planets/earth_l1.ply",
	"res://assets/splat_planets/jupiter_l0.ply",
	"res://assets/splat_planets/jupiter_l1.ply",
]

func _ready() -> void:
	for ply_path in TARGETS:
		var g: GaussianResource = load(ply_path)
		if g == null or g.point_count <= 0 or g.xyz.size() != g.point_count:
			print("LIGHTING-GEN FAIL: %s (count=%s xyz=%s)" % [ply_path, str(g.point_count if g else -1), str(g.xyz.size() if g else -1)])
			continue
		var lr := GaussianLightingResource.new()
		lr.source_point_count = g.point_count
		lr.source_aabb = g.aabb
		lr.voxel_size = 1.0
		var data := PackedByteArray()
		data.resize(g.point_count * 4)
		for i in g.point_count:
			var n: Vector3 = g.xyz[i].normalized()
			var e: Vector2 = GaussianLightingResource.oct_encode(n)
			data[i * 4 + 0] = GaussianLightingResource.encode_signed_byte(e.x)
			data[i * 4 + 1] = GaussianLightingResource.encode_signed_byte(e.y)
			data[i * 4 + 2] = 255   # AO = 1(行星表面无自遮挡)
			data[i * 4 + 3] = 255   # confidence = 1(表面高斯, 非飘浮点)
		lr.splat_data = data
		var out: String = ply_path.get_basename() + ".lighting.res"
		var err := ResourceSaver.save(lr, out)
		print("LIGHTING-GEN %s: %d pts -> %s err=%d" % [ply_path.get_file(), g.point_count, out, err])
	get_tree().quit()

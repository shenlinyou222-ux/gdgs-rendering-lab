class_name StarWhale
extends Node3D
## v1.4 星金鱼: 4D 动态高斯 · 直线匀速巡航版
##  - 轨迹: 过场地上空的一条固定直线, 匀速直线运动, 越端回绕(远离视野处重入)
##  - 波形: gdgs 着色器逐球形变(连续, 无分段)
##      主体波 = 温和行波, 头→尾, 波峰已压低
##      第二协波 = 胸鳍上下轻摆(背腹轴, 幅度细微但可见), 集中在鳍带
##  - 模型: 左半镜像对称(右半 = 左半沿矢状面镜像)

const REVEAL_TIME := 10.0
const CIRCLE_H := 45000.0   # v2.2 86.4km 巨鱼, 航线再抬高

## v1.7: 下载的金鱼源模型(Downloads/156462bd 包, OBJ+PBR 25万顶点) → 面积采样 11 万高斯球
## 轴向 ASCII 轮廓实证: 头=+Z(椭圆头楔), 背=+Y(背鳍平直展宽), 纱尾=-Z, 胸鳍对展于左右
## 烘焙: tools/bake_goldfish_obj.py(贴图采样上色 + 自适应点径)
const GOLDFISH_PLY := "res://assets/goldfish/goldfish_obj_3dgs.ply"
const WHALE_LEN := 86400.0   # v2.2 再×3: 86.4km 天体级

# —— 直线匀速运动 ——
const MOVE_DIR := Vector3(1, 0, -0.2)   # 航线方向(世界系, 自动归一化)
const MOVE_SPEED := 42.0                # 匀速 (m/s)
const MOVE_SPAN := 5200.0               # 直线段全长(越端回绕)

# —— 波形参数(降波峰版) ——
const SWAY_FREQ := 0.95   # v1.8 速率减半(幅度不变)
const SWAY_AMP := 0.055

# —— 第二协波: 胸鳍上下摆 ——
const FIN_AMP := 0.02
const FIN_Z := 0.32
const FIN_SPAN := 0.15
const FIN_FREQ := 1.8   # v1.8 同步减半

var _center := Vector3.ZERO
var _t := 0.0
var _reveal := 0.0
var _revealing := false
var _last_pos := Vector3.ZERO
var _dist := 0.0
var _dir: Vector3
var _gs_node: GaussianSplatNode = null
var _cells_n := 0
var _model_ext := 1.072
var _last_dbg := -10.0

static func create(center: Vector3) -> StarWhale:
	var w := StarWhale.new()
	w._center = center
	return w

func _line_pos(d: float) -> Vector3:
	return _center + Vector3(0.0, CIRCLE_H, 0.0) - _dir * (MOVE_SPAN * 0.5) + _dir * d

func current_pos() -> Vector3:
	return _line_pos(_dist)

func heading() -> Vector3:
	return _dir

func get_reveal() -> float:
	return _reveal

func start_reveal() -> void:
	_revealing = true
	visible = true

func _ready() -> void:
	visible = false
	_dir = MOVE_DIR.normalized()
	# v2.3 whale_solar: 出生点挪到太阳上空(日心系原点, 太阳 r=10.92km) —— 与太阳同框比尺度
	if " ".join(OS.get_cmdline_user_args()).contains("whale_solar"):
		_center = Vector3(0.0, 55000.0 - CIRCLE_H, 0.0)   # 净高 55km(v2.4 再降5km): 鱼腹距日面~1.2km
		print("WHALE-SOLAR: center=", _center, " 太阳r=10920 鱼=", WHALE_LEN)
	_build_goldfish()

func _build_goldfish() -> void:
	var res: GaussianResource = load(GOLDFISH_PLY)
	if res == null:
		print("WHALE: PLY missing ", GOLDFISH_PLY)
		return
	_cells_n = res.point_count
	_model_ext = maxf(res.aabb.size.x, maxf(res.aabb.size.y, res.aabb.size.z))
	_gs_node = GaussianSplatNode.new()
	_gs_node.gaussian = res
	_gs_node.swim_amp = SWAY_AMP * _model_ext
	_gs_node.swim_z0 = res.aabb.position.z + res.aabb.size.z   # 头端(+Z)
	_gs_node.swim_z1 = res.aabb.position.z                     # 尾端
	_gs_node.swim_freq = SWAY_FREQ * TAU
	_gs_node.swim_axis = Vector3(1, 0, 0)
	_gs_node.fin_amp = FIN_AMP * _model_ext
	_gs_node.fin_z = FIN_Z
	_gs_node.fin_span = FIN_SPAN
	_gs_node.fin_freq = FIN_FREQ
	_gs_node.fin_lat = 0.5 * res.aabb.size.x
	_gs_node.visible = false
	add_child(_gs_node)
	print("WHALE: goldfish %d splats, model_ext=%.3f, swim_amp=%.3f, fin_amp=%.3f" % [_cells_n, _model_ext, _gs_node.swim_amp, _gs_node.fin_amp])

func _push_params() -> void:
	if _gs_node == null or not is_instance_valid(_gs_node):
		return
	var p := _line_pos(_dist)
	var sc := WHALE_LEN / maxf(_model_ext, 0.001)
	var b := Basis.looking_at(-_dir, Vector3.UP)
	_gs_node.transform = Transform3D(b * Basis.from_scale(Vector3.ONE * sc * (0.25 + 0.75 * _reveal)), Vector3.ZERO)
	_gs_node.visible = visible and _reveal > 0.01
	_last_pos = p
	position = _last_pos

func _process(dt: float) -> void:
	_t += dt
	if _t - _last_dbg > 5.0:
		_last_dbg = _t
		print("WHALE-DBG t=%.1f pos=%s reveal=%.2f visible=%s splats=%d" % [_t, str(current_pos()), _reveal, visible, _cells_n])
	if _revealing and _reveal < 1.0:
		_reveal = minf(_reveal + dt / REVEAL_TIME, 1.0)
	_dist = fposmod(_dist + dt * MOVE_SPEED, MOVE_SPAN)
	_push_params()
	position = _last_pos


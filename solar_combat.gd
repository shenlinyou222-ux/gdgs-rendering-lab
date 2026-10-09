extends Node3D
## 第三幕战斗 v0.3:太阳系战场 + 火控(锥+提前量)+ 双武器(机炮/等离子)+ 热量系统
## 数值全部由 data/balance.txt 驱动(改表即改手感);命令行 -- --autotest 可无人值守验收全流程
## 鼠标=视角 W/A/S/D=移动 Q/E=升降 Shift=加速 火控默认全自动(锥内自瞄自射,无需鼠标开火)F=切手动(LMB机炮/RMB等离子) R=重开 Esc=退出

var cam: Camera3D
var self_rot: Array = []
var moon_pivots: Array = []
var _yaw := 0.0
var _pitch := 0.0
var _mouse_free := false

var hp := 100
var score := 0
var dead := false
# --- 武器与热量(数值全部来自 data/balance.txt,见 _load_balance)---
var fire_cd := 0.0            # 机炮装填
var plasma_cd := 0.0          # 等离子装填
var spread_cd := 0.0          # v0.8:散弹炮装填
var bolt_cd := 0.0              # v7.3:弹体炮射击间隔
var mega_cd := 0.0                # v7.4 mega beam charge left (0=ready)
var mega_t := -1.0               # v7.4 beam active timer (-1=off)
var mega_p_t := 0.0              # v7.4 damage pulse timer
var mega_mi: MeshInstance3D = null   # v7.4 beam mesh
var _crowd_lod_cd := 0.0       # v7.5:全局高斯 LOD 裁决节流
var _crowd_lod_dbg := 0
var _perf_t := 0.0            # v7.8:帧率监控采样计时
var _perf_fps := 0.0          # v7.8:帧率平滑值
var _perf_feed_cd := 0.0      # v7.8:帧率警告节流
var _ack_lbl: Label              # v7.7:EVA 应答表情面板(右侧)
var _ack_ttl := 0.0
var laser_phase := 0          # v0.8:超级激光炮 0=充能 1=照射
var laser_t := 0.0            # v0.8:激光当前阶段计时
var laser_beam: MeshInstance3D = null   # v0.8:光束可视化节点
var _laser_fx: GaussianSplatNode = null # v0.8:光束命中点高斯火花
var laser_glow: MeshInstance3D = null       # v0.9:光束辉光层(宽管)
var laser_muzzle_fx: MeshInstance3D = null  # v0.9:炮口光晕(充能涨亮/出射闪光)
var laser_impact_fx: MeshInstance3D = null  # v0.9:弹着光斑(星芒+冲击环)
var laser_mlight: OmniLight3D = null        # v0.9:炮口点光(复用实例)
var laser_ilight: OmniLight3D = null        # v0.9:弹着点光(复用实例)
var _laser_swirl := false                   # v0.9:充能内旋粒子已投放
var _shader_cache := {}                     # v0.9:特效 shader 缓存
var fx_time := 0.0                          # v0.9:特效统一时钟(能量流/呼吸)
var laser_beam_len := 0.0                 # v0.9.1:光束伸出长度(生长动画,GDQuest 手法)
var laser_motes: GPUParticles3D = null     # v0.9.1:束内能量尘
var laser_ip: GPUParticles3D = null        # v0.9.1:弹着环状粒子(对齐法线)
var _impact_p_cd := 0.0                    # v0.9.1:弹着粒子重发计时
var missile_cd := 0.0            # v0.9.2:追踪导弹冷却
var missiles: Array = []         # v0.9.2:在飞导弹 {mi,vel,target,life}
var beam_hit := false           # v0.9.6:光束正在造成伤害(HUD 命中标记数据源)
var beam_hit_t := 0.0           # v0.9.6:连续命中时长(HUD 热度弧)
var heat := 0.0               # 共享热量 0..heat.max
var overheated := false       # 过热锁定
var bloom := 0.0              # 机炮连射扩散(度)
var auto_fire := true           # F 切换:全自动火控(锥内自瞄自射,无需鼠标开火)
var plasma_bolts: Array = []  # 实体等离子弹 {mi, vel, life}
var enemy_bolts: Array = []    # 敌方实体弹 {mi, vel, life, eta}(可闪避,预警用)
# --- 火控状态(_update_fire_control 每帧刷新)---
var lock_valid := false
var lock_ready := false
var lock_in_range := false
var lock_point := Vector3.ZERO
var lock_is_core := false
var lock_target: Object = null   # 当前锁定对象(Enemy 或核心 Area3D)
var lock_direct := Vector3.ZERO  # 目标当前位置(机炮 hitscan 直射用)
# --- 自动化验收(命令行 -- --autotest)---
var autotest := false
var shots_mode := false    # v0.7:--shots 时随 autotest 打点截图
var demo_weapons := false
var stress := false       # 压测模式: 敌机x5 + 120FPS + FPS 计数 HUD
var _fps_label: Label = null
var _fps_n := 0
var _fps_t := 0.0
var _fps_avg := 0.0
var _stress_log := 0
var _last_us := 0
var _worst_frame_us := 0  # v0.8:--demo 时散弹/激光 L1 解锁(仅演示/截图)
var autotest_t := 0.0
var autotest_last_print := -10.0
# --- 太阳眩光探针(命令行 -- --sunprobe mask=nonebulae|nostars|nosun|bare)---
var sunprobe := false
var sunprobe_started := false
var probe_mask := ""
var _last_ctr := 0.0
# --- 语音命令接口层(v6.12:移植自 godot_valley_demo 管线)---
# 链路: 按住 V 录音 -> user://voice/*.wav -> Python voice_intent.py --project gdgs_lab
#       (Qwen3-ASR 转写 -> 规则意图识别) -> user://commands/inbox.jsonl -> 本端轮询执行
const CMD_INBOX := "user://commands/inbox.jsonl"
const CMD_EXECLOG := "user://commands/executed.json"
var _cmd_interfaces := {}       # command_type -> Callable(params: Dictionary) -> String
var _cmd_executed := {}         # command_id -> true(幂等去重, 持久化)
var _cmd_timer := 0.0
var orbit_lines: Array = []     # 轨迹圈节点集合(接口操控对象)
var _voice_effect: AudioEffectCapture
var _voice_player: AudioStreamPlayer
var _voice_rec := false
var _voice_samples := PackedVector2Array()
# --- 音效层(v6.13:程序化合成 SFX,见 _gen_sfx.py)---
var _sfx_lib := {}                      # name -> AudioStream
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_rr := 0
# --- 特效状态 ---
var shake := 0.0                  # 相机震动强度
var _muzzle_mi: MeshInstance3D = null
var _muzzle_light: OmniLight3D = null
var _muzzle_ttl := 0.0
# --- 行星 3DGS 分级渲染 + 解析日食(v0.4) ---
# 结论: 太阳唯一阴影源; 行星光照整颗烤死(太阳烘进 SH band-0);
# 烘焙太阳轴=本地-Z, look_at(太阳) 对齐 —— 平移自由, 朝向锁定(自转只剩绕太阳轴 1 自由度)
const SPLAT_PLANETS := {
	"earth.jpg": { "l0": "res://assets/splat_planets/earth_l0.ply", "l1": "res://assets/splat_planets/earth_l1.ply" },
	"res://assets/textures/8k_jupiter.jpg": { "l0": "res://assets/splat_planets/jupiter_l0.ply", "l1": "res://assets/splat_planets/jupiter_l1.ply" },
}
const SPLAT_LOD_SWAP_DEG := 8.0    # v6.7 三级 LOD:≥8° → L0 精 splat,<6.5° 回 L1(迟滞)
const SPLAT_LOD_HYST_DEG := 1.5
const SPLAT_LOD_L1_DEG := 3.5      # ≥3.5° → L1 粗 splat,<2.5° → 网格(差异低于感知阈处切换)
const SPLAT_LOD_MESH_DEG := 10.0   # v6.12c:角径>=10度(地球 d<=576m) 网格贴图接管; 400k 高斯投影>1px 会糊
const PLANET_INVINCIBLE := true    # 星球不可被攻击:武器无星球伤害入口,血量视为∞自回血(观光约定,HUD 标记挂∞)
# ===== 尺度 v6.4:体积比全真实(RAD_P=1.0),轨道距离压缩(DIST_P=0.6)=====
# 半径 r = GAME_R·Re(真实比:木星/地球 11.21×,太阳/地球 109.2× —— 用户重点诉求);
# 距离 d = AU_GAME·AU^0.6(1AU=42km):水星 23.9km = 2.2×太阳半径(安全间隙),太阳在地球轨道 ~30° 金盘;
# 地球 100m/木星 1121m/土星 914m;月亮 27m@777m(~2°);带 66–87km、柯伊伯 336–428km;远平面 500km。
const SOLAR_SCALE := 1e-5
const AU_GAME := 42000.0            # 距离基数:1AU → 42000·AU^0.6 米(轨道压缩,观感优先)
const GAME_R := 100.0               # 半径基数:地球(Re=1)→ 100 米(绝对尺寸自由,比例真实)
const RAD_P := 1.0                  # v6.4:体积比=真实比(太阳 109.2×地球)
const DIST_P := 0.6                 # 距离幂:轨道压缩(1.0=真实距离)
const SUN_R := 10920.0              # 太阳半径 = 109.2×GAME_R(真实比)
const USE_SPLAT_PLANETS := true    # v6.12:行星全面转高斯渲染(贴图经 bake_planet_splat.py 转高斯)

func _pr(re: float) -> float:
	return GAME_R * pow(re, RAD_P)   # 行星半径(Re=地球倍数)

func _pd(au: float) -> float:
	return AU_GAME * pow(au, DIST_P) # 行星距离(AU)
const RE_M := 6.371e6              # 地球真实半径(m)
const AU_M := 1.496e11             # 1 真实天文单位(m)
var splat_planets: Array = []      # {near, far, radius, level}(splat 管线,当前关闭)
var planet_lods: Array = []        # v6.8 全网格三级 LOD {hi:192段, mid:96段, lo:48段, radius, level, name}
var grid_twins := {}	# v6.12f: mid节点 -> [hi,lo] 三级同步自转注册表(修切层经度跳变)
var occluders: Array = []          # 日食遮挡体 {c: Vector3, r: float}(行星即椭球 proxy)
var jupiter_pos := Vector3.ZERO
var earth_pos := Vector3.ZERO
var arena_anchor := Vector3.ZERO   # 战斗竞技场锚点(地球低轨旁,相对几何与战斗数值全部基于此)
# ===== v0.9 星历驱动太阳系(公转/自转/轨道 = 真实运转规律) =====
var solar_sim_ms := 0.0            # 星历模拟时刻(unix ms, 随 solar_time_scale 推进)
var solar_time_scale := 1.0        # 时标: 1=真实速率; 3600=1s≈1h(公转可见)
var ephem_planets: Array = []      # {name, node, tex, r, pos} —— 星历逐帧驱动
var earth_node: MeshInstance3D = null
var earth_gmst_cur := 0.0          # 地球 GMST 累计相位(rad, 相位连续无跳变)
var earth_extras: Array = []       # 大气壳/云层(跟随地球位置+光照)
var moon_node: MeshInstance3D = null
var earth_calib_rad := 0.0          # 贴图相位标定量(rad, _ephem_autocal 写入, 逐帧目标相位需含此项)
var _ephem_diag_t := 0.0           # 直下点对拍打印计时
# ===== v3.0 场景道具 =====
var station: Node3D = null         # 中转站(地球轨道, 休息/过关补给点)
var radar_ring: Node3D = null      # 雷达相阵(另一轨道, 巨型激光)
var boss: Node3D = null            # 八棱柱集群 BOSS(挂核心 HP)
var core_hp_max := 1.0
var _prop_sun: DirectionalLight3D = null   # v3.1 只照道具 mesh 的太阳光

func _prop_damage(dmg: float, src: Vector3) -> void:
	if dead:
		return
	hp -= int(round(dmg))
	_play_sfx("hit_player", -6.0)
	vignette.color = Color(1, 0.1, 0.05, 0.35)
	shake = maxf(shake, 0.65)
	_hit_sparks(src, Color(0.7, 0.95, 1.0))
	if hp <= 0:
		hp = 0
		dead = true
		phase = 3
		_feed("任务失败 — 按 R 重试本关(强化保留)")
var _ephem_dbg_last := -1
var ship_light_cd := 0.0

var enemies: Array = []
var streams: Array = []     # v0.7:机群流(每流 ≥20 架,共用高斯模板与编队轨迹)
var _spawn_q: Array = []          # v7.9:机群流出厂队列(渐次创建)
var tracers: Array = []
var hud: Control
var lbl_main: Label
var lbl_feed: Label
var vignette: ColorRect
var hover_enemy = null          # v0.8:准星压到的敌机(仅它显示锁定括号)
var supply_state := 0           # v0.8:补给点状态 0=无 1=接近结构体 2=舱内倒计时
var supply_t := 0.0
var supply_props: Array = []    # v0.8:舱内停靠机体等高斯道具
var lod_fades: Array = []       # v0.8:行星 LOD 交叉淡化任务 {node,is_mesh,from,to,t,dur}
var fx_active: Array = []       # v0.8:高斯特效播放中 {node,frames,fps,t}
# ===== v0.9.7 性能补丁: 预热 + 节点池 + hitch 归因 + 多线程目标扫描 =====
var _bolt_pool_e: Array = []        # 敌弹节点池(隐藏复用: 免每发 new/add/free)
var _bolt_pool_w: Array = []        # 僚机弹节点池
var _fx_node_pool: Array = []       # 高斯特效节点池
var _frame_ev: Dictionary = {}      # 当帧事件计数(hitch 归因用)
var _hitch_thr_us := 30000          # 单帧超过 30ms 输出 [HITCH]
var _warmup_nodes: Array = []       # 启动预热节点(渲染数帧后回收)
var _warmup_frames := 0
var _rt_busy := false               # 目标扫描 worker 进行中
var _rt_task_id := -1
var _rt_every := 0.2                # 多线程目标扫描周期(秒)
var _rt_cd := 0.0
var _rt_enemy_pos := PackedVector3Array()
var _rt_enemy_ok := PackedByteArray()
var _rt_wm_pos := PackedVector3Array()
var _rt_wm_bias := PackedFloat32Array()
var _rt_result := PackedInt32Array()
var fx_cache: Dictionary = {}   # v0.8:高斯特效帧缓存 {name: [GaussianResource,...]}
var fov_mul := 1.0              # v0.8:补给舱内"机体适配"视角系数(放大=相对变小)
var _whale: StarWhale = null    # v0.9:星鲸(主战场上空高位环游, 核心出现时渐显)
# ===== v6.15 三关demo重构: 炮台激光/护设施/援军/通关鲸歌 =====
var _st_beams: Array = []
var _st_cd := 0.0
var _raid_cd := 12.0
var _reinf_done := false
var _final_whale := false
var _whale_song_cd := 0.0
const ST_COLORS := [Color(1.0, 0.25, 0.35), Color(0.3, 1.0, 0.55), Color(1.0, 0.65, 0.15), Color(0.75, 0.45, 1.0)]

# ===== v7.0 三关剧情 Demo: 歼灭→保卫→BOSS→星鲸终局 =====
var mission_time := 0.0          # 本关用时(结算展示)
var total_kills := 0             # 全程累计击毁(通关画面)
var _support_online := false     # L3: 轨道炮台周期火力支援已上线
var _support_t := 0.0            # L3: 支援上线倒计时
var _song_foreshadow := true     # 鲸歌铺垫: 开局即混入 BGM 周期远歌
var _fac_warned := {}            # 设施血量警告去重 {0.6:true, 0.3:true}
var _worm_t := -1.0              # 虫洞过渡动画计时(-1=未激活)
var _cleared := false            # 本关已结算守卫(核心归零后残留命中不得重复触发)
var _demo_done := false          # 终局剧情播完 → 通关画面
var _eva_voice: AudioStreamPlayer
var _eva_manifest := {}          # 台词文本 -> res:// wav(EVA 机械女声缓存)
var _eva_voice_len := 0.0        # 当前播报音频时长(字幕停留用)
var _mus_a: AudioStreamPlayer
var _mus_b: AudioStreamPlayer
var _mus_cur := ""
var _mus_cur_p: AudioStreamPlayer   # 当前主音量播放器(交叉淡化另一只)
var _mus_fade := 1.0
var _mus_lib := {}               # key -> AudioStream(懒加载)
var _sub_lbl: Label              # 字幕条(剧情/EVA 播报共用显示层)
var _sub_sp: Label
var _sub_tx := ""                # 当前字幕全文(打字机用)
var _sub_shown := 0.0
var _story_q: Array = []         # 剧情队列: [{sp, tx, voice, choice}]
var _story_on := false
var _story_t := 0.0
var _story_wait := 0.0
var _story_choice := false
var _result_panel: PanelContainer
var _result_lbl: Label
var _complete_panel: PanelContainer
var _complete_lbl: Label
var _fac_bar_bg: ColorRect
var _fac_bar: ColorRect
var _fac_lbl: Label
# v7.1: BOSS 血条(L3 专用, 不再展示雷达相阵血条)
var _boss_lbl: Label
var _boss_bar_bg: Panel
var _boss_bar: ColorRect
var _boss_notches: Array = []
var _flash_rect: ColorRect       # 虫洞/跃迁全屏闪光
var _l2_wave_told := false       # L2 开场字幕只播一次
var hitmark_ttl := 0.0
var aim := Vector2.ZERO          # 准星偏移(浮动瞄准)
var mode_follow := true          # true=准星随鼠标+视角跟随; false=准星居中
const AIM_SENS := 0.85
var wave := 1
var wave_clear_ttl := 0.0
var wave_paths: Array = []      # v6.14:巡逻环线(连续刷新复用)
var spawn_cd := 0.0             # v6.14:核心涌出刷新计时
# 关卡循环: 0=生存战 1=突入3DGS 2=结算 3=失败
var phase := 0
var level := 1
var level_timer := 90.0
var quota := 8
var kills := 0
var parts := 0
var dmg_mult := 1.0
var hp_max := 100
var speed_mult := 1.0
# ===== v7.1 双轨成长:能力树(战斗领悟) + 改造升级(机库档位), 各3档 =====
var ab_fire := 0		# 能力树·火力控制 档位(0-3):每档全伤害+12%
var ab_armor := 0		# 能力树·装甲掌控 档位(0-3):每档HP上限+30
var ab_engine := 0		# 能力树·矢量机动 档位(0-3):每档速度/加速+10%
var rf_weapon := 0		# 改造·武器系统 档位(0-3):每档全伤害+15%
var rf_airframe := 0	# 改造·机体结构 档位(0-3):每档HP上限+60
var rf_engine := 0		# 改造·推进器   档位(0-3):每档速度/加速+15%
var vel := Vector3.ZERO          # 惯性速度:太空无阻力,恒推力线性加速,不推进时保持
var autopilot := false           # v6.5:默认关 —— 绝不强制抢视角/镜头;需要时按 T 手动开启(机头咬目标+自动飞)
var ap_hold := 4.0                 # v0.6.1:出生宽限(秒)—— 开局先朝地球看,倒计时结束才允许 autopilot 接管
var god_mode := false            # v7.1:默认关闭免伤 — 真实承伤(G 键仍可手动切换)             # 免伤(观光模式):敌弹接触即消,不扣血
var enemy_bolt_speed := 130.0   # v0.8:随关推进 130+4(L-1), 封顶190
var enemy_speed_mul := 1.0      # v0.8:敌机速度倍率 1+0.02(L-1), 封顶1.3
var enemy_hp_mul := 1.0
var enemy_dmg := 8
var gate: GaussianSplatNode = null
var core: Area3D = null
# --- v6.6:裂隙物件预建暂存(启动时创建,开门时采用 —— 消灭"任务达成瞬间跳帧")---
var gate_stash: GaussianSplatNode = null
var core_stash: Area3D = null
var core_mesh_stash: MeshInstance3D = null
var core_mat_stash: StandardMaterial3D = null
var core_shape_stash: CollisionShape3D = null
var core_hp := 0
var marker_valid := false
var marker_pos := Vector3.ZERO

func _ready() -> void:
	_load_balance()
	stress = " ".join(OS.get_cmdline_user_args()).contains("stress")
	if " ".join(OS.get_cmdline_user_args()).contains("ephem-fast"):
		solar_time_scale = 600.0   # 1s≈10min, 直下点漂移 2.5°/s —— 验证自转方向/速率用
	if stress:
		_apply_stress()
	_build_sky()
	_build_star_layers()
	_build_nebulae()
	solar_sim_ms = float(Time.get_unix_time_from_system()) * 1000.0   # v0.9: 星历从真实 UTC 起步
	_build_solar_system()
	# v3.0 道具: 中转站(地球轨道) + 雷达相阵(另一轨道)
	station = Props.Station._new_at(earth_pos + Vector3(640.0, 150.0, -420.0))
	add_child(station)
	# v3.1 相阵阵心=地球外独立轨道点(不再用地心!): 光束从地球外发出, 掠过地球边缘打向竞技场
	radar_ring = Props.RadarRing.new()
	radar_ring.setup(earth_pos + Vector3(-900.0, 500.0, -1000.0), 420.0, 16, arena_anchor)
	add_child(radar_ring)
	# v3.1 道具太阳光: 只照 layer 2(中转站/雷达 mesh), 不影响 splat/行星
	_prop_sun = DirectionalLight3D.new()
	_prop_sun.light_cull_mask = 2
	_prop_sun.light_energy = 1.4
	_prop_sun.shadow_enabled = false
	add_child(_prop_sun)
	_feed("轨道设施在线: 防御激光炮台·雷达阵(受保护目标)")
	_precreate_gate()   # v6.6:37MB/67万点 PLY 提前到启动加载,开门零IO零建节点
	load("res://assets/props/octa.ply")   # v7.8:BOSS 高斯资源提前解析(出场只剩 GPU 上传, 且已渐次分摊)
	_eclipse_selftest()
	cam = Camera3D.new()
	cam.fov = _fov(); cam.far = 500000.0; cam.near = 0.5   # v6.7:near 0.05→0.5(near 对深度精度影响远大于 far;最近可见物 1.5m)
	add_child(cam)
	cam.position = arena_anchor  # 竞技场锚点=地球低轨旁(_build_solar_system 内已设)
	# 出生朝向对准地球(抬头即见星球),否则真实比例下行星都是点状找不到
	var to_e := earth_pos - arena_anchor
	_pitch = asin(clampf(to_e.normalized().y, -1.0, 1.0))
	_yaw = atan2(-to_e.x, -to_e.z)
	_build_hud()
	_build_story_ui()   # v7.0:字幕/选项/结算/通关/设施血条/全屏闪光
	_build_muzzle()
	_apply_level()
	_balance_report()
	_spawn_wave()
	_setup_music()      # v7.0:BGM 双播放器交叉淡化 + 分关曲目
	_load_eva_manifest()
	_whale_song_cd = 8.0   # v7.0:鲸歌铺垫 —— 开局 8s 第一声远歌, 之后周期性混入
	_feed("第 1 关(歼灭战):击毁 %d 架来犯敌机 → 中转站核心现身, 返航进入即通关" % quota)
	_eva_announce_key("l1_start", true)
	get_tree().create_timer(6.0).timeout.connect(_l1_intro)   # v7.7:开场 6s 后背景介绍+教学
	DisplayServer.window_set_title("第三幕战斗 v0.3.1 — 火控全自动开火(无需鼠标)| F 切手动 | WASD 飞行")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("combat ready")
	_spawn_wingmen()
	_setup_sfx()
	_warmup_v097()   # v0.9.7:fx/材质/弹池/GPU 上传预热
	_setup_voice()
	_register_cmd_interfaces()
	_load_cmd_executed()
	print("CMDSRV ready: %d interfaces %s" % [_cmd_interfaces.size(), str(_cmd_interfaces.keys())])
	var uargs := " ".join(OS.get_cmdline_user_args())
	autotest = uargs.contains("autotest")
	shots_mode = uargs.contains("shots")   # v0.7:autotest 过程截图(敌机高斯外观/编队实拍)
	demo_weapons = uargs.contains("demo")  # v0.8:截图巡演用 —— L1 即解锁散弹/激光
	if autotest and (phase == 1 or (lock_valid and cam.global_position.distance_to(lock_direct) > 150.0)):
		auto_fire = true
		print("AUTOTEST MODE")
	if uargs.contains("whale_early"):   # v0.9.1:开局即召唤星鲸(可视化调试/实拍)
		var wf := -cam.basis.z
		wf.y = 0.0
		wf = wf.normalized() if wf.length() > 0.1 else Vector3.FORWARD
		_whale = StarWhale.create(arena_anchor + Vector3(0.0, 500.0, 0.0) + wf * 900.0)
		add_child(_whale)
		_whale.start_reveal()
		_play_sfx("whale_roar", -3.0)
		print("WHALE-EARLY spawned at arena+950m")
	sunprobe = uargs.contains("sunprobe")
	if sunprobe and uargs.contains("mask="):
		probe_mask = uargs.split("mask=")[1].split(" ")[0].strip_edges()
	if sunprobe:
		print("SUNPROBE MODE mask=%s" % (probe_mask if probe_mask != "" else "(all)"))

func _apply_level() -> void:
	# v7.0:三关剧情 Demo —— L1 歼灭 / L2 保卫 / L3 BOSS; 敌方数值沿用 v0.8 指数漂移
	mission_time = 0.0
	match level:
		1: quota = _bi("demo", "l1_quota")
		2:
			quota = _bi("demo", "l2_quota")
			_fac_warned = {}            # 设施警告每关重置
		3:
			quota = _bi("demo", "l3_quota")
			_support_online = false
			_support_t = _b("demo", "l3_support_t") * (0.15 if autotest else 1.0)   # autotest ~7s 即上线: 保证周期激光路径被实测
		_: quota = _bi("economy", "quota_base")   # 兜底(demo 外不推荐)
	level_timer = _b("economy", "survival_time") + (15.0 if level >= 3 else 0.0)
	enemy_hp_mul = (1.0 + _b("enemy", "hp_level_scale") * (level - 1)) * pow(1.04, float(level - 1))
	if level > 15:
		enemy_hp_mul *= pow(1.09, float(level - 15))   # 无尽段
	if level <= 8:
		enemy_dmg = _bi("enemy", "damage_base") + _bi("enemy", "damage_per_level") * (level - 1)
	else:
		enemy_dmg = 11 + int(round(1.4 * float(level - 8)))
	enemy_bolt_speed = minf(_b("enemy", "bolt_speed") + 4.0 * float(level - 1), 190.0)
	enemy_speed_mul = minf(1.0 + 0.02 * float(level - 1), 1.3)

func _spawn_wave() -> void:
	if phase != 0:
		return
	var total := _bi("enemy", "wave_base") + (level - 1) * _bi("enemy", "wave_per_level")
	# 战斗竞技场:相对几何与 v2 完全一致(锚定地球轨道旁,只平移不缩放 —— 保住飞行节奏与 autotest)
	var path_a := _make_loop_path(arena_anchor + Vector3(60, 4, -160), 150.0, 20.0)
	var path_b := _make_loop_path(arena_anchor + Vector3(-80, -16, 390), 120.0, -15.0)
	var path_c := _make_loop_path(arena_anchor + Vector3(-30, 24, 140), 100.0, 25.0)
	wave_paths = [path_a, path_b, path_c]
	# v0.7 crowd:初始波改为机群流铺设(每流 ≥20 架,共用高斯模板 + 统一编队轨迹)
	# v0.8:流数台阶 L1-2:1 / L3-6:2 / L7-8:3 / L9-12:4 / L13+:5(数据稿 levels_design.md)
	var streams_n := 1 + (1 if level >= 3 else 0) + (1 if level >= 7 else 0) + (1 if level >= 9 else 0) + (1 if level >= 13 else 0)
	for i in streams_n:
		_spawn_stream()

func _open_gate() -> void:
	_play_sfx("gate", -6.0)
	phase = 1
	wave_clear_ttl = 0.0
	# v6.14:敌机不再溃逃 —— 核心现身后续从核心涌出,直至被摧毁
	# v6.6:采用预建物件(启动时已加载上传),此处零加载零建节点 —— 不再跳帧
	if gate_stash == null or not is_instance_valid(gate_stash):
		_precreate_gate()
	gate = gate_stash
	core = core_stash
	gate.visible = true
	core.visible = true
	core_shape_stash.set_disabled(false)
	# v0.8:核心 HP 二次曲线 400+160(L-1)+22(L-1)^2, 无尽段 ×1.10^N(设计稿)
	var ln := float(level - 1)
	core_hp = float(_bi("core", "hp_base") + _bi("core", "hp_per_level") * (level - 1)) + 22.0 * ln * ln
	if level > 15:
		core_hp *= pow(1.10, float(level - 15))
	core_hp_max = core_hp
	# v3.0 BOSS: 第 2 关起, 八棱柱集群包裹核心现身(HP 挂核心, 打核心=打BOSS)
	if level >= 3 and boss == null:
		boss = Props.OctaBoss.new()
		boss.position = gate_stash.position + Vector3(0.0, 240.0, 0.0)
		boss.setup()
		add_child(boss)
		_feed("⚠ BOSS:八棱柱集群护卫核心!")
	marker_valid = true
	marker_pos = core.position
	if level <= 2:
		# v7.0:L1/L2 免打核心 — 中转站核心=虫洞入口, 返航进入即跃迁结算
		phase = 4
		if level == 1:
			_feed("敌机群已歼灭 — 中转站核心已投放,返航进入即可通关!(击毁 %d/%d)" % [kills, quota])
			get_tree().create_timer(1.5).timeout.connect(func(): _eva_announce_key("l1_clear", true))   # v7.10:核心暴露→爆炸余音后语音+字幕播报
		else:
			_feed("防御战达成 — 中转站核心已投放,返航跃迁!(击毁 %d/%d)" % [kills, quota])
			get_tree().create_timer(1.5).timeout.connect(func(): _eva_announce_key("l2_clear", true))   # v7.10:同上
	else:
		phase = 1
		_feed("⚠ BOSS:八棱柱集群护卫核心!轨道炮台支援蓄能中(%ds)" % int(maxf(_support_t, 0.0)))
		_eva_announce_key("boss_warn", true)
	# v7.0:星鲸改为终局现身(BOSS 陨落后) —— 战斗中仅鲸歌音频铺垫, 不再提前剧透
	# v6.6:裂隙渐入 —— gate 从 0 绽放(自转见 self_rot),核心延迟淡入,替代瞬间蹦出
	# v0.8:结构体放大到太阳级(展开范围约 900m,可容纳舱内战斗/补给) —— 按资源 AABB 归一算缩放
	var gs_ext: float = 1.0
	if gate.gaussian != null:
		var ab: AABB = gate.gaussian.aabb
		gs_ext = maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
	var gs_target: float = clampf(430.0 / maxf(gs_ext, 0.001), 0.25, 200.0)   # v7.1:虫洞尺寸收敛(展开约430m)
	core_mat_stash.albedo_color = Color(0.45, 1.0, 0.9, 0.0)
	gate.scale = Vector3(0.02, 0.02, 0.02)
	core_mesh_stash.scale = Vector3(0.05, 0.05, 0.05)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(gate, "scale", Vector3(gs_target, gs_target, gs_target), 2.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(core_mesh_stash, "scale", Vector3.ONE, 1.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.4)
	tw.tween_property(core_mat_stash, "albedo_color:a", 1.0, 1.4).set_delay(0.4)

func _add_planet_extras(pos: Vector3, r: float) -> void:
	# v6.7:比例感三件套 —— ①大气边缘光(fresnel 壳) ②程序化云层(独立慢旋转);③夜面城市灯待夜灯贴图素材
	# 关键设计:两个壳独立于 LOD 层级常驻 → 与网格/splat 切换零耦合,天然零跳变
	var atmo := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = r * 1.035
	sph.height = r * 2.07
	sph.radial_segments = 64
	sph.rings = 32
	atmo.mesh = sph
	var am := ShaderMaterial.new()
	am.shader = load("res://shaders/atmo_rim.gdshader")
	am.set_shader_parameter("rim_color", Color(0.35, 0.55, 1.0))
	am.set_shader_parameter("rim_power", 3.2)
	am.set_shader_parameter("rim_strength", 1.1)
	am.set_shader_parameter("planet_pos_v612", pos)
	am.set_shader_parameter("surface_r", r)
	am.set_shader_parameter("sun_dir", (-pos).normalized())   # v6.12d
	atmo.material_override = am
	atmo.position = pos
	add_child(atmo)
	var clouds := MeshInstance3D.new()
	var cs := SphereMesh.new()
	cs.radius = r * 1.012
	cs.height = r * 2.024
	cs.radial_segments = 64
	cs.rings = 32
	clouds.mesh = cs
	var cm := ShaderMaterial.new()
	cm.shader = load("res://shaders/planet_clouds.gdshader")
	cm.set_shader_parameter("coverage", 0.55)
	cm.set_shader_parameter("drift", 0.6)
	cm.set_shader_parameter("cloud_tint", Color(1.0, 1.0, 1.0, 0.60))
	cm.set_shader_parameter("sun_dir", (-pos).normalized())   # v6.9:夜面云随行星变暗
	cm.set_shader_parameter("planet_pos_v612", pos)
	cm.set_shader_parameter("surface_r", r)
	clouds.material_override = cm
	clouds.position = pos
	add_child(clouds)
	self_rot.append([clouds, 0.012])
	earth_extras.append(atmo)   # v0.9: 登记跟随地球(位置+太阳方向逐帧同步)
	earth_extras.append(clouds)

func _precreate_gate() -> void:
	# v6.6:启动时预建裂隙物件(隐藏/微缩/碰撞禁用)—— 供 _open_gate 即取即用
	var res: GaussianResource = load("res://assets/hy_cell01_lod.ply")   # v6.9:抽稀版 16.7万点(显存 162→~40MB,3.5km 外观感无差)
	gate_stash = GaussianSplatNode.new()
	add_child(gate_stash)
	gate_stash.gaussian = res
	gate_stash.scale = Vector3(0.02, 0.02, 0.02)
	gate_stash.position = earth_pos + Vector3(-980.0, 300.0, 640.0)   # v7.1:虫洞核心移至近地轨道(约1.1km高度,与中转站同层)
	gate_stash.visible = false
	self_rot.append([gate_stash, 0.35])
	core_stash = Area3D.new()
	add_child(core_stash)
	core_stash.collision_layer = 2
	core_stash.collision_mask = 0
	core_stash.visible = false
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 140.0   # v7.1:虫洞入口判定球=高斯球体内部   # v0.8:结构体放大到太阳级 → 核心命中球同步放大
	cs.shape = sh
	cs.disabled = true
	core_stash.add_child(cs)
	core_shape_stash = cs
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 7.0
	sm.height = 14.0
	mi.mesh = sm
	var m2 := StandardMaterial3D.new()
	m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m2.albedo_color = Color(0.45, 1.0, 0.9, 0.0)
	mi.material_override = m2
	mi.scale = Vector3(0.05, 0.05, 0.05)
	core_stash.add_child(mi)
	core_mesh_stash = mi
	core_mat_stash = m2
	core_stash.position = gate_stash.position

func _level_clear() -> void:
	# v7.0:核心瘫痪 —— L3 = BOSS 陨落 → 星鲸终局; 旧补给舱流程由虫洞跃迁取代
	if _cleared:
		return   # v7.0.1:核心归零后残留命中不得重复结算(曾把终局剧情队列无限重灌)
	_cleared = true
	_explode(core.global_position if core != null else cam.global_position)
	if boss != null and is_instance_valid(boss):
		_explode(boss.global_position)
		(boss as Object).call("die")
		boss = null
	for e in enemies:
		if is_instance_valid(e):
			e.fleeing = true   # 敌机溃退
	var gain := _bi("economy", "clear_parts_base") + level * _bi("economy", "clear_parts_per_level")
	parts += gain
	if level < 3:
		pass   # v7.1:打爆核心不再视为通关(进入虫洞内部才结算)
		return
	_finale_whale()

func _finale_whale() -> void:
	# v7.0 终局演出: BOSS 陨落 → 星鲸现身 + 鲸歌 + 剧情对话 → 通关画面
	phase = 6
	_final_whale = true
	_whale_song_cd = 42.0
	_hide_gate_core()   # 核心已陨落: 隐藏裂隙/核心, 停止残留命中与锁定
	_music_play("finale", 4.0)
	if _whale == null or not is_instance_valid(_whale):
		var wfv := -cam.basis.z
		wfv.y = 0.0
		wfv = wfv.normalized() if wfv.length() > 0.1 else Vector3.FORWARD
		_whale = StarWhale.create(cam.global_position + wfv * 1400.0 + Vector3(0.0, 320.0, 0.0))
		add_child(_whale)
	_whale.start_reveal()
	_play_sfx("whale_song", 2.0)     # v7.0:28s 合成鲸歌(混响尾)
	_play_sfx("whale_roar", -6.0, 0.8)
	_feed("🐋 星鲸现身 — 深空传来跨越千里的鲸歌…")
	get_tree().create_timer(12.0).timeout.connect(_finale_voice)   # v7.7:先听 12s 鲸歌 → 再 EVA 播报 → 剧情语音

func _hide_gate_core() -> void:
	# v7.0:核心/裂隙退场(结算与终局共用) —— 碰撞停用防残留命中, 标记清除
	marker_valid = false
	if core_shape_stash != null and is_instance_valid(core_shape_stash):
		core_shape_stash.set_disabled(true)
	if core != null and is_instance_valid(core):
		core.visible = false
		core = null
	if gate != null and is_instance_valid(gate):
		gate.visible = false
		gate = null

func _next_level() -> void:
	level += 1
	kills = 0
	_reinf_done = false
	_support_online = false
	_cleared = false   # v7.0.1:新关重新允许结算
	if _result_panel != null:
		_result_panel.visible = false
	_apply_level()
	phase = 0
	_spawn_wave()
	match level:
		2:
			_feed("第 2 关(保卫战):保卫雷达相阵!击毁 %d 架后核心现身返航" % quota)
			_eva_announce_key("l2_start", true)
			_story_play([
				{"sp": "EVA", "tx": _eva_key_text("l2_story1"), "voice": "l2_story1"},
				{"sp": "EVA", "tx": _eva_key_text("l2_story2"), "voice": "l2_story2"},
			])
		3:
			_feed("第 3 关(BOSS战):歼灭 %d 架先遣机 → BOSS 现身;轨道炮台支援蓄能中" % quota)
			_eva_announce_key("l3_start", true)
		_:
			_feed("第 %d 关:击毁 %d 架 → 核心现身" % [level, quota])

func _retry_level() -> void:
	hp = hp_max
	dead = false
	phase = 0
	kills = 0
	# v7.0:重试复位 —— 剧情/终局/虫洞/设施/支援全部回卷
	_story_clear()
	_reinf_done = false
	_fac_warned = {}
	_support_online = false
	_demo_done = false
	_final_whale = false
	_cleared = false
	_worm_t = -1.0
	_flash_rect.color.a = 0.0
	if _whale != null and is_instance_valid(_whale):
		_whale.queue_free()
		_whale = null
	if radar_ring != null and is_instance_valid(radar_ring):
		(radar_ring as Object).set("hp", 6000.0)   # 设施血量重置(与 solar_props 默认一致)
	for e in enemies:
		e.queue_free()
	enemies.clear()
	for b in enemy_bolts:
		_bolt_release(b["mi"] as MeshInstance3D, _bolt_pool_e)   # v0.9.7:回池
	enemy_bolts.clear()
	for b in friendly_bolts:
		_bolt_release(b["mi"] as MeshInstance3D, _bolt_pool_w)   # v0.9.7:回池
	friendly_bolts.clear()
	marker_valid = false
	if core != null:
		core.visible = false          # v6.6:重试同样隐藏复用(原实现 gate 不回收,顺手修掉)
		core = null
	if gate != null:
		gate.visible = false
		gate.scale = Vector3(0.02, 0.02, 0.02)
		gate = null
	if gate != null: gate.queue_free(); gate = null
	_apply_level()
	_spawn_wave()
	_feed("重试第 %d 关(强化保留)" % level)

func _make_loop_path(center: Vector3, radius: float, tilt: float) -> Curve3D:
	var c := Curve3D.new()
	for i in 8:
		var a := TAU * i / 8.0
		var p := center + Vector3(cos(a) * radius, sin(a * 2.0) * tilt, sin(a) * radius)
		c.add_point(p)
	c.add_point(c.get_point_position(0))
	return c

func _spawn_enemy_from_core() -> void:
	# v6.14:敌机一律从核心(裂隙)位置涌出,再自行飞向巡逻环线 —— 物理转向,天然成群涌出
	if wave_paths.is_empty():
		return
	var path: Curve3D = wave_paths[randi() % wave_paths.size()]
	var e := Enemy.new()
	add_child(e)
	e.setup(self, path, randf())
	e.hp = int(round(float(e.hp) * enemy_hp_mul))
	e.hp_max = e.hp
	var origin := _core_spawn_pos()
	e.global_position = origin + Vector3(randf_range(-40, 40), randf_range(-16, 16), randf_range(-40, 40))
	enemies.append(e)

func _spawn_stream() -> void:
	# v0.7:一波 = 一条机群流(≥20 架):随机机型 × 随机编队行为(VEE/SNAKE/RING/PINCER)
	# 同流全部个体共用同一机型高斯模板(Crowd 缓存一份 GaussianResource)与统一轨迹
	if wave_paths.is_empty():
		return
	var type_keys: Array = Crowd.TYPES.keys()
	type_keys.erase(WING_TYPE)   # p1 已分给僚机, 敌机只用 p2/p3
	var type_id: String = type_keys[randi() % type_keys.size()]
	var s := Crowd.Stream.new()
	s.root = self
	s.behavior = randi() % Crowd.Stream.BEHAVIOR_N
	s.type_id = type_id
	s.members_n = _bi("crowd", "members")
	s.path = wave_paths[randi() % wave_paths.size()]
	s.leader_t = randf()
	s.dir = 1.0 if randf() > 0.5 else -1.0
	s.speed = 42.0 * float(Crowd.TYPES[type_id]["speed_mul"]) * 0.8 * enemy_speed_mul
	streams.append(s)
	var origin := _core_spawn_pos() + Vector3(randf_range(-80, 80), randf_range(-30, 30), randf_range(-80, 80))
	# v7.9:整流成员不再一次性创建 —— 入队渐次出厂(0.12s/架), 分摊节点+trimesh+高斯上传的创建尖峰
	_spawn_q.append({"s": s, "i": 0, "cd": randf_range(0.0, 0.12), "origin": origin})

func _tick_streams(dt: float) -> void:
	_crowd_lod_cd -= dt   # v7.5:全局高斯 LOD(0.3s 节流)
	if _crowd_lod_cd <= 0.0:
		_crowd_lod_cd = 0.3
		_crowd_lod()
	# v0.7:流轨迹推进 + 编队目标点 + 高斯/低模 LOD 批量裁决;死流惰性回收
	for s in streams:
		if is_instance_valid(s):
			s.tick(dt)
	streams = streams.filter(func(x) -> bool: return is_instance_valid(x) and (x.alive_count() > 0 or _pending_members(x) > 0))   # v7.9b:出厂中的流不过滤

func _core_spawn_pos() -> Vector3:
	if gate_stash != null and is_instance_valid(gate_stash):
		return gate_stash.position
	return arena_anchor

func _tick_enemy(e: Enemy, dt: float) -> void:
	if e.hp <= 0:
		return
	e.bt_tick(dt)

func _act_patrol(e: Enemy, dt: float) -> int:
	if e.stream != null:
		e.steer_soft(e.stream.slot_pos(e.slot_i), dt)   # v0.7.1:编队软伺服(宽弧线转弯)
		return 2
	e.path_t = fmod(e.path_t + dt * e.speed / maxf(e.path.get_baked_length(), 1.0), 1.0)
	var target: Vector3 = e.path.sample_baked(e.path_t * e.path.get_baked_length())
	e.steer_to(target, dt)
	return 2

func _act_engage(e: Enemy, dt: float) -> int:
	if phase >= 2:   # v6.14:核心战阶段敌机继续作战(原来只 phase0 交战)
		return 2
	var to_p: Vector3 = cam.global_position - e.global_position
	var orbit := to_p.normalized().cross(Vector3.UP).normalized() * 45.0 * e.orbit_dir
	var target: Vector3 = cam.global_position - to_p.normalized() * 90.0 + orbit
	e.steer_to(target, dt)
	e.gun_cd -= dt
	if e.gun_cd <= 0.0:
		e.gun_cd = 0.9 + randf() * 0.6
		_enemy_fire(e)
	return 2

func _act_evade(e: Enemy, dt: float) -> int:
	var away: Vector3 = (e.global_position - cam.global_position).normalized()
	var target: Vector3 = e.global_position + away * 60.0 + Vector3.UP * sin(Time.get_ticks_msec() * 0.003 + e.rseed) * 25.0
	e.steer_to(target, dt)
	e.heal_cd -= dt
	if e.heal_cd <= 0.0:
		e.hp = mini(e.hp + _bi("enemy", "regen"), e.hp_max)
		e.heal_cd = 1.0
	return 2

# ===== 共享资源(压测尖峰修复): 弹/火花的 mesh与材质只建一次 =====
# 原实现每发弹/每次命中都 new StandardMaterial3D -> shader变体编译+GPU上传,
# 交战峰值一秒十几次 = 材质编译风暴, 即 [STRESS] 59~64fps 尖峰的主因。
var _bolt_mesh_cache: BoxMesh = null
var _bolt_mat_cache: StandardMaterial3D = null
var _spark_mesh_cache: QuadMesh = null
var _spark_mat_cache := {}   # Color -> StandardMaterial3D (命中色固定3种, 至多3份)

func _bolt_mesh_res() -> BoxMesh:
	if _bolt_mesh_cache == null:
		_bolt_mesh_cache = BoxMesh.new()
		_bolt_mesh_cache.size = Vector3(0.2, 0.2, 8.0)   # 拉长弹条, 远距离可见
	return _bolt_mesh_cache

func _bolt_mat_res() -> StandardMaterial3D:
	if _bolt_mat_cache == null:
		_bolt_mat_cache = StandardMaterial3D.new()
		_bolt_mat_cache.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bolt_mat_cache.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_bolt_mat_cache.albedo_color = Color(1.0, 0.3, 0.15)
	return _bolt_mat_cache

func _spark_mesh_res() -> QuadMesh:
	if _spark_mesh_cache == null:
		_spark_mesh_cache = QuadMesh.new()
		_spark_mesh_cache.size = Vector2(0.35, 0.35)
	return _spark_mesh_cache

func _spark_mat_res(col: Color) -> StandardMaterial3D:
	if not _spark_mat_cache.has(col):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = col
		_spark_mat_cache[col] = m
	return _spark_mat_cache[col]

# ===== v0.9.7: hitch 归因 / 弹丸与特效节点池 / 启动预热 / 多线程目标扫描 =====
func _ev(tag: String) -> void:
	_frame_ev[tag] = int(_frame_ev.get(tag, 0)) + 1

func _bolt_acquire(pool: Array, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi: MeshInstance3D
	if pool.is_empty():
		mi = MeshInstance3D.new()
		mi.mesh = _bolt_mesh_res()
		add_child(mi)   # 仅新建时进树; 池内节点常驻隐藏, 免 add/remove churn
		_ev("bolt_new")
	else:
		mi = pool.pop_back()
		_ev("bolt_pool")
	mi.material_override = mat
	mi.visible = true
	mi.position = pos
	return mi

func _bolt_release(mi: MeshInstance3D, pool: Array) -> void:
	if is_instance_valid(mi):
		mi.visible = false
		if not pool.has(mi):
			pool.append(mi)

func _retarget_kick() -> void:
	# 主线程: 快照数据并派发 worker; 完成前不重复派发
	if _rt_busy:
		return
	_rt_result = PackedInt32Array()
	if enemies.is_empty() or wingmen.is_empty():
		_rt_result.resize(wingmen.size())
		_rt_result.fill(-1)
		return
	var epos := PackedVector3Array()
	var eok := PackedByteArray()
	epos.resize(enemies.size())
	eok.resize(enemies.size())
	for i in enemies.size():
		var e: Enemy = enemies[i]
		if is_instance_valid(e) and e.hp > 0:
			epos[i] = e.global_position
			eok[i] = 1
	_rt_enemy_pos = epos
	_rt_enemy_ok = eok
	var wpos := PackedVector3Array()
	var wbias := PackedFloat32Array()
	wpos.resize(wingmen.size())
	wbias.resize(wingmen.size())
	for i in wingmen.size():
		var w: Wingman = wingmen[i]
		if is_instance_valid(w):
			wpos[i] = w.global_position
			wbias[i] = 1.0 + 0.35 * fmod(absf(sin(float(w.idx + 1) * 12.9898) * 43758.5453), 1.0)
	_rt_wm_pos = wpos
	_rt_wm_bias = wbias
	_ev("rt_kick")
	_rt_busy = true
	_rt_task_id = WorkerThreadPool.add_task(Callable(self, "_retarget_job"), false, "wingman_retarget")

func _retarget_job() -> void:
	# worker 线程: 纯数学打分, 只读快照数组, 不触碰场景树(线程安全)
	var res := PackedInt32Array()
	res.resize(_rt_wm_pos.size())
	var n_e := _rt_enemy_pos.size()
	for wi in _rt_wm_pos.size():
		var best := -1
		var bd := 1e9
		var wp: Vector3 = _rt_wm_pos[wi]
		var bias: float = _rt_wm_bias[wi]
		for ei in n_e:
			if _rt_enemy_ok[ei] == 1:
				var d := wp.distance_to(_rt_enemy_pos[ei]) * bias
				if d < bd:
					bd = d
					best = ei
		res[wi] = best
	_rt_result = res

func _warmup_v097() -> void:
	# v0.9.7: 启动预热 —— 消灭"首用惰性加载/首次编译/首次上传"尖峰
	# 1) fx 帧序列全部预载(原为首次播放时同步 load PLY = 70~89ms 尖峰主因)
	for k in FX_FRAMES.keys():
		_fx_frames(k)
	# 2) 共享 mesh/材质预建(含 spark 三色, 首次命中不再编译)
	_bolt_mesh_res()
	_bolt_mat_res()
	_wm_bolt_mat_res()
	_spark_mesh_res()
	_spark_mat_res(Color(1.0, 0.35, 0.2))
	_spark_mat_res(Color(0.45, 0.8, 1.0))
	_spark_mat_res(Color(0.5, 0.9, 1.0))
	# 3) 弹池预建 64+64 隐藏节点
	for i in 64:
		var me := MeshInstance3D.new()
		me.mesh = _bolt_mesh_res()
		me.material_override = _bolt_mat_res()
		me.visible = false
		add_child(me)
		_bolt_pool_e.append(me)
		var mw := MeshInstance3D.new()
		mw.mesh = _bolt_mesh_res()
		mw.material_override = _wm_bolt_mat_res()
		mw.visible = false
		add_child(mw)
		_bolt_pool_w.append(mw)
	# 4) GPU 上传预热: fx 首帧 + 弹/火花材质, 相机前方 40m 微缩渲 3 帧后回收
	var fwd := cam.global_position - cam.basis.z * 40.0
	var ki := 0
	for k in FX_FRAMES.keys():
		var fr := _fx_frames(k)
		if not fr.is_empty():
			var n := GaussianSplatNode.new()
			n.gaussian = fr[0]
			n.position = fwd + Vector3.UP * (float(ki) * 0.5)
			n.scale = Vector3.ONE * 0.05
			add_child(n)
			_warmup_nodes.append(n)
		ki += 1
	var wb := MeshInstance3D.new()
	wb.mesh = _bolt_mesh_res()
	wb.material_override = _bolt_mat_res()
	wb.position = fwd + Vector3.RIGHT * 2.0
	wb.scale = Vector3.ONE * 0.05
	add_child(wb)
	_warmup_nodes.append(wb)
	var ws := MeshInstance3D.new()
	ws.mesh = _spark_mesh_res()
	ws.material_override = _spark_mat_res(Color(1.0, 0.35, 0.2))
	ws.position = fwd - Vector3.RIGHT * 2.0
	ws.scale = Vector3.ONE * 0.05
	add_child(ws)
	_warmup_nodes.append(ws)
	_warmup_frames = 3
	print("[WARMUP] fx=%d pool(e/w)=%d/%d warm_nodes=%d" % [FX_FRAMES.size(), _bolt_pool_e.size(), _bolt_pool_w.size(), _warmup_nodes.size()])
func _enemy_fire(e: Enemy) -> void:
	# v0.3.3:敌弹实体化 —— 有限速飞行弹(可闪避),预警环数据来源
	var from := e.global_position
	var target := cam.global_position - cam.basis.z * 8.0
	var spread := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (2.0 + from.distance_to(target) * 0.012)
	var aim := (target + spread - from).normalized()
	var mi := _bolt_acquire(_bolt_pool_e, from, _bolt_mat_res())   # v0.9.7:节点池复用(共享mesh/材质)
	mi.look_at(from + aim * 10.0, Vector3.UP)
	enemy_bolts.append({ "mi": mi, "vel": aim * enemy_bolt_speed, "life": 4.0, "eta": -1.0, "dmg_mul": e.dmg_mul })

func _tick_enemy_bolts(dt: float) -> void:
	for i in range(enemy_bolts.size() - 1, -1, -1):
		var b: Dictionary = enemy_bolts[i]
		var mi: MeshInstance3D = b["mi"]
		if not is_instance_valid(mi):
			enemy_bolts.remove_at(i)
			continue
		var prev: Vector3 = mi.global_position
		mi.global_position += (b["vel"] as Vector3) * dt
		b["life"] = float(b["life"]) - dt
		var cur: Vector3 = mi.global_position
		# 命中判定:弹道线段-玩家点距(防高速穿透);v0.7.1 机体 2m 级 → 命中半径 2.4→1.2m;god_mode 免伤(直锁导航观光模式)
		if not dead and _point_line_dist(cam.global_position, prev, cur) < 1.2:
			if god_mode:
				enemy_bolts.remove_at(i)
				_bolt_release(mi, _bolt_pool_e)   # v0.9.7:回池
				continue
			hp -= int(round(enemy_dmg * float(b.get("dmg_mul", 1.0))))   # v0.7:机型伤害倍率
			_play_sfx("hit_player", -6.0)
			vignette.color = Color(1, 0.1, 0.05, 0.35)
			shake = maxf(shake, 0.65)
			_hit_sparks(cur, Color(1.0, 0.35, 0.2))
			if hp <= 0:
				hp = 0
				dead = true
				phase = 3
				_feed("任务失败 — 按 R 重试本关(强化保留)")
			_bolt_release(mi, _bolt_pool_e)   # v0.9.7:回池
			enemy_bolts.remove_at(i)
			continue
		# 敌弹 <-> 唀机(对打): 唀机可挡枪被击落, 同样线段-点距判定
		var wing_hit := false
		for w in wingmen:
			if is_instance_valid(w) and _point_line_dist(w.global_position, prev, cur) < 1.6:
				(w as Wingman).hp -= enemy_dmg * 0.7
				_hit_sparks(cur, Color(0.45, 0.8, 1.0))
				wing_hit = true
				break
		if wing_hit:
			_bolt_release(mi, _bolt_pool_e)   # v0.9.7:回池
			enemy_bolts.remove_at(i)
			continue
		# 预警 ETA:最近接近时刻,掠过距离 <2.5m 视为威胁(v0.7.1 随 2m 级机体同步缩半)
		var rel := cam.global_position - cur
		var v: Vector3 = b["vel"]
		var tstar := -rel.dot(v) / maxf(v.length_squared(), 0.001)
		if tstar > 0.0 and (rel + v * tstar).length() < 2.5:
			b["eta"] = tstar
		else:
			b["eta"] = -1.0
		if float(b["life"]) <= 0.0:
			_bolt_release(mi, _bolt_pool_e)   # v0.9.7:回池
			enemy_bolts.remove_at(i)

func _point_line_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

# ==================== 友方僚机(与敌机对打; 友伤默认关闭) ====================
# 友伤结构保证: 玩家激光/导弹/等离子只遍历 enemies; 友方弹只判 enemies。
# wingman.friendly_fire=1 时友方弹才可伤玩家(默认 0=关闭友伤)。
const WING_TYPE := "p1"   # 僚机专属机型(falcon); 敌机流选型避开, 后续换专用友军机只改这一处
var wingmen: Array = []
var friendly_bolts: Array = []
var _wm_body_mesh: BoxMesh = null
var _wm_body_mat: StandardMaterial3D = null
var _wm_bolt_mat: StandardMaterial3D = null

class Wingman extends Area3D:
	var root = null
	var hp := 80.0
	var vel := Vector3.ZERO
	var target = null
	var speed := 42.0
	var fire_cd := 0.0
	var retarget_cd := 0.0
	var idx := 0

	func setup(r, i: int) -> void:
		root = r
		idx = i
		hp = root._b("enemy", "hp_base") * 2.0   # 机体数值与敌机相同, 血量翻倍
		var t: Dictionary = Crowd.TYPES[root.WING_TYPE]
		speed = 42.0 * float(t["speed_mul"])          # 与敌机同款速度公式
		fire_cd = randf()
		retarget_cd = randf()
		collision_layer = 4
		collision_mask = 0
		Crowd.build_jet(self, root.WING_TYPE, root._b("crowd", "jet_scale"))

func _wm_body_mesh_res() -> BoxMesh:
	if _wm_body_mesh == null:
		_wm_body_mesh = BoxMesh.new()
		_wm_body_mesh.size = Vector3(1.4, 0.6, 3.2)
	return _wm_body_mesh

func _wm_body_mat_res() -> StandardMaterial3D:
	if _wm_body_mat == null:
		_wm_body_mat = StandardMaterial3D.new()
		_wm_body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wm_body_mat.albedo_color = Color(0.35, 0.75, 1.0)
	return _wm_body_mat

func _wm_bolt_mat_res() -> StandardMaterial3D:
	if _wm_bolt_mat == null:
		_wm_bolt_mat = StandardMaterial3D.new()
		_wm_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wm_bolt_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_wm_bolt_mat.albedo_color = Color(0.4, 0.9, 1.0)
	return _wm_bolt_mat

func _make_wingman(i: int) -> void:
	var w := Wingman.new()
	w.setup(self, i)
	add_child(w)
	w.global_position = cam.global_position - cam.basis.z * 30.0 + cam.basis.x * (float(i) - 1.0) * 16.0 + Vector3.UP * -2.0
	wingmen.append(w)

func _spawn_wingmen() -> void:
	# v7.9:僚机渐次出厂(0.7s/架) —— 与敌机同样分摊创建成本
	_feed("僚机中队跃迁抵达 — 陆续就位(友伤已关闭)")
	_wingman_stagger()

func _wingman_stagger() -> void:
	if wingmen.size() >= _bi("wingman", "count"):
		return
	_make_wingman(wingmen.size())
	get_tree().create_timer(0.7).timeout.connect(_wingman_stagger)

func _tick_wingmen(dt: float) -> void:
	for wi in range(wingmen.size() - 1, -1, -1):
		var w: Wingman = wingmen[wi]
		if not is_instance_valid(w):
			wingmen.remove_at(wi)
			continue
		if w.hp <= 0.0:
			wingmen.remove_at(wi)
			_explode_small(w.global_position)
			w.queue_free()
			get_tree().create_timer(_b("wingman", "respawn")).timeout.connect(_respawn_wingman)
			continue
		w.retarget_cd -= dt
		if w.retarget_cd <= 0.0:
			w.retarget_cd = 0.6
			var best = null   # v0.9.7:目标由 WorkerThreadPool 后台扫描(_retarget_job), 主线程只回填
			var idx := -1
			if w.idx >= 0 and w.idx < _rt_result.size():
				idx = int(_rt_result[w.idx])
			if idx >= 0 and idx < enemies.size() and is_instance_valid(enemies[idx]) and (enemies[idx] as Enemy).hp > 0:
				best = enemies[idx]
			w.target = best
		var col := w.idx % 3
		var rowf := float(w.idx / 3)
		var hold: Vector3 = cam.global_position - cam.basis.z * (28.0 + rowf * 22.0) + cam.basis.x * (float(col) - 1.0) * 26.0 + Vector3.UP * (fmod(float(w.idx) * 0.7, 3.0) - 1.0) * 7.0
		var want: Vector3 = hold
		var tgt = w.target
		if tgt != null and is_instance_valid(tgt) and tgt.hp > 0:
			var to: Vector3 = tgt.global_position - w.global_position
			var dd := to.length()
			var nrm := to / maxf(dd, 0.01)
			var side := nrm.cross(Vector3.UP).normalized()
			var ang := float(w.idx) * TAU / 15.0
			want = tgt.global_position - nrm * 120.0 + (side * cos(ang) + Vector3.UP * sin(ang)) * 45.0
			w.fire_cd -= dt
			if dd < _b("wingman", "fire_range") and w.fire_cd <= 0.0:
				w.fire_cd = _b("wingman", "fire_interval")
				_wingman_fire(w, tgt)
		var sep := Vector3.ZERO   # 分离力: 偤机互斥 + 不贴玩家, 防穿模
		for o in wingmen:
			if o == w or not is_instance_valid(o):
				continue
			var dvo: Vector3 = w.global_position - (o as Wingman).global_position
			var dvl := dvo.length()
			if dvl < 26.0 and dvl > 0.01:
				sep += dvo / dvl * (26.0 - dvl) * 0.8
		var dpc := w.global_position - cam.global_position
		if dpc.length() < 20.0 and dpc.length() > 0.01:
			sep += dpc.normalized() * (20.0 - dpc.length()) * 0.6
		var acc := (want - w.global_position) * 0.6 + sep * 2.0
		if acc.length() > w.speed * 2.0:
			acc = acc.normalized() * w.speed * 2.0
		w.vel = w.vel.lerp(acc, clampf(dt * 2.2, 0.0, 1.0))
		if w.vel.length() > w.speed:
			w.vel = w.vel.normalized() * w.speed
		w.global_position += w.vel * dt
		if w.vel.length_squared() > 1.0:
			w.look_at(w.global_position + w.vel, Vector3.UP)

func _respawn_wingman() -> void:
	if wingmen.size() < _bi("wingman", "count"):
		_make_wingman(wingmen.size())
		_feed("僚机增援就位")

func _wingman_fire(w: Wingman, tgt) -> void:
	var mi := _bolt_acquire(_bolt_pool_w, w.global_position, _wm_bolt_mat_res())   # v0.9.7:节点池(局部position,根在原点=世界系)
	var aim: Vector3 = (tgt.global_position - w.global_position).normalized()
	mi.look_at(w.global_position + aim * 10.0, Vector3.UP)
	friendly_bolts.append({"mi": mi, "vel": aim * 320.0, "life": 2.5, "tgt": tgt})

func _tick_friendly_bolts(dt: float) -> void:
	var dmg := _b("wingman", "damage")
	for i in range(friendly_bolts.size() - 1, -1, -1):
		var b: Dictionary = friendly_bolts[i]
		var mi: MeshInstance3D = b["mi"]
		if not is_instance_valid(mi):
			friendly_bolts.remove_at(i)
			continue
		var prev: Vector3 = mi.global_position
		mi.global_position += (b["vel"] as Vector3) * dt
		b["life"] = float(b["life"]) - dt
		var cur: Vector3 = mi.global_position
		var consumed := false
		var tb = b.get("tgt")   # 只判自己的目标: O(弹x敌) -> O(弹), 压测帧率保护
		var dmg2: float = float(b.get("dmg", dmg))   # v7.3:弹体炮弹自带伤害
		if tb == core and core != null and is_instance_valid(core) and _point_line_dist(core.global_position, prev, cur) < 100.0:
			_damage_core(dmg2)
			_hit_sparks(cur, Color(1.0, 0.45, 0.3))
			consumed = true
		elif tb != null and is_instance_valid(tb) and tb.hp > 0 and _point_line_dist(tb.global_position, prev, cur) < 4.0:
			_damage_enemy(tb, dmg2)
			_hit_sparks(cur, Color(0.5, 0.9, 1.0))
			consumed = true
		if not consumed and _b("wingman", "friendly_fire") > 0.0 and not dead \
				and _point_line_dist(cam.global_position, prev, cur) < 1.2:
			hp -= int(round(dmg))
			consumed = true
		if consumed or float(b["life"]) <= 0.0:
			_bolt_release(mi, _bolt_pool_w)   # v0.9.7:回池
			friendly_bolts.remove_at(i)

# ==================== 数值平衡表(data/balance.txt 驱动)====================
# 设计参照:Endless Sky 纯文本数据表 / Vega Strike units.csv / Ian Schreiber《Game Balance》
# 原则:改表即改手感;代码只读表。表缺失时用内置默认值兜底,保证工程永不因数据文件而崩。
const BALANCE_PATH := "res://data/balance.txt"
var BAL: Dictionary = {}

func _default_balance() -> Dictionary:
	return {
		"player": { "hp": 100.0, "armor_upgrade": 25.0, "speed_base": 40.0, "speed_boost": 600.0, "speed_upgrade": 0.15, "accel_base": 13.0, "accel_boost": 100.0 },
		"cannon": { "damage": 12.0, "fire_interval": 0.10, "range": 600.0, "heat_per_shot": 5.0, "bloom_per_shot": 0.55, "bloom_max": 3.2, "bloom_decay": 4.0 },
		"plasma": { "damage": 70.0, "fire_interval": 1.1, "projectile_speed": 320.0, "projectile_life": 6.0, "hit_radius": 4.5, "blast_radius": 14.0, "blast_edge": 0.45, "heat_per_shot": 34.0, "core_mult": 1.25 },
		"heat": { "enabled": 0.0, "max": 100.0, "dissipate": 26.0, "resume_below": 35.0 },
		"weapon_spread": { "damage": 9.0, "pellets": 6.0, "spread": 4.5, "fire_interval": 0.9, "range": 420.0, "unlock_level": 3.0 },
		"weapon_laser": { "dps": 620.0, "beam_time": 1.5, "recharge": 2.2, "range": 1100.0, "beam_width": 0.35, "core_mult": 1.5, "unlock_level": 5.0 },
		"firecontrol": { "auto_cone": 30.0 },
		"playergun": { "damage": 22.0, "fire_interval": 0.18, "speed": 520.0, "life": 3.0 },   # v7.3:弹体炮(敌机同款弹体)
		"megabeam": { "cooldown": 60.0, "duration": 2.0, "dps": 4000.0, "range": 4000.0, "radius": 14.0, "far_range": 1500.0, "far_factor": 0.35, "core_mult": 2.0 },
		"fx": { "muzzle_flash": 0.0 },
		"enemy": { "visual_size": 8.0, "hp_base": 180.0, "hp_level_scale": 0.2, "damage_base": 4.0, "damage_per_level": 1.0, "engage_range": 260.0, "retreat_hp": 30.0, "regen": 8.0, "kill_parts": 10.0, "kill_score": 100.0, "wave_base": 53.0, "wave_per_level": 27.0, "spawn_interval": 4.0, "max_alive": 172.0, "bolt_speed": 130.0, "warn_time": 1.6 },
		"crowd": { "members": 43.0, "attack_tokens": 10.0, "splat_range": 900.0, "gauss_cap": 96.0, "jet_scale": 0.45 },
		"wingman": { "count": 3.0, "hp": 80.0, "speed": 55.0, "fire_range": 520.0, "fire_interval": 0.5, "dps": 18.0, "respawn": 25.0, "friendly_fire": 0.0 },
		"camera": { "fov": 70.0 },
		"core": { "hp_base": 18000.0, "hp_per_level": 6000.0 },
		"economy": { "clear_parts_base": 120.0, "clear_parts_per_level": 30.0, "upgrade_cost": 100.0, "dmg_upgrade": 0.15, "quota_base": 8.0, "quota_per_level": 2.0, "survival_time": 300.0 },
		"demo": { "l1_quota": 160.0, "l2_quota": 180.0, "l3_quota": 80.0, "l3_support_t": 45.0, "raid_interval": 8.0, "raid_base": 40.0, "raid_per_enemy": 1.5, "song_cd_min": 40.0, "song_cd_max": 65.0 },
	}

# ===== 压测模式(-- --stress): 敌机x5 + 120FPS 上限 + FPS 计数 =====
func _apply_stress() -> void:
	# 敌机数量x5(每流成员/在场上限/波次基数), 击杀配额x5 维持关卡时长;
	# FPS: 上限 120 + 关垂直同步(默认 vsync 锁显示器刷新率); 右上角 FPS/敌数 HUD。
	var mult := {"enemy": ["wave_base", "wave_per_level", "max_alive"],
			"crowd": ["members"],
			"wingman": ["count"],
			"economy": ["quota_base", "quota_per_level"]}
	for sec in mult:
		for key in mult[sec]:
			if BAL.has(sec) and BAL[sec] is Dictionary and (BAL[sec] as Dictionary).has(key):
				BAL[sec][key] = _b(sec, key) * 5.0
	Engine.max_fps = 120
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var layer := CanvasLayer.new()
	add_child(layer)
	_fps_label = Label.new()
	_fps_label.position = Vector2(1080, 8)
	_fps_label.add_theme_font_size_override("font_size", 15)
	_fps_label.modulate = Color(0.7, 1.0, 0.7)
	layer.add_child(_fps_label)
	print("[STRESS] enemy x5: members=%d max_alive=%d wave_base=%d quota_base=%d | fps<=120 vsync off" % [
		_bi("crowd", "members"), _bi("enemy", "max_alive"), _bi("enemy", "wave_base"), _bi("economy", "quota_base")])

func _b(sec: String, key: String) -> float:
	var tbl: Variant = BAL.get(sec, {})
	return float(tbl.get(key, 0.0)) if tbl is Dictionary else 0.0

func _bi(sec: String, key: String) -> int:
	return int(round(_b(sec, key)))

func _load_balance() -> void:
	BAL = _default_balance()
	if not FileAccess.file_exists(BALANCE_PATH):
		push_warning("balance.txt 缺失 → 使用内置默认数值")
		return
	var f := FileAccess.open(BALANCE_PATH, FileAccess.READ)
	if f == null:
		push_warning("balance.txt 打开失败 → 使用内置默认数值")
		return
	var sec := ""
	var n := 0
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with(";"):
			continue
		if line.begins_with("[") and line.contains("]"):
			sec = line.substr(1, line.find("]") - 1).strip_edges().to_lower()   # v0.9.2:duantou allow comment
			if not BAL.has(sec):
				BAL[sec] = {}
			continue
		var eq := line.find("=")
		if eq < 0 or sec.is_empty():
			continue
		var key := line.substr(0, eq).strip_edges().to_lower()
		var val := line.substr(eq + 1).strip_edges()
		var ci := val.find("#")
		if ci >= 0:
			val = val.substr(0, ci).strip_edges()
		if val.is_valid_float():
			BAL[sec][key] = val.to_float()
			n += 1
		elif not val.is_empty():
			BAL[sec][key] = val
	print("balance: 载入 %d 项(%s)" % [n, BALANCE_PATH])

func _balance_report() -> void:
	# 数值验收(参照 Ian Schreiber:先算清 TTK/热量/收支,再谈手感)
	var cdmg := _b("cannon", "damage")
	var cint := _b("cannon", "fire_interval")
	var cdps := cdmg / maxf(cint, 0.001)
	var pdmg := _b("plasma", "damage")
	var pint := _b("plasma", "fire_interval")
	var pdps := pdmg / maxf(pint, 0.001)
	var net_c := _b("cannon", "heat_per_shot") / maxf(cint, 0.001) - _b("heat", "dissipate")
	var t_boil := _b("heat", "max") / net_c if net_c > 0.0 else 999.0
	var p_boil := int(_b("heat", "max") / _b("plasma", "heat_per_shot"))
	var t_recover := (_b("heat", "max") - _b("heat", "resume_below")) / _b("heat", "dissipate")
	print("== 数值报告 ==")
	print("机炮 %.0f×%.2fs=DPS%.0f | 等离子 %.0f×%.2fs=DPS%.0f(核心×%.2f)| 弹速 %.0fm/s" % [cdmg, cint, cdps, pdmg, pint, pdps, _b("plasma", "core_mult"), _b("plasma", "projectile_speed")])
	print("热量: 机炮净积热 %.1f/s → 连射 %.1fs 过热 | 等离子 %d 发过热 | 过热恢复 %.1fs" % [net_c, t_boil, p_boil, t_recover])
	for L in range(1, 6):
		var ehp := _b("enemy", "hp_base") * (1.0 + _b("enemy", "hp_level_scale") * float(L - 1))
		var ch := ceili(ehp / cdmg)
		var ph := ceili(ehp / pdmg)
		var chp := float(_bi("core", "hp_base") + _bi("core", "hp_per_level") * (L - 1))
		var pc := ceili(chp / (pdmg * _b("plasma", "core_mult")))
		var q := _bi("economy", "quota_base") + L * _bi("economy", "quota_per_level")
		var inc := q * _bi("enemy", "kill_parts") + _bi("economy", "clear_parts_base") + L * _bi("economy", "clear_parts_per_level")
		print("L%d 敌HP%.0f: 机炮%d发/%.1fs 等离子%d发 | 核心%.0f: 等离子%d发 | 配额%d 收入%d" % [L, ehp, ch, ch * cint, ph, chp, pc, q, inc])

# ==================== 武器:机炮(hitscan)+ 等离子(实体弹)+ 热量 ====================
func _fire_cannon() -> void:
	if float((BAL.get("cannon", {}) as Dictionary).get("enabled", 1.0)) < 0.5:
		return   # v0.9.3:机炮退役 —— 常驻激光接管
	if dead or fire_cd > 0.0 or overheated:
		return
	var from := cam.global_position + cam.basis.z * -1.0
	var dir := _spread_dir(_aim_dir(), bloom)   # v6.16:永远直射准星方向, 不追锁
	var to := from + dir * _b("cannon", "range")
	var q := PhysicsRayQueryParameters3D.create(from, to, 2)
	q.collide_with_areas = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		# v0.8:机炮常开 —— 未压到目标也持续开火(仅无伤害结算), 命中判定照常在下方进行
		fire_cd = _b("cannon", "fire_interval")
		_muzzle_flash(from - cam.basis.z * 2.0, false)
		_fx_play("muzzle", from - cam.basis.z * 2.4 + cam.basis.x * 0.6 - cam.basis.y * 0.4, 1.0)
		_add_tracer(from + cam.basis.x * 0.6 - cam.basis.y * 0.4, to, Color(0.5, 1.0, 0.8))
		bloom = minf(bloom + _b("cannon", "bloom_per_shot"), _b("cannon", "bloom_max"))
		return
	_play_sfx("cannon", -12.0, randf_range(0.92, 1.08))
	fire_cd = _b("cannon", "fire_interval")
	_muzzle_flash(from - cam.basis.z * 2.0, false)
	_fx_play("muzzle", from - cam.basis.z * 2.4 + cam.basis.x * 0.6 - cam.basis.y * 0.4, 1.0)   # v0.8:高斯枪口焰
	shake = maxf(shake, 0.05)
	var endp := to
	if hit.has("collider"):
		var col: Object = hit["collider"]
		endp = hit["position"]
		if col == core:
			_damage_core(_b("cannon", "damage") * dmg_mult)
		elif col is Area3D and col.has_meta("boss"):
			_damage_core(_b("cannon", "damage") * dmg_mult)   # v3.2 BOSS low-poly prism hit
		elif col is Enemy:
			_damage_enemy(col as Enemy, _b("cannon", "damage") * dmg_mult)
	_add_tracer(from + cam.basis.x * 0.6 - cam.basis.y * 0.4, endp, Color(0.5, 1.0, 0.8))
	bloom = minf(bloom + _b("cannon", "bloom_per_shot"), _b("cannon", "bloom_max"))
	_add_heat(_b("cannon", "heat_per_shot"))

func _fire_plasma() -> void:
	if float((BAL.get("plasma", {}) as Dictionary).get("enabled", 1.0)) < 0.5:
		return   # v0.9.2:等离子本机关闭(重武器移交僚机)
	_play_sfx("plasma", -7.0, randf_range(0.95, 1.05))
	if dead or plasma_cd > 0.0 or overheated:
		return
	# v0.8.2:锁定发射门整体拆除 —— 等离子沿准星自由开火(弹丸命中判定照常), 不再有"压到才打"的憋屈感
	plasma_cd = _b("plasma", "fire_interval")
	var from := cam.global_position - cam.basis.z * 1.5 - cam.basis.x * 0.6
	_muzzle_flash(from, true)
	shake = maxf(shake, 0.15)
	var dir := _aim_dir()   # v6.16:直射准星
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.6
	sm.height = 1.2
	mi.mesh = sm
	var m := ShaderMaterial.new()   # v0.9.1:弹体 shader(GDQuest projectile 手法:能量条带滚动+核心增亮)
	m.shader = _get_shader("bolt")
	m.set_shader_parameter("tint", Color(1.0, 0.55, 0.2, 1.0))
	m.set_shader_parameter("energy", 1.6)
	mi.material_override = m
	mi.position = from
	add_child(mi)
	mi.look_at(from + dir * 10.0, Vector3.UP)
	mi.scale = Vector3(1.0, 1.0, 3.0)  # 拉长弹体=尾焰感
	var lt := OmniLight3D.new()
	lt.light_color = Color(1.0, 0.55, 0.25)
	lt.omni_range = 38.0
	lt.light_energy = 2.2
	mi.add_child(lt)  # 光随弹飞行
	plasma_bolts.append({ "mi": mi, "vel": dir * _b("plasma", "projectile_speed"), "life": _b("plasma", "projectile_life") })
	_add_heat(_b("plasma", "heat_per_shot"))

# ==================== v0.8 武器扩展:散弹炮 + 超级激光炮(数据表驱动, 关卡解锁) ====================
func _fire_spread() -> void:
	# 散弹炮:一次 N 弹丸锥形散布(每颗独立 hitscan),中近距爆发
	if dead or spread_cd > 0.0 or not _spread_unlocked():
		return
	spread_cd = _b("weapon_spread", "fire_interval")
	var from := cam.global_position - cam.basis.z * 1.2
	_muzzle_flash(from, false)
	var n := _bi("weapon_spread", "pellets")
	var half := deg_to_rad(_b("weapon_spread", "spread")) * 0.5
	var aim := _aim_dir()
	var axis := Vector3.UP.cross(aim)
	if axis.length() < 0.1:
		axis = Vector3.RIGHT.cross(aim)
	axis = axis.normalized()
	for i in n:
		var t := float(i) / maxf(float(n - 1), 1.0)
		var dir := aim.rotated(axis, lerpf(-half, half, t)).rotated(aim, randf_range(-half, half)).normalized()
		var to := from + dir * _b("weapon_spread", "range")
		var q := PhysicsRayQueryParameters3D.create(from, to, 2)
		q.collide_with_areas = true
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
		var endp := to
		if hit.has("collider"):
			endp = hit["position"]
			var col: Object = hit["collider"]
			if col == core:
				_damage_core(_b("weapon_spread", "damage") * dmg_mult)
			elif col is Area3D and col.has_meta("boss"):
				_damage_core(_b("weapon_spread", "damage") * dmg_mult)   # v3.2 BOSS低模棱柱命中
			elif col is Enemy:
				_damage_enemy(col as Enemy, _b("weapon_spread", "damage") * dmg_mult)
		_add_tracer(from - cam.basis.x * 0.6, endp, Color(1.0, 0.8, 0.4))
	_play_sfx("cannon", -8.0, 0.7)

func _missile_unlocked() -> bool:
	# v0.9.2:追踪导弹 —— 本机第二武器(表 [missile] 驱动,L1 起可用)
	return _b("missile", "enabled") >= 0.5 and (demo_weapons or level >= _bi("missile", "unlock_level"))

func _missile_target() -> Object:
	# 优先火控锁定;否则最近敌机;再否则核心
	if lock_target != null and is_instance_valid(lock_target):
		if (not (lock_target is Enemy)) or (lock_target as Enemy).hp > 0:
			return lock_target
	var best: Object = null
	var bd := 1e9
	for e in enemies:
		if is_instance_valid(e) and e.hp > 0:
			var d := cam.global_position.distance_to(e.global_position)
			if d < bd:
				bd = d
				best = e
	if best != null:
		return best
	return core if core != null and is_instance_valid(core) else null

func _fire_missile() -> void:
	# v0.9.2:追踪导弹 —— 翼下交替发射,比例导引追击,命中/自毁爆炸
	if dead or missile_cd > 0.0 or not _missile_unlocked():
		return
	var tgt := _missile_target()
	if tgt == null:
		return   # 无目标不浪费
	missile_cd = _b("missile", "fire_interval")
	_play_sfx("missile_launch", -3.0, randf_range(0.95, 1.05))
	var side := 1.0 if missiles.size() % 2 == 0 else -1.0
	var from := cam.global_position - cam.basis.z * 2.2 + cam.basis.x * side * 1.4 - cam.basis.y * 0.3
	var dir := _aim_dir()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.22, 1.7)
	mi.mesh = bm
	var m := ShaderMaterial.new()   # 弹体白热+滚动条带(复用 v0.9.1 bolt shader)
	m.shader = _get_shader("bolt")
	m.set_shader_parameter("tint", Color(1.0, 0.85, 0.55))
	m.set_shader_parameter("energy", 1.8)
	mi.material_override = m
	mi.position = from
	add_child(mi)
	mi.look_at(from + dir * 10.0, Vector3.UP)
	if _b("missile", "smoke") >= 0.5:
		var p := GPUParticles3D.new()   # 尾烟:微亮粒子拖尾(世界坐标)
		p.amount = 36
		p.lifetime = 0.55
		p.local_coords = false
		p.visibility_aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 4.0))
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 0, -1)
		pm.spread = 12.0
		pm.initial_velocity_min = 1.5
		pm.initial_velocity_max = 3.0
		pm.gravity = Vector3.ZERO
		pm.scale_min = 0.10
		pm.scale_max = 0.22
		pm.color = Color(0.85, 0.85, 0.8, 0.55)
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.35, 0.35)
		var qm := StandardMaterial3D.new()
		qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		qm.albedo_color = Color(0.8, 0.8, 0.75, 0.55)
		q.material = qm
		p.draw_pass_1 = q
		mi.add_child(p)
	missiles.append({ "mi": mi, "vel": dir * _b("missile", "speed"), "target": tgt, "life": _b("missile", "lifetime") })

func _tick_missiles(dt: float) -> void:
	# v0.9.2:制导(速度矢量 slerp 向目标,恒速)→ 命中判定 → 爆炸/自毁
	missile_cd = maxf(missile_cd - dt, 0.0)
	var spd := _b("missile", "speed")
	var turn := _b("missile", "turn_rate")
	var hr := _b("missile", "hit_radius")
	for i in range(missiles.size() - 1, -1, -1):
		var ms: Dictionary = missiles[i]
		var mi: MeshInstance3D = ms["mi"]
		if not is_instance_valid(mi):
			missiles.remove_at(i)
			continue
		ms["life"] = float(ms["life"]) - dt
		var tgt = ms["target"]   # v0.9.2 untyped: freed-instance safe
		if tgt != null and is_instance_valid(tgt) and tgt is Enemy and (tgt as Enemy).hp <= 0:
			tgt = null   # 目标被击落 → 直飞自毁
		if tgt != null and is_instance_valid(tgt):
			var desired: Vector3 = ((tgt.global_position as Vector3) + Vector3.UP * 1.5 - mi.global_position).normalized() * spd
			ms["vel"] = (ms["vel"] as Vector3).slerp(desired, clampf(turn * dt, 0.0, 1.0)).normalized() * spd
		var vel: Vector3 = ms["vel"]
		mi.global_position += vel * dt
		mi.look_at(mi.global_position + vel, Vector3.UP)
		var hit := false
		for e in enemies:
			if is_instance_valid(e) and e.hp > 0 and mi.global_position.distance_to(e.global_position) < hr + 4.0:
				_damage_enemy(e, _b("missile", "damage") * dmg_mult)
				hit = true
				break
		if not hit and core != null and is_instance_valid(core) and mi.global_position.distance_to(core.global_position) < 90.0 + hr:
			_damage_core(_b("missile", "damage") * _b("missile", "core_mult") * dmg_mult)
			hit = true
		if hit or float(ms["life"]) <= 0.0:
			if hit:
				_explode_small(mi.global_position)
				shake = maxf(shake, 0.12)
			mi.queue_free()
			missiles.remove_at(i)

func _tick_laser(dt: float) -> void:
	# 超级激光炮:充能(recharge)→持续光束(beam_time)循环;未解锁(关卡门槛)永不充能
	if dead or not _laser_unlocked():
		_hide_laser_fx()   # v0.9:统一熄灯(双层/光晕/点光)
		return
	laser_t += dt
	if laser_phase == 0:   # 充能阶段
		if laser_t >= _b("weapon_laser", "recharge"):
			laser_phase = 1
			laser_t = 0.0
			laser_beam_len = 0.0   # v0.9.1:自炮口重新伸出
			_laser_swirl = false
			_play_sfx("plasma", -4.0, 0.6)
		else:
			_update_charge_fx(clampf(laser_t / maxf(_b("weapon_laser", "recharge"), 0.01), 0.0, 1.0))   # v0.9:充能可视化
		if laser_beam != null:
			laser_beam.visible = false
		if laser_glow != null:
			laser_glow.visible = false
		return
	# 照射阶段:逐帧 hitscan,持续 tick 伤害(核心享受 core_mult)
	var from := cam.global_position - cam.basis.z * 1.2
	var dir := _aim_dir()
	var to := from + dir * _b("weapon_laser", "range")
	var q := PhysicsRayQueryParameters3D.create(from, to, 2)
	q.collide_with_areas = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	var endp := to
	var nrm := -dir
	if hit.has("normal"):
		nrm = hit["normal"]   # v0.9.1:弹着粒子按命中法线定向
	if hit.has("collider"):
		endp = hit["position"]
		var col: Object = hit["collider"]
		var dmg: float = _b("weapon_laser", "dps") * dmg_mult * dt
		if col == core:
			_damage_core(dmg * _b("weapon_laser", "core_mult"))
		elif col is Area3D and col.has_meta("boss"):
			_damage_core(dmg * _b("weapon_laser", "core_mult"))   # v3.2 BOSS low-poly prism hit
		elif col is Enemy:
			_damage_enemy(col as Enemy, dmg)
	# v0.9.8b:粗束命中容差 —— 束方向永远=准星方向(绝不自动控准星),仅按角度容差扫到即判中
	var dealt := hit.has("collider")
	var cone := deg_to_rad(maxf(_b("weapon_laser", "hit_cone"), 0.0))
	if cone > 0.0 and not (hit.has("collider") and hit["collider"] is Enemy):
		var best_e: Enemy = null
		var best_a := cone
		for e in enemies:
			if is_instance_valid(e) and e.hp > 0:
				var ed: Vector3 = e.global_position - from
				if ed.length() <= _b("weapon_laser", "range") + 20.0:
					var a: float = dir.angle_to(ed.normalized())
					if a < best_a:
						best_a = a
						best_e = e
		if best_e != null:
			endp = best_e.global_position
			nrm = -dir
			_damage_enemy(best_e, _b("weapon_laser", "dps") * dmg_mult * dt)
			dealt = true
	_update_beam(from, endp, nrm, dt, dealt)
	# v0.8:光束命中点高斯火花(循环 laser_hit 序列)
	if hit.has("collider"):
		if _laser_fx == null or not is_instance_valid(_laser_fx):
			_laser_fx = GaussianSplatNode.new()
			_laser_fx.gaussian = _fx_frames("laser_hit")[0]
			add_child(_laser_fx)
		_laser_fx.visible = true
		_laser_fx.position = endp
		var lframe: int = int(fmod(fx_time * 10.0, 8.0))   # v0.9.3:常驻光束 —— 命中火花按特效时钟 10fps 循环
		var lframes := _fx_frames("laser_hit")
		if _laser_fx.gaussian != lframes[lframe]:
			_laser_fx.gaussian = lframes[lframe]
	elif _laser_fx != null and is_instance_valid(_laser_fx):
		_laser_fx.visible = false
	if laser_t >= _b("weapon_laser", "beam_time"):
		laser_phase = 0
		laser_t = 0.0
		_hide_laser_fx()
		if _laser_fx != null and is_instance_valid(_laser_fx):
			_laser_fx.visible = false

func _update_beam(from: Vector3, to: Vector3, nrm: Vector3, dt: float, did_hit: bool) -> void:
	# v0.9:三层光束重构 —— 白炽核心管 + 宽幅辉光管(shader 能量流/闪络/端部软化)
	#      + 炮口/弹着光晕 billboard + 双点光;替代 v0.8 单层加色圆柱(随机透明度闪)
	if laser_beam == null:
		laser_beam = _make_beam_layer(0.55)    # 核心:0.55×beam_width,白炽
		laser_glow = _make_beam_layer(2.6)     # 辉光:2.6×,柔和
		laser_muzzle_fx = _make_flare(3.4)
		laser_impact_fx = _make_flare(7.5)
		laser_mlight = _make_light(Color(0.4, 0.85, 1.0), 60.0)
		laser_ilight = _make_light(Color(0.5, 0.9, 1.0), 130.0)
	var d := to - from
	var y_axis := d.normalized()
	var x_axis := y_axis.cross(Vector3.UP)
	if x_axis.length() < 0.1:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	var b := Basis(x_axis, y_axis, z_axis)
	laser_beam_len = minf(laser_beam_len + 12500.0 * dt, d.length())
	var tip := from + y_axis * laser_beam_len
	var arrived := laser_beam_len >= d.length() - 1.5
	var fxpos := (tip if not arrived else to - y_axis * 1.6)
	# v0.9.6:视觉段外移(8m 起)只留核心细束 —— 近场不再糊屏;辉光层/炮口光晕/近场点光下线,状态反馈移入 HUD 准星
	var vfrom := from + y_axis * 8.0
	laser_beam.visible = true
	laser_beam.basis = b
	laser_beam.global_position = (vfrom + tip) * 0.5
	laser_beam.scale = Vector3(1.0, maxf((tip - vfrom).length(), 0.1), 1.0)
	if laser_glow != null:
		laser_glow.visible = false
	if laser_muzzle_fx != null:
		laser_muzzle_fx.visible = false
	var ramp := clampf(laser_t / 0.12, 0.0, 1.0)
	var tailt := maxf(_b("weapon_laser", "beam_time") - laser_t, 0.0)
	var env := ramp * clampf(tailt / 0.15, 0.0, 1.0) * (0.85 + 0.15 * randf())
	_set_beam_params(laser_beam, Color(0.55, 0.95, 1.0), 1.0, 0.85 * env, 16.0, 5.0)   # v0.9.7:常驻束恢复可见
	beam_hit = arrived and did_hit   # v0.9.6:HUD 命中标记数据源
	beam_hit_t = (beam_hit_t + dt) if beam_hit else 0.0
	if beam_hit:
		_place_flare(laser_impact_fx, fxpos, Color(0.6, 0.95, 1.0), 1.0 * env, 0.6, 1.0)   # v0.9.7
	elif laser_impact_fx != null:
		laser_impact_fx.visible = false
	laser_mlight.visible = false   # v0.9.6:近场点光下线
	laser_ilight.visible = beam_hit
	laser_ilight.global_position = fxpos
	laser_ilight.light_energy = 2.5 * env   # v0.9.7
	# v0.9.1:束内能量尘(GDQuest BeamParticles 手法)—— 发射盒随束长伸缩
	if laser_motes == null:
		laser_motes = _make_beam_motes()
	laser_motes.visible = true
	laser_motes.emitting = true
	laser_motes.global_position = (vfrom + tip) * 0.5
	if tip.distance_to(laser_motes.global_position) > 0.5:
		laser_motes.look_at(tip, Vector3.UP)
	(laser_motes.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.6, 0.6, clampf(laser_beam_len, 40.0, maxf(_b("weapon_laser", "fx_fade"), 40.0)) * 0.5)   # v0.9.8:随束加粗
	# v0.9.1:弹着环状粒子 —— 到达目标后按命中法线定向,0.28s 节奏重发
	if did_hit and arrived:
		if laser_ip == null:
			laser_ip = _make_impact_particles()
		laser_ip.visible = true
		laser_ip.global_position = to
		if nrm.length_squared() > 0.01:
			var upv := (Vector3.RIGHT if absf(nrm.dot(Vector3.UP)) > 0.99 else Vector3.UP)
			laser_ip.look_at(to + nrm, upv)
		_impact_p_cd -= dt
		if _impact_p_cd <= 0.0:
			_impact_p_cd = 0.28
			laser_ip.restart()
	elif laser_ip != null:
		laser_ip.visible = false

func _hide_laser_fx() -> void:
	# v0.9:熄灯 —— 光束双层/炮口弹着光晕/双点光全部隐藏(充能期仅炮口光晕再亮起)
	for n in [laser_beam, laser_glow, laser_muzzle_fx, laser_impact_fx, laser_mlight, laser_ilight]:
		if n != null:
			n.visible = false
	laser_beam_len = 0.0
	if laser_motes != null:
		laser_motes.visible = false
		laser_motes.emitting = false
	if laser_ip != null:
		laser_ip.visible = false
		laser_ip.emitting = false

func _update_charge_fx(prog: float) -> void:
	# v0.9:充能可视化 —— v0.8 充能 2.2s 全程无提示;现在炮口光晕随进度涨亮+青蓝粒子内旋
	var from := cam.global_position - cam.basis.z * 6.0   # v0.9.6:充能粒子外移,不糊屏
	if laser_muzzle_fx == null:
		laser_muzzle_fx = _make_flare(3.2)
	if laser_mlight == null:
		laser_mlight = _make_light(Color(0.4, 0.85, 1.0), 50.0)
	if not _laser_swirl:
		_laser_swirl = true
		_fx_play("charge", from, 0.45, 6.0 / maxf(_b("weapon_laser", "recharge"), 0.5))   # v0.9.6:缩小
	var m := laser_muzzle_fx.material_override as ShaderMaterial
	laser_muzzle_fx.visible = false   # v0.9.6:充能反馈移入 HUD,3D 近场光晕下线
	laser_muzzle_fx.global_position = from
	m.set_shader_parameter("tint", Color(0.45, 0.9, 1.0))
	m.set_shader_parameter("intensity", 0.15 + 0.35 * prog * prog)   # v0.9.5
	m.set_shader_parameter("spike", 0.7)
	m.set_shader_parameter("ring", 0.0)
	m.set_shader_parameter("progress", clampf(0.3 + 0.7 * prog, 0.0, 1.0))
	m.set_shader_parameter("time", fx_time)
	laser_mlight.visible = true
	laser_mlight.global_position = from
	laser_mlight.light_energy = 0.15 + 0.5 * prog

func _get_shader(key: String) -> Shader:
	if _shader_cache.has(key):
		return _shader_cache[key]
	var sh: Shader = load("res://shaders/%s.gdshader" % key)
	_shader_cache[key] = sh
	return sh

func _make_beam_layer(width_mul: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var w: float = _b("weapon_laser", "beam_width") * width_mul
	cm.top_radius = w
	cm.bottom_radius = w
	cm.height = 1.0
	cm.radial_segments = 12
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	var m := ShaderMaterial.new()
	m.shader = _get_shader("laser_beam")
	mi.material_override = m
	add_child(mi)
	return mi

func _make_flare(size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = _get_shader("fx_flare")
	mi.material_override = m
	mi.visible = false
	add_child(mi)
	return mi

func _make_light(col: Color, rng: float) -> OmniLight3D:
	var lt := OmniLight3D.new()
	lt.light_color = col
	lt.omni_range = rng
	lt.visible = false
	add_child(lt)
	return lt

func _make_beam_motes() -> GPUParticles3D:
	# v0.9.1:束内能量尘 —— 沿光束漂移的微亮珠(GDQuest laser_beam_3d BeamParticles 手法)
	var p := GPUParticles3D.new()
	p.amount = 32   # v0.9.7
	p.lifetime = 0.6
	p.visibility_aabb = AABB(Vector3(-1.0, -1.0, -2000.0), Vector3(2.0, 2.0, 4000.0))   # v0.9.3:常驻长光束
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.3, 0.3, 10.0)
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.05
	pm.scale_max = 0.14
	p.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mm.albedo_color = Color(0.5, 0.8, 1.0)   # v0.9.7
	sm.material = mm
	p.draw_pass_1 = sm
	p.emitting = false
	add_child(p)
	return p

func _make_impact_particles() -> GPUParticles3D:
	# v0.9.1:弹着环状迸溅 —— 环形发射+法线定向(GDQuest CollisionParticles 手法)
	var p := GPUParticles3D.new()
	p.amount = 26
	p.lifetime = 0.5
	p.explosiveness = 0.8
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 0, 1)
	pm.emission_ring_radius = 1.1
	pm.emission_ring_inner_radius = 0.2
	pm.emission_ring_height = 0.0
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 25.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.08
	pm.scale_max = 0.22
	pm.color = Color(0.65, 0.9, 1.0)
	p.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mm.albedo_color = Color(0.8, 0.97, 1.0)
	sm.material = mm
	p.draw_pass_1 = sm
	p.emitting = false
	add_child(p)
	return p

func _set_beam_params(mi: MeshInstance3D, col: Color, coreness: float, power: float, nscale: float, scroll: float) -> void:
	var m := mi.material_override as ShaderMaterial
	m.set_shader_parameter("beam_color", Color(col.r, col.g, col.b, 1.0))
	m.set_shader_parameter("coreness", coreness)
	m.set_shader_parameter("power", power)
	m.set_shader_parameter("noise_scale", nscale)
	m.set_shader_parameter("scroll_speed", scroll)
	m.set_shader_parameter("flicker", randf())
	m.set_shader_parameter("time", fx_time)
	m.set_shader_parameter("beam_len", laser_beam_len)   # v0.9.4:沿程衰减
	m.set_shader_parameter("fade_dist", maxf(_b("weapon_laser", "fx_fade"), 20.0))

func _place_flare(mi: MeshInstance3D, pos: Vector3, col: Color, intensity: float, spike: float, ring: float) -> void:
	mi.visible = true
	mi.global_position = pos
	var m := mi.material_override as ShaderMaterial
	m.set_shader_parameter("tint", Color(col.r, col.g, col.b, 1.0))
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("spike", spike)
	m.set_shader_parameter("ring", ring)
	m.set_shader_parameter("progress", 1.0)
	m.set_shader_parameter("time", fx_time)

func _tick_bolts(dt: float) -> void:
	var hr := _b("plasma", "hit_radius")
	for i in range(plasma_bolts.size() - 1, -1, -1):
		var bolt: Dictionary = plasma_bolts[i]
		var mi: MeshInstance3D = bolt["mi"]
		if not is_instance_valid(mi):
			plasma_bolts.remove_at(i)
			continue
		mi.global_position += (bolt["vel"] as Vector3) * dt
		bolt["life"] = float(bolt["life"]) - dt
		var bp: Vector3 = mi.global_position
		var consumed := false
		for e in enemies:
			if is_instance_valid(e) and e.hp > 0 and bp.distance_to(e.global_position) < hr + 3.0:
				consumed = true
				break
		if not consumed and core != null and bp.distance_to(core.global_position) < 90.0 + hr:   # v0.8:太阳级结构体核心球
			consumed = true
		if not consumed and boss != null and is_instance_valid(boss) and (boss as Object).call("hit_test", bp, hr):   # v3.2 BOSS低模棱柱
			consumed = true
		if consumed:
			_plasma_blast(bp)   # v6.17:命中即爆 —— 半径内全体伤害
		if consumed or float(bolt["life"]) <= 0.0:
			if consumed:
				_explode_small(bp)
			mi.queue_free()
			plasma_bolts.remove_at(i)

func _spread_dir(dir: Vector3, deg: float) -> Vector3:
	if deg <= 0.01:
		return dir
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var u := dir.cross(up).normalized()
	var v := dir.cross(u).normalized()
	var ang := randf() * TAU
	var r := tan(deg_to_rad(deg * 0.5)) * sqrt(randf())
	return (dir + u * (cos(ang) * r) + v * (sin(ang) * r)).normalized()

func _add_heat(amount: float) -> void:
	if not _b("heat", "enabled"):
		return   # v0.8:过热系统整体关闭([heat] enabled=0) —— 雷霆战机式无限连射
	if overheated:
		return
	heat = minf(heat + amount, _b("heat", "max"))
	if heat >= _b("heat", "max") - 0.01:
		overheated = true
		_play_sfx("overheat", -6.0)
		_feed("武器过热 — 排热锁定!")
		vignette.color = Color(1.0, 0.45, 0.1, 0.30)

func _damage_enemy(e, dmg: float) -> void:
	e.hp -= int(round(dmg))
	hitmark_ttl = 0.12
	_play_sfx("hit_enemy", -10.0, randf_range(0.9, 1.1))
	_hit_sparks(e.global_position, Color(1.0, 0.8, 0.4))
	if e.hp <= 0:
		_explode(e.global_position)
		_play_sfx("explode_big", -2.0, randf_range(0.92, 1.08))
		_feed("击落 +%d" % _bi("enemy", "kill_score"))
		score += _bi("enemy", "kill_score")
		kills += 1
		total_kills += 1
		parts += _bi("enemy", "kill_parts")
		enemies.erase(e)
		e.queue_free()
		if enemies.is_empty():
			wave_clear_ttl = 3.0

func _damage_core(dmg: float) -> void:
	hitmark_ttl = 0.12
	_hit_sparks(core.global_position, Color(0.5, 1.0, 0.9))
	if level <= 2:
		return   # v7.1:L1/L2 虫洞入口不可破坏 —— 只能飞入球体内部通关
	core_hp -= int(round(dmg))
	if core_hp <= 0:
		_level_clear()

func _explode_small(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 28
	p.one_shot = true
	p.lifetime = 0.4
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 22.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.8
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, 0.5)
	p.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.7, 0.3)
	p.material_override = m
	add_child(p)
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)

# ==================== 火控:火控锥目标选择 + 提前量解算 ====================
func _update_fire_control(_dt: float) -> void:
	# v6.16:自动锁敌全部移除 —— 不选目标、无锥判定、无自瞄、无锁定音
	# 武器只沿准星(_aim_dir)直线开火, 打中什么算什么; HUD 锁定框随之消失
	lock_valid = false
	lock_ready = false
	lock_in_range = false
	lock_point = Vector3.ZERO
	lock_direct = Vector3.ZERO
	lock_target = null
	lock_is_core = false

func _intercept(shooter: Vector3, target: Vector3, tvel: Vector3, pspeed: float) -> Vector3:
	# 提前量:迭代求拦截点 t = |aim-P|/v,三次迭代收敛(实体弹用;机炮 hitscan 无需提前量)
	var t := shooter.distance_to(target) / pspeed
	var aim := target
	for k in 3:
		aim = target + tvel * t
		t = shooter.distance_to(aim) / pspeed
	return aim

# ==================== 自动化验收(-- --autotest)====================
func _spread_unlocked() -> bool:
	return demo_weapons or level >= _bi("weapon_spread", "unlock_level")

func _laser_unlocked() -> bool:
	return demo_weapons or level >= _bi("weapon_laser", "unlock_level")

func _fov() -> float:
	# v0.7.1:相机视场角数据表驱动 —— 缩小 fov=拉近/放大世界观感(本体与地球的比例观感随之放大)
	return clampf(_b("camera", "fov") if BAL.has("camera") else 70.0, 20.0, 120.0)

func _supply_enter(from_station: bool = false) -> void:
	# v0.8:进入高斯结构体补给舱 —— HP 修复 + 机体适配(视角放大模拟机体缩小) + 倒计时
	phase = 5
	supply_state = 2
	supply_t = 8.0
	hp = hp_max
	var bounty := 30 + 10 * level   # v0.8:核心赏金(设计稿经济)
	parts += bounty
	_feed("补给舱接入 — 核心赏金 +%d" % bounty)
	for b in enemy_bolts:
		(b["mi"] as MeshInstance3D).queue_free()
	enemy_bolts.clear()
	# v3.1 停靠小飞机已移除(中转站自身即模型); 保留灯光氛围
	var center: Vector3 = station.global_position if from_station and station != null and is_instance_valid(station) else (core.global_position if core != null and is_instance_valid(core) else cam.global_position)
	var lt := OmniLight3D.new()
	lt.light_color = Color(0.5, 0.95, 1.0)
	lt.omni_range = 90.0
	lt.light_energy = 1.6
	lt.position = center
	add_child(lt)
	supply_props.append(lt)
	_play_sfx("gate", -4.0, 1.3)
	_feed("机体适配 2m→0.8m 级 — HP 修复 100% — 补给倒计时 8s")

func _supply_exit() -> void:
	# v0.8:补给完成 → 弹出舱外,回到结算/升级阶段
	phase = 2
	supply_state = 0
	fov_mul = 1.0
	if core != null and is_instance_valid(core):
		cam.global_position = core.global_position + Vector3(0, 60, 520)
		core.visible = false
		core = null
	if gate != null:
		gate.visible = false
		gate.scale = Vector3(0.02, 0.02, 0.02)
		gate = null
	marker_valid = false
	for pr in supply_props:
		if is_instance_valid(pr):
			pr.queue_free()
	supply_props.clear()
	_feed("补给完成!— [1]火力 [2]装甲 [3]引擎 后进入下一关")

var normal_t := 0.0
var _normal_shots := 0

func _capture_named(nm: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/%s.png" % nm)
	print("NORM SHOT saved %s (t=%.0f)" % [nm, normal_t])
	if _whale != null and is_instance_valid(_whale):
		var wpp: Vector3 = _whale.current_pos()
		var sp2: Vector2 = cam.unproject_position(wpp)
		var dist2: float = cam.global_position.distance_to(wpp)
		var px2: Color = img.get_pixel(clampi(int(sp2.x), 0, img.get_width() - 1), clampi(int(sp2.y), 0, img.get_height() - 1))
		print("NORMDIAG %s screen=(%.0f,%.0f) dist=%.0f px=(%.2f,%.2f,%.2f) whale_visible=%s" % [nm, sp2.x, sp2.y, dist2, px2.r, px2.g, px2.b, str(_whale.visible)])

func _capture_game_shots() -> void:
	# v0.7:游戏内实拍(隐藏窗口渲染) —— 证据:敌机=高斯外观 + crowd 编队
	var idx := int(autotest_t) / 10
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/game_t%02d.png" % idx)
	print("GAME SHOT saved game_t%02d" % idx)

func autotest_tick(dt: float) -> void:
	autotest_t += dt
	if hp < 40:
		hp = hp_max  # 冒烟保护:确保流程走完(非平衡性测试)
	var steer := Vector3.ZERO
	var has_steer := false
	if (phase == 1 or phase == 4) and core != null:
		steer = core.global_position  # 阶段1/返航 无条件朝核心(与锁定解耦,防死锁)
		has_steer = true
	elif lock_valid:
		steer = lock_point
		has_steer = true
	else:
		var nd := 1e9  # 无锁定时朝最近敌机(测试导航兜底)
		for e2 in enemies:
			if is_instance_valid(e2) and e2.hp > 0:
				var dd: float = cam.global_position.distance_to(e2.global_position)
				if dd < nd:
					nd = dd
					steer = e2.global_position
					has_steer = true
	# [仅 --autotest 验证进程] 自动瞄准转向 —— 正常游戏永不执行; 禁止在玩家在场时启动 autotest 窗口
	if has_steer and autotest:
		var d := (steer - cam.global_position).normalized()
		_yaw = lerp_angle(_yaw, atan2(-d.x, -d.z), clampf(dt * 3.0, 0.0, 1.0))
		_pitch = lerp_angle(_pitch, asin(clampf(d.y, -1.0, 1.0)), clampf(dt * 3.0, 0.0, 1.0))
	if int(autotest_t) % 10 == 0 and autotest_t - autotest_last_print >= 1.0:
		autotest_last_print = autotest_t
		var sdesc := ""
		for s in streams:
			if is_instance_valid(s):
				sdesc += "%s:%s×%d " % [s.type_id, Crowd.Stream.behavior_name(s.behavior), s.alive_count()]
		var core_d := int(core.global_position.distance_to(cam.global_position)) if core != null else -1
		var vram: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
		var vram_tex: float = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
		var cp := cam.global_position
		print("AUTOTEST t=%.0f phase=%d kills=%d/%d hp=%d enemies=%d core_d=%dm pos=(%.0f,%.0f,%.0f) mf=%s vram=%.0fMB(tex %.0fMB) fps=%d streams=[%s]" % [autotest_t, phase, kills, quota, hp, enemies.size(), core_d, cp.x, cp.y, cp.z, str(_mouse_free), vram, vram_tex, Engine.get_frames_per_second(), sdesc.strip_edges()])
		if shots_mode and (int(autotest_t) <= 50 or (int(autotest_t) >= 95 and int(autotest_t) <= 125) or (int(autotest_t) >= 11 and int(autotest_t) <= 19)):
			_capture_game_shots()
	if phase == 2:
		# v7.0:结算不退出 —— 买得起就强化, 买不起直接跃迁; 三关全通后统一 PASS
		if parts >= _bi("economy", "upgrade_cost"):
			parts -= _bi("economy", "upgrade_cost")
			dmg_mult += _b("economy", "dmg_upgrade")
			_next_level()
		else:
			_next_level()
		print("AUTOTEST 跃迁第%d关 t=%.1f" % [level, autotest_t])
		return
	if phase == 7:
		print("AUTOTEST PASS t=%.1f (三关demo全流程: L1歼灭→虫洞结算 → L2保卫+援军剧情 → L3 BOSS+周期支援激光 → 星鲸终局+鲸歌+剧情对话) 总击毁=%d" % [autotest_t, total_kills])
		get_tree().quit()
		return
	if autotest_t > 420.0:
		print("AUTOTEST TIMEOUT phase=%d level=%d kills=%d/%d hp=%d enemies=%d support=%s" % [phase, level, kills, quota, hp, enemies.size(), str(_support_online)])
		get_tree().quit(1)

func _explode(pos: Vector3) -> void:
	_fx_play("blast", pos, 1.0)   # v0.8:高斯爆炸火球(12帧序列)
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 42
	p.one_shot = true
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 26.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 2.2
	var qm := QuadMesh.new()
	qm.size = Vector2(0.8, 0.8)
	p.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.6, 0.2)
	p.material_override = m
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)

func _add_tracer(a: Vector3, b: Vector3, col: Color) -> void:
	# v0.9:shader 曳光 —— 亮头渐尾能量 streak(弹头白热)+ 残影淡出;替代 v0.3.2 平色盒
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var len := maxf(a.distance_to(b), 0.5)
	bm.size = Vector3(0.16, 0.16, len)
	mi.mesh = bm
	var m := ShaderMaterial.new()
	m.shader = _get_shader("tracer")
	m.set_shader_parameter("tint", Color(col.r, col.g, col.b, 1.0))
	m.set_shader_parameter("length_m", len)
	m.set_shader_parameter("power", 1.0)
	m.set_shader_parameter("time", fx_time)
	mi.material_override = m
	mi.position = (a + b) * 0.5
	add_child(mi)
	mi.look_at(b, Vector3.UP)
	tracers.append({ "mi": mi, "ttl": 0.16, "dur": 0.16 })

func _build_muzzle() -> void:
	# 枪口闪光:单个复用实例(四边形 + 点光)
	_muzzle_mi = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.7, 1.7)
	_muzzle_mi.mesh = q
	var m := ShaderMaterial.new()   # v0.9:换 fx_flare shader(径向辉光+星芒)
	m.shader = _get_shader("fx_flare")
	m.set_shader_parameter("tint", Color(1.0, 0.9, 0.7))
	m.set_shader_parameter("intensity", 1.1)
	m.set_shader_parameter("spike", 1.0)
	m.set_shader_parameter("ring", 0.0)
	m.set_shader_parameter("progress", 1.0)
	_muzzle_mi.material_override = m
	_muzzle_mi.visible = false
	add_child(_muzzle_mi)
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.omni_range = 30.0
	_muzzle_light.visible = false
	add_child(_muzzle_light)

func _muzzle_flash(pos: Vector3, big: bool) -> void:
	if _muzzle_mi == null or _b("fx", "muzzle_flash") < 0.5:
		return  # 大屏频闪来源(贴脸加色大四边形+30m点光),默认关,fx.muzzle_flash=1 可开
	_muzzle_mi.position = pos
	_muzzle_mi.visible = true
	_muzzle_light.position = pos
	_muzzle_light.visible = true
	_muzzle_light.light_energy = 1.6 if big else 0.9
	_muzzle_light.light_color = Color(1.0, 0.6, 0.3) if big else Color(0.7, 1.0, 0.9)
	_muzzle_ttl = 0.04 if big else 0.028

func _hit_sparks(pos: Vector3, col: Color) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 12
	p.one_shot = true
	p.lifetime = 0.25
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 20.0
	p.scale_amount_min = 0.2
	p.scale_amount_max = 0.7
	p.mesh = _spark_mesh_res()
	p.material_override = _spark_mat_res(col)   # 共享(按色缓存): 命中峰值不再每次编译材质
	add_child(p)
	p.emitting = true
	get_tree().create_timer(0.5).timeout.connect(p.queue_free)

func _process(dt: float) -> void:
	# v0.9.7: 预热节点回收 + 多线程目标扫描调度
	if _warmup_frames > 0:
		_warmup_frames -= 1
		if _warmup_frames == 0:
			for n in _warmup_nodes:
				if is_instance_valid(n):
					(n as Node).queue_free()
			_warmup_nodes.clear()
	_rt_cd -= dt
	if _rt_cd <= 0.0:
		_rt_cd = _rt_every
		_retarget_kick()
	if _rt_busy and _rt_task_id >= 0 and WorkerThreadPool.is_task_completed(_rt_task_id):
		WorkerThreadPool.wait_for_task_completion(_rt_task_id)
		_rt_task_id = -1
		_rt_busy = false
	if not stress:
		_frame_ev = {}
	if stress:
		var now_us := Time.get_ticks_usec()
		var frame_us := 0
		if _last_us > 0:
			frame_us = now_us - _last_us
			_worst_frame_us = maxi(_worst_frame_us, frame_us)   # 帧间隔即帧耗时: 抓单帧尖峰
			if frame_us > _hitch_thr_us:
				print("[HITCH] %dms ev=%s" % [frame_us / 1000, str(_frame_ev)])   # v0.9.7:尖峰归因(当帧事件)
		_last_us = now_us
		_frame_ev = {}   # v0.9.7:每帧重置归因计数
		_fps_n += 1
		_fps_t += dt
		if _fps_t >= 1.0:
			_fps_avg = float(_fps_n) / _fps_t
			_fps_n = 0
			_fps_t = 0.0
			if _fps_label != null:
				_fps_label.text = "FPS %d | 敌 %d" % [int(_fps_avg), enemies.size()]
			_stress_log += 1
			if _stress_log >= 3:
				_stress_log = 0
				print("[STRESS] fps=%d worst=%dms enemies=%d bolts=%d wing=%d fbolts=%d streams=%d phase=%d kills=%d/%d poolE=%d poolW=%d poolFx=%d rt=%s" % [int(_fps_avg), _worst_frame_us / 1000, enemies.size(), enemy_bolts.size(), wingmen.size(), friendly_bolts.size(), streams.size(), phase, kills, quota, _bolt_pool_e.size(), _bolt_pool_w.size(), _fx_node_pool.size(), ("busy" if _rt_busy else "ok")])
				_worst_frame_us = 0
	if sunprobe and not sunprobe_started and Time.get_ticks_msec() > 2500:
		sunprobe_started = true
		_sunprobe_run()
	_cmd_timer += dt
	if _cmd_timer >= 0.25:
		_cmd_timer = 0.0
		_poll_cmd_inbox()
	if not ephem_planets.is_empty():
		_update_ephem_solar(dt)   # v0.9: 星历逐帧 —— 公转位置/GMST 自转/月球/光照方向
	# v3.0 道具逐帧: 相阵激光伤害 / BOSS 武器 / 中转站停靠与标记
	if radar_ring != null and is_instance_valid(radar_ring):
		# v4.0 相阵沿环地轨道运行(绕地球, 周期~5分钟) + 整阵缓慢自转使天线扫描方位随轨道变化
		var _oa: float = Time.get_ticks_msec() * 0.000021
		(radar_ring as Node3D).global_position = earth_pos + Vector3(cos(_oa) * 1500.0, 320.0, sin(_oa) * 1500.0)
		var _bd: float = (radar_ring as Object).call("beam_hit", cam.global_position, dt)
		if _bd > 0.0:
			_prop_damage(_bd, cam.global_position - (radar_ring as Node3D).global_transform.basis.z * 50.0)
		(radar_ring as Object).call("tick", dt, cam.global_position)
	_station_defense(dt)
	if level == 2 and phase == 0:
		if not _reinf_done and kills >= int(quota * 0.5):
			_reinf_done = true
			_l2_reinforce_cutscene()
		_raid_cd -= dt
		if _raid_cd <= 0.0:
			_raid_cd = _b("demo", "raid_interval")
			if radar_ring != null and is_instance_valid(radar_ring):
				var rhp: float = (radar_ring as Object).get("hp")
				var rhmax: float = (radar_ring as Object).get("hp_max")
				var frac: float = clampf(rhp / maxf(rhmax, 1.0), 0.0, 1.0)
				(radar_ring as Object).call("take_damage", _b("demo", "raid_base") + _b("demo", "raid_per_enemy") * enemies.size())
				_hit_sparks((radar_ring as Node3D).global_position, Color(1.0, 0.4, 0.3))
				_play_sfx("explode", -8.0, 0.8)
				_feed("⚠ 雷达阵遭空袭! 结构 %d%%" % [int(100.0 * frac)])
				# v7.0:血量阈值 EVA 自动警告(60%/30% 各一次)
				for th in [0.6, 0.3]:
					if frac <= th and not _fac_warned.has(th):
						_fac_warned[th] = true
						_eva_announce_key("fac_60" if th > 0.45 else "fac_30", true)
		if radar_ring == null or not is_instance_valid(radar_ring):
			_story_clear()
			hp = 0
			dead = true
			phase = 3
			_feed("雷达阵被摧毁 — 任务失败! 按 R 重试本关")
			_eva_announce_key("fail", true)
	# v7.0 鲸歌铺垫:开局即混入 —— 远处微弱鲸歌周期性浮现(终局前低吟, 终局后洪亮)
	_whale_song_cd -= dt
	if _whale_song_cd <= 0.0:
		if _final_whale:
			_whale_song_cd = 42.0
			_play_sfx("whale_distant", -10.0, randf_range(0.92, 1.08))
		elif _song_foreshadow and phase < 3:
			_whale_song_cd = randf_range(_b("demo", "song_cd_min"), _b("demo", "song_cd_max"))
			_play_sfx("whale_distant", -16.0, randf_range(0.88, 1.02))
		else:
			_whale_song_cd = 20.0
	# v7.0 L3 轨道炮台支援倒计时(打到一定时间后激光周期性参战)
	if level == 3 and not _support_online and (phase == 0 or phase == 1) and not dead:
		_support_t -= dt
		if _support_t <= 0.0:
			_support_online = true
			_eva_announce_key("l3_support", true)
			_feed("⚡ 轨道炮台火力支援上线 — 周期性巨型光束横扫敌阵!")
	_story_tick(dt)
	_music_tick(dt)
	_ui_tick(dt)
	_perf_t += dt   # v7.8:帧率骤降监控(0.5s 采样)
	if _perf_t >= 0.5:
		_perf_t = 0.0
		var fps_now := float(Engine.get_frames_per_second())
		if _perf_fps < 1.0:
			_perf_fps = fps_now
		if fps_now < 55.0 and fps_now < _perf_fps * 0.65:
			print("[PERF] fps骤降 %.0f->%.0f | level=%d phase=%d enemies=%d ebolt=%d fbolt=%d boss=%s whale=%s" % [_perf_fps, fps_now, level, phase, enemies.size(), enemy_bolts.size(), friendly_bolts.size(), str(boss != null and is_instance_valid(boss)), str(_whale != null and is_instance_valid(_whale))])
			_perf_feed_cd -= 0.5
			if _perf_feed_cd <= 0.0:
				_perf_feed_cd = 8.0
				_feed("⚠ 性能:帧率骤降 %.0f→%.0f(上下文见日志[PERF])" % [_perf_fps, fps_now])
		_perf_fps = lerpf(_perf_fps, fps_now, 0.4)
	if _worm_t >= 0.0:
		_worm_t += dt
		var wa: float = _worm_t / 1.4
		_flash_rect.color = Color(0.62, 0.95, 1.0, clampf(wa, 0.0, 1.0))
		if _worm_t >= 1.4:
			_settlement_open()
	if boss != null:
		if is_instance_valid(boss) and core != null and is_instance_valid(core):
			var _bdmg: float = (boss as Object).call("tick", dt, cam.global_position, clampf(core_hp / core_hp_max, 0.0, 1.0))
			if _bdmg > 0.0:
				_prop_damage(_bdmg, boss.global_position)
		elif is_instance_valid(boss):
			(boss as Object).call("die")
			boss = null
	if _prop_sun != null and is_instance_valid(_prop_sun):
		_prop_sun.look_at(earth_pos, Vector3.UP)   # 太阳(原点)→地球方向
	if phase == 4 and station != null and is_instance_valid(station):
		marker_valid = true
		marker_pos = station.global_position   # v7.0:中转站仅作导航标记, 跃迁入口=核心(下同)
	for it in self_rot:
		if is_instance_valid(it[0]):
			var n_r := it[0] as Node3D
			var sp_hit := {}
			for sp in splat_planets:
				if sp["mesh"] == n_r:
					sp_hit = sp
					break
			if not sp_hit.is_empty():
				var rot_a: float = dt * it[1]	# v6.12f: 烤死光照行星只绕太阳轴(本地Z)自转, 三体同步保经度
				n_r.rotate(Vector3(0.0, 0.0, 1.0), rot_a)
				(sp_hit["near"] as Node3D).rotate(Vector3(0.0, 0.0, 1.0), rot_a)
				(sp_hit["far"] as Node3D).rotate(Vector3(0.0, 0.0, 1.0), rot_a)
			else:
				n_r.rotate_y(dt * it[1])
				if grid_twins.has(n_r):	# v6.12f: 三级网格同步自转
					for t in grid_twins[n_r]:
						if is_instance_valid(t):
							(t as Node3D).rotation = n_r.rotation
	for pv in moon_pivots:
		if is_instance_valid(pv):
			(pv as Node3D).rotate_y(dt * 0.05)
	if not planet_lods.is_empty():
		_update_splat_lod()
	ship_light_cd -= dt
	if ship_light_cd <= 0.0:
		ship_light_cd = 0.25
		_update_ship_lighting()
	fire_cd = maxf(fire_cd - dt, 0.0)
	hitmark_ttl = maxf(hitmark_ttl - dt, 0.0)
	plasma_cd = maxf(plasma_cd - dt, 0.0)
	spread_cd = maxf(spread_cd - dt, 0.0)
	bolt_cd = maxf(bolt_cd - dt, 0.0)   # v0.8:散弹炮装填
	bloom = maxf(bloom - _b("cannon", "bloom_decay") * dt, 0.0)
	heat = maxf(heat - _b("heat", "dissipate") * dt, 0.0)
	# v7.3:取消自动回血 —— 结构完整度只在结算/购买装甲时修复
	if overheated and heat <= _b("heat", "resume_below"):
		overheated = false
		_feed("排热完成 — 武器在线")
	var hq := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.basis.z * 800.0, 2)
	hq.collide_with_areas = true
	var hhit: Dictionary = get_world_3d().direct_space_state.intersect_ray(hq)
	var hc: Object = hhit.get("collider")
	hover_enemy = hc if hc is Enemy else null   # v0.8:准星压到才算"锁定"敌机
	_tick_bolts(dt)
	_tick_missiles(dt)   # v0.9.2:追踪导弹制导/命中/自毁
	_tick_enemy_bolts(dt)
	_tick_wingmen(dt)
	_tick_friendly_bolts(dt)
	_tick_streams(dt)
	_tick_spawn_q(dt)   # v7.9:渐次出厂
	if phase == 0:
		level_timer -= dt
		mission_time += dt
		if kills >= quota or level_timer <= 0.0:
			_open_gate()
	if phase <= 1:   # v6.14:核心被破坏前,敌机从核心持续涌出
		spawn_cd -= dt
		if spawn_cd <= 0.0:
			spawn_cd = _b("enemy", "spawn_interval")
			if enemies.size() + _bi("crowd", "members") <= _bi("enemy", "max_alive"):
				_spawn_stream()   # v0.7:持续补充也按"流"为单位(整流计入上限)
	# ===== v7.0 返航跃迁:phase4 接近中转站核心 → phase6 虫洞过渡 → phase2 结算 =====
	if phase == 4 and core != null and is_instance_valid(core):
		if cam.global_position.distance_to(core.global_position) < 140.0:   # v7.1:飞入虫洞高斯球体内部=通关判定
			_wormhole_jump()
	if phase == 4:
		fov_mul = lerpf(fov_mul, 1.0, clampf(dt * 2.5, 0.0, 1.0))  # v7.1:返航/虫洞不再改变视角(原机体缩小模拟已删)
	elif phase == 6:
		pass   # v7.1:虫洞吸入感(FOV 拉伸=机体缩小错觉)代码已删除
	else:
		fov_mul = lerpf(fov_mul, 1.0, clampf(dt * 2.5, 0.0, 1.0))
	cam.fov = _fov() * fov_mul
	_tick_lod_fades(dt)
	_tick_fx(dt)
	_tick_l0_stream(dt)
	if shots_mode and not autotest:   # v0.9:普通模式定时截屏(星鲸实拍)
		normal_t += dt
		var nn := int(normal_t / 12.0)
		if nn > _normal_shots and _normal_shots < 8:
			_normal_shots = nn
			_capture_named("norm_%02d" % nn)
	if autotest:
		autotest_tick(dt)
	if (not _mouse_free or autotest) and not dead:   # v0.8:autotest 对杂散按键免疫(隐藏窗口曾收到 ESC 导致停滞)
		_fly(dt)
		_update_fire_control(dt)
		if not overheated:
			if auto_fire:
				_fire_cannon()
				_fire_bolts()   # v7.3:弹体炮
				_fire_missile()   # v0.9.2:追踪导弹(有目标才放;等离子/散弹/激光已关闭)
			else:
				if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(KEY_SPACE):
					_fire_cannon()
					_fire_bolts()   # v7.3:弹体炮
				if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
					_fire_missile()   # v0.9.2:RMB = 追踪导弹
		_tick_laser(dt)   # v0.8:超级激光炮独立节奏(充能→照射循环)
		if not dead and mega_t < 0.0 and mega_cd > 0.0:
			mega_cd = maxf(mega_cd - dt, 0.0)
			if mega_cd <= 0.0:
				_feed("MEGA READY [X]")
				_play_sfx("lock", -2.0)
		if mega_t >= 0.0:
			_mega_tick(dt)
	fx_time += dt   # v0.9:特效统一时钟(光束能量流/光晕呼吸)
	for i in range(tracers.size() - 1, -1, -1):
		tracers[i]["ttl"] -= dt
		if tracers[i]["ttl"] <= 0.0:
			(tracers[i]["mi"] as Node).queue_free()
			tracers.remove_at(i)
		else:
			var tm := (tracers[i]["mi"] as MeshInstance3D).material_override as ShaderMaterial
			tm.set_shader_parameter("power", clampf(float(tracers[i]["ttl"]) / 0.16, 0.0, 1.0))   # v0.9:残影淡出
	# v6.14:补波逻辑移除 —— 连续刷新取代固定波次
	vignette.color.a = maxf(vignette.color.a - dt * 1.2, 0.0)
	shake = maxf(shake - dt * 3.0, 0.0)
	if _muzzle_ttl > 0.0:
		_muzzle_ttl -= dt
		if _muzzle_ttl <= 0.0:
			_muzzle_mi.visible = false
			_muzzle_light.visible = false
	if shake > 0.0 and not dead:
		cam.rotation.x += randf_range(-1.0, 1.0) * 0.006 * shake
		cam.rotation.y += randf_range(-1.0, 1.0) * 0.006 * shake
		cam.rotation.z += randf_range(-1.0, 1.0) * 0.004 * shake
	hud.queue_redraw()
	var ph: String
	match phase:
		0: ph = "生存 %ds" % int(ceil(maxf(level_timer, 0.0)))
		1: ph = "摧毁BOSS核心!"
		2: ph = "结算 — 能力树[1-3] 改造[4-6] / [Enter]跃迁"
		3: ph = "失败 — 按 R 重试"
		4: ph = "返航!飞入虫洞球体内部即通关"
		6: ph = "虫洞跃迁中…"
		7: ph = "全任务完成"
		_: ph = ""
	pass   # v0.9.9:左上角状态行下线(出戏)

func _feed(s: String) -> void:
	_eva_say(s)   # v0.9.10: EVA voice broadcast takes over (print for now, TTS later); v0.9.9 text feed removed

func _aim_radius() -> float:
	var vp := get_viewport().get_visible_rect().size
	return minf(vp.x, vp.y) * 0.30

func _steer_follow(dt: float) -> void:
	var r := _aim_radius()
	if r <= 1.0:
		return
	var off := aim / r
	if off.length() > 0.12:
		var t := clampf((off.length() - 0.12) / 0.88, 0.0, 1.0)
		var rate := off.normalized() * t * 2.4 * dt
		_yaw -= rate.x
		_pitch = clampf(_pitch - rate.y, -1.45, 1.45)

func _aim_dir() -> Vector3:
	var vp := get_viewport().get_visible_rect().size
	if mode_follow:
		return cam.project_ray_normal(vp * 0.5 + aim)
	return cam.project_ray_normal(vp * 0.5)

func _fly(dt: float) -> void:
	cam.rotation = Vector3(_pitch, _yaw, 0.0)
	ap_hold = maxf(ap_hold - dt, 0.0)   # 出生宽限倒计时(autotest 与手动输入不受影响)
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): move -= cam.basis.z
	if Input.is_physical_key_pressed(KEY_S): move += cam.basis.z
	if Input.is_physical_key_pressed(KEY_A): move -= cam.basis.x
	if Input.is_physical_key_pressed(KEY_D): move += cam.basis.x
	if Input.is_physical_key_pressed(KEY_E): move += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q): move -= Vector3.UP
	var boost := Input.is_physical_key_pressed(KEY_SHIFT) or autotest
	var max_v := (_b("player", "speed_boost") if boost else _b("player", "speed_base")) * speed_mult
	if autotest:
		move -= cam.basis.z
		vel = move.normalized() * minf(max_v, 60.0)  # 自动驾驶:保持旧匀速节奏,不做惯性
	elif move != Vector3.ZERO:
		# 手动输入优先:推力 → 速度线性增长(太空无阻力,松开方向键速度保持)
		var accel := (_b("player", "accel_boost") if boost else _b("player", "accel_base")) * speed_mult
		vel += move.normalized() * accel * dt
		if vel.length() > max_v:
			vel = vel.normalized() * max_v
	elif autopilot and not dead and (autotest or ap_hold <= 0.0):
		_ap_fly(dt)  # 直接锁定:不碰摇杆就自动飞向最近敌机(出生 4s 宽限内不接管)
	else:
		# 无推力:速度保持;仅当超过当前档位上限(如松开 Shift)时线性回落
		var s := vel.length()
		if s > max_v:
			vel = vel.normalized() * maxf(s - 60.0 * dt, max_v)
	cam.position += vel * dt

# 直接锁定导航:选最近敌机(阶段1=核心),机头平滑咬住(30°火控锥自然接管开火),速度伺服逼近至 60m 悬停缠斗
func _ap_fly(dt: float) -> void:
	var tp := Vector3.ZERO
	var found := false
	# v0.6:阶段1 仅当 gate 近于 1.2km(或敌已清场/autotest)才咬核心 —— 否则继续咬最近敌机,视角不再被 3.5km 外的核心拽走
	if phase == 1 and is_instance_valid(gate) and (cam.global_position.distance_to(gate.global_position) < 1200.0 or autotest or enemies.is_empty()):
		tp = gate.global_position
		found = true
	else:
		var bd := INF
		for e in enemies:
			if not is_instance_valid(e) or e.hp <= 0:
				continue
			var d: float = cam.global_position.distance_to(e.global_position)
			if d < bd:
				bd = d
				tp = e.global_position
				found = true
	if not found:
		return
	var to := tp - cam.global_position
	var d := to.length()
	var dir := to / maxf(d, 0.001)
	# v6.15:绝对不动玩家视角 —— 导航只控位移, _pitch/_yaw 唯一来源是鼠标输入
	# (旧的"自动锁定拽视角"已按玩家要求移除)
	var max_v := _b("player", "speed_boost") * speed_mult
	var v_des := dir * clampf((d - 60.0) * 1.2, 0.0, minf(max_v, 220.0))
	vel = vel.lerp(v_des, minf(dt * 2.0, 1.0))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_V and not event.echo:
		if event.pressed:
			_voice_start()
		else:
			_voice_stop()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if _mouse_free: get_tree().quit()
			else:
				_mouse_free = true
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_R and phase == 3:
			_retry_level()
		elif event.keycode == KEY_R and phase != 3:
			get_tree().reload_current_scene()
		elif event.keycode == KEY_F:
			auto_fire = not auto_fire
			_feed("火控全自动:%s" % ("开 — 锥内自瞄自射,无需鼠标" if auto_fire else "关 — LMB 激光 / RMB 导弹"))
		elif event.keycode == KEY_T:
			autopilot = not autopilot
			_feed("直接锁定导航:%s" % ("开 — 自动飞向目标(视角完全手动)" if autopilot else "关 — 手动惯性飞行"))
		elif event.keycode == KEY_G:
			god_mode = not god_mode
			_feed("免伤:%s" % ("开" if god_mode else "关(20/s 回血仍生效)"))
		elif event.keycode == KEY_X:
			_mega_fire()   # v7.4 mega beam
		elif _story_on and event.keycode in [KEY_1, KEY_E, KEY_SPACE]:
			_story_advance()   # v7.0:剧情应答/快进
		elif phase == 2 and event.keycode == KEY_ENTER:
			_result_panel.visible = false
			_next_level()   # v7.0:不购买直接跃迁下一关
		elif phase == 2 and event.keycode in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]:
			_settlement_buy(int(event.keycode) - int(KEY_0))   # v7.1:能力树[1-3]/改造[4-6], 可连续购买, Enter 跃迁
	elif event is InputEventMouseButton and event.pressed and _story_on:
		_story_advance()   # v7.0:点击应答剧情
	elif event is InputEventMouseButton and event.pressed and _mouse_free and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_free = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and not _mouse_free:
		_yaw -= event.relative.x * 0.0022
		_pitch = clampf(_pitch - event.relative.y * 0.0022, -1.45, 1.45)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HUDCanvas.new()
	hud.root = self
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(hud)
	pass   # v0.9.9:左上角 lbl_main/lbl_feed 不再创建
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(1, 0, 0, 0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(vignette)
	vignette.z_index = -1

func _build_story_ui() -> void:
	# v7.0:剧情/结算 UI 层 —— 全屏闪光/字幕条/单选项提示/设施血条/结算面板/通关面板
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(0.62, 0.95, 1.0, 0.0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash_rect)
	# --- 设施血条(L2 保卫战, 顶部居中) ---
	_fac_lbl = Label.new()
	_fac_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_fac_lbl.anchor_left = 0.5
	_fac_lbl.anchor_right = 0.5
	_fac_lbl.offset_left = -260
	_fac_lbl.offset_right = 260
	_fac_lbl.offset_top = 30
	_fac_lbl.offset_bottom = 52
	_fac_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fac_lbl.add_theme_font_size_override("font_size", 15)
	_fac_lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_fac_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_fac_lbl.add_theme_constant_override("shadow_offset_y", 2)
	_fac_lbl.text = "雷达相阵"
	_fac_lbl.visible = false
	layer.add_child(_fac_lbl)
	_fac_bar_bg = ColorRect.new()
	_fac_bar_bg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_fac_bar_bg.anchor_left = 0.5
	_fac_bar_bg.anchor_right = 0.5
	_fac_bar_bg.offset_left = -260
	_fac_bar_bg.offset_right = 260
	_fac_bar_bg.offset_top = 56
	_fac_bar_bg.offset_bottom = 72
	_fac_bar_bg.color = Color(0.05, 0.09, 0.14, 0.78)
	_fac_bar_bg.visible = false
	layer.add_child(_fac_bar_bg)
	_fac_bar = ColorRect.new()
	_fac_bar.color = Color(0.3, 1.0, 0.55)
	_fac_bar.visible = false
	_fac_bar_bg.add_child(_fac_bar)
	# --- v7.7 EVA 应答面板(右侧居中) ---
	_ack_lbl = Label.new()
	_ack_lbl.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_ack_lbl.anchor_left = 1.0
	_ack_lbl.anchor_right = 1.0
	_ack_lbl.offset_left = -460
	_ack_lbl.offset_right = -70
	_ack_lbl.offset_top = 190
	_ack_lbl.offset_bottom = 252
	_ack_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ack_lbl.add_theme_font_size_override("font_size", 24)
	_ack_lbl.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	_ack_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_ack_lbl.add_theme_constant_override("shadow_offset_y", 2)
	_ack_lbl.text = ""
	_ack_lbl.visible = false
	layer.add_child(_ack_lbl)
	# --- BOSS 血条(L3 BOSS战, 顶部居中, v7.1) ---
	_boss_lbl = Label.new()
	_boss_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_lbl.anchor_left = 0.5
	_boss_lbl.anchor_right = 0.5
	_boss_lbl.offset_left = -320
	_boss_lbl.offset_right = 320
	_boss_lbl.offset_top = 26
	_boss_lbl.offset_bottom = 50
	_boss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_lbl.add_theme_font_size_override("font_size", 16)
	_boss_lbl.add_theme_color_override("font_color", Color(1.0, 0.62, 0.66))
	_boss_lbl.add_theme_color_override("font_shadow_color", Color(0.35, 0.0, 0.05, 0.9))
	_boss_lbl.add_theme_constant_override("shadow_offset_y", 2)
	_boss_lbl.text = "⚠ 八棱柱集群 · 湮灭核心"
	_boss_lbl.visible = false
	layer.add_child(_boss_lbl)
	_boss_bar_bg = Panel.new()
	_boss_bar_bg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_bar_bg.anchor_left = 0.5
	_boss_bar_bg.anchor_right = 0.5
	_boss_bar_bg.offset_left = -300
	_boss_bar_bg.offset_right = 300
	_boss_bar_bg.offset_top = 54
	_boss_bar_bg.offset_bottom = 70
	var sbf := StyleBoxFlat.new()
	sbf.bg_color = Color(0.04, 0.05, 0.10, 0.82)
	sbf.border_color = Color(0.90, 0.25, 0.35, 0.85)
	sbf.set_border_width_all(2)
	sbf.set_corner_radius_all(6)
	_boss_bar_bg.add_theme_stylebox_override("panel", sbf)
	_boss_bar_bg.visible = false
	layer.add_child(_boss_bar_bg)
	_boss_bar = ColorRect.new()
	_boss_bar.color = Color(1.0, 0.28, 0.32)
	_boss_bar.position = Vector2(3, 3)
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar_bg.add_child(_boss_bar)
	for i in 9:
		var notch := ColorRect.new()
		notch.color = Color(0, 0, 0, 0.35)
		notch.size = Vector2(2, 12)
		notch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_boss_bar_bg.add_child(notch)
		_boss_notches.append(notch)
	# --- 字幕条(底部居中: 说话人 + 打字机文本 + 选项提示) ---
	_sub_sp = Label.new()
	_sub_sp.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sub_sp.anchor_left = 0.5
	_sub_sp.anchor_right = 0.5
	_sub_sp.anchor_top = 1.0
	_sub_sp.anchor_bottom = 1.0
	_sub_sp.offset_left = -480
	_sub_sp.offset_right = 480
	_sub_sp.offset_top = -186
	_sub_sp.offset_bottom = -162
	_sub_sp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_sp.add_theme_font_size_override("font_size", 16)
	_sub_sp.add_theme_color_override("font_color", Color(0.45, 0.95, 1.0))
	_sub_sp.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_sub_sp.add_theme_constant_override("shadow_offset_y", 2)
	_sub_sp.visible = false
	layer.add_child(_sub_sp)
	_sub_lbl = Label.new()
	_sub_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sub_lbl.anchor_left = 0.5
	_sub_lbl.anchor_right = 0.5
	_sub_lbl.anchor_top = 1.0
	_sub_lbl.anchor_bottom = 1.0
	_sub_lbl.offset_left = -520
	_sub_lbl.offset_right = 520
	_sub_lbl.offset_top = -158
	_sub_lbl.offset_bottom = -96
	_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_lbl.add_theme_font_size_override("font_size", 22)
	_sub_lbl.add_theme_color_override("font_color", Color(0.98, 0.99, 1.0))
	_sub_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_sub_lbl.add_theme_constant_override("shadow_offset_y", 2)
	_sub_lbl.visible = false
	layer.add_child(_sub_lbl)
	# --- 结算面板(虫洞抵达) ---
	_result_panel = PanelContainer.new()
	_result_panel.set_anchors_preset(Control.PRESET_CENTER)
	_result_panel.anchor_left = 0.5
	_result_panel.anchor_right = 0.5
	_result_panel.anchor_top = 0.5
	_result_panel.anchor_bottom = 0.5
	_result_panel.offset_left = -330
	_result_panel.offset_right = 330
	_result_panel.offset_top = -140
	_result_panel.offset_bottom = 140
	_result_panel.visible = false
	var rl := Label.new()
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rl.add_theme_font_size_override("font_size", 19)
	rl.add_theme_color_override("font_color", Color(0.92, 0.98, 1.0))
	_result_panel.add_child(rl)
	_result_lbl = rl
	layer.add_child(_result_panel)
	# --- 通关面板(终局剧情播毕) ---
	_complete_panel = PanelContainer.new()
	_complete_panel.set_anchors_preset(Control.PRESET_CENTER)
	_complete_panel.anchor_left = 0.5
	_complete_panel.anchor_right = 0.5
	_complete_panel.anchor_top = 0.5
	_complete_panel.anchor_bottom = 0.5
	_complete_panel.offset_left = -330
	_complete_panel.offset_right = 330
	_complete_panel.offset_top = -150
	_complete_panel.offset_bottom = 150
	_complete_panel.visible = false
	var cl := Label.new()
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cl.add_theme_font_size_override("font_size", 19)
	cl.add_theme_color_override("font_color", Color(0.98, 0.95, 0.85))
	_complete_panel.add_child(cl)
	_complete_lbl = cl
	layer.add_child(_complete_panel)

func _build_sky() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var smat := ShaderMaterial.new()
	smat.shader = load("res://shaders/dual_panorama_sky.gdshader")
	smat.set_shader_parameter("pan_mosaic", load("res://assets/textures/nasa_sky_panorama_8k.jpg"))
	smat.set_shader_parameter("pan_nasa", load("res://assets/textures/nasa_svs/starmap_2020_4k.exr"))
	smat.set_shader_parameter("nasa_gain", 0.70)   # v6.11:EXR 0.70 + shader 黑电平 0.28(弥漫天光归零、星峰保留)—— 修"全屏白雾+太阳方向过曝亮斑"
	smat.set_shader_parameter("sky_black_point", 0.28)
	smat.set_shader_parameter("sky_knee", 0.90)
	print("SKY v6.11 live: mosaic=%.2f nasa=%.2f black_point=%.2f knee=%.2f | sun albedo HDR 10/9.2/8.2" % [0.50, 0.70, 0.28, 0.90])
	smat.set_shader_parameter("mosaic_gain", 0.50)   # v6.11:配合黑电平(见 dual_panorama_sky.gdshader)—— 巡天图平均亮度~0.47,直接 0.85 增益会把太空渲染成白雾
	sky.sky_material = smat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC   # v6.3:HDR 滚降 —— 修"全屏突变亮光"(EXR 星图×1.3 加在全屏背景,Linear 直切即爆白)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _build_star_layers() -> void:
	_add_star_layer(1500, 4.5e5, 4.9e5, 25.0, 62.0, 0.95)
	_add_star_layer(600, 4.2e5, 4.6e5, 12.0, 30.0, 1.0)
	_add_star_layer(350, 25.0, 90.0, 0.15, 0.4, 0.5)  # 近景尘埃层:贴相机,不随尺度放大

func _add_star_layer(count: int, r_min: float, r_max: float, s_min: float, s_max: float, alpha: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260909
	var palette := [Color(0.72, 0.78, 1.0), Color(1, 1, 1), Color(1, 0.93, 0.78), Color(1, 0.75, 0.55), Color(1, 0.55, 0.45)]
	for i in count:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if dir.length() < 0.001: dir = Vector3.RIGHT
		dir = dir.normalized()
		var pos := dir * rng.randf_range(r_min, r_max)
		var s := rng.randf_range(s_min, s_max)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), pos))
		var c: Color = palette[rng.randi_range(0, palette.size() - 1)]
		c.a = alpha * rng.randf_range(0.5, 1.0)
		mm.set_instance_color(i, c)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/star_billboard.gdshader")
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _build_nebulae() -> void:
	var defs := [
		["res://assets/textures/nebula/PIA03096.jpg", Vector3(-0.45, 0.12, -0.88), 4.6e5, 2.0e5, Color(0.8, 0.9, 1.0), 0.5],
		["res://assets/textures/nebula/carina_nebula.jpg", Vector3(-0.2, -0.35, -0.91), 4.8e5, 2.2e5, Color(1.0, 0.72, 0.85), 0.55],
		["res://assets/textures/nebula/PIA25434.jpg", Vector3(0.62, 0.25, -0.74), 4.4e5, 1.9e5, Color(0.8, 0.9, 1.0), 0.45],
	]
	for d in defs:
		_add_nebula(d[0], d[1].normalized() * d[2], d[3], d[4], d[5])

func _add_nebula(tex_path: String, pos: Vector3, size: float, tint: Color, strength: float) -> void:
	var t: Texture2D = load(tex_path)
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	var aspect := t.get_size().x / maxf(t.get_size().y, 1.0)
	quad.size = Vector2(size * aspect, size)
	mi.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/nebula_billboard.gdshader")
	mat.set_shader_parameter("tex", t)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("strength", strength)
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# ================= 太阳系 =================
const Ephem := preload("res://solar_ephem.gd")   # v0.9 星历核心(headless 下全局类缓存不可靠, 显式预载)
const Props := preload("res://solar_props.gd")   # v3.0 场景道具(中转站/相阵/BOSS)
const P_TEX := "res://assets/textures/planets/"

func _build_solar_system() -> void:
	# ===== 尺度 v4:统一线性比例,半径/距离同乘 SOLAR_SCALE —— 行星间比例=真实比例 =====
	# 太阳真实半径 6.96e8 m ×1e-5 = 6960m(不再特例,太阳/地球 = 109 与真实一致)
	var sun := _make_planet(P_TEX + "sun.jpg", SUN_R, Vector3.ZERO, true)   # 自发光太阳盘;不再叠加光晕公告板(v6.11:150km 加法光晕在镜头对日/微偏角时产生极亮亮斑与突变,已移除)
	add_child(sun)
	# v0.9 def: [星历名, 贴图, Re, 装饰自转速度] —— 位置/轨道平面/椭圆形状全部由星历解算
	# 公转 = Standish J2000 根数开普勒解(真实偏心率/倾角/升交点/近日点), 方向=真实, 半径=压缩律 _pd(au)
	var defs := [
		["mercury", "mercury.jpg", 0.383, 0.02],
		["venus", "venus.jpg", 0.949, 0.008],
		["earth", "earth.jpg", 1.0, 0.05],
		["mars", "mars.jpg", 0.532, 0.045],
		["jupiter", "res://assets/textures/8k_jupiter.jpg", 11.21, 0.09],
		["saturn", "saturn.jpg", 9.45, 0.08],
		["uranus", "uranus.jpg", 4.01, 0.05],
		["neptune", "neptune.jpg", 3.88, 0.05],
	]
	var t0 := Ephem.centuries_from_ms(solar_sim_ms)
	var planet_pos := {}
	for d in defs:
		var r := _pr(float(d[2]))
		var pos := _ephem_pos(String(d[0]), t0)
		var tex: String = d[1]
		var tex_path := tex if tex.begins_with("res://") else P_TEX + tex
		var p := _make_planet(tex_path, r, pos, false)
		add_child(p)
		_add_orbit_line_from_elements(String(d[0]), t0, Color(0.35, 0.5, 0.8, 0.13))   # 真实开普勒椭圆轨道线
		planet_pos[tex] = pos
		ephem_planets.append({ "name": String(d[0]), "node": p, "tex": tex, "r": r, "pos": pos })
		occluders.append({ "c": pos, "r": r, "eph": String(d[0]) })
		if tex == "res://assets/textures/8k_jupiter.jpg":
			jupiter_pos = pos
		if tex == "earth.jpg":
			earth_pos = pos
			earth_node = p
		var sp_def: Dictionary = SPLAT_PLANETS.get(tex, {})
		if USE_SPLAT_PLANETS and not sp_def.is_empty():
			_add_splat_planet(tex, sp_def, pos, r, p)
		else:
			_add_grid_lod(tex, pos, r, p)   # v6.8:全网格三级(48/96/192 段)—— 近观=连续贴图面,又亮又清
		if String(d[0]) == "earth":
			# v0.9 地球自转 = 真实规律: 自转轴按黄赤交角 23.44° 倾斜(指向黄经270°), 相位 = GMST
			p.basis = Basis(Vector3.RIGHT, deg_to_rad(-Ephem.obliquity(t0)))   # 黄北极=godot(0,cosε,-sinε), 直下点纬度=真赤纬
			earth_gmst_cur = deg_to_rad(Ephem.gmst_deg(Ephem.jd_from_ms(solar_sim_ms))) + EARTH_PHASE
			p.rotate_object_local(Vector3.UP, earth_gmst_cur)
		else:
			self_rot.append([p, d[3]])   # 其余行星: 装饰性自转(真实速率在本尺度下不可感知)
	_ephem_autocal(t0)
	_ephem_report(t0)
	# 冥王星(程序化,Re=0.186/AU=39.5,角度 2.4rad,倾角 17.14° —— 最斜的一条,升交点 110.30°)
	var pluto_plane := Basis(Vector3.UP, deg_to_rad(110.30)) * Basis(Vector3.RIGHT, deg_to_rad(17.14))
	var pluto_dist := _pd(39.5)
	var pluto_pos := pluto_plane * (Vector3(sin(2.4), 0.0, -cos(2.4)) * pluto_dist)
	var pluto := _make_planet("", _pr(0.186), pluto_pos, false)
	pluto.material_override = _pluto_mat()
	add_child(pluto)
	self_rot.append([pluto, 0.01])
	occluders.append({ "c": pluto_pos, "r": _pr(0.186) })
	_add_orbit_line(pluto_dist, Color(0.35, 0.5, 0.8, 0.13), pluto_plane)
	# 卫星:真实半径/真实轨道距 ×SOLAR_SCALE(月球 0.2724Re/38.44 万 km;伽利略卫/土卫六同)
	var ep: Vector3 = planet_pos["earth.jpg"]
	var jp: Vector3 = planet_pos["res://assets/textures/8k_jupiter.jpg"]
	var sp: Vector3 = planet_pos["saturn.jpg"]
	var up: Vector3 = planet_pos["uranus.jpg"]
	_add_planet_extras(earth_pos, GAME_R)   # v6.7:地球三件套(大气边缘光+程序化云层;夜面城市灯待素材)
	# v0.9 月球 = Meeus 截断星历: 真实黄经/黄纬/距离(白道倾角·月相随之正确), 逐帧跟随地球(装饰 pivot 弃用)
	var mn := _make_planet("res://assets/textures/moon.jpg", _pr(0.2724), _moon_game_pos(t0), false)
	var mm := _gray_mat(Color(0.75, 0.74, 0.72))
	var moon_tex: Texture2D = load("res://assets/textures/moon.jpg")
	if moon_tex != null:
		mm.albedo_texture = moon_tex
	mn.material_override = mm
	add_child(mn)
	moon_node = mn
	self_rot.append([mn, 0.05])
	_add_moon("io", _pr(0.286), sqrt(6.033) * _pr(11.21), jp)
	_add_moon("europa", _pr(0.245), sqrt(9.60) * _pr(11.21), jp)
	_add_moon("ganymede", _pr(0.4136), sqrt(15.31) * _pr(11.21), jp)
	_add_moon("callisto", _pr(0.3784), sqrt(26.93) * _pr(11.21), jp)
	_add_moon("titan", _pr(0.4041), sqrt(20.28) * _pr(9.14), sp)
	# 行星环:真实比例(土星 1.24–2.27R=722–1322m;天王星 1.6–1.9R=406–482m)
	_add_ring("saturn_ring.png", _pr(9.14) * 1.24, _pr(9.14) * 2.27, sp, 27.0, 1.0)
	_add_ring("", _pr(3.981) * 1.6, _pr(3.981) * 1.9, up, 98.0, 0.25)
	# v6.3:小行星带 9.5–12.4km(±2km) | 柯伊伯带 48–61km(±6km),远平面 100km 内
	_add_belt(_pd(2.2), _pd(3.3), 1600, 4.0, 18.0, Color(0.45, 0.38, 0.3, 1.0), 1, 2000.0)
	_add_belt(_pd(32.0), _pd(48.0), 2200, 6.0, 30.0, Color(0.4, 0.42, 0.5, 1.0), 2, 6000.0)
	_add_orbit_line(_pd(2.75), Color(0.35, 0.3, 0.22, 0.10))
	# 战斗竞技场锚点:地球低轨旁(距地心 290m,地表 226m 上空)—— 地球在窗外 ~12.5°,抬头可见
	arena_anchor = ep + Vector3(120, 40, 260).normalized() * 350.0   # v6.4:地球 r=100m,350m 处角径 ~16.6°(33° 盘),且敌机巡逻环离地表 ≥49m
	var _e_d := ep.distance_to(arena_anchor)
	print("ARENA: 距地心 %s(真实), 地球角径 %.1f°" % [_dist_real(_e_d), rad_to_deg(asin(clampf(GAME_R / _e_d, 0.0, 1.0)))])
	var ys: Array = planet_pos.values().map(func(v: Vector3) -> float: return v.y)
	print("solar system built (scale v6.3: r=%s·Re^%s, d=%s·AU^%s, 太阳%s, 网格行星) 行星高度 y∈[%.0f, %.0f]m" % [str(GAME_R), str(RAD_P), str(AU_GAME), str(DIST_P), str(SUN_R), ys.min(), ys.max()])

# ============ v0.9 星历驱动(公转/自转/轨道) ============
func _dist_real(u: float) -> String:
	# v2.7 显示统一: 单位=千米(万/亿为量级前缀)。近场 1u=63.7km(地球半径标定)
	return _km_str(u * 6371.0 / GAME_R)

func _km_str(km: float) -> String:
	if km >= 1.0e8:
		return "%.2f亿km" % (km / 1.0e8)
	if km >= 1.0e4:
		return "%.1f万km" % (km / 1.0e4)
	return "%.0fkm" % km
const EARTH_PHASE := 0.0   # 地球贴图经度相位手动微调(rad); 主标定由 _ephem_autocal 启动时自动完成

func _ephem_pos(name: String, t: float) -> Vector3:
	# 星历黄道坐标(au) → 游戏坐标: 方向 = 真实, 半径 = 轨道压缩律 _pd(au)。映射 g=(x, z, -y)
	var ecl := Ephem.heliocentric(name, t)
	var au := ecl.length()
	if au < 1e-9:
		return Vector3.ZERO
	return Vector3(ecl.x, ecl.z, -ecl.y) / au * _pd(au)

func _moon_game_pos(t: float) -> Vector3:
	# 月球地心黄道球坐标 → 地球游戏坐标系偏移(白道倾角/月相/距离全真实)
	var m := Ephem.moon_geocentric(t)
	var lo := deg_to_rad(float(m["lon"]))
	var la := deg_to_rad(float(m["lat"]))
	var dir_g := Vector3(cos(la) * cos(lo), sin(la), -cos(la) * sin(lo))
	return _ephem_pos("earth", t) + dir_g * _pd(float(m["dist"]) / Ephem.AU_KM)

func _add_orbit_line_from_elements(name: String, t: float, col: Color) -> void:
	# 真实开普勒椭圆轨道线: 根数固定于 t, 平近点角扫 0..2π(偏心率/倾角/升交点 = J2000 真值)
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	var seg := 160
	for i in seg + 1:
		var ecl := Ephem.orbit_point(name, t, TAU * i / seg)
		var au := ecl.length()
		im.surface_add_vertex(Vector3(ecl.x, ecl.z, -ecl.y) / au * _pd(au))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	add_child(mi)
	orbit_lines.append(mi)

func _ephem_autocal(t: float) -> void:
	# v0.9 贴图相位自标定: 旋转地球使"游戏内太阳直下点经度" = 星历真值(±两向试旋取优, 免手猜符号)
	if earth_node == null:
		return
	var target := Ephem.subsolar_lon_at(t, solar_sim_ms)
	var delta := deg_to_rad(_ephem_lon_err(t, target))
	var best_err := 1e9
	var best_rot := 0.0
	for cand in [delta, -delta]:
		earth_node.rotate_object_local(Vector3.UP, cand)
		earth_gmst_cur += cand
		var err := absf(_ephem_lon_err(t, target))
		if err < best_err:
			best_err = err
			best_rot = cand
		earth_node.rotate_object_local(Vector3.UP, -cand)
		earth_gmst_cur -= cand
	earth_node.rotate_object_local(Vector3.UP, best_rot)
	earth_gmst_cur += best_rot
	earth_calib_rad = best_rot   # 关键: 逐帧目标相位必须含标定量, 否则首帧即被 GMST 回归抵消
	print("EPHEM: 贴图相位自标定完成, 直下点经度残差 ", snappedf(best_err, 0.01), "°(标定旋转 ", snappedf(rad_to_deg(best_rot), 0.1), "°)")

func _ephem_lon_err(t: float, target: float) -> float:
	var sun_local: Vector3 = (earth_node.global_transform.basis.inverse() * (-earth_node.global_position.normalized())).normalized()
	var lon_g := rad_to_deg(atan2(sun_local.x, sun_local.z))
	var e := target - lon_g
	while e > 180.0:
		e -= 360.0
	while e < -180.0:
		e += 360.0
	return e

func _ephem_report(t: float) -> void:
	# 启动验收打印: 与 tools/demo/live-solar-system.mjs 同源可对拍; 游戏内直下点供贴图相位标定
	var ecl := Ephem.heliocentric("earth", t)
	var g := Ephem.gmst_deg(Ephem.jd_from_ms(solar_sim_ms))
	var ss := Ephem.subsolar_lon_at(t, solar_sim_ms)
	print("EPHEM: earth 日心 %.4f,%.4f,%.4f au | GMST %.3f° | 太阳直下点经度 %.2f°(星历真值)" % [ecl.x, ecl.y, ecl.z, g, ss])
	if earth_node != null:
		var sun_local: Vector3 = (earth_node.global_transform.basis.inverse() * (-earth_node.global_position.normalized())).normalized()
		var lat := rad_to_deg(asin(clampf(sun_local.y, -1.0, 1.0)))
		var lon := rad_to_deg(atan2(sun_local.x, sun_local.z))
		print("EPHEM: 游戏内地球直下点 lat %.2f° lon %.2f° —— 与星历经度差 = EARTH_PHASE 标定值" % [lat, lon])

func _update_ephem_solar(dt: float) -> void:
	solar_sim_ms += dt * 1000.0 * solar_time_scale
	var t := Ephem.centuries_from_ms(solar_sim_ms)
	var pos_map := {}
	for e in ephem_planets:
		var pos := _ephem_pos(String(e["name"]), t)
		e["pos"] = pos
		pos_map[e["name"]] = pos
		var n: Node3D = e["node"]
		if is_instance_valid(n):
			n.position = pos
			var mo = n.material_override
			if mo is ShaderMaterial:   # 网格行星昼夜半球跟随真实日向
				mo.set_shader_parameter("sun_dir", (-pos).normalized())
			if grid_twins.has(n):
				for twin in grid_twins[n]:
					if is_instance_valid(twin):
						(twin as Node3D).position = pos
		for sp in splat_planets:   # splat 层位置跟随(朝向保持构建时 look_at 太阳, 烘焙光照近似有效)
			if sp["mesh"] == e["node"]:
				(sp["near"] as Node3D).position = pos
				(sp["far"] as Node3D).position = pos
	# 地球自转: GMST 逐帧推进(角速度 = 360.9856°/恒星日, 相位连续)
	if earth_node != null and is_instance_valid(earth_node):
		var g := deg_to_rad(Ephem.gmst_deg(Ephem.jd_from_ms(solar_sim_ms))) + EARTH_PHASE + earth_calib_rad
		earth_node.rotate_object_local(Vector3.UP, g - earth_gmst_cur)
		earth_gmst_cur = g
		if grid_twins.has(earth_node):
			for twin in grid_twins[earth_node]:
				if is_instance_valid(twin):
					(twin as Node3D).rotation = earth_node.rotation
		for ex in earth_extras:   # 大气壳/云层跟随
			if is_instance_valid(ex):
				var xn := ex as Node3D
				xn.position = earth_pos
				var xm = xn.material_override
				if xm is ShaderMaterial:
					xm.set_shader_parameter("sun_dir", (-earth_pos).normalized())
					if xm.get_shader_parameter("planet_pos_v612") != null:
						xm.set_shader_parameter("planet_pos_v612", earth_pos)
	# 关键派生位置同步(雷达/竞技场参考)
	if pos_map.has("earth"):
		earth_pos = pos_map["earth"]
	if pos_map.has("jupiter"):
		jupiter_pos = pos_map["jupiter"]
	if moon_node != null and is_instance_valid(moon_node):
		moon_node.position = _moon_game_pos(t)
	for oc in occluders:   # 日食遮挡体中心跟随真实位置
		if oc.has("eph") and pos_map.has(oc["eph"]):
			oc["c"] = pos_map[oc["eph"]]
	# 周期对拍打印(60s): 游戏内直下点经度漂移应 ≈ 星历直下点经度漂移
	_ephem_diag_t += dt
	if _ephem_diag_t >= 60.0:
		_ephem_diag_t = 0.0
		if earth_node != null and is_instance_valid(earth_node):
			var sun_local: Vector3 = (earth_node.global_transform.basis.inverse() * (-earth_node.global_position.normalized())).normalized()
			var _g2 := Ephem.gmst_deg(Ephem.jd_from_ms(solar_sim_ms))
			var _s2 := Ephem.subsolar_lon_at(t, solar_sim_ms)
			var _i2 := rad_to_deg(atan2(sun_local.x, sun_local.z))
			print("EPHEM[diag] GMST=", snappedf(_g2, 0.01), "° 星历直下点=", snappedf(_s2, 0.01), "° 游戏内=", snappedf(_i2, 0.01), "° 时标x", solar_time_scale)

func _make_planet(tex: String, radius: float, pos: Vector3, emissive: bool, segs: int = 96) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segs
	s.rings = maxi(segs / 2, 16)
	mi.mesh = s
	if emissive:
		var em := StandardMaterial3D.new()
		if tex != "" and ResourceLoader.exists(tex):
			em.albedo_texture = load(tex)
		em.emission_enabled = true
		em.emission = Color(1.0, 0.9, 0.7)
		em.emission_energy_multiplier = 1.4
		em.albedo_color = Color(10.0, 9.2, 8.2)   # v6.11:UNSHADED 下 emission 不参与合成,旧值(≈1.05)经 FILMIC 只有 ~0.38,比背景天空还暗;拉到 HDR~4 使日盘白热(FILMIC→~0.9),黑天上轮廓清晰
		em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = em
		mi.position = pos
		return mi
	# v6.9:太阳方向光照(昼夜半球+柔和晨昏线);三级 LOD 共用同一 shader → 换档零差异
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/planet_surface.gdshader")
	if tex != "" and ResourceLoader.exists(tex):
		m.set_shader_parameter("tex", load(tex))
	m.set_shader_parameter("sun_dir", (-pos).normalized())   # 太阳在原点
	m.set_shader_parameter("night_ambient", 0.07)
	mi.material_override = m
	mi.position = pos
	return mi

func _pluto_mat() -> StandardMaterial3D:
	var img := Image.create(512, 256, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for y in 256:
		for x in 512:
			var n := 0.5 + 0.28 * sin(x * 0.05 + sin(y * 0.11) * 3.0) + 0.12 * rng.randf_range(-1, 1)
			var heart := Vector2(x - 256, y - 120).length() < 60.0
			img.set_pixel(x, y, Color(n * 0.62, n * 0.55, n * 0.46))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 1.0
	return m

func _add_moon(_name: String, radius: float, orbit_r: float, center: Vector3) -> void:
	var pivot := Node3D.new()
	pivot.position = center
	add_child(pivot)
	var mi := _make_planet("", radius, Vector3(orbit_r, 0, 0), false)
	if _name == "moon":
		var mm := _gray_mat(Color(0.75, 0.74, 0.72))
		var moon_tex: Texture2D = load("res://assets/textures/moon.jpg")   # v0.8:NASA SVS CGI Moon kit LROC 4k(公有领域)
		if moon_tex != null:
			mm.albedo_texture = moon_tex
			mm.uv1_scale = Vector3.ONE
		mi.material_override = mm
	elif _name == "io":
		mi.material_override = _gray_mat(Color(0.85, 0.75, 0.4))
	elif _name == "europa":
		mi.material_override = _gray_mat(Color(0.8, 0.78, 0.7))
	elif _name == "ganymede":
		mi.material_override = _gray_mat(Color(0.55, 0.5, 0.45))
	elif _name == "callisto":
		mi.material_override = _gray_mat(Color(0.42, 0.4, 0.38))
	else:
		mi.material_override = _gray_mat(Color(0.7, 0.55, 0.35))
	pivot.add_child(mi)
	moon_pivots.append(pivot)

func _gray_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _add_ring(tex: String, r_in: float, r_out: float, pos: Vector3, tilt_deg: float, opacity: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 128
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var u0 := Vector2(cos(a0), sin(a0))
		var u1 := Vector2(cos(a1), sin(a1))
		var vs := [Vector3(u0.x * r_in, 0, u0.y * r_in), Vector3(u0.x * r_out, 0, u0.y * r_out), Vector3(u1.x * r_out, 0, u1.y * r_out), Vector3(u1.x * r_in, 0, u1.y * r_in)]
		var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		st.set_uv(uv[0]); st.add_vertex(vs[0])
		st.set_uv(uv[1]); st.add_vertex(vs[1])
		st.set_uv(uv[2]); st.add_vertex(vs[2])
		st.set_uv(uv[0]); st.add_vertex(vs[0])
		st.set_uv(uv[2]); st.add_vertex(vs[2])
		st.set_uv(uv[3]); st.add_vertex(vs[3])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if tex != "" and ResourceLoader.exists(P_TEX + tex):
		m.albedo_texture = load(P_TEX + tex)
		m.albedo_color = Color(1, 1, 1, opacity)
	else:
		m.albedo_color = Color(0.65, 0.7, 0.75, opacity * 0.5)
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = Vector3(-tilt_deg, 0, 0)
	add_child(mi)

func _add_belt(r_in: float, r_out: float, count: int, s_min: float, s_max: float, col: Color, layer: int, h_spread: float = 20000.0) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var mesh := SphereMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.radius = 1.0
	mesh.height = 2.0
	mm.mesh = mesh
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260910 + layer
	for i in count:
		var a := rng.randf() * TAU
		var r := rng.randf_range(r_in, r_out)
		var h := rng.randf_range(-h_spread, h_spread) * (0.4 + 0.6 * rng.randf())
		var pos := Vector3(cos(a) * r, h, sin(a) * r)
		var s := rng.randf_range(s_min, s_max)
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s, s * rng.randf_range(0.6, 1.4), s))
		mm.set_instance_transform(i, Transform3D(basis, pos))
		var c := col * rng.randf_range(0.6, 1.2)
		c.a = 1.0
		mm.set_instance_color(i, c)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# ==================== 行星 3DGS 分级渲染 + 解析日食(v0.4) ====================

func _add_grid_lod(tex_key: String, pos: Vector3, r: float, mid: MeshInstance3D) -> void:
	# v6.8:三级全网格 —— 近=192段 / 中=96段(原网格) / 远=48段;同贴图同材质,切换差异亚像素级
	var hi := _make_planet(tex_key, r, pos, false, 192)
	var lo := _make_planet(tex_key, r, pos, false, 48)
	add_child(hi)   # v6.16.1 修复: hi/lo 从未挂树 → L0 时不渲染(天王星/海王星看不到)
	add_child(lo)
	hi.visible = false
	lo.visible = false
	grid_twins[mid] = [hi, lo]	# v6.12f
	planet_lods.append({ "hi": hi, "mid": mid, "lo": lo, "radius": r, "level": 1, "name": tex_key })
	print("GRID-LOD: %s r=%.1fm 三级就绪(48/96/192 段)" % [tex_key, r])

func _add_splat_planet(tex_key: String, def: Dictionary, pos: Vector3, radius: float, mesh_twin: MeshInstance3D) -> void:
	mesh_twin.look_at(Vector3.ZERO, Vector3.UP)	# v6.12f: 与高斯(look_at太阳)同经度基准, 交叉淡变不滑纹理
	var res_l1: GaussianResource = load(def["l1"]) if ResourceLoader.exists(def["l1"]) else null
	if res_l1 == null:
		print("SPLAT-PLANET: PLY 缺失, 保持网格行星 (%s)" % [def["l1"]])
		return
	# v6.7:PLY 按旧半径烘焙 → 节点缩放适配现半径(高斯协方差随 MODEL_MATRIX 正确缩放,无需重烘)
	var baked_l1: float = res_l1.aabb.size.x * 0.5
	var n_far := GaussianSplatNode.new()
	add_child(n_far)
	n_far.position = pos
	n_far.look_at(Vector3.ZERO, Vector3.UP)
	n_far.gaussian = res_l1
	n_far.scale = Vector3.ONE * (radius / maxf(baked_l1, 0.001))
	n_far.visible = false
	var n_near := GaussianSplatNode.new()
	add_child(n_near)
	n_near.position = pos
	n_near.look_at(Vector3.ZERO, Vector3.UP)
	n_near.scale = Vector3.ONE
	n_near.visible = false
	# v0.8:L0 不再启动常驻(地球/木星各 ~200-300MB) —— 角径≥7.5° 线程加载, 离开 6.5° 后 10s 卸载回收
	splat_planets.append({ "near": n_near, "far": n_far, "mesh": mesh_twin, "radius": radius, "level": 2, "name": tex_key,
		"l0_path": def["l0"], "l0_state": 0, "l0_grace": 0.0, "l0_baked": res_l1.aabb.size.x })
	print("SPLAT-PLANET: %s r=%.1fm L1=%dk 三级LOD就绪(L0 按需流式)" % [tex_key, radius, res_l1.point_count / 1000])

# ==================== v0.8 高斯特效播放器(逐帧 PLY 序列, 开源 SplatVFX/PhysGaussian 运动模型离线烘焙) ====================
const FX_FRAMES := { "muzzle": 6, "blast": 12, "laser_hit": 8, "charge": 6 }

func _fx_frames(name: String) -> Array:
	if fx_cache.has(name):
		return fx_cache[name]
		_ev("fx_first_load:" + name)   # v0.9.7:惰性加载事件(仅未预热时出现)
	var frames: Array = []
	var n: int = int(FX_FRAMES.get(name, 0))
	for i in n:
		var res: GaussianResource = load("res://assets/fx/%s_%02d.ply" % [name, i])
		if res != null:
			frames.append(res)
	fx_cache[name] = frames
	return frames

func _fx_play(name: String, pos: Vector3, scale_mul: float = 1.0, fps: float = 0.0) -> void:
	var frames := _fx_frames(name)
	if frames.is_empty():
		return
	var node: GaussianSplatNode
	if _fx_node_pool.is_empty():
		node = GaussianSplatNode.new()
		_ev("fx_new:" + name)
	else:
		node = _fx_node_pool.pop_back()
		_ev("fx_pool:" + name)
	node.visible = true
	node.gaussian = frames[0]
	node.position = pos
	node.scale = Vector3.ONE * scale_mul
	if node.get_parent() == null:
		add_child(node)
	fx_active.append({ "node": node, "name": name, "frames": frames, "fps": (fps if fps > 0.0 else (30.0 if name != "blast" else 25.0)), "t": 0.0 })

func _tick_fx(dt: float) -> void:
	for i in range(fx_active.size() - 1, -1, -1):
		var f: Dictionary = fx_active[i]
		f["t"] = float(f["t"]) + dt
		var frame := int(float(f["t"]) * float(f["fps"]))
		var frames: Array = f["frames"]
		if frame >= frames.size():
			var dn := f["node"] as GaussianSplatNode
			dn.visible = false
			_fx_node_pool.append(dn)   # v0.9.7:回池复用
			fx_active.remove_at(i)
		elif (f["node"] as GaussianSplatNode).gaussian != frames[frame]:
			(f["node"] as GaussianSplatNode).gaussian = frames[frame]

func _lod_fading(node) -> bool:
	for f in lod_fades:
		if f["node"] == node:
			return true
	return false

func _lod_fade_out_only(node: Node3D, is_mesh: bool) -> void:
	for i in range(lod_fades.size() - 1, -1, -1):
		if lod_fades[i]["node"] == node:
			lod_fades.remove_at(i)
	lod_fades.append({ "node": node, "is_mesh": is_mesh, "from": 1.0, "to": 0.0, "t": 0.0, "dur": 0.55 })
	_apply_lod_alpha(node, is_mesh, 1.0)

func _apply_lod_alpha(node, is_mesh: bool, frac: float) -> void:
	# frac: 0=不可见 1=完全可见(网格走 transparency 反相, splat 走 node_alpha)
	if is_mesh:
		(node as GeometryInstance3D).transparency = 1.0 - frac
	else:
		node.set("node_alpha", frac)

func _lod_crossfade(sp: Dictionary, old_lv: int, new_lv: int) -> void:
	var n_old: Node3D = [sp["near"], sp["far"], sp["mesh"]][old_lv]
	var n_new: Node3D = [sp["near"], sp["far"], sp["mesh"]][new_lv]
	if new_lv == 0 and int(sp.get("l0_state", 2)) != 2:
		_lod_fade_out_only(n_old, old_lv == 2)   # L0 未流完: 只淡出旧层, L1 已作为 fallback 持续显示
		return
	for i in range(lod_fades.size() - 1, -1, -1):
		if lod_fades[i]["node"] == n_old or lod_fades[i]["node"] == n_new:
			lod_fades.remove_at(i)
	n_new.visible = true
	lod_fades.append({ "node": n_new, "is_mesh": new_lv == 2, "from": 0.0, "to": 1.0, "t": 0.0, "dur": 0.55 })
	lod_fades.append({ "node": n_old, "is_mesh": old_lv == 2, "from": 1.0, "to": 0.0, "t": 0.0, "dur": 0.55 })
	_apply_lod_alpha(n_new, new_lv == 2, 0.0)
	_apply_lod_alpha(n_old, old_lv == 2, 1.0)

func _tick_lod_fades(dt: float) -> void:
	for i in range(lod_fades.size() - 1, -1, -1):
		var f: Dictionary = lod_fades[i]
		f["t"] = float(f["t"]) + dt
		var k := clampf(float(f["t"]) / float(f["dur"]), 0.0, 1.0)
		var frac := lerpf(float(f["from"]), float(f["to"]), k)
		_apply_lod_alpha(f["node"], f["is_mesh"], frac)
		if k >= 1.0:
			if frac <= 0.001:
				var gn: Node3D = f["node"] as Node3D
				if gn != null:
					gn.visible = false
					_apply_lod_alpha(gn, f["is_mesh"], 1.0)   # 复位,下次淡入干净(GaussianSplatNode=VisualInstance3D,不能转 GeometryInstance3D)
			lod_fades.remove_at(i)

func _tick_l0_stream(dt: float) -> void:
	# v0.8:行星 L0 按需流式 —— 线程加载(角径≥7.5°即 level==0)/宽限卸载(离开 6.5° 后 10s), 单颗回收 ~200-300MB
	for sp in splat_planets:
		var st: int = sp["l0_state"]
		var near: GaussianSplatNode = sp["near"]
		var lv: int = sp["level"]
		if st == 2 and lv != 0:
			sp["l0_grace"] = float(sp["l0_grace"]) + dt
			if float(sp["l0_grace"]) > 10.0:
				_ev("l0_un:" + str(sp["name"]))   # v0.9.7:hitch 归因
				near.gaussian = null   # 释放 GPU 缓冲(后端随 gaussian 变更 detach)
				sp["l0_state"] = 0
				sp["l0_grace"] = 0.0
				print("SPLAT-L0: %s 卸载(显存回收)" % [sp["name"]])
		elif st == 0 and lv == 0:
			ResourceLoader.load_threaded_request(sp["l0_path"])
			sp["l0_state"] = 1
			print("SPLAT-L0: %s 开始流式加载" % [sp["name"]])
		elif st == 1:
			var sts: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(sp["l0_path"])
			if sts == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_LOADED:
				var res: GaussianResource = ResourceLoader.load_threaded_get(sp["l0_path"])
				if res != null:
					near.scale = Vector3.ONE * (float(sp["radius"]) * 0.996 / maxf(float(sp["l0_baked"]) * 0.5, 0.001))
					_ev("l0_up:" + str(sp["name"]))   # v0.9.7:hitch 归因
					near.gaussian = res
					near.visible = sp["level"] == 0
					sp["l0_state"] = 2
					sp["l0_grace"] = 0.0
					if sp["level"] == 0:
						_lod_crossfade(sp, 1, 0)   # L1→L0 平滑接管
					print("SPLAT-L0: %s 加载完成(%dk)" % [sp["name"], res.point_count / 1000])
			elif sts == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_FAILED or sts == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_INVALID_RESOURCE:
				sp["l0_state"] = 0   # 加载失败,回到待命(下帧重试)

func _update_splat_lod() -> void:
	# v6.12c splat 三级:近(>=10度)=网格贴图 / 中(3.5~10度)=L0 高斯 / 远(<2.5度)=L1 高斯
	# 像素依据: L0 40万点点距0.56m 投影1px 临界约780m(角径7.4度), 10度接管留余量; 网格 texel 0.116m 1:1 到约130m
	for sp in splat_planets:
		var d_s: float = cam.global_position.distance_to((sp["near"] as Node3D).global_position)
		var ang_s := rad_to_deg(asin(clampf(float(sp["radius"]) / maxf(d_s, float(sp["radius"]) + 0.1), 0.0, 1.0)))
		var lv_s: int = sp["level"]
		if ang_s >= SPLAT_LOD_MESH_DEG:
			lv_s = 2
		elif lv_s == 2 and ang_s >= SPLAT_LOD_MESH_DEG - SPLAT_LOD_HYST_DEG:
			lv_s = 2
		elif ang_s < SPLAT_LOD_L1_DEG - 1.0:
			lv_s = 1
		elif lv_s == 1 and ang_s < SPLAT_LOD_L1_DEG:
			lv_s = 1
		else:
			lv_s = 0
		# v0.8:交叉淡化切换(0.55s) —— 旧层淡出/新层淡入,亮度与点密度差异随视角连续过渡,消除跳变
		# (v6.12g 弃用的是"整层 alpha 进透明队列"; 本版用 gdgs node_alpha 逐节点通道, 不改渲染队列)
		if lv_s != int(sp["level"]):
			var old_lv: int = sp["level"]
			sp["level"] = lv_s
			_lod_crossfade(sp, old_lv, lv_s)
			print("SPLAT-LOD: %s -> %s (角径 %.1f度, d=%.0fm, 淡入0.55s)" % [str(sp["name"]), ["L0高斯", "L1高斯", "网格"][lv_s], ang_s, d_s])
		var l0_ready: bool = int(sp["l0_state"]) == 2
		(sp["mesh"] as Node3D).visible = lv_s == 2 or _lod_fading(sp["mesh"])
		(sp["near"] as Node3D).visible = (lv_s == 0 and l0_ready) or _lod_fading(sp["near"])
		(sp["far"] as Node3D).visible = lv_s == 1 or (lv_s == 0 and not l0_ready) or _lod_fading(sp["far"])   # L0 未流完 L1 顶上
	# v6.8 全网格三级 LOD(48/96/192 段)—— 近观要的是"连续贴图面"(8k 贴图+192段),splat 40万点铺100m球点距0.5m近看是颗粒雾
	# 判据角径 = 按行星半径归一化的距离:d ≤ r/sin(8°)=7.15r 切近层(地球 715m / 木星 8.0km / 太阳 78km,一条规则通用)
	for sp in planet_lods:
		var d: float = cam.global_position.distance_to((sp["mid"] as Node3D).global_position)
		var ang := rad_to_deg(asin(clampf(float(sp["radius"]) / maxf(d, float(sp["radius"]) + 0.1), 0.0, 1.0)))
		var lv: int = sp["level"]
		if ang >= SPLAT_LOD_SWAP_DEG:
			lv = 0
		elif ang < SPLAT_LOD_L1_DEG - 1.0:
			lv = 2
		elif lv == 0 and ang < SPLAT_LOD_SWAP_DEG - SPLAT_LOD_HYST_DEG:
			lv = 1
		elif lv == 2:
			lv = 1
		# v6.12g: 离散切换(自转已三体同步, 切层经度恒对齐)
		if lv != sp["level"]:
			sp["level"] = lv
			(sp["hi"] as Node3D).visible = lv == 0
			(sp["mid"] as Node3D).visible = lv == 1
			(sp["lo"] as Node3D).visible = lv == 2
			print("PLANET-LOD: %s -> L%d (角径 %.1f°, d=%.0fm)" % [str(sp["name"]), lv, ang, d])

# 解析日食: 太阳(原点, 真实比例 r=6960m 面光源)是唯一光源, 行星椭球遮挡 —— 无 shadow map
func _sun_visibility(p: Vector3) -> float:
	var sun_r := SUN_R
	var d_sun := p.length()
	if d_sun < sun_r:
		return 0.0
	var dir_sun := -p / d_sun
	var beta := asin(minf(sun_r / d_sun, 1.0))
	var vis := 1.0
	for oc in occluders:
		var to_c: Vector3 = oc["c"] - p
		var d_c := to_c.length()
		if d_c < 0.001:
			return 0.0
		var cosg := dir_sun.dot(to_c / d_c)
		if cosg <= 0.0:
			continue  # 遮挡体在背向太阳的半球
		var alpha := asin(minf(oc["r"] / d_c, 1.0))
		var g := acos(clampf(cosg, -1.0, 1.0))
		if g >= alpha + beta:
			continue  # 阴影锥外
		var a2 := alpha * alpha
		var b2 := beta * beta
		if alpha >= beta and g + beta <= alpha:
			return 0.0  # 本影全食(行星角径 ≥ 太阳盘)
		if beta > alpha and g <= beta - alpha:
			vis = minf(vis, 1.0 - a2 / b2)  # 环食: 行星盘整个悬在太阳盘内
			continue
		# 部分重叠: 两圆重叠面积占太阳盘比例(Heron 因子在此带内均 ≥0)
		var d2 := g * g
		var t1 := a2 * acos(clampf((d2 + a2 - b2) / (2.0 * g * alpha), -1.0, 1.0))
		var t2 := b2 * acos(clampf((d2 + b2 - a2) / (2.0 * g * beta), -1.0, 1.0))
		var t3 := 0.5 * sqrt(maxf((-g + alpha + beta) * (g + alpha - beta) * (g - alpha + beta) * (g + alpha + beta), 0.0))
		var frac := (t1 + t2 - t3) / (PI * b2)
		vis = minf(vis, 1.0 - clampf(frac, 0.0, 1.0))
	return vis

func _update_ship_lighting() -> void:
	for e in enemies:
		if not is_instance_valid(e) or e.body_mat == null:
			continue
		var s := 0.3 + 0.7 * _sun_visibility(e.global_position)
		e.body_mat.albedo_color = Color(s, s, s, 1.0)

func _eclipse_selftest() -> void:
	if jupiter_pos == Vector3.ZERO or occluders.is_empty():
		print("ECLIPSE-SELFTEST: SKIP(无遮挡体)")
		return
	# 木星背阳面 ~2.7×半径(应全食) 与绕太阳轴转 45° 的位置(应全照)
	var behind := jupiter_pos.normalized() * (jupiter_pos.length() + 2.7 * _pr(11.21))
	var vb := _sun_visibility(behind)
	var lit := jupiter_pos.rotated(Vector3.UP, deg_to_rad(45.0))
	var vl := _sun_visibility(lit)
	print("ECLIPSE-SELFTEST: behind=%.3f lit=%.3f -> %s" % [vb, vl, "PASS" if vb < 0.15 and vl > 0.95 else "FAIL"])

func _add_orbit_line(radius: float, col: Color, plane: Basis = Basis()) -> void:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	var seg := 128
	for i in seg + 1:
		var a := TAU * i / seg
		im.surface_add_vertex(Vector3(cos(a) * radius, 0, sin(a) * radius))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.transform = Transform3D(plane, Vector3.ZERO)
	add_child(mi)
	orbit_lines.append(mi)

func _ship_texture() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(s / 2.0, s / 2.0)
	for y in s:
		for x in s:
			var p := Vector2(x - c.x, y - c.y)
			if absf(p.x) < 5.0 and absf(p.y) < 20.0:
				img.set_pixel(x, y, Color(1.0, 0.92, 0.75))
			elif absf(p.x) * 0.8 + absf(p.y) < 26.0:
				img.set_pixel(x, y, Color(1.0, 0.32, 0.12))
	return ImageTexture.create_from_image(img)

class Enemy extends Area3D:
	var root: Node3D
	var path: Curve3D
	var path_t := 0.0
	var speed := 42.0
	var hp := 100
	var hp_max := 100
	var vel := Vector3.ZERO
	var gun_cd := 1.0
	var heal_cd := 1.0
	var orbit_dir := 1.0
	var rseed := 0.0
	var bt_root: RefCounted
	var fleeing := false
	var _bt_sel: RefCounted
	var body_mat: StandardMaterial3D   # 日食调光用(解析椭球阴影只算太阳)
	# v0.7 crowd 机型字段(低模=物理+远景剪影,高斯=渲染外观)
	var stream: Crowd.Stream = null
	var slot_i := 0
	var engaging := false
	var gs_node: GaussianSplatNode = null
	var mesh_node: MeshInstance3D = null
	var dmg_mul := 1.0

	func setup(r: Node3D, p: Curve3D, t0: float) -> void:
		root = r
		path = p
		path_t = t0
		rseed = randf() * 100.0
		hp = root._bi("enemy", "hp_base")
		orbit_dir = 1.0 if randf() > 0.5 else -1.0
		collision_layer = 2
		collision_mask = 0
		var vs: float = root._b("enemy", "visual_size")   # v0.6:机体可视尺寸数据表驱动(默认 8m,原 3m 在 260m 交战仅 ~6px)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(vs * 0.8, vs * 0.8, vs * 0.8)
		cs.shape = sh
		add_child(cs)
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(vs, vs)
		mi.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_texture = root._ship_texture()
		mi.material_override = mat
		body_mat = mat
		add_child(mi)
		position = p.sample_baked(t0 * p.get_baked_length())
		_bt_sel = BTSel.new([
			BTSeq.new([BTCond.new(func() -> bool: return hp < root._bi("enemy", "retreat_hp")), BTAct.new(Callable(root, "_act_evade"))]),
			BTSeq.new([BTCond.new(func() -> bool: return root.cam.global_position.distance_to(global_position) < root._b("enemy", "engage_range")), BTAct.new(Callable(root, "_act_patrol_or_engage"))]),
			BTAct.new(Callable(root, "_act_patrol")),
		])

	func setup_jet(r: Node3D, s: Crowd.Stream, i: int, origin: Vector3) -> void:
		# v0.7:机群流成员 —— 低模 trimesh 物理判定 + 高斯模板外观 + 流编队 slot
		root = r
		stream = s
		slot_i = i
		rseed = randf() * 100.0
		hp = root._bi("enemy", "hp_base")
		orbit_dir = 1.0 if randf() > 0.5 else -1.0
		collision_layer = 2
		collision_mask = 0
		var t: Dictionary = Crowd.TYPES[s.type_id]
		speed = 42.0 * float(t["speed_mul"])
		dmg_mul = float(t["dmg_mul"])
		var built: Dictionary = Crowd.build_jet(self, s.type_id, root._b("crowd", "jet_scale"))   # v0.7.1:jet_scale=0.22 → 2m 级机体,碰撞盒同步缩放
		gs_node = built["gs"]
		mesh_node = built["mesh"]
		global_position = origin + Vector3(randf_range(-90, 90), randf_range(-40, 40), randf_range(-90, 90))
		_bt_sel = BTSel.new([
			BTSeq.new([BTCond.new(func() -> bool: return hp < root._bi("enemy", "retreat_hp")), BTAct.new(Callable(root, "_act_evade"))]),
			BTSeq.new([BTCond.new(func() -> bool: return root.cam.global_position.distance_to(global_position) < root._b("enemy", "engage_range")), BTAct.new(Callable(root, "_act_patrol_or_engage"))]),
			BTAct.new(Callable(root, "_act_patrol")),
		])

	func _update_pose(dt: float) -> void:
		# v0.7.1:机头指向速度方向 + 转弯侧倾;倾角限 ±15°(原 ±40°),姿态收敛放慢(dt*2.2)
		# —— 消除"锐角转向"观感:机头扫摆与滚转都有上限,急转弯呈现为宽弧线
		if vel.length_squared() < 9.0:
			return
		var dir_n := vel.normalized()
		var target := Basis.looking_at(dir_n, Vector3.UP)
		var last_dir: Vector3 = get_meta("last_dir", dir_n)
		var lat := last_dir.cross(dir_n).dot(Vector3.UP) / maxf(dt, 0.001)
		set_meta("last_dir", dir_n)
		var roll := clampf(lat * 0.28, -0.26, 0.26)
		basis = basis.slerp(target * Basis(Vector3.BACK, roll), clampf(dt * 2.2, 0.0, 1.0)).orthonormalized()

	func _process(_dt: float) -> void:
		if hp <= 0:
			return
		_update_pose(_dt)
		if fleeing:
			var away: Vector3 = (global_position - root.cam.global_position).normalized()
			steer_to(global_position + away * 120.0 + Vector3.UP * 25.0, _dt)
			if global_position.distance_to(root.cam.global_position) > 3000.0:
				root.enemies.erase(self)
				queue_free()
			return
		_bt_sel.tick(self, _dt)

	func steer_to(target: Vector3, dt: float) -> void:
		var want := (target - global_position).normalized() * speed
		vel = vel.lerp(want, clampf(dt * 1.6, 0.0, 1.0))
		global_position += vel * dt

	func steer_soft(target: Vector3, dt: float) -> void:
		# v0.7.1:编队软伺服 —— 速度方向收敛减半,转弯弧线更宽,配合倾角上限消除锐角转向观感
		var want := (target - global_position).normalized() * speed
		vel = vel.lerp(want, clampf(dt * 0.85, 0.0, 1.0))
		global_position += vel * dt

func _act_patrol_or_engage(e: Enemy, dt: float) -> int:
	if cam.global_position.distance_to(e.global_position) >= _b("enemy", "engage_range"):
		if e.stream != null:
			e.stream.release_attack(e)
		return _act_patrol(e, dt)
	# v0.7:交战令牌 —— 每流同时最多 attack_tokens 架开火,其余保持编队整齐飞过
	if e.stream != null and not e.engaging and not e.stream.request_attack(e):
		return _act_patrol(e, dt)
	return _act_engage(e, dt)

const BT_SUCCESS := 0
const BT_FAILURE := 1
const BT_RUNNING := 2

class BTNode extends RefCounted:
	func tick(_e: Enemy, _dt: float) -> int:
		return BT_FAILURE

class BTSeq extends BTNode:
	var children: Array
	func _init(c: Array) -> void: children = c
	func tick(e: Enemy, dt: float) -> int:
		for ch in children:
			var s: int = ch.tick(e, dt)
			if s != BT_SUCCESS:
				return s
		return BT_SUCCESS

class BTSel extends BTNode:
	var children: Array
	func _init(c: Array) -> void: children = c
	func tick(e: Enemy, dt: float) -> int:
		for ch in children:
			var s: int = ch.tick(e, dt)
			if s != BT_FAILURE:
				return s
		return BT_FAILURE

class BTCond extends BTNode:
	var cond: Callable
	func _init(c: Callable) -> void: cond = c
	func tick(_e: Enemy, _dt: float) -> int:
		var r: bool = cond.call()
		return BT_SUCCESS if r else BT_FAILURE

class BTAct extends BTNode:
	var act: Callable
	func _init(a: Callable) -> void: act = a
	func tick(e: Enemy, dt: float) -> int:
		return act.call(e, dt)

class HUDCanvas extends Control:
	var root: Node3D = null

	func _draw() -> void:
		if root == null or root.cam == null:
			return
		var vp := get_viewport_rect().size
		var c := vp * 0.5
		var col := Color(0.6, 1.0, 0.8, 0.9)
		var spread := 10.0
		if root.fire_cd > 0.0:
			spread += 4.0 + root.bloom * 2.5
		draw_line(c + Vector2(-spread - 8, 0), c + Vector2(-spread, 0), col, 1.5)
		draw_line(c + Vector2(spread, 0), c + Vector2(spread + 8, 0), col, 1.5)
		draw_line(c + Vector2(0, -spread - 8), c + Vector2(0, -spread), col, 1.5)
		draw_line(c + Vector2(0, spread), c + Vector2(0, spread + 8), col, 1.5)
		# v0.9.6:常驻激光 UI 反馈(集中于准星,替代 3D 近场特效)
		if root._laser_unlocked():
			var lc := Color(0.45, 0.9, 1.0, 0.85)
			if root.laser_phase == 1:
				var pr := 20.0 + 1.5 * sin(root.fx_time * 6.0)   # 激活呼吸环
				draw_arc(c, pr, 0.0, TAU, 32, lc, 1.2)
				var ra: float = float(root.fx_time) * 0.8
				for k in 4:
					var an: float = ra + TAU * float(k) / 4.0
					draw_line(c + Vector2(cos(an), sin(an)) * (pr + 3.0), c + Vector2(cos(an), sin(an)) * (pr + 8.0), lc, 1.5)
				if root.beam_hit:
					draw_circle(c, 2.0, Color(0.8, 1.0, 1.0, 0.9))   # 命中中心亮点
					var heat := clampf(root.beam_hit_t / 1.2, 0.0, 1.0)
					draw_arc(c, pr + 5.0, -PI * 0.5, -PI * 0.5 + TAU * heat, 16, Color(1.0, 0.6, 0.3, 0.9), 2.0)   # 持续照射热度弧
			else:
				var cprog := clampf(root.laser_t / maxf(root._b("weapon_laser", "recharge"), 0.01), 0.0, 1.0)
				draw_arc(c, 20.0, -PI * 0.5, -PI * 0.5 + TAU * cprog, 24, Color(0.45, 0.9, 1.0, 0.6), 2.0)   # 起辉充能弧
		if root.hitmark_ttl > 0.0:
			var h := 7.0
			var mc: Vector2 = c + (root.aim as Vector2)
			draw_line(mc + Vector2(-h, -h), mc + Vector2(-3, -3), Color(1, 0.3, 0.2), 2.0)
			draw_line(mc + Vector2(h, -h), mc + Vector2(3, -3), Color(1, 0.3, 0.2), 2.0)
			draw_line(mc + Vector2(-h, h), mc + Vector2(-3, 3), Color(1, 0.3, 0.2), 2.0)
			draw_line(mc + Vector2(h, h), mc + Vector2(3, 3), Color(1, 0.3, 0.2), 2.0)
		# 火控提前量标记(等离子拦截点)
		if root.lock_valid:
			var lp: Vector3 = root.lock_point
			if not root.cam.is_position_behind(lp):
				var lscr: Vector2 = root.cam.unproject_position(lp)
				var pc := Color(1.0, 0.8, 0.2, 0.85) if not root.lock_ready else Color(0.4, 1.0, 0.6, 0.95)
				draw_arc(lscr, 10.0, 0.0, TAU, 24, pc, 1.6)
				if root.lock_ready:
					draw_circle(lscr, 2.5, pc)
					draw_string(ThemeDB.fallback_font, lscr + Vector2(14, -8), "LOCK", HORIZONTAL_ALIGNMENT_LEFT, 70, 10, pc)
		# 目标标记(真实比例下肉眼难辨:核心/地球/太阳/敌机全部屏幕标记+距离,出视野钳到边缘)
		var mlist := []
		# v2.7 雷达统一: 全部千米(万/亿前缀), 每个目标只一个数字
		# 近场(地球/核心/金鱼)按尺寸比例换算; 跨轨道(太阳/木星)取星历真实距离(游戏内坐标幂压缩, 换算无意义)
		var _t_eph: float = Ephem.centuries_from_ms(root.solar_sim_ms)
		var _pd: Vector3 = root.cam.global_position
		var _au_km := 1.496e8
		if root.phase >= 1 and is_instance_valid(root.gate):
			mlist.append({"p": root.gate.global_position, "t": "核心 " + root._dist_real(_pd.distance_to(root.gate.global_position)), "c": Color(0.75, 0.5, 1.0)})
		mlist.append({"p": root.earth_pos, "t": "地球 " + root._dist_real(_pd.distance_to(root.earth_pos)), "c": Color(0.45, 0.85, 1.0)})
		if PLANET_INVINCIBLE:
			var _j_km: float = (Ephem.heliocentric("jupiter", _t_eph) - Ephem.heliocentric("earth", _t_eph)).length() * _au_km
			mlist.append({"p": root.jupiter_pos, "t": "木星 " + root._km_str(_j_km), "c": Color(0.95, 0.75, 0.5)})
		var _s_km: float = Ephem.heliocentric("earth", _t_eph).length() * _au_km
		mlist.append({"p": Vector3.ZERO, "t": "太阳 " + root._km_str(_s_km), "c": Color(1.0, 0.85, 0.4)})
		if is_instance_valid(root._whale):
			mlist.append({"p": root._whale.current_pos(), "t": "星金鱼 " + root._dist_real(_pd.distance_to(root._whale.current_pos())), "c": Color(0.5, 1.0, 0.95)})
		if root.station != null and is_instance_valid(root.station):
			mlist.append({"p": root.station.global_position, "t": "防御炮台 " + root._dist_real(_pd.distance_to(root.station.global_position)), "c": Color(0.6, 0.9, 1.0)})
		if root.radar_ring != null and is_instance_valid(root.radar_ring):
			mlist.append({"p": root.radar_ring.global_position, "t": "雷达相阵 " + root._dist_real(_pd.distance_to(root.radar_ring.global_position)), "c": Color(0.8, 0.9, 1.0)})
		if root.boss != null and is_instance_valid(root.boss):
			mlist.append({"p": root.boss.global_position, "t": "BOSS·八棱柱集群 " + root._dist_real(_pd.distance_to(root.boss.global_position)), "c": Color(1.0, 0.3, 0.3)})
		# v0.8:不再逐机撒标记 —— 只标主目标(核心)与准星压到的敌机
		if is_instance_valid(root.hover_enemy) and root.hover_enemy.hp > 0:
			mlist.append({"p": root.hover_enemy.global_position, "t": "敌机", "c": Color(1.0, 0.35, 0.3)})
		var rim := minf(vp.x, vp.y) * 0.42
		for m in mlist:
			var wp: Vector3 = m["p"]
			var behind: bool = root.cam.is_position_behind(wp)
			var sp: Vector2 = root.cam.unproject_position(wp)
			var sdir := sp - c
			if behind:
				sdir = -sdir
			var off: bool = behind or sdir.length() > minf(vp.x, vp.y) * 0.45
			if off:
				sdir = sdir.normalized()
				sp = c + sdir * rim
			var txt: String = m["t"]   # v2.7: 距离数字已在标签里(统一真实千米), 不再追加游戏坐标距离
			var mc2: Color = m["c"]
			var r2 := 6.0
			draw_polyline(PackedVector2Array([sp + Vector2(0, -r2), sp + Vector2(r2, 0), sp + Vector2(0, r2), sp + Vector2(-r2, 0), sp + Vector2(0, -r2)]), mc2, 1.6)
			draw_string(ThemeDB.fallback_font, sp + Vector2(10, -8), txt, HORIZONTAL_ALIGNMENT_LEFT, 140, 12, mc2)
			if off:
				var tangent := sdir.orthogonal()
				draw_line(sp + tangent * 5.0, sp + sdir * 14.0, mc2, 2.0)
				draw_line(sp - tangent * 5.0, sp + sdir * 14.0, mc2, 2.0)
		# 来袭预警环(参考吃鸡声音指示器:椭圆环 + 八方位红色扇区,亮=越紧急)
		var lv := {}
		var warn_t := float(root._b("enemy", "warn_time"))
		for b in root.enemy_bolts:
			var bmi: MeshInstance3D = b["mi"]
			if not is_instance_valid(bmi):
				continue
			var eta := float(b.get("eta", -1.0))
			if eta < 0.0 or eta > warn_t:
				continue
			var bp: Vector3 = bmi.global_position
			var scr2: Vector2
			if root.cam.is_position_behind(bp):
				scr2 = vp * 0.5 - (root.cam.unproject_position(bp) - vp * 0.5)
			else:
				scr2 = root.cam.unproject_position(bp)
			if scr2.distance_to(c) < 4.0:
				continue
			var ang := (scr2 - c).angle()
			var sector := wrapi(int(round(ang / (PI * 0.25))), 0, 8)
			var inten := 1.0 - eta / warn_t
			lv[sector] = maxf(float(lv.get(sector, 0.0)), inten)
		if lv.size() > 0:
			var rx := minf(vp.x, vp.y) * 0.33
			var ry := rx * 0.82
			var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.02)
			for k in lv:
				var a0 := float(k) * PI * 0.25 - PI * 0.17
				var a1 := float(k) * PI * 0.25 + PI * 0.17
				var pts := PackedVector2Array()
				var steps := 10
				for st in steps + 1:
					var a2 := lerpf(a0, a1, float(st) / float(steps))
					pts.append(c + Vector2(cos(a2) * rx, sin(a2) * ry))
				var wc := Color(1.0, 0.16, 0.1, (0.25 + 0.65 * float(lv[k])) * pulse)
				draw_polyline(pts, wc, 5.0)

		# v0.8:补给舱内倒计时大字
		if root.phase == 5:
			var sct := "补给适配中 %d s" % int(ceil(maxf(root.supply_t, 0.0)))
			draw_string(ThemeDB.fallback_font, Vector2(c.x - 150.0, vp.y * 0.32), sct, HORIZONTAL_ALIGNMENT_CENTER, 300, 26, Color(0.4, 1.0, 0.9, 0.95))
			draw_string(ThemeDB.fallback_font, Vector2(c.x - 150.0, vp.y * 0.32 + 24.0), "机体 2m→0.8m 级 · HP 已修复", HORIZONTAL_ALIGNMENT_CENTER, 300, 13, Color(0.6, 1.0, 0.9, 0.8))
		# ===== v0.8 高科技损伤度仪表盘(唯一常驻状态:结构完整度)=====
		var fnt3 := ThemeDB.fallback_font
		var integrity := clampf(float(root.hp) / maxf(float(root.hp_max), 1.0), 0.0, 1.0)
		var dmg_frac := 1.0 - integrity
		var dw := 360.0
		var dh := 48.0
		var dx := c.x - dw * 0.5
		var dy := vp.y - dh - 30.0
		draw_rect(Rect2(dx, dy, dw, dh), Color(0.01, 0.05, 0.045, 0.6))
		# 四角科技刻线
		var tkl := 11.0
		var ac := Color(0.4, 1.0, 0.9, 0.9)
		for corner in [Vector2(dx, dy), Vector2(dx + dw, dy), Vector2(dx, dy + dh), Vector2(dx + dw, dy + dh)]:
			var sx2 := -1.0 if corner.x > c.x else 1.0
			var sy2 := -1.0 if corner.y > c.y else 1.0
			draw_line(corner, corner + Vector2(tkl * sx2, 0), ac, 2.0)
			draw_line(corner, corner + Vector2(0, tkl * sy2), ac, 2.0)
		# 分段损伤条(24 段):损伤从左往右点亮,未损段暗绿
		var segs := 24
		var gap := 2.0
		var seg_w := (dw - 24.0 - gap * float(segs - 1)) / float(segs)
		var lit := int(ceil(dmg_frac * float(segs)))
		for i in segs:
			var sx := dx + 12.0 + float(i) * (seg_w + gap)
			var sy := dy + 22.0
			if i < lit:
				var sc := Color(1.0, 0.22, 0.12) if dmg_frac > 0.6 else (Color(1.0, 0.6, 0.1) if dmg_frac > 0.3 else Color(0.95, 0.35, 0.2))
				draw_rect(Rect2(sx, sy, seg_w, 9.0), sc)
			else:
				draw_rect(Rect2(sx, sy, seg_w, 9.0), Color(0.25, 0.75, 0.55, 0.45))
		draw_string(fnt3, Vector2(dx + 12.0, dy + 15.0), "结构完整度", HORIZONTAL_ALIGNMENT_LEFT, 120, 10, Color(0.5, 1.0, 0.85, 0.85))
		draw_string(fnt3, Vector2(dx + dw - 86.0, dy + 16.0), "%d%%" % int(round(integrity * 100.0)), HORIZONTAL_ALIGNMENT_RIGHT, 74, 13, Color(0.7, 1.0, 0.9))
		if integrity < 0.3 and Time.get_ticks_msec() % 800 < 400:
			draw_rect(Rect2(dx - 2.0, dy - 2.0, dw + 4.0, dh + 4.0), Color(1.0, 0.2, 0.12, 0.85), false, 2.0)
		# 武器状态行(机炮常开/等离子/散弹/激光充能)+ 语音指示
		var wy := dy - 16.0
		draw_string(fnt3, Vector2(dx + 12.0, wy), "机炮·自动", HORIZONTAL_ALIGNMENT_LEFT, 90, 11, Color(0.5, 1.0, 0.8))
		draw_string(fnt3, Vector2(dx + 112.0, wy), "等离子·就绪" if root.plasma_cd <= 0.0 else "等离子·装填", HORIZONTAL_ALIGNMENT_LEFT, 110, 11, Color(1.0, 0.75, 0.4))
		if root._spread_unlocked():
			draw_string(fnt3, Vector2(dx + 222.0, wy), "散弹·就绪", HORIZONTAL_ALIGNMENT_LEFT, 100, 11, Color(1.0, 0.65, 0.5))
		if root._missile_unlocked():
			var ltxt := ("导弹●就绪" if root.missile_cd <= 0.0 else "导弹…%.1fs" % root.missile_cd)
			draw_string(fnt3, Vector2(dx + 322.0, wy), ltxt, HORIZONTAL_ALIGNMENT_LEFT, 140, 11, Color(0.4, 0.9, 1.0))
		var vtxt := "语音 ●" if root._voice_rec else "语音 ○"
		draw_string(fnt3, Vector2(dx + dw - 64.0, wy), vtxt, HORIZONTAL_ALIGNMENT_LEFT, 70, 11, Color(0.95, 0.9, 0.4, 0.9) if root._voice_rec else Color(0.6, 0.6, 0.6, 0.6))
		if root.marker_valid:
			var mp: Vector3 = root.marker_pos
			var scr2: Vector2
			if root.cam.is_position_behind(mp):
				scr2 = vp * 0.5 - (root.cam.unproject_position(mp) - vp * 0.5)
			else:
				scr2 = root.cam.unproject_position(mp)
			var clamped := false
			if scr2.x < 40.0 or scr2.y < 40.0 or scr2.x > vp.x - 40.0 or scr2.y > vp.y - 40.0:
				scr2 = Vector2(clampf(scr2.x, 40.0, vp.x - 40.0), clampf(scr2.y, 40.0, vp.y - 40.0))
				clamped = true
			var mc2 := Color(0.4, 1.0, 0.9, 0.95)
			var dsz := 26.0
			draw_line(scr2 + Vector2(0, -dsz), scr2 + Vector2(dsz, 0), mc2, 2.0)
			draw_line(scr2 + Vector2(dsz, 0), scr2 + Vector2(0, dsz), mc2, 2.0)
			draw_line(scr2 + Vector2(0, dsz), scr2 + Vector2(-dsz, 0), mc2, 2.0)
			draw_line(scr2 + Vector2(-dsz, 0), scr2 + Vector2(0, -dsz), mc2, 2.0)
			var fnt2 := ThemeDB.fallback_font
			draw_string(fnt2, scr2 + Vector2(0, dsz + 16), "核心 %s%s" % [root._dist_real(mp.distance_to(root.cam.global_position)), " ▸" if clamped else ""], HORIZONTAL_ALIGNMENT_CENTER, 120, 12, mc2)
		# v0.8:锁定括号只给准星压到的敌机(其余时间只锁定主目标核心)
		for e in ([root.hover_enemy] if is_instance_valid(root.hover_enemy) and root.hover_enemy.hp > 0 else []):
			if not is_instance_valid(e):
				continue
			var wp: Vector3 = e.global_position
			if root.cam.is_position_behind(wp):
				continue
			var sp: Vector2 = root.cam.unproject_position(wp)
			if sp.x < -50 or sp.y < -50 or sp.x > vp.x + 50 or sp.y > vp.y + 50:
				continue
			var d := wp.distance_to(root.cam.global_position)
			var sz := clampf(1600.0 / maxf(d, 1.0), 10.0, 46.0)
			var bc := Color(1.0, 0.45, 0.3, 0.85) if d < 200.0 else Color(1.0, 0.8, 0.4, 0.6)
			if root.auto_fire and root.lock_target != null and e == root.lock_target:
				bc = Color(0.4, 1.0, 0.6, 0.95)
			var p1 := sp + Vector2(-sz, -sz) * 0.5
			var p2 := sp + Vector2(sz, -sz) * 0.5
			var p3 := sp + Vector2(sz, sz) * 0.5
			var p4 := sp + Vector2(-sz, sz) * 0.5
			var L := sz * 0.35
			draw_line(p1, p1 + Vector2(L, 0), bc, 1.5)
			draw_line(p1, p1 + Vector2(0, L), bc, 1.5)
			draw_line(p2, p2 + Vector2(-L, 0), bc, 1.5)
			draw_line(p2, p2 + Vector2(0, L), bc, 1.5)
			draw_line(p3, p3 + Vector2(-L, 0), bc, 1.5)
			draw_line(p3, p3 + Vector2(0, -L), bc, 1.5)
			draw_line(p4, p4 + Vector2(L, 0), bc, 1.5)
			draw_line(p4, p4 + Vector2(0, -L), bc, 1.5)
			var font := ThemeDB.fallback_font
			draw_string(font, sp + Vector2(-sz * 0.5, sz * 0.5 + 14), "锁定 " + root._dist_real(d), HORIZONTAL_ALIGNMENT_CENTER, sz, 11, Color(0.4, 1.0, 0.6, 0.95))

# ==================== 太阳眩光探针(-- --sunprobe [mode=ring|grid] [mask=...])====================
func _sunprobe_run() -> void:
	print("SUNPROBE START pos=%s mask=%s" % [str(cam.global_position), probe_mask])
	var geo_e: Vector3 = earth_pos - cam.global_position
	var geo_s := (-cam.global_position).normalized()
	print("SUNPROBE GEO earth_pos=%s arena=%s | earth_dist=%.0f earth_ang=%.2f sun-vs-earth=%.2f deg" % [str(earth_pos), str(arena_anchor), geo_e.length(), rad_to_deg(asin(clampf(_pr(1.0) / maxf(geo_e.length(), 0.001), 0.0, 1.0))), rad_to_deg(acos(clampf(geo_e.normalized().dot(geo_s), -1.0, 1.0)))])
	for c in get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false   # HUD 不进统计
	for e in enemies:
		if is_instance_valid(e):
			(e as Node).queue_free()
	enemies.clear()
	_apply_probe_mask()
	await get_tree().process_frame
	var uargs := " ".join(OS.get_cmdline_user_args())
	var ring := uargs.contains("mode=ring")
	var grid := uargs.contains("mode=grid")
	var last := -1.0
	var jumps := 0
	var last_img: Image = null
	if grid:
		# 网格:每行固定 pitch,扫全周 1°;阈值 0.003;跳变处存前后帧 PNG
		for pit in [-30.0, -15.0, 0.0, 15.0, 30.0]:
			last = -1.0
			var row_j := 0
			for k in 360:
				_yaw = deg_to_rad(float(k))
				_pitch = deg_to_rad(pit)
				vel = Vector3.ZERO
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var img: Image = get_viewport().get_texture().get_image()
				if img.get_format() != Image.FORMAT_RGBA8:
					img.convert(Image.FORMAT_RGBA8)
				var st := _probe_img_stats(img)
				var d := absf(st[0] - last)
				if last >= 0.0 and d > 0.003:
					print("SUNPROBE GRID pitch=%+5.1f yaw=%3d-%3d mean %.4f->%.4f JUMP %.4f ctr %.4f->%.4f" % [pit, (k + 359) % 360, k, last, st[0], d, _last_ctr, st[4]])
					row_j += 1
					jumps += 1
					if jumps <= 4 and last_img != null:
						last_img.save_png("user://grid_before_%02d.png" % jumps)
						img.save_png("user://grid_after_%02d.png" % jumps)
					row_j = 0
				last = st[0]
				_last_ctr = st[4]
				last_img = img
			print("SUNPROBE GRIDROW pitch=%+5.1f done" % pit)
	elif ring:
		for k in 1440:
			_yaw = deg_to_rad(float(k) * 0.25)
			_pitch = 0.0
			vel = Vector3.ZERO
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img: Image = get_viewport().get_texture().get_image()
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			var st := _probe_img_stats(img)
			var d := absf(st[0] - last)
			if last >= 0.0 and d > 0.008:
				print("SUNPROBE off=%+8.2f mean=%.4f ctr=%.4f hot=%.5f p95=%.3f  <== JUMP %.3f" % [float(k) * 0.25, st[0], st[4], st[1], st[2], d])
				jumps += 1
			last = st[0]
	else:
		var offs: Array = []
		var k2 := -55
		while k2 <= 55:
			offs.append(float(k2))
			k2 += 1
		k2 = -20
		while k2 <= 20:
			offs.append(float(k2) * 0.05)
			k2 += 1
		for off in offs:
			var sun_dir := (-cam.global_position).normalized()
			_yaw = atan2(-sun_dir.x, -sun_dir.z) + deg_to_rad(off)
			_pitch = asin(clampf(sun_dir.y, -1.0, 1.0))
			vel = Vector3.ZERO
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img: Image = get_viewport().get_texture().get_image()
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			var st := _probe_img_stats(img)
			var d := absf(st[0] - last)
			var mark := ""
			if last >= 0.0 and d > 0.008:
				mark = "  <== JUMP %.3f" % d
				jumps += 1
			print("SUNPROBE off=%+8.2f mean=%.4f ctr=%.4f hot=%.5f p95=%.3f%s" % [off, st[0], st[4], st[1], st[2], mark])
			last = st[0]
	print("SUNPROBE DONE jumps=%d" % jumps)
	get_tree().quit()

func _apply_probe_mask() -> void:
	if probe_mask == "":
		return
	var hide_neb := probe_mask.contains("nonebulae") or probe_mask.contains("bare")
	var hide_star := probe_mask.contains("nostars") or probe_mask.contains("bare")
	var hide_sun := probe_mask.contains("nosun") or probe_mask.contains("bare")
	var hide_sky := probe_mask.contains("nosky") or probe_mask.contains("bare")
	for c in get_children():
		if c is MultiMeshInstance3D:
			var mm_mat = (c as MultiMeshInstance3D).material_override
			if hide_star and mm_mat is ShaderMaterial and (mm_mat as ShaderMaterial).shader.resource_path.find("star_billboard") >= 0:
				(c as MultiMeshInstance3D).visible = false
		elif c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var mat = mi.material_override
			if mat is ShaderMaterial:
				if hide_neb and (mat as ShaderMaterial).shader.resource_path.find("nebula_billboard") >= 0:
					mi.visible = false
			elif hide_sun and mi.global_position.length() < 1.0:
				mi.visible = false
		elif c is WorldEnvironment and hide_sky:
			var we := c as WorldEnvironment
			we.environment.background_mode = Environment.BG_COLOR
			we.environment.background_color = Color(0, 0, 0)
			we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			we.environment.ambient_light_color = Color(0, 0, 0)
			we.environment.ambient_light_energy = 0.0

func _probe_img_stats(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	var n := 0
	var sum := 0.0
	var hot := 0
	var cx0 := int(w * 0.35)
	var cx1 := int(w * 0.65)
	var cy0 := int(h * 0.35)
	var cy1 := int(h * 0.65)
	var nc := 0
	var sumc := 0.0
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var o := (y * w + x) * 4
			var lum := (d[o] + d[o + 1] + d[o + 2]) / 765.0
			sum += lum
			n += 1
			if lum > 0.90:
				hot += 1
			if x >= cx0 and x < cx1 and y >= cy0 and y < cy1:
				sumc += lum
				nc += 1
			x += 8
		y += 8
	return [sum / float(n), float(hot) / float(n), 0.75, 1.0, sumc / float(nc)]

# ==================== 语音命令接口层实现(v6.12)====================
# ===== EVA shipboard voice-broadcast channel (v0.9.10) =====
# All _feed call sites (wave/core/level/overheat/voice feedback...) broadcast here;
# static lines + word library live in aigc_demo_framework/eva_broadcasts.json
# (single source of truth, TTS pre-synthesis uses the same file).
# Voice entry: voice_intent.py eva_intents.classify_eva -> eva_query/eva_repeat/eva_mute.
var _eva_mute := false
var _eva_last := ""
var _eva_lines := {}

func _eva_lib() -> Dictionary:
	if _eva_lines.is_empty():
		# 台词库由配套项目 aigc-game-framework 提供（本仓库不内置该文件）：
		# 用环境变量 EVA_BROADCASTS 指向它，或把文件放到 <项目>/data/eva_broadcasts.json。
		# 取不到时 FileAccess.open 返回 null，下面走 push_warning + 内置 fallback 文案。
		var path := OS.get_environment("EVA_BROADCASTS")
		if path == "":
			path = "res://data/eva_broadcasts.json"
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parser := JSON.new()
			if parser.parse(f.get_as_text()) == OK and parser.data is Dictionary:
				_eva_lines = parser.data
			f.close()
		else:
			push_warning("[EVA] lib missing: " + path)
	return _eva_lines

func _eva_line(group: String, key: String, fallback: String) -> String:
	var g = _eva_lib().get(group, {})
	if g is Dictionary:
		var arr = g.get(key, [])
		if arr is Array and (arr as Array).size() > 0:
			return str((arr as Array)[0])
	return fallback

func _eva_say(s: String, force := false) -> void:
	if s == "" or (_eva_mute and not force):
		return
	_eva_last = s
	print("[EVA] ", s)   # text channel (HUD removed); TODO TTS: hit eva_audio/ cache or synth then play

func _eva_phase_hint() -> String:
	match phase:
		1: return "BOSS 已现身, 摧毁核心即可通关"
		2: return "结算中: [1-3]能力树 [4-6]改造, [Enter]跃迁下一关"
		3: return "任务失败, 等待重试"
		4: return "返航!飞入虫洞(高斯球)内部完成跃迁"
		6: return "虫洞跃迁中"
		7: return "全任务完成"
		_: return "击毁 %d 架后核心现身" % maxi(quota - kills, 0)


# ===== v7.0 EVA 语音: AI 机械女声缓存(eva_tts.py 预合成)优先, SAPI 实时兜底; 字幕同步 =====
func _eva_announce(s: String, force := true) -> void:
	_eva_say(s, force)
	if s == "":
		return
	DisplayServer.window_set_title("[EVA] " + s.substr(0, 70))
	_sub_transient("EVA", s)
	_eva_speak_text(s)

func _eva_announce_key(key: String, force := true) -> void:
	_eva_announce(_eva_key_text(key), force)

func _eva_key_text(key: String) -> String:
	var bk: Dictionary = _eva_manifest.get("by_key", {})
	var e: Dictionary = bk.get(key, {}) if bk.get(key, {}) is Dictionary else {}
	if not e.is_empty():
		return str(e.get("text", ""))
	return ""   # 未知 key → 空串(播报自动跳过)

func _load_eva_manifest() -> void:
	var f := FileAccess.open("res://assets/eva/manifest.json", FileAccess.READ)
	if f == null:
		push_warning("[EVA] manifest 缺失 — 语音回落 SAPI")
		return
	var parser := JSON.new()
	if parser.parse(f.get_as_text()) == OK and parser.data is Dictionary:
		_eva_manifest = parser.data
	f.close()
	var n: int = (_eva_manifest.get("by_key", {}) as Dictionary).size()
	print("[EVA] manifest 台词 %d 条 %s" % [n, "(OK)" if n > 0 else "(空)"])

func _eva_speak_text(s: String) -> float:
	# 播台词: 缓存命中 → 机械女声 wav(返回音频时长); 未命中 → SAPI 异步(返回 0, 字幕按文本长度估时)
	_eva_voice_len = 0.0
	if s == "":
		return 0.0
	var t2w: Dictionary = _eva_manifest.get("text_to_wav", {})
	var wav_name := str(t2w.get(s, ""))
	if wav_name != "":
		var path := "res://assets/eva/" + wav_name
		if ResourceLoader.exists(path):
			var st: AudioStreamWAV = load(path)
			if st != null:
				_eva_voice.stream = st
				_eva_voice.play()
				_eva_voice_len = st.get_length()
				return _eva_voice_len
	_eva_voice_len = 0.0
	var safe := s.replace("'", "''")
	OS.create_process("powershell", ["-NoProfile", "-Command",
			"Add-Type -AssemblyName System.Speech; $s = New-Object System.Speech.Synthesis.SpeechSynthesizer; $s.Rate = 2; $s.Speak('" + safe + "')"])
	return 0.0


# ==================== v7.0 剧情系统: 字幕条 + 单选项(打字机 + 语音驱动停留时长) ====================
func _story_play(seq: Array) -> void:
	for it in seq:
		_story_q.append(it)
	if not _story_on:
		_story_next()

func _story_next() -> void:
	if _story_q.is_empty():
		_story_clear()
		return
	var it: Dictionary = _story_q.pop_front() if _story_q[0] is Dictionary else {}
	_story_on = true
	_story_t = 0.0
	_story_choice = bool(it.get("choice", false))
	var tx := str(it.get("tx", ""))
	var voice := str(it.get("voice", ""))
	var vlen := _eva_speak_text(_eva_key_text(voice)) if voice != "" else 0.0
	_story_wait = maxf(2.8, tx.length() * 0.14) + vlen
	_sub_show(str(it.get("sp", "")), tx, _story_choice)
	if bool(it.get("done", false)):
		_demo_done = true   # 该行播完 → 通关画面

func _story_tick(dt: float) -> void:
	if not _story_on:
		return
	_story_t += dt
	_sub_lbl.visible_characters = mini(int(_story_t * 22.0), _sub_tx.length())
	if _story_choice:
		if autotest and _story_t > 1.0:
			_story_advance()   # 无人值守: 自动应答
		return
	if _story_t >= _story_wait or (autotest and _story_t > 0.8):
		if _demo_done and _story_q.is_empty():
			_demo_complete_show()
			return
		_story_next()

func _story_advance() -> void:
	# 选项应答 / 快进(1 / E / 空格 / 点击)
	if not _story_on:
		return
	_play_sfx("lock", -8.0, 1.25)
	if _demo_done and _story_q.is_empty():
		_demo_complete_show()
		return
	_story_next()

func _story_clear() -> void:
	_story_q.clear()
	_story_on = false
	_story_choice = false
	_demo_done = false
	_sub_hide()

func _sub_show(sp: String, tx: String, choice := false) -> void:
	if _sub_lbl == null:
		return
	_sub_sp.text = sp
	_sub_sp.visible = sp != ""
	_sub_tx = tx + ("    [1] 应答" if choice else "")
	_sub_lbl.text = _sub_tx
	_sub_lbl.visible_characters = 0
	_sub_lbl.visible = true
	_sub_sp.visible = true if sp != "" else false

func _sub_transient(sp: String, tx: String) -> void:
	# 事件播报字幕: 剧情进行中让位, 平时显示数秒
	if _story_on:
		return
	_sub_show(sp, tx, false)
	_sub_shown = maxf(2.6, tx.length() * 0.12)

func _sub_hide() -> void:
	if _sub_lbl != null:
		_sub_lbl.visible = false
	if _sub_sp != null:
		_sub_sp.visible = false
	_sub_shown = 0.0


# ==================== v7.0 BGM: NotaGen AI 古典曲库 + 双播放器交叉淡化 + EVA ducking ====================
const MUSIC_TABLE := {
	"battle": ["res://assets/music/bgm_battle.wav", "res://assets/music/bgm_battle_fallback.wav"],
	"boss": ["res://assets/music/bgm_boss.wav", "res://assets/music/bgm_boss_fallback.wav"],
	"calm": ["res://assets/music/bgm_calm.wav"],
	"finale": ["res://assets/music/bgm_finale.wav"],
}

func _setup_music() -> void:
	_mus_a = AudioStreamPlayer.new()
	_mus_a.volume_db = -40.0
	add_child(_mus_a)
	_mus_b = AudioStreamPlayer.new()
	_mus_b.volume_db = -40.0
	add_child(_mus_b)
	_eva_voice = AudioStreamPlayer.new()
	_eva_voice.volume_db = 5.0   # v7.10:EVA 音量提升, 盖过加大的 BGM
	add_child(_eva_voice)
	print("[MUSIC] BGM 就绪: battle/boss/calm/finale(NotaGen AI 古典曲库)")

func _mus_stream(key: String) -> AudioStream:
	if _mus_lib.has(key):
		return _mus_lib[key]
	for p in MUSIC_TABLE.get(key, []):
		if ResourceLoader.exists(p):
			var st: AudioStreamWAV = load(p)
			if st != null:
				st.loop_mode = AudioStreamWAV.LOOP_FORWARD
				st.loop_begin = 0
				st.loop_end = st.data.size() / 2   # 16bit mono: 2B/帧 → 循环整个曲子
				_mus_lib[key] = st
				return st
	return null

func _music_play(key: String, _fade := 2.5) -> void:
	if key == _mus_cur:
		return
	var st := _mus_stream(key)
	if st == null:
		print("[MUSIC] 缺曲目: ", key)
		return
	_mus_cur = key
	_mus_fade = 0.0
	_mus_cur_p = _mus_b if _mus_cur_p == _mus_a else _mus_a
	_mus_cur_p.stream = st
	_mus_cur_p.volume_db = -40.0
	_mus_cur_p.play()
	print("[MUSIC] -> ", key)

func _music_tick(dt: float) -> void:
	if _mus_cur_p == null:
		return
	_mus_fade = minf(_mus_fade + dt / 2.5, 1.0)
	var duck: bool = _eva_voice != null and _eva_voice.playing   # EVA 播报自动压低音乐
	var target := lerpf(-40.0, -8.0 if duck else 3.0, _mus_fade)
	_mus_cur_p.volume_db = lerpf(_mus_cur_p.volume_db, target, clampf(dt * 2.5, 0.0, 1.0))
	for p in [_mus_a, _mus_b]:
		if p != _mus_cur_p and p.playing:
			p.volume_db = lerpf(p.volume_db, -40.0, clampf(dt * 2.5, 0.0, 1.0))
			if p.volume_db < -37.0:
				p.stop()
				p.stream = null

func _ui_tick(dt: float) -> void:
	# 事件字幕超时 / 设施血条 / BGM 状态跟随 / 结算闪光淡出
	if not _story_on and _sub_lbl != null and _sub_lbl.visible and _sub_shown > 0.0:
		_sub_shown -= dt
		if _sub_shown <= 0.0:
			_sub_hide()
	if _fac_bar_bg != null:
		var show := level == 2 and phase < 3 and radar_ring != null and is_instance_valid(radar_ring) and not dead
		_fac_bar_bg.visible = show
		_fac_lbl.visible = show
		if show:
			var rhp: float = (radar_ring as Object).get("hp")
			var rhmax: float = maxf(float((radar_ring as Object).get("hp_max")), 1.0)
			var fr := clampf(rhp / rhmax, 0.0, 1.0)
			_fac_bar.visible = true
			_fac_bar.position = Vector2(2, 2)
			_fac_bar.size = Vector2((_fac_bar_bg.size.x - 4.0) * fr, _fac_bar_bg.size.y - 4.0)
			_fac_bar.color = Color(0.3, 1.0, 0.55) if fr > 0.6 else (Color(1.0, 0.65, 0.15) if fr > 0.3 else Color(1.0, 0.3, 0.35))
			_fac_lbl.text = "雷达相阵 结构 %d%%" % int(fr * 100.0)
	if _ack_lbl != null and _ack_lbl.visible:
		_ack_ttl -= dt
		_ack_lbl.modulate.a = clampf(_ack_ttl, 0.0, 1.0)
		if _ack_ttl <= 0.0:
			_ack_lbl.visible = false
	if _boss_bar_bg != null:
		var bshow: bool = level == 3 and boss != null and is_instance_valid(boss) and phase == 1 and not dead
		_boss_bar_bg.visible = bshow
		_boss_lbl.visible = bshow
		if bshow:
			var bf := clampf(core_hp / maxf(core_hp_max, 1.0), 0.0, 1.0)
			_boss_bar.size = Vector2(maxf((_boss_bar_bg.size.x - 6.0) * bf, 0.0), _boss_bar_bg.size.y - 6.0)
			_boss_bar.color = Color(1.0, 0.28, 0.32) if bf > 0.5 else (Color(1.0, 0.55, 0.18) if bf > 0.25 else Color(0.95, 0.20, 0.70))
			_boss_lbl.text = "⚠ 八棱柱集群 · 湮灭核心  %d / %d" % [maxi(int(core_hp), 0), int(core_hp_max)]
			for k in _boss_notches.size():
				(_boss_notches[k] as ColorRect).position = Vector2(3.0 + (k + 1) * (_boss_bar_bg.size.x - 6.0) / 10.0, 2.0)
	var want := ""
	if _final_whale or phase == 7:
		want = "finale"
	elif phase == 2:
		want = "calm"
	elif level >= 3:
		want = "boss"
	else:
		want = "battle"
	if want != _mus_cur:
		_music_play(want, 2.5)
	if phase == 2 and _flash_rect != null and _flash_rect.color.a > 0.0:
		_flash_rect.color.a = maxf(_flash_rect.color.a - dt * 1.5, 0.0)


# ==================== v7.0 虫洞跃迁 / 结算画面 / 通关画面 ====================
func _wormhole_jump() -> void:
	# 返航进入中转站核心 = 穿越虫洞 → 结算画面
	if _worm_t >= 0.0 or phase == 6:
		return
	phase = 6
	_worm_t = 0.0
	_story_clear()
	_play_sfx("gate", -2.0, 0.85)
	_eva_announce_key("wormhole", true)

func _settlement_open() -> void:
	# 虫洞抵达 → 结算画面(升级购买后跃迁下一关)
	phase = 2
	_worm_t = -1.0
	hp = hp_max
	_hide_gate_core()
	_music_play("calm", 2.0)
	var mission_name := "歼灭战" if level == 1 else ("保卫战" if level == 2 else "BOSS战")
	_result_lbl.text = _settlement_text()   # v7.1:能力树+改造 双轨升级界面
	_result_panel.visible = true
	_feed("任务通过!资源结算完成 — 强化或直接跃迁")

func _demo_complete_show() -> void:
	# 终局剧情播毕 → 通关画面
	phase = 7
	_demo_done = false
	_story_clear()
	_result_panel.visible = false
	_complete_lbl.text = "★ 全 任 务 完 成 ★\n\n歼灭战 · 保卫战 · BOSS战 —— 全部达成\n总击毁 %d     最终资源 %d\n\n星鲸仍在深空歌唱……\n\n[R] 重新开始      [Esc] 退出" % [total_kills, parts]
	_complete_panel.visible = true
	_music_play("finale", 3.0)
	_feed("全任务完成 — 感谢试玩三关 Demo!")

# ==================== v7.0 L2 援军小剧情 ====================
func _l2_reinforce_cutscene() -> void:
	# 中途援军抵达: 跃迁闪光 + 僚机参战 + 字幕剧情 + EVA 自动语音播报
	_flash_rect.color = Color(0.5, 0.85, 1.0, 0.0)
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color:a", 0.55, 0.28)
	tw.tween_property(_flash_rect, "color:a", 0.0, 0.9)
	_play_sfx("gate", -6.0, 1.6)
	_spawn_wingmen()
	_feed("📡 增援中队跳跃抵达战区!")
	_eva_announce_key("l2_reinf", true)
	_story_play([
		{"sp": "僚机频道", "tx": "这里是游侠中队——收到求援信号，跳跃完成，我们已就位！"},
		{"sp": "EVA", "tx": _eva_key_text("l2_reinf_eva"), "voice": "l2_reinf_eva"},
	])

func _iface_eva_query(params: Dictionary) -> String:
	var topic := str(params.get("topic", "ack"))
	var text := ""
	if topic == "mission":
		text = _eva_line("queries", "mission", "第 {level} 关, 击毁 {kills}/{quota}, {phase_hint}").format({
			"level": level, "kills": kills, "quota": quota, "phase_hint": _eva_phase_hint()})
	elif topic == "status":
		text = _eva_line("queries", "status", "HP {hp}/{hp_max}, 第 {level} 关").format({
			"hp": hp, "hp_max": hp_max, "level": level, "kills": kills,
			"res_hint": "升级费用 %d 资源/项" % _bi("economy", "upgrade_cost")})
	elif topic == "resources":
		text = _eva_line("queries", "resources", "{res_hint}").format({
			"res_hint": "升级费用 %d 资源/项, 过关获取资源" % _bi("economy", "upgrade_cost")})
	elif topic == "help":
		text = _eva_line("queries", "help", "能做: 查询当前任务、汇报战况、播报资源、再说一遍、安静、恢复播报, 显示隐藏轨迹圈")
	elif topic == "unknown":
		text = _eva_line("queries", "unknown", "没听懂。可以问: 当前任务、战况、资源, 或说帮助").format({
			"heard": str(params.get("heard", ""))})
	else:
		text = _eva_line("queries", "ack", "EVA 在线。说 EVA 查询当前任务 试试。")
	_eva_announce(text)
	return "topic=%s" % topic

func _iface_eva_repeat(_params: Dictionary) -> String:
	if _eva_last == "":
		_eva_announce(_eva_line("control", "repeat_none", "EVA 还没有播报过内容。"))
	else:
		_eva_announce(_eva_last)
	return "repeated=%s" % str(_eva_last != "")

func _iface_eva_mute(params: Dictionary) -> String:
	var on: bool = params.get("on", true)
	if on:
		_eva_announce(_eva_line("control", "mute_on", "EVA 已静音, 说 EVA 恢复播报 解除。"))
		_eva_mute = true
	else:
		_eva_mute = false
		_eva_announce(_eva_line("control", "mute_off", "EVA 恢复播报。"))
	return "mute=%s" % str(on)


func _register_cmd_interfaces() -> void:
	# 新接口在此注册: command_type -> 处理函数; Python 意图表对应写命令即可路由到这
	_cmd_interfaces["set_orbit_lines"] = Callable(self, "_iface_set_orbit_lines")
	_cmd_interfaces["set_time_scale"] = Callable(self, "_iface_set_time_scale")   # v0.9: 星历时标(1=真实)
	_cmd_interfaces["toggle_orbit_lines"] = Callable(self, "_iface_toggle_orbit_lines")
	_cmd_interfaces["notify"] = Callable(self, "_iface_notify")
	_cmd_interfaces["teleport"] = Callable(self, "_iface_teleport")
	_cmd_interfaces["dbg_planet"] = Callable(self, "_iface_dbg_planet")   # 调试: 行星LOD可见性   # v6.16 语音传送
	_cmd_interfaces["eva_query"] = Callable(self, "_iface_eva_query")
	_cmd_interfaces["eva_repeat"] = Callable(self, "_iface_eva_repeat")
	_cmd_interfaces["eva_mute"] = Callable(self, "_iface_eva_mute")

func _iface_set_orbit_lines(params: Dictionary) -> String:
	var v: bool = params.get("visible", true)
	for mi in orbit_lines:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).visible = v
	_feed("轨迹圈 %s(%d 条)" % ["显示" if v else "隐藏", orbit_lines.size()])
	return "visible=%s n=%d" % [str(v), orbit_lines.size()]

func _iface_notify(params: Dictionary) -> String:
	var msg := str(params.get("text", ""))
	if msg != "":
		_feed(msg)
	return "shown: %s" % msg.substr(0, 40)

func _iface_set_time_scale(params: Dictionary) -> String:
	if params.has("scale"):
		solar_time_scale = maxf(float(params["scale"]), 0.0)
	_feed("星历时标 ×%g(1=真实速率)" % solar_time_scale)
	return "solar_time_scale=%g" % solar_time_scale

func _iface_teleport(params: Dictionary) -> String:
	# v6.16 传送: 即时把玩家挪到目标行星附近(星历实时位置), 可直接飞出来
	var tgt := str(params.get("target", ""))
	var cn := str(params.get("cn", tgt))
	for e in ephem_planets:
		if String(e["name"]) == tgt:
			var r: float = e["r"]
			var pos: Vector3 = (e["pos"] as Vector3) + Vector3(r * 2.5, r * 0.7, r * 1.2)
			cam.global_position = pos
			_play_sfx("gate", -4.0, 1.2)
			_feed("⚡ 跃迁完成 — 已抵达%s附近, 坐标(%s)" % [cn, str(pos).replace("(", "").replace(")", "")])
			return "teleported to " + tgt
	_feed("传送目标未找到: %s" % cn)
	return "target not found: " + tgt

func _iface_dbg_planet(params: Dictionary) -> String:
	var tgt := str(params.get("target", ""))
	for sp in planet_lods:
		if str(sp["name"]).find(tgt) >= 0:
			for k in ["hi", "mid", "lo"]:
				var nd: Node3D = sp[k]
				print("[DBG] %s %s vis=%s scale=%s pos=%s dist=%.0fm" % [str(sp["name"]), k, nd.visible, str(nd.scale), str(nd.global_position), cam.global_position.distance_to(nd.global_position)])
			print("[DBG] player=%s level=%d radius=%s" % [str(cam.global_position), int(sp["level"]), str(sp["radius"])])
			return "logged"
	return "no match"

func _iface_toggle_orbit_lines(_params: Dictionary) -> String:
	var v := true
	if orbit_lines.size() > 0 and is_instance_valid(orbit_lines[0]):
		v = not (orbit_lines[0] as MeshInstance3D).visible
	return _iface_set_orbit_lines({"visible": v})

func _load_cmd_executed() -> void:
	if not FileAccess.file_exists(CMD_EXECLOG):
		return
	var f := FileAccess.open(CMD_EXECLOG, FileAccess.READ)
	if f == null:
		return
	var parser := JSON.new()
	if parser.parse(f.get_as_text()) == OK and parser.data is Dictionary:
		for k in parser.data:
			_cmd_executed[str(k)] = true
	f.close()

func _poll_cmd_inbox() -> void:
	if not FileAccess.file_exists(CMD_INBOX):
		return
	var f := FileAccess.open(CMD_INBOX, FileAccess.READ)
	if f == null:
		return
	var lines: Array[String] = []
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line != "":
			lines.append(line)
	f.close()
	var cf := FileAccess.open(CMD_INBOX, FileAccess.WRITE)   # 先清空防重复执行
	if cf:
		cf.store_string("")
		cf.close()
	for line in lines:
		var parser := JSON.new()
		if parser.parse(line) != OK or not (parser.data is Dictionary):
			push_warning("[CMDSRV] bad line: %s" % line.substr(0, 60))
			continue
		_execute_cmd(parser.data)

func _execute_cmd(cmd: Dictionary) -> void:
	var ctype := str(cmd.get("command_type", ""))
	var cid := str(cmd.get("command_id", ""))
	if cid != "" and _cmd_executed.has(cid):
		print("[CMDSRV] skip duplicate: ", cid)
		return
	if cid != "":
		_cmd_executed[cid] = true
		var ef := FileAccess.open(CMD_EXECLOG, FileAccess.WRITE)
		if ef:
			ef.store_string(JSON.stringify(_cmd_executed))
			ef.close()
	if _cmd_interfaces.has(ctype):
		var res: String = (_cmd_interfaces[ctype] as Callable).call(cmd.get("params", {}))
		print("[CMDSRV] %s -> %s" % [ctype, res])
		if not ctype.begins_with("eva_") and ctype != "dbg_planet":
			_eva_ack()   # v7.10:查询/播报类指令不应答(收到已完成)
	else:
		push_warning("[CMDSRV] unknown command_type: %s" % ctype)

func _setup_voice() -> void:
	# 专用总线 + capture(移植自 valley voice_input.gd; 指示走 _feed, 不另建 UI)
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "VoiceRec")
	AudioServer.set_bus_send(idx, "Master")
	_voice_effect = AudioEffectCapture.new()
	AudioServer.add_bus_effect(idx, _voice_effect)
	_voice_player = AudioStreamPlayer.new()
	_voice_player.stream = AudioStreamMicrophone.new()
	_voice_player.bus = "VoiceRec"
	add_child(_voice_player)
	DirAccess.make_dir_recursive_absolute("user://voice")
	print("[VOICE] 就绪: 按住 V 说话松开转写(需 Python voice_intent.py --project gdgs_lab)")

func _voice_start() -> void:
	if _voice_rec or _voice_effect == null:
		return
	while _voice_effect.get_frames_available() > 0:   # 清积压
		_voice_effect.get_buffer(_voice_effect.get_frames_available())
	_voice_samples = PackedVector2Array()
	_voice_player.play()
	_voice_rec = true
	_feed("录音中…(松开 V 结束)")

func _voice_stop() -> void:
	if not _voice_rec:
		return
	_voice_rec = false
	_voice_player.stop()
	if _voice_samples.size() < 4410:   # <0.1s 视为误触
		_feed("录音太短, 已忽略")
		return
	var path := "user://voice/input_%d.wav" % Time.get_unix_time_from_system()
	var ok := _voice_save_wav(path)
	_feed("语音已保存(%.1fs), 等待转写…" % (float(_voice_samples.size()) / 44100.0))
	print("[VOICE] captured -> ", path, " ok=", ok, " frames=", _voice_samples.size())

func _physics_process(_dt: float) -> void:
	if not _voice_rec:
		return
	var n := _voice_effect.get_frames_available()
	if n > 0:
		_voice_samples.append_array(_voice_effect.get_buffer(n))

func _voice_save_wav(path: String) -> bool:
	var data := PackedByteArray()
	data.resize(_voice_samples.size() * 2)
	const GAIN := 6.0   # 麦克风电平偏低, 软件增益后量化
	for i in _voice_samples.size():
		var v := clampf(_voice_samples[i].x * GAIN, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	var mix_rate := 44100
	f.store_32(0x46464952)              # RIFF
	f.store_32(36 + data.size())
	f.store_32(0x45564157)              # WAVE
	f.store_32(0x20746d66)              # fmt
	f.store_32(16)
	f.store_16(1)                       # PCM
	f.store_16(1)                       # mono
	f.store_32(mix_rate)
	f.store_32(mix_rate * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_32(0x61746164)              # data
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
	return true

# ==================== 音效层实现(v6.13)====================
func _setup_sfx() -> void:
	const SFX := ["cannon", "plasma", "hit_player", "hit_enemy", "explode", "overheat", "lock", "gate", "whale_roar", "whale_distant", "whale_greet", "missile_launch", "explode_big", "whale_song"]
	for n in SFX:
		var p := "res://assets/sfx/%s.wav" % n
		if ResourceLoader.exists(p):
			_sfx_lib[n] = load(p)
		else:
			push_warning("[SFX] 缺文件: %s" % p)
	for i in 10:   # 播放池:机炮 0.1s/发 连射需并发
		var ap := AudioStreamPlayer.new()
		ap.bus = "Master"
		add_child(ap)
		_sfx_pool.append(ap)
	print("[SFX] loaded %d/%d, pool=%d" % [_sfx_lib.size(), SFX.size(), _sfx_pool.size()])


# ===== v6.15.1 防御炮台巨型光束: 充能→发射→冷却 循环打击 =====
var _gb_state := 0        # 0=待机 1=充能 2=发射
var _gb_t := 5.0
var _gb_col: Color = ST_COLORS[0]
var _gb_core: MeshInstance3D = null    # 白芯(细)
var _gb_glow: MeshInstance3D = null    # 彩色辉光(粗)
var _gb_outer: MeshInstance3D = null   # 外层半透明(更粗)
var _gb_light: OmniLight3D = null
var _gb_muzzle: OmniLight3D = null
const GB_RANGE := 30000.0
const GB_BEAM_R := 55.0   # 对齐传送门环口径(内径68)

func _gb_create() -> void:
	# 三层同心圆柱 = 质感: 白热芯 + 彩色辉光 + 半透明扩散层
	for layer in [{"r": 15.0, "col": null, "alpha": 0.95, "em": 8.0},
			{"r": GB_BEAM_R * 0.7, "alpha": 0.5, "em": 5.0},
			{"r": GB_BEAM_R, "alpha": 0.22, "em": 2.5}]:
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = layer["r"]
		cyl.bottom_radius = layer["r"]
		cyl.height = 1.0
		mi.mesh = cyl
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(1, 1, 1, 0.0)
		m.emission_enabled = true
		m.emission = Color(1, 1, 1)
		m.emission_energy_multiplier = layer["em"]
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
		mi.visible = false
		add_child(mi)
		if _gb_core == null:
			_gb_core = mi
		elif _gb_glow == null:
			_gb_glow = mi
		else:
			_gb_outer = mi
	_gb_light = OmniLight3D.new()
	_gb_light.omni_range = 1200.0
	_gb_light.visible = false
	add_child(_gb_light)
	_gb_muzzle = OmniLight3D.new()
	_gb_muzzle.omni_range = 600.0
	_gb_muzzle.visible = false
	add_child(_gb_muzzle)

func _gb_beams_off() -> void:
	if _gb_core != null:
		_gb_core.visible = false
		_gb_glow.visible = false
		_gb_outer.visible = false
		_gb_light.visible = false
		_gb_muzzle.visible = false

func _gb_update_visual(from: Vector3, dir: Vector3, r_scale: float, alpha: float) -> void:
	for pair in [[_gb_core, 1.0], [_gb_glow, GB_BEAM_R * 0.7 / 8.0], [_gb_outer, GB_BEAM_R / 8.0]]:
		var mi: MeshInstance3D = pair[0]
		mi.visible = alpha > 0.01
		var cyl: CylinderMesh = mi.mesh
		cyl.height = GB_RANGE
		mi.global_position = from + dir * (GB_RANGE * 0.5)
		mi.look_at(from + dir * GB_RANGE, Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		var mat: StandardMaterial3D = mi.material_override
		mat.albedo_color = Color(_gb_col.r, _gb_col.g, _gb_col.b, alpha * (0.95 if mi == _gb_core else 0.5 if mi == _gb_glow else 0.22))
		if mi == _gb_core:
			mat.albedo_color = Color(1, 1, 1, alpha * 0.95)
	_gb_light.visible = alpha > 0.01
	_gb_light.light_color = _gb_col
	_gb_light.global_position = from + dir * 400.0
	_gb_light.light_energy = 8.0 * alpha
	_gb_muzzle.visible = true
	_gb_muzzle.light_color = _gb_col
	_gb_muzzle.global_position = from
	_gb_muzzle.light_energy = 4.0 * alpha

func _station_defense(dt: float) -> void:
	# v6.15.1 防御炮台: 周期性一道巨型光束, 横扫光束路径上全部敌机/BOSS核心
	# v7.0:L3 剧情门控 —— 支援上线前炮台蓄能待命, 上线后周期性打击敌人(打到一定时间才有的援护)
	if level < 3 or not _support_online:
		_gb_state = 0
		_gb_beams_off()
		return
	if station == null or not is_instance_valid(station):
		return
	if _gb_core == null:
		_gb_create()
	_gb_t -= dt
	var station_pos: Vector3 = (station as Object).call("muzzle_origin") as Vector3   # v6.15.1 炮口截面中心, 光束贴环射出
	# 目标: 优先敌机最密集方向的代表敌机; 无敌机时打BOSS核心
	var best: Object = null
	var bd := 30000.0
	for e in enemies:
		if is_instance_valid(e) and e.hp > 0:
			var d: float = station_pos.distance_to(e.global_position)
			if d < bd:
				bd = d
				best = e
	var tgt: Vector3 = (best.global_position if best != null else
		(core.global_position if core != null and is_instance_valid(core) and boss != null and is_instance_valid(boss) else Vector3.ZERO))
	if tgt == Vector3.ZERO:
		_gb_state = 0
		_gb_beams_off()
		return
	var dir: Vector3 = (tgt - station_pos).normalized()
	# v6.15.2 炮台转向: 环口轴向对齐激光方向(充能/发射期间持续追踪)
	if _gb_state >= 1:
		var cur_ax: Vector3 = (station as Object).call("portal_axis_global") as Vector3
		if cur_ax.dot(dir) < 0.9995:
			var turn := Quaternion(cur_ax, dir).normalized()
			var target_q: Quaternion = turn * station.quaternion
			var spd := 3.5 if (_gb_state == 1 and _gb_t < 0.6) else 2.0
			station.quaternion = station.quaternion.slerp(target_q, clampf(dt * spd, 0.0, 1.0))
	match _gb_state:
		0:   # 待机冷却
			_gb_beams_off()
			if _gb_t <= 0.0:
				_gb_state = 1
				_gb_t = 1.6
				_gb_col = ST_COLORS[randi() % ST_COLORS.size()]
				_play_sfx("plasma", -8.0, 0.5)   # 充能低鸣
		1:   # 充能: 光束由细变粗, 透明度上升
			var p := 1.0 - _gb_t / 1.6
			_gb_update_visual(station_pos, dir, 0.3 + 0.7 * p, 0.15 + 0.35 * p)
			if _gb_t <= 0.0:
				_gb_state = 2
				_gb_t = 2.8
				_play_sfx("explode_big", -6.0, 1.4)   # 发射轰鸣
		2:   # 发射: 全径光束, 路径上所有敌机持续受伤
			_gb_update_visual(station_pos, dir, 1.0, 0.85)
			if _st_cd <= 0.0:
				_st_cd = 0.4
				var dmg := 16.0 + 4.0 * level
				for e in enemies.duplicate():
					if is_instance_valid(e) and e.hp > 0:
						var rel: Vector3 = e.global_position - station_pos
						var along := rel.dot(dir)
						if along > 0.0 and along < GB_RANGE:
							if (rel - dir * along).length() < GB_BEAM_R:
								_damage_enemy(e, dmg)
				if boss != null and is_instance_valid(boss) and core != null and is_instance_valid(core):
					var relc: Vector3 = core.global_position - station_pos
					var alongc := relc.dot(dir)
					if alongc > 0.0 and alongc < GB_RANGE and (relc - dir * alongc).length() < GB_BEAM_R * 1.5:
						_damage_core(dmg * 1.5)
				_hit_sparks(station_pos + dir * 60.0, _gb_col)
			if _gb_t <= 0.0:
				_gb_state = 0
				_gb_t = 6.0   # 冷却
	_st_cd -= dt

func _play_sfx(name: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _sfx_lib.has(name):
		return
	var ap := _sfx_pool[_sfx_rr % _sfx_pool.size()]
	_sfx_rr += 1
	ap.stream = _sfx_lib[name]
	ap.volume_db = vol_db
	ap.pitch_scale = pitch
	ap.play()

# ==================== 等离子爆炸(AoE, v6.17)====================
func _plasma_blast(pos: Vector3) -> void:
	var r := _b("plasma", "blast_radius")
	var edge := _b("plasma", "blast_edge")
	for e in enemies.duplicate():   # 复制迭代: 击杀会原地改 enemies
		if is_instance_valid(e) and e.hp > 0:
			var d := pos.distance_to(e.global_position)
			if d < r:
				var k := 1.0 - (1.0 - edge) * (d / r)   # 中心 100% → 边缘 edge 线性衰减
				_damage_enemy(e, _b("plasma", "damage") * dmg_mult * k)
	if core != null and pos.distance_to(core.global_position) < r:
		var dc := pos.distance_to(core.global_position)
		var k2 := 1.0 - (1.0 - edge) * (dc / r)
		_damage_core(_b("plasma", "damage") * _b("plasma", "core_mult") * dmg_mult * k2)
	_explode_small(pos)
	_play_sfx("explode_big", -6.0, randf_range(0.9, 1.1))

# ==================== v7.1 结算升级:能力树 + 改造升级(双轨分档) ====================
func _tier_str(t: int) -> String:
	var s := ""
	for i in 3:
		s += "▰" if i < t else "▱"
	return s

func _ab_cost(t: int) -> int:
	return 80 * (t + 1)   # 能力树档位价:80/160/240

func _rf_cost(t: int) -> int:
	return 150 * (t + 1)  # 改造档位价:150/300/450

func _settlement_text() -> String:
	var mission_name := "歼灭战" if level == 1 else ("保卫战" if level == 2 else "BOSS战")
	var lines: Array = []
	lines.append("══ 任 务 完 成 ══   第 %d 关 · %s" % [level, mission_name])
	lines.append("击毁 %d    用时 %ds    持有资源 %d" % [kills, int(mission_time), parts])
	lines.append("─".repeat(46))
	lines.append("◆ 能力树(战斗领悟)")
	lines.append("[1] 火力控制 %s  全伤害+12%%/档   需 %d" % [_tier_str(ab_fire), (0 if ab_fire >= 3 else _ab_cost(ab_fire))])
	lines.append("[2] 装甲掌控 %s  HP上限+30/档     需 %d" % [_tier_str(ab_armor), (0 if ab_armor >= 3 else _ab_cost(ab_armor))])
	lines.append("[3] 矢量机动 %s  速度+10%%/档      需 %d" % [_tier_str(ab_engine), (0 if ab_engine >= 3 else _ab_cost(ab_engine))])
	lines.append("◆ 改造升级(机库档位)")
	lines.append("[4] 武器系统 %s  全伤害+15%%/档   需 %d" % [_tier_str(rf_weapon), (0 if rf_weapon >= 3 else _rf_cost(rf_weapon))])
	lines.append("[5] 机体结构 %s  HP上限+60/档     需 %d" % [_tier_str(rf_airframe), (0 if rf_airframe >= 3 else _rf_cost(rf_airframe))])
	lines.append("[6] 推进器   %s  速度+15%%/档      需 %d" % [_tier_str(rf_engine), (0 if rf_engine >= 3 else _rf_cost(rf_engine))])
	lines.append("─".repeat(46))
	lines.append("当前: 伤害×%.2f   装甲 %d/%d   机动×%.2f" % [dmg_mult, hp, hp_max, speed_mult])
	lines.append("[1-6] 购买强化(可连续)      [Enter] 跃迁下一关")
	return "
".join(lines)

func _recalc_stats() -> void:
	dmg_mult = 1.0 + 0.12 * float(ab_fire) + 0.15 * float(rf_weapon)
	hp_max = 100 + 30 * ab_armor + 60 * rf_airframe
	speed_mult = 1.0 + 0.10 * float(ab_engine) + 0.15 * float(rf_engine)
	hp = clampi(hp, 0, hp_max)

func _settlement_buy(idx: int) -> void:
	var bought := false
	match idx:
		1:
			if ab_fire < 3 and parts >= _ab_cost(ab_fire):
				parts -= _ab_cost(ab_fire)
				ab_fire += 1
				_feed("◆ 能力树·火力控制 → 第 %d 档(全伤害 +12%%)" % ab_fire)
				bought = true
		2:
			if ab_armor < 3 and parts >= _ab_cost(ab_armor):
				parts -= _ab_cost(ab_armor)
				ab_armor += 1
				_feed("◆ 能力树·装甲掌控 → 第 %d 档(HP 上限 +30)" % ab_armor)
				bought = true
		3:
			if ab_engine < 3 and parts >= _ab_cost(ab_engine):
				parts -= _ab_cost(ab_engine)
				ab_engine += 1
				_feed("◆ 能力树·矢量机动 → 第 %d 档(速度 +10%%)" % ab_engine)
				bought = true
		4:
			if rf_weapon < 3 and parts >= _rf_cost(rf_weapon):
				parts -= _rf_cost(rf_weapon)
				rf_weapon += 1
				_feed("🔧 改造·武器系统 → 第 %d 档(全伤害 +15%%)" % rf_weapon)
				bought = true
		5:
			if rf_airframe < 3 and parts >= _rf_cost(rf_airframe):
				parts -= _rf_cost(rf_airframe)
				rf_airframe += 1
				_feed("🔧 改造·机体结构 → 第 %d 档(HP 上限 +60)" % rf_airframe)
				bought = true
		6:
			if rf_engine < 3 and parts >= _rf_cost(rf_engine):
				parts -= _rf_cost(rf_engine)
				rf_engine += 1
				_feed("🔧 改造·推进器 → 第 %d 档(速度 +15%%)" % rf_engine)
				bought = true
	if bought:
		_recalc_stats()
		hp = hp_max
		_result_lbl.text = _settlement_text()
		_eva_ack("强化模块已安装")
	else:
		_feed("无法购买(档位已满或资源不足)")

# ==================== v7.3 弹体炮:敌机同款实体弹(主武器火力补充) ====================
func _fire_bolts() -> void:
	if dead or bolt_cd > 0.0:
		return
	var tgt: Object = null
	if hover_enemy != null and is_instance_valid(hover_enemy) and (hover_enemy as Enemy).hp > 0:
		tgt = hover_enemy
	elif lock_target != null and is_instance_valid(lock_target):
		tgt = lock_target
	elif lock_valid and core != null and is_instance_valid(core):
		tgt = core
	bolt_cd = _b("playergun", "fire_interval")
	var from := cam.global_position - cam.basis.z * 1.6
	var dir: Vector3
	if tgt is Node3D:
		dir = ((tgt as Node3D).global_position - from).normalized()
	else:
		dir = _aim_dir()
	var mi := _bolt_acquire(_bolt_pool_w, from, _bolt_mat_res())   # 敌机同款弹体(红色曳光)
	mi.look_at(from + dir * 10.0, Vector3.UP)
	friendly_bolts.append({"mi": mi, "vel": dir * _b("playergun", "speed"), "life": _b("playergun", "life"), "tgt": tgt, "dmg": _b("playergun", "damage") * dmg_mult})
	_play_sfx("cannon", -14.0, 1.6)

# ==================== v7.4 mega beam ====================
func _mega_fire() -> void:
	if dead or mega_t >= 0.0:
		return
	if mega_cd > 0.0:
		_feed("mega charging %d%%" % int(100.0 * (1.0 - mega_cd / _b("megabeam", "cooldown"))))
		return
	mega_t = 0.0
	mega_p_t = 0.0
	_play_sfx("gate", -2.0, 0.7)
	_play_sfx("explode_big", -4.0, 0.6)
	_feed("MEGA BEAM FIRE")
	mega_mi = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = _b("megabeam", "radius")
	cyl.bottom_radius = _b("megabeam", "radius")
	cyl.height = _b("megabeam", "range")
	cyl.radial_segments = 24
	mega_mi.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.70, 0.90, 1.0, 0.85)
	m.emission_enabled = true
	m.emission = Color(0.80, 0.95, 1.0)
	m.emission_energy_multiplier = 6.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mega_mi.material_override = m
	add_child(mega_mi)
	shake = 1.2

func _mega_tick(dt: float) -> void:
	mega_t += dt
	var dir := -cam.basis.z
	var from := cam.global_position
	var R := _b("megabeam", "range")
	if mega_mi == null or not is_instance_valid(mega_mi):
		mega_t = -1.0
		return
	mega_mi.global_position = from + dir * (R * 0.5)
	mega_mi.look_at(from + dir * R, Vector3.UP)
	mega_mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	var breath := 1.0 + 0.15 * sin(fx_time * 30.0)
	mega_mi.scale = Vector3(breath, 1.0, breath)
	mega_p_t -= dt
	if mega_p_t <= 0.0:
		mega_p_t = 0.1
		var dps := _b("megabeam", "dps") * dmg_mult
		var far_r := _b("megabeam", "far_range")
		var far_f := _b("megabeam", "far_factor")
		var rad := _b("megabeam", "radius")
		for e in enemies:
			if is_instance_valid(e) and (e as Enemy).hp > 0:
				var rel: Vector3 = (e as Node3D).global_position - from
				var along := rel.dot(dir)
				if along > 0.0 and along < R:
					var perp := (rel - dir * along).length()
					if perp < rad + 12.0:
						var mul := 1.0 if along < far_r else far_f
						_damage_enemy(e, dps * 0.1 * mul)
						if randf() < 0.2:
							_hit_sparks((e as Node3D).global_position, Color(0.8, 0.95, 1.0))
		if core != null and is_instance_valid(core):
			var relc: Vector3 = core.global_position - from
			var alongc := relc.dot(dir)
			if alongc > 0.0 and alongc < R:
				var perpc := (relc - dir * alongc).length()
				if perpc < rad + 100.0:
					var mulc := 1.0 if alongc < far_r else far_f
					_damage_core(dps * 0.1 * mulc * _b("megabeam", "core_mult"))
	if mega_t >= _b("megabeam", "duration"):
		mega_t = -1.0
		mega_cd = _b("megabeam", "cooldown")
		mega_mi.queue_free()
		mega_mi = null
		_feed("mega beam spent, recharge %ds" % int(_b("megabeam", "cooldown")))
# ==================== v7.5 全局高斯 LOD 预算: GPU 绘制数封顶 ====================
func _crowd_lod() -> void:
	# 空间复用省的是显存(同型共享 GaussianResource); 但每架仍是独立绘制调用。
	# 260 架全高斯 = 260 次半透明 splat 绘制+排序, GPU 顶不住。
	# 这里按距离排序, 只有最近 gauss_cap 架保留高斯, 其余切换低模剪影(视觉密度不变)。
	if cam == null:
		return
	var cam_pos := cam.global_position
	var rng := _b("crowd", "splat_range")
	var cap := _bi("crowd", "gauss_cap")
	var arr: Array = []
	for e in enemies:
		if is_instance_valid(e) and (e as Enemy).gs_node != null:
			arr.append([cam_pos.distance_squared_to((e as Node3D).global_position), e])
	arr.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	var used := 0
	for it in arr:
		var e: Enemy = it[1]
		var near: bool = float(it[0]) < rng * rng and used < cap
		if near:
			used += 1
		if is_instance_valid(e.gs_node):
			e.gs_node.visible = near
		if is_instance_valid(e.mesh_node):
			e.mesh_node.visible = not near
	_crowd_lod_dbg += 1
	if _crowd_lod_dbg >= 20:
		_crowd_lod_dbg = 0
		print("[LOD] gauss=%d lowmesh=%d enemies=%d" % [used, arr.size() - used, enemies.size()])
# ==================== v7.7 EVA 应答 / 终局时序 / L1 引导 ====================
func _eva_ack(tx: String = "收到，已完成") -> void:
	# 指令执行后的 EVA 应答: 字幕 + 右侧表情面板 + 文字频道
	_sub_transient("EVA", tx)
	_eva_say("好的, " + tx)
	if _ack_lbl != null:
		_ack_lbl.text = "٩( 'ω' )و  " + tx
		_ack_lbl.visible = true
		_ack_lbl.modulate.a = 1.0
		_ack_ttl = 2.6

func _finale_voice() -> void:
	# v7.7:鲸歌先行 12s 后才进入 EVA 播报 + 剧情语音(原实现击杀即触发太突兀)
	_eva_announce_key("l3_boss_down", true)
	_story_play([
		{"sp": "EVA", "tx": _eva_key_text("whale_line1"), "voice": "whale_line1"},
		{"sp": "", "tx": "那是什么？？？", "choice": true},
		{"sp": "EVA", "tx": _eva_key_text("finale_answer"), "voice": "finale_answer"},
		{"sp": "EVA", "tx": _eva_key_text("demo_complete"), "voice": "demo_complete", "done": true},
	])

func _l1_intro() -> void:
	# v7.7:L1 开场引导 —— 背景介绍 + 操作/超级武器/语音指挥教学(剧情字幕推进)
	if level != 1 or phase >= 3 or _story_on:
		return
	_story_play([
		{"sp": "EVA", "tx": "欢迎登机,飞行员。这里是近地防线 —— 星门失守后,敌军机群不断从虫洞涌出,你是这条轨道上最后一架截击机。"},
		{"sp": "EVA", "tx": "我是 EVA,你的舰载 AI。按 [1/E/空格] 或点击鼠标推进对话。"},
		{"sp": "EVA", "tx": "操作指引: 主激光常驻照射; [F] 全自动火控; [鼠标右键] 追踪导弹; 弹体炮自动连射; [T] 直接锁定导航; [WASD+QE] 飞行, [Shift] 加力。"},
		{"sp": "EVA", "tx": "超级武器: [X] 湮灭光束 —— 充能 60 秒,释放后巨型光束随视角扫射 2 秒,范围杀伤随距离衰减。开局已充能完毕,找机群密集处试试!"},
		{"sp": "EVA", "tx": "语音指挥: 按住 [V] 对我说话,例如 调高音量 / 查看状态 / 打开轨道线 —— 指令完成后我会回复 收到,已完成。"},
	])

func _tick_spawn_q(dt: float) -> void:
	# v7.9:机群流渐次出厂 —— 每条流每 0.12s 生成 1 架(43 架约 5s 铺满), 创建成本摊平不再有波次尖峰
	var keep: Array = []
	for it in _spawn_q:
		var s = it["s"]
		if not is_instance_valid(s):
			continue
		it["cd"] = float(it["cd"]) - dt
		while float(it["cd"]) <= 0.0 and int(it["i"]) < s.members_n:
			var e := Enemy.new()
			add_child(e)
			e.setup_jet(self, s, int(it["i"]), it["origin"])
			e.speed = 42.0 * float(Crowd.TYPES[s.type_id]["speed_mul"]) * enemy_speed_mul
			e.hp = int(round(float(e.hp) * enemy_hp_mul * float(Crowd.TYPES[s.type_id]["hp_mul"])))
			e.hp_max = e.hp
			enemies.append(e)
			s.members.append(e)
			it["i"] = int(it["i"]) + 1
			it["cd"] = float(it["cd"]) + 0.12
		if int(it["i"]) < s.members_n:
			keep.append(it)
	_spawn_q = keep

func _pending_members(s) -> int:
	# v7.9b:该流还剩多少架未出厂(渐次创建期间 alive_count 可能为 0)
	for it in _spawn_q:
		if it["s"] == s:
			return s.members_n - int(it["i"])
	return 0


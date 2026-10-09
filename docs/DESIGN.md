# 核心机制设计说明

本文只写**代码里真实存在**的东西，每节末尾给文件与函数出处。读不懂或没核实的地方直接标「未核实」。

阅读顺序对应三条独立的技术链路：

1. **3DGS 渲染侧**：高斯数据怎么进来、怎么渲染、怎么按距离分级（§1–§3）
2. **3DGS 碰撞侧**：高斯→体素→网格这条管线到底走到哪一步（§4）
3. **模拟侧**：真实轨道要素、解析日食、真实比例缩放（§5–§7）
4. **玩法侧**：机群流、武器与数值表、验收开关（§8–§10）

---

## 1. 高斯数据是怎么进来的

插件注册了一个 Godot `EditorImportPlugin`，识别扩展名 **`ply` / `splat` / `sog` / `gltf` / `glb` / `usdz`**，统一导入成 `GaussianResource`（保存扩展名 `res`）。

出处：`addons/gdgs/importers/gaussian_import_plugin.gd` `_get_recognized_extensions()` / `_get_save_extension()` / `_get_resource_type()`。

底层解码器是分开的（`addons/gdgs/importers/decoders/`）：

| 解码器 | 说明 |
|---|---|
| `standard_ply_decoder.gd` | 标准 INRIA 3DGS binary PLY |
| `compressed_ply_decoder.gd` | 压缩 PLY（本项目的主力样例 `demo.compressed.ply` 走这条） |
| `splat_decoder.gd` | `.splat`（antimatter15 格式） |
| `sog_decoder.gd` | `.sog` |
| `gltf_decoder.gd` | glTF/GLB/USDZ 里的高斯扩展 |
| `nurec_decoder.gd` | **不是独立扩展名**：它是从 **USDZ 压缩包内**取出 `.nurec`（gzip + MessagePack）载荷的解码器，见该文件第 33–45 行的 zip 内查找逻辑 |

> 更正一句常见说法：`nurec` **不在**导入器的扩展名列表里，它是走 `usdz` 进来的。出处：`nurec_decoder.gd:33-45` vs `gaussian_import_plugin.gd` 的扩展名数组。

两个底层解析器：`binary_ply_reader.gd`、`msgpack_reader.gd`。

## 2. 两条渲染后端

`addons/gdgs/runtime/render/backend/gaussian_backend_selector.gd` 在**会话第一次请求**时读一次项目设置 `gdgs/rendering/backend`（`Auto` / `Compute` / `Raster`），解析结果缓存整个会话——**设计上不允许运行时切换，也没有逐节点覆盖**。两条后端用 guarded load 分开加载，选中者自检失败时回退到另一条，两条都失败则返回 null、跳过渲染而不崩。

- **Raster**：`raster_render_backend.gd` + `raster_data_textures.gd`（把高斯数据打包成数据纹理）+ `raster_sorter.gd` / `raster_sort_job.gd` / `raster_sort_driver.gd`（排序）+ `materials/gaussian_raster.gdshader`（22.8 KB 的着色器）。
- **Compute**：`gaussian_renderer.gd` + `gaussian_gpu_state_cache.gd` + `gaussian_rendering_device_context.gd` + `gaussian_scene_registry.gd` + 一组 GLSL：`gsplat_projection.glsl`、`gsplat_render.glsl`、`gsplat_boundaries.glsl`，以及一套 4 个文件的基数排序（`radix_sort_spine/upsweep/downsweep.glsl`）。它通过 `gaussian_compositor_effect.gd` 挂 `CompositorEffect` 做合成。

**本项目出厂用 Raster**（`project.godot` `[gdgs] rendering/backend="Raster"`）。原因写在 `project.godot` 自己的注释里：Compute 修好后在单一大云（星鲸 40.8 万点）上快 2.4×，但在 100 个小实例的编队场景上慢 36%、显存约 5×，所以 Raster 是默认。

`project.godot` 的 `[gdgs] opt/*` 是一组 **A/B 优化开关**，全部默认关掉即回到优化前行为，逐项读数与结论见 `docs/evidence/15-高斯渲染器优化执行报告.md`、`16-Compute后端优化AB报告.md`。这些开关在 `addons/gdgs/runtime/` 下被真实读取（`raster_data_textures.gd:47-50`、`raster_render_backend.gd:378-385`、`raster_sort_job.gd:16`、`gaussian_gpu_state_cache.gd:34-38`、`gaussian_renderer.gd:11-16,151-153`）。

## 3. 三级 LOD 与行星高斯烘焙

### 3.1 烘焙：贴图 → 表面高斯

`tools/bake_planet_splat.py` 的文档字符串把设计写得很清楚，实现也对得上：

- **太阳烘进 SH band-0**：`f_dc = 颜色`、`f_rest = 0`，运行时零着色成本；
- 烘焙时的太阳轴固定在**本地 −Z**，Godot 侧用 `look_at(太阳)` 对齐 → **平移自由、朝向锁定**（只剩绕太阳轴的 1 个自由度自转）；
- 球面点用 **Fibonacci 球面均匀采样**（`fib_sphere()`）；
- 每个点是**切向扁平圆盘**：`scale = (s, s, 0.15s)`，切向覆盖重叠系数 `OVERLAP = 1.25`；
- 法线→四元数用 **Shepperd 法**（`basis_and_quat()`，按旋转矩阵最大对角元分支）；
- 输出**标准 INRIA binary PLY**（小端 f32；scale 取 log、opacity 取 logit、color 用 `0.5 + C0·f_dc`），省略 `nx/ny/nz` 与 `f_rest_*`（解码器按缺省 0 处理）；
- 两级点数由 `--counts` 指定（如 `160000,20000`）。

常量：`SH_C0 = 0.28209479177387814`（标准 SH 零阶系数）、`FLAT = 0.15`、`OPACITY = 0.98`（概率而非 logit，注释说明 0.98×覆盖 1.56 → 内部净不透明 ~99.9%）。

另外 `tools/ply_to_compressed.py`（27.3 KB）负责把大 PLY 转成压缩 PLY。

### 3.2 relight 法线资源

`lighting_gen.gd` 是一个 headless 脚本，为 4 个行星 PLY（`earth_l0/l1`、`jupiter_l0/l1`）生成配对的 `GaussianLightingResource`：**法线 = 位置归一化**（球面行星），AO = 255（表面无自遮挡），置信度 = 255（是表面高斯而非飘浮点），法线用八面体编码成每点 4 字节（`oct_encode` / `encode_signed_byte`），`voxel_size = 1.0`。输出 `<名>.lighting.res`（日志格式 `LIGHTING-GEN %s: %d pts -> %s err=%d`）。

### 3.3 运行时三级切换

`solar_combat.gd` 按**角径**（不是距离）决策，因为"哪个级别够用"取决于它在屏幕上占多少像素：

```
角径 = rad_to_deg(asin(clamp(radius / max(d, radius+0.1), 0, 1)))
```

| 常量 | 值 | 含义 |
|---|---|---|
| `SPLAT_LOD_MESH_DEG` | 10.0 | ≥10° 交给网格贴图（8k 贴图 + 192 段球） |
| `SPLAT_LOD_L1_DEG` | 3.5 | <3.5° 降到 L1 高斯（远疏） |
| `SPLAT_LOD_HYST_DEG` | 1.5 | 迟滞带宽，防止在临界角径抖动 |
| `SPLAT_LOD_SWAP_DEG` | 8.0 | **纯网格行星**（非高斯）的 L0/L1 切换角径 |

函数 `_update_splat_lod()`。

两条梯队各自独立：

- **高斯行星**（earth / jupiter，`SPLAT_PLANETS` + `_add_splat_planet()`）：mesh ↔ L0 高斯 ↔ L1 高斯。
- **纯网格行星**（其余，`_add_grid_lod()`）：192 段 ↔ 96 段 ↔ 48 段，三份网格由 `grid_twins` 注册表**同步自转**，避免切层时经度跳变。

切换用 0.55s 交叉淡化（`_lod_crossfade()` / `_tick_lod_fades()` / `_apply_lod_alpha()`）。代码注释明确记录了被放弃的方案：「v6.12g 弃用的是"整层 alpha 进透明队列"；本版用 gdgs node_alpha 逐节点通道, 不改渲染队列」。

### 3.4 L0 按需流式

行星 L0 高斯点数大（日志：地球 400k），所以**不预加载**（`_tick_l0_stream()`）：

| 状态 | 行为 |
|---|---|
| 0（待命）→ 1（加载中） | 角径到位即 `ResourceLoader.load_threaded_request()`（后台线程） |
| 1 → 2（就绪） | `load_threaded_get_status()` 轮询；就绪则设 scale、赋 `gaussian`、必要时做 L1→L0 交叉淡化 |
| 2 → 0 | 离开 L0 档位满 10s（`l0_grace`）后把 `near.gaussian = null` 释放 GPU 缓冲，打印 `SPLAT-L0: %s 卸载(显存回收)` |

L0 还没流完时由 L1 顶上（`_update_splat_lod()` 里 `far.visible = lv==1 or (lv==0 and not l0_ready)`）。

日志证据（`logs/autotest-pass-42.3s.log`）：
```
SPLAT-LOD: earth.jpg -> L0高斯 (角径 8.5度, d=677m, 淡入0.55s)
SPLAT-L0: earth.jpg 开始流式加载
SPLAT-L0: earth.jpg 加载完成(400k)
```

## 4. 高斯 → 体素 → 网格（碰撞生成管线）——**能力存在，Demo 未使用**

这是最容易被说错的一段，所以把边界写清楚。

### 4.1 管线本身（真实存在）

`addons/gdgs/collision/pipeline/` 里的数据流是：

```
GaussianResource
   │  splat_source.snapshot()      ← 必须在主线程；只从资源里取 point_count/xyz/point_data_float/aabb
   ↓  （深拷贝成纯 PackedArray + GPU shader 源码字符串，worker 里不碰任何 Resource）
splat_source.prepare()             ← 协方差求逆 + 正则化；>2,000,000 splat 自动等距降采样并做密度补偿
   ↓
candidate_index.build()            ← 按块建立 splat→voxel 的候选索引（上限 12,000,000 条引用）
   ↓
gpu_voxelizer.voxelize()           ← 走 collision/shaders/voxelize.glsl（私有 compute shader）
   │                                  或 voxelizer.gd（CPU 回退）
   ↓
voxel_grid.gd                      ← 占用块索引
   ↓
mesher.build()                     ← 只取"暴露面"，按 (bucket, plane, u, v) 分组做**贪心矩形合并**
   │  smooth_mesher.gd             ← 平滑变体
   ↓  coplanar_merge.gd            ← 共面合并
网格
```

关键上限常量（`collision_pipeline.gd`）：`AUTO_VOXELS_ON_LONGEST_AXIS = 128`、`MAX_VOXEL_SIZE = 0.5`、`MAX_GRID_VOXELS = 16,777,216`、`MAX_GRID_AXIS = 4096`、`MAX_CANDIDATE_REFERENCES = 12,000,000`、`MAX_EXPOSED_FACES = 2,000,000`。

线程模型：`collision_pipeline.gd` 把流程拆成三段——主编程 `create_snapshot()` → 工作线程 `generate_from_snapshot()` → 主线程 `finalize_result()`，这样 worker 里不触碰 Resource / UI / 编辑器对象，能被 `WorkerThreadPool` 安全调用。

### 4.2 边界（必须说清的部分）

- 管线**只在编辑器侧接入**：`plugin.gd:_enable_collision_feature()` 注册的是一个 `EditorInspectorPlugin`（`collision/editor/inspector_plugin.gd` + `collision_panel.gd` + `progress_dialog.gd`），由编辑器面板触发、带进度条、带 `generation_metadata.gd` 记录生成参数。**没有任何运行时入口**。
- 光照烘焙模块依赖它：`lighting/bake/proxy_builder.gd` 第 21 行 preload 了同一个 `collision_pipeline.gd` —— 即"给高斯做代理网格以便投阴影"也走这条管线（`proxy_shadow_caster.gd`）。
- **本仓库的游戏没用它**：
  - 敌机碰撞 = 低模 OBJ 的 **trimesh**（`crowd.gd:66` `cs.shape = mesh.create_trimesh_shape()`），不是体素化产物；
  - 最低限验证场景 `main.gd` 里，高斯盆景的碰撞是**手写的盒子代理**（`wall_body` / `BoxShape3D`），并且该文件注释直接写明「代理碰撞墙(代替 splat 承接物理/射线)」，射线测试的预期结果也是"被代理墙挡住, 而非 splat"；
  - `solar_combat.gd` 全文没有引用这条管线（无 `collision_pipeline` / `gpu_voxelizer` 出现），它的碰撞体是 `SphereShape3D`（第 544 行，核心）与 `BoxShape3D`（第 3633 行）。
- 仓库里**找不到任何生成的碰撞网格产物**（我按 `coll|collision|proxy|voxel` 扫过 `*.res/*.tres/*.obj/*.glb/*.mesh`）。
- 这条管线**没有测试**（插件侧的 `collision_feature.gd:self_test()` 只做"依赖链能否编译并返回合法字典"级别的检查），**我没有运行过它**。

**结论**：准确说法是"这个 3DGS 插件具备把高斯场景转成可碰撞网格的能力（自实现 GPU 体素化 + 贪心面合并；本项目在上游基础上做过渲染器优化）"，而**不是**"这个 Demo 用体素化网格实现了高斯场景可碰撞"。

## 5. 真实轨道要素与解析星历

`solar_ephem.gd`（`class_name SolarEphem extends RefCounted`），全部静态函数：

| 能力 | 实现 |
|---|---|
| 行星日心位置 | **JPL Standish 近似根数**（8 行星，`ELEM` 表给 `a, e, I, L, varpi, Omega` 六根数 + 每儒略世纪变率 `rate`），适用 1800–2050；开普勒方程用**牛顿迭代 8 次**（`solve_kepler`，初值 `E = M + e·sin M`） |
| 坐标约定 | 返回**黄道 J2000 右手系** `Vector3(x,y,z)`，`z` = 黄北极；游戏层映射 `g = (x, z, −y)` |
| 月球 | **Meeus 截断级数**（黄经 13 项、黄纬 5 项、距离 3 项），返回地心黄道球坐标 `{lon, lat, dist(km)}` |
| 黄赤交角 | IAU1980 平黄赤交角多项式 `obliquity(t)` |
| 恒星时 | GMST 近似式 `gmst_deg(jd_ut)` |
| 太阳直下点 | `sun_apparent_lon()`（含岁差项与光行差 −0.005691°）→ 转赤经 → 减 GMST |
| 儒略日 | `jd_from_ms` / `jd_tt_from_ms`，后者把闰秒硬编码进去（`UTC_TT_SECONDS = 69.184`，注释说明"单机无感"） |

**溯源**：文件头自述这是另一个项目里 `tools/ephemeris/ephemeris.mjs` 与 `tools/coords/rotation.mjs` 的 GDScript 移植，并声称"已过 9 项天文回归"。那两个源文件存在于工作区但**不在本仓库**；本仓库不包含那 9 项回归测试，因此**该精度声明我未核实**。文件头给出的精度量级是"内行星 <1 角分、月球 ~0.3′"——同样**未核实**。

### 运行时怎么用它

`solar_combat.gd:_build_solar_system()` 用星历解算出的位置摆放：8 行星 + 程序化冥王星（`Re=0.186, AU=39.5, 角度 2.4 rad, 倾角 17.14°, 升交点 110.30°`，代码里是硬编码常量而非星历）+ 月球 + 5 颗卫星（io/europa/ganymede/callisto/titan）+ 土星环与天王星环 + 小行星带（2.2–3.3 AU）与柯伊伯带（32–48 AU）。轨道线也是**按根数采样**画出来的真椭圆（`_add_orbit_line_from_elements` → `orbit_point` 扫平近点角 0..360）。

**地球自转是真实规律**：自转轴按黄赤交角倾斜（`Basis(Vector3.RIGHT, -obliquity(t0))`），相位 = GMST + 标定量 `EARTH_PHASE`（`_ephem_autocal` 写入）。

**逐帧对拍**（`_ephem_report`，日志里能看到）：
```
EPHEM: earth 日心 0.9925,-0.1651,0.0000 au | GMST 248.887° | 太阳直下点经度 -77.22°(星历真值)
EPHEM: 游戏内地球直下点 lat 3.74° lon -77.22° —— 与星历经度差 = EARTH_PHASE 标定值
```
注意这句对拍的构造方式：`EARTH_PHASE` 是**为了让贴图相位与星历对齐而标定出来的**（`_ephem_autocal` 搜索使直下点经度残差最小的旋转，日志 `EPHEM: 贴图相位自标定完成, 直下点经度残差 0.0°(标定旋转 89.7°)`）。也就是说"游戏内 = 星历"部分是**标定的结果**，不能独立当作星历正确性的证明；能算独立证据的是 GMST 与太阳直下点经度这一路（由 `solar_ephem.gd` 独立算出）。

时间是可推进的：`solar_sim_ms` 从真实 UTC 起步（`Time.get_unix_time_from_system()`），按 `solar_time_scale` 推进（命令行 `ephem-fast` 设 600×，直下点漂移 2.5°/s，用于目视验证自转方向与速率）。

## 6. 解析日食（无 shadow map）

`solar_combat.gd:_sun_visibility(p) -> float`，返回 0..1 的太阳可见比例。

模型：太阳在第 0 点、半径 `SUN_R = 10920.0`；行星不是球而是**椭球 proxy**（`occluders` 数组，每项 `{c: 中心, r: 半径}`，在 `_build_solar_system()` 里随行星一起登记，冥王星也登记了）。对每个遮挡体：

```
β   = asin(sun_r / d_sun)                  # 太阳盘半角
α   = asin(occluder_r / d_c)               # 遮挡盘半角
γ   = acos(dir_sun · dir_occluder)         # 两盘心角距
```

三种情形：

| 条件 | 结果 |
|---|---|
| `γ ≥ α + β` | 阴影锥外，不遮挡（`continue`） |
| `α ≥ β 且 γ + β ≤ α` | **本影全食**，返回 0.0 |
| `β > α 且 γ ≤ β − α` | **环食**：行星盘整个悬在太阳盘内，`vis = min(vis, 1 − α²/β²)` |
| 其它 | **部分食**：两圆交叠面积占太阳盘比例（两条弧的扇形面积 − 三角形面积，即 Heron 因子），`vis = min(vis, 1 − frac)` |

逐帧应用到敌机 albedo（`_update_ship_lighting()`：`s = 0.3 + 0.7 * visibility`）。

**自检**：`_eclipse_selftest()` 取两个构造点——木星背阳面 ~2.7×半径处（应全食）与木星位置绕太阳轴转 45°（应全照）——判据 `behind < 0.15 且 lit > 0.95`，每次启动都打印：
```
ECLIPSE-SELFTEST: behind=0.000 lit=1.000 -> PASS
```

**未核实/边界**：这个模型把行星当**正球**（只有 `r`，没有椭球三轴），也**不考虑大气折射、太阳非点光源的有限距离效应以外的东西**（太阳本身按有限半径的面光源处理了）；隐藏在这一句里的复杂度是"多遮挡体只取最暗的那个"（`vis = min(...)` 累加），**没有做遮挡体之间的互相遮挡/多次日食的叠加几何**。另外它只影响 `_update_ship_lighting()` 的敌机明暗，**不影响高斯/网格行星自身的着色**（行星光照是烘焙死的，见 §3.1）——所以"日食"在视觉上是"敌机变暗 + 解析出的可见比例"，而不是"整个场景真的被月亮遮住"。

## 7. 尺度：半径真实比例，距离幂律压缩

`rad_to_deg` 之外的四个常量决定了整个世界观感（`solar_combat.gd` 常量区）：

| 常量 | 值 | 作用 |
|---|---|---|
| `GAME_R` | 100.0 | 地球半径 Re=1 → 100 m |
| `RAD_P` | 1.0 | 半径幂 = 1 → **行星间半径比 = 真实比**（太阳 109.2×地球 = 10,920 m） |
| `AU_GAME` | 42000.0 | 距离基数 |
| `DIST_P` | 0.6 | 距离幂 → **轨道压缩**：`d = 42000·AU^0.6` 米；1.0 才是真实距离 |
| `SOLAR_SCALE` | 1e-5 | 真实米 → 游戏米的线性系数（**§10 有一个关于它的注释不一致**） |

两个换算函数（`solar_combat.gd:131,134`）：`_pr(re) = GAME_R · re^RAD_P`（半径，`RAD_P = 1` 时即线性）、`_pd(au) = AU_GAME · au^DIST_P`（距离）。

竞技场锚定在地球低轨旁：`arena_anchor = earth_pos + normalize(120,40,260) * 350.0`，距地心 350 m（≈地球半径 3.5 倍），地球角径 ~16.6°，抬头即见星球（出生朝向就对准地球）。日志会打印真实尺度换算：`ARENA: 距地心 2.2万km(真实), 地球角径 16.6°`（`_dist_real()` 把游戏米反算回真实 km）。

## 8. 机群流（crowd）

`crowd.gd` 是 `RefCounted` + `class_name Crowd`，核心是**两层复用**：

- **机型层**（`TYPES`）：3 种机型，每种 = 一份低模 OBJ（物理判定体 + 远景剪影）+ 一份高斯 PLY（近景外观）+ 一组倍率（`hp_mul` / `speed_mul` / `dmg_mul` / `length` / `tint`）。模板用静态字典缓存（`_mesh_cache` / `_gs_cache`），每机型只 `load` 一次。
- **流层**（`Stream`）：一波 ≥20 架共用同一机型模板 + 统一编队轨迹与行为（行为枚举由 `Crowd.Stream.behavior_name()` 打印，日志里能见到 `VEE / SNAKE / RING / PINCER`），每流有 `alive_count()` 与自己的一批 `Enemy`。

**空间复用**：同型所有个体引用**同一个** `GaussianResource`（内存/GPU 一份）；超出 `crowd.splat_range = 900` m 的个体由流**批量裁决**从高斯渲染中剔除，换低模剪影——近景高斯 / 远景低模互斥 LOD。全局再叠一层预算 `crowd.gauss_cap = 96`（最近 K 架才用高斯，其余低模）。

**对齐细节**：网格与高斯必须同轴。代码里高斯节点先置一个非单位 `basis` 以跳过插件默认的 RotZ 校正，再给 `Basis(Vector3.RIGHT, -PI*0.5)`（Blender Z-up → Godot Y-up，与 OBJ 导入同轴），`vis.rotation.y = PI` 把导入网格的机头从 +Z 转到 Godot 的前向 −Z。低模 / 碰撞体 / 高斯三者用同一个 `s` 同步缩放（`s = length / mesh.aabb.size.z * scale_mul`）。——实战教训写在注释里：**三者不同步就会出现"打得中看不见的地方"**。

## 9. 武器、数值表与"实战值 vs 表格值"

### 9.1 数值表管线

`data/balance.txt`（18 个 section）→ `_load_balance()` 逐行解析：

```
跳过空行 / # 开头 / ; 开头
[section] 行 → 切出小写 section 名，BAL 里没有就建空 dict
key = value 行 → key 小写；value 去掉 '#' 之后的注释；
                is_valid_float() 则存 float，否则存字符串（非空时）
```

表缺失或打不开时回退到代码里的 `_default_balance()`（只 `push_warning`，不中断）。读表用 `_b(sec,key)` / `_bi(sec,key)` 两个访问器。

启动即打印**数值验收报告**（`_balance_report()`）：各武器 DPS、过热时间与恢复、每一关敌机 HP 对应的击杀发数、核心 HP 与配额收入。README 里贴了一段实际输出。

### 9.2 当前真正生效的武器

| 武器 | 关键数值 | 出处 |
|---|---|---|
| 常驻激光 | 220 DPS、`unlock_level = 1`、射程 3800 m、对核心 ×1.15、`beam_time = 9999`（常驻不熄）、`recharge = 0.35`（起辉棘轮） | `[weapon_laser]` + `_tick_laser()` |
| 弹体炮 | 22 伤害 / 0.18s、弹速 520 m/s、存活 3.0s | `[playergun]` + `_fire_bolts()` |
| 追踪导弹 | 90 伤害、转向率 2.8 rad/s、间隔 1.4s、`enabled = 1` | `[missile]` + `_fire_missile()` / `_tick_missiles()` |
| MEGA 光束 | 冷却 60s、持续 2.0s、4000 DPS、射程 4000 m、远段 ×0.35 | `[megabeam]` + `_mega_fire()` / `_mega_tick()` |
| 僚机 ×3 | 18 伤害、间隔 0.5s、25s 重生、友伤关 | `[wingman]` + `_spawn_wingmen()` / `_tick_wingmen()` |

激光的命中判定值得单独说（`_tick_laser()` 第 1575 行起）：**束方向永远等于准星方向，绝不自动控准星**；先做一次真实 `intersect_ray`，若没打中敌机，再在 `hit_cone = 1.8°` 的角度容差内扫最近的一架判为命中。这是"粗束宽容"而不是"自动瞄准"。

### 9.3 已退役但保留的部分

`[cannon]`（机炮）与 `[plasma]`（等离子）都是 `enabled = 0`，`[heat]`（过热）也是 `enabled = 0`；`_fire_cannon()` / `_fire_plasma()` 的第一行就按 `enabled` 早退，`_add_heat()` 在 `heat.enabled` 为假时直接返回。代码与表项都保留，方便将来重开。

**⚠️ 因此启动日志里的"数值报告"关于机炮/等离子的 DPS 是表格理论值，不是实战值**——`_balance_report()` 读的是表，不看 `enabled`。

## 10. 三关流程、自动验收与外部接口

### 10.1 关卡状态机

`phase` 是一个整数状态机，`level` 是 1..3：**0** 交战 · **1** 开门待返航 · **2** 结算（可用 `Enter` 跳过 / 数字键买强化）· **3** 阵亡待重开（`R` 重开，`_retry_level()`）· **4** 返航接近核心 · **5** 补给舱 · **6** 虫洞过渡 · **7** 全通关。`_apply_level()` 按 `[demo]` 读三关配额（`l1_quota` / `l2_quota` / `l3_quota`）与地面支援上线时间（`l3_support_t`），并按 `[enemy]` 与 `[economy]` 算本关敌机 HP 倍率、伤害、弹速、速度倍率与生存计时。

三关的叙事与机制差异（`_apply_level`、`_spawn_wave`、`_station_defense`、`_finale_whale`）：

1. **L1 歼灭**：清完配额 → 中转站核心现身 → 飞进核心即跃迁。
2. **L2 保卫**：受保护目标变成雷达相阵；敌方**周期性空袭**（`demo.raid_interval` 秒一次，伤害 = `raid_base + raid_per_enemy × 在场敌机数`——在场敌机越多打得越狠，逼你清场）；打到一半触发**增援中队**剧情（`_l2_reinforce_cutscene`）。
3. **L3 BOSS**：先歼灭先遣队 → 八棱柱集群 BOSS 现身 → 开战 `l3_support_t` 秒后**轨道炮台周期火力支援**上线（`_station_defense`）→ BOSS 倒下后星鲸终局 + 鲸歌 + 剧情对话。

### 10.2 自动验收开关 `--autotest`

`solar_combat.gd:autotest_tick(dt)`。要点：

- 自动转向：按"核心（phase 1/4）→ 锁定点 → 最近敌机"的优先级选一个朝向，`lerp_angle` 平滑转过去；
- **HP < 40 时自动回满**（注释：「冒烟保护:确保流程走完(非平衡性测试)」）→ 所以它**不能**用来验证平衡性或"玩家打得赢"；
- 每 10s 打一行状态（t / phase / kills/quota / hp / 敌机数 / 到核心距离 / 位置 / VRAM / FPS / 各流编队的机型×行为×存活数）；
- phase 2 自动买强化（够钱就买伤害升级）再 `_next_level()`；
- phase 7 打印 `AUTOTEST PASS` 并 `quit(0)`；`autotest_t > 420.0` 打印 `AUTOTEST TIMEOUT` 并 `quit(1)`；
- 附属开关：`shots`（过程截图）、`demo`（L1 起解锁全部武器）、`stress`（敌机 ×5 + 120FPS + 帧率 HUD）、`ephem-fast`、`whale_early`、`sunprobe`、`mask=`。

**注意它是 headless 跑的**（`[gdgs] headless environment: rendering backend selection skipped`、`vram=0MB(tex 0MB)`、无 `SAVED` 行）→ 一次 PASS 覆盖的是**逻辑流程**（关卡状态机、星历、日食自检、音频资源、台词表、命令接口），**不覆盖渲染路径**。

### 10.3 外部命令接口与语音

`_register_cmd_interfaces()` 注册 9 个接口，通过 `user://commands/inbox.jsonl` 轮询、`user://commands/executed.json` 做**幂等去重（持久化）**：`set_orbit_lines` / `set_time_scale` / `toggle_orbit_lines` / `notify` / `teleport` / `dbg_planet` / `eva_query` / `eva_repeat` / `eva_mute`。

语音：按住 `V` 录音（`AudioEffectCapture`）→ 松开存 WAV → 外部 Python（`voice_intent.py`）转写 → 回写命令。**那个 Python 依赖不在本仓库**，所以这条通道在这里跑不通。

### 10.4 剧情/台词/音频表

- 台词走 `assets/eva/manifest.json`（21 条，`text_to_wav` + `by_key` 两张表），`_load_eva_manifest()` 载入，缺键时 `_eva_line()` 用 fallback 文本。日志会打印 `[EVA] manifest 台词 21 条 (OK)`。
- 音效走对象池（`_setup_sfx()` / `_play_sfx()`，日志 `[SFX] loaded 14/14, pool=10`）。
- BGM 四个播放器交叉淡化，按关卡切曲（`_setup_music()` / `_music_play()`：`battle` / `boss` / `calm` / `finale`）。
- 特效是一组**高斯序列帧**（`assets/fx/`：`muzzle_00-05`、`blast_00-11`、`charge_00-05`、`laser_hit_00-07`），由 `_fx_play()` / `_tick_fx()` 驱动；生成脚本是 `tools/gen_fx_splats.py`。也就是说**爆炸火花本身也是高斯泼溅**。

---

## 附：几处代码与注释不一致（以代码为准）

| 位置 | 注释说 | 代码是 |
|---|---|---|
| `solar_combat.gd:2,4` | "火控(锥+提前量)"、"锥内自瞄自射" | `_update_fire_control()` 自 v6.16 起是空壳，`_intercept()` 无调用点 |
| `solar_combat.gd:2903,3511` | 太阳 "r=6960m" | `SUN_R := 10920.0`（6960 = 6.96e8 × 1e-5 的旧推导，与 `GAME_R = 100` 不自洽） |
| `data/balance.txt [firecontrol]` | `auto_cone = 30.0` 全自动火控跟踪锥 | 无任何代码读取该键 |
| `bench/bench_runner.gd` 文件头 | "由 Python 编排器调用" | 那个编排器不在本仓库 |
| `solar_combat.gd:1956` 小节标题 | "火控:火控锥目标选择 + 提前量解算" | 紧跟其下就是移除说明 |

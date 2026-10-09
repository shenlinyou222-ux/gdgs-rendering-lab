# 本地实验报告:Godot 4.7.2 + gdgs 3.3.0 渲染 3DGS(实测通过)

日期:2026-09-09 · 环境:Windows 11 · NVIDIA GeForce RTX 5060 8GB(driver 616.64) · Vulkan 1.4.351
工程:`experiment/gdgs_lab/`

## 0. 结论(TL;DR)

| 验证项 | 结果 |
|---|---|
| Godot 4.7.2 + gdgs 插件渲染 .ply | ✅ 271,123 高斯点照片级渲染(样例为桌面盆景) |
| 稳态性能(720p,含公告板/物理) | ✅ 58–60 FPS(垂直同步封顶) |
| splat ↔ 不透明网格 深度互相遮挡 | ✅ 正确(Raster 后端硬件深度测试,遮挡箱几乎完全挡住盆景) |
| 半透明公告板敌机与 splat 共存 | ✅ 正常,billboard 正确朝向相机 |
| splat 本体参与物理? | ❌ 不参与(射线直接穿到后面的代理墙)→ 必须用代理碰撞体 |
| 射击检测:射线→敌机Area3D→代理墙StaticBody | ✅ 全部按预期命中 |
| Compute 后端(Forward+ 计算着色器) | ⚠️ 代码附加 CompositorEffect 后无合成输出(见"踩坑4"),需跟进 |
| Raster 后端(标准透明管线) | ✅ 完全可用,推荐本项目使用 |

## 1. 环境与下载(国内网络适配)

- GitHub API / raw / codeload 可达,**release 资产(objects.githubusercontent.com)被墙** → 用镜像 `https://gh-proxy.com/`、`https://ghproxy.net/` 前缀拼接原 URL;HuggingFace 直连失败,镜像 `https://hf-mirror.com` 可用。
- Godot 4.7.2 stable win64(86MB zip):`https://gh-proxy.com/https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip`
- gdgs 插件 v3.3.0(纯 GDScript,插件包仅 0.2MB;codeload 主分支 zip 169KB,经 .gitattributes 只含 `addons/gdgs`,正好是安装所需全部)
- 样例资产 `demo.compressed.ply`(16.6MB,27.1 万高斯点):ReconWorldLab 仓库 Releases 的 `sample-assets`

## 2. 工程结构与关键配置

```
experiment/gdgs_lab/
├── project.godot        # Forward+;enabled 插件;gdgs/rendering/backend="Raster"
├── addons/gdgs/         # 插件本体
├── assets/demo.compressed.ply
├── main.tscn / main.gd  # 全代码搭建场景 + 自动截图 + 射线检测
└── shots/*.png          # 输出截图
```

`project.godot` 关键段:

```ini
[application]
run/main_scene="res://main.tscn"
[editor_plugins]
enabled=PackedStringArray("res://addons/gdgs/plugin.cfg")
[gdgs]
rendering/backend="Raster"     # Auto/Compute/Raster
[rendering]
renderer/rendering_method="forward_plus"
```

命令级流程:

```bash
# 1) 首次导入(必须先做,让 .ply 与插件 glsl 完成 import)
Godot_v4.7.2-stable_win64_console.exe --headless --path experiment/gdgs_lab --import
# 2) 运行(弹窗约 40 秒,自动存 3 张截图后退出)
Godot_v4.7.2-stable_win64_console.exe --path experiment/gdgs_lab
```

## 3. 场景搭建要点(main.gd,全代码)

1. **合成器(Compute 后端才需要)**:`GaussianCompositorEffect.new()` → `Compositor.new()` → `compositor.compositor_effects.append(fx)` → `WorldEnvironment.compositor`。**Raster 后端不需要这一步**。
2. **splat**:`GaussianSplatNode.new()` → `add_child()` → 再 `splat.gaussian = load("res://assets/demo.compressed.ply")`;`GaussianResource.aabb` 可用于自动取景(本样例 AABB 约 3.8m)。
3. **公告板敌机**:QuadMesh + StandardMaterial3D(`TRANSPARENCY_ALPHA` + `SHADING_MODE_UNSHADED` + `BILLBOARD_ENABLED` + 程序生成的 ImageTexture),挂 Area3D+BoxShape3D 用于命中判定。
4. **代理碰撞墙**:StaticBody3D + BoxShape3D + 半透明蓝色可视化盒,代表"splat 废墟的碰撞代理"。
5. **遮挡测试箱**:不透明 StandardMaterial3D 普通网格。

## 4. 踩坑记录(按出现顺序)

1. **Godot 4.7 API 改名**:`Compositor.effects` → `compositor_effects`(README/旧教程均写 `effects`,4.7 运行时报 `Invalid access to property or key 'effects'`)。
2. **`Node3D.look_at()` 必须在节点入树后调用**,否则报 "Node not inside tree"(改用 add_child 后再 look_at,或 `look_at_from_position()`)。
3. **错误会静默**:GDScript `_ready` 中途报错后场景继续空转(灰屏窗口不退出),headless 导入正常不代表运行正常——务必重定向 stdout/stderr 到文件排查。
4. **Compute 后端在 4.7 + 代码附加合成器时无输出**:修复 API 改名后 props 正常渲染但 splat 不显示;切 `Raster` 后一切正常。官方 README 的 Raster 后端标注 beta、桌面 Forward+ 的 Compute 是"验证充分"路径,推测与 4.7 合成器行为变化有关。**跟进项**:用插件仓库自带的 `samples/demo.tscn`(场景文件内配置合成器)在编辑器里验证 Compute,再决定是否给 ReconWorldLab 提 issue。本项目用 Raster 无阻碍(且其硬件深度测试恰是混合渲染最需要的)。
5. **FPS 测量要预热**:管线首次编译把滚动平均拉到 2 FPS;预热 90 帧后稳态 58–60(垂直同步封顶)。
6. `--headless --import` 只做导入不渲染,可以 CI 化;正式运行必须带 GPU。

## 5. 实测输出

射线检测日志(自动打靶):

```
RAY_ENEMY: hit Area3D name=@Area3D@12 at (1.97, 1.54, 5.09)          ← 先命中敌机判定区
RAY_CENTER: hit StaticBody3D name=@StaticBody3D@8 at (2.04, 1.11, 3.07) ← 再命中代理碰撞墙(而非 splat)
```

截图(`experiment/gdgs_lab/shots/`):
- `01_overview_splat_plus_billboard_enemies.png`:splat 盆景 + 3 架公告板敌机 + 半透明代理墙共存
- `02_closeup_other_angle.png`:近景,布纹纤维清晰,照片级质量
- `03_occluder_blocks_splat.png`:不透明箱体正确遮挡 splat(仅左下角露出布角)

## 6. 下一步扩展实验(建议顺序)

1. 编辑器打开工程,选中 `GaussianSplatNode` → Inspector 的 **GDGS Collision** 面板 → 点 **Generate Collision**(选 `Interior` 模式 + `CollisionSeed` 可封出可行走室内;导出 .obj/.glb 可复用于其他引擎)。
2. **Bake Lighting Proxy** → 让场景里的 DirectionalLight/OmniLight 给 splat 打光,并让 splat 向普通地面投影——爆炸闪光瞬间照亮废墟的关键功能。
3. 用 HY-World 2.0 在线版生成的 .ply 替换 demo 盆景,验证"图生世界 → Godot"全链路。
4. 性能压测:下载插件 Releases 里更大的 .ply,或拆分多个 GaussianSplatNode 实例,观察 Raster 后端 CPU 排序的帧耗时。

## 7. 追加实验:第二幕预演场景(space.tscn,2026-09-09 补)

**已下载的星图素材**(`assets/textures/`,署名见 `ASSETS_LICENSE.md`):

| 文件 | 实际分辨率 | 用途 | 来源/许可 |
|---|---|---|---|
| `8k_stars_milky_way.jpg` | 8192×4096 | 天空球 PanoramaSkyMaterial | Solar System Scope,CC BY 4.0 |
| `8k_jupiter.jpg` | 4096×2048 | 木星球体贴图 | Solar System Scope,CC BY 4.0 |

注:NASA SVS 的 `starmap_2020_4k_print.jpg` 实为 1024×512 缩略图(已弃用);NASA 的正主是 EXR 母版(8K 约 124MB,公版),需色调映射后转 JPG/PNG 再上天空球,留作后续管线。

**场景** `space.tscn / space.gd`(运行:`--path . res://space.tscn`):
星空天空球(PanoramaSkyMaterial + 环境光取自天空)→ 木星(SphereMesh r=55 @ 500m 外,缓慢自转)→ 3DGS 盆景占位废墟(原点)→ 17 架 billboard 敌机 V 字编队(120m 外,Area3D 判定)。纯代码搭建,自动截 2 图后退出。

**结果**:满帧 60FPS;两层截图构图符合设计(前景废墟→编队→木星→银河):
`shots/space_01_ruins_milkyway_enemies.png`、`shots/space_02_jupiter_and_fleet.png`

结论:**第二幕的渲染分层(天空球/行星/3DGS前景/billboard舰队)全部同帧共存且满帧**,换上 HY-World 2.0 的废墟 .ply 即为正式第二幕。

**追加修复:星空无视差问题**(用户实飞反馈)。原因:PanoramaSkyMaterial 渲染在无穷远,平移相机零视差,是天空盒固有属性。修复:按 01/02 报告的"三层视差"方案加 `shaders/star_billboard.gdshader`(径向发光 + 逐实例颜色 + 加法混合的 billboard shader)+ 三个 MultiMesh 星层(远星 1600–3200m ×1500 / 中星 500–1000m ×600 / 近距尘埃 25–90m ×350),全景图 energy 降至 0.85 做最深背景。每层 1 个 draw call,稳态仍 60FPS;飞行时尘埃拉出速度感、中星层明显位移,与 Elite/EVE 手法一致。

**追加:billboard 星云层**(`shaders/nebula_billboard.gdshader` + `_build_nebulae()`)。素材:NASA 公版星云照 ×3(创造之柱 PIA03096 / 猎户座红外 PIA25434 / JWST 宇宙悬崖,均为 1920px,`images-assets.nasa.gov` 直连可用)→ 6 块加法混合 billboard 按 3×2 全天分布(4800–5600m,单片 3000–4200m,径向边缘淡出)。**关键坑:Camera3D 默认远裁剪面 4000m,把 5km 外的星云整个裁掉**——`cam.far = 12000` 后才可见;同理任何"放了东西但看不见"先查 near/far。木星(不透明)对星云的遮挡正确。

**追加:星云拼接 360° 全景**(用户需求:多张星云图拼接的全景天空)。`tools/make_sky_panorama.py`:3 张 NASA 星云照切成 14 块补丁沿银道带分布(镜像+染色+缩放变化),加法混合 + 正弦羽化,叠双层高斯银河辉光与 ~2.6 万颗三档程序化星点,输出 `nasa_sky_panorama_8k.jpg`(8192×4096, 4MB)。踩坑:羽化遮罩首版写反(边缘 1 中心 0)拼出矩形框,截图审查抓出后改为正弦方向。

**追加:真·NASA 全天图 + 极区修复**(用户反馈"上下没星图")。①下载 SVS Deep Star Maps 2020 的 `starmap_2020_4k.exr`(36MB HDR,公版)——Godot 4.7 原生导入 EXR 无需转换;②新增 `shaders/dual_panorama_sky.gdshader`:自研 sky shader 按 equirect 采样**两张全景相加**(NASA 巡天图做全向星场地基 + 星云拼接全景做彩色氛围层),比单 PanoramaSkyMaterial 多一层自由度;③拼接脚本修复极区:高纬星云补丁 ×4、星点密度均匀化(极区保有 55% 密度)、全天空值噪声微星云雾、去掉极区压暗。验证:抬头/低头均为致密真实星场(含麦哲伦云),实况稳态 60FPS。注意:截图模式打印的 fps 含 PNG 落盘停顿,真实帧率以 live 模式为准。

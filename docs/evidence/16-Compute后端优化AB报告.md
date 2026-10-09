# 16 · Compute 后端优化 A/B 报告（O1/O2/O3/O5/O6）

> 对照：`research/15_高斯渲染器优化执行报告.md`（M1–M5），本报告是"多实例不占优势"的后续攻关。
> 机器：RTX 5060 / Godot 4.7.2 Forward+ / 1280×720 / vsync off。
> 场景：`fleet` = 100 节点（P1×40 + P2×30 + P3×30）= 225,000 splat（多实例）；`whale` = 1 节点 = 408,252 splat（单实例）。
> 工具：`experiment/gdgs_bench/ab_compute.py`（交错 reps、min-of-runs）、`compare.py`（PSNR/SSIM）。

---

## 0. 结论速览

| 优化 | 开关（默认关） | fleet（多实例） | whale（单实例） | VRAM | 判定 |
|---|---|---|---|---|---|
| **O3 跨帧复用排序** | `gdgs/opt/compute_reuse_sort` | **-10.7%** | ~0% | — | ✅ 采纳（有条件） |
| **O5 排序对预算 10→4** | `gdgs/opt/compute_sort_budget=4` | -0.1% | **-3.5%** | 139→102MB / 464→426MB | ✅ 采纳（主要是显存） |
| **O1 亚像素空间剪枝** | `gdgs/opt/compute_subpixel_prune` | -3.3% | -3.0% | — | ⚠️ 收益小，保留开关 |
| **O6 精简直方图清零** | `gdgs/opt/compute_lean_clear` | ±0.4%（噪声内） | — | — | ⚠️ 无收益，保留开关 |
| **O2 可见性判断提前** | 无开关（恒定生效） | 0 | 0 | — | ✅ 零风险重排 |
| **四项全开** | — | **-12.8%**（1.741→1.518ms） | **-12.9%**（1.151→1.003ms） | 102 / 426MB | ✅ |
| 对照：Raster | — | **0.893ms**（仍快 41%） | 3.205ms（慢 2.8×） | 57 / 91MB | — |

**但四个开关的像素影响全部落在后端自身噪声内**（同一配置跑两次：PSNR 42.0/45.6dB、SSIM 0.9985/0.9993、max_delta 162/157），见 §3。
**并且：多实例场景下 Compute 仍然打不过 Raster（1.52 vs 0.89ms）。** 本轮优化把它从"慢 95%"拉到"慢 70%"，没有翻盘；翻盘需要 §5 的下一层。

---

## 1. ⚠️ 方法学踩坑：改 .glsl 不跑导入 = 测了个寂寞

本轮最贵的教训，先写在这里：

```text
.godot/imported/gsplat_render.glsl-<hash>.res   编译后的 SPIR-V 缓存
```

**`.glsl` 计算着色器是被 import 的资源**：运行时 `load()` 拿到的是 `.godot/imported/` 里的已编译 SPIR-V，
只改源码不重新导入，**改动完全不生效**（也不报错）。本轮第一版 A/B 就是这么废掉的：
所有配置给出 -0.4% ~ -0.1% 的"无效果"，且"像素差异"其实来自后端自身的非确定性。

修复 + 防呆：

- 跑一次 `Godot_v4.7.2-stable_win64_console.exe --headless --path <proj> --import`；
- `bench_common.ensure_imports()` 封装了它，`ab_compute.py` 每次开跑前自动调用（`--no-import` 可跳过）。

验证手段（可复用）：把某个开关调成"必然破坏画面"的极端值，看图像是否真的变。本轮用 kill-switch
（`continue` 掉整个内循环）与 `compute_prune_scale=0.05`、`compute_sort_budget=1` 三个极端值确认了管线真的生效。

---

## 2. 性能 A/B（重新导入后，min-of-4 runs，warmup 60 / frames 150）

### 2.1 fleet（100 节点 / 225,000 splat）

| 配置 | mean ms | p95 ms | p99 ms | process ms | VRAM MB | vs base |
|---|---|---|---|---|---|---|
| base | 1.741 | 2.501 | 2.811 | 0.069 | 139¹ | — |
| prune (O1, ×2.0σ) | 1.683 | 2.297 | 2.480 | 0.053 | 139 | **-3.3%** |
| reuse (O3, 0.5°) | 1.554 | 2.267 | 2.679 | 0.075 | 139 | **-10.7%** |
| budget=4 (O5) | 1.739 | 2.488 | 2.777 | 0.053 | **102** | -0.1% |
| clear (O6) | 1.748 | 2.611 | 2.845 | 0.071 | 139 | +0.4% |
| **all** | **1.518** | 2.210 | 2.345 | 0.052 | **102** | **-12.8%** |
| raster（对照） | **0.893** | 1.323 | 1.379 | 0.025 | 57 | -48.7% |

¹ 表格取 4 次运行的 VRAM 最大值，其中一次出现 256MB 的瞬时峰值（重建期间的瞬时双份分配）；稳态 139MB。

### 2.2 whale（1 节点 / 408,252 splat）

| 配置 | mean ms | p95 ms | p99 ms | process ms | VRAM MB | vs base |
|---|---|---|---|---|---|---|
| base | 1.151 | 1.375 | 1.549 | 0.184 | 464 | — |
| prune | 1.116 | 1.334 | 1.533 | 0.180 | 464 | -3.0% |
| reuse | 1.149 | 1.330 | 1.479 | 0.183 | 464 | -0.1% |
| budget=4 | 1.110 | 1.409 | 1.686 | 0.158 | **426** | -3.5% |
| **all** | **1.003** | 1.254 | 1.369 | 0.157 | **426** | **-12.9%** |
| raster（对照） | 3.205 | 3.678 | 3.784 | 0.018 | 91 | Raster 慢 2.8× |

### 2.3 安全边界验证

| 测试 | 结果 | 说明 |
|---|---|---|
| 快转视角 1.0°/frame（base vs reuse） | 1.29 vs 1.30 ms | 视角变化超阈值 → 复用自动让路，每帧全量重排，**行为与 base 一致** |
| 慢转视角 0.15°/frame（base vs reuse） | 1.741 vs 1.554 ms | 每 ~3.3 帧仍全量重排一次（≈30% 帧付全价），收益即来自其余 70% 帧 |
| whale + reuse | 0.0% | 鲸的节点 transform 每帧变化 → `needs_instance_upload` → 强制全量重排（诚实记录：复用对"运动物体"无效） |

---

## 3. 像素 A/B（fleet 固定机位双机位，PSNR / SSIM / max_delta）

| 对比 | wide | close | 判定 |
|---|---|---|---|
| **对照：base vs base（同配置跑两次）** | 45.63dB / 0.9993 / 157 | 42.01dB / 0.9985 / 162 | 后端自身噪声 |
| prune | 45.49 / 0.9992 / 149 | 41.97 / 0.9985 / 168 | 噪声内 |
| budget=4 | 44.39 / 0.9990 / 176 | 41.82 / 0.9984 / 151 | 噪声内 |
| reuse | 45.55 / 0.9992 / 153 | 42.05 / 0.9985 / 175 | 噪声内 |
| all | 44.66 / 0.9991 / 177 | 41.77 / 0.9984 / 159 | 噪声内 |
| **极端值：prune_scale=0.05** | 32.25 / 0.9871 / 227 | 25.04 / 0.9549 / 249 | **明显可见**（证明评测能分辨） |
| **极端值：budget=1** | 43.34 / 0.9987 / 186 | 38.91 / 0.9966 / 239 | 可测差异（大 splat 被裁） |

**结论（重要）**：Compute 后端**本身不是逐像素确定的**——pair 顺序来自投影 pass 的全局 `atomicAdd`，且深度键只有 16 位、同 tile 内大量并列，导致同一配置两次运行的混合顺序可能不同。因此：
1. 上表里所有开关的像素差异 ≈ 对照的像素差异 ⇒ **本轮优化在这两个场景是像素中性的**；
2. 反过来也说明"用 PSNR 验收 Compute 改动"必须带同配置对照，否则会把噪声当回归。

---

## 4. 机制：为什么 O1（亚像素剪枝）只有 -3%

O1 的实现（`gsplat_render.glsl`）：投影 pass 把每个 splat 的屏幕半径写进 `depth_data.y`，
光栅化内循环先用 `|dx|>r·scale || |dy|>r·scale` 剪掉不在足迹内的像素。

测出来的三档：

| prune 半径 | fleet 帧时间 | 像素 |
|---|---|---|
| 关闭 | 1.741 ms | 基准 |
| ×2.0（=5σ，默认） | 1.683 ms（-3.3%） | 噪声内 |
| ×0.05（≈0.07px，几乎全剪） | 1.28 ms（-27%） | 明显破坏（PSNR 25–32dB） |

**机制**：光栅化 pass 的 chunk 循环条件是 `shared_t > MIN_FACTOR`（整 tile 的透射率），
密集 tile 在**未剪枝**时会很快被填满不透明 → 提前退出；
一旦剪枝，被剪掉的那些 splat 不再累加 alpha → `t` 居高不下 → **循环不再提前退出，反而把更多 chunk 跑满**。
于是"内循环省下的算术"和"多跑的 chunk 加载"互相抵消，只剩 -3%。
极端值那 -27% 也不是"剪枝赚到了"，而是"身体被剪光、只剩 chunk 装载"时的卸载上限——
**它给出的信息是：像素内循环最多只占帧时间的 ~27%，其余是 chunk 装载（每 chunk 256×64B 散读）与固定 tile 网格。**

---

## 5. 还没做的两项（为什么、以及要做的话怎么做）

| 项 | 状态 | 理由 | 落地方案 |
|---|---|---|---|
| **子块/两级空间结构**（层1c） | 未做 | 这是"多实例翻盘"的正解：把空间粒度从 16×16 降到 8×8 或子块，让每像素只遍历自己的子块列表，同时减少 chunk 装载。会改动 sort key 的 tile 编码宽度、渲染 workgroup 结构与 shared 布局，属于结构性改动，需要独立一轮 A/B | 方案 A：`TILE_SIZE 16→8`（pair 数上升 4×，需权衡）；方案 B：16×16 排序 + 块内 4×4 子块剔除（推荐，pair 不变） |
| **O8 姿态簇投影复用** | 未做 | 实测可省窗口小：编队的"投影+全局排序+boundaries"整段只有 ~0.35ms/1.74ms，其中投影只占一部分；而它需要新增一个 pre-pass、一个 `cluster×unique_splat` 缓存缓冲、以及实例姿态聚类逻辑 | 若要做：参考 `project_covariance()` 的推导——同姿态实例的 `cov_2d` 只差一个 `(d_ref/d_inst)²` 标量缩放，故可缓存 `(V·Cw·Vᵀ)` 的 2×2 块（每帧一次、按簇×唯一 splat），逐点只做标量缩放 |

---

## 6. 落地方式与复现

**新增开关（`project.godot [gdgs]` 已写入默认值说明）：**

```ini
opt/compute_sort_budget=10          ; 每 splat 的 pair 预算（10=原行为，4 推荐：显存 -27%）
opt/compute_subpixel_prune=false    ; O1 亚像素剪枝
opt/compute_prune_scale=2.0         ; 剪枝半径 = scale × 2.5σ
opt/compute_reuse_sort=false        ; O3 跨帧复用排序
opt/compute_resort_deg=0.5          ; 视角变化阈值（度）
opt/compute_resort_pos=0.01         ; 相机位移阈值（占相机到场景质心距离的比例）
opt/compute_reuse_animated=false    ; 是否允许动画实例复用（会滞后 1~N 帧）
opt/compute_lean_clear=false        ; O6 精简直方图清零
```

**改动文件：**

- `addons/gdgs/runtime/render/compute/shaders/gsplat_projection.glsl`
  — O2 可见性判断提前；发布屏幕半径；`sort_budget_in` 运行期预算；
  **顺带修掉一个真实溢出 bug**：巨型 splat 的裁剪块旧代码用 `side = budget-1`（10 → 9×9 = 81 对）会写出 N×budget 的排序缓冲，现在用 `side = isqrt(budget)`（10 → 3×3 = 9）。
- `addons/gdgs/runtime/render/compute/shaders/gsplat_render.glsl` — O1 剪枝（`radius_tile` 共享数组 + `prune_scale` push constant）。
- `addons/gdgs/runtime/render/compute/gaussian_renderer.gd` — 复用判定 `_view_needs_resort()`、`_render_pass()` 拆分、预算/剪枝/精简清零接线。
- `addons/gdgs/runtime/render/compute/gaussian_gpu_state_cache.gd` — 运行期预算定尺寸、精简清零字节数、复用状态字段、uniform 块扩到 64B。
- `addons/gdgs/runtime/render/compute/gaussian_scene_registry.gd` — `get_scene_center()`、`has_animated_instances()`。
- `experiment/gdgs_bench/ab_compute.py`（新）、`bench_common.py`（`ensure_imports()`）、`project.godot`（开关与说明）。

**复现：**

```powershell
cd <gdgs_bench 基准工程目录>
python ab_compute.py --scene fleet --configs base,prune,reuse,budget,clear,all,raster --reps 2
python ab_compute.py --scene whale --configs base,prune,reuse,budget,all,raster --reps 2
python compare.py --a runs/fleet_base --b runs/fleet_all --out reports/cmp_fleet_base_all.md
```

---

## 7. 建议

1. **多实例（编队/人群）继续用 Raster**：本轮把 Compute 的相对劣势从 +95% 压到 +70%，但没有质变；质变要靠 §5 的子块空间结构。
2. **单实例大云（星鲸类）用 Compute + 四个开关全开**：1.003ms vs Raster 3.205ms（3.2×），显存 426MB 仍是代价。
3. 只要用 Compute，就**建议开 `compute_sort_budget=4`**：两个场景都更快（-0.1% / -3.5%）且显存显著下降（-27% / -8%），像素在噪声内。
4. `compute_reuse_sort` 只在"每帧视角变化 < 阈值"时有效（高帧率 / 缓慢运镜 / 静态机位）；快速运镜时它会自动让路，可安全默认开启于"展示类"场景。
5. 任何 Compute 改动验收：**必须带同配置对照跑两遍**（噪声基线 PSNR≈42–46dB），否则会把后端非确定性当成回归。

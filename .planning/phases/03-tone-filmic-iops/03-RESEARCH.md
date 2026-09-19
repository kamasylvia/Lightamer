# Phase 3 Research: Tone & Filmic iops

**Researched:** 2026-09-19
**Confidence 汇总：** Darktable 模块数学映射 = High（源码逐行核过，含 OpenCL kernel）；darktable-cli golden 链路 = High（本机实测跑通 EXR 直通与 CLI 语法）/ **XMP 历史钉参 = 保留疑点**（预构建 binary 实测有缺陷，见 §6，需重建后复核）；toneequal/guided filter 移植设计 = High（算法）/ Med（性能预算需实测）；CIRAW displayed-domain 对 scene-referred 模块默认值的影响 = High（方向确定）/ Med（默认值校准量需 Phase 3 实测）。

---

## Summary

Phase 3 交付日常调色闭环（7 个 tone 模块 + filmic 家族）+ 首个 Inspector 参数面板框架 + darktable-cli golden 基建。核心结论：

1. **⚠ CONTEXT 文件清单两处勘误（不影响决策，影响 plan 输入）**：① Darktable **没有 `contrast.c`**——IOP-TONE-05 "contrast" 的对标模块是 **`colisa`**（contrast/brightness/saturation 三滑块，v50=47.0，Lab 域，`src/iop/colisa.c` 仅 285 行）；② **没有 `src/iop/guidedfilter.c`**——guided filter 实际在 **`src/common/guided_filter.c`（725 行）+ `src/common/fast_guided_filter.h`（CPU，349 行）+ `data/kernels/guided_filter.cl`（8 个 kernel）**。`agx.c`（2844 行，v50=45.5）是 IOP-FILM-03"其他 filmic 变体"的具体对标物。
2. **D-T1/D-T2（sigmoid 先行 → filmicrgb 完整移植）可行且正确**。sigmoid 的全部复杂度都在 CPU 侧参数推导（`commit_params` 一次算 4 个标量），kernel 是纯逐像素元素级运算；filmicrgb 同样是「CPU 样条推导 + 逐像素管线」，两者都可分解成 golden 可测子阶段。filmicrgb 的**高光重建子树默认关闭**（`enable_highlight_reconstruction=FALSE`），建议 plan 明确把 à-trous wavelet 重建划出本阶段（默认参数 parity 不需要它）。
3. **四个 display-referred 模块（tonecurve/shadhi/levels/colisa）在 Darktable 里全部工作于 Lab 域**（L 通道曲线/模糊，a/b 缩放）。要保持 parity，Lightamer 版本必须在模块内部做 Rec2020→Lab→Rec2020 往返（标准 CIE 变换 + D50 Bradford，矩阵固定、确定性可移植；`IOPColorspace.Lab` 枚举已预留）。不做 Lab 往返 = 放弃这 4 个模块的 golden parity——planner 需要显式拍板（Open Question #3）。
4. **golden 基建（D-T5）已实测跑通一半**：darktable-cli 对 linear EXR 的默认管线是**精确直通**（逐像素 float 差 ≤3.6e-7），`--icc-type LIN_REC2020` 的 EXR→EXR round-trip 可产出带 Rec2020 chromaticities 的规范 fixture。**但预构建 binary（2026-06-05，1263552fab-dirty）实测存在缺陷：XMP 附带的历史在 export 时被丢弃**（内存态不落库，export 重读库内默认行），直接改库也会被覆写。**Phase 3 第一个任务 = 从当前源码树（dc58cf0ba1）重建 darktable-cli**——顺带保证 `.so` 参数布局与移植参考源码一致（XMP params blob 的字节布局以源码 struct 为准）。XMP schema 与 params blob 编码已全部摸清（§6），重建后按 §6 配方验证。
5. **CIRAW displayed-domain 语义是 scene-referred 模块的最大 gotcha**（02-RESEARCH §3.1 预警，本阶段兑现）：管线输入已含 CIRAW 的 WB/基线曝光/内部 tone curve，不是真场景线性域。filmicrgb/sigmoid 的默认参数（black −8EV / white +4EV / grey 18.45%）假设场景线性输入，在 displayed-domain 输入上会把动态范围压进曲线极窄一段。**对策**：算法 parity 用合成场景线性 EXR fixture（两侧同输入，纯数学可比）；真机 RAW 上的默认值校准作为独立任务（exposure 默认 0EV 而非 dt 的 0.7EV，同理 filmic/sigmoid 默认黑白云点需按 CIRAW 输出实测再定）。
6. **toneequal 是性能/架构上唯一的重模块**：三段 Metal 图（luma 估计 → EIGF/guided 细节保持滤波 → LUT 增益施加），Darktable 本体无 OpenCL（CPU only，`toneequal.c:313 TODO`），Metal 移植是自由发挥但数学必须逐式对齐。guidance 滤波用 separable box mean（O(1)/px，与半径无关），PREVIEW 2560px 全在预算内；**TilingPlan 首战在 FULL 管线**（100MP 下 luma mask + 滤波中间平面乘法爆内存）。
7. **Inspector 框架（D-T6）的接缝全部现成**：`PipeCoordinator.beginContinuousEdit/setLiveParams/commitContinuousEdit` 三件套 + `ModuleBox.setParams`（hash 失效）+ `ModuleRegistry.makeBox`；缺的只是 slider 控件层与 `InspectorState` 的实体化（现在是 19 行 stub）。新增缝 = **色彩采样 plumbing**（WB 吸管 D-T4 + filmic auto 三键共用：viewport 坐标 → PREVIEW 纹理采样（L014 fence）→ 面积均值 → 参数更新 → 单条 history commit）。
8. **性能（PERF-5）余量充足但形状明确**：PREVIEW 2560px float32 平面 70MB，元素级 kernel 纯带宽约束 ≈0.35-0.7ms/趟，7-10 趟链 ≈3-5ms，60fps（16.6ms）内安全；toneequal guidance 多趟（~8-12 kernel）估 3-6ms 仍安全。禁止项不变：管线内 half（L006）、Swift Hasher、encoder 顺序（L008）。

**给 planner 的 plan 切分建议**（7 个，末尾 Open Questions 前详述）：A. dt-cli 重建 + golden 脚手架 → B. exposure + WB（含吸管）→ C. sigmoid + tonecurve + colisa + levels（CPU 推导 + 元素级 kernel 群）→ D. shadhi（首个域内模糊）→ E. toneequal + guided filter（TilingPlan 首战）→ F. filmicrgb（子阶段 golden 攻坚）→ G. Inspector 面板框架 + 色彩采样 plumbing（与 B 同步起步，G 的吸管先服务 B）。C/D/E/F 之间可部分并行，A/B 是全序头部。

---

## Implementation Approaches

### 1. Darktable iop 参数清单（每模块：params + 默认值 + auto 行为 + kernel 结构）

模块 v50 位次（`LightamerCore/Sources/Foundation/V50Order.swift` 已全数在表）：temperature 3.0 / exposure 21.0 / toneequal 24.0 / sigmoid 45.3 / agx 45.5 / filmicrgb 46.0 / colisa 47.0 / tonecurve 48.0 / levels 49.0 / shadhi 50.0。

#### 1.1 exposure（`src/iop/exposure.c`，1364 行）——最简单，建议打样

- **Params v7**（`:66-78`）：`mode`(manual/deflicker)、`black` ∈[−1,1] 默认 0、`exposure` ∈[−18,18] 默认 0、`deflicker_percentile` 50、`deflicker_target_level` −4、`compensate_exposure_bias`、`compensate_hilite_pres`（默认 TRUE）。
- **数学**（`:44-45, 479-521, 552-577`）：`white = exp2(−exposure)`；`out = (in − black) × 1/(white − black)`。`processed_maximum` 同步乘 scale（Lightamer 无此管线状态，省略并记录）。
- **auto 行为**：`reload_defaults`（`:346-370`）对 scene-referred RAW 首实例自动 `exposure=0.7 / black=−0.00024414 / compensate_exposure_bias=TRUE`。**Lightamer 不采用**（CIRAW 已烘入基线曝光；默认 0EV），记录为有意 divergence。deflicker（时间流逝防御）依赖直方图统计，Phase 3 不做（params 结构保留 mode 位）。exif 曝光偏移补偿（`:631-660`）可后补，依赖 RAW-06 元数据。
- **kernel**：`basic.cl:240-251` 单 kernel，`(pixel − black) × scale` 逐像素，uniform 2 个 float。**每拖动帧成本最低的模块，作为 Inspector 滑块 → D-H1 三件套 → 缓存失效全链的第一个真实载体**。

#### 1.2 temperature / WB（`src/iop/temperature.c`，2235 行）

- **Params**（`:66-75`）：`red/green/blue/various` 四通道增益 ∈[0,8]（默认 1.0）+ `preset`。UI 层把增益换算成 Kelvin/tint 显示（`_mul2temp`）。各种预设 = D65 等照明体系数表。
- **Kelvin→增益模型**（`:48-54, 287-473`）：K<4000 用 Planck 黑体 SPD、≥4000 用 CIE D-series SPD（Lindbloom 公式，`cmsWhitePointFromTemp` + S0/S1/S2 分量表）；SPD×CIE1931 CMF 积分→XYZ（归一化 max=1）；**tint = Y 除法 hack**（`xyz.Y /= tint`，源码自带 TODO 承认不正交）；XYZ→相机增益经 per-camera `XYZ_to_CAM` 矩阵（4×3，来自 `adobe_XYZ_to_CAM`，`:1370-1420`）。K 范围 [1901, 25000]、tint ∈[0.135, 2.326]，K↔XYZ 互求用二分搜索（`:396-432`）。
- **吸管**（`:1933-1955` `color_picker_apply`）：`gain[c] = clamp(1/picked[c], 0, 8)` 再按绿归一（`gain[g]=1.0`）——三行数学，直接进 D-T4。
- **kernel**：`basic.cl:229-239 whitebalance_4f` = 逐像素 `rgb × coeffs[3]`。
- **Lightamer 设计要点**：dt 的 Kelvin 模型需要相机 XYZ 矩阵（传感器域），Lightamer 是 CIRAW 后的 Rec2020 校正层——**Kelvin→增益改为 Rec2020 原生换算**：目标照明 SPD→XYZ→（Bradford）→Rec2020 白点 T，`gains = W/T`（W=D65 在 Rec2020 下 = (1,1,1)），tint 沿用 Y-hack 语义在 Rec2020 上复现。吸管路径与 dt 完全同构（通道比值与域无关，灰色在任意 D65 锚定 RGB 下同值）。D65 系数表、SPD 分量表、CMF 表都需要随源码搬进 Swift（约 100 行数据表）。

#### 1.3 tonecurve（`src/iop/tonecurve.c`，1971 行）

- **Params v5**（`:97-108`）：`tonecurve[3][20]` 节点（L/a/b 三曲线）+ `tonecurve_nodes[3]` + `tonecurve_type[3]`（MONOTONE_HERMITE 默认/CATMULL_ROM/CUBIC_SPLINE）+ `autoscale_ab`（manual/L-ab/XYZ-linked/RGB-linked）+ `unbound_ab` + `preserve_colors`（RGB norm 家族，`rgb_norms.h`）。
- **域**：**Lab**。L_in∈[0,100] 查 0x10000 LUT（CPU 预计算，monotone Hermite 插值），超界用抛物线外推系数（`unbounded_coeffs_L[3]`）；ab 按 autoscale 模式联动（RGB-linked 走工作 profile 亮度）。process_cl（`:301-398`）显式取 ProPhoto 工作 profile 做 Lab 变换。
- **kernel**：`basic.cl:1426-1490`——LUT image2d ×3 + coeffs + 逐像素三模式分支。
- **Lightamer**：REQUIREMENTS 说「可作用于 RGB/各通道」。**parity 路线 = 移植 Lab 往返**（Rec2020→XYZ→Lab D50 + 曲线 + 回程），曲线 LUT/Hermite 求值在 CPU commit 时做（参数变更一次，10001 点 LUT 上传 buffer）。UI 曲线编辑器（拖节点）是本模块 UI 大头，Phase 3 的 D-T6 面板框架要预留 curve-editor 控件位（可先出 5 节点最小版）。

#### 1.4 shadhi / shadow & highlight（`src/iop/shadhi.c`，705 行）

- **Params**（`:65-80`）：`radius` ∈[0.1,500] 默认 100、`shadows` ±100 默认 +50、`highlights` ±100 默认 −50、`whitepoint`、`compress` 50、`shadows_ccorrect` 100、`highlights_ccorrect` 50、`flags`（unbound 位）、`shadhi_algo`（bilateral 默认 / gaussian）。
- **数学**（`:356-490`）：**Lab 域 L 通道**。先产模糊底：bilateral 基底层（`dt_bilateral` sigma_r=100 固定，detail=−1）或 4 通道 gaussian（sigma = radius × roi.scale / iscale）；然后 overlay 混合：`highlights_xform = clamp(1 − Lb/(1−compress))`、`shadows_xform = clamp(Lb/(1−compress) − compress/(1−compress))`，`shadows2/highlights2 = (±strength×2)²` 循环施加（>1 时两次迭代），色度保持因子 `chroma_factor = L'a×lref×(1−cc) + (1−L'a)×href×cc`。公式逐式可移植（`:426-490` 全部是标量运算）。
- **kernel**：无自有 .cl——组合 `gaussian.cl`（separable）与 `bilateral.cl`（splat/blur/slice 三趟）+ 逐像素 overlay 段自写。
- **Lightamer**：模糊段是 Phase 3 第一个「域内大半径模糊」——bilateral 网格移植较大，**gaussian 腿先做**（algo 参数保留双值，bilateral 后置 Open Question）。Lab 往返同 §1.3。

#### 1.5 contrast = colisa（`src/iop/colisa.c`，285 行）

- **Params**（`:44-48`）：`contrast/brightness/saturation` 各 ∈[−1,1] 默认 0。
- **数学**（`:190-241` + `basic.cl` colisa kernel）：**Lab L 域**。contrast>0：软 S 形 `L' = 50×(cs·(x²−1)/√(1+c²(x²−1)²) + 1)`（:206）；contrast<0：绕 50 的线性；brightness：`L'' = 100×(L'/100)^gamma`（gamma=10^(−brightness)，:225）；saturation：a,b × (1+sat)。CPU 预计算 ctable/ltable（0x10000）。
- **Lightamer**：最薄的 Lab 模块，与 levels/tonestring 共用 Lab 往返 + LUT 基建。UI 三滑块。

#### 1.6 levels（`src/iop/levels.c`，1000 行）

- **Params**（`:60-67`）：`mode`（manual/automatic）、`black/gray/white` ∈[0,100]（0/50/100）、`levels[3]`、`percentiles[3]`。automatic 模式按直方图百分位（black 2%/gray 50%/white 99.8% 类）在 `commit_params_late` 自动求值（`:215-247`）——**需要下采样直方图 pass（GPU 归约）**，manual 模式不需要。
- **数学**（`:407-431`）：`L_in ≤ black → 0`；否则 `percentage=(L_in−black)/range` → LUT/`pow(percentage, −inv_gamma)`；`a,b ×= L_out/max(L_in,0.01)`（色度保持）。
- **Lightamer**：manual 模式 parity 直取；automatic 的直方图归约是 Phase 3 唯一的新 GPU 模式（MPS histogram 或自写两趟归约，独立小 spike）。

#### 1.7 toneequal（`src/iop/toneequal.c`，3446 行）→ 详见 §4

#### 1.8 filmicrgb（`src/iop/filmicrgb.c`，4758 行）→ 详见 §2

#### 1.9 sigmoid（`src/iop/sigmoid.c`，982 行）→ 详见 §3

#### 1.10 agx（`src/iop/agx.c`，2844 行，IOP-FILM-03 候选）

- **Params**（`:105-140`）：look 五元组（lift/slope/brightness/saturation/hue-mix 默认 0.6）+ range（black −10EV / white +6.5EV / dr-scaling）+ 曲线七元组（pivot/contrast 3.0/toe-shoulder ratio/power/gamma 2.2/target black/white）+ `base_primaries`（**默认 Rec2020**，对 Lightamer 天然亲和）+ inset/rotation。
- **kernel**：`agx.cl:216` 单 kernel `kernel_agx`（sigmoid trapezoid 曲线 + primaries 调整），CPU 侧推导小。**建议 v1 的 FILM-03 落 agx**（与 sigmoid 共享 per-channel primaries 基建，工作量小）；「hatchless」无源码对标，记录为无对标项。

#### 1.11 WB 吸管流程（D-T4）

`EditorMTKView` 点击 → 视图坐标 → PREVIEW 纹理归一坐标 → 读回 linear Rec2020 值（**必须 drain/fence**，L014 先例；建议采样点周围 N×N 均值，对齐 dt 的 AREA picker 语义）→ `gains = normalize(1/picked)`（§1.2）→ WB 实例 `setLiveParams` 预览 → 单击语义按 D-H1「离散控件一次一 commit」处理。与 filmic 的 auto grey/black/white 三键（§2）共用同一 plumbing。

---

### 2. filmicrgb 深挖（最难移植；golden 子阶段切分）

#### 2.1 结构总览：两段式 = CPU 推导 + 逐像素管线

全部难点中**没有一处需要局部归约或邻域访问**（高光重建除外——见 2.5，默认关闭）。这是把 ~2000 行 scene-linear 数学拆成可 golden 验证子阶段的关键前提。

**CPU 段（commit 时一次，`filmicrgb.c:410-560` `dt_iop_filmic_rgb_compute_spline` + `_compute_output_power`）**——纯 Swift 逐式直译 + 单元测试即可锁死：
1. `dynamic_range = white_point_source − black_point_source`（EV，默认 4−(−8)=12）。
2. `grey_display = 0.1845^(1/output_power)`（custom_grey 关时；`filmicrgb.c:428-437`）。
3. log 域锚点：`black_log=0`、`grey_log=|black_source|/dynamic_range`、`white_log=1`（`:440-443`）。
4. `black_display/white_display = (black/white_point_target/100)^(1/output_power)`（v2/v3 路径，`:452-458`）。
5. toe/shoulder 节点由 `latitude`/`balance`/`contrast` 推（v3 splines，`:460-540`），含 `SAFETY_MARGIN` 钳制。
6. **样条系数 M1..M5（float4×5：toe/shoulder/latitude 三段各配）+ `latitude_min/max`**——poly4 用 Horner 形式（`filmic.cl:247-296` 注释即公式）。
7. `_compute_output_power`（`:2560-2570`）：`output_power = log(grey_target/100)/log(−black_source/(white_source−black_source))`（auto_hardness 默认 TRUE，参数被覆盖）。
8. `norm_min/norm_max = exp_tonemapping_v2(0/1,…)`（process_cl `:2394-2395`）——norm 的 log 域钳制界。

**GPU 段（默认 V5 色彩科学路径 = `filmic_chroma_v5`，`filmic.cl:470-560`）**，每像素九步：
1. `norm = clamp(max_rgb(i), norm_min, norm_max)`（V5 固定 MAX_RGB norm；`get_pixel_norm` 家族在 `filmic.cl:171-198`，含 luminance/power/euclidean 变体供 preserve_color 参数选择）。
2. `ratios = i / norm`（负值 sanitize：减 min_ratios）。
3. log 编码：`norm = clip((log2(norm/grey) − black_source)/dynamic_range)`（`log_tonemapping_v2`，`filmic.cl:302-310`）。
4. S 曲线：`norm = filmic_spline(norm, M1..M5, lat_min, lat_max, types)`（`filmic.cl:230-296`：x<lat_min 走 toe poly4/poly3/rational，x>lat_max 走 shoulder，之间线性）。
5. 显示钳制 + 输出幂：`norm = pow(clamp(norm, black_display, white_display), output_power)`。
6. `max_rgb_out = norm × ratios`；**同时**算 naive 逐通道路径（每通道 log→spline→clamp→pow）。
7. V5 混合：`o = (0.5 − saturation)·naive + (0.5 + saturation)·max_rgb`。
8. **Yrg 域 gamut 映射**（`gamut_mapping`，`filmic.cl:658-720`）：经 `matrix_in`（pipeline RGB→CIE LMS 2006）转 Ych → 强制 hue=original → Y 钳到 [display_black, display_white]（CIE Y1931↔Y2006 换算）→ `filmic_desaturate_v4` → `gamut_check_Yrg`（Yrg 三角形内插）→ `gamut_check_RGB` 回 pipeline RGB（可选 export 矩阵绕行 LMS）。
9. alpha 透传。

矩阵 `matrix_in/matrix_out` 由 CPU 按工作 profile 预导（`filmic_v4_prepare_matrices`，process_cl `:2396-2410`）；Lightamer 工作域恒为 linear Rec2020 → 矩阵是编译期常量（与 terminal trio 同法）。V5 混合与 gamut 映射的中间色度域（LMS 2006 Kirk/Filmlight Yrg）需要 3×3 常量矩阵 + Ych 球坐标换算，全部标准公式。

#### 2.2 子阶段 golden 切分（D-T1 的兑现方案）

| 子阶段 | 域 | 可独立验证方式 |
|---|---|---|
| F0 CPU 推导（M1..M5、power、norm_min/max） | CPU | Swift 单测：公式直译向量对照（同源数学双实现互验） |
| F1 log 编码 + S 样条 + pow（1D 复合函数） | 1D 曲线 | 10001 点 LUT 对照：Lightamer CPU LUT vs Metal kernel 采样 vs（重建后）dt-cli 单模块 EXR |
| F2 V5 双路混合 | 逐像素 | EXR round-trip 单模块 golden |
| F3 Yrg gamut 映射 | 逐像素 | 同上 + 专用 out-of-gamut fixture（饱和色块） |
| F4 全模块 | 全链 | torture EXR 组 vs dt-cli（§6 配方） |

高光重建子树（2.5）单独编号 F5，默认不进本阶段验收。

#### 2.3 保留色彩变体（preserve_color 参数）

`DT_FILMIC_METHOD_MAX_RGB / LUMINANCE / POWER_NORM（默认）/ EUCLIDEAN_V1/V2 / NONE`（`filmic.cl:171-198`，norm 公式在 `rgb_norms.h`）。v1 建议：全部实现（norm 是一行函数，成本低），V5 色彩科学固定用 MAX_RGB；V1-V4 色彩科学不移植（`filmic.cl` 的 v1-v4 分支是历史包袱，dt 默认 V5）——**需要在 plan 里显式声明「colorscience 只落 V5」**，params 枚举保留位。

#### 2.4 auto 三键（grey/black/white 吸管）

`apply_auto_grey`（`:2575-2605`）：picked 色的 norm/2 → grey_point_source，K 对称缩放 black/white；`apply_auto_black/white` 用 `picked_color_min/max` + MAX_RGB norm。全部 CPU + 色彩采样 plumbing（§7），数学直译。

#### 2.5 高光重建（默认关闭 → 建议划出）

`filmic_mask_clipped_pixels`（Sigmoid 权重 mask）→ `filmic_inpaint_noise`（xoshiro128+ 噪声）→ à-trous wavelet 分解重建（bspline separable h/v 趟 + `wavelets_reconstruct` 按 gamma/beta/delta 权重合成，process_cl `:2100-2140`）→ 可选 HQ 循环（compute/restore_ratios，`high_quality_reconstruction` 次）。**参数默认 FALSE + torture 样本无大面积裁剪时 parity 不需要它**。plan 建议：本阶段只落 mask kernel + 参数位，重建子树挂 TODO（Phase 8 HDR 或 v1 后期）。——若 planner 判断必须进 v1，工作量另计约 +60%。

---

### 3. sigmoid（风险缓冲，先行落地）

- **Params**（`:57-74`）：`middle_grey_contrast` ∈[0.1,10] 默认 1.5、`contrast_skewness` ±1 默认 0、`display_white_target` ∈[20,1600] 默认 100（%）、`display_black_target` 默认 0.0152（%）、`color_processing`（per-channel 默认 / rgb-ratio）、`hue_preservation` 默认 100、RGB inset/rotation 六元组（默认 0）、`purity`、`base_primaries`（默认工作域）。预设里 scene-referred 默认 `middle_grey_contrast=1.22/1.6/1.0/1.5` 数枚（`:249-277`）。
- **CPU 推导**（`commit_params :318-407`，全部标量）：约束 `f(0)=display_black`、`f(MIDDLE_GREY)=0.1845`、`f(∞)=display_white`、grey 处斜率只由 contrast 决定 → `paper_power = 5^(−skew)`；数值差分求参考斜率 → `film_power`；`white_grey_relation / white_black_relation` → `film_fog`、`paper_exposure`。**直译 Swift + 黄金向量单测**（引用 `MIDDLE_GREY 0.1845`，`sigmoid.c:37`）。
- **kernel（`sigmoid.cl`，2 个，直接 MSL 转写）**：
  - `sigmoid_loglogistic_per_channel`（`:172-223`）：pipe→base 矩阵 → 负值去饱和（`_desaturate_negative_values`）→ base→rendering → 逐通道 `f(v) = magnitude·pow(film_response/(paper_exp+film_response), paper_power)`（`filmic.cl` 同款稳定形式，`sigmoid.cl:103-113`）→ **hue+energy 保持**（min/mid/max 排序 + 能量约束中通道校正，`:115-170`，40 行标量）→ rendering→pipe。inset/rotation 矩阵仅当参数非零时非恒等（`_calculate_adjusted_primaries`，AgX 思路，`sigmoid.c:409+`）。
  - `sigmoid_loglogistic_rgb_ratio`（`:225-295`）：luma=(R+G+B)/3 → f(luma) → 等比缩放 → 双曲 gamut 压缩（chroma_vs_mapping_border × display_border 距离比，`:272-291`）。
- **为什么是风险缓冲**：无 Lab、无样条拟合、无邻域、CPU 推导 40 行；先行落地即建立「scene-referred tone mapping」的面板/缓存/,golden 全链路，filmicrgb 攻坚期 sigmoid 可兜底产品需求。**与 Lightamer 的输入语义 caveat 同 §2.6**：display_white/black_target 是「输出端」参数，与输入域无关，默认值可直接用——这是它比 filmicrgb 更稳的直接原因。

---

### 4. toneequal + guided filter（D-T3；TilingPlan 首战）

#### 4.1 数学结构（三段 Metal 图）

- **Params**（`:170-190`）：9 个 EV 带（noise/ultra_deep_blacks/deep_blacks/blacks/shadows/midtones/highlights/whites/speculars，各 ±2EV 默认 0）+ `blending` ∈[0.01,100] 默认 5（smoothing diameter %）+ `smoothing` √2 + `feathering` + `quantization` + `contrast_boost` ±16 + `exposure_boost` ±16 + `details`（**默认 EIGF**；none/guided/EIGF 五值）+ `method`（luma 估计器，默认 NORM_2）+ `iterations` 1。
- **段 1：luma mask**（`common/luminance_mask.h`，header-only）：9 种估计器（RGB sum/euclidean/power norm/max/min/average…，`:45-47` 等），逐像素 + `linear_contrast(exposure_boost×lum, fulcrum=exp2(−4), contrast_boost)`（`toneequal.c:132`）。
- **段 2：细节保持滤波**（`compute_luminance_mask`，`:866-934`）：EIGF（默认）= exposure-aware 迭代引导滤波（`fast_eigf_surface_blur`，`fast_guided_filter.h:268-349`，radius = blending% × 图尺寸 × scale，feathering 作 eps，iterations 次扩散，quantization 作步进）；guided = `fast_surface_blur`（box mean 分离趟）；none = 直通。**radius 与图像尺寸成正比 → FULL 管线大半径**。
- **段 3：校正施加**（`apply_toneequalizer`，`:774-803`）：`exposure = clamp(log2(luma), −8, 0)` → 查 `correction_lut[10001]` → RGB × gain。LUT 由 CPU 在 commit 时构建：用户 9 参数 → 8 控制点 radial-basis（gaussian σ=√2，`gaussian_denom/func`，`:751-768`）插值（`interpolation.h` 三次样条）→ clamp [0.25, 4]。**UI 曲线图也用同一插值矩阵（`CHANNELS×PIXEL_CHAN`）**——CPU 代码一份两吃。

#### 4.2 Metal 移植设计

```
kernel luma_estimate(method 常量特化)            // 逐像素, r32Float mask plane
kernel eigf_box_mean_x / _y (分离 box, O(1)/px)   // guided_filter.cl:43-163 同构
kernel eigf_covariance / variance / solve / apply // guided_filter.cl:164-325 同构
kernel toneeq_apply(lut buffer, gain)             // 逐像素
```

- `guided_filter.cl` 的 8 个 kernel（split_rgb/box_mean_x/box_mean_y/covariances/variances/update_covariance/solve/generate_result，`:22-325`）本来就是为 OpenCL 写的 tile-safe 分离盒式滤波，**逐 kernel 直译 MSL 即可**；EIGF 差异（exposure 权重项）按 `fast_guided_filter.h` CPU 版补进 solve 段。
- box mean 用滑动窗口/局部和实现 O(1)（半径无关）；PSO 常量特化 radius 档（或 uniform radius + 滑窗），METAL-7 的 threadgroup 限制不构成约束（无共享内存依赖）。
- **TilingPlan 接入点**：PREVIEW（2560px，mask+LF 平面各 26MB）无需分块；FULL（100MP，float mask 400MB × 迭代中间平面）必须分块 + overlap ≥ 最大 radius（blending% × 尺寸——overlap 策略按 `TilingPlan.tiles` 的占位参数兑现，这是脚手架注释里预留的「wavelet scale halo 语义顶替」场景）。**FULL 是 on-demand 管线，不占 60fps 预算**——分块只服务内存上限（D-C1 3GB）与正确定性。
- **golden**：Darktable 无 CL 路径（CPU only）——EXR round-trip 照常可用（dt-cli 走 CPU 跑 toneequal，输出与 Lightamer Metal 比对）；EIGF 的迭代浮点顺序差异预计需要放宽容差（相对误差 ~1e-4 级而非 1e-6），plan 预设两档容差。

---

### 5. WB temperature/tint 模型（含 CIRAW 交互验证）

- **CIRAW 侧事实**（Phase 1/2 已核）：CIRAW 内部完成 WB（`neutralChromaticity` 等），Lightamer `ColorInModule` 是恒等——管线输入是「CIRAW 显影域 linear Rec2020」。**Lightamer 的 WB = post-hoc 通道增益校正层**，与 dt 的 sensor 域增益在数学上不同域但在「灰世界假设」下等价（对中性色两侧同样把 picked→白）。
- **模块语义**：params = 3 通道增益（0-8，默认 1.0）+ Kelvin/tint 派生视图 + preset 枚举（spot/d65/…，对齐 dt `DT_IOP_TEMP_*`）。Kelvin→增益换算按 §1.2 的 Rec2020 原生方案（SPD→XYZ→Bradford→Rec2020）。CMF/SPD 数据表随 `temperature.c` 头部常量搬移（`cie_1931_std_colorimetric_observer[]`、`cie_daylight_components[]`）。
- **与 dt 的 golden 关系**：EXR 输入下 dt 的 temperature 仍有 Kelvin 面板吗？dt 对非 RAW 用文件矩阵（EXR 无）——**吸管增益路径（spot preset）是双方共有的确定语义**，golden 用「三通道增益直设」钉参（绕开 Kelvin 模型差异），Kelvin 换算本身用 CPU 单测锁（与 dt 的 K→XYZ 段逐值对照，XYZ 之前两侧同源）。
- **自动 WB（import 时）**：不做（CONTEXT deferred 项确认）——CIRAW 已经按相机元数据做了 as-shot WB。

---

### 6. darktable-cli golden 参考生成（D-T5；本机实测记录）

#### 6.1 已验证可用

- CLI 语法：`darktable-cli <input> [XMP] <output-stem|DIR> [--out-ext exr] [--icc-type LIN_REC2020] [--width/--height] [--apply-custom-presets 0] [--library <db>] [--core -d params|all]`。`--icc-type` 支持枚举含 `LIN_REC2020/LIN_REC709/SRGB/...`（`--help icc-type` 实测）。
- **EXR 直通基线**：64×64 灰阶 ramp（−8..0EV）默认管线 round-trip 逐像素最大差 **3.6e-7**（float32 精度级）。默认启用链 = `colorin exposure(0EV) finalscale colorout gamma`（`-d imageio` 日志实证），对 EXR 输入零色调干预。
- **EXR chromaticities 语义**：EXR 无 chromaticities 属性 → dt 按 linear Rec709 读（`imageio_exr.cc:273-275`）；有 → 构 ICC 交给 colorin。**规范 fixture 生产线**：任意线性 EXR → `--out-ext exr --icc-type LIN_REC2020` 一次 round-trip → 产出「值已换算为 Rec2020 + 属性已标记」的 canonical fixture（实测属性被写入）。dt 的 EXR export 对 LIN_REC2020 写 chromaticities（`imageio/format/exr.cc:209-232`）。
- Lightamer 侧读 EXR 是 Phase 2 RAW-03 已验证的 float 路径（ImageIO），两侧共享同一 fixture。

#### 6.2 已确认的阻塞缺陷（Phase 3 首任务 = 重建）

预构建 `build/bin/darktable-cli`（2026-06-05，`1263552fab-dirty`；源码树已前进至 `dc58cf0ba1` 2026-08-02）实测：

1. **XMP 附带历史被丢弃**：`cli/main.c:666-681` 把 XMP 读进 image cache 后以 `DT_IMAGE_CACHE_RELAXED` 释放（不落库）；export 从 library DB 读历史 → 拿到的是 import 时自动种子行（默认参数）。实测 marker 值（percentile=100）从未出现在 DB，输出恒等默认。
2. **直接改 library DB 也会被覆写**：export 过程用内存态（默认）回写 `history.op_params`（实测 +1EV blob 被重置为默认字节）。
3. 参数 blob 编码本身已验证正确：`sizeof(dt_iop_exposure_params_t)=28`、`modversion=7` 与源码一致（dlopen 探针读 `.so` introspection 实测 `size=28`）。

**对策（写入 plan 的前置任务）**：`cmake --build` 重建当前树（或最少 `darktable` + `darktable-cli` 目标），重建后按 §6.3 配方重验 XMP 链路。重建同时保证所有 `.so` 的参数布局与「移植参考源码」逐字节一致——**这是 XMP blob 编码正确性的前提**，比修 golden 流程本身更重要。

#### 6.3 XMP 钉参配方（schema 已从 `exif.cc` 逐字段核过）

- **命名空间/字段**（`exif.cc:418-428`）：`Xmp.darktable.{history, history_modversion, history_enabled, history_end, history_operation, history_params, iop_order_version, iop_order, multi_priority, multi_name, blendop_version, blendop_params, xmp_version}`；`xmp_version ∈ {4,5}` 走 `_read_history_v2`（Exiv2 XmpData 数组路径，`:4245-4347`）；sanity 要求每 entry 有 operation+params+modversion（`:3813`）。
- **params blob**：`dt_exif_xmp_encode` = 纯 base64（>100B 才 zlib，`exif.cc:3218-3241`）；解码器认 `gz` 前缀（`:3317`）。C struct 按 `<` 小端 `struct.pack` 直排（exposure v7 = `<iffffii` 28B，gboolean=int）。**每个模块的 pack 格式表在 plan 里从源码 struct 逐个登记**（列在 §1 各节）。
- **blendop**：可不写（reader 缺省给 default_blendop）；写则必须 `blendop_version == dt_develop_blend_version()`（实测当前=14）且长度 = sizeof(dt_develop_blend_params_t)，否则标 WRONG 但不阻塞（走默认混合）。
- **`regenerate.sh` 结构**（D-T5 产物）：
  ```bash
  # input/golden/regenerate.sh
  DT=/Volumes/UNITEK/Documents/Development/darktable/build/bin/darktable-cli
  gen_fixtures            # ① uv 脚本产合成 EXR（灰阶 ramp/饱和色块/out-of-gamut/深阴影）
  roundtrip_fixture       # ② $DT in.exr fixture --out-ext exr --icc-type LIN_REC2020（产 Rec2020 规范件）
  for case in cases/*.xmp # ③ 每测试案例一个 XMP（单模块钉参）
     $DT fixture.exr case.xmp out/$case --out-ext exr --icc-type LIN_REC2020 --apply-custom-presets 0 --library /tmp/golden.db
  manifest                # ④ 记录 commit id + 参数 blob hash + 输出 sha256
  ```
- **回退方案**（若重建后 XMP 仍异常）：用 GUI 版 darktable 人工产出每模块「模板 XMP」一次，脚本只替换其中的 params base64（模板由 Exiv2 写出，保证可解析）。不阻塞 golden 主线。

---

### 7. Inspector 参数面板框架（D-T6）+ 色彩采样 plumbing

- **现状**：`InspectorState`（19 行 stub：selectedPanel/expandedSections）、`InspectorView`（ContentUnavailableView 占位）、token 体系在 `LightamerColors`（UI-SPEC Color 契约）。D-H1 三件套在 `PipeCoordinator` 全部就位（`beginContinuousEdit`/`setLiveParams(ModuleInstance)`/`commitContinuousEdit(label:)`，`PipeCoordinator.swift:696-732`），外加 undo/redo/jump。
- **面板数据流（双暴露）**：
  ```
  Slider drag begin  → coordinator.beginContinuousEdit()
  Slider tick (v)    → 新 ModuleInstance(params 更新, 同 instanceID)
                       → coordinator.setLiveParams(snapshot)   // 只重渲 PREVIEW，0 条 history
                       → box 经 rematerializeInstances 原位 apply（byte 同 → 缓存全 hit 只重算本模块）
  Slider drag end    → coordinator.commitContinuousEdit(label)  // 恰 1 条 HistoryItem + sidecar 节流写
  ```
  滑块显示值从 `editorState.instances` 的 typed params 读（`ModuleInstance.params(of:)` 已有）。
- **ModuleRegistry 驱动的面板生成**（最小缝）：
  ```swift
  public protocol IOPPanelProvider: Sendable {
      associatedtype M: IOPModule
      var opName: String { get }
      @ViewBuilder func panel(box: ModuleBox<M>, edit: InspectorEditSession) -> some View
  }
  ```
  `InspectorState` 持 `[any PanelProviderFactory]`（按 opName 分发，@MainActor）；v1 先手写 9 个 provider（exposure/WB 最先），反射式通用滑块生成留扩展。**滑块控件**：`LightamerSlider`（SwiftUI `Slider` + `onEditingChanged` 映射三件套 + 数值 readout + double-click 归零），token 化样式进 Theme。
- **色彩采样 plumbing**（D-T4 + filmic auto 三键共用）：`EditorAreaView` 点击手势（现有几何输入缝）→ `PipeCoordinator.samplePreview(at: NSEvent)`：归一坐标 → PREVIEW 纹理 `getBytes` N×N（**fence 后读**，L014 同族；或独立小 commandBuffer + waitUntilCompleted）→ 面积均值（dt AREA picker 语义，`color_picker_proxy` 的 3×3~5×5）→ 回调 `(simd_float3) -> Void`。WB 吸管：`gains = normalize(1/picked)`；filmic auto grey：`grey = norm(picked)/2`；auto black/white：对全图 min/max 的需求（dt 用 `picked_color_min/max` 全图统计）→ **需要一次 PREVIEW 全图归约**（MPS histogram 或两趟 reduce，与 levels automatic 共用，Open Question #6）。
- **UI 红线**：面板永不写 `displayTexture`（D-X1 单生产者不变量）；拖动风暴由 PipeCoordinator generation newest-wins + 缓存命中天然抑制（METAL-8 的预防已在 Phase 2 架构内）。

---

### 8. 性能约束（PERF-5）与 TilingPlan

- **预算账**（spike-b 基线：cached-frame blit 15.6ms@102MP；PREVIEW 2560px float32 平面 = 70MB）：
  - 元素级 kernel（exposure/WB/sigmoid/filmic 主体/colisa/levels/toneeq-apply）：70MB 读 + 70MB 写 ≈ 0.35-0.7ms/趟（M4 ~400GB/s 有效带宽）；典型链 5-8 趟 = 2-6ms。
  - Lab 往返（4 个 display-referred 模块）每模块 2 次全平面矩阵 pass ≈ +1.4ms——同链堆叠 4 个时 ≈ 6ms，仍在预算内；**优化位**：相邻 Lab 模块共享一次往返（pipe 级 colorspace 协商，dt `IOP_CS_LAB` 段语义；v1 可不做，plan 记录）。
  - toneequal：luma(1) + EIGF box 群(~8-12) + apply(1) ≈ 3-6ms@PREVIEW。60fps 合计余量 >5ms。
- **FULL 管线 = TilingPlan 首战**：100MP float32 全幅平面 1.55GB；toneequal 需 mask 平面 + 2-3 个滤波中间平面 → 单模块 >3GB 直破 D-C1 预算。`TilingPlan.tiles(maxTileBytes:overlap:)` 的 overlap 从占位值改为 `max(radius, 1) + halo`（radius = blending% × 长边 × scale）；分块执行语义 = `PixelPipe.processRec` 头部挂接注记处（Phase 2 预留）逐 tile 驱动。**验收口径**：FULL toneequal 100MP 内存峰值 < 3GB 且输出与整幅结果逐 tile 一致（overlap 正确性测试）。
- **PSO 冷启动**（METAL-5）：Phase 3 新增 ~25-35 个 kernel × 少量常量特化 → 仍在 256 项 LRU 内；首次拖动前预热当前链 PSO（app 启动后台 Task，open Question #7）。

---

## Validation Architecture

1. **golden 双轨**：
   - **算法 parity 轨（新）**：合成场景线性 EXR fixture →（重建后）dt-cli 单模块钉参 → EXR 输出 vs Lightamer 同 fixture 同参数 → linear 域逐像素比对。容差两档：元素级纯数学模块 <1e-5 相对误差；含迭代/滤波（toneequal EIGF、shadhi bilateral）<1e-4 + 感知判据（ΔE < 1.0 的 99% 分位）。**只在 fixture 上做 full-image diff，绝不用真机 RAW 做 parity**（CIRAW vs dt 解码域不同，02-RESEARCH §3.1）。
   - **显示正确性轨（复用）**：Phase 2 双判据 harness（中性度 + ColorSync 交叉一致性）对新模块链回归——保证新 iop 插入后 terminal trio 语义不被破坏。
2. **fixture 组**（`input/golden/fixtures/`，脚本可复现）：灰阶 ramp −8..0EV（tone 主靶）、0/-4/-8EV 平场、饱和色块（R/G/B/C/M/Y 100% + out-of-Rec2020 光谱色，gamut 映射靶）、深阴影梯度（banding 靶，METAL-2）、中性灰阶梯（WB 吸管靶）、10001 点 1D 阶梯（曲线 LUT 靶）。
3. **CPU 推导单测**：sigmoid `commit_params` 四标量、filmic 样条 M1..M5/输出幂/norm 界、toneequal correction LUT、WB K→增益、Lab 往返矩阵——全部「公式直译 + 已知向量」双实现互验，不依赖 dt 二进制。
4. **性能断言**：PREVIEW 链（全模块启用）单帧 < 16.6ms 的 CI 记录（os.signpost 汇总，Phase 1 模式）；FULL toneequal 100MP 内存峰值 < 3GB。
5. **合并闸门**：沿用 Phase 2 口径——每模块 golden 过闸才 merge（SOLO-2）；容差常量写死在测试内，超差输出差值表 + EXR dump。

## Risks & Gotchas

1. **dt-cli 重建是硬前置**（§6.2 实测缺陷）——不重建则 D-T5 整条 golden 线不可用；重建后 XMP 链路需 1 个验证任务兜底，回退方案是 GUI 模板 XMP。
2. **displayed-domain 输入 vs scene-referred 默认值**（§Summary#5）：filmic/sigmoid/toneequal 的「自动」默认参数在真机 RAW 上需要重新校准；这是产品语义任务不是算法任务，与 parity 测试解耦。exposure 默认 0EV（非 dt 0.7EV）已定。
3. **Lab 域模块的 parity 路线**（§Summary#3）：不做 Lab 往返 = tonecurve/shadhi/colisa/levels 四模块 golden 不可比。Lab 往返矩阵常量（D50 Bradford + sRGB-like→XYZ）移植自 dt `colorspaces.c`/lcms 语义，是确定性数学，风险低但工作量要计入（每模块 +0.5 天量级）。
4. **CONTEXT 文件名勘误**（contrast.c/guidedfilter.c 不存在）——plan 引用路径时用勘误后路径（§Summary#1）。
5. **params blob 布局漂移**：XMP blob 的字节布局绑定「darktable 源码 struct」；Lightamer `Params` struct（Codable JSON）与之**无关**——两侧各存各的，测试案例映射表（Lightamer Params ↔ dt blob 字段）是 regenerate.sh manifest 的一部分，防两侧行无文档漂移。
6. **processed_maximum 管线状态**：dt 多个 tone 模块会更新 `pipe->dsc.processed_maximum`（exposure `:545` 等），Lightamer 管线无此状态——省略对单模块输出无影响，但 plan 需记录该 divergence（自动曝光类功能 Phase 8+ 可能需要补管线级 max 跟踪）。
7. **EIGF/迭代滤波的浮点顺序差**：CPU（dt）与 Metal 的归约顺序不同，toneequal 容差必须放宽到 1e-4 级 + 感知判据；不要用 1e-5 硬闸卡死。
8. **L013/L014/L006/L008 全部继续有效**：ParamsCoding.sortedKeys 是 paramsHash 正源；纹理回读必须 fence；管线禁 half（Lab 往返、log2/exp2 全 float32）；encoder endEncoding 先于 commit。
9. **XMP 多实例/multi_priority**：本阶段全部单实例（multi_priority=0）钉参；dt XMP 的 multi_name/masks 字段在配方里保持空值，不留模糊空间。
10. **`--apply-custom-presets 0` 必须带**：否则 dt-cli 会套用用户预设库（本机 ~/Library/Application Support/darktable 状态污染）——regenerate.sh 固化该 flag。

## Open Questions for Planning

1. **重建 darktable-cli 的验收标准**（建议：`darktable-cli --version` 输出新 commit；§6.3 exposure +1EV 配方在合成 EXR 上跑出 0.1306 预期值）。
2. **WB 模块 v50 位次语义**：槽位 3.0（表内冻结）但执行语义是 post-CIRAW 校正层——保持槽位 + 模块头注记 divergence（推荐，零表变更），还是重排到 post-colorin 位置（动冻结表 + sidecar iopOrder）？
3. **Lab 域模块路线**：tonecurve/shadhi/colisa/levels 移植 Lab 往返保 parity（推荐），还是 v1 以 Rec2020 luma 近似 + 放弃这四模块的 dt golden（省 ~2 天但破 LOCKED parity 目标）？
4. **filmicrgb 高光重建子树**：确认默认关闭 → 划出本阶段（推荐）？若必须 v1，是本阶段尾部还是独立 plan？
5. **toneequal details 默认档**：v1 golden 验收先锁 `details=none`（无滤波、1e-5 容差），EIGF/guided 档第二层容差验收？dt 默认 EIGF——默认值与验收顺序解耦。
6. **levels automatic / filmic auto black-white 的全图归约**：MPS histogram vs 自写 reduce 的选型 spike 放 C 段还是 G 段？（可先 manual 模式交付，归约 spike 并行。）
7. **PSO 预热时机**：app 启动后台预热 vs 首次面板展开时预热。
8. **agx 是否进本阶段**：IOP-FILM-03 的具体交付物拍板（推荐 agx，与 sigmoid 共享基建；「hatchless」记录为无对标不实现）。
9. **Lab 往返的管线级共享**（同链多 Lab 模块只转换一次）v1 做否（推荐 v1 不做，记为 Phase 5+ 优化）。

## Sources

### Darktable（本地源码，file:line 均已核；源码树 dc58cf0ba1 2026-08-02）

- `src/iop/exposure.c:44-45`（exposure2white）、`:66-78`（params v7）、`:346-370`（reload_defaults 场景 RAW 0.7EV）、`:479-521`（scale 推导）、`:552-577`（process）、`:614-660`（commit_params bias 补偿）
- `src/iop/temperature.c:48-54`（K/tint 域常量）、`:66-75`（params）、`:287-473`（SPD→XYZ→CAM 全链）、`:1933-1955`（吸管）
- `src/iop/tonecurve.c:46-108`（常量+params）、`:301-398`（process_cl，ProPhoto→Lab、LUT+外推）、`:420-500`（CPU process 三模式）
- `src/iop/shadhi.c:65-80`（params）、`:356-384`（bilateral/gaussian 底）、`:399-490`（overlay 数学）、`:520-570`（CL 腿组装）
- `src/iop/colisa.c:44-48`（params）、`:190-241`（ctable/ltable 构造）
- `src/iop/levels.c:60-67`（params）、`:215-247`（percentile 自动）、`:395-431`（process）
- `src/iop/toneequal.c:132`（fulcrum）、`:140-158`（常量/centers）、`:170-220`（params/data）、`:639-768`（luma 采样/gaussian RBF）、`:771-860`（apply 直通与 LUT 版）、`:866-934`（compute_luminance_mask）、`:967-1080`（toneeq_process 缓存/hash）
- `src/common/luminance_mask.h:45-47,84-126`（估计器 + linear_contrast）
- `src/common/fast_guided_filter.h:161-349`（box mean/EIGF/surface blur）、`src/common/guided_filter.c`（725 行 CL 封装）
- `data/kernels/guided_filter.cl:22-325`（8 kernel 全列）
- `src/iop/filmicrgb.c:98-138`（枚举）、`:168-202`（params）、`:285-311`（data/spline）、`:368-560`（compute_spline v1→v3）、`:1260-1279`（get_scales）、`:2098-2140`（à-trous 重建循环）、`:2228-2420`（reconstruct_highlights_cl）、`:2394-2410`（norm_min/max + 矩阵准备）、`:2450-2560`（process_cl 主序列）、`:2560-2650`（auto 三键 + output_power）
- `data/kernels/filmic.cl:160-228`（norm 家族 + desaturate v1/v2）、`:230-296`（filmic_spline Horner/rational）、`:302-310`（log_tonemapping_v2）、`:470-560`（chroma v4/v5）、`:658-720`（gamut_mapping）、`:795-950`（split/chroma v1-v3）、`:1035-1215`（mask/inpaint/reconstruct/ratios kernels）
- `src/iop/sigmoid.c:37`（MIDDLE_GREY）、`:57-74`（params）、`:249-277`（预设）、`:318-407`（commit_params 推导）、`:409-500`（inset/rotation primaries）
- `data/kernels/sigmoid.cl:103-170`（loglogistic + hue/energy 保持）、`:172-295`（两个 kernel 全文）
- `src/iop/agx.c:105-140`（params）、`data/kernels/agx.cl:216`（kernel_agx）
- `data/kernels/basic.cl:206-239`（whitebalance_1f/4f）、`:240-251`（exposure）、`:1426-1490`（tonecurve）、colisa kernel
- `src/common/exif.cc:418-428`（XMP tag 名）、`:3218-3241,3317`（blob 编解码）、`:3563-3813`（v1/v2 history 解析 + sanity）、`:4245-4347`（xmp_version 分派）
- `src/cli/main.c:446,461,505-545,666-681`（参数解析、write_sidecar=never、XMP attach + RELAXED 释放）
- `src/develop/develop.c:2410-2432`（history SELECT）、`:2562-2572`（validity 判定）、`:2621-2635`（params 采纳条件）、`:1619-1668`（pop_history_items_ext）
- `src/develop/imageop.c:217-223`（params_size=introspection.size）、`src/imageio/imageio_exr.cc:273-275`（EXR 默认 Rec709）、`src/imageio/format/exr.cc:209-232`（export chromaticities）、`src/imageio/imageio.c:1200-1245`（export 模块列表日志）

### 项目内证据（本机实测 2026-09-19）

- dt-cli EXR 直通基线：64×64 ramp round-trip maxdiff 3.6e-7；默认链 `colorin exposure finalscale colorout gamma`（`-d imageio` 日志）
- dt-cli 缺陷实证：XMP marker 值（percentile=100）不入库；直接写库被覆写为默认（fresh.db hex dump 前后对照）
- `.so` introspection 探针（swift dlopen）：exposure `modversion=7, introspection size=28`
- `--icc-type` 枚举含 LIN_REC2020（`--help icc-type`）
- Phase 2 底座：`IOPModule.swift:37-93`（协议）、`MetalContext.swift:42-181`（dispatch/PSO）、`PipeCoordinator.swift:616-760`（D-H1 三件套/undo）、`TilingPlan.swift:23-90`（tiles 几何）、`InspectorState.swift`（stub）、`V50Order.swift`（Phase 3 全部槽位）

### 项目文档

- `.planning/phases/02-.../02-RESEARCH.md` §3.1（displayed-domain 结论）、§5（渲染路径）、§1.3（decodeParamsHash）
- `.planning/phases/02-.../02-0[1-6]-SUMMARY.md`（StableHash/L013、PipeCache 语义、D-C3 档位、ModuleRegistry/双判据 harness、D-H1/HistoryHash、sidecar/预算/L014）
- `.planning/phases/01-.../spike-b-100mp-perf.md`（15.6ms/平面账）
- `LESSONS.md` L006/L008/L009/L013/L014；`AGENTS.md`（.swift+.metal 文件对、golden 硬约定）

---
*Phase 3 Research — 2026-09-19。产物仅本文件；未提交 git。*

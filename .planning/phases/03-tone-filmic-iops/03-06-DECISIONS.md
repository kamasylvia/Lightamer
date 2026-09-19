# Plan 03-06 — checkpoint 决策记录（T0 D-T1 范围定稿 + 源码勘误）

**日期**: 2026-09-19（执行轮；用户确认沿 03-06 checkpoint 预授权——执行协议 Artifacts 注记「user-confirmed in Artifacts」）

## T0 checkpoint:decision — D-T1 filmicrgb 范围（REVERSIBILITY_GATES，costly）

三项范围决定（plan 03-06-T0 原文 + RESEARCH §2.3/§2.5 引用），全部**按推荐采纳并已获用户确认**：

1. **colorscience 只落 V5**（`filmic_chroma_v5`，dt 默认路径 `DT_FILMIC_COLORSCIENCE_V5=4`）。
   V1–V4 分支（`filmic.cl:721-1032` split/chroma v1–v4 全族）是历史包袱，不移植；
   params 枚举保留位（`FilmicRGBColorscience` 全五值 Codable 侧写，非 V5 值在 commit 时
   走 V5 语义并记录）。**已采纳**。
2. **高光重建子树划出本阶段**（F5 à-trous wavelet，`filmicrgb.c:2098-2140` +
   `filmic.cl:1035-1215`）：只落 `filmic_mask_clipped_pixels` mask kernel + 参数位
   （`enableHighlightReconstruction` 默认 FALSE，parity 不需要重建）；wavelet 重建 +
   HQ 循环挂 TODO（Phase 8 HDR 或 v1 后期；若必须 v1 工作量 +60%，RESEARCH §2.5）。
   **已采纳**。
3. **preserve_color norm 家族全实现**（MAX_RGB / LUMINANCE / POWER_NORM（默认）/
   EUCLIDEAN_V1 / EUCLIDEAN_V2 / NONE——`filmic.cl:169-196` + `rgb_norms.h` 一行函数）；
   V5 固定 MAX_RGB（`filmic_chroma_v5` 硬编码 `DT_FILMIC_METHOD_MAX_RGB`）。**已采纳**。

## 源码核对勘误（对 plan 文本）

- **plan T3 勘误——V5 无 ratio sanitize**：plan 写「ratios = i/norm（负值 sanitize 减
  min_ratios）」，但 `filmic_chroma_v5`（filmic.cl:651-719）与 CPU `norm_tone_mapping_v4`
  （filmicrgb.c:1806-1845）均**无** min_ratios sanitize——那是 v1 路径
  （`filmic_chroma_v1`，filmic.cl:874-881）独有的。V5 逐源码直译（无 sanitize），
  plan 文本系 v1/v5 混写。
- **dt 的 Y 1931→2006 系数**：`CIE_Y_1931_to_CIE_Y_2006(x) = 1.05785528·x`（含 CAT16
  D50→D65 适配），非纯 CIE 换算——逐常量搬移。
- **gamut 段 saturation 恒 0**：V5 的 `gamut_mapping(..., saturation=0.f, ...)`
  （filmic.cl:718）——`saturation` 参数只进 max_rgb/naive 混合步，不进 gamut 步。
- **auto_hardness 语义**：dt 在 GUI 回调（gui_changed :4667-4668）+ reload_defaults 中
  改写 `output_power`；commit 本身不复算。Lightamer 在 commit 时当 `autoHardness==true`
  直译 `_compute_output_power`（不变式等价，GUI 无从属）——divergence 记录在模块头。
- **LUMINANCE norm 的实现域**：dt `get_pixel_norm(LUMINANCE)` 走工作 profile 矩阵亮度
  （`dt_ioppr_get_rgb_matrix_luminance`）。Lightamer 工作域恒 linear Rec2020 →
  编译期 Rec2020 亮度系数（`YrgGamut.rec2020Luminance`）。

## agx（T6）记录

- **「hatchless」无对标不实现**（REQUIREMENTS 层 IOP-FILM-03 注记；模块头 + manifest 落账）。
- agx primaries 路径的 `rendering_to_xyz` 亮度矩阵：dt 用 base ICC profile 的 D50 media
  white 构建；Lightamer 用 Rec2020 primaries + D65 white 的 SigmoidProfile builder
  （同 sigmoid_smooth 的 recorded deviation——默认 look 路径 look_tuned=false 不经过该矩阵，
  非默认 look 案例钉双实现不钉 dt）。

## PERF-5（T7）口径

- 正式门 = **Release 配置测量**（`xcodebuild test -configuration Release
  -only-testing:LightamerTests/PreviewChainPerfTests`）+ os.signpost 汇总 + 断言
  <16.6ms；Debug 构建保留 120ms 病理回归界（03-05 预验口径延续，Debug -Onone 的
  63.4ms 基线数据保留在 `.work/03/perf-record.md`）。
- 优化杠杆落地：PSO 启动预热（PipeCoordinator.load 后台 Task）+ 面板/链路沿用
  既有 dispatch；「dispatch 批合并」评估为 MetalContext 层改造（跨模块 encoder 合并），
  本轮以 Release + 预热达标后不动管线核心（风险控制），记录为后续优化位。

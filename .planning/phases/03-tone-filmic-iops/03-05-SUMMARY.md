# Plan 03-05 Summary — toneequal（CorrectionLUT + EIGF kernel 群 + TilingPlan FULL 首战）

**Status:** Complete（2026-09-19）
**验收:** 全 suite **244 tests / 0 failures / 3 documented skips**（连续两次全量稳定）；golden 两档全绿——`details=none` 档 <1e-5（ParityGate 双闸）、EIGF 档（dt 默认）<1e-4 + ΔE76 p99 <1.0；分块正确性（强制分块 vs 整幅 <1e-5）+ 100MP FULL 内存门（Δfootprint <3GB）双过。

## 交付物

- **T1 `ToneEqual/CorrectionLUT`**：9 带 EV → exp2 线性 → 9×8 RBF 设计矩阵 → **float32 逐式直译的正规方程 + Cholesky 最小二乘**（choleski.h :107-358 verbatim——dt 发布的 weights 出自 float 运算，Double 推导会在 9×8 条件数下漂 ~3e-4，破坏 none 档 1e-5 门）→ **80001 点 LUT**（8 EV × 10k/EV + 1；plan 文本「10001」为勘误）clamp [0.25,4]。UI 与 kernel 同源：`uiCurveSamples` / `channelGainsEV`（dt compute_lut_correction / compute_channels_factors）。
- **T2 `ToneEqualKernels.metal` luma_estimate**：**7 种估计器**（plan 文本「9 估计器」勘误——dt 枚举 DT_TONEEQ_LAST=7；9 指 user bands）+ `linear_contrast`（fulcrum exp2(−4)、MIN_FLOAT floor）。method 用 **uniform 分支**（PSO 常量特化会在 256 项 LRU 预算下乘爆维度，可预测 1-cycle 分支双赢——决策记录在案）。
- **T3 EIGF/guided kernel 群**：bilinear_1c（dt corner convention）/ quantize / pack4 (g, g², m, g·m) / box_mean_x/y（有限窗滑窗）/ guided_ab / blend（EIGF no-mask + EIGF mask + guided a/b 三模式，linear/geomean，全尺寸或内联双线性上采样）。**EIGF 的模糊是 Gaussian 非 box**（plan 勘误：`guided_filter.cl` 是彩色 guidedfilter iop 的 kernel；toneequal 的 dt 真实路径 = `eigf.h` `fast_eigf_surface_blur`）——复用 03-04 的 `GaussianBlur`，常量 bounds (2⁻¹⁶, FLT_MAX) 与 dt 数据 min/max clamp 点位等价（dt 的 CLAMPF 施加在输入样本上且界=数据 min/max，有限数据永不触发，论证在 03-05-DECISIONS.md）。blend 内联 av 上采样省一个全幅平面（D-C1 分块账）。
- **T4 apply + 组装**：`toneeq_apply`（LUT 版，**4 通道全乘**——dt `for_each_channel` quirk，逐字跟随保 golden）；三段图按 dt `compute_luminance_mask` 组装（NONE 直通 / EIGF 全分辨率逐迭代 / guided ds 平面逐迭代 + 末轮 ab 上采样）；radius 按 dt `modify_roi_in`（blending% × **piece 全图几何** × scale），`PixelPipe.run` 新 stamp `piece.dscIn`（dt `piece->iwidth` 同构）。v50 槽位 24.0 注册。
- **T5 golden 两档**：`gen_fixtures.py` 增 toneequal 节——**float64 参考逐式复刻 CPU 源码**，choleski 在 Python 端 **float32 逐 op 复刻**（与 Swift 端权重一致到 ~1e-7，纹波包络数字两侧相同：min 0.9907 / max 1.0177 / 单带 −4EV 1.7459）；5 钉参 case（default / shadow_lift / highlight_compress / contrast_boost / none_ramp）× 6 fixture = 30 参考图；v2 blob `<15f3i` 72B **采纳实证**（`params v. 2: version ok params ok` + DB op_params hex 核对）；平场 PFM probes（EIGF 平场不动点：var→0 ⇒ a=0,b=avg ⇒ 恒等）。`ToneEqualParityTests` 两档门 + 轨 B。
- **T6 TilingPlan FULL 首战**：`IOPModule.tileHalo / tileWorkingSetBytesPerPixel` seam（默认 0，存量模块零破坏）+ `ModuleBoxing` erased 转发 + `PixelPipe.executeTiled`（上游整图一次渲染 → TilingPlan 网格（bytesPerPixel=模块工作集，overlap=halo）→ tile 外扩 halo 的 readRect 上整幅语义执行 → blit 裁回；缓存键不变——tile 驱动在单次模块执行内部）。toneequal 上报 halo = **4·radius + 65**：EIGF 的 gaussian 是递归 IIR，边界瞬态 exp(−1.695·d/σ_ds)，对齐整幅 <1e-6 需 ≈14.5σ_ds 跑道（plan 的 `max(radius,1)+halo` 由此推导落地，决策记录更新）。tile 预算 512MB/模块，可经 `RenderPipeline.process(maxTileWorkingBytes:)` 注入。
- **T7 面板 + 预验**：`ToneEqualPanelView`（校正曲线 Canvas——与 kernel LUT 同源插值 + 9 带滑块 ±2EV + details/method Picker + blending/iterations/feathering/quantization/boost 滑块；String Catalog zh/en 33 keys）；`InspectorState` 注册 Provider；toneequal 进 editingDefaultInstances（全 0 带默认）；`PanelWiringTests` +2（panel dispatch + seed 载入拖动恰 1 commit）。

## 中间探针抓出的缺陷（本 plan 排障记录）

1. **参考端 contrast 双重 exp2**（T5）：`te_luma_plane` 对已线性的 slope 再做 2^，contrast=1 变 2，暗部 luma 全部砸进 MIN_FLOAT floor——症状是**仅 ramp_8ev 的 EIGF 档失败**（其余 5 fixture 全绿：平场 luma 与 contrast→(v−f)·2+f 对大 v 影响小）。定位法：Python 端逐像素复算参考链（luma→eigf→lut）与落盘 golden 比对。教训：**参考生成与 parity 失败都要先怀疑参考端，逐像素复算是最快定位**。
2. **float64 最小二乘与 dt float Cholesky 的 3e-4 漂移**（T1/T5 设计期发现）：9×8 正规方程条件数放大 1ulp 级系数差；Python 参考必须 float32 逐 op 复刻（`_f32` 每次运算舍入），否则 none 档 1e-5 门被参考自身的不确定度击穿。
3. **全 0 参数 ≠ 恒等 LUT**：RBF 最小二乘拟合常数 1 留 ~1.8e-2 纹波（dt 同行为）；恒等验收改由「精确 1.0 LUT 注入 apply → 输出逐位不变」钉住（`testApplyIdentityWithUnitLUT`），参数级纹波由包络断言钉住。

## PERF-5 预验数据（03-06 正式门输入）

- **PREVIEW 全链单帧（10 模块含 toneequal，2048×1536，每帧全链 miss）：warm median 63.4ms（Debug -Onone，M4）**——**超 16.6ms 预算**。按计划「超限先记录后优化，不阻塞签收但需注记」处置：①Debug 构建未优化；②10 模块 × 每 encoder 独立 commit 的 dispatch 开销与元素级带宽（~15ms@此尺寸）叠加。优化杠杆（03-06 工作项）：Release 构建、PSO 预热、相邻模块 dispatch 批合并、模块内多 pass 同 encoder。测试保留 120ms 病理回归界 + 完整数据打印。
- **FULL on-demand 不占 60fps 预算**（plan 注记落实）：100MP FULL toneequal Δfootprint 实测 <3GB（TilingOverlapTests 门）。

## checkpoint 产物（对 plan）

- D-T3 三问定稿 + 全部源码核对勘误（7 估计器 / 80001 LUT / Gaussian 非 box / feathering 反转 / 9→8 最小二乘 / 4 通道 apply）落 `03-05-DECISIONS.md`。
- halo 公式 dev（4r+65 vs plan 的 max(r,1)+1）：IIR 跑道推导，决策文件含反推式。
- golden 参考路线（L017 延续）：float64 合成 + float32-复刻 choleski；dt 侧证据 = XMP 采纳 + 平场 probes。

## Verification 对账

| VALIDATION 行 | 结果 |
|---|---|
| IOP-TONE-07（toneequal unit+golden） | ✅ `ToneEqualLUTTests` 7/7 + `ToneEqualKernelTests` 7/7 + `ToneEqualModuleTests` 4/4 + `ToneEqualParityTests` 2/2（两档门 + 轨 B） |
| METAL-6/7 + D-C1（FULL 分块） | ✅ `TilingOverlapTests` 2/2（分块一致 <1e-5 + 100MP Δfootprint <3GB） |
| PERF-5 预验 | ⚠️ 数据记录（Debug warm median 63.4ms > 16.6ms；正式门 03-06-T7，优化杠杆已列） |
| 轨 B 回归（ColorSync 双判据） | ✅ `ToneEqualParityTests.testTrackBNeutralityWithToneEqualInserted` |

**测试计数**：220（03-04 末）→ **244**（+LUT 7、kernel 7、module 4、parity 2、tiling 2、perf 1、wiring 1；3 documented skips 不变）。

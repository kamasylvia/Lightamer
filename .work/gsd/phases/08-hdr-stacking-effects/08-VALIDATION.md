---
phase: 8
slug: hdr-stacking-effects
status: validated
nyquist_compliant: true
created: 2026-09-27
validated: 2026-09-28
---

# Phase 8 VALIDATION — HDR/Stacking & Effects iops

> **C 档第 3 停执行记录（2026-09-28）**：本文件 + REQUIREMENTS 翻账（IOP-HDR-01..05 /
> IOP-FX-01..05 → Delivered ×10）产出后，按 `.work/config.toml [gsd]` 暂停机制与 AGENTS.md
> C 档门控**停等用户过目**——翻账 commit 之后、后续 phase 推进之前（晨审可推翻；夜间授权
> 先例 D-07-3-T5-1/D-09-05-T1-1 可循但用户随时可推翻）。GOAL-STATE 续接点由 orchestrator
> 更新，本 plan 只交付材料。

## SC 逐条证据指针（ROADMAP §Phase 8 SC#1-4）

### SC#1 — HDR merge 产出 aligned、de-ghosted 的 32-bit float HDR（linear Rec2020），可继续正常编辑链 → **PASS**

| 证据 | 位置 |
|---|---|
| MTB 对齐 (17,-11)/(-9,23) 精确命中（含 4×/0.25× 曝光差；8 级金字塔/256-bin 中位/±1 粗到细/收缩窗） | `MTBAlignTests` ×14（08-1 T2，验收①核真） |
| EXIF §2.4 预检矩阵 + §1.2 交集带比例自检 + **ΔEV 亮度倍数语义（08-5 `efccca9` 符号修复 + E2E 数值断言）** | `MTBAlignTests` / `ProvenanceV4Tests.testE2EEXIFBracketMergesToKnownLuminance`（EV=[0,−2,+1]、ratioVerified 全 true、产物≈L ±0.5%） |
| Robertson 合并（双门高斯权 σ=0.2 / HOLE 黑输出+weight-map / ghost 残差拒绝 k=3 + 3×3 膨胀 PNG → `RasterMaskRef` + Ghost Suppression 层；deGhost:false 零开销） | `HDRMergeMathTests` ×15（08-1 T3/T4，验收③④核真） |
| 行带流式（R3 红线：28/41 B/px 累积面契约 + **显式 N 对照表**） | `HDRMergeMathTests.testAccumulatorFootprintIndependentOfSourceCount`（08-5 `cd0b5b9`） |
| 产物 = 会话根 `<stem>_hdr.tif`（ExportNamer 防撞）+ **E2E 全链可编辑**（grid 三行 → RAWDecoder 保深 → history/sidecar round-trip 零漂移） | `ProvenanceV4Tests.testE2EProductGridDecodeEditSidecar`（08-1 T5） |
| sidecar v4 provenance（UInt64String wire 断言 / 源漂移一字节标脏 / 重放同参等价） | `ProvenanceV4Tests` ×9 |

### SC#2 — focus stacking 与 average/median stacking 产出干净合并结果、对齐正确 → **PASS**

| 证据 | 位置 |
|---|---|
| SML 度量 kernel（modified Laplacian 3×3 ΣML²，CPU mirror 逐位同构，L014 三步证明形态 drain） | `FocusStackTests` ×13（08-3 T1） |
| 5 级 quality-weighted 金字塔融合（清晰区归属 MAE 0.0016，P5 量级；DC=1 线性伴随 D-08-3-T2-2）+ NCC 漂移警告不阻断 | `FocusStackTests`（08-3 T2） |
| 三模式聚合（解析 golden ×3 + 星野 N=8 轨迹剔除残差 <0.02 + bandStackBytes 286MB 精确锁 + N=3 退化 √(N−1) 口径） | `StackAggregateTests` ×11（08-3 T3） |
| 四 kind E2E 真生产腿（`_fstack`/`_stack_avg|_med|_sig` + 位移轨 (3,-2) MTB 精确命中 + precheckStack 判据矩阵） | `StackAggregateTests`（08-3 T4） |

### SC#3 — HDR/EDR 显示输出真实高动态范围（wantsExtendedDynamicRangeContent；headroom >1.0 不是另一种色彩空间）→ **PASS**

| 证据 | 位置 |
|---|---|
| PSO 三臂（legacy/displayReadySDR/edr16F）唯一源 + `applyEDRDisplaySurface` 三件（16F/EDR flag/extendedLinearSRGB）+ D-COL2 跳过 | `EDRViewportTests` ×5（08-4 T1） |
| 终端 SDR 钳制旁路（run 级 `edrDisplayLeg` 默认 false；gamma 除名双位一致；export/QL/culling/thumbnail 结构不消费） | `EDRDisplayLegTests` ×7（08-4 T2/T3） |
| SDR 不变断言三件套（on==剥 gamma 链逐字节 / off==默认逐字节 / off→on→off 全命中零 stale / 三不进独立用例） | 同上（08-4 T4，验收④核真） |
| headroom 合法域 ≥1.0/nil=1.0 + 跨屏双通知幂等 + 1.0 橙警 | `EDRHeadroomMonitorTests` ×2（08-4 T3） |
| **Manual-Only**：XDR 目检 / 外接 HDR 屏 / headroom>1.0 观感（本环境无 XDR 屏；P4 API 面实测已证） | 08-4 SUMMARY Manual-Only 表 → 本文件下表 |

### SC#4 — vignette/grain/bloom/dehaze/text overlay 渲染正确且对参考；watermark iop（order 77）与 yiyin 终端水印区分 → **PASS**

| 证据 | 位置 |
|---|---|
| vignette 68.0（dt 参数面 9 参数 verbatim + OpenCL 形 cosine 恒用 + 1e-6 全图 parity） | `VignetteTests`（08-2 T1） |
| grain 65.0（simplex 逐值 verbatim + StableHash 种子 + 确定性双断言逐位） | `GrainTests`（08-2 T2） |
| bloom 61.0（三段 verbatim + 线性域映射 + HDR>1.0 零特判） | `BloomTests`（08-2 T3） |
| **dehaze 14.0**（四 kernel 直译 + 窗口式 + A0 网格降采样哈希复用 + **box 两遍近似（planner 裁决冻结）** + 合成雾反演 golden 三场景 + float64 parity 6.6e-5 + CLAHE 零混入） | `DehazeTests` ×6（08-5 T1） |
| **text overlay 66.7**（新非 dt 行 add-only + FULL-BLOCK 字形分析断言 + StableHash 缓存 + 层蒙版局部化 + **yiyin 77.0 零改动 + 同链共存**） | `TextOverlayTests` ×6 + `V50OrderTests` ×15（08-5 T2） |
| **order-77 冲突裁决注记**（编写期冲突按需求原文裁——77.0 归 yiyin 终局水印，text overlay 走 66.7 新槽；晨审注意项 D-08-CONTEXT-9 已过目在案） | `V50Order.swift` 行注 + `testYiyinCoexistenceAndZeroChangeBoundary` |

## Per-Task Map

| Plan | 任务 | 关键 commit | 需求 |
|---|---|---|---|
| 08-1 | T1-T8（service/MTB/Robertson/ghost/落位/provenance/矩阵基座） | `7825089`/`15da1e5`/`8abfc07`/`7f7e92b`/`1dc1556`/`e4ce37b` | IOP-HDR-01/04 |
| 08-2 | T1-T5（vignette/grain/bloom + wiring） | `c44a548`/`366cdf4`/`49db32c`/`8842a1c` | IOP-FX-01/02/03 |
| 08-3 | T1-T6（SML/融合/聚合/分派/perf） | `be67d5b`/`5e3e845`/`387fde3`/`9e389e2`/`aa1b01b` | IOP-HDR-02/03 |
| 08-4 | T1-T5（PSO/旁路/headroom/断言） | `761b721`/`75b9c10`/`70b647e`/`ad39d0f`/`f40d790` | IOP-HDR-05 |
| 08-5 | T0（EXIF P1）/T1（dehaze）/T2（overlay）/T3（LUT+矩阵+预算）/T4（收口）/T5（签核） | `efccca9`/`4de6264`/`eec0173`/`ac4f709`/`cd0b5b9` | IOP-FX-04/05 + 12-5 移交④ |

## 缺陷处置表

| # | 缺陷 | 处置 | 状态 |
|---|---|---|---|
| 1 | **EXIF ΔEV 快门项符号反向**（08-1 验收回注 P1——research §2.4 笔误下传；真实 bracket 合并系统性偏差 + 自检恒 false） | `efccca9`：实现/测试/研究三面同批修复 + E2E 数值回归钉 | ✅ 闭环 |
| 2 | box mean 对 2D kernel 误走 1D dispatch（08-5 T1 执行期发现，parity 44× 假差） | stage-by-stage probe 定位 → `dispatchBox2D` 分型（parity 6.6e-5） | ✅ 闭环 |
| 3 | EDR draw() 无条件 SDR clearColor 顶替 16F 线性解码值（08-4 验收修复） | `f40d790`（08-4 验收批） | ✅ 闭环 |
| 4 | zero-stuff expand DC 增益 4（08-3 T2 执行期修复） | D-08-3-T2-2 线性 2× 伴随（MAE 0.84→0.0016） | ✅ 闭环 |
| 5 | CI input 腿 RGBAh sub-1e-4 下溢（D-08-1-13①）+ torture 黑平面分歧（②） | 08-5 收口：峰值重归一 4.0 绕开（真实产物域 0.001–100）；subnormal 面 → L006 HDR 附件，非阻塞 | ✅ 关闭（L006 附件登记） |
| 6 | 12-5 移交④/遗留#4（LUT HDR 域精度结论） | 08-5 判定写死：D7 rgba32Float 保持（混合符号面破门坐实） | ✅ 闭环 |

## Manual-Only 汇总（verify-work 走查清单）

| # | 项 | 需要 | 来源 |
|---|---|---|---|
| 1 | 真 RAW bracket 灰卡两点标定（research §1.2 R2 单次确认） | 真三脚架 bracket 样张 | 08-1 |
| 2 | HDR/focus/stack menu·dialog·toast 真机观感（含 N=3 弱统计文案） | 解锁控制台 | 08-1/08-3 |
| 3 | bloom/vignette/grain 默认手感观感轮（R4） | 真图走查 | 08-2 |
| 4 | pristine 图 grain 跨启动重掷 wart | 用户观感裁决 | 08-2 |
| 5 | 100MP N=8 真实 RAW 全幅秒表 | 内存/时长超 CI 面 | 08-3 |
| 6 | XDR 屏 EDR 目检 | XDR 显示器 | 08-4 |
| 7 | 外接 HDR 屏双实测（COLOR-4） | 外接 HDR | 08-4 |
| 8 | headroom>1.0 「not a different color space」观感（SC#3） | HDR 屏 | 08-4 |
| 9 | dehaze box 近似 vs dt guided filter 视觉差对比（v1 接受；guided 全移植 = Reversibility 缝） | 真雾图对照 | 08-5 |
| 10 | text overlay 真机排版观感（字体/字号/位置手感） | 真图走查 | 08-5 |

## 终轮回归

- **全 Phase 终轮 = 1768/11skip/0fail（729.6s，`/tmp/la-085-final-suite.log`）**——基线 1636
  （13-3 后）→ 08 车道净增 +132；在案 flake（LayerE2ERoundTrip/ToneEqualPerf/GoldenColor）
  终轮零现身。perf 对账：`.work/gsd/phases/08-hdr-stacking-effects/perf.md` 08-5 收口节。

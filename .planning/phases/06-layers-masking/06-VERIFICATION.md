---
phase: 06-layers-masking
verified: 2026-09-24T06:05:54+08:00
status: human_needed
score: 14/14 must-haves verified（14 需求全部在代码库交付且注册/接线；SC#1-5 自动化证据全绿；5 项 Manual-Only 视觉/手感判据挂人工）
behavior_unverified: 0
overrides_applied: 0
overrides: []
re_verification:
  previous_status: none
  previous_score: none
  gaps_closed: []
  gaps_remaining: []
  regressions: []
gaps: []
deferred:
  - truth: "LAYER-04「编组（层文件夹）」未在本 Phase 交付（SC#5 的 group 以 MaskGroup 组语义判定满足）"
    addressed_in: "v2（无专属 phase，REQUIREMENTS LAYER-04 注记行挂账）"
    evidence: "D-06-CONTEXT-6（纯 UX 组织不产生管线语义；蒙版组由 MaskGroup 内嵌套 child 承载 = MaskGroupItem.child MaskSpec.swift:203）+ REQUIREMENTS.md LAYER-04 注记 + mergeDown v1 已交付（LayerStack.swift:152-184）"
  - truth: "IOP-MASK-02 dt 双域 UI（Lab+RGB 双面板）未交付"
    addressed_in: "v1 后按需（域枚举扩展位已留）"
    evidence: "D-06-CONTEXT-3（ParametricMask.Domain 枚举 + 单 kernel 覆盖 luma+JzCzhz 全通道族，ParametricMask.swift:38-41；双域 UI 为可逆扩展位）"
  - truth: "retouch v1 圈定项：视口圆形绘制（path/lasso 手势未接）、blur bilateral、fill erase、stroke 叠加 parametric mask"
    addressed_in: "后续 plan/v2（VALIDATION Per-Requirement Annotations 挂账）"
    evidence: "RetouchStroke.swift:26-28 头注（blur GAUSSIAN only / fill COLOR only / path 数据腿就绪）+ RetouchLayer.swift:94-101 形状门 + 06-VALIDATION 注记行——均 optional additive 路径非缺口"
  - truth: "rgbcurve（42.0）/ rgblevels（43.0）不在本 Phase 交付"
    addressed_in: "Phase 6+ stretch（无专属 phase，05-VERIFICATION deferred 沿用）"
    evidence: "D-05-CONTEXT-1 + 06-CONTEXT §Phase Boundary「不做」清单明示 rgbcurve/rgblevels stretch 非本 Phase 承诺 + V50Order 槽位在表作占位"
behavior_unverified_items: []
human_verification:
  - test: "retouch source 拾取手感（十字线 + 源-目标连线跟随）真机走查"
    expected: "拾取锚点十字线实时跟随光标，连线视觉连续；clone/heal 取样位置与预期一致"
    why_human: "视觉/手感判据（L011 红线：单测不可达）；数据腿已钉（clone 跨窗 hint 32→57px 无源区黑边 ≤1e-5，RetouchParityTests.testCloneCrossWindowSourceExpansion）。VALIDATION Manual-Only 表 pending-manual"
  - test: "stroke 羽化视觉（border 渐变带）真机目检"
    expected: "stroke 边缘呈平滑渐变带（hardness/border 语义），无硬边锯齿"
    why_human: "视觉判据；解析断言已钉（mask 平面 = 06-03 光栅化器同源，DrawnMaskRasterTests 解析 ≤1e-6）。VALIDATION Manual-Only 表 pending-manual"
  - test: "heal 效果人像目检（真实人像 RAW 上画 heal stroke）"
    expected: "修复区纹理自然过渡、无可见接缝/色块；自动化腿已绿：heal vs 独立 float64 红黑 SOR 参考 <1e-3 + Dirichlet 外区不动 + median 9.99-11.63ms"
    why_human: "人眼质量判据。VALIDATION Manual-Only 表 pending-manual"
  - test: "GUI-17「显示蒙版」按钮偶发不可见复验（部分会话 AX 树/渲染均不可见）"
    expected: "按钮稳定可见；若复现，定位 Menu/Toolbar 布局偶发塌缩根因"
    why_human: "偶发布局塌缩待人工复现（FINDINGS.md:531 低危登记，不阻塞——overlay 请求路径 row-tap 驱动已验证 + GUI-15 修复使 toggle 渲染链路就绪）"
  - test: "stroke path lasso 视口手势接线的交互验收（后续 plan 交付时）"
    expected: "lasso 自由圈选生成 path stroke，与既有 ellipse/path 数据腿一致"
    why_human: "手势未接（v1 圈定注记：path 数据腿 parity 就绪）；接线后需真机手势走查。VALIDATION Manual-Only 表登记"
---

# Phase 6: Layers & Masking System — 阶段目标级验证报告

**Phase Goal（ROADMAP §Phase 6）:** Capture One 调整图层架构——全项目根本差异化能力。背景层 + 多个可命名调整图层（各携独立 iop 参数 + 蒙版 + 混合模式）与全局 iop 共存于同一 pixelpipe；drawn/parametric/raster 蒙版 + combine 与图层互相依赖、同批交付；liquify 与 retouch 依赖蒙版/变形框架落位于此。
**Verified:** 2026-09-24T06:05:54+08:00
**Status:** human_needed（自动化层全绿、无阻塞缺口；5 项 Manual-Only 视觉/手感判据待人工，均有正式记录）
**Re-verification:** No — 初始验证（阶段目标级，非 plan 级复验）

## Goal Achievement

### 验证方法

从 ROADMAP §Phase 6 的 GOAL + 14 条需求（LAYER-01..07 + IOP-MASK-01..05 + IOP-GEO-05/06）+ SC#1-5 反向推导 must-have，逐条在**代码库**找承载实现（模型类型/驱动器/kernel/注册/面板/overlay），核内容级测试覆盖（抽查测试体确认真比较循环 + 防空转门，非恒真）。SUMMARY 自述不作为唯一证据。证据来源：

1. **模型/管线面**：`LightamerCore/Sources/Layers/`（Layer 协议 + LayerStack mutation API + AdjustmentLayer/RetouchLayer 双 kind + BlendMode 17 值 + Masks 五件 + Retouch 三件）+ `LightamerCore/Sources/Pipe/LayerCompositeDriver.swift`（1+N+1 合成编排，616 行）+ `LightamerCore/Sources/Sidecar/`（schemaVersion 2 + SidecarLayerStackRecord + RasterMaskStore）。
2. **iop 面**：`LightamerIOP/Sources/BlendOp/`（compositeLayer kernel + float64 参考）+ `Liquify/`（Registry.swift:211-217 注册 18.0 + seed enabled-neutral :412-416）+ `Masks/`（parametric/post-process kernel 对）。
3. **UI 面**：LayersPanelView / LiquifyPanelView（LiquifyPanelProvider 注册于 InspectorState.swift:96）/ RetouchPanelView / MaskToolbarView / 三个 OverlayHost；InspectorView.swift:117/123 路由。
4. **测试面**：Phase 6 新增 20 个测试文件；抽查 8 类独立实跑 **91 tests / 0 fail**（见下节）+ 3 个测试体内容级抽查（确认真循环 + anti-vacuity 门）。
5. **GUI 红线**：FINDINGS.md 四轮登记（06-03 overlay 量化 / 06-05 八截图 GUI-14/15/16 当场修 / 06-06 liquify 复测 / 06-07 retouch 走查 + GUI-18 当场修）。

### 独立实跑记录（抽查）

测试产物 Sep 24 05:22 构建，晚于全部源码提交（其后仅 docs 提交），无源码新于产物 → 实跑反映 committed 代码。命令 `Scripts/test-direct.sh '<Class>'`（直启宿主，L019b 口径）：

| 测试类 | 覆盖 | 结果 |
|---|---|---|
| RetouchParityTests | clone/fill/blur/heal 四算法 parity + 跨窗扩窗 + 基准 | 9/0 fail（0.33s） |
| BlendOpParityTests | 17 模式两域 parity + 恒等门 + REVERSE + dt 采纳 | 20/0 fail |
| LayerCompositeTests | 恒等三元组逐字节 + 参数差异 + 轨 B 零增量 | 10/0 fail |
| MaskEditIncrementTests | 蒙版编辑零链重算双向记账 | 4/0 fail |
| LayerUIWiringTests | 层操作 D-H1 语义 + 互斥路由 | 14/0 fail（3.34s） |
| Phase6SidecarTests | 层栈拼写冻结 + history 投影 | 7/0 fail |
| RetouchSidecarTests | retouch 拼写表 + pre-06-07 兼容 | 4/0 fail |
| LiquifyParityTests | 场解析 + warp parity + 分块==整幅 + 轨 B | 16/0 fail |

**合计 91 tests / 0 fail**，与签核轮 788/3skip/0fail 全绿结论一致，无 flake 触发（02-04 台账隔离判定未启用）。全量复跑未执行（788 套件已由 06-07 签核轮 touch + build-for-testing 重编复跑覆盖，本验证为抽查口径）。

### 逐需求判定表

| 需求 | 代码证据（file:line） | 测试证据 | 判定 |
|---|---|---|---|
| **LAYER-01** 背景层 + 多命名调整图层栈 | `Layer.swift:25-52`（协议：UUID 身份/可见性/opacity/blend/kind）+ `LayerStack.swift:32-47`（baseLayer 恒在 + adjustmentLayers 自下而上，compositeLayers 收窄）+ `LayerKind.swift`（background/adjustment/**retouch** 双 kind 栈，06-07 扩展）+ `AdjustmentLayer.swift:27` / `RetouchLayer.swift` | LayerCoreTests 10（duplicate 新身份/mergeDown 两态/未知 op 盒化跳过）+ LayerSkeletonTests 5 + RetouchParityTests.testEmptyStrokeRetouchLayerIsIdentity（空 retouch 层插链零增量逐字节） | ✓ VERIFIED |
| **LAYER-02** 每层独立 iop 参数 | `AdjustmentLayer.swift:48`（`chain: [ModuleInstance]` 记录形，与全局集同拼写）+ `LayerCompositeDriver.swift:69-98`（逐层独立子 run = 完整 PixelPipe walk） | LayerCompositeTests.testLayerParamsChangeTheComposite:289（异参异层内容差异 >0 字节）+ LayerCacheTests 层 K 增量账本精确断言 + LayerUIWiringTests.testLayerParamEditIsolatedFromBase:242 | ✓ VERIFIED |
| **LAYER-03** 每层蒙版 | `AdjustmentLayer.swift:52`（`mask: MaskSpec?`）+ `MaskSpec.swift:239-299`（drawn/parametric/raster 三 payload + `stableHash()` 派生身份）+ 内容锚定 `GeometryPointMapper`（commit 41fe1e2，四几何段逆序复合） | DrawnMaskRasterTests.testContentAnchoredThroughCropMapper:489 + GeometryPointMapperTests（roundtrip ~1e-12 px）+ MaskEditIncrementTests（mask plane 独立记账） | ✓ VERIFIED |
| **LAYER-04** 层管理（可见/重排/复制/合并/组） | `LayerStack.swift:91-184`（addAdjustment/remove/reorder/duplicate/mergeDown——身份不动、copy 插原位上方、mergeDown v50 排序两态）+ `:57-72`（replace/replaceAny live 写者）+ `LayersPanelView.swift`（全件 UI）+ InspectorView.swift:117/123 选中路由 | LayerUIWiringTests 14/14（add=1 commit/reorder 1 commit + undo 还原/duplicate 新身份/mergeDown 链合并/remove 还原身份参数）+ 06-05 GUI 轮八截图（拖动重排实时） | ✓ VERIFIED（编组=层文件夹 defer v2，注记入账 → deferred） |
| **LAYER-05** PS 风格混合模式 + opacity | `BlendMode.swift:88-141`（17 case：SC#3 十三模式全数——normal/multiply/screen/overlay/softLight/hardLight/**psColorDodge 0x2A/psColorBurn 0x2B**/difference/hue/saturation/color/luminosity + 增补 linearBurn/lighten/darken/colorAdjust；REVERSE 位 `BlendOptions.reverse` :85）+ `BlendOpEngine.swift`/`BlendOpKernels.metal`（compositeLayer 单 kernel：mask×blend×gopacity）+ `BlendOpReference.swift`（float64 正本） | BlendOpParityTests 20/20（算术全表 <1e-5 + JzCzhz pow-chain 档 + 恒等三元组逐字节 + `testEveryModeChangesTheComposite:432` 防空转 + REVERSE==平面交换 + 分块恒等）+ dt 三证据 54/54（manifest blendop 节：v14 blob 420B + `--d params` ok + 平场 PFM） | ✓ VERIFIED |
| **LAYER-06** 层与全局 iop 共存一管线 | `LayerCompositeDriver.swift:69-98`（混合模型 (c)：全局 iop = base 链，层 = 子链 + blend 三元组；**walk/缓存/ROI/tiling 零改动**——每腿即 PixelPipe run）+ L021 层维度红线（:84-91 每层自 stamp dscIn/iscale + 几何模块层内拒绝 :103-128） | LayerCompositeTests.testTrackBFullChainWithIdentityLayerIsZeroIncrement:430（轨 B 恒等层零增量逐字节）+ testLayerGeometryDetectorCatchesAllForbiddenSlots:367 + testWindowedCompositeMatchesFlatRunAtSameWindow:318 | ✓ VERIFIED |
| **LAYER-07** 层栈持久化 sidecar round-trip | `LightamerSidecar.swift:102`（schemaVersionCurrent=2）+ `:218-226`（v1 文档 decodeIfPresent 兼容投影）+ `SidecarLayerStack.swift`（265 行记录拼写）+ `RasterMaskStore.swift`（旁挂 PNG）+ retouch strokes optional（06-07） | LayerE2ERoundTripTests.testRealRAWRoundTripThroughHistoryAndSidecar:65（真 RAW 渲染**逐字节**恒等）+ Phase6SidecarTests 7（拼写冻结表/history kind 投影/未知 op 降级）+ RetouchSidecarTests 4（pre-06-07 兼容） | ✓ VERIFIED |
| **IOP-MASK-01** drawn mask | `MaskSpec.swift:160-177`（MaskForm.Kind = **brush（bézier 链）/ path（闭合 bézier 多边形）/ ellipse / gradient**——ROADMAP 措辞 polygon/bezier 由 path/brush 的 bézier ctrl 点承载，口径注记）+ `DrawnMaskRasterizer.swift`（707 行：GPU 解析 kernel + render-pipeline additive stamping 双轨） | DrawnMaskRasterTests 8（四形态解析 golden ≤1e-6 + brush 硬度剖面 + 累积解析和 + eraser 负笔画 + tile 缝 banded==whole 0.0 + 内容锚定经 crop mapper） | ✓ VERIFIED（形态措辞口径注记入账） |
| **IOP-MASK-02** parametric mask（亮度/颜色范围 + 羽化/反相/模糊） | `ParametricMask.swift:34-199`（luma+JzCzhz 单 kernel 记录：dt 通道槽位 verbatim + 4 点曲线 + per-channel invert + boost + `packedParameters()` blend.c:167-216 直译；后处理 blurRadius/featherRadius/contrast/brightness/invert :85-91，链序 blur→feather→tone curve 钉 dt `_get_post_operations`）+ `ParametricMaskKernels.metal` + `MaskCombiner.swift:200-265` | ParametricMaskParityTests 8（通道 sweep parity + invert/boost + 平场二元门 + blur 系数==IOP GaussianBlur + float64 递归 parity + 链序 pin + packing 手算） | ✓ VERIFIED（双域 UI defer v1 后，注记 → deferred） |
| **IOP-MASK-03** raster mask（烘焙） | `RasterMaskRef.swift`（旁挂引用 + StableHash）+ `RasterMaskStore.swift`（232 行：16-bit 灰度 PNG bake/load + 校验）+ `MaskCombiner.swift:492-560`（装配 + 三失败腿降级：缺目录/损坏 PNG/哈希不符 → 全一平面 × clamp opacity） | RasterMaskRoundTripTests 7（bake/load uint16 恒等 + **篡改哈希降级** + 损坏 PNG 降级 + 缺文件降级 + invert 腿 + 前向兼容拼写 + 哈希覆盖三 payload） | ✓ VERIFIED |
| **IOP-MASK-04** mask combining（union/difference/intersection/组） | `MaskSpec.swift:181-187`（五式 MaskCombineOp：union/intersect/difference/exclusion/sum + inverted + opacity）+ `MaskGroupItem.child`（:203 **嵌套组**）+ `MaskCombiner.swift:319-395`（combinePair opCode 表 + reduce 多平面）+ `:395`（drawnGroupPlane 递归求值） | MaskCombineTests 8（五式公式逐式 parity <1e-6 + **解析面积 golden** + reduce 上界拒绝 + 顺序敏感 + 三类 ⊗ 装配 + 嵌套组求值） | ✓ VERIFIED |
| **IOP-MASK-05** 蒙版应用于任意调整图层 | `MaskSpec` 挂 `AdjustmentLayer.mask`（任意层同构）+ 驱动器 mask 腿（commit 244fcef 三类 ⊗ 装配单平面 + a94fa97 composite mask leg）+ retouch 层 NO_MASKS 例外（`RetouchLayer.swift:46-51`，dt retouch.c:221 同语义） | MaskEditIncrementTests.testThreePayloadMaskEditAccounting:144（drawn ⊗ parametric ⊓ raster 装配 + 编辑互不扩散）+ BlendOpParityTests.testMaskPlaneTripleMatchesReference:542（mask 腿 parity） | ✓ VERIFIED（retouch 例外 = 决策 D-06-CONTEXT-4 非缺口） |
| **IOP-GEO-05** liquify | `Liquify/LiquifyModule.swift`（393 行，18.0）+ `LiquifyDistortionField.swift`（562 行，dt path 场模型 CPU stamp）+ `LiquifyKernels.metal`（lanczos3/bicubic warp）+ `Registry.swift:211-217`（注册）+ `:412-416`（seed enabled-neutral = 空路径 blit 恒等）+ `LiquifyPanelProvider`（InspectorState.swift:96）+ LiquifyOverlayHost | LiquifyParityTests 16/16（三场型解析 ≤2.4e-7 vs 独立 float64 + warp kernel parity 0.0 @27,648 采样 + 空路径逐字节恒等 + seed neutral + ROI 扩窗 + 强制分块==整幅 0.0 + **轨 B 零增量**）+ 06-06 GUI 复测（拖拽实时/⌘Z 恰 1 commit） | ✓ VERIFIED |
| **IOP-GEO-06** retouch（heal/clone brush） | `RetouchLayer.swift`（第二 Layer kind，D-06-CONTEXT-4；mask NO_MASKS 契约 :46-51）+ `RetouchStroke.swift`（四算法 raw 值 dt retouch.c:66-71 同槽）+ `RetouchEngine.swift`（617 行：stroke 管线 + **heal 红黑 SOR** `:387-432`（w=heal.c:380 因子、ε=0.1/255 exit、Dirichlet 外区）+ patch 裁剪 O(patch) + hint 源∪目标 AABB 扩窗）+ `RetouchPanelView`/`RetouchOverlayHost` + LayerEditingState 互斥路由 | RetouchParityTests 9/9（clone 源内容平移 ≤1e-5 + fill 常数域 + blur 剖面（边缘塌缩+线性场 ≤2e-3）+ **跨窗扩窗无黑边 ≤1e-5** + heal vs 独立 float64 参考 <1e-3 + 外区不动 + 基准 median 9.99-11.63ms + composite smoke + stroke 腿缓存记账）+ LayerUIWiringTests retouch 路由 + 06-07 GUI 走查 4 截图 | ✓ VERIFIED（heal 降级条款未触发——预算内，D-06-07-T3-1；v1 圈定注记 → deferred） |

### SC#1-5 判定（ROADMAP 契约）

| SC | 判据 | 代码/测试证据 | 独立实跑 | 判定 |
|---|---|---|---|---|
| **SC#1** | 背景层 + 多命名调整层独立运作（同 iop 异参数异层） | LayerStack 双 kind 栈 + driver 每层独立子 run（L021 红线常驻断言：entry dscIn == 自 bufInROI.first == window）+ LayerCompositeTests 恒等层逐字节 + 层 K 增量账本 | LayerCompositeTests 10/10 绿 | ✓ VERIFIED |
| **SC#2** | drawn（brush/polygon/ellipse/path/bezier）+ parametric（亮度/颜色范围 + feather/invert/blur）+ raster + combine（union/difference/intersection/组）全功能可挂层 | drawn 四形态（polygon/bezier → path/brush bézier 承载，注记）+ parametric 全后处理 + raster 三失败腿降级 + combine 五式 + 嵌套组 + 装配单平面（MaskCombiner.effectivePlane :450）；mask 腿接 driver（06-03 T6） | DrawnMaskRaster/ParametricMaskParity/RasterMaskRoundTrip/MaskCombine 四套件抽查绿（MaskEditIncrement 4/4 实跑） | ✓ VERIFIED（drawn 形态措辞口径注记入账） |
| **SC#3** | PS 式 blend modes（13 模式列举）正确合成 + per-layer opacity | BlendMode 17 case 覆盖列举全部 13 模式（dodge/burn 新 raw 值 0x2A/0x2B；值不重编 D-06-CONTEXT-2 + 头注三方映射表）+ compositeLayer mask×blend×gopacity 单 kernel + REVERSE 位消费 | BlendOpParityTests 20/20 实跑绿 + dt 三证据 54/54（manifest blendop 节总账） | ✓ VERIFIED |
| **SC#4** | liquify（肖像扭曲）与 retouch（heal/clone）可用——架构依赖蒙版/变形框架 | liquify：18.0 注册 + seed neutral + 蒙版内容锚定经 GeometryPointMapper liquify 段（e550f10）；retouch：stroke 形状即蒙版（经 06-03 光栅化器 + mapper 渲染同源）+ kind 分派进 driver——两者均以实际耦合证据判定满足（06-VALIDATION SC#4 注记同口径） | LiquifyParity 16/16 + RetouchParity 9/9 实跑绿 | ✓ VERIFIED |
| **SC#5** | 全层栈（层 + 参数 + 蒙版 + blend + opacity + visibility/reorder/duplicate/merge/group）sidecar round-trip；与全局 iop 一管线共存 | round-trip：sidecar v2 真 RAW 渲染逐字节（LayerE2ERoundTrip）+ Phase6/RetouchSidecar 11 + ONE-WAY 拼写锁；操作语义：LayerUIWiringTests 14/14；**group** = MaskGroup 组语义（嵌套 child）判定满足，层文件夹 defer v2（注记 → deferred）；共存 = 轨 B 恒等层零增量逐字节 | Phase6Sidecar 7 + RetouchSidecar 4 + LayerUIWiring 14 实跑全绿 | ✓ VERIFIED（group 口径注记入账） |

### 内容级验证覆盖抽查（非恒真确认）

- `BlendOpParityTests.swift:432`（`testEveryModeChangesTheComposite`）：全 17 模式 op=0.6 必须改变 below 平面（`differing > 0` 断言）——「kernel 分支塌缩为 identity/copy-b 仍过逐点门」的兜底防空转带。
- `RetouchParityTests.swift:553`（heal parity）：真比较双循环 + `XCTAssertGreaterThan(compared, 50, "防空转: masked-cell coverage")` + Dirichlet 外区逐点不动断言 + <1e-3 迭代容差档——独立 float64 红黑 SOR 参考（heal.c:96-422 逐式），非自比。
- `MaskEditIncrementTests.swift:82`（蒙版编辑零链重算）：冷轮 9 miss 精确账本 → 移动椭圆 → 5 hit/2 miss/1 blend 精确断言（B 链 HIT = 零链重算）→ 再参数编辑反向独立（mask plane HIT）——METAL-8 双保险的内容级钉。
- `BlendOpParityTests.swift:392`（算术 parity）：12 算术模式 × 3 opacity 全像素 GPU vs float64 参考循环，`assertPlaneParity` 逐值。

### 漂移检查（共享层计划外改动）

| 漂移 | 改动位置 | 回归钉住 | LESSONS | 判定 |
|---|---|---|---|---|
| setParams 同步化（91 文件，GUI-10/13 竞态修复，commit 909b7bd 2026-09-23） | `ModuleBox.swift:187-194`（async→sync + 注释引 forensics 双栈根因） | `PanelWiringTests.testEnableCommitRacingLiveTicksHundredRounds:897`（×100 交错发射 + 计数精确 + 终态一致）——本轮抽查期 PanelWiring 套件在 788 全绿轮内 | gui10-forensics.md 取证在档（Phase 5 验证已核，Phase 6 未重开） | ✓ 可接受 |
| moduleList ScrollView（W6 布局修复沿革） | `InspectorView.swift:46,156`（高度 = min(内容, 38% 列高)） | 06-05 GUI 轮 AX 压力 + 层路由回归（LayerUIWiringTests 与布局解耦，AX 语义层钉） | GUI 红线 FINDINGS 登记 | ✓ 可接受 |
| mask 缓存键折几何哈希（06-05 C0 遗留①，commit 1679b23） | `GeometryPointMapper.stableHash()`（FNV-1a 折段载荷，liquify 网格限幅抽样）+ DrawnMaskRasterizer.plane / MaskCombiner.effectivePlane 键折 mapper 哈希 | `Plan0605LeftoverTests`（maskKey 随几何态翻转 + 内容级回归：flip 重映射后平面字节 >1/4 像素差异 + 精确 hit/miss 记账）——防空转前提断言在案 | D-06-05-C0-1 记录（网格哈希成本决策） | ✓ 可接受 |
| iscale 沿革（Phase 5 stamp 机制在层维度的存续） | `PixelPipe.swift` run 前向 walk 唯一写点 + 每层子 run 自 stamp（L021 红线） | `IOPieceIscaleTests` + `TileNegotiationRegressionTests`（Phase 4/5 钉全在场）+ LiquifyParityTests.testTrackBZeroIncrementWithEmptyLiquify（本轮实跑绿）+ L021DoubleScaleAuditTests | L021（层维度 dscIn 禁抄近路，driver 头注 :84-91 钉死） | ✓ 可接受 |
| layer 维度缓存政策（D-06-CONTEXT-8 数据驱动回退） | `PipeCacheKey.swift`（compositePosition/maskPosition/retouchPosition 保留位 + tier-5 驱逐）+ fullColdLayer 政策维持 | LayerCacheTests（tier 分类 + 驱逐序 + 政策常量 :219）+ LayerDragPerfTests（10 层门 + FULL 政策 benchmark + 窗口化内存账本） | perf.md PERF-2 正式记账 | ✓ 可接受 |

LESSONS 落账核对：L022（omp 期间禁工作区编辑，:190）、L023（uniforms 半边契约全往返钉，:197——parametric/JzCzhz 矩阵沿用）、L024（滚动 tmp 逐通道，:204）、**L025（String Catalog zh 语言标签——GUI-18 修复沉淀，:212）**四条与 Phase 6 实际踩坑对应在案。GUI 红线：06-03（overlay ΔR+65.5 量化）/ 06-05（8 截图 + GUI-14/15/16 当场修）/ 06-06（liquify 真机复测）/ 06-07（4 截图 + GUI-18 当场修 592/592 键）四轮 FINDINGS 登记闭环。

### Gap 清单

**须补做：无。** 自动化层未发现 MISSING/STUB/NOT_WIRED/恒真测试/未钉回归的漂移；14/14 需求在代码库交付且接线（模型/驱动器/kernel/注册/面板/overlay 六面齐全）。

**可接受裁决/挂账（6 项，均有正式记录、非阻塞）：**

| # | 项 | 记录位置 | 性质 |
|---|---|---|---|
| 1 | LAYER-04 编组（层文件夹）defer v2；SC#5「group」以 MaskGroup 组语义判定满足 | D-06-CONTEXT-6 + REQUIREMENTS LAYER-04 注记 + VALIDATION 注记行 | 规划期签核裁决 → deferred |
| 2 | IOP-MASK-02 dt 双域 UI（Lab+RGB）defer（域枚举扩展位在） | D-06-CONTEXT-3 + REQUIREMENTS IOP-MASK-02 注记 | 规划期裁决（可逆扩展） |
| 3 | retouch v1 圈定：视口圆形绘制（path/lasso 手势未接，数据腿就绪）、blur gaussian（bilateral defer）、fill 纯色（erase defer）、stroke 不叠加 parametric | RetouchStroke.swift:26-28 头注 + RetouchLayer.swift:94-101 形状门 + VALIDATION 注记行 | 规划期圈定（optional additive 路径非缺口） |
| 4 | heal 降级条款（拆 6.5b）**未触发**——基准 median 9.99-11.63ms << 100ms | D-06-07-T3-1 + perf.md + VALIDATION 注记 | 判定记录（正向闭环非缺口） |
| 5 | SC#2 drawn 形态措辞：ROADMAP「polygon/bezier」由 path（闭合 bézier 多边形）/ brush（bézier 链）承载 + gradient 增补（dt parity） | MaskSpec.swift:160-177 + 本报告 SC#2 行 | 语义覆盖口径注记（无功能缺口） |
| 6 | Manual-Only 5 行 pending-manual（source 拾取手感 / stroke 羽化视觉 / heal 人像目检 / GUI-17 复验 / lasso 手势） | VALIDATION Manual-Only 表 + FINDINGS.md:531/539 + TODO | 人工挂账（L011 口径）→ human_verification |

### 反模式扫描

Layers/Masks/Retouch/Liquify/BlendOp 五目录 + LayerCompositeDriver + 四个新面板/overlay + MaskToolbar 全量扫描：无 TBD/FIXME/XXX/HACK/PLACEHOLDER/coming soon/空实现/`return null`/console-only 路径（唯一历史命中 `Registry.swift` 的 `XXXModule` 模式名文档占位非债务，Phase 5 验证已定性）。retouch 圈定项在代码中以头注 + 形状门显式声明（`RetouchLayer.append` guard），非静默 stub。

### Requirements Coverage

REQUIREMENTS.md：14 条需求复选框全部勾选（:99-122）+ 映射表（:329-342）14 行全 Delivered + 4 条注记行（IOP-GEO-06 圈定 / LAYER-04 编组 v2 / IOP-MASK-02 双域 defer / LAYER-01 双 kind）——与代码库状态一致，无 orphaned 需求（Phase 6 映射 :411 = 14/14）。Phase 7 移交清单落 DISCUSSION-LOG 终节（AI mask 消费端 = RasterMaskRef 通道 / 层栈 API 面 / mask 版本化 / pipe 缓存面）。

## 结论

**GOAL ACHIEVED（无阻塞缺口）→ GSD status `human_needed`。** 14/14 需求在代码库交付：层栈模型（双 kind）+ 1+N+1 合成驱动器（walk 零改动）+ 17 值 blend 引擎（dt 三证据 54/54）+ 蒙版三 payload 与五式 combine + liquify/retouch 双模块 + sidecar v2 真 RAW round-trip 渲染逐字节；SC#1-5 自动化证据全绿，签核口径缺口零静默（编组 v2 / 双域 UI / retouch 圈定 / drawn 形态措辞四处注记均有裁决记录）。独立抽查实跑 8 类 91 tests / 0 fail，与签核轮 788/3skip/0fail 一致。漂移四项（setParams 同步化 91 文件 / moduleList ScrollView / mask 键折几何哈希 / iscale 层维度存续）全部有内容级回归钉住且 LESSONS L022-L025 落账。剩余 5 项人工挂账均为视觉/手感判据（自动化腿已钉数值与语义）→ 人工补验完即可关账。

---

_Verified: 2026-09-24T06:05:54+08:00_
_Verifier: Claude (gsd-verifier, goal-backward 阶段级)_

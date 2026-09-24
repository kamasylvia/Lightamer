---
phase: 07-ai-modules
verified: 2026-09-24T18:48:21+08:00
status: human_needed
score: 4/4 must-haves verified（AI-01/05/06/07 全部在代码库交付、注册接线且内容级测试覆盖；SC#1-5 按修订口径全绿，SC#1/SC#5 带注记）
behavior_unverified: 2
overrides_applied: 0
overrides: []
re_verification:
  previous_status: none
  previous_score: none
  gaps_closed: []
  gaps_remaining: []
  regressions: []
gaps:
  - truth: "GUI-21 候选缺陷（skinSmooth 全局链启用+强度变化视口零刷新）未正式登记、未复现归因；其根源之一 = skinSmooth 全局链腿零内容级测试"
    status: partial
    reason: "07-3 验收（PROGRESS.log 2026-09-24 行）与收口提交 6bf4b76 提交信息均声称『GUI-21 filed』，但 FINDINGS.md / TODO.md / 全仓无任何 GUI-21 条目——登记声明与登记记录不符（可审计性缺口）。缺陷本身候选态：模块数学已被内容级测试钉住（SkinSmoothParityTests 8/8 + testSkinSmoothEnabledCompositeDiffersFromDisabled），但后者只走 LayerCompositeDriver 层腿——D-07-CONTEXT-2 认定的合法形态『base 链配 raster skin mask』的全局链腿零测试覆盖，无法静态排除 skinSmooth 专属接线缺陷；通用全局链参数→渲染路径由 PanelWiring 60 测试 + Phase 3-6 GUI 验收背书，故 GUI-19（层链行不显示）与 GUI-21 同根（行显示/交互家族）为最可能根因，但未证实"
    artifacts:
      - path: ".work/gui-acceptance/FINDINGS.md"
        issue: "GUI-19/20 有正式条目（:605/:613），GUI-21 缺席"
      - path: "Tests/LightamerTests/PanelWiringTests.swift"
        issue: "testSkinSmoothEnabledCompositeDiffersFromDisabled:1664 只覆盖层腿；全局链（base instances 含 skinSmooth）无启用态差异断言"
    missing:
      - "GUI-21 正式登记入 FINDINGS.md + TODO.md（与 GUI-19/20 同格式）"
      - "真鼠标复现 + 归因判定：skinSmooth 专属接线缺陷 vs GUI-19 同根 UI 刷新家族——归因若指向 skinSmooth 专属，回注 Phase 7 修复批"
      - "补 1 条全局链腿内容级测试（base instances 含 skinSmooth、enabled+strength 变化 → 渲染差异 >0）"
  - truth: "maskPlane 'L00h' LE UInt16 格式腿无回归测试（P1 修复 3602498 本身在位，但分支不可测盲区未消除）"
    status: partial
    reason: "07-1 验收 P1：层 B 真实推理产出 0x4C303068（'L00h'）像素格式，AIMaskService.maskPlane(from:) 原不支持 → 真实层 B 推理必抛 invalidMask。修复已落（AIMaskService.swift:531-540 折入 OneComponent16 臂 + 探针证据注释），但该分支无任何合成 CVPixelBuffer 单测钉住（Tests/ 全仓 grep 'L00h|4C303068|CVPixelBufferCreate' 零命中）——层 B 推理腿测试宿主 skip（entitlement）使该格式腿在所有验证环境从未真实执行过；同类格式回归将再次漏测"
    artifacts:
      - path: "LightamerCore/Sources/AI/AIMaskService.swift"
        issue: "maskPlane(from:) 五格式臂（:523-571）零测试覆盖——maskPlane 为 internal static，可测而未测"
    missing:
      - "补 1 条合成 CVPixelBuffer 格式臂单测（'L00h'/OneComponent8/'L00f'/32F 至少覆盖 'L00h' + 1 条既有臂对照），锁定 3602498 修复"
deferred:
  - truth: "scribble/lasso 手势（SC#1 『iterative tap/scribble/lasso refinement』的 scribble/lasso 半句）"
    addressed_in: "v1 后（无专属 phase）"
    evidence: "D-07-CONTEXT-4 用户裁决：v1 交互 = tap 含/排点 + ⇧box；升级缝在案——AISubjectSeed.scribble case 预留（AIMaskTypes.swift:67-71）+ 构造即 typed throw scribbleNotSupported（AIMaskService.swift:328-329）+ testScribbleSeamThrowsTyped 钉住"
  - truth: "AI-06 parametric 直挂腿（REQUIREMENTS AI-06 原文『或直接作为 parametric mask』）"
    addressed_in: "v2（REQUIREMENTS AI-06 行注记已落，D-07-CONTEXT-3）"
    evidence: "裁决：Vision mask 是像素非参数曲线，raster 烘焙 = v1 唯一忠实通道；parametric 输入面 Phase 6 已就绪（MaskSpec.parametric），v2 肤色 hz 曲线预设生成器直接挂"
  - truth: "多尺度小波磨皮 / bilateral 边缘感知变体（AI-05 增强路径）"
    addressed_in: "v2（D-07-CONTEXT-6）"
    evidence: "Variant enum 位预留（SkinSmoothModule.swift:73-78：twoBandGaussian 单 case + v2 保留注释 + sidecar 携 rawValue 免 schema 升级）"
  - truth: "层 A generateScaledMask 全分辨率软边腿（层 A 现走 512 级标签合成 + bake 双线性上采样）"
    addressed_in: "Apple 修复 macOS 27 beta 后切回（升级缝保留）"
    evidence: "D-07-1-T2-4：beta 双重损坏（subset 语义坏 + all 集合几何 +3/16 偏移）探针实证；scaledMask 腿保留为 documented upgrade seam（AIMaskService.swift:195-205）；真机 overlay ΔR 量化证明标签腿实用精度足够（10.31% 变化像素达标）"
  - truth: "GUI-20 层 B 资产供给（dev-signed 构建下载无错误但 assetStatus 恒 notReady）→ 层 B ready 态跃迁 + 真实推理端到端在所有验证环境不可达"
    addressed_in: "v1 后观察项（Developer ID / 正式分发签名复验；TODO.md:27 登记）"
    evidence: "macOS 27 beta 资产供给对 development 签名不放行（与 07-1 测试宿主 entitlement 同根）；三态 UI 行为诚实（FINDINGS :613 真机走查）；服务逻辑 + 状态机矩阵全钉（testLayerBEntryGateStates 三态跃迁 + AIAssetStore 矩阵测试）"
behavior_unverified_items:
  - truth: "层 B 真实推理端到端（tap/box 种子 → GenerateIterativeSegmentationRequest 真实执行 → mask 平面产出）从未在任何验证环境成功执行"
    test: "Developer ID 签名构建真机：下载资产至 ready → tap 点选 → 生成蒙版 → bake 落盘"
    expected: "蒙版生成成功且覆盖点选主体；'L00h' 格式腿真实走通（当前由 3602498 修复 + 探针证据背书，无运行时实证）"
    why_human: "测试宿主 entitlement 阻断（2 条 skip-with-reason）+ GUI 轮 GUI-20 阻断——beta 资产供给问题，非代码缺陷；服务逻辑/预算门/Y 翻转全由单测钉住"
  - truth: "磨皮真模型腿（VisionFaceLandmarkProvider 真实人脸 landmarks → SkinRegionLocator hull−保护区⊗personSeg 全链）未在测试宿主执行（合成卡通脸未检出，1 条 skip-with-reason）"
    test: "含真实人脸 RAW 样张：定位皮肤 → skin mask bake → 启用 skinSmooth 目检 pore 保留/无塑料感"
    expected: "skin mask 覆盖肤色区排除五官；磨皮后毛孔/发丝保留（parity <1e-5 数据腿已钉，人眼质量判据补验）"
    why_human: "真模型检测行为 + 人眼质量判据（L011）；现有 3 张样张均无人脸——与 ColorChecker 补拍同批（TODO 登记）"
human_verification:
  - test: "tap-to-segment 手感真机走查（点选/⌥·右键排点/⇧拖 box + 点计数满禁点 toast）"
    expected: "点选亮主体、排点剔除区收缩、box 圈选生效；13/11 满禁点出 toast 不崩；精修同 maskID 覆盖（⌘Z 逐级还原）"
    why_human: "视口手势 CGEvent/AX 均不可驱动 + 手感判据；数据腿已钉（testSegmentSessionBudgetAndYFlipWiring + testSegmentRouteMutexExhaustive）；ready 入口被 GUI-20 阻断，待资产可下载后复验"
  - test: "磨皮 pore-level 目检 + 「定位皮肤」真人像走查"
    expected: "磨皮自然不塑料（毛孔/边缘保留）；定位皮肤 mask 挂层 + 面板三滑块生效"
    why_human: "人眼质量判据 + 需含人脸样张（现有 3 张均无人脸）；自动化腿（parity 6×6 <1e-5 + 恒等三元组 + 启用态差异）已钉"
  - test: "instance 勾选浮层真机走查（多主体照片层 A 生成）"
    expected: "多主体触发浮层，勾选子集 bake 对应主体"
    why_human: "需多主体样张；子集语义已由 07-1 双向断言钉住（testLayerAMultiInstanceSubsetSelection）"
  - test: "GUI-21 复现与归因（skinSmooth 全局链启用+强度变化，真鼠标操作）"
    expected: "判定零刷新是否复现；若复现，归因 skinSmooth 专属接线（回 Phase 7 修复）或 GUI-19 同根 UI 刷新家族（并 UI 打磨轮）"
    why_human: "AX 对 tap-gesture 行不可驱动（FINDINGS :605 备注），复现需真鼠标；候选缺陷未经复现不能定性"
---

# Phase 7: AI Modules (Native Vision Masking & Retouching) — 阶段目标级验证报告

**Phase Goal（ROADMAP §Phase 7）:** 交付 Apple **原生** Vision/Core Image 框架直接实现的 AI 蒙版/修图子集——无自定义训练 Core ML 模型：`VNGenerateForegroundInstanceMaskRequest` 主体隔离（AI-01）+ Vision face/segmentation 地标驱动的频率分离磨皮（AI-05）；全部 AI 蒙版作为**可编辑输入**接入 Phase 6 图层/蒙版系统（AI-06）而非黑盒（AI-07）。全部检测原生跑 Apple Silicon Neural Engine——无第三方 ML 模型、无网络调用。

**Verified:** 2026-09-24T18:48:21+08:00
**Status:** human_needed（自动化层全绿、无 MISSING/STUB/NOT_WIRED；2 项须补做 gap + 5 项计划内 deferred 挂账 + 2 项真模型腿 behavior-unverified + 4 项人工验证）
**Re-verification:** No — 初始验证（阶段目标级，非 plan 级复验）

## Goal Achievement

### 验证方法

从 ROADMAP §Phase 7 的 GOAL + 4 条需求（AI-01/05/06/07，含 D-07-CONTEXT-1 SC#5 修订口径 / D-07-CONTEXT-3 AI-06 raster 口径 / D-07-CONTEXT-4 scribble 后置）反向推导 must-have，逐条在**代码库**找承载实现（服务/类型/iop/定位器/面板/overlay/接线），核内容级测试覆盖（抽查测试体确认真比较循环 + 防空转门，非恒真），并独立实跑 5 个 AI 测试套件。SUMMARY 自述不作为唯一证据。证据来源：

1. **AI 服务面**：`LightamerCore/Sources/AI/` 四件——AIMaskService.swift（604 行：层 A 两段式 catalog→label 合成 / 层 B segmentSubject 资产门控 / personSeg 腿 / 设备 pin 三态守卫 / 五格式 mask 解码）+ AIMaskTypes.swift（seed/budget/Y 翻转单缝/typed error 面）+ AIAssetStatus.swift（actor 状态机 + 首启提示政策）+ AIMaskResample.swift（像素中心双线性）。
2. **iop 面**：`LightamerIOP/Sources/SkinSmooth/` 四件——SkinSmoothModule.swift（378 行：两频分离 + raised-cosine 阈值衰减 + 恒等三元组 + ceil(3σ) halo + Variant 位预留）+ SkinSmoothKernels.metal（skin_smooth_mix）+ SkinSmoothReference.swift（float64 正本）+ SkinRegionLocator.swift（529 行 hull−保护区⊗personSeg + yaw 门）。
3. **UI/接线面**：`App/Sources/Lightamer/`——State/AIMaskEditing.swift（唯一 bake 通道 + AIMaskEntryGate 纯函数门）+ UI/Overlay/MaskToolbarView.swift AI 组（:128-173）+ SegmentEditingOverlayHost.swift（tap/排点/box + 预算 toast）+ InstancePickerOverlay.swift + UI/AIDownloadPrompt.swift（ContentView.swift:106 挂载）+ UI/Inspector/SkinSmoothPanelView.swift + State/InspectorState.swift:107（第 25 席注册）+ State/LayerEditingState.swift:207（segment 第 4 编辑模式）。
4. **注册/槽位面**：V50Order.swift:159（skinSmooth 66.5 非 dt 首例 + 表头标记 :12）+ Registry.swift:211-218（注册）/ :332-334（kernel）/ :429-432（ENABLED-neutral 种子）。
5. **测试面**：Phase 7 新增 7 个测试文件（AIMask 确定性/语义/几何/编辑路径 + SkinRegion 几何 + SkinSmooth parity + PanelWiring/LayerUIWiring 扩展）；本验证独立实跑 5 套件 **49 tests / 2 skip / 0 fail**（见下）+ 测试体内容级抽查（防空转门逐条确认）。
6. **GUI 红线**：FINDINGS.md「Plan 07-3 T4 AI 集成 GUI 验收轮」（:582-632，真机解锁屏 7 截图 + ΔR 量化 10.31%/8.97%/13.0 + GUI 级 ⌘Z + 层 B 三态走查 + zh 标签全量）。
7. **签核面**：07-VALIDATION.md（validated + nyquist_compliant: true）+ 07-DISCUSSION-LOG.md SC#1-5 终核对 + REQUIREMENTS.md AI-01/05/06/07 翻账 Delivered ×4（:347-350）+ input/golden/manifest.md skinSmooth 节（:807）与 Phase 7 golden 总账（:835-841）+ .work/07/perf.md。

### 独立实跑记录（抽查）

命令 `caffeinate -dis Scripts/test-direct.sh '<Class>'`（直启宿主，L019b 口径；2026-09-24 本验证执行）：

| 测试类 | 覆盖 | 结果 |
|---|---|---|
| AIMaskSemanticTests | 语义门：IoU ≥0.9 / 背景环 ≤0.1 / 双主体 subset 双向 / noSubject typed / 预算边界 / 状态机矩阵 | 10/1skip/0fail（0.9s） |
| AIMaskDeterminismTests | 确定性门：层 A gpuPinned 进程内+跨进程逐字节恒等 / supported 枚举含 GPU / CPU pin typed 拒绝 / 层 B pin 拒绝 | 6/1skip/0fail（0.79s，真实 Vision 推理） |
| SkinSmoothParityTests | 恒等三元组逐字节（a=0 / mask nil==全一 / 平场）+ zero-mask 反向锚 + σ/halo 链 + float64 parity | 8/0fail（1.16s） |
| AIMaskEditPathsTests | 五条覆盖路径内容级 + sidecar schema 零升级 | 6/0fail（0.05s） |
| LayerUIWiringTests | AI 集成（⌘Z 恰 1 + refine 覆盖 + 三态门 + 五模式互斥 + 预算/Y 翻转）+ Phase 6 层操作回归 | 19/0fail（4.09s） |

**合计 49 tests / 2 skip / 0 fail**（2 skip = 层 B 真推理腿 entitlement skip-with-reason，与签核轮 845/6skip/0fail 结论一致；flake 未触发，02-04 台账隔离判定未启用）。

### 逐需求判定表

| 需求 | 代码证据（file:line） | 测试证据 | 判定 |
|---|---|---|---|
| **AI-01** 主体隔离（class-agnostic，层 A 离线 + 层 B tap 精修 + 下载门控） | `AIMaskService.swift:150-169`（层 A stage 1 detectInstances→`GenerateForegroundInstanceMaskRequest`）+ `:184-253`（stage 2 `allInstancesMask` 标签合成——D-07-1-T2-4 beta scaledMask 双重损坏的正确性替代腿，scaled 保留升级缝 :195-205）+ `:261-361`（层 B segmentSubject + buildLayerBRequest 种子/质量/ROI/预算门）+ `AIMaskTypes.swift:20-99`（Y 翻转单缝 visionPoint :33-35 + 13/11 预算 :94-99）+ `AIAssetStatus.swift:57-190`（三态 actor 状态机 + 首启提示政策）+ 接线：`MaskToolbarView.swift:128-173`（AI 组：层 A 一键 + InstancePickerOverlay + 层 B 三态门）+ `SegmentEditingOverlayHost.swift`（tap/⌥排点/⇧box + 满禁点 toast :154）+ `AIDownloadPrompt.swift`（ContentView.swift:106 挂载） | AIMaskSemanticTests 10/1skip（IoU ≥0.9 :124 / 背景 ≤0.1 :126 / subset 双向 :153-185 含「防空转 compared>0」:185 / noSubject typed :140 / 预算 13/11 :246-278 / scribble 缝 typed :286-293 / 状态机矩阵 :331-397）；AIMaskDeterminismTests 6/1skip（gpuPinned 逐字节进程内+跨进程 / CPU+层 B pin typed 拒绝）；LayerUIWiringTests `testSegmentRouteMutexExhaustive`（五模式穷举）+ `testSegmentSessionBudgetAndYFlipWiring`；GUI：FINDINGS :582-632（IMG_4276.CR3 真实推理 bake `ai-subject-<uuid>.png` + 层 B 三态真机走查） | ✓ VERIFIED（scribble/lasso = D-07-CONTEXT-4 计划内后置 → deferred；层 B 真推理端到端 = GUI-20 beta 资产阻断 → behavior_unverified + human） |
| **AI-05** 频率分离磨皮（Vision 定位 + Core Image/Metal 分离，保细节不塑料，无自定义模型） | `SkinSmoothModule.swift:67-378`（math 头注 :4-60 = 两频高斯分离 + raised-cosine 阈值衰减 raised-cosine 软窗 :26-33 + 共享 RGB 幅值防色偏 :24 + Variant enum 位预留 :73-78 + 66.5 槽 :113 + ENABLED-neutral :217-219 + ceil(3σ) halo :211-213 + direct-drive maskPlane :133）+ `SkinSmoothKernels.metal`（skin_smooth_mix）+ `SkinSmoothReference.swift`（float64 正本）+ `SkinRegionLocator.swift`（hull + 额头带闭合 − 五官保护区 ⊗ personSeg + yaw 门 45° typed :31-32 + 多脸 union）+ 低频腿复用 `Common/GaussianBlur.swift` 零重写 + 注册 `Registry.swift:211-218/332-334/429-432` + V50Order.swift:159 + 面板 `InspectorState.swift:107`（第 25 席）+ `SkinSmoothPanelView.swift`（三滑块 + 定位皮肤 + 保护区 toggle） | SkinSmoothParityTests 8/8 实跑（三元组逐字节 :144-231 每条含「anti-vacuum compared>0」门 + σ 链手算 :236-258 + float64 parity 双闸 1e-5 :265-304）；SkinRegionGeometryTests 8/1skip（hull 内=1/保护区=0/yaw 门/多脸 union/坐标换算——纯 Swift 不跑模型）；PanelWiringTests `testSkinSmoothPanelDispatch` + `testSkinSmoothLayerScopeDragCommitsOnceAndUndoRestores`（D-H1 恰 1）+ `testSkinLocateCommitWritesMaskSlotOneCommit` + `testSkinSmoothEnabledCompositeDiffersFromDisabled`（内容级启用差异 :1664，防空转 >0 字节） | ✓ VERIFIED（pore 级人眼目检 = Manual-Only 挂账——需含人脸样张；真模型腿 1 skip → behavior_unverified；多频变体 = D-07-CONTEXT-6 v2 → deferred；全局链腿覆盖缺口 → gap#1） |
| **AI-06** AI 蒙版作为图层/蒙版输入（raster 烘焙唯一忠实通道，D-07-CONTEXT-3） | `AIMaskEditing.swift:89-176`（唯一 bake 通道：decodeFrameInput 解码帧锚定 :95-102 → AIMaskResample 双线性规范化 :143-151 → `RasterMaskStore.bake` :153-156 → `MaskSpec.raster` 写选中层 mask 槽保留既有 payload :161-165 → 恰 1 条 commitLayerEdit + landing form（hot layer + overlay 0.85 + brush 工具臂装）:169-173）+ `AIMaskResample.swift:24-98`（像素中心双线性 + 仅小图上采样 + r32Float 纹理上传）+ `RasterMaskStore.swift:88-99`（featherRadius 增件，>0.1 才接 blur——dt blend.c:306-307 门）+ `AIMaskSource` 三前缀文件名 = D-07-CONTEXT-5 同 maskID 覆盖重 bake（:29-52） | LayerUIWiringTests `testAIMaskCommitOneSnapshotUndoAndRefineOverwrite`:475（⌘Z 恰 1 snapshot + PNG 落盘 + 同文件新 hash 精修逐级还原）+ `testAIMaskSourceFileIdentity`:549；RasterMaskRoundTrip 9/9（AI 平面 uint16 恒等 + 覆盖重 bake hash 翻转缓存记账）；AIMaskGeometryTests 6/6（双线性权重 [0,0.25,0.75,1] + 行 0=图顶对齐 + 仅小图上采样 + Y 翻转向量 + 羽化剖面 + 默认 0 逐字节恒等）；GUI：真机 sidecar history/undo 证据（FINDINGS 07-3） | ✓ VERIFIED（parametric 直挂腿 = D-07-CONTEXT-3 v2 → deferred，REQUIREMENTS 注记已落） |
| **AI-07** 可编辑非黑箱（手动边缘/羽化/反向/组合全可用） | 生成即 bake 语义 = `AIMaskEditing.swift:8-13` 头注 + 产物进 Phase 6 既有编辑世界（`MaskSpec.raster` 同 payload，与手画蒙版不可区分）；AI 参数永不落盘（:21-24 头注 + `AIMaskSource.fileName` 同名覆盖 = 无生成参数态） | AIMaskEditPathsTests 6/6 实跑（内容级 L020 方向断言）：`testDrawnPatchDifferenceRepairDirection`:165（drawn 差集修补方向）/ `testParametricIntersectTightensRaster`:206（⊓ 收紧）/ `testInvertFlipsEffectivePlane`:234（逐字节往返）/ `testFeatherRebakeSoftensEdgesAndFlipsIdentity`:259（hash 翻转 + 边界均值下降）/ `testRefineRegenerateOverwritesSameMaskIDWithCacheBookkeeping`:308（同 maskID 覆盖 + MISS-then-HIT 记账）/ `testSidecarSchemaZeroUpgradeAIParamsNeverPersist`:351（移除 mask 子树逐字节还原 + 无 quality/seed/refine 键） | ✓ VERIFIED |

### SC#1-5 判定（ROADMAP 契约，SC#5 按 D-07-CONTEXT-1 修订措辞）

| SC | 判据 | 代码/测试证据 | 独立实跑 | 判定 |
|---|---|---|---|---|
| **SC#1** | 主体隔离 class-agnostic 正确 + WWDC26 iterative refinement 可交互 | 层 A 两段式 + 标签合成腿（beta scaledMask 损坏的替代，D-07-1-T2-4）+ 层 B tap/box/含排点/预算门 + 第 4 编辑模式互斥路由 + InstancePickerOverlay；scribble/lasso = D-07-CONTEXT-4 后置（升级缝在案） | 语义门 10 + 确定性门 6 实跑绿；GUI 真机层 A 端到端 | ✓ PASS（注记：层 B ready 跃迁被 GUI-20 阻断 = behavior_unverified；真模型腿人机交互手感 = Manual-Only） |
| **SC#2** | 频率分离磨皮自然保细节不塑料，纯公开 API 无自定义模型 | 两频高斯分离 + raised-cosine 阈值衰减（低幅强衰减/高幅保留 = 防塑料机制，D-07-CONTEXT-6）+ float64 parity <1e-5 + 恒等三元组逐字节 + SkinRegionLocator 纯 Swift 几何 | SkinSmoothParity 8/8 + SkinRegion 8/1skip 实跑绿 | ✓ PASS（pore 级人眼目检 = Manual-Only 挂账，数据腿全钉；L011 口径） |
| **SC#3** | AI mask 烘焙为 raster mask（IOP-MASK-03）挂任意 Phase 6 调整层 | AIMaskEditing 单通道 → RasterMaskStore.bake → MaskSpec.raster → 恰 1 stackSnapshot；round-trip 存活 | testAIMaskCommit... + RasterMaskRoundTrip 9/9 + GUI 真机 sidecar ⌘Z | ✓ PASS |
| **SC#4** | AI mask 可编辑非黑盒（边缘精修/羽化/反向/组合，IOP-MASK-04 操作） | 五条覆盖路径全走 `MaskCombiner.effectivePlane` 自身装配——与手画蒙版完全同一编辑/合成/持久化世界；AI 参数零落盘 | AIMaskEditPathsTests 6/6 实跑绿（内容级方向断言） | ✓ PASS |
| **SC#5** | 层 A 离线（OS 内置）；层 B 一次性下载 + assetStatus 门控 + 层 A 恒可用 fallback（修订口径 D-07-CONTEXT-1）；100MP 延迟可交互（缓存免重跑） | 层 A/personSeg/faceLandmarks OS 内置零下载；AIAssetStore 三态 + AIMaskEntryGate 纯函数 + AIDownloadPrompt（ContentView:106）+ 层 B notReady typed 拒绝（AIMaskService.swift:274-286）；perf.md warm：层 A 15-16ms / 层 B accurate 85-126ms（GFX 102MP）全 ≪1s（D-07-1-T1-3 warm 裁定，cold = 一次性首编译 spinner 承接）；缓存 = bake 落盘 + 既有 mask 缓存链（refine MISS/HIT 记账实证） | AIAssetStore 状态机矩阵测试 + testLayerBEntryGateStates + GUI 真机三态走查（prompt zh/declined 持久化/置灰引导） | ✓ PASS（注记：层 B ready 跃迁真机复验 = GUI-20 v1 后观察项；dev-signed 限制非代码缺陷——三态 UI 行为诚实已实证） |

### 内容级验证覆盖抽查（非恒真确认）

- `AIMaskSemanticTests.swift:185`（subset 双向）：每实例 IoU vs 自己框 ≥0.9 且对他框覆盖 ≤0.05 后带 `XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")`——语义门防空转带。
- `SkinSmoothParityTests.swift:151-158`（a=0 blit）：逐字节 bit-pattern 比较循环 + `XCTAssertGreaterThan(compared, 0, "anti-vacuum")`；parity 门 `testFrequencySeparationFloat64Parity:304` 双闸（relative 1e-5 + absFloor 1e-5）GPU vs 独立 float64 参考（bring-up 曾抓转置 bug——parity 门真比对实证）。
- `PanelWiringTests.swift:1664`（启用态差异）：enabled/disabled 双跑 `LayerCompositeDriver.composite` 全字节 zip 比较 `differing > 0` 断言——但**只走层腿**（见 gap#1）。
- `AIMaskEditPathsTests.swift:351`（schema 零升级）：移除 mask 子树后层记录逐字节还原 + 编码字节仅含 fileName/maskHash/invert——AI 参数不落盘的负向断言。

### 漂移检查（共享层计划外改动）

| 漂移 | 改动位置 | 回归钉住 | LESSONS/记录 | 判定 |
|---|---|---|---|---|
| `RasterMaskStore.bake` 增 featherRadius 参数（07-1 T4） | `RasterMaskStore.swift:88-99`（additive 默认 0 = 逐字节零改动，>0.1 才接 MaskCombiner.blur） | `AIMaskGeometryTests.testBakeDefaultFeatherZeroIsByteIdentical:172`（默认 0 零改动）+ `testBakeFeatherProfileOnStepEdge:133`（羽化剖面 mid≈0.5 单调）+ AIMaskEditPaths feather 路径 | D-07-CONTEXT 羽化定案 + 07-1 T4 交付记录 | ✓ 可接受（钉住） |
| `maskPlane` 增 'L00h' LE UInt16 分支（07-1 验收 P1，commit 3602498） | `AIMaskService.swift:531-540`（折入 OneComponent16 臂 + 探针证据注释：bpr=2·w、0x1376/0xFEFE 半浮点解读证伪） | **无回归测试**——全仓 Tests 无 'L00h'/合成 CVPixelBuffer 格式臂测试；层 B 推理腿宿主 skip 使该分支不可达 | P1 记录在 PROGRESS.log + commit 3602498 body（根因 = skip-with-reason + bench.swift 只读尺寸不读格式） | ⚠️ **缺口（gap#2）**——修复在位但不可审计地防复发，须补 1 条格式臂单测 |
| AIDownloadPrompt 挂 ContentView（07-1 T3） | `ContentView.swift:106`（`.modifier(AIDownloadPrompt())`）+ `LightamerApp.swift:129`（与 MaskToolbar 共享同一 app 级 AIDownloadModel——单状态机 D-07-CONTEXT-1） | `testLayerBEntryGateStates`（三态跃迁矩阵 LayerUIWiringTests:563）+ AIAssetStore 矩阵测试 + GUI 真机三态走查 | FINDINGS :613（GUI-20 条目） | ✓ 可接受（接线实证） |
| setParams 同步化沿革（Phase 5 GUI-10/13 修复的存续） | `ModuleBox.swift:194-200`（sync 全 mutating + 注释引 gui10-forensics 双栈根因） | `PanelWiringTests.testEnableCommitRacingLiveTicksHundredRounds:897`（×100 交错发射）——Phase 7 期间该套件随 60/60 全绿轮存活 | gui10-forensics.md 在档（Phase 5/6 验证已核，Phase 7 未重开） | ✓ 可接受（钉住） |
| LESSONS L025（String Catalog zh 标签） | `LESSONS.md:212`（GUI-18 修复沉淀——部分翻译 .lproj 整体破坏回退） | AIDownloadPrompt 9 处 `String(localized` + 面板四件套 zh 标签——GUI 轮「zh 标签首屏全量」核过（VALIDATION + FINDINGS 07-3） | L025 落账在案 | ✓ 可接受 |

### Gap 清单

**须补做（2 项，见 frontmatter `gaps` 结构化条目）：**

1. **GUI-21 未正式登记 + 未归因 + 全局链腿零测试**——登记声明（PROGRESS.log / commit 6bf4b76「GUI-21 filed」）与登记记录（FINDINGS.md/TODO.md 零条目）不符，违反可审计性；候选缺陷本身不能静态排除 skinSmooth 专属接线问题（全局链形态 = D-07-CONTEXT-2 合法交付面，但 enabled-differs 内容测试只覆盖层腿）。补：正式登记 + 真鼠标复现归因 + 1 条全局链内容级测试。
2. **'L00h' 格式腿回归测试缺失**——3602498 P1 修复在位（源码 + 探针证据注释），但五格式臂零测试覆盖；同一盲区（skip 腿背后的格式解码）再次变化时将重演漏测。补：合成 CVPixelBuffer 格式臂单测（'L00h' + 至少 1 条既有臂对照）。

**两项均为小额可补做（测试/登记层面），不推翻任何需求判定；归因后若 GUI-21 指向 skinSmooth 专属缺陷，再立修复批。**

**可接受裁决/挂账（均有正式记录、非阻塞）：**

| # | 项 | 记录位置 | 性质 |
|---|---|---|---|
| 1 | scribble/lasso 后置 v1 后（tap/box 交付，种子枚举升级缝 + typed throw 钉住） | D-07-CONTEXT-4 + AIMaskTypes.swift:67-71 + testScribbleSeamThrowsTyped | 规划期用户裁决 → deferred |
| 2 | AI-06 parametric 直挂腿留 v2（raster = v1 唯一忠实通道） | D-07-CONTEXT-3 + REQUIREMENTS AI-06 注记 + 07-DISCUSSION-LOG SC#3 | 规划期用户裁决 → deferred |
| 3 | 多尺度小波/bilateral 变体留 v2（Variant enum 位预留） | D-07-CONTEXT-6 + SkinSmoothModule.swift:73-78 | 规划期用户裁决 → deferred |
| 4 | generateScaledMask beta 双重损坏 → 标签合成腿替代（scaled 留升级缝） | D-07-1-T2-4 + AIMaskService.swift:176-205 + 真机 ΔR 量化背书 | beta 现实应对（升级缝在案）→ deferred |
| 5 | GUI-20 层 B 资产供给（dev-signed 不放行）→ Developer ID 复验 v1 后 | FINDINGS :613 + TODO.md:27 + VALIDATION 注记 | beta 环境 blocker（非代码缺陷）→ deferred + human |
| 6 | Manual-Only 挂账：tap 手感 / pore 目检 / instance 浮层真机（数据腿全钉；已闭环 2 行 = 层 A 真机 + 层 B 三态 UI） | 07-VALIDATION Manual-Only 表 + FINDINGS 07-3 + TODO.md:28 | 人工挂账（L011 口径）→ human_verification |
| 7 | 设备 pin beta 现实（CPU 不在 supported 集 / 层 B pin 崩）→ typed 拒绝守卫 + gpuPinned/default 探针 | D-07-1-T1-2 + AIMaskService.swift:39-61/441-464 | beta 现实应对（typed error 防 trap） |

### 反模式扫描

`LightamerCore/Sources/AI/` + `LightamerIOP/Sources/SkinSmooth/` + App 层六个新 UI/State 文件全量扫描：无 TBD/FIXME/XXX/HACK/PLACEHOLDER/coming soon/not yet implemented/空实现/`return null`/console-only 路径。后置项在代码中以 typed error + 头注显式声明（`scribbleNotSupported` throw、Variant enum v2 保留注释、scaledMask 升级缝 UNUSED 注记），非静默 stub。唯一注意点 = 「GUI-21 filed」提交信息与登记记录不符（见 gap#1，属流程纪律非代码反模式）。

### Requirements Coverage

REQUIREMENTS.md：AI-01/05/06/07 复选框全勾（:146-152）+ 映射表（:347-350）4 行全 Delivered + 3 条口径注记（AI-06 raster / AI-01 scribble 后置 / 层 B 下载例外 D-07-CONTEXT-1）——与代码库状态一致，无 orphaned 需求（Phase 7 映射 :416 = 4/4）。REQUIREMENTS.md 尾注（:434）已记 Phase 7 签核。Phase 8 移交清单六面落 07-DISCUSSION-LOG（RasterMaskRef / 层栈 API 面 / 缓存面零新类 / skinSmooth 66.5 槽位 / AIMaskService 复用面 / Vision 推理基建）。

## 结论

**GOAL ACHIEVED-WITH-GAPS（小额可补做，不阻塞 Phase 8 开工的架构面）→ GSD status `human_needed`。**

4/4 需求在代码库交付且接线：AI-01 双层主体蒙版（层 A 离线标签合成腿 + 层 B 资产门控 tap 精修 + 三态 UI 全走查）+ AI-05 skinSmooth 66.5 非 dt 首例（两频分离 + raised-cosine 防塑料衰减 + float64 parity <1e-5 + SkinRegionLocator 纯 Swift 几何）+ AI-06 唯一 bake 通道（生成即 Phase 6 普通 raster 蒙版，⌘Z 恰 1，sidecar 零升级）+ AI-07 五条覆盖路径内容级 E2E；SC#1-5 按修订口径全 PASS（SC#5 warm 裁定 15-126ms ≪1s）。独立抽查实跑 5 套件 49 tests / 2 skip / 0 fail（含真实 Vision 推理逐字节确定性门），与签核轮 845/6skip/0fail 一致；真机 GUI 轮 ΔR 量化（10.31%/8.97%）闭环 L021 红线。

剩余工作分三档：**① 须补做（2 项）**——GUI-21 正式登记 + 复现归因 + 全局链腿内容级测试；'L00h' 格式臂回归单测。**② 人工验证（4 项）**——tap 手感 / pore 目检 / instance 浮层（均待样张或 GUI-20 解除）/ GUI-21 真鼠标复现。**③ v1 后观察项（5 项 deferred）**——全部有用户裁决或正式登记（scribble/parametric 预设/多频变体/scaledMask 升级缝/GUI-20 Developer ID 复验）。人工补验 + 2 项小额补做完即可关账。

---

_Verified: 2026-09-24T18:48:21+08:00_
_Verifier: Claude (gsd-verifier, goal-backward 阶段级)_

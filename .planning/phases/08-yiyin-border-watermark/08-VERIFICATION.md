---
phase: 08-yiyin-border-watermark
verified: 2026-09-25T12:35:08+08:00
status: human_needed
score: 8/8 must-haves verified（YIYIN-01..08 全部在代码库交付、注册接线且内容级测试覆盖；SC#1-5 按拆解口径全绿，SC#5 带 D-08-CONTEXT-7 范围注记）
behavior_unverified: 0
overrides_applied: 0
overrides: []
re_verification:
  previous_status: none
  previous_score: none
  gaps_closed: []
  gaps_remaining: []
  regressions: []
gaps:
  - truth: "CIContextPool memo 键尺寸维度修复（39dd005，GUI-22 复验 note-1）无专用回归测试 + GUI-22 根因未沉淀 LESSONS"
    status: partial
    reason: "Phase 8 执行窗口内的共享层修复：MemoKey.content 原只含内容指纹，全幅（FULL）与 longEdge（PREVIEW/THUMBNAIL）腿同键互踩、交替请求过 hit 后尺寸检查当 miss、重执行 CIRAW（39dd005 提交正文自述）。修复在位（CIContextPool.swift:77-81 尺寸入键 + 三构造点同步），但全仓无任何测试构造 full↔longEdge 交替场景钉住该维度——GUI22UndoWarmColdTests 常驻字节门只走单一路径；同族回归（键维度再收敛）将由 GUI-23 类真机观察才暴露。另：GUI-22 根因（CIRAW 输入平面逐次渲染非字节稳定 × 预算驱逐变体重嵌 → 渲染一次冻结 memo）属可跨阶段迁移的新坑，TODO.md:212 有详录、测试头注有详录，但 LESSONS.md 零新增（Phase 8 期间 L025 后无续条）——按 AGENTS.md §3.1「LESSONS 不欠账」口径属落账缺口"
    artifacts:
      - path: "LightamerCore/Sources/Metal/CIContextPool.swift"
        issue: "MemoKey 尺寸维度（:77-91）无专用单测——全↔longEdge 交替无碰撞断言"
      - path: "LESSONS.md"
        issue: "GUI-22 家族（CIRAW 非字节稳定 + memo 冻结 + 键维度）未落 LESSONS（L025 后无续条）"
    missing:
      - "补 1 条 memo 键尺寸维度单测：同一 imageID 构造 full-extent 与 longEdge 两个 MemoKey → 断言键不等、交替取回各自平面（可纯键级断言，无需真 CIRAW）"
      - "LESSONS.md 补 1 条：CIRAW 输入平面非字节稳定 → CIContextPool 渲染一次冻结 memo；memo 键必须携带全部请求维度（尺寸教训）"
deferred:
  - truth: "YIYIN-08 物理应用（resize + kCGImagePropertyDPIWidth/Height 写入）与导出管线消费点"
    addressed_in: "Phase 11（EXP-03 / EXP-05）"
    evidence: "D-08-CONTEXT-7 用户裁决：本 Phase 交付配置模型 + 纯 targetSize 数学 + 版式分辨率无关验证（物理应用 Phase 11）；ROADMAP §Phase 11 Notes（:193）「EXP-05 applies the yiyin border/watermark」消费面在案；接口面已就位（YiyinExportSettings.swift:82-108 纯数学、YiyinExportSettingsTests 5/5）"
  - truth: "YIYIN-03/04 完整旋转/自由拖拽（v1 深度 = 行内偏移 + 九宫格锚点 + Logo 透明度）"
    addressed_in: "v2"
    evidence: "D-08-CONTEXT-2 用户裁决 + REQUIREMENTS YIYIN-03/04 行 v1 口径注记；`rotation?` 参数位预留（YiyinTemplate.swift:120-142，Codable 前向兼容头注在案）"
  - truth: "zoom ROI 窗口化 run 下联合布局 band 预留（尺寸卫兵优雅降级 = 本地空 rows 布局）"
    addressed_in: "观察项 → v2（zoom 预览候选）；Phase 11 导出不受影响（恒全帧）"
    evidence: "D-08-3-T3-2 在案；代码卫兵 BordersModule.swift:224-231（sourceImageSize 不匹配即弃 override 走本地布局）；PREVIEW/FULL 全帧 run 精确（GUI ΔR 实证）"
  - truth: "模糊背景腿 Release 性能复测（Debug 极值在案：模块腿 ~7.3s @5.4Mpx 画布、√N 21-pass 分解）"
    addressed_in: "Phase 11（导出腿复测）"
    evidence: "08-VALIDATION 遗留#5 + .work/08/perf.md（只记不设门——ROADMAP §Phase 10 无性能 SC）+ D-08-1-8（√N 分解决策）"
  - truth: "LAYER-04 编组（层文件夹）类比义务"
    addressed_in: "v2（Phase 6 挂账，非本 Phase 缺口）"
    evidence: "REQUIREMENTS.md:109 LAYER-04 已于 Phase 6 交付并注记「编组 = v2（D-06-CONTEXT-6）」；Phase 8 对位义务仅为层内纪律——testLayerInternalDisciplinePin（YiyinBordersTests.swift:567）钉住 borders 永不入层腿"
  - truth: "HDR 创意文字水印不占 77.0 槽位"
    addressed_in: "届时阶段（用户口径 Phase 12）另定新 opName/新槽位"
    evidence: "D-08-CONTEXT-1 用户裁决（动工前落定，执行期不重开）；77.0 = yiyin 终局水印已裁决并实现"
behavior_unverified_items: []
human_verification:
  - test: "字体下拉手感真机走查（系统+用户双源 Picker 滚动、字体切换即时生效）"
    expected: "下拉流畅、切换字体后水印行即时重排（D-H1 恰 1 commit 背书下无卡顿感）"
    why_human: "交互手感不可量化（L011 口径）；数据腿已钉（YiyinFontStoreTests 9/9 + PanelWiring testYiyinPanelDispatch）"
  - test: "Logo 视觉终审（band 内 SONY logo PDF 锐度、字号观感、透明度滑杆手感）"
    expected: "Logo 在实机 band 内清晰、位置正确（GUI 轮初观可读——ΔR band 墨迹 18.76% 实证），透明度 0-1 滑杆线性生效"
    why_human: "视觉观感判据；渲染腿已钉（testEmbeddedBrandLogoRendersThroughPipe + testLogoOpacityBakesIntoAlpha + 26/26 PDF 转换目检）"
  - test: "暗背景自适应蒙层观感定标（四档切换的自然度，D-08-CONTEXT-6 容差带）"
    expected: "四档蒙层在暗背景样张上过渡自然、无突变感"
    why_human: "观感定标判据；数值腿已钉（testOverlayTierBoundaries 四档边界表驱动 + testAdaptiveOverlayLightensDarkBackdrop 增亮预测命中）"
  - test: "超长文本溢出行为真机构造（超长模板行，yiyin 同款单行直排溢出语义）"
    expected: "溢出行为与 yiyin 一致（不崩、按单行语义直排）"
    why_human: "yiyin 正本自认 TODO 语义（源码头注在案）；本 Phase 未构造超长样张——Manual-Only 表登记"
  - test: "blur 背景腿真机观感（暗绿模糊 + 蒙层；Debug 首渲延迟主观可接受度）"
    expected: "模糊背景观感自然（GUI 轮 ΔR 27.79% 实证渲染正确）；Debug 首渲延迟在可接受范围（Release 极值待 Phase 11 复测）"
    why_human: "观感判据 + Debug/Release 性能分离；数值腿已钉（DC 增益=1 + 平场 + σ 定标式 D-08-1-8）"
---

# Phase 8: yiyin Border/Watermark Panel — 阶段目标级验证报告

**Phase Goal（ROADMAP §Phase 10，执行序 08）:** Port the yiyin (壹印) border/watermark capability to a first-class native panel, implemented as two terminal iop modules (borders at order 76, watermark at order 77, matching Darktable) plus a SwiftUI panel. Feature parity with the standalone yiyin project; layout algorithm, EXIF extraction, font management, and model-map normalization ported from Electron/Svelte/sharp to Swift/Core Image/Core Text.

**Verified:** 2026-09-25T12:35:08+08:00
**Status:** human_needed（自动化层全绿、无 MISSING/STUB/NOT_WIRED；1 项小额补强 gap + 6 项计划内 deferred 挂账 + 5 项 Manual-Only 人工验证）
**Re-verification:** No — 初始验证（阶段目标级，非 plan 级复验）

## Goal Achievement

### 验证方法

从 ROADMAP §Phase 10（执行序 08，两套编号按 08-CONTEXT.md 口径分开引用）的 GOAL + 8 条需求（YIYIN-01..08，含 D-08-CONTEXT-2 v1 深度口径 / D-08-CONTEXT-7 YIYIN-08 像素域拆解）反向推导 must-have，逐条在**代码库**找承载实现（两终端 iop 模块/布局器/EXIF 层/资产系统/面板/接线），核内容级测试覆盖（抽查测试体确认真比较循环 + 防空转门，非恒真），并独立实跑 Phase 8 全部 9 个相关测试套件。SUMMARY 自述不作为唯一证据。证据来源：

1. **iop 面**：`LightamerIOP/Sources/Yiyin/` 九件 3,520 行——BordersModule.swift（838 行：全参数面 + effectiveLayout 尺寸卫兵 :224-231 + isIdentityRender 记录级真值）+ WatermarkModule.swift（485 行：模板消费 + makeJointLayoutRecord 公共面 + captureExif/logo 注入缝）+ YiyinLayout.swift（float64 七步直译）+ YiyinTemplate.swift（引擎三门/交错/rotation 预留位）+ YiyinTextRenderer.swift（CoreText 行渲染 + 排版缓存）+ YiyinLogoStore.swift / YiyinFontStore.swift（双通道资产）+ YiyinColor.swift（display 域换算）+ YiyinKernels.metal（217 行：composite/shadowSDF/boxDownsample/row 四核）。
2. **注册/槽位面**：V50Order.swift:171-172（borders 76.0 / watermark 77.0 现表槽位，零插行）+ Registry.swift:231-241（注册）/ :350-357（kernel prewarm）/ :456-468（ENABLED-neutral 种子）+ LayerCompositeDriver.swift:110/115-121/209（终端段尾窗 iopOrder ≥ 70.0——本 Phase 唯一管线改动）。
3. **EXIF 面**：YiyinExifFormat.swift（458 行，15 字段 + 品牌归一化）+ CaptureMetadata.swift 六 additive optional 字段 + RAWDecoder ImageIO walk 增读。
4. **UI/接线面**：YiyinPanelView.swift（745 行：borders/watermark/templates 三节全参数面，25 处 accessibilityIdentifier，`yiyin.panel`:91 + `yiyin.template.row.<key>`:471 稳定 id）+ InspectorState.swift:110/115（双 provider 注册）+ PipeCoordinator.swift:831（instanceRecord）/ :1379,1432-1469（injectYiyinRunContext 生产联合上下文——captureExif :1456 + jointLayoutOverride :1469）+ IOPPanelProvider.swift:144（sibling lookup 双实例联动）。
5. **测试面**：8 个 yiyin 测试文件 3,095 行 + PanelWiringTests 7 条 yiyin 扩展；本验证独立实跑 9 套件 **183 tests / 0 skip / 0 fail**（见下）+ 测试体内容级抽查。
6. **GUI 红线**：FINDINGS.md「Plan 08-3 T5 GUI 验收轮」（:726-743，真机 DSC00012.ARW 全程 AX 语义操作 + ΔR 量化 31.15%/26.29%/18.76%/27.79% + 双级撤销 1.70%/1.65% + SONY α 7rm5 品牌链实证）。
7. **签核面**：08-VALIDATION.md（SC#1-5 对照 5/5 + Per-Task Map 08-1/2/3 全任务 + Manual-Only 汇总）+ REQUIREMENTS.md YIYIN-01..08 翻账 Delivered ×8（:171-178，v1 口径注记在案）+ input/golden/manifest.md yiyin 两节（:851 borders 参考节 / :877 watermark golden 自基线节）+ README.md 商标归属表（:17-38）+ .work/08/perf.md。

### 独立实跑记录（抽查——Phase 8 全部 yiyin 套件 + 面板接线）

命令 `caffeinate -dis Scripts/test-direct.sh '<Class>'`（直启宿主，L019b 口径；2026-09-25 本验证执行，测试产物 = 09-25 11:43 终轮构建）：

| 测试类 | 覆盖 | 结果 |
|---|---|---|
| YiyinLayoutTests | yiyin node harness 13 case 逐值（整数精确/浮点 <1e-6）+ ceil-quirk 58×7→59 纯函数钉 + rows 预留语义 | 3/0fail（0.001s） |
| YiyinExifFormatTests | 15 字段表驱动 + 品牌 α/ℤ/罗马/charToNumberChar 逐码点 + formatDate 规则 + 旧档六键兼容 | 23/0fail（0.002s） |
| YiyinExportSettingsTests | 校验边界 + targetSize 永不放大 + 正交性 + 归一化布局 20+ 字段分辨率无关 + 预设渲染 byte-equal | 5/0fail（0.050s） |
| YiyinWatermarkTests | 模板引擎矩阵 + rows 手算 + 九宫格锚点 + golden 自基线 ×2（逐字节 diff==0）+ 缓存记账 + logo 透明度 | 36/0fail（2.04s） |
| YiyinFontStoreTests | 13 品牌内嵌集 + 用户 logo typed 四错 + 字体导入/注册/删除 + 损坏注册表自愈 | 9/0fail（0.046s） |
| YiyinBordersTests | 31 测试（种子恒等逐字节/尾窗路由/tail 政策/平场门/窗口化 ROI 内容级/SDF 剖面/投影单调/模糊 DC 增益=1/蒙层四档/orientation=6） | 31/0fail（3.06s） |
| YiyinMetadataWalkTests | 真实 CR3/NEF/ARW 六字段 vs 独立 ImageIO 读逐一对照 + 旧档解码 + orientation=6 端到端 byte-exact | 3/0fail（0.55s） |
| YiyinE2ETests | 开图→配印框→配水印→⌘Z 逐级每步 byte-exact + sidecar 跨重启活体 + 4 态矩阵 | 2/0fail（3.05s） |
| PanelWiringTests | 71 测试含 7 条 yiyin（dispatch/滑块恰 1 commit+undo/离散 toggle·delete/双实例交错/目录 smoke） | 71/0fail（18.3s） |

**合计 183 tests / 0 skip / 0 fail**（与签核轮 973/6skip/0fail 一致；GoldenColor 既有 flake 本轮未触发——02-04 台账隔离判定未启用）。

### 逐需求判定表

| 需求 | 代码证据（file:line） | 测试证据 | 判定 |
|---|---|---|---|
| **YIYIN-01** 白边/印框生成（边距、比例、颜色、按原比例扩展、竖转横） | `BordersModule.swift`（全参数面：solid/blur 背景、width rate、min margin、aspect 7 预设、landscape 竖转横、radius/shadow 上限 50、adaptiveBackdrop）+ `YiyinLayout.swift`（float64 七步直译，yiyin `:543-545` 末行膨胀 quirk 保留）+ `YiyinColor.swift`（sRGB hex → 线性 → Rec2020 → P3/sRGB display 域）+ 注册 V50Order.swift:171 + Registry.swift:231/352-354 + 终端段尾窗 LayerCompositeDriver.swift:110 | YiyinLayoutTests 13 case 逐值断言（参考 JSON `.work/plans/08-01/yiyin-layout-reference.json` + `Scripts/yiyin-ref-harness.mjs` 正本仓量测对照 + sharp bbox 探针精确命中）；YiyinBordersTests 31/31 实跑（平场白底取样精确 :405 / **窗口化画布扩展内容级** :500-557——32×24 窗 @ (10,8) → 64×48、band==填充、主图==基线映射逐值 / SDF 剖面 :598 / 投影单调 :638 / orientation=6 :972）；GUI ΔR 31.15%（FINDINGS :737） | ✓ VERIFIED |
| **YIYIN-02** EXIF 叠加（相机/镜头/焦距/光圈/快门/ISO/时间，可配置字段与格式） | `YiyinExifFormat.swift`（15 字段 + 快门分数/档位字母/测光中文 + exiftool 表 verbatim + formatDate 引擎）+ `CaptureMetadata.swift` 六 additive optional 字段 + `RAWDecoder.swift` ImageIO walk 增读 + `YiyinTemplate.swift` 引擎（matchFields/show·use·forceUse 三门/交错 segment）+ Logo 明暗 auto 分派（WatermarkModule.swift:309-312 logoExists 门） | YiyinExifFormatTests 23/23 实跑（表驱动 + `testFieldsFillAllFifteenKeys`:151 + 旧档兼容 :234）；YiyinMetadataWalkTests 3/3 实跑（**CR3/NEF/ARW 真实样张六字段与独立 ImageIO 读逐一对照** :27-128）；模板引擎矩阵（testForceUseOverrideAndEmptyValueFallback:326 等）；GUI 真机 SONY α 7rm5 EXIF 行渲染（FINDINGS :739，ΔR 26.29%） | ✓ VERIFIED |
| **YIYIN-03** 日期文字（可配置字体/大小/颜色/位置/旋转）——v1 口径 D-08-CONTEXT-2 | 行内语义 = 模板行堆叠 + `textBottomOffset`（YiyinLayout textBottomOffsetPx :44-47 派生）+ **九宫格锚点**（applyAnchor，bottomCenter 恒等 yiyin 语义）+ 行色矩阵（YiyinColor.swift）+ 字体大小 %（YiyinTemplate fontPx）+ `rotation?` 预留位（YiyinTemplate.swift:120-142，Codable 前向兼容头注） | testNineGridAnchorTranslatesBlock:570（锚点平移）+ testStackingOrderLastRowNearestBottom:486（行堆叠序）+ testRowLayoutFormulaSameShape:616 / testRowHeightDrivenByMaxSlotFont:647（行高公式交叉）+ golden text-row 自基线逐字节（testGoldenTextRowSelfBaseline:927 实跑绿）；GUI 真机水印行渲染 | ✓ VERIFIED（完整旋转 = D-08-CONTEXT-2 v2 → deferred，参数位已预留） |
| **YIYIN-04** Logo 水印（PNG/透明图，可配置位置/大小/透明度）——v1 口径 | `YiyinLogoStore.swift`（273 行：内嵌 13 品牌 × 明暗 26 PDF + 用户上传 name+StableHash 注册表 + 损坏 typed 降级）+ `LightamerIOP/Resources/Logos/*.pdf` 26 件实物在库 + CG PDF 矢量渲染 + 九宫格锚点 + `logoOpacity` 参数（kernel alpha 链） | testEmbeddedBrandSetResolvesAllThirteen:27 + testUserLogoImportRoundTripAndTypedFailures:62（typed 四错）+ testUserLogoRegistryPersistsAcrossStoreInstances:99 + **testEmbeddedBrandLogoRendersThroughPipe:999**（真品牌 PDF 过管线）+ testLogoOpacityBakesIntoAlpha:756（透明度入 alpha）+ 26/26 PDF 转换目检（`Scripts/yiyin-logo-convert`）；GUI band 墨迹 ΔR 18.76%（FINDINGS :740） | ✓ VERIFIED（大小/位置 = 行高推导 + 锚点，v1 口径注记在案 REQUIREMENTS:174） |
| **YIYIN-05** 自定义字体管理（.ttf/.otf 上传、仅本地不联网） | `YiyinFontStore.swift`（175 行：系统族枚举 + CGFont 校验导入 + 会话注册 + 启动重扫自愈 + 删除）+ **零联网实证**：Yiyin 源码面 grep URLSession/dataTask/Network 零命中 | YiyinFontStoreTests 9/9 实跑（testFontImportRegisterRemoveRoundTrip:148 + testFontRegistryPersistsAcrossInstances:187 + **testCorruptRegistryEntrySelfHeals**:199 + typed 错误面）；面板字体 Picker 双源（YiyinPanelView watermarkSection） | ✓ VERIFIED |
| **YIYIN-06** Make/Model 品牌归一化（Sony ILCE→α、Nikon Z→ℤ，model-map 移植） | `YiyinExifFormat.swift` 品牌分派（CORPORATION 剥离 + 首字母大写 + sonyModel + nikonModel + toRoman + charToNumberChar 0x1D63C 段保留——D-08-CONTEXT-8）+ D-08-2-2 定性 model-map.ts 为 yiyin 死代码面（归一化走 exif-format 活跃路径） | testMakeStripsCorporationAndCapitalizes:265 + **testSonyAlphaSubstitution:276**（ILCE-7M4→α 7m4 / ILCE-7RM5→α 7rm5 表向量 verbatim）+ **testNikonZAndRomanNumerals:288**（Z_6_II→" ℤ 6 II" + 引擎 slot trim）+ testCharToNumberCharPerCodePoint:338（52 码点逐点）+ testModelMapFilterSurfaceParity:366；**真机实证**：DSC00012.ARW（ILCE-7RM5）→「SONY α 7rm5」logo PDF + 归一化文本（FINDINGS :740） | ✓ VERIFIED |
| **YIYIN-07** 文字模板系统（预设模板 + 用户自定义模板字符串） | `YiyinTemplate.swift`（引擎：matchFields 首现去重/slot trim/{---} 交错 segment-先于-slot/跳行规则）+ 面板 templatesSection（YiyinPanelView.swift:447-471，3 系统模板 + CRUD + `{Field}` 插入器 + `yiyin.template.row.<key>` 稳定 id——L010） | testMatchFieldsOrderDedupAndCase:255 + testResolveInterleaveAndSlotTrim:285 + testHiddenFieldPlaceholderRemovedAndRowSkips:397 + PanelWiring **testYiyinTemplateToggleAndDeleteCommitDiscretely:2094** + testYiyinCatalogSmoke:2130（37+28 键 zh+en 双面） | ✓ VERIFIED |
| **YIYIN-08** 输出尺寸/分辨率配置（DPI、长边/短边像素、保留原尺寸）——D-08-CONTEXT-7 拆解 | `YiyinExportSettings.swift`（109 行：mode 三态 :23-34 + DPI :41 + validate 边界 1...100_000px/1...2400dpi :60-80 + **纯 targetSize 数学永不放大** :87-108）+ AppError.invalidParameter additive + 与水印参数正交（不触 paramsHash——EXP-07 多规格面）+ 预设接口面（paramsData 捕获/应用零新 API） | YiyinExportSettingsTests 5/5 实跑（testValidationBoundaries:24 + testTargetSizePureMath:49 含永不放大断言 + testCodableRoundTripAndOrthogonality:83 + **testJointLayoutRecordResolutionIndependent:119**（PREVIEW 2560 vs 2× 全幅归一化 20+ 字段相等）+ testPresetCaptureApplyRendersByteEquivalent:208）；**物理应用 = Phase 11 EXP-03/EXP-05**（ROADMAP :193 消费面在案——D-08-CONTEXT-7 用户裁决非缺口） | ✓ VERIFIED（本 Phase 范围 = 配置模型 + 像素域；物理应用 → deferred Phase 11） |

### SC#1-5 判定（ROADMAP §Phase 10 契约，SC#5 按 D-08-CONTEXT-7 拆解口径）

| SC | 判据 | 代码/测试证据 | 独立实跑 | 判定 |
|---|---|---|---|---|
| **SC#1** | 印框 parity（边距/比例/颜色/比例扩展/竖转横）输出对齐 yiyin | YiyinLayout float64 直译 + node harness 13 case 逐值 + sharp 探针 + 全腿渲染（solid/圆角/投影/模糊/蒙层）+ COLOR-2 已知点 | YiyinLayoutTests 3（含 13 case）+ YiyinBordersTests 31 实跑绿；GUI ΔR 31.15% 真机 | ✓ PASS |
| **SC#2** | EXIF 叠加（可配置字段与格式）+ 日期文字 + logo 水印渲染正确 | YiyinExifFormat 15 字段 + decoder walk 真样张 + 模板引擎 + 九宫格锚点 + logo 双通道 | YiyinExifFormatTests 23 + YiyinMetadataWalkTests 3 + YiyinWatermarkTests 36 实跑绿；GUI SONY α 7rm5 实证 | ✓ PASS |
| **SC#3** | 自定义字体管理（本地、不联网、CoreText）+ 文字模板系统 | YiyinFontStore（导入/注册/自愈/typed 四错）+ 零联网 grep 实证 + 模板 CRUD 稳定 key 行 | YiyinFontStoreTests 9 + PanelWiringTests 71（含 yiyin 7 条）实跑绿 | ✓ PASS |
| **SC#4** | Make/Model 品牌归一化移植 | α/ℤ/罗马/charToNumberChar 全表驱动 + 真机 ILCE-7RM5→SONY α 7rm5 实证 | YiyinExifFormatTests 品牌组实跑绿 | ✓ PASS |
| **SC#5** | 输出尺寸/分辨率配置驱动预览与导出 | `YiyinExportSettings` 配置模型 + 纯 targetSize 数学 + 与水印参数正交 + 版式分辨率无关（PREVIEW vs 2× 全幅归一化相等）+ 预设 byte-equal；**「驱动导出」半边 = D-08-CONTEXT-7 裁决 Phase 11 EXP-03/EXP-05（接口面已就位）** | YiyinExportSettingsTests 5/5 实跑绿 | ✓ PASS（按拆解口径；物理应用 deferred Phase 11） |

### 内容级验证覆盖抽查（非恒真确认）

- `YiyinLayoutTests.swift:166-211`（harness 逐值）：13 参考案例（verbatim 数字自 2026-09-22 harness run）× 每例 6 整数精确 + 3 浮点 <1e-6 + rows 四元组逐值，`XCTAssertGreaterThan(compared, 0, "防空转")` + ≥8 case 计划门——真比较循环。
- `YiyinBordersTests.swift:500-557`（窗口化 ROI 内容级，L020/L021 红线）：baseline 窗平面 vs borders 态逐像素取样——画布 32→64 增长、band==填充 1.0、主图 frame 映射 `output(16+k,12+k)==baseline(k,k)` 四点逐通道 <1e-5，防空转门——**记账绿≠内容对的红线已闭环**。
- `YiyinWatermarkTests.swift:896-925`（golden 自基线）：渲染位图 → PNG → 与冻结金标逐字节 zip diff，`XCTAssertEqual(diff, 0)`——真循环非存在性检查；`LA_REGEN_YIYIN_GOLDEN=1` 重冻结名令 + skip 信息内嵌（manifest :877 节 + 系统依赖头注）。
- `YiyinMetadataWalkTests.swift:27-128`（真样张交叉）：CR3/NEF/ARW 各字段「ImageIO 有 → decoder 必填且相等 / 文件无 → 必须 nil（additive 面）」双向断言——六字段 walk 的正反两向都被钉住。

### 漂移检查（共享层计划外改动）

| 漂移 | 改动位置 | 回归钉住 | LESSONS/记录 | 判定 |
|---|---|---|---|---|
| LayerCompositeDriver 终端段尾窗 iopOrder ≥ 70.0（08-1 T1，`a709c9b`，唯一管线改动） | `LayerCompositeDriver.swift:110`（terminalTailFloor）+ :115-121（splitTerminal）+ :209 | **三测试钉**：testTailWindowExtraction:194 + testTailWindowRoutesBordersToTerminalSegmentWithLayers:210 + testTailPolicyGammaTopUnchanged:244（gamma 仍 top → .bgra8Unorm；borders/watermark 平面 float32 政策不回归）；colorin 28/skinSmooth 66.5 留 base 随全套回归 | 08-1-DECISIONS + plan 记录（计划内改动） | ✓ 可接受（钉住） |
| CIContextPool memo 键尺寸维度（`39dd005`，2026-09-25 01:15，GUI-22 复验 note-1——执行窗口内共享层修复） | `CIContextPool.swift:77-91`（MemoKey.content 加 (width,height)，full-extent/longEdge/sub-region 三构造点同步） | **间接钉**：GUI22UndoWarmColdTests 常驻字节门（暖==冷==首帧逐字节）只走单一路径；**无 full↔longEdge 交替碰撞专用测试** | TODO.md:212-213（GUI-22 闭环 + GUI-23 留观行内记 note-1 修复）+ 提交正文；**LESSONS.md 零新增** | ⚠️ **小额缺口（gap#1）**——修复在位但键维度回归不可审计防复发；LESSONS 落账欠账 |
| CaptureMetadata 六字段 additive（08-2 struct / 08-3 walk 两半落地） | `CaptureMetadata.swift`（六 optional 全 additive Codable）+ `RAWDecoder.swift` walk | **三测试钉**：testSixFieldsDecodableFromLegacyArchive:234（旧档兼容）+ testSixFieldsRoundTrip:249 + testLegacyRecordJSONWithoutSixKeysDecodesCleanly（YiyinMetadataWalkTests:131） | D-08-CONTEXT 继承定案 + 08-3-DECISIONS D-08-3-T2-1（LensMake 字典更正） | ✓ 可接受（钉住） |
| setParams 同步化沿革（Phase 5 GUI-10/13 存续） | `ModuleBox.swift:190-200`（sync 全 mutating + gui10-forensics 注释） | `PanelWiringTests.testEnableCommitRacingLiveTicksHundredRounds:897`（×100 交错）——本验证 PanelWiringTests 71/71 实跑绿（含该测试） | gui10-forensics 在档（Phase 5/6/7 验证已核，Phase 8 未重开） | ✓ 可接受（钉住） |
| yiyin_watermark_row kernel alpha 因子修正（08-3 T0，`49faec4`——08-2 验收必修） | `YiyinKernels.metal`（编码域 un-premultiply + 线性 coverage——旧版二次 EOTF 削瘦 AA 边缘） | testRowBitmapInk:681（注释已更正）+ golden 自基线 ×2 不受影响（D-08-3-T0-1）+ 全套 960→973 回归 | 08-3-DECISIONS D-08-3-T0-1 双向归因在案 | ✓ 可接受（钉住 + 决策落账） |

### Gap 清单

**须补做（1 项小额，测试/文档层面，见 frontmatter `gaps` 结构化条目）：**

1. **CIContextPool memo 键尺寸维度无专用回归测试 + GUI-22 根因未沉淀 LESSONS**——39dd005 修复在位（三构造点同步 + 提交正文详录），但键维度回归（full↔longEdge 交替碰撞）零测试覆盖，同族收敛将重演 GUI-23 类真机才暴露的路径；LESSONS.md 自 L025 后零新增，GUI-22 家族新坑（CIRAW 输入平面非字节稳定 × 预算驱逐 → 渲染一次冻结 memo；memo 键必须携带全部请求维度）按 AGENTS.md §3.1「LESSONS 不欠账」属落账缺口。补：1 条键级单测 + LESSONS 1 条。**不推翻任何需求判定。**

**可接受裁决/挂账（均有正式记录、非阻塞）：**

| # | 项 | 记录位置 | 性质 |
|---|---|---|---|
| 1 | YIYIN-08 物理应用/导出消费点 → Phase 11 EXP-03/EXP-05（配置模型 + 像素域本 Phase 交付） | D-08-CONTEXT-7 用户裁决 + ROADMAP :193 + YiyinExportSettings 接口面 | 规划期用户裁决 → deferred |
| 2 | YIYIN-03/04 完整旋转/自由拖拽 → v2（`rotation?` 位预留） | D-08-CONTEXT-2 + REQUIREMENTS:173-174 v1 口径注记 + YiyinTemplate.swift:120-142 | 规划期用户裁决 → deferred |
| 3 | zoom ROI band 预留缺失（尺寸卫兵优雅降级，导出恒全帧不受影响） | D-08-3-T3-2 + BordersModule.swift:224-231 卫兵代码 | 执行期决策 + 已登记降级 → 观察项 |
| 4 | blur Release 性能复测 → Phase 11 导出腿 | 08-VALIDATION 遗留#5 + .work/08/perf.md（只记不设门，ROADMAP 无性能 SC） | 范围外移交 → deferred |
| 5 | LAYER-04 编组类比 → Phase 6 v2 挂账（非本 Phase 义务；层内纪律 testLayerInternalDisciplinePin 钉住） | REQUIREMENTS.md:109 + D-06-CONTEXT-6 | 前期既有挂账 → 不适用本 Phase |
| 6 | HDR 文字水印槽位 → 届时另定新 opName/新槽位（77.0 = yiyin 终局水印已定） | D-08-CONTEXT-1 用户裁决 | 规划期用户裁决 → deferred |
| 7 | knownRegions/zh 编译疑虑 → **证伪**（zh.lproj 全 699 键编译在案，08-2 备注误报，零修复） | 08-3 T5 FINDINGS | 误报关闭 |

### 反模式扫描

`LightamerIOP/Sources/Yiyin/` 九件 + YiyinExifFormat/YiyinExportSettings/CaptureMetadata + App 层 YiyinPanelView + Scripts/yiyin-ref-harness.mjs 全量扫描：无 TBD/FIXME/XXX/HACK/PLACEHOLDER/coming soon/not yet implemented/空实现/console-only 路径。后置项在代码中以 typed error + 头注显式声明（`rotation?` v2 预留位头注、logoExists nil 降级注释、尺寸卫兵降级注释），非静默 stub。git 工作区干净（全计划产物已提交）。

### Requirements Coverage

REQUIREMENTS.md：YIYIN-01..08 复选框全勾（:171-178）+ 映射表（:365-372）8 行全 Delivered + 3 条口径注记（YIYIN-03/04 v1 深度 D-08-CONTEXT-2 / YIYIN-08 拆解 D-08-CONTEXT-7 / YIYIN-04 双通道 D-08-CONTEXT-5）——与代码库状态一致，无 orphaned 需求（Phase 8 映射 :365-372 = 8/8，REQUIREMENTS 无其他 ID 映射到本 Phase）。签名口径：VALIDATION `Status: validated`（材料齐备、终验走 verify-work）。

## 结论

**GOAL ACHIEVED（含 1 项小额测试/文档补强 + 5 项 Manual-Only 人工验证）→ GSD status `human_needed`。**

8/8 需求在代码库交付且接线：YIYIN-01 印框（borders 76.0 + YiyinLayout 13-case harness parity + 全腿内容级渲染测试）+ YIYIN-02 EXIF（15 字段格式化 + 真样张 decoder walk 交叉 + 模板引擎）+ YIYIN-03/04 文字/Logo 水印（v1 口径 = 九宫格锚点 + 行内偏移 + 透明度，rotation 位预留）+ YIYIN-05 字体管理（零联网 + typed 四错 + 自愈）+ YIYIN-06 品牌归一化（α/ℤ/罗马逐码点 + 真机 SONY α 7rm5 实证）+ YIYIN-07 模板系统（引擎三门 + CRUD 稳定 key）+ YIYIN-08 导出配置（独立值类型 + 永不放大纯数学 + 分辨率无关 + 正交；物理应用按 D-08-CONTEXT-7 → Phase 11）。SC#1-5 按拆解口径全 PASS。

独立抽查实跑 9 套件 **183 tests / 0 skip / 0 fail**（覆盖 Phase 8 全部 8 个 yiyin 测试类 + PanelWiring 接线面），与签核轮 973/6skip/0fail 一致；GUI 真机轮 ΔR 量化（31.15%/26.29%/18.76%/27.79% + 双级撤销 1.70%/1.65%）闭环 L021 红线；两终端模块落位 V50 现表槽位零插行，唯一管线改动（终端段尾窗）三测试钉住。

剩余工作分两档：**① 小额补强（1 项）**——memo 键尺寸维度单测 + GUI-22 家族 LESSONS 落账。**② 人工验证（5 项 Manual-Only）**——字体下拉手感 / Logo 视觉 / 蒙层观感定标 / 超长文本溢出 / blur 观感+Debug 延迟。人工补验 + 1 项补做完即可关账；Phase 11（EXP-03/EXP-05）按移交清单消费本 Phase 接口面。

---

_Verified: 2026-09-25T12:35:08+08:00_
_Verifier: Claude (gsd-verifier, goal-backward 阶段级)_

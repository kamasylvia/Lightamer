---
phase: 04-geometry-lens-detail-iops
verified: 2026-09-21T07:10:00+08:00
status: human_needed
score: 8/8 must-haves verified (SC#1-4 自动化证据全绿)
behavior_unverified: 0
re_verification:
  previous_status: none
  previous_score: none
  gaps_closed: []
  gaps_remaining: []
  regressions: []
gaps: []
deferred:
  - truth: "cacorrect（v50 5.0，Bayer raw 域横向 CA）/ cacorrectrgb（13.5）不在本 Phase 交付"
    addressed_in: "Phase 5（视 Bayer 访问方案再议）"
    evidence: "04-05-DECISIONS.md D-04-05-T0-0（Bayer 域不可移植 + lens TCA 已覆盖横向 CA）；Phase 4 需求清单（IOP-GEO-01..04/DETAIL-01..04）本就不含 cacorrect——defer 与 ROADMAP 语义一致"
  - truth: "PERF-5 全链重渲 33.42ms 未达 16.6ms 预算（Phase 3 36.23ms → Phase 4 全链 +9 中性模块≈零增量）"
    addressed_in: "Phase 5+（Lab 往返共享 Open#9 + dispatch 批合并）"
    evidence: "TODO.md PERF-5 行 + .work/04-07/perf-phase4.md；04-07 明确「只记录不设门」，SC#1-4 不含该预算"
  - truth: "toneequal/flip 同类 dscIn × scale 模式审计"
    addressed_in: "Phase 5"
    evidence: "04-06-SUMMARY 遗留节 + TODO「Phase 3 遗留/分配」行（L021 引用；当前均被恒等路径免疫，质量向）"
behavior_unverified_items: []
human_verification:
  - test: "crop overlay 手柄交互（拖角/旋转手柄→实时预览+暗膜+松手 history +1）"
    expected: "拖动中实时重渲染、三分/phi 网格可见、拖拽恰 1 history commit"
    why_human: "交互时序与手感；XCUITest 需解锁控制台（L011，Phase 1 起环境挂账）。自动化腿已覆盖：CropOverlayTests 拖拽=恰 1 commit + live-disabled + 比例锁短边贴合"
  - test: "crop 比例锁手感（3:2/16:9/original 选定后拖角）"
    expected: "矩形保持选定比例（短边贴合），original 以当前图幅比锁定"
    why_human: "锁定手感；几何腿已由 CropOverlayTests.testAspectLockKeepsShortSide 自动断言"
  - test: "镜头校正视觉（DSC00012/DSC09991 建筑直线）"
    expected: "distortionK1 ±0.1 拖动→边缘直线由弯变直、CA 紫边收敛；复位归零"
    why_human: "畸变还原需人眼直线判据；数值腿已由 LensParityTests 7/7（vignette 解析点检 + CA 方向断言）覆盖"
  - test: "detail 五模块视觉抽检（sharpen/bilat/soften/highpass/equalizer 单参激活）"
    expected: "sharpen 起颗粒无振铃、bilat 局部对比无 halo、soften 高光柔化、highpass 灰底浮雕、equalizer 细纹理增强；复位归零"
    why_human: "增强方向/强度人眼判据；方向/能量/parity 已由 22 个 parity 测试自动钉死"
  - test: "Vision 自动检测真机抽检（真实 RAW 地平线/矩形）"
    expected: "地平线 θ 与矩形角点在真实照片上可用"
    why_human: "合成探针已 4/4 绿（θ<0.2°/矩形<0.5%/符号钉死），真实照片泛化需人看；field notes 落 .work/04-03/vision-field-notes.md"
  - test: "990pt 窗三列布局复验（GUI-4 遗留）"
    expected: "小窗下视口仍为视觉主体（≥50%）"
    why_human: "1440pt 窗已量化达标（13.9%/54.1%/32.0%，FINDINGS.md）；990pt 因 macOS 持久化 split frames 本轮未复现，需人工开窗目验"
---

# Phase 4: Geometry, Lens & Detail iops — 阶段目标级验证报告

**Phase Goal（ROADMAP §Phase 4）:** Geometry（crop、rotate/perspective、lens correction、flip/orientation）+ detail（sharpen、local contrast、highpass/soften、equalizer）模块；端到端证明 ROI 协商（`modifyROIOut`/`modifyROIIn`）；覆盖日常工作流 table stakes。
**Verified:** 2026-09-21T07:10:00+08:00
**Status:** human_needed（自动化层全绿；6 项交互/视觉挂账待人工，均有正式记录、非阻塞）
**Re-verification:** No — 初始验证（阶段目标级，非 plan 级复验）

## Goal Achievement

### 验证方法

从 ROADMAP §Phase 4 的 GOAL + 8 条需求 + SC#1-4 反向推导 must-have，逐条在**代码库**找承载实现（模块类/kernel/注册/面板），核内容级测试覆盖（抽查测试体确认真循环非恒真），并独立实跑 4 个测试类抽查（31 tests / 0 fail，`TEST SUCCEEDED`，xcresult `Test-Lightamer-2026.09.21_06-58-24`）。SUMMARY 自述不作为唯一证据。

### 逐需求判定表

| 需求 | 代码证据（file:line） | 测试证据 | 判定 |
|---|---|---|---|
| **IOP-GEO-01** crop（比例锁定、旋转微调） | `LightamerIOP/Sources/Crop/CropModule.swift:144`（modifyROIOut 前向收缩，dt crop.c:522-533 直译）、`:168`（modifyROIIn，含 04-06 double-scale 修复注释）、`:198`（窗口 blit process）、`:131`（clamp 半区）；`Registry.swift:94`（v50 24.5）+ `:207`（seed 全帧中性）；比例锁 UI `App/.../CropPanelView.swift:32-41`（7 档 preset picker）+ `App/.../CropOverlayView.swift:95`（hitTest）/`:70`（短边贴合锁定） | `CropParityTests`（实比对循环，compared>0 + dark<0.9 反塌门）+ `CropOverlayTests`（拖拽=恰 1 commit、live-disabled+暗膜、`testAspectLockKeepsShortSide`）+ `ROINegotiationTests.testCropForwardShrinkDownstream`（273） | ✓ VERIFIED |
| **IOP-GEO-02** rotate/perspective（含自动检测） | `Ashift/AshiftModule.swift:233`（modifyROIOut AABB grow）/`:271`（modifyROIIn 有界）+ `Homography.swift`（DLT+fit）+ `VisionDetect.swift:35`（VNDetectHorizonRequest）/`:52`（VNDetectRectanglesRequest）；`Registry.swift:84`（v50 15.0）+ 面板 `AshiftPanelView.swift:48/:99`（auto-level/auto-detect 按钮） | `HomographyTests`（rot30 解析/DLT<1e-9/inv×fwd<1e-12）+ `AshiftParityTests` 7 用例（28 路 <1e-5、黑角 alpha `:227`、gamma 尾黑角 `:266`、中性逐字节 `:316`）+ `VisionDetectTests` 4/4 | ✓ VERIFIED（真机抽检挂账 human_verification#5） |
| **IOP-GEO-03** lens correction（畸变/横向 CA/渐晕，CIRAW 缺口 Metal 补 + lensfun 数据库） | `Lens/LensModule.swift:247`（forward）/`:261`（modifyROIIn，04-04 clamp 原点修复）+ `LensKernels.metal`（lens_manual_warp：径向 dc1-4+TCA+devignette 一 pass）+ `LensfunDB.swift`/`LensfunMatch.swift`（XMLParser+Hermite/IDW）+ `Registry.swift:79`（v50 13.0，cacorrectrgb 13.5 前注释对齐）+ `LensPanelView.swift:39-75`（三段：内嵌注记/手动滑块/Lensfun match）+ `App/.../LensfunDownloadService.swift`（下载失败降级）；(a) 内嵌直通 = 模块头+面板注记（防双补） | `LensParityTests` 7 用例（anti-vacuum compared>0 `:138`、k=0 逐字节恒等 `:187-203`、vignette 解析 `:209`、CA 方向 `:248`、`testUnifiedExitMatchesManual:277` 同 kernel 逐字节）+ `LensfunDBTests` 15/15（d-factor/Hermite/IDW 手算 + fixtures/lensfun 4 XML 实存）+ `ROINegotiationTests.testLensShrinkNegotiationBoundsInput`（483） | ✓ VERIFIED（镜头视觉挂账 human_verification#3） |
| **IOP-GEO-04** flip/orientation | `Flip/FlipModule.swift:203`（modifyROIOut）/`:216`（modifyROIIn，buf_out×scale 基准，dt flip.c:338-339）+ `FlipKernels.metal`（8 态索引 remap）；`Registry.swift:89`（v50 16.0，ashift<flip<crop 顺序注释） | `FlipParityTests` 8 用例（parity <1e-6 + CPU round-trip/GPU 8 态/ROI AABB 三方互锁）+ `V50OrderTests.testFlipBeforeCropOrderConstraint` | ✓ VERIFIED |
| **IOP-DETAIL-01** sharpen（USM 及变体） | `Sharpen/SharpenModule.swift:187`（forward 恒等）/`:194`（modifyROIIn 对称 halo 外扩，D-G5）/`:183`（中性谓词）+ `SharpenKernels.metal`（IIR Gaussian + 软阈值 mix）；`Registry.swift:111`（v50 35.0）+ `:218`（seed amount=0 中性） | `SharpenParityTests` 5 用例（合成 float64 参考 <1e-4、amount=0 逐字节、平场恒等、σ 链钉参）+ `ROINegotiationTests.testSharpenBackwardExpandsUpstream`（367，真模块 24+2·ceil(3·2.0)=36×36 ≪ 全图） | ✓ VERIFIED |
| **IOP-DETAIL-02** local contrast（clarity） | `LocalContrast/LocalContrastModule.swift:189`/:195（ROI 钩子）+ EIGF 腿复用 toneequal 核 + `Registry.swift:117`（v50 54.0，dt "bilat"）；TilingPlan FULL 第二消费者 | `LocalContrastTests` 6 用例（合成 EIGF 参考 <1e-4、detail=0 逐字节、台阶方向、分块一致 <1e-4） | ✓ VERIFIED |
| **IOP-DETAIL-03** highpass / soften | `Highpass/HighpassModule.swift:152`/:159 + `Soften/SoftenModule.swift:191`/:197（RGB 线性域 Orton）；`Registry.swift:105`（34.0）/:122（66.0），seed 双双 disabled（DECISIONS D11：无零参恒等） | `HighpassSoftenTests` 7 用例（双合成参考 <1e-4、soften 平场恒等、amount=0 逐字节、去饱和断言、半径链） | ✓ VERIFIED |
| **IOP-DETAIL-04** equalizer / detail enhancement | `Equalizer/EqualizerModule.swift:183`/:190（ROI 钩子）+ 高斯半倍频程金字塔 + `Registry.swift:100`（v50 27.0）+ `:223`（全零中性 seed） | `EqualizerParityTests` 4 用例（金字塔合成参考 <1e-4、全零逐字节、带能量内容断言）+ `V50OrderTests` 五槽位约束 | ✓ VERIFIED |

注：IOP-DETAIL-01 需求文字「高斯/拉普拉斯变体」——dt sharpen 本体即 Gaussian-USM（radius/amount/threshold，照 `sharpen.c:45-47` 直译交付）；Laplacian 型局部增强语义由 highpass（34.0，反相高通）与 local contrast（EIGF 分解）承载，为规划期签核决策（04-CONTEXT D-G3/D-G4：「highpass/soften = USM 变体」）。非缺口，判 ✓。

### SC#1-4 判定（ROADMAP 契约）

| SC | 判据 | 代码/测试证据 | 独立实跑 | 判定 |
|---|---|---|---|---|
| **SC#1** | crop 比例锁 + 旋转微调 + rotate/perspective（含 auto-detect）+ flip 全部 live preview 正确 | 比例锁 `CropOverlayTests.testAspectLockKeepsShortSide`；旋转/透视 `AshiftParityTests`（28 路 <1e-5）+ `HomographyTests`；auto-detect `VisionDetectTests` 4/4（θ<0.2°/矩形<0.5%/符号钉死）；flip `FlipParityTests` 8/8 + `V50OrderTests` flip<crop 硬约束；live 语义自动化腿 = 拖拽恰 1 commit + live-disabled+暗膜（`CropOverlayTests`） | 本轮实跑 GeometryGoldenTests 绿 | ✓（自动化腿全绿；拖拽手感/实时预览目验挂账 hv#1/#2——L011 口径，VALIDATION Manual-Only 表登记） |
| **SC#2** | lens 三层（内嵌 opcode + 手动滑块 + Metal warp + Lensfun 开放决策落地） | (a) 内嵌直通零代码+注记；(b)(c) 同一 kernel `testUnifiedExitMatchesManual`（≤1e-6）+ 降级路径（无数据→恒等+手动可用）；`LensParityTests` 7/7 + `LensfunDBTests` 15/15；XML-data-only 决策落地（04-DISCUSSION-LOG 04-04-T0 + LensfunDownloadService） | 本轮实跑 LensParityTests 绿 | ✓（镜头视觉挂账 hv#3） |
| **SC#3** | sharpen/local contrast/highpass/soften/equalizer 对 golden 参考渲染 | 四套 parity 22 用例，合成 float64 参考（L017），anti-vacuum compared>0 门 + 恒等/方向门；manifest「Phase 4 golden 完整性总账」9/9 有账（`input/golden/manifest.md:741`） | 本轮实跑 GeometryGoldenTests（track A <1e-6 + track B 2/2）绿 | ✓（视觉抽检挂账 hv#4） |
| **SC#4** | ROI 协商端到端：crop 前向收缩 + sharpen 后向扩展最小区域处理 | `ROINegotiationTests.testCropForwardShrinkDownstream`（273：终帧 32×32、crop roiIn=(16,16,32,32)、记账 3×窗口）+ `testSharpenBackwardExpandsUpstream`（367：真模块 36×36≪全图 + 记账双断言）+ `testDisabledCropPassesThrough` + `testCropDragKeepsOldKeys`（回拖全命中）；`PipeCacheKey.roi` 首次实际生效 | **本轮独立实跑 11/11 绿（0.081s）** | ✓ VERIFIED（状态转换有通过测试钉住，非仅符号在场） |

### 内容级验证覆盖抽查（非恒真确认）

- `LensParityTests.swift:138`：`XCTAssertGreaterThan(compared, 0, "parity must compare real pixels (anti-vacuum)")` —— 24 路实比对循环。
- `CropParityTests.swift:269-276`：逐像素 compared 计数 + `dark/compared < 0.9` 反塌门（04-02 验收曾抓出该文件恒真空转并修复，现循环实在）。
- `ROINegotiationTests.swift:284-299`：SC#4 断言钉尺寸/次数/坐标三元组（misses==3、roiIn 精确坐标），且经 04-02 L020 教训后由 golden 内容级断言兜底。

### 漂移检查（计划外管线共享路径改动）

| 漂移 | 改动位置 | 回归钉住 | LESSONS | 判定 |
|---|---|---|---|---|
| 04-03 union-clamp | `PixelPipe.swift:688`（`roiIn.clamped(to: frameROI.union(roiOut))`）+ `ROI.swift:58`（union） | `ROINegotiationTests.testAshiftWarpAABBGrowsOutputAndBoundsInput`（441：下游见 87 宽——若 clamp 退回裸 frameROI 此测试即红）+ `AshiftParityTests.testModifyROIOutGrowsAABBOnRotation:336`/`testModifyROIInStaysBounded:355` | L020（dt ROI 公式坐标系前提 + 内容级断言兜底）+ 04-03-SUMMARY 排障 #1 | ✓ 可接受（有回归、有记录） |
| 04-06 crop modifyROIIn double-scale | `CropModule.swift:168-185`（clamp 界直用 dscIn，注释钉死坐标系） | `CropParityTests.testScaledFullFrameCropMatchesTrioOnly`（238：trio+crop 逐字节 == trio-only，pre-fix 红）+ `CropOverlayTests.testFitQuadMatchesFittedRect` | L021（dscIn 本 run 像素禁再 ×scale + 显示腿 GUI 验收强制） | ✓ 可接受（有回归、有记录） |

GUI 红线（AGENTS.md Phase 执行模型新增硬性项）：04-06 已执行真实 GUI 验收轮——Debug 产物 `open` + 真实 RAW（DSC00012.ARW）+ screencapture 像素量化（`.work/gui-acceptance/FINDINGS.md`：GUI-1 视口 <16 30.6%→13.7%、饱和 0→75480；GUI-2/3 无对角线、包络边距 ≤11px；GUI-4 视口 54.1% ≥50%），修复因果一致、逐项闭环。红线已满足。

### Gap 清单

**须补做：无。** 自动化层未发现 MISSING/STUB/NOT_WIRED/恒真测试/未钉回归的漂移。

**可接受挂账（6 项，均有正式记录、有 owner 口径、不阻塞核心目标）：**

| # | 挂账 | 记录位置 | 性质 |
|---|---|---|---|
| 1 | crop overlay 交互 3 行（拖拽手感/比例锁手感/实时预览目验） | 04-VALIDATION Manual-Only 表 + L011（XCUITest 需解锁控制台，Phase 1 起环境挂账） | 人工交互，自动化腿已覆盖语义 |
| 2 | Vision 真机抽检 | `.work/04-03/vision-field-notes.md` + VALIDATION 表 | 合成探针 4/4 已绿，真实照片泛化需人看 |
| 3 | 镜头校正视觉（建筑直线） | VALIDATION Manual-Only 表 row 3 | 人眼直线判据，数值腿已由 parity 覆盖 |
| 4 | detail 五模块视觉抽检 | VALIDATION Manual-Only 表 row 6 | 方向/能量/parity 已自动钉死 |
| 5 | 990pt 窗三列复验 | FINDINGS.md GUI-4 遗留 + 04-07 签核（1440pt 已量化达标） | macOS 持久化 split frames 环境因 |
| 6 | XCUITest 三栏断言（L011 授权） | TODO.md Phase 4 节 `- [ ]`（Phase 1 起跨阶段挂账，非 Phase 4 引入） | 环境阻塞（TCC/辅助功能权限） |

**Defer（有正式记录、ROADMAP 语义允许）：** cacorrect/cacorrectrgb（04-05-DECISIONS D-04-05-T0-0，Bayer 域不可移植 + lens TCA 覆盖，Phase 5 再议）；PERF-5 预算缺口（TODO + `.work/04-07/perf-phase4.md`，只记录不设门，Phase 5+ Open#9）；toneequal/flip 同类 dscIn×scale 审计（Phase 5，L021 引用）。

### 反模式扫描

9 模块 + Registry + 7 面板 + overlay 全量扫描：无 TBD/FIXME/XXX/HACK/PLACEHOLDER/空实现（唯一命中为 Registry.swift:5 文档注释中的 `XXXModule` 模式名占位，非债务标记）。GUIProbeTests 判别探针已按 L012 D-X2 退役（Tests/ 无 probe 文件），常驻回归只留合成图门。

### Anti-patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| REQUIREMENTS.md | 80-97, 316-328 | Phase 4（及 Phase 3）需求复选框未勾、映射表仍 "Pending" | ℹ️ Info | 项目级文档惯例（状态由 TODO.md/VALIDATION.md 承载，TODO Phase 4 节已更新为完成态）；非 Phase 4 引入的漂移，建议里程碑收口时统一回填 |

### Human Verification Required

见 frontmatter `human_verification` 6 项（交互手感 2 + 视觉判据 3 + 布局复验 1）。全部为「自动化已覆盖语义/数值，人只补手感与目验」性质。

## 结论

**GOAL ACHIEVED-WITH-GAPS → 判定 ACHIEVED（无阻塞缺口）。** 8/8 需求在代码库交付且注册（9 模块 v50 槽位全对齐 + seed），SC#1-4 自动化证据全绿（SC#4 本轮独立实跑 11/11），漂移改动均有回归钉住且 LESSONS 落账，GUI 红线验收闭环。剩余 6 项均为交互/视觉类人工挂账（L011 口径，有记录、非阻塞）→ GSD status `human_needed`：目标已达成，等待人工补验视觉/手感项即可关账。

---

_Verified: 2026-09-21T07:10:00+08:00_
_Verifier: Claude (gsd-verifier, goal-backward 阶段级)_

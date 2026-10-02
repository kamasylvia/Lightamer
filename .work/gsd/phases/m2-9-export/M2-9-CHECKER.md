# M2-9 Plan 集执行前质量门 — Checker 报告

**Checker:** goal-backward 审查（M2-2..M2-8 七期 checker 链第 8 期）
**Date:** 2026-10-02
**输入:** CONTEXT 裁决记录（OQ-1..12 全按推荐 + D-1..6）× 5 PLAN × RESEARCH-NOTES × ROADMAP M2-9 行 × REQUIREMENTS EXP2 族 × 11-export/m2-6-drt/m2-8-versions/13 交叉锚 × 源码实核
**实核方式:** 每条 plan 断言的代码事实亲核源文件（PixelPipe / ExportRenderer / ExportQueue / ExportChainBuilder / ExportEncoder / ImageIOEncoders / ExportNamer / ExportRecipe / YiyinExportSettings / HistoryStack / DrtRecord / CaptureMetadata / LayerCompositeDriver / InspectorState / ContentView / Project.swift / test-direct.sh / BUNDLE-MAP）

## 结论

# FAIL / 9 error + 2 minor

裁决记录 12 OQ 全部被 plan 集正确吸收（无重开、无自造默认值），依赖链/波次/封存面清单大框架成立；但 **4 处密封-消费自相矛盾**（均为「文件级零 diff 封存 vs 消费腿必须改该文件」型）、**2 处 front-matter 漏文件**、**1 处跨 plan 交接悬空**、**1 处密封冲突的 fallback 写法**、**1 处机检方式自相矛盾**——按七期 checker 口径，凡机检 AC 不可满足或自相矛盾 = error。修复代理按下列处方回注 plan 原文后可复审。

---

## Error（必修，修复处方 = checker-hint 原文回注）

### E1 [M2-9-03 / T2+T3 / KD-3] 元数据腿与 ICC OMIT 消费腿在其自封文件内不可实现

- **事实**（源码亲核）：
  - EXIF 字典装配发生在 `ImageIOEncoders.swift` **内部**——`ImageIOEncodeCore.readExif`（:73-80）与各 encoder 的 properties 组装（JPEG :117-123 / PNG :153+）都在该文件；「加工发生在字典进 destination 前」必然改它。
  - ICC embed = `makeCGImage(from:colorSpace:)`（`ImageIOEncoders.swift:32`），各 encoder :110/:135 传 `request.colorSpace`。**OMIT 走「CGImage 构造 colorspace nil 路径」技术不可行**：CGImage 位图构造传 nil colorspace 只对 image mask 合法，常规位图返回 nil → 现有 guard 直接 throw `encodeFailed`。untagged 产物无法经 nil-space 达成。
- **矛盾**：plan 03 纪律 2/AC6 封存 `ImageIOEncoders.swift`/`WebPEncoder.swift` 零 diff，而 T2（EXIF Software/GPS/serials 剥离/NONE 短路）与 T3（OMIT）都要求改它。
- **checker-hint（处方，两案择一，禁混用）**：
  - **案 A（推荐）——封存面重划**：`ImageIOEncoders.swift` 封存面收窄为「编码核心面」（makeCGImage 签名与 CGImageDestination 参数/质量映射/量化消费零 diff），**元数据装配腿允许 additive 改造**（统一经 `ImageIOEncodeCore` 单点新增 `processedProperties(for:request:)` 一类入口，五 encoder 只换调用点）；OMIT 放弃 nil-space 幻想，改为 **post-encode ICC 剥离步**（`ExportEncoder.swift` 内、mountXMP 同位次的新 outcome 面——JPEG 去 APP2 ICC_PROFILE marker / PNG 去 iCCP / TIFF 去 34675 tag，XMPContainerInjector 同族纯 Data 平面，HEIC/AVIF/WebP = OMIT 不可达档 typed 记录）。
  - **案 B**：解除 encoder 文件级封存，改「行为封存」——11-02 六格式 golden（ExportEncoderGoldenTests）+ XMPExportMatrixTests 全量零漂移为硬 AC，文件 diff 逐 hunk 审限元数据/ICC 面。AC6 改写为「编码核心行为零漂移（golden 机检）」。
  - 两案都必须同步改 AC6 的机检方式（现在的「四文件零 diff」按案 A/B 各自重写）。

### E2 [M2-9-03 / 已定裁决+纪律2+AC4 vs KD-3/风险节] 元数据政策默认档的内部自相矛盾（legacy 冻结承诺 vs OQ-6 默认剥离）

- **矛盾**：plan 03 一处写「legacy 面（模板 nil + **政策默认**）逐字节冻结——mountXMP 默认参数路径 outcome 与现行为逐值同」「既有 XMPExportMatrixTests **零修改全绿**」；另一处（KD-3/AC3/AC4/风险节）按 OQ-6 裁决把 `policy` 默认 = `.standard`（editingHistory=false → packet 默认不嵌）。**默认参数路径 outcome 按设计就变**——两段文本不可同真。XMPExportMatrixTests 直接断言 mountXMP 无参调用 outcome（:187/:200/:208），默认值一改这些断言必翻红，「零修改全绿」机械不可能。
- **checker-hint**：重写纪律 2 与 AC4 的措辞——legacy 冻结 = **代码路径/UI 面**（naming==nil 分支、encoder 调用形状）；元数据默认档 = OQ-6 用户裁决的**有意行为变更**，波及全部导出路径（含 legacy sheet 产物：packet 不嵌、GPS/serials 剥离）。把 XMPExportMatrixTests 从零修改封存清单**移出**，改列为「显式传参改造白名单」：既有矩阵逐 case 补 `editingHistory=true` 显式参以锚定原 packet 行为，另增默认档断言（packet 缺席）；改造前后 case 清单逐条入 DECISIONS。风险节的「回退方案 = 默认参数保持现行为」标注为**用户升级点**（OQ-6 是用户裁决，plan 不得以 DECISIONS 注记自行翻转），非执行方可自裁项。

### E3 [M2-9-03 / T3] peak 闸门落点文件缺 front-matter 登记

- **事实**：T3「校验落 `ExportVariant.validate` 扩展」——该函数在 `LightamerCore/Sources/Export/ExportRecipe.swift:70-74`；front-matter files_modified 无此文件。
- **矛盾**：纪律 6「git diff --stat 与 front-matter 逐文件核对，越界 = 违约」+ AC8 diff 边界断言会在执行时自爆。
- **checker-hint**：files_modified 增 `LightamerCore/Sources/Export/ExportRecipe.swift`（注记：仅 validate 扩展 additive + peak 闸门；ExportFormatSpec/ExportColorSpace 枚举体零 diff 延续 01 的封存口径）。

### E4 [M2-9-01 / KD-5#3 / AC9] ExportPanelView 编译性补臂文件缺 front-matter 登记

- **事实**（源码亲核）：`OutputMode` 加 case 后的编译期穷举 switch 影响面（production 代码全集）：①`YiyinExportSettings.validate` :61-74 ②`YiyinExportSettings.targetSize` :90-107 ③`ExportRecipe.derivedTag` :149-154（①②③均已在 files_modified 内的文件）④**`ExportPanelView.swift` :435-436**（mode→`ExportPanelViewSizingKind` 映射 switch，穷举）与 **:698-701**（`(SizingKind, OutputMode)` 二元组模式 switch，穷举）——两处都编译炸，必须补不可达臂。⑤`MCP/Tools/EditingToolset.swift:336` 为三元式构造，非 switch，不炸。
- **矛盾**：KD-5 第 3 条与 AC9 要求 ExportPanelView「仅编译性补臂、逐 hunk 机检」，但该文件不在 files_modified。
- **checker-hint**：files_modified 增 `App/Sources/Lightamer/Export/ExportPanelView.swift`（注记原文照抄 KD-5#3：仅补臂、legacy 面行为字节冻结、逐 hunk 机检）。KD-5#4 的「yiyin 面板消费面 grep」保留（实测 production 面 = 上列五处，grep 结果入 DECISIONS 即闭环）。

### E5 [M2-9-04 / KD-1 / 纪律3] InspectorState.swift 与 Localizable.xcstrings 缺 front-matter 登记

- **事实**：KD-1「`InspectorState` additive 页开关（exportPageActive）」落点 = `App/Sources/Lightamer/State/InspectorState.swift`（:22，实核存在）——不在 files_modified；纪律 3「zh/en 键随手落 `Resources/Localizable.xcstrings`」+ T4 AC8「diff 边界 == front-matter **+ .xcstrings**」自认会碰该文件——也不在 files_modified。
- **checker-hint**：files_modified 增 `App/Sources/Lightamer/State/InspectorState.swift`（additive 页开关）与 `Resources/Localizable.xcstrings`（zh/en 键）；AC8 措辞同步为「diff 边界 == front-matter」。

### E6 [M2-9-01 KD-1 → M2-9-02/03] 修正后 DPI 的 renderer 消费交接悬空（D-M2-9-CONTEXT-6 不闭环）

- **事实**：plan 01 KD-1 明写「M2-9-02 的 renderer 切换到 resolve 拿修正后 DPI」；plan 02 的任务集/AC **无任何** sizing/resolve/DPI 条目（其 renderer 改动纯 DRT 面）；plan 03 只接命名/元数据腿；plan 04 纯 App。结果：physical 模式 + cap 触发时，`StageOutput.dpi`（`ExportRenderer.swift:367` 现取 `effectiveSizing.dpi`）永远拿**未修正** DPI → `kCGImagePropertyDPIWidth` 写旧值 → 物理打印尺寸守恒（D-6 裁决、cpp:74-78 数学）在产物元数据上失效。M2EXP-01 缺一角。
- **checker-hint**：把「renderStage step 2 切 `resolveExportResolution`（拿修正后 dpi）+ `StageOutput.dpi = result.dpi`」登记为 **M2-9-03 T1 的显式第 3 步**（03 本就改 ExportRenderer，files_modified 无需扩）；配套 golden 一条：physical(如 3000×2000@300dpi) + cap 2000 → 产物 DPI 元数据 = 200。legacy 面字节零漂移论证写进 DECISIONS（legacy 三模式构造不出 physical/cap，resolve 对其输出与 targetSize 逐值同）。

### E7 [M2-9-02 / KD-2 括注] 「Built.target 类型如需扩 = additive 枚举臂」同时踩两条密封 AC

- **事实**：`Built.target: ExportColorSpace`（ExportChainBuilder.swift:52）；若给它加臂：①违反 plan 01 AC9「ExportColorSpace 枚举体零 diff」；②`exportChain` 体内 ：103-109 的 target 穷举 switch 必须补臂 → 违反 plan 02 自家 AC2「exportChain 函数体零 diff」。括注 fallback 一旦被执行方采纳即双爆。
- **checker-hint**：删除该括注，改为：`Built` 增**新可选载体字段**（如 `drtEncoding: (space: DrtEncodingSpace, eotf: DrtEotf)?`，或新建小枚举 `Built.ColorExit` 单独承载 DRT 派生）——`ExportColorSpace` 永不加臂；`target` 在 DRT 腿留 `.sRGB` 哑值并以新字段为准（DECISIONS 注记哑值语义）。

### E8 [M2-9-01 / T4 / AC6] 尾格式覆写缝漏算 LayerCompositeDriver 透传（「三处」计数错 + 文件缺登记）

- **事实**（源码亲核）：export 路遇 layerStack 非空走 `processComposite` → `LayerCompositeDriver.composite`（:204 收 `terminalTail`）→ **driver 内部自建 terminal pipe 并 `terminalPipe.terminalTail = terminalTail`（:545）**。覆写 flag 是 PixelPipe 实例属性，driver 造的 pipe 不经 RenderPipeline 静态入口——**不透传 driver，合成导出路径（分层文档 = M2 常态）尾平面仍是 bgra8/16F → exit 腿 float 读回破坏**。AC6「PixelPipe diff = 三处 additive」计数错；`LayerCompositeDriver.swift` 不在 files_modified。
- **checker-hint**：files_modified 增 `LightamerCore/Sources/Pipe/LayerCompositeDriver.swift`（additive 透传参数，默认 false，:204/:545 同 terminalTail 路径同构）；AC6 改「四处 additive（属性/consult/两入口透传/driver 透传）」；T3 测试补一条**合成 layerStack 导出 E2E 位深断言**（现在只有平面路径）。

### E9 [M2-9-01 / AC3] 「零修改全绿」的机检方式（git diff 零 hunk）对自家申报文件不可满足

- **事实**：AC3 机检列「`git diff` 零 hunk」针对 ExportRecipeTests/YiyinExportSettingsTests——但 front-matter 申报这两文件**修改（追加）**；ExportNamerTests 才是真零 diff。
- **checker-hint**：AC3 机检拆开写：ExportNamerTests = git diff 零 hunk + 全绿；ExportRecipeTests/YiyinExportSettingsTests = **既有测试方法零改动（append-only）** + 全绿（机检 = 既有测试方法名清单 diff 为空）。

---

## Minor（建议修，不阻执行）

### m1 [M2-9-01 / KD-2] OutputMode Codable 机制措辞不准

- 「enum additive（旧 rawValue 解码不破坏）」——`OutputMode` 是带关联值枚举，synthesized Codable 按 **case 名 keyed container** 编解码（非 rawValue）；结论（旧 payload 解码安全）仍成立。措辞改为「case 名 keyed 编解码 additive」；T1 的旧 JSON 字面锚测试保留（正确的可观测保障）。

### m2 [M2-9-02 read_first / M2-9-03 read_first] 行号锚漂移

- PixelPipe 实际 ：1590/:1642（写 1587/1631）、ExportRenderer.Request instancesOverride 实际 :93/:106（写 :100-104）、ExportRenderer step9 实际 :356-373 ✓、PipeCoordinator drtCarrier 实际 :595-604。符号名全对，仅行号漂移——各 plan read_first 处补一句「行号以符号检索为准」即可，防执行期误读。

---

## 七维审查通过面（免复审项，记录在案）

1. **12 OQ 生效值逐条落位**：OQ-1(A)→04 页挂载+legacy 冻结双向门；OQ-2(A)→01 原地扩（shortEdge/percent 保留）；OQ-3(B)→04 lastDirectory+首用回落；OQ-4(A)→01 全量语法+shutter `1-500` 修正；OQ-5(A)→01/03 三档默认 Increment（D-11-CONTEXT-4 扩档注记义务在 05）；OQ-6(A)→01 模型 7bool+03 消费+04 单开关；OQ-7(A)→02 强制联动+03 闸门+04 三元组只读行；OQ-8(A)→02 钳位+05 走查9；OQ-9(A)→01 仅命名预设；OQ-10(A)→04 四键；OQ-11(B)→03 行为+04 文案；OQ-12(A)→04 折叠区。D-1..6 全延续。无 plan 重开已裁决项（E2 的回退段已按升级点处置）。
2. **编译完整性（除 E4/E8 外）**：OutputMode 影响面全集 = 上列五处（01 覆盖 ①②③④，⑤不炸）；`.skippedByPolicy` 加臂——XMPMountOutcome production 消费仅 renderer 的 `if case .failed` 日志（非穷举 switch），零编译炸点；Core 单 target（LightamerCore 同 module）无跨模块可见性问题；App 源 glob（`App/Sources/**`）新源文件无需 Project.swift；测试 bundle 显式清单 + Project.swift/BUNDLE-MAP 双登记惯例齐。
3. **红线机检框架**：六格式编码器/ExportQuantizer/ExportQueueContract/ExportQueue 引擎体/exportChain 体封存清单与 files_modified 交集核验（除 E1/E8 外无冲突）；yiyin 注入器缝零 diff（02 KD-4）+ borders/watermark EOTF 后顺序由 pipe 尾段既有保证 + 05 走查 8 判据——m2-6 红线延续成立。
4. **测试对账**：预估 45+24+20+18+0 = +107 与「基线 2577/16/0」（M2-8-3 终态，ROADMAP 在案）算术闭环；XMPExportMatrixTests 两案冲突已判（E2 处方 = 单一默认语义 + 白名单改造）。
5. **依赖链**：01→02→03→04→05 线性链成立（03 wave 标 2 但 depends_on 02，串行无并行竞争）；每 plan autonomous + 每任务独立提交；封存清单∩files_modified 除 E1/E3/E4/E8 外为空。
6. **资源纪律**：E2E 全临时目录 scratch（禁入仓 fixture）；测试不触 8G 门敏感面（Export bundle 现行峰值安全，DRT E2E 用合成小图）；无模型/资产入仓；GUI 走查 Manual-Only 惯例在 05（GUI 不可用 → 待人工登记不阻塞翻账）。
7. **goal-backward**：ROADMAP M2-9 Goal 七要素 ↔ plan 任务集映射齐全（格式矩阵=封存、四模式=01/04、元数据=01/03/04、模板=01/03/04、ICC 联动=02/03/04、队列 UI=04、yiyin 终步=02 T4/05 走查8）；M2EXP-01..05 逐条可推出达成（E6 修复后 M2EXP-01 才完整）；M2-8-3 交接节（projection + effectiveDrtRecord + 零新依赖）被 04 KD-0 完整消费；`.lalb` manifest 注入 sink v1 不做 = CONTEXT 明示豁免 ✓。SC 挂账五项（recipe 预设 PRES/UltraHDR V2/peak-ICC V2/OQ-8 直出 V2/细粒度 UI 后置）05 KD-3 全数登记。

## 复审口径

修复代理按 E1..E9 处方回注五份 plan 原文（E6 为跨 plan 交接补登记，落在 03）后，本门只复核改动 hunks + front-matter 一致性，不重开全文。

---
phase: m2-6
plan: "M2-6-3"
title: "面板 + EOTF 联动 + HDR 视口 + Post 四件迁移 + 收口（wave 3）——App 持久化链（session carrier + makeSidecarDocument v6 写腿 + restore 腿 + HistoryItem additive drtRecord 快照 + history_drt_* 键族 + historyHash 折叠）+ DrtPanelModel 与 DRT 面板（Method 分段卡恒展开/预设三件套/Peak slider/displayTransformPlaceholder 特面替换/Vignette 行原地保留）+ EOTF 联动吸附 + HDR→EDR 视口（IsHdrEncoding→16F drawable + CAMetalLayer PQ/HLG colorSpace 切换）+ Post 四件迁移（DRT 后 display-referred 应用一次 + Look 页 pre-DRT 注摘除）+ method 收口 + zh 对账 + phase 翻账（VALIDATION 停）"
wave: 3
depends_on: ["M2-6-1", "M2-6-2"]
autonomous: true
requirements: [M2DRT-01, M2DRT-04, M2DRT-05, M2DRT-06]
files_modified:
  - App/Sources/Lightamer/State/PipeCoordinator.swift        # 修改：DRT 持久化四件（session carrier 写腿调度 + makeSidecarDocument 读 v6 字段 + restore 腿 + run 传点 terminalTail 装配——rawOverrides 四件同构，KD-1）
  - App/Sources/Lightamer/State/WorkspaceModel.swift         # 修改：DrtRecord session carrier（per-url 持有/恢复，rawDecodeOverrides 先例）+ 面板 pass-through 钩子
  - App/Sources/Lightamer/State/EditorState.swift            # 修改：document 级 DRT commit 面（HistoryItem additive drtRecord 快照 + undo/redo 恢复腿 + history_drt_* 键族）
  - LightamerCore/Sources/Pipe/History/HistoryStack.swift    # 修改：HistoryItem 增 additive optional `drtRecord: DrtRecord?`（stackSnapshot 06-01 先例——decodeIfPresent + 写者 nil 省略）+ 投影面 drtHash 折叠（set-fields-move，KD-1）
  - LightamerCore/Sources/Sidecar/LightamerSidecar.swift     # 修改：SidecarHistoryItemRecord 投影同步 drtRecord additive 字段（runtime↔sidecar String-hash 投影惯例）
  - App/Sources/Lightamer/UI/Shell/EditorTabRoute.swift      # 修改：displayTransform 页面板行接入 + displayTransformPlaceholder 特面摘除（Vignette 行原地保留——checker E1 勘误边界不动）+ Look 页四行 panel_note_pre_drt 注摘除
  - App/Sources/Lightamer/UI/Shell/DrtPanelView.swift        # 新建：DRT 面板（Method 分段卡恒展开 + Color & Encoding 组 + ACES Limiting 组 + OpenDRT 预设三件套 + Peak slider）
  - App/Sources/Lightamer/UI/Shell/DrtPanelModel.swift       # 新建：面板 ViewModel（订阅 session carrier + 写经 EditorState document commit + 预设单 discrete commit + EOTF 吸附逻辑消费 legalEOTFs）
  - App/Sources/Lightamer/UI/Shell/EditorAdjustmentStackView.swift  # 修改：displayTransformPlaceholder 渲染臂替换为 DrtPanelView 挂载
  - App/Sources/Lightamer/UI/EditorMTKView.swift             # 修改：DRT HDR 视口腿（blit regime 扩展 + CAMetalLayer.colorspace PQ/HLG 切换 + applyEDRDisplaySurface 四分支化，KD-4）
  - LightamerCore/Sources/Pipe/PixelPipe.swift               # 修改：Post 四件尾段插槽填充（drtPostOpNames 注入 skip + 尾段四 box 应用——KD-5 半径红线）
  - LightamerCore/Sources/Pipe/LayerCompositeDriver.swift    # 修改：drtPost box 集透传（terminalTail 同位同半径）
  - Resources/Localizable.xcstrings                          # 修改：history_drt_* + 面板标签/方法名/预设名/空间名/EOTF 名随手键（checker 教训②：front-matter 严格申报）
  - AGENTS.md                                                # 修改：M2-6 架构增量节（DrtRecord/尾段策略/HDR 判定/Post 四件域惯例——front-matter 严格申报）
  - Project.swift                                            # 修改：新测试文件登记（checker E2 纪律）
  - Tests/LightamerTests/DrtPersistenceTests.swift           # 新建（APP，SidecarV5Tests 同位）：session carrier/写腿/restore 腿/undo-redo 恢复/historyHash 折叠
  - Tests/LightamerTests/DrtPanelModelTests.swift            # 新建（APP）：面板 Model 预设应用/吸附/commit 语义
  - Tests/LightamerTests/DrtViewportTests.swift              # 新建（APP，EDRViewportTests 同位）：HDR 判定→blit regime/colorspace 四分支 + 非 DRT 逐字节不变
  - Tests/LightamerTests/DrtPostMigrationTests.swift         # 新建（LAYERS）：Post 四件主链 skip + 尾段应用 + display-referred golden 重钉
  - .work/gsd/phases/m2-3-ui-shell/M2-3-TAB-MATRIX.md        # 修改：displayTransform 页 + Look 页注记勘误行（路由表实态同步惯例）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt  # 修改：四个新测试文件增行
  - .work/gsd/phases/m2-6-drt/M2-6-3-SUMMARY.md              # 新建（收口任务）
  - .work/gsd/phases/m2-6-drt/M2-6-3-DECISIONS.md            # 新建（收口任务）
  - .work/GOAL-STATE.md                                      # 修改：续接点 + phase 翻账（收口任务）
  - .work/TODO.md                                            # 修改：M2-6 收口条目（收口任务）
  - .work/LESSONS.md                                         # 如踩坑
---

# Plan M2-6-3 — 面板 + EOTF 联动 + HDR 视口 + Post 四件迁移 + 收口

> **性质**：App 集成/管线收尾 plan——M2-6 面向用户的交付面。六块：①**持久化链**（session
> carrier + sidecar v6 写腿/restore 腿 + HistoryItem additive 快照 + undo/redo——rawOverrides
> M2-4-1 四件同构）；②**DRT 面板**（M2DRT-01：Method 分段卡恒展开，替换
> `displayTransformPlaceholder` 占位特面，Vignette 行原地保留）；③**EOTF 联动吸附**（OQ-5-A
> UI 行为半边）；④**HDR→EDR 视口**（OQ-6-A 预览腿：IsHdrEncoding → 16F drawable +
> PQ/HLG colorSpace）；⑤**Post 四件迁移**（M2DRT-05：DRT 后 display-referred 全图一次，
> Look 页 `panel_note_pre_drt` 注摘除）；⑥**method 收口 + zh + phase 翻账**（M2DRT-06 兑现
> 收尾 + C 档门控 3 VALIDATION 停）。规格锚点 = D-M2-6-CONTEXT-1/5/6/8/9/12（不得重开）+
> FEATURE-MAP §5/§2.6 + REQUIREMENTS M2DRT-01/04/05/06。
>
> **执行期精读悬决点**（CONTEXT 预告项中属本 plan 的两件，T2/T4/T5 内钉死、DECISIONS 签注）：
> ①PQ/HLG drawable colorSpace 枚举与 peak→layer 映射（OQ-6——CGColorSpace name 常数实态 +
> PQ 绝对/相对映射语义 + EDRHeadroomMonitor 被动关系落笔）；②Post 四件 display-referred
> 强度标定（OQ-9——四 kernel 输入域换轨后的锚重钉终值）。另：HDR 屏未备时的 HDR 编码降容
> 显示 = 走查观察项（非阻塞门，OQ-6-A 字面）。

## 已定裁决（不得重开）

- **D-M2-6-CONTEXT-2（OQ-2 A）**：DrtRecord document 级；编辑走 document 作用域 history
  item（`history_drt_*` 键族）；预设应用 = 单 discrete commit；custom = 派生展示值。
- **D-M2-6-CONTEXT-5（OQ-5 A）**：`legalEOTFs` Core 单源（P1 已落）；本 plan 落切换吸附
  UI 行为（空间切换时当前 EOTF 非法 → 吸附该空间首个合法值，单 discrete commit）。
- **D-M2-6-CONTEXT-6（OQ-6 A）**：HDR = 编码值直写 16F drawable + `CAMetalLayer.colorspace`
  切对应编码 space；`EDRHeadroomMonitor` 被动读出不动；非 EDR 屏 HDR 编码降容显示不阻塞
  （走查观察项）；**非 DRT 文档行为逐字节不变**（env 回切路径——`LibraryLegacyGate` 回切
  面 P1 已保证管线零差，本 plan 保证视口零差）。
- **D-M2-6-CONTEXT-8（OQ-8 A）**：DRT 编辑 = document 作用域 history item；colorout/gamma
  降级语义 P1 已落。
- **D-M2-6-CONTEXT-9（OQ-9 A）**：Post 四件 = DRT 之后 display-referred 应用一次 + 既有
  kernel 域适配；`panel_note_pre_drt` 摘除；UI 家不动（仍 Look 页 Look 组——不新开 Detail
  页签，M2-3 裁定范围）。
- **D-M2-6-CONTEXT-12（OQ-12 A）**：method 注册口 = 枚举 + 穷举 switch（P1/P2 已落）；本
  plan 收口 = 面板暴露 `[aces20, opendrt]` + 预留 case 不入 UI + zh 键对账。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 持久化链 = rawOverrides 四件同构 + HistoryItem additive 快照

- **四件同构**（`PipeCoordinator.swift:519-546` rawOverrides 先例逐条对照）：
  1. **session carrier**（`WorkspaceModel`）：`drtRecord(for url:)` per-url 持有（默认
     `DrtRecord()` pristine——**默认记录不写 sidecar**（isDrtRecordDefault → makeSidecar
     显式 nil，档保持 v5 形态字节）；
  2. **写腿**：面板变更 → carrier 更新 → `scheduleSidecarWrite()`（2s debounce 现制）；
     `makeSidecarDocument` 读 carrier 填 `displayTransform` 字段（P1 已备）；
  3. **restore 腿**：载入档 `displayTransform != nil` → 回注 carrier + 触发尾段重渲染
     （nil = pristine 零动作——rawOverrides restore :544 分级语义同构）；
  4. **run 传点**：coordinator 组装 run 参数时 carrier → `TerminalTailPolicy.drt(...)`
     （P1 T7 装配消费）；**pristine 文档传 `.sdrGamma`**（零管线差）——「DRT 恒在」是面板
     概念（M2-6 后默认 method 恒 OpenDRT），**渲染面 pristine=无 DRT 段**，二者并存由
     `isDrtRecordDefault` 判定缝合（KD 必答，防「默认档全图 tone map」的性能与视觉双重
     破坏——Alcedo 语义为 DRT 恒启用，Lightamer 收敛为「默认档 = 视觉等效 sdrGamma 直通」，
     差异入 DECISIONS 与 AGENTS 增量节）。
- **HistoryItem additive 快照**：`HistoryItem` 增 `public var drtRecord: DrtRecord?`
  （decodeIfPresent + 写者 nil 省略——stackSnapshot 06-01 先例）；commit 形态 = document
  级 item（`snapshot` 槽仍必填——占位空 instance 快照形态执行期钉死：复用 history 投影
  忽略面或 nil-instance 语义，**以「投影面不污染 instances」为硬约束**，方案 DECISIONS
  签注）；undo/redo 恢复腿 = item.drtRecord 回写 carrier + 触发写腿调度。
- **historyHash 折叠（set-fields-move 兑现，KD 必答）**：history 投影（`HistoryStack`
  有效集→hash）把**末位含 drtRecord 的 item** 的 `DrtRecord.stableHash` 折进 historyHash
  ——DRT 参数变更 → 新 history item → historyHash 变 → drift 判定覆盖（OQ-2-A 字面；
  无 drt item 的档与改造前 hash 逐位一致——回归机检）。
- **`SidecarHistoryItemRecord` 投影同步**：runtime additive 字段在 sidecar history 记录
  投影侧同步 decodeIfPresent/encodeIfPresent（UInt64 decimal String 惯例不涉——drtRecord
  是结构体非哈希）；旧档零漂移测试钉死。
- **键族**：`history_drt_param`（参数编辑）/ `history_drt_preset`（预设应用）/ 
  `history_drt_method`（method 切换）/ `history_drt_encoding`（空间/EOTF/peak）——四键
  xcstrings 同批。

### KD-2 DrtPanelModel + 面板 UI（M2DRT-01 面）

- **面板结构**（FEATURE-MAP §5 逐行）：Method 分段卡（ACES 2.0/OpenDRT）**恒展开**置顶；
  Color & Encoding 折叠组默认展开（Encoding Space 六选 menu / Encoding EOTF picker（合法
  子集）/ Peak Luminance slider 100-1000 默认 100）；ACES 2.0 专属组（Limiting Space 七选，
  method == aces20 时显示）；OpenDRT 专属组（Look 7+custom / Tonescale 全枚举 / Creative
  White 七项 picker，method == opendrt 时显示）。**无 detailed 参数编辑面**（CONTEXT 非目标
  明文——editor-owned 数据面已持久化，UI 只暴露预设三件套）。
- **`DrtPanelModel`**（@Observable，EditorTabRoute 面板 provider 惯例）：只读投影
  carrier + 三个动作面——`setParam`（连续拖动 = live-upsert 语义？**否**：DRT 是文档级
  record，无 ModuleInstance live 槽——拖动即时更新 carrier 触发重渲（debounce 由 pipe
  调度天然承担），**松手/步进提交一次 discrete commit**（`commitContinuousEdit` 先例
  :1284 语义移植到 document 级——commit 时点判定执行期钉死，DECISIONS 签注）；
  `applyPreset`（单 discrete commit，undo 一步回）；`setMethod`（discrete commit）。
- **占位替换**：`EditorAdjustmentStackView.swift:134` `displayTransformPlaceholder` 渲染
  臂 → `DrtPanelView` 挂载；`EditorTabRoute` specialContent 枚举**保留 case 但值不再
  产生**（枚举摘除会扩 diff 触 TAB-MATRIX 全表——收敛为「枚举保留 + 映射表改返回新面板
  描述」还是「枚举+臂全摘」执行期按 diff 最小面定，DECISIONS 签注）；Vignette 行原地
  保留（checker E1 勘误边界不动——CONTEXT 范围①字面）。
- **node 选中路由**：`displayTransformNodeID` 面板选中 → Display Transform 页（M2-4 既有
  路由零改——本 plan 只换页内容）。

### KD-3 EOTF 联动吸附（OQ-5-A UI 半边）

- 空间切换 → `legalEOTFs(for: newSpace)` 查询；当前 EOTF ∉ 合法集 → 吸附到**该空间首个
  合法值**（FEATURE-MAP §5 联动表行序 = 合法序）；吸附与空间切换**同一 discrete commit**
  （一次 undo 双值回）；EOTF picker 数据源 = `legalEOTFs(for: 当前空间)`（UI 永不出现非法
  项——纯函数消费，禁 UI 层硬编码副本，OQ-5-B 拒绝理由）。
- **peak 联动**：peak slider 编辑 = discrete commit（`history_drt_encoding`）；PQ/HLG 时
  slider 语义 = tonescale limiting 输入（P1 KD-2/KD-6）；SDR 时同样可调（上游行为如实，
  P2 KD-5 必答）。
- **测试**：吸附矩阵（六空间 × 七 EOTF 全组合机检——非法组合切换后 EOTF ∈ 合法集 + 合法
  组合保持原值）+ 吸附 commit 原子性（undo 一步双值回）。

### KD-4 HDR→EDR 视口（OQ-6-A 预览腿）

- **判定→尾段输出**（P1 已备）：HDR（st2084/hlg）尾平面 = 16F 编码值平面。视口腿：
  - `EditorMTKView.applyEDRDisplaySurface` 三分支化→四分支：SDR-gamma（现 bgra8Unorm）/
    EDR-linear（现 16F + extendedLinearSRGB）/**DRT-SDR**（bgra8Unorm + drawable
    colorSpace = DRT encoding space 对应 CGColorSpace——P3 原色匹配，gamma 先例「软件编码
    + layer colorSpace 匹配」）/**DRT-HDR**（16F + colorspace = PQ/HLG 对应 CGColorSpace
    + `wantsExtendedDynamicRangeContent`）。
  - **colorSpace 终式（执行期钉死）**：PQ = `CGColorSpace(name: .extendedITUR_2100PQ)`
    / HLG = `.extendedITUR_2100HLG`（macOS 原生 name 常数——实态核读 + 非 nil 断言；
    不可用时回落 extendedSRGB + E3 记录）；peak→layer 映射 = PQ 编码为绝对亮度语义、
    `maximumExtendedDynamicRangeColorComponentValue` 由系统读出（**被动**——不写 edr
    headroom 期望值，`EDRHeadroomMonitor` 现面零改；peak 与屏上限的差 = 降容显示，走查
    观察项非门）。
  - **blit regime 扩展**：`blitRegime(edrActive:sourceIsDisplayReady:)` 增 DRT 两臂
    （sourceIsDisplayReady 在 DRT 尾平面恒 true——尾平面即显示就绪编码面）；16F blit
    路径复用 EDR 腿直写面。
- **判定纯函数消费**：视口分支判定 = `isHdrEncoding(record.encodingEotf)`（Core 单源，
  禁视图层复制判定式——OQ-6-C 拒绝理由的机检面：grep 无第二实现）。
- **零差门**：非 DRT 文档（pristine → `.sdrGamma`）视口路径**逐字节不变**（现 bgra8 腿）；
  EDR 手动开关语义不动（`.edrLinear` 臂原样）；DRT HDR 与手动 EDR 开关**互斥收敛**——
  DRT-HDR 激活时手动 EDR 开关置灰/旁路（状态漂移防线，OQ-6-C 语义延伸；具体手势执行期
  按 EDRControlView 现面定，DECISIONS 签注）。

### KD-5 Post 四件迁移（M2DRT-05）

- **主链 skip**：drt 尾段激活时，`drtPostOpNames` 命中的 box 在主链 pass 装配处跳过
  （gamma skip 同模式——装配期摘除非运行时跳跑）；opName 集由 App 注入（App 侧从
  `NodeOwnershipCatalog.drtPostOpNames` 计算 → `DrtTailParams` 或并位参数传入——**Core
  不 import IOP 方向约束**保持；注入面执行期定形，DECISIONS 签注）。
- **尾段插槽填充**（P1 T7 注释锚）：装配序 = `[DrtMethodBox] → [post 四 box 原参数] →
  [EotfBox]`——四 box **原样复用**（ModuleBoxing 装配面零新 kernel），仅在尾段重放；
  输入域 = DRT 输出 display-referred 线性（encoding space 原色）。
- **display-referred 重校准（执行期钉死）**：四 kernel 的 scene-referred 标定锚在
  display-referred 域重钉——Sharpen（unsharp 参数半径/阈值量纲不变，锚图换 display 域
  参考）/ Clarity（equalizer 带增益钳制面）/ Halation（bloom 阈值域换 [0,1] 显示线性）/
  FilmGrain（粒度强度在暗部显示域的可见性标定）——每件 golden 重钉终值 + 走查观察项
  （gui-acceptance 主观面）入 SUMMARY；Float64 参考侧（BloomReference/GrainReference）
  锚值同步更新（同批同 commit）。
- **UI 摘注**：`EditorTabRoute.swift` Look 页四行 `note: "panel_note_pre_drt"` 摘除 +
  `M2-3-TAB-MATRIX.md` 勘误行（路由表实态同步惯例——checker 教训①穷举触点：TAB-MATRIX
  是路由表的转录面，漏勘 = 文档失真）。
- **测试**：主链 skip 断言（drt 激活时 pieces 无四件 opName）+ 尾段序断言（DRT → 四件 →
  EOTF）+ 非 drt 文档四件仍主链原位（零回归）+ display-referred golden（每件锚点重钉值）
  + 缓存键（四件参数变更 → 尾平面 MISS、colorout 前全 HIT）。

### KD-6 method 收口 + zh + 文档（M2DRT-06 兑现面）

- **面板暴露集**：`DrtMethod.allCases` = [aces20, opendrt]（P2 后实态）；预留 case
  （filmic/sigmoid/agx）**不入枚举**——D1 注册口「形状」机检 = P1 AC#9 + P2 AC#6 保持 +
  本 plan `defaultFaceDisabledOpNames` 零 diff（grep 审计）；「parity 后评估回归」挂账面
  = AGENTS 增量节注记（非代码）。
- **zh 对账**：新键随手 `String(localized:)`（KD-1 四 history 键 + 面板组标签/方法名/
  预设名/空间名/EOTF 名/四件套标签 ≈ 30-50 键）——**预设名/空间名/EOTF 名为技术专名不译**
  （zh 值 = 英文原文，OQ-12-A）；收口批 `Scripts/zh-audit.py --check` 全绿。
- **文档同批（checker 教训② front-matter 严格申报）**：`AGENTS.md` M2-6 架构增量节
  （DrtRecord/尾段策略/HDR 判定/Post 四件域/键族登记）+ `M2-3-TAB-MATRIX.md` 勘误行 +
  FEATURE-MAP「45 参数」勘误注记（53 实数——CONTEXT 事实基线②的文档落点，**注记不改
  REQUIREMENTS 原文**）。
- **性能观察（OQ-10 bench 行）**：全图 DRT pass @24MP/100MP 计时入 SUMMARY（PREVIEW 桶
  + FULL 小图实测——100MP 全幅 bench 非 gate，观察行）；60fps 复验归 M2-11（惯例）。

## read_first

1. `.work/gsd/phases/m2-6-drt/M2-6-CONTEXT.md`——D2/5/6/8/9/12 裁决正本 + Specific Ideas
   （DrtPanelModel 挂接/尾段策略枚举先见）。
2. `.work/gsd/phases/m2-6-drt/M2-6-1-PLAN.md` KD-1/KD-6/KD-7 + `M2-6-1-SUMMARY.md` +
   `M2-6-2-SUMMARY.md`——P1/P2 交付面（TerminalTailPolicy/EotfBox/isHdrEncoding/method 臂）。
3. `App/Sources/Lightamer/State/PipeCoordinator.swift:508-560,1160-1320`——rawOverrides
   四件同构正本 + commitContinuousEdit 语义。
4. `App/Sources/Lightamer/UI/Shell/EditorTabRoute.swift:160-300` + `EditorAdjustmentStackView
   .swift:120-290`——specialContent/占位特面/panel descriptor 面（面板接入点）。
5. `App/Sources/Lightamer/UI/EditorMTKView.swift:320-460`——applyEDRDisplaySurface/blit
   regime（KD-4 四分支化点）。
6. `LightamerCore/Sources/Pipe/History/HistoryStack.swift:49-230`——HistoryItem additive
   先例（stackSnapshot/pasteSet）+ commit/投影面。
7. `LightamerIOP/Sources/{Bloom,Sharpen,Grain,Equalizer}` + 各 Reference——Post 四件 kernel
   与标定锚现位（KD-5 重钉源）。
8. `Tests/LightamerTests/`（SidecarV5Tests/EDRViewportTests/LayerCompositeTests 同位参照）+
   `Scripts/test-direct.sh` 头注 + `Scripts/zh-audit.py` 用法。

## 纪律（强制）

1-8 全同 M2-6-1 纪律（提交/构建/测试基线 = P2 验收后总数/边界/config 检查/测试登记/收口
核对/枚举穷举）。**本 plan 增补**：

9. **架构红线**：`PipelineDocument.swift`/`NodeOwnershipCatalog.swift`/`Registry.swift`/
   `V50Order.swift`/`PipeCacheKey.swift` **零 diff**；`PixelPipe.swift` diff 半径 = Post
   四件 skip 集 + 尾段插槽填充（策略枚举/键折叠/DRT 装配段零改动）；`EditorMTKView.swift`
   diff 半径 = applyEDRDisplaySurface 分支扩展 + blit regime 两臂（渲染数学零改）；
   `LibraryLegacyGate` 回切面零触碰（回切后 UI 与 M2-2 前同构红线不破——DRT 面板只在
   非 legacy face 挂载）。
10. **zh 纪律**：新键全部 `String(localized:)` 随手入 `Resources/Localizable.xcstrings`；
    收口批 `Scripts/zh-audit.py --check` 必跑必绿；技术专名不译清单（预设/空间/EOTF）在
    PR 注释（commit body）列明。
11. **gui 走查（OQ-6/OQ-9 观察项）**：HDR 降容显示/Post 四件视觉标定/预设三件套手感 =
    走查证据落 `.work/gsd/phases/m2-6-drt/` evidence（截图按全局 §3.2 视口裁剪规则）——
    观察项非 gate，阻塞项才升级 E3。

## Tasks

### T1 持久化链（session carrier + history additive + restore）

- **read_first**：上列 1/3/6。
- **action**
  1. `HistoryStack.swift`：HistoryItem 增 `drtRecord` additive optional + 投影面 drtHash
     折叠（KD-1）；`LightamerSidecar.swift`：SidecarHistoryItemRecord 投影同步。
  2. `WorkspaceModel.swift` + `PipeCoordinator.swift`：KD-1 四件（carrier/写腿/restore 腿/
     run 传点——pristine 传 `.sdrGamma`）。
  3. `EditorState.swift`：document 级 commit 面（四个 `history_drt_*` 键 + discrete/continuous
     commit 语义 + undo/redo 恢复腿）。
  4. 新建 `Tests/LightamerTests/DrtPersistenceTests.swift`（APP）：carrier per-url 隔离 +
     写腿 debounce 触发一次 + restore 腿三态（nil 零动作/同值跳过/异值回注重渲——rawOverrides
     :544 分级同构）+ undo/redo 一步回（预设应用单 commit）+ historyHash 折叠（DRT 变更 →
     hash 变；无 drt item 档 hash 与改造前逐位一致）+ 旧档（无 drtRecord 字段）解码零漂移 +
     pristine 档不写 displayTransform key（v5 形态字节）。
  5. 测试登记两处。
- **验收标准**
  - [ ] 上述断言全绿；`HistoryStack` diff 仅 additive（逐 hunk 核）；`git diff` 边界核。
  - [ ] 全套回归 `0 fail`（基线 = P2 验收后总数）。

### T2 DRT 面板 + Model + 占位替换

- **read_first**：上列 1/2/4。
- **action**
  1. 新建 `App/Sources/Lightamer/UI/Shell/DrtPanelModel.swift` + `DrtPanelView.swift`：
     KD-2 全量（面板结构 FEATURE-MAP §5 逐行 + 三动作面 + legalEOTFs 消费 + custom 派生
     展示）。
  2. `EditorTabRoute.swift` + `EditorAdjustmentStackView.swift`：占位特面替换（KD-2;
     Vignette 行原地保留；specialContent 枚举处置方案 DECISIONS 签注）。
  3. 新建 `Tests/LightamerTests/DrtPanelModelTests.swift`（APP）：面板结构描述符断言
     （组序/可见性随 method 切换）+ 预设应用单 commit + setMethod discrete + custom 派生
     （匹配快照→具名/不匹配→custom）+ peak 越界钳制 + 占位特面消失断言（specialContent
     查询面）+ Vignette 行在册断言。
  4. 测试登记两处。
- **验收标准**
  - [ ] 上述断言全绿；`displayTransformPlaceholder` 渲染臂不再产生（grep 审计：枚举保留
        与否与 DECISIONS 一致）；Vignette 行原位（TAB-MATRIX 面 T6 勘误）。
  - [ ] 全套回归 `0 fail`。

### T3 EOTF 联动吸附

- **read_first**：上列 1/2。
- **action**
  1. `DrtPanelModel.swift` 续：KD-3 吸附逻辑（空间切换吸附 + picker 合法子集 + 原子 commit）。
  2. `DrtPanelModelTests.swift` 续：吸附矩阵全组合机检（6×7）+ 吸附原子性（undo 一步双值
     回）+ UI 非法项不可达断言。
- **验收标准**
  - [ ] 吸附矩阵/原子性全绿；联动知识单源（视图层零第二实现——grep 审计）。
  - [ ] 全套回归 `0 fail`。

### T4 HDR→EDR 视口

- **read_first**：上列 1/2/5。
- **action**
  1. `EditorMTKView.swift`：KD-4 全量（四分支 applyEDRDisplaySurface + blit regime DRT
     两臂 + colorSpace 终式 + 互斥收敛）。
  2. 新建 `Tests/LightamerTests/DrtViewportTests.swift`（APP）：四分支判定矩阵
     （isHdrEncoding × drt 激活 → colorPixelFormat/colorspace 期望值逐臂断言）+ 非 DRT
     路径逐字节不变（现 bgra8 腿参数全等）+ 手动 EDR 臂原样 + DRT-HDR 与手动 EDR 互斥
     断言 + colorSpace 非 nil 断言 + blit regime 新臂。
  3. 走查观察项启动项记 SUMMARY（HDR 屏实机/降容显示观察——纪律 11）。
  4. 测试登记两处。
- **验收标准**
  - [ ] 四分支矩阵全绿；非 DRT/E DR 手动臂零差断言绿；colorSpace 终式入 DECISIONS。
  - [ ] 全套回归 `0 fail`。

### T5 Post 四件迁移

- **read_first**：上列 1/2/7。
- **action**
  1. `PixelPipe.swift` + `LayerCompositeDriver.swift`：KD-5 全量（注入 skip + 尾段插槽
     填充 + App 侧 opName 集计算注入）。
  2. 四件 display-referred 重校准（KD-5：锚重钉 + Reference 同步——Bloom/Grain Reference
     终值 DECISIONS 签注）。
  3. `EditorTabRoute.swift`：Look 页四行注摘除（T2 同文件可并批——登记清晰即可）。
  4. 新建 `Tests/LightamerTests/DrtPostMigrationTests.swift`（LAYERS）：KD-5 测试面全量
     （skip/序/golden 重钉/键局部性/非 drt 零回归）。
  5. 测试登记两处。
- **验收标准**
  - [ ] 上述断言全绿；重校准终值入 DECISIONS（每件一行锚值表）；`panel_note_pre_drt`
        零残留（grep 审计）。
  - [ ] 全套回归 `0 fail`。

### T6 method 收口 + zh 对账 + TAB-MATRIX/AGENTS 文档批

- **read_first**：上列 1/4/8 + `Scripts/zh-audit.py` 头注。
- **action**
  1. `Resources/Localizable.xcstrings`：全键落账（KD-1 四 history 键 + 面板标签全集）+
     `Scripts/zh-audit.py --check` 绿。
  2. `M2-3-TAB-MATRIX.md`：displayTransform 页 + Look 页注记勘误行。
  3. `AGENTS.md`：M2-6 架构增量节（KD-6 清单 + 键族登记 + pristine 直通差异声明）。
  4. FEATURE-MAP「45→53」勘误注记（`.work/gsd/research/ALCEDO-FEATURE-MAP.md` §5 处加
     勘误行——注记不改 REQUIREMENTS）。
  5. 性能观察行（OQ-10 bench）采集。
- **验收标准**
  - [ ] zh-audit --check PASS；TAB-MATRIX/AGENTS/勘误行落盘；注册口机检（P1 AC#9/P2 AC#6
        断言保持全绿）。
  - [ ] 全套回归 `0 fail`。

### T7 收口——SUMMARY/DECISIONS + phase 翻账 + VALIDATION 停

- **read_first**：本 plan AC 表 + `.work/GOAL-STATE.md` + `.work/TODO.md`。
- **action**
  1. AC 逐条机检 + 全套回归终跑（`--all` 前报备；计数/秒数/峰值 RSS 入 SUMMARY）。
  2. 落盘 `M2-6-3-SUMMARY.md`（测试数/吸附矩阵结果/重校准锚表/bench 观察行/走查证据索引）
     + `M2-6-3-DECISIONS.md`（占位特面枚举处置/PQ-HLG colorSpace 终式/peak→layer 映射/
     Post 四件标定终值/pristine 直通差异/pristine commit 形态）。
  3. `.work/GOAL-STATE.md`：M2-6-3 续接点 + **M2-6 phase 翻账**（M2DRT-01..06 销账 +
     REQUIREMENTS 勾选面提示——按惯例 REQUIREMENTS 勾选由 verify-work/签核批处理，此处
     只登记完成态）；`.work/TODO.md` 收口条目；LESSONS 如踩坑。
  4. `git diff --stat` 核对边界（纪律收口核对）。
  5. **VALIDATION 停**（C 档门控 3）——verify-work 结论交用户签核，本 plan 止于此。
- **验收标准**
  - [ ] AC 表全绿；SUMMARY/DECISIONS/GOAL-STATE/TODO 同批落盘；diff 边界无越界。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 持久化链：carrier 隔离/写腿一次/restore 三态/undo-redo 一步回/historyHash 折叠（drt 变更→hash 变；无 drt 档逐位不变）/旧档零漂移/pristine 档不写 key | DrtPersistenceTests |
| 2 | 面板：Method 恒展开 + 三组结构与 FEATURE-MAP §5 逐行一致 + 预设单 discrete commit + custom 派生 + peak 钳制 + Vignette 行原位 + 占位特面不再产生 | DrtPanelModelTests + grep |
| 3 | EOTF 吸附：6×7 全组合机检（非法→吸附首合法 + 合法保持）+ 原子 commit（undo 一步双值回）+ 联动知识单源（legalEOTFs 唯一消费） | DrtPanelModelTests + grep |
| 4 | HDR 视口：四分支判定矩阵（isHdrEncoding 单源消费）+ 非 DRT 逐字节不变 + 手动 EDR 臂原样 + 互斥收敛 + colorSpace 非 nil | DrtViewportTests |
| 5 | Post 四件：drt 激活主链 skip + 尾段序 DRT→四件→EOTF + display-referred golden（重钉锚值全绿）+ 键局部性（四件参数变更尾平面 MISS、colorout 前全 HIT）+ 非 drt 四件原位零回归 | DrtPostMigrationTests |
| 6 | `panel_note_pre_drt` 零残留 + TAB-MATRIX 勘误行在册；`defaultFaceDisabledOpNames`/注册面零 diff（method 收口——grep 审计） | grep + `git diff` |
| 7 | zh：新键全落 xcstrings + `zh-audit.py --check` PASS；技术专名不译 | 脚本 + `git grep` |
| 8 | `PipelineDocument.swift`/`NodeOwnershipCatalog.swift`/`Registry.swift`/`V50Order.swift`/`PipeCacheKey.swift` 零 diff；`PixelPipe`/`EditorMTKView` diff 半径逐 hunk 核 | `git diff` 逐 hunk |
| 9 | 全套回归 0 fail，计数 ≈ P2 基线 + 25..40 | test-direct.sh --all TOTAL 行双读 |
| 10 | diff 边界 == 申报文件集；测试登记闭环（四文件 × Project.swift + BUNDLE-MAP 双命中）；AGENTS.md/xcstrings 在 front-matter 申报（checker 教训②） | `git diff --stat` + `git grep` |

## 风险与边界

- **pristine 直通差异（KD-1 必答项的行为面）**：Alcedo 语义 = DRT 恒启用（默认 OpenDRT
  渲染）；Lightamer 收敛为 pristine 档 = `.sdrGamma` 直通（视觉上 ≈ 无 DRT 的现行为）——
  默认档开图视觉与 M2-5 前一致，**用户显式动 DRT 面板后才进入 DRT 渲染**。此为性能/视觉
  双保护与「非 DRT 文档行为不变」红线（OQ-6-A）的共同要求；与 Alcedo 的差异在 AGENTS
  增量节显式声明（对标偏离登记一处）。若晨审推翻（要求 DRT 恒渲染）= pristine 传 `.drt`
  一行 + 回归重跑，决策点已隔离在 KD-1 传点处。
- **HDR 降容显示观察项**：非 EDR 屏上 PQ/HLG 编码 = 降容显示（compositor 裁剪）——
  OQ-6-A 明文不阻塞；走查记录入 evidence；macOS PQ colorSpace 常数若实态不可用（API
  面变化）回落 extendedSRGB + E3。
- **Post 四件重校准的主观面**：display-referred 锚值客观可钉（golden），但「视觉等效」
  存在主观残差——走查证据（纪律 11）+ 偏差记录入 SUMMARY；不做自动 A/B。
- **HistoryItem snapshot 槽形态**（KD-1 悬决）：document 级 item 的 `snapshot` 必填槽
  处置方案执行期钉死——若需投影面忽略逻辑，改动半径限于 HistoryStack 投影函数数行
  （sidecar 投影同步），禁扩全文件。
- **specialContent 枚举处置**（KD-2 悬决）：摘除 vs 保留——diff 最小面判定；摘除则
  TAB-MATRIX 勘误行同步「枚举移除」事实；两案均合规，DECISIONS 签注即可。
- **EOTF 切换 UI 时延**：尾平面重算一次（M2-6-1 KD-6 键局部性）——PREVIEW 桶 ms 级；
  FULL 大图切换时延走查观察（非门）。
- **基线上移**：起算基线 = M2-6-2 验收后总数；本 plan 预计 +25..40。

## 提交约定

- T1 `feat(app): drt persistence with document history integration`
- T2 `feat(app): display transform panel with method card`
- T3 `feat(app): eotf linkage snapping for encoding space`
- T4 `feat(app): hdr viewport for drt encoded output`
- T5 `feat(iop): migrate post four after display transform`
- T6 `chore(m2-6): method registry closeout zh audit and tab matrix errata`
- T7 `docs(m2-6): close out plan 3 and m2-6 phase`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。

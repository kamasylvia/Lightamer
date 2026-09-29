---
phase: m2-3
plan: "M2-3-1"
title: "UI 壳骨架——暗色玻璃 ThemeTokens 单一来源（D1）；AppPhase 双工作区路由 + WorkspaceHost + ProjectWorkspaceFace 演进（D2）；LibraryGridModel 集合态单源 + 双档缩略图桥（零 Core 改动）；左竖向胶片条虚拟化组件（用户修订：偏离 Alcedo 底部）；顶栏 + 菜单 IA 收纳（Session 死路由门控，D11）；BackgroundTaskHosting 协议先行 + 导入腿（M2UIW-06）。纯 App 层，Core 零改动"
wave: 1
depends_on: ["M2-2"]
autonomous: true
requirements: [M2UIW-01, M2UIW-02, M2UIW-06, M2LIB-06]
files_modified:
  - App/Sources/Lightamer/UI/Theme/ThemeTokens.swift            # 新建（→ tuist generate）：暗色玻璃家族 tokens 单一来源（colCardSurface/colCardBorder 视觉意图、数值自写自测——GPL DESIGN.md 数值禁逐值拷）；新壳文件裸 hex 唯一豁免地
  - App/Sources/Lightamer/UI/Shell/WorkspaceModel.swift         # 新建：@MainActor @Observable——AppPhase 枚举（library/editor）+ 双态保留结构（选中图/ExifSearchFilter/排序/滚动锚/滚动位）+ 无损往返切换 + isSearchDialogPresented 呈现布尔（⌘F，P2 消费——m6）
  - App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift      # 新建：gate=false 壳根——library face ↔ editor face 两态路由 + 切换动画（Alcedo 折叠语义）
  - App/Sources/Lightamer/UI/Shell/EditorWorkspaceShellView.swift # 新建（P1 骨架态）：编辑器 workspace 占位容器（空态 slot：视口区/左轨/右栏/胶片条位），P3 填充三段布局
  - App/Sources/Lightamer/UI/ContentView.swift                  # 修改：gate=false 分支内层 = ProjectWorkspaceFace → WorkspaceHostView（legacyBody 分支零 diff，OQ-12/D12）
  - App/Sources/Lightamer/Library/LibraryGridModel.swift        # 新建：图库网格/胶片条唯一集合态消费者——ExifSearchFilter + FilterSort + keyset 分页（searchPage/searchNullTail + LibraryPageAnchor）+ 选中态 + 当前图
  - App/Sources/Lightamer/Library/LibraryThumbnailBridge.swift  # 新建：双档缩略图桥——档 A = SessionThumbnailProvider.embeddedPreview(url:)（public static，零 Core 改动）；档 B = THUMBNAIL 分辨率管线渲（has_edits 裁决）；盘缓存 = ThumbnailDiskStore(directory: .lathumbs)；内存 LRU + 并发上限 + prioritize
  - App/Sources/Lightamer/UI/Shell/FilmstripView.swift          # 新建：左竖向胶片条（SwiftUI List 惰性虚拟化 + 窗口化预取 + 选中环 + 当前图高亮；万张滚动）
  - App/Sources/Lightamer/UI/LightamerApp.swift                 # 修改：菜单 IA 收纳——MenuCommandSet 纯函数消费 + Session 死路由门控 + Open/Import/回图库/进编辑器命令回路 + View 菜单挂工具轨/示波器可见性占位
  - App/Sources/Lightamer/UI/Shell/MenuCommandSet.swift         # 新建：纯函数（gate/phase → 可见命令 id 集）——菜单 IA 的单测面
  - App/Sources/Lightamer/Library/BackgroundTaskHosting.swift   # 新建：后台任务注册表协议一次成型（id/title/进度快照/cancel）+ @MainActor registry——导入腿首实现，导出腿 M2-9、AI 腿 M2-10 消费
  - App/Sources/Lightamer/UI/Shell/BackgroundTaskBarView.swift  # 新建：底部任务栏 + 任务对话框宿主（对话框 + 底部栏双呈现共用 registry）
  - App/Sources/Lightamer/Library/ImportTaskAdapter.swift       # 新建：ImportProgress 快照 → BackgroundTaskHosting 适配器（ImportModeDialog/ImportProgressView 本体零 diff）
  - Tests/LightamerTests/ThemeTokensTests.swift                 # 新建（→ tuist generate）：token 完备性 + 家族语义断言
  - Tests/LightamerTests/WorkspaceRoutingTests.swift            # 新建：AppPhase 往返无损（filter/选中/滚动位逐字段）+ gate 两分支面 marker + MenuCommandSet 矩阵
  - Tests/LightamerTests/LibraryGridModelTests.swift            # 新建：keyset 逐页不重不漏 + filter 变更重置 + 选中/当前图状态机（真 .lalb fixture）
  - Tests/LightamerTests/LibraryThumbnailBridgeTests.swift      # 新建：双档裁决（has_edits）+ LRU 驱逐 + 并发上限 + 请求窗口合并计数（万张不爆）
  - Tests/LightamerTests/FilmstripModelTests.swift              # 新建：万行窗口化（mount 窗口外零缩略图请求计数断言）+ 选中环状态 + 1 万行挂载性能观察（BENCH| 行，非门）
  - Tests/LightamerTests/BackgroundTaskRegistryTests.swift      # 新建：注册/进度/取消/完成四态 + 导入腿适配单调快照 + 双呈现一致性
  - .work/gsd/phases/m2-3-ui-shell/M2-3-1-SUMMARY.md            # 新建（收口任务）
  - .work/gsd/phases/m2-3-ui-shell/M2-3-1-DECISIONS.md          # 新建（收口任务）
  - .work/GOAL-STATE.md                                         # 续接点追加（收口任务）
  - .work/LESSONS.md                                            # 如踩坑
---

# Plan M2-3-1 — UI 壳骨架（tokens + 双工作区路由 + 集合态/缩略图缝 + 左竖胶片条 + 菜单 IA + 后台任务协议）

> **性质**：纯 App 层 plan——`LightamerCore/` 零改动（壳消费 M2-2-3 已交付 API 面）。把
> D-M2-3-CONTEXT-1..12 中壳骨架相关裁决落成新壳的地基：主题 tokens 单源、AppPhase 双态
> 路由、图库/胶片条共用的集合态模型与缩略图桥、**左竖向胶片条组件**（用户修订：偏离
> Alcedo 底部——本项目标识性差异，computer-use 对照以修订后布局为准）、菜单 IA 收纳、
> 后台任务协议先行。规格锚点 = `research/ALCEDO-FEATURE-MAP.md` §1.1/1.2 + §1.3（编辑器
> 布局语义，P3 消费）+ `M2-3-CONTEXT.md`（裁决正本）。
>
> **本 plan 是 P2/P3 的缝正本**：`WorkspaceModel`（双态路由与保留）、`LibraryGridModel`
> （集合态唯一消费者）、`LibraryThumbnailBridge`（缩略图供给）、`FilmstripView`（P3 直挂
> 编辑器左轨）、`BackgroundTaskHosting`（三腿协议）——API 形态在此定死，后续只消费不重开。

## 已定裁决（不得重开）

- **D-M2-3-CONTEXT-1（OQ-1 A）**：视觉验收 = 信息架构/布局语义级对齐 + 逐屏差异清单
  （P4 执行）；tokens 数值自写自测，GPL DESIGN.md 数值禁逐值拷。
- **D2（OQ-2 A）**：同款两态路由（Alcedo `WorkspaceHost` 语义）：图库 ↔ 编辑器单窗口；
  入口 = 网格双击（P2 接线，本 plan 路由先立）；编辑器回退按钮/⌘W 关图回图库；**切换
  保留集合态与选中态（往返无损）**；Welcome 面保持 P2 语义（无项目 → Library 空态 +
  新建/打开入口）。
- **D12（OQ-12 A）**：`legacyBody`/Session 面板文件（SidebarView/SessionBrowserView/
  CullingView/FilterBarView 等 legacyBody 树资产）**零 diff**；`ContentView` 只动
  gate=false 分支内层；LibraryLegacyGateTests 与冻结 marker 快照零改动全绿。
- **用户修订（2026-09-29）**：胶片条不放底部，放**编辑器左侧竖向滚动**——本 plan 交付
  该组件本体（竖向、虚拟化），P3 挂进编辑器三段布局左轨。
- **D9（OQ-9 A）**：新 UI 开写即 `String(localized:)` + 英文默认值（键名英文族沿用
  `settings_*`/`menu_*` 惯例），zh 值允许滞后，P4 统一对账补录。
- **D11（OQ-11 A）**：菜单 IA 对齐 + 快捷键保守——Session 死路由清理 + 项目命令回路 +
  View 菜单挂可见性；Alcedo 具体键位不逐项照抄；25 shortcut 增删以新 IA 为准。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 ThemeTokens = 新壳唯一色彩来源，与 legacy `LightamerColors` 并存零迁移

新文件 `UI/Theme/ThemeTokens.swift`（与 legacy `LightamerColors.swift` 同目录、互不引用
——legacy 树继续消费旧色板，新壳只消费 tokens，两者零交叉）。tokens 家族 = Alcedo 暗色
玻璃卡片家族的**视觉意图**：`cardSurface`（半透明深底 + 材质模糊挂点）/ `cardBorder` /
`windowBackground` / `textPrimary/Secondary` / `accent` / `selectedRing` / `busyDim`。
**数值自写自测**（D1 红线：禁从 Alcedo DESIGN.md 逐值拷；以「暗、低对比、玻璃卡片」语义
自定并在 DECISIONS 记录选定值与理由）。机检：新壳目录
`App/Sources/Lightamer/UI/Shell/` + `App/Sources/Lightamer/Library/Views/` 内
`git grep -E '#[0-9A-Fa-f]{6}'` **仅 ThemeTokens.swift 命中**（裸 hex 散落 = 违约）。

### KD-2 AppPhase 路由 = 枚举 + 双态保留结构，往返无损逐字段机检

```swift
enum AppPhase { case library, editor }        // 穷举 switch 全部在本文件内，禁 default
struct LibraryPhaseState { /* ExifSearchFilter, FilterSort, selectedIDs, pageAnchor,
                              scrollPosition, inspectorSelection */ }
struct EditorPhaseState { /* currentImageID, filmstripScrollAnchor */ }
```

`WorkspaceModel`（@MainActor @Observable）持 `phase` + 两态各一份保留结构 +
`isSearchDialogPresented: Bool`（⌘F 全局搜索对话框呈现态——**P1 预埋申报（m6）**，
P2 GlobalSearchDialog 仅在 WorkspaceHostView 消费此 bool，不自持状态）；
`openEditor(imageID:)` / `closeEditor()` 读写保留结构——图库 → 编辑器 → 图库往返后
filter/选中/滚动位逐字段相等（单测断言）。切换动画 = Alcedo 折叠语义（opacity+offset
过渡，200ms 级，不做逐帧仿真）。gate=true 时 WorkspaceHostView 不参与（`legacyBody`
原样，编译层隔离：gate 判定仍走 `LibraryLegacyGate.isLegacyLibraryRequested` 唯一读点，
本 plan 零改动该文件）。

### KD-3 LibraryGridModel = 图库网格与胶片条的唯一集合态消费者

Alcedo「胶片条与图库同集合过滤」语义的载体：一份 `ExifSearchFilter` + `FilterSort` +
keyset 分页游标（消费 `LibraryQueries.searchPage/searchNullTail` +
`LibraryPageAnchor.anchor(of:key:)`，**壳零 SQL**——M2-2-3 接口面清单逐签名引用）。
排序白名单五键（filename/rating/captureDate/iso/focalLength，M2-2-3 KD-3 既有守卫，
不重复实现）。filter/sort 变更 → 游标重置 + 首页重取；选中态（Set<Int64>）与当前图
（Int64?）为模型字段；分页 = 前向 `searchPage` + NULL 尾段 `searchNullTail` 两段走完
即封底（`isExhausted` 标志）。**模型纯逻辑可单测**（真 `.lalb` fixture），视图层只渲染。

### KD-4 缩略图桥双档 = 档 A embeddedPreview 直用 + 档 B 管线渲，零 Core 改动

- **档 A（无编辑）**：`SessionThumbnailProvider.embeddedPreview(url:)`（public
  nonisolated static，`SessionThumbnailProvider.swift:411` 实态核实）——ImageIO 嵌入
  预览，10.6ms/张 @86MP 既有实测。
- **档 B（`has_edits == true`）**：App 层经既有渲染管线 THUMBNAIL 分辨率渲一档
  （PipeCoordinator PREVIEW 腿同族消费面；不经 Session 域索引行——Library 行无
  relPath/SessionIndexRow，tier 裁决字段 = `LibraryImageRow.hasEdits` + 缩略图盘缓存
  mtime 对比，红线：不 touch `LightamerCore/Sources/Session/`）。
- **盘缓存**：`ThumbnailDiskStore`（public struct，`init(directory:)`，M2-2-1 冻结面）
  落 `<项目目录>/.<stem>.lathumbs/`（`LibrarySchema.thumbsDirectoryName(stem:)` 既有
  常量）；键 = 稳定字符串（`String(imageID)`，非用户路径——路径含空格/Unicode 免疫）。
- **内存**：NSCache LRU + 全局并发上限（≤4 in-flight）+ `prioritize` 可见窗口插队；
  请求合并 = 同 imageID in-flight 去重（单测：万行窗口滚动总请求数 ≤ 可见窗口 × 常数）。

### KD-5 FilmstripView = List 竖向虚拟化 + 窗口化预取，万张滚动为第一约束

`SwiftUI List`（macOS 惰性容器）竖向布局——**用户修订的标识性差异：左轨竖向滚动，非
Alcedo 底部横条**。行高固定常量；`onAppear/onDisappear` 窗口信号 → 桥 `prioritize/
cancel`；选中行玻璃环 + 当前图 accent 边。数据源 = `LibraryGridModel` 同一游标（KD-3，
不复制集合态）。机检 = 模型级：1 万行 id 挂载、仅可见窗口 ± prefetch 常数行发起缩略图
请求（计数断言）、滚动锚随选中行更新；性能观察项（BENCH| 行，非门）：1 万行 mount
数据本 plan 落 SUMMARY；滚动 60fps 目测 + List 窗口信号 → 桥 prioritize/cancel
**真接线兜底核验**（m9 并入）= P4 T2「交互/性能观察清单」①（E4 接账）。

### KD-6 菜单 IA = MenuCommandSet 纯函数，Session 死路由门控收口（M2LIB-06 尾巴）

`MenuCommandSet.visibleCommandIDs(gate:phase:)` 纯函数 = 菜单 IA 单测面：

| 命令（id） | gate=true（legacy 通道） | gate=false（新壳） |
|---|---|---|
| `session.new/open/close/import` 四死路由 | **原样可见**（M1 行为基线，字节语义不变） | **移除**（M2LIB-06 登记 inert 死路由清理） |
| `project.new/open/recent/importFolder/backup/move` | 不可见 | 可见（⌘N/⌘O/⌘⇧O/⌘⇧I 族，macOS 惯例保守对齐，D11） |
| `workspace.enterEditor` / `workspace.backToLibrary` | 不可见 | 可见（⌘E 进编辑器占位——P2 网格双击为主入口；⌘W 关图回图库） |
| `library.search` | 不可见 | 可见（⌘F 打开全局搜索对话框——命令 id 本 plan 在册，呈现态 = `WorkspaceModel.isSearchDialogPresented` P1 预埋（m6），呈现目标 P2 T3 接线） |
| `view.toolRail/scopes/adjustmentStack` 可见性 | 不可见 | 可见（toggle 命令，P3 面板挂接前为占位布尔） |

`LightamerApp.swift` 的 CommandMenu/CommandGroup 改为消费该函数（Session 四项包进
gate 条件，gate=true 分支**语句字节不变**）；25 既有 keyboardShortcut 逐个过 IA 表：
Session 专属键（⌘N 新建 Session 等撞新命令键位者）在 gate=false 下让位给新命令。
**AC 机检**：MenuCommandSet 矩阵单测（gate × phase 全组合）+ `git grep` 断言
Session 命令构造在 gate=false 路径零直接出现。

### KD-7 BackgroundTaskHosting 协议一次成型，导入腿首实现（M2UIW-06 地基）

```swift
protocol BackgroundTaskHandle: Sendable { var id: UUID; var title: String;
  var snapshot: BackgroundTaskSnapshot /* progress 0…1 / indeterminate / 阶段文案 */ ;
  func cancel() async }
@MainActor final class BackgroundTaskRegistry { /* register/update/finish/cancelAll */
```

- 三腿协议面一次成型（CONTEXT Specific Ideas：防三腿三实现）；**导入腿首实现** =
  `ImportTaskAdapter` 桥 M2-2-2 `ImportProgress` 快照 + `cancelImport()`（既有
  Controller API，**controller 零改动**——adapter 只读订阅 `importProgress` 发布面 +
  `cancelImport()` 透传，编排点 `LibraryProjectController.swift:241` 不入修改面，
  checker E3）；`ImportModeDialog`/`ImportProgressView` 本体零 diff，
  呈现迁入新壳底部栏 + 任务对话框双面（同一 registry）。
- 导出腿 M2-9 消费、AI 腿 M2-10 消费——协议不预留这两腿专属字段（progress/cancel 已
  足；需要时届时协议演进化，禁提前设计）。

## read_first

1. `.work/gsd/phases/m2-3-ui-shell/M2-3-CONTEXT.md`——裁决正本（D1..D12 + Reusable
   Assets 表 + 用户修订尾注）。
2. `.work/gsd/phases/m2-2-library-project/M2-2-3-SUMMARY.md`「M2-3 数据接口面清单」——
   LibraryQueries/ExifSearchParser/SmartAlbumStore 逐签名（壳零 SQL 的引用正本）。
3. `App/Sources/Lightamer/UI/ContentView.swift`——gate 分叉全貌 + ProjectWorkspaceFace
   （`:655`）演进落点；legacyBody 分支禁触区。
4. `App/Sources/Lightamer/Library/LibraryProjectController.swift`——项目生命周期 +
   ImportProgress 快照面（KD-7 适配源）。
5. `LightamerCore/Sources/Session/SessionThumbnailProvider.swift`——`embeddedPreview:411`
   / `prioritize:262` / `cancelAll:276`（档 A 消费面；**该文件本身禁改**）。
6. `LightamerCore/Sources/Session/ThumbnailDiskStore.swift`——public init(directory:)
   `:40` / write `:57` / read `:75`（KD-4 盘缓存复用面）。
7. `App/Sources/Lightamer/UI/LightamerApp.swift:1108-1352`——9 CommandMenu/CommandGroup
   + 25 keyboardShortcut 实态（KD-6 触点全表）。
8. `App/Sources/Lightamer/UI/Theme/LightamerColors.swift`——legacy 色板形态（并存参照，
   禁改）。
9. `AGENTS.md`「Phase 2 架构增量」节（目录惯例/L013/L014）。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits 全英文、subject ≤72 字符祈使句、
   body 写 what+why + 同批 md 清单）；只 add 本任务申报文件；**不 push**；git add 用
   `.work/gsd/...` 真路径（`.planning` 链接垫片不穿透）。
2. **构建纪律**：`caffeinate -dis` 包裹一切构建；**不加 `-derivedDataPath`**；新建
   .swift 文件后同 commit 内跑 `tuist generate`（T1/T2 批量建文件 → generate 一次，
   后续任务零新文件不重复跑）。
3. **测试纪律**：单测命令 = `Scripts/test-direct.sh '<Class>'`；判据 = Executed 计数行 +
   failures 行双读（L028）。**回归基线 = 2049/13skip/0fail**。每任务全套 suite 绿、
   0 fail；在案 flake（相邻渲染域负载型轮换挂）隔离复跑 ×3 归因入 SUMMARY 不计违约。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
5. **架构红线**：`LightamerCore/` **零改动**（含 Session 域 ThumbnailDiskStore/
   SessionThumbnailProvider 只消费不修改）；legacyBody 树资产（SidebarView/
   SessionBrowserView/CullingView/FilterBarView/CatalogBrowser*/SettingsView.swift、
   `ContentView` legacyBody 分支）零 diff；`ContentView.swift` 只动 gate=false 分支内层
   与 ProjectWorkspaceFace 演进；新 UI 全量 `String(localized:)` 键（zh 值可滞后，D9）；
   T7 收口 `git diff --stat` 核对申报一致。

## Tasks

### T1 ThemeTokens 暗色玻璃 tokens 单一来源

- **read_first**：上列 1/8/9。
- **action**
  1. 新建 `App/Sources/Lightamer/UI/Theme/ThemeTokens.swift`（KD-1 家族全量：
     cardSurface/cardBorder/windowBackground/textPrimary/textSecondary/accent/
     selectedRing/busyDim；`static let` 全 precomputed；头注声明「新壳唯一色彩来源 +
     数值自写（D1 禁拷 GPL 数值）」）。
  2. 新建 `Tests/LightamerTests/ThemeTokensTests.swift`：token 全非 nil + 家族完备性
     （七族逐一在册）+ 暗/亮判别断言（相对亮度序：windowBackground < cardSurface <
     textPrimary）+ `accessibilityIdentifier` 稳定面（**marker 断言 T2 补验（m8）**——
     T1 只落 token 稳定面基座，视图级 marker 断言随 T2 WorkspaceRoutingTests 落地）。
  3. 机检：`git grep -En '#[0-9A-Fa-f]{6}' App/Sources/Lightamer/UI/Shell
     App/Sources/Lightamer/Library/Views` —— T1 时点仅 ThemeTokens.swift 命中（AC 表 #1
     逐 plan 收口复跑）。
- **验收标准**
  - [ ] tokens 七族在册断言全绿；亮暗序断言全绿。
  - [ ] 裸 hex grep：Shell/ + Library/Views/ 仅 ThemeTokens.swift 命中。
  - [ ] 全套回归 `0 fail`（基线 2049 + 新增）。

### T2 AppPhase 双工作区路由 + WorkspaceHost + ProjectWorkspaceFace 演进

- **read_first**：上列 1/3/4。
- **action**
  1. 新建 `UI/Shell/WorkspaceModel.swift`（KD-2：AppPhase 穷举、双态保留结构、
     `openEditor/closeEditor/switchPhase` 保留读写、`isSearchDialogPresented` 呈现布尔
     （⌘F，P2 消费——m6）；`@Observable`）。
  2. 新建 `UI/Shell/WorkspaceHostView.swift`：gate=false 壳根——phase switch 渲染
     library face / editor face + 切换过渡；顶部 TopBar slot（项目名 + 相面命令按钮，
     P2/P3 填充）；`accessibilityIdentifier("shell.workspace.host")` marker。
  3. 新建 `UI/Shell/EditorWorkspaceShellView.swift`（P1 骨架态：四区 slot 占位——左轨/
     视口/左胶片条位/右栏，空态文案 `<Feature> arrives in M2-3/P3` 家族）。
  4. 修改 `ContentView.swift`：gate=false 分支内层 ProjectWorkspaceFace →
     WorkspaceHostView（ProjectWorkspaceFace 降为 library face 之一部分——项目名区 +
     Welcome 入口；`library.project.workspace` marker 保留）；legacyBody 分支**零字节
     改动**。
  5. 新建 `Tests/LightamerTests/WorkspaceRoutingTests.swift`：往返无损逐字段（filter
     rules/sort/selectedIDs/pageAnchor/scrollPosition）；AppPhase 穷举编译证明（switch
     禁 default）；gate=false host marker + gate=true legacy marker（既有
     LibraryLegacyGateTests 零改动全绿对账）。
- **验收标准**
  - [ ] 往返无损断言全绿；穷举 switch 零 default（编译器 + `git grep "case .editor"`）。
  - [ ] `library.project.workspace`/`shell.workspace.host` marker 断言在册；
        LibraryLegacyGateTests 零改动全绿。
  - [ ] 全套回归 `0 fail`。

### T3 LibraryGridModel 集合态单源 + 缩略图桥

- **read_first**：上列 2/4/5/6 + `LightamerCore/Sources/Library/LibraryQueries.swift`
  （接口签名逐个对齐，禁凭记忆）。
- **action**
  1. 新建 `Library/LibraryGridModel.swift`（KD-3 全量：filter/sort/游标/选中/当前图/
     isExhausted/filter 变更重置；Task 注入隔离供单测）。
  2. 新建 `Library/LibraryThumbnailBridge.swift`（KD-4：档 A/B 裁决 + ThumbnailDiskStore
     + NSCache LRU + 并发 ≤4 + 请求合并 + prioritize/cancel 窗口接口）。
  3. 新建 `Tests/LightamerTests/LibraryGridModelTests.swift`：真 `.lalb` fixture（复用
     M2-2-3 LibraryQueriesTests fixture 模式）——keyset 逐页不重不漏全走查 + NULL 尾段
     封底 + filter/sort 变更重置 + 选中/当前图状态机 + 五键白名单透传。
  4. 新建 `Tests/LightamerTests/LibraryThumbnailBridgeTests.swift`：has_edits 双档裁决
     （档 A 不渲管线/档 B 走管线 mock 缝）+ 盘缓存命中零重产 + LRU 驱逐 + 并发上限
     + in-flight 合并计数。
- **验收标准**
  - [ ] 分页三断言（不重/不漏/NULL 封底）全绿；filter 重置断言全绿。
  - [ ] 桥四断言（双档/盘缓存/LRU/合并）全绿。
  - [ ] 全套回归 `0 fail`。

### T4 FilmstripView 左竖向胶片条组件

- **read_first**：上列 2/5 + `App/Sources/Lightamer/UI/EditorAreaView.swift`（
  ZoomHUD marker 惯例参照，禁改该文件）。
- **action**
  1. 新建 `UI/Shell/FilmstripView.swift`（KD-5：List 竖向虚拟化 + 行高常量 + 窗口信号
     → 桥 prioritize/cancel + 选中环 + 当前图 accent + `filmstrip.list`/
     `filmstrip.row.<id>` marker；消费 LibraryGridModel，零集合态复制）。
  2. 新建 `Tests/LightamerTests/FilmstripModelTests.swift`：1 万行挂载 + 可见窗口外零
     缩略图请求（计数断言，prefetch 常数上界）+ 选中滚动锚更新 + 空集合空态。
  3. BENCH| 观察行：万行窗口滚动请求总数（非门，落 SUMMARY）。
- **验收标准**
  - [ ] 万行窗口化断言全绿（窗口外零请求）；选中锚断言全绿。
  - [ ] 全套回归 `0 fail`。

### T5 顶栏 + 菜单 IA 收纳（Session 死路由门控）

- **read_first**：上列 7 + `.work/gsd/phases/m2-2-library-project/M2-2-4-SUMMARY.md`
  （gate 面语义 + File 菜单 inert 登记）。
- **action**
  1. 新建 `UI/Shell/MenuCommandSet.swift`（KD-6 纯函数：gate × phase → 命令 id 集；
     Session 四死路由/项目五命令/工作区两命令/View 可见性三 toggle 全表）。
  2. 修改 `LightamerApp.swift`：CommandMenu/CommandGroup 消费 MenuCommandSet——Session
     四项包进 gate 条件（gate=true 分支语句字节不变）；新增项目命令回路 + 工作区切换
     命令 + View 可见性 toggle 占位；撞键 Session 键位在 gate=false 让位（D11 保守表）。
  3. WorkspaceHostView TopBar 挂项目名 + phase 切换按钮（⌘W 回图库等价入口）。
  4. `WorkspaceRoutingTests` 补 MenuCommandSet 矩阵（gate×phase 全组合逐 id 断言）+
     `git grep` 断言：gate=false 路径 Session 命令构造零直接出现。
- **验收标准**
  - [ ] MenuCommandSet 矩阵全绿；Session 四死路由 gate=false 移除 + gate=true 原样
        （**逐 hunk 评审（m7）**：`git diff <T5 起点 SHA>..HEAD --
        App/Sources/Lightamer/UI/LightamerApp.swift` 逐 hunk + grep 核 gate=true 分支
        语句零改动；无逐字节机检，评审结论入 SUMMARY）。
  - [ ] 全套回归 `0 fail`；LibraryLegacyGateTests 零改动全绿。

### T6 BackgroundTaskHosting 协议 + 导入腿接入

- **read_first**：上列 4 + `App/Sources/Lightamer/Library/ImportProgressView.swift`
  （快照呈现面参照，禁改）+ `App/Sources/Lightamer/Library/ImportModeDialog.swift`
  （禁改）。
- **action**
  1. 新建 `Library/BackgroundTaskHosting.swift`（KD-7 协议 + registry：register/
     update/finish/cancel/cancelAll；@MainActor；Sendable 快照值类型）。
  2. 新建 `Library/ImportTaskAdapter.swift`：ImportProgress 快照 → handle（单调进度 +
     per-file 阶段文案 + cancel 透传 `cancelImport()`）。
  3. 新建 `UI/Shell/BackgroundTaskBarView.swift`：底部栏（进行中任务行 + 进度 + 取消）
     + 任务对话框宿主（同 registry 双呈现；`tasks.bar`/`tasks.dialog` marker）。
  4. WorkspaceHostView 挂底部栏；导入腿编排归属钉死（**checker E3**）：adapter **只读
     订阅** `LibraryProjectController.importProgress`（`:47` 发布面）+ `cancelImport()`
     透传（`:267`）——**controller 零改动**（`LibraryProjectController.swift:241`
     runImport 编排点不入修改面），ImportModeDialog 弹出流程不变。
  5. 新建 `Tests/LightamerTests/BackgroundTaskRegistryTests.swift`：注册/更新/完成/
     取消/多任务并发注册表语义 + 导入腿单调快照（复用 M2-2-2 快照序列 fixture 模式）
     + 双呈现一致性（bar 与 dialog 同源断言）。
- **验收标准**
  - [ ] registry 语义 + 导入腿单调/取消断言全绿；双呈现同源断言全绿。
  - [ ] ImportModeDialog/ImportProgressView/**LibraryProjectController.swift** 零 diff
        （`git diff --stat` 核——adapter 只读订阅 + cancel 透传，controller 不入修改面，
        checker E3）。
  - [ ] 全套回归 `0 fail`。

### T7 收口——SUMMARY/DECISIONS + 续接点

- **read_first**：本 plan AC 表 + `.work/GOAL-STATE.md` 续接点节。
- **action**
  1. AC 逐条机检 + 全套回归终跑（计数/秒数入 SUMMARY）。
  2. 落盘 `M2-3-1-SUMMARY.md`（测试数变化/KD 确认/裸 hex grep 证据/BENCH 观察行）+
     `M2-3-1-DECISIONS.md`（KD-1..7 执行确认 + 偏差归因）。
  3. `.work/GOAL-STATE.md` 续接点追加（M2-3-1 完成 + 下一步 = M2-3-2）；LESSONS 如踩坑。
  4. `git diff --stat` 核对文件边界与 front-matter 一致（纪律 5）。
- **验收标准**
  - [ ] AC 表全绿；SUMMARY/DECISIONS/GOAL-STATE 同批落盘；diff 边界无越界文件。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | ThemeTokens 七族在册 + 亮暗序；新壳目录裸 hex 仅 ThemeTokens.swift 命中 | ThemeTokensTests + `git grep -En '#[0-9A-Fa-f]{6}'` 命中集断言 |
| 2 | AppPhase 双态路由往返无损（filter/sort/选中/锚/滚动位逐字段）；穷举 switch 零 default | WorkspaceRoutingTests 逐字段断言 + 编译穷举证明 |
| 3 | gate=false = WorkspaceHostView（`shell.workspace.host` marker）；gate=true = legacyBody 原样；LibraryLegacyGateTests 零改动全绿 | marker 断言 + 既有测试零 diff 全绿 + `git diff` ContentView legacy 分支空 |
| 4 | LibraryGridModel keyset 分页不重不漏 + NULL 封底 + filter 变更重置 + 五键白名单 | LibraryGridModelTests（真 .lalb fixture） |
| 5 | 缩略图桥双档裁决（has_edits）+ 盘缓存 `.lathumbs` 命中零重产 + LRU + 并发 ≤4 + in-flight 合并 | LibraryThumbnailBridgeTests |
| 6 | 胶片条 = 竖向 List 虚拟化；1 万行挂载窗口外零请求（prefetch 常数上界）；选中滚动锚 | FilmstripModelTests 计数断言 |
| 7 | MenuCommandSet 矩阵（gate × phase 全组合）：Session 四死路由 gate=false 移除/gate=true 原样字节不变；项目/工作区命令回路在册 | MenuCommandSet 单测 + **逐 hunk 评审（m7）**：`git diff <P1 起点 SHA>..HEAD -- App/Sources/Lightamer/UI/LightamerApp.swift` 逐 hunk + grep 核 gate=true 分支零语句改动（结论入 SUMMARY） |
| 8 | BackgroundTaskHosting 协议 + registry 四态 + 导入腿单调快照 + 取消 + 双呈现同源；ImportModeDialog/ImportProgressView/LibraryProjectController.swift 零 diff | BackgroundTaskRegistryTests + `git diff --stat`（E3：controller 只读订阅面，不入修改面） |
| 9 | 新 UI 全量 `String(localized:)` 键、零裸字面 `Text("…")` LocalizedStringKey 漂移（verbatim 仅限沿用 M2-2 惯例处） | `git grep -n 'Text("' App/Sources/Lightamer/UI/Shell App/Sources/Lightamer/Library` 白名单核对 |
| 10 | 全套回归 0 fail，计数 ≈ 2049 + 25..35 | test-direct.sh Executed/failures 双读 |
| 11 | diff 边界 == 申报文件集；`LightamerCore/` 零 diff；legacyBody 树资产零 diff | `git diff --stat` + `git diff --name-only` 逐文件核对 |

## 风险与边界

- **List 万行虚拟化性能**：SwiftUI List 在万行 + 异步缩略图场景的滚动帧率不可静态保证
  ——第一约束设计（固定行高/窗口化请求/合并去重）+ 万行计数单测；**真机滚动帧率 =
  P4 T2「交互/性能观察清单」①（E4 接账，非门）**；若走查不达标，后备 = 行高降档 +
  预取窗收窄，不推倒 List 选型。
- **缩略图档 B 首渲成本**：has_edits 大图管线渲一档非嵌入预览路径，首屏可能忙——桥
  层并发上限 + prioritize 已缓解；档 B 产能观察项挂 SUMMARY，M2-2-3 挂账「缩略图首屏」
  的量测销账在 P2（网格接线后）。
- **菜单 IA 撞键**：⌘N/⌘O 等在 M1 是 Session 命令、新壳改绑项目命令——gate=true 通道
  键位不变（字节级），gate=false 键位按 KD-6 表；真实按键走查 = P4 T2「交互/性能观察
  清单」②（E4 接账）。
- **@Observable + @MainActor 测试面**：WorkspaceModel 单测在 test host MainActor 域内
  跑（既有 MainActor 模型测试先例）；禁为了可测把状态拆出 actor（路由状态就是主线程态）。
- **新建文件批量**：T1/T2 一次建齐 Shell/ 基础件 + 测试，`tuist generate` 一次；后续
  任务新文件随任务 generate。

## 提交约定

- T1 `feat(ui): dark glass theme tokens as single color source`
- T2 `feat(ui): two-workspace app phase routing with lossless state`
- T3 `feat(library): grid collection model and dual-tier thumbnail bridge`
- T4 `feat(ui): vertical virtualized filmstrip component`
- T5 `feat(ui): menu ia consolidation with gated session dead routes`
- T6 `feat(library): background task registry with import leg`
- T7 `docs(m2-3): close out plan 1 ui shell skeleton`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。

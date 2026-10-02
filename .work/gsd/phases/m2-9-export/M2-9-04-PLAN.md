---
phase: m2-9
plan: "M2-9-04"
title: "检查器 Export 页 + App 装配点（wave 3）——Inspector 内嵌 Export 页（OQ-1 A：M2 面新页、legacy sheet 冻结）五节面板（Destination 落点记忆+子文件夹 / File Naming 模板编辑器+预设 / Metadata&Color 单开关+EMBED-OMIT / SDR 格式尺寸四模式+高级折叠区 / Queue 四态+进度）+ 入队装配（instancesOverride 投影 + effectiveDrtRecord + 模板 sequence + 质量四键 + exifSoftware）——渲染/编码消费面（01-03）全部到位后的纯 App 波"
wave: 3
depends_on: ["M2-9-01", "M2-9-02", "M2-9-03"]
autonomous: true
requirements: [M2EXP-01, M2EXP-02, M2EXP-03, M2EXP-04, M2EXP-05]
estimated_new_tests: 18
bundles: [App]
files_modified:
  - App/Sources/Lightamer/Export/ExportInspectorView.swift        # 新建：Export 页五节（SwiftUI；zh/en String Catalog 键随手落）
  - App/Sources/Lightamer/Export/ExportNamingEditor.swift         # 新建：模板编辑器（预设下拉 + token 插入 + 模式串 + live 预览 + 存/改名/删）
  - App/Sources/Lightamer/Export/ExportQueueFaceView.swift        # 新建：队列节（四态行 + 36 行帽 + 汇总行 + 进度 + add/clear）
  - App/Sources/Lightamer/State/ExportState.swift                 # 修改：additive M2 装配面（enqueueExportM2 + 目标推导 M2 腿 + 记忆键读写）——既有方法体零 diff
  - App/Sources/Lightamer/State/InspectorState.swift             # 修改：additive 页开关（exportPageActive，KD-1——checker 回注 E5 登记）
  - App/Sources/Lightamer/UI/InspectorView.swift                  # 修改：Export 页挂载（页开关 + 切换臂）
  - App/Sources/Lightamer/UI/ContentView.swift                    # 修改：M2 面 toolbar 导出路由检查器页（legacy sheet 臂零 diff）
  - Resources/Localizable.xcstrings                              # 修改：zh/en 键（纪律 3 自认会碰——checker 回注 E5 登记）
  - Tests/LightamerTests/ExportInspectorFaceTests.swift           # 新建【App】
  - Tests/LightamerTests/ExportAssemblyTests.swift                # 新建【App】
  - Tests/LightamerTests/ExportMemoryKeysTests.swift              # 新建【App】
  - Project.swift                                                 # 修改：双登记
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt    # 修改：双登记
---

# Plan M2-9-04 — 检查器 Export 页 + App 装配点（wave 3）

> **性质**：纯 App 波——Core 渲染/编码消费面（01-03）全部到位，本 plan 落 ROADMAP
> 明文的「导出队列 UI（检查器内）」与 App 装配点接线（D-M2-9-CONTEXT-4 的最终消费
> 形态）。对照 Alcedo `ExportInspectorPanel.qml`（RESEARCH §1.5 控件/校验域/默认值
> 逐节实测）。红线：**legacy 面冻结**——`ExportPanelView.swift` 除编译性补臂外零
> diff；`LibraryLegacyGate` 回切语义不破坏（M2-2-4 剥离门纪律）。

## 已定裁决（硬约束，不得重开）

- **OQ-1（A：检查器新页）**：新建 Inspector 内 Export 页；M2 面导出入口（toolbar）
  打开该页；legacy sheet（`ContentView.swift:337-340` 挂载 + `ExportPanelView`）
  **在 legacy gate 内保留原样**（回切后与 M2-2 前同构）；M2 面零 sheet。
- **OQ-3（B：最近使用跨会话记忆）**：默认落点 = UserDefaults 键 `export.lastDirectory`
  （bookmark/URL 语义随既有 destinationSection 先例——sandbox 书签与否以现状对齐）；
  首用（键空）回落 = 当前选中首图所在目录；目录选择器记忆写回。
- **OQ-10（A：四格式各一键）**：`export.jpegQuality` / `export.heicQuality` /
  `export.avifQuality` / `export.webpQuality`（0...1 Double）；面板 prepare 载入、
  导出发起与离页写回（Alcedo QML:271-288 生命周期同构）。
- **OQ-11（B：子文件夹默认关 + 本地化默认文案）**：开关默认关；默认文案 zh「导出」
  / en `"Processed"`（String Catalog 双语，L25 zh 键纪律）。
- **OQ-12（A：高级折叠区）**：`allowUpscale`（默认 false）+ `maximumEdgePixels`
  （默认 0=关）两控件在 DisclosureGroup 折叠区暴露；主面板保 Alcedo 同构简洁。
- **四态映射**：`ExportJobState` 现值直接映射——pending→Queued、rendering/encoding→
  Exporting、done→Done、failed/cancelled→Failed（取消归 Failed 档，DECISIONS 注记；
  无新状态、无队列引擎感知）。预览 36 行帽 + `…(N more)` 汇总行（Alcedo QML:47/129）。
- **模板预设**：OQ-9 面板消费——预设下拉（3 内置 + 用户 + Custom 尾项）+ 11 枚
  token 插入按钮 + 模式串编辑 + **live 预览**（样本 = 队列首行名，无队列 = 当前图
  stem 合成）+ 模板无效 = 该节红字 + startExport 禁用（Alcedo QML:64 同构）。
- **入队装配（D-M2-9-CONTEXT-4 终态）**：逐图构造——`instancesOverride` =
  `EditorState.history.projection(upTo:)` 有效面（instances + layerSnapshot 随
  active 链/版本走；**M2-8 交接零新依赖**）+ `drtTail` = `DrtTailParams(record:
  effectiveDrtRecord() ?? DrtRecord(), postOpNames: <NodeOwnershipCatalog.
  drtPostOpNames ∩ 启用集——与 PipeCoordinator 同法>)` + `drtOutput` = 同 record
  （peak 闸门由 03 的 validate 兜底）+ `metadataPolicy`/`embedICC`/`naming`/
  `collisionPolicy`/`subfolder`/`exifSoftware`（`Lightamer <版本>`）+ 质量旋钮回填
  variant.format。**多选批量**：目标集 = M2 工作区当前选中（库网格多选），无选中 =
  当前编辑图；`ExportState.targetRelPaths`（session 语义）不进 M2 面——新 M2 目标
  推导腿 additive。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 页挂载形态（Inspector 列内页切换）

- `InspectorState` additive 页开关（如 `exportPageActive: Bool`，默认 false）；
  `InspectorView` body 顶部分支：active → `ExportInspectorView` 全列（Layers 列表
  与模块面板让位）；inactive → 现体逐字节。toolbar 导出按钮：M2 face（gate=false）
  → 置 exportPageActive + inspector 可见；legacy face → 现 sheet 路径**零 diff**。
- 队列生命周期：`ExportState.rebuildQueueForSession()` 语义复用——项目打开事件
  （LibraryProjectController open 面）触发 rebuild（M2 工作区无 Session 概念，
  命名可后定，重置点 = 项目切换）；无项目 → 面板空态（ContentUnavailableView，
  Alcedo 队列节空态同构）。

### KD-2 五节面板（节序对齐 Alcedo QML）

1. **Destination**：目录（显示串 + Browse `NSOpenPanel`）+ 记忆写回 + 子文件夹
   checkbox + 文案输入（默认本地化）+ effectiveOutDir 拼接显示。
2. **File Naming**：`ExportNamingEditor`（KD-3）。
3. **Metadata & Color**：单开关「Include photo metadata」+ 固定说明文案（zh/en——
   Alcedo QML:621 语义）+ 「Embed output ICC profile」checkbox + DRT 编码三元组
   只读行（space/EOTF/peak——来自当前图 effectiveDrtRecord，联动可见性即 OQ-7 的
   UI 表达；无图 = 空态）。
4. **SDR Export**：格式 Picker（六格式）/ 位深 / 质量滑杆（四格式，键回填记忆）/
   PNG level / TIFF 压缩 / 尺寸四模式 Picker + 各模式字段（longEdge/bounds W×H/
   physical 双维 + 单位 + DPI）+ 高级折叠区（OQ-12）。校验域对齐模型域（1...100000
   像素 / 1...2400 DPI / 物理双精度 2 位 0.01...100000——Alcedo QML:802-1008 域与
   我方模型域的差集已在 01 DECISIONS 记录，UI 按模型域禁越界值）。
5. **Queue**：add 选中入队 + clear + 四态行（图标 + 文件名 + 状态点）+ 36 行帽 +
   `…(N more)` + completed/total 进度条 + 错误摘要红字 + per-job retry（快照已有
   语义）。

### KD-3 ExportNamingEditor（模板编辑器）

- 预设下拉：内置 3（NamingTemplateStore 常量）+ 用户预设（store）+ Custom 尾项；
  选中预设 = 模式串填充；存预设（命名 sheet/inline）+ 改名 + 删除（内置不可删）。
- token 按钮 11 枚（`{source}`/`{date:…}`/`{cameramake}`/`{cameramodel}`/`{lens}`/
  `{iso}`/`{aperture}`/`{shutter}`/`{focal}`/`{rating}`/`{sequence:0000}`）插入
  光标位（简化：追加尾亦可，DECISIONS 记录）。
- 解析反馈 = M2-9-01 的 `parse` typed 错误直接展示（本地化文案 + 原始 message）；
  无效 = 队列节 add/start 禁用。
- live 预览 = `render` 到样本上下文（首图 stem/当前图 stem + sequence=1 + 空捕获
  字段缺省渲染）。

### KD-4 装配点（`ExportState` additive M2 面）

- 新方法 `enqueueExportM2(...)`（既有 `enqueueExport` 方法体零 diff——legacy sheet
  继续走旧面）：输入 = 图 URL 集 + 各图装配载荷（KD-0 的 override/drtTail）+ 面板
  参数（sizing/format/color 政策/命名/冲突/子目录/落点）→ variant 组 + quality
  写回 + queue.enqueue（drtTails per-image 载体）。
- sequence = 选中序（1 起）；`exifSoftware` = `Lightamer <CFBundleShortVersionString>`。
- **注入式纪律**：新视图 body 零 UserDefaults 直读（记忆键经 ExportState/store 读，
  D-EXEC-1 同款）；inspector 页开关不进 UserDefaults（会话内状态，非用户偏好——
  与 inspectorVisible 布局记忆区分，DECISIONS 注记）。

### KD-5 测试面（App bundle，headless 可测优先）

- 页挂载：gate=false 下 toolbar 路由 → exportPageActive（InspectorView AX 树可见
  Export 面）；gate=true（legacy 注入）下 sheet 路径不变 + Export 页不可达
  （剥离门双向）。
- 装配：合成 EditorState/history 投影 + effectiveDrtRecord 注入 → enqueueExportM2
  捕获 Request 面（instancesOverride/drtTail record/naming sequence/policy/质量
  回填/子文件夹拼接）逐字段断言（真链形态——HistoryStack 投影非 stub）。
- 记忆键：四质量键 round-trip + lastDirectory 写回 + 首用回落；store 损坏 JSON 降级。
- 模板编辑器：预设选择/CRUD/无效禁用/live 预览（纯状态层测——视图渲染细节不逐
  像素断言，AX/状态断言为界）。

## read_first

1. `M2-9-CONTEXT.md` 裁决记录 + OQ-1/3/10/11/12 + RESEARCH §1.5（QML 控件/校验域/
   默认值逐节）+ §2.4（App UI 现状锚点）。
2. M2-9-01/02/03 PLAN（消费面 API 形状——Request/queue/validate 签名以对应交付源码
   为准）。
3. `App/Sources/Lightamer/Export/ExportPanelView.swift`（既有 sheet 结构与
   destinationSection/postActionsSection 先例——**新页不复用其代码路径，但目录选择
   /书签/toast 惯例对齐**）+ `App/Sources/Lightamer/State/ExportState.swift` 全文。
4. `App/Sources/Lightamer/UI/ContentView.swift`（:147 exportPanelRequested / :214
   InspectorView 挂载 / :337 sheet / :647+ ProjectWorkspaceFace）+
   `UI/InspectorView.swift`（body 分支点）。
5. `App/Sources/Lightamer/State/PipeCoordinator.swift`（:595-607 drtCarrier 一致性
   守卫 + DrtTailParams 构造同法）+ `LightamerCore/Sources/Pipe/History/HistoryStack.
   swift`（projection/effectiveDrtRecord 面）。
6. `App/Sources/Lightamer/Library/LibraryProjectController.swift`（项目打开事件挂点
   ——KD-1 队列 rebuild 触发源）。
7. 行号锚以**符号检索为准**——实测行号有漂移（checker 回注 m2：PipeCoordinator
   drtCarrier 实际 :595-604），执行期以符号名定位，行号偏差不作违例。

> checker 回注（2026-10-02）[E5]：KD-1 的 `InspectorState` additive 页开关落点
> （`App/Sources/Lightamer/State/InspectorState.swift`，:22 实核存在）与纪律 3 的
> `Resources/Localizable.xcstrings` 原均不在 front-matter files_modified——与
> 纪律 6 收口核对自爆（T4 原 AC 措辞「front-matter + .xcstrings」即自认会碰后者）。
> 两文件已登记；T4 验收措辞同步为「diff 边界 == front-matter」。

## 纪律（强制）

1. 提交/边界/收口纪律同 M2-9-01；测试双登记；全套基线 = 01-03 终态计数（2577+增量）。
2. **legacy 冻结机检**：`ExportPanelView.swift` 仅许编译性补臂（如 sizing kind 映射
   新 case 不可达臂——01 已列）；`ContentView.swift` legacy sheet 臂/legacy body
   分支零 diff（diff 逐 hunk 审，改动限 M2 face 路由 + Inspector 挂载）。
3. zh/en String Catalog 键随手落（`Resources/Localizable.xcstrings`——**本 plan
   允许改**，L25 zh 键 + locale 纪律；`zh-audit --check` 任务级自跑）。
4. 无图/无项目空态必须可达且不崩（M2-8 FINDING-A sheet 环境注入教训——新页若用
   sheet 呈现任何子流程，内容面显式重注入 Observable，`SheetEnvironmentInjection
   Tests` 先例）。

## Tasks

### T1 页挂载 + Destination/Naming 两节（KD-1/KD-2/3 骨架）

- **action**：InspectorState 开关 + InspectorView 分支 + ContentView M2 路由 +
  ExportInspectorView 骨架（节 1/2 完整）+ ExportNamingEditor + 记忆键读面
  （lastDirectory）+ zh/en 键。
- **验收标准**
  - [ ] M2 face 导出入口开检查器页（AX 可见）；legacy gate 下 sheet 路径行为不变
        （双向剥离门测试绿）。
  - [ ] 无效模板 → add/start 禁用 + 错误文案；预设 CRUD 走 store 测试面。

### T2 Metadata&Color/SDR 两节（KD-2 节 3/4）

- **action**：单开关 + EMBED/OMIT checkbox + DRT 三元组只读行 + 格式/位深/质量/
  尺寸四模式 + 各模式字段与校验域 + 折叠区（allowUpscale/maximumEdgePixels）+
  质量四键读写 + zh/en 键。
- **验收标准**
  - [ ] 尺寸四模式字段按模式显隐正确；越界值禁入（模型域校验）。
  - [ ] 质量键四键 round-trip 测试绿；折叠区默认 false/0。

### T3 Queue 节 + 装配点（KD-2 节 5/KD-4）

- **action**：ExportQueueFaceView（四态行/36 帽/汇总/进度/错误摘要/retry）+
  ExportState M2 目标推导 + enqueueExportM2 装配（投影/drtTail/模板 sequence/
  policy/exifSoftware/质量回填）+ 项目打开 rebuild 挂点 + 装配测试（KD-5）。
- **验收标准**
  - [ ] 装配逐字段断言绿（instancesOverride=投影真链 / drtTail.record=
        effectiveDrtRecord ?? 默认 / sequence 批内递增 / peak 闸门兜底触发 typed）。
  - [ ] 四态映射断言绿；36 行帽与汇总行状态层测试绿。

### T4 波次收尾核对

- **action**：App bundle 终跑 + 全套 `--all`（前报备）+ `git diff --stat` 对表
  （ExportPanelView/ContentView 逐 hunk 复审）+ zh-audit `--check` 自跑 PASS +
  DECISIONS 底稿（KD-4 注记 / 页开关非持久 / token 插入位裁决 / 四态取消归档）。
- **验收标准**
  - [ ] 全套 0 fail；zh-audit PASS；legacy 冻结机检过；diff 边界 == front-matter
        （.xcstrings 已登记 front-matter——checker 回注 E5，原「+ .xcstrings」后缀
        不再需要）。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | OQ-1 A：M2 面检查器 Export 页可达；legacy sheet 冻结（gate 双向测试绿） | 测试 + `git diff` 逐 hunk |
| 2 | 五节齐备且默认值对表 Alcedo（质量记忆/子文件夹关/折叠区 false/0/四模式字段） | 测试 + 走查 |
| 3 | 落点记忆（lastDirectory）+ 首用回落源图目录 | 测试 |
| 4 | 质量四键 round-trip；键名拼写 = 登记值 | 源码 grep + 测试 |
| 5 | 装配面逐字段断言（投影/drtTail/sequence/policy/exifSoftware） | ExportAssemblyTests |
| 6 | 模板无效 → 禁用 + 错误展示；live 预览绿 | 测试 |
| 7 | 队列四态 + 36 帽 + 进度 + retry 面绿 | 测试 |
| 8 | zh-audit `--check` PASS；.xcstrings locale 纪律 | 工具输出 |
| 9 | App bundle 0 fail；双登记闭环；全套基线精确对账 | bundle 行 |

## 风险与边界

- **M2 目标集语义**：库网格多选状态源（CatalogBrowser/Library 面的 selection 载体）
  若与 Sessions relPath 语义不齐 → M2 腿直接持 URL 集（不做 relPath 投影），
  queue.enqueue 的 relPath 载体传展示名（DECISIONS 记录；快照显示语义不受影响）。
- **GUI 不可自动化域**：真机观感（面板手感/滚动/暗色对比）= 走查项归 M2-9-05，
  本 plan 状态层测试为界，禁假完成（E1 纪律）。
- **queue rebuild 时机**：项目打开事件若与队列 in-flight 冲突（导出中切项目）——
  既有 session-switch 语义已裁决（旧实例 detached stragglers 完成入虚空，D-11-8），
  M2 同款照搬，无新机制。

## 提交约定

- T1 `feat(m2-9): inspector export page with destination and naming editor`
- T2 `feat(m2-9): metadata-color and sdr sizing sections with quality memory`
- T3 `feat(m2-9): queue face and m2 export assembly wiring`
- T4 `test(m2-9): wave-3 reconciliation and legacy freeze audit`
- 全英文；body 写 what+why；不 push。

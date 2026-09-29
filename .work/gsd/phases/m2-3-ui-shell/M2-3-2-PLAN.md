---
phase: m2-3
plan: "M2-3-2"
title: "图库面——缩略图网格（keyset 无限滚动 + 双击进编辑器 + M2-2-3 挂账销账）；Album Inspector 面板（Overview 总数卡 + 四分组点击过滤 + Activity view + SEARCH FILTER 区 + 智能相册成员集，壳零 SQL）；全局搜索三合一对话框（EXIF 词法腿真接 Parser，CLIP/全文占位，D8）；Inspector 批量 relink UI（M2LIB-07③）。纯 App 层，Core 零改动"
wave: 2
depends_on: ["M2-3-1"]
autonomous: true
requirements: [M2LIB-05, M2UIW-01, M2LIB-07]
files_modified:
  - App/Sources/Lightamer/Library/Views/LibraryGridView.swift        # 新建（→ tuist generate）：缩略图网格（LazyVGrid + keyset 无限滚动 + 选中/多选/星级角标 + 双击 openEditor；消费 LibraryGridModel + LibraryThumbnailBridge）
  - App/Sources/Lightamer/Library/Views/LibraryInspectorView.swift   # 新建：Album Inspector 右面板（LIBRARY OVERVIEW 总数卡 + 四分组 + ACTIVITY + SEARCH FILTER 区 + SMART ALBUMS 成员集）
  - App/Sources/Lightamer/Library/Views/GlobalSearchDialog.swift     # 新建：三合一搜索对话框（EXIF/CLIP/全文三段；EXIF 腿真接；占位 tab 空态）
  - App/Sources/Lightamer/Library/Views/RelinkSheetView.swift        # 新建：批量 relink sheet（stale 两形态分类呈现 + 换源选择器 + 批量进度）
  - App/Sources/Lightamer/Library/LibraryInspectorModel.swift        # 新建：Inspector 视图模型（四分组/Activity/总数/过滤态渲染源 + 点击载荷 → filter 折叠；纯逻辑可单测）
  - App/Sources/Lightamer/Library/LibrarySearchModel.swift           # 新建：搜索视图模型（parse typed error 映射 + filter.plan 组装 + 提交流）
  - App/Sources/Lightamer/Library/LibraryRelinkModel.swift           # 新建：relink 视图模型（stale 行分类 + 批量编排经 Controller 缝 + BackgroundTaskHosting 注册）
  - App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift           # 修改：library face 挂网格 + Inspector 双栏 + 搜索命令入口 + relink sheet 挂点
  - App/Sources/Lightamer/UI/Shell/WorkspaceModel.swift              # 修改：openEditor 真接线（当前图 → EditorPhaseState；P1 已留缝）
  - Tests/LightamerTests/LibraryGridModelTests.swift                 # 修改：网格接线胶水补充（滚动信号 → loadNextPage 调用计数 / isExhausted 后零调用）
  - Tests/LightamerTests/LibraryInspectorModelTests.swift            # 新建：四分组点击折叠/dayFilter/总数卡/过滤态描述/智能相册成员集（真 .lalb fixture）
  - Tests/LightamerTests/LibrarySearchModelTests.swift               # 新建：parse typed error 四族映射 + plan 组装 + 空串恒真语义 + 提交 → 集合刷新
  - Tests/LightamerTests/LibraryRelinkModelTests.swift               # 新建：stale 两形态分类 + 批量编排单调进度 + 取消 + 完成分类计数
  - .work/gsd/phases/m2-3-ui-shell/M2-3-2-SUMMARY.md                 # 新建（收口任务）
  - .work/gsd/phases/m2-3-ui-shell/M2-3-2-DECISIONS.md               # 新建（收口任务）
  - .work/gsd/phases/m2-2-library-project/perf.md                    # 修改：§A.4「缩略图首屏挂账 M2-3」观察行销账注记（量测值 + 指向 M2-3-2 SUMMARY）
  - .work/GOAL-STATE.md                                              # 续接点追加（收口任务）
  - .work/LESSONS.md                                                 # 如踩坑
---

# Plan M2-3-2 — 图库面（网格 + Album Inspector + 搜索三合一 + relink UI）

> **性质**：纯 App 层 plan——壳零 SQL（M2-2-3 数据接口面清单逐签名消费：`searchPage/
> searchNullTail/overviewCount/groupCounts/activitySeries/dayFilter/currentFilterDescription/
> SmartAlbumStore.evaluate(.library)/ExifSearchParser.parse`）。裁决 = D-M2-3-CONTEXT
> 1/2/8/10 + M2LIB-05 壳半边（OQ-11 切分线：面板/网格/搜索对话框壳与视觉验收归本 phase）。
> 规格锚点 = `research/ALCEDO-FEATURE-MAP.md` §1.2（图库逐件：`ThumbnailGridView`/
> `AlbumInspectorPanel` 四分组名/`GlobalSearchDialog` 三段结构）+ `M2-3-CONTEXT.md`。
>
> P1 缝消费：`LibraryGridModel`（集合态唯一消费者）、`LibraryThumbnailBridge`、
> `WorkspaceModel.openEditor`、`BackgroundTaskHosting`（relink 腿第二实现）。

## 已定裁决（不得重开）

- **D2（OQ-2 A）**：入口 = 图库网格双击图 → 编辑器（本 plan 接线真缝）；编辑器回图库
  保留集合态（P1 保留结构）。
- **D8（OQ-8 A）**：对话框按 Alcedo `GlobalSearchDialog` 三段结构一次成型；**EXIF tab
  消费 `ExifSearchParser.parse`**（typed error 交对话框呈现）；CLIP tab 与 AI 描述/标签
  全文 tab = 占位空态（「Semantic search arrives with M2-10」）；搜索结果直接过滤图库
  网格（`ExifSearchFilter` 集合态），Inspector SEARCH FILTER 区经
  `currentFilterDescription` 同步显示。
- **D9（OQ-9 A）**：新键 `String(localized:)` 随手写、zh 值 P4 补录。
- **M2LIB-07③**：Inspector 批量 relink UI = stale 两形态（`pathMissing`/`volumeAbsent`）
  呈现 + 换源选择 + 批量 relink；数据缝 = M2-2-2 `ImageLinker.relinkRecord`（Core 既有
  public 面，零改动消费）。
- **M2-2-3 挂账**：缩略图首屏观察项量测在本 plan 落账（网格接线后实测，BENCH| 行非门），
  同批销 `perf.md` §A.4 挂账行。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 网格 = LazyVGrid + keyset 无限滚动，双击即编辑器入口

网格视图消费 `LibraryGridModel`（P1 单源，**零集合态复制**）：滚动接近尾部 →
`loadNextPage()`（`searchPage` 前向段 + `searchNullTail` NULL 尾段，`isExhausted`
封底）；单元格 = 桥缩略图 + 星级角标 + 选中玻璃环；**双击 → `WorkspaceModel.openEditor
(imageID)`**（D2 真缝，P1 骨架槽位本 plan 点亮）；单击选中/⌘单击多选（选中态进
`LibraryPhaseState`，胶片条同源高亮）。`accessibilityIdentifier`：`library.grid`/
`library.grid.cell.<id>`。

### KD-2 Inspector 点击语义 = typed 载荷 → FilterPredicateGroup 折叠，面包屑可退

四分组点击全部折叠进**同一份** `ExifSearchFilter.group`（`FilterPredicateGroup`）：

| 分组 | 数据源（M2-2-3 签名） | 点击折叠 |
|---|---|---|
| By Capture Date | `groupCounts(by: .captureDate)` | `LibraryQueries.dayFilter(day)` 既有投影 |
| By Camera Model | `.camera`（typed payload mk+md，Unknown 归一） | camera 谓词臂（FilterField 既有字段，零 SQL） |
| By Labels | `.labels`（星档 tier payload） | rating 谓词臂 |
| By Lens | `.lens` | lens 谓词臂 |
| ACTIVITY | `activitySeries` 日柱序列 | 柱点击 = `dayFilter(day)` 同日期腿 |

再点击已选分组 = 反选（谓词臂移除）；**过滤态面包屑**可逐臂退；SEARCH FILTER 区 =
`currentFilterDescription` typed 渲染源 verbatim 呈现（Alcedo 面板文案 IA 对齐）。总数卡
= `overviewCount`（当前 filter 域，随过滤联动）。面板纯逻辑沉 `LibraryInspectorModel`
（入参 = LibraryQueries 注入），视图零业务。

### KD-3 搜索三合一 = 三段对话框一次成型，EXIF 腿真接、两腿诚实空态

- 结构对齐 Alcedo 三段：模式段（EXIF / CLIP / AI 描述与标签全文三分段卡）+ 输入段 +
  结果应用段。⌘F 打开（Library phase 命令，P1 MenuCommandSet 挂点接线；**呈现态 =
  P1 预埋 `WorkspaceModel.isSearchDialogPresented`，P2 仅在 WorkspaceHostView 消费
  该 bool 挂对话框——m6，不自持状态**）。
- EXIF 腿：输入串 → `ExifSearchParser.parse`；typed error 四族（iso 非法/光圈非法/
  日期 disjoint/unrecognized 词）→ 对话框行内呈现（不弹 alert）；parse 成功 →
  `ExifSearchFilter.plan = plan` → `LibraryGridModel.applyFilter`（网格 + Inspector
  SEARCH FILTER 区同批联动）。空串 = `.isEmpty` 恒真语义（清过滤）。
- CLIP tab / 全文 tab：占位空态 marker `search.tab.clip.placeholder` /
  `search.tab.fulltext.placeholder`，文案「Semantic search arrives with M2-10」家族
  （D3 空态统一族）；**禁放假开关/假结果**。
- `LibrarySearchModel` 纯逻辑单测：typed error 四族逐条映射断言 + 提交流 filter 组装 +
  清空语义。

### KD-4 批量 relink = stale 分类呈现 + 换源选择 + registry 第三腿接入

- 入口 = Inspector（图片域操作区）对 stale 选中行批量发起；`LibraryRelinkModel` 消费
  M2-2-2 `ImageLinker` stale 两形态分类（`pathMissing`/`volumeAbsent`）→ sheet 分组
  呈现（缺失路径组 / 卷缺席组）+ 每组「选择新位置」（NSOpenPanel 缝，既有
  `FileOpenHelper` 同族）→ 批量 `relinkRecord` 编排经 `LibraryProjectController` 既有
  缝（若 Controller 无 relink 编排面，则 App 层直接逐行调 `ImageLinker.relinkRecord`
  ——**禁改 Core**，编排循环在 App 层）。
- 进度 = `BackgroundTaskHosting` 注册（P1 协议第二腿消费）；完成分类计数
  （relived/stillStale/cancelled）入面板行态。

### KD-5 智能相册成员集 = evaluate(.library) 闭环消费

智能相册（albums.type == filter）在 Inspector SMART ALBUMS 区列出；选中 →
`SmartAlbumStore.evaluate(id:, domain: .library, sessionStore: nil, catalogStore: nil,
libraryQueries:)` 成员集 → `ExifSearchFilter` 以 id 集合腿折叠（成员集 → 相册谓词，走
既有 `FilterPredicateGroup` 构造，零 SQL）；`nil` 注入 typed missingStore → 面板空态
（未开项目防御，正常路径不可达）。

## read_first

1. `.work/gsd/phases/m2-3-ui-shell/M2-3-CONTEXT.md`——D2/D8/D9/D10 + Phase Boundary
   图库节。
2. `.work/gsd/phases/m2-2-library-project/M2-2-3-SUMMARY.md`「M2-3 数据接口面清单」——
   九签名逐个对齐（**禁凭记忆写调用**）。
3. `App/Sources/Lightamer/Library/LibraryGridModel.swift` + `LibraryThumbnailBridge.swift`
   （P1 缝正本）。
4. `App/Sources/Lightamer/UI/Shell/WorkspaceModel.swift` + `WorkspaceHostView.swift` +
   `BackgroundTaskHosting.swift`（P1 缝正本）。
5. `LightamerCore/Sources/Library/LibraryQueries.swift`——九签名 + typed 载荷定义
   （`LibraryGroupCount` payload 字段名逐一核对）。
6. `LightamerCore/Sources/Library/ExifSearchParser.swift`——typed error 四族定义。
7. `LightamerCore/Sources/Library/ImageLinker.swift`——relinkRecord/stale 两形态签名
   （m4 路径勘误：Library 域，非 Session）。
8. `research/ALCEDO-FEATURE-MAP.md` §1.2——面板分组名/搜索对话框三段 IA。
9. `.work/gsd/phases/m2-2-library-project/perf.md` §A.4——挂账行原文（销账措辞对齐）。

## 纪律（强制）

1. 提交纪律：每任务独立提交（全英文 Conventional、≤72 字符祈使句、body what+why）；只
   add 本任务申报文件；不 push；`.work/gsd/...` 真路径。
2. 构建纪律：`caffeinate -dis` 包裹；不加 `-derivedDataPath`；新文件同 commit
   `tuist generate`。
3. 测试纪律：`Scripts/test-direct.sh '<Class>'` 双读（L028）；**基线 = 2049 +
   M2-3-1 终值**；全套 0 fail；在案 flake 归因惯例同 P1。
4. 边界纪律：每任务检查 `.work/config.toml [gsd]`。
5. 架构红线：`LightamerCore/` 零改动；legacyBody 树资产零 diff；网格/Inspector/搜索
   全走 M2-2-3 九签名，**壳内禁止出现任何 SQL 字符串拼接**（机检：新文件
   `git grep -E 'SELECT|FROM images'` 零命中）；新 UI 全量 `String(localized:)`。

## Tasks

### T1 缩略图网格 + 双击进编辑器真缝

- **read_first**：上列 1/3/4/5。
- **action**
  1. 新建 `Library/Views/LibraryGridView.swift`（KD-1 全量：LazyVGrid 列自适应 +
     keyset 无限滚动 + 单元格三件（缩略图/星级角标/选中环）+ 双击 openEditor +
     marker 族）。
  2. 修改 `WorkspaceHostView.swift`：library face 双栏骨架挂网格（左网格 + 右 Inspector
     槽位，T2 填充）；修改 `WorkspaceModel.swift`：openEditor 点亮 EditorPhaseState
     （currentImageID + filmstrip 锚）。
  3. 网格接线单测并入 `LibraryGridModelTests` 补充（视图模型胶水层：滚动信号 →
     loadNextPage 调用计数、isExhausted 后零调用）。
- **验收标准**
  - [ ] 网格分页胶水断言全绿；`library.grid` marker 在册。
  - [ ] 双击 openEditor → EditorPhaseState 接线断言全绿。
  - [ ] 全套回归 `0 fail`。

### T2 Album Inspector 面板（四分组/Activity/总数/过滤态/智能相册）

- **read_first**：上列 1/2/5/8。
- **action**
  1. 新建 `Library/LibraryInspectorModel.swift`（KD-2/KD-5 全量：分组加载/点击折叠/
     反选/面包屑退/总数卡联动/Activity 序列/智能相册成员集腿）。
  2. 新建 `Library/Views/LibraryInspectorView.swift`：Alcedo `AlbumInspectorPanel` IA
     逐件——`LIBRARY OVERVIEW`（Total Photos 卡）+ 四分组节（Alcedo 节名文案）+
     `ACTIVITY` 日柱（柱点击过滤）+ `SEARCH FILTER` 区（currentFilterDescription 渲染）
     + SMART ALBUMS 区；全部 `accessibilityIdentifier`（`library.inspector.group.<key>`
     族）。
  3. WorkspaceHostView 右栏挂 Inspector（宽度固定档，P1 TopBar 不动）。
  4. 新建 `Tests/LightamerTests/LibraryInspectorModelTests.swift`（真 `.lalb`）：四分组
     点击 → filter group 逐臂断言（dayFilter/camera/labels/lens）+ 再点反选 + 面包屑
     逐臂退 + 总数卡随 filter 变化 + Activity 柱点击 = 日期腿 + 智能相册成员集折叠 +
     currentFilterDescription 渲染源字段断言。
- **验收标准**
  - [ ] 分组点击折叠/反选/面包屑断言全绿；总数卡联动断言全绿。
  - [ ] 智能相册成员集腿断言全绿；过滤态 typed 渲染断言全绿。
  - [ ] 全套回归 `0 fail`。

### T3 全局搜索三合一对话框（EXIF 腿真接）

- **read_first**：上列 1/2/6/8。
- **action**
  1. 新建 `Library/LibrarySearchModel.swift`（KD-3：parse 包装/typed error 映射表/
     filter.plan 组装/清空语义/提交流回调）。
  2. 新建 `Library/Views/GlobalSearchDialog.swift`：三段结构（模式分段卡 + 输入段 +
     应用段）+ EXIF 腿错误行内呈现 + CLIP/全文占位空态（marker + 「arrives with M2-10」
     文案）+ ⌘F 入口接线（P1 MenuCommandSet 命令点亮）+ `search.dialog`/
     `search.tab.exif|clip|fulltext` marker。
  3. 新建 `Tests/LightamerTests/LibrarySearchModelTests.swift`：typed error 四族逐条
     （iso 非法/aperture 非法/date disjoint/unrecognized）→ 呈现文案断言 + 合法输入
     → plan 组装字段断言 + 空串 = 清过滤 + 提交 → 网格/Inspector 双联动信号。
- **验收标准**
  - [ ] EXIF 腿 typed error 四族映射断言全绿；plan 组装断言全绿。
  - [ ] 占位 tab 空态 marker 在册；零假结果面（grep 无 mock 数据注入路径）。
  - [ ] 全套回归 `0 fail`。

### T4 Inspector 批量 relink UI（M2LIB-07③）

- **read_first**：上列 1/4/7 + `App/Sources/Lightamer/Library/LibraryProjectController.swift`
  （编排缝实态）。
- **action**
  1. 新建 `Library/LibraryRelinkModel.swift`（KD-4：stale 行两形态分类 + 批量编排循环
     （App 层逐行 relinkRecord）+ BackgroundTaskHosting 注册 + 完成分类计数）。
  2. 新建 `Library/Views/RelinkSheetView.swift`：分组呈现（缺失路径/卷缺席两节）+
     每组换源选择器 + 进度/取消 + `library.relink.sheet` marker。
  3. Inspector 挂入口（图片域操作区按钮，stale 行存在时可见）。
  4. 新建 `Tests/LightamerTests/LibraryRelinkModelTests.swift`：两形态分类断言 + 批量
     编排单调进度 + 取消中途计数（relived/stillStale/cancelled 精确）+ 失败行不阻塞
     余行。
- **验收标准**
  - [ ] stale 两形态分类 + 批量进度/取消断言全绿。
  - [ ] `LightamerCore/` 零 diff（relinkRecord 只消费）。
  - [ ] 全套回归 `0 fail`。

### T5 缩略图首屏观察量测 + 收口——SUMMARY/DECISIONS

- **read_first**：本 plan AC 表 + `.work/gsd/phases/m2-2-library-project/perf.md` §A.4。
- **action**
  1. 首屏缩略图量测：真 `.lalb` + 档 A 语料首屏 N 张产耗（BENCH| 行，Debug/Release 双
     记，非门）——销 M2-2-3 §A.4 挂账行（同批小 edit：挂账行尾追加「→ M2-3-2 已量测，
     见 phases/m2-3-ui-shell/M2-3-2-SUMMARY.md」）。
  2. AC 逐条机检 + 全套回归终跑（计数/秒数入 SUMMARY）。
  3. 落盘 `M2-3-2-SUMMARY.md` / `M2-3-2-DECISIONS.md`（KD-1..5 执行确认 + 偏差归因）。
  4. `.work/GOAL-STATE.md` 续接点追加（M2-3-2 完成 + 下一步 = M2-3-3）；LESSONS 如踩坑。
  5. `git diff --stat` 核对文件边界与 front-matter 一致。
- **验收标准**
  - [ ] 量测 BENCH| 行落账 + perf.md 挂账销账注记同批。
  - [ ] AC 表全绿；SUMMARY/DECISIONS/GOAL-STATE 同批落盘；diff 边界无越界文件。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 网格 keyset 无限滚动不重不漏 + isExhausted 封底零调用；双击 → EditorPhaseState 接线 | LibraryGridModelTests 补充 + 接线断言 |
| 2 | Inspector 四分组点击 → filter 逐臂折叠/反选/面包屑退；dayFilter/camera/labels/lens 载荷 typed | LibraryInspectorModelTests（真 .lalb） |
| 3 | Activity 柱点击 = 日期腿；总数卡随 filter 联动；SEARCH FILTER 区 = currentFilterDescription typed 渲染 | LibraryInspectorModelTests |
| 4 | 智能相册成员集 → 过滤折叠；nil 注入 typed missingStore 面板空态 | LibraryInspectorModelTests |
| 5 | 搜索三合一：EXIF 腿 typed error 四族行内呈现 + plan 组装 + 空串清过滤；CLIP/全文 tab 诚实空态 marker | LibrarySearchModelTests + marker 断言 |
| 6 | relink：stale 两形态分类 + 批量进度单调 + 取消三分类计数精确 + 失败不阻塞 | LibraryRelinkModelTests |
| 7 | 壳零 SQL：新文件 `SELECT|FROM images` grep 零命中；九签名调用与 M2-2-3 清单逐个一致 | grep + 评审项核对 |
| 8 | 缩略图首屏量测 BENCH| 行落账；perf.md §A.4 挂账销账注记同批 | SUMMARY 引用 + perf.md diff |
| 9 | 新 UI 全量 `String(localized:)` 键；`LightamerCore/` 零 diff；legacyBody 树资产零 diff | grep + `git diff --name-only` |
| 10 | 全套回归 0 fail，计数 ≈ 基线 + 20..30 | test-direct.sh Executed/failures 双读 |
| 11 | diff 边界 == 申报文件集 | `git diff --stat` 逐文件核对 |

## 风险与边界

- **Inspector 点击语义与 FilterPredicateGroup 表达力**：camera/lens 臂依赖 FilterSQL
  既有 FilterField 覆盖面（camera mk+md 双列/lens 单列）——若某臂无既有字段（实态核对
  第一步），该臂降级为「成员集腿」（evaluate 反查 id 集，KD-5 同通道），禁扩
  FilterSQL（Session 域冻结）；plan 期不预判，T2 read_first 核对后择道并在 DECISIONS
  记录。
- **keyset 无限滚动与 NSTableView 差**：LazyVGrid 滚动信号近似窗口估计，可能多取一页
  ——语义无害（keyset 幂等），仅内存观察项；不走 NSTableView 重写。
- **搜索对话框窗口形态**：Alcedo 为模态浮层——SwiftUI sheet 实现；⌘F 焦点冲突
  （legacy Body ⌘F 过滤条 gate=true 原样）——gate 分支互斥，无共存冲突。
- **relink 批量与项目包写并发**：relinkRecord 逐行经 Controller 单写者缝天然串行；
  导入同批并发 = registry 队列化（同时刻单任务推进），v1 不做并行批。
- **zh 文案欠账**：本 plan 新增键预估 60..80（网格/Inspector/搜索/relink 全量），P4
  对账脚本统一补录——SUMMARY 登记键族清单防漏。

## 提交约定

- T1 `feat(library): thumbnail grid with keyset paging and editor entry`
- T2 `feat(library): album inspector panel with grouped filters`
- T3 `feat(library): global search dialog with exif lexical leg`
- T4 `feat(library): batch relink sheet over stale links`
- T5 `docs(m2-3): close out plan 2 library face`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。

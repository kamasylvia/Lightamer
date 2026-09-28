---
phase: m2-2
plan: "M2-2-4"
title: "收口——Sessions/Catalogs 剥离（M2LIB-06：运行时布尔门默认收窄 + LIGHTAMER_LEGACY_LIBRARY=1 env 回切口；Settings 无开关；代码与测试保留全绿）+ 项目面成为默认启动面（OQ-1/8 裁决闭环）+ AC 终验 + 台账同批（AGENTS 增量/TODO/GOAL-STATE）+ commit guard"
wave: 4
depends_on: ["M2-2-2", "M2-2-3"]
autonomous: true
requirements: [M2LIB-06]
files_modified:
  - App/Sources/Lightamer/Library/LibraryPreferences.swift      # 新建：legacyLibraryEnabled 布尔门（默认 false）+ isLegacyLibraryRequested(environment:) 注入式求值（env = LIGHTAMER_LEGACY_LIBRARY=1）+ 测试 override 缝
  - App/Sources/Lightamer/UI/SidebarView.swift                  # 修改：门收窄 modeSection（模式切换器）/Sessions/Catalogs 双区/catalogSessions/catalog 树节——false 全隐，true 原样
  - App/Sources/Lightamer/UI/ContentView.swift                  # 修改：门 false → 项目工作区最小面（P2 LibraryProjectController 入口）；true → 既有 Session 面原样
  - App/Sources/Lightamer/UI/LightamerApp.swift                 # 修改：组装点注入 gate 求值（environment 传参，M2-1 D-EXEC-1 face 注入式同款）
  - App/Sources/Lightamer/UI/SettingsView.swift                 # 修改：门 false 时隐藏 Catalogs 开关（Settings 页不放新开关 = OQ-8；既有开关随 catalog 面同隐）
  - Tests/LightamerTests/LibraryLegacyGateTests.swift           # 新建（→ tuist generate）：门默认 false / env=1 true / 注入求值三分 / Sidebar 节集合断言（false 不含 Sessions/Catalogs 节，true 全含）
  - .work/TODO.md                                               # M2LIB-01..07 勾选（T3）
  - AGENTS.md                                                   # 「M2-2 架构增量」节追加（T3：Library 目录惯例/包形态/真身边界/剥离门/env 口登记）
  - .work/GOAL-STATE.md                                         # M2-2 翻账 + 续接点更新（T3）
  - .work/gsd/phases/m2-2-library-project/M2-2-4-SUMMARY.md     # 新建（T3）
  - .work/gsd/phases/m2-2-library-project/M2-2-4-DECISIONS.md   # 新建（T3）
  - LESSONS.md                                                  # 如踩坑
---

# Plan M2-2-4 — 收口（Sessions/Catalogs 剥离门 + 默认面翻转 + 台账）

> **性质**：收窄与记账 plan——机制照抄两条先例的组合（M2-1 env 口
> `LIGHTAMER_FULL_IOP_FACE=1` 默认面收窄 + `CatalogPreferences.catalogsEnabled`
> 运行时开关形态），零新算法零 schema 变更。剥离 = **默认面收窄 + 显式回切口**，
> Session/Catalog 代码与测试不迁不删全绿（M2LIB-06 字面）。

## 已定裁决（不得重开）

- **OQ-8**：运行时布尔门（`legacyLibraryEnabled = false` 默认）盖住 Sidebar
  Sessions/Catalogs 双区 + browser 入口 + 模式切换器；**env 口
  `LIGHTAMER_LEGACY_LIBRARY=1`** 作 QA/回归回切通道；**Settings 页不放开关**。
- **OQ-1**：门 false 的默认启动面 = 项目工作区入口（P2 `LibraryProjectController`：
  新建/打开/最近）；完整双工作区壳 = M2-3。
- **非目标**：删 Session/Catalog 代码（禁）；CatalogPreferences/CatalogBrowserModel
  等 Core/App 模型零改动（门只盖 UI 呈现层入口）；M2-3 视觉面。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 门求值 = 注入式，禁 view body 直读静态 env

M2-1 T2 实测教训（59 fail 全 env 直读撞种子断言，D-EXEC-1）直引：门唯一求值点 =
`LibraryPreferences.isLegacyLibraryRequested(environment: [String: String] =
ProcessInfo.processInfo.environment)`——纯函数可注入；生产组装点（`LightamerApp`
场景构造）求值一次并以参数/环境对象下发；`LibraryLegacyGateTests` 用字面字典三分
（无键 false / `"0"` false / `"1"` true）。**SidebarView/ContentView body 零
ProcessInfo 触碰**。

### KD-2 收窄 = 节级条件渲染，非删除

`SidebarView` 的 `modeSection`/Sessions 节/Catalogs 五节（`SidebarView.swift:51-64`
起的面）包进 `if gate`；`ContentView` 同层二选一（gate false → 项目面容器；true →
既有视图树原样）。**既有关键字标识符（`accessibilityIdentifier("Sessions")` 等）
与视图逻辑零改动**——env=1 时 UI 面与 M2-2 前逐字节同构（回归通道语义），XCUITest
标识面不动。Settings 的 Catalogs 开关行同门隐藏（不放新开关 = 防误开双库分叉，
OQ-8 理由原文）。

### KD-3 默认启动面 = 项目工作区最小容器

gate false 时 `ContentView` 渲染 P2 的项目入口 + （项目打开后）导入命令面；**不渲染
任何 Session/Catalog 数据模型环境对象依赖的分支**（环境对象仍在树中注入——模型零
改动红线——只是不消费）。项目面布局细化归 M2-3；本 plan 只保证「默认启动看到的是
项目工作区、Session 面不可达（无入口）」。

### KD-4 回归通道测试策略 = 三层钉

1. **门求值层**：字面字典三分（KD-1）。
2. **节集合层**：构造 SidebarView 依赖的最小 model 集（gate 注入），断言可见节
   identifier 集合——false = 项目面节且不含 `Sessions`/catalog 族；true = 含全部
   既有节（与 M2-2 前快照一致）。
3. **既有面零回归层**：CatalogBrowserModelTests/CatalogModeIsolationTests/
   Session 族既有测试零改动全绿（模型层未触碰的机器证明）。

### KD-5 台账同批纪律（全局 §3.1 commit guard）

T3 单批完成：AGENTS.md 追加「M2-2 架构增量」节（`LightamerCore/Sources/Library/`
目录惯例、`.lalb` 包形态 + checkpoint/backup 纪律、`.lra` 真身/库=投影边界、剥离门
与 env 口、UserDefaults 键登记 `library.import.*`/`library.recentProjects`）；
TODO M2LIB-01..07 勾选（附 commit 引用）；GOAL-STATE M2-2 翻账 + 续接点 =
「M2-2 执行完毕，待验收（C 档第 2 停）→ M2-3」；REQUIREMENTS 翻账留验收批（M2-1
先例：front-matter 边界约束，验收 subagent/orchestrator 同批翻转）。

## read_first

1. `.work/gsd/phases/m2-2-library-project/M2-2-CONTEXT.md`——OQ-8/1 裁决 + 剥离先例
   表（M2-1 env 口 + catalogsEnabled）。
2. `App/Sources/Lightamer/UI/SidebarView.swift` 全文——organizationMode 轴（:51-64）
   /modeSection/五节结构与 identifier（KD-2 落点）。
3. `App/Sources/Lightamer/UI/ContentView.swift`——启动视图树与环境对象注入点。
4. `App/Sources/Lightamer/Catalog/CatalogPreferences.swift`——键宿主/开关形态先例
   （本 plan 不改它，只对照）。
5. `.work/gsd/phases/m2-1-dt-disable/M2-1-PLAN.md` KD-3 + DECISIONS D-EXEC-1——env
   口纪律与注入式教训正本。
6. `App/Sources/Lightamer/Library/LibraryProjectController.swift`——P2 项目面（KD-3
   消费）。
7. `Tests/LightamerTests/CatalogModeIsolationTests.swift`——模式隔离既有断言形状
   （KD-4 第 3 层）。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（全英文 Conventional Commits，subject ≤72 祈使句，
   body what+why + 同批 md 清单）；只 add 申报文件；不 push；`.work/gsd/...` 真路径。
2. **构建纪律**：`caffeinate -dis` 包裹；不加 `-derivedDataPath`；新建 .swift 后同
   commit `tuist generate`。
3. **测试纪律**：`Scripts/test-direct.sh '<Class>'` 双读（L028）；基线 = GOAL-STATE
   续接点最新值；全套 0 fail——**既有测试零改动**是本 plan 硬判据（KD-4 第 3 层；
   若确有测试断言「Sidebar 默认含 Sessions 节」，属默认面翻转的合法碰撞，处置 =
   该测试改显式 gate-on 注入并在 DECISIONS 逐条登记，禁删禁弱断言）。
4. **边界纪律**：每任务边界查 `.work/config.toml [gsd]`。
5. **架构红线**：禁触 `LightamerCore/`（本 plan 零 Core 改动）；Session/Catalog 的
   Core/App 模型与浏览器文件（CatalogBrowserView/CatalogTreeModel/SessionCoordinator
   等）零改动；diff 限五处 UI 文件 + 新 gate 文件 + 测试 + 台账。

## Tasks

### T1 剥离门正本 + Sidebar/Settings 收窄

- **read_first**：上列 2/4/5。
- **action**
  1. 新建 `App/Sources/Lightamer/Library/LibraryPreferences.swift`（KD-1）。
  2. `SidebarView.swift`：gate 条件包 `modeSection`/Sessions 节/Catalogs 族节（KD-2；
     注释指向 OQ-8 + M2LIB-06）。gate 源 = 环境注入（LightamerApp 构造传入）。
  3. `SettingsView.swift`：Catalogs 开关行同门隐藏。
  4. `LightamerApp.swift`：组装点求值一次 + 下发（KD-1）。
  5. 新建 `Tests/LightamerTests/LibraryLegacyGateTests.swift`（→ `tuist generate`）：
     KD-4 第 1/2 层（字典三分 + 节集合双态断言）。
  6. 全套回归 0 fail（碰撞处置按纪律 3）。
- **验收标准**
  - [ ] 门默认 false：Sidebar 无 Sessions/Catalogs 节与模式切换器；Settings 无
        Catalogs 开关。
  - [ ] env=1：节集合与 M2-2 前快照一致（回切通道成立）。
  - [ ] view body 零 ProcessInfo 直读（`git grep ProcessInfo App/Sources/Lightamer/UI/`
        仅组装点一处）；全套回归 `0 fail`。

### T2 默认启动面翻转（ContentView 项目面）

- **read_first**：上列 3/6 + P2 `ImportModeDialog`/`ImportProgressView` 消费面。
- **action**
  1. `ContentView.swift`：gate false → 项目工作区最小容器（KD-3：项目入口 + 打开后
     导入命令面；复用 P2 组件，零新布局体系）；true → 既有树原样。
  2. KD-4 第 2 层补 ContentView 双态断言（项目面节 identifier 在 / Session 面不可达）。
  3. 全套回归 0 fail；`LIGHTAMER_LEGACY_LIBRARY=1` 语义在单测层由注入对偶覆盖
     （真进程 env 冒烟 = Manual-Only 观察项入 SUMMARY）。
- **验收标准**
  - [ ] 默认启动 = 项目面；Session/Catalog 入口不可达（节集合断言）。
  - [ ] env 回切对偶断言全绿；全套回归 `0 fail`。

### T3 AC 终验 + 台账同批 + 收口

- **read_first**：本 plan AC 表 + 全局 §3.1 commit guard + AGENTS.md Phase 增量节
  格式（「Phase 2 架构增量」）。
- **action**
  1. AC 逐条机检 + 全套回归终跑（计数/秒数入 SUMMARY）。
  2. 台账同批（KD-5）：AGENTS.md「M2-2 架构增量」节 / TODO M2LIB-01..07 勾选 /
     GOAL-STATE 翻账 + 续接点 / `M2-2-4-SUMMARY.md`（含 Manual-Only：env 真进程冒烟、
     真实 C1 Session 目录复跑、缩略图首屏挂账 M2-3）/ `M2-2-4-DECISIONS.md`。
  3. commit guard（§3.1）：TODO 勾选态 = REQUIREMENTS 实况对账说明（REQUIREMENTS
     翻账留验收批，说明写入 SUMMARY）；`git diff --stat` 边界终核。
- **验收标准**
  - [ ] AC 表全绿；AGENTS/TODO/GOAL-STATE/SUMMARY/DECISIONS 同批落盘且互洽。
  - [ ] REQUIREMENTS 不在本批（留验收）说明在案；diff 边界无越界。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 门求值三分：无键 false / `"0"` false / `"1"` true（字面字典注入） | LibraryLegacyGateTests |
| 2 | 默认面：Sidebar/ContentView/Settings 不含 Sessions、Catalogs 族节与模式切换器、Catalogs 开关 | 节集合断言 |
| 3 | 回切口：env=1 时节集合 == M2-2 前快照（回切通道成立） | 节集合对偶断言 |
| 4 | view body 零 ProcessInfo 直读；求值点唯一（组装点） | `git grep` 自检 |
| 5 | Session/Catalog 模型与测试零改动全绿（CatalogModeIsolation/CatalogBrowserModel/Session 族） | 既有测试零 diff 全绿 |
| 6 | 默认启动 = 项目工作区最小面（P2 组件复用，无 Session 数据依赖分支） | ContentView 双态断言 |
| 7 | 台账同批：AGENTS 增量节 + TODO 勾选 + GOAL-STATE 翻账互洽 | §3.1 commit guard 核对 |
| 8 | 全套回归 0 fail（基线 + M2-2-1..3 新增 + 本 plan ≈ +8..12） | test-direct.sh 双读 |
| 9 | diff 边界 == 申报文件集；`LightamerCore/` 零改动 | `git diff --stat` |

## 风险与边界

- **UI 测试碰撞**（默认面翻转）：既有测试若断言默认含 Sessions 节，处置 = 显式
  gate-on 注入 + DECISIONS 登记（纪律 3）；禁删禁弱断言。XCUITest 面（若涉）
  env 门入 launch arguments 属 M2-3 GUI 轮处置，本 plan 登记。
- **双库并存心智**（OQ-8 立论）：Settings 无新开关；env 口仅 QA 通道，README/AGENTS
  记录不进 UI 文案。
- **回切完整性**：gate on 路径 = 既有树原样（KD-2 零逻辑改动）——回归风险集中于
  条件包裹的括号级失误，节集合对偶断言承载。
- **过渡态收尾**：M2-2 后 App 默认 = 项目面（无网格壳，仅入口 + 导入 + 数据 API）；
  「图库可用」完整体验落 M2-3——SUMMARY 明示该衔接，防验收误判功能缺失。

## 提交约定

- T1 `feat(app): legacy library gate with env opt-back channel`
- T2 `feat(app): project-first startup face behind legacy gate`
- T3 `docs(m2-2): close out phase ledgers and flip requirements`
- 全英文 Conventional Commits；body 写 what+why + 同批 md 清单；不 push。

# M2-2-4 SUMMARY — 收口剥离（运行时布尔门 + 默认启动面翻转 + 台账）

> Plan M2-2-4 收口（2026-09-29）。执行 = ZCode subagent worker；T1/T2 代码提交 + 本收口提交，未 push。
> 裁决正本 = `M2-2-CONTEXT.md`（D-M2-2-CONTEXT-1..12；OQ-8/OQ-1 未重开）；
> P1-P3 交付缝消费 = `M2-2-1-SUMMARY.md` 常量钉死清单 + `M2-2-2` 交付缝
> （LibraryProjectController/LibraryPanels/LibraryWelcomeView/ImportModeDialog/ImportProgressView）+
> `M2-2-3-SUMMARY.md` M2-3 数据接口面清单（本 plan 不消费查询 API——数据接口留给 M2-3 壳）。

## 提交账

| 任务 | Commit | 内容 |
|---|---|---|
| T1 | `207bd25` | LibraryLegacyGate（KD-1 注入式求值正本：`isLegacyLibraryRequested(environment:)` 纯函数 + `LIGHTAMER_LEGACY_LIBRARY=1` 回切口 + Settings 无开关）+ SidebarView 门收窄（modeSection/Sessions 族/Catalogs 族单条件包裹）+ SettingsView Catalogs 双节同隐 + LightamerApp 组装点求值一次下发 + `visibleSidebarSectionMarkers`/`visibleCatalogSectionMarkers`（KD-4 第 2 层载体）+ LibraryLegacyGateTests 8 |
| T2 | `c09d258` | ContentView 门分叉（gate false → `ProjectWorkspaceFace` 项目工作区最小面；true → 既有树 verbatim 迁入 `legacyBody` 零逻辑改动）+ `visibleContentFaceMarkers` + LightamerApp 传 controller/import 路由 + LibraryLegacyGateTests +3（冻结快照/默认集/跨门不相交） |
| T3 | 本提交 | AC 终验 + 台账同批（AGENTS 增量节 / TODO M2LIB-01..07 / GOAL-STATE 翻账 / SUMMARY / DECISIONS / LESSONS L040）（docs-only，零代码） |

## 测试终值

**全套 2049 / 13 skip / 0 fail**（终跑 R Debug，`Scripts/test-direct.sh`，789.1s；T3 docs-only 不触碰 bundle，与 T2 轮 716.97s 同值——两轮独立全绿）。

- 基线 2038（M2-2-3 终态）+ 新增 11 = 2049：LibraryLegacyGateTests 11
  （T1 轮 8：门求值三分 + 非法拼写负例 + Sidebar 双态 4 断言 + Settings 双态 2 断言；
  T2 轮 +3：ContentView 冻结快照/默认集/跨门不相交）。
- skip 13 = 既有基线原样（11 既有 + harness 门控 2；无新增 skip）。
- 每任务全套独立跑全绿：T1 轮 2046/13/0（713.1s）→ T2 轮 2049/13/0（717.0s）→ 终跑 R
  （见上方终值）零 flake。
- **M1 域零破坏（KD-4 第 3 层机器证明）**：`git diff 0754c4c..HEAD -- LightamerCore/`
  空；CatalogBrowserModelTests / CatalogModeIsolationTests / Session 族既有测试**零
  diff 全绿**（模型层未触碰——门只盖 UI 呈现层）。

## AC 总表（9/9 全绿）

| # | AC | 机检证据 | 状态 |
|---|---|---|---|
| 1 | 门求值三分：无键 false / `"0"` false / `"1"` true（字面字典注入） | LibraryLegacyGateTests.testGateEvaluationThreeWayOverLiteralDictionaries + testGateRejectsEveryNonOneSpelling（`""/true/yes/2/"1 "/" 1"/on` 全 false） | ✅ |
| 2 | 默认面：Sidebar/ContentView/Settings 不含 Sessions、Catalogs 族节与模式切换器、Catalogs 开关 | testDefaultSidebarFaceHidesEveryLegacySectionMarker（org/enable 全矩阵 4 态 = ∅ + 与 legacy 族不相交）/ testDefaultSettingsFaceHidesTheCatalogSections（∅ + 无新 legacy 开关键）/ testDefaultContentFaceIsTheProjectWorkspaceOnly（恰 `library.project.workspace`） | ✅ |
| 3 | 回切口：env=1 时节集合 == M2-2 前快照（回切通道成立） | testGateOnSidebarSessionsFaceMatchesFrozenSnapshot / …CatalogsFaceMatchesFrozenSnapshot / …SessionsModeWithCatalogsEnabledAddsSwitcher / testGateOnSettingsFaceMatchesFrozenSnapshot / testGateOnContentFaceMatchesFrozenSnapshot——期望全部 = **测试内硬编码 `Set<String>` 字面量**（从 M2-2 前 Sidebar/Settings/ContentView 源逐个誊入冻结，checker minor #3 语义；非运行时录制件） | ✅ |
| 4 | view body 零 ProcessInfo 直读；求值点唯一（组装点） | `git grep ProcessInfo -- App/Sources/Lightamer/UI/` = 仅 LightamerApp.swift 既有 DEBUG 探针（`.arguments`，前序 phase 资产零改动）+ 注释；Sidebar/Settings/ContentView body 零命中；env 唯一读点 = `LibraryPreferences.swift` 求值函数（default 参数），生产消费 = LightamerApp 组装点单次求值 | ✅ |
| 5 | Session/Catalog 模型与测试零改动全绿（CatalogModeIsolation/CatalogBrowserModel/Session 族） | `git diff 0754c4c..HEAD -- LightamerCore/` 空；三族测试文件零 diff；全套 2049/0 fail 含其全绿 | ✅ |
| 6 | 默认启动 = 项目工作区最小面（P2 组件复用，无 Session 数据依赖分支） | testDefaultContentFaceIsTheProjectWorkspaceOnly + testContentViewMarkersAreDisjointAcrossTheGate（两面临 marker 零共享 = Session 面无渲染入口，OQ-1 无入口语义）；`ProjectWorkspaceFace` 只读 `LibraryProjectController`，不触 Session/Catalog 环境对象（注入保持，仅不消费）；项目入口 = P2 `LibraryWelcomeView` 启动 sheet（app root 既有 `.task` 自动呈现，M2-2-2 缝原样） | ✅ |
| 7 | 台账同批：AGENTS 增量节 + TODO 勾选 + GOAL-STATE 翻账互洽 | 本提交同批：AGENTS.md「M2-2 架构增量」节 / TODO M2LIB-01..07 勾选（附 commit 引用）/ GOAL-STATE 续接点翻账 / SUMMARY / DECISIONS；键登记与源一致（`library.import.mode`/`rememberMode`/`rawExtensions` + `library.recentProjects`——`ImportFilter.swift:128-130`/`LibraryProjectController.swift:30` 实名核对） | ✅ |
| 8 | 全套回归 0 fail（基线 + M2-2-1..3 新增 + 本 plan ≈ +8..12） | 2049/13skip/0fail（+11，预估 8..12 带内；test-direct.sh 双读纪律：门测试类双读 OK，全套终跑单轮零 flake） | ✅ |
| 9 | diff 边界 == 申报文件集；`LightamerCore/` 零改动 | `git diff 0754c4c..HEAD --stat` = 恰 6 文件（4 UI 修改 + gate 新建 + 测试新建）+ 本批台账 md；LightamerCore 空 diff | ✅ |

## Manual-Only 观察项（不入自动验收）

1. **真进程 env 冒烟**：`LIGHTAMER_LEGACY_LIBRARY=1` 重启 App 目视核对 Sidebar/Settings
   与 M2-2 前逐节同构（注入字典双态断言为其机器等价；门 on 路径 = 既有树 verbatim，
   回归风险集中于条件包裹的括号级失误——由冻结快照断言承载）。建议 M2-3 GUI 轮顺带执行。
2. **默认启动面目视**：gate=false 冷启动目视核对（项目面 + 无项目时 Welcome sheet）。
3. **真实 C1 Session 目录复跑 / 缩略图首屏**：M2-2-2/M2-2-3 挂账项原样顺延 M2-3。

## 偏差与说明（详版见 DECISIONS）

1. **SidebarView gate=false 分支渲染空 List**（而非占位节）——ContentView gate=false
   根本不渲染 SidebarView（三分栏整体被项目面替换），Sidebar 收窄是纵深防御 + AC#2 的
   独立机检面；空 List = 「false 全隐」最小实现，布局细化归 M2-3。
2. **KD-4 第 2 层载体 = body 条件式的纯函数镜像**（`visibleSidebarSectionMarkers` 等
   三函数，紧邻 body 注释绑定）+ 测试内硬编码字面量——非渲染树遍历（单测进程渲染
   SwiftUI List 无先例且 flaky 风险高；节结构钉死的既有先例 = `CatalogSidebarSection.
   allCases` 恒等断言，Plan 16-2 T2 同型）。body 侧由「单条件包裹 + verbatim 迁移」
   保证 env=1 字节同构，`ProjectWorkspaceFace` 无 Session 数据分支由 marker 不相交断言钉。
3. **节 marker 集合粒度 = 每节恒渲染的稳定 identifier**（数据依赖行 id
   `session.row.*`/`catalog.*.row.*` 排除在外，注释声明）；List 容器 id `"Sessions"`
   零改动保留（KD-2 既有标识符不动），AC#2 的 Sessions 面不可达由 ContentView 层
   marker 不相交断言承载（gate=false 下 SidebarView 不在树中）。
4. **`legacyLibraryEnabled` 视图属性形态 = `var` + 默认 false**（带默认值的 memberwise
   init 参数——`let` 带初值不进 memberwise init，实测编译证伪后改 `var`；语义不变：
   未注入构造 = 收窄面，仅组装点显式传值）。
5. **File 菜单 Session 项未门控**（OQ-8 盖住面 = Sidebar 双区 + browser 入口 + 切换器 +
   Settings 开关；菜单不在其列）——gate=false 下菜单 Session 路由喂给未渲染的
   legacyBody，视觉 inert 非可达「面」；菜单级 IA 收纳归 M2-3（DECISIONS D3 登记）。
6. **File > New Project ⌘N 与「New Session」⌘⇧N 并存**、Import Folder 按钮键位 ⌘⇧I 与
   菜单一致——均为 M2-2-2 既有缝，未改。

## 与 M2-3 的衔接（防验收误判）

M2-2 后 App 默认 = **项目工作区最小面**（入口 + 导入命令面 + M2-2-3 数据 API）——
「图库可用」完整体验（网格/Inspector 面板/搜索对话框/双工作区路由/zh 文案/菜单 IA
收纳）全部落 M2-3 UI 壳 charter。本 plan 交付的是剥离门 + 默认面翻转 + 回切通道，
不是图库终态。

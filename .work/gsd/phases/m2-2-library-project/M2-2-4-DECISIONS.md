# M2-2-4 DECISIONS — 执行决策（KD 已决项只记执行确认，不重开）

> 裁决正本 = plan §已定裁决（OQ-8/OQ-1）+ §关键设计决策（KD-1..5）。本文件记执行期新决策
> 与 KD 执行确认。日期 2026-09-29。

## D1 KD-4 第 2 层载体 = body 条件式的纯函数镜像 + 测试内硬编码字面量

**决策**：节集合断言不走渲染树遍历，改三个纯函数（`SidebarView.visibleSidebarSectionMarkers`
/ `SettingsView.visibleCatalogSectionMarkers` / `ContentView.visibleContentFaceMarkers`）
作为 body 条件式的 1:1 镜像（紧邻 body、注释绑定），测试对它们断言**硬编码
`Set<String>` 字面量**（从 M2-2 前源码逐 identifier 誊入冻结）。

**why**：plan KD-4 字面「构造最小 model 集断言可见节 identifier 集合」在单测进程内的
实现通道二选一：(a) NSHostingView 渲染 + a11y 树遍历——本仓零先例、List 懒加载 +
a11y 物化时序 = 高 flaky 风险，与全套 720s 零 flake 纪律冲突；(b) 纯函数镜像——节
结构钉死的既有先例就是 `CatalogSidebarSection.allCases` 恒等断言（Plan 16-2 T2，
"the RQ-16-12 five-section order is frozen"），房子风格同型。checker minor #3 只钉
「快照载体 = 硬编码字面量、非运行时录制件」，未钉渲染方式。env=1 字节同构由 T2 的
「既有树 verbatim 迁入 legacyBody + 单条件包裹」（diff 可核）与 Manual-Only 真进程
冒烟（SUMMARY 观察项 #1）双承载。

## D2 视图门属性 = `var` + 默认 false（memberwise init 默认参数）

**决策**：`SidebarView`/`SettingsView`/`ContentView` 的 `legacyLibraryEnabled` 用
`var legacyLibraryEnabled: Bool = false`（ContentView 另加
`var projectController: LibraryProjectController?` 与 `var onImportFolder: () -> Void`），
不用 `let`。

**why**：Swift memberwise init 对**带初值的 `let` 不生成 init 参数**（实测编译报
"argument passed to call that takes no arguments"），带默认值的 `var` 才生成带默认值
的参数。语义与 KD-1/KD-2 完全一致：未注入构造 = 收窄面（默认 false = 安全方向），
仅生产组装点（LightamerApp）显式传求值结果；env=1 注入 true 后渲染树与 M2-2 前
逐字节同构。View struct 的 `var` 属性为 SwiftUI 常规形态（值语义，无状态风险）。

## D3 File 菜单 Session 项不做门控（范围纪律 + inert 论证）

**决策**：菜单栏 File > Open Session / Open Recent（以及 New Session/Open Image）
保持原样，不加 gate 条件；登记为 M2-3 菜单级 IA 收纳输入。

**why**：OQ-8 裁决门覆盖面 = 「Sidebar Sessions/Catalogs 双区 + browser 入口 + 模式
切换器」，Settings 开关随 catalog 面同隐——菜单不在裁决字面内；plan AC #2 的机检面 =
三处节集合断言，无菜单项。gate=false 下菜单 Session 路由（openSession）喂给未渲染的
legacyBody 分支，状态更新无任何渲染消费——是 inert 死路由而非可达「面」；门控菜单
反而改 env=1 回归通道的菜单树（`.disabled` 条件哪怕条件恒 false 也是结构变更，违反
KD-2 零改动精神）。风险已在 GOAL-STATE 续接点向 M2-3 登记。

## D4 Sidebar gate=false 分支 = 空 List（纵深防御位）

**决策**：`SidebarView` gate=false 时不渲染任何节（List 空），不加项目占位节。

**why**：KD-3 的默认启动面替换发生在 ContentView 层（三分栏整体 → 项目面容器），
gate=false 下 SidebarView 根本不在视图树中；Sidebar 的门是纵深防御 + AC#2
「Sidebar 不含 Sessions/Catalogs 族节」的独立机检载体。加占位节 = 新增布局面（KD-3
「项目面布局细化归 M2-3」的越界）；空 List 保持「false 全隐」字面 + 零新标识符。

## D5 节 marker 粒度 = 每节恒渲染稳定 identifier；行级 id 排除有声明

**决策**：Sessions 族 = `session.current`/`session.open`/`session.watch`/
`smartalbum.add`；Catalogs 族 = `catalog.section.all`/`catalog.category.add`/
`catalog.collection.add`；切换器 = `organization.mode`；Settings = 七个
`settings.catalogs.*`；ContentView = 8 个内容面 marker + `library.project.workspace`。
数据依赖行 id（`session.row.<hash>`、`catalog.category.row.<id>` 等）不入快照，
函数注释与测试注释双声明。

**why**：行 id 含运行时哈希/自增 id，无法誊成静态字面量；节的「存在性」由其恒渲染
控制件（current/open 二态、add/all 按钮、watch 状态行）承载——同节若在，marker 必在。
`session.current`/`session.open` 是同节两态（有会话/空态），字面量并集 + 注释钉语义，
两态任一出现均命中族。

## D6 ContentView verbatim 迁移 = `legacyBody` 计算属性整体搬运

**决策**：既有 body 的 NavigationSplitView + 全部 modifier 原样迁入
`private var legacyBody`（`@ViewBuilder`），`body` 只剩门分叉。

**why**：KD-2「env=1 时 UI 面与 M2-2 前逐字节同构」的最强保证 = diff 可核的零改动
搬运（T2 commit 的 ContentView diff 中 legacyBody 段只有缩进一级的 wrapper 差异，
逻辑行零修改）；`@ViewBuilder if/else` 只求值被取分支，gate=false 下 legacyBody 的
环境对象链完全不构建（「不渲染任何 Session/Catalog 数据模型环境对象依赖的分支」
KD-3 字面成立；环境对象仍在 app root 注入——模型零改动红线）。

## KD 执行确认

- **KD-1**（注入式求值）✅ `LibraryLegacyGate.isLegacyLibraryRequested(environment:)`
  唯一读点；LightamerApp 组装点单次求值（`private let legacyLibraryEnabled = …`）；
  `git grep ProcessInfo -- App/Sources/Lightamer/UI/` 视图 body 零新增命中。
- **KD-2**（节级条件渲染非删除）✅ Sidebar 单 `if legacyLibraryEnabled` 包裹、Settings
  双节包裹、ContentView verbatim 迁移；代码零删除，标识符零改动，env=1 同构。
- **KD-3**（默认启动面）✅ 项目面 = `ProjectWorkspaceFace`（状态两态）+ P2 Welcome
  sheet/导入命令面/进度 overlay（app root 既有缝）；无 Session 数据消费分支。
- **KD-4**（三层钉）✅ 第 1 层字面字典三分（8 测试）+ 第 2 层冻结字面量对偶（D1 形态）
  + 第 3 层既有测试零 diff 全绿（2049/0 fail）。
- **KD-5**（台账同批）✅ 本提交单批：AGENTS「M2-2 架构增量」/ TODO M2LIB-01..07 /
  GOAL-STATE 翻账 / SUMMARY / DECISIONS / LESSONS L040；REQUIREMENTS M2LIB-06 翻账
  留验收批（M2-1 先例），对账说明入 SUMMARY。

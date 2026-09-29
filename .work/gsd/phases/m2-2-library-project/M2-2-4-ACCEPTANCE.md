# M2-2-4 ACCEPTANCE — 收口剥离验收报告（含 M2-2 全 phase 小结）

> **PASS / 0 error + 0 minor**（3 条 observation 登记不计数，见 Findings）
> 验收人 = 独立验收 subagent（2026-09-29）；执行方 = ZCode subagent worker；
> plan = `M2-2-4-PLAN.md`；CONTEXT 裁决 = `M2-2-CONTEXT.md`（OQ-8/OQ-1，未重开）；
> commit 基点 `0754c4c`（M2-2-3 收口）。全套测试独立复跑（执行方进程外）。

## 结论

执行方 3 commits（T1 `207bd25` / T2 `c09d258` / T3 `96a7fab`）边界干净——3 commits
恰 12 文件 = plan 申报集逐一对上（6 代码/测试 + 6 台账 md）、`LightamerCore/` 全
plan 零 diff、既有测试零 diff（唯一测试变更 = 新建 `LibraryLegacyGateTests.swift`）。
AC 9 条逐条独立核对全部属实；五重点核查（env 回切完整性 / KD-4 快照载体 / M1 域
零破坏 / OQ-1 衔接 / 6 条偏差合理性）全部通过；独立复跑与声明逐值一致。

## 复跑 vs 声明

| 轮次 | 范围 | 结果 | 耗时 |
|---|---|---|---|
| 执行方声明（终轮 R） | 全套 | 2049 / 13 skip / 0 fail | 789.1s |
| **验收独立复跑** | 全套（`caffeinate -dis Scripts/test-direct.sh`，执行方进程外） | **2049 / 13 skip / 0 fail（host exit=0）** | 763.8s |
| 验收定向核对 | LibraryLegacyGateTests | **11/11 逐条 PASS**（日志逐行核对，零 `' failed` 行） | — |

- 计数 2049/13skip 与声明逐值一致；本轮零 flake、零 fail。
- 2049 = 基线 2038（M2-2-3 终态）+ 11（LibraryLegacyGateTests 8 + 3）。✅

## AC 总表（9/9 全绿，独立核对）

| # | AC | 验收独立证据 | 状态 |
|---|---|---|---|
| 1 | 门求值三分：无键 false / `"0"` false / `"1"` true（字面字典注入） | `LibraryPreferences.swift:36-40` 纯函数 `environment[key] == "1"`；`LibraryLegacyGateTests.swift:33-60` 字面字典三分 + 7 种非法拼写负例（`""/true/yes/2/"1 "/" 1"/on` 全 false）——复跑逐条 PASS | ✅ |
| 2 | 默认面：Sidebar/ContentView/Settings 不含 Sessions、Catalogs 族节与模式切换器、Catalogs 开关 | 三处 marker 纯函数 gate=false：Sidebar 4 态全矩阵 = ∅（`SidebarView.swift:45`）/ Settings = ∅（`SettingsView.swift:55`）/ ContentView = 恰 `library.project.workspace`（`ContentView.swift:67-69`）；复跑三条 default 测试 PASS | ✅ |
| 3 | 回切口：env=1 时节集合 == M2-2 前快照 | 冻结 `Set<String>` 字面量逐个对源核实：Sessions 族 4 id（SidebarView :365/:389/:552/:499）、Catalogs 族 3 id（:620/:642/:763）、切换器（:599）、Settings 7 id（SettingsView :114-171）、ContentView 8 marker（browser.mode.*:90 / toolbar.import:523 / toolbar.export:534 / browser.grid / catalog.grid / Inspector）；5 条 gate-on 对偶测试复跑 PASS | ✅ |
| 4 | view body 零 ProcessInfo 直读；求值点唯一（组装点） | `grep ProcessInfo App/Sources/Lightamer/UI/` = 9 处命中，其中 8 处 = LightamerApp 既有 DEBUG 探针（`.arguments`，`git show 0754c4c` 证实前序 phase 资产零改动）+ 1 处注释；三个视图 body 零命中；`ProcessInfo.processInfo.environment` 全 App 源仅 2 处 = gate 求值函数 default 参数（`LibraryPreferences.swift:37`）+ McpLauncher 既有（UI 外前序资产）；生产消费 = `LightamerApp.swift:327` 组装点单次求值 → :382/:1383 下发 | ✅ |
| 5 | Session/Catalog 模型与测试零改动全绿 | `git diff 0754c4c..96a7fab -- LightamerCore/` 空；`git diff -- Tests/` 仅新建 LibraryLegacyGateTests；CatalogBrowserModelTests / CatalogModeIsolationTests / Session 族零 diff 且复跑全绿（2049 含其全量） | ✅ |
| 6 | 默认启动 = 项目工作区最小面（P2 组件复用，无 Session 数据依赖分支） | `ContentView.swift:175-181` 门分叉；`ProjectWorkspaceFace`（:655-699）只读 `LibraryProjectController`，零 Session/Catalog 环境对象消费；跨门 marker 不相交测试 PASS（OQ-1 无入口语义）；项目入口 = P2 `LibraryWelcomeView` app root sheet（`LightamerApp.swift:1070-1080` 既有缝）；SidebarView 全仓唯一调用点 = legacyBody 内（`ContentView.swift:190`）——gate=false 下根本不在树中 | ✅ |
| 7 | 台账同批：AGENTS 增量节 + TODO 勾选 + GOAL-STATE 翻账互洽 | T3 `96a7fab` 单批 6 md；AGENTS「M2-2 架构增量」节五条与实现逐条对上（键拼写 `library.recentProjects` = `LibraryProjectController.swift:30` 实名核对）；TODO M2LIB-01..07 全勾附锚；GOAL-STATE 续接点翻账；REQUIREMENTS 留验收批说明在 SUMMARY/DECISIONS 在案 | ✅ |
| 8 | 全套回归 0 fail（≈ +8..12） | 复跑 2049/13skip/0fail（+11 在预估带内）；T1 轮 2046（713.1s）→ T2 轮 2049（717.0s）→ 终轮 789.1s → 验收轮 763.8s，四轮独立全绿零 flake | ✅ |
| 9 | diff 边界 == 申报文件集；`LightamerCore/` 零改动 | 3 commits 文件并集恰 12 = plan front-matter 申报 12（含 LESSONS「如踩坑」条目，L040 落账）；`LightamerCore/` 空 diff | ✅ |

## 五重点核查结论

1. **剥离 = 布尔门收窄非删除，env 回切完整** ✅：`LIGHTAMER_LEGACY_LIBRARY=1` 求值链
   完整——纯函数唯一读点（KD-1）→ 组装点单次求值 → 三视图属性注入；env 口机检 =
   字面字典三分 + 7 负例拼写；**回切形态机检可信**：T2 verbatim 迁移经验收 diff 机检
   （old body @`0754c4c` vs 现版 `legacyBody` 逐行 diff = **仅差声明行 1 行**，逻辑
   零改动）；Sidebar/Settings 为缩进级单条件包裹（T1 diff 逐 hunk 核对，节内容零
   变化）；gate-on 5 条冻结快照对偶断言全绿。
2. **KD-4 快照载体 = 硬编码 `Set<String>` 字面量 + 零 switch 消费者** ✅：11 测试内
   期望集全部为测试文件内硬编码字面量（`LibraryLegacyGateTests.swift:69-213`，注释
   声明 transcribed-from-source、never runtime-recorded）；checker minor #3 语义兑现。
   全仓零 switch 消费者声明核实：`grep -rn "legacyLibraryEnabled\|LibraryLegacyGate"`
   App/Sources = 恰 10 处（gate 正本 1 + 组装点 3 + 三视图属性/函数 6），无任何
   `switch` 分支按门值派生行为——门是纯呈现开关，无逻辑分叉消费面。
3. **M1 域零破坏（机器证明复核）** ✅：`git diff 0754c4c..96a7fab -- LightamerCore/`
   空（验收方独立执行）；既有测试文件零 diff；复跑 2049/0 fail 含 Catalog/Session 族
   全量绿——模型层未触碰的断言成立。
4. **「项目面成默认启动面」与 OQ-1 Welcome 语义衔接** ✅：gate=false 启动 =
   `ProjectWorkspaceFace`（项目名 + 导入命令面两态；无项目 → "Create or open" 文案）
   + app root 既有 `.sheet(isPresented: $libraryWelcomePresented)` P2 Welcome 自动
   呈现 + `ImportModeDialog`/`ImportProgressView`/错误 alert 全在 root 链（LightamerApp
   :1055-1090）——M2-2-2 交付缝原样承接，零新布局体系；Session/Catalog 面在默认树下
   无任何渲染入口（marker 不相交断言承载）。
5. **6 条偏差全部合理** ✅（逐条核过）：
   - D1 纯函数镜像载体：非渲染树遍历——单测进程渲染 SwiftUI List 无先例 + flaky
     风险，`CatalogSidebarSection.allCases` 恒等断言为房式先例同型；镜像保真由
     「单条件包裹 diff 可核 + 冻结字面量对源逐个核实」双承载，接受。
   - D2 `var` + 默认 false：`let` 带初值不进 memberwise init 属 Swift 语言事实；
     默认 false = 安全方向（未注入构造 = 收窄面）。
   - D3 File 菜单 Session 项未门控：OQ-8 裁决字面（Sidebar 双区 + browser 入口 +
     切换器 + Settings 开关）确实不含菜单；inert 论证成立——`menu_new_session` 本就
     是空 action 占位（LightamerApp:1110），`menu_open_session`（:1131）路由喂给未
     渲染的 legacyBody 分支，状态更新零渲染消费；且加门控反而结构变更 env=1 菜单树
     （KD-2 零改动精神）。登记 M2-3 菜单 IA 输入，合理。
   - D4 Sidebar gate=false 空 List：gate=false 下 SidebarView 不在视图树（唯一调用
     点在 legacyBody 内），门收窄是纵深防御 + AC#2 独立机检位，不加占位节 = 不越
     KD-3 界，合理。
   - D5 marker 粒度（行级 id 排除）：行 id 含运行时哈希/自增 id 无法誊静态字面量；
     节存在性由恒渲染控制件承载，注释双声明，合理。
   - D6 verbatim 迁移：本报告已 diff 机检兑现（见重点 1）。

## Findings（3 observation，均不计数不修）

- **OBS-1**：plan AC#4 字面「`git grep ProcessInfo App/Sources/Lightamer/UI/` 仅组装点
  一处」与实际命中数不符——UI 目录 9 处（8 处 = 前序 phase 既有 `.arguments` DEBUG
  探针 + 1 处注释）。SUMMARY AC4 证据已如实限定（「既有 DEBUG 探针……零改动 + 注释；
  body 零命中」），AC 意图（env 读点唯一、view body 零直读）成立。计划措辞瑕疵，
  非执行缺陷。
- **OBS-2**：T3 commit subject = `docs(m2-2): close out phase ledgers and gate records`
  与 plan 提交约定 `...and flip requirements` 措辞差——与「REQUIREMENTS 翻账留验收批」
  的实际执行一致（约定里的 flip 本就不在本批），subject 更诚实。零影响。
- **OBS-3**：`settings.catalogs.section`（SettingsView:307）与
  `settings.catalogs.rebuild_progress`（:189）两个 id 在门内但不在冻结集——D5 粒度
  声明（「每节恒渲染稳定 identifier」，状态条件行排除）覆盖，属声明内取舍。零影响。

## M2-2 全 phase 小结（4 plans 终态）

| Plan | 交付面 | 执行 commits | 验收结论 | 终态测试 |
|---|---|---|---|---|
| M2-2-1 | Library 数据层（`.lalb` 包 + schema + albums 三型 + ref_count + ExifFold + FTS 索引层） | 5（`4491c7b`/`a50f67f`/`c1e8a90`/`5bf0eeb`/`a2fe9eb`） | **PASS / 1 error + 1 minor**（error = withWriteBatch 无事务包裹，验收方当场修复 + 原子性回归测试；minor = QuickLook 负载型 flaky 登记） | 1951/11skip/0fail |
| M2-2-2 | 导入管线（ImportFilter 三门 + ImageLinker kind0/1/2 + ImportService 三方式 + 项目开关/导入薄壳） | 5（`b77c677`/`b2da780`/`c6eee61`/`b30d8e5`/`18a5189`） | **PASS / 0 error + 0 minor**（3 observation） | 1995/11skip/0fail |
| M2-2-3 | 查询面（ExifSearchParser + LibraryQueries 混查三腿 AND + keyset 分页 + OQ-9 p95 硬门 PASS 15.66ms@20k） | 4（`dfb4746`/`b9792ea`/`811122f`/`b284528`） | **PASS / 0 error + 2 minor**（harness 观察项登记） | 2038/13skip/0fail |
| M2-2-4 | 收口剥离（LibraryLegacyGate env 回切门 + 默认启动面翻转 + 台账收口） | 3（`207bd25`/`c09d258`/`96a7fab`） | **PASS / 0 error + 0 minor**（本报告） | **2049/13skip/0fail** |

**测试演进**：1889（M2-2 基线）→ 1951（+62，含验收修复回归 1）→ 1995（+44）→
2038（+43，含 harness 门控 skip +2）→ **2049（+11）**——全 phase +160，零 fail 闭环。

**M2LIB 全族翻账汇总**：M2LIB-01..07 **七条全 Delivered**（本批翻转 M2LIB-06 收口；
01/02 = M2-2-1、03/07 = M2-2-2、04/05 = M2-2-1+3、06 = M2-2-4）；UI 壳半边
（M2UIW-01..05）全部未动，归 M2-3 charter。

**Manual-Only 汇总表（全 phase 顺延 M2-3 GUI 轮）**：

| # | 项 | 来源 | 建议时点 |
|---|---|---|---|
| 1 | 真实 C1 Session 目录导入复跑（用户盘 `Capture/RAW` 样张，版权——自动验收用合成 fixture） | M2-2-2 #1 / M2-2-4 #3 | M2-3 GUI 轮顺带真目录导入一次 |
| 2 | 导入吞吐软指标 ≥100 张/min（真实 RAW 大文件口径；现值 ~123k 张/min 为 4KB 合成件口径） | M2-2-2 #2 / M2-2-3 #5 | M2-3 真件量测 |
| 3 | kind1 volumeIdentifier 真实外置卷插拔稳定性 | M2-2-2 #3 | M2-3 硬件在环 |
| 4 | env=1 真进程 GUI 冒烟（回切面目视逐节同构） | M2-2-4 #1 | M2-3 GUI 轮 |
| 5 | 默认启动面目视（项目面 + Welcome sheet） | M2-2-4 #2 | M2-3 GUI 轮 |
| 6 | 缩略图首屏（真实大目录首帧预算） | M2-2-3 挂账 | M2-3 |

**遗留挂账清单（非阻塞）**：

1. **100k 结构化排序腿 138ms**（TEMP B-TREE，tiebreaker 与索引形状不匹配）——修法 =
   schema v2 表达式索引或 id-tiebreaker 变体；perf.md §A.4 + M2-2-3 DECISIONS D4。
2. **harness deep walk NULL 键边界重启首页**（无死循环，尾段查询正确性已单测覆盖）——
   M2-2-3 验收 F-1 登记。
3. **realraw 交叉腿首轮导入耗时离群**（首启一次性成本，非查询路径）——M2-2-3 验收
   F-2 备查。
4. **QuickLook 负载型计时 flaky 留观**（M2-1 起 in-案族）——M2-2-1 F-2 / Phase 15 留观。
5. **File 菜单 Session 项未门控**（inert 死路由）——M2-3 菜单级 IA 收纳输入（D3）。

**验收批翻账**：REQUIREMENTS M2LIB-06 → Delivered（锚 `207bd25`/`c09d258` + 本报告）；
TODO M2LIB-06 验收注记；GOAL-STATE 新续接点（验收闭环 + C 档停等用户确认 → M2-3）。

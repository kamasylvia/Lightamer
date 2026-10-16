# FIX2-01 PLAN 评审（独立 zcode 路，2026-10-13）

> 评审身份：独立 plan 评审（替代 omp 路），零共享上下文。
> 输入 = `FIX2-01-PLAN.md` + `FIX2-CONTEXT.md` + 挂账正本
> `phases/v2-maintenance/V2M-VALIDATION.md`（§挂账①②）+ 两波 ACCEPTANCE
> （`V2M-01-ACCEPTANCE-2ND.md` §五 E2-1 / `V2M-02-ACCEPTANCE.md` §六）+
> 证据域 `gui-acceptance/v2m/`（MANIFEST + fix2-probe/ + 两份 sample）+
> `gui-acceptance/m6-closeout/MANIFEST.md`（42 行总队列）+ 先例
> `V2M-PLANS-REVIEW.md`（findings 形态 + F1/E2 教训）。
> 代码面 HEAD（`c6d56598`）亲验——下引 file:line 全部实读/实跑，非转述。
>
> **结论头**：
> - **FIX2-01 = 须修后放行——0 error + 8 minor + 5 注记**。骨架（三缺陷
>   根因定稿 / 探针先行定罪→按罪断环 / D-8 零码翻案 / 四波走查编排 /
>   红线族 / 对账口径）成立且证据链亲证（含两份 sample 栈帧独立复核）；
>   8 处 minor 全部是**实现钉 / 行集簿记 / 时序级**修订，不动任务序、
>   量级与批次治理。D-6 判别探针→定罪→断环的修法纪律与 D-8 翻案证据
>   是本 plan 的突出强项；唯一面内漏行（M-4 的 32/33）恰是简报第四维
>   问的「第六漏行」，答案 = 有，一行补丁可闭。

---

## 一、findings

### M-1【minor｜T2 合流实现】handler 内不得阻塞 ImportService actor——被改函数的 doc comment 正是此陷阱的正本，plan 未设钉

**证据链（HEAD 亲验）**：

1. `LibraryProjectController.runImport`（:384-435）的 handler 形 =
   `await service.setProgressHandler { [weak self] snapshot in
   Task { @MainActor in self?.importProgress = snapshot } }`（:389-391）
   ——闭包**立即返回**，投递任务不入 await。
2. 该函数头 doc comment（:370-383）明载前代缺陷：handler 体
   `await MainActor.run { … }` 曾使**每次进度投递阻塞 ImportService
   actor 直到主线程排干**，构成 actor↔主线程互等（D-7 波 1 复现的
   2/2 机制），修复 = 拆依赖。
3. handler 签名 = `(@Sendable (ImportProgress) async -> Void)`
   （ImportService.swift:178），`emit` 处 `await progressHandler?(progress)`
   （:737）——**handler 内任何 `await`（如 `Task.sleep` 实现节流窗）
   都会重新阻塞 actor 逐文件循环**。
4. plan T2 action 1 只写「改节流合流（投递间隔 ≥100ms 或批次尾强制）」
   ——未钉实现位置与阻塞语义；Checker #3 只钉终态穿透，不钉此形态。

**修法（两钉入 action 1 + Checker）**：①合流必须**非阻塞形**——handler
内零 await（pending 槽位 + 尾沿调度任务，或主 actor 侧节流），禁止
sleep-in-handler；②保序钉：合流后投递仍走 main-queue FIFO（既有注释
「Main-queue FIFO preserves snapshot order」+ adapter 单调钳
belt-and-braces 维持），尾沿投递取**最新**快照单槽去重。

### M-2【minor｜T1 H1-b 修法形态】条件发布缺初始发布钉——onChange-only 形会让首窗 focusedWorkspace == nil，⌘E/⌘W/⌘F/View toggles 启动即死

- 亲验：`WorkspaceModel` = `@Observable final class`、**非
  Equatable**（WorkspaceModel.swift:103-104）；`.focusedSceneValue`
  写点（WorkspaceHostView.swift:170）发布的是引用，窗口生命周期内
  恒同一实例——语义上**每次挂载发布一次即可**。
- plan action 2 H1-b 写「改 `.onChange(of: workspace.phase)`…单次发布」
  ——`onChange` 双参形**只在变更时触发、不在挂载时触发**：若唯一
  发布点挂在 phase 变更上，窗口打开至首次 phase 翻转之间
  `focusedWorkspace` 为 nil（LightamerApp.swift:461-462），全部
  workspace 命令（:1620/:1627/:1638 + View toggles）置灰 = 行为回归。
- 「或引入稳定 Equatable 载体使 FocusedValues 去重生效」备案路线的
  前提 = **框架对同值重写确有去重**——未证（D-7 样本只见 setter 在
  飞，未见去重与否；`.work/gui-acceptance/v2m/import-stall-sample.txt`
  :344/:510/:587 亲核 `updateFocusedValues`/`FocusedValueModifier
  .Transform.updateValue` 帧在案，只证写在发生）。
- **修法**：H1-b 修法形态钉死 = **挂载时一次发布（`.task`/`.onAppear`
  priming）+ phase 变更重发布**两条腿；若走 Equatable 载体路线，T1
  探针须顺带裁断「同引用重写是否触发下游失效」后再选（探针本来就要
  挂，加一条读数零成本）；AC 的「⌘E/⌘W/⌘F/View toggles 语义零变」
  补一个**启动即按**的显式走查点（不等首次 phase 翻转）。

### M-3【minor｜T1 H2 备案】条件摘除 `.inspector` 的分支身份翻转风险——壳 @State 重置隐患未入重验清单；SystemSplitView 归因属推断，行使时应记录归因确认

- 亲验：`.inspector(isPresented:)` 挂在 `WorkspaceHostView(…)` 上
  （ContentView.swift:205-223，gate-false 分支内）；H2 备案「页面未
  激活不挂 SystemSplitView」若按字面实现为 `if pageActive {
  host.inspector(…) } else { host }`，**分支两侧是不同具体类型 →
  WorkspaceHostView 结构身份随页开/页关翻转 → 壳级 @State
  （workspace / gridModel / thumbnailBridge / editor 面）整组重置**
  ——开一次 export 页 = 编辑器/图库态清零，比 spin 更重的回归。
- 恒挂 `.inspector` 内容空形保不住身份也消不掉 SystemSplitView 宿主
  ——两难本身就是 H2 需要 DECISIONS 裁形态的理由。
- 另外：SystemSplitView ← `.inspector` 的归因是 **grep 排除法推断**
  （NavigationSplitView 仅存 legacyBody:249 与 SettingsView，二者不在
  gate=false 树上；macOS 27 `.inspector` 由分栏宿主承载），非直接
  符号证——主案消环后归因自动无谓；**H2 行使时** DECISIONS 应记录
  归因确认步骤（如摘除后 spin 消失的反证 + 或符号级证据），防摘错宿主
  白改一轮。
- **修法**：H2 备案补两点——①形态裁定必须含**身份保持**要求（或证明
  所选形不翻结构身份）；②M3-4-01 T4 挂载语义走查行（export/film 页
  挂载 + dismiss 双向）之外，加「页开→页关一轮后 shell 状态存活」
  （编辑器 phase/图库网格/选中不丢）一行。

### M-4【minor｜T5 行集】**第六漏行坐实 = GUI-M6C-32/33**——v2m 终表定性 Blocked-Channel（D-6 阻断编辑器面），属挂账②「余 Blocked-Channel 行随通道恢复复走」点名面，四波与排除清单双缺

- 亲验对照（`gui-acceptance/v2m/MANIFEST.md` wave-2 终表 :47-64）：
  - **32/33（无人像 typed toast / 羽化三档）= Blocked-Channel，理由
    「AI 蒙版交互在编辑器面；D-6 阻断」**——T1 修复即解锁，既不在
    W1..W4 任何波，也不在不入波清单（不入波 = 24/25/26/27-31/39）。
    m6-closeout 原表的 Blocked-Manual（时间止损）定性已被 v2m 复走
    **升格为通道阻断**——FIX2 未吸收这一定性变更。
  - 40 = Blocked-Channel → W4 ✓；16-19 = Blocked-Channel → W4 ✓；
    34-38 = Blocked-Channel → W4 ✓；26/39 = Blocked-Env（供件）→
    排除 ✓；E2-1 四行（V2M-T1-02/D3-01/D4-01/D5-01）+ 挂账② 硬义务
    （03/05/08 + 06/07 + D-4 复验）全数在波 ✓。
  - 三行零注记静默缺席（非通道面）：10（Registered-obs 观察行无判据）、
    12（Executed 1/3，filmstrip 行实质由 D3-01 复走覆盖）、14
    （deghost 三档——简形 sheet 零档位控件，UI 通道仍缺席，与通道
    修复无关）。
- **修法**：①32/33 入波（编辑器面行，建议 W1 或 W2 尾，判据 =
    m6-4/MANIFEST M-3/M-4 原文）或入不入波清单并注记理由——二选一，
    不许双缺；②10/12/14 在不入波清单补一行排除理由（M-6 先例：
    静默排除须注记）。

### M-5【minor｜T5 W2 前置】合并行面的前置通道错位——三合并对话框只在 legacy SessionBrowserView，项目面无 merge 入口

- 亲验：`MergeDialogCount` + 三对话框 + merge 菜单全在
  `SessionBrowserView.swift`（:170/:200/:207/:284/:345/:446-459）；
  SessionBrowserView 唯一挂载点 = ContentView.swift:439——**legacyBody
  内**（gate=false 项目面 Library 视图族 grep 零 merge 菜单入口）。
- W2 前置通道写「T1 + W1；merge 动作经项目面 import 供件」——
  D4-01/D5-01 的对话框呈现与 D5 的 toast 判据都在 **legacy 会话腿**
  （⌘⇧O 打开文件夹会话 → 网格多选 ≥2 → merge 菜单）；「项目面
  import」供进的是项目库，SessionBrowserView 浏览的是文件夹会话，
  两面不通。「经项目面 import」对 D-7 复验（W3）是对的，放 W2 是
  错位。
- 时序上无害（T3 在 T5 前完成，legacy 配方届时在位），但按现文执行
  会在项目面找 merge 动作白走一轮 / 误记 Blocked。
- **修法**：W2 前置补「T3 legacy 配方（⌘⇧O 会话腿）」；供件注记改
  「待合并素材 = 文件夹（会话腿直开）」；GUI-M6C-13 先例（legacy 面
  Robertson02 走通）即此配方。

### M-6【minor｜T4/T5 时序】GOAL-STATE「修复批 II closed」续接点在 T5（可触发代码返工）之前落盘——账实倒挂口

- plan 执行序 T1→T2→T3→**T4 收口（GOAL-STATE 续接点翻新为「修复批
  II closed → 新特性立项待用户定向」）**→T5；而 T5 W2 有真实返工臂
  （D4-01 复验仍见 0 →「快照上移」返工，返工改
  `SessionBrowserView.swift`——**不在 files_modified**——且可能带
  ΔN 变化）。返工一旦触发，T4 已写的 closed 续接点即失真。
- **修法**：①T4 的 GOAL-STATE 续接点改写「修复批 II 代码面收口，T5
  走查复走批执行中」，T5 末尾（含返工分支收口）补一次台账 commit 翻
  终态；②files_modified 补返工 contingency 面（SessionBrowserView
  .swift + 可能的新测试行）注记，防返工时 front-matter 失真。

### M-7【minor｜T1 探针配方】`Self._printChanges()` 是 View 专属 API——LightamerApp 是 Scene，照方硬套会在 App 环节编译失败或静默漏测

- 亲验：`LightamerApp.body` 是 `some Scene`（LightamerApp.swift:490）；
  `_printChanges` 挂在 View 上（WorkspaceHostView/ContentView 可用）。
- plan action 1 写「挂 WorkspaceHostView.body / LightamerApp.body /
  ContentView.body」并给「（或 OsLog signpost 同效形）」——措辞有退路
  但未点名 Scene 不可用 `_printChanges`；idle 样本亲核显示 App 环节
  才是 churn 的关键读数面（`LightamerApp.body.getter` 闭包族
  :1820-1854〔ratingMenuLabel/colorMenuLabel/metadataTextEntryActive〕
  持续重估，`sample-idle-face.txt` :263/:315/:351 亲证）。
- **修法**：探针配方钉两段形——View 面 `_printChanges`；App/Scene 面
  以 signpost 或手动桩（`visibleMenuCommands` 求值计数 + Commands
  闭包进桩日志）替代，并在 transcript 判读规则中写明 App 环节读什么。

### M-8【minor｜T1 判定口径】空载面 CPU 门归属两处不一致 + 「spin 消失但静置 CPU 10-30%」区间无裁定路径

- SC 写「重开**空载**静置 CPU<10%」（读作空载面设门）；T1 action 4
  铁条 (1) 只对**编辑器面**设门 <10%，铁条 (3) 空载面「一并记录」
  不设门。churn 是三面共病（probe-0 34% / probe-9 50.8% / probe-10
  82.3%）——若失刷源多发，可能出现「编辑器面达标、空载面残留 >10%」
  的中间态，plan 未写此时的裁定（二轮探针迭代？H2 行使门槛？记
  Blocked？）。
- **修法**：两处对齐——建议：编辑器面 = 硬门（SC 主判据）；空载面 =
  硬门或「记录 + >10% 时判别探针二轮迭代义务（多写点逐个断环）」
  二选一钉死；H2 行使门槛保持「主案消环后 spin 仍现」不变。

---

## 二、注记（不要求修订，执行批知悉）

### N-1 D-8 翻案与零码核销：证据充分，核销成立；证据目录有三处引用缺口（T3 复走自愈）

- 亲验真腿链：`visibleMenuCommands.contains(.sessionOpen)` 门内
  `menu_open_session` → `FileOpener.openSessionFolder` →
  `sessionCoordinator.openSession`（LightamerApp.swift:1530-1552）；
  gate=true 时 `sessionRoutes` 含 `.sessionOpen`
  （MenuCommandSet.swift:60 + `visibleCommandIDs` gate 分支）；「打开…」
  腿 = `FileOpener.openImage` 单图载入（:1515-1528）——「走查错腿 +
  inert-by-design 两事叠加」的翻案定性成立；Import Folder
  `.disabled(libraryProjects.projectStore == nil)`（:1600）=
  disabled-by-design 锚亲证。
- 证据目录缺口：CONTEXT 引 probe-8（D-7 本轮未复现的导入完成面）、
  probe-14（返回图库）、probe-16（legacy 菜单面件清单）三图，现目录
  仅 5 png（probe-0/10/11/18/20），CONTEXT 头称「六图」——计数与
  引用不闭合。T3 复走将重产 legacy 面证据（自愈）；probe-8 涉及 D-7
  间歇性论证，建议执行批补采或注明缺失原因。
- 核销口径 Checker #5（「翻案核销（走查错腿 + inert-by-design），非
  代码修复」+ V2 #4 前置句勘误）到位；配方双落点（MANIFEST local-only
  + AGENTS T4 配方正本）保证跨会话可达，形态合规。
- 一处如实注记：T3 三步之 (2)「双击进编辑器加载成功」在现有 probe
  中无显式截图（probe-20 = 会话 + 0.0% CPU），T3 将新产——翻案主体
  （通道可达）不受影响。

### N-2 T5 harness 教训未随行——键盘路径与多选是 W2/W4 的承载风险

- m6-closeout 执行批注记（MANIFEST :95-100）：**CGEvent 键盘事件全程
  不进 app（键盘路径判死，AXPress 可靠）**；**网格多选可建立但清选
  不可靠（pano 六张混选翻车先例）**；wave-1 又添「CGEvent cmd+click
  旗标不生效」（v2m MANIFEST :16）。
- W2 D4-01（多选 ≥2 才可见 merge 菜单项）与 W4 pano 16-19（≥2 多选）
  直接踩这两个坑；plan 已把交互判据行交给 B 类 computer-use（输入
  通道与 AX harness 不同，可能避开旗标问题），但教训本身应在 T5
  read_first/执行纪律点名（键盘路径一律菜单 AXPress；多选优先
  computer-use、失败则行如实 Blocked——plan 的「不硬造」条款已兜底）。

### N-3 SC 机检性 / ΔN 算术 / skip 口径 / 红线现状：全过

- **ΔN 带自洽**：`+0..4` = T1 `+0..2` + T2 `+0..2` + T3 `0`——上下界
  精确闭合（V2M M-4 类滑差免疫）；`estimated_tests` 与分任务组成一致。
- **skip 口径**：35 = 基线 24 + RAW 供件漂移 11 与 V2M-VALIDATION
  逐族构成一致；Checker #7 第三来源申报条款在位。T1/T2 新测试均非
  RAW 依赖域，不触 skip 面。
- **三铁条可观测性**：`ps`/`sample` 机检 + 修前 82-99% / legacy 0.0%
  双侧对照锚在案，<10% 门余量极宽（无 F1 型不可判定 AC）；filmstrip
  出图 + 截图证据面具体。
- **红线现状亲跑**：`\.runModal(` App/Sources = **0** ✓；插值禁形
  代码 = **0**（裸 grep 2 命中 = :2069 doc comment〔Checker #8 豁免锚
  在案〕+ ExportInspectorView.swift:**534** 拼接形〔非插形——注意该锚
  自 V2M 评审的 :433 已漂移至 :534，V2M-02 T5 落行所致；grep 形须钉
  插值 regex `String\.LocalizationValue\("[^"]*\\\(` + 注释免疫〕）✓；
  T1 触码三文件（WorkspaceHostView/ContentView/LightamerApp）均不在
  封存面清单 ✓；LibraryProjectController 非封存面 ✓；`Project.swift`
  条款 + L041 在位 ✓；`test-direct.sh` App token 合法（:165）+ 8G 门
  RSS_LIMIT_MB=8192（:70）✓；`.work/config.toml [gsd] auto=true /
  paused=false` ✓。
- **探针入库纪律**：判别探针 /tmp 即弃零 commit——与「churn 探针即弃」
  先例一致，方案正确；如需复发诊断常驻面，T2 watchdog 的 OsLog 已
  部分承担，无需 `_printChanges` 环境门控常驻（不采纳也不违规）。

### N-4 D-6 假说面与 D-7 根因链：证据自洽性复核通过

- H1-b 环路的两个关键环节有独立采样支撑：写腿 = stall 样本
  `ViewGraph.setFocusedValues` / `FocusedValueModifier.Transform
  .updateValue` 帧（import-stall-sample.txt :344-345/:510/:561-562/
  :587 亲核）；读腿 + 回环 = idle 样本 App body/Commands 持续重估
  （:263/:315/:351）。闭环「若 FocusedValues 写不按值去重即成立」的
  表述诚实——探针裁定纪律（先定罪后动刀 + DECISIONS 记 view/属性名
  + 断环 diff 落定罪点）正是防 F1 型不可判定 AC 的正确形态。
- SystemSplitView 栈结构（:49-:91 三层嵌套）与「全框架帧零 app 帧」
  形态亲读吻合；H3 降权论证（churn 不需要重开也存在）成立。
- D-7：`runImport` @MainActor 全链（类注记 :41-42 + :384-435）、O(N)
  hop、完成尾 nil 直写（:416）、消费面 nil 收尾（WorkspaceHostView
  :309-332）逐环亲证；**与 F-1 分根论证成立**（F-1 = ImportModeDialog
  呈现/闭包生命周期 crash；D-7 = 调度饥饿——机制不相交，只对表不修
  合规）。T2 自我定位「独立于 D-6 的防御面，消 churn 才拆饥饿根」
  诚实——其 AC（N 轮完成 + 完成态发布 + CPU 回落）测的是系统行为
  而非合流机制有效性（T1 修好后 AC 无论合流强弱都会过），属可接受的
  定位；机制有效性由 M-1 的四语义单测承载。
- 服务侧终态语义补充（执行批知悉）：`ImportProgress.Phase` 有
  `.completed`/`.cancelled` 终态快照（ImportService.swift:56-60，
  importFolder 循环尾 :359 发 .completed、取消检查点发 .cancelled），
  与 controller 侧 nil 直写（:416）是**两个终态载体**；视觉收尾唯一
  依赖 nil（onChange :318-320），四语义测试的「终态穿透」以两个载体
  都不被吞为断言面最稳。

### N-5 T5 波次完整性总核（简报第四维的正面回答）

对照三正本逐行：**硬义务行零缺**（E2-1 四行 W1/W2 全在 + D-4 复验
W2 + 挂账② 03/05/06/07 W1 + 08 W2）；**Blocked-Channel 行集缺
32/33 一处**（M-4 修法一行闭）；不入波 24/25/26/27-31/39 与 v2m
Blocked-Env 定性一致 ✓；W2 D4-01「见 0 → 快照上移」为机械触发
（对话框实际呈现为前提——V2M-02 T2 双路追认条款原文兑现），无裁量
歧义，裁定权条款无须另设；「返工不产假交付 + DECISIONS 申报」在位。
供件面：pano 合成切片（PIL 水平切片先例）、连拍 auto-stack、guided
filter 深度模型包在位（m6-closeout :58 确认）——供件缺座行排除清单
（24/25/26/27-31/39）与三正本供件记载一致 ✓。

---

## 三、放行面复核结论（逐维度对简报七问）

1. **T1 D-6 修法面**：探针→定罪→断环纪律自洽，两写环证据链闭合
   （N-4）；修法验收可观测（transcript + file:line + 三铁条）无 F1
   残留；断环方案与 SwiftUI 惯例相容，唯 H1-b 需初始发布钉（M-2）、
   H2 备案需身份保持钉（M-3）、探针配方需 Scene 段替形（M-7）、CPU
   口径需对齐（M-8）。
2. **D-8 翻案**：零码核销证据充分（N-1，真腿 :1530-1552 + :1600 锚
   亲证）；配方双落点合规；pano/栈面行号对表准确（16-19/34-38/40
   全对 v2m 终表）。
3. **T2 D-7**：合流 + watchdog 方向成立，F-1 分根成立；实现缺
   actor-非阻塞钉（M-1）；终态双载体语义见 N-4。
4. **T5 走查复走波**：硬义务零缺；第六漏行 = 32/33（M-4）；W2 前置
   通道错位 legacy 面（M-5）；D4-01 触发裁定权 = 机械触发无歧义；
   harness 教训随行建议（N-2）。
5. **SC 机检性 + 数字**：ΔN 带自洽 + skip 口径 + 三铁条 + T4 对账
   全过（N-3）。
6. **红线族**：T1 触码面与封存面零交集；探针零 commit 纪律正确；
   插值禁形 grep 形钉法与豁免锚在案（含 :534 漂移注记）。
7. **独立猎残**：M-4/M-5/M-6 为简报维度外产出；未发现结构性驳回项
   （任务序、批次治理、停等点〔T4 --all 批准制〕、暂停开关现值均
   复核无误）。

## 总评

**须修后放行（0 error + 8 minor + 5 注记）**。本 plan 的证据纪律与
V2M 两波一脉相承且更进一步——根因定稿带三路亲跑采样、修法带探针
定罪前置、D-8 走「翻案核销」而非硬修、T5 把「不硬造判定」写成机械
触发条款；两份 sample 的栈帧引用经本路独立复核逐帧命中。8 处 minor
全部是钉子/簿记级：M-1（handler 非阻塞钉）与 M-2（初始发布钉）防的是
「按现文实现引入新缺陷」，M-4/M-5/M-6 防的是「走查批行集与台账时序
失真」，修订量级均为行级补丁，不动任务序、波次编排与批次治理。修订
完成后可派发。

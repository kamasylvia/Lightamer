# M7-1-01 PLAN 评审（独立 zcode 路，2026-10-16）

> 评审身份：独立 plan 评审（替代 omp 路），零共享上下文。
> 输入 = `M7-1-01-PLAN.md` + `M7-1-CONTEXT.md` + `M7-1-RESEARCH.md` +
> 挂账/教训正本（`FIX2-01-PLAN-REVIEW.md` M-2/M-3/M-7、
> `V2M-PLANS-REVIEW.md` E-1/E-2、`M6-6-01-PLAN-REVIEW.md` F1 可观测性、
> `FIX2-01-DECISIONS.md` D-FIX2-1、`FIX2-01-SUMMARY.md`）+ 代码面 HEAD
> （`31d5afce`，plan/research 全 docs-only——基线 `3860/35/0` 未漂移亲核）
> 亲验，下引 file:line 全部实读/实跑，非转述。
>
> **结论头**：
> - **M7-1-01 = 须修后放行——1 error + 7 minor + 6 注记**。骨架（七任务
>   序 / 案 A+B+C3+燃料减频的组合裁定 / 裁定权归属双钉 / 判别臂 flag +
>   transcript 决定性判据 / 红线族 / ΔN 对账）成立且证据链亲证；E-1 是
>   **SC 数字门级**的：T1 的 CPU <5% 硬门与研究正本自己预测的 AppKit
>   骨架底噪带（~28%）直接矛盾且 plan 内部两处裁定相反——不修订则执行批
>   要么把成功误记 BLOCKED、要么无授权越过自家 SC。7 处 minor 全为实现钉
>   / 可观测性谓词 / 簿记级修订，不动任务序、量级与裁定权归属。

---

## 一、findings

### E-1【error｜T1/T4 SC】CPU <5% 硬门与证据正本的底噪带（~28%）直接矛盾；plan 内部两处裁定相反；底噪情形无裁定路径

**证据链（亲验）**：

1. `FIX2-01-DECISIONS.md` D-FIX2-1 第 5 条（:63-67）：「C1 形空载面
   SwiftUI churn 死后仍有 **~28% CPU 的 AppKit 侧低频**（~11Hz Source1
   UpdateCycle → NSWindow layoutIfNeeded → 嵌套 hosting layout →
   preferencesDidChange）底噪（c1-sample/c2-sample）」——C1/C2 scratch
  （= 案 B/案 A 的等效摘除形）饿死 churn 后，同一空载面、同一 `ps` 口径
   的实测残值是 **~28%**，非归零。
2. `M7-1-RESEARCH.md` §1.2 自己承写：「减树方案对底噪的预期 =
   **部分残留（AppKit 侧），不承诺归零**」。
3. 而 plan：front-matter SC「flag-on build 图库/空载面可见窗 CPU **<5%**
   （10×1s ps 系列）」+ T1 AC「<5%（…<10% = §5.4 判据一门亦过——两口径
   同录）」+ T4 判据一同门——按证据正本预测，案 A+B 落地后该门
   **大概率数学不可达**（28% ≫ 10%）。
4. **plan 内部矛盾**：T1 action 7 又写「AppKit 底噪注记（~11Hz 族残留
   **不判 FAIL**，记录口径）」——同一指标，SC 说 <5% 硬门、走查注记说
   残留不判 FAIL，两处裁定相反，且注记没有引用为裁定条款的资格（不在
   AC/SC 内）。执行批到 AC 判定时将面临二选一：按 SC 记 FAIL（churn
   已死、修法实质成功却被记 BLOCKED）或按注记放行（无 SC 授权的越权
   裁定）。
5. 这正是 `FIX2-01-PLAN-REVIEW.md` M-8 的同类缺口（CPU 口径两处不一致 +
   中间态无裁定路径）在本 plan 的复发——M-8 当时是 minor，本 plan 把该门
   升格为 SC 主判据与 T4 终验判据，缺口随之升格。

**修法（二选一，DECISIONS 申报）**：

- **甲（推荐）**：重排判据主从——决定性判据 = probed transcript 稳态
  0 重估行（已有，机检性最强）+ sample 环符号归因（makeMainMenu/
  updateMainMenu/invalidateProperties 计数归零或 ≤ 底噪阈值）；CPU ps
  系列改为「**churn 死 + 底噪带注记**」形态：预先声明底噪带（如 <40%
  带 + sample 归因 AppKit 骨架帧占比），带内 = PASS 带注记，带外 =
  真判 FAIL；删除 <5%（及 <10% 回落）数字门或降格为「观察目标非门」。
- **乙**：T1 落地前加一步 scratch（案 A+B 形即 C1+C2 组合）先实测减树
  形的底噪地板，用实测值回填 SC 数字（plan 他处「先探针定罪再动手」
  纪律的延续；半天级增量）。
- 无论甲乙：T1 走查注记升格为正式裁定条款写进 AC；T4 判据一同步修订
  （终 build 复测同口径）；判据二的「消失或降底噪」同步给数值谓词
  （见 N-5）。

### F-1【minor｜T3】carrier 3→1 的 metadataFieldFocused 桥接面欠钉——:429 publish 跨两面服务，「3→1」与 legacy 面 disarm 兼容不可兼得时无裁定

**证据链（亲验）**：

1. focused 值发布点全仓 = 5 处：`ContentView.swift:287-288`（legacy
   双写，冻结）/ `:228`（gate=false exportPanelRequest）/
   `WorkspaceHostView.swift:170`（workspace model）/
   `InspectorView.swift:429`（metadataFieldFocused）。gate=false 面
   生效 3 处 ✓（plan 计数正确）。
2. **`:429` 是两面共用的**：InspectorView 双挂载点 = `legacyBody:269`
   + `ContentView:220`（gate=false inspector 列）——legacy 面（QA 回归
   通道）的 metadata 裸键自解除**只依赖 :429 旧键发布**。
3. carrier 装配宿主 = WorkspaceHostView（plan 原文「天然单点」）——
   **legacy 面没有 WorkspaceHostView**：若 :429 publish 被并入 carrier
   （files_modified 原文「:429 metadataFieldFocused 写点并 carrier」），
   legacy 面 disarm 即失效 = 行为回归；若保留 :429 旧键发布保 legacy，
   gate=false 面写点 = carrier(1) + :429(1) = **2 处**，SC「3→1」与
   「prependValue 降幅与 3→1 合并同域」不达。
4. 另外 metadataFieldFocused 的值体是 InspectorView 内层视图的
   `@FocusState`（InspectorView.swift:419 `.focused($fieldFocused)`），
   与 WorkspaceHostView 无父子关系（inspector 列内容是 WorkspaceHostView
   的修饰符兄弟而非后代）——「跨 view 字段桥接形执行批定」不是机械改，
   需要 mirror store（@FocusState onChange 写共享态，change-driven）或
   状态上提，两条路线的行为面都该钉。
5. **columnVisibility 槽无 gate=false 数据源**：该键唯一发布点 =
   `legacyBody:287`（亲核 grep 全仓）；gate=false 面从不发布它（View
   toggles 读 nil → `workspaceToggleBinding` false 面，LightamerApp
   :476-482）。carrier 四槽形（workspace + columnVisibility +
   exportPanelRequest + metadataFieldFocused）里的 columnVisibility 槽
   在 gate=false 面没有可发布的值——RESEARCH §3.2「5→1」双面想象的
   残留，照抄会引入一个恒 nil/恒占位的死槽（若消费端「carrier 优先」
   读到非 nil 占位还会改变 View toggles 现行为）。

**修法**：

- 钉目标拓扑（写进 T3 action 1）：①InspectorView 两构造点传 face 标记
  （或以注入参数承载），`:429` 旧键发布**仅 legacy 臂保留**；②gate=false
  臂 @FocusState 经 onChange 镜像进共享 store（change-driven 钉），
  WorkspaceHostView carrier get 读 store——实现真 3→1 且 legacy 零回归；
  ③SC 与 AC 的措辞钉死「gate=false 面 focusedSceneValue 发布点 3→1；
  legacy 面 publish 面字节冻结零触」；④columnVisibility 槽从 carrier
  删除，或 DECISIONS 申报恒 nil 语义 + 消费端回落链核验。

### F-2【minor｜T3】T3 sample 计数对的采样面未钉——修后死环面上四符号前后双触底，「可测下降」地板化不可测

- T1/T2 完成态 build 上，空载面（案 A+B）与编辑器面（分支 A）的菜单环
  **已饿死**——此时再采 sample，makeMainMenu/updateMainMenu/prependValue
  在「前」读数就已是 ~0；T3 后再采 = 0 vs 0，「可测下降」无信号面
  （F1 可观测性家族：验收机制对预期态失明）。FIX2/M7-1 RESEARCH 自己
  注记过「sample 帧计数概率性差异——签名一致性 = 判据，非计数一致性」
  （RESEARCH §0.2）——单窗 6s 计数直接比大小本就有噪声面。
- **修法**：钉采样面 = **flag-off 臂**（环活着，churn 82-90%/23-34%
  域）为 T3 前后对照的主判据面（分支 B 时加编辑器面为第二面）；每面
  ≥2 窗取中位；下降判据给数值形式（如 prependValue 降 ≥40%——3→1 的
  预期形状——或如实记录 + 机制面证明：carrier 单发布点的代码级断言）。

### F-3【minor｜T3】shortcut gate 收窄的目标集按现码疑似空集——「纯削重挂热帧」收益预期失实

- 亲扫 Commands 块（LightamerApp.swift:1502-2241）全部 29 个
  `.keyboardShortcut`：gate=false 面**不可见**的命令 = sessionNew/
  sessionOpen/sessionClose（MenuCommandSet gate=true-only 族）——它们的
  Button 与 shortcut **已经整体在** `if visibleMenuCommands` wrap 内
 （:1504-1508 / :1530-1541 / :1553-1559 区段亲读），本就不挂载、本就不
  重挂；gate=false 面可见的全部无条件件（⌘O :1527、⌘N、⌘⌥O、⌘⇧I、
  ⌘S、⌘⇧E、undo/redo、⌘⇧C/⌘⇧V、⌘⌥S/⌘⌥I、rating/flag/color 裸键、
  ⌘? 等）均属可见命令（plan 自己点名 ⌘O 原位不动）。
- 即：action 2 字面目标「挂在 gate=false 面不显示命令上的**无条件件**
  → 移进 wrap」在现码上**目标集 = ∅**；「逐个核对」退化为审计确认，
  「纯削重挂热帧（mangled-name 与 shortcut 件数正相关）」收益预期 = 0。
- 且「隐藏命令的 shortcut 本就不触发，移 wrap = 零行为变更」这一前提
  在 macOS 27 上未经本仓实测——若框架对不可见件仍注册 shortcut（未证），
  移 wrap 反而是行为变更。
- **修法**：action 2 改写为「29 shortcut 逐个审计三产出：①隐藏命令已
  wrap 确认清单；②无条件可见件清单（原位不动声明）；③『隐藏即不触发』
  前提的一次 flag-off 臂实测（隐藏命令 shortcut 按键 → 无响应截图）」；
  收益预期改如实（零码或微码）；若审计发现真有 wrap 外隐藏件（本评审
  扫描未见到，但不排除 :1560-2241 段个别），按原方案移 wrap 并逐件
  DECISIONS 记录。

### F-4【minor｜T1】files_modified 漏 `ProjectReadOnlyFaceTests.swift`——banner AX 回归套件直接构造 WorkspaceHostView，flag 参数必触其构造点

- 亲验：`Tests/LightamerTests/ProjectReadOnlyFaceTests.swift:571`
  `WorkspaceHostView(projectController:onImportFolder:)`（裸构造）+
  `ToastFaceTests.swift:69` 同形。按 LibraryLegacyGate 孪生纪律
 （KD-1 单读点：生产装配点唯一求值、plain Bool 分发——LibraryPreferences
  .swift:17-25 注记正本），WorkspaceHostView/ContentView 新增 flag 参数
  应为**必需参数**（带默认值 = 第二求值点，违孪生范式）→ 两个测试文件
  的构造点同批更新。
- files_modified 只列了 ToastFaceTests + SheetEnvironmentInjectionTests，
  **ProjectReadOnlyFaceTests 缺席**——:317-361 的
  `testBannerAccessibilityFace` 正是案 A 座移的第一回归面（它只认
  `shell.readonly.banner` identifier，座移后预期自愈绿，但构造点编译
  必破）。front-matter 失真 = M-6 前科家族。
- **修法**：files_modified 补该文件；或按 Sheet 套件同款写「预期零 diff
  （断言只认 AX identifier）；破绿 = 座移面审」注记——二选一，不许
  缺席。

### F-5【minor｜T1 案 B】M-3 教训的「页开→页关 shell 状态存活」走查行未随迁

- `FIX2-01-PLAN-REVIEW.md` M-3 对同风险面（条件挂载 `.inspector`/列）
  的修法②明确要求：「页开→页关一轮后 shell 状态存活（编辑器 phase/
  图库网格/选中不丢）」入重验清单。本 plan T1 案 B 正是该风险面的真
  行使（条件尾列 = 页开挂载/页关卸载的结构变化），但 T1 走查三件
  （toast/横幅/M6-1 对话框）+ AX 断言族均不含此行；AC 的「film 页分支
  结构性可达性回归钉」只钉可达性、不钉存活。
- **修法**：T1 走查补第④件：export 页开→关一轮后编辑器 phase/图库
  选中/网格模型存活（截图或 AX 断言）；或落一条 AX 机检（Sheet 套件
  邻域，座移面审时顺带）。

### F-6【minor｜T6】挂账④双通道矩阵的 cmd+click 腿与两代 harness 判死记录冲突；AXPress 腿对 cmd+click 目标无机制定义

- 亲验矛盾链：FIX2-01-SUMMARY §5「D4-01 = Blocked-Channel（**cmd+click
  多选旗标判死再证**——两次独立通道）」+ FIX2-01-PLAN-REVIEW N-2「CGEvent
  键盘事件全程不进 app（键盘路径判死）」——而 M7-1 RESEARCH §5.3 提议的
  `cliclick kd:cmd c:x,y ku:cmd` 配方，其引证先例（T3 `dc:` 双击可达）
  是**纯鼠标事件**，不含键盘修饰键腿；`kd:cmd` = CGEvent 键盘路径 =
  两代判死的同一族。plan T6 波 3 照方开 2×2×N 矩阵，kd:cmd 腿有
  结构性存疑。
- 且矩阵的 AXPress 腿（`osascript click` / AXPress action）**没有修饰键
  参数**——「cmd+click 多选」目标的 AXPress 通道无定义机制（可行候选 =
  AX `AXSelectedCells` 属性直写，RESEARCH §5.3 未提）。
- **修法**：波 3 前置 kd:cmd 有效性探针（已知多选目标上旗标生效与否，
  截图判读）；失效则该腿如实 Blocked-Channel + 改 AXSelectedCells 直写
  为对照腿；矩阵表述从固定 2×2 改「目标 × 可用通道」，挂账④呈报件
  登记「第三通道尝试 + 判死记录引证」。plan 已有「通道受阻 = Blocked
  如实登记」兜底，本条修的是 AC「双通道对照表在案（N≥3/通道/目标）」
  在通道判死情形下的可达性——按现文执行 AC 无法兑现。

### F-7【minor｜T2】C3 scratch 与产线落地的代码同体性未钉——二次实现漂移风险

- 分支 A「C3 饿死 = 落产线」：scratch 若按插桩先例形（主树临时改 +
  判定 + `git checkout --` 回退）做，产线落地 = **同一 diff 的二次
  手摇重放**——重放走样（可收起 overlay 的细节、collapse 状态、
  转场动画）时，scratch 判定通过的是 A 代码、产线落的是 B 代码，
  判定效力被稀释；/tmp 分叉副本形更糟（跨目录二写）。
- **修法**：钉 scratch = **主树工作区未 commit 改动**（不回退）；
  分支 A 行使 = 同一工作区 diff 转正（补 flag-off 臂 + flag 参数后
  commit，即 scratch 原样晋升）；分支 B = `git checkout --` 恢复 +
  产线零 diff 机检兑现。「scratch 零产线 commit」红线对分支 B 的兑现
  口径同步写明（回退后 diff 面为零）。

---

## 二、注记（不要求修订，执行批知悉）

### N-1 挂账⑥ 时序亲核结论：RESEARCH 再现 1 例 = 修后证据，plan 前提自洽，无修订义务

- `ImportProgressCoalescer` 落地 commit = `da99ea2f`（FIX2-01-SUMMARY
  §2）；M7-1 RESEARCH 复验批 HEAD = `14ee3993` ⊃ da99ea2f——§0.4.1 的
  再现 1 例（probe 16:12 FAIL + DB WAL 6 行）**是合流修之后的证据**；
  post-T2 11 轮 3 轮零行（FIX2 SUMMARY §2）同为修后。T4 N≥3 复测的
  两个分支判据（零再现 =「修后证据」注记 / ≥2 轮再现 = 呈报立项）与
  「churn 饥饿面假说」时序自洽 ✓。D-FIX2-4 勘误口径（行恒落库 + grid
  刷新迟到，禁再循 insert 路径）plan 引用正确。

### N-2 flag 形态亲核：LibraryLegacyGate 孪生可行，两处细节执行批注意

- 孪生范式正本 = `LibraryPreferences.swift:28-41`（单读点纯函数 +
  装配点一次求值 `LightamerApp.swift:432` + plain Bool 分发
  `:514`）——`ShellReducedTreeGate` 的 UserDefaults + env 双源比孪生
  多一维（LibraryLegacyGate 是 env-only），注入面
  `isReducedTreeEnabled(environment:defaults:)` 形态正确；优先级
  env > defaults > 缺省的测试三分（+2..3 法）覆盖缺省 ON / false off /
  env "0" ✓。
- 细节①：测试宿主进程的 env 与 UserDefaults suite 注入路径不同——
  env 三分测试用字面字典 ✓（孪生先例），UserDefaults 三分用隔离
  suite（LabelingPreferences 先例 `defaultsSuiteName`）——plan 未点名
  suite 注入形，执行批按 LabelingPreferences 先例走即可。
- 细节②：**flag-off 臂的 env 注入路径**——`open -a` 走 launchd 不透
  env；判别臂与 GUI 走查启动必须直接二进制 + env 前缀（`script -q` /
  `env LIGHTAMER_REDUCED_TREE=0 <bin>`，RESEARCH §0.4 PID 陷阱同域）。
  建议执行批在 t1-* 证据文件头记启动命令行（可复现性）。缺省 ON 的
  迁移安全：charter 四裁已授权 + env 逃生口在案 + AGENTS 键族登记
  （T7）= 开源自用项目可接受；README 端用户注记可选（非义务）。

### N-3 案 B 列活态的 churn 重燃面未测——判别矩阵建议补一读数

- C1 证据的燃料 = SystemSplitView 分栏宿主的**存在**（inspector 关闭态
  仍 churn）。案 B flag-on 臂在 export/film 页**打开时**重新挂上尾列
  （自绘 HStack + InspectorView，无 NSSplitViewController 机制）——该
  树形是否越 threshold **未测**（E 系只测过摘除与现形）。若列活态
  churn 重燃，用户开 export 页期间空载面仍烧（表型与「零 churn 包」
  表述冲突）。建议 T1 判别矩阵补一读数：flag-on + 页活态 CPU/
  transcript 各一组，如实登记（预期：自绘列轻于 SystemSplitView，
  但不设门——登记面）。toast 活态（4s 窗）同理可选。

### N-4 案 B 宽度语义措辞二义——DECISIONS 落一句终式

- T1 action 3「宽度 = ideal 240 **钉死**（`layout.inspectorWidth` 记忆键
  **保留读取**，缺省回落 240）」——「钉死 240」与「记忆键读取」字面
  冲突。D-M7-1-6 正解 = ideal 应用记忆键值（`clamped(inspectorWidth,
  200, 460)`，缺省 240）、「钉死」义 = 不实现新拖拽。执行批若硬编码
  240 常量 = 老用户列宽记忆被静默重置。建议 DECISIONS 终式写全式
  `ideal: clamped(inspectorWidth, 200, 460)` 一句钉死。

### N-5 判据二「消失或降底噪」无数值谓词（F1 家族）

- T4 判据二「环符号消失**或降底噪**——符号计数 vs 基线对照表」：后半
  无阈值。且 E-1 修法（底噪带）落定后，AppKit 11Hz 残留环可能维持
  updatePreferences/invalidateProperties/requestUpdate 小额计数——
  建议谓词拆两组：菜单环核心符号（makeMainMenu/updateMainMenu/
  prependValue/mangled-name）= 归零或 ≤1；AppKit 骨架族（Source1/
  layoutIfNeeded/preferencesDidChange）= 归类注记非门。机检性补全。

### N-6 transcript 稳态窗与统计量两处机检钉法

- ①「10s 窗 0 行」的窗选取规则未钉（~3min 捕获头部含挂载事件、尾部
  含交互）——建议钉「捕获 ≥60s，门窗 = 末尾连续 10s（计数脚本机械
  取段）+ 全窗计数同录」，杜绝 cherry-pick 空间；T4 判据三同款。
- ②CPU ps 系列「逐点值落证据文件」缺判定统计量（max/median/全点），
  flag-off 对照带「复现 23-34%」同样未定——建议钉 median（或全点
  ≤门+2pp 容差）并在证据头声明；flag-off 带照此。
- ③`--bundle App` 全绿与 ΔN 对账、红线族机检清单、T5 批准制 + 8G 门 +
  MEMFAIL、T6 零硬造条款——亲核全在位（`test-direct.sh` 8G 门
  RSS_LIMIT_MB=8192 先例复核过；本批非 RAW 供件域，skip 35 口径不触）。

---

## 三、放行面复核结论（逐维度对简报七问）

1. **T1 flag 形态**：孪生范式可行（N-2 亲核），launch-immutable 构造保
   @State 身份（M-3 不触——flag 臂进程寿命内不翻转，亲核 ContentView
   :175-241 三臂分支形兼容）；判别臂可观测性 = SC 双臂对照带 + N-2②
   env 注入路径钉 + F-9 统计量钉；缺省 ON 迁移面 = charter 授权 +
   env 逃生口，可接受；**底噪矛盾 E-1 须修**。
2. **T1 案 A+B 改造面**：inset 迁移布局等价面亲核（零高度语义
   ToastFaceTests 法 1 / banner AX 法 :317-361 均只认 identifier 与
   高度契约，座移后自愈路径在案）；建议补布局断言 = F-5（页开页关
   shell 存活）+ N-3（列活态 churn 读数）+ 走查三件覆盖充分性 OK
   （M6-1 对话框不受座移影响，走查确认即可）；legacyBody 零 diff 落点
   （:243 起）亲核正确；files_modified 缺 ProjectReadOnlyFaceTests
  （F-4）。
3. **T2 C3 scratch 门**：形态二选一（/tmp 即弃 vs feature-gated）在
   F-7 收敛为第三形（主树工作区未 commit + 同 diff 转正/回退）——
   可裁定性补钉后成立；「饿死 = 产线落地」判据（<10% + transcript 近零）
   编辑器面饿死时实测归零（E1/E2/E3 = 0.0-0.1%）无底噪矛盾 ✓；不饿死
   分支呈报件四项（C3 读数 / C1 损失 / C2 损失 / 窗拆读数）完整性 ✓，
   裁定权归属钉（呈报 = orchestrator 汇报层非 agent 自裁）plan 文面
   逐处一致 ✓。
4. **T3 燃料减频**：carrier 合并的取值正确性——⌘E/⌘W/⌘F 消费链亲核
  （LightamerApp :461-472 focusedWorkspace → visibleMenuCommands →
   gate wrap；carrier 挂载发布腿天然覆盖 priming，M-2 教训以「启动即按
   走查点验」随行 ✓）；**桥接面 3→1 可达性 F-1 须修**；采样面 F-2 须修；
   shortcut 收窄 F-3 须修；phase 镜像注意 Scene 面限制（M-7 同族——
   onChange 挂不了 Scene，落 View 层，执行批知悉）。
5. **T4/T6**：挂账⑥时序亲核 = 修后证据，前提自洽（N-1，无修订）；
   双通道对照 F-6 须修；排除行清单完备性——32/33 已入波 2 ✓（FIX2
   M-4 闭合）、10/12/14 排除注记由 T6 action 6 泛条款承接（FIX2 SUMMARY
   §5 已兑现过一轮，T6 read_first 含 m6-closeout MANIFEST，执行批逐行
   引用即可，不另设修订）。
6. **ΔN 带与 SC 机检性**：+2..6 = T1 gate +2..3 + 座移随迁 0..1 +
   T3 +0..2 + T2 0，上下界精确闭合 ✓；baseline 3860/35/0 与
   FIX2-01-SUMMARY 终值一致、现 HEAD 全 docs 未漂移 ✓；skip 35 = 24+11
   口径维持 ✓；F1 可观测性教训全 SC 扫描 = E-1（CPU 门失明于底噪）+
   F-2（计数对地板化）+ N-5（判据二无谓词）+ N-6①（稳态窗裁量空间）
   四处，其余 SC（transcript 行计数 / DB 行数机检 / 对账闭合 / 红线
   逐条机检）均可机检 ✓。
7. **独立猎残**：F-4/F-5/F-7 为简报维度外产出；未发现结构性驳回项
   （七任务序 / 双钉裁定权 / 暂停开关现值 auto=true paused=false 亲核 /
   呈报层措辞 / 封存面 17 件与壳树三文件零交集亲核 / xcstrings 预期零
   diff 的 C3 collapse 控件逃生条款在案——若 collapse 控件确需新 AX
   文案走尾块纯插入 + DECISIONS 申报）。

## 总评

**须修后放行（1 error + 7 minor + 6 注记）**。本 plan 的组合裁定
（案 A+B 已证判据打包 → C3 零损失期权 → 呈报层双钉）、判别臂纪律
（flag 回切 + transcript 决定性判据 + 越带停手）与裁定权归属（呈报 =
orchestrator 汇报层、agent 不自裁有损形）是突出强项，FIX2 三先例教训
（M-2 priming / M-3 结构身份 / M-7 Scene 探针）逐条有随行钉。E-1 是
唯一 error 级：SC 把 CPU 门钉在证据正本已预测不可达的数字上、且 plan
内部注记与 SC 相反——不修订则 T1/T4 验收环节必然 face 一个无授权裁定，
这与 FIX2 T1「如实 BLOCKED」的教训同样昂贵。7 处 minor 全为钉子/簿记级
（F-1 桥接拓扑、F-2/F-3/N-5/N-6 可观测性谓词、F-4 簿记、F-5 走查行、
F-6 通道机制、F-7 scratch 同体性），修订量级行级，不动任务序、波次与
治理。修订完成后可派发。

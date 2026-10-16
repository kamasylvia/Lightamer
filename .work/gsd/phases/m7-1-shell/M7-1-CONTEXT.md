# M7-1 CONTEXT — D-6 壳专项（OQ-M7-1-1..6 裁决落签，2026-10-16 夜间）

> Phase = M7-1（ROADMAP §M7 站 M7-1 行 + REQUIREMENTS SHELL-01..05 +
> M7 站 charter 2026-10-16 四裁之①「接受降级 + gate=false 壳减树/窗口
> 内容拆分专项」）。本文 = OQ 裁决正本；读解正本 = 同目录
> `M7-1-RESEARCH.md`（复验门三判据亲跑全复现 + SHELL-01..05 五块测绘 +
> 路线推荐 §6 + OQ 六条原文 §7 + 验收铁条草案 §6.2）。
>
> **授权注记（夜间全自动授权批，晨审可推翻）**：本裁决为夜间全自动授权
> 批落签（先例 D-07-3-T5-1；M6-3/M6-4 CONTEXT 同款），六项全按
> RESEARCH 推荐采纳；M7 站 charter 用户「按推荐」已授权 + 站内
> auto-advance（`config.toml [gsd] auto=true / paused=false` 亲核）。
> 晨审/用户可随时推翻，推翻项回注 plan 修复批重走（M6-3 先例形）。
>
> 状态：research 定稿（`M7-1-RESEARCH.md`，commit `5f2bc07a`）→ OQ 裁决
> 落签（本文）→ plan round（`M7-1-01-PLAN.md` 同批起草，单 plan）。
> 基线 = FIX2 终态 `3860/35/0`（HEAD `5f2bc07a`，research 亲核
> `2427670e..HEAD` 零产线文件——基线未漂移）。

## Phase Goal（ROADMAP M7-1 行锚定）

接受降级路线落地（H2 = macOS 27 SwiftUI 框架共犯——修法 = 减树/窗拆/
燃料减频，非根治承诺）：①gate=false 壳减树（案 A inset 迁移 + 案 B
inspector 列改造，feature-flag `shell.reducedTree` 门控可回切对照）+
案 C 三段重组（C3 零损失形 scratch 实验门先行）②编辑器面独立 NSWindow
路线评估（research §2 已裁定：不作主修、挂账结构终案备选）③菜单环燃料
面减频（焦点写点合并 + shortcut gate 收窄 + phase 镜像断边）④上游通道
（Apple Feedback 用户手动提交 + macOS 27.1 release notes 监测节律）⑤
走查专项卷与复测波（SHELL-05 五波行集 + 挂账④⑤⑥ 消解义务）。
验收形态 = D-6 复现配方 churn 探针转绿（三判据）+ 走查复走行集逐行销账
或如实登记 + FB 案号登记；SC 数字门 = phase 终验全套轮判定式。

## 裁决（D-M7-1-1..6，全按 RESEARCH 推荐；生效值 = 硬约束）

### D-M7-1-1 案 C 功能损失裁决序 = C3 实验先行；不饿死则呈报用户（OQ-M7-1-1）

第一刀案 A+B（空载面零 churn 包）落地后，第二刀只跑 **C3 形**
（HStack 三段 → viewport hero + 可收起 overlay——零功能损失重组形）
的 **scratch 实验门**。C3 饿死（编辑器面 <10% 硬门 + transcript 稳态
零重估）→ C3 落产线（flag 门内），为零损失主修；C3 不饿死 → **C1
（右栏并入 inspector 列，偏离 Alcedo 三段 IA）/ C2（filmstrip 收
弹出层，常驻性损失）呈报用户二选一**，窗拆实验数据（同批顺带采数）
并列呈报——**两形均有真实 UI 对标损失，不默认代选**。

**裁定权归属（呈报层钉，非 agent 自裁）**：C1/C2 的功能损失取舍 =
**用户裁决**；worker 只负责把三选项数据（C3 实测读数 / C1/C2 功能损失
陈述 / 窗拆 scratch 读数）登记 DECISIONS + SUMMARY，**呈报动作 =
orchestrator 汇报层**——agent 不得自裁行使 C1/C2/窗拆落地产线。
呈报前编辑器面 <10% 硬门诚实保持未达（接受降级残余，FIX2 T1
BLOCKED 分支先例形），T3..T7 在接受降级基础上不受阻继续。

### D-M7-1-2 SHELL-02 窗拆不立项，挂账「结构终案备选」（OQ-M7-1-2）

窗拆（案 D / SHELL-02）**本 phase 不立项**。评估报告正本 =
RESEARCH §2（四面改造评估 + spin 饿死性偏悲观〔C1 反证：inspector/
inset 非编辑器面持续条件，三段内容才是〕+ L 级量化 2-3 plan 波）。
挂账触发条件（满足其一即向用户呈报行使评估）：

1. 案 C 三形（C3/C1/C2）scratch 实验全数不达 <10% 硬门；
2. 案 C 落地后 27.x 系统更新环复燃且减树再无效；
3. 用户明确偏好窗拆 IA（代价知情——L 级 + Alcedo 单窗三段对标偏离）。

窗拆 scratch 实验数据在案 C 实验批**同批顺带采数**（半天级，两实验
一并），采得数据随 D-M7-1-1 呈报件并列呈报，零产线代码。

### D-M7-1-3 FB 提交 = 用户现在手动提交；两处勘误随批落稿（OQ-M7-1-3）

**现在就提交**（用户手动，Nitro LUT 先例）——缺陷在 macOS 27.0.1
（build 26A434）全量复现，框架侧修复价值独立于 app 侧减树；等减树
落地后提交只会让稿面数字过时。提交前落 RESEARCH §4.1 两处勘误（随
本 plan T7 批落稿，落点 = `research/APPLE-FB-D6-DRAFT.md`）：

1. **"~60 Hz" → display-cycle-locked（~60-120 Hz per display
   refresh）**——本批复验 119 passes/s = ProMotion 120Hz display
   cycle 锁频；FIX2 稿面 "~60 Hz" 为其测量窗 60Hz 屏读数；与「遮挡
   断环 = display-cycle 耦合」定性自洽。
2. **CPU 带补 98-100% 数据点**——静置口径（34-51%/82-90%）之外补
   「interact-after 98-100%」一句；两读数均已记录。

提交后 FB 案号回填登记（T7 登记待回填槽；案号到达 = SHELL-04 闭环
判据之一）。27.1 release notes 监测节律（GOAL-STATE 巡检义务：
Apple Releases / macOS release notes / Mr. Macintosh 三信源，关键词
menu/updateMainMenu/property graph/invalidation/SwiftUI；命中即在
下一批次复测 §0 配方三判据原样）随 T7 落 GOAL-STATE。

### D-M7-1-4 flag = 运行时 env/UserDefaults `shell.reducedTree`（OQ-M7-1-4）

`shell.reducedTree` = **运行时 flag**（非编译期 `#if`），形态 =
`LibraryLegacyGate` 同款先例：①**UserDefaults 键 `shell.reducedTree`**
（Bool，缺省 = true = 减树形态默认开）；②**env 覆盖
`LIGHTAMER_REDUCED_TREE=0`** = QA/判别回切通道（flag off = 现行
seating 逐字节复现——回切臂同时是全部实验的判别力基座）；③求值 =
**装配点一次**（LightamerApp 组装），可注入纯函数读点，view body 零
`ProcessInfo`/UserDefaults 直读（M2-1 D-EXEC-1 注入式同款）；④flag =
**launch-immutable 常量**（无 Settings 开关，LibraryLegacyGate OQ-8
「双形态并存心智负担」rationale 同款）——装配期 if/else 分支在进程
寿命内不翻转，@State 结构身份跨臂稳定由构造保证；⑤**UserDefaults 新
键 `shell.reducedTree` 登记** AGENTS 键族（T7 随批）；键零 UI 文案
（AGENTS.md 记载，不入 xcstrings）。

### D-M7-1-5 挂账⑥复测 = 案 A/B 落地后即第一轮，不等案 C（OQ-M7-1-5）

导入零行间歇（grid 刷新迟到族，FIX2-VALIDATION §挂账⑥）复测时机 =
**案 A/B 落地后即复测第一轮**（空载 churn 消失可能已解除 main-actor
饥饿面；不等案 C——案 C 落地与否不影响该面假设成立）。轮数 N≥3
（probe 配方：`-la_editor_probe` 建项目 → 杀进程重启 → zh 菜名 AX
腿 → 导入 ≥6 供件；每轮 DB 行数机检 + grid 刷新时点记录）。裁定：
N≥3 轮零间歇再现 → 表型以「修后证据」注记（churn 消解旁证，
非逻辑证伪——如实措辞）；间歇再现 ≥2 轮 → **独立待研立项呈报用户**
（report item，非 agent 自立专项）。D-FIX2-4 勘误口径维持（「行恒
落库 + grid 刷新迟到」，禁再循 insert 路径排查）。

### D-M7-1-6 inspector 列宽首批钉死 240 ideal（OQ-M7-1-6）

案 B 的 inspector 列改造：首批**钉死 ideal 240**（现有
`navigationSplitViewColumnWidth(min: 200, ideal:..., max: 460)` 的
ideal 值在减树列上应用；`layout.inspectorWidth` 记忆键**保留读取**
——缺省回落 240 ideal 语义不变）；**拖拽自实现挂账后续批**
（最小化第一刀面）。SystemSplitView 拖拽分隔 + 自动记忆功能在
flag-on 臂缺失 = 已登记功能损失（挂账行），flag-off 臂原样保留。

## 红线（phase 批次级，plan front-matter 承载 + T5 逐条机检）

- **零新 SPM 依赖**维持。
- **UserDefaults 新键唯一** = `shell.reducedTree`（D-M7-1-4）；键族
  登记随 T7。
- **`.metal` 全域零 diff**（本专项全 UI 域，无 kernel 义务；翻案先停手
  修订 plan 申报）。
- **xcstrings 预期零 diff**（flag 无 UI 文案；banner/toast/inspector
  座移复用既有键）；若执行批确需新键 = 尾块纯插入 + DECISIONS 申报。
- **`\.runModal(` App/Sources 零命中**（L057 禁令——面板一律
  `PanelPresentation.begin` 缝；菜单命令/按钮 Task hop）。
- **封存面零触**：壳树三文件（`ContentView.swift` /
  `WorkspaceHostView.swift` / `LightamerApp.swift`）**非封存已核**
  （planner 2026-10-16 亲核封存清单——DrtRecord/TerminalTailPolicy/
  DrtTailAssembly/PixelPipe/Lut3dKernels.metal/DrtEotf/
  ExportQueueContract/六格式导出矩阵/NodeGraphCommand/sidecar schema/
  HistoryStack/HistoryHash/PipelineDocument(Core)/V50Order/
  GradeCatalog/Registry/ModuleInstance）；**V50Order add-only**；
  **MCP 快照族零触**（本 phase 无 MCP 面；M7-2..M7-5 快照串行编排
  纪律不因本批启动）。
- **app-root 级 sheet 闭包禁止裸 `@Environment` 跨界**（M2-8 教训——
  内容面重注入或 init 参数注入二选一）；**无 if/else 翻 @State 面**
  （M-3 教训——flag launch-immutable 构造保证）；**M3-4-01 T4 挂载
  语义逐字迁移**（present no-op / dismiss 双关 + InspectorView 只在
  本宿主可达）。
- **`--all` 全套轮 orchestrator 批准制 + 运行 8G 门 + MEMFAIL 机检**
  （夜间授权链覆盖在案；AGENTS 资源监控节全程适用）。
- **测试宿主清理先核 parentage**（`ps -o ppid`，M2-7-3 事故先例）；
  PTY/harness 配方以 RESEARCH §0.4 三钉（zh 菜名寻址 / script 封装
  PID 陷阱 / PTY 行缓冲）为前提。

## 与先例的接口

- **FIX2-VALIDATION §挂账①** = 本 phase 本体（charter 四裁之①兑现）；
  **§挂账④**（点击表型双通道）→ plan T6；**§挂账⑤**（探针缝
  `exit(0)` 兜底）→ plan T6 顺手窗；**§挂账⑥**（导入零行间歇）→
  plan T4（N≥3 轮）+ T6 旁证；**§挂账②③**（D-FIX2-4 勘误 / T2 窄
  边界两枚）= 已落账 / 下批触 LibraryProjectController 顺手，本 plan
  不承载。
- **V2M-VALIDATION §挂账②** = m6-closeout Blocked-Channel 余行复走
  硬义务 → plan T6 波 2。
- **RESEARCH §5.2 五波行集** → plan T4（挂账⑥）+ T6（波 1/2/3 +
  挂账⑤ + D-FIX2-4 旁证）；H2 精确定性措辞引用不重写。

# V2M-01 / V2M-02 修订版 CHECKER（独立反向核，2026-10-13）

> checker 身份：独立目标反向核（fixer 修订后的两 plan 为对象，零共享
> 修订过程上下文；输入 = 修订版 `V2M-01-PLAN.md` / `V2M-02-PLAN.md` +
> `V2M-CONTEXT.md` + `V2M-PLANS-REVIEW.md`（对照 findings 逐条闭环）+
> 代码面 HEAD 亲验）。
> 修订基线 = commit `8846c219`（docs(v2m): revise plans per review）。
>
> **结论头**：
> - **V2M-01（修订版）= 放行**——零再修项。E-1/M-1/M-2/M-3/M-4 与 T5
>   绿例措辞五项修订全部落位且自洽；E-1 新挂点覆盖面经代码级穷举
>   （含第五路径猎残）无缺口；对账带算术闭合。2 条执行批注记（C-1/C-2，
>   不构成再修）。
> - **V2M-02（修订版）= 放行**——零再修项。E-2 三处补钉（供给面扩形 /
>   逐参有序比对 / golden 八例）落位自洽；M-3/M-4/M-5/M-6 全落位；两波
>   接缝（绿例措辞 / 对账链 / D-5 条件 / 06 行防双走）逐环核过。2 条
>   执行批注记（C-3/C-4，不构成再修）。

---

## 一、Goal-backward（修订版两 plan 达成性）

### V2M-01（波 1 = 五缺陷闭环 + 数字对账）

- **缺陷↔任务映射**：D-1→T1（快照去热读）/ D-2→T2（bisect 三段式）/
  D-3→T3（换图钉序）/ D-4→T4（arm 快照，两形态）/ D-5→T5（调用点
  Int 化）+ T6 收口对账——无孤儿项，与 RESEARCH §一.A 五行一一对应。
- **数字对账闭合**：T1 **+2**（两具名测试均必做，M-4 修订后）+ T2
  +1..2（供件缺席可合法记 0）+ T3 +0..1 = **+3..5**，与 front-matter
  `estimated_tests` / `expected_all`（+3..5）算术一致；files_modified
  的 ColorMatchPanelModelTests 行同步 `+2 法`——三处同批，无滑差。
- **SC→任务映射**：success_criteria 逐任务有观测点（T1 静态机检+单测+
  走查 / T2 transcript+修法+复验 / T3 加固脚本 / T4 标题 grep+走查 /
  T5 调用点 grep+zh-audit / T6 全套对账）——无 F1 型不可观测验收残留。
  T4 观测点措辞已随 M-1 扩为「读快照属性**或 payload**」，与 action 2
  两形态对齐。

### V2M-02（波 2 = 清算闭环）

- **清算项↔任务映射**：V17→T1（门扩展+活体清偿）/ Manual-Only 余行→T2
  （前置 = 波 1 D-1+D-2 闭环）/ PATCH-LIVEPLANE→T3、RELEASE-DIRECT-
  INJECT→T4（顺带候选，余量盘点先行）/ EXPORT-PRESET-01→T5（波尾）/
  D-5 条件并入→T6 步 1——RESEARCH §一.B/C/F + §四编排全覆盖，§一.D
  留置 5 项与 V2 大件 7 项未越批。
- **数字对账闭合**：T3 +0..2（销账形态 ΔN=0 合法，另记）+ T5 +2..4
  （波尾固定范围）= **+2..6**，与修订后 `estimated_tests` /
  `expected_all`（+2..6）一致；M-4 的「+0 不可达」理由（T5 非容量门
  任务）已入注记。V17 self-test = 脚本侧非 XCT 记 ΔN 0 不变。
- **SC→任务映射**：T1 self-test+check+xcstrings 纯插入 / T2 逐行终态 /
  T3/T4 盘点双向收口 / T5 预设单测+新键登记 / T6 全套对账——全机检，
  无缺口。

## 二、核心修订自洽（逐项代码级反向核）

### E-1 挂点覆盖面穷举（含第五路径猎残）

修订挂点 = `ColorMatchPanelView` 内 `.onChange(of: instance)`（或
`.task(id:)` 同效形）。逐路径核（HEAD 亲验）：

1. **实例切换**：`InspectorView.swift:341`
   `inspectorState.panelView(for: effective, edit: session)`——
   `effective` 从 `editableInstances`（editorState.instances 派生）
   逐次 body 求值现取，`instance` 为 view 的 `let` 携新值 → seam 触发 ✓。
2. **commit 后重渲**：`InspectorEditSession.endEditing`（IOPPanelProvider.
   swift:83-88）→ `coordinator.commitContinuousEdit` → commit 落
   editorState.instances → body 重渲携新 instance value → 触发 ✓。
3. **MCP `apply_params` 外部写腿**：SessionBatchApplier 直改
   editorState.instances（评审证据链）→ 同 2 → 触发 ✓。
4. **undo-redo / 版本 swap（第五路径候选，已核成立并入覆盖面）**：
   `EditorState.rebuildInstances()`（EditorState.swift:448）doc comment
   明文「Rebuild the live set after **undo/redo/jump**」；调用点含
   `performUndo`（:384 域）/ `performRedo` / `installMergePaste`（:338
   域）等 7 处——历史移动后 instances 重建 → 新 ModuleInstance 值 →
   body 重渲 → 触发 ✓。修订版 Checker 关注点 #3 的枚举（solve 回填 /
   commitStrengthDrag 尾 / 实例切换 / commit 后重渲 / MCP 外部写 /
   undo-redo 与版本 swap）与代码现实一致。
5. **无第六路径**：colormatch committed truth 的唯一写入面 =
   editorState.instances（IOPPanelProvider.swift:41-43 UI red lines
   「Panel values READ from EditorState.instances records」单源注记；
   拖动 tick 走 `update(_:)` = `setLiveParams` **PREVIEW-only 零
   history 零 instances 写**，IOPPanelProvider.swift:73-80——故 seam
   不 per-tick 触发、无 per-tick 解码回归，且只对 committed 变更刷新，
   与 :96-98「committed truth, never a stale cached copy」语义相合）。
   拖动窗闭合序 = commitStrengthDrag 尾同步刷（末次 live 值，即时正确）
   + commit 异步落地后 onChange 再确认（终态）——双保险闭合。
6. **藏面板边缘**：实例变更时面板不在层级 → 无 onChange；面板复现 =
   view 重建走 init（刷新点①）——闭合。

> 结论：覆盖面穷举成立，无第五漏路径。`ModuleInstance` 为
> `Equatable, Hashable` 值类型（LightamerCore/Sources/Pipe/History/
> ModuleInstance.swift:44）是 seam 正确性的类型前提，已亲验在位。

### E-2 逐参比对与 golden 八例自洽

- **供给面 ↔ 绿例可达性**：D-5 修后调用点
  `Int((holeFraction * 100).rounded())`（LightamerApp.swift:2019，
  `holeFraction: Float` 为 :2017 函数参数）——供给面含「函数参数声明 +
  `Int(…)` 包装调用形」后推导为 Int → `%lld`；目录
  `toast_hdr_merge_done %lld` **PRESENT 亲验**（xcstrings JSON 实查）
  → 绿例可交付，V2M-01 T5 头注 / V2M-02 T1 action 3 / V2M-02 Checker #2
  三处措辞同批对齐 ✓。
- **逐参有序比对 ↔ 位置洞**：`settings_catalogs_rebuild_progress` 两
  调用点亲验在位（App/Sources/Lightamer/Settings/SettingsPages.swift:
  1406 + App/Sources/Lightamer/UI/CatalogBrowserView.swift:71，均双参）；
  `session_counts`（SidebarView.swift:372，三参）/
  `toast_import_partial`（LightamerApp.swift:943，双参）亲验——集合
  交集形的放行洞真实存在，有序比对（长度 + 逐位）将其关闭 ✓。
- **golden 八例**：①-④ 承 V16 四例；⑤位置错配红（`[String, Int]` vs
  `%lld %lld`）与判定式修订互为镜像 ✓；⑥ Int32→`%lld` 正例 =
  全 Int 族映射锚（`mcp_launcher_status_running %lld` 变体 PRESENT
  亲验）✓；⑦ Float=Double 同映射 `%lf`（D-5 样本同款）✓；⑧注释免疫
  （LightamerApp.swift:2058-2065 doc comment 内插值字面活体亲验——
  V15 form 1c「注释行保持 pending」逻辑延伸到 Text 族 regex，误报源
  预防）✓。八例与判定式/供给面/映射表三面自洽，无互相矛盾例。

### M-1 两候选判定标准（可操作性核）

- 判据链成立：`pendingTargets` 全文件无清空路径（亲验：7 处 arm 写
  :152/:157/:168/:180/:191/:199/:205 + 捕获读 + :433 @State 声明，零
  removeAll）→ 「数组被清空」排除；GUI-M6C-13 动作面正确 targets 跑通
  → 状态店未整体失效 → 收窄至「呈现时点陈旧快照」vs「视图身份/状态店
  重建」两候选 ✓。
- 判别探针可操作：修订版 action 1 前置取证（「取 0 时点 + 状态店存活
  证据」AX harness + 同窗 M6C-13 对照）；action 2 按定案择形——候选②
  （陈旧快照）→ @State 快照；候选①（身份重建，@State 同灭）→
  `.sheet(item:)` payload（payload 随呈现项携带，与状态店/快照两机制
  解耦，两候选下都鲁棒）。**机制定案若判错形，走查 AC（三对话框标题
  计数正确）仍是硬门**——最坏损失一轮返工，不产假交付；风险节
  「快照上移」预案保留。判定标准充分。

### 两 plan 接缝

- **绿例措辞**：三处（V2M-01 T5 头注 / V2M-02 T1 action 3 / V2M-02
  Checker #2）供给链表述一致（函数参数 → `Int(…rounded())` → Int →
  `%lld`），且都声明「供给面缺形 = EXEMPT 非绿 = 失守哨兵」——波间
  交叉引用单源 ✓。
- **对账链**：3848 → +ΔN₁（+3..5）→ 波 1 终值 → +ΔN₂（+2..6）逐环
  可追；两 plan `expected_all` 均对账式精确判 ✓。
- **D-5 条件**：V2M-02 T6 步 1 条件并入原样；波 1 T5 修法 + E-2 供给
  面下主形态即清——条件步零动作记一行即可 ✓。
- **06 行防双走**：V2M-01 T1 action 6（数值面本批走、色彩目测挂波 2）
  ↔ V2M-02 T2 余行集 06 条款（波 1 数值面以波 1 证据为准不重跑，本波
  只走 D-2 解锁后剩余面）——两 plan 同批闭环 ✓。

## 三、findings 闭环对照（review → 修订 → checker 复核）

| finding | 修订落点 | checker 复核 |
|---|---|---|
| E-1 | V2M-01 T1 action 1②④ 重写 + 头注 + 风险节 + files_modified 两行 + Checker #3 | §二 E-1 穷举，代码级证实 |
| E-2 | V2M-02 T1 深检/断言 6/golden 八例 + action 3 + Checker #2 + V2M-01 T5 头注联动 | §二 E-2，目录变体实查 |
| M-1 | V2M-01 T4 头注两候选收窄 + action 1 前置 + action 2 两形态 + AC/SC 措辞 | §二 M-1，判据充分 |
| M-2 | V2M-01 T2 action 3 重指 untracked 供件机制 + AC 措辞 | 两 tier 设计引用一致 |
| M-3 | 两 plan 红线各两处（blockquote + red_lines 节）钉形 + 双豁免锚 | :2061 注记 / :433 拼接形亲验 |
| M-4 | V2M-01 T1 +2 / V2M-02 带 +2..6 | §一 两处算术闭合 |
| M-5 | V2M-02 T5 范围句钉死 + files_modified 措辞 + 单测面两增项 | 与 :401/KD-1 锚一致 |
| M-6 | V2M-02 T2 06 条款 + 30 行显式排除注记 + Checker #3 | 防双走两 plan 对齐 |
| N-1..N-8 | 无 plan 文本义务（D-5 偏离维持 / N-4 内证）；V17 绿例措辞 = E-2 联动已落 | N-4 D-5 偏离内证（xcstrings:23513 整数语义）维持成立 |

## 四、独立猎残（checker 自有产出）

- **C-1（执行批注记｜V2M-01 T1）**：`.onChange(of: instance)` 的闭包体
  写法注意 `model` 为 `@State ColorMatchPanelModel?` optional——钩子应
  挂在 `content(_ model:)` 作用域（model 非 nil）或以 `model?.update
  Instance` 解包；plan 文本 `{ model.updateInstance(instance) }` 为语义
  形非字面代码。不构成再修（挂点文件与语义已钉，字面形属执行批裁量）。
- **C-2（执行批注记｜V2M-01 T1）**：refresh 点④「从末次 live 值或重读
  record」两臂择一后，建议 DECISIONS 记明择臂理由（live 值臂免一次
  解码；record 重读臂更贴近「committed truth」语义——commit 已落地时
  两臂值应相同，竞争窗由 onChange 终态兜底）。现有文本已可执行，此为
  记账精度建议。
- **C-3（执行批注记｜V2M-02 T1）**：`mcp_launcher_status_running \(pid)`
  的 pid 经 `if let pid = model.runningPID` 解包（McpLauncherPanelView.
  swift:224-225）——跨类型属性链可能落在推导供给面之外（EXEMPT 非绿）。
  **不违 AC**：该键绿例 AC 只锚 D-5 键；McpLauncher 三键的义务是
  PRESENT（断言 5 层 + Text 族存在性门），变体 `%lld` PRESENT 亲验即
  过。golden ⑥ 为 self-test 合成例，不受 live 推导面影响。
- **C-4（措辞注记｜V2M-02 T1 头注）**：头注①摘要行的映射表仍写
  「Int→`%lld`」未带「全 Int 族」——action 深检块已载全表（含
  Int32/Int64/UInt），以 action 为准；纯摘要精度，零语义差。
- **负向猎残（未发现）**：T2 走查批零源码红线与提前口（OQ-VM-5）边界
  不冲突（走查 local-only 零 commit）；V2M-02 T5 封存面（六格式矩阵/
  ExportQueueContract/sidecar）与预设装配层无交集；T4 脚本形态不触
  Project.swift dependencies 块；config.toml `auto=true/paused=false`
  现值口径两 plan 均已挂 read_first。

## 五、结论

- **V2M-01（修订版）：放行**。五缺陷闭环映射完整，对账带算术闭合，
  E-1 挂点覆盖面代码级穷举无漏，执行批注记 C-1/C-2 随批知悉。
- **V2M-02（修订版）：放行**。V17 门语义三态+八例自洽，清算项映射
  完整，接缝（绿例/对账/D-5 条件/06 行）逐环核过，执行批注记 C-3/C-4
  随批知悉。
- 两 plan 可按既定波次派发（波 1 先行；波 2 的 T2 提前口随波 1
  D-1+D-2 验收闭环解锁）。

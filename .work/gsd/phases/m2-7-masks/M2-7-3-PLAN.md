---
phase: m2-7
plan: "M2-7-3"
title: "收口——Follow Edges 质量验证走查与复杂度熔断裁决（OQ-4-C 条款行使点）+ 性能观察（stamping golden 复验/缩略 pass 成本/双羽化手柄实时性，perf.md 记账，OQ-11 观察项清账）+ zh/en 对账（Scripts/zh-audit.py --check + 40-70 键补齐，OQ-12 A）+ REQUIREMENTS M2MASK-01..07 翻账 + GOAL-STATE/TODO 收口 + 验收移交清单"
wave: 3
depends_on: ["M2-7-2"]
autonomous: true
requirements: [M2MASK-01, M2MASK-02, M2MASK-03, M2MASK-04, M2MASK-05, M2MASK-06, M2MASK-07]
files_modified:
  - .work/gsd/phases/m2-7-masks/perf.md                    # 新建：phase 级性能账本（bench 记账 + 观察项终值）
  - .work/gsd/phases/m2-7-masks/M2-7-3-SUMMARY.md          # 新建：phase 收口 SUMMARY（含 Follow Edges 熔断裁决记录）
  - .work/gsd/phases/m2-7-masks/M2-7-3-ACCEPTANCE-INPUT.md # 新建：验收 subagent 移交清单（AC 指针 + 挂账 + Manual-Only）
  - .work/gsd/phases/m2-7-masks/evidence/m2-7-3/           # 新建目录：走查证据截图（视口裁剪纪律 §3.2）
  - .work/gsd/REQUIREMENTS.md                              # 修改：M2MASK-01..07 勾选 + Delivered 注记（锚 commit + 验收指针）
  - .work/GOAL-STATE.md                                    # 修改：M2-7 phase 续接点翻账（收口态 + 下一步）
  - .work/TODO.md                                          # 修改：M2 节推进记录
  - AGENTS.md                                              # 修改：M2-7 架构增量节（如执行批有新惯例沉淀）
  - App/Sources/Lightamer/**/*.l10n 处                     # zh/en 补键（zh-audit 对账产物；文件集以 zh-audit 输出为准——Localizable.xcstrings 单文件）
  - App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift # 仅当熔断触发：FollowEdgesMode 默认值翻 `.snap`（一行；完整流线挂账 V2）
---

# Plan M2-7-3 — 收口（质量验证 + 性能观察 + zh 对账 + 翻账移交）

> **性质**：phase 收口 plan——零功能新增；唯一可能的代码触碰 = 熔断条款行使
> （FollowEdgesMode 默认值一行翻转）+ zh 补键。规格锚点 = D-M2-7-CONTEXT-4-C
> （熔断）、11（观察项）、12（zh 对账）+ REQUIREMENTS M2MASK-01..07 全族。
> **先例口径**：M2-4-3 / M2-6-3 收口批（zh-audit --check 对账 + TAB/键矩阵 +
> 翻账 + 验收移交）。

## 已定裁决（不得重开）

- **D-M2-7-CONTEXT-4（OQ-4-C 熔断条款）**：若 P1 交付的完整流线追踪（`.streamline`）
  在本 plan 走查实测超预算（判据见 KD-1），行使熔断 = UI 默认值翻 `.snap`
  （边缘吸附）+ walker 代码保留 + 完整流线挂账 V2 **如实登记**（验收走查裁决，
  不静默降级不虚报交付）。
- **D-M2-7-CONTEXT-11（OQ-11 A 观察项清账）**：观察项 = 双羽化手柄拖动实时性、
  缩略 pass 成本、Follow Edges 交互手感——本 plan 逐项实测落 `perf.md`；
  超标 fallback（拖动中缩略窗口预览、松手全精）仅在超标时启用并登记。
- **D-M2-7-CONTEXT-12（OQ-12 A）**：phase 尾 `Scripts/zh-audit.py --check`
  对账补齐；预估 **40-70 键**（P2 面板/设置/Range/Follow Edges 参数/入口/toast
  族 + P1 内核残余 <5 键）；语言 code 沿 `zh`。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 Follow Edges 质量验证 = 合成 golden 已绿 + 真实样张走查 + 熔断判据

- **走查矩阵**（三景 × 两模式，证据截图入 evidence/m2-7-3/）：
  | 景 | 样张 | 判据 |
  |---|---|---|
  | 高对比直边 | 合成/建筑边缘 | 点链贴边（目测 + 边距采样 ≤ 1 brush radius）；streamline 与 snap 输出对比记录 |
  | 弯曲轮廓 | 人像/物体轮廓 | 跟随连续性（断链数 = 0 为过；断链 > 2 处 = 记缺陷） |
  | 低对比/噪声 | 平缓渐变区 | 阈值门生效（不出笔 + 状态条提示，不乱贴） |
- **熔断判据（量化，防「看着办」）**：满足任一即行使熔断——
  ① 交互延迟：seed 按下到 stamps 呈现 > 200ms 持续发生（真实样张 ×5 轮中位）；
  ② 正确性：弯曲轮廓景断链 > 2 处且 snap 模式显著更稳；
  ③ 边缘图读回在 100MP FULL 窗口出现可感卡顿（> 1 帧 @60fps 预算）。
  行使动作 = `MaskToolbarView` 默认 mode 翻 `.snap`（一行）+ SUMMARY/GOAL-STATE
  挂账登记（ walker 与 `.streamline` 分支保留，V2 复活零重写）。
- **判定纪律**：streamline 过门 = 默认 `.streamline` 交付（M2MASK-05 全量兑现）；
  熔断 = M2MASK-05 以 `.snap` 态 Delivered + 挂账注记（REQUIREMENTS 翻账措辞
  分歧预制：「Delivered（snap 态，streamline 挂 V2）」）。

### KD-2 性能观察 = 三项实测 + golden 复验，perf.md 记账

- **既有 golden 复验（回归性，非新 bench）**：stamping 0.744ms/千枚族、combine
  五式 parity、analytic golden、SidecarV5 零漂移——全套 `--all` 终跑即覆盖，
  计数入 SUMMARY。
- **新增三项实测（观察项，非门）**：
  1. 缩略 pass：单格渲染耗时（112px，drawn/parametric/raster 各一）+ 面板
     20 格滚动场景总耗时——口径 = Debug 构建(signpost 手测中位 ×10)。
  2. 双羽化手柄拖动实时性：拖动帧率目测 + 可感迟滞记录；超标 fallback =
     拖动中缩略窗口平面预览（OQ-11 预案，启用则登记为 V1.1 挂账——本 phase
     不再实现，预览降档属交互打磨）。
  3. Follow Edges 边缘图：首算耗时 + 缓存命中后零成本复核（同层连续笔画
     100 枚 seed 计时）。
- **记账落点**：`.work/gsd/phases/m2-7-masks/perf.md`（phase 级账本，AGENTS
  布局冻结条款：phase 级 perf.md 落 `.work/gsd/phases/<slug>/` 根）——三表 +
  环境行（机器/构建态/日期）+ 与 OQ-11 预算项逐条对照结论。

### KD-3 zh/en 对账 = zh-audit 机制对账 + 手工补键

- 终跑 `Scripts/zh-audit.py --check`（exit 0 为过）——先跑对账拿缺口清单，
  再补 `Localizable.xcstrings` zh 译（键来源 = P2 SUMMARY 键清单节 + P1 残余
  + 本 plan 零新键）；补完复跑 `--check` exit 0。
- **键范围防线**：只补 M2-7 键族，**禁顺手翻旧键**（历史键改动 = 噪声 diff；
  发现旧键错误记 TODO 不动）；AX 键（缩略图/面板可访问性标签）在册核查。

### KD-4 翻账与移交 = 单一状态源收口批

- **REQUIREMENTS**：M2MASK-01..07 逐条勾选 + Delivered 注记（锚 commit SHA +
  验收指针 `phases/m2-7-masks/M2-7-3-ACCEPTANCE-INPUT.md`）——**措辞按 P1/P2
  SUMMARY 实态**（T1 熔断触发则 M2MASK-05 带注记）。
- **GOAL-STATE**：M2-7 phase 续接点终态（三 plan 闭环 + 熔断裁决结论 + 挂账
  清单指针）+ 下一步 = M2-7 验收 subagent（C 档门控第 3 停前的验收批）。
- **TODO**：M2 节推进；**AGENTS.md** M2-7 架构增量节（新增惯例：边缘图缓存键
  口径/revision 写点全表/Default Behavior 键——沿 M2-2 增量节先例，仅当执行批
  沉淀了值得登记的惯例）。
- **ACCEPTANCE-INPUT**：验收 subagent 移交清单——AC 指针（三 plan AC 表）+
  熔断裁决记录 + 挂账（观察项残留/手册级限制）+ Manual-Only 候选（真机 HDR
  手感/100MP 走查）——验收批输入唯一入口（M2-5/M2-6 先例）。

## read_first

1. `.work/gsd/phases/m2-7-masks/M2-7-1-PLAN.md` / `M2-7-2-PLAN.md`——AC 表 +
   风险节（本 plan 验证对象的交付承诺）。
2. `.work/gsd/phases/m2-7-masks/M2-7-1-SUMMARY.md` / `M2-7-2-SUMMARY.md`——
   实态终数/键清单/偏差记录（翻账措辞与 perf 对照的正本）。
3. `.work/gsd/phases/m2-6-drt/M2-6-3-SUMMARY.md`——收口批先例（走查清单格式 +
   观察项挂账措辞 + 验收移交口径）。
4. `Scripts/zh-audit.py`（`--check` 用法）+ `M2-4-3` zh 收口先例记录。
5. `.work/GOAL-STATE.md` 续接点节 + `.work/gsd/REQUIREMENTS.md` M2MASK 族现文。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits 全英文；不 push；`.work/`
   真路径 add）。
2. **构建纪律**：`caffeinate -dis` 包裹一切构建（走查构建同）。
3. **测试纪律**：终跑 = `Scripts/test-direct.sh --all`（**报备制**：跑前
   SendMessage 报备 orchestrator）；**基线 = P2 SUMMARY 终数，0 fail**；
   Executed + failures 双读（L028）；MEMFAIL RSS ≥8G 机检；flake ×3 归因。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
5. **架构红线**：本 plan 功能零新增——除熔断一行与 zh 键外**零源码 diff**；
   `git diff --stat` 出现第三类文件 = 违约（收口核对 T4）。
6. **证据纪律（§3.2/§9）**：走查截图 = 视口截图关键区（禁全页长图）+ 图注
   带关键数字；识图/OCR 验证按 §9 链路（如需交叉核对数值）。
7. **checker 四条**（同 P1/P2 移植）：真链实测禁造假（走查亲测非引用 P2 截图）/
   登记（本 plan 无新测试文件，免）/ 语义断言可观测（perf 数字 + 截图成对）/
   边界核对（纪律 5 逐文件）。

## Tasks

### T1 Follow Edges 质量验证走查 + 熔断裁决

- **read_first**：上列 1/2/3 + `MaskToolbarView.swift`（mode 默认值落点）。
- **action**
  1. KD-1 三景 × 两模式走查（Debug 构建 + 真实样张；证据截图成对入
     `evidence/m2-7-3/`，图注带判据数字）。
  2. 熔断判据逐条实测记录（200ms 中位 / 断链数 / 边缘图读回帧影响）。
  3. 裁决落盘：过门 = 记录终值零代码改动；触发 = `MaskToolbarView` 默认值翻
     `.snap` 一行 + 提交 `chore(m2-7): follow edges default to snap mode`。
- **验收标准**
  - [ ] 三景 × 两模式证据在册；判据三项有数字。
  - [ ] 裁决结论明确（过门/熔断二选一，无含糊态）；熔断则挂账登记同步。
  - [ ] 全套回归 `0 fail`（若触发代码改动）。

### T2 性能观察三项 + perf.md 记账

- **read_first**：上列 2/3 + P1/P2 SUMMARY（预算项对照）。
- **action**
  1. KD-2 三项实测（signpost 手测中位 ×10 口径）+ OQ-11 预算项逐条对照。
  2. 落盘 `.work/gsd/phases/m2-7-masks/perf.md`（三表 + 环境行 + 结论行）。
- **验收标准**
  - [ ] perf.md 三表齐 + 数字成对（表值 ↔ 测量记录）；对照 OQ-11 预算项逐条
        有结论（达标/超标+处置）。
  - [ ] 超标项处置记录（fallback 启用与否 + 挂账指针），无静默超标。

### T3 zh/en 对账补齐

- **read_first**：上列 4 + P2 SUMMARY 键清单节。
- **action**
  1. `uv run python3 Scripts/zh-audit.py --check`（Python 走 uv 红线）拿缺口。
  2. `Localizable.xcstrings` 补 zh 译（M2-7 键族 40-70 键；旧键零触碰）。
  3. 复跑 `--check` exit 0。
- **验收标准**
  - [ ] 首跑缺口清单 + 补键 diff + 复跑 exit 0 三步证据在 SUMMARY。
  - [ ] `git diff` 核：仅键族内改动（旧键零触碰——diff 抽查）。

### T4 翻账 + 验收移交 + phase 收口

- **read_first**：上列 5 + 三 plan 全部 SUMMARY/DECISIONS。
- **action**
  1. REQUIREMENTS M2MASK-01..07 勾选 + Delivered 注记（KD-4 措辞预制）。
  2. `M2-7-3-ACCEPTANCE-INPUT.md` 落盘（AC 指针/熔断记录/挂账/Manual-Only）。
  3. `M2-7-3-SUMMARY.md`（phase 收口 SUMMARY：三 plan 战果汇总 + 熔断裁决 +
     观察项终值 + 键数终账）。
  4. GOAL-STATE 续接点翻账 + TODO 推进 + AGENTS.md M2-7 增量节（如有沉淀）。
  5. `git diff --stat` 边界核对（纪律 5：熔断行/zh 键/`.work` md 外零文件）。
- **验收标准**
  - [ ] 翻账四件 + ACCEPTANCE-INPUT 同批落盘；diff 边界核对过。
  - [ ] 全套 `--all` 终跑 0 fail（报备制已履行）——计数/秒数/峰值入 SUMMARY。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | Follow Edges 三景 × 两模式走查证据 + 熔断判据三项有数字 + 裁决结论明确 | evidence/m2-7-3/ + SUMMARY 裁决节 |
| 2 | perf.md 三表 + OQ-11 预算逐条对照结论；超标项有处置记录 | perf.md + SUMMARY 对照 |
| 3 | zh-audit `--check` 复跑 exit 0；M2-7 键族 zh 全覆盖；旧键零触碰 | 命令输出 + diff 抽查 |
| 4 | REQUIREMENTS M2MASK-01..07 勾选 + Delivered 注记（含锚 commit）；措辞与实态一致 | 文件核对 |
| 5 | ACCEPTANCE-INPUT 移交清单在册（AC 指针/熔断/挂账/Manual-Only 四节齐） | 文件核对 |
| 6 | GOAL-STATE 续接点终态 + TODO 推进 + 三件收口 md 同批 | 文件核对 |
| 7 | 源码 diff = 熔断一行（如触发）+ zh 键，零第三类文件 | `git diff --stat` 逐文件核对 |
| 8 | 全套回归 0 fail（基线 = P2 终数） | test-direct.sh --all BUNDLE 行双读 |

## 风险与边界

- **熔断判据主观性残余**：三项判据已量化（200ms/断链 2/帧预算），但「可感」
  仍有走查者间方差——双模式证据成对落盘使裁决可复核；验收 subagent 有权以
  证据推翻（裁决记录 = 输入非结论）。
- **观察项超标连锁**：缩略 pass/手柄拖动若超标，fallback 均为挂账级（预览
  降档/串行队列）非本 phase 实现——防收口范围膨胀（本 plan 红线：功能零新增）。
- **zh 键膨胀**：40-70 预估上限失守（>70）= P2 键清单漏账信号——照补不砍
  （zh-audit 是硬门），差额归因入 SUMMARY（P2 键清单纪律回注）。
- **perf 数字环境敏感**：Debug 构建手测口径与既有 bench（06/07 perf.md）一致，
  跨 phase 纵比禁用（只横比 OQ-11 预算项）——口径行在 perf.md 头部钉死。
- **REQUIREMENTS 措辞与验收冲突**：验收 subagent 推翻熔断裁决或降级交付态时，
  措辞以验收批为准回改（翻账 = 跟随实态，单一批次内同步，防双状态源）。

## 提交约定

- T1 `chore(m2-7): follow edges quality walkthrough and fuse verdict`（触发时
  另有 `chore(m2-7): follow edges default to snap mode` 一行提交）
- T2 `docs(m2-7): phase performance ledger`
- T3 `chore(i18n): zh strings for mask system phase`
- T4 `docs(m2-7): close out mask system phase with acceptance handoff`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。

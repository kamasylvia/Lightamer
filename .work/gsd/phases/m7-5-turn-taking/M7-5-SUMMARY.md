# M7-5 SUMMARY — 块二 GUI agent turn-taking 相位收口摘要（2026-10-17）

> phase = `m7-5-turn-taking`（TURN-01..04）；唯一 plan M7-5-01，前置批 =
> plan 修订 + CHECKER 放行（`552f1a02`）。执行链 = `599601d7..7f6fa522`
> （7 commits，T1..T7，未 push）。执行正本 = `M7-5-01-{SUMMARY,DECISIONS}.md`；
> 裁决正本 = `M7-5-CONTEXT.md`（D-M7-5-1..10 零重开）；双路验收正本 =
> `M7-5-01-ACCEPTANCE.md`（第一路）+ `M7-5-01-ACCEPTANCE-2ND.md`（第二路）。
> 本文件 = 相位级收口摘要（dual-acceptance 闭合 + 遗留路由 + M7-6 scope 定案）。

## Phase Goal

Alcedo AU14 turn-taking 四条 TURN 原生落地（REQUIREMENTS TURN-01..04）：
**TURN-01** 人机共驾控制权 = ControlToolset 第五域三工具（control_acquire /
control_release / control_get，控制命令自身免 admit）+ registry 第三道门
`requiresControl`（13 工具 state-changing 准入候选集）+ 错误码 16→19
（controlNotHeld / controlRevokedByUser / controlBusy ≙ Alcedo
-32003/-32004/-32005 同构，文案全自写禁抄 GPL）+ GUI 禁编辑全表
（disable-not-unmount，11 实落点）+ get_state `control.agent` 子对象。
**TURN-02** agent 活动卡 = BackgroundTaskBar 行「Agent · holder · 命令」
（registry 演进 isPinned/dismiss/activity additive）。**TURN-03** Stop 与
恢复 = 卡 cancel = Stop → 用户立得控制 → 同 holder re-acquire = ResumeTask
活动连续。**TURN-04** 无头恒持有 = makeHeadlessControlContext 恒真面 +
admit nil 恒放行 + read-only 宿主照常注册。附：scopes 保活三纪律
（Alcedo `c7ba784` 对表防病根移植）+ union 29→32 显式改（本波持快照改动权）
+ M7-4 顺路件 S-1..S-5。对表锚 = Alcedo Studio AU14（GPL-3.0 只读对表，
代码与文案零复制零翻译）。

## Execution Batch Results

| 任务 | commit | 面（细节正本 = `M7-5-01-SUMMARY.md` 逐任务表） |
|---|---|---|
| T1 | `599601d7` | ControlToolset 第五域 + registry 第三道门（Entry.requiresControl + setControlAdmit + dispatch 序 writer→control→handler）+ 错误码 16→19 + McpTimeouts.controlAcquire 10s 新档（三波零 diff 红线首开）+ 9 处 requiresControl 字面量（13 工具覆盖）+ 五签名六缝 |
| T2 | `89d8bbff` | AgentControlCoordinator（@MainActor @Observable 单写点 + admit 三拒 + acquire 等待/恢复路由 + Stop 单入口）+ PipeCoordinator.liveEditActive 三窗 OR + get_state control.agent 键 + GUI 禁编辑 11 实落点 + GUI 装配 |
| T3 | `4755941d` | registry 演进（isPinned / dismiss 薄封装）+ AgentTaskHandle + bar/dialog agent 行（Stop 单入口 handle.cancel 直呼，F8 Stop 留 registry）+ 活动列表 + AX 族 |
| T4 | `dea46168` | makeHeadlessControlContext 恒真面（恰 1 定义恰 3 调用点）+ 七点接线 + makeHeadlessSearchState additive agentControl 参（**仅 arbitrated 臂接线 = minor-1**）+ read-only 宿主照常注册 |
| T5 | `47737c1d` | S-1 四处过时注释清零 + S-3 预热实测（8.4ms vs 冷窗 50.2s，evidence 分仓 `9b36b42` 政策 B）+ S-2/S-4/S-5 申报起草 |
| T6 | `f91d9aee` | union 29→32 全点位显式改 + 穷举 16→19 + 两新测试文件（McpControlToolsetTests 15 法 + AgentControlCoordinatorTests 10 法）+ Project.swift/BUNDLE-MAP 恰两行登记 + tuist generate 恒末位 + xcstrings 三错误键补齐（T1 漏插当轮抓获，恰 10 新键） |
| T7 | `7f6fa522` | 定向轮 + 全套 `--all` 对账 + 红线族 11 项机检 + zh-audit 双 PASS + 走查 MANIFEST + 台账翻账 |

**全套终值 `TOTAL|3950/35/0|` exit 0**（零 MEMFAIL，七 bundle 全 8G 门内）；
ΔN = **+25**，3925 + 25 = **3950 对账精确**（预期带 3943..3950 落顶格）；
skip 35 构成零漂移。红线族 11 项全 PASS；zh-audit `--check` PASS
（source keys 1698→1708 恰 +10 / 1956 catalog keys）+ `--self-test` PASS。
**M7-4 挂账单一清单五项全处置**：S-1 全收口（四处 T5 + union 两处 T6）/
S-3 完成（预热后首调 8.4ms，三数量级改善；第二路独立复测 10.4ms 复现）/
S-2 让渡下一 Export 波 / S-4 FIX2③ 第四波维持（controller 零 diff 亲证）/
S-5 无动作。走查配方 = `.work/gui-acceptance/m7-5/MANIFEST.md`
（分仓 `0bf32ac` 政策 B）。

## Dual-Lane Acceptance Verdict

**双路 PASS、零推翻性分歧；三路全套同值 `TOTAL|3950/35/0|`**（执行批 T7 +
第一路独立复跑 2080s + 第二路独立复跑 2090s，均 exit 0 零 MEMFAIL，
3925+25=3950 对账精确、skip 35 零漂移、RSS 差在 SPIKE ±3% 方差带内）。

- **第一路**（`M7-5-01-ACCEPTANCE.md`）：**PASS / 0 blocking + 1 minor +
  4 observations**。全套独立复跑 + T1 三道门/T2 协调器/T3 Stop-resume/
  T4 无头面/T5 顺路件五面深审（产物逐 diff hunk 亲读）+ e2e stdio 真二进制
  抽测 + S-3 预热独立对照轮（10.4ms）+ 偏差①-⑦逐条裁决 + 红线族亲跑。
  minor-1 = 裸无头臂（`--mcp-stdio`/`--mcp-http`）get_state 的
  control.agent = .null（T4 intent 在 2/3 个 searchState 生产调用点未接线，
  e2e 实证三面并存：tools/list=32 + control_get 恒真 + agent=null 镜像
  谎报「face 未装配」）；修复 = 两调用点各 +1 行。
- **第二路**（`M7-5-01-ACCEPTANCE-2ND.md`，零共享上下文、五面错位切入）：
  **PASS（保留）/ 0 blocking + 1 major（open，新发现）+ 1 minor（复核
  成立）+ 5 observations**。全套独立复跑 + 真机 GUI 臂 e2e（HTTP 61330，
  control_get/acquire/get_state.agent 镜像全链工作 = coordinator 活面亲证）
  + osascript AX 实机断言（held 态 New/Open 菜单项行为门生效）+ 裸臂
  stdio e2e + admit 生产接线全仓扫 + 偏差①-⑦与 obs-1..4 逐条独立复核 +
  zh-audit 独立复跑。**本路新发现 major-1**（见下节）——第一路与 CHECKER
  沿 plan 判据走双双漏检，第二路错位切入（全仓 seam 调用点扫描）方暴露。
- 双路一致面：机械面（三道门 dispatch 序 / 9 字面量×13 工具 / 错误码 19 /
  状态机全序 / F8 Stop 留 registry / 无头恒持有 e2e）、回归面（3950/35/0
  三路同值）、红线族 11 项、偏差①-⑦全认。分歧面仅一处且为增量非推翻：
  obs-3 实害评估第二路上调（第一路判「单 agent 现实面不可达 + admit 门
  兜底」，第二路论证 admit 兜底因 major-1 失效 + 双 agent 并发生产可达）。

## Deviations Register

执行批偏差①-⑦**双路逐条独立裁决全部成立**（正本 =
`M7-5-01-DECISIONS.md` §2/§3；第二路 §6 交叉复核表）：①acquire 超时单一
执法点（tool 面不叠 10s 包装——typed controlBusy 优先）②registry 注入缝
（configureLiveEditProbe 可换缝 + attachTaskRegistry weak 附着）③xcstrings
三错误键随 T6 补齐（T1 漏插当轮抓获自我修正）④Stop 闭形终态化（interrupted
不被后续边界改写）⑤S-1 union 注释 token 措辞改写清零⑥evidence 政策 B
分仓（`9b36b42` + MANIFEST `0bf32ac`）⑦两 GUI fixture +1
`.environment(AgentControlCoordinator())`。无结构性偏差。收口批流程偏差
一件：**M7-5 不设独立 VALIDATION.md**（M7-2..M7-4 先例为每 phase 一份）——
双 ACCEPTANCE + 本 SUMMARY 即收口载体；站级 VALIDATION 收口归 M7-6 末
（major-1 修复在先，执法语义完整后一并签核），晨审可翻。

## Leftovers Routed to M7-6

第二路建议「热修批或 M7-6 首项二选一，裁决归用户（VALIDATION 签核前）」
——**orchestrator 裁定：三件全体路由 M7-6**，与既有 M7-6 附带批合并为
一个 scope（GOAL-STATE 续接点同批落账）：

1. **major-1：setControlAdmit 生产接线零调用**。App/Sources 恰 1 定义
   （McpToolRegistry :367）+ **0 生产调用**；全仓 3 处调用全在测试 fixture
   （McpControlToolsetTests :194/:253/:473）；四宿主函数体
   （startReadOnlyHTTPHost / startHeadlessStdioHost / startHTTPHost /
   startEmbeddedServer 段）均只 setWriterCheck 不 setControlAdmit；admit
   闭包从 LightamerApp 到 registry 无任何通道（McpControlContext 按 plan
   有意不含 admit，而 seam 无人安装）。**后果**：13 个 requiresControl
   工具的 typed 拒面（controlNotHeld/controlRevokedByUser）在所有真实宿主
   恒放行；e2e 实锤 = GUI 臂 held=false 直调 set_rating 落 handler
   internalError 而非 controlNotHeld。**根因 = plan 级缺口非 executor
   偏差**（PLAN 只要求 seam 在位 + fixture 接线，无 GUI 臂生产接线
   action）；无头臂 admit nil = 恒放行是 D-M7-5 正确语义，GUI 臂不接线
   无语义依据。**修法两案量级均小**：(a) 四宿主透传参 +1 缺省 nil（无头臂
   字节零 diff），GUI 装配点喂 coordinator.admit；(b) box 暴露 registry
   补接线。伴 1 测试腿（真宿主未 acquire 调 apply_params → controlNotHeld）。
2. **minor-1（两路一致）：裸 stdio（McpServerController :482）/裸 http
   （:497）臂** makeHeadlessSearchState 的 agentControl provider 未传参
   （缺省 nil → get_state.control.agent = .null 镜像谎报）。**两行修**，
   零回归风险（无测试钉裸臂 null 腿）。
3. **obs-3（第二路上调）：acquire 等待循环退出后无复检**。双 agent 并发
   acquire 生产可达（registry actor await 挂起点放行 + alreadyHeldBySelf
   入口预计算）+ **Stop-in-final-window 变体**（resume 型 acquire 等待中
   probe 封合同 poll 轮用户 Stop → 循环退出不查 stoppedByUser → success
   路径静默吞 Stop，窗口 = 一个 250ms poll 间隔）。**硬化 = 等待循环退出
   后复检两行**（stoppedByUser → throw revoked + held 异 holder → throw
   busy）。
4. **obs-A（第二路新，真机）：C12 禁编辑面 AX 旗标不忠实**——commands
   内 `Menu { … }.disabled(gate)` 行为门生效（held 态 AXPress 实点项目
   未切换）但菜单项 AXEnabled 恒读 true。走查批以**行为**判不以 AXEnabled
   判；零代码动作或 M7-6 SwiftUI 注记。
5. **union 快照改动权移交 M7-6**（DECISIONS §6，串行禁并行注记延续；
   M7-6 若并行派发 = 停手上报）；FIX2③ controller 零 diff 第四波维持。
6. **M7 站 VALIDATION 收口**（含 M7-5 签核——major-1/minor-1/obs-3 修复
   在先，执法语义完整后一并过目）。

### M7-6 Scope（收口批定案，六项）

① SKILLS-01 skills 文档仓（我们自家 CLI/MCP 的 agent 使用文档，Alcedo
parity Block 3）；② UQ-A1（预览层 ICC 双曲线失配）/ UQ-L1（滑杆双击重置 +
横扫 scrub）分插；③ M7-5 major-1 setControlAdmit 生产接线（含 1 测试腿）；
④ minor-1 裸 stdio/http 臂两行；⑤ obs-3 acquire 复检硬化两行；⑥ M7 站
VALIDATION 收口。

## Artifacts（留痕）

- 执行链 = `599601d7..7f6fa522`（7 commits，未 push）；前置批 =
  `552f1a02`（CHECKER pass on revised plan）。
- 收口正本 = 本文件；验收正本 = `M7-5-01-ACCEPTANCE.md` +
  `M7-5-01-ACCEPTANCE-2ND.md`（两份随收口批入库——第一路文件在收口批前
  untracked，任务假设「应已入库」不成立，已随本批补录）；执行正本 =
  `M7-5-01-{SUMMARY,DECISIONS}.md` + `M7-5-CONTEXT.md` +
  `M7-5-01-{PLAN,PLAN-REVIEW}.md` + `M7-5-CHECKER.md` + `M7-5-RESEARCH.md`。
- evidence 分仓（政策 B）= lightamer-evidence `9b36b42`（S-3 实测）+
  `0bf32ac`（走查 MANIFEST）；主仓 `.work/gui-acceptance/m7-5/` 工作树
  untracked 副本供走查批直接读。
- 本批 = doc-only：零源码、零测试运行、不 push。

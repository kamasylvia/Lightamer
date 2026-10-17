# M7-5-01 ACCEPTANCE — 第二路独立验收（zcode subagent，零共享上下文，2026-10-17）

```
phase:      m7-5-turn-taking
object:     M7-5-01 执行链 599601d7..7f6fa522（7 commits，T1-T7）
method:     不轻信执行方与第一路——全套独立复跑 + 五面错位切入（admit 生产接线
            全仓扫 / 协调器并发走查 / 真机 GUI 臂 e2e（HTTP 61330）+ AX 实机断言 /
            裸臂 stdio e2e / 偏差①-⑦+obs-1..4 逐条复核）+ 红线族亲跑 + zh-audit
            独立复核；产物新鲜度符号检验独立执行
verdict:    **PASS（保留）/ 0 blocking + 1 major（open，新发现）+ 1 minor（复核成立）
            + 5 observations（含 2 新）**
dual_acc:   本文件 = 第二路；major-1 裁决归用户（VALIDATION 签核前）：热修批或
            M7-6 首项二选一
```

## 结论头

**PASS（保留）/ 0 blocking + 1 major（open）+ 1 minor + 5 observations。**
执行链机械面全数成立：全套独立复跑 `TOTAL|3950/35/0|` exit 0 逐位精确对账
（ΔN=+25 顶格、skip 35 零漂移、七 bundle 全 8G 门内零 MEMFAIL）；T1 三道门
dispatch 序/9 处字面量×13 工具覆盖/错误码 19/控制三命令自免 admit/T2 状态机
全序/T3 Stop-Resume 活动连续/T4 无头恒持有/T5-T7 顺路件与台账——独立复核全绿。
真机 GUI 臂 e2e 证明 coordinator 活面（control_get/acquire/get_state.agent
镜像）全链工作。**但本路新发现 major-1：registry 第三道门（setControlAdmit）
生产接线零调用**——四宿主函数体均未安装 admit 缝，13 个 requiresControl 工具
的 typed 拒面（controlNotHeld/controlRevokedByUser）在**所有真实宿主恒放行**
（e2e 实锤：真机 GUI 臂上未 acquire 直调 set_rating 落 handler
internalError 而非 controlNotHeld）。根因 = plan 级缺口（PLAN 只要求 seam
在位 + fixture 接线，从未规定 GUI 臂生产接线动作），executor 忠实照办，
CHECKER 与第一路双双漏检。TURN-01 的执法语义在成形面上不完整，建议
VALIDATION 签核前用户裁决处置。

## §1 亲跑数字（独立复跑，非转抄）

- **全套 `caffeinate -dis Scripts/test-direct.sh --all`**（工作树 clean @
  HEAD `7f6fa522`）：**`TOTAL|3950/35/0|` exit 0，2090s，零 MEMFAIL，
  七 bundle 全 8G 门内**：
  - IOP 687/5/0（peakRSS 7664MB）/ IOPParity 460/3/0（6582MB）/ Layers
    494/5/0（810MB）/ Library 736/4/0（624MB）/ Sessions 284/9/0（1603MB）/
    Export 385/5/0（4971MB）/ App 904/4/0（2832MB）。
  - **对账**：基线 3925 + ΔN 25（McpControlToolsetTests 15 法 +
    AgentControlCoordinatorTests 10 法；union 显式改/穷举 16→19/get_state
    断言新法 = 零新法口径）= **3950 精确**；skip 5+3+5+4+9+5+4 = **35 零漂移**。
    逐 bundle 与执行方申报逐值一致；RSS 差（IOP 7664 vs 7813 vs 第一路
    7607；Parity 6582 vs 7626 vs 6976）在 SPIKE ±3% 方差带内，门内达标。
- **产物新鲜度独立符号检验**：宿主/xctest 二进制 mtime 13:25（晚于 T1-T5
  全部 commit、早于 T6 commit 13:32 七分钟 = 「先测试绿后 commit」纪律形，
  与第一路判读一致但本次独立重跑）；App xctest 终态符号三连在
  （`testFinalSnapshotUnion32Verbatim` / `NineteenValuesExhaustive` /
  `FullSequenceAcquireAdmitStopResume`），过时符号零命中
  （`Union29Verbatim` / `SixteenValuesExhaustive`）。
- **九个关键新测试法在本路 App bundle 轮亲跑全绿**
  （全序/等待/超时/Stop 中断/admit 三拒/13 候选集/禁编辑 manifest/条件卸载
  负测/scopes 零引用——grep `' passed` 各 1 命中）。
- **e2e stdio 裸臂**（本路自有 spawn，`LIGHTAMER_SKIP_LUT_PREHEAT=1`）：
  initialize 2025-11-25 ✓ → **tools/list = 32**（控制域三工具在册）✓ →
  control_get = `{held:true, holder:"", revokedByUser:false}`（无头恒持有）✓
  → **get_state.control.agent = null**（→ minor-1 独立复现，§5）。
  get_state.control 既有键形零漂移亲证（`holder` 键条件发射 = 前行为，
  cbad16eb 原文对照）。
- **e2e HTTP 真机 GUI 臂**（本路自有 spawn：`mcp_server_enabled=true` +
  Debug 产物直启，端口 61330，probe 全程后杀净 + defaults 还原）：
  initialize ✓ → tools/list = 32 ✓ → **control_get(pre) = `{held:false,…}`**
  （**live coordinator 活面**——非无头常量，GUI 臂 provider 装配真达）✓ →
  control_acquire = `{held:true, holder:"axprobe"}` ✓ → get_state.control.agent
  = `{held:true, holder:"axprobe", revokedByUser:false}`（D-M7-5-8 镜像真达）✓
  → release 幂等 ✓ → **set_rating 未 acquire 直落 handler 面
  `[internalError] metadata service unavailable`（非 controlNotHeld）**——
  major-1 实锤（§4）。
- **真机 AX 断言**（osascript System Events，accessibility 可达）：
  held 态（control_acquire 后）File 菜单「New Project…」= disabled、
  「Open Project…」= disabled、**「Open Recent Project」= enabled**；release
  态三项全 enabled；**行为级判别**：held 态 AXPress 实点最近项 → **项目未
  切换**（窗口标题不变）——`.disabled` 在 commands Menu 上行为门生效但
  AXEnabled 旗标不灰（→ obs-A，§6）。New/Open 两钮 AX 行为双忠实。
- **zh-audit 独立复核**：`--check` PASS（**1708 source keys** = 1698+10 对账
  精确 / 1956 catalog keys / 38 interp keys variant-PRESENT）+ `--self-test`
  PASS（V17 八例）。三错误键 zh 值在册亲验（`mcp_error_control_busy` =
  「另一持有者已持有控制权：%1$@。」等）。
- 运行监视：全套期间无 GUI 实例混杂（探针 app 在套件结束后启动）、零
  MEMFAIL、资源线无触发；探针残留已清（进程 0 / defaults 键删除 / discovery
  json 残留删除——kill 后残 json 为文档在案的自愈面，本路顺手清）。

## §2 五面审计之一：T1/T2 门与协调器（源码级，全部成立）

- **dispatch 序亲读**：`call()` = 未知名 internalError → writer 门
  （writeCallCount 只在门内，计数行零触亲证）→ control 门
  （`if entry.requiresControl, let controlAdmit`）→ handler。**但 controlAdmit
  生产恒 nil（§4 major-1）**——门机械在位、执法缺位，本节其余成立。
- **9 处字面量 × 13 工具覆盖独立点数**：EditingToolset 4（:147/:153/:168/:229）
  + CullingToolset 2（registerOne helper :343 单点覆盖 metadata 五件
  〔helper 5 调用点 :374/:392/:410/:428/:441 亲数〕+ apply_preset :535）+
  MatchColorToolset 1（:166）+ ProjectToolset 2（:164/:226）= **恰 9**；
  ControlToolset 零显式（自免 admit）亲证。
- **协调器单写点/@MainActor 边界**：状态字段全 `private(set)` 编译封闭；
  GUI provider 链 = acquire 闭包 plain-await hop（@MainActor 函数直 await）/
  release/state `MainActor.run` 同步体——双形态均在 LightamerApp :1633-1645
  亲读；admit 闭包无生产消费点（§4）。liveEditActive probe 走
  configureLiveEditProbe 可换缝（:581-583 装配闭包喂
  `pipeCoordinator.liveEditActive`，属性非调用——CHECKER 注意点③兑现）。
- **acquire 三态**（源码 + 测试双读）：异 holder 即拒携 holder；未封合挂起
  轮询至封合/注入超时/Stop 中断——三腿测试亲读本路套件轮全绿（禁真等 10s
  口径维持，注入 200ms 窗 <2s 判定）。
- **禁编辑 11 实落点源码抽验 ≥8 面**（每点上下文亲读）：WorkspaceHostView
  :638-639/:653-654（export/yiyin 合并形 + AX 标识在位）/
  EditorWorkspaceShellView :178 / EditorAdjustmentStackView :85（容器级）/
  EditorToolRailView :161（rail 容器 + :148-152 对 EditorNodesPanelView
  **真传 agentControl**——optional 注入非静默失效）/ EditorNodesPanelView :92
  / VersionsPanelView :92 / FilmstripView :169 / ImportModeDialog :149（合并
  形）/ LibraryInspectorView :381（aiSection 容器）/ LightamerApp undo/redo
  + project 三项 + welcome 三闭包 guard 形。环境注入链亲证（App :537
  `.environment(agentControl)` → 各视图 `@Environment`）；条件卸载负测
  （全仓 >50 文件扫描）本路套件轮绿。
- **scopes 三纪律**：coordinator 源码零 scope 词（setScopeTapEnabled /
  scopesVisible / ScopeThrottle / PipeCoordinator 硬引——亲读 +
  testCoordinatorCarriesZeroScopeReferences 本路轮绿）；ScopePanelView /
  ScopeThrottle / SettingsView 不在 42 文件 diff 清单（亲跑）。

## §3 五面审计之二：T3 Stop/Resume（成立）

- **全序 fixture 亲读本路轮绿**：acquire→admit pending→Stop interrupted 闭形
  →拒→同 holder resume **同 id**（`coordinator.taskId == handle.id` 断言）
  活动列表延续→release 终态→dismiss 刻意断连续→fresh 新 id——
  `testFullSequenceAcquireAdmitStopResumeReleaseDismiss` 亲跑绿。
- **Stop 留 registry（F8）双钉**亲读：全序测试 :72 + legacy 腿测试 :201
  （"Stop keeps the pinned row"）；bar/dialog agent 行路由 = `handle.cancel()`
  直呼 → coordinator.stop()（BackgroundTaskBarView :145/:232）；**agent 行
  registry.cancel 零命中**（:110/:249 两处均在 `as? AgentTaskHandle` 转型
  失败的 legacy else 臂内——具型隔离亲读）。
- **pinned dismiss 语义**：终态行 dismiss = registry.dismiss(id:)（finish 薄
  封装）+ coordinator.dismissCard()（清 handle/taskId/activity = 用户手动破
  连续）——bar :156-157 / dialog :240-241 双面同源亲读。
- **registry 演进零漂移**：diff 亲读 = +10 行 extension（isPinned 默认 false）
  + +8 行 dismiss 薄封装；finish/cancel/cancelAll 体零触；三腿负测本路轮绿。

## §4 独立发现（本路新报，第一路与 CHECKER 均未覆盖）

- **major-1（open，非 blocking 收口但阻断 TURN-01 语义完整申报）：
  registry 第三道门生产接线零调用。**
  - **事实**：`setControlAdmit` 在 App/Sources 仅 1 处定义
    （McpToolRegistry :367）+ **0 生产调用**；全仓 3 处调用全在测试 fixture
    （McpControlToolsetTests :194/:253/:473——其中 :253 的注释自称
    "the production shape in-process"，fixture 手动接线正是生产形的 in-process
    等价，反证作者认知里生产形应含接线）。四宿主函数体
    （startReadOnlyHTTPHost :727 / startHeadlessStdioHost :791 /
    startHTTPHost :1043 / startEmbeddedServer :1120 段）均只 setWriterCheck、
    不 setControlAdmit；GUI 臂 control context 三 provider（acquire/release/
    state）coordinator-backed 接线真达（e2e 亲证），但 **admit 闭包从
    LightamerApp 到 registry 无任何通道**（McpControlContext 按 plan 有意
    不含 admit——"admit 走 registry seam"——而 seam 无人安装；HttpHostHandle
    携 registry 但 box 不外露）。
  - **e2e 实锤**（§1 HTTP GUI 臂）：held=false 态 `set_rating` →
    `[internalError] metadata service unavailable in this host`
    （handler 面）**而非 controlNotHeld**；release 后再调同形。若门接线，
    两答应为 typed controlNotHeld。
  - **语义后果**：13 个 state-changing 工具在所有真实宿主（含 GUI 内嵌宿主）
    未持权直入 handler——TURN-01 的准入执法面（RESEARCH §1.2「每条
    state-changing 命令进 handler 前过 admit 闸」、验收形态①「agent 持锁
    GUI typed 拒」）生产不可达；turn-taking 仅剩「工具 description 自觉 +
    acquire 后 GUI 禁面」两道软门，不合作/有缺陷 agent 可静默绕过。工具
    description 明文承诺 "state-changing tools answer controlNotHeld unless
    it is held"——承诺面与现实不符。
  - **根因 = plan 级缺口，非 executor 偏差**：PLAN SC-T1 只要求 "setControlAdmit
    seam 在位（grep）"，T2 action 5 装配清单只含 acquire/release/state 三
    provider，T4 七点清单只接 `control:` 参；全 PLAN 无 GUI 臂 admit 生产
    接线 action。无头臂 admit nil = 恒放行是 D-M7-5 正确语义（headless 恒
    持有）；**GUI 臂不接线无语义依据**。CHECKER 反向核与第一路验收均沿
    plan 判据走，双双漏检——第二路错位切入（全仓 seam 调用点扫描）方暴露。
  - **修法建议**（两案，量级均小）：(a) 四宿主 +startEmbeddedServer 透传参
    +1 `controlAdmit: (@Sendable (_: String) async throws -> Void)? = nil`
    （缺省 nil = 无头臂字节零 diff），GUI 装配点喂 coordinator.admit；
    (b) startEmbeddedIfPreferenceEnabled 返回 handle 或 box 暴露 registry，
    装配点补 `setControlAdmit { [agentControl] in try await
    agentControl.admit(toolName: $0) }`。伴测 1 腿：真宿主（或
    startHTTPHost + admit 闭包）未 acquire 调 apply_params → controlNotHeld。
    与 minor-1 两行同批热修顺路。裁决归用户（VALIDATION 前）。

## §5 minor-1 交叉验证（第一路结论成立）

- **源码级**：makeHeadlessSearchState `agentControl` 参缺省 nil；三生产调用
  点中裸 stdio 臂（McpServerController :482）与裸 http 臂（:497）未传参，
  arbitrated 共享点（:603）已传常量——第一路 "2/3 未接线" 精确。
- **e2e 级**：裸臂三面并存亲证（tools/list=32 + control_get 恒真 +
  get_state.agent=null）——控制工具在册（union/H3 无违）而镜像谎报
  「face 未装配」。
- **修法影响面**：两调用点各 +1 行 `agentControl: { McpControlState
  .headlessConstant }`；无测试钉裸臂 null 腿（McpSearchStateToolsetTests :920
  钉的是 provider 合同 nil 腿，非宿主接线）→ 两行零回归风险。建议与
  major-1 同批。

## §6 偏差①-⑦ + 第一路 observations 独立复核

| # | 申报/observation | 本路裁决 |
|---|---|---|
| ① | acquire 超时单一执法点（tool 面零第二层 withTimeout） | **成立**——ControlToolset 注释 + coordinator 注入缺省亲读；typed busy 优先与 OQ-7 一致 |
| ② | registry 注入缝（configureLiveEditProbe + attachTaskRegistry weak） | **成立**——两缝源码 + LightamerApp 装配亲读；acquire register 幂等保语义 |
| ③ | xcstrings 三错误键 T6 补齐 | **成立**——1956 keys 亲验 + zh 值在册 + zh-audit 双 PASS 独立复跑；T1 漏插当轮自我修正可接受 |
| ④ | Stop 闭形终态化 | **成立**——closeInFlight 只寻 pending + 全序测试 resume 不复活 entry[0] 亲跑绿 |
| ⑤ | S-1 union 注释 token 措辞清零 | **成立**——`count, 29`/`count == 29`/`all29`/`Union29`/`21-tool face`/`count rides 21`/`exactly these 27` 全域 grep 零命中（本路亲跑） |
| ⑥ | evidence 政策 B 分仓 | **成立**——lightamer-evidence `9b36b42`（S-3）+ `0bf32ac`（MANIFEST）两 commit 亲验 + 主仓 worktree 副本在位 |
| ⑦ | 两 GUI fixture +1 `.environment(AgentControlCoordinator())` | **成立**——ToastFaceTests/ProjectReadOnlyFaceTests 各 +4 行 diff 亲读（never-held 注释在位） |
| obs-1 | isPinned = 协议 extension 属性非协议要求 | **成立**——BackgroundTaskHosting diff 亲读；生产路由 `as? AgentTaskHandle` 具型转型结构性规避 existential 静态派发坑；隐患注记：未来 existential 读恒 false |
| obs-2 | acquire 超时臂 busy 文案硬编码英文 | **成立**——coordinator :234-237 亲读；busy 键由异 holder 臂消费、zh 在册；一致性注记级 |
| obs-3 | 并发 acquire 等待窗无 post-wait held 复检 | **成立但实害评估上调**——见下 |
| obs-4 | window-teardown survivor 未在 DECISIONS 显式申报 | **成立**——DECISIONS §2.4 有 weak 附着申报、无 survivor 裁量句；措辞级 |

- **obs-3 竞态实害重评（与第一路分歧）**：第一路判「单 agent 现实面不可达
  + admit 门兜底」。本路分析：(a) **双 agent 并发 acquire 生产可达**——HTTP
  每 session 一 Server actor，registry.call 在 admit/handler await 挂起点
  放行并发；acquire 的 `alreadyHeldBySelf` 在入口预计算、等待循环退出后无
  复检，两 agent 在窗内先后 resume = 双 held 应答 + 后者覆写 holder
  （`held` 置真前仅有一个 await hop，默认 probe `{false}` 亦不可免）；
  (b) **Stop-in-final-window 变体（本路新面，单 agent 即可达）**：resume 型
  acquire 等待中（卡行在册、Stop 钮可达）probe 封合同 poll 轮用户 Stop →
  循环退出不查 stoppedByUser → success 路径清 stoppedByUser/stoppedHolderName
  ——用户 Stop 被静默吞（fresh-acquire 场景因无卡不可达，resume 场景可达；
  窗口 = 一个 250ms poll 间隔）；后果可恢复（卡复燃后再按 Stop 即可）但
  违反「用户随时 Stop 立即生效」语义；(c) 第一路的「admit 门兜底」论据
  因 major-1 失效（生产无 admit）。**硬化 = 等待循环退出后 +1 复检两行**
  （`if stoppedByUser throw revoked` + `if held, 异 holder throw busy`），
  归 M7-6 硬化候选，与本波交付不冲突。
- **obs-A（本路新，真机）：C12 面 AX 旗标不忠实**——commands 内
  `Menu { … }.disabled(gate)` 行为门生效（held 态 AXPress 实点最近项项目
  **未**切换）但菜单项 AXEnabled 恒读 true（held/release 两态对照亲测；
  同点位普通 Button `.disabled` 的 AX 旗标双忠实）。MANIFEST C12 行
  「New Project/Open Project/Open Recent 灰」若按 AX/目视判将假失败一档。
  走查批注意：Menu 项以**行为**判不以 AXEnabled 判；零代码动作或 M7-6
  SwiftUI 注记。
- 另：第一路 §6 对执行方 SUMMARY「LocalizationValue 插值禁形唯一命中为注释」
  的勘误（ExportInspectorView :534）本路复核成立——该行为字符串拼接形
  （`"export_format_" + kind.rawValue`，L058 注释在位），链外既有零新命中；
  本路独立 grep 插值禁形唯一命中 = LightamerApp :2368 注释行。

## §7 红线族（11 项本路亲跑全 PASS）

①union 29→32 显式改（all32/Union32Verbatim/`control_acquire` 冻结表入口亲
grep；残漏 grep 零命中）②零新 SPM（Project.swift diff 恰两行测试登记亲读）
③既有 29 工具 descriptor/handler 零 diff（writeCallCount 计数行零触亲证 +
快照门本路轮绿）④错误码 19 additive（符号亲验）+ get_state 既有键形零漂移
（holder 条件发射 = cbad16eb 原行为，亲对照）⑤GUI 三腿零漂移（isPinned
extension 默认 + legacy finish 路由亲读）+ scopes 三纪律（§2）+
disable-not-unmount（条件卸载负测本路轮绿）⑥LibraryProjectController 零
diff（`git diff` 0 行亲跑）⑦封存面零触（`.metal` 0 文件 + 42 文件全清单
逐格过——无 DrtRecord/PixelPipe/Lut3dKernels 等命中）⑧Alcedo GPL 零复制
（coordinator/ControlToolset 文案亲读自写、中文错误文案自拟）⑨单写点
（private(set) 编译封闭亲读）⑩xcstrings 100/0 纯插入（numstat 亲跑）+
UserDefaults 零新键（探针后还原亲证键缺席 = 本波零新增）+ runModal 零命中
+ 插值禁形零新命中 ⑪Project.swift 恰两行 + BUNDLE-MAP 恰两行（APP 15+10
亲读）+ tuist generate 恒末位（T6 commit 时序核）。

## §8 commit 清单（599601d7..7f6fa522，7 commits）

| commit | 任务 | 本路核验面 |
|---|---|---|
| `599601d7` 12:39 | T1 | 三道门机械/9 字面量/错误码 19/controlAcquire 新档/五签名六缝——源码亲读 + 套件绿 |
| `89d8bbff` 12:53 | T2 | 协调器/禁编辑 11 实落点/liveEditActive/get_state agent 键——源码 + 真机 AX + e2e |
| `4755941d` 12:57 | T3 | isPinned/dismiss/agent 行 Stop 单入口——diff 亲读 + 测试绿 |
| `dea46168` 12:59 | T4 | 恒真面 + 七点接线（**searchState 裸臂 2/3 未接 = minor-1**；**admit 生产接线全缺 = major-1**） |
| `47737c1d` 13:03 | T5 | S-1 清零 + S-3 实测申报——grep 亲跑 |
| `f91d9aee` 13:32 | T6 | union 32 全点位 + 两新测试文件 + xcstrings 补齐——符号 + 套件绿 |
| `7f6fa522` 14:10 | T7 | 全套对账 + 台账——本路 `TOTAL|3950/35/0|` 独立闭合 |

## §9 判定

- ROADMAP §M7-5 四验收形态：①双端 fixture **PASS（fixture 级）**——但生产
  形 admit 缺位（major-1）使「agent 未持权 typed 拒」止步 fixture；
  ②GUI 活动卡走查 = 配方就绪 + 本路真机补验 C12（行为门 ✓ / AX 旗标
  observation）；③Stop→resume 活动连续 **PASS**；④无头恒持有 **PASS**
  （e2e 实证；裸臂 get_state 镜像缺口 = minor-1 不触形态本体）。
- **验收结论：PASS（保留）**——机械面/回归面/红线族/台账对账全数闭合，
  执行链可交付；**major-1（admit 生产接线）+ minor-1（裸臂 agent 镜像）+
  obs-3 硬化（post-wait 复检两行）打包为一个小热修批**（预估 <1h、零签名
  变化、伴 1-2 测试腿）建议 VALIDATION 签核前由用户裁决执行；或全体路由
  M7-6 首项。在裁决前，TURN-01 的交付申报应注明「准入执法面生产接线待补」。
- union 改动权按 DECISIONS §6 移交 M7-6（串行禁并行）维持；FIX2③ 第四波
  维持。
```
第二路签名：independent second-lane acceptance（零共享上下文；不 push——
本文件 untracked 留 phase 目录，随 orchestrator 收割）
```

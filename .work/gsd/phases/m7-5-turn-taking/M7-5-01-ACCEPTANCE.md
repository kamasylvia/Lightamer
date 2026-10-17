# M7-5-01 ACCEPTANCE — 第一路独立验收（zcode subagent，2026-10-17）

```
phase:      m7-5-turn-taking
object:     M7-5-01 执行链 599601d7..7f6fa522（7 commits，T1-T7）
method:     不轻信执行方报告——全套独立复跑 + T1 三道门/T2 协调器/T3 Stop-resume/
            T4 无头面/T5 顺路件五面深审（产物逐 diff hunk 亲读）+ e2e stdio 真二进制
            抽测 + S-3 预热独立对照轮 + 偏差①-⑦逐条裁决 + 红线族亲跑 + zh-audit 独立复核
verdict:    **PASS / 0 blocking + 1 minor（open，非阻断）+ 4 observations**
dual_acc:   本文件 = 第一路；omp 二次验收按 dual_acceptance 制度串行跟进
```

## 结论头

**PASS / 0 blocking + 1 minor + 4 observations。** 执行链与修订版 plan 逐面
吻合：全套独立复跑 `TOTAL|3950/35/0|` 逐位精确对账闭合（ΔN=+25 顶格）；
T1 三道门 dispatch 序/9 调用点×13 工具覆盖矩阵/错误码 19 值穷举/controlAcquire
新档勘误/控制三命令自免 admit 全部亲证成立；T2 单写点+禁编辑 11 实落点+
liveEditActive 三窗 OR+get_state agent 键全落位；T3 Stop 留 registry（F8）+
同 holder resume 同 id+registry.cancel 移除臂绕行亲证；T4 七点接线 grep 全过；
S-3 独立复测 10.4ms 复现三个数量级改善；偏差①-⑦全部裁定成立（申报在案）。
唯一 open minor = **裸无头臂（无 `--project`）get_state 的 control.agent 面
为 .null**（T4 action 4 意图在 2/3 个 searchState 生产调用点未接线）——e2e
实证在案，工具面 union 纪律无违（32 面完整），修复 = 两调用点各一行，建议
M7-6 顺路或热修。

## §1 亲跑数字（独立复跑，非转抄）

- **全套 `caffeinate -dis Scripts/test-direct.sh --all`**（工作树 clean @
  HEAD `7f6fa522`；`TOTAL|3950/35/0|` 2080s，exit 0，**零 MEMFAIL，七
  bundle 全 8G 门内**）：
  - IOP 687/5/0（peakRSS 7607MB）/ IOPParity 460/3/0（6976MB）/ Layers
    494/5/0（809MB）/ Library 736/4/0（623MB）/ Sessions 284/9/0（1633MB）/
    Export 385/5/0（6172MB）/ **App 904/4/0（2832MB）**。
  - **对账**：基线 3925 + ΔN 25（两新测试文件 15+10 法；union 显式改/穷举
    16→19/get_state 断言新法 = 零新法口径）= **3950 精确**——预期带
    3943..3950 落顶格；skip 5+3+5+4+9+5+4 = **35 构成零漂移**。
  - 逐 bundle 与执行方 T7 申报逐值一致；峰值 RSS 差（IOP 7607 vs 7813 /
    Parity 6976 vs 7626）在 SPIKE ±3% 运行方差带内，门内达标。
- **产物新鲜度字节级自证**：宿主二进制 mtime 13:25:56 / App 测试 bundle
  二进制 mtime 13:25:54——晚于 T1-T5 全部 commit（12:39..13:03）= 产线码
  终态；早于 T6 commit（13:32:49）7 分钟 = 「先测试绿后 commit」纪律形。
  App bundle 二进制 `strings` 符号检验：终态符号三连在（
  `NineteenValuesExhaustive` / `testFullSequenceAcquireAdmitStopResume
  ReleaseDismiss` / `testFinalSnapshotUnion32Verbatim`），过时符号零命中
  (`SixteenValuesExhaustive` / `Union29Verbatim`)——测试二进制含终码亲证。
- **e2e stdio 真二进制抽测**（裸 `--mcp-stdio` 臂，`LIGHTAMER_SKIP_LUT_
  PREHEAT=1` + 隔离 endpoint dir）：initialize 协商 2025-11-25 ✓ →
  **tools/list = 32**（union 面，控制域三工具在册——H3 无违）✓ →
  **control_get = `{held:true, holder:"", revokedByUser:false}`**（无头恒
  持有面）✓ → **get_state 的 control.agent = null**（→ minor-1，见 §6）。
- **S-3 预热独立对照轮**（本验收自有 spawn，preheat 生效 + 100s settle）：
  首调 `list_luts` = **10.4 ms**（luts≈40）vs 执行方 8.4 ms vs M7-3 冷窗
  正本 50.2s——三个数量级改善独立复现（二进制 md5 3e7c3b87… = 本验收轮
  HEAD 全链构建，与执行方 T4 时刻 d7208557… 不同属预期）。
- **zh-audit 独立复核**：`--check` PASS（**1708 source keys** = 1698+10
  对账精确 / 1956 catalog keys / 38 interp keys variant-PRESENT）+
  `--self-test` PASS。
- 运行监视：全套运行期间无 GUI 实例混杂；资源监控线无触发。

## §2 T1 三道门深审（最重项，全部亲证成立）

- **dispatch 序亲读**（`McpToolRegistry.swift` 全文）：`call()` = 未知名
  internalError(:389-391) → **writer 门**（:392-400，`writeCallCount += 1`
  只在门内）→ **control 门**（:405-407，`if entry.requiresControl, let
  controlAdmit { try await controlAdmit(name) }`）→ handler（:408）。
  writeCallCount 三处 diff 命中全为注释/上下文——**计数行零触亲证**。
- **9 调用点 × 13 工具覆盖矩阵亲核**：EditingToolset 4（load_image/
  apply_params/paste_adjustments/export_image——行号 :147/:153/:168/:229
  与 plan 有漂移，工具身份逐点经 handler 体核对）+ CullingToolset 2
  （registerOne helper 单点 :343 覆盖 write five〔helper 恰 5 调用点
  :374/:392/:410/:428/:441 亲数〕+ apply_preset :535）+ MatchColorToolset 1
  （:166）+ ProjectToolset 2（project_open :164 / project_create :226）。
  **恰 9 处字面量**（4+2+1+2）；T6 registry 层行为断言
  （testRequiresControlCandidateSetIsExactlyThirteen）13 名 admit 必死 +
  16 名面外免 admit + 控制三命令免 admit——双层闭合。
- **错误码 19 值穷举**：case 恰 +3（:89/:93/:98，零改零删）+ code switch
  恰 +3 臂（:119-121）+ message 逗号连绑列表恰 +3 名（:134——diff 的 2 行
  删除 = 末行重写的必然形 + Entry 构造接线，均 plan 规定形）；每错误名恰
  3 处 grep 亲证；穷举测试法名/数组/计数 16→19 同批显式改（:1031-1050）。
- **controlAcquire 新档勘误申报复核**：`McpTimeouts` diff 恰 +1 行
  （:248），既有八档（5/10/20/30/10/60/120/5）逐行零触亲证——DECISIONS
  §1.2 申报成立（M7-2/M7-3/M7-4 零 diff 红线历史后首档 additive）。
- **ControlToolset 三工具自免 admit 亲证**：`requiresControl` 在
  ControlToolset.swift **零命中**；行为断言（三工具 honest internalError
  非 controlNotHeld）+ `headlessConstant` 单源在位；超时单一执法点注释在位
  （tool 面零第二层 withTimeout——偏差① 落地亲证）。

## §3 T2 协调器深审（亲证成立）

- **单写点**：`held/stoppedByUser/holderName/stoppedHolderName/taskId/
  activity` 全 `private(set)`——写点编译级封闭于本类；`holdsControl` 派生
  只读；与 M6-1 锁面零耦合（SingleWriterLock/LibraryProjectController
  引用零命中）+ `PipeCoordinator` 硬引零命中（F-6 注入缝，测试
  testCoordinatorCarriesZeroScopeSources 断言源码 zero-hit）。
- **acquire 等待/超时/Stop 三态**（源码亲读 + 测试亲读）：异 holder 即拒
  controlBusy 携 holder；未封合输入挂起轮询（250ms）至封合/注入超时/
  Stop 中断——三腿测试（wait-for-seal / 200ms 注入窗超时 busy 携
  "not sealed" 且 <2s / Stop 中断 <1s revoked）全在案，**禁真等 10s**
  口径维持。
- **禁编辑 11 实落点逐面亲核**（grep 亲点 + 上下文亲读）：WorkspaceHostView
  :639/:654（export/yiyin 合并形）/ EditorWorkspaceShellView :178 /
  EditorAdjustmentStackView :85（容器级）/ EditorToolRailView :161 /
  EditorNodesPanelView :92（optional 注入式申报形）/ LightamerApp
  （undo/redo :1972-73/:1978-79 + project :1859/:1864/:1880-81 + welcome
  guard 等价闭包形 :1680/:1684/:1688）/ VersionsPanelView :92 /
  FilmstripView :169 / ImportModeDialog :149 / LibraryInspectorView :381。
  **条件卸载负测零命中**（`if !agentControl` / `if agentControl.holdsControl`
  全 UI 面 grep 零命中 + 测试内嵌全仓扫描 >50 文件亲跑）；
  `LibraryProjectController.swift` **diff 0 行**（FIX2③ 第四波）。
- **liveEditActive 三窗 OR**：PipeCoordinator diff 恰 +1 只读计算属性
  （`isEditingContinuous || isEditingDrt || isEditingFilm`），属性外函数体
  零触；装配点闭包喂 `pipeCoordinator.liveEditActive`（LightamerApp diff
  亲读）。
- **get_state control.agent 端到端**：SearchStateToolset diff 恰 +1
  optional provider（缺省 nil）+ 恰 +1 键（nil → .null；真值 → 三键子对象）
  ；既有三键（lock/holder/writeCallCount）值与形零漂移；nil 合同腿
  （:920 NSNull）+ 真值腿（McpControlToolsetTests :495-507）双在案。

## §4 T3 Stop/Resume 深审（亲证成立）

- **Stop 后 pinned 留 registry（F8）**：`testFullSequence…` :72（Stop 后
  registry.count==1）+ `testLegacyLegs…` :201（Stop keeps the pinned row）
  双钉；agent 行路由 = `handle.cancel()` 直呼 → `coordinator.stop()`（bar
  :145 / dialog :232）；**agent 行 registry.cancel 零命中**（:110/:249 两处
  = legacy 行路由，具类型转型 `as? AgentTaskHandle` 隔离亲读）。
- **同 holder resume 同 taskId**：`stoppedHolderName == holderName` 恢复
  判据 + 同 id re-register 幂等（:87-88 断言）；异 holder 新任务 mint 新 id
  （:138）；stoppedByUser 任一成功 acquire 清除（:92-93）；Stop 闭形终态
  （resume 后次条 admit 不复活 entry[0] 的 interrupted——:100-101，偏差④
  落地亲证）。
- **registry 演进零漂移**：`isPinned` = extension 默认 false + AgentTaskHandle
  override true；`finish/cancel/cancelAll` 函数体 diff 零触（背景 diff 亲读
  ——仅 +10 行 dismiss 薄封装与 +10 行 extension）；三腿负测
  （extension 默认 false + finish 即移除）亲跑绿。
- **dismiss 路由**：bar/dialog 终态行 dismiss = `registry.dismiss(id:)` +
  `coordinator.dismissCard()`（:156-157/:240-241）；coordinator 侧
  dismissCard 清 handle/taskId/activity——用户手动破连续性语义在案。

## §5 T4 无头面（七点接线 grep 全过 + e2e 抽测）

1. `makeHeadlessControlContext` 恰 1 定义（:216）+ 恰 3 调用点（:486 runHeadless
   stdio 臂 / :500 http 臂 / :612 arbitrated 共享 const）；GUI/Embedded 臂零命中。
2. 七点 `control:` 逐点亲核（行号漂移按 grep 亲点）：:486/:500/:617(stdio)/
   :633(http writer)/:655(read-only——OQ-10 注释在位)/:1168-1172(EmbeddedState
   box 读出)/LightamerApp :1651(GUI 臂 coordinator-backed context)。
3. 三宿主函数体 + startEmbeddedServer 体内 `makeHeadlessControlContext`
   零命中（体只转发 makeRegistry）。
4. McpHostTests fixture 零传 control（grep 零命中；五钉 23 断言 :243/:697
   保绿亲证）。
5. startEmbeddedIfPreferenceEnabled 签名 +1 缺省参（:1142）+ EmbeddedState
   box `control` 字段在位（:1244）。
6. `headlessConstant` 恰 1 定义 + 生产消费仅 McpServerController :218-220/
   :606；coordinator/GUI 零消费。
7. 五签名（makeRegistry :850 / startReadOnlyHTTPHost :727 /
   startHeadlessStdioHost :791 / startHTTPHost :1043 /
   startEmbeddedIfPreferenceEnabled :1142）各恰 +1 缺省 nil 参，既有参零触。
- **e2e 抽测**见 §1（恒持有面成立；**裸臂 get_state agent=null = minor-1**）。

## §6 独立发现

- **minor-1（open，非阻断）：裸无头臂 get_state 的 control.agent = .null。**
  T4 action 4 要求 makeHeadlessSearchState 的 `agentControl` 常量 provider
  落「get_state 无头臂 agent 面 = 恒真常量」——实际仅接 arbitrated 臂
  （:603-606），裸 `--mcp-stdio`/`--mcp-http` 直臂（:482/:497）未传参 →
  缺省 nil → `.null`。**e2e 实证**（§1）：同宿主 tools/list=32 + control_get
  恒真 + get_state.agent=null 三面并存——控制工具在册（union/H3 无违）但
  get_state 镜像谎报「face 未装配」，T4 的「get_state 无头臂恒真面 = 运行时
  自证通道」防堵辅门在这两条臂失效。**修复建议**：两调用点各 +1 行
  `agentControl: { McpControlState.headlessConstant }`（或把该接线点清单
  并入七点清单纪律供未来宿主复用）；测试补裸臂 makeHeadlessSearchState
  get_state 恒真断言一根腿。建议 M7-6 顺路或热修批处理。
- **obs-1**：`isPinned` 落地为**协议扩展属性**而非协议要求——plan SC 文面
  「isPinned 恰协议一处」不符（协议面零命中）。行为零差（生产路由走
  `as? AgentTaskHandle` 具类型转型 + `isRunning`；isPinned 仅测试在具体
  类型上读取）；existential 上扩展属性不动态派发的 Swift 语义坑由转型路由
  结构性规避。归申报面措辞偏差，零动作或 M7-6 注记勘正。
- **obs-2**：acquire 超时臂的 busy 文案为硬编码英文串（未走
  `mcp_error_control_busy` 键——该键由异 holder 臂消费）。与 MCP 错误面
  「部分键化部分硬编码」既有先例一致，zh-audit 无缺口；一致性注记级。
- **obs-3**：acquire 等待窗内无 post-wait `held` 复检——两 agent 在未封合
  窗并发 acquire 的理论竞态（后写者覆写 holderName，双 held 应答）。入口
  已检 + 单 agent 现实面不可达 + admit 门兜底；多 agent 硬化候选归 M7-6+。
- **obs-4**：窗口生命周期 pinned 留存语义已在代码实现并注释
  （attachTaskRegistry 幂等 re-register「window teardown survivor」）但
  未按 plan 风险节要求在 DECISIONS 显式申报裁量。零动作注记。
- 另：执行方 SUMMARY 红线句「LocalizationValue 插值禁形唯一命中为既有注释
  行」少计一处既有代码行（ExportInspectorView :534 拼接形，M7-5 链外既有，
  零新命中）——报告不精确非违例。

## §7 走查配方面（实机走查归第二路/omp 批）

`.work/gui-acceptance/m7-5/MANIFEST.md`（分仓 `0bf32ac`，主仓 worktree
untracked 副本在位）：A 活动卡行面（5 行）/ B Stop→resume（5 行）/ C 禁编
辑 12 面（11 实落点实机行）/ R scopes/viewport 遮挡观感行 + S-3 计时引用
——配方就绪；AX 断言行标注在案；验收形态②的 Manual-Only 面由后续走查批
执行（本路审阅判定：配方与代码 AX 标识/tasks.bar.agent 族逐点对得上）。

## §8 偏差①-⑦裁决（全部成立）

| # | 申报 | 裁决 |
|---|---|---|
| ① | acquire 超时单一执法点（tool 面不叠 10s 包装） | **成立**——双包装会在 10s 边界竞速掩埋 typed busy；ControlToolset 注释 + coordinator 注入缺省 + 测试注入短窗三证在案；typed face 优先与 OQ-7 语义一致 |
| ② | registry 注入缝（configureLiveEditProbe 可换缝 + attachTaskRegistry weak 附着） | **成立**——App 根 @State 声明期引用不可达的装配现实；pipeCoordinator.configure(window:) 跨附着先例同源；acquire register 幂等保 plan 语义不变 |
| ③ | xcstrings 三错误键随 T6 补齐（T1 漏插当轮抓获） | **成立**——终态恰 10 新键（100 行纯插入亲证）+ zh-audit +10 对账亲证 + 补录申报在案；流程缺口当轮自我修正可接受，注记：错误键消费点（coordinator）在 T2 先于键入库（T6），中间态靠 defaultValue 兜底无用户可见破面 |
| ④ | Stop 闭形终态化（interrupted 不被后续边界改写） | **成立**——closeInFlight 只寻 pending + 测试钉（resume 后 entry[0] 保持 interrupted）亲证 |
| ⑤ | S-1 union 注释 token 措辞改写清零 | **成立**——「identifier chain grew one deliberate edit per wave」改写形 + `all29` 残漏 grep 零命中亲证；历史叙事保留 |
| ⑥ | evidence 政策 B 分仓（lightamer-evidence `9b36b42` + MANIFEST `0bf32ac`） | **成立**——分仓两 commit 亲验 + 主仓 gitignore 生效亲证 + worktree 副本在位 |
| ⑦ | 两 GUI fixture +1 `.environment(AgentControlCoordinator())`（never-held） | **成立**——ToastFaceTests/ProjectReadOnlyFaceTests 各 +4 行 diff 亲读，面零漂移 |

## §9 红线族（11 项亲跑全 PASS）

①union 29→32 显式改全点位（冻结表 +3 名序 acquire/get/release、all32 改名、
计数 ×4、五集合并、disjoint +4、descriptionKeys +3、fixture、测试名、头注、
:268 注释清零——diff 全点位亲读；残漏 grep `count, 29|count == 29|all29`
零命中）②零新 SPM（Project.swift 仅两行测试登记）③既有 29 工具 descriptor/
handler 零 diff（快照双证：五钉 23 :200/:223/:243/:697/:277 零触 + union
verbatim 表零触）④错误码 19 additive + 穷举同批 + McpTimeouts 恰 +1 行 +
get_state 三键零漂移 ⑤GUI 三腿零漂移（extension 默认 + finish/cancel/
cancelAll 体零触 + registry.cancel agent 行零命中）⑥LibraryProjectController
零 diff ⑦封存面 17 件零 diff（.metal 全域 0 文件触；DrtRecord/Lut3dKernels
等零命中——diff 清单逐文件过）+ PipeCoordinator 恰 +1 计算属性 ⑧Alcedo
GPL 零复制（ControlToolset/Coordinator 文案自写，语义对表注释在位）⑨单写点
（private(set) 编译封闭 + scope 三词零命中 + F-6 注入缝）⑩xcstrings 恰 10
尾块插入（0 删行亲证）+ UserDefaults 零新键 + runModal 零命中 +
LocalizationValue 零新命中 ⑪Project.swift 恰两行 + BUNDLE-MAP 恰两行
（APP 15+10）+ tuist generate 末位（commit 顺序核）。

## §10 commit 清单（599601d7..7f6fa522，7 commits 逐核）

| commit | 任务 | 面 |
|---|---|---|
| `599601d7` | T1 | ControlToolset 第五域 + registry 第三道门 + 错误码 16→19 + controlAcquire 新档 + 9 处字面量 + 五签名/六缝 |
| `89d8bbff` | T2 | AgentControlCoordinator + PipeCoordinator.liveEditActive + get_state agent 键 + 禁编辑 11 实落点 + GUI 装配 |
| `4755941d` | T3 | isPinned/dismiss 演进 + AgentTaskHandle + bar/dialog agent 行（Stop 单入口） |
| `dea46168` | T4 | makeHeadlessControlContext + 七点接线 + makeHeadlessSearchState agentControl 参（**仅 arbitrated 臂接线——minor-1**） |
| `47737c1d` | T5 | S-1 四处注释清零 + S-3 实测 + 顺路件申报起草 |
| `f91d9aee` | T6 | union 29→32 全点位 + 穷举 19 + 两新测试文件（15+10）+ 登记 + xcstrings 三错误键补齐 |
| `7f6fa522` | T7 | 全套对账 + 红线族 + zh-audit + 台账翻账 |

## §11 判定

- ROADMAP §M7-5 四验收形态：①双端 fixture **PASS**（admit 三拒 + 13 候选集
  行为断言 + 状态机全序，机检在库）②活动卡走查 = **配方就绪**（实机归走查
  批）③Stop→resume 活动连续 **PASS**（F8 双钉 + 同 id 断言）④无头恒持有
  **PASS**（registry/tools 面 + e2e control_get 实证；get_state 镜像面裸臂
  缺口 = minor-1 不触形态本体）。
- **验收结论：PASS**——执行链可交付；minor-1（两行接线缺口）建议 M7-6
  顺路修复或独立热修批，不阻断 M7-5 收口；FIX2③ 维持；union 改动权按
  DECISIONS §6 移交 M7-6（串行禁并行）。

# M7-5 CONTEXT — 块二 GUI agent turn-taking（TURN-01..04；OQ 裁决落定批，2026-10-17）

> **裁决正本**：OQ-M7-5-1..10 **全部按 `M7-5-RESEARCH.md` §6 推荐落定**（M7 站
> charter 授权站内 auto-advance + OQ 全按推荐；先例 M6-3/M6-4、M7-2/M7-3/M7-4
> 同款）。**晨审可推翻**——推翻 = 用户晨审修订本文件对应 D 条，下游 plan 受
> 影响任务面重开（已执行部分按「晨审推翻先例」惯例处理）。读解正本 = 同目录
> `M7-5-RESEARCH.md`（§0 结论摘要 / §1 Alcedo AU14 全语义面 / §2 我方底座
> 差距测绘 / §3 TURN 逐条落点表 / §4 M7-4 顺路件 / §5 测试策略 / §6 OQ 表 /
> §7 红线与许可；file:line 经 planner 2026-10-17 HEAD `cbad16eb` 逐点亲核复核
> 吻合——坐标 fresh 勘正随本批：McpToolError 16 档 :62-85 / McpTimeouts
> :208-225 / registry Entry :283 + writerCheck :296 + dispatch :331-355 /
> makeRegistry :807 / warmLutLibrary :676 / 四宿主 startReadOnlyHTTPHost :686 +
> startHeadlessStdioHost :749 + startHTTPHost :988 + startEmbeddedIfPreference
> Enabled :1089 / runHeadless :451 + runHeadlessArbitrated :512 / union 计数
> ×4 = :275/:328/:356/:510 / all29 :245 / makeUnionRegistry :251 /
> descriptionKeys :363 / BackgroundTaskHandle 协议 :53 + Registry finish :89 /
> WorkspaceHostView .disabled :625/:638 / ScopePanelView 挂载门 :139-140 /
> PipeCoordinator setScopeTapEnabled :2139 + beginContinuousEdit :1771 +
> commitContinuousEdit :1815 / strerror :823〔LightamerCore ExportRenderer〕）。
>
> **夜间全自动授权在案**（先例 D-07-3-T5-1；晨审可推翻）：本 phase 执行批
> （omp/subagent 执行 + 独立验收 + 全套 `--all` 轮〔批准制——执行时
> orchestrator 派发 prompt 即批准〕）可夜间全自动推进，不需逐任务等待用户
> 确认。
>
> **C 档门控行使记录**：RESEARCH 批后续接点自标「C 档第 1 停（OQ 裁决前不进
> plan）」——该停由站 charter 授权链行使（OQ 全按推荐落定即裁决，本文即落定
> 载体）；C 档第 2/3 停照常保留——站内 auto-advance 只覆盖第 2 停的**等待面**
> （闭环汇报照发），第 3 停（VALIDATION 签核给用户过目）不受站内授权覆盖。
>
> **快照改动权（本波显式取权）**：M7-2/M7-3/M7-4 改动权已用讫；TURN additive
> 三工具（control_acquire/release/control_get）→ union 29→32 **显式取权**
> （`McpFinalSnapshotTests.swift` 全点位显式改）。**本波持权窗口内禁并行派发
> M7-6**（orchestrator 编排保证；若误并行派发 = 立即停手上报，禁抢先合并
> 快照表）。

## Phase Goal（ROADMAP §M7-5 行锚定）

`control_acquire` / `control_release` / `control_get`（TURN-01：GUI 会话内
人机共驾控制权）+ registry 第三道门 `requiresControl`（13 工具 state-changing
准入层）+ GUI 禁编辑全表（agent 持锁期间 12 面 disable-not-unmount）+ agent
活动卡（TURN-02：BackgroundTaskBar 底栏行「Agent · holder · 命令」）+ Stop
与恢复（TURN-03：卡 cancel = Stop → 用户立得控制 → 同 holder re-acquire =
ResumeTask 活动连续）+ 无头恒持有（TURN-04：null owner 恒真面）+ scopes
保活三纪律（Alcedo `c7ba784` 对表防病根移植）+ M7-4 顺路件 S-1..S-5。对应
REQUIREMENTS TURN-01..04（:445-448）；对表锚 = Alcedo Studio AU14（HEAD
`6024386`：`automation_control_commands.hpp` / `control_commands.cpp` /
`agent_control_owner.hpp` / `background_task_controller.hpp` / commits
`a6c8848`→`7e0c9cb`→`c7ba784`；**GPL-3.0 只读对表——功能行为/命令语义/错误码
档位克隆合法，代码与文案零复制零翻译**）。

## 决议（D-M7-5-1..10，生效值，硬约束，执行中不重开）

### D-M7-5-1 错误码粒度 = 三码镜像 16→19（OQ-M7-5-1）

- **裁决 = RESEARCH 推荐（①三码镜像）**：`McpToolError` additive 三 case——
  `controlNotHeld`（≙ Alcedo -32003 ControlNotHeld：state-changing 未持
  control，文案要点「先 control_acquire」）/ `controlRevokedByUser`（≙
  -32004：用户已 Stop agent，文案要点「停下问用户；用户同意后再
  acquire」）/ `controlBusy`（≙ -32005：另一 holder 已持有，message 携当前
  holder）。16 档封闭表 additive 扩为 19 档（**本波持权申报**——错误码
  additive 自 M7-2 modelUnavailable 15→16 先例第三行使）；穷举测试
  `testMcpToolErrorCodesSixteenValuesExhaustive` 同批显式改 16→19（法名随批
  `…NineteenValuesExhaustive`）。
- **文案全部自写**（禁抄 Alcedo GPL 措辞——research §2.3 明令）；xcstrings
  三新键 `mcp_error_control_not_held` / `_control_revoked_by_user` /
  `_control_busy` 尾块纯插入。
- 被否备选：②两码（busy 并入 controlNotHeld 携 detail——agent 侧逻辑有
  歧义，Alcedo 同构对表失真）。

### D-M7-5-2 工具名域归属 = 独立第五域 ControlToolset（OQ-M7-5-2）

- **裁决 = RESEARCH 推荐（①独立第五域）**：新文件
  `App/Sources/Lightamer/MCP/Tools/ControlToolset.swift`——`McpControlContext`
  （全 provider closure optional 缺省 nil——`McpSearchStateContext` /
  `McpProjectContext` 同款；「registration consumes no provider」纪律让
  union fixture 全 nil 即注册）+ `McpControlState` 值类型
  `{held, revokedByUser, holder}` + `McpControlToolset.registerAll` 三工具。
- union 分层 editing(9) + culling(14) + searchState(3) + project(3) +
  **control(3) = 32**；域快照层新文件 `McpControlToolsetTests`（union 头注
  「Snapshot layers」清单同批 +1 行）。
- 被否备选：②折入 SearchStateToolset（control ≠ 检索语义；get_state 住
  searchState 只是投影面巧合——「状态读」域收编「控制写」域破坏域自治）。

### D-M7-5-3 requiresControl 集 = 13 工具全集（OQ-M7-5-3）

- **裁决 = RESEARCH 推荐（①13 全集）**：`Entry` additive 第三字段
  `requiresControl`（缺省 false = 既有注册零 diff）+ `setControlAdmit`
  seam（形同 `setWriterCheck`；**dispatch 序 = writerCheck → controlAdmit →
  handler，两道门叠加互不替代**）。候选集精确 13：
  - editing 4：`load_image`（requiresWriter:false 但 state-changing——切
    编辑器文档）、`apply_params`、`paste_adjustments`、`export_image`；
  - culling 6：`set_rating`/`set_flag`/`set_color_label`/`append_note`/
    `set_keywords`（metadata write face 注册批）+ `apply_preset`；
  - match 1：`match_color`；project 2：`project_open`/`project_create`。
- **控制三命令自身免 requiresControl**（Alcedo「控制命令改变的只是控制
  本身」同语义）；admit 拒形 = D-M7-5-1 三码（未持 → controlNotHeld /
  用户 Stop 后 → controlRevokedByUser；异 holder busy 只出现在 acquire）。
  异语义由各自错误码先行（projectReadOnly/imageLiveInEditor 在 handler
  内）——控制门是统一准入层非替代层。
- **writeCallCount 零波及**：计数仍只挂 requiresWriter 门（controlAdmit
  不增计——M6-1 写权计数语义不变）。
- 被否备选：②收窄 10（project/load_image 除外——Alcedo 把 project.open/
  create 与 editor.open 全算 state-changing；半开门 = 准入层不一致）。

### D-M7-5-4 GUI 禁编辑广度 = Alcedo 全表 12 面 + disable-not-unmount（OQ-M7-5-4）

- **裁决 = RESEARCH 推荐（①全表）**：agent 持锁期间 UI 阻止面 =
  `AgentControlCoordinator.holdsControl`；**与既有 `isReadOnly` 同点位合并
  `.disabled(readOnly || agentHeld)`**（M6-1 只读呈现先例机械、新状态源）。
  12 面落点表（research §2.4 为正本）：
  adjustment panels（`EditorAdjustmentStackView` + Drt/Film/RawDecode 页宿主
  列）/ viewport edit tools（`EditorToolRailView` + Nodes 画布 + 蒙版编辑）/
  Undo、Redo、history head（`MenuCommandSet` 命令项 + `EditorToolRailView`
  历史列表）/ Version mutation+checkout（`VersionsPanelView`）/ editor 切图
  （`FilmstripView` + SessionCoordinator 路由）/ import（`ImportModeDialog`
  confirm → `LibraryProjectController.runImport` 入口）/ delete / rating
  （图库删除/评分控件——`LibraryGridView`/`LibraryInspectorView`）〔
  **F5 勘注（2026-10-13 plan 评审，裁决不重开）**：delete 面我方语义
  缺席——无删除工具（MCP 29 无 delete）+ 无删除 UI（全 App 无图库删除
  路由），零落点申报（LibraryGridView 零触），Alcedo 禁面语义由缺席
  覆盖〕/
  export start（topbar export/yiyin 钮 :625/:638 同点位 + `ExportState`
  enqueue 入口）/ project open/create/close（**调用点视图层加门——
  `LibraryProjectController` 文件零 diff，FIX2③ 第四波维持**）。
  保留面（不禁）：浏览/缩放/搜索/设置/**scopes 面板**/任务卡/Toast。
- **机制纪律（红线，防 Alcedo 同病移植）**：**disable-not-unmount**——门
  一律 `.disabled()` 于容器层级；`if !agentHeld { Panel() }` 条件卸载形态
  禁入（卸载即触发 onDisappear → scope tap 关 = Alcedo `c7ba784` 病根同形）。
- 被否备选：②收窄编辑器局部（图库写面与 agent 写工具冲突面同源——半开
  门 = 竞态窗）。

### D-M7-5-5 活动卡宿主 = BackgroundTaskBar 底栏行（OQ-M7-5-5）

- **裁决 = RESEARCH 推荐（①bar 行）**：宿主 = `BackgroundTaskBarView` 底栏
  行 + `BackgroundTaskDialogHost` 对话框（双呈现同源投影既有面）；卡面
  「Agent · <holder> · <命令 summary>」+ indeterminate progress；**Alcedo
  AU14「零 banner 零新窗口零新通知通道」裁示同构**；banner 只留 M6-1 只读
  面（`ProjectReadOnlyBannerView` 不复用不加行）。
- 被否备选：②独立横幅（第二呈现面）③双面并存（双真相）。

### D-M7-5-6 registry 演进 = pinned+activity+dismiss+resume 全套（OQ-M7-5-6）

- **裁决 = RESEARCH 推荐（①全套）**：KD-7「腿需要更多就演进协议」此刻是
  真实需求（TURN-03 resume 活动连续性依赖逐条活动）非投机。落面：
  - `BackgroundTaskHandle` 协议 additive `isPinned: Bool`（**extension 默认
    false = 既有三腿零 diff**）；registry additive `dismiss(id:)`（pinned
    任务显式除名 = finish 的命名面）；**resume 路由 = coordinator**（同
    holder re-acquire → 同 id 回 Running——句柄从未除名，快照回 Running 即
    活动卡复燃；registry 零新 resume 方法）。
  - `AgentTaskHandle: BackgroundTaskHandle`（isPinned = true）携
    `activity: [AgentActivityEntry]`（summary/note/result）。
  - **activity 闭形 = 边界驱动**（与 Alcedo BeginCommand/EndCommand token
    语义对表的简化形——admit seam 形同 writerCheck 只承 admit，end 无法
    在 seam 内挂 defer）：admit 成功即登记活动条目并置 in-flight；下一边
    界（下次 admit / release / Stop）闭前条目并记结果（**用户 Stop 时在跑
    的命令如实记 interrupted**——Alcedo 行为保持）；DECISIONS 申报该终形。
  - **既有三腿零漂移**：import/export/AI 走 finish 即移除语义不变（isPinned
    默认 false；负测钉）。
- 被否备选：②最小面（activity 折进 detail 字符串——resume 活动连续性失去
  承载）。

### D-M7-5-7 acquire 等未封合输入 = 等待 + McpTimeouts.controlAcquire 10s 新档（OQ-M7-5-7）

- **裁决 = RESEARCH 推荐（①等待 10s）**：acquire 检
  `hasInFlightLiveEdit`（D-H1 begin/commit 窗计数查询——`PipeCoordinator`
  additive 只读深度计数，`beginContinuousEdit` :1771 / `commitContinuousEdit`
  :1815 两点配对增减）〔**2026-10-13 plan 评审 F2 载体勘注（orchestrator
  裁定，裁决不重开）**：等待窗载体改三窗 OR 计算属性 `liveEditActive =
  isEditingContinuous || isEditingDrt || isEditingFilm`——DRT/Film 拖动
  连续窗与 D-H1 窗同入口径（Alcedo UnsealedEditorInput 全语义对表；
  深度计数的视图拆卸丢 commit 永久卡死脆弱性 = V2 遗留面登记）；
  「等待 + 10s + 注入短窗」裁决原样〕；有在飞 live drag → acquire 挂起轮询等封合；
  `McpTimeouts.controlAcquire`（**新档 `.seconds(10)`**）兜底超时 →
  `controlBusy`（message 携「编辑器输入未封合」语义族——自写文案）。
  用户拖滑杆是秒级常态，立即拒会把 agent 打进无谓重试环。
- **McpTimeouts 历史红线勘误显式申报**：M7-2..M7-4 三波「零新档零改档」后
  本波**首开新档**——additive（`controlAcquire` 一行），既有八档值零改零
  触；执行批 DECISIONS 承接本申报（晨审可翻为「立即拒」，翻 = 改 D-M7-5-7
  + acquire 三态测试面）。
- coordinator acquire 超时参数可注入（缺省 = `McpTimeouts.controlAcquire`）
  ——测试传短窗（如 200ms）判定超时臂，禁测试真等 10s。
- 被否备选：②立即拒 -32005 族（重试环浪费）。

### D-M7-5-8 get_state 扩展形态 = `control.agent` 子对象（OQ-M7-5-8）

- **裁决 = RESEARCH 推荐（①子对象）**：`get_state` 的 control 对象 additive
  恰 +1 键 `"agent": {held, revokedByUser, holder}`——与 Alcedo state.get
  「control 状态对象」同构；**既有三键 lock/holder/writeCallCount 值与形
  零漂移**（additive 键在 dict 尾部——golden 显式改同批申报）。载体 =
  `McpSearchStateContext` additive optional provider（缺省 nil →
  `.null` 诚实面）；GUI 臂 provider = MainActor.run hop 读 coordinator；
  无头臂 = 常量 `{held:true, revokedByUser:false, holder:""}`。
- 被否备选：②平铺三键（control 对象扁平化——与 lock/holder 族混层）。

### D-M7-5-9 Stop 入口 = 任务卡 cancel 钮单入口（OQ-M7-5-9）

- **裁决 = RESEARCH 推荐（①卡单入口）**：Stop = `AgentControlCoordinator
  .stop()`（cancel agent 任务终态 Canceled + 控制立即回用户 +
  stoppedHolderName 记忆 + in-flight 活动条目如实闭 interrupted）；入口 =
  活动卡 cancel 钮单点（Alcedo `7e0c9cb`「Remove Return control、Stop 从
  任务卡」同构）——不加菜单命令（双入口 = 第二真相）。
- **Stop→ResumeTask 语义**：同 holder re-acquire → 同 id 同活动列表回
  Running（活动历史跨 Stop 连续）；异 holder 在 Stop 后 acquire 合法
  （新建任务；旧 holder Canceled 任务留列表由用户手动 dismiss）；
  stoppedByUser 旗标在任一成功 acquire 时清除。
- 被否备选：②菜单双入口（第二真相）。

### D-M7-5-10 read-only HTTP 宿主 = control 工具照常注册（OQ-M7-5-10）

- **裁决 = RESEARCH 推荐（①注册）**：union 快照单值纪律（所有宿主同 32
  面——tools never disappear 延续）；read-only 宿主 control 三工具走恒真
  面，state-changing 写仍被 requiresWriter 门前置 `serverReadOnly` 拒
  （控制态与写权正交如实呈现）。四宿主缝 + EmbeddedState 缝 additive
  透传（GUI off→on toggle 控制工具不静默缺席——M7-2 F-4① 第五缝同款
  第六缝）。
- 被否备选：②不注册（union 计数分宿主分叉）。

## 登记申报（非 OQ）

- **①无通知通道**：Alcedo 广播 `control.changed` 等 5 通知——我方 MCP v1
  同步 req/resp 无通知（Phase 14 裁决）；agent 以 `control_get` / `get_state`
  轮询替代（偏离申报入 DECISIONS，不设轮询推送）。
- **②无 GUI 选区类工具**：Alcedo headless `library.selection.get/set` 返
  -32001 not_ready——我方无对应工具，**零新错误码**（`notSessionMember`
  typed 拒为对表物，登记申报）。
- **③S-2 路由二选一显式申报**：见下顺路件表——**本波让渡下一 Export 波**
  （planner 裁量：ExportRenderer 非 M7-5 任意任务触碰面，顺路将为纯 MCP/GUI
  波引入 Core Export 域扩散 diff 面；单行修复须伴 EEXIST 路径可观测判定腿
  才不重演 M7-2 F-AC-1「交付或申报」教训——为一行修复开新 EXPORT 测试腿
  = scope 膨胀；M7-4 VALIDATION 原路由「随下一 Export 波」维持 = 零 churn）。
  晨审可翻为「本波顺路」（一行 `let savedErrno = errno` + 判定腿）。

## M7-4 顺路件（本波路由；正本 = `phases/m7-4-mcp-o4/M7-4-VALIDATION.md` §挂账）

| # | 件 | 本波处置 |
|---|---|---|
| S-1 | minor-1 五处过时计数注释（McpFinalSnapshotTests :268〔"exactly these 27"〕+ McpHostTests :466/:668〔"21-tool face"〕+ McpSearchStateToolsetTests :16〔"face (21 …"〕/:265〔"count rides 21"〕——注释正骑计数面 = H1 家族误导面；可执行断言全对） | **随 union 29→32 同批清零**：McpHostTests :466/:668 + McpSearchStateToolsetTests :16/:265 四处在 T5 注释批清零；McpFinalSnapshotTests :268 + 头注 :15/:20/:25 随 T6 union 显式改批同 commit 清零（union 文件 = T6 持权批） |
| S-2 | minor-2 strerror clobber 一行（`LightamerCore/Sources/Export/ExportRenderer.swift` :823——`strerror(errno)` 求值先于 fallback `errno \(errno)` 判读；POSIX 不保证 errno 保全；防覆盖语义不损） | **让渡下一 Export 波**（显式申报见上③） |
| S-3 | S2 预热后 stdio 首调实测（`list_luts` 预热环境首调计时——对照 M7-3 冷窗正本 50.2s） | **本波走查顺路实测**（T5：spawn 真二进制计时一行，数据落 `evidence/s3-preheat-first-call.log`；T7 走查清单引用） |
| S-4 | FIX2③ 维持注记（`LibraryProjectController` 零 diff 连续三波） | **第四波维持注记随批**（GUI 门设计加调用点视图层——controller 零 diff 红线延续） |
| S-5 | 观察项 A 卷归类勘误（/Volumes/UNITEK = Case-sensitive APFS——申报文字勘误） | **条件顺路——本波不触**：M7-5 DECISIONS 不涉 exFAT/EOPNOTSUPP 卷归类句，显式申报无动作（若执行期意外触该句则随批勘正 + 申报） |

## 键族 / 登记面

- **xcstrings 尾块纯插入 10 键**（历史键字节与顺序零触碰）：工具描述 3
  （`mcp_tool_desc_control_acquire` / `_control_release` /
  `_control_get`）+ 错误文案 3（`mcp_error_control_not_held` /
  `_control_revoked_by_user` / `_control_busy`）+ 卡面/Stop 面 4
  （`tasks_agent_kind` / `agent_card_waiting` / `tasks_agent_stop` /
  `tasks_dismiss`）。zh-audit `--check` 对账 source keys 数 +10 +
  `--self-test` PASS。**描述键一律 `String(localized:defaultValue:)` 显式
  形态**（插值禁形零命中）。
- **UserDefaults 零新键**（控制态会话作用域不持久——D-M7-5 卡面无记忆键）。
- **登记纪律**：新测试两文件 `McpControlToolsetTests.swift` /
  `AgentControlCoordinatorTests.swift` → Project.swift 恰两行（Lightamer
  TestsApp 数组）+ BUNDLE-MAP 恰两行（APP 域）+ `tuist generate` 恒为该批
  最后一个动作（L041）。

## 红线（正本移交 `M7-5-01-PLAN.md` front-matter `red_lines`，此处摘要）

①union 29→32 **显式取权**（全点位显式改 + DECISIONS 申报；五钉 23 不变
〔editing 9 + culling 14——控制域独立新增不触两域〕+ 残漏 grep；**M7-6 禁
并行**——orchestrator 编排保证）。②零新 SPM（Project.swift dependencies 块
零 diff；仅测试登记行 +2）。③既有 29 工具 descriptor/handler 零 diff
（requiresControl = **Entry 字段** additive——descriptor 面零新字段，
readOnlyHint/destructiveHint/schema/description 零触碰；controlAdmit 不增
writeCallCount）。④错误码 16→19 additive 本波持权 + McpTimeouts
controlAcquire 新档 additive 申报（既有八档值零改）+ get_state 既有三键值
与形零漂移（agent 恰 +1 additive 键）。⑤GUI 既有三腿（import/export/AI）
零漂移（isPinned extension 默认 false 负测钉）+ WorkspaceModel.scopesVisible
单源（View 菜单开关唯一写者——agent 状态机零触碰）+ ScopeThrottle 零触 +
disable-not-unmount（`if !agentHeld {…}` 条件卸载形态禁入）。⑥`Library
ProjectController` 文件零 diff（FIX2③ 第四波维持——门加调用点视图层）。
⑦封存面零触（DrtRecord / TerminalTailPolicy / DrtTailAssembly / PixelPipe /
Lut3dKernels.metal / DrtEotf / ExportQueueContract / 六格式导出矩阵 /
NodeGraphCommand / sidecar schema / HistoryStack / HistoryHash /
PipelineDocument / V50Order / GradeCatalog / Registry / ModuleInstance）。
⑧Alcedo GPL 代码/文档文案零复制零翻译（错误文案/卡面文案/工具 description
全部自写；只对表命令语义/状态机语义/错误码档位）。⑨AgentControlCoordinator
单写点（control 状态只有 coordinator 写——GUI 面/活动卡/get_state 全读投影）
+ 与 M6-1 SingleWriterLock/LibraryProjectController 零耦合（两层正交，不触
锁面）。⑩xcstrings 10 键尾块纯插入 + zh-audit 双 PASS；UserDefaults 零新键。
⑪`.runModal(` App/Sources 零命中（活动卡/对话框全走 SwiftUI 呈现缝）；
LocalizationValue 插值禁形零命中。⑫`--all` 全套轮批准制 + 8G 门 + MEMFAIL
机检 + 运行中保持监视；测试宿主清理先核 parentage（`ps -o ppid`）。

---

## 晨审推翻点索引（可推翻面速查）

- **D-M7-5-7**：acquire 等待 + `controlAcquire` 10s 新档——若晨审倾向
  「立即拒」= 改 D-M7-5-7 + plan acquire 三态测试面收窄为两态 + McpTimeouts
  新档撤销（红线④申报面随之收窄）。
- **S-2 路由**：本波让渡 ↔ 本波顺路（一行 + 判定腿）二选一，晨审可翻
  （翻 = T5 增 ExportRenderer 一行 + EXPORT 判定腿）。
- **D-M7-5-3**：requiresControl 13 全集 ↔ 收窄 10（load_image/project 族
  除外）——翻案 = 候选集改动 + 对应拒面测试收窄。
- **D-M7-5-4**：禁编辑全表 12 面 ↔ 编辑器局部收窄——翻案 = 禁编辑点位表
  收缩（T2 验收核心面随之改）。

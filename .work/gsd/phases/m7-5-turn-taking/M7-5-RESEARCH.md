# M7-5 Research——块二 GUI agent turn-taking（TURN-01..04 语义测绘与落点）

> **日期**: 2026-10-17（research worker 批，夜间全自动授权在案先例 D-07-3-T5-1）
> **性质**: doc-only——零源码 diff；OQ-M7-5-1..10 待裁决后进 plan。
> **输入**: REQUIREMENTS TURN-01..04（:445-448）+ `research/ALCEDO-CLI-AI-SURVEY.md` 块二（§1.2/§5/§7，AU14 语义）+ 底座 M6-1 SingleWriterLock 面 + AGENTS.md「M7-2/M7-3/M7-4 架构增量」节 + `phases/m7-4-mcp-o4/M7-4-VALIDATION.md` §挂账。
> **上游侦察对**: Alcedo Studio 本地仓 HEAD `6024386`（v0.3.3+2）；turn-taking 面证据 = `automation_control_commands.hpp` / `control_commands.cpp` / `agent_control_owner.hpp(.cpp)` / `background_task_controller.hpp` / AU 计划 §2.8 / commits `a6c8848`（AU14）→ `7e0c9cb`（钉住+Stop）→ `c7ba784`（scopes 保活）。**GPL-3.0 只读——功能行为/命令语义克隆合法（survey §6），代码与文档文案零复制零翻译**。
> **基线**: 全套 `TOTAL|3925/35/0|`（M7-4 终态）；union 快照改动权 = **本波持有**（M7-6 禁并行——串行红线延续）。

---

## 0. 结论摘要

- **四条 TURN 全 additive 可落、单源齐备、零新依赖**，估 **1 plan**；ΔN 预估 **+14..22**（registry 门测试 + coordinator 状态机测试 + 无头恒持有负测 + 活动卡面测试 + union 29→32 显式改）。
- Alcedo AU14 语义 = **三层同心**：①control 三命令 + admit 规则（协议面）；②AgentControlOwner 会话内单写者状态机（GUI 面，与项目级 flock 正交）；③task island 活动卡（呈现面）。我方对应 = MCP 第五域 ControlToolset + App 侧 AgentControlCoordinator + BackgroundTaskBar 扩展，三面各自有现成缝。
- **底座复用非等待项**（charter 勘误已登记）：M6-1 锁面管「跨进程项目写权」，turn-taking 管「GUI 会话内人机共驾」——两层正交叠加，不合并不改 M6-1。
- **Scopes 保活**（Alcedo `c7ba784` 对表）：我方 ScopePanelView 门 = **面板挂载可见性**（`setScopeTapEnabled` onAppear/onDisappear），不派生自编辑控件使能态——只要 GUI 禁编辑走 **disable-not-unmount**（`.disabled()`，不条件卸载视图），scopes 在 agent 控制期间结构性保活（agent 的 apply_params 每次渲染 → scope 跟采样，≤15 Hz 节流）。Alcedo 的病根（visualActive 派生自 controlsEnabled）在我方结构里不存在，但**纪律必须入 plan 红线**防未来回归。
- **union 29→32 本波显式改**（control_acquire/control_release/control_get 三工具新第五域）；M7-4 顺路件（minor-1 五处过时注释 + minor-2 strerror 一行 + S2 预热首调实测）全部登记入本波顺路清单（§4）。
- 错误码表 **16→19 additive**（controlNotHeld / controlRevokedByUser / controlBusy ≙ Alcedo -32003/-32004/-32005 同构）；「无头恒持有」零新错误码（恒真面，无拒形）。

---

## 1. Alcedo AU14 turn-taking 全语义面测绘（file:line 证据）

### 1.1 control 三命令（`automation_control_commands.hpp:15-27` + `commands/control_commands.cpp`）

| 命令 | 参数 → 结果 | 语义 |
|---|---|---|
| `control.acquire` | `holder_name?`（缺省 `"agent"`）→ `{held, revoked_by_user, holder_name}` | 取 GUI 会话控制权；**非 state-changing**（控制命令自身免 admit） |
| `control.release` | — → 同上状态 | 归还控制权；agent 任务以 **Succeeded** 收尾；无控制时零动作（幂等） |
| `control.get` | — → 同上状态 | 纯读 |

**acquire 三拒形**（`control_commands.cpp` AnswerAcquire）：

1. `-32005 Busy`「Another agent holds control: <holder>」——另一 holder 已持有（**立即拒，不排队不等待**）。
2. **UnsealedEditorInput → 不拒，等待**（`RequestAcquire(holder, still_waiting, done)` + `RecheckPendingAcquires`）：用户正在拖编辑器滑杆（未到 Release/Cancel 封合边界）时 acquire 挂起，编辑器输入落定后重试；调用方超时（命令级 `timeout_ms`）停止等待 → `-32007 Failed`「The editor input of the user is not sealed.」。
3. headless 宿主（owner == nullptr）：`control.acquire` 直接返回恒真状态（NotReady 臂不可达——headless 无「agent control 不可用」形态）。

**headless 恒真面**（`AutomationControlState(nullptr)`）：`{held: true, revoked_by_user: false, holder_name: ""}`——null owner 即「agent 恒持有」。

### 1.2 admit 规则（`MakeAgentStateChangeControl`，同文件）

每条 **state-changing 命令**进 handler 前过 admit 闸（规则三臂）：

- `held == true` → 放行（附 begin_command/end_command 活动钩子）。
- `stopped_by_user == true` → **-32004 ControlRevokedByUser**，固定语义文案（要点：「用户已停掉 agent——停止工作、问用户怎么办；用户让你继续后才调 control.acquire」）。
- 其余（从未持有/已释放）→ **-32003 ControlNotHeld**「This command changes the session state and needs agent control. Call control.acquire first.」。

**activities 钩子**：命令开始 → `BeginCommand(summary, note)` 返 token + 任务活动条目（note = agent 给的理由，可空）+ 任务 detail = 该命令 summary；命令结束 → `EndCommand(token, succeeded)`（用户 Stop 时在跑的命令也如实记结果）。

### 1.3 AgentControlOwner（`album_backend/agent_control_owner.hpp`——会话内控制权状态机）

- **单一写点**：control 状态（held/holder_name/stopped_by_user/stopped_holder_name/task_id）只有此 owner 改；GUI 线程 only。
- **任务钉住**：acquire 注册一条 `BackgroundTaskKind::AgentControl` 后台任务并钉住（pinned——终态后留在列表直到用户 DismissTask）；**同 holder re-acquire → `ResumeTask`**（同 id、同活动列表、回 Running——任务与活动历史跨 Stop 连续）；异 holder acquire 在 Stop 后也合法（新建任务；旧 holder 的 Canceled 任务留列表由用户手动 dismiss）。
- **HeldByOtherAgent / UnsealedEditorInput** 两拒形枚举（`AgentControlRefusal`）。
- **GUI 禁编辑机制**：agent 持锁期间该任务持全局 `InteractionCapability::UserStateChange` interaction lock；**user-facing adapters 读该锁拒绝用户状态变更**；**editor session admission 不读该锁** → agent 自己的命令照常跑（同一把锁两种读者，turn-taking 的机械核心）。
- Stop = `Stop()` Q_INVOKABLE：cancel agent 任务（终态 Canceled）+ 控制立即回用户 + `stopped_holder_name_` 记忆（resume 凭据）。

### 1.4 活动卡 / task island（AU 计划 §2.8 + `7e0c9cb` AgentSessionCard.qml）

- acquire 注册的任务字段：Kind label =「Agent」/ Title = holder_name / Detail = 运行中命令 summary，命令间 =「Waiting for the next command」/ Progress = indeterminate / **Cancelable = Yes，Cancel ≙ Take control（后迭代为 Stop）** / Locks = `UserStateChange`。
- island（底部任务条）随运行任务展开；点击开既有任务对话框（activity 逐命令可见）；**AU14 零新窗口零新通知通道零 banner**——全走既有后台任务呈现。
- `7e0c9cb` 迭代增量：任务钉住（完成不消失直到 dismiss）+ 逐命令活动记录（note + 结果）+ **Stop 取代 Return control**（原来「用户夺回后 agent 永久失权 -32004 直到用户 Return control」，改为「Stop 后同 holder 可恢复」）+ 不定进度扫掠换旋转弧 + island 按钮 开任务对话框。

### 1.5 GUI 禁编辑清单（AU 计划 §2.8 Rules）

agent 持锁期间 UI 阻止的用户动作（保留面 = 浏览/缩放/搜索/设置）：

> adjustment panels、viewport edit tools、Undo、Redo、history head moves、Version mutation and checkout、image switching in the editor、import、delete、rating、export start、project open/create/close。

acquire 成功条件（§2.8）：无另一 holder + 用户未 revoke + 编辑器无未封合输入；未封合输入 → acquire 等到边界（命令 timeout 兜底）。

### 1.6 scopes 保活（commit `c7ba784`，Fixes #376）

**病理两件**：①`EditorScopePanel.qml` 的 `visualActive` 派生链含 `controlsEnabled`——agent 控制禁掉编辑控件 → scopes 分析停摆；②`EditorScopeController::Shutdown()` 经 `scope_pool_.clear()` 丢弃已入队 refresh 任务，该任务永不重置 in-flight flag → 下一张图 refresh 永不跑。

**修法三件**：①polling 条件改 `visual_active_ && image_identity_ != 0`（= 面板可见 × 有图——**与编辑控件使能态解耦**）；②`visualActive` 值**只由面板写**（`SetImageIdentity(0)` 关图不再清它，下一张图自动恢复轮询）；③Shutdown 重置 in-flight flag（`refresh_in_flight_ = make_shared<atomic_bool>(false)`）。

### 1.7 headless 简化臂（TURN-04 对表面）

- null owner → control 三命令全走恒真面（§1.1）；state-changing 命令 admit 规则在 headless 恒放行（owner 为 null 时 admit 返回放行——`MakeAgentStateChangeControl` 的 control==nullptr 臂）。
- GUI 选区类命令 `library.selection.get/set`：headless 返回 **`-32001 not_ready`**（AU 计划 §2.6 表注——GUI 选区概念仅 GUI 宿主有效）。

### 1.8 通知面（登记偏离，非 OQ）

Alcedo 广播 `control.changed`（held/revoked_by_user/holder_name）等 5 通知。**我方 MCP v1 同步 req/resp 无通知（Phase 14 裁决）**——agent 以 `control_get` / `get_state` 轮询替代。偏离申报入 DECISIONS，不设轮询推送。

---

## 2. 我方底座差距测绘

### 2.1 底座已有（复用面，逐条 file:line）

| 面 | 现状 | 对 turn-taking 的关系 |
|---|---|---|
| `LightamerCore/Sources/Foundation/SingleWriterLock.swift` | 五态 flock 仲裁 + payload 诊断面 + `probeLockAvailable` | **项目级跨进程写权**——与 turn-taking（会话内）正交分层，零改动 |
| `McpProjectLockVerdict`（McpToolRegistry.swift:130-146） | `.writable / .held(holderSummary, guidance)` + errorMessage 单源 | 语义先例：typed verdict + holder 摘要 + 连接指引——agent 卡 holder 面同构取材 |
| registry 两道门（McpToolRegistry.swift:281-354） | `requiresWriter` + `writerCheck` seam + `writeCallCount` | **第三道门 `requiresControl` 的现成机械形状**（Entry 加字段 + admit seam，同 writerCheck 形） |
| get_state control 面（SearchStateToolset.swift:1053-1076） | `control.lock`（writable/held/null）+ `control.holder` + `control.writeCallCount` | **agent 控制状态的 additive 挂点**（现键字节零漂移，加 agent 子对象） |
| projectReadOnly 臂（M7-3）+ `ProjectReadOnlyBannerView` + `.disabled(isReadOnly)`（WorkspaceHostView.swift:153-157/:625/:638） | M6-1 GUI 只读呈现三件 | **GUI 禁编辑的呈现先例**（inset 横幅 + 逐控件 disabled；agent 禁编辑走同款机械、新状态源） |
| `BackgroundTaskRegistry`/`BackgroundTaskHandle`（Library/BackgroundTaskHosting.swift）+ 双呈现面（UI/Shell/BackgroundTaskBarView.swift） | 底栏 + 对话框同源投影、cancel 路由 | **活动卡的宿主**（KD-7「腿需要更多就演进协议」条款此刻兑现——pinned/activity/dismiss/resume additive） |
| GUI MCP 臂装配（LightamerApp.swift:1428-1612）+ 无头三臂（McpServerController.swift :580-700） | liveState closure + MainActor.run hop 惯例 | control context 的双宿主装配点（headless 恒真面 = 常量闭包零成本） |
| D-H1 live-edit 窗口纪律（AGENTS M3-1 节：begin/setLive/commit 三件套 + 松手一 commit） | liveEdited 实例 + bypass 三防线 | **UnsealedEditorInput 的我方对表物**——「in-flight live edit 查询」的天然钩子（begin/end 对计数） |

### 2.2 缺口清单（对照 TURN-01..04）

- **TURN-01**：`control.*` 三工具（无）；registry `requiresControl` admit 门（无）；GUI 禁编辑状态源（无）；-32003/-32004/-32005 同构错误（无——表 16 档无 control 族）。
- **TURN-02**：agent 活动卡（无——registry 无 pinned/activity/dismiss，handle 无 activity 面；bar 行无「Agent · holder · 命令」形态）。
- **TURN-03**：Stop/恢复（无——registry.finish 直接移除任务，无钉住；无 ResumeTask；EditorState 无 stoppedByUser 面）。
- **TURN-04**：无头恒持有面（新增 control 工具族时一并装配——常量闭包，负测钉住）。
- **明确不做**（survey §5 范围 + MCP-08 封闭集纪律）：无导入/删除工具不入控制面；无独立 CLI 动词（块三挂账不变）；无通知通道（§1.8）。

### 2.3 MCP 工具面设计（TURN-01 骨架）

- **第五域 ControlToolset**：新文件 `App/Sources/Lightamer/MCP/Tools/ControlToolset.swift` + `McpControlContext`（全 provider closure optional 缺省 nil——McpSearchStateContext 同款；「registration consumes no provider」纪律让 union fixture 全 nil 即注册）。
- 三工具（snake_case，与 Alcedo 点分天然异构——survey §6 无逐字 copying 面）：
  - `control_acquire`（`holder_name?: string` 缺省 `"agent"`）→ 状态对象 `{held, revokedByUser, holder}`；
  - `control_release` → 同状态（无控制时零动作幂等）；
  - `control_get` → 同状态（readOnlyHint: true）。
  - 控制命令自身**免 requiresControl**（Alcedo「控制命令改变的只是控制本身」同语义）；acquire/release 非 destructive、`control_get` readOnlyHint。
- **`requiresControl` 门**：`McpToolRegistry.Entry` 加第三字段 + `setControlCheck` seam（形同 writerCheck；dispatch 序 = writerCheck → controlCheck → handler，两道门叠加互不替代）。admit 拒形：
  - 未持有 → `McpToolError.controlNotHeld`（新，文案要点 =「state-changing，先 control_acquire」）；
  - 用户 Stop 后 → `McpToolError.controlRevokedByUser`（新，文案要点 =「用户已停 agent——停下问用户；用户同意后再 acquire」——**文案自写，禁抄 Alcedo GPL 措辞**）；
  - acquire 遇另一 holder → `McpToolError.controlBusy`（新，携当前 holder）。
  - 错误码封闭表 **16→19** additive；穷举 switch 测试同批。
- **requiresControl 候选集（13 工具，精确清单）**：
  - editing 4：`load_image`（requiresWriter:false 但 state-changing——切编辑器文档，Alcedo editor.open 同语义）、`apply_params`、`paste_adjustments`、`export_image`；
  - culling 6：`set_rating`/`set_flag`/`set_color_label`/`append_note`/`set_keywords`（`mcp_tool_desc_write_metadata` 循环注册批，:338）/ `apply_preset`（:529）；
  - match 1：`match_color`；project 2：`project_open`/`project_create`。
  - 排除：`copy_adjustments`（readOnly 预览）、`render_preview`/`list_*`/`get_*`/`search_photos`/IopCatalog 全读面。
- **无头恒持有**（TURN-04）：`makeHeadlessControlContext(mode:)` 常量面——acquire/release 直答 `{held:true, revokedByUser:false, holder:""}`，admit seam 无头臂恒放行（nil check = 放行，与 writerCheck nil 同形）。GUI 臂 context 闭包经 MainActor.run hop 到 AgentControlCoordinator（liveState 同款 hop 纪律 + F-6 结构纪律）。
- **read-only HTTP 宿主**：control 工具照常注册（恒真面）——写仍被 requiresWriter 门拒（serverReadOnly），控制状态与写权正交（登记申报）。
- **get_state additive 扩展**：`control` 对象加 `"agent": {held, revokedByUser, holder}`（GUI 臂从 coordinator 读；无头臂常量；nil provider = `.null` 诚实面）。既有三键（lock/holder/writeCallCount）字节零漂移；goldens 同批显式改。

### 2.4 GUI 侧设计（TURN-01 禁编辑 + TURN-02/03 活动卡）

- **`AgentControlCoordinator`**（App 侧新文件，建议 `App/Sources/Lightamer/State/AgentControlCoordinator.swift`）：`@MainActor @Observable`；状态 = `held / stoppedByUser / holderName / taskId / activity[命令条目]`；单写点纪律（≙ AgentControlOwner——acquire/stop/release/resume/beginCommand/endCommand 全走它）；**与 M6-1 项目锁零耦合**（不触 SingleWriterLock/LibraryProjectController——FIX2③ 维持）。
- **禁编辑清单**（Alcedo §2.8 全表 → 我方落点，gate 值 = `agentControl.holdsControl`；与既有 `isReadOnly` 同点位合并 `.disabled(readOnly || agentHeld)`）：

| Alcedo 禁止面 | 我方落点 |
|---|---|
| adjustment panels | 右栏调整栈容器 `EditorAdjustmentStackView` + panel hosts（Drt/Film/RawDecode/grade/iop 页宿主列） |
| viewport edit tools | `EditorToolRailView` + 节点画布（Nodes/）+ 蒙版编辑 |
| Undo/Redo/history head | `MenuCommandSet` undo/redo/history 命令项 + `EditorToolRailView` 历史列表 |
| Version mutation/checkout | `VersionsPanelView` + `VersionCoordinator` 命令 |
| image switching in editor | `FilmstripView` + SessionCoordinator 切图路由 |
| import | `ImportModeDialog` confirm → `LibraryProjectController.runImport` 入口 |
| delete | 图库删除路由 |
| rating | 图库评分控件（culling UI 批量条） |
| export start | topbar export/yiyin 按钮（:625/:638 同点位）+ `ExportState.enqueue` 入口 |
| project open/create/close | `LibraryProjectController` 三入口（**controller 文件零 diff 维持**——门加在调用点视图层，非 controller 内部） |

  保留面（不禁）：浏览/缩放/搜索/设置/**scopes 面板**/任务卡/Toast。
  机制纪律：**disable-not-unmount**（§2.5）——门一律 `.disabled()` 于容器层级，禁止条件卸载（`if !agentHeld { Panel() }` 形态禁入）。
- **活动卡（TURN-02）**：宿主 = `BackgroundTaskBarView` 底栏行（Alcedo task island 对表）+ `BackgroundTaskDialogHost` 对话框。卡面文案「Agent · <holder> · <命令 summary>」；indeterminate progress；cancel 钮 = **Stop**（TURN-03）。`BackgroundTaskHosting` 演进（KD-7 条款兑现）：`AgentTaskHandle: BackgroundTaskHandle` 携 `activity: [AgentActivityEntry]`（summary/note/结果）+ registry additive：**pinned 保留**（终态不自动 finish 移除）+ `dismiss(id:)` + `resume(id:)`（同 holder re-acquire 回 Running 同活动列表）；既有三腿（import/export/AI）零行为漂移（负测钉）。
- **acquire 等待未封合输入（UnsealedEditorInput 对表）**：acquire 检 `hasInFlightLiveEdit`（D-H1 begin/end 窗计数查询——coordinator/EditorState additive 只读面）；有在飞 live drag → acquire 挂起轮询等封合，`McpTimeouts` 新档（建议 `controlAcquire: .seconds(10)`，apply 同档域）兜底超时 → typed controlBusy 语义族（Failed 档同构；OQ-M7-5-7）。
- **本地化**：新键族 xcstrings 尾块纯插入（`control_*` 工具描述 3 + 错误文案 3 + 卡面/Stop 面若干）；UserDefaults **零新键**（控制态会话作用域不持久）；`String.LocalizationValue("prefix_\(x)")` 插值禁形维持。

### 2.5 scopes 保活测绘（`c7ba784` 对表）

**我方 scopes 现状**（`App/Sources/Lightamer/UI/Shell/ScopePanelView.swift` + `PipeCoordinator.swift:2134-2167`）：

- 数据链 = PREVIEW 输出平面渲染完成后 GPU ScopeReduce 两遍采样，**门 = `setScopeTapEnabled`**（面板 onAppear/onDisappear——挂载可见性单源；关时清结果防陈帧）；节流 = `ScopeThrottle` 纯状态机（≤15 Hz 流式 + 250ms idle settle，已单测）；waveform 读回 = fenced 小纹理 getBytes。
- **关键结构事实**：采样门**不派生自编辑控件使能态**（Alcedo 病根在我方不存在）——`.disabled()` 不触发 onDisappear，面板挂载即 tap 常开；agent 的 apply_params 每次走 GUI pipe 渲染 → scope 跟采样。

**agent 控制期间「什么会停」逐项**（任务书问面）：

| 项 | agent 控制下行为 | 依据 |
|---|---|---|
| scope 采样 | **不停**（面板挂载门 + agent 渲染驱动） | ScopePanelView :139-140 门单源 |
| viewport 呈现 | 命令驱动渲染照常跑；**窗口遮挡/最小化时**呈现与 churn 暂停（M7-1 D-6 可见性门控行为模型——遮 0%，解遮 ≤1s 复燃）——agent 命令的 GPU 执行非 churn 驱动，不受扰；遮挡态 scopes/viewport 观感待 GUI 走查（§5 走查行） | M7-1 VALIDATION 行为模型 |
| pipe 60s clearCaches sweep | 不停（Timer/Task sweep 与控制态无交) | M2-2 架构增量 |
| 用户 live drag | 结构性不存在（用户编辑被禁 → 无未封合冲突窗口） | 禁编辑清单 |
| 后台任务条/Toast | 不停（呈现面与编辑门正交） | BackgroundTaskBarView |

**保活语义技术方案 = 三纪律**（plan 红线，防 Alcedo 同病回归）：

1. **disable-not-unmount**：agent 禁编辑一律 `.disabled()` 容器层，禁条件卸载（卸载即触发 onDisappear → tap 关 → scopes 死 = Alcedo 病根同形）。
2. **`scopesVisible` 所有权**：`WorkspaceModel.scopesVisible` 只由 View 菜单开关写——agent 控制状态机零触碰。
3. **ScopeThrottle 零触**：节流状态机为已测纯函数；控制态不入门。

Alcedo 修法②③的对应检查：面板值所有权（我方 `mode: @State` 面板自有，无外层覆写——健康）；in-flight 丢任务（我方 `setScopeTapEnabled(false)` 显式取消 settle task 并清 pending，语义自洽——健康，负测可在 §5 登记一条）。

---

## 3. TURN-01..04 逐条落点表

| REQ | Alcedo 语义（证据） | 我方落点 | 验收形态（ROADMAP） |
|---|---|---|---|
| **TURN-01** control acquire/release/get + GUI 禁编辑 | 三命令 + admit 三拒形（§1.1/1.2）；GUI 禁编辑 UserStateChange 锁（§1.3）+ 全清单（§1.5） | ControlToolset 第五域 3 工具 + `requiresControl` 第三道门（13 工具集 §2.3）+ 错误码 16→19 + AgentControlCoordinator + 禁编辑点位（§2.4 表）+ get_state additive | **双端 fixture**：agent 持锁 → GUI 编辑动作 typed 拒（coordinator 单测 + 禁编辑点位结构断言）+ 用户夺回 agent 失权（Stop → 写工具 -32004 同构拒）；union 29→32 显式改 ✓ |
| **TURN-02** agent 活动卡 | task island + 卡字段 + Cancel=Take control（§1.4）；「Agent · claude-code · editor.set saturation 20」形 | BackgroundTaskBar 行扩展 + AgentTaskHandle（activity/pinned/dismiss additive §2.4）+ 走查 | **GUI 活动卡走查** ✓（卡面文案 + Stop 钮 + 对话框活动列表 AX 可达） |
| **TURN-03** Stop + 恢复 | Stop = cancel→用户立得控制→-32004→同 holder re-acquire = ResumeTask 同活动（§1.3/1.5，`7e0c9cb`） | coordinator stop/resume 状态机（stoppedByUser + stoppedHolder 记忆 + activity 延续）+ 卡 cancel 路由 + resume 幂等面 | fixture 延伸：Stop → 拒 → 同 holder resume 活动连续 + 异 holder busy（并入 TURN-01 fixture 批） |
| **TURN-04** 无头恒持有 | null owner 恒 `{held:true,...}` + admit 恒放行 + selection 类 not_ready（§1.7） | `makeHeadlessControlContext` 常量面（三宿主装配）+ 恒真负测；GUI 选区类工具我方**不存在**——无 -32001 新码（sessionPair 依赖面既有 `notSessionMember` typed 拒即对表物，登记申报） | **无头恒持有负测** ✓（无头装配写工具免 acquire 直答 + control_acquire 恒 held） |

---

## 4. M7-4 顺路件登记（本波顺路清单；正本 = `phases/m7-4-mcp-o4/M7-4-VALIDATION.md` §挂账）

| # | 件 | 落点（file:line） | 本波路由 |
|---|---|---|---|
| S-1 | **minor-1 五处过时计数注释**（"exactly these 27"/"27 is"/"21-tool face"/"count rides 21"——可执行断言全对，注释矛盾 = H1 家族误导面） | `Tests/LightamerTests/McpFinalSnapshotTests.swift` :263/:268 + `McpHostTests.swift` :466/:668 + `McpSearchStateToolsetTests.swift` :16/:265 | **本波 union 29→32 显式改同批清零**（注释正骑计数面——显式改时顺手校正为新真值，零成本） |
| S-2 | **minor-2 strerror clobber 一行重整**（`strerror(errno)` 求值先于 `errno == EEXIST` 判读——POSIX 不保证保全；防覆盖语义不损） | `ExportRenderer.promoteExclusive`（errno 先存 local 再 strerror） | 登记顺路；**VALIDATION 原路由 =「随下一 Export 波」**——plan 裁量：本波顺路（一行 + 显式申报）或让渡下一 Export 波，二选一显式申报勿静默 |
| S-3 | **S2 预热后 stdio 首调实测**（`list_luts` 预热环境首调计时——对照 M7-3 冷窗正本 50.2s） | 走查批顺路（预热环境 spawn 真二进制计时一行） | 本波走查顺路 |
| S-4 | **FIX2③ 维持注记**（`LibraryProjectController` 零 diff 连续三波） | 本波 GUI 门设计不触 controller（门加调用点视图层）——第四波维持注记随批 | 注记延续 |
| S-5 | 挂账③**观察项 A 卷归类勘误**（/Volumes/UNITEK = Case-sensitive APFS——申报文字勘误） | 若本波 DECISIONS 触 exFAT/EOPNOTSUPP 申报句则随批勘正；否则不动 | 条件顺路 |

---

## 5. 测试策略

1. **union 29→32 显式改全点位**（本波持权，`Tests/LightamerTests/McpFinalSnapshotTests.swift`）：`all29`→`all32`（+`controlTools` 域数组）+ 计数断言 ×4（:275/:328/:356/:510）+ 测试名 Union29Verbatim→Union32Verbatim + 头注三行（:15/:20/:25）+ descriptionKeys +3 + destructive 集不变（control 三工具非 destructive）+ **union 外五钉 23 不变**（editing 9 + culling 14——控制域独立新增不触两域）+ `makeUnionRegistry` 加 control context 参 + minor-1 注释清零（S-1）。同批显式改：`McpServerController.makeRegistry` additive 参（:807-829）。
2. **turn-taking 双端 fixture**（验收形态①③合并批）：registry 层 admit 三拒形（not held → controlNotHeld / stopped → controlRevokedByUser / acquire 异 holder → controlBusy）+ coordinator 状态机全序（acquire→活动条目→Stop→拒→同 holder resume→release→Succeeded 收尾→dismiss）+ GUI 禁编辑结构断言（held 态关键点位 disabled 求值）+ **无头恒持有负测**（headless context 写工具免 acquire 直答 + acquire 恒真）。
3. **活动卡面测试**（验收形态②）：AgentTaskHandle 投影（bar 行 title/detail/indeterminate + cancel 路由到 coordinator.stop）+ 对话框活动列表行集 + AX 标识；GUI 走查批补实机屏面（配方入 `.work/gui-acceptance/m7-5/MANIFEST.md`，含遮挡态 scopes/viewport 观感行 + S-3 计时行）。
4. **scopes 保活**：`ScopeThrottle` 既有纯函数测试零触 + 新增门态翻转断言（控制态翻转不触发 setScopeTapEnabled(false)——结构面断言或 probe）+ disable-not-unmount 负测（禁编辑态面板仍挂载断言）。
5. **回归红线**：既有 requiresWriter/writeCallCount 面 byte 级零漂移（get_state 既有三键 goldens 不变 + additive 键显式改）；BackgroundTaskRegistry 既有三腿负测（finish 即移除语义对 import/export/AI 不变——pinned 只对 AgentTaskHandle 生效）；错误码表穷举测试 16→19；zh-audit `--check` + `--self-test` 双跑；xcstrings 尾块纯插入机检；UserDefaults 零新键；`\.runModal(` App/Sources 零命中（活动卡/对话框全走非阻塞缝）；`String.LocalizationValue` 插值禁形零新增。
6. **全套轮**：`caffeinate -dis Scripts/test-direct.sh --all`（orchestrator 批准 + 8G 门监视，AGENTS 资源监控节）；预估终值带 **3939..3947**（+14..22）。

---

## 6. OQ 清单（带推荐，待裁决后进 plan）

| # | 问题 | 选项 | 推荐 |
|---|---|---|---|
| **OQ-M7-5-1** | 错误码粒度：三新码镜像（controlNotHeld/controlRevokedByUser/controlBusy ≙ -32003/-32004/-32005）vs 两码（busy 并入 controlNotHeld 携 holder detail） | 16→19 vs 16→18 | **三码镜像**——agent 侧逻辑无歧义，Alcedo 同构对表最忠实 |
| **OQ-M7-5-2** | 工具名域归属：独立第五域 ControlToolset vs 折入 SearchStateToolset（control 面已住 get_state） | 新域 3 工具 vs editing/searchState 域 +3 | **独立第五域**——语义自治（控制 ≠ 检索）、union 域数组清晰、fixture 全 nil 即注册纪律沿用 |
| **OQ-M7-5-3** | requiresControl 集：13 工具全集（§2.3）vs 收窄（load_image/project 族除外——它们已有自己的锁/会话语义） | 13 vs 10 | **13 全集**——Alcedo 把 project.open/create 与 editor.open 全算 state-changing；异语义由各自错误码先行（projectReadOnly/imageLiveInEditor 在 handler 内），控制门是统一的准入层 |
| **OQ-M7-5-4** | GUI 禁编辑广度：Alcedo 全表 12 面 vs 收窄（仅编辑器内面板） | 全表 vs 编辑器局部 | **全表**——图库写面（评分/删除/导入/项目开关）与 agent 写工具冲突面同源，半开门 = 竞态窗 |
| **OQ-M7-5-5** | 活动卡宿主：BackgroundTaskBar 行（task island 同构）vs 独立横幅（ProjectReadOnlyBannerView 先例）vs 两处并存 | bar 行 / banner / 双面 | **bar 行**——Alcedo AU14「零 banner 零新通道」裁示同构；banner 只留 M6-1 只读面 |
| **OQ-M7-5-6** | registry 演进深度：pinned+activity+dismiss+resume 全套（Alcedo 形）vs 最小面（activity 折叠进 detail 字符串，无逐条列表） | 全套 vs 最小 | **全套**——TURN-03 resume 活动连续性依赖逐条活动；KD-7「腿需要更多就演进协议」此刻是真实需求非投机 |
| **OQ-M7-5-7** | acquire 等未封合输入：等待轮询（Alcedo 同构，McpTimeouts 新档兜底）vs 立即拒（-32005 族） | 等待 10s vs 立即拒 | **等待**——用户拖滑杆是秒级常态，立即拒会把 agent 打进无谓重试环；新档 `controlAcquire .seconds(10)` |
| **OQ-M7-5-8** | get_state 扩展形态：`control.agent` 子对象 vs 平铺三键（controlHeld/controlHolder/controlRevokedByUser） | 子对象 vs 平铺 | **子对象**——与 Alcedo state.get「control 状态对象」同构；既有三键零触碰 |
| **OQ-M7-5-9** | Stop 入口：任务卡 cancel 钮单入口 vs 加菜单命令（编辑器菜单「停止 agent」） | 卡单入口 vs 双入口 | **卡单入口**——Alcedo `7e0c9cb` 正是「Remove Return control、Stop 从任务卡」；双入口=第二真相 |
| **OQ-M7-5-10** | read-only HTTP 宿主 control 工具注册：照常注册（恒真面）vs 不注册（union 计数分宿主分叉） | 注册 vs 不注册 | **注册**——union 快照单值纪律（所有宿主同 32 面）；写权仍由 requiresWriter 门仲裁，控制态与写权正交如实呈现 |

**登记申报（非 OQ）**：①无通知通道（§1.8 偏离）；②无 GUI 选区类工具（无 -32001/not_ready 新码——`notSessionMember` 为对表物）；③S-2 路由二选一（本波让渡下一 Export 波均可，须显式申报）。

---

## 7. 红线与许可

- **Alcedo GPL-3.0**：功能行为/命令语义/错误码档位克隆合法（survey §6）；**代码与文档文案零复制零翻译**——错误文案、卡面文案、工具 description 全部自写。
- **零新 SPM 依赖**维持；`Project.swift` 仅测试登记行 additive（如需）。
- **快照串行**：本波持 union 改动权（`McpFinalSnapshotTests.swift` 显式改），M7-6 禁并行——orchestrator 编排保证。
- **FIX2③**：`LibraryProjectController` 零 diff 第四波维持（GUI 门加调用点视图层）。
- **runModal 禁入产线**（L057）：活动卡/对话框全走 SwiftUI 呈现缝。
- **资源监控**：全套轮 orchestrator 批准 + 8G 门机检（MEMFAIL 兜底）；定向 bundle 常跑。

## Sources

- Alcedo 本地仓（HEAD `6024386`）：`alcedo_studio/src/include/ui/alcedo_main/automation/automation_control_commands.hpp:15-27`；`automation/commands/control_commands.cpp`（ControlStateSchema/StoppedRefusal/AcquireHandler 三拒形/MakeAgentStateChangeControl admit/Register 三命令 description）；`alcedo_studio/src/include/ui/alcedo_main/album_backend/agent_control_owner.hpp`（状态机 + Stop/resume + activity + UserStateChange 锁注释块）；`album_backend/background_task_controller.hpp`（BackgroundTaskKind.AgentControl/InteractionCapability.UserStateChange/pinned/activity/ResumeTask/DismissTask）；commits `a6c8848`（AU14）/ `7e0c9cb`（钉住+Stop+活动）/ `c7ba784`（scopes 保活，含 EditorScopeController/EditorScopePanel.qml diff）；`docs/roadmap/alcedo_studio/automation/cli_mcp_automation_plan.md` §2.8（agent control + 禁编辑清单 + acquire 成功条件）/ §2.6 表注（headless selection not_ready）。
- 我方：`LightamerCore/Sources/Foundation/SingleWriterLock.swift`；`App/Sources/Lightamer/MCP/McpToolRegistry.swift`（:130 verdict / :281-354 registry 两道门 / 错误码表 16 档）；`App/Sources/Lightamer/MCP/McpServerController.swift`（:150-160 probe / :207-311 无头盒+context / :807-829 makeRegistry）；`App/Sources/Lightamer/MCP/Tools/SearchStateToolset.swift`（:1046-1101 get_state control 面）；`App/Sources/Lightamer/MCP/Tools/{Editing,Culling,Project,MatchColor}Toolset.swift`（requiresWriter 注册点位）；`App/Sources/Lightamer/Library/BackgroundTaskHosting.swift`（registry/handle 全文）；`App/Sources/Lightamer/UI/Shell/BackgroundTaskBarView.swift`（双呈现面）；`App/Sources/Lightamer/UI/Shell/{ScopePanelView,WorkspaceHostView,EditorWorkspaceShellView}.swift`（scopes 门 / 只读先例 / scopes 槽位）；`App/Sources/Lightamer/State/PipeCoordinator.swift`（:2134-2167 scope 门+节流）；`App/Sources/Lightamer/UI/LightamerApp.swift`（:1428-1612 GUI MCP 装配 / :1600 菜单 disabled 先例）；`Tests/LightamerTests/McpFinalSnapshotTests.swift`（union 29 全点位）。
- 台账：`REQUIREMENTS.md` :445-448；`ROADMAP.md` :109；`research/ALCEDO-CLI-AI-SURVEY.md` §1.2/§5/§7；`phases/m7-4-mcp-o4/M7-4-VALIDATION.md` §挂账；AGENTS.md M7-2/M7-3/M7-4 架构增量节。

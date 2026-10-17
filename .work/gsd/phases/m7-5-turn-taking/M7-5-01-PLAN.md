---
phase: m7-5-turn-taking
plan: "M7-5-01"
title: "MCP 块二 GUI agent turn-taking 单 plan——T1 ControlToolset 第五域 3 工具（control_acquire/release/get）+ requiresControl 第三道门（13 工具候选集）+ 错误码 16→19 + McpTimeouts.controlAcquire 新档申报 / T2 AgentControlCoordinator 单写点 + GUI 禁编辑 12 面 disable-not-unmount + get_state control.agent 子对象 / T3 活动卡（BackgroundTaskBar 底栏行 + AgentTaskHandle pinned/activity/dismiss/resume 演进 + 既有三腿负测零漂移）+ Stop→ResumeTask 语义 / T4 无头恒真面 + read-only 宿主照常注册 + scopes 保活三纪律 / T5 M7-4 顺路件（S-1 四处注释 + S-2 让渡申报 + S-3 预热首调实测 + S-4 第四波注记 + S-5 无动作申报）/ T6 测试批（union 29→32 全点位显式改 + 新工具 golden + 13 工具拒面 + acquire 等待/超时/Stop 三态 + 无头恒持有负测）/ T7 定向轮 + 全套 --all（批准制）+ 红线族 + 收口翻账"
wave: 1
depends_on: []
autonomous: true
requirements: ["REQUIREMENTS TURN-01..04（:445-448，→ M7-5）+ ROADMAP §M7-5 行（验收形态四条：双端 fixture〔agent 持锁 GUI typed 拒 + 用户夺回 agent 失权〕/ GUI 活动卡走查 / Stop→resume 活动连续 fixture / 无头恒持有负测）", "OQ 裁决正本 = phases/m7-5-turn-taking/M7-5-CONTEXT.md（D-M7-5-1..10 全按 RESEARCH §6 推荐，站 charter 授权落定，晨审可推翻）+ S-2 路由显式申报（让渡下一 Export 波）", "调研正本 = phases/m7-5-turn-taking/M7-5-RESEARCH.md（§1 Alcedo AU14 全语义面 / §2 底座差距测绘 / §3 TURN 落点表 / §4 顺路件 / §5 测试策略；file:line 经 planner 2026-10-17 HEAD cbad16eb 逐点亲核复核吻合——fresh 坐标勘正随 CONTEXT 头注）", "M7-4 挂账单一清单 = phases/m7-4-mcp-o4/M7-4-VALIDATION.md §挂账（S-1..S-5 本波 T5 路由；FIX2③ 维持）", "夜间全自动授权在案（先例 D-07-3-T5-1；晨审可推翻）"]
success_criteria: "SC 全可机检——T1：McpToolError 恰 +3 case（controlNotHeld/controlRevokedByUser/controlBusy，:62-85 段 additive）+ code switch 恰 +3 臂 + Entry 恰 +1 字段 requiresControl（缺省 false——既有注册零 diff）+ register 恰 +1 参数 + setControlAdmit seam 在位（grep）+ dispatch 序 = writerCheck → controlAdmit → handler（diff 面核——writeCallCount 仍只挂 writer 门）+ McpTimeouts 恰 +1 行 controlAcquire = .seconds(10)（既有八档值零改——diff 面核）+ ControlToolset.swift 新文件三工具注册（control_acquire holder_name? 缺省 \"agent\" / control_release / control_get readOnlyHint:true；三工具 requiresControl 零显式——grep）+ makeRegistry 恰第五参 control:（缺省 nil——四参既有调用编译零改）+ 四宿主缝 additive 透传（startReadOnlyHTTPHost :686 / startHeadlessStdioHost :749 / startHTTPHost :988 / startEmbeddedIfPreferenceEnabled :1089→startEmbeddedServer :1111 EmbeddedState box control 字段第六缝）+ 13 工具注册点恰 +requiresControl: true 各一行（editing 4 :279/:366/:538/:809 + culling 6〔metadata write face 五件 + apply_preset :518〕+ match 1 :59 + project 2 :141/:204）+ 构建绿；T2：AgentControlCoordinator.swift 新文件（@MainActor @Observable；状态面 held/stoppedByUser/holderName/taskId/activity + holdsControl 派生；单写点 API acquire/stop/release/resume/admit/beginCommand 边界）+ PipeCoordinator 恰 additive liveEditDepth 计数（beginContinuousEdit :1771/commitContinuousEdit :1815 两点配对增减——两点外零触）+ get_state control 对象恰 +1 键 agent（SearchStateToolset :1053-1076 段 additive；既有三键 lock/holder/writeCallCount 值与形零漂移；nil provider → .null）+ McpSearchStateContext 恰 +1 optional provider + GUI 装配（LightamerApp MCP 段 MainActor.run hop——liveState 同款纪律）+ 禁编辑 12 面落点 diff 面核（逐点 `.disabled(readOnly || agentHeld)` 合并形——research §2.4 表为落点正本；`if !` + 条件卸载形态零命中）+ LibraryProjectController.swift 零 diff（FIX2③ 第四波）+ 构建绿；T3：BackgroundTaskHandle 协议 additive isPinned（extension 默认 false）+ registry additive dismiss(id:) + AgentTaskHandle（isPinned=true + activity 面板）+ Stop 语义（stop → 终态 Canceled + 控制回用户 + stoppedHolderName 记忆 + in-flight 活动闭 interrupted）+ 同 holder resume 同 id 回 Running + 活动卡 bar 行 + 对话框活动列表 + AX 标识 + 既有三腿 finish 即移除语义零漂移（负测 T6）+ 构建绿；T4：makeHeadlessControlContext 常量面（acquire/release 直答 {held:true, revokedByUser:false, holder:\"\"}）+ 无头臂 admit nil = 恒放行（writerCheck nil 同形）+ runHeadless :451 两臂 + runHeadlessArbitrated :512 + stdio :749 + http :988 + readonly :686 五宿主接 control context + EmbeddedState box 第六缝 + read-only 宿主注册面（union 单值纪律承载）+ scopes 保活三纪律 grep 断言（AgentControlCoordinator 内 setScopeTapEnabled|scopesVisible|ScopeThrottle 零命中；WorkspaceModel.scopesVisible 写者面 diff 零触）+ 构建绿；T5：S-1 四处注释清零（McpHostTests :466/:668 + McpSearchStateToolsetTests :16/:265——grep \"21-tool face\"/\"count rides 21\" 零命中）+ S-3 计时数据落 evidence/s3-preheat-first-call.log + S-2/S-4/S-5 申报句在 T7 DECISIONS；T6：union 显式改全点位亲核——冻结表 +controlTools 域数组三行（名序 control_acquire/control_get/control_release——descriptors() 名序）+ 计数断言 ×4（:275/:328/:356/:510）29→32 + all29→all32（:245 定义 + :273 引用）+ 组合代数五集合并 + 域两两 disjoint 断言 +4（control×{editing,culling,searchState,project}）+ descriptionKeys +3 + destructive 十件集断言零改（control 三工具全非 destructive——集恒等维持）+ makeUnionRegistry 传 control fixture context + 测试名 Union29→Union32 + 头注 :15/:20/:25/:268 过时注释同批清零（S-1 余下坐标）+ 穷举测试 16→19 同批（testMcpToolErrorCodesSixteenValuesExhaustive → Nineteen + errors/expected 数组 +3）+ get_state golden 显式改（恰 +1 键 agent——nil provider 面 .null）+ McpControlToolsetTests 新文件（域快照三工具 verbatim + 域计数 32 分账 + 白名单负测 + requiresControl/readOnlyHint 注解断言 + admit 三拒面〔not held → controlNotHeld / stopped → controlRevokedByUser / acquire 异 holder → controlBusy 携 holder〕+ acquire 三态〔未封合挂起→封合即得 / 注入短窗超时→controlBusy 携未封合语义 / Stop 中断〕+ 无头恒持有负测〔写工具免 acquire 直答 + control_acquire 恒 held + admit 无头臂恒放行〕+ read-only 宿主 control 注册臂）+ AgentControlCoordinatorTests 新文件（状态机全序 acquire→活动条目→Stop→拒→同 holder resume 活动连续→release 终态→dismiss + 异 holder busy + stoppedByUser 清除语义 + activity 边界闭形〔下次 admit/release/stop 闭 in-flight〕+ pinned/dismiss 三腿负测〔import/export/AI finish 即移除不变〕+ 禁编辑点位结构断言〔holdsControl 求值 + 12 面 grep 面〕+ scopes 保活负测〔控制态翻转不触 scope 面——coordinator 零 scope 引用 grep + holdsControl 翻转无 scope 副作用断言〕）+ Project.swift 恰两行 + BUNDLE-MAP 恰两行 + tuist generate 恒末位 + --bundle APP 全绿（红窗闭合点）+ 残漏 grep（count, 29 / count == 29 / all29 在 MCP 测试面零命中）；T7：--bundle App 定向轮绿 + 全套 --all = TOTAL|3925+ΔN/35/0| 对账精确闭合（exit 0 / 0 MEMFAIL / 七 bundle 8G 门内——批准制）+ 红线族逐条机检 PASS + zh-audit --check PASS（10 新键 +3 desc +3 error +4 卡面）+ --self-test PASS + 四台账同批落盘"
estimated_tests: "+14..22（research §0 带；T6 批承载——McpControlToolsetTests ~10..13〔域快照 + admit 三拒 + acquire 三态 + 无头负测 + get_state agent 腿〕+ AgentControlCoordinatorTests ~8..12〔状态机 + 活动边界 + pinned/dismiss/resume + 三腿负测 + 禁编辑/scopes 结构〕；union 显式改/穷举 16→19/golden 显式改 = 零新法口径；执行时逐任务如实记账，越带申报）"
test_bundles: [APP]
baseline: "3925/35/0（M7-4 三路全套同值；其后 cbad16eb〔M7-5 research docs〕docs-only 零漂移；HEAD cbad16eb planner 2026-10-17 亲核 git log/status——其上零产线文件）"
expected_all: "3925 + ΔN（对账式；ΔN 预期带 +14..22 → 终值带 3939..3947，执行时按实记账；skip 35 口径维持——第三种 skip 来源 = 逐族差分申报禁静默吸收）"
red_lines:
  - "union 29→32 显式取权（本波持权——M7-4 移交）：McpFinalSnapshotTests.swift 全点位显式改（冻结表 + 计数 ×4 + all32 改名 + 组合代数五集合并 + descriptionKeys +3 + makeUnionRegistry fixture + 测试名 + 头注）——快照改动全部走「显式改 + DECISIONS 申报」形禁静默；五钉 23 不变（editing 9 + culling 14——控制域独立新增不触两域：McpRegistrySnapshotTests :223 / McpHostTests :243/:697 / McpLauncherTests :200 / McpSearchStateToolsetTests :274 零触）；残漏 grep（count, 29 / count == 29 / all29 在 Tests/LightamerTests/Mcp* 零命中）；本波持权窗口内禁并行派发 M7-6（orchestrator 编排保证——若误并行派发立即停手上报，禁抢先合并快照表）"
  - "零新 SPM 依赖（Project.swift dependencies 块零 diff；Project.swift 仅测试登记行恰两行 additive）"
  - "既有 29 工具 descriptor/handler 零 diff——requiresControl 为 registry Entry 字段 additive（descriptor 面 = McpToolDescriptor 结构零新字段；readOnlyHint/destructiveHint/idempotentHint/schema/description 零触碰）；controlAdmit 不增 writeCallCount（计数仍只挂 writer 门——M6-1 写权计数语义零变）；union 外五钉 23 断言零触"
  - "错误码 16→19 additive（本波持权申报——M7-2 modelUnavailable 15→16 先例第三行使）；穷举测试同批显式改；McpTimeouts 恰 additive 一档 controlAcquire .seconds(10)（既有八档值零改零触——历史「零新档」红线本波显式申报勘误：M7-2/M7-3/M7-4 三波零 diff 后首开新档，additive 非 fix，CONTEXT D-M7-5-7 正本）；get_state 既有三键 lock/holder/writeCallCount 值与形零漂移（agent 为恰 +1 additive 键，nil provider → .null 诚实面）"
  - "GUI 既有三腿（import/export/AI）零漂移：BackgroundTaskHandle.isPinned 走 extension 默认 false（既有 conformer 零改）；finish 即移除语义不变（负测钉）；pinned 只对 AgentTaskHandle 生效；WorkspaceModel.scopesVisible 单源（View 菜单开关唯一写者——agent 状态机零触碰）；ScopeThrottle 零触（已测纯函数零 diff）；disable-not-unmount（禁编辑一律 .disabled() 容器层合并形——`if !agentHeld` 条件卸载形态禁入；scopes 保活结构性前提，Alcedo c7ba784 病根移植禁令）"
  - "LibraryProjectController.swift 文件零 diff（FIX2③ 第四波维持——project open/create/close 门加调用点视图层；行使须显式申报）"
  - "封存面零触：DrtRecord / TerminalTailPolicy / DrtTailAssembly / PixelPipe / Lut3dKernels.metal / DrtEotf / ExportQueueContract / 六格式导出矩阵（ExportFormatSpec·ImageIOEncoders·WebPEncoder）/ NodeGraphCommand / sidecar schema（LightamerSidecar）/ HistoryStack / HistoryHash / PipelineDocument（Core）/ V50Order / GradeCatalog（NodeOwnershipCatalog）/ Registry / ModuleInstance；零新 .metal（全域零 diff）；PipeCoordinator 仅 additive liveEditDepth 计数一处（begin/commit 两点配对——其余函数体零触）"
  - "Alcedo GPL-3.0 代码/文档文案零复制零翻译——错误文案、卡面文案、工具 description 全部自写；只对表命令语义/状态机语义/错误码档位（automation_control_commands.hpp / control_commands.cpp / agent_control_owner.hpp / background_task_controller.hpp 只读对表）"
  - "AgentControlCoordinator 单写点：control 状态（held/stoppedByUser/holderName/taskId/activity）只有 coordinator 写——GUI 面/活动卡/get_state 全读投影（第二写点禁入）；与 M6-1 SingleWriterLock/LibraryProjectController 零耦合（会话内控制权与跨进程项目写权正交两层——不触锁面不合并不改）；PipeCoordinator 引用只经注入 provider（可测缝）"
  - "xcstrings 恰 10 键尾块纯插入（mcp_tool_desc_control_acquire/_control_release/_control_get + mcp_error_control_not_held/_control_revoked_by_user/_control_busy + tasks_agent_kind/agent_card_waiting/tasks_agent_stop/tasks_dismiss——历史键字节与顺序零触碰）；UserDefaults 零新键；执行中如需更多键 = 同纪律 + DECISIONS 申报"
  - "\\.runModal( 在 App/Sources 零命中（L057 禁令——活动卡/对话框全走 SwiftUI 呈现缝）；LocalizationValue 插值禁形代码零命中（新键一律 String(localized: 静态键, defaultValue:) 显式形态——禁 String.LocalizationValue(\"prefix_\\(x)\" 插值形，M2-9 F-2 禁令）"
  - "构建 caffeinate -dis 包裹；单测 = Scripts/test-direct.sh --bundle <域>；全套 --all orchestrator 批准制（本 plan 标注批准制，执行时 orchestrator 派发 prompt 即批准）+ 8G 门 + MEMFAIL 机检 + 运行中保持监视（AGENTS 资源监控节）；测试宿主清理先核 parentage（ps -o ppid，M2-7-3 先例——测试宿主 parent = 脚本进程树，GUI 实例 parent = launchd）"
files_modified:
  - App/Sources/Lightamer/MCP/Tools/ControlToolset.swift                      # T1 新建：McpControlContext（acquire/release/state provider closure optional 缺省 nil + admit 不入 context——admit 走 registry seam）+ McpControlState 值类型 {held, revokedByUser, holder}（heldConstant() 无头常量 + Sendable + Equatable）+ McpControlToolset.registerAll 三工具——control_acquire（holder_name? string 缺省 "agent" → 状态对象）/ control_release（幂等零动作臂）/ control_get（readOnlyHint: true）；三工具 requiresControl 缺省（免 admit）；超时 controlAcquire（acquire 臂）/ list（release/get 臂）；description 走 xcstrings 三键
  - App/Sources/Lightamer/MCP/McpToolRegistry.swift                           # T1：McpToolError 恰 +3 case（controlNotHeld/controlRevokedByUser/controlBusy——:62-85 段 additive）+ code switch +3 臂；Entry 恰 +1 字段 requiresControl（缺省 false）；register 恰 +1 参数 requiresControl: Bool = false；setControlAdmit(_ admit: (@Sendable (_ toolName: String) async throws -> Void)?) seam（形同 setWriterCheck）；dispatch :331-355 段恰 +1 门（writerCheck 之后 handler 之前：if entry.requiresControl, let controlAdmit → try await controlAdmit(name)——writeCallCount 面零触）；McpTimeouts 恰 +1 行 controlAcquire: Duration = .seconds(10)（:208-225 段 additive；既有八档零触）
  - App/Sources/Lightamer/MCP/Tools/EditingToolset.swift                      # T1：requiresControl: true 恰四处（load_image :279 / export_image :366 / apply_params :538 / paste_adjustments :809——register 调用点各一行，descriptor/handler 体零触）
  - App/Sources/Lightamer/MCP/Tools/CullingToolset.swift                      # T1：requiresControl: true 恰六处（metadata write face 注册批 set_rating/set_flag/set_color_label/append_note/set_keywords + apply_preset :518——descriptor/handler 体零触）
  - App/Sources/Lightamer/MCP/Tools/MatchColorToolset.swift                   # T1：requiresControl: true 恰一处（match_color :59）
  - App/Sources/Lightamer/MCP/Tools/ProjectToolset.swift                      # T1：requiresControl: true 恰两处（project_open :141 / project_create :204——list_versions 零触）
  - App/Sources/Lightamer/MCP/McpServerController.swift                       # T1：makeRegistry :807 恰第五参 control: McpControlContext? = nil（缺省 nil = 既有构造零 diff）+ 四宿主缝 additive 透传（startReadOnlyHTTPHost :686 / startHeadlessStdioHost :749 / startHTTPHost :988 / startEmbeddedIfPreferenceEnabled :1089 + EmbeddedState box control 字段——startEmbeddedServer :1111 on-leg 读出透传，第六缝）。T4：makeHeadlessControlContext 常量面（acquire/release 直答 heldConstant + admit 不设 = 恒放行）+ runHeadless :451 两臂（:463-464/:475-476）+ runHeadlessArbitrated :512（:579-581）+ stdio/http/readonly 三宿主接 control context + makeHeadlessSearchState 恰 +1 additive 参（agentControl 常量 provider——get_state 无头臂）+ read-only 宿主照常注册（union 单值纪律）
  - App/Sources/Lightamer/MCP/Tools/SearchStateToolset.swift                  # T2：get_state control 面 :1053-1076 恰 +1 键 "agent"（provider nil → .null；有值 → {held, revokedByUser, holder} 子对象——既有三键 lock/holder/writeCallCount 值与形零漂移）；McpSearchStateContext 恰 +1 optional provider agentControl: (@Sendable () async -> McpControlState?)? = nil（缺省 nil = 既有构造零 diff）
  - App/Sources/Lightamer/State/AgentControlCoordinator.swift                 # T2/T3 新建：@MainActor @Observable 单写点——状态 held/stoppedByUser/holderName/taskId/activity[AgentActivityEntry]/holdsControl 派生；API = admit(toolName:)（throw controlNotHeld/controlRevokedByUser + 成功即登记活动条目置 in-flight）/ acquire(holderName:)（异 holder → controlBusy；未封合输入 → 挂起轮询 + 注入超时缺省 McpTimeouts.controlAcquire；成功 → 同 holder resume 同 id / 异 holder 新任务 / stoppedByUser 清除）/ release（幂等 + 终态收尾）/ stop（终态 Canceled + 控制回用户 + stoppedHolderName 记忆 + in-flight 闭 interrupted）/ resume 路由（同 id 回 Running）；AgentTaskHandle: BackgroundTaskHandle（isPinned = true + activity 投影 + cancel → stop）；liveEditActive: () -> Bool 注入 provider；scoped 依赖零引用（setScopeTapEnabled/scopesVisible/ScopeThrottle 零命中——红线⑤负测面）
  - App/Sources/Lightamer/State/PipeCoordinator.swift                         # T2：恰 additive liveEditDepth 私有计数 + 只读访问器（beginContinuousEdit :1771 / commitContinuousEdit :1815 两点配对增减——两点外函数体零触；scope 门/节流面零触）
  - App/Sources/Lightamer/UI/LightamerApp.swift                               # T2：GUI MCP 装配段（:1268-1390 同段）control context 装配（MainActor.run hop 到 coordinator——liveState 同款纪律 + F-6 结构纪律）+ searchState context agentControl provider（同段 hop）+ MenuCommandSet undo/redo/history 命令项 disabled 合并形（:1600 菜单 disabled 先例形）；T4：GUI 内嵌臂（EmbeddedState 路径）control context = coordinator-backed（非恒真面）
  - App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift                    # T2：禁编辑点位——topbar export/yiyin 钮 :625/:638 合并形（readOnly || agentHeld）+ 调整栈容器宿主点位（执行时 grep 亲点）
  - App/Sources/Lightamer/UI/Shell/EditorWorkspaceShellView.swift             # T2：禁编辑点位——EditorAdjustmentStackView 宿主列 :171 + 页宿主分支（Drt/Film/RawDecode 页列）合并 disabled
  - App/Sources/Lightamer/UI/Shell/EditorAdjustmentStackView.swift            # T2：禁编辑点位——面板栈容器层合并 disabled（容器级一处，非逐面板散点）
  - App/Sources/Lightamer/UI/Shell/EditorToolRailView.swift                   # T2：禁编辑点位——viewport 工具列 + 历史列表合并 disabled
  - App/Sources/Lightamer/UI/Shell/Nodes/EditorNodesPanelView.swift           # T2：禁编辑点位——节点画布/蒙版编辑面合并 disabled（NodeCanvasGeometry 零触——纯函数几何面）
  - App/Sources/Lightamer/UI/Shell/FilmstripView.swift                        # T2：禁编辑点位——editor 切图条合并 disabled
  - App/Sources/Lightamer/UI/Shell/VersionsPanelView.swift                    # T2：禁编辑点位——版本 mutation/checkout 控件合并 disabled
  - App/Sources/Lightamer/UI/Shell/MenuCommandSet.swift                       # T2：禁编辑点位——undo/redo/history head 命令项 disabled 合并形
  - App/Sources/Lightamer/Library/ImportModeDialog.swift                      # T2：禁编辑点位——confirm 入口合并 disabled（ImportTaskAdapter/ImportService 零触）
  - App/Sources/Lightamer/Library/Views/LibraryGridView.swift                 # T2：禁编辑点位——图库删除路由控件合并 disabled
  - App/Sources/Lightamer/Library/Views/LibraryInspectorView.swift            # T2：禁编辑点位——图库评分控件合并 disabled
  - App/Sources/Lightamer/Library/BackgroundTaskHosting.swift                 # T3：BackgroundTaskHandle 协议 additive isPinned: Bool（extension 默认 false——既有 conformer 零改）+ registry additive dismiss(id:)（pinned 显式除名）；finish(:89)/cancel(:94)/cancelAll(:101) 语义零触
  - App/Sources/Lightamer/UI/Shell/BackgroundTaskBarView.swift                # T3：活动卡底栏行（Agent · holder · 命令 summary + indeterminate + cancel 钮 = Stop 路由）+ 终态 pinned 行 dismiss 钮 + 对话框活动列表行集（summary/result 逐条）+ AX 标识（tasks.bar/dialog agent 行族）——既有 import/export/AI 行渲染面零漂移（descriptor 投影 additive）
  - Resources/Localizable.xcstrings                                           # T1/T2/T3：恰 10 键尾块纯插入（mcp_tool_desc_control_acquire/_control_release/_control_get + mcp_error_control_not_held/_control_revoked_by_user/_control_busy + tasks_agent_kind/agent_card_waiting/tasks_agent_stop/tasks_dismiss——zh-only 形；历史键字节与顺序零触碰）
  - Tests/LightamerTests/McpControlToolsetTests.swift                         # T6 新建：control 域快照层（三工具 name/description/schema verbatim + 域计数 32 分账 + 白名单负测 + requiresControl/readOnlyHint 注解断言）+ admit 三拒面 + acquire 三态（等待/短窗超时/Stop 中断——超时参数注入短窗）+ 无头恒持有负测 + read-only 宿主注册臂 + get_state agent 腿（nil → .null / 真值子对象）
  - Tests/LightamerTests/AgentControlCoordinatorTests.swift                   # T6 新建：coordinator 状态机全序（acquire→活动条目→Stop→拒→同 holder resume 活动连续→release 终态→dismiss + 异 holder busy + stoppedByUser 清除）+ activity 边界闭形 + pinned/dismiss 三腿负测（import/export/AI finish 即移除不变）+ holdsControl 派生面 + 禁编辑点位结构断言（12 面 grep 面 + holdsControl 求值）+ scopes 保活负测（coordinator 零 scope 引用 grep + 翻转无 scope 副作用）
  - Tests/LightamerTests/McpFinalSnapshotTests.swift                          # T6：union 显式改 29→32 全点位——冻结表 +controlTools 域数组（:54 段后新三行——名序 control_acquire/control_get/control_release）+ all29→all32（:245 定义 + :273 引用）+ makeUnionRegistry（:251）+ control fixture context 参 + testFinalSnapshotUnion29Verbatim→Union32Verbatim（:270）+ 计数 ×4（:275/:328/:356/:510）29→32 + 组合代数五集合并（:318 段）+ 域两两 disjoint +4（:311-316 段）+ destructive 十件集断言零改（message 可注 control 免 admit 句——集恒等）+ descriptionKeys +3（:363）+ 头注 :14-34 改写（M7-5 条目 + Snapshot layers +1 行）+ :268 "exactly these 27" 清零（S-1 余下坐标——同 commit）
  - Tests/LightamerTests/McpSearchStateToolsetTests.swift                     # T5：S-1 注释 :16/:265 清零（注释批 commit）。T6：穷举测试 :1023 16→19 同批显式改（法名 Nineteen + errors/expected 数组 +3 + count 断言）+ get_state golden 恰 +1 键 agent 显式改（nil provider 面 .null——DECISIONS 申报）+ get_state agent 真值腿（provider 注入）
  - Tests/LightamerTests/McpHostTests.swift                                   # T5：S-1 注释 :466/:668 清零（"21-tool face" 过时形改写——注释批 commit；:243/:697 计数断言 23 零触）
  - Project.swift                                                             # T6：恰两行测试登记（McpControlToolsetTests + AgentControlCoordinatorTests → LightamerTestsApp 数组；tuist generate 恒末位）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt                # T6：恰两行（APP 域）
  - .work/gsd/phases/m7-5-turn-taking/evidence/s3-preheat-first-call.log      # T5：S-3 预热后 stdio 首调计时数据（对照 M7-3 冷窗正本 50.2s）
  - .work/gui-acceptance/m7-5/MANIFEST.md                                     # T7：GUI 走查配方（活动卡行面 + Stop→resume + 禁编辑 12 面实机走查行 + 遮挡态 scopes/viewport 观感行 + S-3 计时行引用——实机走查归验收批）
  - .work/gsd/phases/m7-5-turn-taking/M7-5-01-SUMMARY.md                      # T7：执行摘要（逐任务 ΔN 记账 + 四验收形态判定指针 + union 显式改申报 + 中间红窗申报〔T1..T6 App bundle 穷举/get_state 两面红——构建绿门维持〕）
  - .work/gsd/phases/m7-5-turn-taking/M7-5-01-DECISIONS.md                    # T7：裁定记录（错误码 16→19 + McpTimeouts 新档勘误申报〔D-M7-5-7 承接〕+ union 全点位清单 + get_state golden 显式改申报 + activity 边界闭形终形 + 无通知通道偏离 + 无 GUI 选区工具申报 + S-2 让渡/S-4 第四波/S-5 无动作申报 + 禁编辑点位终清单 + acquire 超时注入终形）
  - AGENTS.md                                                                 # T7：「M7-5 架构增量」节（turn-taking 三面语义 + coordinator 单写点 + requiresControl 门 + 快照权移交 M7-6 注记 + ΔN 终值）
  - .work/TODO.md                                                             # T7：M7-5 条目翻账（M7-4 挂账 S-1/S-3 收口 + S-2 让渡/S-4 维持/S-5 无动作申报 + FIX2③ M7-6 维持）
  - .work/GOAL-STATE.md                                                       # T7：续接点翻新（M7-5 收口 → next = 验收/VALIDATION + M7-6〔union 改动权移交 M7-6——串行禁并行注记延续〕）
  - .work/gsd/REQUIREMENTS.md                                                 # T7：TURN-01..04 翻账（Delivered + M7-5 commit 指针）
---

# Plan M7-5-01 — GUI agent turn-taking（ControlToolset 第五域 + requiresControl 第三道门 + AgentControlCoordinator + 活动卡 + Stop/resume + 无头恒持有 + union 29→32）

> **夜间全自动授权**（先例 D-07-3-T5-1；晨审可推翻）。裁决正本 =
> `M7-5-CONTEXT.md`（D-M7-5-1..10 全按 RESEARCH §6 推荐——站 charter 授权
> 落定 + S-2 路由让渡显式申报）；规格正本 = `M7-5-RESEARCH.md`（§1 Alcedo
> AU14 全语义面 / §2 底座差距测绘 / §3 TURN 落点表 / §4 顺路件 / §5 测试
> 策略；file:line 经 planner 2026-10-17 HEAD `cbad16eb` 逐点亲核复核吻合，
> fresh 坐标勘正清单见 CONTEXT 头注）。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（三工具 additive + 一道门 + 一
> coordinator + 活动卡演进——既有 29 工具行为面零变化由 T6 快照零 diff 门
> 钉死，除 union 显式改申报内字节与 get_state additive 键）。执行中如触
> 「必须扩面」（第四新错误码 / controlAcquire 档值改非增 / requiresControl
> 候选集越出 13 / 禁编辑面越出全表）= 停手上报，不得自裁扩界。
>
> **执行序**：T1 → T2 → T3 → T4 → T5 → T6 → T7。T1-T5 产线码/注释批
> （每任务独立 commit + 构建绿机检；App bundle 快照红窗见「风险与回退」
> 第 1 条——穷举 16→19 与 get_state golden 两面红至 T6），T6 测试批一次
> 落位，T7 轮次 + 收口。每任务独立 commit（Conventional Commits，全英文，
> 只 add 相关文件，不 push）。
>
> **基线**：**3925/35/0**（M7-4 三路全套同值；其后 cbad16eb docs-only 零
> 漂移；HEAD `cbad16eb`）。全套预期 `3925+ΔN/35/0|`（ΔN 预期带 +14..22，
> 对账式 → 终值带 3939..3947）。
>
> **快照改动权**：本波持 union 文件改动权（M7-4 VALIDATION 移交）——
> M7-6 禁并行（orchestrator 编排保证；若误并行派发 M7-6 立即停手上报）。

## 已定裁决（生效值，硬约束，不得重开）

OQ-M7-5-1..10 **全部按 RESEARCH §6 推荐裁**（CONTEXT D-M7-5-1..10）。本单
plan 承载全部十项；执行面速查：

1. **三码镜像 16→19**（OQ-1）：`controlNotHeld` / `controlRevokedByUser` /
   `controlBusy` ≙ Alcedo -32003/-32004/-32005；文案自写；穷举测试同批。
2. **独立第五域 ControlToolset**（OQ-2）：新文件 + `McpControlContext` 全
   provider 缺省 nil（union fixture 全 nil 即注册）；union 32。
3. **requiresControl 13 全集**（OQ-3）：Entry 第三字段 + `setControlAdmit`
   seam（形同 writerCheck；dispatch 序 writer → control → handler）；控制
   三命令自身免 admit；writeCallCount 零波及。
4. **禁编辑全表 12 面**（OQ-4）：与 isReadOnly 同点位合并
   `.disabled(readOnly || agentHeld)`；disable-not-unmount（条件卸载禁入）；
   controller 文件零 diff（FIX2③ 第四波）。
5. **活动卡宿主 = bar 行**（OQ-5）：零 banner 零新通道；banner 只留 M6-1
   只读面。
6. **registry 演进全套**（OQ-6）：isPinned（extension 默认 false）+
   activity 逐条 + dismiss(id:) + resume = coordinator 同 id 回 Running；
   既有三腿零漂移负测钉。
7. **acquire 等待 + controlAcquire 10s 新档**（OQ-7）：未封合输入挂起轮询
   + 新档兜底超时 → controlBusy（携未封合语义）；McpTimeouts 零改档
   additive 申报；测试传注入短窗。
8. **get_state control.agent 子对象**（OQ-8）：恰 +1 additive 键；既有三键
   零漂移；nil provider → .null。
9. **Stop 卡单入口**（OQ-9）：卡 cancel = Stop；同 holder re-acquire =
   ResumeTask 活动连续；异 holder Stop 后合法新建；stoppedByUser 任一
   acquire 清除。
10. **read-only 宿主照常注册**（OQ-10）：union 单值纪律；写仍被 writer 门
    前置拒；四宿主缝 + EmbeddedState 第六缝。

**登记申报（非 OQ，随批进 DECISIONS）**：①无通知通道（轮询替代）；
②无 GUI 选区类工具（零 -32001 新码）；③S-2 让渡下一 Export 波（CONTEXT
顺路件表正本）；④McpTimeouts 历史零新档红线勘误（additive 一档申报）。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/m7-5-turn-taking/M7-5-CONTEXT.md`（D-M7-5-1..10 裁决 +
  顺路件路由表 + 红线摘要 + fresh 坐标勘正清单）
- `.work/gsd/phases/m7-5-turn-taking/M7-5-RESEARCH.md` §1（Alcedo 三层同心
  语义——acquire 三拒形/admit 三臂/owner 状态机/活动卡字段/scopes 病理）+
  §2.3（MCP 工具面设计）+ §2.4（GUI 设计与禁编辑落点表）+ §2.5（scopes
  保活三纪律）+ §5（测试策略六条）
- `.work/config.toml [gsd]` paused/auto 开关（开工前亲核）
- `.work/LESSONS.md` L041（tuist generate 恒末位）+ CONVENTIONS「新测试文件
  落域规则」（Project.swift 显式清单 + BUNDLE-MAP + tuist generate 恒末位）
- `App/Sources/Lightamer/MCP/McpToolRegistry.swift`（:61-107 McpToolError
  16 档 + code switch / :146-176 McpToolDescriptor / :208-225 McpTimeouts /
  :283-303 Entry+writerCheck+writeCallCount / :310-320 register+setWriterCheck /
  :331-355 dispatch 两门序）
- `App/Sources/Lightamer/MCP/McpServerController.swift`（:217 makeHeadless
  SearchState / :287 makeHeadlessProjectContext / :451 runHeadless + :463-464/
  :475-476 两臂 / :512 runHeadlessArbitrated + :579-581 / :676 warmLutLibrary /
  :686 startReadOnlyHTTPHost / :749 startHeadlessStdioHost / :807 makeRegistry
  / :988 startHTTPHost / :1089/:1111 Embedded 两缝）
- `App/Sources/Lightamer/Library/BackgroundTaskHosting.swift`（:53 协议 /
  :70 registry / :82 register / :88 update / :89 finish / :94 cancel /
  :101 cancelAll）+ `App/Sources/Lightamer/UI/Shell/BackgroundTaskBarView.swift`
  （:20 descriptor / :43 bar / :113 dialog host）

---

## T1 — ControlToolset 第五域 + requiresControl 第三道门 + 错误码 16→19 + controlAcquire 新档

> **协议面单任务**：三工具 + 一道门 + 三错误码 + 一超时档，全部 additive。
> **错误码 additive 本波持权**（M7-2 15→16 先例第三行使）；**McpTimeouts
> 新档 additive 申报**（既有八档值零改——历史零 diff 红线勘误正本 =
> CONTEXT D-M7-5-7）。控制三命令自身免 admit（OQ-3 同语义）。

**read_first**：`M7-5-RESEARCH.md` §1.1/§1.2（Alcedo 三命令 + admit 三拒形）
+ §2.3（工具面设计——requiresControl 候选集 13 精确清单）；
`McpToolRegistry.swift` :61-107（错误码表 + code switch）+ :283-355（Entry/
writerCheck/register/dispatch 两门序）；`McpServerController.swift` :807-833
（makeRegistry 四参形——第五参 additive）；`ProjectToolset.swift` :100-230
（registerAll 形——ControlToolset 同款先例）；各工具注册点坐标（SC 列表）。

- **action**：
  1. **`ControlToolset.swift` 新建**：`McpControlState: Sendable, Equatable`
     值类型 `{held: Bool, revokedByUser: Bool, holder: String}` +
     `static let headlessConstant`（`{held: true, revokedByUser: false,
     holder: ""}`——无头恒真面单源，T4 复用）。`McpControlContext: Sendable`
     全 provider closure optional 缺省 nil（`McpProjectContext` 同款）：
     `acquire: (@Sendable (String) async throws -> McpControlState)?` /
     `release: (@Sendable () async throws -> McpControlState)?` /
     `state: (@Sendable () async -> McpControlState)?`——admit **不入
     context**（admit 走 registry seam——两道门是 registry 结构面非工具
     私有面）。`McpControlToolset.registerAll(on:context:)` 注册三工具：
     - `control_acquire`：入参 `holder_name`（string optional，缺省
       `"agent"`）→ 出参状态对象三键；acquire 臂超时
       `McpTimeouts.controlAcquire`；readOnlyHint/destructiveHint 缺省
       （非只读非 destructive——控制权转移非状态变更）；
     - `control_release`：零入参 → 状态对象（无控制时零动作幂等——
       context provider 承担幂等语义，工具面透传）；
     - `control_get`：零入参 → 状态对象 + `readOnlyHint: true`。
     三工具 **requiresControl 缺省**（免 admit——grep 断言零显式）；
     description 走 xcstrings 三键（`String(localized:defaultValue:)`
     显式形态；自写文案——acquire 语义句「取得 GUI 会话控制权；另一
     holder 在持时拒」/ release 幂等句 / get 只读句）。
  2. **registry 第三道门**：`Entry` 恰 +1 字段 `requiresControl: Bool`；
     `register` 恰 +1 参数 `requiresControl: Bool = false`（既有注册零
     diff）；`setControlAdmit(_ admit: (@Sendable (_ toolName: String)
     async throws -> Void)?)` seam；dispatch（:331-355）恰 +1 门——
     writer 门之后 handler 之前：`if entry.requiresControl, let controlAdmit
     { try await controlAdmit(name) }`；**writeCallCount 面零触**（计数仍
     只挂 writer 门）。admit nil = 放行（headless 恒放行臂——writerCheck
     nil 同形）。
  3. **错误码 16→19**：`McpToolError` 恰 +3 case（`controlNotHeld(String)` /
     `controlRevokedByUser(String)` / `controlBusy(String)`）+ code switch
     恰 +3 臂（snake 与 case 同名）；文案走 xcstrings 三键（自写——
     not_held 要点「state-changing 需先 control_acquire」/ revoked 要点
     「用户已停 agent——停下问用户；同意后再 acquire」/ busy 携当前
     holder）；**禁抄 Alcedo GPL 措辞**。
  4. **McpTimeouts 新档**：恰 +1 行 `public static let controlAcquire:
     Duration = .seconds(10)`（:208-225 段 additive）；既有八档逐行零触
     （diff 面核）。
  5. **13 工具 requiresControl**：各 register 调用点恰 +1 行
     `requiresControl: true`——editing 4（load_image :279 / export_image
     :366 / apply_params :538 / paste_adjustments :809）+ culling 6
     （metadata write face 注册批五件 + apply_preset :518）+ match 1
     （match_color :59）+ project 2（project_open :141 / project_create
     :204）；descriptor/handler 体零触（diff 面核——每 hunk 恰一行）。
  6. **makeRegistry 第五参 + 四宿主缝**：`makeRegistry`（:807）恰 +1 参数
     `control: McpControlContext? = nil`（缺省 nil = 既有构造零 diff）+
     `if let control { await McpControlToolset.registerAll(...) }`；四宿主
     additive 透传（startReadOnlyHTTPHost :686 / startHeadlessStdioHost
     :749 / startHTTPHost :988 / startEmbeddedIfPreferenceEnabled :1089 +
     EmbeddedState box `control` 字段——startEmbeddedServer :1111 on-leg
     读出透传，第六缝同款）；本任务透传参暂接 T4 面的 context（T1 内可先
     传 nil 保持编译绿——**宿主缝接线与恒真面装配 T4 一次落**，T1 红线 =
     四宿主缝签名/box 字段就位 + grep 点位在册）。
  7. **xcstrings 三新键**尾块纯插入（`mcp_tool_desc_control_acquire` /
     `_control_release` / `_control_get`）。
  8. 构建绿机检（caffeinate -dis 包裹）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰七产线文件（ControlToolset 新建 +
    McpToolRegistry + 四 Toolset + McpServerController + xcstrings）。
  - grep：`controlNotHeld|controlRevokedByUser|controlBusy` 在
    McpToolRegistry 恰各一处 case + 各一处 code 臂；`requiresControl` 在
    McpToolRegistry 恰三处（Entry 字段 + register 参数 + dispatch 门）+
    四 Toolset 恰 13 处 `requiresControl: true`；`controlAcquire` 恰一行
    定义；既有八档行 diff 零触；`requiresControl` 在 ControlToolset 零
    命中（免 admit 断言）。
  - `git diff App/Sources/Lightamer/MCP/McpToolRegistry.swift` 逐 hunk 核 =
    恰 case×3 + code×3 + Entry×1 + register×1 + setControlAdmit + dispatch
    门×1 + McpTimeouts×1；writeCallCount 行零触。
  - xcstrings diff = 恰三尾块插入（历史键零触碰）。
- **commit**: `feat(m7-5): add the control toolset and the third registry gate`

## T2 — AgentControlCoordinator + GUI 禁编辑 12 面 + get_state control.agent

> **GUI 面单任务核心 = 禁编辑 12 面「与 isReadOnly 同点位合并
> .disabled(readOnly || agentHeld)」逐面清单**（research §2.4 表为落点
> 正本）+ **disable-not-unmount**（条件卸载形态禁入——scopes 保活结构性
> 前提）。**FIX2③ 第四波**：`LibraryProjectController.swift` 零 diff。

**read_first**：`M7-5-RESEARCH.md` §1.3（owner 状态机——单写点/Stop/resume）
+ §2.4（GUI 设计全节）+ §2.5（scopes 保活逐项表）；
`WorkspaceHostView.swift` :153/:625/:638/:1447-1451（M6-1 只读呈现先例
三件）；`PipeCoordinator.swift` :1771/:1815（begin/commit 配对点）+
:2129-2147（scope 门——零触面）；`SearchStateToolset.swift` :1046-1101
（get_state control 面）；`LightamerApp.swift` :1268-1390（GUI MCP 装配段
——liveState hop 纪律）+ :1600（菜单 disabled 先例）。

- **action**：
  1. **`AgentControlCoordinator.swift` 新建**（`App/Sources/Lightamer/
     State/`）：`@MainActor @Observable final class`——状态 =
     `held: Bool` / `stoppedByUser: Bool` / `holderName: String` /
     `taskId: UUID?` / `activity: [AgentActivityEntry]`（T3 扩展字段结构
     本任务就位——entry = {summary, result: pending/ok/interrupted}）+
     `holdsControl` 派生（禁编辑门单源）。API：
     `admit(toolName:)`（held → 放行 + 登记 activity 条目置 in-flight /
     stoppedByUser → throw `controlRevokedByUser` / 其余 → throw
     `controlNotHeld`）；`acquire(holderName:)`（异 holder 在持 → throw
     `controlBusy` 携 holder；liveEditActive → 挂起轮询〔250ms 间隔〕至
     封合或注入超时〔缺省 `McpTimeouts.controlAcquire`——参数可注入供
     测试短窗〕→ 超时 throw `controlBusy` 携未封合语义；成功 → 同 holder
     = resume 同 taskId 回 held + stoppedByUser 清 / 异 holder = 新
     taskId + stoppedByUser 清）；`release()`（幂等——无控制零动作；
     有控制 → held=false + in-flight 闭 ok + 任务终态收尾〔T3 面〕）；
     `stop()`（held=false + stoppedByUser=true + stoppedHolderName 记忆 +
     in-flight 闭 interrupted + 任务终态 Canceled〔T3 面〕）；
     `liveEditActive: () -> Bool` 注入 provider（F-6——不硬引
     PipeCoordinator，装配点闭包喂 `pipeCoordinator.liveEditDepth > 0`）。
     **单写点纪律**：状态写只在本类；**scoped 零引用**（setScopeTapEnabled/
     scopesVisible/ScopeThrottle 字样零命中——红线⑤负测面）。
  2. **PipeCoordinator additive 计数**：恰 +1 私有 `liveEditDepth` +
     internal 只读访问器；`beginContinuousEdit`（:1771）增一、
     `commitContinuousEdit`（:1815）减一（配对；**两点外函数体零触**——
     其余 begin 系〔beginDrtEdit :737/beginFilmEdit :922〕零触面申报：
     live-edit 窗口径 = D-H1 continuous 窗，DRT/Film 单独窗不入——它们
     无拖动连续态，非未封合冲突窗）。
  3. **get_state agent 子对象**：`McpSearchStateContext` 恰 +1 optional
     provider `agentControl: (@Sendable () async -> McpControlState?)? =
     nil`（缺省 nil = 既有构造零 diff）；get_state control 面（:1053-1076）
     恰 +1 键 `"agent"`——provider nil → `.null`；有值 → `{held,
     revokedByUser, holder}` 子对象；**既有三键 lock/holder/writeCallCount
     值与形零漂移**（golden 显式改归 T6——本任务后 App bundle 该面红窗
     起）。
  4. **GUI 禁编辑 12 面落位**（逐面 `.disabled(readOnly || agentHeld)`
     合并形；gate 值 = coordinator.holdsControl——装配点注入 workspace/
     视图层，视图零 coordinator 硬引者走既有环境注入缝）：
     ①adjustment panels——`EditorWorkspaceShellView` :171 宿主列 + 页宿主
     分支（Drt/Film/RawDecode）；②面板栈容器——`EditorAdjustmentStackView`
     容器级一处；③viewport 工具 + 历史列表——`EditorToolRailView`；
     ④节点画布/蒙版——`EditorNodesPanelView`（NodeCanvasGeometry 零触）；
     ⑤Undo/Redo/history——`MenuCommandSet` 命令项（:1600 先例形）；
     ⑥版本——`VersionsPanelView`；⑦editor 切图——`FilmstripView`；
     ⑧import——`ImportModeDialog` confirm 入口；⑨delete——
     `LibraryGridView`；⑩rating——`LibraryInspectorView`；⑪export start——
     `WorkspaceHostView` :625/:638（export/yiyin 钮——与 isReadOnly 同
     点位合并）；⑫project open/create/close——**调用点视图层**（sidebar/
     welcome/open 面板入口——controller 文件零 diff）。
     **机制红线**：全点位 `.disabled()` 容器层合并形；`if !agentHeld`
     条件卸载形态禁入（grep 断言——`if !` + holdsControl/agentHeld 组合
     在 UI 面零命中）。**保留面零触**：scopes 面板/任务卡/Toast/浏览/
     缩放/搜索/设置（diff 面核——ScopePanelView/BackgroundTaskBarView/
     SettingsView 零触）。
  5. **GUI MCP 装配**（LightamerApp :1268-1390 同段）：control context =
     coordinator-backed（`acquire`/`release`/`state` provider MainActor
     .run hop 到 coordinator——liveState 同款纪律；F-6——工具体零
     coordinator 类型引用）；searchState context 的 `agentControl`
     provider 同段 hop；MenuCommandSet undo/redo/history 的 disabled 数据
     源接线（holdsControl）。
  6. **xcstrings**：错误文案三键已在 T1；本任务卡面键零新增（T3 面）。
  7. 构建绿机检。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰新 coordinator 文件 + PipeCoordinator +
    SearchStateToolset + LightamerApp + 禁编辑点位文件族（12 面落点——
    执行时以 grep 亲点后如实申报；每 hunk 恰禁编辑合并形）。
  - **LibraryProjectController.swift 零 diff**（`git diff --stat` 核不在
    清单——FIX2③ 第四波）。
  - grep：`liveEditDepth` 在 PipeCoordinator 恰两触点（:1771/:1815）+ 一
    定义 + 一访问器；`agent` 键在 SearchStateToolset get_state control
    面恰一处；`setScopeTapEnabled|scopesVisible|ScopeThrottle` 在
    AgentControlCoordinator 零命中；`if !` + agentHeld 组合在 UI 面
    零命中。
  - 禁编辑点位逐面 diff 面核 = `.disabled(readOnly || agentHeld)` 合并形
    （或等价派生闭包形——DECISIONS 申报逐面终形）；保留面文件零触。
- **commit**: `feat(m7-5): add the agent control coordinator and the gui disable faces`

## T3 — 活动卡（bar 行 + registry 演进）+ Stop→ResumeTask 语义

> **KD-7 演进条款兑现**：pinned/activity/dismiss/resume 全套（OQ-6）。
> **既有三腿零漂移**是本任务验收核心——isPinned 走 extension 默认 false，
> finish/cancel/cancelAll 语义零触。

**read_first**：`M7-5-RESEARCH.md` §1.3/§1.4（owner 任务钉住 + 活动卡字段
+ `7e0c9cb` 迭代增量）+ §2.4（活动卡段落）；`BackgroundTaskHosting.swift`
:40-115 全文；`BackgroundTaskBarView.swift` :20-170（descriptor/bar/dialog
三面 + cancel 路由 + AX 形）。

- **action**：
  1. **registry/handle 演进**：`BackgroundTaskHandle` 协议恰 +1 要求
     `isPinned: Bool` + extension 默认 `false`（既有三 conformer 零改
     ——编译零 diff）；`BackgroundTaskRegistry` 恰 +1 方法
     `dismiss(id:)`（显式除名——实现 = finish(id:) 复用或薄封装，
     DECISIONS 申报终形）；`finish`（:89）/`cancel`（:94）/`cancelAll`
     （:101）**语义零触**（pinned 不改 finish 形——agent 腿不调 finish
     于终态，由 coordinator 持有句柄；dismiss = 用户手动除名路由）。
  2. **AgentTaskHandle**（coordinator 文件内）：`final class
     AgentTaskHandle: BackgroundTaskHandle`（@MainActor @Observable）——
     `isPinned = true` + `id`（acquire 时 mint；同 holder resume 恒同
     id）+ `title`（"Agent · <holder>"）+ `snapshot`（indeterminate
     进度 + detail = in-flight 命令 summary；命令间 = waiting 文案）+
     `cancel()` → `coordinator.stop()`（Stop 单入口——OQ-9）+ `activity`
     投影面（bar/dialog 消费）。
  3. **Stop→ResumeTask 语义**（coordinator 面补全）：stop → 任务终态
     Canceled（snapshot 终态标注 + 留列表〔pinned〕）+ 控制立即回用户 +
     stoppedHolderName 记忆 + in-flight activity 闭 interrupted；同
     holder re-acquire → 同 id 回 Running（活动列表延续——不 mint 新
     id 不清 activity）；异 holder Stop 后 acquire → 新 id 新任务（旧
     Canceled 任务留列表由用户手动 dismiss）；stoppedByUser 在任一成功
     acquire 清除。终态 pinned 行的 bar/dialog cancel 位 = dismiss 路由
     （registry.dismiss）。
  4. **活动卡 bar 行**（BackgroundTaskBarView）：agent 行渲染
     （kind label = tasks_agent_kind / title = Agent · holder / detail =
     in-flight summary 或 agent_card_waiting / indeterminate progress /
     running 态 cancel 钮 = Stop〔tasks_agent_stop〕/ 终态 pinned 行
     dismiss 钮〔tasks_dismiss〕）；对话框活动列表行集（activity 逐条
     summary + result 徽标）+ AX 标识（bar/dialog agent 行族——
     `tasks.bar.agent` / `tasks.dialog.agent.activity` 形）；既有
     import/export/AI 行渲染面零漂移（descriptor 投影 additive——
     既有行 diff 零触）。
  5. **xcstrings 四新键**尾块纯插入（`tasks_agent_kind` /
     `agent_card_waiting` / `tasks_agent_stop` / `tasks_dismiss`——
     文案自写）。
  6. 构建绿机检。
- **验收标准（机检）**：
  - 构建绿；grep：`isPinned` 恰协议一处 + extension 默认一处 +
    AgentTaskHandle 一处；`dismiss(id:)` 在 registry 恰一处；`finish`
    函数体 diff 零触（`git diff` 面核 :89-:100 段）。
  - Stop 路由 grep：agent 行 cancel → `coordinator.stop()` 单路由
    （无第二 Stop 入口——菜单命令零命中）。
  - 既有三腿（ImportTaskAdapter/Export/AI adapter）diff 零触（`git diff
    --stat` 面核）。
  - xcstrings diff = 恰四尾块插入。
- **commit**: `feat(m7-5): add the agent activity card with stop and resume`

## T4 — 无头恒真面 + read-only 宿主照常注册 + scopes 保活三纪律

> **TURN-04 面**：`makeHeadlessControlContext` 常量闭包零成本 + admit
> 无头臂恒放行（nil = 放行，T1 已就位）；**union 单值纪律** = 所有宿主同
> 32 面（tools never disappear——M7-3 H3 先例延伸：宿主缝不接线 = control
> 三工具静默缺席）。**scopes 保活三纪律**在本任务以红线 + grep 断言落位
> （测试归 T6）。

**read_first**：`M7-5-RESEARCH.md` §1.7（headless 简化臂）+ §2.5（scopes
保活逐项表）+ §2.3（无头恒持有段）；`McpServerController.swift` :451-:620
（runHeadless/runHeadlessArbitrated 全形——T1 宿主缝接线点）+ :686-:1060
（三宿主缝）；`LightamerApp.swift` 装配段（GUI 内嵌臂——EmbeddedState
路径 coordinator-backed 形）。

- **action**：
  1. **`makeHeadlessControlContext`**（McpServerController）：常量面——
     `acquire` → `McpControlState.headlessConstant` / `release` → 同常量 /
     `state` → 同常量（零成本 closure）；**admit 不设**（registry
     controlAdmit nil = 恒放行——writerCheck nil 同形；headless 写工具免
     acquire 直答）。
  2. **五无头宿主接线**：runHeadless :451 两臂（:463-464/:475-476）+
     runHeadlessArbitrated :512（:579-581）+ startHeadlessStdioHost :749 +
     startHTTPHost :988 + startReadOnlyHTTPHost :686——全传
     `control: makeHeadlessControlContext()`（read-only 宿主照常注册——
     OQ-10：控制态与写权正交如实呈现，写仍被 writer 门前置拒）。
     **H3 对账**：不接线 = 该宿主 control 三工具静默缺席违 union 单值
     ——五宿主调用点清单 grep 机检。
  3. **GUI 内嵌臂**（EmbeddedState 路径 + LightamerApp 装配段）：control
     context = coordinator-backed（T2 已装配——本任务核 EmbeddedState box
     `control` 字段 :1089/:1111 两缝读出透传接线闭合——GUI off→on toggle
     控制工具不静默缺席）。
  4. **makeHeadlessSearchState 恰 +1 additive 参**：`agentControl`
     常量 provider（`{ McpControlState.headlessConstant }`——get_state
     无头臂 agent 面 = 恒真常量；T2 的 provider 缝就位后此参注入）。
  5. **scopes 保活三纪律落位确认**（红线 + grep 断言，测试归 T6）：
     ①disable-not-unmount——T2 禁编辑点位已合并形（本任务 grep 复核零
     条件卸载）；②`WorkspaceModel.scopesVisible` 单源——diff 面核写者
     面零触（View 菜单开关唯一写者维持）；③ScopeThrottle 零触——
     `ScopeThrottle` 相关文件 diff 零触 + `setScopeTapEnabled` 调用点
     diff 零触（挂载门单源维持）。
  6. 构建绿机检。
- **验收标准（机检）**：
  - 构建绿；grep：`makeHeadlessControlContext` 恰一定义 + 恰五调用点
    （:463/:475/:579/:749 段/:988 段/:686 段——逐点亲核后如实申报清单）；
    `headlessConstant` 在 ControlToolset 恰一定义 + coordinator/GUI 零
    消费（恒真面只属无头臂——GUI 臂走 coordinator）。
  - **union 单值对账**：五宿主缝调用点清单在 DECISIONS（grep 输出附）；
    EmbeddedState `control` 字段两缝（存 :1089 / 读 :1111）在位。
  - scopes 三纪律 grep 面核（§T2 验收同款 + scopesVisible 写者面零触）。
- **commit**: `feat(m7-5): wire the headless always-held control face`

## T5 — M7-4 顺路件（S-1 四处注释 + S-3 实测 + S-2/S-4/S-5 申报）

> **S-2 路由 = 让渡下一 Export 波**（CONTEXT 顺路件表③显式申报——
> ExportRenderer 非 M7-5 触碰面 + 单行修复须伴判定腿防 F-AC-1 复演 +
> 原路由零 churn；晨审可翻）。**S-1 拆两批**：四处非 union 文件注释本
> 任务清零；union 文件注释随 T6 同 commit。

**read_first**：`M7-4-VALIDATION.md` §挂账（五项正本）；注释坐标
`McpHostTests.swift` :466/:668 + `McpSearchStateToolsetTests.swift` :16/:265；
`M7-5-RESEARCH.md` §4（顺路件表）。

- **action**：
  1. **S-1 注释清零（四处）**：McpHostTests :466/:668（"21-tool face"
     过时形——改写为当前真值形「editing+culling face（23 since M7-4），
     控制域独立第五域不触两域」语义）+ McpSearchStateToolsetTests :16/
     :265（同形改写）；**注释-only diff**（断言/message 零触——:243/:274
     计数 23 五钉零触）。
  2. **S-3 预热后 stdio 首调实测**：spawn 真二进制（T5 时刻已构建的
     debug 产物；env 不设 `LIGHTAMER_SKIP_LUT_PREHEAT`——预热生效），
     计时首调 `list_luts` 一次；数据落
     `evidence/s3-preheat-first-call.log`（含二进制路径/构建指纹/计时值/
     对照正本 M7-3 冷窗 50.2s）；若 spawn 形不可达 = DECISIONS 申报改
     McpProjectArbitrationTests spawn 形同款产出计时行。
  3. **S-2/S-4/S-5 申报句起草**（落 T7 DECISIONS——本任务只在 SUMMARY
     草稿登记指针）：S-2 让渡句 / S-4 第四波维持注记 / S-5 无动作句
     （条件未触发）。
  4. 构建绿机检（注释批不影响编译——App bundle 快照红窗持续）。
- **验收标准（机检）**：
  - `grep -rn "21-tool face\|count rides 21" Tests/LightamerTests/` 零
    命中（四处清零）；McpHostTests/McpSearchStateToolsetTests 断言行
    diff 零触（注释批 diff 逐 hunk 核 = 纯注释行）。
  - `evidence/s3-preheat-first-call.log` 在库且含计时值。
- **commit**: `chore(m7-5): clear the M7-4 carry-over ledger items`

## T6 — 测试批：union 29→32 全点位 + control 域快照 + coordinator 状态机 + 零回归

> **orchestrator 指定分批**：测试集中本任务一次落位（T1-T5 码面稳定后）。
> 新文件 `McpControlToolsetTests.swift`（control 域快照层——union 头注
> 「Snapshot layers」清单 +1 行）+ `AgentControlCoordinatorTests.swift`
> （coordinator/GUI 面）。**union 显式改 = 本波持权**——全点位清单落位 +
> DECISIONS 申报。**穷举 16→19 与 get_state golden 同批显式改**（红窗
> 闭合点）。

**read_first**：`M7-5-RESEARCH.md` §5（测试策略六条）；`McpFinalSnapshotTests.swift`
（:14-34 头注 + layers 清单 / :54 段冻结表尾 / :245-247 all29 / :251-268
makeUnionRegistry / :270-290 union verbatim〔:275 计数 + :278-290
destructive 集〕/ :293-330 域组合代数〔:311-316 disjoint + :318 五集合并
+ :328 计数〕/ :356 白名单负测计数 / :363 descriptionKeys / :510 直入面
计数）；`McpSearchStateToolsetTests.swift` :1020-1050（穷举 16 值）+
get_state golden 面；`McpProjectToolsetTests.swift`（域快照层先例形——
verbatim + 分账 + 白名单负测同构）。

- **action**：
  1. **control 域快照新层**（McpControlToolsetTests）：三工具 name/
     description/schema verbatim（assertSnapshot 同构形）+ 域内计数 32
     分账 + 白名单负测（未注册名 = internalError unknownTool——union
     先例形）+ requiresControl/readOnlyHint 注解断言（control_get =
     readOnlyHint；三工具 requiresControl 面 = registry Entry 断言——
     控制三命令免 admit 负测：无 admit 时写工具照答）。
  2. **admit 三拒面 + 13 工具拒面**（registry 层 fixture）：coordinator
     stub 态三臂——not held 调 `apply_params` → `controlNotHeld` /
     stop 后调 → `controlRevokedByUser` / held 态照答；13 工具逐一名
     无 admit 时拒面（候选集精确性断言——14 件面外工具〔copy_adjustments/
     render_preview/list_*/get_*/search_photos〕免 admit 照答）；acquire
     异 holder → `controlBusy` 携 holder；writer→control 门序断言
     （serverReadOnly 宿主下 requiresControl 工具先吃 serverReadOnly——
     writer 门先行）。
  3. **acquire 三态**（注入短窗）：①未封合挂起→封合即得（liveEditActive
     true → acquire 挂起 → provider 转 false → 短窗内成功）；②超时臂
     （liveEditActive 恒 true + 注入 200ms 窗 → `controlBusy` 携未封合
     语义）；③Stop 中断（等待中 stop → acquire 快速终答 + 控制回用户）。
     **禁测试真等 10s**（缺省档只在生产路径）。
  4. **无头恒持有负测**（TURN-04 验收形态）：makeHeadlessControlContext
     三 provider 恒真断言 + admit nil = 写工具免 acquire 直答（无头装配
     `apply_params` 直接进 handler——stub handler 记调用）+
     control_acquire 无头恒 held；read-only 宿主 control 注册臂
     （writerCheck false 下 control_get 照答 + apply_params 前置
     serverReadOnly）。
  5. **get_state agent 腿**：nil provider → `.null`（诚实面）+ 真值
     provider → `{held, revokedByUser, holder}` 子对象 + 既有三键值形
     不变断言。
  6. **coordinator 状态机全序**（AgentControlCoordinatorTests）：
     acquire→activity 条目→admit 放行→Stop→拒→同 holder resume 活动
     连续→release 终态→dismiss 除名 + 异 holder busy + stoppedByUser
     清除 + activity 边界闭形（下次 admit/release/stop 闭 in-flight；
     Stop 闭 interrupted）+ pinned/dismiss 三腿负测（ImportTaskAdapter/
     Export/AI adapter handle isPinned=false → finish 即移除不变；
     AgentTaskHandle 终态留列表 → dismiss 移除）+ holdsControl 派生面。
  7. **禁编辑点位结构断言 + scopes 保活负测**：12 面 grep 面断言
     （每点位 `.disabled(` 含 agentHeld 合并形——测试内嵌点位清单或
     读源断言，DECISIONS 申报终形）+ holdsControl 求值腿；scopes 保活 =
     coordinator 零 scope 引用 grep 断言 + 翻转 holdsControl 无 scope
     副作用（scopeTapEnabled/结果面不变——coordinator 单测）+
     disable-not-unmount 负测（禁编辑态面板仍挂载结构面——
     ScopePanelView 挂载与 holdsControl 零耦合断言）。
  8. **union 显式改全点位**（McpFinalSnapshotTests——本波持权）：冻结表
     +`controlTools` 域数组（三行——名序 control_acquire/control_get/
     control_release 亲核 descriptors() 名序后落）+ `all29`→`all32`
     （:245 定义 + :273 引用同批改名）+ 计数断言 ×4（:275/:328/:356/
     :510）29→32 + 组合代数**五集合并**（:318 段——controlOnly registry
     + `Set(u) == Set(e)∪Set(c)∪Set(s)∪Set(p)∪Set(k)`）+ 域两两 disjoint
     断言 +4（control×{editing,culling,searchState,project}）+
     `makeUnionRegistry`（:251）+ control fixture context 参（全 nil
     provider——注册面零消费）+ 测试名 Union29→Union32 + destructive
     十件集断言零改（control 三工具全非 destructive——集恒等维持；
     message 可注 control 免 admit 句）+ `descriptionKeys`（:363）+3 行
     + 头注 :14-34 改写（M7-5 条目 + Snapshot layers 清单 +「the control
     domain (3)」行）+ :268 "exactly these 27" 清零（S-1 余下坐标——
     **同 commit**）。
  9. **穷举 16→19 同批**（McpSearchStateToolsetTests :1023）：法名
     `…NineteenValuesExhaustive` + errors/expected 数组 +3 + count 断言
     16→19 + message 同批。
  10. **get_state golden 显式改**：恰 +1 键 `agent`（nil provider 面
      `.null`）——DECISIONS 申报；get_state 真值腿（action 5）同文件。
  11. **零回归门**：既有 29 工具 descriptor/handler 零 diff（快照门
      双证）；union 外五钉 23 零触（:223/:243/:697/:200/:274——T5 注释批
      后断言行仍零触）；`McpRegistrySnapshotTests` 零 diff（editing 层
      9 行零触——控制域独立新增不触两域）；BackgroundTaskRegistry 三腿
      负测绿；requiresWriter/writeCallCount 面零漂移；ScopeThrottle 既有
      纯函数测试零触绿。
  12. **Project.swift 恰两行 + BUNDLE-MAP 恰两行 + tuist generate 恒
      最后动作**（L041）+ `--bundle APP` 定向绿（红窗闭合点）。
- **验收标准（机检）**：`--bundle APP` 全绿；快照显式改申报在 DECISIONS
  （union 全点位清单附）；新文件恰两行登记 + BUNDLE-MAP 恰两行；**残漏
  grep**：`count, 29` / `count == 29` / `all29` 在 Tests/LightamerTests/
  Mcp* 零命中；五钉 23 断言零 diff；`git diff` 面核 destructive 集断言
  零改。
- **commit**: `test(m7-5): pin the goldens and grow the union snapshot to 32`

## T7 — 定向轮 + 全套 `--all` + 红线族 + 收口翻账

- **action**：
  1. **定向轮**：`caffeinate -dis Scripts/test-direct.sh --bundle App`
     全绿（全部新测试落 APP 域；App bundle = MCP 面 + coordinator/GUI 面
     覆盖本批全部新测试面）。
  2. **全套确认轮**：`caffeinate -dis Scripts/test-direct.sh --all`
     （**批准制**——本 plan 标注在案，执行时 orchestrator 派发 prompt
     即批准；运行中保持监视 + 8G 门 + MEMFAIL 机检，超门立即 kill）。
     `TOTAL|3925+ΔN/35/0|` 对账精确闭合（ΔN 逐任务记账；skip 35 构成
     声明——第三种 skip 来源 = 逐族差分申报禁静默吸收）。
  3. **红线族机检**（front-matter `red_lines` 逐条亲跑）：零新 SPM /
     `.metal` 全域零 diff / 封存面 17 件零 diff / 既有 29 工具
     descriptor/handler 零 diff / union 外五钉 23 零触 / writeCallCount
     面 zero-diff / LibraryProjectController 零 diff / PipeCoordinator
     恰 additive 计数（其余函数体零触）/ 保留面文件零触（ScopePanelView/
     BackgroundTaskBarView 既有行——bar 仅 additive agent 行）/ xcstrings
     恰 10 尾块插入（历史键零触碰）/ UserDefaults 零新键 / runModal 零
     命中 / LocalizationValue 插值禁形零命中 / Project.swift 恰两行 +
     BUNDLE-MAP 恰两行 + tuist generate 末位核。
  4. **zh-audit 对账**：`uv run python3 Scripts/zh-audit.py --check` PASS
     （10 新键——source keys 数 +10 对账）+ `--self-test` PASS。
  5. **GUI 走查配方**：`.work/gui-acceptance/m7-5/MANIFEST.md`（活动卡
     行面 + Stop→resume 流程 + 禁编辑 12 面实机走查行 + 遮挡态 scopes/
     viewport 观感行〔research §2.5 走查行〕+ S-3 计时行引用）——实机
     走查归验收批（TURN-02 验收形态②）。
  6. **SUMMARY + DECISIONS**：逐任务 ΔN 记账 + 四验收形态判定指针
     （双端 fixture / 活动卡走查配方 / Stop→resume 活动连续 fixture /
     无头恒持有负测）+ union 显式改申报（全点位清单）+ get_state
     golden 显式改申报 + 错误码 16→19 + McpTimeouts 新档勘误申报
     （D-M7-5-7 承接）+ activity 边界闭形终形 + 无通知通道偏离 +
     无 GUI 选区工具申报 + S-2 让渡 / S-4 第四波维持 / S-5 无动作申报 +
     禁编辑点位终清单（逐面终形）+ acquire 超时注入终形 + 中间红窗
     处置申报。
  7. **翻账**：REQUIREMENTS TURN-01..04 → Delivered（M7-5 commit 指针）；
     AGENTS「M7-5 架构增量」节（turn-taking 三面语义 + coordinator 单
     写点 + requiresControl 门 + **union 改动权移交 M7-6**——串行禁并行
     注记延续 + ΔN 终值）；TODO（M7-5 条目 + M7-4 挂账 S-1/S-3 收口 +
     S-2 让渡/S-4 维持/S-5 无动作申报 + FIX2③ M7-6 维持）；GOAL-STATE
     续接点（M7-5 收口 → next = 验收/VALIDATION + M7-6）。
- **验收标准（机检）**：定向轮绿 + 全套 exit 0 / 0 fail / 0 MEMFAIL /
  七 bundle 8G 门内 + 对账闭合 + 红线族全 PASS + zh-audit 双 PASS +
  四台账同批落盘（历史行只追加不改写）。
- **commit**: `docs(m7-5): reconcile the full suite and close the M7-5 ledgers`

---

## 风险与回退

- **快照红窗（T1..T6 App bundle 中间态，已申报）**：穷举 16→19 自 T1、
  get_state golden 自 T2 起红 → T6 显式改收口；**每任务 gate = 构建绿**
  （App bundle 测试红窗期禁跑 --bundle App 全绿门——M7-3 先例形：T1-T5
  构建绿门 + T5 注释批后仍红）；T6 `--bundle APP` 为红窗闭合点；T7 全套
  终证。**禁为凑绿在 T1-T5 提前改穷举/golden**（显式改集中 T6 一批 =
  全点位亲核审计面）。
- **GUI 禁编辑点位面漂移**：12 面落点表坐标系 research §2.4 定性 +
  planner 部分亲核（:625/:638/:171 亲验；其余执行时 grep 亲点）——若
  某点位实际结构不经 `.disabled`（如 menu command disabled 参数形）=
  等价合并形 + DECISIONS 申报逐面终形；**禁为凑表数硬造点位**（面数 12
  是 Alcedo 语义清单非我方文件数——落点可多可少，语义覆盖为准）。
- **acquire 等待的测试确定性**：挂起轮询 250ms + 注入短窗（200ms）在
  CI/直启环境的时间抖动——轮询间隔与超时判据都经 provider 注入（clock
  可注入则注入，DECISIONS 申报终形）；flaky = 回注 T2/T6 修，禁放宽
  断言。
- **coordinator 与 SwiftUI 生命周期**：@Observable coordinator 注入环境
  ——切图/关窗时 agent 在持（activity 残留）= 窗口生命周期边界行为
  （cancelAll 收尾或保留 pinned 跨窗口——DECISIONS 裁量申报；Alcedo 对
  表 = 任务 island 与窗口解耦，pinned 留存）。
- **union 单值对账**：五宿主缝若一处漏接 = 该宿主 29 面（control 三工具
  静默缺席）——T4 grep 点位清单 + T7 全套轮双门抓；违例 = 回注 T4。
- **T6 大批量测试后置**（orchestrator 指定分批的内在风险）：T1-T5 码面
  缺陷在 T6 才暴露 → 回注对应任务修复（fix commit + T6 重跑），禁为凑
  绿放宽断言；golden 任一不恒等 = 停手归因。
- **快照族冲突**：本波持 union 改动权——若 orchestrator 误并行派发
  M7-6（快照面撞车）→ 立即停手上报，禁抢先合并快照表。
- 全套轮任何 fail：先归因（本批 Δfiles 窗内?）——窗外 fail = 既有缺陷，
  停手上报不静默修。

---

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：ROADMAP §M7-5 行四验收形态 ↔ 任务面逐项映射——
   双端 fixture（T6 action 2/4：GUI typed 拒 + 用户夺回 agent 失权 +
   无头恒持有）/ GUI 活动卡走查（T3 面 + T7 MANIFEST 配方——实机走查
   归验收批）/ Stop→resume 活动连续 fixture（T6 action 6）/ 无头恒持有
   负测（T6 action 4）；REQUIREMENTS TURN-01..04 四行无孤儿项（TURN-01 =
   T1+T2 / TURN-02 = T3 / TURN-03 = T3 / TURN-04 = T4）；Alcedo 对表锚
   （control.acquire/release/get + admit 三拒形 + UserStateChange 锁 +
   task island + `7e0c9cb` Stop/resume + `c7ba784` scopes）→ 我方三面
   一一对应（偏离申报面：无通知通道 / 无 GUI 选区工具 / activity 边界
   闭形简化——CONTEXT 登记申报）。
2. **OQ 兑现核**：D-M7-5-1..10 逐条对任务面——①三码镜像 + 文案自写 +
   穷举同批（T1/T6）②独立第五域 + union 32（T1/T6）③13 全集 + 免
   admit + writeCallCount 零波及（T1——grep 13 处 + writeCallCount 行
   zero-diff）④全表 12 面 + disable-not-unmount + controller 零 diff
   （T2——逐面 diff 面核 + FIX2③ 门）⑤bar 行零 banner（T3）⑥全套演进
   + 三腿零漂移（T3/T6 负测）⑦等待 + controlAcquire 新档申报 + 注入
   短窗（T1/T2/T6）⑧agent 子对象 + 既有三键零漂移（T2/T6）⑨Stop 卡单
   入口 + resume 同 id（T3/T6）⑩read-only 注册 + 四宿主缝 + 第六缝
   （T1/T4）。
3. **快照族纪律**：union 显式改全点位（冻结表 +3 + 计数 ×4 + all32
   改名 + 五集合并 + disjoint +4 + descriptionKeys +3 + fixture context
   + 测试名 + 头注 + :268 注释清零）+ 五钉 23 零触 + 残漏 grep
   （count, 29 / count == 29 / all29 零命中）+ DECISIONS 申报；穷举
   16→19 + get_state golden 显式改同批（红窗闭合点 = T6）；「本波持权
   + M7-6 禁并行」在 plan 头注与红线双写。
4. **错误码/超时 additive 申报面**：恰 +3 case（零改零删）+ code 臂
   +3；McpTimeouts 恰 +1 行（既有八档逐行 zero-diff——diff 面核）；
   勘误申报句在 DECISIONS（M7-2..M7-4 零 diff 红线历史 → 本波首档
   additive——CONTEXT D-M7-5-7 正本）。
5. **禁编辑面**：12 面逐点 diff 面核（合并形 + 容器层）+ 条件卸载
   形零命中 + 保留面文件零触（scopes/任务卡/Toast/设置）+
   LibraryProjectController 零 diff（FIX2③ 第四波）+ coordinator 零
   scope 引用 grep。
6. **活动卡零漂移面**：isPinned extension 默认 false（既有 conformer
   零改）+ finish/cancel/cancelAll 函数体 zero-diff + 三腿负测绿 +
   bar/dialog 既有行 diff 零触（agent 行 additive）+ Stop 单入口
   （菜单第二入口零命中）。
7. **单写点/正交面**：coordinator 状态写只在本类（grep 写点）+ 与
   M6-1 锁面零耦合（SingleWriterLock/LibraryProjectController 引用
   零命中）+ liveEditActive 注入 provider 形（PipeCoordinator 硬引
   零命中——F-6）。
8. **顺路件路由**：S-1 六坐标全清零（四处 T5 + union 文件 T6 同
   commit）+ S-2 让渡申报句（CONTEXT 顺路件表 + T7 DECISIONS 双落）+
   S-3 evidence log 在库 + S-4 第四波注记 + S-5 无动作句；FIX2③ 不
   承载（controller 零 diff 门）。
9. **SC 可机检性**：每条 SC 有命令级判据（grep / diff 面核 / 计数
   断言 / 对账行 / 定向 bundle 绿），非「目测」；expected_all 对账式
   非死数；skip 35 构成声明条款在 T7。
10. **xcstrings/呈现纪律**：10 新键尾块纯插入（历史键零触碰——diff 逐
    hunk 核）+ 描述键 `String(localized:defaultValue:)` 显式形态
    （插值禁形 regex 零命中）+ runModal 零命中（活动卡/对话框全走
    SwiftUI 呈现缝）+ zh-audit --check（source keys +10 对账）+
    --self-test 双 PASS。
11. **登记纪律**：Project.swift 恰两行（两新测试文件）+ BUNDLE-MAP
    恰两行（APP 域）+ tuist generate 恒末位（L041）——commit 顺序核
    （登记与测试同 commit，generate 最后动作）。
12. **零回归面**：既有 29 工具 descriptor/handler 零 diff；五钉 23
    零触；McpRegistrySnapshotTests 零 diff；writeCallCount 面
    zero-diff；ScopeThrottle 测试零触绿；`--all` 3925+ΔN 对账闭合。

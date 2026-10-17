# M7-5-01 DECISIONS — 执行批裁定记录（2026-10-17 夜）

> 执行链：`599601d7`(T1)→`89d8bbff`(T2)→`4755941d`(T3)→`dea46168`(T4)→
> `47737c1d`(T5)→`f91d9aee`(T6)→T7 docs。裁决正本 = 同目录
> `M7-5-CONTEXT.md`（D-M7-5-1..10 全按 RESEARCH §6——执行中零重开）；
> 基线 3925/35/0（HEAD `cbad16eb`，planner 亲核）。

## §1 additive 申报面（三件本波持权/勘误）

1. **错误码 16→19 additive（本波持权）**：`controlNotHeld` /
   `controlRevokedByUser` / `controlBusy` 三 case + code 臂 +3 +
   message 连绑 +3（每名恰 3 处——F6 面）；穷举测试同批显式改
   （`testMcpToolErrorCodesNineteenValuesExhaustive`）。M7-2
   modelUnavailable 15→16 先例第三行使。
2. **McpTimeouts 历史零新档红线勘误（D-M7-5-7 承接）**：`controlAcquire
   .seconds(10)` = M7-2/M7-3/M7-4 三波零 diff 后**首开新档**——additive
   非 fix，既有八档逐行零触（diff 面核在案）。
3. **get_state additive 恰 +1 键 `agent`**：nil provider → `.null` 诚实
   面；既有三键 lock/holder/writeCallCount 值与形零漂移。

## §2 终形申报（plan 条款的落地形）

1. **acquire 超时注入终形（单一执法点）**：tool 面 `control_acquire`
   **不再叠 withTimeout 包装**——acquire 臂的超时预算 =
   coordinator 注入（缺省 `McpTimeouts.controlAcquire`，测试注入短窗）。
   理由：双 10s 包装在 10s 边界竞速（tool 侧精确 10s Task.sleep vs
   coordinator 250ms 轮询粒度 10.0–10.25s 触发）会用 generic
   internalError 掩盖 typed `controlBusy` 携未封合语义——D-M7-5-7 的
   typed face 优先。release/get 臂照旧 `McpTimeouts.list` 包装。
   release/get 臂照旧。
2. **activity 边界闭形终形**：admit 开 entry（pending）；下一边界闭前
   entry——**Stop 的 interrupted 闭形是终态**（后续 admit 不再改写已闭
   entry；`closeInFlight` 只寻 pending）。测试钉死
   （AgentControlCoordinatorTests.testFullSequence…：Stop 后 resume 的
   次条 admit 不复活 entry[0] 的 ok）。
3. **禁编辑点位终清单（11 实落点 + delete 缺席——F5）**：
   - ① EditorWorkspaceShellView stackSlot（宿主列）
   - ② EditorAdjustmentStackView 容器（tab rail + 页内容 + preset 全惰——
     Alcedo 整面板禁用语义）
   - ③ EditorToolRailView panel() 容器（history/versions/nodes 三页体）
   - ④ EditorNodesPanelView body（optional 注入式 gate——NodeCanvasGeometryTests
     裸宿主纪律，inspectorState 先例）
   - ⑤ LightamerApp CommandGroup .undoRedo :1913/:1918 同点位扩展
   - ⑥ VersionsPanelView 容器
   - ⑦ FilmstripView 容器
   - ⑧ ImportModeDialog confirm 钮合并形
   - ⑨ delete **缺席**：我方无删除工具（MCP 32 无 delete）+ 无图库删除
     路由——零落点，Alcedo 禁面语义由缺席覆盖（LibraryGridView 零触）
   - ⑩ LibraryInspectorView aiSection（AI 评片/描述命令区）
   - ⑪ WorkspaceHostView topbar export/yiyin 钮（:625/:638 同点位合并）
   - ⑫ project open/create/close **视图层**：File 菜单三项目项
     `.disabled()` + Welcome sheet 三闭包 guard 形（等价派生闭包形——
     LibraryWelcomeView 住在零 diff controller 文件内，FIX2④ 维持）
   - 结构断言：AgentControlCoordinatorTests 点位 manifest（10 文件 token
     亲点）+ 条件卸载负测（`if !agentControl` / `if agentControl.holdsControl`
     全 UI 面 zero-hit）。
4. **registry 注入缝偏差（F12 承接，记 DECISIONS）**：plan 的 init 依赖
   = BackgroundTaskRegistry 引用 + liveEditActive provider——实际落地：
   liveEditActive 走 `configureLiveEditProbe` 可换缝（App 根 @State 声明
   期无法引用同层对象——pipeCoordinator.configure(window:) 先例形），
   registry 走 `attachTaskRegistry` weak 附着（WorkspaceHostView .task
   注入——App 根装配点够不到窗口级 @State registry，跨附着先例同源）。
   acquire 成功时 register 幂等（id 去重）= plan 语义不变。
5. **union 文件内注释 token 清零形**：S-1 残漏 grep（`all29` 零命中）
   通过改写历史叙事措辞达成（「identifier chain grew one deliberate edit
   per wave」形）——历史条目保留、token 面干净。
6. **第六缝编号注记（F10）**：EmbeddedState `control` 字段 = M7-2 F-4①
   第五缝血统编号的第六缝（project = 第五缝；box 字段序 editing/culling/
   searchState/project/control 中 control 第 5 位——编号与字段序解耦）。
7. **coordinator 注释面与 F-6 负测的措辞耦合**：
   AgentControlCoordinatorTests 断言 coordinator 源码 zero-hit
   `PipeCoordinator`——coordinator 文件头/属性注释相应改用「pipe
   coordinator」小写叙述（类型名 token 只属注入缝文档）。

## §3 登记申报（CONTEXT §登记申报 承接 + 执行批补录）

1. **无通知通道**：Alcedo 广播 control.changed 等 5 通知；我方 MCP v1 同步
   req/resp 无通知（Phase 14 裁决）——agent 以 `control_get` / `get_state`
   轮询替代；工具 description 文案已内嵌该指引。
2. **无 GUI 选区类工具**：Alcedo headless `library.selection.get/set`
   返 -32001 not_ready——我方无对应工具，**零新错误码**
   （`notSessionMember` typed 拒为对表物）。
3. **S-2 让渡**：strerror clobber 一行（ExportRenderer :823）**让渡下一
   Export 波**（CONTEXT 顺路件表③正本——单行修复须伴 EEXIST 判定腿防
   F-AC-1 复演，为 M7-5 纯 MCP/GUI 波引入 Core Export 域扩散 = scope
   膨胀；晨审可翻）。
4. **S-4 第四波维持注记**：`LibraryProjectController` 零 diff 连续四波
   （本波禁编辑面全落视图层/闭包层——controller 零 diff 门亲证 diff 0 行）。
5. **S-5 无动作申报**：本波 DECISIONS 未触 exFAT/EOPNOTSUPP 卷归类句——
   条件顺路未触发，零动作。
6. **S-3 实测数据**：预热后 stdio 首调 `list_luts` = **8.4 ms**
   （total=40；对照 M7-3 冷窗正本 50.2s——三个数量级），二进制 md5
   `d72085572d121d7fca9086fe8f1c4031`，settle 100s。证据分仓 =
   lightamer-evidence `9b36b42`（主仓 policy B gitignore——**files_modified
   的 evidence 路径以分仓承载**，主仓不入库）。**GUI 走查配方
   MANIFEST 同政策分仓 = lightamer-evidence `0bf32ac`**
   （`.work/gui-acceptance/m7-5/MANIFEST.md`；主仓工作树留有同内容
   untracked 副本供走查批直接读）。
7. **xcstrings 三错误键随 T6 批补录**：T1 commit 漏插
   `mcp_error_control_not_held/_control_revoked_by_user/_control_busy`
   三键（T6 对账 1946→1953 发现缺口）——随 T6 同批尾块纯插入补齐，
   终值恰 10 新键（1946→1956）；zh-audit 双 PASS（source keys 1698→1708
   恰 +10 对账）。
8. **fixture 环境补注**：ToastFaceTests / ProjectReadOnlyFaceTests 两
   HostRoot 各 +1 `.environment(AgentControlCoordinator())`（WorkspaceHostView
   新读该环境——never-held 注入，面零漂移）。

## §4 红窗叙事（F4 正本）

无自动红窗——T1..T5 每任务 gate = 构建绿（五签名/box 缝就位 + 透传 nil
保编译零 diff）；union fixture 不传 control（makeUnionRegistry 全 nil）
+ get_state 逐键断言 + 穷举自建数组 = 三面在 T6 前全绿。守门 = T6 显式
改集中批 + 残漏 grep（`count, 29` / `count == 29` / `all29` 在
Tests/LightamerTests/Mcp* zero-hit 亲证）+ 本文件申报。执行期唯一红窗 =
T6 首轮 6 个新测试法失败（race 探针 task-group 阻塞 / 断言期望形三处 /
裸宿主 handles 序一处 / 注释 token 一处）——全部属新测试自身缺陷，回注
修复后 `--bundle App` 904/4/0 全绿；既有测试面零漂移。

## §5 M7-4 挂账路由对账（正本 = M7-4-VALIDATION §挂账）

| # | 件 | 本波处置 | 落点 |
|---|---|---|---|
| S-1 | 五处过时计数注释 | **四处 T5 清零 + union 文件两处 T6 清零**（S-1 全收口） | T5 `47737c1d` + T6 `f91d9aee` |
| S-2 | strerror clobber 一行 | **让渡下一 Export 波**（§3.3） | — |
| S-3 | 预热后首调实测 | **完成**（8.4 ms vs 50.2s） | evidence 分仓 `9b36b42` |
| S-4 | FIX2③ 维持注记 | **第四波维持**（§3.4） | 本文件 |
| S-5 | 观察项 A 卷归类勘误 | **无动作**（§3.5） | 本文件 |

## §6 快照权移交

union（`McpFinalSnapshotTests.swift`）改动权 M7-5 用讫——**移交 M7-6**
（串行禁并行注记延续；M7-6 若并行派发 = 停手上报）。

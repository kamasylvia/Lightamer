---
phase: 14
plan: "14-4"
title: "launcher + 收口签核（W3）：偏好 UI（模板/prompt/开关）+ launcher 动作（Process zsh -c + 占位符注入 + 串行 + SIGTERM→5s→SIGKILL）+ 日志面板（环形缓冲 2000 行/暂停/复制）+ 哨兵测试（注入逐字/串行/终止只及自家）+ 探针工具退役 + tools/list 终快照冻结（19 封闭集 + 白名单负例）+ SC 端到端全链 + 安全走查清单 + PROJECT.md 依赖漂移修正 + VALIDATION 签核（C 档第 3 停：VALIDATION + 翻账）"
wave: 3
depends_on: ["14-2", "14-3"]
autonomous: true
requirements: [MCP-10, MCP-02, MCP-04]
files_modified:
  - App/Sources/Lightamer/MCP/McpLauncher.swift                      # 新建：launcher 动作——模板占位符替换（{{LIGHTAMER_MCP}}/{{PROMPT}} 单引号转义）+ Process /bin/zsh -c + 串行门 + SIGTERM→5s→SIGKILL + Pipe 读行
  - App/Sources/Lightamer/MCP/McpServerController.swift             # 探针 toolset（ping/count_images）退役 + 非回环绑定偏好分支接线
  - App/Sources/Lightamer/UI/SettingsView.swift                     # MCP 节：server 开关 + agent 命令模板 + prompt 模板 + 非回环显式开启（风险明示）+ 默认模板占位文本
  - App/Sources/Lightamer/UI/McpLauncherPanelView.swift             # 新建：一键动作按钮 + 日志面板（TextEditor 环形缓冲 2000 行/暂停滚动/复制剪贴板）+ 终止按钮 + 状态提示
  - Tests/LightamerTests/McpLauncherTests.swift                     # 新建：哨兵测试——占位符替换逐字/单引号转义/串行拒绝/SIGTERM→SIGKILL 只及自家 pid/零写回 toast 语义
  - Tests/LightamerTests/McpFinalSnapshotTests.swift                # 新建：终快照 19 封闭集冻结 + 白名单负例（第 20 工具不存在）+ 探针面退役断言 + SC 全链终验
  - .work/gsd/phases/14-mcp-server/14-VALIDATION.md                 # 新建：SC#1-7 三列证据 + 签核（C 档第 3 停）
  - PROJECT.md                                                      # 依赖最小化约束漂移修正（swift-sdk + swift-nio 登记，收口批）
  - .work/gsd/phases/14-mcp-server/14-4-SUMMARY.md
  - .work/gsd/phases/14-mcp-server/14-4-DECISIONS.md
  - .work/REQUIREMENTS.md                                           # MCP-01..10 翻账 Delivered（签核批）
  - .work/GOAL-STATE.md                                             # Phase 14 翻账 + 续接点（签核批）
  - TODO.md                                                         # 14-4 勾选 + Phase 14 收口
  - LESSONS.md                                                      # 如踩坑
---

# Plan 14-4 — launcher + 收口签核（W3）

> 背景：MCP-10 主体 + 全 Phase 收口（D-14-CONTEXT-10/12）。三条主线：① **launcher**——
> 用户自担 shell 命令模板（用户 = 命令作者，注入面 = 自注入，文档明示即合规）+ 占位符
> `{{LIGHTAMER_MCP}}`/`{{PROMPT}}`（后者单引号包裹法转义后内联）+ `/bin/zsh -c` + app 侧
> 串行（研究项 A 前置：两 agent 并发写回无对策）+ SIGTERM→5s→SIGKILL 只及自家子进程
> （§8.5 自家子进程纪律）+ 日志面板；**与 EXP-08 显式不同源留痕**（EXP-08 `Process` 直 exec
> 不经 shell 是 app 内置动作故收窄路径制——`PostExportActions.swift:123-132`；launcher 走
> shell 是模板表达力的自觉选择，两处纪律不同源不混引，防审计误报与纪律漂移）；② **封闭面
> 收口**——探针工具退役 + tools/list 终快照 19 封闭集冻结（D3：以 research §A 表为正本）
> + SC 端到端全链 + 安全走查清单（公开仓审计注意项）；③ **签核**——VALIDATION + 翻账，
> **C 档第 3 停写在本 plan**：VALIDATION 产出后按夜间授权先例（D-07-3-T5-1 / D-09-05-T1-1
> / 11-05 D1）执行翻账（REQUIREMENTS/GOAL-STATE/TODO），晨审追认。
> 内部任务序刚性：T1（launcher 骨架）→ T2（日志面板+哨兵）→ T3（终快照+全链+走查+文档）
> → T4（VALIDATION+翻账签核）。

## read_first

1. `.work/gsd/phases/14-mcp-server/14-RESEARCH.md`——§RQ-14-12（**launcher 正本**：omp/pi
   默认模板示例/`{{PROMPT}}` 单引号转义法/日志面板 2000 行环形缓冲/终止 UX SIGTERM 5s
   SIGKILL/launch 失败 toast/非零退出红标/「本次会话无写回」/串行置灰）、§RQ-14-13（安全
   走查口径四条：绑定常量/token 比较/Origin pipeline 未禁用/工具白名单负例）、§RQ-14-14
   （生命周期）、§A（19 工具终表 = 终快照正本）、§D D1/D3/D6（依赖登记/19 终数/Origin 带
   端口文档）、§C 风险 R4/R8
2. `.work/gsd/phases/14-mcp-server/14-CONTEXT.md`——D-14-CONTEXT-10（launcher 全裁决：
   模板自担/占位符最小集/EXP-08 差异显式留痕/日志面板/串行/零 AI 代码）、D-14-CONTEXT-2③
   （launcher 路由 = agent 连 GUI 内嵌 HTTP 端点——GUI 恒持锁单写者）、D-14-CONTEXT-6（安全
   边界）+ 验证红线（launcher 注入面哨兵/串行断言/终止只及自家/L025 zh 键 smoke/SC 端到端
   全链）+ Boundary 事实 5（PROJECT.md 依赖漂移修正挂收口批）+ 事实 6（公开仓安全审计注意）
3. `App/Sources/Lightamer/UI/LightamerApp.swift`：`applicationWillTerminate`（:65）/
   Settings 挂点（:1087）；`App/Sources/Lightamer/UI/SettingsView.swift`（偏好 UI 载体——
   MCP 节挂入形态）
4. `App/Sources/Lightamer/Export/PostExportActions.swift`：Process 直 exec 先例（:123-132
   ——**对照正本**：launcher 与它不同源，注入纪律分别留痕）+ Pipe 读行形态（launcher
   stdout/stderr 读腿模板）
5. `.work/gsd/phases/14-mcp-server/14-1-SUMMARY.md` + `14-2-SUMMARY.md` + `14-3-SUMMARY.md`
   （若已落——终快照 19 工具的分域实况/SC#3 与 SC#5/6 已验段/探针面退役位）
6. `.work/gsd/phases/13-system-integration-distribution/13-VALIDATION.md`（VALIDATION 体例
   正本 + 公开仓形态：unsigned unhardened + 审计闸已立）
7. `PROJECT.md`：依赖最小化约束节（漂移修正位——16 期 PROJECT.md:65 先例同款：libavif 砍除
   + swift-sdk/swift-nio 入场后的约束文本修订）
8. `LESSONS.md` L010（accessibilityLabel 吞 AX）/L025（zh 标签）+ `AGENTS.md` + 
   `.work/GOAL-STATE.md`（Phase 14 续接点）

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits，英文 message，只 add 本任务申报
   文件）；**不 push**。
2. **构建纪律**：`caffeinate -dis` 包裹一切构建（`xcodebuild build-for-testing` 先行）；
   **构建勿加 `-derivedDataPath`**；**新建文件后跑 `tuist generate`**（T1 提交前一次，
   后续每新建文件同）。
3. **测试纪律**：单测命令 = `Scripts/test-direct.sh '<Class>'`；判据 = Executed 计数行 +
   failures 行（Executed 0 = 判据失败）。**回归基线 = 14-1..14-3 合并后最新**（读
   `.work/GOAL-STATE.md` 续接点取最新；0 fail 目标）；在案 flake（`LayerE2E`/`ToneEqual`
   负载型）隔离 ×3 归因单列入 SUMMARY，不计违约。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
5. **架构红线**：①**终止只及自家**——SIGTERM/SIGKILL 只对 launcher 自拉起且在册的子
   pid 下手（在册表校验；全局进程枚举式猎杀禁做，§8.5 自家子进程纪律）；②**注入面纪律
   留痕**——launcher 模板走 `/bin/zsh -c`（用户 = 命令作者，文档明示自注入）；与 EXP-08
   路径制分界写进两处代码注释 + 文档（防纪律漂移）；③**app 零 AI 代码**（MCP-10 用户
   裁决继承定案）——launcher 不含任何模型调用/提示词工程/provider 配置（prompt 模板是
   用户自己的文本，app 只替换占位符）；④**Metal 面**：本 plan 无新 iop/Metal 触点，
   L031 `makeRoutedCommandBuffer()` 红线不适用（如执行中发现需要即停下报告）；⑤L025：
   新 UI 键 zh 标签跟全库约定（zh 而非 zh-Hans），L025 smoke 数字随 suite 报；⑥L009：
   哨兵测试临时文件同目录 tmp，fixture 禁 UNITEK 盘。
6. **执行期决策登记**：模板存储键名、日志环形缓冲实现形态、launcher 面板挂点（工具栏/
   菜单/独立窗口）、非回环绑定 UI 文案等入 `14-4-DECISIONS.md`，不臆造。

## Tasks

### T1 偏好 UI + launcher 动作 + 探针工具退役

- **action**
  1. `SettingsView` MCP 节：server 开关（开即启动/关即停——14-1 已落偏好键读面与启停
     钩子，本任务接 UI 控件）+ agent 命令模板文本框（默认模板占位文本 = research
     §RQ-14-12 omp/pi 两例）+ 任务 prompt 模板（可选）+ 非回环显式开启 toggle（开启后
     绑定 0.0.0.0 + **Bearer 必须**自动生效 + 风险明示文案「监听接口将暴露至局域网，
     鉴权 token 将强制启用」；具体网卡选择 UI = v2 精细化不做）。
  2. 新建 `McpLauncher.swift`：模板处理——先占位符替换（`{{LIGHTAMER_MCP}}` = 端点发现
     文件路径；`{{PROMPT}}` = prompt 模板内容经 **shell 单引号包裹法**（`'` → `'\''`）
     转义后内联；无 prompt 模板则该占位符替换为空串并提示），再整体交
     `Process` → `/bin/zsh -c "<替换后模板>"`；环境变量注入发现文件路径。
  3. **串行门**：进行中再点 = 按钮置灰 + 「已有一个 agent 会话进行中」提示（app 侧至多
     1 个 agent 进程——研究项 A 前置）。
  4. **终止 UX**：进行中显示「停止」→ SIGTERM → **5s 超时 SIGKILL**（只对在册自家 pid）；
     launch 失败（executable 不存在）= toast + 日志行；非零退出 = 日志尾部红色标注退出码；
     优雅收尾 = 任务完成 toast；写回零结果时显示「本次会话无写回」（agent 是否听话不作
     断言——诚实条款）。
  5. **探针工具退役**：`McpServerController` 移除 ping/count_images 注册（14-1 DECISIONS
     登记的退役时点兑现）——probe 域快照段同步退役断言（MCP-01 封闭集 19 工具不含探针面）。
  6. zh/en 键入 String Catalog（L025 zh 标签）。
- **证据**：`McpLauncherTests`——占位符替换逐字（含 `{{PROMPT}}` 内含单引号/反引号/
  `$()` 元字符的转义往返）+ 串行拒绝 + 可执行不存在 toast 语义；探针面退役断言。

### T2 日志面板 + 哨兵测试全量

- **action**
  1. 新建 `McpLauncherPanelView.swift`：Pipe 读行（stdout+stderr 合流）→ SwiftUI
     TextEditor；**环形缓冲 2000 行**（超限裁头）；暂停滚动开关（滚动跟随 toggle）；
     导出 = 复制全文到剪贴板（v1 不做文件导出）。
  2. 哨兵测试全量（CONTEXT 验证红线「launcher 注入面」字面）：模板执行哨兵——用
     `echo`/`cat > 哨兵文件` 型安全模板实测端到端（环境变量注入可达/占位符逐字到达子
     进程/转义后特殊字符原样到达）；**串行断言**（第二动作拒绝）；**终止只及自家**（拉起
     sleep 子进程 → 停止 → 断言仅该 pid 被终止、无越界杀——在册表负例：终止不在册 pid =
     拒绝）。
  3. L010 自检：按钮/开关 accessibilityLabel 不吞子元素 AX（哨兵测试 AX 断言或走查记录）。
- **证据**：`McpLauncherTests`——哨兵三件（注入逐字/串行/终止只及自家）+ 在册表负例 +
  缓冲 2000 行裁头断言 + 暂停/复制语义。

### T3 终快照冻结 + SC 端到端全链 + 安全走查 + PROJECT.md 漂移修正

- **action**
  1. **tools/list 终快照冻结**（`McpFinalSnapshotTests`）：并集 = **19 工具封闭集**逐字
     （正本 = research §A 表：4 修图 + 4 筛选读 + 2 culling 辅助 + 5 筛选写 + 3 预设 +
     1 导出；D3 终数）；每工具 inputSchema 键集 + annotations（readOnlyHint/destructiveHint
     与 §A 列一致）+ zh/en 描述键存在；**白名单负例**：构造第 20 工具调用 → 方法不存在
     错误（工具面即安全面）；分域快照（editing 5/culling 14）与终快照一致。
  2. **SC 端到端全链**（SC#3 + SC#5/6 已验段接线复验 + SC#7 字面）：HTTP 宿主起 →
     launcher 拉起哨兵 agent（安全模板：读端点文件 → 连 MCP → list_photos → set_rating
     写回 → 退出）→ 写回落 sidecar + GUI 缩略图 stale 再生同步可见 + 日志面板捕获 agent
     文字流 + 停止按钮可用；「外部任意 MCP client 直连与 launcher 双入口并存」断言（SDK
     client 直连同一端点并行第二 session，上限 4 内）。
  3. **安全走查清单**（§RQ-14-13 口径四条 + 公开仓审计注意，逐条输出入 SUMMARY）：
     绑定常量走查（127.0.0.1 无设置项可改到底线常量；非回环 = 显式 toggle + Bearer 自动
     强制）；token 比较常量时间（源码走查 + 测试在案）；Origin pipeline 未被禁用（构造
     请求实测 403 仍绿）；工具白名单负例（T3-1）；**公开仓专项**：token 生成不落日志/
     端点文件无 token 真身/keychain 拼写无敏感串硬编（gitleaks 面自查）。
  4. **PROJECT.md 依赖漂移修正**（收口批，同 16 期先例）：依赖最小化约束文本修订——
     swift-sdk（+传递 swift-nio/swift-log/swift-system/eventsource）登记为第三个 SPM 依赖
     事实；libavif 已砍除的现状对齐。
  5. 工具文档收口：Origin 匹配带端口示例（D6——`http://localhost:<port>` 形态）、
     render_preview「编辑态预览，无印框」诚实条款、MCP-03 口径（sRGB 编码域，GUI EDR 域
     不对齐）在 README/工具描述落位。
- **证据**：`McpFinalSnapshotTests`——终快照 + 负例 + 双入口并存；SC#7 全链走查记录；
  安全走查四条 + 公开仓专项输出；PROJECT.md diff。

### T4 VALIDATION 签核 + 翻账（C 档第 3 停）

- **action**
  1. 全 suite 终轮（基线 = 14-3 合并后最新 + 本 plan 新增，0 fail）。
  2. 新建 `14-VALIDATION.md`（13-VALIDATION 体例）：SC#1-7 逐条三列证据（SC/证据/指针）
     + MCP-01..10 覆盖矩阵 + Manual-Only 汇总（launcher 真机一键动作/日志面板观感/非回环
     局域网实机验证等人工走查行）+ 缺陷处置记录。
  3. **翻账**（签核批，C 档第 3 停 = 夜间授权先例，晨审可推翻）：`.work/REQUIREMENTS.md`
     MCP-01..10 翻 Delivered + Traceability 表 + 覆盖计数；`.work/GOAL-STATE.md` Phase 14
     翻账 + 续接点更新；TODO.md Phase 14 收口；`14-4-SUMMARY.md`（任务表/commit 表/安全
     走查输出/SC 证据指针）+ `14-4-DECISIONS.md`（模板键名/面板挂点/其余执行期决策）；
     新教训候选评估入 LESSONS。
- **证据**：VALIDATION `status: validated`（+ nyquist 面按体例）；翻账三文件 diff；终轮
  计数（0 fail）；SUMMARY + DECISIONS 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| launcher 骨架 | 占位符/转义逐字 + 串行拒绝 + 探针退役 + 停止 UX | `Scripts/test-direct.sh 'McpLauncherTests'` |
| 日志面板 | 环形缓冲 2000 行/暂停/复制/终止只及自家（在册表负例） | `Scripts/test-direct.sh 'McpLauncherTests'` |
| 终快照 | 19 封闭集逐字 + 第 20 工具负例 + 分域一致 + annotations | `Scripts/test-direct.sh 'McpFinalSnapshotTests'` |
| SC#7 全链 | launcher 端到端（拉起 → 写回 → GUI 可见 → 日志捕获）+ 双入口并存 | `Scripts/test-direct.sh 'McpFinalSnapshotTests'`（全链段） |
| 安全走查 | 绑定常量/token 常量时间/Origin 403/白名单负例/公开仓专项五条输出 | `Scripts/test-direct.sh 'McpHostTests'`（14-1 回归）+ SUMMARY 走查记录 |
| L025 | 新 UI 键 zh 标签 smoke | 全 suite 内 String Catalog smoke + 计数入 SUMMARY |
| 回归 | 全 suite 0 fail（基线 + 新增） | `caffeinate -dis Scripts/test-direct.sh`（全套） |

## 验收标准（Acceptance）

- [ ] 偏好 UI：server 开关（开即启动/关即停接 14-1 钩子）+ 模板/prompt 文本框（默认占位
      示例 omp/pi）+ 非回环显式 toggle（0.0.0.0 + Bearer 强制 + 风险明示）+ zh/en 键
- [ ] launcher：占位符替换逐字（`{{PROMPT}}` 单引号转义往返）+ `/bin/zsh -c` + 串行门
      + SIGTERM→5s→SIGKILL 只及在册自家 pid + 非零退出红标 + 「本次会话无写回」诚实
      toast；EXP-08 不同源分界双留痕（注释 + 文档）
- [ ] 日志面板：2000 行环形缓冲/暂停滚动/复制剪贴板
- [ ] 探针工具退役 + **终快照 19 封闭集冻结**（§A 正本逐字；第 20 工具白名单负例；
      annotations 与 §A 一致）
- [ ] SC#7 launcher 端到端绿（拉起 → agent 经端点写回 → sidecar + GUI stale 再生同步可见
      → 日志捕获）+ 双入口并存（直连 client 第二 session）
- [ ] 安全走查五条全绿（绑定常量/token 常量时间/Origin 未禁用/白名单负例/公开仓 token
      不落盘专项）——输出入 SUMMARY
- [ ] PROJECT.md 依赖漂移修正落盘（swift-sdk + 传递依赖登记，16 期先例同款）
- [ ] `14-VALIDATION.md` SC#1-7 三列证据 + MCP 覆盖矩阵 + Manual-Only 汇总；翻账三文件
      （REQUIREMENTS/GOAL-STATE/TODO）；**C 档第 3 停执行留痕（晨审可推翻）**；全 suite
      0 fail；每任务独立提交 + 边界查开关；不 push；SUMMARY + DECISIONS 落盘

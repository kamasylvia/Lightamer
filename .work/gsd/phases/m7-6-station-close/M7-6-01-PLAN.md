---
phase: m7-6-station-close
plan: "M7-6-01"
title: "M7 站收官单 plan——T1 三缺陷（major-1 setControlAdmit 四宿主透传参案 + minor-1 裸 stdio/http 臂 agentControl 两行 + obs-3 acquire 循环退出后复检硬化〔快照+条件复检三行，review B1〕）/ T2 UQ-A1 预览层 ICC 双曲线失配（legal SDR 对换挂导出同款 ICC v4 + 域外 calibrated 回落 + 解码等值测试）/ T3 UQ-L1 滑杆横扫 scrub（LightamerSlider readout DragGesture + 纯函数映射 + D-H1 三段回调复用）/ T4 SKILLS-01 skills 文档仓（仓内 skills/lightamer-mcp/，SKILL.md 人写 + references 机检测试即门 + en 单语）/ T5 定向轮 + 全套 --all 对账（预批）+ 红线族亲跑 + 走查配方 / T6 站级 M7-VALIDATION + 台账翻账（五 phase 收口矩阵 + SC 翻账 + 制度偏离登记）"
wave: 1
depends_on: []
autonomous: true
requirements: ["REQUIREMENTS SKILLS-01（:452）+ UQ-A1/UQ-L1（:458/:460，→ M7-6）+ ROADMAP §M7-6 行（验收形态：skill 仓机检 reference 生成 ✓ / UQ-A1 解码等值测试 ✓ / UQ-L1 交互走查 ✓ / SC 数字门 = 站终验全套轮判定式兑现）", "M7-5 遗留正本 = phases/m7-5-turn-taking/M7-5-SUMMARY.md §Leftovers（major-1/minor-1/obs-3 三缺陷 + union 改动权移交 + M7 站 VALIDATION 收口含 M7-5 签核）+ GOAL-STATE 续接点 2026-10-17 条（scope 六项定案）", "OQ 裁决正本 = phases/m7-6-station-close/M7-6-CONTEXT.md（D-M7-6-1..10 全按 RESEARCH §7 推荐，站 charter 授权落定，晨审可推翻）", "调研正本 = phases/m7-6-station-close/RESEARCH.md（§1 SKILLS-01 / §2 UQ-A1 / §3 UQ-L1 / §4 三缺陷 / §5 VALIDATION / §6 切分 / §7 OQ / §8 证据索引；file:line 经 planner 2026-10-17 HEAD 07927ab2 逐点亲核复核吻合——转写勘正五条见本 plan 头注）", "夜间全自动授权在案（先例 D-07-3-T5-1；晨审可推翻）；全套 --all 轮 plan 期 orchestrator 已预批"]
success_criteria: "SC 全可机检——T1：三宿主（startReadOnlyHTTPHost :722 / startHeadlessStdioHost :786 / startHTTPHost :1035）+ startEmbeddedIfPreferenceEnabled :1137 各恰 +1 `admit` 缺省 nil 透传参 + EmbeddedState box 恰 +1 admit 字段 + startEmbeddedServer :1165 读出透传 + 每宿主函数体 setWriterCheck 调用点（:737/:819/:1081）之后恰 +1 `if let admit { await registry.setControlAdmit(admit) }`——setControlAdmit 生产调用恰 3 点（embedded 无自有 registry、整段委托 startHTTPHost :1176，经 box→startHTTPHost 复用 :1081 单点装配，无独立安装点；App/Sources grep `setControlAdmit` 恰 5 处 = 定义 :367 + ControlToolset :20 头注字样 + 三调用点——grep 构成按此核，头注命中不计调用点——review M1）+ GUI 装配点恰一处 admit 闭包（coordinator-backed，acquire provider plain-await hop 同款）+ 无头臂生产调用点 admit 缺省 nil 字节零 diff + minor-1 = McpServerController :482/:497 两处 makeHeadlessSearchState 调用各补 `agentControl: { McpControlState.headlessConstant }`（与 :603-606 arbitrated 臂拼写逐字同形）+ obs-3 = AgentControlCoordinator acquire 等待循环（:227-240）前恰 +1 入口快照行（`let stoppedAtEntry = stoppedByUser`）+ 循环退出后、success 路径前恰 +2 条件复检行（revoked 臂 `stoppedByUser, !stoppedAtEntry` 才拒——入口已 stopped = TURN-03 resume 语义放行清零；busy 臂保持无条件 `held ∧ holderName != holderName`——两 throw 拼写与循环内既有臂逐字同构；或等价终形 DECISIONS 申报——review B1）+ 测试腿 ≥4（真宿主未 acquire 直调 apply_params → controlNotHeld〔McpHostTests 扩〕/ 裸臂 get_state agent 非 null〔McpSearchStateToolsetTests 扩〕/ obs-3 两变体 revoked+busy + resume 不断裂负腿〔AgentControlCoordinatorTests 扩——review B1〕）+ 构建绿；T2：drtLayerColorSpace SDR 幂臂两段式（legal 对 try? DrtOutputColorSpace.drtOutputColorSpace → 返回导出同款 ICC v4 实例；typed throw 域外对回落现行 calibrated 构造）+ HDR/linear 臂零改（diff 面核 :734-748 段零触）+ Core DrtOutputColorSpace.swift 零 diff + 等值测试（legal SDR 8 对逐对〔review m1〕preview space === export space 同实例 + ICC data 逐字节同 + ramp 采样等值 ≤1 LSB @8bit〔实现形可 DECISIONS 申报——同实例蕴含等值时 ramp 腿可收敛为字节同断言〕）+ 域外负腿（rec709×gamma18 / p3d65×bt1886 非 nil 且走 calibrated 回落）+ srgbPiecewise legal 对断言 ICC data == Core curv 1024 采样表形（非 2.2 幂）+ 构建绿；T3：scrub 纯函数 session 值类型（travel→value 映射 + Shift ×0.1 + range clamp——golden 测试族）+ readout Text 挂 DragGesture(minimumDistance: 3)（scrub begin → onDragBegin / per-tick → onChange / end → onDragEnd——D-H1 三段回调复用 grep 断言零旁路）+ 既有双击重置 onReset 行为零触（:72-74）+ AX identifier 三处零改（:47/:63/:69）+ denoise 旁路面零 diff（EditorState.previewDenoiseBypass 所在文件零触）+ MonochromePanelView 零 diff（D-M7-6-5）+ xcstrings 恰 +1 键 slider_scrub_hint 尾块纯插入（或零键 DECISIONS 申报）+ 构建绿；T4：skills/lightamer-mcp/ 三文件落位（SKILL.md 七节骨架人写 en 单语 + references/tools.md 机检生成 + references/errors.md 19 码表）+ SkillsReferenceTests 两法绿（tools.md vs 活注册表渲染逐字节 + errors.md 19 码名逐一断言）+ McpFinalSnapshotTests.swift diff 恰一行（makeUnionRegistry private→internal）+ union 32 断言面零触（全测试绿）+ skill 目录中文字符 grep 零命中（en 单语机检）+ N2-2 句 grep 在 SKILL.md + README 一句链接 + 构建绿；T5：--bundle App 定向轮绿 + 全套 --all = TOTAL|3950+ΔN/35/0| 对账闭合（预期带 3959..3964〔review R2 带边随 B1 重导〕 / exit 0 / 0 MEMFAIL / 七 bundle 8G 门内〔预批在案〕）+ skip 35 构成声明 + zh-audit --check PASS（+1 键对账）+ --self-test PASS + 红线族 11 项逐条亲跑 PASS + 走查配方落盘 .work/gui-acceptance/m7-6/MANIFEST.md；T6：M7-VALIDATION.md 落盘（front-matter 对齐 M7-1 体例 + 五 phase 收口矩阵 + 红线族复检记录 + SC 翻账〔skill 机检 ✓ / UQ-A1 等值 ✓ / UQ-L1 走查配方就绪 ✓ / 全套数字门 ✓〕+ 制度偏离登记〔omp→双 zcode / m7-5 载体偏差 / UQ-L1 SC 降格注记——review m4〕+ M7-5 §signed 节 + 挂账清算面〔N2-2 收口 / S-2 维持 / obs-A C12 注记一行 / FIX2③ 第五波维持 / union 权用讫归还 M8〕）+ 四台账一 AGENTS 同批翻账（ROADMAP M7-6 行闭环 / REQUIREMENTS SKILLS-01+UQ-A1+UQ-L1 Delivered / TODO / GOAL-STATE / AGENTS.md M7-6 架构增量节）"
estimated_tests: "+8..13（预期 +13：T1 = 6〔major-1 真宿主 controlNotHeld 1 + 无头臂端到端 nil 恒放行 1〔若与既有负测同语义 = DECISIONS 申报合并让渡，带下限 4〕+ minor-1 裸臂 agent 非 null 1 + obs-3 两变体 2 + resume 不断裂负腿 1〔review B1：5→6〕〕+ T2 = 2〔legal 8 对等值 1〔review m1〕+ 域外回落负腿 1〕+ T3 = 3〔travel→value 映射族 1 + Shift/clamp 族 1 + session begin/end 配对 1，带 2..4〕+ T4 = 2〔tools.md 逐字节 1 + errors.md 19 码名断言 1，带 1..2〕；3950 → 预期 3963，带 3959..3964〔review R2：带边随 B1 重导，T1 带 3..5→4..6，组件和 +9..14〕；执行时逐任务如实记账，越带申报理由）"
test_bundles: [APP]
baseline: "3950/35/0（M7-5 三路全套同值，exit 0 零 MEMFAIL；skip 35 = 24 基线 + 11 RAW 供件缺失；其后 58c3a78a〔M7-5 收口 docs〕+ 17b9a6c2 + 07927ab2〔本 phase research docs〕docs-only 零漂移；HEAD 07927ab2 planner 2026-10-17 亲核 git log/status——其上零产线文件）"
expected_all: "3950 + ΔN（对账式；ΔN 预期 +13〔review B1〕、带 +9..14 → 终值带 3959..3964〔review R2 带边重导〕，执行时按实记账；skip 35 口径维持——第三种 skip 来源 = 逐族差分申报禁静默吸收）"
red_lines:
  - "union 快照串行（本波持权——M7-5 移交）：McpFinalSnapshotTests.swift 32 基线 + 五钉 23（editing 9 + culling 14）维持，union 内容零 diff 为预期态；唯一预期 diff = makeUnionRegistry 可见性提升 private→internal 恰一行 additive（T4 机检新文件复用活注册表——实测 :277 为 private）；若执行中确需改 union 内容/计数断言（六项均不增删工具，不该发生）= 立即停手上报禁自裁；本波持权窗口内禁并行派发任何波（orchestrator 编排保证——误并行派发立即停手上报，禁抢先合并快照表）；窗口用讫归还 M8（T6 VALIDATION 登记移交注记）"
  - "零新 SPM 依赖（Project.swift dependencies 块零 diff；Project.swift 仅测试登记行恰三行 additive——EditorPreviewColorSpaceTests / LightamerSliderScrubTests / SkillsReferenceTests 全 APP 域 + BUNDLE-MAP 恰三行 + tuist generate 恒为该批最后一个动作〔L041〕）"
  - "封存面零触：DrtRecord / TerminalTailPolicy / DrtTailAssembly / PixelPipe / Lut3dKernels.metal / DrtEotf / ExportQueueContract / 六格式导出矩阵（ExportFormatSpec·ImageIOEncoders·WebPEncoder）/ NodeGraphCommand / sidecar schema（LightamerSidecar）/ HistoryStack / HistoryHash / PipelineDocument（Core）/ V50Order / GradeCatalog（NodeOwnershipCatalog）/ Registry / ModuleInstance；零新 .metal（全域零 diff）；受限修改面两条：EditorMTKView 仅 drtLayerColorSpace SDR 幂臂段（UQ-A1 两段式——HDR/linear 臂 :734-748 零改、drtSurfaceSpec :804-811 零触、函数外零触）；AgentControlCoordinator 仅 acquire 等待循环退出后快照 + 复检三行（obs-3——入口快照 1 行 + 条件复检 2 行〔review B1〕；admit/stop/release/activity/resume 面零触、:215-217 入口 busy 检查零触）"
  - "FIX2③ = LibraryProjectController.swift 文件零 diff 第五波维持（planner 勘正：RESEARCH §0 原文「本批修法落点均不触 McpServerController 的 controller 面」为笔误级混淆——FIX2③ 正义 = LibraryProjectController 零 diff〔M7-5-CONTEXT 红线⑥正本，连续四波亲证〕；本波六项无 project 门面，零 diff 可达；McpServerController.swift 是本波合法修改面〔major-1 四宿主签名批 + minor-1 裸臂两行〕——DECISIONS 申报逐 hunk 清单即可，红线只核：宿主签名 additive 缺省 nil、既有调用点编译零改、control/admit 既有面零漂移）"
  - "错误码 19 档封闭表零触（六项零新错误码——obs-3/major-1 typed 拒复用 controlRevokedByUser/controlBusy 既有三码既有文案键）；McpTimeouts 零新档零改档；既有 32 工具 descriptor/handler 零 diff（union golden 双证门）；writeCallCount 面零触（setControlAdmit 装配不增计——M6-1 语义维持）；get_state 既有键族值与形零漂移（minor-1 仅裸臂 provider 缺省参接线——arbitrated 臂 :603-606 与 GUI 臂零触）"
  - "xcstrings 恰 +1 键（slider_scrub_hint——T3 readout AX hint；若执行裁定零提示 = 零键，DECISIONS 申报）尾块纯插入，历史键字节与顺序零触碰；skill 文档 en 单语不入 xcstrings 不入 zh-audit 面（D-M7-6-2 豁免申报）；zh-audit --check（source keys +1 对账）+ --self-test 双 PASS"
  - "UserDefaults 零新键预期（scrub 无持久化面、skills 文档无偏好键；若执行中确需 = 同纪律登记 + DECISIONS 申报）"
  - ".runModal( 在 App/Sources 零命中（L057 禁令）；LocalizationValue 插值禁形代码零命中（新键一律 String(localized: 静态键, defaultValue:) 显式形态——禁 String.LocalizationValue(\"prefix_\\(x)\" 插值形，M2-9 F-2 禁令）"
  - "Alcedo GPL-3.0 文档/代码零复制零翻译（SKILLS-01 SKILL.md/references 全部自写 en 文案——只对表形态与清单事实）；零 taste 规则进 skill 文档（taste 留 launcher {{PROMPT}} 载体）；lightcraft MIT——UQ-L1 只对表交互语义（3pt 阈值/Shift 1/10/一个 undo step），预期自写零成段移植（若成段移植 = NOTICE 归属同 commit 登记 + DECISIONS 申报）"
  - "T3 旁路面零触：EditorState.previewDenoiseBypass 所在文件零 diff（denoise 拖动降档三道防线经 drag begin/end 投影与 commit 自愈自然兼容——scrub 复用同三回调面零额外接线）；LightamerSlider AX identifier 三处（:47/:63/:69）与既有 onReset 双击路径（:72-74）零改"
  - "构建 caffeinate -dis 包裹；单测 = Scripts/test-direct.sh --bundle App 定向；全套 --all 本 plan 期 orchestrator 已预批（运行中保持监视 + 8G 门 + MEMFAIL 机检，超门立即 kill）；测试宿主清理先核 parentage（ps -o ppid——测试宿主 parent = 脚本进程树，GUI 实例 parent = launchd，M2-7-3 先例）"
files_modified:
  - App/Sources/Lightamer/MCP/McpServerController.swift            # T1：major-1 签名批——三宿主 startReadOnlyHTTPHost :722 / startHeadlessStdioHost :786 / startHTTPHost :1035 各恰 +1 `admit: (@Sendable (_ toolName: String) async throws -> Void)? = nil` 透传参 + startEmbeddedIfPreferenceEnabled :1137 恰 +1 同名缺省参 + EmbeddedState box 恰 +1 admit 字段（control 字段 :1143-1150 同款第六缝形）+ startEmbeddedServer :1165 box 读出透传 + 每宿主函数体 setWriterCheck 调用点（:737/:819/:1081）之后恰 +1 `if let admit { await registry.setControlAdmit(admit) }`——生产调用恰 3 点，embedded 无独立安装点（startEmbeddedServer :1165 无自有 registry、整段委托 startHTTPHost :1176，经 box→startHTTPHost 复用 :1081 单点——review M1）；minor-1：:482 / :497 两处 makeHeadlessSearchState(mode: mode) 各补一行 `agentControl: { McpControlState.headlessConstant }`（与 :603-606 arbitrated 臂逐字同形）；无头臂生产调用点 admit 缺省 nil（字节零 diff）
  - App/Sources/Lightamer/UI/LightamerApp.swift                    # T1：GUI 装配段（:1632-1651 startEmbeddedIfPreferenceEnabled 调用）恰 +1 `admit:` 参——闭包 = coordinator-backed `{ name in try await agentControl.admit(toolName: name) }`（acquire provider :1634-1637 plain-await MainActor hop 同款先例形 + 同款注释）
  - App/Sources/Lightamer/State/AgentControlCoordinator.swift      # T1：obs-3——acquire 等待循环（:227-240 while）前恰 +1 入口快照行 `let stoppedAtEntry = stoppedByUser` + 循环退出后、success 路径（:248-267 resume 路由段）之前恰 +2 条件复检行：revoked 臂 `if stoppedByUser, !stoppedAtEntry { throw McpToolError.controlRevokedByUser(…同 :228-231 文案形) }`（入口已 stopped = TURN-03 resume 语义放行清零——review B1）+ busy 臂 `if held, self.holderName != holderName { throw McpToolError.controlBusy(…同 :215-217 文案形) }`（无条件安全）；〔或等价终形 DECISIONS 申报〕；acquire 其余段/stop/release/admit/activity 零触
  - App/Sources/Lightamer/UI/EditorMTKView.swift                   # T2：drtLayerColorSpace :732 SDR 幂臂（:749-798 段）两段式——对每个 SDR eotf case 先 `try? DrtOutputColorSpace.drtOutputColorSpace(space: record.encodingSpace, eotf: eotf)`（Core public，nil 即域外 typed throw）→ 非 nil 返回导出同款 ICC v4 实例；nil → 回落现行 calibratedRGBWhitePoint 构造（现行 switch 逐 case 保留为回落臂）；HDR 臂 :734-746 / linear 臂 :748 零改
  - App/Sources/Lightamer/UI/Inspector/LightamerSlider.swift       # T3：readout Text（:65-69）挂 DragGesture(minimumDistance: 3)——scrub session 值类型（internal 纯函数：began(x:)/tick(x:shift:)/end()，travel→value 映射 + Shift ×0.1 + range clamp）+ trackWidth 经 GeometryReader/onGeometryChange 就地测量 + began → onDragBegin() / per-tick → onChange(value) / end → onDragEnd()（D-H1 三段复用）+ readout accessibilityHint（slider_scrub_hint 键）；:47/:63/:69 AX identifier 与 :72-74 onReset 双击零改
  - Resources/Localizable.xcstrings                                # T3：恰 +1 键 slider_scrub_hint 尾块纯插入（zh-only 形；历史键零触碰）
  - skills/lightamer-mcp/SKILL.md                                  # T4 新建：front-matter（name: lightamer-mcp + description: Use when ...——Alcedo 形态对表，文案自写）+ 七节骨架 en 单语：①Installation & session start（GUI mcp-endpoint.json 发现〔McpEndpointFile :61-75 schema v1 九字段——schemaVersion/transport/host/port/pid/startedAt/serverName/serverVersion/auth + auth none/bearer；loopback 零 token/.lan 强制 Bearer McpServerController :1046-1065——review m3〕→ stdio client 配置模板；裸 --mcp-stdio/--mcp-http〔runHeadless〕；launcher {{LIGHTAMER_MCP}}+{{PROMPT}} 模板）②Turn-taking 语义（先 control_acquire 再写、13 工具 admit 面、错误码三控制码语义与恢复动作、Stop = 用户收回 + 同 holder re-acquire = resume、等待编辑输入封合期间被 Stop → re-acquire 得 controlRevokedByUser〔非静默吞——review B1 诚实面〕、无头臂恒持有〔ControlToolset :1-60 头注 + AgentControlCoordinator :178-268 对表〕）③工具五域边界（editing 9 / culling 14 / searchstate 3 / project 3 / control 3——哪域改像素哪域只读、哪些需要 project）④错误码表指针（→ references/errors.md）⑤render_preview 语义（编辑态无印框 = M2 页域差异；compare:root 前后对照；region 归一化 0..1 相对渲染输出帧、crop 在 render 后）⑥UI 单位说明（滑杆 range 单位与 params 数值域映射——从 list_iops schema 读）⑦已知面（N2-2：get_state project 字段 GUI/headless 两臂不对称句——如实陈述）
  - skills/lightamer-mcp/references/tools.md                       # T4 新建：32 工具表机检生成（name / domain / readOnlyHint / schema 全文 / description）——初版由渲染器产出（executor 经临时脚手架调 SkillsReferenceTests 渲染函数写盘），此后测试即门锁漂移
  - skills/lightamer-mcp/references/errors.md                      # T4 新建：19 错误码表（人写 en：码名 / code / 语义一句 / 恢复动作一句——三控制码 controlNotHeld/controlRevokedByUser/controlBusy 恢复动作句对表 ControlToolset 语义自写）
  - Tests/LightamerTests/McpHostTests.swift                        # T1 扩：major-1 真宿主腿——startHTTPHost 带 admit stub，未 acquire 直调 apply_params → controlNotHeld（现状落 handler internalError 的 e2e 实锤面翻转）
  - Tests/LightamerTests/McpControlToolsetTests.swift              # T1 扩（可选）：无头臂端到端 nil admit 恒放行负腿——若与既有无头恒持有负测同语义 = DECISIONS 申报合并让渡（ΔN 带下限承载）
  - Tests/LightamerTests/McpSearchStateToolsetTests.swift          # T1 扩：minor-1 腿——裸臂 makeHeadlessSearchState(mode: .stdio)（无 projectWriteProbe）的 agentControl provider 非 nil 且返回 headlessConstant（:1015 既有直调先例同文件扩展）
  - Tests/LightamerTests/AgentControlCoordinatorTests.swift        # T1 扩：obs-3 两腿——①liveEditActive=true → 等待循环中 stop() → provider 翻 false → expect controlRevokedByUser（Stop-in-final-window）②等待期间异 holder acquire 先完成持有 → 本 waiter 循环退出复检 → expect controlBusy（交错控制经注入 provider + 显式 Task 序——DECISIONS 申报终形）③resume 不断裂负腿：acquire → stop() → 同 holder re-acquire（liveEditActive 恒 false 注入）→ expect 成功且 taskId 复用（resume——B1 回归拦截腿，review B1）
  - Tests/LightamerTests/EditorPreviewColorSpaceTests.swift        # T2 新建：legal SDR 8 对〔review m1〕（rec709×{bt1886,gamma22,srgbPiecewise} + p3d65×{gamma22,srgbPiecewise} + p3d60×gamma26 + p3dci×gamma26 + xyz×gamma26）逐对 preview space（drtLayerColorSpace 经 record）=== export space（drtOutputColorSpace）同实例 + ICC data 逐字节同 + ramp 采样等值（≤1 LSB @8bit——实现形 DECISIONS 申报）+ 域外负腿（rec709×gamma18 / p3d65×bt1886 非 nil 走回落）+ srgbPiecewise 对断言真分段表形
  - Tests/LightamerTests/LightamerSliderScrubTests.swift           # T3 新建：scrub session golden——travel→value 映射族（零位移恒等/正向/负向/range 双侧 clamp）+ Shift ×0.1 族 + begin/end 配对计数（一次 scrub = onDragBegin 恰 1 + onDragEnd 恰 1 + onChange 序列 = 一次连续 commit 语义）——纯值类型驱动不驱动 UI（M3-1 YiyinSheetDragSession AC 可机检缝范式）
  - Tests/LightamerTests/SkillsReferenceTests.swift                # T4 新建：法 1 = 活注册表渲染 markdown vs skills/lightamer-mcp/references/tools.md 逐字节比对（makeUnionRegistry internal 复用）+ 法 2 = errors.md 19 码名逐一出现断言（码名清单硬编码循环）；渲染函数 = 文件内 internal static（初版生成通道）
  - Tests/LightamerTests/McpFinalSnapshotTests.swift               # T4：恰一行 diff——makeUnionRegistry :277 `private func` → `internal func`（additive 可见性提升，union 内容/断言面零触——本波持权行使申报点）
  - README.md                                                      # T4：一句链接（skills/lightamer-mcp/ agent 文档入口）
  - Project.swift                                                  # T2/T3/T4：恰三行测试登记（三新测试文件 → LightamerTestsApp 数组；tuist generate 恒末位）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt     # T2/T3/T4：恰三行（APP 域）
  - .work/gui-acceptance/m7-6/MANIFEST.md                          # T5：走查配方（UQ-L1 双击重置/横扫 scrub/Shift 细调/一个 commit 面板观察行 + UQ-A1 srgbPiecewise 预览观感微移观察行〔预期行为变化非缺陷〕+ major-1 e2e 执法腿观察行 + 拖离取消让渡观察行〔scrub 中拖离 = 不取消、残值留驻——lightcraft 语义让渡已申报，review m5〕——实机走查归验收批/用户）
  - .work/gsd/phases/m7-6-station-close/M7-6-01-SUMMARY.md         # T5：执行摘要（逐任务 ΔN 记账 + 验收形态判定指针 + 越带申报）
  - .work/gsd/phases/m7-6-station-close/M7-6-01-DECISIONS.md       # T5：裁定记录（FIX2③ 勘正承接 + makeUnionRegistry internal 一行申报 + obs-3 交错控制终形 + T2 等值测试实现形 + T3 trackWidth 测量终形 + xcstrings 键数终账 + RESEARCH §3.1 yiyin 勘正假阴性留痕勘误申报〔review M2〕+ 若干让渡/合并申报）
  - .work/gsd/phases/m7-6-station-close/M7-VALIDATION.md           # T6 新建：站级 VALIDATION（front-matter 对齐 M7-1 体例，phase: M7 站；五 phase 收口矩阵 / 红线族 11 项复检记录 / SC 翻账 / 制度偏离登记 / M7-5 §signed 节 / 挂账清算面）
  - .work/gsd/ROADMAP.md                                           # T6：M7-6 行翻账（✅ 闭环 + ΔN 终值 + M7 站收口标注——历史行只追加不改写惯例）
  - .work/gsd/REQUIREMENTS.md                                      # T6：SKILLS-01 / UQ-A1 / UQ-L1 → Delivered（M7-6 commit 指针；UQ-L1 范围勘注 = LightamerSlider 全部调用点〔iop + yiyin 面板族，177 处——yiyin 八处 :160/:182/:203/:235/:268/:380/:393/:589 实测在册〔review R1 计数勘正 3→8〕，RESEARCH §3.1 勘正为 grep 假阴性，review M2 翻转〕）
  - .work/TODO.md                                                  # T6：M7-6 条目翻账 + M7 站收口标注
  - .work/GOAL-STATE.md                                            # T6：续接点翻新（M7 站收口 → next = M8 charter〔SPEC 正式化〕；union 改动权用讫归还注记）
  - AGENTS.md                                                      # T6：「M7-6 架构增量」节（预览 ICC 两段式 legal/域外两臂 + scrub session 缝 + 宿主 admit 透传缝 + skills 仓形态 + ΔN 终值）
---

# Plan M7-6-01 — M7 站收官（三缺陷 + UQ-A1/UQ-L1 + SKILLS-01 + 全套对账 + 站级 VALIDATION）

> **夜间全自动授权**（先例 D-07-3-T5-1；晨审可推翻）。裁决正本 =
> `M7-6-CONTEXT.md`（D-M7-6-1..10 全按 RESEARCH §7 推荐——站 charter 授权
> 落定）；规格正本 = `RESEARCH.md`（§1..§8；file:line 经 planner
> 2026-10-17 HEAD `07927ab2` 逐点亲核复核吻合）。
>
> **转写勘正五条（RESEARCH → PLAN planner 亲核批，非矛盾、执行以本清单为
> 准）**：①FIX2③ 正义勘正——RESEARCH §0「本批修法落点均不触
> McpServerController 的 controller 面」为笔误级混淆：FIX2③ 正义 =
> **LibraryProjectController.swift 文件零 diff**（M7-5-CONTEXT 红线⑥正本，
> 连续四波亲证）；本波 major-1/minor-1 修法恰落 McpServerController（合法
> 修改面，DECISIONS 申报 hunk 清单即可——RESEARCH §0 括号后半句
> 「minor-1 触同一文件的头less 装配臂，DECISIONS 申报即可」即此意）。
> ②SKILL.md 抽读节面勘正——RESEARCH §1.3「人工抽读五节」vs §1.2 七节骨
> 架：以 **§1.2 七节为正本**（七节全抽读，从严不从松）。③GUI admit 闭包
> 形态——RESEARCH §4.1 `MainActor.run { … }` 形 vs 装配点既有 acquire
> provider **plain-await hop 先例形**（LightamerApp :1634-1637 + 注释「the
> plain await IS the MainActor hop」）：采 plain-await 先例形（同款注释），
> 两形等价。④makeUnionRegistry 可见性——实测 `private func`（:277），
> RESEARCH 未提此前提：T4 机检新文件复用需 **恰一行 private→internal
> 提升**（union 文件本波唯一预期 diff，持权行使申报点）。⑤tools.md
> schema 列从严——RESEARCH §1.2「schema 摘要」→ **schema 全文逐字节**（摘
> 要规则本身需人维护违背「零脚本维护面」；全文渲染 = 纯机械、漂移捕捉
> 更全）。另 obs-3 复检锚微差：busy 入口检查实测 :215-217、revoked 文案
> 臂实测 :228-231（RESEARCH 记 :217/:229——语义同点，±2 行内）。
>
> **评审回注（round 1，2026-10-17）**：`M7-6-01-PLAN-REVIEW.md`（e61185b0）
> 八条已按处方回注——B1（obs-3 快照 + 条件复检 + resume 不断裂负腿 +
> SKILL.md §2 诚实面 + ΔN T1 5→6）/ M1（setControlAdmit 生产调用恰 3 点
> 构成，embedded 经 box→startHTTPHost 单点装配）/ M2（yiyin 勘正翻转：
> 三处 LightamerSlider 调用在册）/ m1（legal SDR 8 对）/ m2（T1 文件
> 恰六）/ m3（endpoint 9 字段）/ m4（T6 SC 降格制度注记）/ m5（拖离取
> 消让渡显式申报）；行内 `（review *）` 标记对账。执行以回注后文本为准。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（三缺陷修复 = M7-5 SUMMARY
> 裁定路由；两 UQ = 上游同病同修既定件；SKILLS-01 = REQUIREMENTS 既定
> 行；VALIDATION = 站收官既定动作）。执行中如触「必须扩面」（新错误码 /
> McpTimeouts 改档 / union 内容改 / 封存面触碰 / legal 表扩容 / 禁编辑面
> 变更）= 停手上报，不得自裁扩界。
>
> **执行序**：T1 → T2 → T3 → T4 → T5 → T6。T1-T4 产线/文档批（每任务独立
> commit + 构建绿机检 + 测试腿随任务落位），T5 轮次 + 红线族，T6 站级收
> 口文档 + 台账翻账。每任务独立 commit（Conventional Commits，全英文，
> 只 add 相关文件，不 push）。
>
> **基线**：**3950/35/0**（M7-5 三路全套同值；其后 docs-only 零漂移；HEAD
> `07927ab2`）。全套预期 `TOTAL|3950+ΔN/35/0|`（ΔN 预期 +13〔review B1〕、
> 带 +9..14 → 终值带 3959..3964，对账式〔review R2 带边重导〕）。
>
> **快照改动权**：本波持 union 文件改动权（M7-5 移交）——预期唯一 diff =
> makeUnionRegistry private→internal 一行（T4）；内容/计数断言零 diff；
> **禁并行派发**（orchestrator 编排保证；若误并行派发立即停手上报）。

## ΔN 预算表（逐任务，合计带 +9..14〔review R2〕；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 三缺陷 | **6**（带 4..6）〔review B1：5→6〕 | major-1 真宿主 controlNotHeld 1 + 无头臂端到端 nil 恒放行 1（与既有负测同语义可合并让渡 → 带下限）+ minor-1 裸臂 agent 非 null 1 + obs-3 两变体 2 + resume 不断裂负腿 1 | McpHostTests / McpControlToolsetTests / McpSearchStateToolsetTests / AgentControlCoordinatorTests 各扩法 |
| T2 UQ-A1 | **2** | legal SDR 8 对等值 1（循环逐对，review m1）+ 域外回落负腿 1 | EditorPreviewColorSpaceTests（新） |
| T3 UQ-L1 | **3**（带 2..4） | travel→value 映射族 1 + Shift/clamp 族 1 + begin/end 配对 1 | LightamerSliderScrubTests（新） |
| T4 SKILLS-01 | **2**（带 1..2） | tools.md 逐字节 1 + errors.md 19 码名断言 1 | SkillsReferenceTests（新） |
| **合计** | **+13**（带 +9..14〔review R2 带边重导〕）〔review B1：+12→+13〕 | 3950 → 预期 3963，带 3959..3964 | 全 APP 域；Project.swift 恰 +3 行 |

## 已定裁决（生效值，硬约束，不得重开）

OQ-M7-6-1..10 **全部按 RESEARCH §7 推荐裁**（CONTEXT D-M7-6-1..10）。执行
面速查：

1. **skills 仓形态 = 仓内 `skills/`**（OQ-1）：`skills/lightamer-mcp/`
   单 skill 多 reference；独立仓挂账至需求出现。
2. **skill 语言 = en 单语**（OQ-2）：不入 xcstrings / zh-audit 豁免申报。
3. **reference 机检 = 测试即门**（OQ-3）：活注册表渲染 vs 仓内文件逐字节。
4. **UQ-A1 = legal 对换 ICC v4、域外对 calibrated 回落**（OQ-4）：两段
   式；HDR/linear 臂零改；不扩导出 legal 表。
5. **UQ-L1 范围 = 只落 LightamerSlider**（OQ-5）：177 调用点全量受益；
   Monochrome 自有 row 登记观察项不顺手改。
6. **track 双击 wrinkle = 登记不动**（OQ-6）：框架行为，lightcraft 修法
   不可平移；文档注记即可。
7. **major-1 修法 = (a) 宿主透传参 +1 缺省 nil**（OQ-7）：writerCheck 装
   配同构；无 toggle 时序缝；无头臂字节零 diff。
8. **VALIDATION = 单站级文档，m7-5 不补写**（OQ-8）：载体偏差登记为制度
   事实；含 M7-5 §signed 节。
9. **plan 切分 = 单 plan**（OQ-9）：六项全入；union 串行 → 并行度为零。
10. **obs-A C12 AX 旗标 = 零代码 + 站级注记一行**（OQ-10）：行为门为准。

**登记申报（非 OQ，随批进 DECISIONS）**：①制度偏离两件正式登记归 T6
（omp→双 zcode / m7-5 载体偏差）；②xcstrings 恰 +1 键预期（零提示裁定
→ 零键申报）；③UserDefaults 零新键预期；④union 持权行使 = internal 一
行申报。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/m7-6-station-close/M7-6-CONTEXT.md`（D-M7-6-1..10 裁决
  + 登记申报 + 晨审推翻点索引）
- `.work/gsd/phases/m7-6-station-close/RESEARCH.md` §4（三缺陷事实链）+
  §2（UQ-A1 落点与消费链）+ §3（UQ-L1 接入点与冲突评估）+ §1（SKILLS-01
  形态）+ §8（证据索引 file:line 速查）
- `.work/gsd/phases/m7-5-turn-taking/M7-5-SUMMARY.md` §Leftovers（三缺陷
  正本 + union 权移交语义）+ `M7-5-01-DECISIONS.md` §2/§3（偏差裁决先例）
- `.work/config.toml [gsd]` paused/auto 开关（开工前亲核）
- `.work/LESSONS.md` L041（tuist generate 恒末位）+ CONVENTIONS「新测试文
  件落域规则」（Project.swift 显式清单 + BUNDLE-MAP + tuist generate 恒末
  位）+ L057 节（runModal 禁令）
- 本 plan 头注「转写勘正五条」（执行以勘正为准）

---

## T1 — 三缺陷：major-1 setControlAdmit 生产接线 + minor-1 裸臂两行 + obs-3 复检硬化三行（快照+条件复检，review B1）

> **产线 ≤10 行**（major-1 签名批 + 两处一行 + 复检硬化三行〔快照 1 + 复检 2，review B1〕）+ 测试腿 ≥4。
> 三缺陷同域（MCP/coordinator 文件）连做。typed 拒复用既有三码既有文案
> 键——零新错误码零新键。

**read_first**：`RESEARCH.md` §4 全节（major-1 事实链亲证 + 两案对比 +
minor-1/obs-3 修法与测试腿预估）；`McpToolRegistry.swift` :335（controlAdmit
字段）+ :367-371（setControlAdmit seam）+ :385-408（dispatch 序
writer→control→handler）；`McpServerController.swift` :478-500（裸臂两处 +
无头宿主调用）+ :603-606（arbitrated 臂同形先例）+ :232-236
（makeHeadlessSearchState 签名）+ 三宿主 :722/:786/:1035 + embedded 入口
:1137/:1165〔review M1：embedded 无独立安装点，读 box/透传段用〕+
setWriterCheck 调用点 :737/:819/:1081；`AgentControlCoordinator.swift`
:213-268（acquire 全形——:215-217 入口 busy / :227-240 等待循环 /
:228-231 revoked 文案臂 / :248-267 success 路径）；`LightamerApp.swift`
:1632-1651（GUI 装配段——controlContext + plain-await hop 先例）；
`McpControlToolsetTests.swift` :194/:253/:473（既有 fixture 接线形态——
真宿主腿的 stub 同款形）。

- **action**：
  1. **major-1 签名批**：三宿主（startReadOnlyHTTPHost :722 /
     startHeadlessStdioHost :786 / startHTTPHost :1035）各恰 +1 参
     `admit: (@Sendable (_ toolName: String) async throws -> Void)? = nil`
     （缺省 nil = 既有全部调用点编译零 diff）；startEmbeddedIfPreferenceEnabled
     :1137 恰 +1 同名缺省参 + EmbeddedState box 恰 +1 `admit` 字段
     （control 字段 :1143-1150 同款形 + 同款缝语义注释）；startEmbeddedServer
     :1165 box 读出透传。每宿主函数体在 setWriterCheck 调用点（:737/:819/
     :1081）之后恰 +1：
     `if let admit { await registry.setControlAdmit(admit) }`——生产调用
     恰 **3** 点；embedded 无自有 registry、整段委托 startHTTPHost :1176，
     经 box→startHTTPHost 复用 :1081 单点装配，**无独立安装点**（review
     M1——禁为凑数在 embedded 段经 handle 二次安装，double-install +
     serve-before-admit 竞态窗）。
     **无头臂生产调用点零触**（缺省 nil = 恒放行 = D-M7-5 正确语义，字节
     零 diff——read-only/arbitrated/GUI-off 同理）。
  2. **GUI 装配**：LightamerApp :1632-1651 段 startEmbeddedIfPreferenceEnabled
     调用恰 +1 `admit:` 参——闭包
     `{ name in try await agentControl.admit(toolName: name) }`
     （plain-await MainActor hop 先例形 + 同款注释——转写勘正③）。
  3. **minor-1 两行**：McpServerController :482 / :497 两处
     `makeHeadlessSearchState(mode: mode)` 各补一行
     `agentControl: { McpControlState.headlessConstant }`（与 :603-606
     arbitrated 臂拼写逐字同形）——裸臂 get_state control.agent 不再
     .null 镜像谎报。
  4. **obs-3 复检硬化（快照 + 条件复检，review B1）**：AgentControlCoordinator
     acquire 等待循环（:227-240 while）前恰 +1 入口快照行
     `let stoppedAtEntry = stoppedByUser`；循环退出后、success 路径
     （:248 起 resume 路由）之前恰 +2 复检——revoked 臂
     `if stoppedByUser, !stoppedAtEntry { throw McpToolError.controlRevokedByUser(…`
     （同 :228-231 文案形逐字；Stop 发生在本次 acquire 等待窗内才拒——
     入口已 stopped = TURN-03 resume 语义，放行走 :248-259 清零）+ busy 臂
     `if held, self.holderName != holderName { throw McpToolError.controlBusy(…`
     （同 :215-217 文案形逐字；无条件安全——能到复检点时 held false→true
     只能是等待/挂起期间他 holder 抢到）。两变体语义：①Stop-in-final-window
     （最后一轮 poll 窗口用户 Stop → 循环条件翻转退出 → 条件复检拒，不再
     静默吞）②并发异 holder（入口 :215-217 预计算后挂起等待期间另一
     holder acquire 成功 → 双持有）。**禁无条件 `if stoppedByUser` 拒绝**
     ——那会打断 Stop→re-acquire=resume 主语义（agent 被 Stop 一次后永久
     无法 re-acquire，review B1 病灶）。
  5. **测试腿**：①真宿主 controlNotHeld（McpHostTests 扩法）——
     startHTTPHost 带 admit stub（`{ _ in throw McpToolError.controlNotHeld(
     "not held") }` 形），未 acquire 直调 apply_params → 断言错误码
     controlNotHeld（M7-5 第二路 e2e 实锤「落 handler internalError」的翻
     转面）；②无头臂端到端 nil 恒放行（McpControlToolsetTests 扩法，可选
     ——与既有无头恒持有负测同语义 = DECISIONS 申报合并让渡）；
     ③minor-1 腿（McpSearchStateToolsetTests 扩法）——裸臂
     `makeHeadlessSearchState(mode: .stdio)`（:1015 既有直调先例形）的
     agentControl provider 非 nil 且调用返回 `.headlessConstant`；
     ④obs-3 两腿（AgentControlCoordinatorTests 扩法）——注入 provider 控
     制交错：liveEditActive=true → 并发 stop() → provider 翻 false →
     expect controlRevokedByUser；等待期间异 holder acquire 先完成持有 →
     provider 翻 false → expect controlBusy（交错控制终形 DECISIONS 申
     报；禁真等 250ms poll——poll 间隔/超时经既有注入缝）；
     ⑤resume 不断裂负腿（AgentControlCoordinatorTests 扩法，review B1）——
     acquire → stop() → 同 holder re-acquire（liveEditActive 恒 false 注入）
     → expect 成功且 taskId 复用（resume）——正是能拦住 B1 缺陷的那条腿。
  6. 构建绿机检（caffeinate -dis 包裹）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰六产线/测试文件（McpServerController +
    LightamerApp + AgentControlCoordinator + 三测试文件扩法——新文件零；
    可选腿 McpControlToolsetTests 执行则恰七，DECISIONS 申报——review m2）。
  - grep：`setControlAdmit` 在 App/Sources 恰 5 处（定义 :367 +
    ControlToolset.swift :20 头注字样 + 三宿主调用点各一——构成按此核，
    头注命中不计调用点；embedded 无独立安装点，review M1）；`admit:` 缺省
    参恰四处签名（三宿主 + embedded——签名批不变）+ box 字段恰一；
    `agentControl: { McpControlState.headlessConstant }` 在
    McpServerController 恰 3 处（:482/:497 新 + :603-606 既有——既有行零
    diff 面核）；acquire 函数体 diff = 恰 +1 快照行 + 2 复检行（或等价
    终形 DECISIONS 申报；其余段零触——`git diff` 逐 hunk 面核，review
    B1）。
  - 测试腿 ≥4 全绿（`--bundle App` 定向）。
  - **LibraryProjectController.swift 零 diff**（FIX2③ 第五波——勘正后正
    义，`git diff --stat` 核不在清单）。
- **commit**: `fix(m7-6): wire setControlAdmit to hosts and harden acquire`
- **回滚与偏差申报要求**：本任务全部 additive 缺省 nil 参——回滚 =
  revert 单 commit 即回到 M7-5 基线语义（admit 无通道 = 13 工具恒放行）；
  偏差（宿主落点/签名形态/测试腿落点变化）= DECISIONS 逐条申报，禁静默；
  若某宿主函数体结构不经 setWriterCheck 点（装配序不同）= 等价安装点 +
  申报，禁为凑 grep 硬造点位。

## T2 — UQ-A1：预览层 ICC 双曲线失配（legal 对换导出同款 ICC v4 + 域外回落）

> **两段式单函数臂**：legal 对预览 = 导出同字节（双曲线失配根治——上游
> Alcedo `36db9a8`/#391 同病同修）；域外对回落 = 预览显示义务（全部
> space×SDR-eotf 组合仍须上屏）。Core 侧 per-pair 永久缓存 → 零每帧 ICC
> 重建开销。M4-1-01 KD-8 显示侧偏离随本修复消解（DECISIONS 收口申报）。

**read_first**：`RESEARCH.md` §2 全节（缺陷定义/预览面/导出面/消费链/域
差清单）；`EditorMTKView.swift` :709-811（drtLayerColorSpace 全形 + SDR 幂
臂 :749-798 + :755-760 srgbPiecewise 2.2 幂近似〔KD-8 注释原位〕+ HDR 臂
:734-746 + linear 臂 :748 + drtSurfaceSpec :804-811）；
`LightamerCore/Sources/Export/DrtOutputColorSpace.swift` :53-141（legal
linkage 表 :59-137 + srgbPiecewise curv 1024 采样表 :72-77/:89-92 +
per-pair 缓存 :56）+ :248-259（ICC bytes 构造）；`PipeCoordinator.swift`
:646-653（drtViewportSurface 消费点——零触确认）；`DrtOutputColorSpaceTests`
（Core resolver 既有测试——等值测试的 (space,eotf) 枚举先例）。

- **action**：
  1. **drtLayerColorSpace SDR 幂臂两段式**：:749-798 段改造——每个 SDR
     eotf case（bt1886/gamma22/gamma26/gamma18/srgbPiecewise）先
     `try? DrtOutputColorSpace.drtOutputColorSpace(space: record.encodingSpace,
     eotf: eotf)`；非 nil → 返回（导出同款 ICC v4 实例——srgbPiecewise
     得真分段 curv 1024 表）；nil（Core typed throw = 域外对）→ 回落现行
     calibratedRGBWhitePoint 构造（现行 switch 逐 case 原样保留为回落臂
     ——:755-760 幂近似行随回落臂保留，KD-8 注释更新为「legal 对已换挂
     导出 ICC；此回落臂仅域外对可达」）。
  2. **HDR/linear 臂零改**（:734-746 / :748——HDR 两侧同为系统命名
     profile 语义一致；linear 仅预览存在）；drtSurfaceSpec :804-811 与
     PipeCoordinator :646-653 零触（单链下游自动继承）。
  3. **等值测试**（EditorPreviewColorSpaceTests 新文件）：legal SDR 8 对
     清单（rec709×{bt1886,gamma22,srgbPiecewise} + p3d65×{gamma22,
     srgbPiecewise} + p3d60×gamma26 + p3dci×gamma26 + xyz×gamma26——
     RESEARCH :131-137 legal 表 SDR 子集）逐对构造 record（DrtRecord 构造
     形态按既有 init/DrtPresets 先例亲核，零 diff 封存面）→ 断言
     preview space（`EditorMTKView.Coordinator.drtLayerColorSpace`）===
     export space（`DrtOutputColorSpace.drtOutputColorSpace`）同实例 +
     ICC data 逐字节同；ramp 采样等值腿（64 点灰阶经两 space 各自 decode
     至 linear，差 ≤1/255）——同实例已蕴含等值，ramp 形可收敛为字节同断
     言（实现形 DECISIONS 申报）；域外负腿——rec709×gamma18 / p3d65×
     bt1886 非 nil（走回落臂）且与 Core resolver throw 行为一致；
     srgbPiecewise 对断言 ICC data == Core curv 1024 采样表形（非 2.2 幂
     ——[2.2,2.2,2.2] gamma 表形负断言）〔8 对计数 = review m1 勘正：
     rec2020 仅 HDR 两档、gamma18 不在任一 legal 集〕。
  4. 构建绿机检。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰两文件（EditorMTKView + 新测试文件）；
    **LightamerCore/Sources/Export/DrtOutputColorSpace.swift 零 diff**
    （纯消费——Core 侧零触碰）。
  - legal SDR 8 对全绿（同实例 + 字节同，review m1）；域外负腿绿
    （gamma18 等非 nil）；srgbPiecewise 真分段表断言绿。
  - HDR/linear 臂 diff 零触（`git diff` 面核 :734-748 段）；消费链下游
    （drtSurfaceSpec/PipeCoordinator）零 diff。
  - 无每帧重建判据：App 侧零新缓存面（Core :56 缓存命中即返回——代码面
    核 try? 直调无本地缓存构造）。
- **commit**: `fix(m7-6): share the export ICC in the drt preview for legal pairs`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（预览回 2.2 幂近似——
  KD-8 偏离复活，无数据面影响）；偏差（legal 对清单出入〔若 Core legal
  表实测与 RESEARCH :131-137 有出入 = 以 Core 表为准逐对申报〕/ record
  构造形态 / ramp 腿收敛形）= DECISIONS 申报；**禁扩导出 legal 表**（域
  外对回流 = 触 export 语义面，越 OQ-4 裁决——发现 legal 表覆盖不足 =
  停手上报）。

## T3 — UQ-L1：滑杆横扫 scrub（LightamerSlider 单组件 + 纯函数映射 + D-H1 复用）

> **scrub = readout 上的值横扫**（lightcraft `ab64e9a5` 交互语义对表：
> ≥3pt 进入 scrub / Shift = 1/10 速 / clamp range / 一个 undo step）；**
> 一个 undo step = D-H1 三段复用**（scrub begin → onDragBegin、per-tick →
> onChange、end → onDragEnd——一次 scrub = 一次连续 commit，禁旁路）；
> denoise 拖动降档旁路零额外接线（M3-1-03 防线挂同回调面自然兼容）。

**read_first**：`RESEARCH.md` §3 全节（现状/wrinkle/lightcraft 两 commit
语义/yiyin 勘误〔review M2：RESEARCH §3.1「零命中」勘正为 grep 假阴性，
以本 plan/CONTEXT 勘误为准〕/接入点与冲突评估）；`LightamerSlider.swift`
:18-81 全文
（D-H1 三段回调 :30-37 头注契约 + readout :65-69 + 双击 :72-74 + AX 三处
:47/:63/:69）；M3-1-02 先例 = `YiyinSheetDragSession`（「AC 可机检缝范式：
交互纪律断言不靠 UI 驱动」——scrub session 值类型同款）；
`YiyinPanelView.swift` 实测 8 处 `LightamerSlider(` 调用在册（:160 blur /
:182 main_rate / :203 / :235 / :268 / :380 / :393 / :589〔review R1 计数
勘正 3→8〕）——LightamerSlider 单组件修复使 yiyin 面板族同样
受益（review M2）；lightcraft
`cb8b797c`/`ab64e9a5` 交互语义清单（RESEARCH §3.1——MIT 对表只取语义不搬
码）。

- **action**：
  1. **scrub session 值类型**（LightamerSlider.swift 同文件 internal 纯
     类型）：`LightamerSliderScrubSession`——`began(startValue:startX:)` /
     `tick(atX:shiftActive:) -> Double`（= startValue + Δx/trackWidth ×
     rangeSpan × (shift ? 0.1 : 1)，clamp range）/ `end()`（配对态收敛）
     ——纯函数无 UI 依赖，golden 测试直接驱动。
  2. **readout 手势**：readout Text（:65-69）挂
     `DragGesture(minimumDistance: 3)`——onChanged 首回调 = session.began
     → `onDragBegin()`；后续回调 = session.tick → `onChange(value)`；
     onEnded = session.end → `onDragEnd()`。shiftActive =
     `value.modifiers.contains(.shift)`。trackWidth 经
     GeometryReader/onGeometryChange 就地测量（组件宽近似——测量终形
     DECISIONS 申报）。**D-H1 三段复用 grep 断言**：scrub 路径只调
     onDragBegin/onChange/onDragEnd 三回调，零旁路。
  3. **AX hint**：readout 加
     `accessibilityHint(String(localized: "slider_scrub_hint",
     defaultValue: …))`——xcstrings 恰 +1 键尾块纯插入（zh-only 形）；
     若执行裁定零提示 = 零键（DECISIONS 申报，ΔN 不变）。
  4. **既有面零触**：onReset 双击（:72-74）、AX identifier 三处
     （:47/:63/:69）、Slider 本体与 onEditingChanged 面零改；与双击手势
     共存 = minimumDistance 区分（tap 零位移 vs drag ≥3pt——SwiftUI 并存
     语义，实测走查确认）。
  5. **测试**（LightamerSliderScrubTests 新文件，纯值类型驱动）：travel
     →value 映射族（零位移恒等 / 正向 / 负向 / range 双侧 clamp）+ Shift
     ×0.1 族（含 clamp 仍生效）+ begin/end 配对计数（一次 scrub =
     onDragBegin 恰 1 + onDragEnd 恰 1 + onChange 序列非空——一个连续
     commit 语义）。
  6. 构建绿机检。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰三文件（LightamerSlider + 新测试文件 +
    xcstrings〔或两文件若零键裁定〕）。
  - **MonochromePanelView.swift 零 diff**（D-M7-6-5）；**denoise 旁路面
    零 diff**（`EditorState.previewDenoiseBypass` 所在文件不在清单——
    `git diff --stat` 核）；AX identifier 三处 diff 零触。
  - scrub golden 全绿；grep：`DragGesture(minimumDistance: 3)` 恰一处于
    LightamerSlider；scrub 路径 `onDragBegin|onChange|onDragEnd` 之外零
    值写入通道。
  - xcstrings diff = 恰一尾块插入（历史键零触碰）或零 diff（零键申报）。
- **commit**: `feat(m7-6): add readout scrub to the shared slider`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（readout 回零手势——
  双击重置不受影响）；偏差（session 拆分形态 / trackWidth 测量终形 /
  键数）= DECISIONS 申报；**拖离取消语义让渡显式申报**（lightcraft
  「拖离取消不留残值」——RESEARCH §3.1 清单在册；SwiftUI DragGesture
  生命周期不等价：onChanged per-tick 已落 live 值、onEnded = 释放点，
  无法等价实现自绘 widget 的取消语义——让渡合理但须 DECISIONS 申报 +
  T5 MANIFEST 观察行登记，review m5）；**禁触 Monochrome 自有 row**
  （OQ-5——顺手改 = 范围越界，发现须停手上报）；**禁加持久化**（scrub
  无记忆面——发现 UserDefaults 需求 = 停手上报）。

## T4 — SKILLS-01：仓内 skills 文档仓（SKILL.md 人写 + references 机检测试即门）

> **en 单语 + 零 taste + 零 Alcedo 文案**（GPL 禁译禁改全自写）；机检 =
> 活注册表渲染 vs 仓内 tools.md 逐字节（测试即门——注册表演进漂移随全套
> 即红）；N2-2 挂账文档句随批收口。union 文件唯一预期 diff = internal 一
> 行（持权行使申报点）。

**read_first**：`RESEARCH.md` §1 全节（Alcedo 面实测/我方 MCP 面/方案建
议/验收形态）+ §7.1-§7.3（三 OQ 裁决依据）；`McpFinalSnapshotTests.swift`
:270-272（all32 五域清单）+ :277（makeUnionRegistry private——本批改
internal）+ :401 起（descriptionKeys 映射表——tools.md description 事实
源）；`McpEndpointFile.swift` :61-75（endpoint schema v1 九字段——schemaVersion/
transport/host/port/pid/startedAt/serverName/serverVersion/auth，review
m3）；
`McpServerController.swift` :1046-1065（loopback/.lan Bearer）+ runHeadless
段（--mcp-stdio/--mcp-http——执行时 grep 亲点行号）；`ControlToolset.swift`
:1-60 头注 + `AgentControlCoordinator.swift` :178-268（turn-taking 语义
——SKILL.md §2 事实源）；`McpControlToolsetTests.swift`（turn-taking 语义
节对照断言面）；REQUIREMENTS :452（SKILLS-01 行——内容清单正本）；
survey `.work/gsd/research/ALCEDO-CLI-AI-SURVEY.md` :217（launcher 模板）+
:303（内容清单）。

- **action**：
  1. **makeUnionRegistry 可见性提升**：McpFinalSnapshotTests :277
     `private func` → `internal func`——**恰一行 diff**（union 内容/断言
     面零触；本波持权行使申报点）。
  2. **`skills/lightamer-mcp/SKILL.md`**（人写 en）：front-matter
     （`name: lightamer-mcp` + `description: Use when …`——Alcedo 形态对
     表，文案自写）+ 七节骨架（CONTEXT D-M7-6-1 证据链；每节一句话定位，
     细节进 references）：①Installation & session start（GUI HTTP
     endpoint 发现 → `mcp-endpoint.json` 九字段〔schemaVersion/transport/
     host/port/pid/startedAt/serverName/serverVersion/auth——review m3〕
     + auth 两档 → stdio client 配置模板；裸 `--mcp-stdio`/`--mcp-http`
     臂；launcher `{{LIGHTAMER_MCP}}`+`{{PROMPT}}` 模板指针）②Turn-taking
     语义（先 control_acquire 再写 / 13 工具 admit 面 / Stop = 用户收回 +
     同 holder re-acquire = resume / 等待编辑输入封合期间被 Stop →
     re-acquire 得 controlRevokedByUser〔非静默吞——obs-3 修复后新对外
     语义，agent 文档如实写，review B1〕/ 无头臂恒持有 / 三控制码恢复
     动作）③工
     具五域边界（32 工具分账 + 哪域改像素/哪域只读/哪些需要 project）④
     错误码表指针（→ references/errors.md）⑤render_preview 语义（编辑态
     无印框 = M2 页域差异；compare:root 前后对照；region 归一化 0..1 相
     对渲染输出帧、crop 在 render 后）⑥UI 单位说明（滑杆 range 单位与
     params 数值域映射——从 list_iops schema 读）⑦已知面（N2-2 句如实：
     get_state project 字段 GUI/headless 两臂不对称——heldByOther 仅
     headless 面）。**零 taste**（规则留 launcher {{PROMPT}} 载体）。
  3. **`references/tools.md`**（机检生成）：渲染器 = SkillsReferenceTests
     内 internal static 函数（makeUnionRegistry().descriptors() 活注册表
     → markdown：name / domain / readOnlyHint / schema 全文 / description
     ——转写勘正⑤ schema 全文从严）；初版生成 = executor 经临时脚手架调
     渲染函数写盘（swiftc 脚手架或测试临时输出——DECISIONS 申报生成通
     道）；此后测试即门锁漂移。
  4. **`references/errors.md`**（人写 en）：19 错误码表——码名 / code /
     语义一句 / 恢复动作一句（三控制码恢复动作对表 ControlToolset 语义
     自写；16 非控制码语义一句从 McpToolError message switch 事实转写）。
  5. **`SkillsReferenceTests.swift`**（新文件两法）：法 1 = 活注册表渲染
     markdown vs 盘上 tools.md **逐字节比对**；法 2 = errors.md 19 码名
     逐一出现断言（码名清单硬编码循环——未来错误码增删即红）。
  6. **README.md 一句链接**（skills/lightamer-mcp/ agent 文档入口）。
  7. 构建绿机检。
- **验收标准（机检）**：
  - 构建绿；SkillsReferenceTests 两法绿。
  - `git diff Tests/LightamerTests/McpFinalSnapshotTests.swift` 恰一行
    （private→internal）；union 既有断言全绿（--bundle App 覆盖——内容
    零触双证）。
  - en 单语机检：`grep -rn "[一-鿿]" skills/` 零命中；N2-2 句 grep 在
    SKILL.md；README 链接句 grep。
  - xcstrings / Localizable 零 diff（T4 不触本地化面——D-M7-6-2 豁免）。
  - 零 taste 判据：SKILL.md 无操作规则性段落（「先做 A 再做 B」类 taste
    句——DECISIONS 人工申报自检）。
- **commit**: `feat(m7-6): add the lightamer-mcp agent skill docs`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（纯文档 + 一行可见性
  + 两测试法，零产线行为面）；偏差（七节骨架节名/落点/references 拆分/
  生成通道）= DECISIONS 申报；**禁抄 Alcedo 文案**（比对正本 = 本地
  AlcedoStudio 仓文档——发现形似句 = 重写；零味觉规则进文档）；**禁改
  union 内容**（internal 一行外任何 diff = 停手上报）。

## T5 — 定向轮 + 全套 `--all` 对账（预批）+ 红线族亲跑 + 走查配方

> **全套轮预批在案**（plan 期 orchestrator 批准）——运行中保持监视 +
> 8G 门 + MEMFAIL 机检。对账式判定：`TOTAL|3950+ΔN/35/0|`，ΔN 逐任务记
> 账落 +9..14 带（预期 +13 → 3963，review B1 预算同步 + R2 带边重导）。

**read_first**：`RESEARCH.md` §5（VALIDATION 清单骨架——红线族 11 项表）
+ §6（ΔN 预估带）；M7-5-SUMMARY §Execution Batch Results（对账先例形）；
`.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt`（域模式——
三新行登记核对）。

- **action**：
  1. **定向轮**：`caffeinate -dis Scripts/test-direct.sh --bundle App`
     全绿（T1-T4 全部测试落 APP 域——覆盖本批全部新测试面）。
  2. **全套对账轮**：`caffeinate -dis Scripts/test-direct.sh --all`
     （预批；运行中监视 + 超门立即 kill）——`TOTAL|3950+ΔN/35/0|` 对账
     精确闭合（ΔN 预期带 +9..14；逐任务记账表进 SUMMARY；越带 = 申报理
     由禁静默）；skip 35 构成声明（24 基线 + 11 RAW 供件——第三种来源
     逐族差分申报禁静默吸收）。
  3. **zh-audit 对账**：`uv run python3 Scripts/zh-audit.py --check` PASS
     （+1 键对账——source keys 1708→1709；零键裁定 = 1708 维持）+
     `--self-test` PASS。
  4. **红线族 11 项亲跑**（RESEARCH §5.3 同表，逐条机检）：零新 SPM /
     `.metal` 全域零 diff / McpToolRegistry 面（错误码 19 档零触 +
     writeCallCount 零触——setControlAdmit 装配四点为 DECISIONS 显式申
     报点）/ controller 面（FIX2③ = LibraryProjectController 零 diff
     第五波——勘正后正义）/ 封存面 17 件零 diff / xcstrings 尾块纯插入
     / UserDefaults 零新键 / runModal 禁形零命中 / 插值禁形零命中 /
     Project.swift 恰三行 + BUNDLE-MAP 恰三行 + tuist generate 末位 /
     union 32 + 五钉 23 零触（internal 一行外）。
  5. **走查配方落盘**：`.work/gui-acceptance/m7-6/MANIFEST.md`——UQ-L1
     交互行（双击重置 / readout 横扫 scrub / Shift 细调 / 面板一次
     commit 观察 / scrub 中拖离 = 不取消、残值留驻——lightcraft 取消
     语义让渡观察行〔review m5〕）+ UQ-A1 观察行（srgbPiecewise 预览观
     感微移 = 预期行为变化登记非缺陷——RESEARCH §2.3 走查观察项）+
     major-1 e2e 执法腿观
     察行（真宿主未 acquire 直调 = controlNotHeld）；实机走查归验收批/
     用户（UQ-L1 验收形态 = ROADMAP「交互走查 ✓」）。
  6. **SUMMARY + DECISIONS** 落盘（逐任务 ΔN 记账 + 转写勘正承接 + union
     internal 一行申报 + 各任务偏差终形）。
- **验收标准（机检）**：定向轮绿 + 全套 exit 0 / 0 fail / 0 MEMFAIL /
  七 bundle 8G 门内 + 对账闭合（对账行进 SUMMARY）+ 红线族全 PASS +
  zh-audit 双 PASS + MANIFEST 在库。
- **commit**: `test(m7-6): reconcile the full suite and redline battery`
- **回滚与偏差申报要求**：全套任何 fail = 先归因（本批 Δfiles 窗内?）——
  窗外 fail = 既有缺陷，停手上报不静默修；ΔN 越带 = 逐任务记账 + 申报理
  由；MEMFAIL = 立即 kill + 上报（禁放任）。

## T6 — 站级 M7-VALIDATION + 台账翻账（五 phase 收口矩阵 + SC 翻账 + 制度偏离登记）

> **单站级文档，不补写 m7-5 VALIDATION**（OQ-8）；含 M7-5 §signed 节
> （前置条件 = T1 major-1 修复后执法语义完整——M7-5-SUMMARY §Leftovers 6
> 路由兑现）；**C 档第 3 停**：文档落盘后呈用户晨审过目，签核推翻 = 翻
> 账重开。

**read_first**：`RESEARCH.md` §5 全节（清单骨架六条）+ §5.1 现状盘点表；
`phases/m7-1-shell/M7-1-VALIDATION.md`（front-matter 体例正本）；
`phases/m7-2-mcp-o1/M7-2-VALIDATION.md` :85（omp→双 zcode 先例句）；
M7-5-SUMMARY §Deviations（载体偏差句）+ §Leftovers（六项路由正本）；
REQUIREMENTS :445-461（翻账目标行）；ROADMAP :108-110（M7-4/M7-5/M7-6 行
翻账形先例）。

- **action**：
  1. **`M7-VALIDATION.md` 落盘**（front-matter 对齐 M7-1 体例：
     `phase: M7 站` / `status: validated` / `nyquist_compliant: true` /
     created / validated / batch_form——头注声明「用户晨审过目待定，
     C 档第 3 停，推翻则翻账」）。六节：①**站终验全套轮**判定式兑现
     （`TOTAL|3950+ΔN/35/0|` 对账行 + exit 0 + 零 MEMFAIL + 七 bundle
     8G 门内——引 T5 证据）②**五 phase 收口矩阵**（m7-1..m7-4 VALIDATION
     指针 + m7-5 双 ACCEPTANCE + SUMMARY 指针〔载体偏差注明〕+ m7-6 本
     批）③**红线族复检记录**（11 项逐条引 T5 机检结果）④**SC 表翻账**
     （ROADMAP §Milestone 7 SC 门判定式：skill 机检 ✓ / UQ-A1 等值 ✓ /
     UQ-L1 走查配方就绪 ✓〔实机走查归验收批〕/ 全套数字门 ✓——与
     REQUIREMENTS 翻账联动）⑤**制度偏离登记**（①omp→双 zcode 验收路由
     〔M7-2 VALIDATION :85 先例在案，站级汇总一句〕②m7-5 无独立
     VALIDATION 载体〔双 ACCEPTANCE + SUMMARY 即更重收口载体〕③UQ-L1
     SC 措辞降格登记（ROADMAP :110「UQ-L1 交互走查 ✓」vs SC 表「走查配
     方就绪 ✓〔实机走查归验收批〕」——M7-5 TURN-02「配方就绪归验收批」
     先例；站级 VALIDATION 以 `status: validated` 签核时，SC 表判定式与
     ROADMAP 原文的措辞差在此显式登记，晨审对账不再出现未解释降格——
     review m4））⑥**挂
     账清算面**（N2-2 → 本批 SKILL.md §7 文档句收口 / S-2 让渡 Export
     波维持 / obs-A C12 AX 旗标 → 制度注记一行〔D-M7-6-10：行为门为准、
     AXEnabled 恒真为框架忠实度已知面，不产码〕/ FIX2③ 第五波维持 /
     union 改动权用讫归还 M8〔禁并行注记移交下一波〕）。**§M7-5 signed
     节**：三缺陷修复后执法语义完整（controlNotHeld 真宿主执法腿绿 +
     裸臂诚实面 + acquire 复检封合）——M7-5 交付在站级文档给 signed
     语义。
  2. **台账翻账同批**（历史行只追加不改写）：ROADMAP M7-6 行 → ✅ 闭环
     （ΔN 终值 + 六项判定式 + M7 站收口标注）；REQUIREMENTS SKILLS-01 /
     UQ-A1 / UQ-L1 → Delivered（M7-6 commit 指针；UQ-L1 范围勘注 = iop
     面板族）；TODO M7-6 条目 + M7 站收口标注；GOAL-STATE 续接点翻新
     （M7 站收口 → next = M8 charter〔SPEC 正式化〕+ union 权归还注
     记）；AGENTS.md「M7-6 架构增量」节（预览 ICC 两段式 legal/域外两
     臂 + scrub session 缝 + 宿主 admit 透传缝 + skills 仓形态 + ΔN 终
     值）。
  3. commit + 汇报（VALIDATION 文档路径 + C 档第 3 停呈用户过目声明）。
- **验收标准（机检）**：M7-VALIDATION.md 在库且六节齐全（grep 节标题）；
  四台账一 AGENTS 同批 diff（历史行追加形——`git diff` 逐 hunk 核）；
  REQUIREMENTS 三行 Delivered grep；SC 四判定式句 grep。
- **commit**: `docs(m7-6): station validation and ledger closeout`
- **回滚与偏差申报要求**：翻账 = 纯 docs——revert 单 commit 即回滚；偏差
  （VALIDATION 节构/翻账行数）= DECISIONS 申报；**禁改写历史状态行**（台
  账只追加——带日期历史行不可改写，新状态追加新行）；**禁补写 m7-5
  VALIDATION.md**（OQ-8——翻案须经晨审改 D-M7-6-8）。

---

## 风险与回退

- **major-1 宿主装配结构出入**：三宿主函数体（embedded 经 box→startHTTPHost
  复用 :1081 单点、无独立安装点——review M1）若实际装配序与 RESEARCH 行
  号表述有差（setWriterCheck 点位漂移）= 以函数体实际结构为准 + 等价安
  装点 + DECISIONS 申报（禁凑 grep）；缺省 nil 参保证既有调用点编译零改
  ——签名批回滚零风险。
- **obs-3 测试交错确定性**：并发异 holder 变体的 Task 交错在直启环境的
  时间抖动——交错控制经注入 provider 显式序（DECISIONS 申报终形）；
  flaky = 回注 T1 修，禁放宽断言；禁真等 250ms poll（既有注入缝）。
- **UQ-A1 legal 表出入**：RESEARCH :131-137 legal 表若与 Core 实测有出入
  = 以 `DrtOutputColorSpace` 实表为准逐对申报（测试清单随实表）；**禁扩
  表**（发现覆盖不足 = 停手上报——扩表越 OQ-4）。
- **UQ-A1 走查观感**：srgbPiecewise 预览低段略深 = 预期行为变化（真分段
  vs 幂近似）——MANIFEST 观察行登记，禁当缺陷回滚。
- **T3 手势并存**：readout DragGesture 与整行 onTapGesture(count:2) 的
  SwiftUI 并存语义（tap 零位移 vs drag ≥3pt）——走查确认双击重置不受
  扰；若实测冲突 = DECISIONS 申报手势隔离形（readout 局部
  contentShape），禁砍双击面。
- **T4 生成通道**：tools.md 初版渲染输出若经测试临时通道不便 = swiftc
  脚手架（进程内探针先例形）——DECISIONS 申报；生成后测试即门恒锁。
- **union internal 一行外任何 diff**：停手上报（持权窗口纪律——内容/断
  言面零 diff 是六项结构保证，出现即结构性误改）。
- **全套轮资源**：--all 预批 + 运行监视 + 8G 门 + MEMFAIL 机检（AGENTS
  资源监控节）；贴线 bundle 连续 MEMFAIL 先查重测顺序漂移（SPIKE ±3%
  方差注记）。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：ROADMAP §M7-6 行四验收形态 ↔ 任务面逐项映射——
   skill 仓机检 reference 生成 ✓（T4 法 1）/ UQ-A1 解码等值测试 ✓（T2）/
   UQ-L1 交互走查 ✓（T3 + T5 MANIFEST 配方——实机归验收批）/ SC 数字门
   （T5 --all 对账）；REQUIREMENTS 三行（SKILLS-01 = T4 / UQ-A1 = T2 /
   UQ-L1 = T3）+ M7-5 Leftovers 四项（major-1/minor-1/obs-3 = T1 /
   VALIDATION = T6）无孤儿项。
2. **OQ 兑现核**：D-M7-6-1..10 逐条对任务面——①仓内 skills/（T4）②en
   单语（T4 grep 零中文）③测试即门（T4 法 1 逐字节）④legal 换 + 域外
   回落 + HDR/linear 零改 + 禁扩表（T2）⑤只落 LightamerSlider（T3
   Monochrome 零 diff）⑥登记不动（wrinkle 注记句 + MANIFEST 观察行）
   ⑦透传参案（T1 四宿主签名批〔4 admit: 缺省参〕+ box + 无头零 diff +
   setControlAdmit 生产调用恰 3 点〔review M1〕）⑧单站级 + m7-5 不补写 +
   signed 节（T6）⑨单 plan（本文件）⑩零代码 + 注记一行（T6 挂账清算
   面）。
3. **快照族纪律**：union 内容零 diff（internal 一行外）+ 五钉 23 零触 +
   32 基线维持 + 禁并行双写（plan 头注 + 红线①）+ 窗口归还 M8 注记
   （T6）；持权行使 = DECISIONS 申报。
4. **三缺陷执法语义**：major-1 = 真宿主 controlNotHeld 腿（M7-5 第二路
   e2e 实锤面翻转）+ 无头臂字节零 diff + GUI 装配闭包；minor-1 = 两行 +
   arbitrated 臂零触 + 非 null 断言腿；obs-3 = 入口快照 + 条件复检三行
   （revoked 条件臂 `stoppedByUser, !stoppedAtEntry` / busy 无条件臂——
   拼写逐字同构）+ 两变体腿 + resume 不断裂负腿（review B1）；合计 ≥4 腿。
5. **UQ-A1 封存交互**：DrtOutputColorSpace/Core 零 diff + DrtRecord 零
   diff（测试只读构造）+ EditorMTKView 受限段（SDR 幂臂两段式——HDR/
   linear/drtSurfaceSpec 零触）+ KD-8 偏离消解申报（DECISIONS）。
6. **UQ-L1 D-H1 复用**：scrub 三回调面 grep 零旁路 + begin/end 配对腿 +
   denoise 旁路面零 diff + AX 三处零改 + 双击零触 + Monochrome 零 diff
   （OQ-5）。
7. **SKILLS-01 内容纪律**：en 单语 grep + 零 taste 申报 + 零 Alcedo 文案
   申报 + N2-2 句 + README 链接 + tools.md 机检逐字节 + errors.md 19 码
   断言 + schema 全文从严勘正（转写⑤）。
8. **制度偏离与挂账清算**：VALIDATION 六节齐全（omp→双 zcode 先例句引
   M7-2 :85 / m7-5 载体偏差 / N2-2 收口 / S-2 维持 / obs-A C12 注记 /
   FIX2③ 第五波 / union 归还 M8）+ M7-5 §signed 节前置条件核（T1 三腿
   绿在先）。
9. **SC 可机检性**：每条 SC 有命令级判据（grep / diff 面核 / 对账行 /
   定向 bundle 绿 / zh-audit 双 PASS），非「目测」；expected_all 对账式
   非死数（带 3959..3964）；skip 35 构成声明条款在 T5。
10. **登记纪律**：Project.swift 恰三行 + BUNDLE-MAP 恰三行 + tuist
    generate 恒末位（L041）——commit 顺序核；xcstrings 恰 +1 键尾块纯
    插入（或零键申报）+ zh-audit 对账；UserDefaults 零新键。
11. **转写勘正承接**：五条勘正（FIX2③ 正义 / 七节正本 / plain-await 形
    / internal 前提 / schema 全文）在 DECISIONS 逐条承接申报——RESEARCH
    原文与 PLAN 勘正冲突处以勘正为准（晨审可翻）。
12. **零回归面**：既有 32 工具 descriptor/handler 零 diff；McpTimeouts
    零触；错误码 19 档零触；get_state 键族零漂移；denoise 旁路面零
    diff；`--all` 3950+ΔN 对账闭合。

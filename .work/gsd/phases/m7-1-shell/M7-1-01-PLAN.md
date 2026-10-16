---
phase: m7-1-shell
plan: "M7-1-01"
title: "D-6 壳专项单 plan——T1 第一刀案 A+B 空载面零 churn 包（shell.reducedTree flag + inset 迁移 + inspector 列 240 钉 + 判别对照臂）/ T2 第二刀案 C3 零损失重组 scratch 实验门（不饿死则 C1/C2 呈报用户——呈报 = orchestrator 汇报层非 agent 自裁）/ T3 SHELL-03 五燃料面减频（焦点写点合并 + shortcut gate 收窄 + phase 镜像断边）/ T4 验收铁条（三判据探针转绿 + flag 回切判别 + 挂账⑥ N≥3 复测）/ T5 全套对账（批准制 + 8G 门）/ T6 走查复走批（SHELL-05 专项卷 + 挂账④⑤ + 双通道对照）/ T7 收口（FB 勘误两处随批 + 台账翻新）"
wave: 1
depends_on: []
autonomous: true
requirements: ["M7 站 charter 四裁之①（2026-10-16 用户「按推荐」：D-6 壳专项 = FIX2 三选一之①接受降级 + gate=false 壳减树/窗口内容拆分专项）", "REQUIREMENTS SHELL-01..05（M7-1 行 2026-10-16）+ ROADMAP §M7-1 行", "OQ 裁决正本 = phases/m7-1-shell/M7-1-CONTEXT.md（D-M7-1-1..6 全按 RESEARCH 推荐，夜间授权落签晨审可推翻）", "挂账正本 = FIX2-VALIDATION §挂账①④⑤⑥ + V2M-VALIDATION §挂账②", "夜间全自动授权在案（先例 D-07-3-T5-1）"]
success_criteria: "SC 全可机检——T1：flag-on build 图库/空载面可见窗 CPU <5%（10×1s ps 系列）+ probed transcript 稳态 10s 窗零重估行 + flag-off 对照 = 复现 23-34% 带（判别臂 transcript）+ 功能走查三件（toast 通道/只读横幅/M6-1 冲突对话框）证据 + AX 标识符零回归 grep + --bundle App 全绿；T2：C3 scratch 实验读数（CPU 系列 + transcript + sample）落 DECISIONS——饿死分支 = 编辑器面 <10%（10×1s ps）+ spin 消失三步铁条（cliclick 真实鼠标 filmstrip 点击出图 + 视口渲染 + 右栏 mount 截图）+ flag-off 编辑器面复现 82-90%，不饿死分支 = 本任务产线零 diff + 呈报件登记（裁定权 = 用户，经 orchestrator 汇报层）；T3：sample 帧计数前 vs 后可测下降（prependValue/mangled-name/makeMainMenu/updateMainMenu 四项计数对）+ MenuCommandSet IA 矩阵族全绿 + 菜单可用性走查证据；T4：三判据终验（CPU 门 + sample 环符号消失/降底噪记录 + probed transcript 稳态近零）+ flag 双向判别读数 + 挂账⑥ N≥3 轮逐轮日志（DB 行数机检）；T5：全套 --all = 3860+ΔN 对账闭合（批准制 + 8G 门 + MEMFAIL 机检）+ 红线族逐条机检 PASS；T6：SHELL-05 复走行集逐行终态 MANIFEST（波 1 四项 + M6C 余行 + 挂账④双通道对照表 N≥3/通道 + 挂账⑤ 缝兜底落地）零硬造；T7：SUMMARY/DECISIONS + FB 勘误两处落稿 + AGENTS 键族登记 + 台账翻新同批"
estimated_tests: "+2..6（T1 ShellReducedTreeGate 三分注入钉 +2..3〔新文件——Project.swift 恰一行 + tuist generate 恒末位〕+ 座移 AX 断言随迁 0..1 / T2 +0〔视图级 seam 走查承载，D-3 先例〕/ T3 +0..2〔carrier 可抽纯函数缝才加〕；执行时逐任务如实记账）"
test_bundles: [App]
baseline: "3860/35/0（FIX2 终态三路同值；HEAD 5f2bc07a，research 亲核 2427670e..HEAD 零产线文件——基线未漂移）"
expected_all: "3860 + ΔN（对账式；ΔN 预期带 +2..6，执行时按实记账；skip 35 = 基线 24 + RAW 供件域漂移 11 口径维持）"
red_lines:
  - "零新 SPM 依赖"
  - "UserDefaults 新键唯一 = shell.reducedTree（Bool，缺省 true；AGENTS 键族 T7 登记随批）"
  - "全部 *.metal 零 diff（本专项全 UI 域；翻案先停手修订本 plan 申报）"
  - "xcstrings 预期零 diff（flag 无 UI 文案；座移复用既有键）；确需新键 = 尾块纯插入 + DECISIONS 申报"
  - "\\.runModal( 在 App/Sources 零命中（L057 禁令——PanelPresentation.begin 缝 + 菜单/按钮 Task hop）"
  - "LocalizationValue 插值禁形代码零命中（插值 regex 形机检；LightamerApp.swift:2069 doc comment 豁免锚 + ExportInspectorView 拼接形豁免锚在案）"
  - "封存面零触：DrtRecord / TerminalTailPolicy / DrtTailAssembly / PixelPipe / Lut3dKernels.metal / DrtEotf / ExportQueueContract / 六格式导出矩阵（ExportFormatSpec·ImageIOEncoders·WebPEncoder）/ NodeGraphCommand / sidecar schema（LightamerSidecar）/ HistoryStack / HistoryHash / PipelineDocument（Core）/ V50Order / GradeCatalog（NodeOwnershipCatalog）/ Registry / ModuleInstance——壳树三文件 ContentView/WorkspaceHostView/LightamerApp 非封存已核（planner 2026-10-16 亲核）；V50Order add-only；MCP 快照族零触"
  - "app-root 级 sheet 闭包禁止裸 @Environment 跨界（M2-8 教训——内容面重注入或 init 参数注入二选一）；无 if/else 翻 @State 面（M-3——flag launch-immutable 构造保证）；M3-4-01 T4 挂载语义逐字迁移（present no-op / dismiss 双关）"
  - "Project.swift：新测试文件（ShellReducedTreeGateTests）= 恰一行登记 + BUNDLE-MAP 无涉（既有 target）+ tuist generate 恒为该批最后一个动作（L041）"
  - "构建 caffeinate -dis 包裹；单测 = Scripts/test-direct.sh --bundle <域>；全套 --all orchestrator 批准制 + 运行 8G 门 + MEMFAIL 机检 + 运行中保持监视（AGENTS 资源监控节）；测试宿主清理先核 parentage（ps -o ppid，M2-7-3 先例）"
files_modified:
  - App/Sources/Lightamer/UI/Shell/ShellReducedTreeGate.swift            # T1 新增：flag 单源（LibraryLegacyGate 孪生——UserDefaults 键 shell.reducedTree + env LIGHTAMER_REDUCED_TREE=0 覆盖 + 可注入纯函数读点 + 装配点一次求值）
  - App/Sources/Lightamer/UI/LightamerApp.swift                         # T1：装配点求值 + plain Bool 分发；T3：carrier 消费端重排（@FocusedValue/@FocusedBinding → carrier 字段读取）+ keyboardShortcut gate 收窄 + visibleMenuCommands phase 镜像断边
  - App/Sources/Lightamer/UI/ContentView.swift                          # T1：案 B——.inspector SystemSplitView 宿主（:205-223）flag-on 臂换条件尾列（240 ideal 钉，M3-4-01 T4 语义逐字迁移）；flag-off 臂字节冻结；T3：:228 exportPanelRequest 写点并 carrier
  - App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift              # T1：案 A——双 safeAreaInset（:153-157/:166-169）flag-on 臂迁 VStack 槽位（banner 上 topBar 之上 / toast 下 BackgroundTaskBarView 之下）；flag-off 臂字节冻结；T3：:170 focusedSceneValue 写点并 carrier；T6：挂账⑤ DEBUG 探针缝 exit(0) 兜底（DEBUG-only，产线行为零变更）
  - App/Sources/Lightamer/UI/InspectorView.swift                        # T3：:429 metadataFieldFocused 写点并 carrier（InspectorView 本体面零触）
  - App/Sources/Lightamer/UI/Shell/EditorWorkspaceShellView.swift       # T2 条件触面（C3 饿死裁定后才落产线：HStack 三段 → viewport hero + 可收起 overlay，flag-on 臂；flag-off 臂 = 现行三段字节冻结；不饿死则本行零 diff 撤销）
  - Tests/LightamerTests/ShellReducedTreeGateTests.swift                # T1 新增 +2..3 法（三分注入钉：缺省 ON / UserDefaults false off / env "0" 覆盖；Project.swift 恰一行 + tuist generate 末位）
  - Tests/LightamerTests/ToastFaceTests.swift                           # T1：3 法 AX wiring 断言随座位移过门（方法数零增减，断言面适配 VStack 槽位）
  - Tests/LightamerTests/SheetEnvironmentInjectionTests.swift           # T1：sheet 环境注入回归随列改造复核（预期零 diff；破绿 = 列改造面审）
  - Project.swift                                                       # T1：恰一行测试登记（tuist generate 恒末位，L041）
  - .work/gsd/phases/m7-1-shell/M7-1-01-SUMMARY.md                      # T7：执行摘要（逐任务 ΔN 记账 + 判别臂/铁条读数指针 + 走查 MANIFEST 终态摘要 + 分支结果申报〔C3 落地/呈报〕）
  - .work/gsd/phases/m7-1-shell/M7-1-01-DECISIONS.md                    # T7：裁定记录（flag 形态终值 / 案 A 座移终形 / 案 B 列终形 + 挂载语义迁移核对 / C3 scratch 裁定〔含窗拆顺带采数〕/ carrier 装配形 / 呈报件终稿〔若行使〕/ 挂账⑥ 裁定）
  - .work/gsd/research/APPLE-FB-D6-DRAFT.md                             # T7：两处勘误落稿（"~60 Hz" → display-cycle-locked ~60-120 Hz + CPU 带补 interact-after 98-100% 数据点；提交动作 = 用户手动，案号回填槽登记）
  - AGENTS.md                                                           # T7：「M7-1 架构增量」节（flag 形态 + 壳 seating 终形 + carrier 形 + ΔN 终值 + UserDefaults 键 shell.reducedTree 键族登记）
  - .work/TODO.md                                                       # T7：挂账④⑤⑥ + 复走波行翻账（D-FIX2-4 口径维持）
  - .work/GOAL-STATE.md                                                 # T7：续接点翻新（M7-1 代码面收口 → T6 走查批执行中 → 终态）+ SHELL-04 27.1 监测节律入巡检义务
---

> **夜间全自动授权**（先例 D-07-3-T5-1；晨审可推翻）。判读与裁决正本 =
> `M7-1-CONTEXT.md`（D-M7-1-1..6 全按 RESEARCH 推荐）+ `M7-1-RESEARCH.md`
> （复验门三判据亲跑全复现：图库/空载面 30-34% / 编辑器面 82-90% /
> probed transcript 21,363+21,360 @self-only ≈ 119 passes/s + 菜单环
> 六符号全链；壳树 file:line 测绘；案 A/B/C 判据面 + 验收铁条草案 §6.2）。
>
> **裁定权归属两钉（全 plan 生效，CONTEXT D-M7-1-1 同源）**：
> ①**C1/C2/窗拆的功能损失取舍 = 用户裁决**——worker 只产呈报件
> （三选项数据并列），呈报动作 = orchestrator 汇报层；agent 不得自裁
> 行使任一有损形落地产线。②**挂账⑥ 立项 = 用户裁决**——N≥3 轮间歇
> 再现 ≥2 → 登记呈报件，不自立专项。
>
> **执行序**：T1 → T2 → T3 → T4 → T5 → T6 → T7。T2 有真实分支
> （饿死落产线 / 不饿死呈报），T3..T7 在两分支下均继续（接受降级基础上
> 不受阻——不饿死分支的编辑器面 <10% 硬门诚实保持未达并登记）。
> 每任务独立 commit（Conventional Commits，全英文，只 add 相关文件，
> 不 push）。GUI 走查/探针证据落 `.work/gui-acceptance/m7-1/`
> （local-only，零 commit）；scratch 实验一律 /tmp 即弃或 feature-gated
> 零产线 commit。harness 三钉前提（RESEARCH §0.4）：zh 菜名寻址 /
> `script` 封装 PID 陷阱（真 pid 从 pty 日志头读）/ PTY 行缓冲 +
> `^D` 前缀容忍。

# Plan M7-1-01 — D-6 壳专项（案 A+B → 案 C3 → 燃料减频 → 铁条 → 对账 → 复走 → 收口）

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/m7-1-shell/M7-1-CONTEXT.md`（OQ 裁决 + 红线 + 裁定权归属）
- `.work/gsd/phases/m7-1-shell/M7-1-RESEARCH.md` §0（判别探针配方三钉）+
  §1（壳树测绘 + 案清单）+ §3（燃料面）+ §5（复走行集）+ §6.2（铁条草案）
- `.work/config.toml [gsd]` paused/auto 开关（亲核 2026-10-16：auto=true /
  paused=false）
- `.work/LESSONS.md` L077（$TMPDIR 残留清扫——PTY 探针 kill 后必扫）/
  L041（tuist generate 恒末位）/ L014（GPU 读回 fence——本批无 GPU 读回，
  预期不触）
- `.work/gsd/phases/fix2-defects/FIX2-01-DECISIONS.md` D-FIX2-1（threshold
  形判据正本）+ `gui-acceptance/v2m/fix2-probe/`（判别探针族配方域）
- `.work/gui-acceptance/m7-1/`（research 复验证据域——transcript/sample/
  CPU 系列正本，判别臂读数对照基线）

---

## T1 — 第一刀案 A+B「空载面零 churn 包」+ `shell.reducedTree` flag + 判别对照臂（M-L；判别力基座）

> **判据正本（FIX2 已证，RESEARCH §1.2/§1.3）**：空载面摘 `.inspector`
> （C1）**或**摘双 safeAreaInset（C2）任一 → 环饿死（sceneBody 2/25s，
> CPU 归零）——两案判据均已证，合并为一包减少一轮走查批。编辑器面摘
> inset/inspector **不**饿死（预期复燃维持，案 C 才是编辑器面主攻）。
> **flag（CONTEXT D-M7-1-4）**：launch-immutable 运行时 flag，装配点
> 一次求值；flag-off 臂 = 现行 seating 逐字节冻结（判别臂 + QA 回切
> 通道）；flag-on 臂 = 减树形态。**legacyBody 字节冻结纪律不触**——
> 本任务全部落点在 gate=false 分支（ContentView:177-241 /
> WorkspaceHostView body 面），`legacyBody`（:243 起）零 diff。

**read_first**：`M7-1-RESEARCH.md` §1.1（壳树 file:line 全录）+ §1.3
案 A/B 行 + §6.2 案 A+B 铁条；`App/Sources/Lightamer/UI/ContentView.swift`
:177-241；`App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift`
:124-175 + :595-660（topBar）+ :1438-1520（banner/toast 视图本体）；
`App/Sources/Lightamer/Library/LibraryPreferences.swift`（LibraryLegacyGate
孪生范式正本）；`Tests/LightamerTests/ToastFaceTests.swift` +
`SheetEnvironmentInjectionTests.swift`。

- **action**：
  1. **flag 单源**：新增 `App/Sources/Lightamer/UI/Shell/ShellReducedTreeGate.swift`
     （LibraryLegacyGate 孪生）：UserDefaults 键 **`shell.reducedTree`**
     （Bool，**缺省 true = 减树形态默认开**）+ env 覆盖
     **`LIGHTAMER_REDUCED_TREE=0`**（QA/判别回切；优先级 env > defaults >
     缺省）+ 唯一可注入读点
     `isReducedTreeEnabled(environment:defaults:)` 纯函数（测试注字面
     字典/suite）；`LightamerApp` 装配点求值**一次**、plain Bool 分发，
     view body 零 `ProcessInfo`/UserDefaults 直读。flag = launch-immutable
     （无 Settings 开关）——if/else 臂在进程寿命内不翻转，@State 结构
     身份跨臂稳定由构造保证（M-3 教训不触）。
  2. **案 A inset 迁移（flag-on 臂；WorkspaceHostView:153-169）**：
     `ProjectReadOnlyBannerView` 座位迁入 host VStack（`topBar` 之上）、
     `ToastBarView` 座位迁入 host VStack（`BackgroundTaskBarView` 槽
     之下）——safeAreaInset ×2 → 0。功能面逐字保持：同一两视图、同一
     数据源、同一 AX 标识符（`shell.readonly.banner` / toast 面
     ToastFaceTests 契约两半）；`.animation(value: editorState.toast)`
     随 toast 挂载点同迁；零高度语义保持（writable/无 toast = 无
     chrome）。flag-off 臂 = safeAreaInset ×2 原位（字节冻结）。
  3. **案 B inspector 列改造（flag-on 臂；ContentView:205-223）**：
     `.inspector(isPresented:)` SystemSplitView 宿主 → 条件尾列（自绘
     HStack 尾列，仅页面开关活时挂载）。**挂载语义逐字迁移（M3-4-01
     T4 教训 = 最大风险点）**：present 侧 no-op / dismiss 双关
     （`closeExportPage` + `closeFilmPage` 幂等）逐字保持为列可见性
     单真相（无第二呈现 flag）；**InspectorView 只在本宿主可达**的
     OR-term（`exportPageActive || filmPageActive`）逐字保持——film 页
     分支结构性可达性回归钉 = 既有走查 + AX 断言族随迁。宽度 =
     **ideal 240 钉死**（`layout.inspectorWidth` 记忆键保留读取，缺省
     回落 240；拖拽自实现挂账——CONTEXT D-M7-1-6）。flag-off 臂 =
     `.inspector` SystemSplitView 原位（字节冻结）。
  4. **AX 断言族随迁**：`ToastFaceTests` 3 法（AX 树 wiring 断言）
     适配 VStack 槽位（方法数零增减、契约两半断言面不变）；
     `SheetEnvironmentInjectionTests` 复核零 diff 预期（破绿 = 列改造
     面审）；**app-root 级 sheet 闭包禁裸 `@Environment`**（M2-8 教训
     ——列改造若触 sheet 面，内容面重注入/init 参数注入二选一）。
  5. **回归测试**：`ShellReducedTreeGateTests`（新文件，+2..3 法）——
     ①缺省（键缺席）= true；②UserDefaults false = off；③env "0"
     覆盖优先。`Project.swift` 恰一行登记 + `tuist generate` 恒末位
     （L041）。
  6. **判别对照臂（SC 主判据之一）**：flag-on fresh build（干净
     DerivedData）图库/空载面**可见窗**静置 10×1s `ps` CPU 系列 +
     probed build transcript（三文件插桩配方 RESEARCH §0.3——PTY
     `script -q` 捕获、kill 后 `git checkout --` 回退、/tmp 即弃）
     10s 稳态窗；flag-off 重跑同配方 = 复现 23-34% 带。证据落
     `.work/gui-acceptance/m7-1/t1-*/`。
  7. **功能走查三件**（铁条④）：toast 通道（哨兵 toast 默认面可见 +
     4s auto-clear + AX 标识）；只读横幅（`shell.readonly.banner` AX
     断言——M6-1 第二实例只读面）；M6-1 冲突对话框面。AppKit 底噪
     注记（~11Hz 族残留不判 FAIL，记录口径——RESEARCH §1.2）。
- **验收标准（机检）**：
  - flag-on 图库/空载面可见窗 CPU **<5%**（10×1s `ps` 系列证据，逐点
    值落证据文件；**<10% = §5.4 判据一门亦过**——两口径同录）。
  - probed transcript 稳态 **10s 窗零 scene-body 重估行**（0 行；
    ~3min 全窗读数同录）；对照 = research 基线 21,363/21,360。
  - flag-off 对照 = 空载面复现 **23-34% 带**（判别臂 transcript；
    越带 = 判别臂失效，停手查环境漂移再续）。
  - 功能走查三件证据在案 + AX 标识符零回归（`shell.readonly.banner`
    grep + ToastFaceTests 全绿）。
  - `--bundle App` 全绿（含新 gate 法 + 随迁断言）。
  - `legacyBody` 零 diff（`git diff App/Sources/Lightamer/UI/ContentView.swift`
    逐 hunk 核——改动全落 gate=false 分支与分发线）。
- **commit**: `fix(m7-1): cut the idle-face churn loop behind a reduced-tree shell flag`

## T2 — 第二刀案 C3：零损失重组 scratch 实验门（饿死性未证须裁；不饿死 = 呈报用户）

> **判据空缺面（RESEARCH §1.3/§1.4）**：E 系证据只覆盖「摘除」
> （三段任摘一段 → 饿死），**不覆盖「重组」**——C3（viewport hero +
> 可收起 overlay，常驻性 UI 保持）是否跌破 threshold 只有实验能裁。
> **先探针定罪再动手纪律延续（防三改）**：scratch 实验门先行，
> 裁定后才落产线。**裁定权归属钉（CONTEXT D-M7-1-1）**：C3 饿死 =
> worker 落产线（零损失主修）；C3 不饿死 = **C1/C2 呈报用户二选一**
> （呈报 = orchestrator 汇报层，**非 agent 自裁**——两形均有真实
> UI 对标损失），窗拆 scratch 数据并列呈报；本任务产线零 diff，
> 编辑器面 <10% 硬门诚实保持未达（接受降级残余登记，FIX2 T1
> BLOCKED 分支先例形），T3..T7 不受阻继续。

**read_first**：`M7-1-RESEARCH.md` §1.3 案 C 三形 + §1.4 复燃预判表 +
§2（窗拆四面评估 + §2.4 顺带采数义务）+ §6.2 案 C 铁条；
`App/Sources/Lightamer/UI/Shell/EditorWorkspaceShellView.swift:40-95`
（三段 HStack + filmstripWidth 148 / rightPaneWidth 280 常量）。

- **action**：
  1. **C3 scratch 实验**（/tmp 即弃或 feature-gated scratch build，
     零产线 commit）：HStack 三段 → viewport hero + 可收起 overlay
     （filmstrip 148 / rightPane 280 作为视口 overlay 层，常驻性 UI
     保持）。E 系等效读数三件：①编辑器面静置 10×1s `ps` CPU 系列
     ②probed transcript 稳态重估率（PTY 配方 §0.3）③`sample <pid> 6
     -file` 环符号计数。判读门 = <10% 硬门 + transcript 稳态近零。
  2. **窗拆 scratch 顺带采数（§2.4 义务，同批两实验）**：SHELL-02
     窗拆最小 scratch（编辑器内容独立 Window scene）同批采
     CPU/transcript 读数——数据入 DECISIONS 挂账「结构终案备选」档
     （CONTEXT D-M7-1-2），零产线代码，呈报件并列项。
  3. **分支 A——C3 饿死 → 落产线**：`EditorWorkspaceShellView`
     flag-on 臂换 overlay 形（flag-off 臂 = 三段 HStack 字节冻结）；
     spin 消失三步铁条：①filmstrip 点击出图（**cliclick 真实鼠标**
     `c:x,y`——AXPress 表型混淆挂账④不作为判据通道）②视口渲染
     ③右栏 mount——三步各一截图。布局走查：overlay 收起/展开 +
     filmstrip 换图游标 + 右栏调整栈 mount + Alcedo IA 零偏离声明
     （C3 零损失构造）。
  4. **分支 B——C3 不饿死 → 登记不落 + 呈报件**：产线零 diff（本任务
     `git diff --stat` 仅 docs/证据）；呈报件登记 DECISIONS +
     SUMMARY：C3 实测读数 / C1 功能损失陈述（右栏并入 inspector 列，
     偏离 Alcedo 三段 IA）/ C2 功能损失陈述（filmstrip 收弹出层，
     常驻性损失两步换图）/ 窗拆 scratch 读数——四项并列，
     **orchestrator 汇报层呈报用户二选一**；agent 不落任何有损形。
- **验收标准（机检）**：
  - scratch 实验读数三件在案（CPU 系列 + transcript + sample，
    `.work/gui-acceptance/m7-1/t2-c3-scratch/`）+ 裁定 + 数字落
    DECISIONS。
  - 分支 A：编辑器面 **<10%**（10×1s ps）+ 三步铁条截图 + 稳态
    transcript 近零 + flag-off 编辑器面复现 **82-90%**（判别臂）+
    `--bundle App` 全绿。
  - 分支 B：本任务产线零 diff 机检 + 呈报件四项并列在案。
- **commit**：分支 A `fix(m7-1): restructure the editor shell as a viewport hero with overlays`；
  分支 B `docs(m7-1): register the C3 scratch verdict and the loss-report item`

## T3 — SHELL-03 五燃料面减频（焦点写点合并 + shortcut gate 收窄 + phase 镜像断边；纯叠加放大器）

> **定位（RESEARCH §3.3）**：燃料减频**单独不承诺饿死环**（threshold
> 决定面在树侧）——纯叠加放大器：降低每 pass 成本 → 与减树叠加提高
> 饿死裕度 + 压低残余底噪。**范围钉**：carrier 合并只落 **gate=false
> 面**（:228 / :170 / :429 三写点 → 1 carrier）；**legacyBody :287-288
> 字节冻结不触**（M2-2-4 gate 纪律；legacy 面 QA-only 通道燃料不在
> 默认路径）——RESEARCH「5→1」双面计数在 gate=false 面的生效值 =
> 3→1，prependValue 实测降幅以 sample 前后计数对承载。Equatable 值
> 去重**已证无效**（D-FIX2-1：`PropertyList.prependValue` 无值去重）
> ——本任务削的是**次数**不是值。

**read_first**：`M7-1-RESEARCH.md` §3.1（燃料面 file:line）+ §3.2 减频
候选 + §6.2 SHELL-03 铁条；`App/Sources/Lightamer/UI/LightamerApp.swift`
:443-489（@FocusedValue/@FocusedBinding 族 + visibleMenuCommands）+
:1502-1600（Commands 块头部——shortcut/ForFirst 面）；`ContentView.swift`
:228（gate=false exportPanelRequest）；`WorkspaceHostView.swift:170`；
`InspectorView.swift:429`（metadataFieldFocused）。

- **action**：
  1. **焦点写点合并（gate=false 面 3→1）**：一个 carrier struct 单键
     （workspace model 引用 + columnVisibility / exportPanelRequest /
     metadataFieldFocused 三 binding 槽）替代三处 `.focusedSceneValue`
     发布；消费端 `LightamerApp` 四个 @FocusedValue/@FocusedBinding
     属性重排为 carrier 字段读取（**legacy 键 fallback 面**：legacyBody
     继续发布旧键——消费端读 carrier 优先、旧键回落，形态 DECISIONS
     申报；装配宿主 = WorkspaceHostView 为天然单点〔topBar 已读
     inspectorState〕，跨 view 字段桥接形执行批定）。**mount-time
     priming 语义铁钉（FIX2 M-2 教训）**：窗口打开至首次 phase 翻转
     之间 ⌘E/⌘W/⌘F/View toggles 可用（carrier 挂载发布腿覆盖）——
     启动即按走查点验。
  2. **keyboardShortcut gate 收窄**：29 个 shortcut 逐个核对——挂在
     gate=false 面不显示命令上的无条件件，`.keyboardShortcut` 修饰符
     移进对应 `visibleMenuCommands` gate wrap 内；可见且无条件命令
     （如 ⌘O :1527——gate=false 面可见）原位不动。行为等价钉：
     隐藏命令的 shortcut 本就不触发，移 wrap = 零行为变更、纯削重挂
     热帧（mangled-name 与 shortcut 件数正相关）。
  3. **`visibleMenuCommands` phase 镜像断边**：getter 读
     `focusedWorkspace?.phase`（图依赖边）→ phase 镜像进 app root
     本地态（onChange 同步——镜像写必须 change-driven 非
     render-driven，禁每 pass 写点）；菜单渲染对焦点图的依赖边断开。
  4. **菜单件数裁剪（激进档）不触**（RESEARCH §3.2.4 独立裁决挂账）；
     **ForEach 不动**（id 已稳定）。
  5. **sample 前后计数对（独立验收判据）**：T1/T2 完成态 build 与
     T3 后 build 各采 `sample <pid> 6 -file`（同配方同窗）——
     makeMainMenu / updateMainMenu / prependValue / mangled-name
     四项计数前后对照表落证据。
- **验收标准（机检）**：
  - 四项计数对照表在案且**可测下降**（prependValue 降幅与 3→1 合并
    同域；具体值如实记录，样本窗差异注记）。
  - MenuCommandSet IA 矩阵测试族全绿（`--bundle App`）+ 菜单全量手动
    走查（command 可用性矩阵抽查：图库/编辑器两面 File/View/编辑
    命令）证据在案。
  - 行为三钉走查：⌘E/⌘W/⌘F 启动即用（priming）+ 元数据输入态裸键
    self-disarm + export 路由开页——零回归。
  - legacyBody 零 diff（:287-288 写点原位）。
- **commit**: `fix(m7-1): merge the shell focus publishes into one carrier and narrow shortcut remounts`

## T4 — 验收铁条：三判据探针转绿终验 + 挂账⑥第一轮复测（N≥3）

> **验收形态（RESEARCH §5.4 = REQUIREMENTS M7-1 行原文）**：D-6 复现
> 配方 churn 探针转绿三判据 + 回切 flag 对照判别力。本任务在 T1-T3
> 终态 build 上跑（编辑器面判据随 T2 分支：分支 A = 硬门判定，
> 分支 B = 诚实残余记录）。

- **action**：
  1. **判据一 CPU 硬门**：图库/空载面（T1 已录 <5%，此处终 build
     复测）+ 编辑器面（分支 A：<10% 判定；分支 B：读数如实录 +
     残余登记）——各 10×1s `ps` 系列。
  2. **判据二菜单环符号**：`sample <pid> 6 -file` 环符号链
     （flushTransactions/graphDidChange/appGraphDidChange/
     makeMainMenu/updateMainMenu/invalidateProperties/requestUpdate/
     updatePreferences）消失或降底噪——符号计数 vs RESEARCH §0.2
     基线对照表。
  3. **判据三 @self 决定性读数**：probed build（三文件插桩 §0.3 配方
     ——PTY 捕获、`^D` 容忍、kill 后回退、/tmp 即弃）稳态重估读数：
     10s 窗 0 行为门，~3min 全窗读数同录（对照基线 21,363/21,360）。
  4. **flag 双向判别**：flag-off 重开项目 + 进编辑器全配方 = 复现
     23-34%（空载）/ 82-90%（编辑器）——转绿是修法效果非环境漂移的
     判别力证。
  5. **挂账⑥导入零行间歇复测（N≥3 轮；CONTEXT D-M7-1-5）**：probe
     配方（`-la_editor_probe` 建项目 → 杀进程重启 → zh 菜名 AX 腿 →
     导入 ≥6 供件〔`/tmp/fix2acc-import` 或新备同量供件〕）× N≥3 轮
     ——每轮 DB 行数机检（= 供件数）+ grid 刷新时点记录 + 完成态
     发布面。**裁定**：零间歇再现 → 「修后证据」注记（churn 消解
     旁证，非逻辑证伪——如实措辞）；间歇再现 ≥2 轮 → 呈报件登记
     （**立项 = 用户裁决**，不自立专项）。D-FIX2-4 勘误口径维持
     （禁再循 insert 路径排查）。
  6. **截图三面**：修后 D-6 态（编辑器三段/overlay 面）+ 图库面 +
     filmstrip 出图——证据域归档。
- **验收标准（机检）**：三判据读数表 + flag 双向对照表 + N≥3 轮逐轮
  日志（DB 行数机检行）全落 `.work/gui-acceptance/m7-1/t4-*/` +
  MANIFEST 行登记；分支 B 编辑器门未达 = 诚实 BLOCKED 残余登记
  （不硬造判定）。
- **commit**: `docs(m7-1): record the post-fix probe verdict and the import re-test rounds`

## T5 — 全套对账收口（批准制 + 8G 门 + 红线族 + ΔN 申报）

- **action**：
  1. 红线族机检（front-matter `red_lines` 逐条亲跑）：`.metal` 全域
     零 diff / 封存面 17 件零 diff / V50Order 零触 / MCP 快照族零触 /
     runModal 零命中 / LocalizationValue 插值禁形 regex 零命中（两
     豁免锚在案）/ UserDefaults 新键唯一 `shell.reducedTree` /
     xcstrings 预期零 diff（新键则尾块纯插入 + DECISIONS 申报）/
     Project.swift 恰一行 + tuist generate 末位核 / legacyBody 零 diff。
  2. **全套确认轮**：`caffeinate -dis Scripts/test-direct.sh --all`
     （**orchestrator 批准制**——夜间授权链覆盖在案，批准前 T6 不开工；
     运行中保持监视 + 8G 门 + MEMFAIL 机检，超门立即 kill）。
  3. `TOTAL|3860+ΔN/35/0|` 对账闭合（ΔN 逐任务记账；skip 35 构成
     声明——第三种 skip 来源 = 逐族差分申报禁静默吸收）。
- **验收标准（机检）**：exit 0 + 0 fail + 0 MEMFAIL + 七 bundle 全 8G
  门内 + 对账精确闭合 + 红线族全 PASS。
- **commit**: `docs(m7-1): reconcile the full suite and pass the red-line battery`

## T6 — 走查复走批（SHELL-05 专项卷；T5 全绿后）

> **行集正本 = RESEARCH §5.2 五波总表 + FIX2-VALIDATION §挂账④⑤⑥ +
> V2M-VALIDATION §挂账②**。harness 前提三钉（§0.4）：zh 菜名寻址 /
> `script` 封装 PID 陷阱 / PTY 行缓冲。通道受阻 = Blocked 如实登记
> （「不硬造判定」条款兜底——代码面证据禁替代屏面判据销账）。

**read_first**：`M7-1-RESEARCH.md` §5（双路七观察 + 五波行集 + §5.3
cmd+click 配方）+ `gui-acceptance/v2m/fix2-probe/`（判别族域）+
`gui-acceptance/m6-closeout/MANIFEST.md`（余行判据原文 + harness 教训
批注）。

- **action**：
  1. **复走波 1（屏面四项；V2M-VALIDATION §挂账②）**：V2M-T1-02
     （追色 solve 屏面：进度态/读数 1s 内 + history item + sidecar）/
     D3-01（filmstrip ≥4 图 ×N 轮连点零卡死）/ D4-01（合并对话框三
     计数——legacy 会话腿 ⌘⇧O 配方）/ D5-01（merge 完成 toast zh
     文案）——修后 build 逐行走查。
  2. **复走波 2（M6C Blocked 余行）**：M6C-03/05/06/07/08（追色族）+
     16-19（pano——合成切片供件）+ 32/33（无人像 toast / 羽化三档）+
     34-38（栈面）+ 40（guided filter）——D-6 通道恢复后的解锁复走
     （编辑器面行放波尾，依赖通道稳定）。
  3. **复走波 3（挂账④点击表型双通道对照）**：filmstrip 点击 +
     cmd+click 多选两目标 × 两通道（AXPress `osascript click` /
     cliclick 真实鼠标 `kd:cmd c:x,y ku:cmd`——坐标从 AX
     `AXPosition`+`AXSize` 求中心）× N≥3 重复——**通道 × 目标 × N
     结果表**定表型边界（AXPress 伪象 vs 间歇真死），DECISIONS 登记
     裁定。
  4. **挂账⑤（顺手窗）**：`-la_editor_probe` DEBUG 探针缝补
     `exit(0)` 兜底（`WorkspaceHostView` DEBUG 域，产线行为零变更；
     T6 触缝时落地——`NSApp.terminate` 遮挡态不可靠先例 2/2 + 3/3）。
  5. **D-FIX2-4 旁证复测**：grid 刷新迟到面在走查轮的旁证记录
     （T4 N≥3 轮为主判据，此处记走查侧观察——一致则互证，不一致
     如实分载）。
  6. **排除行逐行理由注记**（先例条款：静默排除须注记）——供件/
     硬件缺座维持行逐行列由。
  7. **MANIFEST 终态**：`.work/gui-acceptance/m7-1/MANIFEST.md`
     逐行记账（行 id + 判据 + 通道 + 证据指针 + 终态）。
- **验收标准（机检）**：波 1/2/3 逐行终态入 MANIFEST（Executed 带
  屏面证据；Blocked 如实保持）；挂账④双通道对照表在案（N≥3/通道/
  目标）；挂账⑤ diff 落 DEBUG 域（产线 hunk 零）；排除清单逐行
  理由；零硬造 Executed。
- **commit**: `fix(m7-1): add the probe-seam exit fallback and record the walkthrough waves`
  （挂账⑤代码腿；纯文档腿并入 T7 台账 commit）

## T7 — 收口：SUMMARY/DECISIONS + FB 勘误随批 + MANIFEST 终态 + 翻账申报

- **action**：
  1. **SUMMARY**（逐任务 ΔN 记账 + 判别臂/铁条读数指针 + 分支结果
     申报〔C3 落地或呈报件 + 挂账⑥ 裁定〕+ 走查 MANIFEST 终态摘要）
     + **DECISIONS**（flag 形态终值 / 案 A 座移终形 / 案 B 列终形 +
     挂载语义迁移核对 / C3 scratch 裁定〔含窗拆顺带采数〕/ carrier
     装配形 + legacy fallback 面 / 呈报件终稿〔若行使〕/ 挂账④表型
     裁定 / 挂账⑥ 裁定）。
  2. **FB 勘误两处随批**（CONTEXT D-M7-1-3）：`.work/gsd/research/
     APPLE-FB-D6-DRAFT.md` 落稿——①"~60 Hz" → display-cycle-locked
     （~60-120 Hz per display refresh；119 passes/s = ProMotion 120Hz
     锁频）②CPU 带补 interact-after 98-100% 数据点；**提交动作 =
     用户手动**（呈报层），案号回填槽登记（FB 案号到达 = SHELL-04
     闭环判据之一，后续批回填）。
  3. **AGENTS**：「M7-1 架构增量」节（flag 形态 + seating 终形 +
     carrier 形 + ΔN 终值 + 全套终值）+ **UserDefaults 键族登记
     `shell.reducedTree`**；**TODO**：挂账④⑤⑥ + 复走波行翻账
     （D-FIX2-4 口径维持）；**GOAL-STATE**：续接点翻新（M7-1 代码面
     收口 → T6 执行中 → 终态分两步落——T5 时写「T6 执行中」，
     T6 终态后才翻 closed，M-6 账实倒挂教训）+ **SHELL-04 27.1
     监测节律入巡检义务**（三信源 + 关键词 + 命中复测 §0 配方）。
  4. **翻账申报**：呈报件清单（C1/C2 二选一〔若分支 B〕/ 挂账⑥ 立项
     〔若再现〕/ FB 案号待回填）汇总于 SUMMARY 尾节——orchestrator
     汇报层消费。
- **验收标准（机检）**：三台账同批落盘（§3.1 文档原子同步；历史行只
  追加不改写）+ FB 勘误两处 grep 在稿 + 键族登记在 AGENTS + SUMMARY
  呈报件节在案。
- **commit**: `docs(m7-1): close the D-6 shell special project ledgers`

---

## 风险与回退

- **T1 案 B 挂载语义**：条件尾列若破坏 export/film 页 dismissal 语义
  （present echo / dismiss 双关）→ 回退 = 列改造臂回退到
  `.inspector` 形仅保留案 A（空载饿死判据 C2 单独成立——C1/C2 任一
  即饿死，判据面允许单案 A 交付），DECISIONS 申报 + 呈报件更新；
  SheetEnvironmentInjectionTests/ToastFaceTests 破绿 = 硬停（AX 契约
  回归禁收）。
- **T1 flag 判别臂失效**（flag-off 读数越 23-34% 带）= 环境漂移或
  flag 泄漏（body 直读态混入）——停手查 `git diff` 臂隔离再续，禁
  带病进门。
- **T2 C3 scratch 不收敛**（重组后仍 82-90% 域）→ 分支 B 照走
  （登记 + 呈报），**禁**未裁定直接改产线三段树（防三改红线）。
- **T3 carrier priming 缺口**（启动即按 ⌘E/⌘W 失效）= 挂载发布腿漏
  ——修复腿而非回退合并（FIX2 M-2 双腿形先例）；legacy fallback 面
  破坏 legacy 面行为 = 回退该键合并（gate=false 三点合并保底）。
- **T4/T6 通道受阻**（菜单腿/AX 表型）→ Blocked 如实登记，禁硬造；
  挂账⑥ N 轮中 crash/宿主异常 → 换新供件目录重跑该轮（轮数如实记）。
- 全套轮任何 fail：先归因（本批 Δfiles 窗内?）——窗外 fail = 既有
  缺陷，停手上报不静默修（NLMeans flake 先例：隔离重跑 + 台账）。

---

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：RESEARCH §6.1 推荐序五刀 ↔ T1（第一刀）+ T2
   （第二刀 + 窗拆采数）+ T3（燃料叠加）+ T4/T5（SHELL-04/05 验收
   面）+ T6（复走波）+ T7（FB/监测）逐项映射；SHELL-01..05 五需求
   行无孤儿项。
2. **裁定权归属核**：T2 分支 B / 挂账⑥ 立项 / FB 提交三处 = 用户
   裁决 + orchestrator 汇报层——plan 文面不得出现 agent 自裁行使
   有损形（C1/C2/窗拆落地）的路径；呈报件四项并列结构核对。
3. **flag 形态核**：launch-immutable / 装配点一次求值 / body 零直读
   / env > defaults > 缺省序 / 缺省 ON——CONTEXT D-M7-1-4 五条逐条
   对 T1 action 1；UserDefaults 键拼写唯一（`shell.reducedTree`）。
4. **字节冻结面核**：legacyBody 零 diff（T1/T3 双任务都须过）；
   flag-off 臂 = 现行 seating 逐字节（案 A/B 双改造均臂内）——
   checker 逐 hunk 核「改动全落 flag-on 臂」。
5. **M3-4-01 T4 挂载语义**：T1 案 B 后 present no-op / dismiss 双关
   / OR-term 逐字在位（ContentView 改造段亲读）；InspectorView 仍
   只在该宿主可达。
6. **T3 范围钉**：gate=false 3→1（非 5→1——legacy :287-288 冻结）；
   priming 铁钉（启动即按）；mirror 写 change-driven；菜单件数裁剪
   未触（挂账独立裁决）。
7. **SC 数字门可机检性**：CPU 系列逐点值 / transcript 行计数 / flag
   对照带 / N≥3 轮日志 / sample 计数对——每条 SC 有命令级判据非
   「目测」；分支 B 的编辑器门 = 诚实 BLOCKED 形非放水。
8. **ΔN 对账**：expected_all 对账式非死数；新测试文件恰一行登记 +
   tuist generate 末位（L041）；skip 35 构成声明（第三来源 = 差分
   申报）。
9. **红线干跑**：`.metal` 零 diff / 封存面 17 件 / runModal /
   LocalizationValue regex 形（两豁免锚）/ xcstrings 预期零 diff /
   MCP 快照族零触——T5 机检清单可独立复跑。
10. **走查不硬造**：T6 MANIFEST Executed 行须屏面证据；Blocked 保持；
    排除行逐行理由；挂账④双通道表 N≥3 且两通道并列（禁单通道定表型）。

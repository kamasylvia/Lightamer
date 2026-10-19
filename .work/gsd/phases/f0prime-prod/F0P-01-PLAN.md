---
phase: f0prime-prod
plan: "F0P-01"
title: "plan P1 — 审计修复先于翻转（T1 probe-stay hunk 落 main / T2 缺口1 zoom 构造参数化 / T3 缺口2 exportPresent onChange 化〔bridge 生产形落地〕/ T4 缺口3 四 stub 生产化〔ShellGraph+columnVisibility 提升 + 三窗控制器〕/ T5 toolbar 差异登记）→ 壳交接翻转（T6 @main NSApplicationDelegate 化 + NSHostingView 承载 + NSMenu 全族装配去桩 + ShellGraph 扩展 + reopen/fullscreen/autosave 三行 + LightamerShell* 生产改名——翻转 commit 独立可 revert）+ D-6 探针门（T7 绝对 <10% + L082 四哨兵 + 走查面 1-9/14 冒烟级 + SUMMARY/DECISIONS）"
wave: 1
depends_on: []
autonomous: true
requirements: ["F0-prime charter = 用户三裁决入库（35a6c178）：①壳交接生产立项（壳交接 + 菜单全族 parity + 未追踪 @Observable 读审计〔硬前置〕+ @State→@Observable + 全套回归，量级 M）②面迁移 F1-F3 无限期 park ③FB 稿补强", "调研正本 = phases/f0prime-prod/RESEARCH.md（§1 壳交接生产形 / §2 菜单全族 / §3 未追踪读审计〔4 缺口正本〕/ §4 @State 迁移 / §6 回归走查 / §7 切分 / §9 锚点）", "OQ 裁决正本 = phases/f0prime-prod/CONTEXT.md（D-F0P-1..10 全按 RESEARCH §8 推荐，晨审可推翻；特别登记 = 无 QA 回切 + D-6 绝对门 <10% 正门；转写勘误三条）", "spike 正本 = phases/nsmenu-spike/{F0PRIME,SPIKE}.md + 分支 spike/f0prime-shell（a35ad151 probe-stay / c9a91562 壳交接 / d8d1380a trace；patch 正本 0001..0003-*.patch + f0prime-full.stat）", "测试基线权威数 3969/37/0（勘误 RESEARCH 3905——CONTEXT §转写勘误①）；本 plan 带 +0..2；全批带 +15..+25 → 终值带 3984..3994", "C 档停位 = 本 plan 执行+验收闭环后停汇报；确认后 P2 起跑"]
success_criteria: "SC 全可机检——T1：probe-stay hunk 逐字落 WorkspaceHostView.swift（patch 0001 形，7 注释 + 3 代码）+ grep `la_probe_stay` App/Sources 恰 1 命中 + 构建绿；T2：EditorMTKView updateNSView 内 `viewportState.(zoom|pan|rotationDegrees)` 读零命中（签名求值迁构造参数）+ EditorAreaView body 含 ZoomSignature 构造（body tracked read 显式化）+ push-once 语义零改（coordinator.zoomSignature 比对臂仍在）+ 手势路径零触（coordinator 自持 view 引用）；T3：Shell/NSMenuBridge.swift 生产形落位（onChange 双态 note 注入形）+ ContentView export note = `.onChange(of: exportPanelRequested)` 双态注入（spike onAppear 一次性形零带入——grep `noteExportPanelRequestPresent(true)` 的 onAppear 包裹形零命中）+ InspectorView metadataFieldFocused onChange note（B19）+ WorkspaceHostView workspace onAppear note（B20 单窗形）落位；改形点三件（review m6/M4）：Deps +inspectorState 字段 + 观察适配器读集终形 + menu_open_session ⇧⌘O = openSessionFolder picker 缝（grep `recentSessions.first` NSMenuBridge 零命中）；T4：Shell/ShellGraph.swift（9 spike 字段 + columnVisibility 第 10 字段）+ Shell/ShellWindowControllers.swift 三窗控制器（PresetManager/McpLauncher/Settings——env 注入面逐项对齐 HEAD scene 形）+ ContentView columnVisibility binding 双向桥 graph（⌥⌘S/⌥⌘I 写回路径就绪；实例单源形开工前 DECISIONS 三选一定死——review M2）；T6：entry GUI 臂尾 = ShellMain.run()（fork 序逐字零触）+ Shell/LightamerShell.swift（Face 逐字搬运 + Delegate 组合转发 + Controller + Main）+ NSMenu 全族装配（四 stub 真接线：presetManager/mcpLauncher/showSidebar/showInspector 闭包体零空形 + Settings ⌘, 真窗控制器 + export gate=false 臂直走 openExportPage）+ applicationShouldHandleReopen + styleMask .fullScreen + setFrameAutosaveName(\"LightamerMainWindow\") 三行 + WindowCapture private→internal 恰一处（review m4）+ ContentView :551 toolbar preset-manager openWindow 缝接线（review M1——翻转后 openWindow 在 ContentView 零命中机检）+ `F0PrimeShell` App/Sources 零命中（生产改名 LightamerShell*）+ 翻转 = 恰一个 commit；T7：D-6 探针门 = 生产翻转二进制三轮 probe-stay 驱动 %cpu 中位 <10%（30s 窗 6 采样 @6s 中位）+ L082 四哨兵全过（frontmost=true / 窗内截图可见 / 主线程样本泊 mach_msg2_trap / churn 符号族〔UpdateStack/sizeThatFits/beginTransaction〕零）+ 走查面 1-9/14 冒烟级逐项记录 + SUMMARY/DECISIONS/MANIFEST 落盘"
estimated_tests: "+0..2（T2 ZoomSignature 求值如抽纯函数可加相等性负测 +0..2，合法 ΔN=0——本 plan 验收 = 构建 + probe 门 + 冒烟走查，测试族归 P2；执行时逐任务如实记账，越带申报理由）"
test_bundles: [APP]
baseline: "3969/37/0（audit-repair 批收口 9898a0fb 终态，勘误 RESEARCH 3905——CONTEXT §转写勘误①；HEAD 9a0b9530 = research docs-only 产线零漂移；spike 分支/worktree 保留 main 零触碰）"
expected_all: "3969 + ΔN（对账式；P1 分账 +0..2 / P2 分账 +15..23 / P3 分账 +0 → 全批终值带 3984..3994；--all 归 P2 批准制，本 plan 不跑全套——验收 = 构建 + 定向冒烟 + D-6 探针门）"
red_lines:
  - "共用红线正本 = CONTEXT §三 plan 红线 front-matter 15 条（FIX2③ McpServerController.swift 零 diff / 封存面零 diff / 无 QA 回切〔回退 = git revert〕/ 翻转 commit 独立可 revert / xcstrings 零 diff 预期 / LocalizationValue 禁形 / disable-not-unmount〔NSMenu enable 侧等价 + SwiftUI .disabled 面零触〕/ 基线 3969/37/0 / AppDelegate.swift 字节零改 / DEBUG fork 序零触 / L057 缝 .runModal( 零命中 / UserDefaults 应用级零新键 / --all 批准制〔本 plan 不跑〕/ C 档门控 / LightamerShell* 生产改名）。"
  - "审计修复先于翻转是硬序（RESEARCH §7）：T2/T3/T4 必须先于 T6 落地——churn 在场时缺口惰性生效、翻转即需；翻转 commit（T6）= entry 切换 + face 搬运 + bridge 装配 + menu Deps 接线 + ContentView :551 toolbar 缝接线〔review M1〕+ WindowCapture 可见性翻转〔review m4〕恰一个 commit，revert = SwiftUI lifecycle 完整恢复。"
  - "face 搬运纪律：App struct 的 wiring .task（~1088 行）+ helpers（~660 行）+ Window 内容闭包（env 链 23 + 三 task + 四 sheet + onChange/overlay/alert）逐字移植进 ShellFace（spike 机械 perl 变换仅两族先例）——装配序不变性零改（attach↔pipeCoordinator↔versionCoordinator 三角先于任何 open drain，LightamerApp.swift:577-603；catalog 重指 :612-619；MCP host 装配尾 :1648-1660）。"
  - "shell 基建 inert 落位（T3/T4）：NSMenuBridge/ShellGraph/三窗控制器文件先落但 entry 未切——翻转前无激活路径（view 侧 note 修饰符引用 bridge 类型 = 编译依赖，非行为依赖）；T6 前构建绿 + 既有测试面全绿是 inert 性机检。"
  - "disable-not-unmount：T3/T6 菜单 enablement 走 enabler 读 holdsControl + backstop；SwiftUI 侧 .disabled(...holdsControl) 10 处 manifest 面零触碰；face ⑤ manifest 行 P3 才重指（勘误②）。"
  - "M2-8-2 T4 教训继承：ShellDelegate 转发 applicationWillTerminate 参数类型恒 `Notification`（D-F0P-9）；AppDelegate.swift 文件字节零改。"
  - "构建 caffeinate -dis 包裹；本 plan 单测面 = 既有测试零回归底线（--bundle App 过滤定向），全套 --all 不跑（归 P2 批准制）。"
files_modified:
  - App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift        # T1：probe-stay hunk（patch 0001 逐字，EditorProbeIfRequested 探针尾）+ T3：workspace onAppear note（B20 spike 形逐字）
  - App/Sources/Lightamer/UI/EditorMTKView.swift                 # T2：ZoomSignature 求值迁构造参数（updateNSView :127-138 直读摘除）
  - App/Sources/Lightamer/UI/EditorAreaView.swift                # T2：body 计算 ZoomSignature 传入（tracked read 显式化）
  - App/Sources/Lightamer/UI/Shell/NSMenuBridge.swift            # T3：新建——生产形（onChange 双态 note 注入形 + enabler 18 读集〔全读集实数，review m1〕含 holdsControl + handleMenu backstop + menuNeedsUpdate 动态重建 + menu_open_session picker 缝〔review M4〕）
  - App/Sources/Lightamer/UI/ContentView.swift                   # T3：export note onChange 双态（B17/B18 生产形，spike onAppear 一次性形废弃）+ T4：columnVisibility binding 桥 graph + T6：:551 toolbar preset-manager openWindow → 窗控制器缝接线（review M1——scene registry 翻转后不在场的替代缝）
  - App/Sources/Lightamer/UI/InspectorView.swift                 # T3：metadataFieldFocused onChange note（B19 spike 形逐字）
  - App/Sources/Lightamer/UI/Shell/ShellGraph.swift              # T4：新建——ShellGraph（spike 9 字段 + columnVisibility）
  - App/Sources/Lightamer/UI/Shell/ShellWindowControllers.swift  # T4：新建——PresetManager/McpLauncher/Settings 三窗控制器（NSWindow+NSHostingView+env 注入）
  - App/Sources/Lightamer/UI/LightamerApp.swift                  # T6：entry GUI 臂尾 = ShellMain.run()（fork 序逐字；spike `_ = { LightamerApp.main() }` 死行形保留至 P3 退役）+ WindowCapture private→internal 恰一处（review m4——LightamerShellFace 引用所需）
  - App/Sources/Lightamer/UI/Shell/LightamerShell.swift          # T6：新建——ShellMain/ShellController/ShellDelegate/ShellFace（patch 0002 生产化：去桩 + Deps 全接线 + reopen/fullscreen/autosave 三行 + LightamerShell* 改名）
  - .work/gui-acceptance/f0prime-prod/MANIFEST.md                # T5/T7：toolbar 差异登记行（D-F0P-2）+ 走查面 1-9/14 冒烟记录
  - .work/gsd/phases/f0prime-prod/F0P-01-SUMMARY.md              # T7：执行摘要（逐任务记账 + 验收判定指针 + ΔN 终账）
  - .work/gsd/phases/f0prime-prod/F0P-01-DECISIONS.md            # T7：裁定记录（LightamerShell* 终名 + Deps 接线终形 + 探针数据 + 各偏差）
---

# Plan F0P-01 — plan P1：审计修复先于翻转 + 壳交接翻转 + D-6 探针门

> **裁决正本** = `CONTEXT.md`（D-F0P-1..10 全按 RESEARCH §8 推荐——晨审
> 可推翻）；规格正本 = `RESEARCH.md`（§1 壳交接生产形 / §2 菜单全族 /
> §3 未追踪读审计 / §4 @State 迁移 / §6.1-6.2 探针与走查 / §7 切分 /
> §9 锚点；planner 2026-10-18 HEAD `9a0b9530` 抽核 ~20 点亲核吻合——勘误
> 三条见 CONTEXT §转写勘误（含 review M3 paste 族勘误③），本 plan 引用
> 以勘误后为准）。spike 代码正本 =
> patch `0001..0003` + 分支 `spike/f0prime-shell`（main 零触碰；worktree
> `../Lightamer-f0prime-shell` 复测可用）。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（T1-T7 形态 = CONTEXT
> D-F0P-1..10 落定值）。执行中如触「必须扩面」（NSToolbar 重造 / env 回
> 切门 / AppDelegate 继承化 / keyedWindow 判定 / tracked-read 形回退 /
> 封存面触碰）= 停手上报，不得自裁扩界。
>
> **执行序**：T1 → T2 → T3 → T4 → T5 → **T6** → T7。T1-T5 产线批（每任务
> 独立 commit + 构建绿机检），**T6 = 翻转 commit（内聚、独立可 revert）**，
> T7 轮次 + 探针门 + 冒烟走查 + 收口文档。每任务独立 commit（Conventional
> Commits，全英文，只 add 相关文件，不 push）。
>
> **C 档停**：T7 闭环后**停汇报**（壳交接 = 全 face 触达的大翻转，给用户
> 过目点）；确认后 P2 起跑。
>
> **基线**：**3969/37/0**（audit-repair 收口终态；HEAD `9a0b9530`）。全套
> 预期 `TOTAL|3969+ΔN/37/0|`（ΔN 带 +15..+25 → 终值带 3984..3994——勘误
> RESEARCH 3905；本 plan 分账 +0..2；`--all` 归 P2 批准制）。

## ΔN 预算表（逐任务，P1 分账带 +0..2；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 probe-stay | **0** | 测量基建（DEBUG 探针尾），零测试面 | probe 驱动轮（T7 消费） |
| T2 缺口1 | **+0..2** | ZoomSignature 求值抽纯函数可加相等性负测（合法 ΔN=0） | App bundle（如落） |
| T3 缺口2 | **0** | note 注入形（观察行为面，P2 MenuBridgeObservationTests 覆盖） | — |
| T4 缺口3 | **0** | ShellGraph/三窗控制器结构面（P2 smoke 覆盖） | — |
| T5 登记 | **0** | docs-only | MANIFEST |
| T6 翻转 | **0** | 机械搬运 + 接线（测试族归 P2） | 既有测试零回归底线 |
| T7 门+走查 | **0** | 轮次 + 收口文档 | 探针留档 |
| **合计** | **+0..2** | 3969 → P1 终态 ≥3969（全批带 3984..3994 由 P2 兑现） | 全 APP 域；Project.swift 零 diff（Tuist glob 纳新源文件） |

## 已定裁决（生效值，硬约束，不得重开）

1. **无 QA 回切**（D-F0P-5）：禁 env 门；回退 = git revert。
2. **zoom 构造参数化**（D-F0P-7）：tracked-read 形被否。
3. **Settings 真窗控制器**（D-F0P-1）：私有 selector 不入产。
4. **toolbar 接受+登记**（D-F0P-2）：NSToolbar 重造后置。
5. **AppDelegate 组合转发**（D-F0P-9）：AppDelegate.swift 字节零改。
6. **autosave key `"LightamerMainWindow"`**（D-F0P-8）；**reopen/fullscreen
   补行**（D-F0P-4）；**恒主窗单源**（D-F0P-6）；**⌘W 1:1 对齐**（D-F0P-3
   ——library face 落点实测现行 AX 后定，T6 DECISIONS 申报实测记录）。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/f0prime-prod/CONTEXT.md`（D-F0P-1..10 + 勘误两条 +
  红线 15 条 + 晨审推翻点索引）
- `.work/gsd/phases/f0prime-prod/RESEARCH.md` §1（壳交接生产形）+ §2
  （菜单全族清单）+ §3（未追踪读审计——4 缺口正本）+ 对应任务节
- `.work/gsd/phases/nsmenu-spike/F0PRIME.md`（双门 PASS 正本 + §1.3 偏差
  申报 + §4 机制发现）+ `SPIKE.md` §1.3（probe-stay 偏差申报）
- patch 正本：`phases/nsmenu-spike/0001..0003-*.patch`（逐 hunk 解剖面）
- `.work/config.toml [gsd]` paused/auto 开关（开工前亲核）
- `.work/LESSONS.md` L041（tuist generate 恒末位——本 plan 预期不触发：
  Tuist glob 纳新源文件）+ AGENTS.md M2-8-2 T4（willTerminate 参数类型
  load-bearing）+ L057 节（runModal 禁令）

---

## T1 — probe-stay hunk 落 main（D-6 门测量基建）

> patch 0001 逐字落 main——无它则 D-6 门无 phase=editor 机检（HEAD 的
> `-la_editor_probe` 加载完即 terminate，SPIKE §1.3）。

**read_first**：patch `0001-feat-spike-probe-stay-measurement-hunk-F0-A-arm-sour.patch`
（全 hunk）；`WorkspaceHostView.swift:1820-1850`（EditorProbeIfRequested
探针尾）；`SPIKE.md` §1.3（A 臂非纯 HEAD 偏差申报）+ `F0PRIME.md` §1.2
（协议：`-la_editor_probe <fixtures>` + `-la_probe_stay` + stderr 标记）；
`run-one-f0prime.sh` / `run-driver-f0prime.sh`（T7 消费的驱动正本）。

- **action**：
  1. patch 0001 hunk 逐字应用进 `WorkspaceHostView.swift`
     EditorProbeIfRequested 探针尾（HEAD :1827 邻域 `note("film page
     final = …")` 臂后）：`-la_probe_stay` 参数臂 = note("staying alive
     for measurement") + `return`（7 注释 + 3 代码，byte-identity patch
     形）。
  2. 构建绿机检（caffeinate -dis 包裹）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 本任务恰一产线文件（WorkspaceHostView.swift）。
  - grep：`la_probe_stay` 在 App/Sources 恰 1 命中；hunk 内容与 patch 0001
    对应段 byte-identity（`git diff` vs patch body 面核）。
  - DEBUG 探针语义零外溢：hunk 全body 在 `#if DEBUG` 探针函数域内（面核）。
- **commit**: `feat(f0p1): land probe-stay measurement hunk (d6 gate infrastructure)`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（纯 DEBUG 探针尾，产
  品路径零差）；偏差（注释措辞随上下文微调）= DECISIONS 申报；**禁动探
  针函数其余臂**（`-la_editor_probe` 既有 terminate 形零触）。

## T2 — 缺口1：zoom/pan/rot 构造参数化（未追踪读修复，先于翻转）

> churn 在场时缺口惰性生效（96% 机器顺手替跑 updateNSView）、翻转即需
> （F0PRIME §4.3）——修法 = D-F0P-7 构造参数化（tracked-read 形被否）。

**read_first**：`RESEARCH.md` §3.2-A1 行 + §3.3 缺口1 + §8 OQ-F0P-7；
`EditorMTKView.swift:110-145`（updateNSView + ZoomSignature push-once
现形 :127-138）；`EditorAreaView.swift:61-328`（body——EditorMTKView 构
造点 + zoom 族零 tracked read 实证）；F0PRIME §4.3（失效链解剖：菜单
actual/fit 分发✓ 变异✓ 但视口零重绘）。

- **action**：
  1. `EditorMTKView` 加构造参数（如 `let viewportSignature:
     Coordinator.ZoomSignature`）；updateNSView :127-138 的签名求值改读
     构造参数，与 `context.coordinator.zoomSignature` 比对臂原样保留
     （push-once 语义零改：变化 arm 恰一次 redraw）。
  2. `EditorAreaView` body 在 EditorMTKView 构造点计算签名
     （`Coordinator.ZoomSignature(zoom: viewportState.zoom, pan:
     viewportState.pan, rotationDegrees: viewportState.rotationDegrees)`
     ——body 对三字段的 tracked read 显式化）。
  3. 手势路径零触（coordinator 自持 view 引用直接武装重绘——F0PRIME
     §4.3 已验不受扰）；ZoomHUD 路径零触（自己 body tracked，RESEARCH
     §3.2-G）。
  4. 构建绿机检 + `--bundle App` 过滤 Editor* 定向零回归。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰两产线文件（EditorMTKView/EditorAreaView）。
  - grep：updateNSView 函数体内 `viewportState.(zoom|pan|rotationDegrees)`
    零命中（签名读迁构造参数）；EditorAreaView body 含
    `ZoomSignature(` 构造恰一处；`context.coordinator.zoomSignature` 比对
    臂仍在（push-once 零改面核）；`let _ = viewportState` 在 App/Sources
    零命中（review m8——D-F0P-7 tracked-read 禁形〔`let _ =
    viewportState.zoom` 被否备选〕全形机检；T2 SC 原只查 updateNSView 内
    三字段，拦不住 body 内禁形）。
  - 既有测试面零回归：`--bundle App` 过滤 Editor* 全绿（法数零漂移）。
- **commit**: `fix(f0p1): parameterize viewport signature push (untracked-read gap 1)`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（回 churn 掩盖态——缺
  口1 复活，无行为回归）；偏差（参数命名/签名求值点微移）= DECISIONS
  申报；**禁引 tracked-read 形**（`let _ = viewportState.zoom` 被否备选
  ——D-F0P-7，发现 = 停手上报）；**禁改手势路径与 ZoomHUD**（已验不受
  扰面）。

## T3 — 缺口2：exportPresent onChange 化（bridge 生产形 + 三 note 修饰符落位）

> spike 的 `onAppear` 一次性 `noteExportPanelRequestPresent(true)` 是时机
> 缺陷（翻转态不可见——sheet 关闭后菜单项恒亮/恒灭，RESEARCH §3.2-B17）；
> 生产形 = onChange 双态注入 + page leg 直读 `exportPageActive`（B18）。
> 本任务落 bridge 生产形文件 + 三 view 侧 note 修饰符——**inert 落位**
> （entry 未切，无激活路径；编译依赖非行为依赖）。

**read_first**：`RESEARCH.md` §3.2-B17/B18/B19/B20 行 + §3.3 缺口2；
patch 0002 的 ContentView/InspectorView/WorkspaceHostView 三 hunk（spike
onAppear/onChange 形正本）；patch 0002 的 NSMenuBridge.swift 段（671 行
——树构建 + 三注册表 + handleMenu backstop + menuNeedsUpdate + 观察适
配器 :3003-3054）；`ContentView.swift:143-151`（exportPanelRequested
@State）+ :249-250（publish）+ :796-800（page leg）；RESEARCH §2.2
（NSMenu 映射规则——zh 键整字面量零新键 + L057 Task hop 纪律）。

- **action**：
  1. **NSMenuBridge.swift 生产形落位**（App/Sources/Lightamer/UI/Shell/）：
     patch 0002 NSMenuBridge.swift 段落位 + 生产化修正——`Deps` 闭包形保
     留（T6 装配时全接线）；观察适配器 **18 读集**（全读集实数，review
     m1——patch armObservation 逐行数：canUndo/canRedo/loadedImageURL/
     hasPayload/isReadOnly/projectStore/recentProjects/holdsControl/
     isActive/gamutCheck/recentSessions/phase/currentImageID/
     toolRailVisible/scopesVisible/adjustmentStackVisible/
     metadataFieldFocusedState/exportPanelRequestPresent）含 holdsControl
     （:3013 形）；handleMenu stale-enablement backstop（:3047-3054 形）；
     menuNeedsUpdate 动态子菜单重建（:3036-3038 形）。**改形点三件**：
     ①note 注入 API 面就绪但 spike 的 onAppear 一次性调用形**不入产**
     （生产调用形在 action 3）；②`Deps` 增 `inspectorState` 字段（spike
     Deps 七对象无此字段——review m6；B18 enabler 直读
     `inspectorState.exportPageActive` 所需）+ 观察适配器读集终形
     （track exportPageActive 替换 note-box 读或双轨——终形落
     DECISIONS，与 m1 读集基数联动）；③menu_open_session（⇧⌘O）动作体
     生产化 = `FileOpener.openSessionFolder` picker 缝（L057 Task hop
     形——review M4：弃 spike `recentSessions.first` 直开，产线正本
     `LightamerApp.swift:1825-1832`；Deps 闭包 openSession 形不变，桥侧
     action 改调 picker 闭包——新增 `openSessionPicker` 类闭包或复用
     openSession 零参变体，终形落 DECISIONS）。
  2. **ContentView export note = onChange 双态**：`.onChange(of:
     exportPanelRequested) { _, present in
     NSMenuBridgeController.shared.noteExportPanelRequestPresent(present) }`
     ——raise/dismiss 双态都注入；enablement 真相 = bridge enabler 读
     `inspectorState.exportPageActive`（B18 双发布点统一：sheet 腿 note +
     page 腿直读同一信号源；gate=false 面 action 直走
     `inspectorState.openExportPage()` 缝在 T6 Deps 接线兑现）。
  3. **InspectorView metadataFieldFocused onChange note**（B19 spike 形
     逐字：`.onChange(of: fieldFocused)` → `noteMetadataFieldFocused`）+
     **WorkspaceHostView workspace onAppear note**（B20 spike 形逐字：
     `noteWorkspace(workspace)`——单窗形，D-F0P-6 恒主窗单源）。
  4. 构建绿机检 + 既有测试零回归（inert 性机检：bridge 类型被 view 侧
     引用但无激活路径）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰四产线文件（NSMenuBridge 新建 +
    ContentView/InspectorView/WorkspaceHostView）。
  - grep：`noteExportPanelRequestPresent(true)` 的 `.onAppear` 包裹形零
    命中（spike 时机缺陷形不入产）；`.onChange\(of: exportPanelRequested)`
    双态注入恰一处；`noteMetadataFieldFocused` onChange 形恰一处；
    `noteWorkspace` onAppear 形恰一处；`NSMenuBridgeController` 类型恰一
    文件定义；`recentSessions.first` 在 NSMenuBridge.swift 零命中
    （review M4 机检门——picker 缝替代 spike 直开形）。
  - **McpServerController.swift 零 diff**；`.runModal(` App/Sources 零命
    中；`String.LocalizationValue("prefix_\(` 插值禁形零命中。
- **commit**: `feat(f0p1): land production menu bridge with two-state export note (untracked-read gap 2)`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（inert 文件摘除，零行
  为差）；偏差（bridge 生产化微调/注入点微移）= DECISIONS 申报；**禁把
  spike onAppear 一次性形带进产**（时机缺陷正本）；**禁改 SwiftUI 侧
  .focusedSceneValue publish 面**（P3 退役范围，本 plan 零触）。

## T4 — 缺口3：四 stub 生产化（ShellGraph + columnVisibility 提升 + 三窗控制器）

> spike 四 stub（presetManager/mcpLauncher/showSidebar/showInspector 空
> 闭包 + Settings 私有 selector）生产化——本任务落结构面（inert），T6
> 装配时接线。

**read_first**：`RESEARCH.md` §3.2-C1 行 + §3.3 缺口3 + §4（@State 迁移
清单——spike graph 9 字段已到位，唯一增量 = columnVisibility）+ §1.2
#9/#10/#11 行（三窗 scene 现形）；`LightamerApp.swift:2212-2244`（三窗
scene + env 注入面）+ :449-467（@FocusedBinding 消费）+ :2692-2702
（toggleSidebar/toggleInspector 写回现形）；`ContentView.swift:143`
（columnVisibility @State 现形）；patch 0002 F0PrimeShellGraph 段（9 字
段）+ stub 段（:2158-2176）。

- **action**：
  0. **DECISIONS 先行步（review M2）**：ShellGraph 实例单源形三选一定
     死——(a) `ShellGraph.shared` 单例（LutLibraryStore.shared 先例，
     M2-5 检查器 m6 形——跨翻转边界零 seam 改动，最小 diff）/ (b) env
     注入 + optional 回落本地 @State（`@Environment(ShellGraph.self)`
     nil → fallback——pre-flip nil 合法）/ (c) ContentView 新 init 参数
     + face 传（须处理 pre-flip 调用点缺参）——**开工前落 DECISIONS**，
     T4/T6 按 DECISIONS 终形接线（face 装配段与 ContentView 消费须同一
     实例——双实例静默失效模式：菜单 ⌥⌘S/⌥⌘I 写 A、ContentView 读 B
     → 列可见性切换视觉恒死）。
  1. **ShellGraph.swift 落位**：spike `F0PrimeShellGraph` 9 字段形
     （libraryImportRequest/Choice、libraryWelcomePresented、
     pastePartialRequested、adjustmentTransferPresented、
     lastLaunchWasUnclean + thumbnailProvider/catalogThumbnailRouter/
     batchSidecarWriter 三 per-session optional）+ **第 10 字段
     `columnVisibility: NavigationSplitViewVisibility`**（缺口3a 提升，
     缺省 `.all` 对齐 ContentView @State 现值）——生产名 `ShellGraph`。
  2. **ContentView columnVisibility binding 双向桥**：:143 @State 改
     graph-backed binding（实例来源按前置 DECISIONS 单源终形——review
     M2；body tracked read + 菜单写回 graph 路径就绪
     ——值语义等价：读/写/Toggle 行为逐点平移；本任务在 churn 在场下
     惰性生效，翻转后菜单写 graph）。
  3. **ShellWindowControllers.swift 落位**：三窗控制器
     （NSWindow + NSHostingView + `showWindow()` 缝）——
     `PresetManagerWindowController`（PresetManagerWindow + env
     presetsStore/presetController + `.preferredColorScheme(.dark)` +
     520×480，HEAD :2212-2218 形）/ `McpLauncherWindowController`
     （McpLauncherPanelView + 720×480，:2224-2227 形）/
     `SettingsWindowController`（SettingsView(legacyLibraryEnabled:) +
     env catalogPreferences/pipeCoordinator/libraryProjects + dark，
     :2236-2244 形——D-F0P-1 真窗控制器）。
  4. 构建绿机检 + 既有测试零回归。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰三产线文件（ShellGraph 新建 +
    ShellWindowControllers 新建 + ContentView）。
  - ShellGraph 实例单源形已落 DECISIONS（review M2——三选一终形在案，
    T6 接线以此为准）。
  - grep：`class ShellGraph` 恰一处 + `columnVisibility` 字段恰一处声明；
    `WindowController` 三类各恰一处定义；`showSettingsWindow:` 私有
    selector **零命中**（D-F0P-1——不入产）；ContentView :143 位置
    `@State private var columnVisibility` 零命中（已提升 graph）。
  - `Project.swift` 零 diff（Tuist glob 纳新源文件）；McpServerController
    零 diff。
- **commit**: `feat(f0p1): lift column visibility to shell graph and add window controllers (untracked-read gap 3)`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（columnVisibility 回
  @State——菜单写回缺口3a 复活，churn 在场下零行为差）；偏差（控制器拆
  分形/graph 字段序）= DECISIONS 申报；**禁动三窗 scene 本体**（HEAD
  :2212-2244 段本 plan 零触——P3 退役范围；控制器是平行新增）；**禁改
  presetsStore/McpLauncher.shared 注入形**（单例核心不受损）。

## T5 — toolbar 差异登记（D-F0P-2，docs-only）

- **action**：`.work/gui-acceptance/f0prime-prod/MANIFEST.md` 建卷 +
  toolbar 差异登记行（窗级 `.windowToolbarStyle(.unified)` 附着形态缺席
  ——hosting in-face 渲染仍活；NSToolbar delegate 重造 = 后置立项候选；
  OQ-F0P-2 接受裁定引用）。
- **验收标准（机检）**：MANIFEST 在库且含 toolbar 差异行；零代码 diff
  （`git diff --stat` 零产线文件）。
- **commit**: `docs(f0p1): register window toolbar deviation (oq-f0p-2)`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；零偏差面。

## T6 — 壳交接翻转（一个 commit 内聚，独立可 revert）

> 翻转 = patch 0002 全量生产化：entry 切换 + face 逐字搬运 + delegate 组
> 合 + NSMenu 全族装配去桩 + ShellGraph/控制器接线 + reopen/fullscreen/
> autosave 三行 + LightamerShell* 生产改名。**revert 本 commit = SwiftUI
> lifecycle 完整恢复**（红线④）。

**read_first**：`RESEARCH.md` §1 全节（spike 形基准 + Scene 面穷举映射
表 + 装配序不变性 + 存活面/已知差异）+ §2（菜单全族清单——Deps 接线
面）+ §4（@State 迁移终局）；patch 0002 全文（F0PrimeShell.swift 2269
行 + NSMenuBridge 671 行 + view hunks + entry hunk）；`LightamerApp.swift
:128-158`（entry fork 序）+ :507-560（主窗 + env 链）+ :1661-1798（三
task 尾 + 四 sheet + onChange/overlay/alert）+ :1799-2205（commands 全
族——Deps 对账源）；CONTEXT D-F0P-1/3/4/6/8/9/15。

- **action**：
  1. **LightamerShell.swift 落位**（App/Sources/Lightamer/UI/Shell/）：
     patch 0002 F0PrimeShell.swift 段生产化——`LightamerShellMain`（
     NSApplication.shared + .regular policy + delegate 持有 retained +
     app.run()）/ `LightamerShellController`（主窗 1440×900 + styleMask
     补 `.fullScreen`〔D-F0P-4〕+ NSHostingView(face) + 
     `setFrameAutosaveName("LightamerMainWindow")`〔D-F0P-8〕+
     makeKeyAndOrderFront）/ `LightamerShellDelegate`（组合生产
     AppDelegate：open Apple Events + willTerminate **Notification 参数
     类型**逐字转发 + `applicationShouldTerminateAfterLastWindowClosed =
     true` + `applicationShouldHandleReopen` 补行〔D-F0P-4〕）/
     `LightamerShellFace`（App struct 的 Window 内容闭包逐字搬运：env 链
     23 + 三 .task + 四 .sheet + onChange/overlay/alert——装配序不变性零
     改）+ helpers（panel/metadata/probe/copy-paste/sidecar ~660 行逐字）
     + DEBUG 探针 static armed 旗标随迁。生产名统一 `LightamerShell*`
     （D-F0P-15 改名纪律）。
  2. **entry 切换**：`LightamerApp.swift` GUI 臂尾 `LightamerApp.main()`
     → `LightamerShellMain.run()`（fork 序四把逐字零触；spike
     `_ = { LightamerApp.main() }` 死行形保留至 P3 退役）。
  3. **NSMenu 全族装配去桩**（Deps 闭包真接线）：`presetManager` →
     PresetManagerWindowController.showWindow / `mcpLauncher` →
     McpLauncherWindowController.showWindow / `showSidebar`/`showInspector`
     → ShellGraph.columnVisibility 写（toggleSidebar/toggleInspector 语义
     逐点平移 :2692-2702）/ Settings…（⌘,）→ SettingsWindowController.
     showWindow（D-F0P-1 真窗）/ export → gate 分叉：gate=true 面 sheet
     腿写 exportPanelRequested 缝 + gate=false 面直走
     `inspectorState.openExportPage()`（F0PRIME §1.1 同缝裁定）/ 菜单
     action 一律 `Task { await … }` hop（L057）/ **AX identifier 族随桥
     迁移**（review m5）：menu.workspace.enterEditor/backToLibrary
     （:1927/:1935）/ menu.library.search（:1945）/ menu.edit.
     copyAdjustments（:2018）/ menu.view.stacks.expandAll/collapseAll
     （:2096 附近）/ menu.image.aiUpscale/Denoise（:2183/:2195）——按
     `AIEntryPointCoordinator.Marker` / 既有字符串给 NSMenuItem 补
     `accessibilityIdentifier`（NSMenuItem 支持该属性；Marker 常量引用
     恢复「drift 不能编译」方法论）；不补则 P2 DECISIONS 申报 AX 面已知
     差异（二选一，禁静默）。
  4. **ShellGraph 接线**：face 装配段持 graph（Bindable 桥）；⌥⌘S/⌥⌘I
     菜单闭包写 graph.columnVisibility（ContentView binding 桥 body 可见
     ——T4 就绪路径激活；face 装配段与 ContentView 消费**同一 graph
     实例**——实例单源形按 T4 前置 DECISIONS，review M2）。
  5. **ContentView :551 toolbar preset-manager 缝接线（review M1）**：
     `openWindow(id: "preset-manager")`（ContentView :551，
     @Environment :140）→ 窗控制器 showWindow 缝——翻转后 SwiftUI scene
     registry 不在场，openWindow 静默 no-op（用户可见入口回归）；接线形
     与 ShellGraph 单源终形联动（graph 请求字段 + face/shell 侧观察消
     费，或 ContentView 闭包参数——二选一落 DECISIONS）。
  6. **⌘W 双面语义 1:1 对齐**（D-F0P-3）：editor face ⌘W = closeEditor
     优先；library face 落点 = 实测翻转构建的现行 File 菜单 AX 内容后
     1:1 对齐（实测记录落 DECISIONS）。
  7. 构建绿机检 + 翻转 commit 内聚性核（本任务全部产物 = 恰一个 commit）。
- **验收标准（机检）**：
  - 构建绿；`git log` 本任务恰一 commit 且 `git show --stat` 恰三产线文
    件（LightamerApp.swift〔entry 尾 + WindowCapture 可见性——review
    m4〕+ LightamerShell.swift 新建 + ContentView.swift〔:551 缝接线
    ——review M1〕）。
  - grep：`F0PrimeShell` 在 App/Sources **零命中**（生产改名完成）；
    `LightamerShellMain.run()` 恰一处调用（entry 尾）；fork 序四把逐字
    （`AIWorkerMain.runIfRequested`/MCP headless 臂面核零 diff）；
    `showSettingsWindow:` 零命中；`presetManager: { }` 空闭包形零命中
    （四 stub 全接线）；`setFrameAutosaveName("LightamerMainWindow")` 恰
    一处；`.fullScreen` styleMask 恰一处；`applicationShouldHandleReopen`
    恰一处；`applicationWillTerminate(_ notification: Notification)` 转发
    形恰一处（Notification 参数类型面核）；`openWindow` 在 ContentView.
    swift 零命中（review M1——翻转后静默失效根除，含 :140
    `@Environment(\.openWindow)` 面摘除）；WindowCapture 可见性翻转恰
    一处（`private struct WindowCapture` 零命中——review m4）。
  - **AppDelegate.swift / McpServerController.swift / 封存面全清单零
    diff**；App struct 主体（:252-2244）零 diff（P3 退役范围——本任务动
    entry 尾 + WindowCapture 可见性〔private→internal 恰一处，review
    m4：LightamerShellFace 引用所需，同文件非 App struct 域〕 +
    ContentView :551 缝接线〔review M1〕）。
  - 既有测试零回归底线：`--bundle App` 定向全绿（App struct 死码在位，
    ProjectReadOnlyFaceTests 的 `LightamerApp.batchPasteBlocked` static
    面零触——P3 才转移）。
  - **独立可 revert 机检**：`git revert --no-commit <flip-sha>` 干净应用
    + `git revert --abort`（语义 = entry 回 SwiftUI lifecycle 完整恢复）。
- **commit**: `feat(f0p1): hand over app shell to manual NSApplication lifecycle (f0-prime flip)`
- **回滚与偏差申报要求**：回滚 = **revert 本单 commit**（翻转独立可
  revert 是红线④——发现 revert 后残留半态 = 停手上报）；偏差（face 搬
  运机械变换族超 spike 两族先例/Deps 接线形/⌘W 实测落点）= DECISIONS
  申报；**禁触 App struct Commands 面**（P3 退役范围）；**禁改 wiring 装
  配序**（:577-603 三角 + :612-619 + :1648-1660 逐字是验收面）；**禁引
  env 回切门**（D-F0P-5）。

## T7 — D-6 探针门（绝对 <10% + L082 四哨兵）+ 走查冒烟 + 收口文档

> D-6 绝对门复活为验收正门（CONTEXT 特别登记二）：B 臂（生产翻转二进
> 制）三轮 probe-stay 驱动；驱动脚本从 `run-driver-f0prime.sh` 派生
> （RESEARCH §6.1）。

**read_first**：`RESEARCH.md` §6.1（D-6 新门）+ §6.2（走查清单——本任务
面 1-9/14 冒烟级）；`F0PRIME.md` §1.2（协议逐字配方）+ §2（A/B 基线数
据——96.0/0.0 对照正本）；`run-one-f0prime.sh` / `run-driver-f0prime.sh`
（驱动正本，派生时仅改日志目录）；L082 哨兵四门正本（F0PRIME §2.1 栈
旁证形）。

- **action**：
  1. **驱动派生**：`run-one-f0prime.sh` 派生生产版（日志目录 →
     `.work/gsd/phases/f0prime-prod/probe/`；配方 = `-la_editor_probe
     <fixtures>` + `-la_probe_stay`；settle 60s → frontmost 先行复验 →
     截图 → 30s 窗 6 采样 @6s 中位 → `sample 6s` 符号总量）。
  2. **D-6 绝对门**：生产翻转二进制三轮驱动——%cpu 中位 **<10%**（判据
     线留 10pp 余量对 F0PRIME B 臂 0.0% 基线）+ **L082 四哨兵全过**：
     ①3/3 轮 `frontmost=true`；②窗内截图可见（编辑器面完整渲染）；③
     sample 栈主线程样本泊 `mach_msg2_trap`；④churn 符号族
     （UpdateStack/sizeThatFits/beginTransaction）三轮全零。10-30% 区间
     = 未达标 → 停手归因（禁放行；判别探针二轮迭代义务）。
  3. **走查冒烟**（§6.2 面 1-9/14 冒烟级，逐项记录 MANIFEST）：启动 +
     welcome + New/Open/Recent Project；Import Folder + 进度；图库网格
     （缩略图/EXIF/stacks）；编辑器进出（⌘E/⌘W 双向）；视口（解码渲染/
     zoom HUD/**菜单 actual/fit 重绘 = 缺口1 修复验证**）；Inspector
     （滑杆/export 页双入口/film/LUT/raw readout）；标记菜单 16 项
     （review m2 实数——rating clear+1-5=6 / flag ×3 / color
     clear+0-5=7；RESEARCH「标记15」计数勘正）+ ⌘0-6；undo/redo +
     copy/paste adjustments + versions；DRT 面板 + HDR
     四态 + soft proof；退出链（willTerminate flush + clean sentinel +
     ⌘Q）。
  4. **三臂留档起卷**：A = 翻转前（T1 形）二进制 + B = 翻转后（T6 形）
     二进制 + 日志按 spike §6 惯例归档本 phase 目录（C 臂 trace 位 P2
     定版）；B 臂 = D-6 门基线正本。
  5. **SUMMARY + DECISIONS 落盘**（逐任务 ΔN 记账 + LightamerShell* 终
     名终账 + Deps 接线终形 + ⌘W 实测记录 + 探针数据 + 各偏差）。
  6. 汇报 + **C 档停**（执行+验收闭环后停，等用户确认再放行 P2）。
- **验收标准（机检）**：三轮 %cpu 中位数值 + 采样命令 + 四哨兵证据路径
  落 DECISIONS 探针记录节；菜单 actual/fit 重绘验证证据（缺口1 修复）
  在 MANIFEST；MANIFEST/SUMMARY/DECISIONS 在库；探针轮只应有 GUI 实例
  在跑（pid parentage 一行随记录）。
- **commit**: `test(f0p1): run d6 probe gate and smoke walkthrough (f0-prime flip)`
- **回滚与偏差申报要求**：绝对门未达（≥10%）= 本 plan 翻转归因排查
  （重建 T2/T3/T4 任务边界 commit 形二进制二分——worktree + 独立
  DerivedData，spike A/B 先例〔review m7：T6 后逐任务 revert 不可行，
  revert T3 会破 LightamerShell 编译〕+ F0PRIME B 臂对照），修复后复测，
  禁放
  行禁静默；走查面任何 fail = 先归因（本批翻转窗内?）——窗外 fail =
  既有缺陷停手上报；哨兵四门任一 fail = 读数无效重采（禁拿遮挡态/僵死
  态数据过门）。

---

## 风险与回退

- **face 搬运体量**：~1750 行机械搬运 + ~300 行新写（RESEARCH §3.4）——
  机械 perl 变换超 spike 两族先例 = 偏差申报；装配序不变性（三角先于
  open drain）是回归底线（probe 全链 + 冒烟走查覆盖）。
- **翻转后静默失效类**：未追踪读审计已定盘 4 缺口（RESEARCH §3），但
  「churn 曾承担的额外负载未发现第二处」是审计结论非证明——T7 冒烟 +
  P2 16 面走查是穷尽面；新发现缺口 = 补修任务（同模式：构造参数化/
  onChange 化/action-time 直读三修法选型）+ DECISIONS 申报，禁静默热修。
- **三窗控制器 env 注入面**：SettingsView 的三 env 对象在翻转后由控制
  器注入（HEAD scene 形对齐）——注入缺件 = Settings 页运行时崩（
  M2-8-3 FINDING-A 同族风险），走查面 10 专项覆盖。
- **⌘W 拦截序**：NSMenu 主菜单项在 performClose 之前拦截 keyEquivalent
  ——editor face 语义可保是推断（RESEARCH §2.4 风险 1），T6 实测记录
  是唯一裁决面；若实测 library face 落点与现行 AX 不一致 = 按 1:1 对齐
  原则修 Deps，不创新语义。
- **revert 半态风险**：T6 单 commit 内聚是结构性保证；若 T3/T4 inert 文
  件被后续任务改动（不该发生——T6 后冻结至 P2 测试），revert 面核在
  T7 收口时复跑一次。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：charter 三裁决① ↔ T1-T7 映射 + RESEARCH 4 缺口 ↔
   T2/T3/T4/T5 逐项闭合 + F0PRIME 双门 ↔ T7 探针门复现。
2. **OQ 兑现核**：D-F0P-1（T4d/T6 Settings 真窗 + selector 零命中）/
   D-F0P-2（T5 登记）/ D-F0P-3（T6 ⌘W 实测记录）/ D-F0P-4（T6 两行）/
   D-F0P-5（env 门零命中）/ D-F0P-6（B20 单窗形）/ D-F0P-7（T2 参数化 +
   tracked-read 零命中）/ D-F0P-8（autosave key 恰一处）/ D-F0P-9
   （AppDelegate 零 diff + Notification 转发）/ D-F0P-15（改名零残留）。
3. **硬序核**：T2/T3/T4 commit 时间序先于 T6（git log 面核）；T6 内聚
   单 commit + revert 干净。
4. **红线核**：FIX2③ + 封存面 + AppDelegate + App struct 主体 + fork 序
   零 diff；xcstrings/UserDefaults/.runModal/插值禁形零命中；`.disabled
   (...holdsControl)` 面零触。
5. **SC 可机检性**：每条 SC 有命令级判据（grep / git show --stat / 探针
   CPU 数值 / 定向轮），非「目测」；ΔN 对账式非死数（P1 +0..2）。
6. **探针纪律**：frontmost 先行 + parentage 一行 + 四哨兵全过才算数；
   10-30% 未达标禁放行。

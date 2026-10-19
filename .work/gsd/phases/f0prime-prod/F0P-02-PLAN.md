---
phase: f0prime-prod
plan: "F0P-02"
title: "plan P2 — 测试族 + 全套回归 + 16 面走查（T1 NSMenuParityTests ~10 / T2 ShellGraphMigrationTests ~4 / T3 MenuBridgeObservationTests ~4 / T4 窗控制器 smoke ~2 + Project.swift/BUNDLE-MAP 接线〔tuist generate 恒末位〕/ T5 直启宿主等价性验证〔翻转前/后二进制 Library bundle 对账〕/ T6 全套 --all 批准制三轮同值 / T7 16 面 GUI 走查 MANIFEST + 三臂留档定版 + D-6 门定版 + 门① 像素/AX 复证 + SUMMARY/DECISIONS）"
wave: 2
depends_on: ["F0P-01"]
autonomous: true
requirements: ["依赖 P1 闭环（壳交接翻转在位 + 审计修复四缺口已修 + probe-stay 基建在库）——C 档停确认后起跑", "调研正本 = phases/f0prime-prod/RESEARCH.md（§5 测试兼容面〔ΔN 预估 +15..+25 / 0 harness 重写 / 直启宿主等价性〕/ §6 回归走查〔D-6 门 + 16 面清单 + 三臂留档〕/ §7 切分 P2 行〔勘误②：manifest 重指归 P3，本 plan 纯增测试文件〕）", "OQ 裁决正本 = phases/f0prime-prod/CONTEXT.md（D-F0P-1..10；转写勘误①基线 3969/37/0 + ②manifest 重指时序）", "测试基线权威数 3969/37/0（勘误 RESEARCH 3905）；本 plan 分账 +15..23；全批带 +15..+25 → 终值带 3984..3994", "全套 --all = orchestrator 批准制 + 运行监视 + 8G 门 + MEMFAIL 机检；正式轮 + 两轮同值复证（M7-3 三方同值先例）", "C 档停位 = 本 plan 执行+验收闭环后停汇报；确认后 P3 起跑"]
success_criteria: "SC 全可机检——T1：NSMenuParityTests ~10 法（菜单树镜像 × MenuCommandSet.visibleCommandIDs 双臂 gate 族可见性 / enabler 谓词 × 状态对象真值 / shortcut × DefaultKeymap / 标题非裸键——String(localized:) 解析 ≠ 键字面量）；T2：ShellGraphMigrationTests ~4 法（菜单闭包写 graph → face body 可见〔columnVisibility 桥〕/ 值型字段树外写者 / per-session optional 重建点）；T3：MenuBridgeObservationTests ~4 法（适配器 16 字段逐字段触发 / re-arm 幂等 / stale-enablement backstop BLOCKED 路径）；T4：窗控制器 smoke ~2 法（三控制器构造 + showWindow 不崩 + autosave/内容面 sanity）；T4 接线：Project.swift 显式清单恰四新测试文件 + BUNDLE-MAP 恰四行 + tuist generate 恒为该批最后一个动作（L041）；T5：直启宿主等价性 = 翻转前基线轮（T1 形二进制）+ 翻转后轮（T6 形二进制）各跑 --bundle Library，Executed/failed/skip 逐值相等；T6：全套 --all 三轮同值 `TOTAL|3969+ΔN/37/0|`（ΔN 带 +15..23 → 3984..3994——对账式；exit 0 零 MEMFAIL 七 bundle 8G 门内；skip 37 零漂移）；T7：16 面 GUI 走查 MANIFEST 全绿（RESEARCH §6.2 全清单）+ 三臂留档定版（A/B 二进制 + C 臂 dispatch trace 位）+ D-6 门定版（绝对 <10% 三轮 + 四哨兵）+ 门① 像素/AX 复证（zh/en 双语菜单栏）+ SUMMARY/DECISIONS 落盘"
estimated_tests: "+15..23（NSMenuParity 8..12 + ShellGraphMigration 3..4 + MenuBridgeObservation 3..4 + 窗 smoke 1..3；执行时逐任务如实记账，越带申报理由）"
test_bundles: [APP]
baseline: "3969/37/0（audit-repair 收口 9898a0fb 终态 + P1 ΔN +0..2 兑现后重算——勘误 RESEARCH 3905；P1 闭环态 = 本 plan 起算基线）"
expected_all: "3969 + P1ΔN + ΔN（对账式；P2 分账 +15..23 → 全批终值带 3984..3994；skip 37 口径维持——第三种 skip 来源逐族差分申报禁静默吸收；--all 批准制 + 运行监视 + 8G 门 + MEMFAIL 机检）"
red_lines:
  - "共用红线正本 = CONTEXT §三 plan 红线 front-matter 15 条（FIX2③ McpServerController.swift 零 diff / 封存面零 diff / 无 QA 回切 / 翻转 commit 独立可 revert〔P1 产物，本 plan 零触〕/ xcstrings 零 diff 预期 / LocalizationValue 禁形 / disable-not-unmount / 基线 3969/37/0 / AppDelegate.swift 字节零改 / DEBUG fork 序零触 / L057 缝 .runModal( 零命中复跑 / UserDefaults 应用级零新键 / --all 批准制 + parentage / C 档门控 / LightamerShell* 改名已兑现态维持）。"
  - "本 plan 产线零 diff（勘误②）：manifest face ⑤ 行重指 + batchPasteBlocked static 转移 = P3 退役范围——本 plan 纯增测试文件 + Project.swift/BUNDLE-MAP 接线，产线文件零触碰（P1 冻结态）。"
  - "测试文件域归置（M2-4-0 E2）：新测试文件按 BUNDLE-MAP 域模式归入唯一 target（壳/菜单域 = App bundle），同批更新 Project.swift 对应数组（显式清单无 glob）+ tuist generate 恒为该批最后一个动作（L041）。"
  - "--all 纪律：orchestrator 批准 + caffeinate -dis 包裹 + 运行中保持监视 + 8G 门 + MEMFAIL 机检（超门立即 kill）+ 测试宿主清理先核 parentage（ps -o ppid——测试宿主 parent = 脚本进程树，GUI 实例 parent = launchd，M2-7-3 先例）；贴线 bundle（IOP 7654 / IOPParity 5788）MEMFAIL 先查重测顺序漂移（±3% 方差）。"
  - "测试宿主等价性门（T5）是 --all 放行的前置门：等价性 FAIL = 停手上报（壳交接对测试宿主的未知影响面），禁带病跑全套。"
files_modified:
  - Tests/LightamerTests/NSMenuParityTests.swift             # T1：新建 ~10 法（树镜像/enabler/shortcut/标题）
  - Tests/LightamerTests/ShellGraphMigrationTests.swift      # T2：新建 ~4 法（graph 写读桥/值型迁移等价）
  - Tests/LightamerTests/MenuBridgeObservationTests.swift    # T3：新建 ~4 法（16 字段触发/re-arm/backstop）
  - Tests/LightamerTests/ShellWindowControllerSmokeTests.swift # T4：新建 ~2 法（三控制器构造/showWindow）
  - Project.swift                                            # T4：显式清单恰四新测试文件行
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt # T4：恰四新行（App bundle 域）
  - .work/gui-acceptance/f0prime-prod/MANIFEST.md            # T7：16 面走查全清单记录 + 门① 复证 + D-6 门定版数据
  - .work/gsd/phases/f0prime-prod/F0P-02-SUMMARY.md          # T7：执行摘要（ΔN 终账 + 三轮同值数据 + 验收判定指针）
  - .work/gsd/phases/f0prime-prod/F0P-02-DECISIONS.md        # T7：裁定记录（测试 seam 终形 + 等价性数据 + 各偏差）
---

# Plan F0P-02 — plan P2：测试族 + 直启宿主等价性 + 全套回归 + 16 面走查

> **裁决正本** = `CONTEXT.md`；规格正本 = `RESEARCH.md` §5（测试兼容面）
> + §6（回归走查）+ §7 P2 行。**勘误②约束**：manifest face ⑤ 行重指 +
> batchPasteBlocked static 转移随 P3 退役原子落地——**本 plan 产线零
> diff**，纯增测试文件 + 接线。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（T1-T7 = RESEARCH §5.5/§6/§7
> 落定值）。执行中如触「必须扩面」（产线文件改形 / harness 重写需求 /
> test-direct.sh 改形）= 停手上报——三者任一出现即是对 RESEARCH §5 结论
> 的证伪信号，属 orchestrator 裁决面。
>
> **执行序**：T1-T4 测试族（可并行起草，接线收口一次）→ T5 等价性门 →
> T6 全套 `--all`（批准制）→ T7 走查 + 定版 + 收口。每任务独立 commit
> （Conventional Commits，全英文，只 add 相关文件，不 push）。
>
> **C 档停**：T7 闭环后**停汇报**；确认后 P3 起跑。
>
> **基线**：P1 闭环态（3969 + P1ΔN；P1ΔN +0..2 兑现后由 P1 SUMMARY 终账
> 重算）。全套预期 `TOTAL|3969+ΔN/37/0|`（ΔN 全批带 +15..+25 → 终值带
> 3984..3994；本 plan 分账 +15..23）。

## ΔN 预算表（逐任务，P2 分账带 +15..23；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 NSMenuParity | **+8..12** | 树镜像双臂 ~4 / enabler 谓词 ~3 / shortcut pin ~2 / 标题非裸键 ~1..3 | NSMenuParityTests |
| T2 ShellGraphMigration | **+3..4** | columnVisibility 桥 ~2 / 值型树外写 ~1 / per-session optional ~1 | ShellGraphMigrationTests |
| T3 MenuBridgeObservation | **+3..4** | 16 字段逐字段 ~2 / re-arm 幂等 ~1 / stale backstop ~1 | MenuBridgeObservationTests |
| T4 窗 smoke + 接线 | **+1..3** | 三控制器构造/showWindow ~1..3 + Project.swift/BUNDLE-MAP 接线 | ShellWindowControllerSmokeTests |
| **合计** | **+15..23** | P1(+0..2) + P2(+15..23) = 全批 +15..25 → 3984..3994 | App bundle 域 |

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/f0prime-prod/CONTEXT.md`（D-F0P-1..10 + 勘误② +
  红线 15 条）+ `F0P-01-SUMMARY.md`/`-DECISIONS.md`（P1 终账——测试 seam
  对账源）
- `.work/gsd/phases/f0prime-prod/RESEARCH.md` §5 全节（测试兼容面：直接
  依赖点 2 文件 = P3 范围 / harness 已是 hosting 桥形 / 直启宿主等价性 /
  ΔN 预估）+ §6 全节（D-6 门 + 16 面清单 + 三臂留档）+ §2.2（NSMenu 映
  射规则——测试断言的数据源）
- `App/Sources/Lightamer/UI/Shell/NSMenuBridge.swift` + `ShellGraph.swift`
  + `ShellWindowControllers.swift` + `LightamerShell.swift`（P1 落位形
  ——测试对象正本；tree-build/enabler/观察适配器 seam 的 internal 可达
  性亲核）
- `App/Sources/Lightamer/UI/Shell/MenuCommandSet.swift:78-85`（纯函数正
  本）+ `SettingsPagesTests.swift:107-125`（DefaultKeymap pin 先例）+
  `SheetEnvironmentInjectionTests.swift:66-97`（NSWindow + NSHostingView
  + RunLoop 自挂 harness 形先例——本批测试同形）
- `.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt`（域模式）
  + `Project.swift`（显式清单形）+ LESSONS L041（tuist generate 恒末位）
- `.work/config.toml [gsd]` paused/auto 开关（开工前亲核）

---

## T1 — NSMenuParityTests（~10 法：树镜像 / enabler / shortcut / 标题）

> 测试对象 = bridge 树构建 + enablement 求值的纯 seam（Deps 闭包注入测
> 试替身）——不要求运行中的 NSApp 菜单栏；树构建函数须 internal 可达
> （P1 落位形亲核，不可达 = 停手上报，禁产线改形扩 seam——那是 P1 冻结
> 面）。

- **action**：
  1. **树镜像**（~4 法）：gate 双臂 × `MenuCommandSet.visibleCommandIDs
     (gate:phase:)`——bridge 构建树（测试 Deps 替身）的项集与纯函数双
     臂逐一镜像（多一项/少一项/错序 = fail）；系统族锚（Cut/Copy/Paste/
     Select All + 窗菜单三件）在场断言。
  2. **enabler 谓词**（~3 法）：每注册 enabler 闭包喂状态对象真值/假值
     两腿——undo/redo（canUndo/canRedo × isReadOnly × holdsControl 合
     取）/ paste 族（hasPayload × isReadOnly × holdsControl）/ New/Open
     Project（holdsControl）/ export（exportPageActive 信号源）/ 标记
     族（metadataTextEntryActive 全族禁用）/ AI 族（phase ×
     currentImageID）。
  3. **shortcut pin**（~2 法）：自定义 shortcut × DefaultKeymap 表逐项
     对账（SettingsPagesTests :107-125 数据级 pin 同形——keyEquivalent/
     modifier mask 双面）；⌘W/⌘E/⇧⌘E/⌥⌘S/⌥⌘I/bare Z/F/⌘0-6 抽点。
  4. **标题非裸键**（~1..3 法）：每菜单项 title 经 `String(localized:)`
     解析 ≠ 键字面量本身（裸键观感 = F-2 陷阱回归面；zh bundle 环境
     断言）。
- **验收标准（机检）**：
  - `--bundle App --filter NSMenuParity` 全绿；法数在 +8..12 带内。
  - `Project.swift` 恰 +1 测试文件行；测试文件零产线 import 依赖
    （NSMenuBridge internal seam 可达性亲核记录落 DECISIONS）。
- **commit**: `test(f0p2): add ns menu parity suite (tree, enablers, shortcuts, titles)`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（法数越带/seam
  形态）= DECISIONS 申报；**禁为可达性改产线 seam**（发现不可达 = 停手
  上报——P1 冻结面）。

## T2 — ShellGraphMigrationTests（~4 法：graph 写读桥 / 值型迁移等价）

- **action**：
  1. **columnVisibility 桥**（~2 法）：菜单闭包写 graph.columnVisibility
     → ContentView binding 读可见（写读桥 + 缺省 `.all` 对齐 + toggle
     语义 doubleColumn↔all / detailOnly↔all 两腿——:2692-2702 平移等价）。
  2. **值型树外写**（~1 法）：graph 值型字段（如 adjustmentTransferPresented）
     树外写者（模拟菜单闭包/delegate）→ host 树内 body 读可见（F0PRIME
     §4.4 迁移约束的回归钉——@State 存储不跨 struct copy，类实例观察是
     唯一合法形）。
  3. **per-session optional 重建**（~1 法）：thumbnailProvider 等 optional
     置换 → root face 读 box → ContentView 重建点触发（body 重读路径）。
- **验收标准（机检）**：`--filter ShellGraphMigration` 全绿；harness =
  NSWindow + NSHostingView + RunLoop.main.run(until:) 自挂形（Sheet
  EnvironmentInjectionTests 先例）。
- **commit**: `test(f0p2): add shell graph migration suite (observable box write-read bridge)`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差 = DECISIONS 申报。

## T3 — MenuBridgeObservationTests（~4 法：16 字段触发 / re-arm / backstop）

- **action**：
  1. **逐字段触发**（~2 法）：观察适配器 16 字段读集逐字段变异 → onChange
     重武装触发（sample 字段子集驱动全流程：mutation → tracked read 失
     效 → enabler 刷新路径被调）；holdsControl 字段专项（disable-not-
     unmount 的 NSMenu 侧等价实现钉）。
  2. **re-arm 幂等**（~1 法）：同一字段连续多次变异 → 适配器不重复堆积
     观察闭包（re-arm 计数守恒）。
  3. **stale backstop**（~1 法）：enablement 刷新与 dispatch 竞态 →
     handleMenu BLOCKED 路径（stale-enablement backstop :3047-3054 形）
     拦截断言。
- **验收标准（机检）**：`--filter MenuBridgeObservation` 全绿；测试零产
  线 diff。
- **commit**: `test(f0p2): add menu bridge observation suite (field triggers, re-arm, backstop)`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差 = DECISIONS 申报。

## T4 — 窗控制器 smoke（~2 法）+ Project.swift/BUNDLE-MAP 接线（tuist generate 恒末位）

- **action**：
  1. **smoke**（~1..3 法）：三控制器各构造 + `showWindow()` 挂
     NSHostingView 不崩 + 关键面 sanity（PresetManagerWindow env 两件 /
     McpLauncherPanelView 单例核心 / SettingsView 三 env 注入——注入缺
     件 = 运行时崩的 M2-8-3 FINDING-A 同族回归面）+ autosave name 已设
     断言（主窗侧，如有可达 seam）。
  2. **接线**：`Project.swift` 测试显式清单恰 +4 行（T1-T4 四文件）；
     `M2-4-0-BUNDLE-MAP.txt` 恰 +4 行（App bundle 域模式）；**tuist
     generate 恒为该批最后一个动作**（L041）；`--bundle App` 定向轮四
     族全绿。
- **验收标准（机检）**：`--filter ShellWindowController` 全绿；
  `git diff --stat` 恰四测试文件 + Project.swift + BUNDLE-MAP；tuist
  generate 在接线 commit 内最后执行（时间序面核）；产线源文件零 diff。
- **commit**: `test(f0p2): add window controller smoke suite and wire test targets`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（法数/接线行数）
  = DECISIONS 申报；**禁 glob 式接线**（显式清单无 glob——M2-4-0 E2）。

## T5 — 直启宿主等价性验证（翻转前/后二进制 Library bundle 对账）

> RESEARCH §5.4：spike 从未以 B 二进制跑过测试宿主——等价性是全套放行
> 的前置门。配方：两轮 `--bundle Library`（体量中），翻转前基线轮 =
> P1 T1 形二进制（HEAD+probe hunk，行为零差），翻转后轮 = P1 T6 形二
> 进制；Executed/failed/skip 逐值对账。

- **action**：
  1. 翻转前基线轮：P1 T1 commit 形构建 → `caffeinate -dis
     Scripts/test-direct.sh --bundle Library` → Executed/failed/skip 留
     档。
  2. 翻转后轮：P1 T6 commit 形构建（现 HEAD）→ 同配方 → 逐值对账。
  3. 不等价（Executed/failed/skip 任一漂移）= 停手上报（壳交接对测试宿
     主的未知影响面——归因禁放行）；等价 = 留档放行 T6。
- **验收标准（机检）**：两轮日志留档 `phases/f0prime-prod/host-equivalence/`
  ；对账表（Executed/failed/skip 三值）逐值相等记录落 DECISIONS；
  DEBUG fork 序零触旁证（McpHost 相关无扰动——Library bundle 不含 MCP
  跨进程族，等价性对 MCP 族的覆盖归 T6 全套轮）。
- **commit**: `test(f0p2): verify direct-launch test host equivalence across shell flip`
- **回滚与偏差申报要求**：不等价 = 停手上报（禁带病跑全套、禁静默吸收
  漂移）；偏差（bundle 选择调整）= DECISIONS 申报。

## T6 — 全套 --all（批准制）三轮同值

> orchestrator 批准制（AGENTS 资源监控节）——批准未获 = 本任务挂起等
> 批，禁自跑。

- **action**：
  1. **正式轮**：orchestrator 批准后 `caffeinate -dis Scripts/
     test-direct.sh --all`——运行中保持监视（Lightamer 进程 ps 巡检 +
     峰值 RSS ru_maxrss 机检 MEMFAIL + 8G 门 RSS_LIMIT_MB=8192；超门立
     即 kill）；测试宿主清理先核 parentage。
  2. **两轮同值复证**：正式轮绿后复跑两轮，三轮 `TOTAL|…/37/0|` 同值
     （M7-3 三方同值先例）；skip 37 零漂移——第三种 skip 来源逐族差分
     申报禁静默吸收。
  3. 对账：`TOTAL|3969+P1ΔN+P2ΔN/37/0|` 落带（3984..3994 窗口内 = PASS；
     越带 = 逐任务 ΔN 复核 + 越带申报）。
- **验收标准（机检）**：三轮日志留档（`phases/f0prime-prod/all-runs/`）；
  三轮同值 + exit 0 零 MEMFAIL + 七 bundle 峰值 8G 门内记录落 DECISIONS。
- **commit**: `test(f0p2): run full suite three-round same-value (3969+dn baseline)`
- **回滚与偏差申报要求**：MEMFAIL = 立即 kill + 上报；任何 fail = 先归因
  （本批 Δfiles 窗内?）——窗外 fail = 既有缺陷停手上报；贴线 bundle
  MEMFAIL 先查重测顺序漂移；批准未获 = 挂起，禁自跑。

## T7 — 16 面 GUI 走查 MANIFEST + 三臂留档定版 + D-6 门定版 + 门① 复证 + 收口

**read_first**：`RESEARCH.md` §6.2（16 面全清单正本）+ §6.3（回归策略）；
`F0PRIME.md` §1.2（直启协议）+ §7（证据文件清单惯例）；P1 MANIFEST（冒
烟记录——本任务全量化）。

- **action**：
  1. **16 面走查**（§6.2 全清单逐项，MANIFEST 逐项记录证据）：1 启动/
     welcome/New-Open-Recent Project 2 Import Folder + ImportModeDialog +
     进度 3 图库网格全家 4 编辑器进出双向 5 视口（含菜单 actual/fit 重
     绘缺口1 验证）6 Inspector 全页族 7 标记 15 项 + 文本框聚焦 disarm
     8 undo/redo + copy/paste + versions 9 DRT + HDR 四态 + soft proof
     10 三窗（⌘, 挂点 = 缺口3 修复验证）11 MCP stdio 27 工具冒烟 +
     agent control 持锁期菜单禁用面（§2.3）12 导出队列（JPEG+HEIC+WebP
     实跑）13 yiyin sheet + 拖拽 14 退出链 15 多显示器/全屏/⌘M/Dock
     reopen 16 zh/en 双语菜单栏像素对照。
  2. **门① 像素/AX 复证**：菜单栏 8 顶项 + zh 栏 parity 配方复用
     （F0PRIME §1 门① 形——生产二进制复测留档）。
  3. **三臂留档定版**：A（翻转前）/B（翻转后）二进制 + C（B+dispatch
     trace）位补齐，归档本 phase 目录；B 臂 = D-6 门基线正本。
  4. **D-6 门定版**：绝对 <10% 三轮 + L082 四哨兵（P1 T7 数据 + 本轮
     复测一轮定版）；相对门对照（vs F0PRIME A 臂 96.0）双证记录。
  5. **SUMMARY + DECISIONS 落盘**（ΔN 终账 + 三轮同值数据 + 等价性数
     据 + 各偏差终形）。
  6. 汇报 + **C 档停**（等用户确认再放行 P3）。
- **验收标准（机检）**：MANIFEST 16 面全绿逐项证据路径；门① 复证留档；
  三臂四文件（A/B 二进制 + trace 日志）在库；D-6 门定版数据落 DECISIONS；
  SUMMARY ΔN 对账表闭合（全批带 3984..3994）。
- **commit**: `test(f0p2): run 16-face walkthrough, archive arms, finalize d6 gate`
- **回滚与偏差申报要求**：走查面任何 fail = 先归因（翻转窗内 = 修复回注
  P1 模式；窗外 = 停手上报）；D-6 门复测 ≥10% = 停手归因禁放行；禁静默
  吸收任何走查缺项。

---

## 风险与回退

- **bridge seam 可达性**：树构建/enabler 注册表/观察适配器须 internal 可
  达——不可达 = 停手上报（P1 冻结面禁改；seam 扩展属 orchestrator 裁决）。
- **等价性门 FAIL**：翻转对测试宿主的未知影响（XCTest 注入 × 手动
  NSApplication 时序）——归因面 = fork 序/hosting 装配/probe 任务三域；
  FAIL = 停手上报，全套禁跑。
- **--all 资源面**：贴线 bundle（IOP/IOPParity）MEMFAIL 先查重测顺序漂
  移（±3% 方差，AGENTS 资源监控节）；全套轮期间 GUI 实例禁并存（探测
  轮只应有测试宿主在跑）。
- **ΔN 越带**：四族法数带 +15..23——执行时如实记账；越带 = 逐任务复核
  + 申报理由（禁凑数/禁静默）。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：RESEARCH §5.5 四族预估 ↔ T1-T4 逐族映射 + §5.4 等
   价性 ↔ T5 + §6.2 16 面 ↔ T7 逐项 + §6.3 三轮同值 ↔ T6。
2. **勘误②兑现核**：本 plan 产线零 diff（`git diff --stat` 逐 commit
   面核——只有测试文件 + Project.swift + BUNDLE-MAP + 文档）；manifest
   face ⑤ 行 / batchPasteBlocked static 未被触碰（P3 范围在位性）。
3. **OQ 兑现核**：D-F0P-5（全套轮在翻转单壳二进制上跑——无双壳并存）/
   D-F0P-1（T4 Settings env 三件注入断言）/ disable-not-unmount（T3
   holdsControl 专项 + SwiftUI .disabled 面零触面核）。
4. **纪律核**：L041（tuist generate 时间序）/ 显式清单无 glob / parentage
   一行 / skip 37 零漂移 + 第三种 skip 申报 / MEMFAIL 处置链。
5. **SC 可机检性**：每条 SC 有命令级判据；ΔN 对账式（3984..3994 窗口）。

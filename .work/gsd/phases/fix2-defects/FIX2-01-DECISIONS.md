# FIX2-01 DECISIONS — 修复批 II 裁定记录

> executor: FIX2-01 执行批（2026-10-16 夜间）。输入 = 修订版 plan（`dafcec88`+`029f84bc`）
> + FIX2-CONTEXT.md + FIX2-CHECKER.md。本文记录 T1-T3 的探针定罪、裁定与偏差。
> 证据域 = `.work/gui-acceptance/v2m/fix2-probe/`（local-only；T1 新增 `t1-*` 九件）。

---

## T1 — D-6 判别探针定罪与断环裁定

### D-FIX2-1 定罪结论：H1 三写点全部证伪，H2（框架共犯）坐实——主案断环修法不可落地，升级上报

**探针配方**（plan action 1 两段形 M-7 兑现；/tmp 即弃零 commit，证据已拷证据域）：

- View 面：`Self._printChanges()` 挂 `WorkspaceHostView.body` + `ContentView.body`
  + 深层五件（`EditorAreaView` / `FilmstripView` / `ScopePanelView` /
  `EditorAdjustmentStackView` / `EditorToolRailView` + `EDRControlView` /
  `SoftProofControlView`）。
- App/Scene 面：`LightamerApp.probeTick` 手动桩（scene body getter +
  `visibleMenuCommands` getter + `onGeometryChange` action）打 stderr，
  时间戳逐条入 transcript。
- 复现环境：Debug 直启（probed build）+ 6 TIFF 项目
  （`-la_editor_probe` 缝生成 `/var/folders/.../editor-probe-FF80F9A6-*.lalb`）
  + 杀进程重启 + Open Recent Project（AX 菜单腿）+ Enter Editor。
  `sample <pid>` 三段（idle 面 / 编辑器面 / 菜单环 6s 长采）。

**定罪读数（五条，全部 file:line 实证）**：

1. **H1-a 证伪**：`yiyinSheetDomain` 写点（WorkspaceHostView:220-222
   `onGeometryChange` action）全程仅 4 次 tick（启动布局三次 + 首帧一次），
   30s 静置零振荡——几何写环不存在。
2. **H1-b 证伪**：`.focusedSceneValue` 双写点（WorkspaceHostView:170
   workspace / ContentView:228 exportPanelRequest）在 scratch 构建中逐个
   （B1）与双双（B2）摘除——空载面 churn 率不变（sceneBody 1204/20s ≈ 60Hz）。
   焦点值写点不是驱动源。
3. **H1-c / 任意 app 写点证伪（决定性）**：编辑器面 spin 态 14298 次
   ContentView 重估 + 14269 次 WorkspaceHostView 重估（~2 分钟窗）中，
   `_printChanges` 属性变更列表**全部为 `@self`（父传值恒新，闭包身份）**，
   零次 @State/@Observable 属性变更；深层七视图（EditorAreaView/
   FilmstripView/ScopePanelView/EditorAdjustmentStackView/EditorToolRailView/
   EDRControlView/SoftProofControlView）各自**只在挂载时重估一次**，此后
   零重估。app 树内不存在失刷写点——全部重估自 scene/app-graph 层自顶向下
   驱动（`LightamerApp.body.getter` 2791 次/10s 与 ContentView 计数同频）。
4. **环身份（rearm-sample.txt 长采，6s）**：主线程 51% 在
   `flushObservers → beginTransaction → flushTransactions → graphDidChange
   → appGraphDidChange(295) → makeMainMenu(254) → updateMainMenu(240) →
   invalidateProperties(239) → requestUpdate(231) → GraphHost.updatePreferences(231)
   → UpdateStack::update → ForEachChild → View.keyboardShortcut（逐 menu item
   重挂，含 swift_getTypeByMangledName 类型元数据解析热帧）`——
   **菜单重建 ↔ 属性图更新的自持环**：`updateMainMenu(updateImmediately:)`
   触发的图刷新以 `graphDidChange` 收尾，再进 `makeMainMenu`，永不收敛。
   环内焦点侧同步可见 `FocusBridge/ToolbarBridge.preferencesDidChange →
   FocusedValueModifier.Transform.updateValue → PropertyList.prependValue`
   （每 pass 结构性重写 focus store，无值去重）。
5. **持续条件（threshold 形）**：环是否自持取决于单 pass 图工作量——
   - 空载/图库面：完整树（含 `.inspector`）= churn（34%）；**摘 `.inspector`
     （C1）或摘双 safeAreaInset（C2）任一 → 环饿死**（sceneBody 2/25s，
     CPU 归零）；B1/B2（摘焦点写点）不饿死 → 焦点写点非持续条件。
   - 编辑器面：三段内容（filmstrip / viewport / rightPane）**任摘一段 →
     环饿死**（0.0-0.1% CPU，E1/E2/E3 三向复核）；摘 `.inspector`、摘
     insets、换 `List→LazyVStack`、摘 phase 动画/转场（D1）**全部不饿死**
     （48-53%）。剩余 `List→LazyVStack` 差异测试同样阴性（47.9%）。
   - 残余骨架环：C1 形空载面 SwiftUI churn 死后仍有 ~28% CPU 的 AppKit 侧
     低频（~11Hz Source1 UpdateCycle → NSWindow layoutIfNeeded → 嵌套
     hosting layout → preferencesDidChange）底噪（c1-sample/c2-sample），
     与 D-7 wave-1 样本的 131 Source1 布局递归同族。

**定罪写点（file:line）**：app 侧**无写点可断**——写点定罪记录 = 「不存在」
（第 3 条读数即定罪：28k+ 重估零属性变更）。环身在 SwiftUI/AppKit 框架
侧（macOS 27.0.1 build 26A434）：`AppKitMainMenuItem.updateMainMenu` /
`ViewGraphRootValueUpdater.invalidateProperties` / `GraphHost.updatePreferences`
/ `PropertyList.prependValue`（无去重）——**H2 坐实**。

**修法裁定（plan action 2 各臂逐一核销）**：

- H1-a/H1-b/H1-c 臂：前提（app 写点）被第 1-3 条读数证伪，无落地点。
- **H2 备案臂（`.inspector` 宿主改形）行使评估 = 不通过**：C1 scratch
  实测摘 `.inspector` 后空载环饿死但**编辑器面环照转**（53%），且
  filmstrip 点击仍零响应（`t1-filmstrip-click-dead.png`）、空态卡不变——
  改形换不来 spin 消失，反引入 M3-4-01 T4 挂载语义迁移风险。两铁钉
  （①身份保持 ②归因确认）之归因确认已由 C1 可逆实验完成（SystemSplitView
  ← `.inspector` 归因成立但非环根），行使收益为零，不行使。
- `List→LazyVStack`（filmstrip 平台视图假说）：阴性，已回退。
- 残余判断：D-6 表型（重开项目编辑器不可用 + 82-99% spin + 点击零响应）
  的根因为 **macOS 27 SwiftUI 菜单/焦点更新机制在「重树 + churn 放大」
  配置下不收敛**（框架缺陷面），修复路径 = 框架级（系统更新/减树重构/
  窗口内容拆分立项），超出本 plan「写点断环」授权域。

**处置（plan M-8 + 执行纪律「结构性偏差停手汇报」条款行使）**：

- T1 代码面 **零 diff** 收口（全部 scratch/probe 已回退，`git status` App/
  Tests 干净；探针代码零入库，证据 transcript/sample 截图九件入证据域）。
- SC 的「编辑器面静置 CPU<10%」硬门**未过**（实测 48-53%）、「spin 消失/
  filmstrip 点击出图」铁条**未过**（点击零响应复现）——T1 不判绿，如实
  记 BLOCKED（升级待裁），不硬造判定（Checker #6 条款）。
- 上报项（orchestrator 定夺，三选一）：①接受降级（D-6 挂账至框架侧解决
  或专项立项「gate=false 壳减树/窗口内容拆分」）②research 复审（带本批
  五条读数）③回退 macOS 27 目标评估。**T2/T3/T4 与 T5 的非 D-6 依赖波次
  不受此阻塞**（T2 独立机制面；T3 零码；T5 W2-W4 走 legacy/导入通道）。

**探针裁断读数（M-2 顺带裁断，在案）**：`.focusedSceneValue` 同引用重写
在 B1/B2 scratch 中不改变环行为——框架对同引用重写无去重
（`PropertyList.prependValue` 逐 pass 结构性落盘），Equatable 载体路线
在本框架版本上**无效**；若未来行 H1-b 双腿形，priming 腿为必要非充分。

### D-FIX2-2 探针/走查产物归档

- 证据九件 = `gui-acceptance/v2m/fix2-probe/t1-*`（两 transcript + 三 sample
  + 两 d6 复现截图 + 两 scratch 样本），local-only 零 commit。
- 复现配方升级（可复用）：`-la_editor_probe /tmp/fix2t1/srctiff` 生成
  6-TIFF 项目 → 直启 → AX 菜单腿（Open Recent Project → Enter Editor）。
  AX 菜单腿全程健康（CGEvent 键盘路径未用）。

---

## T2 — D-7 进度投递合流裁定

**D-FIX2-3 合流形**：`ImportProgressCoalescer`（LibraryProjectController.swift
内，per-run 载体）——handler 收敛为「锁内单槽 latest-wins + fire-and-forget
drain 任务调度」零 await 形（M-1①钉）；100ms leading+trailing 节流；终态
（.completed/.cancelled）bypass 窗口且 supersede 在途 interim（双载体之
服务侧载体恒穿透；controller 侧 `importProgress = nil` 直写 tail 原样保留
= 第二载体零改动）；投递恒 main actor 单飞（M-1②保序钉 + adapter 单调钳
belt-and-braces 维持）。完成尾 watchdog = os Logger 一行（耗时 + 末服务侧
face），零行为变更。测试 +3 法（`ImportProgressCoalescingTests`：leading/
coalesce/trailing 三合一 + terminal bypass/supersede + 纯函数窗口判定缝），
入 LightamerTestsApp（Project.swift + BUNDLE-MAP 同批，tuist generate 末位）。

**D-FIX2-4 导入轮走查记账 + 新观察登记**：`-la_editor_probe` 缝 N 轮亲跑
（post-T2 build）= **8 完成 / 3 零行**（完成轮 6/6 行落库 + 逐行
loaded/rendered；≥3 完成轮 AC 满足）。3 笔零行失败为**另一间歇**：per-file
insert 静默失败（诊断捕获面 lastError=nil / importProgress=nil tail 照常 /
completion 照常发布 / schema+meta 落盘而 images 零行）——pre-T2 的 PNG 轮
同型失败在案（非 T2 引入）；与波 1 D-7 样本「images=0 + Media 已拷贝」
部分同面但**无停滞**（completion 恒发布）。登记为新观察（D-7 家族邻接、
独立待研），不影响 T2 AC。watchdog 的统一日志查询在本环境失聪
（`log show`/`log stream` 对直启进程零回显，权限面）；watchdog 证据 =
代码面 + R9 失败轮的 tail 执行旁证（progress=nil 即 tail 已过）。

> **勘误（2026-10-16 FIX2 双路验收批补记，原文保留不改写）**：上段
> 「per-file insert 静默失败」机理标签被双路 DB 法证**证伪**——执行批
> FAIL 三轮（`B58CAA6A`/`8F4D1DC5`/`AE849F33`）+ 第一路 FAIL 轮
> （`A8AC64C8`，WAL 626KB read-through = 6 行）的 DB **全部含 6 行**，
> 插入发生于探针 10s 等窗期间；唯一真零行 DB = `869ED347`（T1 时代异轮
> 语境）。**真实失效面 = grid 页刷新迟到**（>10s 未反映已落库行；
> fresh reload 自愈——第二路重开实验 `acc2-a8ac-reopen-grid.png` 6/6
> 可见）。三腿法证正本 = `FIX2-01-ACCEPTANCE.md` §四.1 +
> `FIX2-01-ACCEPTANCE-2ND.md` §四；疑 D-6/D-7 同族 main-actor 饥饿面。
> 独立待研立项以三腿法证为起点，勿再循 insert 路径排查。

## T3 — D-8 翻案核销登记

**D-FIX2-5 翻案核销（零产线 diff）**：真腿（文件 > 打开会话… ⌘⇧O /
Open Recent 会话列表）亲证全链路可用——建会话（网格带图 + Ready + CPU
0.1%）→ 双击进编辑器（Single 模式带图渲染 + 右栏调整栈 mount + CPU 0.1%）
→ 返回图库（probe-14 面）。三步截图 + 配方固化入
`gui-acceptance/v2m/MANIFEST.md`「FIX2-01 批 T3 legacy 通道正确配方」节
（local-only）。**核销口径（对账正本）**：挂账① D-8 行 = **翻案核销
（走查错腿 + inert-by-design），非代码修复**——「打开…」为 Phase 1 单图
载入腿从来不是会话通道；「Import Folder…」legacy 面 disabled 按设计
（M2-2-2 additive 族 + M2-2-4 剥离门 tradeoff 镜像面）；V2 #4
SESSION-LEGACY-READONLY 无「先修通道」前置。证据 =
`fix2-probe/t3-legacy-step{1,2,3}-*.png`。本任务 `git diff --stat` 仅
docs（DECISIONS 本节）。

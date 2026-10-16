# FIX2 Context — 修复批 II（D-6/D-7/D-8 + 走查复走）根因侦查与研究定稿

> research+planner 合批 worker 产物（2026-10-16 夜间批）。对象 =
> `V2M-VALIDATION.md` §挂账① 三笔缺陷（D-6 error 级候选 / D-7 导入停滞 /
> D-8 legacy 会话不可达）+ §挂账② 屏面四项义务与 D-4 复验的走查复走编排。
> 挂账正本 = `phases/v2-maintenance/V2M-VALIDATION.md`（§挂账总汇编）+
> `V2M-02-DECISIONS.md` D-V2M2-2 + `gui-acceptance/v2m/MANIFEST.md`。
> **本批亲跑侦查新增证据**（探针 /tmp/fix2probe 即弃域；关键采样已拷
> `.work/gui-acceptance/v2m/fix2-probe/`，local-only）：
> `sample-idle-face.txt` / `sample-editor-spin.txt` + probe-*.png 六图。
> 基线 = **3857/35/0**（RAW 供件缺失 11 skip 维持环境漂移口径——
> `Fixtures.arw`/`Fixtures.dng` + `LIGHTAMER_RAW_SAMPLES_DIR` 仍缺席，
> 供件备料前 skip 面不收敛）。

---

## 一、D-6（error 级候选）：重开项目态编辑器不可用 + AttributeGraph spin

### 1.1 本批复现亲跑（复现配方第三路独立亲证，配方 = 第二路验收 §六同款）

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 1 | Debug 直启 → 空载无项目面 | **CPU ~34% 持续**（静置面应 ≈0%）——**gate=false 壳自首帧起 churn** | probe-0-launch.png + sample-idle-face.txt（主线程 1150 样本中 986 在 `__CFRunLoopDoObservers` 分支；`LightamerApp.body.getter`〔:1502〕151 样本 + Commands 闭包族〔:1820-1854 ratingMenuLabel/colorMenuLabel/metadataTextEntryActive〕持续重估） |
| 2 | New Project（/tmp/fix2probe/a.lalb）+ Import Folder（6 TIFF） | 导入**完成**（images=6 行，Media/ 落盘）——D-7 本轮未复现（间歇性，与「两波各复现一次」一致） | probe-8-grid.png；导入完成后库面 CPU 仍 ~49% |
| 3 | 杀进程重启 → File > Open Recent > a.lalb → 文件 > 进入编辑器 | **D-6 严格复现**：filmstrip 6 缩略图 AX 在位 + 视口 legacy Session 空态卡「选择文件夹以创建会话」+ 右栏「未选择图像」；CPU 82.3% → 点击后 97.9% | probe-10-editor.png（与 diag-a-editor.png 同款不一致态） |
| 4 | `sample <pid> 3` | 与 t2-spin.sample.txt **同族同链**：updateGraph 37 / `AG::Subgraph::update` 22 / flushTransactions 11 / `SplitViewCoordinator.formCurrentItems` 5 / SystemSplitView 4 | sample-editor-spin.txt |
| 5 | filmstrip row 1 点击（switchCurrent 腿） | **零响应**（空态卡不变、CPU 升至 97.9%）——执行批 24 步循环零响应同面 | probe-11-click1.png |
| 6 | 文件 > 返回图库 | 正常返回（CPU 回落 ~55%） | probe-14-back2lib.png |

### 1.2 sample 栈帧解读 → 代码锚点对表（侦查核心产出）

**t2-spin.sample.txt（执行批正本，1094 主线程帧）递归环结构**（行号 = 该
sample 文件行）：

```
:49  __CFRunLoopDoObservers（783）
:53    NSRunLoop.flushObservers（775）
:55      NSHostingView.beginTransaction 闭包（455）
:56        ViewGraphRootValueUpdater.updateGraph（455）
:58          GraphHost.flushTransactions（440）
:59            AG::Subgraph::update（412）→ UpdateStack::update（398）
:62              PlatformViewChild.updateValue（107）                    ← 平台子视图更新
:65                ViewRendererHost.performExternalUpdate（106）
:67                  PlatformViewRepresentableAdaptor.updateViewProvider（70）
:68                    SystemSplitView.updateNSViewController（68）      ← ① NS 分栏控制器再入
:69                      SplitViewCoordinator.formCurrentItems（66）     ← ② 分栏项重收集
:71-87                     updateRootViewForItem → renderIfNecessary（66）
:89                          ViewGraphRootValueUpdater.render（66）
:90                            GraphHost.flushTransactions（57）          ← ③ 嵌套第二层事务冲刷
:91                              AG::Subgraph::update（56）……            ← 环闭合（回到①②族）
:801-883  环内 app 帧 = WorkspaceHostView.body.getter（16 样本，:125/:596/:309/
          :172/:181/:203/:294/:412）+ ContentView.body.getter（:192）——
          全部是普通 body 构造，无 app 写点热帧
```

**SystemSplitView 的两个宿主候选**（App/Sources 全域 grep：NavigationSplitView
仅存于 legacy 面 `ContentView.legacyBody`〔ContentView.swift:249〕与
SettingsView——D-6 发生在 gate=false 面，两者都不在树上）：gate=false 树上的
split 宿主 = **`ContentView.swift:205-219` 对 `WorkspaceHostView` 挂的
`.inspector(isPresented:)` 尾栏**（macOS 上 `.inspector` 由 SystemSplitView
分栏宿主承载——editor 面把该列拉进渲染面即触发 formCurrentItems 项重渲
路径）。spin 的「全框架帧零/近零 app 帧」形态 = 环身在 SwiftUI 框架侧，
app 侧只提供「永不收敛的失刷源」。

### 1.3 根因假说排序（侦查定稿；T1 执行批按判别探针裁定）

**共同事实面（三路样本互证，非假说）**：churn 是 **gate=false 壳族的长期
固有病**，不是 V2M 两波回归——
- 空/库/编辑器三面全 churn（probe-0 34% / probe-9 50.8% / probe-10 82.3%）；
  与 V2M 批 diff 面（`git diff 7b252db1..HEAD` 仅 ColorMatch 快照/filmstrip
  钉序/merge 对话框/toast Int 化/PATCH-LIVEPLANE eager 释放/RAW 收紧——无一
  触壳树常挂件）不符；与 m6-closeout D-1「layout churn」家族记载吻合。
- **判别性反证（本批新证）**：legacy 面（`LIGHTAMER_LEGACY_LIBRARY=1`）
  同机同 build 同为静置 → **CPU 0.0-0.1%，零 churn**（probe-18/20）——
  churn 源被锁进 **gate=false 独有树**（`WorkspaceHostView` 子树 + 其
  `.inspector` 列 + LightamerApp 对 gate-false 的 Commands 求值面）；legacy
  树（NavigationSplitView 三栏 + SessionBrowser）无此病。

| # | 假说 | 依据 | 反证/缺口 |
|---|---|---|---|
| **H1**（主嫌） | **gate=false 壳树内存在自持失刷源**（渲染路径中的 @State/@Observable 写点）， 使 ViewGraph 永不空闲；在重开空编辑器面失刷源与 `.inspector` SystemSplitView 项重渲耦合升级为硬 spin 环（每次 coordinator 更新→项重渲→再失刷→再更新） | 三面 churn + legacy 面零 churn（树差隔离亲证）+ spin 栈的 formCurrentItems 再入结构 | 失刷写点未逐点定罪——候选写点：(a) `WorkspaceHostView.swift:220-222` `.onGeometryChange { yiyinSheetDomain = $0 }`（几何→@State 写环，若尺寸振荡则永续）；(b) `WorkspaceHostView.swift:170` `.focusedSceneValue(\.lightamerWorkspaceModel, workspace)`（每次 body 求值写 FocusedValues——D-7 样本 ：591-592 亲见该 setter；App Commands 读 `focusedWorkspace?.phase`〔LightamerApp.swift:1622/471〕→ App body 重估 → WindowGroup 内容重求值 → WorkspaceHostView body 重求值 → 再写……若 FocusedValues 写不按值去重即闭环，与 probe-0 中 App body+Commands 持续重估的观测吻合）；(c) `:153-157` 只读横幅 / `:166-169` toast 横幅（纯读，低嫌） |
| **H2**（框架共犯） | macOS 27 SwiftUI `.inspector`/SystemSplitView 对「更新期内再失刷」的内容缺乏收敛保护（框架 bug 面），app 侧 churn 只是点火条件 | spin 环三层全框架帧；M3-4-01 已与 `.inspector` 呈现回声交手一次（present-echo no-op 现挂） | 无法改框架；只能消 app 侧失刷（H1 修复后 spin 应 starving 而亡）或避开 `.inspector` 宿主形 |
| **H3**（已降权） | 重开路径的窗口/分栏状态恢复（NSSplitView autosave / columnVisibility）特异触发 | 「重开 vs 同会话新建」表面对比 | **被本批亲跑削弱**：churn 不需要重开也存在（空载首帧即 churn）；重开只是把 churn 升格为硬 spin 的放大器（编辑器空态 + filmstrip 在 = 进入 SystemSplitView 重渲路径）。「同会话新建健康」旧对照（walk-8）为双击入编辑器带图态，非同态对照 |

**T1 判别探针（执行批第一步，/tmp 即弃）**：`Self._printChanges()`（或
OsLog signpost）临时挂 `WorkspaceHostView.body` + `LightamerApp.body` +
`ContentView.body`，空载静置 30s 读重估流——日志直接打印**哪个 view 因
哪个属性重估**，一次定位 H1 的 (a)/(b)/(c) 或暴露第四写点。此探针零产线
diff（调试完即除），不触红线。

### 1.4 修法方向（主/备）

- **主案（H1 定罪后）**：在定罪写点处断环——(a) 型 = `yiyinSheetDomain`
  写点加等值守卫或改 `onGeometryChange` 的消费形态（sheet 挂载时才量测）；
  (b) 型 = focusedSceneValue 改为**只在 phase/实例真变时写**（SwiftUI 惯用
  法：把写点从 body 提到 `.onChange(of: workspace.phase)`/任务缝，或发布
  稳定 Equatable 载体）；(c) 型若坐实则改读缝。纯 App 域，预期 ΔN 小。
- **备案（主案消环后 spin 仍现，或 H2 坐实）**：`ContentView.swift:205-219`
  的 `.inspector(isPresented:)` 改形——页面未激活时不挂 SystemSplitView 宿主
  （`if inspectorState.exportPageActive || filmPageActive` 包裹 or 改自定义
  尾栏 HStack 形），把 editor 面从分栏重渲路径摘出；代价 = M3-4-01 T4 的
  挂载语义重验（dismiss 双关 + present no-op 约定迁移），红线零触但 UI 面
  须走查复验（export/film 页挂载行为）。
- **验收铁律（任务书原文兑现）**：D-6 修复验证**必须含屏面走查**——重开
  项目 → 文件 > 进入编辑器 → (1) CPU 静置回落 <10%（`sample`/`ps` 机检）；
  (2) 编辑器可用（filmstrip 点击换图 + 视口出图 + 右栏 mount）；
  (3) 截图证据入 `gui-acceptance/` 证据域。仅单测绿不算修复验证。

## 二、D-7：导入停滞（Media 拷贝完成后完成态不发布）

### 2.1 栈解读（wave-1 `import-stall-sample.txt`，2116 主线程帧 + 全 4 线程）

- 主线程分布：**909 mach_msg 空转 + 968 runloop observers 分支**（其中
  flushObservers 966 → beginTransaction 505 → updateGraph 505 →
  flushTransactions 460 → `Subgraph::update` 450 → WorkspaceHostView.body
  27 样本 + `destroy for BackgroundTaskBarView`〔:1724，身份churn 佐证〕）
  + **131 Source1 UpdateCycle → NSDisplayCycleFlush →
  `NSWindow layoutIfNeeded`（107）→ `_layoutSubtreeWithOldSize:` 深达 6 层
  递归**（嵌套 hosting 视图链反复强制布局）。
- **全样本零 ImportService/零 import 链帧**；后台仅 2 个 workq 线程纯停泊
  ——import actor 在采样窗内**完全不在执行**。
- `images=0`（20s 后）+ Media 已拷贝 + 进度条 >10min 不发布完成态。

### 2.2 根因面（与 D-6 同根异症；与 M2-9 F-1 **分根**）

- **主 actor 饥饿闭环**：`LibraryProjectController` = `@MainActor @Observable`
  （LibraryProjectController.swift:41-42）→ `runImport`（:384-435）整体在
  main actor 上：`await service.importFolder(plan)` 的**续体**、逐文件
  `emit()` 的 `Task { @MainActor in self?.importProgress = snapshot }`
  进度投递（:389-391 + ImportService.swift:736-738）、以及完成尾
  `importProgress = nil`（:416）全部排 main actor 队。churn 把主线程钉在
  观察者冲刷/布局循环上（45-99% CPU），逐文件进度 hop 与完成尾被饿成
  「分钟级停滞」观感；actor 侧每个文件之间若含 main-actor 边界 hop 即
  同步被饿（样本零 actor 帧 + 主线程仍有 909 空转 = 两头都在等对方让出
  调度窗的形态）。**与 D-6 同根**：消 churn（D-6 主案）即拆饥饿源。
- **批内硬化点（T2，独立于 D-6 的防御面）**：
  1. 进度投递合流——逐文件 `Task { @MainActor }` 改节流合流（如 ≥100ms
     或 ≥N 文件一次投递，完成态恒即时），把 main-actor 排队面从 O(文件数)
     降到 O(节流数)；
  2. 完成尾 watchdog——`importProgress = nil` 发布前对「已超时未发布」
     打 OsLog（诊断面，不改行为）。
- **F-1 家族对表（裁定 = 不同根，不合修）**：M2-9 F-1 = Import 面板
  **取消即崩**（呈现/闭包生命周期 crash）；D-7 = 导入**停滞**（调度饥饿）。
  同在 ImportModeDialog 面但机制不相交；F-1 自有挂账（M2-9 F-1），本批
  只对表不修。T2 顺带义务：import 走查时若 cancel 腿可安全触达则记录
  F-1 现状，不扩大范围。
- **本批亲跑**：6 文件导入全程完成（probe-8）——D-7 为间歇性（两波各一次
  + 本轮零次），T2 的走查 AC 用「N 轮导入循环 + 完成态发布 + CPU 静置
  回落」机检，不依赖单次复现。

## 三、D-8：legacy 会话建立通道——**走查通道错腿翻案（本批修正判定）**

### 3.1 亲跑翻案证据

| 腿 | 本批亲跑 | 结果 |
|---|---|---|
| 文件 > 打开…（walkthrough 用的腿） | 门面 = Phase 1 单图载入腿（`FileOpener.openImage` → `editorState.load`，LightamerApp.swift:1515-1528 / ContentView.swift:551-562）——**从来不是会话建立腿** | 载图成功但网格无会话 = **按设计**，非缺陷 |
| 文件 > 打开会话…（⌘⇧O，真腿，LightamerApp.swift:1530-1552，`visibleMenuCommands.contains(.sessionOpen)` 门内） | `LIGHTAMER_LEGACY_LIBRARY=1` 直启 → 菜单在位（probe-16 面件清单含 新建会话…/打开会话…/最近打开/关闭会话）→ 选 /tmp 目录 → 确认 | **会话建立成功**：网格 6 TIFF 缩略 + 状态栏恢复提示 + **CPU 0.0%**（probe-18/20） |
| 文件 > Import Folder…（walkthrough 报「无面板」） | 该项在 legacy 面属 M2 项目命令族（M2-2-2 additive，`libraryProjects.projectStore == nil` 时 **disabled**，LightamerApp.swift:1600） | 按设计禁用（legacy 面无项目）——M2-2-4 剥离门在案 tradeoff（「File 菜单 Session 项暂未门控」镜像面） |
| `open -a` 文档语义 | 同打开…腿（odoc → 单图载入） | 按设计 |

### 3.2 定案与义务

- **D-8 无产线代码缺陷**：走查批把「打开…」（单图腿）误作会话建立通道，
  加上 M2 项目命令在 legacy 面的 inert-disabled 可见性，两事叠加读作
  「会话建立不可达」。真腿（打开会话…）全链路可用——V2 #4
  SESSION-LEGACY-READONLY 若立项，通道已通，无「先修通道」前置。
- **连带解锁（T3 核销 + T5 复走）**：legacy 面走查全阻断（D-4/D-5 merge、
  pano 16-19、栈面 34-38）随正确配方解锁；m6-closeout MANIFEST 的
  Blocked-Channel 行（D-7/D-8 依赖族）按 T5 编排复走。
- **T3 义务收窄为**：(1) 正确配方落 `gui-acceptance/v2m/` MANIFEST
  （`LIGHTAMER_LEGACY_LIBRARY=1` 直启 + 打开会话… ⌘⇧O 全步配方，配
  probe-16..20 证据）；(2) 打开会话… 腿的回归确认走查（建会话 → 网格
  带图 → 打开编辑器加载成功三步）；(3) DECISIONS 登记翻案 + 挂账①
  D-8 行销账口径。**若执行批复跑真腿意外失败**（环境差异），升级为
  真修任务并 DECISIONS 申报——主案为零码翻案。

## 四、走查复走波编排（plan T5，前置 = T1-T4 全绿）

> 派发依据 = `V2M-VALIDATION.md` §挂账② + `V2M-01-ACCEPTANCE-2ND.md` §五
> E2-1 + `V2M-02-ACCEPTANCE.md` §六。通道 = AX+CGEvent+screencapture
> harness（波 2 已证健康）+ B 类 computer-use（用户指令：走查批 B 类）。
> 证据落 `.work/gui-acceptance/v2m/`（local-only 零 commit）。

| 波次 | 行集 | 前置通道 | 终态判据 |
|---|---|---|---|
| W1 | **D-6 修复验证**（§1.4 铁律三条）+ V2M-T1-02（D-1 三零消除点击：solve 进度态/读数 1s/history item+sidecar）+ M6C-03/05（追色 solve 面）+ 06 数值面 + 07 before/after | T1（项目编辑器通道恢复） | 逐行 Executed + 截图；hasImage=nil 批外疑点顺带记录 |
| W2 | V2M-D3-01（≥4 图 ×N 轮 filmstrip 连点零卡死）+ V2M-D4-01（三合并对话框标题计数——**若复验仍见 0 按「快照上移」预案返工，一轮损失不产假交付**）+ V2M-D5-01（toast zh 文案）+ 08 | T1 + W1；merge 动作经项目面 import 供件 | 逐行 Executed；D-4 复验裁定记录 |
| W3 | **D-7 复验**：导入循环 N 轮完成态发布 + CPU 静置机检 + F-1 现状记录 | T2 | 逐轮 Executed/Registered |
| W4 | legacy 面行：D-8 翻案确认配方 + pano 16-19（合成切片供件）+ 栈面 34-38（连拍 auto-stack 供件）+ 40（guided filter 编辑器面） | T3（legacy 通道配方） | 逐行 Executed 或供件缺口如实登记 |
| 不入波 | 24/25（HDR 显示器）/26（UltraHDR 样张）/27-31/39（layer 资产/真多人素材等供件族） | 供件/硬件缺座维持原清单 | — |

## 五、对账与红线基线

- 基线 = **3857/35/0**（V2M 终值）；ΔN 预期带 = +0..4（T1 回归钉 +0..2 +
  T2 硬化钉 +0..2；T3 零码翻案 ΔN=0；执行时逐任务如实记账，ΔN=0 合法——
  D-3 先例）；`expected_all = 3857 + ΔN`；skip 35 维持（RAW 供件域漂移
  口径，备料后自动收敛 24）。
- 红线（plan front-matter `red_lines` 正式化）：`.metal` 全域零 diff；
  `LightamerIOP/` 零 diff；sidecar schema 零触；封存面九件零触；
  `\.runModal(` 零命中；LocalizationValue 插值禁形零命中；UserDefaults
  零新键；xcstrings 零 diff；`Project.swift` 无新测试文件则零 diff（若
  T1/T2 加测试文件，BUNDLE-MAP + Project.swift 同批登记 +
  `tuist generate` 恒末位 L041）；构建 `caffeinate -dis` 包裹；全套
  `--all` orchestrator 批准制 + 8G 运行门（AGENTS 资源监控节）。

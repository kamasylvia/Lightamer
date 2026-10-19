# F0'-production Research — 壳交接生产化侦察正本

> **性质**:F0-prime production 批 research(charter `35a6c178`,量级 M)。只读侦察 +
> 产物落盘,零源码触碰、零账本触碰。
> **输入正本**:`.work/gsd/phases/nsmenu-spike/F0PRIME.md`(双门 PASS)+ spike 分支
> `spike/f0prime-shell`(`a35ad151`/`c9a91562`/`d8d1380a`,patch 正本
> `0001..0003-*.patch` + `f0prime-full.stat`)+ `research/UI-STACK-SUCCESSOR-PRE.md`
> + `research/APPLE-FB-D6-DRAFT.md` + AGENTS.md 架构增量节(装配缝/KD-4/D-H1/
> L057/FIX2③/Sheet 注入)。
> **方法**:HEAD 全量 grep/逐文件读取 + spike patch 逐 hunk 解剖。日期 2026-10-18。
> **去向**:plan 切分呈 charter 门。

---

## 0. Verdict Head（结论头）

1. **壳交接生产形成立**:spike 形(@main 手动 NSApplication + delegate 托管 NSWindow +
   NSHostingView + 自建 NSMenu)直推生产,**Scene 面穷举零架构层阻力**——1 主窗 + 2 次级
   窗 + 1 Settings + 1 Commands 块(~55 自定义项 + 系统族)+ 4 sheet + 1 overlay + 1 alert
   + 3 toolbar 组 + 4 focused-value 键,逐个给出 NSApp 形态映射(§1/§2)。
2. **未追踪读审计(本批最大未知数)已定盘**:审计点位 ~50,真实缺口 **4**(1 功能缺口族
   = zoom 签名;1 时机修正;1 stub 迁移点组;1 视觉差异族)——M 批预算成立,不升级(§3)。
3. **测试兼容面轻**:App bundle 104 文件(Project.swift 显式清单;charter 口径 921 测试),
   直接依赖 App struct 的仅 **2 文件 3 处**;视图测试 harness 已是 NSHostingView+NSWindow
   自挂形(天然 hosting 桥兼容);直启宿主需一项等价性验证;**ΔN ≈ +15..+25,0 harness 重写**(§5)。
4. **plan 切分:3 plans**(P1 壳交接翻转+审计修复 → P2 测试+全套回归+走查 → P3 死码退役
   +文档回填),每 plan C 档门控停(§7)。

---

## 1. Shell Handover Production Form（侦察 1:Scene 面穷举）

### 1.1 spike 形基准(已验证的移植约束)

- 入口:`F0PrimeShellMain.run()`(patch 0002 :2370-2398)= `NSApplication.shared` +
  `.regular` policy + delegate 持有(`retainedDelegate` 防 weak 释放)+ `app.run()`。
  主 tip 入口 fork 序(`App/Sources/Lightamer/UI/LightamerApp.swift:128-158`:DEBUG 两把
  flock fixture → MCP headless → AI worker → GUI)必须**逐字保留在生产 @main**——四把
  fork 全部不构造 App 状态,壳交接不触及(McpProjectToolsetTests 的 STDIN_FILENO dup2
  纪律依赖此序)。
- 主窗:`F0PrimeShellController.presentMainWindow()`(patch 0002 :2261-2280)= NSWindow
  1440×900 + `.titled/.closable/.miniaturizable/.resizable` + `NSHostingView(face)` +
  `setFrameAutosaveName` + `makeKeyAndOrderFront`。
- delegate 组合:`F0PrimeShellDelegate` 组合生产 `AppDelegate`(final,组合转发)——
  open Apple Events(`application(_:open:)`)+ `applicationWillTerminate`(**参数类型
  `Notification` load-bearing**,LightamerApp.swift:190-201 的 M2-8-2 T4 教训)逐字转发;
  `applicationShouldTerminateAfterLastWindowClosed = true` 对齐 SwiftUI 默认。
- face 移植形:`F0PrimeShellFace` View struct + 同名属性(值语义保闭包隐式 self 捕获形)+
  `F0PrimeShellGraph`(@Observable box,9 字段)承载树外写者(§4)。

### 1.2 Scene 面穷举映射表(现形 → NSApplicationDelegate 形)

| # | 现形(file:line) | NSApp 生产形 | 风险档 |
|---|---|---|---|
| 1 | `@main` LightamerEntryPoint(LightamerApp.swift:128-158) | `LightamerEntryPoint.main` 尾改调 ShellMain.run();fork 序原样 | 低(spike 已验) |
| 2 | `Window("Lightamer", id:"main")`(:507)+ `.defaultSize(1440,900)`(:1797)+ `.windowToolbarStyle(.unified)`(:1798) | delegate `applicationDidFinishLaunching` 建主窗(spike 形;OQ-F0P-7);toolbar 样式缺席→§3-D2 | 低 |
| 3 | env 链 23 对象(:525-547)+ `.preferredColorScheme(.dark)`(:548) | NSHostingView rootView 内同一链(注入进 face;SwiftUI env 在 hosting 下全活,F0PRIME 门③) | 低 |
| 4 | WindowCapture background(:552-556)→ `pipeCoordinator.configure(window:)` | 原样保留(face 内;D-COL2 多屏跟随窗屏语义不变) | 低 |
| 5 | 三 `.task`(edrHeadroom :557-561 / welcome :562-571 / wiring :572-1661) | face `.task` 原样(spike 已移植)——wiring ~1088 行 + helpers ~660 行逐字搬运 | 中(体量,机械) |
| 6 | 4 sheet(ImportModeDialog :1666 / Welcome :1681 / ProjectConflict :1710 / AdjustmentTransfer :1750) | face `.sheet` 原样——hosting 桥下 sheet 装配已验(F0PRIME 门③;M2-8-3 FINDING-A 内容面重注入惯例维持) | 低 |
| 7 | onChange(:1761)+ overlay(:1771)+ alert(:1782) | 原样;overlay 进度条 legacy 面 gate=true 时可空转 | 低 |
| 8 | `.commands` 全块(:1799-2205)≈55 自定义项 | NSMenuBridge 树生产化(§2) | 中 |
| 9 | `Window("window_preset_manager", id:"preset-manager")`(:2212-2218) | AppKit 窗控制器:NSWindow+NSHostingView(PresetManagerWindow+env 注入 presetsStore/presetController/dark);菜单项/toolbar 入口改调控制器(缺口3 组) | 中 |
| 10 | `Window("window_mcp_launcher", id:"mcp-launcher")`(:2224-2227) | 同上(McpLauncherPanelView,单例核心 McpLauncher.shared 不受损) | 中 |
| 11 | `Settings { SettingsView }`(:2236-2244,⌘, 系统挂点) | AppKit Settings 窗(同形;⌘, 项 action 直调窗控制器;OQ-F0P-1) | 中 |
| 12 | `@Environment(\.openWindow)` 3 调用点(App :2024/:2029;ContentView :551) | 窗控制器 `showWindow` 缝;openWindow env 退役 | 低 |
| 13 | focused-value 4 键(:15-35 键定义;消费 :449-467;发布 ContentView :249-250/:798、WorkspaceHostView :195、InspectorView :428) | bridge note-box 三件(noteWorkspace/noteExportPresent/noteMetadataFocused;spike 形);⌥⌘S/⌥⌘I 写回缺口见 §3-C1 | 中 |
| 14 | `@FocusedBinding` 菜单侧 enable(:1961 exportPanelRequested==nil 等) | bridge enabler 读 note-box(已验形) | 低 |
| 15 | toolbar 3 组(ContentView :503/:532/:597) | hosting in-face 渲染(已验;功能态 tracked;视觉差异登记) | 低(差异) |

**多显示器/全屏/⌘M/reopen**:
- 多显示器:WindowCapture 跟窗屏(D-COL2 既有);EDRHeadroomMonitor 双屏通知(:557 注释)
  事件驱动不受壳影响。
- 全屏:spike styleMask 无 `.fullScreen`——生产补 `.fullScreen`(一行);MTKView drawable
  resize → D-C3 bucket 链既有(EditorAreaView.swift:274-277 `onChange(geo.size)`)。
- ⌘M:minimize 原生 selector 已验(F0PRIME 门①);窗菜单 build 形 patch 0002 :2911-2921。
- Dock reopen:补 `applicationShouldHandleReopen`(一行,显示/重建主窗;SwiftUI 默认行为
  的对齐项)。

### 1.3 Deps/装配缝在新 @main 下的装配序

- **顺序不变性**:wiring `.task` 的装配序(editorState.attach↔pipeCoordinator ↔
  versionCoordinator 三角先于任何 open drain,LightamerApp.swift:577-603;catalog 重指
  :612-619;MCP host 装配尾 :1648-1660)逐字搬运即保序——spike 全链 probe 通过证明该序
  在 hosting 桥下成立。
- **M2-1 注入式(D-EXEC-1)**:`legacyLibraryEnabled` 是 let(controller 持有,spike 同形);
  视图 body 零 ProcessInfo 纪律不受扰。
- **M7-6 GUI plain-await 闭包**:`agentControl.acquire` 的 plain-await MainActor hop 形
  (:1634-1647)+ `admit` gate(:1654-1660)是闭包形态,壳交接零触碰。
- **FIX2③(McpServerController 文件零 diff)**:wiring 只调 controller 公开面,壳交接
  不触文件——红线维持。
- **L057 缝**:菜单/按钮 action 一律 `Task { await … }` + PanelPresentation.begin;
  机检门 `grep -rn "\.runModal(" App/Sources` 零命中须在 P2 复跑。

### 1.4 spike 已验证存活面 + 已知差异(生产化登记)

- 存活(冒烟实证,F0PRIME §3/§4.5):23 对象 env 链、@Observable 三级读、Bindings、四
  sheet、NSSavePanel begin 缝、缩略图管线、EXIF/元数据 inspector、EditorProbe、MCP host
  装配、AppDelegate open/terminate 转发、色温滑杆 pipe 重渲染。
- 已知差异四件:①窗级 unified toolbar 样式(§3-D2);②三处次级窗 stub(§3-缺口3 组,
  生产化解决);③菜单缩放重绘(§3-缺口1,生产化解决);④window title 附着 toolbar 形态
  (并入①)。

---

## 2. Menu Parity Inventory（侦察 2:菜单全族清单)

### 2.1 全族清单(8 组;自定义 55 项 + 系统族)

数据源 = `MenuCommandSet.visibleCommandIDs(gate:phase:)` 纯函数(MenuCommandSet.swift:
78-85;可见性 phase-independent,enablement 归 app 层——KD-6 语义原样保留)。逐项
(file:line 均为 LightamerApp.swift,除非另注):

**App 菜单(7)**:About / Settings…(⌘,) / Services / Hide(⌘H) / Hide Others(⌥⌘H) /
Show All / Quit(⌘Q)——spike buildAppMenu 形已验(patch 0002 :2622-2653);Settings 项
action 生产 = 真窗控制器(OQ-F0P-1;spike 用私有 selector `showSettingsWindow:` 仅冒烟)。

**File(16)**:
| 项 | gate/enable 条件 | shortcut | 行 |
|---|---|---|---|
| menu_new_session | sessionNew;恒 disabled | ⇧⌘N | :1802-1806 |
| menu_open | 恒可用 | ⌘O | :1812-1826 |
| menu_open_session | sessionOpen | ⇧⌘O | :1831-1838 |
| menu_open_recent(动态) | sessionOpen;recentSessions 空→disabled | — | :1841-1848 |
| menu_close_session | sessionClose;恒 disabled | ⇧⌘W | :1854-1856 |
| New Project… | !holdsControl | ⌘N | :1865-1869 |
| Open Project… | !holdsControl | ⌥⌘O | :1870-1874 |
| Open Recent Project(动态) | !empty ∧ !holdsControl | — | :1875-1890 |
| Import Folder… | projectStore != nil | ⇧⌘I | :1900-1904 |
| Backup Project… | projectStore != nil | — | :1906-1909 |
| Move Project… | projectStore != nil | — | :1910-1913 |
| menu_enter_editor | workspaceEnterEditor;phase==.library | ⌘E | :1921-1927 |
| menu_back_to_library | phase==.editor | ⌘W | :1928-1934 |
| menu_library_search | focusedWorkspace != nil | ⌘F | :1939-1945 |
| menu_save_sidecar | 恒 disabled | ⌘S | :1950-1952 |
| menu_export | exportPanelRequested != nil | ⇧⌘E | :1958-1962 |

**Edit(8 + 文本族 4)**:menu_undo(⌘Z;!canUndo∨isReadOnly∨holdsControl :1972-1983)/
menu_redo(⇧⌘Z 同 :1984-1989)/ menu_copy_adjustments(⇧⌘C;loadedImageURL==nil
:1995-1999)/ menu_paste_adjustments(⇧⌘V;!hasPayload∨isReadOnly :2000-2004)/
menu_paste_partial(同上无 shortcut :2005-2008)/ menu_copy_adjustments_dialog(
loadedImageURL==nil :2014-2018)/ menu_preset_manager(:2023-2026)/ menu_mcp_launcher(
:2028-2031);Cut/Copy/Paste/Select All(⌘X/C/V/A 系统文本族——spike 尾部已带,patch :2782-2789)。

**View(12)**:menu_show_sidebar(⌥⌘S :2036)/ menu_show_inspector(⌥⌘I :2038)/
menu_show_film_panel(:2048)/ softproof_toggle Toggle(⌥⌘P;state=isActive :2057)/
softproof_gamut_check Toggle(disabled:!isActive :2062)/ menu_actual_size(bare Z
:2072)/ menu_fit_to_screen(bare F :2076)/ stacks expand/collapse(无 shortcut
:2087-2094)/ menu_view_tool_rail/scopes/adjustment_stack 三 Toggle(viewToolRail gate;
state=*_visible :2100-2108)。

**标记 Metadata(15)**:rating clear(0)+1-5(bare);flag pick(P)/reject(X)/clear;
color clear(⌘0)+1-6(⌘1-6);全族 disabled = metadataTextEntryActive(:2119-2164)。

**Image(2)**:menu_image_ai_upscale / ai_denoise(disabled: phase!=.editor ∨
currentImageID==nil;AX marker AIEntryPointCoordinator.Marker :2172-2195)。

**Help(1)**:menu_help(disabled;⌘? :2201-2203)。

**窗口菜单(3+自动窗清单)**:Minimize(⌘M)/ Zoom / Bring All to Front(patch :2911-2921;
NSApp.windowsMenu 自动并集已开的次级窗)。

shortcut 总计 ≈ 47(自定义 43 + 系统族);与 DefaultKeymap 表的核对 = SettingsPagesTests
:107-125 既有 pin(数据级,零 diff 存活)。

### 2.2 NSMenu 映射规则(spike 形 → 生产化)

- 树构建一次 + `autoenablesItems=false`;per-item action/enabler/state 三注册表
  (ObjectIdentifier 键);dispatch `handleMenu` 带 stale-enablement backstop(patch
  :3047-3054);`menuNeedsUpdate` 做动态子菜单重建 + 全量 enablement 刷新(patch
  :3036-3038);观察适配器 `withObservationTracking` 单读集 + onChange 重武装(patch
  :3003-3032)——**enable 绑定走 tracked 读(接 §3)**:16 字段读集覆盖全族 enabler。
- zh/en:菜单 key 全走 `String(localized: String.LocalizationValue(key))` 整字面量(无
  新键,patch :2611-2613);门①像素/AX 证 zh 栏 `Lightamer|File|Edit|显示|标记|图像|Window|Help`
  与 A 臂一致(F0PRIME §1 结论头)——**系统组标题(File/Edit/Window/Help)现形本就英文**,
  parity 已实证;xcstrings 零新增。
- 菜单 action 的 L057 纪律:Deps 闭包内 `Task { await … }` hop(spike face 装配同形)。

### 2.3 DisableChallengeFace 的 NSMenu 等价物(M7-5/M7-6 语义)

- agent 控制期禁编辑面:SwiftUI 侧 10 处 `.disabled(...holdsControl)` manifest
  (AgentControlCoordinatorTests.swift:228-235,face ①-⑫)——hosting 桥下全部原样存活
  (tracked body 读)。
- NSMenu 侧等价物 = **enabler 闭包读 `agentControl.holdsControl` + 观察适配器 tracked
  读集含 holdsControl**(patch :3013):New/Open Project、Open Recent、undo/redo、
  paste 族 7 项受 holdsControl 合取(spike 已形);`handleMenu` backstop 再拦一遍竞态。
- 生产化注意:face ⑤ 行(manifest 中 `UI/LightamerApp.swift` 的
  `|| agentControl.holdsControl)` token)在 App struct Commands 退役后**必须重指**到
  壳文件(P3,§5)。

### 2.4 已知 parity 风险四件

1. **⌘W 语义**(OQ-F0P-3):editor face ⌘W = closeEditor(:1928-1934)优先——NSMenu 主
   菜单项在窗口 performClose 之前拦截 keyEquivalent,语义可保;library face 的 ⌘W 落点
   (窗口 Close vs 禁用)需 plan 阶段实测现行 File 菜单 AX 内容后 1:1 对齐。
2. **Settings ⌘,**:私有 selector 是冒烟形,生产 = 真窗控制器(OQ-F0P-1)。
3. **export 双发布点**(ContentView :250 sheet 腿 + InspectorPageMount :798 page 腿):
   gate=false 面 action 直走 `inspectorState.openExportPage()`(F0PRIME §1.1 同缝裁定);
   enablement 信号从 exportPageActive onChange 注入 bridge(§3-B17)。
4. **动态子菜单**:recentProjects/recentSessions 的 menuNeedsUpdate 重建已验(patch
   :2932-2970);多窗时 windowsMenu 自动清单为 AppKit 出厂行为,零改。

---

## 3. Untracked @Observable Read Audit（侦察 3:壳级状态读点全量审计)

### 3.1 方法

(a) 从 spike 观察到的失效面(菜单缩放,F0PRIME §4.3)反向解剖:失效链 = mutation 在
tracked 上下文外 → `updateNSView` 是非追踪上下文 → 编辑器面 body 无 tracked read →
churn 静默后 updateNSView 永不再跑。(b) 全量枚举读面:App target 的 NSViewRepresentable
仅 2 文件(grep 实证:EditorMTKView.swift + LightamerApp.swift/WindowCapture);壳级
@Observable 消费面 = App struct body(Commands/env/enable)+ bridge 适配器 + focused-value
族 + 窗族 + 动作时活读。(c) 逐点分类:**tracked-in-body(壳交接后仍活)/ action-time-live
(读即真值,无需跟踪)/ 真缺口(依赖 churn 顺手 re-eval)**。

### 3.2 点位清单(~50 点位)

**A. NSViewRepresentable 域(3 点)**
| 点 | 现读点 | tracked? | 壳交接后 | 修法 |
|---|---|---|---|---|
| A1 | EditorMTKView.updateNSView zoom/pan/rot 签名 push(EditorMTKView.swift:127-138;签名读在 updateNSView 内:131-138) | ✗ 父 body(EditorAreaView.swift:61-328)对 zoom/pan/rotationDegrees 零 tracked read(gesture/onChange 闭包读不入跟踪) | **静默失效**(缺口1——菜单 actual/fit 不重绘;手势路径不受扰:coordinator 自持 view 引用直接武装,F0PRIME §4.3) | OQ-F0P-7 推荐:zoom 签名变 EditorMTKView **构造参数**(EditorAreaView body 计算传入)——观察纪律显式化 + 机检形,与 sourceTexture push-once 同构 |
| A2 | updateNSView 其余 push(sourceTexture/secondary/split/edr/drt) | ✓(EditorAreaView body 读 displayTexture :419、loadedImageURL :66/172/190、beforeAfterState :83-85/:181、pipeCoordinator.edrDisplayEnabled/drtViewportSurface :86-87) | 活 | 零改 |
| A3 | WindowCapture(:217-243 viewDidMoveToWindow) | 事件驱动 | 活 | 零改 |

**B. 菜单 enablement/标题域(20 点 = 16 观察字段 + 4 生产修正)**
16 字段(spike armObservation 读集,patch :3006-3025):editorState.canUndo/canRedo/
loadedImageURL、pasteboard.hasPayload、libraryProjects.isReadOnly/projectStore/
recentProjects、agentControl.holdsControl、softProofState.isActive/gamutCheck、
sessionState.recentSessions、workspace.phase/editorPhase.currentImageID/toolRailVisible/
scopesVisible/adjustmentStackVisible、metadataFieldFocusedState、exportPanelRequestPresent
——适配器形已验,零改。4 修正:
| 点 | 现形 | 壳交接后 | 修法 |
|---|---|---|---|
| B17 | exportPanelRequestPresent note = **onAppear 一次性 true**(patch ContentView :59-61) | **时机缺陷**(翻转态不可见——sheet 关闭后菜单项恒亮/恒灭) | 缺口2:生产改 onChange(exportPanelRequested) 双态注入;或直接读 exportPageActive(InspectorPageMount 同源) |
| B18 | export 双发布点(§2.4-3) | action 缝已裁(直走 openExportPage) | enablement 读 inspectorState.exportPageActive(tracked 由适配器收) |
| B19 | metadataFieldFocused onChange 注入(patch InspectorView :76-79) | ✓ 已验 | 零改 |
| B20 | workspace note onAppear 单窗(patch WorkspaceHostView :3068-3070) | ✓ 单窗;多窗后置(P3 走查项) | keyWindow 判定挂账 OQ-F0P-5 |

**C. focused-value 域(4 点)**
| 点 | 现形 | 壳交接后 | 修法 |
|---|---|---|---|
| C1 | ⌥⌘S/⌥⌘I 写 `focusedColumnVisibility`(App :449/:2692-2702;真相 = ContentView 本地 @State :143) | **stub**(spike 未移植——F0PRIME §1.1 四项 stub 之二) | 缺口3a:`columnVisibility` 提升进 ShellGraph(@Observable),ContentView binding 双向桥,body 读 tracked;菜单闭包写 graph |
| C2 | exportPanelRequest | 见 B17/B18 | 同上 |
| C3 | metadataFieldFocused | 见 B19 | 零改 |
| C4 | lightamerWorkspaceModel | 见 B20 | 零改 |

**D. 窗域(7 点)**
D1 window title 静态 ✓;**D2 toolbar 3 组 + `.windowToolbarStyle(.unified)`(:1798)→
hosting in-face 渲染 = 视觉差异族(缺口4,登记不修;OQ-F0P-2)**;D3 `.defaultSize` →
contentRect 初值 ✓;D4 `applicationShouldHandleReopen` 补一行;D5 `.fullScreen` styleMask
补一行;D6 terminateAfterLastWindowClosed ✓ spike 已带;D7 setFrameAutosaveName(OQ-F0P-8
key 定名)。

**E. sheet/overlay/alert/onChange/task 域(8 点)**
4 sheet(E1-E4)+ overlay(E5)+ alert(E6)→ Bindable graph tracked ✓(门③);E7
onChange(loadedImageURL!=nil)(:1761)body 注册 ✓;E8 wiring/welcome/edr 三 task ✓。
**全绿零缺口。**

**F. 动作时活读域(3 点)**:metadataTargets()/currentImageRelPaths() 读 selection/
loadedImageURL(:2345-2367)、pasteToSelection 链(:2576-2631)、菜单 Deps 闭包——
action 时刻读即真值,@Observable 读恒活,**无需跟踪,零缺口**。

**G. SwiftUI 自管域(4 点)**:toolbar 按钮态(body tracked)、ZoomHUD 读 viewportState
(EditorAreaView.swift:547-552,ZoomHUD 自己 body tracked——**这就是失效面只在菜单不在
HUD 的原因**)、inspector 挂载 binding(ContentView :790-803)、onGeometryChange ×4——
壳交接后全活。

### 3.3 真实缺口定盘(4)

1. **缺口1(A1)**:zoom/pan/rot 签名族——1 个修法点(构造参数化);影响面 = 菜单缩放两
   项(实际大小/适配屏幕)+ 任何未来「壳外写 viewportState」的命令。
2. **缺口2(B17)**:exportPresent note 时机——1 个修法点(onChange 化)。
3. **缺口3(C1+§1.2 #9/#10/#11)**:四项 stub 生产化 = columnVisibility 提升(1 点)+
   preset-manager/mcp-launcher/Settings 三窗控制器(3 窗,每窗 = NSWindow+HostingView+
   env 注入+菜单 action 接线,机械形同构)。
4. **缺口4(D2)**:窗级 toolbar 样式视觉差异——登记不修(OQ-F0P-2)。

### 3.4 规模数(M 批预算定盘锚)

- 审计点位:**~50**(A3+B20+C4+D7+E8+F3+G4);真实缺口修法点:**8**(缺口1 一点、缺口2
  一点、缺口3 四点[1 提升+3 窗]、缺口4 零点+登记)。
- churn 曾承担的额外负载(除菜单 enable 外)**未发现第二处**:E/F/G 三域全绿——spike
  冒烟 13 项全过与此审计互证。唯一功能缺口在 NSViewRepresentable push 族,与 F0PRIME
  §4.3「updateNSView 族为主嫌」预判一致。
- 生产化增量估算:三窗 ~150 行 + 菜单去桩/接线 ~100 行 + 缺口1/2 ~40 行 + delegate
  补行 ~10 行 + probe-stay hunk 3 行 ≈ **~300 行新写**(在 spike ~1750 行机械搬运之外)。

---

## 4. @State Migration Inventory（侦察 4:值型迁移清单)

App struct @State 全量 43 字段(LightamerApp.swift:260-437),分类:

| 类 | 数量 | 处置 |
|---|---|---|
| @Observable class-ref(供 env 链/闭包捕获) | 34 | controller `let`(spike 形 :2226-2260 全列已验) |
| 值型 @State | 6(libraryImportRequest/Choice、libraryWelcomePresented、pastePartialRequested、adjustmentTransferPresented、lastLaunchWasUnclean) | **ShellGraph**(spike 9 字段形 :159-170;@State 存储不跨 struct copy,树外写者必须类实例观察——F0PRIME §4.4) |
| per-session 重建 optional | 3(thumbnailProvider、batchSidecarWriter、catalogThumbnailRouter) | 同上 graph;body 重读点 = root face 读 box → ContentView 重建(已验) |
| let(装配期一次求值) | 1(legacyLibraryEnabled :437) | controller let |
| ContentView 本地 @State | 5(columnVisibility :143、exportPanelRequested :147、xmpImportPresented :151、xmpImportFailure :152、catalogEditReturnRoot :129) | **保留 @State**(view-tree resident,hosting 桥下存活);例外 = columnVisibility 提升进 graph(缺口3a 菜单写回) |
| DEBUG 探针 static armed 旗标 | 4(resize/import/sidecar/aiDeterminism probe) | 随探针函数迁移壳文件(static 语义不变) |

**结论:迁移清单 = spike graph 9 字段已一次到位,生产化零新增值型迁移**;唯一增量 =
columnVisibility 的提升(缺口3a)。

---

## 5. Test Compatibility Surface（侦察 5:测试兼容面)

### 5.1 规模

LightamerTestsApp(Project.swift 显式清单):**104 文件**(charter 口径 921 测试;源码
grep `func test*` ≈938 法,差额 = helper/命名口径,运行期 Executed 行为准)——UITests
bundle 另有 AppLaunchTests 1 文件。

### 5.2 直接依赖 App struct / Scene lifecycle 的点(全量 grep 实证)

| 点 | 内容 | 处置 |
|---|---|---|
| ProjectReadOnlyFaceTests.swift:499-506 | 调 `LightamerApp.batchPasteBlocked` static(:2639) | static 转移壳类型(或保留同名转发);1 文件微改 |
| AgentControlCoordinatorTests.swift:228-235 | source-content guard:grep `UI/LightamerApp.swift` 含 `|| agentControl.holdsControl)`(face ⑤ 行) | App struct Commands 退役后重指壳文件;manifest 1 行改 |
| SettingsPagesTests.swift:107-125 | DefaultKeymap × MenuCommandID pin | 数据级,零 diff 存活 |
| WorkspaceRoutingTests | MenuCommandSet 矩阵 | 纯函数,零 diff 存活 |
| McpProjectToolsetTests:427/:455 | 注释引用 App 装配形(自装 provider) | 零触 |

### 5.3 视图测试 harness 形

SheetEnvironmentInjectionTests(:66-97)/ ToastFaceTests(:38-142)/ ExportInspectorFaceTests
/ ExportCollisionPickerTests / NodeCanvasGeometryTests / ProjectReadOnlyFaceTests——挂载
形 = **NSWindow + NSHostingView + RunLoop.main.run(until:)** 自挂,**已经是 hosting 桥形**
(App struct 退役零影响;它们从不实例化 App/Scene)。

### 5.4 直启宿主行为(Scripts/test-direct.sh)

- HOST_BIN = app 二进制(:214),DYLD 注入 libXCTestBundleInject.dylib + XCTestBundlePath
  (:250-262)——**app main 照常跑**(现行 = SwiftUI lifecycle 在场),注入的 XCTest 在同
  进程驱动测试。
- 新 @main 下 = F0PrimeShellMain.run() 起手动 NSApplication + 主窗——run loop 同为
  NSApplication.run,注入机制与 lifecycle 无关;**预期等价,但 spike 从未以 B 二进制跑过
  测试宿主**→ P2 内置验证任务:新 @main 下跑单 bundle(建议 Library,体量中)对账
  Executed/failed 逐值,再放行全套。
- DEBUG fork 序(entry point 四把,:131-155)零触(§1.1)——McpHostTests/McpProjectArbitration
  跨进程 fixture 不受扰。
- AppLaunchTests(XCUITest 真机驱动):AX label 断言(three-column/empty state),hosting
  桥下 SwiftUI AX 出树不变(F0PRIME 门① AX 双证),结构性零改;走查轮复验。

### 5.5 ΔN 预估

- **新增测试 ~+15..+25 法**:NSMenuParityTests ~10(树镜像:gate 族可见性 × MenuCommandSet、
  enabler 谓词 × 状态对象真值、shortcut × DefaultKeymap、标题非裸键)、ShellGraphMigration
  ~4(菜单闭包写 → face body 可见;@State 值语义等价)、MenuBridgeObservationTests ~4(
  适配器对 16 字段逐字段触发 + re-arm 幂等 + stale backstop)、窗控制器 smoke ~2。
- **修改 2 文件**(§5.2 前两行);harness 重写 **0**;test-direct.sh 零改。
- 全套预期 = 3905 + ΔN(skip 35 零漂移口径,M7-3 基线)。

---

## 6. Regression & Walkthrough Plan（侦察 6)

### 6.1 D-6 新门(壳交接后的验收正门)

- **绝对门 <10% 复活为正门**:B 臂三轮 0.0%(F0PRIME §2)——编辑器静置 %cpu 中位 <10%
  (判据线留 10pp 余量对 0.0% 基线),配 L082 哨兵四门(frontmost/截图可见/主线程泊
  mach_msg2_trap/churn 符号族零)机检;驱动脚本从 `run-driver-f0prime.sh` 派生
  (`.work/gsd/phases/nsmenu-spike/run-driver-f0prime.sh` 正本)。
- 探针基建:**patch 0001(probe-stay hunk,DEBUG 3 行)随 P1 落 main**——无它则 D-6 门
  无 phase=editor 机检(HEAD 的 `-la_editor_probe` 加载完即 terminate,SPIKE §1.3)。

### 6.2 全 face 走查清单(壳交接 = 全 face 触达;MANIFEST 落 `.work/gui-acceptance/f0prime-prod/`)

1. 启动 + welcome sheet + New/Open/Recent Project(L057 面板缝)
2. Import Folder + ImportModeDialog + 进度 overlay/legacy 面
3. 图库网格:缩略图真渲染/EXIF 分组 inspector/filter/sort/smart albums/stacks
   expand-collapse(菜单 + 网格双入口)
4. 编辑器进出(⌘E/⌘W 两向)+ filmstrip/tool rail/adjustment stack/nodes canvas
5. 视口:解码渲染、zoom HUD 五钮/双击标签、捏合/旋转手势、**菜单 actual/fit 重绘
   (缺口1 修复验证)**、D-C3 bucket resize
6. Inspector:面板滑杆(exposure/temp)、export 页(⇧⌘E 菜单路由 + toolbar 双入口)、
   film 页、LUT 页、raw decode 面板(raster readout)
7. 标记菜单 15 项 + 文本框聚焦 disarm(缺口验证)+ ⌘0-6/bare 全 shortcut
8. undo/redo(菜单 + ⌘Z)、copy/paste adjustments、transfer 对话框、versions 面板
9. DRT 面板(method/preset/EOTF/peak)+ HDR 视口四态 + EDR toggle + soft proof(
   菜单 Toggle 态显示 = laState 验证点)
10. preset-manager / mcp-launcher / Settings 三窗(缺口3 修复验证;⌘, 挂点)
11. MCP:stdio 27 工具冒烟 + agent control 持锁期菜单禁用面(§2.3)
12. 导出队列:六格式至少 JPEG+HEIC+WebP 实跑 + 队列 UI
13. yiyin sheet + 拖拽
14. 退出链:willTerminate flush + clean sentinel 下轮 toast + ⌘Q
15. 多显示器/全屏进出/⌘M/Dock reopen(D4)
16. zh/en 双语菜单栏像素对照(门① 配方复用)

### 6.3 回归策略

- 全套 `--all`:**orchestrator 批准制 + 运行监视**(AGENTS 资源监控节;MEMFAIL 机检兜底);
  三轮同值口径(M7-3 先例)。
- 三臂探针留档:A(现行)/B(壳交接)/C(B+dispatch trace)二进制 + 日志按 spike §6 惯例
  归档本 phase 目录;B 臂 = D-6 门基线正本。
- 渲染对照:fixtures Poster 化像素与 F0' 留档一致(F0PRIME §3 渲染对照先例)。

---

## 7. Plan Split + ΔN（侦察 7)

| plan | 范围 | 验收 | 量级 |
|---|---|---|---|
| **P1 壳交接翻转** | probe-stay hunk;缺口1(zoom 构造参数化)/缺口2(exportPresent onChange)/缺口3a(columnVisibility 提升)——**先于翻转落地**(churn 在场时惰性生效,翻转即需);@main 切换 + ShellGraph/Controller/Delegate/NSMenuBridge 生产化(去桩 + Deps 全接线 + 三窗控制器 + reopen/fullscreen 两行);测试宿主等价性验证轮(§5.4) | 构建 + probe 全链 + D-6 绝对门 <10% 机检 + 走查面 1-9/14 冒烟级 | **M**(周内;~1750 机械搬运已验证 + ~300 行新写) |
| **P2 测试 + 回归 + 走查** | ΔN 测试(§5.5);AgentControl manifest 重指;全套 `--all`(批准制);16 面走查 MANIFEST(§6.2);三臂留档 + D-6 门定版 | TOTAL 3905+ΔN 三轮同值;MANIFEST 全绿;门① 像素/AX 复证 | **S-M** |
| **P3 退役 + 文档回填** | App struct Commands/Window/Settings 段死码退役(静 helpers/statics 迁壳);grep 机检(`.commands(`/`WindowGroup`/`Settings {` App target 零命中;`.runModal(` 门复跑);README 已知差异登记(toolbar 形态);FB 稿终章回填呈用户(OQ-F0P-10) | 机检零命中;走查抽样复证退役无回归 | **S** |

依赖序:P1 内部「审计修复先于翻转」是硬序;P2 依赖 P1;P3 依赖 P2(退役前必须全套绿)。
C 档门控:每 plan 闭环停等用户确认(AGENTS 暂停机制)。

---

## 8. Open Questions（侦察 8,带推荐)

| # | 问题 | 推荐 |
|---|---|---|
| OQ-F0P-1 | Settings 窗形态:私有 selector vs 真窗控制器 | **真窗控制器**(NSWindow+NSHostingView(SettingsView)+env 三件注入;⌘, 项直调;私有 selector 是 Apple 随时可拆的面) |
| OQ-F0P-2 | 窗级 toolbar:接受 in-face 差异 vs NSToolbar delegate 重造 | **接受 + 登记**(spike 已申报;churn 收益与 toolbar 形态无关;NSToolbar 后置立项候选) |
| OQ-F0P-3 | ⌘W 语义:library face 落点 | **跟随现行 IA**(editor face ⌘W→closeEditor 优先;library face 落点 plan 阶段实测现行 File 菜单 AX 后 1:1 对齐——不做语义创新) |
| OQ-F0P-4 | Dock reopen/fullscreen delegate 补行 | **补**(各一行;SwiftUI 默认行为对齐) |
| OQ-F0P-5 | QA 回切通道(LIGHTAMER_SHELL=legacy env 门,LibraryLegacyGate 先例)vs 无回切 | **无回切**(回退单元 = git revert/spike 分支;双壳并存使 churn 门失守——legacy 面在场则 96% churn 随时复活,门① 正门失义;QA 若需旧 face 用 release 分支) |
| OQ-F0P-6 | 多窗 keyWindow 语义(bridge workspace note) | **恒主窗单源**(v1 单编辑窗语义;窗菜单自动清单已给 AppKit;多窗聚焦判定后置) |
| OQ-F0P-7 | zoom 修法:构造参数化 vs body tracked read(`let _ = viewportState.zoom`) | **构造参数化**(观察纪律显式化、与 sourceTexture push-once 同构、机检形;tracked-read 形易在重构中丢失) |
| OQ-F0P-8 | 主窗 autosave key | **新 key `"LightamerMainWindow"`**(spike 的 F0PrimeShellMain 是实验名;与 SwiftUI 恢复无冲突——项目零 @SceneStorage 实证) |
| OQ-F0P-9 | AppDelegate 组合转发 vs 改 non-final 继承 | **组合转发**(生产 AppDelegate 文件字节零改——D-X 红线精神;spike 形已验) |
| OQ-F0P-10 | FB 稿终章提交时机 | **P3 收尾呈用户**(手动提交惯例;双重排除法 + churn 功能性发现价值见 APPLE-FB-D6-DRAFT 修订节) |

---

## 9. Anchors（锚点清单)

| 事实 | 锚点 |
|---|---|
| 双门 PASS 正本 | `.work/gsd/phases/nsmenu-spike/F0PRIME.md`(§1 设计/§2 数据/§3 冒烟/§4 机制/§5 校准) |
| spike 代码正本 | patch `0002`(F0PrimeShell.swift 2269 行 + NSMenuBridge.swift 671 行)+ `0001`(probe-stay)+ `0003`(trace);分支 `spike/f0prime-shell` |
| Scene/Commands 正本 | `App/Sources/Lightamer/UI/LightamerApp.swift`(:128 入口/:168 delegate/:252 App struct/:507 主窗/:1799 commands/:2212/:2224 次级窗/:2236 Settings) |
| 菜单 IA 纯函数 | `App/Sources/Lightamer/UI/Shell/MenuCommandSet.swift:78-85` |
| zoom 失效链 | `App/Sources/Lightamer/UI/EditorMTKView.swift:127-138` + `EditorAreaView.swift`(body :61-328 无 zoom tracked read) |
| focused-value 面 | ContentView.swift:249-250/:798、WorkspaceHostView.swift:195、InspectorView.swift:428 |
| 测试宿主 | `Scripts/test-direct.sh:214/:250-262` |
| 测试依赖点 | ProjectReadOnlyFaceTests.swift:499、AgentControlCoordinatorTests.swift:228-235 |
| D-6 门先例 | `.work/gui-acceptance/v2m/fix2-probe/`(sample/截图族)+ `phases/m7-1-shell/M7-1-HALT-REVIEW.md` |
| 直启协议 | F0PRIME §1.2(D-AR1-10 F-8 + L082)+ `run-one-f0prime.sh`/`run-driver-f0prime.sh` |

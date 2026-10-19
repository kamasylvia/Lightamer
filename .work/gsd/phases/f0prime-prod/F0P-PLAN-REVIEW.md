# F0P-PLAN-REVIEW — F0'-production 三 plan 独立 goal-backward 评审

> **结论头：PASS / 0 blocking + 4 major + 9 minor。**
> 评审对象 = `CONTEXT.md` + `F0P-01/02/03-PLAN.md`（HEAD `41e579da`）；上游 =
> `RESEARCH.md`（`9a0b9530`）+ `phases/nsmenu-spike/{SPIKE,F0PRIME}.md` + 分支
> `spike/f0prime-shell` 三 commits（`a35ad151`/`c9a91562`/`d8d1380a`，patch
> 0001..0003 亲读）。方法 = 只读 + 产线源码与 spike patch 逐 hunk 亲核 +
> 26 处 file:line 坐标抽查 + 测试面 grep 亲读；零源码触碰。
> **判定语义**：blocking = 计划结构缺陷不可执行；major = 按计划执行将产生
> 行为回归/规格矛盾/静默失效，须在指定门位修正后方可过门；minor = 文档
> 精确性缺口，随批勘正不阻塞。四条 major 全部可处方化，无需重排列结构。

---

## 一、逐清单结论（评审清单 1-9）

### 1. 翻转原子性与可 revert 性 — 结构成立（附 m4 措辞勘正）

- **内聚性 ✓**：T6 翻转 = 恰两产线文件（`LightamerApp.swift` entry 尾 +
  `LightamerShell.swift` 新建），SC 有 `git show --stat` 恰二文件机检
  （F0P-01 :339）。审计修复 T2/T3/T4 各自独立 commit 且执行序硬性先于 T6
  （F0P-01 :53-56 + red_lines :16），评审可分性成立。
- **revert 完整性 ✓**：T3/T4 的 inert 件（NSMenuBridge note 修饰符 /
  ShellGraph / 三窗控制器）在 revert 后保留于工作区，但激活路径唯一走
  `LightamerShell`（T6 删除）→ revert 后 entry 回 `LightamerApp.main()`，
  SwiftUI lifecycle 完整恢复，行为 = T5 态（churn 在场、缺口修复惰性生效
  零行为差）。`git revert --no-commit <flip-sha>` 干净应用机检在位
  （F0P-01 :354-355）。
- **fork 序零触 ✓**：entry 四把 fork（DEBUG flock ×2 → MCP headless → AI
  worker → GUI）亲核 `LightamerApp.swift:130-158`，T6 只动尾行；spike patch
  0002 entry hunk（@@ -153,7）同形佐证。
- **夹带检查**：T6 实际还含 `WindowCapture` private→internal（patch 0002
  @@ -214,7；LightamerShellFace 引用所需）——同文件非 App struct 域，不破
  内聚，但 T6「本任务只动 entry 尾行」（F0P-01 :350）措辞不准且 SC 未显式
  列该 diff 行 → **m4**。
- **回退半态防护 ✓**：T3/T4 冻结至 P2（F0P-01 :432）+ T7 收口复跑 revert
  面核。
- **一个语义勘正（m7）**：T7 回退节「T2/T3/T4 逐任务 revert 二分」
  （F0P-01 :407）在 T6 之后不可行——revert T3（NSMenuBridge）会破
  LightamerShell 编译。二分应为「重建历史任务边界 commit 形二进制」（spike
  A/B 独立 DerivedData 先例），非 HEAD 上逐个 revert。

### 2. NSMenu 全族 parity 完备性 — 树面 23 项抽查全对齐；规格面两条 major

**抽查 ≥10 项（产线 commands ↔ patch 0002 桥树逐项对读）**：

| 项 | 产线 | spike 桥 | 判定 |
|---|---|---|---|
| menu_new_session ⇧⌘N | 恒 disabled + sessionNew gate（:1802-1806） | `laEnabled { false }` + visible.contains(.sessionNew) | ✓ |
| menu_open ⌘O | ungated（:1812） | ungated item | ✓ |
| menu_open_session ⇧⌘O | **FileOpener.openSessionFolder picker**（:1825-1832） | **`recentSessions.first` 直开**（patch buildFileMenu） | **✗ M4** |
| menu_enter_editor ⌘E | phase==.library + AX id（:1921-1927） | enabler `workspace?.phase == .library` | ✓（AX 缺 → m5） |
| menu_back_to_library ⌘W | phase==.editor（:1928-1934） | enabler phase==.editor | ✓ |
| menu_save_sidecar ⌘S | 恒 disabled（:1950-1952） | `laEnabled { false }` | ✓ |
| menu_export ⇧⌘E | exportPanelRequested != nil（:1958-1962） | note-box 读（生产形 = B18 直读，T3 已裁） | ✓（m6） |
| menu_undo/redo ⌘Z/⇧⌘Z | canUndo ∧ !isReadOnly ∧ **holdsControl**（:1975-1989） | 同三元合取（patch buildEditMenu） | ✓ |
| menu_paste_adjustments ⇧⌘V | **hasPayload ∨ isReadOnly——无 holdsControl**（:2001/:2007） | hasPayload ∧ !isReadOnly——无 holdsControl | ✓（但 P2 规格 ✗ → M3） |
| Import Folder ⇧⌘I | projectStore != nil（:1900-1904） | 同 | ✓ |
| menu_show_sidebar/inspector ⌥⌘S/⌥⌘I | ungated（:2036/:2038） | ungated item | ✓ |
| softproof_toggle ⌥⌘P | Toggle isActive（:2057-2061） | laState isActive + action toggle | ✓ |
| softproof_gamut_check | disabled !isActive（:2062） | enabler isActive | ✓ |
| actual_size/fit_to_screen Z/F | ungated bare（:2072/:2076） | `key, mask: []` ungated | ✓ |
| stacks expand/collapse | ungated 无 shortcut + AX id（:2087-2094） | ungated 无 key | ✓（AX 缺 → m5） |
| tool_rail/scopes/adj_stack | viewToolRail gate + state（:2100-2108） | visible.contains(.viewToolRail) + laState | ✓ |
| 标记全族 | metadataTextEntryActive 全族禁用（:2119-2164，**实数 16 项**） | bare() enabler metadataFieldFocusedState==false | ✓（计数 → m2） |
| Image AI ×2 | phase==.editor ∧ currentImageID!=nil + AX marker（:2172-2195） | 同谓词 aiEnabled | ✓（AX 缺 → m5） |
| Help ⌘? | disabled（:2201-2203） | `laEnabled { false }` + NSApp.helpMenu | ✓ |
| App 菜单 7 项 | About/Settings/Services/Hide/HideOthers/ShowAll/Quit | buildAppMenu 同形（Settings = 私有 selector 冒烟形 → D-F0P-1 生产替换在 T4/T6） | ✓ |
| 窗口菜单 3+自动 | ⌘M/Zoom/Bring All | 同形 + NSApp.windowsMenu（patch buildWindowMenu） | ✓ |
| 动态子菜单 ×2 | recentSessions/recentProjects 空→disabled | rebuildRecentSubmenus + holder isEnabled | ✓ |
| 文本族 Cut/Copy/Paste/SelectAll | 系统默认 | NSText selector target=nil（patch buildEditMenu 尾） | ✓ |

- **disable-not-unmount 的 NSMenu 等价 ✓（码实证）**：enabler 读
  `agentControl.holdsControl`（undo/redo/New/Open Project/Open Recent
  holder+rows）+ 观察适配器 tracked 读集含 holdsControl（patch armObservation
  `deps.agentControl.holdsControl`）+ handleMenu stale-enablement backstop
  （patch handleMenu 首段）+ menuNeedsUpdate→refreshAll。SwiftUI 侧 10 处
  `.disabled(...holdsControl)` manifest 亲读证实恰 10 行
  （AgentControlCoordinatorTests.swift:230-249，face ⑤ = :233-236）。
- **MenuCommandID 热路径 ✓**：桥消费 `MenuCommandSet.visibleCommandIDs
  (gate:phase:)`（patch visibleCommands；phase: .library 安全——
  MenuCommandSet.swift:75-77 自注 phase-independent）。gate 常量
  legacyLibraryEnabled let 单源 ✓。
- **两条 major**：M3（P2 T1 paste 规格错误，见 §三）、M4（⇧⌘O 语义偏差，
  见 §三）。

### 3. 四 stub 生产化设计 — 三窗控制器形成立；两处设计缺口

- **与 HEAD scene 形对齐 ✓**：三窗 env 注入面亲核
  （`LightamerApp.swift:2212-2218` PresetManager presetsStore/presetController
  + dark + 520×480；:2224-2227 McpLauncher 720×480；:2236-2244 Settings
  SettingsView(legacyLibraryEnabled:) + catalogPreferences/pipeCoordinator/
  libraryProjects 三件 + dark）——T4 SC「逐项对齐」可对账。注入缺件运行时崩
  风险已登记（F0P-01 :424-425 风险节 + P2 走查面 10 专项）。
- **L057 相容 ✓**：三控制器是普通 NSWindow + showWindow 缝，无 panel/modal
  面；`.runModal(` 零命中机检在 P1 T3/P2/P3 三处复跑。
- **无重复呈现路径 ✓**：翻转后 App struct 不可达（Settings/preset/mcp 三
  scene 死码），P3 才退役——单呈现路径窗口期成立。
- **缺口 M1**：`ContentView.swift:551` toolbar preset-manager 按钮走
  `openWindow(id:)`（亲核 :551 + @Environment :140）——翻转后 SwiftUI scene
  registry 不在场，openWindow 静默 no-op，用户可见入口死亡。RESEARCH §1.2
  #12 明列「openWindow 3 调用点（App :2024/:2029; ContentView :551）→ 窗控
  制器 showWindow 缝」，但三 plan 无任何任务承接 :551（T3/T4 的 ContentView
  改动 = export note + columnVisibility，均不触及）；P2 走查面 10 写
  「⌘, 挂点」——toolbar 腿大概率不被走查。见 §三 M1。
- **缺口 M2**：ShellGraph 实例单源机制未指定。T4 把 ContentView :143
  `@State columnVisibility` 提升为 graph-backed binding，但 pre-flip 下
  ContentView 拿哪个 graph 实例、T6 face 装配段持有的 graph 与之是否同一
  实例，三 plan 均未写明。双实例静默失效模式真实存在（菜单写 face 实例 /
  ContentView 读自己的实例 → ⌥⌥⌘S/⌥⌘I 视觉恒死）；P2 T2 测试若两侧注入同
  一实例则测不出产线接线变异。见 §三 M2。

### 4. 审计修复四缺口 — T2/T3 设计等价性成立（附 m6/m8）

- **T2 zoom 构造参数化 ✓**：现形亲核 `EditorMTKView.swift:127-138`（签名
  push-once 比对臂 + updateNSView 内直读三字段——非追踪上下文）+
  `EditorAreaView.swift:61-328`（body 对 zoom 族零 tracked read，
  displayTexture 读在 :419）。构造参数化后：body tracked read 显式化、
  updateNSView 改读构造参数、比对臂原样保留 = push-once 语义零改；手势路径
  （coordinator 自持 view 引用）与 ZoomHUD（:547-552 自 body tracked）零触
  ——与 F0PRIME §4.3 失效链解剖一致。**D-H1 提交语义 ✓**：viewportState 是
  视口活态非 adjustment params，不入 D-H1 discrete-commit 域，参数化不改任
  何提交路径；视口坐标系纪律（D-C3 bucket / top-first）无触碰面。机检 grep
  在位（updateNSView 内三字段零命中）；唯一缺 = tracked-read 禁形
  （`let _ = viewportState.zoom`）无 grep 门 → **m8**。
- **T3 B17-B20 等价性 ✓**：spike onAppear 一次性形亲读 patch（ContentView
  @@ -248,6 `noteExportPanelRequestPresent(true)`）确为时机缺陷；生产
  onChange 双态 + enabler 直读 exportPageActive 严格更优。B19 onChange /
  B20 onAppear spike 形逐字落位 = 已验形零改。单窗形 D-F0P-6 一致。
  **m6**：生产形 enabler 读 `inspectorState.exportPageActive` 需要
  `Deps` 增 `inspectorState` 字段（spike Deps 七对象 + 闭包，无
  inspectorState——亲读 patch Deps struct），T3 改形点未枚举；适配器读集
  是否同步换 track exportPageActive（vs 保留 note-box 读）待定形——P2 T3
  字段清单基数受影响（与 m1 同根）。
- **T5 toolbar 登记 / T4 columnVisibility**：见 §一.3（M2）。

### 5. 测试面与 ΔN — 算术闭合 ✓；「2 文件」亲读证实 ✓；规格一条 major

- **ΔN 算术 ✓**：P2 四族 8..12 + 3..4 + 3..4 + 1..3 = 15..23（F0P-02
  ΔN 预算表逐行加总核对）；P1 +0..2 + P2 +15..23 + P3 +0 = 全批
  +15..+25；3969 → 3984..3994 闭合。P2 标题 ~10/~4/~4/~2 = 带中值一致。
- **「直接依赖 App struct 仅 2 文件」亲读证实 ✓**：全 Tests 目录 grep
  `LightamerApp\b` = 10 文件命中，其中 8 文件全部为**注释/路径字符串**
  （ImportCompletionRegressionTests:32 / McpProjectToolsetTests:427,:455 /
  MertensMergeUITests:75,:108 / PanoMergeUITests:79,:114 /
  SettingsPagesTests:113 / StackAggregateTests:463 /
  StackMergeServiceTests:387 / WorkspaceRoutingTests:260——逐文件亲读）；
  代码级依赖恰两处：`ProjectReadOnlyFaceTests.swift:499-512`
  （batchPasteBlocked ×4 + readOnlyPasteToast ×2）+
  `AgentControlCoordinatorTests.swift:228`（face ⑤ source-guard token）。
  RESEARCH §5.2 准确。
- **P2 T5 直启宿主等价性门 ✓**：单变量设计成立——翻转前 = T1 形二进制
  （= audit-repair 3969 基线 + probe hunk，行为零差），翻转后 = T6 形，
  唯一 delta = 壳交接；Library bundle 中等体量 + 全套 --all 兜底 + MCP 跨
  进程族归 T6（Library 不含，明注不冒充覆盖）。等价 FAIL = 停手上报禁带病
  跑全套（F0P-02 red_lines :19）。
- **规格 major**：P2 T1 paste 族 enabler 规格错误（M3，见 §三）。

### 6. D-6 绝对门 — 验收程序写全 ✓（附 m3）

- **<10% 判据 ✓**：生产翻转二进制三轮、30s 窗 6 采样 @6s 中位 <10%
  （F0P-01 :381-382）；判据线留 10pp 余量对 F0PRIME B 臂 0.0% 基线的依据
  在 CONTEXT 特别登记二；10-30% 未达标 = 停手归因禁放行（:385-386）。
- **L082 四哨兵 ✓**：①frontmost=true 3/3；②窗内截图可见；③sample 栈主
  线程泊 `mach_msg2_trap`；④churn 符号族（UpdateStack/sizeThatFits/
  beginTransaction）三轮全零——四门全部机检化，哨兵 fail = 读数无效重采
  （F0P-01 :409-410）。phase=editor 机检 = probe stderr 标记
  （`rendered=yes` + `staying alive`，T1 的 probe-stay hunk 供 stay 标记）
  ——T1 落位与 T7 消费闭环 ✓。
- **门位安排 ✓**：P1 T7 = 翻转后正门（A/B 两臂留档起卷）；P2 T7 = 定版
  （+复测一轮 + 相对门对照 vs A 臂 96.0 双证）。**m3**：CONTEXT 特别登记二
  写「P1 T7 + P2 **T8**」——P2 无 T8（其 D-6 定版 = T7），任务号 stale。

### 7. 坐标抽查 — 26 处亲核，全部吻合（±2 行内）

| # | 坐标 | 亲核结果 |
|---|---|---|
| 1 | LightamerApp.swift:128-158 entry fork 序 | ✓（`LightamerApp.main()` :158；四把 fork 序逐字） |
| 2 | :168-201 AppDelegate / :190-201 willTerminate Notification | ✓（:169 final class；参数类型注释 load-bearing 在位） |
| 3 | :252 App struct | ✓ |
| 4 | :437 legacyLibraryEnabled let | ✓ |
| 5 | :493 metadataTextEntryActive = metadataFieldFocused == true | ✓（桥等价性依据） |
| 6 | :507 Window("Lightamer", id:"main") | ✓ |
| 7 | :1797-1799 defaultSize/toolbarStyle/.commands 起点 | ✓ |
| 8 | :2024/:2029 openWindow 双点 | ✓ |
| 9 | :2212-2244 三窗 scene + env 注入 | ✓ |
| 10 | :2639 batchPasteBlocked static | ✓ |
| 11 | :2692-2702 toggleSidebar/toggleInspector | ✓（.all↔.doubleColumn / .all↔.detailOnly） |
| 12 | ContentView.swift:143 columnVisibility @State | ✓ |
| 13 | ContentView.swift:249-250 focusedSceneValue 双 publish | ✓ |
| 14 | ContentView.swift:551 openWindow preset-manager | ✓（M1 证据） |
| 15 | ContentView.swift:796-800 exportPanelRequest page 腿 | ✓（get exportPageActive / set openExportPage） |
| 16 | EditorMTKView.swift:127-138 签名 push | ✓（:130-138，±3 行内） |
| 17 | EditorAreaView.swift:61 body | ✓ |
| 18 | :274-277 onChange(geo.size) | ✓ |
| 19 | :419 displayTexture 读 | ✓ |
| 20 | :547-552 ZoomHUD label 读 viewportState | ✓ |
| 21 | MenuCommandSet.swift:78-85 纯函数 | ✓ |
| 22 | WorkspaceHostView.swift:195 focusedSceneValue | ✓ |
| 23 | InspectorView.swift:428-432 metadataFieldFocused publish | ✓ |
| 24 | ProjectReadOnlyFaceTests.swift:499-506 | ✓（亲读） |
| 25 | AgentControlCoordinatorTests.swift:228-235 | ✓（face ⑤ :233-236，manifest 10 行） |
| 26 | Scripts/test-direct.sh:214/:250-262 | ✓（HOST_BIN / DYLD 注入） |
| 附 | patch 0001 hunk :1827 落点 | ✓（`film page final` 臂后 +10 行 = 7 注释 + 3 代码） |
| 附 | patch 0002 六文件形 | ✓（stat + 逐 hunk：view 三 note + entry + WindowCapture + 两新文件） |
| 附 | 四 stub 现形 / Settings selector | ✓（`presetManager: { }` 等 + `Selector(("showSettingsWindow:"))`） |

### 8. 红线与转写勘误 — 15 条逐条落位 ✓；勘误①有据 ✓；勘误②自洽 ✓

- **15 条红线落位**：①FIX2③（P1 T3/T6 SC + P2/P3 红线）②封存面（三 plan
  红线 + P1 T6 SC）③无回切（D-F0P-5 + P1 checker env 门零命中）④翻转独立
  revert（T6 机检）⑤xcstrings 零 diff 预期（P1 T3 禁形 grep + P3 T2 ⑥）
  ⑥LocalizationValue 禁形（P1 T3 + P3 T2 ③）⑦disable-not-unmount（§一.2
  码实证 + face ⑤ P3 才重指）⑧基线 3969/37/0（三 plan baseline 行 + skip
  37 = 35 + 探针 2 口径）⑨AppDelegate.swift 字节零改（P1 T6 SC + P3 保留
  段）⑩fork 序零触（T6 面核 + P2 T5 旁证 + P3 保留段）⑪L057（三 plan
  `.runModal(` 复跑）⑫UserDefaults 应用级零新键（系统 `NSWindow Frame *`
  豁免明注）⑬--all 批准制（P2 T6 + parentage + 8G + MEMFAIL）⑭C 档（三
  plan 停位）⑮LightamerShell* 改名（T6 `F0PrimeShell` 零命中机检 + P3 复
  跑）。**全 15 条无一悬空。**
- **勘误①（3905→3969）有据 ✓**：`STATE.md` M8 段明载「审计修复批 closed
  2026-10-19 收口 `9898a0fb`——终态全套 3969/37/0」；M7-3 时代 3905/35/0
  与 M7-4 3925 的演化链与勘误叙述一致。RESEARCH §5.5/§7 的 3905 确为漏更。
- **勘误②自洽 ✓**：P2「产线零 diff」声明可执行——P2 files_modified = 四
  测试文件 + Project.swift + BUNDLE-MAP + 三 docs，无 App/Sources；manifest
  face ⑤ 重指 + batchPasteBlocked 转移落 P3 T1 同 commit 原子（P3 red_lines
  重指原子性 + SC `git show --stat` 恰五文件）。「双源窗口」理由成立
  （P2 全套轮时 source-guard 仍绿）。
- **OQ-F0P-1..10 采纳一致性 ✓**：D1 Settings 真窗（T4 SC `showSettingsWindow:`
  零命中 + T6 SC）/ D2 toolbar 登记（T5）/ D3 ⌘W 1:1（T6.5 实测记录——桥
  结构上 editor face ⌘W = back_to_library 拦截、library face = disabled 项
  消费事件 = 现行 IA 逐点平移，推断成立）/ D4 reopen+fullScreen（T6 SC 恰
  一处 ×2）/ D5 无回切 / D6 恒主窗（B20 单窗形）/ D7 构造参数化（T2；
  禁形 grep 缺 → m8）/ D8 autosave key（T6 SC 恰一处；spike
  `LightamerF0PrimeMain` → 生产 `LightamerMainWindow` 改名在案）/ D9 组合
  转发（T6 SC Notification 转发恰一处）/ D10 FB P3 收尾（P3 T3）。**全
  10 项与任务一一对应。**

### 9. C 档停位 ✓

三 plan 停位编排一致：P1 T7.6 / P2 T7.6 / P3 T5.4 各自「执行+验收闭环后停
汇报，等用户确认再放行下一 plan」；前置依赖序（P2 依赖 P1 闭环、P3 依赖
P2 三轮同值绿 + 16 面走查全绿）与 RESEARCH §7 依赖序一致；三 plan 的
Checker 关注点节（goal-backward / OQ 兑现 / 硬序 / 红线 / SC 可机检性）为
双路验收提供独立反向核输入。`--all` 批准制 + 运行监视 + 8G + MEMFAIL 链条
与 AGENTS 资源监控节逐条对齐。

---

## 二、Major 清单（4，全部须在指定门位修正）

### M1 — ContentView :551 toolbar openWindow 调用点无任务承接（翻转后静默失效）

- **severity**：major（用户可见入口回归；走查大概率不覆盖 → 直达交付）。
- **证据**：`App/Sources/Lightamer/UI/ContentView.swift:551`
  （`openWindow(id: "preset-manager")` + :140 @Environment + :552 AX id
  `toolbar.preset_manager`）；RESEARCH §1.2 #12 明列「openWindow 3 调用点
  （App :2024/:2029; ContentView :551）→ 窗控制器 showWindow 缝」；三 plan
  files_modified 与任务序零承接（P1 T3/T4 的 ContentView 改动 = export
  note/columnVisibility；P2 走查面 10 只写「⌘, 挂点」；P3 只摘 :249-250）。
  翻转后无 scene registry，openWindow = no-op。
- **处方**：T6 翻转 commit 内增一步「ContentView :551 → 窗控制器缝接线」
  （graph 请求字段 + face/shell 侧观察消费，或 ContentView 闭包参数——与
  M2 终形联动二选一）；`verbatim 搬运`偏差照例 DECISIONS 申报。SC 增机检：
  翻转后 `openWindow` 在 ContentView 零命中；P2 走查面 10 增补 toolbar 入
  口腿（`toolbar.preset_manager` 点击 → 窗出现）。

### M2 — ShellGraph 实例单源机制未指定（T4 pre-flip 与 T6 face 装配的同一性）

- **severity**：major（双实例静默失效模式：菜单 ⌥⌘S/⌥⌘I 写 A 实例、
  ContentView 读 B 实例 → 列可见性切换视觉恒死；P2 T2 测试若两侧注入同
  实例则测不出产线接线变异）。
- **证据**：F0P-01 T4 action 2「:143 @State 改 graph-backed binding」未写
  实例来源；T6 action 4「face 装配段持 graph」未写与 ContentView 实例的
  收敛机制。spike 无此问题（stub——列可见性根本没接，F0PRIME §1.1）；即
  生产形是全新接线，无 spike 先例可逐字搬运。pre-flip 约束：App struct
  scene builder（P1 冻结至 P3）不可改 → graph 只能在 ContentView 内部或
  全局单例；post-flip 约束：face 装配段闭包须写到同一实例。
- **处方**：T4 开工前在 DECISIONS 定死单源形，三候选：(a) `ShellGraph.shared`
  单例（LutLibraryStore.shared 先例，M2-5 检查器 m6 形）——跨翻转边界零
  seam 改动，最小 diff；(b) env 注入 + optional 回落本地 @State
  （`@Environment(ShellGraph.self)` nil → fallback——pre-flip nil 合法）；
  (c) ContentView 新 init 参数 + face 传（须处理 pre-flip 调用点缺参）。
  P2 T2 增一条「菜单闭包与 ContentView 读同一实例」断言（共享实例身份
  断言，非仅写读桥）。

### M3 — P2 T1 paste 族 enabler 规格错误（holdsControl 三元合取 ≠ 产线/spike 二元）

- **severity**：major（按规格写测试必红，或逼出越界桥改形 = parity 违约；
  RESEARCH 枚举错误传导）。
- **证据**：产线 paste enabler 无 holdsControl——`LightamerApp.swift:2001/
  :2007`（`.disabled(!pasteboard.hasPayload || libraryProjects.isReadOnly)`）；
  spike 桥同（patch buildEditMenu：`hasPayload && !isReadOnly`）；face ⑤
  manifest 只盖 undo/redo + project commands
  （AgentControlCoordinatorTests:234 why 行）。但 F0P-02 T1 action 2 写
  「paste 族（hasPayload × isReadOnly × holdsControl）」；RESEARCH §2.3
  「New/Open Project、Open Recent、undo/redo、**paste 族** 7 项受
  holdsControl 合取(spike 已形)」——枚举错误（holdsControl 合取族实为
  undo/redo/New/Open/Open Recent holder+rows；「7」凑数把 paste 族错算入）。
- **处方**：P2 T1 enabler 规格勘正为「paste 族 = hasPayload × isReadOnly
  （无 holdsControl）；holdsControl 合取族 = undo/redo/New/Open/Open
  Recent」；RESEARCH §2.3 行随批勘误登记（CONTEXT §转写勘误追加一条或
  P2 DECISIONS 申报）。若晨审欲**改**语义（paste 也受 agent 禁编辑）=
  UI 行为变更超壳交接范围，须走用户裁决面，不属 plan 内自裁。

### M4 — spike 桥 menu_open_session（⇧⌘O）动作语义偏差：recentSessions.first ≠ 产线 picker

- **severity**：major（gate=true legacy 通道行为回归——按 D-F0P-3「壳侧唯
  一义务是 parity」属缺陷；T3 生产化修正清单未含 → 若 T3 逐字落 patch 即
  带病入产；机检面无覆盖）。
- **证据**：产线 `LightamerApp.swift:1825-1832`（menu_open_session →
  `FileOpener.openSessionFolder` picker → openSession）；spike patch
  buildFileMenu（menu_open_session action =
  `deps?.sessionState.recentSessions.first` → `deps?.openSession(url)`——
  无 picker，直开最近会话）；F0P-01 T3 改形点仅列 note 注入三处，未列此
  动作体；P2 树镜像测项集/谓词/shortcut，不测动作体语义；16 面走查无
  session-mode 菜单动作腿。
- **处方**：F0P-01 T3 生产化修正清单增列「menu_open_session 动作体 =
  FileOpener.openSessionFolder picker 缝（L057 Task hop 形）」（Deps 闭包
  openSession 形不变，桥侧 action 改调 picker 闭包——新增一个
  `openSessionPicker: () -> Void` 类闭包或复用 openSession 零参变体，终形
  落 DECISIONS）；机检增 `recentSessions.first` 在 NSMenuBridge 零命中。
  若晨审裁定 gate=true legacy face 接受降级（session 路由死码化先例
  menu_new_session/menu_close_session 恒 disabled），则改登记为已知差异
  ——须用户裁决，禁静默。

---

## 三、Minor 清单（9）

| # | 内容 | 证据 | 处方 |
|---|---|---|---|
| m1 | 观察适配器读集实数 **18** 读 ≠ 全文档「16 字段」（armObservation 逐行数：canUndo/canRedo/loadedImageURL/hasPayload/isReadOnly/projectStore/recentProjects/holdsControl/isActive/gamutCheck/recentSessions/phase/currentImageID/toolRailVisible/scopesVisible/adjustmentStackVisible/metadataFieldFocusedState/exportPanelRequestPresent） | patch armObservation 全文亲读；RESEARCH §3.2-B / CONTEXT 红线 7 / F0P-01 T3 SC / F0P-02 T3 | 「16 字段」→「18 读集」或改称「全读集」；P2 T3 逐字段测试以最终适配器源为基数（与 m6 定形联动） |
| m2 | 标记菜单实数 **16** 项（rating clear+1-5 = 6 / flag ×3 / color clear+0-5 = 7）≠ RESEARCH/PROMPT「标记15」 | LightamerApp.swift:2119-2164 逐项数；patch buildMetadataMenu 同 16 | RESEARCH §2.1 计数勘正；P2 树镜像以实数为准（16 + separator） |
| m3 | CONTEXT 特别登记二「P1 T7 + P2 **T8**」任务号 stale——P2 的 D-6 定版 = T7 | CONTEXT :27 vs F0P-02 任务表 T1-T7 | CONTEXT 该处改「P2 T7」；或 P2 DECISIONS 注记 |
| m4 | T6 实际含 WindowCapture private→internal（LightamerShellFace 引用所需），「只动 entry 尾行」措辞不准、SC 未列该 diff 行 | patch 0002 @@ -214,7；F0P-01 :350/:339 | T6 SC 增「WindowCapture 可见性翻转恰一处」机检行；措辞改「entry 尾 + WindowCapture 可见性」 |
| m5 | 菜单 AX identifier 族未随桥迁移：menu.workspace.enterEditor/backToLibrary（:1927/:1935）、menu.library.search（:1945）、menu.edit.copyAdjustments（:2018）、menu.view.stacks.expandAll/collapseAll（:2096 附近）、menu.image.aiUpscale/Denoise（:2183/:2195）——NSMenuBridge `item()` 不设 accessibilityIdentifier | 产线 AX id 亲读 vs patch item() helper | T6 接线时按 AIEntryPointCoordinator.Marker / 既有字符串给 NSMenuItem 补 accessibilityIdentifier（NSMenuItem 支持该属性）； Marker 常量引用恢复「drift 不能编译」方法论；不补则 P2 DECISIONS 申报 AX 面已知差异 |
| m6 | B18 生产形（enabler 直读 `inspectorState.exportPageActive`）要求 `Deps` +inspectorState 字段——spike Deps 七对象无此字段；适配器读集是否同步换 track exportPageActive 未定形 | patch Deps struct 亲读；F0P-01 T3 action 2 | T3 改形点增列 Deps 扩展 + 适配器读集终形（track exportPageActive 替换 note-box 读，或双轨）；与 m1 基数联动 |
| m7 | T7 归因「T2/T3/T4 逐任务 revert 二分」在 T6 后不可行（revert T3 破 LightamerShell 编译） | F0P-01 :407 | 措辞改「重建任务边界 commit 形二进制（worktree + 独立 DerivedData，spike A/B 先例）」 |
| m8 | D-F0P-7 tracked-read 禁形（`let _ = viewportState.zoom`）无机检 grep——T2 SC 只查 updateNSView 内三字段零命中，拦不住 body 内禁形 | F0P-01 T2 SC :160-162 | T2 SC 增 `grep "let _ = viewportState" App/Sources` 零命中 |
| m9 | P2 T5 翻转前基线二进制（P1 T1 commit 形）的构建方式未写明（现 HEAD ≠ T1 形，须 worktree checkout + 独立 DerivedData） | F0P-02 T5 :183-185 | T5 action 补构建配方行（spike §1 独立 DerivedData 先例引用） |

---

## 四、判定

- **结构面 PASS**：三 plan 切分（审计修复先于翻转 / 测试+回归 / 退役+回
  填）、硬序、原子 commit 边界、C 档停位、机检密度（grep/git stat/探针数
  值级 SC）齐备；坐标转写质量高（26 处亲核 ±2 行内）；15 红线无一悬空；
  勘误两条处理自洽。
- **4 major 均可处方化、不动排列结构**：M1/M2 落点 = P1 T4/T6（执行前修
  正）；M3 落点 = P2 T1 规格（P1 闭环停期间即可勘正）；M4 落点 = P1 T3 改
  形点清单（T3 开工前增列）。建议按 C 档停节奏在 P1 起跑前将 M1-M4 处方
  回写 plan（或以本评审为附件、执行时按处方行使并 DECISIONS 申报）。
- **9 minor 随批勘正**，不阻塞起跑。

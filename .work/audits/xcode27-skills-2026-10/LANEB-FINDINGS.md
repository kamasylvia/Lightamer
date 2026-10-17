# Xcode 27 官方 Skills 对照审计 — B 路（判断级深读抽样）

日期：2026-10-13
范围：`App/Sources/Lightamer/`（196 文件 / 70994 行 SwiftUI）+ 相关 Core 面（ModuleInstance / FilmRecord / DrtRecord / LibraryQueries）
审计方式：纯只读；零代码改动、零 commit。
约定优先级：AGENTS.md 既有架构约定（KD-4 注入式 defaults、app-root sheet 禁裸 @Environment、`String.LocalizationValue("prefix_\(x)")` 禁形、D-H1 提交语义、M2-6 DRT 视口终式等）**优先于 skill 泛则**；冲突处记 obs 不记 violation。

## 结论

**PASS / 0 error + 5 major + 11 minor + 9 obs**

无编译性/行为性 error。5 条 major 全部是失效边界与每帧重算类性能形态问题（其中 3 条 `d6-relevant`，直接关联 macOS 27 AttributeGraph churn 缺陷 D-6 的风险面）；软弃用 API 存量小（17 处，全部 minor 级信息项）；本仓对 skill 的**合规面**显著优于典型 SwiftUI 仓（`@Observable` 全覆盖、ForEach identity 全稳定、无条件修饰符零、单子 Group 零、`.task` 缩略图加载规范）。

**d6-relevant 条数：4**（M1 / M4 / M5 / o6）。

---

## 深读覆盖面声明

**指导材料（先读，全部读完）**：
- `.work/xcode27-skills/swiftui-specialist/references/`：structure.md / dataflow.md / environment.md / foreach.md / animations.md / localization.md / modifiers.md / soft-deprecation.md / soft-deprecated-apis.md（全套清单）
- `.work/xcode27-skills/swiftui-whats-new-27/references/`：state-macro.md / content-builder.md

**深读文件（按序）**：
1. 面板族：`UI/Shell/FilmPanelView.swift`（全文 594 行）→ `UI/Shell/FilmPanelModel.swift`（全文 749 行）→ `UI/Shell/DrtPanelView.swift`（全文 313 行）→ `UI/Shell/DrtPanelModel.swift`（前 160 行）→ `UI/Inspector/LightamerSlider.swift`（全文）→ `UI/Inspector/IOPPanelProvider.swift`（全文）→ `UI/Inspector/LutPanelView.swift`（前 160 行）→ `UI/Inspector/ChannelMixerRGBPanelView.swift`（前 140 行，39 面板同构代表）
2. 图库族：`Library/Views/LibraryGridView.swift`（全文 401 行）→ `Library/LibraryGridModel.swift`（全文 560 行）→ `UI/Shell/FilmstripView.swift`（全文 296 行）→ `UI/SessionBrowserView.swift`（头 120 行 + cell 段）→ `Session/SessionBrowserModel.swift`（Row 定义）→ `LightamerCore/Sources/Library/LibraryQueries.swift`（LibraryImageRow 定义）
3. 宿主族：`UI/Shell/WorkspaceHostView.swift`（body 130-429 + 结构 outline）→ `UI/ContentView.swift`（outline + sheet 段）→ `UI/Shell/EditorAdjustmentStackView.swift`（全文 497 行）→ `UI/Shell/EditorTabRoute.swift`（descriptor/routing 表 115-304）
4. 全仓机扫：onAppear 全部 39 处提及（27 处真实 call site）、软弃用 API 九族 grep、`AnyView` / 条件修饰符 / `Group {` / `.onChange` 形态 / `@State` 隐私 / ObservableObject 残留 / xcstrings 目录结构（1957 键）。

**抽样判断（B 路口径）**：深读逐行判断 + 机扫定位后抽样复核；48 个 iop 面板以 ChannelMixerRGB + 39 文件 `params` 同构 grep 代言。

---

## Findings

### error（0 条）

无。

### major（5 条）

**M1. WorkspaceHostView 宿主 body 失效放大：onChange/toast/banner 依赖读全部落在 1684 行宿主上** — `d6-relevant`
- 位置：`App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift:130-429`（body），关键点 `:166-169`（`ProjectReadOnlyBannerView(isReadOnly: projectController?.isReadOnly ?? false, …)`）、`:179-182`（`ToastBarView(toast: editorState.toast)`）、`:266-271`（`.onChange(of: workspace.pendingAIEnhance)`）、`:276-284`（`.onChange(of: workspace.pendingStackCommand)`）、`:322-345`（`.onChange(of: projectController?.importProgress)`）、`:346-348`（`.onChange(of: projectController?.projectURL)`）。
- 问题：`.onChange(of:)` 的被观察值在 body 作用域读取（dataflow.md「Isolating onChange(of:) side-effect invalidation」），`editorState.toast` / `projectController?.isReadOnly` 的读也在 body 作用域——这些任一属性变化（toast 每次推入/清除、import 进度每次更新）都重估**整个 WorkspaceHostView body**（topBar + libraryFace + 8 个 sheet 闭包 + 全部 modifier 尾）。skill 出处：dataflow.md §Side effects in views / environment.md §Unused @Environment Reads。旁证：`:335-343` 注释记录该 body 已触发过 Release `-O` 类型检查超时（M2-11-02 实战）——body 复杂度已在预算边界。
- 修复草图：toast/banner 改为子视图自读（`ToastBarView(editorState:)` / `ProjectReadOnlyBannerView(controller:)` 让子视图自己建立 observation 依赖）；四个 request-consumption onChange 各抽成轻量 ViewModifier（dataflow.md 的 `EditorChangesModifier` 定式），只让 modifier 所在的叶子重估。
- **d6-relevant**：直接缩小宿主级重估树规模——D-6 churn 高危面。

**M2. 39 个 iop 面板每 tick 重复 JSON 解码 params（系统级）**
- 位置：`App/Sources/Lightamer/UI/Inspector/*.swift` 中 39 个文件的 `private var params: X.Params { PanelEditing.params(of: instance, …) ?? … }` 计算属性（grep 实证 39 文件 / 48 处 `params(of:` 调用）；底层 `LightamerCore/Sources/Pipe/History/ModuleInstance.swift:146-148` = **每次调用 `JSONDecoder().decode` 全新解码**。
- 问题：computed property 在 body 每次求值按读取次数重复解码（ChannelMixerRGB 单次 body ≈ 15+ 次读取 = 15+ 次 base64 + JSON 解码 + JSONDecoder 分配）；而面板恰是 D-H1 live-tick 热路径——拖动期间 `setLiveParams` 每 tick 替换 instance record → 父链重估 → 面板 body 重跑 → 每 tick 全套重解码。skill 出处：structure.md §Keep view init cheap + dataflow.md §Cache derived @Observable values。
- 修复草图：body 顶部 `let params = …` 捕获一次（最薄）；或 @State 缓存以 `instance.id + instance.paramsData 哈希` 键控；或下沉到模型层解码一次。

**M3. Filmstrip 可见窗以 Int 索引记账，堆叠 fixup 中途插行时索引漂移、warm 集合慢性膨胀**
- 位置：`App/Sources/Lightamer/UI/Shell/FilmstripView.swift:44-45`（`visibleIndices: Set<Int>`）、`:194-203`（每行 onAppear/onDisappear 用 `grid.rows.firstIndex(where:)` 反查索引）、`FilmstripModel.refreshWindow()`（`:119-136`）。
- 问题：①行身份按位置（Int）而非元素 id 记账——expanded 堆叠模式的 fixup 在页追加时**中途插入行**（`LibraryGridModel.stackAdjacencyFixup` 在 anchor+1 insert），可见行的索引整体移位；SwiftUI List 行 identity 是 `row.id`（稳定、cell 不卸载），移位后旧行不触发 onDisappear → `visibleIndices` 同时持有 stale 索引与新索引，warm 窗口随之虚胖（`requestedIDs` 融合保证浪费有界，但会慢性膨胀并多发 `prioritize`）。②每次行出现/消失做 O(n) `firstIndex` 扫描（10k 行虚拟化目标下每次滚动摩擦都付）。skill 出处：foreach.md §Avoid collection indices as identity（位置 ≠ 元素）。
- 修复草图：`visibleIndices` 换成 `Set<Int64>`（行 id）记账，warm 窗直接由可见 id ± prefetch 邻域经 id→index 字典（模型维护一次 O(1) 查）解析；`firstIndex` 反查同步消灭（与 m6 合并修）。

**M4. ContentView 根 body 同族失效放大（legacyBody 计算属性 + 多个环境依赖 onChange）** — `d6-relevant`
- 位置：`App/Sources/Lightamer/UI/ContentView.swift:170-425`（body + `@ViewBuilder private var legacyBody`），`:359`（`.onChange(of: editorState.loadedImageURL)`）、`:326/:340/:351/:362`（org-mode / browser-mode / inspector-visible onChange 链）、`:375-424`（两个 sheet + fileImporter + alert 尾）。
- 问题：与 M1 同型——根视图 body 作用域读取 `editorState.loadedImageURL` 等仅作副作用的属性（开图、切模式）→ 整个根（NavigationSplitView 树 + 双 body 面）重估。`legacyBody` 为计算属性不设独立失效边界（structure.md §Always use separate View types for sections）——legacy 门控面整体同界。skill 出处：dataflow.md §Isolating onChange(of:) side-effect invalidation；structure.md §computed properties。
- 修复草图：四个 onChange 各抽 ViewModifier；legacyBody 的稳定段（sidebar 骨架）拆子 View struct。
- **d6-relevant**：app 根级重估树规模。

**M5. 面板族单一失效边界：Film/Drt 面板全 body 按 `private var` 分节，任一模型属性 tick 重估整面板** — `d6-relevant`
- 位置：`App/Sources/Lightamer/UI/Shell/FilmPanelView.swift:23-57`（body）+ `:61-594`（header/enableEntry/sessionControls/latitudeSection/placementSection 等全为 `private var` 计算属性，单 View 一个失效边界）；`UI/Shell/DrtPanelView.swift:32-48` + `:52-313`（methodCard/encodingGroup/limitingGroup/presetGroup 同型）。
- 问题：整个面板读同一个 `@Observable` model 的多个属性（record / latitudeStats / placementParams / solveReadout…），任一变化（最重：Y/M 强度滑杆的 60Hz live tick）重估**整个面板 body**，含 Canvas 直方图重绘、picker 全量重建、§9.2 readout 重算。FilmPanelView 尤重（594 行边界）。skill 出处：structure.md §Always use separate View types for sections（computed property 不引入独立失效边界）。
- 修复草图：`LatitudeSection`（Canvas + share readout + notes）与 `PlacementSection` 抽独立 View struct、只接各自读的字段；DrtPanelView 同法拆 encodingGroup。与房内约定不冲突（KD-3 约束的是模型三级读形态，不是视图分节方式）。
- **d6-relevant**：拖动热路径的重估树规模。

### minor（11 条）

**m1. ForEach 行返回 `AnyView?`** — `App/Sources/Lightamer/UI/Shell/EditorAdjustmentStackView.swift:420-441`（`row(for:session:) -> AnyView?`，`:440` `return AnyView(view)`，喂入 `:202/:212` 的 ForEach）。skill 出处：foreach.md §Avoid AnyView as a ForEach row（类型擦除破坏结构身份，diff 需求值行 body）。修复草图：返回具体 `InspectorRowView?`（该行本就是具体类型——AnyView 只是函数签名偷懒）。

**m2. 每 body 求值的重计算（非解码类）** — ①`UI/Shell/FilmPanelModel.swift:117-130`：`solveReadout` 计算属性在 body 读路径跑 `FilmRuntimeSolve.solve`（每次拖动 tick 全量解算）；②`DrtPanelModel.swift:90-92`：`isCustomLook` 每 body 全 53 参数对内置快照比对；③`FilmPanelModel.swift:330-345`：`placementTarget` 每 body 扫层链。skill 出处：dataflow.md §Cache derived @Observable values。修复草图：solveReadout/isCustomLook 缓存为 stored property（didSet/写入点刷新）。

**m3. 软弃用 API 存量 17 处**（soft-deprecated-apis.md 清单对照；skill 口径 = 信息项非紧急）：
- `.cornerRadius(` ×14：`UI/Overlay/MaskToolbarView.swift:81,170,361,378,396,446,465,483` 等 + `UI/Overlay/InstancePickerOverlay.swift:92` + `UI/Overlay/SegmentEditingOverlayHost.swift` → 改 `clipShape(RoundedRectangle(...))`。
- `.foregroundColor(` ×1：`UI/SessionBrowserView.swift:541` → `foregroundStyle`。
- `TextField(_:text:onCommit:)` ×1：`Export/ExportNamingEditor.swift:179-184` → `TextField(_:text:)` + `.onSubmit`。
- `.onChange(of:) { _ in` 单参旧形 ×1：`UI/McpLauncherPanelView.swift:284` → 双参或零参新形。

**m4. ObservableObject 残留** — `UI/McpLauncherPanelView.swift:31`（`McpLauncherPanelModel: ObservableObject` + 7×`@Published`）+ `:174`（`@StateObject`）。skill 出处：dataflow.md §Model objects with @Observable（粗粒度 objectWillChange 广播 vs 逐属性跟踪）。修复草图：迁 `@Observable` + `@State`（仓内其余 30+ 模型已是此形，此为最后一处）。

**m5. 非私有 @State** — `UI/Overlay/CropOverlayHost.swift:80` `@State var preset`（仓内唯一）。skill 出处：dataflow.md §View-local state with @State（Always private）。修复草图：加 `private`（该视图无外部初始化需求时零波及）。

**m6. 行出现/消失的 O(n) firstIndex 反查** — `Library/Views/LibraryGridView.swift:166-170`（cell onAppear）+ `UI/Shell/FilmstripView.swift:194-203`（两处）。skill 出处：foreach.md（成本随集合规模；`.enumerated()` 即可携带索引）。修复草图：`ForEach(grid.rows.enumerated(), id: \.element.id)`（Swift 6.1 起直接可用）或模型维护 id→index 字典；与 M3 合并修。

**m7. onAppear + `Task {}` 异步初始化应走 `.task`** — `Settings/SettingsPages.swift:377-381`（`guard !loaded` + `Task { await model.refresh() }`，手工复刻 `.task` 的 once-per-identity 语义且无取消）；`:682-686` 同型（sync load，可留 onAppear 但 once-guard 冗余）。skill 出处：structure.md §Keep view init cheap（"compute it asynchronously in `.task`"）。修复草图：`.task { await model.refresh() }`（model 为 @State 持有即天然 per-identity 一次），删 `loaded` 标志。

**m8. 视图路径 DateFormatter 每次调用分配 + 硬编码格式** — `Library/Views/LibraryInspectorView.swift:500-505`（`dateSpelling` 每 chip 渲染新建 formatter，`dateFormat = "yyyy-MM-dd"` 直设）。skill 出处：localization.md §Formatting Dates（用 `Text(date, format:)` / format style；不可避免时 `setLocalizedDateFormatFromTemplate`）。注记：ISO 定长格式若是检索语法契约则属故意——修复草图改为 `static let` 缓存 formatter（线程入口单一）即可去分配项。

**m9. 本地化片段与数字手工拼接（词序风险）** — `UI/Shell/FilmPanelView.swift:339`（`Text(verbatim: "\(label) \(pct)%")`——label 已本地化、百分比后置硬编码；zh 语序「以下 43%」无法表达）+ `:498-509`（三个本地化标签经 `String(format:)` 按位嵌入 verbatim 读出行）。skill 出处：localization.md §String Interpolation vs Concatenation（never glue separately localized fragments）。修复草图：单条目改 `String(localized:)` 格式键（如 `"latitude_share_value %@"` 带注释）；读出行改为各自独立 `Text` 并排（布局而非字符串拼接）。

**m10. xcstrings 零复数变体 + 位置参数刚性** — `Resources/Localizable.xcstrings`：1957 键中 **0 个 variations/plural**，50 个格式键全为 `%lld/%@` stringUnit（如 `library_grid_end`"…— N photos"、`export_face_more %lld`）；英文复数屈折不随数量变化，双数字键（`export_targets_header %lld %lld`）stringUnit 无位置参数语义、zh 语序不可调。skill 出处：localization.md（String Catalog 复数/变体能力未被使用）。修复草图：对含名词数量的键（photos/subjects/jobs 类）逐个加 plural variations；双参数键改语义化模板或拆两段。

**m11. DrtPanelView 在 init 里 `State(initialValue:)` 构造模型** — `UI/Shell/DrtPanelView.swift:23-30`。祖先 body 每次求值都跑该 init → 每个 ancestor-eval 分配一个即刻丢弃的 `DrtPanelModel`（SwiftUI 只在首次插入取值）。skill 出处：structure.md §Keep view init cheap（"init runs much more often than people expect"）。修复草图：仿 FilmPanelView/FilmstripView 的 onAppear 惰性建（o7 既有仓内定式），或模型改由上层注入。

### obs（9 条）

**o1. 闭包 Binding 全仓普及 vs skill 的 KeyPath-Binding 规则 —— 房内约定冲突，记 obs**
- 位置：`FilmPanelView.swift:114-117,130-133,145-148,…`、`DrtPanelView.swift:59-62,81-84,…`、`LightamerSlider.swift:59-62` 等。
- skill 出处：dataflow.md §Use KeyPath bindings, not closure bindings。**不修**：D-H1 提交语义（tick→setLive、dragEnd→commit 一项）要求自定义 set 腿，KeyPath 直连会绕开 live 窗；且拖动绑定的 get/set 本就非纯投影。约定条目：AGENTS.md M3-1 KD-3 D-H1 三件套。skill 的堆分配/比较顾虑在拖动场景不成立（tick 本身就是要写字段）。

**o2. 动态查表键家族（`String.LocalizationValue(变量)` / 插值 String 键）—— 房内约定豁免，记 obs**
- 位置：`Export/ExportInspectorView.swift:390,534,546`、`Export/ExportPanelView.swift:495,536,739,752`、`Export/ExportQueueFaceView.swift:205`、`UI/ContentView.swift:529`、`UI/SidebarView.swift:151,155,548`、`UI/EDRControlView.swift:46` 等。
- skill 出处：localization.md（运行时键不可静态提取）。**不记 violation**：V14/L058 约定明文允许「显式 switch/属性返回静态键 + plain-String 先行拼接」形态，且抽查实证键已手工在册（`edr_headroom_label %@`、`export_format_*`、`ai_picker_subject_n %lld` 均在 catalog，extractionState: manual）。约定条目：CONVENTIONS「V15 提取器 + 动态族 SUMMARY 键清单对账」。

**o3. 面板供给协议以 `AnyView` 为返回面** — `UI/Inspector/IOPPanelProvider.swift:47`（`func panel(...) -> AnyView`，48 面板注册表按 opName 分派）。skill 的 AnyView 罚则针对 ForEach 行身份；此处是单面板挂载点的异构注册缝（非行内），重估面 = 被选面板本身。维持设计；若未来泛型化可用 `any View` 等价——不值得动。约定条目：D12 33-panel zero-diff contract。

**o4. 翻译注释（comment:）全仓零使用** — 1957 键均无 `comment:`，catalog 内亦无 Comment 字段。skill 出处：localization.md §Comments for Translators。仓情：en/zh 双语由所有者直接维护（非外包翻译），信息损失有限；若未来开放翻译贡献再补。

**o5. 面板模型三级读的传递性依赖（KD-3 约定）** — `FilmPanelModel.swift:62-71` / `DrtPanelModel.swift:68-77`：`record` 计算属性经 `editorState.history.effectiveXxxRecord()` 与 coordinator carrier 读取——dataflow.md 明言计算属性传递建立对底层集合/结构的全量依赖。**不修**：这正是约定的三级读形态（live→history→carrier），依赖宽是语义本身。约定条目：AGENTS.md M3-3/M2-6 架构增量 KD-3。

**o6. LutPanelView `.id(libraryRevision)` 子树身份重置** — `UI/Inspector/LutPanelView.swift:79,148-154`：每次面板出现 rescan + revision bump → `LutLibraryTreeView` 整子树 identity 替换、全量重建。**d6-relevant**（AttributeGraph 子树重建 churn；面板开关/tab 切换即触发）。设计动机成立（手动刷新语义 + 递归扫描库树），若 D-6 观测到 LUT 页卡顿，此为第一嫌疑：改为把扫描结果做成数据 diff（rows 按 key 重排）而非 identity 重置。

**o7. onAppear 惰性建 @State 模型定式** — `FilmPanelView.swift:49-50`、`FilmstripView.swift:170-174`、`LibraryGridView.swift:119-123`（`if model == nil { model = … }`）。skill 未禁止（@State 持久性使然、避免 init 抓 Environment）；仓内一致。仅注记 DrtPanelView 未走同式（见 m11）。

**o8. Settings 页 onAppear 重播种** — `SettingsPages.swift:183,1110,1417`：页面再次出现时从持久真相同步重种 @State。因 onChange 写穿（seed→commit→persist 循环闭合）无脏状态丢失风险；skill 无对应条款。合规。

**o9. EditorAdjustmentStackView 每 body 求值的轻量派生** — `EditorAdjustmentStackView.swift:135-136`（body 内新建 `InspectorEditSession` class 实例）、`:189-200`（descriptors filter/分组每 body 重算）、`:192,:281`（`EditorTabRoutingTable.panels(for:)` 每页调两次）。规模 ~10 项/页，成本微；foreach.md §Don't sort or filter inline 的字面命中但量级豁免。若做 M5 拆分时顺路下沉到模型即可。

---

## onAppear 39 处提及分诊（27 处真实 call site；其余为注释提及）

### A 类：真合法（同步种值 / 生命周期配对 / 设计内信号）— 22 处
| 位置 | 性质 |
|---|---|
| SettingsPages.swift:183 | 从 preferences 同步种 @State（onChange 写穿闭环，o8） |
| SettingsPages.swift:283 | caches/lut 路径字符串种值（FileManager 延迟到出现 ✓） |
| SettingsPages.swift:682 | sync `model.load()` 一次性（once-guard 略冗余，非必修） |
| SettingsPages.swift:1110 | seed() 同步种值（o8） |
| SettingsPages.swift:1417 | `refreshSchemaState()` 同步刷新 |
| LibraryGridView.swift:119-123 | pager 惰性建（o7） |
| LibraryGridView.swift:166-170 | 分页滚动信号（LazyVGrid 设计内；配 m6 修索引反查） |
| RelinkSheetView.swift:93-98 | 纯函数 classify 惰性算一次 |
| SettingsView.swift:85-90 | deep-link 一次性消费 |
| EditorAreaView.swift:243-244 | hold-monitor 安装/拆除（onAppear/onDisappear 配对 ✓） |
| EditorAreaView.swift:277 | 初始几何同步（配 onChange ✓） |
| EditorAreaView.swift:321-323 | zoom-lock 初始态 |
| ScopePanelView.swift:139-140 | scope tap 启/停（配对 ✓） |
| EditorNodesPanelView.swift:85-86 | 容器尺寸初值 + onChange |
| EditorNodesPanelView.swift:159 | 首帧 scrollTo |
| WorkspaceHostView.swift:1366 | yiyin sheet 域尺寸初值（配 onChange ✓） |
| ContentView.swift:312-318 | 首帧布局态应用（RQ-16-12 冷启动语义，设计内） |
| FilmstripView.swift:170-177 | 模型惰性建 + onDisappear 取消面（配对 ✓） |
| FilmstripView.swift:194-203 | 虚拟化窗口信号（设计内；M3/m6 指其索引记账缺陷） |
| LutPanelView.swift:148-154 | 打开面板 rescan（手动刷新故事，注释申报） |
| InstancePickerOverlay.swift:94 | 选择集初值种子 |
| PastePartialDialog.swift:130-132 | 勾选集初值种子 |

### B 类：应改 `.task` — 1 处
| 位置 | 说明 |
|---|---|
| SettingsPages.swift:377-381 | `guard !loaded` + `Task { await model.refresh() }` —— 手工复刻 `.task` 的 per-identity 一次语义且丢掉消失取消；直接 `.task { await model.refresh() }` |

（SegmentEditingOverlayHost.swift:79 armSegmentSession 归 A 类变体：拆解走 mode 退出路径而非 onDisappear——LayerEditingState:715 注释申报，属设计内生命周期。）

### C 类：副作用应上移 — 1 处
| 位置 | 说明 |
|---|---|
| WorkspaceHostView.swift:349-351 | `rebuildLibrarySurface()` 在宿主 onAppear 直呼——表面重建编排属模型层职责；上移到 `.task`/模型初始化入口后，该 onAppear 可整体消失（与 M1 的宿主瘦身同批） |

---

## 合规面注记（skill 对照的正向结论）

- **@Observable 全覆盖**：App 层 30+ 模型全部 `@MainActor @Observable`（除 o2/m4 的一处遗留）；record 类型（DrtRecord/FilmRecord/FilmPlacementModule.Params/PlacementFitOutcome 等）全 Hashable/Equatable —— dataflow.md 的 Equatable setter 短路前提成立。
- **ForEach identity 全稳定**：图库 `id: \.id`（Int64 rowid）、filmstrip 同、Session browser `Row: Identifiable`（relPath/pathHash，L010/L013）；无 `.indices` 身份、无 body 内造 UUID、无大结构 `id: \.self`。
- **零条件修饰符**（modifiers.md）：无 `.if` 家族；样式切换用三元（`isSelected ? … : …`）。
- **零单子 Group**（structure.md）：31 处 `Group {` 全为 if/else 条件内容包裹（合法形态）。
- **onChange 双参新形 27 处、零参新形 2 处**，旧单参仅 1 处（m3）。
- **缩略图加载全走 `.task(id:)`**（LibraryGridCellView:388 / FilmstripRowView:290 + `resolvedFor` 回收竞态防 logits）——skill 的异步工作归属模型（model 层 owned）定式执行到位。
- **软弃用存量 17 处**（m3）相对 196 文件体量为低；NavigationView/ActionSheet/旧 alert/accessibility(label:)/edgesIgnoringSafeArea/navigationBarItems 等大头全部为零。
- **content-builder.md 兼容面**：目标 macOS 27（无 back-deploy Chart 分支问题）、零 MapKit、零空 builder body、零 TupleView 泛型拼写、零跨模块 SwiftUI 型遮蔽（Color/Text 等）——ContentBuilder 统一化的四类 source-compat 风险全不命中。

## 后续动作建议（供 orchestrator 裁决，不在本路执行）

1. M1+M4（宿主/根 onChange 隔离）与 M5（面板分节拆分）同属 d6-relevant，建议合并立项并在 macOS 27 真机以 D-6 churn 复现条件走查前后对比。
2. M2（params 解码）改动面大（39 文件）但机械（body 顶部捕获或缓存器），适合单 plan 批处理。
3. m3 软弃用清扫可与任意 plan 顺路（17 处、全部机械替换）。

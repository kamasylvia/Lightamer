# FINDINGS-00 — slice-00 (Export / Library / Settings / InspectorState / UI)

结论头：**0 error + 5 major + 19 minor + 9 obs**（本 slice 内计数）

审计面：App 层 SwiftUI 视图 19 文件，全文逐文件深读（未抽样，未改码，未跑构建/测试）。
判定基准：`.work/xcode27-skills/swiftui-specialist/references/`（structure / dataflow / environment / foreach / animations / localization / modifiers / soft-deprecation）与 `.work/xcode27-skills/swiftui-whats-new-27/references/`（state-macro / content-builder），房内约定优先（KD-4、app-root sheet 闭包禁裸 @Environment、`String.LocalizationValue("prefix_\(x)")` 插值禁令、xcstrings 尾块纪律、disable-not-unmount、D-H1 begin/end 配对；SwiftUI App lifecycle 层观察照记、不作迁移阻断）。

## 实读文件清单（19 个，行数=wc -l）

| # | 文件 | 行数 | 文件级小结 |
|---|------|------|-----------|
| 1 | App/Sources/Lightamer/Export/ExportInspectorView.swift | 1263 | 1 major + 3 minor |
| 2 | App/Sources/Lightamer/Export/ExportNamingEditor.swift | 320 | 1 minor |
| 3 | App/Sources/Lightamer/Export/ExportPanelView.swift | 833 | 2 major + 3 minor |
| 4 | App/Sources/Lightamer/Export/ExportQueueFaceView.swift | 213 | 1 minor（含家族代表） |
| 5 | App/Sources/Lightamer/Library/ImportModeDialog.swift | 321 | 1 major + 2 minor |
| 6 | App/Sources/Lightamer/Library/ImportProgressView.swift | 70 | PASS（零 finding） |
| 7 | App/Sources/Lightamer/Library/LibraryGridModel.swift | 560 | PASS（非 View；@Observable/@MainActor 合规） |
| 8 | App/Sources/Lightamer/Library/LibraryProjectController.swift | 850 | 1 minor（+2 合规确认） |
| 9 | App/Sources/Lightamer/Library/Views/GlobalSearchDialog.swift | 267 | 1 minor |
| 10 | App/Sources/Lightamer/Library/Views/LibraryAutoStackDialog.swift | 98 | 1 minor（含家族代表） |
| 11 | App/Sources/Lightamer/Library/Views/LibraryGridView.swift | 405 | 2 minor + 1 obs |
| 12 | App/Sources/Lightamer/Library/Views/LibraryInspectorView.swift | 564 | 3 minor + 1 obs |
| 13 | App/Sources/Lightamer/Library/Views/RelinkSheetView.swift | 281 | 1 minor + 1 obs |
| 14 | App/Sources/Lightamer/Settings/SettingsPages.swift | 1469 | 2 minor |
| 15 | App/Sources/Lightamer/State/InspectorState.swift | 262 | PASS（非 View；1 obs） |
| 16 | App/Sources/Lightamer/UI/AIDownloadPrompt.swift | 177 | PASS（零 finding） |
| 17 | App/Sources/Lightamer/UI/CatalogBrowserView.swift | 382 | 1 major + 2 minor + 1 obs |
| 18 | App/Sources/Lightamer/UI/CatalogFilterBarView.swift | 387 | 2 minor + 1 obs |
| 19 | App/Sources/Lightamer/UI/ContentView.swift | 828 | 2 minor + 1 obs |

七维逐文件判定摘要：(1) 拆分度——大页 5 处的 computed-section 形态为主 minor，见 M-m1~M-m6；(2) 数据流——@Observable 归属/@State 持有/按属性追踪总体合规，违规集中在静态 UserDefaults 直读（M-J1）与整行传值（M-m7）；(3) ForEach——枚举/Identifiable 占优，indices 形态 3 处（M-J5、M-m8、M-m12 家族）；(4) 动画——仅 CatalogBrowserCell 一处 withAnimation，无值-less `.animation()`，PASS；(5) 本地化——静态键+verbatim 数据面总体合规，动态拼键 1 处 major（M-J2），其余为 casing/数字格式/译者注释 minor；(6) @State macro——init 播种形态（`_mode = State(initialValue:)`）合规，无 init 复写/组合 wrappers/成员 init 缺失，PASS；(7) ViewBuilder/类型检查——最深 switch（formatKnobs / formatSpecificRows / inputSegment / sizingFields）均在预算内，无 TupleView/AnyView 行、无 overlay ShapeStyle 直接参数歧义、无 Charts/MapKit 回部署分支，PASS。soft-deprecation 扫描：全 slice 用 NavigationSplitView / confirmationDialog / Table，无软废弃 API，PASS。

## Major（5）

- [M-J1] major · `App/Sources/Lightamer/Export/ExportPanelView.swift:261`（同形 `L278-279, L299-303`）· 出处：房约 KD-4（body 零 UserDefaults 直读）+ dataflow.md「Model objects with @Observable」。`Toggle(isOn: Binding(get: { PostExportActions.wantsRunScript }, set: …))` 与 `scriptDisplayName`（`PostExportActions.resolveScript()`）在 body 求值链中直读 `UserDefaults.standard`（PostExportActions.swift:48-60 系静态标准 defaults 存取）。修复草图：把三键收进注入式 store（随 ExportState/SessionState 进 environment）或经 init 参数传入解析后值，body 只读已注入 faces。
- [M-J2] major · `App/Sources/Lightamer/Export/ExportInspectorView.swift:534` · 出处：房约 `String.LocalizationValue("prefix_\(x)")` 插值形态禁令（M2-9-05 F-2）+ localization.md（插值键扫描器不可见）。`String.LocalizationValue("export_format_" + kind.rawValue)` 为运行时拼键（注释自述为规避 `"export_format_%@"`，但形态仍属被禁的动态查表键）。修复草图：照本文件 L546 `mode.labelKey` 与 ExportPanelView `titleKey` 的既有合规形态，改显式 switch 返回静态键（`case .jpeg: "export_format_jpeg"` …）。
- [M-J3] major · `App/Sources/Lightamer/Library/ImportModeDialog.swift:85` · 出处：房约「app-root sheet 闭包禁裸 @Environment」（内容面重注入/init 参数注入二选一；同仓 ProjectConflictDialog.swift:596-598 有同源 M2-8-3 sheet-boundary 注释为证）。本对话框注释自述 rides the app-root sheet，却以裸 `@Environment(AgentControlCoordinator.self)` 读取 `holdsControl` 作 confirm 门控（L149）。修复草图：init 参数注入 `holdsControl: Bool`（调用方在 sheet 闭包内从 environment 读取后传入），内容面不再直读 chain。
- [M-J4] major · `App/Sources/Lightamer/UI/CatalogBrowserView.swift:81` · 出处：foreach.md「Keep the id cheap to hash」。`ForEach(Array(model.rows.enumerated()), id: \.element)` 以整行 struct 作 id（Row 含 filename/relPath/rating/flag 等多字段），跨会话大集合下每次 diff 对全量行做深哈希；而行上已有稳定小 id（`row.id`、`row.pathHash`，L86/96/346 均在使用）。修复草图：改为 `ForEach(model.rows, id: \.id)`（或 `\.pathHash`），index 仅作 load-ahead 信号保留。
- [M-J5] major · `App/Sources/Lightamer/Export/ExportPanelView.swift:174` · 出处：foreach.md「Avoid collection indices as identity」。`ForEach(state.recipe.indices, id: \.self)` 作用于可增删的 recipe 数组（L178 add / L184 remove），增删移位时 id 指向错位元素。虽 VariantEditor 无 @State 而无状态丢失，但增删行的 diff/动画按位置而非元素语义走。修复草图：给 variant 稳定 id（Identifiable 或持久 UUID），`ForEach($state.recipe, id: \.id)` 传 element binding。

## Minor（19）

- [M-m1] minor · `App/Sources/Lightamer/Export/ExportInspectorView.swift:37`（代表行；同形 L98/117/131/223/320/436/524/608/652/737 及 `depthPicker` L716）· 出处：structure.md「Always use separate View types for sections」+「Multi-section detail views」。五 section（preset/destination/naming/metadata/sdr/queue）与 gainMapToggle/formatKnobs/sizingFields 全为 parent computed `var`，quality Slider 每 tick 重估整页 body。修复草图：每 section 抽独立 View 类型，仅传其读字段（如 `SdrSection(formatKind:activeQuality:sizingMode:…)`），parent 只做装配。
- [M-m2] minor · `App/Sources/Lightamer/Export/ExportNamingEditor.swift:53`（代表行；同形 L68/100/121/137/169/230）· 出处：structure.md 同上。小体量文件，presetPicker/patternField/tokenButtons/feedbackAndPreview/presetActionRow 均为单用 computed。修复草图：至少把含 ForEach+Binding 的 presetPicker 与 tokenButtons 提为窄输入子 View（`pattern: Binding<String>` + store/ids）。
- [M-m3] minor · `App/Sources/Lightamer/Export/ExportPanelView.swift:168`（代表行；同形 L210/258/322/384）· 出处：structure.md 同上。recipeSection/destinationSection/postActionsSection/queueActionSection/queueStatusSection 为 computed（VariantEditor/JobRow 已正确抽取，肯定）。修复草图：queue/status 两节抽窄输入 View（`progress/jobRows/canRun` 值参 + 回调闭包）。
- [M-m4] minor · `App/Sources/Lightamer/Export/ExportQueueFaceView.swift:87`（代表行；同形 L142/163/178）· 出处：structure.md 同上。progressRow/errorSummary/faceRow 为 computed/func。修复草图：`QueueRowView(row:onRetry:onCancel)` 独立 View（`row: ExportJobSnapshot` 值参即可，switch 映射进内部）。
- [M-m5] minor · `App/Sources/Lightamer/Library/Views/GlobalSearchDialog.swift:36`（代表行；同形 L64/79/106/205）· 出处：structure.md 同上。modeSegment/inputSegment/applySegment/modeCard 为 computed/func（三分支 inputSegment 体量大）。修复草图：按 mode 抽 `ExifInputView/ClipInputView/FullTextInputView(query: Binding<String>…)`。
- [M-m6] minor · `App/Sources/Lightamer/Library/Views/LibraryInspectorView.swift:43`（代表行；同形 L73/100/118/167/218/289/321/387/441 及 `FlowLikeChips` 已独立肯定）· 出处：structure.md 同上。overview/group/activity/filter/actions/ai/smartAlbums 全 computed 且同 body 读 model 六处属性。修复草图：每节抽窄输入 View（如 `ActivitySection(activity:arms:onToggle:)`），`model` 本体不出 parent。
- [M-m7] minor · `App/Sources/Lightamer/Library/Views/LibraryGridView.swift:297` · 出处：dataflow.md「Pass views only the data they read」。`LibraryGridCellView` 取整行值类型 `row: LibraryImageRow`，cell 仅读 id/rating/filename/imagePath（+外部算好的 stackBadge）；行任一字段变更即重估该 cell（逐字段比较成本亦随行宽放大）。修复草图：改传 `filename:imagePath:rating:id` 四窄参（或按 dataflow.md 切 per-view 小 struct）。
- [M-m8] minor · `App/Sources/Lightamer/Library/Views/LibraryInspectorView.swift:111`（同形 L254/260/527 FlowLikeChips）· 出处：foreach.md「Avoid collection indices as identity」。group rows / ftsTerms / structuredTerms / arm chips 四处 `id: \.offset`，filter 折叠增删时 id 随位移漂移。行均为无状态 Button 故 harm 有限，列 minor。修复草图：group 行用 `payload.label+day` 稳定键，terms 用 term 自身 Hashable，chips 用 arm 语义键。
- [M-m9] minor · `App/Sources/Lightamer/Library/Views/LibraryInspectorView.swift:445`（同形 `RelinkSheetView.swift:111`）· 出处：localization.md「Casing」。`sectionHeader` 与 Relink section 标题用运行时 `.textCase(.uppercase)` 统改大小写，剥夺译者逐语言决策。修复草图：大小写 baked 进 catalog 源文（或逐 key 提供大写形态），删 `.textCase`。
- [M-m10] minor · `App/Sources/Lightamer/Export/ExportInspectorView.swift:659`（家族代表；同形 ExportPanelView.swift:652、ExportQueueFaceView.swift:147、ExportPanelView.swift:395、LibraryAutoStackDialog.swift:45、CatalogFilterBarView.swift:242）· 出处：localization.md「Formatting Dates, Numbers, and Currencies」。`"\(Int(q*100))%"` / `"\(done)/\(total)"` / `"\(Int(gapSeconds)) s"` / `"\(Int(v)) mm"` 硬编码百分号/单位/数字拼接，不随 locale 走 format style。修复草图：百分比用 `.percent`（或 `Text(value, format:)`），`s/mm` 进带占位注释的 catalog format 键。
- [M-m11] minor · `App/Sources/Lightamer/Settings/SettingsPages.swift:936` · 出处：localization.md「Localizing Variables and Custom Types」。Keyboard 表 Command 列直展 `row.id.rawValue`（`MenuCommandID` 内部标识）给用户看，非本地化。修复草图：`MenuCommandID` 加显式 switch→`LocalizedStringResource` 显示名（未知 case 回退 rawValue 并标 verbatim）。
- [M-m12] minor · `App/Sources/Lightamer/UI/CatalogBrowserView.swift:225`（家族代表；同形 L238、CatalogFilterBarView.swift:209/217/233/241、ExportPanelView 色标？无）· 出处：localization.md「Formatting…」（数字一律 0-9；`String(format:)` 同理）。评分/色标/ISO/焦段菜单 `Button("\(n)")` 把纯数字写成 LocalizedStringKey 内插。修复草图：`Button {…} label: { Text(verbatim: "\(n)") }` 或 `.formatted()`。
- [M-m13] minor · `App/Sources/Lightamer/Library/ImportModeDialog.swift:151`（家族代表；同形 ImportProgressView.swift:40、RelinkSheetView.swift:83、GlobalSearchDialog.swift:49、LibraryAutoStackDialog.swift:92、ExportNamingEditor saveSheet L254 300pt、ExportPanelView saveSheet L151 320pt）· 出处：localization.md「Layout for Localization」（勿硬编码文本框宽）。对话框 `.frame(width: 440/340/430/460/…)` 定死，译文变长（de/zh）时按钮行易 clip。修复草图：改 `minWidth` + 关键行套 `ViewThatFits`（HStack→VStack 降级）。
- [M-m14] minor · `App/Sources/Lightamer/Settings/SettingsPages.swift:716`（家族代表；同形 L737/763、L1273/1280、SettingsImportDefaultsPage L1082、CatalogBrowserView.swift:301/376、LibraryInspectorView.swift:196）· 出处：localization.md「Layout for Localization」（text styles 而非固定 point size，高脚本易 clip）。`.system(size: 8/9/11, design: .monospaced)` 多处。修复草图：caption/caption2 + `.monospaced()`/`.monospacedDigit()` 组合替代固定 size。
- [M-m15] minor · `App/Sources/Lightamer/UI/ContentView.swift:100`（家族代表；同形 L110/166/167/168、InspectorPageMount L757、SettingsPages.swift:1214-1221 MCP 四键）· 出处：房约 KD-4（注入式 defaults）。布局/模式/MCP 开关经 `@AppStorage` 在 body 直读标准 defaults，非注入 faces（仓内 ImportDefaults/AppPreferences/CatalogPreferencesModel 均为注入形态）。行为正确、属惯用形态，故 minor。修复草图：迁入已有注入 store（MCP→McpServerController 拥有；布局→CatalogPreferencesModel/DisplayStore 类 faces），body 只读 environment。
- [M-m16] minor · `App/Sources/Lightamer/Export/ExportPanelView.swift:663` · 出处：localization.md「SwiftUI Views Localize String Literals Automatically」（变量须 verbatim  opt-out）。depthPicker 行 `Text(labels[index])`（String 变量→走 StringProtocol 重载本就不本地化，但字面意图是技术位深标签，应显式 `verbatim:` 如 Inspector L726 已做对）。修复草图：`Text(verbatim: labels[index])`。
- [M-m17] minor · `App/Sources/Lightamer/Library/LibraryProjectController.swift:649` · 出处：localization.md（用户可见串须进 catalog）。`pidText` 回退字面 `"未知"` 硬编码中文，随 `project_read_only_dialog_message` defaultValue 内插展示，非中文 locale 下不本地化。修复草图：增 `project_read_only_pid_unknown` catalog 键并显式 switch。
- [M-m18] minor · `App/Sources/Lightamer/Export/ExportQueueFaceView.swift:128`（家族代表；同形 L168、本文件 L205 `face.labelKey`、LibraryAutoStackDialog.swift:60、LibraryGridView.swift:148/374、CatalogFilterBarView.swift:152、SettingsPages.swift:504/521/1449）· 出处：localization.md「Comments for Translators」。全部 `\(count)` / `\(n)` 内插 catalog 键（`%lld` 形态，键本身经核对存在：export_face_more %lld、library_stack_members_hint %lld、settings_lcr_dim_semantic %lld 等）均无 `comment:` 说明占位含义。修复草图：逐内插键补 `comment: "…first variable is…"`（或 catalog Comment 字段二选一，单源）。
- [M-m19] minor · `App/Sources/Lightamer/UI/ContentView.swift:497` · 出处：localization.md「Layout for Localization」。modePicker `.frame(maxWidth: 240)` + `.pickerStyle(.segmented)` 定宽三段，译文（grid/single/culling 各语言）易挤压。修复草图：去定宽改自适应，或 `ViewThatFits { segmented / menu }`。

## Obs（9，需运行时验证或跨 slice/不可静态判定者）

- [O-1] obs · `App/Sources/Lightamer/Library/Views/LibraryGridView.swift:184` · 双 `.onTapGesture`（单击 + `count: 2`）并存：双击是否连带触发单击 select 语义、与 contextMenu 右键选择是否竞态，静态不可判。需运行时验证；若误触，修复草图为单击改 `simultaneousGesture(TapGesture(count:1))` 与双击排他。
- [O-2] obs · `App/Sources/Lightamer/Library/Views/RelinkSheetView.swift:218` · `progressSection` 读 `handle.snapshot`：RelinkTaskHandle 非 slice 内类型，其 snapshot 变更是否经 @Observable/发布驱动 body 刷新静态不可见；若为普通 class 则进度条不刷新。需运行时验证；修复草图为 handle 改 @Observable 或经 Task 轮询/`AsyncSequence` 驱动。
- [O-3] obs · `App/Sources/Lightamer/State/InspectorState.swift:242` · `beginEyedropper` 直接覆盖 `eyedropperHandler`：连续 arm 两次会静默丢弃首个 handler（首个调用方永不回调）。D-H1 begin/end 配对语义在此为 begin/disarm；当前 complete/cancel 路径配对完整。需运行时确认面板是否会重复 arm；若会，修复草图为 begin 时若已 active 则先 complete旧值或抛断言。
- [O-4] obs · `App/Sources/Lightamer/Settings/SettingsPages.swift:1142` · `SettingsDisplaysPage` body 内采样 `NSScreen.screens`：非 observable 源，显示器插拔后列表不自动刷新（需无关失效才重估）。需运行时验证；修复草图为订阅 `NSApplication.didChangeScreenParametersNotification` 后改写 @State screens。
- [O-5] obs · `App/Sources/Lightamer/UI/CatalogFilterBarView.swift:185` · `Text(FilterBarView.chipLabel(for: rule))`：`FilterBarView` 非本 slice，chipLabel 返回已本地化显示串还是原始键静态不可判（若返原始英文则跨语言漏本地化）。跨 slice 待查；修复草图为 chipLabel 改返 `LocalizedStringResource`。
- [O-6] obs · `App/Sources/Lightamer/Settings/SettingsPages.swift:925` · `SettingsKeyboardPage.effectiveCombo/conflicts` 用 `_ = overridesTick` / 裸 `overridesTick` 读制造观察依赖：可工作但 fragile（依赖 Observation 对 dummy 读的追踪，重构易断）。修复草图：把 overrides 版号做成 `preferences` 的 @Observable 发布属性并显式读其投影。
- [O-7] obs · `App/Sources/Lightamer/Library/ImportModeDialog.swift:99` · `_selection = State(initialValue: ImportTypeSelectionModel(defaults: ImportDefaults()))`（同形 ExportInspectorView.swift:34 `NamingTemplateStore()` 默认标准 suite）：init 期自建标准-suite 而非接受注入，可测性低于仓内「tests pass an isolated suite」自述。body 零直读故不判 KD-4 违规，记 obs。修复草图：init 参数 `defaults: ImportDefaults = ImportDefaults()` / `store: NamingTemplateStore = .init()` 可覆写。
- [O-8] obs · `App/Sources/Lightamer/UI/ContentView.swift:210` · `legacyBody`（M2-2-4 门控冻结，逐行 byte-frozen 声明）：其内大 body/多 computed（browserContent/toolbarContent 等）结构问题按冻结纪律不可动，本报告结构类 finding 均不指向该分支。记 obs 备查。
- [O-9] obs · 全 slice（代表 `CatalogBrowserView.swift:285` 徽标 `badge("E"/"P"/"X")`）· 单字母徽标硬编码英文首字母（Edited/Pick/Reject），属设计语言还是本地化债务静态不可判；另 xcstrings 尾块纯插入纪律无静态证据（需 git 历史核对），一并记 obs。

## 合规确认（非 finding，防误报）

- `String.LocalizationValue(kind.titleKey / mode.labelKey / Self.sortLabel…)`（ExportPanelView.swift:495/536、ExportInspectorView.swift:546、ContentView.swift:491、CatalogFilterBarView.swift:346）：均为显式 switch 返回静态字面，属 V14 纪律合规形态；抽查键（export_format_jpeg、export_sizing_original/long_edge、filter_chip_rating_3、sort_key_filename）在 `Resources/Localizable.xcstrings` 存在。
- `Text(verbatim: Self.label/hint/countText…)`（ImportModeDialog.swift:110/119/202 等）：verbatim 包的是已 `String(localized:)` 解析串，属正确 opt-out，非本地化绕过。
- 技术标识 verbatim（ExportInspectorView.swift:504 DRT rawValue、depth labels、`ExportM2FormatKind`、`space.rawValue` 色彩空间）：语言纪律合规。
- `.task(id:)` + stale-guard（LibraryGridView.swift:393 `resolvedFor`、LibraryAutoStackDialog.swift:93、CatalogBrowserView.swift:346）：异步竟态处理合规。
- `ImportModeDialog._mode/_remember/_selection = State(initialValue:)`（L96-99）：SDK27 @State macro 下无初值声明+init 播种，属 state-macro.md  sanctioned 形态。
- disable-not-unmount（ImportModeDialog.swift:149、LibraryInspectorView.swift:382）：agent 持有期 `.disabled` 而非卸载，合规。
- 裸字面 `Text("export_preset_none")` / `ContentUnavailableView Label("filter_empty_results" …)` 等：按 localization.md 字面直传即 LocalizedStringKey，属 PREFER 形态且键经核对存在；`settings_catalogs_rebuild_progress %lld %lld` 等格式键亦存在。

# OMP-FINDINGS — Lightamer App 层 SwiftUI 全量深读审计（C 路，2026-10-19）

结论头：**PASS / 3 error + 25 major + 127 minor + 44 obs**

判定基线：`.work/xcode27-skills/swiftui-specialist/references/`（structure / dataflow / environment / foreach / animations / localization / modifiers / soft-deprecation + soft-deprecated-apis.md 清单）与 `.work/xcode27-skills/swiftui-whats-new-27/references/`（state-macro / content-builder），全文先读。房内约定优先：KD-4（body 零 UserDefaults 直读）、app-root sheet 闭包禁裸 `@Environment`、房规插值构键禁令、xcstrings 尾块纪律、disable-not-unmount、D-H1 begin/end 配对、2026-10-19 壳交接既定方向（SwiftUI App lifecycle 观察照记、不作迁移阻断）。纯只读：零源码/测试/构建改动，未跑构建/测试；行为级一律 obs +「需运行时验证」。

## 覆盖面声明

- 口径：`grep -rl "import SwiftUI" App/Sources --include="*.swift"` = **114 个文件，共 41156 行**，逐文件全文深读（大文件分段读完），**实读 114/114，无抽样**。
- 分片：6 worker 各 19 文件，产物 `slices/FINDINGS-0{0..5}.md`（slice 内计数：00: 0+5+19+9；01: 2+5+7+6；02: 0+3+47+5；03: 3+5+7+6；04: 3+1+30+10；05: 0+3+23+11）。orchestrator 归一时做三处定级修正（见方法注记）， slice 内计数与正本计数因此有差。
- 跨文件核实（只读）：`ModuleInstance.params(of:)` 内确为 `JSONDecoder().decode`；`CullingView` 调用点（ContentView.swift:448）无 pair 级 `.id`；catalog 键存在性经 `Resources/Localizable.xcstrings`（1958 键）机检。

## 定级口径

- **error**：违反房内硬禁令且 catalog 证据链断裂（运行时裸 key 或静默回退），或功能正确性缺陷（静态可定罪）。
- **major**：违反房内硬禁令但 catalog 手工在册（行为正确、形态被禁、抽取链断），或高代价失效/身份误用（有真实用户影响）。
- **minor**：skill PREFER 形态偏离（失效边界粗、类型/格式次选、注释缺失、固定尺寸），行为正确。
- **obs**：需运行时验证、约定照记、或有意 tradeoff（维持现状）。

## error（3）

- [E1] error · `App/Sources/Lightamer/UI/Overlay/InstancePickerOverlay.swift:53` · 房规插值构键禁令 + localization.md「Localizing Variables and Custom Types」。`"ai_picker_subject_n \(instance)"` 经 `String.LocalizationValue(...)` 运行时构 key；catalog 仅手工在册 `ai_picker_subject_n %lld`（`extractionState: manual`），构建期抽取已断。修复草图：改静态 format 字面量 `String(localized: "ai_picker_subject_n \(instance)")` 或显式 switch。
- [E2] error · `App/Sources/Lightamer/State/LayerEditingState.swift:45`（消费点 `UI/Overlay/MaskToolbarView.swift:85`）· 同上。`MaskTool.labelKey = "mask_tool_\(rawValue)"` 插值拼装（`followEdges` 等驼峰 rawValue 尤脆），catalog 全手工在册但抽取链断。修复草图：`labelKey` 改显式 switch 返回静态字面量。
- [E3] error · `App/Sources/Lightamer/State/LayerEditingState.swift:75,102`（消费点 `UI/Overlay/MaskToolbarView.swift:144`、`UI/Inspector/LayersPanelView.swift:397`）· 同上。`MaskOverlayStyle.labelKey` / `MaskCommand.labelKey` 插值拼装（`onBlack`/`duplicateAndInvert` 驼峰），catalog 全手工在册但抽取链断。修复草图：同 E2，两处改显式 switch。

注：E2/E3 的 key 定义在非 SwiftUI 文件（State 层 enum），消费点在审计面内；归一时把 slice-04 的两条 error 与 slice-02 的 LayersPanelView major 合并为同族 3 error（定义点 3 处）。

## major（25）

本地化-动态键族（房规禁令形态，catalog 现状有键、行为正确）：
- [J1] major · `App/Sources/Lightamer/UI/CullingView.swift:76-99` · dataflow.md「Model objects with @Observable」+ foreach.md「Don't create a new id on every body evaluation」。`panesContent` 在 body 路径上逐次新建 `CullingPaneModel`，所附 `.task` 无 `id:` 只首跑一次；pair 切换后新 pane 永不加载（调用点 ContentView.swift:448 无 pair 级 `.id`，`comparePair` 由 model 驱动）；旧 `@State panes` 与新视图失配且释放语义混乱。修复草图：pane 创建/加载搬 `.task(id: pairKey)` 或 `onChange(of: pair)` 按 pairKey 持有。
- [J2] major · `App/Sources/Lightamer/UI/FilterBarView.swift:165-185`（调用 L145-160）· 房规插值禁令 + localization.md。`chipButton(labelKey:)` 运行时 `String(LocalizationValue(labelKey))`，四调用点字面量抽取靠运气（键现状在册）。修复草图：改接 `LocalizedStringResource`，调用点传字面量。
- [J3] major · `App/Sources/Lightamer/Export/ExportInspectorView.swift:534` · 同上。`"export_format_" + kind.rawValue` 运行时拼键（L058 注释自述规避 `%@`，形态仍被禁；键现状在册）。修复草图：照 L546 `mode.labelKey` 形态改显式 switch。
- [J4] major · `App/Sources/Lightamer/UI/Inspector/SigmoidPanelView.swift:121` · 同上。`preset.0` 变量构 key（4 静态 preset）。修复草图：presets 携 `LocalizedStringResource` 或显式 switch。
- [J5] major · `App/Sources/Lightamer/UI/Inspector/ToneEqualPanelView.swift:84` · 同上。`band.0` 变量构 key（9 段）。修复草图：bands 加 `label:` 静态资源字段。
- [J6] major · `App/Sources/Lightamer/UI/Inspector/MaskGroupsPanelView.swift:337` · 同上。`commitSlider` 内 `LocalizationValue(labelKey)`（两调用点静态 key，行为正确但抽取失效）。修复草图：调用点直传字面量/`LocalizedStringResource`，删 String 中转。
- [J7] major · `App/Sources/Lightamer/UI/Inspector/EqualizerPanelView.swift:51` · 同上。`Self.bands[i].0` 变量构 key。修复草图：bands 改静态 `LocalizedStringResource` 数组。
- [J8] major · `App/Sources/Lightamer/UI/Inspector/LuminanceColorRangePanelView.swift:332` · 同上。`labelKey` 变量构 key（5 个 `mask_range_*`）。修复草图：`bandSlider` 的 `labelKey: String` 改 `label: LocalizedStringResource`。
- [J9] major · `App/Sources/Lightamer/UI/InspectorRowView.swift:73` · localization.md「Localizing Variables」。`Text(LocalizedStringKey(model.toggleValueKey))` 运行时变量包 key，catalog 缺条目时 AX 回退裸 key。修复草图：按 `model.enabled` 显式 switch 返回 `Text("toggle_on")/Text("toggle_off")`。
- [J10] major · `App/Sources/Lightamer/UI/InspectorRowView.swift:80` · localization.md「SwiftUI Views Localize String Literals」。`Text(LocalizedStringKey(label))` 对已解析串二次查表（locale 切换失效）。修复草图：`Text(label)`。
- [J11] major · `App/Sources/Lightamer/UI/Inspector/PresetPanelView.swift:107` · localization.md「String Interpolation vs Concatenation」。`String(localized:) + " \(name)"` 拼接组句。修复草图：label 闭包 `Text("preset_apply \(name)")` 字面量插值。
- [J12] major · `App/Sources/Lightamer/UI/Shell/FilmPanelView.swift:384-393` · localization.md「String Interpolation vs Concatenation」+「Comments」。`latitude_share_value` 的 `defaultValue` 内嵌已解析内层 `String(localized:)`，源文本随 locale 固化，`%` 硬编码、占位无说明。修复草图：外层改真 format 键（`%@ %lld%%` + comment），内层标签作参数传入。
- [J13] major · `App/Sources/Lightamer/UI/EDRControlView.swift:46` · localization.md「Formatting Dates, Numbers」。`String(format:)` 嵌套 `String(localized:)` 插值，数字恒 0–9 无视 locale。修复草图：`Text("edr_headroom_label \(headroom, format: .number…)", comment: …)`。

数据流/KD-4/结构 major：
- [J14] major · `App/Sources/Lightamer/Export/ExportPanelView.swift:261,278-279,299-303` · 房约 KD-4 + dataflow.md。`Toggle(Binding(get: { PostExportActions.wantsRunScript }…))` 与 `resolveScript()` 在 body 链直读 `UserDefaults.standard`。修复草图：三键收进注入式 store（随 ExportState 进 environment）或 init 传解析值。
- [J15] major · `App/Sources/Lightamer/Library/ImportModeDialog.swift:85,149` · 房约 app-root sheet 禁裸 `@Environment`。对话框自述 rides app-root sheet 却裸读 `@Environment(AgentControlCoordinator.self)` 作 confirm 门控。修复草图：init 参数注入 `holdsControl: Bool`。
- [J16] major · `App/Sources/Lightamer/UI/Overlay/InstancePickerOverlay.swift:34-36,100-129` · dataflow.md「Passing data into views」+ structure.md「Keep view init cheap」。`combinedPlane` 每次 body 重跑 `subjectMask` CPU 读取 + `tintedImage` 重建 plane 级 RGBA 缓冲/CGImage。修复草图：以 selection 为键缓存 plane/CGImage（@State + onChange 重算）或下沉 model。
- [J17] major · `App/Sources/Lightamer/UI/Shell/Nodes/EditorNodesPanelView.swift:82-117` · structure.md「Always use separate View types」。600+ 行单失效边界（content/cards/Canvas 全 `private var/func`），grade mix live-tick 拖动下整链逐 tick 重估。修复草图：header/edgesCanvas/单卡各抽独立 View，窄输入。
- [J18] major · `App/Sources/Lightamer/UI/SidebarView.swift:182-206` · 同上。1000+ 行单失效边界（全 sections + 4 dialog + `.task(id:)` 同 body，`flatRows()` 重建连带）。修复草图：按 section 抽独立 View，dialog 状态下沉。
- [J19] major · `App/Sources/Lightamer/UI/FilterBarView.swift:45-82,86-202` + `App/Sources/Lightamer/UI/EditorAreaView.swift:61-328` · 同上。章节级 `private var` 计算属性共享父边界；EditorArea 主干 200+ 行内联 switch。修复草图：每节提窄输入 `struct`（如 `QuickFilterField(text:onChange:)`）。
- [J20] major · `App/Sources/Lightamer/UI/Inspector/MaskGroupsPanelView.swift:88-149` · 同上。`groupCard(_:)` @ViewBuilder 私有函数含 ForEach/分支且读 `editorState`，与父同边界。修复草图：抽 `MaskGroupCardView`，传显示字段 + masks + layerID/locked。
- [J21] major · `App/Sources/Lightamer/UI/Inspector/RetouchPanelView.swift:90-227` · 同上。7 个 `private var` 分区直读 `editingState`，任一工具量变化重估整个 Form。修复草图：工具区/列表区各抽独立 View，标量值 + 回调窄输入。

ForEach/软废弃 major：
- [J22] major · `App/Sources/Lightamer/UI/CatalogBrowserView.swift:81` · foreach.md「Keep the id cheap to hash」。`ForEach(Array(rows.enumerated()), id: \.element)` 以整行 struct 作 id 深哈希（已有 `row.id`/`pathHash` 稳定小 id）。修复草图：`ForEach(model.rows, id: \.id)`。
- [J23] major · `App/Sources/Lightamer/Export/ExportPanelView.swift:174` · foreach.md「Avoid collection indices as identity」。`ForEach(state.recipe.indices, id: \.self)` 作用可增删数组（L178/184），增删错位。修复草图：variant 稳定 id + `ForEach($state.recipe, id: \.id)`。
- [J24] major · `App/Sources/Lightamer/UI/FilterBarView.swift:192-196` · 同上。`ForEach(Array(enumerated()), id: \.offset)` 位置作身份。修复草图：`Rule` 加稳定身份键。
- [J25] major · `App/Sources/Lightamer/UI/EmptyStateView.swift:52-62` · soft-deprecated-apis.md（`View.overlay(_:)`/`View.background(_:)` → builder 重载）+ soft-deprecation.md review 节。修复草图：`.background {…} / .overlay {…}` trailing 闭包。

归一注：slice-01 的 CurveEditor `nodes.indices`（CurveEditorView.swift:44）降 minor（见 N-F3：tab 静态切换、无增删，harm 有限）；slice-04 的 `LightamerApp.swift:15-35` 手写 FocusedValueKey 升 major 未成立，维持 minor（见 N-D7：dataflow.md @Entry 节的"top-line finding"指代码评审回复格式，非 severity）。

## minor（127）

结构-计算属性分区分族（structure.md「Always use separate View types」）：
- [N-S1] `Export/ExportInspectorView.swift:37`（同形 L98/117/131/223/320/436/524/608/652/737, depthPicker L716）：五 section + toggle/knobs 全 parent computed，quality tick 重估整页。草图：每 section 抽窄输入 View。
- [N-S2] `Export/ExportNamingEditor.swift:53`（同形 L68/100/121/137/169/230）：presetPicker/tokenButtons 等单用 computed。草图：含 ForEach+Binding 的两节提窄输入子 View。
- [N-S3] `Export/ExportPanelView.swift:168`（同形 L210/258/322/384）：recipe/destination/postActions/queue 四节 computed（VariantEditor/JobRow 已抽取，好）。草图：queue/status 抽值参 + 回调 View。
- [N-S4] `Export/ExportQueueFaceView.swift:87`（同形 L142/163/178）：progressRow/errorSummary/faceRow computed/func。草图：`QueueRowView(row:onRetry:onCancel)`。
- [N-S5] `Library/Views/GlobalSearchDialog.swift:36`（同形 L64/79/106/205）：mode/input/apply/card computed/func。草图：按 mode 抽三输入 View。
- [N-S6] `Library/Views/LibraryInspectorView.swift:43`（同形 L73/100/118/167/218/289/321/387/441）：overview/group/activity/filter/actions/ai/smartAlbums 全 computed（FlowLikeChips 已独立，好）。草图：每节抽窄输入 View，`model` 不出 parent。
- [N-S7] `UI/Inspector/ChannelMixerRGBPanelView.swift:146-183`（mixSection/gainRow）、`ColorBalanceRGBPanelView.swift:275-309`（fourWaySection）、`ColorWheelsPanelView.swift:67-116`（wheelBlock）、`CurveEditorView.swift:99-110`（nodeHandle）：helper 工厂函数。草图：提 GainRow/MixSection/FourWaySection/WheelBlock/NodeHandle struct。
- [N-S8] `UI/Inspector/FilmicRGBPanelView.swift:134-171`（autoGrey/Black/WhiteButton 三 `private var`）。草图：`FilmicAutoKeyButton(kind:instance:edit)`。
- [N-S9] `UI/Inspector/HlsPanelView.swift:156-179`（@ViewBuilder targetHueRow）。草图：`TargetHueRow(hueBins:selectedBin:onSelect:)`。
- [N-S10] `UI/Inspector/LiquifyPanelView.swift:103-171`（warpTypePicker/strengthSlider/radiusSlider）。草图：`LiquifyNodeControls` 或三小 View。
- [N-S11] `UI/Inspector/LayersPanelView.swift:112,219-248`（toolbar/baseRow；LayerRowView 已独立，好）。草图：`LayersToolbarView`/`BaseLayerRowView`。
- [N-S12] `UI/Inspector/LuminanceColorRangePanelView.swift:70-93,175-228`（luminanceSection/colorSection 单次调用函数；bandSlider 五复用属允许小 helper，不管）。草图：抽两 section View。
- [N-S13] `UI/McpLauncherPanelView.swift:188,222,261`（header/statusLine/logPane）。草图：`LogPane(lines:followScroll:)` 等。
- [N-S14] `UI/Overlay/MaskOverlayHost.swift:112`（maskCanvas 方法含 Canvas 全量绘制）。草图：`MaskOverlayCanvas(forms:transform:)`。
- [N-S15] `UI/Overlay/MaskToolbarView.swift:67-68,220,262,338`（featherSection/followEdgesSection/aiGroup/depthGroup）。草图：各分区抽窄输入 View。
- [N-S16] `UI/Overlay/SegmentEditingOverlayHost.swift:180,197`（counterBadge/controlBar）。草图：`SegmentCounterBadge`/`SegmentControlBar`。
- [N-S17] `UI/PresetManagerWindow.swift:190`（row(_:) 函数）。草图：`PresetRow(preset:)`（List 行单根 HStack，unary 好）。
- [N-S18] `UI/SessionBrowserView.swift:110-426`（contextMenu/四 sheet/drop/filter/alert 全内联 500+ 行）。草图：菜单/对话框各抽 View（targets/pending 回调窄输入）。
- [N-S19] `UI/Shell/AdjustmentTransferView.swift:78,91,154,203,259`（header/sourceSegment/node/item/versionPane）。草图：三窗格各抽 View。
- [N-S20] `UI/Shell/BackgroundTaskBarView.swift:95,125,280`（rowView/agentRowView/agentActivityList @ViewBuilder 方法）。草图：`BackgroundTaskRow(descriptor:handle:)` 等。
- [N-S21] `UI/Shell/ColorMatchPanelView.swift:58,98,110,175,221`（content/solverPicker/reference/solve/readoutSection 传 model 方法）。草图：各区抽 View 读窄字段。
- [N-S22] `UI/Shell/EditorAdjustmentStackView.swift:125,214,258,303,443`（tabBar/pageRows/groupShell/selectedPanelBody/row 方法组装；panelView 回 AnyView 非 ForEach 行可不计）。草图：页/组/行按路由抽 View。
- [N-S23] `UI/Shell/EditorToolRailView.swift:76-95,99-162,171-209`（buttons/panel/historyPanel/historyRow）。草图：`RailButtons`/`HistoryPanel`。
- [N-S24] `UI/Shell/EditorWorkspaceShellView.swift:126-162`（filmstrip/rightPane/scopeSlot/stackSlot）。草图：右栏抽 `RightPane`（filmstrip 已独立，沿用）。
- [N-S25] `UI/Shell/FilmPanelView.swift:71-90,94-115`（AR-01 后残留 header/enableEntry）。草图：`FilmPanelHeader`/`FilmEnableEntry`。
- [N-S26] `UI/Shell/VersionsPanelView.swift:97-127,131-178,182-214,239-326`（header/emptyState/versionList/row）。草图：header/row 独立成类型。
- [N-S27] `UI/Views/EnhanceDialog.swift:89-120,149-208`（controls/modelStatusRow/progressArea，phase tick 连带两预览窗）。草图：按 choice/phase 窄输入拆类型。
- [N-S28] `Yiyin/YiyinPanelView.swift:104-345,361-429,447-668`（双 section + N 模板行 + templateEditor/fontSetting 全同边界）。草图：borders/watermark/单模板行各抽类型。

init/body 高代价族（structure.md「Keep view init cheap」）：
- [N-I1..15] 面板 init 内 `(try? instance.params(of:))` / `PanelEditing.params(of:)` JSON 解码（params 小 struct，minor）：Dehaze:24；DenoiseProfile:53；Equalizer:25；Exposure:28；FilmicRGB:31；Flip:30；GradeScalarPanels:35,112,169,226,284,342（六面板）；Grain:26；HighpassSoften:28-29（双分支无条件双解码只用其一，另见草图按 opName 单解）；Hls:32；Lens:37；Levels:25；Liquify:36；LocalContrast:23；Lut:39。另 slice-01 同形 11 处：AgX:23-27、Bilateral:28-32、Bloom:20-24、ChannelMixer:21-25、ChannelMixerRGB:28-32、ColorContrast:18-22、ColorWheels:29-33、ColorZones:36-40、Crop:26-30、Ashift:29-33、Colisa:18-22。草图：Provider/Inspector 侧备好 Params 传入或模型层缓存（保持 seam 可接受）。
- [N-I16] `UI/SettingsView.swift:97-105,108`：detail switch 内联构造 LCR/ACASettingsModel（闭包捕获 + 新实例，选中页期间每 body 重建）。草图：model 提升 @State 懒建或 key 化缓存。
- [N-I17] `UI/Views/EnhanceDialog.swift:225,244-269`：`previewPane` body 期同步 `displayImage`（逐像素 uint16 循环 + CGImage 分配）。草图：model 侧缓存 NSImage（frame 变更一算）。
- [N-I18] `UI/SoftProofControlView.swift:39,45,120-126`：`recentEntries`（filter+firstIndex sort）与 `installedProfiles()` 磁盘枚举每 body 执行两次。草图：`.task` 一次装载到 @State。
- [N-I19] `UI/Shell/WorkspaceHostView.swift:1642-1644` 同族另见本地化 N-L16。

数据流族（dataflow.md）：
- [N-D1] `Library/Views/LibraryGridView.swift:297`（dataflow.md「Pass views only the data they read」）：`LibraryGridCellView` 取整行 `LibraryImageRow` 值类型，仅读 id/rating/filename/imagePath。草图：改传四窄参或 per-view 小 struct。
- [N-D2] `UI/Overlay/MaskToolbarView.swift:120-123,136-141,231-234,263-268,737-741`（dataflow.md「Use KeyPath bindings」）：对 @Environment Observable 大量闭包式 `Binding(get:set:)`（每 body 分配）。草图：`@Bindable var b = editingState` 后 `$b.followEdgesParams.mode` 投影。
- [N-D3] `UI/Shell/AdjustmentTransferView.swift:131-150`（同上）：`sourceBinding` 闭包式 Binding。草图：模型下标投影或 @Bindable 化。
- [N-D4] `UI/Shell/ColorMatchPanelView.swift:150-153,196-198`（同上）：weight/strength 闭包式 Binding。草图：@Bindable/下标投影。
- [N-D5] `UI/Shell/ColorMatchPanelView.swift:91-93`（dataflow.md「Isolating onChange」）：`.onChange(of: instance)` 仅副作用却挂含 ScrollView 的 content 作用域。草图：抽专用 ViewModifier。
- [N-D6] `UI/Shell/EditorAdjustmentStackView.swift:94-98,104-108`（同上）：两 `.onChange`（pendingTabRoute/activeLayerID）仅副作用落 whole-stack body。草图：各抽轻量 ViewModifier。
- [N-D7] `UI/LightamerApp.swift:15-35`（dataflow.md「@Entry macro」）：`LightamerColumnVisibilityKey`/`ExportPanelRequestKey` 手写 FocusedValueKey 样板。草图：`extension FocusedValues { @Entry var … }`（macOS 15+，一行 caveat）。
- [N-D8] `UI/LightamerApp.swift:1761`（dataflow.md「Isolating onChange」）：`.onChange(of: loadedImageURL != nil)` one-shot toast 挂 Window 内容链。草图：抽轻量 modifier 持有 Bool 依赖。
- [N-D9] `UI/Shell/EditorWorkspaceShellView.swift:106-109`（同上）：`.onChange(of: selectedIDs)` 挂重型 shell body。草图：仿 `PendingAIEnhanceModifier` 下沉 ViewModifier。
- [N-D10] `UI/Shell/Nodes/EditorNodesPanelView.swift:93`（同上）：`.onChange(of: document?.nodes.map(\.id))` 挂重型 canvas body。草图：下沉 ViewModifier（与 J17 同批）。
- [N-D11] `UI/Shell/FilmPanelView.swift:124-285,295-441,451-664`（dataflow.md「Expose struct fields」+「Cache derived values」）：三 section 以整 `model` 输入经 `model.record` struct 读多字段，任一 history 写入全重估。草图：高频读面上提 model 独立存储属性（didSet 对齐）。
- [N-D12] `UI/Shell/RawDecodePanelView.swift:37,258,265`（dataflow.md「View-local state」）：`isReloading` 只写不读（同步连写同 runloop 合并，置位永不可见）。草图：删状态；真 busy face 改异步可观察态。
- [N-D13] `UI/Shell/WorkspaceHostView.swift:622-692` 升 obs（见 O-38：host 重估稀少，闭包字段比较影响待 Instruments 确认）。
- [N-D14] `UI/Shell/EditorToolRailView.swift:199,280-284`（foreach.md「Don't sort or filter inline」+ dataflow.md「Cache derived」）：`historyRows`（enumerated/reversed/map）每 body 重建。草图：history 侧缓存 newest-first 数组。
- [N-D15] `UI/SidebarView.swift:632,722-725,736-746`（同上）：`flatRows()` 每 body 重建 + `moveToMenu` 内联 filter + `depthPrefixedName` 逐行建表 O(n²)。草图：tree 侧缓存展平/深度表。
- [N-D16] `UI/PresetManagerWindow.swift:44-57`（同上）：`grouped` 每 body 全量 `Dictionary(grouping:)` + 排序。草图：分组下沉 store 缓存。
- [N-D17] `UI/InspectorView.swift:224,233`（同上）：`addFaceEntries.filter` 内联 ForEach 参数。草图：抽 developEntries/compatEntries 预分组。
- [N-D18] `UI/Inspector/PresetPanelView.swift:138-150`（同上）：`categorySections` 每 body `Dictionary(grouping:)+sorted`。草图：随 developPresets 缓存（N 小，次要）。

ForEach 身份族（foreach.md）：
- [N-F1] `Library/Views/LibraryInspectorView.swift:111`（同形 L254/260/527）：group rows/ftsTerms/structuredTerms/arm chips 四处 `id: \.offset`（行无状态 Button，harm 有限）。草图：group 用 `label+day` 稳定键，terms 用自身，chips 用语义键。
- [N-F2] `UI/Inspector/EqualizerPanelView.swift:49`：`ForEach(0..<bands.count, id: \.self)`。草图：bands identifiable 化（`id: \.key`）。
- [N-F3] `UI/Inspector/CurveEditorView.swift:44`：`ForEach(nodes.indices, id: \.self)`（tab 静态切换、无增删， harm 有限，major→minor）。草图：Node 引稳定 id，`ForEach(nodes)`。
- [N-F4] `UI/Inspector/HlsPanelView.swift:159`：`ForEach(0..<binCount, id: \.self)`（8 bin 静态）。草图：以 hueBins 值作 id。
- [N-F5] `UI/Inspector/LiquifyPanelView.swift:52`：`ForEach(params.paths.indices, id: \.self)`（动态增删但 `clampedSelection` 兜底、无 @State）。草图：元素稳定 id 或维持钳位 + obs 跟踪。
- [N-F6] `UI/Overlay/MaskToolbarView.swift:404,418`（foreach.md「Identity must outlive」）：`.popover(item:)` 的 `AIInstanceCatalog.id` 为内容派生有损哈希（reduce 相加，不唯一、内容变身份变）。草图：picker 会话分配持久 UUID 作 item id。
- [N-F7] `UI/PresetManagerWindow.swift:179`（同上）：`ForEach(grouped, id: \.category)` 以可改名 category 作 section id（section 无内部 state，影响可忽略）。草图：后续 section 持展开态再换稳定 id。
- [N-F8] `UI/Inspector/PresetPanelView.swift:132-136`（foreach.md stable+unique）：`CategorySection.id = category ?? ""`，空白分类 trim 后与未分类 nil 碰撞。草图：`category ?? "\u{0}uncategorized"`。
- [N-F9] `UI/Shell/FilmPanelView.swift:138,154`：`ForEach(filmStocks, id: \.info.stock)` id 为 Optional，缺 stock 在 `""` tag 碰撞。草图：收紧非空类型或 Identifiable 包装。
- [N-F10] `UI/Shell/FilmstripView.swift:219`（foreach.md「Prefer Identifiable」）：`ForEach(grid.rows, id: \.id)` 显式 key path，自有类型 `LibraryImageRow` 应补 `Identifiable`。草图：加 `Identifiable`，调用点去 `id:`。
- [N-F11] `UI/Inspector/LutPanelView.swift:82`：`.id(libraryRevision)` 每次 rescan 重建整 tree，`@State collapsedGroups` 清零丢折叠态。草图：折叠态上提 `.id` 边界之上或 rescan 走内部 revision。

本地化族（localization.md）：
- [N-L1] history label eager 解析族（localization.md「LocalizedStringResource for Non-View Types」：提交瞬间解析存 HistoryItem，locale 切换不跟随；逐文件首处）：Dehaze:38（+50,64）；DenoiseProfile:109（+134,146,158,170,182,194,206,346）；Equalizer:59（+90）；Exposure:43（+55,123）；FilmicRGB:46（+60,74,88,199）；Flip:70；GradeScalar:51（+67,95,127,153,185,210,240,267,297,324,358,387）；Grain:41（+54,67,95）；HighpassSoften:45（+58,76,89,101,115,143,159）；Hls:188-190（`historyLabel` computed 每 body 解析）；Lens:62（+75,87,99,111,124,136,220）；Levels:97（+140）；Liquify:140（+168,189）；LocalContrast:38（+56,69,99）；Lut:261。草图：`endEditing/applyDiscrete` 的 `label:` 改 `LocalizedStringResource`，推迟到历史渲染时解析。
- [N-L2] `UI/Inspector/LightamerSlider.swift:20`（localization.md「Localizing Variables」）：`label: String` 迫使调用方先 eager 解析（全仓约 40 处 label 根因）。草图：`label` 改 `LocalizedStringResource`，内部 `Text(label)`。
- [N-L3] 面板 `label: String(localized:)` 即时解析无视 `\.locale` 覆盖（AgX:33-132、Bilateral、Bloom、Colisa、Crop、ColorContrast 等全部 LightamerSlider 调用点；与 N-L2 同根，需跨文件协调）。草图：调用点传字面量（待 N-L2 改型）。
- [N-L4] `UI/Inspector/LightamerSlider.swift:134-136`（localization.md「Formatting」）：readout `String(format: readoutFormat + unit, value)`。草图：`Text(value, format:)` 或 `String(localized:)` 插值。
- [N-L5] `UI/Inspector/DenoiseProfilePanelView.swift:299-309`：`profileValueString` `String(format: "ISO·EXIF a₁ %.3g b₁ %.3g")` 硬编码上屏。草图：`String(localized:)` 插值或字面量插值 + comment。
- [N-L6] `UI/Inspector/LuminanceColorRangePanelView.swift:202-204`：`Text(String(format: "Cz %.3f hz %.2f"))`。草图：`Text("Cz \(cz, format: .number…) hz …")`。
- [N-L7] `UI/Inspector/LensPanelView.swift:44,169`：`Text(String(localized:))` 经 String 中转丢 locale 上下文（同文件其余 `Text("key")` 合规）。草图：字面量直传。
- [N-L8] `UI/Inspector/LayersPanelView.swift:43-63,316,325`：`blendLabel(_:) -> String` eager 解析，调用处 `Text(StringProtocol)` 不再本地化。草图：返回 `LocalizedStringResource`。
- [N-L9] `UI/Inspector/LayersPanelView.swift:597`：`Text("\(count)")` 纯数字作 LocalizedStringKey。草图：`Text(verbatim:)` 或 `Text(count, format: .number)`。
- [N-L10] `UI/Inspector/LutPanelView.swift:248,254`（localization.md「String Interpolation vs Concatenation」）：`String(localized:) + " " + name/error` 拼接组句。草图：单字面量插值。
- [N-L11] `UI/Inspector/RetouchPanelView.swift:294-302,207`（同上）：`strokeLabel` `"\(algorithm) \(center)"` 组装行文本再进 `Text`。草图：行内 HStack 双 Text 或单字面量插值。
- [N-L12] `UI/Inspector/RetouchPanelView.swift:307-309`：`centerString` `String(format:)` 用户可见读数。草图：`String(localized:)` format（纯技术读数则注记保留）。
- [N-L13] `UI/Inspector/MonochromePanelView.swift:184`：`.accessibilityLabel(Text("monochrome color wheel"))` 硬编码英文自然句（工程 opaque-key 惯例）。草图：`"monochrome_wheel_label"` opaque key 进 catalog。
- [N-L14] eager-`String(localized:)` 可改字面量组（显示正确，仅丢 locale 覆盖）：SkinSmooth:122 Toggle；Vignette:174-176 `discreteToggle(title: String)` 签名迫解析；PastePartialDialog:109,113,118,120 Button + :136 Picker；PresetPanel:95 Label + :111 Button。草图：调用点传字面量（Toggle/Button/Label/Picker 皆有 LocalizedStringKey 重载），`discreteToggle.title` 改型 `LocalizedStringKey`。
- [N-L15] `UI/Overlay/MaskOverlayHost.swift:535`：`String(localized: LocalizationValue(commitLabelKey))`（commitLabelKey 已显式 switch，但字面量调用点不可见）。草图：每臂直接返回 `String(localized:"history_mask_brush")` 等静态调用。
- [N-L16] `UI/Shell/EditorAdjustmentStackView.swift:273`：`Text(String(localized: LocalizationValue(note)))` 运行时 note 查表。草图：note 建模显式 switch/`LocalizedStringResource`。
- [N-L17] `UI/SessionBrowserView.swift:317-318`：`Text(String(localized: LocalizationValue(mode.pickerKey)))`（pickerKey 已显式 switch，调用点仍运行时解析）。草图：每臂直接返回静态 `String(localized:)`。
- [N-L18] `UI/Overlay/SegmentEditingOverlayHost.swift:170,253-260`（localization.md「String Interpolation vs Concatenation」）：`budgetNotice = "\(error)"` 与 `"key" + " (\(error))"` 拼接组句。草图：单静态 key + 占位插值。
- [N-L19] `UI/PresetManagerWindow.swift:158`（同上）：`Text(String(localized:) + " " + name)`。草图：`Text("preset_delete_message \(name)")`。
- [N-L20] `UI/Overlay/MaskToolbarView.swift:238,764`（localization.md「Formatting」）：`String(format:"%.0f"/"%.2f")` 读数。草图：`Text(value, format:.number.precision(...))`。
- [N-L21] `UI/Shell/ColorMatchPanelView.swift:156,211`（同上）：weight/strength `String(format:"%.2f")`。草图：format-style Text。
- [N-L22] `UI/Shell/EditorNodeHeaderView.swift:94,100,107,109`（同上）：焦距/光圈/快门 `String(format:)` 硬编码单位语序。草图：Measurement/FormatStyle，单位语序入 catalog。
- [N-L23] `UI/Shell/FilmPanelView.swift:187-199`（同上）：slider readout `String(format:"%.2f"/"%+.2f EV")`。草图：`Text(value, format:)` + 单位可本地化片段。
- [N-L24] `UI/Shell/Nodes/EditorNodesPanelView.swift:456`：`Text("\(Int(…))%")` 尾随裸 `%`，合成 `%lld%` 尾为不完整转换符。草图：`Text(mixValue, format: .percent…)` 或数字与 `%` 分 Text。
- [N-L25] `UI/Shell/RawDecodePanelView.swift:86-89,154,187-188`：`Text("RAW 8"/"RAW 9")` 技术专名未 verbatim；`Text("\(Int(peak)) nits")` 单位硬编码；`transferName` 的 `String(localized:) + String(format:)` 拼接。草图：版本名 `Text(verbatim:)`；peak/gamma format-style 单字面量。
- [N-L26] `UI/Shell/WorkspaceHostView.swift:1642-1644` + `Library/LibraryProjectController.swift:649`：`"未知"` Swift 硬编码中文（pidText 回退；英文 locale 残留中文）。草图：抽 `project_read_only_unknown_pid` 键插值。
- [N-L27] `UI/Shell/AdjustmentTransferView.swift:307` + `Library/Views/LibraryInspectorView.swift:445` + `Library/Views/RelinkSheetView.swift:111`（localization.md「Casing」）：运行时 `.textCase(.uppercase)`。草图：大小写 baked 进 catalog 源文，删 `.textCase`。
- [N-L28] 数字/单位硬编码家族代表（localization.md「Formatting」）：ExportInspectorView:659 `"\(Int(q*100))%"`；同形 ExportPanelView:652、ExportQueueFaceView:147、ExportPanelView:395、LibraryAutoStackDialog:45、CatalogFilterBarView:242（`"\(Int(gap)) s"`/`"\(Int(v)) mm"`）。草图：百分比 `.percent`/`Text(value, format:)`，单位进带占位注释 format 键。
- [N-L29] `Library/Views/LibraryInspectorView.swift:196` 同族另见 N-L34；`CatalogBrowserView.swift:225,238` + `CatalogFilterBarView.swift:209,217,233,241`：评分/色标/ISO/焦段 `Button("\(n)")` 纯数字作 LocalizedStringKey。草图：`Button { } label: { Text(verbatim: "\(n)") }`。
- [N-L30] `UI/LightamerApp.swift:1867,1871,1888,1902,1907,1911`：用户面菜单项 `Text(verbatim:)` 硬编码英文（注释称 zh 随 M2-3，已知缺口仍记）。草图：换静态 key + zh/en 入 catalog。
- [N-L31] `UI/CullingView.swift:269`：`Text(pane.id)` 路径串应显式 opt-out。草图：`Text(verbatim: pane.id)`。
- [N-L32] `Export/ExportPanelView.swift:663`：depthPicker `Text(labels[index])`（StringProtocol 重载本不本地化，应显式意图如 Inspector L726）。草图：`Text(verbatim:)`。
- [N-L33] `Library/ImportModeDialog.swift:151` 家族代表（localization.md「Layout」勿硬编码文本框宽）：对话框 `.frame(width: 440/340/430/460/…)` 定死（同形 Relink:83、GlobalSearch:49、AutoStack:92、NamingEditor saveSheet:254 300pt、ExportPanel saveSheet:151 320pt、ContentView:497 modePicker maxWidth 240、FilterBar:422 maxWidth 130、EditorArea:593 width 140）。草图：改 minWidth + 关键行 `ViewThatFits`（HStack→VStack 降级）。
- [N-L34] 固定磅值家族（localization.md text styles）：SettingsPages:716（同形 L737/763/1273/1280/1082）、CatalogBrowserView:301/376、LibraryInspectorView:196、EDRControlView:53/70/75、EmptyStateView:24（size 28/64）。草图：caption/callout/largeTitle + `.monospaced()`/`.monospacedDigit()`。
- [N-L35] 内插键译者注释缺失家族（localization.md「Comments for Translators」）：ExportQueueFaceView:128（同形 L168/205、AutoStack:60、LibraryGridView:148/374、CatalogFilterBarView:152、SettingsPages:504/521/1449）、VersionsPanelView:71-76（`"Version \(ordinal)"`）、SidebarView:371-375（三占位 session_counts）、各面板 `Text("panel_*")` 表头/Picker 项 + `chipLabel` 各分支（FilterBar:228-267）。草图：逐内插键补 `comment:`（占位按位置说明）或 catalog Comment 字段二选一单源。
- [N-L36] `UI/Views/EnhanceDialog.swift:20-270` 全文件中文裸字面量（与 Shell 系 opaque key + defaultValue 惯例分叉；裸字面量可提取但源语言/审核口径分叉）。草图：引 `enhance_*` opaque 键 + 中文 `defaultValue`。
- [N-L37] `Export/ExportInspectorView.swift:504` 技术专名（DRT rawValue/space rawValue）verbatim 合规，不记（肯定项）。

KD-4/@AppStorage minor：
- [N-K1] `UI/ContentView.swift:100`（同形 L110/166-168、InspectorPageMount L757、SettingsPages:1214-1221 MCP 四键）：布局/模式/MCP 开关经 `@AppStorage` body 直读标准 defaults（行为正确、惯用形态，minor）。草图：迁入注入 store（MCP→McpServerController；布局→CatalogPreferencesModel 类 faces）。

## obs（44）

手势/D-H1/副作用（需运行时验证）：
- [O-1] `UI/Inspector/ColorBalanceRGBPanelView.swift:385-398`：hue-disc 以 `translation == .zero` 判首 tick 并 `onBegin()`，快拖首帧非零漏 begin。草图：本地 `@State dragging` 哨兵配对。需运行时验证。
- [O-2] `UI/Inspector/CurveEditorView.swift:114-132`：`DragGesture.onEnded` 未覆盖取消路径时 `dragStarted` 常真，下次漏 `onBegin`。草图：哨兵改 `.updating` 或取消路径复位。需运行时验证。
- [O-3] `UI/Inspector/MonochromePanelView.swift:167-182`：wheel `translation == .zero` 触发 `onBegin()` + `DragGesture(minimumDistance: 0)` 与 `:182 onTapGesture(count: 2)` 手势吞没双击风险。需运行时验证。
- [O-4] `UI/Inspector/LuminanceColorRangePanelView.swift:336-343`：`bandSlider` 仅 `onEditingChanged(false)` 提交 leg，无 drag-begin leg。草图：确认 `commitMaskEdit` 单调用即一 item 且 live 无残留。需运行时验证。
- [O-5] `UI/Inspector/LightamerSlider.swift:87-130`：readout scrub `DragGesture(minimumDistance: 3)` 与行级双击重置手势竞态（3pt 死区注释断言）。草图：真机验证双击必重置、短拖必扫值只落一 commit。需运行时验证。
- [O-6] `UI/Inspector/TextOverlayPanelView.swift:61-87`：`ColorPicker` selection setter 直 `applyDiscrete`，拖动期 history 条目数取决于 setter 频率。需运行时验证。
- [O-7] `UI/Overlay/LiquifyOverlayHost.swift:142-152`：`.onEnded` 从捕获 record 重解码提交，若末 tick live 未 ARM 丢末笔（CropOverlayView 有 lastLive 兜底，此处 `_ = target` 空转）。草图：仿 Crop 引 lastLive。需运行时验证。
- [O-8] `UI/Shell/RawDecodePanelView.swift:224-232,254-266`：`sliderRow` Binding.set 每 tick 即 `commit()`（设计注释），无 live/commit 分 leg。草图：若卡顿/泛滥仿 FilmPanel 引 begin/end。需运行时验证。
- [O-9] D-H1 面板通用（Monochrome:30-34，NLMeans/Shadhi/Sharpen/Sigmoid/Temperature/TextOverlay/ToneCurve/ToneEqual/Velvia/Vibrance/Vignette/SkinSmooth 同形）：`set` 从 init 快照 `params` 拷贝单字段后 `edit.update`，跨源交错（拖动中外部 preset 落定）是否丢字段。需运行时验证拖动中实例回传时序。
- [O-10] 各面板 `params` init 快照多 tick 基（AgX:143-149、Bilateral:87-95、Bloom:80-86 等）：一次拖拽多 tick 以初始快照为基，连续跨 slider 是否丢中间值取决于 Inspector 重建时序。需运行时验证。
- [O-11] `UI/EditorMTKView.swift:153-158`：`updateNSView` 内 `viewportState.noteGeometry(...)` 写模型，更新期副作用或循环重绘。草图：相等守卫或搬几何事件。需运行时验证。
- [O-12] `Library/Views/LibraryGridView.swift:184` + `UI/Shell/FilmstripView.swift:196-215,240-246`：双 `.onTapGesture`（单击 + `count: 2`）并存，双击是否连带触发单击语义。草图：单击改 `simultaneousGesture` 排他或 `exclusively(before:)`。需运行时验证。
- [O-13] `UI/Shell/FilmstripView.swift:196-215`：`model` nil 到 `onAppear` 才建，首帧非空仍走 emptyState（一帧闪空）。草图：init 注入 `State(initialValue:)`。需运行时验证。

环境/focus/订阅：
- [O-14] `UI/InspectorView.swift:376-385,428-430`：`MetadataFieldFocusedKey.Value = Binding<Bool>`，body 每次重建 `Binding(get:set:)` 写 `.focusedSceneValue`（environment.md 闭包比较节；FocusedValues 仅随焦点传播或抵消）。草图：typing 期失效实测。需运行时验证。
- [O-15] `UI/InspectorView.swift:211`（及 EditorState:909）：`ForEach(addFaceEntries)` 依赖 `AdjustmentAddEntry.id == template.opName` 全局唯一；grade 目录同 op 多条目即重复。需运行时验证多实例目录行为。
- [O-16] `UI/Shell/WorkspaceHostView.swift:248-252,1436-1522`：app-root sheet（`YiyinTopBarSheet`，gate=false shell root 属 app-root Scene 层）内容经裸 `@Environment(EditorState/PipeCoordinator.self)` 继承，未走重注入/init 二选一；实机可用，记 obs 不记 violation。草图：sheet 闭包补 `.environment(...)` 显式重注入后实机验证。
- [O-17] `UI/Overlay/MaskToolbarView.swift:181-208`：sheet 内容依赖 presenter 继承 @Environment（Settings/toolbar 层级 sheet，非 app-root Scene 层，M2-8-3 规则不触发）。无需改。
- [O-18] `UI/SidebarView.swift:114-115,178-180`：`@AppStorage(organizationModeStorageKey)` body 直读（KD-4 字面耦合；与 ContentView 同 key 双点存放，冷启动覆写链保证语义；迁移改覆写链，记 obs）。草图：持现；收敛则覆写 + 订阅收进单一注入 store。
- [O-19] `UI/McpLauncherPanelView.swift:98-100`：`UserDefaults.standard` 直读在 model 动作（launch）非 body，KD-4 合规；与 SettingsView @AppStorage 同 key 拼写。现不动。
- [O-20] `Settings/SettingsPages.swift:925`：`effectiveCombo/conflicts` 用 `_ = overridesTick`/裸读制造观察依赖（fragile，重构易断）。草图：版号做 preferences @Observable 发布属性显式读投影。
- [O-21] `Library/Views/RelinkSheetView.swift:218`：`progressSection` 读 `handle.snapshot`，RelinkTaskHandle 变更驱动静态不可见（普通 class 则进度不刷新）。草图：handle @Observable 或 Task 轮询。需运行时验证。
- [O-22] `Settings/SettingsPages.swift:1142`：`SettingsDisplaysPage` body 采样 `NSScreen.screens`（非 observable，插拔不刷新）。草图：订阅 `didChangeScreenParametersNotification` 改写 @State。需运行时验证。
- [O-23] `UI/Shell/WorkspaceModel.swift:173-176`：`currentRow` 每次 `rows.first(where:)` 线性扫（10k 行 × task 频率；现仅 task 路径消费）。草图：profiler 确认再缓存 id→row 索引。
- [O-24] `UI/Shell/ScopePanelView.swift:213-242`：`readWaveform` 在 view `.task`（main actor）同步 `getBytes`（≤553KB、≤15Hz）。草图：搬后台或采样节流持现。需运行时验证。
- [O-25] `State/InspectorState.swift:242`：`beginEyedropper` 直接覆盖 `eyedropperHandler`（连续 arm 丢首 handler；complete/cancel 配对完整）。草图：begin 时已 active 则先 complete 旧值或断言。需运行时确认是否重复 arm。
- [O-26] `Library/ImportModeDialog.swift:99` + `Export/ExportInspectorView.swift:34`：init 期自建标准-suite（`ImportDefaults()`/`NamingTemplateStore()`）非接受注入（body 零直读，不判 KD-4 违规）。草图：init 参数可覆写 defaults/store。
- [O-27] `UI/Overlay/MaskOverlayHost.swift:81-83`：`layer` 经 `selectedLayer(in:)` 整列传递读（overlay 必需依赖；Canvas draw-only 好）。现不动；高频抖动再窄投影。
- [O-28] `UI/Overlay/SegmentEditingOverlayHost.swift:50`：`session` 整值读取后多字段使用（dataflow.md「Multiple individual reads are fine」）。现不动。
- [O-29] `UI/Shell/DrtPanelView.swift:156,186,280,315`：四分區独立（模范）但各读 `model.record.*` 同 struct 属性（面板自编辑可接受）。现不动。
- [O-30] `UI/Inspector/RetouchPanelView.swift:28`：整 `RetouchLayer` 值类型输入逐字段比较（strokes 个位数，成本可忽略；dataflow.md「Watch the cost」）。暂不处理。
- [O-31] `UI/Overlay/CropOverlayHost.swift:83-85` / `CropOverlayView.swift:205-213` / `LiquifyOverlayHost.swift:50-53`：body 内联 `record.params(of:)` 解码（小 struct，静态无法定量）。草图：profiler 热点再上提缓存。

跨 slice/类型设计/组织：
- [O-32] `UI/CatalogFilterBarView.swift:185`：`Text(FilterBarView.chipLabel(for:))` 返回已本地化串还是原始键（slice-01 确认 chipLabel 各分支静态字面量 + 值插值，属 format-string 形态，PASS；缺 comment 见 N-L35）。跨 slice 对账关闭。
- [O-33] `UI/Inspector/IOPPanelProvider.swift:44-47`：provider 以 `AnyView` 擦除 20+ 面板类型（op 切换语义全换，重建不可避免）。草图：保持现状（去擦除收益小）。
- [O-34] 全面板 `let instance: ModuleInstance` 宽输入：dataflow.md 窄输入规则下任何 record 字段变化全失效，但 record-identity 即 D-H1 变更信号，窄化破坏"commit 后换 identity 即重读"语义，有意 tradeoff。维持现状；profiler 指向再传 `(params, version)` 窄对。
- [O-35] `UI/Inspector/LutPanelView.swift:304-319,368-381`：tree `groups.filter` 内联 + 每行 `displayName` 碰撞扫描 O(R·G·K)（库规模小可忽略）。草图：`libraryGroups` 处一次算 displayName 字典。
- [O-36] `UI/Shell/WorkspaceHostView.swift:856-1256,1308-1684`：单文件 1837 行寄宿 coordinator + 5 sheet/dialog + 2 mount + 4 modifier（均为独立类型，失效边界不受影响，仅组织成本）。草图：按域拆文件，零行为差。
- [O-37] `UI/Shell/WorkspaceHostView.swift:622-692`：`WorkspaceTopBar` 三 `() -> Void` 闭包每 host body 重建（host 重估稀少，影响待确认；dataflow.md「Passing data」）。草图：持现；热点再收敛 action enum。
- [O-38] `UI/CullingView.swift:55,255`：`.transition(.opacity)` 无配套 `.animation(value:)`（切换是否动画真机确认；animations.md transition 依赖显式 animation）。草图：配 `.animation(..., value:)` 或确认即时切换即预期。需运行时验证。
- [O-39] `.font(.system(size:weight:))` 疑似命中 soft-deprecated-apis.md L314-315，但替换签名与现调用字面相同，需对照 SDK 头确认（soft-deprecation.md「以 header 为准」）。不做替换，先记 obs。
- [O-40] 全 slice 单字母徽标（CatalogBrowserView:285 `badge("E"/"P"/"X")`）：设计语言还是本地化债务静态不可判。另 xcstrings 尾块纯插入纪律无静态证据（需 git 历史），一并记 obs。
- [O-41] `UI/ContentView.swift:210` legacyBody（M2-2-4 门控 byte-frozen）：其内大 body/多 computed 按冻结纪律不可动，结构 finding 均不指向该分支。备查。
- [O-42] `Yiyin/YiyinPanelView.swift:527`：`Button(field.zhName)` zh-only 面（API 名已显式限域；英文 locale 中文残留属产品决策）。草图：持现或补 enName。
- [O-43] `UI/LightamerApp.swift:507-1661`：主 Window 内容链单表达式 ~20 `.environment` + 串行 `.task` 装配闭包（可读性/耦合重，无失效错误；App lifecycle 层按壳交接照记、不作阻断）。草图：装配闭包按域分组抽方法。
- [O-44] 壳交接照记：slice-05 无 App lifecycle 层代码（无 @main/Scene 委托），19 文件全 window-content 层；既定方向无新增阻断点。EditorMTKView.swift:33 `NSViewRepresentable` 同属观察项，不提迁移要求。

## 合规确认（肯定项，防误报）

- 显式 switch 静态键（V14 纪律合规）：`mode.labelKey`（ExportInspectorView:546）、`titleKey`（ExportPanelView:495/536）、`sortLabel(for:)`（FilterBarView:439-448）、`SortKey.label`（ContentView:491）、`pickerKey`（SessionBrowserView:81-84）、`SizingMode.labelKey`（ExportInspectorView:1065）、`FaceState.labelKey`（ExportQueueFaceView:54）、rating/color 显式 switch（LightamerApp）、`colorspaceLabel` switch（Lut）、DRT 静态 switch 解析；抽查键（export_format_jpeg/avif、export_sizing_original/long_edge、filter_chip_rating_3、sort_key_filename、preset_apply、mask_tool_brush/gradient/followEdges、mask_overlay_style_translucent/rubylith/onBlack、mask_command_* 全族、latitude_share_value `%@ %lld%%` 双语）在 catalog 在册。
- `LocalizationValue(variable)` 包裹显式-switch-静态字面量（SidebarView:151,155,548-550、YiyinPanelView:303,411）：非房规禁止的 `"prefix_\(x)"` 拼 key 形态，合规（仅双重包装可简化）。
- verbatim 正确 opt-out：`ImportModeDialog:110/119/202`（包已解析串）、技术标识（ExportInspectorView:504 DRT rawValue/space rawValue、depth labels）、`InspectorView.swift:726`。
- 裸字面 `Text("export_preset_none")`、`ContentUnavailableView Label("filter_empty_results")`：字面直传即 LocalizedStringKey，PREFER 形态且键在册。
- `.task(id:)` + stale-guard 合规：LibraryGridView:393、AutoStackDialog:93、CatalogBrowserView:346、SessionBrowserView cell task。
- `State(initialValue:)` init 播种合规（state-macro.md sanctioned 形态）：ImportModeDialog:96-99、EnhanceDialog init、EditorNodesPanelView init。
- disable-not-unmount 合规：ImportModeDialog:149、LibraryInspectorView:382、EditorAdjustmentStackView 容器级 `.disabled(agentControl)`。
- D-H1 三件套配对完整：全部 `LightamerSlider` 调用点（beginEditing/update/endEditing）、CropOverlayView lastLive 末笔兜底（模范）。
- `AnyShapeStyle` 三元（SegmentEditingOverlayHost）：modifiers.md 模范。
- `defaultValue` 双语 key（BackgroundTaskBarView）、`String(localized:defaultValue:)` 兜底（InspectorView:220）：本地化模范。
- `panelView` 回 AnyView（EditorAdjustmentStackView）非 ForEach 行，不计（foreach.md AnyView 节仅约束 List 行）。
- KD-4：slice-01/02/03 零 UserDefaults/@AppStorage 直读 PASS；`legacyLibraryEnabled` 装配点求值一次（LightamerApp:2480-2546，KD-1 合规）；`YiyinSheetMetrics` 注入式为 KD-4 范例；`YiyinSheetSizing` 纯数学 + @Observable 模型 PASS。
- SettingsView legacy gate 装配点注入为 KD-1 模范；pageSession 缓存（EditorAdjustmentStackView）为模范。
- `init` 组织：`Group(if/else)` 非单孩（BackgroundTaskBarView）、popover(item:) 形态（MaskToolbarView）、List 行单根 HStack unary（PresetManagerWindow）、数值区间 `id: \.self`（FilterBar:279/287/304/312、ChannelMixerRGB:203、InstancePicker:46 Int）稳定唯一 PASS。
- overlay/background 均为 trailing 闭包（LightamerApp 全文件、EDRControlView 等）：content-builder.md 合规。
- Form/Section/Slider/Picker/TextField/contextMenu/DisclosureGroup/Canvas/List/ContentUnavailableView/`confirmationDialog(presenting:)`/`onChange` 新双参形态：现行 API PASS。

## 方法注记

1. 分片与归一：6 worker 独立深读（各 19 文件），orchestrator 全文复核 6 份产物 + 交叉验证 5 处定级分歧（labelKey 三处定义点实测为插值拼装、ai_picker 裸键缺席但 `%lld` 变体手工在册、Culling 无 pair 级 `.id`、CurveEditor 无增删 harm 有限、@Entry"top-line finding"为回复格式要求非 severity），归一后正本计数 3+25+127+44。slice 内计数与正本计数差 = 归一合并/升降级所致。
2. error 定级：E1 的 `ai_picker_subject_n \(instance)` 与 E2/E3 的三处 `"stem_\(rawValue)"` 同属房规明令禁止的运行时构 key；catalog 现状全有键（手工在册），故 error 判的是"形态禁令 + 抽取链断"而非"当前裸 key"。J4–J8 的变量构 key 与 E1–E3 同族但定义点在审计面内、调用点静态可枚举，判 major（修复成本低、风险面小）；E2/E3 定义点在 State 层 enum（审计面外），`CaseIterable` 新增 case 即静默断键，判 error。
3. 计数口径：minor 按"条目"计，家族代表条目（如 N-I1..15 合计 26 处 init 解码、N-L1 合计 15 文件 history eager）各计 1 条；file:line 均可定位到家族首处 + 同形行。
4. 未发现项（七维阴性声明）：@State macro 三陷阱（init 复写/组合 wrapper/私有 memberwise）全仓零命中；条件式 `.if` modifier 全仓无定义无调用；custom environment/focused 键闭包值零命中（`WorkspaceModelKey` 持稳定类引用）；`TupleView` 硬编码、`overlay(ShapeStyle…)` 直接传参、MapKit 空 builder、Charts 深分支（back-deploy 超时仅 <27，本工程 floor 27 不适用）零命中；`withAnimation` 缺失类动画 finding 零条（仅 O-38 一处 transition 待确认）；`Group { 单具体 child }` 零命中。
5. 验收自检：114/114 实读（清单见各 slice 产物）；每 finding 带 file:line；结论头格式 `PASS / 3 error + 25 major + 127 minor + 44 obs`；本文件已落盘；零源码/测试/构建改动（仅 `.work/audits/xcode27-skills-2026-10/` 下产物 + slice 清单）。

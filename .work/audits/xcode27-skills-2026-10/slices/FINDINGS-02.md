# FINDINGS-02 — slice-02 深读审计（App 层 Inspector Panels D–L）

结论头：`0 error + 3 major + 47 minor + 5 obs`

- 判定基线：`.work/xcode27-skills/swiftui-specialist/references/` 下 structure.md / dataflow.md / environment.md / foreach.md / animations.md / localization.md / modifiers.md / soft-deprecation.md（及 soft-deprecated-apis.md 清单），`.work/xcode27-skills/swiftui-whats-new-27/references/` 下 state-macro.md / content-builder.md。
- 房内约定优先：KD-4（body 零 UserDefaults 直读，grep 全 slice 无命中，PASS）；app-root sheet 闭包禁裸 @Environment（slice 内无 `.sheet`，PASS）；`String.LocalizationValue("prefix_\(x)")` 插值形态禁止（本 slice 检出 3 处变量形态动态键，记 major F-02-M1/M2/M3）；disable-not-unmount（Exposure deflicker、Denoise variance 均 `.disabled(true)` 常驻，PASS）；D-H1 begin/end 配对（LightamerSlider 三件套全配对，仅 Luminance bandSlider 缺 begin-leg，记 obs F-02-O3）。
- 七维逐文件深读完成：19/19 全文实读（分段读完，无抽样）。动画维：全 slice 无 `withAnimation`/`.animation()`/`Animatable`（grep 无命中），Canvas 均为静态绘制，无动画项，PASS。@State macro 维：全 slice 无 init 内 @State 覆写、无组合 property wrapper、无私有成员 memberwise init 依赖，PASS。ContentBuilder 热点维：无 `overlay(ShapeStyle…)` 直接传参、无 `TupleView` 硬编码、无 MapKit 空 builder、无 Charts 深分支，PASS。soft-deprecation：对照 soft-deprecated-apis.md（iOS/macOS 27.0 生成），Form/Section/Slider(value:in:onEditingChanged:)/Picker/TextField(.plain+.onSubmit)/contextMenu(menuItems:)/DisclosureGroup 均为现行 API，无命中，PASS。

## 实读文件清单（19 个，行数=wc实测）

| # | 文件 | 行数 | 实读覆盖 |
|---|------|------|----------|
| 1 | App/Sources/Lightamer/UI/Inspector/DehazePanelView.swift | 102 | 全文（:1-26 + :28-95 + :96-102） |
| 2 | App/Sources/Lightamer/UI/Inspector/DenoiseProfilePanelView.swift | 415 | 全文（:26-63 + :65-250 + :251-415） |
| 3 | App/Sources/Lightamer/UI/Inspector/EqualizerPanelView.swift | 100 | 全文（:1-27 + :28-93 + :94-100） |
| 4 | App/Sources/Lightamer/UI/Inspector/ExposurePanelView.swift | 134 | 全文一次读完 |
| 5 | App/Sources/Lightamer/UI/Inspector/FilmicRGBPanelView.swift | 231 | 全文一次读完 |
| 6 | App/Sources/Lightamer/UI/Inspector/FlipPanelView.swift | 80 | 全文一次读完 |
| 7 | App/Sources/Lightamer/UI/Inspector/GradeScalarPanels.swift | 434 | 全文一次读完（6 面板 + 6 provider） |
| 8 | App/Sources/Lightamer/UI/Inspector/GrainPanelView.swift | 105 | 全文一次读完 |
| 9 | App/Sources/Lightamer/UI/Inspector/HighpassSoftenPanelView.swift | 175 | 全文一次读完 |
| 10 | App/Sources/Lightamer/UI/Inspector/HlsPanelView.swift | 234 | 全文一次读完 |
| 11 | App/Sources/Lightamer/UI/Inspector/IOPPanelProvider.swift | 198 | 全文一次读完 |
| 12 | App/Sources/Lightamer/UI/Inspector/LayersPanelView.swift | 654 | 全文（:1-220 + :216-250 + :250-450 + :454-654） |
| 13 | App/Sources/Lightamer/UI/Inspector/LensPanelView.swift | 283 | 全文一次读完 |
| 14 | App/Sources/Lightamer/UI/Inspector/LevelsPanelView.swift | 150 | 全文一次读完 |
| 15 | App/Sources/Lightamer/UI/Inspector/LightamerSlider.swift | 192 | 全文一次读完 |
| 16 | App/Sources/Lightamer/UI/Inspector/LiquifyPanelView.swift | 236 | 全文一次读完 |
| 17 | App/Sources/Lightamer/UI/Inspector/LocalContrastPanelView.swift | 109 | 全文一次读完 |
| 18 | App/Sources/Lightamer/UI/Inspector/LuminanceColorRangePanelView.swift | 359 | 全文一次读完 |
| 19 | App/Sources/Lightamer/UI/Inspector/LutPanelView.swift | 440 | 全文（:1-220 + :223-440） |
| | 合计 | 4631 | 19/19 |

另为核实跨文件事实附带只读：`LightamerCore/Sources/Pipe/History/ModuleInstance.swift:130-165`（`params(of:)` 内确为 `JSONDecoder().decode`）、EditorState/LayerEditingState/PipeCoordinator 的 `@Observable @MainActor` 声明行、soft-deprecated-apis.md 头 30 行与 Slider 条目。

## 分级 findings

### major（3）

- [major] `EqualizerPanelView.swift:51` — `String(localized: String.LocalizationValue(Self.bands[i].0))` 以运行时变量做查表键，Xcode 构建期无法从变量提取条目，6 个 `panel_equalizer_g*` 键依赖 catalog 事先存在，新增/改名即静默丢失；房内约定要求动态查表键走显式 switch（反例见 Lut `colorspaceLabel` 的 switch 写法）。出处：房内约定（动态查表键显式 switch）+ localization.md §String Catalogs。修复草图：`bands` 改为带 `LocalizedStringResource` label 的静态 struct 数组（或 id 枚举 + switch），`label:` 直接取静态资源。
- [major] `LayersPanelView.swift:397` — `Button(String(localized: String.LocalizationValue(command.labelKey)))` 同上，变量动态键，右键菜单诸命令标签无法被 catalog 同步捕获。出处：同上。修复草图：对 `MaskCommand.panelMenuCases` 写显式 `switch` 返回各 `LocalizedStringResource`，或给 `MaskCommand` 加 `label: LocalizedStringResource` 计算属性（内含 switch）。
- [major] `LuminanceColorRangePanelView.swift:332` — `Text(String(localized: String.LocalizationValue(labelKey)))` 同上，`dark/light/feather/czrange/czfeather` 五个 `mask_range_*` 键走变量。出处：同上。修复草图：`bandSlider` 的 `labelKey: String` 改为 `label: LocalizedStringResource`，调用处传字面量，删除 `LocalizationValue(labelKey)` 中转。

### minor（47）

init 内 JSON decode（structure.md §Keep view `init` cheap：`ModuleInstance.params(of:)` 内为 `JSONDecoder().decode`，逐次 body 求值触发的 view init 重复做全量解码；Params 皆小 struct 故记 minor；属全 slice 同形，逐文件各记一条）：

- [minor] `DehazePanelView.swift:24` — init 内 `PanelEditing.params(...)` 解码。修复草图：保持 seam 不变属可接受；若要优化，把解码下沉到 `body` 首次使用处或由父面一次解码后传 `Params` 值（需配合 record 版本 token 防 stale）。
- [minor] `DenoiseProfilePanelView.swift:53` — 同上（`try? instance.params(of:)`）。修复草图：同上。
- [minor] `EqualizerPanelView.swift:25` — 同上。修复草图：同上。
- [minor] `ExposurePanelView.swift:28` — 同上。修复草图：同上。
- [minor] `FilmicRGBPanelView.swift:31` — 同上。修复草图：同上。
- [minor] `FlipPanelView.swift:30` — 同上。修复草图：同上。
- [minor] `GradeScalarPanels.swift:35,112,169,226,284,342` — 六面板 init 各解码一次（Cat02/Contrast/White/Black/Tint/Saturation）。修复草图：同上（六处同改）。
- [minor] `GrainPanelView.swift:26` — 同上。修复草图：同上。
- [minor] `HighpassSoftenPanelView.swift:28-29` — 同上，且**两个**模块 params 无条件同时解码，而 body 按 `isHighpass` 只用其一，常年浪费一半。修复草图：按 `instance.opName` 只解码所需的一支（`if` 包裹解码，另一支保持 `nil`/默认）。
- [minor] `HlsPanelView.swift:32` — 同上。修复草图：同上。
- [minor] `LensPanelView.swift:37` — 同上。修复草图：同上。
- [minor] `LevelsPanelView.swift:25` — 同上。修复草图：同上。
- [minor] `LiquifyPanelView.swift:36` — 同上。修复草图：同上。
- [minor] `LocalContrastPanelView.swift:23` — 同上。修复草图：同上。
- [minor] `LutPanelView.swift:39` — 同上（`LutLibraryTreeView` 取 `params` 值参透传，合规，无 decode）。修复草图：同上。

history label 即时解析（localization.md §LocalizedStringResource for Non-View Types：`String(localized: "history_*")` 在提交瞬间 eager 解析并存入 HistoryItem，locale 切换后历史栈标签不跟随；逐文件取首处各记一条）：

- [minor] `DehazePanelView.swift:38`（另 :50、:64 同形） — `onDragEnd/onReset` 内 eager。修复草图：`endEditing/applyDiscrete` 的 `label:` 改为 `LocalizedStringResource`，解析推迟到历史面渲染时。
- [minor] `DenoiseProfilePanelView.swift:109`（另 :134、:146、:158、:170、:182、:194、:206、:346 同形） — 同上。修复草图：同上。
- [minor] `EqualizerPanelView.swift:59`（另 :90 同形） — 同上。修复草图：同上。
- [minor] `ExposurePanelView.swift:43`（另 :55、:123 同形） — 同上。修复草图：同上。
- [minor] `FilmicRGBPanelView.swift:46`（另 :60、:74、:88、:199 同形） — 同上。修复草图：同上。
- [minor] `FlipPanelView.swift:70` — 同上。修复草图：同上。
- [minor] `GradeScalarPanels.swift:51`（另 :67、:95、:127、:153、:185、:210、:240、:267、:297、:324、:358、:387 同形，六面板） — 同上。修复草图：同上。
- [minor] `GrainPanelView.swift:41`（另 :54、:67、:95 同形） — 同上。修复草图：同上。
- [minor] `HighpassSoftenPanelView.swift:45`（另 :58、:76、:89、:101、:115、:143、:159 同形，双分支各 label） — 同上。修复草图：同上。
- [minor] `HlsPanelView.swift:188-190` — `historyLabel` 为 body 求值期 computed `String`，每次 body 都解析一次（虽仅提交时使用）。修复草图：改为 `private var historyLabel: LocalizedStringResource { "history_hls" }`。
- [minor] `LensPanelView.swift:62`（另 :75、:87、:99、:111、:124、:136、:220 同形） — 同上。修复草图：同上。
- [minor] `LevelsPanelView.swift:97`（另 :140 同形） — 同上。修复草图：同上。
- [minor] `LiquifyPanelView.swift:140`（另 :168、:189 同形） — 同上。修复草图：同上。
- [minor] `LocalContrastPanelView.swift:38`（另 :56、:69、:99 同形） — 同上。修复草图：同上。
- [minor] `LutPanelView.swift:261` — 同上。修复草图：同上。

本地化类型与格式：

- [minor] `LightamerSlider.swift:20` — `let label: String` 要求调用方先 `String(localized:)` eager 解析（localization.md §Localizing Variables：应以 `LocalizedStringKey`/`LocalizedStringResource` 透传，`Text(label)` 的 `StringProtocol` 重载本身不做本地化）。此为全 slice 约 40 处 `String(localized:)` label 的根因。修复草图：`label` 改 `LocalizedStringResource`，内部 `Text(label)`。
- [minor] `LightamerSlider.swift:134-136` — `readout` 用 `String(format: readoutFormat + unit, value)`，`String(format:)` 恒渲染 0–9 数字且不跟随 locale（localization.md §Formatting…：用 `Text` format style）。修复草图：readout 改 `Text(value, format: …)` 风格或至少 `String(localized:)` 插值形态。
- [minor] `DenoiseProfilePanelView.swift:299-309` — `profileValueString` 用 `String(format: "ISO·EXIF  a₁ %.3g  b₁ %.3g", …)` 硬编码格式直接上屏（LabeledContent）。修复草图：改为 `String(localized:)` 插值（ catalog 抽 format）或 `Text("…\(…)" , comment: 占位说明)`。
- [minor] `LuminanceColorRangePanelView.swift:202-204` — `Text(String(format: "Cz %.3f  hz %.2f", …))` 同上（JzCzhz domain readout 上屏）。修复草图：改为本地化插值 `Text("Cz \(cz, format: .number…) hz …")`。
- [minor] `LensPanelView.swift:44,169` — `Text(String(localized: "panel_lens_embedded_note"/"panel_lens_no_data"))` 经 `String` 中转再 `Text(String)` 显示，丢 locale-override 上下文（同文件其余 `Text("key")` 写法合规，此两处例外）。修复草图：改为 `Text("panel_lens_embedded_note")` / `Text("panel_lens_no_data")` 字面量直传。
- [minor] `LayersPanelView.swift:43-63` — `blendLabel(_:) -> String` 返回 eager 解析串；调用处 `Text(blendLabel(…)):325` 走 `Text(StringProtocol)` 不再本地化，`Button(…):316` 同理。修复草图：`blendLabel` 返回 `LocalizedStringResource`（或 `Text`），调用处 `Text(blendLabel(…))` 保持 key 形态。
- [minor] `LayersPanelView.swift:597` — `Text("\(layer.strokes.count)")` 把纯数字做成 `LocalizedStringKey`（catalog 产生无意义 `%lld` 条目；localization.md §verbatim 规则）。修复草图：`Text(verbatim: "\(layer.strokes.count)")` 或 `Text(count, format: .number)`。
- [minor] `LutPanelView.swift:248,254` — `String(localized: "panel_lut_imported") + " " + entry.name` 与 `+ " " + error.localizedDescription` 用 `+` 拼接句子（localization.md §String Interpolation vs Concatenation 明令 AVOID）。修复草图：`String(localized: "panel_lut_imported \(entry.name)")` 插值形态（译者可调语序）。

sections/controls 计算属性复用（structure.md §Always use separate View types：`private var x: some View` 与 `@ViewBuilder` 私有 var 拼入同一 body，共享父失效边界；以下均为小体量故 minor）：

- [minor] `FilmicRGBPanelView.swift:134-171` — `autoGreyButton/autoBlackButton/autoWhiteButton` 三个 `private var …: some View`。修复草图：抽 `FilmicAutoKeyButton(kind:instance:edit:)` 独立 View，窄参注入。
- [minor] `HlsPanelView.swift:156-179` — `@ViewBuilder private var targetHueRow`。修复草图：抽 `TargetHueRow(hueBins:selectedBin:onSelect:)` 独立 View。
- [minor] `LiquifyPanelView.swift:103-171` — `@ViewBuilder warpTypePicker/strengthSlider/radiusSlider` 三处。修复草图：抽 `LiquifyNodeControls(params:node:edit:)`（或三小 View）窄参注入。
- [minor] `LayersPanelView.swift:112,219-248` — `private var toolbar` 与 `private var baseRow: some View`。修复草图：抽 `LayersToolbarView` / `BaseLayerRowView` 独立 View（`LayerRowView` 已是独立 struct，合规，不动）。
- [minor] `LuminanceColorRangePanelView.swift:70-93,175-228` — `luminanceSection(_:)/colorSection(_:) -> some View` 单次调用的 section 函数（`bandSlider` 五处复用属 structure.md 允许的小复用 helper，不管）。修复草图：抽 `LuminanceRangeSection` / `ColorRangeSection` 独立 View。

ForEach identity（foreach.md §Avoid collection indices as identity；三处均为静态/小集合故 minor）：

- [minor] `EqualizerPanelView.swift:49` — `ForEach(0..<Self.bands.count, id: \.self)` 以 index 做 id。修复草图：`bands` 改 identifiable 元素（`id: \.key`，key 即 catalog 键，稳定唯一）。
- [minor] `HlsPanelView.swift:159` — `ForEach(0..<HlsModule.binCount, id: \.self)` 同上（8 bin 静态，实践稳定）。修复草图：`ForEach(0..<binCount, id: \.self)` 改 `ForEach(SelectableBins, id: \.self)` 或以 hueBins 值做 id。
- [minor] `LiquifyPanelView.swift:52` — `ForEach(params.paths.indices, id: \.self)`，动态增删列表 index 位移即 id 重映射（Picker 行无 @State，`clampedSelection` 兜底，实际影响小）。修复草图：若 `LiquifyPathData` 元素有稳定 id 则 `id:` 指过去，否则增删后钳位选择（现状已有）+ obs 跟踪。

其它 minor：

- [minor] `LutPanelView.swift:82` — `.id(libraryRevision)` 使整棵 `LutLibraryTreeView` 在每次 panel `onAppear` rescan 后重建，`@State collapsedGroups/revision`（:279-280）清零，用户折叠态丢失。出处：foreach.md identity 稳定性（identity 不稳 → @State 重置）类推。修复草图：把 `collapsedGroups` 上提到 `LutPanelView`（`.id` 边界之上）或 rescan 改走 tree 内部 `revision` 触发而不换 `.id`。

### obs（5，需运行时验证者已标）

- [obs] `IOPPanelProvider.swift:44-47` — provider 以 `AnyView` 擦除 20+ 面板类型（modifiers.md 称 `AnyView` 为 discouraged 的 view type-erasure，与之对比的 `AnyShapeStyle` 才是正解；此处擦除发生在 op 分发边界）。op 切换本就语义全换，重建不可避免，故仅 obs。修复草图：如需去擦除，把 `IOPPanelProvider.panel` 改为 `associatedtype Panel: View` + 调用处 `AnyView` 只包一次（收益小，保持现状亦可）。
- [obs] `IOPPanelProvider.swift:44-47` — 全 slice 面板以整个 `ModuleInstance` 值类型（`let instance`）做输入，dataflow.md §Pass views only the data they read 下任何 record 字段变化都触发 body 全求值。但 record-identity 即 D-H1 的变更信号，窄化会破坏“commit 后 record 换 identity 即重读”语义，属有意 tradeoff。修复草图：维持现状；若将来 profiler 指向此处，传 `(params: Params, version: UInt64)` 窄对。
- [obs] `LuminanceColorRangePanelView.swift:336-343` — `bandSlider` 的 `Slider(value:in:)` 仅有 `onEditingChanged(false)` 提交 leg（`commitFor`），**无 drag-begin leg**（`beginEditing`），与 D-H1 begin/end 配对语义是否自洽（`commitMaskEdit` 是否要求先开窗）静态不可判定，「需运行时验证」。修复草图：运行时确认 `commitMaskEdit` 单调用即一 history item 且 live  tick 无残留；否则补 `if dragging { beginMaskEdit }`。
- [obs] `LightamerSlider.swift:87-130` — readout scrub `DragGesture(minimumDistance: 3)` 与行级 `.onTapGesture(count: 2)`（:128）手势竞态（双击重置 vs 扫值拖拽的 tap-vs-drag 判别只靠 3pt 死区注释断言），多指/快速连击下的手势仲裁「需运行时验证」。修复草图：真机验证双击必重置、短拖必扫值且只落一 commit；失败则改 `exclusivity` 组合手势。
- [obs] `LutPanelView.swift:304-319,368-381` — tree 按 `groups.filter` 内联过滤 + 每行 `displayName` 做 `flatMap/filter` 碰撞扫描，foreach.md §Don't sort or filter inline 形态（每 body 求值 O(R·G·K)）。库规模小（内置 + 用户 cube）可忽略，规模上去才需缓存。修复草图：`libraryGroups` 处一次算好 `displayName` 字典，行只查表。

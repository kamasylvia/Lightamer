# FINDINGS-01 (slice-01: Culling/Editor/EDR/Empty/FilterBar + 13 Inspector panels)

结论头：`0 PASS / 2 error + 5 major + 7 minor + 6 obs`（本 slice 内计数；PASS 项在分级清单末尾以守则条目形式记录）

判定基线：`.work/xcode27-skills/swiftui-specialist/references/` 下 structure.md / dataflow.md / environment.md / foreach.md / animations.md / localization.md / modifiers.md / soft-deprecation.md（+ soft-deprecated-apis.md），以及 `.work/xcode27-skills/swiftui-whats-new-27/references/` 下 state-macro.md / content-builder.md。房内约定优先：KD-4（body 零 UserDefaults 直读）、app-root sheet 闭包禁裸 @Environment、String.LocalizationValue("prefix_\(x)") 插值形态禁止（动态键走显式 switch）、disable-not-unmount、D-H1 begin/end 配对、2026-10-19 壳交接（NSViewRepresentable 观察照记、不作为阻断项）。

## 实读文件清单（19/19，全文逐文件深读）

| # | 文件 | 行数 |
|---|------|------|
| 1 | App/Sources/Lightamer/UI/CullingView.swift | 277 |
| 2 | App/Sources/Lightamer/UI/EditorAreaView.swift | 625 |
| 3 | App/Sources/Lightamer/UI/EditorMTKView.swift | 908 |
| 4 | App/Sources/Lightamer/UI/EDRControlView.swift | 85 |
| 5 | App/Sources/Lightamer/UI/EmptyStateView.swift | 83 |
| 6 | App/Sources/Lightamer/UI/FilterBarView.swift | 461 |
| 7 | App/Sources/Lightamer/UI/Inspector/AgXPanelView.swift | 169 |
| 8 | App/Sources/Lightamer/UI/Inspector/AshiftPanelView.swift | 299 |
| 9 | App/Sources/Lightamer/UI/Inspector/BilateralPanelView.swift | 113 |
| 10 | App/Sources/Lightamer/UI/Inspector/BloomPanelView.swift | 102 |
| 11 | App/Sources/Lightamer/UI/Inspector/ChannelMixerPanelView.swift | 144 |
| 12 | App/Sources/Lightamer/UI/Inspector/ChannelMixerRGBPanelView.swift | 404 |
| 13 | App/Sources/Lightamer/UI/Inspector/ColisaPanelView.swift | 84 |
| 14 | App/Sources/Lightamer/UI/Inspector/ColorBalanceRGBPanelView.swift | 428 |
| 15 | App/Sources/Lightamer/UI/Inspector/ColorContrastPanelView.swift | 113 |
| 16 | App/Sources/Lightamer/UI/Inspector/ColorWheelsPanelView.swift | 278 |
| 17 | App/Sources/Lightamer/UI/Inspector/ColorZonesPanelView.swift | 237 |
| 18 | App/Sources/Lightamer/UI/Inspector/CropPanelView.swift | 182 |
| 19 | App/Sources/Lightamer/UI/Inspector/CurveEditorView.swift | 157 |

## 分级清单

### error

- **[error] CullingView.swift:76-99 — body 内逐次新建 pane 模型 + 无 id 的 `.task`，pair 切换后新 pane 永不加载。** 出处：dataflow.md（§Model objects with @Observable：模型归属与持久化）+ foreach.md（§Don't create a new id on every body evaluation：body 每次求值重建带身份的值）+ structure.md（§Keep view `init` cheap）。`panesContent` 在 body 调用路径上 `let paneA/B = CullingPaneModel(...)`，body 每次求值都产出新实例；所附 `.task { ... await paneA.load() }` 无 `id`，只在首次出现时运行——pair 变化只会重建传给 `CullingPaneView` 的 idle 模型而不触发加载，且旧 `@State panes` 与新视图失配。修复草图：`panesContent` 只做纯布局，pane 的创建/加载搬到 `.task(id: pairKey)` 或 `onChange(of: pair)` 中按 pairKey 持有。
- **[error] FilterBarView.swift:165-185（`chipButton(labelKey:...)`，调用于 L145-160）— 运行时字符串动态转 `LocalizationValue`，房内约定禁止形态。** 出处：房内约定（String.LocalizationValue("prefix_\(x)") 插值形态禁止，动态查表键走显式 switch）+ localization.md（§Localizing Variables and Custom Types：运行时值无法被提取进 catalog）。`Text(String(localized: String.LocalizationValue(labelKey)))` 的 key 在编译期不可见，四个调用点的字面量（`filter_chip_rating_3` 等）抽取靠运气。修复草图：`chipButton` 改接 `LocalizedStringResource`，调用点传 `"filter_chip_rating_3"` 等字面量（或沿用 `sortLabel(for:)` 式的显式 switch）。

### major

- **[major] EDRControlView.swift:46 — `String(format:)` 嵌套在 `String(localized:)` 插值内，数字格式写死且无视 locale。** 出处：localization.md（§Formatting Dates, Numbers, and Currencies：`String(format:)` 恒渲染 0–9 且不适配 locale；§String(localized:) Outside SwiftUI Views：`String(format:)` 不适合用户可见文本）。修复草图：`Text("edr_headroom_label \(headroom, format: .number.precision(.fractionLength(1)))", comment: "…first variable is…")`。
- **[major] EmptyStateView.swift:52-62 — 非 builder 版 `.background(_:)` / `.overlay(_:)` 传 View，已软废弃。** 出处：soft-deprecated-apis.md（§Functions and Methods：`View.overlay(_:)`→`overlay(alignment:content:)`、`View.background(_:)`→`background(alignment:content:)`）+ soft-deprecation.md（§When the user asks to review：review 范围内指出并给现代替换）。修复草图：`.background { RoundedRectangle(...).fill(...) }` / `.overlay { RoundedRectangle(...).strokeBorder(...) }`。
- **[major] FilterBarView.swift:192-196 — `ForEach(Array(...enumerated()), id: \.offset)` 以位置作身份。** 出处：foreach.md（§Avoid collection indices as identity + §`.enumerated()` is fine - the index just shouldn't be the id）。chips 增删会使插入点后全部 id 错位，行状态/动画按替换处理。修复草图：`Rule` 若 `Hashable` 则 `ForEach(sessionState.filterChips, id: \.self)`，否则给 `Rule` 加稳定身份键。
- **[major] CurveEditorView.swift:44 — `ForEach(nodes.indices, id: \.self)` 以下标作身份。** 出处：foreach.md（同上）。tab 切换（L/H/C 节点数不同）或将来节点增删时，下标复用导致旧节点视图被当作新行复用/重建。修复草图：给 `ToneCurveModule.Node` 引稳定 id（持久化侧生成一次）并 `ForEach(nodes)` / `id: \.id`，下标仅作行数据。
- **[major] FilterBarView.swift:45-82/86-202 + EditorAreaView.swift:61-328 — 章节级拆分用 `private var` 计算属性而非独立 `View` 类型，共享父失效边界。** 出处：structure.md（§Always use separate `View` types for sections, not computed properties）。`quickFilterField/quickChips/chipsRow/addButton/sortMenu` 任一读取的 `sessionState` 属性变化即重求整个 body（含其余片段）；EditorAreaView 主 body 同理（虽 overlay 宿主已是独立类型，主干仍 200+ 行内联 switch）。修复草图：每节提为带窄输入的 `struct …: View`（如 `QuickFilterField(text:onChange:)`），父体只做组合。

### minor

- **[minor] 各面板 helper 工厂函数（ChannelMixerRGBPanelView.swift:146-183 `mixSection/gainRow`、ColorBalanceRGBPanelView.swift:275-309 `fourWaySection`、ColorWheelsPanelView.swift:67-116 `wheelBlock`、CurveEditorView.swift:99-110 `nodeHandle`）— 组织性拆分应为真 `View` 类型。** 出处：structure.md（§Always use separate View types…；small `@ViewBuilder` helpers 只留给同 body 内复用两三次的微片段）。slider 每 tick 经 `edit.update` 触发上层重绘时整面板 body 重求值。修复草图：提为 `GainRow/MixSection/FourWaySection/WheelBlock/NodeHandle` 等带窄输入的 struct。
- **[minor] 各面板 `init` 内 `(try? instance.params(of: ...))` / `PanelEditing.params(of:)` 解码（AgX L23-27、Bilateral L28-32、Bloom L20-24、ChannelMixer L21-25、ChannelMixerRGB L28-32、ColorContrast L18-22、ColorWheels L29-33、ColorZones L36-40、Crop L26-30、Ashift L29-33、Colisa L18-22）。** 出处：structure.md（§Keep view `init` cheap：init 随父 body 高频运行，只做常量拷贝）。修复草图：由 Provider/Inspector 侧备好 `Params` 后传入，或在模型层缓存已解码 Params。
- **[minor] 翻译注释系统性缺失：裸 `Text("panel_*")` 表头/Picker 项（各面板 body）与无 `comment:` 的 `String(localized:)`（如 ZoomHUD L549、chipLabel L228-267 各分支）。** 出处：localization.md（§Comments for Translators：歧义串与占位符必须配 comment，占位符按位置描述）。修复草图：表头 `Text("panel_x", comment: "…")`，`chipLabel` 各分支补 `comment:` 说明占位符含义。
- **[minor] 固定磅值锁死行高：EDRControlView.swift:53/70/75 `.font(.system(size: 10/11))`、EmptyStateView.swift:24 `.font(.system(size: 28/64))`。** 出处：localization.md（§Use SwiftUI's text styles instead of fixed point sizes）。修复草图：换 `.caption/.callout/.largeTitle` 等文本样式，字重用 `fontWeight` 保留。
- **[minor] 固定宽度布局：FilterBarView.swift:422 `.frame(maxWidth: 130)`（sort Picker）、EditorAreaView.swift:593 `.frame(width: 140)`（split Slider）。** 出处：localization.md（§Do not hardcode frame widths or heights for text；`ViewThatFits`）。修复草图：去固定宽或包 `ViewThatFits` 给长译文回退布局。
- **[minor] CullingView.swift:269 `Text(pane.id)` — 运行时路径字符串应显式退出本地化。** 出处：localization.md（§Use `Text(verbatim:)` to opt out…；变量已走 `StringProtocol` 重载，显式声明意图）。修复草图：`Text(verbatim: pane.id)`。
- **[minor] 面板 `label: String(localized: …)` 即时解析（AgX L33-132、Bilateral、Bloom、Colisa、Crop、ColorContrast 等全部 `LightamerSlider` 调用点）无视 `\.locale` 覆盖。** 出处：localization.md（§SwiftUI Views Localize String Literals Automatically：包一层即时解析，忽略 locale 覆盖；§LocalizedStringResource for Non-View Types）。修复草图（需跨 slice 协调，不在本 slice 改）：`LightamerSlider.label` 改 `LocalizedStringResource`/`LocalizedStringKey`，调用点传字面量。

### obs（需运行时验证）

- **[obs] ColorBalanceRGBPanelView.swift:385-398 — hue-disc 以 `value.translation == .zero` 判定首 tick 并 `onBegin()`，快拖首帧非零即漏 begin，D-H1 配对破裂。** 出处：房内约定 D-H1（begin/end 配对）+ dataflow.md（副作用归属）。修复草图：以本地 `@State dragging` 哨兵配对 begin/end，或复用 slider 的 `onDragBegin/onDragEnd` 三件套。〔需运行时验证〕
- **[obs] EditorMTKView.swift:153-158 — `updateNSView` 内调用 `viewportState.noteGeometry(...)` 写模型，更新期副作用或致循环重绘。** 出处：dataflow.md（视图更新路径只推送 source of truth；写操作归属 coordinator/事件）。修复草图：`noteGeometry` 内部做相等守卫（无变化不写），或搬到几何变化事件。〔需运行时验证〕
- **[obs] CurveEditorView.swift:114-132 — `DragGesture.onEnded` 未覆盖手势取消路径时 `dragStarted` 常真，下次漏 `onBegin`。** 出处：房内约定 D-H1。修复草图：`onChanged` 哨兵改 `.updating` 或在取消路径复位。〔需运行时验证〕
- **[obs] CullingView.swift:55/CullingPaneView L255 — `.transition(.opacity)` 无配套 `.animation(value:)`，切换是否动画需真机确认。** 出处：animations.md（本 slice 无自定义 Animatable；transition 生效依赖显式 animation）。修复草图：为 pair/plane 变化配 `.animation(..., value:)` 或确认即时切换即为预期。〔需运行时验证〕
- **[obs] 各面板 `params` 为 `init` 快照：一次拖拽多 tick 内 `set` 均以初始快照为基（AgX L143-149、Bilateral L87-95、Bloom L80-86 等同形），连续跨 slider 编辑是否丢中间值取决于 Inspector 重建时序。** 出处：dataflow.md（§Per-property dependency granularity：读整包即依赖整包）。修复草图：以 `instance` 当前记录（或编辑会话的 live 值）为每次 tick 的基。〔需运行时验证〕
- **[obs] `.font(.system(size:weight:))` 疑似命中软废弃表（soft-deprecated-apis.md L314-315），但替换签名与现调用字面相同，需对照 SDK 头确认是否真为同名新 API。** 出处：soft-deprecated-apis.md（§Functions and Methods）+ soft-deprecation.md（§How to identify：以 header `deprecated: 100000.0` 为准）。本 slice 不做替换，先记 obs。

## 房内约定逐条对账

- KD-4：本 slice 无任何 `UserDefaults` 直读（仅 FilterBarView.swift:21 注释说明持久化归 `SessionState`），PASS。
- sheet 闭包禁裸 `@Environment`：FilterBarView `dateRangeSheet`/`alert` 内容只读 `@State`（`dateRangeBounds/textEntryValue`），无 `@Environment`，PASS。
- 动态查表键：除上文 error（`chipButton`）外，`sortLabel(for:)`（L439-448）为显式 switch 返回字面量，合规 PASS；`chipLabel(for:)`（L228-272）键均为静态字面量 + 值插值，属 format-string 形态，PASS（缺 comment 另记 minor）。
- disable-not-unmount：BeforeAfterHUD 关闭为用户主动行为；agent 控制期相关面不在本 slice，无违规，PASS。
- D-H1：全部 `LightamerSlider` 三件套 `beginEditing/update/endEditing` 配对完整（AgX/Ashift/Bilateral/Bloom/ChannelMixer/ChannelMixerRGB/Colisa/ColorContrast/Crop/ColorZones-strength），PASS；hue-disc 与 CurveEditor 拖拽哨兵见 obs。
- 壳交接：EditorMTKView.swift:33（`NSViewRepresentable`）+ ViewportMTKView（NSView 手势面）按 2026-10-19 既定方向属观察项，不作为阻断项；本报告不对其提迁移要求。

## 七维逐文件速览

- 拆分度：ZoomHUD/BeforeAfterHUD/CullingPaneView/TrackballView/HueStrip/ColorBalanceRGBHueDisc 已是独立 View（好）；FilterBar 与 EditorArea 主干、面板 helper 函数见 major/minor。
- 数据流：`@State` 私有性全合规；`@Environment` 模型注入形状合规（EditorArea/ZoomHUD/BeforeAfter/FilterBar/EDR）；`@Bindable` 用法合规；面板宽输入（整 `ModuleInstance`）+ 快照 params ВҖ见 minor/obs。
- ForEach 身份：数值区间 `id: \.self`（FilterBar L279/287/304/312、ChannelMixerRGB L203）稳定唯一 PASS；`enumerated offset` 与 `nodes.indices` 见 major。
- 动画：无自定义 Animatable；`.animation(.easeInOut, value:)`（EditorArea L256）形状合规；孤 transition 见 obs。
- 本地化：key 形态总体合规（字面量自动本地化），`String(format:)` 嵌套、动态键、缺 comment、固定磅值/宽度见上。
- `@State` macro：全部带初值且无 init 内复写、无组合 wrapper、无私有成员 memberwise 依赖，PASS（state-macro.md 三陷阱皆无）。
- ViewBuilder 类型检查：无 `TupleView` 硬编码、无 ShapeStyle overlay 歧义（EDR 用 trailing 闭包合规）、无 MapKit 空 builder、无 Charts 分支爆炸，PASS；大 Form 体为线性组合，未见类型检查热点。

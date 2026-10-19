# FINDINGS-03 (slice-03, 2026-10-19)

结论头：**3 error + 5 major + 7 minor + 6 obs**（本 slice 内计数）

判定基线（已全文先读）：`.work/xcode27-skills/swiftui-specialist/references/` 下
structure.md / dataflow.md / environment.md / foreach.md / animations.md /
localization.md / modifiers.md / soft-deprecation.md（soft-deprecated-apis.md 以 soft-deprecation.md 指引为准），
以及 `.work/xcode27-skills/swiftui-whats-new-27/references/` 下 state-macro.md / content-builder.md。
房内约定优先：KD-4（body 零 UserDefaults 直读）、app-root sheet 闭包禁裸 @Environment、
`String.LocalizationValue("prefix_\(x)")` 插值形态禁止（动态查表键走显式 switch）、
disable-not-unmount、D-H1 begin/end 配对、2026-10-19 壳交接既定方向。
只读审计，未改源码、未跑构建/测试；行为级问题一律降级为 obs 并标「需运行时验证」。

## 实读文件清单（19/19，逐文件全文已读，大文件分段读完）

| # | 文件 | 行数 |
|---|------|------|
| 1 | App/Sources/Lightamer/UI/Inspector/MaskGroupsPanelView.swift | 417 |
| 2 | App/Sources/Lightamer/UI/Inspector/MonochromePanelView.swift | 213 |
| 3 | App/Sources/Lightamer/UI/Inspector/NLMeansPanelView.swift | 134 |
| 4 | App/Sources/Lightamer/UI/Inspector/PastePartialDialog.swift | 155 |
| 5 | App/Sources/Lightamer/UI/Inspector/PresetPanelView.swift | 151 |
| 6 | App/Sources/Lightamer/UI/Inspector/RetouchPanelView.swift | 326 |
| 7 | App/Sources/Lightamer/UI/InspectorRowView.swift | 100 |
| 8 | App/Sources/Lightamer/UI/Inspector/ShadhiPanelView.swift | 188 |
| 9 | App/Sources/Lightamer/UI/Inspector/SharpenPanelView.swift | 104 |
| 10 | App/Sources/Lightamer/UI/Inspector/SigmoidPanelView.swift | 175 |
| 11 | App/Sources/Lightamer/UI/Inspector/SkinSmoothPanelView.swift | 210 |
| 12 | App/Sources/Lightamer/UI/Inspector/TemperaturePanelView.swift | 238 |
| 13 | App/Sources/Lightamer/UI/Inspector/TextOverlayPanelView.swift | 183 |
| 14 | App/Sources/Lightamer/UI/Inspector/ToneCurvePanelView.swift | 208 |
| 15 | App/Sources/Lightamer/UI/Inspector/ToneEqualPanelView.swift | 308 |
| 16 | App/Sources/Lightamer/UI/Inspector/VelviaPanelView.swift | 81 |
| 17 | App/Sources/Lightamer/UI/Inspector/VibrancePanelView.swift | 72 |
| 18 | App/Sources/Lightamer/UI/InspectorView.swift | 482 |
| 19 | App/Sources/Lightamer/UI/Inspector/VignettePanelView.swift | 199 |

七维逐文件结论速览：拆分度——E/M 见 M4、M5，其余面板多为单用途 Form 直写 LightamerSlider，
ToneEqualCurveView / MonochromeColorWheel / MaskThumbnailChipView / MaskItemRowView 均为独立 View 类型，
符合 PREFER 形；数据流——各面板取整 `ModuleInstance` 做 init 解码属真实消费且期望随实例变化失效，
PASS；ForEach identity——除 m5 外全部稳定唯一；动画——slice 内无显式动画 API，PASS；
本地化——E/M/m 见下；@State macro——全部 `@State private`、无自定义 init 内赋值、无组合 wrapper，
PASS；ViewBuilder 热点——无单 child Group、无 TupleView 硬编码、无 overlay(shapeStyle) 直接传参、
无 MapKit/Canvas 异构建造歧义，PASS。软弃用 API——Form/Section/Picker/Menu/Toggle/Slider/
ColorPicker/Canvas/List/ContentUnavailableView/focusedSceneValue/task(id:) 均为现行 API，PASS。
KD-4——slice 内零 UserDefaults/@AppStorage 直读，PASS。壳交接——本 slice 无 SwiftUI App lifecycle 层，
仅 InspectorView L220 `Section(String(localized:defaultValue:))` 为带默认值的显式兜底写法，
合规不记。

## error（3）

- [error] SigmoidPanelView.swift:121 — `String(localized: String.LocalizationValue(preset.0))`
  动态构造查表键，违反房内约定「`String.LocalizationValue("prefix_\(x)")` 插值形态禁止，
  动态查表键走显式 switch」（localization.md §String(localized:) Outside SwiftUI Views
  亦要求 key 为字面量方可抽取）。修复草图：presets 元组改携 `LocalizedStringResource`
  或对 4 个静态 preset 做显式 switch 返回字面量 key。
- [error] ToneEqualPanelView.swift:84 — `String(localized: String.LocalizationValue(band.0))`
  同上，9 段 bands 的 label 用动态键（ForEach 本身 `id: \.0` 静态唯一，identity 维 PASS）。
  修复草图：bands 元组加 `label: LocalizedStringResource` 字段，body 直读。
- [error] MaskGroupsPanelView.swift:337 — `commitSlider` 内
  `String(localized: String.LocalizationValue(labelKey))` 同上（两处调用点传的皆为静态 key，
  行为正确但形态被禁且 catalog 抽取失效）。修复草图：调用点直接传字面量 key 或
  `LocalizedStringResource`，删掉 String 参数中转。

## major（5）

- [major] InspectorRowView.swift:73 — `Text(LocalizedStringKey(model.toggleValueKey))`，
  运行時刻变量包装成 key，Xcode 无法抽取，catalog 缺条目时 AX 值回退显示裸 key。
  出处：localization.md §Localizing Variables and Custom Types。
  修复草图：按 `model.enabled` 显式 switch 返回 `Text("toggle_on") / Text("toggle_off")` 字面量。
- [major] InspectorRowView.swift:80 — `Text(LocalizedStringKey(label))`，`label` 已是
  `String(localized:)` 解析后的显示字符串，再包成 key 做二次查表（locale 切换失效、
  含格式字符时行为未定义）。出处：localization.md §SwiftUI Views Localize String Literals
  Automatically（String 变量走 StringProtocol 重载即不本地化，此处应保持原样显示用户/已解析文本）。
  修复草图：改为 `Text(label)`。
- [major] PresetPanelView.swift:107 —
  `Button(String(localized: "preset_apply") + " \(preset.document.name)")`，
  `+` 拼接产生 String 且组装句子，译者无法调整语序。出处：localization.md
  §String Interpolation vs Concatenation。修复草图：改用 label 闭包
  `Text("preset_apply \(preset.document.name)")` 字面量插值（format 串进 catalog）。
- [major] MaskGroupsPanelView.swift:88-149 — `groupCard(_:)` 为 `@ViewBuilder` 私有函数，
  内含 ForEach/条件分支且读 `editorState`，与父 body 同一失效边界。
  出处：structure.md §Always use separate `View` types for sections, not computed properties。
  修复草图：抽 `MaskGroupCardView: View`，仅传 gradeNode 显示字段 + masks + layerID/locked。
- [major] RetouchPanelView.swift:90-227 — `algorithmPicker/toolSliders/blurSlider/fillSlider/
  sourcePickToggle/overlayHint/strokeList` 7 个 `private var …: some View` 计算属性做分区，
  全部直读 `editingState`，任一工具量变化即重估整个 Form。出处：同上 structure.md。
  修复草图：工具区/列表区各抽独立 View，以标量值 + 回调为窄输入。

## minor（7）

- [minor] MonochromePanelView.swift:184 — `.accessibilityLabel(Text("monochrome color wheel"))`
  硬编码英文自然语句，与工程 opaque-key 惯例不一致。出处：localization.md
  §SwiftUI Views Localize String Literals Automatically（惯例一致性）。
  修复草图：改用 `"monochrome_wheel_label"` opaque key 并进 catalog。
- [minor] Eager `String(localized:)` 可改字面量组（显示正确，仅丢 `\.locale` 覆盖上下文）：
  SkinSmoothPanelView.swift:122 `Toggle(...)`、VignettePanelView.swift:174-176
  `discreteToggle(title: String, ...)` 签名迫使调用点先解析、PastePartialDialog.swift:109,113,118,120
  `Button(...)` 与 :136 `Picker(...)`、PresetPanelView.swift:95 `Label(...)` 与 :111 `Button(...)`。
  出处：localization.md §SwiftUI Views Localize String Literals Automatically。
  修复草图：调用点传字面量（Toggle/Button/Label/Picker 皆有 `LocalizedStringKey` 重载），
  `discreteToggle` 的 `title` 改型为 `LocalizedStringKey`。
- [minor] RetouchPanelView.swift:294-302 + :207 — `strokeLabel` 用 `"\(algorithm) \(centerString)"`
  组装面向用户的行文本，再以 String 变量进 `Text`，句子结构锁死且丢本地化上下文。
  出处：localization.md §String Interpolation vs Concatenation。
  修复草图：行内用 `HStack` 放两个 `Text`（算法名 + 坐标 readout），或单条字面量插值。
- [minor] RetouchPanelView.swift:307-309 — `centerString` 用 `String(format:)` 构造用户可见读数，
  数字恒为 0–9 且非现代 API。出处：localization.md §String(localized:) Outside SwiftUI Views。
  修复草图：改 `String(localized:)` format 写法（若定为纯技术读数则注明意图后保留）。
- [minor] PresetPanelView.swift:132-136 — `CategorySection.id` 为 `category ?? ""`，
  空白分类 trim 后得 `""`，与未分类 `nil` 的 id  collides，违反 identity 唯一性。
  出处：foreach.md §The rule of thumb（stable + unique）。
  修复草图：`var id: String { category ?? "\u{0}uncategorized" }` 区分 nil 与空串。
- [minor] InspectorView.swift:224,233 — `addFaceEntries.filter { $0.section == ... }` 内联写在
  `ForEach` 参数里，每次 body 求值重跑过滤。出处：foreach.md §Don't sort or filter inline
  in `ForEach`。修复草图：抽 `developEntries / compatEntries` 私有计算属性预分组。
- [minor] PresetPanelView.swift:138-150 — `categorySections` 每次 body 做
  `Dictionary(grouping:)+sorted`，同属 body 内联派生集合。出处：同上。
  修复草图：随 `developPresets` 缓存分组结果（N 小，收益为次要）。

## obs（6，需运行时验证或跨文件确认，不改码）

- [obs] InspectorView.swift:376-385 + :428-430 — `MetadataFieldFocusedKey.Value = Binding<Bool>`，
  body 内每次重建 `Binding(get:set:)` 写入 `.focusedSceneValue`；按 environment.md
  §How environment comparison works，闭包承载值不可靠比较，读者可能每轮重读。
  FocusedValues 仅随焦点变化传播，或可抵消——需运行时验证 typing 期间是否异常失效。
- [obs] InspectorView.swift:211（及 EditorState.swift:909）— `ForEach(addFaceEntries)` 依赖
  `AdjustmentAddEntry.id == template.opName`，即假定目录枚举中 opName 全局唯一；
  若 grade 目录出现同 op 多条目，行 identity 重复。需运行时验证多实例目录行为。
- [obs] MonochromePanelView.swift:167-182 — wheel 用 `translation == .zero` 触发 `onBegin()`，
  D-H1 begin/end 配对依赖首个 changed 事件恰为零位移；且 `DragGesture(minimumDistance: 0)`
  与 :182 `onTapGesture(count: 2)` 存在手势吞没双击重置的风险。需运行时验证配对与双击可达。
- [obs] TextOverlayPanelView.swift:61-87 — `ColorPicker` 的 selection setter 内直接
  `applyDiscrete`，取色拖动期间 setter 触发频率决定 history 条目数（连续控件离散提交）。
  需运行时验证是否产生单次拖动多 history 项。
- [obs] RetouchPanelView.swift:28 — 整 `RetouchLayer` 值类型（含 strokes 数组）作为输入，
  每次父 body 求值做逐字段比较；strokes 通常为个位数，成本可忽略。出处：dataflow.md
  §Watch the cost of large value-type inputs。暂不处理，若画像显示热点再收窄输入。
- [obs] 全 D-H1 面板通用（例 MonochromePanelView.swift:30-34，NLMeans/Shadhi/Sharpen/Sigmoid/
  Temperature/TextOverlay/ToneCurve/ToneEqual/Velvia/Vibrance/Vignette/SkinSmooth 同形）—
  `set` 系从 init 快照 `params` 拷贝单字段后 `edit.update`，正确性依赖“live tick 间父视图
  用新 instance 重建面板或单字段幂等”；跨源交错（如拖动中外部 preset 落定）是否丢字段。
  需运行时验证拖动中实例回传时序。

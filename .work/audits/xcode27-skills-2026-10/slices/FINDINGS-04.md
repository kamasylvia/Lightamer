# FINDINGS-04 (slice-04) — SwiftUI 27 skills audit

结论头：3 error + 1 major + 30 minor + 10 obs（本 slice 内计数）

判定基准：`.work/xcode27-skills/swiftui-specialist/references/` 下 structure.md / dataflow.md / environment.md / foreach.md / animations.md / localization.md / modifiers.md / soft-deprecation.md（及 soft-deprecated-apis.md 清单），`.work/xcode27-skills/swiftui-whats-new-27/references/` 下 state-macro.md / content-builder.md。房内约定优先：KD-4（body 零 UserDefaults 直读）、app-root sheet 闭包禁裸 @Environment、String.LocalizationValue("prefix_\(x)") 插值形态禁止、disable-not-unmount、D-H1 begin/end 配对、2026-10-19 壳交接既定方向。

## 实读文件清单（19 个，逐文件全文深读）

| # | 文件 | 行数 |
|---|------|------|
| 1 | App/Sources/Lightamer/UI/LightamerApp.swift | 2906 |
| 2 | App/Sources/Lightamer/UI/McpLauncherPanelView.swift | 292 |
| 3 | App/Sources/Lightamer/UI/Overlay/CropOverlayHost.swift | 134 |
| 4 | App/Sources/Lightamer/UI/Overlay/CropOverlayView.swift | 305 |
| 5 | App/Sources/Lightamer/UI/Overlay/InstancePickerOverlay.swift | 130 |
| 6 | App/Sources/Lightamer/UI/Overlay/LiquifyOverlayHost.swift | 245 |
| 7 | App/Sources/Lightamer/UI/Overlay/MaskOverlayHost.swift | 907 |
| 8 | App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift | 769 |
| 9 | App/Sources/Lightamer/UI/Overlay/RetouchOverlayHost.swift | 330 |
| 10 | App/Sources/Lightamer/UI/Overlay/SegmentEditingOverlayHost.swift | 314 |
| 11 | App/Sources/Lightamer/UI/PresetManagerWindow.swift | 420 |
| 12 | App/Sources/Lightamer/UI/SessionBrowserView.swift | 652 |
| 13 | App/Sources/Lightamer/UI/SettingsView.swift | 126 |
| 14 | App/Sources/Lightamer/UI/Shell/AdjustmentTransferView.swift | 340 |
| 15 | App/Sources/Lightamer/UI/Shell/BackgroundTaskBarView.swift | 311 |
| 16 | App/Sources/Lightamer/UI/Shell/ColorMatchPanelView.swift | 252 |
| 17 | App/Sources/Lightamer/UI/Shell/DrtPanelView.swift | 390 |
| 18 | App/Sources/Lightamer/UI/Shell/EditorAdjustmentStackView.swift | 521 |
| 19 | App/Sources/Lightamer/UI/Shell/EditorNodeHeaderView.swift | 120 |

## 分级 findings

### error

- [error] InstancePickerOverlay.swift:53 — `String(localized: String.LocalizationValue("ai_picker_subject_n \(instance)"))` 为房内约定明令禁止的插值构 key 形态，动态 key 对 zh-audit 提取器不可见。出处：房内约定（KD-4 插值形态禁止）+ localization.md§Localizing Variables（已知 key 集应用类型建模 / 显式 switch）。修复草图：改用静态 format 字面量 `String(localized: "ai_picker_subject_n \(instance)")` 或按 LightamerApp ratingMenuLabel 式显式 switch 返回静态 key。
- [error] MaskToolbarView.swift:85 — `.accessibilityLabel(Text(String(localized: String.LocalizationValue(tool.labelKey))))` 中 `labelKey` 系它文件内 `"mask_tool_\(rawValue)"` 运行时插值拼装（非显式 switch），经 LocalizationValue 动态查表，犯同一条房规。出处：房内约定（KD-4 插值形态禁止）+ localization.md§Localizing Variables。修复草图：在 MaskTool 上把 `labelKey` 改为返回静态字面量的显式 switch（或每分支直接 `String(localized:)`），调用侧保持静态。
- [error] MaskToolbarView.swift:144 — `Text(String(localized: String.LocalizationValue(style.labelKey)))`，`mask_overlay_style_\(rawValue)` 同为插值拼装 key，同上。出处：同上。修复草图：同上，给 MaskOverlayStyle.labelKey 做显式 switch 静态化。

### major

- [major] InstancePickerOverlay.swift:34-36,100-129 — `combinedPlane` 每次 body 求值都重跑 `AIMaskService.subjectMask`（CPU label 读取），且 `tintedImage(from:)` 每次重建 plane 级 RGBA 缓冲 + CGImage，属于 body 内高代价分配/计算。出处：dataflow.md§Passing data into views / structure.md§Keep view init cheap（body 高频重跑语义）+ foreach.md§Don't sort or filter inline（同族：body 内重算派生量）。修复草图：以 selection 为键缓存 plane/CGImage（@State 缓存 + onChange 重算），或下沉到 model 层。

### minor

- [minor] McpLauncherPanelView.swift:188,222,261 — `header` / `statusLine` / `logPane` 为 `private var …: some View` 计算属性分区，与 parent 共享同一失效边界（follow 开关/log 追加会联动重估全部分区）。出处：structure.md§Always use separate View types。修复草图：拆为独立 View 类型并只传窄输入（如 `LogPane(lines:followScroll:)`）。
- [minor] MaskOverlayHost.swift:112 — `maskCanvas(transform:)` 为返回 some View 的普通方法（内含 Canvas + 全量 form 绘制），与 host 共享失效边界。出处：structure.md§Always use separate View types。修复草图：抽为独立 `MaskOverlayCanvas(forms:transform:)` View，只传 forms 与 transform。
- [minor] MaskOverlayHost.swift:535 — `String(localized: String.LocalizationValue(commitLabelKey))` 经变量 key 间接查表；`commitLabelKey` 虽已是显式 switch，但 key 字面量在调用点不可见。出处：房内约定（动态查表键走显式 switch 的精神）+ localization.md§Comments/String Catalog。修复草图：仿 ratingMenuLabel 式，每臂直接返回 `String(localized:"history_mask_brush")` 等静态调用。
- [minor] MaskToolbarView.swift:67-68,220,262,338 — `body` 内联组装 + `featherSection` / `followEdgesSection` / `aiGroup` / `depthGroup` 等计算属性分区，共享同一失效边界（任一 env 抖动重估整条 toolbar）。出处：structure.md§Always use separate View types。修复草图：各分区抽独立 View，窄输入（style/session/degraded 等值类型）。
- [minor] MaskToolbarView.swift:120-123,136-141,231-234,263-268,737-741 — 对 @Environment Observable 大量使用闭包式 `Binding(get:set:)`（每 body 分配 + 比较代价），注释自认“无 $ 投影”。出处：dataflow.md§Use KeyPath bindings, not closure bindings。修复草图：body 内 `@Bindable var b = editingState` 后用 `$b.followEdgesParams.mode` / 下标投影。
- [minor] MaskToolbarView.swift:238,764 — `String(format:"%.0f"/"%.2f")` 硬编码数字格式渲染读数，用户 locale 数字形状不适配。出处：localization.md§Formatting Dates, Numbers, and Currencies。修复草图：改 `Text(value, format:.number.precision(...))`。
- [minor] MaskToolbarView.swift:404,418 — `.popover(item:)` 的 `AIInstanceCatalog: Identifiable` 之 `id` 为内容派生有损哈希（reduce 相加），不唯一且内容一变身份即变。出处：foreach.md§Identity must outlive the view（stable+unique）。修复草图：picker 会话分配持久 UUID 作为 item id，catalog 只做负载。
- [minor] SegmentEditingOverlayHost.swift:180,197 — `counterBadge` / `controlBar` 为计算属性分区且 `controlBar` 内含条件分支，与 host 同边界。出处：structure.md§Always use separate View types。修复草图：拆 `SegmentCounterBadge` / `SegmentControlBar` 窄输入。
- [minor] SegmentEditingOverlayHost.swift:170,253-260 — `budgetNotice = "\(error)"` 与 `"ai_toast_generate_failed" + " (\(error))"` 为拼接组句，语序跨语言失效且裸 error 未入 catalog。出处：localization.md§String Interpolation vs Concatenation。修复草图：单句静态 key + 占位插值（如 `"ai_toast_generate_failed \(detail)"` 字面量）。
- [minor] PresetManagerWindow.swift:44-57 — `grouped` 每次 body 全量 `Dictionary(grouping:)` + 排序，随库规模线性增长。出处：foreach.md§Don't sort or filter inline。修复草图：分组结果下沉 store/model 缓存，body 只读现成数组。
- [minor] PresetManagerWindow.swift:190 — `row(_:)` 为返回 some View 的普通函数（非独立 View 类型），行级失效边界与 List 共享。出处：structure.md§Always use separate View types + dataflow.md§Pass collection elements directly。修复草图：抽 `PresetRow(preset:)` 独立 View。
- [minor] PresetManagerWindow.swift:158 — `Text(String(localized:"preset_delete_message") + " " + name)` 拼接组句，跨语言语序断裂。出处：localization.md§String Interpolation vs Concatenation。修复草图：单 key 插值 `Text("preset_delete_message \(name)")`。
- [minor] SettingsView.swift:97-105,108 — detail switch 内联构造 `LCRSettingsModel` / `ACASettingsModel`（闭包捕获 + 新实例），选中页期间每次 body 求值重建 model。出处：structure.md§Keep view init cheap（body 非一次性语义）。修复草图：model 提升 @State 懒建或 key 化缓存，body 只读。
- [minor] AdjustmentTransferView.swift:78,91,154,203,259 — `header` / `sourceSegment` / `nodePane` / `itemPane` / `versionPane` 计算属性分区共享边界。出处：structure.md§Always use separate View types。修复草图：三窗格各抽独立 View（node/item/version 窄输入）。
- [minor] AdjustmentTransferView.swift:307 — `.textCase(.uppercase)` 运行时改大小写，强制所有译文同一大小写。出处：localization.md§Casing。修复草图：源字符串直接写目标大小写，删 `.textCase`。
- [minor] AdjustmentTransferView.swift:131-150 — `sourceBinding` 闭包式 Binding（每 body 新分配）。出处：dataflow.md§Use KeyPath bindings。修复草图：模型侧加下标投影或 @Bindable 化。
- [minor] BackgroundTaskBarView.swift:95,125,280 — `rowView` / `agentRowView` / `agentActivityList` 为 @ViewBuilder 方法行构造，非独立行 View。出处：structure.md§Always use separate View types。修复草图：抽 `BackgroundTaskRow(descriptor:handle:)` 等独立 View。
- [minor] ColorMatchPanelView.swift:58,98,110,175,221 — `content` / `solverPicker` / `referenceSection` / `solveSection` / `readoutSection` 为传 model 的普通方法分区，共享边界。出处：structure.md§Always use separate View types。修复草图：各区抽独立 View，读 model 窄字段。
- [minor] ColorMatchPanelView.swift:150-153,196-198 — weight/strength 闭包式 `Binding(get:set:)`。出处：dataflow.md§Use KeyPath bindings。修复草图：@Bindable 投影或模型下标投影。
- [minor] ColorMatchPanelView.swift:91-93 — `.onChange(of: instance)` 依赖仅作副作用（updateInstance），却挂在含 ScrollView 的 content 作用域重估整页。出处：dataflow.md§Isolating onChange(of:) side-effect invalidation。修复草图：抽专用 ViewModifier 持有该依赖与 onChange。
- [minor] ColorMatchPanelView.swift:156,211 — `String(format:"%.2f")` 权重/强度读数。出处：localization.md§Formatting。修复草图：改 format-style Text。
- [minor] EditorAdjustmentStackView.swift:125,214,258,303,443 — `tabBar` / `pageRows` / `groupShell` / `selectedPanelBody` / `row(for:session:)` 方法式组装共享大 body 边界（`panelView` 回 AnyView 此处非 ForEach 行可不计）。出处：structure.md§Always use separate View types。修复草图：页/组/行按路由抽独立 View。
- [minor] EditorAdjustmentStackView.swift:94-98,104-108 — 两个 `.onChange` 依赖（pendingTabRoute/activeLayerID）仅作副作用（置 tab、重建 session），却落 whole-stack body。出处：dataflow.md§Isolating onChange。修复草图：各抽轻量 ViewModifier 持有。
- [minor] EditorAdjustmentStackView.swift:273 — `Text(String(localized: String.LocalizationValue(note)))` 经运行时 `note` 查表。出处：房内约定 + localization.md§Localizing Variables。修复草图：note 建模为静态 key 的显式 switch（或 LocalizedStringResource），调用侧静态解析。
- [minor] EditorNodeHeaderView.swift:94,100,107,109 — 焦距/光圈/快门 `String(format:)` 硬编码单位与语序（"%.0f mm"、"ƒ/%.1f"、"1/%.0f s"）。出处：localization.md§Formatting。修复草图：Measurement/FormatStyle 本地化渲染，单位语序入 catalog。
- [minor] LightamerApp.swift:15-35 — `LightamerColumnVisibilityKey` / `ExportPanelRequestKey` 手写 FocusedValueKey 样板 + get/set 扩展。出处：dataflow.md§@Entry macro（明确要求 surface 为顶层 review finding；iOS18/macOS15+ 可用为一行 caveat）。修复草图：`extension FocusedValues { @Entry var lightamerColumnVisibility: Binding<NavigationSplitViewVisibility>? }` 同理迁移。
- [minor] LightamerApp.swift:1761 — `.onChange(of: editorState.loadedImageURL != nil)` 挂 Window 内容链，依赖仅作 one-shot toast 副作用。出处：dataflow.md§Isolating onChange。修复草图：抽轻量 modifier 持有该 Bool 依赖。
- [minor] LightamerApp.swift:1867,1871,1888,1902,1907,1911 — "New/Open/Import/Backup/Move Project…" 等用户面菜单项用 `Text(verbatim:)` 硬编码英文，绕过 catalog（注释称 zh 随 M2-3 落地，属已知 perencanaan 缺口仍须记）。出处：localization.md§SwiftUI Views Localize String Literals Automatically。修复草图：换静态 key + zh/en 入 catalog。
- [minor] SessionBrowserView.swift:110-426 — 单文件 500+ 行 body：contextMenu、四个 sheet 对话框、drop/filter/alert 全内联，共享同一失效边界。出处：structure.md§Always use separate View types。修复草图：菜单/对话框各抽独立 View（传 targets/pending 回调窄输入）。
- [minor] SessionBrowserView.swift:317-318 — `Text(String(localized: String.LocalizationValue(mode.pickerKey)))` 经变量 wrap；`pickerKey` 本身已是显式 switch 静态 key（合规精神），但调用点仍运行时解析。出处：房内约定 + localization.md。修复草图：仿 ratingMenuLabel，每臂直接返回 `String(localized:"stack_denoise_mode_average")` 等。

### obs（含需运行时验证）

- [obs] LightamerApp.swift:507-1661 — 主 Window 内容链单表达式挂 ~20 个 `.environment` + 串行 `.task` 装配闭包，可读性/装配耦合重但无失效错误；App lifecycle 层观察按约定照记、不作迁移阻断（2026-10-19 壳交接既定方向）。出处：structure.md（组织）+ 房内约定（壳交接）。修复草图：装配闭包按域分组抽方法，保持行为零差。
- [obs] LightamerApp.swift:2480-2546 等 — `#if DEBUG` probe（resize/sidecar/import）与 ProcessInfo argv 读取限 DEBUG，`legacyLibraryEnabled` 已在装配点求值一次分发（KD-1 合规），body 无直接读。出处：房内约定 KD-4/KD-1。修复草图：无需改；probe 退役按 D-X2 政策。
- [obs] CropOverlayHost.swift:83-85 / CropOverlayView.swift:205-213 / LiquifyOverlayHost.swift:50-53 — body 内联 `record.params(of:)` 解码（小 struct，代价可忽略，静态无法定量）。出处：structure.md§Keep view init cheap。修复草图：如 profiler 显示热点再将解码上提 model 缓存；现不动。
- [obs] LiquifyOverlayHost.swift:142-152 — `.onEnded` 从捕获 `record` 重解码并提交“当前态”，若末 tick 的 live 重渲染尚未ARM可能丢末笔（CropOverlayView 用 lastLive 兜底，此处 `_ = target` 空转）。需运行时验证。出处：房内约定 D-H1 + dataflow 手势语义。修复草图：仿 CropOverlayView 引入 lastLive 末笔直提 commit。
- [obs] McpLauncherPanelView.swift:98-100 — `UserDefaults.standard` 直读发生在 model 动作（launch）而非 body，KD-4“body 零直读”合规；与 SettingsView @AppStorage 同 key 拼写。出处：房内约定 KD-4。修复草图：如收敛存储面可注入 defaultsصة实例；现不动。
- [obs] MaskOverlayHost.swift:81-83 — `layer` 经 `selectedLayer(in: layerStack)` 传递读整列，属 overlay 必需依赖；Canvas 已 draw-only 且 record 抽离可测。出处：dataflow.md§Cache derived values（传递依赖语义）。修复草图：现不动；若 layerStack 高频抖动再对 selectedLayer 做窄投影。
- [obs] SegmentEditingOverlayHost.swift:50 — `session` 经 `editingState.segmentSession` 整值读取后多字段使用，属真实消费非误订阅。出处：dataflow.md§Multiple individual reads are fine。修复草图：现不动。
- [obs] MaskToolbarView.swift:181-208 — sheet 内容依赖 presenter 继承的 @Environment（Settings/toolbar 层级 sheet，非 app-root Scene 层），M2-8-3 FINDING-A 的重注入规则仅约束 app-root Scene sheet，本处不触发。出处：房内约定（sheet 边界）+ AdjustmentTransferSheetContent 注释先例。修复草图：无需改。
- [obs] DrtPanelView.swift:156,186,280,315 — 四分區已是独立 View（AR-01 T3 模范），但各持 model 类引用读 `model.record.*` 同一 struct 属性，属同 record 域共享依赖，面板自编辑场景下可接受。出处：dataflow.md§Expose struct fields。修复草图：现不动；跨 record 抖动出现再展平字段。
- [obs] PresetManagerWindow.swift:179 — `ForEach(grouped, id: \.category)` 以可改名 category 作 section id，改名即 section 身份更替；section 无内部 state，影响可忽略。出处：foreach.md§Identity must outlive。修复草图：如后续 section 持有展开态再换稳定 id（如首 preset id 或持久分组 id）。

## 七维逐文件结论速览

- LightamerApp：拆分 obs / 数据流 minor×1（onChange） / ForEach PASS（静态 range + absoluteString）/ 动画 PASS（无自定义动画）/ 本地化 minor×1（verbatim 英文）+ 模范（rating/color 显式 switch）/ State-macro PASS / ContentBuilder PASS（overlay/background 均为 trailing 闭包）。
- McpLauncherPanelView：拆分 minor / 数据流 PASS（onChange 依赖同时用于渲染）/ ForEach N/A / 本地化 PASS（hint 在 model 层 String(localized:) 预解析）/ State PASS / ContentBuilder PASS。
- CropOverlayHost / CropOverlayView：七维基本 PASS，唯 body 内联 params 解码记 obs；CropOverlayView 的 lastLive 兜底为 D-H1 模范。
- InstancePickerOverlay：本地化 error + body 重算 major；ForEach(id:\.self 于 Int) PASS。
- LiquifyOverlayHost：末笔 commit 语义记 obs（需运行时验证）；其余 PASS。
- MaskOverlayHost：拆分 minor + 本地化 minor；Canvas draw-only 与 record 可测抽离为优。
- MaskToolbarView：error×2 + 拆分/闭包 Binding/数字格式 minor；Group(if/else) 非单孩、popover(item:) 形态 PASS，item id 记 minor。
- RetouchOverlayHost：七维 PASS（commit 读 live 无丢笔；canvas 独立）。
- SegmentEditingOverlayHost：拆分 minor + 组句 minor；AnyShapeStyle 三元为 modifiers.md 模范。
- PresetManagerWindow：分组重算/row 函数/组句 minor；List 行单根 HStack，unary PASS。
- SessionBrowserView：拆分 minor + pickerKey minor；cell task stale-guard 与 MergeDialogCount item 负载为模范；静态星级 ForEach PASS。
- SettingsView：页 model 内联构造 minor；legacy gate 装配点注入为 KD-1 模范。
- AdjustmentTransferView：拆分/textCase/闭包 Binding minor；SheetContent 重注入为房规模范。
- BackgroundTaskBarView：行方法 minor；defaultValue 双语 key 为本地化模范；单孩 Group 内为 if 条件属实工作 PASS。
- ColorMatchPanelView：拆分/闭包 Binding/onChange/数字格式 minor；onAppear 懒建 + D-H1 slider 为模范。
- DrtPanelView：四分區独立为结构模范；静态 switch 解析为本地化模范；record 共享依赖记 obs。
- EditorAdjustmentStackView：拆分 minor + onChange minor + note minor；容器级 .disabled(agentControl) 与 pageSession 缓存为模范。
- EditorNodeHeaderView：仅 EXIF 数字格式 minor；其余 PASS。

# FINDINGS-05（slice-05 深读审计）

## 结论头

**PASS / 0 error + 3 major + 23 minor + 11 obs**（本 slice 内计数）

判定基线：`.work/xcode27-skills/swiftui-specialist/references/` 下 structure.md / dataflow.md / environment.md / foreach.md / animations.md / localization.md / modifiers.md / soft-deprecation.md，以及 `.work/xcode27-skills/swiftui-whats-new-27/references/` 下 state-macro.md / content-builder.md。房内约定优先：KD-4（body 零 UserDefaults 直读）、app-root sheet 闭包禁裸 @Environment（内容面重注入/init 参数注入二选一）、`String.LocalizationValue("prefix_\(x)")` 插值形态禁止（动态查表键走显式 switch）、disable-not-unmount（agent 控制期用 `.disabled` 不卸载）、D-H1 begin/end 配对、2026-10-19 壳交接既定方向（NSApplicationDelegate + NSHostingView；SwiftUI App lifecycle 层观察照记、不作迁移阻断）。
纯只读审计：零源码改动，未跑构建/测试。行为级问题一律降级为 obs 并标「需运行时验证」。

## 实读文件清单（19/19，全文逐文件深读，无抽样；行数=wc实测）

| # | 文件 | 行数 | 七维速览（详见分级清单） |
|---|------|------|--------------------------|
| 1 | `UI/Shell/EditorTabRoute.swift` | 319 | 无 View（纯路由表）；七维 PASS |
| 2 | `UI/Shell/EditorToolRailView.swift` | 364 | 结构 minor×1、数据派生 minor×1；其余 PASS |
| 3 | `UI/Shell/EditorWorkspaceShellView.swift` | 238 | 结构 minor×1、onChange 隔离 minor×1；其余 PASS |
| 4 | `UI/Shell/FilmPanelView.swift` | 664 | 本地化 major×1、结构 minor×1、数据流 minor×1、ForEach minor×1、本地化 minor×1 |
| 5 | `UI/Shell/FilmstripView.swift` | 330 | ForEach minor×1；obs×1 |
| 6 | `UI/Shell/Nodes/EditorNodesPanelView.swift` | 634 | 结构 major×1、本地化 minor×1、数据流 minor×1 |
| 7 | `UI/Shell/RawDecodePanelView.swift` | 288 | 死状态 minor×1、本地化 minor×1；obs×1 |
| 8 | `UI/Shell/ScopePanelView.swift` | 243 | 七维 PASS；obs×1 |
| 9 | `UI/Shell/VersionsPanelView.swift` | 334 | 结构 minor×1、注释 minor×1；其余 PASS |
| 10 | `UI/Shell/WorkspaceHostView.swift` | 1837 | 本地化 minor×1；obs×3（含 sheet/闭包/文件组织） |
| 11 | `UI/Shell/WorkspaceModel.swift` | 490 | 无 View（纯 @Observable 模型，@MainActor 合规）；obs×1 |
| 12 | `UI/SidebarView.swift` | 1001 | 结构 major×1、派生计算 minor×1、注释 minor×1；obs×2 |
| 13 | `UI/SoftProofControlView.swift` | 127 | body 期 IO/重算 minor×1；其余 PASS |
| 14 | `UI/StatusBar.swift` | 59 | 七维 PASS |
| 15 | `UI/Theme/LightamerColors.swift` | 79 | 无 View（纯 token）；PASS |
| 16 | `UI/Theme/ThemeTokens.swift` | 110 | 无 View（纯 token）；PASS |
| 17 | `UI/Views/EnhanceDialog.swift` | 270 | 结构 minor×1、本地化 minor×1、body 期重活 minor×1 |
| 18 | `Yiyin/YiyinPanelView.swift` | 745 | 结构 minor×1；obs×1（与 Sidebar 共用） |
| 19 | `Yiyin/YiyinSheetSizing.swift` | 286 | 无 View（纯数学 + @Observable 模型，KD-4 注入式范例）；PASS |

全局维结论（全 slice）：动画维无 `withAnimation` 以外热点、无 `Animatable`，PASS；@State macro 维无 init 覆写/组合 wrapper/私有 memberwise 依赖（`EnhanceDialog.init` 的 `_model = State(initialValue:)` 与 `EditorNodesPanelView.init` 同形均为合规 FIX 形态），PASS；ViewBuilder 热点维无 `overlay(ShapeStyle…)` 直接传参、无 `TupleView` 硬编码、无 MapKit 空 builder、无 Charts 深分支（overlay 均为 trailing-closure 形态），PASS；条件式 view modifier（`.if`）全 slice 无定义无调用，PASS（modifiers.md）；soft-deprecated API 无检出（`onChange` 均为新双参形态、`confirmationDialog(presenting:)`、`ContentUnavailableView` 均为现行 API），PASS；custom environment/focused 键无闭包值（`WorkspaceModelKey` 持稳定类引用），PASS（environment.md§Closures in the Environment）；KD-4：body 零 `UserDefaults` 直读（唯一 `@AppStorage` 见 obs O6；`YiyinSheetResizeModel` 经注入 `YiyinSheetMetrics` 持久化，为 KD-4 范例），PASS。

---

## major（3）

- [major] `UI/Shell/FilmPanelView.swift:384-393` — `latitude_share_value` 的 `defaultValue` 内嵌已解析的内层 `String(localized:)`（`"\(String(localized: "latitude_share_below" …)) \(Int(…))%"`）：外层 key 的源文本在运行时由当前 locale 的内层解析结果拼装，catalog 条目不稳定，且 `%` 硬编码、占位无说明，m9 注释自称的“zh 语序交 catalog”实际未成立（内层标签在 defaultValue 求值时已按当前 locale 固化）。出处：localization.md§String Interpolation vs Concatenation + §Comments for Translators。修复草图：外层改为真 format 键（如 `defaultValue: "%@ %lld%%"` 并配 comment 说明两槽位语义），内层标签以参数传入而非拼入 defaultValue。
- [major] `UI/Shell/Nodes/EditorNodesPanelView.swift:82-117` — 600+ 行单失效边界：`content/chainView/header/edgesCanvas/cardsLayer/card/developCard/gradeCard/drtCard/filmCardView/menu` 全是同一 View 上的 `private var/func`，grade mix 是连续 live-tick（`setMixLive` 经 model 直写 document），拖动速率下整链（含全部卡片 + Canvas 边层 + preference 回读）逐 tick 重估；header（仅读 `fitToken`）亦被连带。出处：structure.md§Always use separate View types。修复草图：header / edgesCanvas / 单卡（含 slider 行）各抽独立 View 类型，窄输入（`name/isEnabled/mix/liveMix` 回调），panel 只留组合。
- [major] `UI/SidebarView.swift:182-206` — 1000+ 行单失效边界：current/orphan/smartAlbum/recent/watch/mode/5 catalog sections + 4 alert/confirmationDialog + `.task(id:)` 全挂同一 body，任一 dialog 草稿（`renameText/createName/organizationNameText`）或 `.task` 刷新都重估整树（含 `flatRows()` 重建 + `depthPrefixedName` 逐行建表）。出处：structure.md§Always use separate View types。修复草图：按 section 抽独立 View（dialog 状态下沉到各 section 内部），`refreshCatalogFaces` 结果经窄输入下发。

## minor（23）

- [minor] `UI/Shell/EditorToolRailView.swift:76-95,99-162,171-209` — `buttons/panel/historyPanel/historyRow` 为 `private var/func`，history 每次 tick 连带重估 icon 列（含 `ForEach(allCases)` 整列）。出处：structure.md§Always use separate View types。修复草图：`RailButtons(expanded:onSelect)` / `HistoryPanel(items:…)` 独立成类型。
- [minor] `UI/Shell/EditorToolRailView.swift:199,280-284` — `historyRows`（`enumerated().reversed().map`）在每次 body 求值重建派生数组。出处：foreach.md§Don't sort or filter inline in ForEach + dataflow.md§Cache derived values。修复草图：YSTEM history 侧缓存 newest-first 派生数组，view 只读现成数组。
- [minor] `UI/Shell/EditorWorkspaceShellView.swift:126-162` — `filmstrip/rightPane/scopeSlot/stackSlot` 为同一 shell 边界上的计算属性，selection 变化连带右栏。出处：structure.md§Always use separate View types。修复草图：右栏抽 `RightPane(scopesVisible:adjustmentStackVisible:…)` 独立类型（filmstrip 已是独立 View，沿用）。
- [minor] `UI/Shell/EditorWorkspaceShellView.swift:106-109` — `.onChange(of: workspace.editorGrid?.selectedIDs)` 直接挂在重型 shell body 作用域。出处：dataflow.md§Isolating onChange(of:) side-effect invalidation。修复草图：仿 WorkspaceHostView 的 `PendingAIEnhanceModifier` 形态下沉为 ViewModifier。
- [minor] `UI/Shell/FilmPanelView.swift:71-90,94-115` — AR-01 已拆三 section 后残留：`header/enableEntry` 仍是 panel 边界上的 `private var`（header 与 model tick 无关却被连带）。出处：structure.md§Always use separate View types。修复草图：抽 `FilmPanelHeader(onClose:)` / `FilmEnableEntry(isReady:onEnable:)`。
- [minor] `UI/Shell/FilmPanelView.swift:124-285,295-441,451-664` — 三 section 以整 `model: FilmPanelModel`（@Observable）为输入并经计算属性 `model.record`（FilmRecord struct）读多字段：观察系统对整 `record` 建依赖，任一 history 写入（即使非 film 腿）都使三 section 全重估（计算属性无 Equatable 短路）。出处：dataflow.md§Expose struct fields as individual @Observable properties + §Cache derived values。修复草图：高频读面（film/paper stock、shifts、stats/descriptor/anchors）上提为 model 侧独立存储属性（`didSet` 对齐），view 读窄属性。
- [minor] `UI/Shell/FilmPanelView.swift:138,154` — `ForEach(model.filmStocks, id: \.info.stock)` 的 id 为 `Optional<String>`，配套 `.tag(profile.info.stock ?? "")` 使缺 stock 资产在 `""` 上碰撞。出处：foreach.md§Keep the id cheap to hash + §稳定唯一要求。修复草图：以非空 stock 为 id（store 加载期已保证 `missingStockId` 抛错，可收紧类型为非空）或 `ForEach` 改由 Identifiable 包装。
- [minor] `UI/Shell/FilmPanelView.swift:187-199` — slider readout 用 `String(format: "%.2f"/"%+.2f EV")` 硬编码小数与单位，经 `Text(readout)` 显示，locale 数字与单位语序不可调。出处：localization.md§Formatting Dates, Numbers, and Currencies。修复草图：readout 改走 `Text(value, format:)` / format-style 插值，单位独立成可本地化片段。
- [minor] `UI/Shell/FilmstripView.swift:219` — `ForEach(grid.rows, id: \.id)` 用显式 key path；`LibraryImageRow` 为自有类型（`Sendable, Equatable`，id 为 `Int64` 稳定键），依 skill 应补 `Identifiable` 以便 `List/sheet(item:)` 复用。出处：foreach.md§Prefer Identifiable conformance。修复草图：给 `LibraryImageRow` 加 `Identifiable`（`var id: Int64 { rowID }` 视字段名），调用点去 `id:`。
- [minor] `UI/Shell/RawDecodePanelView.swift:37,258,265` — `isReloading` 只写不读（body 无任何读取点，busy caption 实际不存在；且同步连写在同一 runloop 合并，置位永不可见）。出处：dataflow.md§View-local state with @State（写面无读面的死状态）。修复草图：删状态；若要真 busy face，改为 load 链的异步可观察态并在 body 消费。
- [minor] `UI/Shell/RawDecodePanelView.swift:86-89,154,187-188` — `Text("RAW 8"/"RAW 9")` 技术专名未 `verbatim:`（进 catalog 占 key）；`Text("\(Int(peak)) nits")` 单位硬编码；`transferName` 的 `String(localized:) + String(format:)` 用 `+` 拼接（产物为 String，locale 数字不适配）。出处：localization.md§SwiftUI Views Localize String Literals（`verbatim:`）+ §String Interpolation vs Concatenation + §Formatting。修复草图：版本名改 `Text(verbatim:)`；peak/gamma 改 format-style 插值单字面量。
- [minor] `UI/Shell/VersionsPanelView.swift:97-127,131-178,182-214,239-326` — `header/emptyState/versionList/row` 同边界，slots 变化连带 header。出处：structure.md§Always use separate View types。修复草图：`VersionsHeader/CreateBranchButtons` 与 `VersionRow(slot:isActive:…)` 独立成类型（row 已是 func 带参，顺势搬运）。
- [minor] `UI/Shell/VersionsPanelView.swift:71-76` — `defaultVersionName` 的 `"Version \(ordinal)"` 插值缺 `comment`（占位语义不明）。出处：localization.md§Comments for Translators。修复草图：补 `comment:` 说明 ordinal 为新槽位序号。
- [minor] `UI/Views/EnhanceDialog.swift:89-120,149-208` — `controls/modelStatusRow/progressArea` 为同边界计算属性，`phase` 进度 tick 连带整 dialog（含两预览窗）重估。出处：structure.md§Always use separate View types。修复草图：controls / statusRow / progressArea 按 `choice/phase` 窄输入拆类型。
- [minor] `UI/Views/EnhanceDialog.swift:20-270`（全文件） — 全文件中文裸字面量（标题/按钮/说明/状态文案零 `String(localized:)`），与 `UI/Shell` 系清一色 opaque key + `defaultValue` 惯例不一致；裸字面量虽可提取但源语言与既有 catalog/审核口径分叉。出处：localization.md§SwiftUI Views Localize String Literals（按项目既定惯例二选一并一致）。修复草图：引入 `enhance_*` opaque 键 + 中文 `defaultValue`（源文零差，catalog 增量收敛）。
- [minor] `UI/Views/EnhanceDialog.swift:225,244-269` — `previewPane` 在 body 求值期同步跑 `displayImage`（逐像素 uint16 循环 + `CGImage` 分配）。出处：structure.md§Keep view init cheap。修复草图：model 侧缓存 `NSImage`（frame 变更时一算），view 只读缓存。
- [minor] `UI/SoftProofControlView.swift:39,45,120-126` — `recentEntries`（filter + `firstIndex` sort）与 `installedProfiles()` 磁盘枚举在每次 body 求值执行两次（recent + all-printers `ForEach` 内联调用亦重算）。出处：structure.md§Keep view init cheap。修复草图：`.task` 一次装载到 `@State`，picker 读缓存。
- [minor] `UI/SidebarView.swift:632,722-725,736-746` — `catalogTree.flatRows()` 每次 body 重建 + `moveToMenu` 内 `flatCategories().filter` 内联过滤 + `depthPrefixedName` 逐行重建 id 表（O(n²) 于树规模）。出处：foreach.md§Don't sort or filter inline + dataflow.md§Cache derived values。修复草图：tree 侧缓存展平/深度表，view 读现成数组。
- [minor] `UI/SidebarView.swift:371-375` — `Text("session_counts \(total) \(edited) \(orphans)")` 三占位零 `comment`。出处：localization.md§Comments for Translators。修复草图：改 `String(localized:defaultValue:comment:)` 并按序说明三数语义。
- [minor] `UI/Shell/Nodes/EditorNodesPanelView.swift:456` — `Text("\(Int((Double(node.mix) * 100).rounded()))%")` 插值字面量尾随裸 `%`，合成 format 串 `%lld%` 尾 `%` 为不完整转换符。出处：localization.md§String Interpolation vs Concatenation。修复草图：改 `Text(mixValue, format: .percent…)` 或数字与 `%` 分两个 Text。
- [minor] `UI/Shell/Nodes/EditorNodesPanelView.swift:93` — `.onChange(of: model.document?.nodes.map(\.id))` 挂重型 canvas body 作用域（每次 document 变化全链重估已是必然，观察者本身亦在 body 依赖面内）。出处：dataflow.md§Isolating onChange side-effect invalidation。修复草图：下沉为 ViewModifier（与 M22 结构拆分同批）。
- [minor] `Yiyin/YiyinPanelView.swift:104-345,361-429,447-668` — 双 section + N 模板行（含 `templateEditor/fontSetting`）全同边界；`params/bordersParams` 每次访问经 `PanelEditing.params` 重解，任一 discrete commit 全面板重估。出处：structure.md§Always use separate View types（含 Multi-section detail views 形态）。修复草图：borders/watermark/单模板行各抽类型，窄输入（params 值 + 回调；缓冲下沉行内）。
- [minor] `UI/Shell/WorkspaceHostView.swift:1642-1644` — `pidText` 的 `"未知"` 为 Swift 硬编码中文（不进 catalog，英文 locale 下残留中文）。出处：localization.md§Localizing Variables + §String(localized:) Outside SwiftUI Views。修复草图：抽 `project_read_only_unknown_pid` 键，插值传入。

## obs（11，需运行时验证或约定照记）

- [obs] `UI/Shell/FilmstripView.swift:196-215,240-246` — `model` 为 nil 直到 `onAppear` 才建，首帧 rows 非空仍走 `emptyState`（一帧闪空）；同 view 双 `.onTapGesture`（单击 + `count: 2`）共存，单击是否在双击序列中误触发需真机确认。需运行时验证。修复草图：`model` 改 init 注入（`State(initialValue:)` 如 EnhanceDialog 形态）；手势二选一或经 `exclusively(before:)` 编排后实机验证。
- [obs] `UI/Shell/ScopePanelView.swift:213-242` — `readWaveform` 在 view `.task`（main actor）同步 `getBytes`（≤553KB、≤15Hz），主线程阻塞待 profiler 定量。需运行时验证。修复草图：搬后台解析后回跳，或采样节流已够则持现。
- [obs] `UI/Shell/WorkspaceModel.swift:173-176` — `currentRow` 每次访问 `rows.first(where:)` 线性扫（10k 行规模 × shell task 触发频率）。当前仅 task 路径消费，影响可忽略；需 profiler 确认再缓存。修复草图：id→row 索引随 grid 同步缓存。
- [obs] `UI/Shell/WorkspaceHostView.swift:248-252,1436-1522` — app-root sheet（`YiyinTopBarSheet`，`WorkspaceHostView` 即 gate=false shell root，属 app-root Scene 层）内容面经裸 `@Environment(EditorState/PipeCoordinator.self)` 继承，未走“重注入/init 参数”二选一（`onDismiss/domainSize` 走 init 合规，coordinator 仍靠继承；`InspectorEditSession` 在 body 内现场构造亦绑继承链）。M2-8-3 FINDING-A 的重注入规则约束的正是此层；现状实机可用，故记 obs 不记 violation。出处：房内约定（app-root sheet 闭包禁裸 @Environment）。修复草图：sheet 闭包内补 `.environment(editorState).environment(pipeCoordinator)` 显式重注入，行为零差后实机验证。
- [obs] `UI/Shell/WorkspaceHostView.swift:622-692` — `WorkspaceTopBar` 窄输入合规，但三个 `() -> Void` 闭包每 host body 求值重建（View struct 字段逐项比较下闭包恒不等），host 重估即顶栏重估。host 重估本已稀少，影响待 Instruments 确认。出处：dataflow.md§Passing data into views。修复草图：持现；若顶栏成热点再将回调收敛为单一 action enum。
- [obs] `UI/SidebarView.swift:114-115,178-180` — `@AppStorage(organizationModeStorageKey)` body 直读（KD-4“body 零直读”字面系 defaults 耦合；与 `ContentView` 同 key 双点存放，RQ-16-12 冷启动恒 Sessions 语义由首帧覆写保证）。`YiyinSheetMetrics` 注入式为 KD-4 范例方向；此处迁移将改动冷启动覆写链，故记 obs 不记 violation。出处：房内约定 KD-4。修复草图：持现；若收敛则把覆写 + 订阅收进单一注入 store。
- [obs] `UI/SidebarView.swift:151,155,548-550` / `Yiyin/YiyinPanelView.swift:303,411` — `String(localized: String.LocalizationValue(variable))` 包裹变量：变量值均为显式 switch 返回的静态字面量（catalog 可提取、运行时查表命中），非房规禁止的 `"prefix_\(x)"` 插值拼 key 形态，故合规；唯双重包装可简化。出处：房内约定（插值形态禁止条）+ localization.md§Localizing Variables。修复草图：switch 直接返回 `LocalizedStringResource`，调用点 `Text(key)`/`String(localized: key)` 去一层包装。
- [obs] `Yiyin/YiyinPanelView.swift:527` — `Button(field.zhName)`：`zhName` 字面即声明 zh-only 面（与 `pidText“未知”` 同族但此处 API 名已显式限域）。英文 locale 下是否接受中文残留属产品决策，需确认。修复草图：持现或补 `enName` 双语面。
- [obs] `UI/Shell/RawDecodePanelView.swift:224-232,254-266` — `sliderRow` 的 `Binding.set` 每 tick 即 `commit()`（写 session carrier + 重发 `EditorState.load` 重解码），无 D-H1 live/commit 分 leg（注释称“committed on every change”为设计）。是否 history 泛滥/重解卡顿需运行时验证。出处：房内约定 D-H1。修复草图：若实机卡顿，仿 FilmPanel 引入 begin/end（live tick 零历史 + 松手单 commit）。
- [obs] `UI/Shell/WorkspaceHostView.swift:856-1256,1308-1684` — 单文件 1837 行寄宿 `AIEntryPointCoordinator` + 5 sheet/dialog + 2 mount + 4 modifier：均为独立类型故失效边界不受影响，仅组织成本。出处：structure.md（组织节）。修复草图：按域拆文件（coordinator / sheets / modifiers），零行为差。
- [obs] 壳交接照记 — 本 slice 无 SwiftUI App lifecycle 层代码（无 `@main App`、无 Scene 委托），19 文件全为 window-content 层 View/模型/纯逻辑；2026-10-19 起 `NSApplicationDelegate + NSHostingView` 既定方向无新增阻断点。出处：房内约定（壳交接条）。修复草图：无需动作。

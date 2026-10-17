# Xcode 27 官方 Skills 对照审计 — A 路(机械扫描)

- **日期**:2026-10-13
- **审计员**:A 路 subagent(纯只读机械扫描;零代码改动、零 commit)
- **范围**:`App/Sources`(196 文件,App 层)+ `Project.swift` / 生成 `Lightamer.xcodeproj/project.pbxproj` / `Tests/`
- **Skill 正本**:`.work/xcode27-skills/`(登记正本 `research/XCODE27-SKILLS.md`)
- **口径**:`finding` = 本仓存在的真实差距/真废弃用法(机械判定,建议处置);`note` = 需深读/登记/N/A 项,不构成缺陷。

# PASS / 31 finding + 9 note

(finding 明细:§1 软废弃真用法 28 + §3 构建面差距 3;note:§1 需深读 3 类 + §2 N/A 4 + §3 裁决挂账 2)

---

## §1 软废弃 API 全量扫描(swiftui-specialist/references/soft-deprecated-apis.md)

**方法**:解析六个节(Types 22 / Protocols 3 / Initializers 57 / Functions & Methods 88 / Properties 13 / Subscripts 2)全部反引号符号,归并为约 110 个可 grep token,`rg -w`(word-boundary)逐个跑 `App/Sources --type swift`,命中行人工核形态(注释行不计;类型名与使用形态分开核)。

### 1.1 全零节(覆盖证明)

- **Types 22/22 零命中**:CarouselTabViewStyle、MenuButton(类型形,排除 MenuButtonStyle 后零)、ActionSheet(类型形)、ColumnNavigationViewStyle、Alert(构造形 `Alert(`,12 处 `.alert(` 全部为现代 `alert(_:isPresented:presenting:actions:)` 形,逐样本核对无 `alert(isPresented:content:)` 旧闭包形)、BorderedButtonMenuStyle、RotationGesture、PresentationMode、MagnificationGesture、ContextMenu(类型形)、PullDownMenuButtonStyle、BorderlessPullDownMenuButtonStyle、BorderlessButtonMenuButtonStyle、DefaultMenuButtonStyle、DefaultNavigationViewStyle、BorderlessButtonMenuStyle、DoubleColumnNavigationViewStyle、NavigationView(排除 *Style 后零)、PopUpButtonPickerStyle、StackNavigationViewStyle、ContentSizeCategory、ControlActiveState。
- **Protocols 3/3 零命中**:NavigationViewStyle、AnimatableModifier、MenuButtonStyle。
- **Initializers**:Section(header:/footer:、GroupBox(label:、alternatesRowBackgrounds、showsByDefault、NavigationLink(destination:/destinationName、tint-init 样式族(LinearProgressViewStyle/CircularProgressViewStyle/BorderedButtonStyle/LinearGaugeStyle/SwitchToggleStyle with tint:)、Color(UIColor/NSColor/CGColor、PasteButton、supportedTypes 全零;Picker( 全部为现代 `Picker(_:selection:content:)` 标题形(6 处);TabView( 零;Slider( 全部为自定义 LightamerSlider 或无 label 的现代 `Slider(value:in:onEditingChanged:)`(非废弃——废弃形态要求 minimumValueLabel/maximumValueLabel 参数);Stepper( 2 处见 1.3 note。
- **Functions & Methods**:accessibility(value:/label:/hint:/hidden:/identifier:/sortPriority:/activationPoint:/addTraits:/removeTraits:、actionSheet、onContinuousHover、listRowPlatterColor、hasItemsConforming、onInsert、onPasteCommand、navigationBarItems、statusBarHidden/statusBar(、autocapitalization、disableAutocorrection、navigationBarHidden、navigationBarTitle、navigationViewStyle、toolbarBackground、`.toolbar(`(可见性实参形,2 处 `.toolbar {` builder 形非废弃)、searchable、tabItem、collapsible、mask(、cornerRadius、edgesIgnoringSafeArea、.colorScheme(、Font.system(_ style:)、menuButtonStyle、TabViewCustomization、presentationMode、navigationBarLeading/Trailing、sizeCategory、controlActiveState、systemDark 全零。
- **Subscripts 2/2 零命中**:TabViewCustomization sectionID/sidebarVisibility。
- **Properties**:唯一命中 = `.menuStyle(.borderlessButton)`(见下)。

### 1.2 真软废弃用法(finding ×28)

| # | 符号(skill 出处节) | 命中 | file:line | 初判 |
|---|---|---|---|---|
| 1 | `ScrollView(_:showsIndicators:content:)`(Initializers) | 3 | `App/Sources/Lightamer/UI/FilterBarView.swift:189`;`App/Sources/Lightamer/UI/CatalogFilterBarView.swift:169`;`App/Sources/Lightamer/Library/Views/LibraryInspectorView.swift:180` | 真废弃。改 `ScrollView(.horizontal) { … }.scrollIndicators(.hidden)` |
| 2 | `TextField(_:text:onCommit:)`(Initializers) | 1 | `App/Sources/Lightamer/Export/ExportNamingEditor.swift:182-184`(`TextField(title, text: $renameName, onCommit: commitRename)`) | 真废弃。改 `.onSubmit(commitRename)` |
| 3 | `View.foregroundColor(_:)`(Functions) | 1 | `App/Sources/Lightamer/UI/SessionBrowserView.swift:541`(`.foregroundColor(.orange.opacity(0.7))`) | 真废弃。全仓唯一一处,改 `.foregroundStyle(...)` |
| 4 | `MenuStyle.static borderlessButton`(Properties) | 5 | `App/Sources/Lightamer/UI/FilterBarView.swift:323`;`App/Sources/Lightamer/UI/EDRControlView.swift:58`;`App/Sources/Lightamer/UI/SoftProofControlView.swift:66`;`App/Sources/Lightamer/UI/CatalogFilterBarView.swift:253`;`App/Sources/Lightamer/UI/Inspector/PresetPanelView.swift:98`(均 `.menuStyle(.borderlessButton)`) | 真废弃。skill 替代 = `.menuStyle(.button)` + `.buttonStyle(.borderless)` |
| 5 | `View.coordinateSpace(name:)`(Functions) | 1 | `App/Sources/Lightamer/UI/Shell/Nodes/EditorNodesPanelView.swift:273` | 真废弃。改 `.coordinateSpace(Self.canvasSpace)`(macOS 15+ 新形) |
| 6 | `View.dropDestination(for:action:isTargeted:)` Bool-action 形(Functions) | 2 | `App/Sources/Lightamer/UI/SidebarView.swift:709`(category 拖入,闭包 `return true/false` + `isTargeted:`);`App/Sources/Lightamer/UI/SidebarView.swift:809`(collection 同形) | 真废弃。skill 替代 = `dropDestination(for:isEnabled:action:)` 带 DropSession 参数 |
| 7 | `View.overlay(_ overlay:alignment:)` 旧 View 重载(Functions) | 6 | `App/Sources/Lightamer/UI/SessionBrowserView.swift:596`;`App/Sources/Lightamer/UI/CatalogBrowserView.swift:336`;`App/Sources/Lightamer/UI/SoftProofControlView.swift:101`;`App/Sources/Lightamer/UI/EDRControlView.swift:82`;`App/Sources/Lightamer/UI/Shell/Nodes/EditorNodesPanelView.swift:612`;`App/Sources/Lightamer/UI/Inspector/CurveEditorView.swift:104`(实参均为 shape strokeBorder/stroke 的 `some View`) | 真废弃。改尾闭包形 `.overlay { … }` |
| 8 | `View.background(_ background:alignment:)` 旧 View 重载(Functions) | 9 | `App/Sources/Lightamer/UI/FilterBarView.swift:114`、`:218`;`App/Sources/Lightamer/UI/SessionBrowserView.swift:649`;`App/Sources/Lightamer/UI/CatalogFilterBarView.swift:198`;`App/Sources/Lightamer/UI/SidebarView.swift:417`;`App/Sources/Lightamer/UI/CatalogBrowserView.swift:380`;`App/Sources/Lightamer/UI/Shell/Nodes/EditorNodesPanelView.swift:611`;`App/Sources/Lightamer/UI/Inspector/LayersPanelView.swift:602`(实参 shape `.fill(...)`);`App/Sources/Lightamer/UI/LightamerApp.swift:552`(自定义 View `WindowCapture`) | 真废弃。改尾闭包形。注:其余 `.background(Color)/.background(.bar)/.background(.ultraThinMaterial, in:)` 走 ShapeStyle/`in:` 重载,**非**废弃,不计 |

**小计:28 处真软废弃**(软废弃 = 不产生弃用警告、不阻断 macOS 27 编译,均为机械可修的低风险卫生项)。

### 1.3 需深读(note ×3 类,34 处)

- **note-1(note)**:`Font.system(size:)` 族 ×31(如 `App/Sources/Lightamer/UI/SessionBrowserView.swift:572,645` 等)。soft-deprecated 列表把 `system(size:weight:design:)` 旧默认参数形标废、替代名相同。调用语法两重载均可绑定,Swift 重载消歧 disfavor 废弃臂 → 大概率已落新重载,零行动;如要消除不确定性,B 路对单点跑编译器 `-swift-version` 诊断核。
- **note-2(note)**:`GeometryProxy.frame(in coordinateSpace:)` ×1 — `App/Sources/Lightamer/UI/Shell/Nodes/EditorNodesPanelView.swift:255`(`proxy.frame(in: .named(Self.canvasSpace))`)。`.named` 字面量可经 CoordinateSpaceProtocol 解析到新重载,亦可落到废弃 CoordinateSpace 重载;判需深读(单点)。
- **note-3(note)**:`Stepper(value:in:step:) { }` 尾闭包形 ×2 — `App/Sources/Lightamer/Library/Views/LibraryAutoStackDialog.swift:39`;`App/Sources/Lightamer/UI/Shell/FilmPanelView.swift:442`。尾闭包绑定语义下新旧重载均可接受,废弃臂被 disfavor → 大概率落新签名 `Stepper(value:in:step:label:onEditingChanged:)`;零行动登记。

### 1.4 误报类别(不计,记录防复查翻车)

- 自定义 `onCommit` 闭包 ×8:`App/Sources/Lightamer/UI/EditorAreaView.swift:112,136,159`、`App/Sources/Lightamer/UI/Overlay/CropOverlayHost.swift:76,105,107`、`App/Sources/Lightamer/UI/Overlay/LiquifyOverlayHost.swift:46,150,165` — 均为项目自有回调类型(`var onCommit: (ModuleInstance, String) -> Void`),非 SwiftUI API。
- `onEditingChanged` ×1:`App/Sources/Lightamer/UI/Shell/ColorMatchPanelView.swift:200` — 现代 `Slider(value:in:onEditingChanged:)`(无 label 参数,不在废弃形态内)。
- `Color.accentColor` 静态属性读取 ×若干 — 废弃的是 `View.accentColor(_:)` 修饰符,属性读非废弃;`.color(.accentColor)`(GraphicsContext)同理。
- `.onTapGesture(count:)`/`.onTapGesture { }` ×10 — 废弃形要求 `coordinateSpace:` 参数,各命中均无。
- `SpatialTapGesture()` 无参 ×1(`App/Sources/Lightamer/UI/EditorAreaView.swift:292`)— 废弃形为 `init(count:coordinateSpace:)`。
- `CGColor(gray:...)` ×3(`App/Sources/Lightamer/MCP/Tools/CullingToolset.swift:977,1003,1010`)— CoreGraphics 构造,非 SwiftUI `Color(CGColor)`。
- `NSColor(...).cgColor` ×1(`App/Sources/Lightamer/UI/EditorMTKView.swift:95`)— NSColor 属性,非 SwiftUI `Color.cgColor`。
- `LightamerColors.surface` 等传入 `.background(...)` — `color(_:)` 返回 `Color`(Theme/LightamerColors.swift),走 ShapeStyle 重载非废弃。

---

## §2 whats-new-27 陷阱机械面(swiftui-whats-new-27/references/{state-macro,content-builder,toolbar}.md)

**方法**:只提取可 grep 模式跑机械查;判断级(语义改写建议)留 B 路。

| # | 机检项 | 出处 | 结果 | 判 |
|---|---|---|---|---|
| M1 | `@State` 带初始值 + `init` 内 `self.<stateVar> =` 再赋值(「used before being initialized」反模式) | state-macro.md §Init Assignment Errors | 全 App/Sources 扫描(@State 声明名 ↔ self. 赋值名交叉) **零命中**;合规 `State(initialValue:)` 形 ×5(ImportModeDialog.swift ×3、EnhanceDialog.swift:1、DrtPanelView.swift:1) | PASS |
| M2 | `@State` 与其他属性包装器堆叠(synthesized `_x` redeclaration) | state-macro.md §Redeclaration | 多行正则零命中 | PASS |
| M3 | 私有 memberwise init 依赖合成(state-macro §Private memberwise) | — | 不可机械 grep(需编译器诊断),**留 B 路** | note |
| C1 | 旧 `overlay/background` 直传 `ShapeStyle.opacity/.blendMode` 表达式(content-builder 歧义源) | content-builder.md §Ambiguous ShapeStyle | 正则零命中;§1.2 的 15 处旧重载实参均为 View/Shape,不受此歧义影响(但仍建议顺手换尾闭包形,见 §1.2 #7/#8) | PASS |
| C2 | 他模块影子 SwiftUI 类型(`Color`/`Text` 同名冲突 → ambiguous use) | content-builder.md §Ambiguous Type References | import 面 = Apple 框架 + LightamerCore/IOP + MCP + WebP + NIO,无自定义 Color/Text 导出模块;MCP 目录命中均为注释/字符串 | PASS |
| C3 | `TupleView`/`TupleContent` 出现在泛型参数 | content-builder.md §TupleView | 全仓零命中 | PASS |
| C4 | MapKit + 空 builder 体 / `#if` 空 else(EmptyMapContent 歧义) | content-builder.md §Empty Builder Body | `import MapKit`、`import Charts` 全零;空 `Group { }`/`VStack { }` 零命中 | PASS(N/A) |
| C5 | Charts 深分支类型检查超时 | content-builder.md §Charts | 仅 back-deployment(< OS 27)受影响;本仓 floor = macOS 27.0(Project.swift 每 target `deploymentTargets: .macOS("27.0")`)→ 结构性免疫 | PASS(N/A) |
| T1 | toolbar 新 API 需 gating(部署目标 < 27 时) | toolbar.md §Deployment target below SDK 27 | floor = 27 → 无需 gating;且 8 个新 API(visibilityPriority/ToolbarOverflowMenu/topBarPinnedTrailing/toolbarMinimizeBehavior/contentMarginsRemoved/toolbarVisibility 等)采纳数 = 0(纯登记,非缺陷) | PASS |
| T2 | `ToolbarPlacement.statusBar` 平台限制(iOS-only) | toolbar.md §Status bar visibility | macOS 专属 app → N/A | note |

**§2 小计:0 finding;机检陷阱清单全过**(M3 留 B 路)。

---

## §3 构建设置安全审计(audit-xcode-security-settings)

**方法**:SKILL.md + 16 份 references 全读,提取建议清单;逐项对照 `Project.swift`(Tuist manifest,7 target + 2 appex + 1 UI test)与生成产物 `Lightamer.xcodeproj/project.pbxproj` 实测值。语言面实测:App/Core/IOP/Tests 全 Swift,唯一非 Swift 文件 = `LightamerIOP/Sources/Common/LabMath.h`(**Metal shader 头,仅被 `.metal` #include,非 C 编译单元**)→ 按 skill 自己的 Scope 规则,一切 C/C++/ObjC 限定设置 = **N/A(纯 Swift)**。

### 3.1 对照表(建议 / 现状 / 差距 / 优先级 / 相容性)

| # | skill 建议项(出处) | 本仓现状 | 差距 | 优先级 | 相容性 |
|---|---|---|---|---|---|
| F1 | **`ENABLE_ENHANCED_SECURITY = YES`**(项目级,enhanced-security.md §Part A;级联 pointer-auth/stack-zero-init/security warnings/typed allocators) | pbxproj 实测 **0 命中**(默认 NO) | **finding** | P1(先裁决再动,见 F4) | 相容性存疑:runtime 侧保护靠 hardened-process entitlements 族,而 restricted entitlements 在无 Apple 签名链(2026-09-27 终裁 unsigned DMG/zip 分发)下不生效 → 编译侧(ENABLE_ENHANCED_SECURITY 本体 + 级联警告)仍有效。**需人工裁决**:本地开发加固收益 vs 分发形态 |
| F2 | **hardened-process entitlements 族**(required: `com.apple.security.hardened-process` + `enhanced-security-version-string="2"`;default-ON: hardened-heap / dyld-ro / platform-restrictions-string="2";enhanced-security.md §Part B) | **app target 无 .entitlements 文件**;两个 appex 的 entitlements(`App/Extensions/QuickLook/LightamerQuickLook.entitlements`、`App/Extensions/Spotlight/LightamerSpotlight.entitlements`)均为仅注释的空 dict | **finding** | P1(与 F1 同门) | 同 F4 裁决;若裁决走加固,三 target(app + 2 appex)都要补 |
| F3 | **`ENABLE_POINTER_AUTHENTICATION = YES`**(级联自 F1;arm64e slice) + **SPM arm64e flags**(pointer-authentication.md §Swift Package Manager Support:`macOSPackagesShouldBuildARM64e` 写入 workspace xcsettings) | pbxproj 0 命中;workspace flags 未配置 | **finding** | P2 | 依赖面有利:两个 SPM 包(Swift-WebP[libwebp C 源码构建] + MCP swift-sdk)均源码构建、无预编 xcframework → arm64e 可构建,无 binary-dependency 豁免需求;unsigned 分发下收益限于本地运行面 |
| F4 | **Hardware memory tagging**(MTE,`checked-allocations` + soft-mode;hardware-memory-tagging.md) | 未配置(default-OFF,skill 只要求报状态) | **note(挂账,不立项)** | — | 硬件门 = Mac M5+;当前开发机 M2(AGENTS.md 资源监控节)→ 现阶段无从验证;skill 自己的裁决矩阵对 pure Swift 建议 Phase 1+Runtime Restrictions+Read-Only Memory,MTE 属 Phase 4 可选项 |
| F5 | **Checked pointer arithmetic**(CPA2,`arm64e.x1` slice + enforcement entitlement;checked-pointer-arithmetic.md) | 未配置 | **note(N/A)** | — | run-time enforcement 硬件 = iOS A20 Pro / watchOS S11 独占,macOS 无 enforcement 硬件 → N/A + 理由(skill 规定 N/A 必标理由) |
| W1 | Compiler warnings 5 项(security-settings-reference.md §Warnings;scope C/C++/ObjC) | pbxproj 实测:`GCC_WARN_ABOUT_RETURN_TYPE=YES_ERROR` ✓、`GCC_WARN_UNINITIALIZED_AUTOS=YES_AGGRESSIVE` ✓、`GCC_WARN_64_TO_32_BIT_CONVERSION=YES` ✓ 已硬化;`CLANG_WARN_IMPLICIT_FALLTHROUGH`、`GCC_TREAT_IMPLICIT_FUNCTION_DECLARATIONS_AS_ERRORS` 未显式设置 | **note(N/A)** | — | 纯 Swift(仅 Metal 头),scope 不适用;且前三项本就已在 pbxproj(Xcode/Tuist 默认写入)——「skip the whole step if pure Swift」skill 自有规则命中 |
| W2 | Static analyzer + clang-tidy(`CLANG_ANALYZER_SECURITY_*` ×3、`CLANG_TIDY_*`;scope C/C++/ObjC) | 现有 analyzer 项仅 Xcode 默认三件(LOCALIZABILITY_NONNULL_NUMBER_OBJECT);security 族未设 | **note(N/A)** | — | 同 W1,scope 不适用 |
| A1 | Additional diagnostics(`CLANG_WARN_SUSPICIOUS_IMPLICIT_CONVERSION` 等 4 项;additional-settings.md) | 未设 | **note(N/A)** | — | scope 全部 C/C++/ObjC |
| ✓ | `ENABLE_HARDENED_RUNTIME`(DIST-5) | **Release=YES ✓**(Project.swift:64-70);Debug=NO 是**有档可查的 deliberate**(Project.swift:56-63 注释:Xcode 26 debug-dylib + library-validation 陷阱;`ENABLE_DEBUG_DYLIB=NO` 同批)——精确符合 skill「deliberately disabled + documented rationale」谓词,不触发询问 | 已达标 | — | 完全相容 |
| ✓ | Universal/Release slice 检查(universal-binaries-for-libraries.md:框架 target 需 Release 出双 slice) | `ONLY_ACTIVE_ARCH=YES` 实测仅出现在 Debug 配置块(pbxproj ×1,毗邻 `MTL_ENABLE_DEBUG_INFO=YES`);Release 未设 → archive 走 ARCHS_STANDARD 全量 | 已达标(启用 F3 时自动含 arm64e) | — | 相容 |
| ✓ | 语言级防线 | `SWIFT_VERSION=6.0` + `SWIFT_STRICT_CONCURRENCY=complete`(D-33)+ 手动稳定签名身份(TCC 键控)已在 baseSettings | 已达标(skill 范围外,一并登记) | — | — |

### 3.2 构建面差距 Top 5(汇报口径)

1. **`ENABLE_ENHANCED_SECURITY` 完全缺席**(pbxproj 0 命中)— 总开关;编译侧级联(安全警告族/stack zero-init/typed allocators)与签名形态解耦,可先只开编译侧。
2. **hardened-process entitlements 族全缺** — app 无 entitlements 文件、appex 空 dict;F4 裁决前不动。
3. **`ENABLE_POINTER_AUTHENTICATION` + SPM arm64e workspace flags 未配** — 源码构建依赖无豁免需求,是三者中落地摩擦最小的一项。
4. **MTE 挂账** — default-OFF,skill 仅要求报状态;硬件门 M5+(当前 M2)→ 裁决后按 soft-mode 路线启动。
5. **CPA2 = N/A** — macOS 无 enforcement 硬件;如未来只追 `arm64e.x1` slice 需与 F3 同批(`ENABLE_HARDWARE_CHECKED_POINTER_ARITHMETIC_SLICE`)。

---

## §4 modernize-tests 快评(modernize-tests/SKILL.md)

**实测数字**(Tests/ 全量,427 个 .swift 文件):

| 指标 | 值 |
|---|---|
| `import XCTest` 文件 | **426** |
| `import Testing` 文件 | **0** |
| 混合 import 文件 | 0 |
| XCTest test 方法(`func test*`) | **3,968** |
| XCTestCase 类 | 434 |
| `XCTAssert*` 断言调用 | **15,479** |
| `#expect`/`#require` | 0 |
| `measure {}` 性能 API(迁移阻断项) | **0** |
| XCUIApplication UI 测试文件(不可迁移项) | 1(Tests/LightamerUITests/,必须留 XCTest) |

**一句话结论**:单测侧无硬阻断(零 `measure`、零 UI 依赖,426 文件可机械 codemod:`XCTestCase→struct`、`XCTAssert*→#expect` 逐映射),但 3,968 法 / 15,479 断言的全量迁移是一次大工程,建议「随触随迁、不立项专项」——收益(并行执行、更快失败报告)相对现役 test-direct.sh 直启链路增量有限;UITests 1 文件按 skill 规则永久留 XCTest。

---

## 附:扫描命令与可复现性

- 软废弃扫描:六节符号归并 ~110 token,`rg -w <token> App/Sources --type swift`(+形态后滤),命中行逐条人工判(注释/自定义闭包/现代重载排除)。
- M1 交叉:对每个含 `@State (private )?var <name> =` 的文件,查 `self.<name> =` 同文件命中 → 零。
- pbxproj 实测:`grep -o "<SETTING> = <VALUE>" Lightamer.xcodeproj/project.pbxproj`(生成物,以 Project.swift 为真相源、pbxproj 为实况交叉)。
- 全程只读;本文档为本路唯一产出。**未 commit**(在飞 executor 保护)。

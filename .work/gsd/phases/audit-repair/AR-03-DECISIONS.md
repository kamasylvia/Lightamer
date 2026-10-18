# AR-03 DECISIONS — plan C(机械小件批)裁定记录

> 执行批 = plan C(AR-03),单 executor,同 worktree `/tmp/la-ar-bc-wt`
> (branch `audit-repair-bc`,串行于 AR-02 闭环后)。commits:
> `7640ed2e`(overlay/background 15)+ `8c0514a9`(杂项 8)+
> `af4581c7`(cornerRadius 14 + menuStyle 5 + onChange 1)+
> `8f78f392`(coordinateSpace fixup)+ `5d522e88`(minor 五件)。

## D-AR3-1 43 处对账表(执行时符号形态复核终值)

plan 头注行号(planner 2026-10-13 HEAD `363117ee` 实测)vs 执行时
(AR-01/AR-02 落盘后 HEAD)——**行号零漂移**(全部逐处 grep 复核
吻合,以符号形态为准的复核面全数命中):

| 族 | 清单处数 | 执行实改 | 落点与形态 |
|---|---|---|---|
| overlay 旧 View 重载 | 6 | 6 ✓ | SessionBrowserView :596 / CatalogBrowserView :336 / SoftProofControlView :101 / EDRControlView :82 / EditorNodesPanelView :612 / CurveEditorView :104 → 尾闭包形;ShapeStyle/`in:`/`alignment:` 合法重载零触 |
| background 旧 View 重载 | 9 | 9 ✓ | FilterBarView :114/:218 / SessionBrowserView :649 / CatalogFilterBarView :198 / SidebarView :417 / CatalogBrowserView :380 / EditorNodesPanelView :611 / LayersPanelView :602 / LightamerApp :552(WindowCapture)→ 尾闭包形 |
| showsIndicators | 3 | 3 ✓ | FilterBarView :189 / CatalogFilterBarView :169 / LibraryInspectorView :180 → `ScrollView(_:){}` + `.scrollIndicators(.hidden)` |
| foregroundColor | 1 | 1 ✓ | SessionBrowserView :541 → `.foregroundStyle` |
| TextField onCommit | 1 | 1 ✓ | ExportNamingEditor :182-184 → `TextField(_:text:)` + `.onSubmit(commitRename)` |
| coordinateSpace | 1 | 1 ✓(fixup) | EditorNodesPanelView :273 → 见 D-AR3-2 |
| dropDestination | 2 | 2 ✓ | SidebarView :709/:809 → DropSession 新形(见 D-AR3-3) |
| menuStyle borderlessButton | 5 | 5 ✓ | FilterBarView :323 / PresetPanelView :98 / CatalogFilterBarView :253 / SoftProofControlView :66 / EDRControlView :58 → `.menuStyle(.button)` + `.buttonStyle(.borderless)`;两 capsule 处 `.menuIndicator(.hidden)` 原位保留 |
| cornerRadius | 14 | 14 ✓ | MaskToolbarView ×11(:81/:170/:361/:378/:396/:446/:465/:483/:515/:530/:555)+ SegmentEditingOverlayHost :224 + InstancePickerOverlay :70/:92 → `clipShape(RoundedRectangle(cornerRadius:))`,圆角值逐处保持 |
| onChange 旧形 | 1 | 1 ✓ | McpLauncherPanelView :284 → 双参 `{ _, _ in }`(仓内 27 双参先例形) |
| **合计** | **43** | **43** | 五族 grep 清零机检:showsIndicators: / .foregroundColor( / .menuStyle(.borderlessButton) / .cornerRadius( / .onChange(of:.*){ _ in —— App/Sources 全域零命中 |

误报防翻车(LANEA §1.4)零误伤:自定义 onCommit 回调(EditorAreaView/
CropOverlayHost/LiquifyOverlayHost 自有面)零 diff;accentColor 属性读/
无 coordinateSpace 的 onTapGesture/SpatialTapGesture/CGColor 族零触。

## D-AR3-2 coordinateSpace fixup(编译失败回正本重对表条款行使)

plan 字面 `.coordinateSpace(Self.canvasSpace)`(读 skill「use
coordinateSpace(_:)」)不编译:`missing argument label 'name:'`。
SDK swiftinterface 对表:新形 = `coordinateSpace(_ name:
NamedCoordinateSpace)`(非任意 Hashable);落地 =
`coordinateSpace(.named(Self.canvasSpace))`——经
`CoordinateSpaceProtocol.named(_:)` factory(同 panel 两个消费面
:255/:381 已在用的 `.named(Self.canvasSpace)`),命名空间字符串
verbatim,行为等价。commit `8f78f392`。

## D-AR3-3 dropDestination 语义让渡申报(plan 风险节预定面)

旧 Bool-action 形的 `return false` = 视觉拒绝(禁止光标);新
DropSession 形 action 返回 Void,不可拒绝——guard fail(异物 payload
前缀不匹配)时落为 no-op 而非禁止光标。move 动作本身的 guard 链逐字
保留,最终行为等价(无 move);空 `isTargeted: { _ in }` 顺路消失
(本就是零效果闭包)。MANIFEST 观察行登记 category/collection 拖入
走查。

## D-AR3-4 minor 五件终形

- **m1**:row(for:) `AnyView?` → `InspectorRowView?`(:445),
  `return AnyView(view)` → `return view`(:465);喂入面 :228/:238/:269
  `if let row` 零改。
- **m4**:McpLauncherPanelModel `@Observable @MainActor final class`
  (@Published ×6 直剥——review F-4 勘误口径 ✓);:174 `@StateObject`
  → `@State`;`model.$xxx` 投影消费面 grep = 零(零适配);
  objectWillChange 隐式依赖 grep = 零(迁移语义差面清零)。
- **m5**:CropOverlayHost :80 `@State private var preset`(零外部
  初始化调用点——编译绿即零波及证明)。
- **m7**:LCR 页 :377-381 → `.task { await model.refresh() }`(loaded
  旗标 + 声明行删);ACA 页 :682-686 sync `model.load()` 留 onAppear、
  once-guard 摘除(per-identity appearance 天然承载)。
- **m8**:dateSpelling formatter 提 `private static let`
  (dateFormat "yyyy-MM-dd" + UTC verbatim——**保守口径维持**:
  ISO 定长格式是检索语法消费面,RESEARCH §9 默认不触);线程入口
  单点论据 = 该 formatter 仅 dateSpelling(_:) 消费,UI 主线程单一
  入口。

## D-AR3-5 borderlessButton 5 处截图对比(3/5 执行批亲证 + 2/5 配方让渡)

同界面(编辑器视口控件条 + Inspector 底缘)同窗口 frame
(60,60 1440×786),改前 = 基线构建(8e3bd59d,容器 eipng)、改后 =
本批构建(5d522e88,容器 dkzhl),cliclick 真实点击展开 menu + 全屏
截图 + 菜单区裁剪对比:

| # | 处 | 判定 |
|---|---|---|
| ① | SoftProofControlView softproof.control | **PASS——裁剪区逐像素一致**(capsule + menu 面板样式零差) |
| ② | EDRControlView edr.control | **PASS——逐像素一致** |
| ③ | PresetPanelView presets.apply.menu | **PASS——逐像素一致**(Tone 子菜单浮层 + label 行) |
| ④ | FilterBarView filter.add | **配方让渡**(执行批未截)——见下 |
| ⑤ | CatalogFilterBarView catalog.filter.add | **配方让渡**(执行批未截)——见下 |

④⑤ 让渡理由:两处挂 **legacy Session face**(M2LIB-06 剥离门后
`LIGHTAMER_LEGACY_LIBRARY=1` QA 通道;默认项目工作区不可见)——执行批
已走到 legacy face 启动 + Open Recent 链,但项目开入后 FilterBar 的
出现时序未在时间盒内钉稳(legacy face 的项目装载行为与默认 face 不同
域);且两处 menu = 纯图标 label(plus.circle)+ `.fixedSize` 形,
无 capsule 自绘面,style 换形的观感差风险面显著低于已证三处。
MANIFEST 配方(命令形逐点)交实机验收批;**若实机判定观感差超预期
= 按 plan 红线 DECISIONS 申报 + 该处回退评估**(软废弃卫生债可让渡,
观感回归不可)。

## D-AR3-6 挂账 3 正式登记(零代码动作,OQ-8/D-6 专项卷兑现)

1. **m10(xcstrings 复数变体)**:1957 键 0 variations 维持;zh 无复数
   形态(实害 = 英文名词屈折);复活条件 = 用户裁「缩量修」(photos/
   subjects/jobs 族 ~5-10 键 variations 尾块纯插入 + zh-audit 对账,
   plan C 追加 T 项形)。
2. **o4(翻译注释)**:en/zh 自维护,全仓零使用;复活条件 = 开放翻译
   贡献时补。
3. **o6(LutPanelView `.id(libraryRevision)` 子树身份重置)**:d6-
   relevant churn 放大器(LUT 页卡顿第一嫌疑);改动需 diff-based 重排
   设计——入 D-6 专项卷,本批零触(o6 红线条款兑现:LutPanelView 本批
   仅动 params codemod 面〔AR-02〕,`.id(libraryRevision)` 行零 diff)。

## D-AR3-7 销账 8 正式登记(各附豁免正本)

1. **o1(闭包 Binding vs KeyPath)**:D-H1 提交语义要求自定义 set 腿
   (AGENTS.md M3-1 KD-3 约定豁免)。
2. **o2(动态查表键)**:V15 豁免——显式 switch 返回静态键形态在册,
   `String.LocalizationValue("prefix_\(x)")` 禁形机检零命中。
3. **o3(面板 AnyView 注册缝)**:D12 33-panel zero-diff 契约;单挂载
   点异构注册缝非 ForEach 行(本批 m1 的 row 收紧是另一面——
   EditorAdjustmentStackView 私有 helper,非 provider 注册缝)。
4. **o5(面板模型三级读传递依赖)**:KD-3 约定本体。
5. **o7(onAppear 惰性建 @State 定式)**:仓内一致定式;本批 m7 的
   ACA 页 onAppear sync load 即该定式面(once-guard 摘除后仍是
   onAppear 定式,非 .task——async 才归 .task)。
6. **o8(Settings onAppear 重播种)**:onChange 写穿闭环合规。
7. **m2①(每 body 重计算)**:勘误降级注记——solve 已有
   FilmSolveCache 内 consult(FilmTailPolicy.swift:629,路径勘误②);
   isCustomLook/placementTarget 缓存已由 AR-01 兑现。
8. **m3 note-1/2/3(Font.system ×31 / GeometryProxy.frame ×1 /
   Stepper ×2)**:重载消歧大概率已落新臂,编译器零弃用警告——零行动
   (43 处口径不含 notes 的 34 处深读面,本批零触,grep 面核)。

**LANEA side-note 销账两行(review F-5)**:
- LANEA §2 M3 note(@State private memberwise init 合成依赖):零行动
  销账——编译器诊断面,大概率零缺陷;「留 B 路」交接由本批(B/C 连跑
  单 executor)承接并显式销账,不留断链。
- LANEA §4 modernize-tests 快评(3,968 法 XCTest):裁决留痕——不立项
  专项,随触随迁(零代码决定留痕)。

## D-AR3-8 清单外残余注记(软废弃卫生债,未清完面)

执行时全仓符号形态扫描发现 plan 43 清单**之外**仍有旧 View 实参形
overlay/background 残余(~40 处:WorkspaceHostView :497/:685/:1633 域、
FilmstripView :311/:317、EditorNodesPanelView :292/:436/:536、
LibraryGridView :321/:379/:385、RelinkSheetView :88、GlobalSearchDialog
:54、EnhanceDialog :237、EmptyStateView :52/:56、HlsPanelView :162、
MaskGroupsPanelView :391、VersionsPanelView :266、BackgroundTaskBarView
:83、EditorToolRailView :87/:242、EditorWorkspaceShellView :62/:82、
LibraryInspectorView :63、McpLauncherPanelView :280、SegmentEditingOverlayHost
:186、RetouchPanelView :218、LayersPanelView :93/:230/:373/:609、
MaskToolbarView :77/:357/:442、SidebarView 等——含若干
`.overlay(X, alignment:)` 双参形与 `.background(Group{})` 条件形)。
按 plan 清单纪律**不扩面**(43 = findings 冻结口径;全仓清除属 scope
扩张,须立项)。登记为后续软废弃卫生批的现成清单;其中
McpLauncherPanelView :280 与本批文件重叠但不同行,同样未动(禁顺手改)。

## D-AR3-9 ΔN 记账

- 本批 ΔN(pass)= **+0**(零新测试;plan 带 +0..1 的 +0 臂);
  Project.swift 零 diff 红线兑现(m1/m4 顺路单测让渡——m1 类型收紧由
  编译期静态保证,m4 迁移由 grep 机检 + 定向轮 McpLauncherTests 既有
  面回归覆盖)。
- 全批终值对账:基线 3963 → AR-01 +4 = 3967 → AR-02 +0 = 3967 →
  AR-03 +0 = **3967**(全批终值带 3964..3972 内,三 plan 实现下界;
  skip 口径 = 基线 35 + AR-02 探针族 +2 = 37,逐族差分已在 AR-02
  DECISIONS 申报)。

## D-AR3-10 m9 readout 复核行(AR-01 面的 C 走查复核)

m9(Film 面板 latitude share/readout 布局)属 AR-01 交付面;C 批复核
= Manual-Only 归实机验收批(MANIFEST 观察行):Film 面板 share 读出
zh 格式键渲染 + placement readout 并排 Text 布局目测——本批零触 Film
面板文件(FilmPanelView 零 diff 机检在案),复核 = AR-01 拆节后形态
的走查确认,不涉本批改动归因。

## D-AR3-11 C 路并入条款核对(开工前复核,同 AR-01 D-AR1-1)

C 路合并 MANIFEST 仍未落盘(`find .work -iname "*manifest*"` + 
LANEC/lane-c/automation 键 grep 零命中)——静态基线形态执行,条款
保持活线;C 路 findings 落盘时的分诊义务(§9 同款)转后续批。

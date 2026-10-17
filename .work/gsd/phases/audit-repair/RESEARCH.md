# 审计修复批 RESEARCH — Xcode 27 skills 对照审计 A/B 路 findings 修复测绘

- **日期**:2026-10-13
- **范围基线**:`.work/audits/xcode27-skills-2026-10/LANEA-FINDINGS.md`（31 finding + 9 note，commit `388e3875`）+ `LANEB-FINDINGS.md`（PASS / 0 error + 5 major + 11 minor + 9 obs，同 commit）。**C 路并入条款见 §11**。
- **全套基线**:`3963/35/0`（M7-6 收口终态，skip 35 = 基线 24 + 供件漂移 11）。
- **本文性质**:只读侦察；唯一产出 = 本文件；零源码触碰。
- **深度证据来源**:本文所有 file:line 均为本次侦察实读核实（非转抄 A/B 路），与 A/B 原文不符处显式标注「勘误」。

## §0 结论摘要

1. **B 路 5 条 major 全部核实成立、全部可修**。四条大件（M1/M4/M5/M2）拆分/缓存方案已定（§2..§5），行为保持验证三层（既有测试面 + D-6 探针硬门 + GUI 走查，§7）；M3 Filmstrip id 记账方案已定（§6）。**m2① 勘误**:FilmPanelModel.solveReadout 的 FilmRuntimeSolve.solve **内部已 consult FilmSolveCache**（FilmTailPolicy.swift:629 `FilmSolveCache.shared.autoSolution(for: key)`），B 路「每次拖动 tick 全量解算」高估——每 tick 实付 = 缓存键计算 + 字典查 + 两次 `store.profile(id:)` 读，m2① 降级为顺路注记。
2. **A 路 28 处软废弃**：逐处抽查 6 代表命中全数坐实；15 处 overlay/background + 3 showsIndicators + 1 foregroundColor + 1 TextField onCommit + 1 coordinateSpace + 2 dropDestination = 机械零观感差；**5 处 menuStyle borderlessButton 需截图对比**（`.menuStyle(.button)` + `.buttonStyle(.borderless)` 观感近似非逐字节）。连同 B 路 m3（cornerRadius ×14 + onChange 旧形 ×1）合计 **43 处机械批**。
3. **构建设置 = 本批唯一用户裁决点（OQ-M7-AR-1）**。关键新事实：`ENABLE_ENHANCED_SECURITY = YES` **级联强制 pointer authentication（= arm64e slice 全链）**（enhanced-security.md :37「Cascades automatically to pointer authentication…」）——A 路「编译侧可先行单开」的口径不成立，F1 与 F3 是一个包：app + 2 appex + SPM（libwebp C 源码）+ 测试宿主全部 arm64e 化 + `macOSPackagesShouldBuildARM64e` workspace 旗标配套。结合 unsigned 分发终裁（13-4），runtime enforcement 面全灭，**推荐本批不采纳、挂账**（§8 分析 + 复活条件）。
4. **B 路 11 minor + 9 obs 分诊完毕**（§9）：本批修 9 项（m1/m3/m4/m5/m7/m8/m9 + m2 剩余 + M3 顺路 m6）、挂账 3 项（m10 xcstrings 复数 / o4 翻译注释 / o6 LutPanelView——o6 入 D-6 专项卷）、销账/豁免 8 项（o1/o2/o3/o5/o7/o8 + m2① 勘误降级 + m3 Stepper 零行动）。
5. **plan 切分推荐三 plan 串行**（§10）:plan A = d6 面大重构（M1/M4/M5 + 顺路，~6 文件，行为保持验证重）/ plan B = M2 39 面板 codemod（机械但面大，独立验收）/ plan C = 机械小件批（软废弃 43 + minor 族）。A/B 文件零交集可并行；C 最后（含观感改动走查一次定稿）。ΔN 预估:A +1..7 / B +0..1 / C +0..1（§10；review F-1 勘误——本节原文「A +0..4」与 §10「+0..6」互斥，且均漏 T4 fixup 新回归 +1..3 的下界强制 ≥1）。

---

## §1 D-6 交互禁区（红线节，M1/M4/M5 拆分的硬约束）

**正本链**:`.work/gsd/phases/v2-maintenance/V2M-VALIDATION.md`（D-6 登记）→ `phases/fix2-defects/FIX2-VALIDATION.md`（T1 探针定罪 + 三选一裁定①）→ `phases/fix2-defects/FIX2-01-PLAN.md` front-matter `red_lines` 八条 → M7-1/M7-3/4/5 各波「FIX2③ 维持」注记（LibraryProjectController 零 diff 连续四波）。

D-6 定性（FIX2 T1 五读数，双路追认）：macOS 27 SwiftUI **菜单/焦点更新机制在特定树形〔重树 + `.inspector` 分栏宿主 + 三段内容〕下不收敛**——自持环 `flushTransactions→graphDidChange→appGraphDidChange→makeMainMenu→updateMainMenu→invalidateProperties→requestUpdate→updatePreferences`；编辑器面 ~60k 次重估全部 `@self`（零属性变更）；**持续条件 = threshold 形**（空载摘 `.inspector`/双 safeAreaInset 任一饿死；编辑器三段内容任摘一段饿死；**摘焦点写点/List→LazyVStack/动画不饿死**）；churn 具可见性门控 + legacy 开菜单态点火。

**本批拆分组（M1/M4/M5）必须遵守**：

1. **menus/focus 形态零触碰**:`.focusedSceneValue` 挂点（WorkspaceHostView.swift:183、ContentView.swift:287-288、:228 exportPanelRequest）、LightamerApp Commands 求值面、`legacyBody` 的 toolbar/alert 链——**不得移动、摘除或改变求值路径**。菜单环燃料面（visibleMenuCommands/ratingMenuLabel/metadataTextEntryActive）不在本批任何修法触面内。
2. **threshold 承载面不得结构性增删**:双 safeAreaInset（WorkspaceHostView.swift:166-169 top banner / :179-182 bottom toast）的**挂载方式**（`safeAreaInset(edge:)` 修饰符族）保持原形——M1 的改造是「值传递改模型自读」的**内容面**替换，不是挂载点摘除；`.inspector` 分栏（ContentView.swift:205-223）形态不动；编辑器三段内容段数不变。M5 面板拆分不触碰 scopes 面（M7-5 disable-not-unmount 三纪律无交涉面）。
3. **每次树形改动 = D-6 探针复测义务**:树规模降低是 churn 燃料面减量（良性方向），但树形变化可能意外跨越 threshold——M1/M4/M5 各自验收必须复测 FIX2 T1 硬门：**重开项目进编辑器静置 CPU<10%（ps/sample 机检）+ 空载无项目面同口径记录**（FIX2-01-PLAN T1 SC 原文复用）；walkthrough 配方 = `gui-acceptance/v2m/` D-6 复现链（6 图项目重开）。
4. **legacy 面（gate=true）惰性**:FIX2 实测 legacy 树 idle 0.1%（反证隔离）——legacyBody 无 churn 问题，叠加 M2LIB-06 byte-frozen QA 通道纪律，**M4 拆分不进 legacyBody**（§3 论证）。
5. **AX 自动化轻用**:AX 深遍历是 L057-B 主线程栈边界故障的共同因子——走查以行为判 + 定点 AX 断言（ToastFaceTests 既有 AX wiring 断言形态），避免全树深遍历放大。
6. **o6 LutPanelView `.id(libraryRevision)` 子树身份重置**（LANEB :114，d6-relevant obs）:identity 重置是 churn 放大器但改动 = diff-based 重排的语义设计，**本批不动、挂 D-6 专项卷**（LUT 页卡顿第一嫌疑登记在案）。

---

## §2 M1 — WorkspaceHostView 宿主 body 失效放大（勘测 + 方案）

**现状事实**（`App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift`，1684 行，body :130-429）:

- body 作用域的**非渲染读**（任一变化重估全宿主 = topBar + phase switch + libraryFace/EditorWorkspaceShellView + 8 个 sheet 闭包 + 全部 modifier 尾）:
  - `editorState.toast` ×2（:180 传值 + :181 `.animation(value:)`）——toast 每次推入/清除全宿主重估；
  - `projectController?.isReadOnly` ×3（:168 banner、:638/:653 topBar disabled）+ `readOnlyHolderPid`（:169）；
  - `.onChange(of: workspace.pendingAIEnhance)`（:266-271）、`.onChange(of: workspace.pendingStackCommand)`（:276-284）、`.onChange(of: projectController?.importProgress)`（:322-345）、`.onChange(of: projectController?.projectURL)`（:346-348）——四个副作用观察全部落宿主 body 作用域；
  - `projectController?.projectURL`（:672-676 `projectName`）、`agentControl.holdsControl`（:639/:654）、`workspace.phase`（:134/:610/:625）、`workspace.isSearchDialogPresented`/`aiEntry.enhancePresented`/`ratingConfirmPresented`/`labelingPrompts.pendingPrompt`（sheet binding get 闭包,body 求值期读取）。
- 子视图签名:`ProjectReadOnlyBannerView(isReadOnly:holderPid:)`（:1461-1464 值传递）、`ToastBarView(toast:)`（:1505-1508 值传递，`ToastFaceTests` 钉两面契约）。
- C 类副作用:`rebuildLibrarySurface()` 在宿主 `.onAppear` 直呼（:349-351，表面重建编排属模型层职责）。
- 旁证:`:335-343` 注记该 body 曾触发 Release `-O` 类型检查超时（M2-11-02）——body 复杂度已在预算边界。

**修法**（dataflow.md §Isolating onChange side-effect invalidation :515-660 `EditorChangesModifier` 定式 + structure.md §separate View types）:

- **T-M1a** 四个 onChange 各抽 ViewModifier（`PendingAIEnhanceModifier` / `StackCommandModifier` / `ImportProgressModifier` / `ProjectURLChangeModifier`），依赖读收进 modifier——值变化只重估轻量 modifier。`ImportProgressModifier` 需携带 `gridModel`/`inspectorModel` 弱引用或闭包（宿主 @State 经 init 参数/闭包传入，行为保持:consumer 逻辑逐行平移）。
- **T-M1b** 两个叶挂载:`ToastBarMount`（自读 `@Environment(EditorState.self)` 的 toast，转发既有 `ToastBarView(toast:)`）+ `ReadOnlyBannerMount`（自读 controller 面，转发既有 `ProjectReadOnlyBannerView`）——**既有值传递 init 零改动**（ToastFaceTests 零 diff），observation 依赖建在叶上。safeAreaInset 挂载形不变（§1.2 禁区）。
- **T-M1c** `topBar` 抽子 View struct（`WorkspaceTopBar`，窄输入:phase/projectName/isReadOnly/holdsControl + 回调）——isReadOnly/holdsControl 变化只重估 topBar。
- **T-M1d**（顺路，C 类）`rebuildLibrarySurface()` 从 `.onAppear` 移入既有 `.task` 链（:355-423 已有宿主级 task，合并或并列新 task；语义近似 = appear 后异步执行一次，时序差异走查覆盖）。
- **深度裁量（OQ-M7-AR-2）**:推荐最小隔离子集（上述四件），**不做** libraryFace/8-sheet 闭包大重排——sheet binding 读是呈现耦合（dataflow.md「Do NOT apply when the dependency is also used in rendering output」），且 sheet 面树形稳定是 D-6 禁区优先项。

**行为保持验证**:①既有面 = ToastFaceTests（含 AX wiring 断言）+ WorkspaceRoutingTests + ProjectReadOnlyFaceTests + EditorStackRoutingTests + App bundle 定向轮；②D-6 探针硬门（§1.3）+ D-6 复现链走查；③GUI 走查 = toast 推入/清除、只读横幅、import 进度条、项目切换四信号逐项目测。**ΔN +0..2**（modifier 消费逻辑平移可抽纯函数负测，合法 ΔN=0）。

## §3 M4 — ContentView 根 body 同族（勘测 + 方案）

**现状事实**（`App/Sources/Lightamer/UI/ContentView.swift`，769 行）:

- **gate-false 生产臂**（:175-241）:WorkspaceHostView 装配 + `.inspector(isPresented:)` binding（:205-219，get 读 `inspectorState.exportPageActive || filmPageActive`——呈现耦合，合法渲染读）+ `.focusedSceneValue(\.exportPanelRequest)`（:228-233，读 exportPageActive）+ `.onChange(of: projectController?.projectURL)`（:238-240，**纯副作用读** → exportState.rebuildQueueForProject）。
- **legacyBody**（:248-418，byte-frozen QA 通道）:StatusBar 值读（:283-285）+ 5 onChange（:326/:340/:351/:359/:362）+ 2 alert + 2 sheet + fileImporter——idle churn 0.1%（FIX2 实测）+ M2LIB-06 gate 纪律。
- 放大链:LightamerApp.swift:508-524 每 Scene body 求值重建 ContentView 实参闭包（onImportFolder 等）→ ContentView 值 diff 失败即重估根 body → WorkspaceHostView 实参闭包随之重建（链路末端即 §2 宿主）。

**修法（OQ-M7-AR-3）**:推荐**只动 gate-false 臂**——`.onChange(of: projectController?.projectURL)` 抽 modifier（`ExportQueueRebuildModifier`）；可选加深 = `InspectorPageMount` 子 View struct（inspector 挂载 + focusedSceneValue + onChange 整段下沉，exportPageActive 变化不再重估根）——推荐行使（呈现耦合读下沉后根 body 只剩常量读）。**legacyBody 零触碰**:byte-frozen 纪律 + idle 0.1% 无收益 + QA 通道行为回归风险不对称；LANEB「legacyBody 稳定段拆子 View」建议在此行使为不采纳（房内约定优先，§1.4）。

**行为保持验证**:①WorkspaceRoutingTests / LibraryLegacyGateTests（gate 投影面）+ App bundle 定向轮；②D-6 探针硬门 + 空载口径；③GUI 走查 = File▸Export 菜单命令 → Export 页打开/关闭、film 页双关 dismiss、项目切换队列重建。**ΔN 0**。

## §4 M5 — Film/Drt 面板单失效边界（勘测 + 方案）

**现状事实**:

- `FilmPanelView.swift`（594 行）:单 View struct；body :23-57 + 全节 `private var` 计算属性（header :61 / enableEntry :84 / sessionControls :109 / latitudeSection / placementSection + row/shiftRow helper）——computed property 不设独立失效边界（structure.md §1 直引），**任一模型属性 tick 重估整面板**（含 Canvas 直方图 + picker 全量 + readout 重算）。60Hz live tick（Y/M 强度滑杆）是重灾路径。
- `DrtPanelView.swift`（313 行）:body :32-48 = ForEach(model.sections) + switch 分派到 methodCard（:52）/ encodingGroup（:76，含 peakRow :124 D-H1 三件）/ limitingGroup / presetGroup 四个 `private var`——同型单边界。
- **m11**（同文件顺路）:DrtPanelView init :23-30 `State(initialValue: DrtPanelModel(...))`——祖先 body 每次求值分配一个即刻丢弃的 model；仓内既有定式 = FilmPanelView:49-50 onAppear 惰性建（o7）。
- **m2 剩余项**（同域顺路）:①solveReadout（FilmPanelModel.swift:117-130）——**勘误**:FilmRuntimeSolve.solve 内部已 consult FilmSolveCache（FilmTailPolicy.swift:628-648），每 tick 非全量解算，剩 `store.profile(id:)` ×2 + 键计算，降级为注记级；②isCustomLook（DrtPanelModel.swift:90-92）53 参数对每 body 比对；③placementTarget（FilmPanelModel.swift:330-345）每 body 扫层链。

**修法（OQ-M7-AR-4）**:节级子 View struct——Film 拆 `SessionControlsView` / `LatitudeSectionView` / `PlacementSectionView`（各持 `let model: FilmPanelModel` 类引用 + 各自窄读）；Drt 拆四节 struct（`DrtMethodCard` / `DrtEncodingGroup` / `DrtLimitingGroup` / `DrtPresetGroup`；`encodingExpanded` @State 随 encodingGroup 子 View 迁移）。同批:m11 改 onAppear 惰性建（FilmPanelView 定式，body 包 `if let model`）；m2②③ 顺路下沉 model 缓存（isCustomLook 按 recordHash 键 stored 缓存 / placementTarget 写点刷新）。**不动**:KD-3 三级读形态（o5 豁免）、D-H1 闭包绑定（o1 豁免——KeyPath 规则不适用）、scopes 面（无交涉）、o3 AnyView 注册缝（D12 33-panel 契约）。条件分支形态保持（`if model.isPristine` 原样）——disable-not-unmount 精神 = 不新增条件卸载。

**行为保持验证**:①FilmstripModelTests 不涉；面板模型测试（若 DrtPanelModel/FilmPanelModel 有单测面——plan 时核对）+ App bundle 定向轮；②D-6 探针硬门；③GUI 走查 = Film/Drt 面板逐滑杆拖动 60Hz 目测 + readout 刷新 + undo/redo 跳转 + 版本切换面板同步。**ΔN +0..2**（m2 缓存可 +1..2 纯函数测试）。

## §5 M2 — 39 面板每 tick params JSON 重解码（勘测 + 方案 + 性能门）

**现状事实**:

- 热路径底座:`ModuleInstance.params(of:)`（`LightamerCore/Sources/Pipe/History/ModuleInstance.swift:146-152`）**每次调用 `JSONDecoder().decode` 全新解码**（+ decoder 分配）。Core 面零改（本修纯 App 层消费形态）。
- 消费形态两式:①直接式 `(try? instance.params(of: X.self)) ?? .init()` computed property（ChannelMixerRGBPanelView.swift:26-28 等）；②helper 式 `PanelEditing.params(of: instance, as:)`（IOPPanelProvider.swift:194-198）。grep 实证 `UI/Inspector/` 48 文件含 `params(of:`。
- **关键语义事实（零风险论据）**:`instance` 是面板 View 的 `let` 值捕获（ChannelMixerRGBPanelView.swift:23）——computed `params` 与 Binding get/set 闭包内读（discreteBinding :322-331 等）**每次解码的是同一份字节**。提升为 stored = 纯语义等价，无 stale 风险（记录变更恒经 `edit.update` → 父链重估 → 面板以新 instance 重建）。
- ChannelMixerRGB 单次 body 求值解码计数实测:body 直读 `params.*` ~20 处 + 4 个 discreteBinding 闭包各 1 读（求值期触发）≈ **每 tick 24+ 次 base64+JSON 解码**；B 路估 15+ 偏保守。

**修法（OQ-M7-AR-5）**:推荐 **stored-`params` 形态**——每面板加 custom init（或保留 memberwise + init 内一次解码存 `let params`），删 computed property；helper 方法签名不变（值传参已解耦）；binding 闭包捕获 stored 值。备选 body-top `let params = self.params`（更薄但 helper 闭包再读需逐处过——48 文件不推荐）；@State 缓存（per-tick paramsHash 必 miss，无益，弃）。39 文件 × ~10-30 行机械改，单 commit。

**性能门（评估结论）**:本修**不需要 PERF 硬门**——N→1 是机械可证构造（init 一次 vs body N 读），无用户可见预算面（60fps 预算在 viewport 不在面板解码）；按 M2-5 PERF 惯例补 **+1 env 门探针**（`LIGHTAMER_PERF_PROBE=1` + XCTSkipUnless，App bundle，测代表性 Params 解码 µs 基线留档）作为文档面，非门。验收门 = 编译 + App bundle 定向轮 + 1-2 面板拖动走查。**ΔN +0..1**。

## §6 M3 — Filmstrip Int 索引记账（勘测 + 方案）

**现状事实**（`App/Sources/Lightamer/UI/Shell/FilmstripView.swift`，295 行）:

- `FilmstripModel.visibleIndices: Set<Int>`（:45）按**位置**记账；行出现/消失经 `grid.rows.firstIndex(where:)` O(n) 反查（View 侧 :194-203——**洞在 View 侧手里已有 `row.id` 仍反查索引**）；`warmWindow`（:66-74）取 min/max index ± prefetchSpan；`refreshWindow()`（:119-136）按 index 取 row.id 发请求。
- 病害一（正确性）:expanded 堆叠 fixup 中途插行（`LibraryGridModel.stackAdjacencyFixup` anchor+1 insert）→ 可见行索引整体移位；SwiftUI List 行 identity 是 `row.id`（cell 不卸载、不触发 onDisappear）→ `visibleIndices` 同持 stale+新索引 → warm 窗慢性虚胖 + 多发 `prioritize`（`requestedIDs` 融合保证浪费有界但膨胀真实）。
- 病害二（成本）:每行事件 O(n) firstIndex（10k 行虚拟化目标下滚动摩擦）。
- 回归面:`Tests/LightamerTests/FilmstripModelTests.swift`（KD-5 机检面）——现有方法全 index API（:89/:96/:141-142/:179-197）。

**修法（OQ-M7-AR-7）**:记账换 `visibleIDs: Set<Int64>`；View 侧直传 `row.id`（**firstIndex 反查整体消灭**——病害二零成本顺手修）；`warmWindow` 解析 = model 在 refreshWindow 时以 `idToIndex: [Int64: Int]` 字典（**每次 refresh O(n) 重建**——正确性优先，10k 行 ~µs 级，指纹缓存挂后续优化；fixup 中插/删/重排全形态下指纹易错，重建式无正确性洞）。`scrollAnchorID`/`select`/`listDisappeared` API 形态不变；LibraryGridView.swift:166-170 cell onAppear 反查（m6 合并修）改 `ForEach(grid.rows.enumerated(), id: \.element.id)` 携带 index——**pager.cellAppeared(at:) API 不动**（分页按 index 是设计内）。

**行为保持验证**:FilmstripModelTests 改写为 id API（量不变）+ **新增 fixup 中插 stale-window 回归**（可见 id 集在插行后仍产正确 warm 窗 + 无 stale id 残留）**+1..3 法**；GUI 走查 = 展开堆叠 → filmstrip 滚动 → 请求计数断言（既有 requestCount 机检面）不虚胖。**ΔN +1..3**。

---

## §7 行为保持验收形态（大重构通用三层，OQ-M7-AR-6）

1. **既有测试面（回归底线）**:App bundle 定向轮（`Scripts/test-direct.sh --bundle App`，M7-6 口径 917 法）——ToastFaceTests / WorkspaceRoutingTests / ProjectReadOnlyFaceTests / EditorStackRoutingTests / LibraryLegacyGateTests / FilmstripModelTests / LibraryGridModelTests 全在 App bundle。每 plan 终了跑一次；全套 `--all` 不强制（改动全 App 域，orchestrator 批准制）。
2. **D-6 探针硬门（树形改动专用，§1.3）**:重开项目进编辑器静置 CPU<10%（ps/sample 机检）+ 空载面同口径记录 + D-6 复现链（6 图项目重开 + 编辑器交互铁条:filmstrip 点击换图出图）。plan A 内 M1/M4/M5 合并复测一次（同一批树形改动，一次探针轮覆盖三件）+ plan B 面板批后复测一次。
3. **GUI 走查（行为目测）**:plan A = toast/banner/import 进度/项目切换 + 面板拖动 60Hz + Export 页开闭；plan C = borderlessButton 5 处截图对比（唯一非逐字节等价面）+ m9 readout 布局。**AX 树快照对比 = 可选增强不设门**（AX 深遍历是 L057-B 压力因子，§1.5 轻用纪律）。
4. **后台验证通道**:夜间批可用（先例 D-07-3-T5-1）；C 档门控 = plan A 闭环后停（汇报战果等确认）。

## §8 构建设置裁决（唯一用户裁决点，OQ-M7-AR-1）

**现状实测**（Project.swift + 生成 pbxproj + entitlements）:

| 项 | 现状 | 实据 |
|---|---|---|
| `ENABLE_ENHANCED_SECURITY` | 缺席（pbxproj 0 命中，默认 NO） | A 路 F1 |
| hardened-process entitlements 族 | app target **无 .entitlements 文件**；2 appex entitlements = 仅注释空 dict | A 路 F2；App/Extensions/QuickLook/LightamerQuickLook.entitlements |
| `ENABLE_POINTER_AUTHENTICATION` + `macOSPackagesShouldBuildARM64e` | 双缺 | A 路 F3 |
| `ENABLE_HARDENED_RUNTIME` | Release YES / Debug NO（有档 deliberate） | Project.swift:56-70 |
| MTE / CPA2 / C 族警告与 analyzer | 未配 / N/A（纯 Swift + M2 硬件门不达 + macOS 无 CPA2 enforcement 硬件） | A 路 F4/F5/W1/W2/A1 |

**关键级联事实（勘误 A 路口径）**:enhanced-security.md :37 明文——`ENABLE_ENHANCED_SECURITY = YES` **自动级联 pointer authentication**（= arm64e slice 追加）+ stack zero-init + 安全警告族 + typed allocators。A 路 F1 相容性列「编译侧（ENABLE_ENHANCED_SECURITY 本体 + 级联警告）仍有效，可先只开编译侧」的口径**不成立**——F1 采纳即 F3 生效，arm64e 化波及 app + 2 appex + SPM 包（libwebp C 源码需配 `macOSPackagesShouldBuildARM64e` workspace 旗标）+ 测试宿主/测试 bundle，验证面 = 全量重建 + 全套轮 + 测试基建（test-direct.sh 直启链）复验 + perf 抽查（PAC 开销 1-3% 量级）。

**结合 unsigned 分发终裁（13-4:砍签名公证，unsigned DMG/zip）**:

- **runtime enforcement 面（F2 entitlements 族）= 全灭**:restricted entitlements 需 Apple 签名链（notarization/provisioning）方被内核 honoring；unsigned 分发下落了等于没落。**无论 1/3 都不落**。
- **编译侧面（F1 级联本体）= 有效但不免费**:stack zero-init/typed allocators/警告族真生效（纯代码生成，与分发形态无关），收益面 = 内存安全缺陷类的编译期防御；代价 = 上述 arm64e 全链验证面 + libwebp arm64e 构建风险 + Debug-dylib/签名陷阱邻域回归排查（Project.swift:56-63 历史教训）。

**推荐**:**本批不采纳，三项全挂账**。理由:①unsigned 终裁下大头（runtime enforcement）为零收益；②编译侧收益需以测试基建全面重验证换取，ROI/风险比不成立；③本批定位 = SwiftUI 审计修复（App 域），构建设置采纳横跨构建/测试/依赖三域，耦合进本批破坏验收口径纯净性。**复活条件**:分发形态回签名（Developer ID/公证回归）或内存安全专项立项时，F1+F3 捆绑单独立项（含 F2 重评）。晨审点呈用户；若用户裁「采纳」→ 追加 plan D（构建设置验证批:开关 → 全量重建 → 全套轮 --all（批准制）+ perf 抽查 + D-6 探针复测 + 回滚预案 = 单行 revert）。

## §9 B 路 11 minor + 9 obs 分诊

### minor（11）

| # | 判 | 落点 |
|---|---|---|
| m1 EditorAdjustmentStackView AnyView 行（:420-441/:440/:202/:212） | **本批修（plan C）** | 返回具体 `InspectorRowView?`——该行本就是具体类型，签名收紧机械；foreach.md §AnyView row 直引 |
| m2 每 body 重计算非解码族 | **部分修（plan A M5 顺路）** + **m2① 勘误降级注记**（§4，solve 已有 FilmSolveCache 内 consult）；isCustomLook/placementTarget 顺路缓存 |
| m3 软弃用 17 处（cornerRadius ×14 / foregroundColor ×1 / TextField onCommit ×1 / onChange 旧形 ×1） | **本批修（plan C，与 A 路 28 合并 43 处批）**；note-1/note-2/note-3（Font.system 31 / GeometryProxy.frame 1 / Stepper 2）= 零行动销账（重载消歧大概率已落新臂，编译器无弃用警告） |
| m4 McpLauncherPanelModel ObservableObject 残留（:31 + :174 @StateObject） | **本批修（plan C）** | 迁 `@Observable` + `@State`（仓内 30+ 模型既定形，最后一处）；`@Published` 6 处直剥（review F-4 勘误——LANEB m4 原文 7 处差 1） |
| m5 CropOverlayHost 非私有 @State（:80） | **本批修（plan C）** | 加 `private`（无外部初始化需求，零波及） |
| m6 行出现/消失 O(n) firstIndex ×2 处 | **本批修（plan A M3 顺路）** | §6（LibraryGridView enumerated + Filmstrip id 化双修） |
| m7 SettingsPages:377-381 onAppear+Task 手工复刻 .task | **本批修（plan C）** | `.task { await model.refresh() }` 删 loaded 旗标；:682-686 同型 once-guard 冗余顺路清（B 类）；o8 三处重播种 = 合规销账 |
| m8 LibraryInspectorView:500-505 DateFormatter 每渲染新建 | **本批修（plan C）** | `static let` 缓存（线程入口单一）；`setLocalizedDateFormatFromTemplate` 不动（ISO 定长若属检索语法契约则维持——plan 时核对消费方后定，默认保守只去分配项） |
| m9 FilmPanelView 本地化片段拼接（:339 + :498-509） | **本批修（plan A 顺路——与 M5 同文件同走查）** | :339 改单 `String(localized:)` 格式键（V14 静态键纪律，xcstrings 尾块纯插入 +2..3 键）；:498-509 改并排独立 `Text`（布局替代拼接） |
| m10 xcstrings 零复数变体（1957 键 0 variations，实核坐实；% 格式键 en 侧 ~102 处粗计） | **挂账（OQ-M7-AR-8）** | 0 用户可见缺陷（zh 无复数形态，实害 = 英文名词屈折）；全量加 variations = 大回归面低收益；缩量方案（photos/subjects/jobs 族 ~5-10 键）备选——呈用户裁，默认挂账 |
| m11 DrtPanelView init State(initialValue:) | **本批修（plan A M5 顺路）** | §4（onAppear 惰性建定式） |

### obs（9）

| # | 判 |
|---|---|
| o1 闭包 Binding vs KeyPath 规则 | **销账（约定豁免）**:D-H1 提交语义要求自定义 set 腿（AGENTS.md M3-1 KD-3）——skill 规则让位房内约定，LANEB 判定维持 |
| o2 动态查表键家族 | **销账（V15 豁免 + 手工在册实证）**:显式 switch 返回静态键形态在册 |
| o3 面板协议 AnyView 返回面 | **销账（设计维持）**:单挂载点异构注册缝非 ForEach 行；D12 33-panel zero-diff 契约 |
| o4 翻译注释全仓零使用 | **挂账**:en/zh 自维护信息损失有限；开放翻译贡献时补 |
| o5 面板模型三级读传递依赖 | **销账（KD-3 约定本体）** |
| o6 LutPanelView `.id(libraryRevision)` 身份重置 | **挂账（D-6 专项卷）**:§1.6——d6-relevant，churn 放大器，改动需 diff-based 重排设计 |
| o7 onAppear 惰性建 @State 定式 | **销账（仓内一致定式）**:m11 顺势对齐 |
| o8 Settings 页 onAppear 重播种 | **销账（合规）**:onChange 写穿闭环无脏状态风险 |
| o9 EditorAdjustmentStackView 每 body 轻量派生 | **本批顺路（plan A M5 邻域）**:量级豁免但顺路下沉模型零风险；不入独立验收 |

## §10 plan 切分推荐 + ΔN 预估带

**推荐三 plan 串行（A→B→C），A/B 文件零交集可并行**:

- **plan A — d6 面大重构（行为保持验证重）**:M1（§2 四件）+ M4（§3）+ M5（§4 含 m2②③/m11/o9/m9 顺路）+ M3（§6 含 m6）。文件 ~8（WorkspaceHostView / ContentView / FilmPanelView / FilmPanelModel / DrtPanelView / DrtPanelModel / EditorAdjustmentStackView / FilmstripView / FilmstripModelTests / LibraryGridView）。ΔN **+1..7**（review F-1 勘误——原写 +0..6 漏 T4 fixup 新回归 +1..3 的下界强制 ≥1；M3 测试 +1..3 / m2 缓存 +0..2 / M1 +0..2 / 其余 0）→ 终值带 3964..3970。验收 = §7 三层全开（D-6 探针硬门在此 plan）。C 档停:闭环后汇报等确认。
- **plan B — M2 39 面板 codemod（机械但面大，独立验收）**:§5 stored-params 批 + env 门探针 +1（可选）。文件 ~40（UI/Inspector/ 全域 + PanelEditing 不动）。ΔN **+0..1** → 终值带 +0..1。验收 = 编译 + App bundle 轮 + 1-2 面板拖动走查 + D-6 探针复测一次（面板树形亦变）。与 A 并行合法性:UI/Inspector/* 与 plan A 文件零交集（唯一共享依赖 = LightamerSlider 只读）；并行时 D-6 探针轮合并到两 plan 都落盘后一次跑亦可。
- **plan C — 机械小件批**:软废弃 43 处（A 路 28 + cornerRadius 14 + onChange 旧形 1，§4/§9 清单逐处复核）+ m1/m4/m5/m7/m8。文件 ~30。ΔN **+0..1**。验收 = 编译 + App bundle 轮 + borderlessButton 5 处截图对比。**C 最后**:含观感改动（menuStyle/m9 邻域），走查一次定稿；plan A 的面板走查截图不受其扰动。
- **构设置（若用户裁采纳）= plan D 独立验证批**（§8，含回滚预案）；默认挂账零 plan。

**串行理由**:A 的 D-6 探针门要求净基线（C 的观感改动会污染树形归因）；B/C 机械批任何时刻可插队。**单 plan 分任务序**备选可接受（总 Δfiles ~78 但逐任务独立 commit 满足每任务独立验收），推荐仍三 plan——A 的 C 档停与 B/C 的无停形成自然的用户裁决节奏。

## §11 C 路并入条款（规划期义务）

C 路 omp 全量深读（automation `automation-af8b6363`，周一 00:00）产出三路合并 MANIFEST 后，**plan 期必须**:①重读合并 MANIFEST，C 路新 findings 逐条按本文 §9 同款分诊（本批修/挂账/销账）并入对应 plan 或追加 plan；②基线数字以 MANIFEST 落盘时点全套终态为准重算 ΔN 对账带；③C 路若推翻 A/B 误报（如软废弃命中存疑项），以 C 路为准修正清单；④本文 §8 构建设置裁决不受 C 路影响（裁决点已呈用户）。研究结论中「C 路未读」的显式边界:本文全部方案基于 A/B 路 + 源码亲读，C 路只增不减范围。

## §12 房内纪律合规核对（本批全部修法的约束面）

- **KD-4 注入式 defaults**:零 UserDefaults 新键（m9 格式键走 xcstrings 非 defaults）；面板批零 defaults 面。
- **V14/V15 动态键纪律**:m9 新键 = `String(localized:)` 静态字面量键 + xcstrings 尾块纯插入；零 `String.LocalizationValue("prefix_\(x)")` 禁形。
- **D-H1 提交语义**:M5 拆分绑定逐行平移（live tick→setLive、dragEnd→commit 零改）；m2 缓存不触 commit 点。
- **disable-not-unmount 三纪律（M7-5）**:M5 拆分不涉 scopes 面；FilmstripView:169 `.disabled(agentControl.holdsControl)` M3 重构中逐字节保留。
- **M2LIB-06 legacy 门**:M4 legacyBody 零触碰；`LIGHTAMER_LEGACY_LIBRARY=1` 回归通道行为不变（gate 测试面零 diff）。
- **app-root sheet 禁裸 @Environment（M2-8-3）**:M1 叶挂载走 safeAreaInset 内容面（非 .sheet），Environment 读合法；不新增 sheet 闭包。
- **L057 runModal 禁令**:零面板呈现改动；红线机检 `.runModal(` App/Sources 零命中随批。
- **L041 tuist generate 末动作**:两 plan 均无新测试文件（M3 测试进既有 FilmstripModelTests.swift）→ Project.swift 零 diff；若 ΔN 落新文件则同批登记。
- **FIX2 红线族八条**:本批不触 `.metal`/LightamerIOP/LightamerSidecar/封存面（DrtRecord/GradeCatalog/Registry/HistoryStack/V50Order/ExportFormatSpec/ImageIOEncoders/WebPEncoder/ExportQueueContract）/UserDefaults/xcstrings（除 m9 键尾块纯插入——该红线原文「xcstrings 零 diff」按 m9 申报同批显式豁免一条，plan front-matter 申报）/Project.swift（零新文件时）。
- **FIX2③ 维持**:LibraryProjectController 零 diff（本批全部修法不触 controller——M1d 的 rebuildLibrarySurface 是宿主侧调用点平移，controller 本体零改）。

## §13 留痕

- 侦察时间窗:2026-10-13 单批；证据 = LANEA/LANEB 逐条对照源码亲读 + skill 正本（dataflow.md/structure.md/enhanced-security.md/soft-deprecated 清单）+ FIX2/V2M/M7-5 记录链。
- 勘误三笔（对 A/B 路）:①m2① solveReadout 已有缓存内 consult（§4）；②M2 每 tick 解码计数 15+ → 实测 24+（§5，加重非减轻）；③F1「编译侧可先行单开」不成立（§8 级联耦合）。
- 关联:`.work/GOAL-STATE.md` 续接点（审计修复批 research = 当前站）；A/B 正本 = `.work/audits/xcode27-skills-2026-10/`；本文件为 audit-repair phase 唯一 research 产出。

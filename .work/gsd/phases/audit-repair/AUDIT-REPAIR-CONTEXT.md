# AUDIT-REPAIR CONTEXT — 审计修复批（Xcode 27 skills 对照 A/B 路 findings 修复测绘的执行批；OQ 裁决落定批，2026-10-13）

> **裁决正本**：OQ-M7-AR-1..9 **全部按 `RESEARCH.md` 各节推荐落定**（审计
> 修复批 charter 承 M7 站收官裁链——先例 M6-3/M6-4、M7-2..M7-5、M7-6 同
> 款「OQ 全按推荐」。**晨审可推翻**——推翻 = 用户晨审修订本文件对应 D
> 条，下游 plan 受影响任务面重开（已执行部分按「晨审推翻先例」惯例处理）。
> 读解正本 = 同目录 `RESEARCH.md`（§0 结论摘要 / §1 D-6 禁区 / §2 M1 /
> §3 M4 / §4 M5 / §5 M2 / §6 M3 / §7 验收形态 / §8 构建设置 / §9 分诊 /
> §10 切分 / §11 C 路并入 / §12 房内纪律 / §13 留痕；file:line 经
> planner 2026-10-13 HEAD `363117ee` 抽核 ~45 点亲核吻合——**转写勘误两
> 条**随本文 §勘误节登记，执行以勘误为准）。
>
> **用户裁决点消解（OQ-M7-AR-1 特别登记）**：构建设置三件
> （`ENABLE_ENHANCED_SECURITY` + hardened-process entitlements 族 +
> `ENABLE_POINTER_AUTHENTICATION`/`macOSPackagesShouldBuildARM64e`）
> **全挂账、无 plan D**——级联事实（enhanced-security.md :37
> `ENABLE_ENHANCED_SECURITY = YES` 自动级联 pointer authentication =
> arm64e slice 全链）使 F1/F3 为一个包；unsigned 分发终裁（13-4）下
> runtime enforcement 面全灭。复活条件 = 分发回签名 ∨ 内存安全专项
> （D-M7-AR-1；晨审若裁「采纳」→ 追加 plan D 验证批）。
>
> **C 路并入条款活线**（RESEARCH §11）：C 路 omp 全量深读（automation
> `automation-af8b6363`，周一 00:00）产出合并 MANIFEST 后，执行批必须
> ①新 findings 按 §9 同款分诊并入对应 plan 或追加 plan；②基线以
> MANIFEST 落盘时点全套终态重算 ΔN 对账带；③C 路推翻 A/B 误报时以 C 路
> 为准修正清单；④§8 构建设置裁决不受 C 路影响。三 plan front-matter
> 红线均登记此条款。
>
> **编排总纲**：三 plan，A/B 文件零交集**可并行**、**C 最后**（A 的
> D-6 探针门要求净基线——C 的观感改动会污染树形归因；§10）。A/B 并行
> 窗口内全套 `--all` 轮（批准制）**flock 串行**：锁 `/tmp/la-audit-repair-all.lock`
> （mkdir 原子占位或 fcntl 排它锁；macOS 无 flock(1)，用 fcntl/进程树
> 探测等价——M7-6 验收先例口径）；持锁未释放的 `--all` 启动 = 等待或
> 放弃并上报，**禁双 `--all` 并跑**（8G 门资源面）。定向
> `--bundle App` 轮不受此限。**C 档停位 = plan A 执行+验收闭环后停
> 汇报**（大重构批给用户过目点；先例 M7-6 T6 前停形），确认后 B/C
> 连跑不再停。

## Phase Goal（审计修复批 charter 锚定）

把 Xcode 27 skills 对照审计 A/B 路（正本 =
`.work/audits/xcode27-skills-2026-10/LANEA-FINDINGS.md` 31 finding +
9 note、`LANEB-FINDINGS.md` PASS / 0 error + 5 major + 11 minor +
9 obs，同 commit `388e3875`）的可修项落进产线，**行为保持**优先：
四条大件（M1 宿主失效放大 / M4 根 body 同族 / M5 面板单失效边界 /
M2 每 tick params 重解码）+ M3 Filmstrip id 记账 + 43 处软废弃 +
minor 族 9 项；挂账 3 项（m10 复数 / o4 翻译注释 / o6 LutPanelView
→ D-6 专项卷）；销账 8 项。验收形态：既有测试面（App bundle 定向轮）
+ D-6 探针硬门（树形改动专用）+ GUI 走查三层（§7）；全套基线
`3963/35/0`，全批终值带 `3964..3972`（review F-1——plan A 带
+1..7，T4 fixup 新回归下界强制 ≥1）。

## 决议（D-M7-AR-1..9，生效值，硬约束，执行中不重开）

### D-M7-AR-1 构建设置 = 本批不采纳、三项全挂账、无 plan D（OQ-M7-AR-1）

- **裁决 = RESEARCH §8 推荐**：`ENABLE_ENHANCED_SECURITY`（A 路 F1）、
  hardened-process entitlements 族（F2）、`ENABLE_POINTER_AUTHENTICATION`
  + `macOSPackagesShouldBuildARM64e`（F3）**三项全挂账**；MTE（F4 硬件
  门不达）与 CPA2（F5 macOS 无 enforcement 硬件）维持 N/A note。
- **理由一句**：unsigned 分发终裁下大头（F2 runtime enforcement）为零
  收益；F1 编译侧收益需以 arm64e 全链重验证（app + 2 appex + SPM
  libwebp C 源码 + 测试宿主/测试 bundle）换取，ROI/风险比不成立，且横
  跨构建/测试/依赖三域破坏本批 App 域验收口径纯净性。
- **关键级联事实（勘误 A 路「编译侧可先行单开」口径）**：
  enhanced-security.md :37 明文 `ENABLE_ENHANCED_SECURITY = YES` **级联
  强制 pointer authentication（= arm64e slice 全链）**——F1 采纳即 F3
  生效，不可拆分单开；`macOSPackagesShouldBuildARM64e` workspace 旗标
  为配套义务。
- **复活条件**：分发形态回签名（Developer ID/公证回归）**∨** 内存安全
  专项立项——届时 F1+F3 捆绑单独立项（含 F2 重评），plan 形 = 开关 →
  全量重建 → 全套 `--all`（批准制）+ perf 抽查（PAC 开销 1-3% 量级）
  + D-6 探针复测 + 回滚预案 = 单行 revert。
- 证据：RESEARCH §8 表（pbxproj 三项 0 命中实测；Project.swift:56-70
  `ENABLE_HARDENED_RUNTIME` Release YES/Debug NO 有档 deliberate 精确
  符合 skill 豁免谓词——不触发）；§13 勘误③。
- 晨审推翻点：用户裁「采纳」→ 追加 plan D（构建设置验证批，见复活条
  件 plan 形）。

### D-M7-AR-2 M1 深度裁量 = 最小隔离子集四件，不做 libraryFace/8-sheet 大重排（OQ-M7-AR-2）

- **裁决 = RESEARCH §2 推荐**：四件 = ①四个 onChange 各抽 ViewModifier
  （`PendingAIEnhanceModifier` / `StackCommandModifier` /
  `ImportProgressModifier` / `ProjectURLChangeModifier`）②toast/banner
  叶挂载自读（`ToastBarMount` + `ReadOnlyBannerMount`，既有值传递 init
  零改动）③topBar 抽子 View struct（`WorkspaceTopBar` 窄输入）
  ④`rebuildLibrarySurface()` 从 `.onAppear` 移入既有 `.task` 链（B 路
  C 类副作用）。
- **理由一句**：sheet binding 读是呈现耦合（dataflow.md「Do NOT apply
  when the dependency is also used in rendering output」），且 sheet 面
  树形稳定是 D-6 禁区优先项（§1.2 threshold 承载面）。
- 证据：RESEARCH §2（WorkspaceHostView.swift 1684 行，body :130-429；
  body 作用域非渲染读清单 :166-169/:179-182/:180-181/:266-271/:276-284/
  :322-345/:346-348/:349-351/:608 topBar/:638-639/:653-654/:672-676/
  :1461-1466/:1505-1509——planner 亲核吻合；:335-343 Release `-O` 类型
  检查超时注记 = body 复杂度在预算边界的旁证）。
- 晨审推翻点：翻案 = 深拆 sheet 闭包面（D-6 threshold 风险自担 + 探针
  复测义务加倍，不建议）。

### D-M7-AR-3 M4 修法 = 只动 gate-false 臂 + InspectorPageMount 行使、legacyBody byte-frozen 零触碰（OQ-M7-AR-3）

- **裁决 = RESEARCH §3 推荐**：`.onChange(of: projectController?.projectURL)`
  抽 `ExportQueueRebuildModifier`；可选加深 `InspectorPageMount`（
  inspector 挂载 + focusedSceneValue + onChange 整段下沉）**推荐行使**。
  LANEB「legacyBody 稳定段拆子 View」在此行使为**不采纳**。
- **理由一句**：legacyBody byte-frozen QA 通道纪律（M2LIB-06）+
  legacy 树 idle 0.1%（FIX2 实测反证隔离）零收益，QA 通道行为回归风
  险不对称。
- 证据：RESEARCH §3（ContentView.swift 769 行；gate-false 臂 :175-241 /
  `.inspector` :205-223 / focusedSceneValue :228-233 / onChange
  :238-240；legacyBody :248-418 + StatusBar 值读 :283-285 + 5 onChange
  :326/:340/:351/:359/:362——planner 亲核吻合；LightamerApp.swift
  :508-524 实参闭包重建放大链）。
- 晨审推翻点：翻案 = legacyBody 拆分（破 M2LIB-06 byte-frozen 纪律，
  需用户晨审重开该裁决，不建议）。

### D-M7-AR-4 M5 修法 = 节级子 View struct 拆分 + m11 onAppear 惰性建 + m2②③ 模型缓存，KD-3/o1/o3/scopes 面零触（OQ-M7-AR-4）

- **裁决 = RESEARCH §4 推荐**：Film 拆 `SessionControlsView` /
  `LatitudeSectionView` / `PlacementSectionView`（各持 `let model:
  FilmPanelModel` 类引用 + 各自窄读）；Drt 拆 `DrtMethodCard` /
  `DrtEncodingGroup` / `DrtLimitingGroup` / `DrtPresetGroup`
  （`encodingExpanded` @State 随 encodingGroup 迁移）；m11 改 onAppear
  惰性建（FilmPanelView:49-51 仓内定式）；m2② isCustomLook 按
  recordHash 键 stored 缓存 + ③ placementTarget 写点刷新；o9 顺路下沉。
- **理由一句**：computed property 不设独立失效边界（structure.md §1），
  60Hz live tick 拖动下任一模型属性 tick 重估整面板（含 Canvas 直方
  图 + picker 全量）——拆节后各节独立边界；m2① 已勘误降级（solve 内
  部已 consult FilmSolveCache，FilmTailPolicy.swift:629）。
- **不动**：KD-3 三级读形态（o5 豁免）、D-H1 闭包绑定（o1 豁免）、
  scopes 面（M7-5 disable-not-unmount 无交涉面）、o3 AnyView 注册缝
  （D12 33-panel 契约）；条件分支形态保持（`if model.isPristine` 原样
  ——不新增条件卸载）。
- 证据：RESEARCH §4（FilmPanelView.swift 594 行 body :23-57 + :49-51
  onAppear 定式 + :61/:84/:109 分节 + :339/:498-509 m9 落点；
  DrtPanelView.swift 313 行 init :23-30 + body :32-48 + :52/:76/:124
  四节；FilmPanelModel.swift :117/:330；DrtPanelModel.swift :90-92——
  planner 亲核吻合）。
- 晨审推翻点：翻案 = 深拆到 row 级 ∨ 模型改上层注入形（拆分粒度与
  init 形态重开，走查面加大）。

### D-M7-AR-5 M2 修法 = stored-params 形态（每面板 init 一次解码存 `let params`）（OQ-M7-AR-5）

- **裁决 = RESEARCH §5 推荐**：39 面板 `params(of:)` 调用点提升
  stored——custom init（或保留 memberwise + init 内一次解码）存
  `let params`，删 computed property；`PanelEditing.params(of:as:)`
  helper 签名不变（值传参已解耦）；binding 闭包捕获 stored 值；Core
  `ModuleInstance.params(of:)` 零改（纯 App 层消费形态）。
- **零 stale 风险论据（进 plan 头注）**：`instance` 是面板 View 的
  `let` 值捕获（ChannelMixerRGBPanelView.swift:23）——computed `params`
  与 Binding get/set 闭包内读（discreteBinding :322 等）每次解码的是
  **同一份字节**；记录变更恒经 `edit.update` → 父链重估 → 面板以新
  instance 重建 → init 重解码。提升 stored = 纯语义等价。
- **被否备选**：body-top `let params = self.params`（更薄但 helper 闭
  包再读需逐处过——48 命中面不推荐）；@State 缓存（per-tick paramsHash
  必 miss，无益，弃）。
- 证据：RESEARCH §5（ModuleInstance.swift:146-152 每次
  `JSONDecoder().decode`；ChannelMixerRGB 单 body ≈ 24+ 次解码实测——
  B 路估 15+ 偏保守，勘误②）；planner 实测勘误①：RESEARCH「48 文件」
  实为 **48 命中 / 41 文件 / 39 直读面板**（`private var params: X.Params {`
  直读形 grep = 39 文件，codemod scope 正本）。
- 晨审推翻点：翻案 = body-top let 形（验收面更碎、闭包读逐处过，不建
  议）。

### D-M7-AR-6 行为保持验收 = 三层（既有测试面 + D-6 探针硬门 + GUI 走查）（OQ-M7-AR-6）

- **裁决 = RESEARCH §7 推荐**：①既有测试面 = App bundle 定向轮
  （`Scripts/test-direct.sh --bundle App`，M7-6 口径 917 法）每 plan
  终了一跑；全套 `--all` 不强制（改动全 App 域，orchestrator 批准
  制）。②**D-6 探针硬门** = 每次树形改动后复测：重开项目进编辑器静
  置 CPU<10%（ps/sample 机检；10-30% 区间 = 未达标，触发判别探针二轮
  迭代义务——FIX2-01-PLAN T1 SC 原文）+ 空载无项目面同口径记录；plan A
  内 M1/M4/M5 合并复测一次 + plan B 面板批后复测一次（A/B 并行可合并
  到两 plan 都落盘后一跑）；walkthrough 配方 = `gui-acceptance/v2m/`
  D-6 复现链（6 图项目重开 + 编辑器三铁条：spin 消失 / filmstrip 点击
  换图出图 / 截图证据）。③GUI 走查 = plan A（toast/banner/import 进
  度/项目切换 + 面板拖动 60Hz + Export 页开闭）+ plan C（borderlessButton
  5 处截图对比——唯一非逐字节等价面 + m9 readout 布局复核）；**AX 树
  快照对比 = 可选增强不设门**（AX 深遍历是 L057-B 压力因子，§1.5 轻
  用纪律）。
- 证据：RESEARCH §7 + FIX2-01-PLAN T1 SC（CPU 门判定式原文）+
  `gui-acceptance/v2m/` 复现链证据在库。
- 晨审推翻点：翻案 = 加 AX 快照硬门（放大 L057-B 压力因子，不建议）。

### D-M7-AR-7 M3 修法 = visibleIDs: Set<Int64> 记账 + row.id 直传 + idToIndex 每次 refresh O(n) 重建（OQ-M7-AR-7）

- **裁决 = RESEARCH §6 推荐**：`FilmstripModel.visibleIndices: Set<Int>`
  换 `visibleIDs: Set<Int64>`；View 侧直传 `row.id`（**firstIndex 反查
  整体消灭**——病害二零成本顺手修）；`warmWindow` 解析 = model 在
  refreshWindow 时以 `idToIndex: [Int64: Int]` 字典**每次 refresh O(n)
  重建**（正确性优先——fixup 中插/删/重排全形态下指纹易错，重建式无
  正确性洞；指纹缓存挂后续优化）；`scrollAnchorID`/`select`/
  `listDisappeared` API 形态不变；`pager.cellAppeared(at:)` API 不动
  （LibraryGridView:166-170 改 `ForEach(grid.rows.enumerated(),
  id: \.element.id)` 携带 index——分页按 index 是设计内）。
- **理由一句**：expanded 堆叠 fixup 中途插行（`LibraryGridModel.
  stackAdjacencyFixup` :40 anchor+1 insert）使位置索引整体移位，而
  SwiftUI List 行 identity 是 `row.id`（cell 不卸载、不触发
  onDisappear）→ 位置记账慢性虚胖 + 多发 `prioritize`。
- 证据：RESEARCH §6（FilmstripView.swift :45 visibleIndices / :66-74
  warmWindow / :119-136 refreshWindow / :169 disabled / :194-203
  firstIndex 双处；LibraryGridView.swift :166-170；
  FilmstripModelTests.swift :89/:96/:141-142/:179-197 全 index API——
  planner 亲核吻合）。
- 晨审推翻点：翻案 = idToIndex 指纹缓存（正确性洞风险——fixup 全形态
  指纹易错，不建议）。

### D-M7-AR-8 m10 xcstrings 复数变体 = 挂账（OQ-M7-AR-8）

- **裁决 = RESEARCH §9 推荐（默认挂账）**：0 用户可见缺陷（zh 无复数
  形态，实害 = 英文名词屈折）；全量加 variations = 大回归面低收益；
  缩量方案（photos/subjects/jobs 族 ~5-10 键）备选呈用户裁，默认
  挂账。
- 证据：RESEARCH §9 minor 表（1957 键 0 variations 实核坐实）。
- 晨审推翻点：用户裁「缩量修」→ plan C 追加 T 项（+2..3 键
  variations 尾块纯插入 + zh-audit 对账）。

### D-M7-AR-9 plan 切分 = 三 plan（A/B 零交集可并行、C 最后）（OQ-M7-AR-9）

- **裁决 = RESEARCH §10 推荐**：plan A = d6 面大重构（M1/M4/M5 + 顺路
  m2②③/m11/m9/o9 + M3 含 m6，ΔN +1..7——review F-1 勘误）；plan B = M2 39 面板
  stored-params codemod（ΔN +0..1）；plan C = 机械小件批（软废弃 43 +
  m1/m4/m5/m7/m8，ΔN +0..1）。A/B 文件零交集（A = UI/Shell/ 宿主面板
  族 + ContentView + LibraryGridView；B = UI/Inspector/ 面板域——唯一
  共享依赖 LightamerSlider 只读）可并行；C 最后（含观感改动，走查一次
  定稿；C 与 A/B 文件交集合法——串行保证）。
- **编排细则**：A/B 并行窗口内 `--all` 轮 flock 串行（本文件头注编排
  总纲）；**C 档停 = plan A 执行+验收闭环后停汇报**，确认后 B/C 连跑。
- 证据：RESEARCH §10（串行理由：A 的 D-6 探针门要求净基线；B/C 机械
  批任何时刻可插队；A 的 C 档停与 B/C 的无停形成自然裁决节奏）。
- 晨审推翻点：翻案 = 全串行 ∨ 单 plan 分任务序（总 Δfiles ~78 但逐任
  务独立 commit 可满足验收；编排开销变大）。

## 转写勘误（RESEARCH → 本批 planner 亲核批，非矛盾、执行以勘误为准）

1. **M2 面数勘误**：RESEARCH §5「grep 实证 `UI/Inspector/` 48 文件含
   `params(of:`」——实测 **48 = 命中数**；含命中文件 = 41；
   **codemod scope = 39**（`private var params: X.Params {` 直读形文
   件数，B 路 39 面板口径成立）。plan B 以 39 为正本，执行时 grep 重
   定清单落 DECISIONS。
2. **路径补全**：RESEARCH §0.1/§4 引 `FilmTailPolicy.swift:629`——全
   路径 = `LightamerCore/Sources/Pipe/Film/FilmTailPolicy.swift:629`
   （`FilmSolveCache.shared.autoSolution(for:)` consult 行，m2① 勘误
   降级的证据锚）。
3. 其余 ~45 抽核点（WHV/CV/Film/Drt/Filmstrip/LibraryGrid/ModuleInstance/
   IOPPanelProvider/ChannelMixerRGB/McpLauncher/CropOverlayHost/
   SettingsPages/LibraryInspectorView/ExportNamingEditor/SessionBrowser/
   EditorAdjustmentStackView/Project.swift）全部吻合（±1 行内微差不影
   响语义）。
4. **@Published 计数勘误（review F-4）**：McpLauncherPanelView.swift
   全文件 `@Published` = **6** 处（:33-41——lines/followScroll/
   isRunning/runningPID/lastOutcome/hint）；LANEB m4 与 AR-03 T2
   「×7 直剥」均差 1——grep 清零判据不受影响，纯数字面勘误
   （AR-03 已随批同步 ×7 → ×6）。
5. **「39 面板」计量单位勘误（review F-4）**：实为 39 **文件** / 44
   处 `private var params` 直读形（GradeScalarPanels.swift 一文件 6
   个面板 struct 各 1 处，:27/:101/:155/:208/:262/:316）——AR-02
   命中数恒等式按处数闭合（44 + helper 1 + 其余 3 = 48 ≤ 48）；勘误
   ①（48 命中/41 文件/39 直读）在文件口径维持成立。

## 登记申报（非 OQ）

- **xcstrings**：plan A m9 恰 +2..3 键尾块纯插入（latitude_share 族格
  式键，终账 DECISIONS 申报）；plan B/C 零新键预期。FIX2 红线族原文
  「xcstrings 零 diff」按 m9 同批显式豁免一条（三 plan front-matter
  申报）。
- **UserDefaults**：三 plan 零新键预期（KD-4）。
- **Project.swift**：零 diff 预期（plan A M3 测试进既有
  FilmstripModelTests.swift；plan C ΔN 不落新文件）——例外 = plan B
  env 门探针若落新文件则 Project.swift 恰 +1 行 + BUNDLE-MAP 恰一行 +
  `tuist generate` 恒为该批最后一个动作（L041）。
- **ΔN 对账带**：plan A +1..7（review F-1 勘误——原文 +0..6 漏 T4
  fixup 新回归 +1..3 的下界强制 ≥1）/ plan B +0..1 / plan C +0..1 →
  全批终
  值带 **3964..3972**（基线 `3963/35/0`，M7-6 收口终态；skip 35 = 24
  基线 + 11 RAW 供件漂移；第三种 skip 来源逐族差分申报禁静默吸收）。
- **销账 8 项明细**（落 plan C DECISIONS 正式登记）：o1（闭包 Binding
  ——D-H1 约定豁免）/ o2（动态查表键——V15 豁免 + 手工在册实证）/
  o3（面板 AnyView 注册缝——D12 33-panel 契约）/ o5（三级读——KD-3
  约定本体）/ o7（onAppear 惰性建——仓内一致定式，m11 顺势对齐）/
  o8（Settings onAppear 重播种——onChange 写穿闭环合规）/ m2①（勘误
  降级注记——solve 已有 FilmSolveCache 内 consult）/ m3 note-1/2/3
  （Font.system ×31 / GeometryProxy.frame ×1 / Stepper ×2——重载消歧
  大概率已落新臂，零行动）。
- **挂账 3 项**：m10（xcstrings 复数，D-M7-AR-8）/ o4（翻译注释——
  开放翻译贡献时补）/ o6（LutPanelView `.id(libraryRevision)` 子树身
  份重置——d6-relevant churn 放大器，LUT 页卡顿第一嫌疑，**入 D-6 专
  项卷**，本批不动）。
- **测试登记**：三 plan 均优先改写既有测试文件（FilmstripModelTests
  改写 id API + fixup stale-window 新回归；DrtPanelModelTests 既有面
  零触确认）；新测试文件仅 plan B 探针一处（见 Project.swift 条）。
- **键族登记面摘要**：plan A = `latitude_share` 族格式键 +2..3（xcstrings
  尾块纯插入）；plan B/C = 零。

## 晨审推翻点索引（可推翻面速查）

- **D-M7-AR-1**：三项挂账 ↔ 采纳（追加 plan D）——翻案 = 构建设置验证
  批立项（开关 → 全量重建 → `--all` 批准制 + perf 抽查 + D-6 探针复
  测 + 单行 revert 预案）。
- **D-M7-AR-2**：最小隔离子集 ↔ 深拆 sheet 面——翻案 = AR-01 T1 扩面
  （D-6 threshold 风险自担）。
- **D-M7-AR-3**：gate-false 臂 only ↔ legacyBody 拆分——翻案 = 破
  M2LIB-06 byte-frozen（QA 通道回归面重开）。
- **D-M7-AR-4**：节级拆分 ↔ row 级深拆 ∨ 模型注入形——翻案 = AR-01
  T3 粒度/init 形态重开。
- **D-M7-AR-5**：stored-params ↔ body-top let——翻案 = AR-02 codemod
  形态重开（验收面更碎）。
- **D-M7-AR-6**：三层验收 ↔ 加 AX 快照门——翻案 = L057-B 压力因子放
  大（不建议）。
- **D-M7-AR-7**：重建式 idToIndex ↔ 指纹缓存——翻案 = 正确性洞风险
  自担（fixup 全形态指纹易错）。
- **D-M7-AR-8**：m10 挂账 ↔ 缩量修（photos/subjects/jobs 族 ~5-10 键
  variations）——翻案 = plan C 追加 T 项。
- **D-M7-AR-9**：三 plan（A/B 并行 + C 最后）↔ 全串行 ∨ 单 plan——
  翻案 = 编排重排（B/C 插队合法性收回）。

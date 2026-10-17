---
phase: audit-repair
plan: "AR-01"
title: "plan A — d6 面大重构（行为保持验证重）：T1 M1 WorkspaceHostView 宿主失效隔离（四 onChange 抽 ViewModifier + toast/banner 叶挂载自读 + topBar 抽子 View + rebuildLibrarySurface 移 .task）/ T2 M4 ContentView gate-false 臂（onChange 抽 modifier + InspectorPageMount 下沉；legacyBody byte-frozen 零触）/ T3 M5 Film/Drt 面板节级拆子 View + m11 onAppear 惰性建 + m2②③ 模型缓存 + m9 本地化拼接改格式键 + o9 顺路下沉 / T4 M3 Filmstrip id 记账（visibleIDs Set<Int64> + row.id 直传 + firstIndex 消灭 + fixup stale-window 回归）/ T5 定向轮 + D-6 探针硬门（M1/M4/M5 合并一次）+ GUI 走查配方 + SUMMARY/DECISIONS"
wave: 1
depends_on: []
autonomous: true
requirements: ["审计修复批 charter：A/B 路 findings 可修项行为保持落线（正本 = .work/audits/xcode27-skills-2026-10/LANEA-FINDINGS.md + LANEB-FINDINGS.md，commit 388e3875）", "调研正本 = phases/audit-repair/RESEARCH.md（§1 D-6 禁区 / §2 M1 / §3 M4 / §4 M5 / §6 M3 / §7 验收形态 / §10 切分 / §12 房内纪律）", "OQ 裁决正本 = phases/audit-repair/AUDIT-REPAIR-CONTEXT.md（D-M7-AR-1..9 全按 RESEARCH 推荐，晨审可推翻）", "全套基线 3963/35/0（M7-6 收口终态）；本 plan 带 +1..7（review F-1——T4 fixup 新回归 +1..3 下界强制 ≥1，带下界非 0）→ 终值带 3964..3970", "C 档停位 = 本 plan 执行+验收闭环后停汇报（大重构批给用户过目点）；确认后 plan B/C 连跑"]
success_criteria: "SC 全可机检——T1（M1）：四 modifier（PendingAIEnhanceModifier / StackCommandModifier / ImportProgressModifier / ProjectURLChangeModifier）落位且 WorkspaceHostView body 作用域 `.onChange(of: (workspace.pendingAIEnhance|workspace.pendingStackCommand|projectController?.importProgress|projectController?.projectURL))` 四观察零命中（grep 分组形——review F-7）+ ToastBarMount 自读 `@Environment(EditorState.self)` 转发既有 `ToastBarView(toast:)` + ReadOnlyBannerMount 转发既有 `ProjectReadOnlyBannerView(isReadOnly:holderPid:)`——两叶既有值传递 init 零 diff（ToastFaceTests 零 diff 全绿）+ safeAreaInset 双挂载形不变（:166-169 top banner / :179-182 bottom toast 的 `.safeAreaInset(edge:)` 修饰符族原位保留，仅内容表达式换 Mount）+ `WorkspaceTopBar` 子 View struct 落位（窄输入 phase/projectName/isReadOnly/holdsControl + 回调；isReadOnly ×3 与 holdsControl ×2 读收进 topBar）+ rebuildLibrarySurface() 从 `.onAppear`（:349-351）移入既有 `.task` 链（:355 起，onAppear 摘除）+ menus/focus 形态零触碰（:183 focusedSceneValue 挂点零 diff）；T2（M4）：`ExportQueueRebuildModifier` 落位 + gate-false 臂 body 作用域 onChange(of: projectController?.projectURL) 零命中 + `InspectorPageMount` 下沉（.inspector :205-223 + .focusedSceneValue :228-233 + onChange :238-240 整段）后根 body 只剩常量读 + WorkspaceHostView 装配 + Mount + **legacyBody :248-418 逐字节零 diff**（机检：HEAD 版 vs 工作版 :248-418 段 diff 零输出——review F-6 命令形见 T2 验收）；T3（M5）：Film 拆 SessionControlsView / LatitudeSectionView / PlacementSectionView 三子 View struct（各持 let model 类引用 + 窄读）+ Drt 拆 DrtMethodCard / DrtEncodingGroup / DrtLimitingGroup / DrtPresetGroup 四子 View struct（encodingExpanded @State 随 encodingGroup 迁移）+ m11 = DrtPanelView init State(initialValue:)（:23-30）摘除改 onAppear 惰性建（body 包 `if let model`，FilmPanelView :49-51 定式）+ m2② isCustomLook 按 recordHash 键 stored 缓存 + ③ placementTarget 写点刷新缓存（commit 点零触）+ 条件分支形态保持（if model.isPristine 原样，零新增条件卸载）+ scopes 面零 diff + D-H1 绑定链逐行平移（live tick→setLive、dragEnd→commit 零改；grep setLiveParams/commitFilmEdit/recordDrtChange 绑定面零漂移）+ m9 = :339 改单 `String(localized:)` 格式键（xcstrings 恰 +2..3 键尾块纯插入）+ :498-509 改并排独立 Text（零新键）+ o9 = EditorAdjustmentStackView :135-136 InspectorEditSession 新建下沉模型；T4（M3）：FilmstripModel 可见窗换 `visibleIDs: Set<Int64>` + View 侧直传 row.id（FilmstripView :194-203 与 LibraryGridView :166-170 的 `firstIndex(where:)` 反查 App/Sources 零命中）+ warmWindow 解析经 `idToIndex: [Int64: Int]` 每次 refreshWindow O(n) 重建 + scrollAnchorID/select/listDisappeared API 形态不变 + `pager.cellAppeared(at:)` API 不动 + FilmstripView :169 `.disabled(agentControl.holdsControl)` 逐字节保留 + FilmstripModelTests 改写 id API（法数不变）+ fixup 中插 stale-window 新回归 +1..3 法；T5：`--bundle App` 定向轮全绿 + D-6 探针硬门（重开项目进编辑器静置 CPU<10% ps/sample 机检 + 空载无项目面同口径记录 + 三铁条）+ GUI 走查逐项（toast/banner/import/项目切换 + 面板拖动 60Hz + Export 页开闭 + filmstrip fixup 请求计数不虚胖）+ MANIFEST/SUMMARY/DECISIONS 落盘 + 全套 --all 不强制（批准制；若跑 = /tmp/la-audit-repair-all.lock 串行）"
estimated_tests: "+1..7（review F-1——T4 新回归下界强制 +1；M3 FilmstripModelTests 新回归 +1..3 / m2②③ 缓存纯函数测试 +0..2 / M1 modifier 消费逻辑平移可抽纯函数负测 +0..2（合法 ΔN=0）/ 其余 0；执行时逐任务如实记账，越带申报理由）"
test_bundles: [APP]
baseline: "3963/35/0（M7-6 收口终态，skip 35 = 24 基线 + 11 RAW 供件漂移；HEAD 363117ee = audit-repair research docs-only 产线零漂移；planner 2026-10-13 亲核 git log/status——工作区三个未跟踪文件为既有在制品非本批）"
expected_all: "3963 + ΔN（对账式；ΔN 带 +1..7 → 终值带 3964..3970——review F-1，执行时按实记账；skip 35 口径维持——第三种 skip 来源逐族差分申报禁静默吸收；--all 批准制 + A/B 并行窗口 /tmp/la-audit-repair-all.lock 串行）"
red_lines:
  - "D-6 交互禁区（正本 = RESEARCH §1，FIX2 链）：①menus/focus 形态零触碰——.focusedSceneValue 挂点（WorkspaceHostView:183 / ContentView:287-288、:228-233）、LightamerApp Commands 求值面、legacyBody 的 toolbar/alert 链不得移动摘除或改变求值路径；菜单环燃料面（visibleMenuCommands/ratingMenuLabel/metadataTextEntryActive）零触。②threshold 承载面不得结构性增删——双 safeAreaInset（WHV:166-169/:179-182）挂载方式（.safeAreaInset(edge:) 修饰符族）保持原形（本 plan 改造 = 内容面替换非挂载点摘除）；.inspector 分栏（CV:205-223）形态不动；编辑器三段内容段数不变。③每次树形改动 = FIX2 T1 探针复测硬门：重开项目进编辑器静置 CPU<10%（ps/sample 机检；10-30% = 未达标触发判别探针二轮迭代义务）+ 空载无项目面同口径记录；本 plan 内 M1/M4/M5 合并复测一次（同一批树形改动一次探针轮覆盖三件）；walkthrough 配方 = gui-acceptance/v2m/ D-6 复现链（6 图项目重开 + 编辑器三铁条）。④AX 自动化轻用（L057-B 共同因子——定点 AX 断言形，禁全树深遍历放大）。⑤o6 LutPanelView .id(libraryRevision) 本批不动（挂 D-6 专项卷）。"
  - "disable-not-unmount 三纪律（M7-5）：T3 面板拆分不涉 scopes 面（无交涉面）；条件分支形态保持（if model.isPristine 原样——不新增条件卸载）；FilmstripView:169 .disabled(agentControl.holdsControl) 逐字节保留（T4）。"
  - "FIX2③ = LibraryProjectController.swift 文件零 diff（本 plan 全部修法不触 controller——T1d 的 rebuildLibrarySurface 是宿主侧调用点平移，controller 本体零改；git diff --stat 核不在清单）。"
  - "ToastFaceTests.swift 零 diff（T1 toast 叶挂载改造的既有回归钉——ToastBarView(toast:) 与 ProjectReadOnlyBannerView(isReadOnly:holderPid:) 既有值传递 init 零改；改造走 Mount 叶自读转发）。"
  - "legacyBody byte-frozen（M2LIB-06）：ContentView.swift :248-418 段逐字节零 diff（T2 只动 gate-false 臂）；LIGHTAMER_LEGACY_LIBRARY=1 回归通道行为不变（LibraryLegacyGateTests 零 diff 全绿）。"
  - "封存面零 diff（FIX2 红线族）：LightamerIOP/ 全域、*.metal 全域、LightamerSidecar、DrtRecord / TerminalTailPolicy / DrtTailAssembly / PixelPipe / Lut3dKernels.metal / DrtEotf / ExportQueueContract / 六格式导出矩阵 / NodeGraphCommand / HistoryStack / HistoryHash / PipelineDocument（Core）/ V50Order / GradeCatalog（NodeOwnershipCatalog）/ Registry / ModuleInstance（params(of:) Core 面零改——本 plan 纯 App 层）。"
  - "xcstrings 恰 +2..3 键（m9 latitude_share 族格式键，终账 DECISIONS 申报——FIX2 红线族原文「xcstrings 零 diff」按 m9 同批显式豁免一条）尾块纯插入，历史键字节与顺序零触碰；zh-audit --check 对账 + --self-test 双 PASS；T2/T4 不触本地化面。"
  - "UserDefaults 零新键（KD-4）；.runModal( 在 App/Sources 零命中（L057 禁令随批机检）；String.LocalizationValue(\"prefix_\\(x)\" 插值禁形零命中（m9 新键一律 String(localized: 静态键, defaultValue:) 显式形态——M2-9 F-2 禁令）。"
  - "M2-8-3 app-root sheet 禁裸 @Environment：T1 叶挂载走 safeAreaInset 内容面（非 .sheet），Environment 读合法；零新增 sheet 闭包。"
  - "C 路并入条款（RESEARCH §11）：周一合并 MANIFEST 落盘后，C 路新 findings 按 CONTEXT §9 同款分诊并入对应 plan 或追加 plan；C 路推翻本 plan 清单项（如软废弃/firstIndex 命中存疑）时以 C 路为准修正——执行前亲读合并 MANIFEST 一轮；基线按合并 MANIFEST
  落盘时点全套终态重算 ΔN 对账带（review F-9——RESEARCH §11②，本文带
  +1..7/3964..3970 为 3963 静态基线形态，合并时点漂移即重算对齐）。"
  - "构建 caffeinate -dis 包裹；单测 = Scripts/test-direct.sh --bundle App 定向；全套 --all 批准制（运行中保持监视 + 8G 门 + MEMFAIL 机检，超门立即 kill；A/B 并行窗口 /tmp/la-audit-repair-all.lock 串行——macOS 无 flock(1) 用 mkdir/fcntl/进程树探测等价）；测试宿主清理先核 parentage（ps -o ppid——测试宿主 parent = 脚本进程树，GUI 实例 parent = launchd，M2-7-3 先例）。"
  - "Project.swift 零 diff（本 plan 零新测试文件——M3 测试进既有 FilmstripModelTests.swift；BUNDLE-MAP 零触）。"
files_modified:
  - App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift        # T1：四 onChange 抽 modifier（:266-271/:276-284/:322-345/:346-348 消费逻辑逐行平移）+ ToastBarMount/ReadOnlyBannerMount 叶挂载（:166-169/:179-182 内容面替换、挂载形不变）+ WorkspaceTopBar 子 View（:608 起私有 topBar 收编，窄输入 + 回调）+ rebuildLibrarySurface 移 .task（:349-351 onAppear 摘除、:355 起 task 链合并或并列）——menus/focus（:183）与既有 sheet 闭包零触
  - App/Sources/Lightamer/UI/ContentView.swift                   # T2：gate-false 臂（:175-241）——ExportQueueRebuildModifier（:238-240 下沉）+ InspectorPageMount（.inspector :205-223 + .focusedSceneValue :228-233 整段下沉）；legacyBody :248-418 逐字节零 diff
  - App/Sources/Lightamer/UI/Shell/FilmPanelView.swift           # T3：拆 SessionControlsView/LatitudeSectionView/PlacementSectionView（:109/:84 起/:61 起 private var 节收编）+ m9 :339 格式键 + :498-509 并排 Text——D-H1 绑定逐行平移、scopes 零触
  - App/Sources/Lightamer/UI/Shell/FilmPanelModel.swift          # T3：m2② placementTarget 写点刷新缓存（:330-345）；solveReadout（:117-130）勘误注记零代码
  - App/Sources/Lightamer/UI/Shell/DrtPanelView.swift            # T3：拆 DrtMethodCard/DrtEncodingGroup/DrtLimitingGroup/DrtPresetGroup（:52/:76/:124 private var 节收编；encodingExpanded @State 随 encodingGroup 迁移）+ m11 :23-30 init State(initialValue:) 摘除改 onAppear 惰性建（body 包 if let model）
  - App/Sources/Lightamer/UI/Shell/DrtPanelModel.swift           # T3：m2② isCustomLook 按 recordHash 键 stored 缓存（:90-92 消费面）
  - App/Sources/Lightamer/UI/Shell/EditorAdjustmentStackView.swift # T3：o9 顺路——:135-136 InspectorEditSession 每 body 新建下沉模型（量级豁免项顺路；m1 AnyView 签名归 plan C）
  - App/Sources/Lightamer/UI/Shell/FilmstripView.swift           # T4：View 侧直传 row.id（:194-203 firstIndex 反查摘除）+ visibleIDs 消费面适配 + :169 .disabled 逐字节保留
  - App/Sources/Lightamer/Library/Views/LibraryGridView.swift    # T4：:166-170 改 ForEach(grid.rows.enumerated(), id: \\.element.id) 携带 index——pager.cellAppeared(at:) API 不动
  - App/Sources/Lightamer/Library/LibraryGridModel.swift         # T4：stackAdjacencyFixup（:40）零 diff（只读锚——回归测试的插行语义源）
  - Resources/Localizable.xcstrings                              # T3：m9 恰 +2..3 键尾块纯插入（latitude_share 族格式键）
  - Tests/LightamerTests/FilmstripModelTests.swift               # T4：改写 id API（法数不变）+ fixup 中插 stale-window 新回归 +1..3 法
  - .work/gui-acceptance/audit-repair/MANIFEST.md                # T5：走查配方（AR-01 节：D-6 探针配方 + toast/banner/import/项目切换 + 面板拖动 60Hz + Export 页开闭 + filmstrip fixup 计数 + m9 readout 布局观察行）——实机走查归验收批/用户
  - .work/gsd/phases/audit-repair/AR-01-SUMMARY.md               # T5：执行摘要（逐任务 ΔN 记账 + 验收判定指针 + 越带申报）
  - .work/gsd/phases/audit-repair/AR-01-DECISIONS.md             # T5：裁定记录（modifier 终形 + m2 缓存键终形 + m9 键数终账 + xcstrings 豁免申报 + 各偏差）
---

# Plan AR-01 — plan A：d6 面大重构（M1 宿主失效隔离 + M4 gate-false 臂 + M5 面板分节 + M3 Filmstrip id 记账）

> **裁决正本** = `AUDIT-REPAIR-CONTEXT.md`（D-M7-AR-1..9 全按 RESEARCH
> 推荐——晨审可推翻）；规格正本 = `RESEARCH.md`（§1 禁区 / §2 M1 / §3
> M4 / §4 M5 / §6 M3 / §7 验收 / §12 纪律；file:line 经 planner
> 2026-10-13 HEAD `363117ee` 逐点亲核吻合——勘误两条见 CONTEXT §勘误，
> 本 plan 引用以勘误后为准）。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（四任务形态 = CONTEXT
> D-M7-AR-2/3/4/7 落定值）。执行中如触「必须扩面」（sheet 闭包重排 /
> legacyBody 触碰 / scopes 面改动 / 封存面触碰 / KD-3 三级读改形 /
> D-H1 提交语义改道）= 停手上报，不得自裁扩界。
>
> **执行序**：T1 → T2 → T3 → T4 → T5。T1-T4 产线批（每任务独立 commit
> + 构建绿机检），T5 轮次 + 探针硬门 + 走查配方 + 收口文档。每任务独
> 立 commit（Conventional Commits，全英文，只 add 相关文件，不 push）。
>
> **C 档停**：T5 闭环后**停汇报**（本 plan = 大重构批，给用户过目点）；
> 确认后 plan B/C 连跑（编排 = CONTEXT 头注总纲）。
>
> **基线**：**3963/35/0**（M7-6 收口终态；HEAD `363117ee`）。全套预期
> `TOTAL|3963+ΔN/35/0|`（ΔN 带 +1..7 → 终值带 3964..3970——review F-1，
> 对账式；
> `--all` 批准制，不强制）。

## ΔN 预算表（逐任务，合计带 +1..7——review F-1：T4 下界强制 ≥1；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 M1 | **+0..2** | modifier 消费逻辑平移可抽纯函数负测（ImportProgress adapter 生命周期逻辑）；合法 ΔN=0 | 既有 App bundle 面回归底线（ToastFace/WorkspaceRouting/ProjectReadOnlyFace/EditorStackRouting 全绿即 0） |
| T2 M4 | **0** | 纯结构下沉，无新逻辑面 | WorkspaceRouting/LibraryLegacyGate 既有面 |
| T3 M5 | **+0..2** | m2②③ 缓存纯函数测试（recordHash 键命中/失效两腿） | DrtPanelModelTests 扩或 DECISIONS 申报让渡 |
| T4 M3 | **+1..3** | fixup 中插 stale-window 新回归（可见 id 集插行后仍产正确 warm 窗 + 无 stale id 残留）+ id API 改写（法数不变） | FilmstripModelTests |
| **合计** | **+1..7** | 3963 → 终值带 3964..3970（review F-1） | 全 APP 域；Project.swift 零 diff |

## 已定裁决（生效值，硬约束，不得重开）

1. **M1 = 最小隔离子集四件**（OQ-2）：四 modifier + 双叶挂载自读 +
   topBar 子 View + rebuildLibrarySurface 移 .task；不做 libraryFace/
   8-sheet 大重排（sheet binding 读 = 呈现耦合，D-6 禁区优先）。
2. **M4 = 只动 gate-false 臂**（OQ-3）：ExportQueueRebuildModifier +
   InspectorPageMount（行使加深）；legacyBody byte-frozen 零触。
3. **M5 = 节级子 View struct 拆分**（OQ-4）：Film 三节 + Drt 四节 +
   m11 惰性建 + m2②③ 缓存 + m9/o9 顺路；KD-3/o1/o3/scopes 面零触。
4. **M3 = visibleIDs: Set<Int64>**（OQ-7）：row.id 直传 + firstIndex
   消灭 + idToIndex 每次 refresh O(n) 重建（指纹缓存挂后续）。
5. **验收 = 三层**（OQ-6）：App bundle 定向轮 + D-6 探针硬门（M1/M4/
   M5 合并一次）+ GUI 走查；AX 快照可选不设门。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/audit-repair/AUDIT-REPAIR-CONTEXT.md`（D-M7-AR-1..9
  裁决 + 勘误两条 + 编排总纲 + 晨审推翻点索引）
- `.work/gsd/phases/audit-repair/RESEARCH.md` §1（D-6 禁区全文）+ 对应
  任务节（§2/§3/§4/§6）+ §7（验收形态）+ §12（房内纪律核对表）
- `.work/gsd/phases/fix2-defects/FIX2-01-PLAN.md`（T1 SC 探针门判定式
  原文 + red_lines 八条——D-6 禁区正本链末端）
- `.work/gsd/phases/fix2-defects/FIX2-VALIDATION.md`（T1 探针定罪 +
  三选一裁定①——D-6 定性正本）
- `.work/config.toml [gsd]` paused/auto 开关（开工前亲核）
- `.work/LESSONS.md` L041（tuist generate 恒末位——本 plan 预期不触发）
+ CONVENTIONS V14/V15（动态键纪律）+ M2-8-3（app-root sheet 禁裸
  @Environment）节

---

## T1 — M1：WorkspaceHostView 宿主失效隔离（四 onChange 抽 modifier + toast/banner 叶自读 + topBar 抽子 View + rebuildLibrarySurface 移 .task）

> **行为保持**为唯一验收语义：消费逻辑逐行平移、既有值传递 init 零
> 改、挂载形不变。禁顺手改任何 D-6 禁区面（§1 全文）。

**read_first**：`RESEARCH.md` §2 全节（body 作用域非渲染读清单 + 修法
四件 + dataflow.md EditorChangesModifier 定式出处）；`WorkspaceHostView.swift`
:130-183（body 头 + 双 safeAreaInset + focusedSceneValue）+ :266-284
（两 request-consumption onChange）+ :322-355（importProgress onChange
+ projectURL onChange + onAppear rebuildLibrarySurface + task 链起点）
+ :608-676（topBar 全形 + projectName + isReadOnly/holdsControl 读点）
+ :1461-1470（ProjectReadOnlyBannerView 值传递 init）+ :1503-1512
（ToastBarView 值传递 init）；`dataflow.md` §Isolating onChange
side-effect invalidation（`.work/xcode27-skills/swiftui-specialist/references/`，
skill 正本只读对表）；`ToastFaceTests.swift`（两面契约 + AX wiring 断
言——零 diff 红线锚）。

- **action**：
  1. **四 onChange 抽 ViewModifier**（T-M1a）：`PendingAIEnhanceModifier`
     （:266-271 消费逻辑逐行平移）/ `StackCommandModifier`（:276-284，
     gridModel 依赖经 init 参数传入）/ `ImportProgressModifier`
     （:322-345，taskRegistry/importAdapter 生命周期与 gridModel/
     inspectorModel 弱引用或闭包经 init 传入——:335-343 hoisted locals
     注记随迁）/ `ProjectURLChangeModifier`（:346-348）。宿主 body 对
     四观察的 `.onChange` 全部替换为 modifier 挂载；**消费语义逐行等
     价**（guard/Task/guard let 结构原样）。
  2. **双叶挂载**（T-M1b）：`ToastBarMount`（自读
     `@Environment(EditorState.self)` 的 `toast`，转发既有
     `ToastBarView(toast:)` 与 `.animation(value:)`）+
     `ReadOnlyBannerMount`（自读 projectController 面，转发既有
     `ProjectReadOnlyBannerView(isReadOnly:holderPid:)`）。safeAreaInset
     双挂载点（:166-169/:179-182）原位保留，内容表达式换 Mount——
     **挂载方式零改**（§1.2 禁区）。既有值传递 init 零改动。
  3. **topBar 抽子 View**（T-M1c）：`WorkspaceTopBar` struct——窄输入
     `phase`/`projectName`/`isReadOnly`/`holdsControl` + 回调闭包
     （closeEditor/export/yiyin 等动作面）；:608 起私有 `topBar` 计算
     属性收编（保留同名转发或调用点替换）；isReadOnly ×3（:168 由
     Mount 承接 + :638/:653）与 holdsControl ×2（:639/:654）读收进
     topBar。AX identifier（shell.topbar.*）零改。
  4. **rebuildLibrarySurface 移 .task**（T-M1d）：:349-351 `.onAppear`
     摘除，调用并入 :355 起既有宿主级 `.task` 链（合并或并列新
     task——语义 = appear 后异步执行一次，时序差异走查覆盖）。
  5. 构建绿机检（caffeinate -dis 包裹）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 本任务恰一产线文件（WorkspaceHostView.swift）。
  - grep（review F-7 分组形——原交替式无分组括号时闭合 `\)` 只约束末分支、前三分支宽匹配）：`\.onChange\(of: (workspace\.pendingAIEnhance|workspace\.pendingStackCommand|projectController\?\.importProgress|projectController\?\.projectURL)\)` 在 WorkspaceHostView body 作用域零命中（四观察全部迁入 modifier）；`ToastBarMount|ReadOnlyBannerMount|WorkspaceTopBar` 各恰一处定义 + 挂载点替换；`.safeAreaInset\(edge: \.top|\.bottom` 双挂载点仍在（:166-169/:179-182 形核对）；`.onAppear` 内 `rebuildLibrarySurface` 零命中（移入 .task）。
  - **ToastFaceTests / WorkspaceRoutingTests / ProjectReadOnlyFaceTests / EditorStackRoutingTests 全绿**（`--bundle App` 定向过滤）；ToastFaceTests.swift 零 diff。
  - **LibraryProjectController.swift 零 diff**；focusedSceneValue :183 与既有 sheet 闭包段零 diff（`git diff` 逐 hunk 面核）。
- **commit**: `fix(ar01): isolate workspace host invalidation fans (audit M1)`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（宿主回原单边界
  形——行为面无差）；偏差（modifier 拆分粒度/Mount 命名/topBar 输入
  面/task 合并形态）= DECISIONS 申报，禁静默；若某 onChange 消费逻辑
  与 RESEARCH 行号表述有差 = 以函数体实际结构为准平移 + 申报；**禁为
  凑 grep 改语义结构**（guard/Task 结构原样是验收面）。

## T2 — M4：ContentView gate-false 臂失效下沉（ExportQueueRebuildModifier + InspectorPageMount；legacyBody byte-frozen 零触）

> **只动 gate-false 臂**（:175-241）；legacyBody（:248-418）逐字节
> byte-frozen——LANEB「legacyBody 拆子 View」建议在此行使为不采纳
> （D-M7-AR-3）。

**read_first**：`RESEARCH.md` §3 全节；`ContentView.swift` :170-247
（body 分叉 + gate-false 臂全形：.inspector :205-223 binding get 读
exportPageActive||filmPageActive / .focusedSceneValue :228-233 /
.onChange :238-240 → exportState.rebuildQueueForProject）+ :248-250
（legacyBody 起点标记）；`LibraryLegacyGateTests.swift`（gate 投影面
——零 diff 红线锚）；`WorkspaceRoutingTests.swift`（路由回归面）。

- **action**：
  1. **ExportQueueRebuildModifier**：:238-240 onChange 抽 modifier
     （projectController?.projectURL 观察 + exportState 闭包传入，
     `Task { await exportState.rebuildQueueForProject() }` 逐行平移）。
  2. **InspectorPageMount**（D-M7-AR-3 推荐行使）：.inspector（:205-223
     ——binding get 的 exportPageActive||filmPageActive 呈现耦合读）+
     .focusedSceneValue（:228-233）+ ExportQueueRebuildModifier 挂载
     整段下沉进子 View struct——**根 body 只剩常量读 + WorkspaceHostView
     装配 + Mount 挂载**；exportPageActive/filmPageActive 变化不再重估
     根。binding set 腿（dismiss 双关、present no-op）逐行平移。
  3. **legacyBody 零触**：:248-418 逐字节零 diff（本任务 diff 面 =
     gate-false 臂 + 文件头注如有）。
  4. 构建绿机检。
- **验收标准（机检）**：
  - 构建绿；legacyBody byte-frozen 机检（review F-6——命令级判据非
    面核）：`diff <(git show HEAD:App/Sources/Lightamer/UI/ContentView.swift | sed -n '248,418p') <(sed -n '248,418p' App/Sources/Lightamer/UI/ContentView.swift)`
    要求零输出；辅以 `git diff -U0 App/Sources/Lightamer/UI/ContentView.swift`
    确认全部 hunk 归属 gate-false 臂（:248-418 段零 hunk）。
  - grep：`ExportQueueRebuildModifier|InspectorPageMount` 各恰一处定
    义；gate-false 臂 body 作用域 `.onChange\(of: projectController\?\.projectURL\)` 零命中（迁入 modifier）；`.focusedSceneValue\(\\\.exportPanelRequest` 求值路径仍在（下沉后于 Mount 内——路径改变 = 禁区违反，面核确认仅挂载宿主变化、求值内容零改）。
  - WorkspaceRoutingTests / LibraryLegacyGateTests 全绿且两测试文件零 diff。
  - **LibraryProjectController.swift 零 diff**。
- **commit**: `fix(ar01): sink contentview gate-false side effects (audit M4)`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（Mount 拆分
  形/binding 载体形态）= DECISIONS 申报；**禁触 legacyBody**（发现任
  何 legacyBody 面 diff = 停手上报——byte-frozen 纪律）；**禁改
  focusedSceneValue 求值内容**（仅挂载宿主可变——禁区①）。

## T3 — M5：Film/Drt 面板节级拆分（子 View struct + m11 惰性建 + m2②③ 缓存 + m9 本地化 + o9 顺路）

> **拆分 = 独立失效边界**（structure.md §Always use separate View
> types）；D-H1 提交语义与 KD-3 三级读零改（o1/o5 豁免正本）；
> scopes 面零触；条件分支形态保持（不新增条件卸载）。

**read_first**：`RESEARCH.md` §4 全节 + §9 m2/m9/m11/o9 行；
`FilmPanelView.swift` :23-57（body）+ :49-51（onAppear 惰性建定式——
m11 对齐锚）+ :61-594（header/enableEntry/sessionControls/latitude
Section/placementSection private var 节 + :339 verbatim 拼接 + :442
Stepper + :498-509 String(format:) 读出行）；`FilmPanelModel.swift`
:117-130（solveReadout——勘误①：FilmTailPolicy.swift:629 已有
FilmSolveCache consult，**零代码注记级**）+ :330-345（placementTarget）；
`DrtPanelView.swift` :23-30（init State(initialValue:)——m11）+ :32-48
（body ForEach sections 分派）+ :52-313（methodCard/encodingGroup
含 peakRow D-H1 三件 :124/limitingGroup/presetGroup）；`DrtPanelModel.swift`
:90-92（isCustomLook）；`EditorAdjustmentStackView.swift` :135-136
（o9）；`DrtPanelModelTests.swift`（既有面板模型测试面）；AGENTS.md
M3-1 KD-3 / M2-6（D-H1 三件套 + 三级读正本）。

- **action**：
  1. **Film 三节拆分**：`SessionControlsView`（sessionControls 节）/
     `LatitudeSectionView`（latitudeSection + 直方图 Canvas + share
     readout + notes）/ `PlacementSectionView`（placementSection）——
     各持 `let model: FilmPanelModel` 类引用 + 各自窄读；绑定链逐行
     平移（live tick→setLive、dragEnd→commit 零改）。
  2. **Drt 四节拆分**：`DrtMethodCard` / `DrtEncodingGroup` /
     `DrtLimitingGroup` / `DrtPresetGroup`——`encodingExpanded` @State
     随 encodingGroup 子 View 迁移；peakRow（:124 D-H1 三件）随
     encodingGroup 平移。
  3. **m11**：DrtPanelView init :23-30 `State(initialValue:)` 摘除 →
     `@State private var model: DrtPanelModel?` + onAppear 惰性建
     （FilmPanelView :49-51 定式逐字对齐）；body 包 `if let model`。
  4. **m2②③ 缓存**：isCustomLook（DrtPanelModel :90-92）改按
     recordHash 键 stored 缓存（record 变更时失效——写点 = record
     setter/commit 路径，**commit 点零触**，缓存键计算与命中面新增）；
     placementTarget（FilmPanelModel :330-345）写点刷新缓存（层链变
     更写点失效）。缓存失效点选择 = DECISIONS 申报终形。
     **伪优化防线（review F-3）**：DrtPanelModel record 为 KD-3 三级
     computed 读（liveRecord → history → carrier，模型侧无 record
     setter——history/carrier 腿不存在写点失效钩子），缓存键**不得按
     读点计算 `record.stableHash()`**（单次 65 浮点 sorted-keys JSON +
     FNV 成本 ≥ 被缓存对象 `DrtPresets` struct `==` 的 ns 级比较 =
     伪优化降级）；DECISIONS 终形申报须附**单次读成本对比证据**，成本
     对比不成立 = 比照 m2① 降级为注记零代码（isCustomLook 计算成本
     本身可忽略）。
  5. **m9**：:339 `Text(verbatim: "\(label) \(pct)%")` 改单
     `String(localized:)` 格式键（latitude_share 族格式键 %lld/%@ 槽
     ——V14 静态键纪律，xcstrings 恰 +2..3 键尾块纯插入，键名终账
     DECISIONS 申报）；:498-509 三段 `String(format:)` verbatim 读出
     行改并排独立 `Text`（布局替代拼接，既有 latitude_readout_* 键
     零触零新键）。
  6. **o9 顺路**：EditorAdjustmentStackView :135-136 每 body 新建
     `InspectorEditSession` 下沉模型层（写点重建；量级豁免项顺路，
     独立验收让渡）。
  7. 构建绿机检。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰七文件（FilmPanelView/FilmPanelModel/
    DrtPanelView/DrtPanelModel/EditorAdjustmentStackView/xcstrings/
    本任务测试如落）。
  - grep：`State\(initialValue: DrtPanelModel` 零命中（m11）； Film/Drt
    面板内 `private var (sessionControls|latitudeSection|placementSection|methodCard|encodingGroup|limitingGroup|presetGroup)` 六节零命中（收编为子 View struct——Drt 的 methodCard 若保留为薄转发层 = DECISIONS 申报）；
    `String\(format:` 在 FilmPanelView :498 邻域零命中；verbatim 拼接
    :339 形零命中。
  - **scopes 面零 diff**；`if model.isPristine` 条件分支形态保持
    （diff 面核零新增条件卸载）；D-H1 绑定链零漂移（grep
    setLiveParams/commitFilmEdit/recordDrtChange/setFilmLive 绑定面
    与 pre-diff 一致）。
  - DrtPanelModelTests 全绿；Film 面板既有测试面（如有）全绿；
    ToastFaceTests 零 diff（跨任务红线持续核）。
  - xcstrings diff = 恰 +2..3 键尾块纯插入（历史键零触碰）；
    zh-audit --check + --self-test 双 PASS。
  - **LibraryProjectController.swift 零 diff**。
- **commit**: `fix(ar01): split panel sections and cache derived reads (audit M5)`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（面板回单边界形）；
  偏差（节拆分粒度/缓存失效点/键名与键数/ o9 让渡与否）= DECISIONS
  申报；**禁触 scopes 面**（发现 = 停手上报）；**禁改 D-H1 三段回调
  语义**（逐行平移是验收面）；**禁改 KD-3 三级读形态**（o5 豁免正
  本——发现缓存穿透到 record 读链 = 停手上报）；**m2② 伪优化判定成立
  （成本对比不成立）= 降级注记零代码并 DECISIONS 申报**（review F-3
  ——伪优化方向是「停手上报」护栏不覆盖的另一失败向，降级合法、硬上
  不合法）。

## T4 — M3：Filmstrip id 记账（visibleIDs Set<Int64> + row.id 直传 + firstIndex 消灭 + fixup stale-window 回归）

> **记账换 id、解析重建**（D-M7-AR-7）：正确性优先——idToIndex 每次
> refreshWindow O(n) 重建（10k 行 ~µs 级），指纹缓存挂后续优化；
> `pager.cellAppeared(at:)` 分页 API 不动（按 index 是设计内）。

**read_first**：`RESEARCH.md` §6 全节 + §9 m6 行；`FilmstripView.swift`
:44-45（visibleIndices）/ :66-74（warmWindow）/ :119-136（refreshWindow）
/ :169（disabled）/ :170-177（模型惰性建 + onDisappear）/ :194-203
（firstIndex 双处）；`LibraryGridView.swift` :119-123 + :166-170；
`LibraryGridModel.swift` :40（stackAdjacencyFixup——插行语义源，零
diff）+ :347（调用点）；`FilmstripModelTests.swift` 全文（:89/:96/
:141-142/:179-197 index API 改写面）。

- **action**：
  1. **FilmstripModel**：`visibleIndices: Set<Int>` →
     `visibleIDs: Set<Int64>`；`rowAppeared/rowDisappeared` 改 id API
     （`rowAppeared(id: Int64)` 形——或携 index 双参形 DECISIONS 申
     报）；`warmWindow` 解析 = refreshWindow 时 `idToIndex: [Int64:
     Int]` 字典重建（O(n) 每次，正确性优先）；`scrollAnchorID`/
     `select`/`listDisappeared`/`requestedIDs`/`prioritize` 面形态
     不变。
  2. **View 侧直传**：FilmstripView :194-203 双 firstIndex 反查摘除
     （`row.id` 直传）；LibraryGridView :166-170 cell onAppear 改
     `ForEach(grid.rows.enumerated(), id: \.element.id)` 携带 index
     ——`pager.cellAppeared(at:)` API 不动。
  3. **测试**：FilmstripModelTests 全量改写 id API（法数不变——既有
     index 驱动改 id 驱动，断言语义等价）；**新增 fixup 中插
     stale-window 回归 +1..3 法**：模拟 expanded 堆叠 fixup 中途插行
     （stackAdjacencyFixup anchor+1 insert 语义）→ 可见 id 集在插行
     后仍产正确 warm 窗 + 无 stale id 残留 + 请求计数不虚胖。
  4. 构建绿机检。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰四文件（FilmstripView/LibraryGridView/
    FilmstripModelTests/LibraryGridModel 仅头注如有——本体零 diff 预期）。
  - grep：`firstIndex\(where:` 在 FilmstripView/LibraryGridView 零命中
    （App/Sources 全域面核不误伤其它合法用途——以两文件零命中为判据）；
    `visibleIndices` 零命中；`visibleIDs` 恰一处声明。
  - FilmstripModelTests 全绿（改写 + 新回归）；**LibraryGridModelTests
    全绿**（stackAdjacencyFixup 行为零触旁证）。
  - FilmstripView :169 `.disabled(agentControl.holdsControl)` 逐字节
    保留（diff 面核）。
  - **LibraryProjectController.swift 零 diff**；Project.swift 零 diff。
- **commit**: `fix(ar01): account filmstrip visibility by row id (audit M3)`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（回 index 记账——
  病害一/二复活，无行为回归）；偏差（API 双参形/测试法数越带）=
  DECISIONS 申报；**禁改 pager.cellAppeared(at:) 签名**（分页按
  index 设计内）；**禁动 stackAdjacencyFixup 本体**（只读锚）；禁引
  入 idToIndex 指纹缓存（D-M7-AR-7 被否备选——发现 = 停手上报）。

## T5 — 定向轮 + D-6 探针硬门（M1/M4/M5 合并一次）+ GUI 走查配方 + 收口文档

> **D-6 探针 = 树形改动专用硬门**（§1.3；FIX2 T1 SC 判定式原文复
> 用）：本 plan M1/M4/M5 同批树形改动 → **合并复测一次**。全套
> `--all` 不强制（改动全 App 域，orchestrator 批准制）。

**read_first**：`RESEARCH.md` §7（验收形态三层）+ §1.3（探针义务）；
`FIX2-01-PLAN.md` T1 SC（CPU<10% 判定式 + 10-30% 未达标条款）+ :130
邻域（复现链配方）；`.work/gui-acceptance/v2m/`（D-6 复现链证据正
本）；`Scripts/test-direct.sh` 头注（bundle 划分与过滤形态）。

- **action**：
  1. **定向轮**：`caffeinate -dis Scripts/test-direct.sh --bundle App`
     全绿（M7-6 口径 917 法 + ΔN）。
  2. **D-6 探针硬门**：重开 ≥6 图项目 → 进入编辑器 → 静置 30s CPU
     机检 **<10%**（采样命令形钉死，review F-8：30s 窗内
     `ps -o %cpu -p <gui-pid>` 采样 ≥5 次、间隔 ≥5s 取中位 +
     `sample <gui-pid> 3` 一轮作栈旁证；**pid parentage 判别一行**
     随记录落 DECISIONS 探针记录节——探针对象 = GUI 实例，parent =
     launchd；test-direct 宿主 parent = 脚本进程树，AGENTS 资源监控
     口径/M2-7-3 先例；探针轮只应有 GUI 实例在跑）。10-30% = 未达标
     → 判别探针二轮迭代义务，禁放行 + 空载无项目面同口径记录 + 三铁
     条走查（编辑器 spin 消失 / filmstrip 点击换图出图 / 截图证据）。
     **若 A/B 并行且 plan B 已落盘 = 探针轮合并覆盖两 plan 树形改
     动**（D-M7-AR-6）。
  3. **GUI 走查**（配方落盘 MANIFEST，实机归验收批/用户）：toast 推
     入/清除、只读横幅显隐、import 进度条出现/收尾、项目切换四信号
     逐项目测；Film/Drt 面板逐滑杆拖动 60Hz 目测 + readout 刷新 +
     undo/redo 跳转 + 版本切换面板同步；File▸Export 菜单命令 →
     Export 页打开/关闭 + film 页双关 dismiss；filmstrip 展开堆叠 →
     滚动 → 请求计数不虚胖（requestCount 机检面）；m9 readout 并排
     布局目测。
  4. **全套 --all（可选，批准制）**：若 orchestrator 批准 = 运行中保
     持监视 + 8G 门 + MEMFAIL 机检；A/B 并行窗口内持
     `/tmp/la-audit-repair-all.lock` 串行（CONTEXT 编排总纲）。
  5. **SUMMARY + DECISIONS 落盘**（逐任务 ΔN 记账 + 各任务偏差终形 +
     xcstrings 豁免申报 + m9 键数终账）+ MANIFEST 落盘
     `.work/gui-acceptance/audit-repair/MANIFEST.md`（AR-01 节）。
  6. 汇报 + **C 档停**（执行+验收闭环后停，等用户确认再放行 plan
     B/C）。
- **验收标准（机检）**：定向轮绿 + 探针硬门记录（CPU 数值 + 命令 +
     三铁条证据路径）落 DECISIONS + MANIFEST 在库 + SUMMARY ΔN 对账
     表（3963+ΔN 带 3964..3970——review F-1）。
- **commit**: `test(ar01): run app suite, d6 probe gate, and walkthrough manifest`
- **回滚与偏差申报要求**：探针门未达 = 本 plan 树形改动归因排查（逐
  任务 revert 二分），修复后复测，禁放行禁静默；定向轮任何 fail =
  先归因（本批 Δfiles 窗内?）——窗外 fail = 既有缺陷停手上报；
  MEMFAIL = 立即 kill + 上报。

---

## 风险与回退

- **M1 modifier 依赖传递面**：ImportProgressModifier 需携带
  gridModel/inspectorModel/taskRegistry——弱引用或闭包注入形若引入循
  环持有/生命周期差 = DECISIONS 申报注入终形；消费逻辑逐行平移是回
  归底线（WorkspaceRoutingTests 等）。
- **树形变化跨 threshold**：树规模降低是 churn 燃料面减量（良性方
  向），但 M1/M4/M5 任意一件可能意外跨越 D-6 threshold——探针硬门是
  唯一裁决面（未达 = 停，禁放行）。
- **M5 拆分 SwiftUI 等价性**：子 View struct 化后 @State（encodingExpanded）
  迁移与 DisclosureGroup 交互等价性走查确认（面板展开态跨重估保持）。
- **M3 id 记账与 List 行 identity 对齐**：改写后 warm 窗语义与
  onAppear/onDisappear 触发序的等价性靠 fixup stale-window 回归 +
  走查双证；若 List 虚拟化行为与模拟差异 = 回归法补真滚动驱动腿
  （DECISIONS 申报）。
- **xcstrings +2..3 键观感**：m9 格式键 zh 语序变化（「以下 43%」可
  表达）= 预期行为改进非缺陷；MANIFEST 观察行登记。
- **A/B 并行文件面**：本 plan 与 plan B 文件零交集（唯一共享依赖
  LightamerSlider 只读）——若发现对方域文件入本批 diff = 停手上报
  （并行纪律破坏信号）。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：B 路 M1/M4/M5/M3 四 major ↔ T1-T4 逐项映射 +
   m2②③/m6/m9/m11/o9 五顺路项落位无孤儿；RESEARCH §0.1「四条大件拆
   分/缓存方案已定」↔ 本 plan SC 覆盖。
2. **OQ 兑现核**：D-M7-AR-2（T1 四件 + 不做 sheet 重排）/ D-M7-AR-3
   （T2 gate-false only + legacyBody 零 diff 面核）/ D-M7-AR-4（T3
   节级 + 不动清单四件）/ D-M7-AR-7（T4 重建式 + pager API 不动）/
   D-M7-AR-6（T5 三层 + 合并探针）。
3. **D-6 禁区八面核**：menus/focus 零触（:183/:287-288/:228-233 挂点
   diff 面核）/ 双 safeAreaInset 挂载形 / .inspector 形态 / 三段内
   容段数 / 探针硬门执行记录 / AX 轻用 / o6 不动 / legacy 燃料面零触。
4. **byte-frozen 双面**：legacyBody :248-418 零 diff + ToastFaceTests
   零 diff；FIX2③ = LibraryProjectController 零 diff（三任务持续核）。
5. **D-H1/KD-3/scopes 零漂移**：T3 绑定链 grep 面核 + scopes 面 diff
   零 + 条件分支形态保持。
6. **M3 语义面**：pager.cellAppeared(at:) 签名零改 + stackAdjacencyFixup
   本体零 diff + FilmstripView:169 disabled 保留 + 新回归法 ≥1。
7. **SC 可机检性**：每条 SC 有命令级判据（grep / diff 面核 / 定向轮
   / 探针 CPU 数值），非「目测」；ΔN 对账式非死数（带 3964..3970——review F-1）。
8. **登记纪律**：xcstrings 恰 +2..3 键尾块纯插入 + zh-audit 双 PASS +
   UserDefaults 零新键 + Project.swift/BUNDLE-MAP 零 diff +
   `.runModal(`/插值禁形零命中。
9. **C 路并入**：执行前合并 MANIFEST 亲读一轮记录 + 基线重算核对
   （红线条款兑现——review F-9）。
10. **编排**：C 档停位兑现（T5 闭环停汇报）；--all 批准制 + 锁串行。

---
phase: audit-repair
plan: "AR-03"
title: "plan C — 机械小件批（C 最后）：T1 软废弃 43 处（A 路 28 = overlay/background 尾闭包 15 + showsIndicators 3 + foregroundColor 1 + TextField onCommit 1 + coordinateSpace 1 + dropDestination 2 + menuStyle borderlessButton 5；B 路 m3 增量 = cornerRadius 14 + onChange 旧形 1）/ T2 minor 族（m1 AnyView 签名收紧 + m4 McpLauncher @Observable 迁移 + m5 CropOverlayHost @State private + m7 SettingsPages .task + m8 DateFormatter static let）/ T3 挂账 3 + 销账 8 登记 + 编译 + App 轮 + borderlessButton 5 处截图对比走查"
wave: 2
depends_on: ["AR-01", "AR-02"]
autonomous: true
requirements: ["审计修复批 charter：A 路软废弃 28 处 + B 路 minor 族可修项落线（正本 = .work/audits/xcode27-skills-2026-10/LANEA-FINDINGS.md §1.2 + LANEB-FINDINGS.md m1/m3/m4/m5/m7/m8 行）", "调研正本 = phases/audit-repair/RESEARCH.md §9 分诊表 + §10 切分（C 最后）+ §12 纪律", "OQ 裁决正本 = phases/audit-repair/AUDIT-REPAIR-CONTEXT.md（D-M7-AR-8 m10 挂账 + D-M7-AR-9 C 最后 + 销账 8/挂账 3 登记面）", "全套基线 3963/35/0；本 plan 带 +0..1 → 全批终值带 3963..3971", "C 最后理由（§10）：含观感改动（menuStyle 5 处 + m9 邻域复核）——A 的 D-6 探针门要求净基线，C 观感改动污染树形归因；走查一次定稿"]
success_criteria: "SC 全可机检——T1 软废弃批：43 处逐处清零（执行时先 grep 复核清单与 LANEA §1.2/B 路 m3 行号漂移——以符号形态为准落 DECISIONS 对账表）①overlay 旧重载 6 处 + background 旧重载 9 处 → 尾闭包形（grep `\\.overlay\\(` / `\\.background\\(` 旧 View 实参形逐处面核清零——ShapeStyle/`in:` 合法重载不误伤）②showsIndicators 3 处 → `.scrollIndicators(.hidden)`（grep `showsIndicators:` 零命中）③foregroundColor 1 处 → `.foregroundStyle`（grep `\\.foregroundColor\\(` App/Sources 零命中）④TextField onCommit 1 处 → `TextField(_:text:)` + `.onSubmit`（grep `onCommit:` 的 SwiftUI 形零命中——自定义回调类型 onCommit 不误伤）⑤coordinateSpace 1 处 → 新形（EditorNodesPanelView :273）⑥dropDestination 2 处 → DropSession 新形（SidebarView :709/:809——skill 正本对表替代签名）⑦menuStyle borderlessButton 5 处 → `.menuStyle(.button)` + `.buttonStyle(.borderless)`（grep `\\.menuStyle\\(\\.borderlessButton\\)` 零命中）⑧cornerRadius 14 处 → `clipShape(RoundedRectangle(cornerRadius:))`（grep `\\.cornerRadius\\(` App/Sources 零命中——清单 = MaskToolbarView ×11 :81/:170/:361/:378/:396/:446/:465/:483/:515/:530/:555 + SegmentEditingOverlayHost :224 + InstancePickerOverlay :70/:92，planner 实测勘误 B 路清单缺 :70）⑨onChange 旧形 1 处 → 双参/零参新形（McpLauncherPanelView :284，grep `\\.onChange\\(of:.*\\) \\{ _ in` 零命中）；T2 minor 族：m1 = EditorAdjustmentStackView row(for:) `AnyView?` → 具体 `InspectorRowView?`（:420-441 签名收紧，:440 AnyView 包装摘除——喂入面 :202/:212 ForEach 零改语义）+ m4 = McpLauncherPanelModel ObservableObject → @Observable + :174 @StateObject → @State（@Published ×7 直剥——仓内 30+ 模型既定形，最后一处）+ m5 = CropOverlayHost :80 `@State var preset` → `@State private var preset` + m7 = SettingsPages :377-381 改 `.task { await model.refresh() }` 删 loaded 旗标 + :682-686 同型 once-guard 冗余顺路清（sync load 留 onAppear 仅删冗余 guard）+ m8 = LibraryInspectorView :500-505 dateSpelling formatter 提 `static let` 缓存（dateFormat 直设面按 RESEARCH 保守口径维持——检索语法契约嫌疑，DECISIONS 核对消费方后终账）；T3：挂账 3 + 销账 8 正式登记（AR-03-DECISIONS）+ 构建绿 + `--bundle App` 定向轮全绿 + borderlessButton 5 处截图对比走查（FilterBarView :323 / PresetPanelView :98 / CatalogFilterBarView :253 / SoftProofControlView :66 / EDRControlView :58——唯一非逐字节等价面）+ m9 readout 布局复核行（m9 属 AR-01——C 走查复核一次定稿）+ MANIFEST/SUMMARY/DECISIONS 落盘"
estimated_tests: "+0..1（m1 签名收紧 / m4 迁移顺路单测可选 +1——纯机械批合法 ΔN=0；执行时如实记账）"
test_bundles: [APP]
baseline: "3963/35/0（M7-6 收口终态；叠加 plan A/B ΔN 后按累计口径对账——本 plan depends_on AR-01/AR-02 串行尾位）"
expected_all: "3963 + 累计 ΔN（对账式；本 plan 带 +0..1；全批三 plan 终值带 3963..3971；skip 35 口径维持；--all 批准制 + /tmp/la-audit-repair-all.lock 串行如逢并行残窗）"
red_lines:
  - "D-6 交互禁区（正本 = RESEARCH §1，三 plan 共用清单）：①menus/focus 形态零触碰——本 plan menuStyle 5 处改造仅换 style 形（.menuStyle(.button) + .buttonStyle(.borderless)），菜单内容/命令求值面/Commands 面零触；.focusedSceneValue 挂点零 diff。②threshold 承载面不得结构性增删。③本 plan 树形改动面 = 观感级（style 换形/尾闭包形）——非结构性树形改动，探针硬门不强制；若执行中发现某处改造引入结构性树变化（如 overlay 尾闭包形改变子层级身份）= 升级触发探针复测义务（停手上报 + 复测一次）。④AX 自动化轻用。⑤o6 LutPanelView 本批不动（挂 D-6 专项卷）。"
  - "disable-not-unmount 三纪律：零条件卸载新增；CropOverlayHost m5 仅加 private（零波及）。"
  - "FIX2③ = LibraryProjectController.swift 文件零 diff。"
  - "封存面零 diff（FIX2 红线族，三 plan 共用清单）：LightamerIOP/ 全域、*.metal 全域、LightamerSidecar、DrtRecord / TerminalTailPolicy / DrtTailAssembly / PixelPipe / Lut3dKernels.metal / DrtEotf / ExportQueueContract / 六格式导出矩阵 / NodeGraphCommand / HistoryStack / HistoryHash / PipelineDocument（Core）/ V50Order / GradeCatalog（NodeOwnershipCatalog）/ Registry / ModuleInstance。"
  - "xcstrings 零 diff（本 plan 零新键——与 AR-01 的 m9 豁免不同）；UserDefaults 零新键（KD-4）。"
  - "禁形机检：String.LocalizationValue(\"prefix_\\(x)\" 插值禁形零命中；.runModal( App/Sources 零命中（L057——m7 的 .task 改造零面板呈现面）。"
  - "观感改动申报面：borderlessButton 5 处 = 唯一非逐字节等价面（.menuStyle(.button) + .buttonStyle(.borderless) 观感近似非逐字节）——改造后 5 处截图对比步为验收面（MANIFEST 配方），观感差超预期 = DECISIONS 申报 + 该处回退评估；其余 38 处 = 机械等价改造（观感零差预期）。"
  - "dropDestination 新形对表纪律：替代签名以 skill 正本为准（.work/xcode27-skills/swiftui-specialist/references/soft-deprecated-apis.md——只读对表，禁凭模型先验写签名）；编译失败 = 回 skill 正本重对表，禁自造 API。"
  - "C 路并入条款（RESEARCH §11）：执行前必读周一合并 MANIFEST——C 路新 findings 按 CONTEXT §9 同款分诊并入本 plan（机械小件族天然落位本 plan）或追加 plan；C 路推翻 A/B 软废弃命中存疑项（如某处实为合法重载）以 C 路为准修正清单。"
  - "构建 caffeinate -dis 包裹；单测 = Scripts/test-direct.sh --bundle App；全套 --all 批准制 + /tmp/la-audit-repair-all.lock 串行（macOS 无 flock(1) 用 mkdir/fcntl/进程树探测等价——M7-6 验收先例口径）；测试宿主清理先核 parentage（ps -o ppid）。"
  - "Project.swift 零 diff（本 plan 零新测试文件——m1/m4 顺路单测进既有文件或 ΔN=0 让渡）。"
files_modified:
  - App/Sources/Lightamer/UI/FilterBarView.swift                   # T1：showsIndicators :189 + background :114/:218 + menuStyle :323（截图对比步①）
  - App/Sources/Lightamer/UI/CatalogFilterBarView.swift            # T1：showsIndicators :169 + background :198 + menuStyle :253（截图对比步③）
  - App/Sources/Lightamer/Library/Views/LibraryInspectorView.swift # T1：showsIndicators :180 + T2 m8：dateSpelling static let（:500-505）
  - App/Sources/Lightamer/Export/ExportNamingEditor.swift          # T1：TextField onCommit :182-184 → .onSubmit(commitRename)
  - App/Sources/Lightamer/UI/SessionBrowserView.swift              # T1：foregroundColor :541 + overlay :596 + background :649
  - App/Sources/Lightamer/UI/CatalogBrowserView.swift              # T1：overlay :336 + background :380
  - App/Sources/Lightamer/UI/SoftProofControlView.swift            # T1：menuStyle :66（截图对比步④）+ overlay :101
  - App/Sources/Lightamer/UI/EDRControlView.swift                  # T1：menuStyle :58（截图对比步⑤）+ overlay :82
  - App/Sources/Lightamer/UI/Inspector/PresetPanelView.swift       # T1：menuStyle :98（截图对比步②——UI/Inspector/ 域文件与 plan B 串行不冲突）
  - App/Sources/Lightamer/UI/Shell/Nodes/EditorNodesPanelView.swift # T1：coordinateSpace :273 新形 + overlay :612 + background :611
  - App/Sources/Lightamer/UI/SidebarView.swift                     # T1：dropDestination :709/:809 DropSession 新形 + background :417
  - App/Sources/Lightamer/UI/Inspector/CurveEditorView.swift       # T1：overlay :104 尾闭包形
  - App/Sources/Lightamer/UI/Inspector/LayersPanelView.swift       # T1：background :602 尾闭包形
  - App/Sources/Lightamer/UI/LightamerApp.swift                    # T1：background :552（自定义 View WindowCapture 实参）尾闭包形
  - App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift         # T1：cornerRadius ×11（:81/:170/:361/:378/:396/:446/:465/:483/:515/:530/:555——planner 实测清单，B 路原「等」展开）→ clipShape
  - App/Sources/Lightamer/UI/Overlay/SegmentEditingOverlayHost.swift # T1：cornerRadius :224 → clipShape
  - App/Sources/Lightamer/UI/Overlay/InstancePickerOverlay.swift   # T1：cornerRadius :70/:92 → clipShape（planner 勘误：B 路清单缺 :70）
  - App/Sources/Lightamer/UI/McpLauncherPanelView.swift            # T1：onChange 旧形 :284 双参/零参新形 + T2 m4：McpLauncherPanelModel :31 ObservableObject → @Observable + @Published ×7 直剥 + :174 @StateObject → @State
  - App/Sources/Lightamer/UI/Shell/EditorAdjustmentStackView.swift # T2 m1：row(for:) AnyView? → InspectorRowView?（:420-441 + :440 AnyView 摘除）——与 AR-01 T3（o9）串行不冲突
  - App/Sources/Lightamer/UI/Overlay/CropOverlayHost.swift         # T2 m5：:80 @State var preset → @State private var preset
  - App/Sources/Lightamer/Settings/SettingsPages.swift             # T2 m7：:377-381 .task { await model.refresh() } 删 loaded 旗标 + :682-686 once-guard 冗余顺路清
  - .work/gui-acceptance/audit-repair/MANIFEST.md                  # T3：走查配方（AR-03 节：borderlessButton 5 处截图对比步 + m9 readout 复核行 + cornerRadius/overlay 观感零差抽查行）
  - .work/gsd/phases/audit-repair/AR-03-SUMMARY.md                 # T3：执行摘要（43 处对账表 + ΔN 记账）
  - .work/gsd/phases/audit-repair/AR-03-DECISIONS.md               # T3：裁定记录（43 处对账 + 行号漂移面核 + 挂账 3/销账 8 正式登记 + m8 dateFormat 终账）
---

# Plan AR-03 — plan C：机械小件批（软废弃 43 处 + minor 族 5 项 + 挂账/销账登记）

> **裁决正本** = `AUDIT-REPAIR-CONTEXT.md`（D-M7-AR-8 m10 挂账 +
> D-M7-AR-9 C 最后 + 登记申报面）；规格正本 = `RESEARCH.md` §9 分诊
> 表 + §10 + §12；软废弃清单正本 = `LANEA-FINDINGS.md` §1.2（28 处
> 逐处 file:line）+ B 路 m3 行（cornerRadius ×14 + onChange ×1）。
>
> **清单纪律**：本 plan 头注与 files_modified 的行号 = planner
> 2026-10-13 HEAD `363117ee` 实测（cornerRadius 14 处全清单 + menuStyle
> 5 处 + onChange 旧形 1 处均 rg 实测过）——**执行时先 grep 复核行号
> 漂移，以符号形态为准**（行号仅定位辅助）；对账表逐处落 DECISIONS。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（43 处修法 = skill 正本替
> 代形机械对表；m8 dateFormat 口径 = RESEARCH 保守默认维持）。执行中
> 如触「必须扩面」（m10 复数变体入批〔D-M7-AR-8 晨审翻案情形〕/
> o6 LutPanelView 动 / 观感差超预期的 menuStyle 处回退争议 / 封存面
> 触碰）= 停手上报，不得自裁扩界。
>
> **执行序**：T1 → T2 → T3。depends_on = AR-01 + AR-02（C 最后）；
> T1 可按文件族拆 2-3 个 commit（overlay/background 族 + 软废弃杂项
> 族 + cornerRadius 族——每 commit 自洽），T2 独立 commit，T3 收口。
> Conventional Commits，全英文，只 add 相关文件，不 push。
>
> **基线**：**3963/35/0**（叠加 plan A/B ΔN 后按累计口径）；本 plan
> ΔN 带 +0..1 → **全批终值带 3963..3971**。

## ΔN 预算表（逐任务，合计带 +0..1；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 软废弃 43 处 | **0** | 纯机械 API 换形——回归靠既有 App bundle 面 + 走查 | 既有测试面 |
| T2 minor 族 | **+0..1** | m1 签名收紧 / m4 迁移顺路单测（可选——类型层断言）；纯机械批合法 ΔN=0 | 既有测试文件扩或让渡 |
| T3 登记 + 验收 | **0** | 挂账/销账登记 + 轮次 + 截图对比 + 收口文档 | — |
| **合计** | **+0..1** | 累计基线 → 全批终值带 3963..3971 | 全 APP 域；Project.swift 零 diff |

## 已定裁决（生效值，硬约束，不得重开）

1. **m10 xcstrings 复数 = 挂账**（OQ-8）：本 plan 零复数变体改动；
   晨审翻案（缩量修 ~5-10 键）= 追加 T 项再入批。
2. **挂账 3**：m10 / o4（翻译注释——开放翻译贡献时补）/ o6（
   LutPanelView `.id(libraryRevision)`——入 D-6 专项卷）。三件在本
   plan **零代码动作**，DECISIONS 正式登记。
3. **销账 8**：o1 / o2 / o3 / o5 / o7 / o8 / m2①（勘误降级注记）/
   m3 note-1/2/3（Font.system ×31 / GeometryProxy.frame ×1 / Stepper
   ×2——重载消歧大概率已落新臂，编译器无弃用警告，零行动）。DECISIONS
   正式登记（零代码）。
4. **m3 note 族零行动**：note-1/note-2/note-3 不入 T1 清单（43 处 =
   28 + 14 + 1，不含 notes 的 34 处深读面）。
5. **m8 保守口径**：只去分配项（static let）；`dateFormat = "yyyy-MM-dd"`
   直设面默认维持（ISO 定长检索语法契约嫌疑——plan 时核对消费方后
   终账，DECISIONS 申报）。
6. **C 最后**（OQ-9）：观感改动走查一次定稿——borderlessButton 5 处
   截图对比 + m9 readout 布局复核（m9 属 AR-01，C 复核）。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/audit-repair/AUDIT-REPAIR-CONTEXT.md`（D-M7-AR-8/9
  + 登记申报面 + 勘误）
- `.work/gsd/phases/audit-repair/RESEARCH.md` §9（分诊表逐行）+ §10
  （C 最后理由）+ §12（纪律核对表）
- `.work/audits/xcode27-skills-2026-10/LANEA-FINDINGS.md` §1.2（28 处
  正本清单）+ §1.3（note 族——零行动面）+ §1.4（误报类别——防复查
  翻车清单）
- `.work/audits/xcode27-skills-2026-10/LANEB-FINDINGS.md` m1/m3/m4/
  m5/m7/m8 行
- `.work/xcode27-skills/swiftui-specialist/references/soft-deprecated-apis.md`
  （替代签名正本——dropDestination/menuStyle/coordinateSpace 三族逐
  符号对表）
- `.work/config.toml [gsd]` paused/auto 开关（开工前亲核）

---

## T1 — 软废弃 43 处机械批（28 + 14 + 1）

> **替代形 = skill 正本对表**，禁凭先验；观感等价性分级——38 处机械
> 等价（overlay/background/scrollIndicators/foregroundStyle/onSubmit/
> coordinateSpace/dropDestination/cornerRadius/onChange 新形）+
> 5 处观感近似（menuStyle，T3 截图对比步）。

**read_first**：LANEA §1.2 全表（28 处 file:line 正本）+ B 路 m3 行；
`soft-deprecated-apis.md`（替代形正本）；本 plan files_modified 22
产线文件锚（planner 实测行号——执行时 grep 复核漂移）。

- **action**：
  1. **清单复核**：执行时 `rg -w` 逐族复核（showsIndicators /
     foregroundColor / onCommit / coordinateSpace / dropDestination /
     overlay 旧重载 / background 旧重载 / menuStyle borderlessButton /
     cornerRadius / onChange 旧形）——清单与行号漂移面核落 DECISIONS
     对账表；LANEA §1.4 误报类别（自定义 onCommit 回调 ×8 等）不误伤。
  2. **overlay/background 尾闭包形（15 处）**：6 处 overlay
     （SessionBrowserView :596 / CatalogBrowserView :336 /
     SoftProofControlView :101 / EDRControlView :82 /
     EditorNodesPanelView :612 / CurveEditorView :104）+ 9 处
     background（FilterBarView :114/:218 / SessionBrowserView :649 /
     CatalogFilterBarView :198 / SidebarView :417 /
     CatalogBrowserView :380 / EditorNodesPanelView :611 /
     LayersPanelView :602 / LightamerApp :552）——实参 View/Shape
     平移进尾闭包；ShapeStyle/`in:` 合法重载面零触。
  3. **杂项 8 处**：showsIndicators ×3 → `.scrollIndicators(.hidden)`
     （FilterBarView :189 / CatalogFilterBarView :169 /
     LibraryInspectorView :180）；foregroundColor ×1 →
     `.foregroundStyle`（SessionBrowserView :541）；TextField onCommit
     ×1 → `TextField(_:text:)` + `.onSubmit(commitRename)`
     （ExportNamingEditor :182-184）；coordinateSpace ×1 → 新形
     （EditorNodesPanelView :273——skill 正本对表）；dropDestination
     ×2 → DropSession 新形（SidebarView :709/:809——skill 正本对表
     替代签名，编译失败回正本重对表）。
  4. **menuStyle borderlessButton ×5**：`.menuStyle(.button)` +
     `.buttonStyle(.borderless)`（FilterBarView :323 / PresetPanelView
     :98 / CatalogFilterBarView :253 / SoftProofControlView :66 /
     EDRControlView :58）——观感近似非逐字节，5 处截图对比步归 T3。
  5. **cornerRadius ×14**：→ `clipShape(RoundedRectangle(cornerRadius: N))`
     （MaskToolbarView ×11 + SegmentEditingOverlayHost :224 +
     InstancePickerOverlay :70/:92）——圆角值逐处保持。
  6. **onChange 旧形 ×1**：McpLauncherPanelView :284 单参闭包 → 双参
     或零参新形（仓内 27 双参 + 2 零参先例形对齐）。
  7. 构建绿机检（caffeinate -dis 包裹）。
- **验收标准（机检）**：
  - 构建绿；grep 五族清零：`showsIndicators:` / `\.foregroundColor\(`
    / `\.menuStyle\(\.borderlessButton\)` / `\.cornerRadius\(` /
    `\.onChange\(of:.*\) \{ _ in` 在 App/Sources 零命中；
    `onCommit:` SwiftUI 形零命中（自定义回调类型不误伤——EditorAreaView/
    CropOverlayHost/LiquifyOverlayHost 自有 onCommit 面零 diff）；
    overlay/background 旧 View 重载形逐处面核清零（对账表）。
  - `git diff --stat` 恰本任务文件族（22 文件内 T1 面）；
    **LibraryProjectController.swift 零 diff**。
  - 既有 App bundle 面全绿（定向过滤涉改文件相关法）。
  - 自有回调/合法重载面零 diff（LANEA §1.4 误报清单逐条不误伤——
    diff 面核）。
- **commit**（按族 1-3 个，示例）：`chore(ar03): clear soft-deprecated overlay and background call sites` /
  `chore(ar03): migrate remaining soft-deprecated swiftui api call sites`
- **回滚与偏差申报要求**：回滚 = revert 族 commit（回软废弃原形——
  编译与行为零差，仅卫生债复活）；偏差（行号漂移实差 / dropDestination
  签名特例 / 某处实为合法重载被 C 路翻案）= DECISIONS 对账表逐处申
  报；**观感差超预期的 menuStyle 处 = DECISIONS 申报 + 回退评估**（
  禁静默保留差异面）；**禁顺手清 note 族**（note-1/2/3 零行动裁决）。

## T2 — minor 族五件（m1 / m4 / m5 / m7 / m8）

> 五件皆 RESEARCH §9 判「本批修（plan C）」；逐一独立可回滚，合一个
> commit（同域机械族）或拆二（m4 迁移独立——行为面最大件）。

**read_first**：`RESEARCH.md` §9 minor 表 m1/m4/m5/m7/m8 行；
`EditorAdjustmentStackView.swift` :189-227（row 消费面 :202/:212）+
:420-441（row(for:) AnyView?）；`McpLauncherPanelView.swift` :31-40
（ObservableObject + @Published ×7）+ :174（@StateObject）+ :284 邻域；
`CropOverlayHost.swift` :80；`SettingsPages.swift` :377-381 + :682-686；
`LibraryInspectorView.swift` :500-505（dateSpelling）+ 消费方 grep
（dateFormat 契约核对——m8 保守口径）。

- **action**：
  1. **m1**：row(for:) 返回类型 `AnyView?` → `InspectorRowView?`，
     :440 `return AnyView(view)` → `return view`；喂入面 :202/:212
     ForEach 零改（类型收紧后 SwiftUI 结构身份更精——行为保持走查）。
  2. **m4**：McpLauncherPanelModel `ObservableObject` →
     `@Observable`（@MainActor 对齐仓内 30+ 模型既定形）；`@Published`
     ×7 直剥（@Observable 逐属性跟踪）；:174 `@StateObject` →
     `@State`；消费面 `model.$xxx` 投影若有 → 直读适配（逐处面核）。
  3. **m5**：CropOverlayHost :80 `@State var preset` → `@State private
     var preset`（无外部初始化需求——编译绿即零波及证明）。
  4. **m7**：:377-381 `guard !loaded` + `Task { ... }` →
     `.task { await model.refresh() }`，删 loaded 旗标；:682-686 sync
     load 留 onAppear、once-guard 冗余顺路清（`guard !loaded` 摘除
     ——once 语义由 onAppear per-identity 天然承载）。
  5. **m8**：dateSpelling formatter 提 `static let` 缓存（DateFormatter
     非线程安全——本消费面入口单一即安全，DECISIONS 记线程入口单点论
     据）；dateFormat 直设面按保守口径维持。
  6. 构建绿机检。
- **验收标准（机检）**：
  - 构建绿；grep：`AnyView` 在 EditorAdjustmentStackView 零命中；
    `ObservableObject|@Published|@StateObject` 在 McpLauncherPanelView
    零命中且 `@Observable|@State` 在位；`@State private var preset`
    在 CropOverlayHost :80 在位；`loaded` 旗标在 SettingsPages :377
    邻域零命中。
  - `git diff --stat` 恰五文件（m8 与 T1 的 LibraryInspectorView
    showsIndicators 同文件——同批合并 diff 合法，对账表注记）。
  - **LibraryProjectController.swift 零 diff**；McpLauncherPanelView
    滚动视口/暂停行为走查零差（m4 迁移的行为敏感面——MANIFEST 观察行）。
  - 既有 App bundle 面全绿。
- **commit**: `refactor(ar03): tighten anyview row and observable model`
- **回滚与偏差申报要求**：回滚 = revert 族 commit；偏差（m4 迁移的
  消费面适配形态 / m8 dateFormat 若核对后判契约面改维持申报 / m7 的
  :682-686 让渡）= DECISIONS 申报；**m4 迁移后 objectWillChange 依赖
  面（若有）逐处核**——发现隐式依赖 = 停手上报（迁移语义差，非机械）。

## T3 — 挂账 3 + 销账 8 登记 + 验收（App 轮 + borderlessButton 截图对比 + 收口）

> **登记面**（零代码）：挂账 3 / 销账 8 正式落 DECISIONS（CONTEXT
> 登记申报面的兑现）；**观感验收**：borderlessButton 5 处截图对比步
> + m9 readout 复核行（走查一次定稿，§10）。

**read_first**：RESEARCH §9 分诊表全表（挂账/销账判语正本）+ §7.3
（走查面）；CONTEXT §登记申报（销账 8 明细 + 挂账 3）；
`gui-acceptance/v2m/` 先例形（MANIFEST 体例）。

- **action**：
  1. **AR-03-DECISIONS 落盘**：43 处对账表（执行时行号漂移面核终值）
     + 挂账 3 正式登记（m10/o4/o6——零代码动作 + 复活条件）+ 销账 8
     正式登记（o1/o2/o3/o5/o7/o8/m2①/m3 notes——各附豁免正本引语）
     + m8 dateFormat 终账 + C 路并入记录（合并 MANIFEST 亲读结论 +
     新 findings 分诊去向）。
  2. **定向轮**：`caffeinate -dis Scripts/test-direct.sh --bundle App`
     全绿（累计基线 + ΔN 对账）。
  3. **截图对比步**：borderlessButton 5 处改造前后截图对比
     （FilterBarView/PresetPanelView/CatalogFilterBarView/
     SoftProofControlView/EDRControlView 的菜单展开态——MANIFEST 配
     方逐处）；观感差超预期 = DECISIONS 申报 + 回退评估。
  4. **m9 readout 复核行**：Film 面板 latitude share/readout 布局目
     测（m9 属 AR-01——C 走查复核一次定稿）。
  5. **SUMMARY + MANIFEST 落盘**（AR-03 节：43 处对账 + 截图配方 +
     m4 McpLauncher 行为观察行）；全批 ΔN 终账对
     照（A +0..6 / B +0..1 / C +0..1 → 3963..3971）。
  6. 汇报（本 plan 闭环 + 全批终值 + 挂账/销账清单呈用户）。
- **验收标准（机检）**：定向轮绿 + DECISIONS/MANIFEST/SUMMARY 在库
  （grep 节标题）+ 43 处 grep 清零终态复核 + 全批 ΔN 对账表闭合。
- **commit**: `test(ar03): borderless menu screenshots and ledger registration`
- **回滚与偏差申报要求**：登记 = 纯 docs——revert 单 commit 即回滚；
  偏差（登记面增减/截图配方形）= DECISIONS 申报；**挂账件禁入批**
  （m10/o4/o6 零代码动作——发现任何挂账件产码 = 停手上报越 OQ-8/
  D-6 专项卷裁决）。

---

## 风险与回退

- **dropDestination 新形兼容**：DropSession 替代签名的行为面（isTargeted
  等价物）与旧 Bool-action 形若有语义差 = 走查 category/collection
  拖入行为（MANIFEST 观察行）；不可等价 = DECISIONS 申报让渡，禁静默。
- **menuStyle 观感漂移**：`.menuStyle(.button)` 与 borderlessButton
  观感近似非逐字节——5 处截图对比是唯一裁决面；个别处不可接受 = 回
  退该处并申报（软废弃卫生债可让渡，观感回归不可）。
- **cornerRadius → clipShape 布局差**：clipShape 不改布局（cornerRadius
  同）但越界绘制裁剪时序有细微差—— overlays 内部内容溢出场景走查抽
  查（MaskToolbarView 高密度文件）。
- **m4 迁移隐式依赖**：ObservableObject → @Observable 后任何
  objectWillChange/$投影 依赖 = 迁移语义差——逐处 grep 面核，发现 =
  停手上报。
- **C 路清单扰动**：周一合并 MANIFEST 可能增删本 plan 43 处清单——
  执行前亲读并以 C 路为准修正（对账表记录增删项）。
- **与 A/B 的串行依赖**：本 plan depends_on AR-01/AR-02——若 A/B 未
  闭环即启动 = 编排违规，停手上报。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：LANEA §1.2 28 处 + B 路 m3 17 处（cornerRadius
   14 + foregroundColor 1 + onCommit 1 + onChange 1）↔ T1 清单 43 处
   逐项映射（m3 的 foregroundColor/onCommit 与 A 路重叠项不双计——
   对账表核）；m1/m4/m5/m7/m8 ↔ T2 五件；挂账 3/销账 8 ↔ T3 登记。
2. **OQ 兑现核**：D-M7-AR-8（m10 挂账零代码）/ D-M7-AR-9（C 最后 +
   depends_on）/ 走查一次定稿（borderlessButton 截图 + m9 复核）。
3. **误报防翻车**：LANEA §1.4 清单（自定义 onCommit ×8 /
   onEditingChanged ×1 / accentColor 属性读 / onTapGesture 无
   coordinateSpace / SpatialTapGesture 无参 / CGColor(gray:) /
   NSColor.cgColor / LightamerColors surface）逐条零误伤（diff 面核）。
4. **note 族零行动**：note-1/2/3（Font.system ×31 / GeometryProxy.frame
   ×1 / Stepper ×2）零 diff（裁决 4 兑现面核）。
5. **红线核**：LibraryProjectController / 封存面 / xcstrings /
   UserDefaults / Project.swift 五面零 diff；禁形机检两零命中。
6. **SC 可机检性**：五族 grep 清零 + 对账表 + 定向轮 + 截图配方；
   ΔN 对账式（全批 3963..3971）。
7. **C 路并入**：合并 MANIFEST 亲读记录 + 新 findings 分诊去向逐条。
8. **编排**：depends_on 串行兑现（A/B 闭环证据在先）。

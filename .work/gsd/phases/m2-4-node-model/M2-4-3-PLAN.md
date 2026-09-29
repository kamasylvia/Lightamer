---
phase: m2-4
plan: "M2-4-3"
title: "节点面板 UI + phase 收口——SwiftUI Canvas 线性链自绘（纵向单列 Develop→Grade×N→DRT，卡片=真 SwiftUI 视图原生命中、Canvas 只画连线）+ 拖卡插入重连 + Fit；NodesPanelModel（订阅投影 + 选中写 selectedLayerID，P2 联动缝消费）；锁定节点三件套可复用 modifier；EditorToolRailView nodes 空态替换；zh 对账（nodes_*/history_graph_* 键族）+ 全套终跑 + REQUIREMENTS M2NODE 翻账"
wave: 3
depends_on: ["M2-4-2"]
autonomous: true
requirements: [M2NODE-06, M2NODE-02, M2NODE-04]
files_modified:
  - App/Sources/Lightamer/UI/Shell/Nodes/NodeCanvasGeometry.swift  # 新建（新目录 Nodes/ → tuist generate）：纯函数几何正本——纵向单列 layout（card/endpoint 尺寸常量 + 间距 + 居中）、insertionIndex(dragY:)（中点阈值）、fitScale(content:container:)（≤1）、edge endpoints（卡中心连线）
  - App/Sources/Lightamer/UI/Shell/Nodes/NodesPanelModel.swift     # 新建：@MainActor @Observable——PipelineDocument 投影订阅 + 选中态（写 editingState.selectedLayerID = P2 联动缝）+ 命令路由（EditorState.apply 薄转发）+ 锁定判定
  - App/Sources/Lightamer/UI/Shell/Nodes/EditorNodesPanelView.swift # 新建：面板本体——Canvas 连线层（只画线，无命中）+ 卡片层（真视图，原生命中）+ 拖卡重连手势（locked 不可拖）+ 上下文菜单（Rename/Toggle/Delete/Insert Before）+ mix 滑杆（D-H1 live/commit 腿）+ Fit 按钮 + 锁定三件套 modifier（可复用，M2-7 首组锁消费）
  - App/Sources/Lightamer/UI/Shell/EditorToolRailView.swift        # 修改：panel(.nodes) 空态 → EditorNodesPanelView（EditorRailPlaceholder struct 保留——versions 仍消费；history case 零 diff）
  - Resources/Localizable.xcstrings                                # 修改（T4）：nodes_* / node_lock_* / history_graph_*（P1 键族）/ editor_node_develop 等 zh 值对账补齐
  - Tests/LightamerTests/NodeCanvasGeometryTests.swift             # 新建：layout 单调/居中/常量 + edge 端点连接 + insertionIndex 阈值矩阵 + fitScale 边界（0/1 节点、超高内容）
  - Tests/LightamerTests/NodesPanelModelTests.swift                # 新建：投影发布 + 选中 → selectedLayerID 写入 + 命令路由正例 + 锁定判定（develop/drt 恒锁）+ 拖拽序 → reconnect 命令参数
  - .work/gsd/REQUIREMENTS.md                                      # 修改（T4）：M2NODE-01..06 → Delivered 翻账（逐条交付注记；签核 VALIDATION 归 verify-work 后置——C 档门控第 3 条）
  - .work/gsd/phases/m2-4-node-model/M2-4-3-SUMMARY.md             # 新建（收口任务）
  - .work/gsd/phases/m2-4-node-model/M2-4-3-DECISIONS.md           # 新建（收口任务）
  - .work/gsd/phases/m2-4-node-model/M2-4-ACCEPTANCE.md            # 新建（收口任务：phase 级 AC 汇总表——verify-work 输入正本）
  - .work/GOAL-STATE.md                                            # 续接点追加（收口任务）
  - .work/LESSONS.md                                               # 如踩坑
---

# Plan M2-4-3 — 节点面板 UI（Canvas 自绘线性链）+ phase 收口

> **性质**：纯 App 层 UI plan（Core 零改动——消费 P1 投影/命令 + P2 投影扩展）。把
> D-OQ-5-A 落成 `EditorNodesPanelView`：SwiftUI `Canvas` 画连线 + 真 SwiftUI 视图做
> 节点卡（命中测试免费）、纵向单列自动布局、Fit 恒定、拖卡重连；并做 phase 收口三件
> （zh 对账 / 全套终跑 / REQUIREMENTS 翻账）。规格锚点 = D-M2-4-CONTEXT-5/9/10/11 +
> REQUIREMENTS M2NODE-06 + FEATURE-MAP §1.3（EditorNodesPanel 操作面：Add/Rename/
> Delete/Connect/Fit + 锁定提示 `LockedNodeMaskPromptDialog` 语义）。
>
> **本 plan 的复用正本**：锁定三件套 modifier（锁形标记 + 删除拦截 + 提示文案）做成
> 可复用 view modifier——M2-7 Mask Groups 首组锁直接消费（CONTEXT Specific Ideas）；
> `NodesPanelModel` 的组序投影消费面留给 M2-7（P2 已钉数据语义）。

## 已定裁决（不得重开）

- **D-OQ-5（OQ-5 A）**：SwiftUI `Canvas` 自绘线性链图（Metal 无必要）；纵向单列
  Develop → grade×N → DRT；Fit 恒定；重连 = 拖节点卡到目标边（插入手势）。
- **D-OQ-7（OQ-7 A）**：Develop = base 投影（不可删/不可重连/恒图首/锁形标记）；
  DRT = 灰态占位端点 + 「DRT arrives with M2-6」文案；retouch 不上图。
- **D-OQ-6（OQ-6 A）**：mix = opacity 投影；面板**不露 blend mode**。
- **D-OQ-9（OQ-9 A）**：选中 grade → 七页签编辑该层（写入端 = `editingState
  .selectedLayerID`，P2 已验缝）；未选中/Develop = 全局链现行为。
- **D-OQ-10（OQ-10 A）**：失效传播零新机制（prefix 键既有）；多层链拖动流畅度 =
  观察项走查（非门）。
- **D-OQ-11（OQ-11 A）**：键随手 `String(localized:)`；本 plan T4 收口对账补齐。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 命中测试/拖拽几何答案：卡片 = 真视图，Canvas 只画线

- **分层**：`ZStack { Canvas(连线层); 卡片层 }`——连线用 `Canvas` path（卡中心到
  卡中心的垂直折线，`NodeCanvasGeometry.edges` 供端点），**Canvas 不承担命中**
  （v1 无连线交互）；节点卡 = 真 SwiftUI 视图（`.position` 布局），按钮/菜单/滑杆/
  拖拽手势全部原生命中——零手写 hit-test。
- **几何正本 = 纯函数**（Core 值无关，App 文件但零 UI 依赖，单测直调）：

```swift
enum NodeCanvasGeometry {
    static let cardWidth: CGFloat = 196          // 248pt 展开轨内留边
    static let cardHeight: CGFloat = 64
    static let endpointHeight: CGFloat = 44      // develop/drt 端点卡
    static let verticalSpacing: CGFloat = 18
    struct Layout: Equatable { let frames: [UUID: CGRect]; let order: [UUID]
        func center(of id: UUID) -> CGPoint; func edges() -> [(UUID, CGPoint, CGPoint)] }
    static func layout(for nodes: [PipelineDocument.Node], width: CGFloat) -> Layout
    /// 拖拽落点 → 插入序（grades 序内索引；相邻卡中点为界，拖出上下界钳制）。
    static func insertionIndex(dragY: CGFloat, in: Layout) -> Int
    static func fitScale(contentHeight: CGFloat, containerHeight: CGFloat) -> CGFloat // ≤1
}
```

- **重连手势**：grade 卡 `DragGesture(minimumDistance: 6)`（与 ScrollView 滚动共存：
  阈值起步，拖动中面板滚动锁定）——translation.y → `insertionIndex` → 插入指示线
  （Canvas 层高亮一条横线）→ 松手 `editorState.apply(.reconnectGrade(id:toPosition:))`
  （P1 命令；序 = **grade 序内索引**，不含端点）。develop/drt 卡不可拖（锁定判定）。
- **Fit**：`fitScale` = min(1, container/content)——内容不超高时 scale 1 + 无滚动；
  超高时缩放适配 + Fit 按钮重置。自由平移/缩放 = CONTEXT Deferred（v1 不做）。

### KD-2 NodesPanelModel = 投影订阅 + 选中写入 + 命令路由，图视图纯 dumb

```swift
@MainActor @Observable final class NodesPanelModel {
    private let editorState: EditorState
    private let editingState: LayerEditingState
    private(set) var document: PipelineDocument?   // layerStack 变更时重建（纯派生，KD-1/M2-4-1）
    private(set) var selectedNodeID: UUID?
    func select(_ id: UUID?)       // 写 editingState.selectedLayerID（grade → 层 UUID；
                                   //  develop/drt/nil → nil = 全局链现行为）
    func apply(_ command: NodeGraphCommand)  // editorState.apply 转发 + 错误 toast
    func isLocked(_ id: UUID) -> Bool        // develop/drt 恒锁（P1 投影 isDeletionLocked）
}
```

- **一致性维持答案（KD 必答）**：模型不缓存投影语义——`document` 是 `LayerStack` 的
  重建快照（每次 stack 变更重算，节点数十级成本可忽略）；选中态是模型唯一自有状态，
  写入端 = 既有 `selectedLayerID`（仲裁点单源，不立第二选中真相）。
- **mix 滑杆 = D-H1 live/commit 腿而非命令**（防 history 刷屏）：drag 变更走
  `applyLiveLayer`（零 history）+ drag end `commitLayerEdit(label: history_graph_mix)`
  （恰一条）——与 06-05 属性编辑同款；**SetMix 命令仍经 `NodeGraphCommand` 保留**
  （菜单/快捷路径/未来批量消费），滑杆只是其 live/commit 化身（数学等价已由 P1
  AC「SetMix(0) ≡ bypass」钉死，opacity 即 mix）。

### KD-3 节点卡信息面 + 交互表（Alcedo 操作面对齐）

| 卡类型 | 内容 | 交互 |
|---|---|---|
| Develop（端点） | 「Develop」+ RAW 徽标 + 锁形标记 | 不可拖/不可删；点选 = 全局链 |
| Grade | 层名 + enabled 圆点 + mix % + mix 滑杆 + 锁形（未来） | 拖=重连；菜单=Rename/Toggle Enabled/Delete/Insert Grade Before；点选=该层 |
| DRT（端点，灰态） | 「Display Transform」+ 「DRT arrives with M2-6」+ 锁形标记 | 不可拖/不可删；点选 = 灰态提示 |

- **删除拦截**：菜单 Delete 仅对 grade 出现；locked 卡无 Delete 项 + 锁形点击 →
  toast（`node_lock_develop`/`node_lock_drt`，沿 Alcedo `LockedNodeMaskPromptDialog`
  语义文案自写，D-OQ-7）。
- **锁定三件套 = `NodeLockedBadge` + `.nodeLocked(intercept:)` modifier**（标记渲染 +
  手势禁用 + 提示回调三合一），泛化签名不带节点语义（M2-7 首组锁零改动复用）。
- **Rename** = alert + TextField → `.renameGrade(id:to:)`；**Insert Grade Before** =
  `.addCleanGrade(before: id)`；工具栏「+」= `.addCleanGrade(before: nil)`（栈顶）。
- **穷举纪律（checker 教训①）**：视图对 `NodeKind` 的 switch 穷举禁 default；
  `EditorRailSection.nodes` 的消费者触点全列 = `EditorToolRailView.panel(_:)` 唯一
  switch（T1 改造点）+ `EditorRailSectionTests`（如存在）grep 复核。

### KD-4 收口三件 = zh 对账 + 全套终跑 + REQUIREMENTS 翻账

- **zh 对账**：`Scripts/zh-audit.py --check` exit 0 为门；`nodes_*`/`node_lock_*`/
  `history_graph_*`（P1 七键族）/`editor_node_develop`/`editor_node_display_transform`/
  `editor_nodes_*` 逐键补 zh 值（`Resources/Localizable.xcstrings` 单文件）。
- **REQUIREMENTS 翻账**：M2NODE-01..06 逐条 Delivered 注记（格式沿 M2UIW/M2DIS 先例：
  交付面 + 锚点文件/测试 + plan 引用）；**VALIDATION/签核不在此做**（C 档门控第 3 条
  ——Phase 签核前停，verify-work 独立步）。
- **`M2-4-ACCEPTANCE.md`**：phase 级 AC 汇总表（三 plan AC 合并对照 + 终态测试计数 +
  观察项清单：拖动流畅度/30 节点 BENCH/滚动共存）——verify-work 的输入正本。

## read_first

1. `.work/gsd/phases/m2-4-node-model/M2-4-CONTEXT.md` OQ-5/7/9/10/11 + Specific Ideas
   （ViewModel/锁定 modifier 先行裁定）。
2. `.work/gsd/phases/m2-4-node-model/M2-4-1-SUMMARY.md` + `M2-4-2-SUMMARY.md`——投影/
   命令/groups 投影终形（本 plan 全部数据面消费签名以 SUMMARY 记录为准，禁凭记忆）。
3. `App/Sources/Lightamer/UI/Shell/EditorToolRailView.swift`——面板挂接点（`:135-140`
   nodes 空态 + `EditorRailPlaceholder` 保留面）。
4. `App/Sources/Lightamer/UI/Shell/EditorAdjustmentStackView.swift:262-278`——
   `activeLayerID` 消费面（选中 → 页签作用域的既有读端；本 plan 写端对接）。
5. `App/Sources/Lightamer/State/LayerEditingState.swift`——`selectedLayerID` 仲裁点 +
   viewport overlay 路由（选中 grade 的副作用边界：仅当不触发 overlay 冲突时置选中，
   实测确认 mask 编辑态互斥面零回归）。
6. `App/Sources/Lightamer/UI/Theme/ThemeTokens.swift`——七族 tokens（卡片视觉；
   裸 hex 禁令沿 M2-3-1 D1）。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits 全英文、≤72 字符祈使句、body
   what+why + 同批 md 清单）；只 add 申报文件；不 push；`.work/gsd/...` 真路径。
2. **构建纪律**：`caffeinate -dis` 包裹构建；T1 一次建齐 Nodes/ 三文件 + 测试 →
   `tuist generate` 一次，后续任务零新文件不重复跑。
3. **测试纪律**：单测 = `Scripts/test-direct.sh '<Class>'`（双读 L028）；基线 =
   M2-4-2 收口值（SUMMARY 记录）；**全套 = `Scripts/test-direct.sh --all` 七 bundle，
   跑前向 orchestrator SendMessage 报备**；RSS ≥8G = MEMFAIL 机检内置（SPIKE `70e09e5`
   8G 口径）；在案 flake 隔离复跑 ×3 归因。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
5. **架构红线**：`LightamerCore/` 零 diff（UI plan）；`EditorToolRailView` 只动
   `.nodes` case（history/versions 面零 diff）；裸 hex 禁令（ThemeTokens 单源，
   M2-3-1 AC 复跑口径：Shell/ 新目录 grep 仅 ThemeTokens 命中）；`REQUIREMENTS.md`
   只翻 M2NODE 族行（他族零 touch）；GPL 参考只读。
6. **收口核对**：T4 `git diff --stat` 与 front-matter 逐文件核对（checker 教训②）。

## Tasks

### T1 NodesPanelModel + 面板挂接（空态替换）+ 几何正本

- **read_first**：上列 2/3/6。
- **action**
  1. 新建 `Nodes/NodeCanvasGeometry.swift`（KD-1 全量：Layout/order/center/edges +
     insertionIndex + fitScale；常量集中文件头）。
  2. 新建 `Nodes/NodesPanelModel.swift`（KD-2 全量）。
  3. 新建 `Nodes/EditorNodesPanelView.swift`（骨架态：Canvas 连线 + 三类卡渲染 +
     点选选中；交互 T3 补全——本任务先立「图可见」）。
  4. `EditorToolRailView.swift`：`case .nodes: EditorNodesPanelView(model:)`
     （placeholder 移除该用法；`editor.nodes.placeholder` marker 退役，新 marker =
     `editor.nodes.panel`）。
  5. 新建 `Tests/LightamerTests/NodeCanvasGeometryTests.swift` + 
     `Tests/LightamerTests/NodesPanelModelTests.swift`：
     - 几何：layout y 单调 + 水平居中 + 0/1/N 节点 + edges 端点 = 相邻卡中心 +
       insertionIndex 阈值矩阵（卡间/卡上/出界钳制）+ fitScale（不超高=1/超高<1/零容器）。
     - 模型：投影随 stack 变更重建 + select 写 selectedLayerID（grade→UUID、
       develop/drt/nil→nil）+ apply 路由（真 EditorState 实例驱动断言）+ isLocked。
  6. `tuist generate`（新目录）。
- **验收标准**
  - [ ] 几何/模型断言全绿；`editor.nodes.panel` marker 在册。
  - [ ] EditorToolRailView history/versions 面 diff 零（逐 hunk 评审 m7）。
  - [ ] 全套回归 `0 fail`（基线 = M2-4-2 收口值）。

### T2 Canvas 连线 + 自动布局渲染 + Fit

- **read_first**：上列 2/6 + 本 plan KD-1。
- **action**
  1. `EditorNodesPanelView` 补 Canvas 连线层（`Layout.edges()` → path；线色 =
     `ThemeTokens` 族，禁裸 hex）+ `.position` 卡片层 + ScrollView 容器 + Fit 按钮
     （`fitScale` 应用）+ 插入指示线渲染位（T3 手势消费）。
  2. DRT 灰态卡（`editor_node_drt_placeholder` 键「DRT arrives with M2-6」）+ Develop
     端点卡常显。
  3. `NodeCanvasGeometryTests` 补渲染几何回归（30 节点 layout 计时 BENCH| 观察行，
     非门，落 SUMMARY）。
- **验收标准**
  - [ ] 三段链（develop+grades+drt）渲染帧几何与 Layout 逐项相等（预览快照断言或
        marker 几何读回，机检方式入 DECISIONS）。
  - [ ] Fit 边界断言绿；30 节点 BENCH| 行落 SUMMARY（节点数十级无虞的量化注记）。
  - [ ] 全套回归 `0 fail`。

### T3 卡片交互 + 拖卡重连 + 锁定三件套 + mix 滑杆

- **read_first**：上列 4/5 + P1 `NodeGraphCommand.swift` 签名。
- **action**
  1. 上下文菜单四项（KD-3 表）+ 工具栏「+」+ Rename alert。
  2. 拖卡重连手势（KD-1：阈值起步 + 滚动锁定 + 指示线 + 松手 `reconnectGrade`）；
     locked 卡禁拖。
  3. `.nodeLocked(intercept:)` 可复用 modifier（KD-3 三件套；泛化签名）。
  4. mix 滑杆（KD-2：applyLiveLayer/commitLayerEdit live-commit 腿）。
  5. `NodesPanelModelTests` 补：拖拽序 → reconnect 参数断言（insertionIndex 注入）+
     locked 拖拽拒发命令 + mix commit 恰一条 history item 断言。
- **验收标准**
  - [ ] 交互断言全绿（菜单路由/重连参数/锁拦截/mix 单条 history）。
  - [ ] 选中 grade → 页签作用域联动真缝验证（model 测试 + `activeLayerID` 读端
        既有测试全绿）。
  - [ ] 全套回归 `0 fail`。

### T4 收口——zh 对账 + 全套终跑 + 翻账 + phase AC 汇总

- **read_first**：本 plan AC 表 + 三 plan SUMMARY/DECISIONS + `Scripts/zh-audit.py`
  用例头。
- **action**
  1. zh 对账：`Scripts/zh-audit.py --check` → `Resources/Localizable.xcstrings`
     补齐（KD-4 键族全列）→ 复跑 exit 0。
  2. 全套回归终跑（`--all` 报备规矩；三 plan 测试增量合计入 M2-4-ACCEPTANCE）。
  3. `REQUIREMENTS.md` M2NODE-01..06 Delivered 翻账（KD-4；他族零 touch）。
  4. 落盘 `M2-4-3-SUMMARY.md`/`M2-4-3-DECISIONS.md`/`M2-4-ACCEPTANCE.md` +
     `.work/GOAL-STATE.md` 续接点（M2-4 完成，下一步 = M2-5 / verify-work 签核由
     orchestrator 裁）。
  5. `git diff --stat` 核对边界（纪律 6）。
- **验收标准**
  - [ ] zh-audit exit 0；全套 0 fail；翻账六条逐条在册；ACCEPTANCE 汇总表齐。
  - [ ] diff 边界 == 申报文件集。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 几何正本：layout 单调/居中 + edges 连接 + insertionIndex 阈值 + fitScale 边界 | NodeCanvasGeometryTests |
| 2 | 模型：投影重建 + 选中写 selectedLayerID 分支 + apply 路由 + isLocked | NodesPanelModelTests |
| 3 | 三段链渲染帧几何 = Layout（机检方式见 DECISIONS）+ Fit 边界 | T2 断言 + BENCH| 行 |
| 4 | 交互：菜单四项路由 + 拖卡 → reconnect 参数 + locked 拒发 + mix 恰一条 history | NodesPanelModelTests 补组 |
| 5 | 锁定三件套：develop/drt 锁形 + Delete 缺席 + toast；modifier 泛化签名（M2-7 可消费） | 视图 marker 断言 + DECISIONS 签名记录 |
| 6 | Rail 改造仅 .nodes case；`LightamerCore/` 零 diff；裸 hex 仅 ThemeTokens | `git diff` + `git grep -En '#[0-9A-Fa-f]{6}'` |
| 7 | zh 对账 exit 0；nodes/graph 键族 zh 值全在 | `Scripts/zh-audit.py --check` |
| 8 | 全套回归 0 fail，计数 ≈ P2 收口值 + 12..18 | test-direct.sh --all BUNDLE 行双读 |
| 9 | REQUIREMENTS M2NODE-01..06 翻账在册；他族零 diff | `git diff .work/gsd/REQUIREMENTS.md` 逐行 |
| 10 | diff 边界 == 申报文件集；ACCEPTANCE/SUMMARY/DECISIONS/GOAL-STATE 同批落盘 | `git diff --stat` 逐文件核对 |

## 风险与边界

- **Canvas 性能**：节点数十级（线性链典型 <10）帧成本可忽略（D-OQ-5）；30 节点
  layout BENCH| 观察行量化兜底；真机拖动流畅度 = 走查观察项（D-OQ-10，非门），
  不达标后备 = 布局缓存（`Layout` 按 stack hash memo）——零语义风险。
- **拖拽手势与 ScrollView 滚动冲突**：`minimumDistance` 阈值 + 拖动中锁滚动双保险；
  手感 = Manual-Only 走查项（触控板/鼠标双输入），不达标调阈值常数（几何纯函数
  参数，不推倒选型）。
- **蒙版缺口字段与面板消费面**：本 plan 不消费 mask items（M2-7 Mask Groups 面板）；
  grade 卡上的蒙版徽标（有/无蒙版计数）可作低风险增量——仅读 P2 投影摘要，不立
  编辑面。
- **锁定 modifier 泛化不足**：M2-7 首组锁消费时若签名不合，演化 = additive 参数，
  本 plan 冻结的是三件套**语义**（标记/拦截/提示）非签名细节（DECISIONS 记录）。
- **`selectedLayerID` 副作用边界**：选中 grade 会激活页签作用域（期望行为）但不得
  触发 viewport overlay 抢占（LayerEditingState 互斥面）——T3 走查 + 既有
  LayerUIWiringTests 全绿为界。

## 提交约定

- T1 `feat(ui): nodes panel model with canvas geometry core`
- T2 `feat(ui): linear chain canvas rendering with fit`
- T3 `feat(ui): node card interactions with drag reconnect and lock modifier`
- T4 `docs(m2-4): close out node editing model phase with zh audit`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。

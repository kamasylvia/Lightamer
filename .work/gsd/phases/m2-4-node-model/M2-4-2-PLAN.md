---
phase: m2-4
plan: "M2-4-2"
title: "蒙版语义面 + 页签联动——MaskGroupItem.enabled/deletionProtected 语义激活（MaskCombiner 恒等元过滤 + Mask 页 clear 拦截）；Grade-owned 多蒙版只读访问面 + PipelineDocument maskGroups 投影（组序=grade 序，M2-7 数据语义钉死）；节点选中 → 七页签联动缝（EditorNodeHeaderView 动态名 + node(for:)/displayTitle 映射）。InspectorEditSession 层作用域实测已存在（盘点修正），只补写入端语义"
wave: 2
depends_on: ["M2-4-1"]
autonomous: true
requirements: [M2NODE-04, M2NODE-01]
files_modified:
  - LightamerCore/Sources/Layers/Masks/MaskSpec.swift      # 修改：item 访问面 additive——maskItems 只读视图（id/displayName/enabled/opacity/inverted）+ setItemEnabled/setItemDisplayName（值语义 struct，既有行零 diff）
  - LightamerCore/Sources/Layers/Masks/MaskCombiner.swift  # 修改：disabled item 恒等元过滤——enabled 项求值，空 enabled 集 = 恒 1 passthrough（kernel 零改动，装配前 CPU 侧过滤）
  - LightamerCore/Sources/Graph/PipelineDocument.swift     # 修改：maskGroups 投影（组序 = grade 序 = 层序，M2-7 Mask Groups 数据正本）+ node(for:) / displayTitle(for:) 选中映射
  - App/Sources/Lightamer/State/LayerEditingState.swift    # 修改：performMaskCommand .clear 腿 deletionProtected 拦截（mask=nil 写入点，typed 拦截 + toast）
  - App/Sources/Lightamer/UI/Shell/EditorNodeHeaderView.swift # 修改：节点名常量 → 选中态动态绑定（displayTitle 消费；develop=「Develop」/grade=层名/未选中=现行为）
  - Tests/LightamerTests/MaskItemSemanticsTests.swift      # 新建：combiner 恒等元矩阵（5 op × disabled 组合）+ 空 enabled 集 = 恒 1 + lock 拦截 + accessor round-trip
  - Tests/LightamerTests/PipelineLinkageTests.swift        # 新建：maskGroups 组序 = grade 序（reorder 后投影跟随）+ node(for:)/displayTitle 全分支 + item 摘要 parity
  - .work/gsd/phases/m2-4-node-model/M2-4-2-SUMMARY.md     # 新建（收口任务）
  - .work/gsd/phases/m2-4-node-model/M2-4-2-DECISIONS.md   # 新建（收口任务）
  - .work/GOAL-STATE.md                                    # 续接点追加（收口任务）
  - .work/LESSONS.md                                       # 如踩坑
---

# Plan M2-4-2 — 蒙版语义面 + 页签联动（M2NODE-04 数据/绑定面收口）

> **性质**：Core蒙版语义 + App联动薄层。P1 交付的 v5 字段（`MaskGroupItem.enabled/
> displayName`、`MaskSpec.deletionProtected`）在此**激活语义**（combiner/拦截/访问面），
> 并钉死 M2-7 Mask Groups 面板的数据语义（组序 = grade 序 + 组序命令 = Reconnect）。
> 规格锚点 = D-M2-4-CONTEXT-3/9 + REQUIREMENTS M2NODE-04 + FEATURE-MAP §3「蒙版绑定」+
> §1.3 Mask Groups 语境。**渲染管线零改动**（kernel 零新派发——过滤发生在 CPU 装配前）。

## 盘点修正（plan 期实测，修正 CONTEXT 表述——非重开裁决）

- **OQ-9「InspectorEditSession 扩层作用域」实态 = 已存在**：`InspectorEditSession
  (coordinator:layerScope:)`（`IOPPanelProvider.swift:60`）06-05 已落，且
  `EditorAdjustmentStackView.pageContent` 已按 `editingState.selectedLayerID` 注入作用域
  （`EditorAdjustmentStackView.swift:113,262-268`）。M2-4 真缺口 = **写入端**（选中节点 →
  `selectedLayerID`，P3 面板落）+ **header 动态名**（本 plan T2）。七页签面板本体零改动
  的裁决由此**天然满足**（该缝 06-05 就在）。
- **蒙版删除路径实态**：`MaskCommand.clear`（`LayerEditingState.swift:295-300`）= 唯一
  的 mask→nil 写入命令面；`deletionProtected` 拦截缝 = 该腿（全仓 mask 清除写入点 grep
  复核在 T1 action 内完成，触点全列入 DECISIONS）。

## 已定裁决（不得重开）

- **D3（OQ-3 A）**：多蒙版 = `MaskGroupSpec` 承载，字段面 P1 已落；本 plan 激活语义。
- **D6（OQ-7 A）**：首 Grade 删除锁 = baseLayer 结构性恒在；蒙版 spec 级
  `deletionProtected` 为 M2MASK-04 前置数据面，拦截语义本 plan 落。
- **D9（OQ-9 A）**：组序 = grade 序 = 层序；拖组排序（M2-7 UI）复用 Reconnect 命令——
  本 plan 用投影纯度证明（reorder 后 maskGroups 序跟随），不立新命令。
- **D8（OQ-11 A）**：新 UI 键随手 `String(localized:)`（header 动态名「Develop」等），
  zh 滞后，P3 收口对账。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 disabled mask 语义 = 恒等元过滤，空 enabled 集 = 恒 1

Alcedo 语义（FEATURE-MAP §4）：蒙版**限制** grade 的作用域；mask disabled = 该约束
不参与。据此定义（记录入 DECISIONS，M2-7 面板文案以此为准）：

- **求值域 = enabled 项**：`MaskCombiner` 装配前过滤 `item.enabled == false` 的项
  （CPU 侧，kernel/公式零改动——06-04 五式公式逐行保留）。dt 组合公式为 n-ary fold，
  丢弃 disabled 项对各 op 恒正确（union/sum 少一项、intersect 收窄变宽、difference/
  exclusion 少一个被减项——「不参与」语义逐 op 成立）。
- **空 enabled 集（全 disabled 或组空）= 恒 1 passthrough**（= nil mask 的 06-01 退化
  三元组通道）——「无活动约束 = 全图作用」，与单蒙版 disabled 时 grade 全图生效的
  Alcedo 直觉一致；**不是**恒 0（那会把 disabled 语义变成「禁用整个 grade」，与 mix/
  enabled 的节点级语义冲突，D5 分工）。
- **AC 机检**：5 op × {首项 disabled / 中项 disabled / 末项 disabled / 全 disabled} 的
  面积 golden 矩阵（06-04 解析面积 golden 先例同款）+ 全 disabled = 恒 1 逐字节。
- **执行顺序注记**：应用序保持既有 feather→invert→opacity→clamp（M2MASK-04 终态），
  enabled 过滤发生在**序之前**（不参与才谈应用）。

### KD-2 蒙版访问面 = MaskSpec 上的值语义 helpers（读写都对齐 group items）

```swift
extension MaskSpec {
    /// 组内蒙版只读视图（nil group / 空 forms = []）。id = item.formID。
    public var maskItems: [(id: UUID, name: String?, enabled: Bool,
                            opacity: Float, inverted: Bool)] { … }
    public mutating func setItemEnabled(_ id: UUID, _ enabled: Bool)
    public mutating func setItemDisplayName(_ id: UUID, _ name: String?)
}
```

- 多蒙版「列表」语义 = `drawn.group.items`（D3）——**不新增第二存储**；helpers 是
  M2-7 面板与测试的读写门面，写路径仍经 `EditorState.commitLayerEdit`（恰一条
  history item，既有的层属性提交腿原样）。本 plan 不立新命令枚举（蒙版 item 属性
  命令面 = M2-7 UI 落地时随面板立，YAGNI）。
- `displayName` nil = 派生名（「Mask N」序号），派生规则与 `LayerStack.nextLayerName`
  同款保守风格，纯函数可测。

### KD-3 maskGroups 投影 + 选中映射 = PipelineDocument 的两个纯派生（仍零状态）

```swift
extension PipelineDocument {
    public struct MaskGroup: Sendable, Equatable {
        public let gradeNode: Node
        public let masks: [MaskItemSummary]     // = KD-2 maskItems 投影
    }
    public struct MaskItemSummary: Sendable, Equatable { /* id/name/enabled/opacity/inverted */ }
    /// 组序 = grade 序 = 层序（D9 正本）；M2-7 拖组排序 = Reconnect 命令，投影自动跟随。
    public var maskGroups: [MaskGroup]
    /// 选中映射：nil = 未选中（nil 返回 develop 段语义由视图层裁）；
    /// drtNodeID → displayTransform；grade UUID → 该 Node；develop id → develop。
    public func node(for id: UUID?) -> Node?
    public func displayTitle(for id: UUID?) -> String   // 未选中 = 「Color Grade」现行为
}
```

- **组序一致性答案（KD 必答）**：`maskGroups` 与 LayerStack 的一致性 = 与 KD-1(M2-4-1)
  同款**纯派生零同步点**——`reorder` 后重新 init 即得新组序；测试钉「reorder → 投影
  跟随」而非任何双写。
- `displayTitle` 分支表（穷举，禁 default）：nil → 现常量「Color Grade」（未选中行为
  逐字节不变——M2-3-3 交付面兼容）；develop → 「Develop」（新键 `editor_node_develop`）；
  grade → 层名；drt → 「Display Transform」（新键）。EditorNodeHeaderView 只消费此函数，
  视图自身零分支逻辑。

### KD-4 deletionProtected 拦截 = Mask 页 clear 腿一处 + 全写入点审计

- 拦截缝 = `performMaskCommand(.clear)`：`mask?.deletionProtected == true` → 拒绝
  （toast + 零 history item）；false/nil → 现行为逐字节不变。
- **全写入点审计（checker 教训①）**：T1 执行 `git grep -n "mask = nil\|\.mask ="`
  `App/Sources` + `LightamerCore/Sources`，触点全列入 DECISIONS；`deletionProtected`
  拦截只落 `MaskCommand.clear`（命令面唯一清除入口），其余触点逐个定性
  （load 恢复/undo 复原 = 合法写入；其余如存在 = 审计结论记录，M2-7 再收）。

## read_first

1. `.work/gsd/phases/m2-4-node-model/M2-4-CONTEXT.md` OQ-3/OQ-7/OQ-9 + Reusable Assets 表。
2. `LightamerCore/Sources/Layers/Masks/MaskCombiner.swift` 全文——06-04 五式装配形态
   （过滤落点 + golden 面积测试先例）。
3. `LightamerCore/Sources/Layers/Masks/MaskSpec.swift:189-320`——group/items 冻结拼写 +
   P1 新字段 + stableHash 语义。
4. `App/Sources/Lightamer/State/LayerEditingState.swift:80-120,267-310`——MaskCommand
   全集 + performMaskCommand 分派（.clear 拦截缝）。
5. `App/Sources/Lightamer/UI/Shell/EditorNodeHeaderView.swift`——常量名现形（消费点改造）
   + `EditorAdjustmentStackView.swift:29-50`（header 挂接面）。
6. `.work/gsd/phases/m2-4-node-model/M2-4-1-SUMMARY.md`——P1 交付实态（投影/命令/v5
   字段终形）。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits 全英文、≤72 字符祈使句、body
   what+why + 同批 md 清单）；只 add 申报文件；不 push；`.work/gsd/...` 真路径。
2. **构建纪律**：`caffeinate -dis` 包裹构建；新建 .swift 同 commit `tuist generate`
   （本 plan 新文件仅测试两个 → T1 首任务 generate 一次）。
3. **测试纪律**：单测 = `Scripts/test-direct.sh '<Class>'`（Executed + failures 双读，
   L028）；**基线 = M2-4-1 收口值**（SUMMARY 记录，预估 2165+24 左右）；全套
   `--all` 跑前向 orchestrator SendMessage 报备；RSS ≥8G = MEMFAIL 机检内置。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
5. **架构红线**：kernel/Metal 文件零 diff；`MaskCombiner` 只许装配前过滤（五式公式行
   零语义改动）；`EditorAdjustmentStackView`/`InspectorEditSession`/24 面板本体零 diff
   （D9「面板本体零改动」）；`LayerEditingState` 只动 `.clear` 腿；新 UI 键
   `String(localized:)`（zh 可滞后）。
6. **收口核对**：收口任务 `git diff --stat` 与 front-matter 逐文件核对（checker 教训②）。

## Tasks

### T1 蒙版 item 语义激活（combiner 过滤 + 访问面 + lock 拦截）

- **read_first**：上列 2/3/4。
- **action**
  1. `MaskSpec.swift` 增 KD-2 helpers（additive；`setItem*` 找不到 id = 静默 no-op，
     值语义 struct）。
  2. `MaskCombiner.swift` 装配入口增 enabled 过滤（KD-1：求值域 = enabled 项；空集 =
     恒 1 通道走既有 degenerate passthrough 路径——实测该路径名并以 DECISIONS 记录）。
  3. `LayerEditingState.swift` `.clear` 腿增 deletionProtected 拦截（KD-4）。
  4. 全写入点 grep 审计（KD-4 触点表入 DECISIONS）。
  5. 新建 `Tests/LightamerTests/MaskItemSemanticsTests.swift`：5 op × disabled 位置
     面积 golden 矩阵 + 全 disabled = 恒 1 + 无组单形（disabled 单形 = 恒 1）+
     lock 拦截（protected 层 clear = mask 保持 + 零新 history item）+ accessor
     set/get round-trip + displayName 派生。
- **验收标准**
  - [ ] 恒等元矩阵 + 空 enabled = 恒 1 断言全绿；既有 MaskCombiner 族测试零改动全绿。
  - [ ] lock 拦截断言绿（mask 保持 + history 不动）；非 protected clear 行为不变。
  - [ ] 全套回归 `0 fail`。

### T2 maskGroups 投影 + 节点选中映射 + header 动态名

- **read_first**：上列 5/6。
- **action**
  1. `PipelineDocument.swift` 增 KD-3 三件（maskGroups / node(for:) / displayTitle；
     仍零存储状态——扩展只读计算属性与纯函数）。
  2. `EditorNodeHeaderView.swift`：常量名 → `displayTitle(for: editingState
     .selectedLayerID)` 动态绑定（environment 注入 EditorState/LayerEditingState；
     kind 副标题随 node.kind 切换；未选中渲染 = 现输出逐字节不变）。
  3. 新建 `Tests/LightamerTests/PipelineLinkageTests.swift`：maskGroups 组序 = grade 序
     + `reorder` 后投影跟随（D9 证明）+ item 摘要与 maskItems parity + node(for:)
     全分支（nil/develop/grade/drt/未知 id）+ displayTitle 四分支断言（未选中 =
     「Color Grade」现值）。
- **验收标准**
  - [ ] groups 组序/跟随 + 选中映射全分支断言全绿；displayTitle 未选中 = 现值。
  - [ ] `EditorNodeHeaderView` 未选中渲染零 diff（评审 m7：diff 仅消费点替换）；
        七页签面板族文件零 diff。
  - [ ] 全套回归 `0 fail`。

### T3 收口——SUMMARY/DECISIONS + 续接点

- **read_first**：本 plan AC 表 + `.work/GOAL-STATE.md` 续接点节。
- **action**
  1. AC 逐条机检 + 全套回归终跑（`--all` 报备规矩同 P1；计数入 SUMMARY）。
  2. 落盘 `M2-4-2-SUMMARY.md` + `M2-4-2-DECISIONS.md`（KD-1..4 确认 + 恒等元语义
     记录 + mask 写入点审计表 + 偏差归因）。
  3. `.work/GOAL-STATE.md` 续接点追加（M2-4-2 完成 + 下一步 = M2-4-3）；LESSONS 如踩坑。
  4. `git diff --stat` 核对边界（纪律 6）。
- **验收标准**
  - [ ] AC 表全绿；SUMMARY/DECISIONS/GOAL-STATE 同批落盘；边界无越界文件。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | disabled item 恒等元语义：5 op × 位置矩阵 + 空 enabled = 恒 1 | MaskItemSemanticsTests golden 面积矩阵 |
| 2 | deletionProtected 拦截：protected clear 拒绝且零 history item；非 protected 不变 | MaskItemSemanticsTests + 既有 MaskCommand 族零 diff 全绿 |
| 3 | 蒙版写入点审计表完整（grep 触点全列 + 逐个定性） | DECISIONS 审计表 + `git grep` 复跑 |
| 4 | maskGroups 组序 = grade 序；reorder 跟随（Reconnect 复用证明）；item 摘要 parity | PipelineLinkageTests |
| 5 | node(for:)/displayTitle 全分支；未选中 = 「Color Grade」现值逐字节 | PipelineLinkageTests + header diff 评审 m7 |
| 6 | kernel/Metal 零 diff；MaskCombiner 五式公式行零语义改动；面板族零 diff | `git diff --name-only` + 逐 hunk 评审 |
| 7 | 全套回归 0 fail，计数 ≈ P1 收口值 + 10..14 | test-direct.sh --all BUNDLE 行双读 |
| 8 | diff 边界 == 申报文件集 | `git diff --stat` 逐文件核对 |

## 风险与边界

- **MaskCombiner 装配形态未知数**：过滤落点以实测为准（read_first 2）；若装配在 GPU
  plan 侧无法 CPU 预过滤，回退 = disabled 项权重 0 注入（公式行仍零改动），DECISIONS
  记录选型；两形态 AC 同表。
- **空 enabled 集 = 恒 1 的语义争议**：本 KD 给出 Alcedo 对齐理由（约束 lifted ≠ grade
  禁用）；若晨审推翻，改常量与测试断言各一处，公式面零改。
- **displayName 派生稳定性**：派生名不入盘（nil 持久化），UI 层派生可随时改规则——
  与 sidecar 字节零耦合。
- **header 未选中行为回归**：M2-3-3 交付面（P4 走查 20 屏）以「未选中 = 逐字节不变」
  为硬 AC；选中态新呈现 = 增量面，走查挂 P3 收口批。

## 提交约定

- T1 `feat(core): honor mask item enabled and deletion lock semantics`
- T2 `feat(app): node selection mapping and dynamic node header title`
- T3 `docs(m2-4): close out plan 2 mask semantics and tab linkage`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。

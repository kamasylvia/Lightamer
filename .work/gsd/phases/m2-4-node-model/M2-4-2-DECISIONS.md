# M2-4-2-DECISIONS — 执行期裁定与审计（plan M2-4-2 收口批）

> 正位：`.work/gsd/phases/m2-4-node-model/M2-4-2-PLAN.md`（checker 修正版
> `c94aa3c`）的收口产物。KD-1..4 全部按 plan 落地（确认见下）；下列
> D-M2-4-2-N 为执行期新增裁定 / 签注，晨审可推翻（各条附翻转代价）。

## KD 执行确认

- **KD-1（disabled mask = 恒等元过滤，空 enabled 集 = 恒 1）**：照落地。
  过滤点 = `MaskCombiner.drawnGroupPlane` item 循环顶部一行
  `if item.enabled == false { continue }`（装配前 CPU 侧；五式公式与全部
  kernel 文件零 diff，`git diff --name-only` 核）。空 enabled 集 →
  `drawnGroupPlane` 返 nil → 走 `assembleUnmasked` 既有 **dt no-form fill-1
  leg**（该文件 `// nil group plane (no resolvable item) → dt's no-form
  fill 1 leg` 注记段落 → 末尾 constant-1 × opacity 兜底）——路径名实录如
  plan 要求。**不是恒 0**（禁用蒙版 = 约束解除 ≠ 禁用 grade，节点级
  enabled/mix 语义归 D-M2-4-CONTEXT-6）。测试：5 op × 首/中/末 disabled
  逐像素 Double 参考矩阵（<1e-6，参考折叠真实逐像素 plane 值，边缘像素
  覆盖）+ 双圆闭式面积锚（首/末 disabled 各 5 op）+ 全 disabled =
  逐字节 0.7 + 单项 disabled 组同通道。
- **KD-2（蒙版访问面 = MaskSpec 值语义 helpers）**：照落地。
  `maskItems` 只读视图（plan tuple 形状原样；`enabled` 折叠 nil→true；
  name 存储值原样透出 nil——派生在展示侧）+ `setItemEnabled`/
  `setItemDisplayName`（找不到 id / 无组 = 静默 no-op；top-level items
  only，嵌套 child 归 M2-7 组树 UI）。无第二存储：唯一列表仍是
  `drawn.group.items`。displayName 派生消费 Core 单源
  `LayerStack.nextLayerName(base:)`（测试钉序数+碰撞清扫，未重写第二份）。
- **KD-3（maskGroups 投影 + 选中映射 = PipelineDocument 纯派生）**：照落地
  （`maskGroups` 落法签注见 D-M2-4-2-3）。组序 = grade 序 = 层序由
  「reorder → 重新 init 即得新序」的纯函数性证明（测试钉投影跟随 +
  旧投影不动，零双写）。
- **KD-4（deletionProtected 拦截 = clear + fill 双腿 + 全写入点审计）**：
  照落地（checker E3 扩面忠实执行——`.fill` `:292` 与 `.clear` `:298`
  两腿同权拒绝：toast + 零 history item；非 protected 行为逐字节不变，
  `MaskCommandTests` 既有断言零改动全绿）。审计表见下节。

## 蒙版写入点审计表（KD-4 / checker 教训①；`git grep -n "mask = nil\|\.mask =" -- App/Sources LightamerCore/Sources` 全触点）

| 触点 | 写入形态 | 定性 | 处置 |
|---|---|---|---|
| `LayerEditingState.swift:292`（`.fill`，mask = 空 spec） | 蒙版内容清空（恒 1 passthrough，内容不可恢复） | **清空腿 #2** | **deletionProtected 拦截**（checker E3） |
| `LayerEditingState.swift:298`（`.clear`，mask = nil） | 蒙版记录移除 | **清空腿 #1** | **deletionProtected 拦截** |
| `LayerEditingState.swift:282`（duplicateAndInvert，mask = inverted 拷贝） | 内容变换（invert 位翻转，内容不丢失；写在新拷贝层上） | 合法 | 不拦 |
| `AIMaskEditing.swift:164`（segment bake，`updated.mask = mask`） | 内容生产（raster ref 换新，既有 payload 保留——注释明文 KEEP） | 合法 | 不拦 |
| `MaskOverlayHost.swift:387 / :403`（stroke live 腿，`MaskSpec(drawn: drawn)`） | 内容生产（form 追加/变形） | 合法（执行期观察见 D-M2-4-2-5） | 不拦 |
| `AdjustmentLayer.swift:73`（init 参数赋值） | 构造 | 合法 | 不拦 |
| `LayerStackSnapshot.swift:61`（snapshot 拷贝） | undo/复原载体的记录面 | 合法（恢复路径） | 不拦 |
| `SidecarLayerStack.swift:131`（decode 缺省 `mask = nil`） | load 恢复路径的记录缺省 | 合法（plan 明文「load 恢复 = 合法写入」） | 不拦 |

结论：命令面仅有 `.clear`/`.fill` 两个清空入口，与 plan 盘点修正一致；
拦截面闭合，其余触点全部内容生产/恢复类。

## 执行期裁定

### D-M2-4-2-1：T1 测试类拆两班（Swift 6 区域隔离）

plan 申报单文件单类。实测：`@MainActor` 类里本地创建的 `MTLTexture`
送入 async 装配函数触发 Swift 6 `SendingRisksDataRace`（MainActor 区域
→ nonisolated async 的发送报错；MaskCombineTests 能过正因其类 nonisolated）。
处置 = 同文件两班：`MaskItemCombinerSemanticsTests`（nonisolated，Metal 4
例）+ `MaskItemSemanticsTests`（@MainActor，App 状态/锁 5 例）。文件名
与登记行不变（BUNDLE-MAP 按文件计 9）；定向轮按类名两段过滤。
翻转代价：合并回单类 = 全部 harness 搬 nonisolated + 状态用例
`MainActor.run` 包裹。

### D-M2-4-2-2：displayTitle 落 Core 的 String(localized:) = M4 惯例显式豁免 + 「未选中恒等」本质是 KEY 恒等

- plan KD-3 明文把 displayTitle（含新键 `editor_node_develop`/
  `editor_node_drt`）放进 PipelineDocument（Core）——与 M2-4-1 M4
  「Core 不持本地化键」（nextLayerName base 注入）并存：M4 钦定面是
  **名字铸造缝**，displayTitle 是**展示面**，plan 有意为之，本批照办
  （Core 首个 `String(localized:)` 使用点；运行期经宿主 app
  Bundle.main 解析，zh catalog 实测生效）。
- **执行期发现（重要）**：「未选中 = 现常量 Color Grade 逐字节不变」的
  真身是 **KEY 恒等而非英文字面量**——zh catalog 已把 `editor_node_name`
  译为「调色」，zh 宿主上现行为渲染的就是「调色」。nil 分支复用同一键
  后，契约由测试以「同键同解析」断言钉死（`PipelineLinkageTests`
  testDisplayTitleCoversAllBranches 对照 `String(localized:...)` 同式），
  任何 locale 渲染零 diff。plan 的「Color Grade 现值」按此勘误读。
- 新 UI 键全集（4 个，zh 滞后挂收口对账，D-M2-4-CONTEXT-11）：
  `editor_node_develop` / `editor_node_drt` /
  `editor_node_kind_grade` / `editor_node_kind_drt`。

### D-M2-4-2-3：maskGroups 落 stored let（KD-3 签名 `var` 的落地形态签注）

KD-3 草图 `public var maskGroups: [MaskGroup]` 计算属性与「零存储纯派生」
在 Node 不携带 mask 的事实下不可兼得（computed 属性需持有 stack = 真存储，
且 LayerStack 非 Equatable 会破坏合成 ==）。落法 = `public let maskGroups`，
在 `init(_:)` 内与 grades 同批派生（zip(gradeNodes, compositeLayers)）——
与 `grades` 本身同构的「per-read 重建投影」，非缓存非同步点，头注门面
纪律（禁 var 缓存/身份字段）不破。Eq 面随之加宽（mask 差异进投影相等）
= 行为正确化。plan 签名以「属性访问语法不变」满足。翻转代价：改 computed
= Node 增 mask 字段（波及 Eq 面）或文档存 stack（违门面红线）。

### D-M2-4-2-4：maskItems「空 forms = []」门 + top-level only

`maskItems` 按 plan 明文：nil group / 空 forms → `[]`（无可栅格化展示的
项不上视图）；group items 全量投影（缺 form 的项不在此面过滤——记录视图
非渲染视图，combiner 侧已有 dt nb_ok 跳过）。setter 只寻址 top-level
items（嵌套 child 的 formID 是占位身份，归 M2-7 组树 UI）。plan 未言明
处按最窄实现，M2-7 若需 child 寻址再扩（YAGNI）。

### D-M2-4-2-5：执行期观察——MaskOverlayHost stroke 腿重建 MaskSpec 丢弃 sibling payload（非本 plan diff 面，M2-7 复核）

`MaskOverlayHost.appendForm/mutateForm`（:387/:403）以
`MaskSpec(drawn: drawn)` 重建 spec——parametric / raster /
deletionProtected 三个 sibling 字段被置 nil（Phase 6/07 既有形态：stroke
会话期 payload 本就 session-scoped）。当前无用户可达后果：
deletionProtected 是 runtime-only 字段（sidecar 载体缺口 = D-M2-4-1-3
挂 M2MASK-04），raster 腿有独立保 Payload 写点（AIMaskEditing）。登记
义务：**M2MASK-04 给 SidecarMaskSpec 补 deletionProtected 载体时，同批
复核 stroke 腿的 payload 保持**（修法候选 = `var spec = layer.mask ??
MaskSpec(); spec.drawn = drawn`）。本 plan 纪律（零越界）不许顺手修。

### D-M2-4-2-6：评审 m7 域勘误——header diff 含头注/环境声明，未选中渲染输出逐字节不变

AC「EditorNodeHeaderView 未选中渲染零 diff（diff 仅消费点替换）」按
实质核验：diff 面 = ①文件头注/结构体注释更新（文档）②两个
`@Environment` 声明 + `document` 计算属性（注入面，环境对象沿既有树
下发，无新 injection site）③两个 Text 消费点替换（`nodeTitle`/
`nodeKindLabel` 私有 helper，穷举 switch 无 default）。**未选中（或无
栈）路径两个 Text 的实参表达式与改前逐 token 相同**（同键同 defaultValue
的 `String(localized:)`），渲染输出逐字节不变；`EditorStackRoutingTests`
等既有族零改动全绿佐证。七页签面板族文件零 diff（`git diff --name-only`
核）。

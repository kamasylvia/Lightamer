# Phase M2-4: 节点编辑模型 — Context

> discuss/research 起草稿（2026-09-29）。规格锚点 = `research/ALCEDO-FEATURE-MAP.md` **§3 节点图模型**（PipelineDocument/图命令/所有权/蒙版绑定/C1 映射表）+ §2.1（18 目录与所有权）+ §1.3（Nodes 面板与 Mask Groups 语境）；需求 = REQUIREMENTS **M2NODE-01..06**。衔接面 = M2-3-3 交付的编辑器壳（`EditorTabRoute` 七页签 / `EditorToolRailView` Nodes 空态）+ Phase 6 adjustment layers 基础设施（LayerStack / LayerCompositeDriver / sidecar v4 / blendop 17 模式 / drawn mask 四形态 + MaskGroup shell）。**本 CONTEXT 面向夜间授权裁决**（文末「夜间授权预案」节：按推荐自主生效、晨审可推翻）。

## Phase Boundary

**范围**（ROADMAP M2-4 行 + M2NODE-01..06）：

1. **PipelineDocument 线性链语义**（M2NODE-01）——Develop → Color Grade×N → DRT；Develop = RAW→scene-referred；DRT = 显示终点（非 scene 端口）。
2. **图命令集**（M2NODE-02）——AddClean / Remove+Bridge / Reconnect / Rename / SetEnabled / SetMix(0-1) / InsertFromJson；undo/redo 可复原、保 NodeId。
3. **有序调整列表 + 所有权校验**（M2NODE-03）——顺序 = 用户数据编译器不得重排；18 项目录所有权面（Clarity/Sharpen/Halation/FilmGrain 属 DRT/Post，Grade 内插入 = typed error）。
4. **蒙版 Grade-owned 绑定**（M2NODE-04）——每 Grade 多蒙版独立 enabled/opacity/invert；首 Grade 删除锁。
5. **持久化 schema 扩展**（M2NODE-05）——sidecar/项目文件承载节点图（one-way 格式锁惯例）。
6. **节点面板 UI**（M2NODE-06）——图视图（Develop/DRT 端点 + Grade 节点 + 连线 + 增删改名重连 + Fit）SwiftUI/Metal 自绘。

**非目标（本 phase 明确不做）**：

- **18 项目录参数本体 / LGG 色轮 / CAT02 / ACEScc 域**（M2-5）——本 phase 只落**目录框架 + 所有权校验面**，不落参数模型与控件。
- **DRT 功能体**（M2-6）——DRT = 固定占位端点节点（灰态「DRT arrives with M2-6」）；ACES 2.0/OpenDRT 零涉及。
- **蒙版编辑 UI**（M2-7）——图上绘制/手柄 overlay/Mask Groups 面板归 M2-7；本 phase 只落蒙版**数据面与 Grade-owned 绑定面**。
- **mini-git 版本历史**（M2-8）——`.lalb` 四表（`edit_commit`/`version_ref`/`image_edit_state`/`pipeline_root`）保持注释占位（`LibrarySchema.swift:339,445-470` 明文「M2-4 must stabilize the edit pipeline FIRST; M2-8 then activates」——本 phase 只钉数据面，不碰迁移 seam）。
- **自由画布**——节点自由拖放定位/画布平移缩放不在 v1（线性链自动布局 + Fit 已满足 M2NODE-06 明文）。

## Existing Code Insights

### 关键语义发现（本 phase 方向裁决的地基，2026-09-29 Grep 实测）

1. **`LayerCompositeDriver` 是串行级联复合，不是平行叠加**——`LayerCompositeDriver.swift:75` 明文「layer sub-run (input = **C_prev**, roiHint = window)」：每层子链的输入 = **前一层复合输出**（composite prefix C_k，按键 `(owning layer, compositePosition)` 缓存，:93-97；输入累加器 accumulator 语义，GUI-21 修复注）。即 C_0 = base 输出 → L_k = chain_k(C_{k-1}) → C_k = blend(C_{k-1}, L_k)。**与 Alcedo grade 串行语义同构**：Alcedo `mix(p)` = lerp(in, graded(in), p)，而 normal blend + opacity p 的合成公式精确相等（lerp 即 alpha-over at opacity p over 同一输入）。→ 「layer 栈 = 节点链的持久化形态」方向**无需改任何复合语义**（OQ-1 依据）。
2. **`AdjustmentLayer` 字段与 Alcedo Grade 节点字段几乎一一对应**（`AdjustmentLayer.swift:28-56`）：`name`↔display_name、`enabled`↔enabled、`opacity`(0…1)↔mix、`chain: [ModuleInstance]`（有序记录，v50 排序 per sub-run）↔有序调整列表、`mask: MaskSpec?`↔masks。缺口仅两处：**删除锁字段**（`deletion_protected`）与 **mask 列表语义**（现单 `MaskSpec?` 壳，但 `MaskSpec` 内已有 `MaskGroupSpec`/`MaskGroupItem{formID, op: MaskCombineOp, inverted, opacity}`（`MaskSpec.swift:198-218`）——多蒙版 shell 06-03 已冻结）。
3. **sidecar 已到 v4，不是简报记忆里的 v2**——`LightamerSidecar.swift:121` `schemaVersionCurrent = 4`（v2 = typed `SidecarLayerStackRecord`、v3 = 五元数据字段、v4 = `provenance`；全部 decodeIfPresent additive + hash-isolation 判定 + 读者容忍 `schemaVersion > current` degrade）。M2NODE-05 的「升版本」起点 = **v4 → v5**，惯例正本就在该文件。
4. **`.lalb` 四表占位明文钦定激活序**——`LibrarySchema.swift:445-470`：「M2-4 (node model) must stabilize the edit pipeline FIRST; M2-8 then activates these through the KD-2 migrate seam」。当前 `.lalb` 只带 `has_edits`/`params_hash` 投影列，**`.lra` sidecar 恒编辑态真相**（架构红线）。
5. **Nodes 轨空态已钉本 phase 接缝**——`EditorToolRailView.swift:139` `"Nodes arrive in M2-4"`；七页签分派 = `EditorTabRoute.swift:29,109`（`EditorTabRoutingTable` 单一正本）；节点头 = `EditorNodeHeaderView`（现常量 "Color Grade" + EXIF 四腿，M2-3-3 交付）。

### Reusable Assets

| 资产 | 位置 | M2-4 复用判定 |
|---|---|---|
| `LayerStack`（baseLayer 恒在 + adjustmentLayers bottom-to-top + `replace`/`reorder`/`duplicate`/`remove` mutation API，NDE-1 UUID 身份） | `LightamerCore/Sources/Layers/LayerStack.swift` | **节点链真相源**——图命令集 = 其 mutation + history 的薄封装；baseLayer 无 remove API = `grade.primary` 删除锁的结构性保证 |
| `AdjustmentLayer`（字段对照见上） | `LightamerCore/Sources/Layers/AdjustmentLayer.swift` | **Grade 节点持久化形态**——补删除锁/mask 列表缺口走 additive |
| `LayerCompositeDriver`（1+N+1 串行复合 + composite prefix 键 + enabled=false 整层摘除 `:375` + blend-attribute/MASK 变更折进 prefix 键 `:160`） | `LightamerCore/Sources/Pipe/LayerCompositeDriver.swift` | **渲染语义零改动**——节点图是投影视图；失效传播消费既有键设计（OQ-10） |
| `BlendMode` 17 slot（dt rawValue 槽表，`normal=0x01`…`psColorBurn=0x2B`） | `LightamerCore/Sources/Layers/BlendMode.swift:92-129` | **超集保留**——Alcedo 只有 normal+mix；mix(p) ≡ normal + opacity p（OQ-6） |
| `MaskSpec` 族（drawn 四形态 frozen 06-03 + `MaskGroupSpec`/`MaskGroupItem{inverted, opacity, MaskCombineOp}` shell + parametric/raster/combine decodeIfPresent 惯例） | `LightamerCore/Sources/Layers/Masks/MaskSpec.swift` | **Grade-owned 多蒙版承载**（OQ-3）——item 级缺口（enabled/display_name/锁）additive |
| `HistoryStack` + `HistoryItem.layerScope`（层 UUID 作用域，D-H1 live ticks + commit leg） | `App/Sources/Lightamer/State/EditorState.swift:86-140` | **undo/redo 复原载体**——每图命令一条 history item；InsertFromJson = 复原快照 |
| `PipeCacheKey.layerID` / `compositePosition`（NDE-1 层 UUID 全线锚） | `LightamerCore/Sources/Pipe/PipeCacheKey.swift` | 节点身份 = 层 UUID（**不引入 Alcedo `grade.*` 字符串 id**——history/sidecar/cache 三线已是 UUID） |
| `EditorToolRailView` Nodes 空态 + 展开推挤 | `App/Sources/Lightamer/UI/Shell/EditorToolRailView.swift:139` | **面板挂接点**——空态文案替换为真节点图 |
| `EditorTabRoute`/`EditorTabRoutingTable` + `EditorNodeHeaderView` | `App/Sources/Lightamer/UI/Shell/` | **选中节点 → 页签联动**的既有分派面（OQ-9） |
| `EditorState`（@MainActor 单写者；`layerStack: LayerStack?` + history 双所有权） | `App/Sources/Lightamer/State/EditorState.swift:34` | 命令执行宿主——图命令与既有 D-H1 提交腿同批 |

### Integration Points

- **App/Core 边界**：节点模型/命令集落 Core（`LightamerCore/Sources/Layers/` 或新 `Graph/`，沿「sidecar 读写器放 Core」同款可单测原则）；App 层只消费命令面 + 投影视图。
- **七页签联动**：选中 Grade → `EditorAdjustmentStackView` 的 `InspectorEditSession` 需扩展层作用域（现 = 全局链作用域）。
- **`.lalb`**：`pipeline_root` 等四表零触碰；节点图状态不进项目文件（`.lra` 真相红线）。

## Open Questions（每条含推荐；夜间授权按推荐生效）

### OQ-1 映射核心：Alcedo Color Grade 节点 ↔ 既有 adjustment layer 的落地形态（必裁——决定整 phase 形状）
- **A（推荐）**：**layer = 节点的持久化形态，节点图 = LayerStack 的投影视图**——新建只读 `PipelineDocument` 门面类型（develop + grades(= compositeLayers 投影) + drt 占位）供图命令/面板消费；持久化**零迁移**（sidecar `layerStack` + base instances 原样承载）；图命令 = `LayerStack` mutation + `HistoryItem` 薄封装。依据 = 关键语义发现 1/2（串行级联 + 字段一一对应）；Phase 6 全部资产（复合驱动/缓存键/history layerScope/sidecar）原样复用。
- B：独立 `PipelineDocument` 持久化 + 与 LayerStack 双向同步——双真相源，违单一事实源（L 系列教训），同步一致性负担全在后续每个 phase。
- C：重建串行 runner（新执行器按 Alcedo 图直跑）——被发现 1 证伪：现有复合已是串行级联，重写零收益、全量回归风险。
**推荐 A**；`grade.primary` ↔ base layer 投影、UUID 身份保留（`grade.*` 字符串 id 不引入，仅在 UI 层可派生稳定显示标签）。

### OQ-2 图命令集语义对齐度（M2NODE-02：照抄 vs 简化）
- **A（推荐）**：**全套照抄 Alcedo 命令面**——AddClean(beforeID)（插 identity grade）/ Remove+Bridge（删层，链自动桥接 = 线性链上平凡）/ Reconnect（= 层重排位置）/ Rename / SetEnabled / SetMix / InsertFromJson（undo/redo 复原保 UUID）。命令面本就 7 条、每条对应一个明确 UI 手势，无简化收益；每命令 = 一条 `HistoryItem`（layerScope 既有），InsertFromJson 载荷 = 层记录 JSON 快照（沿 `paramsData` Data→base64 字节精确惯例）。
- B：v1 砍 InsertFromJson（undo 用逆命令）——逆命令在 Remove+Bridge（UUID 再生）下无法精确复原，违 M2NODE-02「保 NodeId」明文。
- C：加超集命令（如批量 move）——无 Alcedo 对应、无 UI 手势，YAGNI。
**推荐 A**。

### OQ-3 蒙版绑定：Grade-owned 多蒙版 vs 既有单 `mask: MaskSpec?`
- **A（推荐）**：**多蒙版 = `MaskGroupSpec` 承载，不重造第二套蒙版模型**——Grade 的 masks 列表语义映射为 `MaskSpec` 内 group form（`MaskGroupItem{inverted, opacity, MaskCombineOp}` 06-03 已冻结 shell，combine 语义 06-04 已落 `MaskCombiner`）；缺口字段（item 级 `enabled`/`display_name`、spec 级 `deletion_protected`）走 additive decodeIfPresent；`AdjustmentLayer.mask: MaskSpec?` 字段面不变。「每 Grade 多蒙版独立 enabled/opacity/invert」逐项对齐；首 Grade 删除锁 ↔ baseLayer 结构不可删（OQ-7）。
- B：`mask` 升级为 `[MaskSpec]` 数组字段——schema 破坏性变更（v2 frozen spelling 作废），违 one-way 锁。
- C：重构成 Alcedo `masks: [MaskModel]` 平行列表——丢弃 Phase 6 mask 资产（rasterizer/combiner/revision），M2-7 连带重写。
**推荐 A**。

### OQ-4 持久化：sidecar v4→v5 additive vs 零字段投影 vs 项目文件承载
- **A（推荐）**：**零字段投影优先 + 最小 v5 additive 兜底**——OQ-1-A 下节点图本身是派生物不落盘；仅当 plan 期证实 OQ-3 缺口字段确实缺失（item enabled/锁等）才升 **v5 additive**（`LightamerSidecar.swift` 惯例：decodeIfPresent + 读者容忍更高版本 + hash-isolation 判定逐字段过）。`.lalb` `pipeline_root` 零触碰（M2-8 迁移 seam 明文后置）；one-way 格式锁（永不迁移）延续。
- B：直接升 v5 引入完整「节点图序列化」块——节点图可派生却落盘 = 冗余真相，漂移风险。
- C：节点图状态进 `.lalb`（pipeline_root 表提前激活）——违 `LibrarySchema.swift:445` 激活序 + `.lra` 真相红线。
**推荐 A**；v5 是否触发、字段清单、hash-isolation 判定（结构字段不进 `HistoryHash.hash`，沿 v3 五字段先例）留给 plan 以实测缺口定。

### OQ-5 节点面板 UI 形态（M2NODE-06：Canvas 自绘 vs 列表先行；Alcedo = QuickQanava 画布）
- **A（推荐）**：**SwiftUI `Canvas` 自绘线性链图**——节点卡（SwiftUI 控件：图标+名称+enabled/mix 摘要）+ 连线（Canvas path）+ 自动布局（纵向单列：Develop → grade×N → DRT）+ Fit 恒定；增删改名经卡上菜单，重连 = 拖节点卡到目标边（插入手势）。线性链布局算法平凡（无自由图需求），QuickQanava 的自由画布能力用不上；「SwiftUI/Metal 自绘」读作 SwiftUI 自绘（Metal 无必要——节点数个位数，Canvas 帧成本可忽略）。
- B：简化列表视图先行（LayersPanel 复用改造）——违 M2NODE-06「图视图」明文，M2-7 Mask Groups 面板（组序=grade 序）也需要图式组卡先例。
- C：Metal 自绘整面板——过度工程，可访问性/命中测试全要手写。
**推荐 A**；落 `App/Sources/Lightamer/UI/Shell/Nodes/`（EditorNodesPanelView），Core 零 UI。

### OQ-6 mix(0-1) 与既有 blendop 17 模式/opacity 的关系
- **A（推荐）**：**mix = opacity 投影，零新字段**——数学等价已证（normal blend + opacity p ≡ mix lerp）；`SetMix(p)` 命令 = 写层 `opacity`。节点面板**不露 blend mode**（Alcedo 无此概念，IA 一致性；17 mode 保留为层模型超集，既有 sidecar 值不动不丢）。
- B：节点面板加 blend mode 选择器——超 Alcedo 功能面，v1 IA 偏离且 M2-7 Mask Groups 无对应呈现位。
- C：mix 独立字段与 opacity 并存——同值双字段 = 漂移温床。
**推荐 A**；`grade.primary`（= base layer 投影）mix 恒 1 不可调（OQ-7）。

### OQ-7 Develop/DRT 端点节点的固定语义 + retouch 层呈现
- **A（推荐）**：**三重固定 + retouch 不上图**——① Develop = base layer 投影：不可删/不可重连/恒图首端，其「调整列表」= 现全局链（RAW Decode/CIRAW 参数 + 现 33 op 过渡期宿主，M2-5 收窄语义届时另裁）；② DRT = 固定占位端点：不可删/不可重连、交互灰态 + 「DRT arrives with M2-6」，图拓扑上恒终点（scene 输入单端口语义照抄 Alcedo `drt_node_model.hpp:182-187` 注记）；③ `grade.primary` 删除锁 = baseLayer 结构性恒在（`LayerStack` 无 base remove API——已保证）+ 图上锁形标记 + 锁定提示（沿 Alcedo `LockedNodeMaskPromptDialog` 语义，文案自写）；④ retouch 层不进节点图（`compositeLayers` narrowing 已跳过；stroke 链语义独立，Alcedo 无对应物，Presentation 面归既有 retouch UI）。
- B：DRT 占位做成可删节点——删除后 M2-6 要重建端点，无收益。
- C：retouch 层上图显示为特殊节点——Alcedo 无对应、图语义污染（stroke 链非线性链）。
**推荐 A**。

### OQ-8 所有权校验面：18 目录未落（M2-5）前的过渡策略 + DRT/Post 四件占位
- **A（推荐）**：**框架先行 + 归属表落盘 + 宽限执行**——①目录注册表增 owner 维度（`.grade` / `.drtPost` / `.develop`），按 Feature-map §2.1 的 18 项归属先把**映射表落盘**（含现 33 op → 未来归属的对照：Grain→FilmGrain 位、Bloom→Halation 位等）；②校验 API + typed error（Grade 内插 `.drtPost` 项 = `NodeOwnershipError`，对齐 Alcedo `color_grade_node_model.hpp:29-34` 抛异常语义）；③**过渡宽限**：M2-4 时点 UI 新插受限，但已存 sidecar 加载宽容（degrade 不拒载——沿读者容忍惯例），M2-5 收窄 18 目录时激活严格执行。DRT 四件（clarity/sharpen/halation/film_grain）M2-6 前无实体，仅归属表占位 + instance id 命名约定预留（`drt.*` 语义注记，不建对象）。
- B：等 M2-5 一起做校验——违 M2NODE-03 明文（所有权校验是本 phase 交付物）。
- C：立即严格执行（已存文档拒载）——破坏非破坏性承诺，用户现存文档里 Grain/Bloom 在链中即拒载，不可接受。
**推荐 A**。

### OQ-9 与七页签栈的联动（选中节点 → 页签编辑该节点）
- **A（推荐）**：**会话层作用域扩展**——`InspectorEditSession` 增层作用域：Nodes 面板选中 grade → 七页签面板读写该层 `chain`（面板本体零改动，分派层注入作用域）；`EditorNodeHeaderView` 节点名从常量绑定为选中节点 name；未选中/选中 Develop = 现行为（全局链）。Mask Groups 面板（M2-7）数据语义在本 phase 钉死：**组序 = grade 序 = 层序**，拖组排序复用 Reconnect 命令（同一 mutation 两个 UI 面）。
- B：页签栈维持全局作用域、节点编辑仅经 Nodes 面板——「选中节点后面板编辑该节点」是 Alcedo 核心交互（`EditorAdjustmentHeader` 0.3.0），不做则 M2-5 控件集无落点。
- C：每节点独立页签栈实例——状态爆炸，history 作用域混乱。
**推荐 A**。

### OQ-10 节点图 UI 与 pixelpipe 的失效传播（drag 参数 → 下游失效，60fps 衔接）
- **A（推荐）**：**零新机制，消费既有键设计**——参数拖动 → 该层 chain `paramsHash` 变 → 该层 chain plane + composite prefix 失效（`LayerCompositeDriver.swift:160` blend-attribute/MASK 已折进 prefix 键）→ 下游层 C_k 输入变 → 级联重算（既有行为，PREVIEW 双级 busy + 帧稳定回调既有机制衔接）；图数据变更与像素失效解耦：Rename/重排仅动结构键（`compositePosition`），无 paramsHash 抖动；节点面板重绘 O(节点数) 无压力。观察项挂账验收走查（多层链拖动流畅度目测，沿 M2-3-4 E4 观察清单先例）。
- B：引入增量渲染（只重算受影响子链）——prefix 键已天然做到（上游未变层 chain plane 缓存命中），无需新机制。
- C：拖动节流/降帧——双级 busy 已表达「调整渲染中」，额外节拍器是复杂度。
**推荐 A**。

### OQ-11 zh/en 键范围（M2-3-4 zh-audit 先例沿用）
- **A（推荐）**：**随手键 + phase 尾对账补齐**——节点面板/命令菜单新 UI 开写即 `String(localized:)`（`nodes_*` 键族），zh 值滞后允许；收口批跑 `Scripts/zh-audit.py --check` 对账一次补齐（预估 30-60 键，基数沿 M2-3-4 后现值）；语言 code 沿 `zh` 不引入 `zh-Hans`。
- B：每任务同步 zh——面板密集期反复打断，M2-2/M2-3 已确立 verbatim 先例。
**推荐 A**。

## Canonical References

- `research/ALCEDO-FEATURE-MAP.md` §3（节点图模型正本：`pipeline_graph_commands.hpp`/`graph_validation.hpp`/`color_grade_node_model.hpp:29-34,56-65,130-137`/`drt_node_model.hpp:182-207`）+ §2.1（18 目录归属）+ §1.3（Nodes 面板/Mask Groups 语境）
- REQUIREMENTS M2NODE-01..06（本 phase 需求族）；ROADMAP M2-4 行
- `LightamerCore/Sources/Pipe/LayerCompositeDriver.swift:69-97,160,375`（串行复合语义正本）
- `LightamerCore/Sources/Layers/`（LayerStack/AdjustmentLayer/BlendMode/MaskSpec 族）+ `LightamerCore/Sources/Sidecar/LightamerSidecar.swift:86-121`（v4 additive 惯例正本）
- `LightamerCore/Sources/Library/LibrarySchema.swift:339,445-470`（四表占位 + 激活序钦定）
- `phases/m2-3-ui-shell/M2-3-CONTEXT.md`（CONTEXT 惯例 + 七页签/工具轨交付边界）；`phases/m2-3-ui-shell/M2-3-3-ACCEPTANCE.md`（壳交付实态）

## Specific Ideas（起草倾向，plan 细化）

- `PipelineDocument` 门面类型放 Core（`Sources/Layers/` 或新 `Sources/Graph/`），只读投影 + 命令枚举（`NodeGraphCommand`）同文件，命令执行器 = `LayerStack` extension——单文件承载「图语义 ↔ 层操作」映射表，防映射知识散落。
- 命令执行统一入口（`@MainActor` `EditorState.apply(_: NodeGraphCommand)`），内联 history item 构造——undo/redo 复原路径只有一条。
- 节点图 ViewModel 独立于视图（`NodesPanelModel`：订阅 EditorState.layerStack 投影 + 选中态），图视图纯 dumb——M2-7 Mask Groups 面板复用同一 ViewModel 的组序投影。
- 锁定节点交互三件套（锁形标记 + 删除拦截 + 提示文案）做成可复用 modifier，M2-7 首组锁直接用。

## Deferred Ideas

- 节点画布缩放/平移（Fit 恒定的补集；节点多到溢出再议——线性链 N 通常 <10）。
- blend mode 在节点面板的呈现（OQ-6-B，M2-7 后按用户反馈再裁）。
- `graph_validation` 式旧文档拒绝器（Alcedo 拒 AnalyticMaskNode/RasterMaskNode 旧型）——Lightamer 无历史包袱型，不适用。
- Develop 节点「调整列表」的长期归属（现全局链 vs M2-5 后 18 目录收窄——M2-5 plan 裁）。

---

## 夜间授权预案（2026-09-29 起草时点）

本 CONTEXT 提交夜间授权裁决：若无人干预，D-M2-4-CONTEXT-1..11 = **OQ-1..11 全部按推荐 A 生效**。晨审可推翻：推翻任一条 = 修订对应 plan（CONTEXT OQ 原文不改、以 Ruling/勘误注记为准，沿 M2-3-CONTEXT E1 勘误先例）。plan 期需回填的悬决点（非 OQ 级）：v5 是否触发与字段清单（OQ-4）、33 op → 18 目录归属对照表终值（OQ-8）、重连手势的具体交互样式（OQ-5）。

---

## Ruling（2026-09-30 夜间授权，晨审可推翻）

D-M2-4-CONTEXT-1..11 = OQ-1..11 **全部按推荐 A 生效**。三条盘点发现采信为事实基线：①LayerCompositeDriver 串行级联与 grade 链数学等价，投影视图零复合语义改动；②sidecar 升版起点 = v4→v5（additive/hash-isolation 惯例）；③蒙版 shell 06-03 已冻结，缺口仅 item 级 enabled/display_name/删除锁字段。

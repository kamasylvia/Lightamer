---
phase: m2-4
plan: "M2-4-1"
title: "模型核——PipelineDocument 只读门面（develop + grades 投影 + DRT 占位，D-M2-4-CONTEXT-1）；LayerStack 图命令集 7 条（AddClean/Remove+Bridge/Reconnect/Rename/SetEnabled/SetMix/InsertFromJson，D-M2-4-CONTEXT-2，undo 保 UUID）；18 目录所有权框架（Core 枚举+IOP 常量表+App 校验缝，D-M2-4-CONTEXT-8）；sidecar v4→v5 additive（蒙版缺口三字段 + rawOverrides，M2DIS-04 挂账销账）+ RAW overrides 持久化接线。渲染零改动（LayerCompositeDriver 串行级联原样）"
wave: 1
depends_on: ["M2-3"]
autonomous: true
requirements: [M2NODE-01, M2NODE-02, M2NODE-03, M2NODE-05, M2DIS-04]
files_modified:
  - LightamerCore/Sources/Graph/PipelineDocument.swift     # 新建（新目录 Graph/ → tuist generate）：只读门面——Node{id,kind,name,isEnabled,mix,isDeletionLocked} + develop/grades/displayTransform 三段投影（D1：develop=baseLayer 投影、grades=compositeLayers、drt=固定占位常量 UUID；retouch 不上图=compositeLayers narrowing 既有；零存储字段=纯派生）
  - LightamerCore/Sources/Graph/NodeGraphCommand.swift     # 新建：7 命令枚举 + 纯数据 apply(to: LayerStack) throws -> LayerStack（映射表单文件承载）+ NodeGraphError + NodeOwnershipError 引用；InsertFromJson 载荷 = SidecarLayerRecord JSON（保 UUID/paramsData 字节）
  - LightamerCore/Sources/Graph/NodeOwnership.swift        # 新建：Owner 枚举（develop/grade/drtPost）+ validate(insert:into:) 纯函数 + NodeOwnershipError；Core 零 op 字面量（表在 IOP）
  - LightamerIOP/Sources/NodeOwnershipCatalog.swift        # 新建：33 op → Owner 对照表（全部 <Module>.opName 常量，零字符串字面量；默认 .grade + 显式例外四件 DRT/Post + develop 族）+ 全量分类完备性入口
  - LightamerCore/Sources/Layers/LayerStack.swift          # 修改：public mutating insert(_ layer: AdjustmentLayer, at index: Int) additive（AddClean(beforeID)/InsertFromJson 落点；既有 API 零 diff）
  - LightamerCore/Sources/Layers/Masks/MaskSpec.swift      # 修改：MaskGroupItem 增 enabled/displayName + MaskSpec 增 deletionProtected（全 Optional additive，synthesized encodeIfPresent——nil 保持 canonical JSON 字节不变 → stableHash 零漂移）
  - LightamerCore/Sources/Sidecar/LightamerSidecar.swift   # 修改：schemaVersionCurrent = 5 + v5 字段注释节 + rawOverrides: RAWTechnicalOverrides?（decodeIfPresent + encodeIfPresent + hash-isolated 判定注记）
  - App/Sources/Lightamer/State/EditorState.swift          # 修改：@MainActor apply(_ command: NodeGraphCommand) 统一入口（每命令恰一条 structure commit，history_graph_* 键族）+ addModuleToLayer 所有权校验缝（typed error → toast）+ nextLayerName 私有实现下沉迁移（M4 单源：调用点 :414/:605 改消费 Core extension，私有副本删除）
  - App/Sources/Lightamer/State/PipeCoordinator.swift      # 修改（T5）：恢复腿 E1 方案①——document.rawOverrides 与会话缓存不等 → 会话缓存回注 + 经 EditorState.load 唯一请求链触发带 overrides 的 re-decode（KD-5 调用链图）+ updateRawOverrides 写腿（内存文档 → 既有 2s throttle 写）+ attach(workspace:) 反向缝
  - App/Sources/Lightamer/UI/Shell/WorkspaceModel.swift    # 修改：attach(pipeCoordinator:) 缝（E1③ 引用通道）+ setRawDecodeOverrides 增持久化透传钩（会话缓存字典保留，语义零变）
  - App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift # 修改（T5，一行）：.task 装配 workspace.attach(pipeCoordinator:) + pipeCoordinator.attach(workspace:)（E1③ M2-3-1 attach 缝同款）
  - Project.swift                                          # 修改：新建测试文件登记进对应 bundle sources 显式清单（bundle 无 glob，漏登 = 文件不进构建；checker E2 测试登记纪律；新文件同 commit tuist generate）
  - Tests/LightamerTests/PipelineDocumentTests.swift       # 新建（→ tuist generate；**LightamerTestsLayers**，Core 级——纯 Core 投影，checker E2 归属）：投影 parity（序/id/锁/mix）+ retouch 排除 + 空栈三段
  - Tests/LightamerTests/NodeGraphCommandTests.swift       # 新建（**LightamerTestsApp**，App 级——undo/redo round-trip 经 EditorState 实例，checker E2 归属）：7 命令逐一（含 undo/redo round-trip 保 UUID + InsertFromJson 字节复原 + SetMix 钳制 + SetMix(0)≡bypass 像素断言 + 锁拦截）
  - Tests/LightamerTests/NodeOwnershipCatalogTests.swift   # 新建（**LightamerTestsApp**，App 级——addModuleToLayer 拦截经 EditorState 实例，checker E2 归属）：33 op 全分类完备性（registry 面 ∖ 表 = ∅）+ 四件 DRT/Post 断言 + 校验矩阵
  - Tests/LightamerTests/SidecarV5Tests.swift              # 新建（**LightamerTestsApp**，App 级——AC7 真 load 链经 EditorState/PipeCoordinator 实例，checker E2 归属）：v4 档 decode（新字段 nil）+ v5 round-trip + nil 零漂移（stableHash 字节 parity + driftDetected 不变）+ 容忍 >5 + 真链持久化 round-trip
  - .work/gsd/phases/m2-4-node-model/M2-4-1-SUMMARY.md     # 新建（收口任务）
  - .work/gsd/phases/m2-4-node-model/M2-4-1-DECISIONS.md   # 新建（收口任务）
  - .work/GOAL-STATE.md                                    # 续接点追加（收口任务）
  - .work/LESSONS.md                                       # 如踩坑
---

# Plan M2-4-1 — 模型核（PipelineDocument 门面 + 图命令集 + 所有权框架 + sidecar v5）

> **性质**：模型 plan——`LightamerCore/Sources/Graph/` 新目录承载节点图语义，`LightamerCore
> /Sources/{Layers,Sidecar}` additive 扩展，App 层只加「统一命令入口 + 校验缝 + overrides
> 持久化接线」。**渲染管线零改动**：`LayerCompositeDriver` 串行级联即 grade 链的执行形态
> （CONTEXT 盘点发现①），本 plan 不触 `Pipe/` 任何文件。规格锚点 = D-M2-4-CONTEXT-1..8、11
> （全部按推荐 A 生效）+ `research/ALCEDO-FEATURE-MAP.md` §3 + REQUIREMENTS M2NODE-01/02/03/05。
>
> **本 plan 是 P2/P3 的缝正本**：`PipelineDocument`（P2 groups 投影、P3 面板数据源）、
> `NodeGraphCommand`（P3 全部手势的执行面）、`NodeOwnership`（M2-5 目录收窄的校验地基）、
> sidecar v5（M2-7 蒙版面板的持久化前置）——API 形态在此定死，后续只消费不重开。

## 已定裁决（不得重开）

- **D-M2-4-CONTEXT-1（OQ-1 A）**：layer = 节点的持久化形态，节点图 = `LayerStack` 的**只读投影视图**；
  持久化零迁移；`grade.primary` ↔ base layer 投影；UUID 身份（`grade.*` 字符串 id 不引入）。
- **D-M2-4-CONTEXT-2（OQ-2 A）**：全套 7 条命令照抄 Alcedo 命令面；每命令 = 一条 `HistoryItem`；
  InsertFromJson 载荷 = 层记录 JSON 快照（字节精确惯例）。
- **D-M2-4-CONTEXT-3（OQ-3 A）**：多蒙版 = `MaskGroupSpec` 承载；缺口字段 additive decodeIfPresent。
- **D-M2-4-CONTEXT-4（OQ-4 A）**：零字段投影优先 + 最小 v5 additive 兜底——**plan 期实测证实缺口存在**
  （`MaskGroupItem` 无 `enabled`/`display_name`、`MaskSpec` 无 `deletion_protected`、
  `RAWTechnicalOverrides` 无持久化载体），v5 触发；`.lalb` 四表零触碰。
- **D-M2-4-CONTEXT-6（OQ-6 A）**：mix = opacity 投影零新字段；面板不露 blend mode（P3 执行）。
- **D-M2-4-CONTEXT-7（OQ-7 A）**：Develop = base layer 投影（不可删/不可重连/恒图首）；DRT = 固定灰态
  占位端点；`grade.primary` 删除锁 = baseLayer 结构性恒在；retouch 不上图。
- **D-M2-4-CONTEXT-8（OQ-8 A）**：框架先行 + 归属表落盘 + 宽限执行——UI 新插受限（typed error），
  已存 sidecar 加载宽容（degrade 不拒载），M2-5 激活严格执行。
- **D-M2-4-CONTEXT-11（OQ-11 A）**：新 UI 键随手 `String(localized:)`，zh 滞后允许，P3 收口对账。
- **M2DIS-04 挂账销账**（本 plan 范围裁定）：`RAWTechnicalOverrides` 目前是
  `WorkspaceModel.rawDecodeOverrides: [String: RAWTechnicalOverrides]` 会话级字典
  （`WorkspaceModel.swift:184`），M2-3-3 明文「持久化挂账 M2-4 节点 schema」——本 plan
  以 sidecar v5 `rawOverrides` 字段销账（Develop 节点载荷的第一块真实内容）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 PipelineDocument = 纯派生门面，双向同步点 = 无

```swift
public struct PipelineDocument: Sendable, Equatable {
    public enum NodeKind: Sendable { case develop, grade, displayTransform }
    public struct Node: Identifiable, Sendable, Equatable {
        public let id: UUID                  // develop = baseLayer.id；grade = 层 UUID；drt = 固定常量
        public let kind: NodeKind
        public let name: String
        public let isEnabled: Bool
        public let mix: Float                // grade = layer.opacity；端点恒 1（D-M2-4-CONTEXT-6）
        public let isDeletionLocked: Bool    // develop/drt = true（D-M2-4-CONTEXT-7）；grade = false
        public let layerID: UUID?            // grade → 层 UUID；端点 nil
    }
    public static let displayTransformNodeID = UUID(uuid: (…))  // 编译期固定常量
    public let develop: Node
    public let grades: [Node]                // = compositeLayers 投影，bottom-to-top = 图序
    public let displayTransform: Node
    public init(_ stack: LayerStack)
    public var nodes: [Node] { [develop] + grades + [displayTransform] }
}
```

**一致性维持答案（KD 必答）**：投影视图**没有任何双向同步点**——`PipelineDocument` 无
存储字段、无身份、每次读取由 `init(_ stack:)` 重建，是 `LayerStack` 的纯函数。漂移在
构造上不可能；测试钉的是**投影不变量**（序/数量/id/锁/mix 与栈逐项相等），而非同步。
retouch 层被 `compositeLayers` narrowing 自然排除（D-M2-4-CONTEXT-7 ④ 上图豁免的结构性保证）。

### KD-2 图命令集 = Core 纯数据 apply + App 统一入口，undo 靠既有 stackSnapshot

```swift
public enum NodeGraphCommand: Sendable, Equatable {
    case addCleanGrade(before nodeID: UUID?)      // nil = 栈顶追加；identity = 空 chain（13 目录项 M2-5 落）
    case removeGradeAndBridge(id: UUID)           // 线性链桥接 = 层栈结构性平凡（移除即桥接）
    case reconnectGrade(id: UUID, toPosition: Int) // = 层重排（grade 序内索引，钳制）
    case renameGrade(id: UUID, to name: String)
    case setGradeEnabled(id: UUID, enabled: Bool)
    case setGradeMix(id: UUID, mix: Float)         // 写 opacity，钳 0...1（D5）
    case insertGradeFromJSON(data: Data, position: Int)
}
extension NodeGraphCommand {
    /// 纯数据变换：LayerStack in → LayerStack out，不碰 history（可 Core 单测）。
    public func apply(to stack: LayerStack) throws -> LayerStack
}
public enum NodeGraphError: Error, Equatable {  // lockedNode / nodeNotFound / notAGrade
}                                               // / badPayload / badPosition
```

- **执行分工**：Core `apply(to:)` 承载「图语义 ↔ 层操作」映射表（单文件，防映射知识
  散落——CONTEXT Specific Ideas）；App `EditorState.apply(_ command:)`（@MainActor）
  = 薄封装：调 `apply(to:)` → 重赋 `layerStack`（GUI-19 @Observable 原子）→ **恰一条**
  `commitLayerStructure(label:)`（`history_graph_*` 新键族）。undo/redo 复原路径只有一条
  = 既有 `rebuildLayerStack()`（structure item + `stackSnapshot`，`EditorState.swift:646`）。
- **InsertFromJson 复原语义（KD 必答）**：载荷 = `SidecarLayerRecord` 的 JSON 编码
  （`paramsData` base64 字节精确惯例）；restore 走 `record.layer`——**id/chain 字节/mask
  全 verbatim**（`SidecarLayerStack.swift` restore 路径已保证身份不重铸）+ `LayerStack
  .insert(_:at:)` 新 mutation。undo Remove = 对 Remove 前快照执行 InsertFromJson；
  **AC 断言复原后 UUID 与 paramsData 逐字节相等**（M2NODE-02「保 NodeId」机检）。
  `kind != "adjustment"` 的载荷 = `badPayload` 拒绝（retouch 永不上图）。
- **AddClean identity 形态**：M2-4 时点 = 空 chain + 默认名「Color Grade N」（= Core
  单源 `nextLayerName` 产出，见下条 M4）+ enabled + opacity 1 + normal blend
  （18 目录项 = M2-5 非目标，CONTEXT Phase Boundary 明文）。
- **默认名规则单源（checker M4）**：序数 + 碰撞清扫算法**下沉 Core**——
  `extension LayerStack { public func nextLayerName(base: String) -> String }`
  （现 `EditorState.nextLayerName` 私有静态 `EditorState.swift:668` 算法 verbatim 搬移）；
  `EditorState` 两个调用点（`:414` adjustment / `:605` retouch）改消费该 extension、
  私有实现删除——**消除双源**（App 与 `NodeGraphCommand.apply` 同一入口）；
  base = `layer_default_name` 本地化键由调用方传入（Core 不持本地化键——Core 零
  `String(localized)` 先例保持）。
- **穷举纪律（checker 教训①）**：`NodeGraphCommand`/`NodeKind`/`NodeGraphError` 全部
  switch **禁 default**；新枚举全仓消费者 grep 触点全列 = `EditorState.apply`（唯一执行
  入口）+ `NodeGraphCommandTests`，P3 面板为纯生产者不 switch 命令。

### KD-3 所有权框架 = Core 枚举 + IOP 常量表 + App 校验缝，宽限执行

- **依赖方向约束**：Core 不 import LightamerIOP（既有方向，`Mat3D.swift:6` 注记）——
  归属表若落 Core 必然引入 op 字符串字面量，违「opName 恒 `<Module>.opName` 常量」纪律。
  故三层切分：
  1. **Core** `Graph/NodeOwnership.swift`：`NodeOwnership` 枚举（`.develop`/`.grade`/
     `.drtPost`）+ `validate(owner:into:) -> NodeOwnershipError?` 纯函数 + typed error。
  2. **LightamerIOP** `NodeOwnershipCatalog.swift`：`static func owner(of opName: String)
     -> NodeOwnership`——默认 `.grade`，显式例外全用 `<Module>.opName` 常量：
     - **.drtPost 四件**（Alcedo Detail 面板族，Feature-map §2.1）：`SharpenModule`→Sharpen、
       `GrainModule`→FilmGrain、`BloomModule`→Halation、`EqualizerModule`→Clarity
       （**Clarity 位源 op = equalizer** 为 plan 裁定，IOP-DETAIL-02「local contrast 等效
       clarity」交付面；执行时在 DECISIONS 复核签注）；
     - **.develop 族**：`TemperatureModule`（相机 WB 归 RAW Decode，M2GRADE-04）、
       `LensModule`/`AshiftModule`/`FlipModule`/`CropModule`/`LiquifyModule`（几何，
       layerForbiddenGeometryOps 既有禁令的语义呼应）、`BordersModule`/`WatermarkModule`/
       `TextOverlayModule`（终端段/yiyin 面）、禁用 face 六件（`FilmicRGB`/`Sigmoid`/`AgX`
       → DRT 域、`DenoiseProfile`/`NLMeans`/`Bilateral` → RAW 域，禁 `defaultFaceDisabled
       OpNames` 常量导入判）、非 UI 两件（passthrough_spike/testgain）。
  3. **App**：`EditorState.addModuleToLayer` 增校验缝——`.drtPost`/`.develop` 项入 Grade =
     `NodeOwnershipError` → 既有 toast（不崩、不静默）。**放宽面**：全局链、retouch、
  sidecar 加载、undo/redo、InsertFromJson 复原全部**不校验**（D-M2-4-CONTEXT-8 宽限 +
  复原是用户自己的数据）。M2-5 收窄 18 目录时只改表，不改校验面。
- **AC 机检**：完备性测试 = ModuleRegistry 默认 face 全集 ∖ `owner(of:)` 已分类 = ∅
  （新增 op 忘记归类 = 测试红）；四件 DRT/Post 逐名断言。

### KD-4 sidecar v4→v5 additive = 一原子格式事务（M2-3-3 nil 零漂移先例照抄）

v5 新字段全集（三处，全部 Optional additive，decodeIfPresent/encodeIfPresent）：

| 字段 | 位置 | 语义 |
|---|---|---|
| `enabled: Bool?` | `MaskGroupItem` | nil = true（M2NODE-04 独立 enabled 的数据面） |
| `displayName: String?` | `MaskGroupItem` | nil = 派生显示名（M2-7 面板消费） |
| `deletionProtected: Bool?` | `MaskSpec` | nil = false（D-M2-4-CONTEXT-7 spec 级锁，M2MASK-04 前置数据面） |
| `rawOverrides: RAWTechnicalOverrides?` | `LightamerSidecar` | Develop 节点载荷（M2DIS-04 销账） |

- **零漂移机理**：`MaskSpec.stableHash()` = canonical sortedKeys JSON（`MaskSpec.swift:296`
  注记明文 encodeIfPresent 语义）——新字段 nil 时编码**缺席**，canonical JSON 字节与
  v4 逐字节相同 → 旧档 cache key 与 drift 锚零漂移。测试逐字节钉（先例 = M2-3-3
  `RawDecodeOverridesTests` 膨胀字段 5 断言）。
- **hash-isolation 判定**：`rawOverrides` = decode 域载体，**不进** `HistoryHash.hash`
  的 stack 折叠（decode 结果已由 `decodeParamsHash` 代表；沿 v3 五字段先例的判定形式，
  理由入 DECISIONS）；蒙版三字段**进** mask 域（经 `stableHash()` 自然折叠）——蒙版
  编辑本就该 flip 缓存与 drift（06-05 hardening 既有语义，无新代码）。
- **读者容忍矩阵**：v1..v4 档 decode 新字段全 nil；v5 档被 v4 时代读者读（schemaVersion
  5 > 4）= 既有容忍契约全绿回归；**写者恒发 5**。
- **round-trip 风险对策**：SidecarV5Tests 用 fixture 字符串矩阵（v1/v2/v3/v4 真形档 +
  v5 生成档）逐档 decode→encode→decode 断言。

### KD-5 RAW overrides 持久化接线 = 既有 load(overrides:) 缝 + 恢复腿 re-decode（checker E1 方案①）

**调用链图（恢复腿 + 写腿 + 引用通道；全部触点均在 files_modified 申报内）**：

```
恢复腿（E1 方案①——真 load 链两次 decode）：
  EditorWorkspaceShellView.loadCurrentImage（:171 既有）
  → EditorState.load(overrides: 会话缓存值/identity)【decode #1，唯一请求链】
  → PipeCoordinator.load → sidecar probe → restoreFromSidecar（:850）
  → document.rawOverrides？
      ├─ nil（pristine 档）：单 decode 终局，零 re-decode 零回注【②】
      └─ 非 nil 且 ≠ 会话缓存 rawDecodeOverrides(for: url)：
           a. 会话缓存回注 workspace（切图秒回显通道不变）
           b. 经 EditorState.load 唯一请求链触发带 overrides 的 re-decode
             【decode #2 替换首帧；同图 reload 既有语义 = 会话内 history
               保留（PipeCoordinator.load same-url 分支），无二次 restore】
      └─ 非 nil 但 == 会话缓存：跳过（帧已带 overrides，防 switch-back 双 decode）

写腿（持久化）：
  RawDecodePanelView.commit()（零 diff）
  → WorkspaceModel.setRawDecodeOverrides（会话缓存语义零变）
  → 透传钩 pipeCoordinator?.updateRawOverrides(overrides, for: url)
  → PipeCoordinator：内存 document.rawOverrides 更新 + 既有 2s debounce throttle 写盘
  （flushNow() 时机 = 切图/退出，既有机制覆盖——切图 flush 保证 sidecar 与缓存同步）

引用通道（E1③——M2-3-1 既有 attach 缝同款，弱引用防环、root 强持有）：
  app-root 单例 pipeCoordinator（LightamerApp.swift:185；:459 经 EditorState.attach
  缝已绑 editorState）
  → WorkspaceHostView（workspace 实例宿主 :40）.task 一行装配：
      workspace.attach(pipeCoordinator:)   【WorkspaceModel→PipeCoordinator，写腿透传】
      pipeCoordinator.attach(workspace:)   【恢复腿回注会话缓存用，同缝反向】
```

- **① 双 decode 代价声明（checker E1）**：sidecar 含 `rawOverrides` 的图**每次冷加载
  两次 decode**——首帧 identity 出图（请求链发出时 sidecar 未读，时序上不可能先知），
  overrides 到位后二次 decode 替换。**缓存失效零新代码**：PixelPipe cache key 含
  `RAWTechnicalParams JSON`（`PixelPipe.swift:67`，M2-3-3 KD-4 既有机理）——overrides
  帧与 identity 帧键不同自动分流，identity 帧缓存随既有 LRU 逐出。**同会话切回 =
  单 decode**：恢复腿回注/写腿保证会话缓存就位，`loadCurrentImage` 首次 decode 即带
  overrides（触发条件等价判定跳过 re-decode）。双 decode 代价面仅限「session 内首次
  打开且档含 overrides」，间隔 = 一次完整解码时延，PREVIEW 双级 busy 既有语义覆盖
  视觉过渡。
- **② pristine 档语义**：`document.rawOverrides == nil`（v5 缺省档/全部旧档）= 单
  decode、零 re-decode、零回注——现行为逐字节不变。
- **③ 引用通道（checker E1③）**：`WorkspaceModel` 增 `weak var pipeCoordinator` +
  `attach(pipeCoordinator:)`、`PipeCoordinator` 增 `weak var workspace`——**同款
  M2-3-1 attach 缝模式**（`EditorState.attach(pipeCoordinator:)` `EditorState.swift:107`
  / `PipeCoordinator.attach(editorState:)` `:495`，弱引用防环、app-root 强持有）；
  装配点 = `WorkspaceHostView`（workspace 宿主 `:40`）`.task` 一行（**files_modified
  申报 `WorkspaceHostView.swift`**）。re-decode 参数供给：decoder = `workspace
  .editorDecoder`（与 `loadCurrentImage:170` 同款参数面）、metal = coordinator 既有
  attach 面、logger = `EditorState.decodeLogger`。
- **触发条件细化（防双 decode 退化）**：re-decode 仅当 `document.rawOverrides` 与
  会话缓存 `rawDecodeOverrides(for: url)` **不等**（含缓存 miss 的 identity）时触发——
  切回已回注的图（缓存 == 档）跳过；切图 flushSidecar 既有机制保证档与缓存同步，
  会话内新改值不被档回灌。
- **红线**：`WorkspaceModel` 会话缓存字典语义保留（切图秒回显仍走它，恢复腿只做
  **回注**不改读面）；面板 `RawDecodePanelView.swift` **零 diff** 目标（若实测必须动，
  逐 hunk 评审 m7 入 SUMMARY）；`EditorState.load` 签名零改（overrides 参数 =
  M2-3-3 T4 既有缝）。
- **re-entrancy 注记**：re-decode 重入 `PipeCoordinator.load` 时 URL 相同 → 既有
  「same-url reload keeps the session's in-memory history」分支——不重放 sidecar
  restore、不重置 history；`decodeTask?.cancel()` 对已完成任务 no-op，新旧 decode
  竞争由既有 `Task.isCancelled` 卫语消解。

## read_first

1. `.work/gsd/phases/m2-4-node-model/M2-4-CONTEXT.md`——裁决正本（D1..D11 + Reusable
   Assets 表 + Ruling 节）。
2. `LightamerCore/Sources/Layers/LayerStack.swift`——mutation API 全貌（insert 落点 +
   reorder 钳制语义参照）；`AdjustmentLayer.swift`（字段对照正本）。
3. `LightamerCore/Sources/Sidecar/LightamerSidecar.swift`——v4 additive/hash-isolation
   惯例正本（`:86-121` 版本注释节 + decodeIfPresent 形态）；`SidecarLayerStack.swift`
   （InsertFromJson 载荷/restore 正本）。
4. `LightamerCore/Sources/Layers/Masks/MaskSpec.swift:189-300`——MaskGroupItem/MaskSpec
   现形 + `stableHash()` encodeIfPresent 语义。
5. `App/Sources/Lightamer/State/EditorState.swift:385-680`——layer 结构操作全貌
   （commitLayerStructure/layerStructureScope/rebuildLayerStack/GUI-19 重赋原子）。
6. `App/Sources/Lightamer/State/PipeCoordinator.swift:680-900`——sidecar 恢复腿 +
   EditorState.load(overrides:) 缝（`:301`）。
7. `LightamerIOP/Sources/Registry.swift`——`defaultFaceDisabledOpNames` + 模块注册面
   （归属表分类域）；`LightamerCore/Sources/Foundation/V50Order.swift`（op 全集参照）。
8. `.work/gsd/phases/m2-3-ui-shell/M2-3-3-ACCEPTANCE.md` T4 节——RawDecodeOverrides
   缝的交付实态（挂账原文）。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits 全英文、subject ≤72 字符祈使句、
   body 写 what+why + 同批 md 清单）；只 add 本任务申报文件；**不 push**；git add 用
   `.work/gsd/...` 真路径。
2. **构建纪律**：`caffeinate -dis` 包裹一切构建；不加 `-derivedDataPath`；新建 .swift
   文件后同 commit 内跑 `tuist generate`（T1-T3 批量建文件 → generate 一次）。
3. **测试纪律**：单测命令 = `Scripts/test-direct.sh '<Class>'`；判据 = Executed 计数行 +
   failures 行双读（L028）。**回归基线 = 2165/14skip/0fail**；每任务全套 suite 绿。
   **全套跑法 = `Scripts/test-direct.sh --all`（七 bundle）**；跑前必须向 orchestrator
   SendMessage 报备；RSS ≥8G = MEMFAIL 机检内置（SPIKE `70e09e5` 8G 口径），触发即记
   E3 不自行重试超两次。在案 flake 隔离复跑 ×3 归因入 SUMMARY。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
5. **架构红线**：`LayerCompositeDriver.swift`/`PixelPipe.swift`/`PipeCacheKey.swift`
   **零 diff**（渲染语义零改动是本 phase 地基）；`.lalb`/`LibrarySchema.swift` 零触
   （四表占位 M2-8）；`LayerStack.swift`/`MaskSpec.swift`/`LightamerSidecar.swift`
   只许 additive（既有行零语义改动）；GPL 参考只读（Alcedo 代码不入库）。
6. **测试登记纪律（checker E2，2026-09-30）**：新建测试文件**同 commit** 登记两处——
   ① `Project.swift` 对应 bundle 的 sources 显式清单（bundle 无 glob，漏登 = 文件不进
   构建）；② `.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt` 增行
   （格式 `<bundle>\t<test-method-count>\t<file>`）。归属判定：**App 级（实例化
   EditorState/LayerEditingState 等 App target 类型）→ LightamerTestsApp；Core 级 →
   LightamerTestsLayers**（front-matter 逐文件标注为准）。新文件落盘后同 commit
   `tuist generate`。本 plan 归属：PipelineDocumentTests = Layers（Core）；其余三件
   （NodeGraphCommand/NodeOwnershipCatalog/SidecarV5）= App（EditorState 实例）。
7. **收口核对（checker 教训②）**：T6 `git diff --stat` 与 front-matter files_modified
   逐文件核对，越界 = 违约。

## Tasks

### T1 PipelineDocument 只读门面 + 投影测试

- **read_first**：上列 1/2/5。
- **action**
  1. 新建 `LightamerCore/Sources/Graph/PipelineDocument.swift`（KD-1 全量：NodeKind
     穷举、Node 七字段、`displayTransformNodeID` 固定常量、`init(_ stack:)` 纯派生、
     `nodes` 拼接；头注声明「纯派生门面——无存储状态，禁止加任何 var 缓存」）。
  2. 新建 `Tests/LightamerTests/PipelineDocumentTests.swift`：投影 parity 三断言组
     （grades 序 = compositeLayers 序逐 id；name/enabled/opacity 逐层相等；
     isDeletionLocked = 端点 true / grade false）+ retouch 层排除断言 + 空栈三段
     （develop + [] + drt）+ Equatable 快照相等（同栈两次 init 相等——纯函数证明）。
  3. `tuist generate`（新目录）。
- **验收标准**
  - [ ] 投影 parity/retouch 排除/空栈三段断言全绿；同栈两次 init 相等。
  - [ ] 测试登记：Project.swift（LightamerTestsLayers sources）+ BUNDLE-MAP 行同 commit
        在册（纪律 6）。
  - [ ] 全套回归 `0 fail`（基线 2165 + 新增）。

### T2 图命令集 7 条 + LayerStack.insert + EditorState.apply

- **read_first**：上列 2/3/5。
- **action**
  1. `LayerStack.swift` 追加 `public mutating func insert(_ layer: AdjustmentLayer,
     at index: Int)`（钳制语义与 `reorder` 一致；既有 API 零 diff——diff 评审 m7）。
  2. 新建 `Graph/NodeGraphCommand.swift`（KD-2 全量：7 case + 纯 `apply(to:)` +
     `NodeGraphError` 穷举；AddClean 默认名 = **Core 单源** `LayerStack.nextLayerName
     (base:)`——M4 落法：算法自 `EditorState.swift:668` verbatim 下沉为 LayerStack
     extension，`EditorState` 调用点 `:414/:605` 改消费、私有实现删除）。
  3. `EditorState.swift` 增 `@MainActor func apply(_ command: NodeGraphCommand) throws`
     （KD-2 分工：try apply(to:) → 重赋 layerStack → 恰一条 commitLayerStructure，
     `history_graph_add/remove/reconnect/rename/enable/mix/insert` 七键族）+
     error → toast 面序（lockedNode 不 toast 静默拦截，其余 toast）。
  4. 新建 `Tests/LightamerTests/NodeGraphCommandTests.swift`：7 命令逐一正例 + 锁拦截
     （develop/drt id 上 remove/reconnect = lockedNode）+ `reconnect` 钳制 +
     `setGradeMix` 钳 0...1 + **SetMix(0) ≡ bypass 像素级断言**（checker E4：同一栈
     `setGradeMix(0)` 后经 LayerCompositeDriver 复合输出 vs 该层 `enabled=false`
     摘除后复合输出，逐像素**容差 0**、`-0/+0` 视相等——LayerCompositeTests CPU
     对照先例）+ **undo/redo round-trip**（每命令 undo 后栈与命令前逐层相等、
     redo 后 UUID 保持）+ **InsertFromJson 字节复原**（encode→apply→decode 后
     id/paramsData/mask 逐字节相等）+ `kind=="retouch"` 载荷拒绝 + 纯函数性
     （apply 不改输入栈——value 语义证明）。
- **验收标准**
  - [ ] 7 命令正例 + 锁/钳/载荷拒绝断言全绿；undo/redo 保 UUID 全绿；InsertFromJson
        字节复原全绿；SetMix(0) ≡ bypass 像素级断言绿（E4）。
  - [ ] `NodeGraphCommand`/`NodeGraphError` switch 穷举零 default（`git grep -n
        "default:" -- LightamerCore/Sources/Graph/` 于新文件零命中 + 编译穷举——M2 口径）。
  - [ ] M4 单源核验：`git grep -n "nextLayerName" App/Sources` 仅剩消费点（无私有副本），
        Core extension 单定义。
  - [ ] 测试登记：Project.swift（LightamerTestsApp sources）+ BUNDLE-MAP 行同 commit
        在册（纪律 6）。
  - [ ] 全套回归 `0 fail`。

### T3 所有权框架（Core 枚举 + IOP 常量表 + App 校验缝）

- **read_first**：上列 1/7 + `App/Sources/Lightamer/State/EditorState.swift:515`
  （addModuleToLayer 实态）+ REQUIREMENTS M2GRADE-04/IOP-DETAIL-02（develop/drtPost
  归属语义依据）。
- **action**
  1. 新建 `Graph/NodeOwnership.swift`（KD-3 层 1：枚举 + validate 纯函数 +
     `NodeOwnershipError`）。
  2. 新建 `LightamerIOP/Sources/NodeOwnershipCatalog.swift`（KD-3 层 2：`owner(of:)`
     默认 .grade + 显式例外全常量；**禁一个字符串字面量**——AC 机检 grep）。
  3. `EditorState.addModuleToLayer` 增校验缝（KD-3 层 3：typed error → 既有 toast 面；
     加载/undo/InsertFromJson 零校验）。
  4. 新建 `Tests/LightamerTests/NodeOwnershipCatalogTests.swift`：完备性（默认 face
     全集已分类）+ 四件 DRT/Post 逐名 + develop 族逐名 + validate 矩阵（grade 内插
     drtPost = error；grade 内插 grade = nil；develop 不限）。
- **验收标准**
  - [ ] 完备性 + 归属矩阵断言全绿；`git grep '"' NodeOwnershipCatalog.swift` 中
        opName 实参零字面量（仅注释/文档可含）。
  - [ ] addModuleToLayer 拦截路径单测绿；全局链加载路径零回归（既有 suite 全绿）。
  - [ ] 测试登记：Project.swift（LightamerTestsApp sources）+ BUNDLE-MAP 行同 commit
        在册（纪律 6）。
  - [ ] 全套回归 `0 fail`。

### T4 sidecar v5 additive（格式事务）

- **read_first**：上列 3/4 + `LightamerCore/Sources/Sidecar/SidecarStore.swift`
  （写路径参照）。
- **action**
  1. `MaskSpec.swift`：`MaskGroupItem` 增 `enabled: Bool?`/`displayName: String?`、
     `MaskSpec` 增 `deletionProtected: Bool?`（KD-4：Optional additive，init 缺省 nil，
     既有调用点零改动——编译器证）。
  2. `LightamerSidecar.swift`：`schemaVersionCurrent = 5` + 版本注释节（v5 三字段 +
     rawOverrides + hash-isolation 判定注记）+ `rawOverrides` 字段（decodeIfPresent/
     encodeIfPresent）。
  3. 新建 `Tests/LightamerTests/SidecarV5Tests.swift`（KD-4 测试面）：**nil 零漂移**
     （v4 形 spec 加 nil 新字段 → `stableHash()` 与 v4 逐字节相等；v4 档
     `driftDetected` 与升级前代码同值）+ v4 fixture decode 新字段 nil + v5 round-trip +
     `>5` 容忍 + v1..v5 decode 矩阵。
- **验收标准**
  - [ ] nil 零漂移两断言（stableHash 字节 parity + driftDetected 同值）全绿。
  - [ ] v1..v5 decode 矩阵 + 容忍断言全绿；既有 Sidecar 族测试零改动全绿。
  - [ ] 测试登记：Project.swift（LightamerTestsApp sources）+ BUNDLE-MAP 行同 commit
        在册（纪律 6）。
  - [ ] 全套回归 `0 fail`。

### T5 RAW overrides 持久化接线（M2DIS-04 挂账销账；E1 恢复腿方案①）

- **read_first**：上列 6 + `App/Sources/Lightamer/UI/Shell/RawDecodePanelView.swift`
  （改面板写入路径，**目标零 diff**）+ `App/Sources/Lightamer/UI/Shell/WorkspaceModel
  .swift:180-200`（会话字典实态）+ `App/Sources/Lightamer/UI/Shell/WorkspaceHostView
  .swift:25-60`（workspace 宿主装配面）+ `EditorWorkspaceShellView.swift:160-175`
  （loadCurrentImage 参数面——re-decode 同款）。
- **action**
  1. `PipeCoordinator.swift`：恢复腿（`restoreFromSidecar :850`）按 KD-5 调用链图——
     读 `document.rawOverrides`，非 nil 且 ≠ 会话缓存 → 会话缓存回注 workspace +
     经 `EditorState.load` 唯一请求链触发**带 overrides 的 re-decode**（E1 方案①，
     双 decode 代价/缓存键漂移/same-url 保留 history 注记全按 KD-5）；新增
     `updateRawOverrides(_:)`（内存文档 + 既有 throttle 写）+ `attach(workspace:)`
     反向缝。
  2. `WorkspaceModel.swift`：`attach(pipeCoordinator:)` 缝 + `setRawDecodeOverrides`
     增透传钩（会话缓存语义零变）。
  3. `WorkspaceHostView.swift`：`.task` 一行装配双向 attach（E1③ 引用通道，
     M2-3-1 attach 缝同款）。
  4. `SidecarV5Tests` 补**真链 round-trip**（AC7：写 sidecar 含 rawOverrides → 真实
     `EditorState.load` → decode 完成 → restore 腿读 sidecar → re-decode 触发 →
     渲染生效断言——最终 decoded readback 携带 overrides + pristine 档（nil）单
     decode 零 re-decode 断言）+ 持久化 round-trip（写 overrides → 文档含
     rawOverrides → 重读 → load 侧得到同值）+ nil 缺省档写盘不带该键
     （encodeIfPresent）。
- **验收标准**
  - [ ] AC7 真链 round-trip 断言全绿（含 pristine 档零 re-decode 断言）；nil 档不带键
        断言绿。
  - [ ] `RawDecodePanelView.swift` 零 diff（`git diff --stat` 核；若必动 = 逐 hunk
        评审 m7 结论入 SUMMARY）。
  - [ ] WorkspaceHostView/WorkspaceModel/PipeCoordinator 三件 diff 仅 KD-5 声明面
        （attach 缝 + 恢复腿触发 + 透传钩），无越界改动。
  - [ ] 全套回归 `0 fail`。

### T6 收口——SUMMARY/DECISIONS + 续接点

- **read_first**：本 plan AC 表 + `.work/GOAL-STATE.md` 续接点节。
- **action**
  1. AC 逐条机检 + 全套回归终跑（`--all` 前向 orchestrator SendMessage 报备；计数/
     秒数/bundle 峰值入 SUMMARY）。
  2. 落盘 `M2-4-1-SUMMARY.md`（测试数变化/KD 确认/equalizer→Clarity 位复核签注/
     v5 字段终表）+ `M2-4-1-DECISIONS.md`（KD-1..5 执行确认 + 偏差归因）。
  3. `.work/GOAL-STATE.md` 续接点追加（M2-4-1 完成 + 下一步 = M2-4-2）；LESSONS 如踩坑。
  4. `git diff --stat` 核对文件边界与 front-matter 一致（纪律 7）。
- **验收标准**
  - [ ] AC 表全绿；SUMMARY/DECISIONS/GOAL-STATE 同批落盘；diff 边界无越界文件。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | PipelineDocument 投影 parity（序/id/name/enabled/mix/锁逐项）+ retouch 排除 + 纯函数性 | PipelineDocumentTests 断言组 |
| 2 | 7 命令语义 + 锁拦截 + 钳制 + **SetMix(0) ≡ bypass 像素级相等**（`setGradeMix(0)` 后 composite 输出与该层 `enabled=false` bypass 输出逐像素相等——容差 0，`-0/+0` 视相等，checker E4）+ undo/redo 保 UUID + InsertFromJson 字节复原 | NodeGraphCommandTests |
| 3 | 新枚举（NodeGraphCommand/NodeKind/NodeGraphError）switch 穷举零 default | `git grep -n "default:" -- LightamerCore/Sources/Graph/NodeGraphCommand.swift LightamerCore/Sources/Graph/PipelineDocument.swift` 零命中 + 编译穷举（M2 口径：模式限 `default:`、文件限新枚举文件） |
| 4 | 所有权完备性（registry 面 ∖ 表 = ∅）+ 四件 DRT/Post + validate 矩阵 + 表零字面量 | NodeOwnershipCatalogTests + `git grep` |
| 5 | addModuleToLayer typed error 拦截；加载/undo/复原零校验（既有 suite 全绿证） | NodeOwnershipCatalogTests + 既有 suite |
| 6 | sidecar v5：nil 零漂移（stableHash 字节 parity + driftDetected 同值）+ v1..v5 矩阵 + 容忍 >5 + 写者恒发 5 | SidecarV5Tests |
| 7 | RAW overrides **真 load 链** round-trip（checker E1）：写 sidecar 含 rawOverrides → 真实 `EditorState.load` → decode 完成 → restore 腿读 sidecar → re-decode 触发 → 渲染生效断言（最终 decoded readback 携带 overrides）；pristine 档（nil）单 decode 零 re-decode；nil 档不带键；RawDecodePanelView 零 diff | SidecarV5Tests 真 load 链用例（fixture RAW + 直启宿主）+ `git diff --stat` |
| 8 | 渲染红线零 diff：LayerCompositeDriver/PixelPipe/PipeCacheKey | `git diff --name-only` 断言 |
| 9 | 全套回归 0 fail，计数 ≈ 2165 + 20..28 | test-direct.sh --all BUNDLE 行双读 |
| 10 | diff 边界 == 申报文件集 | `git diff --stat` 逐文件核对 |
| 11 | 新测试文件登记闭环（checker E2）：四测试文件逐个在 Project.swift 对应 bundle sources + BUNDLE-MAP 行在册 | `git grep -n "PipelineDocumentTests.swift\|NodeGraphCommandTests.swift\|NodeOwnershipCatalogTests.swift\|SidecarV5Tests.swift" Project.swift` + BUNDLE-MAP grep 同命中 |

## 风险与边界

- **投影视图双写漂移**：结构性免疫（KD-1 零同步点）；残余风险 = 有人给 PipelineDocument
  加缓存 var——头注红线 + 纯函数性测试钉死。
- **InsertFromJson 载荷漂移**：`SidecarLayerRecord` spelling 若未来演进，载荷随行
  （同文件同格式）；undo 依赖 stackSnapshot 而非本命令，命令本身是 API 面 + M2-8 前置，
  漂移面有界。
- **蒙版缺口字段 vs MaskGroupSpec 冻结面（06-03 frozen spelling）**：全 Optional
  additive + synthesized encodeIfPresent，canonical JSON 缺席式编码保 stableHash 字节
  parity——T4 断言逐字节钉；若实测 synthesized 编码形态与预期不符（枚举关联值等），
  回退手写 Codable decodeIfPresent（不改既有键）。
- **sidecar v5 与旧档 round-trip**：容忍契约既有（读者 `> current` degrade 不拒载）；
  风险集中在「v4 时代读者读 v5 档」——本仓无旧版本二进制在野，矩阵测试为防御性钉。
- **equalizer→Clarity 位归属争议**：若执行时复核发现 Phase 4 另有 local-contrast 独立
  op，表改一行 + 测试改一行，DECISIONS 记录；校验面零改。
- **Graph/ 新目录**：tuist generate 后 Layers/Library 等既有 target 结构零变化
  （同 target 内新子目录，glob 覆盖）。
- **恢复腿 re-decode 时序（E1）**：触发条件以「sidecar 档 vs 会话缓存」等价判定防
  switch-back 双 decode 退化；re-entrancy 由 same-url 保留 history 既有分支消解
  （KD-5 注记）；若实测首帧→overrides 帧交替出现可感闪烁，后备 = re-decode 就绪前
  保持 identity 帧不动（displayTexture 原子替换既有语义，零新机制）——两形态 AC7
  同表。

## 提交约定

- T1 `feat(core): pipeline document read-only facade`
- T2 `feat(core): node graph command set with identity-preserving undo`
- T3 `feat(iop): node ownership catalog with grade insert validation`
- T4 `feat(core): sidecar schema v5 additive mask and raw override fields`
- T5 `feat(app): persist raw decode overrides in sidecar v5`
- T6 `docs(m2-4): close out plan 1 node model core`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。

## Checker 回注记录（2026-09-30）

checker 判 FAIL（4E+4M）后的本 plan 修订落点：

- **E1 恢复腿时序（KD-5/T5/AC7 重写）**：采纳方案①——恢复腿读到
  `document.rawOverrides != nil` 后经 PipeCoordinator 触发**带 overrides 的
  re-decode**。KD-5 明写三件套：①双 decode 代价声明（首帧 identity 出图 + overrides
  到位二次 decode 替换，PixelPipe cache key 含 RAWTechnicalParams JSON 漂移自动失效）；
  ②pristine 档语义（无 overrides = 单 decode 零 re-decode）；③引用通道 =
  WorkspaceModel→PipeCoordinator 透传按 M2-3-1 既有 attach 缝（`EditorState.attach`
  同款弱引用模式）声明进 files_modified（新增 `WorkspaceHostView.swift` 装配行）+
  KD-5 调用链图。AC7 改走真实 load 链（decode 完成 → 读 sidecar overrides →
  re-decode → 渲染生效断言），禁绕路造假。附触发条件细化（档 vs 会话缓存等价判定，
  防 switch-back 双 decode 退化）与 re-entrancy 注记。
- **E2 测试登记纪律（系统性）**：files_modified 增 `Project.swift`；纪律节新增第 6 条
  （同 commit 登记 Project.swift bundle sources + BUNDLE-MAP 行；App 级 →
  LightamerTestsApp，Core 级 → LightamerTestsLayers）；四个测试文件逐一标注归属
  （PipelineDocumentTests = Layers；NodeGraphCommand/NodeOwnershipCatalog/SidecarV5 =
  App——undo/redo、addModuleToLayer、真 load 链均实例化 EditorState）；T1-T4 验收增
  登记 checkbox；AC11 新增。
- **E4 AC2 闭环**：AC2/T2 增「setGradeMix(0) 后 composite 输出与该层 enabled=false
  bypass 输出像素级相等（容差 0，-0/+0 视相等）」断言；P3 KD-2 同步改引本 AC 编号。
- **M1 编号统一**：全 plan 裁决引用统一为 D-M2-4-CONTEXT-N（已定裁决 D1..D8 标题与
  KD 正文内引全部换算；title 行原「D8」误标所有权裁决，修正为 CONTEXT-8）。
- **M2 AC3 grep 口径**：模式改 `default:` 且文件限定 NodeGraphCommand.swift/
  PipelineDocument.swift（原 `grep "default"` 会误命中注释/缺省字样）。
- **M4 nextLayerName 单源**：规则下沉 Core `LayerStack.nextLayerName(base:)`
  extension（`EditorState.swift:668` 算法 verbatim 搬移），EditorState 两个调用点改
  消费、私有副本删除；KD-2/T2/AC 增对应落法与单源核验。
- M3（`Scripts/test-direct.sh` 头注「六 bundle」陈旧 + bundle glob 漏 IOPParity）属
  M2-4-0 遗留，本 plan 期不动——由修复 commit body 提醒 orchestrator（执行批顺手修）。

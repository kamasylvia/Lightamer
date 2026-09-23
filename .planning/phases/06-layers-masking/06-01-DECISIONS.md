# Plan 06-01 执行期决策（DECISIONS）

> 依据 plan 纪律：执行期决策逐条落账（D-06-01-T* 前缀）。全部为 plan 授权范围内的形态选型，无 CONTEXT 级推翻。

## D-06-01-T1-1：REVERSE 位落 `BlendOptions` OptionSet（枚举旁挂，不 OR 进 rawValue）

- **裁决**：`BlendOptions: OptionSet`（UInt32）承载 `reverse = 0x80000000`（blend.h:89）；`BlendMode` 保持纯槽位表，另暴露 `dtModeSlot`（mask 0xFF）/`dtPackedValue` 投影。层运行时字段 `AdjustmentLayer.blendOptions` 与 mode 并行存储。
- **理由**：dt 把 flag OR 进同一 word 是 C 位域习惯；Swift 侧分离后枚举保持 `CaseIterable`/干净的 rawValue 空间，sidecar 序列化两侧各自独立（mode=Int 槽位、options=UInt32 位），6-2 增补 flag 无需触碰枚举。plan T1 允许「OptionSet 或静态常量——执行期决策形态」。
- **可逆性**：可逆——存储值不变，只是类型重组。

## D-06-01-T3-1：enforceBudget 层档只扫「当前图层平面」；终端/输入腿锚在既有 image tiers

- **裁决**：tier 5 = 当前 image 的 `layerTier != nil` 平面（layerID ≠ base sentinel），tier 内序 = layerChainOutput → compositePrefix → maskPlane（LRU 同档）。base/terminal 命名空间（sentinel 或真实 baseLayer.id 的平面）不进入层档 sweep——当前图 PREVIEW 平面保持 Phase 2-6 的「永不触碰」豁免。
- **理由**：plan 的四档序「终端/输入 > 层链输出 > 前缀 > mask」若把当前图 base 平面纳入层档，会与既有 keep-matrix 契约（当前图 PREVIEW 免疫全部 sweep，MemoryBudgetTests 锁定）直接冲突，且对 D-C3 预览梯子造成零收益的抖动。「终端/输入」的驱逐实际由既有 tier 2（他图 FULL）/tier 4（当前图非 PREVIEW）承担，语义覆盖完整。
- **可逆性**：可逆——6-5 benchmark 若证明当前图 base 平面需要更激进驱逐，在 tier 5 前插入一档即可（纯策略执行器，阈值/档序可注入）。

## D-06-01-T3-2：前缀平面键 = 复用 `PipeCacheKey` + 保留位 `position = -1`（非新 key 类）

- **裁决**：合成前缀 C_k 键 = `(imageID, pipeType, layerID=属主层, position=-1=compositePosition, upstreamHash=⊕(prefixHash_prev, chainHash_k, blendTripleHash_k), roi=窗口)`；mask 平面保留位 `-2`（6-3/6-4 前空档占位）。层链输出键沿用 (layerID, position ≥ 0, levelHash)。
- **理由**：`PipeCache.plane(for:)` 是单字典 actor，新 key 类型意味着第二套字典 + 重复 LRU/账本；保留位负值与链位（从 0 计）天然无碰撞，一行分类函数（`layerTier`）即可分档。upstreamHash 的链式折叠天然编码「编辑 K → K..N 前缀连锁失配、>K 链输出全 hit」。
- **层链输出 position 语义**：每个子 run 的 position 从 0 重计（现 walk 语义），层命名空间（layerID）保证跨层隔离；重排不改任何链键。
- **可逆性**：可逆（键是内存形态，非持久化）。

## D-06-01-T4-1：几何拒绝 = 纯检测器 + driver fatalError（进程内不可测面明示）

- **裁决**：`LayerCompositeDriver.layerGeometryViolation(_ effectiveChain:) -> String?` 为纯函数（可测），`composite` 在任何 GPU 工作前对非 nil 判定执行 fatalError（plan 原文「fatal error 语义」）。拒绝集 = V50Order 槽位 {13.0 lens, 15.0 ashift, 16.0 flip, 17.0 clipping}（由槽位表反查 opName，非字符串硬编码）。
- **理由**：fatalError 无法在 XCTest 进程内断言；纯检测器 + driver 硬前置的组合既保 plan 语义又留出可测面。**挂账**：crop（24.5）/enlargecanvas（16.5）同为几何但不在 D-06-CONTEXT-5 点名的四槽位——维持 plan 字面集，6-5 UI 面核时与 planner 确认是否扩集。
- **可逆性**：检测器扩集是一行常量变更。

## D-06-01-T4-2：子 run 复用 seam = `PixelPipe.runSub`（walk 代码提取共享，语义逐字不动）

- **裁决**：`run()` 的「pieces/levelHash 准备」与「forward walk」提取为 `prepareChain`/`forwardWalk` 私有助手（语句逐字搬移）；新增 `runSub(input:inputROI:instances:decodeHash:metal:layerID:)`；`processRec` base case 在 `subRunInput` 非空时直接返回外部平面（不缓存、不计数）。
- **理由**：层子链/终端段没有 DecodedImage，唯一差异是入口形状；提取比复制 60 行 walk 代码更符合「walk 语义零改动」——两入口现在共享同一实现。层子 run 的 levelHash 以 base 腿的 `decodeParamsHash` 为种子（decode 变更正确失效全部层平面）。
- **附随修复（T6 期间发现）**：`run()` 自动安装的默认 LayerStack 标记 `usesDefaultStack`——同一 pipe 第二次 run 不再翻转命名空间（此前会以新鲜 BackgroundLayer UUID 每轮换键，破坏 MultiResolution 命中快路径）。
- **可逆性**：结构重构，无语义可逆性问题。

## D-06-01-T6-1：sidecar v2 层记录拼写 + `blendOptions` additive 字段

- **冻结拼写（06-01 checkpoint）**：
  ```
  layerStack : { "layers" : [SidecarLayerRecord…] }        // 自下而上
  SidecarLayerRecord {
    "id" : UUID, "kind" : String ("adjustment"), "name" : String,
    "isVisible" : Bool, "enabled" : Bool, "opacity" : Float,
    "blendMode" : Int,                    // 冻结 raw 值空间（D-06-CONTEXT-2）
    "blendOptions" : UInt32,              // ★ 06-01 additive（见下）
    "chain" : [ModuleInstance 冻结拼写],   // paramsHash = decimal String（lock #2）
    "mask" : SidecarMaskSpec?             // { "version" : Int }（payload 6-3/6-4）
  }
  ```
- **★ blendOptions 为何在 plan 拼写之外**：plan T6 的记录字段清单无 REVERSE 载体；运行时 `AdjustmentLayer.blendOptions`（D-06-01-T1-1）若不落盘，用户设置的 REVERSE 在 round-trip 后丢失 = 数据丢失。按冻结纪律以 **optional + decodeIfPresent（缺省 0）** 追加——v1/v2 文档互容，属允许的「optional 字段追加」类演进（与 mask payload 同一节奏）。
- **kind 为 String 拼写**（"adjustment"）：LayerKind 枚举非 Codable；6-7 retouch kind 以新字符串扩展，永不重编。
- **drift 锚**：`driftDetected` 升级为层感知（折叠文档自身 layer 记录：UUID 16B ‖ name UTF8 ‖ isVisible/enabled/opacity bitPattern ‖ blendMode LE ‖ blendOptions LE ‖ 链实例 fold），v1 文档（nil）哈希与 02-06 形态逐位一致。**注意**：哈希折叠的是 `paramsData` 字节 + 属性显式折叠，`paramsHash` 原子本身不入哈希（它是派生值——测试篡改必须打在 paramsData/属性上）。
- **history 层维度**：`HistoryItem.stackSnapshot: LayerStackSnapshot?`（optional decodeIfPresent；sidecar 经 `SidecarLayerStackRecord` 投影——同一冻结拼写两处使用）。`effectiveInstances()` 仅投影 `layerScope == nil` 条目；层条目经 `effectiveInstances(layerScope:)` / `ModuleRegistry.effectiveInstances(layer:)`。
- **可逆性**：ONE-WAY——拼写即格式，后续只加不改。

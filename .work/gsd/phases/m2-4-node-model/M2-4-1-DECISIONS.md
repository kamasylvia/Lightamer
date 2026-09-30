# M2-4-1-DECISIONS — 执行期裁定与签注（plan M2-4-1 收口批）

> 正位：`.work/gsd/phases/m2-4-node-model/M2-4-1-PLAN.md` 的收口产物。
> KD-1..5 全部按 plan 落地执行确认；下列 D-M2-4-1-N 为执行期新增裁定 /
> plan 裁定的复核签注，晨审可推翻（推翻 = 改表一行 + 测试一行，校验面零改）。

## KD 执行确认

- **KD-1（PipelineDocument 纯派生门面）**：照落地。零存储字段、`init(_:)`
  唯一构造面、`nodes` 拼接；同栈两次 init 相等由测试钉死（纯函数证明）。
  头注红线「禁止加任何 var 缓存」在册。
- **KD-2（图命令集 = Core 纯 apply + App 统一入口，undo 靠既有 stackSnapshot）**：
  照落地。映射表单文件承载（`NodeGraphCommand.swift`）；`EditorState.apply`
  恰一条 structure commit（`history_graph_*` 七键族）；undo/redo 复原走既有
  `rebuildLayerStack()` 单路径，UUID 保持由 round-trip 测试钉死。InsertFromJson
  字节复原（id/paramsData/mask verbatim）+ retouch 载荷 badPayload 拒绝在册。
- **KD-3（所有权框架三层切分）**：照落地。Core 零 op 字面量；IOP 表全常量
  （`git grep '"' NodeOwnershipCatalog.swift` = 0 命中）；App 缝只拦 UI 新插，
  加载/undo/复原零校验（宽限执行，M2-5 收窄时只改表）。
- **KD-4（sidecar v5 一原子格式事务）**：照落地。v5 四字段全 Optional
  additive；nil 零漂移（canonical JSON 字节 parity + stableHash parity）由
  SidecarV5Tests 逐字节钉；读者容忍矩阵（v1..v4 档全 nil、`>5` 容忍）在册；
  写者恒发 5。
- **KD-5（RAW overrides 持久化接线 = 既有 load(overrides:) 缝 + 恢复腿
  re-decode）**：照落地。恢复腿（E1 方案①）三件套全实现：①双 decode 代价
  声明（首帧 identity + overrides 到位二次 decode 替换，cache key 漂移自动
  分流）；②pristine 档零 re-decode 零回注；③引用通道 = 双向 attach 缝
  （弱引用，M2-3-1 同款），装配点 `WorkspaceHostView.task`。触发条件细化
  （档 vs 会话缓存等价判定防 switch-back 双 decode）+ same-url 保留 history
  注记均在代码注释在册。`RawDecodePanelView.swift` 零 diff 达成（git 核）。

## D-M2-4-1-1（复核签注）：Clarity 位源 op = equalizer，维持 plan 裁定

Plan KD-3 钦定 `EqualizerModule.opName` → Clarity 位（.drtPost）。执行期复核
发现 Phase 4 确有第二个候选：`LocalContrastModule`（dt bilat，EIGF base +
detail mix，REQUIREMENTS IOP-DETAIL-02「local contrast（等效 clarity）」交付，
其注册头注亦自述 "local contrast (clarity)"）。复核依据 = feature-map §2.1 的
Alcedo 映射行「highpass / equalizer → Clarity（±100 标量，DRT/Post）」（行
247）与「bilat / equalizer — Clarity 是最近对应」（行 216）——研究正本把
equalizer 与 bilat 同列为 clarity 族候选，plan 取 equalizer 与研究一致。
**裁定 = 维持 plan**：equalizer → .drtPost（Clarity 位）；localContrast 留
.grade（作为 grade 内可用的 local-contrast iop，与 dt bilat 语义一致）。
两候选语义都是「细节反差」，M2-5 收窄 18 目录若改判（localContrast 换位）=
表一行 + `NodeOwnershipCatalogTests` 两处 pin 一行，校验面零改。已与 plan
「风险与边界」预授权条款对齐（「表改一行 + 测试改一行，DECISIONS 记录」——
本条即该记录，表未改）。

## D-M2-4-1-2（复核签注）：rawOverrides hash-isolation 理由

`rawOverrides` 不进 `HistoryHash.hash` / `driftDetected` 的判定理由（plan KD-4
要求入册）：它是 **decode 域载体**——overrides 的像素效果已经由
`RAWTechnicalParams` 折进 `decodeParamsHash`（M2-3-3 T4 既有机理，cache key
随 overrides 漂移），hash 再折叠一次是同一信息的二次记账；且 sidecar 的 drift
重算以**文件自身的 decodeParamsHash 为种子**，overrides 变更本来就会随 decode
stamp 传播，不依赖 historyHash。判定形式沿 v3 五元数据字段先例
（`LightamerSidecar.swift` v3 节同款文式）。对照面：蒙版三字段（item
enabled/displayName、spec deletionProtected）是**蒙版域参数**，经
`MaskSpec.stableHash()` 自然折叠（06-05 hardening 既有语义，无新代码）——
两类字段一进一出的分界在 SidecarV5Tests 双向钉死（hash-isolation pair +
set-fields-move 断言）。

## D-M2-4-1-3：deletionProtected 的 sidecar 文件载体缺口（挂账 M2MASK-04）

`MaskSpec.deletionProtected` 按 plan 落在 runtime/snapshot 拼写
（`MaskSpec` 自身 Codable + `LayerStackSnapshot` + `stableHash()` 折叠）。
sidecar 层文件拼写 `SidecarMaskSpec`（`SidecarLayerStack.swift`）**不在本 plan
files_modified 申报集**（AC10 diff 边界纪律），故该字段暂不入 .lra 文件——
蒙版缺口三字段中仅 item 级 enabled/displayName（随 drawn payload verbatim）
随 v5 落盘。挂账：M2MASK-04（删除锁成为用户可编辑面时）给
`SidecarMaskSpec` 补 `deletionProtected` capture/restore 各一行 + 测试一行。
SidecarV5Tests 已用断言注释显式钉住此缺口形态（防静默误判为已持久化）。

## D-M2-4-1-4：SidecarMetadataV3Tests 三处 writer-version pins 4→5

plan 纪律「既有 Sidecar 族测试零改动全绿」与 schemaVersionCurrent=5 的 mandated
bump 在三处硬编码 writer 版本 pin 上不可同时成立（checker 盲点）：字节金样
`"schemaVersion" : 4`、v2→current 加键 diff 的版本行、`testMetadataValuesRoundTrip`
的 `schemaVersion == 4`。处置 = 机械随动（4→5 + 注记更新），**读者容忍语义零
改动**（v4 作为过去版本的 decode 断言原样绿；v1..v4 解码矩阵在 SidecarV5Tests
独立覆盖）。属版本 bump 的不可避免伴随面，非行为性改动，本条备案。

## D-M2-4-1-5：passthrough_spike / testgain 归属 .develop → .grade

Plan KD-3 把「非 UI 两件」列进 .develop 族。执行期实测：testgain 是
`MaskCommandTests` / `LayerE2ERoundTripTests` 现有层链用例的标准模板 op，
.develop 归属使 `addModuleToLayer` 拒绝它们 → 既有 suite 红（与 plan AC5
「既有 suite 全绿」直接冲突）。裁定 = 改列 .grade（默认臂），理由：①面板
缺席（non-UI）是**呈现面事实**，不是**阶段归属事实**——gain/no-op 语义是
阶段无关的 grade 可容纳算子；②AC5 优先级高于 KD-3 的归类清单（清单服务
语义，语义不服务清单）。M2-5 收窄 18 目录时可再裁（无面板 op 是否给独立
dev 位）。表改二行 + `NodeOwnershipCatalogTests` pin 一处，校验面零改。

## D-M2-4-1-6：EditorState.apply 非 throwing + 内联 typed toast 面

Plan KD-2 草图写 `func apply(_ command: NodeGraphCommand) throws`，同时要求
「error → toast 面序（lockedNode 不 toast 静默拦截，其余 toast）」。两者不
可兼得（throws 把错误处理推给每个 UI 调用点 → 漏 catch 即崩，违「不崩、
不静默」）。裁定 = `apply` 非 throwing：内部 `do/catch` + 对
`NodeGraphError` **穷举 switch 无 default**（lockedNode → 静默；其余四例 →
D-26 toast），类型化错误面仍由 Core `apply(to:)` 承载供测试断言。
穷举纪律核验：`git grep "default:" NodeGraphCommand.swift PipelineDocument.swift`
零命中 + 两处消费者 switch 编译穷举。

## D-M2-4-1-7：AddClean 默认名 base = Core 常量「Color Grade」

Plan KD-2 钉 AddClean 默认名「Color Grade N」且 M4 钉 base 由调用方传
（Core 不持本地化键）。命令本身无 base 参数，故 Core `apply` 以
`defaultGradeName = "Color Grade"` 常量过 `nextLayerName(base:)`（序数 +
碰撞清扫单源算法不变）；M4 的 base 注入面由 `LayerStack.nextLayerName(base:)`
签名承载（App 两个调用点传 `layer_default_name` 本地化值，私有副本已删）。
P3 面板若需本地化 AddClean 名，扩展点 = 命令增加 base 载荷或 UI 层先改名。

## D-M2-4-1-8：updateRawOverrides = 仅调度写（无第二镜像）

Plan 写「新增 updateRawOverrides(_:)（内存文档 + 既有 throttle 写）」。落地
取「会话 carrier 即内存真相」形态：`makeSidecarDocument` 直读
`workspace.rawDecodeOverrides(for:)`，coordinator 不另持副本（双镜像 = 漂移
温床，L 系列教训）；`updateRawOverrides` 因此收缩为「守卫 current url +
`scheduleSidecarWrite()`」。恢复腿回注走 `restoreSessionOverrides`（绕开
透传钩——文档是该值的来源，回写 echo 会在 identity 首帧 stamp 下调度一次
冗余 sidecar 写）。

## 执行期观察（非缺陷，登记备查）

- **同图 re-decode 的层栈投影丢失**（pre-existing）：`EditorState.load` 每次成功
  decode 重建空 `LayerStack`，same-url 重入不重放 restore——M2-3-3 T4 面板
  re-decode 路径既有行为，T5 恢复腿复用同链即继承之（history 含 stackSnapshot
  不丢数据，undo/redo/jump 可重建）。本 plan diff 面纪律（KD-5 声明面之外零
  改动）不允许顺手修；M2-4-2/P3 节点面板 plan 若裁「re-decode 保层栈」，改点 =
  `EditorState.load` 的 same-url 保栈分支，一行 guard。
- **isDecoding 指示灯在 re-decode 交叠窗可能提前熄灭**：decodeTask#1 的 defer
  与 decodeTask#2 的置位竞争，视觉面 = PREVIEW 双级 busy 短暂缺席（既有
  load-over-load 语义，面板路径同款），不新机制。

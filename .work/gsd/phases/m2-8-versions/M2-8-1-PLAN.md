---
phase: m2-8
plan: "M2-8-1"
title: "版本模型核（wave 1）——sidecar v7 additive 双可选键（versions/activeVersionID，active 链续住冻结 history 键，D-M2-8-CONTEXT-11）+ VersionCoordinator 旁挂编排与链 swap（EditorState.history 唯一链真相源 + rebuildLayerStack 单路径复用，D-M2-8-CONTEXT-4/5）+ .lalb version_ref 投影表激活（migration v2→v3 + replaceVersionRefs 整表 reconcile + 注入式投影 sink，D-M2-8-CONTEXT-1）"
wave: 1
depends_on: ["M2-7"]
autonomous: true
requirements: [M2VER-01, M2VER-02, M2VER-03]
files_modified:
  - LightamerCore/Sources/Sidecar/LightamerSidecar.swift   # 修改：schemaVersionCurrent 6→7（头注释 v7 节）+ SidecarVersionRecord（新建 Codable，chain 复用 {items,position} 冻结拼写）+ 双可选键 decodeIfPresent/encodeIfPresent + SidecarHistoryItemRecord/SidecarHistoryRecord private→internal（版本链复用同一份 item 编码器——CONTEXT Specific Ideas）
  - App/Sources/Lightamer/State/VersionCoordinator.swift   # 新建：@Observable 旁挂协调器——VersionSlot(id/name/createdAt/updatedAt/chain?)/slots/activeVersionID + 三命令（createFromScratch/branchFromCurrent/switch(to:)）+ rename/remove + materialize-on-first-create + 投影 sink（注入式，Sessions 模式 nil 跳过——L036）
  - App/Sources/Lightamer/State/EditorState.swift          # 修改（最小半径）：installVersionChain(_:) 面（history swap + rebuildInstances + rebuildLayerStack——既有单路径，零新投影）+ versions 挂点（coordinator 弱回引 attach，pipeCoordinator 同款）
  - App/Sources/Lightamer/State/PipeCoordinator.swift      # 修改：makeSidecarDocument 版本两键投影（active 链在 history 键不双写 + touchActive）+ restore 腿 hydrate（versions 解码 → coordinator 装载 + dangling activeVersionID typed degrade）+ 版本动作 scheduleWrite 触发
  - LightamerCore/Sources/Library/LibrarySchema.swift      # 修改：schemaVersion 2→3 + createVersionRefTableSQL/idx_version_ref_element + migrate v2→v3 slot（幂等 CREATE IF NOT EXISTS）+ apply() DDL 清单追加 + reservedTableNames 收窄为三名（version_ref 移出）+ 头注释/预留注释节更新（reduced DDL 签注：无 head_commit_hash——OQ-2-A 无 DAG）
  - LightamerCore/Sources/Library/LibraryStore.swift       # 修改：replaceVersionRefs(elementID:rows:)（单事务 DELETE+INSERT 整表 reconcile 投影——versionRefRow 结构落 Core）
  - App/Sources/Lightamer/UI/Shell/EditorWorkspaceShellView.swift # 修改（最小半径）：loadCurrentImage 的 row.id 注入点——projectStore 非 nil 时装配 VersionProjectionSink（elementID + LibraryStore），切图/关闭清空
  - Project.swift                                          # 修改：新测试文件登记（bundle 无 glob——checker E2 纪律）
  - Tests/LightamerTests/SidecarV7Tests.swift              # 新建（APP——SidecarV5Tests/DrtSidecarTests 同位先例）：v7 字节形 pin + v6 零漂移 + historyHash 版本结构零折叠负测 + dangling degrade
  - Tests/LightamerTests/VersionSwapTests.swift            # 新建（APP——真链实例化 EditorState）：materialize/branch 时点/switch 往返字节忠实/remove 边界/pristine 收窄边界
  - Tests/LightamerTests/LibrarySchemaTests.swift          # 修改：负测翻面（version_ref 现应存在，余三名仍负）+ v2→v3 迁移测试（含 pre-migrate.bak 快照真实触发）
  - Tests/LightamerTests/LibraryStoreTests.swift           # 修改：replaceVersionRefs round-trip + reconcile 删除面 + FK CASCADE
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt # 修改（checker E2）：两新测试文件登记行 + 增行记录注
  - .work/gsd/phases/m2-8-versions/M2-8-1-SUMMARY.md       # 新建（收口任务）
  - .work/gsd/phases/m2-8-versions/M2-8-1-DECISIONS.md     # 新建（收口任务）
  - .work/GOAL-STATE.md                                    # 续接点追加（收口任务）
  - .work/LESSONS.md                                       # 如踩坑
---

# Plan M2-8-1 — 版本模型核（sidecar v7 + 链 swap + version_ref 投影激活）

> **性质**：数据模型 + 编排 plan——App UI 零改动（Versions 面板/历史行升级/Copy Adjustments
> 归 P2/M2-8-2）。三块交付：①**sidecar v7 additive**——双可选键 `versions` +
> `activeVersionID`（D-M2-8-CONTEXT-11 落地：active 链续住 FROZEN `history` 键，版本链
> 复用既有 `{items,position}` 拼写，nil 键缺席零漂移——v5/v6 双先例）；②**VersionCoordinator
> 旁挂编排**——版本元数据 + 链 swap 三命令，`EditorState.history` 保持唯一链真相源
> （D4 投影复用，零重建），切换即时性 = swap + `rebuildLayerStack()` param 重放（D5，
> 同图切版本零重新解码）；③**`.lalb version_ref` 投影表激活**——migration v2→v3 走
> KD-2 缝（pre-migrate 快照已活）+ `replaceVersionRefs` 整表 reconcile（OQ-1-A；
> `edit_commit/image_edit_state/pipeline_root` 维持预留，负测只翻 version_ref 一名）。
> 规格锚点 = D-M2-8-CONTEXT-1..12（**全部已裁决，不得重开**）+ Feature-map §6.2/§6.3 +
> REQUIREMENTS M2VER-01/02/03。**降级条款未触发**：盘点实测迁移缝已活
> （`ProjectFileStore.dispatchSchema` v1→v2 先例）+ open 路径 row.id 注入点现成
> （`EditorWorkspaceShellView.loadCurrentImage`）——激活成本不过高，按裁决全量激活。
>
> **执行期悬决销账**（CONTEXT 预告三件，本 plan KD 内钉死、DECISIONS 签注）：版本 swap
> 的 sidecar 写原子序（KD-3）、`version_ref` upsert 触发位（KD-5）、pristine 不变量
> 收窄的边界测试（KD-6）。

## 已定裁决（不得重开）

- **D-M2-8-CONTEXT-1（OQ-1 A）**：双轨——sidecar v7 = 真身（每片 .lra 自足，Sessions
  全功能），`.lalb` 仅激活 `version_ref` 一表为投影；「.lra 缺席」收窄为「**缺席 =
  观感 pristine（无编辑且无版本结构）**」，投影判定面（items/position）零改动。
- **D-M2-8-CONTEXT-2（OQ-2 A）**：v1 简化——版本 = 独立线性事务链（`HistoryStack`
  值拷贝），**不落 hash commit 图**（`edit_commit/pipeline_root` 继续预留）。ROADMAP
  「双亲=分支/合并」字面收窄 = **晨审专项追认项①**。
- **D-M2-8-CONTEXT-3（OQ-3 A）**：入口子集 = 从原始态新建 + branch from current +
  rename/remove；**fork-from-root 并入新建**（无 DAG 下同型）。M2VER-02「fork from
  root」字面收窄 = **晨审专项追认项②**。
- **D-M2-8-CONTEXT-4（OQ-4 A）**：现有线性 `history` = active 版本事务流本体，零重建；
  `HistoryItem` FROZEN CodingKeys 零改动；v7 注释将 `history` 键语义升级为「active 版
  本链」，v6 读者降级拿到最后活跃版本观感（可接受 degrade）。
- **D-M2-8-CONTEXT-5（OQ-5 A）**：无落库材质化——active 链常驻内存 + param 重放；
  `image_edit_state` 与 `edit_commit/pipeline_root` 同列预留。
- **D-M2-8-CONTEXT-11（OQ-11 A）**：v7 = `versions: [SidecarVersionRecord]?`（每记录 =
  id/name/createdAt/updatedAt + 非活跃链 items+position）+ `activeVersionID: String?`；
  写入时 active 链在 `history` 键、其元数据在 `versions[]`（**items 不双写**）；
  `schemaVersionCurrent` 6→7；版本结构**不进 historyHash 折叠**（负测钉死）。
- **M2VER-03 字面**：「切换即时」= KD-2 的 param 重放语义；「ImageEditState 材质化」
  = D5 不落库（需求侧以内存态兑现，翻账注记）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 SidecarVersionRecord：链拼写复用，nil 双键零漂移

```swift
// LightamerSidecar.swift（同文件——sidecar 拼写唯一落点纪律）
public struct SidecarVersionRecord: Codable, Sendable, Equatable {
    public var id: UUID                       // 版本身份（activeVersionID 引用它）
    public var name: String                   // 「版本 N」默认名（P2 面板消费）
    public var createdAt: Date
    public var updatedAt: Date
    public var chain: SidecarHistoryRecord?   // nil = ACTIVE 版本（items 在 history 键）
    // CodingKeys: id/name/createdAt/updatedAt/chain；chain = 冻结 {items, position}
}
```

- **`SidecarHistoryItemRecord`/`SidecarHistoryRecord` private→internal**（零拼写改动，
  纯 access level——L042「先查 access level」先例）：版本链与非版本链**同一份 item
  编码器**，字节同形（CONTEXT Specific Ideas 字面）。改 access level 的理由入 commit
  body。
- **v7 additive 三件套照抄 v5/v6 惯例**：decode `decodeIfPresent`（v6 文档读 nil）；
  encode `encodeIfPresent`（nil 版本面 = 键缺席——`rawOverrides/displayTransform`
  「write ONLY when present」正本 `:418-424` 同款）；`schemaVersionCurrent = 7`。
- **字节形 pin（KD 必答——逐字节 parity 先例）**：
  ①v6 形文档（无两键）decode→re-encode **逐字节相等**；
  ②v7 writer 全 nil 版本面输出 = v6 writer 输出**逐字节相等除 schemaVersion 位**；
  ③v7 带版本文档 round-trip 字节忠实（SidecarV7Tests 三断言）。
- **historyHash 零折叠负测（KD 必答）**：同一 active 链 + 同 decode 哈希，篡改 JSON
  中版本元数据（改 `name`）→ `driftDetected == false`（版本元数据非像素语义，CONTEXT
  OQ-11 字面）。hash 函数签名零改动（版本结构进不了公式 = 结构性保证，测试钉行为面）。
- **v6 读者降级**（注释 pin，不可机检不立测）：旧二进制 JSONDecoder 忽略未知键 → 拿
  到 active 版本观感（`history` 键 + 最后写入的 instances）。

### KD-2 VersionCoordinator：旁挂编排 + swap 单路径 + 切换即时语义

```swift
// App/Sources/Lightamer/State/VersionCoordinator.swift
struct VersionSlot: Identifiable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var chain: HistoryStack?   // nil = ACTIVE 槽（真相源 = EditorState.history）
}

@Observable @MainActor final class VersionCoordinator {
    private(set) var slots: [VersionSlot] = []      // 空 = 隐式单版本（面板空态，P2 消费）
    private(set) var activeVersionID: UUID?
    weak var editorState: EditorState?              // attach（pipeCoordinator 同款弱回引）
    var projection: VersionProjectionSink?          // 注入（KD-5）；Sessions 模式 nil
    // 命令：createFromScratch / branchFromCurrent / switch(to:) / rename(_:to:) /
    //       remove(_:) —— 每命令尾 = syncProjection() + 通知 coordinator 写 sidecar
}
```

- **materialize-on-first-create**：`slots` 空时首个创建命令先把当前隐式链物化为
  「版本 1」（新 UUID/name/createdAt=updatedAt=now/chain=nil-marked-active），再落新
  版本。隐式链在 `versions[]` 物化前不落任何键（v6 字节形保持）。
- **swap 序（KD 必答——写原子序悬决销账）**：单条 MainActor 同步状态转移 =
  「outgoing 槽.chain ← EditorState.history（值拷贝）→ editorState.installVersionChain
  (target.chain) → target.chain = nil → activeVersionID ← target.id」，随后一次
  `scheduleSidecarWrite()`——`makeSidecarDocument()` 读 **post-swap 快照**一次，经
  SidecarStore tmp 原子晋升落盘。**磁盘上从不存在中间态**（单文档原子写覆盖双键一致
  性）；swap 内无任何 await 点（UI 连点安全——两次 swap 合并进同一 debounce 写）。
- **installVersionChain（EditorState 新面，最小半径）**：
  `history = chain; rebuildInstances(); rebuildLayerStack()`——**与
  restoreFromSidecar/performUndo 同一条 rebuild 单路径**（rebuildLayerStack M2NODE-02
  identity-preserving），零新投影代码。baseInstances 不动（pristine 种子跨版本共享）。
- **切换即时语义（KD 必答——activeVersionID 语义钉死）**：切版本 = 链 swap +
  `rebuildLayerStack()`（纯 param 投影重放，毫秒级）+ PipeCoordinator 通知链
  （`historyDidChange()` 重渲染 + `currentLayerStack` 同步）+ **DRT carrier 重同步复用
  `syncDrtCarrierWithHistory()`**（swap 后由 coordinator 经 PipeCoordinator 面触发——
  M2-6-3 undo/redo 恢复腿同款）。**decode 纹理由 PipeCache 承载，同图切版本零重新解码**
  （CONTEXT 发现 7）；**rawOverrides 不随版本换**（image-global decode 域，换 = 触发
  重解码，违「切换即时」）——KD 签注为有意排除面。
- **branchFromCurrent 快照时点（KD 必答）**：拷贝源链 `items[0...position]`
  （**redo 尾不带**）为新区链，position = 拷贝尾索引；时点 = 命令执行瞬间的
  `EditorState.history.position`（非「链末尾」——跳回中途 branch 时 redo 尾留在源版本）。
- **createFromScratch**：新空链（position -1）——编辑器呈现 pristine-of-chain
  （base 种子渲染）。**创建即激活**（Alcedo 语义推定，DECISIONS 签注）。
- **remove 语义**：确认对话框归 P2（本 plan 只落命令面）；active 版本被删 → 切到列表
  首项（OQ-3 字面）；**删除唯一版本 → 回隐式单版本态**（slots 清空 + activeVersionID
  nil，当前链保持为 history——版本结构消失、编辑不丢）。
- **updatedAt 触碰规则**：链内容变更（history move 发生时的 write 面 touchActive）+
  版本元数据操作（rename/switch-in）。纯内存时间戳，不进 hash。
- **dangling activeVersionID typed degrade**（restore 腿）：activeVersionID 无匹配槽 →
  log error + **版本结构整体丢弃**（slots 清空，`history` 键保持为链）——用户编辑
  永不丢，结构可重建；SidecarV7Tests 负测钉。

### KD-3 .lalb version_ref：reduced DDL + 幂等迁移 + 整表 reconcile

```sql
CREATE TABLE IF NOT EXISTS version_ref (
  version_id TEXT PRIMARY KEY,      -- .lra 版本 UUID string（.lra↔.lalb 关联键）
  element_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  created_at_unix INTEGER NOT NULL,
  updated_at_unix INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_version_ref_element ON version_ref(element_id);
```

- **reduced DDL 签注**：预留注释的 `head_commit_hash` 列**不激活**（OQ-2-A 无 DAG，
  无 commit hash 可写）；版本 active 态不投影（`image_edit_state` 预留中）。DDL 与
  预留注释的拼写偏离（列集收窄）入 DECISIONS。
- **migration v2→v3**：`LibrarySchema.schemaVersion = 2→3`；migrate slot
  `if from <= 2 && to >= 3 { createVersionRefTable(on:) }`——CREATE IF NOT EXISTS 双幂
  等（表+索引），部分迁移快照重跑干净（default_look_pending slot 同款）。`apply()` DDL
  清单追加同两语句（fresh create 路径 v3 直落）。**KD-2 缝零改动**：
  `ProjectFileStore.dispatchSchema` 的 stored<schemaVersion 臂自动走 pre-migrate 快照 +
  migrate（v1→v2 先例的结构性收益，本 plan 不触 ProjectFileStore）。
- **reservedTableNames 收窄为 `["edit_commit", "image_edit_state", "pipeline_root"]`**；
  `LibrarySchemaTests.testReservedMiniGitTablesDoNotExist` 翻面 = version_ref 移入
  存在性断言（新建存在 + 列序 `PRAGMA table_info` 对照 reduced DDL），余三名负测
  保持。
- **`LibraryStore.replaceVersionRefs(elementID:rows:)`**：单 `withWriteBatch` 事务
  DELETE（该 element 全部行）+ INSERT 当前集——**整表 reconcile 投影**（幂等、无增量
  漂移面；行集 = `.lra` 版本槽投影，可随时从真身重建）。`assertImageExists` typed
  notFound（updateProjection 同款）。`versionRefRow` 结构落 Core（Sendable 值）。
  FK CASCADE：image 删除连带清投影行（DDL 语义，测试钉）。

### KD-4 makeSidecarDocument / restore 腿扩展（PipeCoordinator 最小半径）

- **写腿**：`makeSidecarDocument()` 追加两参数——`versions:`（coordinator.slots 非空时
  映射 `[SidecarVersionRecord]`：active 槽 chain=nil，非 active 槽 chain=其链）+
  `activeVersionID:`（UUID string 或 nil）。写前 `coordinator.touchActive()`（updatedAt
  触碰——见 KD-2）。**items 不双写**（active 链只在 history 键——OQ-11 字面，测试钉：
  同一 items 数组字节不出现在两处）。
- **读腿**（restoreSidecar 扩展）：`document.versions` 非 nil → coordinator hydrate
  （非 active 槽装载链、active 槽标记）+ `restoreFromSidecar` 照旧（active 链）；nil →
  no-op（v6/隐式单版本）。dangling degrade 见 KD-2。
- **版本动作的 scheduleWrite**：三命令 + rename/remove 尾部经 PipeCoordinator 面触发
  `scheduleSidecarWrite()`（低频用户动作——CONTEXT OQ-9 字面「版本创建/切换动作补触发」）。

### KD-5 投影 sink：注入式，Sessions 模式零引用

```swift
// VersionCoordinator.swift（App）
struct VersionProjectionSink: Sendable {
    let elementID: Int64          // images.id（.lalb 行）
    let store: LibraryStore
}
```

- **装配点 = `EditorWorkspaceShellView.loadCurrentImage`**（row.id 现成持有——实测
  `:175-196` defaultLookPending 同位）：`projectController?.projectStore` 非 nil 时
  构造 sink 注入 coordinator；切图/项目关闭清空（nil）。**视图 body 零 LibraryStore
  直读**（L036：装配根读一次显式注入）；Sessions 模式 projectStore 恒 nil = 投影自然
  跳过。
- **触发位（KD 必答——upsert 触发位悬决销账）**：版本命令尾 + restore hydrate 尾各
  `syncProjection()` 一次（整表 reconcile 幂等，重复调用无成本）。投影失败 = log 不
  toast（投影非真相，可重建；不阻塞编辑）。

### KD-6 pristine 不变量收窄的边界测试（KD 必答）

- **收窄表述**：「.lra 缺席 = 观感 pristine（无编辑且无版本结构）」——版本创建（空链
  新版本）即触发 scheduleWrite，**.lra 可在零编辑时诞生**（CONTEXT 发现 5）。
- **边界测试两枚**：
  ①App 级（VersionSwapTests）：空链版本创建 → flushNow → .lra 文件存在且 decode 回
  `history.position == -1`、versions 含 1..2 槽（零编辑 + 版本结构共存）；
  ②投影判定面回归（Core 级，SidecarV7Tests）：has_edits/pristine-decode 的判定输入
  （`history.effectiveInstances().isEmpty`）不被版本结构翻转——空 active 链 + 非空
  versions → 投影仍判「无编辑」。
- **明确不做**：SessionIndexStore/MetadataService 的 `sidecar_present` 联动面本 plan
  不触（「.lra 存在∧has_edits=0」新组合的下游消费面列风险节观察）。

## read_first

1. `.work/gsd/phases/m2-8-versions/M2-8-CONTEXT.md`——裁决正本（D1..D12 + 三条事实基线
   + Reusable Assets 表 + 发现 1-9）。
2. `LightamerCore/Sources/Sidecar/LightamerSidecar.swift`——v6 正本 + additive 三件套
   惯例（`:154` version 常量、`:418-424` write-ONLY-when-present、`SidecarInstanceRecord`
   internal 先例）+ `driftDetected` 折叠公式。
3. `LightamerCore/Sources/Pipe/History/HistoryStack.swift`——链语义（jump 保尾/commit
   截尾）+ FROZEN CodingKeys + pasteEpochScope/drtDocumentScope 标记族。
4. `App/Sources/Lightamer/State/EditorState.swift`——`restoreFromSidecar`/`rebuildInstances`
   /`rebuildLayerStack`（`:1070` 单路径）+ attach 弱回引模式。
5. `App/Sources/Lightamer/State/PipeCoordinator.swift`——`makeSidecarDocument`（`:1160`）
   + restore 腿 + `syncDrtCarrierWithHistory`（`:646`）+ `scheduleSidecarWrite`。
6. `LightamerCore/Sources/Library/LibrarySchema.swift`——schemaVersion=2 冻结面 + migrate
   slot 形 + reservedTableNames + 尾部预留注释块；`ProjectFileStore.swift:131-152`——
   dispatchSchema KD-2 缝（本 plan 零触）。
7. `LightamerCore/Sources/Library/LibraryStore.swift:405-445`——withWriteBatch/
   assertImageExists/updateProjection 形态（replaceVersionRefs 同款）。
8. `Tests/LightamerTests/LibrarySchemaTests.swift:254-263`——负测翻面落点；
   `DrtSidecarTests.swift`——字节形 pin 先例；`Scripts/test-direct.sh` 头注——跑法。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits 全英文、subject ≤72 字符祈使句、
   body 写 what+why + 同批 md 清单）；只 add 本任务申报文件；**不 push**；git add 用
   `.work/gsd/...` 真路径；多段 message 用 `-F` 文件（L040）。
2. **构建纪律**：`caffeinate -dis` 包裹一切构建；不加 `-derivedDataPath`；**tuist
   generate 必须落在全部新文件落盘之后**（L041——本 plan T1/T2 新测试文件同批 generate
   一次即可）。
3. **测试纪律**：单测命令 = `Scripts/test-direct.sh '<Class>'`；判据 = Executed 计数行
   + failures 行双读（L028）。**回归基线 = 2525/16skip/0fail**；每任务全套 suite 绿。
   **全套跑法 = `Scripts/test-direct.sh --all`（七 bundle），跑前向 orchestrator 报备**
   （--all 报备制）；RSS ≥8G = MEMFAIL 机检，触发记 E3 不自行重试超两次；定向轮残留
   目录清盘纪律（L049）。在案 flake 隔离复跑 ×3 归因入 SUMMARY。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
5. **架构红线**：`HistoryStack.swift`/`HistoryHash.swift` **零 diff**（HistoryItem
   FROZEN CodingKeys + 折叠公式不动——版本结构不进 hash 是 KD-1 负测的行为面，非代码
   面）；`ProjectFileStore.swift` **零触**（KD-2 缝已活，结构性收益）；`PixelPipe.swift`
   /`PipeCacheKey.swift`/`LayerCompositeDriver.swift` 零触；EditorState 改动半径 =
   installVersionChain 面 + versions 挂点（rebuild 单路径零改）；PipeCoordinator 改动
   半径 = makeSidecarDocument 两键 + restore hydrate + 版本动作写触发；`.xmp` 永不读写
   删；GPL 参考只读（Alcedo 代码不入库）。
6. **测试登记纪律（checker E2）**：两新测试文件**同 commit** 登记——①`Project.swift`
   对应 bundle sources 显式清单；②BUNDLE-MAP 增行 + 增行记录注。归属：
   SidecarV7Tests = **APP**（SidecarV5Tests/DrtSidecarTests 同位）；VersionSwapTests =
   **APP**（真链实例化 EditorState）。运行期总数基线相应上移（对账以 BUNDLE 行为准）。
7. **checker 四条（M2-4 教训移植，逐条对表）**：①真链验收禁绕路造假（E1）——swap/
   restore AC 走真实 EditorState + SidecarStore 实例链，禁测试后门直捅存储；②登记闭环
   （E2）——纪律 6；③语义断言落可观测级（E4）——字节形 pin 到逐字节、dangling 到
   typed degrade 行为、投影 reconcile 到行集相等；④收口边界核对（M 级）——T4
   `git diff --stat` 逐文件对表 + 消费点单源核验（版本两键唯一写点 = makeSidecarDocument）。
8. **收口核对**：T4 diff 边界 == front-matter files_modified，越界 = 违约。

## Tasks

### T1 sidecar v7 additive + SidecarV7Tests

- **read_first**：上列 1/2/3/8。
- **action**
  1. `LightamerSidecar.swift`：KD-1 全量——`schemaVersionCurrent = 7` + 头注释 v7 节
     （含「history 键语义 = active 版本链」升级 + v6 读者降级注）+
     `SidecarVersionRecord` + 双可选键 decode/encode + 两 record access level internal
     化（拼写零改）。
  2. 新建 `Tests/LightamerTests/SidecarV7Tests.swift`：KD-1 三字节形断言（v6 round-trip
     逐字节 / v7 全 nil = v6 形除版本位 / v7 带版本 round-trip）+ historyHash 篡改负测
     （KD-1）+ dangling activeVersionID degrade 面（decode 层输入，行为断言归 T2 真链）
     + pristine 判定面回归（KD-6 ②）+ UInt64 零新增面确认（版本记录无 hash 字段——
     L013 不涉及，注释声明）。
  3. `Project.swift` 登记 + BUNDLE-MAP 增行（APP）+ `tuist generate`（T2 文件未落盘前
     只登记 T1 文件——L041：generate 在本任务新文件落盘后跑）。
- **验收标准**
  - [ ] 三字节形断言 + hash 负测 + pristine 判定面回归全绿；既有 SidecarV5Tests/
        DrtSidecarTests/SidecarMetadataV3Tests 零改动全绿。
  - [ ] `HistoryStack.swift`/`HistoryHash.swift` 零 diff（机检 `git diff --name-only`）。
  - [ ] 登记闭环（Project.swift + BUNDLE-MAP 双命中）。
  - [ ] 全套回归 `0 fail`（基线 2525 + 新增）。

### T2 VersionCoordinator + 链 swap + restore 腿 + VersionSwapTests

- **read_first**：上列 1/4/5。
- **action**
  1. 新建 `App/Sources/Lightamer/State/VersionCoordinator.swift`：KD-2 全量
     （VersionSlot/三命令/rename/remove/materialize/dangling degrade/投影 sink 壳——
     sink 装配归 T3，本任务类型与调用面先落）。
  2. `EditorState.swift`：`installVersionChain(_:)` + versions 挂点（attach 弱回引）。
     **rebuild 单路径零改**。
  3. `PipeCoordinator.swift`：KD-4 写腿两键 + touchActive + restore hydrate + 版本动作
     scheduleWrite 触发面（coordinator → coordinator 通知，Task 弱回引同款）。
  4. 新建 `Tests/LightamerTests/VersionSwapTests.swift`（真链——checker E1）：
     materialize-on-first-create（首创建 = 版本1+版本2 双槽）/branch 快照时点（跳回
     中途 branch：redo 尾留源版本）/switch 往返字节忠实（编辑→切走→切回→链 items+
     position 逐字节相等）/remove active 切首项/remove 唯一版本回隐式/dangling degrade
     （手造 doc → slots 丢弃 + history 保持）/KD-6 ①（空链版本 .lra 诞生 + position==-1）
     /切换触发 scheduleWrite（flushNow 后文件反映 post-swap 态）/DRT carrier swap 后
     重同步（effectiveDrtRecord 驱动）。
  5. Project.swift/BUNDLE-MAP 登记 + `tuist generate`（两新文件齐后）。
- **验收标准**
  - [ ] VersionSwapTests 全绿（真链，无存储后门）；`rebuildLayerStack`/`rebuildInstances`
        零 diff（机检——单路径复用证明）。
  - [ ] 既有 HistoryStack/undo/redo/sidecar restore 测试零改动全绿（D4 零重建证明）。
  - [ ] 登记闭环；全套回归 `0 fail`。

### T3 .lalb version_ref 激活 + 投影 sink 装配 + LIB 测试

- **read_first**：上列 1/6/7。
- **action**
  1. `LibrarySchema.swift`：KD-3 全量（schemaVersion 3 + DDL/索引 + migrate slot +
     apply 追加 + reservedTableNames 收窄 + 头注释 v3 节 + 尾部预留块 version_ref
     「ACTIVATED M2-8（reduced DDL）」改注）。
  2. `LibraryStore.swift`：`replaceVersionRefs(elementID:rows:)` + `versionRefRow`。
  3. `EditorWorkspaceShellView.swift`：loadCurrentImage 注入点（KD-5；切图清空）。
  4. `LibrarySchemaTests.swift`：负测翻面（version_ref 存在 + 列序对照 + 余三名仍负）
     + v2→v3 迁移测试（v2 包升级 → 行完好 + user_version==3 + `pre-migrate.bak` 真实
     产生断言——快照 hook 首个 v2→v3 消费者）+ fresh create v3 直落断言。
  5. `LibraryStoreTests.swift`：replaceVersionRefs round-trip（写→读回行集相等）+
     reconcile 删除面（旧行清除）+ FK CASCADE（image 删 → 投影行删）+ notFound typed。
  6. VersionSwapTests 追加投影面：sink 注入下版本命令后行集 reconcile 相等断言
     （内存 fake store 或内存库——LibraryStore 可指向临时 .lalb，真链优先）。
- **验收标准**
  - [ ] 翻面负测 + 迁移 + 快照 hook + Store 四面全绿；`ProjectFileStore.swift` 零 diff
        （机检）。
  - [ ] Sessions 模式零回归（现有全 suite 不含 sink 路径——App bundle 全绿即证）。
  - [ ] 全套回归 `0 fail`。

### T4 收口——SUMMARY/DECISIONS + 续接点

- **read_first**：本 plan AC 表 + `.work/GOAL-STATE.md` 续接点节。
- **action**
  1. AC 逐条机检 + 全套回归终跑（`--all` 前报备；计数/秒数/bundle 峰值入 SUMMARY）。
  2. 落盘 `M2-8-1-SUMMARY.md`（测试数变化/字节形 pin 实测值/迁移实测/v7 键形 JSON 样例）
     + `M2-8-1-DECISIONS.md`（三悬决销账签注：swap 原子序 KD-2 / upsert 触发位 KD-5 /
     pristine 边界 KD-6 + reduced DDL 偏离 + 创建即激活 + rawOverrides 不随版本换）。
  3. `.work/GOAL-STATE.md` 续接点追加（M2-8-1 完成 + 下一步 = M2-8-2）；LESSONS 如踩坑。
  4. `git diff --stat` 核对文件边界与 front-matter 一致（纪律 8）。
- **验收标准**
  - [ ] AC 表全绿；SUMMARY/DECISIONS/GOAL-STATE 同批落盘；diff 边界无越界文件。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | v7 三字节形断言（v6 round-trip 逐字节 / 全 nil = v6 形除版本位 / 带版本 round-trip）+ v6 既有 pin 测试零改动全绿 | SidecarV7Tests + 既有三 sidecar 测试文件 |
| 2 | historyHash 版本结构零折叠：篡改版本元数据 `driftDetected == false`；`HistoryHash.swift`/`HistoryStack.swift` 零 diff | SidecarV7Tests + `git diff --name-only` |
| 3 | swap 真链：materialize / branch 快照时点（redo 尾留源）/ switch 往返字节忠实 / remove 两边界 / dangling typed degrade 全绿 | VersionSwapTests |
| 4 | 切换即时：swap 后 `rebuildLayerStack` 单路径零 diff + DRT carrier 重同步 + 零重新解码（无 decode 请求面触发断言） | VersionSwapTests + `git diff` EditorState 半径 |
| 5 | pristine 收窄：空链版本 .lra 诞生且 position==-1（KD-6 ①）；投影判定面不被版本结构翻转（KD-6 ②） | VersionSwapTests + SidecarV7Tests |
| 6 | items 不双写：active 链字节只在 `history` 键（文档 JSON 无重复 items） | SidecarV7Tests |
| 7 | version_ref 激活：v2→v3 迁移 + pre-migrate.bak 真实产生 + fresh v3 直落 + 负测翻面（余三名仍负）+ 列序对照 reduced DDL | LibrarySchemaTests |
| 8 | replaceVersionRefs：round-trip / reconcile 删除 / FK CASCADE / typed notFound + 版本命令投影 reconcile 相等 | LibraryStoreTests + VersionSwapTests |
| 9 | 注入式投影：视图 body 零 LibraryStore 直读；Sessions 模式（projectStore nil）零引用 | `git grep` EditorWorkspaceShellView body + App suite |
| 10 | 全套回归 0 fail，计数 ≈ 2525 + 30..38 | test-direct.sh --all BUNDLE 行双读 |
| 11 | diff 边界 == 申报文件集；ProjectFileStore/HistoryStack/HistoryHash 零触 | `git diff --stat` 逐文件核对 |
| 12 | 登记闭环（两新测试文件 × Project.swift + BUNDLE-MAP） | `git grep` 双命中 |

## 风险与边界

- **多版本 × M2-2 导入链（default_look_pending）交互**：mint 分支在 load 时判定
  （.lra 缺席才 mint），版本创建发生在 load 之后——无时序冲突。真实新组合 =
  「.lra 存在∧has_edits=0」（空链版本）；`sidecar_present`/`backfill` 下游客户面本 plan
  不触，M2-8-3 观察项挂账（若发现消费面假设破裂，届时另立案）。
- **长版本列表/多版本内存**：每版本链 = param 字节值拷贝（KB 级，D-H2 先例）；百版本
  列表渲染归 P2 面板 + M2-8-3 观察项。本 plan 不预优化（OQ-10）。
- **投影通道为 App 侧新建面**：`LibraryStore.updateProjection` 至今零生产调用者
  （实测）——本 plan 的 version_ref 通道是该方向的第一个实例；若后续 has_edits 投影
  通道立项，应复用同款注入 sink 形态（KD-5 备注，DECISIONS 签注）。
- **v7 文档被 v6 语义消费者误读**：不可机检（旧二进制不在场）；注释 pin + SUMMARY
  声明。dangling/损坏输入 = typed degrade 保编辑不丢（KD-2），结构丢失可接受并测钉。
- **创建即激活的行为假定**：Alcedo 源码未见显式反面证据，按 UX 常理裁定；晨审/验收
  可翻（翻 = 创建后停留在原版本，一行改动）。
- **基线上移**：2525 为起算基线；本 plan 预计 +30..38（两新文件 + LIB 增补），后续
  plan 以 BUNDLE-MAP 行对账。

## 提交约定

- T1 `feat(core): sidecar v7 version records`
- T2 `feat(app): version coordinator and chain swap`
- T3 `feat(library): version_ref projection table`
- T4 `docs(m2-8): close out plan 1 version model core`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。

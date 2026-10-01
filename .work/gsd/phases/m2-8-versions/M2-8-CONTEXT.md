# Phase M2-8: 版本与历史（mini-git） — Context

> discuss/research 起草稿（2026-09-29）。规格锚点 = `research/ALCEDO-FEATURE-MAP.md` **§6.2**（DuckDB EditCommit/VersionRef/ImageEditState 三表 DDL）+ **§6.3**（版本与历史交互规则：跳回保 redo 尾/再编辑丢尾/切版本即时/自动保存/Copy Adjustments 排除清单）+ **§1.3**（EditorVersionsPanel/EditorSaveRecoveryBar/AdjustmentTransferDialog UI 面）；需求 = REQUIREMENTS **M2VER-01..05**；ROADMAP M2-8 行。衔接面 = Phase 2 `HistoryStack`（线性链 + position 指针，跳回/截尾语义**已是 Alcedo 规则的字面实现**）+ sidecar **v6**（`schemaVersionCurrent = 6`；v5 = rawOverrides M2-4-1、v6 = displayTransform M2-6-1——本 phase additive 落点 = **v6→v7**）+ `.lalb` mini-git 四表注释占位（`reservedTableNames` 负测 pin + KD-2 sqlite3_backup 迁移缝已就位）+ M2-3-1 tool rail `.versions` 空态占位。**本 CONTEXT 面向夜间授权裁决**（文末「夜间授权预案」：按推荐自主生效、晨审可推翻）。
>
> 起草勘误：任务简报称「sidecar v5→v6 additive」与「.lalb PipelineRoot/PipelineParam 表 M2-2 交付」——实测 sidecar 正本已至 **v6**（本 phase 是 **v6→v7**）；`.lalb` 交付的只有 `project_meta/images/albums/album_content` 四表 + `has_edits/params_hash` 投影列，`pipeline_root` 在 `reservedTableNames` 注释占位中（`pipeline_param` 从未登记）。以下发现均以 Grep 实测为准。

## Phase Boundary

**范围**（ROADMAP M2-8 行 + M2VER-01..05）：

1. **版本模型与存储载体**（M2VER-01/02/03）——版本/历史真身落点裁决（OQ-1）、EditCommit 图形态裁决（OQ-2）、VersionRef 三入口语义（OQ-3）、sidecar v7 additive 策略（OQ-11）。
2. **Versions 面板**（M2VER-02）——tool rail `.versions` 占位兑现：版本列表 + 新建/Branch/Rename/Remove + 版本切换（OQ-6）。
3. **与现有 HistoryStack 的接线**（M2VER-04 前半）——现有线性 history = active 版本事务流（OQ-4）；永久 undo/redo 语义钉死（跳回保尾/再编辑丢尾——已达成，验收固化）+ 历史面板行可点跳 + 参数 delta 呈现裁定（OQ-8）。
4. **切换即时性**（M2VER-03）——材质化语义落点裁定（OQ-5）。
5. **Copy Adjustments 三层面板**（M2VER-05）——Version→Node→Item 勾选 → Paste 新版本；排除 RAW decode/lens/crop 对应面（OQ-7）。
6. **自动保存 + 崩溃恢复条**（M2VER-04 后半）——自动保存 = 既有 2s debounce 收敛说明；崩溃恢复条语义落点（OQ-9）。

**非目标（本 phase 明确不做）**：

- **commit 图可视化**（Alcedo `EditorHistoryCommitGraphNode` + `DateCommitGraph`）——OQ-2 若裁简化线性链则无图可画；即令裁照抄 DAG，可视化亦后置（面板列表先行）。
- **版本合并（merge）**——Alcedo DDL 的 `second_parent_hash` 支持合并，但 §6.3 交互规则与 Versions 面板均无 merge 操作；v1 不做。
- **跨图整版本复制**——Alcedo 刻意延后项（§6.3「Confirmed interaction rules」）；Copy Adjustments 覆盖调整复制需求。
- **库网格版本徽标/批量版本操作 UI**——`version_ref` 投影数据就位（若 OQ-1-A），消费面后置。
- **性能优化专项**——观察项挂账（OQ-10），不预优化。

## Existing Code Insights

### 关键语义发现（本 phase 方向裁决的地基，2026-09-29 Grep 实测）

1. **Alcedo 版本内交互规则在现有 HistoryStack 是已实现行为，不是新语义**——`HistoryStack.jump(to:)` 只移指针（items 永不重写，redo 尾保留）；`commit` = 截尾 + 追加（「undo 后再编辑丢 redo 尾，与所有主流编辑器一致」，`HistoryStack.swift:9-14`）。§6.3「跳回早期编辑后 redo 尾巴保留；跳回后再编辑则丢弃未来尾巴」**逐字已达成**。「永久 undo」= `.lra` 持久化整个 `items` 数组（D-H2 无上限：items 持 param 字节永不纹理，内存可忽略）+ 加载恢复 `init(items:position:)` 字节忠实——也已达成。M2VER-04 的 undo 半边是**验收固化**，不是开发项。
2. **sidecar 已至 v6，additive 三件套惯例齐备**——`schemaVersionCurrent = 6`（`LightamerSidecar.swift:154`）；v5 rawOverrides / v6 displayTransform 双先例 = `decodeIfPresent` + nil 键缺席零漂移（「write ONLY when present」注释正本 `:418-424`）+ 专测 pin v6 字节形（`DrtSidecarTests.swift:67`）。v7 沿用零新机制。`history` 键的 `{items, position}` Codable spelling 是 **FROZEN**（checkpoint lock #6），v7 不可动它——active 链续住 `history` 键是唯一兼容路径。
3. **`.lalb` mini-git 四表仍是注释占位 + 负测 pin，KD-2 迁移缝就位**——`reservedTableNames = ["edit_commit", "version_ref", "image_edit_state", "pipeline_root"]`（`LibrarySchema.swift:346`；`LibrarySchemaTests.swift:259` 断言其缺席）；激活路径 = `ProjectFileStore` open 时 user_version dispatch → `sqlite3_backup` 快照 → `LibrarySchema.migrate` 单 BEGIN IMMEDIATE（`ProjectFileStore.swift:131-143`）。**真身边界红线**（M2-2 OQ-3 正文）：`.lalb` = 组织+检索投影+引用容器，`.lra` = 编辑态真相——版本真身落 `.lalb` 需显式翻线，落 `.lra` 则四表只余投影/预留价值。
4. **Sessions 模式（无 `.lalb`）必须可用 → 版本真身只能落 `.lra`**——`LibraryLegacyGate` 回切通道（`LIGHTAMER_LEGACY_LIBRARY=1`）下无项目包；`.lra` 与原片同目录自足。任何「版本数据仅在 `.lalb`」的方案直接违反该约束（也是双轨/纯 sidecar 两案的判决性论据）。
5. **「.lra 缺席 = 未编辑」不变量在版本面需要一次收窄表述**——版本骨架（空链新版本）若允许落盘，`.lra` 可在零编辑时诞生。既有投影面（`has_edits` 列、库网格徽标、pristine-decode 腿）全部以 items/position 判定，不以文件存在性判定——故收窄为「**.lra 缺席 = 观感 pristine（无编辑且无版本结构）**」后投影语义零破坏（M2-5 OQ-8「内存态、首次编辑随 sidecar 落盘」先例的推广：版本创建也触发 scheduleWrite，属低频用户动作）。
6. **History 面板已交付但行不可点、无参数 delta**——`EditorToolRailView.swift:150+`：undo/redo 按钮（disabled 绑定 position）+ 倒序 List（label + timestamp 两行文本）；无 `jump` 交互、无 delta 摘要。Alcedo 面板 = undo/redo 按钮 + 每行「操作名+参数 delta+时间」。缺口 = 行可点跳（`jump(to:)` 现成）+ delta 呈现策略（OQ-8）。
7. **版本切换的即时性由既有管线性质免费获得**——切版本 = swap HistoryStack + `rebuildLayerStack()`（`EditorState.swift:1070`，M2NODE-02 单路径 identity-preserving）= 纯 param 投影重放（毫秒级）；**decode 纹理由 PipeCache 承载，同图切版本零重新解码**。Alcedo `ImageEditState` 落库材质化要解决的「恢复加速」问题，在 Lightamer 的架构里由「active 链常驻内存 + param 重放」结构性满足——落库材质化 v1 收益存疑（OQ-5）。
8. **蒙版随 Grade 实例值拷贝是 Copy Adjustments 的安全前提**——M2-7 蒙版 = Grade-owned 记录（mask 几何/参数，无图像像素引用）；跨图贴 Grade 实例时蒙版记录随 instance Codable 值拷贝走，无外部引用悬挂。contentRevision 乐观并发字段随拷贝重置由 plan 期钉。
9. **DRT item 已有专属 scope 标记先例**——`drtDocumentScope`/`pasteEpochScope` 标记族（`HistoryStack.swift:311-320`）：版本模型若需「版本级条目」（如 Copy Adjustments 的 DRT record 载体），标记族是现成范式；`HistoryItem` 编码面已五字段 additive（layerScope/stackSnapshot/pasteSet/drtRecord 全 decodeIfPresent），v7 沿此再加字段零破坏。

### Reusable Assets

| 资产 | 位置 | M2-8 复用判定 |
|---|---|---|
| `HistoryStack`（items+position、jump 保尾/commit 截尾、五字段 additive item、projectedState peek） | `LightamerCore/Sources/Pipe/History/HistoryStack.swift` | **版本事务流本体，零重建**——每版本一条链值拷贝；OQ-4 |
| `rebuildLayerStack` 单路径（param 投影重放） | `App/Sources/Lightamer/State/EditorState.swift:1070` | 版本切换的执行路径（OQ-5 即时性的根基） |
| sidecar v6 additive 惯例（decodeIfPresent + nil 键缺席 + 形状 pin 测试） | `LightamerCore/Sources/Sidecar/LightamerSidecar.swift:154,418-424` + `DrtSidecarTests` | v7 双可选键（versions/activeVersionID）零新机制（OQ-11） |
| `SidecarStore`（2s debounce + tmp 原子晋升 + flushNow） | `LightamerCore/Sources/Sidecar/SidecarStore.swift` | 「自动保存（无显式 save）」的既有实现（OQ-9）；版本切换/创建触发 scheduleWrite 即可 |
| `reservedTableNames` + KD-2 迁移缝（user_version dispatch + sqlite3_backup 快照） | `LightamerCore/Sources/Library/LibrarySchema.swift:346` + `ProjectFileStore.swift:131-143` | `.lalb` 投影表激活的唯一合法路径（OQ-1）；负测随激活翻转 |
| tool rail `.versions` 占位（`EditorRailPlaceholder` + marker） | `App/Sources/Lightamer/UI/Shell/EditorToolRailView.swift:128-135` | Versions 面板挂点（占位退役，同 M2-4-3 nodes 先例） |
| History 面板（undo/redo 按钮 + List） | `EditorToolRailView.swift:150+` | 行可点跳 + delta 呈现的改造基底（OQ-8） |
| `history_graph_*` 七标签族（节点命令历史 label 正本） | `App/Sources/Lightamer/State/EditorState.swift:639-651` | 版本操作的 label 家族扩充样板（`versions_*` 键族） |
| scope 标记族（pasteEpoch/drtDocument/layerStructure） | `HistoryStack.swift:311-320` | 版本级条目/排除投影的现成范式 |
| 蒙版 Grade-owned 值拷贝（Codable 记录） | M2-7 交付 | Copy Adjustments 跨图贴 Grade 的蒙版随行（发现 8） |

### Integration Points

- **App/Core 边界**：版本记录结构（VersionRecord/版本列表面）落 `LightamerCore/Sources/Sidecar/`（sidecar 读写器放 Core 惯例，可单测）；Versions/Copy Adjustments 面板落 `App/Sources/Lightamer/UI/Shell/`；版本编排状态（activeVersionID、切换/新建/删除动作）落 `EditorState` 或其旁挂 observable。
- **投影同步**：`.lalb` `version_ref` 行随 sidecar debounce 写同批 upsert（沿 `has_edits/params_hash` 投影惯例；Sessions 模式跳过）。
- **不变量守护**：pristine-decode 腿与库网格徽标的判定面（items/position）零改动；`.lra` 诞生条件放宽为「编辑或版本结构」（OQ-1 附带裁定）。

## Open Questions（每条含推荐；夜间授权按推荐生效）

### OQ-1 存储载体：版本/历史真身落哪（必裁——决定整 phase 形状）
- **A（推荐）**：**双轨——sidecar v7 = 真身（每片 .lra 自足），`.lalb` 仅激活 `version_ref` 一表为投影**。真身：版本列表 + 各版本链 + activeVersionID 全在 `.lra`（Sessions 模式全功能，发现 4）；`.lalb` `version_ref(element_id, display_name, created_at_unix, updated_at_unix)` 行随 sidecar 写 upsert（库面数据就位，消费 UI 后置）；`edit_commit/image_edit_state/pipeline_root` 维持注释预留（负测只翻 `version_ref` 一名）。附带裁定：「.lra 缺席 = 未编辑」收窄为「**缺席 = 观感 pristine**」（发现 5，投影判定面零改动）。
- B：全落 `.lalb`（激活四表为真身）——Sessions 模式版本直接不可用，违约束（发现 4）；且翻 M2-2 OQ-3 真身红线。
- C：全落 `.lra`、`.lalb` 不动——最简，但 M2-2 预留 + KD-2 缝为 M2-8 保留的意图落空，库级版本面（未来批量/徽标）无数据基座。
**推荐 A**；激活走 KD-2 缝（migration v1→v2 + 自动快照），`version_ref` DDL 照抄预留注释拼写。

### OQ-2 EditCommit 图形态：照抄 Alcedo DAG vs 简化线性链
- **A（推荐）**：**v1 简化——版本 = 独立线性事务链（`HistoryStack` 值拷贝），不落 hash commit 图**。branch from current = 拷贝源链 `items[0...position]`（redo 尾不带）；从原始态新建 = 新空链。不可变 hash 主键/双亲/`edit_payload` JSON 不落库。理由：①Alcedo UI 三入口（新建/branch/fork）无一需要 DAG 语义，merge 操作在其 UI 不存在（§6.3）；②`HistoryStack.items` 全快照行**已经是**事务链本体，hash 图 = 同信息冗余表示；③值拷贝成本 = param 字节 KB 级（D-H2 先例）；④跳回/再编辑语义按链内 position 天然成立（发现 1）。**ROADMAP「双亲=分支/合并」字面被本条收窄**——晨审可裁 B 翻回。
- B：照抄 Alcedo DDL——`edit_commit(commit_hash PK, first/second_parent, created_at_ns, kind, edit_payload)` 激活，版本链 = commit 遍历、材质化 = 重放到 head。语义保真 + 未来 merge/图可视化就位，代价 = 双表示（HistoryStack 与 commit 图）同步面 + hash 稳定性（payload 编码规范化）工程量翻倍，v1 无一个 UI 需求消费 DAG。
- C：折中——`edit_commit` 激活但只记单亲线性 commit（kind/payload 简化）——表在语义退化，两头不讨好。
**推荐 A**；若裁 A，`edit_commit`/`pipeline_root` 继续预留，将来真需求（merge/跨版本去重/图可视化）出现再激活。

### OQ-3 VersionRef 三入口子集：从原始态新建 / branch from current / fork from root
- **A（推荐）**：**入口子集 = 从原始态新建 + branch from current + rename/remove；fork-from-root 并入「从原始态新建」不单列**。无 DAG 模型下 fork-from-root 与从原始态新建同为「新空链」（root = 导入原始态）；两按钮同行为即 UI 欺骗。Alcedo 语义中 fork-from-root 的可区分价值（从版本谱系根分叉）依赖 commit 图存在——OQ-2-A 裁定下它退化为重复入口；M2VER-02 字面「fork from root」由本条收窄（晨审可裁 B 照抄三按钮）。
- B：三按钮全做、行为照抄（fork from root = 空链、新建 = 空链，两按钮同型）——UI 忠实 ROADMAP 字面但行为重复，用户心智负担。
- C：只做 branch from current——缺「另起炉灶」主用例（「暖调」「黑白」独立 look 场景），违 M2VER-02 字面。
**推荐 A**；版本默认命名 = 「版本 N」（zh 键），Remove 需确认对话框、active 版本删除后切到列表首项。

### OQ-4 与现有 HistoryStack 的关系：投影复用 vs 重建
- **A（推荐）**：**现有线性 `history` = active 版本的事务流本体，零重建**——`EditorState.history` 即「当前活跃版本的链」（与 M2-4「PipelineDocument = 层栈投影」同款投影心智）；版本切换 = 当前链写回其版本槽 + 目标链装入 `history` + `rebuildLayerStack()`（单路径既有）；`HistoryItem` 形状与 FROZEN CodingKeys 零改动。
- B：重写为统一 commit 图模型（HistoryStack 废弃）——波及 paste/DRT/structure 三 scope 标记族 + M2-4 节点命令面 + 全部历史测试资产，风险与收益完全不成比例。
- C：`history` 键固定为主版本、versions 数组只存其它版本——「active 版本」心智分裂（切到版本 2 后主链到底是谁），且 v6 读者拿到的 `history` 与用户所见脱节。
**推荐 A**；`history` 键语义在 v7 注释中升级为「active 版本链」，v6 读者降级拿到最后活跃版本的观感（可接受的 degrade，键不可动的必然）。

### OQ-5 材质化缓存 ImageEditState：切换即时性如何达成
- **A（推荐）**：**无落库材质化——active 链常驻内存 + param 重放**。切换即时性 = swap 链 + `rebuildLayerStack()`（纯 param 投影，毫秒级）+ decode 纹理由 PipeCache 承载（同图切版本零重新解码，发现 7）；`ImageEditState` 落库材质化（materialized_head/transaction_chain/serialized_pipeline_state）解决的「加速恢复」在 Lightamer 架构里已被满足，v1 表不激活（M2VER-03「仅加速恢复非用户概念」的兑现方式 = 内存态）。
- B：激活 `image_edit_state` 落库材质化——为毫秒级重放再存一份序列化管线态，引入「材质化与真身漂移」新风险面（版本切换/崩溃/并发三处同步），收益不成比例。
- C：全量快照（每版本缓存渲染结果纹理）——内存爆炸（多版本 × 100MP float 纹理），否决。
**推荐 A**；若 OQ-1-A，`image_edit_state` 与 `edit_commit/pipeline_root` 同列预留。

### OQ-6 Versions 面板 UI 面
- **A（推荐）**：**tool rail `.versions` 占位兑现 = 版本列表 + 四操作**——List（每行：版本名 / updated_at / active 徽标），头部按钮组 = 新建（从原始态）+ Branch from current；行 contextual menu = Rename（inline 编辑）/ Remove（确认对话框）；单击行 = 切换（同 Alcedo「切版本即时」）；空态（无 .lra 或单隐式版本）= 现占位文案升级为引导文案。面板样式复用 History 面板骨架（同文件 `EditorToolRailView`）。commit 图可视化不做（OQ-2-A 联动 + 非目标）。
- B：列表 + 图可视化（照抄 EditorVersionsPanel + DateCommitGraph 两面）——无 DAG 无图可画；即便 OQ-2-B，可视化后置。
- C：版本操作挂 File 菜单、不做面板——违 Alcedo 工具轨 IA（§1.3 rail 三键之一）。
**推荐 A**；`editor.versions.placeholder` marker 退役（M2-4-3 nodes 占位退役同款流程）。

### OQ-7 Copy Adjustments 三层面板：范围与排除清单
- **A（推荐）**：**AdjustmentTransferDialog 对应物，复制面按 owner 收窄**——流程 = 选源（当前图 active 版本或跨图选源版本）→ Node pane（Grade 节点 + DRT）勾选 → Item pane（节点 chain 内 iop 实例逐条勾选）→ Version pane 汇总 → Paste = 目标图生成**新版本**（新空链 + 所选实例值拷贝；蒙版记录随 Grade 值拷贝走，发现 8）。**排除清单（Alcedo「RAW decode/lens/crop-rotation」的 Lightamer 对应面，按 `NodeOwnershipCatalog` owner 判）**：`.develop` 全域（rawOverrides = RAW decode；geometry 五件 = crop/rotate/lens 族；yiyin 三件）+ terminal trio + base 链 develop-owned 兼容实例；复制面 = `.grade` chain 实例 + document-level `drtRecord`（`.drtPost` 四件在 DRT 节点内，随 DRT 勾选整体走）。跨图为默认场景（Alcedo 主用例），同图为退化路径。
- B：无对话框整链直贴——违 M2VER-05 三层勾选字面，且把 develop 域参数错贴到别图（不同相机 WB/几何无意义）。
- C：仅同图版本间复制——Alcedo 场景主用例就是跨图（把 A 图调色搬到 B 图），砍掉即功能空壳。
**推荐 A**；对话框为模态 sheet，面板文案三 pane 沿 Alcedo Node→Item→Version 序。

### OQ-8 永久 undo 语义衔接 + 历史事务行呈现
- **A（推荐）**：**undo 语义零改动（发现 1 已达成，验收固化）+ 历史行升级「可点跳 + 类型图标」，参数 delta 文本 = Deferred**。验收固化项：跳回后 redo 尾保留、跳回后编辑丢尾、⌘Z/⇧⌘Z 与面板按钮同源、`.lra` 重载链字节忠实。行升级 = 行点击 `jump(to:)`（现成）+ 行尾类型小图标（结构/paste/DRT item 按 scope 标记判，标记族现成）；delta 文本需 per-op displayValue 设施（18 目录各 Params 无人类可读摘要器），v1 造 = 范围失控，**M2VER-04「参数 delta」字面由本条部分收窄**（操作名+时间已满足，delta 摘要挂 Deferred 待 per-op 摘要设施立项）。晨审若坚持 delta：降级方案 = 行副标题显示「N params changed」（Codable 键计数，通用但信息量低）。
- B：本 phase 造 per-op delta 摘要器——18+ 目录 × 双语摘要文案，侵入 M2-5 已签核目录面，范围膨胀。
- C：历史行维持现状不可点——HIST-02「jump to any point」的 UI 面缺席，永久 undo 无入口即无意义。
**推荐 A**；「永久」验收 = 500 条链 .lra 重载 + 全程可 undo 走查。

### OQ-9 崩溃恢复条 + 自动保存语义
- **A（推荐）**：**结构性崩溃安全 + clean-terminate 哨兵 toast（最小恢复面）**。自动保存 = 既有 2s debounce + tmp 原子晋升 + flushNow（切图/终止）——「无显式 save」已是事实，版本创建/切换动作补触发 scheduleWrite（低频）；崩溃丢失上界 = 2s debounce 窗。恢复条 v1 = 双向哨兵：terminate 置位 / launch 清位，launch 检出非正常终止 → 一次性 toast「上次会话异常退出；编辑已自动保存（至多丢失最后数秒）」；不建 journal、不做逐图恢复条 UI。
- B：完整 `EditorSaveRecoveryBar` 对应物（pending-write journal + 逐图检测 + 恢复条）——Alcedo 造它因 DB 自动保存粒度粗；Lightamer 原子写 + 2s 上界下 journal 收益不成比例，且引入 journal 自身的一致性面。
- C：零设施——崩溃静默无感知，ROADMAP「崩溃恢复条」字面不满足。
**推荐 A**；哨兵存 UserDefaults（`app.cleanTerminate`），仅 editor 打开态图受影响面，逻辑单测 + 人工杀进程走查。

### OQ-10 性能：重放深度上限 / 长历史分页
- **A（推荐）**：**不设上限、不投机，观察项挂账**（M2-5 OQ-11 同款论证）——items 持 param 字节（D-H2 无上限先例，万条 ≈ MB 级内存）；SwiftUI List 懒加载天然分页；切换 = param 重放非纹理重建。观察清单：①500+ 条链的版本切换耗时 sanity；②万条历史 .lra 加载/保存耗时；③Versions 面板百版本列表滚动流畅度。超带才立项专项。
- B：设硬门（如切换 ≤100ms）——无基线的假精度。
- C：链截断/归档（老事务迁出）——破坏「永久 undo」字面，否决。
**推荐 A**。

### OQ-11 sidecar schema v7 additive 策略
- **A（推荐）**：**v7 = 双可选键，active 链续住冻结 `history` 键**——`versions: [SidecarVersionRecord]?`（每记录 = id/name/createdAt/updatedAt + **非活跃链 items+position**）+ `activeVersionID: String?`（UUID string）；写入时 active 链在 `history` 键、其元数据在 `versions[]`（items 不双写）；切换 = 原链写回槽 + 新链装入 `history`（swap 语义，plan 期钉原子性）。nil 时键缺席零漂移（v5/v6 双先例）；`schemaVersionCurrent` 6→7；v6 读 v7 = 拿到 active 版本观感（JSONDecoder 忽略未知键）；>7 typed degrade 既有；新测 `SidecarV7Tests` pin v7 字节形（DrtSidecarTests 同款）。哈希面：版本结构不进 `historyHash` 折叠（drift 锚仍判编辑态——版本元数据非像素语义），plan 期以一条负测钉死。
- B：`history` 键弃写、主链也搬 `versions[]`——v6 读者拿到空历史，向后读面破坏。
- C：每版本独立 `.lra` 文件——「.lra 与原片同名一一对应」契约破坏 + 文件爆炸 + 投影同步面翻倍。
**推荐 A**；`SidecarVersionRecord` Codable 落 Core（sidecar 读写器放 Core 惯例），UInt64 字段（若有）DECIMAL TEXT（L013）。

### OQ-12 zh/en 键范围预估
- **A（推荐）**：**随手键 + 收尾 zh-audit 对账补齐**（M2-3-4/M2-4 T4/M2-7 三先例）——预估 **40–60 键**：Versions 面板（列表/两入口按钮/Rename/Remove 确认/active 徽标/空态引导/版本默认名「版本 N」）+ Copy Adjustments 对话框（三 pane 标题/勾选行/Paste/取消/排除项注记）+ 崩溃哨兵 toast + 历史行类型图标 accessibility 标签；zh 值滞后允许，phase 尾 `Scripts/zh-audit.py --check` 对账补齐；语言 code 沿 `zh`。
- B：每任务同步 zh——三 phase 先例已弃。
**推荐 A**。

## Canonical References

- `research/ALCEDO-FEATURE-MAP.md` §6.2（三表 DDL）+ §6.3（交互规则/Copy Adjustments/跨图版本复制延后）+ §1.3（EditorVersionsPanel/EditorSaveRecoveryBar/AdjustmentTransferDialog/EditorHistoryTransactionsPanel）
- REQUIREMENTS M2VER-01..05；ROADMAP M2-8 行（依赖 M2-2, M2-4）
- `LightamerCore/Sources/Pipe/History/HistoryStack.swift`（链语义/五字段 additive item/scope 标记族/DRT hash 折叠）
- `LightamerCore/Sources/Sidecar/LightamerSidecar.swift`（v6 正本 + additive 惯例注释）+ `SidecarStore.swift`（debounce/flushNow）
- `LightamerCore/Sources/Library/LibrarySchema.swift:340-346,466-510`（reservedTableNames + mini-git DDL 注释占位）+ `ProjectFileStore.swift:131-143`（KD-2 缝）+ `LibrarySchemaTests.swift:259`（负测）
- `App/Sources/Lightamer/State/EditorState.swift`（undo/redo/jump/rebuildLayerStack/history_graph 标签族）+ `UI/Shell/EditorToolRailView.swift`（History 面板 + versions 占位）
- `phases/m2-5-color-grade/M2-5-CONTEXT.md`（CONTEXT 惯例 + 夜间授权预案先例）

## Specific Ideas（起草倾向，plan 细化）

- 版本编排放 `EditorState` 旁挂 `VersionCoordinator`（observable）：持有版本元数据数组 + activeVersionID，切换/新建/删除三命令；`EditorState.history` 保持唯一链真相源，coordinator 只做 swap 编排——避免双状态源（§3.1 单一状态源纪律）。
- `SidecarVersionRecord.items` 复用 `SidecarHistoryItemRecord` 既有记录拼写（同一份 item 编码器，版本链与非版本链字节同形）。
- `.lalb` `version_ref` upsert 挂在 SidecarStore 写完成回调（或 EditorState 投影同步点——M2-2 has_edits 投影同位），Sessions 模式经 `LibraryLegacyGate` 判空跳过。
- Copy Adjustments 的排除判定单函数化：`isAdjustmentTransferable(instance:) -> Bool`（owner ∈ {.grade}），面板与未来批量面共用一份。

## Deferred Ideas

- per-op 参数 delta 摘要设施（displayValue/changed-keys 摘要器）——OQ-8 挂账，M2-5 18 目录稳定后立项。
- commit 图可视化（`DateCommitGraph` 式时间轴）——待真 DAG（OQ-2-B 世界线）。
- 版本快照缩略图（版本列表行内缩略预览，Alcedo 未有）——库面消费版本数据时一并议。
- 版本导出/导入（把单版本存为预设/文件）——预设系统（12）与版本系统交汇处，后置。

---

## 夜间授权预案（2026-09-29 起草时点）

本 CONTEXT 提交夜间授权裁决：若无人干预，D-M2-8-CONTEXT-1..12 = **OQ-1..12 全部按推荐 A 生效**。晨审可推翻：推翻任一条 = 修订对应 plan（CONTEXT OQ 原文不改、以 Ruling/勘误注记为准，沿 M2-4/M2-5 先例）。两条 ROADMAP 字面收窄需晨审特别注意：**OQ-2-A（EditCommit hash 图不落库）与 OQ-3-A（fork-from-root 并入新建）**——推翻即回到 Alcedo DDL 照抄线，plan 形状显著变大。plan 期需回填的悬决点（非 OQ 级）：版本 swap 的 sidecar 写原子序（OQ-11）、蒙版 contentRevision 拷贝重置规则（OQ-7）、`version_ref` upsert 触发位（OQ-1）、500 条链验收脚本（OQ-8/10）。

---

## Ruling（2026-10-01 夜间授权，晨审可推翻）

D-M2-8-CONTEXT-1..12 = OQ-1..12 **全部按推荐 A 生效**。三条盘点发现采信为事实基线：①sidecar 升版起点 = **v6→v7**（非 v5）；②Alcedo 版本交互规则在现有 HistoryStack 已实现（jump 保尾/commit 截尾），M2VER-04 undo 半边 = 验收固化；③Sessions 无库约束判决载体 = .lra 真身 + .lalb 仅 version_ref 投影。**ROADMAP 字面收窄点①②**（OQ-2 不落 hash DAG/双亲、OQ-3 fork-from-root 并入新建）为晨审专项追认项——翻回 = 照抄 Alcedo DDL 全量语义。

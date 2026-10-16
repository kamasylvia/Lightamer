# M7-2 CONTEXT — MCP O1 检索与状态读（OQ 裁决落定批，2026-10-16）

> **评审修订批（2026-10-16 fixer 批，输入 = `M7-2-01-PLAN-REVIEW.md`）**：
> 本文件 D-M7-2-3（EXIF 两段走法 + cursor segment 字段 + 默认 sort）/
> D-M7-2-4（limit 截断语义）/ D-M7-2-6（AIWorkerClientError 族映射补记）/
> D-M7-2-9（library provider 形改携 ProjectFileStore）四处经评审修订批
> 同步改写——均为**实现细节级行使**（评审 E-1/E-2/F-3/F-5 修法甲择定），
> **非裁决重开**：九裁决的方向与归属零变化，改写的只是「生效值」中
> 交付不出/语义缺口的实现形（先例 V2M E-2 供给面 / F1 失明面）。

> **裁决正本**：OQ-M7-2-1..9 **全部按 `M7-2-RESEARCH.md` §6 推荐落定**（M7 站
> charter 2026-10-16 授权站内 auto-advance + OQ 全按推荐；先例 M6-3/M6-4）。
> **晨审可推翻**——推翻 = 用户晨审修订本文件对应 D 条，下游 plan 受影响任务面
> 重开（已执行部分按「晨审推翻先例」惯例处理）。读解正本 = 同目录
> `M7-2-RESEARCH.md`（§0 结论摘要 / §2 MCP 现状测绘 / §3 三工具语义 /
> §4 集成缝 / §6 OQ 表；file:line 均 2026-10-16 HEAD `d08306fd` 亲核）。
>
> **夜间全自动授权在案**（先例 D-07-3-T5-1；晨审可推翻）：本 phase 执行批
> （omp 执行 + subagent 验收 + 全套 `--all` 轮〔批准制——执行时 orchestrator
> 派发 prompt 即批准〕）可夜间全自动推进，不需逐任务等待用户确认。
>
> **C 档门控行使记录**：RESEARCH 自标「C 档第 1 停（OQ 裁决前不进 plan）」——
> 该停由站 charter 授权链行使（OQ 全按推荐落定即裁决，本文即落定载体）；
> C 档第 2/3 停（plan 闭环汇报 / VALIDATION 签核）照常保留——站内
> auto-advance 只覆盖第 2 停的**等待面**（闭环汇报照发，不停等确认），
> 第 3 停（VALIDATION 签核给用户过目）不受站内授权覆盖，仍走人工过目。

## Phase Goal（ROADMAP §M7-2 行锚定）

补 agent 最大单点缺口——`search_photos`（EXIF/全文/CLIP 语义三路由对齐 GUI
三段搜索，复用 FilterSQL/SemanticEngine 单源）+ `get_history`（编辑历史只读，
含 note 面）+ `get_state`（统一状态快照：project/workspace/editor + control +
运行中任务，Alcedo `state.get` 语义同构）。工具面 additive，快照显式改。
验收形态（ROADMAP 原文）= 三工具 parity golden ✓（对齐 GUI 同源查询结果）+
tools/list 快照同批更新 ✓ + 既有 20 工具面零回归 ✓。
对应 REQUIREMENTS MCP2-01..03（:431-433）；对表锚 = Alcedo `search.query` /
`editor.history` / `state.get`（ALCEDO-CLI-AI-SURVEY.md §1.4/§2.4）。

## 决议（D-M7-2-1..9，生效值，硬约束，执行中不重开）

### D-M7-2-1 主域判定 = 库域（open `.lalb`）；`get_history` 双地址制（OQ-M7-2-1）

- **裁决 = RESEARCH 推荐（是）**：`search_photos` / `get_history` / `get_state`
  的检索与历史读面落在**库域**——GUI 三段搜索（`LibrarySearchModel`）、
  SemanticStore、`ai_understanding_fts` 全部骑 open `.lalb` 的
  `ProjectFileStore`；session 域不动（`list_photos` 的 D-14-CONTEXT-9 v1
  评估域已覆盖）。
- **addressing 分界**：`list_photos` = open **session** 索引；
  `search_photos` = open **library**（`.lalb`）——tool description 一句写明
  （RESEARCH §8；完整边界表归 M7-6 SKILLS-01）。
- **`get_history` 双地址制**（match_color 先例形）：`image` 参数 = 库图 id
  （digits → `LibraryStore.image(id:)`〔LibraryStore.swift:452〕+ ImageLinker
  解析落文件路径）或 open-session relPath；`search_photos` 无 relPath 臂
  （纯库域 keyset）。
- 被否备选：session 域扩（否——session 无 FTS/CLIP 面，等于重写检索）。

### D-M7-2-2 `mode` 显式三枚举（OQ-M7-2-2）

- **裁决 = RESEARCH 推荐（是）**：`mode` enum `exif|clip|fulltext`，
  **默认 `exif`**；无 auto 分类。
- auto 分类器后置挂账（Alcedo `search_query_classifier` 是 GUI 启发式
  单源，我方无对应物；引入 = 新面非复用）——挂账入
  `M7-2-01-DECISIONS.md`，不阻塞本波。

### D-M7-2-3 分页与结果集（OQ-M7-2-3）

- **裁决 = RESEARCH 推荐（是）**：
  - **EXIF 臂**：keyset cursor **两段走法（2026-10-16 评审修订批 E-2
    修法甲，GUI 同源——`searchPage` 主段〔恒 nullTail:false，只含 sort
    key 非 NULL 行〕耗尽 → cursor 翻 `segment = nullTail` 走
    `searchNullTail` NULL 尾段；token = `PhotoProjection.Cursor` 同形
    base64 JSON + `segment` 字段；`LibraryGridModel` :5-13/:88-91 一一
    对应）**+ 窄投影九字段 `imageID/imagePath/filename/dir/captureDate/
    rating/flag/colorLabel/hasEdits`（列映射以 `images` 表实存列为准，
    无列支撑字段如实缺席——**禁为此加 schema 面或第二查询面**，
    FilterSQL 头注红线「no second SQL face may exist」）；`limit` 1..500
    默认 200；`sort` 白名单五键 `{key, ascending}`（LibraryQueries.swift
    :202-205，`scanEpoch` 显式排除），**默认显式钉 `{key: "filename",
    ascending: true}`（GUI 同源——N-3）**；cursor/sort 越臂组合
    （mode=clip|fulltext 携带）typed 拒（N-4）。
  - **CLIP 臂**：有界 top-K 不分页，帽 256（GUI `semanticHitLimit` 同值，
    LibrarySearchModel.swift:210）；cosine score 降序 + score 字段。
  - **全文臂**：有界 top-K 不分页，帽 500（`AIDescriptionService.imageIDs`
    默认 limit 同值）；bm25 rank 序。
  - **缩略图不入结果**（走既有 `get_thumbnails`——image 三件能力不重复）。
- **库域 OFFSET 禁令**（LibraryQueries 头注 KD-3）与 Alcedo offset/limit
  形的显式偏离成立（RESEARCH §3.1「显式偏离」三条全采纳）。
- 超时：三臂复用 `McpTimeouts.list`（10s）；CLIP 嵌入+扫库贴线实测超时
  才按 DECISIONS 申报升 `thumbnailsAndContact` 20s 档——**禁止静默新增
  档位或改既有档值**。

### D-M7-2-4 `get_history` 载荷深度 = summary + `includeParams`（OQ-M7-2-4）

- **裁决 = RESEARCH 推荐（是）**：items 默认 summary（id/label/timestamp/
  kind/layerScope）；`includeParams`（bool 默认 false）开启后逐 item 附
  params 面 `{opName, enabled, …}`；**`limit` = min(全量, 500)，截断
  保留最新端（position 侧，有效历史优先），itemCount 恒真值总数**
  （2026-10-16 评审修订批 F-5 一句话钉死——HistoryStack 无 cap，
  >500 栈上「默认全量」与「最大 500」不能同真；截断可由
  position/itemCount 检出，保留方向影响 agent 自查序列正确性故显式钉）。
- **author 字段前向占位**：出参 schema 含 `author?`，v1 恒 null（负测钉死
  ——M7-4 MCP2-09 commit attribution 落地后填充）。
- **kind 判别纯函数**：`pasteSet != nil → paste`；`drtRecord != nil → drt`；
  `filmRecord != nil → film`；`stackSnapshot != nil → structure`；
  否则 `param`。drt/film item 的 `snapshot` 占位记录按
  `drtDocumentScope`/`filmDocumentScope` 标记剔除（HistoryStack.swift
  :61-134 语义），不进投影。

### D-M7-2-5 versions 面 = meta only（OQ-M7-2-5）

- **裁决 = RESEARCH 推荐（是）**：`get_history` 出参 versions 只带 meta
  （`{id, name, createdAt, updatedAt, active}`——`chain == nil` 即 ACTIVE，
  LightamerSidecar.swift:919）；完整链投影归 M7-3 `list_versions`
  （两波不重复）。`activeVersionID` 随出参。

### D-M7-2-6 CLIP 错误臂 = `McpToolError.modelUnavailable` additive 15→16（OQ-M7-2-6）

- **裁决 = RESEARCH 推荐（是）**：新 case
  `modelUnavailable(String)`——code `"modelUnavailable"`，message 携
  「bundled CLIP assets missing / failed to load」语义；两 switch
  （`code` / message 提取）各补一臂 + 16 值穷举测试钉死
  （McpToolRegistry.swift:62-111 封闭表 additive，D-14-CONTEXT-3 机制内
  显式改）。
- **映射规则**：`SemanticSearchError.modelUnavailable` →
  `modelUnavailable`；`dimensionMismatch(expected:actual:)` → 亦归
  `modelUnavailable`（模型/资产错配同属「语义运行时对本查询不可用」族
  ——agent 换参数重试无解，message 区分 missing vs mismatched）；
  **`AIWorkerClientError` 四案（workerUnavailable / workerCrashed /
  workerExhausted / requestFailed）→ 同归 `modelUnavailable`，message
  携 worker 案名与细节**（2026-10-16 评审修订批 F-3 补记——M2-10-05 后
  production runner 是 worker 进程，此族不是 SemanticSearchError、
  adapter 只捕 McpToolError，不映射 = 协议级无码兜底；归
  modelUnavailable 与本条「语义诚实优于错误码数量最小化」裁定同构，
  非裁决重开）。
- 被否备选：复用 `notSessionMember`/`invalidParams`（语义错位，排障误导）；
  worker 族归 `internalError`（资产/进程缺席映射成我方 bug，排障误导——
  F-3 评审同款否决）。

### D-M7-2-7 无头 `--project` 只读臂 = `openReadOnly()` 服务读面（OQ-M7-2-7）

- **裁决 = RESEARCH 推荐（是）**：heldByOther 臂在 emitConnectGuidance 后
  `ProjectFileStore.openReadOnly()`（ProjectFileStore.swift:199——**锁免**
  〔flock 语义零改，零锁获取〕、schema `stored == current` 守卫、写腿
  `withWriteBatch` 断路器 :454 typed 拒）→ `headlessProjectStore` 载体
  → 三读工具照常服务。
- **降级面**：openReadOnly 失败（schema 守卫拒等）= 诚实回落 nil seam
  （三工具 typed `notSessionMember`）+ log——**禁 exit(1)**。
- M6-1 connect-guidance 双通道并存不变（McpProjectArbitrationTests
  序列 A/B fixture 零 diff 绿 = 零回归门）。

### D-M7-2-8 `get_state` 六字段面 v1 范围（OQ-M7-2-8）

- **裁决 = RESEARCH 推荐（是）**：零入参；一行 JSON 快照，六字段组
  = **project / workspace / editor / control / tasks / server**
  （RESEARCH §3.3 状态源表逐字段）：
  - project = `LibraryProjectController`（projectStore/projectURL/
    isReadOnly）；无头 writer 臂 = path、heldByOther 臂 = held 态、
    无旗标 = null。
  - workspace = filter 投影 + selectedIDs + `editorPhase.currentImageID`；
    无头臂诚实 null。
  - editor = `PipeCoordinator.liveImageURL`（既有 provider 同源）+
    has_edits（`history.position >= 0`，readDocument 可查）；无头臂 null。
  - control = 锁 verdict probe（`McpProjectLockVerdict`）+ endpoint 锁
    自身态 + `writeCallCount`（launcher 诚实面同源）。
  - tasks = **M2 导出队列计数面**（`ExportState.queue` 的 pending/failed
    等四态计数，`ExportQueueContract.swift` :33/:46）——merge/pano/AI
    worker 队列不入 v1（M7-4 `list_tasks` 若立项再扩，ROADMAP 预埋）。
  - server（我方增列）= serverName/serverVersion + host mode +
    readOnly 立场 + writeCallCount。
- **热态语义**：一行快照即取即走，不保证调用间一致（Alcedo 同构，
  description 注明）；@Observable 态全部经 seam closure + `MainActor.run`
  hop 读取，工具 handler 零直接观测（RESEARCH §3.3 结构纪律）。

### D-M7-2-9 库 seam 形态 = 新 context 自带 `library` provider（OQ-M7-2-9）

- **裁决 = RESEARCH 推荐（是）**：`McpSearchStateContext` 自带 provider
  closure（14-1 以来的 seam 纪律——全 provider 注入、测试可注入、宿主
  装配点接线）；**`MatchColorToolset.installLibraryProvider` static box
  不泛化复用**（match_color 单工具特例，单例 box 语义不共享）。
- provider 清单（闭包签名以 GUI 同源装配形为准——LibrarySearchModel
  provider 三件同形）：`library`（**ProjectFileStore + projectDirectory
  ——2026-10-16 评审修订批 E-1 修法甲改写：三路由单源 `LibraryQueries` /
  `SemanticStore` / `AIDescriptionService.imageIDs` 全吃 ProjectFileStore
  （三 init 签名亲核），provider 直携；`LibraryStore` 需要处（get_history
  digits 臂 `LibraryStore.image(id:)`）由 toolset 用公开
  `LibraryStore(store:)` init 现场派生（LightamerApp :1362-1371
  match_color provider 派生形）；不加 LibraryStore accessor（零 Core
  diff）**）/ `sessionPair`（get_history relPath 臂）/ `semanticStore`
  （open 包 SemanticStore 读面）/ `semantic`（`AIInferenceService.shared
  .semanticSearcher()` 同源，:41）/ `fulltext`（`AIDescriptionService
  .imageIDs` 查询缝）/ `liveState`（get_state workspace/editor/tasks
  快照，MainActor hop inside）/ `projectWriteProbe`（control 面，既有
  probe 复用）/ `writeCallCount`（server 面，GUI embedded 走
  `embeddedWriteCallCount()` 同源；headless / 只读 face 无 handle 外露面
  = null 诚实面——F-4②）。
  optional 缝缺省 nil = 既有构造零 diff + typed 诚实错误臂。
- 被否备选：复用 match_color static box（单例共享语义混淆）。

## LabelQueries 勘误注记（RESEARCH §3.1 载，本文件升正本）

REQUIREMENTS MCP2-01 行文案「复用 FilterSQL/SemanticEngine/**LabelQueries**
单源」中 LabelQueries 为**勘误**：`LabelQueries.catalog`/`seedRows(modelKey:)`
（LightamerCore/Sources/AI/LabelQueries.swift）是**导入期自动打标的查询
目录**（label → zh/en 查询文本），**不是搜索路由**；GUI 三段没有 Label 段。
Alcedo 的 Label 路由在我方由「CLIP 直接嵌匹配 + keywords 走 EXIF 结构项」
覆盖——本波**不新增 Label 路由**（标签可检索性已由 CLIP 腿 + 全文腿
〔AI tags 进 FTS〕承载）。plan 期不复核；REQUIREMENTS 行文案随 T6 翻账
批顺带勘正（「复用 FilterSQL/SemanticEngine/AIDescriptionService 单源」形）。

## 红线（正本移交 `M7-2-01-PLAN.md` front-matter `red_lines`，此处摘要）

①MCP 快照族 additive 显式改（D-14-CONTEXT-3 机制内）——本波持 union
改动权，M7-3/M7-5 串行在后（ROADMAP §M7 红线③，orchestrator 编排保证
不并行）；editing(6)/culling(14) 两层快照文件零触。②零新 SPM 依赖。
③工具面 additive——既有 20 工具 descriptor/handler/timeout 零 diff。
④三新工具恒只读（`requiresWriter: false` + `readOnlyHint: true`）——
writer gate / writeCallCount / projectWriteProbe 三写面结构性不触
（registry :333 分支结构保证）；零写路径（sidecar 写面/withWriteBatch/
库写腿零触；openReadOnly 只读臂零锁获取）。⑤Alcedo GPL 代码/文档文案
零复制零翻译（只对表命令语义）。⑥封存面零触（get_history 是 HistoryStack
只读投影，类型零改）。⑦xcstrings 三新键尾块纯插入 + zh-audit --check
PASS。⑧`--all` 全套轮批准制 + 8G 门 + MEMFAIL 机检 + 运行中保持监视。

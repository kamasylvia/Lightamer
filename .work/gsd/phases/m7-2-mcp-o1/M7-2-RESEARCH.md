# M7-2 RESEARCH — MCP O1 检索与状态读（MCP2-01..03）

```
phase:        M7-2
title:        MCP O1 检索与状态读 research（search_photos / get_history / get_state）
status:       research-draft — C 档第 1 停（OQ-M7-2-1..8 待裁决，裁决前不进 plan）
baseline:     3860/35/0（M7-1 定罪批逐值维持，ΔN=0）
date:         2026-10-16
input:        ROADMAP §M7-2 行 + REQUIREMENTS MCP2-01..03 + ALCEDO-CLI-AI-SURVEY.md 块一 O1
              + Phase 14 MCP server 20 工具封闭集 + M2-3 GUI 三段搜索单源 + M2-2 LibraryQueries
              + LIGHTCRAFT-NOTES.md §面6/OQ-LC-1
red_lines:    ①MCP 快照族 additive 显式改（D-14-CONTEXT-3 机制内），M7-2..M7-5 快照改动串行编排
              ②零新 SPM 依赖 ③Alcedo GPL 代码/文档文案零复制零翻译（只对表命令语义）
              ④不改码（本批 doc-only）⑤--all 全套轮仍须 orchestrator 批准（本 research 零产线不跑）
estimate:     1 plan（三工具 additive + 快照同批 + parity golden 测试）
```

## §0 结论摘要

1. **三工具全部可 additive 落地，单源齐备，零新依赖**：
   - `search_photos` = GUI 三段搜索的同一单源（EXIF 腿 `ExifSearchParser` → `LibraryQueries.searchPage`〔FilterSQL `.library` 域〕；CLIP 腿 `SemanticEngine.search`；全文腿 `AIDescriptionService.imageIDs`）——**无第二 SQL/检索面**（FilterSQL 头注红线「no second SQL face may exist」直接覆盖本工具）。
   - `get_history` = `ExportRenderer.readDocument(imageURL:)`（MCP editing 面已在用的 sidecar 读缝）→ `HistoryStack`/`versions`/`note` 只读投影——**零新持久化读法**。
   - `get_state` = 既有 @Observable 状态对象的 seam-closure 注入快照（LibraryProjectController / WorkspaceModel / PipeCoordinator / ExportState / 锁 verdict）——**与 GUI host 既有 provider 形同构**（`liveImageURL` / `installLibraryProvider` 两先例）。
2. **主域判定（OQ-1，推荐）**：三工具的检索/历史读面落在**库域（open `.lalb` 项目）**——GUI 三段搜索、SemanticStore、ai_understanding_fts 全部骑 `ProjectFileStore`；session 域（`list_photos` 的 D-14-CONTEXT-9 v1 评估域）不动。Alcedo `search.query`/`editor.history`/`state.get` 的同构语义也都在「打开的项目/库」上。
3. **锁交互**：三工具全部只读（`readOnlyHint: true` + `requiresWriter: false`）→ 不过 writer gate、不计 `writeCallCount`、不过 `projectWriteProbe`（probe 本就是 write-face 专用，registry 源 :333 只对 `requiresWriter` 生效）。唯一缝 = 无头 `--project` 只读臂当前**不 open store**——`get_state`/`search_photos` 要在只读臂有数据面需 `ProjectFileStore.openReadOnly()`（OQ-7 推荐 open）。
4. **快照族**：新第 4 个 snapshot layer（search/state 三工具）+ union `McpFinalSnapshotTests` 20→23 显式改；editing(6)/culling(14) 两层快照零触。M7-2 批持有 union 文件改动权，M7-3..M7-5 串行接棒（ROADMAP §M7 红线③）。
5. **工作量 = 1 plan**：T1 search_photos（三路由）+ T2 get_history + T3 get_state + 快照/测试/收尾。验收形态 = ROADMAP §M7-2 行三条（parity golden 对齐 GUI 同源查询 / tools/list 快照同批 / 既有 20 工具零回归）。

## §1 输入正本（复述）

- **ROADMAP §M7-2 行**：`search_photos`（EXIF/全文/CLIP 语义三路由对齐 GUI 三段搜索，复用 FilterSQL/SemanticEngine/LabelQueries 单源）+ `get_history`（编辑历史只读，含 note 面）+ `get_state`（统一状态快照：project/workspace/editor + control + 运行中任务，Alcedo `state.get` 语义同构）。工具面 additive，快照显式改。
- **REQUIREMENTS MCP2-01..03**（:431-433）：MCP2-01 对表 Alcedo `search.query`（现状 = `list_photos` 逐页扫、无检索动词 = agent 最大单点缺口，survey gap #20）；MCP2-02 对表 `editor.history`（含 note/author 读面，与 MCP2-09 归属缝配套）；MCP2-03 对表 `state.get`（project/workspace/editor + control + 运行中任务一行快照）。
- **Alcedo 同构锚**（survey §1.4/§2.4）：`search.query` = `text`/`offset`/`limit`/`mode(auto|fuzzy)` → 匹配 + 分页；GUI 侧 `search_query_classifier.hpp:14-44` 四路由（Empty/Traditional/Label/Semantic，只有 Semantic 起 semantic runtime）；命中 AI FTS + 标签 + 评分（A5 = DuckDB BM25）；`state.get` = project / workspace / editor + control + 运行中任务；`editor.history` = commits **含 author 与 note**。
- **LightCraft MCP 参考**（§面6/OQ-LC-1）：单写者锁 + `--connect` 转发已由 M6-1 兑现；resources JSON 快照 / progress notification 均列「低」候选——本波不取。

## §2 MCP 现状测绘（Phase 14 + M6-1 + M5-1 交付面）

### 2.1 registry 内核（`App/Sources/Lightamer/MCP/McpToolRegistry.swift`，零 `import MCP`）

- `McpJSON`（Sendable 手搓 JSON 值，:22）；`McpToolError` **15 档封闭错误码表**（:61-111，snake_case code + zh/en 混排 message）；`McpToolDescriptor`（name/description/**inputSchemaJSON verbatim 快照断言**/readOnlyHint/destructiveHint/idempotentHint，:142）；`McpToolOutput`（text + imageBase64 两形态，:169）；`McpToolHandler`（:193）；`McpTimeouts` 一表（:198-216：metadataWrite 5s / list 10s / thumbnailsAndContact 20s / renderAndCrop 30s / apply 10s / applyBatch 60s / export 120s / shutdownDrain 5s）；`McpRenderGate`（render 类并发 1，:223）。
- **注册面**：`register(descriptor, requiresWriter:, handler:)`（:300）——`requiresWriter: true` 的工具在 call 前过 `writerCheck`（失败 = `serverReadOnly`）并计 `writeCallCount`（launcher「本次会话无写回」面）；只读工具两条都不走（:333-341 只在 `entry.requiresWriter` 分支内）。`descriptors()` 按名字排序输出（tools/list 快照稳定，:316）。
- **M6-1 锁面**：`McpProjectLockVerdict`（.writable / .held(holderSummary, guidance)，:120）——probe 是**非持有式**每写调用检查，只被 write-five/apply_preset/match_color 写臂消费。

### 2.2 双宿主（`McpServerController.swift`）

- **封闭集装配点** = `makeRegistry(editing:culling:)`（:456-468）：editing 6 + culling 14 = 冻结 20。**additive 缝 = 在此追加第三 toolset 参数（或并入现有二参），装配点唯一**。
- **GUI host**：`LightamerApp.swift` :1331-1374——`makeEditingSeams(session:liveImageURL:yiyinInjector:)` + `makeCullingContext(session:...)` + `projectWriteProbe` + `MatchColorToolset.installColorMatchService/installLibraryProvider` + `startEmbeddedIfPreferenceEnabled`。**search/state 工具的 seam 注入点就在这一段**（见 §4.2）。
- **无头 host**：`runHeadlessArbitrated(mode:projectURL:)`（:242）——writer 臂 `store.open(role: .headless)` 成功持锁、`headlessProjectStore` 载体；**heldByOther 只读臂不 open store**（`headlessProjectStore` 保持 nil，仅 emit connect-guidance + serve）→ 只读工具在该臂无数据面（OQ-7）。stdio EOF 优雅腿已 armed（:272-286）。
- 端点发现（`McpEndpointFile`/`McpEndpointDiscovery`）+ Bearer（`.lan` 分支强制）+ 会话帽 4 + launcher（串行至多 1 agent 进程）不变。

### 2.3 快照族（三层 + union）

| 层 | 域 | 文件 | 本波 |
|---|---|---|---|
| 1 | editing 6 | `McpRegistrySnapshotTests.swift`（APP bundle） | 零触 |
| 2 | culling 14 | `McpCullingToolsetTests.swift`（APP bundle） | 零触 |
| 3 | **union 20** | `McpFinalSnapshotTests.swift`（APP bundle，冻结表 + 计数断言；M5-1-03 先例 = 19→20 显式改） | **20→23 显式改** |
| 4（新） | search/state 3 | 新 `McpSearchStateToolsetTests.swift` 内含本域快照 | 新建 |

快照纪律（D-14-CONTEXT-3③）：工具面 = 安全面，schema 字节改动必须显式改快照；三层「consciously change together」。

### 2.4 既有 20 工具与域判定

- Editing 6（`load_image`/`list_iops`/`apply_params`/`render_preview`/`export_image`/`match_color`）+ Culling 14（`list_photos` 25 列投影 + keyset 游标、写五 `set_rating`/`set_flag`/`set_color_label`/`append_note`/`set_keywords`、preset 三件、image 三件、burst/faces）+ MatchColor 1。
- **v1 评估域 = 当前打开的 session**（D-14-CONTEXT-9，`McpCullingContext.store: SessionIndexStore`）——这是 `search_photos` 落库域时必须写清的 addressing 分界（OQ-1）：`list_photos` 走 session 索引，`search_photos` 走 open `.lalb`；两者语义边界进 tool description 与 M7-6 SKILLS-01 文档。
- **库域已有 MCP 先例**：`match_color` 的 reference 支持库图 id（digits → `LibraryStore.image(id:)` + ImageLinker 解析；`MatchColorToolset.installLibraryProvider` :90-109 static box，GUI 装配点注入 `(LibraryStore, projectDirectory)`）。

## §3 三工具语义测绘

### 3.1 `search_photos`（MCP2-01）

**GUI 同源链（正本）**：`GlobalSearchDialog`（三段卡 exif/clip/fullText，`search.tab.*`）→ `LibrarySearchModel.submit`（`App/Sources/Lightamer/Library/LibrarySearchModel.swift` :145）三分派：

| 腿 | 单源 | 链路 | 结果序 |
|---|---|---|---|
| EXIF | `ExifSearchParser.parse`（`LightamerCore/Sources/Library/ExifSearchParser.swift`）→ `ExifSearchPlan{ftsTerms, structured, dateRange}` | `LibraryQueries.searchPage(filter: ExifSearchFilter)`（`LibraryQueries.swift` :224）——结构/日期项折成 FilterSQL `.library` 域规则（`FROM images i`、`+i.` 前缀、keywords 四子句物化列），词项经 `ExifFold.matchQueryToken` 进 `images_fts MATCH`（:678）；keyset 行值 seek + NULL 尾段；排序白名单 5 键（:204 filename/rating/captureDate/iso/focalLength，`scanEpoch` 显式排除）；`stackMode: .flat`（MCP 先例） | sort 键序（`image_path` tiebreaker） |
| CLIP | `SemanticEngine.search(_ queryText, limit, in: SemanticStore)`（`SemanticEngine.swift` :82；`maxTokens 52`；vDSP 全量扫 ACTIVE model 行） | provider = `AIInferenceService.shared.semanticSearcher()`（App 层，:41；bundled `chinese-clip-vitb16-int8`，M2AI-01/02 资产在位）；`SemanticSearchError.modelUnavailable` typed | cosine score 降序；GUI 预算 `semanticHitLimit = 256`（:210） |
| 全文 | `AIDescriptionService.imageIDs(matching:store:limit:)`（`AIDescriptionService.swift` :146） | `ai_understanding_fts MATCH` → JOIN `ai_understanding active=1` → `ORDER BY rank`；`ftsMatchQuery` 把裸词折成引号短语（操作符失义、永不 throw）；默认 limit 500 | bm25 rank 序 |

**`LabelQueries` 角色澄清**：`LabelQueries.catalog`/`seedRows(modelKey:)`（`LightamerCore/Sources/AI/LabelQueries.swift`）是**导入期自动打标的查询目录**（label → zh/en 查询文本），不是搜索路由——GUI 三段没有 Label 段；Alcedo 的 Label 路由（classifier 第三路）在我方由「CLIP 直接嵌匹配 + keywords 走 EXIF 结构项」覆盖。REQUIREMENTS 文案列 LabelQueries 为「复用单源」之一，实际本波**不新增 Label 路由**（标签可检索性已由 CLIP 腿 + 全文腿〔AI tags 进 FTS〕承载）——登记为勘误注记，plan 期不复核。

**工具面提案**（对齐 Alcedo `search.query` 语义 + 我方 keyset 纪律）：

- 入参：`query`（string，必填；空串 = typed `invalidParams`——GUI 空串语义是「清过滤」，MCP 面无过滤态可清，诚实拒绝）、`mode`（enum `exif|clip|fulltext`，默认 `exif`——OQ-2）、`limit`（1..500，EXIF 默认 200 / CLIP 帽 256 / 全文帽 500）、`cursor`（EXIF 臂 only，`PhotoProjection.Cursor` 同形 opaque token）、`sort`（EXIF 臂 only，白名单 5 键 `{key, ascending}`）。
- 出参：`results[] = {imageID, imagePath, score?}`（CLIP/全文臂带 score/rank 序位；EXIF 臂可携 25 列投影的库域子集——**推荐窄投影** `imageID/imagePath/filename/dir/captureDate/rating/flag/colorLabel/hasEdits`，缩略图走既有 `get_thumbnails` 不内嵌〔OQ-3 附带〕）+ `nextCursor?`（EXIF 臂 only）。
- 错误语义：无开项目 → `notSessionMember`（文案写明 "no open project — open a .lalb first"）；EXIF 解析错（`ExifSearchParserError.unrecognizedToken/disjointDateRanges`）→ `invalidParams` 携 token（GUI `ErrorFamily` 同构分类信息进 message）；CLIP `modelUnavailable`/`dimensionMismatch` → **OQ-6**（推荐新增 `McpToolError.modelUnavailable`，15→16 additive）。
- `readOnlyHint: true`、timeout 复用 `McpTimeouts.list`（10s；CLIP 嵌入+扫库 GUI inline 同路径无门，万级库 vDSP 扫 <10s——贴线时 OQ-3 裁量升 `thumbnailsAndContact` 20s 档）。

**与 Alcedo 的显式偏离**：①分页用 keyset cursor 而非 offset/limit（库域 OFFSET 禁令 = LibraryQueries 头注 KD-3；Alcedo 形态不照搬）；②显式 mode 而非 auto 分类（classifier 是 Alcedo GUI 启发式单源，我方无对应物，引入 = 新面非复用——OQ-2 附带「auto 后置」注记）；③结果不含评分列（Alcedo `library.list` 的 rating 经 EXIF 字段可查，EXIF 臂投影含 rating 即覆盖）。

### 3.2 `get_history`（MCP2-02）

**Alcedo 对照**：`editor.history` → commits 含 author 与 note；`versions.list` 独立命令（M7-3 的 `list_versions` 对表）；commit attribution（agent 身份）= MCP2-09（M7-4 落地），本波只读面**前向占位 author 字段**（v1 恒缺省/`"user"`）。

**我方只读源**（零新读法）：`ExportRenderer.readDocument(imageURL:)`（`ExportRenderer.swift` :783，editing 面已在用）→ `LightamerSidecar`（schemaVersionCurrent = 10）：

- `history: HistoryStack`（`HistoryStack.swift` :34）——`items[]` + `position`（-1 = pristine；**has_edits 判定面 = `position >= 0`**，M2-8 收窄语义）。`HistoryItem`（:61-134）：`id` / `snapshot: ModuleInstance`（opName/enabled/params/multiPriority）/ `label` / `timestamp` / `layerScope`（nil = 全图）/ `stackSnapshot?`（结构编辑）/ `pasteSet?`（paste 纪元）/ `drtRecord?` / `filmRecord?`（文档级载体，`snapshot` 为占位、投影时按 `drtDocumentScope`/`filmDocumentScope` 标记剔除）。
- `versions: [SidecarVersionRecord]?` + `activeVersionID`（v7 双键，:342/:348）——record = `{id, name, createdAt, updatedAt, chain?}`（:919；`chain == nil` = ACTIVE 版本，items 住 `history` 键）。
- note/metadata 归属：`note: String?`（:309，`append_note` 上游）/ `keywords: [String]?` / `rating` / `flag` / `colorLabel` / `provenance` / `aiProvenance`。

**工具面提案**：

- 入参：`image`（string 必填——**双地址制**，match_color 先例：库图 id（digits）或 open-session relPath；库 id 经 `LibraryStore.image` + ImageLinker 落到文件路径再拼 sidecar）、`includeParams`（bool 默认 false）、`limit`（history items 帽，默认全量、最大 500）。
- 出参：`{position, itemCount, items[] = {id, label, timestamp, kind(param|structure|paste|drt|film), layerScope, [params: {opName, enabled, …}] when includeParams}, versions[] = {id, name, createdAt, updatedAt, active}, activeVersionID, note, keywords, rating, flag, colorLabel, author?}`。`kind` 判别纯函数：`pasteSet != nil → paste`；`drtRecord != nil → drt`；`filmRecord != nil → film`；`stackSnapshot != nil → structure`；否则 param。
- 显式边界：**只读**——无 undo/redo/jump 动词（Alcedo `editor.undo/redo` 属变更面，不在 O1 范围）；`list_versions`（M7-3）做完整链投影，`get_history` 的 versions 只带 meta 不带 chain items（OQ-5 两波不重复）。

### 3.3 `get_state`（MCP2-03）

**Alcedo 对照**：`state.get` = project / workspace / editor + control + 运行中任务（survey :85）。我方逐字段状态源盘点：

| Alcedo 字段 | 我方状态源 | GUI host | 无头 host |
|---|---|---|---|
| project | `LibraryProjectController`（:52 `projectStore` / :57 `projectURL` / :78 `isReadOnly`；`openProject` :150 / `openProjectReadOnly` :172） | 活 | `--project` writer 臂 = path；heldByOther 臂 = held 态（经锁 payload）；无旗标 = null |
| workspace | `WorkspaceModel.LibraryFace`（:41 `filter: ExifSearchFilter`〔投影 = `LibraryFilterDescription` 同源〕/ :47 `selectedIDs: Set<Int64>`）+ `editorPhase.currentImageID`（:75） | 活 | 诚实 null（无 GUI 收集态） |
| editor | `PipeCoordinator.liveImageURL`（editing seams 既有 `liveImageURL` provider 同源）+ 打开文档 has_edits（`history.position >= 0`，readDocument 可查） | 活 | null |
| control | M6-1 锁 verdict：`McpProjectLockVerdict` probe（.writable / .held(holderSummary)）+ endpoint writer lock 自身态 + `serverReadOnly` 立场（`registry.writeCallCount` 可携） | 活 | 活（probe/锁面与 GUI 无关） |
| 运行中任务 | M2 导出队列：`ExportState.queue`（`State/ExportState.swift` :74）+ `ExportJobState`（`ExportQueueContract.swift` :33 pending / :46 failed(AppError)）计数面 | 活 | GUI-only → null（无头无 M2 队列） |
| server 自身（我方增列） | `serverName/serverVersion` + host mode（stdio/http/embedded）+ readOnly + `writeCallCount`（launcher 诚实面同源） | 活 | 活 |

**工具面提案**：零入参；一行 JSON 快照（嵌套对象，字段缺 = null 的诚实面——Alcedo 同构）。**不入 v1**：legacy session merge/pano 队列、AI worker 任务面（M7-4 若立项 `list_tasks` 再扩，ROADMAP M7-4 行预埋）——OQ-8。注意 GUI 侧全部 @Observable MainActor 态——**seam closure 注入 + `MainActor.run` hop**（`liveImageURL`/`installLibraryProvider` 既有形），工具 handler 零直接观测，快照即取即走（无跨 actor 长持）。

## §4 集成缝测绘

### 4.1 注册缝（additive，装配点唯一）

- 新 toolset 文件 `App/Sources/Lightamer/MCP/Tools/SearchStateToolset.swift`（新域不折入 CullingToolset——session 域/库域分界清晰化，快照第 4 层命名归位）：`McpSearchStateContext`（seam 结构体，全 provider closure 注入）+ `McpSearchStateToolset.registerAll(on:context:)` 注册三工具。
- `makeRegistry` 追加第三参数 `searchState:`（默认 nil = 测试零 diff）；三处宿主装配（GUI `startEmbeddedIfPreferenceEnabled` / `startHTTPHost` / stdio host）传 context。
- **库 seam**：OQ-9 形态二选一——(a) 复用 `MatchColorToolset.installLibraryProvider` static box（零新缝，但单例 box 语义被第二个消费方共享）；(b) 新 toolset context 自带 `library: () async -> (LibraryStore, URL)?` provider，GUI 装配点独立注入（推荐——provider 形是 14-1 以来的一贯纪律，static box 是 match_color 单工具特例）。

### 4.2 GUI 装配点（LightamerApp.swift :1331-1374 同段追加）

```swift
searchStateContext = McpSearchStateContext(
    library: { [libraryProjects] in  // (LibraryStore, projectURL) or nil
        await MainActor.run { ... }
    },
    sessionPair: { ... },            // get_history 双地址制的 relPath 臂
    liveState: { ... },              // get_state 的 workspace/editor/export 快照
    semantic: { await AIInferenceService.shared.semanticSearcher() },
    projectWriteProbe: projectWriteProbe)  // 只读 verdict 复用（get_state control 面）
```

零 UserDefaults 新键、零 xcstrings 动态键；`mcp_tool_desc_search_photos`/`_get_history`/`_get_state` 三静态键 xcstrings 尾块纯插入（zh-audit --check 同批 PASS）。

### 4.3 无头臂

- writer 臂（`--project` 成功 open）：`headlessProjectStore` 已在 → LibraryStore 直建，三工具全活。
- **只读臂（heldByOther）**：现不 open store → OQ-7：推荐 `openReadOnly()`（`ProjectFileStore.swift` :199——锁免、schema `stored == current` 守卫、写腿 `withWriteBatch` 断路器 :457 挡写）后服务读面；connect-guidance 双通道并存（M6-1 语义不变）。不改 = 三工具在只读臂诚实 `notSessionMember`（降级形态，可后补）。
- 无 `--project`：库 seam = nil → typed `notSessionMember`（no open project），`get_state` 返回 project=null + control/server 字段活。

### 4.4 锁交互结论（复述 §0.3）

三工具 `requiresWriter: false` + `readOnlyHint: true`：writer gate / writeCallCount / projectWriteProbe 三面全不触（registry :333 分支结构保证）；M6-1 `projectReadOnly` typed error 只属写面，读面在只读打开（GUI `openProjectReadOnly` / 无头只读臂）下照常服务——`LibraryStore` 读缝无 read-only 断路（断路只在 `withWriteBatch`，:457-463）。

### 4.5 CLIP 模型依赖面

`AIInferenceService.shared`（App 层单例，同 binary 双宿主可达）：bundled `chinese-clip-vitb16-int8`（M2AI-01/02 在位，`ModelAssetCatalog` SHA-256 锁）；缺资产/未转换 = `SemanticSearchError.modelUnavailable` → typed 错误（OQ-6）。Tokenization/WordPieceTokenizer 同 Core 资产链。**零新模型面、零下载触发**（搜索腿只消费已有库内 embedding 表）。

### 4.6 零回归面申报

不改：registry 错误码表语义（OQ-6 若行使 = additive 一 case）、既有 20 工具 descriptor/handler、`McpTimeouts`（若不新加档）、`PhotoProjection`、session 域查询、sidecar 写面、`.metal`、Project.swift（新测试文件落 APP bundle 需显式清单 +BUNDLE-MAP 一行 + `tuist generate` 恒末位——CONVENTIONS M2-4-0 E2 纪律；**注意 plan 期确认 SearchState 测试落 APP 还是新域**，默认 APP 与既有 Mcp* 同 bundle）。

## §5 测试策略（验收形态兑现）

1. **parity golden（对齐 GUI 同源查询）**：
   - EXIF 臂：同 fixture `.lalb` 上，`search_photos` 输出 id 集 ≡ 直调 `LibraryQueries.searchPage(filter: ExifSearchFilter(group:plan:))` 结果集（同 sort/anchor 序）；`ExifSearchParser.parse(query)` plan 恒等断言（工具与 GUI 共用 parse——GUI 同源的结构性保证）；FilterSQL WHERE/bind 快照钉死（`FilterSQLTests` 同型）。
   - CLIP 臂：mock `SemanticSearching` 注入（`LibrarySearchModel` 测试先例，CI 零模型资产）——确定性 fixture embedding 下 hit 序/分数投影恒等。
   - 全文臂：fixture `ai_understanding(_fts)` 行 → 工具输出 ≡ `AIDescriptionService.imageIDs` 直调（rank 序恒等）。
2. **get_history golden**：fixture sidecar 文档（param/structure/paste/drt/film 五种 item + versions 三条 + note/keywords）→ 投影 JSON byte-equal golden；`includeParams` 两档；`position=-1` pristine 面。
3. **get_state golden**：无头无项目 = typed nulls 契约测试；context 注入 fixture 后字段面快照（project/workspace/editor/control/tasks 各臂至少一活一空）。
4. **快照同批**：第 4 层域快照（3 工具 name/description/schema verbatim）+ union 20→23（冻结表加三行 + 计数断言显式改，M5-1-03 KD-1 先例）；白名单负测（未注册名 = internalError）随域快照。
5. **锁/只读负测**：只读臂 openReadOnly 服务 search（fixture 双进程锁形，`McpHostTests` 先例）；`requiresWriter:false` 不计 `writeCallCount` 断言。
6. **零回归**：既有 20 工具快照零 diff + `McpHostTests`/`McpEditingToolsetTests`/`McpCullingToolsetTests` 全绿；收尾跑定向 APP bundle（`Scripts/test-direct.sh --bundle App`）；全套 `--all` 留 phase 收口（orchestrator 批准制）。
7. **zh-audit**：`uv run python3 Scripts/zh-audit.py --check` PASS（三新键尾块纯插入；V17 门）。

## §6 OQ-M7-2-1..8（每条带推荐）

| # | 问题 | 推荐 | 备选 |
|---|---|---|---|
| 1 | `search_photos`/`get_history` 地址域：库域（open `.lalb`）主域？ | **是**——GUI 三段搜索/SemanticStore/FTS 全库域单源；session 域不动（`list_photos` 已覆盖）；`get_history` 双地址制（digits 库 id + relPath，match_color 先例） | session 域扩（否——session 无 FTS/CLIP 面，等于重写检索） |
| 2 | `mode` 形态：显式三枚举 `exif|clip|fulltext`？ | **是**，默认 `exif`；auto 分类器缓（Alcedo classifier = GUI 启发式，我方无单源；挂账后置） | auto 单入口（本波不做） |
| 3 | 分页与结果集：EXIF 臂 keyset cursor + 窄投影，CLIP/全文臂有界 top-K 不分页？ | **是**——库域 OFFSET 禁令；CLIP 帽 256 / 全文帽 500（GUI 同值）；缩略图走既有 `get_thumbnails`；CLIP 超时贴线则升 20s 档（复用 `thumbnailsAndContact`） | offset/limit（违库域纪律）；结果内嵌缩略图（重复 image 三件能力） |
| 4 | `get_history` 载荷深度：默认 summary + `includeParams` 开关？ | **是**——summary = id/label/timestamp/kind/layerScope；params 面按需（agent 自查序列主要消费 label/kind 序）；author 字段前向占位（M7-4 MCP2-09 落地后填充） | 全量 params 恒载（响应膨胀，500 item 帽下不可控） |
| 5 | versions 面归属：`get_history` 内带 meta（id/name/createdAt/updatedAt/active），chain 留给 M7-3 `list_versions`？ | **是**——两波不重复；`list_versions` 做完整链/切版本投影 | get_history 带全链（与 M7-3 重复） |
| 6 | CLIP `modelUnavailable` 错误编码：新增 `McpToolError.modelUnavailable`（15→16 additive 显式改）？ | **是**——GUI `ErrorFamily.modelUnavailable` 同源 typed 诚实面；message 携「bundled CLIP assets missing/failed to load」 | 复用 `notSessionMember`/`invalidParams`（语义错位，排障误导） |
| 7 | 无头 `--project` 只读臂：`openReadOnly()` 后服务三读工具？ | **是**——零写险（schema 守卫 + 写断路器），agent 在只读臂仍有检索/自查价值；M6-1 connect-guidance 不变双通道并存 | 保持不 open（三工具只读臂诚实空态——降级可后补） |
| 8 | `get_state` tasks 面 v1 范围：M2 导出队列计数 + control + server 自身，merge/pano/AI-worker 队列不入？ | **是**——M7-4 `list_tasks` 若立项再扩（ROADMAP 预埋）；workspace/editor 字段无头臂诚实 null（推荐随本条一并钉死） | v1 带全部任务族（无消费者，且 legacy 面） |
| 9 | 库 seam 形态：新 context 自带 `library` provider（独立注入）？ | **是**——provider closure 形（14-1 纪律）；`MatchColorToolset.installLibraryProvider` static box 不泛化复用 | 复用 match_color static box（单例共享语义混淆） |

## §7 plan 拆分建议（1 plan）

- **T1**：`SearchStateToolset` + `search_photos` 三路由 + context/seam + GUI/无头装配 + EXIF/CLIP/全文 parity golden + 解析错/modelUnavailable typed 面。
- **T2**：`get_history` + `get_state` + golden（含只读臂 openReadOnly 负测〔OQ-7 行使时〕）。
- **T3**：快照三层同批（域层新文件 + union 20→23 + 计数断言）+ Project.swift/BUNDLE-MAP 登记 + `tuist generate` 恒末位 + xcstrings 三键 + zh-audit + 定向 App bundle 轮 + SUMMARY/DECISIONS + REQUIREMENTS MCP2-01..03 翻账。
- SC 判定式：parity golden 三臂恒等 ✓ + 快照同批 ✓ + 既有 20 工具零回归（快照零 diff + 定向轮绿）✓；ΔN 预期 +12..+20 测试（估），全套轮留收口。

## §8 风险与边界

- **域分界心智**：`list_photos`（session）vs `search_photos`（library）并存——tool description 必须一句写明 addressing；M7-6 SKILLS-01 承载完整边界表。
- **cursor 稳定性**：keyset anchor 跨调用依赖库不重排；库变更后旧 cursor 可能跳行/漏行——与 `list_photos` 同风险同口径（不引入 cursor 版本戳，与先例一致；登记为已知边界）。
- **`get_state` 热态**：@Observable 态经 seam 取值即快照，不保证调用间一致（一行快照语义，Alcedo 同构）；文档注明。
- **GPL 边界**：Alcedo 命令语义对表合法（survey §6）；我方工具名/参数/schema 全部自写（snake_case MCP vs 点分 JSON-RPC 天然异构）。
- **快照串行**：本波若与 M7-3/M7-5 并行派发即违规——orchestrator 编排保证 M7-2 先行（ROADMAP §M7 边界「唯 MCP 快照面改动须串行」）。

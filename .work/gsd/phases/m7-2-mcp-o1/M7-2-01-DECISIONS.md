# M7-2-01 DECISIONS — 执行批裁定记录（2026-10-16 夜间批）

> executor = ZCode subagent（夜间全自动授权在案，先例 D-07-3-T5-1）。
> 本文件只记执行中的裁定与显式改申报；裁决正本 = `M7-2-CONTEXT.md`
> （D-M7-2-1..9 全按推荐落定，执行中零重开）。

## §1 显式改申报（快照族 + 错误码表）

1. **union 快照显式改 20→23**（D-14-CONTEXT-3 机制内；本波持 union 文件
   改动权，M7-3/M7-5 串行在后）。全点位（commit `32055308`，F-1 清单
   逐项兑现）：
   - 冻结表：新增 `searchStateTools` 三行（name/schema verbatim +
     `readOnlyHint: true`），`all20` → `all23`（editing + culling +
     searchState 三段拼接）；
   - 计数断言 ×4：`testFinalSnapshotUnion23Verbatim`（:209 23）、
     `testDomainSnapshotsComposeIntoTheUnion`（u.count 23）、
     `testPostUnionToolIsWhitelistNegative`（tools.count 23）、SC7
     `directTools.count`（23）——测试名 `Union20` → `Union23`（M5-1-03
     先例形）；
   - 组合代数（:200 同位）：`Set(u) == Set(e).union(Set(c)).union(Set(s))`
     **三集合并** + 三对 pairwise disjoint 断言——三新工具入**新域**
     （searchStateOnly registry 独立断言 `Set(s)`），非并入 editing/culling
     （与 M5-1-03 match_color 并入既有域的先例形刻意不同）；
   - `descriptionKeys` +3 行（search_photos/get_history/get_state →
     mcp_tool_desc_* 三键），`:274 对账断言`（key map == descriptor
     names）随之过门；
   - `makeUnionRegistry` + SC7 `startHTTPHost` 均传 fixture
     `McpSearchStateContext()`（不传则 23 计数永不可达——F-1 点位）；
   - 表头注释同步（layer 表 + 搜索/state 域行 + M7-2..M7-5 串行注记）。
   - editing(6)/culling(14) 两层快照文件**零触**（git diff 核）。
2. **`McpToolError.modelUnavailable` additive 15→16**（D-M7-2-6 机制内
   显式改）：`code` switch + message 提取 switch 各补一臂；16 值穷举
   测试钉死（`testMcpToolErrorCodesSixteenValuesExhaustive`）；adapter
   走 `.code/.message` 通用面零改。
3. **worker 族映射终形（F-3）**：`AIWorkerClientError` 四案
   （workerUnavailable/workerCrashed/workerExhausted/requestFailed）→
   全部归 `modelUnavailable`，message 携
   `semantic worker unavailable: <String(describing: error)>`（案名 +
   细节）；`dimensionMismatch` → 同码，message 携
   `semantic model dimension mismatch: <detail>`。测试钉两案
   （mismatch + workerUnavailable/workerCrashed/workerExhausted）。
4. **xcstrings 三新键尾块纯插入**（历史键字节与顺序零触碰——git diff
   删除行空核）：`mcp_tool_desc_search_photos` / `_get_history` /
   `_get_state`，zh-only 块形（match_color 先例）；zh-audit --check +
   --self-test 双 PASS（1691 source keys 扫描可见，无动态族新增）。

## §2 实现裁定（评审修订批的落地行使）

1. **两段走法翻段规则（E-2 的边界补全）**：主段锚定 seek 对 NULL-key 行
   永假（row-value 比较遇 NULL 不为真）→ 翻段完全可从页形推导，落
   `advanceMain` 头注六规则：空页（anchored）→ 翻段 tier 头；满页键尾 →
   留主段；满页 NULL 尾 → **NULL tier 已在本页内开始** → 翻段携
   NULL 行 path 锚（尾段 seek 从它之后续走）；短页（anchored）→ 翻段
   tier 头；短页（unanchored）→ 全库已尽（NULL 行随本页返回）→ 无
   cursor。golden 对照腿在 limit=3 下 NULL 行不进主段页（12 行 fixture），
   两腿同构且实现路径独立（直调 LibraryQueries 双查询）。
2. **尾段续页 anchor 手搭（R-2）**：`.anchor(of:key:)` 对 NULL 行返 nil，
   尾段锚 = `LibraryPageAnchor(keyValue: .int(nil), imagePath:)` 手搭
   （LibraryGridModel.advanceTail 同款）；空 path 的 nullTail token 解码
   后即 tier 头（`image_path > ''` 恒真）——尾段首页与续页同一 token 形。
3. **cursor token（R-3 落地）**：payload = `{k, d, p, v, s}`（PhotoProjection
   同形 + segment）；`s` 缺失 = typed invalidParams（跨工具 token 拒——
   测试用 list_photos 形 payload 亲证）；main token 无 `v` = garbage 拒；
   token 键/向须与请求 sort 一致（换键失效负测亲证）。
4. **窄投影九字段列映射终值（D-M7-2-3「以 images 表实存列为准」核）**：
   `imageID`=images.id / `imagePath`=image_path / `filename`=filename /
   `dir`=dir / `captureDate`=capture_date / `rating`=rating /
   `flag`=flag / `colorLabel`=color_label / `hasEdits`=has_edits——九字段
   全有列支撑，「无列支撑字段如实缺席」条款零行使，schema 面零 additions。
5. **CLIP 超时档裁定**：维持 `McpTimeouts.list`（10s）——fixture 级
   mock 测试无贴线证据；万级库 vDSP 扫贴线实测超时才申报升 20s 档
   （本波零实测数据，不预设升档）。
6. **fulltext limit 语义**：seam 与 LibrarySearchModel fulltextProvider
   同形（`(String) async throws -> [Int64]`，无 limit 参）——工具面
   `limit` 走客户端侧 `prefix(limit)` 切片，bm25 rank 序保序。
7. **get_state 快照载体五面**：`McpSearchStateLiveSnapshot` =
   {project, workspace, editor, tasks, server}（plan T3 action 3「project
   也从 liveState 缝取」兑现——T1 骨架时仅三面，T3 补 project/server）。
   server face 的 host mode + readOnly 立场为宿主派生事实（handler 无法
   自证）；identity（name/version）handler 兜底。
8. **GUI workspace 面诚实缺省（小偏差，DECISIONS 申报）**：D-M7-2-8 的
   workspace face 规格含 filter 投影 + selectedIDs +
   editorPhase.currentImageID——三者在 `WorkspaceModel.LibraryPhaseState`
   （**per-window** @FocusedValue 形），app 级装配点不可达（亲核
   LightamerApp :462 `focusedWorkspace` 链）。GUI liveState 闭包如实
   渲染 `filterSummary: null / selectedCount: null` +
   `currentSessionRoot`（app 级可达的 session root）。字段键保留（行形
   稳定，客户端按键名不按存在性）；无头臂全 null 契约不受影响。属
   「宿主看不到的字段 = null 诚实面」条款的自然行使，非裁决重开。
9. **library seam projectDirectory 语义勘正（fix `20997721`，T5 golden
   抓获）**：E-1 修订批的 provider 形 `(store, projectDirectory)` 在 GUI
   装配沿用 match_color provider 的 `projectURL` 直传——但 ImageLinker
   `.projectRelative` 解析 = `projectDirectory.appendingPathComponent(
   imagePath)`，锚必须是**包所在目录**（`deletingLastPathComponent()`，
   WorkspaceHostView urlResolver 先例形）；match_color 传文件 URL 未爆
   仅因其 golden 行走 absolute kind。GUI + headless 两装配点同批勘正；
   get_history digits 臂 golden 由「恒 stale」转绿。
10. **historyItemCap = 500 常量单源**（F-5）：`min(全量, 500)`、截断保
    留最新端（suffix 窗）、position/itemCount 恒真值 + 显式 `truncated`
    旗标（agent 检出截断不依赖窗口推算）。
11. **kind 判别优先序**（D-M7-2-4 五臂 + N-5 双载荷）：pasteSet → drt →
    film → stackSnapshot → param。双载荷项（pasteSet+stackSnapshot 并存）
    判 paste——payload 专一性优先（OVERWRITE paste 的 stackSnapshot 骑
    paste epoch 内，N-5 评审亲核语义）。
12. **includeParams 面形**：param/structure 项 =
    `{opName, multiPriority, multiName, enabled, paramsBase64}`（canonical
    params 编码字节 base64——sidecar 回程同形）；paste 项 =
    `{records: [recordIdentity…]}`；drt/film 项 = null（占位 snapshot
    剔除——HistoryStack scope-marker 语义，KD-1 硬约束的面化）。

## §3 T4 判据通道（F-2 甲落地申报）

- **甲落地**：`startReadOnlyHTTPHost` 在 DEBUG + `LIGHTAMER_MCP_ENDPOINT_DIR`
  域内写独立 discovery 文件 `mcp-endpoint-readonly.json`（McpEndpointInfo
  v1 同 schema）；Release 编译零触（`#if DEBUG` + env 双门）；writer 的
  `mcp-endpoint.json` 零触碰（测试断言亲证 nil）。乙（registry 级降格）
  未行使、丙（stderr 刮端口）不采。两进程测试
  （`testReadOnlyArmServesSearchPhotosTwoProcess`）经读缝拿端口 → HTTP
  亲调 search_photos（返回 held 包行）+ get_state（heldByOther=true）。
- **McpEndpointFile additive 两缝（R-1）**：write/read/remove ↔
  writeReadOnly/readReadOnly/removeReadOnly 六面共享同一体（
  writePayload/readPayload 私有体），既有 writer 面语义字节零改；禁令
  「McpServerController 内二写 discovery 逻辑」守住（调用点只写 info）。
- **openReadOnly 降级臂**：heldByOther 臂 emitConnectGuidance 后
  `try await store.openReadOnly()`（锁免 + schema 守卫 + 写断路器原样）；
  失败 = nil seam + log，禁 exit。stdio EOF 腿 `try? close()` 自然覆盖
  只读 store 释放（N-7：writer 持 WAL 时 checkpointTruncate typed 失败
  被吞 + 进程退出兜底——既有语义，非本波新增面）。

## §4 已知边界登记（不阻塞）

- **cursor 跨调用稳定性**：与 list_photos 同风险同口径（库重排后旧
  cursor 可能跳行/漏行；不引入 cursor 版本戳——先例一致）。
- **auto 分类器后置挂账**（D-M7-2-2）：mode 显式三枚举，auto 分类器
  不入 v1（Alcedo classifier 是 GUI 启发式单源，引入 = 新面非复用）；
  挂账 M7-4+（若立项）。
- **author 恒 null**（前向占位）：M7-4 MCP2-09 commit attribution 落地
  后填充（负测钉死）。
- **GUI workspace 面字段**（§2.8）：filter/selectedIDs 恒 null（per-window
  不可达）——若 M7 站后续需要真值，须给 shell 注册一道 workspace 汇集
  缝（新 plumbing，本波不做）。

## §5 逐 commit 链

| commit | 内容 |
|---|---|
| `9f69775b` | T1 骨架 + context + registry 第三参 + 五缝装配 + xcstrings 三键 |
| `5a89f07f` | T2 search_photos 三路由 + modelUnavailable additive |
| `028c6230` | T3 get_history/get_state 只读投影 |
| `9efbd976` | T4 只读臂 openReadOnly + discovery 变体两缝 |
| `20997721` | fix: projectDirectory 锚勘正（T5 golden 抓获回注） |
| `32055308` | T5 测试批 + union 20→23 + 登记 + tuist generate |

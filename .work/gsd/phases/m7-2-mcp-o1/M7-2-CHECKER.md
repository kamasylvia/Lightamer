# M7-2-CHECKER — 修订版 M7-2-01 plan 独立反向核（2026-10-16）

> 评审身份：fixer 后独立 checker 批（同 worker 两阶段，本文件 = checker
> 阶段产物；反向核以**修订后 plan 全文** + 评审正本 + 代码面 HEAD 亲核，
> 非 fixer 阶段结论的转述）。
> 输入 = 修订版 `M7-2-01-PLAN.md`（fixer 批 commit `9e244534` + 本批
> checker 微修）+ `M7-2-01-PLAN-REVIEW.md` + `M7-2-CONTEXT.md`（评审
> 修订批同版）+ `M7-2-RESEARCH.md`（§0/§3/§4/§5 抽读）+ `.work/gsd/ROADMAP.md`
> §M7-2 行 + 代码面（`LibraryQueries.swift` / `LibraryStore.swift` /
> `SemanticStore.swift` / `AIDescriptionService.swift` /
> `LibraryGridModel.swift` / `McpServerController.swift` /
> `McpEndpointFile.swift` / `McpFinalSnapshotTests.swift` /
> `AIWorkerClient.swift` / `LightamerApp.swift` / `PhotoProjection.swift`
> ——逐点实读）。
>
> **结论头：放行**。E-1（修法甲）+ E-2（修法甲）+ F-1..F-6 + N-2..N-8
> 修订全部落位、判据链可机检、新旧口径无残留矛盾（grep 机检过：
> `LibraryStore, projectDirectory` / `默认全量、最大 500` /
> `四处计数断言` 旧形零命中）；独立猎残 4 处（R-1..R-4，全 minor /
> 簿记级）已在本 checker 批并入 plan 微修（§四），零阻塞残留，可派发
> 执行批。

---

## 一、Goal-backward：修订版达成性

ROADMAP §M7-2 行验收形态三条 ↔ 修订版任务面逐项映射（亲核 ROADMAP
:106 原文「三工具 parity golden ✓ + tools/list 快照同批更新 ✓ + 既有
20 工具面零回归 ✓」）：

1. **parity golden（形态①）**：T5 action 1 三臂——EXIF 臂两段对照
   （工具跨调用拼接 ≡ 直调 searchPage+searchNullTail 拼接）+ CLIP mock
   + 全文 rank 恒等。E-2 修订后 EXIF 臂 golden 不再单段失明
   （fixture 必含 NULL-key 行 + 双向可达断言 + 翻段链路断言）——
   「对齐 GUI 同源查询结果」在分页面上成立（GUI = LibraryGridModel
   两段走法，:5-13/:88-91 亲读）。**达成**。
2. **快照同批更新（形态②）**：T5 action 4 域快照新层 + union 显式改
   全点位（F-1 清单）。**达成**。
3. **既有 20 工具零回归（形态③）**：T5 action 5 两层快照零 diff +
   McpHostTests/McpEditingToolsetTests/McpCullingToolsetTests 全绿 +
   T4 序列 A/B 零 diff 绿。**达成**。

REQUIREMENTS MCP2-01..03 三行无孤儿项（front-matter `requirements`
逐条入任务面）；Alcedo 对表锚 `search.query` / `editor.history` /
`state.get` → search_photos / get_history / get_state 一一对应
（CONTEXT Goal 段亲读一致）。**Goal-backward 通过**。

## 二、核心修订自洽（逐 error/minor 反向核）

### E-1（provider 形 = ProjectFileStore）——四宿主缝全通 ✓

- 单源面亲核三 init：`LibraryQueries(store: ProjectFileStore)`
  （LibraryQueries.swift :209-212）/ `SemanticStore(store:
  ProjectFileStore)`（SemanticStore.swift :58-63）/
  `AIDescriptionService.imageIDs(matching:store:limit:)` 的
  `store: ProjectFileStore`（AIDescriptionService.swift :146-149）——
  provider 直携 ProjectFileStore 后三路由取数源全通。
- 派生面亲核：`LibraryStore` 的 `store` 仍 private 无 accessor
  （LibraryStore.swift :103），公开 `init(store:)`（:105）在位；
  get_history digits 臂（`LibraryStore.image(id:)` :452）由 toolset
  现场派生——GUI match_color 装配点
  （LightamerApp :1362-1371 `LibraryStore(store: store)` 派生形）
  先例在位。
- **四宿主缝逐一过**：①GUI embedded = `libraryProjects.projectStore`
  （ProjectFileStore）✓；②headless writer 臂 = `headlessProjectStore`
  （:167 类型亲核 `ProjectFileStore?`——直携吻合）✓；③heldByOther
  只读臂 = T4 openReadOnly 后同载体 ✓；④无 `--project` 臂 = nil →
  typed notSessionMember ✓。semanticStore 同源派生同型 ✓。
- files_modified 对账：无 LibraryStore.swift（不加 accessor 纪律
  维持）✓；T3 action 1 digits 臂派生注记同步在位 ✓。
- **自洽通过**。

### E-2（EXIF 两段走法 + cursor segment + golden 失明消除）——机制逐点核 ✓

- 两段走法与 GUI 一一对应亲核：`searchPage` 恒 `nullTail: false`
  （LibraryQueries :231-236）/ `searchNullTail` 独立 NULL-tier 查询
  （:239-256，五键全可空）/ LibraryGridModel `Segment{main, nullTail}`
  翻段形（:88-91, :260-292）。
- **cursor token 编码自洽**：PhotoProjection.Cursor payload
  `{k, d, p, v}`（base64 + sortedKeys，:198-232）加 `segment` 字段
  ——sort 键 + 方向嵌入白拿换键失效负测（:203-205 注记先例形）；
  segment 缺失 = typed invalidParams 拒（R-3，本批钉死——防跨工具
  token 静默串用）。
- **翻段与续页 anchor 语义核**：翻段首尾页 anchor=nil（plan T2
  action 2 在位）✓；尾段续页 anchor 必须手搭——`.anchor(of:key:)`
  对 NULL-key 行返 nil（LibraryQueries :89 `guard let value else
  { return nil }`），GUI `advanceTail` 手搭
  `LibraryPageAnchor(keyValue: .int(nil), imagePath: last.imagePath)`
  （LibraryGridModel :294-300 注记正本「key value unused, image_path
  is the only seek」）——**此实现细节评审与 fixer 批均未点名，独立
  猎残 R-2，已补进 T2 action 2**（不补则执行批用 `.anchor(of:key:)`
  得 nil，尾段分页断）。
- **golden 失明消除验证**：对照腿 = 两段拼接（与工具腿同构但独立于
  工具实现路径）+ fixture 必含 NULL-key 行（unrated / 无 captureDate）
  + sort=rating / sort=captureDate 两向可达断言 + 翻段链路断言——
  单段回归（执行批静默回摆）会被 NULL-key 可达断言抓住。**失明洞
  闭合**。
- 与 GUI 的同页补齐差（GUI 主段短页立即以 `remaining` 拼尾段同页，
  :272-280；MCP 主段短页即发 nextCursor 下一调用走尾段）= 行覆盖与
  顺序等价（主段行恒先于尾段行，keyset 序不变）——golden 两段拼接
  对照在序列域恒等，非偏离。**自洽通过**。

### F 族逐条（抽核）

- **F-1**：union 全点位亲读 McpFinalSnapshotTests.swift 对账——
  :174/:202/:230/:373 计数 ✓；:200 `XCTAssertEqual(Set(u),
  Set(e).union(Set(c)))` 三新工具入新域必红、须改三集合并 ✓；
  :237-259 descriptionKeys + :274 对账 ✓；:159-160 makeUnionRegistry
  现调两参不传 searchState、23 计数永不可达 ✓；:363 SC7
  startHTTPHost 两参现形、:373 directTools.count 前提 ✓；:22-27
  表头 + :226 注释 ✓。fixture context = 全 nil provider 的
  McpSearchStateContext（注册面零 provider 消费，handler 调用才触）
  ——可落地 ✓。
- **F-2 甲**：判据通道自洽亲核——`headlessEndpointPaths` 的
  `#if DEBUG` + `LIGHTAMER_MCP_ENDPOINT_DIR` 门形（McpServerController
  :115-124）可复制；独立文件名不覆 writer `mcp-endpoint.json`（
  guidance 真相源零触碰——:316-323 Release 注记语义保留）✓。
  **实现载体缺口（独立猎残 R-1）**：`McpEndpointFile.write/read` 只
  写读固定名 `mcp-endpoint.json`（`jsonURL` computed 固定拼接，
  McpEndpointFile.swift :34/:145/:164 亲读）——独立文件名变体需要
  McpEndpointFile.swift additive 两缝（或 paths 参数化）；原
  files_modified 未含该文件。已补申报（§四 R-1）——变体落
  McpEndpointFile.swift，禁在 McpServerController 内二写 discovery
  逻辑。**自洽（补申报后）通过**。
- **F-3**：AIWorkerClientError 四案亲读（AIWorkerClient.swift :31-43）
  ✓；归 modelUnavailable 的语义论证（「语义运行时对本查询不可用」
  族 + internalError 误导面）与 D-M7-2-6「语义诚实优于错误码数量
  最小化」同构 ✓；CONTEXT D-M7-2-6 补记 + 被否备选补 internalError
  行 ✓；T5 action 6 worker 族映射一法在位 ✓。
- **F-4**：①EmbeddedState box 存取形亲读（:721-750）——searchState
  随 box 存取 + on-leg 读出透传 + grep 点位含 startEmbeddedServer，
  off→on toggle 三工具静默缺席缺口闭合 ✓；②writeCallCount null
  诚实面亲读 `embeddedWriteCallCount()`（:585-588 只读 embedded
  box handle，stdio/只读 face 无外露面）——GUI embedded 走同源、
  其余 null ✓；「不立项新 plumbing（无消费者）」论证成立 ✓。
- **F-5**：min(全量,500) + 截断保留最新端 + itemCount 真值——
  T3 action 1 / front-matter SC / T5 golden >帽断言 / CONTEXT
  D-M7-2-4 四处一致 ✓；与 D-H2「no cap」无矛盾（帽是工具面语义，
  HistoryStack 不改——封存面零触）✓。
- **F-6**：机检双判据可执行——①fixture liveState 闭包内
  `dispatchPrecondition(condition: .onQueue(.main))` + 调用计数
  （get_state 断言「闭包被调且在主线程」= hop 结构在位的可执行
  判定）；②grep SearchStateToolset 源四类型名零直接引用（handler
  只摸 context closure）——两条皆命令级判据 ✓。

### 8 注记落位核

N-2（fresh-group 无状态 description，T2 action 2）✓；N-3（默认 sort
filename asc，T2 action 1 + D-M7-2-3）✓；N-4（越臂组合 typed 拒 +
T5 负测 + token 嵌 sort 键白拿负测）✓；N-5（双载荷项 golden 显式
先序断言，T5 action 2）✓；N-6（imagePath 相对语义，T2 action 2）✓；
N-7（checkpointTruncate 知悉，T4 知悉块）✓；N-8（六调用点/四缝 +
EmbeddedState 对账形，T1 AC + front-matter SC）✓；N-1（基线知悉，
修订记录尾行）✓。

## 三、独立猎残（本批新产出，评审简报维度外）

- **R-1【minor｜F-2 甲实现载体】**：只读 discovery 独立文件名的
  写读变体不在既有 `McpEndpointFile.write/read` 面上（固定名
  `mcp-endpoint.json`）——files_modified 缺 `McpEndpointFile.swift`
  申报。**处置 = 已补申报**（additive 变体两缝，既有 write/read
  与 mcp-endpoint.json 语义零改；禁二写 discovery 逻辑）。
- **R-2【minor｜E-2 实现细节】**：尾段续页 anchor 须手搭
  （`.anchor(of:key:)` 对 NULL-key 返 nil）——评审/fixer 批只钉了
  翻段 anchor=nil，续页 anchor 语义缺席。**处置 = 已补进 T2
  action 2**（advanceTail 同款手搭形 + LibraryQueries :89 guard
  引证）。
- **R-3【minor｜E-2 token 语义】**：cursor payload 加 segment 后
  「segment 缺失」语义未钉——list_photos token（无 segment）传入
  search_photos 会被静默接受（FilterSortKey 枚举共享，k/d/p/v
  结构同形）。**处置 = 已钉「缺失 = typed invalidParams 拒」**
  （cursor 是 OUR token 纪律，PhotoProjection decode garbage 同形）。
- **R-4【cosmetic｜措辞】**：四处旧口径残留——①T1 action 1 尾部
  多余 `**` 标记；②T2 blockquote 单源红线只列 searchPage 未列
  searchNullTail；③全局 read_first :571-587 应为 :571-588；④风险
  归因行单源清单缺 searchNullTail。**处置 = 全部已修**。

未发现结构性驳回项：T1-T6 任务序 / 九裁决归属 / 波次 / 量级带 /
封存面 17 件零交集（R-1 的 McpEndpointFile.swift 不在封存清单——
亲对 front-matter red_lines 封存面清单确认）/ GPL 对表纪律 /
files_modified 骨架（R-1 为 additive 一件申报，非骨架变动）。

## 四、checker 批微修清单（并入修订版 plan，本 commit 随附）

1. files_modified 补 `McpEndpointFile.swift`（R-1）+ T4 AC diff 面
   同步（additive 变体两缝）。
2. T2 action 2 补尾段续页 anchor 手搭（R-2）。
3. T2 action 1 补 segment 缺失 = typed invalidParams（R-3）。
4. R-4 四处措辞（多余 `**` / T2 blockquote 两查询 / :571-588 /
   风险归因行补 searchNullTail）。

## 五、SC 可机检性 + 红线对账（修订后复扫）

- front-matter SC 逐段复核：T1（负测 + 装配断言 + N-8 对账 grep）/
  T2（两段 golden + NULL-key 可达 + 五件错误臂 + 越臂拒）/ T3
  （byte-equal + 截断方向 + F-6 双判据）/ T4（F-2 甲通道 + 序列 A/B
  零 diff）/ T5（union 全点位 + 16 值穷举 + worker 映射法）/ T6
  （对账式 + 红线机检 + zh-audit）——每条有命令级判据，非目测 ✓。
- 红线族复核：快照族 additive 显式改（union 改动权串行编排不变）/
  既有 20 工具零 diff / 三新工具恒只读 / 封存面零触（R-1 新申报件
  不入封存清单）/ xcstrings 三新键尾块纯插入 / Project.swift +
  BUNDLE-MAP 恰一行 + tuist generate 末位——逐条在位零松动 ✓。
- 残留口径 grep 机检：`LibraryStore, projectDirectory` /
  `默认全量、最大 500` / `四处计数断言` / `searchPage（同 sort`
  旧形在 plan+CONTEXT 零命中（fixer 批后亲跑）✓。

## 总评

**放行**。E-1/E-2 两 error 修法甲落位且机制自洽（E-1 四宿主缝全通
+ 零 Core diff；E-2 两段走法与 GUI 一一对应 + golden 失明洞闭合）；
F-1..F-6 判据全部机器可判；8 注记按性质落位；独立猎残 R-1..R-4
（全 minor/簿记级）已在本 checker 批并入 plan 微修，零阻塞残留。
修订后 plan 可派发执行批。

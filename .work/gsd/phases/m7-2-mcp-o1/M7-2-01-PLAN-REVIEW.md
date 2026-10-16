# M7-2-01 PLAN 评审（独立 zcode 路，2026-10-16）

> 评审身份：独立 plan 评审（替代 omp 路），零共享上下文。
> 输入 = `M7-2-01-PLAN.md` + `M7-2-CONTEXT.md` + `M7-2-RESEARCH.md`
> + 先例教训正本（`FIX2-01-PLAN-REVIEW.md` M-2 priming、
> `V2M-PLANS-REVIEW.md` E-2 供给面、`M6-6-01-PLAN-REVIEW.md` /
> `M7-1-01-PLAN-REVIEW.md` F1 可观测性家族）+ 代码面 HEAD 亲验。
> 评审时 HEAD = `55dc2552`（plan docs commit，其前一跳 `d08306fd` =
> research docs——plan 自述基线 `3860/35/0` 两跳均 docs-only，
> `git log`/`git status` 实跑亲核，产线基线未漂移）。下引 file:line
> 全部实读/实跑，非转述。
>
> **结论头**：
> - **M7-2-01 = 须修后放行——2 error + 6 minor + 8 注记**。骨架（T1-T6
>   任务序 / 九裁决速查 / 只读三面结构性不触 / 快照同批三验收形态 /
>   ΔN 对账式 / 红线族）成立且证据链亲证。两个 error 均为「SC 按现文
>   必然放行一个语义/供给缺口」级：E-1 = context `library` provider
>   声明形（LibraryStore+URL）交付不出三路由都需要的 ProjectFileStore
>   面（V2M E-2 同族——按现文交付不出）；E-2 = EXIF 臂只走
>   `searchPage(nullTail: false)` 单段，NULL-key 行整段静默不可达，且
>   parity golden 双腿同源同缺恒等照样绿（F1 家族升格——验收门对功能
>   缺口失明）。6 处 minor 全为点位枚举/测试形/映射表/簿记级修订，
>   不动任务序、量级与裁决权归属。

---

## 一、findings

### E-1【error｜T1/T2 供给面（V2M E-2 家族）】`McpSearchStateContext.library` 声明形交付不出 search_photos 三路由的 ProjectFileStore 面

**证据链（亲验）**：

1. plan T1 action 1 + CONTEXT D-M7-2-9（生效值硬约束）钉的 provider 形 =
   `library`（`(store: LibraryStore, projectDirectory: URL)?`）。
2. 而 T2 三路由的单源全部吃 **ProjectFileStore**，不吃 LibraryStore：
   - EXIF：`LibraryQueries(store: ProjectFileStore)`（LibraryQueries.swift
     :209-212 `public init(store: ProjectFileStore)`）；
   - CLIP：`SemanticStore(store: ProjectFileStore)`（SemanticStore.swift
     :58-63）；
   - 全文：`AIDescriptionService.imageIDs(matching:store:limit:)` 的
     `store: ProjectFileStore`（AIDescriptionService.swift :146-149）。
3. `LibraryStore` 的底层 store 是 **private 且无公开访问器**
   （LibraryStore.swift :103 `private let store: ProjectFileStore`——全文件
   grep 无 accessor）；toolset 从声明的二元组拿不到 ProjectFileStore。
4. plan `files_modified` 不含 LibraryStore.swift（也不该含——为取 store
   加公开 accessor 是未申报的 Core diff）；get_history 的 digits 臂
   （`LibraryStore.image(id:)` :452 + ImageLinker.resolve）确实只需
   LibraryStore，**缺口只在 search_photos 侧**。
5. 后果：T2 按 plan 现文实现必然二选一——①偏离 D-M7-2-9 生效值
   （自裁改裁决正本）；②给 LibraryStore 加未申报的 Core 访问器
   （additive 纪律静默破口）。两者都是执行批的无授权裁定，与 M7-1
   E-1 的「无授权裁定陷阱」同构。

**修法（二选一，plan + CONTEXT D-M7-2-9 同批修订）**：

- **甲（推荐）**：`library` provider 形改为携带 ProjectFileStore——
  `(store: ProjectFileStore, projectDirectory: URL)?`，LibraryStore 需要处
  由 toolset 用公开 `LibraryStore(store:)` init 现场派生（GUI 装配点
  `libraryProjects.projectStore` 在手，LightamerApp :1364-1373 的
  match_color provider 已演示 `LibraryStore(store:)` 派生形）；或二元组
  扩为三元。CONTEXT D-M7-2-9 的 provider 清单同步改写。
- **乙**：保持 `library` 二元组不动，另加一条 EXIF 专用 provider
  （`libraryPage` closure 形：`(filter, sort, anchor, limit) async throws ->
  [LibraryImageRow]`，GUI 装配点闭包内持 projectStore 建 LibraryQueries
  ——与 `fulltext` 的 imageIDs 闭包缝同构，provider 纪律不破）。
- 无论甲乙：SC「三处宿主装配点 grep 机检」与 T5 负测不受影响；
  修订是 plan/CONTEXT 文本级，不动 files_modified（SearchStateToolset
  的字段类型变化在其自身文件内）。

### E-2【error｜T2 语义面（F1 家族升格）】EXIF 臂缺 NULL 尾段——`searchPage(nullTail: false)` 单段走法使 NULL-key 行整段静默不可达，且 parity golden 双腿同源同缺不报警

**证据链（亲验）**：

1. plan T2 action 2 唯一的分页走法 =「`searchPage`（`.library` 域 +
   `.flat`）→ … + `nextCursor`（有下页才携）。sort 键序 + image_path
   tiebreaker 单源（searchPage 原样）」——**全文零处提及 NULL 尾段**。
2. 代码面事实：`searchPage` 恒 `nullTail: false`（LibraryQueries.swift
   :231-236），主段**只含 sort key 非 NULL 行**；NULL tier 是独立查询
   `searchNullTail`（:239-256，doc 原文「every library sort key is
   nullable — … so the tail face is legal for ALL five keys」）。
3. **GUI 同源走法是两段**：LibraryGridModel.swift :5-13 头注原文
   「pagination walks `LibraryQueries.searchPage` (the forward keyset)
   **then** `searchNullTail` (the NULL tier)」+ :88-91 `Segment{main,
   nullTail}`——「search_photos 对齐 GUI 三段搜索」（ROADMAP §M7-2 /
   CONTEXT Goal）在分页面上按现文不成立。
4. 失明链：SC/T5 的 EXIF parity golden =「工具输出 id 集与序 ≡ **直调
   `LibraryQueries.searchPage`**（同 sort/anchor）」——golden 的对照腿
   用的正是同一个单段调用，**双腿共享同一盲区**：fixture 若无 NULL-key
   行、或即便利了也无排序面把它们送进 null tier，golden 恒等照样绿。
   这是 F1 教训的精确复现（验收机制对预期态失明），且失明的是
   ROADMAP 验收形态①本身。
5. 实害评估：rating/captureDate/iso/focalLength 四键全部可空——按
   rating 排序（culling 工作流常见）时**全部未评分图**、按 captureDate
   排序时全部无日期图，经分页永不可达；agent 侧表现为「搜索结果静默
   缺行」，无错误面、无日志面。对 M7-2 的立项动机（agent 最大单点
   缺口 = 检索）而言，这是核心语义缺口。

**修法（推荐甲，DECISIONS 申报终形）**：

- **甲（两段 cursor，GUI 走法复用）**：cursor token（PhotoProjection
  .Cursor 同形 base64 JSON）加 `segment` 字段（main|nullTail）+ sort 键
  + 方向 + anchor；主段耗尽 → nextCursor 翻入 nullTail 段（anchor=nil
  起 `searchNullTail`），与 LibraryGridModel 两段走法一一对应；golden
  fixture 必含 NULL-key 行（如一行 unrated + sort=rating）并断言工具
  可达该行（补 F1 失明洞）。
- **乙（显式降级裁决）**：若 orchestrator 裁定 v1 只服主段——则
  ①description 显式注明「rows whose sort key is NULL are not reachable
  via pagination in v1」（诚实面）；②ROADMAP 验收形态①的「对齐 GUI」
  措辞在该行登记显式偏离；③golden 仍补 NULL-key fixture 行断言
  「按现文不可达」防执行批静默回摆。**禁无裁决静默缺段。**
- 附带：session 域 `list_photos` 的 cursor 已在 predicate 内处理
  NULL-class 续段（PhotoProjection.swift :270 区注记）——域间形态差异
  建议在 M7-6 SKILLS-01 边界表登记一行。

### F-1【minor｜T5 快照面】union 显式改点位枚举不全——四处计数断言之外还有 4 处必改点，按现文枚举执行必红

**证据链（亲验，McpFinalSnapshotTests.swift 实读）**：

1. plan 列的四处计数断言坐标 **准确** ✓（:174 `descriptors.count == 20`、
   :202 `u.count == 20`、:230 `tools.count == 20`、:373
   `directTools.count == 20`；plan 写「:169-174」涵盖 :174 断言行）。
2. 但除此之外还有 4 处必改点 plan 未列：
   - **:200** `XCTAssertEqual(Set(u), Set(e).union(Set(c)))`——三新工具
     入**新域**，不入 e∪c，此断言必红；组合代数须改为三集合并
     （M5-1-03 先例形不能照抄——match_color 并入**既有** editing 域，
     代数不变；本波是新域，代数要改）。
   - **:237-259** `descriptionKeys` 映射表 + **:274** `Set(key map) ==
     Set(descriptors.map(\.name))`——三新工具不加三行必红（zh 面键
     对账断言）。
   - **:159-160** `makeUnionRegistry()`——现调 `makeRegistry(editing:
     culling:)` 不传 searchState；按 T1「非 nil 时 registerAll」机制，
     不传 = union 恒 20，**四处计数断言改 23 永不可达**——该 helper
     必须传 fixture context。
   - **:363** SC7 链测试的 `startHTTPHost(paths:editing:culling:)`——
     同理，:373 改 23 的前提是该调用传 searchState fixture。
3. 另 :226 注释「no 21st tool rides the list either」与冻结表头注
   （:22-27）属表头注释批（plan 已列「表头注释」项，知悉即可）。

**修法**：T5 action 4 的显式改清单补全为「冻结表 +3 行 + 计数断言 ×4 +
组合代数断言（:200）+ descriptionKeys +3 行 + makeUnionRegistry 传
fixture context + SC7 startHTTPHost 传 fixture context + 表头注释 +
测试名 Union20→Union23」；或改写为「union 文件全部 20-字面/20-断言
点位显式改 + 逐处列表见 DECISIONS」。SC 同步（front-matter T5 段）。

### F-2【minor｜T4/T5 SC 可测形】只读臂「search_photos 照常服务」SC 无端口发现通道——引用的两先例均不过线调工具

**证据链（亲验）**：

1. SC T4「双进程锁 fixture 下只读臂 search_photos 照常服务
   （McpHostTests/McpProjectArbitrationTests 先例）」。亲核两先例：
   McpProjectArbitrationTests 的序列 A/B（:175-232/:274-300）对 spawn 的
   子进程只断言 **guidance JSON + 进程驻活**（:206-207
   `child.isRunning`），**从不过 HTTP 线调用任何工具**；McpHostTests 的
   HTTP 面全部走 in-process `startHTTPHost`（handle.port 在手）。
2. 而只读 http face 按设计**不写 discovery json**（McpServerController
   :316-323 注记正本「no discovery json — that file belongs to the
   writer」），bind 的 ephemeral 端口只进 **os_log**（:393-397 `log()` →
   `AppError.logger`，非 stdout/stderr）——spawn 出来的子进程的只读
   face 端口，测试父进程**没有任何机器可读通道**可拿到。「照常服务」
   按现文无可接线判据（F1 家族：SC 对自身的观测通道不存在）。

**修法（三选一，DECISIONS 申报）**：

- **甲（推荐）**：DEBUG 门控下只读 face 也写 discovery 文件——
  `LIGHTAMER_MCP_ENDPOINT_DIR` 域内（该 env 本就是测试专用装配根读，
  McpServerController :121-130），Release 路径零触；测试经既有
  `McpEndpointDiscovery` 拿端口，先例（McpHostTests）全复用。
- **乙**：降格 SC 措辞——registry 级 in-process 测试（readOnlyMode
  store + `writerCheck { false }` + search 走通）+ 序列 A/B 驻活门照旧；
  「双进程过线」保真放弃，如实登记。
- **丙**：stderr 人类行携端口 + 测试刮 stderr——弱且脆，不推荐。

### F-3【minor｜T2 错误映射表】CLIP 腿 worker 族错误未映射——M2-10-05 后 production runner 是 worker 进程，4 案 typed 错误走无码兜底

**证据链（亲验）**：

1. plan T2 action 5 的 CLIP typed 错误臂只列 SemanticSearchError 两案
   （modelUnavailable / dimensionMismatch 双映射）。
2. 代码面事实：M2-10-05 switch line 后 `AIInferenceService.engine()`
   的 runner = **AIWorkerClient**（进程隔离 worker，M2-10-05 注记正本）；
   `SemanticEngine.search` 内 `runner.embedText` 抛
   **`AIWorkerClientError`** 4 案（AIWorkerClient.swift :31-43：
   workerUnavailable / workerCrashed / workerExhausted / requestFailed）
   ——这些**不是** SemanticSearchError，会穿透出 search。
3. adapter 只捕 `McpToolError`（McpAdapters.swift :40-45）——worker 族
   未映射 = 无 `[code]` 前缀的协议级兜底错误，GUI 侧同型错误映射
   `.semanticQueryFailed`（LibrarySearchModel :211-214 的 catch-all
   正本）——MCP 面按现文比 GUI 面排障信息更差。
4. GUI 同源 claim：LibrarySearchModel 的 CLIP 腿 catch 顺序 =
   SemanticSearchError 两案 + **catch-all 一案**——plan 只搬了前两案。

**修法**：T2 action 5 补第四臂：AIWorkerClientError 族 → 显式映射
（推荐归 `modelUnavailable`「语义运行时对本查询不可用」族——与
D-M7-2-6 的「语义诚实优于错误码数量最小化」裁定一致，message 携
worker 细节；或 `internalError`——二选一 DECISIONS 钉死）；T5 的
typed 错误臂测试同步补一法（mock searcher 抛 workerUnavailable →
断言映射码）。

### F-4【minor｜T1 装配簿记】EmbeddedState 第五缝未点名 + headless writeCallCount「既有面透传」为空集

**证据链（亲验）**：

1. 「四宿主缝」（startHTTPHost / startHeadlessStdioHost /
   startReadOnlyHTTPHost / startEmbeddedIfPreferenceEnabled）漏了
   **内部第五缝**：`startEmbeddedIfPreferenceEnabled` 把 editing/culling
   存进 EmbeddedState box（McpServerController :723-726），preference
   toggle on-leg 的 `startEmbeddedServer` 从 box 读出再传
   `startHTTPHost`（:740-750）——searchState 必须同路存取（加一个
   box 字段），否则 GUI 用户先关后开 MCP 时三工具静默缺席。同文件
   内改，不增 files_modified，但 grep 机检点位应含 startEmbeddedServer。
2. T1 action 5「probe/writeCallCount = 既有面透传」对 headless 是
   **空集**：`embeddedWriteCallCount()` 只读 embedded box 的 handle
   （:585-588），stdio host 与只读 face 无 handle 外露面——headless
   的 writeCallCount 没有「既有面」可透。诚实值 = null（server 字段
   缺席语义），但 plan 措辞暗示有面可透。

**修法**：①T1 action 3/4 补一句「searchState 随 EmbeddedState 存取
（startEmbeddedServer on-leg 同路透传）」；②T1 action 5 措辞改为
「probe = 既有面透传；writeCallCount = GUI embedded 走
embeddedWriteCallCount() 同源，headless = null 诚实面」（或显式立项
新 plumbing——不推荐，无消费者）。

### F-5【minor｜T3】get_history `limit` 语义二义——「默认全量、最大 500」在 >500 栈上自相矛盾

- plan T3 action 1 与 CONTEXT D-M7-2-4 均写「`limit`（items 帽，默认
  全量、最大 500）」。HistoryStack 无 cap（D-H2 :36-38「no cap」），
  >500 的栈上「默认全量」与「最大 500」不能同真；截断保留端（最新
  position 侧还是最老侧）未钉。position/itemCount 可检出截断，但
  保留方向影响 agent 自查序列的正确性。
- **修法**：一句话钉死——推荐「默认 = min(全量, 500)；截断保留
  最新端（position 侧，有效历史优先）；itemCount 恒真值总数」；
  或「默认真全量（无帽），显式 limit ≤ 500 才截」——二选一
  DECISIONS，T5 golden 补一例 >帽 截断方向断言。

### F-6【minor｜T5 可测形】MainActor hop「结构断言」无机器判据形

- plan T5 action 3「MainActor hop 结构断言（handler 零直接 @Observable
  观测——seam 闭包承载）」：现文无可执行判定（「结构断言」不是测试
  语言）。风险面真实（@Observable 态跨 actor 读 = 热态读崩，plan
  风险节自列），但钉法缺席。
- **修法**：钉两条可机检判据——①fixture `liveState` 闭包体内
  `dispatchPrecondition(condition: .onQueue(.main))`（或 MainActor
  检查 + 调用计数），get_state 调用断言「闭包被调且在主线程」=
  hop 结构在位；②grep 机检：SearchStateToolset.swift 源对
  WorkspaceModel/PipeCoordinator/ExportState/LibraryProjectController
  类型名零直接引用（handler 只摸 context closure）。SC 同步补谓词。

---

## 二、注记（不要求修订，执行批知悉）

### N-1 基线与开关亲核 ✓

- HEAD = `55dc2552`（plan docs commit）⊃ `d08306fd`（research docs），
  两跳 docs-only；`git status` 无产线漂移；基线 `3860/35/0` 记账成立。
  plan 自述 HEAD `d08306fd` 属撰写时点，不构成问题。
- `.work/config.toml [gsd]`：auto = true / paused = false 亲核 ✓，
  与 plan read_first 相符；夜间全自动授权 + `--all` 批准制标注在案。

### N-2 EXIF 臂 fresh-group 语义（与 GUI 的层叠差）

GUI `submitExif` 把 parse plan 折进**当前 grid filter group**
（LibrarySearchModel :160 `ExifSearchFilter(group: grid.filter.group,
plan: plan)`）；MCP 无状态面从空组起步（无「当前过滤态」可层叠）。
golden 双腿同构所以恒等成立；建议 search_photos description 注明
「each call evaluates the query against the full library (no layered
session filter state)」——无状态语义诚实，防 agent 误推层叠行为。

### N-3 默认 sort 未钉

T2 schema 的 `sort` 无默认值裁决；GUI 默认 = `FilterSort(key: .filename,
ascending: true)`（LibraryGridModel :97）。建议 schema 显式钉
`default {key: "filename", ascending: true}`（GUI 同源 + 快照可断言）。

### N-4 cursor/sort 与 mode 的组合校验

「cursor / sort 为 EXIF 臂 only」的越臂组合（如 mode=clip 带 cursor）
应 typed 拒并入 T5 负测；PhotoProjection.Cursor 先例已把 sort 键+方向
嵌入 token（换排序键游标失效负测 :203-205 注记）——EXIF token 同形
即可白拿该负测。

### N-5 kind 判别先序对 OVERWRITE-paste 双载荷项正确

HistoryItem 的 OVERWRITE paste = `pasteSet != nil` **且**
`stackSnapshot != nil` 并存（HistoryStack.swift :89-95 doc 正本）；
plan 五臂先序（pasteSet 最前）把该类归 `paste` ✓。建议 T5 golden
fixture 五种 item 外加一例双载荷项，把先序钉成显式断言。

### N-6 narrow projection / metadata 取数源 / versions meta 亲核 ✓

- 窄投影九字段与 `LibraryImageRow` 28 列一一在位（LibraryQueries.swift
  :95-125：id/imagePath/filename/dir/captureDate/rating/flag/colorLabel/
  hasEdits 全有列支撑）——「无列支撑字段如实缺席」条款大概率零行使。
- get_history 的 note/keywords/rating/flag/colorLabel 全在 sidecar
  document（LightamerSidecar.swift :293-309 META face，hash-isolated）
  ——与 Phase 12 metadata 面同源同真相 ✓；`readDocument` 为 editing
  面在用读缝（EditingToolset.swift :240/:572 两处先例）✓。
- versions meta：SidecarVersionRecord = {id, name, createdAt, updatedAt,
  chain?}，`chain == nil` = active（LightamerSidecar.swift :919-946）
  ——meta-only 投影零 chain 字段泄漏可由 schema 快照钉 ✓。
- imagePath 为 path-kind 相对形——agent 寻址走 imageID（get_history
  digits 臂）即可，description 可注明 imagePath 的相对语义。

### N-7 写断路器与 openReadOnly 交互亲核 ✓（T4 的「原样足以拦写」成立）

- `openReadOnly` 零 flock 获取、schema `stored == current` 守卫、
  `readOnlyMode = true`（ProjectFileStore.swift :199-229）；
  `withWriteBatch` 是库域写腿唯一出口且 readOnlyMode typed 拒
  （:454-477，注释自证「the SINGLE point every library write exits
  through」）——抽核 LibraryStore 全部 INSERT/UPDATE/DELETE 调用点
  （:147/:249/:270/:325/:338/:347/:382/:411/:421/:440）全部在
  withWriteBatch batch 内，ImportService 的 withHandle 为纯读面 ✓。
- heldByOther 臂同实例复用安全：`open(role:)` 在锁失败点抛出时
  SQLiteHandle **尚未打开**（:163 `acquireProjectLockIfRoled` 先于
  :164 handle open），store 干净 → T4 的 `store.openReadOnly()` 同实例
  调用无双开 ✓。
- 只读 store 的 `close()` 会跑 `checkpointTruncate`（:303-312）——writer
  持 WAL 时 typed 失败（busy/log ≠ 0）、stdio EOF 腿 `try?` 吞掉 +
  进程退出兜底；writer 空闲且 WAL 已全 checkpoint 时 truncate 是
  SQLite 语义内的安全操作。既有 GUI openProjectReadOnly 路径同语义，
  非本波新增面——执行批知悉即可。

### N-8 宿主装配点完整清单（供 grep 机检对账）

物理调用点 6 处 / 缝函数 4 个 + 内部缝 1 处（F-4①）：
LightamerApp :1374（startEmbeddedIfPreferenceEnabled）；
runHeadless :196（stdio 无 --project）与 :203（http 无 --project）；
runHeadlessArbitrated :292（stdio --project 臂）/:303（writer http 臂）/
:322（只读 http face）；startEmbeddedServer :746（内部，经
EmbeddedState）。plan T1 action 5 的「两臂 + 无 --project 路径」措辞
已覆盖 6 处 ✓；SC 的「三处宿主装配点」计数措辞建议改「六调用点
/ 四缝 + EmbeddedState」对账形。McpHostTests/McpProjectArbitrationTests
的 spawn 形骑产线路径，无额外宿主。

---

## 三、放行面复核结论（逐维度对简报七问）

1. **T1 装配面**：第三参缺省 nil 机制成立（makeRegistry :456-468 两参
   现形 + descriptors() 名序 :316-320 + requiresWriter 缺省 false
   :300-307 全亲核）；「缺第三参 = 20 descriptor 零 diff 负测」可落地
   （负测直调 makeRegistry(editing:culling:) 对 frozen 20 表）；宿主
   清单无第六处遗漏（N-8），但 EmbeddedState 第五缝（F-4①）与
   writeCallCount 空集（F-4②）须补钉；**E-1 provider 形须修**。
2. **T2 三路由**：cursor 传递形态有先例形（PhotoProjection.Cursor
   base64+sortedKeys JSON、garbage = typed invalidParams、换键失效负测
   白拿，:198-270 亲核）；CLIP mock 与真路径在 `SemanticSearching`
   协议缝结构等价 ✓（LibrarySearchModel 测试先例同缝）；modelUnavailable
   双映射对既有 15 值零扰（additive 两 switch 补臂形与 :79-110 结构
   吻合，穷举测试 T5 钉）✓；**E-2 null 尾段须修** + F-3 worker 族
   映射须补。
3. **T3 读面**：note/keywords/rating 取数源与 Phase 12 同源 ✓（N-6）；
   includeParams payload 面的 limit 语义须钉（F-5）；get_state 六字段
   无头臂语义自洽（liveState=nil → nulls；D-M7-2-8 与状态源表逐字段
   亲核：WorkspaceModel.LibraryFace :43/:47/:75、
   SessionCoordinator.currentSession :400-404、McpProjectLockVerdict
   :120-136、ExportJobState 六案 :33-50——「四态计数」措辞与六案
   枚举有出入，执行批按分组计数如实实现即可，知悉）。
4. **T4 openReadOnly**：锁免语义亲核成立（N-7 三条）——两进程并发
   GUI(writer)+headless(readOnly) 在 SQLite WAL 多读者语义内安全；
   断路器覆盖面抽核通过；connect-guidance 双通道零 diff 面真实存在
   （序列 A/B 断言点 :206-207/:284 均不触 openReadOnly 插入点——
   插入在 emitConnectGuidance **之后**，stdout 首行断言不受扰）；
   失败降级禁 exit 在码面可钉。「照常服务」SC 可测形须修（F-2）。
5. **T5 测试面**：union 四处计数坐标准确但显式改清单缺 4 处（F-1）；
   parity golden 三臂可测形成立——唯 EXIF 臂 golden 有同源同缺失明
   （E-2 修法甲内补 NULL-key fixture 行）；锁只读豁免面测试形态可落地
   （writerCheck{false} + writeCallCount 零增量 + probe 调用计数，
   registry :333-341 结构保证亲核）；MainActor hop 断言须补机检形
   （F-6）。
6. **SC/ΔN/红线**：+12..20 带 vs T5 分解上界 21——越带申报条款兜底
   （N 级知悉）；SC 全可观测扫描命中两处失明（E-2 golden、F-2 端口
   通道）+ 一处无判据形（F-6），其余 SC（grep 机检/byte-equal/计数
   断言/对账行/红线逐条机检）均可机检 ✓；MCP 快照串行红线三处落位
   （red_lines ② + 风险 4 + T6 GOAL-STATE 注记）✓；zh-audit 三键
   scanner 可见（静态键，现 xcstrings 已有 16 个 mcp_tool_desc 键亲数，
   尾块纯插入形成立）✓。
7. **独立猎残**：F-1..F-6 + N-3/N-4/N-5 为简报维度外产出；未发现
   结构性驳回项（T1-T6 任务序 / 九裁决与 RESEARCH §6 一致性 / 封存面
   17 件与 diff 面零交集 / GPL 对表纪律 / files_modified 清单基本准确
   ——唯 E-1 修法若走甲方案不改清单，走 LibraryStore accessor 方案
   则必须补申报）。

## 总评

**须修后放行（2 error + 6 minor + 8 注记）**。本 plan 的突出强项：
只读三面结构性不触的论证扎实（registry 分支结构 + writeCallCount
计数点 + probe 消费面三点亲证）；快照同批三验收形态与 ROADMAP 逐项
对得上；openReadOnly 的零写险论证经代码抽核全部成立；红线族与
L041/L013/M2-4-0-E2 登记纪律随行完整。两个 error 都是「照现文执行
必然产出缺口而验收门放行」级：E-1 供给形（V2M E-2 同族，执行批将
被迫无授权偏离 D-M7-2-9 生效值或加未申报 Core 面）、E-2 语义缺口
（F1 升格，NULL 尾段整段静默不可达且 golden 失明）。修订量级 =
plan/CONTEXT 文本级 + 测试点位清单级，不动任务序、波次、裁决权
归属与 files_modified 骨架。修订完成后可派发。

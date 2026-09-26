# Phase 16: Catalogs Mode - Context

**Gathered:** 2026-09-26
**Status:** Draft for planning — 9 项 OQ 全按推荐自动裁决〔晨审追认〕（D-16-CONTEXT-1..9，追认清单表见 decisions 末）；研究问题清单另见 `16-RESEARCH-QUESTIONS.md`（含 2026-09-26 本机探针事实）

<domain>
## Phase Boundary

本 Phase 在既有 Sessions 模式（恒默认）之外交付可选的 Catalogs 模式（6 项需求 CATALOG-01..06）。核心架构事实：

1. **推翻语义是精确的「升格」不是「翻转」**——2026-08-03「不做中央库」整族排除被推翻（ROADMAP §Phase 16 Notes 修订留痕），但修订语义 = 中央库从「禁止」变为「**可选第二模式、默认关闭**」；Session 哲学与 **sidecar 恒真身原则零改动**（PROJECT.md:65 约束修订版黑体原文）。目录库 = `SessionIndexStore` 的 `.cosessiondb`-ROLE 同构从会话域放大到跨会话域：每行可重建、删库无损、mutable and untrusted（`LightamerCore/Sources/Session/SessionIndexStore.swift:8-12` 的纪律原文跨域延续）。**两级派生链 = sidecar（真身）→ session.lindex（会话缓存）→ catalog（跨会话聚合视图）**——catalog 投影的忠实对象是 lindex，lindex 重建后 catalog 靠 sweep 追平，真身永远是 sidecar。
2. **复用底座三件已就位，零返工**（GOAL-STATE 2026-09-27 架构指令判定）——①`SessionIndexStore`：34 列 v2 schema（`SessionIndexSchema.swift:49` `schemaVersion=2`）+ FilterSQL 消费面（`SessionIndexStore.swift:561-583` `query(groups:sort:limit:)`）+ 单事务 diff 纪律 + `scan_epoch` 水位机制——catalog 投影引擎是它的跨会话孪生，不是重写；②`FilterSQL` 单一翻译层（`FilterSQL.swift:110` `translate` / `:380` `translateConjoining`）——CATALOG-04「复用 12-2 谓词层，求值域扩全库」的字面落点，**catalog 域不得出现第二 SQL 翻译面**；③`SmartAlbumStore` app 级 JSON 先例（`SmartAlbumStore.swift:80-85`）——规则资产位置与生命周期不变，变的只是求值时连接的库。
3. **12-CONTEXT:20 的「跨会话智能相册 defer」由本 Phase 正式兑现**——当时 defer 理由「跨会话聚合需多 session.lindex 联合查询，新架构面」（D-12-CONTEXT-4）在中央库落地后消解：求值域从单 lindex 换成 catalog 单库，谓词模型与 SQL 形状零改（D-16-CONTEXT-6）。这不是返工——12-2 的 session 面交付在双模式下均为复用底座。
4. **身份的两层语义是本 Phase 最容易做错的地方**——session 面的 `path` = rel-to-session-root（随文件夹移动，`SessionIndexStore.swift:29-31`）、`thumb_path` = 绝对路径；跨会话后两者都失去定位力。catalog 行身份 = **`（session_id, rel_path）`复合**，session 本身需要稳定 id（root 路径会变，不能当身份）；图片文件本体零搬移（reference 模式），catalog 只做组织视图——编辑管线、解码管线、缩略图管线全部仍在会话域（D-16-CONTEXT-7）。
5. **SC#3 基准门是 v1 SQLite 终裁的最终实证裁决，不是性能调优任务**——2026-09-26 本机探针（`:memory:`、1M 行）：朴素 OFFSET 分页 59-157ms **超 50ms 门**、LIKE 四条款全扫 83ms（物化表必要性的直接佐证）、树递归 CTE 0.05ms。即：SC#3 不是走过场，分页索引设计/keyset pagination/标签物化表形状是 research 的真问题（RQ-16-6/7，见 `16-RESEARCH-QUESTIONS.md` 探针事实节）；若基准终测不过，出路 = 回到 ROADMAP §Phase 16 Notes 的 v2 评估项重启裁决（pg），不是硬调到过。
6. **文档账漂移两处，orchestrator 收口同批修正**（本 Phase discuss 环识别，非本环义务）——①`PROJECT.md:65` 约束仍写「PostgreSQL 后端」，与 2026-09-27 用户终裁「v1 = 本地 SQLite」（REQUIREMENTS CATALOG-02 / ROADMAP §Phase 16）不一致；②ROADMAP Phase Overview/Per-phase counts（134）与 REQUIREMENTS Traceability 表均未登记 CATALOG-01..06 与 Phase 15/16 行。

**Phase 16 不做**：

- **v2 远程后端（pg 实例 / SQLite 镜像）**——CATALOG-06 预留；FilterSQL 方言适配是届时工作量（ROADMAP Notes 已钉）；v1 只保证三道受控缝（D-16-CONTEXT-8），不预写任何 pg 代码
- **文件搬移入 catalog / 内容哈希去重 / 跨会话同内容文件合并**——reference 模式（D-16-CONTEXT-7）；LR「导入拷贝」形态不在对标面
- **目录库作为任何写面的真身**——编辑/元数据写面零改动（sidecar 照旧，`MetadataService` 路径不动）；catalog 行更新 = 投影产物
- **MCP 筛选工具的 catalog 求值**——MCP-05/06 求值域 = 当前会话（Phase 14 面）；Phase 14 研究项 A（同会话并发双写）与本 Phase 互不依赖，catalog 联动 defer
- **全局搜索（WORK-02）/ 地图 / 打印**——v2 面，本 Phase 的 catalog 镜像恰好是其未来索引源，但不进 v1 范围
- **多 catalog / catalog 内文件夹式嵌套集合**——v1 单 catalog（`.lcat` 单文件）；多 catalog 管理是 v2 议题
</domain>

<decisions>
## Implementation Decisions

> 9 项 = discuss 起草识别的 OQ，全部按推荐项自动裁决〔晨审追认〕。晨间任一推翻 → 回注 planner 重开受影响面（推翻代价见追认清单表）。

### D-16-CONTEXT-1: Catalogs 库 = app 级单文件 SQLite `Catalog/catalog.lcat`（位置设置可改）+ 四表骨架；镜像行 = (session_id, rel_path) 复合主键 + 34 列语境化镜像
- **裁决**：①库文件 = **单文件** SQLite，默认 `~/Library/Application Support/Lightamer/Catalog/catalog.lcat`（自有扩展名 `.lcat`；one-way 格式锁 + `schemaVersion=1` + v99 拒开，`SessionIndexSchema.swift:49/:192-197` 同款），设置中可改位置（C1 catalog 文件位置惯例）；②表骨架四张：`catalog_images`（34 列语境化镜像，下述）+ `catalog_sessions`（登记表：`session_id` TEXT PK / `root_path` / `display_name` / `last_projected_epoch` / `last_seen`）+ `categories`（树，D-16-CONTEXT-4）+ `collections`（平集合）+ 关联表 `image_categories`/`image_collections`/`image_tags`（D-16-CONTEXT-3）；③镜像行主键 = `（session_id, rel_path）`复合（session 内 rel_path 唯一性由 session.lindex 的 `path TEXT PRIMARY KEY`（`SessionIndexSchema.swift:67`/`SessionIndexStore.swift:360`）保证，跨会话后自然全局唯一）；④34 列语境化 = 列名集与 v2 逐列对齐（`SessionIndexSchema.swift:66-102`），仅 `path` → `rel_path` 改名 + 增 `session_id` 列；**`thumb_path`/`thumb_state` 不镜像**——缩略图文件留在会话域（零复制膨胀），Catalogs 模式网格经 `（session_id, rel_path）` 路由到会话侧缩略图缓存取图（RQ-16-9）；另增 `catalog_images.id INTEGER PRIMARY KEY`（稳定内部键——**不用 rowid**，VACUUM/删除后 rowid 可重排，`image_tags`/`image_categories` 引用它而不是 rowid，RQ-16-7 分叉）。
- **理由**：单文件 = 脱库降级/备份/迁移的最小面（CATALOG-05 = 删一个文件）；镜像列集对齐 v2 = 投影是逐列拷贝零变换（parity 测试机械）+ FilterSQL 字段白名单（`FilterSQL.swift:348-367`）在 catalog 域零翻译损耗；复合主键继承 session 面已验证的唯一性语义，不发明第二身份；稳定 `id` 列是探针之外的主动防坑（rowid 重排会让标签表引用静默错行）。
- **Reversibility**: 加列 additive（migrate 表驱动先例 `SessionIndexSchema.swift:234-262`）；缩略镜像列日后可补（ALTER 尾追加）；`.lcat` 文件位置常量一处。

### D-16-CONTEXT-2: 投影引擎 = lindex→catalog 单向水位投影（打开会话增量 + Catalogs 模式启动全库 sweep 后台）；Sessions 模式运行零 catalog 触碰；编辑写面零改动
- **裁决**：①**投影源 = session.lindex**（两级派生链，Boundary 事实 1）；②触发面三条：a. **打开会话时增量投影**——`openSession` 五步编排完成后，catalog 侧 `SELECT … WHERE scan_epoch > catalog_sessions.last_projected_epoch` 取 diff 行 UPSERT/DELETE 进 catalog（`scan_epoch` 水位机制复用 `SessionIndexStore.swift:290/:431-437` 既有列），单事务，然后推进 `last_projected_epoch`；b. **进入 Catalogs 模式 / catalog 打开时后台全库 sweep**——遍历 `catalog_sessions` 对每会话跑同款水位投影 + 罗列未登记会话入册（首次登记 = 打开过的会话才入 catalog），后台 Task 不阻塞 UI；c. **全量重建** = 清空 `catalog_images` + 各会话水位归零重投影（显式动作 + 进度 UI）；③**Sessions 模式运行时零 catalog 文件句柄**（CATALOG-01 零外部依赖的字面执行——Sessions 模式连「顺手更新 catalog」都不做，落后无害，下次投影追平）；④编辑写面零改动——`MetadataService`/批量管线（`SessionIndexStore.swift:1164-1198` claim 面）不感知 catalog；Catalogs 模式下编辑产生的 lindex 行变更由「返回网格时增量投影」追平（写后 write-through 不做——避免把投影逻辑塞进热写路径）。
- **理由**：pull-on-open 是 session 面已验证的哲学（「re-derive state on access」，09-CONTEXT）；水位投影 = 每 session 一次 diff SELECT + 单事务 UPSERT，10 万级重建时长 = 各 lindex 已回填列的纯 DB 拷贝（零 EXIF 重解码、零 sidecar 重读——回填发生在 lindex 侧），预算实测进 research（RQ-16-5，plan 目标：10 万行全量投影 ≤30s 级、单会话增量秒级）；「落后无害、追平即可」是可重建派生层的自由度红利，write-through 反而把 catalog 变成写路径的一致性负担。
- **Reversibility**: write-through 可后补为优化（接口位 = 投影函数本就是纯函数）；全量重建/增量共用同一投影核心，触发面可增删。

### D-16-CONTEXT-3: 标签物化表 = `image_tags(id, tag)` 拆行 + 投影时祖先展开（打子隐含父物化为行）；查询 = 等值可索引；keywords 谓词按求值域选 SQL 形状（第一处受控方言点）
- **裁决**：①投影时把 lindex 的 `keywords` 物化串（`|`-join，`SessionIndexStore.swift:826-828`）拆行入 `image_tags(catalog_image_id, tag)`：每条完整路径一行 **+ 全部祖先路径展开行**（`"Nature|Flower|Rose"` → 3 行：`Nature` / `Nature|Flower` / `Nature|Flower|Rose`）——12-2 的「打子隐含父」语义从查询期展开（LIKE 四条款，`FilterSQL.swift:220-229`）变为**存储期物化**，查询 = `EXISTS (SELECT 1 FROM image_tags WHERE catalog_image_id = ? AND tag = ?)` 等值 + 复合索引 `(tag, catalog_image_id)`（百万级行数下的层级关键字查询面 = SC#2 黑体的落点）；②catalog 域的 keywords 谓词翻译 = FilterSQL 按求值域选形状：session 域照旧四条款 LIKE（列上直翻），catalog 域 = EXISTS 子查询——**谓词模型零改、SQL 生成器加形状分派**（不是第二翻译函数，RQ-16-11 定实现形态）；③直打 vs 祖先继承是否在表内区分（`is_direct` 列）= research 定（RQ-16-7，UI 无需求则不加）。
- **理由**：探针实测 LIKE 四条款全扫 1M 行 = 83ms（无索引，超 50ms 门）——SC#2 把物化表写进黑体正是因为 LIKE 形状在百万级不可索引；等值 + 覆盖索引是 SQLite 的甜点区；语义搬家（查询期→存储期）在投影侧一次性完成，真身仍是 sidecar `keywords` 数组，物化表随投影重建。
- **Reversibility**: 展开行可重导（删表重投影）；`is_direct` additive；session 域 LIKE 形状零改动（12-2 契约不回流）。

### D-16-CONTEXT-4: catalogs 组织树 = `categories` 邻接表（parent_id + sort_order）+ `image_categories` 多对多；树查询 = WITH RECURSIVE；拖拽重排 = 单事务；C1 Categories 语义
- **裁决**：①`categories(id INTEGER PRIMARY KEY, parent_id NULLABLE, name, sort_order, created_at)` 邻接表（单父树——C1 Categories 语义；`parent_id NULL` = 根）；②`image_categories(category_id, catalog_image_id)` 多对多——**图片多归属**（一图可属多分类，C1/LR Collections 同惯例），无上限；③树读取 = `WITH RECURSIVE` 子树展开（探针 0.05ms@3 层，邻接表在 v1 树规模下零压力；物化路径/嵌套集不做——RQ-16-8）；④树编辑（CRUD/拖拽重排/图片归类含批量）全部单事务（one bulk change = one transaction 纪律延续），拖拽 = 受影响兄弟集 `sort_order` 重排；⑤手动虚拟集合 `collections` 平表 + `image_collections` 多对多与树正交并存（SC#2 的「虚拟集合」），批量归类复用 Phase 12 批量面语义（CATALOG-03 黑体）。
- **理由**：邻接表 + 递归 CTE 是 SQLite 官方推荐树形（3.8.3+ 原生支持，系统 3.54.0 探针过）；多对多是 C1 Categories/Albums 的字面语义（一张图同时在「2026 旅行」分类和「精选」集合）；单父树 vs DAG 的分叉在 C1 语义下不存在。
- **Reversibility**: 列 additive；多父（DAG）= 加关联表可扩；递归深度上限执行期定（SQLite 默认无限制，UI 防呆即可）。

### D-16-CONTEXT-5: UI 入口 = 设置开关 + catalog 位置；模式切换 = 侧栏 segmented（Sessions | Catalogs）持久化；Catalogs 侧栏 = All Photographs + Categories 树 + Collections + Smart Albums；会话管理动作双模式共享
- **裁决**：①设置面 = 「启用 Catalogs 模式」开关 + catalog 文件位置选择器（CATALOG-01「设置中启用」字面）；**未启用 = 模式切换器不出现**（Sessions 恒默认零感知——CATALOG-01「零外部依赖」的 UI 半边）；②启用后侧栏顶部 segmented 切换器（持久化记住上次模式；**每次冷启动默认 Sessions**——「恒默认」语义优先于「记住」）；③Catalogs 模式侧栏四段：All Photographs（全库网格）/ Categories（树）/ Collections（集合列表）/ Smart Albums（既有 app 级规则，求值域=全库）；④`catalog_sessions` 在侧栏以会话分组呈现，点入 = 过滤到该会话域（C1 Library 面板 Sessions 节同款）——Catalogs 下 Sessions 可见但从属；⑤新建/打开会话动作双模式共享（Catalogs 模式添加会话 = 走同一 `openSession` 流程 + 首次投影入册）；⑥跨会话网格/过滤/排序复用 12-2 的 filter bar chips + Quick Filter + 排序菜单全套 UI（D-12-CONTEXT-7 面），只换数据源。
- **理由**：C1 的双入口（Sessions/Catalogs 切换）是对标正本；「冷启动恒 Sessions」把默认模式做成了不可漂移的常量而非状态；过滤 UI 复用 = L025 zh/en 负担最小 + 「一套代码两个消费面」纪律（12-CONTEXT:67 同款）第三实例。
- **Reversibility**: 切换器形态/位置 plan 期 UI 走查定；Catalogs 模式内布局 additive。

### D-16-CONTEXT-6: SmartAlbums 联动 = 规则资产零改动；求值域随模式（Sessions=当前会话 / Catalogs=全库）；`scope` 字段留 additive 不进 v1
- **裁决**：①`SmartAlbumDocument`（`SmartAlbumStore.swift:26-39`）schemaVersion 1 零改动——规则是 app 级资产（规则随应用走），求值域是运行时事实（结果随打开的库）——两个自由度解耦的原则（D-12-CONTEXT-4）直接推广到第二模式：**域 = 当前模式的连接库**；②Catalogs 模式下智能相册对 `catalog_images` 求值（同一谓词模型 + D-16-CONTEXT-3 的形状分派）；③`scope` 字段（「此规则只在某域求值」）留 additive 预留位不进 v1——v1 无「跨 catalog 多库」场景，域随模式已是完整语义。
- **理由**：D-12-CONTEXT-4 Reversibility 预留的「加 scope 字段即可扩跨会话」在本 Phase 以更简形态兑现（域随模式，字段都不用加）；规则零改 = 12-2 存量用户数据零迁移。
- **Reversibility**: scope 字段随时 additive；域判定逻辑是一处 if。

### D-16-CONTEXT-7: 文件本体 = reference 模式零搬移；session root 失效 = 离线标记 + 手动 re-link；跨会话同内容不合并
- **裁决**：①**Catalogs 模式零文件操作**——图片文件/缩略图/sidecar 全部留在会话目录（对比 LR「导入拷贝入 catalog」形态，明确不采纳）；Catalogs 模式打开图片 = catalog 行解析 `（session_id, rel_path）` → `catalog_sessions.root_path` 拼绝对路径 → 既有解码/编辑管线零改动；②会话文件夹被移动/删除/断卷 = `catalog_sessions.root_path` stat 失败 → 该会话行集标**离线**（网格灰显/禁打开，分类树/集合中的成员行保留——组织数据是 catalog 自己的资产不随文件走）；恢复 = 手动 re-link（重选新路径，登记表更新 root_path）——不做自动路径搜索；③跨会话出现同内容文件（拷贝进两个会话）= 两行独立，**不做内容哈希去重**；④会话从磁盘删除 = 用户显式动作「从 catalog 移除会话」清行（分类归属随行删除），无孤儿自动清理。
- **理由**：reference 模式 = Session 哲学（文件夹即会话、sidecar 随原片）在双模式下的必然推论，也是 C1 自身的 Sessions+Catalogs 混用形态；离线标记 + re-link 是 C1 同款 UX 且实现面最小（stat 一次）；去重需要全库哈希 = 万级以上不可行且无需求方。
- **Reversibility**: re-link 后自动搜索可后补；离线行集的处置策略（保留/清理）可调。

### D-16-CONTEXT-8: pg v2 预留 = 不做后端 trait 全家桶；三道受控缝（SQL 生成收口 FilterSQL 单面 / DDL 集中 `CatalogIndexSchema` / 访问走 SQLiteHandle 级薄封装）
- **裁决**：①**反推荐 repository protocol**——v2 是否换 pg 未决（CATALOG-06 预留评估，非承诺），提前抽象 = YAGNI + 违反「不臆造」纪律；②预留三道缝，全部是**纪律不是代码**：a. 一切 SQL 生成收口 FilterSQL 单面（CATALOG-02 黑体已钉；ROADMAP Notes「FilterSQL 方言适配为该轮工作量」= v2 的适配点**已被钉死在这一个文件**，方言缝=该文件本身）；b. 全部 schema DDL 集中 `CatalogIndexSchema` enum（`SessionIndexSchema` 同款模式——列冻结表 + apply/migrate + v99 拒开）；c. DB 访问走既有 `SQLiteHandle` 薄封装不散落裸 C API（v2 换驱动 = 换 handle 层一处）；③**不预写**任何方言分支/pg 类型映射——v2 真要换时，翻译层形状分派（D-16-CONTEXT-3②）是天然扩展点。
- **理由**：探针 + 引擎归因调研（ROADMAP §Phase 16 Notes：LR/C1 是「SQLite 被用出问题」非「SQLite 到顶」）支持 SQLite 在 1M-100M 行域非瓶颈；三道缝已使 v2 适配 = 单文件方言化 + handle 替换，无架构级重写；trait 全家桶的成本（每查询两跳 + 假抽象泄漏）是即期纯付。
- **Reversibility**: 三道缝都是收敛纪律，v2 若仍 SQLite 则零浪费；真换 pg 时 FilterSQL 内方言分派是加法不是重写。

### D-16-CONTEXT-9: 波次分解建议 = 4 plans / 3 waves（16-1 依赖根先行；16-2∥16-3 可选并行经 planner 裁决；16-4 基准终测+签核收口）
- **裁决**（给 planner 的依赖序基线）：**16-1**（catalog 底座：`CatalogIndexSchema` 四表 DDL + 投影引擎（水位增量 + 全量重建）+ 标签物化投影 + sessions 登记 + **1M 行基准 harness 与 fixture 生成器**——SC#3 的 harness 早建早好，属底座不算收口）→ **16-2**（双模式 UI：设置开关 + 切换器 + Catalogs 侧栏四段 + 跨会话网格/过滤/排序（FilterSQL 接 catalog 源）+ 智能相册全库求值 + 缩略图跨会话路由）∥ **16-3**（组织树与归类：categories CRUD/拖拽 + collections CRUD + 图片归类批量 + 树侧栏接线；Core 服务层可与 16-2 并行，UI 接线依赖 16-2 的模式载体——planner 裁决并行度）→ **16-4**（收口：SC#3 基准终测 p95<50ms 实测裁决 + 脱库重建专项 + 双模式隔离断言 + 签核）。
- **理由**：16-1 是全 Phase 依赖根（schema/投影/身份）；基准 harness 挂 16-1 = 索引设计问题（RQ-16-6）在 UI 面之前暴露，收口轮无惊喜；16-2/16-3 的 Core 面天然正交（浏览过滤 vs 树编辑），UI 载体耦合点集中；16-4 是实证裁决位 + SC#1 脱库半边的专项验收。
- **Reversibility**: plan 边界可并/拆；刚性 = 16-1 先行、16-4 收口含签核。

### 继承定案（非 OQ，上游已论证、下游不得重开）

- **真身恒 sidecar / 目录库恒可重建**（SESS-07 黑体 + CATALOG-02 黑体 + Boundary 事实 1）——两级派生链 sidecar → lindex → catalog 单向；catalog 永不做任何字段的权威。
- **单一 SQL 翻译面**（FilterSQL，CATALOG-02 黑体）——catalog 域禁止第二翻译函数；形状分派收在 FilterSQL 内部（D-16-CONTEXT-3②）。
- **批量/事务纪律**——one bulk change = one transaction（`SessionIndexStore.swift:279` 注释原文）；批量归类走 Phase 12 批量面语义；万张级操作零像素渲染（PERF-07 语义跨域延续）。
- **L013 哈希纪律 / one-way 格式锁**——`.lcat` schemaVersion 1 + v99 拒开 + sortedKeys 语义（DDL 侧 `params_hash` 等 decimal TEXT 照抄）；一切跨进程身份禁 Swift `Hasher`。
- **零新 SPM 依赖**——libsqlite3 是 Phase 9 既有系统库；全项目首个 SPM 新增仍只有 Swift-WebP。
- **SQLite pragmas 基线**——WAL + synchronous=NORMAL（`SessionIndexSchema.swift:174-178` 同款；D-09-CONTEXT-1 的 dirty-marker 论证在 catalog 域同构成立）；基准期 PRAGMA 调优（cache_size/mmap）是 research 计量项不是随手旋钮（RQ-16-13）。
- **失败语义**——投影/树编辑失败 ROLLBACK + typed error；catalog 打不开（schema 不识别）= Catalogs 模式降级禁用 + 引导重建，**永不**波及 Sessions 模式。
- **执行纪律**——`.work/config.toml [gsd]`（auto/paused）每任务边界检查；C 档门控三点停（research 定稿后停 / 每 plan 闭环停 / 签核前停）。

### 验证红线（全 plan 写死，执行期不得放宽）

- **投影 parity 专项**：catalog 行 vs 源 lindex 行逐列断言（34 列语境化后 + session_id）；水位增量投影与全量重建两路产物逐字节一致；`scan_epoch` 水位推进不丢行（对账 added/removed/changed 计数）。
- **脱库重建专项**：删 `.lcat` → 全量重建 → 行集 parity（CATALOG-05 门）；重建期间 Sessions 模式零影响；**双模式隔离断言**：Sessions 模式全流程零 catalog 文件句柄（句柄审计/lsof 断言或注入探针）。
- **树编辑事务性**：拖拽重排中断 ROLLBACK；CRUD 幂等；孤儿 category（parent 失效）不可达构造。
- **标签物化 golden**：祖先展开正确性（`"A|B|C"` → 3 行 golden）；等值查询行集 vs session 域 LIKE 四条款行集**语义一致性**对照（同数据同谓词同结果）；直打/继承区分若加列则双向断言。
- **基准 harness**：fixture 生成器参数化（N 行/查询集/PRAGMA 基线入档）；SC#3 终测 = 真机手动跑（不进 CI——机器差异），报告落账；查询集 = 真实组合矩阵（过滤 chips 组合 × 排序键 × 分页深度），禁「单查询跑分」（L020 同源纪律）。
- **防空转/L014/L010/L025/面板纪律**：同 09/12-CONTEXT 全套；新面板 zh catalog 键同步（L025 smoke 数字随 suite 报）。
- **回归纪律**：每任务全套 suite 绿（现基线 **1437/6skip/0fail**，12-5 收口批后）；每任务边界查 `.work/config.toml [gsd]`。

### Open Questions 晨审追认清单（9 项全按推荐自动裁决）

| OQ | 裁决一句 | 关键理由 | 推翻代价 | Reversibility |
|---|---|---|---|---|
| 1 库 schema | `.lcat` 单文件四表；(session_id, rel_path) 复合 PK + 34 列语境化镜像 + 稳定 id 列；缩略图不镜像 | 脱库=删一文件；投影逐列零变换；rowid 重排防坑 | 复合 PK 改单列身份 = 投影/查询面全改；镜像列集改 = parity 全重写 | 加列 additive；文件位置常量 |
| 2 投影触发 | 打开会话水位增量 + Catalogs 模式后台 sweep + 显式全量重建；Sessions 模式零触碰；无 write-through | pull-on-open 已验证哲学；落后无害；写路径零污染 | write-through 化 = 投影塞进热写路径，一致性负担 | write-through 可后补 |
| 3 标签物化 | 拆行 + 祖先展开物化；查询=等值+复合索引；FilterSQL 形状分派 | LIKE 全扫 83ms@1M 超门（探针）；SC#2 黑体正主 | 查询期展开 = 放弃可索引性，SC#2/SC#3 双违 | 展开行可重导 |
| 4 组织树 | 邻接表 + WITH RECURSIVE + 多对多归属 + 单事务拖拽 | SQLite 官方推荐形；探针 0.05ms；C1 语义 | 物化路径/嵌套集 = 写放大与复杂度白付 | 多父可扩关联表 |
| 5 UI 入口 | 设置开关 + segmented 切换器；冷启动恒 Sessions；侧栏四段；会话动作共享 | C1 对标正本；「恒默认」做成常量非状态 | 启动进 Catalogs = 违 CATALOG-01 恒默认 | 切换器形态可调 |
| 6 SmartAlbums | 规则零改；求值域随模式；scope 留 additive | 域=连接库是 D-12-CONTEXT-4 解耦原则推广 | 规则带域 = 存量数据迁移 | scope 随时可加 |
| 7 文件本体 | reference 零搬移；离线标记 + 手动 re-link；不去重 | Session 哲学必然推论；C1 混用同款 | 拷贝入 catalog = 文件面全重写+存储膨胀 | 自动搜索可后补 |
| 8 pg 预留 | 不做 trait；三道纪律缝（FilterSQL 单面/DDL 集中/handle 薄封装） | YAGNI；v2 适配点已被钉死在单文件 | trait 全家桶 = 即期纯付 + 假抽象泄漏 | 缝是收敛纪律零浪费 |
| 9 波次 | 4 plans / 3 waves；16-1 根含基准 harness；16-2∥16-3 可选；16-4 收口 | harness 早建索引设计早暴露；Core 面正交 | 串行拉长日历；深并行破 UI 载体耦合 | plan 边界可调 |

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.work/gsd/ROADMAP.md` §Phase 16（:282-309——SC#1-5 + Notes：v1 本地 SQLite 终裁 / 标签物化表 / 1M 行基准门 / v2 pg 评估项三边界 + 引擎归因调研存档）；`.work/gsd/REQUIREMENTS.md` CATALOG-01..06（:225-234）
- `.planning/PROJECT.md`:65（约束修订版——⚠️ 仍写「PostgreSQL 后端」，与 09-27 终裁漂移，orchestrator 收口修正）；`.planning/PROJECT.md` 约束节其余条款（sidecar 自有格式 / 依赖最小化）
- `.work/gsd/phases/12-metadata-presets-lut/12-CONTEXT.md`（D-12-CONTEXT-4 智能相册域语义 + :20 跨会话 defer 正本 + :67 一套代码两个消费面 + 追认清单表体例）；`12-RESEARCH.md` §3（LIKE 四条款 / 索引测量方法论——基准 harness 的先例口径）
- `LightamerCore/Sources/Session/SessionIndexStore.swift`（:8-12 真身纪律 / :171-219 openSession 五步编排 / :279-487 单事务 diff / :561-583 FilterSQL query face / :826-828 keywords 物化 / :1177-1198 metadata claim）；`LightamerCore/Sources/Session/SessionIndexSchema.swift`（:49 schemaVersion=2 / :66-102 列冻结表 / :173-220 apply 版本分派 / :234-262 migrate 先例 / :174-178 pragmas）
- `LightamerCore/Sources/Session/FilterSQL.swift`（:110 translate / :179-229 keywords 四条款 + fourClause / :348-367 字段白名单 / :380-394 translateConjoining / :8-22 SQL 红线注释）；`SmartAlbumStore.swift`（:26-39 document / :80-85 app 级目录 / 三拆模式）；`LightamerCore/Sources/Presets/LightamerPreset.swift`（:38 schemaVersion 锚——`.lcat` 格式锁同款）
- `.work/gsd/phases/16-catalogs-mode/16-RESEARCH-QUESTIONS.md`（RQ-16-1..15 + 2026-09-26 本机探针事实——research 首读）
- `AGENTS.md`（Phase 执行模型 + 暂停机制 + Conventions）+ `LESSONS.md` L009/L010/L013/L014/L020/L025/L029/L031
- `.work/GOAL-STATE.md`（:71-76 Phase 16 架构指令 + 预研存档索引；Phase 12 全闭环续接上下文）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **投影源面**：`SessionIndexStore` actor（单事务 diff + `scan_epoch` 水位列 :290/:431-437 + 34 列 `rowSelectColumns` :608-617 单一拼写）——catalog 投影引擎的逐列源与事务纪律范本；`fetchAllRows()`/:534 已有全行读出口（全量重建的直接输入）。
- **查询面**：`FilterSQL.translate/translateConjoining`（谓词模型 `FilterPredicateGroup` Codable 持久化就绪）+ `SessionIndexStore.query(groups:sort:limit:)` :561-583——catalog 查询面的同构孪生模板（换 handle + 换形状分派）。
- **Schema 框架**：`SessionIndexSchema`（列冻结表 + apply 版本分派 + 表驱动幂等 migrate + v99 拒开 + meta KV）——`CatalogIndexSchema` 的逐行模板。
- **app 级资产先例**：`SmartAlbumStore`（一规则一文件 + 启动重扫自愈 + typed 降级 + 同目录 tmp 原子晋升 L009）——catalog 设置资产（启用开关/文件位置偏好）的存储范式；`YiyinFontStore` 三拆模式（L025 面板纪律配套）。
- **批量归类消费面**：Phase 12 批量管线三段语义（段1 内存变换 / 段2 索引单事务 / 段3 sidecar 写队列）——图片批量归类的段2 同构位（catalog 侧无段3——catalog 本身就是终态，归类的真身是 catalog 组织数据，这是与 sidecar 面的关键语义差异：**组织数据（分类/集合成员）的真身 = catalog 自己，可重建的只有元数据镜像**）。
- **UI 载体**：`ContentView.swift:37` BrowserMode 三态 + filter bar chips 全套（12-2）+ 侧栏三段结构——模式切换器与 Catalogs 侧栏的挂点。

### Integration Points

| 底座面（Phase 9/12） | Phase 16 落位 |
|---|---|
| `session.lindex` 34 列 + scan_epoch 水位 | D-16-CONTEXT-1/2：镜像列集 + 水位增量投影源；`openSession` 后投影钩子 |
| FilterSQL 谓词模型 + 翻译层 | D-16-CONTEXT-3/6：形状分派（session LIKE / catalog EXISTS）+ 求值域随模式；字段白名单 16 字段 catalog 域全可用（RQ-16-11 复核） |
| SmartAlbumStore app 级规则 | D-16-CONTEXT-6：零改动；Catalogs 模式求值域 = catalog_images |
| Phase 12 filter bar UI（chips/Quick Filter/排序） | D-16-CONTEXT-5⑥：跨会话网格原样复用，只换数据源 |
| 批量管线三段语义 | D-16-CONTEXT-4⑤：批量归类段2 同构（catalog 单事务）；无段3（组织数据真身= catalog） |
| MCP-05/06 筛选面（Phase 14） | 不动——求值域恒当前会话；catalog 联动 defer（Boundary 不做节） |

</code_context>

<specifics>
## Specific Ideas

- **执行顺序刚性**：16-1（schema+投影+harness）→ 16-2（模式 UI+跨会话浏览）→ 16-3（树+归类，Core 面可与 16-2 并行）→ 16-4（基准终测+脱库专项+签核）。基准 harness 在 16-1 落地 = RQ-16-6/7 的索引设计问题在 UI 之前定形。
- **research 头项三探针**（详见 RQ 文件）：①分页形状终判（keyset vs OFFSET vs 覆盖索引，SC#3 的 50ms 门在朴素形状下探针已证超门）；②标签 EXISTS 形状复测（2026-09-26 探针数字异常，fixture 严谨性待修）；③投影吞吐基线（10 万行水位投影/全量重建实测，定 D-16-CONTEXT-2 的 plan 预算数字）。
- **C 档门控**：research 定稿后停（用户过目 Open Questions 裁决点）→ 每 plan 执行+验收闭环后停 → 签核（VALIDATION）前停。worker 每任务边界查 `.work/config.toml [gsd]`。
- **「组织数据真身 = catalog 自己」要在 plan 里显式教**：元数据镜像可重建、分类/集合/树的成员关系**不可从会话面重建**（会话面根本不知道它们存在）——脱库重建 = 元数据行集恢复 + 组织数据**丢失**（这是 CATALOG-05「可由会话面全量重建」的精确边界：重建的是**元数据投影**，不是用户手建的组织树；文档与 UX 文案必须诚实，不得暗示组织数据也脱库无损）。
- **执行期决策边界**：分页 UI 形态（滚动加载 vs 页码）、树拖拽的自动展开语义、离线会话行在 Smart Albums 求值中的剔除、`.lcat` 文件锁（多开 app 实例）——标注执行期决策入各 plan DECISIONS，不臆造。
- **PROJECT.md:65 漂移修正与 Traceability 补账**挂 orchestrator 收口批（Boundary 事实 6），不进 worker plan。

</specifics>

<deferred>
## Deferred Ideas

- **v2 远程后端（pg / SQLite 镜像）**——CATALOG-06；三边界 + 驱动选型 + 基准双跑已存档 ROADMAP §Phase 16 Notes，届时重启裁决
- **多 catalog**（多 `.lcat` 管理/切换）——v1 单库；`CatalogIndexSchema` 无多库阻碍
- **组织数据的跨库导出/导入**（分类树 JSON 导出）——组织数据真身在 catalog，导出 = 自有格式 additive 议题
- **内容哈希去重 / 同内容文件合并**——无需求方 + 全库哈希不可行；需求出现时经 re-link 语义扩展
- **自动路径搜索 re-link**——手动 re-link 先行；扫描候选目录可后补
- **Write-through 投影优化**——水位追平已满足；热路径投影是优化非语义
- **MCP 筛选工具 catalog 求值**——Phase 14 研究项体系外；catalog 求值面就绪后是工具壳增量
- **`scope` 字段（SmartAlbum 规则级域绑定）**——v1 域随模式；字段随时 additive
- **FTS5 全文索引（note/filename 搜索加速）**——基准后按需；系统 3.54.0 含 FTS5，零依赖障碍

</deferred>

---

*Phase: 16-Catalogs Mode*
*Context gathered: 2026-09-26（discuss 起草；9 项 OQ 全按推荐自动裁决〔晨审追认〕——用户晨间任一推翻即回注 planner 重开受影响面；探针事实与 RQ 清单见 16-RESEARCH-QUESTIONS.md）*

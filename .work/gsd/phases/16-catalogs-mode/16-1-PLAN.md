---
phase: 16
plan: "16-1"
title: "Catalog 底座（全 Phase 依赖根）：CatalogIndexSchema 四表+关联表 DDL（31 列镜像终表 + 7 索引 + pragmas 基线）+ CatalogProjector 水位增量投影（键集对账 + 标签物化祖先展开 + sessions 入册）+ FilterSQL domain 分派（keywords EXISTS / orderBySQL / scopeClause 三落点）+ CatalogIndexStore keyset 查询面（NULL 尾段两段式 + `+` 前缀形状）+ 1M 行基准 harness 首跑落账"
wave: 1
depends_on: []
autonomous: true
requirements: [CATALOG-02]
files_modified:
  - LightamerCore/Sources/Catalog/CatalogIndexSchema.swift          # 新建：四表+关联表 DDL / 31 列冻结表 / 7 索引 / pragmas（WAL+NORMAL+cache_size+busy_timeout）/ schemaVersion=1 / v99 拒开 / 表驱动 migrate
  - LightamerCore/Sources/Catalog/CatalogProjector.swift            # 新建：水位增量投影 + 键集对账 + 标签物化（祖先展开算法）+ sessions 入册/离线标记 + sweep
  - LightamerCore/Sources/Catalog/CatalogIndexStore.swift           # 新建：actor 查询面——keyset 两段式分页 / 锚点消费 / COUNT 现算+memo / tag 批量 GROUP BY
  - LightamerCore/Sources/Session/FilterSQL.swift                   # domain 分派三落点：translate/translateConjoining 加 domain 参数（默认 .session 零改）/ keywords catalog 域 EXISTS 模板 / `+` 前缀纪律 / orderBySQL domain 参数 / scopeClause 新函数 / filename-dir contains→startsWith 降级
  - App/Sources/Lightamer/Session/SessionCoordinator.swift          # openAndSync 后台投影钩子（启用守卫内；:266 openAndSync 返回后挂）
  - Tests/LightamerTests/CatalogIndexSchemaTests.swift              # 新建：DDL 冻结断言 / pragmas VERBATIM / v99 拒开 / migrate 幂等
  - Tests/LightamerTests/CatalogProjectorTests.swift                # 新建：parity 34 列逐列 / 键集对账三腿 / 标签 golden 五形态 / 水位不丢行 / 离线标记 / 双模式隔离
  - Tests/LightamerTests/CatalogFilterSQLTests.swift                # 新建：domain 分派矩阵 / EXISTS 模板 / `+` 前缀 plan 断言（EXPLAIN 无 TEMP B-TREE）/ keyset 全形状 suite
  - Tests/LightamerTests/CatalogBenchmarkHarness.swift              # 新建：fixture 生成器（参数化）+ 查询集矩阵 runner（SC#3 口径）
  - .work/gsd/phases/16-catalogs-mode/perf.md                       # 新建：harness 首跑数字 + PRAGMA 基线入档
  - .work/gsd/phases/16-catalogs-mode/16-1-SUMMARY.md
  - .work/gsd/phases/16-catalogs-mode/16-1-DECISIONS.md
  - TODO.md                                                         # Phase 16 节开账 + 16-1 勾选
  - LESSONS.md                                                      # 如踩坑
---

# Plan 16-1 — Catalog 底座（W1，全 Phase 依赖根）

> 背景：把 Phase 9/12 已验证的 session 索引底座放大到跨会话域（D-16-CONTEXT-1/2/3）。
> 四条主线（16-RESEARCH 正本）：① `CatalogIndexSchema` —— `.lcat` 单文件四表 + 三关联表 +
> **31 列语境化镜像**（29 镜像列 + `session_id` + 稳定 `id`；`path`→`rel_path` 改名；thumb 三列
> 与 `scan_epoch`/`dirty` 不镜像，§RQ-16-2 终表）+ **7 索引**（排序索引统一形状
> `(k IS NULL, k [DESC], rel_path)`，F6）；② `CatalogProjector` —— 水位增量投影 +
> **键集对账**（修正①：纯水位 diff 检测不到删除行）+ 标签物化表祖先展开（§6 串域前缀展开
> 算法，R7）；③ **FilterSQL domain 分派一次落齐**（修正③三落点：keywords EXISTS 模板 /
> orderBySQL domain 参数 / scopeClause 锚点 + `+` 前缀形状纪律 F10）——从 16-2 草案前移至本
> plan：`CatalogIndexStore` 查询面与 harness 必须消费真实分派产物，缝 a（SQL 生成收口
> FilterSQL 单面）才能在 16-1 闭环断言；④ 基准 harness（RQ-16-13 参数化 fixture + §1.5 查询
> 集矩阵）——SC#3 的 harness 早建早好，索引设计问题在 UI 面之前暴露（D-16-CONTEXT-9）。
> 内部任务序刚性：schema → projector → FilterSQL 分派 → store 查询面 → harness（前者是后者
> 的编译依赖序；FilterSQL 分派先于 store，store 消费其产物）。

## read_first

1. `.work/gsd/phases/16-catalogs-mode/16-RESEARCH.md` 全文——§0 探针事实表（F6-F16）、§1（DDL
   verbatim + `+` 前缀纪律 + COUNT 裁决 + SC#3 查询集定义）、§2（标签物化形状）、§3（镜像列终
   表 + session 身份）、§4（投影时序图 + 修正①键集对账）、§5（FilterSQL 落点）、§6（keywords
   `|` 歧义与 v1 裁决）、§7（RQ-16-13 harness 规格 / RQ-16-17 并发）、§9（三缝 grep 审计清
   单）、§10（本 plan 任务/AC 草案正本）
2. `.work/gsd/phases/16-catalogs-mode/16-CONTEXT.md` D-16-CONTEXT-1（四表骨架/31 列/稳定 id）、
   D-16-CONTEXT-2（投影触发/水位/Sessions 零触碰语义）、D-16-CONTEXT-3（标签物化/形状分派）、
   D-16-CONTEXT-8（三道受控缝——纪律不是代码）、继承定案节（pragmas 基线/L013/one-way 格式锁/
   失败语义）、验证红线节（parity/隔离断言/标签 golden 口径）
3. `LightamerCore/Sources/Session/SessionIndexSchema.swift`：`schemaVersion = 2`（:49）、
   `imagesColumns` 冻结表（:66）、`apply(to:)` pragmas + version dispatch + v99 拒开
   （:173-231）、`migrate(from:to:on:)` 表驱动幂等先例（:234-262）——`CatalogIndexSchema` 逐行
   模板
4. `LightamerCore/Sources/Session/SessionIndexStore.swift`：头部真身纪律注释（:8-12）、
   `openSession` 五步编排（:172）、`sync` 单事务 diff 三腿（:279-487——键集对账的 added/
   removed/changed 纪律范本）、`query(groups:sort:limit:)`（:563——catalog 查询面同构孪生）、
   `rowSelectColumns` 单一拼写（:600 起）、`materializeKeywords`（:826）、
   `claimMetadataApply` 单事务循环（:1177）
5. `LightamerCore/Sources/Session/FilterSQL.swift`：头部 SQL 红线注释（:8-22）、`orderBySQL`
   （:100——`, path ASC` 尾巴即 domain 参数改造位）、`translate`（:110）/
   `translate(group:appendsBaseline:)`（:117）、keywords 四条款两处消费（:190/:197）、
   `fourClause`（:220）、字段白名单（:348-367）、`translateConjoining`（:380）
6. `LightamerCore/Sources/Session/SQLiteHandle.swift`（handle 薄封装——缝 c 唯一 C API 面）+
   `LightamerCore/Sources/Session/SmartAlbumStore.swift`（:26-39 document / :78-85 默认目录
   惯例——catalog 位置常量同款）
7. `App/Sources/Lightamer/Session/SessionCoordinator.swift`：`openAndSync`（:266——投影钩子挂
   点；openSession 五步返回后后台 Task）
8. `App/Sources/Lightamer/State/SessionState.swift` 的 `SessionState.promoteRecent`（:265 起；checker M1 路径修正——原 research 误挂 Coordinator 名下）
   URL 精确去重语义（SESSION 面先例；catalog_sessions 复用判定同构）
9. `LESSONS.md` L009（fixture 禁 UNITEK / 同目录 tmp 晋升）/ L013（哈希 decimal String）/ L020
   （内容级断言）/ L031（唯一路由纪律——本 plan 的 SQL/DDL/C-API 三缝落实正本）+ `AGENTS.md`
   （Phase 执行模型 + 暂停机制）+ `.work/GOAL-STATE.md`（Phase 16 续接点）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 本任务申报文件）；`caffeinate -dis` 包裹一切
  构建（`xcodebuild build-for-testing` 先行——test-direct 前提）。
- **单测命令** = `Scripts/test-direct.sh '<Class>'`；**判据 = Executed 计数行 + failures 行**，
  Executed 0 = 判据失败（防空转假绿）。
- **每任务边界检查 `.work/config.toml [gsd]` 开关（`auto`/`paused`）**——commit 后、下一任务
  前：`paused=true` 全链路停；`auto=false` 完成当前任务后停等「继续」。
- **不 push**（本 Phase 全部 plan 同此）。
- **构建勿加 `-derivedDataPath`**（SPM submodule 坑）；**新文件后跑 `tuist generate`**（11-03
  教训——本 plan 新建 `LightamerCore/Sources/Catalog/` 目录与 4 个测试文件，T1 提交前 generate
  一次，后续任务每新建文件同）。
- **回归基线 = 1437/6skip/0fail**（12 验收轮后终值；任务书旧值 1390 为 12-4 后数字，勘误以
  GOAL-STATE Phase 12 闭环行为准）；每任务全套 suite 绿（收尾轮 = 1437 + 新增，0 fail）。
- **在案 flake 归因条款**：`LayerE2ERoundTripTests` 负载型 flake 若现，隔离 ×3 归因单列入
  SUMMARY，不计本 plan 违约。
- **fixture 禁 UNITEK 盘**（L009）——harness fixture 落真机本地盘临时目录（/tmp 即弃，
  perf.md 记路径口径）；基准库为一次性产物，禁入工作区/入仓。
- **L031 三缝 grep 审计（本 plan 交付时自证，16-4 T3 终审计复核）**：
  `grep -rn "SELECT\|WHERE" LightamerCore/Sources/Catalog/` 命中仅 CatalogIndexStore 查询面
  拼接（消费 FilterSQL 产物）与 CatalogIndexSchema DDL；
  `grep -rn "CREATE TABLE\|CREATE INDEX\|PRAGMA" LightamerCore/Sources App/Sources` 命中仅
  SessionIndexSchema / CatalogIndexSchema 两文件；
  `grep -rn "sqlite3_\|import SQLite3" LightamerCore App` 命中仅 SQLiteHandle.swift。
- **L031 Metal 面声明**：Phase 16 无新 iop/Metal 面，`makeRoutedCommandBuffer()` 红线本 phase
  **不适用**（16-1 无任何 Metal 触点；如执行中发现需要即停下报告，不得自建队列）。
- **写事务形态**：投影/树/归类一律 `BEGIN IMMEDIATE` 单事务（RQ-16-17，busy 立即显式化）；
  handle 不出 actor 隔离（SessionIndexStore 同款 confinement）。
- **one-way 格式锁**：`.lcat` `schemaVersion = 1` + v99 拒开 + 失败 ROLLBACK + typed error；
  catalog 打不开永不波及 Sessions 模式（失败语义继承定案）。
- RESEARCH/CONTEXT 未覆盖细节（分页 page size 常量、memo 失效键拼写等）标注**执行期决策**入
  `16-1-DECISIONS.md`，不臆造。

## Tasks

### T1 CatalogIndexSchema：四表 + 关联表 DDL + pragmas 基线

- **action**
  1. 新建 `LightamerCore/Sources/Catalog/CatalogIndexSchema.swift`（enum，SessionIndexSchema
     逐行模板）。位置常量一处：默认
     `~/Library/Application Support/Lightamer/Catalog/catalog.lcat`（SmartAlbumStore.swift:78-85
     同目录惯例）；`schemaVersion = 1`；`MetaKey`（schemaVersion，无 scan_epoch——水位在
     catalog_sessions 行级）。
  2. **pragmas 集中**（`apply(to:)` 内，F13 基线）：`journal_mode=WAL` / `synchronous=NORMAL` /
     `cache_size=-64000`（−25% 实测收益）/ `busy_timeout=5000`（RQ-16-17 双实例）；`mmap_size`
     不设（<2% 增益，可选项不入基线——DECISIONS 记录）。
  3. **七张表 DDL**（列名拼写 verbatim，16-RESEARCH §1.2/§RQ-16-2/§RQ-16-3）：
     - `catalog_images`：`id INTEGER PRIMARY KEY`（稳定内部键，rowid alias——VACUUM 不改列值，
       RQ-16-7②）+ `session_id TEXT NOT NULL` + 29 镜像列（`path`→`rel_path` 改名；`scan_epoch`
       /`thumb_state`/`thumb_path`/`thumb_params_hash`/`dirty` 五列不镜像；其余逐列同名同型照
       SessionIndexSchema.swift:66-102；`params_hash` DECIMAL TEXT 照抄——L013）+
       `UNIQUE(session_id, rel_path)`（隐含唯一索引，复合身份 + 会话域过滤）。
     - `catalog_sessions`：`session_id TEXT PRIMARY KEY, root_path TEXT NOT NULL, display_name
       TEXT, last_projected_epoch INTEGER NOT NULL DEFAULT 0, last_seen REAL, offline INTEGER
       NOT NULL DEFAULT 0`（RQ-16-3 终列）。
     - `categories(id INTEGER PRIMARY KEY, parent_id INTEGER, name TEXT, sort_order INTEGER,
       created_at REAL)`——邻接表，`parent_id` **不声明外键**（纪律：孤儿防御在 UI 强制先处置
       子树，RQ-16-8）。
     - `collections(id INTEGER PRIMARY KEY, name TEXT, sort_order INTEGER, created_at REAL)`。
     - `image_categories(category_id INTEGER, catalog_image_id INTEGER, PRIMARY KEY(category_id,
       catalog_image_id)) WITHOUT ROWID`。
     - `image_collections(collection_id INTEGER, catalog_image_id INTEGER, PRIMARY KEY
       (collection_id, catalog_image_id)) WITHOUT ROWID`。
     - `image_tags(tag TEXT, catalog_image_id INTEGER, PRIMARY KEY(tag, catalog_image_id))
       WITHOUT ROWID`（F11：单聚簇结构即覆盖索引；等值 EXISTS plan = PK seek）。
  4. **7 索引**（§1.2 verbatim）：`idx_cat_cd_desc/idx_cat_cd_asc/idx_cat_rt_desc/idx_cat_rt_asc/
     idx_cat_fn/idx_cat_rel` 六排序/尾段索引（统一形状 `(k IS NULL, k [DESC], rel_path)`）+
     UNIQUE 复合身份即第七。**不建过滤列索引**（idx_cat_cam/idx_cat_cl 被裁决移除——F10 `+`
     前缀纪律替代，DECISIONS 记录）。
  5. `apply(to:)`：pragmas → 七表 DDL → version dispatch（absent → stamp 1；`1` → ok；
     `>1` 或 unparsable → typed `schemaFailed` 拒开——SessionIndexSchema.swift:192-215 同款语义）。
  6. 表驱动 `migrate(from:to:on:)` 先例落位（:234-262 模板照搬，v1 首版为空实现位——为 v2 加列
     预留，幂等语义当场钉死）。
  7. `tuist generate` 后构建绿。
- **证据**：`CatalogIndexSchemaTests`——七表 `PRAGMA table_info` VERBATIM 冻结断言（31 列序
  钉死）/ 7 索引 `PRAGMA index_list` 断言 / pragmas VERBATIM（WAL/NORMAL/-64000/5000）/
  v99 与 unparsable 拒开 / 二次 open 幂等零害 / 失败 ROLLBACK 后原文件字节不变（L020 内容级）。

### T2 CatalogProjector：水位增量投影 + 键集对账 + 标签物化 + sessions 入册

- **action**
  1. 新建 `LightamerCore/Sources/Catalog/CatalogProjector.swift`（actor，handle confinement 同
     SessionIndexStore）。核心 = `project(sessionRoot:lindexHandle:)` 单事务（`BEGIN IMMEDIATE`）：
     - **①入册**：`catalog_sessions` 无 `root_path`（realpath(3) 归一后精确串比对——L027）行则
       INSERT + 发 `session_id`（UUIDv4 字符串）+ `display_name = root.lastPathComponent`；已有
       则复用 id + 更新 `last_seen`。
     - **②键集对账**（修正①）：`SELECT rel_path FROM <lindex.images>` 全键 ⊕
       `SELECT rel_path FROM catalog_images WHERE session_id=?`（复用 SessionIndexStore.sync
       :279-487 三腿纪律的跨库孪生）→ `removed` = catalog 有 lindex 无 → DELETE 行 +
       `DELETE FROM image_tags WHERE catalog_image_id IN (...)`。
     - **③水位增量**：`SELECT <29 镜像列> FROM lindex.images WHERE scan_epoch > ?`（水位 =
       `catalog_sessions.last_projected_epoch`）→ `INSERT INTO catalog_images (...) VALUES (...)
       ON CONFLICT(session_id, rel_path) DO UPDATE SET <镜像列>`（F12 形状；conflict 路径**保留
       既有 id**——组织数据引用不悬空，R1）→ 每行 tags 删净重插（per-image 幂等，R6）。
     - **④标签物化**：lindex `keywords` 物化串（`materializeKeywords` :826 形态）→ **串域前缀
       展开算法**（§6 裁决的精确形式化，plan 期定死，worker 不得自行解读）：
       ```text
       rows(from materialized: String?) -> Set<String>:
         nil        -> ∅                     // NULL = 未打标
         ""         -> ∅                     // 空串 = 已清空（镜像列保持 NULL/'' 两态）
         tokens     = materialized.split("|")
         rows       = Set(tokens)                        // 每个 split token 直打行
         rows      += { tokens[0..<i].joined("|") for i in 1...tokens.count }  // 位置前缀链
       ```
       层级串 `"A|B|C"` → {A, B, C, A|B, A|B|C}（对 CONTEXT D-3 的 3 行 golden 是**超集**——
       research §6「同源超集语义」裁决；平铺串 `"X|Y"` → {X, Y, X|Y}，其中 X|Y 是 session 面
       四条款 `= ?` 也命中的合法 tag，非假行）。两态（NULL/''）的区分由**镜像 keywords 列**承
       担（FilterSQL empty/notEmpty 谓词消费），image_tags 行集对两态同为 ∅。
     - **⑤离线标记**：`stat <root>/.lightamer/session.lindex` 失败 → 本会话跳过 + 水位不动 +
       `offline=1`（恢复时 sweep stat 成功 → 清 0）；lindex 在场 → `offline=0`。
     - **⑥水位推进**：`UPDATE catalog_sessions SET last_projected_epoch = <lindex 当前
       scan_epoch>, last_seen = …` → COMMIT。lindex 读取用只读连接打开（投影不写 lindex）。
     - **⑦启用守卫**：`CatalogPreferences.catalogsEnabled`（偏好读面，本 plan 落 UserDefaults
       键 + 常量；UI 开关在 16-2）为 false 时 `project` 直接返回——**未启用 Catalogs 时打开会
       话零 `.lcat` 句柄**（ Sessions-only 用户零触碰的字面执行）。
  2. **触发面两条**（RQ-16-4 时序图）：a. `SessionCoordinator.openAndSync`（:266）openSession
     五步返回后**后台 Task** 调 `project`（不阻塞开卷预算；守卫内）；b. `sweepAll()`——遍历
     `catalog_sessions` 串行逐会话跑 ①-⑥（任务间 `Task.yield`），+ 罗列 recent 列表已打开未入
     册会话入册（16-2 接 UI 启动时机，本 plan 落 API + 测试直调）。
  3. **不做**：全量重建两档（16-4 T2）；库内 DELETE 型重建（F12 freelist ~470MB 实测禁止）。
- **证据**：`CatalogProjectorTests`——**投影 parity**：catalog 行 vs 源 lindex 行 29 镜像列
  逐列断言 + session_id（L020 内容级）；**键集对账三腿计数**（added/removed/changed 对账，删
  除行闭合——构造 lindex 删行场景断言 catalog 滞留行为零）；**标签 golden 五形态 + 跨域行集方向性对照**（catalog 行集 ⊆ session 域四联式行集——中段路径 `B|C` session 命中而 catalog 无行为 by-design，research §6「同源超集」裁决替代 CONTEXT 等值对照，checker M2 登记面；平铺多标
  签 / 层级标签 / 混合 / NULL / 空串——§6 四形态 + research 超集定义）；**水位不丢行**（两次
  投影幂等 + 中途加行只投增量）；**离线标记**（root 缺失 → offline=1 水位不动 → 恢复清 0）；
  **双模式隔离**：守卫 false 时 openAndSync 全流程 `.lcat` 零句柄（注入探针断言文件未创建）；
  **UPSERT 保 id**（二次投影后 id 不变 + tags 引用有效）。

### T3 FilterSQL domain 分派（修正③三落点 + `+` 前缀纪律）

- **action**
  1. `FilterSQL.swift` 内定义 `public enum FilterDomain { case session, catalog }`。`translate`
     （:110）加第三参 `domain: FilterDomain = .session`——默认值保既有调用零改；
     `translate(group:appendsBaseline:)`（:117）与 `translateConjoining`（:380）同参透传。
  2. **落点 a——keywords EXISTS 模板**：keywords 字段的 contains/eq 两 op 在 catalog 域翻
     `EXISTS (SELECT 1 FROM image_tags t WHERE t.tag = ? AND t.catalog_image_id = i.id)`（单
     等值 bind，无 ESCAPE/LIKE——物化已展开祖先；外层别名 `i` = catalog 查询面恒定拼写
     `FROM catalog_images i`，约定钉死在模板注释）；session 域四条款（:190/:197/:220）原样零改。
  3. **落点 b——`+` 前缀形状纪律**（F10）：catalog 域生成的每个**非排序过滤词项**恒带 `+` 一
     元前缀（`+i.camera_model = ?` 等；rating/color_label/dir/filename 等值与区间同款；EXISTS
     子查询内部不加——子查询本就走 tags PK）。session 域零改。
  4. **落点 c——orderBySQL domain 参数**：`FilterSort.orderBySQL`（:100）加 `domain` 参数（默
     认 `.session`）；catalog 域尾巴 = `rel_path ASC` 且 NULL-flag 表达式与表达式索引逐字对齐
     （§1.1：`(capture_date IS NULL), capture_date DESC, rel_path ASC` 拼写 = DDL 逐字）。
     `FilterSortKey.column` catalog 域同名列直翻（15 字段同名白名单复用 :348-367）。
  5. **落点 d——scopeClause 锚点**：新函数 `FilterSQL.scopeClause(domain:sessionID:categoryID:
     collectionID:) -> (sql: String, binds: [FilterSQLBind])`——会话分组点选 = `i.session_id =
     ?`；树点选 = `EXISTS (SELECT 1 FROM image_categories ic WHERE ic.category_id = ? AND
     ic.catalog_image_id = i.id)`；集合点选同构 image_collections；多锚 AND 组合；v1 chips 不加
     组织谓词字段（锚点即点选，RQ-16-11③）。
  6. **filename/dir contains 降级**（RQ-16-16①）：catalog 域 filename/dir 的 contains op 翻
     **startsWith**（`LIKE ? || '%' ESCAPE '\'`，保留既有 ESCAPE 纪律）+ `CatalogIndexSchema
     .apply` 落 `PRAGMA case_sensitive_like=ON`（连接级，使 startsWith 走 BINARY 索引）；语义
     损失 = 大小写敏感化，plan 期定死（research 推荐①），zh/en 文案差异 16-2 批。
  7. **baseline 不动**：`orphan_sidecar = 0` 两域同款（镜像列保证）。
- **证据**：`CatalogFilterSQLTests`——domain 分派矩阵（16 字段 × 2 域 × 各 op：session 域全部
  输出与改造前逐字节相同——回归锁；catalog 域 keywords→EXISTS / contains→startsWith / `+` 前
  缀在场）；**bind 对齐断言**（EXISTS/四条款各自 bind 数与顺序）；**EXPLAIN plan 断言**（1 万行
  fixture：keyset 主段 `SCAN … USING (COVERING) INDEX` 零 TEMP B-TREE——F6/F10 形状回归锁，1M
  级在 harness）。

### T4 CatalogIndexStore：keyset 两段式查询面 + COUNT 面

- **action**
  1. 新建 `LightamerCore/Sources/Catalog/CatalogIndexStore.swift`（actor，handle confinement；
     open = 建目录 + `SQLiteHandle` + `CatalogIndexSchema.apply`；失败 typed error 向上 =
     Catalogs 模式降级禁用，绝不波及 Sessions）。查询面恒定拼写 `FROM catalog_images i`（T3 模
     板别名契约）。
  2. **keyset 分页 API**：`queryPage(groups:sort:anchor:limit:)`——主段 = WHERE <FilterSQL 产
     物> AND <scopeClause 锚点> AND <row-value seek> ORDER BY <orderBySQL(domain: .catalog)>
     LIMIT ?；seek 谓词按 sort 方向生成 `(k, rel_path) < (?, ?)` / `> (?, ?)`（DESC 用 `<`——
     NULL 主键值行被 seek 自然排除，恰好跳过 NULL 层，§1.1）；**NULL 尾段** =
     `queryNullTail(groups:sort:anchor:limit:)`——`k IS NULL AND rel_path > ?`（走 idx_cat_rel，
     F15）仅对可 NULL 排序键（date/rating）提供；filename 恒非 NULL 单段。**两段拼接语义**（UI
     数据源 = 每排序键主段+尾段）写入 API doc comment。
  3. **首屏形状**：`anchor = nil` 时无 seek 谓词，ORDER BY … LIMIT 60 直接索引头（§1.1）。
  4. **COUNT 面**（§1.4 裁决）：`count(groups:)`——简单谓词现算（单字段/无过滤全库）；组合与
     标签谓词走**会话级 memo**（`[FilterPredicateGroup.hash: Int]` NSCache 形态；失效钩子 =
     `invalidateCounts()`，由投影完成方与 16-3 归类写入方调用）；**tag 批量计数** =
     `tagCounts()` → `SELECT tag, COUNT(*) FROM image_tags GROUP BY tag` 单次索引扫，调用方刷
     内存字典。memo 键拼写入 DECISIONS。
  5. **行读出**：`rowSelectColumns` 单一拼写（31 列序 = T1 冻结表同源；`readRow` 投影函数同构
     SessionIndexStore :600 起）；单行读 `fetchRow(sessionID:relPath:)`；`imageID(for:)` 批量查
     id（tags/归类写面引用键）。
  6. **跨域禁止**：本文件零 lindex 触碰（投影单向上行）；零裸 SQL 翻译（一切 WHERE 片段来自
     FilterSQL 产物——缝 a）。
- **证据**：`CatalogFilterSQLTests` 扩段（或独立 `CatalogIndexStoreTests` 并入同文件申报）——
  **keyset 全形状 suite**：§1.5 排序 4 键 × 正/反方向 × 三深度（10k fixture）页序严格递减/递
  增断言 + `+` 前缀 plan 断言（EXPLAIN 零 TEMP B-TREE）+ NULL 尾段衔接（主段末页 → 尾段首行
  无缝无重复）；COUNT memo 失效语义（投影后 memo 清、简单谓词不走 memo——可注入计数器断言）。

### T5 基准 harness（SC#3 口径首跑落账）

- **action**
  1. 新建 `Tests/LightamerTests/CatalogBenchmarkHarness.swift`——**非 CI 常规测试**（`skip` 或
     环境变量门控 `LA_CATALOG_BENCH=1`，真机手动跑；SC#3 终测同 harness，16-4 T1 复用）。
  2. **fixture 生成器**（RQ-16-13 参数化，默认 1M）：N（1M）/ 会话数 10 / 标签分布（直打 1-3 ×
     深度 1-3 → 膨胀系数 3-9M tags 行）/ NULL 率（capture_date 10%、rating 60%、color_label
     70%）/ EXIF 空洞率（camera 未扫 ~20%）/ 40% 行带层级标签串。落盘真机本地盘（/tmp 即弃，
     L009 禁 UNITEK）。生成走批量 prepared 循环 + 单事务分批 COMMIT（PERF-07 教训：禁 temp-table
     join）。
  3. **查询集矩阵 runner**（§1.5）：过滤 8 款（无过滤 / rating≥4 / color_label 等值 /
     camera_model 等值 / date 区间 / tag 等值高频祖先 / tag+rating / rating+camera+date 最坏
     组合）× 排序 4 款（date DESC 默认 / date ASC / rating DESC / filename ASC）× 深度 3 档
     （0 / 40 万 / 80 万；combo 按实际结果集比例）——每形状 30 页 × 60 行取 p95，冷/热分离，
     Debug/Release 分栏；**COUNT 面**（§1.4 表：全库 / rating≥4 / camera 等值 / 组合 / tag 全
     量）；**投影吞吐三场景**（10 万行全量重建 ≤30s 级预算核 / 单会话 1 万行增量 / 纯 diff 读）。
  4. **报告落账** `.work/gsd/phases/16-catalogs-mode/perf.md`（目录整并后真路径，勘误⑤）：
     PRAGMA 基线入档（WAL+NORMAL+cache 64MB+busy 5000）、fixture 参数、全部 p95 表、与 research
     F6-F16 探针数字对账列（偏差 >2× 须归因注记）。
  5. **首跑门（软门）**：keyset 全形状 p95 与探针同量级（<50ms 预期）；任一形状超门 = 停下归因
     （索引缺失/planner 形状回归/harness 口径），修复或注记后方可收 plan——**不是**硬判失败
     （SC#3 硬裁决在 16-4 T1 真机终测）。
- **证据**：perf.md 首跑全表 + 软门判定行 + 超门形状的归因注记（如有）；fixture 参数与生成耗
  时记录。

### T6 全量回归 + SUMMARY + DECISIONS

- **action**：全 suite 终轮（基线 **1437/6skip/0fail** + 新增，0 fail）；L031 三缝 grep 审计三
  连跑（纪律节三条命令，输出贴 SUMMARY）；TODO.md 开 Phase 16 节 + 16-1 勾选；
  `16-1-SUMMARY.md`（任务表/commit 表/证据/harness 首跑指针）；`16-1-DECISIONS.md`（memo 键拼
  写、page size 常量、mmap 不入基线、过滤索引不建的 F10 依据复核、标签前缀展开算法对 research
  §6 原文的忠实性复核、其余执行期决策）；新教训候选评估入 LESSONS。
- **证据**：测试计数（1437 → N，0 fail）；三缝审计输出；SUMMARY + DECISIONS 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| schema | 七表 31 列冻结 + 7 索引 + pragmas VERBATIM + v99 拒开 + 幂等 | `Scripts/test-direct.sh 'CatalogIndexSchemaTests'` |
| 投影 | parity 29 镜像列逐列 + 对账三腿 + 标签 golden 五形态 + 跨域方向性对照 + UPSERT 保 id + 离线 + 隔离 | `Scripts/test-direct.sh 'CatalogProjectorTests'` |
| FilterSQL | session 域逐字节回归锁 + catalog EXISTS/`+`/orderBy/scope/startsWith | `Scripts/test-direct.sh 'CatalogFilterSQLTests'` |
| 查询面 | keyset 全形状 + NULL 尾段衔接 + COUNT memo | `Scripts/test-direct.sh 'CatalogFilterSQLTests'`（Store 段） |
| harness | 首跑全表落 perf.md + 软门判定 | `LA_CATALOG_BENCH=1 Scripts/test-direct.sh 'CatalogBenchmarkHarness'` |
| 回归 | 全 suite 0 fail（基线 1437+新增） | `caffeinate -dis Scripts/test-direct.sh`（全套） |
| 三缝 | grep 三连仅命中申报文件 | 纪律节三条命令（输出入 SUMMARY） |

## 验收标准（Acceptance）

- [ ] `CatalogIndexSchema`：四表+三关联表（image_tags/categories/collections 关联全 WITHOUT
      ROWID 按裁决）+ 31 列冻结（列序钉死、`rel_path` 改名、五列不镜像）+ 7 索引统一形状 +
      pragmas 基线（WAL/NORMAL/cache 64MB/busy 5000）+ `schemaVersion=1` + v99/unparsable 拒开
      + migrate 先例落位 + 失败不破坏原文件
- [ ] `CatalogProjector`：水位增量 UPSERT（conflict 保 id）+ **键集对账删除闭合**（修正①）+
      标签物化五形态 golden（research §6 超集算法定死）+ sessions 入册（UUIDv4/realpath/
      display_name）+ 离线标记 + sweep 串行 API + openAndSync 后台钩子（守卫内）
- [ ] **双模式隔离**：守卫 false 时 Sessions 全流程零 `.lcat` 句柄（探针断言）；投影失败
      ROLLBACK + typed error，Sessions 模式零波及
- [ ] FilterSQL domain 分派：session 域输出逐字节回归锁（既有 FilterSQLTests 全绿不动）+
      catalog 域 keywords EXISTS 模板（别名 `i` 契约）+ `+` 前缀纪律（EXPLAIN 断言零 TEMP
      B-TREE）+ orderBySQL domain + scopeClause + filename/dir startsWith 降级（case_sensitive_
      like=ON）
- [ ] `CatalogIndexStore`：keyset 两段式全形状（4 排序键 × 双向 × 3 深度）+ 首屏索引头 + NULL
      尾段无缝 + COUNT 现算/memo/批量 GROUP BY + 行读单一拼写
- [ ] harness：参数化 fixture（1M 默认、五参数）+ §1.5 全矩阵首跑 p95 落 perf.md + PRAGMA 基线
      入档 + 软门判定行（超门形状归因注记）
- [ ] 三缝 grep 审计三连仅命中申报文件；全 suite 0 fail（1437+新增）；每任务独立提交 + 边界查
      config 开关；不 push；无 /tmp 产物入工作区（基准库除外——/tmp 即弃有据）；SUMMARY +
      DECISIONS 落盘

# Phase 16: Catalogs Mode — Research Questions

**Created:** 2026-09-26（discuss 环起草；给 research 环的问题清单，答案落 `16-RESEARCH.md`）
**输入:** `16-CONTEXT.md`（D-16-CONTEXT-1..9 + Phase Boundary）+ ROADMAP §Phase 16 + REQUIREMENTS CATALOG-01..06
**约定:** 每条 RQ 给「问题 / 为什么 / 验证方法 / 关联裁决」。P0 = 阻塞 plan 划界的答案；P1 = plan 内可并行解决。带 ★ 的 = 本环已做低成本探针，research 复测/深化即可。

---

## 已验证探针事实（2026-09-26 本机，`:memory:` 1M 行 fixture）

| # | 事实 | 数字 | 对裁决的含义 |
|---|---|---|---|
| F1 ★ | 系统 libsqlite3 版本 | **3.54.0** | 递归 CTE / CTE / 部分索引 / FTS5 全可用，零依赖障碍（D-16-CONTEXT-4/8） |
| F2 ★ | categories 树递归 CTE（3 层子树展开） | **0.05ms** | 邻接表 + WITH RECURSIVE 在 v1 树规模零压力（D-16-CONTEXT-4 定案依据） |
| F3 ★ | keywords LIKE 四条款全扫（无索引） | **83ms** @1M | 查询期展开在百万级超 50ms 门 → 标签物化表（D-16-CONTEXT-3）必要性直接佐证（SC#2 黑体的立项证据） |
| F4 ★ | 朴素 OFFSET 分页（过滤+双键排序+OFFSET 400k） | 混合方向（DESC,ASC）**157ms** / 同向（ASC,ASC）**59ms** | **均超 50ms 门** → SC#3 不是走过场：OFFSET 大偏移与混合方向排序是朴素形状的已知短板，keyset pagination（seek method）/ 覆盖索引设计是 research 真问题（RQ-16-6） |
| F5 ★ | 标签 EXISTS 等值查询 | **数字异常待复测**（count=571 不合 fixture 逻辑；疑似 prepared-stmt 复用/绑定序列问题，非引擎问题——tag 表 3M 行已 verified 入库） | 复测后才能确认等值形状的绝对性能；形状本身（等值+复合索引）方向不变 |

> 探针为 `:memory:` 单机口径，绝对数字不作基准结论；基准终测 = 16-4 真机落盘 `.lcat`（F4 的 keyset 形状复测进 RQ-16-6）。

---

## A. 库 schema 与身份（P0——16-1 划界输入）

### RQ-16-1 `.lcat` 文件形态与位置细节
- **问题**: 单文件之外是否需要伴生文件（-wal/-shm 属 SQLite 自带，确认与备份/移动 `.lcat` 的交互语义）；设置里位置切换时旧库文件的处置（迁移 vs 重新指向）；空库引导（首次启用 Catalogs = 空库 + 「添加会话」引导）。
- **验证**: C1/LR 的 catalog 文件管理惯例对照（文档级）；`.lcat` 在 Finder 单文件拷贝后 WAL 残留检查（checkpoint on close 语义——`SessionIndexStore.close()` 既有面）。
- **关联**: D-16-CONTEXT-1。

### RQ-16-2 镜像列集终表
- **问题**: 34 列语境化的逐列终表——`path`→`rel_path` 改名外，`orphan_sidecar`/`dirty`/`scan_epoch` 三个会话运行态列是否镜像（推荐：`orphan_sidecar` 镜像、`dirty` 不镜像（写路径瞬态，投影时恒 0）、`scan_epoch` 不镜像（水位在 `catalog_sessions.last_projected_epoch`））；`capture_date` NULL/缺 EXIF 的排序语义跨库是否对齐 12-2（NULLs last）；新增列终集（`session_id` / `id` INTEGER PK）。
- **验证**: 列清单对照 `SessionIndexSchema.swift:66-102` 逐列过一遍，每列给「镜像/不镜像+理由」表——这份表直接进 16-1 PLAN。
- **关联**: D-16-CONTEXT-1。

### RQ-16-3 session 身份与生命周期
- **问题**: `session_id` 生成（推荐 UUIDv4，首次投影入册时发）；同一文件夹重新打开 = 同一 session_id 还是新身份（推荐：**root_path 精确匹配则复用**——同一文件夹物理上是同一会话）；会话被「从 catalog 移除」后 re-add 的身份语义；`display_name` 来源（文件夹名）。
- **验证**: 设计推演 + 与 SESS-04 recent 列表的既有会话身份语义对照（recent 列表用什么键识别同一会话——若已有稳定键则对齐）。
- **关联**: D-16-CONTEXT-1/7。

### RQ-16-4 投影触发的完整时序图
- **问题**: 打开会话增量投影的挂点（`openSession` 返回前同步做，还是返回后后台做——影响打开耗时）；Catalogs 模式启动 sweep 的并发度（串行逐会话 vs 有界并发）；投影中 UI 状态（半新半旧数据的可见性——推荐：单会话单事务 = 原子换档，无中间态）；lindex 被删（会话缓存重建中）时投影的降级（跳过该会话 + 待下次）。
- **验证**: 时序图推演 + `openSession` 耗时剖面（现基线打开 1 万会话的数字在 `.work/09/perf.md`——投影增量 ≤ 会话打开预算的百分之几）。
- **关联**: D-16-CONTEXT-2。

### RQ-16-5 投影吞吐基线（D-16-CONTEXT-2 的 plan 预算数字）
- **问题**: 10 万行全量投影实测耗时；单会话 1 万行水位增量实测；全库 sweep（N 会话 × 水位）的 Scaling。
- **验证**: ★ 探针扩展——fixture = 10 会话 × 1 万行 lindex，投影 = SELECT + 批量 UPSERT 单事务，测秒表。目标域：全量 ≤30s、单会话增量秒级（超出则回 CONTEXT 调触发面）。
- **关联**: D-16-CONTEXT-2（SC 面无硬门，plan 预算自定但要有数）。

## B. 查询面与基准门（P0——SC#3 是实证裁决）

### RQ-16-6 分页查询形状与索引设计（P0 首位）
- **问题**: ①keyset pagination（seek method：`WHERE (capture_date, rel_path) < (?, ?) ORDER BY … LIMIT n` 行表达式形状）vs OFFSET 在混合方向排序下的对比；②混合方向排序（DESC,ASC）的索引策略（SQLite 单列 DESC 索引不能服务双键混合方向——倒序索引 vs 覆盖索引 vs 排序键同向化）；③**真实查询集定义**（代表性过滤组合矩阵：评分/色标/关键字/相机/日期区间 × 排序键 × 分页深度——直接决定 SC#3 终测的「真实查询集」口径）；④COUNT 总数面（智能相册角标需要 count——`COUNT(*)` 全扫在 1M 行的代价与缓存策略）。
- **验证**: ★ F4 扩展探针——keyset vs OFFSET 双形状 × 混合/同向排序 × 有/无覆盖索引，1M 行落盘库（非 :memory:）实测矩阵；COUNT 代价单测。
- **关联**: SC#3（p95<50ms 终裁）、D-16-CONTEXT-9（16-1 harness）。

### RQ-16-7 标签物化表形状复测与引用键
- **问题**: ①★ F5 异常复测（等值 EXISTS 的真实性能）；②**引用键终判**——`image_tags.catalog_image_id` 引用显式 `id INTEGER PRIMARY KEY`（CONTEXT 已裁不用 rowid——VACUUM/删除后 rowid 重排，此条为已识别分叉的封口）；③祖先展开物化的行数膨胀系数（每图平均标签数 × 祖先深度——1M 图 × 3 标签 × 平均 2 祖先 = ~9M 行 tags 表的索引体积与查询影响）；④`is_direct` 列要不要（UI 无「仅直打」需求则不加）；⑤不含关键字谓词的查询是否被 tags 表 JOIN 拖累（EXISTS 短路验证）。
- **验证**: 修正版探针（逐条 INSERT 校验 rc + 新连接复验）+ 9M 行 tags fixture 的等值/组合查询实测。
- **关联**: D-16-CONTEXT-3、SC#2。

### RQ-16-8 树存储确认与拖拽排序模型
- **问题**: 邻接表在「深树 + 兄弟重排」下的写面（拖拽 = 受影响兄弟集 sort_order 重排的行数上限）；sort_order 用浮点间隙（fractional indexing）还是整数重排（推荐整数重排——树规模小）；树缓存的 App 侧形态（全树一次读入内存 vs 递归懒加载——v1 树规模推荐全读）。
- **验证**: 探针已过（F2）；拖拽语义推演即可，无需新探针。
- **关联**: D-16-CONTEXT-4。

### RQ-16-9 缩略图跨会话路由与内存预算
- **问题**: Catalogs 模式网格 = 行集跨 N 会话 → 每行缩略图需路由到对应会话的缩略图缓存（现 `thumb_path` 绝对路径在 `session.lindex`；catalog 不镜像）——路由 = `（session_id, rel_path）` → 定位 root → 拼会话缩略图路径；**多会话同时软打开的缩略图缓存聚合**（现 LRU 是 per-session？跨会话网格的 LRU 预算是共享池还是 per-session 池）；缩略图 stale 再生在 Catalogs 模式的触发路由（缩略图管线是 session 域资产）。
- **验证**: 读 Phase 9 缩略图管线的缓存作用域代码（`SessionBrowserView`/provider 层），给「路由 + 预算」设计案——这是 16-2 的最大未知面。
- **关联**: D-16-CONTEXT-1④/2/7。

### RQ-16-10 Catalogs 模式的编辑回环
- **问题**: Catalogs 网格点图进编辑器 = 打开对应会话（现 `openSession` 流程）→ 编辑写 sidecar → lindex 变 → **何时投影回 catalog**（推荐：返回网格/切换图片时增量投影——与 D-16-CONTEXT-2③ 一致，plan 期定时点）；跨会话多选批量操作（归类/评分）在 Catalogs 模式的语义（评分等元数据操作走 MetadataService 写各会话 sidecar + 投影追平——确认无新写路径）。
- **验证**: 流程推演 + MetadataService 消费面代码走查。
- **关联**: D-16-CONTEXT-2/7。

### RQ-16-11 FilterSQL 形状分派实现形态
- **问题**: ①分派位（`translate` 加 `target:` 参数枚举 `.sessionColumn/.catalogTags` vs `FilterSQL` 内部按列元数据判别）；②16 字段白名单在 catalog 域的可用性复核（`note`/`filename`/`dir` 等 TEXT 字段在 catalog 镜像列上直翻零改；`dir` 在 catalog 域语义 = 会话内子目录——语义仍成立？）；③catalog 域新增谓词字段（`category`/`collection` 成员谓词、`session` 谓词）v1 要不要进 chips（推荐：v1 chips 不加——组织过滤走侧栏树点选，谓词面保持 16 字段；additive 位留）。
- **验证**: 代码推演 + 字段×域可用性矩阵表（16 行 × 2 域）。
- **关联**: D-16-CONTEXT-3②/6、CATALOG-04。

## C. UI 与模式交互（P1——16-2 输入）

### RQ-16-12 模式切换交互细节
- **问题**: 切换器落位（侧栏顶部 vs 工具条——12-2 filter bar 同行的空间账）；未启用 Catalogs 时的设置入口文案；Catalogs 模式下编辑器（单图视图）的行为（编辑无模式差异——确认编辑器不感知模式，只有浏览器层分叉）；会话分组列表在 Catalogs 侧栏的位置（All Photographs 之下独立节）。
- **验证**: UI 走查（现 `ContentView.swift`/`SessionBrowserView.swift` 布局空间）+ C1 截图对照。
- **关联**: D-16-CONTEXT-5。

### RQ-16-13 基准 harness 规格（16-1 交付件的定义）
- **问题**: fixture 生成器参数（行数 N / 标签分布 / 会话数 / EXIF 空洞率——真实感参数）；查询集矩阵（RQ-16-6③ 的产出）；p95 采样口径（每查询 N 次取 p95，冷/热分离——现 12-RESEARCH 的 perf 方法论照抄）；PRAGMA 基线入档（journal/sync/cache_size/mmap_size——调优是计量项，逐项开关对比后定基线，不静默旋钮）；基准报告落账路径（推荐 `.work/16/perf.md`，Phase 9/12 先例）。
- **验证**: 无新探针——规格文档 + 复用 `.work/09/perf.md`/12-perf 方法论。
- **关联**: SC#3、D-16-CONTEXT-9。

### RQ-16-14 脱库降级与重建 UX
- **问题**: 重建进度 UI（进度条/可取消/后台完成通知）；重建期间 Catalogs 模式行为（空网格 + 进度浮层 vs 禁入）；「组织数据不可重建」的 UX 文案（CONTEXT specifics 的诚实边界——重建完成提示「元数据已恢复；分类与集合需重新整理」）；损坏 `.lcat`（schema 不识别/文件截断）的处置（禁用 Catalogs + 引导重建，永不波及 Sessions）。
- **验证**: UX 推演 + C1 verify/restore 流程对照。
- **关联**: CATALOG-05、D-16-CONTEXT-7、CONTEXT specifics「组织数据真身」条。

## D. 语义边界与风险（P1——晨审注意）

### RQ-16-15 「可全量重建」的精确边界（已识别语义分叉，需晨审知悉）
- **问题**: ROADMAP SC#2「可全量重建（mutable and untrusted 延续）」与 CATALOG-05「目录库数据丢失可由会话面全量重建」的字面，在**组织数据**（分类树/集合成员/手动归类）上不成立——会话面不知道它们存在，删库后元数据镜像可重建、组织数据**丢失**。CONTEXT 的处理（specifics 显式登记 + RQ-16-14 文案诚实）是否可接受，或需求面要补「组织数据备份」（`.lcat` 文件级备份即天然兜底——单文件拷贝）。
- **验证**: 无探针——晨审裁决项（推荐维持现状：单文件备份兜底 + 文案诚实，不加自动备份机制）。
- **关联**: SC#1/2、CATALOG-05、CONTEXT specifics。

### RQ-16-16 `dir` 谓词与网格分组的跨会话语义
- **问题**: session 域 `dir` = 会话内子目录；catalog 域 1M 行的 `dir` 值域膨胀（万会话 × 子目录）——Quick Filter 的 `dir` contains 谓词性能与语义（跨会话重名目录的行集是「散点」符合预期？）；网格按 `dir` 分组的 UI（若有）跨会话语义。
- **验证**: 谓词面推演；性能并入 RQ-16-6 查询集。
- **关联**: RQ-16-11②。

### RQ-16-17 多开/并发访问 `.lcat`
- **问题**: 两个 app 实例同时开同一 `.lcat`（WAL 支持多读者单写者——投影写事务与另一实例写冲突的 busy 语义）；v1 是否做文件锁（推荐：不做锁——`BEGIN IMMEDIATE` + busy_timeout 兜底，双开是边缘场景，真冲突 = 后写者重试）；与 Phase 14 研究项 A（同会话双写）的纪律对照。
- **验证**: SQLite 并发语义文档确认 + busy_timeout 参数落定。
- **关联**: D-16-CONTEXT-2、继承定案失败语义。

---

## 优先级与研究环顺序建议

| 序 | RQ | 优先级 | 类型 |
|---|---|---|---|
| 1 | RQ-16-6 分页形状+查询集 | P0 | 探针（设计定生死） |
| 2 | RQ-16-7 标签物化复测+引用键 | P0 | 探针 |
| 3 | RQ-16-2 镜像列终表 | P0 | 设计（16-1 PLAN 直用） |
| 4 | RQ-16-3 session 身份 | P0 | 设计 |
| 5 | RQ-16-4/5 投影时序+吞吐 | P0 | 推演+探针 |
| 6 | RQ-16-9 缩略图路由 | P0（16-2 前） | 代码走查+设计 |
| 7 | RQ-16-10/11 编辑回环+形状分派 | P0（16-2 前） | 推演 |
| 8 | RQ-16-1/8/13 | P1 | 设计/规格 |
| 9 | RQ-16-12/14/16/17 | P1 | 推演 |
| 10 | RQ-16-15 重建边界 | 晨审裁决项 | 语义确认 |

---

*Phase: 16-Catalogs Mode — Research Questions*
*起草: 2026-09-26（discuss 环；探针脚本为一次性 /tmp 脚本未留存，数字与方法已录本档；research 复测时按「验证方法」栏重建）*

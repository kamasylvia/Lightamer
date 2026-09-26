# Phase 16: Catalogs Mode — Research

**Completed:** 2026-09-27（research 环；回答 `16-RESEARCH-QUESTIONS.md` RQ-16-1..17，P0 优先）
**输入:** `16-CONTEXT.md`（D-16-CONTEXT-1..9）+ RQ 文件（F1-F5 探针事实）+ ROADMAP §Phase 16（SC#1-5）
**方法:** 探针实测优先——本轮在 **1M 行落盘库**（`/tmp/catalog-probe/catalog.lcat`，SQLite 3.54.0 系统 libsqlite3）上重建并扩展了 discuss 环的 `:memory:` 探针（F4/F5 复测 + 新形状矩阵）；schema/查询形状结论全部有实测数字背书，纯推演项显式标注。
**给 planner 的一句话:** D-16-CONTEXT-1..9 全部可执行，无推翻项；三处**语义增强**（投影需键集对账非纯水位 / 全量重建两档化 / FilterSQL 形状分派比预想多两处落点）+ 一处**新发现**（lindex keywords `|` 分隔符碰撞）见 §5 与 §6。

---

## 0. 本轮探针事实总表（F6-F16，接 RQ 文件 F1-F5）

环境：macOS 27 / 机器本地盘 `/tmp`（非 USB 卷，L009 口径）/ SQLite **3.54.0** / WAL + synchronous=NORMAL / fixture = 1M 行 10 会话（capture_date 10% NULL、rating 60% NULL、color_label 70% NULL、40% 带层级标签串）。探针脚本为一次性 /tmp 即弃件，数字与方法已录本档；绝对数字不作基准结论，基准终测 = 16-4 真机落盘 harness（RQ-16-13）。

| # | 事实 | 实测数字 | 出处 |
|---|---|---|---|
| F6 | 表达式索引 `(k IS NULL, k [DESC], rel_path)` **逐字匹配** NULLs-last ORDER BY；keyset row-value seek 无 TEMP B-TREE | A1/A3/A4/A5 全部 `SCAN … USING (COVERING) INDEX`，plan 零 temp b-tree | A1/A3/A4/A5 |
| F7 | **keyset 分页全形状过 50ms 门**（1M 行）：date DESC d400k p95 **10.3ms**；d800k p95 **20.5ms**；ASC d400k **10.7ms**；rating DESC（60% NULL）d100k **23.0ms**；filename d400k **0.01ms**；rating≥4 过滤 d100k **26.9ms** | 全部 <50ms 门 | A1/A3/A4/A5/A6 |
| F8 | OFFSET 基线（F4 复测，落盘库比 `:memory:` 更差 2-3×）：混合方向 d400k p95 **348ms** / 同向 **113ms** / d800k **316ms** / 过滤+OFFSET d150k **359ms** | 全部超门，OFFSET 判死 | A2/A7 |
| F9 | OFFSET 唯一幸存窄条 = 「无过滤 + 覆盖索引 + ORDER BY 逐字匹配」：d400k p95 **1.2ms**（E2）——一加过滤即崩（A7 359ms）→ 不可作为通用形状 | E2 |
| F10 | **planner 陷阱（新发现）**：低选择性等值过滤 + 异列排序，planner 默认走过滤索引 + TEMP B-TREE 物化 = cam **p95 201ms** / combo **p95 425ms**（max 525ms）超门；`+`-前缀（禁该词项用索引）强制排序索引领先 = cam **1.46ms** / combo **4.93ms**——**两个数量级** | E1 vs A6 |
| F11 | 标签物化复测（F5 修正）：等值 EXISTS plan = `SEARCH t EXISTS USING PRIMARY KEY (tag=? AND catalog_image_id=?)`（WITHOUT ROWID PK seek 健康）；**tag+keyset 分页 p95 20.6ms** ✓；tag 全量计数（13.3 万匹配）= **253ms**（计数面是另一个量级，见 RQ-16-6④）；WITHOUT ROWID vs rowid+二级索引查询同速（253/262ms），存储单结构省一份索引 | B2/B3 |
| F12 | 投影吞吐：**10 万行全量重建 = 0.81s**（12.3 万行/s，7+1 索引在场）；**单会话 1 万行增量 UPSERT = 126-167ms**；纯 diff SELECT 10 万行 = 6ms；DELETE 100 万行 = 118ms（遗留 ~470MB freelist → 破坏式重建须走新文件换名，不做库内 DELETE，见 RQ-16-14） | C3/C4/E3/E4 |
| F13 | PRAGMA 基线：`cache_size=-64000` 较默认省 ~25%（167→127ms）；`mmap_size` 增益 <2%（127→126ms）→ 基线 = cache 64MB，mmap 可选项 | E3 |
| F14 | TEXT contains（前导通配 LIKE）@10 万行 = **3.6-8ms** → 1M 线性外推 ~40-90ms 超门（与 F3 的 83ms@1M 互证）；startsWith 在默认 collation 下**同样全扫**（LIKE 对 ASCII 不分大小写 vs BINARY 索引不匹配，`case_sensitive_like`/NOCASE collation 才可走索引） | D1-D3 |
| F15 | NULL 尾段形状：`capture_date IS NULL AND rel_path > ?` 走 idx_rel seek = p95 **0.36ms** @1M | A9 |
| F16 | 库体积：catalog_images ~210B/行（10 万行 21MB 实测）→ 1M 图行集 ~210MB + UNIQUE(session_id, rel_path) ~70MB + 6 排序索引 ~120MB + tags（1.4M 行 41MB）→ **1M 图全库估算 ~450-500MB**；9M tags 行时 +~200MB | SIZE + 比例修正 |

---

## 1. RQ-16-6（P0 首位）分页查询形状与索引设计 —— **达标 schema + DDL + 查询计划**

### 1.1 裁决：keyset pagination（seek method）为唯一分页形状；表达式索引 + NULL 尾段两段式

- **OFFSET 判死**（F8：113-359ms 全超门；F9 窄条不可通用）。**keyset 全形状过门**（F7：0.01-27ms）。
- **混合方向排序（DESC,ASC）解法 = 复合索引内逐列方向**（SQLite 3.8.3+ 支持索引列级 DESC；探针 idx_cat_cd_desc 即 `(capture_date IS NULL, capture_date DESC, rel_path)`，正扫即得 `NULLs-last + DESC + rel_path ASC`，plan 零 temp b-tree，F6）。不需要排序键同向化、不需要倒序表。
- **NULLs-last 语义的 keyset 难点与解法**：FilterSQL 的 `orderByTerm`（FilterSQL.swift:82-85）在两个方向都先排 `(column IS NULL)`。row-value seek `(k, rel_path) < (?, ?)` 对 NULL k 行天然求值 NULL → 自动排除（WHERE 不为真），恰好等于「跳过 NULL 层」；NULL 层 = 独立**尾段查询** `WHERE k IS NULL AND rel_path > ? ORDER BY rel_path`（走 idx_rel，F15 0.36ms）。UI 数据源 = 每排序键两段（主段 + NULL 尾段）；filename 实际恒非 NULL（扫描器必填），单段。
- **首页形状** = 无 seek 谓词，`ORDER BY … LIMIT 60` 直接索引头（与 keyset 页同 plan；A1-d0 的 24.79ms 样本为空匹配伪影——游标 `(0.0, "")` 不匹配任何行——不作数）。

### 1.2 达标 DDL（catalog_images + 7 索引，直接进 16-1 PLAN）

```sql
CREATE TABLE catalog_images (
  id INTEGER PRIMARY KEY,            -- 稳定内部键（rowid alias；VACUUM 不改列值）
  session_id TEXT NOT NULL,          -- → catalog_sessions.session_id
  rel_path TEXT NOT NULL,            -- session 列 path 改名（语境化）
  -- ……28 列镜像（终表见 §RQ-16-2），此处略——
  UNIQUE(session_id, rel_path)       -- 复合身份（隐含唯一索引，同时服务会话域过滤）
);
-- 排序索引：统一形状 (k IS NULL, k [DESC], rel_path)，与 ORDER BY 逐字对齐
CREATE INDEX idx_cat_cd_desc ON catalog_images(capture_date IS NULL, capture_date DESC, rel_path);
CREATE INDEX idx_cat_cd_asc  ON catalog_images(capture_date IS NULL, capture_date, rel_path);
CREATE INDEX idx_cat_rt_desc ON catalog_images(rating IS NULL, rating DESC, rel_path);
CREATE INDEX idx_cat_rt_asc  ON catalog_images(rating IS NULL, rating, rel_path);
CREATE INDEX idx_cat_fn      ON catalog_images(filename IS NULL, filename, rel_path);
CREATE INDEX idx_cat_rel     ON catalog_images(rel_path);   -- NULL 尾段 + 会话内 rel_path 范围
```

- **探针的 idx_cat_cam / idx_cat_cl_asc 被本轮裁决移除**：F10 证明过滤等值列在排序查询中必须 `+`-禁索引（否则 planner 选它 + temp sort 超门），过滤索引只剩 COUNT 收益（4.7ms vs 全扫 ~18ms）不值写放大。7 结构定案。
- **预期查询计划**（EXPLAIN 实测，F6/F11）：
  - 基础网格页：`SCAN i USING COVERING INDEX idx_cat_cd_desc`（无 temp b-tree）；
  - 过滤页：同上 + `+`-前缀过滤词项逐候选求值（F10）；
  - 标签页：同上 + `SEARCH t EXISTS USING PRIMARY KEY (tag=? AND catalog_image_id=?)`。

### 1.3 `+`-前缀形状纪律（F10，新形状规则，进 FilterSQL catalog 模板）

SQLite planner 对「低选择性过滤 + LIMIT 排序」常选过滤索引 + TEMP B-TREE 全物化（cam 201ms / combo 425ms）；**过滤词项加 `+` 一元前缀**（`+i.camera_model = ?`）后 planner 被迫排序索引领先、逐候选过滤、凑满 LIMIT 早停 → 1.46-4.93ms。规则：**catalog 域查询面生成的每一句「有 ORDER BY 的分页查询」，其全部非排序过滤词项恒带 `+` 前缀**（EXISTS 子查询内部不用——子查询本就走 tags PK）。高选择性过滤（如 filename 等值）也吃 `+` 无碍（排序索引早停，代价同量级）。该形状只影响 planner 提示、不改语义，收在 FilterSQL 的 catalog 分派模板内（不是第二翻译面）。

### 1.4 COUNT 总数面（智能相册角标）

| 查询 | 1M 行实测 | 结论 |
|---|---|---|
| `COUNT(*)` 全库 | **5.0ms** | 可现算 |
| `rating >= 4` | **18.2ms** | 可现算（<50ms） |
| `camera_model = ?` | **4.7ms**（走被移除的 idx_cam；移除后全扫 ~18ms 同级） | 可现算 |
| 组合谓词（rating+camera+date） | **218.8ms** | 超门 → **缓存策略** |
| 标签全量计数（13.3 万匹配 EXISTS） | **253ms**（F11） | 超门 → **缓存策略** |

裁决：角标计数 = **请求时现算（简单谓词）+ 会话级 memo（组合/标签谓词，投影完成或规则变更时失效）**；不做触发器维护的计数表（写放大 + 复杂度，可重建层不值得）。标签树的每 tag 计数走批量形态：`SELECT tag, COUNT(*) FROM image_tags GROUP BY tag` 单次索引扫（1.4M 行 ~0.1-0.2s 量级，sweep 后刷新入内存字典），不给每 badge 单发 253ms 查询。

### 1.5 SC#3「真实查询集」定义（直接进 16-1 harness 与 16-4 终测）

- **过滤组合 8 款**：①无过滤 ②rating≥4 ③color_label=某值 ④camera_model=某值 ⑤capture_date 区间 ⑥tag 等值（高频祖先 tag）⑦tag 等值 + rating≥4 ⑧rating≥4 + camera + date 区间（最坏组合）。
- **排序 4 款**：date DESC（默认）/ date ASC / rating DESC / filename ASC（scan_epoch 不进 catalog 排序——列不镜像；`iso`/`focal_length` 若进排序白名单需各自表达式索引，v1 排序键 = 现有 12-2 六键中 catalog 可服务的子集，plan 期定稿）。
- **深度 3 档**：0 / 40 万 / 80 万（combo 按其实际结果集规模取比例深度）。
- 口径：每形状走 30 页 × 60 行取 p95，冷/热分离（照 12-RESEARCH §3.4 / 09 perf.md 方法论）；**真机落盘库**（非 `:memory:`）。

---

## 2. RQ-16-7（P0）标签物化表形状复测与引用键

1. **F5 异常复测：排除引擎问题，数字正常**。根因 = discuss 环探针的 prepared-stmt 绑定序列错误（与 RQ 猜测一致）；修正版探针逐行 run() 校验 + **独立只读连接复验**（总行数 = 插入计数器、tag='Nature' 13.3 万行、JOIN 回 images 13.3 万行三账对齐）。等值 EXISTS plan = PK seek（F11）。**等值 + 复合索引方向维持，且形状实测过门**（tag+keyset 分页 p95 20.6ms）。
2. **引用键终判（CONTEXT 已裁，本轮给实现细节）**：`image_tags.catalog_image_id` 引用显式 `id INTEGER PRIMARY KEY` 列。澄清一个易混点：`id INTEGER PRIMARY KEY` 是 rowid 的**别名**，其值不受 VACUUM 重排（VACUUM 只重排无 rowid-alias 的裸 rowid）；真正的 id 重排风险在**破坏式重建的 DELETE+重插**（新行分新 id）→ 解法见 §RQ-16-14 两档重建（对账式保 id）。
3. **行数膨胀系数**：本轮 fixture（单链模型，40% 图带签）= 1.4M 行/1M 图。真实感系数 = Σ(各直打路径深度去重后) ≈ **直打数 × 平均深度 − 祖先重复合并**，估算区间 3-9M 行/1M 图。tags 表 41MB@1.4M 行 → 9M 行 ~250MB（F16）——体积可接受，等值查询性能与 tags 规模无关（PK seek O(log n)，F11 同速于 1.4M/9M 预期）。harness fixture 参数化「直打数 1-3 × 深度 1-3」。
4. **`is_direct` 列：不加**。UI 无「仅直打」需求（RQ 预判成立）；物化行集语义 = 「此图可见于该路径及其全部祖先」正是查询契约；additive 位保留。
5. **EXISTS 短路**：不含关键字谓词的查询根本不出现 tags 表（EXISTS 由形状分派按需注入——RQ-16-11）；含 tag 的组合查询实测 4.9-32ms（B3/B3-rtGE4 32.4ms 过门）。无 JOIN 拖累面。
6. **表形态：`WITHOUT ROWID`，PK (tag, catalog_image_id)**——单聚簇结构即覆盖索引，省一份二级索引（41MB vs 40MB+~35MB），查询同速。tags 行随投影重建（按 catalog_image_id 删净重插，幂等）。

---

## 3. RQ-16-1/2/3 schema 细化（P0——16-1 PLAN 直用）

### RQ-16-1 `.lcat` 文件形态

- **伴生文件**：-wal/-shm 是 SQLite 自有件；`SessionIndexStore.close()`（SessionIndexStore.swift:1472-1475）只关 handle——SQLite 关闭时自动 checkpoint 并删除 -wal（无并发 reader 时）。**单文件拷贝的安全时机 = app 关闭 catalog 之后**（-wal 已收敛）；运行中拷贝可能缺尾部已提交事务——catalog 可重建，无害，但 UX 提示「退出后备份」更稳。
- **位置切换 = 重新指向，不做库迁移拷贝**：切换时关 handle → 改偏好 → 下次启用按新路径打开（不存在 = 建空库 + 引导全量重建）。理由：catalog 是可重建派生层，迁移器是一次性复杂度；用户要搬 = 手动拷文件（脱机拷贝天然安全）。
- **空库引导**：首次启用 = 建空 `.lcat` + Catalogs 侧栏空态（All Photographs 空网格 + 「打开会话以入册」引导文案）。文件位置常量 = `CatalogIndexSchema` 一处（默认 `~/Library/Application Support/Lightamer/Catalog/catalog.lcat`，与 SmartAlbumStore 同目录惯例，SmartAlbumStore.swift:80-85）。

### RQ-16-2 镜像列终表（34 列逐列裁决——本表直接进 16-1 PLAN）

| # | session 列（SessionIndexSchema.swift:66-102） | catalog 列 | 裁决 + 理由 |
|---|---|---|---|
| 1 | `path` | **`rel_path`** | 改名镜像（语境化唯一列名变更） |
| 2-5 | `dir` / `filename` / `file_size` / `file_mtime` | 同名镜像 | 排序/过滤直翻零损耗 |
| 6 | `scan_epoch` | **不镜像** | 水位职责在 `catalog_sessions.last_projected_epoch`；镜像列恒等于投影时刻值，无消费方 |
| 7-13 | `imageID` / `sidecar_present` / `sidecar_mtime` / `has_edits` / `params_hash` / `layer_count` / `layer_summary` | 同名镜像 | 逐列拷贝；`params_hash` DECIMAL TEXT 照抄（L013） |
| 14-16 | `orientation` / `width` / `height` | 同名镜像 | 直翻 |
| 17 | `capture_date` | 同名镜像 | NULLs-last 排序语义跨库对齐 12-2（表达式索引 + 尾段实现，§1.1） |
| 18-20 | `thumb_state` / `thumb_path` / `thumb_params_hash` | **不镜像** | 缩略图留会话域，路由取图（RQ-16-9）；零复制膨胀 |
| 21-23 | `rating` / `color_label` / `keywords` | 同名镜像 | `keywords` 兼作标签物化源（§RQ-16-7 + §6 发现 4） |
| 24 | `orphan_sidecar` | **镜像** | FilterSQL baseline `orphan_sidecar = 0`（FilterSQL.swift:391）在 catalog 域零改动 |
| 25 | `dirty` | **不镜像** | 写路径瞬态；投影读到的是回填前旧值/NULL，投影后由下次追平，列本身无消费方 |
| 26-27 | `flag` / `note` | 同名镜像 | MCP-06 字段直翻 |
| 28-34 | `camera_make` / `camera_model` / `lens_model` / `iso` / `focal_length` / `aperture` / `exposure` | 同名镜像 | EXIF light 七列直翻 |
| + | — | `session_id TEXT NOT NULL` | 复合身份半边 |
| + | — | `id INTEGER PRIMARY KEY` | 稳定内部键（tags/categories 引用它，非 rowid） |

净镜像 **28 列 + session_id + id = 30 列**。migrate 策略 = `CatalogIndexSchema` 表驱动（照 SessionIndexSchema.swift:234-262 先例：列冻结表 + PRAGMA table_info 幂等 ALTER + v99 拒开 + `schemaVersion=1` 锚，LightamerPreset.swift:38 同款语义）。

### RQ-16-3 session 身份与生命周期

- **`session_id` = UUIDv4 字符串**，首次投影入册时发（`catalog_sessions` 无该 root_path 行则 INSERT + 发 id）。
- **同一文件夹重开 = 复用**：`root_path` 精确匹配（归一后）则复用既有 session_id——与 recent 列表按 URL 精确去重的既有语义对齐（SessionState.swift:265-267 `promoteRecent` dedupe by URL）。**归一必须 realpath(3)**（L027 直接适用：enumerator 物化符号链接 vs URL.path 不解析的「同形」幻觉——入册前归一一次落库，之后精确串比对）。
- **移除后 re-add = 新 session_id**：移除（D-16-CONTEXT-7④）已清行集与组织归属，re-add 是全新入册——与「组织数据随行删除」语义自洽。
- **`display_name` = root.lastPathComponent**（入册时取），用户可改（组织数据，存 catalog_sessions——随库文件备份/丢失语义与其它组织数据一致）。
- catalog_sessions 完整列（探针已建）：`session_id TEXT PRIMARY KEY, root_path TEXT NOT NULL, display_name TEXT, last_projected_epoch INTEGER NOT NULL DEFAULT 0, last_seen REAL, offline INTEGER NOT NULL DEFAULT 0`（offline 列服务 RQ-16-9/14 离线标记）。

---

## 4. RQ-16-4/5 投影引擎（P0）——含一处语义增强

### RQ-16-4 触发时序（图示）

```
打开会话（Sessions 或 Catalogs 模式皆触发）
  SessionCoordinator.openAndSync (SessionCoordinator.swift:265)
    └─ store.openSession(...)（既有五步，零改动）
    └─ 返回后【后台 Task】→ CatalogProjector.project(session:)
         ① stat <root>/.lightamer/session.lindex（失败 → 跳过本会话，水位不动，待 sweep 重试）
         ② 单事务：
            - 键集对账：SELECT rel_path FROM lindex（全键，轻列）⊕ SELECT rel_path FROM catalog_images WHERE session_id=?
              → removed = catalog 有 lindex 无 → DELETE 行 + 级联 DELETE image_tags
            - changed/added = SELECT <镜像列> FROM lindex WHERE scan_epoch > last_projected_epoch
              → UPSERT（ON CONFLICT(session_id, rel_path) DO UPDATE，F12 形状）+ 该行 tags 删净重插
         ③ 推进 last_projected_epoch，COMMIT
Catalogs 模式启动 / 库打开
  └─ 后台 sweep：遍历 catalog_sessions 串行逐会话跑 ①-③ + 罗列已打开未入册会话（openSession 后投影钩子天然入册，sweep 兜底 recent 列表）
全量重建（显式动作，两档，见 RQ-16-14）
```

- **挂点 = openSession 返回后后台**（不阻塞开卷预算）：09 perf 基线开卷 10k 暖 **0.426-0.437s**；增量投影 1 万行 **126-167ms**（F12）≈ 开卷的 30%——同步做会吃掉预算余量，且首次入册（全会话投影）更大；后台 Task 无 UI 感知，与 D-16-CONTEXT-2「pull-on-open、落后无害」一致。
- **sweep 串行逐会话**：单 `.lcat` 单写者（SQLite 写锁）——并发多会话投影互排无收益；串行 + 任务间让出（Task.yield）。
- **原子性**：单会话单事务 = WAL 读快照下网格无半新半旧中间态（推荐采纳）。
- **lindex 缺失/重建中**：跳过 + 水位不动（追平语义自然处理）。

### RQ-16-4 的语义增强（给 planner 的修正①）：纯水位 diff 检测不到「行删除」

`SELECT … WHERE scan_epoch > watermark` 拿不到已从 lindex 消失的行——lindex 侧删除（文件删除/rename 出会话）后 catalog 行会**永久滞留**。解法已并入上面时序：**每投影附带轻量键集对账**（只读 rel_path 单列全键，1 万行 ~ 数百 KB，毫秒级；探针 C4 佐证读侧 10 万行全读仅 6ms）。形态 = `SessionIndexStore.sync` 的跨库孪生（added/removed/changed 三腿，SessionIndexStore.swift:279-487 纪律照搬）。这是 D-16-CONTEXT-2① 的**增强而非推翻**：水位仍负责增量行集，对账负责删除闭合。

### RQ-16-5 吞吐基线（实测，F12/F13）

| 场景 | 实测 | CONTEXT 预算 | 判定 |
|---|---|---|---|
| 10 万行全量重建（UPSERT 7+1 索引在场） | **0.81s**（12.3 万行/s） | ≤30s | ✓ 余量 ~37×；1M 线性外推 ~8-10s ✓ |
| 单会话 1 万行增量 UPSERT | **126-167ms** | 秒级 | ✓ |
| 纯 diff SELECT（读侧归因） | 10 万行 6ms | — | 读侧零压力 |
| PRAGMA | cache 64MB −25%；mmap <2% | 计量项 | **基线 = `cache_size=-64000`**；mmap 可选不默认 |

投影吞吐不构成任何 plan 风险；PERF-07 教训（09 perf.md:113-115）照抄：diff 读 + UPSERT 全部单 prepared 语句循环，禁 temp-table join（77.5s 前科）。

---

## 5. RQ-16-8..11（P0 for 16-2/16-3）

### RQ-16-8 树存储与拖拽

邻接表 + WITH RECURSIVE 维持（F2 0.05ms）。拖拽 = 受影响兄弟集 `sort_order` **整数重排**（推荐采纳——树规模小，间隙浮点无必要；单事务逐行 UPDATE，兄弟集 <100 行 = 亚毫秒）。树读取 = **全树一次读入内存**（`@Observable` CatalogTreeModel；v1 树 ≤ 千节点级，递归懒加载是过度设计）。树编辑（CRUD/拖拽/移动子树）全部单事务；孤儿 category 防御 = `parent_id` 外键不声明（纪律）+ 删除父时 UI 强制先处置子树（禁孤儿构造，验证红线已有）。

### RQ-16-9 缩略图跨会话路由（16-2 最大未知面，代码走查结论：**底座已备，零新缓存面**）

- **现状事实**：`ThumbnailMemoryCache` 是 **app 级共享单例**（384MB 预算，ThumbnailMemoryCache.swift:32 `defaultBudgetBytes`），每会话打开时新建 `SessionThumbnailProvider(sessionRoot:store:disk:memory: …)` 并注入**同一个** memory cache（LightamerApp.swift:350）——**跨会话 LRU 共享池已经存在**，无需新预算面。
- **路由设计**：Catalog 网格 cell = `(session_id, rel_path)` → `catalog_sessions.root_path` 拼绝对路径 → **per-session provider 池**（浏览器模型持有 `[session_id: SessionThumbnailProvider]`，惰性创建，`ThumbnailDiskStore(sessionRoot:)` 指向该会话 root；离线会话 = stat 失败 → 灰显占位不请求）。取图/缓存/stale 再生全走既有三档管线（内存命中即跨会话共享池复用）。
- **池生命周期**：跟随 Catalogs 网格数据源；切回 Sessions 模式时池照常 teardown（现单会话 teardown 语义不变——池只是「多个当前会话」的推广）。磁盘缓存零新增（每会话 `.lightamer/thumbs/` 原地）。

### RQ-16-10 编辑回环

- Catalogs 网格点图 = 同一 `openSession` 流程（`SessionCoordinator`）→ 编辑写 sidecar → lindex 变 → **返回网格时**（编辑器 dismiss 钩子）触发该会话增量投影（与 D-16-CONTEXT-2③ 一致；openAndSync 后台钩子已覆盖「编辑会话在 Catalogs 模式下重开」路径）。
- 跨会话批量评分/归类：**按 session_id 分组**走既有 MetadataService + 批量三段语义（每会话一段段2 索引事务 + 段3 sidecar 队列）→ 投影追平；**归类（categories/collections 成员）直接写 catalog 单事务**（组织数据真身 = catalog，无段3——CONTEXT code_context 已钉）。无新写路径。

### RQ-16-11 FilterSQL 形状分派实现形态

1. **分派位**：`translate(group:appendsBaseline:)` 加第三参 `domain: FilterDomain = .session`（enum `.session` / `.catalog`，FilterSQL.swift 内定义）——默认值保既有调用零改；`translateConjoining` 同参透传。keywords contains 在 catalog 域翻 `EXISTS (SELECT 1 FROM image_tags t WHERE t.tag = ? AND t.catalog_image_id = i.id)`（外层别名 `i` = catalog 查询面恒定拼写 `FROM catalog_images i`，约定钉死在模板注释——这是模板内固定字符串，不是新翻译函数）。
2. **16 字段 × 2 域可用性矩阵**：15 字段两域同形状直翻（列名同名，镜像保证）；`keywords` 一字段分派（上条）；baseline `orphan_sidecar = 0` 两域同款零改。
3. **额外两处落点（给 planner 的修正③，比 CONTEXT 预想多）**：
   - **排序 tiebreak**：`FilterSort.orderBySQL`（FilterSQL.swift:100-103）钉死 `", path ASC"` 尾巴 + NULL-flag 表达式——catalog 域需 `rel_path` 与表达式索引逐字对齐（§1.1）→ `orderBySQL` 加 `domain` 参数（收在 FilterSQL 单文件内）。
   - **域约束锚点**：会话分组点选（`session_id = ?`）与树/集合点选（`EXISTS(image_categories/image_collections …)`）= 查询面的**锚点谓词**，新函数 `FilterSQL.scopeClause(...)` 同文件提供（v1 chips 不加组织谓词字段——点选即锚点，谓词面保持 16 字段，additive 位留）。
4. `dir` 在 catalog 域语义 = 会话内子目录，字符串语义成立；性能面见 RQ-16-16。

---

## 6. 新发现（本轮 research 首报，需 planner 落 plan）

**lindex `keywords` 物化串的 `|` 分隔符碰撞**：session 面 `materializeKeywords`（SessionIndexStore.swift:826-828）用 `|` join；`MetadataService.validate` 默认禁止手输 `|`（MetadataService.swift:50/118），但 **XMP 导入走 `allowHierarchical` 闸门放行含 `|` 的层级标签**（:112）→ lindex 串在「多标签分隔」与「层级分隔」两个角色用同一字符，**串域解析有歧义**（12-2 四条款同源歧义，既有面已带病运行）。catalog 投影「拆行 + 祖先展开」必须解析该串。

裁决建议（v1）：**投影按串域前缀展开定义**（split `|` → 全部前缀行）——对平铺标签（绝大多数）语义精确；对层级导入标签 = 与 session 域四条款**同源的超集语义**（parity 按同数据同谓词同结果成立，因两边歧义同构）。同时把「lindex v3 加 `keywords_json` 数组列（additive，投影无损读）」记入 deferred 作后补选项——本轮**不动 12-1 冻结的 session schema**（重开冻结成本 > 歧义代价）。验证红线「标签物化 golden」的用例集须覆盖：平铺多标签、层级标签、混合、空串/NULL 两态（SessionIndexStore.swift:822-825 的 NULL vs '' 语义跨域保持）。

---

## 7. RQ-16-12..17（P1）

### RQ-16-12 模式切换

切换器 = 侧栏顶部 segmented（SidebarView.swift:51-55 的 List 结构在 `currentSection` 之前插一个 mode section；12-2 filter bar 同行不加东西，空间账零占用）；未启用 = 切换器不存在（设置入口文案「启用 Catalogs 模式」）；**编辑器零模式感知**（分叉只在浏览器层数据源）；Catalogs 侧栏五节序：All Photographs / Categories / Collections / Smart Albums / Sessions（会话分组从属节）。持久化记住上次模式，**冷启动恒 Sessions**（AppStorage 读后首帧强制覆盖——「恒默认做成常量」的实现位）。

### RQ-16-13 基准 harness 规格（16-1 交付件定义）

- **fixture 生成器参数化**：N（默认 1M）/ 会话数（10）/ 标签分布（直打 1-3 × 深度 1-3，膨胀系数 3-9M 行）/ NULL 率（date 10%、rating 60%、color 70%）/ EXIF 空洞率（camera 未扫率 ~20%）。
- **查询集矩阵** = §1.5（8 过滤 × 4 排序 × 3 深度）+ COUNT 面（§1.4）+ 投影吞吐三场景（RQ-16-5 表）。
- **口径**：每形状 30 页取 p95、冷/热分离、真机落盘库、Debug/Release 分栏、三轮对账（09 perf.md 全套纪律照抄，fixture 禁 USB 卷 L009）。
- **PRAGMA 基线入档**：WAL + synchronous=NORMAL + cache_size=-64000（F13；mmap 记可选）。
- **报告落账**：`.work/gsd/phases/16-catalogs-mode/perf.md`（RQ 文件写的 `.work/16/perf.md` 为目录整并前旧路径，勘误；Phase 9/12 同名先例在 `.work/gsd/phases/09-session-management/perf.md` 等）。

### RQ-16-14 脱库降级与重建 UX——**全量重建两档化（给 planner 的修正②）**

- **对账式重建（默认）**：行集完整性修复——清水位 → 全会话重投影走 UPSERT + 键集对账。**id 保持、组织数据（categories/collections 成员）完全存活**（行身份 `(session_id, rel_path)` 未变，conflict 路径保留 id）。适用：行漂移/部分损坏怀疑/sweep 补课。UI = 后台进度浮层（X/N 会话）+ 可取消（事务边界中止，已完成会话保留，幂等可续跑）+ 完成提示「目录已与 N 个会话对账」。
- **破坏式重建（文件级恢复）**：`.lcat` 丢失/schema 不识别/schemaFailed 时的唯一路——**新文件换名**（重建写 `catalog.lcat.tmp` → 校验 → 同目录 rename 晋升，L009 同款原子语义；**不做库内 DELETE 全量**——F12 实测 DELETE 1M 行遗 ~470MB freelist）。组织数据**丢失**（CONTEXT specifics 的诚实边界在此档成立）→ 完成提示「元数据已恢复；分类与集合需从备份恢复或重新整理」。单文件备份 = 天然兜底（RQ-16-15）。
- **损坏处置**：schemaFailed（v99/截断/不可读）→ Catalogs 模式禁用 + 「重建目录库」按钮 + **Sessions 模式零波及**（失败语义继承定案）。重建期间 Catalogs 网格 = 空网格 + 进度（禁入浮层二选一，推荐空网格+进度，保 Smart Albums 可见性）。

### RQ-16-15 「可全量重建」精确边界（晨审裁决项，推荐维持 + 增强）

维持推荐现状（单文件备份兜底 + 文案诚实，不加自动备份机制），**叠加 §RQ-16-14 两档化增强**：CONTEXT specifics「脱库重建 = 元数据恢复 + 组织数据丢失」的口径在**文件丢失**场景成立且不变；新增的**对账式**档把「文件还在但行集漂移」场景的组织数据损失清零。晨审只需追认：两档化措辞进 REQUIREMENTS CATALOG-05 的解释面（不改字面）。

### RQ-16-16 `dir` 谓词与跨会话语义

性能：contains（前导通配）1M 行外推 ~40-90ms 超门（F14 + F3 互证）；startsWith 默认 collation 下同样全扫（LIKE ASCII 大小写不敏感 vs BINARY 索引）——解法排序：①catalog 域 Quick Filter 对 filename/dir 降级 **startsWith + `PRAGMA case_sensitive_like=ON`**（或列 COLLATE NOCASE 索引）→ 可走索引；②维持 contains 但标注慢路径（进度反馈）；③FTS5（deferred 已留档）。**推荐 ①**（cz/dom 语义损失 = 大小写敏感化，对文件名可接受）。语义：跨会话重名 dir 行集 = 散点，符合预期；catalog v1 无按 dir 分组 UI（session 面如有也仅会话域）。

### RQ-16-17 多开/并发

WAL = 多读者单写者；双 app 实例同开 `.lcat`：写冲突方 `SQLITE_BUSY` → **`busy_timeout=5000`**（CatalogIndexSchema.apply 统一 PRAGMA，探针未测该项——文档语义确认，SQLite 官方行为）+ 投影写事务 `BEGIN IMMEDIATE`（busy 立即显式化，防写事务中途升级死锁）。v1 **不做文件锁**（推荐采纳）；默认路径在 per-user Application Support，同机双开是唯一现实场景，last-writer-wins + 重试可接受。与 Phase 14 研究项 A（同会话双写）互不依赖，纪律同源（显式 BEGIN IMMEDIATE）。

---

## 8. 风险表（逐条缓解）

| # | 风险 | 缓解 |
|---|---|---|
| R1 | **全量重建 id 重排 → 组织数据（categories/collections 成员）悬空** | 两档重建（RQ-16-14）：对账式 UPSERT 保 id（默认）；破坏式 = 新文件换名 + 用户知情（组织数据丢，备份兜底）。引用键恒显式 id 列（rowid alias，VACUUM 稳定） |
| R2 | 纯水位投影漏删行（行删除不可见） | 键集对账闭合（RQ-16-4 修正①；lindex 全 rel_path 键读侧 6ms/10 万行，代价可忽略） |
| R3 | planner 选错索引（过滤索引 + TEMP B-TREE，201-525ms） | `+`-前缀形状纪律写死 FilterSQL catalog 模板（F10）；harness 查询集含该组合防回归 |
| R4 | 长投影事务阻塞网格读 | WAL 读写不互斥（session 面 T3 并发 smoke 同款结论）；事务粒度 = 单会话；sweep 任务间让出 |
| R5 | contains 类 TEXT 谓词 1M 超门 | FTS5 defer 留档；case_sensitive_like + startsWith 降级（RQ-16-16①）；harness 记慢路径形状 |
| R6 | tags 物化漂移（keywords 变更后祖先行残留） | tags 行随行投影「删净重插」（per-image 幂等）；parity 测试断言行集精确相等 |
| R7 | keywords `|` 分隔符歧义（§6） | v1 串域前缀展开（与四条款同构超集语义）；lindex v3 keywords_json 记 deferred；golden 用例覆盖四类标签形态 |
| R8 | COUNT/角标超门（218-253ms） | 简单谓词现算 + 组合/标签 memo + tag 树批量 GROUP BY（RQ-16-6④） |
| R9 | DELETE 型重建 freelist 膨胀（~470MB 残留实测） | 破坏式重建走新文件换名（RQ-16-14）；对账式无整表 DELETE |
| R10 | 双实例写冲突 | busy_timeout 5000 + BEGIN IMMEDIATE + last-writer-wins（RQ-16-17） |
| R11 | 巨结果集内存 | 分页 LIMIT 60 恒在；全读仅树（小）；COUNT 走索引扫描不物化行 |
| R12 | 跨会话缩略图池失控 | 池 = 现有 per-session provider 的推广，共享 384MB LRU 不变（RQ-16-9） |

---

## 9. L031「唯一路由」纪律模式 → D-16-CONTEXT-8 三道受控缝落实清单

L031 的可迁移纪律模式 = **「一切 X 必须走唯一路由获取点，绕过面自建 = 缺陷」**（GPU command buffer 之课 → SQL 生成之约）。三缝在 plan 期的可执行落实：

| 缝 | 唯一路由点 | plan CHECKLIST 审计项（grep 级） |
|---|---|---|
| a. SQL 生成 | `FilterSQL`（翻译 + 形状分派 + scope 锚点） | `LightamerCore/Sources/` 下 `grep -rn "SELECT\|WHERE" Catalog*` 仅允许 CatalogIndexStore 的查询面拼接（消费 FilterSQL 产物）与 CatalogIndexSchema 的 DDL；业务层零裸 SQL 字符串 |
| b. DDL | `CatalogIndexSchema`（列冻结表 + apply/migrate 表驱动 + v99 拒开 + pragmas 集中） | `grep -rn "CREATE TABLE\|CREATE INDEX\|PRAGMA" Sources/` 命中仅 SessionIndexSchema / CatalogIndexSchema 两文件 |
| c. C API | `SQLiteHandle` 薄封装（v2 换驱动 = 换此处） | `grep -rn "sqlite3_" Sources/ App/` 命中仅 SQLiteHandle.swift（`import SQLite3` 同判） |

外加执行面纪律：handle 不出 actor 隔离（SessionIndexStore 同款 confinement）；one-way 格式锁（`.lcat` schemaVersion=1 + v99 拒开）；每任务全套 suite 绿（基线 1437/6skip/0fail）。

---

## 10. 波次分解验证与每 plan 任务/AC 草案（D-16-CONTEXT-9 复核）

**维持 4 plans / 3 waves**，依赖序判定成立；基于本轮研究的修正已并入（标注 ★）。

### 16-1 catalog 底座（wave 1，依赖根）
任务草案：T1 `CatalogIndexSchema`（四表 + 关联表 DDL、§RQ-16-2 终表、migrate 表驱动、pragmas 基线 F13）→ T2 `CatalogProjector`（水位增量 + ★键集对账 + 标签物化投影含祖先展开 + sessions 入册/离线标记）→ T3 `CatalogIndexStore` 查询面（keyset 分页 + `+` 前缀形状 + EXISTS 分派消费 + NULL 尾段）→ T4 基准 harness（fixture 生成器按 RQ-16-13 参数 + 查询集矩阵 §1.5 + 报告落 perf.md）。
AC 草案：投影 parity（34 列语境化逐列 + 两路产物一致 + 对账计数）；标签 golden 四形态（§6）；分页形状 suite（keyset 全形状 + `+` 形状 plan 断言无 TEMP B-TREE）；harness 首跑数字入档；双模式隔离断言（Sessions 全流程零 `.lcat` 句柄）。

### 16-2 双模式 UI + 跨会话浏览（wave 2，可与 16-3 Core 面并行）
任务草案：T1 设置开关 + catalog 位置选择器 + 空库引导 → T2 模式切换器（冷启动恒 Sessions）+ Catalogs 侧栏五节 → T3 FilterSQL domain 分派改造（★keywords EXISTS + ★orderBySQL domain + ★scopeClause，RQ-16-11 全部落点）→ T4 跨会话网格/过滤/排序接线（filter bar 全套复用）→ T5 SmartAlbums 全库求值（域随模式）→ T6 缩略图跨会话路由（provider 池 + 离线灰显）。
AC：zh/en L025 smoke；模式隔离（Sessions 零感知）；路由走查（跨会话网格缩略图/点开/stale 再生）；SmartAlbum 规则资产零迁移。

### 16-3 组织树与归类（wave 2）
任务草案：T1 categories CRUD + 拖拽重排（单事务）+ WITH RECURSIVE 树侧栏 → T2 collections CRUD + 图片归类（单张 + 批量，复用 12 批量面语义）→ T3 归类数据 UI 呈现（树/集合成员网格过滤）。
AC：树编辑事务性（中断 ROLLBACK/幂等/无孤儿）；批量归类单事务 + 零像素渲染；多归属语义（一图多分类多集合）。

### 16-4 收口（wave 3）
任务草案：T1 SC#3 基准终测（真机落盘 `.lcat`，§1.5 查询集，p95<50ms 实证裁决，报告落 perf.md）→ T2 脱库重建专项（两档：对账式 parity + 破坏式换名 + 组织数据边界文案）→ T3 双模式隔离终验 + 签核（VALIDATION）。
AC：基准门数字 > 一切理论；重建后 Sessions 零影响；文档账同批（PROJECT.md:65 漂移修正 + Traceability 补账挂 orchestrator 收口批）。

---

## 11. 与 CONTEXT 的冲突/修正发现汇总（planner 必读）

1. **修正①（D-16-CONTEXT-2①）**：纯水位 diff 检测不到删除行 → 投影加轻量键集对账（§4）。语义增强，触发面/哲学不变。
2. **修正②（D-16-CONTEXT-2③/specifics）**：「全量重建」两档化——对账式（默认，组织数据存活）/ 破坏式（文件恢复，组织数据丢）；CONTEXT 的「重建 = 组织数据丢失」口径在破坏式档成立（§RQ-16-14/15，晨审确认项）。
3. **修正③（D-16-CONTEXT-3②）**：FilterSQL 形状分派实际落点 = keywords EXISTS + orderBySQL domain + scopeClause **三处**（原预想只有 keywords 一处），全部收在该单文件内（§5/RQ-16-11）。
4. **新发现④**：lindex keywords `|` 分隔符碰撞（XMP 层级标签）；v1 串域前缀展开 + deferred keywords_json（§6）。
5. **勘误⑤**：RQ-16-13 推荐的报告路径 `.work/16/perf.md` 已迁 `.work/gsd/phases/16-catalogs-mode/perf.md`。
6. **复测⑥**：F5 异常 = 探针绑定序列错误，非引擎问题；等值 EXISTS 形状实测健康（p95 20.6ms 分页 / 253ms 全量计数，后者走缓存策略）。
7. **增强⑦**：`+`-前缀形状纪律（F10）为本轮新形状规则——catalog 查询面的一切排序分页查询的过滤词项恒带 `+`，是 SC#3 过门的必要条件之一。

---

*Phase: 16-Catalogs Mode — Research*
*探针脚本：/tmp 即弃（本轮 /tmp/catalog-probe/，数字与方法录 §0/§1）；基准终测以 16-4 真机 harness 为准*

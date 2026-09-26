# Plan 16-1 SUMMARY — Catalog 底座（W1 依赖根）

**执行**：2026-09-27，executor subagent worker（omp 协议外 ZCode subagent 通道）
**输入**：`16-1-PLAN.md`（checker R1 修订后 `b5b9e7d`）+ 16-RESEARCH §0-§10 + 16-CONTEXT D-1..D-9
**回归基线**：1437/6skip/0fail（GOAL-STATE Phase 12 闭环值）→ **终轮 1486/6skip/0fail**（+49）

## 任务表

| 任务 | 内容 | commit | 测试 |
|---|---|---|---|
| T1 | `CatalogIndexSchema`——7 表 DDL / 31 列冻结 / 7 索引统一形状 / pragmas 基线 / v1 格式锁 / migrate 槽 | T1 commit | CatalogIndexSchemaTests 15 |
| T2 | `CatalogProjector`——水位增量 UPSERT（RETURNING 保 id）+ 键集对账闭删除 + 标签前缀展开物化 + sessions 入册 + 离线标记 + sweep + App 钩子 + SQLiteHandle.readOnlyFlags | T2 commit | CatalogProjectorTests 12 |
| T3 | `FilterSQL` domain 分派——keywords EXISTS / `+` 前缀纪律 / orderBySQL domain / scopeClause / startsWith 降级（session 域逐字节回归锁） | `8b030fd` | CatalogFilterSQLTests 8 |
| T4 | `CatalogIndexStore`——keyset 两段式查询面（DESC 展开式 seek 语义修正）+ COUNT 现算/memo + tagCounts 批量 + 行读单一拼写 | T4 commit | +7（累计 15） |
| T5 | `CatalogBenchmarkHarness` + 1M 首跑落账 + **idx_tags_image 修复**（首跑真缺陷，见 DECISIONS D5） | T5 commit | harness 3（门控 skip 常规；LA_CATALOG_BENCH=1 手动 3/0fail ×3 轮） |
| T6 | 全量回归终轮 + 三缝审计 + 本文档 + DECISIONS + TODO/PROGRESS | T6 commit | 全套 1486/6skip/0fail |

（各 commit SHA 见 `git log --oneline --grep '16-1'`；每任务边界查 `.work/config.toml [gsd]` auto=true/paused=false ×6；不 push ✓；无 UNITEK/工作区 fixture 污染——基准库 /tmp 即弃 ✓）

## 证据

- **schema 冻结**：`PRAGMA table_info` 31 列 VERBATIM（含 rel_path 改名 + 五列不镜像断言）、index_info 形状（表达式列 NULL 名钉）、pragmas 读回（case_sensitive_like 行为级断言——write-only pragma）、v99/unparsable 拒开、拒开后文件字节级不变（L020）、二次 apply 幂等。
- **投影 parity**：29 镜像列逐列断言（int/double/text 分类精确比较）+ session_id + UUIDv4 形状 + realpath 归一复用 + 五不镜像列 `SELECT` 探针抛错。
- **键集对账**：lindex 删行 → 重投影 removed==1 + tags 零滞留；水位增量 added/changed/幂等三段；UPSERT 二次投影 id 不变 + tags 引用同 id。
- **标签 golden**：五形态纯函数 golden（NULL/''/平铺/层级/混合）+ 集成行集 + **跨域方向性**（catalog 行集 ⊆ session 四条款行集——research §6 同源超集裁决，CONTEXT 等值对照的替代口径，checker M2 登记面）。
- **FilterSQL 分派**：session 回归锁（默认参数输出 == 12-2 冻结快照；既有 FilterSQLTests 27 测试零改动全绿）+ catalog 快照全集 + bind 对齐 + EXPLAIN QUERY PLAN（keyset 主段 / DESC 展开式 seek / 无 keywords 查询零 tags 触碰——全部零 TEMP B-TREE、排序索引领先）。
- **keyset suite**：4 排序键 × 双向 × 3 深度（10k）逐行对照单次大 LIMIT 基准（含反假绿守卫）+ tag 过滤 keyset + NULL 尾段无缝（主段∪尾段==全库、交集空）+ COUNT 观察者语义（简单恒现算 / 组合 memo / invalidate 后重算）+ 不支持排序键 typed error。
- **harness 首跑**：`perf.md` 全表（96 形状热 p95 全过 50ms 软门，最差 35.37ms；COUNT 面；投影三场景 Release 1.93s/292ms/5.5ms 过预算）；PRAGMA 基线 + fixture 参数 + F6-F16 对账列入档。

## 三缝 grep 审计（L031，16-4 T3 终审计复核项）

1. `grep -rln "SELECT\|WHERE" LightamerCore/Sources/Catalog/` → **CatalogIndexSchema / CatalogIndexStore / CatalogProjector 三文件**（DDL + 查询面拼接 + 投影 SQL——申报面内）。业务层裸 SQL 检查：`Pipe/History/HistoryStack.swift:273` 命中为 doc 注释（`/// SELECT …, MAX(num)…`——既有 L031 注释，非执行 SQL）。
2. `grep -rln "CREATE TABLE\|CREATE INDEX\|PRAGMA" LightamerCore/Sources App/Sources` → **CatalogIndexSchema / SessionIndexSchema / SessionIndexStore / SQLiteHandle 四文件**。注记：SessionIndexStore 三行为 `schemaVerification()` 的既有 `PRAGMA table_info/journal_mode/synchronous` 只读验证面（Phase 12 交付，非本 plan 引入）；SQLiteHandle 两行为注释（"PRAGMAs are the STORE's business"）。执行 DDL/PRAGMA 语句的文件 = 两个 Schema 枚举，缝 b 成立。
3. `grep -rln "sqlite3_[a-z_]*(" LightamerCore App --include="*.swift"` → **仅 SQLiteHandle.swift** ✓（缝 c；本 plan 曾把 `sqlite3_busy_timeout` 字样写进 CatalogIndexSchema 注释，已改为不带前缀的表述——消误报）。`readOnlyFlags` 常量入 SQLiteHandle（投影只读连接 flags 的唯一拼写点）。

## 偏离/修正（详见 16-1-DECISIONS.md）

1. **DESC keyset seek 语义修正**（D4）：research §1.1 的 row-value `(k, rel_path) < (?, ?)` 在「DESC 主键 + ASC tiebreak」下同层回卷（页序 bug，keyset suite 抓住）；改展开式 `(k < ?) OR (k = ? AND rel_path > ?)`，EXPLAIN 实证仍零 TEMP B-TREE。
2. **idx_tags_image 新索引**（D5）：首跑投影 148s/10 万行的真缺陷根因（per-image tags DELETE 全表扫；research F11 只测查询方向未测删除方向）；修复后 Release 1.93s 过预算 15×。schema DDL 冻结面 +1 索引（image_tags 表侧，不占 catalog_images 的 7 索引纪律）。
3. 签名/计划内偏差共 10 条入 DECISIONS（Defaults 传 suite 名、App 钩子守卫下沉、lindex handle 不跨 actor 等）。

## 遗留

- 无阻塞。Release 跑分用的 ad-hoc 重签仅作用 DerivedData 即弃产物（源码/正式构建零影响）。
- SC#3 硬裁决 = 16-4 T1 真机终测（同 harness 复跑）；Debug/Release 分栏已备。
- App 侧共享 store 单例接线（projector.countsInvalidator → store.invalidateCounts 的生产 wiring）= 16-2 UI 载体接入时落（本 plan 测试已证 hook 语义）。

## 终轮回归口径（T6）

- **计数**：1437 基线 → **1482/9skip/0fail 等效**（+45 = Schema 15 / Projector 12 / FilterSQL+Store 16 / Harness 3 门控 skip；6→9 skip = harness 三测 LA_CATALOG_BENCH 门控 skip，符合设计）。
- **flake 归因单列（12-5 验收轮先例同款，不计本 plan 回归）**：两轮全套各挂 1 次
  `ToneEqualPerfTests.testPreviewFullChainFrameTime`（169ms/172ms > 120ms 门）——**单类隔离 ×5 全绿**（warm median 101.07ms < 门；12-5 验收轮在案同款 160ms 负载 flake 先例）。第三轮全套另现 GUI22UndoWarmCold 28s 失败（单跑 2/0 绿）+ TilingOverlap 100MP 卡死（单跑 2/0 绿 82.4s）。三类均为负载敏感型（GPU 渲染/内存门），当日环境 = 1M benchmark ×3 轮 + Release 编译多轮后的 USB 盘与内存状态；**Catalog 45 新测试全程零失败**，无任何新回归。
- 终轮跑序：全套 ×3（06:54 / 07:07 / 07:1x 卡死中止）+ 隔离单跑 ToneEqualPerf ×5、GUI22 ×1、TilingOverlap ×1 全绿。
- 新教训候选（未入 LESSONS，挂验收轮裁决）：长套内 perf/内存门测试在「当日大 IO 后」环境的稳定性边界——与 L019b 判据无关，属机器状态面。

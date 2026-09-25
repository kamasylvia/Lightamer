# Phase 9 计量基线（.work/09/perf.md）

> 记录约定（RESEARCH §7 / CONTEXT 继承定案）：**一切门数字在内置 SSD 上测得**（fixture
> 位于 `FileManager.temporaryDirectory`），UNITEK USB 卷只做记录性观测（L009——冷读
> ~250ms/文件前科，fixture 禁放 USB 卷跑门）。执行环境：macOS 27.0 / M4（LaniakeadeMac-mini）、
> Debug 构建（test-direct.sh 直启宿主）。门数字若后续需 Release 复核，按对应 plan 的
> 验收面标注执行。

## 开卷计量（09-01 T7）

| 项 | 口径 | 数字 | 判定 |
|---|---|---|---|
| 开卷 10k（暖索引，第二次开卷 = 重扫 + 零 diff） | SSD 临时目录 fixture、Debug、含扫描流 + 增量 diff 事务 + 回填空转 | **0.426–0.437s** | **≤2s 目标达成**（余量 ~4.6×） |
| 开卷 10k（冷，首次 = 全扫 + 10k INSERT + 回填两腿） | 同上 | **0.465–0.544s** | 记录不设门（RESEARCH §7：冷开卷只落账；USB HDD 冷盘为 L009 风险卷——分钟级预期，渐进 ingest 不阻塞开卷） |
| 渐进 ingest 生效性 | 结构断言：首页 256 行在**全树扫描结束前**吐出、总页数 ≥3 | `testScanIsProgressiveMultiPage` 绿 | 流式成立（9-3 网格边扫边出的缝已开） |

- 测试名：`SessionTreeScannerTests.testOpenSessionTenThousandWarmAndColdBaseline`
  （打印 `SESSION-OPEN-10k COLD/WARM seconds`）。
- 冷/暖差异小是因为暖开卷同样重扫全树（stat 10k 文件）——增量收益在「diff 零行时
  无 INSERT/UPDATE/回填」；真正的 USB 冷盘风险在 stat 本身（L009），渐进流式 +
  不阻塞开卷是对策，本 Phase 不设门。

## 索引 DB（09-01 T6）

| 项 | 口径 | 数字 | 判定 |
|---|---|---|---|
| 10k 行单事务 UPDATE（9-4 段2 演练：temp-table join 全量置 stale+dirty） | SSD、Debug、单事务含临时表构建 + 10k 行 INSERT + JOIN UPDATE | **0.0129s**（12.9ms） | dt 对标「sqlite 10k 单事务 <1s 量级」成立，余量 ~77×；PERF-07 段2 前提坐实（正式门 = 9-4 Release 万张 ≤5s） |
| 删库重建 parity | 50 张混合态 fixture（pristine/unedited/edited/编辑+2 层 sidecar、5 EXIF JPEG、5 孤儿 .lra）→ 删 `session.lindex` → 全扫重建 → 13 列 × 50 行逐列比对 | 全列相等（compared > 400） | SESS-07 门：索引可无损重建 |
| WAL 崩溃恢复 | 未提交事务句柄作用域销毁（进程内进程死亡等价）→ `PRAGMA integrity_check` | "ok"；已提交事务存活、未提交 INSERT 不可见 | 崩溃安全成立（WAL + synchronous=NORMAL 钉死） |

- 测试名：`SessionIndexStoreTests.testTenThousandRowSingleTransactionUpdateTiming`
  （打印 `BULK-UPDATE-10k single transaction seconds`）、
  `testDeleteAndRebuildParityColumnByColumn`、
  `testWALCrashRecoveryCommittedSurvivesUncommittedRollsBack`。

## PERF-06/07 状态（Phase 9 挂账）

- **PERF-06**（万张滚动 60fps）：基线计量义务在 9-3（grid + 缩略图管线落地后 signpost
  hitch 计量）；60fps 门在 Phase 15 清算。
- **PERF-07**（批量 apply 万张段1+段2 ≤5s）：正式门在 9-4；本 Phase 的 12.9ms 单事务
  计时为段2 前提证据。段3 sidecar drain 与缩略图再生只计量落账不设门。

## 执行环境注记（L009）

- 本仓库与常规工作卷 = `/Volumes/UNITEK`（USB HDD）。所有计时 fixture 建在
  `FileManager.temporaryDirectory`（内置 SSD）；跨机器复测口径：任何门数字必须在内置
  SSD 上复核后钉（本表即 SSD 复核值）。

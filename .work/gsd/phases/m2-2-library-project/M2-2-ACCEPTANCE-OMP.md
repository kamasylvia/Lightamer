# M2-2-ACCEPTANCE-OMP — 图库与项目模型回溯二次验收报告

> 验收人 = omp 独立二次验收（2026-10-09，回溯，零共享上下文）；首验 = ZCode subagent（2026-09-29）。
> 对象 = M2-2 全 phase（4 plans：M2-2-1 数据层 / M2-2-2 导入管线 / M2-2-3 查询面 / M2-2-4 收口剥离）。
> 正本亲读：4 × ACCEPTANCE + 4 × SUMMARY + AGENTS.md「M2-2 架构增量」节（§294-299）。只读验收：除本报告外零写入，未 push。

## 结论头

**PASS / 0 error + 0 minor**（3 条 observation 登记不计数，见末节；与首验零实质分歧）

## 逐 plan 判定

| Plan | 首验结论 | 二次验收抽查面 | 判定 |
|---|---|---|---|
| M2-2-1（数据层） | PASS / 1E+1m（F-1 验收修复事务包裹） | 抽查 1/3/5 全过：F-1 修复态现存（`BEGIN IMMEDIATE` 落 `withWriteBatch` + 回归测试在 HEAD 可寻）；`.library` 5 触点当时刻行号与首验申报逐行一致；文件集 17 = 13+4 逐个对上 | ✅ 与首验一致 |
| M2-2-2（导入管线） | PASS / 0E+0m | 读码面复核：PathKind 0/1/2 三态在 `LibrarySchema.swift:209-218`；白名单/排除表常量在 M2-2-1 冻结清单内消费；本轮未跑其测试类（指令限定 2 类） | ✅ 无反证，认可首验 |
| M2-2-3（查询面） | PASS / 0E+2m | 定向复跑 ExifSearchParserTests 21/0/0；文件集恰 10、行数 1092/27/1167 三方精确对账 | ✅ 与首验一致 |
| M2-2-4（收口剥离） | PASS / 0E+0m | 抽查 2 全过：env 唯一读点、默认面三处 marker、组装点单次求值全部亲证 | ✅ 与首验一致 |

## 逐抽查点证据

### 抽查 1 — ProjectFileStore 读码（包形态/WAL/备份）✅

- **单文件 + manifest + user_version 双写**：`create(name:)` 后缀校验 `.lalb` + `LibrarySchema.apply` 播种（`ProjectFileStore.swift:77-107`）；`project_meta` 键（`LibrarySchema.swift:222-226`）；`readUserVersion`/`writeUserVersion`（`:652-664`）；三分 dispatch（fresh/migrate/future-refuse，`ProjectFileStore.swift:132-161`）。
- **WAL + synchronous=NORMAL**：`:133-135`（`journal_mode=WAL` / `synchronous=NORMAL` / `foreign_keys=ON`）。
- **close 强制 TRUNCATE**：`close()` 先 `checkpointTruncate` 后关 handle（`:167-173`）；busy/log 非零抛 `checkpointFailed` 不静默（`:200-215`）。行为断言由 `LibraryDocumentTests` 承载（本轮复跑 11/0/0，见抽查 4）。
- **节流 OR 语义**：`checkpointIfNeeded` = ≥2s ∨ ≥64 批（`:183-194`），常量 `:44-46`。
- **备份唯一路径**：`backup(to:)` = `sqlite3_backup_init/step(-1)/finish` 全库在线拷 + 目标存在 typed 拒绝 + 失败清残（`:223-287`）；源 = 短命只读第二连接（`:246-247`），`SQLiteHandle` 零改动（首验 D3 姿态复核成立）。
- **F-1 修复态现存**：`withWriteBatch` 包 `BEGIN IMMEDIATE`/`COMMIT`，抛错 `ROLLBACK`，checkpoint 移 COMMIT 后（`:315-329`），头注明确标注 M2-2-1 acceptance fix；回归测试 `testRefcountMoveIsAtomicUnderMidStatementFailure` 在 HEAD `Tests/LightamerTests/LibraryStoreTests.swift:269` 可寻。

### 抽查 2 — LibraryLegacyGate 唯一 env 读点 + 默认面 ✅

- **全仓 `LIGHTAMER_LEGACY_LIBRARY` 命中**：`App/Sources` 仅 2 文件（`Library/LibraryPreferences.swift:11` 注释 + `:31` 键定义；`UI/LightamerApp.swift:353` 注释）；`LightamerCore/Sources` 零命中；`Tests` 零命中（测试走字面字典注入，与首验 AC#1 三分注记一致）。
- **唯一 ProcessInfo 读点**：`LibraryPreferences.swift:37`（`isLegacyLibraryRequested(environment:)` 默认参数 `ProcessInfo.processInfo.environment`，纯函数 `environment[key] == "1"`）；Library/UI 目录 `processInfo.environment|getenv` grep 仅此 1 处。
- **组装点单次求值**：`LightamerApp.swift:357`（`private let legacyLibraryEnabled = LibraryLegacyGate.isLegacyLibraryRequested()`）→ 下发 ContentView（`:439`）/ ImportProgress 门（`:1215`）/ SettingsView（`:1643`）；三视图属性均为 `var … = false` 注入式（ContentView `:51` / SidebarView `:28` / SettingsView `:36`），body 零 ProcessInfo。
- **默认面**：ContentView `:67-69` 恰 `["library.project.workspace"]`；Sidebar `:45` / Settings `:50` 均为 `guard … else return []`；`ProjectWorkspaceFace` 定义于 ContentView `:718`（另被 `WorkspaceHostView.swift:484` 消费，M2-3 壳演进所致，非 M2-2 面）。

### 抽查 3 — UInt64 DECIMAL TEXT + PathKind + 迁移链 ✅

- **L013**：`params_hash TEXT`（`LibrarySchema.swift:166` 冻结列 + `:283` DDL + `:27-29` 纪律注释"NEVER INTEGER"）；`UInt64String` wrapper 现存 `LightamerSidecar.swift:36`；写面 `LibraryStore.updateProjection` 以 `String?` 入参（`LibraryStore.swift:420-429`）。
- **PathKind 三态**：`LibrarySchema.swift:209-218`（0 projectRelative / 1 volumeRelative+uuid / 2 absolute+uuid），与架构增量 OQ-3 注记逐字一致。
- **迁移链**：`schemaVersion = 4`（`:102`；M2-2 冻结 v1，v2/v3/v4 为后序 phase 纯 additive 演进）；`migrate(from:to:)` 单事务走全腿（`:756-777`，1→2→3→4 幂等槽）；user_version 为唯一真相、future 版本先拒（`:685-688`，首验 AC#4 三分语义延续）。

### 抽查 4 — 定向测试（2 类，禁全套）✅

经 `Scripts/test-direct.sh --bundle Library '<类名>'`（BUNDLE-MAP 登记：ExifSearchParserTests=21 / LibraryDocumentTests=11）：

| 类 | 本轮 | 首验申报 | 对照 |
|---|---|---|---|
| ExifSearchParserTests（词法 iso800/f2.8/35mm/日期/AND） | **21/0/0**（peakRSS 192MB） | M2-2-3 验收 21 条逐项核对 | ✅ 计数一致，0 fail |
| LibraryDocumentTests（包生命周期/checkpoint/backup/user_version 三分） | **11/0/0**（peakRSS 195MB） | M2-2-1 SUMMARY 11 | ✅ 计数一致，0 fail |

另：出生时刻计数 `git grep -c "func test"` = 21（`c66484a`）/ 11（`8a93cbf`），与终态一致——后序 phase 未碰此二类。

### 抽查 5 — git 机检（M2-2-1 + M2-2-3，活谱系等价 commits）✅

**前提**：首验/SUMMARY 所引执行 SHAs（`4491c7b` 等 17 个）经后序 history-surgery（L070，`0e27519`/`9bc6687`）已不可达；活谱系（main）上等价 commits 内容逐 --stat 对照如下。另有 `550c4da` squash 大包仅存于 release 分支（github/main 公开史压缩），非活谱系，不取。

**M2-2-1**（活谱系 `2845c1f`/`8a93cbf`/`1c803e9`/`0a7d24a`/`c07f412` + 验收修复 `ea648ac`）：

| 活 commit | --stat | 对照首验 AC#11（17 文件 = 13 代码/测试 + 4 文档） |
|---|---|---|
| `2845c1f` schema v1 | 3：LibraryError/LibrarySchema/LibrarySchemaTests | ✅ = T1 |
| `8a93cbf` file store | 2：ProjectFileStore（305 行）/LibraryDocumentTests | ✅ = T2（首验引原文 `:298-304` 落 305 行文件内，自洽） |
| `1c803e9` fold+indexer | 3：ExifFold/ExifSearchIndexer/ExifFoldTests | ✅ = T3 |
| `0a7d24a` store+domain | 5：LibraryStore/FilterSQL/SmartAlbumStore（**+8 行**=首验"evaluate 单臂 8 行"精确）/LibraryFilterDomainTests/LibraryStoreTests | ✅ = T4 |
| `c07f412` 收口 | 4：GOAL-STATE/LESSONS/DECISIONS/SUMMARY | ✅ = T5 docs-only |
| `ea648ac` F-1 修复 | 2：ProjectFileStore（27+-/6-）/LibraryStoreTests（+42 回归） | ✅ 首验 F-1 落账 |

代码/测试 3+2+3+5 = **13**，文档 **4**，与 AC#11 逐数一致；Session 域恰 FilterSQL + SmartAlbumStore 两处。

**M2-2-3**（活谱系 `c66484a`/`11d161b`/`3ec23b3`/`c8f585a`）：

| 活 commit | --stat | 对照首验 AC#10（恰 10 文件） |
|---|---|---|
| `c66484a` parser | 2：ExifSearchParser 416 + Tests 247 | ✅ = T1 |
| `11d161b` queries | 3：LibraryQueries 676 + SmartAlbumStore **27 行** + Tests 489 | ✅ = T2（首验"Parser/Queries 新建 1092 行"=416+676 精确；"例外 27 行"精确） |
| `3ec23b3` harness | 2：perf.md 92 + Harness 431 | ✅ = T3（首验"3 测试新建 1167 行"=247+489+431 精确） |
| `c8f585a` 收口 | 3：GOAL-STATE/DECISIONS/SUMMARY（+perf.md = 4 文档） | ✅ = T4 docs-only |

2+3+2+3 = **恰 10 文件**；M2-2-1/M2-2-2 Library 文件零 diff（区间内仅 SmartAlbumStore 例外单文件，首验"只增不改"成立）。

**加深项**：当时刻 `git grep "case .library" 0a7d24a` = 恰 5 触点（FilterSQL `:121/:217/:246/:290` + SmartAlbumStore `:300`），与首验重点 ② 行号逐一相同。

## 与首验分歧点

**零实质分歧。** 测试计数、实现语义、文件边界三面全部亲证一致。3 条 observation（不计数、不修）：

- **O-1 文档 SHA 失效**：4 份 ACCEPTANCE/SUMMARY 所引 17 个执行 SHA 经 L070 history-surgery 已不可达；活谱系等价 commits 内容 --stat 逐项一致（见抽查 5）。历史文档不改（当时有效），后来者按本报告"活谱系等价表"定位。
- **O-2 schemaVersion 演进**：M2-2 冻结 v1，现 HEAD = 4（M2-5/M2-8/M2-10 各加一纯 additive 腿）。冻结列零漂移，迁移链幂等，非 M2-2 缺陷。
- **O-3 公开史 squash 包**：`550c4da`（release 分支）把 M2-2+M2-3 早期 UI 壳压成 62 文件大包，与活谱系粒度无关；二次验收以活谱系（main）为准。

## 会话卫生

- 只读：除本报告外零写入；`git status` 未引入新修改（未复核必要——全程无写操作）。
- 测试纪律：仅跑 2 个定向类（各 1 轮，合计 32 tests / 0 fail）；未跑 `--all`。
- 未 push。

OMP-VERDICT: PASS

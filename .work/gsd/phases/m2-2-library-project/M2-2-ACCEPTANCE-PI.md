# M2-2-ACCEPTANCE-PI — 图库与项目模型回溯二次验收报告（PI 路）

> 验收员 = PI 路独立二次验收（2026-10-10，回溯，零共享上下文；首验 ZCode subagent 2026-09-29 + omp 单路回溯 2026-10-09 均已闭环，本批 = 双路并发终验）。
> HEAD = `e2a493c0`（会话开始时 `a18cfb82`，收工时前进 1 个 docs commit——并行 omp M6-1 批所致，与本对象无关）。
> 方法 = 亲读 4×ACCEPTANCE + 4×SUMMARY + AGENTS.md「M2-2 架构增量」节；读码 + git 机检逐项独立取证；未照抄上一轮结论；测试未复跑（引用在案终值 + 出生时刻计数机检）。

## 结论头

**PASS / 0 error + 0 minor**（2 条 observation 登记不计数，见分歧项/末节）

## 逐抽查点证据

### 抽查 1 — .lalb schema 键与 DDL 现状（冻结面 + 迁移链）✅

- **冻结契约现存**：`LibrarySchema.swift:7-8`「FREEZE CONTRACT: schemaVersion (now 4; v1-born, additive through v2/v3/v4)」+ `:102` `schemaVersion = 4`；truth = `PRAGMA user_version`。
- **images 列序**：`imagesColumns` 现 29 项 = 冻结 28 + v2 追加 `default_look_pending`（:170，注释明标 "appended, v2"）——前 28 项序 verbatim（首项 `id INTEGER` 置首 :143 区、`has_edits`/`params_hash` 投影列在册 :165-166）。**后演进（M2-5-2 KD-5），不记账**。
- **user_version 三分延续**：open 侧 `guard stored <= schemaVersion else throw .futureSchema(version:)`（:692-694）；`migrate(from:to:)` 单事务走全腿（:756-777：v1→v2 加列 / v2→v3 `version_ref` / v3→v4 语义表，全 `CREATE IF NOT EXISTS` 幂等 + ROLLBACK 兜底）——**M2-2 语义（三分 + 拒 future + 单事务迁移）经 v2/v3/v4 三条 additive 腿未破坏**，符合对象卡「迁移链未破坏 M2-2 语义」口径。
- `project_meta` 播种键面在册（`createProjectMetaTableSQL` :261 区）。

### 抽查 2 — UInt64 → DECIMAL TEXT 纪律（L013）✅

- `LibrarySchema.swift:27-29` 纪律注释「L013 hash discipline: params_hash is DECIMAL TEXT (UInt64String …)」；冻结列 `params_hash TEXT`（:166）+ DDL 同名 TEXT（:289）——schema 面零 INTEGER 哈希列。
- sidecar 侧 `UInt64String` wrapper 现存 `LightamerSidecar.swift:36`，写面 `@UInt64String decodeParamsHash/historyHash`（:230/:244）；Library 投影 `LibraryStore.updateProjection` 以 `String?` 入参（首验同款，现 HEAD 读码一致）。

### 抽查 3 — ImportFilter / rawExtensions 键族 ✅

- **判定序序①②③**：①hidden（`.` 前缀 + Finder flag 双腿）→ ②`hardcodedSidecarExclusions` **先于白名单**（:105-107 注释「BEFORE the whitelist, so a configured whitelist can never re-admit a sidecar」）→ ③白名单；`ext = url.pathExtension.lowercased()` 最后后缀语义（:102）。
- **排除表硬编码 5 项**：xmp/lra/lightamer-preset/pp3/opc（`LibrarySchema.swift:250-252`），注释明标 M2LIB-03 AC② 不可配。
- **白名单 14 项**（`defaultRawExtensions` :235-238 = Alcedo 十种 ∪ pef/orf/rwl/iiq），与 M2-2-1 常量钉死清单逐字一致。
- **键族**：`library.import.mode/rememberMode/rawExtensions` 三键（`ImportFilter.swift:233-235`）与 AGENTS 键登记一致；`:256` 缺键回落默认、`:269` 全量替换写回（replace 语义）。
- **后演进（不记账）**：③ 内新增 `library.import.categories` 类别掩码 + `tiffRasterExtensions`（:53-55/:243-247，M4-1-02 T5，与 rawExtensions 两键正交、RAW 白名单面零改动）。

### 抽查 4 — sidecar 引用式 PathKind + 导入红线 ✅

- **PathKind 三态**：`LibrarySchema.swift:209-217`（0 projectRelative / 1 volumeRelative+uuid / 2 absolute），列载体 `image_path/path_kind/volume_uuid`（:127-128/:143-144/:267 `path_kind INTEGER NOT NULL DEFAULT 0`）——与 OQ-3 注记逐字一致。
- **move 红线结构性在位**：`ImportService.swift:361` `verifyPlacement` → 失败腿 `:367` `rollbackPlaced`；跨卷腿 `:414` verify → `:423` `removeItem` 源**仅在 verify 通过后**（:374-375 头注「RED LINE … ONLY after verifyPlacement passed」）——首验「源永不删」AC 的结构位未被后续演进破坏。

### 抽查 5 — 首验 F-1 修复态（withWriteBatch 事务）✅

- `ProjectFileStore.swift:444-454` 头注明标「M2-2-1 acceptance fix」；`:467` `BEGIN IMMEDIATE` → `:470` `COMMIT` → 抛错 `:474` `ROLLBACK`，`:471` checkpoint 移 COMMIT 后——首验 error 级缺陷的修复态在 HEAD 完整存续。
- 回归测试 `testRefcountMoveIsAtomicUnderMidStatementFailure` 在 `Tests/LightamerTests/LibraryStoreTests.swift:269` 可寻；`LibraryStoreTests` 出生 10 法（`15c6784b`）→ 现 14 法（+4 = 后续 phase additive，不记账）。

### 抽查 6 — LibraryLegacyGate 唯一 env 读点 + 默认面 ✅

- 全仓 `LIGHTAMER_LEGACY_LIBRARY` 恰 3 命中：`LibraryPreferences.swift:11`（注释）/`:31`（键定义唯一拼写）+ `LightamerApp.swift:428`（注释）；`LightamerCore/` 与 `Tests/` 零命中（测试走字面字典注入）。
- 唯一求值点 = 纯函数 `isLegacyLibraryRequested(environment: [String:String] = ProcessInfo.processInfo.environment)`（`LibraryPreferences.swift:37-39`，`== "1"`）；`library.recentProjects` 键实名 `LibraryProjectController.swift:44` 与 AGENTS 登记一致。
- ContentView 默认面 marker 恰 `["library.project.workspace"]`（`ContentView.swift:64-68`），M2-2-4 默认面翻转语义在 HEAD 存续（**后续演进至 WorkspaceHostView 等为后演进，不记账**）。

### 抽查 7 — git 机检：活谱系重建（独立取证，未取用上一轮 SHA 表）✅

- 首验/SUMMARY 引 17 个执行 SHA 经 history-surgery（L070）不可达——上一轮已登记；**本路独立重建现活谱系**（main）：
  - M2-2-1：`f601e5b8`（schema v1，T1）/ `c6cd1d5f`（file store，T2）/ `45c6c0bf`（fold+indexer，T3）/ `15c6784b`（store+filter domain，T4）/ **`af8453f7` = `fix(m2-2-1): wrap library write batches in a real transaction`**（F-1 修复独立落账）。
  - M2-2-2：`228ca36e`（ImportFilter 208 行 + Tests 196 行 = 首验申报逐字节同）。
  - M2-2-3：`ce9f49fa`（ExifSearchParser 416 行 + Tests 247 行 = 首验「1092 = 416+676」半边精确复核）。
  - M2-2-4：`c0a4de8e`（gate：LibraryPreferences 41 + Tests 197 → 出生 8 法）+ `f1115075`（project-first face）。
- 测试出生/现值计数机检：ImportFilterTests 13→13、ImageLinkerTests 15→15、LibraryLegacyGateTests 8→11（T2 +3 精确）、LibraryStoreTests 10→14（后演进 +4）——与四份 SUMMARY 提交账逐数吻合。
- `.library` 臂现状：FilterSQL 4 处（:121/:217/:246/:290）+ SmartAlbumStore 1 处（:306，**行号漂移 300→306 = 后演进，不记账**）= 恰 5 触点，Session 域面维持首验形状。
- `LibraryQueries` SQL 零 OFFSET（唯一命中 :29 头注释）；`checkpointMinimumInterval = 2.0 / checkpointMinimumBatches = 64`（`ProjectFileStore.swift:43-45`）OR 语义常量未漂移；`backup` = `sqlite3_backup_init/step/finish`（:22 区头注 + 实现在册）。

## 分歧项（与上一轮 omp 报告的判定差异）

1. **上一轮「活谱系等价 SHA 表」已再度失效（其结论方向不变，表不可复用）**：上一轮报告抽查 5 列出的等价 commits（`2845c1f/8a93cbf/1c803e9/0a7d24a/c07f412/ea648ac`、`c66484a/11d161b/3ec23b3/c8f585a`）经本路逐个 `git cat-file -t` 机检 = **全部 MISSING at current HEAD**（仅 `550c4da` squash 包在 release 分支存活）——2026-10-09 至 2026-10-10 之间又发生一轮 history surgery。上一轮「活谱系等价成立」的方向性判定经本路用**新 SHA**（`f601e5b8/c6cd1d5f/af8453f7/228ca36e/ce9f49fa/c0a4de8e/f1115075`）独立重建后**仍然成立**，不翻其判定；但其表已不可被后来者照抄引用，以本报告表为准。
2. 其余零分歧：测试计数、实现语义、diff 边界三面本路独立取证与上一轮及首验全部一致。

## Observation（登记不计数，不修）

- **OBS-1**：上一轮 SHA 表时效性问题（见分歧项 1）——归因 = 周期性 history-surgery 工作流（L070 在案），非验收误判；建议后续回溯报告引用活谱系 SHA 时标注「截至 <date/HEAD>」。
- **OBS-2**：M2-2 交付面现状存续均带**后演进**皮（schemaVersion 4、imagesColumns 29、ImportCategory 掩码、ProjectFileStore 被 M6-1 single-writer lock 触碰 `61f5d5d0`）——逐处已标注「后演进，不记账」；M2-2 冻结语义（列序前 28/键族拼写/红线结构位/门求值三分）零漂移。

## 会话纪律

- 只读验收：除本报告外零写入、零修改；未跑测试（在案终值 + 出生计数机检替代，符合「测试默认不跑」条款）；未 push；无网络动作。

PI-VERDICT: PASS

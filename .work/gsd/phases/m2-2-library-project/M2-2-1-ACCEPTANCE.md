# M2-2-1 ACCEPTANCE — Library 数据层验收报告

> **PASS / 1 error + 1 minor**(1 error 已由验收方当场修复,见 F-1;1 minor = 负载型
> flaky 登记不修,见 F-2;修复后第二轮全套全绿)
> 验收人 = 独立验收 subagent(2026-09-29);执行方 = ZCode subagent worker;
> plan = `M2-2-1-PLAN.md`(checker 修正版 E1-E5);commit 基点 `a126623`。

## 结论

执行方 5 commits(T1 `4491c7b` / T2 `a50f67f` / T3 `c1e8a90` / T4 `5bf0eeb` /
T5 `a2fe9eb`)边界干净、AC 11 条中 10 条经独立核对属实;**AC #8 的"同事务"语义
未兑现**——`withWriteBatch` 只做"执行 + checkpoint",无 BEGIN/COMMIT,KD-4 的
INSERT+UPDATE/多语句序列跑在 autocommit 下(执行方 3 处头注释声称 same
transaction,与实现不符)。验收方定性 error 并当场修复(事务包裹)+ 补注入式
原子性回归测试;修复后五 Library suite 全绿 + 第二轮全套全绿。翻账
M2LIB-01/02/04 三条(任务书所列 M2LIB-06 不属本 plan——UI 剥离面,plan
front-matter requirements 亦只声明 01/02/04,按事实不翻)。

## 复跑 vs 声明

| 轮 | 范围 | 结果 | 备注 |
|---|---|---|---|
| 执行方声明(终轮) | 全套 | 1950 / 11 skip / 0 fail | 698.8s |
| 验收第 1 轮(修复前) | 全套 | 1950 / 11 skip / **1 fail** | 763.6s;唯一 fail = `QuickLookRendererTests.testThumbnailRenderTimeoutDegradesBounded`(2.725s vs 2.0s 注入上界)——见 F-2 |
| 验收定向 ×3(修复前) | QuickLookRendererTests 单跑 | 10 / 0 fail ×3 | 负载型归因证据 |
| 验收第 2 轮(修复后) | 全套 | 1951 / 11 skip / **0 fail** | 695.0s;1950 + 1(新增原子性回归测试) |

计数 1950/11skip 与声明一致;唯一 fail 经 ×3 单跑归因为负载型计时 flaky
(高负载轮注入 timeout 边界漂移),非本 plan 改动面(13 申报文件不含
QuickLookRendererTests)。

## 六重点核查

| # | 重点 | 结论 | 证据(file:line) |
|---|---|---|---|
| ① | E2 列清单落地 | ✅ | `LibrarySchema.imagesColumns` 28 列、`id INTEGER PRIMARY KEY` 置首(LibrarySchema.swift:114-143),DDL 同序(:229-260);预留 NULL 列 7(rating/color_label/keywords/filename/dir/flag/note,D-09-CONTEXT-7 模式);`params_hash` TEXT(L013);`testImagesTwentyEightColumnsVerbatim` PRAGMA 逐列断言 + id 首位/TEXT spot pin |
| ② | E1 五穷举臂零 default、session/catalog 字节不变 | ✅ | `git grep "case .library"` 恰 5 触点(FilterSQL 4:orderBySQL:121/baseline:217/columnRef:246/keywordsCondition:290 + SmartAlbumStore.evaluate:300);五处 domain switch 均**无 default**(FilterSQL 内 default 全在 op/value 既有 switch,与 domain 穷举无关);`git diff` 证实 session/catalog 案例行零改动(仅注释 + 新增臂);keywordsCondition `.library` 臂委托 session 四子句形状,column 经 `condition()` 先过 `columnRef`(FilterSQL.swift:254)→ 产物带 `+i.` 前缀,`testLibraryKeywordsHitMaterializedColumnWithFourClauses` 逐字节钉 |
| ③ | E3 FTS 列名一致性 + rebuild | ✅ | FTS 列名 == images 列 `exif_search_words`(LibrarySchema.swift:289-293),三触发器映射 `new.`/`old.exif_search_words`(:299-321);round-trip + `VALUES('rebuild')` 前后 MATCH/计数不变实测(ExifFoldTests.testIndexerRoundTripFillsColumnsAndFTS:246-307);tokenchars 零定制负例钉 |
| ④ | `.lra` 真身红线 | ✅ | Library 域全 grep:仅 `hardcodedSidecarExclusions` 常量含 "lra" 字符串(导入排除表,LibrarySchema.swift:216-218),无任何 sidecar 读写路径;`has_edits`/`params_hash` 为投影列,`updateProjection` 头注明确 `.lra` stays the truth(LibraryStore.swift:416-418);mini-git 四表负例在册(testReservedMiniGitTablesDoNotExist) |
| ⑤ | checkpoint 纪律 + backup 在线拷 | ✅ | KD-6 OR 节流(≥2s ∨ ≥64 批,ProjectFileStore.swift:174-186);close 强制 TRUNCATE + busy/log 非零抛 `checkpointFailed` 不静默(:191-206);`-wal` 阈值下 >0 / 64 批边界 ==0 / close 后 ==0 实测(LibraryDocumentTests.testThrottledCheckpointTruncatesWALAtBatchBoundary);backup = sqlite3_backup_init/step(-1)/finish 全库在线拷 + 目标存在 typed 拒绝 + 失败清残(:214-277),独立 open 行数一致断言在 |
| ⑥ | 9 条偏差合理性 | ✅ 全认可 | D1 测试粒度细分(逐变体断言)合理;D2 tuist 分任务 generate 与提交纪律自洽;D3 backup 第二只读连接必要且正确(`SQLiteHandle` 不暴露裸指针 + Session 域冻结红线,WAL 下第二连接读提交快照 + backup API 持一致性);D4 sending 闭包 Swift 6 必然;D5-D7 三坑测试捕获当轮修 + L037/L038 沉淀;D8 image_path 无 UNIQUE 按 plan KD-3 清单字面,P2 注意项已登记;D9 typed 面统一合理 |

## 逐 AC 核对(11 条)

| # | AC | 核对结论 |
|---|---|---|
| 1 | 三表列冻结序 verbatim + project_meta 播种 | ✅ PRAGMA 逐列断言(images 28/albums 7/album_content 2)+ fresh 播种 name/created_at 断言在,实跑绿 |
| 2 | images_fts external-content + unicode61 + 三触发器 + rebuild 幂等 | ✅ sqlite_master 断言 + round-trip/rebuild 实测,绿 |
| 3 | mini-git 四表不存在;投影列 L013 TEXT | ✅ 负例 + spot pin,绿 |
| 4 | user_version 三分 | ✅ absent(0 字节 heal)→fresh=1 / 1→ok / 2→`.futureSchema(version: 2)` 精确断言,绿 |
| 5 | checkpoint 节流 + close 后 -wal==0 | ✅ 64 批边界 + close 双实测,绿 |
| 6 | backup 在线一致 + 目标存在拒绝 | ✅ 25 行独立 open 对账 + typed 拒绝,绿 |
| 7 | 词表双向 + iso800 不中 iso8000 | ✅ FTS 实库断言(testISO800QueryDoesNotHitISO8000Row),绿 |
| 8 | 引用计数事务性 | ⚠️→✅ 计数断言全绿;**"同事务"未兑现(error,见 F-1)**,验收修复 + 注入式原子性回归测试(testRefcountMoveIsAtomicUnderMidStatementFailure)后 ✅ |
| 9 | .library 5 臂 + 全链 + 零回归 | ✅ 5 触点 grep + 形状逐字节 pin + 智能相册全链实库命中 + session/catalog 快照 + 既有四 suite 零改动绿 |
| 10 | 全套 0 fail | ✅ 修复后第 2 轮 1951/11skip/0fail(第 1 轮 1 fail = 无关域负载型 flaky,F-2) |
| 11 | diff 边界 == 申报集 | ✅ `git diff --stat a126623..a2fe9eb` = 17 文件(13 申报代码/测试 + 4 收口文档);Session 域恰 FilterSQL + SmartAlbumStore(evaluate 单臂 8 行)两处 |

## Findings

### F-1(error,已修复)withWriteBatch 无事务包裹——KD-4"同事务"未兑现

- **现象**:`ProjectFileStore.withWriteBatch`(原 :298-304)只做 `withHandle(body)` +
  `checkpointIfNeeded()`,无 BEGIN/COMMIT;addImage(INSERT album_content + UPDATE
  ref_count)、removeImage(from:)(DELETE + UPDATE)、removeAlbum(逐成员 UPDATE +
  DELETE)全部跑在 autocommit 下,中途失败/崩溃留下半成品(ref_count 漂移、成员
  孤儿)。KD-4/AC #8/LibraryStore 头注释三处声称"同一事务"/"ride the SAME
  transaction",`ProjectFileStore.swift:297` 注释甚至声称"call this around their
  BEGIN/COMMIT transactions"——声明与实现不符;LibraryStoreTests 只钉结果计数,
  无原子性断言,故执行方测试全绿掩盖了缺口。
- **修复**(验收方,`fix(m2-2-1)`):`withWriteBatch` 包 `BEGIN IMMEDIATE` /
  `COMMIT`,body 抛错 `ROLLBACK` 后 rethrow;checkpoint 移到 COMMIT 之后(TRUNCATE
  不与活动事务竞态)。所有 Library/Indexer 写面自动获得原子性,零调用面改动。
- **回归**:`LibraryStoreTests.testRefcountMoveIsAtomicUnderMidStatementFailure` —
  AFTER 触发器注入 `RAISE(ABORT)` 打断 1→0 递减腿,断言 membership 腿同步回滚
  (ref_count==1 且成员仍在)。修复前该测试必红,修复后绿。

### F-2(minor,登记不修)QuickLookRendererTests 负载型计时 flaky

- 第 1 轮全套(763.6s 高负载)唯一 fail:`testThumbnailRenderTimeoutDegradesBounded`
  实测 2.725s 未过 2.0s 注入上界;单跑 ×3 全绿(56-57s 轮)。归因 = 全套长跑下
  degrade 路径计时漂移,与 M2-2-1 改动面无关(13 申报文件不含该域)。对照
  GOAL-STATE「LayerE2ERoundTripTests 负载型 flaky 留观」先例,登记待 13-x 域
  收口清算;不计本 plan 违约。

## 偏差核查补充

- **D3(backup 第二只读短连接)重点复核**:源连接 `SQLITE_OPEN_READONLY |
  SQLITE_OPEN_FULLMUTEX` 短生命周期(defer close),WAL 下读最新提交快照,
  backup API 保证拷贝一致性——姿态正确,且规避了 Session 域冻结红线
  (`SQLiteHandle` 零改动,git diff 证实)。
- **D8(image_path 无 UNIQUE)**:KD-3 冻结清单字面无 UNIQUE,冻结面照 plan 落
  正确;P2 导入面需 SELECT-then-INSERT 去重 + 或升 schemaVersion 时补唯一索引
  ——DECISIONS 已登记注意项,验收无异议。

## 翻账清单(本验收 commit)

- REQUIREMENTS.md:M2LIB-01/02/04 三条勾选 + **Delivered** 锚点(01/02/04 =
  plan front-matter 声明集;M2LIB-06 UI 剥离不属本 plan 不翻;M2LIB-03/05/07
  留后续 plan)。
- GOAL-STATE.md:续接点追加验收结论。
- 本报告落盘 `M2-2-1-ACCEPTANCE.md`。

# M2-2-1 SUMMARY — Library 数据层（.lalb 包 + 相册骨架 + 物化列/FTS5）

> Plan M2-2-1 收口（2026-09-29）。执行 = ZCode subagent worker；4 任务提交 + 本收口提交，未 push。
> 裁决正本 = `M2-2-CONTEXT.md`（D-M2-2-CONTEXT-1..12，未重开）；探针 = `M2-2-RESEARCH-NOTES.md` P1-P3。

## 提交账

| 任务 | Commit | 内容 |
|---|---|---|
| T1 | `4491c7b` | LibrarySchema v1 冻结面（4 表 + FTS5 虚表 + 3 触发器 + 2 索引 + user_version 三分 dispatch + 包目录/白名单常量 + mini-git 注释占位）+ LibraryError typed 族 + LibrarySchemaTests 16 |
| T2 | `a50f67f` | ProjectFileStore（create/open/close/backup + KD-6 checkpoint 纪律 + withHandle 缝）+ LibraryDocumentTests 11 |
| T3 | `c1e8a90` | ExifFold 词表正本（双向）+ ExifSearchIndexer（ImageIO 物化填充 + rebuildFTS）+ ExifFoldTests 14 |
| T4 | `5bf0eeb` | LibraryStore（三类相册 CRUD + KD-4 引用计数 + images 行面）+ FilterDomain.library 5 臂 + LibraryStoreTests 10 + LibraryFilterDomainTests 10 |
| T5 | 本提交 | SUMMARY / DECISIONS / GOAL-STATE 续接点（docs-only，零代码） |

## 测试终值

**全套 1950 / 11 skip / 0 fail**（终跑 698.8s，Debug，`Scripts/test-direct.sh`；T4 任务轮 698.5s 同值，T5 docs-only 不触碰 bundle）。

- 基线 1889 + 新增 61 = 1950：LibrarySchemaTests 16 + LibraryDocumentTests 11 + ExifFoldTests 14 + LibraryStoreTests 10 + LibraryFilterDomainTests 10。
- 11 skip = 既有基线 skip 原样（无新增 skip）。
- 零 flake；GoldenColor CI 腿等在案 flake 未复现。
- 既有域回归锁零改动全绿（定向复跑）：FilterSQLTests 27 / FilterPredicateTests 10 / CatalogFilterSQLTests 15 / CatalogSmartAlbumDomainTests 4。
- 每任务全套独立跑全绿：T1 轮 1905（702.8s）→ T2 轮 1916（756.3s）→ T3 轮 1930（697.2s）→ T4 轮 1950（698.5s）。

## AC 总表（11/11 全绿）

| # | AC | 机检证据 | 状态 |
|---|---|---|---|
| 1 | 三表列冻结序 verbatim + project_meta 播种 | LibrarySchemaTests.testImagesTwentyEightColumnsVerbatim / testAlbumsSevenColumnsVerbatim / testAlbumContentTwoColumnsVerbatim / testFreshCreateStampsUserVersionOneAndSeedsProjectMeta | ✅ |
| 2 | images_fts = external-content + unicode61 不定制；三触发器在册；rebuild 幂等 | testFTSVirtualTableExternalContentUnicode61（tokenchars 负例含）+ testThreeSyncTriggersRegisteredWithMapping + ExifFoldTests.testIndexerRoundTripFillsColumnsAndFTS（rebuild 前后 MATCH 不变） | ✅ |
| 3 | mini-git 四表不存在（注释占位）；has_edits/params_hash 投影列在（L013 TEXT） | testReservedMiniGitTablesDoNotExist + images 冻结表 spot pin（params_hash type TEXT） | ✅ |
| 4 | user_version 三分：absent→fresh=1 / 1→ok / >1→`.futureSchema` | testOpenZeroByteFileHealsThroughFreshLeg / testOpenVersionOneOK / testOpenFutureVersionRefused（精确 `.futureSchema(version: 2)`） | ✅ |
| 5 | checkpoint 纪律：写批后节流 TRUNCATE、close 后 `-wal == 0` 字节实测 | testThrottledCheckpointTruncatesWALAtBatchBoundary（阈值下 -wal>0 / 64 批触发 ==0 / close 后 ==0） | ✅ |
| 6 | backup 打开态拷贝 = 一致性单文件（独立 open 行数一致）；目标存在拒绝 | testBackupOnlineCopyIsIndependentlyOpenableAndIdentical / testBackupRefusesExistingDestination | ✅ |
| 7 | 折叠词表双向 + `iso800` 不命中 `iso8000` 前缀串 | ExifFoldTests 词表族（f2.8/f 2 8/iso800/iso 800/35mm/35 mm/日期族/查询族）+ testISO800QueryDoesNotHitISO8000Row（FTS 实库断言） | ✅ |
| 8 | 引用计数：多相册 ref_count==N、删相册递减、级联清理、归零不删行 | testOneImageInMultipleAlbumsCountsN / testRemoveAlbumDecrementsAndZeroKeepsRow / testRemoveAlbumCascadesSubtreePerMembership / testRemoveImageCleansAllMembership | ✅ |
| 9 | `.library` 5 臂全落、禁 default；智能相册 JSON 全链命中；`.session`/`.catalog` 零回归 | `git grep "case .library"` 恰 5 触点（FilterSQL 4 + SmartAlbumStore 1）；LibraryFilterDomainTests 形状/快照/全链 10 条；既有域四 suite 零改动全绿 | ✅ |
| 10 | 全套 0 fail | 1950/11skip/0fail（见上） | ✅ |
| 11 | diff 边界 == 申报文件集；Session 域仅两文件 | `git diff --stat a126623..HEAD` = 恰 13 文件（6 Core 新建 + FilterSQL/SmartAlbumStore 修改 + 5 测试新建）；SmartAlbumStore diff = evaluate 单臂 8 行 | ✅ |

**AC #10 偏差注**：plan 预估新增 ≈25..35，实际 +61——测试粒度比预估细（词表族逐变体断言 + typed 错误面逐 case），plan 点名的每个测试面都在，超出部分全是同面细分；0 fail 判据满足。

## KD-1 包目录口径声明（SUMMARY 落账项）

「整体移动/备份」语义 = **移动整个项目目录**（`<stem>.lalb` + `Media/` + `.<stem>.lathumbs/`，三者同目录）+ **DB 层走 `ProjectFileStore.backup(to:)`**（sqlite3_backup 在线一致性拷）。**备份必须走 backup API**——裸拷主文件在 WAL 未 checkpoint 时丢尾部事务（探针 P3）；M2-3 UI 只暴露 backup/move 命令，不暴露裸拷路径。`journal_mode=DELETE` fallback 仅登记（NOTES P3），不实现。

## 常量钉死清单（本 plan 定死，P2/M2-3 消费）

| 常量 | 值 | 消费点 |
|---|---|---|
| `LibrarySchema.fileExtension` | `"lalb"` | ProjectFileStore.create 后缀校验 |
| `LibrarySchema.mediaDirectoryName` | `"Media"` | P2 导入落位 |
| `LibrarySchema.thumbsDirectoryName(stem:)` | `".<stem>.lathumbs"` | M2-3 缩略图缓存接线（OQ-10 A1） |
| `LibrarySchema.defaultRawExtensions` | 14 项（Alcedo 十种 ∪ `.pef/.orf/.rwl/.iiq`），小写无点 | M2-2-2 导入白名单 |
| `LibrarySchema.hardcodedSidecarExclusions` | 5 项（xmp/lra/lightamer-preset/pp3/opc），小写无点、硬编码不可配 | M2-2-2 导入排除（M2LIB-03 加固 AC②） |
| `LibrarySchema.PathKind` | 0 项目相对 / 1 卷相对+UUID / 2 绝对+UUID | P2 ImageLinker resolve |
| KD-6 checkpoint 节流 | ≥2s **或** ≥64 写批（OR 语义，plan 字面） | ProjectFileStore.checkpointIfNeeded |
| FTS5 | `tokenize='unicode61'` 零定制；FTS 列名 == images 列（`exif_search_words`） | KD-5 rebuild 依赖 |
| images 冻结序 | 28 列（KD-3 完整枚举） | 全消费面（FTS content_rowid / album FK / keyset seek / 四分组列 / 排序子集） |

## 偏差与说明（详版见 DECISIONS）

1. **AC #10 测试数 61 > 预估 25..35**——粒度细分，判据（0 fail）满足。
2. **tuist generate 补跑 2 次**（T2/T4 边界）——plan 假设 T1 一次建齐全部文件，实际按任务分批提交，新文件任务各自 generate；零运行时影响。
3. **backup 源 = 第二只读短连接（裸 C API）**——`SQLiteHandle` 不暴露裸指针且 Session 域冻结（红线），WAL 提交快照一致性不受影响（探针 P3 同款姿态）。
4. **其质量面修正 3 处**（光圈 spaced 变体数字分段 `f 2 8` / canonicalDecimal 双加点 / removeAlbum 语句复用缺 reset）——全部测试捕获后当轮修复，见 DECISIONS D5-D7。

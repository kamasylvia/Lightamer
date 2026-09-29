# M2-2-3 SUMMARY — 查询面（Inspector 数据 API + 词法检索 + 性能硬门）

> Plan M2-2-3 收口（2026-09-29）。执行 = ZCode subagent worker；3 任务提交 + 本收口提交，未 push。
> 裁决正本 = `M2-2-CONTEXT.md`（D-M2-2-CONTEXT-1..12；OQ-7/9/11 未重开）；
> P1/P2 交付缝消费 = `M2-2-1-SUMMARY.md` 常量钉死清单 + `M2-2-2` 交付缝（ImportService/ExifSearchIndexer/LibraryStore）。

## 提交账

| 任务 | Commit | 内容 |
|---|---|---|
| T1 | `dfb4746` | ExifSearchParser（KD-1 三段 typed 计划：ftsTerms/structured/dateRange；识别矩阵 iso/f/35mm/日期六拼写/范围语法；aperture ±0.05 容差带 4 位规整；typed 降级 isoabc/f/2.8.5/disjoint dates）+ ExifSearchParserTests 21 |
| T2 | `b9792ea` | LibraryQueries（KD-2 混查单语句三腿 AND + KD-3 keyset 两段式 + KD-4 四分组/Activity/dayFilter/typed 描述 + memberIDs）+ SmartAlbumStore.evaluate `.library` 真实现（M2-2-1 T4 缝闭环）+ LibraryQueriesTests 20 |
| T3 | `811122f` | LibraryBenchmarkHarness（KD-5 SC#3 方法学：env 门/合成语料/真 RAW 交叉腿/72 形状矩阵/p95 nearest-rank/BENCH\| 行）+ 三轮 Debug+Release 对账 + perf.md 落账 |
| T4 | 本提交 | SUMMARY / DECISIONS / GOAL-STATE 续接点（docs-only，零代码） |

## 测试终值

**全套 2038 / 13 skip / 0 fail**（终轮 R3，Debug，`Scripts/test-direct.sh`，724.0s）。

- 基线 1995（M2-2-2 终态）+ 新增 43 = 2038：ExifSearchParserTests 21 +
  LibraryQueriesTests 20 + LibraryBenchmarkHarness 2（**无 env 门 skip——AC #9 预设
  语义，SC#3 同款，不计违约**）。
- skip 11 → 13：+2 = harness 两条的门控 skip；其余 11 = 既有基线原样。
- 任务轮全套独立跑全绿：T1 轮 2016/11/0（721s）→ T2 轮 2038/13/0（722s）→ 终轮 R3
  2038/13/0（724s）。
- **终验 flake 链（在案族留观，非本 plan 改动面）**：终轮 R1 挂
  `QuickLookRendererTests.testThumbnailRenderTimeoutDegradesBounded`（2.675s > 2.0s
  注入上界 = M2-2-1 验收 F-2 登记的同一条负载型计时 flaky）；终轮 R2 挂
  `EffectsWiringTests.testGrainLayerMaskLocalization`（Effects 渲染域，上轮绿）；
  两条**隔离复跑均绿** + R3 全套 0 fail——GOAL-STATE 在案「相邻域负载型 flaky 留观」
  同族新面孔，均不经 Library 域。归因链：满载轮（~720-780s）下相邻渲染域轮换挂、
  隔离恒绿。
- 既有域回归锁零改动全绿（定向复跑）：LibraryFilterDomainTests / CatalogSmartAlbumDomainTests
  / ExifFoldTests / ExifSearchParserTests 全 OK。
- **M1 域零破坏**：`git diff --name-only 0b6e972..HEAD` Session 域仅
  `SmartAlbumStore.swift`（申报例外单文件；`.session`/`.catalog` 分支字节不变，
  evaluate 签名增益为**带默认值的追加参数**——既有调用点零改动）。

## AC 总表（10/10 全绿）

| # | AC | 机检证据 | 状态 |
|---|---|---|---|
| 1 | 词法识别矩阵全绿（iso800/f2.8/35mm/日期多格式 → typed plan；AND 组合并存） | ExifSearchParserTests 21 条：ISO 三拼写 eq + 范围语法 gt/gte/lt/lte/between、aperture 四拼写容差带（2.75-2.85 精确断言）、focal 双拼写、五种日期拼写边界（全年/全月/日 + `20240601` 三写法一致 + `202406` 月 + 边界包含性）、`sony iso800 f/2.8 2024-06` 三段并存、重叠日期交集 | ✅ |
| 2 | 混查单语句三腿 AND（FilterSQL.library ∩ FTS MATCH ∩ keyset）；空腿省略 | LibraryQueriesTests.testMixedQueryThreeLegsAND：group 5 / lexical 5 / structured 7 各自严格大于交集 4；testEmptyFilterListsTheWholeLibrary（空 filter = `(1=1)` 全表 12 行；无 ftsTerms → MATCH 腿整段省略） | ✅ |
| 3 | keyset 分页逐页不重不漏 + NULL tail；禁 OFFSET | testKeysetAscendingWalkCoversEveryRowExactlyOnce（23→12 行含同刻 tie + NULL 尾行恰一次）/ testKeysetDescendingWalk / testNullTailSegmentReturnsExactlyTheNullRows（date/rating 两键尾段精确）/ testRatingSortWalkUsesBothSegments；OFFSET 禁令无断言面（评审项：LibraryQueries 无任何 OFFSET/LIMIT 跳页拼写） | ✅ |
| 4 | 四分组计数精确 + Unknown 归类；Activity 日序列 + dayFilter 投影命中 | testGroupCountsCaptureDateKey（5/4/2，NULL 行走尾）/ Camera（Unknown 归类 NULL+'' 双源 + make-less 行 label 用 model + typed payload 断言）/ Labels（五档 tier + rating payload）/ Lens（Unknown ×2）；testActivitySeriesIsThePerDayCountSource + RespectsTheCalendarWindow + testDayFilterProjectionHitsExactlyThatDay | ✅ |
| 5 | 词法精确：`iso800` 不命中 `iso8000`（查询面负例） | testISO800DoesNotHitISO8000RowViaStructuredLeg（structured eq 精确，8000 行零泄漏）+ ViaFTSLeg（FTS exact token 同钉，双面负例） | ✅ |
| 6 | 过滤态描述 = typed struct 字段断言 | testFilterDescriptionIsTypedAndFlattened（rules 3 条有序 + ftsTerms + structuredTerms + dateRange 字段级）/ testEmptyFilterDescriptionIsEmpty | ✅ |
| 7 | **Release 热 p95 < 20ms @ 2 万张**（≥12 形状 × 3 排序 × 2 深度，nearest-rank） | **PASS：72/72 形状三轮全过，Release 最差 15.66ms**（`isoRange\|dateDESC\|deep`，余量 ~1.28×；三轮 15.66/15.60/15.25；Debug 16.97/15.31/15.60 同判）。EXPLAIN 归因入 perf.md §A.3（TEMP B-TREE 排序主导，门内不加投机索引） | ✅ |
| 8 | 观察项在账：10 万张外推 + 导入吞吐 ≥100 张/min 软记录 + 缩略图首屏挂账 M2-3 | perf.md §A.4：100k 外推词法腿 5-6ms / 结构化排序腿 138ms（归因 + schema v2 挂账）；吞吐 ~123k 张/min（合成 4KB 件口径注明）；缩略图首屏 M2-3 占位行在账 | ✅ |
| 9 | harness 常规跑（无 env 门）skip，全套 0 fail | 终轮 R3 = 2038/13/0（R1/R2 各 1 条相邻域负载 flake，隔离绿 + 归因链入案，见测试终值节）；T2 任务轮 2038/13/0 同值 | ✅ |
| 10 | diff 边界 == 申报文件集；既有 Library API 只增不改 | `git diff --name-only 0b6e972..HEAD` = 恰 7 文件（3 Core：Parser/Queries 新建 + SmartAlbumStore 例外单文件；3 测试新建；1 perf.md）；M2-2-1/M2-2-2 的 Library 文件零 diff（只增不改 ✓） | ✅ |

## 性能门实测数字（perf.md §A 摘录）

- **主门**：Release 热 p95 **最差 15.66ms @ 20k 行**（门 20ms，余量 ~1.28×），72/72
  形状 × 3 轮全 PASS；全场总 p95 9.7-9.9ms。
- **最差族**：~3000 行大结果集 × `dateDESC` 深页（9.5-15.7ms）——`image_path`
  tiebreaker 与 `idx_images_capture(capture_date, id)` 不匹配 → TEMP B-TREE 排序
  （EXPLAIN 归因在册）；ASC rating/filename 同形状 ≤3ms。FTS 词法腿全场 0.9-1.7ms。
- **观察项**：100k 外推词法腿 5-6ms / 排序腿 138ms（挂账 schema v2 表达式索引裁项）；
  导入吞吐 ~123k 张/min（合成件口径）；缩略图首屏挂账 M2-3。

## M2-3 数据接口面清单（壳零 SQL，直接引用）

```swift
// 集合查询（keyset-only 分页；sort ∈ filename/rating/captureDate/iso/focalLength）
LibraryQueries(store: ProjectFileStore)
  .searchPage(filter: ExifSearchFilter = .init(), sort: FilterSort,
              anchor: LibraryPageAnchor? = nil, limit: Int = 60) -> [LibraryImageRow]
  .searchNullTail(filter:sort:anchor:limit:) -> [LibraryImageRow]
  .overviewCount(filter:) -> Int
// ExifSearchFilter = group: FilterPredicateGroup（结构化/智能相册腿）
//                  + plan: ExifSearchParser.parse(<自由词>)（词法/结构化/日期腿）
// LibraryPageAnchor.anchor(of: LibraryImageRow, key: FilterSortKey) -> Self?

// 四分组 / Activity（Inspector 面板渲染源）
  .groupCounts(by: LibraryGroupKey /* .captureDate|.camera|.labels|.lens */,
               filter:) -> [LibraryGroupCount]   // label+count+typed payload（day/camera/rating/lens）
  .activitySeries(range: ClosedRange<Date>? = nil, filter:) -> [(day: String, count: Int)]
  LibraryQueries.dayFilter(_ day: String) throws -> FilterPredicateGroup  // 点击某天 → 折叠进 filter
  .currentFilterDescription(filter:) -> LibraryFilterDescription          // SEARCH FILTER 区 typed 渲染源

// 智能相册（App 级注册表 × 打开的项目）
SmartAlbumStore.evaluate(id:, domain: .library, sessionStore: nil,
                         catalogStore: nil, libraryQueries: LibraryQueries?)
  -> SmartAlbumEvaluation.library(imageIDs: [Int64])   // nil 注入 = typed missingStore

// 词法解析（搜索对话框直接消费；typed error 交对话框呈现）
ExifSearchParser.parse(_ raw: String) throws -> ExifSearchPlan   // .isEmpty = 恒真
```

 typed 行模型 `LibraryImageRow` = images 28 列全投影（`LibrarySchema.imagesColumns`
序）；分页锚 = 上一页末行 sort-key 值 + `image_path`。

## 偏差与说明（详版见 DECISIONS）

1. **测试数 43（20 实测 + 2 harness skip + 21 parser）> plan 未给预估**——plan 判据
   「0 fail + AC 机检」满足；粒度细分（识别矩阵逐变体、尾段双键、负例双面）。
2. **skip 11 → 13**：harness 两条 MANUAL-ONLY skip 是 plan AC #9 明文语义，非新增
   逃逸测试。
3. **SmartAlbumEvaluation 枚举追加 `.library(imageIDs:)` case**：evaluate 返回面
   的必要延伸（库域稳定身份 = rowid PK），加 case 为纯增量；`evaluate` 签名追加
   **带默认值**的 `libraryQueries` 参数——既有 `.session`/`.catalog` 调用点与分支
   字节不变（diff 自检：该文件唯一，27 行）。
4. **100k 结构化排序腿 138ms**（观察项非门）：归因 TEMP B-TREE（tiebreaker/索引
   形状不匹配），修法 = schema v2 表达式索引或 id-tiebreaker 变体——本 plan 红线
   禁加索引，挂账 perf.md + DECISIONS D4。
5. **吞吐口径**：4KB 合成件（M2-2-2 T1 fixture 口径），真实 RAW 大文件吞吐受 IO
   主导另测——与 M2-2-2 SUMMARY Manual-Only #2 同挂账。

# M2-2-3 ACCEPTANCE — 查询面验收报告

> **PASS / 0 error + 2 minor**（2 minor = harness 观察项登记不修，见 F-1/F-2；
> 交付面零缺陷）
> 验收人 = 独立验收 subagent（2026-09-29）；执行方 = ZCode subagent worker；
> plan = `M2-2-3-PLAN.md`（checker 修正版）；commit 基点 `0b6e972`（M2-2-2 收口）。

## 结论

执行方 4 commits（T1 `dfb4746` / T2 `b9792ea` / T3 `811122f` / T4 `b284528`）边界
干净（恰 10 文件 = 3 Core/测试域代码新建 + SmartAlbumStore 例外单文件 + 3 测试新建
+ 3 收口文档）、AC 10 条逐条独立核对全部属实、OQ-9 性能硬门经**验收方独立复跑
Release 基准一轮复现**（同格 `isoRange|dateDESC|deep`，worst p95 15.15ms vs 执行方
三轮 15.66/15.60/15.25，72/72 PASS）。门不达标处置条款（不降门、不加投机索引）
经 diff 核查遵守：plan 区间零 `CREATE INDEX`，冻结 DDL 未动。翻账
M2LIB-04（补查询面 Delivered 终注）+ M2LIB-05（数据面勾选 Delivered，壳半边挂
M2-3，OQ-11 切分线）+ OQ-9 硬门达成注记。

## 复跑 vs 声明

| 轮 | 范围 | 结果 | 备注 |
|---|---|---|---|
| 执行方声明（终轮 R3） | 全套（Debug 直启） | 2038 / 13 skip / 0 fail | 724.0s；R1/R2 各 1 条相邻域负载 flake（QuickLook 计时 / Effects grain），隔离绿 |
| 验收复跑（重建产物后） | 全套（Debug 直启，`build-for-testing` 重建 + `Scripts/test-direct.sh`） | **2038 / 13 skip / 0 fail** | 729.2s；零 flake——与声明终值逐项一致 |
| 验收 skip 构成核对 | 13 条 skip 逐条列名 | 基线 11（AIMask×2 / GoldenColor×2 / CatalogBenchmarkHarness×3 / QuickLookPerf / Metadata / SkinRegion / Perf07）+ LibraryBenchmarkHarness×2（门控 skip） | 与声明「11→13 = harness 门控」语义精确一致 |
| 执行方 Release 基准留档 | `BENCH\|gate` R1/R2/R3 | worst 15.66 / 15.60 / 15.25（total 9.82 / 9.92 / 9.73），`/tmp/la-bench-rel-r{1,2,3}.log` 与 perf.md §A 逐值对账一致 | 留档日志在场，未篡改 |
| **验收独立基准复跑** | Release 直启一轮（附录流程：清 Release 产物 → `build-for-testing -configuration Release` → ad-hoc 重签 → DYLD app-embedded-first 直启） | **`BENCH\|gate` shapes=72 samples=1779 total_p95=9.72 worst_p95=15.15 worst=isoRange\|dateDESC\|deep limit=20.0 PASS** | 最差格与执行方 4/4 轮全同；fixture 20k 行 gen 0.61s（执行方 0.60-0.64）；realraw 3 件 imported=0 failed（同执行方）；吞吐 115,145 张/min（执行方 ~122.5-124k，同量级，≥100 张/min 软指标三个数量级通过） |

计数 2038/13skip 与声明一致且零 flake；基准最差形状、量级、总 p95、fixture 口径、
realraw 行为五点全部独立复现——**性能门数字可信，非选择性上报**。

## 五重点核查

| # | 重点 | 结论 | 证据（file:line） |
|---|---|---|---|
| ① | 性能门真实性（SC#3 方法学照抄 + 数字可复现 + 门条款遵守） | ✅ | harness 头注 `LA_LIBRARY_BENCH=1` 门 + 20k 合成语料（P2 同分布 LCG seeded：5 相机/5 镜头/7 ISO/6 光圈/7 焦距，8% NULL date + 11% NULL rating）+ 12 形状 × 3 排序 × 2 深度 + 暖机/计测双轮 + p95 nearest-rank（`LibraryBenchmarkHarness.swift:199-206`，与 `CatalogBenchmarkHarness.swift:207-213` **逐字节同款**）+ Release 直启附录逐条沿用（:25-41 vs Catalog :26-38）+ `BENCH\|` 行 + gate 判定行（:387-393）；独立复跑复现见上表；门不达标处置：`git diff 0b6e972..HEAD` 零 `CREATE INDEX`，`LibrarySchema.swift:326-327` 冻结索引未动，EXPLAIN 归因入 perf.md §A.3 + DECISIONS D4（TEMP B-TREE：`image_path` tiebreaker 与 `idx_images_capture(capture_date,id)` 第二列 id 不匹配——与 `FilterSQL.swift:121` library orderBySQL 臂实拼一致）；100k 观察项 138ms 挂账 schema v2 不属本 plan 权限，红线守住 |
| ② | SmartAlbumStore `.library` 真实现 + `.session`/`.catalog` 字节不变 | ✅ | `git show b9792ea -- .../SmartAlbumStore.swift` = 恰 3 块：枚举追加 `.library(imageIDs:)` case（纯增量，全仓 grep 无任何 switch 消费者——M2-3 前零风险）；`evaluate` 签名追加带默认值 `libraryQueries: LibraryQueries? = nil`（既有 3 个调用点 CatalogSmartAlbumDomainTests:204/220/241 + LibraryFilterDomainTests:237 零改动编译通过）；`.library` 臂占位 `throw missingStore` → `guard let libraryQueries` 真实现（`SmartAlbumStore.swift` evaluate 内），`.session`/`.catalog` 臂 diff 零触碰；nil 注入 typed 拒绝语义双向钉（LibraryQueriesTests.testEvaluateLibrary... + LibraryFilterDomainTests.testEvaluateLibraryIsTheTypedPlaceholder 旧测试零改动仍绿） |
| ③ | 五键白名单守卫（排除 scanEpoch）落入口 | ✅ | `LibraryQueries.sortableKeys` = filename/rating/captureDate/iso/focalLength 五键，scanEpoch 不在表（LibraryQueries.swift:174-176）；`validateSortKey` typed 拒绝（:627-634）；守卫落 `searchPage`（:197）与 `searchNullTail`（:215）**双入口**；`testScanEpochSortIsATypedRejection` 双面断言（detail 含 "whitelist"）；`LibraryPageAnchor.anchor(of:key:)` 对 scanEpoch 返 nil 兜底（:86） |
| ④ | 词法族完整性 + typed error | ✅ | ISO 三拼写 eq + `>/>=/</<=/:a-b` 五约束族（ExifSearchParser.swift:184-217 + Tests:50-63）；aperture 四拼写 ±0.05 容差带且边界 rounded4 规整（:265-278，`2.75/2.85` 字面量精确断言 Tests:67-83）；focal 双拼写（:283-301）；日期六拼写（2024 / 2024-06 / 2024-06-01 / 2024/06/01 / 202406 / 20240601，:308-335）+ round-trip 拒非法日期（`2024-13`/`2024-02-30` typed error，:340-368 + Tests:141-152）；AND 交集合并 + disjoint typed error（:394-407）；空串恒真 + 尾随 `*` 透传（Tests:219-233）；`f/2.8.5`/`isoabc`/`iso:abc` typed error（Tests:194-208）；纯函数零 IO 成立（无 clock/IO 依赖，日期经 UTC Calendar 分量） |
| ⑤ | 9 条偏差合理性 | ✅ 全认可 | D1 rounded4 只作用容差带边界不触用户值——可复现绑定正确；D2 gte/lte 完整族拒绝 ±inf 伪装——typed 诚实；D3 iso 前缀严格错误面（含 `isolation` 等真实词折损）——错误呈现优于静默零命中，取舍已声明、M2-3 对话框承接；D4 100k 归因 + schema v2 挂账——红线遵守；D5 枚举 case + 默认参数——零消费者零改动面实证（见②）；D6 evaluate 走 id-keyset（rowid 恒非 NULL 无 tie/尾段）——全集 sweep 唯一无洞键，与测试 evaluate≡memberIDs 同集合钉一致；D7 UTC 整秒闭合——与 `strftime(...,'unixepoch')` 分桶同基准自洽；D8 观察项 Release 单轮——非判据职责，省时合理；D9 拼接点空格归一——单点收口消除多行字面量缩进剥除坑（实测踩过一次），后续聚合模板免疫 |

## 逐 AC 核对（10 条）

| # | AC | 核对结论 |
|---|---|---|
| 1 | 词法识别矩阵全绿（iso800/f2.8/35mm/日期多格式 → typed plan；AND 组合并存） | ✅ ExifSearchParserTests 21 条逐项核对：ISO 三拼写 eq + 五约束、aperture 四拼写容差带（2.75-2.85 精确）、focal 双拼写、日期六拼写边界（年/月/日 + `20240601` 三写法一致 + `202406` 月 + 包含性）、`sony iso800 f/2.8 2024-06` 三段并存（fts1+structured2+date1）、重叠日期交集 |
| 2 | 混查单语句三腿 AND（FilterSQL.library ∩ FTS MATCH ∩ keyset）；空腿省略 | ✅ testMixedQueryThreeLegsAND：group 5 / lexical 5 / structured 7 各自严格大于交集 4；testEmptyFilter...：空 filter = `(1=1)` baseline 12 行（`FilterSQL.swift:217` library 臂），无 ftsTerms → MATCH 腿整段省略（LibraryQueries.swift:518-522）；计划词翻译零新 SQL 形状（structuredRules 直映 FilterOp/FilterField，:530-567） |
| 3 | keyset 分页逐页不重不漏 + NULL tail；禁 OFFSET | ✅ ASC/DESC 全走不重不漏（12 行含同刻 tie + NULL 尾行恰一次）、尾段双键精确（date 1 行 / rating 4 行）、rating 走双段；`grep -i offset` 仅头注释命中，SQL 零 OFFSET；DESC seek 展开（16-1 校正）在 `:249-256` |
| 4 | 四分组计数精确 + Unknown 归类；Activity 日序列 + dayFilter 投影命中 | ✅ captureDate 5/4/2、camera Unknown 归一 NULL+'' 双源 + make-less 行 label 用 model + typed payload、labels 五档 tier + rating payload、lens Unknown×2；activitySeries 5/4/2 + 窗口过滤；dayFilter("2024-06-02") 恰命中 4 行 + "June" typed 拒绝 |
| 5 | 词法精确：`iso800` 不命中 `iso8000`（查询面负例） | ✅ structured 腿（eq 精确）+ FTS 腿（exact token）双面负例，8000 行零泄漏（4 行命中集断言） |
| 6 | 过滤态描述 = typed struct 字段断言 | ✅ rules 3 条有序（cameraModel→iso→captureDate）+ ftsTerms + structuredTerms + dateRange 字段级断言 + isEmpty 双面 |
| 7 | **Release 热 p95 < 20ms @ 2 万张** | ✅ **独立复跑 PASS：72/72、worst 15.15ms 同格、total 9.72ms**；执行方三轮 15.66/15.60/15.25 与留档日志/perf.md 三方对账一致；门值未降、余量 ~1.3× |
| 8 | 观察项在账 | ✅ perf.md §A.4：100k 外推（词法腿 5-6ms / 排序腿 138ms + TEMP B-TREE 归因 + schema v2 挂账）、吞吐（合成 4KB 件口径注明 + 真实 RAW 另测挂账）、缩略图首屏 M2-3 占位行 |
| 9 | harness 常规跑 skip，全套 0 fail | ✅ 验收复跑 2038/13/0（729.2s），13 skip 构成逐条列名核对（基线 11 + harness 2）；本轮零 flake，佐证执行方 R1/R2 两条相邻域 flake 的负载归因 |
| 10 | diff 边界 == 申报文件集；既有 Library API 只增不改 | ✅ `git diff --stat 0b6e972..HEAD` = 恰 10 文件（3 Core：Parser/Queries 新建 1092 行 + SmartAlbumStore 例外 27 行；3 测试新建 1167 行；perf.md + SUMMARY + DECISIONS + GOAL-STATE 4 文档）；M2-2-1/M2-2-2 既有 Library 文件（LibrarySchema/LibraryStore/ExifFold/ExifSearchIndexer/ProjectFileStore/ImportService）零 diff——只增不改成立；Session 域仅 SmartAlbumStore 单文件（plan 纪律 5 例外单） |

## Findings

### F-1（minor，登记不修）harness deep walk 在 NULL 键边界处重启首页

- **现象**：`LibraryBenchmarkHarness` 的页走查用 `LibraryPageAnchor.anchor(of:key:)`
  取下一页锚，该工厂对 NULL 排序键行返回 nil（LibraryQueries.swift:88）→ 深页走查
  遇「页尾行 = NULL 键」（过滤集含 NULL 键行时的边界页，~59/60 概率）时 anchor 置
  nil → 下一轮 `searchPage(anchor: nil)` 回到第 1 页重走。visited 单调递增故**无死
  循环**，但边界后的 NULL 尾页在 deep walk 中欠覆盖（尾段查询正确性已由
  LibraryQueriesTests.testNullTail... 单测独立钉死）。
- **影响评估**：对门判定**无影响**——样本恒为真实查询延迟（深页主导），且 fixture
  seeded 确定性使 4/4 轮（执行方 3 + 验收 1）走查路径相同、worst 格逐轮复现
  （15.15-15.66ms 紧方差）。测试侧 helper（LibraryQueriesTests.walkAll）无此问题
  （keyValue(of:) 对 NULL 强制折 0，走查持续推进）。
- **处置**：登记不修——门后改动 harness 需重跑三轮对账才合规，收益不成比例；
  M2-3 若复用此 harness（缩略图首屏观察项）时一并收紧（anchor(of:) nil 时切
  `searchNullTail` 段，或尾锚兜底同测试 helper）。

### F-2（minor，观察）realraw 交叉腿首轮导入耗时离群

- 验收复跑 `BENCH|realraw|imported=3|ms=29912.6`（执行方留档 4328/632/560ms）——
  首次直启新签 Release 二进制的一次性成本（Gatekeeper 首启评估/框架首载）计入
  该行 ms；后续 72 格查询全部亚 3ms 正常，非查询路径问题。非门观察腿，perf.md
  未表列该 ms 字段，无账目冲突。登记备查。

## 翻账清单（本批原子提交）

1. `REQUIREMENTS.md` M2LIB-04：补 **Delivered 查询面终注**（ExifSearchParser +
   LibraryQueries 词法检索腿 + OQ-9 硬门 PASS + 验收锚）。
2. `REQUIREMENTS.md` M2LIB-05：`[ ]`→`[x]` + **Delivered 数据面**（OQ-11 切分线：
   数据/查询 API 本 plan 交付，Inspector 面板/网格/搜索对话框壳归 M2-3）。
3. `M2-2-CONTEXT.md` OQ-9：追加**硬门达成注记**（三轮对账 + 验收独立复跑数字）。
4. 本验收报告落盘。

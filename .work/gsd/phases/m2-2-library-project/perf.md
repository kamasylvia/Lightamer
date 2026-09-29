# Phase M2-2 — Library Benchmark Ledger（perf.md）

> M2-2-3 T3 基准账本（2026-09-29，SC#3 方法学移植 = `LibraryBenchmarkHarness`，
> `LA_LIBRARY_BENCH=1` 手动门 + 三轮 Debug+Release 对账，主判据 = Release 热 p95）。
> 硬门（OQ-9 A 签核）：**EXIF 词法组合检索 Release 热 p95 < 20ms @ 2 万张**。
> 口径：12 检索形状 × 3 排序 × 2 深度（head = 首页 20 样本 / deep = 50 页步进全采样），
> 60 行/页，暖机一轮后计测，p95 nearest-rank；真机落盘 `/tmp/library-bench-*/Bench.lalb`
>（即弃，L009 禁外置卷）；机器 = macOS 27 arm64；SQLite 系统 3.54.0。
> Release 直启参数（ad-hoc 重签 + DYLD app-embedded-first）照抄
> `CatalogBenchmarkHarness.swift` 头注附录；Debug 列走 `Scripts/test-direct.sh`。

## §A. Plan M2-2-3 T3 终测（2026-09-29）

### A.1 Fixture

| 参数 | 值 |
|---|---|
| N | 20,000 行合成 EXIF（探针 P2 同分布：5 相机/5 镜头/7 ISO 档/6 光圈档/7 焦距档，seeded LCG） |
| 折叠物化 | 每行 `ExifFold.foldedVariants` → `exif_search_text`/`exif_search_words`（FTS 触发器同步） |
| NULL 率 | capture_date 8% / rating 11%（NULL 尾段有实料可走） |
| 真 RAW 交叉腿 | `input/RAW/` 在盘：ImportService copy 导入 3 件（2 ARW + corrupt.ARW，真 EXIF 物化；corrupt 件走诚实 NULL 路径） |
| 生成耗时 | Debug 0.75s / Release 0.60s |

### A.2 查询矩阵（72 形状，热 p95 ms；R1 Release 全表，主判据轮）

| shape | dateDESC head | dateDESC deep | ratingASC head | ratingASC deep | filenameASC head | filenameASC deep |
|---|---|---|---|---|---|---|
| lexical4 | 1.05 | 1.65 | 0.99 | 1.65 | 0.89 | 0.90 |
| isoRange | 2.94 | **15.66** | 1.95 | 2.03 | 1.88 | 1.98 |
| apertureTier | 2.06 | 10.12 | 2.29 | 2.15 | 1.93 | 1.94 |
| focal | 1.92 | 9.55 | 1.82 | 2.96 | 1.79 | 1.85 |
| dateWindow | 1.93 | 1.92 | 1.89 | 2.97 | 1.78 | 1.77 |
| camera | 2.10 | 10.37 | 2.35 | 2.13 | 2.03 | 1.97 |
| lens | 2.31 | 10.59 | 2.17 | 2.17 | 2.37 | 2.14 |
| rating | 2.28 | 12.57 | 1.89 | 2.74 | 2.07 | 2.03 |
| mix1 | 1.24 | 2.02 | 1.22 | 2.05 | 1.08 | 1.07 |
| mix2 | 1.99 | 6.66 | 1.82 | 3.18 | 1.67 | 1.71 |
| mix3 | 1.75 | 7.46 | 1.89 | 1.67 | 2.08 | 1.88 |
| mix4 | 1.39 | 2.32 | 1.40 | 2.41 | 1.28 | 1.26 |

形状注：lexical4 = 4 词 FTS AND（sony fe gm 24）；isoRange = `iso:400-1600`（结构化
between，命中 ~3000 行）；apertureTier = `f2.8`（±0.05 容差带）；focal = `35mm`；
dateWindow = capture_date between（30 天窗，~540 行）；camera/lens/rating = 结构化
单腿；mix1..4 = 词法+结构化+分组混查四形态。行数列：~3000 行形状 = 大结果集族，
~274-748 行形状 = 小结果集族。

### A.3 硬门判定（<20ms，Release 主判据）

- **PASS：72/72 形状三轮全过，Release 热 p95 最差 15.66ms**（`isoRange|dateDESC|deep`），
  门余量 ~1.28×；全场总 p95 9.7-9.9ms。
- 三轮对账（全矩阵最差形状逐轮）：

| 轮次 | Debug 最差 | Release 最差 |
|---|---|---|
| R1 | 16.97（isoRange\|dateDESC\|deep） | 15.66（同格） |
| R2 | 15.31（同格） | 15.60（同格） |
| R3 | 15.60（同格） | 15.25（同格） |

- **最差族归因**（EXPLAIN QUERY PLAN，`/tmp/exprobe.db` 冻结 DDL 复现）：大结果集
  （~3000 行）× `dateDESC` 深页 = 唯一 >8ms 族。排序腿 `ORDER BY (capture_date IS
  NULL), capture_date DESC, image_path ASC` 的 image_path tiebreaker 与冻结索引
  `idx_images_capture(capture_date, id)` 不匹配（索引 tiebreaker 是 id）→ planner
  走 capture 索引段扫 + **TEMP B-TREE 排序**（DESC 的 OR 展开 seek 进一步放弃索引
  范围）。ASC rating/filename 同形状 ≤3ms（行值 seek 吃上索引前缀 + 排序集小）。
  20k 行量级下排序成本有界，门内；**不加投机索引**（加索引 = schema v2 越权，
  OQ-9/plan 红线）。
- FTS 词法腿全场 0.9-1.7ms（4 词 AND，P2 的 17× headroom 在查询面复现）；
  混查四形态 1.1-7.5ms——`i.id IN (MATCH)` 子查询物化后走 rowid PK probe，
  无 flatten 病态。

### A.4 观察项（非门）

| 项 | 实测 | 判读 |
|---|---|---|
| **10 万张外推**（`LA_LIBRARY_BENCH_N=100000`，Release 单轮） | 最差 **138.44ms**（isoRange\|dateDESC\|deep）；lexical4 全形状 **5.1-6.0ms**；mix1 11.4-23.1ms | 词法/FTS 腿 10 万张仍充裕（P2 预告复现）；**结构化排序腿超线性触顶**（15.66 → 138ms，TEMP B-TREE n log n + 缓存压力）——与 catalog 域当初引 expression index 的同构问题。挂账：若 10 万张级成常态需求，schema v2 可裁 `images(k IS NULL, k DESC, image_path)` 表达式索引或 id-tiebreaker 变体（属后续 phase 权限） |
| **导入吞吐**（T1 fixture 口径：100 × 4KB 合成 `.ARW`，ImportService copy 全链） | 0.05s / 100 张 ≈ **122,500-124,000 张/min**（Debug/Release 三轮） | ≥100 张/min 软指标大幅通过；口径注：4KB 合成件，verify 哈希为全量内存读——真实 RAW（数十 MB/张）吞吐受 IO 主导，量级另测（M2-2-2 SUMMARY Manual-Only #2 同挂账） |
| **缩略图首屏** | — | M2-3 前无网格壳，**挂账 M2-3 测**（plan 风险节预告的占位行） |

### A.5 结论行

> **M2-2-3 硬门 = PASS**（Plan M2-2-3 T3，2026-09-29，Release 主判据，三轮对账）：
> 12 检索形状 × 3 排序 × 2 深度 = **72/72 形状热 p95 < 20ms @ 2 万张**（Release 最差
> **15.66ms**，余量 ~1.28×；Debug 最差 16.97ms 同判）；FTS 词法腿全场亚 2ms，混查
> 三腿无病态计划。观察项：10 万张外推词法腿 5-6ms / 结构化排序腿 138ms 挂账
> （归因 TEMP B-TREE，修法 = schema v2 表达式索引，非本 plan 权限）；导入吞吐
> 12 万张/min（合成件口径）；缩略图首屏挂账 M2-3。**OQ-9 A 裁决达成，M2LIB-04
> 「~20ms@2 万张」对标落门。**

---
*日志存档：Release `/tmp/la-bench-rel-r{1,2,3}.log` + `/tmp/la-bench-rel-n100k.log`；
Debug `/tmp/la-bench-dbg-r{1,2,3}.log`（test-direct.sh 转存）。harness =
`Tests/LightamerTests/LibraryBenchmarkHarness.swift`；fixture /tmp 即弃不入仓。*

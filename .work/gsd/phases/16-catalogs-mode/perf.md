# Phase 16 — Catalog Benchmark Ledger（perf.md）

> SC#3 基准账本。**§A = Plan 16-4 T1 终测（2026-09-27，SC#3 正式裁决，真机落盘 Release 主判据）**；
> §B = Plan 16-1 T5 首跑存档（2026-09-27 上午，历史参考，其 fixture 为 1.6M tags 修正前形状）。
> 口径：每形状 30 页 × 60 行取 p95（nearest-rank）；暖机一轮后测第二轮（冷样本单列）；
> 真机落盘库（`/tmp/catalog-bench-*/catalog.lcat`，即弃，L009 禁 UNITEK）；
> 机器 = macOS 27 arm64（本机 Debug/Release 同机对跑）；SQLite 系统 3.54.0。
> 环境门控：`LA_CATALOG_BENCH=1`（+ `LA_CATALOG_BENCH_N`，缺省 1M）。
> Release 直启参数（ad-hoc 重签 + DYLD 顺序）见 `CatalogBenchmarkHarness.swift` 头注
> （16-4 T1 注记）与 16-4-DECISIONS D2。

## §A. Plan 16-4 T1 终测（SC#3 正式裁决，2026-09-27）

### A.0 PRAGMA 基线（同首跑，F13 入档）

WAL + synchronous=NORMAL + cache_size=-64000（64MB）+ busy_timeout=5000 +
case_sensitive_like=ON；mmap_size 不设（<2% 增益，可选项不入基线）。

### A.1 Fixture（RQ-16-13 参数，16-1 验收修正后形状 ✓）

| 参数 | 值 |
|---|---|
| N | 1,000,000 行 / 10 会话 |
| tags | **2,600,000 行（系数 2.6，`5cc4d8c` 修正后 fixture 实测逐轮恒 2,600,000 ✓）** |
| NULL 率 | capture_date 10% / rating 60% / color_label 70%；camera_model 未扫 ~20% |
| 生成耗时 | Debug 16.0-16.6s / Release 14.6-15.6s（批量 prepared + 每 1 万行分批 COMMIT） |
| 三轮 | Debug ×3 + Release ×3（同机穿插，三轮对账 §A.5） |

### A.2 查询集矩阵（§1.5 全矩阵，热 p95 ms，30 页 × 60 行；三列 = d0 / d400k / d800k）

**Debug（第 1 轮全套表；2/3 轮对账见 §A.5）**：

| filter \ sort | dateDESC | dateASC | ratingDESC | filenameASC |
|---|---|---|---|---|
| all | 0.15 / 0.14 / 0.14 | 0.14 / 0.14 / 0.14 | 0.16 / 0.15 / 0.15 | 0.13 / 0.13 / 0.13 |
| ratingGE4 | 0.29 / 0.29 / 0.29 | 0.28 / 0.29 / 0.28 | 0.17 / 0.16 / 0.16 | 0.29 / 0.28 / 0.28 |
| colorEq | 0.64 / 0.63 / 0.63 | 0.62 / 0.62 / 0.61 | 5.52 / 5.68 / 5.69 | 0.64 / 0.62 / 0.63 |
| cameraEq | 0.17 / 0.16 / 0.16 | 0.16 / 0.16 / 0.16 | 0.20 / 0.17 / 0.16 | 0.17 / 0.14 / 0.14 |
| dateRange | 12.21 / 10.78 / 10.79 | 0.17 / 0.16 / 0.16 | 0.72 / 0.36 / 0.30 | 0.14 / 0.14 / 0.14 |
| tagAncestor | 0.34 / 0.33 / 0.32 | 0.33 / 0.31 / 0.31 | 0.26 / 0.20 / 0.20 | 0.25 / 0.24 / 0.24 |
| tag+rating | 1.06 / 0.98 / 0.99 | 1.02 / 0.96 / 0.98 | 0.27 / 0.22 / 0.20 | 1.00 / 0.94 / 0.94 |
| combo | 11.54 / 11.34 / 11.13 | 0.36 / 0.35 / 0.35 | 0.51 / 0.34 / 0.31 | 0.30 / 0.30 / 0.30 |

**Release（第 2 轮全套表；主判据）**：

| filter \ sort | dateDESC | dateASC | ratingDESC | filenameASC |
|---|---|---|---|---|
| all | 0.14 / 0.13 / 0.14 | 0.13 / 0.13 / 0.13 | 0.15 / 0.14 / 0.14 | 0.12 / 0.12 / 0.12 |
| ratingGE4 | 0.29 / 0.28 / 0.28 | 0.28 / 0.27 / 0.27 | 0.16 / 0.15 / 0.15 | 0.28 / 0.28 / 0.28 |
| colorEq | 0.63 / 0.62 / 0.62 | 0.62 / 0.60 / 0.60 | 5.51 / 5.57 / 5.59 | 0.65 / 0.62 / 0.63 |
| cameraEq | 0.15 / 0.15 / 0.15 | 0.15 / 0.15 / 0.14 | 0.19 / 0.15 / 0.15 | 0.13 / 0.13 / 0.13 |
| dateRange | 11.71 / 11.91 / 10.83 | 0.15 / 0.15 / 0.15 | 0.69 / 0.37 / 0.30 | 0.13 / 0.13 / 0.13 |
| tagAncestor | 0.32 / 0.31 / 0.31 | 0.32 / 0.30 / 0.30 | 0.25 / 0.19 / 0.18 | 0.23 / 0.23 / 0.23 |
| tag+rating | 1.01 / 0.95 / 0.95 | 1.02 / 0.96 / 0.96 | 0.24 / 0.19 / 0.19 | 0.98 / 0.94 / 0.93 |
| combo | 12.28 / 10.91 / 11.18 | 0.35 / 0.34 / 0.34 | 0.48 / 0.33 / 0.29 | 0.28 / 0.27 / 0.27 |

（96/96 形状全测：`combo|filenameASC|d400k` 的输出行与 XCTest passed 行交错粘行，
数字已从粘行提取并入表。）

### A.3 硬门判定（<50ms，Release 主判据）

- **PASS：96/96 形状 Release 热 p95 最差 12.28ms**（`combo|dateDESC|d0`），门余量 **>4×**。
- 三轮对账（全矩阵最差形状逐轮）：

| 轮次 | Debug 最差 | Release 最差 |
|---|---|---|
| R1 | 12.21（dateRange\|dateDESC\|d0） | 11.53（dateRange\|dateDESC\|d0） |
| R2 | 13.20（combo\|dateDESC\|d800k） | 12.28（combo\|dateDESC\|d0） |
| R3 | 12.92（combo\|dateDESC\|d0） | 11.87（dateRange\|dateDESC\|d800k） |

- 两个关注形状（同首跑，均远过门）：`combo|dateDESC`（最坏组合 + 默认排序索引领先逐候选
  过滤，全深度 10.8-13.2ms）；`dateRange|dateDESC`（12h 窗低匹配率，DESC 扫过候选段长，
  10.8-12.2ms；ASC 同窗 0.15-0.17ms——区间上沿在索引头）。
- **`+` 前缀形状对照列（F10 防回归）**：cameraEq 全形状 0.13-0.20ms、colorEq|ratingDESC
  5.51-5.69ms、combo 深度页 0.27-0.48ms——无一形状出现 planner 过滤索引 + TEMP B-TREE
  回归形态（若回归应为 100-400ms 量级）；EXPLAIN 零 TEMP B-TREE 断言常驻 T3/T4 suite。
- 冷样本（d0 首查单列，参考非判据）：最差 `colorEq|ratingDESC` 164.2/165.6/166.2ms
  （Debug/Release 三轮——首页低选择性过滤 + DESC 索引跳候选的纯冷页缓存一次性成本，
  暖后 5.5ms；与首跑 215.13ms 同源同量级）。

### A.4 COUNT 面 + 投影吞吐（RQ-16-5，三轮区间）

| 项 | Debug（R1） | **Release（R1-R3 区间）** | 预算 | 判定 |
|---|---|---|---|---|
| COUNT(*) 全库 | 58.44 | 59.93-61.08 | 现算亚 100ms（角标非分页门） | ✓ |
| COUNT rating≥4 | 64.61 | 65.66-65.91 | 同上 | ✓ |
| COUNT cameraEq | 72.22 | 73.22-73.86 | 同上 | ✓ |
| COUNT combo（memo 命中） | 0.02 | 0.01 | memo 生效 | ✓ |
| tagSweep（**2.6M 行** GROUP BY） | 63.90 | 64.30-64.40 | 批量形态单次索引扫 | ✓ |
| 投影 full100k | 2.041s | **1.461 / 1.472 / 1.467s** | ≤30s（余量 **~20×**） | ✓ |
| 投影 increment10k | 312.3ms | 238.2-241.2ms | 秒级 | ✓ |
| 纯 diff SELECT | 5.0ms | 5.0-5.2ms | — | ✓ |

（combo 冷现算未单独呈现——harness 计时位为暖后第二次调用即 memo 命中；冷现算量级 =
首跑 ~219ms 与探针 218.8ms 对齐，走 memo 策略裁决 §RQ-16-6④ 不变。）

### A.5 与 16-1 首跑 / research 探针对账（偏差 >2× 归因）

| 项 | 探针（F6-F16） | 首跑（1.6M tags，存档 §B） | **终测（2.6M tags）** | 归因 |
|---|---|---|---|---|
| F7 keyset 全形状 | 0.01-27ms | 最差 35.37（Debug） | **最差 12.21-13.20（Debug）/ 11.53-12.28（Release）** | 同量级偏优（首跑机器负载略高 + fixture 同形）；无超门 |
| F10 `+` 前缀两量级 | cam 201→1.46ms | cameraEq 0.15-0.33 | cameraEq 0.13-0.20 ✓ | `+` 纪律稳定生效，无 F10 回归 |
| F11 tags PK seek | tag 分页 20.6ms | tagAncestor 0.19-0.35 | tagAncestor 0.18-0.34 ✓ | 同量级（tags 1.6M→2.6M 无感知，等值 O(log n)） |
| F12 投影吞吐 | 0.81s/10 万行 | Release 1.926s | **Release 1.461-1.472s** | 同量级且更优（修复后基线稳定）；预算余量 ~20× |
| tagSweep | 0.1-0.2s 量级估 | 40.21 @1.6M | **63.9-64.4 @2.6M** | 随行数线性 1.6×→2.6M 增长符合预期（首跑表预告），量级不变 |
| F16 库体积 | 450-500MB 估 | ~310MB | ~310-330MB（2.6M tags） | 估算带内 |
| F6/F15 keyset/尾段形状 | 零 TEMP B-TREE | ✓ | ✓（EXPLAIN 常驻断言 + 1M 实测） | 无回归 |

**超门处置记录：无**（无任一形状超门，无归因修复需求，无 BLOCKER）。

### A.6 SC#3 裁决行（正式）

> **SC#3 = PASS**（Plan 16-4 T1，2026-09-27，真机落盘 `.lcat`，Release 主判据，三轮对账）：
> §1.5 全矩阵 8 过滤 × 4 排序 × 3 深度 = **96/96 形状热 p95 < 50ms**（Release 最差
> **12.28ms**，余量 >4×；Debug 最差 13.20ms 同判）；COUNT 面现算亚 100ms + memo 命中
> 0.01ms + tagSweep 64ms@2.6M；投影 full100k **1.467s**（预算 30s 余量 ~20×）/ 增量 10k
> **240ms** / 纯 diff 5.0ms；`+` 前缀形状零 TEMP B-TREE 回归。**ROADMAP §Phase 16 SC#3
> 「1M 行参考库 p95<50ms」达成，v1 SQLite 终裁成立，无 v2 评估项重启事由。**

---

## §B. Plan 16-1 T5 首跑存档（2026-09-27 上午；历史参考——fixture 为修正前 1.6M tags 形状）

### B.1 首跑 fixture 说明

首跑 set-based 物化 SQL 候选表只枚举前缀链（漏独立 token Flower/Rose/Night），tags 实为
1.6M 行；`5cc4d8c` 修正后 projector 真形 = token + 前缀链全集（系数 2.6）。终测（§A）以
修正后 fixture 复跑落新账；首跑分页/投影结论不受影响（tags 体量仅影响 tagSweep 一项），
此处存档其数字作对账基线：

- 矩阵最差 `combo|dateDESC|d0` 35.37ms（Debug）；冷最差 `colorEq|ratingDESC` 215.13ms。
- COUNT：all 64.49 / ratingGE4 67.90 / cameraEq 76.41 / combo memo 0.04 / tagSweep 40.21@1.6M。
- 投影：full100k Debug 2.704s / Release 1.926s；increment 420.2/292.4ms；diff 5.5ms
  （修复 `idx_tags_image` 后——修复前 147.9s 为 tags 删除方向 N² 引擎缺陷，归因 ②）。

### B.2 Plan 16-3 附注：归类写面吞吐（PERF-07 语义跨域延续）

| 场景 | 实测 | 预算 | 判定 |
|---|---|---|---|
| 10k 批量归类（段2 单事务 INSERT OR IGNORE ×10000） | **0.027s**（Debug 直启 /tmp 落盘） | ≤5s | ✓ 余量 ~185× |
| 零像素渲染 | API 零图像数据进出 + fixture 目录零会话侧产物探针 + catalog 不镜像 thumb 列 | 万张级操作零像素 | ✓ |

口径：CatalogOrganizationTests.testBulkTenThousandAssignUnderFiveSeconds 常驻断言（<5s 门
+ printed 实测秒数）；归类路径仅触碰 catalog（单事务 prepared 循环，claimMetadataApply
形态），无 lindex/sidecar/解码/缩略图管线介入。

---
*§A = Plan 16-4 T1 终测（harness = Tests/LightamerTests/CatalogBenchmarkHarness.swift，
`LA_CATALOG_BENCH=1` 手动跑；Debug 轮日志 /tmp/la-bench-dbg-r{1,2,3}.log，Release 轮
/tmp/la-bench-rel-r{1,2,3}.log）；fixture /tmp 即弃不入仓。*
*验收轮盘点（2026-09-27）：六份日志现仅五份在盘（dbg-r2/r3 + rel-r1/r2/r3）——dbg-r1.log
不在（疑为后续轮覆盖/清理），§A.2 Debug 主表（R1 轮）数字无原始日志背书；其 R2/R3 轮数字
经验收抽核与现存日志逐项吻合（combo\|dateDESC 13.20/12.92 ✓），且 Debug 仅参考判据、
Release 主判据三份日志全在（rel-r2 combo\|dateDESC\|d0 = 12.28 ✓ 逐字复核）。*

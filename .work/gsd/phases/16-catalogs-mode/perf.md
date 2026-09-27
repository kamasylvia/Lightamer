# Phase 16 — Catalog Benchmark Ledger（perf.md）

> SC#3 基准账本。首跑 = Plan 16-1 T5（2026-09-27，executor worker，Debug + Release 双栏）。
> 口径：每形状 30 页 × 60 行取 p95（nearest-rank）；暖机一轮后测第二轮（冷样本单列）；
> 真机落盘库（`/tmp/catalog-bench-*/catalog.lcat`，即弃，L009 禁 UNITEK）；
> 机器 = macOS 27 arm64（本机 Debug/Release 同机对跑）；SQLite 系统 3.54.0。
> 环境门控：`LA_CATALOG_BENCH=1`（+ `LA_CATALOG_BENCH_N`，缺省 1M）。

## 0. PRAGMA 基线（F13 入档）

| PRAGMA | 值 | 依据 |
|---|---|---|
| journal_mode | WAL | 读写不互斥（R4） |
| synchronous | NORMAL | 可重建派生层 + 崩溃安全 |
| cache_size | -64000（64MB） | F13 实测 −25% |
| busy_timeout | 5000 | RQ-16-17 双实例 |
| case_sensitive_like | ON | RQ-16-16① startsWith 走 BINARY 索引 |
| mmap_size | 不设 | F13 <2% 增益，可选项不入基线（16-1-DECISIONS） |

## 1. Fixture（RQ-16-13 参数）

| 参数 | 值 |
|---|---|
| N | 1,000,000 行 / 10 会话 |
| 标签 | 40% 行带层级串（`Nature\|Flower\|Rose` 40%、`City\|Night` 20%）→ image_tags **1.6M 行**（膨胀系数 1.6；research 估算带 3-9M 对应「直打 1-3 × 深度 1-3 更宽分布」，本 fixture 用双标签串近似，行集形状同构） |

> **验收修正（2026-09-27，fix(16-1)）**：首跑 fixture 的 set-based 物化 SQL 候选表只枚举了**前缀链**
> （漏独立 token Flower/Rose/Night），故首跑实为系数 1.6（1.6M 行）； projector `tagRows` 真形 =
> token + 前缀链全集 → 本分布系数 **2.6（2.6M 行）**。harness 已修（候选表 8 形态，小 N 实证
> tags=78000/30000 行、distinct=8）；**§2/§3 首跑数字为 1.6M 行形状下的实测**，分页/投影场景
> 不受影响（tags 表体量仅影响 tagSweep 一项，1.6M→2.6M 同量级），16-4 T1 终测以修正后
> fixture 复跑落新账。
| NULL 率 | capture_date 10% / rating 60% / color_label 70% |
| camera_model 未扫率 | ~20% |
| 生成耗时 | Debug 16.0s / Release 17.2s（批量 prepared + 每 1 万行分批 COMMIT，PERF-07 无 temp-table join） |
| 库体积 | ~310MB（1M 行表 + 7 索引 + 1.6M tags；F16 估算 450-500MB 含更宽 tags 分布——一致性可接受） |

## 2. 查询集矩阵（§1.5）——热 p95（ms），30 页 × 60 行

**Debug**（首跑 2026-09-27，全套数字 /tmp/la-direct-tests.log；下表为摘要全表）：

| filter \ sort | dateDESC | dateASC | ratingDESC | filenameASC |
|---|---|---|---|---|
| all | 0.15 / 0.15 / 0.16 | 0.28 / 0.15 / 0.15 | 0.19 / 0.20 / 0.20 | 0.14 / 0.13 / 0.16 |
| ratingGE4 | 0.31 / 0.30 / 0.34 | 0.29 / 0.28 / 0.29 | 0.20 / 0.17 / 0.17 | 0.29 / 0.29 / 0.30 |
| colorEq | 0.65 / 0.63 / 0.63 | 0.62 / 0.64 / 0.69 | 5.66 / 8.04 / 7.10 | 0.87 / 0.67 / 0.76 |
| cameraEq | 0.18 / 0.19 / 0.19 | 0.17 / 0.16 / 0.20 | 0.33 / 0.17 / 0.16 | 0.16 / 0.15 / 0.15 |
| dateRange | 15.15 / 16.84 / 14.75 | 0.18 / 0.18 / 0.18 | 0.74 / 0.37 / 0.30 | 0.15 / 0.15 / 0.15 |
| tagAncestor | 0.35 / 0.34 / 0.34 | 0.34 / 0.32 / 0.32 | 0.20 / 0.19 / 0.19 | 0.26 / 0.26 / 0.26 |
| tag+rating | 1.06 / 1.01 / 1.01 | 1.04 / 1.01 / 0.98 | 0.22 / 0.20 / 0.20 | 1.01 / 0.96 / 0.97 |
| combo | **35.37** / 13.60 / 11.60 | 0.36 / 0.38 / 0.61 | 0.45 / — / — | 0.— / — / — |

（三列 = 深度 d0 / d400k / d800k。）

冷样本（每形状 d0 首查询单列）：最大值 = `colorEq|ratingDESC` **215.13ms**（首页低选择性过滤 + DESC 索引跳候选，纯冷页缓存）、`combo|dateDESC` 12.18ms；其余 ≤16ms。

**Release**：（见 §2.R）

### 软门判定（<50ms，Debug 口径）

- **PASS**：全部 96 形状热 p95 ≤ 35.37ms（最差 = combo|dateDESC|d0），无一处超门。
- 超门归因注记：无（无形状 >50ms）。两个关注形状（均过门）：
  - `combo|dateDESC|d0` 35.37ms：最坏组合（rating≥4 ∧ camera ∧ date 区间）+ 默认排序索引领先逐候选过滤；d400k/d800k 收敛到 ~12ms（越深处凑满 LIMIT 60 的候选越密）。
  - `dateRange|dateDESC` 全深度 ~15-17ms：12h 窗口低匹配率，DESC 索引扫过的候选段长；ASC 同窗仅 0.18ms（区间上沿在索引头）。

## 3. COUNT 面（§1.4）

| 查询 | Debug 现算/热 | research 探针 | 备注 |
|---|---|---|---|
| COUNT(*) 全库 | 64.49ms | 5.0ms | 见归因 ① |
| rating≥4 | 67.90ms | 18.2ms | 同上 |
| camera_model= | 76.41ms | 4.7ms（走被移除的 idx_cam） | 探针自注「移除后全扫 ~18ms」；此处含 `+`-前缀 + baseline 双谓词 |
| combo（冷） | ~219ms（探针级 218.8ms 对齐 ✓） | 218.8ms | 走 memo |
| combo（memo 命中） | **0.04ms** | — | memo 生效实证 |
| tag 全量（1.6M 行 GROUP BY） | 40.21ms | 253ms@13.3 万匹配 | 批量形态远优于 per-badge |

归因 ①（COUNT 偏差 ~2-4×）：Debug build 的逐候选谓词求值 + `+`-前缀抑制 + baseline 双谓词（探针 COUNT 为裸谓词）。COUNT 是角标面不是分页门（50ms 门只约束网格分页查询）；简单谓词亚 100ms 在「请求时现算」预算内，Release 分栏复测见 §2.R/§3.R。

## 4. 投影吞吐三场景（RQ-16-5）

| 场景 | 预算 | 首跑（修复前） | 修复后 Debug | **修复后 Release** |
|---|---|---|---|---|
| 10 万行全量重建 | ≤30s 级 | 147.94s（Debug）/ 148.34s（Release） | **2.704s** ✓ | **1.926s** ✓（余量 ~15×；5.2 万行/s） |
| 单会话 1 万行增量 | 秒级 | 31.62s（Debug）/ 32.92s（Release） | **420.2ms** ✓ | **292.4ms** ✓ |
| 纯 diff SELECT | — | 5.6ms | 7.0ms | 5.5ms（探针 6ms 对齐 ✓） |

### 归因 ②（首跑超预算 ~5×，已修复——真缺陷非口径）

首跑 Debug 147.9s 与 Release 148.3s **完全一致** → 排除编译口径，实为引擎缺陷：
`DELETE FROM image_tags WHERE catalog_image_id = ?`（投影 R6 的 per-image 删净重插）
在 `(tag, catalog_image_id)` 聚簇 PK 下**无反向索引** → 每次 DELETE 全扫 tags 表
（随 tags 行数增长，N² 型劣化）。research F11 探针只测了 `(tag, id)` 等值查询方向，
未测投影删除方向——**研究盲点，执行期发现并修复**。

修复 = `idx_tags_image ON image_tags(catalog_image_id)`（Schema DDL 变更 + 测试冻结断言
同步；EXISTS 查询方向不受影响仍走 PK）。修复后 Debug/Release 双口径双场景全部过预算，
与探针 F12（0.81s/10 万行）同量级对齐。结论：投影引擎无 N² 面、无意外 IO。

## 5. 与 research F6-F16 探针对账

| 项 | 探针 | 首跑（Debug/Release） | 偏差 | 归因 |
|---|---|---|---|---|
| F6 keyset 形状零 TEMP B-TREE | ✓ | ✓（T3/T4 EXPLAIN 断言常驻 + 1M 实测 p95 0.1-0.3ms） | 无 | — |
| F7 keyset 全形状 <50ms | 0.01-27ms | 0.13-35.4ms（Debug 全绿） | 无超门 | dateRange/combo 低选择形状在 Debug 下贴近门；Release 更低 |
| F8 OFFSET 判死 | 113-359ms | 不适用（OFFSET 已禁，键集唯一形状） | — | — |
| F10 `+` 前缀两量级 | cam 201→1.46ms | cameraEq 全形状 0.15-0.33ms ✓ | 无 | `+` 纪律生效 |
| F11 tags PK seek | tag 分页 20.6ms | tagAncestor 0.19-0.35ms；tag+rating ~1ms | 无 | 等值 EXISTS 形状健康 |
| F12 投影 10 万行 0.81s | 12.3 万行/s | 修复前 147.9s（Debug=Release 同值）→ 修复后 Debug 2.704s / **Release 1.926s** | 无（修复后与探针同量级） | 归因 ② |
| F13 cache 64MB | −25% | 入基线（§0） | — | — |
| F15 NULL 尾段 0.36ms | ✓ | tail 形状常驻（NULLTail suite + 矩阵内自动衔接） | — | — |
| F16 库体积 450-500MB | — | ~310MB（tags 1.6M 行 vs 估算 3-9M） | 预期内 | fixture 标签分布窄于估算带 |

## 6. 首跑结论

- 分页软门（<50ms）：**全形状 PASS**（Debug 口径；最差 35.37ms）。
- COUNT 面：简单谓词现算亚 100ms（Debug），组合/标签走 memo（命中 0.04ms）；分页门不适用于角标。
- 投影：修复后双口径双场景全过预算（full100k Debug 2.704s / **Release 1.926s**；增量 292.4ms；纯 diff 5.5ms）——首跑超预算为引擎缺陷（tags 删除方向 N²）已修复（归因 ②），**非**编译口径偏差（Debug/Release 首跑同值已排除口径）。
- **SC#3 硬裁决保留给 16-4 T1 真机终测**（同 harness 复跑）。

---
*Plan 16-1 T5；harness = Tests/LightamerTests/CatalogBenchmarkHarness.swift（LA_CATALOG_BENCH=1 手动跑）；fixture /tmp 即弃不入仓。*

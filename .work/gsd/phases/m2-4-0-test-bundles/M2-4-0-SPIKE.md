# M2-4-0 SPIKE — 测试宿主内存「积累」根因（2026-09-29/30，OQ 选项 c 先行定性）

**执行** = ZCode spike executor。**红线遵守**：产品源（LightamerCore/LightamerIOP/App）零 diff；
测试文件零改动；仅新增 `.work/gsd/phases/m2-4-0-test-bundles/spike/` 实验产物 + 本文档。

## 结论头

**PASS / 「17-26MB/test 线性跨域积累」前提被证伪。**

真实内存结构 = **三层**：

1. **少数 by-design GB 级重测试的瞬态峰值**（真凶）：每个破门 bundle 的 ru_maxrss
   峰值由 1-3 个单个测试独立定格，与测试总数无关；
2. **~1.4-1.6GB 一次性框架分页地板**：任何走 CI/RawCamera/RAW 9 解码的宿主进程，
   `__TEXT` 分页（RawCamera/CoreImage/CoreML/Metal 库）+ IOSurface 驱动驻留，
   首次使用即入驻、全程不退（vmmap diff 中 `__TEXT +1381MB` 在 IOPParity/Export
   两个独立 diff 中**逐字节同值出现**——一次性成本，非积累）；
3. **0.18-2.4MB/test 残留**（二阶）：Library（纯 CPU）0.18MB/test = XCTest 固有；
   GPU 域 ~2.4MB/test = 驱动驻留 + 少量 malloc zone 增长。

**<3G 硬门判定：在现重测试设计下数学不可达，且与 bundle 划分完全无关。**
隔离到单进程的最小重测类 `TilingOverlapTests`（仅 2 tests）自身峰值 **7865MB**。
原三选一中 (b)「细拆 bundle」无效（约束是单测峰值非积累），(c)「clearCaches 可释」
方向对本门无效（ru_maxrss 是高水位，跨测试 sweep 不可能降低已定格的峰值；
且重测试自身工作集就是它的验证对象）。见「建议选项」。

## 证据链

### E1 逐秒内存时间线 × 测试时间线 join（外部 vmmap/ps 轮询，零侵入）

宿主外部 1-2s 轮询 `ps rss` + `vmmap --summary`（footprint），与 run log 的
`Test Case … passed (N seconds)` 行（自含类名，无对齐歧义）join：

- **IOP**（457 tests，ru_maxrss 7654MB）：前 43s 全部测试 RSS ≤764MB；
  `TilingOverlapTests.testFULLToneEqual100MPMemoryUnder3GB` 单测 99.35s
  （100MP 合成图，by-design 验证 <3GB 属性），窗口内 RSS 1.9G 平台 60s →
  8s 内跳 7.3G。**峰值 100% 归因这 1 个测试**。其后 ~90 测试（XMP/WebP/Viewport
  等微测试）在 5.9G 残留地板上运行（重测试内存进程死亡前不归还——retention 非
  leak，对高水位门无影响）。
- **IOPParity**（308 tests，5788MB）：`HDRPipelineMatrixTests.testMergeStopwatchProbe24MP`
  （100.25s，RSS 3.6→6.0G）+ `McpRenderParityTests.testParityPlaneByteIdenticalToExportRenderStage`
  （102.7s，footprint 瞬时 7.6G）两测定格峰值。**关键反证**：HDR 测试结束后
  McpRenderParity 开始前 footprint 回落至 **525.8MB**——GB 级分配随测试实例死亡
  正常归还，**跨测试无棘轮**（假设 1/2/4 直接证伪）。bundle 结束仅 1557MB。
- **Export**（260 tests，6659MB）：`ExportPerfProbeTests` 两测（按设计测量 100MP
  规模内存/分段计时，4.5G RSS）+ `QuickLookRendererTests.testPreviewPlaneParityByteIdenticalSharedDecode`
  （79.1s，真 ARW 全分辨率双腿 parity；RSS 回落至 1.8G 同时 footprint 膨胀至
  10.1G = committed-but-paged-out / malloc zone 虚存 +4.1G——retention 形态，
  非跨测棘轮）+ `ExportRendererE2ETests` yiyin 双尺寸 E2E（2.5G）。
- **Layers**（164 tests，944MB）：无 GB 级单测。峰值 = 爬升地板（192→580MB）+
  后段测试瞬态（采样内最大 827MB/瞬时 footprint 2.5G）。944 ≈ 5.8MB/test 纯属
  「峰值÷计数」的算术假象。
- **Library**（430 tests，292MB）：0.18MB/test——XCTest 宿主固有基线的直接测量。

### E2 单类隔离峰值（test-direct.sh --bundle，ru_maxrss 精确口径，独立进程）

| bundle | 类（隔离运行） | tests | 峰值 RSS | 定格 bundle 峰值? |
|---|---|---:|---:|---|
| IOP | `TilingOverlapTests` | 2 | **7865MB** | 是（7654，±3% 运行方差） |
| IOPParity | `HDRPipelineMatrixTests` | 7 | **5913MB** | 是（5788） |
| IOPParity | `McpRenderParityTests` | 9 | 4368MB | 次峰 |
| Export | `QuickLookRendererTests` | 10 | 4589MB | 次峰 |
| Export | `ExportPerfProbeTests` | 2 | 4306MB | 次峰（by-design 测内存） |
| Export | `ExportRendererE2ETests` | 9 | 2494MB | 次峰 |
| IOPParity | `NLMeansParityTests` | 11 | 220MB | 否（时间线 4.1G 段系前类残留驻留） |

进程孵化开销实测 **2.2s/进程**（`--bundle Library StableHashTests` 7 tests 全墙钟
2.19s）——进程级隔离的成本可忽略。

### E3 vmmap 分区 diff（增长大户归因）

| 分区 | Layers Δ | IOPParity Δ | Export Δ | 定性 |
|---|---:|---:|---:|---|
| `__TEXT` | +300MB | **+1381MB** | **+1381MB** | 一次性框架分页（RawCamera/CI/CoreML/Metal），两 bundle 同值 = 共享一次性成本 |
| `IOSurface` | +1200MB（瞬态） | +1000MB | +1300MB | GPU 表面 = 测试工作集 |
| DefaultMallocZone | +76MB | +127MB | **+4100MB** | Export 大头在 QL parity 窗口（committed-but-paged-out 形态） |
| `__DATA`/stack/ObjC RO | +30MB | +200MB | +300MB | 运行时固有，二阶 |

### E4 残留量化（end-state − boot，时间线口径）

| bundle | boot | end | floor Δ | /test | 备注 |
|---|---:|---:|---:|---:|---|
| Library | 195 | 273 | +78MB | **0.18** | XCTest 固有（假设 5 属实但二阶） |
| Layers | 192 | 580 | +388MB | 2.37 | GPU 驱动驻留 + 框架分页 |
| IOPParity | 187 | 1557 | +1370MB | 4.45 | 末段类踩在前类残留上 |
| IOP | 210 | 5884 | +5674MB | 12.42 | TilingOverlap retention 占绝对多数 |

**算术收口**：即使残留清零（不可能全清），IOP 峰值 7654 → ≈7865-ε（隔离重测已证
峰值来自单测工作集本身）；残留全部消除的收益 ~0.3-1G，**不翻转任何门的判定**。

## 假设清单裁决（任务书 5 条）

| # | 假设 | 裁决 | 证据 |
|---|---|---|---|
| 1 | CIContextPool/CI 内部态跨测驻留 | **否**（对本门） | pool/MetalContext 每测试新建随测试死；GUI-22 memo ≤512MB 有界；clearCaches 存在（`MetalContext.clearCICaches()` public / pool internal @testable 可达）但 IOPParity 525MB 回落证明无棘轮可清；**ru_maxrss 高水位 = sweep 数学上不可能降已定格峰值** |
| 2 | PipeCache/PSO 缓存 | **否** | 测试自带 `PipeCache()` 实例（不共享）；3G budget 不触顶；PSO ≤256 项 MB 级 |
| 3 | Metal device/queue 驻留 | **部分**（一次性地板） | device/queue 单测内创建；IOSurface/驱动驻留属测试工作集 + ~1G 一次性分页，非跨测增长 |
| 4 | actor/Task 树悬挂 | **否** | 大测结束后 floor 回落（IOPParity 525MB）= 无 Task 持引用 |
| 5 | XCTest 宿主固有 | **属实，二阶** | Library 0.18MB/test × 2165 ≈ 全套 390MB；__TEXT/__OBJC_RO 分页一次性 ~1.5G |

## 已实现项（测试基建侧）

- `.work/gsd/phases/m2-4-0-test-bundles/spike/instrument.sh`——外部轮询插桩跑器
  （ps RSS + footprint + vmmap 快照时间线），零侵入（不动宿主/测试/产品任何文件）。
- 时间线/vmmap 产物同目录（`*.timeline.tsv` / `*.vmmap-*.txt` / `*.run.log`）。
- **无产品源改动、无测试文件改动**——「测试类间插 clearCaches 重测斜率」对照实验
  未执行：E1/E4 已证残留为二阶且 ru_maxrss 高水位使 sweep 对门无效，插桩手术无判定力
  （避免无意义 Tests 面污染）。

## 外推与判定

- 原「2165 × 17MB ≈ 37G」外推作废：单宿主全套真实峰值 ≈ **max(重测单测峰值) + 其前
  地板 ≈ 8-9G**，非 37G。7 bundle 现状各宿主峰值即完整刻画（最大 IOP 7654MB）。
- **<3G 门**：不可达（TilingOverlap 隔离单类 7865MB）。**<8G 门**：现 7 bundle 全过
  （最大 7865，贴线余量 ~4%，存在 ±3% 运行方差需留意）。

## 建议选项（OQ 三选一修订版）

- **(a) 放宽硬门至 8G + 维持 7 bundle（推荐，零改动立即可落地）**：门语义 = 「单宿主
  峰值 <8G + 运行监视 >8G 即杀」现行口径转正；MEMFAIL 阈值 `RSS_LIMIT_MB=3072`→8192
  一行改动（Scripts/test-direct.sh）。风险：IOP 贴线 4%，方差轮可能偶发破门——可配
  (b) 加固。
- **(b) heavy-class 进程隔离（可选加固，Tests/ 面 ~6 文件小 diff + 脚本隔离表）**：
  test-direct.sh 对隔离表类逐类独立 `-XCTest` 进程跑（每次 +2.2s），主跑跳过它们
  （需各类 setUp 加 env-gated XCTSkip，~4 行/类）。收益：各主 bundle 峰值回落至
  <1-3G、常规回归远离门线；**隔离进程自身峰值不变**（7.9G 仍在），故不单独解决门，
  只是把「门」与「重测」解耦。
- **(b') 重测减负手术（不推荐本轮）**：`testFULLToneEqual100MPMemoryUnder3GB` 等 5 处
  的 GB 级工作集是验证对象本身（100MP 平面 float32 = 1.6GB/张），减负 = 改验证语义，
  风险 > 收益。
- **(c) 原案「clearCaches 排障」关闭**：前提（线性积累可释）证伪；clearCaches 缝对
  ru_maxrss 门与跨测残留均无判定收益。

## 运行方差注记

TilingOverlapTests 隔离 7865MB vs 全 bundle 内 7654MB（±2.8%）；IOP 单跑时长三轮
115/77/(含轮询 145)s。门阈值判定应容忍 ≥5% 方差或取两轮最大值。

## 产物清单

`spike/instrument.sh`、`{IOP,IOPParity,Export,Layers,Library}.timeline.tsv`、
`IOP.TilingOverlapOnly.timeline.tsv`（隔离重测保留证据）、`*.vmmap-*.txt`（各 bundle
首/中/末快照）、`Library.spawn.timeline.tsv`（孵化开销证据）、join 分析脚本内联于
会话（一次性，未落盘）。

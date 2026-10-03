# Phase M2-10 — AI Library Benchmark Ledger（perf.md）

> M2-10-02 T3 嵌入扫描基准账本（2026-10-03，方法学 = M2-2-3 口径：真宿主
> measure 读数誊录 + 主判据明确）。硬门（D-M2-10-CONTEXT-1 后手触发线）：
> **20 万行 × 512 维全扫 median ≤ 50ms**（三次取中位；测试
> `EmbeddingScannerTests.testScanBudget200KRowsWithinP50Of50ms` 即哨兵，
> 超线 = 停下触发 sqlite-vec 讨论，禁静默调宽）。
> 口径：`Scripts/test-direct.sh` 直启宿主（Debug，L019b），
> `EmbeddingScanner.topK(rowIDs:contiguousFP16:dim:query:k:)`（生产连续面），
> k=256 min-heap partial sort；fp16 BLOB → `vImageConvert_Planar16FtoPlanarF`
> 256 行块升 fp32（零拷贝块视图）→ `vDSP_dotpr` 全扫；机器 = macOS 27
> arm64（10 性能核，本轮实测宿主单线程）。合成数据 = 64 个归一化向量循环
> 填充（扫描为数据无关定 FLOP 工作，循环填充只降生成成本，不影响度量；
> 方法注记）。读数 = 测试内 `print("PERF|…")`（日志
> `/tmp/la-direct-tests-Library.log`），三轮取中位。

## §A. Plan M2-10-02 T3 终测（2026-10-03）

### A.1 扫描三档（512 维，k=256，连续面主判据）

| rows | run1 | run2 | run3 | median | 判定 |
|---|---|---|---|---|---|
| 10,000 | 2.44 | 2.51 | 2.47 | **2.47ms** | 记录档 |
| 100,000 | 15.98 | 16.29 | 15.69 | **15.98ms** | 记录档 |
| 200,000 | 31.30 | 31.95 | 31.56 | **31.56ms** | **硬门 PASS**（≤50ms，余量 1.58×） |

- 线性外推：~31.6 万行触 50ms 线（RESEARCH §5 预估「20 万张或 p95>50ms」
  后手阈值与实测一致留 5× 安全余量的口径下，v1 全扫续航到 ~30 万行）。
- 分解探针（独立 -O 探针二进制，2026-10-03）：vImage fp16→fp32 块转换
  200k×512 ≈ 15.4ms + `vDSP_dotpr` 全扫 ≈ 8.0ms；逐行 Data 面
  （`topK(rows:)` sketch face）10k = 3.44ms（逐行 memcpy/桥接开销，
  记录用——生产恒走连续面）。

### A.2 查询链非扫描段（参考；M2-10-01 spike 数字）

- CLIP 文本塔 int8 前向（52 token）：5.59ms（ANE 档 20 次中位，
  M2-10-01-SPIKE ①）。
- 检索链目标 <100ms（CONTEXT D-1）：文本前向 ~6ms + 全扫 31.6ms
  （20 万行满库）≈ 38ms，**预算内**。

### A.3 方法学注记

1. **数据无关填充**：64 向量循环（扫描 FLOP 与数据内容无关；避免 Debug
   宿主 102M 次随机数生成的生成成本噪声）。
2. **连续面 vs 逐行面**：`loadScanTable` 产单一平面 fp16 buffer，扫描块
   `vImage_Buffer` 直指 payload（零拷贝）；逐行 `[EmbeddingScanRow]` 面每行
   memcpy + Data 桥接，Debug 宿主 200k 行实测 +25ms 量级——**生产代码路径
   恒走连续面**（KD-4 sketch face 保留给小 N/测试）。
3. **Debug 宿主口径**：主判据在 Debug 直启宿主采读（test-direct 纪律）；
   独立 -O 探针复核扫描核 ≈ 23.4ms（转换+点积），Debug 环境差 ≈ 8ms 为
   Swift 侧循环开销——阈值 50ms 在两口径下均过，哨兵不因口径漂移误触。
4.三轮中位（KD-4 波动防护）；MEMFAIL 门随全套（本轮 Library bundle
   peak < 8G）。

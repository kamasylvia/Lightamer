# Phase 6 perf 记账（`.work/06/perf.md`）

> 口径：只记录不设门（06-RESEARCH §7；SC 门沿 PREVIEW 拖动实测，6-5 建立拖动基线后补）。

## 2026-09-23 Plan 06-01 收工

- **signpost 埋点**：`LayerCompositeDriver.composite` 全程 interval 已落（subsystem `com.kamasylvia.lightamer`，category `pixelpipe`，signpost 名 `composite`）——Instruments 中与 `pixelpipe`/`decode`/`render` 并列可见。逐腿（base/层/终端）细分 interval 留 6-5 拖动门建立时按需加。
- **合成增量账本**（Debug，合成 48×32 fixture，LayerCacheTests 断言锁定）：
  - 冷轮 cache 行 = 8（base 输入+colorin / 每层 chain+prefix / colorout+gamma）
  - 编辑顶层 K（N=2）：4 hit / 2 miss / 1 blend kernel dispatch
  - 编辑底层 K=1：3 hit / 3 miss / 2 blend（下游前缀连锁失配为正确语义）
  - 重排两层：4 hit / 2 miss / 2 blend（链输出零重渲——重排免费红利）
  - 隐藏层：5 hit / 0 miss / 0 blend；禁用层：4 hit / 0 miss
- **内存账本**（MemoryBudgetTests 精确断言，窗口平面 = 48×32 float32 = 24576 B）：
  - 5 层 PREVIEW：cache = 13 float32 面 + 1 bgra8 尾 = **325632 B**，热轮复跑 +0 B
  - FULL 窗口化（96×64 图 + 64×40 roiHint，2 层一冷一热）：cache = 5×40960 + 10240 = **215040 B**，逐平面 ≤ 窗口平面；冷层链输出已逐出、热层链输出保留（D-06-CONTEXT-8 政策实证）； ungated 全幅等价 ≈ 6×98304 B，窗口化收益 ~2.7×（此窗口比例下），100MP 视窗场景收益为「几十 MB/平面 vs 1.63GB/平面」量级
- **待 6-5**：PREVIEW 层 K 拖动实测门（60fps）、FULL fit 视图 N 层全幅重渲 benchmark（fullColdLayer ↔ fullCacheAll 回退决策点）、10 层稳态拖动记账。

## 2026-09-24 Plan 06-05 收工

- **10 层稳态拖动门（PERF6，`LayerDragPerfTests.testTenLayerSteadyStateDrag`）**：
  - 场景：10 层全启用（每层一条 TestGain 记录，廉价 kernel 隔离合成成本），编辑层 K=4 每帧参数 tick，2560 PREVIEW bucket（2048×1536 原生帧），stable imageID 拖动形态，PSO 预暖 + 4 帧热身后测 12 帧。
  - **Debug 实测：median 15.6–16.4 ms**（多轮复测 15.57 / 15.69 / 15.72 / 15.73 / 16.10 / 16.24），**低于 16.6ms 60fps 预算**（Debug -Onone 口径；Release 更快）→ **60fps 门达标**，逐帧 = 层 K 链重跑 + K..N 前缀 reblend，<K/链输出全 hit（06-1 增量语义的实测兑现）。
  - 门 = Release 回归界 20ms / Debug 病理界 120ms（PERF-5 口径，只防回归不放宽）。
- **FULL 政策 benchmark（D-06-CONTEXT-8 回退决策点，D-06-05-T5-1 结论输入）**：
  - 同帧 2048×1536、10 层、fit（无 roiHint）vs 窗口（1024×768 roiHint）× fullColdLayer vs fullCacheAll（Debug，×3-5 修 Release）：
    - fit cold=16-17ms / fit cacheAll≈0ms（全 hit 短路）
    - window cold=4-5ms / window cacheAll≈0ms
  - **结论：维持「冷层不缓存」（fullColdLayer）**。理由：① 交互不落 FULL-fit 路径（PREVIEW 承担拖动，实测 15.7ms 达标）；② cacheAll 在 100MP FULL = 每层 1.63GB 平面 × N，5 层即 8.2GB，必破 D-C2 4GB 预算 → 预算 enforcement 会反向抖动驱逐，等效回冷层；③ 窗口化 cold 4ms vs fit cold 16ms（~4× 收益）证明 O(视窗) 是正确方向；④ cacheAll 的 0ms 帧只在「小图 + 全缓存存活」的合成场景出现，100MP 下不可持续。
- **10 层窗口化 FULL 内存账本（PERF-2 前瞻，正式门在 6-7 签核）**：
  - `testTenLayerWindowedFullMemoryLedger`：窗口化 coldLayer = **166,723,584 B**（base 腿 pre-geometry input + colorin 全幅 2×50.3MB + 层腿窗口平面）vs cacheAll = **279,969,792 B**（+68%，每层链输出全保留）→ 冷层扫描确实生效（断言 cold < all）。
- **signpost composite 段**：06-1 埋点（`LayerCompositeDriver.composite` interval）在上述全部场景直接可见于 Instruments（category `pixelpipe`，signpost 名 `composite`），与 `pixelpipe`/`decode`/`render` 并列。

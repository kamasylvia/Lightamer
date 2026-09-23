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

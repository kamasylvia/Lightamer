# Plan 06-01 — 层核与 sidecar v2 执行 SUMMARY

**执行**：2026-09-23 夜间 ZCode subagent worker（GSD executor）
**状态**：✅ 全部 7 任务完成，验收标准全过；终轮全 suite **648 tests / 3 skip / 0 fail**（直启宿主，touch + build-for-testing 重编后复跑）
**提交**：7e076b2 (T1) → fd21a5f (T2) → 0d08e30 (T3) → 2b497ca (T4) → 650e95d (T5) → 9ab15b2 (T6) → T7 收尾提交（本文档同批）

## 任务完成表

| 任务 | commit | 验证数字 / 证据 |
|---|---|---|
| T1 BlendMode 定案执行 | 7e076b2 | 三方映射表 13 值逐一核对 dt blend.h:44-91（本机树 dc58cf0ba1）；`colorDodge`→`colorAdjust` 更名编码不变回归：decode(Int 22)==.colorAdjust + 全枚举整数往返；`BlendOptions.reverse = 0x8000_0000` 与所有槽位无交叠断言 |
| T2 AdjustmentLayer + mutation API | fd21a5f | LayerCoreTests 11/0：duplicate 新层 UUID + 新链记录 UUID + paramsData/hash 字节不变；reorder 后 UUID 稳定；mergeDown 两态（mergedIntoLayer / mergedIntoBase）；effectiveChain 元组去重后者胜 + v50 排序；layerScope 分区投影（全局不含层条目）；未知 op 盒化跳过且记录保留 |
| T3 PipeCacheKey.layerID | 0d08e30 | 层命名空间隔离（同 imageID 异 layerID 不互hit）；compositePosition(-1)/maskPosition(-2) 保留位分类；enforceBudget tier-5 单轮跨档断言：3 chain + 4 最旧 prefix 驱逐、8 新 prefix + 3 mask + base sentinel 全存活；sentinel 默认值使 Phase 2-5 键空间字节不变 |
| T4 LayerCompositeDriver | 2b497ca | LayerCompositeTests 7/0：恒等三元组**逐字节**双档（op=1 == 平铺合并链；op=0 == base-only；空链/禁用/隐藏层 no-op）；LAYER-02 独立参数内容级差异（diverging bytes > 0）；roiHint 窗口化合成 == 同窗口平铺链；几何检测器 4 槽位全抓（lens 13/ashift 15/flip 16/clipping 17）；REVERSE a/b 交换 |
| T5 层缓存记账 | 650e95d | 精确 hit/miss 账本（数字入注释）：冷轮 8 miss（base 腿含输入面 2 + 每层 chain+prefix 2×2 + 终端 2）；编辑顶层 K=2：4 hit/2 miss/1 blend；编辑底层 K=1：3 hit/3 miss/2 blend（B 前缀连锁失配 ✓）；重排：4 hit/2 miss/2 blend（链缓存全存活 + 重合成字节恒等）；隐藏：5 hit/0 miss/0 blend（链存活无 probe 前缀）；禁用：4 hit/0 miss（完全无 probe）；opacity 编辑：5 hit/1 miss/1 blend |
| T6 sidecar v2 | 9ab15b2 | Phase6SidecarTests 6/0：3 层栈 write→read 参数逐字节 + UUID 恒等 + **渲染逐字节恒等**（identity layer 栈，PREVIEW）；v1 文档（真实 v2 降版 + 手写 null 样本）兼容读；层感知漂移（opacity/paramsData/结构性三种篡改全抓、原文档零误报）；stackSnapshot 双路径（运行时 + sidecar String-hash 投影）round-trip；未知 op 层降级（层 enabled=false、链字节 verbatim） |
| T7 预算/轨B/signpost/收尾 | 本提交 | MemoryBudgetTests +2：5 层 PREVIEW 账本**精确** = 13 float32 面 + 1 bgra8 尾 = 325632 B，热轮 +0 字节；FULL 窗口化（96×64 图 + 64×40 roiHint）账本精确 = 5 窗口 float32 面 + bgra8 尾 = 215040 B，冷层链输出被逐出、热层保留，输出平面 == 窗口；轨 B 全链（Phase 3+4+5 全模块，真实 RAW）+ 单恒等层 == 无层基线**逐字节**（零增量证明）；signpost `composite` 段埋点（LayerCompositeDriver 入口/出口 interval） |

## 全套测试

- 终轮：**648 / 3 skip / 0 fail**（196s，`Scripts/test-direct.sh`，构建 = `caffeinate -dis xcodebuild build-for-testing`）
- 基线 609 → 648：+39（LayerCoreTests 11、LayerCacheTests 10、LayerCompositeTests 8、Phase6SidecarTests 6、LayerSkeletonTests +2、MemoryBudgetTests +2、其余为 SidecarRoundTrip/TieBreak 重编后计数）
- 既有测试改动仅两处：LayerSkeletonTests（BlendMode 更名波及 + T1 回归 3 断言）、SidecarRoundTripTests（schemaVersion==1 硬编码 → `schemaVersionCurrent`，v2 兼容）

## 防空转自检（L020 对策③）

- 恒等三元组：`assertBytesEqual` 逐字节 float 位比较 + 空面 fail（非容差档），PREVIEW/FULL 双档 ✓
- 缓存记账：survival probe = make 闭包必须不执行（hit）；eviction probe = 必须执行一次（miss）；账本数字精确断言（非不等式）✓
- dscIn/ROI：driver 常驻 precondition（每层 entry dscIn == 自身 bufInROI.first == window）+ 内容级窗口化对比 ✓
- 渲染类断言全部 L014 fence 读回 ✓

## 遗留 / 风险（移交 6-2+）

1. **GoldenColorTests flake（既有，非本 plan 引入）**：ColorSync CI 腿黑帧类（L018 缺陷 3 同类），失败数随轮次 0–2 浮动、单跑必绿、先行测试集与基线一致——GOAL-STATE「trackB flake（05-08 复估）」既有挂账，本轮终轮已通过；建议 perf plan 一并复估。
2. 驱动 `blendPasses` 语义 = kernel dispatch 数（prefix hit 短路不计）——6-2 blendop 引擎接手时保持该语义。
3. 层内几何拒绝 = fatalError 语义（plan 原文），进程内不可直接测——可测面 = `LayerCompositeDriver.layerGeometryViolation` 纯检测器（4 槽位全断言）；UI 隐藏在 6-5。
4. crop（V50 24.5）/enlargecanvas（16.5）未列入 D-06-CONTEXT-5 的 13/15/16/17 拒绝集——同理由可入集，留 6-5 UI 面核时决定（DECISIONS D-06-01-T4-1）。
5. FULL 冷层政策的「热层」概念当前由参数注入（hotLayerID），真实热层跟踪在 6-5 接线；benchmark 回退开关（fullColdLayer ↔ fullCacheAll）已备。
6. `BlendOptions`/`blendOptions` 为 plan 拼写之外的 ADDITIVE optional 字段（REVERSE 位载体）——见 DECISIONS D-06-01-T6-1。
7. 层 K 编辑的「>K 链输出全 hit」在 6-1 依赖同 batch 内层链 records 不变；6-5 history 全粒度接线时按 `effectiveInstances(layer:)` 维持。

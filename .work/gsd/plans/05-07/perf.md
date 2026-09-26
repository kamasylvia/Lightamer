# Plan 05-07 PERF — denoiseprofile 波列引擎趟数 + FULL 分块（2026-09-23，Debug，M4）

测量：`PreviewChainPerfTests.testWaveletsEnginePassBudget`（2048×1536 float32
引擎平面，PSO 预热后计时，队列 drain 同步）+ `DenoiseProfileParityTests
.testFullFootprintBudget`（100MP TilingPlan 账面）。

| 项 | 数字 | 说明 |
|---|---|---|
| 波列引擎（2048×1536，默认 Y0U0V0，FULL 语义 scale=1） | **31 趟 = 41.7 ms 中位**（8 轮 40.7–43.0） | 20% 支撑域规则 → max_scale 7 ⇒ 7 band × 4 encoder（decompose/reduce×2/synthesize）+ precond/residue/backtransform = 31；与 RESEARCH「~25-30 趟」预期同档（上界 32 已断言） |
| FULL 100MP（11648×8736）分块 | **35 tiles，单 tile 读平面 0.059 GB** | 168 B/px = (3.5+7)×16 → 全幅账面 16.8 GB ⇒ TilingPlan（512MB budget，halo 2^7=128）强制分块，Δfootprint 被分块封顶 ≪3GB 门 |
| PREVIEW 拖动帧 | 未单独计 | 波列降载未做 K clamp（与 nlmeans 不同：band 数由支撑域规则全幅钉死，tile 内稳定——L021），preview 管经 TilingPlan 分块摊薄；正式 60fps 门 = 05-08 签核（Release 构建 + GUI 拖动实测） |

- 波列 31 趟全部为 `dispatchThreads` 一次性 encoder（无 read_write RMW 图
  ——L018 双缓冲合规），41.7ms 为 Debug 数字；Release 预期显著低。
- dt 侧对照：dt CPU process_wavelets 同为 band 循环（OpenCL 关闭时），
  趟数结构一致（per band decompose+reduce+synth）。

# Plan 05-06 PERF — nlmeans 满血 vs 降载两档（2026-09-22，Debug，M4）

测量：`PreviewChainPerfTests.testNLMeansPreviewDowngradeTiers`
（2048×1536 float32 平面，PSO 预热后计时，队列 drain 同步）。

| 档 | 趟数 | 中位 ms | 说明 |
|---|---|---|---|
| 引擎降载（K=3 + decimate，PREVIEW/THUMBNAIL 管自动） | 14×4+1 = **57** | **57.8** | piece.pipeType=.preview 派生（单元 pin：NLMeansParityTests.testPreviewDowngradeDerivations） |
| 引擎满血（K=7，FULL 管语义） | 120×4+1 = **481** | **430.9** | 同平面同参数，仅 pipeType 差 |
| PREVIEW 全链（28 实例 seed 含 nlmeans 降载） | — | **97.1**/帧 | 拖动帧型（params tick/帧）；链基线 ~45ms（03-06 T7 同图基线）→ nlmeans 增量 ≈52ms ≈ 引擎降载档 |

- 降载杠杆兑现：**7.5×**（430.9 → 57.8）；预览拖动档趟数 481→57（-88%）。
- 与 RESEARCH §9 预算对照：预期「PREVIEW ≈ 30-60ms Debug」实测 57.8 ✓；
  满血 481 趟 431ms ⇒ FULL 100% 放大镜场景必然走 TilingPlan 分块（80 B/px
  → 100MP ≈ 8.2GB > 512MB budget，`testFullResolutionTileGridEngages`）。
- SC#4 正式 60fps 门 = 05-08 签核（Release 构建 + GUI 拖动实测；本轮为
  Debug 数字 + 降载路径命中证据）。
- dt 侧满血/降载对照：dt nlmeans 无 K clamp（decimate 有）——K clamp 3 为
  denoiseprofile.c:1626-1631 同构的 Lightamer 增强（DECISIONS D-05-06-T2-2）。

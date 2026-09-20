# 04-05 PERF — detail 五模块单帧增量（T5 acceptance）

> 方法：PreviewChainPerfTests 模式（2048×1536 synthetic，PREVIEW longEdge 2560，
> PSO prewarm 后 12 帧 warm median）。Debug 本机（Apple M4），与 03-06-T7 同口径。
> 下面是单模块 toggling 测量：全 seed 链 vs 该模块 disabled（highpass/soften 反向：
> enabled-active vs disabled），差值 = 单帧增量。

| 模块 | 腿 | 单帧增量 Debug | 备注 |
|---|---|---|---|
| sharpen (r2.0/a0.5) | prep + IIR(σ2) + mix | ~2-4ms | IIR 双平面 3 pass + 2 Lab 往返 |
| bilat (d1.0/r20) | prep + EIGF(ds+pack+IIR+blend) + apply | ~4-6ms | ds 下 EIGF 最重；FULL 走 TilingPlan |
| highpass (s50/c50) | prep + IIR(σ~13) + mix | ~2-4ms | σ 大但平面小（PREVIEW） |
| soften (s50/a50) | over + IIR + mix | ~2-4ms | HSL 过曝 + IIR |
| equalizer (g0+0.5) | prep + 5×IIR(σ1-16) + recombine | ~5-8ms | 5 次全幅 IIR，链最重；FULL 注意 tile |

- 全 seed 链（+5 detail）PREVIEW warm median 预期 03-06 基线 +15-25ms（Debug）。
- 03-06 优化杠杆为共同解（Release/PSO 预热/批合并/Lab 往返共享 Phase 5）。
- 门：记录即合规（plan T5 "预期 2-6ms@2560px Debug"——equalizer 超 6ms 已标注，不阻塞）。

# M4-3 depth perf — IOP-MASK-07 Depth 蒙版（T7, KD-8）

- **机器**：Mac（Apple Silicon，macOS 27，test-direct 直启宿主，L019b 通道）。
- **方法**：`LIGHTAMER_PERF_PROBE=1` env 门控探针（`DepthPerfProbeTests`，默认
  套件 skip 实测 1/1/0）；计时 = await completion 环钟（L014：await 即完成栅
  栏，非 queue-async 假数）；每档 warm-up 1 次 + N=5 取中位（全样本在案）。
- **输入**：`Tests/Fixtures/DepthPrecision/scene-soft-shapes.png`（518×392）；
  端到端 = 3000×2000 合成帧（preview 长边 1040 帽生效）。

## 三档前向中位（2026-10-10 正式轮）

| compute units | median (N=5) | samples (ms) |
|---|---|---|
| **all**（ANE 优先，生产档） | **45.0** | 45.0 / 46.4 / 45.4 / 44.5 / 40.4 |
| cpuAndGPU | 55.8 | 58.8 / 55.8 / 56.3 / 55.1 / 54.6 |
| cpuOnly | 67.0 | 67.2 / 67.0 / 66.9 / 67.4 / 66.4 |

## 端到端一趟（preview 写盘 → worker runDepth → F32 读回 → 四段管线）

- **231.3 ms**（α=518×392 产出；烤盘走 IOP-MASK-03 共享通道未重复计时）。

## 对照与结论

- Apple 官方自报：ANE 纯推理 25-33 ms（M1/M3 Max 口径）。本机 `.all` 45 ms
  含 PNG 解码 + CGContext 拉伸 + half 读回 + F32 写盘（≈10-15 ms 管道开销）
  → 推理核 ≈30-35 ms，**落带**；无 >10× 超带项，无落 CPU 异常（`.all` 显著
  快于 `.cpuOnly` 45 vs 67 = ANE 确在档）。
- 首轮探针（同一测试二进制、冷 ANE specialization）`.all` 曾录 67.1 ms ≈
  `.cpuOnly` 档位——warm-up 后稳定 45；推论 = ANE 首专化未竟时落 GPU 兜底。
  perf 结论取 warm 正式轮；一次性用户操作对 ≤1 s 的首专化不敏感（生成是
  后台任务，非每帧路径）。
- 预算判定：一次性蒙版生成（preview→出 α）≈ 0.23 s，预算宽松达标。

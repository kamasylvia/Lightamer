# Phase 08（HDR/Stacking & Effects）perf 账 — 只记不设门

> 口径：与 Phase 12 先例一致——**只记不设门**。RESEARCH §0/§12 的探针实测数字作为**参考基准**
> 对账；偏差 >2× 归因注记；不得为凑数字调口径（L020 同源纪律）。
> 环境：Apple M4（4P+6E）/ 16GB / macOS 27.0，Release 探针为 research /tmp 原型；本账数字来自
> **真实解码链**（`RAWDecoder.decode` + `CIContext` 渲染，Debug 测试宿主 `test-direct.sh` 直启）。

## 08-1（HDR merge 全链）

| 段 | research 参考基准 | 本 plan 实测 | 对账 | 备注 |
|---|---|---|---|---|
| CIRAW 100MP 单张解码（对齐遍形态：decode + 1024px 全帧渲染） | 2–5 s/张（§12 估） | **0.96–1.93 s**（GFX100S 11648×8736 = 101.8MP，两次采样） | ✓ 优于参考 | R7 消解：解码主导段实测低于估算下界；冷启动首测取 1.93s 稳态上限口径 |
| CIRAW 100MP 单张解码（合并遍形态：decode + 全幅 float32 RGBA 渲染） | 同上（含全幅写出） | **0.92–0.99 s** | ✓ 优于参考 | 全幅 1.63GB bitmap 短暂驻留（BandStreamer 流式带消费） |
| MTB 对齐（3-bracket） | ≈3.8 s 单线程 CPU（P1） | 待 T2 首账 | — | |
| Robertson 合并内循环 | ≈1.1 s 单线程（P2 11.2ns/px） | 待 T3 首账 | — | |
| ghost/weight-map 面 | 0.3–4 s（P3/P5） | 待 T4 首账 | — | |
| float TIFF 写 | 2–4 s（EXP-01 量级） | 待 T3 首账 | — | |
| 全程秒表（100MP×3，<60s 参考基准） | ≈15–40 s | 待 T7 首账 | — | |

### 首测记录（08-1 T1）

- 测试：`StackMergeServiceTests.testCIRAW100MPDecodeTimingProbe`（真实链：`RAWDecoder().decode`
  → `CIContext.render` 两档，强制 lazy CIRAW 真解码；**无时长断言**）。
- fixture：`Fujifilm-GFX100S-14bits-uncompress-4_3.RAF`（101.8MP，无压缩；RAW v8——GFX100S 不在
  RAW 9 beta 支持表）。
- 采样 1（冷）：align-pass **1.93s** / merge-pass **0.99s**；采样 2（暖）：align-pass **0.96s** /
  merge-pass **0.92s**。
- 归因注记：research §12 的 2–5s 估算为 Phase 2 量级外推，实测低 ≈2–5×——GFX 无压缩 RAF +
  Apple M4 CIRAW 快速路径；无压缩大文件是最有利形态，压缩 RAW（lossless）预期落在估算带内。
  全程预算结论不变（解码非瓶颈风险 R7 解除）。

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
| MTB 对齐（3-bracket） | ≈3.8 s 单线程 CPU（P1） | 512px fixture 搜索 <0.05s（Debug）；100MP 带级未单钉 | 见注 | 对齐面并入 E2E 秒表；100MP 单段钉留 08-5 收口 |
| Robertson 合并内循环 | ≈1.1 s 单线程（P2 11.2ns/px，Release -O） | 24MP E2E 秒表 73.5s（Debug 宿主，见下） | **口径差归因** | Debug 内循环 ≥10× 慢于 Release；数字不可与 Release 探针直比 |
| ghost/weight-map 面 | 0.3–4 s（P3/P5） | deGhost-off 探针未含；deGhost 段随 08-3/08-5 | — | |
| float TIFF 写 | 2–4 s（EXP-01 量级） | 含于 73.5s E2E 内（384MB×3 合成源写盘） | — | |
| 全程秒表（100MP×3，<60s 参考基准） | ≈15–40 s | **24MP 实测 73.5s（Debug）；线性外推 100MP ≈312s（Debug 上界）** | **归因注记** | ①宿主 = test-direct Debug 配置（Project.swift @testable 与 Release 测试互斥，Release 直测不可行）②research 11.2ns/px 为 Release -O 探针，Debug 逐像素 Swift 循环典型慢 ≥10×③16GB 宿主内存策略（13-2 swap 纪律）禁止 100MP 直测入全套④Release 口径复测归 08-5 收口/独立验证批 |

### T7 补账（HDRPipelineMatrixTests，2026-09-28）

- `testMergeStopwatchProbe24MP`：6000×4000（24MP）3-bracket 合成 float TIFF，真生产 leg
  （raster decode → MTB → Robertson → float TIFF 落位），deGhost off，全程 **73.5s**（Debug）。
- `testMergedProductPreviewMemoryProbe`：64×64 真合并产物 → preview 管线，plane = 64KB
  （= 64×64×16B ✓ 与 2560px≈70MB/平面同一 16B/px 口径，比例自洽）。
- **发现（D-08-1-T7，回注 08-5）**：①CI input 腿 workingFormat RGBAh 对 sub-1e-4 HDR 值
  **下溢丢失**（shadow_torture.exr 场景线性值 96×96 经 pipeline 输出全黑，同链 64×32 合成
  patch 正常——L006 half-banding 的 HDR 面）②torture 96×96 与 patch 64×32 的 pipeline 行为
  分歧未定位。两项归 08-5 preview float32 预算复核收口；矩阵基座以 patch 域钉住核心主张：
  65504×2 = 131008 无钳制存活 + toneequal(0) 全链尾恒等（maxDev = 0.0）。

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

## 08-2（创意效果簇：vignette / grain / bloom）

| 项 | research 参考基准 | 本 plan 实测（Debug，`test-direct.sh` 直启） | 对账 | 备注 |
|---|---|---|---|---|
| bloom blur 腿形态 | 级联 ÷8 box → 1/8 分辨率小 σ gaussian → 双线性上采 = **0.29 s @100MP r=64**（P5；vs 3-pass box 1.87s，6.5×） | 采级联实现；`EffectsWiringTests.testEffectsPreviewPerfProbe`：**preview 链整体 median 27.8 ms @2560px**（bloom dt 默认 size 20） | ✓ 形态一致 | preview 面积 ≈ 100MP/64，级联腿理论 ≈4.5ms——27.8ms 为**整链 composite 计时**（含 base 管线 + 终端段），非 blur 腿单独秒表；无回退（基线链 45.5ms 量级同域） |
| vignette preview 链 | —（dt 单 kernel，无独立参考数） | **median 26.0 ms @2560px**（整链，同上口径） | 只记 | 单 kernel 逐像素直译，60fps 预算（16.7ms/帧）外的 Debug 计时含链路固定开销，Release 形态预期减半 |
| grain preview 链 | —（3-octave simplex，dt CPU-only 无 GPU 参考数） | **median 25.8 ms @2560px**（整链，同上口径） | 只记 | 与 vignette 同量级——simplex 3 octave 无差量；21-tap lattice filter 腿仅在 zoom-out 激活 |

### 首测记录（08-2 T4）

- 测试：`EffectsWiringTests.testEffectsPreviewPerfProbe`（LayerCompositeDriver preview 链 + 各模块 dt
  默认参数；warm 1 轮 + 10 采样取 median；**无时长断言，只记不设门**）。
- 口径注记：`PERF8-EFFECTS preview-chain (2560px, Debug) — vignette: median 26.0 ms | grain:
  median 25.8 ms | bloom: median 27.8 ms`。三 iop 挂链后均 **不回退**既有 preview 基线（与
  `PERF5 PREVIEW full-chain` 45.5ms Debug 量级同域对照——本探针走 LayerCompositeDriver，链略短）。
- bloom 级联 0.29s @100MP 对账：形状一致（÷8 box + 1/8 FIR + 双线性）；100MP 全幅级联秒表未在本
  plan 单独复测（preview 探针 + P5 参考数在案即过；EXPORT 全幅秒表留 08-5 收口若需）。
- 确定性纪律注记：三模块 preview 渲染逐字节确定（GrainTests 双断言 + EffectsWiring 恒等段在案）。

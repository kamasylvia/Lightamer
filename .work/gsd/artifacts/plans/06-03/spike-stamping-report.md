# Plan 06-03 T1 — stamping spike 报告（两方案数字表）

- 日期：2026-09-23（夜间 subagent worker）
- 原型：`.work/plans/06-03/spike-stamping.swift`（独立 Metal harness，运行时 MSL 编译，零项目依赖——L018 红线下先于一切正式光栅化代码）
- 机型：Apple Silicon（MTLCreateSystemDefaultDevice），macOS 27 SDK

## 判据与数字

### 1. 精度（单 stamp flow=1/100 叠加 100 次，目标 1.0，门 <1e-5）

| 方案 | 累加结果 | 误差 | 判定 |
|---|---|---|---|
| A render-pipeline additive（r32Float + 硬件 blender add） | 0.99999934 | **6.56e-07** | ✓ 达标 |
| B compute + atomic_fetch_add（uint32 定点 2^24/1.0） | 解析和逐点对照 | **3.73e-09** | ✓ 达标（整数加法天然精确） |

A 的误差 = float32 累加舍入（100 次单站累加的期望量级 ~1e-7），低于 1e-5 门一个半数量级。

### 2. 吞吐（1000 stamps @ 2560×1707 窗口，50 轮中位，门 = 交互预算内）

| 方案 | 形态 | median | min | max |
|---|---|---|---|---|
| A | instanced 单 pass 一次 draw（生产形态：整条 stroke 的 stamps 批在一趟 render pass） | **0.744 ms** | 0.534 | 3.717 |
| A | 1000 独立 encoder draw（悲观上界：逐 stamp 编码开销） | 0.947 ms | 0.816 | 3.878 |
| B | compute 逐像素全 stamp 循环（1000 stamps，atomic 定点） | **29.540 ms** | 28.194 | 29.951 |

B 慢 ~40×：accumulate 语义迫使每个像素在 shader 内遍历全部 stamps（fan-out 移入 per-pixel 循环）+ 全图原子写；A 的 fan-out 在光栅化硬件（quad 覆盖域），无覆盖像素零成本。0.74ms ≪ 交互预算（D-C3 单 pass 1-3ms 档）。

### 3. 代码复杂度（定性）

| 维度 | A | B |
|---|---|---|
| 代码量 | vertex+fragment 两函数，blender 状态四行 | 同 kernel + 定点换算/回转 |
| 失败模式 | 无（硬件保证） | 定点量化（2^24）、uint32 溢出界（>256.0 需防护）、无 float 原子的绕行复杂度 |
| eraser（负 stamp） | flow<0 直接可加（有符号 float） | 定点负数需补码语义绕行 |

## 定稿（D-06-03-T1-1）

**选 A：render-pipeline additive blending。**
- falloff 实现位置：**fragment shader**（每 stamp 一个屏幕空间 quad，fragment 内按插值的图像域坐标求径向剖面；hardness = 实心核半径占比，density/flow = 每 stamp 权重，eraser = 负 flow）。
- B 保留为记录在案备选（精度更高但吞吐/复杂度全劣，仅在 A 的硬件混合在未来平台失效时复评）。

# Plan 06-03 执行期决策（DECISIONS）

> 编排授权模式：plan 逐字执行 + 执行期决策落本档。每条含裁决/依据/可逆性。
> 执行者：GSD executor subagent（2026-09-23/24 夜间）。

## D-06-03-T1-1 stamping 定稿 = 方案 A render-pipeline additive blending

- **裁决**：brush stamps 累加走 **render pass + 硬件 blender add**（r32Float render target，`rgbBlendOperation = .add`、source/destination factor = `.one`；整条 stroke 的 stamps 以 instanced 单 pass 批绘）。备选 B（compute + `atomic_fetch_add` uint32 定点 2^24）记录在案不复用。
- **依据**（spike 实测数字，报告正本 `.work/plans/06-03/spike-stamping-report.md`）：
  - 精度：A = 6.56e-07（100 次 flow 1/100 叠加 vs 理想 1.0，门 1e-5）；B = 3.7e-09。A 达标。
  - 吞吐：A instanced 1000 stamps @2560×1707 = **0.744 ms 中位**；B = 29.5 ms（accumulate 语义迫使 per-pixel 全 stamp 循环 + 全图原子写）。A 快 ~40×。
  - 复杂度：A 无定点量化/溢出/负数补码问题；eraser 负 flow 天然可加。
- **falloff 落位**：fragment shader——每 stamp 屏幕 quad，fragment 按插值图像域坐标求径向剖面（hardness = 实心核占比；density/flow = 权重；eraser = 负 flow）；累加后由 fold pass 做 clamp[0,1] × gopacity（预乘契约 D-06-02-T5-3）。
- **可逆性**：reversible——若未来平台禁 float render-target 混合，B 原型在案可复评；光栅化 API 面不变。

## D-06-03-T2-1 GeometryPointMapper 落位 = Core 纯数学 + IOP 模块侧增量 hook

- **裁决**：`GeometrySegment`（affine / homography / radial / liquifyIdentity 四 case）+ `GeometryPointMapper`（compose + forward/inverse，全解码帧归一化坐标 ↔ 合成平面坐标，内部连续像素坐标）落 **LightamerCore/Sources/Pipe/GeometryPointMapper.swift**；四个几何模块各自新增 `pointMapSegment(inputSize:) -> (GeometrySegment, SIMD2<Double>)?`（nil = 恒等直通；模块侧算各自矩阵/系数，Core 不 import IOP——D-03 依赖向）。`Mat3D` 上移 Core/Foundation（IOP 侧 typealias 保 API），homography 的 3×3 复合（crop∘flip∘ashift 归一化域单矩阵）由 rasterizer 侧 CPU 组装进 kernel uniforms。
- **依据**：D-03 模块依赖向（Core ← IOP）不可反向；mapper 是 mask 光栅化（Core）与 liquify（6-6）的共享件；`ModuleBoxing` 加 `pointMapSegmentErased`（既有 erased-hook 惯例）。
- **可逆性**：reversible（hook 纯增量，默认 nil 即旧行为）。

## D-06-03-T5-1 brush/eraser 语义（执行期定稿）

- **裁决**：stamp = 圆盘（radius 以解码帧**宽度单位**归一），径向剖面 `w(d) = flow·(d ≤ hardness·r ? 1 : max(0, 1 − (d − hardness·r)/(r·(1−hardness))))`；hardness=1 全实心、0 全线性锥。**同 stroke 内 stamps 累加（A 方案 blender add），stroke 收尾 fold pass 一次性 clamp[0,1]**；eraser = **负 flow stamp**（同管线，fold clamp 到 [0,1] 即减除）——非 combine difference（那是 6-4 MaskGroup 的层间语义，brush 内擦除用负 stamp 直观且与交互一致）。多点 stroke 的贝塞尔串按 spacing = 0.5·r 采样插点（相邻 stamp 50% 重叠，硬边连续）。
- **依据**：plan T5「N stamps → 解析和」验收项的可断言语义 = 加法累积 + 收尾 clamp；dt CPU brush 的 MAX-union 是其 CPU 实现细节（border 线段模型），dt-cli 对 mask 不可达（L017），解析参考替代（06-CONTEXT golden 主轨）——加法+clamp 与 dt MAX 在不重叠 stamp 上逐值一致，重叠域为 flow 语义（PS/C1 brush 惯例）。
- **可逆性**：语义级（sidecar 只存点列/参数，渲染语义可后续演进，不破坏格式）。

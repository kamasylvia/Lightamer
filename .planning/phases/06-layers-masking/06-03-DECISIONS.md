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

## D-06-03-T2-2 IOPModule 协议成员声明陷阱（执行期排障实录）

- **裁决/事实**：`pointMapSegment` 最初只写在 `public extension IOPModule`（默认 nil）——协议扩展-only 成员在泛型语境**静态派发**，`ModuleBox<M>` 的 erased 转发读到的永远是扩展默认值（四个几何模块的具体实现被静默跳过，crop/ashift hook 直接返回 nil，测试红）。修复 = 把需求声明进**协议本体**（witness table 落位）+ 扩展保默认。教训已在 IOPModule.swift 头注钉死。
- **依据**：GeometryPointMapperTests 红 → 直接调用模块实例（绿）vs box erased 路径（nil）二分定位。
- **可逆性**：n/a（语言语义备忘，泛型 erased-hook 全项目适用）。

## D-06-03-T4-1 analytic 形态公式定稿（q 域椭圆 + A&S erf + 精度分层）

- **裁决**：①椭圆 = dt `_fill_mask` 二次衰减的**重形式**——f = clamp((k²−q)/(k²−1))、v = f²，q = 归一化椭圆半径平方（旋转 −rotation 后 (dx/rx)²+(dy/ry)²）；k² 域避免 dt 原式 (total²−radius²) 在 border→0 的 0/0 与 float32 大数相消（实测 e 域仍漏 ~2e-6，q 域 ≤0.03e-6 + 旋转桁件 1.34e-6）。border = 0 → 守卫硬边。②gradient 逐式直译 gradient.c（旋转符号 −、curvature 抛物项、对角归一距离），sigmoidal 的 erff 用 Abramowitz-Stegun 7.1.26 有理逼近（max abs err 1.5e-7，预算内）。③path = 多边形（贝塞尔环 CPU 展平）SDF + 射线奇偶 + border 带 smoothstep——自定解析形（dt border walk 为网格/UI 产物）。
- **依据**：L017 分流（mask 对 dt-cli 不可达 → 解析参考替代）；GPU float32 对 float64 参考的实测地板：全形 ≤1e-6（含 linear/sigmoidal gradient ≤3.5e-7、path ≤4.2e-7、brush ≤4.2e-7），唯一超档 = **旋转 30°+ 羽化带** 1.34e-6（float32 三角 |d|·ulp(cos/sin) 经 /rx ÷border 放大）→ 按 L023/05-02 分层门先例设 5e-6 档，实测数字入测试输出。
- **可逆性**：reversible（纯 kernel 内公式；参考与 kernel 同批改）。

## D-06-03-T4-2 大结构 uniform 禁 setBytes（ashift 竞态复现 + 全线换 MTLBuffer）

- **裁决/事实**：MaskRasterUniforms（176B）经 `setBytes` 上传时整场读到 pre-dispatch 垃圾（06-03 crop 场景实测：整幅 wedge 场）；换 shared MTLBuffer 后逐值正确。与 04-03 AshiftModule D2 注记同根（本机 async-committed encoder 的栈地址 setBytes 竞态）。stamp fragment 的 uniforms 同批换 setFragmentBuffer。
- **依据**：GeometryPointMapperTests/DirectModule 调用绿 + GPU 场错位的二分；切 buffer 后 DrawnMaskRasterTests 全绿。
- **可逆性**：n/a（工程纪律：>单字节小结构 的 uniform 一律 buffer 上传）。

## D-06-03-T7-1 overlay 显示腿路线 = Core overlay API + DEBUG 启动参 probe（UI 6-5）

- **裁决**：`DrawnMaskRasterizer.overlay(display:mask:strength:tint:metal:)`（Core 公开 API，返回显示平面**副本**——缓存写一次契约不破；tint 按显示纹理自身通道序传参，.bgra8Unorm 读回为 RGBA 序，黄 = (1,1,0)）。6-3 的 GUI 验证经 DEBUG 启动参 `-la_mask_overlay_probe`（PipeCoordinator 种子静态 UUID 的 brush 蒙版层，不入用户层栈；renderPreview 尾部叠加）。「显示蒙版」UI 开关 + 选中层路由 = 6-5 接线。
- **依据**：plan T7 授权执行期路线决策；L021 显示腿无单测覆盖 → 真机量化（FINDINGS：ΔR +65.5/ΔG +80.4/ΔB −35.6，视口 OFF 基线逐字节确定）。
- **可逆性**：reversible——probe 为 DEBUG-only；6-5 的 UI 开关直接调同一 overlay API。

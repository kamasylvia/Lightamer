# Plan 06-07 Decisions

> 执行期决策记录（GSD executor 纪律：决策即落盘）。dt 正本 = retouch.c + heal.c；
> 上下文依据 = 06-CONTEXT D-06-CONTEXT-1/4 + 06-RESEARCH §5.2/§9。

## D-06-07-T1-1: LayerKind 定名 = `retouch`（`case raster` 不增设）

- **裁决**：06-01 预留注释「Phase 6 may add: case raster (baked raster layer for
  retouch/clone)」兑现为 **`case retouch`**——kind 名表达层的语义（修复层），而非像素
  实现形态。`raster`（烘焙像素层）是另一个未来概念，v1 无消费者，不增设。
- **理由**：C1 语义里用户面对的是「修复层」（heal/clone 可整体开关/重排/删除）；
  `retouch` 与 `adjustment` 同为用户语义命名，`raster` 是实现描述。
- **Reversibility**: reversible——`case raster` 未来可作 additive 扩展（enum 扩展
  永不重编，与 BlendMode 同纪律）。

## D-06-07-T1-2: stroke payload 拼写冻结（复用 06-03 MaskForm 拼写）

- **裁决**：`RetouchStroke` = `{id, algorithm(Int), form(MaskForm), source(MaskPoint?),
  opacity(Float), blurRadius(Float?), fillColor(SIMD3<Float>?)}`；sidecar 键名 `strokes`
  optional additive（06-01 记录壳不动）。`algorithm` raw 值 = **dt 槽位逐字**
  （retouch.c:66-71：clone=1/heal=2/blur=3/fill=4；NONE=0 不用）。
- **要点**：
  1. 形状复用已冻结的 06-03 `MaskForm` 拼写（ellipse/path）——**不为 stroke 形状造
     第二套形状词表**；v1 允许 kind = ellipse/path（append 门拒 brush/gradient）。
  2. `source` = 单个归一化「源区中心」：采样区 = stroke 形状平移至以 source 为中心
     （dt 允许任意源 form；translation-only 覆盖 clone/heal 工作流且使 ROI 扩窗精确）。
  3. 算法参数按需 optional（blurRadius 仅 blur、fillColor 仅 fill）——省缺省歧义。
- **冻结对照表**（encode 顺序无关，键名逐字）：
  ```
  {"kind":"retouch", "strokes":[{"id":uuid, "algorithm":1..4,
    "form":{...06-03 MaskForm 拼写...}, "source":{"x":..,"y":..}|absent,
    "opacity":f, "blurRadius":f|absent, "fillColor":[r,g,b]|absent}]}
  ```
- **Reversibility**: ONE-WAY——后续只加 optional 字段。

## D-06-07-T2-1: retouch 子 run 形态 = 驱动器 retouch 腿（非 PixelPipe 链）

- **裁决**：retouch 层在 `LayerCompositeDriver` 合成环内走专用腿：stroke 列表在
  accumulator（C_prev）上按序施加（mask 平面 → 替换内容 → masked paste），产出
  strokeOutput 后走与 adjustment 完全相同的 blend 三元组路径。
- **理由**：retouch 层无 iop 链——`runSub` 的 v50 walk/hash 链对空链是纯开销；
  stroke 管线的缓存键（输入前缀 ⊕ strokeListHash）语义与链输出一致且更精确
  （stroke 编辑只翻这条腿 + 上方前缀）。
- **Reversibility**: reversible（数据同构，改回子链实现不迁移数据）。

## D-06-07-T2-2: 源区∪目标 AABB 扩窗 = base 子 run 入口 hint 预扩（走 walk clamp）

- **裁决**：合成入口前对全部启用 retouch 层计算 `strokeExtent`（源∪目标 AABB，内容
  锚定经 `GeometryPointMapper.forward(normalized:)` 投影到合成 px），与 roiHint
  union 后作为 base 子 run 的 entry hint；walk 内 clamp 到帧。无 retouch 层或无
  源出窗 → hint 逐字不变（零改动面）。裁剪/采样越平面边界时 clamp（帧边 stroke 的
  dt 同款 roi clamp，retouch.c:3057-3060）。
- **红线兑现**：跨窗专项断言（RetouchParityTests
  .testCloneCrossWindowSourceExpansion）——hint 32px 窗、源在 48px 处：窗口扩至 57px、
  stroke 内部逐值 == 源平移 ≤1e-5、无黑边。
- **实测注记**：窗口化渲染与全幅渲染存在 decode 子域腿的 ±1px 裁剪圆整（04-01 seam
  既有特性，梯度斜率 0.011/px 量级；非 retouch 腿缺陷——同窗口内逐字节确定）。内容级
  断言门放宽到 2e-2 仅用于「windowed vs full」对照；stroke 语义断言保持 1e-5。
- **Reversibility**: reversible。

## D-06-07-T2-3: blur/heal 作用于 stroke AABB 裁剪（O(patch)，拒绝全平面模糊）

- **裁决**：blur = stroke bbox(+3σ halo) 裁剪 → RGBA Deriche 三遍（`retouch_blur_col/
  row/store`，dt `dt_gaussian_blur_4c` 形状）→ masked paste；heal = 同形 patch 对
  （目标/源 crop）→ Laplacian 解 → masked paste。clone 直接在窗口平面按 offset 采样
  （dt `_retouch_clone` 语义：采样演化中平面，非原始输入）。
- **理由**：FULL-fit 视图下全平面 blur 需要 2×1.63GB 工作平面，直接破 ≤3GB 预算；
  patch 裁剪 = dt `roi_mask_scaled` 同形（dt 本来就只在 patch 上做）。Deriche 系数
  与 MaskCombiner 同源（Core 不能 import IOP 的 GaussianBlur——MaskCombiner 先例，
  系数一致性由 `testMaskBlurCoeffsMatchIOPGaussianBlur` 跨检钉住）。
- **Reversibility**: reversible。

## D-06-07-T3-1: heal 基准判定 = **留 6-7 交付，不拆 6.5b**（D-06-CONTEXT-1 决策点）

- **基准实测**：`RetouchParityTests.testHealInteractionLatencyBenchmark`——160×120
  典型窗口化 patch（掩码椭圆、掩码像素 ≈ π·(30)²），GPU 红黑 SOR（`heal_laplace_step`
  每 dispatch 一个颜色半扫，ping-pong 两平面，误差原子累加 + batch=25 读回一次）：
  - 多轮实测 **median 9.99–11.63ms**（runs 9.29/9.54/9.99/11.63/11.98/12.13ms），
    PSO 预暖后计时 ×3 取中位。
- **判定**：median ≈ 10-12ms **<< 100ms 交互预算**（计划口径：具体门执行期按实测分布
  定，落本 DECISIONS——门定为 **25ms**（实测分布 ×2 上界 + 余量），低于 plan 的
  100ms 量级预算）。**heal 不拆 6.5b**；无用户确认待办（预算内交付，非降级）。
- **架构注记**：GPU 单步 dispatch + CPU 迭代循环按 plan 执行；dt 的 OpenCL 腿实际
  回落 CPU（heal.c:442 注记「reduction takes forever」）——本实现的红黑半扫并行化
  是 GPU 友好形态，且同色 cell 更新相互独立 ⇒ **与 dt 串行 GS 值语义逐步等价**。

## D-06-07-T3-2: heal 容差档 = <1e-3（vs 独立 float64 红黑 SOR 参考）

- **裁决**：parity 参考 = 测试内独立 float64 实现（heal.c 逐式：pattern = target −
  source；红黑 SOR，w = (2 − 1/(0.1575·√nmask + 0.8))·¼；ε = 0.1/255、err_exit =
  ε²w²； Dirichlet 外区不动；healed = source + solution）。参考**不提前退出**
  （全 2000 iter 收敛），GPU 侧 batch 均值门提前退出——门 <1e-3 界住两侧 ε 残差差。
- **实测**：24×18 patch，掩码内 max|GPU−ref| ≤1e-3 门全绿（compared>50；
  精确 maxErr 未单独落账，门内即达标）；外区逐值不动（pass-through 精确）。
- **Reversibility**: 门收紧方向可逆（参考已全收敛）。

## D-06-07-T4-1: retouch 交互路由 = 选中修复层即拥有视口（机器第 3 优先级）

- **裁决**：`viewportRoute(liquifyPanelSelected:retouchPanelSelected:)` 扩为
  mask > liquify > **retouch** > crop——选中修复层 = 修复面板为选中 Inspector 面 =
  RetouchOverlayHost 拥有视口（与 liquify 的「选中面板规则」同构）。源拾取 = 面板
  toggle（「拾取源点」）武装后下一次视口 tap 采样（dt ctrl-click 同语义）。
- **实测**：LayerUIWiringTests.testRetouchRouteOwnershipAndMutex 穷举四路由 +
  GUI 真机走查（加层 → 画 stroke → ⌘Z 恰回退，FINDINGS 06-07 节截图）。
- **Reversibility**: reversible。

## D-06-07-T5-1: stroke 腿缓存键 = (输入前缀 hash ⊕ strokeListHash) @ retouchPosition

- **裁决**：stroke 腿输出平面缓存于 `PipeCacheKey.retouchPosition`（-3，层链输出
  同驱逐档），upstreamHash = fold(前缀 hash, strokeListHash)（canonical sortedKeys
  JSON ⊕ StableHash，与 maskVersionHash 同纪律）。blend 三元组照旧 maskHash=0
  （NO_MASKS）+ 层 opacity/blend/blendOptions。
- **增量语义**：编辑上方层/参数 → retouch 腿输入不变 → 腿缓存 HIT（测试钉：
  testStrokeLegCacheAccounting）；stroke 编辑只翻本腿 + 上方前缀。
- **Reversibility**: reversible。

## 附：本轮 GUI-18 缺陷修复（非决策，归档指针）

zh-Hans catalog 标签致部分 zh-Hans.lproj 破坏运行时回退 → 全 app 裸键；修复 = 新键
统一 `zh` 标签。明细见 FINDINGS 06-07 节 + LESSONS L025。

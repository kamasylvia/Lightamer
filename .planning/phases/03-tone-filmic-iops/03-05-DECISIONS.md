# Plan 03-05 决策记录(checkpoint D-T3 + 实施期勘误)

状态:已定稿并按此实施(commit 0b4bc2a 之后)。plan autonomous 授权下按 RESEARCH §4 证据落定;用户可审阅推翻(reversible 项标注)。

## D-T3 分解语义(plan T3 checkpoint 三问)

1. **全局多频段(无蒙版)= 确认**。dt 默认模式即为全局(guidance 分解无 per-region);Phase 6 补 per-region。**Reversibility: costly** — kernel 图(luma→filter→apply)与参数面(无蒙版输入)按此定型;Phase 6 蒙版是在此之上加 per-region 输入,不改 kernel 图结构。
2. **golden 两档验收顺序 = 确认**:①`details=none`(无滤波直通)<1e-5;②EIGF(dt 默认)<1e-4 + ΔE p99<1.0。CPU(dt)与 Metal 归约顺序不同,EIGF 禁用 1e-5 硬闸(RESEARCH Risk #7)。默认参数(details=EIGF)与验收顺序解耦。**Reversibility: reversible** — 容差是测试常量。
3. **FULL 分块 overlap = max(radius, 1) + halo(1) = 确认**。radius 按 dt `modify_roi_in`(toneequal.c:1352-1357):`diameter = blending% × max(piece 全图宽,高) × roi.scale;radius = (diameter−1)/2`。halo 1 px 覆盖 bilinear/量化边缘舍入。**Reversibility: reversible** — overlap 是 TilingPlan 参数。

## 源码核对勘误(实施前逐文件核对,plan 文本 vs dt 树 dc58cf0ba1)

| plan 文本 | 源码事实 | 处置 |
|---|---|---|
| `guided_filter.cl` 8 kernel 直译 | `guided_filter.cl` 是**彩色** guided filter(`guidedfilter` iop/去噪用);toneequal 的 CPU 路径是 `eigf.h` `fast_eigf_surface_blur`(EIGF,**Gaussian** 非 box)+ `fast_guided_filter.h` `fast_surface_blur`(guided 档,box mean)。dt 本体 toneequal 无 OpenCL(:313 TODO) | 移植对象改为 dt 真实数学:eigf.h + fast_guided_filter.h + box_filters.cc;kernel 群仍按「分离盒式 box_mean_x/y + variance/solve + blend」分解(与 guided_filter.cl 同构的 kernel 拓扑),公式逐式对齐 CPU 源 |
| EIGF「exposure 权重项补进 solve 段」 | EIGF 差异 = 方差用 `variance/(pixel²)` 归一比值(eigf.h `eigf_blending_no_mask`)+ **去掉 final spatial averaging**(eigf.h 文档段)+ Gaussian 模糊替代 box | `toneeq_blend` kernel mode 0/1 逐式实现 |
| 「9 估计器」 | `luminance_mask.h` 枚举 = **7**(MEAN/LIGHTNESS/VALUE/NORM_1/NORM_2/NORM_POWER/GEOMEAN) | 7 个全落;9 指 user bands |
| 「10001 点 LUT」 | `correction_lut[PIXEL_CHAN × LUT_RESOLUTION + 1]` = **80001**(8 EV × 10k/EV + 1) | 80001;apply 索引 `round((clamp(log2(luma),−8,0)+8)×10000)` |
| LUT 控制点直取 9 参数 | 9 带线性增益先经 **9×8 最小二乘投影**(正规方程 + Float Cholesky,choleski.h)得 8 个 RBF 权重 | CorrectionLUT.pseudoSolve Float 逐式直译 |
| feathering 直接用 | commit **反转**:`d->feathering = 1/p->feathering`(:1617) | Derived.feathering 取倒数 |
| apply 乘 RGB | `for_each_channel` = **4 通道**(alpha 也乘 correction,dt quirk) | 逐字跟随(golden 对比需要) |
| 全 0 参数 = 恒等 | RBF 拟合留 ~1.8e-2 纹波(非精确恒等;dt 同) | golden 默认档两侧同公式,parity 不受影响;测试钉纹波包络 |

## EIGF Gaussian bounds 等价性论证(GPU 无读回)

dt_gaussian 的 `CLAMPF(in, Labmin, Labmax)`(gaussian.c:283+)施加在**输入样本**上,且 EIGF 传入的 bounds = 数据实际 per-channel min/max(eigf.h `eigf_variance_analysis` 先扫全图)——即对有限数据**永不触发**(纯 NaN/inf 保险)。GPU 侧用常量 bounds `(exp2(−16), FLT_MAX)`(luma 平面下界由 linear_contrast 的 MIN_FLOAT floor 保证)与 dt 点位等价,免去 GPU min/max 归约 + CPU 读回往返(PREVIEW 预算)。

## PSO 特化选型(T2 记录,plan Artifacts 要求)

luma estimator 用 **uniform 分支**,不用 `[[function_constant]]` PSO 特化:7 method × 其余维度会乘爆 256 项 PSO LRU(METAL-5),换来的是可预测 1-cycle 分支。金标:none 档 perf 断言不依赖此(元素级带宽约束)。

## tiling 接缝(实现形态,T6)

- `IOPModule` 协议 extension 新默认缝:`tileHalo(roi:piece:) -> Int`(0 = 永不分块)+ `tileWorkingSetBytesPerPixel(piece:) -> Int`;`ModuleBoxing` 加 erased 转发。默认 0 = 现有模块零破坏。
- `PixelPipe.processRec`:FULL + 模块声明工作集超预算时,上游整图渲染一次 → `TilingPlan.tiles`(bytesPerPixel = 模块工作集)→ 每 tile:readRect = tile 外扩 halo → 模块在 readRect 尺寸平面上整幅语义执行(模块无感知,边界数据真实存在)→ blit 裁回整图输出。
- 模块 radius 语义:`piece.dscIn` 由 pipe 在 run() stamp 为**整图**几何(dt `piece->iwidth` 同构)——tile 不改变 radius,与 dt zoom-pad 行为一致。

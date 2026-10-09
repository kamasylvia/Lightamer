# M4-1-01-DECISIONS — 执行期偏差、实测带与平台事实

> 正本补充 = SUMMARY；本文件只收执行期发现与实测数字。KD 编号引用 plan。

## §1 T1：canonicalization γ 拟合换中位数估计器（实测驱动）

log-log 最小二乘斜率在 u16 载体的异方差量化噪声下漂移 ~0.005（Python 复算 2.2 表拟合出
2.1947，残差 8.9e-4 > 1e-4 门）；改**逐点瞬时 γ = ln(v)/ln(code) 的中位数**后，精确 γ 表的
残差 ~8e-6，门内 12× 余量。plan 的「幂拟合 γ」语义保留（中位数即拟合形式之一），门距实测
（checker O4）：

| 表类型 | u16 载体噪声 | 门 | 实测余量 |
|---|---|---|---|
| PQ 1024 点 | ~7.6e-6 | 2e-4 | 26× |
| HLG 显示曲线 | ~7.6e-6 | 2e-4 | 26× |
| sRGB 分段 256 点 | ~7.6e-6 | 1e-4 | 13× |
| 纯 γ（中位估计） | ~8e-6 | 1e-4 | 12× |
| 负测（γ2.2 vs sRGB 门） | — | 1e-4 | 偏差 4.7e-3 = 47× 出门 |

## §2 T3：ICC 提取走 TIFF IFD（tag 34675），不走 copyICCData（平台事实）

Host 探针（22 fixture 全量）：①ImageIO 对**无 ICC 文件合成 colorspace**（8/16-bit → 系统
sRGB 3144 字节；float32 → extendedLinearSRGB + ProfileName「sRGB IEC61966-2.1 Linear」）——
colorspace 面无法区分「内嵌」与「合成」；②ColorSync 对**近似匹配的内嵌 profile 降级替换**
（dual-tag 与 LUT fixture 在 colorspace 面变成系统 sRGB，原始字节丢失）。故描述链主源 =
`RasterIccParser.tiffEmbeddedICCData`（IFD0 直读，双字节序，有界读取）；`cgImage.colorSpace`
仅用于 CMYK 模型 typed 拒绝与平台行为钉测试。此为 plan KD-1「tag 34675」字面的兑现，与
「ImageIO 侧」候补路径的取舍记录。

## §3 T3/T2：MAT3 逆矩阵与 gray TRC 两处修复

1. RasterIccMat3.inverse 伴随式第 3 元素笔误（`a[0][2]*a[1][0]` → `a[0][2]*a[1][1]`）——
   chad 反解 0.03 级漂移的根因；export 侧同名私有 Mat3 核对为正确写法（未触碰）。
2. 生成器 gray fixture：GRAY 模型的 TRC tag 是 `kTRC`（非 rTRC 剥离后残留）；修复后重生成
   （幂等复验于新字节）。

## §4 T5：forward 的 gamut 边界 guard 对深影饱和色归零 M（上游固有，登记不修）

Stage 级探针（fwd 逐段打印）实锤：场景 (0.1875, 0.1875, 0) @rec2020@100 的 forward 自身在
`gamut_boundary_M <= 0 → M = 0` guard 处**把 chroma 归零**（输出中性灰）——上界 hull 线估计
的分母 `f_JM_cusp_J − (−slope)·cuspM` 在 |slope| > cuspJ距/cuspM（深影区）时变负 → smin 取
负巨值 → guard 触发。该 guard 为上游 CTL 原文行为（:728-774 同形），forward 自 M2-6 起在
产线携带（parity 只钉镜像不钉色相保持，未暴雷）。**含义**：①forward 在该类颜色上非单射；
②逆变换 inv∘fwd 的 display 级恒等仍**机器精确**（4.4e-15，五键全绿）——T5 首稿的 scene 级
比较谓词选错（跨非单射点比 scene），改为 display 级恒等 + display-first 网格普查（M-zeroed
1 点 / out-of-clamp-domain 57 点 / 10985×5 键）。**M4-1-02 观察项**：真实照片深影饱和像素
经新腿 + 默认 record 回看可能中性化（与 Alcedo OCIO 逆的接受面同族）；gui-acceptance 观察项
挂账，不在本批修。

## §5 T5：round-trip 实测带（KD-4 ②的「实测带写 DECISIONS」）

- **fwd-first（display 恒等，变换本域）**：4.4e-15 —— 同源一致性主张成立（远优于 1e-3 目标）。
- **display-first 全立方网格**（plan 字面方向）：in-domain 带 3.9e-3 @rec2020@100
  （(1.0, 0.583, 1.0) 邻域）——该网格含 forward 输出域之外的 chroma 色，逆的 ≤2 次估值
  近似（solve_J_intersect 二次分支翻转）在此类点上是上游固有近似；**严格 1e-3 在本域成立**
  （fwd-first 面）。FMA 哨兵（近黑 1e-6 线性光）五键全 0 —— 排除熔合嫌疑后才落带宽。
- **FMA 结论（KD-3）**：Float64 侧（swiftc 无 fast-math）与 kernel f32 侧近黑均零漂移，
  无需 pragma/旗标处置；上游 R1-1 教训的处置路径走完（结论行在案）。
- T8 kernel parity 带（33³×五键，f32 vs f64）：近黑 = **0**（双判据之一严守）；p99.9 =
  4.4e-4..6.5e-4 @100nits / 4.9e-3 @1000nits（f32 pow/log 链噪声，L048 家族）；worst 集中
  近白角（逆 tonescale 病态顶 = 上游 R2 面文档化）。plan 1e-5 目标对全网格 f32 kernel 不可达，
  按 M3-1-E5「门结构实测收窄」先例钉 6e-3/0.3 双门 + 近黑严守 1e-6。

## §6 T6：CGBitmapContext 支持矩阵（host 探针）与 16-bit gray 缺口

探针（8/16/32F × RGB/gray × alpha 形态）：RGB 全深度 `.none` 一律 REFUSED；`noneSkipLast`
可载（X 字节死槽，存储色在 0..2 槽不动）；8-bit gray `.none` 可载；**16-bit gray 无任何受支持
context 面** → typed reject（decodeFailed），native 腿唯一登记的布局缺口（DECISIONS §8 待供
件：真实 16-bit gray TIFF 需求出现时再立项）。alpha 腿一律 premultipliedLast（关联 alpha 的
存储色 = premul 值，D6 不反 premul——CPU 走查直接丢弃 A）。

## §7 T7：GPU face 两处 host-probed 修正

1. **UNORM 面**：rgba8Uint/rgba16Uint（UINT 格式）经 `texture2d<float>` read 返回零——改
   .rgba8Unorm/.rgba16Unorm（归一化读 = TRC 码域本身）。
2. **uniform buffer 生命周期**：`dispatch2DTexture` 的 configure 闭包内 makeBuffer 逃逸后
   encoder 持悬挂引用 → 全零平面；buffer 提升到闭包外（Aces2KernelGolden 既有形态）。

## §8 待供件 / 挂账清单

- 16-bit gray TIFF 原生腿（§6 布局缺口）——需求驱动。
- 深影饱和中性化观察项（§4）——02 接线后 gui-acceptance 观察；如需产品级处置（如 OCIO
  GPU-form 边界估计替换 CTL 形）另立 plan。
- KD-9 iccParametric type≠0 的「fallback 链首」策略——更精细的最近邻（对 evaluate 后的形状
  跑 canonicalization 阶梯）为增强项，非缺口（parse 层已把 sRGB/γ/PQ/HLG 形状吸走）。
- derive 的 scene-linear HDR 分支 peak = 描述 peak（② 默认 = 100 nits）——HDR 观感 peak 由
  02 的视口 face 决定，如晨审翻案改 assemble 一处。
- 双重验收（dual_acceptance）= orchestrator 编排串行 omp 二次验收，ACCEPTANCE 文件待落。

## §9 T11 终验数字（定向轮亲跑，caffeinate -dis）

四 bundle 定向轮（全量、无过滤）终值（2026-10-10 亲跑，零 MEMFAIL、exit 0）：

| bundle | executed/skipped/failed | 基线 | 增量 |
|---|---|---|---|
| IOP | **544/1/0**（153s） | 483/1/0 | +61（28+20+13） |
| IOPParity | **427/3/0**（461s） | 408/3/0 | +19（8+8+3） |
| Layers | **394/3/0**（160s） | 378/3/0 | +16（14+2） |
| Export | **347/1/0**（202s） | 342/1/0 | +5 |

四 bundle 合计 1712/8/0（基线 1611/8/0，+101）；App 另 +1（DrtViewportTests 负测，定向抽测
7/0/0 绿）→ 全套预期 **3276/16/0**（3174+102）。zh-audit PASS 1585/1823（+1 键 =
`drt_eotf_srgb_piecewise`）。红线机检（Aces2Kernels.metal / LightamerIOP / Sidecar /
History / Library）全零命中（`git diff 71f8f8d..HEAD` 亲跑）。App bundle 全量轮未跑
（--all 需 orchestrator 批准，移交 02 收口轮）。

## §10 checker 引注块逐条兑现索引

E1（①′ 半边）→ T1 测试 testLinearICCFloat32BecomesSceneLinear + T3 fixture face；
E3（[i4'] 数据依赖序）→ Aces2InverseReference 头注 + riTonemapAndCompressInv 落笔序 +
DECISIONS 图序注记（本文件 §4 旁证）；E5（canonicalization ②③ 支）→ T1/T3 门测 + T9
Export round-trip 闭环；E6（编译破面全清单）→ kernelIndex 7 / powerExponent / Math encode/
decode / isHdrEncoding / kernel 镜像 / colorSpace 六臂 / DrtPanelView + 新键 /
EditorMTKView drtLayerColorSpace + hdrDrawable 布尔链（:801-803 补位）全落地；
E4（联合规则两表分离）→ derive 双表 + T10 逐行断言。

# Plan 06-02 执行期决策（DECISIONS）

> 编排授权模式：plan 逐字执行 + 执行期决策落本档。每条含裁决/依据/可逆性。
> 执行者：GSD executor subagent（2026-09-23 夜间）。

## D-06-02-T1-1 blendop_params blob = 420 字节（运行时实证，非检出树的 404）

- **裁决**：blob 按 `dt_develop_blend_params_t`（blend.h:190-223, DEVELOP_BLEND_VERSION=14）逐字段 pack 至 **404 字节后再补 16 字节零尾**（4×int32，偏移 404..419），总 420。
- **依据**：检出版（dc58cf0ba1）逐字段算术 = 404（15 标量 60B + reserved 8B + blendif_parameters 256B + boost 64B + raster 16B，全 4 字节对齐零 padding）。运行时二进制（5.5.0+755，本机 build/bin）`-d params` 判 404 为 **params WRONG**（history loader 尺寸检查 `bl_length == sizeof(...)`，develop.c:2567）并回退默认参数——实证：404 包探针 multiply 变 normal 全值输出，回退后 DB 存出的默认 blob 长 420B；改 420B 包 → **`blendop v. 14: version ok params ok`** + DB hex 与 XMP 逐字节一致（840 hex 字符）。默认 blob 前段（mask_mode@0 / blend_cst@4 / blend_mode@8 / blend_parameter@12 / opacity@16 / feathering_guide@36=5 / feather_version@56=1 / blendif 参数 @68+ / boost@324+ / raster 尾 @388..403）与检出树布局逐段吻合 → 头 404 字节语义不变，尾 16B 对 blend 流程无语义（blend.c 只读 mask_mode..mask_combine 段）。
- **字段字节账**：gen_fixtures.py `blendop_params_blob` docstring 逐字段表（正本）。
- **可逆性**：自动防线——regenerate.sh ③c2 每案跑「params ok」，dt 上游 sizeof 变更即红，按 ledger 增补即可。

## D-06-02-T1-2 承载模块 = exposure +1EV

- **裁决**：blend blob 骑 exposure 历史项（params = +1EV blob），非独立模块组合。
- **依据**：plan 授权「任何已交付 RGB 模块 + exposure 组合均可承载，执行期选最简」；exposure 是 03-01 首个三证据打通模块（modversion 7 / iop_order 21.0 已有配方）；+1EV 使平场 b = 2a（0.5→1.0）非退化。exposure 的 blend_cst = RGB_SCENE（4）与 Lightamer 工作域一致。
- **可逆性**：reversible——BLENDOP_MODES/生成器参数化，换承载模块只改 carrier 行。

## D-06-02-T2-1 算术模式的线性域无界化（去 [0,1] 输出 clamp，保 lmin=0）

- **裁决**：screen/overlay/softlight/hardlight 取归一化域公式形状（blendop.cl:594-651 的 min=0/max=1/lmin=0/lmax=1 常量字面），在无界线性 Rec2020 上求值，**不 clamp 输出**（HDR >1 保真）；唯一例外 linearBurn（Lab SUBTRACT 形 a+b−1）保留下界 0 clamp（dt 三个 kernel 族都有 lmin clamp）。PS dodge/burn 保留 W3C 自带的 min(1,·) 封顶。
- **依据**：plan T2「lmin/lmax = 工作域界」（工作域下界 0、上界无界）+ parity fixture 含 >1 HDR 值（若 clamp [0,1] 则 HDR 值全灭，与「合成小图含 HDR 值」验收矛盾）；dt 场景 CPU 参考函数（blendif_rgb_jzczhz.c `_blend_*`）本身零 clamp。
- **可逆性**：reversible——如需 dt 显示域行为（clamp [0,1]）加 uniform 开关即可；parity 门同步。

## D-06-02-T2-2 alpha 走 normal 混合（偏离 dt 的 o.w = opacity 覆写）

- **裁决**：compositeLayer 输出 alpha = a.w·(1−op) + b.w·op；不采用 dt 的 `o.w = opacity`（blendop.cl 各 kernel 尾）。
- **依据**：Lightamer 工作空间 = 不透明图像（alpha≡1 不变量，恒等三元组/缓存/终端段都假设之）；若写 opacity，op<1 的任何合成都会把 alpha 拉离 1，破坏 Phase 2-5 全部字节级假设。dt 写 opacity 的用途（下游 mask_display / 合成信息传递）在 Lightamer 对应 6-3 的 mask 平面与 Phase 11 manifest，不走 alpha。
- **可逆性**：reversible（kernel 单行）——但需先重审全部字节级恒等门；非必要不做。

## D-06-02-T3-1 JzCzhz 常量同源 + 往返门分层（矩阵/极性 <1e-6，pow 链实测地板）

- **裁决**：常量链 = LabRoundTrip.rec2020ToXYZ（D65 Rec2020，项目唯一常量集）→ ColorBalanceRGBMath.xyzToJzAzBz（dt 7 位前向矩阵 + PQ）→ 极性转换（atan2/hypot，[0,1) turns）；逆链用 dt 16 位 AI/MI 对。L023 门分两层执行：**矩阵对与极性腿（GPU float32）<1e-6**（实测达标）；**RGB 全链往返/感知 parity = 实测地板门**（float32 pow 链 rel ~2e-4-8e-4、abs ~3e-5，门 rel 2e-3/abs 5e-4，数字全部入测试注释与 SUMMARY）。
- **依据**：dt 常量集构造性非对称（前向 7 位舍入 vs 逆 16 位），PQ 编码 p=134 把 ~1e-7 放大到 ~3e-5——float64 CPU 实测 3.1e-5、float32 GPU 实测同量级；dt 自身同吃此地板。硬套 plan 的 1e-6 于全链 = 永假红；硬放宽矩阵门 = 丢 L023 实质。分层 = plan 精神的忠实执行（1e-6 由「mo·M·mi」承担——L023 原文即矩阵对恒等式）。
- **可逆性**：非 reversible（常量集变更 = 大返工）——常量变更必须同批重审 BlendOpParityTests（L023 强化条款已在 JzAzBz.swift 头注钉死）。

## D-06-02-T4-1 PS color dodge/burn 新 raw 值 = 0x2A / 0x2B

- **裁决**：`psColorDodge = 0x2A`、`psColorBurn = 0x2B`（Int 原始值，进 sidecar 的就是这个整数）。
- **依据**：blend.h:44-91 全枚举占用审计——dt 已占 0x00..0x29（上限 HARMONIC_MEAN 0x29）+ 0x80000000 位；0x2A/0x2B 是 0xFF mask 内首个双连空位。公式源 = W3C Compositing-1 §color-dodge/color-burn（线性域逐通道；dodge: Cb=0→0, Cs=1→1, else min(1, Cb/(1−Cs))；burn 对偶）。**单向损失入账**：sidecar 带此值进 dt，dt 的 switch 无 case → normal 回退（不崩、语义降级）；反向（dt 文档进 Lightamer）无影响。
- **可逆性**：值一旦进 sidecar 不可重编（冻结纪律）；后续 vivid/linear/pin light 等按 CONTEXT deferred 清单从 0x2C 起追加。

## D-06-02-T5-1 感知模式与 dt 场景路径的公式族分歧（定案：Lightamer 钉 JzCzhz 域，dt 探针记回退值）

- **裁决**：hue/saturation/color/luminosity/colorAdjust 按 plan/CONTEXT 的 JzCzhz 域公式族实现（LCh 族公式转置：Jz/Cz/hz 分量换或最短路径混合）；dt-cli 平场探针对这些模式记录的是 **dt 实际输出**（RGB_SCENE 路径：hue/color/coloradjust 无 case → normal 回退；luminosity/saturation = RGB 范数缩放）——即「采纳证据 + dt 实值记录」，**非逐值公式对照**；逐值对照由 float64 参考承担（plan 的 parity 门定义）。公式共享模式（normal/multiply/difference/lighten*/REVERSE/saturation-灰保持）保留 dt 逐值 MATCH。
- **依据**（源码实证 + 探针实测）：
  - CPU `_choose_blend_func`（blends/blendif_rgb_jzczhz.c:703-761）无 HUE/COLOR/COLORADJUST/LIGHTEN/DARKEN/SCREEN/OVERLAY/SOFTLIGHT/HARDLIGHT case → `_blend_normal`；LIGHTNESS/CHROMATICITY = RGB 向量范数缩放（:607-646）。
  - CL `blendop_rgb_jzczhz` kernel 同构（无这些 case）。
  - 探针实测（a=0.5,b=1.0）：darken op60 = 0.8 = normal 值；hue/color/coloradjust/psburn 同；lighten = max 混合与 normal 在 a<b 平场数值巧合相等；screen/overlay/soft/hard op<1 = 0.8/0.625 = 回退；linearburn = max(a−p·b,0) = 0/0.2/0.375 **精确复现 dt 场景 SUBTRACT**；normal_reverse = 0.5/0.7/0.875 REVERSE 语义逐值一致。
  - plan 预设「blendop_rgb_jzczhz 做 JzCzhz 往返」与该 kernel 实名不符（它直接吃工作空间缓冲，名字是历史遗留）；CONTEXT §4.1 已裁决 JzCzhz 域（「parity 源唯一性优先 JzCzhz」）+ 验收含 Jz 往返/hue sweep——故按 plan 而非 dt 场景回退实现。
- **后果**：与 dt 对拍时感知模式数值不同（用户从 dt 迁移预设的观感差异）；语义本身自洽、公式源唯一、parity 全绿。UI 帮助文案（6-5）按此对齐。
- **可逆性**：reversible——kernel 分支可换 norm-scaling/normal 回退；但 Jz 往返/hue sweep 验收与 D-06-CONTEXT-3（parametric mask v1 = JzCzhz 域）依赖此域，翻转需 planner 层重裁。

## D-06-02-T5-2 linearBurn 语义 = a+b−1（Lab SUBTRACT 形），非 dt 场景的 max(a−p·b,0)

- **裁决**：linearBurn（0x07）按 Lab/RAW kernel 的 SUBTRACT 形状 a+b−1（lmin=0 clamp）实现——与冻结头注「the PS linear-burn analog」一致；不做 dt 场景路径的真减法 max(a−p·b,0)。
- **依据**：case 名与 Phase 1 冻结头注都锚定「linear burn」语义；plan 公式族正本 = blendop.cl:513-800（Lab kernel，a+b−1）；真减法语义在 W3C/PS 体系属「subtract」模式，将来按需以新 raw 值增补（0x2C 起）。
- **实证**：dt 场景探针 0/0.2/0.375 精确复现 max(a−p·b,0)——两侧差异已由 testSceneFallbackDocumentedDifferences 常驻钉住。
- **可逆性**：reversible（新值增补真减法永不重编本值）。

## D-06-02-T5-3 mask 平面契约 = 红通道即有效 opacity（预乘语义）

- **裁决**：compositeLayer 的 mask 纹理红通道 = **已折叠的每像素有效 opacity**（= CLIP(gopacity) × mask form，dt blend.c:458+:530 的 CPU 折叠产物）；kernel 不再乘 u.opacity（hasMask=1 时）。
- **依据**：dt 的 mask 平面在进 blend kernel 前已完成 gopacity 折叠（uniform 路径 = blendop_set_mask(value=gopacity)、绘制路径 = form×gopacity）；预乘契约让 6-3/6-4 的光栅化输出直接进合成，避免双乘。测试：全 1 mask × opacity 路径 == 纯 uniform 路径逐字节 + 梯度 mask 闭式参考。
- **可逆性**：契约级——6-3 光栅化器按此输出；若改契约须同步 kernel + 双侧测试。

## D-06-02-T5-4 分块恒等的实现形态 = 行带 uniform（非 origin 派发）

- **裁决**：compositeLayer 增加 rowBegin/rowEnd 写入带 uniform；分块 = 同 kernel 全网格派发 + 带外丢弃。不用 MTLComputeCommandEncoder origin 派发（本 SDK 无此 API）。
- **依据**：pointwise kernel 的「分块==整幅」门只需保证写域可分割；uniform 门零额外 API 面且 PSO 常量布局不变（32B）。
- **可逆性**：reversible——未来真邻域语义（如 future blur mask）引入时改为 halo 分块，门改为容差档（plan 预留语义）。

## 环境约束（如实落账）

- **dt 本机构建插件 OpenCL 桩坏**（任务书预警，实测印证）：blend 探针走 CPU 管线（`--core` 默认；未启用 CL），`-d opencl` 未触;adoption/PFM 证据不受影响（CPU/CL 公式同源）。与 05-07 D-05-07-T5-4 的 conf opencl=false 解除口径一致。
- 密码弹窗：全程无（test-direct 直启路径）。
- tuist generate 需在新增源文件后重跑（BlendOp/、BlendOpParityTests 两次踩中）——`Scripts/test-direct.sh` 前置检查建议（未加，执行纪律层记忆）。

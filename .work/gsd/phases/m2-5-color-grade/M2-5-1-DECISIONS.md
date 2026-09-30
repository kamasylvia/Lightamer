# M2-5-1 DECISIONS — 执行期签注（2026-09-30 夜间批）

> plan = M2-5-1-PLAN.md（checker 修正版 87c039d）。本文记录执行期钉死的四个精读悬决点终式 + 各项偏差签注。语义忠实优先级：Alcedo 源码（GPL 只读，代码零复制）> plan 假设。

## 一、四个执行期精读悬决点终式

### D1. LGG kernel 终式（KD-6 悬决点；源 = primary_grade.metal behavior 11 + adjustment_runtime.cpp:242-255）

- **Runtime 装配**：values[i·4..i·4+3] = lift/gamma/gain 依次的 `colorOffset.xyz + luminanceOffset`。**disc/strength 不进 runtime 装配**（trackball UI 态，不达像素）；**gain.luminanceOffset 被 Alcedo 装配但 kernel 不消费**——两者均照抄（不动"更正确"）。
- **Kernel 终式**（ACEScc 域）：
  `gammaLeg.ch = max(gamma.color.ch + gamma.luma, 1e-4)`；
  `out.ch = sign(c.ch) · |c.ch + lift.color.ch + lift.luma|^(1/gammaLeg.ch) · gain.color.ch`。
- **IsIdentity 判定式**（color_wheel_model.cpp 逐条对应）：lift 全零（disc/colorOffset/luminanceOffset）且 gamma/gain colorOffset == (1,1,1)；gamma/gain 的 disc/strength/luminanceOffset **不参与**。identity 走 CPU flag 早退，像素容差 0。

### D2. Contrast 公式终式（KD-5 悬决点；源 = primary_grade.metal behavior 2 / cuda_primary_grade_pass.cu ApplyOkLabContrast）

- **0.3.0 语义 = OkLab lightness S 曲线**（工作假设"luma 轴幂曲线"不成立，以下为源码实测式）：
  `slope = 2^(contrast/100)`；`shape = L > 0 ? tanh(3·log2(L/0.5646216)/2.5) : −1`（pivot = cbrt(0.18)）；`gain = 2^((slope−1)·2.5·shape/3)`；`chromaScale = √slope·min(gain, 1)`；`(L,a,b) ← (L·gain, a·chromaScale, b·chromaScale)`；全程 ACEScc decode → linear AP1 → OkLab → 曲线 → 逆变换 → encode。
- **AC6 度量基签注**：色相保持度量改用 **OkLab hue（atan2(b,a)）**——公式对 a/b 同比缩放，OkLab hue 严格不变；plan 字面的"HSL hue"是 linear RGB 的另一种色相基，对忠实公式也有 2–4° 固有漂移，不是算子的色相基。luma 单调性照 AC6 保持。
- contrast 0 = CPU flag 早退（Alcedo `value != 0` 同款），像素容差 0。

### D3. White/Black 端点式终式（KD-5 悬决点；源 = behavior 3/4）

- **White**（behavior 3）：`gain = 1 + max(value, 0)·0.005`，三通道同乘（**ACEScc 域值直接乘**——Alcedo 实测语义，负半区 max() 恒等式成立，CPU flag 早退覆盖 value ≤ 0）。
- **Black**（behavior 4）：`offset = value·0.001`，三通道同加（ACEScc 域）；0 = flag 早退。
- 端点有界断言：±100 对全极端场无 NaN/Inf（kernel 与参考双侧）。

### D4. HLS 单 target 映射 + 权重窗终式（KD-7/OQ-6 悬决点；源 = editor_hls_model.cpp + editor_support/modules/hls.hpp + behavior 8）

- **权重窗 = Gaussian `2^(−d²/w²)`，非 plan 假设的 raised-cosine**（d = 圆周色相距，w = max(h_range_table[i], 1)）。KD-7 "以 Alcedo 为准" 条款生效，测试按 Gaussian 钉。
- **applyTargetEdit 终式**（saveActiveProfile + currentHlsWrite 合并语义）：
  `adjTable[bin] = {clamp(dh, ±30), clamp(dl, ±100)/1000, clamp(ds, ±100)/1000}`；
  `hlsAdj = adjTable[bin]`；`hRange = hRangeTable[bin]`（同步不改动）；
  `targetHls = {hueBins[bin], 0.5, 0.5}`（UI 常数 kFixedTargetLightness/Saturation = 0.5——**注意 model pristine 默认是 {0, 0.5, 1}**，UI 写入恒覆盖为 {hue, 0.5, 0.5}）；`lRange = sRange = 1.0`（UI 常数 kFixedLightness/SaturationRange = 1.0，同样覆盖 model 默认 0.1）。UI 写入的 l/s_range 是惰性字段（kernel 不消费）。
- **YIQ 旋转终式**：`angle = adj_h·2.25·π/180`；`scale = 2^(adj_s·2.25·(adj_s ≥ 0 ? 4.5 : 3.25))`；`luma += adj_l·1.125`（AP1 luma 权 0.272229/0.674082/0.053689）；i/q = NTSC 系数（0.596/−0.274/−0.322；0.211/−0.523/0.312），重构 0.956/0.621/−0.272/−0.647/−1.106/1.703。

## 二、KD-3 v50 终值挪位签注

- **black：42.0 → 41.95**（KD-3 ±0.05 挪位条款）。理由：42.0 与未注册 dt 行 `rgbcurve` 42.0 同位；KD-3 声明的同位例外仅 colorWheels↔colorbalance 一处，black 不得再开例外。相对序保持 white(41.8) < black(41.95) < rgbcurve(42.0)。
- 其余九行照 plan 终值落位：acesccIn 20.5 / acesccOut 69.9 / colorWheels 41.0 / cat02WhiteBalance 41.4 / contrast 41.6 / white 41.8 / saturation 42.2 / tint 42.4 / hls 42.6。
- colorWheels↔colorbalance 41.0 同位 = 声明例外（28.5 簇先例；dt colorbalance 无 Lightamer 模块；未来若启用 dt colorbalance，届时重排是彼 plan 的事）。

## 三、checker E7 完备性公式的执行解读（签注）

plan 字面 `default face ∖（18 目录 op 集 ∪ {testgain}）= ∅` **不可满足**：default face 故意携带 18 目录之外的 D6 时代 grade 收纳面（colisa/toneequal/levels/colorzones/velvia/monochrome/skinSmooth/colorbalancergb/channelmixer×2/colorcontrast/vignette/grain/bloom/dehaze/highpass/soften/localContrast/equalizer 等——M2-4 宽限表的 default 臂遗产，故意不入 18 目录封闭集）。按公式意图落为三个可真断言：(a) 对齐九件（五既有 + 四 DRT/Post）已在 default face 注册；(b) 新七件随各自实现 commit 注册，T7 后全 18 目录 op ∈ face（后续 plan 的严格面收窄前提）；(c) testgain = DEBUG-only 注册豁免（Registry.swift `#if DEBUG`，Release face 不含），断言旁已注明防"漏登"误读。GradeCatalogTests 承载。

## 四、checker m5 对齐五件 identity no-op 参数点核验表

| 目录项 | op | identity 快照（kernel no-op 点） | 面板默认（Params() 默认值） | 分立? |
|---|---|---|---|---|
| exposure | exposure | `{mode:manual, black:0, exposure:0, …}`（0 EV 恒等） | 同左（exposure 0 = identity，无分立） | 否 |
| shadows | shadhi | `{shadows:0, highlights:0, …}`（overlay opacity 0 = 恒等） | `{shadows:50, highlights:−50, …}`（工作点） | **是**（断言钉两值不等） |
| highlights | shadhi | 同上（同一快照） | 同上 | **是** |
| curve | tonecurve | `Params()`（默认平/恒等曲线） | 同左 | 否 |
| vibrance | vibrance | `{amount:0}` | 同左 | 否 |
| lmt | lut3d | `{lutName:nil}`（blit 恒等） | 同左 | 否 |

其余新七件 identity = 各自 Params()（isIdentity 判定式机检在册）；halation/filmGrain（DRT/Post 四件之二）identity = strength 0（非模块默认——bloom/grain 默认非恒等故 seed DISABLED，快照 = no-op 点）。

## 五、checker E2 既有层链像素断言盘点表

| 测试 | 层链内容 | 包夹面? | 断言 | 结论 |
|---|---|---|---|---|
| ExportPipeTests（composite export） | 层链含 exposure +1EV | **是**（进 envelope） | 仅尺寸/像素格式/管道缓存零字节 | **保持**——无像素断言，零放宽 |
| ExportRendererE2ETests | exposure 记录在 **base 链**（sidecar→instances） | 否（base 不包夹） | 尺寸/ICC/DPI/字节不等（sidecar 消费证据） | **保持** |
| LayerCompositeTests 全部 | 层链 = TestGain（非目录件） | 否（E2 收窄跳过） | 字节精确 vs flat run | **保持**（本轮全绿 = 逐字节不变证明） |
| LayerCacheTests / LayerE2ERoundTrip / Mask* 系列 | TestGain / 空链 | 否 | 缓存/字节断言 | **保持** |
| 其余含目录 op 的测试（PasteSemantics/MetadataService/BeforeAfter/McpEditingToolset 等） | 纯 record/历史语义，无层子 run | 否 | — | **保持** |

**净结论：零断言放宽、零静默改**。语义备忘：五既有件（exposure/shadhi/vibrance/tonecurve/lut3d）的 kernel 是域盲的——非 identity 参数的层链进入包夹后其 kernel 收到 ACEScc 值（如 exposure 的线性 gain 变为 log 域乘法）。这是 D1"零代码对齐"+ D3"全链包夹"的结构性后果，面板级语义对齐归 P2（本 plan 的验收面 = identity 往返 ≤1e-5 + 非目录链逐字节不变，均已证）。

## 六、golden 容差实配值签注（KD-8）

- **比较空间 = linear（双侧 decode 后）**：encoded 空间比较在 linear≈0 处被 encode 对数腿斜率（1/(x·17.52·ln2)，x=1e-4 时 ~750×）放大 f32 固有 epsilon（~1e-7 linear）至 ~1e-4 encoded——数值比较点选 linear 域（斜率 ~12×，稳健）。f32 eps 的量级是任何 f32 kernel 不可消除的。
- **参考常数 = 出厂 f32 常数升 Double**（`Double(Float(17.52))` 等）：KD-2"Float64 推导后降 float32 常数"对数学常数同样适用；精确十进制参考会在 decode 斜率上引入 ~4e-5 的常数舍入系统差（T3 实测），golden 度量的是公式保真而非字面舍入。
- **输出窗裁剪 [-0.5, 2.5]**（plan 原文条款）：统计窗内样本；(2000K, +150) CAT02 角点全窗裁空时仅做 bounded/NaN 断言。
- **病态角点单独签注**：CAT02 (2000K, +150) 的适应阵元达 ~1e10（Alcedo 同款未防护，源头 max(src,1e-10) 除法），f32 行求和消散在该角点不可修复——该角点 p999 ≤ 1e-3 / max ≤ 5e-3（其余角点/工作点保持 1e-5/5e-5；实测 (2000,−150) 2e-7、(15000,±150) ≤3e-7、工作点 ≤1e-7）。
- 纯函数断言 ≤1e-6 照 KD-8；identity 参数点像素容差 0 照 KD-8。

## 七、其它执行签注

- **架构缝**：Core 不可 import IOP（D-03）→ 包夹缝 = Core 侧 public `LayerCompositeSeam.acesccEnvelope` 持有器 + IOP populate 时 `ACESccEnvelope.install()` 注入；默认恒等包装（纯 Core harness 字节不变）。driver diff = 腿部 2 行 + 缝持有器 + 头注（半径红线内核对通过）；PixelPipe/PipeCacheKey 零 diff。
- **T1 载体前置**：GradeCatalog 引用 `<Module>.opName` 常量（零字面量纪律）→ 七新件的参数载体（opName/Params/clamp/identity 面）随 T1 落地，kernel/注册随 T3-T7；载体 process 以 `GradeCarrierKernelPending` tripwire 占位（未注册不可达）。
- **边界偏差（已声明）**：Tests/LightamerTests/V50OrderTests.swift 不在 front-matter，但 count 钉（95→105）与同位簇钉 {28.5, 41.0} 必须随原生行插入更新（93→94→95 先例）；静态 count 字面量与"既有测试全绿"不可兼得，m3 判据的"不锚行数"即此意。
- **CAT02 CCT/tint→xy**：Planck 定律 × CIE 1931 2° CMF（1nm 360-830，CIE 018:2019 公开数据集）直接积分（c2 = 1.4387774e-2，与 Alcedo 表生成同源；对表首条目验证 du≈−9.6e-9），**不拷贝其派生表数据**；locus 切向窗 ΔK 照抄（clamp(cct·0.001, 0.5, 3250)）。
- **identity 判定补充**：shadhi 目录快照（shadows/highlights 0）≠ 面板默认（50/−50）——checker m5 分立两套值的声明由测试钉死。
- **HLS 8-bin uniform 装配**：values[0..7]=hue_bins、[8+i·3]=adj 行、[32+i]=h_range（Alcedo 行为 8 装配式样）；flag = 全零表早退（等价于 kernel 内 adj≈0 返回，省 8 bin 循环）。

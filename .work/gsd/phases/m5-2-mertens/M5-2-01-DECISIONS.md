# M5-2-01 DECISIONS — Mertens 融合 Core 底座批（wave 1 执行批，2026-10-13）

> 执行 subagent worker 落账。基线 = `0f7e10b` 后 HEAD（plan/cheker docs 已在）；
> 终点 = T5 收口 commit。五个执行 commit：T1 `075114a` / T3 `fc66033` / T2
> `288467a` / T4 `a141814` / T5（本批 docs）。checker 5 minor 全部同批采纳
> （§7）；实测带与数学证据见 §3-§5。

## §1 checker 5 minor 采纳记录（plan 执行落点）

| # | minor | 处置 |
|---|---|---|
| M1 | Lumen `static.sum()<64` 全格兜底缺失 | **已移植**：`MertensFusion.staticSampleMask` 落 merge.py:146 语义（静止格 <64 → 全格视作静止 + `fellBack` 返回面），负测/正测双钉（`testStaticSampleFallbackCoversAllMotionDegenerate`）；02 KD-1 LUT 预计算段引用同句（`substituteLUTs` 内部已消费兜底后网格）。 |
| M2 | G3① 双帧恒等前置 + 常数钉死 | **采纳**：恒等靶 fixture = 三通道异种子 LCG 纹理（S>0 处处 + 白噪声曲率 C>0 处处）；gray = Rec709 luma、std = population（÷3）两常数钉进 `MertensFusion.swift` 头注（OpenCV COLOR_RGB2GRAY 为 BT.601——KD-3 绑定值 Rec709 胜，deghost 阈值对系数选择不敏感，头注记明）。 |
| M3 | 基线勘误链 +31→+32 | plan 基线段原文笔误（头值 3477/21/0 无误）；本 DECISIONS 记录勘误，plan 文件不改（执行批不回改 planner 正文，VALIDATION 对账链以 M5-1-VALIDATION :39 为准）。 |
| M4 | 真值表 6 行非 8 行 | **采纳**：测试落 KD-2 六行（32/64/256/512/1024/8642）+ 边界两行（16→1 地板 / 65536→12 / 131072→12 帽），测试注记「plan 八行系笔误」。 |
| M5 | 02 test_bundles 口径 | 属 M5-2-02 plan 文件，本批不触（02 执行批处置）。 |

另：checker O1（decode N 超步为五 kind 共性）已写进 `StackMergeService.stepTotal`
头注与 T2 commit body（挂账不改，G5 红线）；O3（G3③ 两因子并写）在 §5 落字。

## §2 执行序偏差（一处，申报）

**T3 commit 先于 T2 commit**（`fc66033` → `288467a`）。原因 = 可编译提交纪律：
`MertensMergeKindTests` 同文件承载 T2 词汇断言与 T3 verdicts 断言（plan 原文
「并入 MertensMergeKindTests」），先落 ExifPrecheck 生产面再落测试文件，每个
commit 独立可编译。T1/T4/T5 序不变。plan 提交约定消息逐字采用（T2 commit body
注明测试文件双职责）。

## §3 G2 Float64 孪生 parity——实测钉门字面

- fixture：256² 三面合成 bracket（base·0.6 / base / base·1.5 clip），levels =
  adaptiveLevels(256) = 4。
- **实测 p99.9 = 6.954681426845722e-07**；max 尾 = 1.0877221378269297e-05。
- **钉门 = p99.9 ≤ 1e-6**（KD-7 程序：实测向上取整到数量级）；硬上限 1e-5 在册
  （违反 = 实现缺陷，先查 FMA/序）。max 尾 1.09e-5 为 print-only 观察值不入门
  （单像素尾噪，p99.9 才是 plan 绑定口径）。
- 孪生范围申报：**融合核**（weights + Float64 金字塔对 + blend + collapse）；
  deghost/分位路径不孪生——其数值由阈值/形态学主导，Float32 敏感面在金字塔
  算术（头注同文）。σ/系数常数经 `Double(Float(x))` 升维（L048 ②）。

## §4 G1 / G3① / G3③ 实测记录

- **G1**：`fuse(frames:)` 与 `fuseStrip` 双跑各自**逐字节相等**（Float `==`
  全元素），零原子零并发归约。
- **G3① 双帧恒等**（deghost off，96×72 纹理靶）：worst = **8.940697e-08**，
  ≤1e-6 带内、**非逐位**——机制 = per-level 除法 `(w₁l+w₂l)/(w₁+w₂)` 的
  float 舍入 + collapse 传递；plan「预期逐位」实测否，带 11× 余量。
- **G3③ 权重压制**（checker O3 两因子并写）：flat 1.0 块上 C=0 **且** S=0，
  完整权重 C·S·E **真零**（E(1.0) 单通道 exp(−3.125)≈0.0439 立方后
  8.48e-5 > 0——高斯核无真零点，但乘性结构下占比 = 0），实测占比 worst =
  **0.0**，≤5% 占比门以更强方式成立；融合输出 vs 正确帧 worst = 5.96e-08。
  测试同时钉 E(1.0) 立方式（KD-7③ 修正依据的可执行形式）。

## §5 G3② 鬼影构造——fixture 形态的机制发现（重要）

初版 fixture（白噪声块平移复制）**mask 全零**——探针实测：σ1.2 模糊后残差
p50 6.3e-4 / p95 3.0e-2 / max 0.101，**全部低于 medium 阈值 0.12**。机理：
①白噪声平移保直方图 → 33 点分位映射 ≈ 恒等（映射无残差可吞）；②σ1.2 模糊
把独立噪声差压到 std≈0.077（方差因子 ≈ 1/(4πσ²)），1.57σ 才过阈。**这是
检测器的设计而非缺陷**——Lumen 阈值表针对自然图像的连贯结构边缘（模糊域
残差 ≈ 亮度阶跃），合成靶必须构造连贯区域（真实运动物体的形状）。

修正形 fixture = **连贯暗物体 +20px 平移**（背景 [0.45,0.85] 纹理 + 暗块
[0.08,0.15]）：目标块与离位原点 mask 均值均 ≈ **0.9999999**；置换后目标块
vs 参考内容 worst = **1.7881393e-07**（分位 LUT ≈ 恒等 + α≈1）。M5-2-02 走查
（G6）构造样张时沿用「连贯区域」形态，禁白噪声平移靶。

## §6 G3④ halo 不渗——逐位结论 + 网格对齐前提

- 正门：256×512、levels=5（感受野 2^5−2 = 30，halo = haloRows(5) = 32 精确
  锚 `defaultHaloRows`）：带行（距条带边 ≥ 30）vs `fuse(frames:)` 整帧
  **逐位相等**（Float `==`，全带 × 全列零失败）。
- 负门（测试可证伪性）：halo=16（< 30）时条带近边行**不同**于整帧参考——
  halo 公式的余量是承重的，正门不是永真假绿。
- **网格对齐前提（02 继承约束）**：条带起始行必须被 2^(L−1) 整除（最深
  reduce 网格），逐位性质才成立（本测试 strip 起点 64 = 2^6）。生产 band
  driver（M5-2-02）的 band 划分需满足该对齐（BandStreamer bands 为均分切，
  02 落地时按层深取整 band 边界——挂账进 GOAL-STATE 02 续接点）。不对齐时
  金字塔各级 decimation 网格错位，带内行与整帧参考出现粗层级小偏差（enfuse
  语义仍正确，但 G3④ 式逐位门不可用）。

## §7 sRGB piecewise 接缝类型名勘误 + junction hairline

- plan/checker 引注 `DrtEotf.srgbPiecewiseEncode/Decode`——实际宿主类型 =
  **`DrtEotfMath`**（`DrtEotf.swift` :76 enum `DrtEotfMath`；`DrtEotf` 是
  selector 枚举）。语义/文件位与 plan 一致，仅类型名勘误。
- round-trip 带：运行域 [0.004,1] 实测 worst ≈ 1e-8 量级，≤1e-6 达成；IEC
  分段式**结点发丝带**（v ∈ ~(0.0031287, 0.0031308)，encode 落幂支 code 略
  低于 0.04045 → decode 走线性支）存在 ~1.5e-6 绝对偏差——标准常数舍入的
  测度零伪影，非融合缺陷；专测 `testDisplayEncodeJunctionHairlineDocumented`
  以 ≤3e-6 钉记录（plan ≤1e-6 带声明适用于运行域，头注/测试注记双落字）。

## §8其它实现裁决

- **权重归一形**：per-level num/den（ε 守卫，ε = FocusStackMerge.weightEpsilon
  = 1e-8）——FocusStackMerge.fuseStrip 同构（08-3 验收面），KD-2「逐层
  Σ G(Ŵ)·L」的 per-level 读法；与 OpenCV normalize-then-pyramid 的差异仅在
  ε 作用层（两式在 ε→0 时同极限），G3① 实测带佐证语义正确。
- **provider 契约**：每 source 恰调用一次（单遍 fold），权重金字塔在 fold
  前局部构建——源互不常驻性质与 FocusStackMerge 相同。
- **NaN 契约**：MertensFusion 不分支 NaN（调用方 sanitizes——02 流式腿的
  StagedSet 惯例），头注声明。
- **`exposureFitPlane` 默认参数** sigma = `MertensFusion.weightSigma` 文件
  常量（KD-4 不参数化）；wc/ws/we = 1.0 同。
- **merge.py `radius/2` 羽化 σ**：`max(1, Float(radius)/2)` 逐字移植（int
  除法语义按 Python3 float 除保留）。
- **高斯核半径** = `round(3σ)`（≈ OpenCV `ksize = round(6σ+1)|1`；σ=1.2 →
  ksize 9 逐值命中）。

## §9 测试账

- 四文件 39 法：MertensFusionTests 13（IOP）/ MertensMergeKindTests 14（IOP，
  含 T3 verdicts 六法）/ MertensFusionGoldenTests 7（IOPP）/ 
  MertensProvenanceTests 5（LIB）。plan 估 +42..52，实落 39（估数按 AC 全覆盖
  收敛后自然落点；每 AC 至少一法，无缺项）。
- 定向轮：IOP 590/1/0（=563+27，198→195→7202MB 无 MEMFAIL）/ IOPParity
  451/3/0（=444+7，6974MB）/ Library 631/4/0（=626+5，615MB）；skip 计数
  与 M5-1 终验逐位一致（1/3/4），失败零。
- 临时探针（ZZMertensDebugProbeTests）已删，未入任何 commit。

## §10 待供件 / 挂账移交

1. **02 band 网格对齐约束**（§6）——band 边界按层深取整，G3④ 式逐位性质
   的生产前提。
2. **G3② 样张形态**（§5）——G6 走查用连贯物体构造，禁白噪声平移靶。
3. **stepTotal 08-3 观察项**（KD-8/O1）——五 kind 共性 decode N 未入声明式，
   修复批另案（本批零改动）。
4. **M5-2-01-ACCEPTANCE.md**——双重验收（zcode PASS → 串行 omp，严禁并发）
   由验收波落盘，本批不预写。

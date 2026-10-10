# M5-1-01 DECISIONS — TRACK P1 统计域 + S1/S3 求解器 + colormatch op 核心

> 执行批 2026-10-11（夜间全自动授权「开跑，不要停」）；基线 `dcd02a8` 后 HEAD，
> 8 commits `47a27be..b83db8f`。任务序 T1..T9 与 PLAN 一致；本文只记**偏离、
> 实测带、钉死值与机制勘误**——KD 落地无偏离者不重复。

## 1. 常数与组合链（KD-1 落地选择）

- **预合并单矩阵形（声明内部自由度的选择）**：正向 `M1C = M1·M(2020→709)`、
  逆向 `M1C⁻¹ = M(709→2020)·M1⁻¹` 各折叠为一个 3×3，Float64 推导自
  BT.2020/BT.709 原色色度（2020: R(.708,.292) G(.170,.797) B(.131,.046)；
  709: R(.64,.33) G(.30,.60) B(.15,.06)；均 D65 (.3127,.3290)），11 位有效
  数字硬编码。理由：每方向一次矩阵乘（Float32 产线少一轮舍入）+ kernel 单乘。
  常数单源 = `OklabMath.swift` 文件头；MSL 注记指向同源（零重推导）。
- **Float64 孪生常数 = `Double(Float(公开常数))` 升维**（L048 ②）——白点锚的
  容差因此是 1e-7 而非理想数学的 1e-8（升维常数行和残留 ~3e-8）。
- **符号保持 cbrt 双侧同拼写**：`x≥0 ? pow(x, 1/3) : −pow(−x, 1/3)`，指数
  字面量 = `Float(1.0)/Float(3.0)`（≡ MSL `1.0f/3.0f`）。MSL 侧用
  **`precise::pow`**（MSL 默认 fast-math，裸 `pow` 是近似形——FilmPlacement
  kernel 先例）。
- **域政策 = 零 clamp**（线性臂全定义域裁定）：负分量/HDR 双向解析直通，
  负测钉 NaN-free + 奇对称。
- **Rec2020 域 Oklab a/b 极值抽样**（KD-2 域宽依据）：Rec2020 凸包 Y≤4 内
  20 万样本实测 a∈[−0.638, +0.546]、b∈[−0.537, +0.339]——超出 ±0.5 直方图
  域的部分按端 bin clamp（计数不丢）落地，域宽不改。

## 2. 实测带（T1/T4/T7 全部实测收窄钉门，目标值不进断言）

| 面 | 实测 | 门 |
|---|---|---|
| Oklab Float32 往返（色域角+灰轴+2048 随机，相对） | worst **1.19e-6** | ≤1e-5 |
| Oklab Float64 孪生往返（相对） | ≤5e-7（Python 全精度同构 8.9e-9） | ≤5e-7 |
| 产线 f32 vs 孪生 f64（前向，abs in Oklab units） | worst **5.72e-6** | ≤2e-5 |
| OT 定义约束 `M·Σs·Mᵀ=Σt`（非对角非交换组，Float64） | **1.08e-12** | ≤1e-10 |
| 同上经 Float32 降格面（checker 红线 ≤1e-6） | ~1e-7 | ≤1e-6 |
| G3 矩精确构造臂（ commuting 族 T_true 恢复，相对） | ~1e-7 级 | ≤1e-3 |
| G3 采样臂（LCG 2 万样本，T 映射后 extract→solve） | worst **1.73e-2** | ≤0.06 |
| S1 对角输入 ≡ S3 输出（逐元素） | ≤1e-6 达成 | ≤1e-6 |
| G2 well-conditioned 子集（全部 |lms|>1e-3，scale-aware p99.9） | ≤1e-5（abs 口径实测 3.4e-5 @ 输出幅值>10 ≈ 3e-6 相对） | ≤1e-5 |
| G2 全网格 abs p99.9 / max | **2.95e-3 / 3.68e-2** | ≤4e-3 / ≤5e-2 |

**G2 双面门的机制注记（重要）**：Oklab 正向 cbrt 在 **LMS 近零交越**处导数
无界（`d x^{1/3}/dx = (1/3)x^{−2/3}`）：实测一像素 lms.y = −6.3e-10（三加项
对消），f32 舍入被放大成 ~1e-3 的 lab 误差 → 输出绝对误差 ~6e-4。轴对齐
lab 网格系统性切过 LMS=0 曲面，交越像素不是零测度意外而是驱动集的固定组成
→ 相对误差判据在尾部无意义。门拆两面：良态子集（|lms|>1e-3 全通道）扛
1e-5 级精度门（证 kernel 算术正确），全网格扛交越界门（钉实测带）。
**plan 的「p99.9 ≤1e-5 目标」在交越像素上数学不可达**——不是 kernel 缺陷
（f64 自身在该点对输入扰动同样敏感），非降级交付。

## 3. 求解器实现选择与勘误（KD-3 + 执行期修复）

- **实现形 = 对称三明治**（E1 正本）：`M = Σs^{−1/2}·(Σs^{1/2}·Σt·Σs^{1/2})^{1/2}·Σs^{−1/2}`，
  3 次固定 Jacobi 对称特征分解（固定对序 (0,1),(0,2),(1,2)、固定相对门
  1e-15·scale、60 sweep 帽、固定下标 tie-break 的降序排烟），**零
  LAPACK/Accelerate**（G1 bit-identity 可达面）。极因子形等价性 = checker
  已数值复核（≤1e-15），不另设测。
- **执行期修复两枚**（golden 批发现，均在 T4 commit 内修复）：
  ① jacobiEigen 返回的「特征向量」按行读了行主累加阵（列实际 stride 3）——
  三明治重构面全错（约束带 ~1.6）；修复后 Float64 约束带 1.08e-12；
  ② S3 对角原写方差比，按 checker E1 的「对角归约 = diag(√(tᵢ/sᵢ)) 标准差
  比」改为开方比。
- **零迹 S3 面（R1 边界补全）**：常数色源图 trace=0 → ε=0 → S1 秩门
  `min<0` 恒假会漏进 1/√0=inf；补 `min≤0 ∨ min<1e-9·trace` 双臂 +
  S3 零迹面 = **恒等矩阵 + 纯 offset（c=μt−μs）**（零协方差下任意 M 等优，
  恒等是中性确定面；G1 钉双跑确定）。
- **strength 语义**：`out = (1−α)x + α(Mx+c)`；kernel 采 KD-6 推荐展开
  `x + α((M−I)x + c)`，uniform 携 (M−I, c)（α 不变量）——降格点单源
  `ColorMatchSolver.strengthKernelTerms`（M−I 逐对角减 1，Sterbenz 精确）。
- **求解缓存键折叠序精确值**（FilmSolveCache 体例，G1 钉死）：
  `gaussianOT(0,0) = 2495982924697081349`、`reinhard(0,0) = 3458577883779271296`
  （两 UInt64 小端原始字节 + tag UTF8，FNV-1a 链）。
- **statsHash 折叠序**（E4）：histograms（通道主序 3×256 计数）→
  sampleCount（UInt64）→ μ（3×f32 位型）→ Σ（6×f32 位型）→ supportLo →
  supportHi。字段敏感三测（改一矩位/一支撑位/一计数各翻哈希）钉死。

## 4. G3 恢复目标的构造约束（可复现性关键）

**commuting 族构造**：`T_true = V·diag(tᵢ)·Vᵀ`（V = 固定正交，tᵢ>0 互异）。
理由：OT 求解从高斯矩只能恢复 **OT 映射本身**——任意满足
`T·Σs·Tᵀ=Σt` 的 T 不是恢复目标（例：Σs=I 时正交 T 满足协方差约束但 OT 映射
= I）。commuting 族使三明治代数精确坍缩到 T_true，矩精确臂的 ≤1e-3 门才有
意义。采样臂（非精构造）带 1.73e-2，来源 = 逐通道 1%/99% 截尾在映射后
marginal 上选出的支撑域样本集不同（trim shuffle）——非缺陷，机制注记。

## 5. T5 落位决策与 plan 勘误

- **optional 三字段显式 null 编码**（checker E2 采纳）：`encode(to:)` 全键
  恒编码（nil → JSON null）；专测以 `NSNull` 断言钉死（JSONSerialization
  语义）。decode 宽容（缺键/未知 solver rawValue → 默认，不 throw）。
- **xcstrings 零键（对 plan「+1..2 键」的偏离）**：占位期无消费点
  （InspectorView.localizedLabel 落 raw-opName fallback = filmPlacement
  add 菜单精确先例）；孤儿键会被 zh-audit 判红（assertion 2）。M5-1-02
  面板落地时随面板键一起入册。
- **prewarm 名单未加**（对「kernel 预热惯例」的偏离声明）：恒等占位期
  kernel 永不 dispatch，PSO 首用构建 ~ms 级可接受；M5-1-02 面板批随首例
  落位补 `ColormatchKernel.linear` 入 `prewarmFunctionNames`。
- **DefaultFaceTests 钉数勘误（对 plan E2 清单的机制修正）**：plan 写
  「`defaultFaceOps() == 15` 钉不动——seed ABSENT 不入默认 face」——机制上
  不成立：`defaultFaceOps = ops ∖ defaultFaceDisabledOpNames`，colormatch
  不在禁用集 → ops 19 − D1 三件 = **16**（MCP 默认面 list_iops 同步 16、
  全 face 19）。E2 五文件的其余钉数照改；L050 教训（按机制穷举非人工点名）
  再次兑现：实际受波及断言 7 处，plan 点名 5 处。
- **McpEditingToolsetTests 反射 guard 扩展**：seed-absent op（colormatch）
  无 seed record → guard 回落 **GradeCatalog identityJSON**（同字节单源）
  + version 钉 1 + iopOrder 钉 V50Order——filmPlacement 先例的 generalized。
- **add-face 枚举 13→14**（colormatch 入列）；templateInstance case =
  E2 前置缝已落（漏补即 compactMap 静默丢行）。
- **IopCatalog COVERAGE 注记 18→19**、guard 钉数 18→19、`checked` 19。

## 6. T7 parity 判据面（详见 §2 末注记）

- 判决 = **绝对误差双面**（良态子集 scale-aware 相对 ≤1e-5 + 全网格绝对
  交越界）——相对判据在交越尾部无意义。
- kernel 常数与 OklabMath 字面量逐位同源；参考实现与 kernel 展开式逐项同步
  （同式防假 parity——执行期曾发现测试参考把 (M−I) 逐元素减 1 的 bug，
  与 kernel 无关，已修）。
- L047 教训两次兑现：.metal 重建后先核 metallib 新容器 mtime（本次 fresh
  容器吸收正常；两枚陈旧容器无 colormatch_linear 属正常多容器现象）。

## 7. 批量账目

- 新测试 6 文件 **38 法**（Oklab 7 / Stats 10 / SolverGolden 10 / Module 7 /
  KernelParity 2 / Identity 2）；BUNDLE-MAP 增行 6；运行期对账：IOP 562→563
  （V50OrderTests +1 法）、IOPParity 427→438（+11）、Layers 394→438（含
  M4-3 存量增量，本批 +27）、App 704→711（含 M4-3 存量增量，本批 App 零新
  测试文件——钉数修订均在既有文件内）。
- 定向四 bundle 轮（本批终值）：**Layers 438/3/0（958MB）/ IOP 563/1/0
  （6848MB）/ IOPParity 438/3/0（6667MB）/ App 711/4/0（2832MB）**——全绿
  零 MEMFAIL（IOP 6848 < 8192 门，余量 ~16%）。
- 红线自证（`git diff dcd02a8..HEAD`）：密封面
  `LightamerIOP/Sources/Lut3d/`、`LightamerCore/Sources/Sidecar/`、
  `LightamerCore/Sources/Pipe/History/`、`PipeCacheKey.swift`、
  `PipelineDocument.swift`、`Graph/NodeGraphCommand.swift` **零命中**；
  `defaultFaceDisabledOpNames` 零触碰；`.metal` 新增面 = ColorMatchKernels.metal
  一文件一 kernel（零 function constants）；V50Order add-only +1 行
  （106→107）；零新 SPM（Project.swift diff 仅测试编列）；xcstrings 零改动；
  zh-audit `--check` PASS（1617 source / 1855 catalog keys）。

## 8. 待供件 / 移交 M5-1-02

- 面板键族（solver/strength/参考选取）随 M5-1-02 面板入册（含补
  prewarm 名单）；`.cdf` solver case additive 时破穷举 switch 的补臂点 =
  IopCatalog enum 注记 + 面板 switch。
- S2 的直方图输入 = ColorMatchStats.histograms（已入 statsHash 折叠）；
  平面 tap 适配器（ScopeReduce 桥）按 plan 留 M5-1-02。
- `match_color` 的 P3 attach=false 参数组回灌路径已由显式 null 编码保通
  （apply_params 未知键拒绝不误伤）。

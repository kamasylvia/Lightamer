# M5-2-01 ACCEPTANCE — Mertens 融合 Core 底座批（wave 1）独立验收

> **验收路 = zcode subagent（零共享上下文独立验收，2026-10-13/14 夜间批）。**
> 对象 = 五执行 commit `075114a..06a3b9c`（基线 `d9f0957`）；规格正本 =
> `M5-2-01-PLAN.md`；裁决正本 = `M5-2-CONTEXT.md`（OQ-1..7 全 A）；
> checker = `M5-2-CHECKER.md`（PASS / 0E+5M，5 minor 采纳已在执行批 DECISIONS
> §1 落账）。实测核验不轻信：三 bundle 亲跑 + 数学独立复算 + Lumen
> `merge.py` 全文亲读逐段对照 + 逐 commit 边界 + 红线机检全部亲证。

# PASS / 0 error + 0 minor + 4 obs（zcode 路）

批内全部 AC 亲证达成，无需修复批；4 obs 为观察级登记（不阻断、不强制
02 处置，处置建议随条）。omp 串行二次验收由 orchestrator 编排（本文件
§9 留位；两路结论齐前不进 C 档门控）。

## §1 亲跑数字对表（L075 纪律：`build-for-testing` scheme Lightamer 重建后跑）

| bundle | 亲跑 | 申报 | 对表 | peakRSS（亲跑 / 申报） |
|---|---|---|---|---|
| IOP | **590/1/0**（149s） | 590/1/0 | ✅ 逐位 | 7651MB / 7202MB（轮间漂移族，8G 门内非贴线） |
| IOPParity | **451/3/0**（567s） | 451/3/0 | ✅ 逐位 | 6301MB / 6974MB（同上） |
| Library | **631/4/0**（80s） | 631/4/0 | ✅ 逐位 | 614MB / 615MB |

exit 0、零 MEMFAIL、零 crash；skip 计数 1/3/4 与 M5-1 终验（563+27 /
444+7 / 626+5 = **+39 法**账面自洽）逐位一致。zh-audit 复跑 **PASS
1638/1877**（与 M5-1-03 终态逐位同——本批零 UI 键零新增，一致）。全套
`--all` 批准制未申请（plan 纪律原文），账面 3477→3516 待批准轮。

## §2 数学审计（灵魂节；Lumen merge.py 全文亲读逐段对照）

- **W 三因子**：C = |4 邻 Laplacian(gray)|（OpenCV ksize=1 核同形）/
  S = population std(RGB)（÷3，OpenCV `calculateSaturation` 同式）/
  E = ∏exp(−(I−0.5)²/2σ²) σ=0.2；W = C·S·E 指数全 1.0（`createMergeMertens(1.,1.,1.)`
  锚真实——merge.py:167 亲读）。独立复算 E(1.0) = 0.04393693、
  **E³ = 8.4818e-5**（DECISIONS §4 逐位吻合）；G3③「flat 块 C=S=0 →
  完整权重真零」乘性结构亲核成立（checker O3 两因子并写已落字）。
- **分位映射**：33 点 linspace(2,98) / 抽样步 `max(1,ceil(max(dim)/1000))`
  / np percentile 'linear' 插值（rank = q/100·(n−1)）/ np.unique first-position
  语义 / np.interp 端点钳——与 merge.py:124-131 逐段吻合。
- **deghost 全链 vs merge.py:120-138**：档表 (.20,2)/(.12,5)/(.065,9) 逐值；
  σ1.2 blur → 绝对差 → 阈值 → **可用门（双帧灰度 ∈ (0.015,0.985) 开区间）**
  → **motion 为多帧 OR 累积**（merge.py:135 `np.maximum(...)` 同构——Swift
  `motion[pixel]=1` 语义一致）→ 膨胀 `round(base·max(dim)/1800)` max(1,·)
  → 方形 dilate (2r+1)² → 羽化 σ = max(1, radius/2)（Python3 float 除逐字
  移植，DECISIONS §8 属实）→ clip [0,1]。**MIT 语义移植注记真实**（文件头
  `Portions derived from Lumen RAW (lumen-raw, MIT)` 在位）。
- **merge.py:146 全格兜底**（checker minor-1）：`static.sum()<64 → 全格
  static` 在 `staticSampleMask` 落地 + 双向专测（all-motion 触发 / mostly-
  static 不触发 + LUT 仍满 129 点）亲跑绿。
- **置换式 vs merge.py:141-169**：129 点 0..100 分位 LUT（xs=ref 分位 unique、
  ys = frame 分位按 first-position 对位）、`prepared = original·(1−α) +
  LUT(ref)·α`、融合前 in-pass（bright-rectangle 陷阱结构性消解）——逐段吻合。
  `*255` 段为 Lumen 8-bit 容器约定，Lightamer [0,1] 域下语义等价跳过。
- **金字塔复用零复制**：`FocusStackMerge.reduce/expand/gaussianPyramid/
  laplacianPyramid` 均 internal static 直调（同模块，访问级已足）；
  `weightEpsilon=1e-8`、`defaultHaloRows=32` 锚真实。
- **Float64 孪生镜像性（G2 有效性前提）**：MertensFusion64 的 reduce/expand/
  expand1D/pyramid/blend/collapse 与 FocusStackMerge Float 版**逐算子同构**
  （binomial 两相 decimation、expand1D even/odd 相位式、clamp 边界逐字符
  对应）；常数经 `Double(Float(x))` 升维（L048 ②）——parity 带测的是精度
  差而非实现差，孪生有效。
- **adaptiveLevels/haloRows**：独立复算九行真值全对（32→1/64→2/256→4/
  512→5/1024→6/8642→9/16→1/65536→12/131072→12）；haloRows 1/4/5→32、
  6→64、9→512（`max(1, levels)` 防 shift 负数，L≥1 与公式恒等）。
- **白噪声机制发现独立性验算**（DECISIONS §5）：uniform [0.1,0.9] 白噪声
  双帧差 std ×√(1/(4πσ²)) σ=1.2 → **0.0768 ≈ 0.077**、0.12/0.077 = 1.56σ
  ≈ 申报「1.57σ」——机制叙述数学自洽，非杜撰。

## §3 golden 门独立复跑（亲跑 LA-MEASURE 与 DECISIONS 字面对表）

| 门 | 亲跑实测 | DECISIONS 申报 | 断言门 | 判定 |
|---|---|---|---|---|
| G1 | 双路径双跑全 passed（bitwise assert 无带） | 逐位相等 | 逐位 | ✅ |
| G2 p99.9 | **6.954681426845722e-07** | 逐位同 | ≤1e-6（硬上限 1e-5 在册） | ✅ |
| G2 max | 1.0877221378269297e-05 | 逐位同 | ≤1e-4（print-only 外圈辅助门） | ✅ |
| G3① | worst 8.940697e-08 | 逐位同 | ≤1e-6（非逐位带，plan 预期逐位实测否已如实落账） | ✅ |
| G3② mask | destination/origin 均 0.9999999 | 同 | >0.3 | ✅ |
| G3② 置换 | worst 1.7881393e-07 | 同 | <0.12（暗块-背景差 ≈0.3-0.7 ≫ 门，鬼影内容可拒，门有区分力） | ✅ |
| G3③ | 占比 worst **0.0** / fused-vs-correct 5.96e-08 | 同 | ≤5% / <0.1 | ✅ |
| G3④ | 7/7 passed（正门 bitwise + 负门 halo16 沾污） | 逐位 | 逐位 | ✅ |

G2/G3 全部数字**逐位复现**（兼证 G1 bit-identity 设计的确定性）；LA-MEASURE
7 法 IOPParity 全 passed、IOP 13+14 = 27 法全 passed 亲数。

## §4 域语义 / additive / fixture / commit 边界

- **域语义**：`DrtEotfMath.srgbPiecewiseEncode/Decode`（DrtEotf.swift :76
  enum 名亲证——DECISIONS §7 类型名勘误属实）自带 [0,1] clamp，KD-1 域约定
  by construction；encode/decode 配对 + junction hairline ~1.5e-6 专测在册
  （IEC 常数舍入测度零伪影，≤3e-6 钉记录）；round-trip 运行域 worst
  6.36e-08 亲跑 ≤1e-6。Core 不 import IOP（依赖方向亲核）。
- **免 EV 预检**：`mertensVerdicts` 零拒绝面（返回类型只 .ok/.admittedWithWarning）
  + body/lens/focal/aperture/ISO/shutter-missing 全 warning + EV = 既有
  ΔEV 组成式逐行同构（shutter 比 + ISO 比、缺 0 占位——:120-153 亲核）+
  strict `precheck` 对照负测（同输入 strict 拒 / mertens 收）亲跑绿。
  `metadataMatches` 复用既有 helper（与 strict precheck 同一函数）。
- **additive 面**：四 switch 补臂（provenanceKind/defaultTag/stepTotal 4N+3/
  dispatch）+ `runMertensLeg` typed stub（`invalidParameter` 点名 M5-2-02，
  M4-1-01「路由不切」形）+ MergeParams 双 optional 尾参缺省（既有 11 参调用
  点零改动）+ provenance Kind 镜像 raw 值恒等 + 双常量独立。旧 MergeParams
  golden JSON **逐字节零漂移**（7 键字面 + decode→re-encode 逐位）+ 新字段
  encodeIfPresent 双向专测。`done==total==15` 恒式（注入腿 3N+2 + decode N +
  settle 1）与 stub typed 失败两测试用不同缝，不矛盾（checker §四论证亲核）。
  五既有 kind stepTotal/tag 快照原值负测在册。
- **fixture 纪律**：checker M2 落地——恒等靶 = 三通道异种子 LCG 纹理（S>0
  处处 + 白噪声曲率 C>0 处处）；golden/单元测试全内存合成面零盘上资产；
  MertensMergeKindTests 盘上 fixture = temp 域 + UUID 子目录（与
  StackMergeServiceTests 先例同形，先例亦无 defer 清理——域惯例一致）。
- **commit 边界**：五提交文件面与 front-matter 逐一对表干净（T3 先于 T2 =
  可编译提交序，ExifPrecheck 无 MergeKind 依赖独立编译，DECISIONS §2 申报
  属实）；subject 与 plan 提交约定逐字一致；全英文 Conventional Commits。

## §5 红线机检（验收亲跑）

- `git diff 1d1f438..HEAD -- LightamerIOP/ Sidecar/ Pipe/History/ Graph/`
  = **0 行**；`*.metal` = **0 文件**；`Project.swift` diff = 仅 4 行测试登记，
  **dependencies 块 0 diff（零新 SPM）**；ExportQueue/sidecar schema 零触；
  `runHDRLeg`（Robertson02 腿体）在 StackMergeService diff 中零出现（唯一
  触面 = kind/params/stepTotal/defaultTag/dispatch 补臂，纯 additive）。
- **⚠️ AC1 grep 门账面勘误（本验收唯一申报失实处）**：SUMMARY §1 / GOAL-STATE /
  TODO 申报「`git grep -i opencv` 零命中」——实测 **11 处命中，全部为注释级
  行为锚注记**。根因 = **plan 内在矛盾**：AC1 要求 grep 零命中，而 plan T1
  明文要求文件头写「OpenCV `createMergeMertens(1.,1.,1.)` 行为锚」算法注记
  ——执行者按 T1 写注记则 AC1 字面必假。实质面（零依赖/零 import/零第三方
  符号，OpenCV 零入仓意图）完全达成。处置 = 账面勘误三处已随本验收批修正
  （SUMMARY §1 / GOAL-STATE 续接点 / TODO M5-2-01 行：改「零代码符号/import
  命中 + 注记为 plan T1 明文要求」）；非代码缺陷，不构成 minor（0 minor
  判定的依据：实质 AC 达成 + 失实为 plan 措辞缺陷的传导，非执行者虚报——
  执行批 DECISIONS 对注记本身申报如实）。

## §6 观察项（4 obs，登记不阻断）

1. **o-1 G3④ 带循环 off-by-one**：正门逐位断言 `for row in band.first..<(band.last−1)`
   遗漏带末行 415（该行距 strip 底边 33 ≥ 2^L−2 = 30，属带内应测面）——门
   覆盖 [96,414] 共 319/320 行。单行遗漏非假绿（其余全测且绿），建议 02 触
   该文件时顺手补全（不强制）。
2. **o-2 deghost 半径舍入语义**：`round(radius·max/1800)` 处 Swift
   `.rounded()`（half away）vs Python `round()`（banker）——恰值 .5 时半径
   差 1（如 radius=9×max=100 → 2.5：Swift 3 / Python 2），measure-zero 级
   自然数碰点；语义移植允许的实现级微差，登记备查。
3. **o-3 边界处理差异**：`gaussianBlurGray/contrastPlane/dilate` 边界 =
   clamp（BORDER_REPLICATE 形），OpenCV 对应算子缺省 = BORDER_REFLECT101
   ——仅影响边缘 1-2 像素行（内核半径内），内部区域逐位同构；对门值无影响
   （golden 全自实现内部一致性），对 02 真实样张边缘掩码有 ≤1-2px 语义差，
   走查时如见掩码边缘微差先查此处。
4. **o-4 OpenCV 权重归一时机差异**（DECISIONS §8 已如实落账，验收复核确认）：
   本实现 = per-level num/den 归一（FocusStackMerge 同构），OpenCV =
   normalize-then-pyramid——两式 ε→0 同极限、G3① 带佐证语义正确；非缺陷，
   02 与 Lumen 结构对照（G4）时按「结构对照非逐位」口径解读。

## §7 AC 总表核对（plan 九条）

| AC | 判定 | 证据节 |
|---|---|---|
| 1 OQ-1 自实现 + 零依赖 + 零 .metal | ✅（grep 门账面勘误见 §5） | §2/§5 |
| 2 OQ-3 deghost 四态 + nil→medium + 零 UI | ✅（档表 golden + resolved 负测 + diff 无 App 文件亲证） | §4 |
| 3 OQ-5 免 EV 全表 + strict 对照负测 | ✅ | §4 |
| 4 OQ-6 sRGB piecewise 经 DrtEotf + 真值表 + clamp | ✅ | §2/§4 |
| 5 G1 双路径逐位 | ✅ 亲跑 | §3 |
| 6 G2 钉门 ≤1e-6 | ✅ 亲跑逐位复现 | §3 |
| 7 G3 四靶 | ✅ 亲跑（③占比 0.0 强于门；④逐位 + 负门） | §3 |
| 8 G5 三 bundle 零回归 + 五 kind 快照 + 旧档零漂移 | ✅ 亲跑 + golden JSON | §1/§4 |
| 9 stepTotal 4N+3 恒式 + 08-3 观察项挂账 | ✅（done==total==15 亲跑；挂账在 stepTotal 头注 + DECISIONS §10） | §4 |

## §8 结论

**zcode 独立验收 = PASS / 0 error + 0 minor + 4 obs。** 五提交范围、数学、
门值、红线全部亲证；唯一申报失实（opencv grep 字面）已勘误并归因 plan
措辞矛盾。批内无需修复。**下一步 = orchestrator 串行 omp 二次验收
（严禁并发）→ 两路结论齐 → C 档门控（plan 闭环汇报 + M5-2-02 摘要等用户
确认）**。

## §9 omp 二次验收（orchestrator 编排留位）

- 结论：＿＿＿（PASS / FAIL + 证据指针；本节由 omp 路追加，严禁与本节
  之外的 zcode 结论并发产生——串行硬约束）。
- 抽查建议配方：§2 数学审计锚（MertensFusion.swift 头注 MIT 注记 + 档表
  三行 + 兜底分支）+ §3 LA-MEASURE 复跑（定向 `--bundle IOPParity
  MertensFusionGoldenTests`）+ §5 红线机检四条命令重放。

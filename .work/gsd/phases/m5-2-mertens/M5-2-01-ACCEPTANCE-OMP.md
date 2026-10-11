# M5-2-01 ACCEPTANCE-OMP — Mertens 融合 Core 底座批（wave 1）omp 二次验收

> 验收路 = omp 独立第二遍（2026-10-12 凌晨，与 zcode 首验串行后行：首验 commit
> `7d9708f` 已落盘后开跑）。对象 = 五执行 commit `075114a..06a3b9c`
> （基线 `d9f0957`）；规格正本 = `M5-2-01-PLAN.md`；裁决正本 =
> `M5-2-CONTEXT.md`；checker = `M5-2-CHECKER.md`（PASS / 0E+5M）。
> 本路独立执行：两 bundle 亲跑 + Python 独立复算七组 + merge.py
> 全文亲读逐段对照 + 四测试文件全文亲读 + 红线机检重放 + BUNDLE-MAP
> 逐 commit 对账。不轻信首验字面，每条结论附独立证据。

# PASS / 0 error + 1 minor + 5 obs（omp 路）

批内全部 AC 亲证达成，无需修复批。1 minor = 本路新发现的 DECISIONS
§7 账面失实（§6 m-omp1，不阻断、建议 02 触账时顺手勘误）。5 obs =
首验 o-1..o-4 复核确认 + 本路 o-omp5（skip 双口径，诊断已闭环属脚本
记账口径差非代码问题）。两路结论一致：**PASS**，分歧点见 §7
（零实质分歧，仅 1 账面勘误 + 1 口径澄清 + 1 证据补强）。

## §1 定向复跑对表（亲跑，不经首验转述）

| bundle | omp 亲跑（脚本行） | 宿主总结行 | 申报 | 判定 |
|---|---|---|---|---|
| IOP | **590/1/0**（155s，peakRSS 7245MB） | 590/1/0（147s） | 590/1/0 | ✅ 逐位 |
| IOPParity | **451/1/0**（脚本行；737s，peakRSS 5721MB） | **451/3/0**（732s） | 451/3/0 | ✅ 见 o-omp5 |

- exit 0、零 MEMFAIL、零 crash；两轮 8G 门内（IOP 7245 / IOPP 5721，
  轮间漂移族：首验 7651/6301、执行批 7202/6974——三轮互差 ≤20%，SPIKE
  ±3% 注记外但门内非贴线，`--all` 批准制未申请故不深究）。
- IOP 亲跑日志：`Test Suite 'All tests'` = `Executed 590 tests, with 1
  test skipped and 0 failures`；`' skipped` 行 1 条（SkinRegion 宿主
  Vision 态），suite 求和 590——记账三方闭合。
- IOPParity 细节见 o-omp5：**宿主总结行就是 451/3/0**（与申报逐位一致），
  脚本 BUNDLE 行记 451/1/0 是 `parse_bundle_log` 的 `grep -c "' skipped"`
  只捕到 1 条 `'] skipped` 行——另 2 skip 是静默跳过（日志中无 `' skipped`
  行、无独立 suite 行，疑 FilmGolden 打印污染邻 suite 计数的 XCTest
  输出交错所致，证据 §6）。`zsh` 重放 `parse_bundle_log` 得同值
  `451/1/0|peakRSS=5721MB|sampling=time|verdict=ok`——脚本行为确定性复现。
- Mertens 7 法在亲跑日志中逐法 `passed`（G1 0.58s / G2 1.89s / G3①
  0.05s / G3② 0.09s / G3④负门 2.66s / G3④正门 2.79s / G3③ 0.02s），
  suite 行 `Executed 7 tests, with 0 failures`。
- zh-audit 复跑 **PASS（1638 source / 1877 catalog，zh complete）**——与
  首验逐位同，本批零 UI 键一致。
- Library 未复跑（任务程序只派 IOP + IOPParity 两 bundle；首验 Library
  631/4/0 亲跑在案，本路不转述为己证）。

## §2 数学独立复算（uv/Python 独立实现，七组全对）

1. **三因子权重**：E(1.0) = exp(−3.125) = **0.04393693**、立方 =
   **8.4818e-5**（DECISIONS §4 逐位吻合）；E(0.5) = 1（σ-参数化恒等）；
   5 像素随机矩阵 W = C·S·E 手算复核乘性结构；flat 块 C=S=0 → W 真零。
2. **分位映射**：33 点 linspace(2,98) 步长恰 3.0；numpy linear 百分位
   rank = q/100·(n−1) 独立梯实现单调 + 端点钳（interp below/above  pinned）
   与源码 `brightnessMapping` 结构同构。
3. **deghost 三档**：(.20,2)/(.12,5)/(.065,9) 与 merge.py:122 逐值；
   半径缩放 `max(1,round(base·max/1800))` 九格表亲算；羽化 σ =
   max(1,radius/2)（Python3 float 除逐字——DECISIONS §8 属实）；
   banker 碰点 round(2.5) = 2 vs Swift 3（首验 o-2 属实，measure-zero）。
4. **白噪声机制验算**：uniform[0.1,0.9] 差 std ×√(1/(4πσ²)) σ=1.2 =
   **0.0768**、0.12/0.077 = **1.56σ** ≈ 申报 1.57σ——DECISIONS §5
   机制叙述数学自洽，非杜撰。
5. **金字塔一层手算**（精确分数）：4×4 输入 1..16 → horizontal row0 =
   [1.375, 2.0625, 2.9375, 3.625] → reduce 2×2 =
   [[2.875,4.4375],[9.125,10.6875]] → expand 相位式（even=源/odd=邻均）
   回 4×4；binomial 和/16 = 1（DC-consistent，常数场不动点 =
   telescoping exact 的结构前提）。与 `FocusStackMerge.reduce/expand`
   逐算子对照：两相 decimation、expand1D even/odd、`sample` clamp——
   Float32 产线与 Float64 孪生逐字符对应（首验 G2 有效性前提属实；
   另亲证孪生常数经 `Double(Float(x))` 升维：gray 系数/σ/指数/ε 四处）。
6. **adaptiveLevels 九行**：32→1 / 64→2 / 256→4 / 512→5 / 1024→6 /
   8642→9 / 16→1 / 65536→12 / 131072→12 全对；haloRows 1/4/5→32、
   6→64、9→512；decimationStep 三锚（1/2/9）与 Swift
   `(max+999)/1000` 整数除恒等。
7. **round-trip sweep 仿真**（128 步 [0.004,1]，Double→Float32→Double）：
   worst = **6.360626181312057e-08** at v = 0.9137——与亲跑 LA-MEASURE
   字面**逐位相等**（含末位 057），兼证 sweep 确定性。

## §3 golden 门亲跑复现（LA-MEASURE 字面对表）

| 门 | omp 亲跑（IOPParity 日志原文） | DECISIONS/首验 | 判定 |
|---|---|---|---|
| G2 p99.9 | **6.954681426845722e-07**（levels 4） | 逐位同 | ✅ ≤1e-6 |
| G2 max | 1.0877221378269297e-05 | 逐位同 | ✅ ≤1e-4 |
| G3① worst | 8.940697e-08 | 同 | ✅ ≤1e-6 |
| G3② mask | destination/origin 均 0.9999999 | 同 | ✅ >0.3 |
| G3② 置换 | 1.7881393e-07 | 同 | ✅ <0.12 |
| G3③ 占比 | **0.0** / fused-vs-correct 5.9604645e-08 | 同（首验 5.96e-08 缩写） | ✅ ≤5% / <0.1 |
| G3④ | 正门逐位 + 负门沾污（两法 passed） | 同 | ✅ |
| display round-trip | 6.360626181312057e-08（IOP 日志） | 首验 6.36e-08 缩写 | ✅ ≤1e-6 |

- 七法全 passed（§1），G1 双路径逐位断言无带；G2/G3 数字**逐位复现**
  （三路：执行批 → 首验 → 本路）。
- G3④ 网格对齐前提亲核：strip 起点 64 = 2^6 整除 2^(L−1)=16 ✓；
  负门 halo=16（stripFirst=80，同样对齐但感受野不足）沾污近边行——
  门可证伪（首验 §3 判定复核成立）。
- o-1 复核确认：正门循环 `band.first..<(band.last−1)` 遗漏末行 415
  （距 strip 底边 33 ≥ 30 属带内应测面），覆盖 319/320 行——单行遗漏
  非假绿，02 顺手补（不强制）。

## §4 merge.py 逐段对照（亲读全文 315 行，非转述）

| 段 | merge.py | MertensFusion.swift | 判定 |
|---|---|---|---|
| 档表 | :122 `{'low':(.20,2),'medium':(.12,5),'high':(.065,9)}` | DeghostLevel 三行 | ✅ 逐值 |
| 抽样步 | :124 `max(1,ceil(max/1000))` | `decimationStep`（整数除恒等） | ✅ |
| 33 点 | :124 linspace(2,98,33) | `linspace(2,98,33)` | ✅ |
| 分位/unique/interp | :129-131 percentile+unique+interp | `percentileOfSorted`(rank 式)+`uniqueWithFirstPositions`(first-position)+`interp`(端点钳) | ✅ |
| σ1.2 blur | :123/:132 `(0,0),1.2` | `residualBlurSigma=1.2` + `gaussianBlurGray` | ✅（核半径 round(3σ)=4→ksize 9 命中 OpenCV `round(6σ+1)\|1`：round(8.2)=8\|1=9 ✓） |
| 可用门 | :134 双帧 `(0.015,0.985)` 开区间 | :311-313 双帧 `>`/`<` | ✅ 开区间逐字 |
| motion OR | :135 `np.maximum(motion,…)` | `motion[pixel]=1` 只置不清除 | ✅ 跨帧累积同构 |
| 膨胀 | :136 `max(1,round(radius·max/1800))` + ones((2r+1)²) | :320-321 + `dilate` 方形 max 滤波 | ✅（舍入 o-2 登记） |
| 羽化 | :138 `max(1,radius/2)` + clip[0,1] | :323-327 同式 | ✅ |
| 全格兜底 | :146 `static.sum()<64 → ones` | `staticSampleMask` + `fellBack` 面 + 双向专测 | ✅ checker M1 落地 |
| 129 点 LUT | :147-150/:159（ref 分位 xs + frame 分位按位对位） | `substituteLUTs`（同向：ref→frame 色调域） | ✅ |
| 置换式 | :164 `original·(1−α)+LUT(ref)·α` 融合前 | `applySubstitution` + `fuse` 先置换后融合 | ✅（`*255` 为 8-bit 容器约定，[0,1] 域语义等价跳过——首验口径复核成立） |
| 融合锚 | :167 `createMergeMertens(1.,1.,1.)` | wc=ws=we=1.0/σ=0.2 文件常量 | ✅ |
| MIT 注记 | — | 文件头 `Portions derived from Lumen RAW (lumen-raw, MIT)` | ✅ 在位 |

- 差异三处（首验 o-2/o-3/o-4，本路复核确认非缺陷）：①半径舍入
  banker vs half-away（measure-zero 自然数碰点）；②blur/contrast/dilate
  边界 clamp（BORDER_REPLICATE 形）vs OpenCV 缺省 REFLECT101（仅边缘
  1-2px，golden 全自实现内部一致故门值无扰）；③per-level num/den 归一
  vs OpenCV normalize-then-pyramid（ε→0 同极限，G3① 带佐证；02 G4 按
  结构对照口径）。
- gray 系数注记复核：`cv2.COLOR_RGB2GRAY` = BT.601（0.299/0.587/0.114），
  本实现 Rec709——头注如实记明差异 + 「阈值对系数不敏感」依据（checker
  M2 绑定值），诚实非误标。

## §5 域语义 / additive / fixture / commit 边界 / 红线（亲核）

- **KD-1 接缝**：`DrtEotfMath.srgbPiecewiseEncode/Decode`（DrtEotf.swift
  :76/:172/:179 亲证）——DECISIONS §7 类型名勘误属实；encode/decode
  自带 [0,1] clamp（:173/:180 `min(max(…,0),1)`），KD-1 域约定 by
  construction；Core 不 import IOP（MertensFusion.swift 唯一 import =
  Foundation）。
- **免 EV**：`mertensVerdicts` 返回面只有 `.ok/.admittedWithWarning`
  （Verdict 枚举 :41-51 亲证三 case 中 rejected 不可达该函数——函数体无
  `.rejected` 构造）；body/lens/focal/aperture/ISO/shutter-missing 全
  warning；EV 组成式与 strict `:148-153` **逐行同构**（shutter 比 +
  ISO 比 + `candShutter>0` 守卫 + 缺件 0 占位）；`metadataMatches` 复用
  既有 helper；strict 对照负测（同输入 strict 拒 / mertens 收）全文亲读。
- **additive**：四 switch 补臂（provenanceKind/defaultTag"mertens"/
  stepTotal 4N+3/dispatch→`runMertensLeg`）+ MergeParams 双 optional
  尾参缺省（既有 11 参调用点零改动——diff 只见 init 尾两行追加）+
  provenance raw 值恒等镜像 + 双常量独立命名；旧 params golden JSON
  7 键字面 + decode→re-encode 逐位（全文亲读）；五既有 kind
  stepTotal/tag 快照原值负测在册；`done==total==15`（N=3：decode 3 +
  腿 3N+2=11 + settle 1）与 stub typed 失败用不同缝（注入腿 vs 生产腿
  mergeLeg:nil）——不矛盾（checker §四论证复核成立）。
- **stub 形态**：`runMertensLeg` = `nonisolated private static` + `throw
  AppError.invalidParameter("hdr-merge-mertens production leg lands in
  M5-2-02")`——M4-1-01「路由不切」同形，测试钉 `message.contains("M5-2-02")`。
- **Robertson02 零触碰**：`git diff d9f0957..06a3b9c -- LightamerCore/ |
  grep -c runHDRLeg` = **0**；StackMergeService diff 唯二含
  `runFocusStackLeg/runStackAggregateLeg` 的是 dispatch 上下文行（非
  腿体）；`runHDRLeg` 命中 2 条全在账面 md（SUMMARY/GOAL-STATE 叙述行）。
- **红线**：`LightamerIOP/` + `Sidecar/` + `Pipe/History/` + `Graph/` 对
  1d1f438 = **0 行**；`*.metal` = **0 文件**；App/ = **0 文件**；
  Project.swift diff 仅 4 行测试登记（338/415/416/594），dependencies
  块 0 diff（`grep -c '^[+-].*\.package'` = 0）；BUNDLE-MAP 增行随各自
  commit（T1 +8 含头注 / T2 +2 / T4 +1，终态四行 `13/14/7/5` 与
  `grep -c "func test"` 逐位对账）。
- **fixture/L072**：三测试文件全内存合成零盘上资产；MertensMergeKindTests
  盘上 fixture = temp 域 + UUID 子目录、无 defer 清理——与
  StackMergeServiceTests 先例（:57-60 同形、无 removeItem/defer）逐字
  一致，域惯例合规。
- **commit 边界**：五提交文件面与 front-matter 逐一对表干净；T3 先于 T2
  = 可编译提交序（ExifPrecheck 无 MergeKind 依赖，`fc66033` 单文件 91 行
  独立编译——DECISIONS §2 申报属实）；subject 与 plan 提交约定逐字一致
  （`feat(core)×3/test(iopp)/docs(m5-2)`）；全英文 Conventional。
- **AC1 grep 门**：`git grep -ci opencv HEAD -- LightamerCore/ App/` =
  **11**，全部在 MertensFusion.swift 注释/文档注记行（`//` 行为锚 +
  `///` doc），零 import/零符号/零依赖——首验 §5 勘误（plan AC1/T1 内在
  矛盾，实质达成）复核成立；三处账面（SUMMARY §1 / GOAL-STATE :19 /
  TODO :355）勘误措辞均已亲见落位。

## §6 本路新发现（1 minor + 1 obs）

- **m-omp1（minor，账面失实——DECISIONS §7 junction 发丝带三处错）**：
  DECISIONS §7 申报「v ∈ ~(0.0031287, 0.0031308)，encode 落幂支 code
  略低于 0.04045 → decode 走线性支，~1.5e-6 偏差」。独立验算证伪三点：
  ①**方向反**：v < 0.0031308 走的是**线性支**（`v<=0.0031308 ? v*12.92`），
  encode 不可能「落幂支」——真发丝带在**边界上方**
  (0.0031308, 0.0031308073)（幂支 code < 0.04045 → decode 走线性支）；
  ②**宽度错 6 个量级**：真带宽 7.3e-9（非申报 ~2.1e-6 宽）；
  ③**幅度错 6 个量级**：真带内 worst dev = 2.3e-9（非 ~1.5e-6）；
  专测取值 0.0031297 在边界下方走线性支 round-trip dev = **0.0**（Python
  双精度；Swift 同式）——该专测实际钉的是「线性支恒等」而非发丝带。
  程序：`enc(0.0031308⁻)=0.040449936` vs `enc(0.0031308⁺)=0.040449907`
  （幂支低 2.9e-8 < 0.04045 ✓ 机制存在但测度远小于申报）。
  影响：纯账面（运行域 sweep worst 6.36e-08 ≤ 1e-6 门本身由本路仿真逐位
  复现成立，无代码缺陷、无门值影响）；专测 `≤3e-6` 恒过（真值 0.0）。
  处置：minor（DECISIONS §7 三行勘误 + 专测改取边界上方真带内值如
  0.003130804 或改名「线性支恒等」，建议 02 触账时顺手，不强制本批返工）。
- **o-omp5（obs，skip 双口径——诊断闭环，非代码问题）**：本路 IOPParity
  脚本行 451/1/0 vs 宿主总结行 451/3/0 vs 申报 451/3/0。证据链：
  ①日志全文仅 1 条 `' skipped` 行（LutLibrary manual probe）+ 1 条
  suite 级 `Executed 16 tests, with 1 test skipped`；
  ②`Test Case started` 379 条 vs 451（72 条缺席——FilmGolden 7 法只打印
  3.5 法即被 HDRPipelineMatrixTests 行截断，302.7s 计入后者 suite 行，
  XCTest 并发打印交错污染）；
  ③`parse_bundle_log` skip 口径 = `grep -c "' skipped"` = 1（zsh 重放
  同值，脚本行为确定性）。
  结论：2 skip 静默（无行可捕）+ 72 行打印丢失 = **XCTest 日志输出交错/
  截断 + 脚本行计数口径**的复合现象；宿主总结行（XCTest 内部计数器）
  451/3/0 与申报逐位一致，**executed/failed 双零差**才是有效判据。
  首验轮脚本行即 451/3/0（其轮日志未截断）——轮间输出完整性差异。
  处置：obs 登记；建议 `--all` 批准轮以宿主总结行为准（脚本行作旁路），
  不改脚本（口径变更属另案）。

## §7 与首验分歧点（结论：零实质分歧）

1. **m-omp1（本路新增 minor）**：首验 §2 复述 DECISIONS §7 发丝带
   「~1.5e-6 专测在册」未独立验算——本路验算证伪（三处错，§6）。
   首验对门值本身（运行域 ≤1e-6）的 PASS 判定不受影响（sweep 逐位复现）。
2. **o-omp5（本路新增 obs）**：首验轮无此现象（其脚本行 451/3/0 一次命中）；
   本路轮脚本行 451/1/0——已诊断为日志截断 + 记账口径差，宿主行 451/3/0
   对表一致，不构成对首验数字的质疑。
3. **证据补强（非分歧）**：round-trip sweep Python 仿真与 LA-MEASURE
   **逐位相等**（§2⑦）；merge.py :39-43/:293-315 入口约束亲读确认
   RESEARCH §2.1 转述无误（2..32 源数/RGB 校验/`*255` 容器约定/:169
   clip）；BUNDLE-MAP 逐 commit 尾行对账（T1/T2/T4 各增行亲见）。
4. 首验 o-1..o-4：本路逐条复核**确认成立**（o-1 行号 318 亲见/
   o-2 banker 2 vs 3 亲算 / o-3 clamp vs REFLECT101 源码亲见 /
   o-4 per-level 归一 DECISIONS §8 + 源码 :583-608 亲见），处置建议无异议。
5. 首验 §5 AC1 勘误：本路复核**确认成立**（11 命中全注释级亲见 + 三处
   账面勘误亲见落位 + plan T1/AC1 矛盾原文亲见），不计 minor 的判定
   （实质达成 + plan 措辞传导）同意。

## §8 AC 总表核对（plan 九条，本路独立判定）

| AC | 判定 | 本路证据节 |
|---|---|---|
| 1 OQ-1 自实现 + 零依赖 + 零 .metal | ✅（11 命中全注释级 + dependencies 0 diff + metal 0 文件；grep 门勘误复核成立） | §5 |
| 2 OQ-3 deghost 四态 + nil→medium + 零 UI | ✅（档表 golden + resolved 六断言 + App 零文件） | §4/§5 |
| 3 OQ-5 免 EV 全表 + strict 对照负测 | ✅（零拒绝面 + 逐行同构 EV + 对照负测全文亲读） | §5 |
| 4 OQ-6 sRGB piecewise 经 DrtEotf + 真值表 + clamp | ✅（DrtEotfMath 亲证 + 九行复算 + clamp 源码亲见） | §2/§5 |
| 5 G1 双路径逐位 | ✅ 亲跑 | §3 |
| 6 G2 钉门 ≤1e-6 | ✅ 亲跑逐位复现 | §3 |
| 7 G3 四靶 | ✅ 亲跑（③占比 0.0；④逐位 + 负门；o-1 单行遗漏非假绿） | §3 |
| 8 G5 三 bundle 零回归 + 五 kind 快照 + 旧档零漂移 | ✅（两 bundle 亲跑 + 快照/golden JSON 全文亲读；Library 转引首验不作本路证） | §1/§5 |
| 9 stepTotal 4N+3 恒式 + 08-3 观察项挂账 | ✅（done==total==15 亲跑；挂账在 stepTotal 头注 + DECISIONS §10 亲见） | §5 |

## §9 结论

**omp 独立二次验收 = PASS / 0 error + 1 minor + 5 obs。** 五提交范围、
数学、门值、红线全部独立亲证；G2/G3 全部 LA-MEASURE 三路逐位复现；
merge.py 移植逐段吻合；Robertson02 腿体零触碰机检为零。1 minor
（m-omp1 发丝带账面三处错）与首验 o-1 同级——账面勘误，建议 02 触账时
顺手，不返工。**下一步 = 两路结论齐（zcode PASS / 0E+0M+4obs + omp
PASS / 0E+1M+5obs，零实质分歧）→ C 档门控（plan 闭环汇报 + M5-2-02
摘要等用户确认）**。

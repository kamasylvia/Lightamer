# M5-2-02 ACCEPTANCE — Mertens 生产腿与 UI 收口批（wave 2）独立验收

> **验收路 = zcode subagent（零共享上下文独立验收，2026-10-14/15 夜间批）。**
> 对象 = 五执行 commit `826fa5b..17142f3`（基线 `7d9708f`）+ 验收批修复
> commit `358abd8`；规格正本 = `M5-2-02-PLAN.md`；执行裁决 =
> `M5-2-02-DECISIONS.md`（§1-§5 全文亲读）；checker 回注 =
> `M5-2-CHECKER.md`。实测核验不轻信：全套 `--all` 七 bundle 亲跑 +
> 生产腿读码逐段对照 merge.py/01 纯函数面 + KD-3 refactor 逐字符 diff +
> 红线机检全部亲跑 + skip 22 逐个验身份 + perf 数字独立复算。

# PASS / 1 error + 0 minor + 5 obs（zcode 路；error 已随验收批修复闭环）

唯一 error = **生产腿 LUT staticGrid 缺 merge.py:145 全格兜底**（§3
E-1）——已修复（`358abd8`：腿侧改直调 01 面 `staticSampleMask` 单源 +
回归法 `testStageLUTsFallBackOnAllMotionMask` + BUNDLE-MAP 13→14），
修复后定向 IOP 复跑 **609/1/0** 绿。批内全部 plan AC 亲证达成；omp 串行
二次验收由 orchestrator 编排（§9 留位；两路结论齐前不进 C 档门控）。

## §1 亲跑数字对表（L075 纪律：`build-for-testing` 重建后跑；批准制全套轮 = 本验收任务指令即批准）

| bundle | 亲跑（执行批树 = `17142f3`） | 申报 | 对表 | peakRSS（亲跑 / 申报） |
|---|---|---|---|---|
| IOP | **608/1/0**（165s） | 608/1/0 | ✅ 逐位 | 7743MB / 7657MB（漂移族，8G 门内） |
| IOPParity | **451/3/0**（576s） | 451/3/0 | ✅ 逐位 | 6254MB / 7738MB（同上） |
| Layers | **466/4/0**（175s） | 466/4/0 | ✅ 逐位 | 1176MB / 1178MB |
| Library | **631/4/0**（80s） | 631/4/0 | ✅ 逐位 | 617MB / 617MB |
| Sessions | **279/4/0**（69s） | 279/4/0 | ✅ 逐位 | 1622MB / 1625MB |
| Export | **351/2/0**（199s） | 351/2/0 | ✅ 逐位 | 6098MB / 6443MB |
| App | **752/4/0**（362s） | 752/4/0 | ✅ 逐位 | 2832MB / 2832MB |
| **TOTAL** | **3538/22/0**（1626s） | 3538/22/0 | ✅ **逐位闭合** | 零 MEMFAIL / 零 crash / exit 0 |

对账链亲核：3477（M5-1 终验）+ 39（M5-2-01）+ 22（本批 13+5+3+1）=
3538 ✅。修复后树（`358abd8`）定向 IOP 复跑 **609/1/0**（7709MB，159s，
exit 0）——+1 = 回归法；后续全套账面基线 = **3539/22/0**。

## §2 生产腿审计（灵魂节）

- **KD-3 `runMTBAlignment` 行为保持抽取**：baseline `7d9708f` 的
  `runStackPrecheckAndAlignment` MTB 段（old :1161-1205）与新 helper 函数体
  **逐字符 diff = 零**（bump 序 ref→N−1 比较 / labels 词汇 / NCC 警告面 /
  返回四元组全同）；`withNCC` 分支原样；stack 严格预检留在原函数（Mertens
  免 EV 面不受 aperture 严格预检污染——OQ-5 结构亲证）。runHDRLeg 函数体
  对 baseline **零 diff**（diff hunks 全部落在 runStackPrecheckAndAlignment
  注记/抽取与 landStackProduct/StagedSet 任务域内）。
- **与 01 纯函数族同构性**：腿不重实现——`fuseStrip`/`applySubstitution`/
  `gaussianBlurGray`/percentile 族全为 `MertensFusion` 既有 internal/public
  面直调（01 双验亲证的同一批函数）；stage 期 motion 累积
  （`accumulateMertensMotion`）与 01 `ghostMask` 逐段同构（33 点分位映射 →
  σ1.2 blur → 绝对差 → 阈值 → (0.015,0.985) 双帧开区间可用门 → union
  max 累积），掩码定稿 = **全帧一次** dilate + 一次 feather + clip（
  merge.py :136-138 序）；驱动级互证 = `testBandOuterFuseMatchesWholeFrame-
  Golden`（64×600 三 band，band-outer 驱动 vs `MertensFusion.fuse` 整帧
  **逐位相等** mismatches==0）——01 G3④ 性质经生产驱动面延伸亲证。
- **StagedSet 共享掩码/网格行通道**：`writeMask`（512 行分块流式 UInt8）/
  `readMaskBand`（**无 shift**——α 在参考/输出帧坐标，与 `readShiftedPixels`
  的输出帧坐标条带同一坐标系，配对正确）/ `readPixelRow`（LUT 网格行整行
  读）读码亲核；掩码共享单通道语义与 merge.py `ghost_mask` 并集单平面逐项
  对照吻合（`np.maximum` 跨帧累积 + 一次 dilate + 一次 feather）——
  DECISIONS §2.1 修正判定成立（per-source dilate+feather 再并集 = 近似非
  正本，dilate max 可分配、feather 不可分配的论证数学成立）。
- **置换 in-pass 顺序**：`mertensBandOuterFuse` provider 内
  `applySubstitution(original: strip, reference: referenceStrip, motion:
  maskStrip, ...)` 先于 `fuseStrip` 折叠——融合前贴参考语义结构性成立
  （bright-rectangle 陷阱不可达）；source 0 恒直通（merge.py :154 参考帧
  不置换）；NaN 出叠区 → `sanitizedStrip` 消毒 0（E³≈8.5e-5 自然近零权，
  01 G3③ 常数锚真实；`testShiftedStagedSourceStaysFinite` 负测在册）。
- **对齐带**：`mertensAlignedBands` band 起点 = bandRows 整数倍且
  bandRows ≡ 0 (mod 2^(L−1))，halo = max(32,2^L) 恒为对齐模倍数 →
  stripFirst 对齐保持（`testAlignedBandStartsDivisibleByDeepestReduceGrid`
  levels 1/2/5/9/12 × 8642×11584 全过亲跑）。
- **分离式 dilate**：水平+垂直两次 max 轴分解与 naive 方形 max 数学恒等
  （max 可分解），`testSeparableDilateMatchesGoldenNaive` radii 1/3/9
  Float 精确相等亲跑绿；golden 面 `MertensFusion.dilate` 零触碰亲证。
- **进度恒式**：`stepTotal(.hdrMertens) = 4N+3`（decode N 泵段 + align N +
  stage N + fuse N band-paced+pad 补齐 + write/sidecar/settle 3）；tier off
  减掉的置换段不在步数账（零 bump 点被删）——`testProgressConstant-
  DoneEqualsTotalThroughRealLeg` 双档 done==total==15 亲跑绿。
- **落地 additive 面**：`landStackProduct` 四新参全 default-nil；
  nil 路径零漂移逐点亲核——`ghostSuppressionLayerStack(nil) = nil`（源码
  :156 guard 亲见）、`exposureEVs?[i] ?? 0` ≡ 旧 flat-zero、
  `implementationVersion ?? hdr ≡` 旧常量、`writeFloatTIFF` 缺省
  `WorkingSpace.colorSpace` ≡ 旧调用；ghostUnion 臂 = runHDRLeg 尾形同构
  （`contains(1)` 门 + `GhostMaskWriter.dilate + land`，runHDRLeg 自有落地
  逐行对照）。`testExistingKindLandingByteZeroDriftWithDefaults` 亲跑绿。
- **G1 腿级**：`testDoubleRunProductBitIdentity` 双 enqueue 产物 TIFF 字节
  相等亲跑绿（碰撞递增名不同、字节同）。

## §3 E-1（error，已修复闭环）——生产腿 LUT staticGrid 缺 merge.py:145 兜底

**发现**：`runMertensLeg` 首版内联构造 staticGrid（`mask[...] < 0.01` 游走）
**无** merge.py:145 的 `static.sum() < 64 → 全格 static` 兜底。对照面：
①merge.py:145 原文亲读有兜底；②01 面 `staticSampleMask` 有兜底 + 双向专测
（`testStaticSampleFallbackCoversAllMotionDegenerate`，01 checker minor-1
落地件）；③`MertensFusion.swift` 头注明文「The static-sample fallback of
merge.py:146 … is transplanted into `substituteLUTs`」——而生产腿经
`mertensStageSubstituteLUTs` 自建网格**绕开**了 substituteLUTs，兜底在
生产路径断链。plan KD-1 ④「LUT = 01 KD-3 的 129 点/通道」绑定语义被打破。
**后果**：staticCount==0（全运动退化）→ `percentileOfSorted` precondition
（:190 `precondition(!sorted.isEmpty)` 亲见）= 进程崩溃路径；1..63 →
LUT 饿采样静默偏离参考语义。可达性低（需运动覆盖近全帧）但非零。
**修复**（`358abd8`）：腿侧删除内联游走，改直调
`MertensFusion.staticSampleMask(motion: mask, ...)`——同一游走 + 同一兜底
单源化（非退化输入逐位零漂移：staticCount ≥ 64 时两形网格恒等，既有等价
测试钉面不变）。**回归**：`testStageLUTsFallBackOnAllMotionMask`
（all-motion → fellBack + 全格 true + streamed == 整帧 substituteLUTs +
129 点满 LUT）亲跑 passed (0.222s)；重建后定向 IOP **609/1/0** exit 0。

## §4 skip 22 身份表（逐个验身份，亲跑日志为证）

| bundle | skip 数 | 身份（亲跑日志行） | 判定 |
|---|---|---|---|
| IOP | 1 | `SkinRegionGeometryTests testVisionProviderOnSynthesizedFaceDrawing`（宿主 Vision 态，M5-1 在册） | ✅ |
| IOPParity | 3 | M5-1 在册三项（宿主总结行 451/3/0；日志交错静默形态 = 已登记 o-omp5 现象，本轮复现） | ✅ |
| Layers | 4 | AIMaskDeterminism / AIMaskSemantic（模型资产缺席）+ ColorMatchBakeGolden testBakeTimeBudget（env 门）+ GradeEnvelopePerfProbe（env 门） | ✅ |
| Library | 4 | LibraryBenchmarkHarness ×2（env 基准）+ LibraryGridModel 观察记录 + MetadataTests GPS（fixture） | ✅ |
| Sessions | 4 | CatalogBenchmarkHarness ×3（env 基准）+ Perf07MassApply（record-only） | ✅ |
| Export | **2** | QuickLookPerfProbe（LA_QL_PERF 门，M5-1 在册）+ **`MertensFusionPerfProbeTests`（LIGHTAMER_PERF_PROBE 门——本批 +1，日志 :474 原文亲见）** | ✅ |
| App | 4 | DepthGolden ×3（模型资产缺席）+ DepthPerfProbe（env 门） | ✅ |

**21+1 结构成立**：21 = M5-1 终验在册（12 env 探针/基准 + 6 模型资产 +
3 fixture），+1 = 本批 probe env 门。**零静默新跳过**。

## §5 UI / 键族 / perf / G4 审计

- **UI 三段接线**：`SessionBrowserView.onHDRMertens`（≥2 多选 gate 同形 +
  nil 隐藏；Robertson02 项 diff 零触碰亲证）→ 简形 sheet（标题/body/开始
  + 既有 `alert_cancel`；**零档位控件**，body 文案注明默认中档——xcstrings
  亲见）→ `ContentView` 机械穿线（与既有四 merge seam 同形）→
  `SessionCoordinator.mertensMergeHandler` → LightamerApp
  `enqueue(.hdrMertens, MergeParams(deGhost: false, tag: nil,
  mertensDeghost: "medium"))` + `toast_hdr_mertens_queued`——tier 显式、
  deGhost 恒 off、tag nil 三点读码亲证。sheet = SwiftUI `.sheet` 形；
  **`grep -rn "\.runModal(" App/Sources` = 0 命中亲跑**（L057 红线）；
  `LocalizationValue` 插值禁形 0 新增（仅 2 处既有：ExportInspectorView
  F-2 已知在案 + LightamerApp :1831 doc 注记，均 pre-existing 亲证）。
- **zh 键族**：五键尾块纯插入（diff = 插入块 + 文件尾 EOF 换行差——见
  obs o-1）；`zh-audit --check` 亲跑 **PASS 1643/1882**（1638/1877 +5 逐位）；
  零动态键（MergeKind 新 case 不进 Picker/文案亲核）。
- **perf.md 数字独立复算**：11648×8588 = 100,033,024 px；172.24s →
  0.5808 MPx/s ≈ 申报 0.58 ✅；levels = adaptiveLevels(8588) = 9、
  halo = 2^9 = 512、bands = ⌈8588/256⌉ = 34 ✅（公式逐项）；ru_maxrss
  6248MB < 8192 门 ✅；staged 写 4.73s / 驻留 2.9GB / 三起事故全环境侧
  （L077 亲见在册）与 DECISIONS §4/SUMMARY §4 三方一致。预算判据「无硬门
  出数记录、GPU 化未触发」与 OQ-6 原文吻合。
- **G4 evidence**：report.md + 脚本 + bench 源三件在案（evidence 域
  gitignore :80 亲证不入 git，DECISIONS §3.3 申报属实）；判据合理性 =
  非门值声明在册（OpenCV 内部常数未冻结——01 双验同口径）、四节结构形态
  （三因子积/金字塔对/凸包/fuse-before-substitute）+ ρ=0.990/max 0.105/
  凸包 0.9602/0.9270 与 VALIDATION 引用逐位一致；偏差归因三项（gray 系数
  Rec709 vs BT.601 / per-level 归一 / 层数未对齐）与 01 在案差异面吻合，
  无杜撰。adaptiveLevels(192)=3 亲算吻合。
- **G6 MANIFEST**：五行 Manual-Only 配方在册（双算法各一张 + 三档对比 +
  `_mertens` 分账核 + 重导入观感；连贯物体样张纪律 + 三档切换非 UI 通道
  替代配方如实登记）——配方质量合格，执行面如实挂账待回填。

## §6 VALIDATION pending-signoff 审计

- 形态正确：`status: validated-pending-signoff` = C 档第 3 停（phase 签核
  前停，结论给用户过目后翻 validated）——与 config `dual_acceptance` 串行
  二验流程自洽；双重验收表两格「待验收波落盘」如实留空。
- 内容一致性：七 bundle 拼表数字与执行批申报逐位同（本验收 §1 亲证闭合）；
  skip 22 身份拆解（12+6+3+1）与 M5-1 台账 + 本批 probe 亲证吻合；SC 对账
  IOP-HDR-06 三列锚 = 七测试文件 47 法（01 39 + 02 22 中 Mertens 族 34+
  RasterDomain 等——两批合计口径亲核成立）；六门 G1-G5 ✅ 与本验收 §2/§3/
  §5 亲证一致，G6 ✅ 配方在册/⏳ 证据待回填 = M3-4 挂账先例形态。
- **一处需随验收批补账**：Per-Plan Map 02 行终态 commits 缺验收批
  `358abd8`（E-1 修复）——已随本验收批增补（见 §8）。

## §7 逐 commit 边界 + 红线机检（亲跑）

| commit | 边界 | 判定 |
|---|---|---|
| `826fa5b` T1 | StackMergeService + MertensLegTests + MertensMergeKindTests（§3.1 申报）+ Project.swift + BUNDLE-MAP；subject 与 plan 提交约定逐字同 | ✅ |
| `5afa952` T2 | BandStreamer + StackMergeService（传递）+ MertensRasterDomainTests + Project.swift + BUNDLE-MAP | ✅ |
| `45bcfe4` T3 | SessionBrowserView + SessionCoordinator + ContentView（§3.1 申报）+ LightamerApp + xcstrings + MertensMergeUITests + Project.swift + BUNDLE-MAP | ✅ |
| `e52bd6f` T4 | MertensFusionPerfProbeTests + perf.md + Project.swift + BUNDLE-MAP；evidence/ 不入 git（§3.3 申报，gitignore 亲证） | ✅ |
| `17142f3` T5 | 纯 docs 七文件（SUMMARY/DECISIONS/VALIDATION/GOAL-STATE/TODO/LESSONS/AGENTS） | ✅ |
| `358abd8` 验收修复 | StackMergeService + MertensLegTests + BUNDLE-MAP（E-1 域内） | ✅ |

plan 外两文件申报合理性亲核：ContentView 穿线 = 零自有逻辑机械传递
（与既有 seam 逐字符同形）；MertensMergeKindTests 改写 = stub 所钉「未落地
态」被其点名的落地 plan 终结（01 KD-4 预宣告结构），14 法计数不变。
**红线机检亲跑全零**：批窗 `7d9708f..17142f3` 密封面（HDRMergeMath/
ExifPrecheck/Sidecar//Pipe/History//Graph//LightamerIOP/）= **0 行**；
`*.metal` = **0 文件**；`Project.swift` dependencies = **0 diff**（diff 仅
4 行测试登记）；phase 全窗 `0f7e10b..HEAD` 密封面仅 ExifPrecheck +91 =
01 批 mertensVerdicts 自身任务域（02 批窗零触）；runHDRLeg 函数体零 diff
（§2 亲证）；removed-lines 审计 = stub 体/refactor 迁移/landStack 签名与
nil 字面行（全部任务域内）。

## §8 观察项（5 obs，登记不阻断）与验收批账面动作

1. **o-1 xcstrings EOF**：五键尾块插入后文件尾换行符被剥（`\ No newline
   at end of file`）——历史键字节与顺序零触碰属实，纯文件尾 1 字节差异；
   下次触该文件顺手补回。
2. **o-2 01 验收 o-1 顺延**：G3④ 带循环 off-by-one（单行遗漏非假绿）——
   本批未触 `MertensFusionGoldenTests.swift`，按「不强制」继续挂账。
3. **o-3 omp-01 minor m-omp1 顺延**：01 DECISIONS §7 发丝带三处错——本批
   未触 01 DECISIONS，按「建议 02 触账时顺手」未触发（未触账），继续挂账。
4. **o-4 plan KD-1「decode 每源 1 次」措辞松**：实测面 = CIImage decode
   每源 1 次、**渲染** 2N−1 面（对齐段 + stage 段各一）；perf.md 自报
   「decode 渲染 2N 面」诚实，Robertson02 = 3N 渲染「少一档」结论不受
   影响——plan 侧量化措辞与 perf 口径的措辞差，登记备查。
5. **o-5 IOPParity skip 日志交错现象复现**：本轮宿主总结行 451/3/0 正确，
   `' skipped'` 行可 grep 数 < 3（o-omp5 已登记的 XCTest 输出交错 + 脚本
   口径差，非新问题）——沿用「宿主总结行为准」口径。

**账面动作**（本验收批同批落盘）：①E-1 修复 commit `358abd8` + 本
ACCEPTANCE 文件 + ②VALIDATION Per-Plan Map 02 行增补 `358abd8` +
③GOAL-STATE 验收续接点。

## §9 omp 二次验收（orchestrator 编排留位；严禁与本节之外的 zcode 结论并发）

- 结论：＿＿＿（PASS / FAIL + 证据指针；本节由 omp 路追加——串行硬约束）。
- 抽查建议配方：§2 生产腿审计锚（KD-3 逐字符 diff 重放 + landStack nil 臂
  零漂移四点 + in-pass provider 读码）+ §1 定向复跑（`--bundle IOP`
  MertensLegTests 14 法 + `--bundle Export` 缺省 probe skip）+ §3 E-1 修复
  面读码（staticSampleMask 单源化 + all-motion 回归法）+ §7 红线四条机检
  命令重放。

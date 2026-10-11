# M5-1-01 ACCEPTANCE-OMP — omp 独立二次验收路（双重验收第二路）

> 验收 2026-10-11（零共享上下文，独立执行不轻信首验）。
> 对象 = 10 commits `47a27be..e4acb70`（基线 `dcd02a8`，含首验验收批 `d134ad4` + 立卷 `e4acb70`）。
> **结论：PASS / 0 error + 0 minor**。与首验（PASS / 0E+3minor 全已修）无分歧；首验三 minor 的修复在位亲证。

## 0. 结论头

`PASS / 0 error + 0 minor`

| 维度 | 判定 |
|---|---|
| 定向双 bundle 亲跑对表 | **全命中**（Layers 438/3/0 / IOPParity 438/3/0，逐位 = 申报） |
| S1 数学审计 | **PASS**——三断言独立复算（numpy 独立特征分解路，200 组随机 SPD 对）+ 换基重构 + 缓存键字面逐位命中 |
| G5 恒等三态审计 | **PASS**——四态测试亲跑（IOPParity 轮）+ 三态结构读码亲证 |
| Oklab 统计域审计 | **PASS**——零 clamp 域政策 + 端 bin clamp + 统计全链 Oklab 读码亲证 |
| colormatch op 结构 | **PASS**——V50Order 36.5 add-only 纯插入 + Registry seed ABSENT + GradeCatalog 第 20 行 + kernel 52B ABI 双侧同构 |
| 红线机检 | **PASS**——密封面六路径 + Aces2Kernels.metal 零 diff；disable set / SPM / xcstrings 零触碰 |

## 1. 定向复跑（Bash 亲跑）

```
验收轮（2026-10-11，串行单宿主直启，跑前删孤儿 lra）
BUNDLE|Layers   |438/3/0|peakRSS=1164MB|170s ← 申报 438/3/0（958MB）命中
BUNDLE|IOPParity|438/3/0|peakRSS=6026MB|558s ← 申报 438/3/0（6667MB）命中
```

- 两 bundle 计数逐位命中申报；RSS 轮间漂移正常（Layers 958↔1170、IOPParity 6667↔6026，均远离 8G 门）。
- 跑前删 `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`（首验 §3 移交注记执行；本路未跑 App bundle，无 #6 发作面）。
- 本批 +38 法六文件亲数：Oklab 7 / Stats 10 / SolverGolden 10 / Module 7 / Parity 2 / Identity 2（`grep -c "func test"`，与首验一致）。

## 2. 数学抽查（numpy 独立实现，零共享代码路径）

| 断言 | 我方实测 | 门 | 判定 |
|---|---|---|---|
| ① OT 定义约束 `M·Σs·Mᵀ=Σt`（200 组随机非交换 SPD 对，相对） | **4.86e-15** | Swift 门 1e-10；首验 9.05e-15；checker 4.9e-15 | ✅ 同带 |
| ② 对角归约 S1 ≡ `diag(√(tᵢ/sᵢ))`（50 组，abs） | **8.9e-16** | ≤1e-6 | ✅ |
| ③ 各向同性 `Σs=σs²I,Σt=σt²I → M=(σt/σs)I`（20 组，abs） | **3.6e-15** | ≤1e-6 | ✅ |
| 换基重构（commuting 族 T_true 恢复，相对） | **1.58e-15** | G3 矩精确臂 ≤1e-3 | ✅ |
| S3 对角恢复（abs） | **0.0（精确）** | ≤1e-6 | ✅ |

注：我方首版脚本曾把 ③ 期望误写为 `(t/s)I`（方差比而非标准差比），得 3.088 即时发现为脚本错误——修正为 `√(t/s)I` / σ 形后 4.4e-16/3.6e-15。恰与本批 T4 发现的「S3 方差比→开方比」同类错误同构，佐证该修复的必要性。

缓存键 FNV-1a 64 独立复算（小端 8B×2 + tag UTF-8 链式，basis/prime 与 StableHash.swift 亲读同参）：

```
gaussianOT(0,0) = 2495982924697081349 ← 逐位命中 ✅
reinhard(0,0)  = 3458577883779271296 ← 逐位命中 ✅
(1,2) vs (2,1) 序敏感 = True ✅
```

## 3. SUMMARY + DECISIONS 核对（S1 三断言 / G5 四态 / Oklab 域宽 clamp）

- **S1 三断言**：DECISIONS §3 三明治正本拼写 `M = Σs^{−1/2}·(Σs^{1/2}·Σt·Σs^{1/2})^{1/2}·Σs^{−1/2}` 与实现（ColorMatchSolver.swift:238-253，inner→innerHalf→三明治）逐项对应；G1 数学结构双门 + 各向同性特例在 SolverGoldenTests 10 法内（本路 Layers 轮亲跑绿）。
- **G5 四态**：`testColormatchAbsentFromEditingSeed`（缺席：Registry 可解析 + 双 seed 无实例）+ `testIdentityStatesBlitByteExact`（禁用-commit 面零 uniform / strength=0 与 unsolved 双臂 blit + solved-strength-1 反空转 `XCTAssertNotEqual` :159）——读码亲证，IOPParity 轮亲跑绿。
- **Oklab 域宽 clamp**：转换面零 clamp（OklabMath.swift:40-41「clamps NOTHING」）+ 直方图域外端 bin clamp（ColorMatchStats.swift:15）——DECISIONS §1 域宽依据（20 万样本 a/b 极值）与政策自洽。

## 4. 读码抽查五项

1. **solveKnee 无关面**：`FilmPlacementModule.solveKnee(pullBack:rolloff:sceneExtreme:mediumBoundary:)`（:183-185）四形参，**无 `placementGain` 形参**；全仓 grep `placementGain` 零命中——本波无 placement 面改动，M3-3 锚落点未扰。✅
2. **`graph(from:high:)` 无 strength 形参**：全仓 grep `func graph\(from` 零命中——M4-2-03 终裁删除后 V2 RidgeExtract 面无残留；FollowEdges.swift 现状 = M2-7 熔断基线（V1 walker + `.snap` 默认）。✅
3. **`EdgeMapField.ridges` 未 reintroduce**：全仓 grep `RidgeExtract|RidgeGraph|withRidges|followEdgesRidge|\.ridges` 零命中；`EdgeMapField` 仅 width/height/values（FollowEdges.swift:81-84）；`readEdgeMap` 回缺省 512（:337）。✅
4. **colormatch_linear kernel 52B uniform ABI**：MSL struct 13 floats（mi0-8/c0-2/strength，ColorMatchKernels.metal:74-80，字段序）≡ Swift `ColormatchUniforms` 13 floats 同序（ColorMatchUniforms.swift:20-25）+ `expectedStride = 52`（:29）——双侧同构亲证；`precise::pow` 符号保持 cbrt（:61-66）与 CPU 侧 `Float(1.0)/Float(3.0)` 同拼写（kOneThird :52）。✅
5. **V50Order 36.5 add-only**：`git diff dcd02a8..HEAD` 该文件 = 纯插入 10 行（9 行 LIGHTAMER-NATIVE 注记 + `("colormatch", 36.5)` 一行），零删除零重排；colortransfer 37.0 / colormapping 38.0 verbatim 行零触碰。✅

附加亲证：jacobi 列抽取 stride-3 修复在位（:357-359 注释 + `v[c0],v[3+c0],v[6+c0]`）；S3 开方比 `(t/s).squareRoot()`（:233）；R1 双臂门（rankFloorRelative 1e-9，:166；零迹补臂 :195-196）；`strengthKernelTerms` M−I 逐对角减 1（:407-414）；SolveCache LRU 8 + invalidateAll（ColorMatchSolveCache.swift:25/71）；Registry seed ABSENT 注记（Registry.swift:117-123）；GradeCatalog 第 20 行 owner `.grade` + panelExposures `["strength"]`（NodeOwnershipCatalog.swift:274-277）。

## 5. 红线机检（Bash 亲跑）

```
git diff dcd02a8..HEAD -- Lut3d/ Sidecar/ Pipe/History/ PipeCacheKey.swift
  PipelineDocument.swift Graph/NodeGraphCommand.swift Drt/Aces2Kernels.metal → 空（全绿）
Registry.swift diff 中 defaultFaceDisabledOpNames 触碰 → 0 行
.metal 新增面 → A ColorMatchKernels.metal 唯一
Project.swift package 行 → 0（零新 SPM）
sidecar/xcstrings → 零改动（diff 零命中；zh-audit 首验 PASS 佐证）
```

## 6. 与首验分歧点

**无分歧。** 首验三 minor（BUNDLE-MAP 9→10 / 死 helper 去重 / McpHostTests 注释 15→16）的修复 commit `d134ad4` 在本路基线内，定向轮已覆盖回归（Layers/IOPParity 逐位绿）。首验 §8 移交注记（App 轮前删孤儿）本路执行，未跑 App 故无 #6 复发观察项。

挂账继承（非本批缺陷）：M4-1 挂账 #6 持续在案；IOP 贴线余量监视口径维持；M5-1-02 待启（面板/S2/cube 资产/prewarm/xcstrings 键族）。

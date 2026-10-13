# M5-3-01-ACCEPTANCE-OMP — omp 独立二次验收（第二路）

> **结论头：PASS / 0 error + 1 minor**
>
> 第一路 = zcode 首验（`M5-3-01-ACCEPTANCE.md` §一..§六）：PASS / 0 error + 3 minor。
> 本文件 = 第二路 omp 独立二验（2026-10-13，串行于首验之后执行）。五步全部独立亲跑
> （非转述首验数字），分歧点见 §六。

---

## 一、亲跑对表（两 bundle，exit 0，独立复跑）

| bundle | 本轮（亲跑） | 首验/申报 | 对表 | peak RSS | MEMFAIL |
|---|---|---|---|---|---|
| IOP | **642/1/0**（165s） | 642/1/0 | ✓ 逐位 | 7209MB | 0 |
| Library | **636/4/0**（78s） | 636/4/0 | ✓ 逐位 | 617MB | 0 |

- 命令：`caffeinate -dis Scripts/test-direct.sh --bundle IOP` / `--bundle Library`
  （直启宿主，无 testmanagerd），输出尾 `OK (direct launch, no testmanagerd)`。
- IOPParity 未在本次派遣指令内（指令只列 IOP/Library 两束），未复跑；
  G1/G2 门由 IOP 内 PanoCameraTests/LM 恢复面 + §二数学复算侧证（非逐位替代，
  见 §六分歧 d-3）。
- 法数对账：`grep -c "func test"` 六新文件 = 9/9/7/8/5/5，
  与 BUNDLE-MAP 增行（IOP 9+9+7+8 / LIB 5 / IOPP 5）逐行一致，
  与申报增量 609+33=642 / 631+5=636 一致。

## 二、数学复算（uv + numpy 独立实现，脚本 `/tmp/omp_pano_audit.py`，与产线零共享代码）

复算面 = Hartley DLT / f 闭式两式及尺度不变性 / 置信度原形+上界+真值表 /
自适应迭代表 / wave correct 幂等+符号。**11/11 PASS**：

| 审计项 | 结果 |
|---|---|
| DLT 已知 H 精确恢复 | PASS（max\|ΔH\| = 8.88e-16 ≤ 1e-9） |
| f 闭式两式（f=800，Rx8°+Ry25° 复合旋转） | PASS（800.000000000000 / 800.000000000000） |
| f 两式尺度不变性（H×7.3） | PASS |
| f(H=I) 双分母为零 → nil 等价 | PASS |
| 置信度真值表 6 行（OpenCV 原形） | PASS（≤1e-12） |
| 置信度上界 → 10/3（m→∞） | PASS（3.333333） |
| `1−` 形不可能承载 10/3（sup=1） | PASS（D-1 勘误被迫成立） |
| 边门语义（conf(10,10)>0.6 ∧ conf(5,100)≤0.6） | PASS |
| 自适应迭代表 w=0.3/0.5/0.7/0.9 | PASS（N=850/108/26/7） |
| wave correct 幂等（二次零变化） | PASS（max\|d\|=0.0） |
| wave correct 符号 Σx≥0 | PASS（Σx=0.0070） |

- **复算侧诚实注记**：脚本首轮 2 FAIL 均为脚本自身 bug——①f 段误用纯 yaw
  旋转（正交式分母 c0z·c1z 恒零，数学上该式在纯 yaw 下本来无定义；
  产线 `focalFromHomography` 对此有 `abs(denominator) > 1e-12` typed 守卫，
  合议复算改复合旋转后双式机器精度恢复）；②漏 `import math`。与首验同款
  「脚本 bug 反证产线守卫」形态（首验 §二注记三 bug）。
- **LM BA 未数值复算**（dgesv LM 全复刻超出二验预算）：以读码替代——
  `bundleAdjust` 参数向量 `1 + 3*imageCount`（3N+1 ✓）、弦角残差世界侧
  `rotate(ri.transposed(), d1)`（D-6 ✓）、前向差分稠密 Jacobian +
  列主序 dgesv（H+λ·diag(H) ✓）、λ ÷3/×10 自适应 + 1e12 爆炸退出 ✓、
  数据相对判据 `cost ≤ initialCost·(1−improvementFloor)` 三退出路径统一裁决 ✓、
  `Mat3D`/`rotation(fromAxisAngle:)` Rodrigues 形 cI+sK+(1−c)kkᵀ 逐行核对正确 ✓。
- wave correct 读码：S = Σrow₀ᵀ·row₀ + 最小特征向量 Jacobi + Σ 投影符号定向 +
  右乘 `Rᵢ·R_corrᵀ`（头注钉 load-bearing ✓，与复算实现同形）。

## 三、红线机检（亲跑命令，非转述）

```
grep -rnE "SystemRandomNumberGenerator|srand|arc4random|\.random\(" Stack/
  → 0 命中（覆盖 checker minor-4 硬化后模式，含 .random( 族）
git diff c38eef3..HEAD -- LightamerIOP/ Sidecar/ Pipe/ Graph/ '*.metal' → 0 行
git diff c38eef3..HEAD -- '*ExifPrecheck.swift'                          → 0 行
git diff c38eef3..HEAD -- Project.swift → 8 行 = 6 个 +登记行 + 2 头行；
  dependencies/package/product 零命中（首验 m-c 勘误：6 登记行非 5，本轮亲证 6）
```

- **PanoRNG 读码**：`state = state &* 6364136223846793005 &+ 1442695040888963407`
  （MMIX 常数 ✓），`defaultSeed = 121` ✓；`ransacHomography(_:rng: inout PanoRNG…)`
  唯一流 + `ransacMaxIters = 3000` + `ransacConfidence = 0.999` + `ransacThreshold = 3.0` ✓。
- **checker ①-⑤ 回注对表**：①minor-1 属 M5-3-03 面，本批无动作 ✓；
  ②minor-2 双缝已落地（`rgbaLinear`/`rgbaEncoded` 双 `preparePreviewGray` +
  头注引 checker-minor-2 + 双重编码发散负测 :117-127 ✓）；
  ③minor-3 属 M5-3-02 面 ✓；④minor-4 grep 门 `\.random\(` 在案，
  SUMMARY 申报「T6 实跑 0 命中」，本轮亲跑 Stack/ 全域 0 命中复核 ✓；
  ⑤minor-5（L077 runbook）属 M5-3-02 探针面 ✓。
- MIT 锚：三 pano 文件头归属注记齐备（1200/:215、6000/:219、seed121/:220、
  <10/:223-224、Lowe0.3/:227、边门/:231-233、BFS/:235-238、refinement/:243-245、
  RANSAC/:62 注记行均亲见）；`loweRatio = 0.3` / `edgeConfidence = 0.6 strict >` /
  `edgeMinInliers = 10` / `featureCap = 6000` / `previewMaxEdge = 1200` /
  `dimensions = 128` 常量逐值亲证。

## 四、additive / typed / 词汇核验（读码 + 测试代码点验）

- **MergeKind.pano additive 四臂**：`case pano = "pano-merge"` ✓ /
  `provenanceKind → .panoMerge` ✓ / `defaultTag → "pano"` ✓ /
  `stepTotal → sources*3+6`（N=2/3/5 直查 ✓）/ `runProductionMerge → runPanoLeg` ✓。
  另亲证第五 switch 在 `runStackAggregateLeg` 内带 default 不破（checker §五主张成立）。
- **typed stub**：`runPanoLeg` = `throw AppError.invalidParameter(
  "pano-merge production leg lands in M5-3-02")`，M5-2-01 KD-4 同形 ✓；
  测试断言 `.failed(.invalidParameter)` + stub 路径恒式 `2N+5 + settle 1 + decode N = 3N+6` ✓。
- **32 门 kind 条件式**：`if kind == .pano, sources.count > 32` 纯 additive if ✓；
  反测 = `.hdrMerge` 33 张照常 enqueue 且 `total == 33*2+3` HDR 公式逐字节 ✓（:187-212 亲读）。
- **MergeParams 三字段**：init 尾参缺省 nil ✓；旧档 7-key golden JSON 双向逐字节
  零漂移（`testLegacyMergeParamsEncodesByteIdentical` +
  `testLegacyJSONDecodesAndReencodesByteIdentical` ✓）+
  单字段出现语义双文件钉死（MergeKind :232-235 + Provenance :76-82 ✓）。
- **typed 三态词汇**：`FailurePrefix.alignment/disconnected/canvas` 三常量字面
  与 KD-4 逐字符一致（含尾随空格）✓，`matchConfidence = inliers/(8+0.3·matches)` ✓。
- **六既有 kind 快照**：tag 六值 + stepTotal 六式（hdrMerge 双旋钮）逐值快照 ✓；
  `MertensMergeKindTests` 6→7 为 e561395 内 8 行两处计数（ additive 编译级连带，
  首验判定合理，本轮认同）。
- **Provenance 镜像**：两 Kind 枚举 raw 值全表逐一对齐断言 ✓ +
  `"spherical-feature-panorama"` / `"1"` 与 HDR/Mertens 身份互异断言 ✓。

## 五、逐 commit 边界（七提交亲核 git show --stat）

| commit | stat 亲核 | 判定 |
|---|---|---|
| `3fa930a` T1 | PanoFeature 617 + 测试 404 + Project +1 + MAP +9 | ✓ |
| `96056d7` T2 | PanoMatch 535 + 测试 243 + 登记 | ✓ |
| `c6f020b` T3 | PanoCamera 442 + 测试 233 + 登记 | ✓ |
| `8ec142e` T4 | Service +58/-1 / Replay +11 / 两测试 / 登记 +2/+2 | ✓ |
| `e591c89` T5 | PanoCamera 115 行探针修复 + Golden 430（SUMMARY T5 行已申报） | ✓ |
| `e561395` T6 收口 | SUMMARY/DECISIONS/GOAL/TODO + Mertens 计数 8 行 | ✓（m-a 时序同首验） |
| `c0eb1f5` T6 chore | Project +1 / MAP +1（Golden 登记） | ✓（m-b 时序同首验） |

- 批间三 docs 提交（67e2de0/c38c1c4/e40244e LightCraft）零代码 ✓。
- 首验 m-a/m-b/m-c 三 minor：m-a、m-b 时序观察属实（内容正确、HEAD 完备，
  无需修复）；m-c 本轮亲证确为 6 登记行——首验「实为 6 行」勘误正确，
  SUMMARY「5 行」字面仍错（账面项，随 M5-3-02 收口文档顺手订正即可）。

## 六、与首验分歧点 + 本轮 minor

- **d-1（认同）**：D-1 置信度勘误成立——本轮 A3c 独立复算 `1−` 形 sup=1
  不可达 10/3，与首验 §二判定一致。
- **d-2（认同）**：G2 对应段换轨申报合理——合成点阵描述子近简并是 fixture 域
  结构性歧义；硬上限未动 + 匹配质量由 T1 判别性测试与 G1 分担，判据与首验一致。
- **d-3（覆盖差异，非分歧）**：首验亲跑三束含 IOPParity（G1/G2 逐位）；
  本次派遣指令只列 IOP/Library 两束，故 G1 bit-identity 与 G2 三门未逐位复跑。
  替代证据 = PanoCameraTests LM 恢复面（IOP 内全绿）+ §二独立复算 11 项
  + Golden 断言字面亲读（f≤5%/R≤2°/inlier≥60% 硬上限在码 :337-366）。
  G1/G2 逐位以首验亲跑为准，本轮不重复声称。
- **m-omp-1（minor，账面）**：`M5-3-CHECKER.md` §二「置信度公式 `1 − …`：OpenCV
  detail 公式正确」一句仍按 plan 笔误原文背书，与 D-1 勘误（OpenCV 原形无 `1−`）
  矛盾——checker 行文本级过期，不影响任何代码/测试结论；建议 M5-3-02 收口时
  在 CHECKER 或 DECISIONS 追一笔勘误注记。本轮唯一 minor。

---

**两路合计**：首验 PASS / 0E+3minor（m-a/m-b/m-c）+ 本轮 PASS / 0E+1minor
（m-omp-1，checker 行账面过期）。零代码修复项。建议 → C 档第 2 停
（战果汇报 + M5-3-02 摘要等用户确认）。

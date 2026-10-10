# M5-1-01 ACCEPTANCE — zcode 独立验收路（双重验收第一路）

> 验收 2026-10-11（夜间双重验收窗；零共享上下文 subagent，实测核验不轻信）。
> 对象 = 9 commits `47a27be..b97cf8f`（基线 `dcd02a8`）+ 验收批小修（见 §7）。
> **结论：PASS / 0 error + 3 minor（全已修）+ 2 obs**。omp 二次验收（串行）
> 结论追加于 §8（本文件由 zcode 路立卷；omp 路到货后由 orchestrator 回填）。

## 0. 结论头

| 维度 | 判定 |
|---|---|
| 定向四 bundle 亲跑对表 | **全命中**（Layers 438/3/0 / IOP 563/1/0 / IOPParity 438/3/0 / App 711/4/0——App 首轮 711/4/1 = M4-1 挂账 #6 已知孤儿 sidecar 污染，因果闭环后净树 711/4/0，§3） |
| S1 数学审计（灵魂） | **PASS**——三断言独立复算（numpy 独立特征分解路，200 组随机 SPD 对）+ 极因子等价亲验 + 缓存键字面复算逐位命中（§4） |
| G5 恒等三态审计 | **PASS**——四态测试亲跑 + 反空转 + seed ABSENT 双面结构断言读码亲证（§5） |
| Oklab 统计域审计 | **PASS**——常数推导独立复算（M1C/M1C⁻¹ 与文字量 6.8e-12/2.1e-11 吻合）+ 白点/灰轴/原色锚/域宽/f32 往返带全复核（§6） |
| colormatch op 结构 | **PASS**——V50Order add-only 107 亲跑 + Registry seed ABSENT 双面 + GradeCatalog 第 20 行 + IopCatalog 键集闭合 + templateInstance 前置缝在位 + kernel 52B ABI + metallib 吸收亲证（§6.3） |
| 逐 commit 边界 | **PASS**——九提交对照 front-matter；红线机检全绿（§7） |
| zh-audit | **PASS**（1617 source / 1855 catalog keys，与申报逐位一致） |

**min_votes 语义**：单路验收（跨夜串行单 subagent slot）；error 零项无需裁决；
三 minor 均为账面/卫生级，当场修复并回归（§7）。

## 1. 亲跑数字（对表）

```
验收轮（2026-10-11 03:04-03:33，串行单宿主直启）
BUNDLE|Layers   |438/3/0|peakRSS=1170MB|173s   ← 申报 438/3/0（958MB）命中
BUNDLE|IOP      |563/1/0|peakRSS=7922MB|164s   ← 申报 563/1/0（6848MB）命中；< 8192 门
BUNDLE|IOPParity|438/3/0|peakRSS=6539MB|553s   ← 申报 438/3/0（6667MB）命中
BUNDLE|App      |711/4/1|peakRSS= 2832MB|363s  ← 申报 711/4/0，1 fail = 挂账 #6（§3）
净树复跑：BUNDLE|App|711/4/0|peakRSS=2832MB|360s     ← 删孤儿后逐位命中申报
小修回归：BUNDLE|Layers（§7 修复后重跑，尾注）
zh-audit --check：PASS（1617 source keys / 1855 catalog keys）
```

- IOP 本轮 peakRSS 7922MB vs 申报轮 6848MB——同 bundle 轮间漂移（AGENTS 记载
  IOP 贴线族 ±3% 级方差在案；本轮 < 8192 门，无 MEMFAIL，机检兜底未触发）。
- 本批 +38 法六文件全部到岗：Oklab 7 / Stats 10 / SolverGolden 10 / Module 7 /
  Parity 2 / Identity 2（`grep -c "func test"` 亲数；BUNDLE-MAP 账面勘误见 §7 m-a）。
- 运行期对账亲证：IOP 562→563（V50OrderTests +1）、IOPParity 427→438（+11）、
  Layers 411→438（+27 = 7+10+10）、App 704→711（M4-3 存量，本批零新 App 文件）。

## 2. 逐 commit 边界（九提交对照 front-matter）

| commit | 申报 | 亲核 |
|---|---|---|
| `47a27be` T1 | OklabMath + 7 法 | ✅ 文件/方法数/常数单源头注在位 |
| `1d16b5f` T2 | ColorMatchStats + 10 法 | ✅ E4 三敏感断言（矩位/支撑位/计数）在位 |
| `c4fa099` T3 | Solver + Cache | ✅ 三明治形 + R1 双臂 + LRU 8 |
| `97a1c32` T4 | SolverGoldenTests 10 法 | ✅ 含两枚执行期真缺陷修复（jacobi stride / S3 开方）——T3 文件在本 commit 修，修因与 DECISIONS §3 一致 |
| `518bd87` T5 | op 落位 + 五测试钉数 | ✅ V50Order/Registry/GradeCatalog/IopCatalog/EditorState/templateInstance 全在位；L050 机制穷举修正（defaultFaceOps 16）合理（ops 19 − D1 三件，禁用集亲读） |
| `0817115` T6 | kernel + uniforms | ✅ 52B ABI 双侧同构 |
| `fff0635` T7 | Parity 2 法 | ✅ 含 kernel `precise::pow` 精化（T7 内修 kernel = 批内演进，commit message 记因在案：MSL fast-math 近似形） |
| `b83db8f` T8 | Identity 2 法 | ✅ 三态 + 反空转 |
| `b97cf8f` T9 | 收口 | ✅ SUMMARY/DECISIONS/GOAL-STATE/TODO 同批 |

- **plan 勘误合理性亲核**：`defaultFaceOps == 15 钉不动` 机制证伪成立——
  `defaultFaceDisabledOpNames` = D1 三件（filmicrgb/sigmoid/agx；denoise 三件
  不在 IopCatalog.ops）→ 19−3 = 16，DefaultFaceTests 新钉 16 与机制自洽。
- 实际受波及断言 7 处 vs plan 点名 5 处（DECISIONS §5 自曝）——逐处亲读，
  无漏网（McpHostTests 一处注释计数漏改 = m-c，§7）。

## 3. App 首轮 1 fail 因果闭环（非本批缺陷）

- 失败 = `RasterEditFaceTests.testRestoreWinsOverDerive`（App bundle，
  RasterEditFaceTests.swift:192）：restore 腿读回 `p3_d65`/peak400 记录 ≠
  `editedRecord()`（rec709/100）。
- 留证：`Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`（untracked 孤儿，
  本 session 起始 `git status` 已在；SHA-256
  `045163e9dea72a591b3bd4b226872ac21f8e1691b1fedc544f2ed0471d6e1bd3`，其内
  drtRecord.encoding_space = `p3_d65` 与失败值精确吻合；mtime 03:39:45 =
  轮内晚到 debounce 复写）。
- 机制 = **M4-1 挂账 #6 已知形态**（M4-1-02-ACCEPTANCE-OMP omp-minor-1 定根因；
  M4-2-01/M4-3-01 两轮验收各自闭环同款）：同 fixture 孤儿 sidecar 抢坐
  `flushUntilPersisted` 判定窗 → restore 腿读到他者记录。修复方向在案
  （写方改 tmp 域拷贝 + 双前清），挂账批未到。
- **闭环实验**：删孤儿 → 净树复跑 App 全量 = **711/4/0**（逐位命中申报）；
  跑后孤儿由 App 轮自身晚到 debounce 再生（挂账 #6 机制复证）。与 colormatch
  批零相关（本批不触 DRT/Raster 面；`git diff dcd02a8..HEAD` 亲证零交集）。
- **移交注记（给 omp 二次验收路）**：跑 App bundle 前先删
  `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`，否则预期同款 1 fail。

## 4. S1 数学审计（灵魂——独立路复算）

工具 = numpy（`np.linalg.eigh` 独立特征分解路 + `np.linalg.svd` 极分解），
与本批 Swift 实现零共享代码路径；脚本 = /tmp/m5-1-01-acceptance-audit.py（即弃）。

### 4.1 三断言（200 组随机非交换 SPD 对）

| 断言 | 我方实测 | 申报/门 | 判定 |
|---|---|---|---|
| ① OT 定义约束 `M·Σs·Mᵀ=Σt`（相对） | **9.05e-15** | 申报 1.08e-12（Swift 门 1e-10；checker 处方数值复核 4.9e-15） | ✅ 同带 |
| ② 对角归约 S1 ≡ `diag(√(tᵢ/sᵢ))`（50 组，abs） | **7.1e-15** | 门 ≤1e-6 | ✅ |
| ③ 各向同性 `Σs=σs²I,Σt=σt²I → M=(σt/σs)I`（20 组） | **8.9e-16** | 门 ≤1e-6 | ✅ |

### 4.2 三明治 vs 极因子等价（checker 复查轮补正亲验）

- 正形 `U = polar(Σt^{1/2}·Σs^{1/2})`：`|M_polar − M_sandwich| ≤ 6.4e-15`
  （20 组非交换对）——两形数值恒等亲证。
- checker 证伪形 `U = polar(Σt^{1/2}·Σs^{−1/2})`：满足约束（<1e-10）但
  **Trace 缺口最坏 1.05e-2 相对**——与 DECISIONS §1/§3「Trace gap ~1e-2」
  逐位同带，亲证实现择形正确（最优三明治，非证伪拼写）。

### 4.3 秩亏回落 R1 路径（读码 + 测试亲跑）

- 读码：`solveMatrix64` 对正则化后源协方差取秩门
  `min ≤ 0 ∨ min < 1e-9·trace` → 回落 S3 路径 + `effectiveSolver = .reinhard`
  记账（params solver 保持用户选择；`.reinhardFallback` 不入枚举 = checker m2
  两值纪律）；零 trace 面 = 恒等矩阵 + 纯 offset（`min ≤ 0` 补臂防 1/√0=inf）。
- `testG1DegenerateFallbackDeterministic` 亲跑绿（Layers 轮）：零 trace + 秩亏
  两面双跑同 `effectiveSolver` 同解；零 trace 面恒等+offset 断言在位。

### 4.4 缓存键字面复算（FNV-1a 64 独立实现）

```
gaussianOT(0,0) = fnv_le(0)⊕fnv_le(0)⊕"colormatch.solve.gaussianOT.v1"
              = 2495982924697081349   ← 与 DECISIONS §3/测试钉死值逐位一致 ✅
reinhard(0,0)  = 3458577883779271296  ← 同上 ✅
(1,2) vs (2,1) 序敏感 = True ✅
```
（小端 8B × 2 + tag UTF-8 链式 FNV-1a，basis 0xCBF29CE484222325 / prime
0x100000001B3——StableHash.swift 亲读同参。）

### 4.5 执行期修复两枚的事后验证

- jacobi stride 修复：`jacobiEigen` 返回列按 stride-3 抽取（v[j],v[3+j],v[6+j]）
  读码亲证；我方审计的约束带 9e-15 与修复后申报 1.08e-12 同带（修复前 ~1.6）。
- S3 开方修复：`reinhardMatrix64` = `(t/s).squareRoot()` 标准差比亲读；
  4.1②断言即其数学面。

## 5. G5 恒等三态审计

`ColormatchIdentityGoldenTests`（IOPParity 轮亲跑绿）+ 读码核：

1. **缺席**：`testColormatchAbsentFromEditingSeed` —— Registry 注册可解析
   （makeBox 非 nil = add 面）+ 全 face/default face 双 seed 无 colormatch 实例
   + disable set 不含 colormatch（三断言 = seed ABSENT 双面结构亲证）。
2. **禁用**：commit 面零 uniform（`piece.data == nil`）+ 管道层跳过 =
   ModuleInstance 既有契约（本批零触）；测试断言 commit 面。
3. **strength=0 + unsolved**：`testIdentityStatesBlitByteExact` 双臂逐字节
   （`XCTAssertEqual(a, plane)` 全平面 Float4 数组比对 = 逐字节）——默认实例
   （strength 0）与 strength=1-but-hashes-missing（手工改 params 无法半渲染）
   都走 `makeRoutedCommandBuffer` blit（L031 路由面，跨队列安全）。
4. **反空转**：solved + strength=1 实例 `XCTAssertNotEqual(c, plane)`——恒等
   面是「op 选择恒等」而非「kernel 恒 copy」。
5. **基线零漂移旁证**：IOP 563/IOPParity 438 全绿 = 既有 op 零触碰（红线 diff
   零命中为主证，§7）。

## 6. Oklab 统计域审计

### 6.1 常数独立复算（numpy，自 BT.2020/709 色度推导）

- `M1C = M1·M(2020→709)`（M(2020→709) = M709⁻¹·M2020）vs 文字量：**6.8e-12**；
  `M1C⁻¹ = M(709→2020)·M1⁻¹` vs 文字量：**2.1e-11**——11 位有效数字印刷精度
  面，吻合（头注推导与硬编码自洽；M2/M2⁻¹ = Ottosson 公开常数逐位）。
  注：首轮审计脚本曾得 rel 0.69——系我方脚本把 M(2020→709) 方向写反
  （M709·M2020⁻¹），修正方向后逐位吻合；literal 正确。
- 白点 (1,1,1) → (1, 0, 0) ✅；M1C 行和 = (1,1,1) = 灰轴中性 ✅。
- Rec2020 三原色锚：真链（rgb→XYZ→709rgb→M1→cbrt→M2）与 literal 链两路
  独立计算逐位一致，且与测试硬编码 8 位锚一致（R 0.68708904/G 0.82977721/
  B 0.42344826）——「Rec2020 红不落 sRGB 红锚」的组合链活性亲证。
- f32 往返带：同驱动族 numpy 复现 worst **8.26e-7** 相对（申报 1.19e-6、
  门 1e-5）——同带 corroborate。
- 域宽依据（Rec2020 凸包 a ∈ [−0.638,+0.546]、b ∈ [−0.537,+0.339]，Y≤4 抽样
  20 万）与端 bin clamp 政策自洽（DECISIONS §1；测试端 clamp 断言在位）。

### 6.2 统计域/求解域全链 Oklab 亲证

- `ColorMatchStats` 输入输出全 Oklab 域（binIndex/binValue 域常数 L[0,1]/
  a,b[±0.5]）；kernel 单 pass 出入均 working linear Rec2020（MSL 尾注 +
  parity 测试 L048 比较域断言头注）——OQ-2 生效值落位。
- 三组闭式矩手算复核（μ/σ 六槽/99 除子全对）；E4「同直方图异矩翻哈希」
  负测在位（mu +1e-7 位翻 → hash 翻，直方图逐字节相同前提断言在位）。

### 6.3 colormatch op 结构（T5/T6 落位亲证）

- V50Order：`("colormatch", 36.5)` 单行插入（lut3d 36.0 与 dt verbatim
  colortransfer 37.0 之间；LIGHTAMER-NATIVE ROW 注记全式）；V50OrderTests
  107 + 36.5 唯一性 + <70 floor 断言亲跑绿（IOP 轮）= **add-only 106→107**。
- Registry：additive 注册块 + seed ABSENT（CAT02/filmPlacement 同款注记）；
  `defaultFaceDisabledOpNames` 零触碰（diff 亲证仅注册块 +10 行）。
- GradeCatalog 第 20 行（owner `.grade` + identityJSON = Params() +
  panelExposures ["strength"]）；GradeCatalogTests 20/16/19 三钉亲跑绿。
- IopCatalog additive 行七键（solver/matrix/offset/strength/双 hash/
  effectiveSolver）；反射 guard `checked == 19` 回落 GradeCatalog identityJSON
  （seed-absent ops 供字节单源）——亲读在位，App 轮亲跑绿。
- templateInstance colormatch case（E2 前置缝）在位（EditorState.swift :977）；
  CatalogAddFaceTests 14 行含 colormatch 亲跑绿。
- kernel ABI：MSL struct 13 floats = ColorMatchUniforms 13 floats 字段对齐 +
  size-probe 断言（52B）在 parity runner 内每跑必检；零 function constants；
  metallib 亲证 = fresh 容器含 `colormatch_linear`（metal-objdump + strings
  4 命中；mtime = 本批时段）。

## 7. 红线机检（`git diff dcd02a8..HEAD` 亲跑）与验收批小修

红线全绿：密封面六路径（Lut3d/ Sidecar/ Pipe/History/ PipeCacheKey/
PipelineDocument/ Graph/NodeGraphCommand）diff **0 行**；`.metal` 新增面 =
ColorMatchKernels.metal 一文件一 kernel；V50Order add-only；零新 SPM
（Project.swift diff = 6 行测试编列亲读）；disable set 零触碰；sidecar 零
schema；xcstrings 零改动（zh-audit PASS 佐证）。

**验收批小修三枚（`fix(m5-1-01)` 单提交）**：

- **m-a** BUNDLE-MAP `ColorMatchSolverGoldenTests.swift` 记 9 → 实 10 法
  （`grep -c` 亲数；SUMMARY +27 = 7+10+10 与 Layers 411+27=438 双向对账佐证）
  → 已改 10。
- **m-b** SolverGoldenTests 死 helper `transpose(_ simd_double3x3)`（体 =
  rowMajor，语义误导陷阱）删除 + 同测试文件内一处重复断言（157-160 双写
  同断言）去重——非行为变更（同 10 法同断言面），Layers 轮回归绿。
- **m-c** McpHostTests 规范文本注释 "narrowed 15" → 16（19−D1 三件；T5 批改
  18→19 时漏同步的注释计数）——注释级，零编译面。

## 8. omp 二次验收（串行）——待 orchestrator 派遣后回填

- 结论：（待 omp 路）
- 配方注记：App bundle 跑前删孤儿 sidecar（§3）。

## 9. 移交与挂账

- M4-1 挂账 #6（孤儿 `.lra` 写侧卫生）持续在案——本轮两度发作 + 因果双闭环，
  修复批催办维持。
- IOP peakRSS 轮间漂移（6848↔7922MB）贴 8G 门余量收窄——维持 AGENTS 贴线
  bundle 监视口径；M5-1-02/03 批新增 parity 测试继续走小 fixture 纪律。
- G2 双面门（良态 ≤1e-5 + 交越界 2.95e-3/3.68e-2 钉门）的机制注记
  （cbrt LMS≈0 交越导数无界）经我方独立审阅成立——1e-5 单一目标在交越像素
  数学不可达的论证接受；非降级交付。

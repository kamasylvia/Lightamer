# M5-1-02 ACCEPTANCE — zcode 独立验收路（双重验收第一路）

> 验收 2026-10-11（夜间双重验收窗；零共享上下文 subagent，实测核验不轻信）。
> 对象 = 批内 7 commits `14d032d..4cc1c52` + T9 `abc46c0` + 补提交 `9c61c48`
> + 验收批小修 `cbd1afa`（基线 `e4acb70`）。**结论：PASS / 0 error + 3 minor
> （m-a 已修 `cbd1afa`，m-b/m-c 账面注记级）+ 3 obs**。omp 二次验收（串行）
> 结论追加于 §9（本文件由 zcode 路立卷；omp 路到货后由 orchestrator 回填）。

## 0. 结论头

| 维度 | 判定 |
|---|---|
| 定向四 bundle 亲跑对表 | **全命中**（Layers 466/4/0 / IOPParity 444/3/0 / App 724/4/0 / IOP 563/1/0，零 MEMFAIL；**以 HEAD `9c61c48` 重建产物后亲跑**——现成产物早于补提交，直接复用会漏测 resolver forward，§1） |
| S2 数学审计（灵魂） | **PASS**——整数交叉相乘分位对齐独立复算（Fraction 精确有理数路 + 20 万组随机对）+ 量化对齐独立实现复现单调/中位映射 + Float32 截断勘误机制复现 + bake 体素门/恒等带全晶格独立复算同带 + `.cdf` 缓存键字面独立 FNV 复算（P1 双键逐位命中锚定转写正确性）（§3） |
| 池化确定性审计 | **PASS**——6 排列逐字节同池化亲跑（测试绿）+ 二阶矩公式锚 Fraction 独立复算全六槽精确命中 + statsHash 升序规范化读码 + 取整回整数秩（2.5→3 / 22.5→23 钉测在位）（§4） |
| LUT 臂三臂状态机 + E5/E6 审计 | **PASS**——Arm{identity,linear,lut} 分派读码 + 恒等 uniform 盒与 MSL `Lut3dUniforms` 96B 布局逐字段镜像亲核 + armed input-tap 一次性捕获读码 + E6 管线级提取（throwaway cache 无头渲染 + live==headless 同值断言亲跑）+ attach store 级投影缝（projectColormatch upsert + 幂等零新 item 钉测亲跑）+ bake LRU 16 / α 双路 `bakeCountForTesting` 钉测在位（§5） |
| .cube 派生资产审计 | **PASS**——位精确往返 + 篡改/缺失/结构损坏三路 degrade 值形态 + L009 原子晋升 + 同解前缀清理 + **paramsData <8KB 上界断言在位**（LUT 字节不进 sidecar 红线机检面）+ omit-nil serde 默认编码零漂移专测在位（§6） |
| 逐 commit 边界 | **PASS（3 处账面发现，§7）**——七功能提交对照 front-matter；EditorAdjustmentStackView 零改动撤销申报成立（provider 注册 + 路由表机制足达）；三处机制面新增申报亲证（路由行 41→42 / TAB-MATRIX / InspectorView case）；红线机检全绿（§7） |
| zh-audit | **PASS**（1637 source / 1875 catalog，与申报逐位一致；xcstrings 尾块纯插入 340 行 / 0 删改行亲证） |

**min_votes 语义**：单路验收（跨夜串行单 subagent slot）；error 零项无需裁决；
minor m-a 当场修复（`cbd1afa`，账面-only 无行为面，四 bundle 亲跑即回归证据）。

## 1. 亲跑数字（对表）

```
构建：build-for-testing 于 HEAD 9c61c48 重建（现成产物 07:33 早于补提交
      07:37:15——复用会漏测 ColormatchResolverBox/SharedForward；重建后亲跑）
验收轮（2026-10-11 07:4x-08:2x，串行单宿主直启；App 轮前预删孤儿 sidecar）
BUNDLE|Layers   |466/4/0|peakRSS=1156MB|162s   ← 申报 466/4/0（1154MB）命中
BUNDLE|IOPParity|444/3/0|peakRSS=5749MB|557s   ← 申报 444/3/0（7006MB）命中；RSS 轮间漂移带内
BUNDLE|App      |724/4/0|peakRSS=2832MB|359s   ← 申报 724/4/0 逐位命中（预删孤儿后一轮净绿）
BUNDLE|IOP      |563/1/0|peakRSS=7864MB|161s   ← 申报 563/1/0（7884MB）命中；< 8192 门
zh-audit --check：PASS（1637 source keys / 1875 catalog keys）
```

- 四 bundle 全绿零 MEMFAIL；IOPParity/IOP peakRSS 轮间漂移（5749↔7006 /
  7864↔7884MB）= AGENTS 在案的同 bundle 方差注记，均 < 8G 运行门。
- **对账算术闭合亲证**：Layers +28（CDFSolver 8 + Pooling 6 + BakeGolden 6
  + CubeAsset 8；其中 budget probe 1 法 env 门 skip——`Executed` 总计含
  skip 计数，438+28=466 与 skip 3+1=4 双向自洽）；IOPParity +6（Module +5
  + Identity +1）；App +13（Service 7 + Panel 6）。八文件 `grep -c "func
  test"` 亲数 = 47 法与申报一致。
- **G1 关键断言亲跑绿**（ bundle 轮内）：`testDoubleBakeIsBitIdentical`
  （bitPattern 逐体素）、`testSolveTwiceLandsByteIdenticalParams`（E5 平面
  解耦 + params 逐字节 + 幂等零新 history item + 持久资产 vs 内存 bake
  全表位型比对）、`testAnyPermutationGivesByteIdenticalPool`（3! 全排列
  基线+5 变体）、`testVoxelGateAgainstIdealModel`（LCG 4096 体素 ≤1e-5，
  实测 worst print 在日志）。
- 孤儿 `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra` 跑后再生 =
  **M4-1 挂账 #6 第四度发作**（本验收轮 App 轮前预删故一轮净绿；机制与前
  三度同款，非本批缺陷，催办维持）。

## 2. 逐 commit 边界（对照 front-matter + 申报）

| commit | 申报 | 亲核 |
|---|---|---|
| `14d032d` T1 | CDFSolver + 8 法 | ✅ 纯新建 + ColorMatchSolver additive `.cdf` case/cacheTag/solver 臂 + BUNDLE-MAP/Project.swift 编列 |
| `d04b0ab` T2 | Pooling + 6 法 | ✅ 文件面最小 |
| `69748bd` T3 | Bake + 6 法 | ✅ |
| `e73e188` T4 | CubeAsset + Params 载体 + 8 法 | ✅ ColormatchModule params additive 触碰在申报面内（reflog 有一次 amend `408b65f→e73e188`，amend 未申报但内容单提交自洽） |
| `b59623d` T5 | LUT 臂 + 6 法（Module+5/Identity+1） | ✅ Registry forward 接线 + prewarm 补 `colormatch_linear` |
| `6bdcd18` T6+T7 | 合并提交（申报 §6） | ✅ 合并合理性成立（共享文件面）；EditorAdjustmentStackView 零改动 = 撤销申报成立（机制面三处新增亲证：路由 `.lut` 页行 + EditorStackRoutingTests 41→42 + TAB-MATRIX 补行 + InspectorView zh case） |
| `4cc1c52` T8 | G1 全链 + G3 配方 | ✅ ServiceTests 全链断言；MANIFEST 落 `.work/gui-acceptance/m5-1/`（证据域不入 git = L073 体例，盘面亲证九行） |
| `abc46c0` T9 | 收口 docs | ⚠️ m-b：docs 提交夹带 1 行测试 `print`（BakeGolden voxel gate worst 观测行）——commit boundary 卫生瑕疵，内容良性 |
| `9c61c48` 补 | shared resolver forward 补提交 | ⚠️ m-c：orchestrator 派发申报 SHA `6ee8615` 不存在（reflog 全史无此 SHA——申报笔误/陈旧）；实际补提交 = `9c61c48`（主题/内容与申报一致亲证：ResolverBox + SharedForward + Registry 接线）；SUMMARY/GOAL-STATE/TODO 记「7 commits `14d032d..4cc1c52`」为 T9 前时点账，未含 T9 自身与补提交（时点性账面，非内容错误） |
| `cbd1afa` 验收批 | 本轮小修 | m-a（下） |

## 3. S2 数学审计（灵魂——独立路复算）

工具 = numpy Float32/Float64 + Python `Fraction` 精确有理数（与 Swift 实现
零共享代码路径；脚本 /tmp/m5-1-02-acceptance-audit.py + m5-1-02-recheck.py
即弃）。Oklab 常数取自 OklabMath.swift 印刷字面（P1 轮已独立推导锚定）。

### 3.1 整数交叉相乘分位对齐

- **等价性**：`cumRef[j]·totalSrc ≥ cumSrc[i]·totalRef` ⇔ 有理数比较
  `cumRef[j]/totalRef ≥ cumSrc[i]/totalSrc`——20 万组随机整数对（计数域
  ≤2^32）逐对精确等价 ✅（原始整数域，无 Fraction 约分失真）。乘积上界
  论证亲核：extract 桶钉 512²=262,144 样本、池化按权重求和——实际计数
  远低于 2^32，`(2^32−1)² < 2^64` 无溢出面。
- **独立实现复现**：本审计自己的 Fraction 梯实现跑 shifted-tent 对
  （peak 90→150）——曲线单调 ✅、源中位 bin 90 映射到参考中位 bin 150
  精确命中 ✅（Swift 测试的 ±4 容差带内取精确值）。
- **支撑 bin 重推导勘误（DECISIONS §1）机制亲证**：`binIndex(binValue(bin))`
  Float32 往返在 a/b 通道（域 [−0.5,0.5]）**63/256 bins 低一格**（截断
  `Int(scaled)` 机制，numpy float32 逐 bin 复现）——逆映射 Float32 脆弱性
  机制类成立、修复方向（改走与 extract 同一轮分位梯）正确。归因细节见
  obs o-1（L 通道具体案例未能独立复现）。
- **平台语义**：源支撑外 → 参考支撑端值（格点精确）、支撑内梯位 clamp 进
  参考支撑——读码 + 测试 `testOutOfSupportBinsPlateauAtReferenceSupportEnds`
  （含 fixture 非全域 sanity 断言）亲跑绿。

### 3.2 bake 体素门 / 恒等带独立复算（全 65³ 晶格，非抽样）

| 面 | 我方独立复算 | 申报/门 | 判定 |
|---|---|---|---|
| 体素门 vs 理想连续模型（shifted 90→150，α=0.7，**全 274,625 体素**） | **worst 5.96e-8** | 申报 7.6e-8（4096 抽样）/ 门 1e-5 | ✅ 同带（Float32 存储 epsilon 量级；我方全晶格略低于其抽样极值，一致） |
| 恒等 bake 带（identical tents@128，α=1，**全 269,927 支撑内体素**） | **worst 0.0259** | 申报 0.0233（by-8 抽样）/ 门 0.03 | ✅ 同带（一步低阶梯 ×3 通道经 Oklab⁻¹ 非线性放大的机制带；全晶格略高于抽样极值，同因） |
| α 折入精确性 | 复算 spine 与测试同一公式形（双写 `(1−α)lab + α·mapped`） | 测试 512 体素 ≤1e-6 亲跑绿 | ✅ |

- 双跑 BIT-IDENTICAL：`concurrentPerform` 逐 z 切片固定索引写、零归约——
  读码结构面 + `testDoubleBakeIsBitIdentical` 亲跑绿。
- bakeKey 折叠：`fnv(solutionHash LE ⊕ α bitPattern LE)` 读码与 P1
  solve-cache 折叠同体例；`.cdf` tag 字面 `colormatch.solve.cdf.v1` 在册。

### 3.3 缓存键字面复算（FNV-1a 64 独立实现）

```
gaussianOT(0,0) = 2495982924697081349   ← P1 钉死值逐位命中（转写正确性锚）✅
reinhard(0,0)   = 3458577883779271296   ← P1 钉死值逐位命中 ✅
cdf(0,0)        = 3429970360978670064   ← 本批 .cdf tag 字面的键值（存档）
```

### 3.4 池化公式锚（Fraction 精确）

- μ_pool = (1/4, 3/20, −3/40) 精确命中；Σ 六槽 = (11/80, 3/400, −3/800,
  31/400, −3/800, 31/1600) 精确命中测试钉值 (0.1375/0.0075/−0.00375/
  0.0775/−0.00375/0.019375)——混合二阶矩公式 `Σ w(Σ_i + (μ_i−μ_pool)(·)ᵀ)`
  与手算锚全等 ✅。sampleCount round(0.25·10+0.75·30)=25 ✅；支撑逐分量
  并集 ✅。
- **序规范化结构面**：sorted by statsHash 升序（tie 按 offset 稳定）→
  Float64 求和序固定 → 同集异序逐字节同；6 排列亲跑绿（Equatable 全字段
  + statsHash 双断言）。

## 4. 池化确定性审计（补充面）

- statsHash 升序规范化读码（`ColorMatchPooling.pool` :69-73）✅；
- 直方图取整 = sorted-order Float64 和 + `.rounded()`（schoolbook 半远离
  零）回 UInt32——2.5→3 / 22.5→23 专测钉死亲跑绿；**整数秩纪律无断裂**
  （S2 梯只吃整数计数，池化产物直喂 `ColorMatchCDFSolver.solve` 集成断言
  在位）✅；
- N=1 恒等退化（verbatim 直通 + 权重非零 typed 前置）✅；空输入 typed
  error ✅；权重比不变（×100 缩放同池化同哈希）亲跑绿 ✅。

## 5. LUT 臂三臂状态机 + E5/E6 审计

- **三臂分派**：`commitParams` strength==0 → identity；`.cdf` → LUT 臂；
  其余 → linear。identity 态 `piece.data = nil` + `makeRoutedCommandBuffer`
  blit（L031）——`testLutArmIdentityStatesBlitByteExact` 两恒等态
  （assetRef nil / 资产 degrade）逐字节直通 + 反空转（真表实动像素）亲跑绿。
- **恒等 uniform 盒**：`ColormatchLutUniforms` 与 MSL `Lut3dUniforms`
  （width/height/level + domain 6 + fwd[9] + inv[9]，96B 标量布局）逐字段
  镜像亲核；fwd/inv 恒等 + [0,1] 域 = bake 产物即工作空间映射（OQ-2）；
  kernel 文件零 diff（红线机检）下签名适配全在 colormatch 侧——KD-5 硬门
  兑现。
- **共享 tetrahedral 链路断言（G2 延伸）**：`testLutArmOutputMatchesThe
  SharedTetrahedralSampling`——colormatch 自有 PSO 引共享函数，GPU 输出 vs
  CPU 双写晶格映射 ≤1e-5，亲跑绿（IOPParity 轮）。
- **E5 armed tap**：`process()` 入点一次性捕获（armed 读清 + capture 先于
  本模块任何 dispatch = **旁路即构造**）；首解 = 合成恒等 box 注入 v50 槽
  位（排序对齐）、重解 = arm 真实 box 输入平面——两解同链位（solve-twice
  稳定性的结构面）；L014 fence + 全面 readback + ≤512² 固定序 stride 采样
  + Oklab + P1 extract 读码亲证。
- **E6 管线级提取**：`extractStats(document:bucket:)` = ColorMatchDocument
  值面 + materialize boxes + **throwaway PipeCache**（hermetic）+ armed tap
  消费——零 GUI 会话态；`testHeadlessExtractionNeedsNoGUISession`（无头
  双跑同哈希）+ `testLiveFaceMatchesTheHeadlessFace`（live==headless 同值）
  亲跑绿。源桶钉 512（solve-twice 分辨率半边）/ 参考 THUMBNAIL pristine
  （`instances: []` 同一 API；编辑链改变源面而参考腿 pristine 的负测
  `testReferenceExtractionIsPristineAndCached` 亲跑绿）。
- **attach = store 级投影缝**：`projectColormatch`（(opName, multiPriority 0)
  upsert，identity/iopOrder 保持）= apply_params `projectInstances` 同缝；
  live 腿 recordChange / addModuleToBaseChain 恰一 commit（钉测）+ 幂等投影
  零新 history item（solve-twice 钉测）——MCP match_color（M5-1-03）复用
  同缝的结构面在位。
- **bake LRU 16 + α 双路**：会话曲路（resolver.cdfSolution → bakeKey LRU，
  `bakeCountForTesting` 钉 bake-once/rebake-on-tick/LRU-hit 三态）与恢复路
  （资产 verbatim 零 bake）亲跑绿。
- **shared resolver forward**：`ColormatchResolverBox` + `ColormatchShared
  ResolverForward`（registry 工厂捕获 forward、调用时读盒）——9c61c48 补
  提交内容亲证与测试消费面一致（`testInvalidateAllDropsSessionFaces` 经
  forward 断言）。

## 6. .cube 派生资产审计

- 位精确往返：`String(Float)` 最短往返 + 自有 parser；nasty 值集
  （±0/指数/denormal 邻域）+ locale 不变（无逗号形态专测）亲跑绿；
  `CubeLutParser` 零触碰（Lut3d/ 密封面 0 行 diff 主证）。
- 全验证 degrade 值形态：缺失/不可读/哈希失配（FNV decimal String 对
  params.assetHash，L013）/结构损坏四路各自 typed reason，无静默默认——
  四专测亲跑绿；模块 degrade → blit（§5 恒等态）。
- L009 原子晋升：同目录 `.tmp-` 前缀 + rename，无半文件（专测）✅；
  同解前缀清理 keep-file 语义专测 ✅（孤儿 = 观察项政策一致）。
- **paramsData <8KB 上界断言**（`testParamsBlobStaysUnderBoundWithAsset
  Attached`）在位亲跑绿——65³ LUT 字节不进 sidecar 红线机检面兑现。
- omit-nil additive serde：默认 Params() 编码零 asset 键（P1 档字节零漂移
  契约）+ 附载编码 round-trip（decimal String）专测亲跑绿。

## 7. 红线机检（`git diff e4acb70..HEAD` 亲跑）与验收批小修

红线全绿：`Lut3d/` 密封面（Lut3dModule/CubeLutParser/LutLibraryStore/
Lut3dKernels.metal）**0 行**；Film 域/LutEncodingCatalog/Sidecar/History/
PipeCacheKey/PipelineDocument/Graph **0 行**；`.metal` 本批 0 行 diff +
0 新文件；零新 SPM（Project.swift diff = 测试编列）；`runModal` App/Sources
0 命中；`String.LocalizationValue("prefix_\(x)")` 禁形 0 命中（唯一 grep 命中
= LightamerApp.swift 注释里的禁形示范，非使用）；xcstrings 尾块纯插入
（340 增 / 0 删改）。

**验收批小修一枚（`cbd1afa`，账面-only）**：

- **m-a** BUNDLE-MAP 既有行计数漏更新：`ColormatchModuleTests` 7→12、
  `ColormatchIdentityGoldenTests` 2→3（本批 +5/+1 扩展未同步，DECISIONS
  「BUNDLE-MAP 增行 8」实为新增 6 行 + 既有 2 行应改——m-a 修后总触点 8
  与申报数自洽）。P1 验收 m-a 同款账实差；无代码面（四 bundle 亲跑即回归
  证据）。

**账面注记（不修）**：m-b = T9 docs 提交夹带 1 行测试 print（§2）；
m-c = 申报 SHA `6ee8615` 不存在 + SUMMARY「7 commits」时点账（§2）。

**观察项（obs，不计数）**：

- **o-1** DECISIONS §1「L 通道 1% 分位实测差一 bin」的 **L 通道归因未能
  独立复现**：格点往返复现中 L 通道（域 [0,1]）0/256 bins drop，a/b 通道
  （域 [±0.5]）63/256 drop——机制类（Float32 截断脆弱）确证、修复方向正确
  且 shipped 代码已完全不依赖该逆映射，无行为影响；归因差异可能来自首轮
  实测的非格点值路径（如 fixture 手工 support 值）。留档不改。
- **o-2** `ColormatchResolverBox.shared` = `nonisolated(unsafe)` 裸静态
  （写 = MainActor configure/solveAndAttach 安全网 + 测试注入；读 = 任意
  线程 commit 路径）——理论数据竞争面；声明体例 `LutLibraryStore.shared`
  为 NSLock holder。实际写入一次性/低频，风险低；V2 若有多会话热切换再
  收紧为锁内 holder。
- **o-3** M4-1 挂账 #6 第四度发作（§1）——修复批催办维持。

## 8. min_votes / 纪律声明

- 单路验收（config `[matrix.review.slot]` 跨夜 = 串行单 subagent）；error
  零项，三 minor 中 m-a 已修、m-b/m-c 为账面注记级（不触产物正确性）。
- 审计全程只读产物 + 独立路复算；未读他路报告（omp 路未到货）。

## 9. omp 二次验收（串行）——待 orchestrator 派遣后回填

- 结论：（待 omp 路）
- 配方注记：①App bundle 跑前删 `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`
  （M4-1 #6 孤儿，跑后再生属预期）；②**现成 DerivedData 产物早于 `9c61c48`
  ——若复用产物需先 `build-for-testing` 重建**（本 zcode 轮已重建，07:43
  后的容器可直接用）；③GUI 走查九行配方 = `.work/gui-acceptance/m5-1/
  MANIFEST.md`（G3 自然样张 = Manual-Only，omp computer-use 可执行）。

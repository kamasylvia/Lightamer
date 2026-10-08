# M3-3-02-ACCEPTANCE — FSIM 管线批（wave 2）独立验收

> **结论头：PASS / 0 error + 1 minor（已修）**
> 验收：2026-10-09 夜间独立验收 subagent（零共享上下文，实测核验不轻信；夜间
> 全自动授权在案）。验收对象 = `d68ebf8..d3e3262` 六提交（T1+T3 `b458273` →
> T4 `6eba352` → T2 `6b2ed00` → T5 `a6fab6a` → T6 `14a7893` → T7 `d3e3262`）。
> 验收方式：**全套七 bundle 独立复跑**（`caffeinate -dis Scripts/test-direct.sh
> --all` 亲跑）+ 全部关键源/测试文件读码 + `git diff` 密封面机检亲跑（真路径
> 重跑制——首轮路径笔误的假 CLEAN 已自纠，见 §六.2）。未 push。

## 一、全套独立复跑（对账）

| bundle | 亲跑 | 申报 | 判定 |
|---|---|---|---|
| Layers | **366/3/0**，peakRSS 1148MB | 366/3/0 | ✅ 逐位一致 |
| IOP | **483/1/0**，peakRSS 7675MB | 483/1/0 | ✅ 逐位一致 |
| IOPParity | **392/3/0**，peakRSS 5986MB | 392/3/0 | ✅ 逐位一致 |
| App | **665/0/0**，peakRSS 2831MB | 665/0/0 | ✅ 逐位一致 |
| Export | **342/1/0**，peakRSS 6115MB | 342/1/0 | ✅ 逐位一致 |
| Library | **598/4/0**，peakRSS 613MB | 598/4/0 | ✅ 逐位一致 |
| Sessions | **279/4/0**，peakRSS 1623MB | 279/4/0 | ✅ 逐位一致 |
| **TOTAL** | **3125/16/0**（1275s，exit 0） | 3125/16/0 | ✅ |

- 全程零 MEMFAIL（峰值 IOP 7675MB < 8192 运行门；与 AGENTS 贴线记载 IOP
  7654 同量级）、零 crash、零 no-total-line。运行中进程监视在案。
- 构建独立先行（`xcodebuild build-for-testing` RC=0，caffeinate 包裹）。

## 二、基线分解裁决（minor 正本，已修）

TOTAL 3125 对，但**分解账勘误**：

- **文件实数亲数**（`grep -c "func test"`）：FilmLeg 9 + FilmPrintBake **8** +
  FilmPlacementDriver **3** + FilmPlacementTests **11** + FilmPlacementKernel 3
  + FilmCoordinator 5 + ExportFilmChain 4 = 43 新方法 + V50OrderTests +1
  （归 IOP，BUNDLE-MAP :185 亲核）= **+44**。
- **BUNDLE-MAP 执行期增行初记** 9/7/4/7/3/5/4（=39）+1 = +40——三处与文件
  实数不符（FilmPrintBake 7↔8、Driver 4↔3、FilmPlacementTests 7↔11）。
- **账面基线** = 3125 − 44 = **3081**，与 M3-3-01 波推算值（3029+52）两条
  独立路径精确吻合；分 bundle 倒推（Layers 346 亲测 + IOP 471 + IOPParity
  389 + App 660 + Export 338 + Library 598 + Sessions 279 = 3081）第三条
  独立路径亦吻合。**SUMMARY/DECISIONS 的「实际基线 3085 / +40」系按初记值
  倒推的错账**（3085+40 与 3081+44 巧合同得 3125，故 TOTAL 申报仍对；03 波
  续算以 TOTAL 3125 为基线不受影响）。
- **处置**：BUNDLE-MAP 四处行内数已按终态实数修正 + 勘误注记（本验收批
  commit）；SUMMARY/DECISIONS 正文档不动（申报 TOTAL 正确，分解裁决以本节
  与 GOAL-STATE 增量承载）。记 **minor（已修）**——AC#7「三方对表」的行内
  method 数维一度要求。

## 三、3×2 交互矩阵审计（本波灵魂，逐格亲核）

实现面（`PixelPipe.isTerminalTailSkipped` :271-315 + `FilmTailAssembly.
displayReplayResidents` 读码）与测试面（FilmLegTests 9 法）逐格对表：

| 格 | 降出集 | 重放链 | 终平面 | 断言落点 | 判定 |
|---|---|---|---|---|---|
| `.sdrGamma` × off | ∅（现状） | — | bgra8 | test 2 byte 门 + planesRendered=3 | ✅ |
| `.sdrGamma` × on | 终端驻留集四件（colorout/borders/watermark/gamma） | v50 序 colorout→borders→watermark→gamma | bgra8 | test 4（byte 恒等 + canvas 恰一次长 + misses=6/5/0/5 局部性链）+ test 3 序断言 | ✅ |
| `.edrLinear` × off | 仅 gamma（现状） | — | float32 linear | test 5 off face | ✅ |
| `.edrLinear` × on | colorout+gamma | 仅 colorout（**gamma 恒不重放**） | float32 linear | test 5（byte 门 + misses=3） | ✅ |
| `.drt` × off | DrtTailAssembly 既有降出（M2-6 面） | 尾链 | bgra8 | test 6 off face | ✅ |
| `.drt` × on | **零改** | DRT 尾链照旧 | bgra8 | test 6（byte 门 + **seed 交接证明**：record 变更 → 尾三平面 re-render/misses=3 + input hit，film-off 同 record 对照全 hit） | ✅ |

- **byte 门真实性**：on 三格均 `readAllBytes(on) == readAllBytes(off)` 亲读
  断言（T1 routed-blit 恒等载体，FilmMethodBox.process 无 payload 臂）；
  test 8（resolved materials）反向断言 bytes MOVE（fused kernel 真分派）+
  float32 平面 + strength 变更移像素。
- **重放序**：`displayReplayResidents` filter 后 `(iopOrder, multiPriority)`
  排序亲读（DECISIONS §7.1 v50 序修正的兑现位）；test 3 逐 op 序断言。
- **misses 计数**：test 4 = 6（cold）/5（record 变更）/0（warm）/input-hit，
  test 5 = 3，test 6 = 3/3/0——「planesRendered 只计主管线」既有口径的
  misses 断言形态与 DECISIONS §7.2 备案一致。
- **seed 折叠**（test 1）：恒稳 + 三分量（upstream/recordHash/solvedPackHash）
  逐项判别 + replay 命名空间与 film seed 分离。`FilmTailAssembly.seed` 折叠
  序 = fnv(recordHash ⊕ policyTag ⊕ solvedPackHash ⊕ upstream) 与 KD-1 逐字
  吻合；`DrtTailAssembly.seed(upstream:)`（PixelPipe.swift:1535）**签名零改
  亲证**（diff 中函数定义零命中；数源替换在 runTerminalTails :985-993 亲读）。
- **防重入**：`isFilmTailLeg` 腿内短路降出（:275）+ test 7 exact accounting。

## 四、filmPlacement 审计（T4）

- **三断言成立**：①恒等核 byte==input（FilmPlacementKernelTests test 1，
  tolerance 0，identity commit 无 uniforms 亲断言）；②delta 形（CPU
  `placementGain` δ=±(Δ−g_m(Δ)) + kernel δ 形无取消式展开读码亲证）；③
  catalog identityJSON（`Params()` 全零点）≡ kernel no-op 点（commitParams
  armed=false→data=nil→blit；kernel flag<0.5 早退 verbatim copy）。
- **膝点简化臂**：m=1 闭式 K=t−√((a−t)(C−t)) + m≥2 有界二分 40 + 括号守护
  牛顿 4 步（步出括号/|F| 不降回落二分）读码亲证；锚点 +7/+4/−7.5/−4.5 与
  DECISIONS §4 一致；testM1ClosedFormLandsExactly/testM2BisectionNewton...
  /testHigherOrderKneeHasSmallerNearKneeDelta（m 阶接触 smoke，d2<1e-9）。
- **V50Order 20.8**：add-only 亲证（entry 数组 diff 零删除行；头注释计数
  94→106 修订非行为面）+ testFilmPlacementSlotOrderConstraint（20.8 pin +
  acesccIn<filmPlacement<exposure + 位置唯一）+ 模块 statics/表双写一致。
- **GradeCatalog 18→19 多点修订 ≥5 处亲核**（m8 清单全兑现）：count :37、
  unique ids、grade-owner 14→15、catalogOps 17→18、resolved 17→18、owner
  matrix +filmPlacement .grade、lightamerGradeRows +20.8、文件头注释、
  seed-deferred 集合扩员、CatalogAddFaceTests 12→13（可加不可编占位，m4）。
- **Registry**：默认面注册（恒等 = pixel-safe）+ seed 缺席 + prewarm；
  `defaultFaceDisabledOpNames` diff 零命中亲跑。
- GPU-vs-Float64 encoded smoke 门 = 2e-3（实测 maxDiff 申报 1.4e-3 量级，
  golden 体 M3-3-03——门结构与 E5 处方的分级预告一致）。

## 五、E1 导出递缝审计（T6）

- **ExportQueue 三编辑点亲读**：①`ExportJob.filmTail`（:64，drtTail :60 旁
  additive）；②`enqueue(filmTails:)` per-image 索引参数（:202）+ precondition
  count==images（:215-218）+ `filmTails?[imageIndex]`（:254）；③腿内
  `$jobFilmTail.withValue(queued.filmTail)`（:431）**嵌套于** `$jobDrtTail`
  （:430）内层——drt 外 film 内，值域互不干扰，detached 腿注释锚 :420-424
  在案。
- **ExportRenderer**：`$jobFilmTail` TaskLocal（:125）+ `Request.filmTail`
  （:183）+ consult = `request.filmTail ?? jobFilmTail`（:433）+ 两 pipe 调
  用点传参（:509/:519）。
- **enqueueExportM2 恒装配**：ExportState :474-512（per-image filmTails +
  typed 计数门 :476-478 先行拒绝）；RunAssembly per-image fan-out
  （ExportInspectorView :866-867 loaded 图 carrier / 其余 nil → :878）。
- **ExportFilmChainTests 4 法**：detached 腿交付证明（injected renderLeg 捕
  获 TaskLocal）、per-image fan-out（两图 0.4/0.9 carrier 各达腿）、无 film
  零漂移（[nil]）、Request wins、typed 计数门。
- **`ExportQueueContract.swift` 零 diff**（真路径机检 0 行）。

## 六、红线机检与边界

1. **密封面零 diff（真路径重跑制）**：首轮机检路径笔误（HistoryStack 等记
   为 `Sources/Layers/`，实际 `Sources/Pipe/History/`；DrtEotf 实际
   `Sources/Pipe/Drt/`；Lut3dKernels 实际 `LightamerIOP/Sources/Lut3d/`）
   ——git diff 对不存在路径静默返空 = 假 CLEAN，**已自纠重跑**：七文件
   （Contract/DrtEotf/Lut3dKernels/LightamerSidecar/HistoryStack/HistoryHash/
   ModuleInstance）+ 六格式导出矩阵全部 **0 行 diff**；全批 name-only 兜底
   扫描零命中。
2. **签名零改**：`TerminalTailPolicy` 枚举与 `DrtTailParams`/`DrtTailAssembly`
   在 PixelPipe diff 内仅注释提及（+行），`policyTag "lightamer.drt"` 零命中；
   `seed(upstream:params:)` :1535 定义不在 diff。
3. **V50Order add-only**：entry 数组零删除行（头注释 94→106 为注释修订）。
4. **sidecar v9 / history 族**：HistoryStack/HistoryHash/Sidecar 三文件
   0 行 diff（01 波已落，本批零触）；xcstrings 纯插入（toast 键 append 式）。
5. **提交边界**：六提交 stat 抽验（T4 = Module+Kernels+catalog+Registry+三
   新测试+三修订测试+Project.swift；T1+T3 合并 commit body 明示「T1 tests
   consume the T3 default parameters」——全局 §2.1 相关变更合并纪律符合，
   偏差申报在案）；全英文 Conventional Commits；未 push。

## 七、T2/T5 抽审（配套面）

- **fused kernel**（FilmSubRunKernels.metal）：单 pass 查表→base→滤色密度
  减（G−kM/B−kY = E3 修正向量的代数等价形式，solver x=−d+k 印相曝光形）→
  65³ 四面体（lut3d 形 + rint 细节）→ log 域 strength 混（out=in^(1−k)·
  film^k）；逐像素纯函数无 barrier。
- **FilmPrintBake**：K 标定两连修读码亲证（:133-135 session 操作点 = pack 后
  密度；systemDensity :240-244 反演带 pack = session 系统反演）；LRU 16 锁外
  bake + 确定性双 bake bit-identical（test 1/4）；域界 = 密度域+base−头量
  （R 无/G s_m/B s_y）；中灰回环 0.184（1/4 stop 晶格容差）；串扰恒等矩阵
  （D-5d 回填挂 03）。
- **solve cache 分半**：`FilmRuntimeSolve.solve` 读码——缓存键只含
  pair⊕stats⊕modeTag（无 ROI 项 = per-ROI 红线结构性兑现 + testPerROIRedLine
  钉死），手动 Y/M shift + exposureEv 在缓存外消费层叠加（:618-621）+ 测试
  钉死；整数秩 percentileBin 累积计数 + ramp 钉死。
- **coordinator 四件**：carrier（WorkspaceModel per-url :281-311）/写腿
  （updateFilmRecord 只 schedule）/恢复腿（nil 零动作/switch-back skip/异值
  回注 + field wins 日志，挂 load 链 DRT 腿后 :1103）/`filmTailPolicy(for:)`
  （thumbnail 恒 nil + unknown stock typed 降级）；undo/redo/jumpToHistory
  三处 `syncFilmCarrierWithHistory`（:1744/:1753/:1773）亲证（§7.6）；成对
  写入（makeSidecarDocument :1425/:1432 historyHash 尾位 + filmRecord 字段）；
  store 装配坏目录 typed throw + toast（FilmCoordinatorTests 5 法 + xcstrings
  键在案）。

## 八、偏差七条处置核验（DECISIONS §7 逐条）

| # | 偏差 | 处置证据 | 判定 |
|---|---|---|---|
| 1 | replay filter v50 序修正 | displayReplayResidents sorted 读码 + test 3 | ✅ |
| 2 | planesRendered 口径备案 | FilmLegTests misses 断言形态 + 既有 DRT-tail 口径 | ✅ |
| 3 | 膝点括号守护 | solveKnee 守护牛顿读码 + m 阶接触测试 | ✅ |
| 4 | K 标定两连修 | §七读码两处 + 中灰回环测试 | ✅ |
| 5 | solve cache 分半 | solve() 消费层叠加读码 + 键判别/手动叠加测试 | ✅ |
| 6 | undo/redo/jump 同步补线 | 三调用点亲证 + testRecordFilmChange...UndoSyncsCarrier | ✅ |
| 7 | T1+T3 合并 commit | b458273 body 明示理由，纪律符合 | ✅ |

## 九、观察项（非阻塞）

1. **基线分解错账**（已修，见 §二）：SUMMARY §三「基线 346 + 23」括号自相
   矛盾（366−346=20）；「实际基线 3085」应为 3081。TOTAL 与分 bundle 申报
   全对，03 波续算不受扰。
2. FilmPlacementKernelTests 的 GPU 测试带 `XCTSkipIf(no GPU)`——本机有 GPU
   零 skip（全套 skip 16 = 基线 16，零新增）；无 GPU 环境该三法静默 skip，
   golden 批（03）落地时注意 CI 形态。

## 十、验收批变更（本 commit）

- `M2-4-0-BUNDLE-MAP.txt`：四处行内 method 数按文件终态实数修正 + 勘误注记。
- 本 ACCEPTANCE 落盘 + GOAL-STATE 续接点增量（基线裁决承载）。

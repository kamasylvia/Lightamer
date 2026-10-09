# M3-3-ACCEPTANCE-OMP — FSIM-01 三波回溯二次验收（omp 独立）

> 验收：2026-10-09 omp 回溯二次验收（零共享上下文，不轻信首验，一切亲测）。
> 对象 = M3-3-01（`c8ddc57..301f933` 七提交）/ M3-3-02（`d68ebf8..d3e3262` 六提交）/
> M3-3-03（`2fee806..c5f5dce` 六提交）。只读验收，未修改源码/既有文档，未 push。
> 注：HEAD 已含 M3-4-01（FilmGoldenTests 12→16 法等），回溯数据以各批基线/commit 树为准，
> 定向测试亲跑值为 HEAD 现态。

## 结论头

**PASS / 0 error + 1 minor**

- minor：M3-3-02 首验 minor（BUNDLE-MAP 行内数初记错、分解账勘误）已修闭环，
  回溯确认修正终态正确；M3-3-03 首验 2 minor + 6 obs 均已现场处置/登记，
  回溯抽核无新增。minor 记账 = 本报告唯一 minor（承首验 02 项，无新增 error）。
- 与首验实质分歧：无（测试红/数学超容差/上游漂移三类实质项全部零命中）。

## 一、M3-3-01 判定：PASS

- 首验结论 PASS / 0e+0m，回溯确认。三 commit 范围机检在案：
  `22e14c8`/`04b2909`（36 文件，资产 29 + 文书 4 + MANIFEST + 测试 229 行）/
  `1ea9264`/`72b7222`/`0a48b55`/`dc82dc0`（6 文件，HistoryStack +101/−18 等）/
  `301f933`，与 SUMMARY 申报一致。
- AC 抽查（2 条）：
  - AC#2 资产五件套：`shasum -a 256 -c MANIFEST.sha256` 亲跑 **30/30 OK**；
    `git log --oneline -- Resources/FilmProfiles` 仅 `04b2909` 单提交，其后零改动；
    `Resources/LUTs` 本批 diff 零命中（01 范围密封机检，全空）。
  - AC#4 求解器：数学面见 §四独立复算，四值逐位吻合 + 错误向量判别成立。
- func test 实数：FilmRecord 9 / FilmProfile 21 / Solver 8 / FilmHistory 8 /
  FilmSidecar 6 = 52，与 BUNDLE-MAP（`:506-513`）逐行一致，01 波计数零错账。

## 二、M3-3-02 判定：PASS

- 首验结论 PASS / 0e+1m（已修），回溯确认。commit 范围 `b458273`→`6eba352`→
  `6b2ed00`→`a6fab6a`→`14a7893`→`d3e3262` 六提交亲列，与首验一致。
- AC 抽查（2 条）：
  - AC#1 sub-run 缝：`PixelPipe.isTerminalTailSkipped`（`PixelPipe.swift:271-315`）+
    `runTerminalTails`（`:976-1025`，film → DRT tail → display replay 共享序）+
    `isFilmTailLeg` 防重入（`:170`，腿内短路 `:275`）读码在案；
    `DrtTailAssembly.seed(upstream:params:)`（`:1553`）签名亲核，数源替换在
    `:986-993`，02 范围内该符号 diff 零命中（ sealing 机检全空）。
  - AC#4 filmPlacement：V50 20.8 add-only（`V50Order.swift:62-69`，filmPlacement 行
    介于 acesccIn 20.5 / exposure 21.0 之间，头注释 106 条）亲核；
    `6eba352` stat = 14 文件（Module + Kernels + catalog + Registry + 三新测试 +
    三修订测试 + Project.swift + BUNDLE-MAP），与首验 §六.5 一致。
- 基线分解勘误复核：文件实数 9/8/3/11/3/5/4 + V50OrderTests +1 = **+44**，
  账面基线 3125−44 = **3081**，与 01 波推算值两条独立路径吻合；
  BUNDLE-MAP 勘误注记（`:529-533`）亲读在案，SUMMARY「3085/+40」错账裁定成立。
- E1 三编辑点抽核：`ExportJob.filmTail` / `enqueue(filmTails:)` + precondition /
  腿内 `$jobFilmTail.withValue` 嵌套于 `$jobDrtTail` 内层——首验 §五亲读结论
  与现源码一致（Contract 零 diff，02 范围机检全空）。

## 三、M3-3-03 判定：PASS

- 首验结论 PASS / 0e+2m（已修）+ 6 obs，回溯确认。commit 范围
  `9f4a649`→`6c83505`→`b10df2c`→`94168f8`→`5a8a2f8`→`c5f5dce` 六提交亲列。
- AC 抽查（2 条）：
  - AC#1 golden 主门：门结构钉值读码亲证——1a 1e-4（`FilmGoldenTests.swift:779,820`，
    `measuredMax > 0` 活性在 `:758-759` 收集）/ 1b 凸性 1.5×（`:1002-1011`）+
    flat-cell 实测口径 / 门 2 体素 1e-5（`:1086`）/ 门 4 中性闭合 2e-3（`:1732`）；
    `6c83505` stat = 2 文件（Project.swift +1 / golden 1460 行）与申报一致。
  - AC#3/AC#4 面板+只读卡：FilmPanelTests 6 / FilmCardTests 4 func test 实数亲数；
    `filmCardID` 编译期常量 + `layout(includesFilmCard:)` additive 默认参面
    首验 §五结论与源码一致；NodeKind 零新增（03 范围 PipelineDocument 零 diff，
    见 §六）。
- m=1 符号修复 `9f4a649`：单文件 12+/6−，commit body 代数（K²−2tK+t(a+c)−ac=0 →
  K=t±√）与 §四独立推导逐字一致；旧符号探针 f(a)=−5.92 vs t=−4.0（1.92 stop）
  独立复算逐位复现；回归钉 `testPlacementM1ShadowClosedFormLandsExactly`
  （`:1458`）在案。
- 03 范围 25 文件清单亲列（产线 = FilmPlacementModule 符号修正 + App 面板/卡五文件 +
  PipeCoordinator/InspectorState/InspectorView + xcstrings + FilmTailPolicy 一法，
  其余测试/docs），与 SUMMARY §一申报一致。

## 四、数学独立复算（第三实现，uv/Python，非产线路径）

处方来源 = 01 DECISIONS D-5a/b + 03 DECISIONS §5（读资产 JSON + 独立二分/闭式，
Float32 存储拓宽 Float64 同口径），结果：

| 断言面 | 独立复算值 | 申报值（测试钉死） | 判定 |
|---|---|---|---|
| baseDensityProjection（portra_400 三点） | 0.1945546/0.6023984/0.8150475 | 同（`FilmProfileTests`） | ✅ 逐位 |
| midGrayDensities（portra_400） | 0.489136888/0.947016837/1.272824936 | 同 | ✅ 逐位 |
| portra×endura (M0,Y0) | 57.9322/49.2372 | 同（`FilmFilterPackSolverTests:63-64`） | ✅ 逐位 |
| 表值 TH-KG3 | [0.0, 51.56801468, 52.53400422]，偏差 +6.36/−3.30 | 51.568/52.534，±10 带 | ✅ 带内 |
| ektar×ultra (M0,Y0) | 63.1549/59.1051 | 同（`:74-75`） | ✅ 逐位 |
| 表值 | [0.0, 71.21744660, 55.58437667]，偏差 −8.06/+3.52 | 71.217/55.584，±10 带 | ✅ 带内 |
| 错误向量 Y | 20.2711/27.5277（出带 −29.0/−31.6 CC），M 不变 | 20.27/27.53 | ✅ 判别成立 |
| m=1 阴影闭式 | 独立展开 K²−2tK+t(a+c)−ac=0 → K=t+√；t=−4.0 时 K=−2.677（旧符号 −5.323） | `9f4a649` body | ✅ 代数一致 |
| 旧符号探针 | f(a)=K−g=−5.92 vs t=−4.0 = 1.92 stop 偏离 | 同 body | ✅ 逐位 |

注：首轮复算误用高光分支式得 dev 3.5，改用阴影分支正确式（f=K−g，delta=K−e）
后与申报 1.92 逐位一致——中间偏差系复算侧分支误用，非产线/首验问题。

## 五、上游一致（M3-2 七项生效值，3 处 file:line 亲核）

| 生效值 | 亲核落点 | 判定 |
|---|---|---|
| ①document 级 FilmRecord（OQ-1 ③） | `FilmRecord.swift:47` struct + `film_stock` snake_case（`:94`）+ pristine 单源 `isFilmRecordDefault`（`:141`）；sidecar v9 additive + HistoryItem 镜像（`dc82dc0`） | ✅ |
| ①film sub-run 固定点 + seed 签名零改 | `PixelPipe.runTerminalTails`（`:976`，film→DRT→replay）+ `seed(upstream:params:)`（`:1553`）02/03 范围零 diff | ✅ |
| ⑦独立 filmPlacement op（OQ-7 ①） | `V50Order.swift:69`（20.8 add-only）+ `FilmPlacementModule.solveKnee`（`:183`）+ GradeCatalog 19 行（02 波 `6eba352`） | ✅ |
| ⑤golden 数学复算主门（OQ-5 ①） | `FilmGoldenTests.swift` 四门（1a `:712`/1b `:836`/门2 `:1055`/门4 `:1694`），零图像资产（受控输入程序化生成） | ✅（加测第4处） |

其余：②两段式求解（bake 求解器 + solve cache 分半 + 手动恒叠加）/ ③资产 c 混合五件套 /
④宽容度面板让出 M3-4 / ⑥spike 同批（M3-2 基线批结案，01 首验 §七亲证）——与三波
SUMMARY/DECISIONS 一致，无漂移。

## 六、定向测试（2 类亲跑，禁全套遵守）

| 类 | bundle（BUNDLE-MAP 登记） | 亲跑 | 判定 |
|---|---|---|---|
| FilmDeterminismTests（03 T2，5 法） | LAYERS 5（`:544`） | **5/0/0**，21s，peakRSS 244MB，`OK (direct launch, no testmanagerd)` | ✅ 0 fail |
| FilmGoldenTests（03 T1，16 法 = 12 + M3-4-01 重钉 4） | IOPP 16（`:540`，M3-4-01 修订注记 `:541-543`） | **16/0/0**，163s，peakRSS 237MB，`OK (direct launch, no testmanagerd)` | ✅ 0 fail |

说明：FilmGoldenTests 现 16 法含 M3-4-01 T1 精确锚重钉 4 法（RFC-023 §6.4 向量门等），
M3-3 基线时为 12 法——回溯验收跑 HEAD 现态 16 法全绿，覆盖 M3-3 四门原面。

## 七、git 机检（commit stat + 密封面）

- 抽查 commit：`04b2909`（36 文件 = BUNDLE-MAP +1/Project.swift +9/资产 29/
  文书 4/MANIFEST/测试 +229 行）与 01 SUMMARY 一致；`6eba352`（14 文件）/
  `6c83505`（2 文件 +1461）/ `dc82dc0`（6 文件 +674/−18）/ `9f4a649`（单文件
  12+/6−）/ `b458273`（6 文件 +870/−23）与各 SUMMARY/首验申报一致。
- 密封面三范围机检（亲跑，全部零命中）：
  - 01（`c8ddc57..301f933`）：PixelPipe / DrtEotf / Lut3dKernels / V50Order /
    Registry / NodeOwnershipCatalog / `Resources/LUTs` / HistoryHash.swift —
    全空；`HistoryHash.swift` 零 diff 亲证（折叠实体在 HistoryStack 尾部，前
    matter 勘误成立）。
  - 02（`d68ebf8..d3e3262`）：ExportQueueContract / LightamerSidecar /
    HistoryStack / HistoryHash / 六格式导出矩阵 — 全空。
  - 03（`2fee806..c5f5dce`）：DrtRecord/DrtPanel/Lut3dKernels/ExportQueueContract/
    Sidecar/HistoryStack/HistoryHash/PixelPipe/PipelineDocument/V50Order/
    NodeOwnershipCatalog/Registry/ModuleInstance/导出矩阵 — 全空（grep 21 实体
    零命中）。
- CHECKER 一致性：E1–E5 处方落点（E1 ExportQueue 三编辑点 / E2 三点投影 /
  E3 [0,1,0] 修正向量（`FilmFilterPackSolver.swift:21` 亲核）/ E4 3×2 矩阵 /
  E5 两级门分解）全部在三波交付中兑现；m1/m2/m4/m8 文本修订批与执行面一致；
  m6（M3-2 spike/台账）已由基线批 `c8ddc57` 处置（01 首验 §七亲证）。

## 八、与首验分歧点

无实质分歧。三点注记（均非分歧）：

1. 01 首验 obs-1（BUNDLE-MAP 预存计数漂移三处）为既有登记陈旧，01 波新行计数
   全对——回溯复核 16 个 film 测试文件实数与 BUNDLE-MAP 终态逐行一致
   （FilmGoldenTests 16 含 M3-4-01 增量，账面注记齐备）。
2. 03 首验 obs-4（门 1a 预声明 ~1e-6 vs 实测 8.7e-5）机理（rtne 外推放大 f32
   坐标噪声）读码成立——门分辨力保留（真实缺陷 ≥1e-2 = 钉值 100×），接受。
3. 03 首验 §六走查受阻（click-dead）挂 M3-4 处置——M3-4-01 已交付 Film 页实机
   走查补课（`2d580d8`），挂账关闭不在本回溯半径内，状态如实收录。

## 九、会话卫生

- 只读验收：除本报告文件外零写入；定向测试 2 类（Layers/IOPParity 各一），
  未跑 `--all`；未 push；工作区新增未跟踪项（`dt-clone-archive/`、两张 gui 走查
  jpg）为他批产物，本验收未触碰。
- 报告落盘：`.work/gsd/phases/m3-3-fsim/M3-3-ACCEPTANCE-OMP.md`。

OMP-VERDICT: PASS

# M8-2-SUMMARY — FSIM 管线集成执行摘要（2026-10-25）

> 执行正本 = `M8-2-PLAN.md`（checker `40bccfd3` + fixer `dd9490fe` + R1
> `bc2baf39` 后 HEAD）；偏差与裁定的正本 = `M8-2-DECISIONS.md`（本文只
> 记账 + 验收判定，不重复裁定正文）。C 档停位：本 plan 执行+验收闭环后停
> 汇报，M8-3 待用户确认后起跑。

## 逐任务记账

| 任务 | commit | 产物 | 测试增量 |
|---|---|---|---|
| T1 换臂分叉 | `ba568763` | assembleFilmLeg exhaustive switch（骨架）+ FilmLegAssembly 载体 + 光谱 dispatch 编排（A→blur→B→mix + 调制 uniform 34/35）+ strength mix kernel 一枚 + seed process 感知折叠（3-arg 形态零改） | +6 |
| T2 solve 光谱域 | `568f1376` | solveSpectral（build 中性对 + 直方图 gain + record 消费层）+ spectralModeTag 键空间隔离 + cacheKey(modeTag:) 加法重载（键形契约行零 diff） | +5 |
| T3 bake 家族 | `9ebb43fe` | SpectralPrintBake 三槽（tc 整 bundle / print / scan PCHIP 切片，各自 LRU + bakeCount）+ 单次 build 扇出 facade | +5 |
| T4 process v2 | `bae428ac` | case v2 账本 doc + all=[.v1,.v2] + current=2 + processVersion 反查 + AGENTS 账本行/里程碑行/零新键声明 + .v2 工厂臂 + policyTag .v2 臂（编译器指向落地） | +5 |
| T5 双臂 golden | `32ddb498` | 双臂冻结 golden 套件（密度零漂移组 + 光谱三件套 + sidecar 零 bump + 折键负测 + pristine 门） | +8 |
| fix CC delta | `8e7d6947` | kM/kY 相对 build 操作点取 delta（T5 golden 抓出的真实缺陷：中性对双重施加） | 0 |
| 机械 pin 移动 | `30a05d20` | T1 套件 post-bump 形态 + StackMergeServiceTests birth stamp 字面 → current.rawValue | 0 |
| T6 收口 | 本 commit | Project.swift 五行 + BUNDLE-MAP 五行 + tuist generate 末位 + 双冒烟 + SUMMARY/DECISIONS | +2 |
| **合计** | | | **+31**（越带 +5 申报 = DECISIONS 十一） |

## 定向轮实测（Scripts/test-direct.sh，全程 machine-guard 记录在案）

| 轮 | 结果 | 说明 |
|---|---|---|
| **IOP（全量终态）** | **788/5/0**（915s） | M8-1b 终态 783 → +5 = SpectralSolveTests ✓；首轮 2 失败 = StackMerge birth stamp 字面 pin（bump 机械面，30a05d20 同型修复后复跑套件 13/0/0；全量终态轮零失败） |
| **IOPParity（全量终态）** | **523/11/0**（1479s） | M8-1b 终态 502 → +21 = LegFork 6 + Bake 5 + DualArmGolden 10 ✓ 精确对账；首轮 6 失败 = 4 × T1 pre-bump 陈旧面（30a05d20 修复）+ 2 × GoldenColorTests 环境型 flake（终态全量轮未复现，DECISIONS 十二） |
| **Layers（全量终态）** | **507/6/0**（437s） | 终态 502 → +5 = RenderProcessLedgerTests ✓ 精确对账；RenderProcessSeamTests 8/0/0 + SidecarV10Tests（Library bundle）15/0/0 定向轮在案 |
| 哨兵 | ramp512 `3613671270926763817` / fixture `7557687968680693683` / 中性闭合 `0.1300766902548187` | T5 钉死；probe ④ `10129511468721193651` = 登记消费（DECISIONS 十） |
| peak RSS | 全轮 < 260MB（IOPParity 全量 252MB 最高） | 8G 门远内；guard --monitor 伴跑无 RSS-KILL |

- 全套 `--all` 不在本 plan（M8-3 收口轮统一对账）；定向三 bundle 算术对账
  精确：ΔN 31 = IOPParity +21 + IOP +5 + Layers +5；全套预期 = 4242 + 31 =
  **4273 ∈ [4256, 4274] ✓**（顶带）。
- 新 skip = 0；IOPParity skip 11 = 1b probe 族 5 + 存量 6（逐族申报纪律的
  本批增量面 = 零）。
- tuist generate 恒末位（L041）：全部文件落盘后执行，无生成物入 git
  （.xcodeproj ignored）✓。

## 验收判定（逐条 SC，机检面）

- **T1** ✓ 构建绿；产线 diff = {PixelPipe, FilmTailPolicy, SpectralPayloads}
  + SpectralFilmKernels.metal（strength mix 一枚，DECISIONS 五申报）；
  `git diff PixelPipe.swift` 仅 film leg 工厂区段（runTerminalTails/
  runFilmLeg 骨架行零语义 diff——种子折叠序/3×2 降出矩阵/导出递缝全批零
  触）；冻结臂字节恒等断言在册（legacy==v1 逐位 + FilmDeterminism 全套
  源级零改跑绿）；既有 FilmDeterminismTests 零回归 ✓。
- **T2** ✓ 构建绿；solve 段恰 FilmTailPolicy.swift 一产线文件；键形契约行
  零 diff（cacheKey 原体未触，加法重载共享折叠契约）；modeTag 光谱段常量
  恰一处声明；密度域 FilmFilterPackSolver 零 diff（git diff 零命中）；
  exposureEv 不入键断言在册。
- **T3** ✓ 恰 FilmPrintBake.swift 一产线文件（追加式，密度域 65³ bake 路径
  零 diff——`git diff` 删除行 = 0）；确定性逐位断言在册；tc_lut 槽存在 +
  命中面断言（同 pair 二次 consult = HIT、bakeCount 不增）在册。
- **T4** ✓ exhaustive switch 编译通过 = 分叉点全覆盖编译期证明；折键负测
  在册（legacy/v1 恒等 + v2 独立 FNV 重算精确值）；AGENTS 账本行 +
  里程碑行在 diff；mint 升号写档断言（process=2 + legacy 键缺席）。
- **T5** ✓ 密度核零漂移组全绿（既有 goldens 零改）；sidecar 断言组全绿
  （schemaVersionCurrent grep 恰 11；LightamerSidecar.swift 全批零 diff）；
  `git diff` 产线面 = T1-T4 文件 + AGENTS.md，无第六产线文件（fix 8e7d6947
  = T1/T5 golden 抓出缺陷的修复 commit，DECISIONS 九申报）。
- **T6** ✓ 定向 bundle 面（上表）；Project.swift diff = 五行数组插入；
  BUNDLE-MAP 五行在库；tuist generate 末位；SUMMARY/DECISIONS 在库；
  红线 17 五件套逐项在 DECISIONS §一勾对。

## 红线机检（plan 红线 17 条对照）

- FIX2③：`LibraryProjectController.swift` 零 diff ✓（ba568763^..HEAD 零命中）；
  McpServerController.swift 零 diff ✓。
- 封存面：DrtRecord/TerminalTailPolicy/DrtTailAssembly/DrtPanelModel/
  DrtPanelView/DrtEotf/Lut3dKernels.metal/ExportQueueContract/六格式导出矩阵
  /NodeGraphCommand/LightamerSidecar（v11 零 bump，schemaVersionCurrent==11
  断言在册）/HistoryStack/HistoryHash（process 不折 history hash 的机检面）/
  PipelineDocument/V50Order/GradeCatalog/Registry/ModuleInstance 全零 diff ✓；
  **FilmSubRunKernels.metal 零 diff** ✓（恒零 diff 面）；密度域冻结面
  （FilmFilterPackSolver/FilmPrintBake.bake/FilmRuntimeSolve.solve/film_subrun
  kernel）零 diff ✓。
- 零 FilmRecord 字段（键集冻结七键断言）/ 零 sidecar 新键 / 零 schema bump /
  零 UserDefaults 新键（红线 3/11）✓。
- xcstrings 零触碰 ✓；LocalizationValue 禁形零命中 ✓（红线 4/5）。
- 测试落域（红线 14）：SpectralLegFork/Bake/DualArmGolden ∈ IOPParity、
  SpectralSolve ∈ IOP、RenderProcessLedger ∈ Layers ✓；tuist generate 恒末位
  （红线 6/L041）✓。
- 机器级单重活（红线 7/9）：全部 xcodebuild/tuist/test-direct 前置
  `machine-guard.sh --wait`（G4 磁盘门一次等待后放行，记录在 stdout）；
  只杀自出 PID（零 kill）✓。
- probe 纪律（红线 8）：本批无新 probe（1b probe 族存量不动）✓。
- L057（红线 13）：无面板/对话框触碰（零相关 diff）✓。
- 默认中性零行为门（红线 12）：pristine 文档 v1/v2 逐位恒等（D 组）+
  film-less 文档 process 不可见 ✓；导出面零新增开关（$jobFilmTail 递缝
  零改，export 冒烟 = v2 腿经 .export resolution 有限性验证）✓。
- GPL 合规（红线 16）：strength mix kernel 追加于既有 GPL-3.0 归属文件
  （头部修改清单同批更新）✓。
- process 五件套（红线 17）：DECISIONS §一逐项勾对 ✓。
- C 档门控：本汇报后停，M8-3 不启动 ✓。

## 双臂 golden 证据链

- 正本 = Tests/LightamerTests/SpectralDualArmGoldenTests.swift（8+2 法）。
- 证据登记 = lightamer-evidence 私仓 `m8-fsim-spectral/evidence-m82/
  DUAL-ARM-GOLDEN.md`（哨兵值 + 机制 + probe ④ 关系 + CC delta 修复记录 +
  A2 缓存面实测；pack policy B，M8-1a/1b 同式）。

## 遗留与移交（M8-3 消费面）

- **coupler 数据摄取**：资产集无 coupler 矩阵/Langmuir 数据 → v1 出厂
  couplers-off（结构与 1/4 臂全在位，激活 = payload 构造一行换 face）；
  corr blur 20µm 物理面随激活接线（DECISIONS 四）。
- **逐 CC 表族**：手动 Y/M 二阶效应（dichroic 光谱质）挂账——一阶 E3 形
  已兑现；表族重建秒级带不可作滑杆路径（DECISIONS 六）。
- **cmax 表缓存观察项**：payload 每 run 重造含 cmax 64×720×18 轮二分——
  若帧热点实测成立，升格第二缓存面（DECISIONS 七）。
- **面板 readout**：数值随核变（by design）；「Update to Current Process」
  迁移 UX + NOTICE 升格 + OQ-6/OQ-7/措辞批 = M8-3 正业。
- **全套 --all 对账**：4242 + 31 = 4273 预期 ∈ [4256, 4274]；M8-3 收口轮
  执行（GoldenColorTests 环境型 flake 按 verdict 口径复核，DECISIONS 十二）。

# M8-ACCEPTANCE — FSIM 光谱升维双路独立验收 lane 1（2026-10-26）

> 验收性质：双路 zcode 独立验收第一路（lane 1）。逐项实测核验，不轻信
> executor 报告。HEAD = `903d23fe`；M8 批 = `a44758b0`（首个 m81a 产品
> commit）..HEAD，28 产品 commits；批次基线对照点 = `547a266a`（R4 收口，
> 即 M8 起点^）。
> 复跑日志正本 = `acceptance-lane1/acc1-all.log`（本目录）。

**PASS / 0 B + 0 M + 0 m + 4 obs**

---

## 一、全套回归独立复跑（终值对账）

- 执行形态：`Scripts/machine-guard.sh --wait` 过门 → 同命令链内 ps 验证
  Lightamer/xctest 进程清零 → `machine-guard.sh --monitor 21600` 看门狗伴跑
  （PID 31974，RSS-KILL 零触发）→ `nohup Scripts/test-direct.sh --all` +
  disown 脱离（PID 31977）。构建产物 = executor 交接面（宿主二进制
  2026-10-26 07:29；末个产品代码 commit `d6a3c32f` 02:56 早于构建，其后的
  `af84ddc1`/`903d23fe` 均 test/docs 面——二进制含 T5 pin 修复由复跑结果
  亲证：Library/Sessions/App 三 bundle 陈旧 pin 零复现）。
- **终值 = 4286/46/0（4001s），∈ [4283, 4287] 预期带 ✓**；零 fail 零
  MEMFAIL 零 crash；单次 `--all` 调用即收敛（M8-3 收口轮的环境型
  ToneEqualPerf flake 与装配式形态本轮均未复现）。

| bundle | lane 1 实测 | executor 三轮终账 | 峰值 RSS | 耗时 | 判定 |
|---|---|---|---|---|---|
| IOP | 788/5/0 | 788/5/0 | 6220MB | 955s | ✓ 同值 |
| IOPParity | 529/11/0 | 529/11/0 | 5944MB | 1539s | ✓ 同值 |
| Layers | 507/6/0 | 507/6/0 | 814MB | 449s | ✓ 同值 |
| Library | 778/4/0 | 778/4/0 | 748MB | 168s | ✓ 同值 |
| Sessions | 285/9/0 | 285/9/0 | 1205MB | 61s | ✓ 同值 |
| Export | 385/5/0 | 385/5/0 | 4952MB | 201s | ✓ 同值 |
| App | 1014/6/0 | 1014/6/0 | 2832MB | 628s | ✓ 同值 |
| **TOTAL** | **4286/46/0** | **4286/46/0** | 全轮 < 8G 门 | 4001s | ✓ |

- skip 对账：46 = 基线 41 + 1b probe 族 5（SpectralPerfProbeTests，
  LIGHTAMER_PERF_PROBE 门 + XCTSkipUnless 实证于
  SpectralPerfProbeTests.swift:37-39）——与 M8-VALIDATION §一申报一致。
- ΔN 独立记账：13 个新测试文件 `func test` 直数合计 **恰 80**
  （1a 19 = 3+4+5+7〔T5 冒烟并入 BuildGolden〕/ 1b 17 = 12+5 / M8-2 31 =
  6+5+5+5+8+2 / M8-3 13 = 7+2+4）；4206 + 80 = 4286 与终值精确闭合 ✓。

## 二、四 plan AC 逐条实证（file:line 实测，非转抄）

### M8-1a 数学核-数据面（commit 链 a44758b0..47b28be0）

| AC | 实证 | 判定 |
|---|---|---|
| T1 六字段 additive 解码（nullable 双字段 + Info.viewingIlluminant） | FilmProfile.swift:225/229/233/237/240 + :156（viewingIlluminant）；decodeIfPresent :197-198 | ✓ |
| T1 null 投影 face 单源 | FilmProfile.swift:27-28/213-216（`channelDensityProjected()`/`midscaleNeutralDensityProjected()`/baseDensityProjection 同位家族） | ✓ |
| T1 缺键零漂移负测 + 28 张 null-aware 冒烟 | SpectralProfileDecodeTests 3 法（:72 null 逐点保留 / :171 旧形态 byte-identical / :220 全 28 张实测带） | ✓ |
| T2 常量五件 + provenance 头 + 白点 ≤1e-6 | SpectralConstantsData.swift:1-14（GENERATED 头 + colour-science 0.4.7 出处）+ SpectralConstantsSanityTests 4 法（:31 D65 白点哨兵） | ✓ |
| T3 tc 自拟合器 + 双跑逐位 + 质量门三件 | SpectralTcFit.swift + SpectralTcFitTests 5 法（:165 fullgrid 质量门 / :257 双跑逐位） | ✓ |
| T4 构建引擎 golden 五门 + 表体积 | SpectralBuildGoldenTests 7 法（:66 tc 独立复算 / :176 PCHIP 分级带 / :281 中灰闭合 / :306 体积预算 / :333 端到端逐位 / :342 typed fail-closed / :383 28 张构建时长带）；载体体积 442,368 B 断言在 :306 法内 | ✓ |
| NumPy/dt 对拍 evidence | evidence/t4-numpy-crosscheck.log（`numpy crosscheck: PASS`）+ evidence/t4-dt-source-crosscheck.md（GPL 纪律头注 + 出处行号） | ✓ |
| 测试落域 + BUNDLE-MAP | BUNDLE-MAP.txt:866-869 四行在库；Project.swift 数组插入 | ✓ |

### M8-1b 数学核-GPU 面（e47c32f9..e702be76）

| AC | 实证 | 判定 |
|---|---|---|
| T1 七 stage + fused A/B + corr 降采样臂 | SpectralFilmKernels.metal（stage_a/stage_b + spectral_film_strength_mix :985 + corr 小面）；dispatch 形状断言 SpectralKernelGoldenTests :268 | ✓ |
| T1 GPL 归属双断言（红线 16） | 文件头 :16-22（PORTED from darktable spektrafilm.cl + Modified by Lightamer + 修改清单）+ 根 NOTICE 第 3 条（:112-134 段） | ✓ |
| 既有全仓 .metal 零 diff | `git diff -- "*.metal"` = 唯 SpectralFilmKernels.metal 新增；FilmSubRunKernels.metal 零 diff | ✓ |
| T2 表载体 + 转置上传 + 体积断言 | SpectralPayloads.swift + SpectralKernelGoldenTests :584（上传往返无损）/ :593（texel.x=u 转置面）/ :675（体积） | ✓ |
| T3 bit-exact 分级带 + 三板斧专项 + NaN 三例 | :1398（twin 逐位）/ :1261（micro band，带表 [2e-4,1e-6×5,5e-3] :1272 与 DECISIONS §二逐位一致）/ :417（三板斧源级 grep）/ :1292（fma/取倒分歧度量）/ :1479（共享多项式 device 逐位）/ :1519（NaN 硬化） | ✓ |
| T4 probe 五件默认 skip | SpectralPerfProbeTests 5 法 + XCTSkipUnless 门 :37-39；probe 正本 = 私仓 a6f2872 PROBE-RECORD.md | ✓ |

### M8-2 管线集成（ba568763..ff110abd）

| AC | 实证 | 判定 |
|---|---|---|
| T1 工厂 exhaustive switch 分叉（X4） | PixelPipe.swift `assembleFilmLeg`（switch over `RenderProcess.resolving`，v1→assembleDensityFilmLeg / v2→assembleSpectralFilmLeg）；编译期全覆盖 = exhaustive switch 编译通过 | ✓ |
| T1 密度冻结臂逐字节 | `assembleDensityFilmLeg` doc（pre-M8-2 bytes verbatim）；FilmFilterPackSolver 零 diff（git diff 0 行）；FilmPrintBake 删除行 = 0 | ✓ |
| T1 runTerminalTails 骨架/seed 四项序/3×2 降出矩阵零改 | runTerminalTails :1145 在 diff 首个 hunk（:1219）之前零触；`seedFolding` 单折叠体共享，3-arg 密度形 tag 逐位 `lightamer.film.subrun.v1`（FilmTailPolicy.swift:89/127），4-arg 进程形仅换 tag 值（:132-145） | ✓ |
| T2 solve 光谱域 + 键形契约零 diff + modeTag 隔离 + exposureEv 不入键 | FilmTailPolicy.swift:555（key = fnv(pair⊕stats⊕modeTag) 契约）+ spectralModeTag :656 + SpectralSolveTests 5 法（:137 注册偏移带 / :180 灰阶 0 / :203 键形 FNV 跨核隔离 / :267 ev 不入缓存 / :308 逐位） | ✓ |
| T3 bake 三槽（tc 整 bundle 6 / print 8 / scan 8）+ HIT/bakeCount | SpectralBakeTests 5 法（:79 HIT 逐位 / :117 pair miss / :140 LRU 淘汰 / :154 fills 非 touches / :171 钳位面）；容量 = DECISIONS 七申报面 | ✓ |
| T4 process v2 bump 五件套 | RenderProcess.swift：case v2 账本 doc ✓ / all=[.v1,.v2] ✓ / current=2（:84-90）✓ / processVersion 反查 :167-171 ✓ / AGENTS.md 账本行+M8 里程碑行 ✓；clamp 表测试 RenderProcessLedgerTests :51（四域）+ mint 写档 :66（process=2） | ✓ |
| T4 折键负测（v1 键字节恒等）+ v2 新键空间 | RenderProcessLedgerTests :98（v1 seed 逐位恒等 + v2 独立 FNV 精确值）；`lightamer.film.subrun.v2-spectral` = FilmTailPolicy.swift:99（X4 钉死形态） | ✓ |
| T4 v2 档 → 光谱 payload 形（bump 后为真） | RenderProcessLedgerTests :182 + SpectralLegForkTests :161/:230 | ✓ |
| T5 双臂 golden 三件套 | SpectralDualArmGoldenTests：spectralRampPlaneHash = 3_613_671_270_926_763_817（:62）/ spectralFixturePlaneHash = 7_557_687_968_680_693_683（:67）/ registeredNeutralClosureSpread = 0.1300766902548187（:78，±0.01 带） | ✓ |
| T5 legacy 冻结主门 | FilmDeterminismTests.swift:44 `filmRampPlaneHash = 14_365_179_805_968_017_957`；该文件全批零 commit 零 diff（`git log`/`git diff` 双空）；probe④ 哨兵 10129511468721193651 仅登记消费（DualArmGolden :60 注释 + DECISIONS 十） | ✓ |
| T5 sidecar 零 bump + FilmRecord 键集冻结 + process hash 隔离 | LightamerSidecar.swift 零 diff + schemaVersionCurrent = 11（:255）；testSidecarStaysAtElevenAndRoundTripsByteExact（DualArmGolden :418）+ testFilmRecordKeySetIsFrozen（:491，七键集）+ process hash-isolated 断言（:475-486） | ✓ |
| T5 pristine 零行为门 | testPristineDocumentRendersIdenticallyAcrossArms（DualArmGolden :515） | ✓ |
| T6 端到端冒烟（28 张×双臂 + 导出递缝） | :544（28 张双臂端到端）+ :598（v2 经 .export resolution） | ✓ |

### M8-3 面板+收口（06ac0d41..903d23fe）

| AC | 实证 | 判定 |
|---|---|---|
| T1 UI 零新增快照（31 id 恒等） | FilmPanelSpectralUITests :218（frozen snapshot 集合恒等）+ :244（活树零陌名）+ :309（源码 token 面）；T3 仅增 migrate 行 id（:156 声明） | ✓ |
| T1 adaptation 不暴露 + UserDefaults 零新键 | `grep adaptationBandwidth/adaptationSurface/upsampling App/Sources` = 0；diff 面 UserDefaults 写入 = 0（复核 grep 空） | ✓ |
| T2 descriptor/probe 跟随（零改确认） | FilmDescriptor/FilmDescriptorProbe 零 diff（git diff 0 行）+ DualArmGolden :736（E1 v2 臂 probe 形输出）+ :749（E2 双臂读数 diverge，不断言相等，M83-PROBE-READOUT 落 DECISIONS 五） | ✓ |
| T3 迁移 UX（模型/面板行/确认 sheet/单 discrete commit） | FilmMigrationAction 纯模型（EditorState+FilmMigration.swift:38-46，evaluate 四域表）+ FilmPanelView.swift:138-200（按钮 v2 隐藏 + SwiftUI sheet + init 参数注入零 @Environment + accessibility ids）+ PipeCoordinator.runProcessMigration（:834 域：载体升 2 + marker 一枚 + 重渲 + sidecar 写） | ✓ |
| T3 键族六键 + xcstrings 尾块纯插入 + zh-audit 双 PASS | Localizable.xcstrings :34060-34140 六键；diff +96/−0 纯插入；**zh-audit --check PASS（1726 source / 2041 catalog）+ --self-test PASS（本轮独立复跑）** | ✓ |
| T3 L057 缝（.runModal 零命中） | `grep \.runModal\( App/Sources` = 0 | ✓ |
| T3 undo 边界（撤 marker 不撤 process） | FilmPanelSpectralUITests :455-462（undo 后 process 不回翻断言在册） | ✓ |
| T3 旧档零迁移语义（零自动迁移） | setProcessVersion 唯一生产调用者 = runProcessMigration（WorkspaceModel.swift:371 域 doc + DECISIONS 二 grep 实录）；载入腿 restoreProcessVersion 原孔 | ✓ |
| T4 曝光语义四法 | SpectralExposureSemanticsTests：:84（ev 走 solve gain 不入键）/ :117（落 print 槽，链头 ev_scale ≡ 1——双钉实证 SpectralPayloads.swift:456 uniform 写面 + SpectralBuildEngine.swift:606 引擎表值）/ :188（宽容度 descriptor 键空间 exposure-free）/ :210（NOTICE 升格断言） | ✓ |
| T4 NOTICE §2 升格 + profile/MANIFEST 字节零动 | Resources/FilmProfiles/NOTICE:38-60（ARE consumed as per-wavelength material chain + metameric reconstruction + 「not scene spectral replay」+ density 域 legacy 臂披露保留）；profiles/ + MANIFEST.sha256 + neutral_print_filters.json 零 diff（git diff 0 行）；MANIFEST 对账测试（FilmProfileTests:70 全量非抽样） | ✓ |
| T4 措辞升格三处 + README 零命中 | AGENTS.md:369 勘误行（原文不改追加式）+ :442 M8 里程碑行 + M3-2 RESEARCH-NOTES.md:137；`grep 物理流程建模\|非光谱重放 README.md docs/` = 零命中（DECISIONS 三口径复证） | ✓ |
| T5 全套 --all 对账 | 本文第一节（lane 1 独立复跑 4286/46/0 同值） | ✓ |
| T5 gui 走查证据 | `.work/gui-acceptance/m8/MANIFEST.md` 六项逐一与 M8-VALIDATION §四对账吻合（6 截图文件在库）；**合成输入环境 sheet 确认非确定性已如实申报**（持久化活面由 App 端到端机检承载 + 人工复核行登记） | ✓ |

## 三、封存面零 diff 核验（`git diff 547a266a..HEAD` 逐面对账）

| 封存面 | diff | 判定 |
|---|---|---|
| DrtRecord / TerminalTailPolicy* / DrtTailAssembly / DrtEotf | 0 | ✓ |
| PixelPipe.swift | **+103/−12** | ✓ 域内豁免——4 hunks 全落 film leg 工厂区（:1219-1381）：工厂 doc + exhaustive switch + 密度臂原样提取 + 光谱臂新增 + renderProcess 参数贯穿；runTerminalTails（:1145）/ TerminalTailPolicy enum（:1771）/ 3×2 降出矩阵 / 显示尾段零触（film leg 自有区豁免 = M8-2 PLAN 红线 + CONTEXT m2 登记面） |
| Lut3dKernels.metal / FilmSubRunKernels.metal / 其余全部既有 .metal | 0（唯一 .metal diff = 新增 SpectralFilmKernels.metal，M8 解封申报面） | ✓ |
| ExportQueueContract / ExportFormatSpec / ImageIOEncoders / WebPEncoder | 0 | ✓（ExportRenderer 有 diff，但非封存清单成员——M8-3 DECISIONS 一申报面） |
| NodeGraphCommand / HistoryStack / HistoryHash / PipelineDocument（Core） | 0 | ✓ |
| LightamerSidecar（sidecar schema） | 0；schemaVersionCurrent = 11 零 bump | ✓ |
| V50Order / GradeCatalog（NodeOwnershipCatalog） | 0 | ✓ |
| FilmFilterPackSolver / film_subrun kernel / FilmDeterminismTests（密度冻结主门） | 0 | ✓ |
| Resources/FilmProfiles 数据件（profiles/ + MANIFEST.sha256 + neutral_print_filters.json） | 0 | ✓ |
| FIX2③：LibraryProjectController.swift / McpServerController.swift | 0 | ✓ |
| UserDefaults 键族 | 零新键（diff 面复核空） | ✓ |

\* TerminalTailPolicy 类型（PixelPipe.swift:1771）与 FilmTailPolicy.swift 为
两个不同面；前者零 diff，后者 diff 全部落在 film 自有区（seed tag 段/solve
段/box 扩形），其封存语义面（seed 四项序、键形契约行 :555、3×2 降出矩阵）
逐点核验零改。

## 四、证据面抽查

- **gui-acceptance**：`.work/gui-acceptance/m8/MANIFEST.md` 在库，六项
  （walk-01..05b）与 M8-VALIDATION §四逐项对账吻合；六截图文件在库；
  走查范围如实申报节在案（sheet 合成输入非确定性 + SidecarStore 去抖写
  观察项 + probe 缝竞态）——GUI 实机复核归 omp 终审职责，本 lane 只做
  文面对账。
- **私仓证据链**（lightamer-evidence，本地在案性核对）：`75298b9`（1a T2
  常量生成器 + log）/ `2b48924`（1a T4 numpy 对拍 + dt 转录）/ `a6f2872`
  （1b PROBE-RECORD.md）/ `106c328`（M8-2 DUAL-ARM-GOLDEN.md，四哨兵
  登记 + 机制 + 中性闭合申报）——四 commit 与 M8-VALIDATION §二指针逐条
  吻合。
- **zh-audit**：`--check` PASS（1726 source keys / 2041 catalog keys）+
  `--self-test` PASS（V17 golden 八 case 持立）——本轮独立复跑，与
  DECISIONS 二申报数精确一致。

## 五、偏差与观察（逐条编号）

- **obs-1**：M8-2 收口轮的 `--all` 装配式对账形态（红即停 + 环境型
  ToneEqualPerf flake + 陈旧 pin 组合）在本 lane 未复现——单次 `--all`
  直接收敛且七 bundle 逐值同账；M8-3-DECISIONS 六.6 的装配式形态登记仍
  有效（供后续同类场景引用），非缺陷。
- **obs-2**：迁移持久化活面的 GUI 链路未在实机走查闭环（合成输入对
  sheet 确认按钮非确定性）——MANIFEST 已如实申报并以
  `testMigrationEndToEndFlipsCarrierAndPersistsProcess2` 端到端机检承载，
  人工复核行登记在案；omp 终审（computer-use）应消费该复核行。
- **obs-3**：验收消费的构建产物 = executor 交接面（宿主 07:29 构建），
  早于 `af84ddc1` 提交时刻（09:44）——build-then-commit 流的常态；二进制
  含该 pin 修复由复跑亲证（Library 778/4/0 + Sessions 285/9/0 + App
  1014/6/0 零陈旧 pin 失败）。若后续批要求更强证据，可在收口轮固化
  「构建 mtime > 末 commit mtime」机检（不改本批判定）。
- **obs-4**：M8-2 遗留观察项（cmax per-run 重建 → 迁移端到端 240s 实测；
  SidecarStore probe 空闲实例去抖写不自发落盘；descriptor v2 重锚定
  posture）已在 M8-2/M8-3 DECISIONS 挂账登记，本 lane 核对账面一致，
  不构成 M8 验收阻断面。

## 六、结论

四 plan AC 全数实证通过（逐条 file:line 见第二节）；封存面零 diff 核验
通过（唯一命中 PixelPipe 于声明豁免域内，域外零触）；全套回归独立复跑
4286/46/0 与 executor 三轮终账逐 bundle 精确同值、带内、零 MEMFAIL；
证据面（gui MANIFEST + 私仓四 commit + zh-audit 双 PASS 复跑）在案吻合。
**M8 批验收 lane 1 = PASS（0 blocking / 0 major / 0 minor / 4 observations）**，
移交 omp 终审（GUI 实机走查 + 二次验收串行道）。

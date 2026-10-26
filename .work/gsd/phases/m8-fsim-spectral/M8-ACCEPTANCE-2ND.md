# M8 验收报告 — lane 2（双路独立验收第二眼，2026-10-26）

> **独立性纪律执行声明**：本报告全程未读 `M8-ACCEPTANCE.md`（lane 1）及其
> `acceptance-lane1/` 日志；全部结论从一手正本（四 PLAN / 四 SUMMARY /
> 四 DECISIONS / M8-VALIDATION / M8-CHECKER / 产线源码 / 测试源码 / 实跑
> 日志）独立形成。HEAD = `45f88435`（账本 commit；产品面终点 = `903d23fe`）。
> M8 批范围 = `547a266a..903d23fe`（首个 M8 commit = `a44758b0`，基线 =
> `547a266a`）。

## 结论头

**PASS / 0 B + 0 M + 0 m + 5 obs**

- 四 plan AC 抽查面逐条独立核对全绿（file:line 实证见 §三）。
- 全套回归独立复跑 **4286/46/0**（单次连续 `--all`，4009s）∈ [4283, 4287]，
  与 executor 申报三轮逐 bundle 逐值同；零 MEMFAIL 零 crash。
- 封存面核验：清单 15 项零 diff；命中面全部为 film leg 自有区豁免正业 +
  DECISIONS 申报面（§二逐项）。
- 行为级探针：改 CMF 常数 → 白点哨兵 + 生产缝 ramp 哨兵双红（§四——
  反自取消金样成立，哨兵透过真实生产缝测真东西）。

## 一、全套回归独立复跑（orchestrator 预批 --all）

执行形态：`machine-guard.sh --wait` 过门 → 命令链内 ps 验证 Lightamer/
xctest 进程清零（=0）→ `--monitor 21600` 看门狗伴跑（PID 55977，全程零
RSS-KILL，跑完 kill）→ `nohup Scripts/test-direct.sh --all > acceptance-lane2/
acc2-all.log 2>&1 & disown`。**单次连续调用**（非装配式——executor 三轮
因当时红即停用了装配式，本轮无红无停）。

| bundle | lane2 实跑 | 申报三轮（VALIDATION §一） | 判定 | peakRSS |
|---|---|---|---|---|
| IOP | 788/5/0（928s） | 788/5/0 | 同值 ✓ | 6129 MB |
| IOPParity | 529/11/0（1559s） | 529/11/0 | 同值 ✓ | 5750 MB |
| Layers | 507/6/0（456s） | 507/6/0 | 同值 ✓ | 814 MB |
| Library | 778/4/0（170s） | 778/4/0 | 同值 ✓ | 749 MB |
| Sessions | 285/9/0（60s） | 285/9/0 | 同值 ✓ | 1206 MB |
| Export | 385/5/0（200s） | 385/5/0 | 同值 ✓ | 5022 MB |
| App | 1014/6/0（636s） | 1014/6/0 | 同值 ✓ | 2832 MB |
| **TOTAL** | **4286/46/0 / 4009s** | 4286/46/0 三轮同值 | **同值 ✓** | 全轮 <8G 门 |

- skip 对账：46 = 基线 41 + SpectralPerfProbeTests probe 族 5
  （LIGHTAMER_PERF_PROBE 门）——与申报逐族一致。
- MEMFAIL 行：零。
- ΔN 链独立复算：4206（基线）+ 19（M8-1a：3+4+5+6+1）+ 17（M8-1b：
  KernelGolden 12 + PerfProbe 5）+ 31（M8-2：LegFork 6 + Bake 5 + DualArm 10
  + Solve 5 + Ledger 5）+ 13（M8-3：PanelUI 7 + DualArm +2 + Exposure 4）
  = **4286** ✓——测试方法数逐 suite `grep -c "func test"` 独立清点闭合。

## 二、封存面零 diff 核验（`git diff 547a266a..HEAD` 过清单）

| 封存面 | 判定 |
|---|---|
| DrtRecord / TerminalTailPolicy / DrtTailAssembly / Lut3dKernels.metal / DrtEotf / ExportQueueContract / ExportFormatSpec / ImageIOEncoders / WebPEncoder / NodeGraphCommand / LightamerSidecar（schemaVersionCurrent=11 :255 亲核）/ HistoryStack / HistoryHash / PipelineDocument（Core）/ V50Order / GradeCatalog（NodeOwnershipCatalog） | **零 diff** ✓ |
| FilmSubRunKernels.metal / FilmFilterPackSolver.swift（密度冻结面邻接） | **零 diff** ✓ |
| PixelPipe.swift（+115） | **豁免正业**：diff 全部落 film leg 工厂区段（:1219-1380）——X4 分叉 exhaustive switch + assembleDensityFilmLeg 冻结臂原样提取 + assembleSpectralFilmLeg 新臂；runTerminalTails 骨架/runFilmLeg 零触 ✓ |
| FilmTailPolicy.swift（+212） | **豁免正业**：diff hunk 全部在 policyTag 段（:88+）/seed（:145+）/FilmMethodBox payload 分型（:243+）/solve 段（:534+）——film leg 自有区；密度核消费路径字节未触 ✓ |
| ExportRenderer.swift（+13） | 清单外，**申报面**：M8-3-DECISIONS 一（磁盘 sidecar `document.process ?? .legacy` 派生 + 两 render 调用点传 process——M6-2 注册 coordinator threading 欠账补齐，红线 12 filmTail-follows-record+process 的 export 面）✓ |
| EditorState.swift（+19）/ PipeCoordinator.swift（+59）/ WorkspaceModel.swift（+14）/ FilmPanelView.swift（+96）/ FilmPanelModel.swift（+28）/ EditorState+FilmMigration.swift（新） | M8-3 T3 正业 + DECISIONS 一（接线三文件）/二末件（commitProcessMigrationMarker 落本体——file-private 域）申报 ✓ |
| RenderProcess.swift（+37） | M8-2 T4 五件套正业 ✓ |
| FilmProfile.swift（+254） | M8-1a T1 正业（additive 六字段）✓ |
| Project.swift（+13 行）/ xcstrings（+96/−0 纯插入）/ NOTICE（+18/−9） | 测试数组行 / 尾块键族 / T4 措辞批修正业 ✓ |
| 测试文件 8 处 pin 移动（FilmProfileTests/ImportService/Metadata/ProcessVersionCarrier/RenderProcessSeam/SessionBatchApplier/SidecarV10/StackMerge） | 机械 pin 移动申报面（`30a05d20` + `af84ddc1`，M8-3-DECISIONS 六.1/六.4）✓ |

FIX2③ 附加核验：`LibraryProjectController.swift` / `McpServerController.swift`
零 diff ✓。Resources/FilmProfiles/ profile JSON + neutral_print_filters +
MANIFEST.sha256：`shasum -a 256 -c MANIFEST.sha256` 全 28 件 OK（零非 OK 行）
✓。

## 三、AC 逐条对账（重点抽查面，独立 file:line 实证）

| # | 抽查面 | 实证 | 判定 |
|---|---|---|---|
| 1 | process v2 bump 双臂 + 单源 + 五件套 | `RenderProcess.swift:90`（current=2）/:122-135（case v1 frozen-arm + case v2 doc 账本）/:139（all=[.v1,.v2]）/:156-161（clamp 表）；`PixelPipe.swift` assembleFilmLeg exhaustive switch（`.v1`→assembleDensityFilmLeg 原样 / `.v2`→assembleSpectralFilmLeg）；AGENTS.md:399（process 账本行 v1→v2）；M8-3 迁移 `d6a3c32f`（FilmMigrationAction + 面板行 + sheet） | ✓ |
| 2 | legacy 冻结主门 filmRampPlaneHash | `FilmDeterminismTests.swift:44`（`14_365_179_805_968_017_957`）+:415 断言消费；全套 IOPParity 529/11/0 零改跑绿（本轮实跑） | ✓ |
| 3 | 光谱 golden 哨兵三件 | `SpectralDualArmGoldenTests.swift:58`（ramp512 `3_613_671_270_926_763_817`）/:63（fixture `7_557_687_968_680_693_683`）/:78（中性闭合注册 `0.1300766902548187`）；`testSpectralArmRampSentinel`/`testSpectralArmRealImageSamplingGolden`/`testMidGrayNeutralClosureThroughV2Chain` 三法在册且本轮绿 | ✓ |
| 4 | 曝光语义四法 | `SpectralExposureSemanticsTests.swift:84`（solve gain 消费层不入键）/:117（ev_scale ≡ 1 双钉——print slot 不入 expose 链头）/:188（descriptor 键空间 exposure-free）/:210（NOTICE 升格断言）；4/0/0 本轮绿 | ✓ |
| 5 | Film 面板零新增控件 | `FilmPanelSpectralUITests.swift:218`（31 id 冻结快照恒等）/:244（AX 活树零陌名）/:309（源 token grep 面）；adaptationBandwidth/adaptationSurface/upsampling 于 App/ grep = **0 命中**（本轮独立复跑） | ✓ |
| 6 | NOTICE 措辞 + profile 字节零动 | `Resources/FilmProfiles/NOTICE:39-53`（「ARE consumed as a per-wavelength material chain … metameric reconstruction … not scene spectral replay」升格 + 密度域冻结臂披露保留 + couplers-off 出厂态诚实注记）；MANIFEST.sha256 对账 28/28 OK | ✓ |
| 7 | 迁移 UX 四面 + undo 边界 + L057 | pristine（`EditorState+FilmMigration.swift:43` notApplicable guard）/迁移按钮（`FilmPanelView.swift:143-150`）/确认 sheet（:171-200，SwiftUI sheet + init 参数注入）/渲染翻面（`PipeCoordinator.swift:866-876` runProcessMigration：carrier 升 2 + marker + historyDidChange + scheduleSidecarWrite）；undo 边界 = process 无 history 槽（grep 全文仅 3 读点、零 sync 点）；`grep -rn "\.runModal(" App/Sources` = **0 命中**（本轮独立复跑） | ✓ |
| 8 | 折键「非 legacy 才折」+ 折叠序 | `FilmTailPolicy.swift:89`（`policyTag = "lightamer.film.subrun.v1"`）/:99（`spectralPolicyTag = "lightamer.film.subrun.v2-spectral"`）/:104-110（policyTag(for:) arm 分派——v1 verbatim）；`RenderProcessLedgerTests.swift` testV1SeedStaysByteIdenticalAndV2OpensANewKeyspace；filmRampPlaneHash 零改跑绿 = 端到端主门 | ✓ |
| 9 | M8-1a 数据面（六字段/零漂移/28 冒烟/白点/确定性） | `FilmProfile.swift:225-240`（六 additive 字段 + decodeIfPresent/encodeIfPresent :276-277）；`SpectralProfileDecodeTests` 3 法（六项 null 保留 / 旧形 decode→encode byte-identical / 28 张 null-aware 带）；`SpectralConstantsSanityTests` 4 法（白点哨兵 1e-6/locus 闭合/SPD 域/dichroic）；`SpectralTcFitTests` 5 法（双跑逐位 testDualRunBitIdentity 在册） | ✓ |
| 10 | M8-1b GPU 面（GPL 头/三板斧/既有 .metal 零 diff） | `SpectralFilmKernels.metal` 文件头（darktable spektrafilm.cl GPL-3.0 + Modified by Lightamer + 上游版权保留）；`fma(` 58 处；log10/exp10/cbrt 禁令断言（`SpectralKernelGoldenTests:495-501`）+ GPL grep 断言（:507-513）；根 NOTICE 第 3 条登记行（:112-135，M8-1B-DECISIONS:123 登记落点）；`git diff 547a266a..HEAD --stat -- "*.metal"` = 仅新文件 | ✓ |
| 11 | sidecar 零 bump | `LightamerSidecar.swift:255` schemaVersionCurrent = 11；`SpectralDualArmGoldenTests:418` testSidecarStaysAtElevenAndRoundTripsByteExact + :491 testFilmRecordKeySetIsFrozen；LightamerSidecar.swift 本体零 diff | ✓ |
| 12 | 缓存槽 X7 + solve 键形 | `SpectralPrintBake.tables(forPairHash:)` 消费于 assembleSpectralFilmLeg（tc 槽 per-pair LRU）；`FilmBake` 家族 5 法（HIT 逐位/pair 键控/LRU/bakeCount/钳位面）；solve 键形 fnv(materialPairHash ⊕ statsHash ⊕ modeTag)（`FilmTailPolicy.swift:555+`）+ `spectralModeTag` 跨核隔离（:656）+ `SpectralSolveTests` testSpectralCacheKeyIsCanonicalFNVAndCrossCoreIsolated | ✓ |

## 四、行为级独立探针（反自取消金样）

**设计**：改一个生产常数（`SpectralConstantsData.swift` cmfs[0] 的 x̄@380nm
`0.001368` → `0.001568`，+0.0002）到 `/tmp/m8-acc2-probe` 独立 worktree
（`git worktree add --detach HEAD`，主树零触碰），独立构建（独立
DerivedData）后跑哨兵单法，验证「改常数必红」。做完即删（worktree +
DerivedData + 日志全清，`git worktree list` 复核主树独存）。

| 腿 | 树 | 常数 | 宿主来源 | 结果 |
|---|---|---|---|---|
| 主树对照 | 主树 `45f88435` | 原值 | 主树 DerivedData（全套同产物） | `testSpectralArmRampSentinel` **1/0/0 绿**（258s） |
| 探针·白点 | worktree | +0.0002 | 探针独立 DerivedData | `testD65WhitePointIntegrationReproducesTheSentinel` **1/0/1 红**——xy 实测 0.3127215946 vs 注册 0.3127205252，散 1.07e-6 > 1e-6 带（:41 断言） |
| 探针·生产缝 | worktree | +0.0002 | 探针独立 DerivedData | `testSpectralArmRampSentinel` **1/0/1 红**（245s）——`XCTAssertEqual failed: ("5071070346921862477") is not equal to ("3613671270926763817") — the spectral arm's ramp plane hash drifted from the production golden sentinel`（:341 断言，错误文案自带 re-pin 纪律指引） |

**结论**：改一个 CMF 波长点 → 数据面哨兵（白点积分）与生产缝哨兵（真实
pipe film leg v2 臂端到端平面 FNV）双双必红——哨兵测试透过
SpectralBuildEngine 表链 → GPU dispatch → 输出平面哈希的真实生产缝在测真
东西，反自取消金样成立。

**探针过程注记（obs-1）**：首轮探针腿假绿——根因 = `Scripts/test-direct.sh`
的 DerivedData 定位硬编码 glob `~/Library/Developer/Xcode/DerivedData/
Lightamer-*`（:205，无 env 覆盖缝），探针树构建在自定义 `-derivedDataPath`
时脚本静默回落主树宿主（跑的仍是未改常数二进制）。修正 = HOME 重定向
（`HOME=<probe-home>` 使 glob 落探针 home 内容器）+ `CODE_SIGNING_ALLOWED=
NO`（HOME 重定向下 'Lightamer Dev' 签名证书不可达）。被测对象无缺陷；
工具缝建议（不改代码，仅登记）：test-direct.sh 增设 `LIGHTAMER_DD_ROOT`
类 env 覆盖缝，供 worktree 验证/双树实验场景。

## 五、zh-audit 独立复跑

- `uv run python3 Scripts/zh-audit.py --check` → **PASS**（1726 source keys /
  2041 catalog keys / 10 interp keys variant-PRESENT / zh complete / locale
  {en, zh}）——与 M8-3-DECISIONS 二申报数字一致。
- `--self-test` → **PASS**（V17 golden 八 case 持有）。
- xcstrings 尾块纯插入独立复核：`git diff 547a266a..HEAD --stat` = +96 行
  0 删除行；六新键（history_process_migrate + panel_film_migrate_body/
  button/cancel/confirm/title）grep 在册。

## 六、证据面抽查（`.work/gui-acceptance/m8/MANIFEST.md`）

- MANIFEST.md 在库，六项走查（pristine 面 / v2 readout 活面 / v1 档迁移
  按钮 / 确认 sheet / 同屏佐证 / 确认后渲染翻面）逐项对应
  `walk-01..05b` 六截图文件（ls 实证在库）——与 M8-VALIDATION §四对账一致。
- 如实申报面核实：迁移持久化活面（sheet 确认→落盘的 GUI 链路）申报
  「合成输入非确定性，由 APP bundle 端到端机检承载
  （testMigrationEndToEndFlipsCarrierAndPersistsProcess2）+ 人工复核行」——
  该端到端测试在册（`FilmPanelSpectralUITests.swift:384`）且 App bundle
  1014/6/0 本轮绿。申报诚实，无账实不符。

## 七、偏差与观察（B/M/m/obs 逐条）

- **B（blocking）：无。**
- **M（major）：无。**
- **m（minor）：无。**
- **obs-1**（工具缝）：test-direct.sh DerivedData glob 无 env 覆盖缝——
  worktree/双树场景静默跑主树宿主（§四探针注记；建议项，非本批缺陷）。
- **obs-2**（资源编排）：验收起跑时 Data 卷 24.8GB 贴 G4 门 guard BLOCK ×4
  轮；按 M8-3-DECISIONS 六.4 同款处置修剪我方可再生模块缓存
  （SDKExplicitPrecompiledModules/ModuleCache/CompilationCache，~400MB）后
  过门（26.2GB）。长期张力 = 申报过的编排侧注记，本批无新违规。
- **obs-3**（RSS 方差）：IOP bundle 本轮 peakRSS 6129MB vs 申报三轮带
  5603-5769MB（+6.3%，超 ±3% 方差注记）——<8G 门 + 零 MEMFAIL + 单轮观察，
  不判异常；IOP 历史贴线（7654）注记在案，后续连续 MEMFAIL 时按 AGENTS
  口径先查重测顺序漂移。
- **obs-4**（已申报偏差复核）：中性闭合注册值 0.1301 vs plan 带 ≤2e-3——
  M8-2-DECISIONS 九的申报逻辑独立复核自洽（plan 带是密度臂反演构造的
  premise，光谱链无反演面；机制拆解：链头 print raw 通道散 ≈3.7e-6 ✓ →
  paper 密度三通道差 + scan 积分残差 = 输出 ~13%）；±0.01 漂移带钉死 +
  测试注释内嵌偏离声明。维持申报原判，不升级。
- **obs-5**（哨兵消费形态）：probe ④ 哨兵 `10129511468721193651` =
  probe-only 双 blur 序列（M8-2-DECISIONS 十如实注记「登记消费非生产
  复现」）——生产哨兵三件独立在 SpectralDualArmGoldenTests 钉死；两套
  哨兵不可互换的边界申报诚实。

## 验收判定汇总

四 plan AC 抽查面 12 组全绿（§三）；封存面 15 项 + FIX2③ 零 diff，命中面
全部豁免正业或 DECISIONS 申报面（§二）；全套独立复跑 4286/46/0 与申报逐
值同、ΔN 链独立清点闭合（§一）；反自取消探针双红成立（§四）；zh-audit
双 PASS（§五）；证据面账实一致（§六）。**M8 批通过 lane 2 独立验收。**

> 探针证据日志（断言行截图文本）已内嵌 §四；`acc2-all.log` /
> `guard-mon-l2.log` / `probe-ctrl-main.log` 三份原始日志随本报告存
> `acceptance-lane2/`。

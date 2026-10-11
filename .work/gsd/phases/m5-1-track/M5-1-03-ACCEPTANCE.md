# M5-1-03 ACCEPTANCE — TRACK P3（match_color MCP 最小面 + G4 + 五门收口）zcode 独立验收

> 验收批 2026-10-12（zcode 独立验收 subagent；零共享上下文，实测核验不轻信；
> 夜间全自动授权在案）。对象 = `3be69ee..2002779` 四提交。**结论：
> PASS（本批范围全部 AC 亲证通过）**，附带**一项非本批 P1 潜伏缺陷登记**
> （M3-3 Film leg 引用计数竞态，阻断本机当晚全 App bundle 复跑——非本批引入，
> 零 diff 铁证 + 溯源在案 §7）；账面小修 2 处（§8）。omp 二次验收按 config
> `dual_acceptance` 由 orchestrator 串行派遣（本批未派，不并发）。

## 0. 验收程序与亲跑数字

**独立重建**：`tuist generate` + 全部 8 scheme（host + 7 bundle）逐一
`build-for-testing` 重建（L075 纪律照办；构建日志零 FAIL）。复跑落
`Lightamer-dgzsvdww` 容器（脚本按 xctest mtime 取最新容器选中，亲核）。

**全套 `--all` 复跑**（orchestrator 派发即批准；跑前孤儿 fixture 预删，
M4-1 #6 预防照旧）：

| bundle | 我方实测 | peakRSS | MEMFAIL | worker 申报（GATE-LEDGER §6） | 对账 |
|---|---|---|---|---|---|
| IOP | **563/1/0** | 7190MB | 无 | 563/1/0（7806MB） | 逐位 ✓ |
| IOPParity | **444/3/0** | 7305MB | 无 | 444/3/0（8107MB） | 逐位 ✓ |
| Layers | **466/4/0** | 1222MB | 无 | 466/4/0（1180MB） | 逐位 ✓ |
| Library | **626/4/0** | 616MB | 无 | 626/4/0（618MB） | 逐位 ✓ |
| Sessions | **279/4/0** | 1625MB | 无 | 279/4/0（1249MB） | 逐位 ✓ |
| Export | **350/1/0** | 6435MB | 无 | 350/1/0（6085MB） | 逐位 ✓ |
| App | **crash（§7）** | — | — | 749/4/0（2832MB） | ✗ 被预存缺陷阻断 |

- 六 bundle 合计 **2728/17/0** 与 worker 逐位相等；RSS 差值（如 IOPParity
  5836↔7305↔8107）在 SPIKE 70e09e5 在案的重测顺序漂移族内，全轮零 MEMFAIL
  （<8192MB 门）。
- **诚实声明**：我方三试（`--all` 一轮 + L055 重跑两轮 + FilmPanelTests
  单类一轮）均未能产出 App bundle 全绿轮——阻断因子 = §7 非本批缺陷。
  批内关键面以下列**定向亲跑**补齐（同批新产物）：

| 定向轮（App bundle，类过滤） | 我方实测 | worker 申报 |
|---|---|---|
| `McpMatchColorToolsetTests` | **21/0/0** | 21/0/0 ✓ |
| `McpMatchColorParityTests`（G4） | **3/0/0** | 3/0/0 ✓ |
| `McpRegistrySnapshotTests` | 8/0/0 | 8/0/0 ✓ |
| `McpFinalSnapshotTests` | 6/0/0 | 6/0/0 ✓ |
| `McpLauncherTests` | 10/0/0 | 10/0/0 ✓ |
| `McpHostTests` | 18/0/0 | 18/0/0 ✓ |

- **3477 单轮全绿亲证未达，以三重互证替代**：①六 bundle 我方逐位 +
  ②批内六定向轮我方逐位 + ③worker 七 bundle 日志逐份解析复核（我方在
  worker 轮日志覆盖前抓存 `/tmp` 副本逐 bundle 重析，E/S/F/peakRSS/末条
  `All tests` 身份五字段全对上 GATE-LEDGER §6 表）。对账链
  3367+38+47+1+24 = **3477** 算术闭合；App = 725+24 = 749（724 基线 +
  E-omp1 +1 出 `M5-1-02-OMP-FIX.md` 实测轮，锚在案）。

## 1. match_color e2e 审计（本波灵魂）

**读码**（`MatchColorToolset.swift` 616 行全文 + `EditingToolset`/`LightamerApp`
diff）：

- 五参签名全落（OQ-6 字面）：reference 必填、targets string|array 缺省当前图
  （`liveImageURL`→session relPath 映射，live 缺席 = typed invalidParams）、
  strength 0...1 缺省 1.0、solver kebab 三档缺省 gaussian-ot、attach 缺省 true。
- **fan-out 逐目标独立求解**：N 目标共享参考统计、源统计逐图独立（解不同 =
  设计语义，工具 doc 明示）；帽 30（get_contact_sheet 先例）在 GPU 前置门
  fail-fast（负测以无 metal seams 钉「参数层先行」，亲读 :265-280）。
- **attach=true** = store 级投影缝（`projectColormatch` @MainActor 值调用 +
  `SessionBatchApplier` 一次写 + `flushForTeardown`）——与 apply_params
  projectInstances 同缝（E6 注记兑现）；attach=false = 参数组返回（含
  assetRef/assetHash 语义说明 note）。
- **render gate**：整调用 `withRenderGate` + render 档 bounded wait；硬超时
  typed `renderTimeout`（已完成目标落盘真相保留文案在返回体）；GUI-live 目标
  拒写不拒读（attach=false 只读放行，两测钉死亲读）。
- **确定性披露**：solveHash 随返回（线性臂 = `ColorMatchSolveCache.cacheKey`
  折叠、CDF 臂 = `solution.solutionHash`，均十进制 L013）——与 plan KD-1
  「solution.stableHash」措辞有出入（实为 solve-cache 键折叠/解哈希，语义 =
  解身份不含 strength），确定性承诺（同输入同哈希）不受扰，非缺陷，注记备案。
- **两段流与 seed ABSENT 一致**：`apply_params` 无法 CREATE colormatch =
  M5-1-01 seed ABSENT 密封必然（G5 锚 `testColormatchAbsentFromEditingSeed`
  双面断言亲读；`IopCatalog` colormatch 行 :287 零 diff）——m4 回灌面 =
  attach=true 建实例 → attach=false 组经 apply_params 重参数化，工具 doc
  已写明（E-omp1 同族，非缺陷）。
- **solver 拼写二态**（DECISIONS §8）：入参 kebab / 返回与 wire =
  `ColorMatchSolverKind` rawValue（`gaussianOT`）——apply_params 回灌字节
  诚实，`testRelPathReferenceSolvesAndAttachesWithDefaults` :318 钉死。亲核。
- 宿主形态（申报偏离核实）：`MatchColorToolset` 自持两 box
  （library provider / 共享 ColorMatchService，headless 惰性 standalone +
  `configure` 进 `ColormatchResolverBox.shared`）+ `LightamerApp` 装配两行
  install（:1174-1186，机制必需——不装则 id 形 reference 生产恒 typed 死面、
  不共享 service 则双 resolver 互踢 shared box；装配 order 先于
  `startEmbeddedIfPreferenceEnabled` 亲核）。偏离合理，接受。

**亲跑**：`McpMatchColorParityTests` 3/0/0（G4 三法亲证）——

- `testMatchColorApplyParamsRenderPreviewParity`：match_color(attach) →
  apply_params(strength 0.7 微调真实闭环) → render_preview == 本地
  renderedPlane+JPEG q85 **逐字节**（SC#3 同型，零容差带未放宽）；
- `testBatchDoubleTargetParity`：单次 fan-out 双目标各自逐字节；
- `testDoubleCallDisclosesTheSameSolveHash`：双调用同 solveHash（G1 agent 面）。
- `McpMatchColorToolsetTests` 21/0/0：schema 五法 + reference 双形态 6 法
  （id happy/无库 typed/未知 id/stale linker/路径非成员/relPath happy）+
  无头批量 fan-out（E6）+ 透传 + CDF 资产臂 + attach=false→apply_params 回灌
  （m4，sourceStatsHash/referenceStatsHash 逐位回灌断言）+ GUI-live 两态 +
  缺省当前图 + 确定性双测 + gate 串行 + list_iops/apply_params 元数据复用。
  21 法清点与 DECISIONS §11 申报逐位吻合。

## 2. 快照族审计（checker E3，security face）

四文件 diff 逐 hunk 亲核（对照 DECISIONS §7 申报「实际改动面 > plan 行号」）：

- `McpFinalSnapshotTests`：frozen 表入 verbatim descriptor + `all19→all20`
  更名 + `testFinalSnapshotUnion19Verbatim→20` + 白名单负测重形
  （`testTwentiethToolIsWhitelistNegative→testPostUnionToolIsWhitelistNegative`，
  match_color 移出 not-a-tool 名单、剩 delete_file/run_shell）+ destructive
  集 8→9（match_color 入破坏列，destructiveHint: true 与注册面一致）+
  descriptionKeys 增 `mcp_tool_desc_match_color` + 计数 :199/:227/:370 三处。
- `McpRegistrySnapshotTests`：editing 域表（5→6）入 verbatim descriptor
  （plan 行号外首跑红面，申报属实）+ :191 计数 + 三处注释。
- `McpLauncherTests` :197 / `McpHostTests` :242/:694 计数 19→20 + 注释。
- **schema 三方字节比对（机检亲跑）**：工具注册源 / final frozen 表 /
  editing 域表三处 inputSchemaJSON 逐字节相等（提取正则全串 md5 比对，
  `0bde6ea4…` 三方一致）。
- 不动点亲核：`McpHostTests:726`「19 ops」= IOP 目录计数（full-face 19 iops
  含 colormatch），非工具数，未触碰 ✓；`McpRenderParityTests:564` 陈旧注释
  零 diff（plan 预授权核对点）✓。
- xcstrings +1 键 = `mcp_tool_desc_match_color` 尾块纯插入，zh 译文在案
  （diff 亲读）；`McpServerController` 头注「frozen 19-tool set」陈旧未改 =
  files_modified 纪律（DECISIONS §12 登记，历史注记不误导行为，接受；
  后续 plan 顺手面）。

## 3. skip 16→21 身份表（本波重点，逐个验身份）

我方全套轮 21 skip 全枚举（各 bundle 日志 `' skipped` 行 + 理由行逐条提取）：

| # | bundle | 测试 | skip 理由（日志原文摘） | 类别 |
|---|---|---|---|---|
| 1 | IOP | SkinRegionGeometryTests testVisionProviderOnSynthesizedFaceDrawing | no face detected in the cartoon drawing (host Vision state) | 模型/宿主态 |
| 2 | IOPParity | GoldenColorTests testNeutralPatchesColorCheckerARW | ColorChecker ARW not present… synthetic target carries the gate | fixture 缺席（合成面扛门） |
| 3 | IOPParity | GoldenColorTests testCrossConsistencyColorCheckerARW | 同上 | 同上 |
| 4 | IOPParity | LutLibraryRecursionTests testRescanTenThousandFilesManualProbe | manual probe（env 门） | env 探针 |
| 5 | Layers | AIMaskDeterminismTests testLayerBDefaultInProcessByteIdentity | layer B assets unavailable (entitlement-blocked download) | 模型资产 |
| 6 | Layers | AIMaskSemanticTests testLayerBSeedNonEmptyAndExcludedPointDrops | 同上 | 模型资产 |
| 7 | Layers | ColorMatchBakeGoldenTests testBakeTimeBudget | PERF_PROBE 门（M5-1-02 bake 批新增，源 :256-266 亲读） | env 探针（**本波新增**） |
| 8 | Layers | GradeEnvelopePerfProbeTests testFullPipe100MPGradeLayerCostProbe | PERF_PROBE 门 | env 探针 |
| 9-11 | Library | LibraryBenchmarkHarness ×2 + LibraryGridModelTests testThumbnailFirstScreenProductionObservation | LA_LIBRARY_BENCH / LA_THUMB_BENCH manual-only benchmark | env 基准 |
| 12 | Library | MetadataTests testGPSParsedWhenPresent | CR3 fixture carries no GPS dictionary — nothing to assert | fixture 缺席（无断言物） |
| 13-15 | Sessions | CatalogBenchmarkHarness ×3 | bench 门 | env 基准 |
| 16 | Sessions | Perf07MassApplyTests testExternalVolumeDrainComparisonRecordOnly | 外置卷 record-only | env 基准 |
| 17 | Export | QuickLookPerfProbeTests testQLRenderLatencyGrid | PERF_PROBE 门 | env 探针 |
| 18-20 | App | DepthGoldenTests ×3 | depth package absent / not installed | 模型包缺席 |
| 21 | App | DepthPerfProbeTests testDepthInferenceLatencyProbe | 同族 perf probe | env 探针 |

**判定**：21 = 12 env 探针/基准（全部显式 env 变量门，惯例默认 skip）+
6 模型/资产包缺席（entitlement/下载面）+ 3 fixture 缺席（合成面扛门/无断言
物）。**零静默跳过**——每条均有日志内显式理由 + 源码门。Δ+5 对 M4-3 估 16：
台账已诚实改口径为「估算非实测锚」（GATE-LEDGER §6 注记）；本波批内新增
可考 = #7（testBakeTimeBudget，M5-1-02）；其余为 M4-x 各批环境性累积。
**身份全数合法，非静默跳过，通过。**

## 4. 五门台账审计（`M5-1-GATE-LEDGER.md` 逐行对锚）

- **锚真实性（机检亲跑）**：15 个锚方法 `grep -rln "func <锚>"` 全部命中
  实文件（G1 五锚 SolverGolden + Pooling/Bake/Service 三补腿、G2 两锚、
  G3 三锚、G4 三锚 = 本批文件、G5 三锚）。
- **门值/钉字面抽查**：G2 良态 ≤1e-5 / 全网格 abs ≤4e-3 / max ≤5e-2
  （`ColormatchKernelParityTests` :312/:315/:318 亲读）；G3 矩 ≤1e-3 /
  采样 ≤0.06（SolverGolden :376/:415）；G1 钉死字面
  `2495982924697081349`/`3458577883779271296`（:331/:335）——台账引用逐位
  一致。
- **终值带**：G2 实测带（2.95e-3/3.68e-2）、G3 采样带 1.73e-2、G4
  byte-identical、cbrt 交越机制注记——与 P1/P2 DECISIONS 正本交叉一致
  （亲读对应文件）。
- **亲验性**：G1/G2/G3/G5 = 前波落门 + 本收口轮定向重跑（我方六 bundle
  复跑逐位复核 Layers/IOPParity/IOP 三者，即 G1/G2/G3/G5 锚所在 bundle
  全绿亲证）；G4 = 本批落门（§1 亲跑）。**禁无证据 ✅ 兑现。**
- G3 自然样张目测 = Manual-Only 行挂 M5-4 VALIDATION，台账未代跑（诚实）✓。

## 5. L075 审计（首轮 Library SIGSEGV 归因）

- **叙事与证据交叉**：GATE-LEDGER §6 记录 exit 139 + ModelAssetCatalogTests
  中途 terminated abnormally——**同日 15:23:25 .ips 实证**（已保全
  `evidence/m5-1-03-acceptance/ips-0-worker-library-1523.txt`：SIGSEGV
  `swift_retain` @ `ModelAssetManifest` outlined init copy，位于
  `ModelAssetCatalogTests.testBundledDigestConsistentWithOnDisk`——与叙事
  「Library bundle / ModelAssetCatalogTests 中途」逐点吻合）。
- **归因链（mtime 法证）**：worker 容器（glcjhggt）内 Library/Sessions/
  Export 三 xctest 二进制 mtime 15:30 = 「四 scheme 逐一重建」的重建产物；
  host 二进制亦 15:30（第四 scheme = Lightamer app scheme，linker 无变化
  不改 mtime 自洽）；成功轮日志时序 IOP 15:09 → App 15:42 与「分割重跑，
  前三 bundle 取重建前有效值」叙述吻合。「tuist generate 后旧 xctest 配新
  框架」机理与 .ips 的 retain 垃圾引用计数（ABI 混态特征）相容。
- **缺口（记录）**：SIGSEGV 当轮原始日志被重跑覆盖，磁盘仅存叙事 + 成功轮
  日志（worker 五字段已逐份复核入 §0）；证据强度依赖 .ips + mtime 链，
  可接受。
- **L075 条目本身**：LESSONS L075 在案（改测试后必须 build-for-testing 对应
  scheme；连续两轮逐字节同败 = 陈旧产物签名）；**本验收亲历其适用面扩展**
  ——我方 generate 后全 8 scheme 重建即 L075「generate 后全部 scheme 重建」
  扩展纪律的执行样板（§7 缺陷与此无关：我方产物全同批新鲜）。

## 6. 逐 commit 边界 + 红线机检（亲跑）

| commit | 边界核验 |
|---|---|
| `e13d750` T1 | 11 文件：工具新文件 + EditingToolset **+1 行**（register 一行 + 行尾注释，diff 亲数）+ LightamerApp +13（装配两 install，申报偏离接受 §1）+ 快照族四文件 + 测试 835 行 + xcstrings +1 键 + Project.swift +1 + BUNDLE-MAP +21 行登记 |
| `1f4270e` T2 | 3 文件：ParityTests 258 行 + Project.swift +1 + BUNDLE-MAP +1（ParityTests 3 法补登——T1 注记与 T2 落行分离，合读 = 2 行登记齐） |
| `c99e149` T3 | 仅 GATE-LEDGER 123 行 ✓ |
| `2002779` T4 | GOAL-STATE/LESSONS/TODO/REQUIREMENTS/DECISIONS/SUMMARY 六文件 ✓（commit message 与 plan 提交约定逐字吻合 ×4） |

红线机检（`git diff 3be69ee..HEAD` + grep 亲跑，全过）：

- `LightamerCore`/`LightamerIOP` **零 diff**（空输出）；`.metal` 零 diff
  零新文件；V50Order/Registry/GradeCatalog 零触碰（同上零 diff 推得）。
- `grep -rln '"match_' App/Sources/Lightamer/MCP/Tools/` = **MatchColorToolset
  一文件**（零新工具面）。
- `runModal` App/Sources **0 命中**；`String.LocalizationValue("…\(x)…")`
  禁形唯一命中 = LightamerApp:1805 **注释行**（非代码）。
- 零新 SPM：Project.swift diff 仅测试编列 2 行。
- LumaRescue 零搬：工具 doc/错误文案全英文自写 + 一句 zh 用户指引（与
  apply_params 同缝先例同形），无 LumaRescue 术语/文本痕迹（定性亲读）。
- render gate 消费：源 :301 `withRenderGate` + 专测
  `testMatchColorSerializesOnTheRenderGate`（hold/release 两断言）亲读。
- explicit null 决策源证：`ColormatchModule.swift` :34-37（统计哈希键
  EXPLICIT null / assetRef 键 encodeIfPresent 分域注释）亲读——m4 回灌
  「键集接纳」的机制根基在案。

## 7. 非本批 P1 潜伏缺陷登记（M3-3 Film leg 引用计数竞态）——阻断全 App bundle 复跑

**现象**：验收全套 `--all` 轮 App bundle 宿主 SIGSEGV；L055 重跑两轮同点
复发；`--bundle App FilmPanelTests` **单类隔离复现**（3/3 同点）：

- 崩点 = `FilmPanelTests testShiftSliderLiveWindowCommitsOnce` 开跑后
  （该类前序 4 法全过，含 31.9s 的 undo 法）；
- 签名（.ips ×3 同签名，`evidence/m5-1-03-acceptance/ips-1/3/4-*.txt`）：
  `EXC_BAD_ACCESS` / `_swift_release_dealloc` → `outlined destroy of
  (method: FilmMethodBox.Params, payloads: FilmGPUPayloads?, …)` @
  `PixelPipe.runFilmLeg` ← `runTerminalTails` ← `PipeCoordinator.render*`；
- 第四轮异形（ips-2）：`GUARD_EXC_RECLAIM_ACCOUNTING_FAILURE` @
  renderPreview（内核 reclaim 记账 guard，全机历史首现，当日 swap 6.1G/7.2G
  重压力背景——同族环境性发作）。

**嫌疑机理（读码定位，供修复批起点，非定谳）**：
`PixelPipe.swift:1183-1194` —— `FilmMethodBox.runContext` 为**进程级静态
可变槽**（`FilmGPUPayloads` 载体），film leg `set → await runSub（悬挂点）→
defer clear`；`setFilmLive`/滑杆 live 窗的连续 coordinator 渲染可在 await
窗口交叠，两腿互踩 payload（提前 clear = 悬空引用 / 双重释放）——与 M3-3
「runContext set/clear single-writer window」的**串行假设**冲突；GUI 面渲染
不经 MCP render gate，coordinator 层无跨腿互斥。

**非本批引入（铁证）**：`git diff 3be69ee..HEAD -- LightamerCore
LightamerIOP` = 空；PixelPipe.swift 末次触碰 `1b2b520`（2026-10-10 M4 批）；
FilmPanelTests/Film 域四提交零触碰。worker 当日两轮 App 749/4/0 全绿 +
M3-3/M5-1 历轮全绿 = 时序敏感（概率性；当晚内存压力/调度抖动放大的潜伏
竞态——M3-3 时代即存在）。

**处置建议（挂账，非本批修复）**：立项 `fix(film-leg)` 小批——runContext
改显式传参或 task-local（消静态槽），`FilmPanelTests` 作复现载体回归；
修复前本机全 App bundle 轮受其扰（概率性 crash），`--bundle` 定向轮不受扰
（本批六定向轮即证）。

## 8. 账面小修（本验收批直接修）

1. `M5-1-03-SUMMARY.md` §0 提交账 T3/T4 行 `<回填>` 占位 → 真 SHA
   `c99e149` / `2002779`（占位遗留，账面完整性修复）。
2. 证据保全：五份 .ips + FilmPanelTests 单类崩溃日志尾 →
   `evidence/m5-1-03-acceptance/`（不入 git 正文，随 M4 证据分仓政策）。

## 9. M5-1 phase 终态意见（三 plan 收口）

- **本批可交付**：生效值⑥⑧全兑现——match_color 最小面（五参/批量独立求解/
  attach 双态/确定性披露/零新增面机检）+ G4 byte-identical 亲证 + 五门台账
  亲验闭合 + 翻账（TRACK-01..05 勾选 + TRACK-03 偏差注记 + MCP-09 研究
  项 C 兑现注记）+ 对账链 3477 闭合。批内质量高：申报偏离逐条核实合理、
  DECISIONS 与实作一一对应、快照族 security face 显式申报执行到位。
- **双重验收**：zcode PASS → orchestrator 派 omp 串行复验（config
  `dual_acceptance`；严禁并发）。**omp 复验提示**：GUI 走查面 Manual-Only
  行照旧 M5-4 人工；App bundle 全量轮在本机当前受 §7 缺陷概率性阻断——
  omp 复验如跑测试建议定向 bundle/类，或等 fix(film-leg) 后全套。
- **挂账移交**：①§7 M3-3 Film leg 竞态（P1，建议紧随修复批——GUI 面理论
  可触发，非测试专属）；②M5-1-02 遗留 bake 生产耗时实测（M5-4 人工）；
  ③MCP 多参考 V2 + preset 化（OQ-6 备选 A，需求驱动）；④M4-1 #6 孤儿
  预防照旧（本批已执行）。
- **VALIDATION 输入件**：GATE-LEDGER + 三 ACCEPTANCE（01/02/03）+ 走查
  MANIFEST（`.work/gui-acceptance/m5-1/`）——齐备。

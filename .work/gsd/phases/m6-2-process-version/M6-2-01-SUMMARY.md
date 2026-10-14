# M6-2-01 SUMMARY — per-photo process version（单 plan 全量批）

> Phase = M6-2（REQUIREMENTS M6INT-01）。plan 正本 = 同目录 `M6-2-01-PLAN.md`
> （含 checker E1 回注块 `2363549c`）；裁决正本 = `M6-2-CONTEXT.md` 裁决记录
> （OQ-1..6 全 A，用户回批 2026-10-14）；设计正本 = `RESEARCH-NOTES.md`。
> 基线 = `2363549c` 后 HEAD；全套基线 **3689/24/0**（M6-1-VALIDATION 终验亲证）。
> 状态：**执行批完成（6 commits，未 push）——双重验收待走**（本文件 T6 节 +
> `M6-2-01-ACCEPTANCE.md`）。

## 1. 任务序与提交

| 任务 | 交付 | commit | 测试 |
|---|---|---|---|
| T1 | Core 账本件 `Pipe/RenderProcess.swift`（RenderProcessVersion 值载体 + RenderProcess 枚举账本 + resolving 钳制表 + KD-6 契约头注）+ sidecar v10（schemaVersionCurrent 9→10 + `process: Int?` additive + lenient decode + encode canonical 形 + hash isolation 注记 + 「入册 ≠ 升级」） | `3be89a19` | SidecarV10Tests（LIB）15 法 |
| T2 | 管线读缝 armed 零行为：PixelPipe run-scoped `renderProcess` + `process`/`processComposite` additive 参数 + IOPiece run 常量 stamp（不入 paramsHash）+ 派生 sub-run pipe 继承（DRT tail / film / replay / LCDriver base-layer-terminal 六处；static render throwaway 豁免注记） | `72e6d22d` | RenderProcessSeamTests（LAYERS）8 法 |
| T3 | App 载体与写腿：WorkspaceModel `processVersions` 载体三面（ABSENT 键 = `.legacy` 极性）+ PipeCoordinator load 腿双分支 prime（pristine = mint `.current`）+ `makeSidecarDocument` 唯一写缝（`rawValue == 0 ? nil : carrier`） | `a33a6afd` | ProcessVersionCarrierTests（APP）8 法 |
| T4 | 出生点盖章五面：ImportService AI 副本 + StackMergeService 两 writer（HDR 尾 / landStackProduct 共用）+ SessionBatchApplier **E1 分支条件盖章**（`processStamp` per-arm 提升，禁 `?? .current`）+ MetadataService pristine 臂（既有档臂真 round-trip 零改） | `14c349c1` | additive 5 法（StackMerge 2 真生产腿 / Import 1 / SessionBatch 1 三态 / Metadata 1） |
| T5 | 红线自证 + AGENTS.md M6-2 架构增量节（process 账本 + bump 纪律三层 + M6 iop 调参 AC 模板行）+ GOAL-STATE 续接点 + TODO 行 | `1dbd4217` | —（机检族全绿，§4） |
| T6 | SUMMARY + DECISIONS + ACCEPTANCE（双重验收）+ ROADMAP/REQUIREMENTS 翻账 | 本批 | — |

## 2. golden 四门证据

| 门 | 内容 | 证据 |
|---|---|---|
| **G1 additive 零漂移负测** | ①v9 档（digit-rewound）decode→re-encode 逐字节、process 恒 ABSENT（SidecarV10Tests `testV9FormDocumentDecodesAndReencodesByteExact`）②v10 nil-face writer = v9 shape 仅差 schemaVersion 数字（`testNilProcessFaceDiffersFromV9ShapeOnlyAtTheSchemaVersionDigit`）③process=1 档 round-trip byte-faithful（`testProcessDocumentRoundTripsByteFaithful`）+ hash isolation（`testProcessIsHashIsolated`——同档 ± process historyHash 逐字节同 + driftDetected 双 false）+ App 级 legacy v9 档编辑重存键 ABSENT + 既有键保全（ProcessVersionCarrierTests `testLegacyDocumentReSavesWithTheKeyAbsentAndKeysPreserved`） | LIB 15 法全绿 |
| **G2 冻结语义 golden** | ①冻结门：fork double（test-local ProcessProbeModule，legacy 臂 = blit 直通 / v1 臂 = gain 2.0 可见分叉）legacy 值渲染 = passthrough 基线逐位——**同一 build 已带 v1 臂**仍逐位（跨模拟语义变更不变）②分叉可见门：renderProcess 1 → ≠ 基线（缝非摆设）③缺键 = legacy 臂：sidecar 无键档 decode → `.legacy` → pipe → legacy 臂逐位（sidecar→pipe 值流贯通；LightCraft `settings_saved_before_process_versions_load_as_v1` 同构） | RenderProcessSeamTests 三式全绿 |
| **G3 读缝零行为门** | 真实生产链（terminal trio）renderProcess 0 vs 1 **逐位恒等**（`testRealChainRendersProcessZeroAndOneBitIdentical`）+ 缓存键面零变化（同链同参仅 process 异 → 第二 run **ALL-HIT**，`testCacheKeyFaceUnchangedAcrossProcessValues`）+ IOP/IOPParity 本批零触碰（源码 diff 无 IOP 模块文件）+ Layers/IOP bundle 全绿 | LAYERS 474/4/0 + IOP 686/1/0 |
| **G4 mint/传输面** | 五出生点盖章（T3① coordinator pristine 载体 + T4 四文件）——mint 门：pristine load → 首编辑落盘 `"process": 1`（CarrierTests `testPristineLoadMintsCurrentAndFirstEditWritesIt`）；真实 HDR/Mertens 生产腿产物 `.lra` JSON 含 `"process": 1`（StackMergeServiceTests +2）；AI 副本出生档 = 1（ImportServiceTests +1）；Session pristine 臂 = 1（SessionBatchApplierTests）；Metadata mint = 1（MetadataServiceTests）；**传输零携带**：Copy Adjustments 贴入 legacy 目标重存仍 ABSENT（CarrierTests `testPasteTransportNeverCarriesTheProcess`）+ LightamerPreset 无 process 键（SidecarV10Tests `testLightamerPresetCarriesNoProcessKey`）+ corrupt 档存回无键（`testCorruptValueIsNotRetainedOnRewrite` + CarrierTests ④） | APP 8 + additive 5 全绿 |

## 3. 确定性门（legacy 档跨模拟语义变更逐位不变）

`testLegacyArmStaysOnTheBaselineAcrossTheSimulatedFork`（RenderProcessSeamTests）：
测试本地 fork double **在本 build 内已携带 v1 分叉臂**（模拟「语义变更已上线」的
编译产物），renderProcess = 0（legacy）的渲染与分叉臂存在**之前**的直通基线
**逐位相等**——legacy 值结构性不可达新臂（`piece.renderProcess.rawValue == 0`
永不进入 gain 分支）；这正是 OQ-4 零行为基线 + 未来 bump 冻结承诺的可执行
证明形。G2③ 补 sidecar 缺键档 → `.legacy` → 同一 legacy 臂的贯通证据。

## 4. 红线自证（T5 机检族，基线 `2363549c`）

- `git diff 2363549c..HEAD -- LightamerCore/Sources/Pipe/History/ LightamerCore/Sources/Pipe/PipeCacheKey.swift` **零命中**（HistoryHash/HistoryStack/HistoryItem/PipeCacheKey 四面零 diff——hash 折叠面与 history item 面红线本体）。
- MCP 面（App/Sources/Lightamer/MCP/）零 diff——20 工具封闭集快照族无扰。
- 六格式导出面（Export Core+App）零 diff；`.metal` 全仓零 diff；QuickLook/Spotlight appex、`.lalb` schema（LibrarySchema）、LightamerPreset、FilterPredicate 零触碰。
- `*.xcstrings` 零 diff + 触碰面零 UserDefaults 直读——零新键（OQ-6 范围边界）。
- `Project.swift` diff = 恰 3 行测试登记（dependencies 块零 diff，零新 SPM）。
- App 源码改动 = 恰两 plan 文件（PipeCoordinator +26 / WorkspaceModel +38）。
- **iop 模块文件零触碰**（LightamerIOP/ 无 diff）——「否决演示性 bump」的 diff 面佐证（OQ-4/AC4）。

## 5. bundle 分账与对账链

定向五 bundle（执行末态全量轮）：

| bundle | 数字 | vs 基线 | 新法 |
|---|---|---|---|
| Library | **671/4/0** | 669→671 | +2（SidecarV10Tests 15 为新文件、ImportServiceTests +1、MetadataServiceTests +1——文件内法数见 BUNDLE-MAP；轮间增量对账以 bundle 内总数为准） |
| Layers | **474/4/0** | 466→474 | +8（RenderProcessSeamTests 新文件 8 法） |
| App | **801/4/0** | 793→801 | +8（ProcessVersionCarrierTests 新文件 8 法） |
| IOP | **686/1/0** | 684→686 | +2（StackMergeServiceTests additive） |
| Sessions | **280/4/0** | 279→280 | +1（SessionBatchApplierTests additive） |
| IOPParity | 零触碰 | 460/3/0（基线） | 0 |
| Export | 零触碰（源码面） | 353/4/0（基线） | 0（保险轮见 §7） |

**对账链**：基线 3689 = 3631+53+4+1（M6-1 终验亲证闭合）；本批新文件 31 法
（15+8+8）+ additive 5 法 = **+36** → 全套预期 **3725/24/0**（= 3689+36；AC8
预估窗 3721..3727 内）。定向面合计 671+474+801+686+280+460+353 = **3725**
（Export 取基线值）。批准轮对账留 ACCEPTANCE。

## 6. 偏差与发现（执行期）

1. **resolving 负数构造测试修正**（T1 内，无独立 commit）：初稿 `RenderProcessVersion(rawValue: -5)!` 崩——域门拒负数（KD-1 设计正确），测试改为 legacy（0）→ 最老 case 单式 + 注记「负数在 `init?` 即拒，guard 臂为纵深防御」。**零产线改动**。
2. **ProcessVersionCarrierTests flush 竞态**（T3 内）：预存 fixture 文件使「文件存在」判定失真（写未落地即返回）——`flushUntil` 改为**内容谓词轮询**（重 flush 直到重写面呈现）。零产线改动；legacy 门断言修正一处（decodeParamsHash = writer 面活原子重盖章，既有惯例非漂移）。
3. **RenderProcessSeamTests 7→8 法**（T2 内）：G2①/G2② 初稿合一法，按 plan「8 法」拆分（冻结门 / 分叉可见门各一法）。
4. **既有断言零浮出**：KD-7 预登记的「Session/Metadata mint 臂字节断言」与 byte-face 字面量断言均未出现（checker §2 亲证成立：全仓无 `"schemaVersion" : 9` 字面量断言，符号化引用自动传播）。
5. 无待核标注；无待供件。

## 7. 运行日志指针

定向轮日志 = `/tmp/la-direct-tests-{Library,Layers,App,IOP,Sessions}.log`
（test-direct 惯例路径，收口轮即值）；Export 保险轮 =
`/tmp/m6-2-export-run.log`（本批源码面零触，只作 PixelPipe 签名 additive 的
回归保险）。批准轮 `--all`（须 orchestrator 批准 + 8G 门监视）日志随
ACCEPTANCE 补记。

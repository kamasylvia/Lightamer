# M9-1 ACCEPTANCE — 双路 zcode 独立验收第二路（行为级深审，2026-10-27）

## 结论头

**PASS / 0 error + 0 minor（obs 5 条）**

- 验收对象 = 五 commits `d45f1e2d..97cb3fc2`（refs #11）；AC 源 = REQUIREMENTS
  M9AIM-01..03（`.work/gsd/REQUIREMENTS.md:735-737`）。
- 封存面 17 件零 diff 机检 PASS；定向三域（Layers 522/5/0 + App 1037/6/0 +
  IOPParity GoldenColorTests 6/0/0）与 SUMMARY 终值逐值一致；zh-audit
  --check/--self-test 独立复跑双 PASS（1732/2048 与 SUMMARY 同值）。
- 行为级深审三面（候选数据流 / paste 反转 / σ_px 换算）全 PASS；两项反自取消
  探针均真红（测试非自取消）。
- **独立性声明**：本路未读 `M9-1-ACCEPTANCE.md`（路 1 报告）与 `all-runs/`
  （路 1 证据目录）；结论独立形成。全套 `--all` 复跑属路 1 职责，本路按任务书
  定向三域，全套预期 **4328/33/0** 以路 1 复跑为账。

## 一、AC 独立核对（M9AIM-01..03）

### M9AIM-01 任务蒙版三件 + Sky 留槽 — PASS

| 验收形态 | 核对（file:line 亲验） |
|---|---|
| 三件经 M6-4 基建落位 | Subject = 现役 `generateSubjectMask(invert: false)`（`MaskToolbarView.swift:455`，唯一实现 :742）；Background = 同腿 `invert: true`（:470）；People = person 实例族子集确认（AIMaskTask enum 单源 + unionSelection 服务面）。**无第二 subject 生成实现**（grep 三消费点全走同一函数）。 |
| Background 恒等负测 | `AIMaskTaskPanelTests.testBackgroundRidesSubjectLegWithInvertBit`（:84）——同 plane 两次 commit：`fileName`/`maskHash` 相等（共腿断言）+ `invert` 位承载 + slot 位断言；`testInvertBitRoundTripsThroughLoad`（:124）bake 字节逐位相等 + load 后逐点 `1−x`（accuracy 1e-3）。 |
| Sky 槽 disabled 断言 | `taskIcon(AIMaskTask.sky).disabled(true)` 恒置 + `.help(ai_task_sky_disabled_hint)` tooltip（MaskToolbarView T1 diff）；`testTaskPanelFourEntriesAndSkySlotDisabled`（:60）AX id `ai.mask.task.sky` + disabled 态断言。disable-not-unmount 纪律遵守（不条件卸载）。 |
| People 子集 union | `testPeopleSubsetUnionConsumption`（:167）——.all/.subset/空 subset（typed noSubject）/未知 index（typed invalidInput）四态数学断言。 |

### M9AIM-02 viewport 迭代交互 — PASS

| 验收形态 | 核对 |
|---|---|
| tap-to-segment 点增删再解 | 点增（click/⌥-click）+ **点删**（tap 命中 ≤12px = 删除，`SegmentEditingOverlayHost.pointHitRadius`；`SegmentSession.removeIncluded/removeExcluded` LayerEditingState.swift:812-820）+ 300ms debounce 全量重解（`scheduleCandidateResolve`→`runCandidateResolve`，AIMaskEditing.swift:313-396；`candidateDebounceMs = 300` 单源 :798）。 |
| coverage 显示专属视口通道 | 候选专用合成臂（D1 选定形态②）：`PipeCoordinator.candidateOverlayRequest`（:252）+ render 尾 tint 分支先于 legacy 臂（:2463-2490，`DrawnMaskRasterizer.overlay` + `candidateTint` 固定淡红 SIMD3(1.0, 0.32, 0.42)）。 |
| Commit 后隐藏 | commitRasterMask source==.segment 腿 `releaseCandidate()` + `setCandidateOverlayRequest(nil)`（AIMaskEditing.swift:275-279）；`testCommitClearsCandidatePlaneAndOverlayRequest`（IterativeSessionTests:210）双清除 + commit 恰 1 条 stackSnapshot 断言。既有蒙版编辑 tint 0.85 零 diff（D-M9A-4 区分语义）。 |
| 交互不改参数真相（AI-06） | **深审一全链（§二.1）+ `testCandidateNeverPersistsIntoSidecar`（:187）sidecar 序列化零 candidate 键 + `testCandidateSessionWritesZeroHistory`（SessionCommands:195）候选态零 history。** |

### M9AIM-03 算子与会话 — PASS

| 验收形态 | 核对 |
|---|---|
| Feather golden | `AIMaskFeatherPxTests.testSigmaPxFoldIsExactAndInverts`（px→σ==px 恒等 + 反向）+ `testPxClampBoundaries`（0/50/越界 + 小平面 clamp 域）+ `testNegativeLogitGainLegUnchanged`（负腿超集回归）。 |
| Expand | `AIMaskMorphologyTests` 五面全在册（:79 BFS 八角距离 ground truth / :111 vImage vs host 随机平面 / :146 erode-dilate 反演 / :169 |px|=0 恒等 / :186 量化单调交换律）；bake 序 expand→feather→quantize 由 `testBakeAppliesExpandBeforeFeather`（FeatherPxTests:74）钉死。**GPU→CPU 合法偏离 D2 申报在册**（REQUIREMENTS「GPU 算子」字样偏离，零新 kernel 红线优先）。 |
| 会话三命令 | open 三源显式 re-entry（`LayerEditingState.swift:326` 三源判据 + `AIMaskSessionCommandsTests.testReentryRoutesTheThreeSources` 含 depth/skin/手绘负测）；commit 恰 1 条维持；cancel = Done·Escape 收敛（`cancelSession()` 零 bake 零 history + `testCancelDiscardsCandidateWithZeroBake`）。 |
| paste 排除负测 | 正负测 + 混合面三测全在册（§二.2）。 |

## 二、行为级深审三面

### 1. 候选合成臂数据流（AI-06：候选不进参数真相）— PASS

全链逐环读码（每环亲验）：

1. **迭代解**：`AIMaskEditing.runCandidateResolve`（AIMaskEditing.swift:336-396）
   ——`AIMaskService.segmentSubject` 全量重解 → 输出 **唯一写点**
   `session.candidatePlane = upsampled`（:387，SegmentSession UI 态，
   LayerEditingState.swift:808）→ `AIMaskResample.texture` 上载 →
   `coordinator.setCandidateOverlayRequest((texture, 0.6))`（:390，display 面）。
2. **视口 tint**：`PipeCoordinator` render 尾候选分支（:2463-2490）——
   `DrawnMaskRasterizer.overlay` 直染候选纹理，**不触 layer stack、不走 spec
   组装腿**（判据与 plan 一致：无 layer.mask spec 的 session 候选对
   `applyMaskOverlayIfRequested` 结构性不适用）；newest-wins 复用 generation
   gate。
3. **AI-06 判定（grep 全消费点）**：`candidatePlane` 全仓命中 = 生产 1（:387）
   + 定义 1 + 清除 1（releaseCandidate :846）+ confirm bake 消费 1
   （OverlayHost:422）+ 测试；`candidateOverlayRequest` 命中 = PipeCoordinator
   定义/合成 + 三处清除断言 + AIMaskEditing 设/清。**history/params/sidecar/
   UserDefaults 写入点零命中**；sidecar 目录 grep `candidatePlane/candidateState/
   expandPx/featherPx` 零命中（RasterMaskStore 的 expandPx 为 bake 运行时函数
   参数默认 0，非 schema 字段）。唯一进参数真相的路径 = confirm →
   commitRasterMask → bake（恰 1 条 stackSnapshot，像素即真相——设计即如此）。
4. **清除四路**：commit（commitRasterMask :275-279）/ cancel（cancelSession）/
   `recordSeed` 重置 / `releaseLivePatchState`（identity 换图防陈旧 bake）——
   全部 `releaseCandidate()`。

### 2. paste 反转回归面（AdjustmentTransfer 全消费面枚举）— PASS

- **buildPayload 两处调用 = 全部消费面**：①App UI
  `AdjustmentTransferModel.pastePayload()`（AdjustmentTransfer.swift:420）→
  Paste 按钮 → `versions.pasteChain`；②MCP `EditingToolset.pasteAdjustmentsBody`
  （EditingToolset.swift:1024）——**共享同一 Catalog，排除自动生效两路**
  （D6 申报吻合）。
- **排除逻辑**（AdjustmentTransfer.swift:215-227）：唯一谓词
  `AIMaskSource.source(ofFileName:) != nil`（本批新增消费恰两处 = re-entry
  路由 LayerEditingState:326 + paste 排除 :221，git blame 亲验；另 3 处命中
  = lumen-culling 批 c374889d 存量先在）。AI raster 剥除 → `hasAnyPayload`
  分流：有 drawn/parametric 保留 mask（contentRevision 置 nil = KD-3 epoch
  reset 维持）/ 剥空整 mask 置 nil。
- **手绘不排负测**：`testPasteKeepsHandDrawnRaster`（:143）——无前缀 raster
  随 payload 原样 + epoch reset 仍适用；`testPasteStripsAIRasterButKeeps
  OtherPayloads`（:163）混合面：AI raster 掉、drawn 存、mask 不空。
- **toast 面**：`AdjustmentTransferView.swift:289-292` count toast（
  `transfer_ai_masks_excluded %lld` 静态键 + String(format:)，动态键禁形遵守）。
- **存量翻转**：`AIMaskPatchFlowTests.testPersonMenuRoutingSourceFace` 翻转
  （D6 清单）；`AdjustmentTransferTests` 零翻转（其断言面不涉 mask 随行——
  本路 App 全量 1037/6/0 间接复核其绿）。

### 3. Feather px 域换算（σ_px 单源 ≥2500px 恒等亲验）— PASS

`AIMaskFeather.sigmaFromPx`（AIMaskFeather.swift:85-89）数学亲验：

```
percent = px × 100 / (0.02 × longEdge)
σ       = |percent|/100 × 0.02 × longEdge = px   ← 折回恒等（代数精确）
```

- **恒等条件**：percent ≤ 100 ⇔ longEdge ≥ px × 50；px 全域 [0,50] 需
  longEdge ≥ 2500——**「longEdge ≥ 2500px 恒等」声明亲验成立**（px=50 时
  percent=100 σ=50=px 精确；较小 px 所需 longEdge 更小）。
- 低于 2500：`sigma` 内部 ±100 clamp 封顶 σ = 2% longEdge < px——注释诚实
  申报为「percent 腿既有红线行为，小合成平面专属」。
- `pxFromPercent` = σ(percent) 同式（正域恒等往返）；percent ≤ 0 → 0（负腿
  logit-gain 无 px 表达，面板归 0——超集保留）。
- **单源性**：slider 面（MaskToolbarView:314-339）直接读写
  `session.featherPx`（UI 态），零本地换算;`resolveFeather`（AIMaskEditing:
  409-424）px 优先 / percent 回落超集。D-H1：onEditingChanged 空 body 注释
  明示 session-only 零 history 写入，bake 消费 settled 值。
- 反向印证 = 探针 B（§三）。

## 三、反自取消补充探针（主树掏空还原法）

| 探针 | 注入 | 结果 |
|---|---|---|
| **A paste 排除掏空** | `AdjustmentTransfer.swift:215` 谓词 `!= nil` → `false`（AI 件不再排除） | `AIMaskSessionCommandsTests` **5/0/2 真红**——`testPasteExcludesAIBakedRasterAndListsNames`（skip list 空 `[] ≠ [期望]` + AI mask 未剥）+ `testPasteStripsAIRasterButKeepsOtherPayloads`（count 0≠1 + raster 未剥）；手绘不排负测保持绿（掏空后仍不排除 = 语义自洽）。**排除断言非自取消。** |
| **B σ_px 换算改错** | `sigmaFromPx` 返回值 `+0.5` 常数偏移 | `AIMaskFeatherPxTests` **4/0/2 真红**——`testSigmaPxFoldIsExactAndInverts`（25.5≠25.0 / 50.5≠50.0 恒等破坏）+ `testPxClampBoundaries`（50.499≠50.0 + 小平面 clamp 域断言双红）。**换算 golden 非自取消。** |

两项注入后各自 `git` 还原 + 干净重建（BUILD_EXIT=0）+ 三域复绿。构建全程
guard 前置（G PASS heavy=0）、nohup 串行、GUI 实例起跑前 parentage 核清零。

## 四、定向三域测试（本路口径）

| 域 | 结果 | SUMMARY 对账 |
|---|---|---|
| Layers（全 bundle） | **522/5/0**（1183MB / 442s） | 同值 ✓ |
| App（全 bundle） | **1037/6/0**（2832MB / 607s） | 同值 ✓ |
| IOPParity（GoldenColorTests 类，开工基线核同款） | **6/0/0**（3619MB / 49s） | 同值 ✓ |

全套 `--all` 预期 4328/33/0 属路 1 复跑账（任务书明示本路定向）；MEMFAIL 零
触发（峰值 ≪ 8G 门）。

## 五、走查配方对账（MANIFEST ↔ SUMMARY）

MANIFEST 六项（`.work/gui-acceptance/m9-1/MANIFEST.md`）↔ SUMMARY「走查与
验收指针」节六项**逐项映射吻合**：①任务面板 Sky disabled ②逐点即解候选消长
③Path 采样计数 ④Feather/Expand slider px 域 ⑤paste 排除 toast ⑥cancel
丢弃。AXPress 纪律 + M9AIM-02 承载映射三层链（状态机级单测 / 走查②③ /
omp computer-use）登记在册（m-3 兑现）。顺路登记节旧 AX id
（`ai.mask.subject` 族）退役说明与产线/测试零残留 grep 吻合；新 id
`ai.mask.task.*` 族四枚可达。

## 六、红线复核（独立机检汇总）

- 封存面 17 件 `git diff d45f1e2d~1..97cb3fc2` 零命中（PixelPipe 含
  TerminalTailPolicy/DrtTailAssembly 内嵌定义一并覆盖；ExportFormatSpec 于
  ExportRecipe.swift 内覆盖）。
- 零新 SPM（Accelerate 系统框架）；零新 `.metal`；零新模型。
- sidecar schema v11 零 bump；UserDefaults 零新键（候选/featherPx/expandPx
  全 UI 态）。
- xcstrings：新增 10 键与 SUMMARY 键族清单逐键吻合；死键防御
  （`mask_overlay_style_candidate`/`ai_path_tool`）零在册；删除恰三键
  （ai_mask_subject 族 = D12 申报配平删除，非历史键触碰）；zh-audit 双 PASS
  独立复跑。
- V50Order 零触碰；`.candidate` case 恰一处声明 + picker 消费
  `userSelectableCases`（MaskToolbarView:180 恰一处）+ 白名单断言三项机检全过。
- `scribbleNotSupported` 硬清零面全仓零命中（m-5 达成；`case .path: return
  "scribble"` LayerEditingState:53 = SF Symbol 图标名，假阳性非 seed case）。
- 「must never seed」措辞零残留（m-4 注释改写在案）。
- GPL 零复制（形态学核序/σ 式/采样常量/色值 = 公开数学与数值参数，出处注记
  在案）。

## 七、发现（B/M/m/obs）

**B：0。M：0。m：0。**

- **obs-1**：`Lut3dKernels.metal` 在 HEAD 已不存在（历史批次退役），封存
  清单 17 件的该条目零 diff 平凡成立——清单与 HEAD 现实的漂移记录（不影响
  本批判定）。
- **obs-2**：PLAN T4 验收 grep「`source(ofFileName:)` 消费点恰两处」全仓实
  际 5 处——本批新增恰 2 处（re-entry + paste，blame 亲验），另 3 处
  （MaskRefineCoordinator ×2 / MaskToolbarView:266）为 lumen-culling 批
  （c374889d， 2026-10-24）存量先在。判据语义按「本批新增面」成立；plan
  措辞未区分存量/新增，记录性歧义。
- **obs-3**：`AdjustmentTransferPayload.isEmpty` 现含 `excludedAIMasks`
  （AdjustmentTransfer.swift:126-128）——「只勾选带 AI mask 的层、无其它可
  粘贴件」时 payload 非 nil、Paste 可点，toast 告知排除后 pasteChain 应用
  空链 records + 剥空层结构。设计取舍（toast 面可达性优先），无数据破坏；
  版本树可能出现空内容「Pasted adjustments」条目，走查轮可顺带观察。
- **obs-4**：`runCandidateResolve` 的 identity guard 仅在 `patchImageURL
  != nil` 时跑（D13 自申报的 nil-stamp 语义豁免）——程序化
  `setSegmentActive(false)`（非 host 路径）不清 coordinator 候选 request 的
  残留缺口真实存在；host 路径 onDisappear + cancelSession 双路覆盖主路径，
  现役程序化调用点无候选窗口。D13 预登记在案，走查轮观察项（独立复核确认
  其风险评估成立）。
- **obs-5**：vImage bias 核数学细节——dilate = MAX(src−ε)−ε = MAX−2ε/步
  （非对称），erode = MIN(src−ε)+ε = 精确；≤50 步累积 1e-7 ≪ uint16 LSB
  1.5e-5（D8「±ε 往返」论证与实际 −2ε 一致性在量化域结论不变）。非缺陷，
  数学记录。

## 八、方法附注

- 探针 = 主树注入→定向类跑→`git`/备份还原→干净重建→复绿；每步构建
  BUILD_EXIT=0 留档（/tmp/m91-2nd-*.log）。
- 独立 DerivedData 未另建（串行单容器增量，机器级单重活制遵守；guard 每
  重活轮前置）。
- 本报告为第二路独立结论；omp computer-use 二次验收由 orchestrator 排程
  （串行独占）。

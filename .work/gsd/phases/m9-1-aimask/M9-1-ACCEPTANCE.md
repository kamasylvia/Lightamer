# M9-1 ACCEPTANCE — AI Mask 工具 parity 双路 zcode 独立验收（第一路）

> 验收日 2026-10-27，验收 HEAD `97cb3fc2`（五 commits `d45f1e2d`/`228b090a`/
> `6d7534a9`/`0e495b6c`/`97cb3fc2`，refs #11）。验收正本 = M9-1-SUMMARY.md +
> M9-1-DECISIONS.md（D1..D15）+ PLAN v2；AC 源 = REQUIREMENTS M9AIM-01..03。
> 全程独立实测：diff 逐文件 / grep 机检 / zh-audit 亲跑 / 全套 `--all` 亲跑 /
> 行为级反自取消双探针（主树掏空还原法 + 产物重建）。

## 结论头

**PASS / 0 error + 1 minor**（全套 4328/33/0 逐值命中；反自取消双探针真红；
封存面 17 件零 diff；ΔN +33 如实对账越带 D15 申报在案）。唯一 minor =
AdjustmentTransfer 注释虚构谓词名 `isAIMaskSpec`（行为正确，注释缺陷）。

## 一、AC 逐条对账（M9AIM-01/02/03）

### M9AIM-01（任务蒙版三件 + Sky 槽）— 兑现

| 验收形态 | 实证 |
|---|---|
| 三件经 M6-4 分割基建落位 | `MaskToolbarView.swift` 任务面板区：Subject = `generateSubjectMask(invert: false)` 现役腿复用；Background = 同腿 `invert: true`（per-ref `RasterMaskRef.invert` 位承载 1−x）；People = `detectPersonInstances` → InstancePicker 子集确认 → `unionSelection(.subset)` → `.person` commit。`AIMaskTask` enum 单源（identifier/isEnabled/systemImage）；grep `generateSubjectMask` 无第二 subject 实现 |
| Background 恒等负测 | `AIMaskTaskPanelTests.testBackgroundRidesSubjectLegWithInvertBit`（同 plane 同 fileName 同 maskHash，仅 invert 位异）+ `testInvertBitRoundTripsThroughLoad`（bake 字节逐位相等 + load 后逐点 1−x） |
| Sky 槽 disabled 断言 | `testTaskPanelFourEntriesAndSkySlotDisabled`（enum 层 isEnabled false + AX id stem）+ 产线 `Button{}.disabled(true)` 恒置 + `.help` tooltip（`ai_task_sky_disabled_hint`）——disable-not-unmount，零活代码路径（action 空） |
| People 子集 union | `testPeopleSubsetUnionConsumption`（max-fold 数学 + 空 subset typed noSubject + 越界 typed invalidInput） |

### M9AIM-02（tap-to-segment + coverage 通道）— 兑现

| 验收形态 | 实证 |
|---|---|
| 逐点即解（点增删再解） | `SegmentSession.candidatePlane/CandidateState/candidateDebounceMs=300`（`LayerEditingState.swift`）+ `AIMaskEditing.scheduleCandidateResolve`（注入时钟缝）/`runCandidateResolve`（全量重解 + 保留旧候选 + typed 失败 toast）；点删 = `removeIncluded/removeExcluded` + OverlayHost 12px 命中删除（`SegmentEditingOverlayHost.deletePoint`）；单测 `testPointDeleteReturnsBudgetHeadroom` / `testCandidateDebounceMergesBurstIntoSingleSolve`（五调度一解）/ `testFailedResolveKeepsOldCandidate` |
| coverage 专属视口通道（淡红 tint） | **候选专用合成臂（M-2 形态②，D1）**：`PipeCoordinator.candidateOverlayRequest` 独立变体 + `setCandidateOverlayRequest` setter + render 尾 candidate 分支先于 legacy `maskOverlayRequest`（旁路 spec 组装，直 `DrawnMaskRasterizer.overlay` + `MaskOverlayStyle.candidateTint`〔1.0,0.32,0.42〕）；newest-wins = generation gate 复用；legacy switch `.candidate` = 防御降级分支。**Commit 后隐藏** = `commitRasterMask` 内 `releaseCandidate() + setCandidateOverlayRequest(nil)`（D-M9A-4），单测 `testCommitClearsCandidatePlaneAndOverlayRequest`（request 双清 + 恰 1 history） |
| 交互不改参数真相（AI-06） | `testCandidateNeverPersistsIntoSidecar`（sidecar JSON 零 candidate 键）+ `testCandidateSessionWritesZeroHistory`（解算全程零 history）+ `testCandidateStyleIsDisplayOnlyAndWhitelistedOut`（`userSelectableCases` 不含 `.candidate` + picker 消费白名单〔`MaskToolbarView.swift` ForEach〕+ xcstrings `mask_overlay_style_candidate` 零在册三项机检全过） |
| 承载映射（m-3 三层链） | MANIFEST §承载映射显式登记：①状态机级单测（上述八法）②走查②③ AXPress ③omp computer-use——SUMMARY 对账行同源在册 |

### M9AIM-03（Feather/Expand + 会话语义）— 兑现（GPU→CPU 偏离 D2 申报在案）

| 验收形态 | 实证 |
|---|---|
| Feather/Expand golden（对称半径/边界行为） | `AIMaskMorphologyTests` 五面：①八角 BFS 真值三方对拍（vImage==host==定义级 BFS，中心/角落/顶边 × n1..4）②随机面 vImage vs host（5 尺寸 × ±1..4，量化域逐值）③erode-dilate 对偶（clamp-replicate 边界合同）④px=0 恒等 ⑤量化单调交换律（R8）；`AIMaskFeatherPxTests` 四面：σ_px↔percent 双向 + clamp 边界 + **bake 序 expand→feather→quantize**（非对称随机面+平台，合成序==手动链逐字节 + 反序确实不同——D9 教训落地）+ 负腿 logit-gain 超集保留回归。CPU vImage = D-M9A-9/D2 显式偏离 REQUIREMENTS「GPU 算子」字样（零新 kernel 红线优先），GPU seam 注记在文件头 |
| 会话三命令端到端 | open = `armSegmentSession` 现役 + re-entry 三源扩源（`.segment/.subject/.person`，`testReentryRoutesTheThreeSources` 正负测；depth/skin/手绘不路由；m-4 注释改写在册，grep `must never seed` 零残留）；commit = 恰 1 stackSnapshot 维持（`testCommitClears…` history+1 断言）；cancel = Done/Escape 收敛（`cancelSession` + `.keyboardShortcut(.cancelAction)`，`testCancelDiscardsCandidateWithZeroBake` 零 bake 零 history） |
| paste 排除负测 | **语义反转（D6/D-M9A-8）**：`AdjustmentTransferCatalog.buildPayload` AI raster 不入 payload（判据 `AIMaskSource.source(ofFileName:) != nil`，本批新增消费点恰两处 = re-entry 路由 + paste 排除）；保守臂手绘不排（`testPasteKeepsHandDrawnRaster`）；混合 mask 剥 raster 留 drawn（`testPasteStripsAIRasterButKeepsOtherPayloads`）；剥空整 mask 置 nil；名单 toast `transfer_ai_masks_excluded %lld`（`AdjustmentTransferView` paste 按钮） |

## 二、diff 审（371a3d95..97cb3fc2，批真实边界）

- **产品面 15 文件**与 plan files_modified 吻合：App 侧 AI Mask 族七件（AIMaskEditing/
  AdjustmentTransfer/LayerEditingState/PipeCoordinator/MaskToolbarView/
  SegmentEditingOverlayHost/AdjustmentTransferView）+ Core 侧（AIMaskFeather +31 /
  AIMaskGeometry 新建 / AIMaskMorphology 新建 / AIMaskService −2 / AIMaskTypes /
  RasterMaskStore）+ Project.swift +6 + xcstrings。任务书基准 4ad9887b 的 diff 中
  `.gitignore`/`pipe_frame.npy` 属 CC-ARW 批（371a3d95/13d2c579），非本批面。
- **封存面 17 件零 diff 机检过**（name-only grep 零命中；PixelPipe 零触碰）。
- **零新 .metal / 零新 SPM（Accelerate 系统框架）/ 零新模型 / schema v11 零 bump /
  UserDefaults 零新键**（featherPx/expandPx/candidatePlane/candidateState 全 UI 态，
  AI-06 负测在册）。
- **.scribble 全撤核过**：`scribbleNotSupported` 全仓零命中；`.scribble` 残留 9 处
  = SF Symbol 图标名（`case .path: return "scribble"`）+ 历史叙述注释（"retired
  with this seam's activation"），零活代码路径。
- **存量改写三处与 D4/D6 一致**：AIMaskSemanticTests scribble 拒绝负测 → Path 采样
  激活正测（原位 1 法）；AIMaskPatchFlowTests person 路由断言翻转（原位 1 法，
  三源正测 + 负测）；LayerUIWiringTests scribble 段删除（法数不变）。
- **xcstrings**：+10 键（ai_task_* 5 + expand 2 + candidate 2 + transfer 1，zh/en
  双语）+ 三死键配平删除（ai_mask_subject 族，D12）；`mask_overlay_style_candidate`
  /`ai_path_tool` 零在册（死键防御 + D11）。
- **BUNDLE-MAP 六行 + Project.swift 六行数组插入**齐；zh-audit 亲跑 `--check` PASS
  （1732 source / 2048 catalog）+ `--self-test` PASS（V17 golden 八例）——与 SUMMARY
  值逐字一致。

## 三、全套独立复跑

```
BUNDLE|IOP|788/1/0|peakRSS=6271MB|990s
BUNDLE|IOPParity|529/9/0|peakRSS=5753MB|1582s
BUNDLE|Layers|522/5/0|peakRSS=1181MB|455s
BUNDLE|Library|782/4/0|peakRSS=747MB|174s
BUNDLE|Sessions|285/4/0|peakRSS=1210MB|81s
BUNDLE|Export|385/4/0|peakRSS=4946MB|204s
BUNDLE|App|1037/6/0|peakRSS=2832MB|598s
TOTAL|4328/33/0|4084s
```

**TOTAL = 4328/33/0 逐值命中预期**（基线 4295/33/0 + 33 精确）；七 bundle 分值与
SUMMARY 逐值一致；skip 33 形态不变（真模型门/性能探针门）；MEMFAIL 零触发，峰值
IOP 6271MB < 8G 门；`machine-guard --monitor 21600` 伴跑零 kill 事件。全套纪律
（guard --wait 前置 + 起跑前 ps 清零 + nohup disown）全程执行。ΔN +33 越 plan 带
+20..29 上限 4、越 charter 带 +20..28 上限 5——越带全落 T3（14 vs 6..9），D15
申报构成剖析在案（Iterative 八法与 AI-06/交互断言面一一对应；PathSampling 六法
数学面独立），六文件法数与 BUNDLE-MAP 登记逐行相符（5+4+6+5+8+5=33）。

## 四、反自取消双探针（主树掏空还原法，产物重建）

- **探针 A（vImage 形态学核扰动）**：`AIMaskMorphology.swift` vImage 腿 kernel
  交替序翻转（奇步 square↔cross 互换，host/BFS 不动）→ build-for-testing →
  `--bundle Layers 'AIMaskMorphologyTests'` = **5/0/2 真红**——
  `testSinglePixelDilationMatchesCadenceGroundTruth`（八角 BFS 真值对拍）+
  `testVImageMatchesHostOnRandomPlanes`（逐字节对拍）两法红。cadence 红线由
  独立真值三方对拍真承载，非摆设断言。
- **探针 B（候选合成臂删除）**：`PipeCoordinator.setCandidateOverlayRequest`
  掏空为 no-op（request 丢弃）→ build → `--bundle App 'AIMaskIterativeSessionTests'`
  = **8/0/1 真红**——`testCommitClearsCandidatePlaneAndOverlayRequest` 红
  （候选通道断言真消费合成臂缝）。
- **还原验证**：双探针源还原（`git diff` 空）+ build-for-testing 重建干净产物 →
  Morphology **5/0/0** + Iterative **8/0/0** 双绿——产物态恢复，不留扰动残留。

## 五、走查证据抽查（读文件面，GUI 实机归 omp 轮）

`MANIFEST.md` 在库，六项（①任务面板 Sky disabled ②逐点即解候选消长 ③Path 采样
计数 ④Feather/Expand px 域 ⑤paste 排除 toast ⑥cancel 丢弃）与 SUMMARY §走查指针
逐项对账吻合；AXPress 纪律（R6 obs-3 教训）+ M9AIM-02 三层链承载映射显式登记 +
§12.3 验收口径（AI-06 语义不照抄上游）+ 旧 AX id 退役改写提示在册。走查样例
清单（截图证据 `<item>.png`）待 omp computer-use 轮落。

## 六、偏差与观察

- **m-1（minor，注释缺陷）**：`AdjustmentTransfer.swift:192` 注释「THE ONE
  PREDICATE: `isAIMaskSpec`」引用了**不存在的符号**——仓内无 `isAIMaskSpec`
  定义，实际判据 = `AIMaskSource.source(ofFileName:) != nil`（:221）。行为与
  「判据单源」语义正确（消费点恰两处属实），仅注释虚构谓词名。建议后续批顺手
  改注释为实际符号名。
- **obs-1**：SUMMARY/plan 措辞「随机平面 vImage vs host 逐字节」，实测断言 =
  float 域 accuracy 1e-6 + uint16 量化域逐值——与 D8 论证域（ε 累积 1e-7 ≪
  量化步 1.5e-5，量化域精确）自洽，非缺陷，如实记录措辞精度。
- **obs-2**：Sky disabled 断言 = 枚举层（isEnabled）+ 产线 `.disabled(true)` 恒置；
  完整 AX 树 disabled 态由走查①承载——与 plan 分层（单测面 + 走查面）一致。
- **obs-3**：`MaskOverlayStyle.labelKey` 的 `.candidate` case 返回
  `"mask_overlay_style_candidate"` 字符串（键零在册）——白名单 + 测试断言保证
  其零渲染；若未来出现非 picker 消费面直接以 labelKey 渲染 allCases 会出裸键
  （plan M-1 已知限制：无编译期保障，收口靠三项机检）。
- **obs-4**：探针 B 仅 1/8 法红——render 尾候选合成分支（tint 实际渲染输出）
  无单测断言（displayTexture 染色），由走查②承载。与 MANIFEST 三层链分工
  一致，非缺陷；记录供走查轮重点覆盖。
- **obs-5**：xcstrings 实际形态 = 尾块插入 10 新键 + 中部三死键配平删除，非
  字面「纯尾插」——D12 已申报配平删除（本批自产死键），非触碰历史键。

## 七、判定

PASS。五 commits 战果与终报逐项相符（不轻信前提下的逐项实测全中）；AC 三条
全兑现；全套逐值命中；双探针证 golden 门与候选通道测试真红承载；红线
（封存面/零 kernel/AI-06/V50Order/D-H1/键族）机检全过。m-1 注释缺陷不阻断
（后续批顺手修）。建议按 C 档停汇报用户后进 omp 二次验收（computer-use 串行）。

# R7 ACCEPTANCE（R7 修复批综合验收；issue #15）

**PASS / 0 error + 0 major + 1 minor + 3 obs**

- 验收对象：`838314b2`（T1）/ `8211b86f`（T2）/ `edd66755`（T3）/ `082178f2`（T4）/
  `236cd50b`（T5 收口），基线 `f783f1c3`。HEAD 验收时 = `236cd50b`。
- 全套独立复跑 **4435/34/0**（七 bundle 逐值 = executor 终报，总时长 4084s vs
  executor 4081s，方差 3s；峰值 RSS IOP 6419MB < 8192 运行门，零 MEMFAIL）。
  日志 = `all-runs/r7-acc-all.log`（前六 bundle 一轮 + App bundle 补跑一轮，
  见 §八）。
- 反自取消双探针**双真红 + 还原双绿**（§四）。
- T3 两裁决（raster seed 按设计 / AX 合成伪影）与 T4 paste 活引用裁决**复核均
  成立**（§五、§六）。

## 一、逐 T 独立核对（file:line）

### T1（`838314b2`）— 端点对称臂 + dragMoved 门 ✓

- `App/Sources/Lightamer/UI/Overlay/UprightGuidesOverlay.swift:150-163`：`release()`
  端点臂 = `endpointDragLanded = dragging != nil && dragMoved`（151），draw 臂
  优先（154-161，press 时 endpointHit/pending 互斥置位），零 tick grab 落
  `false`。`dragMoved` 三态：press 复位（97）/ dragTick 端点分支置位（135，
  pending 分支不置——draw 臂由零长度门守）/ release+leave 清除（153、209）。
- 幻影 item 防线读验：视图 `onEnded`（275-285）`changed = m.release()` →
  `if changed { onCommit }`（282-284）→ host `commitLinkedSnapshots`（395）落
  恰 1 item。零 tick 时 changed == false → 不提交。比 M9-3 N-1 原建议
  （`dragging != nil` 即提交，`M9-3-ACCEPTANCE-OMP.md:118`）更严——1-2px
  press 即 release 场景不落 params 全同的幻影 item，与零长度画线「不是导线」
  既有面同构。
- DECISIONS §1「Equatable 合成无消费面」亲核：全仓唯一 `UprightGuidesModel`
  等值比较 = `dragModel == nil`（nil 比较，251 行）；模型同型 `==` 零消费。
- 回归 `testEndpointDragReleaseCommitsThroughTheHostSeam`
  （`Tests/LightamerTests/UprightGuidesInteractionTests.swift:345-385`）：draw /
  端点 / 零 tick 三 release 契约 + host 缝（setParams + recordChange 落恰 1
  item 携 0.85 端点）。类法数 8→9 ✓。

### T2（`8211b86f`）— swapsXY 桥 I/O 转置 + 镜像抵消 ✓（数学独立复核）

- 产品面（`App/Sources/Lightamer/State/CropToolRotation.swift`）：`flip` 参数
  缺省 nil（164，旧调用零破坏）；`.auto` → `.none`（173-175）与
  `FlipModule.commitParams`（`FlipModule.swift:200-202`）语义一致；进桥转置
  （204-208）/ 出桥转置（242-246）。
- **镜像半边代数抵消证明独立复核成立**（DECISIONS §2 的数学声明，逐环验）：
  1. SWAP_XY 四位型 = transpose/rotCW90/rotCCW90/transverse
     （`FlipModule.swift:75-81`，bit2），forward = 先 flip 轴再 swap
     （`outputXY` :119-127）→ `F = T∘M`（M ∈ {Mv, Mh, Mhv} 帧心镜像，M² = id）。
  2. `withAngle`（`CropFitAngle.swift:229-278`）四路径对帧心镜像等变：
     旋转关于帧心镜像共轭不变（M∘R∘M = R，旋转为线性映射 R(−d) = −R(d)）→
     `isWithinImage`/`fitScaleAboutCentre` 门对称；largest = `fitRect` 居中
     （`fromCenter(w/2, h/2)`）自镜像；shrink 绕自身中心镜像协变；fallback 输出
     居中自镜像。`isLargest` 门 aspect 镜像不变 + largest 居中 → 对称。
  3. 合成：实现落盘 = T(q̃′)，完整 F-往返落盘 = T∘M∘M(q̃′) = T(q̃′)——逐值相同。
  4. 桥（`RotatedFrameBridge`）为各轴独立居中仿射，镜像可穿过；`frameSize` 是
     upright 输入平面（flip 之前），不受位型影响。
  注记（措辞级）：「落盘 record 逐字节相同」在浮点严格意义下指几何恒等——
  镜像臂并不存在于代码，反事实路径含 1−x 浮点项，理论偏差 ≤1ulp 级、经
  Float 化与 clamp 实测消失；回归以 1e-6 闭式钉死，声明实质成立。
- 三调用点全接线：`EditorAreaView.swift:165`（tool strip rotate 手柄）/
  `:193`（auto-straighten）/ `:607`（crop 工具内 rotate 手柄），flipRecord
  提取点 = `:484`。`ninetyDegreeSnapshot`（:177）不涉 crop 重拟，90° 步窗随
  帧转置为自然语义（M9-3 验收已过），不属本修。
- 回归（`CropToolRotationTests.swift:354-468`）：转置闭式四边 1e-6 + 反真空
  （未转置旧答案可证漂移，401/403 行在探针②实测漂移 4-5%）+ 全幅面
  （unit 转置不变、largest@10° 同桥）+ 镜像-only（flipH ≡ nil-flip 整
  record Equatable）。类法数 7→9 ✓。

### T3（`edd66755`）— 两裁决 = 审计 + 回归，产品零 diff ✓（§五专项）

- commit 只动 `DrtPanelModelTests.swift`（+65 行），产品面零 diff ✓。
- 读序亲核：`DrtPanelModel.swift:68-77` record = liveRecord →
  `history.effectiveDrtRecord()` → `workspace.drtRecord(for:)` → `DrtRecord()`，
  无面板局部默认 ✓。
- 回归双向钉死：`testPeakInitialValueEqualsTheRecordSemanticValue`（pristine→100
  / seed 400→400 / 清键→100）+ `testMethodSwitchReflowsSectionsThroughTheReadChain`
  （setMethod 两方向 sections 重排，实例面 = ForEach 消费投影）。类法数 11→13 ✓。

### T4（`082178f2`）— 卫生包五小件 ✓

1. **①paste 清扫**：`RasterMaskStore.removeAssetIfUnreferenced`
   （`RasterMaskStore.swift:146-175`）引用核对 = 全 chains 全 items 全 layers
   的 `mask.raster?.fileName`；消费点 `AdjustmentTransferView.swift:301-317`
   （`case .currentImage` + `loadedImageURL` 门，excludedAIMasks 逐名清扫）。
   回归三面：referenced-kept / unreferenced-reclaimed / missing-silent
   （`AdjustmentTransferTests.swift:542` 起）。**paste 活引用裁决复核成立**（§六）。
2. **②谓词名勘正**：`AdjustmentTransfer.swift:192-195` `isAIMaskSpec`（不存在）
   → `AIMaskSource.source(ofFileName:) != nil` ✓。
3. **③vpError 死码**：`UprightMath.swift` `vpError` + `Segment.midpoint` 删除；
   全仓 grep `vpError` = 0 命中、`midpoint` 零消费命中 ✓。
4. **④HP5 note**：`grain_calibration.json` note 对齐 M9-2 null 终裁（「no
   invented interpolation — the readout hides」）；`MANIFEST.sha256` 独立复验
   **9/9 OK**（`shasum -a 256 -c`）✓。
5. **⑤paper_grade 清键**：`FilmPanelModel.swift:330-347` `setPaperStock` 同一
   commit 内 `gradedBW`（`channelModel == "bw"` 且 `PaperGradeTable.cachedTable`
   非空，判别式与 :138/:145 既有面同源）不成立时清 `paperGrade`。回归
   `testPaperSwitchClearsGradeOnlyOnNonGradedPaper`：graded BW 保留 / 色纸清除 /
   单 commit（`items+1`）+ landed record `paperGrade == nil` ✓。
   ΔN：AdjustmentTransferTests +1（git 基线实为 9→10，见 §九 m-1）、
   FilmPanelBWTests 5→6 ✓、IOP 2/0/0 + IOPP 2/1/0 定向日志在案。

## 二、diff 审

- **封存面 17 件机检**：`git diff f783f1c3..HEAD --name-only`（30 文件）对封存
  清单（DrtRecord/TerminalTailPolicy/DrtTailAssembly/PixelPipe/Lut3dKernels.metal/
  DrtEotf/ExportQueueContract/ExportFormatSpec/ImageIOEncoders/WebPEncoder/
  NodeGraphCommand/LightamerSidecar/HistoryStack/HistoryHash/PipelineDocument/
  V50Order/NodeOwnershipCatalog）grep 交集 = **0**。T2 动的 with_angle 路径落
  `CropToolRotation.swift`/`EditorAreaView.swift`（非封存件）亲核一致。
- **zh-audit**：`--check` PASS（1770 source keys / 2100 catalog keys / 10 interp
  keys variant-PRESENT；本批零新键）。
- **commit 规范**：五 commits 各自洽（fix ×2 / test / chore / docs），全部
  `refs #15`，subject ≤72 字符祈使句，body 英文 what+why；账本与产品拆分干净
  （T5 收口 commit 只载账本 + 日志）。

## 三、全套独立复跑

| bundle | executor 终报 | 本验收复跑 | peakRSS |
|---|---|---|---|
| IOP | 814/1/0 (979s, 6521MB) | **814/1/0** (947s) | 6419MB |
| IOPParity | 565/10/0 (1602s, 5500MB) | **565/10/0** (1603s) | 5274MB |
| Layers | 528/5/0 (438s, 1167MB) | **528/5/0** (473s) | 1166MB |
| Library | 785/4/0 (170s, 749MB) | **785/4/0** (172s) | 747MB |
| Sessions | 285/4/0 (63s, 1229MB) | **285/4/0** (63s) | 1255MB |
| Export | 385/4/0 (199s, 4981MB) | **385/4/0** (201s) | 4983MB |
| App | 1073/6/0 (630s, 2832MB) | **1073/6/0** (625s) | 2832MB |
| **TOTAL** | **4435/34/0** (4081s) | **4435/34/0** (4084s) | 零 MEMFAIL |

七 bundle 逐值一致；ΔN = +7（4428+7）与 git 基线/HEAD 法数差分自洽（§九）。
日志 `all-runs/r7-acc-all.log`；monitor 日志 `all-runs/r7-acc-monitor.log`
（两段：03:41 起全套轮 / 04:46 起补跑轮，`RSS-KILL` = 0 条）。

## 四、反自取消双探针（主树掏空还原法）

| 探针 | 掏空点 | 定向结果 | 还原后 |
|---|---|---|---|
| ① T1 端点对称臂 | `UprightGuidesOverlay.swift` release() `return endpointDragLanded` → `return false` | App `UprightGuidesInteractionTests` **9/0/1**——`testEndpointDragReleaseCommitsThroughTheHostSeam` :355 `XCTAssertTrue(m.release(), "the endpoint drag's release IS a change")` 真红 | **9/0/0** 绿 |
| ② T2 进桥转置 | `CropToolRotation.swift` `if swapsXY { recordRect = … }` → `if false && swapsXY` | App `CropToolRotationTests` **9/0/4**——`testSwapXYFlipRefitsInTheTransposedFrame` :401/:403 真红（landed 落未转置旧答案，与转置闭式差 4-5%；反真空断言同法翻红） | **9/0/0** 绿 |

两回归均可证伪，非自取消。探针经独立构建轮（掏空态 build → 测试 → `git
checkout` 还原 → 还原态 build → 双绿复验）。

## 五、T3 裁决专项复核

- **obs-4（400 峰值 = 按设计）复核成立**：证据链三层闭合——①源码
  `RasterDefaultRecord.derive` 四处 `peak: description.peakLuminanceNits`
  （`RasterDefaultRecord.swift:102/152/212/223`）；②登记正本
  `M4-1-02-SUMMARY.md` T3 行（`seedRasterDrtRecord` 三支 + carrier-only derive +
  `syncDrtCarrierWithHistory` raster「DRT 恒在」臂）；③读序无面板局部默认
  （§一 T3）。R6-R1 走查的 400（HDR raster seed = 文件 mastering 峰）与其 omp
  复现的 100（pristine RAW）不矛盾。「修复至初值 = record 语义值」的验收 =
  该性质本身，回归三态（pristine→100 / seed→400 / 清键→100）双向钉死质量合格：
  读链任一环被未来改动破坏即红。
- **m-1b（sections 不联动 = AX 合成伪影）复核成立**：写链/读链源码健全
  （Picker binding → setMethod → commit → `history.commitDrt` → @Observable →
  panelBody 重读）；静态表既有钉 + 新实例面回归钉死模型级真相。走查表型
  （radio 翻转而 sections 滞留）机理 = AppKit segmented 控件在合成 AXPress 下
  自更新选中态而 binding set 不达（m-1a 同族），人手通道（target/action →
  binding）不被触及。「登记观察不立项产品修复」判定合理；回归防的是模型级
  回归（读链/写链被改坏），非走查通道伪影——分工清楚，无验收缺口。

## 六、paste 活引用裁决复核（不删 = 正确）

- `VersionCoordinator.pasteChain`（:255）在安装新链前 `captureActiveChain`
  （:289 → :410-415）把 live history **值拷贝**进 active slot（`slot.chain =
  history`）——同图 paste 后，带 mask 引用的原链仍被 slot 持有。
- 清扫的 chains 集 = `[editorState.history] + versions.slots.compactMap {
  $0.chain }`（`AdjustmentTransferView.swift:308-309`）——**含捕获链**，故同图
  paste 时 `removeAssetIfUnreferenced` 必然 no-op（引用真），文件保留。
- M9-1 o-omp3 的「孤儿」实为该捕获版本活引用（omp 只核 active 链）——裁决
  正确，无条件删 = 静默破坏被捕获版本。真死回收（mask 移除/版本删除后的
  后续 paste）由引用门自然放行。外部 .lra / MCP 源不扫（非本 app 内存真相）
  边界已登记（DECISIONS §4.1，归 M11/M12 reachability collector）。

## 七、G4 透明越门追记（§9 先例）

- 起跑前 Data 卷 20393MB < 25G 门（GUARD BLOCK: G4）。清理尽人事：/tmp m94
  走查残留（~100K）清除；Lightamer 主 DerivedData 容器（1.7G）**不清**——
  全套前提即 build-for-testing 产物，清除后重建净收益 ≈ 0 且拖长构建。
- 越门执行条件核：G1 重活进程 = 0 ✓、G2 free 内存 77% ✓（swap used 8G/9.2G
  为静态占用，G3 已撤非压力指标）、`--monitor` 强制伴跑两段全程（`RSS-KILL`
  = 0）、逐 bundle 峰值 RSS 全部 < 8192 运行门、全程零 MEMFAIL、Data 卷运行
  最低点 15882MB（未触底）。按 §9 先例透明越门成立。

## 八、复跑执行注记

全套轮外壳（nohup 包装层）在 Export bundle 完成后被宿主侧终止，App bundle
未随轮执行——**非测试失败**（前六 bundle 已逐值落盘）；App bundle 以同
DerivedData 产物单独补跑（monitor 伴跑），1073/6/0 逐值与 executor 一致。
七 bundle 合计即本报告 §三表。

## 九、缺陷与观察清单

- **m-1（minor）BUNDLE-MAP 两行登记滞后（账本面）**：`M2-4-0-BUNDLE-MAP.txt`
  的 `DrtPanelModelTests` 行记 11（git 基线实为 **11** 法、HEAD **13** 法——
  旧账原记 9 滞后 2，本批「9→11」在旧值上 +Δ 继承滞后）、`AdjustmentTransferTests`
  行记 9（git 基线 **9** 法、HEAD **10** 法——旧账原记 8 滞后 1，本批「8→9」
  同理）。DECISIONS §5 的「8→9」「9→11」表述同源继承。ΔN 总账（+7）与全套
  实跑 4435 **不受影响**（git 差分自洽：8→9 / 7→9 / 11→13 / 9→10 / 5→6）；
  纯登记账落后实际，建议下批把两行勘正为 13/10 并在行尾注记勘误。
- **obs-1**：T2「落盘 record 逐字节相同」为几何恒等声明——反事实镜像臂不存在
  于代码，浮点严格逐字节仅指同代码路径确定性；回归以 1e-6 闭式钉死，实质
  成立（§一 T2 注记）。零动作。
- **obs-2**：T4① 清扫的 MCP `paste_adjustments` / 外部 .lra 消费面不扫——
  DECISIONS §4.1 已登记，归 M11/M12 reachability collector。零动作。
- **obs-3**：m-1a/m-1b 的 AX 合成事件通道伪影族——GUI 走查配方课题（SE 优先 /
  by-role+desc 断言），非产品缺陷面（DECISIONS §3 已登记）。零动作。
- observer 三件（M9-2 grade 视口地板 / 旧档 hash 伪影 / M9-2 路 2 obs-4）维持
  纯观察，本批零动作，与 DECISIONS §3 尾一致。

## 十、验收结论

五 commits 全部核验通过：T1/T2 修复语义正确且回归可证伪（双探针真红）；
T2 镜像抵消数学声明独立复核成立；T3 两裁决与 T4 paste 裁决复核均成立（证据
链闭合，无翻案）；封存面 17 件零 diff、zh-audit PASS、commit 拆分规范；全套
4435/34/0 独立复跑逐值吻合。**R7 修复批验收通过（PASS / 0 error + 0 major +
1 minor + 3 obs）**，m-1 为账本面勘正建议，不阻断。

验收人：R7 综合验收 agent（zcode）
验收 commit：见本文件所在 commit（单 commit，免关联，不 push）

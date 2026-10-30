# R7 DECISIONS（M9 站后尾项清偿修复批；issue #15）

基线 HEAD = `f783f1c3`，全套基线 4428/34/0。本批全程 G4 透明越门执行（见 §G4）。

## §1 T1 — 导线端点拖拽 release 提交门（M9-3 N-1）

- **根因**（源码亲核）：`UprightGuidesOverlay.swift` `release()` 只落 pending-draw
  臂，端点拖拽分支恒 `return false` → 视图 `changed == true` 门永不触发
  `onCommit` → live 值（setLiveParams）永不落为离散 item——拖完即关图丢失、
  undo 无该步。
- **修法裁决**：采用「对称臂 + dragMoved 门」而非 N-1 报告的第一建议
  （`dragging != nil` 即提交）。理由：DragGesture(minimumDistance: 1) 下
  「press 抓住端点但零 tick」可达（1-2px 微动即 press 即 release），无条件提交会
  落一条 params 全同的幻影 history item；`dragMoved`（dragTick 端点分支置位、
  press/leave/release 复位）把门收到「真实移动才提交」，与零长度画线按压
  「不是导线」的既有面同构。`UprightGuidesModel` 是 transient 值语义（每拖拽
  新建），Equatable 合成含 dragMoved 无消费面影响（grep 零模型等值比较）。
- **回归**：draw/端点/零 tick 三 release 契约 + host 缝持久化面
  （release 列表经 setParams + recordChange 落恰 1 item 携带移动后端点）。

## §2 T2 — flip 换轴重拟（M9-3 N-2）

- **根因**：`CropToolRotation.linkedSnapshots` 在 pre-flip AABB 域读 crop 记录，
  而 V50 序 flip 16 → crop 24.5，crop op 在自己（flip 输出）帧解释记录；
  SWAP_XY 态轴交换 → 重拟窗在 flip 帧内转置（近全幅差 0.3% 不可见；非对称
  crop + 90 族 + 角度变更时贴边不严）。
- **修法裁决**：桥 I/O 按 `swapsXY` 转置（进桥一次、出桥一次），**镜像半边不处理**
  ——代数证明：withAngle 对帧心镜像等变（最大拟合居中 / fit-shrink 门镜像对称
  / minSide 门对称），故 mirror∘transpose∘refit∘mirror∘transpose ≡ 纯转置往返，
  落盘 record 逐字节相同。四个 SWAP_XY 位型通用（M 各为 flipX/flipY 复合、自逆）。
  非 SWAP_XY 态（flipV/flipH/rot180）零处理零漂移（回归法钉死与 nil-flip 逐值同）。
- **`.auto` 语义**：漏斗内按 `FlipModule.commitParams` 语义解析（auto → none =
  管线恒等），与渲染真值一致。
- **回归**：rotCW90 + 非对称近全幅 crop + 10° 落「转置闭式」
  （transpose → bridge → withAngle → bridge → transpose 逐边 1e-6）+ 反真空面
  （未转置旧答案可证漂移 >1e-6）+ 全幅面（unit 转置不变、largest@10° 经同一桥）
  + 纯镜像面（flipH ≡ nil-flip 逐值）。

## §3 T3 — M2-6 纵深两项（R6-R1 omp obs-4 + m-1b）＝审计 + 回归，产品零 diff

- **obs-4（峰值初值 400 ≠ 100）**：全读序源码亲核（`DrtPanelModel.record`：
  live → history.effectiveDrtRecord → workspace.drtRecords → `DrtRecord()`）
  ——无面板局部默认；「400」= **M4-1-02 T3 raster derive seed 的语义值**
  （`RasterDefaultRecord.derive` peak = `description.peakLuminanceNits` =
  文件 mastering 峰；SDR 恒 100 = `sdrPeakNits`）。R6-R1 走查的 400 与其 omp
  复现的 100 并不矛盾——前者是 raster seed 说话，后者是 pristine RAW。定性 =
  **按设计（「DRT 恒在」raster 语义）**，非缺陷；「修复至初值=record 语义值」
  的验收 = 该性质本身，回归法双向钉死（pristine → 100；seed 400 → 400；清键 → 100）。
- **m-1b（方法切换 sections 不联动）**：写链/读链源码亲核全健全
  （Picker binding → setMethod → commit 幂等门 → recordDrtChange →
  `history.commitDrt`（EditorState.history tracked setter）→ @Observable 失效
  → panelBody 重读 sections）。静态表早有钉（test 1）；新回归钉**实例面**
  （视图 ForEach 消费的 `model.sections` 经全读链随 setMethod 重排：
  acesLimiting ↔ opendrtPresets）。走查表型（radio 翻转而 sections 滞留 +
  切页复位）= **AX 合成事件与 SwiftUI binding 脱钩（m-1a 同族伪影）**——
  AppKit segmented 控件在合成 AXPress 下自更新选中态而 binding set 不达；
  20s 滞后/切页「复位」= 重进页重读 binding 的必然。登记为观察项，不立项
  产品修复；人手通道未被该伪影触及（真点击走 target/action → binding）。
- observer 三件（M9-2 grade 视口地板 / 旧档 hash 伪影 / M9-2 路 2 obs-4）维持
  纯观察，本批零动作。

## §4 T4 — 卫生包五小件

1. **①paste 排除后 ai-subject 资产**：`RasterMaskStore.removeAssetIfUnreferenced`
   = 引用核对清扫（全 chains 全 items 全 layers 的 `mask.raster?.fileName`）；
   GUI paste 动作在 pasteChain 后对排除名单清扫。**关键裁决：不无条件删**——
   同图 paste 的 `captureActiveChain`（VersionCoordinator.swift:410-415）把带
   mask 引用的原链捕获进 slot，文件仍被引用；M9-1 o-omp3 的「孤儿」实为该活
   引用（omp 只核了 active 链）。无条件删 = 静默破坏被捕获版本。清扫只在
   引用真死时回收（mask 移除/版本删除后的同图后续 paste 等形态）。
   **边界登记**：外部 .lra 源与 MCP `paste_adjustments` 消费面不清扫（源图
   版本态非本 app 内存真相——磁盘 document 重读属 reachability collector
   （RESEARCH.md:100 M11/M12 规划）的面，本批不铺第二真相源）。
2. **②注释谓词名勘正**：`isAIMaskSpec`（不存在）→ `AIMaskSource.source(ofFileName:)`。
3. **③vpError 死代码删除**：全仓零消费点（grep 亲证）；连带 `Segment.midpoint`
   （唯一读者即 vpError，删除后成为新死码，同批清除）。
4. **④HP5 note**：对齐 M9-2 DECISIONS null 终裁——「no invented interpolation —
   the readout hides」；`MANIFEST.sha256` 同批重算（9/9 OK 复验）。测试面只钉
   rms null 语义、不钉 note 字符串，零回归扰动。
5. **⑤paper_grade 残留键**：取「清键」臂——`setPaperStock` 在同一 commit 内对
   无 graded face 的新纸清 `paperGrade`（ BW→graded BW 保留 grade 作梯记忆；
   BW→色纸清除）。消费缝（`FilmPrintBake` 查表门）本就渲染中性，本修使记录
   在源头诚实。回归法：保留/清除/单 commit 三断言。

## §5 测试账

ΔN = +7：UprightGuidesInteractionTests 8→9、CropToolRotationTests 7→9、
DrtPanelModelTests 11→13、AdjustmentTransferTests 8→9（原文 8，BUNDLE-MAP 行
327 原登记）、FilmPanelBWTests 5→6。全套预期 **4435/34/0**。BUNDLE-MAP 同批登记。

## §G4 透明越门追记（每轮一行）

- 起跑前清理：陈旧 DerivedData 容器 `Lightamer-glcjhggtbffoiuguwlseyjhxhvew`
  (1.9G) + /tmp m94-omp 走查残留 (121M)——尽人事后 Data 卷 23.4G/21.7G，仍
  <25G 门（PixCake 11G 等用户应用数据不可清）。三批 §9 先例：free 内存
  59-74% 区间、无 swap 压力、`--monitor` 伴跑强制（pid 在案）。定向轮与全套
  轮均在此状态下执行，无 MEMFAIL。

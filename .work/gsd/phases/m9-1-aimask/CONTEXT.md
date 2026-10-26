# M9-1 CONTEXT — AI Mask 工具 parity（OQ-1..10 裁决落定批，2026-10-25）

> **裁决正本**：research 期新开 **OQ-1..10 全部按 `RESEARCH.md` §六推荐落定**
> （charter 2026-10-27 夜间授权「M9 直接按推荐自动推进」制度，M7-2..M7-6 /
> LUMEN 同款「OQ 全按推荐」auto-advance；**晨审可推翻**——推翻 = 修订本文件
> 对应 D-M9A 条，下游 plan 受影响任务面重开）。读解正本 = 同目录
> `RESEARCH.md`（上游测绘 §一 / 我方盘点 §二 / 差距矩阵 §三 / 方案骨架 §四 /
> 探针 §五 / 风险 R-1..R-6 + OQ §六）；planner 2026-10-25 HEAD 抽核 ~25 点
> 亲核吻合（AIMaskService / AIMaskEditing / LayerEditingState / SegmentEditing
> OverlayHost / AIMaskFeather / RasterMaskStore / AdjustmentTransfer /
> PipeCoordinator / MaskToolbarView / InstancePickerOverlay 逐锚点在案）。
>
> **规格上游**：ROADMAP §M9 站 1 行（M-L，ΔN +20..28）+ REQUIREMENTS
> M9AIM-01..03 + `research/M9-CHARTER-INPUT.md` §2.1。charter 生效值 = OQ-M9-1
> 否（零新模型、Layer B 原生）+ OQ-M9-2 A（Sky 砍留槽）+ **AI-06 bake-to-raster
> 非黑箱范式维持 = 显式合法 parity 偏离**（DRT pristine 先例）。
>
> **并行现势（2026-10-25）**：R6 修复批 executor 在飞（重活道，同仓 commit）；
> 本 phase 执行批排 R6 收口后起跑；plan/CONTEXT = 零 commit 产物由 orchestrator
> 收割。全套对账锚 = **M8 终态 `4287/39/0` + R6 修复批 ΔN**（R6 终值由其收口轮
> 落账，本批全套申报带以「R6 收口终值 + ΔN」式表达，不写死数）。

## Phase Goal（M9AIM-01..03 锚定）

把 Alcedo AI Mask 工具的**交互与算子面**在我方 bake-to-raster 范式上对齐：
**M9AIM-01 任务蒙版三件**（Subject 现役 / Background = 1−Subject invert 腿 /
People = person 实例族 union；Sky 第四槽 disabled 占位）+ **M9AIM-02 viewport
迭代交互**（tap-to-segment 点集增删逐点即解 + Path 笔触采样 + 候选 coverage
淡红 tint 视口通道 + Commit 后候选通道消失）+ **M9AIM-03 算子与会话**
（Feather 绝对 px 口径对齐 + Expand 3×3 交替形态学新算子〔CPU vImage 零新
kernel〕+ open/commit/cancel 三命令 + paste 排除 AI bake 蒙版）。验收形态 =
三 REQUIREMENTS 行的机检断言（见 PLAN 各 T 验收标准）+ 定向 bundle 全绿 +
全套 ΔN 对账 + gui-acceptance 走查。

## 决议（D-M9A-1..10 = research OQ-1..10 采纳值，硬约束，执行中不重开）

| D | OQ | 采纳值（research 推荐直取） | 落点 |
|---|---|---|---|
| **D-M9A-1** | OQ-1 逐点即解 vs 先攒点后 confirm | **逐点即解**：点集变更 → debounce 300ms 全量重解（Layer B warm 85-126ms/步基线）→ 候选 plane 持有（session 态不 bake）；spinner + 保留旧候选显示（上游「推理期间保留旧 coverage」语义）；冷启动首步 spinner 提示模型就绪态（AIMaskEntryGate 三态门现役） | Plan T3 |
| **D-M9A-2** | OQ-2 People 子列表形态 | **子集一次确认**（复用 InstancePickerOverlay checkbox 形态 + unionSelection(.subset) 服务面）；上游逐人 toggle 增量 bake 不建（无 session 栈，逐 toggle bake = 多条 history 噪声）——偏离登记 §合法偏离 5 | Plan T1 |
| **D-M9A-3** | OQ-3 候选 coverage tint | **新增第四 style case `candidate`**（`MaskOverlayStyle` additive，display 样式枚举不入 record/history/sidecar；**样式 picker 走 `userSelectableCases` 白名单**——`.candidate` 不入用户样式菜单，`MaskCommand.panelMenuCases` 同款先例 LayerEditingState:109-111；xcstrings 不加 `mask_overlay_style_candidate` 键——v2 修 M-1，`ForEach(allCases)` 无编译期保障，收口靠白名单断言）；淡红 tint（上游 #515 maskCoverageTintColor 行为对照）走**候选专用合成臂 / request 形态扩展**（spec 组装腿对无 layer.mask spec 的 session 候选结构性不适用——PLAN T3 action 3 二选一预案，v2 修 M-2） | Plan T3 |
| **D-M9A-4** | OQ-4 Commit 后 tint 命运 | **维持 AI-06**：候选 coverage 通道在 Commit/Cancel 后消失（= REQUIREMENTS「Commit 后隐藏」的等价满足——隐藏的是候选通道）；既有「commit 后蒙版编辑 tint 0.85 常亮」零 diff（那是蒙版编辑 affordance 非 AI 候选，语义不同不照搬） | Plan T3/T4 |
| **D-M9A-5** | OQ-5 session undo/redo 栈 | **不建**（M9AIM-03 验收形态只列 open/commit/cancel；点级删点 + recordSeed 重置覆盖 80% 场景；栈 = 后续批按需）——偏离登记 §合法偏离 6 | Plan T3/T4 |
| **D-M9A-6** | OQ-6 Path 采样点数（预算 13/11 冲突） | **按 seed 形态收敛**：point-seeded = 12 采样点 + seed = 13 满；box-seeded = 11 采样点；等弧长 24px 采样、采样数 = min(16, 预算余量)（上游 kAiMaskMaximumStrokePromptPoints=16 / kAiMaskStrokePromptSpacingItemPx=24.0 行为对照） | Plan T3 |
| **D-M9A-7** | OQ-7 Feather/Expand 单位口径 | **绝对 px 对齐**：面板 Feather px [0,50] + Expand px [−50,50]（上游域）；内部经换算单源函数接既有 σ/羽化腿；`featherPercent` 既有字段与负腿（logit-gain）保留为我方超集，旧 UI slider 面平移换算（M6-4-02 面迁移） | Plan T2 |
| **D-M9A-8** | OQ-8 paste 排除呈现 | **跳过名单 toast/对话框列名**（与 transfer 面既有 greyed+count note 风格一致；上游 M17 ListAiMasksExcludedFromTransfer 行为对照）；**语义反转申报**：现行 raster mask 随 payload 走（AdjustmentTransfer.swift:193-195）→ 改排除 AI bake 件 = 上游 D18 反义对齐 | Plan T4 |
| **D-M9A-9** | OQ-9 Expand 实现 | **CPU Accelerate vImage 先行**（零新 kernel 红线最稳；3×3 cross/square 交替 dilate/erode，形态学 = 公开数学非 GPL 复制；bake 缝异步，CPU 形态学挂同缝）；GPU kernel 化挂后续优化批（升级 seam 注记） | Plan T2 |
| **D-M9A-10** | OQ-10 几何指纹 notice | **不入本批**（M9AIM 验收形态无此项；charter 落地路径 5 已列 = 提示件）——挂 `research/UPSTREAM-QUEUE.md` 登记，M9AIM-03 不背附加验收 | — |

> 附带裁定（planner 补，晨审可推翻）：**Expand→Feather 应用序** = 形态学先
> （边界移动）、羽化后（软化最终边界；反序会把 erode 掉的边缘晕回来）。
> 上游 margin 式 `max(expand,0) + ceil(4·feather)+1` 与两算子独立字段不锁序；
> 若执行期行为对照发现上游反序，DECISIONS 申报 + golden 双序负测钉死。

## 复用件清单（file:line，planner 亲核吻合）

| 件 | 位置 | 本批用法 |
|---|---|---|
| Layer B `segmentSubject` | `LightamerCore/Sources/AI/AIMaskService.swift:285-329` | 逐点即解的全量重解引擎（每步重攒点集重调用——API 无链式迭代，探针判定在案） |
| Layer B request 装配 | `AIMaskService.swift:366-418`（refine 逐点 :402-409） | 唯一装配路径零二路；点预算 gate 先于 Vision typed throw |
| 点预算 + Y-flip | `LightamerCore/Sources/AI/AIMaskTypes.swift:94-98`（`pointSeeded=13`/`boxSeeded=11`）+ `visionPoint` :33 | Path 采样收敛的消费判据（D-M9A-6） |
| person 实例族 | `AIMaskService.swift:480-613`（detect→labelComposite→`unionSelection` :588-613） | People 任务服务面**零适配**（探针判定：InstanceMaskObservation 与 Layer A 同型共腿 :235-267） |
| Layer A subject | `AIMaskService.swift:150-277`；入口 `App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift:353` | Subject 任务 = 现役入口入面板；Background = 同生成 + invert 位（per-ref `RasterMaskRef.invert`，`MaskToolbarView.swift:380-395` 现役 sugar） |
| commit/bake 通道 | `App/Sources/Lightamer/State/AIMaskEditing.swift:158-296`（`commitRasterMask` 含 `invert:`/`featherRadius:` 参数）+ `LightamerCore/Sources/Sidecar/RasterMaskStore.swift:88-116`（bake：r32F→Deriche→uint16→gray16 PNG→StableHash） | commit 命令 = 现役 Confirm；Expand 挂 bake 前置 pass（同缝） |
| AIMaskSource 识别面 | `AIMaskEditing.swift:29-62`（五源枚举 + `fileName(forLayerID:)` + `source(ofFileName:)` :55-62） | paste 排除判据（现役可判据）；re-entry 扩展 .segment → .subject/.person |
| SegmentSession | `App/Sources/Lightamer/State/LayerEditingState.swift:691-862`（点预算 gate :824-844 / recordSeed :810 / featherPercent :741 / `.scribble` typed seam :684-685,:811） | T3 主扩展宿主（删点/候选 plane/debounce/Path 激活）；T4 cancel 腿 |
| 蒙版 overlay 通道 | `LayerEditingState.swift:69-76`（`MaskOverlayStyle` 三态）+ `App/Sources/Lightamer/State/PipeCoordinator.swift:227-230`（maskOverlayRequest）+ :2434-2452（render 尾 `applyMaskOverlayIfRequested` 合成腿 + newest-wins 门） | 候选 coverage tint 传值面（D-M9A-3 第四 case + **专用合成臂/request 扩展预案**——`applyMaskOverlayIfRequested` :264-300 spec 组装前提与 caller payload 门对无 layer.mask spec 候选结构性不适用，v2 修 M-2）；**PipeCoordinator 不在封存面清单内**（App 侧协调器） |
| Feather 算子 | `LightamerCore/Sources/AI/AIMaskFeather.swift`（`sigma(percent:longEdgePixels:)` :54-58 / 负腿 logit-gain :69-88） | px 口径换算单源挂点；正/负腿全保留 |
| 交互宿主 | `App/Sources/Lightamer/UI/Overlay/SegmentEditingOverlayHost.swift`（click/⌥-click/⇧-drag :104-154 / confirm→commitRasterMask :231-264 / 27 SDK DragGesture.modifiers 坠落注记 :105） | 点删除 + Path 笔触 + 候选 spinner 挂载宿主 |
| People UI 先例 | `App/Sources/Lightamer/UI/Overlay/InstancePickerOverlay.swift`（checkbox floater :25,:47-57） | 任务面板 People 子列表复用形态 |
| paste 载体 | `App/Sources/Lightamer/State/AdjustmentTransfer.swift`（`isAdjustmentTransferable` :36-40 / `buildPayload` :174 起，mask 腿 :193-195） | 排除腿落点（mask 识别 + 跳过名单） |
| 既有测试面 | Layers bundle：AIMaskSemantic/Determinism/EditPaths/Feather/PlaneFormat/PersonInstanceMask/PatchAssembly/Geometry 八族；App bundle：AIMaskPatchFlow 等 | 回归面 + 新测试落域参照（BUNDLE-MAP 增行纪律） |

## 红线（plan 正本引用，执行批违者即错）

1. **封存面 15 项零 diff**（AGENTS 跨批速查清单：DrtRecord/TerminalTailPolicy/
   DrtTailAssembly/**PixelPipe**/Lut3dKernels.metal/DrtEotf/ExportQueueContract/
   六格式导出矩阵/NodeGraphCommand/sidecar schema（LightamerSidecar，v11 不
   bump）/HistoryStack/HistoryHash/PipelineDocument/V50Order/GradeCatalog）。
   蒙版/视口族**不在**封存面内（RasterMaskStore/AIMaskService/PipeCoordinator
   可触）；但 **PixelPipe（Core 侧）本批预期零触碰**——Layer B/蒙版 overlay
   全走 App 侧缝；若执行中发现必须触 Core PixelPipe → **逐 hunk 申报豁免 +
   停手上报**，不得自裁。
2. **零新 SPM**（Expand = Accelerate/vImage 系统框架；D-M9A-9）。
3. **零新 AI 模型 / 零模型下载面新增**（Vision 原生 Layer B + instance 族；
   AIMaskEntryGate 三态门现役复用）。
4. **AI-06 bake-to-raster 范式不可破**：AI 生成参数（点集/quality/候选
   plane/Path 采样）**永不持久**（sidecar 零新键、UserDefaults 零新键——本批
   候选态/点集/session 态全 UI 态）；像素即真相（Confirm 才 bake）。
5. **UserDefaults 新键登记制**——本批**零新键**（无跨会话记忆面；若执行中
   出现需求 → 停手申报，不得静默加键）。
6. **xcstrings 尾块纯插入** + `zh-audit --check`/`--self-test` 双 PASS +
   动态键禁形（`String.LocalizationValue("prefix_\(x)")` 禁；动态族显式
   switch 返回静态键，V14/L058）。
7. **V50Order / sidecar schema 零 bump**（AI 任务蒙版 = bake 件，无 iop 无
   schema 面）。
8. **新测试落域规则**（M2-4-0 E2）：新测试文件按 BUNDLE-MAP 域模式归唯一
   target + `Project.swift` 显式数组 + `tuist generate` 恒为该批最后动作
   （L041）。
9. **机器级单重活**：重活前过 `Scripts/machine-guard.sh`；**R6 修复批在飞时
   让位**（guard block 即停）；全套 `--all` = orchestrator 预批 + 8G 门 +
   MEMFAIL 机检；GUI 实例在测试起跑前 ps 清零验证（2026-10-24 运行时上限
   制度）。
10. **GPL 零代码复制**：Alcedo 仓只读行为对照（形态学核/高斯 σ 式/采样常量
    = 公开数学与数值参数，非代码复制）；上游 file 出处引 RESEARCH 附录表。
11. **D-H1 三段提交语义**：Feather/Expand slider 若交互式预览走 begin/
    live/end（松手才进 bake 参数；live 值不进 discrete commit）。
12. **disable-not-unmount**：Sky 槽 = `.disabled` 占位，不条件卸载（M7-5 纪律）。
13. **commit 纪律**：执行批 commit-per-task（Conventional Commits 全英文，
    只 add 相关文件；planner 本批零 commit）；产品面 commit 带 issue ref
    规则按 AGENTS 提交节（执行期 orchestrator 定）。
14. **AX id 浮出一处改动级则顺路**（R6 批 omp obs-3 教训）：走查配方触达的
    AX id 若因本批改动浮出缺失 → 顺路补，不留死账。
15. **测试宿主进程清理纪律**（M2-7-3 教训）：清理 GUI 进程前核 parentage
    （`ps -o ppid`）。

## 合法偏离清单（parity 申报面，验收不照抄上游断言）

1. **AI-06 bake-to-raster vs 上游 AI Mask source kind + R8 content-addressed
   asset + sidecar 进程（puerh_mind gRPC）+ 模型下载面板 + M16 lease +
   M11 reachability**（charter 显式声明；RESEARCH §四.5 不做清单全项）。
2. **click level 三级不可达**：Vision Layer B API 无多 mask token 输出面
   ——REQUIREMENTS M9AIM-02 不含此项，如实列偏离。
3. **64 点/组不可达**：Vision 点预算 13/11（API 自身限制）；Path 采样按
   D-M9A-6 收敛（12/11 点），体验降级明示（UI 计数器现役面承载）。
4. **无 embedding 缓存/链式迭代**：每步全量重解 warm 85-126ms（vs 上游
   decoder-only 33ms）+ 无「组内重放同结果」保证（每步独立重解可微漂；
   DeterminismTests 同输入同设备 byte-identical 在案）——spinner + 保留旧
   候选承接；大图多步累计延迟预算见 PLAN 风险节门值。
5. **People = 子集一次确认**（D-M9A-2）vs 上游逐人 toggle 会话形态。
6. **session undo/redo 栈不建**（D-M9A-5）：点级增删 + recordSeed 重置最小面。
7. **Commit 后隐藏 = 候选通道消失的等价满足**（D-M9A-4）：既有蒙版编辑
   tint 常亮保留（AI-06 affordance，语义不同）。
8. **Feather 实现域差**：GPU Deriche IIR（高斯族近似）+ bake 工作平面域，
   vs 上游可分离两 pass 高斯 + 分析图 R8 域；观感等价（同为高斯族模糊），
   逐字节 parity 非目标。负 feather logit-gain 腿为我方超集保留。
9. **paste 排除 = 语义反转**（D-M9A-8 申报）：现行 mask 随 payload 走 →
   改排除 AI bake 件（`AIMaskSource.fileName` 前缀判据；用户手绘蒙版无前缀
   = 不排除，语义正确：描述本图内容的恰是 AI 件）。识别面脆弱性（rename
   破坏判据）= R-2 登记：保守 = 只排可识别 AI 件，degrade 蒙版不排。
10. **Sky 砍留槽**（charter OQ-M9-2A 生效）：第四槽 disabled + tooltip，
    不建死代码路径。
11. **几何指纹 notice 不入**（D-M9A-10 → UPSTREAM-QUEUE）。

## 风险登记（RESEARCH §六 R-1..R-6 消解绑定）

- **R-1 Layer B 能力边界**（点预算/无链式/无缓存）→ PLAN 风险节给门值
  （逐点重解 P95 ≤500ms/步 + debounce 300ms + 点集上限 = AIPointBudget +
  patch 腿备选）与降载方案；冷启动 5.5s = 一次性（EntryGate 门现役）。
- **R-2 paste 判据脆弱性** → 排除面只及可识别 AI 件（保守臂）；rename 场景
  测试负例在册。
- **R-3 Path 点数冲突** → D-M9A-6 收敛（12/11 点）+ UI 计数器现役面。
- **R-4 Expand 新 kernel 家族** → D-M9A-9 CPU vImage 化解（零新 kernel）；
  GPU 化留 seam 注记不入本批。
- **R-5 逐点即解 history 语义** → PLAN T4 定边界：候选态不进 history；
  Confirm 恰 1 条 stackSnapshot；re-entry 再 confirm = 第 2 条（现役 re-bake
  同款，如实呈现非缺陷）。
- **R-6 范式偏离验收口径** → §合法偏离清单 + PLAN 各 T 验收标准按我方语义
  断言（不照抄上游断言）；走查样例动工前与用户对齐（§12.3 铁律——C 档停
  呈报时附走查样例清单）。

## 编排

- 单 plan `M9-1-PLAN.md`（T1→T5 串行，机器级单重活制）；执行批排 **R6 修复
  批收口之后**起跑（guard 让位纪律）；每任务独立 commit。
- **C 档停**：T5 闭环（全套对账 + 走查配方落盘）后停汇报，等用户确认再谈
  M9-2。
- 验收 = 双路 zcode 独立验收（串行）→ omp 二次验收（computer-use，严格串行
  独占——AGENTS 全阶段 omp 复审节）。
- 探针/定向轮：`Scripts/test-direct.sh --bundle Layers|App`（常跑免批）；
  全套 `--all` = orchestrator 预批制。

# M9-1 PLAN REVIEW — AI Mask 工具 parity（独立评审，2026-10-25）

> **结论档位：PASS-with-notes**（0 blocking / **2 major** / **5 minor**）
> 评审对象 = `M9-1-PLAN.md` v1 + `CONTEXT.md`；依据 = `RESEARCH.md` / REQUIREMENTS
> M9AIM-01..03 / ROADMAP §M9 / AGENTS 跨批不变量 + 仓库 HEAD 实测。
> 抽核锚点 **35+ 处，零错锚**（最大漂移 1-2 行，语义全中）——见附录。
> 纯读评：零 commit、零构建零测试、未启 computer-use。

---

## 一、逐维度判定

### 1. 目标回溯（AC 覆盖矩阵）— PASS

M9AIM 三条验收形态逐条可兑现，无缺腿：

| REQUIREMENTS 验收形态 | Plan 承载 |
|---|---|
| M9AIM-01「三件经 M6-4 分割基建落位 + Background 恒等负测 + Sky 槽 disabled 断言」 | T1 测试①②（invert 位断言 + AX id/disabled/点击零动作）+ 三件面板落位；服务面实测零差距（`detectPersonInstances` :480 / `unionSelection` :588 亲核在位） |
| M9AIM-02「合成事件→AX 驱动真视口 tap→蒙版更新→coverage 消长 + 交互不改参数真相（AI-06）」 | T3 候选通道消长 + AI-06 断言（sidecar/history 零写入 grep + 序列化负测）+ T5 走查②③（AXPress 配方）+ omp computer-use 二次验收——覆盖链完整（映射显式化建议见 m-3） |
| M9AIM-03「会话三命令端到端 + paste 排除负测 + Feather/Expand golden（对称半径/边界行为）」 | T4 四族测试（cancel 丢弃/re-entry 三源/paste 正负测/undo 边界）+ T2 golden 五面（八角距离对称/逐字节/反演/恒等/量化单调） |

### 2. 坐标真实性 — PASS（35+ 锚点亲核，零错锚）

全部复用缝锚点（AIMaskService 六段 / AIMaskEditing 四段 / LayerEditingState 七段 /
PipeCoordinator 两段 / SegmentEditingOverlayHost 三段 / AIMaskFeather / RasterMaskStore /
AdjustmentTransfer 三段 / MaskToolbarView 三段 / InstancePickerOverlay / AIMaskTypes /
AIMaskSemanticTests :220 / 07-1-DECISIONS :30 warm 85-126ms / STATE M8 终态 `4287/39/0` /
GOAL-STATE R6 在飞）实测语义命中；行号漂移 ≤2 行仅三处（见 m-5）。CONTEXT「PipeCoordinator
不在封存面清单内」与 AGENTS 封存面 15 项清单核对一致；RasterMaskStore/AIMaskService 确不在
封存面。BUNDLE-MAP 实测：Core 级 AI 测试族全在 LAYERS、交互族在 APP——「三 LAYERS + 三 APP」
落域与惯例一致。

### 3. 红线完备 — PASS

CONTEXT §红线 15 条逐条落 plan `red_lines` 或对应 T 的验收 grep/断言：封存面 15 项零 diff
+ PixelPipe 逐 hunk 申报豁免停手（T3 双写）、零新 SPM（T2 vImage 系统框架）、零新模型、
AI-06 零新键（T2/T3 持久化面 grep 断言 + 序列化负测）、xcstrings 尾插 + zh-audit 双 PASS +
动态键禁形（T1/T3/T4/T5）、V50Order/schema 零 bump、测试落域 + tuist 末位（T5）、机器级
单重活 + R6 让位（front-matter depends_on + guard）、GPL 零复制（T2 形态学 = 公开数学）、
D-H1 三段（T2 slider）、disable-not-unmount（Sky 槽）、commit-per-task、AX id 顺路（T5②）、
parentage 纪律。无漏项。**唯一缺口在执行层：`.candidate` case 的 allCases 消费面（M-1）**。

### 4. 可执行性 — PASS-with-flag（M-2）

- 各 T 验收均为命令级判据（grep 恰一处/逐 hunk diff/定向 bundle），SC 可机检。
- ΔN 对账锚诚实：基线带式表达（M8 终态 `4287/39/0` 实测吻合 STATE + R6 在飞终值不写死），
  不预支未落账数字。
- T 间依赖序合理：T1→T2→T3→T4→T5 串行；T4 cancel 的「已解候选丢弃面」正确依赖 T3 候选态；
  T5 收口依赖全部。
- **flag = M-2**：T3「候选 tint 复用 maskOverlayRequest 腿」低估了结构缝——
  `applyMaskOverlayIfRequested`（PipeCoordinator:264-300）从 stack layer 的 **mask spec**
  组装 plane（DrawnMaskRasterizer / `MaskCombiner.effectivePlane`），caller 门
  `layer.mask?.hasAnyPayload == true`（:2437-2441）与函数内 `unwrap(layer.mask,
  "mask overlay: no mask")` 对**未 bake 的候选 plane**（session 态、无 layer.mask spec）
  结构性不适用。复用 = 需扩展 request 形态（附带纹理）或旁路 spec 组装——都在可触面
  （PipeCoordinator 非封存），但 plan 的措辞（「:227-230 消费 .candidate」）把结构扩展写成了
  样式参数消费，风险节只点了 newest-wins 冲突未点 payload guard。须补预案点名（修法见 M-2）。

### 5. 风险处置 — PASS

- **R-1 门值与降载序可执行**：门 P95 ≤500ms/步 = warm 85-126ms 的 4× 余量（07-1-DECISIONS:30
  实测锚亲核）；降载四步序（debounce 300 已入 T3 → API 硬限无自设 → 超门自适应 500ms →
  `segmentPatch` :350 备选实测在位）具体、有次序、有申报点。
- **paste 语义反转回归面覆盖**：存量依赖者**实锤**——`AdjustmentTransferTests.swift:114`
  （mask 装配）+ `:390`（`XCTAssertNil(pastedLayer.mask?.contentRevision)` mask 随 payload
  断言）在案，反转后必翻转。plan T4 处置正确：验收强令 DECISIONS 列翻转清单 + 手绘蒙版不排
  负测守门 + 存量断言同步改写纪律。回滚 = 回复现行语义有 DECISIONS 记账。

### 6. OQ 采纳表 — PASS

D-M9A-1..10 与 RESEARCH §六推荐逐条比对**全一致**，无暗偏离：OQ-1 逐点即解 / OQ-2 子集一次
确认 / OQ-3 第四 case / OQ-4 维持 AI-06 / OQ-5 不建栈 / OQ-6 按 seed 形态收敛 / OQ-7 绝对 px
（research「倾向绝对 px」，采纳无暗加重）/ OQ-8 跳过名单 / OQ-9 CPU vImage / OQ-10 不入
（UPSTREAM-QUEUE.md 实测存在于 `.work/gsd/research/`）。附带裁定 Expand→Feather 有独立技术
理由（反序会把 erode 掉的边缘晕回来）+ 晨审可推翻 + 执行期反序证据双序负测预案——偏离处理
规范。

### 7. 量级诚实 — PASS-with-note

- M-L 档与任务面（5 T / 23 产线+测试文件 / 一新算子 + 三交互件）相称。
- 测试落域三 LAYERS + 三 APP 与 BUNDLE-MAP 实测域分布一致；Project.swift 显式数组 + tuist
  末位（L041）落 T5。
- ΔN 带 +20..27 ⊂ charter +20..28，但**构成明细合计 ≈27-29 法**（T2 = Morphology 5 面 +
  FeatherPx 4 面 ≈ 9 vs 带 +5..7；T3 = Path 3+ 面 + Iterative 6 族 ≈ 9 vs 带 +6..8）——
  偏紧 2-4，越带申报机制兜底，建议 plan 期对齐（m-2）。

---

## 二、发现清单

### Blocking（0）

无。

### Major（2，须修后执行）

**M-1 `MaskOverlayStyle.allCases` 消费面泄漏未处置（T3）**
- 位置：`App/Sources/Lightamer/State/LayerEditingState.swift:69-76`（枚举 + `labelKey` 动态拼
  `mask_overlay_style_<rawValue>` :75）× `App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift:144`
  （`ForEach(MaskOverlayStyle.allCases)` 样式 segmented picker）。
- 机制：新增 `.candidate` case 后，(a) picker 运行时自动出现第四项（candidate 泄漏进用户样式
  菜单）；(b) 其 labelKey `mask_overlay_style_candidate` 在 xcstrings 无键（实测仅
  translucent/rubylith/onBlack 三键在册）→ 裸键显示——正是本批红线 6/动态键禁形语境里的
  M3-1 F-2 同款陷阱；(c) 用户可选中 candidate 为持久 overlay 样式 = session 内部态语义污染。
  T3 验收写「`allCases` 消费面编译期收口」不成立——`ForEach(allCases)` 非穷举 switch，无编译
  期保障，是运行时 UI 泄漏。
- 修法：T3 action 3 补「样式 picker 白名单（如 `userSelectableCases` 静态列表——
  `MaskCommand.panelMenuCases` 同款先例在 LayerEditingState:107-110，注释明言 a future case
  cannot silently leak into the menu）+ xcstrings **不加** `mask_overlay_style_candidate` 键 +
  测试断言可选样式集不含 candidate」。不必翻 D-M9A-3 裁决（第四 case 路线保留，仅补消费面过滤）。

**M-2 候选 coverage 通道的传值缝结构低估（T3）**
- 位置：`App/Sources/Lightamer/State/PipeCoordinator.swift:264-300`（`applyMaskOverlayIfRequested`
  从 stack layer 的 mask spec 组装 plane）+ `:2437-2441`（caller 门 `layer.mask?.hasAnyPayload
  == true`）。
- 机制：候选 plane 是 session 态、未 bake、无 layer.mask spec——现役合成腿的输入形态（spec →
  DrawnMaskRasterizer / `MaskCombiner.effectivePlane`）与 caller 门对候选**结构性不适用**。
  「复用 maskOverlayRequest 腿」实际 = request 元组形态扩展（附带候选纹理）或候选专用合成臂
  旁路 spec 组装 + payload guard。plan 风险节只点了 newest-wins 冲突，未点这个更根本的缝；
  files_modified 注释「maskOverlayRequest :227-230 消费 .candidate」把结构扩展写成样式消费。
- 修法：T3 action 3 补结构预案二选一显式化（① request 扩展携带 `MTLTexture` 候选 + caller 门
  候选分支 bypass payload guard；② 候选专用 overlay request 变体走同 render 尾插入点），
  read_first 点名 `:264-300` 的 spec 组装前提，DECISIONS 记选定形态。仍在可触面（PipeCoordinator
  非封存），Core PixelPipe 零触碰红线不受影响。

### Minor（5，随批）

**m-1 Expand CPU 路线 vs「GPU」字样未入合法偏离清单**
REQUIREMENTS M9AIM-03 正文与 ROADMAP M9-1 行均写「GPU Feather/Expand（GPU 算子）」；D-M9A-9
裁 CPU vImage（零新 kernel 红线优先，正确）。验收形态不含 GPU 判据，不构成 AC 违反；但 CONTEXT
§合法偏离清单 8 只申报了 Feather 域差，未申报 Expand 的 CPU/GPU 之别。建议 T2/DECISIONS 补一
句申报（「Expand = CPU vImage 偏离 charter 'GPU' 字样，零新 kernel 红线优先，GPU 化留 seam」）。

**m-2 ΔN 构成合计与带偏紧 2-4**
T2 构成 ≈9 法 vs 带 +5..7、T3 构成 ≈9 法 vs 带 +6..8（构成面计数合计 ≈27-29 vs 申报带
+20..27）。建议 plan 期对齐：或将构成面合并为更少测试方法（一法多断言），或上调带并预写越带
申报理由，避免收口轮对账被动。

**m-3 M9AIM-02「探针脚本（合成事件→AX）驱动真视口」承载映射建议显式化**
该验收形态的兑现链 = T3 状态机级单测（机检）+ T5 走查②③（AXPress 配方）+ omp computer-use
二次验收。建议 T5 SUMMARY/走查配方里显式写「M9AIM-02 验收形态 ↔ 走查项②③ + omp 复审」映射行，
供验收轮对账不落空。

**m-4 T4 re-entry 扩源与 AIMaskSource 现役注释意图相抵，需同步改写**
`AIMaskEditing.swift:37-46` 注释明言「`ai-person` prefix stays disjoint… a person re-bake
must never seed a segment session — `armSegmentSession` keys on `.segment` only」（depth 同款）；
判据实测在 `LayerEditingState.swift:284-291`（`source(ofFileName:) == .segment`）。T4 扩三源 =
显式推翻该注释陈述的设计意图。语义可分（注释防自动联动，T4 是用户显式重开），但 executor 读到
「must never」会与任务冲突。修法：T4 action 2 补「同步改写 AIMaskSource/armSegmentSession 注释
意图 + DECISIONS 记设计意图变更（显式 open ≠ 自动 seed）」。

**m-5 行号漂移三处 + scribbleNotSupported 零残留口径**
commitRasterMask 实测 :158（research :157-296 / plan :158-296 各执一词）；AdjustmentTransfer
mask 腿实测 :194-196（引 :193-195）；MaskToolbarView subject 入口按钮实测 :363（锚 :353 =
入口区注释行，±10 内语义锚可接受）。另 T3 验收「`scribbleNotSupported` 零残留 grep」实测现
仓 5 处命中（含 AIMaskError case、LayerEditingState 注释/guard、测试）——零残留若含注释与
error case 会扩大改动面，建议验收措辞明确口径（typed throw 撤除 + 测试改写在册；注释/error
case 去留 DECISIONS 记）。

---

## 三、附录：抽核锚点清单（35+，全命中）

| # | 锚点 | 实测 |
|---|---|---|
| 1 | MaskToolbarView :353 主体蒙版入口 | ✓（注释 :353 / 按钮 :363，语义锚） |
| 2 | MaskToolbarView :380-395 T7 invert sugar | ✓（:385 `invert: true` + per-ref invert 注释） |
| 3 | MaskToolbarView :240-260 feather slider | ✓（:242-248 slider + :249-253 value + reset） |
| 4 | InstancePickerOverlay :25-57 checkbox floater + 预览 tint | ✓（:25 struct / :47-57 Toggle / :62-71 preview tintedImage） |
| 5 | AIMaskService :285 segmentSubject | ✓ |
| 6 | AIMaskService :366 buildLayerBRequest / :402-409 refine | ✓（:405/:407 addIncluded/ExcludedPoint） |
| 7 | AIMaskService :350 segmentPatch | ✓ |
| 8 | AIMaskService :480 detectPersonInstances | ✓ |
| 9 | AIMaskService :588-613 unionSelection（.subset 分支） | ✓ |
| 10 | AIMaskService :235-267 labelComposite 共腿 | ✓ |
| 11 | AIMaskTypes :94-98 AIPointBudget 13/11 | ✓ |
| 12 | AIMaskTypes :33 visionPoint Y-flip 单缝 | ✓ |
| 13 | AIMaskEditing :29-62 AIMaskSource 五源 + :48 fileName + :55 source(ofFileName:) | ✓ |
| 14 | AIMaskEditing :67 AIMaskEntryGate | ✓ |
| 15 | AIMaskEditing :158 commitRasterMask（漂移见 m-5） | ✓ |
| 16 | AIMaskEditing :21-24 AI-06「永不持久」注记 | ✓ |
| 17 | LayerEditingState :69-76 MaskOverlayStyle 三态 + labelKey :75 | ✓ |
| 18 | LayerEditingState :691 SegmentSession | ✓ |
| 19 | LayerEditingState :684-685 .scribble seam 注释 | ✓ |
| 20 | LayerEditingState :811 recordSeed scribble guard | ✓ |
| 21 | LayerEditingState :810 recordSeed | ✓ |
| 22 | LayerEditingState :824-844 点预算 gate | ✓（:830/:841 typed throw） |
| 23 | LayerEditingState :741 featherPercent | ✓ |
| 24 | PipeCoordinator :227-230 maskOverlayRequest/set | ✓ |
| 25 | PipeCoordinator :2434-2452 render 尾合成 + newest-wins（:2446 调用） | ✓ |
| 26 | PipeCoordinator :264-300 applyMaskOverlayIfRequested spec 组装前提（M-2 证据） | ✓ |
| 27 | SegmentEditingOverlayHost :104-154 手势（DragGesture :112/:127） | ✓ |
| 28 | SegmentEditingOverlayHost :105 27 SDK modifierFlags 注记 | ✓ |
| 29 | SegmentEditingOverlayHost :231-264 confirm 腿（:229 MARK/:245 commit） | ✓ |
| 30 | SegmentEditingOverlayHost :217-221 Done 按钮（AX segment.done） | ✓ |
| 31 | AIMaskFeather :54-58 sigma / :69-88 applyFeatherNegative | ✓ |
| 32 | RasterMaskStore :88-116 bake（invert :92/:115）+ RasterMaskRef.invert 位（:156 消费） | ✓ |
| 33 | AdjustmentTransfer :36 isAdjustmentTransferable / :174 buildPayload / :194-196 mask 腿（漂移 m-5） | ✓ |
| 34 | AdjustmentTransferTests :114/:390 存量 mask paste 断言（反转依赖者实锤） | ✓ |
| 35 | AIMaskSemanticTests :220 testLayerBSeedNonEmptyAndExcludedPointDrops + ensureLayerBAssets 门 | ✓ |
| 36 | 07-1-DECISIONS :30 warm 85-126ms 实测 | ✓ |
| 37 | STATE current_phase M8 closed `4287/39/0` | ✓ |
| 38 | GOAL-STATE R6 executor 在飞（guard 让位前提成立） | ✓ |
| 39 | BUNDLE-MAP AI 族域分布（LAYERS 六族 + APP PatchFlow） | ✓ |
| 40 | xcstrings ai_task_*/ai_path_*/ai_candidate_*/transfer_ai_masks* 零冲突；mask_overlay_style_ 恰三键 | ✓ |
| 41 | UPSTREAM-QUEUE.md 存在（.work/gsd/research/） | ✓ |
| 42 | zh-audit.py / test-direct.sh / machine-guard.sh 在位 | ✓ |

---
phase: M9-1
status: drafted
date: 2026-10-25
author: M9-1 researcher (零 commit 批)
---

# M9-1 RESEARCH — AI Mask 工具 parity（上游测绘 / 我方盘点 / 差距矩阵 / 方案骨架）

> 任务源：ROADMAP §M9（站 1）+ REQUIREMENTS M9AIM-01..03 + `research/M9-CHARTER-INPUT.md` §2.1
> （charter 已按推荐生效：OQ-M9-1 否 = 零新模型、Layer B 原生路线；OQ-M9-2 A = Sky 砍留槽；
> bake-to-raster 非黑箱范式〔AI-06〕= 显式合法 parity 偏离）。
> 上游正本 = AlcedoStudio `origin/main`（GPL 只读行为对照，零代码复制；SM5-SM9 增量）。
> 我方引用一律 file:line（HEAD 本批实测）。探针 = 定向单 bundle 单类（guard 前置让位 R6 后空窗跑）。

---

## 一、上游测绘（Alcedo Studio origin/main，行为/结构读解）

### 1.1 工具面板（SM9，`docs/roadmap/.../phase_sm9_tool_and_sm7_notice_plan.md` §1）

控制序（2026-10-25 用户改定：icon 动作面，无 Prompt/Tasks 切换器、无 busy 文字）：

```
AI Mask icon   New AI Mask / Edit AI Mask              Close (icon)
Tasks (icons): Subject  Background  Sky  People
People list (People 为末组件时；click = toggle person)
Prompt tools (icons): Point  Box  Path            Add / Subtract (icons)
Click level (icons)（仅当 last click 有三级时）
Feather
Expand
Undo  Redo (icons)
Error alert + Retry；notice 文本
Confirm（唯一全宽文字按钮；无 Cancel 按钮——header Close 即 Cancel）
Stage progress（运行中）
```

- **唯一文字按钮 = Confirm**；全部控件 icon + accessible name + tooltip；raised control fill。
- **运行态** = 面板黄框旋转（`RotatingTaskBorder`）+ 底部进度条；**Open 五段计数**
  （1 open edit → 2 render analysis → 3 start AI runtime → 4 load models → 5 read image），
  模型 run/update/commit 用 indeterminate 条。
- **入口**（issue #517）：AI Mask header 按钮（新建/编辑所选 AI Mask）+ Mask 列表行点击
  → `EditorAiMaskTool::openSelectedAiMask` → `OpenAiMaskEdit(grade, mask_id)`（存储 coverage
  直显、零模型调用，M15）；Radial/Linear Gradient 行只选中不开编辑。工具开着时行点击不开新编辑。

### 1.2 交互与 prompt 几何

- **三 prompt 工具**（`ai_mask_prompt_geometry.hpp`）：
  - **Point**：单击加点，加入开放 prompt group（Add/Subtract = 点 label）；
  - **Box**：拖画框，恒开新 group（新对象）；
  - **Path**：释放的笔触按**等弧长 24 item-px 间隔采样、每笔 ≤16 点**
    （`kAiMaskMaximumStrokePromptPoints = 16` / `kAiMaskStrokePromptSpacingItemPx = 24.0`），
    恒开新 group；**group ≤64 点**（超限 = 既有解释性错误，保留旧 group，不静默拆分）。
- **prompt group 语义**（SM5 M3）：组开放时 prompt 步入组；task 步 / person toggle / 模式切换
  关组。组内 Add/Subtract 点 = SAM label 1/0；新组的工具模式 = 组 operation（SAM 不能只用减点
  起组——减点笔触在 task 蒙版上做 Subtract region）。
- **click level**（M4）：仅「单点、无 box」的 prompt 步有三级（decoder 三 mask token 按面积
  排序）；`SelectLevel` 换级零模型调用（切换 `selected_index`）。
- **坐标**：viewport 指针 → normalized ReferenceSpace（全源图、无 crop/rotation，D7/D8）；
  `MapItemToAiMaskPromptPoint` / `MapItemRectToAiMaskPromptBox`（旋转视图 = 四角映射的 AABB，
  clip 到源）；提示点只能加在可见照片内，**蒙版可延伸到 crop 外**。
- **推理期间**：保留旧 coverage + 控件可见；禁新模型输入/Undo/Redo/Commit；Cancel 与
  viewport pan/zoom 可用；不 blank 照片。
- **viewport 输入 overlay**（`ai_mask_input_overlay_geometry.hpp`）：绿 + disc / 红 − disc
  （`add_color #30A46C` / `subtract_color #E5484D`，marker r7 + 1.5px 深色 rim）、Path stroke
  4px、box 2px、选中 person box 并集轮廓、悬停 person 虚线框、每工具专用 cursor（平台
  cursor 隐藏）、busy 时 cursor 灰无徽记。左键 = 所选 prompt 工具；中键/滚轮 = pan/zoom。
- **Pointer movement 只画 marker 不推理**（U7）；Run 只在 click/stroke release/box release 后。

### 1.3 任务蒙版（D2/D21/M5 + SM3.C/D）

| 任务 | 数据源 | 形态 |
|---|---|---|
| Subject | S3OD `s3od-synth` 全图 alpha | alpha grid（长边 1024）in ≥0.5 |
| Background | **= 1 − Subject（纯逻辑倒置）** | 同上 |
| Sky | people_sky_head + SAM decoder | region logits 双线性上采样阈值 0 并集，BINARY R8 会话尺寸 |
| People | S3OD 全图 alpha（= Subject 基底）+ People 列表 | 逐人 toggle：Add=max、Subtract=min(c, 255−person)；person alpha = person box crop + margin 的 S3OD；初始 included = `in_subject`；`found=false` 无步；列表左→右排序 |

- People 列表项 = index + box（normalized）+ score + subject_fraction + in_subject。
- People 不用 SAM box prompt（D21）；person 叠加无邻居特判（有序 Add/Subtract）。

### 1.4 编辑会话（D16/D17/M7/M15/M16，`ai_mask_edit_session.hpp`）

- **两级 history**（D16）：session 内存栈（state = recipe + edge + input_mode +
  open_prompt_group 四元）；strokes/加减点/box/task 选择/模式切换/Feather/Expand 皆 session 步；
  Undo/Redo 走 session 栈；**live document 会话期不变**；Commit 发布 1 条主 history op
  （AddMask 或 ReplaceMaskSource）；**Cancel 零发布**；主 history Undo/Redo 不动。
- **M7 output store**：每步模型输出按组件前缀 canonical JSON 为键存原生网格（SAM logits
  256²≈256KB/步、alpha grid、Sky R8）；**栈内已有输出的步 Undo/Redo 零模型调用**；栈无长度限制。
- **M15 重开**：存储 AI Mask 开会话 = 首态显存储 asset coverage，零模型调用；第一步改组件才
  计算新态输出；Undo 回开态再显存储 asset；`analysis_extent` ≠ 会话图像尺寸 = open error。
- **M16 lease**：`AiMaskEdit` 操作租约阻塞主文档操作（PreviewAdjustment/Commit/Undo/Redo/
  MoveHead/版本全家/ApplyPaste/OpenComparison）；视图操作与切图可用（切图经生命周期终结会话）。
- **Feather/Expand**（M8/D20）：`AiMaskEdgeAdjustment{feather_px ∈ [0,50] 高斯 σ,
  expand_px ∈ [-50,50] 整数（>0 dilate / <0 erode）}`，**分析图像素域**；source 字段、
  改值**不写 asset**（stored R8 恒为 pre-edge）；slider 拖动 = previewEdge 显示请求（不加步），
  松手/键盘接受 = acceptEdge 一步；Undo 恢复上组接受参数零模型调用；Escape 边缘编辑恢复起值零步。
- **Commit 裁剪**（M9）：coverage >0 的 bounding rect + 1px 边 → content-addressed zlib
  MaskAsset（DuckDB `MaskAsset` 表，`kMaximumRasterMaskAxis` 4096）；无 >0 值 = commit error。
  **asset 先写（自有事务）→ history 后发布**；失败留孤儿行由 reachability 清扫回收（M11/M12）。
- **错误链**：GPU 失败保留目标 session 态 + 显旧结果 + Commit 禁用直到 Retry 显出目标态
  （SM8 §4.3）；模型错误走 session 结果不加步。
- **模型治理**（D12/D13/D15 U6/D22）：sidecar 进程（Rust `puerh_mind` gRPC）常驻推理；
  S3OD 载入后驻留到 unload；回到普通调节即卸载；embedding 缓存 4 张。

### 1.5 coverage 合成与显示（M6/D23/SM8）

- **合成**（`ai_mask_coverage_composition.hpp`）：R8 会话尺寸；SAM logits 双线性
  （half-pixel）→ >0 二值 255/0；S3OD alpha grid = **联合双边上采样**（D23：4×4 邻域 cell、
  spatial σ1 cell、range σ0.7×窗口色标差、gain=半上采样因子、≥0.5 陡化；guide = 会话图
  σ1 平滑，每会话 ~50ms 一次 + 每转换 ~20ms@2729×4096）；Sky R8 原样。**fold**：组件有序，
  Add = max，Subtract = min(coverage, 255−component)。
- **显示**（SM8.5/8.6/8.7）：**专属视口通道**（RGBA32F、coverage 存红通道、专用 presentation
  adapter，不占照片/detail 槽、不 CPU 回读）；**淡红 tint** = AppTheme `maskCoverageTintColor`
  固定色（每主题同值，#515）；**候选/已提交/Grade Union 共用一次 viewport composite**
  （照片 base/detail 选择之后的同一 draw）；**Commit/Cancel 后 coverage 消失**（除非此前
  选中了 committed mask 的 coverage preview，`SelectMaskCoveragePreview`）；Commit 不自动选中
  已提交 mask。展示态（可见性/tint/preview 选择）不改 history/photo cache/export/scope。
- **thumbnail**：AI 有效 coverage 经 SM8 走 128×128 采样下载，零模型调用。

### 1.6 GPU Feather/Expand（SM8.2-8.4，CUDA/OpenCL/Metal 三后端）

- **Expand** = `|expand_px|` 步 3×3 形态学：**偶数步 cross 核、奇数步 square 核**（交替 =
  近圆盘膨胀/腐蚀），R8 值域（max/min 与 v/255 单调映射交换律 = 与浮点结果精确一致）。
- **Feather** = σ=feather_px 高斯（OpenCV `getGaussianKernel`，size = `round(8σ+1)|1`），
  **可分离两 pass**：水平 R8→R32F 加权和 → 垂直 R32F→R8（`round_half_even` 量化）。GPU 与
  host 参考差 ≤1 code value（浮点求和序）。
- **grid** = source bounding rect 放置于 (source_x, source_y)；外读 0、界外 clamp-replicate；
  **margin = max(expand,0) + ceil(4·feather)+1**；kernel radius ≤200（σ50 → 401-tap）。
- 三后端共享 host 参考函数 `MakeAiMaskCoverageTexture`（测试证据非运行时替代）。

### 1.7 paste 排除与几何指纹

- **paste**（D18/M17）：`AdjustmentTransferPackageBuilder` 不装 AI Mask；所选 Grade 的 mask
  全为 AI 时该 Grade 条目无 mask 集；`ListAiMasksExcludedFromTransfer` 返回跳过名单
  （node/mask/display name）呈 transfer 对话框；`ImportPackage` 的 `MaskModelFromJson`
  拒收 kind `ai_segmentation`。理由：AI Mask 描述本图内容。
- **几何指纹**（P6/M13/D9）：XXH3-128 over Develop 字段 canonical JSON（demosaic/
  highlights/lens 12 字段）；SM7 只对 fingerprint ≠ 当前的 AI Mask 标注失配（不重算
  mask、不修蒙版——用户删旧建新）；notice 文本仅列失配 mask 名单。

### 1.8 性能与内存（master plan §8.2 + charter §2.1）

encoder 191ms/图（CoreML）、decoder 33ms、S3OD 531ms/图、全载 3.19GB（M4）。
Path 工具的迭代本质 = 同 embedding 上多次 decoder 调用（decoder-only 增量成本低）。

---

## 二、我方盘点（file:line，HEAD 实测）

### 2.1 服务层（LightamerCore/Sources/AI/）

| 件 | 位置 | 现状 |
|---|---|---|
| Layer B `segmentSubject` | `AIMaskService.swift:285-329` | seed point/box + refine included/excluded 向量 + quality + ROI + 模型三态门（notReady/downloading/failed → typed `modelNotReady`）；输出 quality 级分辨率 float plane |
| Layer B request 装配 | `AIMaskService.swift:366-418` | `buildLayerBRequest` 唯一装配路径：seed 点/框 + **refine 逐点 `addIncludedPoint`/`addExcludedPoint`**（:402-409）；我方点预算 gate 先于 Vision 抛 typed |
| Layer B patch 腿 | `AIMaskService.swift:350-362` | `segmentPatch` = ROI 形状薄封装（同装配路径零二路） |
| 点预算 | `AIMaskTypes.swift:94-98` | `AIPointBudget.pointSeeded = 13`（seed 计 1）/ `boxSeeded = 11`；Y-flip 单缝 `visionPoint`（:33） |
| Layer A | `AIMaskService.swift:150-277` | `detectInstances`（两段式）+ `subjectMask`（label composite——`generateScaledMask` macOS 27.0b 双坏禁用：subset 语义 + 几何偏移 3/16，:176-183 注记 upgrade seam） |
| person 实例族 | `AIMaskService.swift:480-613` | `detectPersonInstances`（`GeneratePersonInstanceMaskRequest` macOS 15+，OS 内建零下载门）→ catalog + `personInstancePlane`（label composite）+ `personInstanceMask`（`unionSelection` max-fold :588-613）——**People 任务的完整服务面已存在** |
| person matte | `AIMaskService.swift:428-447` | `personSegmentationMask`（skin 链腿） |
| Layer B 设备 pin | `AIMaskService.swift:657-680` | macOS 27.0b Vision bug：任何 pin SIGTRAP → typed 拒绝；unpinned = run-to-run byte-identical |
| 多格式读回 | `AIMaskService.swift:723-789` | L008/L00h(LE UInt16)/L00f(half)/OneComponent32Float/RGBA 全族 |

### 2.2 会话与交互（App/Sources/Lightamer/）

- **SegmentSession**（`LayerEditingState.swift:691-862`）：seed + included/excluded 点集 +
  增点预算 gate（:824-844 typed throw）+ `recordSeed` 替换清空（:810）+ livePlane/patches≤4
  FIFO/1s patch debounce/featherPercent ±100（M6-4-02）+ N-1 身份守卫。**无删点、无 session
  undo 栈、无 Path、无 click level、无任务蒙版组件**——单 group 单对象形态。
- **SegmentEditingOverlayHost**（`UI/Overlay/SegmentEditingOverlayHost.swift`）：click=seed/
  include、⌥-click=exclude、⇧-drag=seed box（:104-154）；**先攒点后 confirm**（非逐点即解）；
  confirm 按钮 = `segmentSubject` → `commitRasterMask`（:231-264）；Done 按钮 = 退出模式；
  counter badge（used/budget，满转红）；SegmentPointsCanvas accent/orange 点 + 黄虚线框。
- **AIMaskEditing.commitRasterMask**（`State/AIMaskEditing.swift:157-296`）：upsample→
  resolveFeather→`RasterMaskStore.bake`→mask slot 写 + `bumpContentRevision` → **恰 1 条
  stackSnapshot history item** → hot layer + display tint 0.85 + activateTool(.brush) =
  **AI-06「落成普通 raster 蒙版」非黑箱形态**；same maskID overwrite re-bake（D-07-CONTEXT-5）。
  **AI 生成参数永不持久**（:21-24 注记——quality/seeds/refine points 皆 UI 态，sidecar 零新键）。
- **五源标记**（`AIMaskEditing.swift:29-62`）：`AIMaskSource` = subject/segment/skin/depth/
  person；`fileName(forLayerID:)` = `"<source>-<layerID>.png"`——**AI bake 蒙版的唯一识别面**
  （re-entry 标记现役消费 = segment 源）。
- **Layer B 入口三态门**（`AIMaskEditing.swift:67-94` `AIMaskEntryGate`）：ready/downloading/
  needsDownload(disabled+guided)/failed。

### 2.3 Feather / Expand / Refine

- **AIMaskFeather**（`LightamerCore/Sources/AI/AIMaskFeather.swift`）：percent ±100 → σ =
  `|p|/100 × 2% × longEdge`（:54-58，LightCraft 口径）；正腿 = 既有 GPU bake 缝
  （`RasterMaskStore.bake(featherRadius:)` → `MaskCombiner.blur` Deriche IIR）；负腿 = CPU
  logit-gain `x^g/(x^g+(1−x)^g)`、g∈(1,8]（:69-88，0.5 等值线不变、过渡收窄）；**双腿互斥
  pin**。**语义差**：上游 feather_px 绝对像素 [0,50]；我方 percent 相对（2% 长边）——对齐时
  需单位换算裁决。**Expand：全仓无对应算子**（负 percent 的 logit-gain ≠ 形态学腐蚀——
  不移动 0.5 等值线；上游 expand_px<0 = 真 erode 移边界）。
- **MaskRefine**（`LightamerCore/Sources/AI/MaskRefine.swift`，LUMEN-C）：lumen MIT `fine()`
  五步采样抠图（band/spread/projection/gate/blend），fineEdge 4096，CPU Accelerate 零新 kernel；
  `fineAutoTrigger` 挂 commitRasterMask 尾（`AIMaskEditing.swift:105,254-256`）。
  **Alcedo 无对应件**（U3 明示不做边缘后处理）——我方超集。
- **RasterMaskStore.bake**（`LightamerCore/Sources/Sidecar/RasterMaskStore.swift:88-116`）：
  r32Float → （featherRadius>0.1 时 GPU Deriche blur）→ uint16 量化 → gray16 PNG →
  StableHash → `<原图>.lra.masks/<maskID>.png`；load = hash 先验 + 失败 degrade all-ones
  typed reason；`loadPlane`（:191-201）无 Metal 读回（MaskRefine quick-alpha 源）。

### 2.4 视口显示通道

- **overlay 三态**（`LayerEditingState.swift:69-76`）：`MaskOverlayStyle` =
  translucent/rubylith/onBlack——**display 样式枚举，不入 record/history/sidecar**。
- **消费点**（`PipeCoordinator.swift:227-230, 2434-2452`）：`maskOverlayRequest = (layerID,
  strength 0.85, style)` → render 尾 `applyMaskOverlayIfRequested` 合成进 `displayTexture`
  （07-3 T1 起任何 payload 含 raster 皆可 tint）。**形态 = 渲染后期 tint 合成腿，非独立
  presentation 通道**——与上游「专属 RGBA32F 红通道」结构不同、语义近似（tint 显示不改像素
  真相一致；改的是合成位置与复用面）。
- newest-wins 门：过期帧不付 overlay pass。

### 2.5 paste 面（差距发现，非对齐项）

- `AdjustmentTransfer.buildPayload`（`State/AdjustmentTransfer.swift:167-205`）：**layer.mask
  随 payload 走**（raster ref 保留，仅 `contentRevision` 置 nil 重开 epoch :193-195）。排除谓词
  `isAdjustmentTransferable`（:36-40）只管 **chain instance**（terminal trio + owner==grade），
  **mask 无排除面**。我方 AI 蒙版已 bake 成普通 raster → paste 到他图 = 把「描述本图内容」的
  蒙版复制过去——恰是上游 D18 拒绝的行为。M9AIM-03「paste 跳过 AI mask 面」需要**识别面**
  （`AIMaskSource.fileName` 前缀是现役可判据）。

### 2.6 测试与实测基线

- **测试分布**（BUNDLE-MAP）：AI 面测试 = Layers bundle（`AIMaskSemanticTests` 10 /
  `AIMaskDeterminismTests` 6 / `AIMaskEditPathsTests` 6 / `AIMaskFeatherTests` 6 /
  `AIMaskPlaneFormatTests` 3 / `PersonInstanceMaskTests` 5 / `AIPatchAssemblyTests` 9 /
  `AIMaskGeometryTests` 6）+ App bundle（`AIMaskPatchFlowTests` 4 等）。
- **Layer B 迭代语义既有证据**（`Tests/LightamerTests/AIMaskSemanticTests.swift:220-244`）：
  `testLayerBSeedNonEmptyAndExcludedPointDrops`——seed 主体上 + 中心 excluded 点再解 →
  主体区均值显著下降（probe margin 0.35→0.32）；**真模型门 = `ensureLayerBAssets()`**
  （test-built app entitlement 拦下载 → CI 形态 skip，模型 ready 环境绿）。点预算 typed
  throw（:246-284）。
- **确定性**（`AIMaskDeterminismTests.swift`）：Layer B unpinned 双跑 byte-identical。
- **延迟实测**（`.work/gsd/phases/07-ai-modules/07-1-DECISIONS.md:30`）：Layer B accurate
  **warm 85-126ms**（25-102MP 全档）、cold 5.5s（进程首启模型编译一次性）；Layer A warm
  14-16ms。「单次生成 ≤1s」门 warm 路径 PASS。

---

## 三、差距矩阵（M9AIM-01..03 逐条）

### M9AIM-01 任务蒙版三件 + Sky 留槽

| 面 | 上游 | 我方现状 | 差距与落点 |
|---|---|---|---|
| Subject | S3OD alpha | Layer A `subjectMask`（MaskToolbar「主体蒙版」现役入口 `MaskToolbarView.swift:353`） | **已有**；无「任务面板 icon」形态 |
| Background | 1−Subject | 「主体以外」sugar 已有（`MaskToolbarView.swift:380-395` inverted 腿） | **已有**（commitRasterMask `invert:` 腿）；需入任务面板 |
| People | S3OD + 逐人 toggle | `detectPersonInstances`/`personInstanceMasks`/`unionSelection` 服务面全有；UI = InstancePickerOverlay checkbox floater（一次性 bake） | **服务面零差距**；差距 = 无 People 列表 toggle 会话形态（现 = 全选/子集一次确认）与 person box 视口轮廓 |
| Sky | people_sky_head + SAM | **无**（Vision 无原生 sky API） | **砍留槽**（OQ-2A 生效）：第四槽 disabled 占位 |
| 面板形态 | 四 icon + People list | 散装菜单项 | 新建任务面板（见 §四方案 1） |

### M9AIM-02 viewport 交互 + coverage 显示

| 面 | 上游 | 我方现状 | 差距 |
|---|---|---|---|
| 迭代点增删再解 | 每步即解（decoder 33ms），组内点集重放（mask_input 链式） | 先攒点后 confirm（一次性全量重解 85-126ms warm）；增点有、**删点无**、改点无 | **交互节奏差**：无逐点反馈候选蒙版（上游核心体验）；Layer B API 无 session 概念——「再解」= 重攒点集重建 request（每次含 embedding 重算 85-126ms 级） |
| Path 工具 | 笔触等弧长 24px ≤16 点 → 16 个 include 点 | 无（`.scribble` = typed 拒绝 seam） | Layer B refine 向量可承载（16 点 ≤ 预算 12 富余边界待算：point seed 计 1 + 16 = 17 > 13 **超预算**——见风险 R-3） |
| click level 三级 | decoder 三 token | 无（Layer B 无多 mask 输出面） | **不可达**（API 无多级输出）——合法 parity 偏离候选 |
| 64 点/组 | group ≤64 | 13/11（Vision API 自身限制） | **不可达**——API 边界,如实偏离 |
| 点/框视觉 | 绿+/红− disc + stroke/box + 专用 cursor | accent/orange 点 + 黄虚线框 + counter badge | 视觉细化件（小） |
| coverage 淡红 tint 候选态 | 专属 RGBA32F 通道 + maskCoverageTintColor + Commit 后隐藏 | overlay 三态（translucent/rubylith/onBlack）走 render 尾合成腿；commit 后 tint 常亮（mask edit mode + 0.85 strength） | **候选态 coverage 显示缺**（生成中无候选蒙版可显——因无逐点即解）；「Commit 后隐藏」与我方「commit 后 tint 常亮显蒙版」语义相反（我方 AI-06 形态 = 落成普通蒙版 + 编辑模式,tint 是「显示蒙版」affordance 非 AI 候选）——**语义对齐需裁决而非照搬** |
| overlay 三态关系 | — | translucent/rubylith/onBlack 既有 | coverage tint 若新增 = 第四显示态 or 复用 rubylith（红 scrim 语义最近）待裁决 |

### M9AIM-03 GPU Feather/Expand + 会话语义

| 面 | 上游 | 我方现状 | 差距 |
|---|---|---|---|
| Feather 正向 | σ=feather_px ∈[0,50] 绝对像素,可分离高斯 | percent±100 → σ=2% 长边（相对）,GPU Deriche | **已有算子**；单位口径差（绝对 px vs 相对 percent）——面板化时二选一 |
| Feather 收紧(负) | 无对应（负 feather 不存在,expand<0 = erode） | logit-gain（0.5 等值线不变收窄） | 语义不同但都合法——保留我方（更保守不破边界）or 对齐 expand erode |
| **Expand** | `\|expand\|` 步 3×3 交替 cross/square dilate/erode,R8/等值域 | **无任何形态学算子**（grep 全仓无 expand/dilate iop 面） | **真缺口**：GPU 形态学 kernel（新 kernel 家族申报面）或 CPU/加速库形态（MaskRefine 有 chamfer/running-max 先例但那是 refine 内部件） |
| 会话 open/commit/cancel | session 栈 + lease + asset + 1 条主 op + cancel 零发布 | 无会话语义——confirm 即 bake 即 1 条 history（commit 形态已有）；Cancel = Done 按钮（模式退出,已 bake 的不撤销）；「open 既有 AI mask 再编辑」无（refine re-entry 仅 segment 源 = 重攒点重解） | **范式差**（charter 已裁：保持我方 bake-to-raster）——需最小会话化：进入/退出边界 + cancel 丢弃未 confirm 生成物 + 「编辑既有蒙版」= refine re-entry 扩展 |
| paste 排除 | 不拷 AI Mask + 跳过名单 | `layer.mask` 随 payload 走,raster ref 无识别 | **真缺口**：识别面（fileName 前缀）+ 排除/跳过名单 |
| 几何指纹 | XXH3-128 Develop 字段 + 失配 notice | 无（raster mask 对 decode/lens 变更同样不校正,亦无提示） | charter 落地路径 5 已列（提示件,非本 M9AIM 硬验收）——建议挂账 M9AIM-03 附加或后续批 |

---

## 四、方案骨架（交钥匙缝导向）

> 原则（charter 已定）：零新模型、零 SPM；bake-to-raster 非黑箱范式维持 = 上游
> AI-Mask-source-kind/asset/lease/sidecar 面全部**不引入**（合法 parity 偏离）；交互体验
> （逐点反馈/任务面板/Path/Expand）为主战场。

### 1. 任务蒙版面板（M9AIM-01）

- **宿主**：`MaskToolbarView` 扩展（现役 AI 入口群旁）——四 icon（Subject/Background/
  People/Sky-disabled）+ People 子列表（InstancePickerOverlay 的 checkbox 形态改 toggle
  逐人增量 bake 或保持子集一次确认——见 OQ-3）。
- **Background** = Layer A subject + `invert: true`（`commitRasterMask` 现役腿,零新服务面）。
- **People** = `detectPersonInstances` + `unionSelection(.subset)`（服务面全复用）；person
  box 视口轮廓 = InstancePickerOverlay 已有预览 tint 通道,box outline = SegmentPointsCanvas
  同款 Canvas 绘制扩展。
- **Sky 槽**：disabled icon + tooltip（OQ-2A 生效值),不建死代码路径。
- **新键族**：`ai_task_*` 面板族（xcstrings 尾插惯例）。

### 2. 迭代交互升级（M9AIM-02 主件）

- **逐点即解**：SegmentSession 增「点变更 → debounce 重解 → 候选 plane 持有」腿（Layer B
  warm 85-126ms/步,ProgressView spinner + 保留旧候选显示 = 上游「推理期间保留旧 coverage」
  语义）。候选 plane = session 态（不 bake 不 commit,Confirm 才走 commitRasterMask——
  **恰好就是我方既有 confirm 形态**,只加中间反馈层）。
- **候选 coverage tint**：候选态激活时 `setMaskOverlayRequest` 复用既有腿（style 淡红
  = rubylith 近亲或新增第四 case `candidate`——OQ-4）;Confirm 后回落既有「普通蒙版 + tint
  常亮」AI-06 形态（**Commit 后隐藏不上游照搬**——上游隐藏的是 coverage 通道,我方 tint 是
  蒙版编辑 affordance,语义不同,OQ-4 一并裁）。
- **删点/改点**：SegmentSession 增 `removePoint(at:)`/点点击删除（上游靠 session undo
  覆盖;我方无栈,最小面 = 点级增删 + 「重来」按钮 = `recordSeed` 重置,session 级 undo/redo
  栈**不建**——OQ-5 裁最小面 vs 栈）。
- **Path 工具**：`.scribble` seam 激活——笔触等弧长采样（上游 24px/≤16 点参数照抄,
  `MapItemStrokeToAiMaskPromptPoints` 行为对照）→ included refine 点序列投喂。**预算冲突
  见 R-3**（16 点 + seed > 13 预算 → 采样点数上限收敛到预算内 or 递减采样,OQ-6）。
- 点视觉细化：绿 +/红 − disc（上游色值行为对照）+ busy cursor 态。

### 3. GPU Expand 算子（M9AIM-03）

- **落点**：`RasterMaskStore.bake` 前置形态学 pass——与 feather 同缝（bake 时一次 GPU）,
  不动已 bake PNG。kernel = 3×3 dilate/erode（交替 cross/square 行为对照,上游
  `ai_mask_coverage.cl` 直接参照——GPL 只读,算法形态学为公开数学）。
- **kernel 家族申报**：新 compute kernel 入 `MaskPostProcessKernels`（Deriche 邻位）或新
  .metal——**M8 先例红线：新核新 kernel 家族须解封申报**（零新 kernel 红线语境下的显式
  例外申报,plan 期立项）。
- **参数面**：feather percent 既有 slider 旁 + Expand slider（单位裁决 OQ-7：绝对 px
  [−50,50] 对齐上游 vs 相对 percent 统一我方 feather 口径）。
- **golden**：对称半径/边界行为（M9AIM-03 验收形态）——膨胀步数→边界外扩像素数精确
  断言（cross/square 交替的八角距离变换性质）+ 与 CPU 参考实现逐字节。

### 4. 会话三命令（M9AIM-03）

- **open**（新建）= 现役「点击选取」模式进入（armSegmentSession）——**已有**。
- **open**（编辑既有）= refine re-entry 扩展：`.segment` 源现役（`AIMaskSource.source(
  ofFileName:)` 判据 + `armSegmentSession`）→ 扩到 `.subject`/`.person` 源（判据现成,
  语义 = 重生成覆盖 bake,零模型缓存差异——**不含**上游 M15「存储 coverage 直显零模型」
  〔我方无 AI source kind,重开即重解,合法偏离〕）。
- **commit** = 现役 Confirm（1 条 stackSnapshot）——**已有**。
- **cancel** = 新增：退出模式时丢弃未 confirm 的候选 plane（现形态 = 攒点未 confirm 本就
  未 bake,天然 cancel;升级点 = 逐点即解候选态后,「已解候选未 confirm」的丢弃面 +
  Done/Escape 语义收敛为 Cancel）。
- **paste 排除**：`buildPayload` 蒙版腿加识别——`AIMaskSource.source(ofFileName:) != nil`
  的 raster ref 不入 payload（或入跳过名单 toast/对话框列名,上游 M17 行为对照）。
  **注意**：bake 蒙版文件名前缀是识别面,但用户手动 brush 蒙版无前缀——排除面只及 AI bake
  件（语义正确：描述本图内容的恰是 AI 件）。验收 = paste 排除负测（M9AIM-03 验收形态）。

### 5. 不做清单（合法 parity 偏离,charter 声明面）

上游 AI-Mask source kind / R8 asset 表 / sidecar 进程 / 模型下载面板（Layer B 已有
DownloadableAssets 三态门）/ M16 lease / M11 reachability / SM7 几何指纹 notice（挂账）/
S3OD 联合双边上采样（Vision 输出自带分辨率与软边）/ click level 三级（API 不可达）/
64 点组（API 13/11 上限）。

---

## 五、探针结果

| 项 | 结果 |
|---|---|
| guard 前置 | 首查：R6 探针 GUI 窗在跑（`-la_film_probe`，G1 block）→ **让位**；二查空窗 → GUARD PASS（heavy=0 free=68%） |
| 定向探针 | `Scripts/test-direct.sh --bundle Layers 'AIMaskSemanticTests'` = **10/1/0，peakRSS=214MB，4s**；探针后进程清场确认（ps xctest 零命中） |
| 1 skip 剖析 | `testLayerBSeedNonEmptyAndExcludedPointDrops` 真模型门（`ensureLayerBAssets()`——test-built app entitlement 拦 DownloadableAssets 下载）；纯逻辑面（点预算 13/11 typed、scribble 拒绝、gate 状态机、首启策略）全绿。excluded 再解语义证据 = 该测试 07 批真机绿记录（probe margin 0.35→0.32 在测试注释在案）+ 读码（`buildLayerBRequest:402-409` refine 向量全量进 request） |
| 迭代再解机制判定（读码） | Layer B API **无增量 session 概念**：每次 `segmentSubject` = 全新 request 全量重解（无 SAM mask_input 链式迭代面）。「增删点再解」可行但每步含 embedding 重算（warm 85-126ms 实测基线,07-1-DECISIONS:30）——逐点即解的体验成本可控（vs 上游 decoder-only 33ms）,但**无上游「组内重放同结果」保证**（每步独立重解,结果可能微漂——byte-identical 仅在同输入同设备下成立,DeterminismTests 在案） |
| Vision person 路线（读码,任务书允许形态） | `GeneratePersonInstanceMaskRequest` 输出 `InstanceMaskObservation`（与 Layer A 同型）→ `labelComposite` 共腿提取（`AIMaskService.swift:235-267` 注记「layer A AND the person-instance family」）→ People 任务 = `personInstanceMasks` + `unionSelection` 现役,零适配 |

---

## 六、风险与 OQ-M9-1 期新开点

### 风险

- **R-1 Layer B 能力边界（如实登记）**：点预算 13/11（Vision API 限制,上游 64 不可达）；
  无多 mask 级输出（click level 不可达）；每请求全量重解无链式迭代（85-126ms/步 warm、
  cold 5.5s 首启——逐点即解 UI 需 spinner + 保留旧候选,防冷启动卡感）；**无 embedding
  缓存面**（上游 4 张 embedding 缓存免付——我方每步重算,大图多步会话的累计延迟需在
  plan 期预算;Vision 内部或有缓存但无 API 面可依赖）。
- **R-2 paste 排除识别面的脆弱性**：fileName 前缀判据依赖 `AIMaskSource` 拼写稳定
  （五前缀在案）,用户 rename masks 目录文件会破坏判据（hash 校验已会 degrade——排除
  面对 degrade 蒙版的行为需定义:保守 = 只排可识别 AI 件）。
- **R-3 Path 点数 vs 预算冲突**：上游 16 点/笔 + seed > 我方 pointSeeded 13——Path 采样
  上限须收敛（如 12 点含 seed,或 box-seeded Path 形态 11）,体验降级需明示。
- **R-4 Expand 新 kernel 家族申报**：零新 kernel 红线语境（M8 先例 = 新核新 kernel 家族
  须解封申报）——3×3 形态学虽小,仍是新 GPU kernel;替代 = CPU vImage erode/dilate
  （Accelerate 现成,MaskRefine CPU 先例）——GPU vs CPU 的 plan 期裁决（100MP 级蒙版
  CPU 形态学耗时需探,但蒙版是单通道 0/1 域,chamfer/running-max 先例显示可控）。
- **R-5 逐点即解的 history 语义**：候选态多步重解不进 history（session 态）,Confirm 恰
  1 条 stackSnapshot——与现役一致,但「确认后再次进入 refine 再 confirm」= 第 2 条
  history（现役 re-bake 同 maskID 但每次 commit 一条）——与会话语义「Commit 后会话结束」
  的边界要在 plan 期定义清楚。
- **R-6 范式偏离的验收口径**：AI-06 非黑箱形态与上游「Commit 后 coverage 隐藏」「AI Mask
  是独立 source kind」多处语义相反——验收样例须先与用户对齐（§12.3 修复批铁律:动工前
  对齐验收样例）,避免照抄上游断言做假修复。

### OQ-M9-1 期新开点（plan 期或用户裁决）

| OQ | 问题 | 推荐 |
|---|---|---|
| **OQ-1（新）** | 逐点即解（每点 85-126ms 候选重解 + spinner）vs 保持先攒点后 confirm（现状,零延迟反馈） | **逐点即解**（上游核心体验;debounce 300ms + 保留旧候选 + spinner 承接;冷启动首步 spinner 提示模型就绪态） |
| **OQ-2（新）** | People 子列表形态：逐人 toggle 增量 bake（上游式,每次 toggle = 一次 commit）vs 子集一次确认（现状 InstancePickerOverlay） | **子集一次确认**（我方无 session 栈,逐 toggle bake = 多条 history 噪声;InstancePicker 复用面最大;偏离登记） |
| **OQ-3（新）** | 候选 coverage tint：复用 rubylith（红 scrim 近亲）vs 新增第四 style case `candidate`（淡红 #515 行为对照） | **新增 `candidate` case**（display 样式枚举 additive,不入 record——三态语义不被 AI 候选占用;CaseIterable 消费面全枚举一处编译期收口） |
| **OQ-4（新）** | Commit 后 tint 命运：维持 AI-06（普通蒙版 + tint 常亮 + brush 编辑）vs 上游（coverage 消失,回到照片） | **维持 AI-06**（charter 已裁范式偏离;「Commit 后隐藏」属 coverage 通道语义,我方无通道） |
| **OQ-5（新）** | session undo/redo 栈：不建（点级增删 + 重来按钮最小面）vs 建（上游 D16 体验对齐） | **不建**（M9AIM-03 验收形态只列 open/commit/cancel 三命令;栈 = 后续批按需;点级删点 + recordSeed 重置覆盖 80% 场景） |
| **OQ-6（新）** | Path 采样点数上限（预算 13/11 冲突） | **按 seed 形态收敛**（point-seeded: 12 采样点 + seed = 13 满;box-seeded: 11 采样点;等弧长采样点数 = min(16, 预算余量),UI 计数器已有面） |
| **OQ-7（新）** | Feather/Expand 单位口径：绝对 px（上游 [0,50]/[−50,50]）vs 相对 percent（我方 feather 现役 ±100） | **面板双轨呈现（px 输入,内部换算 percent）或直改绝对 px**——倾向绝对 px 对齐（蒙版 bake 分辨率已知,绝对像素语义更直;旧 percent 面继续兼容 = M6-4-02 slider 面平移换算） |
| **OQ-8（新）** | paste 排除形态：静默排除 vs 跳过名单提示（上游 M17 列名） | **跳过名单 toast/对话框列名**（与 transfer 面既有 greyed+count note 风格一致） |
| **OQ-9（新）** | Expand 实现：GPU 新 kernel（申报解封）vs CPU Accelerate vImage 形态学（零新 kernel） | **CPU vImage 先行**（零新 kernel 红线最稳;bake 缝是异步的,CPU 形态学挂同缝;100MP 单通道 0/1 域耗时 plan 期探针定;GPU 申报留升级 seam） |
| **OQ-10（新）** | 几何指纹 notice（上游 SM7/D9 类）入不入本批 | **不入**（M9AIM 验收形态无此项;charter 落地路径 5 已列 = 提示件;挂 UPSTREAM-QUEUE 或 M9AIM-03 附加,plan 期与 orchestrator 定） |

---

## 七、汇报口径（供 orchestrator）

- **上游全流程一句话**：Alcedo AI Mask = icon 工具面板（Subject/Background/Sky/People 四
  任务 + Point/Box/Path 三 prompt 工具 + Feather/Expand + session Undo/Redo + 唯一
  Confirm 按钮）驱动 SAM 2.1+S3OD sidecar 逐点即解,候选 coverage 经专属 RGBA32F 视口通道
  淡红 tint 显示,Commit 写 content-addressed R8 asset + 1 条主 history op,Cancel 零发布,
  paste 不拷 AI Mask。
- **我方最大复用件三件**：① Layer B 服务面（`AIMaskService.swift:285-329/366-418`——
  seed/refine/ROI/门控全就绪,迭代再解 = 重攒点集重调用）;② commit/bake 通道
  （`AIMaskEditing.commitRasterMask:157-296` + `RasterMaskStore.bake:88-116`——AI-06
  范式恰是上游 Commit 的我方等价物,含 same-maskID re-bake）;③ person 实例族
  （`AIMaskService.swift:480-613` detect→labelComposite→unionSelection,People 任务服务面
  零差距）。
- **最大缺口一件**：**Expand 形态学算子全仓缺失**（无任何 dilate/erode iop/kernel 面;
  Feather 已有 GPU 缝可复用,Expand 是唯一真新建算子——CPU vImage 零新 kernel 路线为
  推荐）。次缺口 = 逐点即解候选反馈（交互层,非算子层）。
- **新开 OQ 数量**：10（OQ-1..10,见 §六表;含 3 个范式偏离显式化裁决）。
- **探针结论**：guard 让位 R6 后空窗跑 `Layers/AIMaskSemanticTests` 10/1/0（214MB/4s）;
  Layer B 迭代再解机制 = **全量重解无链式迭代**（warm 85-126ms/步可承载逐点即解,无
  embedding 缓存面 = 大图多步累计延迟 plan 期预算）;真模型 excluded 再解语义证据 =
  07 批真机绿 + 读码（CI 形态 entitlement skip 属既知形态非回归）。

---

## 附：上游 file 级出处速查（origin/main）

| 面 | 文件 |
|---|---|
| master plan（D1-D23/P1-P8/§1.5 replan） | `docs/roadmap/alcedo_studio/edit/ai_segmentation_mask_master_plan.md` |
| SM9 工具面板 + SM7 notice | `docs/roadmap/.../ai_segmentation_mask/phase_sm9_tool_and_sm7_notice_plan.md` |
| SM5 会话/asset/paste 决策 M1-M21 | `docs/roadmap/.../ai_segmentation_mask/phase_sm5_ai_mask_source_and_session_plan.md` |
| 会话状态机 | `alcedo_studio/src/include/app/ai_mask_edit_session.hpp` |
| prompt 几何（24px/≤16 点/ReferenceSpace 映射） | `alcedo_studio/src/include/ui/edit_viewer/ai_mask_prompt_geometry.hpp` |
| 输入 overlay 视觉（色值/尺寸/cursor） | `alcedo_studio/src/include/ui/edit_viewer/ai_mask_input_overlay_geometry.hpp` |
| coverage 合成（fold/联合双边/guide） | `alcedo_studio/src/include/app/ai_mask_coverage_composition.hpp` |
| Feather/Expand GPU（OpenCL 参照实现） | `alcedo_studio/src/edit/runtime/opencl/shader/ai_mask_coverage.cl` |
| Feather 权重 + host 参考 | `alcedo_studio/src/edit/mask/ai_mask_coverage_texture.cpp:30-130`（σ→getGaussianKernel round(8σ+1)\|1）/ `.../ai_mask_coverage_work.hpp:69-103`（margin/交替核/radius≤200） |
| Metal 后端 | `alcedo_studio/src/edit/runtime/metal/metal_ai_mask_coverage.mm`（kernels 在 shader/mask.metal） |
| UI 工具控制器（属性/入口/previewEdge/acceptEdge） | `alcedo_studio/src/include/ui/alcedo_main/album_backend/editor_ai_mask_tool.hpp` |
| segmentation DTO（point label 0/1/mask_input/People 列表/task 枚举） | `alcedo_studio/src/include/sidecar_client/dto/segmentation.hpp` |
| paste 排除（M17） | `alcedo_studio/src/app/adjustment_transfer_package_builder.cpp`（SM5 plan §3.1 表） |

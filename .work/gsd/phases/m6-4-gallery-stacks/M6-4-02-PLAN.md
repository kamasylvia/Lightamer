---
phase: m6-4
plan: "M6-4-02"
title: "AI 分割蒙版原生集成 spike——hi-res patch 组装（层 B ROI+quality 延迟重析 + patch 边界规划/合成纯函数 + ≤4 帽 + App 侧 1s debounce）+ Edge 羽化 ±100 参数化（sigma 映射纯函数 + 烘焙缝 CPU 可分离高斯 + 负值收缩 = 1−blur(1−x)，零新 kernel）+ GeneratePersonInstanceMaskRequest 人物实例蒙版入口（蒙版类型菜单新项 + 实例勾选复用 07-3 形）+ spike 达标判据核验与 GUI 真机轮 + Describe 原生不可达收口与 V2 挂账"
wave: 1
depends_on: []
autonomous: true
requirements: ["M6INT-03（REQUIREMENTS :410）"]
estimated_tests: "+21..25"
test_bundles: [LAYERS, APP]
files_modified:
  - LightamerCore/Sources/AI/AIPatchAssembly.swift        # 新建：AIPatchPlanner 纯函数（掩码覆盖 bbox + pad 内缩 + 图界 clamp + 最小尺寸地板 + 全帧掩码 skip 门）+ AIPatchComposer 纯函数（hi-res patch 平面在 patch 界内拼回基础平面 + 接缝线性 ramp 羽化 + ≤4 patch 帽，KD-1）
  - LightamerCore/Sources/AI/AIMaskService.swift          # 修改：additive segmentPatch(input:seed:refine:patchRect:quality:device:assets:)（= segmentSubject 的 ROI 定点形，buildLayerBRequest 既有 ROI 面消费）+ personInstanceMasks(input:device:assets:)（GeneratePersonInstanceMaskRequest 主进程直调 + buildPersonInstanceRequest 可测组装面，KD-2/KD-4）
  - LightamerCore/Sources/AI/AIMaskFeather.swift          # 新建：sigma 映射纯函数（percent −100...100 × longEdgePixels → 半径 ≤2% 长边 → Gaussian sigma，clamp + 端点恒等）+ applyFeather(plane:percent:)（正 = 可分离高斯；负 = 1−blur(1−x) 收缩；0 = 原平面返回，KD-3）
  - App/Sources/Lightamer/State/AIMaskEditing.swift       # 修改：bake 缝羽化接线（会话羽化值 → applyFeather 于 upsample 后 bake 前；0 = 字节恒等短路）+ patch debounce 调度（末次精修交互 1s 静默 → patch 重析 → 会话活平面拼回），KD-3/KD-1
  - App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift # 修改：蒙版类型菜单新项「人物实例」（07-3 蒙版工具族 additive）+ 羽化滑杆（−100...100，会话域，KD-5）
  - App/Sources/Lightamer/State/LayerEditingState.swift   # 修改：SegmentSession additive 羽化值 + patch 状态面（idle/refining/done 计数）——UI 态不入 sidecar/params（KD-3 会话域裁定）
  - Resources/Localizable.xcstrings                       # 修改：5 新键尾块纯插入（mask_tool_person_instance / mask_feather_label / mask_feather_reset / mask_patch_refining / mask_person_none）
  - Tests/LightamerTests/AIPatchAssemblyTests.swift       # 新建（LAYERS，9 法）：planner bbox/pad/clamp/skip 门 + composer 拼接精确性/接缝 ramp/Y-flip ROI/帽/确定性
  - Tests/LightamerTests/AIMaskFeatherTests.swift         # 新建（LAYERS，6 法）：映射 golden 表 + clamp + 零恒等字节面 + 单调性 + 负值收缩 CPU 参照 golden + 长边归一
  - Tests/LightamerTests/PersonInstanceMaskTests.swift    # 新建（LAYERS，4 法）：请求组装 typed 面 + 选中并集 + 空结果分类 + 平面格式面
  - Tests/LightamerTests/AIMaskPatchFlowTests.swift       # 新建（APP，4 法）：debounce 合并 + 羽化→bake 参数面 + 菜单项路由 + 重烘同 maskID 覆写
  - Project.swift                                         # 修改：四新测试文件登记对应 target 数组（显式清单无 glob）+ `tuist generate` 恒为该批最后一个动作（L041）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt # 修改：四新行登记（E2 纪律，随各自任务 commit）
  - AGENTS.md                                             # 修改：M6-4 架构增量节（面 B 段 + spike 判据表，T6）
  - .work/gsd/ROADMAP.md                                  # 修改：M6-4 行 ✅（phase 收口）
  - .work/gsd/REQUIREMENTS.md                             # 修改：M6INT-03 兑现终态注记
  - .work/GOAL-STATE.md                                   # 修改：续接点（phase 收口态）
  - .work/TODO.md                                         # 修改：M6-4 条目翻账
  - .work/LESSONS.md                                      # 如踩坑
  - .work/gsd/phases/m6-4-gallery-stacks/M6-4-02-SUMMARY.md    # 新建（T7——含 §spike 结论落档）
  - .work/gsd/phases/m6-4-gallery-stacks/M6-4-02-DECISIONS.md  # 新建（T7——KD 偏差 + 羽化缝选择申报 + 烘焙时域语义 + GUI 轮证据指针）
  - .work/gsd/phases/m6-4-gallery-stacks/M6-4-02-ACCEPTANCE.md # 新建（T7——双重验收串行）
  - .work/gsd/phases/m6-4-gallery-stacks/M6-4-VALIDATION.md    # 新建（T7——phase 签核：两 plan 汇总 + 全套 --all 终验数字 + C 档第 3 停面）
  - .work/gui-acceptance/m6-4/MANIFEST.md                 # 新建（T5——GUI 真机轮证据清单，R4）
---

# Plan M6-4-02 — AI 分割蒙版原生集成 spike（面 B 全量批）

> **性质**：M6-4 两 plan 之二（面 B；执行串行 01→02——01 落 schema v5 与
> 全套基线后本 plan 的全套对账数字才闭合）。规格正本 = 同目录 `RESEARCH.md`
> （面 B §B1-B5 + R2/R4）；裁决正本 = `M6-4-CONTEXT.md` 裁决记录
> （**OQ-M6-4-5/6/7 全按推荐，夜间全自动授权批 2026-10-14**，晨审可推翻）。
> 机制底座 = AI-01 已交付面（`AIMaskService.segmentSubject` :261 layer B 全
> 脸 + `buildLayerBRequest` :309 可测组装先例 + `AIMaskQuality` 三档 +
> `AIMaskResample` 上采样 + `AISubjectSeed.scribble` typed 拒缝）+ 07-3
> tap-to-segment UI（`LayerEditingState.segmentActive`/`SegmentSession` +
> `SegmentEditingOverlayHost`）+ `AIMaskEditing.swift` upsample→bake 缝。
>
> **基线**：plan 起草时全套 = **3759/24/0**（M6-3 终验亲证）；**对账基线 =
> plan 01 收口后全套**（预期 3811..3817/24/0——01 头部申报）。本批预期
> **+21..25**（三新 LAYERS 文件 19 法 + 一新 APP 文件 4 法 = 计划 23），
> 全套预期 **3832..3842/24/0**（= plan 01 收口值 + 本批，带两段记账滑差
> 余量；phase VALIDATION 终验对表）。

## 已定裁决（生效值，硬约束，不得重开）

M6-4 OQ-5/6/7（面 B 相关项）**全部按推荐裁**（CONTEXT 裁决记录 2026-10-14）：

1. **OQ-5 = A（能力组装范围）**：hi-res patch 组装入 spike 达标判据（判据
   细则 = 本 plan T4 定案）；Edge 羽化 ±100 参数化顺带。**零 SAM、零新
   模型、零下载依赖**——原生零模型成本路即全部工程面。
2. **OQ-6 = A（scribble 不激活）**：`AISubjectSeed.scribble` typed 拒缝
   原样保持；本 plan 零 scribble 工作；既有负测维持绿即合规。
3. **OQ-7 = A（Describe 挂账 V2）**：Vision 零文本分割 API（RESEARCH B2
   swiftinterface 全文 grep 实测）→ 本 plan 收口 = **「Describe 原生
   不可达」结论入档**（SUMMARY §spike + REQUIREMENTS 注记）；SAM CoreML
   大件 = V2 另裁，本 phase 零启动。

**裁决附带澄清（CONTEXT「裁决附带澄清」节的 plan 化）**：
- `GeneratePersonInstanceMaskRequest` = Vision 内置 struct API → **主进程
  Vision 直调**（`AIMaskService` additive，layer A/`personSegmentationMask`
  :371 同形）；**不入 M4-3 worker**（worker 四腿 = ONNX 第三方模型隔离面）。
- 零 VNStatefulRequest 工作（macOS 11 视频跟踪基类，与分割无关——ROADMAP
  行内问句的收口答案已由 RESEARCH B2 给出）。

**架构红线（本 plan 全程 + checker 机检面）**：
- **`.metal` 零 diff**（全仓任何 .metal 文件）；羽化/patch 全部走既有 kernel
  或 CPU 纯函数（零新 kernel 红线传承——M3-1/M5-3 同款）。
- **零新 SPM**；V50Order/封存面零触；六格式导出矩阵零触；MCP 快照族零触；
  sidecar schema 零触（羽化/patch/实例选择全会话域 UI 态，**不入 sidecar
  不入 params**——重烘覆写像素即真相，07-1 D-07-CONTEXT-5 语义延伸）。
- **Vision device-pin 纪律（R2）**：layer B 任何 pin 都 abort（27.0b beta
  bug）——`segmentPatch` 沿用 `segmentSubject` 既有 pin 拒面（`pin(_:to:)`
  typed refusal）；person 实例族 pin 面按 layer A 既有形（可 pin）。
- **生成失败 ≠ load 失败**：patch/羽化/实例任何失败 = typed error + 会话
  平面原样（永不降级 all-ones——AIMaskError 既有纪律）。
- **R4 验收形态**：layer B 资产测试宿主 entitlement 阻断（07-3 先例）——
  涉 layer B 真实推理的验收走 GUI 真机轮（证据 = `.work/gui-acceptance/
  m6-4/MANIFEST.md`）；单测面 = 纯函数（请求组装/平面组装/映射表），零
  Vision 执行依赖。
- xcstrings 5 新键尾块纯插入 + zh-audit 对账；LocalizationValue 插值禁形；
  runModal 禁入；UserDefaults 零新键；L041/L070/M2-7-3 parentage 照 plan 01
  同款执行。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 hi-res patch 组装（T1/T2，LightCraft「延迟 hi-res detail patch」的原生组装）

- **AIPatchPlanner**（纯函数）：输入 = 基础掩码平面（Float，行主序）+ 图像
  尺寸；语义 = 掩码覆盖 bbox（阈值 ≥ 0.5 的像素范围）→ 外扩 pad（bbox 短边
  的 25%，clamp 图界）→ patch 矩形；**skip 门**：bbox 面积 > 60% 全帧 →
  无 patch（全帧已由 accurate 直出，patch 无增益——登记规则）；掩码空 →
  无 patch；patch 最小边 < 32px → 无 patch（噪声域）。
- **AIMaskService.segmentPatch**（additive）：= `segmentSubject` 的 ROI
  定点形——种子 = 原会话种子映射进 patch 空间（point/box 与 patch 矩形的
  视口归一换算，Y-flip 走 `AIMaskPoint.visionPoint`/`AIMaskRect.visionRect`
  既有单缝）；精修点同映射；`quality = .accurate` + `regionOfInterest =
  patchRect`（`buildLayerBRequest` :309 既有 ROI 参数消费，**零改该函数**）；
  产物平面经 `AIMaskResample` 重采样到 patch 矩形的像素分辨率（layer B
  ROI 产物分辨率以运行时实测为准——执行期探针申报实际分辨率入 DECISIONS，
  合成面不受扰）。
- **AIPatchComposer**（纯函数）：hi-res patch 平面拼回会话活平面——patch
  界内 = patch 值；接缝 = 线性 ramp 羽化带（带宽 = patch 短边 5%，clamp
  2..16px）边界混合；patch 外 = 原平面逐字节；**帽 ≤ 4 patch/选择**
  （LightCraft 同值；超帽 = 最早 patch 被替换——FIFO，确定性）。
- **App 调度**：`AIMaskEditing` 会话内 additive——末次种子/精修交互后
  **1s debounce**（后续交互重置计时）→ 单次 patch 重析 → 会话活平面拼回 →
  重烘（同 maskID 覆写，D-07-CONTEXT-5 既有语义）。patch 状态
  （idle/refining/done 计数）= SegmentSession additive UI 态。

### KD-2 人物实例蒙版（T3，`GeneratePersonInstanceMaskRequest` macOS 15+）

- **AIMaskService.personInstanceMasks(input:device:assets:)**：主进程
  Vision 直调（KD 裁决澄清）；返回 = per-instance `AIMaskPlane` 数组
  （实例序 = Vision 观察序，确定性）；**零实例 = typed
  `AIMaskError.noSubject`**（复用既有「无主体」错误面，非 all-ones——
  生成失败纪律）。
- **buildPersonInstanceRequest(device:)** 可测组装面（`buildLayerBRequest`
  先例同形）：revision/quality 显式钉（运行时 supportedRevisions 探针
  申报入 DECISIONS）；pin 面 = layer A 既有形（可 pin，测试确定性）。
- **选中并集**：复用 `AIInstanceSelection`（all/subset）——选中实例平面
  max 并集 = 单 `AIMaskPlane` → 既有 upsample→bake 缝（07-3 layer A
  checkbox overlay 的交互形复用）。

### KD-3 Edge 羽化 ±100 参数化（T2/T3，缝选择 = 烘焙时域）

- **缝裁决（planner 定案）**：羽化落 **bake 时域**（`AIMaskEditing`
  upsample 后 bake 前，CPU `applyFeather` 作用于 Float 平面），**不落**
  `MaskCombiner.postProcess`/`effectivePlane` 缝（该缝的羽化参数只挂
  parametric payload——`MaskCombiner.swift` :623-635 亲核，raster-only
  spec 不达 postProcess；改 effectivePlane 面 = 侵入共享装配面 + 触
  sidecar params 字节域，违反会话域裁定）。理由 = 07-1 既有架构
  （「levels/seeds/refine 留 UI 态，只有烘焙像素进入」）的自然延伸：羽化
  是生成时属性，改羽化 = 重烘（同 maskID 覆写）；**重载后改羽化不在 v1
  范围**（平面已弃，只有 PNG——挂账 DECISIONS）。
- **AIMaskFeather**（Core 纯函数）：`sigma(percent:longEdgePixels:)`——
  percent ∈ −100...100；半径 = |percent|/100 × 0.02 × longEdge（LightCraft
  「≤2% 长边」语义，**执行期先读本地 LightCraft checkout
  `docs/ai-masks.md` Edge 羽化节核对符号语义**，有出入以 LightCraft 原文
  为准 + DECISIONS 申报）；半径 → Gaussian sigma（`maskGaussCoeffs`
  sigma 约定族同径）；端点 clamp。
- `applyFeather(plane:percent:)`：percent > 0 = 可分离高斯模糊（横竖双趟
  CPU，掩码分辨率平面量级有界）；percent < 0 = **收缩** = 1 − blur(1 − x)
  （形态学腐蚀的高斯近似——同一次 blur 原语复用 + 平凡反转，零新 kernel
  兑现 ± 全量程）；percent == 0 = 原平面**同引用返回**（字节恒等短路——
  零羽化 = 今日烘焙字节零漂移的机制本体）。
- **UI**：SegmentSession additive 羽化值（−100...100，缺省 0，会话域）+
  MaskToolbarView 羽化滑杆 + reset；改值 → 下次烘生效（重烘覆写）。

### KD-4 spike 达标判据（T4/T5，ROADMAP「判据 plan 期定」授权的定案）

| # | 能力 | 判据（可机检/GUI 双轨） | 落点 |
|---|---|---|---|
| 1 | 点击精修 | 07-3 已交付面回归绿（AIMask 既有套件零编辑全绿） | LAYERS 定向轮 |
| 2 | hi-res patch | 合成双分辨率 fixture：patch 腿边缘过渡宽度（10-90% rise，px）**≤ 0.6 ×** 同输出尺寸全帧腿；patch 拼接缝错位 ≤ 1px；帽 ≤4 强制；空/全帧掩码 skip 门 | LAYERS golden（T1 验收） |
| 3 | Edge 羽化 | 映射 golden 表（percent × longEdge → sigma 精确值）+ 0 恒等字节面 + 单调性 + 负值收缩 vs CPU 参照 golden | LAYERS golden（T2 验收） |
| 4 | 人物实例 | 请求组装 typed 面（单测）+ GUI 真机轮：多人 fixture 实例数 ≥2、逐实例平面非全零、选中并集正确、无人像 typed 报错 | APP 单测 + GUI 轮（R4） |
| 5 | Describe | **原生不可达收口**（RESEARCH B2 实测引用）+ V2 挂账行入档 | SUMMARY §spike |

- **GUI 真机轮**（T5）：layer B patch 真图一景 + 人物实例多人一景 +
  羽化走查（±两端 + 0），证据（截图 + 步骤 + 结论）= `.work/gui-acceptance/
  m6-4/MANIFEST.md`；**双验收 omp 二次验收可消费此 MANIFEST**。
- **结论落档**：SUMMARY §spike = 五行判定表 + 「达标即收」结案语 +
  V2 挂账清单（Describe/SAM CoreML/scribble 激活/重载后羽化编辑）。

### KD-5 UI 入口与键面（T3）

- 蒙版类型菜单（`MaskToolbarView` 蒙版工具族）新项「人物实例」——路由 =
  SegmentSession 会话形 additive（tap → `personInstanceMasks` → 实例
  checkbox overlay〔07-3 layer A 形复用〕→ 确认 → 并集 → 既有 bake 缝）；
  资产门复用 layer B 既有三态（人物实例为内置 API，**无下载依赖**——
  `assets` 参数在 person 路径不消费，签名保留对称性）。
- **xcstrings 5 新键**（尾块纯插入）：`mask_tool_person_instance` /
  `mask_feather_label` / `mask_feather_reset` / `mask_patch_refining` /
  `mask_person_none`。UserDefaults 零新键。

## read_first

1. `.work/gsd/phases/m6-4-gallery-stacks/M6-4-CONTEXT.md`（裁决记录）+
   `RESEARCH.md` 面 B（§B1 已交付盘点 / §B2 SDK 实测 / §B3 LightCraft SAM
   3 能力集 / §B4 对照表 / §B5 推荐）
2. `LightamerCore/Sources/AI/AIMaskService.swift`（:150 detectInstances +
   :184/:211 layer A 合成 + :261 segmentSubject + :309 buildLayerBRequest +
   :371 personSegmentationMask + :403 refusePin + :507 maskPlane——KD-1/
   KD-2 全部消费面）
3. `LightamerCore/Sources/AI/AIMaskTypes.swift`（Y-flip 单缝 + 预算 + 质量
   + 错误面）+ `LightamerCore/Sources/AI/AIMaskResample.swift`（上采样缝）
4. `App/Sources/Lightamer/State/AIMaskEditing.swift`（upsample→bake→
   MaskSpec.raster 缝 + D-07-CONTEXT-5 同 maskID 覆写——KD-1/KD-3 落点）+
   `App/Sources/Lightamer/State/LayerEditingState.swift`（:246 tap-to-
   segment + SegmentSession——patch/羽化会话态落点）
5. `App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift` +
   `SegmentEditingOverlayHost.swift`（蒙版工具族 + 07-3 overlay 交互形——
   KD-5 落点）+ `App/Sources/Lightamer/UI/Inspector/` 层 A 实例勾选
   checkbox 形（复用判据源）
6. `LightamerCore/Sources/Layers/Masks/MaskCombiner.swift`（:96-153 blur +
   :158-186 postProcess + :623-635 raster 不达 postProcess 的亲核位——
   KD-3 缝裁决的依据源，**只读不改**）
7. `/Volumes/UNITEK/Documents/Development/lightcraft/docs/ai-masks.md`
   （Edge 羽化 ±100 语义 + patch 语义原文——KD-3 符号核对 + KD-1 判据
   语义源；MIT OR Apache-2.0 思想移植零复制）
8. `Tests/LightamerTests/AIMaskGeometryTests.swift` +
   `AIMaskEditPathsTests.swift`（LAYERS AIMask 测试力学正本：平面构造/
   合成 fixture/typed 断言形）+ BUNDLE-MAP LAYERS 段（AIMask 五文件 :290-324
   归域先例）
9. `Scripts/test-direct.sh` + BUNDLE-MAP + AGENTS.md 07-1/M2-7/M4-3 架构
   增量节（AI/蒙版域红线文风）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits 全英文；只 add 相关文件）；
  新测试文件随各自任务 commit 登记 BUNDLE-MAP（E2）+ `Project.swift`
  （L041：`tuist generate` 恒末位）。
- **构建**：`caffeinate -dis` 包裹；单测 = `Scripts/test-direct.sh
  --bundle Layers` / `--bundle App`；**全套 `--all` 需 orchestrator 批准，
  phase 收口轮（T7）才申请**（8G 门 + MEMFAIL 机检 + 运行中监视）。
- **资源监控/parentage**（M2-7-3 教训）照 plan 01 同款。
- **L057**（本 plan 无模态对话框面——自然满足 + grep 机检）；**L070**
  不 push；中文待核标注显式化。
- 红线自证（T6）：`git diff <基线>..HEAD` 上 `.metal` 全零命中 + MCP
  快照族原样 + sidecar schema 零触（`LightamerSidecar.swift` 零 diff）+
  xcstrings 尾块纯插入 + UserDefaults 零新键 + dependencies 块零 diff +
  V50Order 零触。

## Tasks

### T1 patch 纯函数（KD-1）

- read_first 2/3/7 → `AIPatchAssembly.swift`（Planner + Composer）。
- 验收：`AIPatchAssemblyTests.swift`（LAYERS，9 法）——①planner bbox +
  pad + 图界 clamp（贴边掩码场景）②全帧掩码 skip 门（>60%）③空掩码 skip
  ④最小尺寸地板 skip ⑤composer 拼接：patch 界内 == patch 值、界外 == 原
  平面逐字节 ⑥接缝 ramp 带宽与线性 profile ⑦patch 矩形 → 视口归一 ROI 的
  Y-flip 换算（`AIMaskRect.visionRect` 恒等性经 patch 空间往返）⑧帽 ≤4 +
  FIFO 替换确定性 ⑨同输入双跑逐字节（确定性）。

### T2 segmentPatch + 羽化纯函数（KD-1/KD-3）

- read_first 2/6 → `AIMaskService.segmentPatch`（additive，零改
  buildLayerBRequest/segmentSubject 既有字节）+ `AIMaskFeather.swift`。
- 验收：`AIMaskFeatherTests.swift`（LAYERS，6 法）——①映射 golden 表
  （±{1,50,100} × longEdge {1000, 4000} 手算 sigma 精确值）②端点 clamp
  ③percent 0 = 同引用返回（字节恒等短路）④单调性（|percent|↑ → sigma↑，
  固定长边）⑤负值收缩 vs 朴素 CPU 参照（1−blur(1−x) 双写）golden ⑥长边
  归一（竖构图 vs 横构图同 percent 同物理半径）。`segmentPatch` 组装面
  断言并入①-⑥外的编译面（ROI/quality/pin 拒由既有 buildLayerBRequest
  测试族覆盖 + 本文件一法断言 ROI 传值正确性，不计新法——组装面 = 既有
  函数消费）。

### T3 人物实例（KD-2/KD-5）

- read_first 2/5 → `personInstanceMasks` + `buildPersonInstanceRequest` +
  MaskToolbarView 菜单项 + 实例勾选 overlay 复用 + LayerEditingState
  会话态。
- 验收：`PersonInstanceMaskTests.swift`（LAYERS，4 法）——①请求组装
  typed 面（revision/pin 映射 + 非 layer-B 资产门旁路申报）②选中并集
  （all = 全实例 max；subset = 选中 max；空选中 = typed noSubject）③空
  结果分类（零观察 → noSubject，非 all-ones）④平面格式面（maskPlane
  走既有 :507 脸的 Float 单通道断言）。

### T4 App 流程接线（KD-1/KD-3）

- read_first 4 → AIMaskEditing 羽化接线 + patch debounce 调度 + 重烘覆写。
- 验收：`AIMaskPatchFlowTests.swift`（APP，4 法）——①debounce 合并
  （1s 窗内 N 次交互 → 单次 patch 调度——Task 注入式时钟缝）②羽化值 →
  bake 参数面（0 = 烘焙输入逐字节 == 无羽化路径）③菜单项路由（新项 →
  person 会话态）④重烘同 maskID 覆写（文件名稳定 + 旧面被替换断言）。

### T5 GUI 真机轮（KD-4，R4）

- 层 B patch 真图一景 + 人物实例多人一景 + 羽化三档走查；证据 =
  `.work/gui-acceptance/m6-4/MANIFEST.md`（步骤/截图/结论逐行）。
- 验收：MANIFEST 逐项闭环；layer B 资产未就绪 = 记录 assetStatus 现场 +
  按失败处置（不静默）——07-3 先例形。

### T6 spike 判据核验 + 红线自证 + 文档（KD-4）

- 判据表逐行核验（KD-4 五行）+ T6 红线机检族（`.metal` 零 diff 等全列）
  + AGENTS M6-4 架构增量节（面 B 段：patch/羽化缝选择/spike 判据表/
  Vision pin 纪律）+ ROADMAP M6-4 行 ✅ + REQUIREMENTS M6INT-03 终态注记
  + GOAL-STATE/TODO。
- 验收：机检行全绿入 SUMMARY；AGENTS 节与本 plan KD 双源一致。

### T7 phase 收口

- SUMMARY（含 §spike 结论落档——KD-4 判定表 + V2 挂账清单）+ DECISIONS
  （KD 偏差 + **羽化缝选择申报**〔烘焙时域 vs postProcess 缝的亲核依据〕+
  layer B ROI 产物分辨率实测申报 + LightCraft 符号语义核对结论 + 重载后
  羽化编辑挂账）+ ACCEPTANCE（双重验收串行）+ **M6-4-VALIDATION.md**
  （phase 签核 = C 档第 3 停面：两 plan 汇总 + 全套 `--all` 终验数字 +
  用户过目项）。
- 验收：定向轮 `--bundle Layers` + `--bundle App` 全绿；**申请全套
  `--all` 批准轮**（预期 3832..3842/24/0；对账基线 = plan 01 收口值）；
  VALIDATION 落签后 phase 翻账。

## 验收标准（AC 总表）

1. **OQ 生效值⑤（patch 入判据）**：patch 三件（Planner/segmentPatch/
   Composer）+ 判据 2 全部可机检项绿（0.6× 边缘宽度 / ≤1px 缝 / ≤4 帽 /
   skip 门）+ debounce 单调度。【T1/T2/T4】
2. **OQ 生效值⑤（羽化顺带）**：±100 全量程映射（负 = 收缩 1−blur(1−x)）+
   0 恒等字节面 + golden 表 + 烘焙缝接线 + 零新 kernel（`.metal` 零
   diff）。【T2/T4】
3. **OQ 生效值⑤（人物实例入口）**：蒙版类型菜单新项 + 主进程直调 additive
   + 选中并集 + typed noSubject（非 all-ones）。【T3】
4. **OQ 生效值⑥（scribble 不激活）**：scribble typed 拒负测原样绿 +
   零 scribble 代码面（grep 零新增命中）。【T2/T6】
5. **OQ 生效值⑦（Describe 收口）**：SUMMARY §spike 五行判定表 + 「原生
   不可达」结论 + V2 挂账清单 + REQUIREMENTS 终态注记。【T6/T7】
6. **spike 结论落档（ROADMAP 验收形态）**：GUI 真机轮 MANIFEST 闭环（R4）
   + VALIDATION 落签。【T5/T7】
7. **零回归门**：`.metal` 零 diff + sidecar schema 零触 + MCP 快照族零
   diff + V50Order/封存面零触 + 既有 AIMask 套件零编辑全绿 + 生成失败 ≠
   load 失败纪律（typed error 面零新增 all-ones 降级路径）+ UserDefaults
   零新键 + dependencies 块零 diff。【T6】
8. **SC 数字门**：LAYERS +19 / APP +4（计划 23，带 21..25 记账区间）定向
   对表；全套预期 **3832..3842/24/0**（对账基线 = plan 01 收口值，VALIDATION
   终验对表）。【T7】

## 风险与边界

- **layer B ROI 产物分辨率未知**：ROI 下产物分辨率以运行时实测为准（可能
  = ROI 分辨率或全帧分辨率）——composer 的重采样吸收差异，合成 golden 不
  受扰；实测值入 DECISIONS（KD-1 申报义务）。
- **Vision 双 beta bug 尾巴（R2）**：patch 腿走 layer B（不 pin——既有拒
  面生效）；person 实例族若实测 pin 行为异常 → 退不 pin + DECISIONS 申报
  （layer A 族 pin 仅测试确定性消费）。
- **GUI 轮依赖真机资产**（R4）：layer B 资产每机首下 + entitlement 阻断
  ——T5 排在 T4 后独立轮；资产不可达 = MANIFEST 记录现场 + VALIDATION
  标注待复验项（不静默放行）。
- **CPU 羽化全帧性能**：掩码分辨率平面（accurate = 全分辨率）的可分离双趟
  ——100MP float32 单通道 400MB 量级的两趟读写，秒级预估；若实测越秒级
  痛点 → 挂账 GPU 迁移（既有 blur kernel 消费）不在本批扩面（DECISIONS
  申报实测值）。
- **patch 判据的 fixture 依赖**：合成双分辨率 fixture（软边圆/几何体）+
  ground truth 双写——fixture 构造入测试文件（零外部资产依赖）。

## 提交约定

- T1 `feat(core): ai mask patch planner and composer pure functions`
- T2 `feat(core): patch roi segmentation leg and feather mapping`
- T3 `feat(core): person instance mask service face with menu entry`
- T4 `feat(app): patch debounce scheduling and feather bake wiring`
- T5 `docs(m6-4): record the ai mask gui acceptance manifest`
- T6 `docs: register the ai mask spike criteria and increment notes`
- T7 `docs(m6-4): close the ai mask spike batch with phase validation`
- 全英文 Conventional Commits；不 push。

## Checker 关注点

1. **零新 kernel 的验证方式**：checker 逐 .metal 文件 `git diff` 零命中
   （全仓 glob）——羽化收缩必须走 CPU 1−blur(1−x) 而非「顺手加个 kernel」；
   postProcess/effectivePlane/`MaskCombiner.swift` 整文件零 diff（KD-3 缝
   裁决的机检面）。
2. **羽化 0 恒等**：`applyFeather` 的 0 短路必须「同引用返回」级（字节面
   断言），不得是「跑一遍 sigma=0」——后者在 Deriche/高斯退化边界有既有
   先例警告（`MaskCombiner.blur` sigma≤0 identity 注记），但字节面纪律要求
   显式短路。
3. **typed noSubject 纪律**：人物实例零观察与 patch 零掩码都必须 typed
   error + 原平面保全——checker 扫新增路径不得出现 all-ones 兜底构造
   （生成失败 ≠ load 失败的 D-07 红线）。
4. **scribble 缝零扰**：`AISubjectSeed.scribble` 拒面与其负测零编辑；
   checker grep scribble 相关 diff 应为零（除无关上下文行）。
5. **会话域纪律**：羽化值/patch 态/实例选择不得出现在
   `LightamerSidecar.swift` / params 编码面（sidecar schema 零触机检）；
   重烘覆写 = 像素真相唯一入口（D-07-CONTEXT-5 延伸申报在 DECISIONS）。
6. **判据可机检性**：KD-4 表行 2/3 的数值判据（0.6× / ≤1px / golden 表）
   必须逐条落到测试断言字面（不允许「目测合理」）；行 4/5 的 GUI/文档轨
   落 MANIFEST/SUMMARY 逐行对账。
7. **数字对账**：LAYERS 19 / APP 4 计划值逐文件核对；全套 3832..3842 带
   内放行；对账链 = plan 01 收口值 + 23 必须机械闭合（两段滑差余量只许
   消化于带内，出带 = 申报）。

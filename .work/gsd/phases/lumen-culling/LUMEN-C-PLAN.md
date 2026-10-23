---
phase: lumen-culling
plan: "LUMEN-C"
title: "plan C — 蒙版精细化（LU5）：T1 MaskRefine 采样式抠图纯函数族（_spread 归一化卷积 + 投影 alpha + 置信门控）golden / T2 App 编排（单飞 + 等待队列 + 一步 history commit + 失败保快速蒙版 + mask.fineAuto 自动触发）/ T3 MCP refine_masks 入 EditingToolset（FIX2③ 零例外——GUI post-assignment 供给，review M-4）/ T4 Settings 键 + 收口"
wave: 3
depends_on: ["LUMEN-A"]
autonomous: true
requirements: ["research 正本 = phases/lumen-culling/RESEARCH.md（ee73da34）§UQ-LU5", "OQ 裁决正本 = 同目录 CONTEXT.md（D-LU-7/8 + X8 设计承接 + 红线 17 条〔FIX2③ 零例外——CONTEXT 红线 1 M-4 修订正本〕）", "上游 = LUMEN-A 闭环（M6-4 蒙版域既有——AIMaskService 快速段在产线，非本批交付）；与 LUMEN-B 无依赖、可换序（D-LU-9）", "基线 4112/40/0 + A/B 终态；本 plan 分账 +6..7", "C 档停位 = 本 plan 执行+验收闭环后停汇报；全套 --all 对账归本 plan 收口轮（末位 plan）"]
success_criteria: "SC 全可机检——T1：MaskRefine.fine(alpha:guide:networkPx:grow:shrink:) 五步直译（①band=0.75 网络像素 + inside/outside erode α≥.99/α≤.01 椭圆核 2·band+1 不确定带 ②_spread 多尺度归一化卷积扩散 σ=band·{.5,2,8,32} 支撑不足逐级填充 ③投影混合比 alpha = clamp(⟨guide−bg,d⟩/|d|²) + 置信 = |d|²/(|d|²+.08²)·exp(−(residual/(.25|d|+.02))²) ④门控 = 置信 × max(边缘陡度,照片细节) 钳制平方 ⑤混合 + 距离变换 smoothstep + grow/shrink 钳）——Accelerate/vImage 全 CPU 零新 Metal kernel + MIT 归属头 + golden NumPy 参考对拍 + guide ≤4096px 钳；T2：App 编排单飞 + 等待队列（Lumen refine_masks_later 直译）+ 完成 = 置换 layer 蒙版平面 + 一步 history commit（复用 M6-4 既有蒙版 history 键族——HistoryStack/LightamerSidecar 零 diff）+ 失败保快速蒙版 + toast + mask.fineAuto 自动触发 + 手动入口；T3：EditingToolset.Seams additive optional refineMasks（默认 nil——yiyinInjector 先例同形）+ refine_masks 工具（入参蒙版 id 集合 + McpRenderGate 串行 + nil = typed 不可用脸）+ refineMasks 生产缝 = LightamerShell `:1126` 同款 GUI post-assignment（projectWriteProbe 先例形——McpServerController 零 diff、FIX2③ 零例外——review M-4；既有构造点零 diff）+ 工具面快照测试；T4：mask.fineAuto Settings 行 + docs + 数组 + BUNDLE-MAP + tuist generate + 全套 --all 对账（三 plan 合计终值带 4144..4152）"
estimated_tests: "+6..7（T1 +3..4 / T2 +2 / T3 +1 / T4 0..1；越带申报理由）"
test_bundles: [LAYERS, APP]
baseline: "4112/40/0 + LUMEN-A 终态 + LUMEN-B 终态（B 收口 SUMMARY 权威数；C 可先于 B 执行——则基线 = A 终态）"
expected_all: "前序 plan 终态 + ΔN（本 plan 终态带 = 批终值带 4144..4152（A+B+C 全序时）；--all 全套对账归本 plan 收口轮——orchestrator 批准制 + 8G 门 + MEMFAIL 机检）"
red_lines:
  - "共用红线正本 = CONTEXT §三 plan 红线 front-matter 17 条（FIX2③ 零例外〔McpServerController 三 plan 全程零 diff——refine_masks 供给 = LightamerShell :1126 同款 GUI post-assignment（review M-4 修订正本）；任何触碰 = 停手上报〕/ 封存面〔HistoryStack/HistoryHash/LightamerSidecar/V50Order/Lut3dKernels.metal/PixelPipe 零 diff——蒙版置换走 M6-4 既有蒙版 history 键族与 revision/epoch 通道〕/ xcstrings 尾块 / LocalizationValue 禁形 / L041 tuist 末位 / 机器级单重活 / MIT 归属不可延后 / 默认中性零行为〔未触发/失败态蒙版域零行为〕/ UserDefaults 恰一键 mask.fineAuto / --all 批准制 / C 档门控 / probe fence〔精细化时长探针〕/ L057 缝 / 测试落域 LAYERS+APP / commit 纪律 lumenc 前缀）。"
  - "AIMaskFeather.swift 零 diff（logit-gain 羽化正交共存——X8：精细化产出更准 alpha 面，Edge 羽化仍在其上按用户半径作用，两缝零接触）。"
  - "零新模型零新 Metal kernel：Vision 结果即快速 alpha（AIMaskService 既有）+ Accelerate/vImage 全 CPU（Lut3dKernels.metal 零 diff 面核）。"
  - "失败保快速蒙版：蒙版域永不因精细化失败而空（D-LU-7/RESEARCH §风险 9——任何异常路径回落快速蒙版 + toast）。"
  - "MCP 边界（D-LU-8）：refine_masks 入 EditingToolset（编辑域）非 culling 域重挂；culling 域 14 工具与 McpCullingContext 零触。"
files_modified:
  - LightamerCore/Sources/AI/MaskRefine.swift                  # T1：新建——采样式抠图五步直译（MIT 归属头；Accelerate/vImage）
  - NOTICE                                                     # T1：Lumen RAW 条目复核（覆盖 MaskRefine——A 批 T3 条目措辞核对）
  - App/Sources/Lightamer/（蒙版编排落点——MaskRefineCoordinator.swift 新建） # T2：单飞/等待队列/history commit/失败保底/fineAuto 触发
  - App/Sources/Lightamer/（蒙版面板手动入口落点）              # T2：「精细化所选蒙版」动作（实际面板文件 execute 期核实）
  - App/Sources/Lightamer/MCP/Tools/EditingToolset.swift       # T3：Seams additive refineMasks 缝 + refine_masks 工具注册
  - App/Sources/Lightamer/UI/Shell/LightamerShell.swift        # T3：refineMasks 生产缝 post-assignment 赋值行（projectWriteProbe :1126 先例同形——McpServerController 零 diff，review M-4）
  - App/Sources/Lightamer/Settings/（mask.fineAuto 设置行落点） # T4：实际 Settings 文件 execute 期核实
  - Resources/Localizable.xcstrings                            # T2/T3：refine/失败 toast/工具描述键尾块纯插入
  - Tests/LightamerTests/MaskRefineTests.swift                 # T1：新建（LAYERS——AIMaskFeatherTests :296 域先例；平铺目录 + Project.swift LightamerTestsLayers 数组显式行，review M-5）
  - Tests/LightamerTests/MaskRefineCoordinatorTests.swift      # T2：新建（APP——平铺目录 + LightamerTestsApp 数组显式行，review M-5）
  - Tests/LightamerTests/McpRefineMasksToolTests.swift         # T3：新建（APP——同上平铺，McpEditingToolsetTests :201 域先例，review M-5）
  - Project.swift                                              # T4：三个新测试文件入对应 bundle 显式数组
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt # T4：三行登记
  - .work/gsd/phases/lumen-culling/LUMEN-C-SUMMARY.md          # T4：执行摘要（逐任务记账 + ΔN 终账 + 全套 --all 对账）
  - .work/gsd/phases/lumen-culling/LUMEN-C-DECISIONS.md        # T4：裁定记录（grow/shrink 参数终值 + LightamerShell refineMasks 装配 diff 申报 + 各偏差 + 键登记——review M-4 判据改）
---

# Plan LUMEN-C — 蒙版精细化（LU5）

> **裁决正本** = `CONTEXT.md`（D-LU-7/8 + X8；晨审可推翻）；规格正本 =
> `RESEARCH.md`（§UQ-LU5 / §依赖与切分 C 行；planner 抽核吻合 + 勘误见
> CONTEXT）。本 plan = Core 纯函数新件 + App 编排 + MCP 编辑域一工具；
> **零新模型零新 Metal kernel**（Accelerate/vImage 全 CPU）、
> **AIMaskFeather 零 diff**（正交共存）、**蒙版域失败保底**（永不空）。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（T1-T4 形态 = CONTEXT D-LU
> 落定值）。执行中如触「必须扩面」（新 Metal kernel / culling 域重挂 /
> AIMaskService 快速段改写 / HistoryStack 新 item 类型 / McpServerController
> 任何触碰——review M-4 零例外）= 停手上报，不得自裁扩界。
>
> **执行序**：T1 → T2 → T3 → T4。每任务独立 commit；重活起跑前过
> `Scripts/machine-guard.sh`；开工前核 `.work/config.toml [gsd]`
> paused/auto。
>
> **C 档停**：T4 闭环后**停汇报**；本 plan = 批末位——全套 `--all` 对
> 账（终值带 4144..4152）归 T4 收口轮（orchestrator 批准制）。
>
> **基线**：前序 plan 终态（A+B 全序 = 4138..4145；C 换序先于 B = A 终
> 态 4124..4127——以在先收口 SUMMARY 权威数为准）。

## ΔN 预算表（逐任务，本 plan 分账带 +6..7；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 MaskRefine 纯函数族 | **+3..4** | golden NumPy 对拍（五步全式）+ 置信门控表驱动 + grow/shrink 钳 + 畸形输入容错 | LAYERS（MaskRefineTests） |
| T2 App 编排 | **+2** | 单飞/队列/一步 commit/失败保底/fineAuto 门 | APP（MaskRefineCoordinatorTests） |
| T3 MCP refine_masks | **+1** | 工具面快照 + typed 不可用脸 + gate 串行断言 | APP（McpRefineMasksToolTests） |
| T4 收口 | **0..1** | Settings 键 + docs + 数组 + BUNDLE-MAP + tuist generate + --all 对账 | — |
| **合计** | **+6..7** | 前序终态 → 批终值带 4144..4152 | 三新测试文件 |

## 已定裁决（生效值，硬约束，不得重开）

1. **触发 = 自动（默认开）+ 手动入口 + Settings 可关**（D-LU-7）——
   `mask.fineAuto` Bool 默认 true；失败保快速蒙版 + toast。
2. **与 logit-gain 羽化正交共存**（X8）——AIMaskFeather 零 diff；精细
   化在前（alpha 面质量），羽化在后（用户半径语义）。
3. **零新模型零新 kernel**（本地红线 3——m-8 编号显式化）——快速 alpha =
   Vision/AIMaskService 既有产物；精细化 = Accelerate/vImage CPU 域。
4. **一步 history commit 走既有缝**（X8/CONTEXT 红线 2 封存面——m-8 全
   局编号）——蒙版平面置换复用
   M6-4 蒙版 history 键族与 revision/epoch 通道；HistoryStack/
   LightamerSidecar/V50Order 零 diff。
5. **MCP = EditingToolset 编辑域一工具**（D-LU-8/本地红线 5）——Seams
   additive optional 缝 + LightamerShell post-assignment 供给（FIX2③
   零例外——review M-4；McpRenderGate 串行——4096px 解码属渲染级）。
6. **guide ≤4096px**（X8）——显影后显示域一档解码（1480px 档不够）；
   与放大共用解码是 Lumen 语义，我方对应 = 限边解码 + 现管线到显示域。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/lumen-culling/CONTEXT.md`（D-LU-7/8 + X8 + hazards
  + 红线 17 条〔FIX2③ 零例外 = CONTEXT 红线 1 M-4 修订正本〕+ 勘误②
  〔含 M-4 修正〕）
- `.work/gsd/phases/lumen-culling/RESEARCH.md` §UQ-LU5 全节 + §风险 9
- Lumen 直译源（只读，`git show v2.0.1:`——**禁触其工作区**）：
  `lumen/selection.py:88-118,122-252`（refine/FINE_EDGE/fine 全式/
  refine_fine 参数）+ `lumen/auto_masks.py:143-219`（v2.0.1 实读——
  `refine_masks_later` 区块；RESEARCH :121-219 = v1.7.0 行号域，review
  m-4 勘正；编排——单飞/队列/raster 置换/一步 undo）
- 我方蒙版域正本：`LightamerCore/Sources/AI/AIMaskService.swift:68
  （AIMaskPlane）/:285/:350`（快速段——零改消费）+
  `AIMaskFeather.swift:15-31`（logit-gain——零 diff 共存面）；M6-4 蒙
  版 history/revision 通道（AGENTS M6-4 节 + 蒙版编辑面实际文件）
- `.work/config.toml [gsd]` paused/auto + `.work/LESSONS.md` L041（三个
  新测试文件必触发）/ L014（精细化时长探针 fence）
- AGENTS.md M2-4-0 E2（落域——LAYERS/APP）+ M6-4 节（AI 分割蒙版管線）

---

## T1 — MaskRefine 采样式抠图纯函数族 golden（X8，MIT 归属）

> Lumen `selection.py:167-219` fine() 直译域；两段式 = 快速蒙版（既有
> AIMaskService 产物）→ 后台精细化（本件）。

**read_first**：CONTEXT §X8；Lumen `selection.py:88-118`（refine——
1.6.1 导向滤波贴边，**语义参照**：我方无此件，快速段贴边由 Vision 产
物分辨率承担——RESEARCH §UQ-LU5 缝位注记「增量收益主要在发丝/枝叶级
边缘，预期收益面比 Lumen 窄，但算法同形可用」）+:122-252（fine 全式 +
fine_size/fine_guide/sky 参数）；`AIMaskService.swift:68-80`（AIMaskPlane
形态——输入/输出面）；Accelerate/vImage 面（vImage morphology/tent/
convolve 先例盘点——execute 期选型申报）。

- **action**：
  1. 新建 `LightamerCore/Sources/AI/MaskRefine.swift`：
     `fine(alpha: AIMaskPlane, guide: 显影后显示域平面, networkPx: Int,
     grow: Double, shrink: Double) -> AIMaskPlane`——五步直译（CONTEXT
     X8 全式：band/erode 不确定带 → _spread 多尺度归一化卷积 → 投影
     alpha + 置信 → 门控钳制平方 → 混合 + 距离变换 smoothstep +
     grow/shrink 钳）；guide ≤4096px 钳（FINE_EDGE 直译）；distanceTransform
     = 两遍 chamfer 自写 ~30 行；erode/dilate = vImage morphology；
     box/Gaussian = vImage；归一化卷积 = vDSP。
  2. 文件头 MIT 归属（红线 7——NOTICE 条目复核：A 批 T3 条目覆盖三件，
     本任务核对措辞含 MaskRefine）。
  3. 测试（LAYERS）：**golden NumPy 参考对拍**（合成 guide/alpha 对 +
     参考输出双写——M2-4 golden 惯例；Python 参考移植随 evidence 入库）
     + **场景参照 = Lumen `tests/test_v170_masks.py` 四个 fine-pass 测
     试**（twigs/broad-ramps/guide-size/raster-blocks——review m-3）+
     置信门控表驱动（宽缓坡保快速蒙版例——雾/低细节区钳制生效）+
     grow/shrink 钳边界（精细面不得越快速蒙版允许带）+ 畸形输入容错
     （全 inside/全 outside/零支撑）+ ≤4096 钳断言。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰一新产线文件（+NOTICE 复核 diff 如需）。
  - grep：`import Metal`/`MTLCompute` 零命中（文件域——零 kernel 红线
    机检）；`4096` 钳常量恰一处；五步注释分段在册。
  - golden 对拍留档 evidence（NumPy 参考源 + 数值带）；置信门控/钳边
    界/容错测试在册。
  - `--bundle Layers` 定向零回归（AIMaskFeatherTests 存量族全绿）。
- **commit**: `feat(lumenc): add sample-based mask refinement core`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（纯新件零消费方）；
  偏差（vImage 选型/chamfer 实现形态/golden 数值带）= DECISIONS 申报；
  **禁改公式常量**（band 0.75/σ 族 {.5,2,8,32}/.08²/.25|.d|+.02——直译
  标定）；**禁落 Metal**（本地红线 3——m-8）；golden 失配 = 停手对拍定位禁凑数。

## T2 — App 编排：单飞 + 队列 + 一步 commit + 失败保底（X8，D-LU-7）

**read_first**：CONTEXT §X8 编排臂 + §D-LU-7；Lumen v2.0.1
`auto_masks.py:143-219`（refine_masks_later——独立线程单飞/等待队列/
raster 置换/一步 undo 直译正本；RESEARCH :121-219 = v1.7.0 行号域，
review m-4 勘正）；M6-4 蒙版 history/revision 通道实际文件（蒙版平面置
换 + commit 缝——execute 期从蒙版编辑面定位）+ D-H1 三段提交语义；
`AIMaskService` 消费点（分割成功事件缝——自动触发挂点）。

- **action**：
  1. 新建 `MaskRefineCoordinator`（App 侧）：单飞（一次一档）+ 等待队
     列（后续请求排队）+ 完成 = 置换 layer 蒙版平面 + **一步 history
     commit**（复用 M6-4 既有蒙版 history 键族/revision 通道——禁新
     item 类型）+ 失败保快速蒙版 + toast 原因（键族尾块）。
  2. 触发缝：分割成功后自动（`mask.fineAuto` typed 读 + 注入式——默认
     true）+「精细化所选蒙版」手动入口（蒙版面板实际文件 execute 期核
     实落点）。
  3. guide 供给：显影后显示域 ≤4096px 一档（PipeCoordinator 预览档平
     面家族/限边解码——实际缝 execute 期定位，触点最小化申报）。
  4. 测试（APP）：单飞/队列序（后请求排队不并发）/成功置换 + commit
     断言（合成 history 面）/失败保快速蒙版（注入抛错——蒙版平面零变
     + toast）/fineAuto 关 = 不自动触发 + 手动入口仍可达。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` = Coordinator 新建 + 触发/面板/指引最小
    触点（清单 DECISIONS 申报）；HistoryStack/HistoryHash/
    LightamerSidecar/AIMaskFeather 零 diff（`git diff` 面核）。
  - grep：`mask.fineAuto` 全仓恰一处（键单源）；单飞哨兵（并发 ≤1 断
    言在测试）。
  - `--bundle App` 定向零回归。
- **commit**: `feat(lumenc): orchestrate background mask refinement`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（编排零消费 = 精细化
  不触发，快速蒙版现状）；偏差（guide 供给缝/队列容量）= DECISIONS 申
  报；**禁新 history item 类型**（CONTEXT 红线 2 封存面——m-8 全局编
  号；发现「必须」= 停手上报）；
  **禁阻塞 UI 线程**（后台 Task 缝——Lumen 独立线程同义）；**禁失败静
  默**（toast 必达）。

## T3 — MCP refine_masks 入 EditingToolset（X8，FIX2③ 零例外——review M-4）

**read_first**：CONTEXT §X8 MCP 臂 + CONTEXT 红线 1（零例外——M-4 修订
正本）+ 勘误②（含 M-4 修正）；
`EditingToolset.swift:52-141`（Seams additive var 先例 :91-118 + register
:141——「Each plan task extends this body; the snapshot tests pin every
addition」在案）+:1278（registerRenderPreview 形参照）；
`LightamerShell.swift:1112/:1126`（projectWriteProbe post-assignment 先
例——refineMasks 供给同形落点，review M-4）+ `McpServerController.swift:
961-1010`（makeEditingSeams——装配单点参照/零 diff 面）/:501/:634/:742/
:830/:975（既有构造点——零 diff 面）；`McpToolRegistry
.swift:256`（McpRenderGate）；`McpEditingToolsetTests.swift` +
`McpRegistrySnapshotTests.swift`（APP 域先例）。

- **action**：
  1. `EditingToolset.Seams` additive：`var refineMasks:
     (@Sendable (_ ids: [String]) async throws -> Void)? = nil`（默认
     nil——yiyinInjector/projectWriteProbe 先例同形；既有构造点编译零
     diff）。
  2. `refine_masks` 工具注册（register body 扩展——入参 = 蒙版 id 集
     合；nil 缝 = typed 不可用脸；gate = McpRenderGate 串行（渲染级
     ——4096px 解码）；requiresControl/写面纪律沿 EditingToolset 既有
     写工具同形）。
  3. `LightamerShell` 装配点 refineMasks 生产缝供给 **post-assignment
     恰一行赋值**（`editingSeams.refineMasks = …`——projectWriteProbe
     `:1126` 先例同形；**McpServerController 零 diff、FIX2③ 零例外**
     ——CONTEXT 红线 1 M-4 修订正本；makeEditingSeams 参数形 ≥2 行触
     硬门弃用）。
  4. 工具描述键尾块纯插入；zh-audit 双 PASS。
  5. 测试（APP）：工具面快照（list 含 refine_masks——安全面钉）+
     typed 不可用脸（nil 缝）+ gate 串行断言 + 入参校验（未知蒙版 id
     typed 错）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat`：McpServerController **零 diff**（`git
    diff` 面核——零例外，review M-4）；EditingToolset 一文件 +
    LightamerShell 装配赋值最小 diff。
  - grep：`refineMasks` 恰两处（Seams 声明 + LightamerShell 装配赋值
    ——review M-4 判据改）；既有构造点零触碰面核。
  - 快照测试 + 不可用脸 + gate 断言在册；zh-audit 双 PASS 留档。
  - `--bundle App` 定向零回归。
- **commit**: `feat(lumenc): add mcp refine_masks editing tool`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（工具摘除——Seams
  additive 缝残留无害但随 revert）；偏差（入参形态/门控档）= DECISIONS
  申报；**禁触 culling 域 14 工具与 McpCullingContext**（D-LU-8）；
  **禁触 McpServerController**（CONTEXT 红线 1 零例外——review M-4；
  发现「必须」= 停手上报 orchestrator）；**禁绕
  writeGate/projectWriteProbe 既有写面纪律**。

## T4 — Settings 键 + 收口（含全套 --all 对账）

- **action**：
  1. Settings 页 `mask.fineAuto` 行（默认 on——typed 读 + 注入式；实际
     Settings 文件核实落点）。
  2. `Project.swift` 三个新测试文件入对应 target 数组（**平铺
     `Tests/LightamerTests/`——无 LightamerTestsLayers/App 目录，bundle
     归属 = target 数组显式行 + BUNDLE-MAP 登记行——review M-5**；
     MaskRefineTests → LightamerTestsLayers 数组；Coordinator/ToolTests
     → LightamerTestsApp 数组）+ BUNDLE-MAP 三行。
  3. `tuist generate` = 本批最后一个动作（L041）。
  4. `--bundle Layers` + `--bundle App` 定向全绿；ΔN 实数对账（预算
     +6..7）。
  5. **全套 `--all` 对账**（批末位职责——orchestrator 批准 + 8G 门 +
     MEMFAIL 机检 + caffeinate + parentage 核验）：三 plan 合计 ΔN 对
     账（+32..40 → 终值带 4144..4152；skip 增量逐族申报）。
  6. LUMEN-C-SUMMARY（逐任务记账 + ΔN 终账 + 全套对账表 + 探针指针）+
     LUMEN-C-DECISIONS（grow/shrink 参数终值 + LightamerShell refineMasks
     装配 diff 申报 + 各偏差 + 键登记 `mask.fineAuto`）落盘；AGENTS.md
     键族节三键登记
     随批（A/B/C 各键——收口批汇总落地）。
  7. 汇报 + **C 档停**（批收口汇报）。
- **验收标准（机检）**：定向 bundle 全绿零回归；全套 `--all` 对账表在
  SUMMARY（实测数 vs 预测带）；Project.swift diff = 恰三行；BUNDLE-MAP
  三行在库；AGENTS 键族登记在库；SUMMARY/DECISIONS 在库。
- **commit**: `test(lumenc): register mask refine suites and close out culling batch`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；ΔN 越带 / 全套越带
  = SUMMARY 申报理由；禁漏 tuist generate；禁未经批准起跑 `--all`。

---

## 风险与回退

- **计算量与性能**（RESEARCH §风险 9）：≤4096px 钳 + Accelerate 移植性
  能待探针（Lumen 33MP≈7s 参照；probe fence 纪律——红线 14）；劣化可
  接受（后台单飞不占图像作业队列语义）。
- **精细化失败面**：置信/支撑不足 = 保快速蒙版（算法内建）+ 编排异常 =
  toast 保底（T2）——蒙版域永不空（双重保底）。
- **增量收益面窄**（RESEARCH §UQ-LU5 缝位注记）：我方快速蒙版生成分辨
  率本就较高（Vision 全辨析率 + patch ramp），精细化增量集中在发丝/枝
  叶级——判定维持「中」，收益走查挂 validate 道（GUI 对比样张）。
- **FIX2③ 零例外纪律（review M-4）**：McpServerController 零 diff 是硬
  门——`git diff` 面核入 T3 验收；供给走 LightamerShell post-assignment
  （:1126 先例形）；任何 McpServerController 触碰 = 停手上报非自裁。
- **grow/shrink 参数终值**：Lumen sky .3/.02 是其样张标定——我方默认值
  execute 期以合成/实拍对比定（DECISIONS 申报终值；算法钳制边界 T1 钉
  死与参数值解耦）。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：RESEARCH §UQ-LU5 算法五步 ↔ T1 逐项；编排 ↔ T2；
   MCP 臂 ↔ T3；H-LU3 无涉（本 plan 零缓存面——核对无越界触达）。
2. **OQ 兑现核**：D-LU-7（T2 自动/手动/失败保底 + T4 键）/ D-LU-8（T3
   编辑域非 culling 域）/ X8 正交共存（AIMaskFeather 零 diff 面核）。
3. **红线核**：零新 kernel（grep Metal 零命中）；HistoryStack/
   LightamerSidecar 零 diff（蒙版置换走既有缝的面核——commit 载荷查）；
   FIX2③ 零例外（McpServerController 零 diff 面核——review M-4）；MIT 归属 + NOTICE 复核；tuist generate 末位。
4. **SC 可机检性**：每条 SC 有命令级判据；全套对账 = 三 plan 分账合计
   非死数；FIX2③ 零例外 = McpServerController `git diff` 面核判据（review M-4）。

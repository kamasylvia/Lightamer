---
phase: M9-1
plan: v2
title: "M9-1 — AI Mask 工具 parity：T1 任务蒙版三件+Sky 槽 / T2 Feather px 对齐+Expand vImage 形态学 / T3 逐点即解+Path+候选 coverage 通道 / T4 会话三命令+paste 排除 / T5 收口"
wave: 1
depends_on: ["R6 修复批收口（guard 让位）"]
autonomous: true
requirements: ["research 正本 = phases/m9-1-aimask/RESEARCH.md（§一上游测绘/§二我方盘点/§三差距矩阵/§四方案骨架/§五探针）", "OQ 裁决正本 = 同目录 CONTEXT.md（D-M9A-1..10 全按 research 推荐 + 附带裁定 Expand→Feather 序 + 合法偏离 11 条 + 红线 15 条）", "REQUIREMENTS M9AIM-01..03（验收形态即各 T 验收源）", "charter = ROADMAP §M9 站 1（M-L，ΔN +20..28；OQ-M9-1 否/OQ-M9-2A/Sky 砍留槽/bake-to-raster 合法偏离声明）", "全套对账锚 = M8 终态 4287/39/0 + R6 修复批 ΔN（R6 终值由其收口轮落账；本批带式表达不写死数）"]
success_criteria: "SC 全可机检——T1：任务面板四 icon（Subject 现役腿复用/Background=subject+invert 位/M People=InstancePicker+unionSelection/Sky disabled+tooltip）+ Background 恒等负测（invert 面逐点 1−x 或 RasterMaskRef.invert 位断言）+ Sky 槽 disabled 断言（AX id + .disabled 态）+ People 子集 union 消费测试 + xcstrings ai_task_* 尾插；T2：σ_px 换算单源（px↔percent 双向 + clamp [0,50]/[−50,50]）+ Expand = vImage PlanarF 3×3 交替 cross/square dilate/erode（|px| 步；erode=<0）+ golden 五面（单像素源膨胀 n 步 = 八角距离精确像素集/随机平面与 host 参考逐字节/erode-dilate 反演边界/恒等/量化单调交换律）+ bake 缝序 expand→feather→quantize 断言 + slider D-H1 三段；T3：SegmentSession 点删（removePoint + 预算 gate 复用）+ 候选 plane session 态持有 + debounce 300ms 重解状态机 + Path 采样纯函数（24px 等弧长 + min(16,余量) 收敛 + ≤ 上游 16 上限）+ MaskOverlayStyle += .candidate（display 枚举 additive 不入 record——sidecar/history 零新键负测 + 样式 picker 白名单断言〔userSelectableCases——.candidate 不入用户样式菜单，xcstrings 不加 mask_overlay_style_candidate 键〕）+ 候选 tint 传值缝显式预案（专用合成臂/request 形态扩展二选一——spec 组装腿对无 layer.mask spec 的 session 候选结构性不适用；DECISIONS 记选定形态）+ Commit/Cancel 后候选通道消失断言 + 点视觉绿/红 disc 色 + spinner/busy cursor；T4：cancel = 候选丢弃+Escape 语义收敛（退出零 bake 断言）+ open(编辑既有) re-entry 扩展（.segment→.subject/.person 三源路由判据）+ commit 恰 1 条 stackSnapshot 维持 + paste 排除（AIMaskSource.fileName 前缀判据的 raster ref 不入 payload + 跳过名单 toast 列名 + 手绘蒙版不排负测 + 语义反转 DECISIONS 申报）+ undo 边界（session 候选不进 history 负测）；T5：Project.swift 数组+BUNDLE-MAP 增行+tuist 末位 + 定向 Layers+App 全绿 + 全套 --all（orchestrator 预批）ΔN 对账 + zh-audit 双 PASS + gui-acceptance m9-1 MANIFEST 走查配方（含 AXPress 配方纪律）"
estimated_tests: "+20..29（T1 +5..6 / T2 +5..9 / T3 +6..9 / T4 +4..6 / T5 0；构成明细合计 27-29 如实对齐——T2 Morphology 五面 + FeatherPx 四面 ≈9 / T3 Path 三面 + Iterative 六族 ≈9，一法多断言可压缩；上限 29 越 charter 带 +20..28 至多 +1——越带申报 = golden 面各承载独立红线论证不可省 + 交互族与 AI-06 断言面一一对应；收口轮按实数对账）"
test_bundles: [LAYERS, APP]
baseline: "M8 终态全套 4287/39/0（M8-VALIDATION signed；STATE current_phase 节）+ R6 修复批 ΔN（R6 在飞、终值由 R6 收口轮落账——本 plan 验收 = 构建 + 定向 bundle，全套对账基线以 R6 收口终值为准）"
expected_all: "R6 收口终值 + ΔN（本 plan 分账 +20..29；全套 --all 归 T5 收口轮 orchestrator 预批后跑，8G 门 + MEMFAIL 机检兜底）"
red_lines:
  - "共用红线正本 = CONTEXT §红线 15 条（封存面 15 项零 diff〔PixelPipe 预期零触碰，必触则逐 hunk 申报豁免停手上报〕/ 零新 SPM / 零新模型 / AI-06 参数不持久 + sidecar·UserDefaults 零新键 / xcstrings 尾插 + zh-audit 双 PASS + 动态键禁形 / V50Order·schema v11 零 bump / 测试落域 + tuist 末位 / 机器级单重活 + R6 让位 / GPL 零复制 / D-H1 / disable-not-unmount / commit-per-task / AX id 顺路 / parentage 纪律）。"
  - "Paste 排除 = 语义反转件（现行 mask 随 payload 走 → 改排除）：DECISIONS 必申报反转语义 + 只排可识别 AI 件保守臂（degrade/rename 蒙版不排）。"
  - "候选 coverage 通道 = display 样式面（.candidate case additive）：不入 record/history/sidecar 的负测是收口硬门——AI-06 不可破的具体断言面。"
  - "Expand 算子域 = bake 缝 float 平面（PlanarF）形态学，量化单调交换律断言在册；禁在会话态/已 bake PNG 上二次加工。"
files_modified:
  - App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift          # T1/T2/T3：任务面板四 icon + People 子列表 + Feather/Expand slider px 化（:243-255 slider 面平移）+ 样式 picker :144 改消费 userSelectableCases（M-1 白名单）
  - App/Sources/Lightamer/UI/Overlay/InstancePickerOverlay.swift    # T1：People 列表 toggle 消费（checkbox floater 复用/面板化装配）
  - App/Sources/Lightamer/State/AIMaskEditing.swift                 # T1/T3/T4：commitRasterMask 通道复用（:158-296）+ re-entry 三源路由（AIMaskSource :29-62）+ cancel 命令腿
  - LightamerCore/Sources/AI/AIMaskFeather.swift                    # T2：σ_px 换算单源（px↔percent + clamp）
  - LightamerCore/Sources/AI/AIMaskMorphology.swift                 # T2：新建——vImage 3×3 交替形态学 + host 参考实现
  - LightamerCore/Sources/Sidecar/RasterMaskStore.swift             # T2：bake 缝 expand 参数（featherRadius 邻位；序 expand→feather→quantize）
  - App/Sources/Lightamer/State/LayerEditingState.swift             # T2/T3/T4：SegmentSession 扩展（expandPx 字段/removePoint/候选 plane/debounce/Path 激活/cancel 腿）+ MaskOverlayStyle += .candidate（:69）+ userSelectableCases 样式白名单（panelMenuCases 同款先例 :109-111）
  - App/Sources/Lightamer/UI/Overlay/SegmentEditingOverlayHost.swift # T3：点删除交互 + Path 笔触（.scribble seam :684-685/:811 激活）+ 绿红 disc + spinner/busy cursor
  - LightamerCore/Sources/AI/AIMaskGeometry.swift                   # T3：Path 等弧长采样纯函数（24px/min(16,余量)）——或并入 AIMaskTypes additive（execute 期定，DECISIONS 记）
  - App/Sources/Lightamer/State/PipeCoordinator.swift               # T3：候选 plane overlay 传值缝（专用合成臂/request 形态扩展二选一预案——applyMaskOverlayIfRequested :264-300 spec 组装前提对无 layer.mask spec 候选结构性不适用，caller payload 门 :2434-2441 需候选分支；App 侧协调器非封存面）
  - App/Sources/Lightamer/State/AdjustmentTransfer.swift            # T4：mask 腿排除判据 + 跳过名单（buildPayload :174/:193-195）
  - Resources/Localizable.xcstrings                                # T1/T3/T4：ai_task_*/ai_path_*/ai_candidate_*/transfer 跳过名单键族尾块纯插入（mask_overlay_style_candidate 显式不加——M-1 白名单下 labelKey 零消费）
  - Tests/LightamerTests/AIMaskTaskPanelTests.swift                # T1：新建（APP）
  - Tests/LightamerTests/AIMaskMorphologyTests.swift               # T2：新建（LAYERS/Core 级）
  - Tests/LightamerTests/AIMaskFeatherPxTests.swift                # T2：新建（LAYERS/Core 级——换算单源 + bake 序）
  - Tests/LightamerTests/AIMaskPathSamplingTests.swift             # T3：新建（LAYERS/Core 级——纯函数）
  - Tests/LightamerTests/AIMaskIterativeSessionTests.swift         # T3：新建（APP——点删/debounce 状态机/候选样式/通道消失）
  - Tests/LightamerTests/AIMaskSessionCommandsTests.swift          # T4：新建（APP——cancel/re-entry/paste 排除/undo 边界）
  - Project.swift                                                  # T5：六个新测试文件入对应 bundle 显式数组（三 LAYERS + 三 APP——按 front-matter 归属终判）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt     # T5：六行落域登记
  - .work/gsd/phases/m9-1-aimask/M9-1-SUMMARY.md                   # T5：执行摘要（ΔN 终账 + 走查证据指针）
  - .work/gsd/phases/m9-1-aimask/M9-1-DECISIONS.md                 # T5：裁定记录（paste 语义反转/Expand 序/采样落点等）
  - .work/gui-acceptance/m9-1/MANIFEST.md                          # T5：走查配方（M9-1-05 形态）
---

# Plan M9-1 — AI Mask 工具 parity（M9AIM-01..03）

> **裁决正本** = `CONTEXT.md`（D-M9A-1..10 + 合法偏离 11 条 + 红线 15 条；
> 晨审可推翻）。**规格正本** = `RESEARCH.md`（上游测绘 §一 / 我方盘点 §二
> file:line / 差距矩阵 §三 / 方案骨架 §四；planner 抽核 ~25 点吻合）。
> 范式前提：**AI-06 bake-to-raster 维持**——上游 source kind/R8 asset/
> sidecar 进程/lease/下载面板全不引入（charter 合法偏离声明）；本 plan
> 主战场 = 交互体验（任务面板/逐点即解/Path/候选通道）+ 算子面（Expand）
> + 会话三命令与 paste 排除。
>
> **执行序**：T1 → T2 → T3 → T4 → T5 串行（机器级单重活制）。每任务独立
> commit（Conventional Commits 全英文，只 add 相关文件）；重活起跑前过
> `Scripts/machine-guard.sh`（**R6 修复批在飞时让位**）；开工前核
> `.work/config.toml [gsd]` paused/auto。
>
> **C 档停**：T5 闭环后停汇报（附走查样例清单供用户过目——§12.3 铁律：
> 验收样例动工前对齐口径，走查面以我方 AI-06 语义断言不照抄上游）。
>
> **基线**：M8 终态 `4287/39/0` + R6 ΔN（在飞）。本 plan 分账 **+20..29**
> （构成明细 27-29 如实对齐；上限越 charter 带 +20..28 至多 +1——申报
> 见 ΔN 预算表注）；全套对账以 R6 收口终值为基。

## ΔN 预算表（逐任务，越带申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 任务蒙版面板 | **+5..6** | Background 恒等负测 + Sky disabled 断言 + People 子集 union + 面板装配/入口路由 + invert 位往返 | APP（AIMaskTaskPanelTests） |
| T2 Feather px + Expand | **+5..9** | Morphology 五面（八角距离精确集/逐字节对拍/erode 反演/恒等/量化单调——action 6 细目）+ FeatherPx 四面（σ_px 双向换算/clamp 边界/bake 序/负腿回归）≈9 法，一法多断言可压 | LAYERS（AIMaskMorphologyTests + AIMaskFeatherPxTests） |
| T3 逐点即解+Path+候选通道 | **+6..9** | Path 采样 3+ 面（24px 数学/收敛 12·11 边界/短笔触）+ Iterative 六族（点删/debounce 状态机/候选保留/additive 负测+picker 白名单/通道消失/视觉映射）≈9 法 | LAYERS（AIMaskPathSamplingTests）+ APP（AIMaskIterativeSessionTests） |
| T4 会话命令+paste 排除 | **+4..6** | cancel 丢弃 + re-entry 三源路由 + paste 排除/跳过名单/手绘不排负测 + undo 边界 | APP（AIMaskSessionCommandsTests） |
| T5 收口 | **0** | docs + Project.swift + BUNDLE-MAP + tuist + zh-audit + 走查配方 | — |
| **合计** | **+20..29** | R6 收口终值 + ΔN → 全套申报带 | 六新测试文件（三 LAYERS + 三 APP） |

> **带上限 29 越 charter 带 +20..28 至多 +1（m-2 申报）**：构成明细
> （T2 ≈9 / T3 ≈9，合计 27-29）如实申报优先于带内压缩——golden 五面各
> 承载独立红线论证（八角=形态学正确性 / 逐字节=vImage 对拍 / 反演=边界
> 行为 / 恒等=中性默认 / 单调=R8 交换律），交互族与 AI-06 断言面一一对应
> 不可并删；执行期一法多断言（恒等并入八角 golden、视觉映射并入通道
> 断言等）可回落 charter 带内，收口轮按实数对账（越带理由落 SUMMARY）。

## 已定裁决（生效值，硬约束，不得重开）

1. 逐点即解 + debounce 300ms + 保留旧候选 + spinner（D-M9A-1）。
2. People = 子集一次确认（D-M9A-2）；Sky = disabled 槽（charter OQ-M9-2A）。
3. 候选 tint = `MaskOverlayStyle` 第四 case `.candidate`（D-M9A-3）；Commit
   后候选通道消失、既有蒙版编辑 tint 零 diff（D-M9A-4）。
4. session undo/redo 栈不建（D-M9A-5）；Path 采样按 seed 形态收敛 12/11
   点（D-M9A-6）。
5. Feather/Expand 面板绝对 px（[0,50]/[−50,50]），换算单源（D-M9A-7）；
   负 feather logit-gain 超集保留。
6. paste 排除 + 跳过名单 toast（D-M9A-8）；Expand = CPU vImage（D-M9A-9）；
   几何指纹不入本批挂 UPSTREAM-QUEUE（D-M9A-10）。
7. Expand→Feather 应用序（planner 附带裁定，晨审可推翻；执行期行为对照
   若发现上游反序 → DECISIONS 申报 + 双序负测）。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/m9-1-aimask/CONTEXT.md`（D-M9A 表 + 复用件清单 +
  红线 + 合法偏离 + 风险绑定）
- `.work/gsd/phases/m9-1-aimask/RESEARCH.md` §二（我方盘点 file:line——
  本 plan 全部复用缝出处）/§三（差距矩阵——各 T 的差距落点）/§六（R-1..R-6）
- `.work/config.toml [gsd]` paused/auto；`.work/LESSONS.md` L041（tuist
  末位）/L013（StableHash——本批无新身份哈希面，备忘）/L014（探针读钟 fence，
  本批无 GPU 计时面，备忘）
- AGENTS.md「Phase 执行模型」+ 跨批不变量速查 + M2-4-0 E2（测试落域）+
  M6-4/lumen-culling 节（AIMask 基建 + MaskRefine 先例）
- 上游行为对照（GPL 只读，禁复制）：RESEARCH §附录出处表——SM9 工具面板
  plan / `ai_mask_prompt_geometry.hpp`（24px/≤16 点）/`ai_mask_coverage_
  composition.hpp` / `ai_mask_coverage.cl`（交替核形态）

---

## T1 — 任务蒙版面板：三件 + Sky 留槽（M9AIM-01）

> 服务面零差距（Layer A subject / person 实例族现役）；本任务 = 入口面板
> 化 + People 列表形态 + Sky 槽。**零 Core 服务面改动预期**。

**read_first**：CONTEXT §复用件（MaskToolbarView/InstancePickerOverlay/
AIMaskService person 族/commitRasterMask invert 腿）；`MaskToolbarView.swift
:340-400`（现役 AI 入口群 + 主体/主体以外 sugar）；`InstancePickerOverlay.
swift:25-57`（checkbox floater 全文）；`AIMaskService.swift:480-613`（detect
→catalog→unionSelection 签名）；RESEARCH §三 M9AIM-01 表。

- **action**：
  1. `MaskToolbarView.swift` 新建**任务面板区**（现役 AI 入口群旁，上游 SM9
     icon 行为对照）：四 icon = Subject（现役 `generateSubjectMask()` 腿复用
     :353-363——入口区注释 :353 / 主体蒙版按钮 :363）/ Background（同生成
     + `invert: true`——:380-395 现役 sugar 入
     面板化，per-ref `RasterMaskRef.invert` 位承载）/ People（新装配：
     `detectPersonInstances` → InstancePicker 子列表 → 子集确认 →
     `unionSelection(.subset)` → `commitRasterMask(source: .person)`）/
     Sky（**disabled icon + tooltip**，`.disabled(true)` 恒置——disable-not-
     unmount 纪律，不建死代码路径）。
  2. People 子列表：InstancePickerOverlay checkbox 形态复用（D-M9A-2 子集
     一次确认——非逐人增量 bake）；person box 视口轮廓 = InstancePicker
     既有预览 tint 通道复用（box outline 如需新绘 = SegmentPointsCanvas
     同款 Canvas 扩展，execute 期定形 DECISIONS 记）。
  3. `AIMaskEditing.swift` 预期**零 diff**（commitRasterMask 通道 + 五源
     枚举现成；若装配需参数透传 = 最小 additive，DECISIONS 记）。
  4. xcstrings：`ai_task_subject/background/people/sky` + `ai_task_sky_
     disabled_hint`（Sky tooltip）等 `ai_task_*` 键族**尾块纯插入**（技术
     专名 zh=英文原文惯例）。
  5. AX id：`ai.mask.task.subject/background/people/sky` 四枚（走查配方
     消费；Sky 槽 disabled 断言判据）。
  6. 测试（APP，`AIMaskTaskPanelTests.swift` 新建）：①Background 恒等负测
     ——subject plane + invert 位 → bake 后 raster ref `invert == true` 且
     生成路径与 Subject 共腿（同输入同 plane 断言，1−x 语义由 ref 位承载
     的现役机制断言）；②Sky 槽 disabled 断言（AX id 存在 + `.disabled` 态
     + 点击零动作）；③People 子集 union 消费（合成 catalog → subset 选择 →
     unionSelection max-fold 数学断言——纯函数面直测）；④面板装配/入口
     路由（四 icon 可达性 + People 无 person 时空态）；⑤invert 位往返
     （invert→再 invert = 原值，ref 位语义）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 产线文件 = MaskToolbarView + InstancePicker
    Overlay（+ xcstrings；AIMaskEditing 预期零 diff——如非零须 DECISIONS
    申报理由）。
  - grep：`ai.mask.task.sky` 恰一处且其控件恒 `.disabled`；`unionSelection`
    消费点在面板装配链恰一处；`generateSubjectMask(invert: true)` 腿复用
    （非新复制实现——grep 无第二 subject 生成实现）。
  - 测试五族在册；`--bundle App` 定向零回归。
- **commit**: `feat(m9aim): add ai mask task panel with subject background people and sky slot`
- **回滚与偏差申报**：回滚 = revert 单 commit（面板 additive，现役散入口
  零扰）；偏差（People 空态文案/轮廓绘制形态）= DECISIONS 申报；**禁建
  Sky 任何活代码路径**（charter 砍留槽）；**禁逐人增量 bake**（D-M9A-2）；
  **禁新建 subject 生成第二实现**（invert 腿复用红线）。

## T2 — 算子面：Feather 绝对 px 对齐 + Expand vImage 形态学（M9AIM-03）

> Expand = 全仓唯一真缺算子（RESEARCH §七「最大缺口一件」）；CPU vImage
> 路线保零新 kernel 红线（D-M9A-9），GPU 化留 seam 注记。

**read_first**：CONTEXT §红线 2/4/11 + §附带裁定（Expand→Feather 序）；
`AIMaskFeather.swift` 全文（σ 换算 :54-58 / 负腿 :69-88 / 双腿互斥 pin）；
`RasterMaskStore.swift:88-116`（bake：r32F→featherRadius Deriche→uint16
量化→PNG）；`MaskToolbarView.swift:240-260`（featherPercent slider 现役
面）；RESEARCH §一.6（上游 GPU Feather/Expand：偶步 cross/奇步 square 交替
= 近圆盘、R8 单调交换律、margin 式）+ §三 M9AIM-03 表；Accelerate vImage
PlanarF dilate/erode API 文档（系统框架）。

- **action**：
  1. `AIMaskFeather.swift` additive **σ_px 换算单源**：`sigmaFromPx(px:
     Float, longEdgePixels: Int) -> Float`（px∈[0,50] clamp → 折 percent →
     既有 `sigma(percent:longEdgePixels:)` 腿）+ 反向 `pxFromPercent`（旧
     slider 面平移换算，M6-4-02 面迁移）；`featherPercent` 字段与负腿
     logit-gain**全保留**（超集，红线 4 语境——不删既有行为）。
  2. 新建 `LightamerCore/Sources/AI/AIMaskMorphology.swift`：`expand(plane:
     AIMaskPlane, px: Int) -> AIMaskPlane`——|px| 步 3×3 形态学，**偶数步
     cross 核（+字）、奇数步 square 核（3×3 满）交替**（上游行为对照；
     形态学 = 公开数学非 GPL 复制，红线 10）；px>0 dilate / px<0 erode /
     0 恒等；实现 = **vImage `vImageDilate_PlanarF`/`vImageErode_PlanarF`**
     两 kernel（cross/square 掩码）交替调用，bake 缝 float 平面域（量化
     单调交换律断言承载 R8 等价论证）；**host 参考实现**同文件纯 Swift
     （max/min 直扫——golden 对拍非运行时替代，上游 `MakeAiMaskCoverage
     Texture` 同款测试证据形态）。
  3. `RasterMaskStore.swift` bake 缝 additive `expandPx: Int = 0` 参数
     （`featherRadius` 邻位）：应用序 **expand → feather → quantize**（附
     带裁定；上游 margin 式不锁序，反序证据若现 DECISIONS 申报）；已 bake
     PNG 零二次加工（bake 时一次，红线）。
  4. `MaskToolbarView.swift` slider 面：Feather slider **px 化 [0,50]** +
     新 **Expand slider [−50,50] 整数步**（D-H1 三段：begin/setLive/end——
     live 仅预览请求，松手 accept 才入 bake 参数，红线 11）；SegmentSession
     additive `expandPx` 字段（`featherPercent` :741 邻位，UI 态不持久）。
  5. GPU 化 seam 注记 + **合法偏离申报（m-1）**：AIMaskMorphology 文件头
     注记「后续优化批可 kernel 化（M8 新核申报制先例）」——本批零
     .metal 触碰；**Expand = CPU vImage 显式偏离 REQUIREMENTS M9AIM-03
     与 ROADMAP M9-1 行的「GPU 算子」字样**（零新 kernel 红线优先，
     D-M9A-9 裁定；GPU 化留 seam），DECISIONS 收口登记该申报句。
  6. 测试（LAYERS，两新文件）：
     - `AIMaskMorphologyTests`：①八角距离 golden——单像素源膨胀 n 步后
       精确像素集断言（cross/square 交替 = 八角度量，预comput边缘界坐标
       逐点比对）；②随机平面 vImage vs host 参考逐字节（多尺寸含奇偶宽
       高/边界 clamp 行为）；③erode 反演——全 1 平面 erode n 再 dilate n
       的边界收缩精确断言；④|px|=0 恒等（逐字节）；⑤量化单调交换律
       （expand 后量化 == 量化后单调映射断言——R8 论证移植）。
     - `AIMaskFeatherPxTests`：σ_px↔percent 双向换算 + clamp 边界（0/50/
       越界）+ bake 序断言（expand→feather 调用序探针）+ 负腿保留回归
       （percent<0 logit-gain 路径不回归）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰五产线文件（AIMaskFeather + AIMaskMorphology
    新建 + RasterMaskStore + MaskToolbarView + LayerEditingState〔expandPx
    一行〕）+ xcstrings（slider 标签键若有）。
  - grep：`vImageDilate_PlanarF`/`vImageErode_PlanarF` 各恰一文件；新
    `.metal`/`MTLComputePipeline` 零新增（零新 kernel 机检）；`expandPx`
    持久化面零命中（sidecar/UserDefaults——AI-06 红线 4 断言）。
  - golden 五面在册（八角距离/逐字节/反演/恒等/单调）；`--bundle Layers`
    定向零回归（AIMaskFeatherTests 存量 6 法全绿）。
- **commit**: `feat(m9aim): add expand morphology via vimage and align feather to absolute pixels`
- **回滚与偏差申报**：回滚 = revert 单 commit（additive 参数默认 0 = 现行
  bake 逐字节不变）；偏差（vImage 边界模式与上游 clamp-replicate 差异/核
  序证据翻案）= DECISIONS 申报 + golden 同步；**禁新 GPU kernel**（D-M9A-9
  红线——GPU 化 = 后续批申报制）；**禁改 featherPercent 既有语义**（超集
  保留）；**禁在会话态/已 bake PNG 上二次加工**（bake 缝一次原则）。

## T3 — 交互面：逐点即解 + Path 工具 + 候选 coverage 通道（M9AIM-02 主件）

> 上游核心体验（逐点反馈候选蒙版）落地：候选 plane = session 态中间反馈
> 层，Confirm 才走 commitRasterMask——恰好是我方既有 confirm 形态加中间层
> （RESEARCH §四.2）。

**read_first**：CONTEXT §D-M9A-1/3/4/6 + §合法偏离 2/3/4/7；`LayerEditing
State.swift:691-862`（SegmentSession 全文：点集/预算 gate :824-844/
recordSeed :810/patches FIFO/debounce 先例）+:69-76（MaskOverlayStyle）+
:92-112（MaskCommand——`panelMenuCases` 白名单先例 :109-111，注释明言
a future case cannot silently leak into the menu）+:684-685,:811
（.scribble typed seam）；`SegmentEditingOverlayHost.swift`
全文（手势 :104-154 / confirm :231-264 / 27 SDK modifierFlags 坠落注记
:105）；`PipeCoordinator.swift:227-230,:264-300,:2434-2452`（overlay
request + **`applyMaskOverlayIfRequested` 的 spec 组装前提**〔DrawnMask
Rasterizer/MaskCombiner.effectivePlane 从 stack layer 的 mask spec 组装
plane；`unwrap(layer.mask, "mask overlay: no mask")` :282〕+ render
尾合成 + newest-wins + caller payload 门 :2434-2441〕）；`MaskToolbar
View.swift:144`（`ForEach(MaskOverlayStyle.allCases)` 现役消费面——
白名单改写点）；RESEARCH §一.1-1.2（上游控制序/prompt 几何/overlay
视觉：#30A46C/#E5484D、marker r7、busy cursor）+ §五（探针：全量重解 85-126ms
判定）+ §风险 R-1/R-3。

- **action**：
  1. **SegmentSession 扩展**（`LayerEditingState.swift`）：
     - `removePoint(at:)`：included/excluded 点删除（上游靠 session undo
       覆盖；我方最小面 = 点级删 + 既有 recordSeed 重置，D-M9A-5）；
     - **候选 plane 持有**：`candidatePlane: AIMaskPlane?` session 态
       （不 bake 不 commit 不入 history——R-5 边界）；
     - **逐点即解腿**（D-M9A-1）：点集变更 → debounce **300ms** →
       `segmentSubject` 全量重解（Layer B 无链式迭代，探针判定）→ 候选
       plane 更新 + 保留旧候选显示（推理期间不清空——上游语义）；
       spinner 态字段 + busy cursor；冷启动首步 = EntryGate 三态门 +
       spinner 就绪提示；重解失败 = 保留旧候选 + typed 错误 toast（不加步
       ——上游错误链行为对照）；
     - **点集上限** = AIPointBudget 现役 gate（13/11）复用，零新上限逻辑。
  2. **Path 工具**（`.scribble` seam 激活）：
     - Core 纯函数（新 `AIMaskGeometry.swift` 或并入 `AIMaskTypes.swift`
       additive——execute 期定，DECISIONS 记）：笔触点列 → **等弧长 24px
       间隔采样**（上游 `kAiMaskStrokePromptSpacingItemPx=24.0` 行为对照）
       → 采样数 = `min(16, AIPointBudget 余量)`（D-M9A-6：point-seeded
       12 + seed、box-seeded 11——合法偏离 3 降级明示，UI 计数器现役面
       承载）；
     - OverlayHost：`DragGesture` 笔触收集 → 释放时采样 → included refine
       点序列投喂（`buildLayerBRequest` :402-409 既有路径，零二路）。
  3. **候选 coverage 通道**（D-M9A-3/4）：
     - `MaskOverlayStyle` += `.candidate`（:69 additive，display 枚举不入
       record——SidecarV11/HistoryStack 零新键）；淡红 tint（上游 #515
       `maskCoverageTintColor` 行为对照，主题固定色）；
     - **样式 picker 白名单（M-1）**：`.candidate` 不入用户样式菜单——
       新增 `MaskOverlayStyle.userSelectableCases` 静态白名单
       （translucent/rubylith/onBlack 三者；`MaskCommand.panelMenuCases`
       同款先例 `LayerEditingState.swift:109-111`，注释明言 a future
       case cannot silently leak into the menu）；`MaskToolbarView.
       swift:144` 现役 `ForEach(MaskOverlayStyle.allCases)` 改消费白名单；
       **xcstrings 不加 `mask_overlay_style_candidate` 键**（白名单下
       该 labelKey 零消费面 = 死键防御；若 execute 期出现非 picker 消费
       面需此键 → DECISIONS 申报后加）。注意：`ForEach(allCases)` 非
       穷举 switch、无编译期保障——收口靠白名单断言 + grep 三项机检，
       非任何「编译期收口」措辞；
     - **PipeCoordinator 传值缝（M-2 显式预案，不复用 spec 组装腿）**：
       判据 = session 候选 plane 未 bake、无 layer.mask spec，而
       `applyMaskOverlayIfRequested`（`PipeCoordinator.swift:264-300`）
       从 stack layer 的 **mask spec** 组装 plane（DrawnMaskRasterizer
       :289-292 / `MaskCombiner.effectivePlane` :298-307），函数内
       `unwrap(layer.mask, "mask overlay: no mask")` :282 与 caller 门
       `layer.mask?.hasAnyPayload == true`（:2434-2441）对候选
       **结构性不适用**——「复用 maskOverlayRequest 腿」实为结构扩展。
       二选一（execute 期定，**DECISIONS 记选定形态**）：
       ① **request 形态扩展**——`maskOverlayRequest`（:227-230）元组
       additive 候选纹理位（`MTLTexture?`），caller 门加候选分支
       bypass payload guard，合成腿候选位非 nil 时跳过 spec 组装、
       直染候选纹理；
       ② **候选专用合成臂**——独立 `candidateOverlayRequest` 变体
       （候选纹理 + style + 清除态），旁路 spec 组装，走同一 render
       尾插入点（:2434-2452）。
       两臂均 App 侧协调器面（PipeCoordinator 非封存）；newest-wins
       门现役复用；**Core PixelPipe 零触碰**——若发现必须触则停手
       申报豁免，红线 1；
     - **Commit/Cancel 后候选通道消失**（D-M9A-4：候选 overlay request
       清除断言）；既有 commit 后蒙版编辑 tint 0.85 常亮**零 diff**。
  4. **点视觉对齐**：SegmentPointsCanvas 绿 + disc（#30A46C）/红 − disc
     （#E5484D）+ rim（上游 `ai_mask_input_overlay_geometry.hpp` 行为对照
     ——色值/尺寸数值参数非代码复制）；busy cursor 灰态；Path stroke 视觉。
  5. Confirm 钮 = 候选 plane 消费（`SegmentEditingOverlayHost.swift:231-264`
     confirm 腿：候选存在时 bake 候选，无候选时现役全量重解后 bake——两路
     收敛 commitRasterMask 单通道）。
  6. xcstrings：`ai_path_tool`/`ai_candidate_solving`/`ai_candidate_ready`
     等键族尾块纯插入（动态键禁形——switch 返回静态键）。
  7. 测试：
     - LAYERS（`AIMaskPathSamplingTests.swift` 新建）：等弧长采样数学面
       （24px 间距/端点包含/采样数收敛 12/11 边界/短笔触 <24px 单点）+
       预算余量交互（point/box seeded 两态）。
     - APP（`AIMaskIterativeSessionTests.swift` 新建）：点删（删后预算回
       收）/debounce 状态机（300ms 窗内多点合并一解——合成时钟注入）/
       候选 plane 保留旧值（重解失败不清空）/`.candidate` 样式 additive
       负测（sidecar 序列化零新键——AI-06 断言）+ **picker 白名单断言**
       （`userSelectableCases` 不含 `.candidate` + 样式 picker 消费面
       零 candidate——M-1）/候选通道 Commit·Cancel
       后消失（overlay request 清除断言）/视觉映射（色值常量单源）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰六产线文件（LayerEditingState + Overlay
    Host + PipeCoordinator + Core 采样件 + xcstrings + Canvas 视觉件〔若
    独立文件〕）。
  - grep：`.candidate` case 恰一处声明 + **picker 白名单断言替「编译期
    收口」措辞（M-1）**——三项机检：`ForEach` 消费 `userSelectableCases`
    （样式 picker 恰一处）+ 测试断言可选样式集不含 `.candidate` +
    xcstrings `mask_overlay_style_candidate` 键零在册；`candidatePlane`
    持久化面零命中（sidecar/UserDefaults）；`debounce`
    常量 300ms 单源；采样常量 `24`/`16` 与 min 收敛式在册且注记上游出处；
    `.scribble` typed throw 撤除（**口径明确〔m-5〕**：硬清零面 = throw
    点 `AIMaskService.swift:386` + 测试断言 `AIMaskSemanticTests.swift:
    293` 随 seam 激活改写在册；error case 定义 `AIMaskTypes.swift:151`
    与注释〔`:70` / `LayerEditingState.swift:684`〕去留 = DECISIONS 记
    ——throw 点清零后 case 若成死代码则删除，注释同步改写）。
  - 测试各族在册；`--bundle Layers` + `--bundle App` 定向零回归（AIMask
    Semantic/EditPaths 存量族全绿——.scribble 拒绝测试**随 seam 激活同步
    改写**为采样激活正测，DECISIONS 记改动）。
  - 交互不改参数真相断言：候选态全程 sidecar/history 零写入（M9AIM-02
    验收形态「交互不改参数真相」的机检等价——AI-06）。
- **commit**: `feat(m9aim): add iterative tap-to-segment with path tool and candidate coverage channel`
- **回滚与偏差申报**：回滚 = revert 单 commit（候选态全 session 态，现役
  攒点 confirm 路径保留为回落臂）；偏差（debounce 值/视觉细节/采样件落点/
  **候选传值缝选定形态——①request 扩展 vs ②专用合成臂，M-2**）
  = DECISIONS 申报；**禁候选态入 history/sidecar**（AI-06 红线——收口硬
  门）；**禁删现役 confirm 全量重解臂**（候选缺失回落）；**禁触 Core
  PixelPipe**（必触则停手申报豁免）；**禁照抄上游「Commit 后全部隐藏」**
  （D-M9A-4——蒙版编辑 tint 保留）。

## T4 — 会话面：open/commit/cancel 三命令 + paste 排除（M9AIM-03）

**read_first**：CONTEXT §D-M9A-8 + §合法偏离 9 + §R-2/R-5 消解；
`AIMaskEditing.swift:29-62`（AIMaskSource 判据）+:158-296（commitRaster
Mask :158 起——恰 1 条 stackSnapshot 语义）+ :67-94（EntryGate）；`AdjustmentTransfer.
swift` 全文相关段（:36-40 排除谓词 / :174 buildPayload / :193-195 mask 腿
——contentRevision 置 nil :194，v2 实测复核在案）；RESEARCH §一.4（D16/D17/M15/M16 会话语义——对照
非照搬）+ §一.7（D18/M17 paste 排除 + 跳过名单）+ §四.4（会话三命令我方
形态）。

- **action**：
  1. **open（新建）** = `armSegmentSession` 现役（零改——申报「已有」）。
  2. **open（编辑既有）** = re-entry 扩展：现役 `.segment` 源（`AIMaskSource
     .source(ofFileName:)` 判据 `LayerEditingState.swift:284-290`——
     `armSegmentSession` 的 `== .segment` 单源判据 :287 扩三源）→ 扩
     `.subject`/`.person` 源（判据现成 :55-62；语义 = 重生成覆盖 bake
     〔same maskID re-bake，D-07-CONTEXT-5 现役〕——**不含**上游 M15
     「存储 coverage 直显零模型」〔我方无 AI source kind，重开即重解，
     合法偏离〕）。**意图变更注释同步（m-4）**：现役注释
     `AIMaskEditing.swift:36-43` 明言「a person re-bake must never seed
     a segment session — `armSegmentSession` keys on `.segment` only」
     （person :41-43；depth :36-38 同款）——其设计意图 = **防自动联动**
     （AI 件 re-bake 不得自动拉起 segment 会话），T4 扩源 = **用户显式
     重开**（显式 open ≠ 自动 seed，语义可分），但注释的「must never」
     陈述被显式推翻：**同步改写**该注释为「自动联动仍禁；用户显式
     re-entry 走 .segment/.subject/.person 三源路由」+ DECISIONS 记
     设计意图变更（防联动语义保留、路由面扩源）。
  3. **commit** = 现役 Confirm（恰 1 条 stackSnapshot）维持——**undo/redo
     边界钉死（R-5）**：session 候选态不进 history；commit 恰 1 条；re-entry
     再 confirm = 第 2 条（现役 re-bake 同款如实呈现，非缺陷——DECISIONS
     钉措辞）。
  4. **cancel（新增）**：退出模式 = 丢弃候选 plane + 点集 + overlay request
     （Done/Escape 语义收敛为 Cancel——现形态「攒点未 confirm 本就未 bake」
     天然 cancel，升级点 = 逐点即解后「已解候选未 confirm」的丢弃面）；
     零 bake 零 history 断言。
  5. **paste 排除**（语义反转申报件，红线 2）：
     - `AdjustmentTransfer.buildPayload` mask 腿：`AIMaskSource.source(
       ofFileName:) != nil` 的 raster ref **不入 payload**（保守臂：只排
       可识别 AI 件——degrade/rename 蒙版不排，R-2）；
     - **跳过名单**（D-M9A-8）：transfer 面 greyed+count note 风格 toast/
       对话框列名（上游 M17 ListAiMasksExcludedFromTransfer 行为对照）；
     - 手绘蒙版（无前缀）**不排**负测在册；
     - DECISIONS 必申报：反转语义（现行 mask 随 payload → 改排除）+ 判据
       脆弱性保守臂。
  6. xcstrings：`transfer_ai_masks_excluded` 名单键族（含 count 插值——
     静态键 + String(format:) 惯例，动态键禁形）尾块纯插入。
  7. 测试（APP，`AIMaskSessionCommandsTests.swift` 新建）：cancel 丢弃
     （候选 plane 置 nil + overlay 清除 + 零 bake 断言）/ re-entry 三源
     路由（.segment/.subject/.person 判据 + 非 AI 蒙版不路由）/ paste 排除
     正负测（AI bake 件被排 + 名单列名 + 手绘件随 payload）/ undo 边界
     （候选态 zero-history-item 断言 + commit 恰 1 条）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰四产线文件（AIMaskEditing + LayerEditing
    State〔cancel 腿〕+ AdjustmentTransfer + transfer UI 件）+ xcstrings。
  - grep：`source(ofFileName:)` 消费点 = re-entry 路由 + paste 排除恰两处
    （判据单源复用非复制）；`buildPayload` 内 AI 排除谓词恰一处；跳过
    名单文案键在 xcstrings 在册；`AIMaskEditing.swift` 注释「must never
    seed」措辞零残留（m-4 意图变更注释改写在册）。
  - 测试四族在册；`--bundle App` 定向零回归（既有 paste 测试族随语义反转
    **同步改写**——DECISIONS 记：哪些存量断言翻转 + 为什么反转 = 上游 D18
    对齐申报）。
- **commit**: `feat(m9aim): add mask session commands and exclude ai masks from adjustment transfer`
- **回滚与偏差申报**：回滚 = revert 单 commit（paste 排除回滚 = 回复现行
  mask 随 payload 走——语义反转件回滚需 DECISIONS 记账）；偏差（cancel 与
  Done 合一形态/名单呈现形态）= DECISIONS 申报；**禁 paste 排除手绘蒙版**
  （保守臂红线）；**禁 cancel 触碰已 bake 蒙版**（Cancel 零发布——上游
  D16 语义对齐件）；**禁 re-entry 建存储 coverage 直显**（合法偏离申报——
  重开即重解）。

## T5 — 回归收口（对账 + zh-audit + 走查配方）

- **action**：
  1. `Project.swift` 六个新测试文件入对应 bundle 显式数组（三 LAYERS +
     三 APP——按 front-matter 归属终判）+ BUNDLE-MAP 六行登记 + `tuist
     generate` = 本批最后动作（L041）。
  2. 定向 `--bundle Layers` + `--bundle App` 全绿零回归。
  3. **全套 `--all`**：orchestrator 预批后跑（R6 已收口为前提；machine-
     guard + monitor 21600 伴跑 + 8G 门 + MEMFAIL 兜底）；ΔN 对账 =
     R6 收口终值 + 本批实数 vs 预算 +20..29（构成明细 27-29 对齐带；
     越带申报理由见 ΔN 预算表注，落 SUMMARY）。
  4. `zh-audit --check` + `--self-test` 双 PASS（V15 硬化纪律——批次尾
     对账以 SUMMARY 键清单并集核对动态族）。
  5. **走查配方** `.work/gui-acceptance/m9-1/MANIFEST.md`（m3-1/lumen-b
     同款 MANIFEST 形态，gui-acceptance 惯例）：①任务面板四 icon（Sky
     disabled 态截图）；
     ②tap-to-segment 逐点即解（加点/删点/候选 tint 消长/Commit 后候选
     消失）——**AXPress 配方纪律**（R6 批 omp obs-3 教训：AX id 浮出缺失
     一处改动级则顺路补）；③Path 笔触采样（点计数器）；④Feather/Expand
     slider（px 域 + D-H1 松手生效）；⑤paste 排除名单 toast；⑥cancel
     丢弃。**M9AIM-02 承载映射（m-3——SUMMARY 与 MANIFEST 显式登记）**：
     验收形态「合成事件→AX 驱动真视口 tap→蒙版更新→coverage 消长 +
     交互不改参数真相」↔ 三层链 = T3 状态机级单测（机检：debounce/
     候选消长/AI-06 零写入断言）+ 走查项②③（AXPress 配方驱动真视口）
     + omp computer-use 二次验收——SUMMARY 对账行按此映射落，验收轮
     逐段核销不落空。走查样例清单随 C 档停呈报供用户过目（§12.3 铁律）。
  6. `M9-1-SUMMARY.md`（逐任务记账 + ΔN 终账 + 走查证据指针）+
     `M9-1-DECISIONS.md`（paste 语义反转/Expand 序/采样件落点/.scribble
     测试改写/存量 paste 断言翻转/各偏差）落盘。
  7. 汇报 + **C 档停**。
- **验收标准（机检）**：定向 bundle 全绿；Project.swift diff = 恰六行数组
  插入；BUNDLE-MAP 六行在库；tuist generate 后无生成物入 git；zh-audit
  双 PASS 输出留档；全套 TOTAL 对账式落 SUMMARY；MANIFEST 在库。
- **commit**: `test(m9aim): register ai mask suites and close out m9-1`
- **回滚与偏差申报**：回滚 = revert 单 commit；ΔN 越带 = SUMMARY 申报
  理由；禁漏 tuist generate；禁跳过 zh-audit（硬化纪律）。

---

## 风险与回退

- **R-1 大图多步重解延迟（门值与降载）**：逐点重解 warm 基线 85-126ms
  （25-102MP 全档，07-1-DECISIONS:30）——**门值 = P95 ≤500ms/步**（4×
  余量；100MP 大图上限预算 ≤2s/步登记为告警线）。**降载方案序**：①
  debounce 300ms 合并连点（已入 T3）；②点集上限 = AIPointBudget 13/11
  （API 自身硬限，无自设上限可加）；③超门自适应 = debounce 升 500ms +
  spinner 文案（DECISIONS 定形）；④`segmentPatch` ROI 腿（`AIMaskService.
  swift:350-362` 现役薄封装）备选——仅在探针实测超门时启用申报。冷启动
  5.5s = 进程首启一次性（EntryGate 门现役），spinner 就绪提示承接。探针
  实测挂 execute 期（guard 后空窗；探针 = `--bundle Layers` 定向 + fence
  纪律 L014 本批无 GPU 计时面，CPU 计时直读）。
- **Vision 不可达面（合法偏离清单，验收不照抄）**：click level 三级（无
  多 mask 输出）/ 64 点组（13/11 硬限）/ embedding 缓存链式（全量重解）/
  M15 存储直显（重开即重解）——CONTEXT §合法偏离 2/3/4 + 本文件 T3/T4
  申报项。
- **候选通道渲染缝（M-2 扩）**：结构性缝 = `applyMaskOverlayIfRequested`
  （PipeCoordinator:264-300）的 spec 组装前提对无 layer.mask spec 的
  session 候选 plane 不适用（caller payload 门 :2434-2441 同）——判据
  与二选一预案见 T3 action 3（request 形态扩展 / 候选专用合成臂），
  DECISIONS 记选定形态；运行缝 = 候选纹理上载与 newest-wins 门冲突
  （过期帧付 overlay pass）→ execute 期探针；冲突 = request 撤销序调整
  （DECISIONS 记），不动 Core PixelPipe。
- **paste 语义反转回归面**：存量 paste 测试族翻转 = 风险面（漏翻 = 假绿
  或假红）——T4 验收强令 DECISIONS 列翻转清单；手绘蒙版不排负测是守门。
- **.scribble 测试改写**：存量 typed 拒绝测试（AIMaskSemanticTests 域）
  随 seam 激活改写——漏改 = 编译/运行红（显性），改写过度 = 语义漂
  （T3 验收 grep `scribbleNotSupported` 机检——**口径（m-5）**：硬清零
  面 = throw 点 + 测试断言；error case/注释去留 DECISIONS 记，见 T3
  验收标准）。
- **回退总形**：各 T 均独立 commit 可 revert；T2 expandPx 默认 0 / T3 候
  选态 session 态 / T4 cancel additive——全批默认面 = 现行行为逐字节不
  变（面板 additive + 参数默认中性），回滚无需数据迁移。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：RESEARCH §三差距矩阵 M9AIM-01 表 ↔ T1；M9AIM-02 表
   ↔ T3；M9AIM-03 表 ↔ T2/T4；§四方案骨架 1..5 ↔ T1/T3/T2/T4/偏离清单
   逐项闭合。
2. **OQ 兑现核**：D-M9A-1（T3 debounce/保留旧候选/spinner）/ D-M9A-2（T1
   子集确认）/ D-M9A-3（T3 .candidate additive + **picker 白名单收口
   ——userSelectableCases/xcstrings 零 candidate 键/测试断言三项**）/
   D-M9A-4（T3 通道消失 +
   tint 零 diff）/ D-M9A-5（T3 点删 + T4 边界钉）/ D-M9A-6（T3 采样收敛）/
   D-M9A-7（T2 px 化 + 换算单源）/ D-M9A-8（T4 名单）/ D-M9A-9（T2 vImage
   零 kernel + **CPU 偏离 GPU 字样申报**）/ D-M9A-10（零指纹件 = 不在册）。
   另核 M-2：候选传值缝 = DECISIONS 选定形态在册（①request 扩展 /
   ②专用合成臂），非 spec 组装腿复用。
3. **红线核**：封存面 15 项 git diff 零命中（PixelPipe 逐 hunk 特别核）；
   新 .metal 零新增；sidecar/UserDefaults 零新键；xcstrings 尾块纯插入 +
   zh-audit 双 PASS；tuist generate 末位；AI-06 断言面（候选态持久化零
   命中 grep）。
4. **SC 可机检性**：每条 SC 有命令级判据（grep / git diff --stat / 定向
   bundle）；ΔN 对账式非死数（R6 收口终值 + ΔN 带式）。

---

## 评审修复记录（plan v2，2026-10-25 — 对 M9-1-PLAN-REVIEW.md 逐条处置）

> review 档位 PASS-with-notes（0 blocking / 2 major / 5 minor）。
> 本批修复 = 纯 plan 文件修订（PLAN + CONTEXT），零 commit / 零构建，
> 由 orchestrator 收割。修复前全部锚点亲测复核（见各条行号）。

| 条 | 档位 | 处置 | 修法落点 |
|---|---|---|---|
| M-1 `.candidate` allCases 消费面泄漏 | major | 已修 | T3 action 3 新增「样式 picker 白名单」子条：`MaskOverlayStyle.userSelectableCases` 静态白名单（`MaskCommand.panelMenuCases` 同款先例 `LayerEditingState.swift:109-111`——亲测注释明言 a future case cannot silently leak into the menu）；`MaskToolbarView.swift:144` 亲测 `ForEach(MaskOverlayStyle.allCases)` 改消费白名单；xcstrings **不加** `mask_overlay_style_candidate` 键（白名单下 labelKey 零消费 = 死键防御；出现非 picker 消费面则 DECISIONS 申报后加）。T3 测试族补 picker 白名单断言；T3 验收「`allCases` 消费面编译期收口」改「白名单三项机检（ForEach 消费 userSelectableCases + 测试断言可选集不含 candidate + xcstrings 零 candidate 键）」；front-matter SC / files_modified / read_first / Checker 节同步；CONTEXT D-M9A-3 同步改写（「编译期收口」错误措辞源头） |
| M-2 候选 coverage 传值缝结构低估 | major | 已修 | T3 action 3 传值缝子条重写为显式预案（判据句：session 候选 plane 无 layer.mask spec → `applyMaskOverlayIfRequested`〔PipeCoordinator.swift:264-300，亲测：DrawnMaskRasterizer :289-292 / MaskCombiner.effectivePlane :298-307 / `unwrap(layer.mask)` :282〕与 caller 门 `hasAnyPayload`〔:2434-2441 亲测〕结构性不适用）：① request 形态扩展（元组 additive 候选纹理位 + caller 候选分支 bypass payload guard + 合成腿跳过 spec 组装直染）/ ② 候选专用合成臂（独立 request 变体旁路 spec 组装、走同一 render 尾插入点）——二选一 execute 期定、DECISIONS 记选定形态。read_first 补 :264-300 锚；风险节「候选通道渲染缝」扩结构缝面；T3 回滚节偏差清单补「传值缝选定形态」；front-matter SC/files_modified 同步；CONTEXT D-M9A-3 + 复用件清单行同步 |
| m-1 Expand CPU/GPU 合法偏离未申报 | minor | 已修 | T2 action 5 补申报句：Expand = CPU vImage 显式偏离 REQUIREMENTS M9AIM-03 / ROADMAP M9-1 的「GPU 算子」字样（零新 kernel 红线优先，D-M9A-9），DECISIONS 收口登记；Checker 节 D-M9A-9 核面加「CPU 偏离 GPU 字样申报」 |
| m-2 ΔN 构成合计与带偏紧 2-4 | minor | 已修（上调带 + 构成对齐） | 带 +20..27 → **+20..29**（front-matter estimated_tests / expected_all / 头部基线句 / T5 action 3 四处同步）；ΔN 预算表 T2 +5..7→**+5..9**（构成列按 action 6 细目如实重写：Morphology 五面 + FeatherPx 四面 ≈9 法）、T3 +6..8→**+6..9**（Path 三面 + Iterative 六族 ≈9 法）；表后新增越带申报注（上限 29 越 charter +20..28 至多 +1；golden 面各承载独立红线论证 + 交互族与 AI-06 断言面一一对应；一法多断言可回落带内；收口轮按实数对账落 SUMMARY） |
| m-3 M9AIM-02 走查承载映射未显式 | minor | 已修 | T5 action 5 补承载映射句：验收形态（合成事件→AX 驱动真视口 tap→蒙版更新→coverage 消长 + 交互不改参数真相）↔ 三层链 = T3 状态机级单测（机检）+ 走查项②③（AXPress 配方）+ omp computer-use 二次验收——SUMMARY 对账行按此映射落 |
| m-4 re-entry 与 AIMaskSource 注释意图相抵 | minor | 已修 | T4 action 2 补「意图变更注释同步」子句：亲测注释 `AIMaskEditing.swift:36-43`（person :41-43「a person re-bake must never seed a segment session」/ depth :36-38 同款）= 防自动联动语境，T4 显式 open ≠ 自动 seed——同步改写注释（自动联动仍禁 / 显式 re-entry 三源路由）+ DECISIONS 记设计意图变更；re-entry 判据锚精确化（`LayerEditingState.swift:284-290`，`== .segment` :287）；T4 验收 grep 补「must never seed 措辞零残留」 |
| m-5 行号漂移 + grep 口径不明 | minor | 已修 | ① commitRasterMask :157→**:158**（T4 read_first 亲测修正）；② 主体蒙版入口 :353→**:353-363**（注释 :353 / 按钮 :363——T1 action 1）；③ AdjustmentTransfer mask 腿 :193-195 **实测复核无漂移**（review 附录计数偏差——`if var mask` :193 / contentRevision 置 nil :194 / `layer.mask = mask` :195），精确化注 :194；④ T3 验收 `scribbleNotSupported` 零残留口径明确化：硬清零面 = throw 点 `AIMaskService.swift:386` + 测试断言 `AIMaskSemanticTests.swift:293`（现存 5 处命中亲测在案：另含 case 定义 `AIMaskTypes.swift:151`、注释 `:70` 与 `LayerEditingState.swift:684`——error case/注释去留 = DECISIONS 记，throw 点清零后 case 若成死代码则删除）；风险节 .scribble 段同步口径 |

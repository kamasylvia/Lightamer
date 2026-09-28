---
phase: m2-1
plan: "M2-1"
title: "dt 面 feature-flag 禁用——39 iop 审计矩阵落地（D1/D2/D6 签核裁决）；LightamerIOPRegistry 默认面收窄缝（默认参数保 full face，1881 基线零破坏）；App/MCP 生产组装点接线；旧 sidecar/预设 round-trip 红线验证（degradedForUnknownOps 既有机制）；全套回归 0 fail"
wave: 1
depends_on: ["M2-0"]
autonomous: true
requirements: [M2DIS-01, M2DIS-02, M2DIS-03, M2DIS-05]
files_modified:
  - LightamerIOP/Sources/Registry.swift                                # 禁用缝正本：defaultFaceDisabledOpNames + populate(defaultFace:) + editingDefaultInstances(defaultFace:) + isFullFaceRequested 环境变量口
  - App/Sources/Lightamer/UI/LightamerApp.swift                        # 生产组装点 ×2（populate :867 / seedInstances :1481）传 defaultFace
  - App/Sources/Lightamer/State/PipeCoordinator.swift                  # pristine seed（:675 附近）传 defaultFace
  - App/Sources/Lightamer/State/InspectorState.swift                   # registerDefaultProviders(defaultFace:) 门控 6 个 panel 注册
  - App/Sources/Lightamer/MCP/McpServerController.swift                # 生产 editing seams（:224 populate）传 defaultFace
  - App/Sources/Lightamer/MCP/Tools/EditingToolset.swift               # editingSeed(:566)/defaultRecord(:634) 传 defaultFace
  - App/Sources/Lightamer/MCP/Tools/IopCatalog.swift                   # catalogJSON(defaultFace:) 过滤 sigmoid/agx/filmicrgb 三条目（ops 数据不动）
  - Tests/LightamerTests/DefaultFaceTests.swift                        # 新建：禁用集断言/种子面/round-trip/panel 面/catalog 面/MCP unknownOp 负例（新建文件 → tuist generate）
  - .work/gsd/phases/m2-1-dt-disable/M2-1-MATRIX.md                    # 已落盘（planner 产出）；T4 对照代码复核签字
  - .work/gsd/phases/m2-1-dt-disable/M2-1-SUMMARY.md
  - .work/gsd/phases/m2-1-dt-disable/M2-1-DECISIONS.md
  - .work/TODO.md                                                      # M2DIS-01/02/03/05 勾选（T4）
  - LESSONS.md                                                         # 如踩坑
---

# Plan M2-1 — dt 面 feature-flag 禁用（Alcedo 克隆重定义第一批执行）

> **性质**：机械性收窄 phase——零新算法、零管线改动、零 schema 升级。把 D1/D2/D6 签核裁决
>（ROADMAP M2 节，2026-09-27 用户「全按推荐」）落成 registry 层的默认面收窄，三处消费面
>（UI 面板枚举 / 预设与批量 apply / MCP 工具 schema）同步收窄。矩阵正本 =
> 同目录 `M2-1-MATRIX.md`（禁用 6 / 启用 33 / 灰区保留 14，逐模块 verdict + 理由）。
>
> **核心机制（一条缝管四面）**：`ModuleRegistry.makeBox(opName:)` 对未注册 op 返回 nil 是
> 02-06 以来全部消费面的统一寻址原语——禁用 = 默认面 populate 跳过注册。于是：
> ① UI 面板行枚举自 `editorState.instances`（种子收窄 → 行消失）；② 层 add-module 菜单
>（`InspectorView.addableTemplates`）同源种子 → 消失；③ MCP `apply_params` 的
> `projectInstances` 已按 `makeBox != nil` 寻址（`EditingToolset.swift:587`）→ 未注册 =
> typed `unknownOp` 拒绝（免费获得）；④ 旧 sidecar 走 `degradedForUnknownOps`
>（`LightamerSidecar.swift:565`）→ record verbatim + enabled=false + toast——
> **向后兼容红线（用户既有 .lra 不得失效）由既有机制承载，本 plan 只加测试钉**。

## 已定裁决（不得重开）

- **D1**：filmicrgb / sigmoid / agx **禁用**。DRT method 扩展回归位只在 DECISIONS 留一行注记，不实现。
- **D2**：denoiseprofile / nlmeans / bilateral **禁用**；降噪归 RAW 9 解码层。CIRAW NR 参数的
  RAW Decode 页签暴露属 M2-3/M2-5——本 plan **不做任何 UI**，仅保证禁用与 decode 管线零耦合
  （CIRAW 参数走 `RAWDecoder`，不经 iop registry——路径天然不堵）。
- **D6**：其余 Lightamer 独有/近似对应模块**全部保留启用**（含灰区 14 项，矩阵 §灰区表逐项理由）；
  七页签 IA 收纳属 M2-3，本 plan **不动 UI 布局**。
- **M2DIS-04** 不在本 plan requirements 内（UI 面属 M2-3）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 默认面语义 = 「不注册进默认 registry」（非「注册但 flagged 不可见」）

三案对比后裁决：**(a) 不注册** vs (b) 注册但 flagged vs (c) 注册+UI 隐藏。选 (a)：

- (a) 的向后兼容 = `degradedForUnknownOps` 既有机制（02-06 已交付、已测、产品级语义：
  params verbatim / enabled=false / toast / 永不丢数据），**零新机制**；且写面自动收窄
  （apply_params/preset 载入的禁用 op 一律 typed 拒绝或 degrade，不产生新的禁用 op 编辑）。
- (b) 保旧图渲染保真（filmic 视觉不回退），但需要在每个写面（apply_params/preset/batch/面板）
  逐一加 face 检查——四面新机制，且「禁用却仍在渲染」违背 D1/D2 的产品语义。
- 本项目重定义当周、无外部用户存量，旧图视觉回退可接受（toast 明示）；「可显式开启」口
  （KD-3）下旧图完整还原。
- 代价明确化（写进 SUMMARY）：旧 .lra 若启用过 filmic，重定义后打开 = 该 op 降级禁用 +
  一次性 toast + 渲染不再过 filmic。数据不丢，opt-in 后原样恢复。

### KD-2 「默认参数 = full face」——1881 基线零破坏的实现纪律

所有收窄 API 一律加 `defaultFace: Bool = false` 参数（默认 false = 现行为 = full face），
**只有生产组装点显式传 face**。全部既有测试（PanelWiringTests:358/1425/1473 断言
sigmoid/nlmeans/bilateral 面板在册、McpEditingToolsetTests:490 断言 catalog 18 ops、
 dozens 处 `editingDefaultInstances()` 消费）**不改一行保持全绿**；新测试显式传
`defaultFace: true` 断言收窄面。禁用集常量从模块 opName 常量构建（`FilmicRGBModule.opName`
 等），**禁止字符串字面量**防 typo。

### KD-3 opt-in 口 = launch 环境变量，无设置 UI

`LightamerIOPRegistry.isFullFaceRequested`：`ProcessInfo.processInfo.environment["LIGHTAMER_FULL_IOP_FACE"] == "1"`。
生产组装点传 `defaultFace: !isFullFaceRequested`。dev/调试/旧图复原 = `LIGHTAMER_FULL_IOP_FACE=1`
启动 app。设置页开关不做（设置页族属 M2-3 UIW-05）；该 env 口是 M2-3 届时的后端缝。

### KD-4 round-trip 行为结论（红线钉）

旧 sidecar/预设引用禁用模块：**可读、可写、不崩、数据不丢**——机制 = `degradedForUnknownOps`
（global history）+ `degradedLayerStack`（层链，`LightamerSidecar.swift:590`）：record 与
paramsData 字节原样保留、实例/整层 enabled=false、unknownOps 首现一次性 toast、sidecar 写回
保留原字节。用户预设浏览器**不隐藏**含禁用 op 的旧预设（用户数据）；apply 后禁用 op 不生效
（degrade 语义），部分应用选择器（PastePartialDialog）仍列 history 中既有项（历史展示 ≠ 编辑面，
不在 M2DIS-03 收窄范围）。T1 以字节级 round-trip 测试钉死此结论。

### KD-5 死代码与 prewarm 处置

`prewarmFunctionNames` **不动**（禁用 6 模块的 kernel 仍编译、仍预热 PSO——启动成本微增可接受，
换来 opt-in 即用零重建 + 死代码保留红线）。模块 .swift/.metal 源文件、golden 测试、parity
harness 全部保留照常跑（full face 默认下测试面无变化）。NoiseProfileStore、LutLibraryStore 等
伴生存储不动（服务启用模块或禁用模块自身，均无 UI 面）。

### KD-6 内置预设处置

实测仓内零 `.lightamer-preset` 资产（Phase 12 未随 app 分发内置预设目录）——「内置预设含 filmic
参数」风险**不存在**，无需处置。用户自建预设按 KD-4。若 M2-6 DRT 落地时需要内置 look 预设，
届时以 DRT 预设三件套（OpenDRT Look 7）形式新建，不复用 filmic 参数。

## read_first

1. `.work/gsd/ROADMAP.md` Milestone 2 节——M2-1 行 + D1/D2/D6 签核文本（本 plan 裁决正本）。
2. `.work/gsd/phases/m2-1-dt-disable/M2-1-MATRIX.md`——39 行矩阵（本 plan 的 verdict 正本，
   T4 对照代码复核）。
3. `LightamerIOP/Sources/Registry.swift`——全文（populate 注册表 / prewarmFunctionNames /
   editingDefaultInstances 种子；禁用缝落点，注释密度高，逐段读）。
4. `LightamerCore/Sources/Pipe/ModuleRegistry.swift`——makeBox nil 语义 / 02-06 unknown-op
   degrade 契约（head 注释）。
5. `LightamerCore/Sources/Sidecar/LightamerSidecar.swift:540-640`——`degradedForUnknownOps` +
   `degradedLayerStack`（KD-4 机制正本：verbatim + enabled=false + unknownOps 返回）。
6. `App/Sources/Lightamer/State/InspectorState.swift`——registerDefaultProviders 全表 +
   panelOpNames 消费面（LayerUIWiringTests:296 遍历处）。
7. `App/Sources/Lightamer/MCP/Tools/EditingToolset.swift:560-690`——editingSeed / projectInstances
   （:587 `makeBox != nil` 寻址 = MCP 面免费收窄的机制锚）/ defaultRecord。
8. `App/Sources/Lightamer/MCP/Tools/IopCatalog.swift`——ops 表 + catalogJSON 合成（18 条目中
   sigmoid/agx/filmicrgb 需 face 过滤；`ops` 数据不动保 McpEditingToolsetTests:490 反射守卫）。
9. `App/Sources/Lightamer/MCP/McpServerController.swift:200-260`——makeEditingSeams 自建
   registry（:224 populate——MCP 生产面第二个组装点）。
10. `AGENTS.md`「Phase 2 架构增量」节 + LESSONS L019b（test-direct.sh 直启纪律）、L009/L013/L014
    涉及面为零（本 plan 无管线/持久化/读回改动——零触碰即合规）。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits 全英文、subject ≤72 字符祈使句、
   body 写 what+why）；只 add 本任务申报文件；**不 push**。
2. **构建纪律**：`caffeinate -dis` 包裹一切构建；**构建勿加 `-derivedDataPath`**；
   **新建文件（T1 的 DefaultFaceTests.swift）后跑 `tuist generate`**（同 commit 内）。
3. **测试纪律**：单测命令 = `Scripts/test-direct.sh '<Class>'`；判据 = Executed 计数行 +
   failures 行双读（L028：退出态与结果行都要看）。**回归基线 = 1881/11skip/0fail**
   （读 `.work/GOAL-STATE.md` 续接点取最新，M2-1 只减不增 UI 可见面，测试数应基本持平；
   新增预估 +8..12）。每任务全套 suite 绿、0 fail；在案 flake（GoldenColor CI 腿等）
   单跑 ×3 归因入 SUMMARY 不计违约。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
5. **架构红线**：本 plan 禁触管线/持久化/色彩/Metal kernel 文件——diff 不得出现
   `LightamerCore/Sources/{Pipe,Sidecar}/` 生产文件改动（Sidecar 只读消费，不改）；
   grep 自检：T4 收口跑 `git diff --stat` 核对文件边界与 front-matter 申报一致。

## Tasks

### T1 禁用缝正本 + round-trip 红线钉（LightamerIOP + 新测试文件）

- **read_first**：上列 3/4/5/10。
- **action**
  1. `LightamerIOP/Sources/Registry.swift` 新增：
     - `public static let defaultFaceDisabledOpNames: Set<String>`——由 6 个模块 opName 常量
       构建（`FilmicRGBModule.opName` / `SigmoidModule.opName` / `AgXModule.opName` /
       `DenoiseProfileModule.opName` / `NLMeansModule.opName` / `BilateralModule.opName`，
       KD-2 禁字面量）；head 注释指向 M2-1-MATRIX.md（机器可读孪生声明）。
     - `public static var isFullFaceRequested: Bool`——env 口（KD-3，一行实现）。
     - `populate(_ registry:, defaultFace: Bool = false)`——注册循环内
       `defaultFace && defaultFaceDisabledOpNames.contains(opName)` → skip（实现形态自定：
       6 处注册点各自 gate 或统一 helper，**必须逐点注释 D1/D2 依据**）。
     - `editingDefaultInstances(defaultFace: Bool = false)`——返回前按同集合 filter。
  2. 新建 `Tests/LightamerTests/DefaultFaceTests.swift`（**新建文件 → `tuist generate`**）：
     - 禁用集常量 == 矩阵 6 opName 精确断言（防常量漂移）。
     - default-face populate：6 op `makeBox == nil`；启用集抽查（exposure/colorin/lut3d 等
       ≥8 个）`!= nil`；full-face populate（默认参数）6 op `!= nil`（KD-2 反向钉）。
     - default-face 种子：不含 6 opName；v50 sort 不变式保持；count == full − 6。
     - **round-trip 红线（KD-4）**：构造 sidecar document（global history 含 enabled
       filmicrgb 项 + 层链含 sigmoid 项，paramsData 任意非默认字节）→
       `degradedForUnknownOps(registry: default-face)` + `degradedLayerStack` → 断言
       record 保留（count 不变 / paramsData 字节相等 / enabled=false / unknownOps ==
       ["filmicrgb"] 层腿 ["sigmoid"]）；写盘 → 重读 → 字节面 round-trip 相等。
     - default-face 下 MCP `EditingToolset.projectInstances`：upsert filmicrgb →
       `McpToolError.unknownOp`；`remove: true` 仍放行（既有 `registered || op.remove`
       语义，删除不需要注册——钉注释）。
  3. `tuist generate` + `caffeinate -dis xcodebuild build-for-testing` +
     `Scripts/test-direct.sh 'DefaultFaceTests'` 绿 → 全套回归 0 fail。
- **验收标准**
  - [ ] `defaultFaceDisabledOpNames.count == 6` 且逐 opName 与 M2-1-MATRIX.md 禁用集相等（测试断言）。
  - [ ] default-face registry/种子断言全绿；full-face 默认参数反向钉全绿（既有测试零改动）。
  - [ ] round-trip 测试：record/paramsData 字节保留 + enabled=false + typed unknownOps 全绿。
  - [ ] 全套回归 `0 fail`，计数入 SUMMARY（预期 1881 + 本任务新增）。

### T2 App 生产组装点接线 + UI 面收窄

- **read_first**：上列 3/6 + `App/Sources/Lightamer/UI/LightamerApp.swift:860-880`（populate
  场景 task）与 `:1470-1495`（seedInstances）+ `PipeCoordinator.swift:655-690`（pristine seed）。
- **action**
  1. 三处生产种子/populate 调用传 `defaultFace: !LightamerIOPRegistry.isFullFaceRequested`：
     `LightamerApp.swift` populate（:867）+ `seedInstances()`（:1481）；`PipeCoordinator.swift`
     pristine seed（:675）。每处一行注释（M2-1 D1/D2 + KD-1/KD-3 指针）。
  2. `InspectorState.registerDefaultProviders(defaultFace: Bool = false)`——6 个 panel 注册
     （Sigmoid/FilmicRGB/AgX/NLMeans/DenoiseProfile/Bilateral）按 KD-2 gate；调用点
     `LightamerApp.swift:872` 传 face。
  3. 生产 preset/批量 apply 种子源验证（**预期零改动**）：确认 PresetApplier/SessionBatchApplier
     的 seed 由 App 侧收窄种子流入（grep 申报入 SUMMARY；若有旁路 full-face 种子生产源 = 本任务
     一并接线）。
  4. 测试补入 `DefaultFaceTests`：`registerDefaultProviders(defaultFace: true)` →
     `panelOpNames` 不含 6、含 exposure/colisa；默认参数调用 → 含 6（KD-2 反向钉）。
  5. 全套回归 0 fail。
- **验收标准**
  - [ ] 生产三组装点 + 面板注册全部走 face 参数；`git grep "editingDefaultInstances()" App/` 生产残留 = 0（测试目录除外）。
  - [ ] UI 枚举面（面板行/层 add-module 菜单）默认不含禁用集——机制 = 种子收窄（panel face 测试 + 种子测试双钉）。
  - [ ] 全套回归 `0 fail`。

### T3 MCP 面 + IopCatalog face 过滤

- **read_first**：上列 7/8/9 + `Tests/LightamerTests/McpRegistrySnapshotTests.swift`
  （工具面快照——**工具列表不变**（19 个），仅 list_iops 输出面变化，快照预期零改动）。
- **action**
  1. `McpServerController.makeEditingSeams`（:224）populate 传
     `defaultFace: !LightamerIOPRegistry.isFullFaceRequested`（生产 seams；测试 seams 若有
     独立构造保持 full face）。
  2. `EditingToolset.editingSeed`（:566）/ `defaultRecord`（:634）加
     `defaultFace: Bool = false` 参数并透传给 `editingDefaultInstances`；生产 handler 调用点
     传 face（从 seams 的 registry 同源——若 seams 无法携带布尔，`isFullFaceRequested` 直读，
     注释同源声明）。
  3. `IopCatalog`：新增 `static func defaultFaceOps()`（ops 过滤 3 条目：sigmoid/agx/filmicrgb）
     + `catalogJSON(defaultFace: Bool = false)` 按 face 选源；**`ops` 数据与 18 计数不动**
     （反射守卫 McpEditingToolsetTests:452/490 零改动保持绿——KD-2）。
  4. 测试补入 `DefaultFaceTests`：default-face `catalogJSON` 不含三 opName、含 temperature；
     full-face 含全部 18；list_iops 面经 `McpToolRegistry` 集成腿抽测（工具名集合仍 19 不变
     ——M2DIS-05「不删工具」字面钉）。
  5. 全套回归 0 fail。
- **验收标准**
  - [ ] MCP 默认 schema 面：`list_iops` 输出不含禁用集；`apply_params` upsert 禁用 op = typed `unknownOp`（T1 已钉）；工具注册面仍 19 个（不删工具）。
  - [ ] `IopCatalog.ops.count == 18` 既有反射守卫零改动全绿。
  - [ ] 全套回归 `0 fail`。

### T4 矩阵复核 + 文档同步 + 收口

- **read_first**：M2-1-MATRIX.md 全文 + 本 plan AC 表。
- **action**
  1. **矩阵对照复核**：逐行核对 M2-1-MATRIX.md verdict 与 `Registry.swift` 实际注册面
     （40 注册点逐个对号 + gamma/trio 附注）；复核结果签注入 MATRIX 尾节（「T4 复核：
     <date> <commit> 一致」或差异修正）。
  2. AC 终验（下表逐条机检）+ 全套回归终跑（计数/秒数入 SUMMARY）。
  3. 落盘 `M2-1-SUMMARY.md`（含：测试数变化 / 旧图视觉回退代价声明（KD-1）/ preset seed
     验证结论（T2.3）/ flake 归因）+ `M2-1-DECISIONS.md`（KD-1..6 执行确认 + D1 DRT method
     扩展注记一行：「filmicrgb/sigmoid/agx parity 后评估以 DRT method 扩展身份回归——M2-6
     后议题，本 phase 未实现」）。
  4. `.work/TODO.md` M2DIS-01/02/03/05 勾选（M2DIS-04 留 M2-3）；`.work/GOAL-STATE.md`
     M2-1 翻账 + 续接点更新；LESSONS 如踩坑。
  5. 文档一致性 commit guard（全局 §3.1）：TODO 勾选态 = REQUIREMENTS 实况 = SUMMARY 结论。
- **验收标准**
  - [ ] MATRIX 尾节复核签注在案；矩阵 verdict 与代码注册面逐行一致。
  - [ ] AC 表全绿（见下节）；SUMMARY/DECISIONS/TODO/GOAL-STATE 同批更新。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 禁用集 = {filmicrgb, sigmoid, agx, denoiseprofile, nlmeans, bilateral} 恰 6 项 | DefaultFaceTests 常量相等断言 |
| 2 | 默认面 registry 不含禁用集；启用集 + 终端三件套全部可寻址 | makeBox nil/非 nil 断言 |
| 3 | 默认面种子不含禁用集；v50 sort 不变式保持 | 种子断言 |
| 4 | 旧 sidecar（global + 层链）含禁用 op：record/paramsData 字节保留、enabled=false、typed unknownOps、写读 round-trip 字节相等 | degradedForUnknownOps/degradedLayerStack 测试 |
| 5 | 预设含禁用 op：载入不崩、apply 后 degrade 不生效（Payload 直构 + 既有 degrade 面；浏览器不隐藏用户预设） | 既有 PresetApplier 测试面零回归 + T1 round-trip 同机制覆盖 |
| 6 | UI 默认枚举面（面板行/层 add-module/panelOpNames）不含禁用集 | panel face 测试 |
| 7 | MCP 默认面：list_iops 输出无禁用集；apply_params 禁用 op = unknownOp；工具注册面仍 19（不删工具） | catalog face 测试 + registry 集成腿 |
| 8 | 显式 opt-in（`LIGHTAMER_FULL_IOP_FACE=1` 语义）恢复 full face——参数化 API 正反双向钉 | defaultFace false/true 对偶断言 |
| 9 | 全套回归 0 fail；测试数 ≈ 基线 1881 + 8..12 | test-direct.sh Executed/failures 行 |
| 10 | diff 边界 = front-matter 申报文件集；`LightamerCore/Sources/{Pipe,Sidecar}/` 生产文件零改动 | `git diff --stat` 逐任务核对 |

## 风险与边界

- **旧图视觉回退**（KD-1 已裁决接受）：旧 .lra 的 filmic/降噪视觉不再渲染，toast 明示，
  opt-in 可复原。数据零丢失（字节级测试钉）。
- **prewarm/PSO 死代码**：保留（KD-5）——启动预热含禁用模块 kernel 家族，成本可测量不入门。
- **内置预设/LUT 库**：实测零内置预设资产（KD-6 风险关闭）；LUT 库服务 lut3d（启用）零交集。
- **denoiseprofile 的 NoiseProfileStore**：模块代码保留即存储保留，无孤儿面。
- **不改 UI 布局**：七页签收纳、CIRAW NR 的 RAW Decode 页签、设置页开关均属 M2-3/M2-5——
  本 plan 的 UI 面变化仅为「行消失」，无新布局代码。
- **在案 flake**：GoldenColor CI 腿等既有 flake 单跑 ×3 归因，不计违约（纪律 3）。

## 提交约定

- T1 `feat(iop): default-face disable seam for D1/D2 modules with round-trip pins`
- T2 `feat(app): wire default face at composition roots and gate disabled panels`
- T3 `feat(mcp): narrow default mcp face via registry and iop catalog filter`
- T4 `docs(m2-1): close out disable matrix, sync ledgers and summaries`
- 全英文 Conventional Commits；body 说明 what+why + 同批同步的 md 清单（§3.1 commit guard）；
  git add 一律 `.work/gsd/...` 真路径（`.planning` 符号链接垫片 git 不穿透）；不 push。

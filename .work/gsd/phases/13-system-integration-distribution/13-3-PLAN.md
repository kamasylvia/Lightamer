---
phase: 13
plan: "13-3"
title: "交互与 UI 批（SYS-03/04/05）：ViewportFit 单点扩展 viewportTransform（fit/100%/自由 zoom + 光标锚定 + blit uniforms 扩展，禁第二份 fit 数学）+ AppKit 手势面（magnify/rotate/scrollWheel 双指平移挂 MTKView bridge + zoom HUD）+ overlay 互斥（crop/liquify/retouch 锁 fit；mask brush 逆映射 <1px；eyedropper uv 同 transform）+ 拖放导入（默认复制 Capture/ Option=Move、网格+编辑器双落点、openSession reconcile 路由）+ 蒙版命令面 UI 装配（五命令 + overlay 三态 + enable 勾选，内核零改 + GUI-19）+ SYS-05 本地化收口审计"
wave: 2
depends_on: ["13-1"]
autonomous: true
requirements: [SYS-03, SYS-04, SYS-05]
files_modified:
  - App/Sources/Lightamer/UI/Overlay/ViewportFit.swift                 # 单点扩展：fittedRect 基础上新增 viewportTransform（zoom/pan/rotate 状态 → 全消费者唯一变换源；禁止第二份 fit/zoom 数学）
  - App/Sources/Lightamer/UI/EditorMTKView.swift                      # :12 near-static 注释翻转（D-13 预留兑现）+ :318 aspectFitUniforms 加 zoom/pan(/rotate) 偏移向量 + NSView 手势面（magnify/rotate/scrollWheel 或 NSGestureRecognizer）
  - App/Sources/Lightamer/State/ViewportState.swift                   # 新建（如悬)：zoom 状态机（fit/100%/自由）+ pan/rotate 值容器 + overlay 互斥锁（挂点按 App 既有 State 归位，执行期核名）
  - App/Sources/Lightamer/UI/EditorAreaView.swift                     # :227 SpatialTapGesture 旁的手势协调 + 双落点 onDrop（编辑器区）+ zoom HUD
  - App/Sources/Lightamer/UI/EmptyStateView.swift                     # :57 onDrop fileURL 先例扩文件级（空态落点）
  - App/Sources/Lightamer/Session/（网格落点 onDrop + 导入编排调用面）  # 会话网格 onDrop → 导入编排（复制入 Capture/ + reconcile 触发；文件级归位执行期核名）
  - App/Sources/Lightamer/Session/ImportService.swift                 # 新建（如悬）：FileManager.copyItem 批量导入 + 逐文件失败不中断 + 进度/取消 + Option=Move 显式意图（Core 级可测则落 Core；执行期核名归位）
  - App/Sources/Lightamer/UI/Inspector/LayersPanelView.swift          # 蒙版列表五命令上下文菜单 + enable 勾选行 + GUI-19 层链行显示修复
  - App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift            # overlay 三态切换（On-Black / Rubylith / 半透明——显示样式枚举扩展）
  - App/Sources/Lightamer/State/LayerEditingState.swift               # 命令路由（Duplicate/Duplicate-and-Invert/Fill/Clear/Reset Edits → LayerStack 既有编辑入口，每步 history commit）
  - App/Sources/Lightamer/Resources/Localizable.xcstrings             # 新 UI 全键 zh/en 同批（L025）
  - Tests/LightamerTests/ViewportTransformTests.swift                 # 新建：zoom/pan/rotate 数学 pattern（L021 扩展）+ 互斥矩阵 + mask 命中 <1px + eyedropper uv
  - Tests/LightamerTests/ImportDropTests.swift                        # 新建：复制语义源零改动 golden / 批量失败单列 / 无修饰键绝不 Move / reconcile 收编
  - Tests/LightamerTests/MaskCommandTests.swift                       # 新建：五命令语义/内核零改对照/每步 history 可退
  - .work/gsd/phases/13-system-integration-distribution/13-3-SUMMARY.md
  - .work/gsd/phases/13-system-integration-distribution/13-3-DECISIONS.md
  - TODO.md                                                           # 13-3 勾选 + GUI-19 关闭
  - LESSONS.md                                                        # 如踩坑
---

# Plan 13-3 — 交互与 UI 批（W2，与 13-2 并行波）

> 背景：视口从 near-static 升级 zoom/pan/rotate 是 Phase 2 D-13 决策的首次翻转（`EditorMTKView.swift:12/:318` 明示预留位）；最大回归面 = overlay 体系全部假设 fit 布局（`ViewportFit.swift:7-16` 三消费者共享 `fittedRect`）——按 D-13-CONTEXT-6 互斥策略错峰（D-13-CONTEXT-6/7/9）。
> 四条主线：① **手势（SYS-03）**——AppKit NSGestureRecognizer/NSView 覆写面（macOS 触控板原生事件流），zoom 状态机 fit/100%/自由（光标中心锚定），`ViewportFit` 单点扩为 `viewportTransform` 供全部消费者取用，**禁止第二份 fit/zoom 数学**；overlay 互斥 = crop/liquify/retouch 激活时 zoom 锁 fit（v1 从简，crop-while-zoomed deferred）。② **拖放导入（SYS-04）**——默认复制入 `Capture/`（Move = Option 显式意图）、网格 + 编辑器双落点、复用 openSession reconcile 收编。③ **蒙版命令面（2026-09-26 登记批）**——Duplicate / Duplicate-and-Invert / Fill / Clear / Reset Edits 五命令 + overlay 三态 + enable 勾选，内核零改纯 UI 装配（`duplicated()`/`inverted` 位/`fill` 全已验）+ GUI-19 同批。④ **SYS-05 收口审计**——本 Phase 新 UI 每键 zh 同批 + 全 UI 面 zh/en 审计收口。内部序：T1 数学先行（T2/T3 消费）→ T2 手势 → T3 互斥/逆映射 → T4 拖放 → T5 蒙版命令 → T6 本地化收口。

## read_first

1. `.work/gsd/phases/13-system-integration-distribution/13-CONTEXT.md`——D-13-CONTEXT-6（AppKit 面/zoom 状态机/单点扩展/互斥四裁决）、D-13-CONTEXT-7（拖放五裁决：默认复制/双落点/路由复用/批量失败/源零改动）、D-13-CONTEXT-9（蒙版命令面六裁决：内核零改/enable=既有字段/GUI-19 同批）、继承定案（SYS-05 收口非新框架/L021/L025/L032）、验证红线（手势/overlay 安全 + 拖放专项——逐条为本 plan AC 正本）
2. `App/Sources/Lightamer/UI/Overlay/ViewportFit.swift` 全文——:7-16 三消费者单点声明（**本 plan 纪律正本**）/ :33 `fittedRect`（`viewportTransform` 扩展基座）
3. `App/Sources/Lightamer/UI/EditorMTKView.swift`——:12 near-static blit (D-13: no zoom/pan) 注释（本 plan 翻转）/ :318 aspectFitUniforms + fit/100% 预留注释（blit 腿扩展位）/ SpatialTapGesture 既有手势锚（`EditorAreaView.swift:227`）
4. `App/Sources/Lightamer/UI/EmptyStateView.swift:57`（onDrop fileURL 先例——拖放实现参照）+ `LayersPanelView` 层拖拽 NSItemProvider/onDrop 对（同）
5. `LightamerCore/Sources/Layers/AdjustmentLayer.swift`——:43 `enabled`（enable 勾选 = 既有字段 UI 暴露）/ :76-81 `duplicated()` 新 UUID 克隆语义；`LightamerCore/Sources/Layers/Masks/MaskCombiner.swift`——:47 `inverted` 位 / :266 `fill` 常数平面
6. `App/Sources/Lightamer/State/LayerEditingState.swift`（命令路由状态面）+ `App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift`（334 行，overlay 三态显示选项扩展位）+ `LayersPanelView.swift`（673 行，蒙版列表/勾选挂点 + GUI-19 正主）
7. Phase 9 Session 面：`SessionCoordinator` openSession 五步 + reconcile（新文件 → 扫描器 diff 收编——拖放导入完成后的索引入网路由）；`.work/gsd/phases/09-session-management/09-CONTEXT.md`（:41-42 `.lightamer/` 派生缓存落位）
8. `LESSONS.md` L019b（直启宿主）/ L021（overlay/视口观察层量化——zoom pattern 测试与走查口径）/ L025（zh 键纪律）/ L032（合成 CGEvent 未达 SwiftUI 工具条——手势自动化边界，交互观感走查 Manual-Only 的原因）+ `AGENTS.md` + `.work/GOAL-STATE.md`

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 本任务申报文件）；`caffeinate -dis` 包裹一切构建。
- **单测命令** = `Scripts/test-direct.sh '<Class>'`；**判据 = Executed 计数行 + failures 行**，Executed 0 = 判据失败。
- **每任务边界检查 `.work/config.toml [gsd]` 开关（`auto`/`paused`）**——commit 后、下一任务前：`paused=true` 全链路停；`auto=false` 完成当前任务后停等「继续」。
- **不 push**。
- **构建勿加 `-derivedDataPath`**；本 plan 无新 target，每新建源文件后照例 `tuist generate` 一次。
- **回归基线 = 1553/9skip/0fail**；每任务全套 suite 绿；收尾轮 = 1553 + 新增，0 fail。**flake 归因条款**：`LayerE2ERoundTripTests` / `ToneEqualPerf` 负载型 flake 隔离 ×3 归因单列 SUMMARY，不计违约。
- **凭据阻塞项提醒义务**：执行中若知悉 Developer ID/AC API key/GitHub 仓仍未就位，SUMMARY + GOAL-STATE 阻塞节登记提醒（13-4 供件），本 plan 不消费。
- **fit/zoom 数学单点红线**：`ViewportFit` 是三消费者共享的唯一数学源——zoom/pan/rotate 只扩此一处，任何消费端（blit uniforms/mask 绘制/eyedropper/overlay）不得复制第二份变换数学（`ViewportFit.swift:7-16` 本职声明）。
- **蒙版内核零改红线**：`AdjustmentLayer`/`MaskCombiner`/combine 装配 Phase 6 已验面零触碰——本批纯 App 层 UI 装配 + 命令路由；新命令每步过 history（⌘Z 可退逐命令断言）。
- **拖放安全语义**：默认恒复制；Move 仅 Option 修饰键显式意图（无修饰键绝不搬移——golden 断言）；源文件零改动；批量失败逐文件报错不中断。
- **L031 声明**：本 plan 无新 Metal kernel/无新 GPU 提交面（blit uniforms 扩展 = 既有 blit 参数化）——`makeRoutedCommandBuffer()` 红线预期不触；如执行中发现需要即停下报告。
- **GUI 走查标注**：手势/zoom HUD/拖放观感与蒙版命令操作面走查**需解锁控制台（Manual-Only 候补）**（L032：合成 CGEvent 未达 SwiftUI 工具条——自动化腿钉逻辑，观感归 13-4 走查批）。
- **zh 键同步**：zoom HUD/拖放提示/蒙版命令菜单/Settings 新增每键 zh 同批（L025 smoke 数字随 suite 报）。
- RESEARCH/CONTEXT 未覆盖细节（zoom HUD 形态：百分比指示 vs 滑杆、100%/fit 快捷键、蒙版命令快捷键表、旋转复位交互、导入冲突重名策略沿用既有 rename/skip 语义）标注**执行期决策**入 `13-3-DECISIONS.md`，不臆造。

## Tasks

### T1 ViewportFit 单点扩展：viewportTransform（数学先行）

- **action**
  1. `ViewportFit.swift`：在 `fittedRect` 基础上新增 `viewportTransform`（zoom 量 + pan 偏移 + rotate 角 → uv/点双向映射函数对）——zoom 状态机三态的数学承载：**fit（默认）/ 100% 像素 / 自由缩放（光标中心锚定）**；正逆双向映射（正 = 图像 uv → 视口点；逆 = 视口点 → uv——mask 命中与 eyedropper 消费逆向）。
  2. 状态容器 + 互斥锁（`ViewportState` 或挂 App 既有 State 归位，执行期核名）：zoom/pan/rotate 值 + `zoomLocked` 标志（crop/liquify/retouch 激活时置位，切面板自动回 fit）。
  3. blit 腿：`aspectFitUniforms`（`EditorMTKView.swift:318`）加 zoom/pan(/rotate) 偏移向量——同一 `viewportTransform` 产物，不另算。
  4. `EditorMTKView.swift:12` near-static 注释翻转（D-13 预留兑现记录）。
- **证据**：`ViewportTransformTests`——zoom/pan/rotate 正逆映射往返精度 pattern（L021 观察层量化口径扩展）；fit 态 = 恒等变换回归锁（既有 fit 布零漂移）；100% 态数学锚；光标锚定（zoom 前后光标下 uv 点不动）。

### T2 AppKit 手势面（magnify / rotate / scrollWheel + zoom HUD）

- **action**
  1. `EditorMTKView.swift` NSView 面（子类覆写或 NSGestureRecognizer，实现期定）：`magnify(with:)` 捏合缩放（光标锚定）、`rotate(with:)` 旋转、`scrollWheel(with:)` 双指平移（连续 delta）；键鼠兜底（⌘+滚轮缩放等，执行期决策）。SwiftUI 手势面不用（锚点/结束态表达力不足，D-13-CONTEXT-6①）。
  2. zoom HUD（形态执行期决策：百分比指示/滑杆）：显示当前 zoom 态与值；fit/100% 快捷切换（快捷键执行期决策）。
  3. 手势驱动的状态推进全部经 T1 状态容器（无第二份数学）。
- **证据**：状态推进单测（注入手势 delta → 状态/变换断言）；真机触控板观感**需解锁控制台（Manual-Only 候补）**（L032 自动化边界）。

### T3 overlay 互斥 + mask 绘制逆映射 + eyedropper 同步

- **action**
  1. **互斥矩阵**：crop/liquify/retouch 面板激活 → zoom/pan 输入被吞 + zoom 锁 fit + 切面板自动回 fit；mask brush/stamp **不在禁用集**（绘制坐标经 `viewportTransform` 逆映射）。
  2. mask 绘制/eyedropper/crop overlay uv 取样同步走新 transform（同一函数零特判——`ViewportFit` 三消费者全部切换到 `viewportTransform` 取点）。
- **证据**：`ViewportTransformTests` 扩段——互斥矩阵断言（三 overlay 各自激活时 zoom 输入零效 + 自动回 fit）；**zoom 后 mask stamp 命中精度门**（光标点 vs 落点 <1px）；eyedropper uv 经 transform 后取样正确；zoom 态下 overlay 走查**需解锁控制台（Manual-Only 候补）**。

### T4 拖放导入（SYS-04 双落点）

- **action**
  1. **网格落点**：拖入已开会话网格/窗口 → 默认**复制**文件入该会话 `Capture/`（Option+拖 = 移动，显式意图）；批量多文件 + 进度/取消（大文件 USB 卷场景，L009 环境自警）。
  2. **编辑器区落点**：拖入编辑器 = 单图直接编辑（既有 `EditorState.load` 原样，sidecar 随图落原图旁）；**空态/无会话落点**：走既有「文件夹→会话」打开（`EmptyStateView.swift:57` onDrop 先例扩文件级）。
  3. 导入编排（`ImportService` 或归位既有会话服务，Core 级可测部分下沉）：同盘/跨盘统一 `FileManager.copyItem` + 失败逐文件报错不中断批；导入完成后索引入网格 = `openSession` 编排既有 reconcile（显式 refresh 触发，不依赖 FSEvents 时序）。
- **证据**：`ImportDropTests`——复制语义源文件零改动 golden（源目录内容/mtim 不变）；批量失败单列不中断；**无修饰键绝不 Move**（源文件存活断言）；Option 语义显式移动 golden；reconcile 收编断言（导入后 lindex 行就位）。

### T5 蒙版命令面 UI 装配（内核零改 + GUI-19）

- **action**
  1. 五命令挂蒙版列表上下文菜单 + 快捷键表（执行期决策）：`Duplicate`（= `AdjustmentLayer.duplicated()` 新 UUID 克隆）/ `Duplicate-and-Invert`（= duplicated + `MaskCombiner.inverted` 位翻转 `:47`）/ `Fill`（= `MaskCombiner.fill` 常数平面 `:266`）/ `Clear`（归零 mask 记录）/ `Reset Edits`（该蒙版实例参数回默认）。路由走 `LayerEditingState` → LayerStack 既有编辑入口，**每步过 history**（⌘Z 可退）。
  2. overlay 三态切换（`MaskToolbarView.swift` 显示选项扩展）：On-Black / Rubylith / 半透明——显示样式枚举，不改蒙版数据。
  3. 蒙版列表 **enable 勾选** = `AdjustmentLayer.enabled`（`:43`）既有字段的 UI 暴露（列表行 checkbox），勾选切换走既有 history commit 语义。
  4. **GUI-19 同批修复**（TODO :296 登记正主）：层链行不显示问题修复。
- **证据**：`MaskCommandTests`——五命令语义逐一（内核零改对照：Phase 6 既有语义测试全绿不动 + 命令后内核状态 = 直调内核等价）；每步 history 可退断言；enable 勾选 = 既有字段往返；GUI-19 修复面走查**需解锁控制台（Manual-Only 候补）**。

### T6 SYS-05 本地化收口审计 + 全量回归收口

- **action**
  1. **SYS-05 收口审计**（非新框架——String Catalog 结构已在）：本 Phase 全部新 UI（zoom HUD/拖放提示/蒙版命令菜单/overlay 三态/Settings 与 proof 面新增项——13-2 侧键由其 plan 自带，此处审计收口全 UI 面）逐键 zh 同批（L025 smoke 数字随 suite 报）；zh/en 键集 diff 审计（缺译零容忍）；系统语言跟随 = xcstrings 本职零代码（构建走查确认无硬编文案漏网）。
  2. 全 suite 终轮（基线 **1553/9skip/0fail** + 新增，0 fail）；TODO.md 13-3 勾选 + GUI-19 关闭；`13-3-SUMMARY.md` + `13-3-DECISIONS.md`（HUD 形态/快捷键表/旋转复位/重名策略/State 归位核名等执行期决策）；新教训候选评估入 LESSONS。
- **证据**：L025 smoke 计数 + zh/en 键审计输出；测试计数（1553 → N，0 fail）；SUMMARY + DECISIONS 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| viewportTransform | 正逆映射精度 + fit 恒等回归锁 + 光标锚定 + blit uniforms | `Scripts/test-direct.sh 'ViewportTransformTests'` |
| 手势 | 状态推进单测 + HUD wiring | `Scripts/test-direct.sh`（手势段）+ 走查 Manual-Only 候补 |
| overlay 互斥 | 互斥矩阵 + mask 命中 <1px + eyedropper uv | `Scripts/test-direct.sh 'ViewportTransformTests'`（互斥段） |
| 拖放 | 源零改动 / 批量失败单列 / 绝不 Move / reconcile | `Scripts/test-direct.sh 'ImportDropTests'` |
| 蒙版命令 | 五命令语义 + history 可退 + 内核零改对照 | `Scripts/test-direct.sh 'MaskCommandTests'` |
| 本地化 | L025 smoke + zh/en 键审计零缺译 | suite 计数 + 审计输出（SUMMARY 贴证） |
| 回归 | 全 suite 0 fail（基线 1553+新增） | `caffeinate -dis Scripts/test-direct.sh`（全套） |

## 验收标准（Acceptance）

- [ ] `viewportTransform` 单点扩展：fit/100%/自由三态 + 光标中心锚定 + 正逆映射对 + blit uniforms 同源——三消费者全部切换、零第二份 fit/zoom 数学
- [ ] 手势面：magnify/rotate/scrollWheel 双指平移挂 AppKit 面 + zoom HUD + fit/100% 切换；触控板观感走查登记 Manual-Only 候补
- [ ] overlay 安全：crop/liquify/retouch 激活锁 fit 互斥矩阵断言 + mask stamp zoom 后命中 <1px + eyedropper uv 正确
- [ ] 拖放：默认复制 Capture/（Option=Move 显式意图）+ 网格/编辑器/空态三落点 + 批量失败单列 + 源文件零改动 golden + reconcile 收编
- [ ] 蒙版命令面：五命令（Duplicate/Duplicate-and-Invert/Fill/Clear/Reset Edits）+ overlay 三态 + enable 勾选——内核零改（Phase 6 测试全绿不动）+ 每步 history 可退 + GUI-19 关闭
- [ ] SYS-05：新 UI 全键 zh 同批（L025 smoke 数字随 suite 报）+ zh/en 键审计零缺译
- [ ] 全 suite 0 fail（1553+新增）；每任务独立提交 + 边界查 config 开关 ×6；不 push；SUMMARY + DECISIONS 落盘

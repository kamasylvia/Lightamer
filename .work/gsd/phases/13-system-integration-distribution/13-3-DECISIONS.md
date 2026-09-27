# Plan 13-3 — 执行期决策（DECISIONS）

> 执行日 2026-09-27。RESEARCH/CONTEXT 未覆盖细节按 plan 纪律逐条落档，不臆造；与上游裁决冲突处显式标注勘误与依据。

## D-13-3-1: zoom HUD 形态与快捷键表

- **形态** = 紧凑胶囊 `[−] [label] [+] │ [fit] [1:1]`，挂视口 **topLeading**（compare HUD 居中、soft-proof 胶囊 topTrailing——三浮层不重叠）。label 显示 `Fit` / `100%` / 自由百分比；**双击 label = 旋转复位**（锚视口中心，图像原位）。
- **快捷键** = 翻转 Phase 1 既有的两个 disabled 占位：`Actual Size` = bare `Z`、`Fit to Screen` = bare `F`（D-8 冲突表核对：bare z/f 空闲；元数据占 bare 0-5/x/p）。二指双击（smartMagnify）= fit ↔ 100% 切换。
- **锁定面**：overlay 互斥锁持有期间 HUD 整体 disabled。

## D-13-3-2: 缩放范围与灵敏度

- 自由缩放范围 = **[min(1, 100%), 32×fit]**：下限在正常图 = fit（1.0）；**小于视口的图**允许下探到 100% 因子（1px=1pt 是硬语义，可能 < fit）。
- ⌘-滚轮缩放灵敏度 = `0.08/tick`（乘性，scroll-up 放大——通用看图器约定）；HUD ± 按钮 = ×1.25 步进（锚视口中心）。
- pan 手势符号约定 = **delta 取负**（content follows fingers，自然滚动约定）；pristine fit 态（zoom=1、无旋转、无 pan）的 pan 输入忽略——无可平移内容。任何 zoom/旋转输入把 mode 推进 `.free`；`fit()` 恢复恒等并回 `.fit`。

## D-13-3-3: ViewportState 归位 + 菜单几何缝

- 状态容器归位核名结果 = **新建 `App/Sources/Lightamer/State/ViewportState.swift`**（@MainActor @Observable，D-03b 隔离状态；不挂 EditorState/PipeCoordinator）。App root `@State` 持有 + environment 注入；App 场景（View 菜单）直驱。
- 菜单命令（App scene）拿不到视口几何 → **记住几何缝**：`noteGeometry(viewportSize:textureSize:)` 由 EditorAreaView/EditorMTKView 每次推送，`actualSize()` 无参形态用记忆值（陈旧可容忍——fit/100% 均可再按手势修正）。

## D-13-3-4: 【勘误】拖放导入目标 = 会话根（非字面 Capture/）

- plan/CONTEXT 字面「默认复制入 `Capture/`」与 **D-09-CONTEXT-3（09 裁决、用户确认「全按推荐」）直接矛盾**：根级 `Capture/Crop/Output` 在浏览集排除表内（`SessionTreeScanner.isExcludedDirectory` + `skipDescendants`），复制进 `Capture/` 的文件**永远不可能被 scan/index 收编**——plan 自己的 AC「reconcile 收编（导入后 lindex 行就位）」在字面目标下死局。
- **裁决 = 按继承定案优先 + AC 意图**：导入目标 = **会话根**（Lightamer 布局中浏览集的"拍摄层"就是会话根）；`ImportService.importFiles(at:into:)` 泛化目录参数，`importHandler` 传根。测试 `testImportLandsLindexRowThroughExplicitReconcile` 断言根级 relPath 行就位。
- **重名策略** = skip 永不覆盖（仓库内无既有 import rename 语义可沿用——FileOpener 只有打开无导入；覆盖可能毁已编辑原图，安全默认 + toast 报失败清单）。
- **多文件拖编辑器/空态** = 取第一个加载（编辑器 = 单图语义，sidecar 随原图落）；空态目录 vs 文件路由 = 目录→openSession、文件→单图编辑。

## D-13-3-5: 蒙版命令语义落定（内核零改的记录级实现）

- **Duplicate** = 既有 `EditorState.duplicateLayer`（新身份克隆，mask 值拷贝随行）。
- **Duplicate-and-Invert** = clone + 反转位翻转，**2 条 history items**（结构项 + 属性项，两步 ⌘Z）——单条复合项需要新 EditorState 结构入口，超出本 plan 文件清单，文档化取舍。反转位覆盖全 payload：group items（递归 child）、无 group 的 drawn 规格补建全反 group（dt per-item bit 语义）、parametric `invert`、raster `invert`。
- **Fill** = mask 记录置为**空 `MaskSpec`**（版本 1 无任何 payload）——即 Phase 6 简并三元组的常数 1 passthrough 契约，合成结果与 `MaskCombiner.fill(1)` 平面等价而**零内核/GPU 依赖**（App 层调 GPU fill 会把 MetalContext 拖进命令路由，且违背内核零改红线）。
- **Clear** = mask 记录整个置 nil（chip 空态）。与 Fill 合成等价、记录不同（Fill 保留"有蒙版"的记录面）。
- **Reset Edits** = 层 chain 清空、**mask 保留**（命令挂蒙版上下文菜单；"edits" = 蒙版所应用的 iop 参数）。
- **快捷键** = v1 不设全局（bare/⌘0-6 已被元数据三态占用，冲突面大），仅 context menu；13-4 走查批再评估。
- **enable 勾选** = `AdjustmentLayer.enabled` 既有字段 UI 暴露（`LayerCompositeDriver:376` 真实渲染门），toggle = 1 条 `commitLayerEdit`（与 eye/rename/blend 同路径）。

## D-13-3-6: overlay 三态 = 同内核三参数化

- `mask_overlay_display` 内核零改：半透明 = 黄 tint @0.85（06-3 现状原样）、Rubylith = 红 tint @0.6、On-Black = **黑底白蒙** @1.0。
- 黑底平面 = CPU 零填充 `.shared` 纹理（`replace(region:)` 写零字节）——**零 GPU 提交**，L031（无新 GPU 面）红线保持；跨 await 用既有 `SendableTextureBox` 所有权缝。
- style 是显示参数，只随 overlay request 元组走（`(layerID, strength, style)`），**永不进记录/history/sidecar**。style 翻转即时 re-issue request（GUI-15 教训：request 变更必须重渲染）。

## D-13-3-7: blit 腿锚点校正（plan :318 锚已退役）

- plan 写「:318 aspectFitUniforms 加 zoom/pan 偏移」——实测该函数 **04-06 已被 `fitQuad` 退役**（仅剩 doc chain）。活腿 = `fitQuad`：四角 uv 经 `ViewportFit.transform` 正映射再 NDC；**角点↔uv 配对按 shader 契约不变**（p0↔uv(0,1)、p1↔uv(1,1)、p2↔uv(0,0)、p3↔uv(1,0)——identity 下与 04-02 四角逐值相等，CropOverlayTests 全绿背书）。
- NDC 映射改用 **bounds（points）** 驱动（drawable=bounds×backingScale 均匀因子，NDC 比值恒等；pan 是 point 空间偏移不能被重缩放）。`aspectFitUniforms` 注释翻转指向 fitQuad（doc chain 义务履行）。

## D-13-3-8: mask/segment 命中语义变更（zoom 正确性）

- 图像内容外点击**不再 clamp 到边缘落点**（06-05 行为）→ 忽略（zoom/旋转下 clamp 会产生假命中；逆映射 nil = 不画）。拖拽中途滑出内容 = 该 tick 跳过，笔画断点合法。
- handle 命中检验从「归一化空间距离」改 **SCREEN 空间 16px**（缩放/旋转不变量；handle 圆点本来就是屏幕常量尺寸）。
- Segment 路由不在互斥锁集合 → 同步切换 transform 逆映射（plan"三消费者全部切换"精神的补全——07-3 tap 点同样不能假设 fit）。

## D-13-3-9: Catalogs 投影不挂导入钩子

- 导入后的 catalog 副本（.lcat）待下一次 open/sweep 收编（RQ-16-4 触发面 v1 不扩）；session lindex 是显式 reconcile 即时收编。登记为 16 面 follow-up 候补，非本 plan 缺口。

## D-13-3-10: MaskCommandTests bootstrap 勘误（测试基建发现）

- 纯单测环境 `EditorState` 的 `instances/baseInstances` 为空时，`commitLayerStructure` 的 placeholder guard **静默吞 commit**（真 app 流由 decode 种子兜住，永不触发）。测试用 `resetHistoryForNewImage(defaultInstances:)` 显式 seed 一条记录。LESSONS 候补（静默吞提交的 guard 在测试环境造成「命令零效果」假象——排查耗时两轮）。

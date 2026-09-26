# 04-08 DECISIONS

## D-08-T1-1 flip 面板形态：9 态离散 Picker（2026-09-21，executor）

dt `flip.c:gui_init` 是 4 按钮（rotate CCW/CW、flip H/V）对当前 orientation 做 XOR 翻转（`do_rotate`/`_flip_h`/`_flip_v`，`flip.c:528-600`）。
Lightamer 简化为 9 选项 Picker（EXIF auto + 8 态直选）+ 离散 one-commit：

- Picker 与现有 aspect 预设同形态（AX PopUp 路径已有 04-02-e 实证），a11y identifier 直给；
- XOR 按钮组需要"读当前值→异或→回写"三步 + 4 个 action，代码量更大且 AX 要钉 4 按钮；
- EXIF auto 项保留（dt `ORIENTATION_NULL` 默认语义；持久化 `.auto` 按 FlipModule divergence #1 回退 identity，未来 load-path 再 resolve）。

## D-08-T2-1 GUI-8 根因：接线完好，失败路径反馈落在面板局部 notice（2026-09-21，executor）

诊断链（AshiftPanelView → InspectorState → Vision，全读完）：

- 按钮 action 接线完好：`Button { autoLevel() }` / `Button { autoPerspective() }` 直调同步 Vision façade；
- `InspectorEditSession.detectionSourceImage()` → `PipeCoordinator.decoded`，有图时非 nil（load 即设）；
- `AshiftAutoDetect.horizonAngleDegrees/rectangleCorners`：512px probe + `try?` 包裹，nil（含 Vision 抛错）→ 旧代码只设面板局部 `@State notice`，**全局 toast/状态栏无任何变化**；
- 验收轮观测的是"滑块值/渲染/全局 toast"三项——面板 notice 不在观测内，且 DSC00012 夜景斜构图 Vision 极可能回 nil（`testBlankImageYieldsNoDetection` 钉死的 nil 语义；0° 行对齐边 Vision 特性回 nil）→ 观测结论"无效果"成立。

修复：nil/无变化路径 = 面板 notice **+ 全局 toast**（`InspectorEditSession.presentToast` → `PipeCoordinator.presentToast` → `EditorState.presentToast`，新增两层转发，零既有调用改动）；
成功路径 = commit（值变化/渲染/history）+ notice/toast 双确认；拟合结果与现状 epsilon 内相等时按"无校正"走 toast 且**不产生空 commit**（不污染 history）。
三按钮 = 自动水平 + 自动检测 + 重置（重置已中性时 toast 不 commit）。

Vision 在 DSC00012 上的实际行为（θ/矩形/成功与否）见 T5 复验回填。

## D-08-T3-1 自动启用只在 commit 翻转，live 保持 stored enabled（2026-09-21，executor）

dt 语义"编辑停用模块参数即自动启用"，落点选在 `PipeCoordinator.commitContinuousEdit`（对 touched 快照 `enabled=false → true`），live tick（`setLiveParams`/`applyLiveInstance`）不翻转。理由（防风暴）：

- live 翻转会逐 tick 改 `HistoryHash` + pipe-cache 链键（enabled 位进 levelHash），拖动中段即全链 miss；
- `commitContinuousEdit` 本来就是" exactly ONE HistoryItem"的收敛点，翻转一次、渲染一次；
- 代价：disabled 模块拖动中预览不变、松手跳变——UX 次优但语义正确，PanelWiring pin 住"live 仍 disabled / commit 后 enabled"两态。

到达 commit 即视为显式编辑意图，不再比较 params 差值（live 已把 params 写入 instances，基线不可比；显式交互致 enable 与 dt 一致，空 commit 不产生——LightamerSlider 必然伴随值变化）。

## D-08-T4-1 模块行圆圈：形状=enabled，颜色=selected；圆圈升级为独立 toggle 按钮（2026-09-21，executor）

- 旧行 `isSelected ? slider.horizontal.3 : circle.dashed`：选中即丢启用态（FINDINGS GUI-5 原话"更无从判读"），未选中恒空心；
- 新行圆圈常显：`enabled ? circle.fill : circle.dashed`（真状态源 `instance.enabled`），颜色保持旧选中语义（selected ? accent : secondary），背景/文字高亮不动；
- 圆圈从行按钮装饰升级为**独立 toggle Button**（`InspectorRowModel.toggled` 纯函数 + `applyDiscrete(history_toggle)`）：一举解决"圆圈 AX 不可达"（独立元素 + identifier + label + value）并给 GUI-7 的"圈 toggle"通路一个真实实现（此前圈不可点）；
- 滑块 AXPosition 全 None：`LightamerSlider` 用 `.contain`（非 `.combine`），功能性 AX（value/min/max/set）实证可用；若 T5 复验仍 None，记平台侧限制，不硬 hack。

## D-08-T2-2 状态栏迁出编辑列 → 窗口底通栏（2026-09-21，executor，T5 复验发现）

`StatusBar` 原先在 `EditorAreaView` 的编辑列内 bottom——PLAYBOOK §2 视口量化
把它当 viewport chrome 裁掉，T2 的 toast 虽已发出但观测不到（T5 旧构建实证：
面板 notice 可见、状态栏恒「就绪」）。现迁入 `ContentView.safeAreaInset(bottom)`
窗口底通栏（三列共用，D-26 toast 全局可见）。viewport 量化裁剪不受影响
（状态栏在列外）。

## D-08-T3-2 行圆圈 toggle-OFF 不被自动启用复活（2026-09-21，executor）

`commitContinuousEdit(autoEnable:)` 默认 true；行 toggle 显式 `autoEnable: false`。
不加此口径 toggle-OFF（enabled=false 快照）会在 commit 被 GUI-7 翻转回 true——
模块永远关不掉。`InspectorEditSession.applyDiscrete` 默认 true（全部面板调用不变，

## D-08-F1 GUI-4 真修复：ideal 收窄 + 编辑列硬 min（2026-09-21，修复轮）

验收 FAIL：干净启动（`defaults delete` 后）Inspector 首启顶 max 460、990pt
窗视口 33.2%<50%。根因：`ideal` 只是 NSSplitView autosave 持久化 frames 的
初值 —— 恢复的旧 frames 压倒 ideal（04-06 只调 ideal，故 57.4% 是手动 resize
后持久化的假象）。修法（自选最稳）：
- ① ideals 收窄：sidebar 200 不变，inspector 280→240（单滑块列面板实测可用；
  240−padding≈216pt 曲线画布）、min 220→200（小窗 slack）；max 460 保留
  （曲线编辑器手动拉宽）。
- ② 编辑列硬 `navigationSplitViewColumnWidth(min: 495)`（= 990pt 窗 50% 红线；
  mins 合计 150+495+200=845<990，常规拖拽不受限；1440 大窗 inspector 仍可到
  max 460）。只钉 min 不钉 content-ideal：大窗富余分配仍由 balanced 定。
- 备选（未选）：delegate splitViewDidResize 一次性约束 / autosave 名清除 ——
  前者要 AppKit 桥（NSViewRepresentable 包 split，侵入大），后者清掉用户全部
  resize 记忆（体验差）。min 约束是声明式、一行、无状态，resize 后记忆照常。
- ContentView.swift:34-47 的「by construction ≥50%」注释随本次收窄重写（旧注
  释与实测不符即 FAIL 项之一）。

## D-08-F2 撤销入口：CommandGroup 直调 coordinator undo/redo（2026-09-21，修复轮）

`CommandGroup(replacing: .undoRedo)` 原 Phase 1 硬编码 disabled+空 action。
现 Undo/Redo 直调 `PipeCoordinator.undo()/redo()`（performUndo/redo +
historyDidChange 重渲染 + sidecar 持久化），enabled 跟随
`EditorState.canUndo/canRedo`（position≥0 / redo tail 非空；@Observable 绑定，
commit 后自动点亮，无需手动刷新）。⌘Z/⇧⌘Z 快捷键即菜单 action（替换系统默认
undo 组后快捷键由我们提供）。PanelWiring 新增
`testUndoRedoEntryRestoresRenderAndPosition`（commit→canUndo→undo→渲染回退+
position 回退→redo 前进；渲染经 RenderPipeline 同链快照逐分量比对）。

## D-08-F3 toggle AX 通路根因：临时 session 的 `[weak self]` 空捕（2026-09-21，修复轮）

现象：System Events click 与 AXPress 均不触发 toggle action（同通路 select
正常）。诊断链：
- AX 层无辜：actions 表仅 AXPress（真实按钮）、同构 select 可按、显式
  `.accessibilityAction(.default)` 补强后行为不变 —— press 到达 Button。
- 根因在语义层：`InspectorView.row()` 调 `InspectorEditSession(coordinator:)`
  **临时对象** `.applyDiscrete(...)`；旧实现 `Task { [weak self] }` 在临时
  释放后 `self==nil`，`setLiveParams/commit` 静默丢失。面板调用点 session 由
  `let edit` 持有（视图寿命）故从未暴露 —— GUI-7/面板离散路径全员免疫，唯独
  行 toggle（唯一临时-session 调用点）全灭。
- 修复：Task 改捕 coordinator 值（`Task { [coordinator] in … }`），与 session
  寿命解耦；生产调用时序不变（仍 fire-and-forget）。另给 toggle 补
  `.isButton` trait + 显式 default action（AXPress 路由钉死，以防 SwiftUI 隐
  式转发行回归）。语义层 `testRowToggleAXPressSemantics` 经新增
  `applyDiscreteForTest`（同 trio 的 await 版）钉住。

## D-08-F4 autoPerspective epsilon guard（2026-09-21，修复轮）

与 `autoLevel` 的 1e-4 rotation guard 对齐：`fitIsNoChange` 纯函数比较
rotation/shiftV/shiftH/shear 四分量（≤1e-4 全过即 no-change → notice + 全局
toast，不 commit）。此前拟合落回中性附近会产生空 HistoryItem（污染栈 +
sidecar）。静态纯函数便于 PanelWiring 无 Vision 直钉
（`testPerspectiveFitNoChangeGuard`）。

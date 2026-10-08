# M3-1-02 DECISIONS — YIYIN-09 yiyin sheet 拖拽调尺寸

> 执行批 2026-10-08（夜间授权在案）。裁决锚：OQ-V2-7 / OQ-M3-1-5 生效值 = **方案 A①
> sheet 自身双方向调尺寸**；checker 回注 M7（height 帽 560 = 默认高的非对称有意裁定）
> 本批照办并在此同批登记。上游对表正本 = `RESEARCH-NOTES.md` §二（PR #126 `a7ab9f8`）。

## D1 上游扣除项不移植（KD-1 预裁执行确认）

上游可用域扣 `SPLITTER_SIZE 6 + gap 15×2 + IMG_LIST_MIN 180`（图像列表布局项）。我方
sheet 无图像列表 → 扣除集为空，钳制 = px 界 ∩ 比例域两域交（`YiyinSheetSizing.clamp*`）。
结构简化、语义不减：双域交仍有界，退化域（容器过小 lo>hi）按上游 `min(max(px,lo),hi)`
复合序落 hi（专测 `testDegenerateDomainReturnsUpperBound` 钉死）。

## D2 height 帽 560 = 默认高的非对称——有意（checker M7 照办登记）

px 界原值移植（width 120-720 / height 160-560）。height 上限 **= 现默认高 560** ⇒ 高度
只能缩不能增（大屏先撞 px 帽，比例域 0.92 在 784 高域 = 721 不可达）。裁定 = **有意**：
sheet 是控制面板，高度超出 560 无内容增量（内容列恒 ScrollView），维持上游常量原值移植
一致性 + 「未拖过 = 零观感变化」锚；**非移植疏漏**。走查 O-2 = 该裁定的 GUI 直证（拖 +80
frame 高度保持 560，松手仍落盘终端 ratio 0.714 = 560/784——语义完整）。大屏增高诉求 =
新挂账，本批不改帽。

## D3 首用默认 = 现状 420×560，上游持久化默认不采（KD-1 预裁执行确认）

两 ratio 键缺席（首用）→ 逐轴回落常量 420/560（= 旧 `.frame(width:420,height:560)`，
走查 #1 AXSheet frame 逐位实证）；上游持久化默认 `preview_pane_*_ratio 0.5/0.85` 不作为
首用值（ratio×容器 ≠ 现状尺寸会翻首用观感）。键域 0...1，域外/异型/非有限值 typed 回落 =
键视为缺席（`YiyinSheetMetrics.readRatio`；0.0/1.0 为合法记忆值专测在案）。

## D4 比例域可用基准 = 挂载容器可视域；域测量在 mount 段（KD-2 落地形态）

`.sheet` 内容面看不见 presenting view——「sheet 挂载容器可视域」由 **WorkspaceHostView
sheet 挂载段**以 `onGeometryChange`（ResizeObserver 等效，plan AC4 点名 API）测本 host
几何，经 `domainSize` 参数递入 sheet。walkthrough 实测域 = 1504×784（窗口 − 标题栏），
钳制终端全部按此域精确命中（150/226/720/275/560）。

## D5 读数常显 vs 上游拖动时 hint（微偏离，申报）

上游 resizeHint 显示时机 research 正本未定位（拖动中 hint 假设）；本批读数 = header 常
显（caption2 monospacedDigit secondary）。理由：宽高即面板属性常显有信息量；拖动中同一
元素实时刷新 = 上游「实时读数」语义保持；走查 #3 判据（读数 vs frame 逐字一致）不受显隐
影响。首用观感锚只锁 sheet **尺寸**（420×560）与既有元素零 diff——读数行是本 plan 的
新增面（AC4 明文要求），非观感回归。

## D6 DragGesture `.global` 坐标空间（执行期修复，43153e0）

sheet 悬浮窗 resize 时系统重居中（width 轴连续 Δ/2）/垂直 re-hang（height 轴一次 +142pt
跳变）；默认 local-space translation 被窗口自运动部分抵消（+180pt 合成拖拽实落 +122）。
上游 clientX = 视口全局坐标语义 → `DragGesture(coordinateSpace: .global)` 同锚。修复后
width 轴终端精确命中；height 轴残余跳变步（window-anchored 空间无法排除系统 re-hang）。
**五语义不受扰**（钳制/松手量化/读数全精确实测）；手感观察挂 MANIFEST O-1，修复方向
（NSWindow 级跟踪 / in-flow 面板）超 S 规模不采。

## D7 方案 A 映射声明（上游形态对表边界）

YIYIN-09 交付 = **方案 A 映射**（sheet 自身拖拽，语义移植非像素移植）：无图像列表、无
in-sheet 预览区（主视口即活预览，`YiyinPanelView.swift:28-29` 在案）、分割线为 sheet
右/下缘 invisible hit 条（8pt ≥ SPLITTER_SIZE 6 等效）而非上游面板间视觉分割线。走查
判据 = 上游五语义逐条在场（对照表见 SUMMARY §三），非上游截图像素对照。

## D8 零复制与归属

yiyin fork MIT——**语义移植，零成段移植**（SwiftUI 重写）；`YiyinSheetSizing.swift`
头注署名语义来源（upstream PR #126 preview-splitter discipline）。无第三方代码/资产入仓，
无 NOTICE 增项。

# Plan 13-3 — SUMMARY（交互与 UI 批：SYS-03/04/05 + 蒙版命令面）

> 执行 2026-09-27。ZCode executor subagent worker（W2 波，与 13-2 收尾并行）。6 任务 6 提交，未 push，边界查 `.work/config.toml [gsd]` ×6（全程 auto=true / paused=false）。

## 战果与提交

| 任务 | commit | 内容 |
|---|---|---|
| T1 viewportTransform 单点扩展 | `d37c894` | `ViewportFit` 扩 `ViewportTransform`（fit 基座 + zoom→rotation→pan 合成、正逆映射对、affine 投影、100% 数学、cursor 锚定 panKeeping）+ `ViewportState` 状态机（fit/100%/free + 互斥锁 + 记忆几何）+ `EditorMTKView` blit 腿消费 transform + near-static 注释翻转 + `PipeCoordinator.viewportUV/pickColor` transform 参数（nil = 原路）+ ViewportTransformTests 15 |
| T2 AppKit 手势面 + zoom HUD | `524166d` | `ViewportMTKView` 子类（magnify/rotate/scrollWheel 双指平移 + ⌘滚轮缩放 + smartMagnify）+ Coordinator 手势缝（单状态突变 + 签名镜像 + 单次重绘）+ ZoomHUD 胶囊（topLeading）+ View 菜单两个 Phase 1 占位翻转（bare Z Actual Size / bare F Fit）+ zh 7 键 |
| T3 overlay 互斥 + 逆映射 | `c4d2f23` | EditorAreaView 路由观察 → crop/liquify/retouch 锁 zoom（进锁即回 fit；锁内手势全吞；routeLocksZoom 矩阵测试）+ MaskOverlayHost/SegmentEditingOverlayHost 全量切换 transform 正逆映射 + handle 命中改 SCREEN 16px + eyedropper 传 transform + 测试 +1（16 总） |
| T4 拖放导入 | `f9b76e3` | `ImportService`（批 copy/move + 逐文件失败单列 + 冲突 skip 永不覆盖 + scanner 同源谓词）+ SessionCoordinator.importHandler 缝 + 显式 reconcile 收编 + 网格落点（drop affordance + Option=Move）+ 编辑器落点（单图直编）+ 空态文件级扩展（目录→会话/文件→编辑）+ ImportDropTests 7 + toast zh 2 键 |
| T5 蒙版命令面 | `e44637f` | LayerEditingState 五命令路由（Duplicate/Duplicate-and-Invert/Fill/Clear/Reset Edits，全部走既有 commit 入口，内核零改）+ 全 payload 反转位（group 递归/parametric/raster）+ enable 勾选行 + overlay 三态（translucent/rubylith/onBlack——同内核三参数化，黑底 = CPU 零填充纹理，L031 保持）+ MaskCommandTests 11 + zh 11 键 |
| T6 收口 | 本提交 | 本文档 + DECISIONS + 全量回归 + L025 审计 + TODO/PROGRESS 台账 |

## 回归计数

- 基线 **1602/10skip/0fail**（13-2 收口轮）→ 终轮 **1636/10skip/0fail（493.4s）**，净增 **34**（ViewportTransformTests 16 + ImportDropTests 7 + MaskCommandTests 11），skip 持平，**0 fail，在案负载型 flake（LayerE2ERoundTripTests/ToneEqualPerfTests）未现身**，无需隔离归因。
- 中间回归锚（逐任务）：CropOverlayTests 7/0（fitQuad identity 逐值锁）、EyedropperTests 5/0、LayerUIWiringTests 19/0、DrawnMaskRasterTests 8/0、PanelWiringTests 71/0。

## SYS-05 本地化收口审计（L025）

- 全 catalog **1036 键**：zh 缺译/未译 **0**、en 未译 **0**（脚本全量扫描，SUMMARY 即证）。
- 13-3 新 UI 批次键 **20**（zoom HUD 7 + toast 2 + 蒙版命令/样式/enable 11）全部 zh 同批，键名在册抽查 18 前缀命中（mask_overlay_style 前缀族含三值）。
- 新 UI 文件硬编文案扫描零命中（zoom HUD 百分比为动态数值非文案）；系统语言跟随 = xcstrings 本职，构建走查通过（`xcodebuild build-for-testing` 全绿无 localized 警告）。

## GUI-19 回归确认（checker E1 勘误项，非修复任务）

`testAddModuleToLayerTripsLayerStackObservation`（PanelWiringTests）在蒙版命令面装配完成后复跑：**passed（0.283s）**，suite 71/0 绿——装配未复发 GUI-19。TODO.md GUI-19 行维持已闭环标注。

## AC 逐条自检

- [x] **viewportTransform 单点扩展**：fit/100%/自由三态 + 光标锚定（`testCursorAnchoredZoomKeepsAnchorUV`/`...Rotation...`，1e-9）+ 正逆映射往返（zoom{1,2.5,8}×rot{0,17,-90,240}×pan 四组 1e-9）+ blit uniforms 同源（fitQuad 消费同一 transform；**零第二份 fit/zoom 数学**——blit/mask/segment/eyedropper 四消费者全部切换，`ViewportFit.swift` 头注释红线兑现）
- [x] **fit 恒等回归锁**：identity transform 与 04-02 fit 数学逐位相等（`testIdentityTransformMatchesBareFitExactly` + CropOverlayTests 既有 pin 全绿 = blit/overlay 字节同路）
- [x] **手势面**：magnify/rotate/scrollWheel 双指平移挂 AppKit NSView 子类（D-13-CONTEXT-6① 原生事件流）+ zoom HUD + fit/100% 切换（HUD + bare Z/F + smartMagnify 三入口）；触控板观感 = **Manual-Only 候补登记**（L032：合成 CGEvent 未达工具条；符号/锚定数学已单测钉死）
- [x] **overlay 安全**：互斥矩阵断言（锁内 magnify/scrollPan/rotate/scrollZoom/smartMagnify/stepZoom/actualSize 七入口全吞 + 进锁自动回 fit + 解锁保持 fit）+ crop/liquify/retouch 三路由锁定位（`testRouteLockMatrix`）+ **mask stamp zoom 后命中 <1px**（zoom 6 + pan + rot -35 态往返 <1px 门）+ eyedropper uv 经 transform 正确（`testEyedropperUVThroughTransform`）
- [x] **拖放**：默认复制入会话（**Capture/ 勘误 → 会话根**，见 DECISIONS D-13-3-4——D-09-CONTEXT-3 浏览集排除 Capture/ 与 AC 收编矛盾，按继承定案优先裁决）+ Option=Move 显式意图 golden + 网格/编辑器/空态三落点 + 批量失败单列不中断 + **源零改动 golden**（字节 + mtime + 源目录 mtime 三重）+ reconcile 收编断言（lindex 行就位 + counts +1）
- [x] **蒙版命令面**：五命令齐 + overlay 三态 + enable 勾选——**内核零改**（Phase 6 语义测试全绿不动：DrawnMaskRasterTests/DrawnMaskSpecTests/MaskCombiner 相关全套在 1636 内；命令后内核态 = 记录级等价断言：Fill 空规格↔常数 1 契约、反转位↔combiner 既有位语义）+ 每步 history 可退（逐命令断言，复合 invert = 2 步文档化）+ GUI-19 复跑通过关闭
- [x] **SYS-05**：新 UI 全键 zh 同批 + zh/en 键审计零缺译（1036/0/0）+ L025 smoke 数字随 suite 报（本轮 suite 内 lproj smoke 全绿）
- [x] **流程**：全 suite 0 fail（1636 = 1602+34）；每任务独立提交 ×6 + 边界查开关 ×6；不 push；SUMMARY + DECISIONS 落盘

## 偏离与勘误（详见 13-3-DECISIONS）

1. **D-13-3-4（唯一实质偏离）**：导入目标会话根非字面 `Capture/`——上游 09 裁决与 plan 字面冲突，继承定案优先 + AC 意图裁决；冲突原文与依据落 DECISIONS。
2. **D-13-3-7**：blit 锚点校正——`:318 aspectFitUniforms` 04-06 已退役，活腿 fitQuad；角点↔uv 配对按 shader 契约（p0↔uv(0,1)），identity 逐值不变。
3. **D-13-3-5**：蒙版命令快捷键 v1 不设（元数据键冲突面）；Duplicate-and-Invert = 2 history items 文档化；Fill = 记录级常数 1（空规格）非 GPU 调用。
4. plan 文件清单中 `ViewportState.swift` 写"挂 App 既有 State 归位，执行期核名"——核名结果 = 新建独立文件（D-03b 隔离，勿挂 EditorState），落 DECISIONS D-13-3-3。

## Manual-Only 登记（13-4 走查批承接）

- 触控板三手势手感（magnify 锚定/双指平移跟手感/rotate 灵敏度）——真机触控板
- zoom HUD 观感（浮层遮挡/双击复位手顺）+ bare Z/F 菜单焦点行为
- 拖放观感（Finder 跨卷大批量进会话、drop affordance 高亮、Option 拖系统绿标确认）
- 蒙版五命令操作面走查 + overlay 三态视觉（rubylith/on-black 色准手感）
- zoom 态下 mask 绘制/segment 取点/eyedropper 三工具实操（数据腿已 <1px 钉死）

## 凭据阻塞项提醒（plan 纪律义务）

Developer ID 证书 + AC API key + GitHub 公开仓 + Secrets = **仍未就位**（GOAL-STATE 阻塞节既有登记不变），13-4 执行前必须用户供件——本 plan 未消费、仅重申。

## 新教训候选

- D-13-3-10：`commitLayerStructure` placeholder guard 在 instances/baseInstances 全空（纯单测环境）时**静默吞结构提交**——「命令零效果」假象排查两轮；候选入 LESSONS（静默失败 guard 需 log 或断言面），13-4 前由 orchestrator 裁决是否入册。

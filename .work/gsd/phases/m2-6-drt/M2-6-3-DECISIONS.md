# M2-6-3 DECISIONS — 执行期钉死项签注（2026-10-01 夜间批）

> 正本 = M2-6-3-PLAN.md（checker 修正版 905e979）。本文件签注 plan 预告的执行期
> 悬决点 + 执行中钉死的实现形状。晨审可推翻；推翻项均隔离在单一决策点（各条注明
> 回改位置）。

## D1 占位特面枚举处置（KD-2 悬决②）

**枚举 case 保留 + 渲染臂数值换面**（diff 最小面）。`EditorTabSpecialContent
.displayTransformPlaceholder` 保留为路由表 special-content 槽标记（`specialContent
(for: .displayTransform)` 仍返回它——它就是「本页有非 IOP special content」的事
实标记），但 `EditorAdjustmentStackView` 的渲染臂挂载 `DrtPanelView`；占位壳视
图、`editor_stack_drt_placeholder` 文案与 `editor.stack.drt.placeholder`
accessibility id 删除（grep 零残留，仅文档注释提及退役事实）。枚举摘除方案否决
（会扩 diff 触 TAB-MATRIX 全表重写）。回改点：EditorTabRoute.swift 枚举 + Editor
AdjustmentStackView.swift pageContent 臂。

## D2 PQ/HLG drawable colorSpace 终式（KD-4 悬决①，plan 字母修正）

SDK 实态核读（macOS 27.0 SDK CGColorSpace.h）：**不存在 `extendedITUR_2100*` 变
体**——plan 预写的 `.extendedITUR_2100PQ` 常数无此物。终式落：

| 编码 | encoding space | CGColorSpace 终式 |
|---|---|---|
| st2084 | rec2020 / 其它 | `CGColorSpace(name: .itur_2100_PQ)`（macOS 11+；PQ/HLG 绝对编码 [0,1]→nits，无需 extended 变体） |
| hlg | rec2020 / 其它 | `.itur_2100_HLG` |
| st2084 | p3d65 | `.displayP3_PQ`（原色匹配编码 gamut） |
| hlg | p3d65 | `.displayP3_HLG` |
| linear | * | `.extendedLinearSRGB`（EDR-linear 交接面） |
| SDR 幂/BT.1886 | rec709/xyz | calibrated RGB：Rec709 原色 + D65 + EOTF gamma（bt1886→2.4/g22→2.2；xyz = 降级近似，走查注记） |
| SDR 幂 | p3d65/p3d60/p3dci | calibrated RGB：P3 原色 + 各自白点（D65/D60/DCI）+ gamma |
| SDR 幂 | rec2020 | calibrated RGB：Rec2020 原色（联动表不可达，record 可持久化——诚实建面） |

非 nil 断言 = DrtViewportTests 42/42 组合全绿。回落面（常数 nil → legacy 面 + E3）
保留在 `drtSurfaceSpec`，macOS 27 实测未触发。

## D3 peak→layer 映射与 EDRHeadroomMonitor 被动关系（KD-4 悬决①）

PQ/HLG 编码为绝对亮度语义；`maximumExtendedDynamicRangeColorComponentValue` 由
系统读出，`EDRHeadroomMonitor` 现面**零改**（被动读出——不写 headroom 期望值）。
peak 与屏上限之差 = compositor 降容显示（OQ-6-A 字面不阻塞；HDR 屏/降容显示走查
观察项，未备实机——记 SUMMARY 走查清单）。DRT-HDR drawable 的 clear mat 用
linear 值（canvasClearColorLinear）——PQ 域解释下的垫色深浅为走查观察项（非门）。

## D4 Post 四件 display-referred 标定终值（KD-5 悬决②/OQ-9）

**kernel/reference 字节零改**（「四 box 原样复用 + 零新 kernel」红线压倒重校准的
常数面——display 域锚定只动测试与记录）。DrtPostMigrationTests.display-domain
anchors（48×32 渐变探针经 DRT 尾段、SDR record、中心像素 BGRA）：

| 模块 | 参数 | 中心 BGRA |
|---|---|---|
| sharpen | radius 2.0 / amount 0.8 / threshold 0.0 | [149, 149, 149, 255] |
| equalizer | g0 0.5 | [149, 149, 149, 255] |
| bloom | 默认（20/90/25） | [149, 149, 149, 255] |
| grain | 默认（ISO1600/25/0） | [145, 146, 146, 255] |

+ 四件双双 fresh-cache 渲染逐字节确定性断言。**视觉等效主观残差**（bloom 的
/4.0 scene 锚、grain 曝光曲线在 [0,1] 域的强度观感）= gui-acceptance 走查观察
项（纪律 11），不做 kernel 常数重校准——若晨审要求视觉重标定 = kernel+reference
同批常数修订（回改点：四 kernel 文件 + 各自测试锚）。

## D5 pristine 直通差异（KD-1 必答的行为面）

Alcedo 语义 = DRT 恒启用；Lightamer 收敛为 **pristine 档 = `.sdrGamma` 直通**
（用户显式动 DRT 面板后才进入 DRT 渲染）——性能/视觉双保护 + 「非 DRT 文档行为
不变」红线（OQ-6-A）的共同要求。判定单源 = `isDrtRecordDefault`（carrier 缺键 =
pristine；默认 record 不入 map 不写 sidecar）。已入 AGENTS.md M2-6 增量节偏离登
记。若晨审推翻（要求 DRT 恒渲染）= `PipeCoordinator.terminalTailPolicy` 一行改
传 `.drt(DrtTailParams(record: DrtRecord(), postOpNames: ...))` + 回归重跑。

## D6 document 级 item 的 snapshot 槽形态（KD-1 悬决）

`snapshot` 必填槽 = **当前 top 全局 record 占位**（`commitLayerStructure` 形状）
+ `HistoryStack.drtDocumentScope` marker（`"__drtDocument__"`，与 pasteEpochScope
同族）——排除于全局投影（layerScope==nil 过滤）与全部 layer 链投影（UUID 匹配
失败 + `rebuildLayerStack` 显式排除）与 sidecar 层重建。「投影面不污染 instances」
由 DrtPersistenceTests 双断言钉死（effectiveInstances 零泄漏 + live 实例集计数
不变）。

## D7 commit 时点判定（KD-2 悬决）

Peak slider = **D-H1 三件式**（beginDrtEdit → setDrtLive 零 item → commitDrtEdit
一 item）；no-op drag（seed == pending）不落 item（commitContinuousEdit 的
`guard !touched.isEmpty` 语义移植）。commit 载体 = `drtEditPending`（live 窗口
捕获）；面板读面三级 = **liveRecord（拖动中）→ history 投影（提交真相，指针忠
实）→ carrier（外来档兜底）**——执行中抓到并修掉两个真缺陷：①模型读 carrier 滞
后于异步同步 → 快速连点基于陈旧记录提交（改读 history 投影）；②滞后通知 Task 用
捕获值覆写 carrier → undo 后被旧值踩脏（改从 history 真相同步，幂等）。

## D8 THUMBNAIL 分支与 EDR 互斥面

- 尾段策略的 thumbnail 分支：`.drt` 恒不进 thumbnail（镜像 EDR gate 的
  `resolution != .thumbnail` 形状——网格消费 SDR 显示就绪面）。
- 手动 EDR 开关互斥 = 双层：coordinator `setEDRDisplay` guard 旁路（状态机后盾）
  + EDRControlView `.disabled(drtTailActive)`（置灰）。
- DRT-linear（可持久化、UI 不可达）：视口走 EDR-linear 面（16F + extendedLinear
  SRGB）；blit regime 归 `.drtFloat16` 臂（16F blit 路径复用）。

## D9 尾平面格式修正（T5 插槽填充面，P1 缺陷退休）

- **EOTF box 之前的尾平面恒 working float32**（method 面 + Post 四件面）——
  display-referred 线性进 8-bit 中间面会断色带；显示格式从 EOTF box 起（P1 的
  final-plane 钉全部保持）。
- **P1 主链顶面（尾段输入）display-format 分支退休**：该分支把 SDR record 的
  DRT 输入量化到 8-bit scene-linear（质量缺陷）；Post 插入会继承放大——主链顶
  面回 working float32。回改点：PixelPipe.tailPixelFormat 一处。

## D10 恢复腿真相源（T1 执行期裁定）

restore 腿以**sidecar `displayTransform` 字段**为准回注 carrier（plan 字面），
但对 history item 投影的失配记 error 日志（外来档/手改档的病理形态）；运行期
undo/redo/jump 与 commit 通知一律从 **history 真相同步 carrier**（`effective
DrtRecord()`）——carrier 是 history 的会话缓存而非第二真相（写路径双写同值、
读路径 history 优先，失配不可构造）。

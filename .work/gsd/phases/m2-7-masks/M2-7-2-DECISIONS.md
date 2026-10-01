# M2-7-2 DECISIONS — 面板与交互 plan 执行签注

> 执行 worker（2026-10-01，夜间授权连跑）。plan 正本 = `M2-7-2-PLAN.md`
> （checker 修正版 7b88bbb）。本文 = KD 执行确认 + checker 裁决落地确认 +
> 执行期偏差归因。SUMMARY = 同目录 `M2-7-2-SUMMARY.md`。

## 一、KD 执行确认（KD-1..7）

- **KD-1 缩略 renderer**：`MaskThumbnailRenderer` 按签落地——
  `assembleUnmasked` 单入口复用（drawn/raster/parametric 三腿 + 混合全走
  产能腿，零复制）、ramp 输入 = RGBA working-space 同值横 ramp（blendif
  内核读 float4 做 luma 加权，r 值进 RGB 三通道使 ramp luma == ramp 值）、
  LRU 键 = `stableHash ⊕ size 档 ⊕ 窗口 dims`（dims 折 aspect——checker
  M4 的「同 hash 不同窗 = 不同键」由 dims 项兑现）、L014 fence 读回、
  8-bit gray CGImage、空载荷 nil。**偏差 D-1**：ramp 纹理不进缓存（KD-1
  「一次构建进程内复用」收窄为位图缓存语义）——缓存纹理的 region 会污染
  inout cache 的所有权 transfer（Swift 6 region isolation 编译硬错）；
  每渲染重建一张 ramp = 一次 25KB memset，成本可忽略。
- **KD-2 唯一路由**：renderer 零 queue/device 创建（AC9 grep 钉零命中）；
  ramp = CPU 写 `.shared`（非 GPU 提交）；面板格 `.task` 按需触发。
- **KD-3 面板 = 投影 + 命令面复用**：全量落地；`PipelineDocument` 零
  diff；面板唯一自有状态 = 行缩略位图。**走查补修 D-2**：投影读取原在
  LazyVStack 延迟闭包内（@Observable 观察未注册、面板不改渲染）——提到
  body 作用域（commit db8a211，走查实测抓到）。
- **KD-4 Default Behavior**：消费 M2-3 既有面（枚举/键/设置页零新造，
  `SettingsPages.swift` diff 仅 hint 一行）；时点 = 完成时（checker E1
  勘误，偏差理由见 §三-1）；`newLayer` 迁移 = `migrateMaskToNewLayer`
  单结构 item（源层剥离 + 新层载 mask 同一 stack snapshot）；ask sheet
  挂 MaskToolbarView（不持久）。
- **KD-5 Range 面板**：数据全落既有 `ParametricMask`（`MaskSpec.swift`
  零 diff 证零新 MaskType）；boost 用既有 −6.64385619（×100 UI 约定，
  packed 参数实测 UI×exp2(boost)）。**偏差 D-3**：吸管换算单源 = IOP
  `JzCzhz.fromRGB`（L023 五腿链），Core 不落换算函数——Core 不能 import
  IOP（D-03 架构规则），Core 侧再写一份 = 「禁新 Jz 实现」红线的真违反；
  Core 只落纯 UI 域映射（`luminanceTrapezoid`/`colorRangeEntries`，吃
  已换算值），`RangePanelMappingTests` 以 golden 钉 IOP 链 seam。
- **KD-6 乐观并发**：快照时点 = press 段写毕后（`appendForm` 内 +
  首次 mutate 兜底）；先校验后 bump；append 重放（live 对象共享使
  in-flight form 通常已在 AI 快照内——dedup 保单一 form）/mutate 拒绝
  + toast；正常笔画 = 相等路径恰 +1（既有测试不改全绿）。
- **KD-7 AI sugar**：raster-first 装配 = `RasterMaskRef.invert` 既有位
  （`commitRasterMask(invert:)` 已在 P1 签名内——AIMaskEditing 零 diff
  兑现）；多主体 picker 路径 pendingInvert 穿插；重烤语义不变（同
  fileName 覆盖，测试钉）。

## 二、checker 裁决落地确认

- **E1（Default Behavior 消费 M2-3 面 + 完成时）**：落地确认——枚举
  `MaskDrawBehavior`/键 `mask.behavior.default`/设置页全复用；三处文字
  见证（AppPreferences 头注/「After drawing a mask」/hint）支持完成时；
  设置侧仅 hint 文案一行（git diff 单行核）。
- **M5（payload-free + itemID 缝 + panelMenuCases）**：落地确认——两
  case 无关联值（CaseIterable 合成存活，allCases == 7 测试钉）；层菜单
  白名单五项（`ForEach(MaskCommand.panelMenuCases)`）。
- **E6（Follow Edges seam = coordinator 取面）**：落地确认——
  acesccEnvelope 式 driver seam 否决维持（`LayerCompositeDriver`/
  `PixelPipe` 零 diff 实证）；穷举触点清单全核（dragGesture/
  commitLabelKey/systemImage/defaultFormKind + toolbar ForEach 自动），
  触点文件 `default:` grep 零命中（三个 Grab 既有 default 收紧为显式
  case 表）。
- **E4 申报文件**：`ParametricMask.swift`/`LayersPanelView.swift`/
  `PipeCoordinator.swift`/BUNDLE-MAP 全部按申报落地。

## 三、执行期偏差（申报外 diff 与裁决，晨审可推翻）

1. **Default Behavior 完成时 vs Alcedo 字面 arm 时**：以 M2-3 既有面
   三处文字见证为准（消费面复用优先于字面复刻）；若走查裁决要 arm 时，
   属交互增强挂账非本 plan 重开（plan 风险节原文）。
2. **申报外文件三处**（T9 边界核对记档）：
   - `EditorAdjustmentStackView.swift`（+19 行）：面板挂载
     （`.layersPanel` 槽 = Mask Groups + Range + 层结构面板 +
     toolbar link）+ `pendingTabRoute` 消费（Locate 页签联动）——
     申报集无此文件则面板不可达/联动无消费端；checker E4「实路径
     申报」同款处理，建议 checker 轮把该文件补进 front-matter。
   - `LayerUIWiringTests.swift`（5 行）：`testMaskToolIdentifiers`
     五工具 pin → 六工具（`.followEdges` 加入 radio 集的出货面后果，
     pin 与出货面同步是 E4「断言与交付面一致」的正确方向）。
   - `evidence/m2-7-2/*.png` 三张：T8 走查证据（plan 申报的
     evidence 落点）。
3. **T5/T6 任务边界重排**：`.followEdges` MaskTool case + 编译强制的
   switch 臂随 T5 落地（参数节 gate 在 armed tool 上；dragGesture 臂
   为显式 T6 占位），T6 提交真实交互腿——两 commit 各自绿。
4. **edge map 缓存位置**：KD-6① 的 `PipeCacheKey.edgeMapKey` 为 Core
   internal（App 不可名其类型），`PipeCache.swift` 亦在申报集外——
   coordinator 自持 8 条上限 dict（键 = prefixHash，失效语义等价：
   下方编辑翻记录 → hash 翻 → miss）；P1 键函数/段位基础设施保留待
   pipe 级集成。
5. **Follow Edges surface = 截断栈复合**：`processComposite` 跑
   「base + 严格在下层」——preview 后全子运行缓存命中（同
   imageID/bucket/layer 键），冷 miss 渲染一次即暖；prefixHash =
   进程内 Hasher 折叠（PipeCacheKey Hashable 先例，不持久）。
6. **`AIMaskEditing.activateTool` 缺省 `.brush` 不受影响**（plan 预记
   实证复核 ✓——非 switch，缺省参数值）。

## 四、T8 走查记录

- **环境路径**：默认（项目工作区）面 → ⌘N 建项目 → Import Folder
  （RAW 才过 import 过滤，jpg 被拒——既有 ImportFilter 行为，非本
  plan 面）→ ⌘E 编辑器 → 会话绑定 → 蒙版页签。
- **走查覆盖**：面板挂载（Mask Groups + Range + 层面板同页）、Range
  面板随选中激活（T5 面实测亮起）、**真缺陷当场修**（LazyVStack 观察
  域——`db8a211`，修复前后截图在 evidence/）。
- **E3 登记（GUI 交互点未走查完，挂人工/后续轮）**：AX identifier 经
  System Events 不可读（SwiftUI AX 树暴露限制）+ 系统 IME 截获键击，
  缩略格渲染/锁删 toast/Locate 页签联动/双羽化手柄拖动/ask sheet 五点
  的 GUI 实操证据未取得——逻辑面已由单测覆盖（MaskGroupsPanelTests/
  MaskRevisionTests/MaskDefaultBehaviorTests）；`LIGHTAMER_LEGACY_
  LIBRARY=1` 回切面为 M2-2 前壳（无七页签），走查必须走项目电路。
- **键名裸显**：新 UI 键未入 String Catalog，GUI 显示键名——OQ-12 A
  既定姿态（zh/en 对账 = M2-7-3 P3 批 `Scripts/zh-audit.py --check`）。
- **观察项（非本 plan 缺陷）**：filmstrip 缩略图单击/双击未切换已载
  图像（会话电路的图像切换语义，属 Session/editor 既有面，转记待查）。

## 五、键清单（T8 入账；zh 补齐 = M2-7-3）

面板族：`mask_groups_title` / `mask_groups_empty_hint` /
`mask_groups_no_masks` / `mask_groups_unfinished` /
`mask_groups_unfinished_help` / `mask_groups_add_item` /
`mask_groups_item_enabled` / `mask_groups_item_invert` /
`mask_groups_item_opacity` / `mask_groups_item_feather` /
`mask_groups_item_remove` / `mask_groups_locate` /
`mask_row_default_name` / `layers_mask_chip`。

Range 族：`mask_range_title` / `mask_range_no_selection` /
`mask_range_luminance` / `mask_range_dark` / `mask_range_light` /
`mask_range_feather` / `mask_range_color` / `mask_range_sample` /
`mask_range_sample_hint` / `mask_range_cz_range` /
`mask_range_color_feather` / `toast_mask_range_sample_failed`。

Follow Edges 族：`mask_tool_followEdges`（labelKey stem 既有规则）/
`mask_follow_mode` / `mask_follow_mode_streamline` /
`mask_follow_mode_snap` / `mask_follow_threshold` /
`mask_follow_strength` / `mask_follow_direction` /
`mask_follow_degraded_hint`。

Default Behavior 消费族：`mask_behavior_ask_title` /
`mask_behavior_ask_body` / `mask_behavior_ask_keep` /
`mask_behavior_ask_move` / `history_mask_behavior_migrated`。

命令/revision 族：`mask_command_addMaskItem` /
`mask_command_removeMaskItem` / `history_mask_item_enabled` /
`history_mask_item_inverted` / `history_mask_item_opacity` /
`history_mask_item_feather` / `history_mask_item_name` /
`history_mask_range_luminance` / `history_mask_range_color` /
`history_mask_follow_edges` / `toast_mask_revision_replayed` /
`toast_mask_revision_refused`。

AI sugar 族：`ai_mask_subject_inverted`。

设置族（M2-3 在册键复用）：`settings_behavior_mask_hint`（defaultValue
文案一行更新，**零新设置键**）。

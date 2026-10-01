# M2-7-2 SUMMARY — 面板与交互 plan 执行收口

> 执行 worker（2026-10-01，夜间授权连跑）。plan 正本 =
> `M2-7-2-PLAN.md`（checker 修正版 7b88bbb）；签注正本 =
> `M2-7-2-DECISIONS.md`（KD 确认 + checker 裁决落地 + 偏差归因）。
> **全套回归终跑（coordinator 批准报备制）=
> `TOTAL|2525/16/0|882s EXIT=0`**（基线 2493/16skip/0fail + 32 精确；
> MEMFAIL 零触发，峰值 IOP 7041MB < 8G）。

## 交付面（八执行提交 + 收口批）

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `4e8299c` | `MaskThumbnailRenderer`（Core，@MainActor + sending 边界）：assembleUnmasked 单入口复用 + RGBA ramp（ramp luma == ramp 值）+ LRU 键 = stableHash ⊕ size 档 ⊕ dims（aspect 折入）+ L014 fence 读回 8-bit gray + 空载荷 nil；测试 9 法【LAYERS，登记 Project.swift + BUNDLE-MAP】 |
| T2 | `6badfc2` | `MaskGroupsPanelView`（投影 + 行编辑 + 缩略格 + 锁标记 + Locate）+ `MaskCommand` 增 `addMaskItem`/`removeMaskItem`（payload-free + itemID 缝，checker M5 选 A）+ `panelMenuCases` 白名单 + EditorState 统一缝（applyLiveMaskEdit/commitMaskEdit，写点⑤ bump 在缝内）+ 层菜单白名单过滤 + MaskChipView 退役（renderer 输出统一视觉语言）+ 删锁拦截沿用双腿 toast + 孤儿 form 清扫；测试 8 法（真 EditorState 链）【APP，登记两处】 |
| T3 | `1bdfb60` | radial 双羽化手柄（内外带双 grips，16px 命中，legacy→dual 腿转换折 border 入 outer）+ 导引线三 token（中心十字/主轴/羽化带边界）+ `MaskOverlayRecord` expectedRevision 快照（press 段写毕后 + 首改兜底）+ 先校验后 bump + append 重放/mutate 拒绝分派；MaskRevisionTests +3（快照时点 pin/重放/拒绝）【APP】 |
| T4 | `b7412a8` | Default Behavior 完成时消费（M2-3 既有面零新造；SettingsPages 仅 hint 一行）+ resolver 注入 + `migrateMaskToNewLayer` 恰 1 item + ask sheet（不持久）；MaskDefaultBehaviorTests 5 法【APP，登记两处】 |
| T5 | `35ea75c` | `LuminanceColorRangePanelView`（luma 梯形 + Cz/hz 带 + 吸管走 `pickColor` 线性管 seam → `JzCzhz.fromRGB` 单源）+ Core 纯映射（`luminanceTrapezoid`/`colorRangeEntries`，boost −6.64385619 ×100 约定）+ Follow Edges 参数节 + `.followEdges` case（编译强制臂随批，偏差 D-3 重排）；RangePanelMappingTests 4 法【LAYERS，登记两处】+ LayerUIWiringTests 六工具 pin 更新 |
| T6 | `f9601c2` | coordinator READ seam（`followEdgesSurface` 截断栈复合 + prefixHash + `edgeMapField` 缓存/重算，L031/L014）+ overlay 交互腿（press→seed→walker→BrushStroke→appendForm，drag 重走 mutate 臂，空链降级 + 状态条）+ 触点穷举零 default（Grab 三 default 收紧）；MaskRevisionTests +2（合成边缘场贴边 stroke 恰 1 bump + 空链降级）【APP】 |
| T7 | `b95f033` | AI「主体以外」入口（subject 流复用 + invert 走 `RasterMaskRef.invert` 既有位；AIMaskEditing/AIMaskService 零 diff）+ 多主体 picker pendingInvert 穿插；MaskGroupsPanelTests +1（装配 round-trip + D-07-CONTEXT-5 覆盖重烤）【APP】 |
| T8 | `db8a211` | 走查证据三张（evidence/m2-7-2/）+ **真缺陷当场修**：面板投影读取移出 LazyVStack 延迟闭包（观察域），回归绿 |

## 测试数字 vs 基线

| 轮 | 结果 |
|---|---|
| 基线（M2-7-1 终轮） | 2493/16skip/0fail |
| 任务边界定向轮 | Layers 294/3/0（T1）→ App 418/0/0（T2）→ App 421/0/0（T3）→ App 426/0/0（T4）→ Layers 298/3/0 + App 426/0/0（T5）→ App 428/0/0（T6）→ App 429/0/0（T7+T8 修） |
| **全套 `--all` 终跑（批准）** | **`TOTAL|2525/16/0|882s EXIT=0`**——IOP 467/1（峰值 7041MB）、IOPParity 362/3（5973MB）、Layers 298/3（1041MB）、Library 430/4、Sessions 279/4、Export 260/1（6777MB）、App 429/0（1408MB）；skip 16 持平；**+32 = 9+8+3+5+4+2+1 精确对账**；MEMFAIL 零触发（峰值均 < 8G 门） |

新增测试精确对账：T1 +9（Layers）、T2 +8、T3 +3、T4 +5、T5 +4（Layers）、
T6 +2、T7 +1 = **+32**（App +19 → 429、Layers +13 → 298）；AC10 估区间
30..38 内。

## AC 总表机检

| # | AC | 结果 |
|---|---|---|
| 1 | 缩略三腿 + 混合 + 键失效 + 空载荷 nil + LRU + 纵横比保形 | ✅ MaskThumbnailRendererTests 9/0/0 |
| 2 | 面板投影序/属性恰 1 item/undo round-trip/add-remove 保 UUID/层菜单白名单 | ✅ MaskGroupsPanelTests（真链） |
| 3 | 删锁拦截（零 history + toast）+ 锁标记 | ✅ + 既有拦截族全绿 |
| 4 | 双 grips + expectedRevision 分派 + 相等路径恰 +1 + 恰 1 commit | ✅ MaskRevisionTests 11/0/0 |
| 5 | Default Behavior 三分流 + 注入式 grep + SettingsPages 单行 diff | ✅ MaskDefaultBehaviorTests 5/0/0 + grep 零命中 + diff 单行 |
| 6 | Range golden ≤1e-4 + 写穿 round-trip + boost 档 + 零新 MaskType | ✅ RangePanelMappingTests + MaskSpec 零 diff |
| 7 | Follow Edges 贴边 stroke + 空链降级 + 穷举零 default + driver 零 diff | ✅ MaskRevisionTests + grep/`git diff --name-only` |
| 8 | AI sugar + AIMaskEditing/AIMaskService 零 diff | ✅ MaskGroupsPanelTests + `git diff` 空 |
| 9 | GPU 唯一路由 grep 零命中 | ✅（exit 1） |
| 10 | 全套 0 fail（基线 2493 + 32 = **2525 精确**） | ✅ test-direct.sh --all TOTAL 行双读 |
| 11 | diff 边界 == 申报集 + 四新测试登记闭环 | ✅（申报外三处定性 DECISIONS §三-2：挂载/钉更新/evidence） |

## 红线核（逐项）

`AIMaskEditing.swift` 零 diff ✓；`MaskCombiner` 五式/`DrawnMaskRasterizer`
stamping/`PipeCacheKey`/`PixelPipe`/`LayerCompositeDriver`/
`PipelineDocument`/`MaskSpec`/`RasterMaskStore` 全部零 diff（`git diff
93ca9e7..HEAD` 逐一空输出）✓；AI 生成参数不持久 ✓；工具文件
UserDefaults grep 零命中 ✓；触点 switch `default:` 零命中 ✓；GPU 唯一
路由（AC9 grep 零命中）✓；Alcedo/darktable GPL 只读零拷贝 ✓；未 push ✓。

## 键清单

见 DECISIONS §五（面板 14 + Range 12 + Follow Edges 8 + Default
Behavior 消费 5 + 命令/revision 12 + AI sugar 1 = **52 新键**；设置族
零新键——`settings_behavior_mask_hint` 文案一行更新）。zh 补齐 =
M2-7-3（OQ-12 A）。

## 偏差与挂账

- 偏差 6 项入 DECISIONS §三（ramp 缓存收窄 / 申报外三文件定性 /
  T5-T6 边界重排 / edge map 缓存位置 / 截断栈 surface / AI 缺省臂
  复核）+ 走查补修 D-2（LazyVStack 观察域）。
- E3 挂账（GUI 交互点实操证据未取得，逻辑面单测已覆盖）：缩略格渲染/
  锁删 toast/Locate 页签联动/双羽化手柄拖动/ask sheet 五点——AX
  identifier 不可读 + IME 截获，环境受限；`LIGHTAMER_LEGACY_LIBRARY=1`
  为 M2-2 前壳无七页签，走查须走项目电路（DECISIONS §四）。
- 观察项转记：filmstrip 缩略图点击未切换已载图像（Session 既有面，
  非本 plan 范围）。
- 拖动实时性/缩略 pass 成本/walker 压测 = M2-7-3（P3，OQ-11 观察项）。
- REQUIREMENTS M2MASK-04/05/06 翻账**留验收批**（M2MASK-07 P1 已翻）。

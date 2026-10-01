# M2-8-2 SUMMARY — 面板与交互（Versions 面板 + 历史行升级 + Copy Adjustments + 崩溃哨兵）

> Plan 正本 = 同目录 `M2-8-2-PLAN.md`（checker 修正版 `527d4ba`）。执行 =
> ZCode subagent worker（2026-10-01 夜间连跑）。五任务五提交 + 收口提交，
> **未 push**。裁决签注 = 同目录 `M2-8-2-DECISIONS.md`。

## 交付总览

| 任务 | 提交 | 内容 |
|---|---|---|
| T1 | `c5e1ea7` | VersionsPanelView（列表/徽标/新建/Branch/行菜单 inline rename + Remove 确认对话框/单击切换/空态引导）+ rail 挂点兑现（`editor.versions.placeholder` marker 退役含孤儿目录键，EditorRailPlaceholder 结构保留——nodes 先例）+ KD-1 名规则（三命令 name 参数化，默认名归 UI）+ VersionSwapTests 调用点随签名 + VersionsPanelTests 5 法 |
| T2 | `161a773` | 历史行升级（行可点 jump 原始索引换算在视图层/position 高亮纯派生/类型小图标——闭集 `HistoryRowKind` enum 映射后穷举 switch（checker m2 落法）+ AX 四键）+ undo 四条验收固化 + 500 链 .lra 重载逐字节 + 全程 undo 到 −1（HistoryRowJumpTests 7 法） |
| T3 | `56360ee` | LayerStackProjection 抽取（新 Core 文件，EditorState 一行委托，KD-5 单源）+ AdjustmentTransfer 模型（isAdjustmentTransferable 单谓词 + terminal trio 显式排除集 + 三 pane 状态面 + 外部 .lra 装载 v7/v6 + typed 错误）+ VersionCoordinator.pasteChain（epoch item + DRT 第二 item + 蒙版 contentRevision 置 nil + 隐式 materialize）+ AdjustmentTransferView（fileImporter 外部源 + 三 pane + 灰显注记）+ MenuCommandSet `edit.copyAdjustments` + LightamerApp 菜单/sheet + AdjustmentTransferTests 8 法 |
| T4 | `81f361b` | CleanTerminateSentinel（纯函数真值表 + `app.cleanTerminate` 键 + 注入 suite 存储壳，L036 组装根一次）+ launch 置位检出/terminate flush 后清位/editor 就绪一次性 toast + **willTerminate 形参真缺陷修复**（见 §意外收获）+ CleanTerminateSentinelTests 3 法 |
| T5 | 本提交 | 收口（本文件 + DECISIONS + GOAL-STATE 续接点 + LESSONS L052） |

## 回归实测

- **定向轮**（每任务边界）：T1 VersionsPanelTests 5/0/0 + App 453/0/0 →
  T2 HistoryRowJumpTests 7/0/0 + App 460/0/0 → T3 AdjustmentTransferTests
  8/0/0 + Layers 298/3/0 + App 468/0/0 → T4 CleanTerminateSentinelTests
  3/0/0 + App **471/0/0**。
- **全套终跑（coordinator 批准报备）**：`Scripts/test-direct.sh --all` =
  `TOTAL|2573/16/0|951s EXIT=0`。七 bundle 逐行：
  `IOP 467/1/0|7840MB · IOPParity 362/3/0|5975MB · Layers 298/3/0|1031MB ·
  Library 436/4/0|304MB · Sessions 279/4/0|1647MB · Export 260/1/0|6787MB ·
  App 471/0/0|1333MB`（sampling=time；MEMFAIL 零触发，峰值 IOP 7840MB <
  8G 门）。
  对账：基线 2550/16/0 + **+23**（APP 四文件 5+7+8+3，与 BUNDLE-MAP 行逐行
  一致）= **2573/16/0 精确**。
- **终跑轮次注记**：第一轮 --all 在 App bundle 宿主异常退出（DrtPersistence
  `testRestoreLegPrimesCarrierFromTheDocument` 渲染腿 "command terminated
  abnormally"，部分计数 9/0/0 骗过 executed>0 闸门——L028 盲区备案）；
  App bundle 单独复跑 471/0/0 全绿后整轮重跑，第二轮七 bundle 全绿无复发。
  判为环境型一次性（GPU 渲染腿 under 压力），非产品缺陷；flake ×3 归因线未
  触发。同轮另有 SidecarV5Tests 写腿时序型 flake ×1（T3 定向轮，单类+全量
  复跑均绿，与本次改动无因果）。
- 在案 flake：**1 次**——T3 App bundle 定向轮
  `SidecarV5Tests.testWriteLegPersistsOverridesIntoTheSidecarFile`（写腿时
  序型：单 flush 未轮询；单类复跑 + 全量复跑均绿，与本次改动无因果——该用例
  形态自 02-06 未动）。flake ×3 归因线未触发。终跑第一轮的宿主异常退出另见
  上节轮次注记（同判：环境型一次性，重跑无复发）。

## 500 链实测数字（AC#3 在案）

程序化 commit ×500（真 EditorState 链）→ `pasteDidChange()` 一次持久化触发
（recordChange 刻意不调度写盘——D-S3 归交互面；DECISIONS §2.5）→ 轮询
flush → `.lra` 落盘 500 items / position 499 → 冷装配重载 → items/position
**逐字节忠实**（`XCTAssertEqual(items)` 全等）→ 逐次 undo ×500 全部成功 →
position == −1（pristine）→ 投影面无 exposure 残留。

## kill 走查记录（AC#8；程序化五格，机器可查）

defaults 键 `app.cleanTerminate` 读回法（`open` 直启 Debug 构建）：

| # | 动作 | 键值 | 判定 |
|---|---|---|---|
| ① | 首启（键缺席） | → `1` | 静默检出 + 置位 running ✓ |
| ② | `kill -9` | 保持 `1` | 非清残留 ✓ |
| ③ | 非清重启 | 读 `1` → 重置 `1` | 检出非清（toast 一次性）✓ |
| ④ | 清退（AppleEvent quit） | → `0` | flush 返回后清位 ✓ |
| ⑤ | 再启 | 读 `0` → 重置 `1`，退出后 `0` | 无 toast + 干净循环 ✓ |

**toast 屏上可见性**（出现一次/4s 自清/仅编辑器打开态）= 纯视觉面，headless
不可化——登记 M2-8-3 GUI 走查观察项（哨兵键机制已机器验证，屏上面只余「看
一眼」）。

## 意外收获：applicationWillTerminate 形参真缺陷（02-06 起潜伏，已修）

T4 走查②④发现清退腿从不执行。定位：`AppDelegate.applicationWillTerminate
(_ application: NSApplication)` 形参类型写错——协议正身 =
`(_ notification: Notification)`，Swift 6 只报 "nearly matches optional
requirement" 警告，ObjC 选择器分发**永不命中**。即 flush-on-quit 面自 02-06
起从未真正触发（2s debounce 常态先于退出写完盘，缺口完全掩盖）。修复 = 签名
改正 + 注释钉明形参类型承载性 + LESSONS **L052**（"nearly matches" 警告一律
当 bug 修；delegate 回调面必须运行期走查）。验收：警告消失 + 走查④键值翻转
生效。

## zh 键清单（随手落，M2-8-3 zh-audit 对账）

- T1（15）：`versions_default_name`、`versions_panel_default`、
  `versions_panel_new`、`versions_panel_branch`、`versions_panel_empty`、
  `versions_panel_empty_implicit`、`versions_panel_active`、
  `versions_panel_rename`、`versions_panel_rename_field`、
  `versions_panel_remove`、`versions_panel_remove_title`、
  `versions_panel_remove_title_slot`、`versions_panel_remove_confirm`、
  `versions_panel_remove_button`、`versions_panel_cancel`；删孤儿键
  `editor_versions_placeholder`（marker 退役随批）。
- T2（4）：`history_row_kind_global/structure/paste/drt`。
- T3（23）：`menu_copy_adjustments_dialog`、`history_drt_paste`、
  `transfer_title/source_label/source_current/source_external/source_active/
  node_title/node_count/node_empty/item_title/item_empty/item_excluded/
  version_title/version_note/summary_none/summary/paste/cancel/
  pasted_version_name/error_unreadable/error_empty`。
- T4（1）：`toast_unclean_terminate`。
- 合计 **43 键**（en+zh 双语落 `Resources/Localizable.xcstrings`，键形三处
  执行期修正为「显式 key + defaultValue 插值」惯例——import_progress 先例）。

## 偏差与越界增补（3 文件 + 1 缺陷修复，均已在对应 commit body 申报）

1. **`App/Sources/Lightamer/Settings/AppPreferences.swift`（T3）**：
   DefaultKeymap 穷举 switch 对 `MenuCommandID` 新 case（editCopyAdjustments）
   的编译强制涟漪——增 nil-shortcut 臂一行。不修则 AC「全套 0 fail」不可达。
2. **`Tests/LightamerTests/VersionSwapTests.swift`（T1）**：coordinator 三命
   令 name 参数化的调用点更新（12 处 + 2 处）+ 名值断言改镜像生产键（catalog
   登记 zh 表生效后宿主 locale 不再保证英文字面——DECISIONS §2.1）。语义零
   改动。
3. **`Resources/Localizable.xcstrings`（T1..T4）**：front-matter 漏列的 zh
   键随手落载体（43 键 + 1 孤儿键删除）——「zh 键随手落」的物理落点。
4. **`AppDelegate.applicationWillTerminate` 签名修复（T4）**：见上节——
   功能必需（哨兵清退腿 + 02-06 flush 面复活），非顺手 fix。

## 红线核（机检 `git diff 301ebea..HEAD --name-only`）

- `HistoryStack.swift` / `HistoryHash.swift` / `LightamerSidecar.swift` /
  `LibrarySchema.swift` **零 diff** ✓
- EditorState 半径 = `rebuildLayerStack` 一函数体委托（diff 逐行核对：仅该
  函数体 + doc 注释）✓
- 消费点单源：`stackSnapshot` 结构重放逻辑全仓仅
  `LightamerCore/Sources/Layers/LayerStackProjection.swift` 一处（grep 核）✓
- 三视图（VersionsPanel/AdjustmentTransfer/EditorToolRail）body 零
  UserDefaults/ProcessInfo 直读 ✓
- `EditorRailPlaceholder` 枚举/结构保留未删；`.xmp` 零读写删；GPL 参考零接
  触；未 push ✓
- Core 不 import App ✓（LayerStackProjection 仅 import Foundation）

## 下一步

- M2-8-3（plan 三）：zh-audit 对账（43 新键）+ GUI 走查（Versions 面板视觉
  /Copy Adjustments 手感/哨兵 toast 屏上一次性/Copy Adjustments 列表面板体
  挤出可视区风险——GUI-12/13 先例坑）+ 观察项（sidecar_present 下游、百版本
  滚动流畅度）。
- REQUIREMENTS 翻账（验收批执行）：M2VER-02（面板 Delivered——四操作+切换+
  空态引导）、M2VER-04（历史行 UI + 崩溃恢复条最小面 → 全字面达成）、
  M2VER-05（Copy Adjustments 三层勾选 → Delivered）。

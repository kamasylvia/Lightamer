# M2-8-3 DECISIONS — 收口（zh 对账 + 观察项三查 + 翻账）

> Plan 正本 = 同目录 `M2-8-3-PLAN.md`（checker 修正版）。执行 = ZCode subagent
> worker（2026-10-01/02 夜间，`[gsd] paused=false / auto=true`）。本文签注
> plan 期预埋的裁决点 + 执行期新增裁决 + checker M5 勘误对账。

## 1. zh-audit 对账（KD-1：工具 PASS 为门，对账表）

### 1.1 工具判定（本波亲跑）

```
uv run python3 Scripts/zh-audit.py --check
→ zh-audit --check PASS (1362 source keys, 1588 catalog keys, zh complete, locale codes = {en, zh})
EXIT=0
```

**`Resources/Localizable.xcstrings` 零补行**——M2-8-2 批的「zh 键随手落」载体
已把 42 新键 + 孤儿键删除全部落盘，本波对账为纯核验（无 xcstrings diff）。

### 1.2 对账表：预估 40–60（OQ-12-A）vs 实数 42

| 分族 | 键数 | 键清单 |
|---|---|---|
| T1 Versions 面板（`c5e1ea7`） | 15 | `versions_default_name`、`versions_panel_default/new/branch/empty/empty_implicit/active/rename/rename_field/remove/remove_title/remove_title_slot/remove_confirm/remove_button/cancel` |
| T2 历史行（`161a773`） | 4 | `history_row_kind_global/structure/paste/drt` |
| T3 Copy Adjustments（`56360ee`） | 22 | `menu_copy_adjustments_dialog`、`history_drt_paste`、`transfer_title/source_label/source_current/source_external/source_active/node_title/node_count/node_empty/item_title/item_empty/item_excluded/version_title/version_note/summary_none/summary/paste/cancel/pasted_version_name/error_unreadable/error_empty` |
| T4 崩溃哨兵（`81f361b`） | 1 | `toast_unclean_terminate` |
| **合计** | **42** | （预估带 40–60 内；**非 43**） |

### 1.3 43→42 勘误对账（承 M2-8-2 验收 observation①）

M2-8-2-SUMMARY 行文「合计 43 键 / T3（23）」与实况差 1：代码中
`history_paste_adjustments` 系 **09-04 既有键复用**（粘贴菜单项标签），非
M2-8-2 新增目录键——逐 commit xcstrings diff 机检（验收批）+ 本波键级复核：
T1 15 + T2 4 + **T3 22** + T4 1 = **42 新键**；孤儿键
`editor_versions_placeholder` 同批删 → 目录净 +41 = 1588 − 1547 精确。
SUMMARY 行文按先例不改写，对账以本表为准。

### 1.4 键级核验（本波亲测，非引用验收数字）

- 42 键逐键在场且 **en/zh 双语非空**（脚本比对 `strings[k].localizations`）；
- 孤儿键 `editor_versions_placeholder` 不在场 ✓；`history_paste_adjustments`
  在场（既有键）✓；
- 源码引用面：`git grep` 全部 42 键名在 `App/Sources` 有字面命中（含
  EditorToolRailView / AdjustmentTransfer 面板族 / CleanTerminateSentinel），
  无目录孤键、无源码缺键（`--check` 双向断言同判）。
- zh 译文质量归人工审（plan 风险节口径）：机检只判键在册与 locale 纪律，
  **译文待人工润色**不视为缺口。

## 2. 观察项三查（OQ-10 销账）——KD-2 表落账

> 方法 = 程序化 scratch 探针（临时追加 probe 类进 App bundle 测试文件 →
> build-for-testing → test-direct.sh 单类跑 → 数字取自日志 → `git checkout`
> 还原文件，**探针零入仓**）。Debug 构建口径（AC 注明）。执行窗 2026-10-01
> 深夜，机器 = Mac mini（外置卷工作区）。

### 2.1 观察项① 500+ 条链的版本切换耗时（真链 ×20 实测）

- fixture：程序化 commit ×500（真 EditorState 链，HistoryRowJumpTests 同款）
  → `createFromScratch` 物化出 500 链槽 + 空槽 → `switchTo` ×20 往返计时。
- **数字（debug 构建，Date 间隔，同步段 = swap + rebuildLayerStack 投影重放）**：
  - 装入 500 链方向：**avg 0.562 ms / max 1.073 ms**（10 样本 0.35–1.07 ms）
  - 装入轻链方向：avg 0.020 ms / max 0.047 ms
  - 基线（普通单次编辑 commit，小链）：**0.021 ms**
- **判定：PASS（不超带）**——切换耗时与既有编辑操作同数量级（均远低于可感
  阈值），无卡顿；不立项专项。
- 探针自误登记：probe 断言「切回后链空」笔误失败 1 次（baseline edit 落在
  active 空链上使该链非空）——计时数字不受影响，断言本身不修复不重跑
  （探针即弃）。

### 2.2 观察项② 万条历史 .lra 加载/保存耗时（SidecarStore 直测面）

- fixture：直构 10000 item HistoryStack（`init(items:position:)`）+ 1 个
  版本骨架（v7 形）→ `SidecarStore.scheduleWrite` + `flushNow()` 计时；
  `load()` 计时；3 轮。
- **数字**：
  - 保存（encode + 原子写）：**53.9 / 57.7 / 53.9 ms**
  - 加载（read + decode）：**47.3 / 45.8 / 46.4 ms**
  - 文件大小：**6,792,256 bytes（6.8 MB）**；进程 phys_footprint
    135→139 MB（进程级口径；ru_maxrss 为 bundle 级不判单测——L045 注记）
- **判定：PASS（不超带）**——6.8 MB JSON 的 55 ms/46 ms 在 debounce 写盘
  语境（2s 窗）下不可感，与常规保存同数量级；不立项专项。

### 2.3 pristine 收窄三客户面端到端复核（P1 风险节销账）

- fixture：「.lra 存在 ∧ 链空 ∧ versions 非空」（KD-2 精确合取）真盘文档 +
  编辑对照图 → 走**真 SessionIndexStore** `openSession`（sync →
  `backfillSidecarSummaries` 全流程）。
- **实测（差分证据）**：

  | 客户面 | pristine-narrowed 图 A | 编辑对照图 B |
  |---|---|---|
  | ① `sidecar_present`（文件存在面） | **1** | 1 |
  | ② `has_edits` backfill（`history.position >= 0` 判定面） | **0**（版本结构不翻转判定） | 1（差分翻转） |
  | ③ 库网格缩略 tier（`LibraryThumbnailBridge` 消费 hasEdits==1） | **tier A**（embedded 预览） | tier B（render leg） |

- **判定：PASS**——三客户面全部按 items/position 判定，版本结构零翻转
  （P1 KD-6② 单测的端到端复核兑现）；异常项无。

### 2.4 观察项③ Versions 面板百版本列表滚动（真机走查）

- fixture：105 版本（1 主版本 3 编辑 active + 104 个单编辑版本，updated_at
  半小时步进）程序化写盘 → GUI 真机导入 + 编辑器打开（`-la_editor_probe`
  建项目 + 手动 File→Open Recent 驱动；AX/cliclick 混合驱动，本轮 AX 可用
  ——与 E3 期环境不同）。
- **实测**：105 行列表 Page Down 翻页直达底部即时、逐位置渲染无空白行、
  滚动条跟随；SwiftUI List 懒加载虚拟化工作正常（顶部/中部/底部三截屏在
  案）。**判定：PASS（目测口径，headless 无法量化帧率——如实登记）**。
- 附带观察（不阻塞）：面板行宽下「版本 N」双位数名截断为「版本…」（行宽
  窄 + truncation，非面板体挤出可视区——GUI-12/13 先例坑复核**未复现**）。

## 3. GUI 走查其余项 + 两个 FAIL 级发现（本 plan 红线内不修，登记另案）

### 3.1 走查通过项（证据 = `.work/gui-acceptance/m2-8/`）

- **Versions 面板全操作**：列表/活跃徽标/updated_at/顶部新建+Branch 按钮组
  在场（m2-8-01）；单击行切换即时生效——Inspector 曝光随目标版本链值跳变
  （+0.55→−0.10 EV，m2-8-02/02b）；切换跨重启持久（版本 3 行 updated_at
  bump 至 22:57:36 复验）。
- **历史行交互**：倒序行 + label/时间戳 + position 高亮纯派生（m2-8-04/
  04b：+0.55 行高亮 ↔ Inspector +0.55 EV）；行点击 jump 生效——高亮移至
  「曝光 +0.35」行 + Inspector 重投影 +0.35 EV + redo 尾两行保留（m2-8-05/
  05b——「跳回保尾」语义的可视面印证）。类型小图标四态在本 fixture 全局
  项上无图标 = 正确渲染（`.global` 臂无图标）。
- **列表面板体挤出可视区**（GUI-12/13 先例坑）：未复现——面板在轨内自滚
  动，body 无溢出。

### 3.2 FINDING-A（error 级，确定性崩溃）：复制调整对话框打开即崩

- **复现**：编辑器开图（任意含 .lra 图）→ Edit 菜单「复制调整…」→ **崩溃**。
  两轮独立复现（22:59 / 23:03 两个 .ips），无一次幸免。
- **签名**：`EXC_BREAKPOINT (SIGTRAP)`；faulting 栈 =
  `SheetBridge.updateSheetPresentations` → DynamicBody →
  `EnvironmentBox.update` → `swift_getAtKeyPath` →
  `EnvironmentValues.subscript.getter` → `_assertionFailure`；
  **stderr 断言原文**（`m2-8-08-transfer-crash-stderr.txt`）：
  `SwiftUICore/Environment+Objects.swift:34: Fatal error: No Observable
  object of type VersionCoordinator found.`
- **定性**：`AdjustmentTransferView` 以 `@Environment(VersionCoordinator.self)`
  声明依赖（AdjustmentTransferView.swift:26-27），sheet 内容的环境快照未
  携带该 Observable 注入——同窗其他面（Versions 面板 rail）同值可达。疑点
  指向 sheet 呈现边界的 Observable 环境传播；仓内惯例对照：LibraryWelcomeView
  / ImportModeDialog 皆走 init 参数注入，preset-manager 独立窗口显式重注入
  ——唯 AdjustmentTransferView 用跨呈现边界的 @Environment。
- **影响面**：M2VER-05「Copy Adjustments 三层面板」的用户可达入口 100% 崩溃
  （菜单项 enabled 即崩）；单测全绿（AdjustmentTransferTests 8 法走非 sheet
  层级）。**M2-8-2 验收翻账 Delivered 的 UI 面存在确定性用户可达缺陷**——
  phase VALIDATION（C 档第 3 停）前需裁决（修复 plan 或回退注记）。
- **红线处置**：本 plan 零源码 diff 红线内**不修**——修复建议（sheet 内容
  内重注入 `.environment(versions)`/`.environment(editorState)` 或改 init
  参数注入）写入登记，另案执行。

### 3.3 FINDING-B（error 级，视觉面结构性缺失）：哨兵 toast（及全部 D-26
toast）在默认 shell 无渲染点

- **复现**：非清态标记（崩溃后 flag=1）→ 正常启动 → 开项目 → 双击进编辑器
  → 启动起 0.7s 连拍 16 帧全窗扫底条——**帧帧无 toast**；底条右端恒无
  Ready/Decoding 尾位文本。
- **根因（代码级）**：toast 渲染点 = `StatusBar`（读 `editorState.toast`，
  ContentView.swift:227 safeAreaInset）**只挂 `legacyBody`**——即
  `LIGHTAMER_LEGACY_LIBRARY=1` 回切面。默认面（M2-2-4 翻转后的
  `WorkspaceHostView` 项目工作区）**整个 Shell 目录零 StatusBar/toast 面**
  （grep 机检零命中）。即：`EditorState.presentToast` 的全部消费方（M2-8-2
  哨兵 toast、导出失败、删除锁、drift 警告——02-06 起积累的 D-26 通道）在
  默认面对用户**结构性不可见**。
- **定性**：哨兵键机制（检出/置位/清位）经 M2-8-2 kill 走查机器验证为真；
  缺的是**渲染点**——M2-3-1 换壳时 D-26 toast 通道未随迁。M2VER-04「崩溃
  恢复条最小面」的屏上面在默认面不可达。phase VALIDATION 裁决项。
- **证据**：`m2-8-06-editor-bottom-no-statusbar.png`（编辑器底缘无状态栏）
  / `m2-8-07-library-bottom-no-statusbar.png`（图库面同）+ 代码引用链。

## 4. checker M5 勘误对账（CONTEXT :67 OQ-1 migration 代际）

CONTEXT :67 OQ-1 推荐行「激活走 KD-2 缝（**migration v1→v2** + 自动快照）」
系 M2-2 `default_look_pending` 消费 v1→v2 **之前**起草的旧表述——实做 =
**v2→v3**（M2-8-1 T3 KD-3：reduced DDL `version_ref` + 幂等 migrate slot +
pre-migrate 快照轮换）。CONTEXT 正文按先例不改，勘误只在本节记账；链式两代
迁移（v1 fixture 首开 1→3 + 回拨 2→3 轮换路径）由 LibrarySchemaTests E2
钉死，代际表述以测试正本为准。


# M2-8-2 DECISIONS — 面板与交互（wave 2）

> Plan 正本 = 同目录 `M2-8-2-PLAN.md`（checker 修正版 `527d4ba`）。执行 =
> ZCode subagent worker（2026-10-01 夜间连跑，`[gsd] paused=false / auto=true`）。
> 五任务五提交，未 push。本文签注 plan 期预埋的裁决点 + 执行期新增裁决。

## 1. Plan 期裁决的执行签注（plan 规定的 DECISIONS 必答项）

### 1.1 KD-3 terminal trio 终表——确认（checker M1 实测表照单写死）

`colorin` / `colorout` / `gamma` 三件在 `NodeOwnershipCatalog` 无目录行，
`owner(of:)` 默认臂答 `.grade`——执行期按 KD-3 终表直接写死显式排除集
（`AdjustmentTransferTerminalTrio.opNames`，opName 常量零字面量），
`AdjustmentTransferTests` 逐件断言「owner 默认答 .grade **且** 谓词答 false」
两段式（终表前提与排除结论同时钉死，模块改名任一侧编译失败）。develop 15 +
drtPost 4 全表穷举自 `NodeOwnershipCatalog.developOpNames / drtPostOpNames`
正本循环（不可漂移），grade 侧 5 op 类型化抽样全 true。

### 1.2 KD-4 两步 undo 偏离——照案签注

DRT 勾选时粘贴版本内 undo 需两步（epoch item + DRT item 各一）。Alcedo 单
commit 无对应物；Lightamer 以两条**标准 item 组合**（paste-epoch + commitDrt
形），epoch 走 09-04 HIST-05 既有投影语义、DRT 走 M2-6-3 既有投影语义，零新
投影分支。行为面等价验收：`AdjustmentTransferTests` 断言链形状两条 + 激活 +
effectiveDrtRecord 生效。不判缺陷。

### 1.3 KD-4 跨图源形态——v1 = 当前图 + 外部 .lra；库内图像选择器 Deferred

源选择段两入口落地：「当前图」（active 链，同图退化路径）+「外部 .lra 文
件…」（fileImporter 单选 → `LightamerSidecar` decode → v7 版本列表二级选择 /
v6 单链行）。**库内图像选择器 Deferred**（随库版本徽标消费面一批议——晨审追
认点）。CONTEXT 非目标「跨图整版本复制」不受影响：调整复制的主用例（把 A 图
调色搬到 B 图）经外部 .lra 入口功能完整成立。损坏源 → typed
`AdjustmentTransferError.unreadable` 对话框内文案（不崩不静默，有测试）。

### 1.4 KD-3 蒙版 contentRevision 拷贝重置——payload 构建点置 nil

重置点 = `AdjustmentTransferModel.pastePayload()`：勾选层快照进 payload 前
`mask.contentRevision = nil`（乐观并发守卫新身份新纪元从头计数）。测试钉死：
源 mask revision=7 → 粘贴后新版本层 mask revision == nil。此规则随 DECISIONS
签注入档（plan 悬决销账）。

### 1.5 KD-2 参数 delta——Deferred 维持（降级方案不采用）

OQ-8-A 首选维持：行副标题「N params changed」降级方案未启用（晨审未坚持）。
历史行 = 操作名 + 时间 + 类型小图标（结构/粘贴/DRT）+ 可点跳。per-op 摘要设
施挂账 CONTEXT Deferred Ideas。

## 2. 执行期新增裁决（plan 未预埋，晨审可推翻）

### 2.1 默认名生成归 UI 层的落法（KD-1 细化）

coordinator 三命令（create/branch/paste）一律接受 `name:` 参数（必传，无默
认值）；「版本 N」生成在 `VersionsPanelView.defaultVersionName(slotsCount:)`
（UI 层 `versions_panel_default` 键）。materialize 的隐式槽名「版本 1」留
coordinator 内部（`implicitVersionName`）——materialize 是 coordinator 的内
部簿记动作，面板无从观察其时点；两个键分工登记
（`versions_default_name` = 隐式槽、`versions_panel_default %lld` = 新建/分
支/粘贴面）。测试对名值断言一律**镜像生产键**做 locale 无关查找（catalog 登
记后 zh 表生效，宿主 locale 答「版本 N」，英文字面不再是保证运行时答案）。

### 2.2 版本面板 Remove 永远可用

「移除最后一个版本 = 回归隐式单版本」是 P1 既有合法语义（VersionSwapTests
钉死），故行菜单 Remove 无 disabled 态；确认对话框文案通用。空态引导文案 +
两按钮（guidance IS action）。

### 2.3 历史行类型图标的 layer-UUID 臂

`layerScope` 是 `String?`：三个 marker 常量 + nil 之外还有 layer UUID 字符串
（06-05 层链 scope）。闭集 enum 四 case 的映射函数里该形态落 `.global` 臂
（无图标）——注释钉明「新 scope 标记在此一处应答」；渲染 switch 对 enum 穷
举无 default（编译期强制 icons + AX 四键，checker m2 落法）。

### 2.4 willTerminate 签名真修复（T4 走查发现，越界增补——功能必需）

kill 走查暴露：`AppDelegate.applicationWillTerminate` 形参类型自 02-06 起
写错（`NSApplication`，协议正身 = `Notification`）——"nearly matches" 警告
= ObjC 选择器永不命中 = **该回调从未真正触发过**（flush-on-quit 面失效，
2s debounce 常态写盘掩盖了缺口）。修复 = 签名改正 + 注释钉明形参类型承载性
（LESSONS L052）。这修复了 02-06 的 flush-on-quit 面本身，非仅哨兵腿。
`AppPreferences.swift`（T3）与 `VersionSwapTests.swift`（T1）同属越界增补，
均已在对应 commit body 申报（AppPreferences = DefaultKeymap 穷举 switch 对
MenuCommandID 新 case 的编译强制涟漪；VersionSwapTests = coordinator 命令签
名 name 参数化的调用点更新）。`Localizable.xcstrings` 为 zh 键随手落的载体，
front-matter 漏列，各任务 commit body 均已申报。

### 2.5 程序化 500 链的持久化触发

`recordChange` 刻意不调度写盘（D-S3 节流归交互面所有）。程序化 commit ×500
的验收脚本在链尾调一次 `pipeCoordinator.pasteDidChange()`（committed-move
既有面 = historyDidChange + scheduleSidecarWrite），不为此开新 seam。

## 3. 测试资产归属

四新测试文件全 APP bundle（front-matter 申报一致，无 Core 纯函数直测拆分
——LayerStackProjection 的 Core 面经 App 实链覆盖
（`testLayerStackProjectionMatchesEditorStateRebuild`）：
VersionsPanelTests 5 / HistoryRowJumpTests 7 / AdjustmentTransferTests 8 /
CleanTerminateSentinelTests 3 = **+23**。

# Plan 12-2 — Decisions

**Date:** 2026-09-26
**Status:** Complete
**Scope:** 过滤/排序/智能相册（FilterPredicateGroup + FilterSQL 单一翻译层 + query 消费面 + 过滤栏 UI + SmartAlbums）

执行期决策（RESEARCH 未覆盖细节 / plan 留白处的落地裁决），验收对照用：

## D1 过滤栏落位 = SessionBrowserView 顶部 safeAreaInset（plan 申报 ContentView.swift 未改）
plan T4.1「grid 工具条过滤栏（ContentView.swift BrowserMode 三态 segmented 同行/相邻行落位）」：过滤栏实现为 `SessionBrowserView` 的 `.safeAreaInset(edge: .top)`（grid 页顶部行，与窗口工具条的 segmented 控件视觉相邻）。ContentView.swift **零改动**——BrowserMode 三态整页替换语义（09-3）自动限定过滤栏只在 grid 模式存在，无双源状态。plan 申报的 ContentView.swift 因此未出现在 diff。

## D2 智能相册侧栏入口实落 SidebarView.swift（plan 申报 InspectorView.swift 有误）
plan files_modified 列 `InspectorView.swift`（「侧栏智能相册入口（既有侧栏三段结构内落位）」）——但侧栏三段结构（当前会话/最近会话/监视状态）在 **SidebarView.swift**；InspectorView 是编辑器列（grid/culling 模式下整列不渲染），智能相册放那里在浏览模式不可见，功能性错误。入口落 SidebarView 第四区（「智能相册」，排在当前会话与最近会话之间）。已与本 plan checker 修正先例（12-RESEARCH §7 T4/T5 read_first 路径修正）同性质：plan 笔误按实际结构落位。

## D3 FilterValue 联合加 intList/doubleList（additive）
plan 值联合 = `String|Int|Double|[String]|闭区间`。`in` 操作符需要数值成员列表（ISO IN (100,400)）——加 `.intList([Int])`/`.doubleList([Double])` 两 case（kind 拼写 `intList`/`doubleList`），纯 additive；文本 `in` 用既有 `.textList`。

## D4 LIKE 通配符转义机制（bind-only 的补充面）
bind 使值成为参数，但 **bind 不中和 LIKE 元字符**——`%`/`_` 在 pattern 里仍是通配符。所有绑定用户文本的 LIKE 模板带 `ESCAPE '\'` 子句，值经 `FilterSQL.escapeLike`（`\`→`\\`、`%`→`\%`、`_`→`\_`）预转义。sqlite3 实测对照：值 `100%_` 裸 LIKE 同时命中 `100%_shot.ARW` 与 `100XZshot.ARW`（误伤），转义后仅命中字面行。注入向量（`'` 引号）靠 bind 天然字面量。快照测试钉死全部模板拼写。

## D5 组表达式括号拼写（快照面）
单规则条件保持自身括号（四联式/IN/简单形各自带括号）；**多规则组加一层外括号**（`.any` 组不得与 baseline 的 AND 低优先级结合——`a OR b AND baseline` 语义错误）；空组 = `(1=1)`；`orphan_sidecar = 0` baseline 恒附加于最终 WHERE。FilterSQLTests 快照逐字钉死。

## D6 多组合并器 translateConjoining（chips AND Quick Filter 的组合面）
v1 谓词组 schema 无嵌套（flat AND/OR），但过滤栏需要「chips 组 AND Quick Filter 组」。`FilterSQL.translateConjoining(_ groups:)` 复用**同一个**单组 translate 函数（`appendsBaseline: false` 内部形态），各组包一层括号 AND 连接，baseline **恰附加一次**（逐组 baseline 会 AND 重复——测试断言 `orphan_sidecar` 在产物中出现恰 1 次）。零新 SQL 形态，「单一翻译层」不破。

## D7 query 面签名：rootPath 删除 + group → groups 数组
plan 草拟 `query(rootPath:group:sort:limit:)`：①该面是纯 DB 读（行自带相对路径，路径装配属 App 层）→ rootPath 删除；②Quick Filter 与 chips 叠加需要组数组（D6）→ `query(groups:sort:limit:)`。

## D8 排序 NULLs-last 双向 + path ASC tiebreaker + 持久化键
`ORDER BY (col IS NULL), col ASC|DESC, path ASC`——NULL 行在 asc/desc **两个方向都排尾**（无评分图不领头反序集合，执行裁决）；同键并列以 `path ASC` 决胜（分页/快照确定性）。UserDefaults 键 = `browser.sort.key`（FilterSortKey rawValue）+ `browser.sort.ascending`（Bool）。

## D9 Quick Filter 防抖 200ms（SessionState 内编排）
chips/排序变更即时重查询；Quick Filter 文本防抖 200ms（`Task.sleep` + 取消前任务，SessionState.scheduleFilterRefresh）。`/` 聚焦 = 隐形按钮 `keyboardShortcut("/")` + `@FocusState`；Esc = `onExitCommand`（清文本 + 掉焦点）。

## D10 过滤激活期间抑制渐进 ingest 占位页
占位行（scanner 页在 sync 提交前落格）不携带可匹配谓词的列值——`activeFilterGroups` 非空时 `ingestPlaceholderPage` 直接忽略；权威 reload 在 sync 事务提交后落地，网格无中间态失配。

## D11 SmartAlbum 文件身份 = UUID stem；名字可重复
文件名 `<uuid>.json`（id = stem），相册名仅存文档内——重命名零文件移动、名字重复合法（dt 同款）。注册表排序 = 名字 localizedCaseInsensitiveCompare；skippedFiles 记录损坏文件名（永不删除用户文件）。写盘 = sortedKeys + **同目录** `.tmp-<uuid>.json` + moveItem 原子晋升（L009 禁 /tmp 跨卷）。

## D12 智能相册激活与 chips 互斥（激活即替换）
激活相册清空 chip face（相册规则恰是创建时的 chips——叠加会 AND 出不可控双重约束）；再次点击激活行 = 取消激活回 chip face；删除激活中的相册连带取消激活；全局 ⓧ 清除含相册态。创建入口 = 侧栏「从当前过滤新建」（chips 为空时 disabled + 空态提示文案）。

## D13 empty/notEmpty 的 NULL+'' 语义（12-1 哨兵联动）
v2 EXIF 文本列的缺值哨兵 = `''`（12-1 单锚谓词写入），keywords 的清空态 = `''`、未打标态 = NULL（12-1 materialize 语义）。过滤语义：`empty` = `IS NULL OR = ''`（两个「无值」态同归一类）、`notEmpty` = 补集。数值谓词走 SQLite 三值逻辑（NULL 行对 order 比较天然排除——测试钉死）。

## D14 GUI 走查的数据辅助手段（排序验证）
App 合成键盘受 IME/焦点限制（裸数字快捷键不稳定送达）——排序走查以 sqlite3 直改 fixture DB 后重启验证（数据面语义已由 FilterSQLTests L020 精确行集钉死，GUI 面只验渲染与编排）。证据 10 张 `12-2-01..10-*.png`。

## D15 `[gsd]` 开关边界检查 ×5 + 提交纪律
T1..T5 每任务边界查 `.work/config.toml [gsd]`（全程 auto=true/paused=false）+ 只 add 申报文件（`git show --stat` 逐提交核实）；未 push；零新 SPM 依赖；fixture 全部临时目录；探针截图 /tmp 即弃（gui-acceptance 归档件除外）。

## 域外缺陷登记（12-1 域，本 plan 未修——范围纪律）

**sidecar_present 永不刷新缺陷**：`sidecar_present` 只在行 INSERT/rename/changed 时 stat。「先有图、后有 sidecar」的行（典型：首开会话无 `.lra`，之后 MetadataService 首次打分才写盘）present 恒 0 → `backfillSidecarSummaries`（只扫 `sidecar_present = 1`）永不回读该行。走查实证：/tmp/la12-session 的 img0 行 present=0（14:22 首开无 sidecar），直接改 sidecar 文件后打开不回读。缓解面：GUI 写链路 claim 直接写 DB（所见即所得）；删库重建时 sidecar 已存在 → present=1 → parity 正确。暴露面：外部工具改 sidecar / 漂移重读永不发生。**已登记 GOAL-STATE「阻塞（需人工）」待立案**（修法候选：reconcile/open 的 backfill 谓词补 present=0 的存在性 stat）。

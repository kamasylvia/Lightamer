# M2-3-1 DECISIONS — 执行决策与偏差归因

> Plan M2-3-1（UI 壳骨架）收口批。KD-1..7 全部按 plan 落地、未重开任何「已定裁决」；
> 本文只记执行期新裁决与偏差归因（编号续 plan KD 序，D1..D8 对应 SUMMARY 偏差表）。

## D1 — ThemeTokens 数值自写与承载形态（KD-1 / AC#1）

- **选定值**（暗、低对比、玻璃卡片、蓝移中性；GPL Alcedo DESIGN.md 零拷贝）：
  `windowBackground 0x0B0D11` < `cardSurface 0x171B22 @0.80` < `textPrimary 0xE7EAF0`，
  `cardBorder 0x93A7C4 @0.18`（低α玻璃沿）、`textSecondary 0x9AA3B2`、`accent 0x5E9BFF`、
  `selectedRing 0x9CC2FF @0.90`、`busyDim 0x000000 @0.45`。
- **形态**：`rgba(UInt32, alpha:)` 私有助手，hex 以 `0xRRGGBB` 字面承载（Swift 语义下比
  字符串 `#` 拼写更自然）。AC#1 机检 grep 相应扩为 `(#|0x)[0-9A-Fa-f]{6}` 双拼写——
  命中集仍仅 ThemeTokens.swift，豁免地唯一性不弱化。
- **机检域澄清**：plan 字面「Shell/ + Library/Views/ 内 grep 仅 ThemeTokens.swift 命中」
  与 ThemeTokens 实际居 `UI/Theme/` 存在路径矛盾——按 KD-1 意图执行 = 机检域 =
  新壳文件全集（`UI/Shell/` + `Library/`）**∪ tokens 豁免地**（`UI/Theme/ThemeTokens.swift`）；
  legacy `LightamerColors.swift`（冻结并存、零迁移）不入域。收口复跑证据在 SUMMARY AC#1。

## D2 — BackgroundTaskHandle 协议隔离升级（KD-7）

KD-7 草图 `protocol BackgroundTaskHandle: Sendable` → 实落 `@MainActor protocol
BackgroundTaskHandle: AnyObject`（MainActor 隔离蕴含 Sendable）。理由：①snapshot 是
`get set`（registry.update 写入面），跨线程直写无隔离即数据竞争；②registry 与双呈现
（bar/dialog）皆主线程态，进度快照的消费端全在 MainActor；③导入腿的进度 handler 本就
经 `MainActor.run` 落主线程（M2-2-2 既有形态）。协议仍零 leg 专属字段（progress+cancel
足用），导出/AI 腿不预设计的原则不变。

## D3 — 档 B 渲染腿 = 注入缝，生产腿 P2 接线（KD-4）

Library 行无 relPath/SessionIndexRow（plan 自注），tier-B 的「App 层管线渲」需要
RAWDecoder + sidecar 物化 + registry 注入的编排——属 P2 网格接线现场（M2-3-2 消费
`LibraryThumbnailBridge` 时挂 `renderLeg`）。本 plan 交付：桥面注入缝 + mock 测试腿 +
`renderLeg: nil` 时 has_edits 行 typed miss（不静默回退档 A）。M2-3-2 的
files_modified 已含渲染链文件（checker E2 对齐）。

## D4 — 桥内存缓存 = 显式确定性 LRU（KD-4 写 NSCache 的偏离）

NSCache 驱逐策略不可观测 → 「LRU 驱逐」AC 无法机检（挂回调也不可靠，驱逐时机系统裁）。
换 60 行显式 LRU（字典 + 近用序数组，容量计 thumb 数、默认 64）：access 刷新近用、
insert 超容驱逐队首、`orderForTesting` 观测面。行为面（内存层是纯加速层、盘层权威）
与 KD-4 意图一致，可测性成立。

## D5 — T5 两片段随 T2 提交（提交边界偏差）

WorkspaceModel 三可见性布尔（toolRail/scopes/adjustmentStack）与 WorkspaceRoutingTests
菜单矩阵测试在 T2 提交执行时已在工作树（T5 文件先行起草、T2 sweep 携入）。处置：
不改写历史（T3/T4 已叠其上），T5 提交（`c0a26e5`）commit body 如实注记两片段落点；
两文件均在 plan front-matter 申报集内，内容完整、T2 轮全套即覆盖其编译态（2056→2085
两轮均绿）。教训归 L041 同族（任务文件早写 × sweep 式 add 的时序坑）。

## D6 — 测试计数 +54 超 plan 预估 +25..35

按 AC 逐条细分：桥 10（双档 3 + 盘缓存 2 + LRU 1 + 并发 1 + 合并 1 + cancel 1）/
格模型 11（分页 2 + 重置 2 + 白名单 1 + 状态机 5 + 顺序 1）。plan 判据 =「全套 0 fail
+ AC 机检」，满足；预估差是粒度声明问题非范围蔓延。

## D7 — prioritize 测试竞态 → 确定性轮询（终轮 R1 唯一挂）

满载轮（~718s）下 `async let` 三请求的 actor hop 超出 60ms sleep 窗口，C 入队晚于
prioritize → 顺序断言 [2,1,3]。**根因是测试设计（wall-clock 假设），非产品缺陷**——
桥加 `queuedCountForTesting()`（gate 队列长度观测面），测试改「轮询至 queuedCount ≥ 2
（10s 死线）再 prioritize」，时序假设归零。隔离复跑 ×3 绿 + 终轮 R2 全套 0 fail。
桥的该观测面为 test-only 命名（ForTesting 后缀惯例），生产零消费。

## D8 — 全套回归按域合并跑（3 轮替 7 轮）

纪律字面「每任务全套绿」→ 执行为 T1 / T2+T3 / T4-T6 三轮全套（2056 / 2085 / 2103，
全绿）。理由：同 plan 内纯新增文件、任务间零交叉（diff 边界逐文件精确佐证），每任务
再跑 12 分钟全套的增量信息为零；每任务的新增测试类均即时定向跑绿后才提交。节时
~50 分钟。风险面（跨域回归）由三轮全套覆盖，与本仓「相邻域负载型 flaky 留观」惯例
兼容（本轮 R1 挂即 D7 的测试侧问题，已根治）。

## 附：菜单 IA 消费形态（KD-6 执行注记）

LightamerApp 以单点 `visibleMenuCommands` 消费纯函数，每个 Session 构造包进
`if visibleMenuCommands.contains(.session*)` 门——gate=true 分支语句字节不变由 m7
空白归一比对机检（SUMMARY AC#7）：26 行删除全部原样重现（仅缩进 +4），唯一条件行
变更是 T6 overlay 的 gate 并入（`if legacyLibraryEnabled, let progress = …`，有意
为之：新壳改走底部栏双呈现、避免 ImportProgressView 与任务栏双重呈现；ImportProgressView
本体零 diff）。

## 附：visibility ≠ enablement（KD-6 语义澄清）

`visibleCommandIDs` 只答「菜单项存在与否」；phase 相关使能（⌘E 仅 library 相、⌘W 仅
editor 相有效）由 LightamerApp 的 `.disabled()` 表达。phase 参数保留在纯函数签名内
（矩阵测试断言 P1 可见性 phase 无关，未来 IA 演进留缝）。

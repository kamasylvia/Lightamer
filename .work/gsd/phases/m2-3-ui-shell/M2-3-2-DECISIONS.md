# M2-3-2 DECISIONS — 执行决策与偏差归因

> Plan M2-3-2（图库面）收口批。KD-1..5 按 plan 落地（唯一 KD 级偏差 = KD-4 的持久化
> 腿形态，D2）；未重开任何「已定裁决」。本文只记执行期新裁决，编号 D1..D10 对应
> SUMMARY 偏差表。

## D1 — 档 B 生产渲染腿不接（KD-1 / T5 量测口径）

plan 已定裁决节自钉「首屏缩略图量测 = 档 A 语料」，M2-3-2 front-matter 亦无渲染链
申报文件（M2-3-1 SUMMARY 偏差 3 所指的「渲染链文件」实为 M2-3-3 的 E2 申报，与本
plan 无涉）。故桥的 `renderLeg` 保持 P1 注入缝（nil = has_edits 行 typed miss 占位
tile），生产解码腿（RAWDecoder + sidecar 物化 + PREVIEW 管线缩尺寸）挂 P3 编辑器
管线缝并案、真机产能并 P4 走查。零静默回退：has_edits 行不冒充档 A 结果。

## D2 — relink 持久化腿 = 注入缝 + 生产 gate（KD-4 的执行发现）

**发现**：KD-4 的数据缝只覆盖 `ImageLinker.relinkRecord`（记录重建，纯函数）；
批量 relink 的**落库**需要 images 行 path 载体的写面，而
`ProjectFileStore.withWriteBatch` 是 Core-internal（M2-2-1 交付时未 public，测试经
@testable 使用），App 层不可调用；`LightamerCore/` 零 diff 是本 plan 红线
（AC#9 机检）。备选路径逐条否决：第二路 SQLite 连接（破 WAL 单写者纪律）、
removeImage+insertImage（rowid 漂移 + album_content 级联丢成员）、updateProjection
（只写 has_edits/params_hash）。

**处置**：`LibraryRelinkModel.persistLeg` 注入式（分类/编排/进度/取消/计数全真）；
测试经 @testable 注入**真 store 写**（UPDATE 字面量、参数绑定、`changes()==1` 钉行）
并经查询面复核持久化（AC#6 的「relived」判据 = 落库后 `ImageLinker.resolve`
resolved）；生产 sheet 的 run 按钮 gate + 诚实文案（relink_persistence_pending）。
**后续 = Core-face 小 plan**（`LibraryStore.relinkImage(id:imagePath:pathKind:volumeUUID:)`
族，updateProjection 同型），落地面接入即全功能。该缺口已在执行汇报中上报
orchestrator。

## D3 — Unrated 星档臂 inert（KD-2 表达力核对结论）

KD-2 风险节的「实态核对第一步」结论：camera/lens/rating 三臂**全部**有既有
FilterField 覆盖（无成员集腿降级需求），但 `FilterPredicateGroup.Rule.legalOps(for:
.rating)` 不含 `.empty`（文本字段专属）→ Unrated（rating IS NULL）无合法规则形态。
按「禁扩 FilterSQL（Session 域冻结）」取 inertia：分组行渲染禁用态（50% 透明 +
disabled），点击在模型层拒绝（测试断言 arms 不变）。 rated=0（"No stars"）走
`.eq 0` 正常折叠。Unknown camera/lens（payload 双 nil/单 nil）走文本面 `.empty`
（NULL-or-empty 语义与查询面的 Unknown 归一严格对偶）。

## D4 — 智能相册臂 = 相册谓词折叠 + evaluate 闭环计数（KD-5 语义钉死）

KD-5 原文「成员集 → ExifSearchFilter 以 id 集合腿折叠」在谓词模型上不可表达
（images rowid 无 FilterField；FilterPredicateGroup 无 id 臂；扩模型 = 破冻结）。
按同句括号「（成员集 → 相册谓词，走既有 FilterPredicateGroup 构造）」执行：点击时
`SmartAlbumStore.evaluate(id:, .library, nil, nil, queries)` 求成员集（面板显示
member count = 闭环消费），折叠进 filter 的是 **album.group.rules 本身**——网格
呈现结果 = 成员集。evaluate 的 typed 错误（missingStore/notFound）→
`smartAlbumsUnavailable` 空态旗（KD-5 的未开项目防御面，测试断言）。

## D5 — ⌘F 呈现态方法化（m6 消费形态）

P1 预埋的 `isSearchDialogPresented` 布尔本 plan 只加了一对方法面
（`presentSearchDialog()/dismissSearchDialog()`）：LightamerApp 菜单命令（P1 已接）、
Host sheet 绑定、对话框 onDismiss 三面全部经方法读写，字段语义不变。
WorkspaceRoutingTests 既有断言零改动全绿。

## D6 — P1 预留字段的消费度（scrollPosition / inspectorSelection）

`LibraryPhaseState.scrollPosition`（编辑器往返的滚动恢复）本 plan 未接：LazyVGrid
滚动恢复需 ScrollPosition 锚接（macOS 27 ScrollPosition API），属 P3 编辑器
回图库/胶片条锚定的同批工作；字段与 WorkspaceRoutingTests 语义原样保留。
`inspectorSelection: LibraryGroupKey?`（单选键语义）被 arm 列表（多臂 + 反选 +
面包屑）超集覆盖，P1 字段不删（往返快照形状冻结面）。

## D7 — skip 13 → 14

LA_THUMB_BENCH 量测探针常驻（LibraryBenchmarkHarness 先例：MANUAL-ONLY gate =
量测语义，skip ≠ 逃逸）。探针落位 `LibraryGridModelTests`（本 plan 申报的修改文件，
不越界）；终轮全套 +1 skip。

## D8 — 测试 +27 超 plan 预估 +20..30 上沿

按 AC 逐条细分：Inspector 11（四臂×折/反选/面包屑/清空/Activity/描述渲染/智能相册
×2）、Search 5（四族映射/提交面/组装联动/清过滤/占位拒绝）、Relink 6（分类/批量
落库复核/失败不阻塞/取消三分类/handle 单调/整批进度）、Grid 补充 4（pager 三面 +
双击接线）、bench gate 1。判据「全套 0 fail + AC 机检」满足；同 M2-3-1 D6 先例。

## D9 — 量测语料 symlink 与种子勘误

①repo 在外置 USB 卷、/tmp 在根卷 → hardlink EXDEV（POSIX E18 实测），换
`createSymbolicLink`（ImageIO 直随，产耗口径不变：每 id 独立 production）。②首版
种子误将相对路径配 `path_kind=2`（absolute）→ resolve 全 stale → 全 nil；改
kind0（projectRelative，与 ImportService copy 模式同档）后 24/24 产出。③Release
R1（2141.6ms）为 ad-hoc 重签后冷启离群，主判据取热轮 R2/R3（837.1/838.9ms）；
Debug R1 同理（1349.0ms 冷卷缓存）。④「hardlinked」字样为 BENCH 行内沿用的语料
形态描述（symlink 实现），SUMMARY 表已如实标注 symlink。

## D10 — 分组列表骑当前 filter（测试设计教训）

Inspector 分组在每次 fold 后 `refresh()`，列表 = 当前 filter 域的 GROUP BY——折
Sony 后 Unknown 行消失、折 5★ 后 Unrated 消失（与 Alcedo「点击分组即筛选」语义
一致，产品正确）。执行期 5 起单类失败全部源于测试在折叠后仍按全域取行；修复 =
两段式测试（`clearFilter()` 后取行再折）。归因：plan 期未明示「分组列表是 filter
域投影」这一查询面语义（`groupCounts(by:filter:)` 签名本已明示）。零产品缺陷。

## 附：九签名消费面核对（AC#7 评审项）

| 签名 | 消费点 |
|---|---|
| `searchPage(filter:sort:anchor:limit:)` / `searchNullTail` | LibraryGridModel（P1 既有，网格经其游标） |
| `overviewCount(filter:)` | LibraryInspectorModel.refresh |
| `groupCounts(by:filter:)` | LibraryInspectorModel.refresh（四键循环） |
| `activitySeries(range:filter:)` | LibraryInspectorModel.refresh |
| `LibraryQueries.dayFilter(_:)` | LibraryInspectorModel.makeArm（.day 臂） |
| `currentFilterDescription(filter:)` | LibraryInspectorModel.refresh（SEARCH FILTER 渲染源） |
| `SmartAlbumStore.evaluate(id:domain:.library:...)` | LibraryInspectorModel（refreshSmartAlbums + toggleSmartAlbum） |
| `ExifSearchParser.parse(_:)` | LibrarySearchModel.submit |
| `ImageLinker.relinkRecord/resolve`（M2-2-2 面，KD-4 指定） | LibraryRelinkModel + Host 的桥 resolveURL |

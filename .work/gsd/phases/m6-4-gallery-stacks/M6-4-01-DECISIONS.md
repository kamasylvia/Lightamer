# M6-4-01 DECISIONS — 执行期裁决与偏离登记（2026-10-14 夜间全自动授权批）

> 正本链：plan（`d1a87117`+`8198f3be`）→ 七 OQ 生效值（CONTEXT，全 A）→
> 本文件（执行偏差 + 版本化条款）。晨审可推翻；推翻项回注修复批重走。

## D-01 谓词拼写：flag-aware JOIN（KD-5 字面式的语义收敛）

KD-5 的字面 SQL（`NOT IN (SELECT image_id FROM stack_content WHERE
position > 0)`）会隐藏**所有**栈的非封面成员，与 T4①「**收起栈**只余封面
行」+ T4④「**混合**收起/展开栈的过滤面」两处测试规格矛盾（字面式下混合
面无语义）。生效拼写收语义侧：

```sql
AND i.id NOT IN (SELECT sc.image_id FROM stack_content sc
                 JOIN stacks s ON s.id = sc.stack_id
                 WHERE s.collapsed != 0 AND sc.position > 0)
```

D-M6-4-3 的裁决本体零触碰：仍是纯 WHERE 谓词、keyset seek 零改动、无滤片
复制（checker 关注点 2 的唯一合法 diff 位 = runPage 装配点，一行 conjunct）。

## D-02 单栈展开 = 成员现 keyset 位（toggleCollapse 的 v1 语义）

收起态下 toggleCollapse 展开单栈后，其成员出现在各自 keyset 位（**不聚
拢**——gather 是全局 flat 模式的 fixup 属性）。Lightroom 的单栈聚拢语义
留 V2（fixup 按栈粒度触发）。expandAll/collapseAll 同时切换模式与全体
flag，两键行为与 Lightroom 一致。

## D-03 手动 group 的新生栈 = collapsed（KD-2 未钉值的落点）

`group(memberIDs:)` 内部落 `createStack(collapsed: true)`——与缺省收起
网格一致（新栈以封面呈现，不打散当前视图）；auto-stack（OQ-2）与
stackWith（KD-6）本就恒 collapsed。splitStack 的尾栈**继承**原栈 collapsed
值（保守；未钉值，登记）。

## D-04 无 undo 偏离（KD-3 申报项，plan 已授权）

stacks v1 = 即时生效 + 手动 ungroup 逆向，不建 undo 基建（图库域今日即
无 undo；LightCraft catalog-op undo 不借鉴）。auto-stack 不存出处与之一致。

## D-05 fixup forward-only 偏离（KD-7 申报项，plan 已授权）

已在早前页显示的成员不回拉（displayed 集合守卫）；与 LightCraft
gather-to-first-member 的差异 = 后页 keyset 重逢时**去重跳过**（S2 论证：
前拉成员的 keyset 位可后于当前 anchor，无重复性由 displayed-set 保证，
anchor 推进取 raw page last 不受扰）。union golden（T4⑨/T6③ 双测）钉死
无丢失面。

## D-06 收起态无顶替偏离 + 计数口径分裂（M1 申报项，plan 已授权）

① 封面被 filter/语义腿滤掉时整栈从网格消失（无首可见成员顶替）——纯谓
词裁决（D-M6-4-3）的已登记代价；语义腿顶替 App 侧可行（hit 集是有限 id
表）= V2 候选。② `overviewCount`/`groupCounts` 不加 stackMode → 收起态
下 Overview 总数与分组计数按全量行统计、网格按封面行显示，两口径分裂
（Lightroom 收起态计数只数封面）；stackMode 参数 = V2 候选（零调用点消费，
不实现）。

## D-07 导入缝匹配细则（E1 版本化条款，checker 关注点 4）

生效序（`ImportService.resolveSourcePath`）：
1. **后缀主式**：`image_path` 以 `"/" + relPath` 结尾；批内 map 优先，回
   落全库参数化 `LIKE '%' || ? ESCAPE '\'`。**转义字符 = `\`**，转义它本
   身 + `%` + `_`（T5② 的细则表覆盖命中面；`%`/`_` 字面 relPath 按
   O-1 条款有 ESCAPE 兜底）。
2. **多命中** → 批内 folderName 精确候选（`Media/<folderName>/<relPath>`，
   makePlan :220-228 + writeRow :579-583 的无条件落盘形）唯一命中即用，
   仍歧义 = 整组 skip。
3. **零命中** → folderName 精确候选（批内 → 库）→ 末段文件名 stem 唯一
   命中兜底。
4. 任一源解析失败/歧义未消 → **整组 typed skip**（`mergeStacksSkipped`），
   零半栈。product 或任一源已属他栈 → skip（导入缝不合并既有栈——group
   并组语义留给手动入口）。
- **link 模式不自动成栈**（S1）：`.lra` 留原点，`Media/` 前缀门使 link 行
  永不进入探测——自动成栈限 move/copy 导入。
- **计数器零 UI**：双计数仅测试消费（M4），进度面零改；展示面挂账 V2。

## D-08 执行序偏差：fixup 纯函数宿主提前至 T4 commit

plan 前排 T6 挂模型、T4 测纯函数；每 commit 构建自洽约束下，纯函数
`LibraryGridModel.stackAdjacencyFixup` 随 T4 commit 落位（其测试所在批），
T6 只做有状态接线。文件归属不变（App 侧模型，无 Core fixup 文件——O-3
additive 申报纪律维持）。

## D-09 schema 测试定向更新清单（M3 扩展：两法 → 九处）

plan M3 指名两处（`testPackageTablesCreated` extras allowlist +
`testFreshCreateStampsUserVersionFour...`）；实测版本面联动浮出**七处追
加**，全部为机械代际前滚（非语义变更），本批一并落位：
- `LibrarySchemaTests`：`testCurrentVersionReopensOK`（4→5）、
  `testSecondApplyIsIdempotent`（4→5）、`testFutureVersionRefused`
  （5→6）、`testV3ToV4Migration...`（快照代际 3-4→3-5 + 终版 4→5）、
  `testFullChainV1ToV4...`（1-4/2-4→1-5/2-5 + 终版 4→5；方法名保留原名，
  注释已勘误）。
- `DefaultLookTests`：`pre-migrate.1-4→1-5` + 终版 4→5 + 幂等重开注释。
- `ProjectLockTests`：三处 `pre-migrate.3-4→3-5`（perl 原位替换）。
- `LibraryDocumentTests`（Library 全轮浮出，收口轮同款机械前滚）：
  `testCreateSeedsFreshPackage`（4→5）、`testOpenZeroByteFileHeals...`
  （4→5）、`testOpenFutureVersionRefused`（5→6）。

## D-10 T5 fixture 的批内隔离（E1 纪律下的测试设计）

匹配细则表（T5②）各分支在同一测试方法内用**多个独立导入批**构造
（S 树消歧 → Burst 早批 → Solo 库回落 → Odd stem 兜底 → Amb stem 撞名），
全部走真 `importFolder`（E1 硬门：禁手拼 image_path）；stem 兜底分支的
落点行选独立未堆叠 stem（前批已堆叠行会被 already-stacked 门 skip——
语义正确性在 ④ 单独钉死）。

## D-11 auto-stack 池全集走查的性能注记（KD-7 申报项）

池 = 全集走查时，`collectAllIDs` 以 500/页双段 keyset 走完当前集合
（20k 行 ≈ 40 次索引 seek，id-only 投影）——与 semanticHits 全走查同量
级；分页恢复语义不受扰（走查不落 rows）。capture 值由 store 侧单次
`WHERE id IN` 批读（现有 `(capture_date, id)` 索引）。

## D-12 `.flat` 字节恒等双证据（M2 口径，checker 关注点 2）

1. **调用点清单（grep 实测；验收 M-d 勘误版）**：生产 SQL 消费点 =
   `LibraryGridModel.swift` 的 **7 处**——显式传参 5 处（:206/:218/:265/
   :277/:285——分页双段 + semanticHits 双段全走查；原申报 :180/:191/:236/
   :247/:254 为 T6 时点行号）+ `collectAllIDs` 双段 2 处（:540/:551，缺省
   `.flat`——D-11 池走查语义，本就不受收起谓词影响）；MCP
   PhotoProjection = **Session 域**（SessionIndexStore 行，零 `.lalb`
   接触，本批零 diff 亲证）；filmstrip 消费 `model.rows`（零 SQL）。
   缺省参 `.flat` 使全部非堆叠消费者编译面零改。
2. **行级恒等测试**：`StackPaginationTests.testFlatDefaultArgumentIsRowIdentical`
   （无参调用 vs 显式 `.flat` 逐行恒等，跨双段）。runPage 为函数内私有
   装配（无捕获缝），不落「SQL 组装零 diff 断言」类不可落断言。

## D-13 files_modified 范围外两文件补登记（验收 M-b）

T7 `923f3a85` 触碰 plan front-matter `files_modified` 之外的两文件：
`App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift`（+13 行
onChange 消费 + LibraryStore 注入）与 `App/Sources/Lightamer/
WorkspaceModel.swift`（+27 行 `pendingStackCommand` 载体）。定性 =
KD-8「View 菜单 + 非图库面 no-op 守卫」的必要机械依赖（pendingAIEnhance
既有命令路由模式复用，additive，零既有行为面变更——App bundle 零新法
零漂移佐证），补登记即闭环。

## D-14 两处「DECISIONS-registered」注记的登记落账（验收 M-c）

执行批两处代码头注自称 DECISIONS-registered 但无对应条目（事实正确、
登记缺失），本条补账、两处注记已改指本条：

1. `LibraryGridModel.reloadShrinkingSelection`（:525）：KD-7 post-write
   face——v1 **不保滚动位**（简形：reload 首页 + 选择收缩到幸存行），
   Lightroom 位保持语义 = V2 候选。
2. `LibraryQueries.stackMembers(ofStacks:)`（:382）：KD-5 additive 面
   ——fixup 的 gather 源需要整栈成员集，`stackMemberships(ids:)` 的页
   内投射看不到页外 id，故独立 additive 查询（非滤片复制、非 KD-5 清单
   改写）。

## D-15 翻账推迟申报编号（验收 M-e）

全批零翻账（plan `files_modified` 列名的 AGENTS/ROADMAP/REQUIREMENTS/
GOAL-STATE/TODO 五文档未动）——执行期开放式申报（SUMMARY「翻账建议」
节 + 本文件「建议翻账点」节）但未编号，属程序偏差，本条补编号。清偿 =
闭环批统一翻账，素材 = 本文件 D-01..D-15 + SUMMARY「实际收口 TOTAL」
节（02 的 S8 重算基线随修复批 +2 新法，见 SUMMARY 修复批节）。

## 待供件清单

无（全批零「无源待核」项）。

## 建议翻账点（闭环批统一做，本批未动——推迟申报编号 = D-15）

- AGENTS.md：M6-4 架构增量节（面 A 段）——本文件 D-01..D-15 为素材正本。
- ROADMAP：M6-4 行面 A 注记（✅ 归 plan 02 收口）。
- REQUIREMENTS：M6INT-02 兑现注记（面 A 部分）。
- GOAL-STATE：续接点（02 的 T7 对账基线 = 本 SUMMARY「实际收口 TOTAL」）。
- TODO：M6-4 条目。

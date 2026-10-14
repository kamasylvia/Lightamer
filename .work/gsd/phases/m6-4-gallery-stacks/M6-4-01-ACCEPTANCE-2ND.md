# M6-4-01 ACCEPTANCE-2ND — 图库 stacks + auto-stack 第二路独立验收记录

> **PASS / 0 error + 0 minor open + 1 升格建议 + 4 独立观察**
> （第二路 zcode 独立验收，零共享上下文，2026-10-14 夜；不 push。
> 与第一路结论一致无实质分歧；一处观察项升格建议见 §五 N-1。）

## 结论头（第二路 zcode 独立验收）

- **判定：PASS**。五正本（PLAN/CONTEXT/CHECKER/SUMMARY/DECISIONS）全文独立
  亲读 + 八 commit（`f30e83a3..6fa1f536`）逐 hunk 独立亲核 + 全套 `--all`
  独立 build+run（本路亲跑，非转引）+ 六面独立切入审计（不复述第一路：
  sqlite3 EXPLAIN QUERY PLAN 亲跑 / swiftc 直编聚类探针 / Python 驱动 200
  行大库 keyset 模拟 / sqlite3 ESCAPE 三转义探针含第一路未覆盖的字面反斜杠
  面 / 13 键逐键 zh/en 提取 / D-01..D-12 逐项找 REJECT）。
- 与第一路 5 minor 复核：**全部属实、清单完整**（M-c 悬空注记全量 grep 精确
  两处无第三处；M-b 范围外文件全量 diff 核对恰两处无第六处）。

## 一、全套独立复跑对账（本路亲跑）

| bundle | 本路实测 | 第一路 | 基线（M6-3） | 漂移 |
|---|---|---|---|---|
| IOP | 686/1/0（peak 6939MB） | 686/1/0（7546MB） | 686/1/0 | 0 |
| IOPParity | 460/3/0（peak 6694MB） | 460/3/0（6988MB） | 460/3/0 | 0 |
| Layers | 474/4/0（peak 1172MB） | 474/4/0 | 474/4/0 | 0 |
| **Library** | **727/4/0**（peak 623MB） | 727/4/0 | 671/4/0 | **+56 恰合** |
| Sessions | 280/4/0（peak 1277MB） | 280/4/0 | 280/4/0 | 0 |
| Export | 378/4/0（peak 6026MB） | 378/4/0 | 378/4/0 | 0 |
| App | 810/4/0（peak 2832MB） | 810/4/0 | 810/4/0 | 0 |
| **TOTAL** | **3815/24/0 / 2121s** | **3815/24/0 / 2134s** | 3759/24/0 | **+56/0/0 精确** |

- 本路数字对账亲算闭合：686+460+474+727+280+378+810 = 3815；skip 段和
  1+3+4+4+4+4+4 = 24；Library 727 − 671 = +56（六新文件 8+16+8+9+5+10
  ∈ 计划带 52..58 顶沿）。脚本尾行 `OK (direct launch, no testmanagerd)`；
  exit 0；零 MEMFAIL 零 crash；全程 caffeinate 包裹；peakRSS 全 8G 门内
  （最高 IOP 6939MB = 86%）。两路独立跑 TOTAL 同值（2121s vs 2134s），
  与 SUMMARY 申报推算值 3815 逐位一致——02 plan S8 重算基线 = 3815 成立。

## 二、六面独立审计（自选切入，非第一路路径复述）

### 2.1 并发/事务面

- **单事务边界**：store 全 op 族走 `ProjectFileStore.withWriteBatch`（
  `BEGIN IMMEDIATE` + body + COMMIT + checkpoint；body 抛错 ROLLBACK；
  readOnlyMode 断路器在唯一写出口）——亲读 ProjectFileStore :454-485。
  `splitStack` 的 delete-all + prefix 复用原栈 id + suffix 新栈、`group`/
  `stackWith` 的 involved 栈删除 + insertStack、`removeImage` 的图删 +
  <2 sweep，均单事务原子。✓
- **WAL 可见性**：LibraryStore/ExifSearchIndexer 共享同一 ProjectFileStore
  actor-confined 连接（两文件 `private let store: ProjectFileStore` 亲证）
  ——读写同连接，WAL 下不存在跨连接可见性问题面。`foreign_keys=ON` 在
  schema 基线（LibrarySchema :766）与打开点（ProjectFileStore :209/:268）
  双落——CASCADE 语义有效。✓
- **writePositions 重入安全**：静态函数（actor-confined 闭包零 self）、
  delete-first-then-insert（UNIQUE(image_id) + PK(stack_id,image_id) 下
  先插后删会碰 PK——顺序必要且正确）；全部调用点（setTop/moveInStack/
  splitStack/removeFromStacks）在 withWriteBatch 内。✓
- **autoStack 竞态窗**：读腿（capture rows + stackedIDs）与写腿之间有
  await 挂起点，actor 可插其它写方法——**per-cluster re-check（写腿内
  contended 重查、contended 簇整体跳过）在位**，注释明示 belt 语义。
  诚实实现。✓
- **独立发现 N-1（防御不对称）**：`autoStack` 读腿无空数组守卫（空 ids →
  `WHERE id IN ()` = SQLite syntax error），同函数的 `stackedIDs(in:)`
  helper 却有 `guard !ids.isEmpty`——**同一函数一有一无**。App 侧不可达
  （contextMenu 挂 cell = 池 ≥1；全集走查空库 = collectAllIDs 返回空后才
  调 store……空库走查返回空数组 → store.autoStack(ids: []) 直接炸）。
  第一路 O-i 定观察项；本路认为不对称形态 + 空库全集走查路径存在，升格
  建议登记级 minor（一行 guard）。见 §五。

### 2.2 分页面

- **谓词插点**：`runPage` 装配处 `appendFilterLeg` 后一行 conjunct（
  `if case .collapsed` 才拼）；`.flat` 缺省参下 SQL 字节恒等。✓
- **大库模拟（本路独立探针，Python 驱动 sqlite3，非复用测试 fixture）**：
  200 行库 + 20 收起栈（成员紧随封面 → 频繁跨 7 行页界）+ 1 展开栈——
  collapsed 谓词下 keyset 走查 162 行/24 页，**集合相等 / 无重复 / 序恒等
  全过**；页满 7 行；可见数 162 = 200 − 38 数学自洽；展开栈成员可见（
  D-01 flag-aware JOIN 语义亲证）；收起栈只余封面。✓
- **`IN ()` 空池**：查询面三 helper（stackMemberships/rows(byIDs:)/
  stackMembers(ofStacks:)）全有 `guard !ids.isEmpty`；唯独 autoStack 读腿
  缺（N-1）。✓（除 N-1）
- **stackMemberships 的 size 相关子查询**：EQP 实测 = SEARCH c2 USING
  PRIMARY KEY（stack_id 前导 seek）——页规模代价有界。✓
- **收起态谓词 EQP**：LIST SUBQUERY 一次性物化 + CREATE BLOOM FILTER，
  外层每行 O(1) 探测——复杂度 = O(images + stack_content)，与申报量级
  一致。**申报措辞精度缺口见 N-2**（「UNIQUE 索引使子查询为索引扫描」不
  成立——子查询无 WHERE 可走 UNIQUE 索引，实测 SCAN sc，但复杂度申报
  正确）。

### 2.3 聚类面

- **swiftc 直编独立探针（零测试套件依赖，九项边界全过）**：
  ①gap 恰等归簇 / 恰超（+0.0001）断开 ②同 capture 三 id tie 乱序输入两
  序恒等 + id 升序输出 ③nil-capture 跳过 ④全 nil / 空输入 = [] ⑤链式
  合并（A-B ≤gap, B-C ≤gap, A-C >gap → 三成员一簇——「相邻 ≤ gap 归簇」
  直读语义，plan KD-4 字面一致）⑥runs < 2 不成簇 ⑦输出簇内 id 升序
  （id 10/2/7 输入 → [2,7,10]）⑧zero-gap 同刻归簇 ⑨负 gap 退化为全断。
  ✓
- **缺省 60s 常量** + store 腿双 skip（stackedIDs 过滤 + 纯函数 nil 防御
  = KD-4 双重防御）亲读在位。✓
- **preview 零写**：ClusteringTests 用整包 clean-close 前后字节恒等钉死
  （亲读测试 :182）——强形态。✓

### 2.4 导入缝面

- **四步匹配实现与 D-07 条款逐行一致**（亲读 resolveSourcePath）：后缀
  主式（批内 map 优先 → 库 LIKE 回落）→ 多命中 folderName 消歧 → 零命中
  folderName/stem 兜底 → 整组 skip。likeEscaped 转义序 = 先 `\` 后 `%`/
  `_`（顺序正确——反向序会二次转义已转义字符）。✓
- **EXPLAIN QUERY PLAN 亲跑（真实索引形态：images 仅 idx_images_capture，
  无 image_path/file_stem 索引）**：LIKE 后缀回落 = `SCAN images` 全表扫；
  folderName/stem 兜底 = `SCAN images` 全表扫；精确等值 = 索引 seek。
  **可接受性申报成立**（批内 map 优先命中规避 SQL + merge 产物每批至多
  数个 × 数 source = 个位数全表扫，20k 行库亚毫秒级/次，导入本就逐文件
  IO 密集）——但申报未明说全表扫形态，记 N-2。✓
- **ESCAPE 三转义独立探针（本路补强，含第一路未覆盖面）**：`%`/`_` 转义
  恰 1 命中（未转义对照臂 wildcard 泄漏）+ **字面反斜杠 relPath**
  （`back\slash.tif`，likeEscaped 先转 `\` 产物 `\\` 恰 1 命中）——三转
  义全过，实现正确性补强确认。✓
- **link 行作 source 候选（N-5 独立观察）**：executeLink 行入
  batchImportedRows（sidecar probe 对 link 行不触发——Media/ 前缀门），
  但 resolveSourcePath 的 batchRows.filter 无前缀过滤——同批混合
  move/copy + link 导入时 merge 源可解析到 link 行。行为可辩护（源在库
  内）+ 极边缘（混合导入同批同 relPath），观察级。✓
- **零半栈钉死**：testMatchingRulesTable (d) 臂 `stackContaining == nil`
  断言 + mergeStacksSkipped == 1 亲读在案；alreadyStacked 前置检查（每
  involved id 独立查询）+ stackWith 前置 skip 双保险与 D-07 一致。✓

### 2.5 UI 面

- **九命令线程纪律**：LibraryGridModel = @MainActor final class（:28 亲
  证），九命令全 MainActor async 方法；store 调用 actor hop；状态改写零
  跨线程。pendingStackCommand 载体 = pendingAIEnhance 既有模式：菜单
  MainActor set → WorkspaceHostView `.onChange` MainActor 消费（consume
  先于 grid guard——非图库面 set 的命令被即时消费丢弃 = no-op 守卫）→
  `Task { await grid.… }`。✓
- **会话域零持久**：全批新增 diff 内 UserDefaults 命中 = 零（唯一命中 =
  注释文字）；13 键触发面全会话域。✓
- **13 键 zh/en 逐键亲验**（python json 逐键提取）：11 静态键 en/zh 双语
  值齐（Expand All Stacks/展开全部堆叠 … Cancel/取消）；两格式键完整键名
  （`library_stack_members_hint %lld` = " %lld photos in stack "/「堆叠内
  %lld 张照片」、`library_stack_auto_preview %lld` = " %lld stacks will
  be created "/「将创建 %lld 个堆叠」）双语在册。zh-audit `--check` 本路
  独立复跑 **PASS（1677/1918/zh complete）** 与第一路逐位一致。✓
- **格式键插值调用形态（N-3 机检面盲区）**：`String(localized:
  "library_stack_auto_preview \(previewCount)")` = focus_stack_dialog
  既有先例同形（SessionBrowserView :280 亲证）——语义合规（键在册 =
  scanner 可见），但红线机检 grep（`String.LocalizationValue("`）不覆盖
  此形态，申报措辞覆盖面偏宽。观察级。✓

### 2.6 偏差面 D-01..D-12 独立复核（逐项找 REJECT，零 REJECT）

| # | 本路独立裁决 | 独立依据 |
|---|---|---|
| D-01 | **准**（必要修正，非越权） | 字面式（无 JOIN 的 NOT IN position>0）会隐藏**展开栈**成员——本路大库模拟反向亲证：flag-aware 拼写下展开栈成员可见（exp_stack_members_visible=2）、字面式下必为 0；T4④ 混合面在字面式下不可测。D-M6-4-3 裁决本体（纯 WHERE/keyset 零改动/runPage 唯一 diff 位）逐项保持 |
| D-02 | 准（已登记） | toggleCollapse 不切模式实现亲读 + GridStackTests ⑤ |
| D-03 | 准（已登记） | group `collapsed: true` / split 读原 flag 传尾栈亲读；KD-2 未钉值 |
| D-04 | 准（plan KD-3 预授权） | — |
| D-05 | 准（plan KD-7 预授权） | S2 场景本路全程推演（封面首页/成员后页 keyset 位 → fixup 前插 + displayed 守卫 + anchor 推进取 raw last）自洽 |
| D-06 | 准（已登记） | overviewCount/groupCounts 零 diff 亲证 |
| D-07 | 准 | 四步序亲读一致 + ESCAPE 三转义探针（本路补强字面反斜杠面） |
| D-08 | 准（已登记） | stackAdjacencyFixup 在 T4 commit a33a24c1 载体亲证；App 侧静态函数零 Core fixup 文件（O-3 遵守） |
| D-09 | **准——全机械前滚，零断言放松** | 三文件 diff 逐行亲核：4→5 / 5→6（futureSchema 写 6 拒 6）/ 快照代际 1-4→1-5、3-4→3-5 / allowlist 增 stacks+stack_content 两名（FTS shadow 谓词不动）/ 方法名 Four→Five / 注释勘误——无一语义变更 |
| D-10 | 准（已登记） | testMatchingRulesTable 五独立导入批亲读（S 消歧→Burst 早批→Solo 库回落→Lone/Odd stem→Amb 撞名 skip），全走真 importFolder，(d) 臂零半栈断言在位 |
| D-11 | 准（已登记） | collectAllIDs 500/页 id-only 双段亲读；走查不落 rows |
| D-12 | 准（M-d 勘误成立） | 本路独立亲数调用点 = **7 处**全在 LibraryGridModel（:204/:216 语义双段 + :263/:275/:283 loadNextPage 三臂 + :540/:551 collectAllIDs 双段）；全仓其它文件零调用点——MCP Session 域零 .lalb 亲证 |

- **union golden 跨页 fixture（checker 关注点 3）**：亲核成立——
  StackPaginationTests testExpandedWalkUnionGolden（cover r09 首页 /
  成员 r01+r05 后页，pageSize 3）+ GridStackTests testExpandedFullWalk
  UnionEqualsFlatWalk（双栈跨页 + **诚实 flat 基线 = 直接查询走查**而非
  collapsed 模式复用）+ 邻接性断言（|memberPos − coverPos| < 4）。
  ✓

## 三、第一路 5 minor 复核（本路独立确认 + 完整性）

| # | 复核结论 | 本路证据 |
|---|---|---|
| M-a | **属实** | ImportMergeStackTests 五法名亲点无转义用例；checker O-1「补一条转义单测断言」未落。本路 sqlite3 探针补强（三转义含字面反斜杠全过）——实现风险消，欠回归钉。清偿建议不变：闭环批补一法 |
| M-b | **属实且完整** | 全批 diff 文件集（26 文件）vs plan front-matter 逐文件核对：范围外恰 = WorkspaceHostView.swift（+17 onChange 消费 + LibraryStore 注入）+ WorkspaceModel.swift（+27 pendingStackCommand 载体）——**无第六处**。additive 命令路由必要机械依赖，App bundle 零新法佐证 |
| M-c | **属实且精确** | 全量 grep 八处 DECISIONS 引用注记逐一对照 D-01..D-12：六处有对应条目（:38→D-05、:439→D-02、LibraryStore :626/:704→D-03、ImportService :821/:887→D-07）；悬空**恰两处** = LibraryGridModel :525（reloadShrinkingSelection 不保滚动位）+ LibraryQueries :381（stackMembers(ofStacks:) additive 面）——无第三处。清偿 = DECISIONS 补两行 |
| M-d | **属实** | 本路独立亲数 = 7 处（D-12 申报 5 处漏 collectAllIDs 双段）；行为正确（缺省 .flat = D-11 池走查语义），清单需勘误 |
| M-e | **属实** | 五文档现状亲核：AGENTS 无 M6-4 命中 / ROADMAP M6-4 行未 ✅ / REQUIREMENTS M6INT-02 无兑现注记 / GOAL-STATE 续接点停在 plan 批 / TODO M6-4 未勾——全批零翻账，SUMMARY 开放式申报未入 DECISIONS 编号。闭环批翻账时顺带闭 |

## 四、AC 逐条（第二路确认，不重复第一路证据链）

AC1-8 **全项本路独立复核成立**：AC1（DDL 逐字节亲读 + V5Tests 法名对表
①..⑧）/ AC2（16 法对表 + split 三边界与 removeFromStacks 退化等价性本路
推演：2 成员栈切 index 1 = 整栈解散 ≡ removeFromStacks 语义收敛）/
AC3（九项边界探针亲跑全过）/ AC4（大库模拟 + EQP + fixup S2 推演）/
AC5（四步序亲读 + EQP + ESCAPE 三转义）/ AC6（13 键逐键 + 线程纪律 +
零持久 grep）/ AC7（红线电池九项独立复跑全绿 + D-09 逐行抽验）/
AC8（TOTAL 见 §一；法数 8+16+8+9+5+10 = 56 本路亲点相符）。

## 五、本路独立发现（1 升格建议 + 4 观察；零 error、零新增 minor open）

- **N-1（升格建议：O-i 观察项 → 登记级 minor）**：`LibraryStore.autoStack`
  读腿空 `ids` 拼出 `IN ()` 非法 SQL 抛错，而**同函数** `stackedIDs(in:)`
  有 `guard !ids.isEmpty`——防御不对称是作者已意识到该缝的证据。App 侧
  主路径不可达（contextMenu 池 ≥1），但「全集走查 + 空库」组合
  （collectAllIDs 返回空 → store.autoStack(ids: [])）在代码路径上存在。
  清偿 = 一行守卫（闭环批或 V2 首触）。定级差一档非实质分歧（两路均认可
  不可达 + 修复成本极低）。
- **N-2（申报精度，登记级）**：plan 风险节「UNIQUE 索引使子查询为索引扫
  描」——EQP 实测 collapsed 谓词子查询 = `SCAN sc`（WITHOUT ROWID 主键树
  全扫；UNIQUE 索引不可达——子查询投影 image_id 无 WHERE 可走它）；导入
  缝 LIKE/stem 兜底 = `SCAN images` 全表扫（真实库无相应索引）。**复杂度
  申报均正确**（子查询一次性物化 + bloom；批内 map 优先 + merge 产物少
  数），机制名不精确。零动作或文档勘误，V2 候选。
- **N-3（机检面盲区，观察级）**：红线机检 grep（`String.LocalizationValue("`)
  不覆盖 `String(localized: "key \(x)")` 格式键插值形态——新代码恰用此
  形态（先例同形 + 键在册，语义合规）。后续机检若要钉 V14/F-2 禁形，需
  补 `String(localized: "[a-z_]*\\(` 非格式键形态的检查。
- **N-4（补强记录，零动作）**：ESCAPE 字面反斜杠 relPath 转义本路探针补
  强（第一路只测 %/_）——likeEscaped 三转义全过。
- **N-5（link 行 source 候选，观察级）**：§2.4——同批混合 move/copy +
  link 导入时 merge 源可解析到 link 行（batchRows.filter 无前缀过滤）。
  行为可辩护、极边缘，V2 候选（filter 加 Media/ 前缀守卫）。

## 六、与第一路分歧点

**零实质分歧**。唯一差一档：O-i 定级（第一路观察项 vs 本路升格建议
minor，N-1）——依据 = 防御不对称形态 + 空库全集走查代码路径，两路对
「App 主路径不可达 + 修复成本极低」无异议。

## 七、验收链状态

| 路 | 状态 | 结论 |
|---|---|---|
| 第一路 zcode 独立验收（ACCEPTANCE.md） | 完成 | PASS / 0 error + 0 minor open + 5 登记 minor + 6 obs |
| 第二路 zcode 独立验收（本文件） | **完成** | **PASS / 0 error + 0 minor open + 1 升格建议（N-1）+ 4 独立观察**；与第一路 5 minor 全部确认、清单完整；全套 `--all` 两路独立跑 TOTAL 同值 3815/24/0 |

- 执行链 `f30e83a3..6fa1f536` 八 commit 与 plan 提交约定逐条对表一致；
  本验收零 push、零历史手术；探针产物（/tmp/m64_cluster_probe、
  /tmp/esc2.sql、/tmp/paging_sim.sql、/tmp/eqp*.sql）即弃未入仓。
- 本路为第二路 zcode 独立眼（`dual_acceptance=true` 下的 zcode+omp 制度
  位，omp 配额阻塞先例由双 zcode 独立眼替代——M6-2/M6-3 同款，晨审可裁）。

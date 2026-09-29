# M2-3-2 ACCEPTANCE — 图库面（缩略图网格 + Album Inspector + 搜索三合一 + 批量 relink UI）（独立验收报告）

> **PASS / 0 error + 1 minor**（2 条 observation 不计数，见 Findings）
> 独立验收 subagent（2026-09-29）。plan = checker 修正版（`897bcb2` 批）；执行 = 5 commits
> `fe068a2` → `530c971` → `48e906f` → `0d0a1be` → `0f4a058`（收口）。

## Verdict

11/11 AC 全过、五重点核查全过、10 条偏差全部核实且合理、红线零违反。D2 relink
持久化腿缺口判「诚实登记 + 不可用面不误导用户」合规（架构事实，非本 plan 缺陷——
Core 零 diff 红线正确优先，后续 Core-face 小 plan 已三处登记）。独立复跑
**2130 / 14 skip / 0 fail（727.6s）** 与执行方声明终轮（2130/14/0, 733.1s）逐值一致
（零 flake，无需隔离归因）。量测探针独立复跑同量级（见下）。验收方修正 1 处文档
记账（新键计数 64 → 实测 61，本批同 commit，SUMMARY/GOAL-STATE 三处）。
翻账：REQUIREMENTS M2LIB-05 → 终 Delivered（数据面 M2-2-3 + 壳面本 plan 合龙）；
M2UIW-01/02 部分交付注记（不勾选）；M2LIB-07 relink UI 壳注记（本批同 commit）。

## 复跑（独立）

- 验收方先 fresh `xcodebuild build-for-testing`（HEAD = `0f4a058`，`LightamerCore/`、
  `App/`、`Tests/` 工作树零滞留）再 `caffeinate -dis Scripts/test-direct.sh` 全套直启：
  **Executed 2130 tests, with 14 tests skipped and 0 failures (0 unexpected) in 727.629s**。
- = 声明终轮（2130/14/0, 733.1s）逐值一致；skip 14 = 既有 13 + LA_THUMB_BENCH
  MANUAL-ONLY gate 1（D7，M2-2-3 D2 先例）；零挂测试，无 flake 归因事项。

## 缩略图首屏量测复核（重点⑤）

- gated 探针独立复跑一轮：`LA_THUMB_BENCH=1 Scripts/test-direct.sh 'LibraryGridModelTests'`
  → `BENCH| thumbnail first-screen tier-A (cold): N=24 total=829.8ms median=15.6ms
  p95=106.4ms max=106.4ms corpus=2x86MP-ARW+1x12MP-JPG, productions=24`。
- 与声明 **Debug 热轮带（823.7/833.1ms，median 15.5/15.6ms，p95 105.6/107.8ms）同量级
  同中位**；声明 Release 热轮主判据（837.1/838.9ms）与 Debug 热轮互证一致（差异
  ~1%），量级判定可信。M2-2-3 的 10.6ms/张 @86MP 基线以 median 15.6ms 复现（差值 =
  symlink 间接 + /tmp 目标卷 + 外置 USB 卷 IO，D9 归因成立）。`perf.md` §A.4 挂账行
  已销（量测值 + 指向本 plan SUMMARY，同批 diff 核实）。

## Commit 边界核查

- 5 commits 逐个 `git show --stat`：T1=4 文件 / T2=4 / T3=4 / T4=5 / T5=6 docs+测试——
  去重后累计 `git diff --name-only 8637dc8..HEAD` = **恰 18 文件（13 代码 + 5 docs）=
  front-matter 申报集全量，零越界**。T4 amend 注记（`LibraryInspectorModel.swift`
  selectedRows/selectedCount 入口面补漏 add）与最终边界一致。
- `git diff --name-only 8637dc8..HEAD -- LightamerCore/` = **空**（Core 零 diff）；
  legacyBody 树资产（Sidebar/SessionBrowser/Culling/FilterBar/CatalogBrowser*/
  Settings/LibraryProjectController/ImportModeDialog/ImportProgressView/
  LibraryLegacyGateTests）逐域 grep diff = 空。
- 工作树滞留物 = `.work/gui-acceptance/*.png` 与 `.work/{culling-cli,debug-flaky}/`
  历史会话资产，未被 5 commits 携入——非本验收范围（同 M2-3-1 先例）。

## 五重点核查结论

1. **D2 relink 持久化腿缺口（重点①）——判合规**：
   - 架构事实核实：`ProjectFileStore.withWriteBatch`（`LightamerCore/Sources/Library/
     ProjectFileStore.swift:305`）确为 **internal**（无 `public`）；App 层不可调用；
     备选路径否决论证成立（第二路 SQLite 破 WAL 单写者 / remove+insert 破 rowid 与
     album_content 级联 / updateProjection 只写 has_edits+params_hash）。
   - 生产面诚实：Host 建模 = `LibraryRelinkModel()` 默认 init → `persistLeg = nil` →
     `canPersist == false`；`RelinkSheetView.swift:157-181` run 按钮仅在 canPersist
     分支渲染，否则 `relink_persistence_pending` 诚实文案 + `library.relink.pending`
     marker——**不可用面不误导用户**。模型层另有 typed refusal 兜底
     （`LibraryRelinkModel.runBatch` guard persistLeg else throw，注释明示
     unreachable-through-gated-sheet）。
   - 测试真验持久化路径：`LibraryRelinkModelTests` 以 `@testable import LightamerCore`
     注入**真 store 写腿**（`makeStoreWriteLeg()`：`withWriteBatch` 内 UPDATE 字面量 +
     参数绑定 + `changes() == 1` 钉行），并经**查询面复核**（落库后 image_path 读回 +
     `ImageLinker.resolve` resolved 判 relived）——分类/编排/进度/取消/三分类计数全真，
     持久化语义被真实行使而非 mock 掉。
   - 登记账三处齐：DECISIONS **D2**（发现+备选否决+处置+后续）、LESSONS **L042**
     （缝→下游消费→全链 access level 三步核对对策）、GOAL-STATE 续接点（执行发现
     上报 orchestrator 裁量 + Core-face 小 plan `LibraryStore.relinkImage` 族指针）。
     按验收授权判「诚实登记 + 不可用面不误导」= 通过；**Core 补面不属本 plan**。
2. **壳零 SQL（重点②）**：`git diff --name-only 8637dc8..HEAD -- App/ | xargs grep -E
   'SELECT|FROM images|INSERT INTO|DELETE FROM|UPDATE images'` = **exit 1 零命中**；
   测试文件内的 UPDATE 字面量 = D2 注入真写腿（测试域，不在壳机检范围）。
3. **Core + legacyBody 零 diff（重点③）**：见「Commit 边界核查」——两者均空。
4. **搜索三合一 EXIF 腿真接（重点④）**：`LibrarySearchModel.submit` 唯一解析点 =
   `ExifSearchParser.parse`（零二次解析）；`family(for:)` = parser 两 typed case → 四
   呈现族的**形状纯分类**（`iso` 前缀 → iso 族 / `f`+数字或 `f/` → aperture 族 /
   `disjointDateRanges` → date 族 / 其余 → unrecognized），测试四输入逐条断言且集合
   零突变；空串走 parser `.isEmpty` 恒真 → 空 plan 清词法腿（group 臂保留）；
   CLIP/全文 mode 拒绝提交（`submit` guard + apply 按钮 `.disabled(model.mode != .exif)`
   双保险）、诚实 M2-10 空态 marker（`search.tab.clip.placeholder`/
   `search.tab.fulltext.placeholder`）——**零假开关零假结果**。行内错误
   （`search.error` marker）不弹 alert。⌘F 呈现态 = P1 bool 经
   `presentSearchDialog()/dismissSearchDialog()` 方法面三处消费（m6 单一 owner，
   WorkspaceRoutingTests 零改动全绿）。
5. **量测数字可信 + 10 偏差合理（重点⑤）**：探针复跑同量级（上节）；偏差 D1-D10
   逐一核实——D1（档 B 生产腿不接 = 申报集无渲染链文件，typed miss 不冒充档 A）、
   D3（Unrated inert = `legalOps(for: .rating)` 无 `.empty`，FilterSQL 冻结优先，
   模型拒绝 + 视图禁用态双面）、D4（id 集合腿谓词模型不可表达 → 按括号语义折叠
   album.group.rules，evaluate 成员计数闭环）、D6（P1 字段 scrollPosition/
   inspectorSelection 不写，语义保留）、D7（skip +1 = 量测语义非逃逸）、D8（+27 =
   11+5+6+4+1 逐 AC 细分）、D9（symlink 勘误 + Release R1 冷启离群单列取热轮）、
   D10（分组列表 = filter 域投影，5 起失败全为测试设计侧、零产品缺陷）全部成立。

## 逐 AC 核对（11/11 PASS）

| # | AC | 独立证据（file:line / 命令） | 判定 |
|---|---|---|---|
| 1 | 网格 keyset 无限滚动不重不漏 + isExhausted 封底零调用；双击 → EditorPhaseState 接线 | `LibraryGridPager.cellAppeared`（LibraryGridView.swift:57-62：exhausted/isLoading guard + 尾窗 arming 12 + 有界一次调用）；`LibraryGridModelTests`：`testScrollSignalIssuesBoundedLoadNextPageCalls` / `testSignalAwayFromTailIssuesNoCall` / `testExhaustedPagerIgnoresEverySignal` / `testDoubleClickWiresEditorPhaseState`（openCurrent + openEditor → phase/.editor + currentImageID + filmstripScrollAnchor + 选中聚焦 + 往返无损）全绿（复跑覆盖） | ✅ |
| 2 | Inspector 四分组点击 → filter 逐臂折叠/反选/面包屑退；载荷 typed | `LibraryInspectorModel.toggle`（:146-166：day/camera/labels/lens typed source，labels nil=Unrated inert 拒绝）；测试 `testDayClickFoldsDayFilterArm`（dayFilter 规则 verbatim）/ `testCameraClickFoldsTypedEqRulesAndUnknownFoldsEmpty`（mk+md eq；Unknown 双 `.empty`）/ `testRatingClickFoldsRatingArmAndUnratedIsRefused`（arms 原样断言）/ `testLensClickFoldsLensArm`（eq + Unknown `.empty`）/ `testReClickRemovesTheArm` / `testBreadcrumbRetreatsArmByArm` 全绿 | ✅ |
| 3 | Activity 柱点击 = 日期腿；总数卡随 filter 联动；SEARCH FILTER = currentFilterDescription typed 渲染 | `toggleActivityDay`（:170-172）= `.day(day)` 同腿；`testActivityBarClickFoldsTheDateLeg` + `testFilterDescriptionRendersTheFoldedState`（group 规则在前/plan 结构化项在后/ftsTerms verbatim/dateRange 判定）+ 总数卡 `overviewCount = (try? await queries.overviewCount(filter:))`（:112）联动断言全绿；视图渲染 `currentFilterDescription` verbatim（LibraryInspectorView.swift:207-256） | ✅ |
| 4 | 智能相册成员集 → 过滤折叠；nil 注入 typed missingStore 空态 | `toggleSmartAlbum`（:180-：evaluate(.library) 闭环 + `album.group.rules` 折叠 D4 + typed refusal）；`testSmartAlbumClickFoldsAlbumPredicateWithMemberCount`（member count 5 + 臂规则 == album.group.rules + 总数 5 + 反选回 12）/ `testNilQueryFaceSurfacesTypedMissingStoreEmptyState`（`smartAlbumsUnavailable` 旗 + 臂不折叠）全绿 | ✅ |
| 5 | 搜索三合一：四族行内呈现 + plan 组装 + 空串清过滤；CLIP/全文诚实空态 marker | `LibrarySearchModel.family(for:)`（:124-143 形状纯分类）+ 5 测试全绿（四族映射/逐族 submit 失败且网格零突变/合法输入 plan 字段+网格+Inspector 双联动/空串空 plan/占位 mode 拒绝）；marker 七枚在册（search.dialog / search.tab.exif\|clip\|fulltext / 两个 placeholder / search.error / search.input） | ✅ |
| 6 | relink：两形态分类 + 批量进度单调 + 取消三分类精确 + 失败不阻塞 | `LibraryRelinkModel.classify`（pathMissing/volumeAbsent typed）+ `runBatch`（行界 cancel continue 计 cancelled / persist 失败 catch 计 stillStale 不阻塞 / post-relink resolve 判 relived）；6 测试全绿：分类（健康行排除）/ 批量 relive + **真持久化复核**（@testable withWriteBatch UPDATE + changes()==1 + 查询面 resolve）/ 注入 throw 失败行不阻塞（relived 1 + stillStale 1）/ (0,1,2) 取消三分类精确 / handle 单调 + 整快照重放丢弃 + cancel 保底 + finished 旗 | ✅ |
| 7 | 壳零 SQL + 九签名逐个一致 | grep exit 1（见重点②）；九签名消费点逐个核实（DECISIONS 附表对账）：searchPage/searchNullTail（GridModel 既有）、overviewCount/groupCounts/activitySeries/dayFilter/currentFilterDescription（InspectorModel :112-117,241）、SmartAlbumStore.evaluate(.library)（InspectorModel refreshSmartAlbums + toggleSmartAlbum）、ExifSearchParser.parse（SearchModel :108）；ImageLinker.relinkRecord/resolve = M2-2-2 面（RelinkModel :99-108,158-161） | ✅ |
| 8 | 量测 BENCH\| 落账 + perf.md §A.4 销账同批 | 探针 `testThumbnailFirstScreenProductionObservation`（LA_THUMB_BENCH gate，:367-）+ SUMMARY BENCH 表（Debug×3 + Release×3）；`git show 0f4a058 -- .work/gsd/phases/m2-2-library-project/perf.md` 同批销账行（量测值 + SUMMARY 指针）；验收复跑同量级（829.8ms） | ✅ |
| 9 | 新 UI 全量 String(localized:)；Core 零 diff；legacyBody 零 diff | 新 UI 四视图 + 两模型 grep `Text("` 裸字面 = **零命中**；键数实测 **61 distinct**（grid 4 / inspector 23 / dialog 10 / relink sheet 16 / search 4 / relink model 4）——SUMMARY 报 64 系记账偏差（本批修正，见 Findings minor-1）；plan 预估 60..80 区间内；Core/legacyBody 零 diff（边界核查节） | ✅ |
| 10 | 全套 0 fail，计数 ≈ 基线 + 20..30 | 独立复跑 **2130/14/0**（= 2103 + 27：Inspector 11 + Search 5 + Relink 6 + Grid 补充 4 + bench gate 1）；+27 处预估上沿外一字（D8 粒度声明，判据「0 fail + AC 机检」满足，同 M2-3-1 D6 先例） | ✅ |
| 11 | diff 边界 == 申报集 | 见「Commit 边界核查」：累计恰 18 文件 = 申报集全量零越界 | ✅ |

## Findings

### error（0）

无。

### minor（1）

1. **SUMMARY/GOAL-STATE 新键计数 64 vs 实测 61**：SUMMARY AC#9 行「新键 64 个
   （LibraryGridView 5 / InspectorView 25 / GlobalSearchDialog 10 / RelinkSheetView 16 /
   SearchModel 4 / RelinkModel 4）」与 Manual-Only 节「新增 64 键族」、GOAL-STATE 续接点
   「新键 64」三处；逐文件 `localized:` 键名提取实测 **61**（4/23/10/16/4/4）。纯记账
   偏差（数量级、plan 预估区间、AC#9 判据均不受影响）。验收方在本批同 commit 修正
   三处为 61（标注 acceptance correction）。

### observation（不计数）

1. **BENCH 行 `hardlinked` 字样**：探针 print 语料描述沿用 hardlinked，实现为
   symlink——D9④ 已自声明（「语料形态描述沿用，SUMMARY 表如实标注 symlink」），
   测量值本身不受影响。接受原样（改探针 print 会无谓扰动量测产物文件）。
2. **占位 mode 的模型层拒绝文案**：`LibrarySearchModel.submit` 对 CLIP/全文 mode 返回
   `.failed(.unrecognizedToken(raw))`（其 message 提及 EXIF 文本）；UI 不可达——apply
   按钮对非 exif mode `.disabled` + 占位分支无输入框，该路径仅为模型层防御。不改。

## D2 架构注记（验收方裁定记录）

批量 relink 的 UI/分类/编排/进度/取消/计数面已**全量交付且经真实行使**（注入腿在
测试域驱动真 store 写并经查询面复核）；唯一缺台阶 = 生产域的 Core 公共写面。这是
M2-2-1 交付时的 access-level 事实（internal）与本 plan Core 冻结红线共同作用的架构
结果，非执行缺陷。验收判「诚实登记 + 不可用面不误导用户」通过，且不要求本 plan 补
Core。**后续项（已三处登记）**：Core-face 小 plan——`LibraryStore.relinkImage
(id:imagePath:pathKind:volumeUUID:)` 族（updateProjection 同型、withWriteBatch 走
WAL 单写者既有缝），落地后 Host 注入生产腿 + 摘除 sheet gate 即全功能；M2LIB-07
本批已附壳注记指向。

## 翻账清单（本批同 commit）

- REQUIREMENTS **M2LIB-05**：`Delivered 数据面` → **终 Delivered**（数据面 M2-2-3 +
  壳面 M2-3-2 合龙注记：网格/Inspector/搜索对话框壳 + P4 视觉走查维持 OQ-10 并案）。
- REQUIREMENTS **M2UIW-01** / **M2UIW-02**：部分交付注记（不勾选——图库面壳到、
  编辑器面留 M2-3-3；M2UIW-02 另记 M2-3-1 胶片条已交付）。
- REQUIREMENTS **M2LIB-07**：relink UI 壳注记（D2 gate + Core-face 小 plan 指针）。
- SUMMARY / GOAL-STATE：新键计数 64 → 61（minor-1 修正）。
- 本报告 `phases/m2-3-ui-shell/M2-3-2-ACCEPTANCE.md`；GOAL-STATE 续接点追加验收行。

# M2-3-2 SUMMARY — 图库面（缩略图网格 + Album Inspector + 搜索三合一 + 批量 relink UI）

> Plan M2-3-2 收口（2026-09-29）。执行 = ZCode subagent worker；5 任务 4 代码提交 + 本收口提交，未 push。
> 裁决正本 = `M2-3-CONTEXT.md`（D-M2-3-CONTEXT-1..12 + checker 回注 m1..m9）；plan = checker 修正版 `897bcb2`。
> 边界开关：每任务边界查 `.work/config.toml [gsd]`，全程 `paused=false / auto=true`（连跑）。

## 提交账

| 任务 | Commit | 内容 |
|---|---|---|
| T1 | `fe068a2` | LibraryGridView（LazyVGrid + LibraryGridPager 滚动信号胶水 + 桥缩略图 + 星级角标 + 选中环 + `library.grid`/`library.grid.cell.<id>` marker）+ WorkspaceHostView 建 grid/bridge/双栏骨架（ImageLinker resolve 缝 + `.lathumbs` 目录）+ 双击 openEditor 真缝（grid.openCurrent + workspace.openEditor）+ WorkspaceModel present/dismissSearchDialog 方法面 + 4 测试 |
| T2 | `530c971` | LibraryInspectorModel（typed 载荷 → FilterArm 折叠/反选/面包屑退 + 总数卡/Activity/过滤态联动 + 智能相册 evaluate 闭环）+ LibraryInspectorView（Alcedo `AlbumInspectorPanel` IA 逐件 + `library.inspector.*` marker 族）+ Host 挂右栏 + 11 测试（真 .lalb） |
| T3 | `48e906f` | LibrarySearchModel（ExifSearchParser 包装 + typed error 四族映射 + plan 组装 + 空串清过滤 + 占位 mode 拒绝）+ GlobalSearchDialog（模式分段卡/输入段/应用段 + 行内错误 + CLIP/全文诚实空态 marker）+ Host sheet 消费 `isSearchDialogPresented`（m6）+ 5 测试 |
| T4 | `0d0a1be` | LibraryRelinkModel（stale 两形态分类 + App 层批量编排 + RelinkTaskHandle 第二腿 + 三分类计数）+ RelinkSheetView（两节呈现 + 换源选择器 + 进度/取消 + 结果计数）+ Inspector ACTIONS 入口 + Host sheet + 6 测试（真 .lalb + 真文件 + 真持久化腿） |
| T5 | 本提交 | 首屏缩略图量测（LA_THUMB_BENCH gated 探针入 LibraryGridModelTests）+ perf.md §A.4 销账 + SUMMARY/DECISIONS/GOAL-STATE/LESSONS |

## 测试终值

**全套 2130 / 14 skip / 0 fail**（终轮，Debug，`Scripts/test-direct.sh`，见下方轮次账）。

- 基线 2103（M2-3-1 终态）+ 新增 **27** = 2130：LibraryInspectorModelTests 11 +
  LibrarySearchModelTests 5 + LibraryRelinkModelTests 6 + LibraryGridModelTests 补充 4
  （pager 3 + 双击接线 1）+ 首屏量测探针 1（MANUAL-ONLY gate skip）。
- skip 13 → **14**：+1 = LA_THUMB_BENCH gated 量测探针（M2-2-3 D2 先例：harness
  MANUAL-ONLY skip 是量测语义，非逃逸测试）。
- 轮次账：T1 轮全套 **2107/13/0**（718.1s）→ T2+T3 合并轮 **2123/13/0**（755.9s）→
  终轮（T4+T5）**2130/14/0**（733.1s）。执行期单类失败 5 起（测试设计侧，见
  DECISIONS D10）全部当轮修复，零产品缺陷挂起。

## 缩略图首屏量测（销 M2-2-3 perf.md §A.4 挂账）

`BENCH| thumbnail first-screen tier-A (cold): N=24`——真 `.lalb` + 档 A 语料
（repo `input/RAW` 真件：2×86MP ARW + 1×12MP JPG，symlink×24，缩略图盘缓存冷启），
P2 host 同款接线（`LibraryThumbnailBridge` tier A，`productionCount=24` 验证零缓存命中），
三轮 Debug + 三轮 Release（Release 冷启首轮离群单列）：

| 轮 | total（24 张首屏） | median/张 | p95/张 | 备注 |
|---|---|---|---|---|
| Debug R1 | 1349.0ms | 15.7ms | 406.6ms | 首轮含卷冷缓存 |
| Debug R2/R3 | 823.7 / 833.1ms | 15.5 / 15.6ms | 105.6 / 107.8ms | 热轮 |
| Release R1 | 2141.6ms | 16.0ms | 584.7ms | 冷启离群（ad-hoc 重签后首跑） |
| Release R2/R3（热，主判据） | **837.1 / 838.9ms** | **15.6 / 15.7ms** | **107.6 / 108.1ms** | 24 张首屏冷产 |

判读（非门，观察项）：档 A 产能在 M2-2-3 的 10.6ms/张 @86MP 基线上稳定复现
（median ≈ 15.6ms，差值 = symlink 间接 + /tmp 目标卷 + 本机外置 USB 卷 IO）；首屏
24 张 wall ≈ 0.84s，其中 p95 = 首张 ARW 的 CGImageSource 冷开（108ms），其后同件
复用行 ~0.4ms（盘写透后）——**网格滚动的 in-flight 合并 + 盘缓存让「同件多行」
场景产能≈常数**。观察项登记：档 B（has_edits 管线渲）生产腿本 plan 未接（D1），
其首渲产能与真机 60fps 滚动一并 P4 走查（M2-3-1 观察项 #3 并案维持）。

## AC 总表（11/11 全绿）

| # | AC | 机检证据 | 状态 |
|---|---|---|---|
| 1 | 网格 keyset 无限滚动不重不漏 + isExhausted 封底零调用；双击 → EditorPhaseState 接线 | LibraryGridModelTests 补充 4：pager 信号计数（尾窗 1 信号 = 1 次调用、离尾零调用、exhausted 后全忽略）+ `testDoubleClickWiresEditorPhaseState`（openCurrent + openEditor → `editorPhase.currentImageID`/`filmstripScrollAnchor`/选中聚焦/往返无损）；既有 11 条分页/NULL 尾/重置/白名单/选择状态机全绿 | ✅ |
| 2 | Inspector 四分组点击 → filter 逐臂折叠/反选/面包屑退；载荷 typed | LibraryInspectorModelTests：day 臂 = `LibraryQueries.dayFilter` 规则 verbatim（captureDate between）；camera 臂 = cameraMake/cameraModel eq（Unknown 双 nil → 两 `.empty` 规则）；labels 臂 = rating eq（Unrated 无合法规则形态 → 拒绝点击，D3）；lens 臂 = lensModel eq/empty；再点反选（arms 清空 + 总数回 12）；`removeArm(at:)` 逐臂退（06-01 AND Sony → 2 → Sony 5 → 12） | ✅ |
| 3 | Activity 柱点击 = 日期腿；总数卡随 filter 联动；SEARCH FILTER 区 = currentFilterDescription typed 渲染 | activity 三日序列 ASC 断言 + `toggleActivityDay("2024-06-02")` → day 臂（与分组行同投影）+ 总数 3；过滤态断言：group 规则在前、plan 结构化项在后（captureDate between + iso eq）、ftsTerms verbatim、structuredTerms typed、dateRange nil 判定 | ✅ |
| 4 | 智能相册成员集 → 过滤折叠；nil 注入 typed missingStore 面板空态 | 真 SmartAlbumStore（temp 目录）建「Top Rated」（rating ≥ 4）→ evaluate 闭环 member count 5 → 臂折叠 = album 谓词本身（KD-5 成员集→相册谓词，D4）→ 总数 5；再点反选；nil queries 注入 → `smartAlbumsUnavailable` 空态 + 臂不折叠 | ✅ |
| 5 | 搜索三合一：EXIF 腿 typed error 四族行内呈现 + plan 组装 + 空串清过滤；CLIP/全文 tab 诚实空态 marker | LibrarySearchModelTests 5：`family(for:)` 四族纯映射（isoabc→iso / f/2.8.5→aperture / disjoint→date / 2024-02-30→unrecognized）；四输入逐条 `submit` → `.failed(族)` 且集合零突变；`iso800 35mm 2024-06` → plan 字段断言 + 网格行数联动 + queries.currentFilterDescription 双联动；空串/空白 → 空 plan 恒真 + 首页重取；CLIP/全文 mode → 拒绝不造假；marker：`search.dialog`/`search.tab.exif|clip|fulltext`/`search.tab.clip.placeholder`/`search.tab.fulltext.placeholder`/`search.error` | ✅ |
| 6 | relink：stale 两形态分类 + 批量进度单调 + 取消三分类计数精确 + 失败不阻塞 | LibraryRelinkModelTests 6：分类（pathMissing [GoneD,MissingA] / volumeAbsent [RemoteB] / 健康行排除）；批量 relive + 持久化行经查询面复核（image_path 落盘 + ImageLinker.resolve resolved）；失败行注入 throw 不阻塞后行（relived 1 + stillStale 1）；行界取消（0,1,2 精确）；handle 单调 + 重放整快照丢弃 + cancel 保底 + finished 旗 | ✅ |
| 7 | 壳零 SQL：新文件 `SELECT|FROM images` grep 零命中；九签名调用与 M2-2-3 清单逐个一致 | `git grep -E 'SELECT|FROM images' -- <7 新文件>` = 0 命中（三次任务边界各查一次）；九签名逐个对齐：searchPage/searchNullTail（GridModel 既有消费）、overviewCount/groupCounts/activitySeries/dayFilter/currentFilterDescription（InspectorModel）、SmartAlbumStore.evaluate(id:,domain:.library,sessionStore:nil,catalogStore:nil,libraryQueries:)（KD-5）、ExifSearchParser.parse（SearchModel）；ImageLinker.relinkRecord/resolve = M2-2-2 面（KD-4 指定消费） | ✅ |
| 8 | 缩略图首屏量测 BENCH\| 行落账；perf.md §A.4 挂账销账注记同批 | 上节 BENCH 表（Debug×3 + Release×3，热轮主判据）；perf.md §A.4 行尾追加「→ M2-3-2 已量测」注记（本提交同批 diff） | ✅ |
| 9 | 新 UI 全量 `String(localized:)` 键；`LightamerCore/` 零 diff；legacyBody 树资产零 diff | 新键 61 个（LibraryGridView 4 / InspectorView 23 / GlobalSearchDialog 10 / RelinkSheetView 16 / SearchModel 4 / RelinkModel 4——plan 预估 60..80 区间内；zh 值 P4 对账批补录；64→61 = 验收修正 2026-09-29，逐文件键名提取实测）；`git diff --name-only 8637dc8..HEAD -- LightamerCore/` = 空；SidebarView/SessionBrowserView/CullingView/FilterBarView/CatalogBrowser*/SettingsView/LibraryProjectController/ImportModeDialog/ImportProgressView/LibraryLegacyGateTests 全部零 diff | ✅ |
| 10 | 全套回归 0 fail，计数 ≈ 基线 + 20..30 | 终轮 **2130/14/0**、0 fail；+27 > 预估 +20..30（粒度声明，同 M2-3-1 D6 先例：按 AC 逐条细分；skip +1 见 D7） | ✅ |
| 11 | diff 边界 == 申报文件集 | `git diff --name-only 8637dc8..HEAD` = 13 代码文件（9 App + 4 Tests，全部在 front-matter 申报集内）+ 本收口批 4 docs（SUMMARY/DECISIONS/perf.md/GOAL-STATE）+ LESSONS = 申报集全量，零越界 | ✅ |

## KD 执行确认（KD-1..5 全按 plan 落地，偏差见 DECISIONS）

- **KD-1**：LazyVGrid adaptive（cell min 156）+ LibraryGridPager（尾窗 arming 12，
  信号计数可机检；keyset 幂等吃掉窗口近似误差——plan 风险节预期成立）+ 单元格三件
  （桥缩略图/星标/选中玻璃环）+ 双击 openEditor 真缝 + `library.grid` marker 族。
- **KD-2**：四分组点击 → 同一份 `ExifSearchFilter.group` 的 typed FilterArm
  （day/camera/labels/lens 载荷逐字段，零 label 反解析）；反选 + 面包屑逐臂退 + Clear；
  总数卡 = `overviewCount(filter:)` 联动；SEARCH FILTER = `currentFilterDescription`
  verbatim（rules + ftsTerms + structuredTerms + dateRange）；面板纯逻辑沉
  LibraryInspectorModel（入参 queries/grid 注入），视图零业务。
- **KD-3**：三段对话框一次成型（模式卡/输入/应用）；EXIF 腿真接
  `ExifSearchParser.parse`，typed error 四族行内呈现（不弹 alert）；plan 折进共享
  `ExifSearchFilter` → 网格 + Inspector 同批联动；空串 = `.isEmpty` 恒真清过滤；
  CLIP/全文 = 「Semantic search arrives with M2-10」诚实空态（零假开关假结果）；
  ⌘F 呈现态 = P1 预埋 bool，仅 WorkspaceHostView 消费（m6，对话框不自持）。
- **KD-4**：stale 两形态分组呈现 + 每组换源选择（NSOpenPanel 目录缝，
  `LibraryPanels` 同族）+ 按文件名匹配 + 批量编排循环 App 层 + RelinkTaskHandle
  第二腿注册 + 完成 relived/stillStale/cancelled 分类计数入面板行态。
  **持久化腿 = 注入缝**（Core 写面缺口，D2——本 plan 唯一 KD 级偏差）。
- **KD-5**：SMART ALBUMS 区列 albums → 点击 `evaluate(.library)` 成员计数闭环 +
  album 自身谓词折叠（D4）；nil queries → typed missingStore → 面板空态（未开项目
  防御路径实测断言）。

## 偏差与说明（详版 DECISIONS）

1. **D1 档 B 生产渲染腿未接**：plan T5 量测口径自钉「档 A 语料」；渲染链文件不在
   本 plan 申报集（M2-3-1 D3 缝保持），has_edits 行 typed miss 占位。生产腿挂
   P3/P4（编辑器管线缝 + 真机走查并案）。
2. **D2 relink 持久化腿 = Core 写面缺口**（执行发现）：`ProjectFileStore.withWriteBatch`
   internal + `LightamerCore/` 零 diff 红线 → 持久化腿注入式；测试以 @testable 驱动
   真写验证（含查询面复核）；生产 sheet run 按钮 gate + 诚实文案。后续 =
   Core-face 小 plan（`LibraryStore.relinkImage(id:record:)` 族）。
3. **D3 Unrated 星档臂 inert**：`FilterField.rating` 合法 op 集无 `.empty`（FilterSQL
   Session 域冻结，禁扩）→ Unrated 行渲染禁用态；Unknown camera/lens 走 text 面
   `.empty` 合法折叠。
4. **D4 智能相册臂 = 相册谓词折叠**：images rowid 无 FilterField，id 集合腿不可表达
   ——按 KD-5 括号语义「成员集 → 相册谓词」：evaluate 出成员计数（闭环），折叠
   album.group.rules。grid 显示 = 成员集。
5. **D5 ⌘F 呈现方法面**：WorkspaceModel 增 `presentSearchDialog()/dismissSearchDialog()`
   （m6 单一 owner 的方法化），LightamerApp 命令 + Host sheet + 对话框三面经由。
6. **D6 P1 字段消费度**：`LibraryPhaseState.scrollPosition`（滚动恢复）与
   `inspectorSelection`（arm 模型超集）本 plan 未写——滚动恢复挂 P3/P4（缝合在，
   WorkspaceRoutingTests 语义不动）。
7. **D7 skip 13 → 14**：LA_THUMB_BENCH 量测探针 1 条 MANUAL-ONLY gate（M2-2-3 D2 先例）。
8. **D8 测试 +27 > 预估 +20..30 上沿**：粒度按 AC 细分（11+5+6+4+1）；判据「0 fail +
   AC 机检」满足。
9. **D9 量测语料 symlink**：repo 在外置卷、/tmp 在根卷——hardlink EXDEV（POSIX
   E18），换 symlink（ImageIO 直随）；执行首版种子 path_kind=2 配相对路径的失误
   当轮修正（kind0 projectRelative）。Release 冷启轮（R1 2141ms）离群单列，主判据
   取热轮 R2/R3。
10. **D10 分组列表骑当前 filter**：Inspector 分组在 filter 折叠后刷新，Unknown/
    Unrated 行随过滤消失（Alcedo 同语义：点击分组即筛选）——执行期 5 起单类失败
    全部源于此测试设计（两段式：clearFilter 后再取行），零产品缺陷。

## Manual-Only / 顺延

- 档 B（has_edits）缩略图生产腿 + 其首渲产能 + 真机网格 60fps 滚动 → P3/P4
  走查（M2-3-1 观察项 #1/#3 并案）。
- relink 生产持久化 = Core 写面 plan（D2；UI/分类/编排/计数已全量在位）。
- computer-use Alcedo 对照 = P4 统一执行（OQ-10）。
- zh 文案补录（本 plan 新增 61 键族：`library_grid_*` / `library_inspector_*` /
  `search_*` / `relink_*` / `tasks_relink_*` / `shell_library_inspector_arrives`）
  = P4 对账批（OQ-9 A）。

---
phase: m6-4
plan: "M6-4-01"
title: "图库 stacks + auto-stack——LibrarySchema v4→v5 两新表 additive 迁移（stacks/stack_content join 形 + UNIQUE(image_id) 一图一栈 DB 级不变量 + 封面 = position 0 单真相）+ LibraryStore stacks CRUD 命令面（LightCraft op 族：group/stackWith/setTop/move/split/ungroup/removeFromStacks/setCollapsed + CASCADE 后余 <2 自动解散）+ auto-stack 时间阈值聚类（60s 缺省可调 + preview + runs ≥2 + 跳过已堆叠/无 capture）+ 分页×堆叠（收起态 SQL 谓词 + 展开态 forward-only 页内 fixup）+ App 网格徽章 UI + View 菜单 + contextMenu + 导入缝 merge 产物自动成栈"
wave: 1
depends_on: []
autonomous: true
requirements: ["M6INT-02（REQUIREMENTS :409）"]
estimated_tests: "+52..58"
test_bundles: [LIB, APP]
files_modified:
  - LightamerCore/Sources/Library/LibrarySchema.swift            # 修改：schemaVersion 4→5 + v5 注记段 + stacks/stack_content 两张 CREATE SQL + idx_stack_content_image + stacksColumns/stackContentColumns 冻结面数组 + indexNames 追加 + migrate v4→v5 槽（幂等 CREATE IF NOT EXISTS×3）+ apply() fresh-create 面追加（KD-1）
  - LightamerCore/Sources/Library/LibraryStore.swift             # 修改：LibraryStack 值类型 + stacks CRUD 命令面（createStack/group/stackWith/setTop/moveInStack/splitStack/ungroup/removeFromStacks/setCollapsed/setAllCollapsed/stacks()/stackContaining/members — 全部单事务 + 不变量校验 + removeImage 追加同事务解散清扫，KD-2/KD-3）
  - LightamerCore/Sources/Library/StackClustering.swift          # 新建：纯函数聚类（capture 升序 + 相邻 ≤ gap 归簇 + runs ≥2 + 跳过已堆叠/无 capture + defaultGapSeconds = 60 + preview 组数）+ store 落地面（autoStack(ids:gap:preview:)，KD-4）
  - LightamerCore/Sources/Library/LibraryQueries.swift           # 修改：StackDisplayMode 参数（.flat 缺省 = SQL 字节零变化 / .collapsed = NOT-IN 谓词，searchPage+searchNullTail 双腿）+ stackMemberships(ids:) + rows(byIDs:) + stackOverviews()（KD-5）
  - LightamerCore/Sources/Library/ImportService.swift            # 修改：导入批完成缝 merge 产物自动成栈（provenance kind ∈ {hdr-merge, hdr-merge-mertens, pano-merge} + sources relPath 解析 + stackWith collapsed + 源不全 typed skip + ImportOutcome additive 计数，KD-6）
  - App/Sources/Lightamer/Library/LibraryGridModel.swift         # 修改：stackDisplayMode 会话态（缺省 .collapsed）+ 展开态 forward-only fixup（有界补拉 + 已显示集合去重）+ 命令面（toggleCollapse/expandAll/collapseAll/group/ungroup/setCover/removeFromStack/autoStack 路由，KD-7）
  - App/Sources/Lightamer/Library/Views/LibraryGridView.swift    # 修改：cell 堆叠徽章 overlay（封面徽章 + 成员计数 + 收起/展开 chevron）+ contextMenu（成栈/解栈/设为封面/从栈移除/自动成栈…，KD-8）
  - App/Sources/Lightamer/Library/Views/LibraryAutoStackDialog.swift # 新建：auto-stack 确认对话框（gap stepper + preview 组数 + 开始/取消；SwiftUI sheet/alert 缝，禁 runModal，KD-8）
  - App/Sources/Lightamer/UI/LightamerApp.swift                  # 修改：View 菜单「堆叠」节（expand/collapse all；非图库面 no-op 守卫，KD-8）
  - Resources/Localizable.xcstrings                              # 修改：13 新键尾块纯插入（menu_view_stacks_* 2 + library_stack_* 11，清单见 T5）
  - Tests/LightamerTests/LibrarySchemaV5Tests.swift              # 新建（LIB，8 法）：fresh-create 出生面 + v4→v5 迁移 + 幂等重跑 + v1→v5 全腿 + futureSchema typed 拒 + 冻结面零触碰 + UNIQUE 不变量负测 + CASCADE 解散
  - Tests/LightamerTests/LibraryStackStoreTests.swift            # 新建（LIB，16 法）：CRUD 全 op 族 + 不变量负测 + stackWith 语义 + 时间戳
  - Tests/LightamerTests/AutoStackClusteringTests.swift          # 新建（LIB，8 法）：聚类 golden 表 + 边界 + skip 面 + preview/commit + round-trip
  - Tests/LightamerTests/StackPaginationTests.swift              # 新建（LIB，9 法）：collapsed 谓词 + flat 字节恒等 + nullTail + memberships + fixup 纯函数 + anchor 一致性 + 全走查 union golden
  - Tests/LightamerTests/ImportMergeStackTests.swift             # 新建（LIB，4 法）：merge kind 检测 + 封面语义 + 源缺 skip + 非 merge 不触
  - Tests/LightamerTests/LibraryGridStackTests.swift             # 新建（APP，10 法）：缺省收起态 + fixup 无重复 + 展开态 union golden + 徽章投影 + 命令路由 + auto-stack 池选择
  - Project.swift                                                # 修改：六新测试文件登记对应 target 数组（显式清单无 glob）+ `tuist generate` 恒为该批最后一个动作（L041）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt   # 修改：六新行登记（E2 纪律，随各自任务 commit）
  - AGENTS.md                                                    # 修改：M6-4 架构增量节（面 A stacks 段；T7）
  - .work/gsd/ROADMAP.md                                         # 修改：M6-4 行面 A 注记（行级 ✅ 归 plan 02 收口）
  - .work/gsd/REQUIREMENTS.md                                    # 修改：M6INT-02 兑现注记（面 A 部分，T7）
  - .work/GOAL-STATE.md                                          # 修改：续接点
  - .work/TODO.md                                                # 修改：M6-4 条目
  - .work/LESSONS.md                                             # 如踩坑
  - .work/gsd/phases/m6-4-gallery-stacks/M6-4-01-SUMMARY.md      # 新建（T8）
  - .work/gsd/phases/m6-4-gallery-stacks/M6-4-01-DECISIONS.md    # 新建（T8——KD 偏差 + fixup forward-only 偏离登记 + 无 undo 偏离 + 导入缝匹配细则 + 计数器零 UI 注记）
  - .work/gsd/phases/m6-4-gallery-stacks/M6-4-01-ACCEPTANCE.md   # 新建（T8——双重验收：zcode PASS 后串行 omp 二次验收，严禁并发）
---

# Plan M6-4-01 — 图库 stacks + auto-stack（面 A 全量批）

> **性质**：M6-4 两 plan 之一（面 A；执行串行 01→02，两面独立、验收 lane 各自
> 聚焦）。规格正本 = 同目录 `RESEARCH.md`（面 A §A1-A4）；裁决正本 =
> `M6-4-CONTEXT.md` 裁决记录（**OQ-M6-4-1..4 全按推荐，夜间全自动授权批
> 2026-10-14**，晨审可推翻）。机制底座 = album_content/version_ref join 表先例
> 形（`LibrarySchema.swift` :196/:309/:374 亲读）+ v1→v2/v2→v3/v3→v4 三个
> 幂等迁移槽先例（:762-816）+ `semanticHits` 全走查投影先例
> （`LibraryGridModel.apply(semanticHits:)` :113-152）。
>
> **基线**：**3759/24/0**（M6-3-VALIDATION 终验 `TOTAL|3759/24/0|` 两路独立
> 亲跑同值，exit 0 零 MEMFAIL；亲证记录 = `phases/m6-3-ultrahdr/
> M6-3-01-ACCEPTANCE.md` :23）。本批预期全套 **3811..3817/24/0**
> （+52..58；五新 LIB 文件 45 法 + 一新 APP 文件 10 法 = 计划 55，带留
> ±3 记账滑差——M6-3 minor-1 教训：申报带按顶沿预估）。

## 已定裁决（生效值，硬约束，不得重开）

M6-4 OQ-1..4（面 A 相关项）**全部按推荐裁**（CONTEXT 裁决记录 2026-10-14）：

1. **OQ-1 = A（schema v5 两新表 join 形态）**：`stacks` + `stack_content`
   两新表 + `idx_stack_content_image` UNIQUE 索引；封面 = position 0 成员
   （不设 cover 列）；一图一栈 = UNIQUE 索引 DB 级强制；`images` 冻结列清单
   零触碰。
2. **OQ-2 = A（auto-stack = LightCraft 全套语义）**：gap 缺省 60s 可调 +
   preview 只报组数 + 拍摄时间升序相邻 ≤ gap 归簇 + runs ≥2 + 跳过已堆叠/
   无 capture + 结果落普通栈（collapsed）+ 不存 auto 出处。
3. **OQ-3 = A（分页×堆叠）**：收起态 = SQL 谓词排除非封面成员（keyset 零
   改动）；展开态 = App 侧页内 fixup（**forward-only 有界偏离**——KD-7）。
4. **OQ-4 = A（merge 产物自动成栈，落点 = 导入缝）**：merge 完成点在
   Session 域零 `.lalb` 接触（CONTEXT D-M6-4-4 亲核）——自动成栈生效点 =
   ImportService 导入批完成缝（provenance merge 族 + sources 全解析 →
   stackWith collapsed）。

**架构红线（本 plan 全程 + checker 机检面）**：
- **`images` 冻结列清单零 diff**：`imagesColumns` 29 项 verbatim 不动（v2 的
  `default_look_pending` 已在其列）；`albumsColumns`/`albumContentColumns`/
  `versionRefColumns`/AI 七表列面零改；`reservedTableNames` 三名零改（stacks
  是激活实体表，不入 reserved——注记进 v5 注记段）。
- **schema 迁移红线**：列零变更零回填（纯 CREATE additive）；`PRAGMA
  user_version` 双写纪律（truth = user_version，`project_meta` 不承载版本）；
  快照轮换 + 单 `BEGIN IMMEDIATE` + ROLLBACK 全走既有缝，零新机制。
- **`.flat` 查询字节恒等**：`StackDisplayMode.flat` 缺省参 = 全部既有调用
  点（含 semanticHits 全走查、filmstrip、M6-1 MCP PhotoProjection）SQL 零
  变化；MCP 快照族零 diff（R3 收口 = MCP 不透出堆叠序）。
- **零新 SPM / `.metal` 零 diff / V50Order 零触 / 六格式导出矩阵零触 /
  QuickLook+Spotlight appex 零触 / `.lra` sidecar schema 零触**（stacks 是
  `.lalb` 域，不碰 sidecar 一个字节）。
- **UserDefaults 零新键**（gap 与显示态全会话域——KD-8）；xcstrings 13 新键
  尾块纯插入 + zh-audit 对账；LocalizationValue 插值禁形（V14/F-2）；runModal
  禁入（对话框走 SwiftUI sheet/alert 缝，L057）。
- **L041**：新测试文件随任务 commit 登记 `Project.swift` + BUNDLE-MAP，
  `tuist generate` 恒为该批最后一个动作；**L070** 不 push；测试宿主进程清理
  前核 parentage（M2-7-3 教训）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 schema v5 DDL 与迁移槽（T1）

- DDL（RESEARCH A4 原式，列序即冻结面）：
  - `stacks(id INTEGER PRIMARY KEY, collapsed INTEGER NOT NULL DEFAULT 0,
    added_time REAL, modified_time REAL)`；
  - `stack_content(stack_id INTEGER REFERENCES stacks(id) ON DELETE CASCADE,
    image_id INTEGER REFERENCES images(id) ON DELETE CASCADE,
    position INTEGER NOT NULL, PRIMARY KEY (stack_id, image_id)) WITHOUT
    ROWID`；
  - `CREATE UNIQUE INDEX IF NOT EXISTS idx_stack_content_image ON
    stack_content(image_id)`。
- `stacksColumns`/`stackContentColumns` 冻结面数组（`versionRefColumns` 同形
  文风）+ `indexNames` 追加 `idx_stack_content_image`（`triggerNames` 零改）。
- `schemaVersion = 5` + v5 注记段（v3/v4 注记同文风）：**两新表 PURE
  ADDITIVE**——既有表列零变更、零回填，栈初始为空；旧包打开走
  ProjectFileStore 快照轮换 → `migrate(from: 4, to: 5)` 新槽。
- 迁移槽：`if from <= 4 && to >= 5 { try createStackTables(on: handle) }`，
  幂等 = 三条 `CREATE IF NOT EXISTS`（部分迁移快照重跑干净——v2→v3 槽
  「幂等两次」纪律第三代）；`apply()` fresh-create 面追加两条表 + 一条索引
  （v4 新生包出生即带全 DDL——version_ref/七表先例同位）。
- **封面语义**：`position = 0` = 封面（LightCraft `photos[0]` 同构，单真相）；
  成员 position 恒稠密 0..n−1（store 全部写路径同事务重编号）。

### KD-2 LibraryStore CRUD 命令面（T2，LightCraft op 族 SQL 化）

- 值类型 `LibraryStack { id, collapsed, memberIDs: [Int64], addedTime,
  modifiedTime }`（memberIDs = position 序，index 0 = 封面）。
- op 族（全部 `withWriteBatch` 单事务；校验失败 = typed
  `LibraryError.constraintViolation`，盘面零写）：
  - `createStack(memberIDs:collapsed:)`：≥2、无重复、无一已属他栈
    （UNIQUE 索引兜底 + store 先查给可读错误）；
  - `group(memberIDs:)`（LightCraft `group_ops` 并组语义）：成员已属他栈 →
    **整栈并入**（他栈其余成员按原序跟入）；结果 <2 = no-op；
  - `stackWith(productID:sourceIDs:)`：merge 产物语义 = group + 封面恒 =
    product + collapsed 恒 true（KD-6 消费）；
  - `setTop(stackID:imageID:)`（封面 = 挪到数组头）/ `moveInStack(
    stackID:imageID:delta:)`（±1 步进，越界 clamp）；
  - `splitStack(stackID:atImageID:)`：从该图起切后缀为独立栈；后缀 ==1 →
    退化为 removeFromStacks（该图出栈）；切分后任一半 <2 → 该半解散
    （LightCraft「余 <2 解散」同构）；
  - `ungroup(stackID:)` / `removeFromStacks(imageID:)`（移行 + 重编号 +
    余 <2 同事务解散）/ `setCollapsed(stackID:collapsed:)` /
    `setAllCollapsed(_:)`；
  - 读面：`stacks()` / `stackContaining(imageID:)`（UNIQUE 索引反查）/
    `members(of:)`。
- **CASCADE 解散清扫**：`removeImage(id:)`（:405）在删除事务内追加——FK
  CASCADE 掉 stack_content 行后，sweep 查 `stacks` 中成员 <2 者同事务删除
  （LightCraft remove_from_stacks 语义的删除臂；album_content 先例的
  「store 在同事务收尾」同形）。
- `added_time`/`modified_time` = epoch REAL（albums 行同惯例）；一切写路径
  同步 stamp `modified_time`。

### KD-3 无 undo 的偏离登记（T2，程序面）

LightCraft stack ops 可撤销（catalog op-log）；我方图库域（albums/.rating
族）今日即无 undo 基建——stacks v1 = 即时生效 + `ungroup` 手动逆向，**不建
undo**。DECISIONS 登记偏离；auto-stack 不存出处（OQ-2 生效值）与此一致
（解栈 = 唯一逆向动作）。

### KD-4 auto-stack 聚类（T3）

- `StackClustering`（Core 纯函数，独立新文件）：输入 =
  `[(id: Int64, capture: Double?)]`（已堆叠集 + 无 capture 行调用方预过滤
  亦可，函数内双重防御）+ `gap: Double`（`defaultGapSeconds = 60`）；语义 =
  capture 升序排序（stable——tie 走 id 升序，确定性全自握）→ 相邻间隔
  ≤ gap 归同簇 → **runs ≥ 2 才成簇** → 输出 `[[Int64]]`（每簇内升序）。
- store 落地面 `autoStack(ids:gap:preview:)`：池 = 调用方给定的 id 集（App
  侧决定 = 多选选区 or 全集走查，KD-7）；`preview = true` → 只报成簇组数
  零写盘；`false` → 一次 `withWriteBatch` 批量 `createStack(collapsed:
  true)`（一个事务 = LightCraft「一个 undo 批」的事务等价物）。
- 排序输入的 capture 值来源 = `images.capture_date`（现有列 + 现有
  `(capture_date, id)` 索引，零新增数据依赖——OQ-1 裁决的代价面兑现）。

### KD-5 查询面：谓词 + memberships（T4）

- `enum StackDisplayMode { case flat, collapsed }`；`searchPage`/
  `searchNullTail` additive 参数 `stackMode: StackDisplayMode = .flat`——
  `.flat` SQL 字节恒等（缺省参 = 既有调用点零改）；`.collapsed` → WHERE
  追加 ` AND i.id NOT IN (SELECT image_id FROM stack_content WHERE
  position > 0)`（keyset seek 形状零改动——anchor 仍取过滤后末行， seek 与
  谓词同属 WHERE 一致性自洽）。
- `stackMemberships(ids:) -> [Int64: StackMembership]`（imageID → stackID/
  position/size/collapsed）——徽章与 fixup 的单次 JOIN 面；
  `rows(byIDs:) -> [LibraryImageRow]`（fixup 有界补拉）；
  `stackOverviews() -> [(stackID, size, collapsed)]`（View 菜单/统计消费，
  可选交付）。

### KD-6 导入缝 merge→stack（T5→T6，OQ-4 生效值落点）

- `ImportService.importFolder` 行插入完成后追加 `autoStackMergeProducts()`：
  - 对本批每个落盘 destination 探测 `.lra`（`sidecarURL(for:ext:)` 同位）
    → tolerant decode 取 `provenance.kind` + `sources[].relPath`；
  - kind ∈ `{"hdr-merge", "hdr-merge-mertens", "pano-merge"}`（=
    `ProvenanceReplay.Kind` merge 三 case 的 rawValue；focus-stack/average/
    median/sigma 不入——LightCraft 语义只挂 HDR/pano 域）才参与；
  - 源解析：对每条 `relPath` 依次试库内 image_path 候选
    `["Media/" + relPath, relPath]` 精确匹配（本批新行 map 优先，回落全库
    查询）；末段文件名 stem 唯一命中兜底；**任一源解析失败 → 整组 typed
    skip**（计数上浮，零半栈）；
  - 全解析 → `LibraryStore.stackWith(productID:sourceIDs:)`（collapsed）；
    product 或任一源已属他栈 → skip（导入缝不合并既有栈——group 并组语义
    留给手动 `group` 入口）。
- `ImportOutcome` additive `var mergeStacksCreated: Int = 0`（显式默认值 =
  既有构造点零 diff）；**v1 零 UI 呈现**（进度面零改），计数仅测试消费——
  展示面挂账 DECISIONS。
- 代价面：每导入文件至多一次 sidecar JSON 读（tolerant decode；无
  provenance 键即跳过）——导入已是逐文件 IO 密集面，增量有界。

### KD-7 App 侧：显示态 + forward-only fixup（T5→T7）

- `LibraryGridModel`：`stackDisplayMode: StackDisplayMode = .collapsed`
  （**缺省收起**——零栈时两态逐字节同观感，与 Lightroom 惯例一致；会话域
  不持久，UserDefaults 零新键）。收起态 = 查询面谓词（KD-5）替走；展开态 =
  `.flat` 查询 + fixup。
- **展开态 fixup（OQ-3 预留的 plan 期定案，终形）**：`append(page)` 后
  单趟——①收集页内行的 `stackMemberships`；②对页内出现且 `size ≥ 2` 的
  栈，`rows(byIDs:)` 补拉缺失成员；③成员**向前**插入到该栈在本页最早出现
  成员的槽位之后（栈内 position 序），**已显示集合（displayed-IDs Set）
  命中即跳过**；④displayed 集合随 append/插入同步生长。
  - 正确性三件套（R1 兑现）：**无重复**（displayed 集合守卫——后页补拉到
    前页位置的成员，其 keyset 位置 ≤ 当前 anchor，后页 keyset seek 永不
    再取）；**无丢失**（全走查 union golden：展开态完整走查的 displayed
    集合 == `.flat` 全走查集合，测试钉死）；**幂等有界**（重复 loadNextPage
    零增量；补拉量 ≤ 页内栈的总成员数，栈小——burst 量级）。
  - **forward-only 偏离**（对 LightCraft gather-to-first-member）：已在
    早前页显示的成员不回拉（不重写已显示面）；DECISIONS 登记。
- 语义覆盖面（semanticHits != nil）**绕过 fixup**（hit 序投影即显示序，
  两腿不混——KD-3 既有纪律的延伸）；收起态谓词在语义全走查腿同样生效
  （收起语义 = 集合过滤器，与排序正交）。
- 命令面：`toggleCollapse(stackID:)` / `expandAll()` / `collapseAll()` /
  `groupSelection()`（选区 ≥2）/ `ungroup(stackID:)` / `setCover(imageID:)` /
  `removeFromStack(imageID:)` / `autoStack(gap:preview:)`（池 = selectedIDs
  ≥2 时选区，否则全集走查——`apply(semanticHits:)` :113 的全走查形复用，
  capture 值从走查行收集）。**栈写命令后 = `reloadFirstPage()` + 选区按
  存活 id 收缩**（不保滚动位——v1 简形；DECISIONS 登记）。

### KD-8 App UI 面（T7）

- **网格徽章**（`LibraryGridView` cell overlay 落点）：封面 cell 叠加徽章
  （栈成员计数 × 收起/展开 chevron）；chevron 点击 = `toggleCollapse`；
  accessibility label = `library_stack_members_hint`（%lld 成员）。
- **contextMenu**：成栈（选区 ≥2）/ 解栈 / 设为封面 / 从栈移除 / 自动
  成栈…——路由走 `LibraryGridModel` 命令面；**自动成栈确认对话框**
  （`LibraryAutoStackDialog` 新文件）：gap stepper（秒，初值 60）+
  preview 组数行（进入即 preview 查询）+ 开始/取消——SwiftUI `.sheet`
  缝呈现，**禁 runModal**（L057；调用点 `Task { await … }` hop）。
- **View 菜单**（`LightamerApp.swift` :1727 CommandMenu）：「堆叠」节 =
  展开全部 / 收起全部——静态项 + 图库面非激活时动作 no-op 守卫（既有菜单
  惯例；零 MenuCommandID/零快捷键）。
- **xcstrings 13 新键**（尾块纯插入）：`menu_view_stacks_expand_all` /
  `menu_view_stacks_collapse_all` / `library_stack_members_hint` /
  `library_stack_group` / `library_stack_ungroup` /
  `library_stack_set_cover` / `library_stack_remove_from_stack` /
  `library_stack_auto_menu` / `library_stack_auto_title` /
  `library_stack_auto_gap_label` / `library_stack_auto_preview_fmt` /
  `library_stack_auto_start` / `library_stack_auto_cancel`。

## read_first

1. `.work/gsd/phases/m6-4-gallery-stacks/M6-4-CONTEXT.md`（裁决记录 = 生效
   值正本）+ `RESEARCH.md` 面 A（§A1 LightCraft 语义原文 / §A3 落点 / §A4
   DDL 与分页形态）
2. `LightamerCore/Sources/Library/LibrarySchema.swift`（:102 schemaVersion +
   :196/:309/:374 join 表先例形 + :360/:641 索引面 + :652 reserved +
   :681-723 apply + :762-816 迁移槽族——KD-1 全部先例源）
3. `LightamerCore/Sources/Library/LibraryStore.swift`（:101 actor +
   :116 createAlbum 校验文风 + :147 withWriteBatch 用形 + :378 insertImage +
   :405 removeImage——KD-2/CASCADE 清扫落点）+
   `LightamerCore/Sources/Library/ProjectFileStore.swift`（迁移派发 +
   sqlite3_backup 快照轮换钩子）
4. `LightamerCore/Sources/Library/LibraryQueries.swift`（:66 anchor +
   :170 actor + :174 whitelist + :191/:209 双腿 + :223 runPage SQL 装配——
   KD-5 谓词插点）
5. `App/Sources/Lightamer/Library/LibraryGridModel.swift`（:54 rows +
   :113 semanticHits 全走查先例 + :175 loadNextPage + :224 append——KD-7
   fixup 落点）
6. `App/Sources/Lightamer/Library/Views/LibraryGridView.swift`（cell 渲染
   = 徽章 overlay 落点）+ `App/Sources/Lightamer/UI/LightamerApp.swift`
   :1727（View CommandMenu）
7. `LightamerCore/Sources/Library/ImportService.swift`（:281 importFolder +
   :513 sidecarURL + :522 migrateSidecars + :579/:586 writeRow/insertRow——
   KD-6 落点）+ `LightamerCore/Sources/Stack/ProvenanceReplay.swift`
   :39-49（Kind rawValue 表）
8. `Tests/LightamerTests/LibraryStoreTests.swift` + `LibraryQueriesTests.swift`
   （真 `.lalb` fixture 力学正本）+ `LibrarySchemaTests.swift`（冻结面
   断言形——v5 新面仿写）+ `LibraryGridModelTests.swift`（APP 级注入形）
9. `Scripts/test-direct.sh`（:165 bundle 注册表）+ BUNDLE-MAP 登记纪律 +
   AGENTS.md M2-2/M2-8 架构增量节（Library 域红线文风）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits 全英文；只 add 相关文件；
  front-matter `files_modified` 为界）；新测试文件随各自任务 commit 登记
  BUNDLE-MAP（E2）+ `Project.swift`（L041：`tuist generate` 恒末位）。
- **构建**：`caffeinate -dis` 包裹；单测标准命令 = `Scripts/test-direct.sh
  --bundle Library` / `--bundle App`（注册表拼写，散文缩写不入命令行）；
  **全套 `--all` 需 orchestrator 批准，本 plan 收口轮才申请**（8G 运行门 +
  MEMFAIL 机检兜底在案）。
- **资源监控**（AGENTS）：清理 Lightamer 进程前核 parentage（测试宿主
  parent = 脚本树，GUI = launchd——M2-7-3 事故教训）。
- **L057**：对话框只走 SwiftUI sheet/alert；`grep -rn "\.runModal("
  App/Sources` 零命中机检。
- **L070** 不 push；零历史手术；中文待核标注显式化，无源待核项入 DECISIONS
  待供件清单。
- 红线自证（T7）：`git diff <基线>..HEAD -- LightamerCore/Sources/Library/
  LibrarySchema.swift` 逐节核对（imagesColumns 等冻结数组零命中）+ MCP
  快照族原样 + xcstrings 尾块纯插入（diff = 纯插入验证）+ UserDefaults
  零新键 + `Project.swift` dependencies 块零 diff + `.metal` 零 diff。

## Tasks

### T1 LibrarySchema v5（KD-1）

- read_first 2 → DDL 三条 + 冻结面数组 + indexNames 追加 + schemaVersion 5
  + v5 注记段 + 迁移槽 + apply() fresh-create 追加。
- 验收：`LibrarySchemaV5Tests.swift`（LIB，8 法）——①fresh-create（v5 新
  包）`stacks`/`stack_content`/索引出生即在 + user_version = 5 ②v4 包
  （v4 DDL 手建 + 手工 stamp user_version=4）打开 → 迁移 5 + 数据保全
  ③幂等：迁移后快照重跑（二次 migrate 4→5）零异常零重复 ④v1 包全腿走查
  1→5（v1 fixture 先例同形）⑤futureSchema：user_version = 6 → typed 拒
  且文件零写 ⑥冻结面：imagesColumns/albumsColumns/albumContentColumns/
  versionRefColumns PRAGMA verbatim 零变 + triggerNames 零变 +
  reservedTableNames 三名 negative ⑦UNIQUE 不变量：同 image_id 二次入栈 →
  SQLite constraint → typed violation ⑧CASCADE 解散：删图 → membership
  行没 + 余 <2 栈消失 + ≥2 栈幸存。

### T2 LibraryStore CRUD（KD-2/KD-3）

- read_first 3 → `LibraryStack` 值类型 + 全 op 族 + removeImage 解散清扫。
- 验收：`LibraryStackStoreTests.swift`（LIB，16 法）——①createStack happy
  （position 稠密 0..n−1，封面 = 0）②<2 拒 ③重复成员拒 ④已属他栈拒
  ⑤stackContaining 反查 ⑥members 序 ⑦setTop（封面换位 + 全员重编号）
  ⑧move ±delta 与越界 clamp ⑨setCollapsed 单栈 ⑩setAllCollapsed ⑪split
  后缀 ≥2（两栈都 ≥2 的中点切）⑫split 边界（后缀 =1 → 出栈语义；前缀
  <2 → 解散）⑬ungroup ⑭removeFromStacks（重编号 + 余 <2 解散）⑮group
  并组（他栈整栈跟入 + 序保全）⑯stackWith（封面 = product + collapsed =
  true）+ modified_time stamp 抽查。

### T3 auto-stack 聚类（KD-4）

- read_first 1 §A1 → `StackClustering.swift` 纯函数 + store
  `autoStack(ids:gap:preview:)` 落地。
- 验收：`AutoStackClusteringTests.swift`（LIB，8 法）——①golden 表（3
  burst + 游散，手算期望簇）②gap 边界（间隔 == gap 归簇 / 精确超 gap
  断开）③乱序输入排序 + tie 确定性（同 capture 双 id 序恒定）④runs <2
  不成簇 ⑤已堆叠跳过 ⑥无 capture 跳过 ⑦preview 零写（库快照前后逐字节）
  ⑧commit 落栈 collapsed + 读回 round-trip == 期望簇。

### T4 查询面（KD-5）

- read_first 4 → StackDisplayMode 双腿谓词 + stackMemberships + rows(byIDs:)
  （+ stackOverviews 可选）。
- 验收：`StackPaginationTests.swift`（LIB，9 法）——①collapsed 谓词：收起
  栈只余封面行 ②`.flat` 缺省参调用与无参调用行序逐行恒等（字节恒等的行级
  代理 + SQL 组装零 diff 断言）③nullTail 腿谓词生效 ④混合收起/展开栈的
  过滤面 ⑤memberships map 正确性（position/size/collapsed）⑥rows(byIDs:)
  序与缺 id 面 ⑦fixup 纯函数（KD-7 ③单趟变换的 Core 侧可测形：页行 +
  memberships + 补拉行 → 重排结果——前插 + displayed 去重 + 保序）⑧跨 3 页
  keyset 走查（collapsed 谓词下）无 gap 无重叠（anchor 链一致性）⑨全走查
  union golden：展开态（查询+fixup）完整走查 id 集合 == `.flat` 全走查
  id 集合。

### T5 导入缝 merge→stack（KD-6）

- read_first 7 → `autoStackMergeProducts()` + ImportOutcome additive 计数。
- 验收：`ImportMergeStackTests.swift`（LIB，4 法）——①导入含 hdr-merge
  产物 + 全源的目录 → 产物栈成立（封面 = 产物 + collapsed）②Mertens/pano
  kind 各一法覆盖（参数化或三断言合一）③源缺一 → skip 计数 + 零栈 +
  零半写 ④无 sidecar/非 merge kind（如 focus-stack）零触 + 既有 Import
  断言族原样绿（Outcome additive 默认值零漂移亲证）。

### T6 App 侧模型层（KD-7）

- read_first 5 → LibraryGridModel 显示态 + fixup + 命令面。
- 验收：`LibraryGridStackTests.swift`（APP，10 法）——①缺省 `.collapsed`
  （首查行集 = 谓词面）②展开态 fixup：成员跨页场景无重复显示 ③展开态
  全走查 union == flat 全走查（R1 终测）④徽章投影（memberships → cell
  计数/chevron 态的模型面）⑤toggleCollapse 后行集刷新正确 ⑥expandAll/
  collapseAll ⑦groupSelection 路由（≥2 门 + <2 no-op）⑧ungroup/setCover/
  removeFromStack 路由 ⑨autoStack 池选择（选区 vs 全集走查）+ preview 不
  动库 ⑩栈写命令后 reloadFirstPage + 选区收缩面。

### T7 App UI + 文档同步（KD-8）

- read_first 6 → 徽章 overlay + contextMenu + AutoStackDialog（sheet 缝）+
  View 菜单节 + xcstrings 13 键尾块插入 + AGENTS M6-4 架构增量节（面 A 段）
  + ROADMAP/REQUIREMENTS 注记 + GOAL-STATE/TODO。
- 验收：构建零警告新增；`grep -rn "\.runModal(" App/Sources` 零命中；
  zh-audit `--check` 对账（13 新键 MISSING = 0）；LocalizationValue 插值
  禁形零命中；语义覆盖面（semantic overlay）下徽章/fixup 零触回归绿。

### T8 收口

- SUMMARY（任务序/bundle 分账/对账链）+ DECISIONS（KD 偏差申报：**无 undo
  偏离**〔KD-3〕/**fixup forward-only 偏离**〔KD-7〕/**导入缝匹配细则与
  skip 语义**〔KD-6〕/**auto-stack 池全集走查的性能注记**〔20k 级全走查
  代价与分页恢复语义〕/计数器零 UI 挂账）+ ACCEPTANCE（双重验收：zcode
  subagent 独立验收 PASS 后 → **串行** omp 二次验收，严禁并发——FAIL 回注
  修复批后重走）。
- 验收：定向轮 `--bundle Library` + `--bundle App` 全绿（exit 0 + 零
  MEMFAIL，SC 分账对表）；**申请全套 `--all` 批准轮**（预期 3811..3817/24/0，
  基线 3759/24/0 亲核在 plan 头）。

## 验收标准（AC 总表）

1. **OQ 生效值①（schema v5）**：两新表 + UNIQUE 索引 additive 迁移
   （fresh-create 出生面 / v4→v5 / 幂等 / 全腿 / futureSchema 拒）+
   冻结面（images 列清单等）verbatim 零变 + 封面 = position 0 单真相。
   【T1】
2. **OQ 生效值②（CRUD + 不变量）**：LightCraft op 族全量（create/group/
   stackWith/setTop/move/split/ungroup/remove/setCollapsed/setAll）+
   一图一栈 DB 级负测 + CASCADE 后余 <2 同事务解散 + modified_time stamp。
   【T2】
3. **OQ 生效值③（auto-stack）**：聚类 golden 表 + gap 边界 + runs ≥2 +
   双 skip + preview 零写 + commit collapsed 落栈 + 缺省 60s 常量。
   【T3】
4. **OQ 生效值④（分页×堆叠）**：collapsed 谓词双腿 + `.flat` 字节恒等 +
   fixup 三件套（无重复/无丢失/幂等有界）+ 全走查 union golden +
   forward-only 偏离登记。【T4/T6】
5. **OQ 生效值⑤（merge→stack 导入缝）**：merge 三 kind 检测 + stackWith
   collapsed 成栈 + 源缺 skip + 非 merge 零触 + Outcome additive 零漂移。
   【T5】
6. **UI 面**：徽章/chevron/contextMenu/AutoStackDialog（sheet 缝零
   runModal）/View 菜单节 + 13 键 xcstrings 尾块纯插入 + zh-audit 对账零
   MISSING。【T6/T7】
7. **零回归门**：`.flat` 调用点 SQL 零变化（MCP/semanticHits/filmstrip
   面原样绿）+ sidecar schema 零触 + V50Order/封存面零触 + `.metal` 零
   diff + UserDefaults 零新键 + dependencies 块零 diff + 既有
   Library/Import 测试族原样绿。【T7】
8. **SC 数字门**：LIB +45 / APP +10（计划 55，带 52..58 记账区间）定向
   对表；全套预期 **3811..3817/24/0**（批准轮对账，基线 3759/24/0 亲核
   在 plan 头）。【T8】

## 风险与边界

- **冻结计数断言浮出**：若既有测试钉 indexNames/表清单的精确计数 → 按
  additive 登记定向更新 + DECISIONS 申报（预期不浮出——数组遍历形断言
  为主，亲读 LibrarySchemaTests 后执行方确认）。
- **UNIQUE 竞态（R5）**：组栈 UX 与一图一栈约束的竞态在 store 单事务内
  消解（group = 整栈并入；createStack 先查后写 + UNIQUE 兜底）——双保险
  已在 KD-2，负测钉死。
- **导入缝匹配脆弱性**：relPath 匹配依赖导入树保持 session 相对结构
  （copy/move 模式 image_path = `Media/` + relPath；link 模式候选二式）；
  全失败 → skip 计数（安全侧）——DECISIONS 登记匹配规则为版本化细则。
- **性能**：collapsed 谓词为 NOT-IN 子查询（stack_content 规模 = 栈成员
  数，远小于 images；UNIQUE 索引使子查询为索引扫描）；展开态补拉按页有界
  ——20k 行库走查 golden 即性能冒烟。
- **APP bundle 贴线**：本批 APP 新法均为 Library 模型/命令面（无重测族）；
  IOP/IOPParity 零触碰预期零漂移。

## 提交约定

- T1 `feat(core): library schema v5 stacks tables with additive migration`
- T2 `feat(core): stack crud face with the one-image-one-stack invariant`
- T3 `feat(core): capture-time auto-stack clustering with preview`
- T4 `feat(core): stack-aware pagination predicates and membership queries`
- T5 `feat(core): auto-stack merge products at the library import seam`
- T6 `feat(app): grid stack display modes with the forward-only fixup`
- T7 `feat(app): stack badges, menus and the auto-stack dialog`
- T8 `docs(m6-4): close the stacks batch with decisions and ledger`
- 全英文 Conventional Commits；不 push。

## Checker 关注点

1. **冻结面机检**：`git diff` 上 `imagesColumns`/`albumsColumns`/
   `albumContentColumns`/`versionRefColumns`/`reservedTableNames`/
   `triggerNames` 数组必须零命中；`indexNames` 只允许一行追加。任何「顺手
   整理」列序/注释 = 违反（M2-2 冻结契约 + M4-1 先例）。
2. **`.flat` 字节恒等的验证方式**：checker 应要求执行方给出「缺省参 =
   既有调用点零改」的编译面证据（调用点清单 grep）+ 行级恒等测试（AC4②），
   而非只信「加了个 enum 参数」的口头申报——谓词拼进 WHERE 的字符串装配
   点（runPage）是唯一合法 diff 位。
3. **fixup 正确性三件套缺一不可**：无重复（displayed 集合）/无丢失（union
   golden）/幂等有界（重复 load 零增量）——checker 重点审 union golden 的
   构造是否真跨页（成员与封面分处两页的 fixture），同页 fixture 过不了关。
4. **导入缝 skip 语义**：源解析失败必须整组 skip，禁止半栈（product 独栈
   无源 = 语义垃圾）；merge kind 白名单恰好三值（focus-stack/average/
   median/sigma 排除）——逐值核对 rawValue 拼写（ProvenanceReplay :39-49）。
5. **L057/L041/E2 程序红线**：runModal grep 零命中；新测试文件 Project.swift
   + BUNDLE-MAP 同 commit 登记 + tuist generate 末位；xcstrings diff 必须
   是纯插入（历史键字节/顺序零触碰）。
6. **数字对账**：LIB 45 / APP 10 计划值逐文件核对（六新文件法数）；全套
   3811..3817 带内放行，出带 = 记账滑差申报（M6-3 minor-1 先例：申报链
   必须机械闭合）。

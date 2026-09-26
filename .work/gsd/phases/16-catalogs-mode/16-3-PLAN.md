---
phase: 16
plan: "16-3"
title: "组织树与归类：categories 树 CRUD/拖拽重排（单事务整数重排 + WITH RECURSIVE 树读 + 全树内存模型）+ collections CRUD + 图片归类（单张/批量单事务，多归属）+ 归类数据 UI 呈现（树/集合成员网格 = scopeClause 锚点消费）+ 事务性/parity 测试"
wave: 2
depends_on: ["16-1"]
autonomous: true
requirements: [CATALOG-03]
files_modified:
  - LightamerCore/Sources/Catalog/CatalogOrganizationStore.swift     # 新建：categories/collections/image_categories/image_collections 唯一写读面（单事务 CRUD/拖拽/归类）
  - App/Sources/Lightamer/Catalog/CatalogTreeModel.swift             # 新建：@Observable 全树内存模型（WITH RECURSIVE 一次读入 + 增量同步）
  - App/Sources/Lightamer/UI/SidebarView.swift                       # Catalogs 侧栏 Categories 树节 + Collections 节接线（16-2 骨架填充）+ context menu CRUD
  - App/Sources/Lightamer/Catalog/CatalogBrowserModel.swift          # categoryID/collectionID 锚点接线（16-2 T3 预留位）
  - Tests/LightamerTests/CatalogOrganizationTests.swift              # 新建：CRUD/拖拽事务性/中断 ROLLBACK/幂等/无孤儿/多归属/parity
  - Tests/LightamerTests/CatalogTreeModelTests.swift                 # 新建：树读/重排序/增量同步
  - .work/gsd/phases/16-catalogs-mode/16-3-SUMMARY.md
  - .work/gsd/phases/16-catalogs-mode/16-3-DECISIONS.md
  - TODO.md                                                         # 16-3 勾选
  - LESSONS.md                                                      # 如踩坑
---

# Plan 16-3 — 组织树与归类（W2，∥16-2）

> 背景：CATALOG-03 的字面交付（D-16-CONTEXT-4）。组织数据（categories/collections 及成员关
> 系）的**真身 = catalog 自己**——会话面根本不知道它们存在，脱库重建 = 元数据恢复 + 组织数据
> 丢失（CONTEXT specifics 必教语义；两档重建的边界在 16-4 T2 兑现）。Core 服务层（本 plan 的
> `CatalogOrganizationStore`）只依赖 16-1（schema + 查询面），与 16-2 天然正交可并行；UI 接线
> 依赖 16-2 的模式载体（侧栏节骨架/网格锚点参数），若并行执行则 T3 排在 16-2 合入后（wave 内
> 顺序由 orchestrator 按实际进度裁决，CONTEXT D-16-CONTEXT-9 Reversibility）。四条主线：① 树
> CRUD/拖拽 = 邻接表 + 受影响兄弟集 `sort_order` 整数重排（单事务，亚毫秒级——RQ-16-8）；②
> 树读 = `WITH RECURSIVE` 全树一次入内存（v1 树 ≤ 千节点级，懒加载是过度设计）；③ collections
> + 图片归类（单张/批量）= 单事务 + 多归属；④ 成员网格 = `scopeClause` 锚点消费（16-1 T3 落
> 点 d 的归类侧消费面）。

## read_first

1. `.work/gsd/phases/16-catalogs-mode/16-RESEARCH.md` §2 RQ-16-8（树存储/拖拽整数重排/全树内
   存/孤儿防御）、RQ-16-10（归类直接写 catalog 单事务——组织数据真身，无段3）、§10 16-3 草案
2. `.work/gsd/phases/16-catalogs-mode/16-CONTEXT.md` D-16-CONTEXT-4（邻接表/WITH RECURSIVE/多
   对多/单事务/批量复用 12 批量面语义）、specifics 节「组织数据真身 = catalog 自己」教学义务、
   验证红线节（树编辑事务性三条）
3. 16-1 产物：`LightamerCore/Sources/Catalog/CatalogIndexSchema.swift`（categories/collections/
   image_categories/image_collections DDL——`parent_id` 无外键纪律）、`CatalogIndexStore.swift`
   （`scopeClause` categoryID/collectionID 锚点 + `imageID(for:)` 批量 id 查询）、
   `FilterSQL.swift`（scopeClause 定义——本 plan 消费不修改）
4. `LightamerCore/Sources/Session/SessionIndexStore.swift`：`claimMetadataApply` 单事务循环
   （:1177——批量写事务形态蓝本）+ 头部 one-bulk-one-transaction 纪律（:22-24 注释；checker M4 微漂校正）
5. Phase 12 批量面语义正本：`.work/gsd/phases/12-metadata-presets-lut/12-CONTEXT.md` 三段语义
   （段1 内存变换 / 段2 索引单事务 / 段3 sidecar 队列）——归类 = **无段3**（组织数据真身 =
   catalog，段2 即终态；code_context 节已钉）
6. 16-2 产物（UI 接线依赖）：`App/Sources/Lightamer/Catalog/CatalogBrowserModel.swift`（锚点
   参数位）、`App/Sources/Lightamer/UI/SidebarView.swift`（Categories/Collections 节骨架）
7. `LESSONS.md` L009/L010（中断注入红线）/ L013 / L020（内容级断言）/ L031（缝 a：树查询
   SQL 收口本 store，UI 零裸 SQL）+ `AGENTS.md`（Phase 执行模型）+ `.work/GOAL-STATE.md`

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 本任务申报文件）；`caffeinate -dis` 包裹一切
  构建（`xcodebuild build-for-testing` 先行）。
- **单测命令** = `Scripts/test-direct.sh '<Class>'`；判据 = Executed 计数行 + failures 行，
  Executed 0 = 判据失败。
- **每任务边界检查 `.work/config.toml [gsd]` 开关**——commit 后、下一任务前。
- **不 push**；**构建勿加 `-derivedDataPath`**；**新文件后跑 `tuist generate`**（11-03）。
- **回归基线 = 16-1 收尾轮计数**（+16-2 若已合入；读最新 SUMMARY 终值；0 fail）；每任务全套
  suite 绿。`LayerE2ERoundTripTests` flake 若现，隔离 ×3 归因单列。
- **T3 为 GUI 任务：需解锁控制台（Manual-Only 候补）**。
- **树编辑事务红线**（验证正本，执行期不得放宽）：树编辑（CRUD/拖拽/移动子树）全部单事务；
  中断 = ROLLBACK 全量回退；CRUD 幂等；**孤儿 category（parent 失效）不可达构造**——`parent_id`
  不声明外键（16-1 DDL 纪律），防御在写面（删除父强制先处置子树——UI 禁直接删非空父 + store
  校验 parent 存在性）。
- **批量归类红线**：万张级操作零像素渲染（PERF-07 语义跨域延续）；one bulk change = one
  transaction；归类写面 = `CatalogOrganizationStore` 唯一入口（缝 a 同源：一切 SQL 收口
  Core Catalog 面经 FilterSQL 产物/DDL，UI 零 SQL 字符串）。
- **多归属语义**：一图可属多分类多集合（`image_categories`/`image_collections` 多对多无上限）；
  重复归类幂等（PK 冲突 `INSERT OR IGNORE`）。
- RESEARCH/CONTEXT 未覆盖细节（树拖拽自动展开语义、重名分类/集合策略、sort_order 初值间隔）
  标注**执行期决策**入 `16-3-DECISIONS.md`，不臆造。

## Tasks

### T1 CatalogOrganizationStore：categories CRUD + 拖拽重排 + 树读

- **action**
  1. 新建 `LightamerCore/Sources/Catalog/CatalogOrganizationStore.swift`（actor，handle
     confinement；打开 = 复用 16-1 `CatalogIndexStore` 的库路径/handle 约定——同一 `.lcat` 单
     写者，串行化经 actor）。
  2. **categories CRUD**（单事务各一）：create（parent 可空 + `sort_order` 尾追）/ rename /
     move（改 parent——**环检测**：目标不得是自身或自身子树，WITH RECURSIVE 子树集校验）/
     delete（**仅叶子可删**——非空父拒绝 typed error，UI 强制先处置子树）；幂等：重复 rename
     / delete 已删项 typed no-op 或 error（DECISIONS 定）。
  3. **拖拽重排**：受影响兄弟集 `sort_order` 整数重排（0..n-1 重编号，单事务逐行 UPDATE；兄弟
     集 <100 行亚毫秒——RQ-16-8）；跨父拖拽 = move + 两兄弟集重排同事务。
  4. **树读**：`readTree()` = `WITH RECURSIVE` 全树一次读入（探针 0.05ms@3 层量级）→ 返回
     `CatalogTreeNode` 值型数组（id/parent/name/sortOrder/children 已组树）；`subtree(of:)` =
     WITH RECURSIVE 子树集（环检测与移动校验复用）。
  5. **collections CRUD**：create/rename/delete（集合删除 = 平表删 + 成员关联级联删，单事务）/
     重排（同款整数重排）。
- **证据**：`CatalogOrganizationTests`——CRUD 基本流 + 环检测拒绝（self/子树两态）+ 非空父删
  除拒绝 + 删除后树读一致 + 幂等断言 + 兄弟集重排后序精确（0..n-1 无洞，L020）。

### T2 图片归类：单张 + 批量（多归属，单事务）

- **action**
  1. **归类写面**（同 store）：`assign(images:toCategory:)` / `assign(images:toCollection:)`——
     `imageID(for:)` 批量解析 `(session_id, rel_path)` → 显式 `id`（16-1 稳定内部键）→
     `INSERT OR IGNORE INTO image_categories/image_collections`（多归属 + 幂等）单事务；
     `revoke(images:fromCategory:...)` 同构 DELETE。
  2. **批量形态**（万张）：段1 内存变换（解析+去重）→ 段2 catalog 单事务批量 INSERT（prepared
     循环，claimMetadataApply :1177 形态）——**无段3**（组织数据真身 = catalog；PERF-07 零像
     素渲染断言：归类后 `thumb_state`/缩略图管线零触发——探针断言）。
  3. **COUNT memo 失效**：归类写事务 COMMIT 后调 `CatalogIndexStore.invalidateCounts()`（16-1
     钩子——角标追平）。
  4. **投影交互边界**：归类引用的 catalog_image_id 行被投影 UPSERT 时**保留 id**（16-1 T2 ⑥
     已钉）→ 成员关系存活；行被键集对账删除时成员关联随行删（16-1 ②腿级联）——两态各写一条
     断言（与 16-1 测试互补，本 plan 侧重组织数据视角）。
- **证据**：`CatalogOrganizationTests` 扩段——批量万张归类耗时（≤5s 量级，入 perf.md 附注）+
  零像素渲染探针 + 多归属（一图三分类两集合同事务）+ 重复归类幂等 + 投影 UPSERT 后成员存活 /
  对账删除后关联随之消失 + memo 失效断言。

### T3 树/集合 UI 呈现（GUI，依赖 16-2 载体合入）

- **action**
  1. 新建 `App/Sources/Lightamer/Catalog/CatalogTreeModel.swift`（@Observable）：启动/变更后
     `readTree()` 全树入内存；store 变更回调增量刷新（编辑后局部重读该父链——全树重读亦可达
     千节点级零感知，DECISIONS 定粒度）。
  2. `SidebarView.swift`：Categories 节 = 大纲树（DisclosureGroup/OutlineGroup 既有形态）+
     context menu（新建子分类/重命名/移动/删除——非空父删除禁用 + tooltip）+ 拖拽重排（
     `.onDrop/.onMove` 受兄弟集重排语义）；Collections 节 = 平列表 + context menu CRUD。
  3. `CatalogBrowserModel.swift`：categoryID/collectionID 锚点接线（16-2 T3 预留参数位）——
     树/集合点选 → `scopeClause` 锚点 → 成员网格；面包屑/清锚点交互。
  4. 归类入口：网格多选 context menu「添加到分类…/添加到集合…/从分类移除」（单张同款）→
     T2 store 调用（跨会话多选天然支持——组织数据真身在 catalog 不分会话）。
  5. zh/en 同批（L025）。
- **证据**：`CatalogTreeModelTests`（树读/重排/增量同步模型级）+ GUI 走查记录（建树三层/拖拽
  重排视觉即時/成员网格过滤/多选归类/删除保护）+ Manual-Only 未尽项登记 + zh 首屏 smoke。

### T4 事务性专项（中断 ROLLBACK / 幂等 / 无孤儿）

- **action**
  1. **中断注入**（L010 红线模式）：拖拽重排事务中注入抛错（测试 seam）→ ROLLBACK → 树读 =
     前态逐字节（sort_order 全集不变）；批量归类事务中断 → 成员关联零半提交。
  2. **无孤儿构造证明**：穷举写面路径（delete/move/create）断言任意序列后 `parent_id` 全部指
     向存活节点（含环检测拒绝路径）；`PRAGMA foreign_key_check` 式自查查询（无外键声明——
     store 级等价校验函数）随测试跑。
  3. **并发冒烟**：树编辑事务与网格读并发（WAL 读写不互斥——R4 结论跨用：单会话单写者纪律下
     读写隔离冒烟）。
- **证据**：`CatalogOrganizationTests` 专项段全绿；中断后库文件 reopen 一致性断言。

### T5 回归收尾 + SUMMARY + DECISIONS

- **action**：全 suite 终轮（最新基线 + 本 plan 新增，0 fail）；zh/en 键数断言；缝 a grep 自证
  （App/Catalog 树 UI 零 SQL）；TODO.md 勾选；`16-3-SUMMARY.md`（任务表/commit 表/证据/万张
  归类数字）；`16-3-DECISIONS.md`（重名策略、sort_order 间隔、增量刷新粒度、幂等语义、其余执
  行期决策）；Manual-Only 汇总；新教训候选评估。
- **证据**：测试计数（0 fail）；SUMMARY + DECISIONS 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| 树 CRUD/拖拽 | 环检测/非空父保护/重排序精确/幂等 | `Scripts/test-direct.sh 'CatalogOrganizationTests'` |
| 归类 | 批量单事务 + 多归属 + 零像素渲染 + memo 失效 | `Scripts/test-direct.sh 'CatalogOrganizationTests'` |
| 事务性 | 中断 ROLLBACK + 无孤儿穷举 + 并发冒烟 | `Scripts/test-direct.sh 'CatalogOrganizationTests'`（专项段） |
| 树模型/UI | 全树内存 + 增量同步 + 成员网格锚点 | `Scripts/test-direct.sh 'CatalogTreeModelTests'` + GUI 走查 |
| 回归 | 全 suite 0 fail（最新基线+新增）+ L025 | `caffeinate -dis Scripts/test-direct.sh`（全套） |

## 验收标准（Acceptance）

- [ ] categories：邻接表 CRUD + 拖拽/跨父移动（整数重排单事务 + 环检测拒绝）+ 非空父删除禁止
      + WITH RECURSIVE 树读/子树 + 全树内存模型增量同步
- [ ] collections：CRUD + 平表重排 + 删除级联成员（单事务）
- [ ] 归类：单张/批量（万张 ≤5s 量级入 perf.md 附注）多归属 + `INSERT OR IGNORE` 幂等 + 零像
      素渲染断言 + COUNT memo 失效 + 投影 UPSERT 保 id 成员存活 / 对账删除关联随行
- [ ] 事务性：中断 ROLLBACK 全量回退（重排 + 归类两态）+ 无孤儿穷举证明 + CRUD 幂等 + 并发读
      写冒烟
- [ ] UI：侧栏树/集合节完整（context menu CRUD/拖拽/删除保护）+ 成员网格锚点过滤 + 多选归类入
      口 + zh/en
- [ ] 组织数据真身教学：SUMMARY 显式一节（元数据可重建 / 组织数据不可从会话面重建——16-4 文
      案与两档重建的语义前置）
- [ ] 全 suite 0 fail；每任务独立提交 + 边界查开关；不 push；SUMMARY + DECISIONS 落盘；
      Manual-Only 登记

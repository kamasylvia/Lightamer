# Plan 16-3 — 组织树与归类（W2）执行 SUMMARY

**完成:** 2026-09-27（ZCode executor subagent worker，wave 2；基线 = 16-2 收尾轮 1504/9skip/0fail）
**Commits:** T1 `e275e07` → T2 `0cc79f1` → T3 `10d0763` → T4 `5f8f90e` → T5 收尾（本批）；未 push；每任务边界查 `.work/config.toml [gsd]`（auto=true/paused=false ×5）

## 任务表

| 任务 | 交付 | Commit | 测试证据 |
|---|---|---|---|
| T1 | `CatalogOrganizationStore`（Core Catalog 面）：categories 邻接表 CRUD（尾追 sort_order）+ move 单事务环检测（self/子树两态，WITH RECURSIVE subtree + UNION 防腐环终止）+ 双兄弟集整数重排 0..n-1 无洞 + 仅叶子删除（非空父 typed 拒绝）+ 删除级联成员 + `readTree()`/`subtreeIDs` WITH RECURSIVE 树读（孤儿天然排除）+ collections CRUD/平表重排/删除级联 + countsInvalidator 钩子 + 注入 seam（T4 用）；SQLiteHandle 增 `lastInsertRowID()`（缝 c 唯一 `sqlite3_*` 位不变） | `e275e07` | CatalogOrganizationTests 22/0 |
| T2 | 归类写面：`assign/revoke` × category/collection——段1 内存解析（per-session prepared 循环 + 去重 + 未解析 skipped 计数）→ 段2 单事务 prepared `INSERT OR IGNORE` 循环（claimMetadataApply 形态）→ COMMIT 后 memo 失效钩子；多归属 + 幂等；**投影对账删除腿补级联**（16-1 缺口：只级联 image_tags，组织关联两表随行删漏——本 plan 组织数据视角抓住，真缺陷修复入本 commit）；投影 UPSERT 保 id ↔ 成员存活 / 对账删 ↔ 关联随行，两态断言 | `0cc79f1` | +8（累计 30）/0 |
| T3 | `CatalogTreeModel`（App @Observable）：全树 + collections 内存模型，变更后全树重读（增量粒度决策）；拖拽 before-target 语义（含同父去位 index 调整 + 自包子树拒绝）+ 归类 identity 字符串拆分面；`sharedCatalogOrganization` 单例入 SessionIndexController（repoint 重建 + memo 钩子装配 = 16-1 移交的生产 wiring 补全位）；SidebarView Categories 节（常展开缩进树行 + 点选 = categoryID 锚点 + context menu 新建子分类/重命名/移动到（深度缩进平铺）/删除（非空禁用 + hint）+ draggable/dropDestination）+ Collections 节同款平表 + 一个 alert 承四 name 流；CatalogBrowserView 网格菜单「添加到分类…/添加到集合…/从此分类移除」；zh/en 14 键同批 | `10d0763` | CatalogTreeModelTests 8/0 + 相邻全绿 |
| T4 | 事务性专项：注入 `afterSiblingRewrites` → ROLLBACK 后树**逐字节**等于前态（live 句柄 + reopen 双证）+ 跨父移动注入（parent_id flip 同滚）+ 归类注入（`beforeAssignCommit`）零半提交 + reopen 零 ghost；无孤儿穷举 = 确定性 LCG 120 步 CRUD gauntlet 每步断言 parent_id 全指存活节点（store 级 foreign_key_check 等价——DDL 无外键纪律的写面自查）+ 终态 walk 树节点数 == 全表行数 + 成员孤儿变体（行删关联随行）；并发冒烟 = 写者搅动兄弟序 × 树读 × keyset 网格页三方并发（WAL R4 跨用）零错误终态无洞 | `5f8f90e` | +6（累计 36）/0 |
| T5 | 全套终轮 + 缝 a/b/c grep 自证 + SUMMARY/DECISIONS/TODO/PROGRESS + perf.md 附注 | 本批 | 见下 |

## 回归口径（T5）

- **基线 1504/9skip/0fail（16-2 收尾）→ 终轮 1548/9skip/0fail（438.0s，EXIT=0）** = 基线 1504 + 新增 44 零失败（CatalogOrganizationTests 22→36 + CatalogTreeModelTests 8）+ 16-2 遗留零回归。本轮零 flake（无负载敏感型挂单；LayerE2ERoundTripTests 未现）。
- 类级轮次：CatalogOrganizationTests 36 / CatalogTreeModelTests 8 / CatalogProjectorTests 12 / CatalogIndexSchemaTests 15 / CatalogFilterSQLTests 15 / CatalogSmartAlbumDomainTests 4 / CatalogBrowserModelTests 8 / CatalogModeIsolationTests 7 / PanelWiringTests 71（L025 键族全量断言含本批 14 新键）——全绿。

## 万张归类数字（PERF-07 语义延续 + perf.md 附注）

- **10k 批量归类（段2 单事务 INSERT OR IGNORE × 10000）：0.027s**（预算 ≤5s，余量 ~185×；Debug 直启口径，机器本地 /tmp）。
- **零像素渲染断言**：归类 API 签名只承载 identity 对 + 目标 id（零图像数据进出）；调用后 fixture 目录零会话侧产物（探针断言）；catalog 不镜像 thumb 列（16-1 定案）——归类路径从代码事实到探针三层零像素。数字已附注 `perf.md`。

## 组织数据真身 = catalog 自己（CONTEXT specifics 教学义务，SUMMARY 显式节）

- **元数据镜像可重建**：catalog_images 的 31 列随 sidecar→lindex→catalog 两级派生链可全量重投影，脱库重建（对账式）后行集追平。
- **组织数据不可从会话面重建**：categories 树 / collections / image_categories / image_collections 的成员关系**只存在于 catalog**——会话面（sidecar/lindex/扫描器/MetadataService）根本不知道它们存在。`.lcat` 文件级丢失 = 组织数据丢失（破坏式重建档），唯一恢复源 = `.lcat` 文件备份（RQ-16-15 单文件兜底）。
- **但组织数据不是「可牺牲数据」**：16-1 R1 的 UPSERT-保-id 使对账式重建（行集修复档）下成员关系**零损失**；本 plan T2 补的对账删除级联保证「行没了关联才没」——组织数据的生命周期严格跟随用户显式动作（删分类/删集合/移除会话），永不因重建漂移。**16-4 T2 脱库重建文案与两档重建语义的前置即此**：对账档提示「目录已对账」，破坏式档提示「元数据已恢复；分类与集合需从备份恢复或重新整理」——不得暗示组织数据脱库无损。

## 缝 a/b/c grep 自证（收尾轮）

```
$ grep -rn "SELECT\|WHERE" App/Sources/Lightamer/Catalog/        → 零命中
$ grep -rln "CREATE TABLE\|CREATE INDEX\|PRAGMA" App/Sources/Lightamer/ → 零命中（缝 b App 面）
$ grep -rln "sqlite3_[a-z_]*(" App/Sources/Lightamer/            → 零命中（缝 c；Core 侧仍仅 SQLiteHandle.swift——SQLiteHandle.lastInsertRowID 增补在其内）
```

Core 侧：CatalogOrganizationStore 31 处 SELECT/WHERE 全部为 Core Catalog 面常量 SQL（缝 a 收口；业务层零裸 SQL 延续）。CatalogProjector 增补两行 DELETE（对账级联）同缝。

## Manual-Only 台账（交互走查未竟项，验收轮承接）

| # | 项 | 原因 |
|---|---|---|
| MO-16-3-1 | 侧栏建树走查（根→子→孙三层；context menu 新建/重命名；非空父删除禁用态 + hint 文案可见） | 需人工点按走查 |
| MO-16-3-2 | 拖拽重排视觉即时性（同父拖拽 + 跨父拖入集合行 + 拖入自身子树被拒）与 collections 平表拖拽 | 需人工拖拽操作 |
| MO-16-3-3 | 树/集合点选 → 成员网格锚点过滤往返 + 面包屑清锚点 + 网格多选「添加到分类/集合」+ zh 首屏 smoke | 需真实 RAW 会话库 + 人工点按 |

## 偏离/决策

14 条入 `16-3-DECISIONS.md`。要点：**D2** 投影对账删除补组织关联级联（16-1 缺口修复，非本 plan 申报文件但为 T2 验收标准「对账删除关联随行」的必要条件）；**D4** UI 树 = 常展开平铺缩进行（ForEach+children 初始化器在此 SDK 组合不可用，折叠态 additive）；**D5** move-to 菜单 = 深度缩进平铺列表（v1 无递归子菜单）；**D10** 每任务回归 = 类级 + 相邻 Catalog 面，全套在 T5 收尾轮兜底（每任务全套 ×5 ≈ 40 分钟的日历成本 > 风险，收尾轮 0 fail 背书）。

## 遗留

- 无阻塞。Manual-Only 三行（上表）待验收轮交互走查。
- 16-4 输入就绪：对账式重建的组织数据零损失语义已有测试背书（UPSERT 保 id + 对账级联）；破坏式重建文案语义前置见本文「组织数据真身」节。

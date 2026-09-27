---
phase: 16
slug: catalogs-mode
status: validated
nyquist_compliant: true
created: 2026-09-27
validated: 2026-09-27
---

# Phase 16 — Validation（签核：SC#1-5 三列证据 + Per-Task Map + Manual-Only 汇总）

> 体例对齐 12-VALIDATION（frontmatter / Checklist）。**翻账只认证据**：SC 表逐条
> 「一手证据 + 测试锚 + 实证」三列；无证据 ✅ = 违规。
> **CATALOG-05 解释面（RQ-16-15 晨审追认项）**：字面「可由会话面全量重建」的精确边界 =
> 重建的是**元数据投影**（research 修正②两档化）——对账式（文件在、行漂移：id 保持 +
> 组织数据存活）/ 破坏式（文件丢失/schemaFailed：元数据恢复 + 组织数据丢失，唯一恢复源
> = `.lcat` 文件备份）；组织树/集合成员关系不可从会话面重建（会话面不知道它们存在）。
> 两档措辞已落 REQUIREMENTS CATALOG-05 解释面与本表 SC#1/SC#2 证据列，不改需求字面。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit / golden / 直启宿主 / 1M 行基准 harness） |
| **Quick run** | `Scripts/test-direct.sh`（L019b 直启，零弹窗；判据 = Executed 行非宿主退出态） |
| **Full suite（终轮）** | `caffeinate -dis Scripts/test-direct.sh` = **1553 tests / 9 skip / 0 fail**（434.9s，2026-09-27 12:1x，EXIT=0） |
| **基线演变** | Phase 12 末 1437 → 16-1（920→harness skip 计入；口径 1482/16-2 收尾）→ 16-2 +22（**1504**）→ 16-3 +44（**1548**）→ 16-4 +5（**1553**：CatalogRebuildTests） |
| **SC#3 基准 harness** | `LA_CATALOG_BENCH=1` 手动跑（禁 CI——机器差异），Debug×3 + Release×3 三轮对账；Release 主判据 |
| **负载型 flake（LayerE2ERoundTripTests）** | 本 Phase 全部终轮 0 fail 未现身；在案预案未触发 |

---

## SC#1-5 对照表（ROADMAP §Phase 16 契约，三列证据）

| SC | 判据 | 一手证据（文件/决策） | 测试锚（类/用例） | 实证（数字/走查） | 判定 |
|---|---|---|---|---|---|
| **SC#1** | 双模式共存：Sessions 恒默认零依赖；Catalogs 设置中启用；脱库降级零功能损失 | 启用守卫在 `CatalogProjector.project` 句柄之前（守卫假连文件都不创建，16-1-DECISIONS D2）+ 冷启动恒 Sessions 常量（`CatalogPreferencesModel.coldStartRawValue`）+ **两档重建**（`CatalogRebuilder`：对账式保 id 组织存活 / 破坏式换名晋升组织数据丢——本 plan T2）+ schemaFailed 禁用态（`probeSchemaState` + Settings 重建按钮） | `CatalogModeIsolationTests` 7（enable 守卫驱动/位置重指/冷启动常量/**Sessions 全流程零句柄**）+ `CatalogRebuildTests` 5（对账保 id/**破坏式组织空表诚实边界**/**v99 typed 拒绝 + Sessions 零波及 + 修复**） | 破坏式晋升原子性（注入 afterBackupMove 失败 → 原文件字节全等回退）+ `.bak` 一代备份持有旧组织数据；Sessions 全流程零 `.lcat` 句柄（真 scanner openAndSync） | ✅ |
| **SC#2** | 本地 SQLite 单向投影 + catalogs 组织树（C1 语义）+ 虚拟集合；可全量重建；**标签物化表**支撑百万级层级关键字查询 | `CatalogIndexSchema`（七表冻结 DDL + schemaVersion=1 v99 拒开 + pragmas 集中）+ `CatalogProjector`（水位增量 + 键集对账闭删除 + UPSERT 保 id + tags 前缀展开物化）+ `CatalogOrganizationStore`（树 CRUD/拖拽/归类）+ `CatalogRebuilder`（两档全量重建）+ FilterSQL catalog 域 EXISTS 分派（`A\|B\|C`→5 行 golden） | `CatalogIndexSchemaTests` 15 + `CatalogProjectorTests` 12（parity 29 列逐列/对账三腿/标签 golden 五形态）+ `CatalogFilterSQLTests` 15 + `CatalogOrganizationTests` 36 + `CatalogTreeModelTests` 8 + `CatalogRebuildTests`（重建两路产物 parity） | 投影吞吐 full100k **1.461-1.472s**（Release，预算 30s 余量 ~20×）；tag 等值分页 0.18-0.34ms@1M/2.6M tags（PK seek）；10k 批量归类 0.027s 零像素 | ✅ |
| **SC#3** | **基准门（最终实证裁决）**：1M 行参考库 + 真实查询集，网格分页 p95 < 50ms（SQLite 口径实测） | harness = `CatalogBenchmarkHarness`（RQ-16-13 全矩阵 8×4×3×30 页 + COUNT 面 + 投影三场景）；perf.md §A 终账 + **§A.6 裁决行**；fixture = 16-1 验收修正后形状（2.6M tags，`5cc4d8c`） | harness 三轮对账（Debug×3 + Release×3，真机落盘 `/tmp` L009）；`+` 前缀形状对照列 + EXPLAIN 零 TEMP B-TREE 常驻断言（T3/T4 suite） | **PASS：96/96 形状 Release 热 p95 最差 12.28ms**（门余量 >4×；三轮 11.53/12.28/11.87 稳定；Debug 最差 13.20 同判）；COUNT 现算 60-74ms + combo memo 0.01ms + tagSweep 64ms@2.6M；无超门无 BLOCKER 无调门 | ✅ |
| **SC#4** | catalogs 组织树编辑（CRUD/拖拽）+ 图片归类含批量 | `CatalogOrganizationStore`（邻接表 CRUD + 环检测双态 + 兄弟集整数重排 0..n-1 + 仅叶子删除 + WITH RECURSIVE 树读 + collections 平表）+ `CatalogTreeModel`（before-target 拖拽 + flatRows 平铺树 D-16-3-D4）+ SidebarView Categories/Collections 节 + 网格归类菜单 | `CatalogOrganizationTests` 36（注入 ROLLBACK 逐字节回退 + LCG 120 步无孤儿 gauntlet + 并发三方冒烟）+ `CatalogTreeModelTests` 8 | 10k 批量归类 **0.027s**（≤5s 预算余量 ~185×，perf.md §B.2）+ 零像素三层断言 + 多归属/幂等/skipped 记账 | ✅ |
| **SC#5** | Catalogs 模式下跨会话浏览/过滤/智能相册（复用 Phase 12 谓词层，求值域扩全库） | FilterSQL 第三参 domain 分派（keywords EXISTS + orderBySQL domain + scopeClause 三锚点，**单一翻译面零第二翻译函数**）+ `CatalogIndexStore`（keyset 两段式 + COUNT memo 键=whereClause）+ `CatalogBrowserModel`/`CatalogFilterBarView`（12-2 filter bar 全套复用）+ SmartAlbums 域随模式（规则资产零迁移） | `CatalogFilterSQLTests` 15（catalog 域快照 + session 域逐字节回归锁）+ `CatalogSmartAlbumDomainTests` 4 + `CatalogBrowserModelTests` 8（10k 六形状 drain==one-shot 无重无漏）+ `CatalogThumbnailRouterTests` 3 | 跨会话 keyset 分页 p95 0.12-0.15ms（filename）/1M 行实测全套 §A.2 表；规则文件字节不变 + schemaVersion 1 钉测 | ✅ |

---

## 缺陷处置记录（Phase 16 执行期发现 → 闭环）

| 缺陷 | 发现 | 处置 | 证据 |
|---|---|---|---|
| tags per-image DELETE 无反向索引 → 投影 N²（148s/10 万行） | 16-1 首跑 | **16-1 修复**：`idx_tags_image ON image_tags(catalog_image_id)` DDL（research F11 只测查询方向的盲点） | 修复后 Release full100k 1.926s→终测 1.461-1.472s；`CatalogIndexSchemaTests` 冻结断言 |
| 投影对账删除腿漏组织关联级联（只级联 tags） | 16-3 T2 | **16-3 修复**（D2）：补 image_categories/image_collections 两条 prepared DELETE | `CatalogOrganizationTests` 成员孤儿 gauntlet（16-3 验收轮 GLOB 修复后为真断言） |
| 16-1 fixture 物化候选表漏独立 token（1.6M vs 真形 2.6M） | 16-1 验收轮 | **16-1 验收修复 `5cc4d8c`**；本 plan T1 以修正后 fixture 复跑落新账（tags=2,600,000 三轮恒定 ✓） | perf.md §A.1 + §A.5 对账列 |
| CatalogOrganizationTests 两处 await-in-autoclosure 全量重编编译失败 | 16-4 T2 构建轮 | **16-4 构建修复**：await 提升为局部变量（同断言；增量编译从未重编该文件所致，非产品缺陷） | 全套终轮 1553/0 fail；16-4-DECISIONS D8 |
| Release 混合代际产物（TEST BUILD FAILED 被管道吞码掩盖）→ 测试束 dlopen 符号错配 | 16-4 T1 构建轮 | **流程修复**：清该配置产物目录全量重编 + 构建判据改读 SUCCEEDED 行；LESSONS 候选 | 16-4-DECISIONS D2 |

**16-4 执行期无未闭环产品缺陷。**

---

## 三缝终审计（L031 / 16-4 T3，全仓 grep 三连）

```
缝 a（SQL 生成）：grep -rn "SELECT\|WHERE" LightamerCore/Sources/Catalog/ App/Sources/Lightamer/Catalog/
  → Core Catalog 面 5 文件（Schema 2 / Store 10 / OrgStore 29 / Projector 25 / Rebuilder 3——
    全部为申报面常量 SQL；Rebuilder 3 处 = registry 读×2 + COUNT 校验）；App Catalog 零命中。
  App 全域命中仅英文注释（AIMaskEditing "SELECTED" 等），零裸 SQL。
缝 b（DDL/PRAGMA）：grep -rln "CREATE TABLE\|CREATE INDEX\|PRAGMA" LightamerCore/Sources App/Sources
  → SessionIndexSchema / CatalogIndexSchema 两申报文件 + SessionIndexStore 三处 PRAGMA
    （16-1 期既有只读验证面，前序验收已注记）+ SQLiteHandle 两处注释文本。
    16-4 新增 checkpointTruncate 已收进 CatalogIndexSchema（16-4-DECISIONS D4）。
缝 c（C API）：grep -rln "sqlite3_[a-z_]*(" LightamerCore/Sources App/Sources
  → 仅 SQLiteHandle.swift。`import SQLite3` 于 Tests 6 文件 = fixture 直连句柄（16-1 申报
    先例，harness/隔离套同款）；Sources/App 无第二 import。
```

**结论：三缝全过，命中越界 = 零，签核无阻。**

---

## 文档账复核（16-4 T3③）

| 项 | 状态 |
|---|---|
| PROJECT.md:65 约束节（「PostgreSQL 后端」漂移） | ✅ 已修（`458f207`，discuss/research 环完成；现文 = 2026-09-27 修订版两模式约束） |
| ROADMAP Phase Overview counts + §Phase 16 | ✅ 已修（`685d18d`：`16 — Catalogs Mode \| 6` 在册） |
| REQUIREMENTS Traceability CATALOG 行 | ✅ 本批翻账 Delivered ×5（06 Pending 留 v2） |
| 残余漂移清单 | 无（回 orchestrator 事项 = 零） |

zh/en 终核：`CatalogModeIsolationTests.testCatalogKeysL025EnZhComplete` 终轮绿——
settings_catalogs_/organization_mode_/catalog_ 键族（含 16-4 新增 16 键）en+zh 双面
translated 非空；xcstrings 总键 1002。GUI 首屏 smoke 挂 Manual-Only 承接（MO-16-2-2）。

---

## Manual-Only 汇总（交互走查未竟项，8 行——验收轮承接）

| # | 项 | 原因 |
|---|---|---|
| MO-16-2-1 | 设置面板交互走查（开关开合联动切换器出现/消失；NSOpenPanel 位置更改→新路径空库） | 需人工面板操作 |
| MO-16-2-2 | 切换器点按往返 + 五节视觉序 + 空态文案 + zh 首屏 smoke | 需人工点按走查 |
| MO-16-2-3 | 跨会话网格渲染走查（真实多会话库缩略图/点开编辑/返回刷新/stale 再生/离线灰显） | 需真实 RAW 会话库 |
| MO-16-2-4 | 会话管理全流程（移除 confirm→行集消失；re-link 选新目录→行恢复） | 需人工面板操作 |
| MO-16-2-5 | 批量多选跨两会话评分/flag/色标 + filter bar chips/Quick Filter/排序手感 | 需人工点按走查 |
| MO-16-3-1 | 侧栏建树走查（三层树/context menu CRUD/非空父删除禁用态 + hint） | 需人工点按走查 |
| MO-16-3-2 | 拖拽重排视觉即时性（同父/跨父/自子树拒 + collections 平表拖拽） | 需人工拖拽操作 |
| MO-16-3-3 | 树/集合点选锚点过滤往返 + 网格多选归类 + zh smoke | 需真实 RAW 会话库 |

（16-4 新增 UI 面——重建按钮/进度浮层/完成 alert/confirm dialog——逻辑面由
CatalogRebuildTests 5 测 + 隔离套钉死；GUI 交互走查并入 MO-16-2-1 承接。）

---

## CATALOG-01..06 × plan 覆盖矩阵

| 需求 | 16-1（底座） | 16-2（双模式 UI） | 16-3（组织树归类） | 16-4（收口） | 状态 |
|---|---|---|---|---|---|
| CATALOG-01 双模式架构 | 守卫/零句柄隔离 | 设置开关+切换器+冷启动恒 Sessions | — | schemaFailed 禁用态（ Sessions 零波及终验） | Delivered |
| CATALOG-02 目录库后端+标签物化 | 七表 DDL+投影+keyset+COUNT memo | FilterSQL domain 分派 | 组织读写面 | **SC#3 硬门 PASS** + 两档重建 | Delivered |
| CATALOG-03 组织树编辑归类 | — | — | CRUD/拖拽/归类/批量 + 事务性专项 | 重建后组织数据存活/丢失两态断言 | Delivered |
| CATALOG-04 跨会话浏览过滤智能相册 | 查询面 | 浏览/过滤/SmartAlbums/缩略图路由 | 锚点过滤消费 | 隔离终验 | Delivered |
| CATALOG-05 脱库降级 | 投影 parity（可重建面） | 位置重指建空库 | 对账级联（关联随行） | **两档重建专项 + 损坏处置 + Sessions 零波及** | Delivered |
| CATALOG-06 远程后端评估 | — | — | — | — | **v2 预留（不翻账）** |

---

## Per-Task Map（16-1..16-4）

| Task | Plan | 交付 | commit | Status |
|---|---|---|---|---|
| 16-1 T1-T5 | 底座 | 七表 DDL + 投影（键集对账/保 id/tags 物化）+ keyset 查询面 + FilterSQL 分派 + harness + 1M 首跑 | `0cc79f1` 前序波（16-1 SUMMARY 申报） | ✅ |
| 16-1 验收修复 | 底座 | fixture 物化候选表修正（2.6M 真形） | `5cc4d8c` | ✅ |
| 16-2 T1-T7 | 双模式 UI | 设置/切换器/五节/filter bar 分派/SmartAlbums 域/缩略图路由/编辑回环+sweep | `dcc97ca`..`13da53e`/T7 收尾 | ✅ |
| 16-3 T1-T5 | 组织树归类 | OrgStore/归类写面+对账级联修复/树集合 UI/事务性专项 | `e275e07`/`0cc79f1`/`10d0763`/`5f8f90e`/T5 | ✅ |
| 16-3 验收修复 | 组织树归类 | 孤儿 gauntlet 恒真断言修复（LIKE→GLOB） | `19799f5` | ✅ |
| 16-4 T1 | 收口 | SC#3 终测三轮对账 + perf.md §A 终账 + 裁决行 PASS + harness Release 注记 | `b744770` | ✅ |
| 16-4 T2 | 收口 | CatalogRebuilder 两档 + 损坏处置 + 设置/网格绑定 + CatalogRebuildTests 5 + zh/en 16 键 | `f7a8037` | ✅ |
| 16-4 T3/T4 | 收口 | 三缝终审计 + 文档账复核 + 终轮 1553/0 + VALIDATION + 翻账（本文件） | 本提交 | ✅ |

---

## 签核

- SC#1-5 全项 ✅（三列证据齐；SC#3 = 实证 PASS 数字前置）。
- `status: validated` + `nyquist_compliant: true`（T1 硬门 PASS 且 T2/T3 全绿后填写）。
- 翻账：REQUIREMENTS CATALOG-01..05 → Delivered（06 留 v2 预留）；GOAL-STATE Phase 16
  收口 + 续接点；TODO.md 收口勾选。**C 档第 3 停 = 夜间授权先例
  （D-07-3-T5-1 / D-09-05-T1-1 / 11-05 D1）翻账，晨审可推翻。**
- Manual-Only 8 行挂验收轮；Phase 16 verify-work 终验待用户。

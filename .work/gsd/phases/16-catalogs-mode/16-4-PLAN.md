---
phase: 16
plan: "16-4"
title: "收口：SC#3 基准终测（真机落盘 .lcat 全查询集矩阵 p95<50ms 实证裁决落账）+ 脱库重建专项（对账式/破坏式两档 + 损坏处置 + Sessions 零波及）+ 双模式隔离终验 + L031 三缝终审计 + 文档账复核 + VALIDATION 签核（C 档第 3 停）"
wave: 3
depends_on: ["16-2", "16-3"]
autonomous: true
requirements: [CATALOG-05, CATALOG-02, CATALOG-04]
files_modified:
  - LightamerCore/Sources/Catalog/CatalogRebuilder.swift             # 新建：全量重建两档——对账式（清水位重投影保 id）/ 破坏式（新文件换名晋升 L009）+ 损坏处置入口
  - App/Sources/Lightamer/Catalog/CatalogPreferences.swift           # schemaFailed 禁用态 + 「重建目录库」按钮绑定
  - App/Sources/Lightamer/UI/SettingsView.swift                      # 重建动作 + 组织数据边界文案（诚实：破坏式 = 组织数据丢）
  - Tests/LightamerTests/CatalogRebuildTests.swift                   # 新建：两档 parity/保 id/组织数据边界/换名原子性/损坏处置/Sessions 零波及
  - Tests/LightamerTests/CatalogBenchmarkHarness.swift               # 复用 16-1 harness——终测跑批（模式/Release 参数注记）
  - .work/gsd/phases/16-catalogs-mode/perf.md                       # 终测数字落账（SC#3 裁决行）
  - .work/gsd/phases/16-catalogs-mode/16-VALIDATION.md              # 新建：SC#1-5 三列证据 + 签核
  - .work/gsd/phases/16-catalogs-mode/16-4-SUMMARY.md
  - .work/gsd/phases/16-catalogs-mode/16-4-DECISIONS.md
  - .work/REQUIREMENTS.md                                           # CATALOG-01..05 翻账 Delivered（06 留 v2 预留）
  - .work/GOAL-STATE.md                                             # Phase 16 翻账 + 续接点
  - TODO.md                                                         # 16-4 勾选 + Phase 16 收口
  - LESSONS.md                                                      # 如踩坑
---

# Plan 16-4 — 收口：基准终测 + 脱库专项 + 签核（W3）

> 背景：Phase 16 的实证裁决位（SC#3）与脱库半边（SC#1/CS CATALOG-05）。三条主线：① **SC#3
> 基准终测**——16-1 harness 在真机落盘 `.lcat` 上跑全查询集矩阵，**基准门数字 > 一切理论**
> （p95 < 50ms 实测裁决；不过 = 回 ROADMAP §Phase 16 Notes 的 v2 评估项重启裁决，不是硬调到
> 过——CONTEXT Boundary 事实 5）；② **脱库重建专项**——research 修正②的**两档化**：对账式
> （默认：清水位 → 全会话重投影，UPSERT 保 id + 组织数据完全存活）/ 破坏式（文件级恢复：
> `.lcat` 丢失/schema 不识别时新文件换名晋升，组织数据丢失——CONTEXT specifics 的诚实边界在
> 此档成立）；③ 双模式隔离终验 + 三缝终审计 + 文档账复核 + **VALIDATION 签核**。签核前停
> （C 档第 3 停）：VALIDATION 产出后按夜间授权先例（D-07-3-T5-1 / D-09-05-T1-1 / 11-05 D1）
> 翻账（REQUIREMENTS/GOAL-STATE/TODO），晨审追认。

## read_first

1. `.work/gsd/phases/16-catalogs-mode/16-RESEARCH.md` §1.5（SC#3 查询集定义——终测口径正本）、
   §RQ-16-14（两档重建全裁决：对账式/破坏式/损坏处置/重建期 UI）、RQ-16-15（可全量重建精确边
   界——晨审追认项：两档化措辞进 CATALOG-05 解释面，不改字面）、F12（DELETE 1M 行遗 ~470MB
   freelist——破坏式走新文件换名的实测依据）、§10 16-4 草案、§11 修正②⑤
2. `.work/gsd/phases/16-catalogs-mode/16-CONTEXT.md` Boundary 事实 5（SC#3 是实证裁决非调优）、
   specifics「组织数据真身」教学义务 + 执行期决策边界、验证红线节（脱库专项/双模式隔离断言/
   基准 harness 真机手动跑禁 CI）、D-16-CONTEXT-7（re-link/移除——重建后行集语义）
3. `.work/gsd/ROADMAP.md` §Phase 16（SC#1-5 逐条 + Notes v2 评估项——不过门时的出路登记）+
   `.work/gsd/REQUIREMENTS.md` CATALOG-01..06（翻账对象）
4. 16-1 产物：`Tests/LightamerTests/CatalogBenchmarkHarness.swift`（终测 runner 复用）+
   `.work/gsd/phases/16-catalogs-mode/perf.md`（首跑表——终测对账列）+
   `CatalogProjector.swift`（对账式重建的投影核心复用）+
   `CatalogIndexSchema.swift`（schemaFailed 语义/pragmas）
5. 16-2/16-3 产物：隔离测试与 Manual-Only 台账（终验汇总输入）、`CatalogOrganizationStore`
   （对账式重建后组织数据存活断言的对端）
6. 自愈/原子晋升先例：`LightamerCore/Sources/Presets/PresetsStore.swift`（启动重扫自愈 + typed
   降级——损坏处置 UX 范式）+ `LightamerCore/Sources/Session/SmartAlbumStore.swift`（同目录
   tmp 晋升 L009）+ `LightamerCore/Sources/Session/SessionIndexStore.swift`（:8-12 mutable and
   untrusted 纪律原文——重建语义的哲学锚）
7. 12-VALIDATION 体例：`.work/gsd/phases/12-metadata-presets-lut/12-VALIDATION.md`（SC 三列证
   据表 + status/nyquist 字段——16-VALIDATION 同构）
8. `LESSONS.md` L009（同目录 tmp 晋升）/ L010 / L020 + `AGENTS.md`（Phase 执行模型 + 暂停机
   制——C 档第 3 停）+ `.work/GOAL-STATE.md`（Phase 16 续接点）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 本任务申报文件）；`caffeinate -dis` 包裹一
  切构建。
- **单测命令** = `Scripts/test-direct.sh '<Class>'`；判据 = Executed 计数行 + failures 行。
- **每任务边界检查 `.work/config.toml [gsd]` 开关**——commit 后、下一任务前。
- **不 push**；**构建勿加 `-derivedDataPath`**；新文件后 `tuist generate`。
- **回归基线 = 16-3 收尾轮计数**（最新 SUMMARY 终值；0 fail）。`LayerE2ERoundTripTests` flake
  若现，隔离 ×3 归因单列。
- **基准终测为真机手动跑**（禁 CI——机器差异；`LA_CATALOG_BENCH=1` 门控同 16-1）；**Debug/
  Release 分栏 + 三轮对账**（09 perf.md 方法论全套）；fixture 禁 UNITEK（L009）。
- **基准门判据（硬门）**：§1.5 全矩阵 keyset 分页形状 p95 < 50ms；任一形状超门 = **停**：归因
  （索引/planner/口径）→ 可修则修复复测 → 不可修则记 BLOCKER 回报 orchestrator（出路 = ROADMAP
  Notes v2 评估项重启裁决），**不得**调门/换口径硬凑过门（L020 同源纪律）。
- **破坏式重建红线**：禁库内 DELETE 型全量清空（F12 freelist 实测）；晋升 = 同目录 tmp + 校验
  + rename（L009）；晋升前旧文件保留一步（重命名 `.lcat.bak` 或晋升失败回退——DECISIONS 定形
  态）；失败 ROLLBACK/回退后原文件可用。
- **文案诚实红线**：破坏式重建完成提示必须明示「元数据已恢复；分类与集合需从备份恢复或重新整
  理」——不得暗示组织数据无损（CONTEXT specifics）；对账式提示「目录已与 N 个会话对账」。
- **L031 Metal 面**：Phase 16 无 Metal 面，`makeRoutedCommandBuffer()` 红线不适用（维持 16-1
  声明）；三缝 grep 审计终验照跑。
- **签核纪律**：VALIDATION 产出后按夜间授权先例翻账（REQUIREMENTS CATALOG-01..05 → Delivered；
  06 留 v2 预留不翻），晨审追认（C 档第 3 停写在本 plan——用户可随时推翻翻账）。
- RESEARCH/CONTEXT 未覆盖细节（重建进度浮层形态、`.lcat.bak` 保留策略）标注**执行期决策**入
  `16-4-DECISIONS.md`。

## Tasks

### T1 SC#3 基准终测（硬门实证裁决）

- **action**
  1. 复用 16-1 harness（`LA_CATALOG_BENCH=1` 真机手动跑）：fixture 1M 行默认参数 → 真机落盘
     `.lcat`（WAL 收敛后单文件态计时口径照 §1.5）。
  2. 全矩阵：过滤 8 款 × 排序 4 款 × 深度 3 档（每形状 30 页 × 60 行 p95，冷/热分离）+ COUNT
     面 5 款 + 投影吞吐三场景；Debug/Release 分栏、三轮对账。
  3. **硬门判定行**：全形状 p95 < 50ms 逐项 ✔/✘ 表 + `+` 前缀形状（cam/combo）对照列（F10 防
     回归——若 harness 显示 planner 选过滤索引 + TEMP B-TREE 即形状回归，先修分派再计门）。
  4. perf.md 终账：终测表 + 与 16-1 首跑/research 探针 F6-F16 三列对账（偏差 >2× 归因注记）+
     SC#3 裁决行（`PASS` / `BLOCKER` + 数字）。
  5. 超门处置（如有）：归因 → 修复 → 复测闭环记录；不可修 = BLOCKER 上报（纪律节红线）。
- **证据**：perf.md 终测全表 + 裁决行 + 对账列；Release 分栏数字（主判据用 Release——Debug 仅
  参考，DECISIONS 记口径）。

### T2 脱库重建专项（两档 + 损坏处置）

- **action**
  1. 新建 `LightamerCore/Sources/Catalog/CatalogRebuilder.swift`：
     - **对账式重建（默认）**：`reconcileRebuild()` = 遍历 `catalog_sessions` 清
       `last_projected_epoch = 0` → 逐会话全量重投影（16-1 `project` 核心复用；UPSERT 路径
       conflict 保 id）→ **组织数据（categories/collections 及成员关联）完全存活**。适用 = 行
       漂移/部分损坏怀疑/sweep 补课。可取消（事务边界中止，已完成会话保留，幂等可续跑）。
     - **破坏式重建（文件级恢复）**：`destructiveRebuild()` = 写 `catalog.lcat.tmp`（新库 +
       七表 DDL）→ 全会话重投影入 tmp → 校验（行集计数对账）→ 同目录 rename 晋升（L009）→
       **组织数据丢失**（新库无 categories 行）——UX 文案诚实（纪律节红线）。**禁库内 DELETE**
       （F12）。
     - **损坏处置入口**：open 时 `schemaFailed`（v99/截断/unparsable）→ typed error 上抛 →
       Catalogs 模式禁用态 + 「重建目录库」按钮（T3 设置面绑定 destructiveRebuild）+
       **Sessions 模式零波及**（守卫即隔离——16-1 探针断言扩 schemaFailed 态）。
  2. 设置面绑定：重建动作按钮（对账式日常入口 + 破坏式仅在禁用态出现）+ 进度反馈（后台进度
     X/N 会话浮层 + 完成提示两套文案）+ Catalogs 网格重建期间 = 空网格 + 进度（保 Smart
     Albums 可见性——RQ-16-14 推荐态）。
  3. `.lcat` 单文件备份语义复核：文件位置选择器旁提示「退出 app 后拷贝此文件即完整备份」
     （RQ-16-1① 收敛时机；不加自动备份机制——RQ-16-15 维持裁决）。
- **证据**：`CatalogRebuildTests`——对账式：构造行漂移（手改 catalog 行 + 删行）→ rebuild →
  行集 parity 逐列 + **id 不变 + 组织成员关联存活**；破坏式：删 `.lcat` → rebuild → 元数据
  parity + categories 空表（诚实边界断言）+ 晋升原子性（tmp 中断 = 旧文件原样）+ 旧文件保留
  形态；损坏处置：v99 fixture → 禁用态 + Sessions 全流程零波及（探针）；两档后 grid/SmartAl
  bum/角标全链冒烟。

### T3 双模式隔离终验 + 三缝终审计 + 文档账复核（GUI 项需解锁控制台（Manual-Only 候补））

- **action**
  1. **隔离终验**：16-2 `CatalogModeIsolationTests` 全绿复跑 + 手动走查（未启用全流程 / 启用
     后 Sessions 等价 / schemaFailed 禁用态三分支）；Manual-Only 台账（16-2/16-3 汇总行）终
     盘点入 VALIDATION。
  2. **三缝终审计**（L031/16-1 纪律节三命令全仓跑）：输出入 VALIDATION 证据列；命中越界 = 修
     复后才可签核。
  3. **文档账复核**（orchestrator 收口批的复核位——两处漂移已在 discuss/research 环修正：
     `458f207` PROJECT.md:65 / `685d18d` Traceability）：逐项核 PROJECT.md 约束节、ROADMAP
     Phase Overview counts、REQUIREMENTS Traceability 与本 phase 交付一致；残余漂移列清单回
     orchestrator（不在 worker plan 内改 ledger 正文）。
  4. zh/en 终核（全 phase 新增键 zh 首屏 smoke 复跑）。
- **证据**：隔离三分支走查记录；三缝审计输出；文档账复核清单；L025 终核输出。

### T4 VALIDATION 签核 + 翻账 + 收尾（C 档第 3 停）

- **action**
  1. `16-VALIDATION.md`（12-VALIDATION 同构体例）：SC#1-5 逐条三列证据（SC 判据 / 证据 = 测
     试+文件行号+perf.md 裁决行 / 状态）；SC#3 裁决数字前置；CATALOG-01..06 × plan 覆盖矩阵；
     缺陷处置记录（如有）；Manual-Only 汇总；`status: validated` + `nyquist_compliant: true`
     （签核字段——仅在 T1 硬门 PASS 且 T2/T3 全绿后填）。
  2. **翻账**（夜间授权先例 D-07-3-T5-1 / D-09-05-T1-1 / 11-05 D1；晨审可推翻）：
     `.work/REQUIREMENTS.md` CATALOG-01..05 → Delivered（06 留 v2 预留）+ GOAL-STATE Phase 16
     翻账 + 续接点（下一 phase 建议）+ TODO.md 收口勾选。
  3. 全 suite 终轮（16-3 基线 + 本 plan 新增，0 fail）；`16-4-SUMMARY.md`（任务表/commit 表/
     基准裁决行/两档重建证据/Manual-Only 汇总）+ `16-4-DECISIONS.md`（Release 口径、`.lcat.bak`
     保留形态、进度浮层、其余执行期决策）；LESSONS 新候选评估。
- **证据**：VALIDATION 落盘 + 翻账 diff + 测试计数（0 fail）+ SUMMARY/DECISIONS 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| SC#3 硬门 | 全矩阵 p95<50ms 裁决行（Release） | `LA_CATALOG_BENCH=1 Scripts/test-direct.sh 'CatalogBenchmarkHarness'`（真机）+ perf.md |
| 对账式重建 | 行集 parity + id 不变 + 组织数据存活 | `Scripts/test-direct.sh 'CatalogRebuildTests'` |
| 破坏式重建 | 元数据 parity + 组织空表 + 换名原子 + 文案诚实 | `Scripts/test-direct.sh 'CatalogRebuildTests'` |
| 损坏处置 | schemaFailed 禁用 + Sessions 零波及 | `Scripts/test-direct.sh 'CatalogRebuildTests'`（专项段） |
| 隔离终验 | 三分支走查 + 既有隔离套全绿 | `Scripts/test-direct.sh 'CatalogModeIsolationTests'` + 手动走查 |
| 三缝 | grep 三连仅命中申报文件 | 纪律节命令（输出入 VALIDATION） |
| 签核 | VALIDATION status validated + 翻账 diff | 文件审查 |
| 回归 | 全 suite 0 fail（16-3 基线+新增） | `caffeinate -dis Scripts/test-direct.sh`（全套） |

## 验收标准（Acceptance）

- [ ] **SC#3 硬门**：§1.5 全矩阵（8 过滤 × 4 排序 × 3 深度 + COUNT 5 款 + 投影三场景）真机落
      盘 Release p95 < 50ms 逐项裁决行落 perf.md；`+` 形状对照列无 TEMP B-TREE 回归；超门处置
      闭环或 BLOCKER 上报（无静默调门）
- [ ] 对账式重建：清水位重投影 → 行集 parity 逐列 + **id 保持 + categories/collections 成员
      完全存活** + 可取消幂等续跑 + 完成提示「目录已与 N 个会话对账」
- [ ] 破坏式重建：新文件换名晋升（L009，禁库内 DELETE）+ 元数据 parity + **组织数据丢失文案诚
      实**（完成提示逐字含「分类与集合需从备份恢复或重新整理」）+ 晋升中断旧文件原样
- [ ] 损坏处置：schemaFailed → Catalogs 禁用 + 重建按钮 + **Sessions 模式零波及**（探针断言）
      + 重建期空网格+进度
- [ ] 双模式隔离终验三分支 + Manual-Only 台账盘点入 VALIDATION + 三缝 grep 审计全仓仅命中申报
      文件 + 文档账复核清单
- [ ] VALIDATION：SC#1-5 三列证据全项 + `status: validated` + `nyquist_compliant: true`；
      CATALOG-01..05 翻账 Delivered（06 留 v2）；GOAL-STATE/TODO 翻账
- [ ] 全 suite 0 fail；每任务独立提交 + 边界查开关；不 push；SUMMARY + DECISIONS 落盘；
      **签核后停等晨审追认（C 档第 3 停）**

# Plan 16-4 — 收口：基准终测 + 脱库重建 + 签核（W3）执行 SUMMARY

**完成:** 2026-09-27（ZCode executor subagent worker，wave 3；基线 = 16-3 收尾轮 1548/9skip/0fail）
**Commits:** T1 `b744770`（SC#3 终测 + perf.md 终账 + harness 注记）→ T2 `f7a8037`（两档重建 + 损坏处置 + 设置绑定 + 5 测试）→ T3/T4 收口签核（本批）；未 push；边界查开关 ×3（auto=true/paused=false）

## 任务表

| 任务 | 交付 | Commit | 测试证据 |
|---|---|---|---|
| T1 | SC#3 基准终测：16-1 harness 复用，验收修正后 fixture（2.6M tags，`5cc4d8c`）真机落盘 Debug×3 + Release×3 三轮对账；perf.md §A 终账（终测全表 + 与首跑/research 三列对账 + §A.6 裁决行）；harness 头注 Release 直启参数注记（ad-hoc 重签 + DYLD 顺序） | `b744770` | 3 测试 × 6 轮全过（Executed 3/0 ×6） |
| T2 | `CatalogRebuilder`（对账式清水位重投影保 id 组织存活可取消幂等 / 破坏式 tmp 换名晋升 L009 + TRUNCATE checkpoint 确定性化 + 行集校验 + `.bak` 一代备份 + 注入回退）+ 损坏处置（schemaFailed probe + v99 typed 拒绝 + Sessions 零波及）+ 设置/网格 UI 绑定（重建按钮两态 + X/N 进度 + 空网格+进度 + 两套完成文案 + confirm dialog + 备份 hint）+ `CatalogRebuildTests` 5 + zh/en 16 键 + `checkpointTruncate` 收进 Schema（缝 b） | `f7a8037` | CatalogRebuildTests 5/0（含取消续跑/回退字节全等/组织空表/`.bak` 持旧数据/v99 修复闭环） |
| T3 | 隔离终验（隔离套 7/0 复跑 + 三分支程序化走查：未启用零句柄 / 启用 Sessions 等价 / schemaFailed 禁用态）+ 三缝 grep 三连终审（VALIDATION 贴证）+ 文档账复核（PROJECT.md:65 / ROADMAP counts 均已上游修正，残余漂移 = 零）+ zh/en 终核（L025 键族测试绿，xcstrings 1002 键） | 本批 | CatalogModeIsolationTests 7/0 |
| T4 | 全套终轮 1553/9skip/0fail + `16-VALIDATION.md`（SC#1-5 三列证据 + status: validated + nyquist true）+ 翻账（REQUIREMENTS CATALOG-01..05 Delivered / 06 留 v2；GOAL-STATE 续接点；TODO 收口）+ SUMMARY/DECISIONS | 本批 | 见下 |

## 终轮计数（SC#3 裁决数字前置）

- **回归：基线 1548/9skip/0fail → 终轮 1553/9skip/0fail（434.9s，EXIT=0）** = +5（CatalogRebuildTests）零失败零 flake；LayerE2ERoundTripTests/ToneEqualPerfTests 负载型 flake 未现身。
- **SC#3 硬门 = PASS（perf.md §A.6）**：§1.5 全矩阵 8 过滤 × 4 排序 × 3 深度 = **96/96 形状 Release 热 p95 < 50ms**——最差 **12.28ms**（combo|dateDESC|d0），门余量 **>4×**；三轮 11.53/12.28/11.87 稳定（Debug 12.21/13.20/12.92 同判）；`+` 前缀形状零 TEMP B-TREE 回归（cameraEq 0.13-0.20ms / combo 深度页 0.27-0.48ms）；COUNT 简单谓词现算 60-74ms + combo memo 命中 0.01ms + tagSweep 63.9-64.4ms@2.6M（1.6→2.6M 线性符合首跑预告）；投影 full100k **1.461-1.472s**（≤30s 预算余量 ~20×）/ increment10k 238-241ms / 纯 diff 5.0ms。**无超门 → 无归因修复需求 → 无 BLOCKER → 无调门**；ROADMAP §Phase 16 SC#3 达成，v1 SQLite 终裁成立。
- 终测口径：fixture = 16-1 验收修正后形状（tags=2,600,000 六轮恒定）；Release 主判据（Debug 参考）；冷样本单列参考（最差 colorEq|ratingDESC ~166ms 页缓存一次性）。

## 两档重建证据（T2）

- **对账式（默认）**：漂移行重投影列值恢复（rating NULL→3）+ 幸存行 **id 逐行不变** + 分类/集合/成员关联完全存活；lindex 删行经键集对账闭合；可取消（会话边界中止，完成会话水位已推进、pending 水位 0 行集不动）+ 幂等续跑收敛；完成提示「目录已与 N 个会话对账」。
- **破坏式**：新库 `catalog.lcat.tmp` 全投影 → 行集计数校验（8/8）→ TRUNCATE checkpoint → 同目录 rename 晋升；元数据 parity（queryPage 8 / count 8 / tagCounts Nature=4）；**categories/collections/成员四表空 = 诚实边界**；新 session_id 全新铸造；`.lcat.bak` 持有旧组织数据（单文件备份兜底实证）；注入晋升失败 → 原文件**字节全等**回退 + tmp 清净；禁库内 DELETE（F12）红线无违反。
- **损坏处置**：v99 fixture → reconcile/投影 typed `schemaFailed` 拒绝（不猜升级）→ openAndSync 真 scanner 全流程成功 + 文件保持 v99（Sessions 零波及）→ 破坏式重建修复为 v1 + 4 行恢复。
- UI：schemaFailed 禁用态 + 「重建目录库…」仅禁用态出现（前置 confirm dialog 明示组织数据丢弃）；对账按钮日常入口；X/N 进度（设置行 + 网格空网格+进度 overlay）；完成文案两套（破坏式逐字含「分类与集合需从备份恢复或重新整理」）；位置行「退出 app 后拷贝此文件即完整备份」。

## Manual-Only 台账盘点（入 VALIDATION，8 行）

16-2 五行（MO-16-2-1..5：设置面板/切换器/网格渲染/会话管理/批量手感）+ 16-3 三行（MO-16-3-1..3：建树/拖拽/锚点过滤+归类）——全部需真实 RAW 会话库或人工点按；16-4 新增 UI 面逻辑由 5 测 + 隔离套钉死，GUI 走查并入 MO-16-2-1 承接。

## 三缝终审计（VALIDATION 贴证）

- 缝 a：Core Catalog 五文件申报面常量 SQL（Rebuilder 3 处 = registry 读×2 + COUNT 校验）；App 零裸 SQL。
- 缝 b：DDL/PRAGMA 仅两 Schema 文件（SessionIndexStore 三处 PRAGMA = 16-1 期既有只读验证面注记；16-4 新增 checkpoint 已收进 CatalogIndexSchema——D4）。
- 缝 c：`sqlite3_*` 仅 SQLiteHandle.swift；Tests 侧 `import SQLite3` = fixture 直连先例（16-1 申报）。

## 偏离/决策

11 条入 `16-4-DECISIONS.md`。要点：**D2** 混合代际 Release 产物陷阱（管道吞 TEST BUILD FAILED → dlopen 符号错配；处置 = 清配置产物目录 + 判据改读 SUCCEEDED 行——LESSONS 候选）；**D4** checkpoint 确定性化（不赌 SQLite 关闭行为；PRAGMA 收进 Schema 缝 b）；**D8** CatalogOrganizationTests await 提升（全量重编暴露的编译修复，非产品缺陷）；**D9** 终测与 T2 源并存（热路径零改动，数字有效）；**D10** harness 粘行提取（96/96 全测非缺失）；**D11** 16-2 验收注记①不采纳（范围外不顺手修）。

## 遗留

- Manual-Only 8 行待验收轮交互走查；Phase 16 verify-work 终验待用户（VALIDATION 过目）。
- LESSONS 新候选：D2（xcodebuild 管道吞码 + 混合代际产物症状/处置）——登记待 orchestrator 批。
- 无阻塞。**C 档第 3 停：签核翻账已按夜间授权先例执行，晨审可推翻。**

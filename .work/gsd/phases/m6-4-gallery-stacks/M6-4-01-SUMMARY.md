# M6-4-01 SUMMARY — 图库 stacks + auto-stack（面 A 全量批）执行收口

> 执行 = 夜间全自动授权（先例 D-07-3-T5-1；`paused=false` / `auto=true`
> 开工确认）。plan 正本 = 同目录 `M6-4-01-PLAN.md`（修订版）；裁决正本 =
> `M6-4-CONTEXT.md`；偏差登记正本 = `M6-4-01-DECISIONS.md`
> （D-01..D-12 执行批 + D-13..D-15 验收修复批）。
> **ACCEPTANCE 未写**（双重验收归验收批：zcode subagent 独立验收 PASS 后
> 串行 omp 二次验收，严禁并发）。

## 任务序与 commit 链（每任务独立提交，全英文 Conventional Commits）

| 任务 | commit | 内容 | 定向轮 |
|---|---|---|---|
| T1 | `f30e83a3` | schema v5 两新表 + UNIQUE 索引 additive 迁移（KD-1） | V5Tests 8/0/0 + 既有 SchemaTests 23/0/0 |
| T2 | `8c613f4f` | LibraryStore CRUD 全 op 族 + removeImage 解散清扫（KD-2/KD-3） | StackStoreTests 16/0/0 + 既有 StoreTests 14/0/0 |
| T3 | `80b7c5fd` | StackClustering 纯函数 + store autoStack（KD-4） | ClusteringTests 8/0/0 |
| T4 | `a33a24c1` | 查询面谓词/memberships/fixup 纯函数（KD-5） | StackPaginationTests 9/0/0 + 既有 QueriesTests 20/0/0 |
| T5 | `c4ce7847` | 导入缝 merge→stack（KD-6/E1） | ImportMergeStackTests 5/0/0 + 既有 ImportServiceTests 11/0/0 |
| T6 | `07d5fcdd` | LibraryGridModel 显示态 + forward-only fixup + 命令面（KD-7） | GridStackTests 10/0/0 + 既有 GridModelTests 16/1skip/0 |
| T7 | `923f3a85` | 徽章/contextMenu/AutoStackDialog/View 菜单/xcstrings 13 键（KD-8） | App bundle 810/4skip/0 |
| T8 | （本文件 + DECISIONS + BUNDLE-MAP 增行记录） | 收口 | 见下 |

基线 `f498e5f5`（plans review 前的 research 定稿点）→ HEAD = 7 任务 commits。

## 定向轮终值（SC 分账对表）

- **Library bundle（收口轮，全量）**：`727/4skip/0`，exit 0，零 MEMFAIL，
  peakRSS 620MB（8G 门内）。
- **App bundle（回归轮，零新法）**：`810/4skip/0`，peakRSS 2832MB。
- **SC 分账**：LIB +56（六新文件 8+16+8+9+5+10，BUNDLE-MAP 六行与实测逐一
  相符）/ APP +0 ∈ 计划带 52..58 ✓。
- **全套预期**：3811..3817/24/0（基线 3759/24/0）。
- zh-audit `--check`：**PASS**（1677 source keys / 1918 catalog keys /
  zh complete / locale {en, zh}）——13 新键 MISSING = 0，动态族（两个 %lld
  格式键 = 插值键在册）并集核对闭合。

## 实际收口 TOTAL（02 的 S8 重算基线申报值）

**`TOTAL|3815/24/0|`（推算）= M6-3 终验基线 3759/24/0 + 本批 LIB 实测
+56**（六新文件法数为终态实测，分账闭合；App/IOP/IOPParity/Layers/
Sessions/Export 六 bundle 本批零新法）。全套 `--all` 本 plan 未跑（批准
制）——验收批准轮实跑时以此值为预期中心；02 plan 的 S8 机制以 **3815** 为
01 实际收口 TOTAL 重算其预期带（原起草预测 3832..3842 挂重算机制生效）。

## 红线自检（基线 f498e5f5..HEAD 机检电池，T7/T8 双跑）

- 冻结面数组零 diff：`imagesColumns`/`albumsColumns`/`albumContentColumns`/
  `versionRefColumns`/`reservedTableNames`/`triggerNames` 数组定义行零命中
  （唯一命中 = v5 注记段注释文字）；`indexNames` 恰一行追加
  （`"idx_stack_content_image",`）。
- `.metal` 零 diff；`Project.swift` dependencies 块零 diff；V50Order 零触；
  MCP 快照族（PhotoProjection/McpServerController）零 diff；sidecar schema
  零触（LightamerSidecar.swift 零 diff）；六格式导出矩阵零触。
- UserDefaults 零新键（gap 与显示态全会话域）；`.lra` sidecar 格式零字节
  变更。
- xcstrings 13 键尾块纯插入（diff 221 行全为 `+`，唯一 `-` 行 = diff 头）；
  `zh-audit --check` PASS。
- `grep -rn "\.runModal(" App/Sources` = 0；新增 diff 的
  `String.LocalizationValue("` 插值键形态 = 0（存量两处为既有面）。
- L041：六新测试文件随各自任务 commit 登记 `Project.swift`（LIB 数组显式
  清单）+ BUNDLE-MAP 六行 + 头注增行记录；`tuist generate` 每批文件编辑后
  先于构建执行；新 App 文件（LibraryAutoStackDialog）走 App target 既有
  glob，无需登记。
- L070：零 push；零历史手术。

## 挂账申报（DECISIONS 详目）

| # | 项 | 归宿 |
|---|---|---|
| D-01 | 谓词拼写 flag-aware JOIN（KD-5 字面式 ↔ T4①/④ 语义收敛） | DECISIONS §D-01 |
| D-02 | 单栈展开 = 成员现 keyset 位（v1） | §D-02 |
| D-03 | 手动 group 新生栈 collapsed；split 尾栈继承 flag | §D-03 |
| D-04 | 无 undo 偏离 | §D-04 |
| D-05 | fixup forward-only 偏离 | §D-05 |
| D-06 | 收起态无顶替 + overviewCount/groupCounts 口径分裂（V2 候选） | §D-06 |
| D-07 | 导入缝匹配细则版本化条款（LIKE ESCAPE `\`）+ link 模式登记 + 计数器零 UI | §D-07 |
| D-08 | fixup 纯函数宿主随 T4 commit 落位（构建自洽约束） | §D-08 |
| D-09 | schema 测试定向更新九处（M3 两法 + 机械代际前滚七处，含 Library 全轮浮出的 LibraryDocumentTests 三处） | §D-09 |
| D-10 | T5 fixture 批内隔离设计（多导入批构造细则表） | §D-10 |
| D-11 | auto-stack 池全集走查性能注记 | §D-11 |
| D-12 | `.flat` 字节恒等双证据（调用点 grep 清单 + 行级恒等测试） | §D-12 |

## 修复批（双重验收后，minor 清偿；2026-10-14 夜）

双路验收（ACCEPTANCE + ACCEPTANCE-2ND）PASS / 0 error 后的登记 minor
清偿批，逐项落点：

- **M-a**：`ImportMergeStackTests` +1 法（⑥ ESCAPE 回归钉）——`%`/`_`/
  字面反斜杠三转义全走真 importFolder 的库级 LIKE 回落，三 decoy 行钉死
  wildcard 不泄漏（`%`/`_` 泄漏 = 命中集变宽 → folderName 歧义整组
  skip；`\` 不转义 = 错配无反斜杠 decoy）。
- **N-1**（O-i 升格，第二路建议采纳）：`LibraryStore.autoStack` 读腿补
  空池守卫（对称 `stackedIDs(in:)` 形态，`IN ()` 非法 SQL 不可达）+
  `AutoStackClusteringTests` +1 空池负测（preview/commit 双面 = 0）。
- **M-c**：`LibraryGridModel` :525 / `LibraryQueries` :381 两处悬空
  「DECISIONS-registered」注记改指 D-14（登记落账见 DECISIONS §D-14）。
- **M-b/M-d/M-e（doc-only）**：DECISIONS 补 D-13（files_modified 范围外
  两文件补登记）+ D-15（翻账推迟编号）+ D-12 调用点清单勘误 5→7 处
  （collectAllIDs 双段 :540/:551，显式五处行号刷新 :206/:218/:265/:277/
  :285）。
- **定向回归（本批亲跑）**：Library bundle **`729/4skip/0`**（727 + 2 新
  法，exit 0，peakRSS 621MB）/ App bundle **`810/4skip/0`**（零漂移，
  peakRSS 2832MB）。
- **全套预期重算**：3815 + 2 新法 = **3817/24/0**（02 plan 的 S8 重算
  基线随之 3817；上节 3815 为执行链收口时点值，历史行不回写）。
- 红线自检：本批 diff 零 xcstrings / 零 UserDefaults 新键 / 零 `.metal`
  / 零 runModal / 零 `String.LocalizationValue("` 插值形态；只动清单面
  （两测试文件 +2 法、三源文件守卫与注记、两账本文档）。

## 翻账建议（闭环批统一做，本批零翻账）

AGENTS.md（M6-4 架构增量节，素材 = DECISIONS 全文）/ ROADMAP（M6-4 行面 A
注记）/ REQUIREMENTS（M6INT-02 面 A 兑现）/ GOAL-STATE（续接点 → plan 02，
S8 基线 = 3815）/ TODO（M6-4 条目）。

## GUI 走查缺口（验收批Manual-Only 清单素材）

单测面已闭环（63 新法全绿）；以下为 GUI 域观察项，验收批按需走查：
徽章/chevron 点击态、AutoStackDialog sheet 呈现 + preview 数字、View 菜单
两命令在图库面/编辑器面的 no-op 守卫、contextMenu 五项的条件可见性
（`library.grid.cell.*` accessibilityIdentifier 已预埋）。

---
phase: m2-9
plan: "M2-9-05"
title: "收口（wave 4）——真机走查批（检查器 Export 页五节 + 队列四态 + DRT 联动导出端到端 + yiyin×DRT + legacy 回切）+ zh-audit 终核 + REQUIREMENTS M2EXP-01..05 翻账（D-11-CONTEXT-4 扩档注记 + OQ 收窄注记）+ phase 汇总 + GOAL-STATE/TODO/AGENTS.md 同批（UserDefaults 键入册 + M2-9 增量节）"
wave: 4
depends_on: ["M2-9-04"]
autonomous: true
requirements: [M2EXP-01, M2EXP-02, M2EXP-03, M2EXP-04, M2EXP-05]
estimated_new_tests: 0
bundles: []
files_modified:
  - .work/gsd/phases/m2-9-export/M2-9-05-SUMMARY.md               # 新建：走查证据 + phase 汇总（含 M2-9 phase 小结节 + 测试增量对账链）
  - .work/gsd/phases/m2-9-export/M2-9-05-DECISIONS.md             # 新建：走查裁决 + 翻账注记底稿（01-04 各 DECISIONS 底稿合并终稿）
  - Resources/Localizable.xcstrings                               # 修改：zh/en 缺口补齐（T1——04 随手键终核；三先例惯例）
  - .work/gsd/REQUIREMENTS.md                                     # 修改：M2EXP-01..05 勾选 + Delivered 终态 + 注记
  - .work/GOAL-STATE.md                                           # 修改：M2-9 续接点翻账 + C 档门控登记
  - .work/TODO.md                                                 # 修改：M2-9 条目清账
  - AGENTS.md                                                     # 修改：M2-9 架构增量节 + UserDefaults 键登记补册（export.* 六键）
  - .work/LESSONS.md                                              # 如踩坑
---

# Plan M2-9-05 — 收口（走查 + zh 对账 + 翻账 + phase 汇总）

> **性质**：零功能收口 plan——**除 zh String Catalog 增行外零源码 diff**（红线：T3
> `git diff --stat` 出现第三类源码文件 = 违约；`.work/` 与 AGENTS.md 账本 md 除外）。
> 四块：①真机走查批（GUI 证据——状态层单测盖不住的观感/端到端域）；②zh-audit
> 终核（`Scripts/zh-audit.py --check` PASS 为门）；③REQUIREMENTS 翻账（M2EXP-01..05
> + D-11-CONTEXT-4 扩档注记 + OQ-6 XMP 收窄注记 + TIFF32f 语义边界注记）；④phase
> 汇总（SUMMARY phase 小结节 + C 档门控登记——每 plan 闭环后 C 档第 2 停在 M2-9
> 的兑现位）。

## 已定裁决（硬约束，不得重开）

- 本 plan 全部裁决值 = CONTEXT 裁决记录（OQ-1..12）+ 01-04 各 PLAN 已定裁决——
  **走查发现的偏差只登记不修**（当场修 = 违约；修复走新 plan 或验收批 fix 提交，
  `fix(m2-9):` 前缀）。
- 走查证据纪律（§3.2/§9）：视口关键区截图（禁全页长图）+ 图注关键数字；GUI 不可用
  （锁屏/无控制台）= 如实登记待人工，不阻塞翻账（走查项独立挂账）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 走查清单（逐项：操作 → 判据 → 证据）

| # | 走查项 | 判据 | 证据 |
|---|---|---|---|
| 1 | M2 工作区导出入口 → 检查器 Export 页打开，五节齐备 | 页可达 + 节序对表 Alcedo | 截图 ×1 |
| 2 | 尺寸四模式切换与字段显隐 + 折叠区（upscale/cap 默认 false/0） | 字段随模式显隐 + 默认值 | 截图 ×1 |
| 3 | 模板编辑器：预设 3 内置选择 + 无效模式串禁用 start + live 预览 | 禁用态 + 预览串 | 截图 ×1 |
| 4 | 单图 DRT 联动导出（编辑若干模块 + DRT 页动 EOTF）→ 出片 EXIF/ICC 抽验（Software=Lightamer <ver> / ICC space+TRC = DRT 编码 / 无 GPS） | 元数据面与裁决一致 | 截图 + 元数据dump 文本 |
| 5 | 批量多选 × 模板 sequence 递增 × 子文件夹 | 文件名 `…-001/002` + 落子目录 | 目录列表截图 |
| 6 | 冲突 FAIL 档：同名录二次入队 → 失败态红字 + retry 面可用 | 四态 Failed 展示 | 截图 ×1 |
| 7 | 队列四态 + 进度条 + 36 行帽（>36 行构造选区） | 汇总行 `…(N more)` | 截图 ×1 |
| 8 | yiyin 开启 × DRT：出片印框在色调映射后（边框纯白不压暗）+ EOTF 后语义 | 边框视觉判定 | 截图 ×1 |
| 9 | PQ/HLG 编码图导出：产物值域钳位观感（高光压 SDR 白）+ ICC EOTF 标注 | OQ-8 A 行为可见 | 截图 + dump |
| 10 | legacy 回切（`LIGHTAMER_LEGACY_LIBRARY=1`）：旧 sheet 原样可用 + 检查器 Export 页不可达 | 剥离门双向 | 截图 ×1 |

- 判据 4/9 的元数据抽验用只读工具（`mdls`/`exiftool` 缺席则 `sips -g` + ICC
  bytes dump 脚本）——**不引入新依赖**。

### KD-2 翻账注记义务（逐条显式，禁静默按字面勾选）

- M2EXP-01 `Delivered`（OQ-2 原地扩容；尺寸域 1...100000/1...2400 = 我方超集域）。
- M2EXP-02 `Delivered`（OQ-6 模型 7 bool + UI 单开关；**D-11-CONTEXT-5 语义收窄
  注记**：XMP 编辑摘要 packet 默认不嵌）。
- M2EXP-03 `Delivered`（OQ-4 语法全量移植 shutter `-` 形态；OQ-5 **三档**——
  **D-11-CONTEXT-4 扩档注记**：Increment 默认 + FAIL/REPLACE 显式档，历史裁决
  文本不改写）。
- M2EXP-04 `Delivered`（OQ-7 强制联动五菜单退役 = M2 UI 面；**TIFF 32f DRT 档 =
  编码值 float32** 语义边界注记；OQ-8 v1 钳位 + peak 不入 ICC 的 V2 预留注记）。
- M2EXP-05 `Delivered`（OQ-1 检查器页 + 四态 + 质量四键；yiyin/post-actions 超集
  保留注记；EXR/UltraHDR = V2 ALCE-02/03 不变）。

### KD-3 同批落盘（§3.1 原子同步）

- **AGENTS.md**：M2-9 架构增量节（ExportVariant 载体面/`.drt` 导出重放缝/尾格式
  覆写缝/命名模板引擎边界/记忆键族——后续 phase 的约定正本）+ UserDefaults 键
  登记段补 `export.jpegQuality`/`export.heicQuality`/`export.avifQuality`/
  `export.webpQuality`/`export.namingTemplates`/`export.lastDirectory` 六键。
- **GOAL-STATE**：M2-9 续接点翻账 + C 档登记（本 phase 每 plan 闭环 C 档第 2 停
  已逐波执行；本条 = phase 尾终态 + VALIDATION 前置输入清单）。
- **SUMMARY phase 小结节**（M2-6-3 先例）：五 plan 战果一览 + 测试终数对账链
  （2577 → 终值，逐 plan 增量）+ 挂账清单（全 recipe 预设 = PRES 交汇 / UltraHDR
  = V2 / peak-ICC 标注 = V2 / OQ-8 直出 = V2 / 细粒度元数据 UI 后置）+ M2-10
  依赖面交接。
- **TODO**：M2-9 条目清账；**LESSONS**：03 的 mountXMP 默认语义变更抉择 + 02 的
  尾格式缝探索（如踩坑）。

## read_first

1. `.work/gsd/phases/m2-9-export/M2-9-CONTEXT.md` 裁决记录（走查判据正本）。
2. `M2-9-01..04` 四 PLAN + 各 DECISIONS 底稿（合并终稿素材）。
3. `Scripts/zh-audit.py` 头注（三断言口径）+ `Resources/Localizable.xcstrings`
   locale 纪律（zh 非 zh-Hans，L025）。
4. `.work/gsd/REQUIREMENTS.md` EXP2 族五行正本 + `ROADMAP.md` M2-9 行。
5. `.work/GOAL-STATE.md` 续接点节 + AGENTS.md「暂停机制」节（C 档三条）。
6. `phases/m2-8-versions/M2-8-3-PLAN.md`（收口 plan 式样先例）。

## 纪律（强制）

1. 提交纪律同前（每任务独立提交、只 add 申报文件、不 push、`-F` 写 message）。
2. **零源码 diff 红线**：`.xcstrings` 外零源码文件；`.work/`/AGENTS.md 账本 md
   除外；`git diff --stat` 出现第三类 = 违约（T3 终核）。
3. 测试纪律：本 plan 零新测试；全套 `--all` 终跑（前报备）+ 终态计数 = 04 终态
   （走查批若产出 `fix(m2-9):` 修复提交，计数链如实记录）。
4. 证据纪律：KD-1 十项逐条落 SUMMARY（截图路径 + 图注数字 + dump 文本），禁估算
   禁引用他人数字；不可自动化项如实待人工。
5. checker 四条对表：①真链实测（走查亲测）；②登记（本 plan 无新测试文件——
   走查证据即登记面）；③语义断言可观测（元数据 dump 成对）；④边界核对（T3
   逐文件 + zh 键单源工具判）。

## Tasks

### T1 真机走查批（KD-1 十项）

- **action**：逐项执行（GUI 会话；锁屏不可用 → 待人工登记）；证据落
  `.work/gui-acceptance/m2-9/`（截图 + dump）；异常 = 登记 E3/另案，不当场修。
- **验收标准**
  - [ ] 十项逐条状态落 SUMMARY（截图/数字/待人工三态之一）；零当场修复。

### T2 zh-audit 终核 + DECISIONS 终稿

- **action**：`uv run python3 Scripts/zh-audit.py --check` → 缺口补齐复跑 PASS；
  对账表（预估 vs 实数）入 DECISIONS；01-04 底稿合并 `M2-9-05-DECISIONS.md` 终稿。
- **验收标准**
  - [ ] `--check` PASS（输出贴 SUMMARY）；diff 仅 .xcstrings。

### T3 翻账 + phase 汇总 + 终局核对（KD-2/KD-3）

- **action**：REQUIREMENTS 五行翻账（注记义务逐条）；GOAL-STATE 续接点 + C 档终态；
  TODO 清账；AGENTS.md 增量节 + 六键入册——同批落盘；`M2-9-05-SUMMARY.md`（phase
  小结节 + 挂账清单 + 对账链）；全套 `--all` 终跑 + `git diff --stat` 逐文件终核。
- **验收标准**
  - [ ] 五账同批一致（REQUIREMENTS/GOAL-STATE/TODO/AGENTS/SUMMARY）；全套 0 fail；
        diff 边界 == md + .xcstrings 申报集。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 走查十项状态落 SUMMARY（证据路径/待人工登记），零当场修复 | SUMMARY 文本核 |
| 2 | zh-audit `--check` PASS；diff 仅 .xcstrings | 工具输出 + `git diff --stat` |
| 3 | REQUIREMENTS M2EXP-01..05 勾选 + 五条注记义务逐条在（D-11-4 扩档/XMP 收窄/TIFF32f 边界/域差集/V2 挂账） | 文件核 |
| 4 | AGENTS.md M2-9 增量节 + export.* 六键入册 | grep |
| 5 | GOAL-STATE 续接点 + C 档终态；TODO 清账 | 文件核 |
| 6 | SUMMARY phase 小结节 + 挂账清单五项 + 测试对账链（2577→终值逐 plan） | 文件核 |
| 7 | 全套回归 0 fail（终态计数 = 对账链终值） | test-direct.sh --all |
| 8 | diff 边界 == front-matter（md + .xcstrings，零第三类源码文件） | `git diff --stat` |

## 风险与边界

- **走查发现 error 级缺陷**：登记 + `fix(m2-9):` 验收批通道（小改动验收方直修
  ——AGENTS.md Phase 执行模型条款）；翻账相应行注记「走查批修复 <SHA>」。
- **GUI 不可用**：走查 1-10 全转待人工登记（不阻塞 T2/T3——证据纪律允许诚实缺
  席，禁假完成）。
- **元数据抽验工具缺席**：exiftool/mdls 均缺时用最小 `sips` + ICC 字节 hex dump
  脚本（scratch 即弃），判据不变。

## 提交约定

- T1 `docs(m2-9): walkthrough evidence records`
- T2 `chore(m2-9): zh catalog reconciliation`
- T3 `docs(m2-9): phase summary and requirements ledger`
- 全英文；body 写 what+why + 同批同步的 md 清单；不 push。

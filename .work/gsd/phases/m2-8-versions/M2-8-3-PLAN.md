---
phase: m2-8
plan: "M2-8-3"
title: "收口（wave 3）——zh-audit 对账补齐（OQ-12 随手键 40–60 键终核）+ 观察项三查（OQ-10：500 链切换耗时/万条历史 .lra IO/百版本列表滚动 + pristine 收窄下游消费面观察）+ REQUIREMENTS M2VER-01..05 翻账（两条晨审追认项注记）+ phase 汇总 + GOAL-STATE/TODO/AGENTS.md 同批"
wave: 3
depends_on: ["M2-8-2"]
autonomous: true
requirements: [M2VER-01, M2VER-02, M2VER-03, M2VER-04, M2VER-05]
files_modified:
  - Resources/Localizable.xcstrings                          # 修改：zh/en 缺口补齐（T1——M2-3-4/M2-4/M2-7 三先例：随手键 + 收尾对账）
  - .work/gsd/phases/m2-8-versions/M2-8-3-SUMMARY.md         # 新建：观察项数字 + phase 汇总（含 M2-8 phase 小结节——M2-6-3 先例）
  - .work/gsd/phases/m2-8-versions/M2-8-3-DECISIONS.md       # 新建：观察项裁决 + 翻账注记底稿（含 CONTEXT OQ-1 迁移代际勘误对账——checker M5）
  - .work/gsd/REQUIREMENTS.md                                # 修改：M2VER-01..05 勾选 + Delivered 终态 + 两条收窄追认注记
  - .work/GOAL-STATE.md                                      # 修改：M2-8 续接点翻账 + C 档第 3 停登记
  - .work/TODO.md                                            # 修改：M2-8 条目勾选/清账
  - AGENTS.md                                                # 修改：M2-8 架构增量节（版本面约定）
  - .work/LESSONS.md                                         # 如踩坑
---

# Plan M2-8-3 — 收口（zh 对账 + 观察项三查 + 翻账 + phase 汇总）

> **性质**：零功能收口 plan——**除 zh String Catalog 增行外零源码 diff**（红线：T3
> `git diff --stat` 出现第三类文件 = 违约）。四块交付：①**zh-audit 对账补齐**（OQ-12
> A：P1/P2 随手键的 phase 尾终核——`Scripts/zh-audit.py --check` PASS 为门）；②**观察
> 项三查**（OQ-10：不设上限不投机的兑现方式 = 实测数字落账，超带才立项专项；外加
> P1 风险节的 pristine 收窄下游消费面观察销账）；③**REQUIREMENTS 翻账**（M2VER-01..05
> + 两条 ROADMAP 字面收窄的晨审追认项注记——OQ-2-A 不落 hash DAG、OQ-3-A fork 并入
> 新建）；④**phase 汇总**（SUMMARY 含 M2-8 phase 小结节 + C 档第 3 停 VALIDATION 登记）。
> 规格锚点 = D-M2-8-CONTEXT-10/12 + REQUIREMENTS M2VER 全族 + ROADMAP M2-8 行。

## 已定裁决（不得重开）

- **D-M2-8-CONTEXT-10（OQ-10 A）**：不设上限、不投机、观察项挂账——本 plan 把账落成
  数字。超带判据 = 观察值与既有编辑操作同数量级（切换/保存可感卡顿 = 超）；**不在本
  plan 内优化**（立项 = 另案）。
- **D-M2-8-CONTEXT-12（OQ-12 A）**：随手键 + 收尾 zh-audit 对账补齐；语言 code 沿 `zh`
  （L025）。
- **翻账注记义务**：M2VER-01/02 交付形态 = ROADMAP 字面收窄（晨审追认项①②）——
  翻账行内显式标注，**不得**静默按字面勾选（用户晨审推翻任一条 = 回 Alcedo DDL 照抄
  线，plan 形状变大，届时重规划）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 zh 对账 = 工具 PASS 为门，禁手补绕过

- `uv run python3 Scripts/zh-audit.py --check`（三断言：源键在册/目录键被引用/zh 完整
  + locale 纪律）；缺口 = `Resources/Localizable.xcstrings` 补行（zh 值允许滞后于英文
  defaultValue 的部分 = 按既有补齐惯例一并补——审计口径以 `--check` 输出为准）。
- P1/P2 落键清单核对法：`git grep -h 'String(localized' <P1/P2 触碰文件>` 汇总 vs
  SUMMARY 键清单——对账表入 DECISIONS（预估 40–60 键 vs 实数）。

### KD-2 观察项三查（OQ-10 销账）+ 下游消费面观察销账

| # | 观察项 | 方法 | 落账 |
|---|---|---|---|
| 1 | 500+ 条链的版本切换耗时 sanity | 程序化：500 链 fixture（P2 T2 同款——checker M5：程序化 scratch 构造、运行时重建，**不入仓**；P3 不引用仓库 fixture 文件，以同款程序化链重建）→ switch ×20 计时均值/峰值（signpost 或 Date 间隔，debug 构建注明口径） | SUMMARY 数字行 |
| 2 | 万条历史 .lra 加载/保存耗时 | 程序化：10000 item 链写盘 → 读回计时（SidecarStore 直测面；注意 ru_maxrss 口径 L045） | SUMMARY 数字行 |
| 3 | Versions 面板百版本列表滚动流畅度 | headless 不可测——真机走查登记（100 版本 fixture 经 debug 入口构造），GUI 不可用 = 待人工项登记 | SUMMARY 或待人工 |

- **判据**：与既有编辑操作同数量级即过（无硬门——OQ-10-B 假精度否决）；超带 = 登记
  E3/专项提案，**不当场优化**。
- **pristine 收窄下游观察销账（P1 风险节）**：程序化构造「.lra 存在∧链空∧versions
  非空」fixture → 走查 `sidecar_present`/`has_edits` backfill/库网格徽标三客户面实测
  表现（期望：判定面按 items/position，版本结构不翻转——P1 KD-6 ②已测，此处为端到端
  复核）；异常 = 登记另案，不当场修。

### KD-3 翻账与 phase 汇总（账实同步批次纪律 §3.1）

- **REQUIREMENTS**：M2VER-01..05 逐条勾选 + 终态行：
  - M2VER-01 `Delivered (narrowed: OQ-2-A——EditCommit hash 图不落库，晨审追认项①)`
  - M2VER-02 `Delivered (narrowed: OQ-3-A——fork-from-root 并入新建，晨审追认项②)`
  - M2VER-03 `Delivered (in-memory: OQ-5-A——ImageEditState 不落库，param 重放兑现)`
  - M2VER-04 `Delivered (delta deferred: OQ-8-A；恢复条 = 哨兵最小面 OQ-9-A)`
  - M2VER-05 `Delivered`
- **M2-8-3-SUMMARY phase 小结节**（M2-6-3-ACCEPTANCE 先例）：三 plan 战果一览 + 测试
  终数（2525 起算的增量对账链）+ 两条追认项醒目位置 + 挂账清单（delta 摘要设施/commit
  图可视化/库内版本选择器/版本缩略图/版本导出——CONTEXT Deferred Ideas 全量转录）+
  M2-9 依赖面交接（ROADMAP 依赖 M2-8 的下游核）。
- **GOAL-STATE**：M2-8 续接点翻账 + **C 档门控第 3 停登记**（M2-8 phase VALIDATION
  签核前停——verify-work 输入 = 三 SUMMARY + 三 DECISIONS + 本 phase 小结）。
- **AGENTS.md**：M2-8 架构增量节（sidecar v7 双键拼写冻结/version_ref reduced DDL/
  swap 单路径纪律/投影 sink 注入惯例——后续 phase 的约定正本）。

## read_first

1. `.work/gsd/phases/m2-8-versions/M2-8-CONTEXT.md`——D10/D12 + 非目标节 + Deferred
   Ideas（挂账清单正本）。
2. `.work/gsd/phases/m2-8-versions/M2-8-1-SUMMARY.md` + `M2-8-2-SUMMARY.md`——键清单/
   测试数字/悬决销账记录。
3. `Scripts/zh-audit.py` 头注——三断言口径；`Resources/Localizable.xcstrings`——
   locale 纪律（zh 非 zh-Hans，L025）。
4. `.work/gsd/REQUIREMENTS.md:73-77`——M2VER 五行正本；`ROADMAP.md:35`——M2-8 行。
5. `.work/GOAL-STATE.md` 续接点节 + C 档门控三条（AGENTS.md「暂停机制」节）。
6. `phases/m2-6-drt/M2-6-3-SUMMARY.md`（或 ACCEPTANCE 文末）——phase 小结节式样先例。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits 全英文、subject ≤72 字符祈使句、
   body 写 what+why + 同批 md 清单——§3.1 原子同步：翻账/汇总/TODO/AGENTS 同批落盘）；
   只 add 申报文件；**不 push**；多段 message 用 `-F`（L040）。
2. **测试纪律**：本 plan 零新测试；每任务全套 suite 绿（`Scripts/test-direct.sh --all`
   报备制）；**回归基线 = M2-8-2 终态计数**（BUNDLE-MAP 行对账）。
3. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
4. **架构红线（本 plan 核心）**：除 `Resources/Localizable.xcstrings` 外**零源码 diff**
   ——`.work/` 与 `AGENTS.md` 的账本 md 除外；`git diff --stat` 出现第三类源码文件 =
   违约（T3 收口核对）。
5. **证据纪律（§3.2/§9）**：观察数字必须程序化实测（禁估算/禁引用他人数字）；GUI 走查
   截图 = 视口关键区 + 图注关键数字；不可自动化项如实登记待人工，禁假完成。
6. **checker 四条（逐条对表）**：①真链实测禁造假（E1）——观察项亲测非引用 P2 数字；
   ②登记（E2）——本 plan 无新测试文件，免；③语义断言可观测（E4）——perf 数字 + 对账
   表成对；④边界核对（M 级）——T3 逐文件对表 + zh 键单源核验（`--check` 工具判）。
7. **收口核对**：T3 `git diff --stat` 与 front-matter 逐文件核对，越界 = 违约。

## Tasks

### T1 zh-audit 对账补齐

- **read_first**：上列 1/2/3。
- **action**
  1. `uv run python3 Scripts/zh-audit.py --check` → 缺口清单。
  2. `Resources/Localizable.xcstrings` 补齐（zh 值 + 引用面核对）；复跑至 PASS。
  3. 对账表（预估 40–60 vs 实数 + 分族清单）落 DECISIONS 底稿。
- **验收标准**
  - [ ] `--check` PASS（输出贴 SUMMARY）；源码 diff 仅 .xcstrings 一文件。

### T2 观察项三查 + 下游消费面销账

- **read_first**：上列 1/2 + P2 T2 的 500 链 fixture 落点。
- **action**
  1. KD-2 表三行逐一实测（1/2 程序化计时；3 真机或待人工登记）；数字入 SUMMARY。
  2. pristine 收窄三客户面端到端复核（KD-2 尾行）；异常登记另案。
- **验收标准**
  - [ ] 三行数字/状态落账；零源码优化行为（超带 = 提案行，不动代码）。

### T3 翻账 + phase 汇总 + 终局核对

- **read_first**：上列 1/4/5/6。
- **action**
  1. REQUIREMENTS 翻账（KD-3 五行 + 注记义务）；GOAL-STATE 续接点 + C 档第 3 停登记；
     TODO 清账；AGENTS.md M2-8 增量节——同批落盘（§3.1）。
  2. `M2-8-3-SUMMARY.md`（含 phase 小结节）+ `M2-8-3-DECISIONS.md`（含 checker M5
     勘误对账：CONTEXT :67 OQ-1「激活走 KD-2 缝（migration v1→v2 + 自动快照）」系
     v1→v2 已被 M2-2 default_look_pending 消费前的旧表述——实做 = **v2→v3**
     （M2-8-1 KD-3）；CONTEXT 正文不改，勘误只在 DECISIONS 侧记账）。
  3. 全套 `--all` 终跑（前报备）+ `git diff --stat` 逐文件核对（纪律 4/7）。
- **验收标准**
  - [ ] 五账同批一致（REQUIREMENTS/GOAL-STATE/TODO/AGENTS/SUMMARY）；diff 边界 =
        md + .xcstrings 申报集；全套 `0 fail`。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | zh-audit `--check` PASS；diff 仅 .xcstrings | 命令输出 + `git diff --stat` |
| 2 | 观察项三行数字落 SUMMARY（500 链切换/万条 IO/百版本滚动——或待人工登记） | SUMMARY 文本核 |
| 3 | pristine 收窄下游三客户面复核结论落账；异常项另案登记 | SUMMARY 文本核 |
| 4 | REQUIREMENTS M2VER-01..05 勾选 + 终态注记（两条追认项醒目） | 文件核 |
| 5 | GOAL-STATE 续接点 + C 档第 3 停登记；TODO 清账；AGENTS.md 增量节 | 文件核 |
| 6 | M2-8-3-SUMMARY 含 phase 小结节 + 挂账清单全量（Deferred Ideas 五项）+ 测试增量对账链 | 文件核 |
| 7 | 全套回归 0 fail（终态计数 = M2-8-2 终态，零新增） | test-direct.sh --all |
| 8 | diff 边界 == front-matter（md + .xcstrings，零第三类源码文件） | `git diff --stat` |

## 风险与边界

- **观察值超带**：切换/IO 耗时若与常规编辑操作差一个数量级 → 只登记专项提案（含复现
  fixture 指针），禁当场优化（OQ-10 纪律；优化立项 = 新 plan）。
- **GUI 走查不可用**（锁屏/无控制台——GOAL-STATE 巡检规则）：观察项 3 与面板手感走查
  如实登记待人工，不阻塞翻账（走查项独立挂账）。
- **翻账被晨审推翻**：追认项①②任一推翻 = M2-8 重新规划（OQ-2-B/OQ-3-B 世界线）——
  本 plan 翻账行已显式标注，届时 REQUIREMENTS 行回退 + 新 plan 集立项；已有交付
  （.lra 真身/swap/面板）不回滚（增量叠加世界线）。
- **zh 值滞后**：`--check` 只判键在册与 locale 纪律，zh 译文质量归人工审——SUMMARY
  注明「译文待人工润色」不视为缺口。

## 提交约定

- T1 `chore(m2-8): zh catalog reconciliation`
- T2 `docs(m2-8): performance observation records`
- T3 `docs(m2-8): phase summary and requirements ledger`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。

## Checker 回注记录（2026-10-01）

checker 批（4E+5M）措辞联动修订，全量记录见 `M2-8-1-PLAN.md` 同名节。本文件三处：
- **m4** 四处 T4→T3（本 plan 无 T4 任务；含 checker 点名两处「T4 收口」）。
- **m5a** KD-2 表行 1 钉 500 链 fixture 复用方式：程序化 scratch 构造、运行时重建、
  不入仓——P3 以同款程序化链重建，不引用仓库 fixture 文件。
- **m5b** CONTEXT :67 OQ-1「migration v1→v2」勘误（实做 v2→v3，M2-8-1 KD-3）列入
  T3 DECISIONS 对账（front-matter 注同步；CONTEXT 正文不改）。

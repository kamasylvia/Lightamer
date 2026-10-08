---
phase: m3-4
plan: "M3-4-02"
title: "M3 VALIDATION 收口波——全套 --all 报备终验轮 + M3 全 phase SC 三列对账（M2GRADE-08/YIYIN-09/小件族/M3-2 研究产物/FSIM-01a..d/FSIM-02）+ REQUIREMENTS/ROADMAP/STATE/TODO/GOAL-STATE 翻账 + 挂账单一清单总汇编 + 「全史瘦身手术第二次」队列项触发确认（前置断言预检）"
wave: 2
depends_on: ["M3-4-01"]
autonomous: true
requirements: ["FSIM-02（验收翻账）", "M3 milestone 收口"]
estimated_tests: "+0（对账波，零新测试）"
test_bundles: [all]
files_modified:
  - .work/gsd/phases/m3-4-latitude/M3-4-02-VALIDATION.md              # 新建（正本；m2-11 体例：status/nyquist/SC 表/挂账总汇编/Per-Plan Map/授权记录/翻账与移交/签核）
  - .work/gsd/REQUIREMENTS.md                                         # 修改：FSIM-01a..d Delivered 翻账 + FSIM-02 Delivered + 光谱不可达注记引用（M3 段终态）
  - .work/gsd/ROADMAP.md                                              # 修改：M3-3 行 ✅ 闭环 + M3-4 行 ✅ 闭环（终态数字）+ M3 milestone 块收口行
  - .work/gsd/STATE.md                                                # 修改：M3-3/M3-4 complete + M3 milestone closed + current_phase + 对账链
  - .work/TODO.md                                                     # 修改：M3-4 [x] + M3 段收口 + 瘦身手术队列行翻账（触发确认态）
  - .work/GOAL-STATE.md                                               # 修改：M3 closed 续接点（→ 瘦身手术触发 → V2/Maintenance·M4 站）+ 队列行触发确认
  - .work/gsd/phases/m3-4-latitude/M3-4-02-DECISIONS.md               # 新建（收口期裁决——如有）
  - AGENTS.md                                                         # 如需：M3 终态行（若 P1 已落增量节则此处零 diff 或仅终态注记）
---

# Plan M3-4-02 — M3 VALIDATION 收口波（wave 2）

> **性质**：doc-only 收口（零源码 diff 红线）。体例 = `phases/m2-11-performance/
> M2-11-VALIDATION.md` 全套（单文档收口，不另跑 gsd-complete-milestone——
> OQ-8-A 先例：里程碑终态由本件 + 翻账批承载，避免双状态源）。
> **翻账只认证据**：SC 三列对账正本 = 本 VALIDATION §SC 表（逐条门值/证据/
> 判定三列，三态判据禁第四态）；数字正本 = 终验轮日志；走查证据 =
> `.work/gui-acceptance/m3-4/` + `m3-3/`（继承）。
> **C 档第 3 停**：verify-work 结论先给用户过目再落签；夜间授权先例
> （M2-11 D-07-3-T5-1 / M3-1「今晚不停」「开跑，不要停」）沿用需**本次授权
> 原话在案**，晨审可推翻。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 报备终验轮（T1）

- `caffeinate -dis Scripts/test-direct.sh --all`（**orchestrator 批准先行 +
  运行中保持监视**——AGENTS 资源监控节；MEMFAIL 8G 机检兜底 + L055 verdict
  ok 判据 + 贴线 bundle（IOP 7654 / IOPParity 5788）MEMFAIL 先查重测顺序
  漂移 ±3% 方差再报）。
- **对账链**：2962 → 3024（M3-1 终）→ 3081/3125（M3-3 两波实测）→ 3152
  （M3-3-03 终）→ **3152 + P1 登记增量 = M3 终值**（两式互证：BUNDLE-MAP
  登记面 × 逐 bundle Executed 运行面；skip 恒 16 零新增）。
- 终验轮结果入 VALIDATION Test Infrastructure 表（逐 bundle 行 + 耗时 +
  峰值 RSS）。

### KD-2 M3 全 phase SC 三列对账（T2，VALIDATION 正本节）

逐 SC 条目三列（判据 / 证据指针 / 终态判定），来源面：

| SC 域 | 正本指针 |
|---|---|
| M3-0（立项与站规格） | 无独立 SC 判据（no-SC 注记行）——立项批产物（V2 站草案 `4f84351` + OQ-V2-1..10 全裁决 `6e265ee` + 规划五正本落账）已随 M3-1 签核清偿；指针索引 = `ROADMAP.md` M3-0 行（✅ 闭环 2026-10-08） |
| M2GRADE-08 | `phases/m3-1-w1/M3-1-01-*`（已 Delivered——本件只终态索引） |
| YIYIN-09 | `phases/m3-1-w1/M3-1-02-*`（同上） |
| 小件族四件（冲突档/peak-ICC/降档/zh 清算） | `phases/m3-1-w1/M3-1-03-*`（同上） |
| M3-2 研究产物（阶段模型/光谱不可达声明/资产 c 态/FSIM-03 注记/M7 spike） | `phases/m3-2-fsim-research/M3-2-CONTEXT.md` + OQ 回批 `e02dcc7` + perf.md §O-1 |
| FSIM-01a（阶段承载） | M3-3-01/02/03 SUMMARY §七 状态表 |
| FSIM-01b（配光自动求解 + 确定性门 + 精确锚语义收口） | 01 §5 + 02 §2 + 03 §四 + M3-4-01 T1/T2 |
| FSIM-01c（染料近似域基线 + golden 主门 + 光谱不可达注记） | 03 T1 + AGENTS「M3-3 架构增量」 |
| FSIM-01d（资产三态 + 许可面） | 01 §2 + NOTICE |
| FSIM-02（宽容度面板 + 教导 + 置位编辑面） | M3-4-01 SUMMARY AC 表 + 走查证据 |
| SC 数字门 | KD-1 终验轮（ROADMAP「M3-4 plan 期定」兑现 = 本件 KD-1/KD-2） |

> checker 回注（2026-10-09）m7：SC 表原缺 M3-0 行（ROADMAP :19 / STATE 均有
> M3-0「立项与站规格」✅ 闭环行）——与「M3 全 phase」声称不符；补 no-SC
> 注记行（判定 = 立项批已随 M3-1 签核清偿 + 指针索引），SC 表覆盖面恢复
> M3-0..M3-4 全相。

- **nyquist 判定**：逐 SC ≥1 机器锚 + ≥1 数字/实证背书；「无证据 ✅」零项；
  Manual-Only 行（click-dead 人工复核等）如实列通道边界理由。
- **挂账单一清单总汇编**（m2-11 §挂账总汇编同式）：底册 = M3-1 VALIDATION
  七项（L057 / D6-O-1 / T3 补走查 / 冲突档跨会话记忆 / M4 coordinator 串行
  化 / D7 verbatim ×2 / O-2 height 帽）+ M3-3 登记（click-dead 真机复核、
  FilmRecord.PresetNames 预设注册面、grid-only 图 disk sidecar filmRecord
  消费面〔导出 UI 归属〕）+ M3-4 新登记（EV 域分箱升级观察项、统计量化
  容差注记、其它 P1 SUMMARY 移交面）——逐项带锚点，禁第四态。

### KD-3 翻账批（T2 同 commit）

- REQUIREMENTS：FSIM-01a..d 四行 + FSIM-02 行翻 Delivered（终态注记 + 证据
  指针；`grep "^- \[ \] \*\*FSIM"` = 0 为门）；M7 spike 注记已结行核对。
- ROADMAP：M3-3 行 ✅（终态 3152/16/0 三波对账链）+ M3-4 行 ✅（M3 终值）+
  Milestone 3 块头收口行。
- STATE：M3-3/M3-4 complete + **M3 milestone closed**（终验 TOTAL 行 +
  对账链 2962→…→终值）+ current_phase = M3 closed → 瘦身手术。
- TODO：M3-4 [x] + M3 段头部收口行 + 队列行翻账（KD-4）。
- GOAL-STATE：续接点 = **M3 closed → 「全史瘦身手术第二次」触发待执行 →
  V2/Maintenance / M4 站**（append-only 追加，不改写历史行）。

### KD-4 「全史瘦身手术第二次」队列项触发确认（T3）

- **触发条件达成确认**（SPEC 正本 = `.work/gsd/research/HISTORY-SLIM-SURGERY-
  SPEC.md`：M3 VALIDATION 落签后、无在飞 worker）：本件落签 = 触发条件
  达成，GOAL-STATE 队列行翻「条件已达成 → 手术批待执行」。
- **前置断言预检（本批亲跑记录进 VALIDATION）**：①零中文 commit message
  基线（SPEC 步骤 1 perl 检查）②`git status` 无在飞 worker 产物
  ③release 分支未检出确认。三项结果如实登记；任一不成立 = 手术批停等
  （记阻塞，不掩盖）。
- **手术本体不在本 plan 半径**：filter-repo + re-add remotes + force push =
  主会话收敛面（SPEC 红线「push 收敛主会话」）；本批只做触发确认 + 预检，
  执行登记为紧随的独立主会话批（L070 家族坑引用在案）。

## read_first

1. `phases/m2-11-performance/M2-11-VALIDATION.md` 全文（体例正本：front-
   matter 字段/Test Infrastructure 表/SC 对照表/挂账总汇编/Per-Plan Map/
   nyquist/授权记录/翻账与移交/签核节）。
2. `phases/m3-1-w1/M3-1-VALIDATION.md`（M3 侧先例 + 挂账单一清单七项底册）
   + `M3-3-03-SUMMARY.md` §七（M3-3 验收锚状态表——翻账输入）+ §八（交接）。
3. `.work/gsd/research/HISTORY-SLIM-SURGERY-SPEC.md` 全文（触发条件/步骤/
   红线——KD-4 预检清单正本）+ `.work/GOAL-STATE.md` 队列行（:12）。
4. `.work/gsd/REQUIREMENTS.md` M3 段（FSIM-01a..d/FSIM-02/M2GRADE-08 现行
   行——翻账对象实位）+ `.work/gsd/ROADMAP.md` Milestone 3 块 + 边界纪律节。
5. `Scripts/test-direct.sh` 用法与机检面 + AGENTS 资源监控节（报备制/
   MEMFAIL 处置/贴线值）+ `.work/LESSONS.md` L055（verdict 判据）。
6. M3-4-01 SUMMARY/DECISIONS（P1 终值对账 + Manual-Only 行 + 新挂账移交面
   ——本件 KD-2 输入）。

## 纪律（强制）

1. **零源码 diff 红线**：`git diff --stat` 对表 = 申报集全 docs（m2-11 签核
   先例机检）；源码/Tests/Scripts 零触碰。
2. **翻账只认证据**：三态判据（Delivered / 未达 / 挂账）禁第四态；数字一律
   指针到亲跑日志/证据文件，禁凭记忆转述。
3. **真路径**：一切 git pathspec 用 `.work/gsd/...` 真路径（.work 旧垫片只读
   不引用）。
4. **历史行不可改写**：GOAL-STATE/STATE/TODO 历史行只追加；带日期状态行
   sed 禁改（M2-11 翻账先例口径）。
5. **C 档第 3 停**：落签前 verify-work 结论呈报；授权原话在案才落签
   （夜间批）；晨审推翻窗注记照抄体例。
6. **提交**：单笔 `docs(m3): milestone 3 validation and closeout`（全英文；
   VALIDATION + 翻账 + 触发确认一并；不 push）。

## Tasks

### T1 报备终验轮（KD-1）

- **action**：orchestrator 批准 → 全套 `--all` 亲跑（监视 + MEMFAIL 机检）
  → 对账链两式互证。
- **验收标准**
  - [ ] 0 fail / 0 MEMFAIL；终值 = 3152 + P1 增量逐 bundle 对表吻合；
        skip 恒 16；L055 verdict ok。

### T2 VALIDATION 文档 + 翻账（KD-2/KD-3）

- **action**：`M3-4-02-VALIDATION.md`（SC 三列全表 + nyquist + 挂账总汇编 +
  Per-Plan Map + 授权记录）+ REQUIREMENTS/ROADMAP/STATE/TODO/GOAL-STATE
  翻账同 commit。
- **验收标准**
  - [ ] SC 表逐条三列齐、指针可达；FSIM 未清零行 = 0；四正本（ROADMAP/
        STATE/TODO/GOAL-STATE）+ REQUIREMENTS 五处一致；挂账单一清单全带锚。

### T3 瘦身手术触发确认（KD-4）

- **action**：SPEC 三前置断言预检亲跑记录 + GOAL-STATE 队列行翻触发态。
- **验收标准**
  - [ ] 预检三项结果在 VALIDATION 在册；队列行翻账「待执行（主会话批）」；
        手术本体零动作（半径红线）。

## 验收标准（AC 总表）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 终验轮 0 fail / 0 MEMFAIL + 对账链两式互证 | T1 日志 |
| 2 | M3 全 phase SC 三列对账齐 + 翻账五正本一致 + FSIM 未清零 = 0 | T2 grep + 对表 |
| 3 | 挂账单一清单总汇编（底册 + 三波新增全带锚） | T2 文档 |
| 4 | 瘦身手术触发确认 + 三前置断言预检在册；手术本体未越半径 | T3 记录 |
| 5 | 零源码 diff + 真路径 + 单笔 docs commit 不 push | git diff --stat |

## 风险与边界

- **终验轮环境型 flake**（SidecarV5 canary / ToneEqual 家族前科）：按恢复
  协议处置（盘/缓存卫生 → 干净轮为准，两轮取后不平均）；产线零 diff 排除
  回归后再判。
- **P1 增量对账失配**：登记面 vs Executed 面不吻合 = 停下逐 bundle 溯源
  （wave-2 错账先例——以文件 `func test` 实数为仲裁）。
- **授权缺位**：C 档第 3 停无授权原话 = 落签停等（文档备齐待签），禁默认
  落签。

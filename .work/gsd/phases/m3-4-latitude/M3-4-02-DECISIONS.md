# M3-4-02-DECISIONS — M3 VALIDATION 收口期裁决正本

> 收口批：2026-10-10 夜间（executor subagent worker；夜间全自动授权「开跑，
> 不要停」在案）。本件只录收口期新裁决，交付面对账 = `M3-4-02-VALIDATION.md`。

## §1 回溯验收门未清 → milestone closure 门控态（本批最大裁决）

- **事实**：用户令 `a2d3c0a`（2026-10-08，编排正本 `OMP-RETRO-QUEUE.md`）=
  omp 回溯二次验收 16 项（M2-0..M2-11 + M3-0/M3-1 三波/M3-2/M3-3 三波）
  **全部 PASS 方进 M3 VALIDATION**；本批落签时点亲核 = 16 项全待办（全仓唯一
  `*-ACCEPTANCE-OMP.md` = M3-4-01 本身双验，不属回溯批）。
- **冲突**：M3-4-02 plan（ authored 早于该指令入库）与执行派遣均直书
  「M3 milestone closed」翻账。
- **裁定**（worker 报备 → orchestrator 2026-10-10 夜间同意）：门就是用户指令
  原义，**不可绕过**——VALIDATION 照签（交付面/SC 对账与门无关；夜间授权在
  案，晨审可推翻），但 milestone closed 名分挂门，五正本带「回溯验收门未清」
  注记；「全史瘦身手术第二次」触发挂「门清后生效」。回溯批 = 主会话串行 omp
  接力；全 PASS 后翻正注记（两行级改动）+ 触发手术。
- **翻正清单（门清后主会话执行）**：STATE `current_phase`/`status` 门控措辞、
  GOAL-STATE 队列行触发态、ROADMAP 块头 + M3-4 行门注记、TODO M3 头部 +
  手术队列行——共五处注记行，无历史行改写。

## §2 瘦身手术三前置断言预检结果（KD-4/T3，亲跑 2026-10-10）

1. **断言①（零中文 commit message）= FAIL**：`git log --format='%B' main |
   perl CJK 扫描` 命中 3 枚——`2d580d8`（body 内引号 UI 串「显示胶片面板/
   显示侧边栏」）、`ca714f9`（「checker 回注」）、`c5afe0d`（「checker 回注/
   根治」）。性质 = 英文 body 内嵌引号 zh 串/术语（全史重写批之后的增量
   commit 未被既有流程覆盖，同族坑再现）。处置 = 手术批步骤 1 前置 msg 重写
   小批（主会话；perl 判据同 SPEC；sha-rewrite-map 增补）。
2. **断言②（无在飞 worker 产物）= PASS**：untracked 四项定性——
   `M3-4-01-ACCEPTANCE-OMP.md`（已完成证据件，本批入库）/
   `research/dt-clone-archive/`（2026-10-07 历史调研残留 2 文件 20KB，非在飞，
   留晨审归类，本批不收）/ `09-3-tiers-*.jpg` ×2（存量脏文件，GOAL-STATE
   已登记「不入本批」）。
3. **断言③（release 分支未检出）= PASS**：主 worktree 在 `main`；`release`
   检出于独立 worktree `Lightamer-release`（SPEC 括注「独立 worktree 无碍」）。

## §3 账面死 SHA 四枚（V12）——全史重写连动缺口登记

- `4f84351`/`6e265ee`/`b4049b8`/`08dd061` 现世系不存在（`git cat-file` fatal）。
- 根因 = 2026-10-07/08 两轮 msg filter-branch 连动重写后代 SHA，而
  `sha-rewrite-map.txt` 只录 message 实变的 165 对；四个被引 commit（V2 草案 /
  OQ-V2 裁决 / M3-2 research 定稿 / ToneEqual stateLock 修复）message 未变
  故无 map 行。
- 现世系对照（subject 精确匹配反查）：`4f84351`→`06ffb91`、`6e265ee`→
  `ffe0d9e`、`b4049b8`→`b4049b7`、`08dd061`→`e50b291`。
- 处置 = 本批零历史行改写（ROADMAP/REQUIREMENTS/TODO 既有引用原样保留）；
  对照表入 VALIDATION 挂账 V12 + 本件，手术批步骤 6 sha-rewrite-map 增补吸收。

## §4 M3-4-02-DECISIONS 单独成文说明

plan front-matter 申报「新建（收口期裁决——如有）」：本批收口期裁决共三项
（门控态 / 预检 / 死 SHA），均有后续主会话动作面，独立成文便于门清批与手术批
直接消费；SC 对账与签核语义仍在 VALIDATION 正本，不在此重复。

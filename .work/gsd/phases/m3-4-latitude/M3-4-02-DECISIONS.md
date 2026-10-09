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

## §5 门清翻正 + 手术批执行记录（2026-10-10 夜收官批 subagent，本节为 §1-§3 的消账节）

- **§1 门控态 → 已消账**：omp 回溯二次验收 16/16 全 PASS（checkpoint
  `81114d4`——msg 补课后现世 `5f6860d`，sha-rewrite-map 解析）；翻正清单五处
  全落（VALIDATION frontmatter + 置顶注记 / STATE frontmatter+正文+Ledger
  M3-4 行 / ROADMAP 块头+M3-4 行 / TODO M3 头部+手术队列行 / GOAL-STATE
  队列行+新续接点）+ 本节，共六处；历史行零改写。**M3 milestone closed
  名分生效。**
- **§2 断言① → 已补课**：3 枚 commit msg 英文化（`2d580d8`→`9102975`/
  `ca714f9`→`8f2f84f`/`c5afe0d`→`96d2937`，filter-branch --msg-filter；
  perl 模式须 `-Mutf8`，首跑缺它静默不命中 = "Ref unchanged"，L072）；
  后代 57 枚 SHA 联动（subject-exact 配对 57/57，边界 `158a4680` 以下零
  变化）全量入 map；全史 CJK 复扫 CLEAN；ADO `--force-with-lease` 收敛
  `0e27519..5f6860d`（github 公开仓未动）。
- **§3 死 SHA → map 消账 + 链式更新**：`b4049b7`（原判 b4049b8 现世系）
  本身在 57 枚重写集内 → 现世系链至 `b412addb`；其余三枚（06ffb91/ffe0d9e/
  e50b291）不在集内仍活。map 以「死 SHA 短式 → 现活 full SHA」单跳入账。
- **手术批（步骤 3）停手——SPEC 前提实测证伪**：strip 集 = tip 不可达
  （41 blob / 2.16MB，无一路径命中规则）∩ 规则集 = **0 候选**；SPEC 预期
  对象（LUTs「旧」314MB / 归档证据历史版）实为 tip 在册内容（pack
  971.73MiB = .work/gsd/phases 882MB + Resources/LUTs 314MB + gui-acceptance
  ~300MB，5954/5995 blob tip 可达）——「907→400-500MB」数学不可达。按红线
  （tip blob 禁入 strip 集）执行 = 零收益全史重写，停手；filter-repo 未跑
  （remotes/release `ec389f2`/worktree 零扰动）。pack 瘦身转决策项
  （tip 证据资产出仓：LFS/外部仓/降采样归档），挂晨审另立 SPEC。
- **验证五项**：size-pack 971.73MiB（手术未执行，如实不变）/ 零 CJK CLEAN
  / input 240M + Tests/Fixtures + Resources/TestFixtures 在盘 / commit 数
  1237 前后一致 / release SHA `ec389f2` 不变。

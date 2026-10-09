# M3-0「立项与站规格」回溯二次验收报告（omp 独立二次验收）

- 对象：M3-0 立项与站规格（无独立 phase 目录；交付 = V2 站草案定稿 + OQ-V2-1..10 全按推荐裁决 + 规划五正本落账）
- 验收形态：五正本落账一致 + 用户预裁「按推荐」在案（C 档快速通道）；规划/文档面，无测试可跑，未跑测试，未实机
- 验收员：omp（零共享上下文二次验收）；日期 2026-10-09；HEAD `44a6a95`（2026-10-09）
- 方法：五正本 + 两正本（V2-PROPOSAL.md / OQ.md）全文亲读；裁决 commits `git show` 亲读；STATE/GOAL-STATE/TODO 行级对表；`git log -S` 追溯归档去向

## 结论头

`PASS / 0 error + 3 minor`

三 minor 均为记账/轮转层（死 SHA 引用、GOAL-STATE 轮转归档、落账动作与预裁生效日差一天），零实质分歧：五正本对 M3 站定义表述一致，OQ-V2-1..10 裁决值逐条 == 推荐值，commits 零越界文件。

## 一、抽查点 1：五正本落账一致性（PASS）

M3 站定义 = 胶片暗房 = 方案 A（M2GRADE-08 W1 前置 + FSIM-01/02 主打 + 搭车族），五处表述一致：

| 正本 | 位置 | 表述 | 日期 |
|---|---|---|---|
| ROADMAP M3 表 | `ROADMAP.md:10-12,19` | Milestone 3 胶片暗房；M3 = 方案 A；M3-0 行记草案定稿 + 全按推荐裁决 + 五正本清单 | 2026-10-08 立项 |
| REQUIREMENTS V2 节 | `REQUIREMENTS.md:278,380-391,397-398` | FSIM-01 →M3 主打 + 01a..d 草案原文保留；FSIM-02 →M3-W3 尾；FSIM-03 →M3-2 并入；M2GRADE-08 →M3-W1；RASTER-IN-01 →M4 | 2026-10-08 V2 站立项 |
| STATE M3 段 | `STATE.md:63-78` | M3-0 complete 行（五正本清单）+ Notes 行（方案 A / B 滚 M4 / ALCE-02-03 M4 / Mertens M4-W2 / TRACK M4 / PANO M5） | 2026-10-08 chartered |
| GOAL-STATE 续接点 | 归档见 minor-2 | 立项追加行原文记方案 A + 五正本清单 + M3-1 起草下一步 | 2026-10-08 |
| TODO 头部行 | `TODO.md:348-350` | M3 头部行（方案 A + 预裁按推荐）+ 状态行（波次四段 + 边界五项 + 隔离纪律） | 2026-10-08 立项 |

- 日期链：账面立项日五处均为 2026-10-08，一致。落账动作 commit 时间戳为 2026-10-07（见 minor-3），body 已明示预裁生效日 2026-10-08，口径自洽。
- 立项原文可读性：ROADMAP M3-1 行经 M3-1-VALIDATION 批续写为闭环行，但「原 Goal」前缀保留立项原文；REQUIREMENTS FSIM-01a..d 草案原文保留、Delivered 子行为 append 式（原行字节零改写）；STATE/ROADMAP M3-0 行均为追加式闭环注记。零改写历史行。
- 兑现旁证：M3-1/M3-2/M3-3/M3-4 随后交付闭环（终值 3174/16/0），立项兑现成立。

## 二、抽查点 2：OQ 裁决兑现（PASS，全 10 条逐条核）

裁决记录正本 = `OQ.md:75-77`：OQ-V2-1..10 全部按推荐采纳，M3 = 方案 A。逐条「推荐 → 落账裁决值」对照：

| OQ | 推荐（OQ.md） | 落账裁决值 | 一致 |
|---|---|---|---|
| V2-1 主打方向 | A 胶片暗房（OQ.md:10） | ROADMAP.md:12「M3 = 方案 A『胶片暗房』」；STATE.md:78 plan A | ✓ |
| V2-2 Maintenance 提级 | ② M7 spike 搭车，M1/M6 待触发（OQ.md:16） | ROADMAP M3-2 行「M7 spike + FSIM-03 注记搭车」；范围红线无 M1/M6 | ✓ |
| V2-3 denoise 降档语义 | ① M3 搭车（OQ.md:22） | STATE.md:68 M3-1 行含 denoise drag-down semantics；TODO.md:350 波次含 denoise；ROADMAP M3-1 闭环行仍命中 denoise | ✓ |
| V2-4 RASTER-IN 与 M1 捆绑 | ② 不捆绑（OQ.md:28） | V2-PROPOSAL.md:105「不随 RASTER-IN 捆绑」；M3 范围无 M1 | ✓ |
| V2-5 EXR 依赖 | ③ EXR 砍出首批（OQ.md:34） | ROADMAP.md:12 范围红线 ALCE-02 不入 M3 | ✓ |
| V2-6 TRACK 时机 | M4（OQ.md:40） | ROADMAP.md:12「TRACK M4」；STATE.md:78 | ✓ |
| V2-7 YIYIN-09 | ① M3-W1 同批（OQ.md:46） | REQUIREMENTS.md:278「→ M3-W1」 | ✓ |
| V2-8 合成族时机 | ② Mertens M4、PANO M5（OQ.md:52） | ROADMAP.md:12；STATE.md:78 | ✓ |
| V2-9 冲突档选择器 | ① M3-W1 批内修（OQ.md:58） | M3-1-03 交付 + M2-9 挂账#4 关闭（ROADMAP M3-1 行） | ✓ |
| V2-10 CC BY-SA 资产 | ① research 环裁（OQ.md:64） | ROADMAP M3-2 行「资产取舍三态对比裁决（OQ-V2-10…)」 | ✓ |

裁决值 == 推荐值 10/10，无「记按推荐实不按」项。

## 三、抽查点 3：候选池边界（PASS，无孤儿条目）

- M4/M5 走修复批不入本站：V2-PROPOSAL.md:6 边界行明示；ROADMAP.md:25 边界纪律行承接（FINDING-F L057 家族 + ToneEqual 隔离纪律）。✓
- ALCE-01/04/05/06/07 提级 V1 不重复立项：V2-PROPOSAL.md:6 明示（M2-5/6/8/10 交付）；REQUIREMENTS.md:6 顶部重定义注记「V2 节 ALCE-01/04/05/06/07 随重定义提级 V1」。✓
- 边界项落位对表（REQUIREMENTS ↔ ROADMAP）：
  - RASTER-IN-01 → REQUIREMENTS.md:397「→ M4」✓
  - TRACK-01..05（REQUIREMENTS.md:640-644，无 →M4 行内注记）→ 落位在 ROADMAP.md:12 范围红线「TRACK M4」+ STATE.md:78。charter commit body（`88ebb8c`）明确注记范围仅 FSIM/M2GRADE-08/YIYIN-09/RASTER-IN-01，TRACK 等落位在范围红线行——有落位，非孤儿。
  - IOP-HDR-06 / IOP-PANO-01（REQUIREMENTS.md:373-374）→ 落位同上（Mertens M4-W2 / PANO M5）。非孤儿。
  - M2-denoise（无独立 REQUIREMENTS 行，OQ-V2-3 的 M2 栏事项）→ 落位在 STATE.md:68 M3-1 行 + TODO.md:350 波次行。非孤儿。
  - ALCE-02/03（REQUIREMENTS.md:651-652）→ 落位在 ROADMAP.md:12 范围红线（M4）。非孤儿。
- obs-1：ALCE-01..07 checkbox 仍 `[ ]` 未翻勾——OQ.md:71 附注已声明「REQUIREMENTS ALCE 行翻勾注记归下批翻账（非本文范围）」，非 M3-0 范围，不判。

## 四、抽查点 4：git 机检（PASS，零越界；死 SHA 见 minor-1）

申报 `4f84351` / `6e265ee` 在当前历史不可解析（`git show` fatal）。此为已登记的账面死 SHA：对照登记在 TODO.md:408 与 GOAL-STATE.md:14（sha-rewrite-map 前置事项），现世系 = `06ffb91` / `ffe0d9e`。亲核现世系：

- `06ffb91`（草案定稿，现世之 4f84351）：`docs(v2-station): draft V2/Maintenance station proposal with M3 combos`，--stat = 2 文件（`v2-station/OQ.md` +73，`v2-station/V2-PROPOSAL.md` +173），246 insertions。零越界。✓
- `ffe0d9e`（裁决记录，现世之 6e265ee）：`docs(v2-station): record all-recommendations ruling`，--stat = 1 文件（`OQ.md` +4 行裁决记录节）。零越界。✓
- `88ebb8c`（五正本落账，本次验收对象的主 commit）：`docs(m3): charter Milestone 3 film darkroom`，--stat = 5 文件（GOAL-STATE +1 / TODO +11 / REQUIREMENTS +16-6 / ROADMAP +19-1 / STATE +29-8），body 自述 docs-only。零源码 diff，零越界。✓
- 内容漂移：`git diff 06ffb91 HEAD -- v2-station/` 仅 = `ffe0d9e` 的 +4 行裁决记录；V2-PROPOSAL.md 自定稿零改动。✓
- 落账内容抽核：`88ebb8c` 的 REQUIREMENTS diff 落「→ M3」注记 7 行（YIYIN-09/FSIM-01+01a..d/FSIM-02/FSIM-03/RASTER-IN-01/M2GRADE-08）与今日账面逐字一致；STATE diff 落 M3 段 + Notes 行与今日一致；TODO diff 落 M3 头部块与今日头部一致。

## 五、minor 清单（3 项，均不阻塞）

- minor-1：账面 SHA `4f84351`/`6e265ee` 在当前历史不可解析（死 SHA）。现世系 `06ffb91`/`ffe0d9e` 内容与申报面逐项核对一致；对照已登记（TODO.md:408、GOAL-STATE.md:14），sha-rewrite-map 前置事项立案。建议手术批 msg 重写时同步刷新五正本正文引用。
- minor-2：GOAL-STATE 的 M3 立项追加行（`88ebb8c` 写入）经 `ae1d257` 台账轮转附带归档，当前 GOAL-STATE 无 M3 立项续接行。归档正本 `.work/gsd/phases/_archive/GOAL-STATE-continuation-archive-m1-m2.md` 在册（`grep -c` = 1，内容逐字），非丢失。归档动作本身为正常轮转（22MB 瘦身）。
- minor-3：三 commit 落账动作时间戳 2026-10-07 vs 账面立项日 2026-10-08 差一天。三 body 均明示预裁生效日 2026-10-08（`88ebb8c` body 首行），属「先落账、预裁追认」口径；账面日期链五处一致。非矛盾。

## 六、与首验/申报分歧点

- M3-0 无独立首验报告（无 phase 目录、无 ACCEPTANCE 文件）；申报面 = ROADMAP M3-0 行（`ROADMAP.md:19`）「五正本落账一致 ✓；用户预裁『按推荐』在案（C 档快速通道）」。
- 分歧：无实质分歧。申报的「五正本落账一致」成立（§一）；「全按推荐」成立（§二 10/10）。三 minor 均为二次验收新增记账层发现，不推翻申报结论。

## 七、会话卫生

- 只读验收：除本报告文件外零写入；未修改源码与既有文档；未 push；未跑测试（规划面豁免）。
- 报告落盘：`.work/gsd/phases/m3-4-latitude/M3-0-ACCEPTANCE-OMP.md`（本文件）。

OMP-VERDICT: PASS

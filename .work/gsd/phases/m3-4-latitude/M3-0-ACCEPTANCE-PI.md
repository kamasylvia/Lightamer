# M3-0「立项与站规格」回溯二次验收报告（PI 路，双路并发终验）

- 验收员：PI（零共享上下文独立复核）；日期 2026-10-10（批次口径）；HEAD `f2969d24`
- 方法：七正本全文亲读 + 上一轮 R1/R2 报告抽查点独立重验（file:line 读码 / git show·rev-parse·diff / grep·wc 机检）
- 口径：HEAD 远超 M3 收官（M4/M5/M6 已入账）；M4-0 证据分仓 filter-repo 后第一/二代 SHA 全系换代，逐处标「后演进，不记账」

## 结论头

`PASS / 0 error + 2 minor`

## 一、重验：五正本落账一致性（PASS）

- ROADMAP `ROADMAP.md:10-12,19`：M3 块头「胶片暗房【2026-10-08 立项（V2 站方案 A）】」+ 范围红线行（方案 B/EXR/UltraHDR/TRACK/Mertens/PANO 一律不入 M3）+ M3-0 ✅ 闭环行（V2 草案定稿 + 全按推荐裁决 + 五正本清单逐字）。立项日 = 2026-10-08。
- REQUIREMENTS：`REQUIREMENTS.md:278`（YIYIN-09 → M3-W1）、`:380-391`（FSIM-01 → M3 主打 + 01a..d 草案原文保留 + FSIM-02 → M3-W3 尾 + FSIM-03 → M3-2 并入）、`:397`（RASTER-IN-01 → M4）、`:399`（M2GRADE-08 → M3-W1 前置）——亲读逐条在册；`grep -c "→ M3"` = 5。
- STATE `STATE.md:74-78`：M3-0 complete 行（五正本清单）+ M3-1..M3-4 逐行（3024/3152/3174 终值）+ `:116` Notes（方案 A / plan B 滚 M4 / ALCE-02-03 M4 / Mertens M4-W2 / TRACK M4 / PANO M5）。
- TODO `TODO.md:390-392`：M3 头部行（2026-10-08 立项 + 预裁按推荐可推翻）+ 状态行（规格正本双 SHA + 波次四段 + 边界五项 + 隔离纪律）；R1 所引 `TODO.md:348-350` 现漂移至 390-392 = M4/M5/M6 块追加所致，后演进，不记账。
- GOAL-STATE：当前无 M3 立项续接行（已轮转）；归档正本 `phases/_archive/GOAL-STATE-continuation-archive-m1-m2.md` 在册（`grep -c "方案 A"` = 1），非丢失。
- 历史行 append-only：`grep -c "原 Goal" ROADMAP.md` = 8（M3-1..M3-4 原立项 Goal 前缀保留）；`grep -c "^- \[ \] \*\*FSIM" REQUIREMENTS.md` = 0（草案行原样、Delivered 子行为 append）。兑现旁证：M3-1..M3-4 全闭环 + M3 终值 3174/16/0（STATE:78 + TODO:390 逐字互证）。

## 二、重验：OQ-V2-1..10 裁决 == 推荐（PASS，10/10）

- 推荐值（`OQ.md:10,16,22,28,34,40,46,52,58,64` 亲读）：V2-1 A / V2-2 ② / V2-3 ① / V2-4 ② / V2-5 ③ / V2-6 M4 / V2-7 ① / V2-8 ② / V2-9 ① / V2-10 ①；裁决记录 `OQ.md:75-77`「OQ-V2-1..10 全部按推荐采纳：M3 = 方案 A」。与 R1/R2 摘录逐条一致，独立复核无出入。
- 落账抽核（独立取证）：V2-1 → ROADMAP:12「M3 = 方案 A」+ STATE:116 ✓；V2-2 → ROADMAP M3-2 行「M7 spike + FSIM-03 注记搭车」、M1/M6 无立项行（V2-PROPOSAL 触发条件档维持「待触发」）✓；V2-3 → STATE:75 M3-1 行 denoise drag-down + TODO:394 交付行 ✓；V2-4 → `V2-PROPOSAL.md:105`「**不随 RASTER-IN 捆绑**（OQ-4）」✓；V2-5 → ROADMAP:12 范围红线 EXR 不入 M3 ✓；V2-6 → ROADMAP:12「TRACK M4」+ STATE:116 ✓；V2-7 → REQUIREMENTS:278 ✓；V2-8 → ROADMAP:12「Mertens M4-W2；PANO M5」✓；V2-9 → ROADMAP M3-1 行「M2-9 挂账#4 关闭」✓；V2-10 → ROADMAP M3-2 行「资产取舍三态对比裁决（OQ-V2-10）」✓。10/10 无「记按推荐实不按」项。

## 三、重验：候选池边界（PASS，无孤儿条目）

- `V2-PROPOSAL.md:6` 亲读：M4/M5 修复批不入本站 + ALCE-01/04/05/06/07 提级 V1 不重复立项，双明示 ✓。
- 边界项落位对表：RASTER-IN-01 → REQUIREMENTS:397「→ M4」✓；TRACK/IOP-HDR-06/IOP-PANO-01/ALCE-02/03 → ROADMAP:12 范围红线 + STATE:116 ✓；M2-denoise → STATE:75 M3-1 行 + TODO:392 波次 ✓；ALCE checkbox 未翻勾有 `OQ.md:71` 附注豁免（非本文范围），不判。

## 四、重验：git 机检（PASS，零越界）

- SHA 世代独立亲测：第一代 `4f84351`/`6e265ee` 与第二代 `06ffb91`/`ffe0d9e`/`88ebb8c` 在当前历史 `git rev-parse --verify` 全 DEAD（第一代 = S2 msg 手术换代、第二代 = M4-0 pathstrip 手术换代——均后演进，不记账）；**第三代现世 holder 三枚全 ALIVE**：`c2a1fc59`/`83288458`/`ad66f0f6`，与 R2 独立定位结果一致。
- `git show --stat` 亲核三枚（均 2026-10-07）：`c2a1fc59` 草案定稿 = OQ.md +73 / V2-PROPOSAL.md +173（2 文件 246 insertions）；`83288458` 裁决记录 = OQ.md +4；`ad66f0f6` 五正本落账 = GOAL-STATE +1 / TODO +11 / REQUIREMENTS +16-6 / ROADMAP +19-1 / STATE +29-8（5 文件，`git show --name-status` 亲证恰五正本、零源码文件）——与 R1/R2 描述逐项吻合，零越界。
- 零漂移：`git diff c2a1fc59 HEAD -- …/v2-station/V2-PROPOSAL.md` 空输出（自定稿零改动）；`git diff 83288458 HEAD -- …/OQ.md` 空输出（裁决 +4 后零改动）。

## 五、minor 清单（2 项，均记账层，不阻塞）

- minor-1：五正本正文仍引第一代死 SHA（`4f84351`/`6e265ee`，命中 ROADMAP:12/19、TODO:392/450、STATE:74、GOAL-STATE 多行）。死链可经两跳 map 完整解析（`research/sha-rewrite-map.txt:234-235` gen1→gen2 + `research/sha-rewrite-map-2026-10-10-pathstrip-commit-map.txt:29,676,1270` gen2→gen3，亲证在册），但正文引用需两跳查表。可修性：小修（手术批刷新正文引用或补一行链式对照注记；R1 已建议未执行）。
- minor-2：三枚落账 commit 时间戳 2026-10-07（`git show --date=short` 亲证）vs 账面立项日五处一致为 2026-10-08——charter body 明示预裁生效日 2026-10-08，「先落账、预裁追认」口径自洽，非矛盾（同 R1 minor-3 / R2 minor-2）。

## 六、分歧项（与上一轮 R1/R2 报告的判定差异）

- 分歧 1（对 R1 minor-2，同意 R2 降级）：GOAL-STATE M3 立项行轮转归档经独立 `grep -c "方案 A"`（=1，归档正本在册逐字）+ 正常 22MB 瘦身轮转定性，非缺陷，不判 minor。本轮 minor 计 2（R1 为 3，R2 为 2），结论头 PASS 三轮一致。
- 分歧 2（对 R2 minor-1 的补强修正）：R2 表述「账面 SHA 三代全死」未提解析链路；本轮亲证两跳 map（sha-rewrite-map.txt + pathstrip-commit-map.txt）覆盖全链 4f84351→06ffb91→c2a1fc59 等三对，死引用可机检解析——minor-1 性质不变（仍属正文引用记账债），非信息丢失。
- 分歧 3（观察，非判项）：R2 头部自记日期 2026-10-10 与其所引 HEAD `f2969d24` 的 commit 日期 2026-10-13 不一致（R2 执行时工作树已含 M5/M6 收官内容）——R2 头部日期系任务书模板日期，不影响其任何判定成立。
- 其余：与 R1/R2 零实质分歧——「五正本一致」「OQ 10/10 按推荐」「零越界」三结论独立复核均成立；R1 所引行号漂移（TODO 348→390 等）= M4/M5/M6 记账追加，后演进，不记账。

## 七、会话卫生

- 只读验收：除本报告文件外零写入；未跑测试（规划面豁免，引用 R1/R2/VALIDATION 已记终值 3174/16/0）；未实机 GUI；未发起网络动作。

PI-VERDICT: PASS

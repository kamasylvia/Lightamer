# M3-0「立项与站规格」回溯二次验收报告（OMP R2，双路并发终验）

- 验收员：OMP（零共享上下文独立复核）；日期 2026-10-10；HEAD `f2969d24`
- 方法：七正本全文亲读 + 上一轮 R1 报告抽查点独立重验（机检取证）+ 现世 commits `git show` 亲核
- 口径：HEAD 远超 M3 收官；M4-0 证据分仓 filter-repo 后 SHA 全系换代，下文逐处标「后演进，不记账」

## 结论头

`PASS / 0 error + 2 minor`

## 一、重验 R1§一：五正本落账一致性（PASS）

- `ROADMAP.md:10,12,19`：M3=方案 A「胶片暗房」+ 范围红线（方案 B/EXR/UltraHDR/TRACK/Mertens/PANO 不入 M3）+ M3-0 闭环行（五正本清单逐字）。立项日五处均为 2026-10-08。
- `REQUIREMENTS.md:278`（YIYIN-09→M3-W1）、`:380-391`（FSIM-01→M3 主打+01a..d 草案原文保留、FSIM-02→M3-W3 尾、FSIM-03→M3-2 并入）、`:397`（RASTER-IN-01→M4）、`:399`（M2GRADE-08→M3-W1 前置）——亲读逐条在册。
- `STATE.md:63-78`：M3 Ledger 表 M3-0 complete 行（五正本清单）+ M3-2 行 M7 spike 搭车 + Notes（plan A / TRACK M4 / Mertens M4-W2 / PANO M5）。
- `TODO.md:390-392`：M3 头部行（方案 A + 预裁按推荐）+ 状态行（规格正本双 SHA + 波次 + 边界）。`GOAL-STATE.md` 当前无 M3 立项续接行（已轮转，见下）。
- 历史行 append-only：ROADMAP M3-1..M3-4 行「原 Goal」前缀保留立项原文；REQUIREMENTS FSIM-01a..d 草案行原样、Delivered 子行为 append；兑现旁证 M3 终值 3174/16/0（STATE M3-4 行；R1 已引，现状一致）。

## 二、重验 R1§二：OQ-V2-1..10 裁决==推荐（PASS，10/10）

- `OQ.md:1-77` 全文亲读：推荐值 = V2-1 A / V2-2 ② / V2-3 ① / V2-4 ② / V2-5 ③ / V2-6 M4 / V2-7 ① / V2-8 ② / V2-9 ① / V2-10 ①，与 R1 摘录逐条一致；`OQ.md:75-77` 裁决记录「全部按推荐采纳：M3=方案 A」。
- 落账抽核（独立取证）：V2-1→ROADMAP:12「M3=方案 A」✓；V2-5/6/8→ROADMAP:12 范围红线（ALCE-02/TRACK M4/Mertens M4-W2/PANO M5）+ STATE:78 ✓；V2-7→REQUIREMENTS:278 ✓；V2-3→STATE M3-1 行 denoise drag-down ✓；V2-4→V2-PROPOSAL:105「不随 RASTER-IN 捆绑」✓；V2-9→ROADMAP M3-1 行挂账#4 关闭 ✓；V2-10→ROADMAP M3-2 行资产三态裁决 ✓；V2-2→ROADMAP M3-2 行 M7 spike 搭车 ✓。

## 三、重验 R1§三：候选池边界（PASS，无孤儿）

- `V2-PROPOSAL.md:6` 亲读：M4/M5 修复批不入本站 + ALCE-01/04/05/06/07 提级 V1 不重复立项，均有明示 ✓。
- RASTER-IN-01→REQUIREMENTS:397「→M4」✓；TRACK/IOP-HDR-06/IOP-PANO-01/ALCE-02/03 落位 ROADMAP:12 范围红线 + STATE:78 ✓；M2-denoise 落位 STATE M3-1 行 + TODO:392 波次 ✓。
- obs-1 复核：ALCE checkbox 未翻勾有 `OQ.md:71` 附注豁免（非本文范围），同意 R1 不判。

## 四、重验 R1§四：git 机检（PASS，零越界；SHA 系已换代）

- R1 申报 `4f84351`/`6e265ee` + R1 现世系 `06ffb91`/`ffe0d9e`/`88ebb8c`：当前历史**五枚全部不可解析**（`git rev-parse --verify` 全 DEAD）。「后演进，不记账」：M4-0 证据分仓 filter-repo 改写全史，R1 时代 holder 随之失效。
- 现世 holder（独立定位，`git log --grep/-S`）：`c2a1fc59`（草案定稿，OQ.md +73 + V2-PROPOSAL.md +173，246 insertions，2026-10-07）✓、`83288458`（裁决记录，OQ.md +4，2026-10-07）✓、`ad66f0f6`（五正本落账，GOAL-STATE+1/TODO+11/REQUIREMENTS+16-6/ROADMAP+19-1/STATE+29-8，2026-10-07）✓——三枚 --stat 形态与 R1 描述逐项吻合，零源码 diff，零越界。
- 零漂移：`git diff c2a1fc59 HEAD -- V2-PROPOSAL.md` 空输出（自定稿零改动）✓。
- 落账时间戳三枚均为 2026-10-07 vs 账面立项日 2026-10-08（minor-2 延续）。

## 五、minor 清单（2 项，均记账层，不阻塞）

- minor-1：账面 SHA 三代全死（原文 `4f84351`/`6e265ee` → R1 代 `06ffb91`/`ffe0d9e`/`88ebb8c` → 现世 `c2a1fc59`/`83288458`/`ad66f0f6`）。ROADMAP:12/19、TODO:392 仍引第一代死 SHA。可修性：小修（手术批 msg 重写时刷新正文引用；R1 已建议，未执行）。
- minor-2：落账动作 2026-10-07 vs 账面立项日 2026-10-08 差一天；charter body 明示预裁生效日，口径自洽。非矛盾。

## 六、分歧项（与 R1 报告的判定差异）

- 分歧 1（R1 minor-2 降级为观察）：GOAL-STATE 立项行轮转归档经 `grep -c '方案 A' _archive/GOAL-STATE-continuation-archive-m1-m2.md`=1 确认在册逐字 + 正常 22MB 瘦身轮转 = 非缺陷，不计 minor。本轮 minor 数 2（R1 为 3），结论头 PASS 不变。
- 分歧 2（新增后演进注记）：R1 认定的现世系三 SHA 已全部失效，新 holder 已独立定位并逐项核对 --stat 一致。属 M4-0 改写史后演进，不记账、不推翻 R1 当时结论。
- 其余：与 R1 零实质分歧；R1「五正本一致」「10/10 按推荐」「零越界」三结论独立复核成立。

## 七、会话卫生

- 只读验收：除本报告文件外零写入；未跑测试（规划面豁免）；未实机；未发起网络动作。
- 报告落盘：`.work/gsd/phases/m3-4-latitude/M3-0-ACCEPTANCE-OMP-R2.md`（本文件）。

OMP-VERDICT: PASS

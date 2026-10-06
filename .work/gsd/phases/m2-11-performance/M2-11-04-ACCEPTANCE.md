# M2-11-04 ACCEPTANCE — PERF-02 内存三分法落地 + M2PERF 重述批验收（2026-10-07 验收 subagent，零共享上下文实测核验）

## 结论

**PASS / 0 error + 2 minor**（已修，随验收批入库）。

- minor-1：perf.md §PERF-02 R1 T0 = 2391 应为 **2392**（正本
  `r1-footprint-t0.txt` 1MB 手误；T0 参考列不设门，主判据 T60 列原值无误）。
- minor-2：perf.md resident(T60) 参考列 R1/R2 = 1.64/1.11 GB 与正本 rss_kb 换算
  不符（1681312 KB = 1.68 GB / 1137152 KB = 1.14 GB 十进制口径，R3 1.10 一致）——
  已对照正本勘误并加验收复测注记。两处均参考列，**中位 1975MB ≤3GB 判定不受影响**。

---

## 一、GUI footprint 独立复测（验收机亲跑 R4 轮，非转述）

按 SUMMARY 场景脚本 `profile/memprof-round.sh` 亲跑一轮（fresh probe 建项目 →
GUI 启动 → Open Recent → 双击开 100MP RAF → Z/滚轮平移/F → 色温/色调 drag×10 →
静置 60s → 读数），构建先经 `build-for-testing` 重建至 HEAD（895a352，TEST BUILD
SUCCEEDED）。

| 轮 | T0 phys_footprint | **T60 稳态（主判据）** | peak | resident(T60) |
|---|---|---|---|---|
| **R4（验收亲跑，PID 36445）** | 1807 MB | **1856 MB** | 8556 MB | 1.06 GB（1063008 KB） |
| 执行轮 R1/R2/R3（对表正本） | 2392/1914/1809 | 2427/**1975**/1856 | 6317/8556/8558 | 1.68/1.14/1.10 GB |

- R4 T60 = **1856 MB**：落 1.8-2.4GB 复核带，与执行轮 R3 **逐位一致**；peak 8556
  与 R2 逐位一致——场景可复现性成立。四轮中位 1915.5MB，≤3GB 门判定不变
  （余量 ~1.6×）。
- **机制核验复核**：R4 GUI 会话（36445）enforceBudget/evict 日志**零命中**，与执行
  轮申报一致。注记：R4 mech 查询窗（`--last 15m`）捕到 **19 行**——逐行核实 PID
  35702/35772 = **同会话早前测试宿主**（MemoryBudgetTests/IOP 全量轮，threshold
  299/999/1199、bytes 100-600 = 单测模型规模），非 GUI 会话；此为 T2 断言层
  「越界即逐出」触发态的**独立旁证**（PipeCache logger 真实越界时确实发日志）。
  **移交 M2-11-05 注记：mech 查询窗避免与测试轮同窗重叠**。

## 二、重述批审计（T3，`88ffba8`）

- **diff 形态亲证**：单文件 2 ins / 2 del，单 hunk `@@ -96,8 +96,8 @@`，改动行 =
  **:99-100**（M2PERF-01/02 两行）——与申报一致。
- **历史行零触碰亲证**：`:613-620` 前后内容 md5 = `ba6a06c21cfdff4a2b5f889936a7a367`
  双侧一致；checkbox 形态 M2PERF 行 `[ ]`×2、`[x]`×0 零变化；09 perf.md 在四提交
  零出现（git log --stat 逐提交核）。
- **六要素齐备**（M2PERF-01 行内逐条）：①PERF-01 链面 OQ-5-A + 拖动两档终值
  （color 双构建达标 / denoise OQ-7-A 挂账）②PERF-05 OQ-6-A 512 桶门 + 2560 记录
  档 + RAW9 冷单列 ③PERF-02 OQ-1-A 三分全文 + 1975MB ④PERF-03/04/06 终值指针
  ⑤PERF-07 Delivered 维持 + 05 轮复核义务 ⑥SpektraLab 双 PASS + 85ms 记录档 +
  32MB 不对标。M2PERF-02 = 终验基线注记（2955+2+3+1 → 2961/16/0，16+Δs 禁凑数）。
- **数字交叉核（35/35 申报复算，抽 26 项全命中）**：13.4/13.2/37.2/8.6/8.7/57.5/
  26.5/0.172/0.194/2.806/5.061/2.07/2.62/1975/168.2/300.6/0.021/5.009/85/193/9.7
  在 m2-11 perf.md；2.70 与 0.490 在 09-session perf.md（:7/:151/:155）；2955/2961
  落账自洽。零空引。

## 三、口径②③负证亲证

- **②**：`testNLMeansFullFootprintBudget` / `testCompositeFullWindowedPlaneSizes`
  在 59eae1f..HEAD diff **零命中**；`PreviewChainPerfTests.swift` diff 0 行
  （testFullToneEqualMemoryBudget 零触碰）；IOP 全量在册绿（下节亲跑）。
- **③**：`git diff 59eae1f..HEAD -- Scripts/` 空；`RSS_LIMIT_MB=8192` 实体在
  `Scripts/test-direct.sh:70`（plan 写 :59 = 01 波注释增长致行号漂移，实体零变化，
  SUMMARY 偏差#4 已如实登记）；「8G = 运行门（MEMFAIL 机检）非内存 SC 门」口径行
  在 perf.md §PERF-02 节首引文 + 口径③小节双落。

## 四、T2 语义修正复核（读码判定：修正台账非放宽断言）

- 实现语义亲读：`PipeCache.swift:214` floor = `min(evictTarget, byteBudget×2/3)`、
  `:269` `guard trackedBytes > floor else { break }`——**sweep 至 floor 即停
  （hysteresis，anti-thrash）为产线既有行为**；本波产线零 diff（App/ LightamerCore/
  Scripts/ 59eae1f..HEAD 空）。
- 初版预期「逐出全部可逐出面」（5/500/500）与该语义不符 = 测试预期误设；修正后
  （4 planes/400B/resident 600）反而**更严**：精确台账 `==600` + 上界 `≤floor(666)`
  + kept core 下界 `≥500` + current/previous PREVIEW 双存活性断言。测试语义
  （超限即逐出 = footprint 有界）不变。**裁定 = 采纳，非放宽**。

## 五、数字对账（验收机亲跑）

- 构建：`build-for-testing` 至 HEAD 895a352（T4 零代码变更，产物字节同源）。
- MemoryBudgetTests 定向亲跑：**14/0/0**（4s，peak 535MB）——13 既有 + 1 新增
  （`grep -c "func test"` 13→14 精确，git show 59eae1f 对照）。
- IOP 全量亲跑：**471/1/0**（141s，peak **7280MB** < 8192 门零 MEMFAIL；执行轮
  7650MB，方差带内；唯一 skip = 既有 SkinRegion Vision 环境件）。
- 基线算术：2957（02 波末）+3（03 波）= **2960**（03-ACCEPTANCE §四落账）+1
  （本波 MemoryBudgetTests）= **2961/16/0 终验预期** ✓。
- commit 清单对表：T1 `7ac3727`（perf.md §PERF-02 + profile/ 9 件 + MANIFEST 行
  10-14 + 4 截图）/ T2 `f238a55`（MemoryBudgetTests +85 行 + perf.md 对账尾注）/
  T3 `88ffba8`（REQUIREMENTS 2 行）/ T4 `895a352`（SUMMARY/DECISIONS/GOAL-STATE/
  LESSONS L068）——四提交与申报逐一致；产线零 diff 亲证（App/ LightamerCore/
  Scripts/ 空）。

## 六、O-2 瞬态峰登记合理性判定

- OQ-1-A 裁决原文措辞 = 「编辑器 GUI 交互**稳态**工作集 ≤3GB」——门判据锚定稳态
  （KD-1 T60），**瞬态不入门是裁决文本本义**。O-2（100% 缩放腿 peak 6.3-8.6GB，
  F 回落稳态 1.8-2.4GB）登记为观察项移交 M2-11-05 GUI 走查轮 = 与裁决一致的正解，
  非回避。R4 亲跑 peak 8556 与执行轮逐位一致，瞬态数据稳定性佐证登记值可信。
- perf.md 已防误读：「瞬态峰 8.6GB 与宿主 8G 运行门数字无关（不同主体不同语义）」。

## 七、AC 总表核验（plan 7 条逐条）

| # | AC | 结果 |
|---|---|---|
| 1 | 口径①实测在案：三轮中位 + ≤3GB 判定列 | ✅ perf.md §PERF-02 表 + profile/ 正本 + 验收 R4 独立复现 |
| 2 | 口径②负证：FULL 断言零触碰且在册绿 | ✅ diff 零命中亲证 + IOP 471/1/0 亲跑 |
| 3 | 口径③负证：RSS_LIMIT_MB 零变化 + 口径行 | ✅ Scripts/ diff 空 + perf.md 双落 |
| 4 | 新增上界断言绿 | ✅ 定向 14/0/0 亲跑 |
| 5 | 重述批六要素齐且数字同值 | ✅ 六要素逐条 + 26 项数字交叉核全命中 |
| 6 | 历史行零触碰 | ✅ :613-620 md5 一致 + checkbox 零变化 + 09 perf 零 diff |
| 7 | 产线零 diff；登记闭环 | ✅ 三目录 diff 空 + func test 13→14 |

## 验收批变更（本文件同批）

- perf.md：minor-1/2 勘误（R1 T0 2392；resident 1.68/1.14）+ R4 验收复测注记
  （只追加，历史行零触碰）。
- profile/：归档 `r4-footprint-t{0,60}.txt` + `r4-mech.log`（验收轮正本随录）。
- GOAL-STATE：续接点追加验收条目。
- 验收批零产线改码；未 push。

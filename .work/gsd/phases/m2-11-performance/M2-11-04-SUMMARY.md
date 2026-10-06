# M2-11-04 SUMMARY — PERF-02 内存三分法落地 + M2PERF 重述批（wave 4，2026-10-07 夜间执行）

> 执行 = subagent worker（夜间全自动授权在案：「开跑，不要停」）。
> 执行正本 = 本文件 + `M2-11-04-DECISIONS.md`（§1..5）+ `perf.md` §PERF-02 节
> （数字正本）+ `profile/r{1,2,3}-footprint-*.txt`（读数正本）+
> `.work/gui-acceptance/m2-11/MANIFEST.md` 行 10-14（走查证据）。
> 依赖面 = 02/03 波终值（perf.md §PERF-01/§SpektraLab）；基线 = **2960/16/0**。

## 结论头

**三分法三口径全数落账**：①GUI 稳态工作集实测三轮**中位 1975MB ≈1.93GB ≤3GB
PASS**（余量 ~1.55×；`/usr/bin/footprint` phys_footprint 口径，真 GUI app 真
100MP 样张）②FULL 窗口断言**零触碰零新增**（负证在册）③宿主 8G 运行门**零
触碰**（`RSS_LIMIT_MB=8192` 实体不变）。T2 断言面 +1 测试（MemoryBudgetTests
14/0/0 定向；IOP 全量 **471/1/0**，peak 7650MB 零 MEMFAIL）；T3 重述批六要素
入 M2PERF-01 行内 + M2PERF-02 终验基线口径注记（**2961/16/0 终验预期**，数字
35/35 grep 交叉核全过）。**产线零 diff**（App/ LightamerCore/ Scripts/
59eae1f..HEAD 空）。**未 push。下一步 = orchestrator 派验收 subagent →
M2-11-05（closeout 终验批，plan 在册）。**

## 任务逐条

| 任务 | 状态 | commit | 要点 |
|---|---|---|---|
| T1 GUI 稳态内存 profile（GUI 轨） | ✅ | `7ac3727` | KD-1 场景脚本三轮（可复现：probe 缝建项目 + File/Open Recent + 双击开图 + Z/F 缩放 + 滚轮平移×2 + 色温/色调 drag×10 + 静置 60s）；T0/T60 双读 + peak 辅列；机制核验（enforceBudget/evict 日志零命中 + toast 零出现）；trace 归 `profile/` + 截图入 MANIFEST 行 10-14 |
| T2 三分法断言面（IOP） | ✅ | `f238a55` | `testPreviewWorkingSetBoundedByInjectedBudget`：常量 pin（3GB/2GB/floor 公式）+ 稳态 no-op 腿 + 越界逐出 floor 语义精确台账腿（4 planes/400B，resident 600≤666，kept PREVIEW 存活）；定向 14/0/0 + IOP 全量 471/1/0 |
| T3 REQUIREMENTS 重述批 | ✅ | `88ffba8` | M2PERF-01 行内六要素（PERF-01 链面 OQ-5-A / PERF-05 OQ-6-A 512 桶门 / PERF-02 OQ-1-A 三分 / PERF-03/04/06 终值指针 / PERF-07 Delivered 维持 / SpektraLab 双 PASS 并入）+ M2PERF-02 终验基线注记；checkbox `[ ]` 零变化；:613-620 指纹一致；数字 35/35 交叉核 |
| T4 收口 | ✅ | 本批 | AC 机检 7 条全过（下表）；SUMMARY/DECISIONS + GOAL-STATE 续接点 + LESSONS L068 |

## 三口径数字（perf.md §PERF-02 正本）

| 口径 | 结果 | 判定 |
|---|---|---|
| ① GUI 稳态（T60 phys_footprint） | R1 2427 / **R2 1975** / R3 1856 MB → 中位 **1975MB ≈1.93GB** | **≤3GB PASS**（余量 ~1.55×） |
| ① T0 编辑尾（参考列） | 2391 / 1914 / 1809 MB → 中位 1914MB | 参考不设门 |
| ① peak（辅助列，观察项 O-2） | 6317 / 8556 / 8558 MB（100% 缩放腿瞬态） | 稳态门不收；O-2 移交 M2-11-05 |
| ② FULL 窗口 | 既有 bilateral FULL 门 + `testFullToneEqualMemoryBudget` 零触碰 + 在册绿 | 负证 ✓（TilingPlan 窗口有界，不设绝对数） |
| ③ 宿主 8G 运行门 | `RSS_LIMIT_MB=8192` 零变化 + perf.md「运行门非 SC 门」口径行 | 负证 ✓（SPIKE `70e09e5` 指针在） |

## 测试对账

- 基线 **2960/16/0**（03 波终值）+ 本波 Δ = **+1**（MemoryBudgetTests 1 法，
  `grep -c "func test"` 13→14 精确）→ **2961/16/0 终验预期**。
- 实测：IOP 定向 `MemoryBudgetTests` **14/0/0**（零 skip 增量）；**IOP 全量
  471/1/0**（470+1 精确，149s，peak 7650MB < 8192 门零 MEMFAIL；唯一 skip =
  既有 SkinRegion Vision 环境件）。全套 `--all` 未跑（批准制未申请，M2-11-05
  终验）；skip 基线 16 零新增。

## AC 总表核验

| # | AC | 结果 |
|---|---|---|
| 1 | 口径①实测在案：三轮 footprint 中位 + ≤3GB 判定列 | ✅ perf.md §PERF-02 表 + profile/ 归档（`7ac3727`） |
| 2 | 口径②负证：既有 FULL 窗口断言零触碰且在册绿 | ✅ diff 零命中（既有测试体 0 行 +/-）+ 471/1/0 全绿 |
| 3 | 口径③负证：`RSS_LIMIT_MB=8192` 零变化 + perf.md 口径行 | ✅ `git diff Scripts/` 空 + perf.md §PERF-02 口径③行 |
| 4 | 新增上界断言绿 | ✅ 定向 14/0/0（`f238a55`） |
| 5 | 重述批六要素齐且数字与 perf.md 同值 | ✅ 35/35 grep 交叉核（m2-11 perf.md + 09 perf.md + 13 perf.md） |
| 6 | 历史行零触碰：:613-620 + checkbox 形态 + 09 perf 历史行 | ✅ diff 单 hunk 落 :99-100 + :618-626 内容 md5 一致 + 09 perf.md 零 diff |
| 7 | 产线零 diff；登记闭环 | ✅ App/ LightamerCore/ Scripts/ 空；func test 13→14 |

## 偏差与发现（详见 DECISIONS §5）

1. **slider 驱动 = drag 语义**（L068 新知）：合成单击不改值（首轮 10 连击全空点，
   截图复核抓出）；drag 序列即改值。驱动源随档（`profile/cgdrive.swift`）。
2. **probe 缝两 quirk**（DEBUG seam 既有行为，零产线影响）：①`NSApp.terminate`
   2/3 轮未生效（app 驻留，TERM 清理）；②「grid rows never arrived」间歇 2 次
   （10s 等窗竞态，重试即过）——M2-11-05 probe 使用方注意。
3. **观察项 O-2**：100% 实际大小缩放腿瞬态峰 6.3-8.6GB（稳态回落 1.8-2.4GB）——
   稳态门不收，perf.md 登记移交 M2-11-05 GUI 走查轮。
4. **plan 指针行号漂移**：`RSS_LIMIT_MB=8192` 实体在 :70（plan 写 :59）——
   M2-11-01 解析器抽取使脚本头部注释增长所致，实体零变化（AC#3 钉常量非行号）。
5. T2 定向轮后 perf.md 对账尾注随 `f238a55` 同批入库（测试与账同批纪律）。

## 遗留与移交

- O-2（缩放瞬态峰）→ M2-11-05 GUI 走查轮顺带观察（16GB 机器 100% 缩放体验）。
- O-1（RAF warm 双峰噪声，02 波登记）→ M2-11-05 维持。
- 全套 `--all` 终轮（**2961/16/0 预期对账**）+ PERF-07 带内复核 + M2PERF 翻勾 →
  M2-11-05 closeout（批准制）。
- hitch 缩放/平移/万张滚动 Manual-Only 三场景 → M2-11-05 computer-use 主 agent 轮。
- **未 push。下一步 = orchestrator 派 M2-11-04 验收 subagent → M2-11-05。**

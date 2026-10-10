> **⛔ SUPERSEDED（2026-10-10 用户裁决：删除 Follow Edges 功能并挂待定）**——本 plan 描述的walker 纪律批永不执行；IOP-MASK-06 状态见 REQUIREMENTS「待定（parked）」条目与 M4-2-02-DECISIONS 三选一记录。本文件保留为 research 复审（M4-2-03-CONTEXT）的规划存档。

---
phase: m4-2
plan: "M4-2-03"
title: "Follow Edges 算法层迭代批（方案 A 行走纪律修复，OQ-1..6 全 A 裁决）——/tmp 诊断源+log 按 M2-7-3 先例归档 evidence 仓 + walker 三件套纪律（防绕 visited + next-best 回退 + deficit 跨穿越携带并计入跳跃距离）+ 输出链单调重排（无弦线哨兵的结构前提，DECISIONS 申报）+ 真图门定义 v2 双轨（arc≥24 ∧ 逐点贴脊率≥90%@2px ∧ 出点≥8；旧数据不重算）+ 合成 golden 按 v2 语义重推导零删 + 无弦线哨兵 + probe 同协议复跑对账（模拟预测 t0.25 3/8、t0.15 4/8 = 如实判据）+ 性能复测（worst-case 步数 4080→两位数）+ M4-1 挂账 #6 孤儿 .lra 顺手修复 + 收口"
wave: 3
depends_on: ["M4-2-01", "M4-2-02"]
autonomous: true
requirements: ["IOP-MASK-06（算法层迭代——M4-2-02 三选一用户裁决①形态）"]
estimated_tests: "+5..6"
test_bundles: [Layers, App, Export]
files_modified:
  - LightamerCore/Sources/Layers/Masks/FollowEdges.swift            # 修改（T2）：walk/continuationFrom 三件套纪律 + streamline 输出单调重排——readEdgeMap/snap/edgeMap/edgeMapKernel 腿与 FollowEdgesParams 字段+缺省零触
  - Tests/LightamerTests/FollowEdgesTests.swift                     # 修改（T3）：既有断言按 v2 语义重推导（零删）+ 新增 5..6 法（防绕死守卫/deficit 携带/无弦线哨兵/双向共享已访/next-best 回退）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt      # 修改（T3）：FollowEdgesTests 计数行 15→20..21 随批登记（零新文件——Project.swift 零改、无 tuist generate，L041 不触发）
  - Tests/LightamerTests/RasterRoundTripTests.swift                 # 修改（T5）：M4-1 挂账 #6 顺手修复——写腿改 tmp 域拷贝 + 双前清（写方治本，App bundle 跨轮污染根除）
  - AGENTS.md                                                       # 修改（T5）：M4-2 架构增量节（walker 纪律定式 + 输出单调重排 + 门 v2 双轨 + probe 归档路径登记）
  - .work/gsd/phases/m4-2-follow-edges/M4-2-03-SUMMARY.md           # 新建（T5）
  - .work/gsd/phases/m4-2-follow-edges/M4-2-03-DECISIONS.md         # 新建（T5，含模拟 vs 产线两处偏差申报 + 模拟预测对表）
  - .work/gsd/phases/m4-2-follow-edges/M4-2-03-ACCEPTANCE.md        # 新建（m1 双重验收——zcode PASS 后串行 omp）
  - .work/gsd/phases/m4-2-follow-edges/M4-2-03-ACCEPTANCE-OMP.md    # 新建（T5）
  - .work/GOAL-STATE.md                                             # 修改：续接点
  - .work/TODO.md                                                   # 修改：M4-2 条目 + M4-1 挂账 #6 翻账
  - .work/LESSONS.md                                                # 如踩坑
---

# Plan M4-2-03 — Follow Edges 算法层迭代：行走纪律修复（方案 A）+ 门定义 v2 + probe 对账

> **性质**：M4-2-02 停止上报「三选一」的用户裁决①执行批。裁决正本 =
> `M4-2-03-CONTEXT.md` 文末裁决记录（**OQ-1..6 全按推荐，全 A**——六项生效值
> 见 §裁决落地，逐条入 AC）；机理实测正本 = `RESEARCH-NOTES.md` Part 2 §8-10
> （诊断探针 `/tmp/m42diag/`，本批 T1 归档）。方案 = **A 先行单执行批**：行走
> 纪律修复（walker 内部三件套）→ probe 同协议复跑对账 → 如实呈报。**本批不含
> 方案 B/C、不含 GPU NMS/2048 立项（OQ-6-A）、不含默认回翻**（`.snap` 熔断态
> 维持；若 probe 意外 ≥6/8，上报 orchestrator 裁决，不自行翻默认）。
>
> **基线（亲核，2026-10-10 HEAD `f96735b`）**：Layers **422/3/0**（基线 420 +
> M4-2-02 两法）+ App **708/0/0** + Export 350 + 全套预期 **3367/16/1**
> （1 fail = M4-1 挂账 #6 孤儿 `.lra` 跨 bundle 污染 `testRestoreWinsOverDerive`，
> 非本波面——T5 顺手修复，修复后全套预期见 AC-9）。仓内当前无孤儿
> `*.lra`（`Tests/Fixtures/` find 亲证零命中——M4-1 VALIDATION 轮已清）。
>
> **六项生效值（裁决记录 → 落地映射）**：
> ① **方案 A 行走纪律修复先行单执行批**：防绕 visited + next-best 回退 +
> deficit 跨穿越携带，gate 0.5 不动，零提取侧 → T2；
> ② **门定义 v2**：arc ≥24px ∧ 逐点贴脊率 ≥90%（2px 门）∧ 出点 ≥8（可用性
> 地板）；旧门数据（M4-2-01/02）不重算，新门**双轨并行一轮**（probe 打印
> v1+v2 两版 GATE 行）→ T3/T4；
> ③ **followStrength 缺省维持 0.5**：`FollowEdgesParams` 字段与缺省零 diff →
> T2 红线；
> ④ **合成 golden 零删**：几何断言（贴脊距离/覆盖率/确定性/`.snap` 冻结）
> 全保留；出点数/间距类断言按 v2 语义重推导 + 注释标注；**新增无弦线哨兵**
> （相邻出点间隙 ≤4.5px+ε——弦线回归哨兵）；`RidgeExtractTests` 21 法零触 → T3；
> ⑤ **总门维持 6/8 + P1 后中期核对点**：probe 复跑如实上报（预期 ~4/8），
> 不停批不降门；方案 C 批后对 6/8 终裁 → T4；
> ⑥ **GPU NMS / 2048 本批不立项**：零新 kernel / 零新 PSO / 零分辨率变更 →
> 全批红线。

## 机理与改动面（RESEARCH §8/§10 落地定式）

三机理实测（traced walk 8 景与 probe.log bestN 逐值一致的保真校验在案）：
①**ping-pong 死循环**（无 visited 守卫：C2 景 4080 步/1813 穿越被
stepGuard=2048 砍杀，出点 ≈1）②**deficit 穿越重置饥饿**（每次穿越重置
4.0px，穿越后段长 ~1.4px → 积累永不出点 → 27.8px 弦线，n≥12 腿系统性失败）
③**junction 门截停**（次要：gate 扫频 0.5→0.0 只买 +2 出点——参数不可救，
③ 本批不动门）。改动面 = `FollowEdges.swift` 的 `walk`/`continuationFrom`/
`streamline` 尾段——**零提取侧**（`RidgeExtract.swift` 零 diff，六段流水线与
冻结拓扑值不作废）、零参数面、零 Metal、零 App 接线。

### KD-1 walker 纪律定式（T2 实现规格，模拟 `fixedWalk` 为语义基线）

1. **防绕 visited**：每个 `walk` 携带 `Set<ChainEndKey>`；链端到达时 arrival
   key 已在集合 → 死亡返回（诊断性，正常不可达——见 4）；否则插入集合。
   **fwd/bwd 共享同一集合**（streamline 建一份传两腿——`direction` 的
   「首出侧先耗 budget」纪律不变；这是 RESEARCH §10-3「≤2 顶点链共享已访态」
   建议的无条件化超集：A 景实测两向逐点重复出点的病灶是同一现象的一般形，
   条件分支（attach 链长判定）不引入，DECISIONS 申报）。
2. **next-best 回退**：junction 候选按（cos 降序，M3 行主序 tie-break）排序，
   顺次取第一个「落点 end ∉ visited」且 cos ≥ gate 的分支；全耗尽 → 死亡。
   无 visited 过滤时的胜者与现行 `continuationFrom`（max-cos 首中即胜）逐字节
   一致——**未访问语义零漂移**。bridge 照旧直穿（arrival key 照 1 插入）。
3. **deficit 携带 + 跳跃距离计入**：取消穿越重置（`spacing`/`deficit` 跨穿越
   连续）；穿越瞬间计跳跃距离 `J = |落点顶点 − lastPos|`，
   `deficit = max(deficit − J, 0)`——**不在跳跃弦上出点**；clamp 到 0 时下一段
   首个出点恰落在落点顶点（在脊上）。数学保证：相邻出点欧氏距离 ≤ 弧长累积
   ≤ spacing ≤ 4px（桥接 ≤3px 边界情形 ≤ L₁+J ≈ 4.5px，见 KD-3 哨兵钉值）。
   **跳跃段不更新 `arrival`、不重算 spacing**（首段跳过转角更新 = 现行
   `crossed` 旗语义沿用）。模拟未计此项（残余 gapMax 39.7px）——产线必须计，
   否则哨兵门在桥接景不可满足。
4. **步数保险丝不变**：`stepGuard = maxPoints * 8` 原样（防绕后最坏步数 =
   O(链端事件数)，C2 实测预期 4080→两位数；guard 降为 belt-and-braces）。
5. **gate 消费点零改**：`gateValue`/`followStrength` 缺省 0.5 逐字不动（裁决③）。

### KD-2 输出链单调重排（DECISIONS 必申报项）

`streamline` 尾段 `out = [attach] + forward + backward` →
`out = reverse(secondary) + [attach] + primary`（direction ≥0 时 primary =
forward）：输出折线成为**单调骑行序**（b 远端 → … → attach → … → f 远端）。
依据：现行拼接序在两向骑行 ≥4.5px 时 `f_last → b_first` 必然产生跨链长弦
（L 角景即切角线——诊断与合成断言均未抓到，因弦沿脊/断言只查点不查段）；
**无弦线哨兵（裁决④）对整链成立的结构前提 = 本重排**。出点集合不变（既有
几何断言 min/max/覆盖率/贴脊距离全不受扰——逐法对账表在 T3）；App 消费面
（`FollowEdgesInteraction.chain` → BrushStroke 沿折线盖章）无序依赖（亲读
`MaskOverlayHost.swift:888-907`），盖章序单调化 = 用户可见改善。

### KD-3 无弦线哨兵钉值

门值基准 = **4.5px**（research 锚：resampleMaxStep 4.0 + 桥接 3.0 不同段叠加
上界 ≈4.5 + 亚像素抖动 ε）。按 M3-3-E5 先例：合成轨实测后**带内收窄钉死**
（实测 max + 工程余量，不许高于 4.5+ε 静默放宽；若实测越 4.5 → DECISIONS
记录越界来源并裁定，如实上报）。断言加在既有桥接/直脊/L 角景 + 新 hairball
景上（全链相邻出点间隙）。

## Tasks

### T1 诊断源 + log 归档 evidence 仓（M2-7-3 先例）

- read_first：RESEARCH §8.0（保真校验注记）+ evidence 仓 `m4-2-02/probe/MANIFEST.txt` 体例。
- `/tmp/m42diag/`（即弃快照）→ evidence 仓
  `evidence/m4-2-03/probe/`：`diag-main.swift`（诊断脚手架 verbatim）+
  `diag-chord.swift` + `diag.log`（研究实录正本）+ `MANIFEST.txt` 增节
  （构建配方：`swiftc` 直编命令 + 源组成 = evidence `m4-2-02/probe/` 源
  verbatim + `/tmp/m42diag/main.swift`；保真校验注记：8 景 × 2 阈 bestN 与
  `m4-2-02/probe/probe.log` 逐值一致 t0.15: 5/0/13/1/9/34/6/1、t0.25:
  1/0/9/1/8/12/2/1）。`diag` 二进制不归档（可再生，MANIFEST 记配方）。
- 验收：文件在位 + evidence 仓独立 commit；主仓 `git status` 零 probe 产物。

### T2 walker 三件套纪律修复（Core 单文件）

- read_first：`FollowEdges.swift` 全文 + RESEARCH §10 方案 A 清单 + 本 plan
  KD-1/KD-2 定式 + `/tmp/m42diag/main.swift` `fixedWalk`（语义基线，T1 后 =
  evidence `diag-main.swift`）。
- 按 KD-1 1-5 实现 `walk`/`continuationFrom` 纪律改造（visited 集合共享穿
  `streamline` 两腿）+ KD-2 输出单调重排。**零触面**：`FollowEdgesParams`
  字段与缺省、`.snap`/`snapTarget`、`readEdgeMap`、`edgeMap`、
  `nearestVertex`、`resampleStep`、`maxPoints`/`stepGuard`/重采样三常量。
- 既有 15 法全绿对账（预期零断言破坏：无 crossing 景逐字节同序，crossing 景
  点集同序变——对账表落 DECISIONS；若有意外破断言 = 停手读因，禁止改测试
  凑绿，上报形态记录）。
- 验收：`Scripts/test-direct.sh --bundle Layers` 全绿；机检红线
  （`RidgeExtract.swift`/`MaskEdgeKernels.metal`/`PipeCoordinator.swift`/
  `MaskOverlayHost.swift`/`LayerEditingState.swift`/`MaskToolbarView.swift`/
  `Localizable.xcstrings`/`Project.swift` 零 diff + `FollowEdgesParams` 缺省
  亲读 0.5）。
- commit：`feat(core): enforce walk discipline in the follow-edges graph walker`

### T3 golden v2 重推导 + 哨兵 + 门定义 v2 双轨（probe 载体）

- **golden（裁决④）**：`FollowEdgesTests` 既有断言**零删**；出点数/间距类按
  v2 语义重推导（防绕/携带下 bridge 计数、ring maxX 等实测收窄钉门 + 注释
  `v2 walker discipline (M4-2-03)` 语义标注）；几何断言（贴脊/覆盖率/确定性/
  `.snap` 冻结三景常量）不动。新增 5..6 法：
  ①**防绕死守卫**（junction 密集 hairball fixture——旧 walker stepGuard 砍杀
  出点 ≈1 的拓扑：新 walker 快速终止 + 出点数下限 + 无重复连续点）；
  ②**deficit 携带**（短链串接景：旧语义零出点饥饿段 → 新语义出点 ∝ 骑行弧长）；
  ③**无弦线哨兵**（KD-3：桥接 + 两向骑行景全链间隙 ≤ 钉值——重排 killing
  test：旧拼接序在 L 角必产 >4.5px 弦）；
  ④**双向共享已访**（≤2 顶点 attach 链景：fwd/bwd 无逐点重复——A 景病理
  合成复刻）；
  ⑤**next-best 回退**（最优分支落点预消费 → 顺次回退 ≥gate 次优，非死亡）；
  ⑥（可选）重排后 `direction` 两向输出互为反序断言（首出侧 budget 纪律钉）。
- **门 v2 双轨（裁决②）**：evidence 仓 probe `main.swift` 派生自
  `m4-2-02/probe/main.swift`——协议全同（8 景盒 × 5 seed × {0.25, 0.15}），
  SCENE 行同时计算并打印 **GATE-V1 行**（n≥12 ∧ arc≥24 ∧ 端点贴脊 2px——
  旧定义，跨批可比锚）与 **GATE-V2 行**（arc ≥24 ∧ 逐点贴脊率 ≥90%
  （2px Chebyshev 窗候选距）∧ 出点 ≥8）；总门行两版并打印（max-over-thresholds
  口径与 M4-2-02 一致）。逐点贴脊率实现 = diag `candDist` 同式（±2 窗最近
  NMS 候选欧氏距 ≤2）。probe 侧 `FollowEdges.swift` 副本 = T2 修复版 repo 源
  + HB 心跳行（steps/visited/death kind——worst-case 步数实测载体）。
- BUNDLE-MAP 计数行登记（15→20..21）。**零新测试文件** → `Project.swift`
  零改 → **无 tuist generate**（L041 不触发，防 checker 误报注记）。
- 验收：`--bundle Layers` 全绿（21 法 RidgeExtractTests 零触亲证）；probe
  main.swift 编译零错误；BUNDLE-MAP 行更新。

### T4 probe 复跑对账 + 性能复测（中期核对点⑤）

- 同协议双跑（probe.log / probe-run2.log，逐行一致性 = 确定性纪律）+ in-run
  DETERMINISM 行。**模拟预测对表（如实判据，模拟非承诺）**：

  | 景 | t0.25 预测 | t0.15 预测 | 机理 |
  |---|---|---|---|
  | A | no（4 点/revisit 死） | **YES** 27 点/115px | ping-pong 消除 |
  | A2 | no（0 候选） | no（0 候选） | 恒不可救 = 门容错对象 |
  | A3 | **YES** 15/46px | YES 14/49px | 已功能维持 |
  | B | no（1 点） | no（3 点） | 链未成形（方案 C 面） |
  | B2 | **YES** 21/84px | YES 19/92px | 饥饿消除翻功能 |
  | B3 | YES 21/48px | YES 29/62px | 维持 |
  | C | no（6 点） | no（5 点） | free-end（方案 C 面） |
  | C2 | no（9/10px） | no（9/10px） | 死循环→26 步正常返回 |
  | **门** | **3/8** | **4/8** | 模拟实测值（RESEARCH §10） |

  产线含跳跃计入 + 单调重排 → 输出质量**优于**模拟（模拟残余弦线为未计跳
  跃 + 拼接伪影）——逐景对表行落 DECISIONS；≥6/8 = 提前达标上报（默认回翻
  仍不自行执行）；<4/8 = 逐景归因如实分析（防绕/回退/重排三偏差候选 +
  模拟保真度复核），不停批不降门。
- **性能复测**：EXTRACT x10 median（≤50ms 门——提取侧零改，预期 ≈39.3ms 不变）
  + COLD 行（信息性）+ WALK carrier-hit（≤5ms）+ **worst-case 步数崩塌实测**
  （C2/A 景 HB 行：4080 步 → 两位数）。
- App 定向轮回归（carrier 4 法 + 全 App bundle 708/0/0 逐位）。
- 验收：双跑逐行一致 + 对表在 DECISIONS + 预算行在册 + evidence 仓 commit
  （源快照：修复版 `FollowEdges.swift` 含 HB、`RidgeExtract.swift` cmp 主仓
  零 diff、`MaskEdgeKernels.metal`、`shim.swift`、`MaskPointExtract.swift`、
  `main.swift` v2、双 log、MANIFEST 终稿）；主仓零产物。

### T5 挂账 #6 顺手修复 + 收口

- **M4-1 挂账 #6（omp-minor-1）修复**：`RasterRoundTripTests.
  testEditReplaySurvivesFlushAndReload` 写腿改 **tmp 域拷贝**（fixture 复制到
  测试 tmp 目录后编辑副本——仓内 `Tests/Fixtures/` 永不再生成 sidecar）+
  **双前清**（测试入口 + 出口对 tmp 域残留清扫 + 仓内 fixture 目录防御性
  检查）；孤儿清查 `find Tests/Fixtures -name "*.lra"` 零命中亲证。翻账：
  `.work/TODO.md` 挂账 #6 → 已修复（指向本批 commit）。
  commit：`fix(export): keep the edit replay test sidecar out of repo fixtures`
- Export 定向轮全绿（350/0/0 量级——修复不增测）。
- **收口**：SUMMARY/DECISIONS（含 KD-2 重排 + KD-1 两处模拟偏差申报 + 对表）
  /ACCEPTANCE（**双重验收：zcode PASS → 串行 omp，严禁并发**——
  `dual_acceptance = true`）+ AGENTS.md M4-2 架构增量节（walker 纪律定式五条
  + 重排 + 门 v2 双轨 + 归档路径）+ GOAL-STATE/TODO 同批 + 红线自证终表 +
  全套 `--all` 预期对账（**不自行跑 --all**——orchestrator 批准制，预期值
  写 SUMMARY 留验收轮对账）。
- commit：`docs(m4-2): close the walker discipline batch with rulings and ledger`

## 验收标准（AC 总表）

1. **①行走纪律**：防绕 visited（fwd/bwd 共享）+ next-best 回退 + deficit 携带
   含跳跃距离计入（clamp-to-0 落点顶点出点）全落地；gate 消费与缺省 0.5 零改
   （机检：`FollowEdgesParams` 字段+缺省零 diff）；**零提取侧**
   （`RidgeExtract.swift`/`MaskEdgeKernels.metal` 零 diff；`RidgeExtractTests`
   21 法零触全绿）。【T2/T3】
2. **①输出单调重排**：`out = reverse(secondary) + [attach] + primary`；
   `direction` budget 纪律不变；DECISIONS 申报在册。【T2】
3. **②门 v2 双轨**：probe 打印 v1+v2 两版 SCENE/GATE 行；v2 = arc≥24 ∧
   逐点贴脊率 ≥90%@2px ∧ 出点 ≥8；旧门数据不重算（M4-2-01/02 log 原样）。【T3/T4】
4. **④golden 零删 + 重推导 + 哨兵**：既有断言零删（几何族逐字节保留）；出点
   数/间距断言按 v2 重推导 + 注释标注；无弦线哨兵门值按 KD-3 钉死（≤4.5px+ε
   基准，实测带内收窄）；新 +5..6 法全绿。【T3】
5. **⑤中期核对点**：probe 复跑同协议双跑逐行一致；模拟预测对表（t0.25 3/8、
   t0.15 4/8）如实呈报——**门 PASS 与否的判据 = 如实对表，非达标**；不停批
   不降门；总门 6/8 维持为 phase 终裁目标。【T4】
6. **⑥零立项**：零新 kernel/PSO/新 Metal 文件/分辨率变更/参数面变更
   （机检 grep 门 + 新文件清单为零）。【全批】
7. **性能**：EXTRACT ≤50ms（预期 ≈39ms 不变）+ WALK ≤5ms + worst-case 步数
   4080→两位数实测行在册。【T4】
8. **红线**：`.snap` 分支/`MaskOverlayHost`/`PipeCoordinator`/
   `LayerEditingState`/`MaskToolbarView`/xcstrings/`Project.swift` 零 diff；
   `.snap` 熔断缺省维持（不回翻）；zh-audit 零新键不触发；主仓零 probe 产物。【T2/T4】
9. **回归与基线对账**：Layers 422 + 5..6 = 427..428 全绿；App 708/0/0 逐位；
   Export 全绿 + 挂账 #6 修复后孤儿 `*.lra` 零命中；全套 `--all` 预期 =
   **3372..3373/16/0**（3367 − 1 fail + 增量，留验收轮对账）。【T3/T4/T5】
10. **归档与收口**：T1 诊断归档 + T4 probe 证据落 evidence 仓（MANIFEST 全）；
    双重验收两路结论在 ACCEPTANCE；六项生效值逐条在 DECISIONS 引用裁决记录。【T1/T4/T5】

## 风险与边界

- **产线 vs 模拟两处偏差**（DECISIONS 申报，非静默）：①落点 end 于穿越时即
  插入 visited（比 `fixedWalk` 更紧的终止保证）②输出单调重排（模拟无）。两者
  只紧不松；场景结局可能偏离模拟 → T4 对表以实测为准，偏差归因三候选预登记。
- **next-best 仍可能选错支**：蒙版语义 = 「另一条边」非失效（RESEARCH §6.2
  既有定性沿用）；走查观察项不设门。
- **哨兵边界情形**：桥接 3px + 段剩余 1.4px 叠加理论上界 ≈4.5px 贴门——
  合成实测钉值（KD-3），越门如实记录不静默放宽。
- **A2/B/C/C2 残余败景** = 方案 C（提取连通性）的面，本批**不动**——T4 败景
  形态判别行（细脊缺席 vs 碎片断隙）随报，为 orchestrator 下一批裁决供料。
- **内存/预算**：walker 新增 Set<ChainEndKey> ≤ 链端事件数（万级）——量级
  无虞；Layers/App bundle RSS 零增量面。

## 提交约定

- T1 evidence 仓 `m4-2-03: archive walker diagnostics (sources + log)`
- T2 `feat(core): enforce walk discipline in the follow-edges graph walker`
- T3 `test(core): re-derive follow-edges goldens under v2 walker discipline`
- T4 evidence 仓 `m4-2-03: probe re-run with the v2 gate (dual-track)`
- T5 `fix(export): keep the edit replay test sidecar out of repo fixtures` +
  `docs(m4-2): close the walker discipline batch with rulings and ledger`
- 全英文 Conventional Commits；不 push；probe/诊断证据只落 evidence 仓
  （`/Volumes/UNITEK/Documents/Development/lightamer-evidence`，主仓
  `.gitignore` 已排 evidence 路径——commit 前亲查 `git status`）。

# M4-2-02 SUMMARY — 备用批：readEdgeMap 升级口 512→1024 实测裁决

> 状态：**执行完毕——真图门 FAIL 2/8，按 plan 停止线上报**。批内 1 commit
>（`633378b`，未 push）+ evidence 仓 probe 证据 commit。默认回翻（T3）**不执行**，
> `.snap` 熔断态维持。**移交 orchestrator：phase 重裁三选一**（§6）。

## §0 触发与升级行动（T1）

- 触发三证齐备（M4-2-01-ACCEPTANCE 门 FAIL 判别审计 + 双验收 PASS 裁决
  「armed 确认」）——DECISIONS §0 逐条引用。
- **产线唯一改动**：`PipeCoordinator.edgeMapField(for:)` 调用点传
  `maxLongEdge: 1024`（`633378b`）。`readEdgeMap` 签名/缺省 512/函数体零改
  （机检：函数体 sed 抽取 md5 与 M4-2-01 evidence 副本**同值**
  `61c0001f…`；签名行亲读 `maxLongEdge: Int = 512`）。申报外扩 = 同缝
  邻注 4 行诚实化（「≤512-guard」措辞，零逻辑面）——DECISIONS §1。

## §1 probe 1024 门复跑（T1，evidence 仓 `m4-2-02/probe/`）

**门 = FAIL 2/8**（阈值 ≥6；M4-2-01 @512 基线 0/8）。同协议（8 景盒 × 5 seed ×
双阈 {0.25, 0.15}），唯一变量 = 读回工作域。

| 阈 | 功能景 | 明细 |
|---|---|---|
| t0.25 | **1/8** | B3 YES（12 pts / 34px）——两波以来首个功能景 |
| t0.15 | **2/8** | A3 YES（13/39px）+ B3 YES（34/83px） |

- **双跑确定性**：probe.log / probe-run2.log 全部 SCENE/GATE/THRESH/DIAG/
  STAGES/FIELD 行逐行一致（仅计时行抖动）+ in-run DETERMINISM true。
- **跨批协议一致性**：DIAG mle=512 行（chains=1663/junctions=711/
  vertices=4810/longest=21；bestWalk n=7/arc=20px）与 M4-2-01 THRESH 0.15
  门场值逐值一致——协议未漂移。
- 涨幅全景：candidates 3147→11305 / strong 586→2003 / domain 1289→5080；
  t0.15 图 4810→19574 顶点、最长链 21→60；骑行分数（DIAG-2）0.38→0.62。
- 败景形态（三选一裁决输入）：A2 恒 0 候选（区域无脊，非算法侧）；A 景长行走
  （89px）但端点贴脊门不过；B/C 碎片链；**junction 门掉链 = 剩余主导瓶颈**
  （骑行 0.62 仍有 38% 掉链——分辨率单独不可达，算法层观察项与 M4-2-01
  DIAG-2 定性一致）。

## §2 预算阶梯裁决（T2，KD-1 三档）

**落位 = 第一档（≤50ms：门不变）**：

| 行 | 实测 @1024 | 门 |
|---|---|---|
| EXTRACT first-shot | 40.8ms | ≤50ms PASS（81% 贴线） |
| EXTRACT x10 median | **39.3ms**（min 38.6） | ≤50ms PASS |
| COLD GPU pass + 1024 读回 | 8.3ms median（512: 6.3，+2ms） | 预期 ~+6ms 级内 |
| WALK carrier-hit | 0.007ms median | ≤5ms PASS |

无门修订申请、无停止上报（plan 期 ~60ms 猜测偏悲观）。贴线注记：再升 2048
必越 50ms 门——GPU NMS（OQ-2-B）立项论据加强，随三选一呈报。

## §3 回归与负测（T1，LAYERS）

- +2 法（`RidgeExtractTests`，BUNDLE-MAP 登记 19→21 随批）：
  ①1024 路径法——1536×1024 源 → 1024×682（公式精确）+ 最近邻 box 序全断言
  （`+0.5·scale` 采样式 + 角点钳制 + 步进扫描）+ **缺省 512 不变断言**；
  ②纯函数零变负测——直构场冻结 M4-2-01 拓扑值（chains=21/junctions=13/
  bridges=0/vertices=60/longest=11 + 行走 n=5/arc≈28.2px）+ 双跑位等。
- **Layers 422/3/0**（基线 420 + 2 精确；157s→153s；peakRSS 1151MB 同档）。
- 执行史实：负测初版误施 probe 功能腿（n≥12）于合成弧景（该场 matrix 门 =
  hug/coverage，5 点过 coverage 0.8），改冻结值形态——DECISIONS §4 在案。

## §4 未执行/搁置面（如实记录）

- **T3 默认回翻：不执行**（前置门 = 本批 T1 门 PASS；实测 2/8 < 6/8）。
  `LayerEditingState.swift` / `MaskToolbarView.swift` / `Localizable.xcstrings`
  批内零 diff；hint 键零写入；zh-audit 不触发（零新键）。
- **全套 `--all`：未跑**（AGENTS 纪律 = orchestrator 批准制；本批授权面 =
  定向轮 Layers + App）。对账：基线 3365/16/1 + 本批 Δ +2（Layers）→ 预期
  **3367/16/1**（1 fail = M4-1 挂账 #6 孤儿 .lra 同族，非本批面；本批未跑
  --all，该预期留验收轮对账）。
- ACCEPTANCE 双记录：待 zcode lane 独立验收 → 串行 omp（`dual_acceptance =
  true`；本批无并发验收）。验收轮可补跑 --all 对账。

## §5 红线自证（机检）

| 门 | 结果 |
|---|---|
| `git diff 64634dc..HEAD` 六红线文件（MaskEdgeKernels.metal / MaskOverlayHost / LayerEditingState / MaskToolbarView / xcstrings / PipeCache） | **全空** |
| `readEdgeMap` 函数体 sed 抽取 md5 vs M4-2-01 evidence 副本 | 同值 `61c0001f…` |
| `readEdgeMap` 签名/缺省 | `maxLongEdge: Int = 512` 亲读不变 |
| 批内（`633378b`）PipeCoordinator diff | 调用点 1 行 + 邻注 4 行，逐 hunk 全览 |
| 零新 .metal / 零新文件 / `makeEncoder(functionName` 增量 | 0 / 0 / 0 |
| 主仓 probe 产物 | `git status` 无 evidence 命中（仅前波 OMP 验收记录 + 无关研究目录 untracked） |
| App 定向轮 | 见 §7（708/0/0 预期基线，零 App 测试增量） |
| 不 push | origin/main..HEAD = 前波 8 + 本批 1，全未推 |

## §6 移交 orchestrator（停止上报正本）

**phase 重裁三选一**（plan 风险节原 caméraman）：

1. **research 复审**——junction 门掉链（骑行 0.62）+ 端点贴脊失败形态指向
   walker/链接器算法层；分辨率杠杆已用尽（512→1024 只买到 0/8→2/8）。
2. **接受降级**——保留 1024 工作域 + `.snap` 默认，Follow Edges 以「观察中
   能力」挂账，待 GPU NMS 或 V3 换锚再启。
3. **GPU NMS 立项（OQ-2-B）**——1024 场 CPU 预提取 39.3ms 已贴 50ms 门
   （81%），2048 或 GPU 侧 NMS/链接是分辨率路径的下一级；立项裁决权在用户。

**产线 1024 改动保留在位**（`633378b`）——回退与否属三选一实体（「接受降级」
可含回退 512 的子选项；全指标 1024 严格优于 512，默认 `.snap` 下无用户可见
行为面变化，保留无风险）。**snap 臂真图行为注记**：两臂共用 edgeMapField，
1024 域改变 snap 真图搜索密度（合成 snap 门不受扰已绿；真图无门无走查）——
DECISIONS §5。

## §7 亲跑数字汇总

| 轮 | 结果 |
|---|---|
| Layers 定向（批内） | **422/3/0**（153s，peakRSS 1151MB） |
| RidgeExtractTests 单类 | 21/0/0（两轮：修负测前 21/1/0 → 修后 21/0/0） |
| App 定向 | **708/0/0**（362s，peakRSS 2832MB——前波逐位同值） |
| probe 双跑 | FAIL 2/8 双轮逐行一致（evidence 仓） |

对账：基线 3365/16/1 + Δ2（Layers 两法）→ 全套预期 **3367/16/1**（--all 未跑，
§4；验收轮对账）。

## §8 偏差申报（全量）

1. 邻注 4 行诚实化（§0，同缝零逻辑）。
2. probe main.swift 的 DIAG 反转为 512（门场 1024 后原 1024-DIAG 语义由门本
   身承载；512-DIAG 作跨批一致性锚——M4-2-01 数据逐值复现）。
3. 负测断言形态修正（n≥12 → 冻结值；DECISIONS §4 执行史实）。
4. BUNDLE-MAP 计数行 19→21 随批登记。
5. probe 编译告警 2 处（`key` unused warning，DIAG/确定性循环沿用 M4-2-01
   原文形态——证据保真优先，不改写）。

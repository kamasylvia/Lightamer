# M4-2-02 DECISIONS — 备用批执行裁决记录

> 批性质：条件触发批（M4-2-01 T5 FAIL 0/8 + 细脊缺响应三证 → armed）。
> 执行日：2026-10-10 夜。执行方 = subagent worker（夜间全自动授权在案）。
> 产线提交：`633378b`（T1 唯一提交——升参 + 两法 + BUNDLE-MAP 登记）。

## §0 触发三证（AC-1，逐条引用在案正本）

1. **主门 FAIL**：M4-2-01 T5 probe 双跑 `GATE t0.25: 0/8` + `GATE t0.15: 0/8`
   （evidence 仓 `m4-2-01/probe/probe.log` / `probe-run2.log`，zcode lane +
   omp lane 双验收亲读）。✅
2. **败因 = 细脊缺响应**：八景 bestN 全带 ≤7（5 seed 每景；A2 双阈字面 0，≥2 景
   要求远超满足）；DIAG mle=1024 行 `bestWalk n=24 arc=81px` 功能双腿满足——
   唯一变量 = 场分辨率，算法侧排除（审计注记：「到场链指标正常」严格读只在
   1024 诊断成立而非 512 场景行——判别不受翻转，双验收在案）。✅
3. **机制轨健康**：合成 9 景 golden 全绿 + snap 对照轨全绿 + 双跑确定性绿
   （Layers 420/3/0 含全部 19 RidgeExtractTests + 15 FollowEdgesTests）。✅

## §1 升参形态（KD-1，已裁形态零重开）

- **改动面 = 一处**：`PipeCoordinator.edgeMapField(for:)` 调用点
  `readEdgeMap(plane, metal:)` → `readEdgeMap(plane, maxLongEdge: 1024, metal: metal)`。
  `readEdgeMap` 签名 / 缺省 512 / 函数体零改（红线，机检见 SUMMARY）。
- **申报外扩（同缝注释）**：field cache 邻注的「≤512-guard」措辞同步改为
  1024 工作域描述（同文件同缝 4 行注释——不更新即文档滞后，§3.1 纪律）。
  零逻辑面。
- probe 同参：门场 1024（DIAG 反转 512 作对照），同 8 景盒 × 5 seed × 双阈。

## §2 预算阶梯裁决（KD-1 三档，T2）

**落位 = 第一档（≤50ms：维持原门）**。实测 @1024 场（probe x10，短命进程）：

| 行 | 实测 | 门 | 判 |
|---|---|---|---|
| 预提取 EXTRACT first-shot | 40.8ms | ≤50ms | PASS（81% 贴线但在档内） |
| 预提取 EXTRACT x10 median | 39.3ms（min 38.6） | ≤50ms | PASS |
| COLD GPU pass + 1024 读回 | 8.3ms median（6.3ms @512，+2ms） | V1 基线不动观察 | 预期 ~+6ms 级内 |
| 行走 carrier-hit | 0.007ms median / p90 0.011 | ≤5ms | PASS |

- plan 期「512 ~15ms → 1024 预期 ~60ms 可能越门」的猜测偏悲观——实测 4× 涨幅
  （9.4 → 39.3ms）仍在 50ms 门内。**无门修订申请、无停止上报**。
- 贴线注记：first-shot 40.8ms = 门值 81%，后续 phase 若场再升（2048）必越门——
  GPU NMS 逃生口（OQ-2-B）的立项论据加强，随三选一上报一并呈报。

## §3 真图门结果与停止裁决（AC-4，本批唯一上报点之外的第二上报点）

**门 = FAIL 2/8（阈值 ≥6；512 基线 0/8）→ 按 plan「1024 仍 <6/8：停」执行**：

- **T3 默认回翻不执行**（前置门 = 本批 T1 门 PASS，未满足）——`.snap` 熔断态
  维持，`LayerEditingState.swift:193` 零 diff，hint 键零写入，zh-audit 不触发
  （本批无新键）。
- **不三改**：无 2048 二级升级、无 GPU NMS kernel 化、无 walker 算法改动。
- **上报 orchestrator 三选一**（phase 重裁）：research 复审 / 接受降级 / GPU NMS
  立项。**产线 1024 改动保留在位**（`633378b`）——回退与否属三选一裁决面
  （「接受降级」选项的实体）；保留理由 = 全指标严格优于 512（2/8 > 0/8、链长
  45 vs 21、骑行 0.62 vs 0.38、预算在档）且生产默认 `.snap` 下无用户可见行为
  面（见 §5）。

### 门数据要点（evidence 仓 `m4-2-02/probe/`，双跑逐行一致）

- 功能景：t0.25 B3 YES（12 pts/34px）——M4-2-01 以来**首个**功能景；
  t0.15 A3 YES（13/39px）+ B3 YES（34/83px）。合计 2/8。
- 场/图统计：field 1024×682；candidates 3147→11305 / strong 586→2003 /
  domain 1289→5080（×4 域的预期放大）；t0.15 图 6693 链 / 19574 顶点 /
  最长链 60（512：4810/21）。
- 败景形态分化：A2 恒 0 候选（该区域 ≤1024 域仍无脊成形——非算法侧）；
  A 景 bestN=5/arc=89px 长行走但端点贴脊门不过（链端落在非候选区——junction
  网掉链后的漂移尾）；B/C 景链仍碎片化。DIAG-2 骑行分数 0.38→0.62（45 顶点
  链骑 28）——junction 门掉链为剩余主导瓶颈（算法层，分辨率单独不可达）。
- 协议一致性：DIAG mle=512 行（chains=1663/junctions=711/vertices=4810/
  longest=21，bestWalk n=7/arc=20px）与 M4-2-01 THRESH 0.15 门场值逐值一致
  ——跨批同场复现证明（协议未漂移）。

## §4 回归与负测（KD-2）

- `testReadEdgeMap1024WorkingDomainScalesWithNearestNeighborOrder`：
  1536×1024 源（长边 >1024 强制降采样支）→ 出场 1024×682（公式精确）+
  最近邻 box 序对 `+0.5·scale` 采样式全断言（角点 + 步进扫描 + 宽度钳制）+
  **缺省 512 不变断言**（红线：签名/缺省冻结的生产侧证）。
- `testExtractionPureDomainUnreachableByReadbackDomain`：直构场（无读回腿）
  提取 → 冻结 M4-2-01 拓扑值（chains=21/junctions=13/bridges=0/vertices=60/
  longest=11 + carrier 行走 n=5/arc≈28.2px）+ 双跑位等——`maxLongEdge` 在
  纯函数域无路径，生产工作域加宽不可能扰动任何合成门。
  执行注记：初版负测误施 probe 功能腿（n≥12）于合成弧景——该 fixture 的
  matrix 门是 hug/coverage（同场 5 点过 coverage 0.8），n≥12 属真图门定义；
  已改为冻结值形态（本条为执行史实记录，非缺陷）。
- Layers 422/3/0（基线 420 + 2 精确；peakRSS 1151MB 与前波 1152 同档）。

## §5 snap 臂真图行为注记（非门观察项，随上报呈送）

`edgeMapField` 是 follow-edges 交互两臂的共同入口（`FollowEdgesInteraction.chain`
先 fieldReader 后按 mode 分派）——1024 工作域同时改变 **snap 臂**（现缺省熔断态）
的真图 snapTarget 搜索密度（8px 半径内候选更密/更细）。合成 snap 门直构场、
不受扰（Layers 全绿亲证）；真图 snap 行为无门、无走查（本批半径外）。三选一
裁决若选「接受降级」或回退 512，此注记随之消解；若保留 1024，snap 真图手感
入下一轮 GUI 走查清单。

## §6 红线自证（T4，机检在 SUMMARY）

`64634dc..HEAD` 六红线文件零 diff；`readEdgeMap` 函数体 sed 抽取与前波逐字节同；
PipeCoordinator 批内 diff = 调用点 1 行 + 邻注 4 行（§1）。主仓 probe 产物零命中。

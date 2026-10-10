# M4-2-03: Follow Edges 算法层迭代 — Context（research 复审）

> discuss/research 起草稿（2026-10-10）。批次定位 = M4-2-02 停止上报
> 「三选一」的**用户裁决①：research 复审（算法层迭代）**——junction 门掉链
> 与端点贴脊 fail 两瓶颈的机理复盘 + 迭代方向调研 + 方案草案。
> 证据正本 = evidence 仓 `m4-2-02/probe/`（probe.log 双跑）+ 本目录
> `RESEARCH-NOTES.md` **Part 2 §8-10**（2026-10-10 诊断探针实测：死因分类 /
> gate 扫频 / 方案 A 模拟门影响——本文件只引结论，数字正本在彼处）。
> **本批走 C 档第 1 停：research 定稿后停等用户过目 OQ（文末）再 plan。**

## 机理结论摘要（详见 RESEARCH-NOTES §8）

诊断探针（M2-7-3 先例，evidence 源 verbatim + traced-walk 复刻，8 景 bestN
与 probe.log 逐值一致保真）实测**推翻 M4-2-02 的两个读解、确认一个**：

1. **端点贴脊门不是瓶颈**——best 链两端到最近候选 0-1px（8 景全过）；
   M4-2-02「A 景链端落在非候选区」读解有误，A 景实际卡 **n≥12 出点数腿**。
2. **arc≥24 腿被弦线代偿**——出点间隙实测最大 27.8px（设计上限 4px），
   弧长数字含直线弦，输出折线不贴脊。
3. **n 腿真瓶颈 = 行走器三机理**（非提取侧、非阈值侧）：①ping-pong 死循环
   （无 visited 守卫：C2 景 4080 步/1813 穿越被 fuse 砍杀，出点 ≈1）
   ②deficit 穿越重置饥饿（短链占七成 → 积累永不出点 → 弦线）③junction 门
   截停（次要：RIDE@0.25 双向死于 bestCos=0.37<0.5；gate 扫频 0.5→0.0 只买
   +2 点——**参数不可救**）。
4. 「junction 门掉链」的正式判别 = **算法结构缺环节为主（无防绕/无回退/
   无前瞻）+ 判据设计错为辅（deficit 重置语义）**；「端点贴脊 fail」=
   **判据设计错**（n≥12 腿是 V1 固定步距时代的隐含假设，与 V2 自适应步长
   0.75-4px 数学不相容：24px 直脊最多 ~7 出点）。

## 方案草案摘要（详见 RESEARCH-NOTES §10）

| 方案 | 面 | 模拟实测门影响 | 风险 |
|---|---|---|---|
| **A 行走纪律修复（推荐先行）** | `FollowEdges.swift` walker 内部：防绕 visited + next-best 回退、deficit 跨穿越携带（跳跃距离计入）、gate 0.5 不动 | **t0.25 1/8→3/8、t0.15 2/8→4/8**（A 景 5→27 点翻功能；C2 4080 步→26 步） | 出点数/间距 golden 重推导；RidgeExtractTests 零触 |
| B junction 簇合并+前瞻评分 | `RidgeExtract.link` 后处理 | +0~1 景（残余败景非 junction 噪声死） | 冻结拓扑 golden 全重冻结 |
| C 提取连通性补强 | 桥接 3→5-6px 方向感知 / 滞回 low 下调 | P1 后残余 4 败景（free-end/短链）的针对性杠杆；C/C2 翻否须实证 | 纹理假桥；冻结值重冻结 |
| 接受降级 | P1 后 4/8 + 门修订，挂账「观察中能力」 | — | = OQ-1 选项 3 |

推荐 = **A 先行单执行批 → probe 复跑对账 → 若停 4/8 再裁 C**。6/8 直达无
把握（A+C 才有路径；A2 恒不可救 = 门容错对象），如实上报不粉饰。

## 执行批边界（建议，plan 期细化）

- **零变化红线**：`RidgeExtract.swift`（方案 A 不触）/ `MaskEdgeKernels.metal`
  / 参数面（`FollowEdgesParams` 字段与缺省值）/ `.snap` 分支 / App 接线
  （`PipeCoordinator` carrier / `MaskOverlayHost` 交互腿）。
- **probe 归档**：执行批 probe 复跑落 evidence 仓 `m4-2-03/probe/`（同协议
  双跑）；本批 /tmp 诊断源按 M2-7-3 先例随批归档。
- **测试**：`FollowEdgesTests` +4-6 法（LAYERS 域规则 + BUNDLE-MAP 登记 +
  `tuist generate` 收尾，L041）；probe 门定义若修订（OQ-2）须新旧双轨并行
  一轮保可比性。

## Open Questions（每条含推荐；C 档第 1 停裁决点）

### OQ-1 迭代方案选择（必裁）
- **A（推荐）**：**方案 A 先行单执行批**（行走纪律修复）→ probe 复跑对账
  （预期 ~4/8）→ 停 4/8 再裁是否批方案 C。理由：三机理两个半在 walker 内、
  模拟实测 +2 景、零提取侧 golden 冲击、单 plan 可闭环。
- B：**A+C 同批**——6/8 概率最高的一次性尝试；代价 = 冻结拓扑 golden 全
  重冻结 + 假桥风险同批引入，归因困难（walker 修复与连通性收益无法分账）。
- C：**接受降级**——现状 2/8 + 门修订挂账「观察中能力」，算法层迭代关闭
  （M4-2-02 三选一的选项 2 晚到形态）。
**推荐 A**；选 B 须接受归因混合，选 C 则本 CONTEXT 其余 OQ 作废。

### OQ-2 真图门定义修订（n≥12 腿失配 + 端点门改逐点贴脊率）
- **A（推荐）**：**门定义 v2 = 弧长 ≥24px ∧ 逐点贴脊率 ≥90%（2px 门）∧
  出点 ≥8（可用性地板）**。依据：n≥12 与 4px 步距数学不相容（24px 直脊
  最多 ~7 点，RESEARCH §8.4）；逐点贴脊率是弦线检测器（gap 与离脊强相关），
  比「端点贴脊」实质化；probe `main.swift` 门段同批改版。
- B：**保留 n≥12，把 `resampleMaxStep` 4→2px**——出点加倍凑腿；代价 =
  maxPoints 256 帽更早触顶（长链截断）+ 出点密度无用户价值。
- C：**门完全不动**——用 V1 步距时代的门量 V2 步距时代的输出，系统性
  误判（弦线假阳性过 arc 腿、饥饿假阴性挂 n 腿），数据失真。
**推荐 A**；旧门数据（M4-2-01/02）不重算，新门双轨并行一轮（probe 打印
两版 GATE 行）保跨批可比。

### OQ-3 followStrength 缺省值（0.5 维持 / 下调 / 前瞻评分后重定）
- **A（推荐）**：**维持 0.5 不动**。依据：gate 扫频 0.5→0.0 在 45 链只买
  +2 出点、60 链零变化；P1 模拟后残余 gate-blocked 全是「候选耗尽」型
  （next-best 回退已消费），非门型截停——下调无靶。
- B：**下调 0.35**——解锁 bestCos≈0.37-0.39 档截停；但真交叉点横穿边
  离开角 ~90°（cos≈0）仍被拒，收益与 §9.1 前瞻评分重叠且后者无副作用。
- C：**随方案 B 前瞻评分落地后按实测重定**——若 OQ-1 选 A 且 P2（方案 C）
  后仍有门型截停再议。
**推荐 A**；参数面零变化 = `MaskToolbarView`/xcstrings 零 diff 红线延续。

### OQ-4 合成 golden 冲击面处置（方案 A 的断言迁移）
- **A（推荐）**：**几何断言零删 + 出点数/间距断言按新语义重推导**——贴脊
  距离/覆盖率/确定性/`.snap` 冻结全保留；出点数与步距类断言在 deficit 携带
  语义下重新推导并在注释标注 v2 语义；**新增无弦线断言**（相邻出点间隙
  ≤4.5px+ε——弦线回归的哨兵）。`RidgeExtractTests` 21 法零触（提取函数
  不动，M4-2-01/02 冻结拓扑值不作废——方案 A 不批 B/C 的前提红利）。
- B：**冻结值全保留加豁免清单**——断言不动、失败用例显式 skip 等修；
  skip = 撒绿，违背「golden 必须含能杀死旧版的景」教训（RESEARCH §1.2）。
**推荐 A**；重推导值在 plan 期按实测收窄钉门（M3-3-E5 先例）。

### OQ-5 6/8 门目标与分期核对点（维持 / 调门 / 分期）
- **A（推荐）**：**6/8 总门维持 + P1 后设中期核对点**——P1 执行批 probe
  复跑如实上报（预期 ~4/8），不停批不降门；方案 C 批后对 6/8 终裁；若
  C 批后 5/8 且败景均为无脊/纯碎片区（A2 形态）→ 回 OQ-1 三选一（降级
  挂账合法）。理由：A2 恒不可救说明 6/8 本身含 2 景结构性容错，调总门
  会把「算法可达」与「场上有脊」两件事混在一个数里。
- B：**总门下调 5/8**——一次性了断；代价 = 把提取侧连通性缺口合法化。
- C：**拆两期门**（P1 后 4/8 即收 + P2 后 6/8）——与 A 等价但少了终裁
  回退点，降级路径变模糊。
**推荐 A**。

### OQ-6 GPU NMS / 2048 分辨率立项时点（M4-2-02 OQ-2-B 延续）
- **A（推荐）**：**本批不立项，P2（方案 C）后仍 <6/8 且败景形态指向
  分辨率（细脊整条缺席）再立项**。依据：EXTRACT @1024 已 39.3ms 贴
  50ms 门（81%），2048 CPU 必越门；GPU NMS = 新 kernel + PSO + GPU golden
  ——量级为一个独立 phase，且其收益（B/C 景细脊成形）与方案 C 部分重叠，
  应先花便宜的。
- B：**随方案 A 同批立项**——分辨率杠杆一次拉满；代价 = walker 修复与
  提取换轨同批，归因混合（同 OQ-1-B 病）+ 预算门必重开。
**推荐 A**；立项触发形态 = C 批 probe 复跑的败景形态判别（细脊缺席 vs
碎片断隙是两条不同处方）。

## Canonical References

- RESEARCH-NOTES.md **Part 2 §8-10**（本批机理实测/调研/方案草案正本）
- `M4-2-02-SUMMARY.md`/`M4-2-02-DECISIONS.md`（停止上报正本 + 三选一）
- evidence 仓 `m4-2-02/probe/`（probe.log 双跑 + main.swift 门定义）+
  `m4-2-01/probe/`（512 基线）
- `M4-2-CONTEXT.md`（原 research OQ-1..7 已裁全 A）+ `M4-2-01-DECISIONS.md`
  （KD-1 预算阶梯）/`M4-2-01-ACCEPTANCE-OMP.md`（DIAG-2 骑行定性）
- 源码：`LightamerCore/Sources/Layers/Masks/FollowEdges.swift`（walk /
  continuationFrom / stepGuard / readEdgeMap）+
  `LightamerCore/Sources/Layers/Masks/RidgeExtract.swift`（六段流水线）
- `Tests/LightamerTests/FollowEdgesTests.swift`（15 法）+
  `Tests/LightamerTests/RidgeExtractTests.swift`（21 法，冻结拓扑值）

## C 档第 1 停（research 定稿停等裁决）

本 CONTEXT 与 RESEARCH-NOTES.md Part 2 为 M4-2-03 research 定稿产出（一笔
docs commit，未 push，零源码）。**按 AGENTS.md「C 档门控」第 1 条：research
定稿后停——等用户过目 OQ-1..6（尤其 OQ-1 方案选择 / OQ-2 门定义修订 /
OQ-5 分期核对点）裁决后再入 plan。**晨审可整批推翻；推翻任一条 = 修订对应
plan（CONTEXT OQ 原文不改、以 Ruling 注记为准，沿 M2-3-CONTEXT E1 先例）。

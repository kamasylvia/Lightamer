# M4-2-01 SUMMARY — Follow Edges V2 换锚全量批（T5 门 FAIL，T6 未执行，M4-2-02 armed）

> 执行 subagent worker，2026-10-10 夜间批。HEAD 起点 `64634dc`；基线 3335/16/0。
> 本批 5 个执行 commit（T1..T4 + 证据 commit 在 evidence 仓）+ T5 FAIL + T6 按门未执行。
> **门判定的裁决数据齐备**，M4-2-02（P2 升级口）触发判定 = **armed**（KD-5 三分支之
> 「细脊缺响应」，DIAG 亲证）；「算法失稳」观察项一条随报。

## 任务序与提交

| 任务 | commit | 内容 | 结果 |
|---|---|---|---|
| T2 前置 | （随 T1） | DECISIONS 四行钉死（E1 处方甲 / M1 双撤出 / M2 再附图半径 / M3 平手 tie-break） | 放行条件落盘 |
| T1 | `9d7db87` | RidgeExtract.swift 六段流水线 + RidgeGraph/RidgeChain/RidgeJunction/RidgeBridge 类型 + RidgeExtractTests 10 法 | Layers 404/3/0 |
| T2 | `3b3d7fc` | .streamline 换锚 RidgeGraph 消费者 + V1 walker 同批删除（金与删同批单提交）+ params 双撤出 + EdgeMapField.ridges additive + FollowEdgesTests +7 法（点数门实测重校） | Layers 411/3/0 + App 704/0/0 |
| T3 | `163a63d` | 九景 golden 矩阵 +9 法 + 链接器 junction 共享修复 + junction 整像素裁定 + snap 对照轨 | Layers 420/3/0 |
| T4 | （见 git log） | FollowEdgesRidgeCache（折键/LRU 8）+ edgeMapField 注入缝 + FollowEdgesRidgeCacheTests 4 法 + 计数器机检缝 | App 708/0/0 |
| T5 | evidence 仓 `156b7cf` | 真图 8 景盒 × {0.25, 0.15} × 5 seed 双跑 probe | **门 FAIL 0/8** |
| T6 | **未执行** | 门 = T5 PASS；T5 FAIL → 按 KD-5 三分支处置，缺省回翻不做（`.snap` 缺省维持） | — |

测试增量：**+30**（plan 预估 +21..29，实际 +30：T1 +10 / T2 +7 / T3 +9 / T4 +4）。
对账：**3335 + 30 = 3365** = Layers 420 + App 708 + 其余五 bundle 3174−（394+704）+（420+708）… 全套对账以 IOP 562 / IOPParity 427 / Library 619 / Sessions 279 / Export 350（基线数）+ 420 + 708 = 3365。

## 交付面（与 plan front-matter 对射）

- ✅ RidgeExtract.swift（KD-1 六段：轻高斯 σ0.9 → 中心差分 → 张量取向 → NMS 非对称 tie → 滞回 r0.4 → 行主序链接 + B3 桥接 + junction 记录 → ±2 质心 clamp1.5）
- ✅ .streamline 臂换锚（KD-2：8px 附着 / 双向 / junction 贪心 followStrength 门 / 自适应重采样 0.75..4px θ45° / maxPoints 256 fuse）
- ✅ V1 删除（OQ-7：initialHeading / strongestRingGradient / lookahead / 动量 λ 全仓 grep 零命中；stepPixels/maxPoints 零命中，maxPoints 仅 FollowEdges.swift）
- ✅ EdgeMapField.ridges additive（缺省 nil 零漂移）+ .snap/snapTarget/readEdgeMap/edgeMap 函数体逐字节零 diff（awk 抽取 diff 亲证）
- ✅ App carrier（KD-4：折键 prefixHash⊕thresholdBits / LRU 8 / 计数器机检缝 / 注入缝）
- ✅ golden 三轨之合成轨 + snap 对照轨（九景 + 双跑逐字节 + snap 冻结三景常量）；**真图轨 FAIL**（见下）
- ✅ 性能探针：预提取 9.3-10.0ms @512（预算 ≤50ms，**5 倍余量**）；行走 carrier-hit 0.002ms（≤5ms）；edge map 冷 6.3ms（V1 基线不动）
- ❌ 真图轨：**0/8（{0.25, 0.15} 双阈）**——证据 = evidence 仓 `m4-2-01/probe/`（main.swift + 源清单 + probe.log/probe-run2.log 双跑逐行一致 + MANIFEST）

## T5 门 FAIL 判定数据（KD-5 三分支裁决输入）

- **协议**：M2-7-3 同款 8 景盒 × 5 seed（argmax + 4 扰动），双阈 {0.25, 0.15}（V1 同款网格）；功能链 = ≥12 点 ∧ ≥24px（场域）∧ 端点贴 candidate ≤2px；双跑逐行一致（DETERMINISM true）。
- **V2 vs V1 同协议**：V1 = 0/8（链 ≤3 点/≤4px、82/100 空链）；V2 = 0/8 但 attach 至 5/5、弧长至 22px（B2@0.15 20px / A3@0.15 22px——距 24px bar 一步之遥）。**V2 实质性优于 V1，但未过门。**
- **DIAG-1（mle=1024 扫频，P2 目标面）**：field 1024×682，graph 6693 chains/19574 vertices/longest 60，best walk **24 点 / 81px**——功能双腿（≥12 点 ∧ ≥24px）均满足 → **细脊缺响应（机理④）为主导限制，P2 升级口有效，M4-2-02 = armed**。
- **DIAG-2（纯骑行试验）**：最长链（16 顶点）中点附着骑行仅 6 点（fraction 0.38）——碎片网 junction 门/绕行致骑行掉链 = **算法层观察项，随报**（非本 plan 修复面）。
- **field 形态数据**：t0.25 domain 1289px / chains 598 / junctions 213；t0.15 domain 3259px / chains 1663 / junctions 711（均值链长 ~2.9 顶点）——真场在 ≤512 域就是碎片网（机理②④ 亲证），拓扑存在但无能骑的长链。

## 实测带与关键裁定（正本 = DECISIONS）

- 点数门重校：直脊 ≥30→≥12（实测 16）；L 角 ≥20→≥12（实测 17）。
- 九景真值距离最差 **0.235px**（纹理景；门 0.75 未校准即过）；覆盖最差 **0.90**（断隙景；门 0.80）。
- Steger 对照带：直脊+弧线 max deviation **0.0**（对称 fixture 双估计量退化，证据带 ≤0.5 在册）。
- fuse 恰 256（2000px 长脊）；九景 walk n ∈ [5, 17]。
- 6 项执行中裁定（张量取向 / NMS tie 约定 / 交叉环拓扑 / pairBridges 抽纯函数 / 滞回 raw 门 / junction 整像素 + 共享修复）+ 4 项偏差注记 = DECISIONS §1/§3。

## 红线自证

- `MaskEdgeKernels.metal` 零 diff；`MaskOverlayHost.swift` 零 diff；`PipeCache.swift` 零 diff（git diff 空）。
- `snap`/`snapTarget`/`readEdgeMap`/`edgeMap` 函数体逐字节零 diff（awk 按函数抽取 diff 亲证，T2 commit 前）。
- `stepPixels`/`initialHeading`/`strongestRingGradient` 全仓零命中；`maxPoints` 仅 FollowEdges.swift（M1）。
- MaskRevisionTests 真产线腿两法零改绿（11/0/0 单类轮亲证——且其失败倒逼出滞回 raw 门连续性修复）；FollowEdgesTests 既有 8 法几何断言逐字保留（仅点数门实测重校 + :91 调用点随双撤出更新）。
- 主仓 git status 零 evidence/probe 命中（机检亲证）。
- 零 PSO 增量 / 零新 kernel / 零 function constant；sidecar/Library 零触碰。

## 已知偏差与挂账（正本 = DECISIONS §3）

1. **活动阈值管线缺口**：surface.edgeThreshold 缺省 0.25（overlay 腿冻结不可穿线）；非缺省阈值走 walker lazy 路径（RidgeGraph.high 戳拒绝，行为正确不缓存）——观察项（修复需出 plan 边界）。
2. **testRestoreWinsOverDerive 间歇失败**：M4-1 挂账 #6 同族（T3 基线 stash 复现、隔离/带载/重跑通过，App 708/0/0 终值绿）——与本批零相关，随报。
3. **DIAG-2 骑行分数 0.38**：碎片网 junction 门致骑行掉链——算法层观察项，交 M4-2-02/后续 ruling。

## 下一步（orchestrator 裁决点）

1. **M4-2-02（P2 512→1024 升级口）= armed**：DIAG-1 亲证升级后功能双腿可满足；触发分支 = KD-5 三分支之「细脊缺响应 → P2」。
2. 双重验收（dual_acceptance）：zcode 独立验收 → 串行 omp 二次验收 → M4-2-01-ACCEPTANCE.md（本 SUMMARY 为执行方自证，验收尚未跑）。
3. 全套 `--all` 对账轮（3365 预期）建议随验收波执行（本批定向轮 Layers 420/3/0 + App 708/0/0 已绿）。
4. `.snap` 缺省维持（T6 未执行）——熔断态不变，直到某批真图门 PASS 后按 OQ-5 回翻。

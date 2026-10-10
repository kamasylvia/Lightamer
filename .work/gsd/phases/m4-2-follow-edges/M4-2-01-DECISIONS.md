# M4-2-01 DECISIONS — Follow Edges V2 换锚全量批

> 状态：执行期账本（T2 动工前置四行先行落盘，checker 放行条件；T7 收口补全）。
> 裁决正本 = `M4-2-CONTEXT.md` 裁决记录（OQ-1..7 全 A）+ `M4-2-01-PLAN.md`
> 「checker 回注（2026-10-09）」引注块。本文件记录落地裁定 / 实测带 / 偏差注记。

## 0. 动工前置四行（checker 回注钉死，2026-10-09 落盘——放行条件）

- **E1（处方甲）**：断隙桥接对齐门 = **提取期内部常量 0.5**（`RidgeExtract.bridgeAlignmentGate`），
  提取签名 = `RidgeExtract.graph(from:high:)`——**无 followStrengthBridgeGate 形参**；
  `followStrength` 语义收窄为**行走期 junction 延续偏置**（提取面零消费）。OQ-4
  「断隙桥接同门」按偏差注记收窄（裁决本体零重开）；KD-4 缓存键
  `prefixHash ⊕ edgeThreshold.bitPattern` 原样（键不含 strength）；
  KD-2①「同 field 同 edgeThreshold 同输出」恢复为真纯函数声明。
- **M1（maxPoints 双撤出）**：`FollowEdgesParams.maxPoints` **params 字段撤出**（与
  stepPixels 同批）；链 fuse 转 **FollowEdges.swift 内部常量 256**。收口 grep 门：
  `maxPoints` 全仓仅 FollowEdges.swift 单文件命中；params 字段零命中。
- **M2（再附图半径）**：空链降级回退臂的**再附图搜索半径 = 同 8px**，从 `snapTarget`
  （V1 同款 8px 最强邻，阈值门）落点起算，`snapTarget` 同族几何，tie-break 同
  距²序 → 行主序；双路径都空才空链。
- **M3（junction 平手 tie-break）**：余弦平手（含全零候选域）决胜序 = **候选分支按
  其「junction 后首顶点」行主序（y 优先、x 次之）枚举 + argmax 严格大于首中即胜**；
  T 分叉景 followStrength {0.2, 0.8} 两档远离平手域，golden 不受影响。

## 1. 落地裁定（执行中新增，按任务序追加）

（T7 收口补全）

## 2. 实测带（点数门重校 / Steger 对照 / 性能）

（T3/T5 实测后补全）

## 3. 偏差注记（申报外扩 / 计划内收窄）

（T7 收口补全）

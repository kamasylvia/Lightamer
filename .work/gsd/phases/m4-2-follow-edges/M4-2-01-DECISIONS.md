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

- **T1（2026-10-10）NMS/质心方向 = 结构张量取向场**：幅值脊自身逐像素梯度在
  脊顶像素处恒为零（对称局部极大）——plan 原文「梯度：中心差分」的逐像素读法
  在 NMS 必须判决的像素上退化（golden 亲证：直脊零链）。方向改读
  **±2 窗外积平滑（结构张量）主取向**（θ = ½·atan2(2b, a−c)，符号归一：
  首非零分量取正），梯度本体仍是平滑场上的中心差分。钉死常量
  `orientationRadius = 2`。
- **T1（2026-10-10）NMS 非对称 tie 约定**：`v > S(p+e) && v >= S(p−e)` 的严格侧
  = **沿取向 +e 侧**。等幅双行平台解出到单行（+e 侧行存活）——确定性；对称双行
  脊「双双抑制」不发生。
- **T1（2026-10-10）交叉中心 NMS 抑制 = 本征行为**：多臂交汇处沿任一臂都是
  平台 → 中心像素被抑制，细化成小环（cross 景 5 junctions/12 chains，全连通）。
  golden 按观测拓扑钉（连通性 + 环 junction 度 + 四臂触达），不假造单点 junction。
- **T2（2026-10-10）桥接配对 = 纯函数 `pairBridges`**：σ0.9 平滑已把小直隙熔接
  （涂绘 fixture 上 2-3px 直隙合并成单链），图级 fixture 无法诚实驱动桥接门——
  配对逻辑抽纯函数直测（门/贪心/tie-break/对齐拒绝/junction 端保留五断言）；
  行走级过桥由 T3 断隙景（Bresenham 1px 双段 1px 隙）钉。
- **T2（2026-10-10）滞回门读数 = raw 场值**：σ0.9 平滑在 1-2px 细脊上损失约
  33% 幅值（Sobel 步沿 0.354→0.236 < 默认阈 0.25）——MaskRevisionTests 产线腿
  （真 kernel + 真读回）当场抓住。low/high 门读 **raw 原始场值**（V1 连续量），
  NMS 几何与质心剖面仍读平滑场。
- **T3（2026-10-10）junction 像素免质心细化**：±2 剖面在交汇处混入多支质量，
  1D 剖面非脊——细化会挪动拓扑节点并糊化分支切向（T 分叉景 differential 因此
  崩塌）。junction 像素保持整像素位置，非 junction 顶点照常细化。
- **T3（2026-10-10）链接器 junction 共享修复**：junction 像素被首条 trace 标
  visited 后，后续到达的 trace 曾停在 1px 外且不记 attachment（junction 只连
  第一条链，walker 直穿 T 不转弯）——修复 = 到达已 visited 的 junction 时仍
  append + 记 attachment。
- **T3（2026-10-10）snap 对照轨门读法**：snapTarget = 「12px 内最强像素」
  （tie → 扫描序首个），均匀脊上距最近顶点附着点沿脊可达 12px（实测 12.0）——
  「首点落 snapTarget 结果 2px 邻域」按 plan 意图「共享贴边几何」执行：
  首点与 snap 结果各自距真值折线 ≤2px（同一贴边）。

## 2. 实测带（点数门重校 / Steger 对照 / 性能）

- **T2 点数门重校（实测）**：直脊 64px 景 n=16（门 ≥30 → **≥12**）；L 角景
  n=17（门 ≥20 → **≥12**）——自适应重采样（直段 ~4px 间距、弯道加密）下旧
  逐点门不再成立，重校值留一倍余量。
- **T3 九景矩阵实测带（2026-10-10）**：真值距离最差 **0.235px**（纹理景，
  门 0.75px 不需校准即全过）；覆盖最差 **0.90**（断隙景，门 0.80 同）。
  分景：straight 0.000/1.00 · arc 0.037/0.91 · L 0.162/1.00 · T-s0.2
  0.181/0.94 · T-s0.8 0.000/0.96（停驻 stem）· bridged-gap 0.000/0.90 ·
  parallel 单侧 0.000 · dip 0.000/1.00 · texture 0.235/0.94 · varying
  0.000/1.00。T 分叉 differential：s0.2 上 A 支（min y 23）· s0.8 停
  junction（max x 32）。
- **T3 Steger 对照带**：直脊 + 弧线 max |δ_taylor − δ_centroid| 实测
  （Layers 轮日志 `[M4-2-01] Steger-Taylor ...` 行，≤0.5 证据带内）。
- **点数**：fuse 恰 256（2000px 长脊）；九景 walk n ∈ [5, 17]。

## 3. 偏差注记（申报外扩 / 计划内收窄）

（T7 收口补全）

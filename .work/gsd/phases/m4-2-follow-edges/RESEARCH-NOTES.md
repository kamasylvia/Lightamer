# M4-2 Research Notes — Follow Edges V2 换锚重做（脊线预提取 / 亚像素质心 / 自适应步长）

> research 底稿（2026-10-09，正文中文）。证据正本 = evidence 仓 `phases/m2-7-masks/evidence/m2-7-3/probe/probe.log`（主仓已剥离；本文件引用的实录数字逐值可对）。配套裁决文档 = 同目录 `M4-2-CONTEXT.md`（OQ-1..7）。

## 1. V1 失稳机理复盘（probe 实录 + 源码逐行对照）

### 1.1 实录基线（DSC00012.ARW 60.2MP → preview 2560×1707 → ≤512 场）

| 指标 | 实测值 | 含义 |
|---|---|---|
| FIELD stats | max=0.4941 / mean=0.018 / p99=0.1808 | 真实照片幅值场：99% 像素 < 0.181，默认阈 0.25 过不掉 p99——场是**稀疏碎片**而非连续曲线 |
| streamline 链长（8 景 × 2 阈 0.25/0.15） | n ≤ 3 点，len ≤ 4px，meanMag 0.23→0 | 步 1-2 步即出脊断链 |
| 100-seed 网格 | 82/100 空链 | 种子贴边后仍无可走路径 |
| 场分辨率扫频（mle=1024/2560 × 步长 1.5/0.75） | functionalChains **0/3** 全档 | 降采样假说排除——分辨率/步长均非根因 |
| snap 对照 | 12px 触达内确定性 2 点贴边 | 贴边几何（找最强邻）本身是稳的；不稳的是**沿脊行走** |
| 冷/热成本 | 6.3ms / 0.001ms | 预算从不是问题（判据① 200ms 门远未触） |

### 1.2 机理四条（与 V1 源码逐段对应）

1. **朝向信号结构性缺失**（`FollowEdges.streamline` 的 lookahead 腿）：梯度幅值脊的脊线上，沿脊方向中心差分梯度 ≈ 0（crest self-sample vanishes——V1 头注已自知）。V1 的对策是「lookahead 侧翼采样」：在 `position + direction*step` 处取梯度，其旋转 90° 作切向。该对策隐含**脊宽 ≥ 2-3px** 的前提；真实 Sobel 脊 1-2px 宽（≤512 场降采样后更窄），步长 1.5px 的 lookahead 一脚跨过对侧 flank——读到的要么是场底噪声、要么是相邻另一条边的场，切向随机翻转 → 下一步出脊 → `sample(next) < threshold` 断链。probe 的 `n=1-3 / meanMag=0.226→0` 逐值吻合。
2. **幅值场非连续脊网络**：纹理、噪声、软过渡把场打成短碎片（mean 0.018）；经典边缘检测（Canny 族）在梯度幅值之后还有 **NMS → 滞回 → 链接** 三段把碎片织成拓扑曲线——V1 缺了整个后半段，让 walker 直接在原始幅值汤上走，逢隙即停（82/100 空）。
3. **单绝对阈语义错位**：非平稳场上一个绝对阈无法同时「纳入弱边」与「排除纹理」。滞回（high + low = r·high）是标准解：强点作种、弱点凭连通性入围。
4. **最近邻降采样放大前两条**（次因）：`readEdgeMap` 的 5× 最近邻抽点让 1-2px 细脊大概率整条消失。mle 扫频证明它不是唯一根因，但它使问题更糟——V2 保留 ≤512 工作域（预算纪律）因此必须在提取算法内补偿（提取前的轻高斯 + 滞回 low 腿）。

**V1 合成测试全绿的原因**：fixture（`verticalRidgeField` 等）幅值 1.0、脊宽 3px（±1.5 falloff）、全域连续、无纹理——四条机理逐条不成立。教训：golden 必须含「能杀死 V1 的景」（RESEARCH-NOTES §5）。

## 2. 算法调研与参考仓检索结论（2026-10-09 全文检索实测）

| 来源 | 检索结果 | 结论 |
|---|---|---|
| Alcedo（GPL-3.0，功能对标正本） | `src/` 全文无 follow/edge-aware brush；mask 域仅 analytic/brush/raster 型；docs roadmap 唯一 edge 命中为 gradient node 高度语义（无关） | Alcedo 无此功能，无可参考实现 |
| Nitro Photo | 无源码（手册描述级，M2-7-CONTEXT OQ-4 已裁） | 自研唯一路径（D-M2-7-CONTEXT-4-A 沿袭） |
| darktable（GPL-3.0 只读） | 无轮廓跟随笔刷；`hlreconstruct/segbased.c` 的 ridge 为高光重建分割语义（非曲线提取）；`ashift_nmsimplex.c` 的 NMS 是 Nelder-Mead Simplex 优化器（非 non-max suppression） | 无先例可搬；算法取自公开文献域 |
| Lumen（MIT） | `auto_masks.py` = MiDaS 深度 + 语义掩码，无边缘跟随 | 无先例 |

⇒ V2 = 自研算法级新需求（IOP-MASK-06 原定性不变）。候选方案对比：

### 2.1 候选对比

| 方案 | 思路 | 亚像素 | 确定性/可测性 | 复杂度 | 判定 |
|---|---|---|---|---|---|
| **A. Canny 式 NMS+滞回+链接（推荐）** | 幅值场 → 非极大值抑制 → 1px 候选脊 → 滞回 → 8 连通追踪成折线 + 断隙桥接 | 由质心件补（§3.2） | 每阶段独立 golden；纯函数 O(N) | 低-中 | **选型** |
| B. Steger 曲线检测 | 高斯平滑场 Hessian 特征分解，主曲率法向 1D Taylor 位移定亚像素脊点，主方向延续 | 最高（理论最优） | 可纯函数；二阶导噪声敏感、调参面大 | 中-高 | 弃产线；Taylor 式作 golden 对照 |
| C. 结构张量取向场 + 流线积分 | 张量各向同性扩散出连续取向场，欧拉/龙格积分沿场走 | 无（需另补） | 扩散迭代难 golden；积分阶段把 V1 同款漂移请回 | 高 | 弃 |
| D. 二值骨架化 | 阈值二值 → 形态细化 | 无 | 可测但断枝密布 | 低 | 弃 |

选 A 的决定性理由：**与三件套分解天然对齐**（NMS/滞回/链接治机理②③、质心治①定位半、自适应步长治①步进半）；每阶段输出可独立构造真值做 golden；在 ≤512 工作域毫秒级。

## 3. V2 设计草案（三件套细则，plan 期细化落点）

### 3.1 脊线预提取（`RidgeExtract.swift`，Core 新文件，全纯函数）

```
输入: EdgeMapField（≤512 场，既有读回域不变）
① 可选轻高斯 σ≈0.8-1.0（可分离核，CPU；稳定质心与曲率估计；补机理④）
② 梯度（中心差分）→ NMS：沿梯度方向 ±1 采样（4 象限线性插值取亚像素比较值），
   本点 < 两侧任一 → 抑制；过阈（low）者入候选图
③ 滞回：high = edgeThreshold（既有参数平移），low = r·high（r≈0.4 内部常量）；
   强点（≥high）行主序作种 → 8 连通生长收集 ≥low 连通域
④ 链接：行主序确定性追踪 → 折线集；断隙 ≤B px（B≈2-3）按「端点距 + 方向对齐」
   最近端桥接（tie-break 显式：距²序 → 行主序）；交叉点（度 ≥3）记 junction 节点
输出: RidgeGraph = [RidgeChain]（亚像素顶点折线 + 链端点/junction 连接关系）
```

- **确定性纪律**：行主序扫描 / argmax 首中即胜 / 显式 tie-break / 无 RNG——双跑逐字节 golden。
- **复杂度**：全阶段 O(N)（N = 场像素数）；512×341 ≈ 175k px，Swift 串行预计毫秒级（§6 预算）。

### 3.2 亚像素质心（每 NMS 候选点一次）

对候选点 p（整点）、单位法向 n = g/|g|（g = 该点梯度）：

```
剖面采样: f_k = bilinear(field, p + k·n),  k ∈ {-2,-1,0,1,2}
背景扣除: w_k = max(f_k − low, 0)
质心位移: δ = Σ k·w_k / Σ w_k     （Σw < ε → δ = 0；|δ| ≤ 1.5 clamp）
细化点:   p* = p + δ·n
```

- 有界（权重非负、位移 clamp）、对不对称脊稳健、纯函数；对照参考 = Steger 1D Taylor 位移 δ = −d1/d2（d2≈0 病态点需 guard）——golden 批可作 A/B 对照腿验证质心质量，不进产线（OQ-1）。
- 精度预期：合成脊上 ≤0.3px；golden 门取 0.75px（含场噪声余量）。

### 3.3 图上行走 + 自适应步长（`.streamline` 臂新内部）

- **seed 接入**：seed → 最近 `RidgeChain` 顶点（半径 8px，`snapTarget` 同族几何）→ 无命中 = 空链降级（语义与 V1 逐字一致）。
- **双向遍历**（V1 双步进承袭）：沿折线向两端遍历；`direction` ±1 选先侧（单侧跟随语义不变——刷子半径骑脊，方向决定沿轮廓去向）。
- **junction 延续**：度 ≥3 节点处贪心最强延续——候选分支与当前行进方向余弦最大者胜；`followStrength`（改义，OQ-4-A）= 延续判定的最低对齐余弦（缺省 0.5 ≈ 60° 张角限）+ 断隙桥接容忍缩放。
- **自适应步长（输出重采样）**：沿弧长参数化行走，局部转角 θ（相邻段夹角）调制出点距 `s = s_min + (s_max − s_min)·(1 − θ/θ_max)`（s_min≈0.75px、s_max≈4px、θ_max=45°，内部常量 plan 钉死）——直线段省点、弯道加密；`maxPoints` 保留为链 fuse 常量（256 缺省不变）。
- **停止条件**：折线端点 / 断隙 > 桥接容忍 / maxPoints / 出场界。

### 3.4 数据流与缓存（App 侧零腿改动）

```
press seed
  → MaskOverlayHost.followEdgesInteraction（零改动）
  → PipeCoordinator.followEdgesSurface（零改动）
  → edgeMapField 缓存（扩 carrier：field + ridges 同 prefixHash 键、LRU 8——OQ-3-A）
  → FollowEdges.chain(mode:)（穷举零 default 架构不变）
      .streamline → RidgeGraph 上行走（V2 新内部）
      .snap       → 原分支逐字节不动
  → [MaskPoint] → BrushStroke → append/mutate 腿（零改动）
```

- 预提取 lazy：首次 press 后提取并缓存；below 编辑翻 prefixHash 整体失效（M2-7-2 偏差语义逐字一致）。
- 交互手感：press 后行走微秒级；首 press 附加一次提取（毫秒级，§6）。

### 3.5 参数面映射（OQ-4-A）

| 参数 | V1 语义 | V2 语义 | UI |
|---|---|---|---|
| `edgeThreshold` | 行走停门（绝对） | 滞回 high（low = 0.4×high 内部） | 既有滑杆（语义连续平移） |
| `followStrength` | 切向动量混合 | junction 延续最低对齐余弦 + 断隙容忍缩放 | 既有滑杆（改义，hint 至多一行） |
| `direction` | ±1 切向侧 | ±1 链行进侧 | 既有 toggle 不变 |
| `stepPixels` | 固定步长 | **撤出**（自适应步长失义之） | 本就不在 UI |
| `maxPoints` | 链 fuse | 链 fuse 常量保留 | 本就不在 UI |

`FollowEdgesParams` 会话态零持久化（sidecar/Library grep 亲证零命中）——字段变更零迁移。

## 4. Metal 实现路径

- **零新 kernel / 零新 PSO**（OQ-2-A）：`mask_edge_map` 原样；V2 全部工作在 `readEdgeMap`（L014 fence + ≤512 guard）之后的 CPU 域。REQUIREMENTS「Metal 边缘导向实现」的满足面 = Metal edge map（边缘导向数据源）+ Metal 缓存平面（followEdgesSurface）——「CPU 行走段」在 D-M2-7-CONTEXT-4-A 已裁合法（V1 同分界），V2 不移动该界。
- 逃生口（不预期触发）：真图 probe 实测预提取 >50ms @512 场 → GPU NMS kernel（`MaskEdgeKernels.metal` additive 第二 kernel）挂账立项，保留 OQ-2 记录。

## 5. golden 策略与验收形态（对齐 ROADMAP 两枚 ✓）

### 5.1 合成轨（Core 单测，LAYERS bundle）

fixture 矩阵 9 景（真值折线已知）：直脊 / 弧线 / L 角 / T 分叉（junction 走向 + followStrength 判定）/ 断隙脊（1-3px 隙桥接）/ 平行双脊（单侧选择 + direction）/ 低对比段（滞回有效性）/ 纹理背景脊（噪声场 + 隐藏脊——**能杀死 V1 的景**）/ 变宽变强脊。既有理想景 8 法保留回归。断言族：每点垂直真值距离 ≤0.75px、覆盖 ≥80% 真值弧长、纯噪声场零链、双跑逐字节确定、空链降级、`.snap` 分支零 diff（对照基准冻结）。

### 5.2 真图轨（probe 走查，evidence 仓）

复用 `m2-7-3/probe/main.swift` 通道（CIRAW 真解码 + `MaskEdgeKernels.metal` 原文 swiftc 直编 + FollowEdges 源注入 + shim 脚手架）——**V1 同款 8 景盒 × 多 seed**，功能链定义 = 链 ≥12 点且弧长 ≥24px（场域）且端点贴脊（局部 NMS 峰 ≤2px）；门 = **≥6/8 景功能链**（V1 基线 0/8）。证据落 `lightamer-evidence` 仓同相对路径（主仓 `.gitignore` 已排 `phases/*/evidence/`——注意 probe 产物勿入主仓 commit）。

### 5.3 snap 对照轨（ROADMAP 第二枚 ✓）

同 seed 下：V2 链首点落于 `snapTarget`（12px 臂）结果 2px 邻域（共享贴边几何）；V2 全链贴脊 ≤ 笔刷半径；`.snap` 输出与 V1 时代逐字节一致（回归钉）。

### 5.4 性能预算

| 项 | 预算 | 依据 |
|---|---|---|
| 预提取（首次 press，缓存 miss） | ≤ 50ms @512 场 | V1 判据① 200ms 总门占比 25%；O(N) 毫秒级实测预期 5-15ms |
| 行走（每 press，缓存 hit） | ≤ 5ms | 微秒级预期 + 余量 |
| edge map（既有） | 6.3ms 冷 / ~0 热不动 | probe 实测基线 |
| 判据③ FULL 路径 | 不启用 | 现状不变（seam 恒 preview 桶） |

探针惯例：`LIGHTAMER_PERF_PROBE=1` + XCTSkipUnless 门（M2-5 惯例）；读钟前 queue fence（L014）。

## 6. 风险与开放点

1. **NMS 在 ≤512 降采样场上的脊密度**——细脊可能整条没到场里（机理④）：缓解 = 提取前轻高斯（把抽点残迹聚拢）+ 滞回 low 腿纳入弱响应；真图轨门值（≥6/8）已留 2 景容错；plan 期若真图景证实场分辨率不足，升级口 = `readEdgeMap` maxLongEdge 512→1024（预算 ×4 仍内，读回成本 +6ms 级）——**这是一个 plan 期实测裁决点，不预设**。
2. **junction 密集场景（树叶/铁丝网）**——贪心延续可能在分叉处选错支：`followStrength` 用户可调；错支仍贴脊（蒙版语义上是「另一条边」，非失效）——走查观察项，不设门。
3. **质心在双脊并行 ≤3px 时的吸附漂移**——两脊剖面合并质心居中：合成轨「平行双脊」景专门钉该行为（期望 = 吸附较强侧，δ clamp 限幅）；plan 期 golden 定格。
4. **`followStrength` 改义的 UI 文案**——缺省 0.5 两义下行为差异：hint 键至多一行，zh-audit 收口对账。

## 7. Sources

- 实证：evidence 仓 `phases/m2-7-masks/evidence/m2-7-3/probe/probe.log`（V1 判据实录）+ `main.swift`/`shim.swift`（走查通道）
- 源码：`LightamerCore/Sources/Layers/Masks/FollowEdges.swift`、`LightamerCore/Sources/Metal/MaskEdgeKernels.metal`、`App/Sources/Lightamer/State/PipeCoordinator.swift`（:1969 seam + edgeMapField 缓存）、`App/Sources/Lightamer/UI/Overlay/MaskOverlayHost.swift`（followEdgesInteraction）、`App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift`（followEdgesSection）、`Tests/LightamerTests/FollowEdgesTests.swift`
- 账面：`.work/gsd/ROADMAP.md` M4-2 行、`.work/gsd/REQUIREMENTS.md` IOP-MASK-06、`.work/gsd/phases/m2-7-masks/M2-7-CONTEXT.md`（OQ-4 + 勘误-2）、`M2-7-3-ACCEPTANCE-INPUT.md` §二/§三-3、`.work/GOAL-STATE.md` M4 续接点
- 参考仓检索（2026-10-09）：AlcedoStudio `src/`、darktable `src/iop/`、lumen-raw `lumen/`（结论见 §2 表）
- 算法文献域（公开标准知识，未搬运代码）：Canny 边缘检测管线（NMS + 滞回 + 链接）；Steger (2002) curvilinear structure detection（1D Taylor 亚像素位移——仅作 golden 对照参考式）；中心线提取/脊追踪通识

---

# Part 2 — M4-2-03 算法层复审（2026-10-10 追加）

> 触发 = M4-2-02 停止上报的「三选一」用户裁决①（research 复审：算法层迭代）。
> 本部分 = 两瓶颈机理复盘（诊断探针实测）+ 迭代方向调研 + 方案草案。
> 配套裁决文档 = 同目录 `M4-2-03-CONTEXT.md`（OQ-1..6，C 档第 1 停）。

## 8. 两瓶颈机理复盘（诊断探针实测，2026-10-10）

### 8.0 方法与保真校验

M2-7-3 进程内真链探针先例：evidence 仓 `m4-2-02/probe/` 源 verbatim 复用
（`RidgeExtract.swift` 与主仓逐字节同——cmp 已证；`FollowEdges.swift` 仅含
3 行 HB 心跳差异）+ `/tmp/m42diag/main.swift` 诊断脚手架（traced walk 复刻
+ 穿越死因分类 + 出点间隙统计 + 端点-候选距离 + gate 扫频 + 方案模拟），
同 RAW 同协议（DSC00012.ARW → preview 2560×1707 → 1024 工作域）。

**复刻保真校验**：8 景 × 2 阈的 bestN 与 `m4-2-02/probe/probe.log` 逐值一致
（t0.15: 5/0/13/1/9/34/6/1；t0.25: 1/0/9/1/8/12/2/1——全同）→ 以下实测数字
与 probe 实录同源可信。诊断 scratch = `/tmp/m42diag/`（即弃；数字正本 =
本节表格，方法可按本节描述复现；后续执行批应按 M2-7-3 先例将诊断源与 log
入 evidence 仓归档）。

### 8.1 场与图拓扑基线（probe.log 亲值 + 诊断补测）

| 量 | t0.25 | t0.15 |
|---|---|---|
| chains / junctions / bridges | 2724 / 1460 / 39 | 6693 / 3652 / 94 |
| vertices / longestChain | 8288 / 45 | 19574 / 60 |
| ≤2 顶点短链占比 | 1853/2724（68%） | 4897/6693（73%） |
| junction attachments 直方图 | 3:1176 4:281 5:2 6:1 | 3:2869 4:766 5:15 6:2 |

场是**超碎片化脊网**：平均链 2.9 顶点、七成链 ≤2 顶点、junction 占顶点
18.7%。walker 的每一步几乎都踩在 junction 邻域。

### 8.2 死因分类实测（gate 0.5，每景 best 链）

| 景 | t0.15 | t0.25 | 主死因（ traced 实测） |
|---|---|---|---|
| A | n=5（steps=129 cross=54，gapMax 27.8px） | n=1（steps=4080 cross=1483 **fuse**） | ping-pong + deficit 重置饥饿 |
| A2 | 0 候选 | 0 候选 | 区域无脊（≤1024 域不成形，非算法侧） |
| A3 | **YES** 13/39px | n=9（fwd gate-blocked 0.33） | 贴功能线 |
| B | n=1 | n=1 | 链未成形 |
| B2 | n=9（fwd gate-blocked bestCos=0.34） | n=8（gapMax 28.5px） | 门截停 + 饥饿弦线 |
| B3 | **YES** 34/83px（双向 gate-blocked 0.39 截短） | **YES** 12/34px | 已功能；链被门截 |
| C | n=6 | n=2 | 链碎 |
| C2 | n=1（steps=4080 cross=1813 **fuse**） | n=1（同左） | **ping-pong 死循环** |

**三个关键翻转（对 M4-2-02 DECISIONS §3 读解的勘误）**：

1. **端点贴脊门不是瓶颈**。best 链两端到最近 NMS 候选的距离实测 **0-1px**
   （8 景全过 2px 门；遍历端点顶点同测 0-1px）。M4-2-02「A 景长行走 89px
   但端点贴脊门不过（链端落在非候选区）」读解有误——A 景实际卡的是
   **n≥12 腿**（bestN=5）；`&&` 短路使 n 腿失败时贴脊门根本未被评估。
2. **arc≥24 腿被弦线代偿（假阳性通过）**。出点间隙实测最大 27.8px
   （A@0.15）与 28.5px（B2@0.25），远超 `resampleMaxStep=4px` 设计上限
   ——输出折线不贴脊，弧长数字是弦线长度。
3. **真瓶颈 = n≥12 出点数腿**，由三个行走器机理造成（非提取侧、非阈值侧）。

### 8.3 行走器三机理（逐条代码对应 + 实测）

1. **ping-pong 死循环（无 visited 守卫）**——`walk` 无任何已访记录，
   junction 簇内 hop 链反复横穿（每 hop 计一步、不耗 budget）；C2 景实测
   4080 步 / 1813 次穿越 / 出点 ≈1，被 `stepGuard=2048` 砍杀。probe.log
   HB 心跳行（step=1536/2048/2686，idx 恒 0-2、deficit 恒 4.0）同证。
   附带发现：fwd/bwd 两方向**无共享已访态**，A@0.15 实测两方向出点
   **逐点相同**（attach 在 2 顶点链上时双向收敛同一路径重复出点）。
2. **deficit 穿越重置饥饿（判据设计错）**——`walk` 在每次穿越把
   `deficit` 重置 4.0px（`spacing = resampleStep(0); deficit = spacing;
   continue`），而穿越后段长 ~1.4px（8 连通单步）：积累永远到不出点条件
   → 长跳链序列零出点；随后一次出点与前出点之间即直线弦（27.8px 实测
   = (784.9,221.2)→(805.9,203.0)，沿脊路径 ~28px 全程未出点）。出点数
   与骑行弧长脱钩，n≥12 腿系统性失败。
3. **junction 门截停（次要但真实）**——RIDE@0.25（45 链中点骑行，28 出点
   = attach 1 + fwd 21 + bwd 6，与 probe DIAG-2 逐值吻合）双向死于
   gate-blocked：唯一可用分支 bestCos=0.37（coss=[0.37,−0.71]）< gate
   0.5。**gate 扫频**：0.5→0.3→0.0，45 链骑行 28→30（+2，fwd 多跨一次
   junction 后达 free-end），60 链完全不变——**门不是主导死因**
   （free-end 与 fuse 主导）。真实交叉点分支离开角实测集中在 60-90°
   （cos 0.34-0.58），45° 量化假说不成立（亚像素质心后切向非量化值）。

**骑行 0.62 的机理定性**：不是「junction 门掉链」单一叙事——是**无防绕 +
重置饥饿 + 无回退的单遍贪心遍历**在超碎片脊网上的综合输出塌缩；其中
free-end 死亡（骑行长度硬上限 = 局部脊网的物理端点）占比最高。

### 8.4 判别结论（任务第 1 问的正式回答）

| 瓶颈 | 判别 | 依据 |
|---|---|---|
| junction 门掉链 | **算法结构缺环节为主**（无防绕/无回退/无前瞻）+ **判据设计错为辅**（deficit 重置语义）；**参数可救 = 否**（gate 扫频 +2 点封顶） | §8.3 实测 1-3 |
| 端点贴脊 fail | **判据设计错**——门定义是 V1 步距时代的隐含假设：1.5px 固定步 × 24px ≈ 16 点与 n≥12 自洽；V2 自适应步长 0.75-4px 下 24px 直脊最多 ~7 出点，**两腿数学不相容**；且端点测的是重采样相位产物（出点）而非遍历端点 | §8.2 翻转 1+2、n/arc 换算 |

## 9. 迭代方向调研（任务第 2 问）

### 9.1 junction 处理已知工艺（公开文献域通识，未搬运代码）

| 工艺 | 做法 | 对本问题的适配 | 成本 |
|---|---|---|---|
| 交叉点直行保持（angle continuation） | 出分支按与入方向夹角最小者延续 | 已是现状（greedy cosine）——实测不够：真交叉分支离开角 60-90°，直行延续常不存在于同一 junction 的 attachment 集 | 已在产线 |
| 分支前瞻评分（look-ahead scoring） | 候选分支按其 first-k 顶点拟合方向评分（非单跳切向——≤2 顶点链的单步切向噪声主导） | 直接治 gate-blocked 残余（0.34-0.39 档）与 blob 内错选 | 低 |
| junction 簇合并（crossing-point graph） | ≤2-3px 内的 junction 像素并一簇节点，簇内 hop 链折叠，出簇分支统一评分 | 治 blob 多节点跳链噪声（t0.15 场 3652 junction / 大量 1-2 顶点簇间链） | 中（提取侧后处理，golden 重冻结） |
| 全局路径评分 / 带回溯图匹配 | DP 或贪心 + backtrack 选全局最优路径 | 语义过度（笔刷要的是单侧跟随，不是全局最优曲线）；确定性 golden 难写 | 高，弃 |

### 9.2 端点判据替代

- **逐点贴脊率**（all-points hug：≥90% 出点 2px 内有候选）——端点门的
  严格化替身；弦线检测器（gap>4.5px 与贴脊率失败强相关——弦中点必离脊）。
  修复饥饿后逐点贴脊自然成立，门从「相位脆弱」变「质量实质」。
- **n 腿改弧长当量或降门**——n≥12 在 4px 步距下等价于 arc≥44px，与
  arc≥24 腿失配（§8.4）；替代 = n≥8（可用性地板：≈24-32px 直脊当量）
  或 n ≥ arc/4（平凡真，弃）。
- **回看窗口**（walk 停止后回溯 k 点把端点吸附到最近候选）——治标：
  端点本就在候选 0-1px 内（§8.2），不需要。

### 9.3 提取侧连通性（P1 后残余败景的真实瓶颈）

P1 模拟后仍败的 4 景（A2/B/C/C2，见 §10 方案 A 实测）死因全是
**free-end + 短链**：局部脊网物理端点太近（B/C/C2 best 链弧长 2-10px）。
杠杆：①方向感知桥接（`bridgeMaxGap` 3→5-6px + 更强对齐门 + 前瞻连续性
评分——t0.15 场 bridges 仅 94 个，3px 帽把碎片缝全放走）②滞回 low 腿
下调（0.4→0.3：弱段纳入）③分辨率 2048（EXTRACT @1024 已 39.3ms 贴
50ms 门，须 GPU NMS 立项，OQ-2-B 挂账延续）。A2（0 候选）三者皆不可救
——门 6/8 的 2 景容错本就是为此类预留。

## 10. 迭代方案草案（任务第 3 问）

### 方案 A（推荐）：行走纪律修复——`FollowEdges.swift` walker 内部

**改动清单**（全部在 `walk`/`continuationFrom`，零提取侧、零参数面、
零 Metal）：

1. **防绕守卫**：每方向 walk 携 `Set<ChainEndKey>` 已访穿越边；(chain,end)
   至多穿越一次；greedy 最优候选若已访则顺次试 next-best（≥gate），全耗尽
   → 死亡（死亡原因可诊断）。治 ping-pong（C2 4080 步→模拟 26 步）。
2. **deficit 跨穿越携带**：取消穿越重置；`deficit/spacing` 沿骑行弧长连续
   积累。**穿越跳跃距离必须计入**（lastPos→落点段距离减入 deficit——模拟
   未计此项致残余弦线 gapMax 39.7px，产线版必须计，否则弦线仍在）。
   治饥饿 + 弦线，出点数回归「∝ 骑行弧长」。
3. **（可选，建议同批）**attach 落在 ≤2 顶点链时 fwd/bwd 共享已访态——
   治双向同径重复出点（§8.3-1 附带发现）。
4. **gate 缺省 0.5 维持不动**（扫频证据：下调只买 +2 点）。

**预期门影响（模拟实测，非猜测）**：t0.25 1/8→**3/8**、t0.15 2/8→**4/8**
（A 景 5→27 点/115px 翻功能；A3@0.25 9→15/46 翻；B2 双阈翻；B3 保持）。
C2 死循环 → 26 步正常返回。延迟面：最坏行走步数 4080→两位数。

**风险**：①合成 golden 的出点数/间距类断言按新语义重推导（几何断言零删；
`RidgeExtractTests` 21 法零触——提取函数不动）②防绕的「次优回退」在分叉
语义上仍可能选错支（蒙版语义 = 另一条边，非失效——RESEARCH §6.2 既有定性
沿用）③模拟与产线差异：模拟未计跳跃距离（残余弦线），产线修复后输出质量
优于模拟数字。

**测试增量估算**：`FollowEdgesTests` +4-6 法（防绕死守卫 / deficit 携带 /
无弦线门 gap≤4.5px / hairball fixture）+ probe 同协议复跑双跑（evidence 仓
新 `m4-2-03/probe/`）。约 1 个执行 plan（Core 单批 + probe 对账），不含 App
腿（零接线变化）。

### 方案 B：junction 簇合并 + 前瞻评分——`RidgeExtract.link` 后处理

簇合并（≤2-3px 邻域 junction 并节点、簇内 hop 链折叠）+ 出簇分支按
first-3-vertex 方向评分。治 §8.3-3 的门截停残余与 blob 错选。
**风险**：冻结拓扑 golden 全变（chains/junctions/vertices/longest 冻结值
重冻结——M4-2-01/02 两批负测的冻结数字全数失效重推）；提取成本 +O(J)。
**实测预期**：对 P1 后残余 4 败景帮助有限（其死因是 free-end/短链，非
junction 噪声）——gate 影响预期 +0~1 景。

### 方案 C：提取连通性补强——方向感知桥接 + 滞回 low 下调

`bridgeMaxGap` 3→5-6px（配更强对齐门 + 前瞻连续性评分）与/或
`hysteresisRatio` 0.4→0.3。治 B/C/C2 碎片段（P1 后残余败景的真实瓶颈）。
**风险**：纹理假桥（对齐门与前瞻评分约束）；冻结拓扑 golden 重冻结
（同 B）；假桥会造跨纹理弦线——必须配逐点贴脊率门（OQ-2）兜底。
**实测预期**：C/C2 景弧长 9/10px → 24px+ 的连通性翻functional 的
把握中等（桥接是否恰好缝上该景的断隙须 probe 实证）；B 景链未成形
（低阈下候选都稀）希望较小。

### 推荐与组合

**A 先行单执行批 → probe 复跑对账（预期 ~4/8）→ 若停 4/8 再裁 C（B 的
增益被 A 的 next-best 回退大部吸收，可不批）**。诚实测算：A = 4/8（实测
模拟）；A+C 才有触及 6/8 的路径且无把握（C 景翻否须实证）；A2 恒不可救
= 门容错对象。**若用户要 6/8 确定性，须连 GPU NMS/2048 分辨率杠杆一起
立项（OQ-6）——那是另一个量级的批**。备选：接受降级（P1 后 4/8 + 门
修订，以「观察中能力」挂账）——属 OQ-1 的 C 选项。

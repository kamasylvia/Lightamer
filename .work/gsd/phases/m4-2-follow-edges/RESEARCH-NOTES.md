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

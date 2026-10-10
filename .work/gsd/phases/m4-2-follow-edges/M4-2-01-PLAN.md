---
phase: m4-2
plan: "M4-2-01"
title: "Follow Edges V2 换锚全量批（OQ-1..7 全 A 生效值落地）——RidgeExtract Core 纯函数面（轻高斯 σ0.9 → 中心差分梯度 → NMS 4 象限插值 → 滞回 high=edgeThreshold/low=0.4·high → 行主序 8 连通链接 + ≤3px 断隙桥接 + junction 记录 → 亚像素质心 ±2 剖面）+ RidgeGraph 类型 + .streamline 臂换锚（图上行走：seed 8px 附着 / 双向遍历 / junction 贪心最强延续 followStrength=最低对齐余弦 / 自适应重采样 0.75..4px 曲率调制 / maxPoints fuse）+ V1 walker 实现体同批删除（先金后删，单提交）+ stepPixels 撤出 + EdgeMapField additive ridges 传输缝 + App ridge carrier（平行 dict + prefixHash⊕thresholdBits 折键 LRU 8；field 缓存零阈折）+ 合成 9 景 golden 矩阵 + .snap 冻结基准 + 双跑确定性门 + 真图 8 景盒 probe 门 ≥6/8 + 性能探针（提取 ≤50ms / 行走 ≤5ms）+ 默认回翻 .streamline（门后执行）"
wave: 1
depends_on: []
autonomous: true
requirements: ["IOP-MASK-06"]
estimated_tests: "+21..29"
test_bundles: [Layers, App]
files_modified:
  - LightamerCore/Sources/Layers/Masks/RidgeExtract.swift        # 新建：NMS/滞回/链接/桥接/质心纯函数 + RidgeGraph/RidgeChain 类型 + 轻高斯（全 O(N)，零 Metal 依赖）
  - LightamerCore/Sources/Layers/Masks/FollowEdges.swift         # 修改：.streamline 臂换锚为 RidgeGraph 消费者；V1 walker 实现体删除（lookahead/动量混合/环梯度回退）；FollowEdgesParams.stepPixels/maxPoints 双撤出（OQ-4-A 字母面；maxPoints 转链 fuse 内部常量 256——checker 回注 M1）+ followStrength 改义 doc（行走期 junction 延续偏置，提取面零消费——checker 回注 E1 处方甲）；EdgeMapField additive ridges: RidgeGraph?（缺省 nil 零漂移）；.snap/snapTarget/readEdgeMap/edgeMap 零 diff
  - App/Sources/Lightamer/State/PipeCoordinator.swift            # 修改：FollowEdgesRidgeCache（平行 dict，prefixHash ⊕ edgeThreshold bitPattern 折键，LRU 8）+ edgeMapField(for:) 注入 ridges——GPU edge map 缓存键零阈折（拖阈不重跑 GPU pass）
  - App/Sources/Lightamer/State/LayerEditingState.swift          # 修改：followEdgesParams 缺省回翻 .streamline（:193，d10f681 逆向；T6，T5 门后）
  - App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift       # 修改：至多 hint 一行（followStrength 改义说明）；mode/threshold/strength/direction 四件结构零新增
  - Resources/Localizable.xcstrings                              # 修改：0-1 键（mask_follow_strength_hint，尾块纯插入；0 键 = 文案不需要）
  - Tests/LightamerTests/RidgeExtractTests.swift                 # 新建（LAYERS/Core 级）：阶段 golden（NMS/滞回/链接/桥接/质心/确定性）+ 9 景矩阵 + Steger 1D Taylor 对照腿（Taylor 只住测试文件）
  - Tests/LightamerTests/FollowEdgesTests.swift                  # 修改：既有 8 法保留回归（几何断言不动，点数门按 V2 自适应重采样实测重校）+ V2 行走法（junction/followStrength 判定 + .snap 冻结常量 + 双跑确定性）
  - Tests/LightamerTests/FollowEdgesRidgeCacheTests.swift        # 新建（APP/App 级）：carrier LRU/折键/注入 3-4 法
  - Project.swift                                                # 修改：新测试文件登记对应 target 数组（显式清单无 glob）+ tuist generate 恒为该批最后动作（L041）
  - AGENTS.md                                                    # 修改：M2-7 架构增量节 Follow Edges 段 V2 收口注记（熔断 → 已换锚 + 默认回翻 + 内部常量登记，T7）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt   # 修改：RidgeExtractTests / FollowEdgesRidgeCacheTests 增行（E2 纪律，随各自任务 commit）
  - .work/gsd/phases/m4-2-follow-edges/M4-2-01-SUMMARY.md        # 新建（T7）
  - .work/gsd/phases/m4-2-follow-edges/M4-2-01-DECISIONS.md      # 新建（T2 动工前先落 checker E1/M1/M2/M3 消解钉死行——放行条件前置；T7 收口补全）
  - .work/gsd/phases/m4-2-follow-edges/M4-2-01-ACCEPTANCE.md     # 新建（m1 双重验收记录——zcode PASS 后串行 omp 二次验收）
  - .work/gsd/phases/m4-2-follow-edges/M4-2-01-ACCEPTANCE-OMP.md # 新建（T7，omp 二次验收结论面）
  - .work/GOAL-STATE.md                                          # 修改：续接点
  - .work/TODO.md                                                # 修改：M4-2 条目
  - .work/LESSONS.md                                             # 如踩坑
---

# Plan M4-2-01 — Follow Edges V2 换锚全量批（三件套 + golden 三轨 + 默认回翻）

> **性质**：M4-2 单主 plan（M4-2-02 = 条件触发的备用升级口批，非本 plan 的依赖续批）。
> 本批交付 V2 全部代码面 + golden 三轨 + 真图验收门 + 默认回翻。`.snap` 分支与
> `FollowEdgesMode` 双 case 架构**逐字节不动**（对照基准 + 降级底座双重身份）；
> `mask_edge_map` kernel **零 diff**；V2 全部工作在 `readEdgeMap`（L014 fence +
> ≤512 guard）之后的 CPU 域。规格正本 = `RESEARCH-NOTES.md`（机理复盘/三件套
> 细则/golden 策略/性能预算）；裁决正本 = `M4-2-CONTEXT.md` 文末裁决记录
> （OQ-1..7 全按推荐，2026-10-10 用户回批）。
>
> **基线**：**3335/16/0**（M4-1-VALIDATION 2026-10-10 终验 `TOTAL|3335/16/0|1604s`
> 亲跑 + zcode 验收路 1584s 逐位；bundle 分账 IOP 562/1/0 / IOPParity 427/3/0 /
> **Layers 394/3/0** / Library 619/4/0 / Sessions 279/4/0 / Export 350/1/0 /
> **App 704/0/0**——本批增量面 = Layers + App 两 bundle，planner 已亲核）。
>
> **账面勘误（planner 亲核，执行与验收按本条为准）**：CONTEXT/裁决记录引「`60582c3`
> 熔断一行」——仓内实况 = **`d10f681`**（`chore(m2-7): follow edges default to
> snap mode`，`git log -S "FollowEdgesParams(mode: .snap)"` 亲证；`60582c3` 非本仓
> 可达 revision）。T6 回翻的逆向对象 = `d10f681`；DECISIONS 登记勘误，CONTEXT
> 原文不改（Ruling 注记先例）。

## 已定裁决（生效值，硬约束，不得重开）

M4-2 OQ-1..7 **全部按推荐裁**（CONTEXT 裁决记录 2026-10-10，用户回批全 A）。七项全部由本 plan 承载：

1. **OQ-1 = A（Canny 式三段）**：脊线预提取 = 轻高斯 → NMS（沿梯度 4 象限插值）→ 滞回（high = 既有 `edgeThreshold`，low = r×high，r=0.4 内部常量）→ 8 连通行主序确定性追踪 + ≤3px 断隙桥接，junction 记入 `RidgeGraph`。**Steger 仅 golden 对照**：1D Taylor 位移式只落测试文件（`RidgeExtractTests.swift`）作质心质量 A/B 参考腿，Core 零 Steger 代码（grep 机检）。
2. **OQ-2 = A（全 CPU 读回后段）**：零新 kernel / 零新 PSO；`MaskEdgeKernels.metal` 零 diff；`readEdgeMap` 签名与 ≤512 guard 零改。性能探针钉预提取 ≤50ms @512 场（超门 = 观察项逃生口挂账上报，**不在本 plan 内自行 GPU 化**）。
3. **OQ-3 = A（随场同键 carrier）**：ridge 缓存 = coordinator 平行 dict（M2-7-2 偏差先例形态），键 = prefixHash ⊕ edgeThreshold bitPattern，LRU 8；**field 缓存键零阈折**（GPU edge map 不因拖阈重跑——field 与 ridge 两级分层，KD-4）；App 不可持久化面不变（零 UserDefaults 新键）。
4. **OQ-4 = A（面不变改义）**：UI 面零新增（四件原样，至多 hint 一行）；`edgeThreshold` → 滞回 high（语义连续平移）；`followStrength` → junction 延续偏置（0..1 = 延续判定的最低对齐余弦，缺省 0.5 ≈ 60° 张角限；断隙桥接同门）；`stepPixels` 撤出（全仓消费面 = `FollowEdges.swift` 定义 + `FollowEdgesTests.swift:91` 一处调用，planner grep 亲证）；`maxPoints` 保留链 fuse 常量（256 不变）。`FollowEdgesParams` 会话态零持久化——字段变更零迁移。

   > checker 回注（2026-10-09）：裁决原文不改；落地按 DECISIONS 偏差注记收窄两点。①「断隙桥接同门」收窄为**提取期内部常量 0.5**（与 followStrength 缺省同值），followStrength 语义收窄为**行走期 junction 延续偏置**（KD-2③）——否则 followStrength 进入提取面，与 OQ-3 键折叠（无 strength 项）及 KD-2① 纯函数声明三方互斥（checker E1 实录，处方甲消解，OQ-3/OQ-4 裁决本体零重开）。②「maxPoints 保留链 fuse 常量」按裁决字母面执行 = **params 字段撤出 + 内部常量 256**（与 stepPixels 同批双撤出；全仓无任何 maxPoints 设值点，两读行为等价，收口 grep = FollowEdges.swift 单文件——checker M1）。
5. **OQ-5 = A（验收门后回翻）**：UI 默认回翻 `.streamline`（`d10f681` 逆向，`LayerEditingState.swift:193`）；**翻回以 T5 真图门 PASS 为前置**，T5 FAIL 本任务不执行（转 M4-2-02 触发判定或上报）。
6. **OQ-6 = A（golden 三轨）**：合成 9 景矩阵（断言族见 KD-3）+ 真图 8 景盒功能链门 **≥6/8**（V1 实测 0/8 基线上翻）+ snap 对照轨。三轨缺一不收；门值 plan 期按实测校准（M3-3-E5 先例），方向不裁。
7. **OQ-7 = A（V1 实现体同批删除）**：lookahead 侧翼采样 / 动量混合 λ / 环梯度回退（`initialHeading`/`strongestRingGradient`/walk 机制）golden 落地同一提交序内删除（**金与删同批单提交，禁「先删后金」中间红态**）；`FollowEdgesMode` 双 case 架构与 `.snap` 分支原样——「分支保留、实现换锚」。

**架构红线（本 plan 全程 + checker 机检面）**：
- `MaskEdgeKernels.metal` **零 diff**；零新 PSO / 零 function constant（`makeEncoder(functionName:)` 全仓清单零增量）。
- `FollowEdges.snap` / `snapTarget` / `readEdgeMap` / `edgeMap` 函数体**零 diff**（T2 的 diff 只落在 `.streamline` 臂与 params/字段面）。
- `MaskOverlayHost.swift` 交互腿**零 diff**（链生成器内部换锚，腿无感——`FollowEdgesInteraction.chain` 签名零改，`fieldReader` 返回类型不变）。
- `MaskRevisionTests` 既有两法（`:507/:559`——真产线腿注入，fieldReader 无 ridges）必须原样保持绿：V2 在 `field.ridges == nil` 时**链内 lazy 提取**（纯函数语义不变），该负测同时是 lazy 路径的回归钉。
- 蒙版 stamping/combine/revision 红线不触碰；sidecar/Library 零触碰；`PipeCache.swift` 非 plan 边界（M2-7-2 偏差先例沿袭）。
- L014：一切 GPU 读回计时/读值前 queue fence；L041：`tuist generate` 恒为登记批最后动作。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 RidgeExtract 纯函数面（T1，RESEARCH §3.1 逐段落地）

- **新文件** `LightamerCore/Sources/Layers/Masks/RidgeExtract.swift`（纯 Swift，零 Metal 依赖，输入 = `EdgeMapField`）。流水线与**钉死常量**：
  1. **轻高斯** σ=0.9（可分离核 7-tap，半径 ceil(3σ)=3，边界 clamp，先行后列固定序）——稳定质心与曲率估计，补机理④。
  2. **梯度**：中心差分（平滑场上）。
  3. **NMS**：沿梯度方向 ±1 亚像素比较值（4 象限量化 + 线性插值）；保留判据 = `v > n1 && v >= n2`（**非对称 tie-break**，确定性）；过阈（low）者入候选图。
  4. **滞回**：high = `edgeThreshold`（用户参数），low = 0.4×high（r=0.4 内部常量）；强点（≥high）**行主序**作种 → 8 连通生长收集 ≥low 连通域。
  5. **链接**：连通域 → 折线集（端点 = 域内 8 邻度 <2 的点；行主序先端点后环）；度 ≥3 点记 junction；断隙 ≤3px（B=3 内部常量）按「端点距 + 方向对齐（余弦 ≥ 0.5 桥接对齐门——**提取期内部常量**，不消费任何用户参数）」最近端桥接，tie-break = 距²序 → 行主序。

     > checker 回注（2026-10-09）E1 处方甲：原文「余弦 ≥ followStrength 门」使 followStrength 进入提取面，与 KD-4 缓存键（prefixHash⊕threshold，无 strength 项）及 KD-2①「同 field 同 params 同输出」三方互斥（CHECKER §一实录：拖 strength → prefixHash 与阈值均不变 → 命中旧 ridge 缓存 → 桥接按旧门服务，且既有折键测试抓不到）。桥接对齐门改钉内部常量 0.5（与 followStrength 缺省同值属对齐选择），提取恢复 `(field, edgeThreshold)` 真纯函数——KD-4 键原样、KD-2① 声明恢复为真、OQ-3 字面原样；OQ-4「断隙桥接同门」以 DECISIONS 偏差注记收窄（裁决本体零重开）。
  6. **亚像素质心**：每候选点 p、单位法向 n = g/|g|：`f_k = bilinear(smoothed, p + k·n), k ∈ {-2..2}`；`w_k = max(f_k − low, 0)`；`δ = Σ k·w_k / Σ w_k`（Σw < ε → δ=0；|δ| ≤ 1.5 clamp）；细化点 p* = p + δ·n。
- **类型面**：`RidgeGraph`（`chains: [RidgeChain]` + junction 连接关系）+ `RidgeChain`（亚像素顶点折线，场域 px 坐标 `SIMD2<Double>`）——`Sendable` 值类型，坐标系 = EdgeMapField 自身像素网格（与 `EdgeMapField` 同域，无归一化转换）。
- **确定性纪律**：行主序扫描 / argmax 首中即胜 / 显式 tie-break / 无 RNG 无时间输入——双跑逐字节 golden 钉死（承袭 V1 CPU walker 惯例）。
- **复杂度**：全阶段 O(N)；512×341 ≈ 175k px 串行预期 5-15ms（探针实测入 DECISIONS）。

### KD-2 V2 walker（.streamline 臂换锚，T2）

- **传输缝**：`EdgeMapField` additive `public var ridges: RidgeGraph?`（init 缺省 nil——既有构造点逐字节零漂移，负测钉死）。**nil → `.streamline` 臂内 lazy 提取**（提取纯函数语义：**同 field 同 edgeThreshold 同输出**——提取不消费 followStrength，checker 回注 E1 处方甲；coordinator 注入 ridges 时零重提取）。该缝是「交互腿零改动」的关键：`FollowEdgesInteraction.chain` 的 `fieldReader` 返回类型不变，ridges 随 field 值走。
- **行走机制**：
  1. **seed 附着**：seed（归一化）→ 场域 px → 半径 8px 内最近 `RidgeChain` 顶点（`snapTarget` 同族几何；tie-break = 距²序 → 行主序）；无命中 = **空链降级（语义与 V1 逐字一致）**——先按 V1 同款 8px `snapTarget` 找最强邻（阈值门）再附图（**再附图搜索半径 = 同 8px**，从最强邻落点起算，`snapTarget` 同族几何；tie-break 同距²序 → 行主序），双路径都空才空链。

     > checker 回注（2026-10-09）M2：回退臂「再附图」的搜索半径原文未钉（回退臂命中点可距 seed 达 8px，其 8px 邻域与 seed 8px 邻域是不同集合）——钉死为同 8px、`snapTarget` 同族几何、tie-break 同距²序 → 行主序；T2 DECISIONS 落对应一行。
  2. **双向遍历**（V1 双步进承袭）：沿折线向两端 + junction 处跨链延续；`direction` ±1 决定输出链方向序（+1 = 行进前向侧先出）与 junction tie 的符号侧。
  3. **junction 延续**：度 ≥3 节点贪心最强延续——候选分支切向与当前行进方向**余弦 ≥ followStrength**（缺省 0.5）者中余弦最大者胜；**余弦平手 = 候选分支按其首顶点行主序枚举、argmax 首中即胜**（KD-1 确定性纪律）；无一过门 = 停。followStrength 只治行走期 junction 延续（断隙桥接门 = 提取期内部常量 0.5，KD-1⑤——checker 回注 E1 处方甲）。

     > checker 回注（2026-10-09）M3：junction 余弦平手的决胜序原文未显式——钉死为「候选分支按其首顶点行主序枚举 + argmax 首中即胜」；T 分叉景 followStrength {0.2, 0.8} 两档远离平手域，golden 不受影响；T2 DECISIONS 落对应一行。
  4. **自适应重采样**：沿弧长参数化出点，`s = s_min + (s_max − s_min)·(1 − min(θ,θ_max)/θ_max)`，s_min=0.75 / s_max=4.0 / θ_max=45°（内部常量）——直线省点、弯道加密；junction 跨链处弧长累计清零。
  5. **停止条件**：折线端点 / 断隙 > 3px / maxPoints（256）/ 场界。
- **V1 删除清单（同批，grep 机检）**：`initialHeading` / `strongestRingGradient` / walk 闭包的 lookahead 侧翼采样与动量混合 λ——删除后全仓 grep 标识符零命中。`FollowEdgesParams.stepPixels` 与 `maxPoints` 字段及各自 init 缺省同批撤出（**双撤出**，OQ-4-A 字母面——maxPoints 转链 fuse 内部常量 256；收口 grep `maxPoints` = FollowEdges.swift 单文件命中、params 字段零命中，checker 回注 M1）；`FollowEdgesTests.swift:91` 调用点同批更新。
- **`followStrength` 改义 doc**：字段注释按 KD-2③ 几何定义重写（V1 动量混合措辞退役；语义收窄为**行走期 junction 延续偏置**——断隙桥接门为提取期内部常量，不随本参数变，checker 回注 E1 处方甲）；黄金钉 = T 分叉景 × followStrength {0.2, 0.8} 两档行为差（T3，落点 = 行走期 junction 走向）。

### KD-3 golden 三轨（T2/T3/T5，OQ-6 生效值）

- **合成 9 景矩阵**（`RidgeExtractTests`，LAYERS；fixture 构造器沿 `FollowEdgesTests` 基座扩展）：
  直脊 / 弧线 / L 角 / T 分叉（junction 走向 + followStrength 判定）/ 断隙脊（1-3px 隙桥接）/ 平行双脊（单侧选择 + direction）/ 低对比段（滞回有效性：low..high 段续链、<low 断）/ 纹理背景脊（确定性噪声场 + 隐藏脊——**能杀死 V1 的景**）/ 变宽变强脊（幅值 0.3..1.0 沿脊变化）。
  **断言族**：每点垂直真值折线距离 ≤0.75px + 覆盖 ≥80% 真值弧长（junction 景真值 = followStrength 对应的期望**行走**分支——两档行为差落点 = junction 走向，桥接门为提取期内部常量、两档提取图逐字节同，checker 回注 E1 处方甲）+ 纯噪声场零链 + 双跑逐字节确定 + 空链降级保留（nil / 全零场）+ **`.snap` 冻结基准**（三景 snap 输出常量硬编码断言——snap 函数体零 diff 的行为钉）。
- **既有 8 法保留回归，点数门重校**：几何断言（贴边带 / 边界到达 / 转角访问 / 噪声空链）**一字不动**；点数断言（scene-1 ≥30 / corner ≥20）按 V2 自适应重采样**实测重校**（直脊 s_max=4px 下点密度约 1/4——重校值带实测入 DECISIONS，禁拍脑袋）；`testEdgeMapKernelSmokePass` / snap 两法零改应绿。
- **Steger 对照腿**（测试文件内）：直脊 + 弧线景上 Taylor 位移式 vs 产线质心的偏差带实测入 DECISIONS（仅质心质量证据，不进产线、不设门——OQ-1）。
- **真图轨**（T5，probe 走查）：复用 evidence 仓 `m2-7-3/probe/` 通道（CIRAW 真解码 + `MaskEdgeKernels.metal` 原文 swiftc 直编 + shim 脚手架），**probe 源清单 += `RidgeExtract.swift`**；M2-7-3 同款 8 景盒 × 多 seed。功能链定义 = 链 ≥12 点 ∧ 弧长 ≥24px（场域）∧ 端点贴脊 ≤2px（局部 NMS 峰判）；**门 = ≥6/8**。probe 逐景落诊断行（FIELD stats / NMS 候选数 / 滞回强弱点数 / 链指标）——同时是 M4-2-02 触发判别的数据面（KD-5）。
- **确定性门**：合成全矩阵双跑逐字节 + probe 双跑同链（真图域）。snap 对照轨 = 同 seed 下 V2 链首点落于 `snapTarget`（12px 臂）结果 2px 邻域 + 全链贴脊 ≤ 笔刷半径（合成景断言）。

### KD-4 App ridge carrier（T4，OQ-3 生效值）

- **新小类型** `FollowEdgesRidgeCache`（App/Sources/Lightamer/State/ 内，PipeCoordinator 持有）：平行 dict + LRU 8 + 键 = `prefixHash ^ edgeThreshold.bitPattern` 折叠（UInt64 域，L013 精神——进程内键非持久化，Hasher 禁用沿用 M2-7-2 先例的显式折叠）。**独立于 field 缓存**：`edgeMapFieldCache`（prefixHash 键）零改——拖阈只重提取（ms 级）不重跑 GPU pass。
- **注入缝**：`edgeMapField(for:)` 返回前查 ridge cache（miss = `RidgeExtract.graph(from:field:high:)` 提取并缓存——签名无 followStrengthBridgeGate 形参，checker 回注 E1 处方甲），以 `field.withRidges(...)` 值拷贝返回——**产线腿（真 kernel + 真读回 + 注入）与 stub 腿（无注入 → 链内 lazy）双路径都被既有测试覆盖**。
- 失效语义：below 编辑翻 prefixHash → ridge 键随之 miss（与 M2-7-2 偏差记录逐字一致）；LRU 8 上限同族逐出。
- App 单测（`FollowEdgesRidgeCacheTests`，APP bundle）：LRU 逐出序 / 折键区分阈值（同 prefixHash 异阈值 = 两键）/ **异 followStrength 一致性**（同 prefixHash 同阈值下改 strength：键不变 + ridges 逐字节一致——键不含 strength 的正测校准；折入既有 3-4 法配额，估算区间不变）/ 注入后 field.ridges 非 nil / 重复取用零重提取（提取计数器注入）。

  > checker 回注（2026-10-09）E1 处方甲（KD-4 面）：缓存键维持 `prefixHash ⊕ edgeThreshold.bitPattern` **原样不变**（键不含 strength）；`RidgeExtract.graph` 签名随方案甲删除 `followStrengthBridgeGate` 形参；折键测试校准 = 既有「同 prefixHash 异阈值 = 两键」正负测不变 + 新增「异 strength 同键同 ridges」一致性测——「提取 = `(field, edgeThreshold)` 纯函数」从声明变为机器可检面。

### KD-5 真图 probe 通道（T5）

- 证据落 **lightamer-evidence 仓** `/Volumes/UNITEK/Documents/Development/lightamer-evidence/.work/gsd/phases/m4-2-follow-edges/evidence/m4-2-01/probe/`（main.swift + 源清单 + probe.log 双跑；主仓 `.gitignore` 已排 `phases/*/evidence/`——**probe 产物零入主仓 commit**，机检 = 主仓 `git status` 无 evidence 命中）。
- probe 编译面：FollowEdges.swift + RidgeExtract.swift + MaskEdgeKernels.metal + shim + MaskPointExtract（M2-7-3 先例清单 + 一行增量）。
- 性能实测行（入 probe.log + DECISIONS）：预提取（首次，缓存 miss）≤50ms @512 场；行走（缓存 hit）≤5ms；edge map 冷/热（V1 基线 6.3ms/~0 不动）。探针在 probe 域计时（无 GPU 读回计时涉 L014——edge map 读回后计时）。
- **门 FAIL 处置**：不作本 plan 内自行修复扩展——按诊断行判别（M4-2-02 触发条件三分支：细脊缺响应 → P2；算法失稳 → 上报；其余 → 上报），T6 不执行。

### KD-6 默认回翻与收口（T6/T7，OQ-5 生效值）

- T6 = `LayerEditingState.swift:193` `FollowEdgesParams(mode: .snap)` → `FollowEdgesParams()`（缺省 `.streamline`）+ 注释更新（d10f681 逆向；勘误见 plan 头）+ toolbar hint（0-1 键：`mask_follow_strength_hint`，strength 改义说明一行；若判定文案不需要 = 0 键，DECISIONS 记裁定）。**执行门 = T5 PASS**（plan 任务序即门序）。
- T7 收口 = SUMMARY/DECISIONS/ACCEPTANCE + **AGENTS.md M2-7 架构增量节 Follow Edges 段收口注记**（熔断态 → V2 已换锚 + 默认回翻 + KD-1/KD-2 内部常量登记 {σ0.9, r0.4, B3, 桥接对齐门 0.5〔E1 处方甲〕, s0.75/4.0/θ45°, 附着 8px, 再附图 8px〔M2〕, maxPoints 256〔M1〕}——下 phase 引用单一源）+ GOAL-STATE/TODO 同批 + 全套回归 + 红线自证 + 双重验收。

## read_first

1. `.work/gsd/phases/m4-2-follow-edges/M4-2-CONTEXT.md`（裁决记录 = 七项生效值正本 + Phase Boundary + Reusable Assets 表）+ `RESEARCH-NOTES.md` 全文（机理四条/三件套公式/golden 策略/预算细则）
2. `LightamerCore/Sources/Layers/Masks/FollowEdges.swift` 全文（V1 walker 现状 / snap/snapTarget/readEdgeMap/edgeMap 零 diff 面 / params 字段面）
3. `LightamerCore/Sources/Metal/MaskEdgeKernels.metal`（幅值场语义 + 归一化 ÷4√2——提取输入域）
4. `App/Sources/Lightamer/State/PipeCoordinator.swift` :1941-2040（FollowEdgesSurface seam + edgeMapFieldCache LRU 8 形 + 偏差注记）
5. `App/Sources/Lightamer/UI/Overlay/MaskOverlayHost.swift` :880-907（FollowEdgesInteraction 注入缝——本 plan 零 diff 面）
6. `App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift` :201-260（followEdgesSection 四件 + degraded hint）
7. `Tests/LightamerTests/FollowEdgesTests.swift`（fixture 构造器基座 + 既有 8 法）+ `Tests/LightamerTests/MaskRevisionTests.swift` :495-575（真产线腿两法 = lazy 路径回归钉）
8. `App/Sources/Lightamer/State/LayerEditingState.swift` :186-200（followEdgesParams 缺省——T6 翻回点）
9. evidence 仓 `/Volumes/UNITEK/Documents/Development/lightamer-evidence/.work/gsd/phases/m2-7-masks/evidence/m2-7-3/probe/`（main.swift/shim.swift/probe.log——走查通道正本；8 景盒 seed 坐标复用）
10. `.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt`（LAYERS/APP 归域规则）+ `Scripts/test-direct.sh`（bundle 名：Layers/App）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits 全英文；只 add 相关文件；front-matter `files_modified` 为界）；新测试文件随各自任务 commit 登记进 BUNDLE-MAP（E2）+ `Project.swift` 对应数组（L041：`tuist generate` 恒为该批最后动作）。
- **构建**：`caffeinate -dis` 包裹；单测标准命令 = `Scripts/test-direct.sh --bundle Layers` / `--bundle App`（直启宿主）；**全套 `--all` 轮 = orchestrator 批准 + 运行中保持监视 + MEMFAIL 机检**（仅 T7 收口轮申请一次）。
- **金与删同批**（OQ-7）：T2 单提交内 golden 绿 + V1 实现体消失——工作树任何中间态不得出现「删了 V1 而 golden 未绿」的提交。
- **L014**：GPU 读回相关计时/读值先 fence（probe 与测试同规）；**L048 不涉**（本批无色彩域比较）。
- **中文标注**（待核/待定/待补）一律显式；无源待核项入 DECISIONS 待供件清单。
- **资源监控**（AGENTS）：Layers/App 定向轮常跑；probe 进程为短命 swiftc 直编进程，跑完即退。

## Tasks

### T1 RidgeExtract.swift + 阶段 golden（KD-1）

- read_first 1/2/3/7 → 实现 `RidgeExtract.swift`（六段流水线 + RidgeGraph/RidgeChain 类型 + 钉死常量全数在册）→ `RidgeExtractTests.swift` 阶段法：NMS 图（合成场上 NMS 前后逐点断言 + tie 非对称保留判据）/ 滞回（low..high 弱点凭连通入围、孤立弱点不入）/ 链接（L 角连通域 → 单折线 + junction 度记录）/ 桥接（2px 断隙合链、>3px 不合）/ 质心（合成脊上 δ ≤0.3px + clamp 边界）/ 双跑逐字节。
- 验收：`--bundle Layers` 新法全绿；`Project.swift` + BUNDLE-MAP 登记（L041 尾闸）；Core 内 grep `Steger|Taylor` 零命中（对照腿只在测试文件——OQ-1 机检锚）。

### T2 V2 walker 换锚 + V1 删除 + 既有回归重校（KD-2 + KD-3 合成半边）

- **动工前置（checker 放行条件）**：M4-2-01-DECISIONS 先落四行钉死——E1 处方甲（桥接对齐门 = 提取期内部常量 0.5 + followStrength 收窄行走期 junction 延续 + OQ-4「断隙桥接同门」偏差注记）/ M1（maxPoints 双撤出 = params 字段撤出 + 链 fuse 内部常量 256）/ M2（再附图搜索半径同 8px，`snapTarget` 同族几何）/ M3（junction 平手 = 候选分支按首顶点行主序枚举、首中即胜）。
- read_first 2/5/7/8 → `.streamline` 臂改写为 RidgeGraph 消费者（附着/双向/junction/重采样/停止条件）+ `EdgeMapField.ridges` additive + `stepPixels`/`maxPoints` 双撤出（maxPoints 转链 fuse 内部常量 256——checker 回注 M1）+ V1 实现体删除 + `FollowEdgesTests` 演化（几何断言保留 / 点数门实测重校 / stepPixels 调用点更新 / 新增直脊/弧线/L/断隙/噪声 walker 级 golden + snap 冻结三景常量）。**单提交**（金与删同批）。
- 验收：`--bundle Layers` 全绿（FollowEdgesTests 既有法除点数门重校外逐字不变 + MaskRevisionTests 真产线腿两法零改绿 = lazy 路径回归）；`git diff -- LightamerCore/Sources/Metal/MaskEdgeKernels.metal App/Sources/Lightamer/UI/Overlay/MaskOverlayHost.swift` 零命中；grep `stepPixels|initialHeading|strongestRingGradient` 全仓零命中；grep `maxPoints` 全仓仅 FollowEdges.swift 单文件命中（内部常量 + 消费点；params 字段零命中——checker 回注 M1）；空链降级三态（nil/全零/无附着）断言在册。

### T3 9 景矩阵补全 + 三轨断言闭合（KD-3）

- read_first 1/7 → RidgeExtractTests 补 T 分叉（followStrength {0.2, 0.8} 两档**行走**走向差——桥接门为提取期内部常量、两档提取图逐字节同，checker 回注 E1 处方甲）/ 平行双脊（单侧 + direction 翻转序）/ 低对比段（滞回续链门）/ 纹理背景脊（杀 V1 景：噪声 + 隐藏脊 + 噪声区种子零链）/ 变宽变强脊 + snap 对照轨断言（首点 2px 邻域 + 全链贴脊 ≤ 笔刷半径常量）+ 全矩阵双跑确定性门 + Steger 对照腿实测带。
- 验收：9 景 × 断言族全绿；重校值带 + Steger 偏差带 + followStrength 两档行为差实测入 DECISIONS；纯噪声零链与杀 V1 景正测并列（负测对照）。

### T4 App ridge carrier（KD-4）

- read_first 4/5 → `FollowEdgesRidgeCache` + `edgeMapField(for:)` 注入缝 + `FollowEdgesRidgeCacheTests`（LRU 序/折键/注入/零重提取）。
- 验收：`--bundle App` 全绿；`MaskOverlayHost.swift` 与 `edgeMapFieldCache` 零 diff（只增不改）；折键区分阈值的正负测（同 prefixHash 异阈值 = 两键）+ 异 followStrength 一致性测（同键 + ridges 逐字节一致——键不含 strength，checker 回注 E1 处方甲校准）。

### T5 真图 probe 验收门 + 性能探针（KD-5）

- read_first 1/9 → probe 源清单 += RidgeExtract.swift → 8 景盒 × 多 seed 复跑（V1 同 seed 网格）+ 双跑 + 诊断行 + 性能行 → 证据落 evidence 仓 `m4-2-01/probe/`（evidence 仓内 commit）。
- 验收：**功能链 ≥6/8**（V1 基线 0/8）；probe 双跑同链；预提取 ≤50ms / 行走 ≤5ms 实测在册；主仓 `git status` 无 probe 产物命中；probe.log 诊断行完备（M4-2-02 判别数据面）。**FAIL → T6 不执行**，按 KD-5 三分支上报/转 P2。

### T6 默认回翻 + hint（KD-6，门 = T5 PASS）

- read_first 6/8 → `LayerEditingState.swift:193` 回翻 + 注释更新 + toolbar hint（0-1 键尾块纯插入）+ zh-audit 对账。
- 验收：缺省 mode 断言一条（LayerEditingState 新建态 `followEdgesParams.mode == .streamline`）；`--bundle App` 全绿；zh-audit `--check` 对新键（若有）绿；**本任务 commit 信息引用 `d10f681` 逆向与 T5 证据路径**。

### T7 收口

- SUMMARY（任务序/实测带/bundle 分账/门值校准记录）+ DECISIONS（KD 偏差/重校带/Steger 带/60582c3→d10f681 勘误/hint 0-1 键裁定/checker 回注四项终录：E1 处方甲偏差注记·M1 双撤出·M2 再附图半径·M3 平手 tie-break）+ ACCEPTANCE 双重验收记录 + GOAL-STATE 续接点（M4-2-02 触发态判定行：armed/expired）+ TODO 同批 + AGENTS.md M2-7 段收口注记 + 红线自证清单（kernel/overlay 腿/snap 函数体/PipeCache 零 diff 截证）。
- 验收：定向轮 `--bundle Layers/App` 全绿零 MEMFAIL；**全套 `--all` 轮（orchestrator 批准 + 运行监视）基线对账 3335 + 本批增量逐位**；**双重验收（config `dual_acceptance = true`）**：zcode subagent 独立验收 PASS 后 → **串行** omp 二次验收（严禁并发），两路结论落 ACCEPTANCE（+OMP）两文件；FAIL 回注修复批后重走。

## 验收标准（AC 总表）

1. **生效值①（NMS+滞回+链接）**：`RidgeExtract` 六段流水线在册、常量钉死（σ0.9/r0.4/B3/桥接对齐门 0.5〔提取期内部常量——checker 回注 E1 处方甲〕/±2 剖面/clamp1.5）；Core 零 Steger 代码（grep 机检）而 Taylor 对照腿在测试文件在册。【T1/T3】
2. **生效值②（全 CPU）**：`MaskEdgeKernels.metal` 零 diff + 全仓 PSO 清单零增量 + `readEdgeMap` 签名零改；预提取 ≤50ms @512 探针实测。【T1/T2/T5】
3. **生效值③（carrier）**：ridge 平行 dict LRU 8 + prefixHash⊕thresholdBits 折键（键不含 strength——异 followStrength 同键同 ridges 一致性测在册，checker 回注 E1 处方甲）；field 缓存零阈折（拖阈不重跑 GPU pass 的结构断言 = 两 dict 键域分离）；零持久化面。【T4】
4. **生效值④（参数面）**：UI 四件零新增（toolbar diff ≤ hint 一行）；`stepPixels` 全仓零命中（`maxPoints` params 字段同零命中、内部常量 256 收口于 FollowEdges.swift 单文件——checker 回注 M1）；`followStrength` = 行走期 junction 延续最低对齐余弦（断隙桥接对齐门 = 提取期内部常量 0.5，checker 回注 E1 处方甲）且 T 分叉两档行为差 golden 钉死（落点 = junction 走向）；`maxPoints` 256 保留。【T2/T3/T6】
5. **生效值⑤（默认回翻）**：`LayerEditingState` 缺省 `.streamline` 断言 + 回翻 commit 在 T5 门后（提交序机检）；`.snap` 分支与选择器原样。【T6】
6. **生效值⑥（golden 三轨）**：合成 9 景（≤0.75px / ≥80% 覆盖 / 噪声零链 / 双跑逐字节 / 空链降级 / snap 冻结）+ 真图 ≥6/8（probe 证据在 evidence 仓）+ snap 对照（首点 2px 邻域 + 全链贴脊）——三轨缺一不收。【T2/T3/T5】
7. **生效值⑦（V1 删除）**：`initialHeading`/`strongestRingGradient`/`stepPixels`/动量混合标识符全仓零命中；金与删同批提交（T2 单提交）；`FollowEdgesMode` 双 case + `.snap` 逐字节不动。【T2】
8. **确定性门**：合成全矩阵双跑逐字节 + probe 双跑同链，两侧在册。【T3/T5】
9. **零回归红线**：MaskRevisionTests 真产线腿两法零改绿（lazy 路径）；FollowEdgesTests 既有 8 法几何断言逐字保留；Layers/App 定向轮 + 全套 `--all` 基线对账零 MEMFAIL。【T2/T7】

## 风险与边界

- **点数门重校失据**：重校值必须实测（T2 记带）；若重校后 scene-1 边界到达断言受重采样步长影响（s_max=4px 可能跨过端点判定带）→ 缩 s_max 实测校准（内部常量微调属 KD-1 钉死值域内，DECISIONS 记），禁改几何断言凑绿。
- **junction 密集景（树叶/铁丝网）**：贪心延续错支仍贴脊 = 观察项不设门（RESEARCH 风险②）——probe 走查记录，不入 AC。
- **平行双脊质心吸附**：期望 = 吸附较强侧（RESEARCH 风险③）——合成景钉行为；若实测双脊 ≤3px 剖面合并居中，golden 定格实测行为 + DECISIONS 注记（行为缺陷与规范缺陷分账）。
- **真图门 FAIL**：三分支处置（KD-5），禁 plan 内自行扩分辨率/加 kernel。
- **`--all` 轮资源**：IOPParity 贴线在案（8104MB 峰值方差）——本批增量全在 Layers/App，理论上零扰动；MEMFAIL 先查重测漂移（AGENTS 口径）。
- **M4-2-02 衔接**：P2 = 条件触发批（细脊缺响应升级口）；T5 PASS 即 P2 expired（GOAL-STATE 记 expired，不执行）。

## 提交约定

- T1 `feat(core): ridge extraction with nms hysteresis linking and subpixel centroid`
- T2 `feat(core): replace streamline walker with ridge graph traversal`
- T3 `test(layers): nine scene golden matrix with snap frozen baseline`
- T4 `feat(app): ridge graph cache carrier with threshold folded key`
- T5 `docs(m4-2): real photo probe gate evidence for follow edges v2`
- T6 `feat(app): restore streamline as follow edges default mode`
- T7 `docs(m4-2): close follow edges v2 batch with decisions and ledger`
- 全英文 Conventional Commits；不 push；probe 证据 commit 落 evidence 仓（`m4-2-01: probe gate evidence`）。

# Phase M4-2: IOP-MASK-06 Follow Edges V2 换锚重做 — Context

> discuss/research 起草稿（2026-10-09）。规格锚点 = ROADMAP **M4-2 行**（「M2-7 熔断态（`.snap` 默认）换锚重做：脊线预提取 + 亚像素质心 + 自适应步长……验收形态：真实照片脊型走查功能链达既定门 + 与 `.snap` 对照 golden」）+ REQUIREMENTS **IOP-MASK-06**（brush 沿图像轮廓单侧跟随涂抹，Metal 边缘导向实现；Nitro 独门能力）。根因证据正本 = `phases/m2-7-masks/evidence/m2-7-3/probe/probe.log`（evidence 现存 `lightamer-evidence` 私仓，主仓 `.gitignore` 已排除 `phases/*/evidence/`）+ 熔断裁决移交 = `phases/m2-7-masks/M2-7-3-ACCEPTANCE-INPUT.md` §二/§三-3。**本 phase 走 C 档第 1 停：research 定稿后停等用户过目 OQ（文末）再 plan**。

## Phase Boundary

**范围**（ROADMAP M4-2 行 + IOP-MASK-06 + M2-7-3 挂账方向）：

1. **V2 换锚三件套**——`.streamline` 臂原位换实现：①脊线预提取（边缘幅值场 → 拓扑连通的亚像素脊折线集）②亚像素质心细化（垂直法向剖面幅值加权质心）③自适应步长行走（曲率调制步长 + junction 延续）。替换对象 = V1 逐点切向 walker 的**实现内部**；对外形状（seed → `[MaskPoint]` 链 → 既有 BrushStroke 装配 → append/mutate 腿）零变化。
2. **golden 门与验收形态**——合成脊型 fixture 矩阵（Core 单测，真值折线距离门）+ 真实照片走查功能链门（复用 M2-7-3 进程内真链探针先例）+ 与 `.snap` 对照 golden。对应 ROADMAP 验收形态两枚 ✓。
3. **模式处置收口**——验收门过后 UI 默认回翻 `.streamline`（`60582c3` 熔断行使的逆向，见 OQ-5）；`.snap` 分支与模式选择器永存（熔断架构不变）。

**非目标（本 phase 明确不做）**：

- **`.snap` 语义改动**——2 点贴边线分支原样保留（对照基准 + 降级底座双重身份）。
- **edge map 内核（`mask_edge_map`）改动**——Sobel luma 幅值 + 归一化 + 缓存键语义零 diff；V2 全部工作在读回后段。
- **蒙版数据面 / sidecar / history**——`FollowEdgesParams` 为会话态（全仓 grep 证实不入 sidecar/Library），参数面演化零迁移负担；蒙版 stamping/combine/revision 红线不触碰。
- **IOP-MASK-07 Depth 蒙版**——M4-3 地盘。
- **面板新骨架**——工具栏既有 `followEdgesSection`（mode/threshold/strength/direction 四件）为唯一 UI 面；L057 面板呈现约定不涉（无 modal 面板新增）。
- **FULL 桶路径**——V1 判据③ 语境不启用（seam 恒 preview 桶，现状不变）。

## Existing Code Insights

### V1 失稳机理（probe.log 亲证 + 源码复盘，2026-10-09）

1. **实录**：DSC00012.ARW 60.2MP 真解码 → preview 2560×1707 → edge map ≤512 场。**FIELD stats max=0.4941 / mean=0.018 / p99=0.1808**——真实照片幅值场是稀疏碎片汤（p99 连默认阈 0.25 都过不了）；8 景盒 × 2 阈值（0.25/0.15）streamline 链长 ≤3 点；100-seed 网格 82/100 空；场分辨率（1024/2560）× 步长（1.5/0.75）扫频 **0/3 功能链**（降采样假说排除——分辨率拉满仍 0）。冷 6.3ms / 热 0.001ms——预算从未是问题，稳定性才是。
2. **机理四条**（详见 RESEARCH-NOTES §1）：①**朝向信号结构性缺失**——幅值脊上沿脊方向梯度 ≈ 0，V1 依赖 lookahead 侧翼采样取切向；步长 1.5px 对 1-2px 宽的真脊会一步跨过对侧 flank，读到噪声或相邻边场，朝向随机翻转 → 一步出脊 → `sample < threshold` 断链（probe 的 n=1-3/len≤4px 逐值吻合）。②**幅值场非连续脊网络**——纹理/噪声/软边把场打成短碎片，walker 假设脚下存在连续曲线，实际逢隙即停；经典边缘检测的 NMS+滞回+链接阶段恰是补这一层，V1 缺失。③**单绝对阈错位**——非平稳场上一个绝对阈无法兼顾「纳入弱边」与「排除纹理」（滞回 = 标准解）。④**最近邻降采样放大 ①②**（次因）。
3. **V1 合成测试为何全绿**——fixture 是理想场：幅值 1.0 连续脊 + 1.5px 指数衰减 + 无隙无纹理，四条机理逐条不成立。V2 golden 必须按「能杀死 V1」的形态构造（真值折线距离门 + 真图功能链门双轨）。
4. **换锚方向三件套与机理逐条对射**——脊线预提取（NMS+滞回+链接）治 ②③；亚像素质心治 ① 的定位半；自适应步长 + 图上行走治 ① 的步进半。非三件迭加炫技，是同一根因面（逐点切向估计在真实场上信噪比结构性低下）的分解治理。

### Reusable Assets

| 资产 | 位置 | M4-2 复用判定 |
|---|---|---|
| `mask_edge_map` 单 PSO kernel + 归一化语义 | `LightamerCore/Sources/Metal/MaskEdgeKernels.metal` | **零 diff 红线**——V2 输入源原样 |
| `EdgeMapField` + `readEdgeMap`（L014 fence + ≤512 guard） | `LightamerCore/Sources/Layers/Masks/FollowEdges.swift` | 读回域原样（预提取输入域） |
| `.snap` 分支 + `snapTarget`（8px/12px 半径） | 同上 | 对照基准 + seed 贴边几何共享 |
| 熔断双 case（`.streamline`/`.snap` 穷举零 default） | `FollowEdgesMode` | 架构原样——`.streamline` 臂内换锚，不加第三 case |
| coordinator seam（`followEdgesSurface`/`edgeMapField` LRU 8 per prefixHash） | `App/Sources/Lightamer/State/PipeCoordinator.swift:1969+` | 缓存载体扩展点（OQ-3）——Core 键类型 App 不可名，M2-7-2 偏差先例沿袭 |
| 交互腿（press=seed→chain→BrushStroke→append/mutate + newest-wins generation guard + 空链降级） | `App/Sources/Lightamer/UI/Overlay/MaskOverlayHost.swift` | **零改动**——链生成器内部换锚，腿无感 |
| 工具栏参数面（mode picker + threshold/strength 滑杆 + direction toggle） | `App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift` | 演化按 OQ-4（推荐面不变） |
| 合成场测试基建（`verticalRidgeField`/`cornerField`/`rippleField` 构造器） | `Tests/LightamerTests/FollowEdgesTests.swift`（LAYERS bundle 8 法） | fixture 矩阵扩基座——理想景保留回归，新增「能杀死 V1」景 |
| 进程内真链探针（CIRAW 真解码 + 真 kernel 原文 swiftc 直编 + shim 脚手架） | evidence 仓 `m2-7-3/probe/main.swift` | 真图功能链门走查通道先例（M4-2 证据落 `lightamer-evidence` 仓同相对路径） |
| CPU walker 纯函数惯例（确定性无 RNG / 网格量化去重 / 双步进） | `FollowEdges.swift` | V2 行走段同纪律承袭 |

## Open Questions（每条含推荐；C 档第 1 停裁决点）

### OQ-1 脊线预提取算法选型（三件套之核心，必裁）
- **A（推荐）**：**Canny 式 NMS + 滞回 + 链接**——场（可选 σ≈0.8-1.0 轻高斯稳定质心与曲率）→ 沿梯度 4 象限插值非极大值抑制 → 1px 候选脊 → 滞回（high = 既有 `edgeThreshold`，low = r×high，r≈0.4 内部常量）→ 8 连通行主序确定性追踪成折线 + ≤2-3px 断隙桥接。依据：经典管线、每阶段独立可 golden（NMS 图 / 质心精度 / 链形状）、确定性纯函数、复杂度 O(N) 且 ≤512 域毫秒级；机理 ②③ 直治。链接/junction 记录进 `RidgeGraph`（Core 新类型）。
- B：**Steger 曲线检测**（Hessian 主曲率方向 + 一阶/二阶导亚像素位移）——亚像素质量最高、自带宽度估计；但需二阶导（无平滑噪声敏感）、调参面大，对「笔刷引导链」精度过剩；质心件可取其 1D Taylor 作 plan 期 A/B 对照腿。
- C：**结构张量取向场扩散 + 流线积分**——取向连续性好；但扩散迭代 + 积分阶段把 V1 同款漂移问题原样请回，复杂度不成比例。
- D：**二值骨架化 / 细化**——实现最短；丢亚像素、碎片场上断枝密布，治标不治本。
**推荐 A**；B 的 Taylor 位移式仅作 golden 对照参考实现（研究期已落 RESEARCH-NOTES §3.2），不进产线。

### OQ-2 预提取执行域：全 CPU vs GPU kernel vs 混合
- **A（推荐）**：**全 CPU（读回后段）**——工作域恒 ≤512 长边（175k px 量级），NMS+滞回+链接 Swift 纯函数毫秒级（V1 判据① 200ms 预算下占比可忽略）；零新 kernel / 零新 PSO（延续 M2-7-1「单 PSO 零 function constant」纪律与零新 kernel 红线精神）；纯函数直接合成场单测（既有 LAYERS 测试基建原样复用）。REQUIREMENTS「Metal 边缘导向实现」由 Metal edge map + Metal 缓存面满足——「CPU walker」在 D-M2-7-CONTEXT-4-A 已裁合法，V2 沿袭同分界。
- B：**GPU NMS kernel**（`MaskEdgeKernels.metal` additive 第二 kernel）——只在全分辨率场有收益；引入 PSO/管线 plumbing + 读回仍是 CPU，测试面变 GPU golden，收益域不存在。
- C：混合（GPU NMS + CPU 链接）——两头复杂度各担一半，最差组合。
**推荐 A**；若真图 probe 实测预提取超预算（>50ms @512 场），GPU NMS 作观察项逃生口挂账（不预期触发）。

### OQ-3 预提取产物缓存：随场同键缓存 vs 每 press 现算
- **A（推荐）**：**随场同键扩 carrier**——coordinator `edgeMapFieldCache`（prefixHash 键、LRU 8）的值从 `EdgeMapField` 扩为 `(field, ridges)` 双件（或平行 dict 同键同限）；预提取 lazy 于首次 press 后缓存，below 编辑翻 prefixHash 即整体失效——失效语义与 M2-7-2 偏差记录逐字一致。press 延迟 = 纯图上行走（微秒级），交互手感最优。
- B：**每 press 现算**——零缓存状态；同轮廓多次笔划重复付毫秒级提取 + 重复算法成本，无收益。
**推荐 A**；缓存归属仍在 coordinator（M2-7-2 偏差先例：Core 键类型 App 不可名，`PipeCache.swift` 非 plan 边界），App 不可持久化面不变。

### OQ-4 参数面演化：面不变改义 vs 全保留 vs 暴露新滑杆
- **A（推荐）**：**UI 面零新增，`FollowEdgesParams` 最小改义**——用户面维持 mode/threshold/strength/direction 四件；`edgeThreshold` 语义平移为滞回 high（行为连续：V1 用户调的值仍是「多强才算边」）；`followStrength` 改义为 **junction/断隙延续偏置**（0..1：延续判定的方向对齐最低余弦 + 断隙容忍的缩放——比 V1 动量混合有明确几何意义）；`stepPixels`/`maxPoints` 从 params 撤出（内部常量：自适应步长令固定步长失义；maxPoints 保留为链 fuse 常量）。`FollowEdgesParams` 会话态零持久化（grep 亲证不入 sidecar/Library）——字段变更零迁移，one-way 锁不涉。zh 预估 0-2 键（strength 标签既有键复用，至多 hint 一行）。
- B：**全保留原义**——`stepPixels` 在自适应步长架构下无处消费、`followStrength` 动量混合语义已随 V1 实现删除，留着即撒谎。
- C：**暴露新滑杆**（滞回比/桥接距离/最小步长）——内部常量 plan 钉死即可，暴露 = 调参负担转嫁用户，Nitro 描述级交互也无此面。
**推荐 A**；改义后的 `followStrength` 精确几何定义由 plan 以 golden 钉（junction 分叉走向场景）。

### OQ-5 UI 默认模式回翻时点：验收门后翻回 vs 保持 `.snap`
- **A（推荐）**：**验收门（真图功能链 + snap 对照 golden 双 ✓）过后翻回 `.streamline`**——`60582c3` 熔断一行逆向（LayerEditingState `followEdgesParams` 缺省 mode）；翻回以验收证据为前置门，不达标不翻（熔断架构的意义就是可逆且诚实）。翻回批 = phase 收口批（plan 3 尾任务），非首任务。
- B：**保持 `.snap` 默认，用户手选 streamline**——功能达标却不敢 default = 自我否定 phase 存在意义；`.snap` 仍是降级底座与对照基准（架构地位不变）。
**推荐 A**；若用户晨审偏好保守（先发 .snap 默认观察一轮），B 是合法降档，翻回动作拆独立批即可。

### OQ-6 golden 门数值：三轨门的具体定值（plan 期可调，方向先裁）
- **A（推荐）**：**合成 9 景矩阵 + 真图 8 景盒功能链 + snap 对照三轨**——①合成景 = 直脊/弧线/L 角/T 分叉/断隙脊（1-3px 隙）/平行双脊（单侧选择）/低对比段（滞回有效性）/纹理背景脊（噪声场）/变宽变强脊；断言 = 每点垂直于真值折线距离 ≤0.75px + 覆盖 ≥80% 真值长度 + 纯噪声场零链 + 双跑逐字节确定 + 空链降级语义保留；②真图 = M2-7-3 同款 8 景盒（probe 先例复跑），功能链定义 = 链 ≥12 点且弧长 ≥24px（场域）且端点贴脊 ≤2px，门 = ≥6/8 景功能链（V1 实测 0/8 基线上翻）；③snap 对照 = 同 seed 下 V2 链首点落于 snapTarget 2px 邻域 + 全链贴脊 ≤ 笔刷半径。门值 plan 期按实测校准（沿 M3-3-E5「实测收窄钉门」先例），方向 = 三轨缺一不收。
- B：**只做合成轨**——V1 教训正面打脸：合成全绿与真实失稳完全兼容，单轨门无效。
- C：**更严门**（8/8 景 + ≤0.5px）——真照片含极弱纹理景，绝对门易误伤；留 plan 期证据裁量。
**推荐 A**。

### OQ-7 V1 walker 实现处置：同批删除 vs 保留 fallback
- **A（推荐）**：**V2 落地同批删除 V1 逐点切向 walker 实现**（`streamline` 内部函数族：lookahead/动量混合/环梯度回退）——双实现并存 = 双真相源（git 历史保留全部；golden 三轨换防）；`FollowEdgesMode` 双 case 架构与 `.snap` 分支原样。删除时点 = golden 落地同一提交序内（先金后删）。
- B：**保留为内部 fallback**（V2 链空时回落 V1 walker）——V1 在真图上 82/100 空链，回落 = 把已证失效路径留在用户可达域，负收益。
**推荐 A**；挂账措辞「`.streamline` 分支与模式选择器保留，复活零重写」的兑现形态 = **分支保留、实现换锚**——分支（模式架构）不删，walker（V1 实现体）退役，语义一致无冲突。

## Canonical References

- ROADMAP M4-2 行 + REQUIREMENTS IOP-MASK-06 + M2-7 架构增量节（AGENTS.md「M2-7 架构增量」Follow Edges 熔断段）
- `phases/m2-7-masks/M2-7-CONTEXT.md`（OQ-4 原裁 + 勘误-2 edgeMapPosition）+ `M2-7-3-ACCEPTANCE-INPUT.md` §二/§三-3（熔断判据 + V2 移交方向）+ `M2-7-1-DECISIONS.md` KD-6（算法分界原裁）
- evidence 仓 `m2-7-3/probe/`（probe.log + main.swift + shim.swift——真图走查通道正本；主仓 `.gitignore` 已排 `phases/*/evidence/`，M4-2 证据同相对路径落 `lightamer-evidence` 仓）
- `LightamerCore/Sources/Layers/Masks/FollowEdges.swift` + `LightamerCore/Sources/Metal/MaskEdgeKernels.metal` + `App/Sources/Lightamer/State/PipeCoordinator.swift`（seam/缓存）+ `App/Sources/Lightamer/UI/Overlay/MaskOverlayHost.swift`（交互腿）
- `Tests/LightamerTests/FollowEdgesTests.swift`（合成场基建）+ `.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt`（LAYERS 归域规则）
- RESEARCH-NOTES.md（本目录——机理复盘/算法调研/三件套设计/golden 策略/性能预算细则）

## Specific Ideas（起草倾向，plan 细化）

- **新文件落位**：`LightamerCore/Sources/Layers/Masks/RidgeExtract.swift`（NMS/滞回/链接/质心纯函数 + `RidgeGraph` 类型）；`FollowEdges.swift` 的 `.streamline` 臂改写为 `RidgeGraph` 消费者（图上行走 + 自适应重采样）。新测试 `RidgeExtractTests` 归 LAYERS bundle（BUNDLE-MAP 域规则同批更新 `Project.swift` 显式清单 + `tuist generate` 恒收尾，L041）。
- **plan 拆分倾向**：P1 = Core 三件套 + 合成 golden（LAYERS，纯 Core 可单测）→ P2 = App 接线（缓存 carrier 扩展）+ 真图 probe 走查门 + 默认回翻 + phase 收口。两 plan 之间 V1 行为零回归（`.snap` golden 全程钉住）。
- **确定性纪律承袭**：行主序扫描序 / argmax 首中即胜 / tie-break 显式（端点序 + 距离² 序）/ 无 RNG 无时间输入——双跑逐字节 golden 钉死。
- **性能探针惯例**：预提取耗时探针沿 `LIGHTAMER_PERF_PROBE=1` + XCTSkipUnless 门（L014 fence 先于读钟——M2-5 惯例）；真图数字走 evidence 仓 probe（不入单测）。

## Deferred Ideas

- 蒙版宽度沿脊自适应（brush radius 随脊宽度调制）——Steger 式宽度估计的副产品能力，V2 不做，挂观察。
- 脊线场全分辨率 GPU NMS（OQ-2 观察项逃生口）——预算实测超门才立项。
- Follow Edges 参数预设/记忆（跨会话 params 持久化）——会话态现状维持，用户反馈后议。
- IOP-MASK-07 Depth——M4-3 既定。

---

## C 档第 1 停（research 定稿停等裁决）

本 CONTEXT 与 RESEARCH-NOTES.md 为 research 定稿产出（一笔 docs commit，未 push）。**按 AGENTS.md「C 档门控」第 1 条：Phase research 定稿后停——等用户过目 OQ-1..7（尤其 OQ-1 算法选型 / OQ-4 参数改义 / OQ-5 回翻时点）裁决后再入 plan。**晨审可整批推翻；推翻任一条 = 修订对应 plan（CONTEXT OQ 原文不改、以 Ruling 注记为准，沿 M2-3-CONTEXT E1 勘误先例）。

## 裁决记录（用户回批 2026-10-10）

**OQ-1..7 全部按推荐采纳（全 A）**：①Canny 式 NMS+滞回+链接（Steger 仅 golden 对照）②全 CPU 读回后段（GPU NMS 逃生口）③随场同键 coordinator carrier LRU 8 ④UI 零新增、followStrength 改义、stepPixels 撤出 ⑤验收门后翻回 .streamline ⑥合成 9 景 + 真图 8 景盒 ≥6/8 + snap 对照 ⑦V1 walker 实现体 golden 落地同批删除（分支保留）。

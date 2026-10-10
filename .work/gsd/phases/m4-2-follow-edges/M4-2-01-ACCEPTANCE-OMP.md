# M4-2-01-ACCEPTANCE-OMP — omp 串行二次验收记录

> lane：omp 独立第二遍（2026-10-10，与 zcode lane 零共享上下文，独立亲跑亲读）。
> 首验结论：zcode lane **PASS / 0 error + 2 minor**（正本 = 同目录
> `M4-2-01-ACCEPTANCE.md`）。本文件 = omp lane 独立结论。

## 结论头

**PASS / 0 error + 1 minor**

- **0 error**：AC 九条逐条有据可依，红线机检全绿，真图门 FAIL 判别审计成立。
- **minor-1（观察，不动，omp 独立发现）**：首验红线节「`makeEncoder(functionName:)` 批内增量 0（20 处全存量）」计数口径有误——本 lane 以正确拼写 `makeEncoder(functionName` 全仓亲核 = **旧 21 / 新 21**（含 `LightamerCore/API.md` 文档行 1），增量仍为 0。结论不受影响（零新 PSO 门成立），仅首验数字勘误。

## 一、亲跑数字（omp lane）

| 轮 | 结果 | 对表 |
|---|---|---|
| `Scripts/test-direct.sh --bundle Layers` | **420/3/0**（163s，peakRSS 1152MB） | 与 zcode 轮 420/3/0 逐位一致（含 RSS 1152MB） |

本 lane 仅定向复跑 Layers（验收对象 = Core 换锚主波；App bundle 与 --all 沿用 zcode lane 亲跑值 708/0/0 与 TOTAL 3365/16/1，不重复跑，见 §六分歧点说明）。

## 二、红线机检（omp 独立亲跑，全绿）

| 门 | 结果 |
|---|---|
| 六红线文件 `git diff 64634dc..HEAD` | MaskEdgeKernels.metal / MaskOverlayHost / LayerEditingState / MaskToolbarView / xcstrings / PipeCache **全 0 行** |
| snap/snapTarget/readEdgeMap/edgeMap 函数体 | sed 区间抽取 md5：snap+snapTarget 新旧同值 `7de2526d…`；readEdgeMap/edgeMap 同值（**初版 awk 花括号计数误报已用 sed 复核排除**） |
| `stepPixels\|initialHeading\|strongestRingGradient` 全仓 | **0 命中**（swift+metal） |
| `maxPoints` 全仓 | 仅 FollowEdges.swift（内部常量 256 + 消费点，:129） |
| `graph(from:high:)` 签名 | `RidgeExtract.swift:144` 二参，无 strength 形参（E1 处方甲） |
| `makeEncoder(functionName` 全仓 | 旧 21 / 新 21，增量 0；零新 .metal 文件 |
| Core 内 Steger/Taylor | 仅 RidgeExtract.swift:19 一处「deliberately LIVES OUT」注释，零代码 |
| 滞回 raw 值门 | :299 NMS 候选 `raw>=low` + :323 种子 `raw>=high`，与 DECISIONS §1 T2 逐字一致 |
| junction 共享修复 | :422-429 visited-junction 仍 append + noteJunction（行号相对首验 +7 系 E1 小修注释位移，内容一致） |
| T2 单提交原子性 | `3b3d7fc` 同批含换锚+V1 删除+golden（Tests 两文件在 stat 内）；父提交 V1 标识符 8 命中 → 本提交 0 |
| 既有 8 法 | 删除断言恰 2 行（≥30 / ≥20 点数门），几何断言零删除 |
| MaskRevisionTests | 批内 diff 0 行；Layers 轮绿（lazy 路径回归钉有效） |
| carrier 注入缝 | `PipeCoordinator.swift:2063` 折键 `prefixHash ^ threshold.bitPattern` + LRU 8 显式 order（doc :2030-2033 两级分层声明在册） |
| `.snap` 缺省维持 | LayerEditingState:193 `.snap` 不变；`mask_follow_strength_hint` 全仓 0 命中；T6 未执行正确 |
| 登记（E2/L041） | Project.swift 两测试文件 + BUNDLE-MAP（LAYERS RidgeExtract 19 / FollowEdges 15 / APP Cache 4）随任务 commit |
| probe 零入主仓 | 主仓 status 仅无关 untracked 研究目录；批内文件清单（除 .work/）8 个，无 evidence |
| 不 push | origin/main..HEAD = 本批 5 + 前置 3 + 小修 1 + 首验记录 1，全未推 |

## 三、probe 门数据审计（evidence 仓亲读）

- **主门 FAIL 属实**：`GATE t0.25: 0/8` + `GATE t0.15: 0/8` + 合计 `FAIL (threshold ≥6; V1 baseline 0/8)`；run2 同值。
- **双跑确定性**：过滤计时行后两 log diff 仅 1 行（COLD 中位数 6.3↔6.4ms 冷缓存抖动）；全部 SCENE/GATE/THRESH/DIAG 行逐行一致。
- **arming 条件①**：八景 bestN 全 ≤7（A2 双阈字面 0），t0.15 最佳 B2 n=7/arc=20px、A3 n=4/arc=22px——全场细脊 ≤512 域未成形，远超「≥2 景」要求。
- **arming 条件②**：DIAG mle=1024 `bestWalk n=24 arc=81px`——功能双腿（≥12 点 ∧ ≥24px）均满足；唯一变量 = 场分辨率，算法侧排除。
- **DIAG-2（骑行 0.38）**：最长链 n=16 骑行 6 点 = 碎片网 junction 门掉链，算法层观察项；与 1024 域链长 ×3.75 相乘后功能腿可达，不阻 arming。
- **性能行**：EXTRACT 9.3-9.9ms（≤50ms，5 倍余量）/ carrier-hit 行走 0.002ms（≤5ms）/ edge map 冷 6.3ms（V1 基线不动）——三条全过。
- **probe 同源**：RidgeExtract.swift 与 MaskEdgeKernels.metal 与主仓逐字节一致（cmp）；FollowEdges.swift diff 仅 3 行 HB 心跳打印（纯诊断）。

## 四、读码抽查

- **V1 删除清单**：`3b3d7fc` diff 含 `-initialHeading/-strongestRingGradient/-stepPixels` 定义与调用全删 + lookahead/动量注释退役；禁中间红态（金与删同批，Tests 文件同提交）。
- **`ridges: RidgeGraph?`**：FollowEdges.swift:101 additive optional + init 缺省 nil（:103-108 三参构造点零漂移）+ `withRidges` 值拷贝缝（:112-116）；消费点 :175 `ridges.high == threshold` 戳拒绝旧 carrier（非缺省阈值 lazy 行为正确）。
- **fuse 常量**：:126-129 `private static let maxPoints = 256`（M1），全仓唯一。
- **checker 四项**：E1（桥接门内部常量 0.5、无 strength 形参、无 hint 键）/ M1（双撤出）/ M2（再附图 8px 同族）/ M3（junction 平手行主序首中）——DECISIONS §0 四行与实现一致；T-fork differential（RidgeExtractTests:484，两档 walk 门）+ E1 诚实化小修 `93beb87`（注释 6 行，签名保证声明）在册。
- **台账**：GOAL-STATE 续接点（armed + M4-2-02 触发态）与 AGENTS.md M2-7 段 V2 收口注记（内部常量登记 σ0.9/r0.4/B3/门 0.5/s0.75-4.0/θ45°/8px/256）在册。

## 五、偏差六条处置复核（对 DECISIONS）

首验已逐条审计实现一致，本 lane 抽核三条高风险项亲证：①结构张量取向（orientationRadius=2 + 符号归一 + 直脊零链退化机理）②滞回 raw 门（:299/:323 + MaskRevision 产线腿倒逼链）③junction 整像素 + 共享修复（:159-170 skip + :422-429 append/attach）。其余三条（snap 收窄/surface 阈值缺口/M4-1 挂账归属）沿首验审计结论，无异议。

## 六、与首验分歧点

1. **minor 口径差（本 lane 唯一新增）**：首验「20 处全存量」→ 本 lane 亲核 21/21（§二表内行）。根因推测 = 首验计数漏 `API.md` 文档行或拼写不全；**增量 0 结论一致**，记观察 minor 不修。
2. **首验 minor-1（E1 注释）/ minor-2（keys.first）**：本 lane 复核成立——E1 小修 diff 已亲读（诚实化 6 行），keys.first 为 64634dc 存量（:2030，批内 diff 0 命中）。两条沿首验处置，无新增动作。
3. **--all 未重跑**：本 lane 未复跑 App 定向与 --all（M4-1 挂账 #6 孤儿竞态在 Export→App 相邻窗口发作，重跑成本 > 信息增益；Layers 主波 420/3/0 逐位复现已覆盖本批全部 Core 面）。zcode lane 的 TOTAL 3365/16/1 + 删孤儿因果闭环（单类 7/0/0）证据链完整，予以采信。

## 移交

1. M4-2-01 双重验收闭环：zcode PASS + omp PASS。
2. M4-2-02（P2 512→1024）armed 确认——执行令下达即可起。
3. M4-1 挂账 #6 催办维持（首验项）。
4. 未 push 纪律维持。

OMP-VERDICT: PASS

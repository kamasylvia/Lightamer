# M4-2 Plan-Set Checker Report（M4-2-01 + M4-2-02，从严）

> checker = zcode subagent（双重验收制度 zcode 路；2026-10-10）。
> 审查对象 = `M4-2-01-PLAN.md` / `M4-2-02-PLAN.md`（执行前 plan-set 审查，非代码验收）。
> 裁决正本 = `M4-2-CONTEXT.md` 文末裁决记录（OQ-1..7 全 A，2026-10-10 用户回批）；
> 规格正本 = `RESEARCH-NOTES.md`。全部源码锚 / 行号锚 / SHA 勘误 / probe 证据均**亲核**。

# FAIL / 1 error + 3 minor

三敏感结构（算法实现 / V1 删除同批禁中间红态 / 默认回翻执行门）本体全部成立、可执行；
1 error 为 **plan 内部三节相互矛盾**（KD-1⑤ ↔ KD-2① ↔ KD-4），须 T2 动工前在 DECISIONS
消解，不重开任何裁决；3 minor 为规格自由裁量缺口，各附处方。其余八维全过（见 §三）。

---

## 一、error（必修，回注 plan/DECISIONS 后放行）

### E1 followStrength 进入提取面（KD-1⑤）与缓存键（KD-4）及纯函数声明（KD-2①）三方不相容

- **矛盾实录**（三节原文互斥）：
  1. KD-1⑤：桥接门 = 「端点距 + 方向对齐（**余弦 ≥ followStrength 门**）」——followStrength 是
     **提取期**输入；
  2. KD-4：ridge 缓存键 = **prefixHash ⊕ edgeThreshold.bitPattern**（无 followStrength 项）；
     AC3 机检锚只有「同 prefixHash 异阈值 = 两键」正负测；
  3. KD-2①：「nil → lazy 提取（**纯函数语义：同 field 同 params 同输出**；coordinator 注入
     ridges 时零重提取）」——若提取消费 params.followStrength，则「同 field 同 params 同输出」
     与「注入的缓存 ridges」不可能同时成立（strength 拖动后注入值 ≠ 重提取值）。
- **若照单执行的后果**：用户拖 strength 滑杆 → prefixHash 与阈值均不变 → 命中旧 ridge 缓存 →
  桥接按旧 strength 门服务；`FollowEdgesRidgeCacheTests`（只测阈值折键）**抓不到**；
  违反 plan 自己声明的纯函数不变式。
- **根源**：OQ-3-A（键 = threshold 折叠）与 OQ-4-A（followStrength = junction 延续余弦
  **+ 断隙桥接同门**）两条裁决各自成立，plan 把两者落进 KD 时未消解其交互。
- **处方**（任选其一，均**不重开裁决**；DECISIONS 钉死 + 机检补齐）：
  - **处方甲（推荐）**：桥接对齐门改为提取期**内部常量**（如 0.5 与缺省同值），followStrength
    只治 KD-2③ 行走期 junction 延续——提取真正成为 `(field, edgeThreshold)` 的纯函数，KD-4 键
    原样、KD-2① 纯函数句原样、OQ-3 字面原样；OQ-4 的「断隙桥接同门」以 DECISIONS 偏差注记
    收窄（「同门」解释为缺省同值常量）。
  - **处方乙**：保留 KD-1⑤ 原文，ridge 缓存键**追加** followStrength.bitPattern 折叠项
    （OQ-3 的本体 = field 缓存不因拖阈重跑 GPU pass——两级分层不变，只是 ridge 级键多一项；
    strength 拖动付 ms 级重提取）。AC3 正负测同步补「同 prefixHash 异 strength = 两键」。
  - 两案都须同步：`RidgeExtract.graph(from:field:high:followStrengthBridgeGate:)` 签名
    （KD-4 出现的该形参名随方案甲删除/随乙保留）+ T3 followStrength 两档行为差 golden 的
    落点（甲 = 只钉 junction 走向；乙 = junction + 桥接两侧）。

## 二、minor（各附处方，T2 执行时顺手闭合）

### M1 maxPoints 处置两读（OQ-4-A 字母面 vs plan files_modified 面）

- OQ-4-A 裁决原文：「`stepPixels`/`maxPoints` **从 params 撤出**（…maxPoints 保留为链 fuse
  常量）」= 双撤出；plan 生效值④写「`maxPoints` 保留链 fuse 常量（256 不变）」、files_modified
  只写「`FollowEdgesParams.stepPixels` 撤出」——可读成 params 字段保留。两读行为等价
  （全仓无任何 maxPoints 设值点，亲核），但与裁决字母面有偏差风险。
- **处方**：T2 DECISIONS 钉死一行（按裁决字母 = 字段撤出 + 内部常量 256；如实现选择字段保留
  则记偏差理由）。grep `maxPoints` 收口 = FollowEdges.swift 单文件。

### M2 seed 附着回退臂的「再附图」半径未钉

- KD-2①：主路径 = 8px 内最近 RidgeChain 顶点；回退臂 = V1 同款 8px `snapTarget` 最强邻后
  「**再附图**」——再附图搜索的半径/是否仍限 8px 未写明（回退臂命中点可距 seed 达 8px，
  其 8px 邻域与 seed 8px 邻域不同集合）。tie-break（距²序 → 行主序）已给，半径缺口留给实现
  自由裁量。
- **处方**：T2 实现钉死（建议再附图同 8px，`snapTarget` 同族几何）+ DECISIONS 一行。

### M3 junction 延续的余弦平手 tie-break 未显式

- KD-2③ 只写「余弦最大者胜；无一过门 = 停」；两候选分支余弦相等时的决胜序未点名。
  KD-1 确定性纪律的「argmax 首中即胜」可覆盖，但分支枚举序（行主序？入链序？）未写。
- **处方**：T2 按「候选分支按其首顶点行主序枚举 + 首中即胜」落 DECISIONS；T 分叉景
  followStrength {0.2, 0.8} golden 不受影响（两档远离平手域）。

### 观察项（不计，不阻塞）

- KD-1「全阶段 O(N)」对桥接段是宽松表述（端点两两 O(E²)，E ≪ N 实践无虞）——probe 实测行
  会给真值，不修文本。
- KD-2⑤ 停止条件「断隙 > 3px」在合链后的折线上不可达（桥接已在提取面完成，链内无 >3px 隙）
  ——冗余但无害，防御式条件保留即可。
- T2 删除 V1 后 `gradient`/`lengthOf` 可能成死私有件（V1 三消费点 initialHeading /
  strongestRingGradient / walk lookahead 全在删除清单内）——非编译错误，收口 sweep 顺手清理。
- 架构红线行号「MaskRevisionTests :507/:559」= 两法内 `FollowEdgesInteraction.chain` 注入
  调用点行（func 声明在 :497/:546）——锚定准确，无需勘误。

---

## 三、八维审查结论（全过部分逐条对账）

### 1. 裁决一致性（七项生效值逐条对 AC）——PASS

| 生效值 | plan 落点 | AC 映射 | 亲核 |
|---|---|---|---|
| ① Canny 式三段 | KD-1 六段流水线 + 常量钉死（σ0.9/r0.4/B3/±2 剖面/clamp1.5） | AC1 | σ=0.9：ceil(3σ)=3 → 7-tap ✓；Steger 仅测试文件 grep 机检（`Steger\|Taylor` Core 零命中）✓ |
| ② 全 CPU | 零新 kernel/PSO/零 function constant；`MaskEdgeKernels.metal` 零 diff；`readEdgeMap` 签名零改 | AC2 | 亲核 kernel（Sobel luma 幅值 ÷4√2 = 5.656854249492381 ✓ 阈前归一化）；`makeEncoder(functionName:)` 全仓现清单 13 件亲列（零增量可机检）；`readEdgeMap(plane, maxLongEdge: 512, metal:)` 缺省 512 ✓ |
| ③ carrier 两级 | KD-4 平行 dict LRU 8 + 折键；field 缓存零阈折 | AC3 | 亲核 `edgeMapFieldCache [UInt64: EdgeMapField]` + `edgeMapFieldCacheLimit = 8`（PipeCoordinator :2017-2019）——两 dict 键域分离结构断言成立 ✓（键的 strength 缺口见 E1） |
| ④ 面不变改义 | toolbar diff ≤ hint 一行；stepPixels 撤出；followStrength 改义；maxPoints 256 | AC4 | 亲核 `followEdgesSection`（MaskToolbarView :201-260，四件结构无 stepPixels）；stepPixels 全仓消费面 = 定义三行 + streamline 一行 + FollowEdgesTests:91 一处，**亲证** ✓（maxPoints 两读见 M1） |
| ⑤ 回翻执行门 | T6 = `LayerEditingState.swift:193` 翻回，门 = T5 PASS；提交序机检 | AC5 | 亲核 :193 = `var followEdgesParams = FollowEdgesParams(mode: .snap)` 精确命中；任务序即门序 + commit 引用 d10f681 逆向与 T5 证据路径 ✓ |
| ⑥ golden 三轨 | KD-3：合成 9 景 + 真图 ≥6/8 + snap 对照；缺一不收 | AC6 | 九景清单与 OQ-6-A 逐景一致 ✓；功能链定义（≥12 点 ∧ ≥24px ∧ 端点贴脊 ≤2px）与 M2-7 probe 先例同构 ✓ |
| ⑦ V1 同批删除 | KD-2 删除清单 + T2 单提交「金与删同批，禁中间红态」 | AC7 | 删除清单 = `initialHeading`/`strongestRingGradient`/walk 闭包 lookahead+动量混合/stepPixels 字段+init 缺省——亲核现源全部存在且仅 FollowEdges.swift 内；`FollowEdgesTests.swift:91` 同批更新入 T2 ✓（编译依赖图无外部消费点，单提交可执行，无中间红态路径） |

### 2. 算法实现审查（六段流水线数学正确性）——PASS

- **轻高斯** σ=0.9 可分离 7-tap（半径 ceil(3·0.9)=3）、边界 clamp、先行后列固定序：确定性 ✓。
- **梯度**：平滑场上中心差分——对幅值场求梯度得跨脊方向，NMS 沿其抑制非脊点 = 标准幅值场
  NMS 形态 ✓。
- **NMS**：4 象限量化 + 线性插值取 ±1 亚像素比较值；保留判据 `v > n1 && v >= n2` 非对称
  tie——2px 平台脊恰存活一点、全平台场全灭、确定性三性质逐验 ✓。
- **滞回**：high=既有 edgeThreshold（语义连续平移）、low=0.4·high；强点行主序作种 + 8 连通
  生长收 ≥low 域 = 标准形 ✓。强点若遭 NMS 平台抑制，同值邻点凭连通回纳（无强点丢失）✓。
- **链接**：端点 = 8 邻度 <2、度 ≥3 记 junction、环后行主序、桥接 B=3 + 距²序 → 行主序
  tie——确定性完备（junction 平手见 M3）。
- **亚像素质心**：法向 ±2 剖面 bilinear、`w_k = max(f_k − low, 0)` 非负、δ = Σk·w_k/Σw_k、
  Σw<ε→0、|δ|≤1.5 clamp——有界纯函数；精度预期 ≤0.3px / 门 0.75px 含噪声余量，比例合理 ✓。
- **自适应重采样**：`s = s_min + (s_max−s_min)·(1 − min(θ,θ_max)/θ_max)`——θ=0 → s_max=4.0、
  θ=θ_max → s_min=0.75、单调递减；弦高误差上界 s²/8R 在 R≥10px 时 ≤0.2px < 0.75px 门 ✓；
  直脊端到端两端点可达性（minY≤6 / maxY≥57 在 s_max=4 下成立且 plan 已设「跨端点判定带 →
  缩 s_max 实测校准，禁改几何断言凑绿」风险条款）✓。
- **性能预算落 AC**：预提取 ≤50ms @512 在 AC2；行走 ≤5ms 在 KD-5/T5 验收行（实测任务落位）；
  O(N) 五段毫秒级预期 5-15ms；L014 边界澄清正确（edge map 读回后计时，无 GPU 读回计时）✓。
- **确定性门可测性**：合成全矩阵双跑逐字节（T3）+ probe 双跑同链（T5）双侧在册 ✓。

### 3. 换锚正确性（V1 失稳机理 → V2 三件套对射）——PASS

- probe.log 亲读：FIELD stats max=0.4941/mean=0.018/p99=0.1808 + 链长 ≤3 + 82/100 空 +
  扫频 0/3 + 冷 6.3ms——plan/RESEARCH 引值逐值与 evidence 仓 log 一致 ✓。
- 机理→治理对射：①朝向缺失 → 质心（定位半）+ 图上行走/自适应步长（步进半）；②碎片场 →
  NMS+链接；③单绝对阈 → 滞回；④降采样 → 轻高斯 + low 腿——四条全覆盖、非炫技迭加 ✓。
- `.streamline` 臂几何语义：8px 附着（`snapTarget` 同族 + tie-break 显式）/ 双向遍历（V1
  双步进承袭，direction ±1 输出序 + junction 符号侧——单侧跟随语义保持，IOP-MASK-06
  「单侧」不失义）/ junction 贪心（余弦门）/ 弧长重采样（跨链清零）/ 停止条件四件 ✓。
- snap 冻结基准对照轨：snap 函数体零 diff + 三景输出常量硬编码 + 首点 2px 邻域 + 全链贴脊
  ≤笔刷半径——对照基准双重身份钉死 ✓。

### 4. 结构敏感面——PASS（E1 除外）

- **V1 删除同批单提交可执行性**：删除面全部私有/单文件 + 唯一外部消费点（tests:91）同批
  更新 + T1 先行落 RidgeExtract（T2 依赖齐备）——每提交绿、无「删 V1 而 golden 未绿」中间态
  路径 ✓。
- **EdgeMapField additive `ridges: RidgeGraph?`**：显式 init 保留、缺省 nil 既有构造点零漂移
  + 负测钉死；`FollowEdgesInteraction.fieldReader` 返回类型不变 → `MaskOverlayHost.swift`
  交互腿零 diff 可达（亲核 :880-907 seam 签名）✓。
- **lazy 路径回归钉**：MaskRevisionTests :507/:559 两法 fieldReader 无 ridges（真产线腿注入
  形态亲读）→ V2 `field.ridges == nil` 链内 lazy 提取必须原样绿——负测即回归钉，plan 明示 ✓。
- **stepPixels 撤出全仓 grep**：现全仓 6 命中（Core 定义 3 + 消费 1 + 测试 1 处调用 + init），
  T2 后零命中机检可行、清单完备 ✓。
- **缓存两级分层**：field 缓存键（prefixHash）零阈折 + ridge 键折阈 → 拖阈只重提取不重跑
  GPU pass，结构断言 = 两 dict 键域分离 ✓（strength 项缺口 = E1）。

### 5. 02 条件触发——PASS

- 三分支判别可操作：主门 <6/8 + 细脊缺响应（**≥2 败景** NMS 候选零/近零 **且** 候选在场处
  链指标正常——「场里没脊」vs「走了不稳」二分内联澄清）+ 机制轨健康（合成/snap/确定性全绿）
  ——判定数据面 = T5 probe 诊断行（FIELD stats/NMS 候选数/滞回强弱点数/链指标）逐项在 KD-3
  落位 ✓。
- 三档预算阶梯：≤50 维持 / >50≤200 = V1 判据① 200ms 总门内 → 门修订申请 + orchestrator
  追认（追认前按既有 200ms 门继续 = 沿用旧预算非新立）/ >200 = 停 + GPU NMS 立项上报；
  **禁自行二级升级**（2048 / 自行 kernel 化双禁）显式在册 ✓。
- expired 归档：T5 PASS → 02 整体作废，GOAL-STATE 记 expired、文件保留（触发条件与升级行动
  在案正本）✓；升参收窄 = 产线唯一改动 `PipeCoordinator` :2026 一处（行号亲核精确命中），
  `readEdgeMap` 签名/缺省/函数体零 diff 机检 ✓。

### 6. 测试对账——PASS

- **3335 基线亲核**：bundle 分账 562+427+394+619+279+350+704 = **3335** 求和自洽；与
  GOAL-STATE M4-1 终验 `TOTAL|3335/16/0|1604s` 一致 ✓；增量面 = Layers（394 起）+ App
  （704 起）与 test_bundles 一致 ✓。
- **+21..29 合理**：RidgeExtractTests（T1 阶段法 6-8 + T3 场景 5-6）+ FollowEdgesTests 新法
  4-6 + RidgeCacheTests 3-4 ≈ 18-24..29 区间内 ✓。
- **合成 9 景**：断言族（≤0.75px / ≥80% 覆盖 / 噪声零链 / 双跑逐字节 / 空链降级三态 / snap
  冻结）全在册；杀 V1 景（纹理背景脊）正测与纯噪声负测并列 ✓。
- **真图 8 景盒 ≥6/8**：probe 通道亲核在案（evidence 仓 `m2-7-3/probe/` main.swift/shim.swift/
  MaskPointExtract.swift/probe.log 四件）；源清单 += RidgeExtract.swift 一行增量明确；证据落
  evidence 仓 + 主仓 `.gitignore :80` `.work/gsd/phases/*/evidence/` 亲核在案（零入主仓 commit
  机检可行）✓。
- **Steger Taylor 对照腿只住测试文件**：T1 AC grep 机检锚在册 ✓。
- **既有 8 法**：FollowEdgesTests 现有方法恰 8 个（亲列）；几何断言逐字保留 + 点数门实测重校
  （禁拍脑袋、禁凑绿双禁）✓。

### 7. 账面勘误——PASS

- **`d10f681` 引用勘误正当性亲证**：`git log -1 d10f681` = `chore(m2-7): follow edges default
  to snap mode` 在案；`git cat-file -t 60582c3` = **fatal: Not a valid object name**（不可达
  亲证）；`git log -S "FollowEdgesParams(mode: .snap)"` 恰命中 d10f681；且 M2-7-ACCEPTANCE-OMP
  早已记载 60582c3 系公开仓压缩前旧 SHA 体系——三证齐。处置（T6 逆向对象 = d10f681 +
  DECISIONS 登记 + CONTEXT 原文不改）合 Ruling 注记先例 ✓。
- **followStrength 改义零迁移 grep 亲证**：`FollowEdgesParams` 非 Codable；Sidecar/Library
  全目录 grep 零命中；App 消费面仅 LayerEditingState/toolbar/overlay 三处（会话态）——字段
  变更零迁移成立 ✓。

### 8. goal-backward——PASS

- IOP-MASK-06 交付定义：Metal 边缘导向（kernel + 缓存面）+ CPU 行走段（D-M2-7-CONTEXT-4-A
  已裁合法分界，V2 不移界）+ 单侧跟随（direction 语义保持）✓。
- ROADMAP M4-2 行两枚 ✓：真图功能链门（OQ-6②轨）+ snap 对照 golden（OQ-6③轨）全覆盖 ✓。
- M2-7 挂账「`.streamline` 分支保留、复活零重写」兑现 = 分支保留 + 实现换锚（OQ-7-A）✓。
- 挂账验收对射：熔断收口注记入 AGENTS.md M2-7 段（T7）+ 内部常量登记单源 ✓。

### 体例与流程（附加核）

- front-matter 字段 / read_first / Tasks / AC 总表 / 风险与边界 / 提交约定与 M4-1-01/02 同构 ✓。
- 行号锚全亲核命中：LayerEditingState:193 / PipeCoordinator :2026（02）/ FollowEdgesTests:91 /
  MaskRevisionTests :507/:559（注入点）/ MaskOverlayHost :880-907 / MaskToolbarView :201-260 ✓。
- `Scripts/test-direct.sh` bundle 名 Layers/App 亲核在 BUNDLES 注册表 ✓；Project.swift
  LightamerTestsLayers/App target 在案（L041 尾闸条款在册）✓；BUNDLE-MAP 增行随任务 commit
  （E2）✓。
- `paused = false` / `auto = true` / `dual_acceptance = true`（.work/config.toml 亲读）——T7
  双重验收（zcode PASS → 串行 omp 禁并发）与 config 一致 ✓；`--all` 轮 orchestrator 批准 +
  MEMFAIL 机检与 AGENTS 资源监控口径一致 ✓。

---

## 四、放行条件

1. **E1**：T2 动工前在 M4-2-01-DECISIONS 消解（处方甲/乙二选一 + 机检同步）；不重开 OQ-3/
   OQ-4 裁决本体。
2. **M1/M2/M3**：T2 DECISIONS 各钉一行。
3. 其余按 plan 执行；T5 门与 T6 序严格保持（提交序机检）。

> 本报告为 plan-set 执行前审查（结构/规格/可执行性），非代码验收；T7 双重验收按 plan 原条款
> 执行（zcode PASS → 串行 omp）。

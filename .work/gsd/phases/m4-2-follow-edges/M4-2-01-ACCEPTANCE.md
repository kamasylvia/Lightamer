# M4-2-01 ACCEPTANCE — 双重验收记录

> 状态：**zcode lane PASS**（2026-10-10 独立验收 subagent，零共享上下文实测核验）。
> omp 串行二次验收**未跑**（orchestrator 编排——config `dual_acceptance = true`
> 的第二路，本文件追加记录其结论）。

## 结论头

**PASS / 0 error + 2 minor**（zcode lane）

- **0 error**：九条 AC 总表逐条实测过，红线机检全绿，无违反。
- **minor-1（已修）**：`testMatrixTForkFollowStrengthDifferential` 的 E1 断言为
  自比较（graph(from:high:) 与自身比），注释宣称「extraction never consumes
  strength」并非该断言所证——真保证是签名层面（无 strength 形参可传）。
  处置 = 注释诚实化（断言保留，改为如实声明签名保证 + 指向真正承载
  strength 无关面的两处断言）；`93beb87`，RidgeExtractTests 19/0/0 重跑绿。
- **minor-2（观察，不动）**：`edgeMapFieldCache`（field 级，M2-7-2 先例）LRU
  逐出取 `keys.first`（Dictionary 无序）——本批零 diff 面（先例代码），新
  `FollowEdgesRidgeCache` 用显式 order 数组无此问题；挂 M2-7-2 偏差先例名下，
  非本批引入。

## 亲跑数字（验收轮）

| 轮 | 结果 | 备注 |
|---|---|---|
| `--bundle Layers` | **420/3/0**（157s，peakRSS 1152MB） | 与申报逐位一致 |
| `--bundle App` | **708/0/0**（363s，peakRSS 2832MB） | 与申报逐位一致 |
| `--all` 全套 | **TOTAL 3365/16/1**（1582s） | **计数精确对账** = 基线 3335 + 30 |
| 单类重跑 RidgeExtractTests | 19/0/0 | 小修后回归 |
| 单类重跑 RasterEditFaceTests | 7/0/0 | 孤儿清除后（见下） |

**--all 的 1 fail = `RasterEditFaceTests/testRestoreWinsOverDerive`，M4-1 挂账 #6
同族亲证、与本批零相关**：

- 机制现场：`Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra` 孤儿在盘，
  mtime 13:47 = 本轮 --all 的 App bundle 窗口（写方 = Export bundle
  `testEditReplaySurvivesFlushAndReload`，M4-1-VALIDATION R1-R4 三轮对照在案）。
- 因果闭环（验收方独立实验）：删孤儿（untracked，`git status ??` 亲证）→
  单类重跑 7/0/0 绿。本会话时间线亦互证：App 定向轮（--all 之前，树无孤儿）
  708/0/0 绿；--all（Export→App 相邻）发作。
- 归属：M4-1 挂账 #6 所有（修复方向在案 = 写方改 tmp 域拷贝 + 双前清）；
  worker 的「T3 基线 stash 复现」申报与本轮独立复现一致。**不阻塞本批**。

## 门 FAIL 判别审计（KD-5 三分支，T5 = FAIL 0/8）

**裁定：armed 判定成立**——「细脊缺响应 → M4-2-02」分支调用有效。

证据链（evidence 仓 `m4-2-01/probe/` commit `156b7cf` 亲读）：

1. **主门 FAIL 属实**：probe.log 双跑（probe.log / probe-run2.log）全部
   SCENE/GATE/THRESH/DIAG 行逐行一致（仅计时行抖动：PLANE 8108↔855ms 冷缓存、
   EXTRACT 9.9↔10.1ms——确定性面零漂移）；`GATE t0.25: 0/8` + `GATE t0.15: 0/8`
   + 合计 `FAIL (threshold ≥6; V1 baseline 0/8)`。
2. **arming 条件①（≥2 败景 NMS 候选零/近零）**：八景 bestN 全带 ≤7（5 seed 每
   景；A2 双阈字面 0）——远超「≥2 景」要求，全场细脊在 ≤512 域未成形。
3. **arming 条件②（败因 = 输入侧非算法侧）**：DIAG mle=1024 行
   `bestWalk n=24 arc=81px`——功能双腿（≥12 点 ∧ ≥24px）均满足；同一 walker、
   同一提取器，唯一变量 = 场分辨率。**审计注记（诚实记录）**：512 域到场候选处
   的 walk 指标本身未达功能腿（bestN ≤7 / bestArc ≤22px），条件②的「到场脊上
   链指标正常」严格读只在 1024 诊断上成立而非 512 场景行；判别不受翻转——
   1024 实验正是「分辨率是主导变量」的隔离证明，与机制轨健康（条件③）共同
   排除「算法失稳」分支。
4. **arming 条件③（机制轨健康）**：合成九景 + snap 对照轨 + 双跑确定性全绿
   （Layers 420/3/0 验收亲证含全部 19 个 RidgeExtractTests + 15 个
   FollowEdgesTests）。
5. **DIAG-2（骑行分数 0.38）定性正确**：最长链 16 顶点骑行仅 6 点 = 碎片网
   junction 门致掉链，算法层观察项；不阻 P2 arming（1024 域链长 ×3.75 使同
   分数下功能腿仍可达），随报不上分支——与 M4-2-02-PLAN「算法失稳 → 禁升
   分辨率掩盖」的排除逻辑相容（该分支要求「候选在场但链断/漂移」为**主导**
   败因，实测主导变量是分辨率）。
6. **性能行**：预提取 9.3-10.0ms @512（≤50ms 门，5 倍余量）/ 行走 carrier-hit
   0.002ms（≤5ms）/ edge map 冷 6.3ms（V1 基线不动）——三条全过。
7. **probe 源同源性**：evidence 副本 FollowEdges.swift 与主仓 diff = 仅 3 行
   HB 心跳打印（`steps % 512` 纯诊断，不动逻辑）；RidgeExtract.swift 与
   MaskEdgeKernels.metal 逐字节一致。

**M4-2-02（P2 512→1024）= armed 确认。**T6 未执行正确（门 = T5 PASS）。

## 红线机检节（验收方独立亲跑）

| 门 | 结果 |
|---|---|
| `git diff 64634dc..HEAD` 红线零 diff 面 | MaskEdgeKernels.metal / MaskOverlayHost.swift / LayerEditingState.swift / MaskToolbarView.swift / Localizable.xcstrings / PipeCache.swift **全空** |
| snap/snapTarget/readEdgeMap/edgeMap 函数体 | awk 抽取四函数体逐一 diff = **IDENTICAL ×4** |
| `stepPixels\|initialHeading\|strongestRingGradient` 全仓 grep | **0 命中** |
| `maxPoints` 全仓 grep | **仅 FollowEdges.swift**（内部常量 256 + 消费点；params 字段零命中 = M1） |
| Core 内 Steger/Taylor | 仅 1 处注释（「deliberately LIVES OUT」声明），**零代码** |
| `graph(from:high:)` 签名 | 无 strength 形参（E1 处方甲） |
| `makeEncoder(functionName:)` 批内增量 | **0**（20 处全存量）；零新 .metal 文件 |
| 滞回 raw 值门 | nmsCandidates `raw[idx] >= low` + hysteresis 种子 `raw[idx] >= high`；NMS 几何/质心剖面读平滑场（DECISIONS §1 T2 对实现一致） |
| junction 共享修复 | trace() 对已 visited junction 仍 append + noteJunction（RidgeExtract.swift:422-429）+ 整像素 skipPixels（:159-170） |
| T2 单提交原子性 | `3b3d7fc` 同批含换锚 + V1 删除 + golden（金与删同批，无中间红态提交） |
| 既有 8 法 | diff 逐 hunk 核：仅两处点数门实测重校（≥30→≥12 带 :91 调用点 stepPixels 摘除）+ 注释；几何断言逐字保留 |
| MaskRevisionTests 两法 | 批内 diff = 0 行；Layers 轮绿（lazy 路径回归钉） |
| carrier 注入缝 | 折键 `prefixHash ^ threshold.bitPattern` / LRU 8 显式 order / 计数器机检缝 / `field` 缓存零阈折（两 dict 键域分离亲证） |
| `.snap` 缺省维持（T6 门禁） | LayerEditingState `FollowEdgesParams(mode: .snap)` 亲证 + `mask_follow_strength_hint` 全仓 0 命中 + testSnapFrozenConstants 三景常量绿 |
| DECISIONS §0 前置四行 | T1 commit `9d7db87` 已含（先于 T2 动工，放行条件满足） |
| 登记（E2/L041） | Project.swift 两数组 + BUNDLE-MAP（LAYERS 19 / APP 4）随各自任务 commit |
| probe 产物零入主仓 | 批内 14 文件清单无 evidence 命中；主仓 status 仅无关 untracked 研究目录 |
| 不 push | origin/main..HEAD = 本批 5 + 前置 3 + 小修 1，全未推 |

## 九景矩阵与 walker golden 抽查

- 断言族实质在册：≤0.75px 真值距离 + ≥80% 覆盖（matrixAssertWalk 统一门）+
  噪声零链 + 双跑逐字节（graph/walk/injected==lazy 三面）+ snap 冻结三景常量
  （1e-6 精度）+ 空链降级三态 + fuse 恰 256（2000px 长脊）。
- T 分叉 differential：s0.2 上 A 支（min y ≤24）vs s0.8 停 junction（max x ≤33）
  ——followStrength 行走期语义钉死。
- Steger 对照腿：测试文件内 Taylor 位移式 vs 产线质心，≤0.5 证据带 + 实测
  print 行（DECISIONS §2）；Core 零 Steger 代码。

## 偏差六条处置审计（逐条 DECISIONS 对实现）

1. **结构张量取向**：θ = ½·atan2(2b, a−c) 外积平滑主取向 + 符号归一
   （orientationRadius=2）——数学正确（结构张量主特征向量），机理（脊顶梯度
   恒零）成立；NMS 轴与质心法向同源一致。✓
2. **滞回 raw 值门**：实现与 DECISIONS §1 T2 逐字一致（门读 raw、几何读平滑）；
   由 MaskRevisionTests 产线腿倒逼出的连续性修复在册。✓
3. **junction 整像素 + 链接器共享修复**：skipPixels 免细化 + visited-junction
   仍附着，两处理都在实现亲证。✓
4. **snap 对照共享贴边几何读法**：字面（首点距 snap 结果 ≤2px）在均匀脊不可
   满足（snapTarget tie 扫描序首中可沿脊偏 12px），收窄为双方各自贴真值 ≤2px
   ——保意图收窄、DECISIONS §1/§3 双录、测试注释说明。✓
5. **surface 活动阈值缺口（观察项）**：`edgeThreshold` 缺省 0.25 + 注释声明；
   非缺省阈值 lazy 路径 `RidgeGraph.high` 戳拒绝（行为正确不缓存）；
   stale-refusal 测试在册。✓
6. **testRestoreWinsOverDerive 间歇**：M4-1 挂账 #6 同族——验收轮独立复现 +
   孤儿清除因果闭环（见上），归 M4-1 所有。✓

## 验收小修

- `93beb87` `fix(m4-2-01): make the e1 t-fork assertion comment honest`
  （minor-1，注释诚实化，RidgeExtractTests 19/0/0 回归绿）。

## 移交 orchestrator

1. **omp 串行二次验收**（严禁并发）→ 结论追加本文件。
2. **M4-2-02 armed 执行裁决**（DIAG-1 三证齐备；执行令下达即可起）。
3. **M4-1 挂账 #6 修复批催办**：本 --all 轮再次发作（本会话独立复现）——
   每次 --all 第二轮必现，修复方向在案（Export 写腿 tmp 拷贝 + 双前清）。
4. 未 push 纪律维持；晨审呈报点沿 GOAL-STATE。

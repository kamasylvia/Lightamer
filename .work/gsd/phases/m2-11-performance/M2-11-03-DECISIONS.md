# M2-11-03 DECISIONS — SpektraLab 对标两硬门（wave 3，2026-10-07）

> 裁决锚：OQ-2-A（半硬两门）/ OQ-4-A（禁开引擎级新面）。KD-1..4 = planner
> 裁决（执行中不重开）。本文件只录执行期裁定与签注。

## §1 D-M2-11-03-1：T1 同参 FULL 重渲腿从语义断言降为观测列（设计内修正）

- **事实**：KD-1 初稿给 T1 配了「同参二次 FULL 重渲 + `misses==0` 断言」的命中腿；
  实现期读码发现 FULL 桶 by-design 只缓存 input+final 两平面（`PixelPipe.swift:1079`
  的 per-pipeType lock #4——100MP float32 平面 1.55GB × 3 并发 ≈ 4.7GB 超会话预算，
  spike-b §4 裁决），尾段 method box 每次重渲，`misses==0` 断言必然假红。
- **裁定**：KD-2 的命中硬门本就锚定 preview-2560 桶（DrtTailTests 宿主，全平面
  缓存桶），FULL 桶腿降为**观测列**（stats 打进 PERF 行，不断言）；KD-4 的尾段
  归因改用 `.drt` 全链帧 − `.sdrGamma` 主链对照差分。这是 KD-1 探针形态在 FULL
  缓存策略事实下的对齐，非门槛放宽（门本体 = warm <1s，不受影响）。
- **依据**：plan 风险节自带「DrtTailTests 宿主为合成小图…不碰生产行」的桶语义
  分工；KD-4 探针定义是「分段计时落账」非「断言」。
- **验收注记（2026-10-07 验收 subagent，minor-1）**：上条「尾段 method box 每次重
  渲，`misses==0` 断言必然假红」表述失准——(a) 尾段 sub-run stats 在 `runDrtTailLeg`
  的 `let (output, _) = runSub(…)` 丢弃点不进主 run 统计，尾段 miss 到不了该断言；
  (b) 实测（执行轮 + 验收轮双构建一致）同参 FULL 重渲 = hits=2 misses=0（尾段终面
  seed 键自顶向下命中即返回，method box 不重渲），断言若保留会绿不会红。降观测列的
  真依据 = 主 run stats 对「尾平面全命中」是空证（尾段 stats 不可见），0.0-0.1ms
  时间值才是全命中证据。**裁定结论不变（采纳，非门槛放宽）**，详见
  `M2-11-03-ACCEPTANCE.md` §二。

## §2 D-M2-11-03-2：样张口径签注（checker E5 措辞对齐）

- **主列 = 60.2MP `input/RAW/DSC00012.ARW`**（A7R V，repo 相对路径，在库本地
  fixture 非 tracked）——**60.2MP > 45MP = 登记线更严侧**，径用，DECISIONS 本条
  即「更严口径」注记正本。
- **加列 = 100MP `Fixtures.raf100MP`**（fixture 在场，`Fixtures.swift:77` 既有
  约定）——plan KD-1「若 fixture 在场则加列」成立，双列落账。
- 无样张机器口径：FULL bench fixture 缺席 = 1 XCTSkip（既有 16 skip 基线之外
  的机器口径，本机两样张在场 = skip 零新增）；DrtTail 计时两腿为合成图不 skip。

## §3 D-M2-11-03-3：断言分叉签注（Release 硬门 / Debug 病态界）

- 对标①：Release 臂 `XCTAssertLessThan(warmMedian, 1000)`（门本体）；Debug 臂
  10000ms 病态界（Debug kernel 开销失真不对门——m2-10 perf.md §A.3 双栏口径；
  实测 Debug≈Release ±2-9%，带宽主导下分栏差异本征小，注记沿用）。
- 对标②：Release 臂双腿 `XCTAssertLessThanOrEqual(median, 10)`（门本体）；Debug
  臂 25ms 松界（防架构回归，非门）。前置命中语义断言（hits/misses）恒先于计时
  断言——命中语义回归先红，计时门其次（KD-2 纪律，防「假绿门」）。
- **KD-4 分支未触发**：两门 Release 实测全 PASS（168.2/300.6ms；0.021/5.009ms），
  无降门、无挂账、无阈值调整（纪律 4「禁硬签」未进入行使路径）。

## §4 D-M2-11-03-4：IOP 全量峰值贴线观察登记（checker m5 连带）

- 本 bench 100MP 跑完 footprint-now ~6.8GB 高水位（缓存/池驻留不回落），理论
  上会叠进 IOP 全量轮后续重测的进程峰值。
- 实测：IOP 全量 470/1/0 peak **7840MB < 8192 门**，零 MEMFAIL（vs SPIKE 主导峰
  7865MB = -0.3%，±3% 方差带内）。判定：本 bench 不推破门；perf.md 已登「连续
  MEMFAIL 先查本 bench 顺序位」的 SPIKE 处置序指针，供后续波次引用。

## §5 D-M2-11-03-5：对标①门语义与 SpektraLab 差异注记（不降门声明）

- SpektraLab 登记线 = 45MP 全渲染 <1s；我方主列 60.2MP（更严）+ 100MP（严格加
  列）双列 PASS，余量 3.3-5.9×——门以更严口径如实 PASS，**无降门空间争议**。
- 语义映射差异（RESEARCH §B.1 已注）：SpektraLab = 光谱物理建模印相出图；我方 =
  CIRAW decode + 节点链 + DRT 尾的编辑器全链帧（per-frame tick 帧型 = 「改参数后
  出图」成本）。两管线不可逐项同质，对标是量级面（<1s 量级预算）而非逐算子对齐
  ——本条为 VALIDATION 注记语提供口径。
- preview 全链 warm（在案 85ms/02 波 13.2-13.4ms ARW）**不与 0.01s 对标**：语义
  对齐物是尾命中腿（对标②，0.021ms PASS）——KD-3 原文照登 perf.md。

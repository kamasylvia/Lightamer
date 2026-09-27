# Plan 08-3 — SUMMARY（focus stacking + 三模式堆栈降噪）

**完成**：2026-09-28。执行 = ZCode executor subagent worker（单班 T1→T6）。依赖 08-1（已闭环），
与 08-4/08-1 收尾车道共享工作树 + DerivedData（构建以重试轮消解 db 锁与并行 WIP 编译错，
全程未触碰他方文件；08-1/08-4 的提交面在 08-3 各任务构建窗口内自然就位）。

## 1. 任务表

| 任务 | 交付 | commit |
|---|---|---|
| T1 SML 度量 | `StackKernels.metal` focus_sml（modified Laplacian 3×3 ΣML²，half 存储）+ `FocusMeasure.swift`（服务自包含域单一提交点 + L014 drain 读回 + tenengrad additive 枚举位 + CPU float32 mirror）+ FocusStackTests T1 段 6 测试 | `be67d5b` |
| T2 金字塔融合 | `FocusStackMerge.swift`（5×5 box 软化 + 高斯/拉普拉斯金字塔 + 逐源顺序折叠 + NCC 自检）+ 融合测试 +6 | `5e3e845` |
| T3 三模式聚合 | `StackAggregate.swift`（average/median/sigma-clipped 带内算子 + bandStackBytes 常量锁）+ StackAggregateTests 数学段 6 测试 | `387fde3` |
| T4 服务分派/入口 | StackMergeService kind 分派（focus-stack + 三 stack kind 生产腿）+ StagedSet 行带暂存 + precheckStack 判据变体 + tag 词汇（_fstack/_stack_avg/_stack_med/_stack_sig）+ params 快照扩展 + Outcome.warnings + App menu/dialog/Picker/接线 + zh 13 键 + 服务段测试 +4 | `9e389e2` |
| T5 perf/golden | SML 与 sigma N=8 E2E 探针（只记不设门）+ perf.md 08-3 节对账 + golden 汇总复跑 | `aa1b01b` |
| T6 收口 | 全套回归 + 本 SUMMARY + DECISIONS + TODO/PROGRESS 翻账 | 本提交 |

新增测试 **24**（FocusStackTests 13 + StackAggregateTests 11）。

## 2. 回归账

- 基线：08-1 收口轮 + 08-2/08-4 并行增量（1636 时代基线 → 并行交付后 HEAD 实测为准）。
- 各任务边界单套件：FocusStackTests 6→12→13 绿；StackAggregateTests 6→9→10→11 绿，0 fail。
- 终轮全 suite：**1752/11skip/0fail**（609.3s，私有日志副本 `/tmp/la-083-direct-tests.log` 复跑；
  08-3 新增 +24）。首轮全套在共享日志 `/tmp/la-direct-tests.log` 被并行车道中途覆写
  （08-2 已载条款；总行 "1 failure" 为覆写伪影，可见段无任何失败用例）——私有路径复跑干净。
- 共享树条款：并行 08-4 WIP（EditorMTKView/EDRControlView/EDRHeadroomMonitor 等）曾致 4 轮
  构建失败（db 锁 + 其编译中间态），均以等待重试消解，非 08-3 面缺陷；一次 `tuist generate`
  后 `-XCTest` 过滤 Executed 0 为新测试文件未 generate 所致（自查自纠）。

## 3. 08-1 交接面消费清单（禁二遍实现——零重写实证）

| 交接面 | 消费方式 |
|---|---|
| `StackMergeService` actor/队列/cancel/进度/失败分型 | 原样复用（enqueue kind 参数化；stepTotal 加 kind 感知重载，HDR 公式逐字未动） |
| `MTBAlign` 对齐 | 三条新腿共用的 runStackPrecheckAndAlignment 直接调用 pyramid/findShift，零改 |
| `BandStreamer` 行带几何 + float TIFF 写 | bands()/writeFloatTIFF() 原样（聚合/融合遍带驱动） |
| `ExifPrecheck` 预检 | **additive**：新增 precheckStack(captures/reference-candidate) 变体函数，HDR 路径零改 |
| `ProvenanceReplay`/SidecarProvenance | 零改消费（kind 映射 + fileHash + 同参 replay；MergeParams 只加 optional 字段） |
| `ExportNamer` 防撞 | 原样（kind→defaultTag 词汇表见 D-08-3-T4-2） |
| `StackRenderFace` 解码渲染 | 原样（每源单次全幅瞬态渲染 → 暂存） |

**additive diff 边界声明**（08-1 已验收文件的 08-3 触碰面）：
1. `StackMergeService.swift`：runProductionMerge 头部 guard 改为 kind switch（原 HDR 体整体
   移入 runHDRLeg，逐行未动）；`StackMergeWork` 加 device/mergeQueue 两字段（focus 腿 SML 提交
   所需，构造点仅 execute()）；`MergeParams` 加 4 个 optional 快照字段；`MergeKind` 加
   provenanceKind 映射；`StackMergeOutcome` 加 warnings（默认 []）；stepTotal 加 kind 重载。
2. `ExifPrecheck.swift`：纯 additive（precheckStack 两个新静态函数）。
3. `SidecarProvenance`/`ProvenanceReplay`/`BandStreamer`/`MTBAlign`/`GhostMaskWriter`：零触碰。

## 4. AC 自检（逐条）

- [x] **SML 度量 kernel**：ML = |2f−f(x−1)−f(x+1)| + |2f−f(y−1)−f(y+1)|（Rec2020 luma），
      SML = 3×3 ΣML²（clamp-first 窗走位两侧一致）；L014 drain（waitUntilCompleted 于产出 CB，
      无 drain 负例 = 旧图残留确定性复现，D-08-3-T1-3）；half 存储（往返容差断言 1%）；
      tenengrad 枚举位存在且抛 notImplemented（无第二算子数学）。
- [x] **金字塔融合**：quality 5×5 box 软化（P5 软权形状）+ 5 级参数化 + 行带流式
      （map 只留行带：bandWorkingSetBytes O(band) 断言 < 单幅全帧驻留）+ 清晰区归属双向
      MAE 0.0016（P5 ≈0.004 量级，门 <0.01）+ NCC<0.9 警告不阻断（scale-drift fixture 实测）。
- [x] **三模式聚合**：average 默认 / median（偶数取双中位均值）/ sigma-clipped（population σ、
      k=2.5）行带单遍（bandStackBytes = 286,457,856 B ≈286MB @N=8·256·11656 精确断言）+
      解析 golden ×3（精确均值/中位/剔后重均值）+ 星野 fixture 卫星轨迹拒绝（残差 <0.02，
      平均对照可见拖线）+ N=3 退化注记（population σ 下 √(N−1)=1.41 < k，服务层警告）。
- [x] **服务分派**：四 kind 端到端走真实生产腿（产物落位 + provenance kind + params 快照 +
      tag 防撞递增 `_stack_avg-1.tif`）+ 预检变体判据表（D-08-3-T4-4：光圈严 vs 快门/ISO 漂移
      仅警告；HDR 等快门拒绝对照）+ 重放幂等（ProvenanceReplay 零改消费）+ menu 模式 Picker
      （coordinator seam 走查测试）。
- [x] **SC#2 字面闭环**：合成位移轨 fixture（96×72 纹理，known (3,-2) shift）MTB 精确命中
      alignment ["full","full"] + 融合产物保深解码存活（clean combined output；结构鬼影由清晰区
      MAE 断言覆盖）。
- [x] **perf.md**：focus/sigma 全程 + SML 0.15s/源 + sigma 4s 4P 参考对账（只记不设门；
      SML 偏差 >2× 归因 = 上传腿，v2 直渲 MTLTexture 缝）。
- [x] **纪律**：每任务独立提交（6 commits，只 add 申报文件）+ 边界查 config 开关
      （auto=true/paused=false ×6）+ 不 push + fixture 全部本地盘临时目录（禁 UNITEK）+
      SUMMARY/DECISIONS 落盘。

## 5. Manual-Only / 移交

- 100MP N=8 真实 RAW focus/sigma 全幅秒表（内存与时长超 CI 面）→ Phase 15 候补。
- menu/dialog 真机观感（对焦轨/星野真样张走查）→ 随 Phase 8 verify-work 观感轮。
- perf.md 遗留（08-1 移交的 Release 口径 / lut3d 列）维持归 08-5 收口，08-3 未触碰。

## 6. 证据指针

- 测试：`Tests/LightamerTests/FocusStackTests.swift`（13）/ `StackAggregateTests.swift`（11）
- perf：`.work/gsd/phases/08-hdr-stacking-effects/perf.md` 08-3 节
- 决策：`08-3-DECISIONS.md`（D-08-3-T1-1..T4-4 + T2-2/T2-3 执行期决策）

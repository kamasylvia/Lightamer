---
phase: 8
plan: "08-3"
title: "focus stacking + 三模式堆栈降噪（W2，复用 08-1 对齐段与服务骨架）：SML 焦点度量 kernel（modified Laplacian 3×3 ΣML² + L014 fence 读回）+ enfuse 式 quality-weighted 拉普拉斯金字塔融合（行带流式，map 只留行带）+ average/median/sigma-clipped 三模式行带聚合 + 对焦轨 NCC 残差自检 + tag/_fstack/_stack 命名 + provenance kind 消费 + App menu 模式分派"
wave: 2
depends_on: ["08-1"]
autonomous: true
requirements: [IOP-HDR-02, IOP-HDR-03]
files_modified:
  - LightamerCore/Sources/Stack/FocusMeasure.swift              # 新建：SML kernel 封装（GPU 生成 + L014 fence drain() 读回 + tenengrad additive 枚举位）；P5 参考 1.5ns/px → 0.15s/源@100MP
  - LightamerCore/Sources/Stack/FocusStackMerge.swift           # 新建：quality map 5×5 box 软化 + 5 级拉普拉斯金字塔 quality-weighted 融合（层数参数化）+ 行带流式（map 只留行带）+ NCC<0.9 放大率漂移警告
  - LightamerCore/Sources/Stack/StackAggregate.swift            # 新建：average（默认）/median/sigma-clipped 行带聚合（行带内 N 值栈 N=8·256 行 RGB ≈286MB → 带内排序/σ 剔除单遍完成；136.6ns/px 参考）
  - LightamerCore/Sources/Stack/StackMergeService.swift         # 扩：kind 分派 focus-stack/stack-average/stack-median/stack-sigma 末段接入 + focus/stack EXIF 预检变体 + tag 派生（_fstack/_stack + _avg/_med/_sig）+ 等价产物 provenance hash 复用提示
  - App/Sources/Lightamer/UI/SessionBrowserView.swift      # menu 扩展：「焦点堆栈…」/「堆栈降噪…」（模式 Picker：average/median/sigma）复用 08-1 dialog/进度面
  - Tests/LightamerTests/FocusStackTests.swift                  # 新建：SML 分离度（59× fixture）/清晰区归属 MAE≈0.004/NCC 警告/fence 读回
  - Tests/LightamerTests/StackAggregateTests.swift              # 新建：三模式数学 golden/sigma-clip 星野 fixture 离群拒绝/N=8 行带内存常量/tag 防撞
  - .work/gsd/phases/08-hdr-stacking-effects/perf.md            # focus/sigma 全程秒表 + 对账（research §12：sigma N=8 ≈ 解码主导 + 聚合 4s）
  - .work/gsd/phases/08-hdr-stacking-effects/08-3-SUMMARY.md
  - .work/gsd/phases/08-hdr-stacking-effects/08-3-DECISIONS.md
  - Resources/Localizable.xcstrings  # L025 zh/en 同批
  - TODO.md                                                     # 08-3 勾选
  - LESSONS.md                                                  # 如踩坑
---

# Plan 08-3 — focus stacking + 三模式堆栈降噪（W2，依赖 08-1）

> 背景：IOP-HDR-02（focus stacking）与 IOP-HDR-03（average/median stacking）与 HDR merge 共享
> 08-1 的对齐段（MTBAlign）、服务骨架（StackMergeService actor/队列/进度/取消/失败分型）、落位与
> provenance——本 plan **只换末段**（D-08-CONTEXT-3「同一合并服务的聚合算子变体」）。焦点度量 =
> modified Laplacian SML（P5 实测 sharp/blurred 比 59× 分离度充分）；融合 = enfuse 式 quality-weighted
> 拉普拉斯金字塔（soft 权重无硬深度边界——回避深度图 inpaint 全部复杂度，DL 深度图 v2 插拔位
> D-08-CONTEXT-2）。堆栈降噪 = average（默认，√N 增益物理期望不变）/median（运动鲁棒）/
> sigma-clipped（星野）三模式。
> 内部任务序刚性：T1 度量 → T2 融合 → T3 聚合 → T4 服务分派/入口 → T5 golden/内存 → T6 收口。

## read_first

1. `.work/gsd/phases/08-hdr-stacking-effects/08-RESEARCH.md`——§5（RQ-08-5 终形：SML 公式 + 金字塔
   5 级 + 5×5 box 软化 + 对焦轨缩放差 NCC<0.9 残差自检 + **map 以行带流式融合、只留行带**——N=8
   half 全驻 1.6GB 否决线）、§6（行带流式骨架——median/sigma-clipped 带内 N 值栈 286MB 单遍完成，
   无需两遍/滑动窗口）、§12（服务形态 + sigma N=8 全程预算 ≈ 解码主导 + 聚合 4s）、§0 P5 行
   （SML 1.5ns/px、59×、软权重 MAE≈0.004）、§16 R3（16GB 内存硬约束）
2. `.work/gsd/phases/08-hdr-stacking-effects/08-CONTEXT.md`——D-08-CONTEXT-2（SML + 金字塔融合；
   DL 深度图 v2 pluggable）、D-08-CONTEXT-3（三模式同骨架 + 算子枚举 additive）、D-08-CONTEXT-11
   （产物/provenance 同 08-1）、验证与红线节（合成 fixture 数值 golden）
3. `.work/gsd/phases/08-hdr-stacking-effects/08-1-PLAN.md` 全文——T1（服务骨架/队列/失败分型）、
   T2（MTBAlign 接口——**直接复用不做二遍实现**）、T3（BandStreamer 行带形状——本 plan 同骨架换
   聚合算子）、T5/T6（落位/provenance 消费面）；08-1-SUMMARY（交接面以 SUMMARY 实报为准）
4. `LightamerCore/Sources/Stack/`（08-1 产物）——`StackMergeService.swift` kind 分派位/
   `MTBAlign.swift` 对齐接口/`BandStreamer.swift` 行带迭代器/`ExifPrecheck.swift` 预检入口
5. `LightamerCore/Sources/Stack/GhostMaskWriter.swift` 同目录先例（PNG 落盘 + StableHash 惯例——
   本 plan 无 mask 需求，仅 API 风格对位）
6. `LightamerCore/Sources/Metal/MetalContext.swift:524`——`makeRoutedCommandBuffer()` 唯一路由点
   （SML kernel 提交 + 读回走 L014 fence drain()——07 AI `AIMaskInput` 先例）
7. `App/Sources/Lightamer/UI/SessionBrowserView.swift`——08-1 T5 落的 menu/dialog/进度面（本
   plan 扩两个 mode 入口）
8. `LESSONS.md` L009（fixture 禁 UNITEK）/ L013（decimal String）/ L014（fence 读回）/ L020（内容级
   断言）/ L031（唯一路由点）+ `AGENTS.md`（Phase 执行模型 + 暂停机制）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 本任务申报文件）；`caffeinate -dis` 包裹一切构建。
- **单测命令** = `Scripts/test-direct.sh '<Class>'`；**判据 = Executed 计数行 + failures 行**，
  Executed 0 = 判据失败。
- **每任务边界检查 `.work/config.toml [gsd]` 开关（`auto`/`paused`）**——commit 后、下一任务前。
- **不 push**；**构建勿加 `-derivedDataPath`**；**每新建源/测试文件后跑 `tuist generate`**（11-03
  教训；本 plan 文件落 08-1 已建 `LightamerCore/Sources/Stack/` 目录内，新文件仍须 generate）。
- **回归基线 = 1636/10skip/0fail（13-3 后基线）+ 08-1 新增**（以 08-1-SUMMARY 终值为准）；每任务
  全套 suite 绿；本 plan 收尾轮 = 上基线 + 新增，0 fail。**在案 flake 归因条款**：
  `LayerE2ERoundTripTests` / `ToneEqualPerf` 负载型 flake 若现，隔离 ×3 归因单列入 SUMMARY，不计违约。
- **L031 路由红线（本 plan Metal 面适用）**：SML/金字塔/软化一切 GPU 提交走
  `MetalContext.makeRoutedCommandBuffer()`（`MetalContext.swift:524`）唯一路由获取点；读回一律
  L014 fence（`drain()` 模式——quality map 读回是本 plan 高频路径，async completed() 有读早竞态
  L031 教训③）；StackMergeService 专属队列自包含域纪律同 08-1。
- **内存硬约束（R3）**：focus map **不以全幅全驻任何 N 源集合**——行带流式融合（map 只留行带）；
  median/sigma 聚合行带内 N 值栈上界断言（N=8·256 行 RGB ≈286MB）。任何实现把 N×100MP 平面全驻
  = 直接违反，测试钉常量。
- **复用红线**：MTB 对齐/服务骨架/落位/provenance **禁二遍实现**——发现 08-1 交接面缺口（接口不
  够用）时停手登记 DECISIONS + 回注 orchestrator，不得在 08-3 内私改 08-1 已验收文件语义（ additive
  扩展须在 SUMMARY 声明 diff 边界）。
- **perf 口径 = 只记不设门**：SML 0.15s/源、sigma-clip 136.6ns/px（13.9s 单线程 / ~4.0s 4P @100MP
  N=8）、全程 ≈ 解码主导 + 聚合 4s 作参考基准落 perf.md 对账；偏差 >2× 归因注记。
- **fixture 禁 UNITEK 盘**（L009）；合成 focus 轨/星野 fixture 落本地盘临时目录，禁入仓。
- RESEARCH/CONTEXT 未覆盖细节（金字塔层数默认 5 的参数化拼法、sigma 剔除 σ 估计式细节、NCC 窗
  大小、menu 文案）标注**执行期决策**入 `08-3-DECISIONS.md`，不臆造。

## Tasks

### T1 SML 焦点度量 kernel + L014 fence 读回

- **action**
  1. 新建 `LightamerCore/Sources/Stack/FocusMeasure.swift`：modified Laplacian 幅值和度量——
     `ML = |2f(x)−f(x−1)−f(x+1)| + |2f(x)−f(y−1)−f(y+1)|`，SML = 3×3 窗 ΣML²，成 per-source
     quality map（单通道；**half 存**——质量图无需 float32 精度，research §5.4）。
  2. GPU 生成（compute kernel 经 `makeRoutedCommandBuffer()` 唯一路由点提交）；读回走 L014 fence
     （`drain()` 模式——07 AI `AIMaskInput` 先例形状）；参考 1.5ns/px → 0.15s/源@100MP（perf.md
     对账）。
  3. `tenengrad` 作 additive 备选枚举位（度量算子可换，D-08-CONTEXT-2 Reversibility——v1 只实现
     SML，枚举 case + dispatch 缝落位不实现第二算子数学）。
- **证据**：`FocusStackTests`——真 defocus 代理 fixture（sharp/blurred 对）SML 比 ≈59× 量级断言；
  fence 读回正确性（异步竞态负例：不 drain 时偶发旧面——注入延迟验证 drain 必要性，证明性测试
  形态入 DECISIONS）；half 精度往返误差容差断言。

### T2 金字塔融合（行带流式 + NCC 自检）

- **action**
  1. 新建 `LightamerCore/Sources/Stack/FocusStackMerge.swift`：quality map 先 5×5 box 软化（P5 软
     权重 PASS 形状）→ 拉普拉斯金字塔 **5 级** quality-weighted 融合（层数参数化 additive 旋钮；
     1024px 边界过渡带经验值——执行期决策复核）。
  2. **行带流式**（R3 硬约束）：quality map 生成即流式消费，**map 只留行带**（不落地 N×全幅
     half 面）；融合输出与 08-1 同 BandStreamer 骨架写 float TIFF。
  3. **对焦轨缩放差自检**（research §5.3）：对齐后对重叠带算归一化互相关，NCC < 0.9 → 警告
     「源间放大率差异大，边缘可能重影」，**照常融合**（软权重对深度边界小错位天然宽容）；
     homography/光流 = v2 缝（dispatch 位落 DECISIONS 注记）。
- **证据**：`FocusStackTests`——**清晰区归属**：合成对焦轨 fixture（已知清晰区平面）融合输出
  双向 MAE ≈ 0.004 量级断言（P5 PASS 形状）；行带常量内存断言（N=8 无全幅 map 驻留——分配器
  探针或 footprint 上界）；NCC<0.9 警告触发 + 照常融合不断言阻断。

### T3 average/median/sigma-clipped 三模式聚合（行带单遍）

- **action**
  1. 新建 `LightamerCore/Sources/Stack/StackAggregate.swift`：三模式 = 同一行带迭代器换聚合算子——
     ① **average**（默认；线性域算术平均，√N 降噪物理期望不变）；② **median**（带内 N 值栈排序
     取中位）；③ **sigma-clipped**（带内均值/σ → 剔除 |dev|>k·σ → 重均值；σ 估计式执行期决策）。
     行带内 N 值栈（N=8、256 行、RGB ≈ 286MB）→ 带内完成，**单遍、无两遍/滑动窗口**（research
     §6 定形）；参考 136.6ns/px → 13.9s 单线程 / ~4.0s 4P @100MP N=8（perf.md 对账）。
  2. 聚合模式进 `StackMergeService` kind 分派（stack-average/stack-median/stack-sigma）；对齐段
     复用 MTBAlign（对齐对三模式同义可用——运动场景 median 对残余错位天然鲁棒，警告语义同 §2.3
     降级标注）。
- **证据**：`StackAggregateTests`——三模式解析 golden（已知值 fixture：average 精确均值/median
  精确中位/sigma 剔除后精确重均值）；**sigma-clip 星野 fixture**（含卫星轨迹/热噪离群源）离群
  拒绝断言（离群贡献 < 容差）；N 值栈内存常量断言；N=3 退化行为注记（sigma 统计弱——文档 +
  警告文案，同 R6）。

### T4 服务分派 + EXIF 预检变体 + tag 命名 + provenance kind + App menu

- **action**
  1. `StackMergeService` 扩 kind 分派：focus-stack / stack-average / stack-median / stack-sigma
     四末段接入（服务接口 N→1 抽象位不动——D-08-CONTEXT-1 Reversibility 兑现：换末段即新 kind）。
  2. **EXIF 预检变体**：focus/stack 预检走 ExifPrecheck 同面换判据——机身/镜头/焦距严格；快门/
     ISO **不要求** bracket 式互异（对焦轨/堆栈快门常同）；光圈严格（景深一致性前提）。判据差异
     表落 DECISIONS。
  3. **tag 命名**（08-1 ExportNamer 防撞惯例复用）：`<base>_fstack.tif`（focus）/`<base>_stack.tif`
     + 可选 `_avg`/`_med`/`_sig` 后缀（research §3.3；具体拼法执行期决策钉 DECISIONS）。
  4. **provenance kind 消费**：四 kind 写 v4 provenance（algorithm.params 快照含模式专属参数：
     金字塔层数/σ 剔除 k/NCC 结果）；重合并重放同参等价（08-1 ProvenanceReplay 零改消费）。
  5. `SessionBrowserView` menu 扩「焦点堆栈…」/「堆栈降噪…」（模式 Picker 三选；dialog/进度/取消
     面复用 08-1 T5 形状）。
- **证据**：`StackAggregateTests` 服务段——四 kind 端到端（合成 fixture N=3）产物落位 + provenance
  kind 字段断言 + tag 防撞递增；预检变体矩阵（异光圈 focus 拒绝 vs HDR override 语义对位）；menu
  分派 App 层走查。

### T5 golden 汇总 + 内存常量 + perf 对账

- **action**
  1. **golden 汇总轮**：T1/T2/T3 断言全量复跑 + 交叉 fixture（对焦轨 × 星野混合源）——clean
     combined output with correct alignment（SC#2 字面）：合成位移轨 fixture 对齐命中（复用 08-1
     MTB 测试形状断言）+ 融合输出无结构鬼影（清晰区归属 MAE 断言覆盖）。
  2. **内存常量全套**：focus 行带 + N 值栈 + 累积面上界三断言汇编为一组「N=8 @100MP footprint
  门」（只记不设门，超界归因——R3 硬约束的回归锁形态入 DECISIONS）。
  3. **perf.md 对账**：focus 全程秒表（N=8）+ sigma 全程秒表 vs research §12 预算表（解码主导 +
  聚合 4s 参考）；SML 0.15s/源对账。
- **证据**：两类测试全绿；perf.md focus/sigma 两节落档（对账列 + 归因注记如有）。

### T6 全量回归 + SUMMARY + DECISIONS

- **action**：全 suite 终轮（基线 = 08-1 收尾轮 + 本 plan 新增，0 fail；flake 条款见纪律节）；
  Resources/Localizable.xcstrings  # L025 zh/en 同批
  - TODO.md 08-3 勾选；`08-3-SUMMARY.md`（任务表/commit 表/证据/08-1 交接面消费清单——有无 additive
  扩展如实声明）；`08-3-DECISIONS.md`（σ 估计式、NCC 窗大小、tag 拼法、预检判据差异表、金字塔
  层数默认复核、v2 光流/homography 插拔位注记、其余执行期决策）；新教训候选评估入 LESSONS。
- **证据**：测试计数（08-1 终值 → N，0 fail）；SUMMARY + DECISIONS 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| SML 度量 | 59× 分离度 / fence 读回 / half 容差 | `Scripts/test-direct.sh 'FocusStackTests'` |
| 融合 | 清晰区 MAE≈0.004 / 行带常量 / NCC 警告不阻断 | `Scripts/test-direct.sh 'FocusStackTests'`（融合段） |
| 三模式 | 解析 golden ×3 / sigma 星野离群拒绝 / N 值栈常量 | `Scripts/test-direct.sh 'StackAggregateTests'` |
| 服务/入口 | 四 kind 端到端 / provenance / tag 防撞 / 预检变体 | `Scripts/test-direct.sh 'StackAggregateTests'`（服务段） |
| perf | focus/sigma 全程 + SML 对账入 perf.md | 查 perf.md |
| 回归 | 全 suite 0 fail（08-1 终值+新增） | `caffeinate -dis Scripts/test-direct.sh`（全套） |

## 验收标准（Acceptance）

- [ ] SML 度量 kernel：modified Laplacian 3×3 ΣML² 终式 + L014 fence 读回（drain()）+ half 存储 +
      tenengrad 枚举位（不实现第二算子）
- [ ] 金字塔融合：quality 5×5 软化 + 5 级参数化 + **行带流式（map 只留行带，无全幅 N 源驻留）** +
      清晰区归属双向 MAE≈0.004 量级 + NCC<0.9 警告照常融合
- [ ] 三模式聚合：average 默认 / median / sigma-clipped 行带单遍（N 值栈 ≈286MB 上界常量断言）+
      解析 golden ×3 + sigma 星野 fixture 离群拒绝
- [ ] 服务分派：四 kind 末段接入（08-1 骨架零重写——SUMMARY 声明 diff 边界）+ 预检变体判据表 +
      `_fstack`/`_stack` tag 防撞 + provenance kind/params 快照 + 重放幂等 + menu 模式 Picker
- [ ] SC#2 字面闭环：合成位移轨对齐命中（复用 MTB 断言形状）+ clean combined output 数值 golden
- [ ] perf.md：focus/sigma 全程 + SML 0.15s/源 + sigma 4s 4P 参考对账（只记不设门）
- [ ] 全 suite 0 fail（08-1 终值+新增）；每任务独立提交 + 边界查 config 开关；不 push；fixture 禁
      UNITEK；SUMMARY + DECISIONS 落盘

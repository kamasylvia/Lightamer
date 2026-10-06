# M2-11 CONTEXT — Performance 专项 + closeout 决策草案

> Phase：M2-11（M2 最后 phase）。日期：2026-10-06。起草 = discuss/research subagent
> （M2-10 VALIDATION 签核后续接点指令）。
> 输入：`REQUIREMENTS.md` §M2PERF（:99-100）+ 原 PERF 族（:613-620）、ROADMAP M2-11 行
> （含 2026-10-02 SpektraLab 对标注记）、`phases/m2-10-ai-library/M2-10-07-SUMMARY.md`
> §M2-11 交接节、各 phase perf.md、`.work/GOAL-STATE.md` 续接点、`.work/LESSONS.md`。
> 审计正本 = 同目录 `RESEARCH-NOTES.md`（PERF-01..07 逐条现状 + SpektraLab 测法 +
> closeout 组织 + flaky 并案 + 待新测清单）。
> **C 档第 1 停生效**：本文件定稿即停——OQ-1..8 交用户裁决后才进 plan。

## Scope

- 原 Phase 15 并入（ROADMAP 注记"Phase 15 并入 M2-11"）：PERF-01..07 按新架构重校 +
  既有 Phase 15 预约义务清算（PERF-06 60fps 门本体 / 档 B Release 复核 / flaky 清算批
  / denoise 缺口 / L055 脚本件）。
- closeout：M2PERF-02 = M2 全族 SC 终验 + VALIDATION 签核（兼 M2 收口正本，OQ-8）。
- M2-10 交接四件全部有承接位（RESEARCH §C.4 对账表）：60fps 复验 / MCP 零改动机检 /
  AI 面 GUI 走查并案 / flaky 三案并案。

## Non-Goals

- 不做新功能；不重构渲染链（除 OQ-7 限定的 nlmeans 预览降载一处改码候选）。
- 100MP@×2 增强行带流式（E3）不入本 phase（OQ-4 维持 Maintenance）。
- MCP 面 / semantic_search 零新增（OQ-12-A 签认维持，只做零 diff 机检）。
- 二进制体积对标（SpektraLab 32MB）不设——内置 AI 模型 ≈193MB 为 by-design。

## Decisions (drafts)

### D-M2-11-CONTEXT-1 — 目录与产物形态

phase 目录 = `phases/m2-11-performance/`（本文件 + `RESEARCH-NOTES.md`；后续 PLAN-N/
SUMMARY-N/VALIDATION 同址；Instruments 产物归 `profile/` 子目录）。命名沿 M2 惯例
（`M2-11-<N>-<TYPE>.md`）。

### D-M2-11-CONTEXT-2 — 方法学：research 零跑，执行面定向新测

本阶段全部数字为**誊录在案账本值**（RESEARCH §A 七表，逐条带锚点）。新测 11 项全部
归 plan 执行面（RESEARCH §F 清单），门数字遵守既有纪律：L009 SSD fixture、三轮中位、
Debug/Release 分栏、Release 直启重签惯例（D-09-04-D9）、bench 门随全套 MEMFAIL 机检。

### D-M2-11-CONTEXT-3 — PERF 重述总纲（细节随 OQ）

原 PERF-01..07 定义四处置：①**重述**（PERF-01 链面、PERF-02 内存口径、PERF-05 交互点
定义——各见 OQ-5/1/6）；②**原样维持**（PERF-03/04/06 定义不动，补数字）；③**已
Delivered**（PERF-07 只复核不复燃）；④**SpektraLab 对标两行并入 M2PERF-01 重述文本**
（测法 = RESEARCH §B，硬门档位随 OQ-2）。重述落点 = REQUIREMENTS M2PERF-01 文本随
plan 批改写（原 PERF 族 :613-620 保持历史不动，重述只写 M2PERF-01 行内注记）。

### D-M2-11-CONTEXT-4 — flaky 清算批并案形态

五件并案（三案 + L055 + Executed-1 单数 quirk，事实清单 = RESEARCH §D）。改码深度
分层：确定性缺陷件（#3 缩略图断言硬化 / #4 L055 解析器 / #5 单数兼容）默认全收；
环境型/负载型两案（#1 ANE / #2 LayerE2E）默认台账收口 + 可观测性增强、不改测试逻辑
（深度随 OQ-3）。脚本两件修复后须有自证：构造 crash 日志 fixture / 单数日志 fixture
各一（脚本为 bash，测试 = fixture 回放断言）。

### D-M2-11-CONTEXT-5 — closeout 组织（细节 OQ-8）

M2-11-VALIDATION 兼 M2 收口正本：M2PERF-01/02 SC 对账 + 全 `--all` 终轮（批准制 +
L055 核读纪律）+ M2 族机械扫（uncheck 残留 = 零）+ 挂账总汇编（V2/Maintenance 移交
单一清单，含 M2-10 挂账十项落位）+ 翻账批（REQUIREMENTS/ROADMAP/STATE/TODO/GOAL-STATE
同批）。GUI 验收轮一轮四义（RESEARCH §C.3）。

### D-M2-11-CONTEXT-6 — MCP 零改动机检（交接件 2 承接）

closeout 批复跑红线域零 diff 机检：`git diff --name-only <M2-10 基点>..HEAD
App/Sources/Lightamer/MCP/ LightamerCore/Sources/MCP/` 零命中（M2-10 签核批同款）；
`semantic_search` defer 维持，M2-11 不开新验收面。

## Open Questions（用户裁决点；推荐 = A）

### OQ-1 PERF-02 内存 3GB 口径修订

3GB 门按哪个口径立？

- **A（推荐）三分口径**：①编辑器 GUI 交互稳态工作集 ≤3GB（PREVIEW 桶 + 常驻显示平面
  + LRU 预算内，Instruments 实测落账）②FULL 管线瞬态 = TilingPlan 窗口有界断言维持
  （不设绝对数）③测试宿主 8G 运行门不变（M2-4-0 SPIKE 已证 <3G 宿主侧数学不可达）。
  理由：三分后每口径都可测、与既有资产（SPIKE/enforceBudget/MemoryBudgetTests）零冲突。
- B 字面 3GB 硬门（FULL 100MP + N 层管线足迹）：需细拆 ~12+ bundle 才可测（SPIKE 结论
  D5 前提证伪案），成本高且与 by-design 重测面冲突。
- C 3GB 降为记录档不设门：放弃 GUI 侧内存约束，16GB 机器 swap 前科（2026-09-27 暂停
  事件）下不建议。

### OQ-2 SpektraLab 对标线是否立硬 SC

- **A（推荐）半硬**：①45MP 级 FULL 全渲染 **warm <1s 立硬门**（ROADMAP 登记线原文）；
  ②尾平面命中重渲 **≤10ms 立硬门**（"重印 0.01s"的语义对齐物，RESEARCH §B.2）；③
  preview 全链 warm 85ms 作记录档 + 语义差异注记（不与 0.01s 对标）。理由：两硬门均
  有可测路径且 ② 可达性高；① 可达性未知（FULL 带宽主导）——若 plan 期实测 >1s，按
  D-05-08-T6-1 先例做杠杆分解后再裁（降门/挂账如实，不硬签）。
- B 全记录档：测了落账不设门——对标登记失去清算力，M2PERF-01 "决战" 字面落空。
- C 全硬门（含 preview 全链 ≤10ms）：已知 85ms 不达，等于自带缺口签核，不可取。

### OQ-3 flaky 清算三案 + 脚本两件取舍

- **A（推荐）确定件全修 + 环境件观测**：#3 缩略图队列断言硬化 / #4 L055 解析器 /
  #5 单数 quirk 三件确定性改码全收；#1 ANE 案 = 加宿主 ANE 态自检日志（`ANECCompile`
  失败签名落账）不改测试逻辑；#2 LayerE2E = 复现律统计落账。理由：环境型归因五波
  台账维持（M2-10-VALIDATION 裁决），强行改码无靶；确定件修复即消。
- B 五件全修：含 ANE 重试协议（skip/retry 改码）+ LayerE2E 竞态修复尝试——环境型
  无靶风险 + 负载型未定位，可能制造新 flake 面。
- C 只收脚本两件：三案全维持台账——缩略图两连击下「环境型」归因已趋弱
  （M2-10-05-ACCEPTANCE O-1 原话），不硬化则 M2 终验轮噪声持续。

### OQ-4 100MP@×2 增强行带流式（E3）是否本 phase 收

- **A（推荐）不收，维持 Maintenance**：M2-11 = 计量 + closeout；`c573087` typed 门
  （>285M 输出拒绝 + 诚实文案）已兜底；M2-10-06 M-1 / M2AI-09 注记两处均挂 Maintenance
  在案。触发条件 = 真实 100MP@×2 增强需求出现。
- B 收入本 phase（tile 直写流水线化）：新引擎工作，改 AI worker 增强腿 + 重开内存
  验收面，与 closeout 定位冲突且挤占 PERF 决战带宽。

### OQ-5 PERF-01 链面定义（"满 iop 集"重述）

- **A（推荐）M2 默认面**：Develop + 1 Grade（默认 look：+1.5EV/+15/1.3）+ DRT（SDR
  record）= 静态 warm 门对象；拖动门保持两档（color 七件 / denoise 单件，既有
  testPhase5DragGateTwoChains 形态）。100MP 真样张 preview-2560。理由：与 Alcedo
  克隆架构和 M2-1 feature-flag 禁用裁决一致；dt 39 iop 全 enabled 与 M2 默认面矛盾。
- B dt 39 iop 全 enabled 复活：与 M2-1 禁用矩阵冲突，需先翻 M2-1 裁决。
- C 最小链（Develop + DRT）：门太松，失去"满链"语义。

### OQ-6 PERF-05 可交互定义 + 渐进显示

- **A（推荐）warm 首帧交互点**：定义 = open→PREVIEW 缩略/fit 桶首帧上屏 ≤500ms
  （warm，进程内二次）；RAW9 CoreML 一次性编译冷 2.62s 单列落账不入门；渐进显示
  （低清先出→高清替换）立观察项不强制实现。理由：组件证据（decode warm 0.11s/
  100MP@512 0.166s）达标概率高；冷门会把一次性编译计进用户体验门，语义失真。
- B 冷门 ≤500ms：首启必不达 → 被迫实现渐进显示 + 预热策略，范围膨胀。
- C 字面维持「后台解码 + 渐进显示」强制实现渐进上屏：2560 桶 warm ~2.08s 现状下
  渐进显示确有实感价值，但属新功能开发——若用户重视首开体验可选此项（工作量 +
  1 plan 任务）。

### OQ-7 denoise 链 85.7ms 缺口处置（60fps 复验交接的正杠杆）

- **A（推荐）bounded 降载尝试**：本 phase 内一次 nlmeans 预览降载加深（K clamp/
  window/decimate 档位调整，杠杆点 `PixelPipe.swift:800` + 降载档位测试
  `testNLMeansPreviewDowngradeTiers` 在位），复测拖动链；仍不达 = 如实挂账 V2 并在
  VALIDATION 注记「denoise 拖动降档预览」备选语义。理由：57 趟降载已兑现 7.5×
  （05 perf），剩余成本本征；一次 bounded 尝试成本低、闭环体面。
- B 只复验落账：零改码，85.7ms 缺口原样移交——M2PERF-01 "决战" 对该缺口无交代。
- C 决战到底（含 NLMeans kernel 重写/时域复用）：超出 perf 收口 phase 范围，风险高。

### OQ-8 closeout 形态

- **A（推荐）M2-11-VALIDATION 兼 M2 收口正本**：单一文档 + 全 `--all` 终轮 + M2 族
  机械扫 + 挂账总汇编（M2-10 挂账十项在此落位：Release digest 回填/命中质量走查/
  真批量队列/衍生徽标/DeepLink 限制/worker 冷启动 → Maintenance/V2 清单）。不另跑
  gsd-complete-milestone。理由：M2-1..M2-10 各 phase VALIDATION 已签核，收口事实 =
  汇总 + 终验，避免双状态源。
- B 另跑完整 milestone-close 流程：仪式重叠，产出双正本。

## 裁决后动作

1. OQ-1..8 落签 → CONTEXT 定稿（未采纳项注记用户裁决）→ 进 plan（plan 拆分建议：
   P1 计量批（§F #1-7 bench 面）/ P2 GUI 走查批（§F #8-10 + AI 走查 + L057）/
   P3 flaky+脚本清算批（D-4）/ P4 Instruments+内存 profile / P5 closeout 终验批）。
2. 本文件 + RESEARCH-NOTES 一笔 docs commit 入库（`.work/gsd/` 真路径，不 push）。

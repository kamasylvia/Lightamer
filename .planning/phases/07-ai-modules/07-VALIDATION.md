---
phase: 7
slug: ai-modules
status: validated
nyquist_compliant: true
wave_0_complete: true
created: 2026-09-24
validated: 2026-09-24
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> 体例对齐 04/05/06-VALIDATION。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit）+ AI 变体验证三轨（确定性门逐字节 + 合成语义门方向断言 + 自研 float64 parity——L017 分流，无 dt parity 轨） |
| **Config file** | `Project.swift` (Tuist) — LightamerTests target |
| **Quick run command** | `Scripts/test-direct.sh`（直启宿主零弹窗；L019b 三加固） |
| **Full suite command** | `Scripts/test-direct.sh`（签核终轮 = touch Tests + build-for-testing 重编复跑） |
| **Estimated runtime** | ~207 seconds（845 tests；AI/层/golden/parity/蒙版/面板/perf） |

---

## Sampling Rate

- **After every task commit:** quick unit tests（test-direct.sh 全套）
- **After every plan wave:** full suite
- **Before phase sign-off:** full suite must be green（0 fail）
- **Max feedback latency:** ~207 seconds

---

## Per-Task Verification Map

> 4 needs（AI-01/05/06/07）→ 3 plans（07-1..07-3）。验证范式 = AI 变体（07-RESEARCH §6）：
> AI 输出不可逐字节 golden——确定性门（同 device 两次推理恒等）+ 合成语义门（IoU/方向
> 断言）+ 自研 float64 参考轨（skinSmooth）。

| Task ID | Plan | Wave | Requirement | Test Type | Evidence（测试/文件/数字） | Status |
|---------|------|------|-------------|-----------|---------------------------|--------|
| 07-1-T1..T5 | 07-1 | 1 | AI-01（双后端 + 确定性门）+ bake 几何 | unit+确定性门+benchmark | 零漂移 SDK 复核（D-07-1-T1-1）+ `.work/07/perf.md` 基线（warm 层 A 15-16ms / 层 B accurate 85-126ms ≪1s）；确定性门 6 测试（层 A gpuPinned 逐字节恒等进程内+跨进程）；语义门 10 测试（IoU ≥0.9/背景 ≤0.1/subset 双向/noSubject typed）；几何 6/6（双线性权重 + Y 翻转 + 羽化剖面 + 默认 0 byte-identical）；round-trip 9/9（AI 平面 uint16 恒等 + 同 maskID 覆盖 hash 翻转缓存记账）；全套 812/5skip/0fail | ✅ green |
| 07-2-T1..T5 | 07-2 | 2 | AI-05（skinSmooth parity + SkinRegionLocator） | golden(float64)+unit | V50Order 66.5 非 dt 行首例（14/14 含零移动钉 strip-to-93）；恒等三元组逐字节（a=0 blit / mask nil==全一 / 平场 DC-1）；**float64 parity 6 case × 6 fixture 双闸 <1e-5（低频腿 7.2e-7）**；SkinRegionGeometryTests 8（hull−保护区⊗personSeg/yaw 门/多脸 union，纯 Swift 不跑模型）+ 真模型腿 skip-with-reason；轨 B 中性插链零增量逐字节；tiling 抽查 <1e-4；manifest skinSmooth 节（L017 分流）；全套 830/6skip/0fail | ✅ green |
| 07-3-T1+T2 | 07-3 | 3 | AI-06（UI 接入面：AI 组 + 第 4 编辑模式） | unit | `AIMaskEditing` 单通道（恰 1 stackSnapshot + PNG 落盘 + landing form）`LayerUIWiringTests.testAIMaskCommitOneSnapshotUndoAndRefineOverwrite`（⌘Z 恰 1 + 逐级 hash 还原 + 同文件新 hash 精修覆盖）+ `.testAIMaskSourceFileIdentity` + `.testLayerBEntryGateStates`（三态跃迁矩阵）+ `.testSegmentRouteMutexExhaustive`（mask>liquify>retouch>segment>crop 穷举）+ `.testSegmentSessionBudgetAndYFlipWiring`（13/11 满禁点 + Y 翻转向量）；全套 835/6skip/0fail（830→835） | ✅ green |
| 07-3-T3 | 07-3 | 3 | AI-05 UI（skinSmooth 面板第 25 席 + 定位皮肤） | unit | PanelWiringTests 60/60：`testSkinSmoothPanelDispatch` + `testSkinSmoothLayerScopeDragCommitsOnceAndUndoRestores`（D-H1 恰 1 commit + 归零还原）+ `testSkinLocateCommitWritesMaskSlotOneCommit`（ai-skin 身份 mask 槽 1 commit）+ `testSkinSmoothEnabledCompositeDiffersFromDisabled`（内容级低幅条纹板） | ✅ green |
| 07-3-T4（E2E） | 07-3 | 3 | AI-07（五条覆盖路径非黑箱）+ sidecar 零升级 | unit(E2E) | `AIMaskEditPathsTests` 6/6 内容级（L020）：drawn 差集修补方向 / parametric ⊓ 收紧 / invert 逐字节往返 / 羽化重 bake（hash 翻转 + 边界列均值下降）/ refine 同 maskID 覆盖 + MISS-then-HIT 缓存记账 / **sidecar schema 零升级**（移除 mask 子树逐字节还原 + 无 quality/seed/refine 键可编码） | ✅ green |
| 07-3-T4（GUI） | 07-3 | 3 | GUI 红线（L021：真 RAW + 量化 + PLAYBOOK） | GUI+真机 | FINDINGS「Plan 07-3 T4 AI 集成 GUI 验收轮」（2026-09-24 16:15-17:05 真机解锁屏，7 截图）：层 A 真实 CR3 推理 bake `ai-subject-<uuid>.png` + **overlay ΔR 量化（06-03 口径）= 变化像素 10.31% / 黄染新增 8.97% / mean |Δ|luma 13.0** + GUI 级 ⌘Z 恰 1（sidecar position 1→0）+ 层 B 三态走查（prompt zh 弹窗/declined 持久化/置灰引导）+ zh 标签首屏全量（L025）；新缺陷 GUI-19/GUI-20 登记 | ✅ green |
| 07-3-T5 | 07-3 | 3 | Phase 7 终签核 | all | 本文件 + 07-DISCUSSION-LOG SC#1-5 终节 + REQUIREMENTS AI-01/05/06/07 翻账 + manifest「Phase 7 golden 完整性总账」节 + perf.md 收口（SC#5 门 = warm 裁定）+ Phase 8 移交清单 + 终轮全套 **845/6skip/0fail**（touch + build-for-testing 重编复跑） | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Per-Requirement Annotations（需求口径注记）

| Requirement | 注记 |
|---|---|
| **AI-01** | 双层共存（D-07-CONTEXT-1）：层 A `VNGenerateForegroundInstanceMaskRequest` 离线兜底 + 层 B `GenerateIterativeSegmentationRequest` tap 精修（首次一次性模型下载，assetStatus 三态门控）；iterative **tap/box** 已接，**scribble/lasso = v1 后**（D-07-CONTEXT-4，种子枚举升级缝预留）；设备 pin beta 现实（CPU 不在 supported 集/层 B pin 即崩）→ 生产 default 不 pin、测试层 A gpuPinned（D-07-1-T1-2）；层 A `generateScaledMask` beta 双重损坏 → 标签合成腿（512 级 + 双线性上采样，升级缝保留）。 |
| **AI-05** | 磨皮数学 v1 = 两频高斯分离 + raised-cosine 阈值衰减（D-07-CONTEXT-6）；**多尺度小波 / bilateral 边缘感知变体 = v2**（Variant enum 位预留）；定位皮肤 = landmarks hull − 五官保护区 ⊗ personSeg（纯 Swift 几何可单测）；yaw 门 45° typed warning 非静默；pore-level 人眼目检 = Manual-Only 挂账（样张缺含人脸帧）。 |
| **AI-06** | **raster 烘焙 = v1 唯一忠实通道**（D-07-CONTEXT-3——Vision mask 是像素非参数曲线）；parametric 语义曲线预设（肤色 hz 曲线）= v2（REQUIREMENTS 行注记已落）；AI 参数不进 sidecar（schema 零升级断言常驻）。 |
| **AI-07** | 非黑箱三面全交付（07-RESEARCH §4）：生成即 bake → 与手画蒙版完全相同的编辑/合成/持久化世界；五条覆盖路径（drawn 修补/parametric ⊓/invert/羽化重 bake/refine 重生成）内容级 E2E 断言常驻（AIMaskEditPathsTests）；同 maskID 覆盖重 bake = 版本策略（D-07-CONTEXT-5，无孤儿文件；考古由 history stackSnapshot 承载）。 |
| **SC#5 判定** | 按修订版措辞核对（D-07-CONTEXT-1）：层 A 离线可用（OS 内置模型）+ 层 B 首次使用需模型下载（assetStatus 门控 + 层 A fallback）；延迟门 = **warm 路径裁定**（层 A 15-16ms / 层 B accurate 85-126ms，全 ≪1s；cold = 进程内模型首编译一次性，后台 Task + spinner 承接——D-07-1-T1-3）；缓存 = bake 持久化 + 既有 mask 缓存链（refine MISS/HIT 记账实证）。 |
| **层 B 资产供给（GUI-20）** | dev-signed 构建下载无错误返回但 assetStatus 恒 notReady——macOS 27 beta 资产供给对 development 签名不放行（与 07-1 测试宿主 entitlement 同根）；三态 UI 行为诚实（引导态保持/无静默假就绪/层 A 全程可用）；**Developer ID / 正式分发签名复验 = v1 后观察项**（不阻塞签核——服务逻辑 + 状态机矩阵全钉）。 |

---

## Wave 0 Requirements

- [x] benchmark 基线先行（07-1 T1 首任务——SC#5 门按实测分布定 = warm 裁定，D-07-1-T1-3）
- [x] SDK swiftinterface 复核先行（07-1 T1——零漂移结论 D-07-1-T1-1，beta 漂移风险解除）
- [x] 确定性门前提钉死（层 A gpuPinned 合成小图 + 层 B default 探针逐字节——CPU pin 现实不可达，typed 拒绝路径锚）

---

## Manual-Only Verifications（L011 口径挂账汇总）

> 07-1/07-2/07-3 三轮 Manual-Only 逐行汇总；真模型腿 GUI 复验在 07-3 T4 真机走查
> 的实际闭环范围如实登记（层 A 真机已闭环；层 B ready 跃迁受 GUI-20 阻断；人像目检
> 待样张）。

| Behavior | Requirement | Why Manual | 状态 |
|----------|-------------|------------|------|
| 层 A 主体蒙版真机端到端（真实 CR3 推理 → bake → overlay） | AI-01/06 | 真实推理 + 真机渲染判据 | ✅ 07-3 T4 GUI 轮（IMG_4276.CR3：bake 落盘 + ΔR 10.31%/8.97% 量化 + ⌘Z 恰 1） |
| 层 B 下载三态真机走查（prompt/declined/引导态） | AI-01（D-07-CONTEXT-1） | 真机 UI 流 | ✅ 07-3 T4 GUI 轮（zh 弹窗 + declined 持久化 + 置灰引导 AX 枚举）；**ready 态跃迁 = GUI-20 阻断**（beta 资产供给，待 Developer ID 签名复验） |
| tap-to-segment 手感（点选/⌥排点/⇧框 + 点计数满禁点） | AI-01（D-07-CONTEXT-4） | 视口手势（CGEvent/AX 均不可驱动）+ 手感判据 | ⏳ pending-manual（数据腿全钉：预算/互斥/Y 翻转 5 测试；ready 入口被 GUI-20 阻断，待资产可下载后真机复验） |
| 磨皮 pore-level 目检 + 「定位皮肤」真人像走查 | AI-05 | 人眼质量判据 + 需含人脸样张 | ⏳ pending-manual（现有 3 张样张均无人脸；parity <1e-5 + 三元组 + 启用态差异已钉；与 ColorChecker 补拍同批——TODO 登记） |
| instance 勾选浮层（多主体照片） | AI-01 | 需多主体样张 | ⏳ pending-manual（子集语义 07-1 双向断言已钉；单主体直接 bake 路径已真机实证——酒瓶未触发浮层） |
| 保护区显示 toggle 视觉 | AI-05 | 视觉判据 | ✅ 同 overlay 通道（raster 染色 ΔR 量化达标，FINDINGS 07-3） |
| skinSmooth 面板入层链（真机 sidecar 证据） | AI-05 | 真机 UI 流 | ✅ 07-3 T4 GUI 轮（layer.chain=[skinSmooth] + history「添加模块到图层」；面板行显示 = GUI-19 挂 UI 打磨轮） |

---

## PERF 记账（摘要，正本 .work/07/perf.md）

- **SC#5 交互延迟门（warm 裁定，D-07-1-T1-3）**：GFX 102MP 实测 warm median——层 A
  15-16ms / 层 B accurate 85-126ms / personSeg accurate 42-44ms / faceLandmarks
  4.7-6.3ms，全 ≪1s 达标；cold = 进程内模型首编译（层 A 最高 5.5s，一次性，后台
  Task + spinner 承接）。
- **层 B 模型下载**：`downloadAssets()` 实测 3.3-11.4ms → ready（测试环境，模型极小
  或系统级预暂存）；真机 dev-signed 态见 GUI-20 注记。
- **bake 内存**：双线性上采样 grow-only 分配（fast 档 256×256 → 解码帧）；balanced/
  accurate 直接产全分辨率 mask（11648×8736@102MP）无需上采样——峰值内存 = 单平面
  r32Float + uint16 PNG 编码，量级 ≪ 3GB 工作集预算；Instrument 专项记账并入 Phase 8+
  perf plan（本轮无超预算信号）。

---

## Sign-Off Checklist

- [x] 全部 3 plans 执行完成（07-1/07-2/07-3），SUMMARY 逐 plan 落盘
- [x] SC#1-5 逐条证据指针落 07-DISCUSSION-LOG 终节（缺口注记零静默：scribble/lasso = D-07-CONTEXT-4 v1 后 / parametric 预设 = D-07-CONTEXT-3 v2 / 多频磨皮 = D-07-CONTEXT-6 v2 / GUI-20 层 B ready 跃迁待签名复验 / Manual-Only 7 行）
- [x] golden 完整性总账（manifest「Phase 7 golden 完整性总账」节：AI 阶段无落盘 blob——确定性门/语义门/float64 参考轨全常驻测试锚 + skinSmooth 节引用）
- [x] sidecar schema 零升级（AI 参数不落盘：`testSidecarSchemaZeroUpgradeAIParamsNeverPersist` 逐字节断言 + GUI 真机 `.lra` 对比）
- [x] 轨 B 全链回归绿（07-2 中性插链零增量逐字节；Phase 3+4+5+6 全模块基线保持）
- [x] SC#5 门记账（.work/07/perf.md：warm 裁定 + cold 一次性 + 缓存链；GUI-20 beta 资产现实注记）
- [x] GUI 验收轮汇总（07-3 T4 一轮 7 截图 + ΔR 量化 + FINDINGS 07-3 节）；Manual-Only 汇总表（本文件，7 行——2 行已闭环 5 行挂账）
- [x] AI-01/05/06/07 需求注记行（本文件 + REQUIREMENTS.md 翻账 Delivered）
- [x] Phase 8 移交清单（07-DISCUSSION-LOG 终节：RasterMaskRef/层栈 API/缓存面/skinSmooth 66.5 槽位/AIMaskService 复用面/Vision 推理基建 + 07-1 遗留对表）
- [x] `status: validated` + `nyquist_compliant: true`；TODO/GOAL-STATE/REQUIREMENTS 同批更新（§3.1 commit guard）
- [x] 终轮全 suite 0 fail（**845/6skip/0fail**；touch Tests + build-for-testing 重编复跑防增量吞更新；基线 830→845，+15 = 07-3 三测试文件）

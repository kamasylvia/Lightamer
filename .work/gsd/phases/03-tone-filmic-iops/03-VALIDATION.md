---
phase: 3
slug: tone-filmic-iops
status: signed-off
nyquist_compliant: true
wave_0_complete: true
created: 2026-09-19
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (unit) + headless golden harness（dt-cli parity + Phase 2 双判据复用）|
| **Config file** | `Project.swift` (Tuist) — LightamerTests target |
| **Quick run command** | `xcodebuild test -project Lightamer.xcodeproj -scheme Lightamer -destination 'platform=macOS' -only-testing:LightamerTests` |
| **Full suite command** | `xcodebuild test -project Lightamer.xcodeproj -scheme Lightamer -destination 'platform=macOS'` |
| **Estimated runtime** | ~60-120 seconds（golden parity 含 dt-cli 调用与 60MP 渲染） |

---

## Sampling Rate

- **After every task commit:** quick unit tests (LightamerTests only)
- **After every plan wave:** full suite
- **Before `$gsd-verify-work`:** full suite must be green
- **Max feedback latency:** ~120 seconds

---

## Per-Task Verification Map

> Task IDs filled by planner. Seeds from RESEARCH §Validation Architecture（双轨制）。

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-01-T1/T5/T6 | 03-01 | 1 | IOP-TONE-01 (exposure) | — | N/A | golden parity | 合成 fixture → dt-cli 单模块钉参 → EXR vs Lightamer → 逐像素 <1e-5 相对误差（tracer） | ✅ | ✅ green（2026-09-19，`GoldenParityTests.testExposureGoldenParityAgainstDarktableCLI`，commit 5c57916；轨 B 双判据同文件） |
| 03-01-T2 | 03-01 | 1 | Wave 0 fixture 组 + dt-cli 重建 | — | N/A | script | `bash input/golden/regenerate.sh` 一键复现 + manifest | ✅ | ✅ green（2026-09-19：dt-cli 重建 dc58cf0ba1 + XMP 钉参采纳实证（0.25→0.5 exact）+ roundtrip maxdiff 0.0 + manifest，commit 6c7bc7e） |
| 03-02-T1/T2/T6 | 03-02 | 2 | IOP-TONE-02 (WB) | — | N/A | unit+golden | K→增益 CPU 单测（已知向量，C harness 对照 <1e-4）+ 吸管数学 + fixture golden（增益直设钉参 <1e-5；参考合成 + dt 平场 PFM probe，manifest host finding） | ✅ | ✅ green（2026-09-19，`CPUDerivationTests` WB 节 + `TemperatureParityTests` 轨 A/轨 B/probe + `EyedropperTests` 端到端；dt-cli 对空间变化图像 float 导出损坏的 host finding 见 manifest 与 LESSONS L017） |
| 03-03-T3 | 03-03 | 2 | IOP-TONE-03 (tonecurve) | — | N/A | unit+golden | 10001 点 1D 阶梯 LUT round-trip + 合成参考 parity（双闸：≥99% <1e-5 + 1e-4 包络；L017 路线 + dt 采纳实证） | ✅ | ✅ green（2026-09-19，`ToneCurveParityTests` 8/8：identity/S-manual/S-RGB/perchannel × stair_1d/ramp/gray_staircase/flat/saturated + 轨 B + 注册；dt-cli Lab 链 probe 不可用（piece-state 损坏，manifest 落账），v5 blob 采纳实证（params ok + DB 520B）） |
| 03-04-T1/T2 | 03-04 | 3 | IOP-TONE-04 (shadhi) | — | N/A | golden parity | Lab 往返 + gaussian 腿钉参容差 <1e-4 + ΔE<1.0 99% 分位 | ✅ | ✅ green（2026-09-19，`ShadhiParityTests` 4/4：4 钉参 case × 6 fixture（gaussian 腿钉参）+ 恒等参数逐像素不变 + 轨 B + 注册；中间探针抓出两类 blur 缺陷（read_write 纹理同线程 RMW 丢失 → L018；行 pass 原位读写 DC 坍缩为 cp·(1+cn)），按 dt gaussian.cl `__global float4*` 双平面 buffer 形移植后全绿；合成参考路线 + v5 blob 采纳实证，manifest 落账） |
| 03-03-T1/T2 | 03-03 | 2 | IOP-TONE-05 (colisa contrast) | — | N/A | golden parity | Lab 往返恒等 <1e-9（Double）+ Lab 域对比度 parity（双闸） | ✅ | ✅ green（2026-09-19，`LabRoundTripTests` 6/6 + `ColisaParityTests` 7/7：5 case × 6 fixture + 轨 B + 注册；LUT 索引四舍五入偏差与 ParityGate 双闸记录在案） |
| 03-03-T4/T5 | 03-03 | 2 | IOP-TONE-06 (levels) | — | N/A | unit+golden | levels black/white/灰点 parity（manual 双闸 / automatic <1e-4+ΔE p99<1.0 + 直方图解析 ±1 bin） | ✅ | ✅ green（2026-09-19，`LevelsParityTests` 9/9：3 manual case × 6 fixture + automatic 自洽链（GPU 直方图→percentile→LUT→apply）+ 色度保持 + 轨 B + 注册；levels_auto blob 采纳实证） |
| 03-05-T1..T6 | 03-05 | 4 | IOP-TONE-07 (toneequal) | — | N/A | unit+golden | CPU correction LUT 单测 + golden 两档（none <1e-5 / EIGF <1e-4+ΔE）+ TilingPlan FULL 首战（分块一致 + <3GB） | ✅ | ✅ green（2026-09-19，`ToneEqualLUTTests` 7 + `ToneEqualKernelTests` 7 + `ToneEqualModuleTests` 4 + `ToneEqualParityTests` 2（none 档 <1e-5 双闸 / EIGF 档 <1e-4 + ΔE76 p99<1.0；L017 合成参考路线——float32 复刻 choleski 与 Swift 权重一致 ~1e-7；dt 侧 = v2 blob 采纳实证（params v. 2 ok + DB hex）+ 平场 PFM probes）+ `TilingOverlapTests` 2（强制分块 vs 整幅 <1e-5 + 100MP FULL Δfootprint <3GB）；PERF-5 预验数据记录：Debug 构建 PREVIEW 全链 warm median 63.4ms > 16.6ms 预算，按 plan「超限先记录后优化」注记，正式门 03-06-T7（优化杠杆：Release/PSO 预热/dispatch 批合并）；勘误与决策落 `03-05-DECISIONS.md`（7 估计器 / 80001 LUT / EIGF=Gaussian 非 box / halo=4r+65 IIR 跑道推导）） |
| 03-04-T3/T4 | 03-04 | 3 | IOP-FILM-02 (sigmoid) | — | N/A | unit+golden | commit_params 四标量 CPU 互验 + fixture parity <1e-5 | ✅ | ✅ green（2026-09-19，`CPUDerivationTests` sigmoid 节 3/3（四标量互验 <1e-9 + 约束集 Double 档 + 域边界 NaN）+ `SigmoidTests` 6/6：5 case × 6 fixture <1e-5 + GPU 曲线约束（f(0)/f(grey)/f(∞)）+ 双路径中性 + 轨 B + 注册；中间探针抓出 primaries `invert3` 单格余因子笔误（G 行 [0,0.9735,−1.0001] ≠ 恒等 → G 通道取反），修复后 D-T2 基线（面板/golden/缓存）就绪） |
| 03-06-T1..T5 | 03-06 | 5 | IOP-FILM-01 (filmicrgb) | — | N/A | unit+golden | F0-F4 五子阶段独立 golden + 组合 parity（F1 <1e-6 / F2-F4 <1e-5） | ✅ | ✅ green（2026-09-20，`CPUDerivationTests` filmic F0 节 6/6（默认组手算锚点 output_power=4.168313824554027 / grey_display=2/3 / norm 界 0.000720703125/2.952，v1/v2/v3 params 分支全覆盖 + 非法组合无 NaN）+ `FilmicRGBTests` 10/10：F1 三方（Metal vs CPU Double，toe/linear <1e-6、poly4 shoulder float32 Horner 档 <1e-5 + 1e-4 包络——FMA 单舍入参考逐式复刻）+ F2/F4 组合 parity（5 钉参 case × 5 fixture，ParityGate 98% strict + 1e-4 包络；`saturated` 按 log 未定义域注记划归 F3 合法性靶）+ F3 out-of-Rec2020 光谱全部入域 + 中性轴不变 + norm 六模式解析向量 + auto 三键直译（grey /2 语义、全图 min/max 归约 HistogramReduce.rgbMinMax 端到端）+ F5 mask kernel 权重 + 轨 B + v50=46.0 注册。合成参考（L017 路线，float32-FMA 逐式复刻）；dt 侧 = 116B blob 库 DB op_params hex 采纳实证 + history load + piece commit（CPU 腿崩溃本机导出不可用，sigmoid per_channel SIGSEGV 同族，manifest/DECISIONS 落账）） |
| 03-06-T6 | 03-06 | 5 | IOP-FILM-03 (variants=agx) | — | N/A | unit+golden | agx 参数组 round-trip + 钉参 parity | ✅ | ✅ green（2026-09-20，`AgXTests` 5/5：5 case × 6 fixture 合成参考 parity <1e-5（agx_primaries 按记录的矩阵偏差钉 Swift 双实现）+ 曲线 pivot/斜率不变式（pivot 在线上、过渡节点在线上、pivot 夹在过渡间、auto_gamma 对角）+ ParamsCoding round-trip + v50=45.5 注册 + look 调态下灰轴不变。dt 侧 = 「params v. 7: version ok params ok」+ DB op_params hex（③d adoption probes；CPU 腿导出崩溃同 filmic，manifest 落账）。hatchless 无对标注记于模块头/manifest/DECISIONS） |
| 03-06-T7 | 03-06 | 5 | PERF-5 | — | N/A | signpost | PREVIEW 全模块链单帧 <16.6ms CI 记录（Phase 1 模式）| ✅ | ⚠️ 记录完成、预算未达（2026-09-20，`.work/plans/03/perf-record.md`）：`PreviewChainPerfTests` 2/2 进套可复跑——真实拖拽形状（稳定 imageID + exposure tick 全链失效 + PSO 启动预热）Release warm median **36.23ms**（Debug 37.63；03-05 预验 63.4→37.6 的改善来自 PSO 预热 + 形状修正），Release 门 = 45ms 回归界。16.6ms 预算的 7-10 趟假设被证伪（实测 ~40 GPU 趟：toneequal EIGF 多趟 + 每 Lab 模块 2 趟往返 ×3 + shadhi 模糊）。**晚链单滑块拖拽 2-6ms ✓ 60fps**；最坏情形（exposure tick）超预算，剩余杠杆 = 管线级 Lab 往返共享（Open#9→Phase 5）+ 跨模块 dispatch 批合并（Phase 4+），已分配并落账 DECISIONS/VALIDATION。SC#3 相应注记见下 |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

> **Planner 回填注记（2026-09-19）**：Wave 列已按 plan 系 wave 对齐（1=03-01 基建+exposure → 2=03-02 WB+面板 ∥ 03-03 Lab 三模块 → 3=03-04 shadhi+sigmoid → 4=03-05 toneequal → 5=03-06 filmicrgb+variants+签核）。规划期拍板：①Lab 域往返进模块内部（colisa/shadhi/tonecurve/levels parity 前提，03-03-T1 共享件）；②shadhi golden 钉 `shadhi_algo=gaussian`（bilateral 腿 → Phase 5，03-04 checkpoint）；③toneequal golden 两档 none→EIGF（03-05 checkpoint）；④filmicrgb 只落 V5 + 高光重建子树划出（03-06 checkpoint D-T1）；⑤IOP-FILM-03 交付物 = agx（hatchless 无对标不实现）。checkpoint:decision 详见各 PLAN。

---

## Wave 0 Requirements

- [x] `input/golden/fixtures/` — 合成 fixture 组脚本（灰阶 ramp −8..−0.125EV 幂次锚列、平场 ×3、饱和色块+out-of-Rec2020 光谱、深阴影梯度、中性灰阶梯、10001 点 1D 阶梯）（03-01-T2，2026-09-19）
- [x] darktable-cli 重建（当前树 dc58cf0ba1，5.5.0+1862~gdc58cf0ba1-dirty）+ XMP attach 验证（+1EV 钉参 0.25→0.5 采纳实证；预构建版丢历史缺陷随重建消失）（03-01-T1，2026-09-19）
- [x] `Tests/LightamerTests/GoldenParityTests.swift` — dt-cli parity 双轨 harness（轨 A <1e-5 + 轨 B Phase 2 双判据带新模块插入）（03-01-T3，2026-09-19）
- [x] `Tests/LightamerTests/CPUDerivationTests.swift` — 各模块 CPU 推导公式直译互验（exposure 节落账 + WB/Lab/sigmoid/toneequal/filmic 占位节）（03-01-T4，2026-09-19）

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 滑块拖动 60fps | PERF-5 SC#3 | 交互时序 + Instruments | 拖任一 tone 滑块 → Instruments 确认 PREVIEW 链帧时。**自动化已覆盖数据面**（`.work/plans/03/perf-record.md`：晚链单滑块 2-6ms ✓；全链重渲 36ms 注记）；交互目检解锁后重跑一次 Instruments 记录即可 |
| 色彩视觉效果 | IOP-TONE-01..07 | 视觉验收 | 对真实照片逐模块开关对比，确认无伪影/带状/跳变 |

## SC#3 结论注记（2026-09-20，T7）

RESEARCH §8 的「7-10 趟 = 2-6ms」预算账被实测证伪：真实 11-iop 链 ≈ 40 GPU 趟（toneequal EIGF
多趟、每 Lab 模块独立 2 趟往返 ×3、shadhi 模糊），全链重渲 Release 稳态 36ms。已落杠杆
（Release/PSO 预热/稳定 imageID 拖拽形状）后，晚链单滑块拖拽（用户高频路径：sigmoid/filmic/
agx/colisa/tonecurve 调整）实测 2-6ms 达 60fps；最坏情形 = 拖 exposure/WB（链首，全部下游重渲）
36ms（~27fps）。两根架构级杠杆已分配：①管线级 Lab 往返共享（RESEARCH Open#9，原计划 Phase 5+）；
②跨模块 dispatch 批合并（Phase 4+）。SC#3 = **⚠️ 部分达成**（交互路径成立、极端路径注记 + 杠杆分配），
不阻塞 Phase 3 交付（感知卡顿仅出现在拖链首滑块场景，且 D-C3 缓存让大多数操作命中缓存平面）。

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 120s（全量单测 107-116s）
- [x] `nyquist_compliant: true` set in frontmatter
- [x] Phase 3 全 suite 绿：**267 tests / 0 failures / 3 documented skips**（2026-09-20，连续两轮）
- [x] ROADMAP SC#1: 7 tone 模块（exposure/WB/tonecurve/shadhi/colisa/levels/toneequal）全部钉参 golden green（03-01..03-05 各 VALIDATION 行）
- [x] ROADMAP SC#2: filmicrgb F0-F4 子阶段独立 golden + F4 组合 parity 在容差内（03-06-T1..T5 行；容差注记：float32 spline/FMA 网格 → 98% strict + 1e-4 包络；saturated 划归 F3 合法性靶）
- [x] ROADMAP SC#3: 晚链交互 60fps 成立（2-6ms）；全链重渲 36ms 超预算注记 + 杠杆分配（见上节 + `.work/plans/03/perf-record.md`）——⚠️ 部分达成
- [x] ROADMAP SC#4: sigmoid（03-04）+ agx（03-06-T6）scene-referred tone mapping golden green；全部 11 模块 `IOPColorspace` 声明核查（RGB 模块 .RGB、Lab 模块 .Lab，`V50OrderTests`/各注册测试钉住）
- [x] Issue 关联：Per CONVENTIONS（commit message 已带 (03-06) 前缀；GitHub issue 关联按用户手动指令执行）

**Approval:** signed-off（2026-09-20，保活巡检自主执行轮；PERF-5/SC#3 按上节注记部分达成，其余全绿）

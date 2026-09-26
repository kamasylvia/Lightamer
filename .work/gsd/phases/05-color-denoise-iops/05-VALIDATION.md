---
phase: 5
slug: color-denoise-iops
status: validated
nyquist_compliant: true
wave_0_complete: true
created: 2026-09-21
validated: 2026-09-23
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (unit) + golden/parity harness（gen_fixtures float64 双轨） |
| **Config file** | `Project.swift` (Tuist) — LightamerTests target |
| **Quick run command** | `Scripts/test-direct.sh`（直启宿主零弹窗；L019b）|
| **Full suite command** | `xcodebuild test -project Lightamer.xcodeproj -scheme Lightamer -destination 'platform=macOS' -only-testing:LightamerTests`（签核终轮用；日常用 test-direct.sh） |
| **Estimated runtime** | ~170-200 seconds（609 tests；ROI/golden/parity/面板/perf） |

---

## Sampling Rate

- **After every task commit:** quick unit tests（test-direct.sh 全套 <3 分钟）
- **After every plan wave:** full suite
- **Before phase sign-off:** full suite must be green（0 fail）
- **Max feedback latency:** ~200 seconds

---

## Per-Task Verification Map

> 11 needs → 11 dt 模块 + 2 基建 plan。golden 双轨（L017）：合成 float64 参考主轨 + dt 三证据（blob 采纳 / `--d params` ok / 平场 probe）。

| Task ID | Plan | Wave | Requirement | Test Type | Evidence（测试/文件/数字） | Status |
|---------|------|------|-------------|-----------|---------------------------|--------|
| 05-01-T1..T7 | 05-01 | 1 | 基建（剖面/iscale/L021 审计/加噪器/BilateralGrid3D） | unit | NoiseProfileStoreTests 手算向量；L021DoubleScaleAuditTests 6/6；TileNegotiationRegressionTests 加固；BilateralGrid3DTests 64×64 <1e-4；加噪器 variance 实测 vs a·I+b | ✅ green |
| 05-02-T1..T5 | 05-02 | 2 | IOP-COLOR-01 | golden+unit+GUI | ColorBalanceRGBParityTests 轨 A + dt 采纳 + 恒等门 + seed disabled D1 + 面板三测 + GUI 走查（FINDINGS 05-02 节） | ✅ green |
| 05-03-T1..T5(+F1-F6) | 05-03 | 2 | IOP-COLOR-02/04 + colorcontrast | golden+unit+GUI | ChannelMixerRGB/ChannelMixer/ColorContrastParity + dt 采纳 12/12（blob 88B）+ PanelWiring +4 + GUI 走查（FINDINGS 05-03 节） | ✅ green |
| 05-04-T1..T5 | 05-04 | 2 | IOP-COLOR-03/07 + colorzones | golden+unit+GUI | Vibrance/Velvia/ColorZonesParity（hue sweep 全环 + LUT 双闸）+ 采纳复验 2026-09-22 + GUI 走查（FINDINGS 05-04 节） | ✅ green |
| 05-05-T1..T4 | 05-05 | 3 | IOP-COLOR-06 | golden+unit+GUI | MonochromeParity/GridTests（CPU sigma² + grid==窗口交叉 + TilingPlan 第三消费者）+ GUI 走查（FINDINGS 05-05 节） | ✅ green |
| 05-06-T1..T5 | 05-06 | 4 | IOP-DENOISE-02 | golden+unit+GUI+perf | NLMeansParityTests 12/12 ≤5.7e-6 + 降载三件套（57 趟 vs 481）+ 分块==整幅 + Δfootprint 352MB + GUI 走查（FINDINGS 05-06 节） | ✅ green |
| 05-07-T1..T6 | 05-07 | 5 | IOP-DENOISE-01（**SC#2 正式验证**） | golden+unit+GUI+perf | DenoiseProfileParityTests 8×3（VST 三变体+波列+Bayesshrink+NLMeans 腿，门 ≤1e-6 VST）+ 错配方向断言 + PERF7 31 趟 41.7ms + GUI 走查（FINDINGS 05-07 节） | ✅ green |
| W6 修复轮 | — | 5 | 签核前 GUI 缺陷清零 | unit+真机 | GUI-10/13 同步化修复 + GUI-11/12 布局 + TaskGroup×100 回归；582/3/0；AX 压力 20 轮零崩溃 | ✅ green |
| 05-08-T1 | 05-08 | 6 | IOP-DENOISE-03 直连档 | unit+golden | `_compute_sigmas` 逐行对照表（D-05-08-T1-1）+ leg 路径切换 + 直连 vs 精确公式 **8e-7**（门 1e-5）+ σ→0 逐字节 + V50 +1（10.0）+ seed DISABLED | ✅ green |
| 05-08-T2 | 05-08 | 6 | IOP-DENOISE-03 5D grid + OQ7 | golden+unit | 网格档 vs 同算法 float64 参考（gen_fixtures）**8.6e-7**（门 1e-3）+ 近似包络测量（maxAbs 0.013-0.021 <0.05 回归界，D-05-08-T2-2）+ 确定性 <1e-6 + 分块==整幅 **4.5e-7**（grid>1）+ OQ7 公式/上界/放粗（D-05-08-T2-1） | ✅ green |
| 05-08-T3 | 05-08 | 6 | IOP-DENOISE-03 dt 三证据 | golden+adoption | 9 参考 EXR + sha256 总账（manifest bilateral 节）+ dt-cli 采纳 **3/3**（loader + params v.1 ok + DB hex==blob 20B）+ 平场探针（direct 0.0；boundary 内区 0.0；grid_large dt lattice 上游垃圾已记录） | ✅ green |
| 05-08-T4 | 05-08 | 6 | 面板 + IOP-DENOISE-04 defer | unit+doc | BilateralPanelView 4 滑块 + catalog 8 keys + Inspector zh 名同轮 + PanelWiringTests +2（54/54）；defer 决议 D-05-08-T4-1（chromatic 交付 / hotpixels/dark-frame defer / cacorrect 维持 defer 与 Phase 6 无关） | ✅ green |
| 05-08-T5 | 05-08 | 6 | sidecar 11 op + 轨 B 全链 | golden+unit | Phase5SidecarTests **12/12**（11 op 非默认 round-trip + registry 物化 + 未知 op 降级复核）；GeometryGolden track B 扩链（nlmeans+bilateral disabled）= **Phase 3+4+5 全模块基线** | ✅ green |
| 05-08-T6 | 05-08 | 6 | Phase 5 签核 | all | 本文件 + DISCUSSION-LOG SC#1-4 节 + perf.md + 移交清单；终轮全 suite **609 tests / 3 skip / 0 fail** | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Per-Requirement Annotations（需求口径注记）

| Requirement | 注记 |
|---|---|
| **IOP-COLOR-09** | 交付本体 = **colorcontrast（56.0，Lab a/b 斜率+偏移）**——SC#1 的「color contrast/correction curves」以此满足；rgbcurve(42)/rgblevels(43) 划出 Phase 5（D-05-CONTEXT-1），Phase 6+ stretch（CurveTools 全复用机械增量，槽位在 V50Order 现表）。 |
| **IOP-DENOISE-04** | 四半边拆解（D-05-08-T4-1）：**chromatic noise 已交付**（05-06 chroma 参数 + 05-07 Y0U0V0 色度模式，方向断言钉住）——SC#3 的该半边满足；**hot pixels 正式 defer**（hotpixels.c:94 IOP_CS_RAW Bayer 单通道域，CIRAW 无 despeckle 键——Spike A 双重证据；需求解释权裁决，非缺口）；**dark frame subtraction 正式 defer**（需解码前传感器访问，v1 无路径）；重启条件统一 = v2 自研 RAW 解码路径论证。 |
| **cacorrect 复议** | 维持 defer（04-05 D-04-05-T0-0 Bayer 域论证复核成立）；**与 Phase 6 无关**——Phase 6 是蒙版/图层域，cacorrect 是 RAW 域问题，不随 Phase 6 接收。 |
| **SC#3 措辞落差** | ROADMAP §Phase 5 SC#3 原文「NLMeans, bilateral/surface blur, and hot-pixel/dark-frame/chromatic-noise reduction all reduce noise…」→ 实际交付 = NLMeans ✓ + bilateral ✓ + chromatic ✓（denoise 双件承载）；hot-pixel/dark-frame 域不可达正式 defer（上注）。SC#3 以 NLMeans/bilateral/chromatic 三件 torture/加噪集 parity + 方向门判定 **PASS**。 |
| **SC#4 判定** | ① color 七件全启用拖动 **4.8ms Debug 中位 = 60fps 达标**；② denoise 单件（nlmeans 降载档）**85.7ms 未达标**——降载/批合并杠杆已兑现后仍不达，Open#9 应急判定成立；判定依据（Lab 共享对本缺口贡献 ~5%，非正杠杆）落 `.work/05/perf.md` + DECISIONS D-05-08-T6-1，应急工作不在本 plan 内，移交 Phase 6+/独立 perf plan。60fps 承诺按链区分成立：color/toning 链达标，denoise 启用链 v1 达到「可用拖动」（12fps Debug，Release 估计 ~20-25fps）而未达 60fps——**这是本签核唯一公开的未达标项**（注册 TODO PERF-5 行继续跟踪）。 |

---

## Wave 0 Requirements

- [x] gen_fixtures.py 加噪器（种子化 Poisson-Gaussian，variance 实测 vs a·I+b 统计检验）+ delta 脉冲 + hue sweep + torture crop（05-01-T5）
- [x] NoiseProfileStore（noiseprofiles.json 规范化 + 匹配/插值/generic 回落）——LICENSE 注记见 TODO 待用户知悉项
- [x] executeTiledNegotiated 回归加固（05-01-T6，四消费者预演先行）

---

## Manual-Only Verifications（L011 口径挂账）

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| bilateral 面板真机视觉走查 | IOP-DENOISE-03 | AX 行枚举路径本轮未贯通（模块行 Button 内嵌 StaticText 读取失败）；自动化已覆盖 PanelWiring 54/54（dispatch + 拖动=1 commit + 复位还原 pristine hash）+ zh/en catalog + 渲染 parity | PLAYBOOK 流程：Debug 产物 + 新文件名 ARW 副本 → 找「表面模糊」行 → 启用 → radius 拖动观察保边平滑（边缘保持、平坦区噪声消失）→ screencapture 量化（tile 缝目检：无竖向接缝）→ 撤销 1 条 → 证据归档 FINDINGS 05-08 节。**pending-manual 2026-09-23** |
| denoise 三件 torture 真实 RAW 目检（细节保持人眼判据） | IOP-DENOISE-01/02/03 | 「无细节损失」需人眼定标（自动化已钉方向+能量+parity） | 05-06/05-07 GUI 轮已做启用渲染变化量化（meanAbsDiff/拉普拉斯能量）；DSC00012 高 ISO 样本补拍后可做正式 torture 目检。**pending-manual** |
| PERF-5 denoise 链 Release 复测 | SC#4 | Release 产物需独立构建轮（test-direct 锁定 Debug 容器）；Debug≈Release 比对历史 0.92（GPU-bound）已给外推 | `xcodebuild build-for-testing -configuration Release` → Release 容器直启复跑 testPhase5DragGateTwoChains → 数字补 perf.md。**pending-manual（外推 ≈79ms，结论不受影响）** |
| noiseprofiles.json 许可证核对 | D-05-CONTEXT-2 | GPL 数据再分发合规需人工法律判读 | 核对 dt data/noiseprofiles.json 来源与许可注记 → 写 LICENSE-NOTES → 解除「不对外分发」限制。**pending-manual（2026-09-23 签核复核：仍未完成，限制继续有效）** |

---

## Sign-Off Checklist

- [x] 全部 8 plans 执行完成（05-01..05-07 + W6 + 本 plan），SUMMARY 逐 plan 落盘
- [x] SC#1-4 逐条证据指针落 DISCUSSION-LOG（缺口 = SC#4 denoise 链 60fps，公开注记非静默放宽；SC#3 措辞落差注记）
- [x] golden 完整性总账 11/11（manifest「Phase 5 golden 完整性总账」节 + sha256 抽验）
- [x] sidecar 11 新 op round-trip（Phase5SidecarTests 12/12）+ 未知 op 降级回归绿
- [x] 轨 B 全链回归（Phase 3+4+5 全模块 = Phase 6 基线）绿
- [x] PERF-5 记录 `.work/05/perf.md`（基线/两链/增量/判定）
- [x] GUI 验收轮汇总（W1-W7 闭环 + bilateral 自动化覆盖）；Manual-Only 4 行 L011 口径登记
- [x] IOP-DENOISE-04 / IOP-COLOR-09 需求注记行（本文件 + REQUIREMENTS.md）
- [x] Phase 6 移交清单（DISCUSSION-LOG/SUMMARY；mask_display 挂点 / colorbalancergb opacity masks / Lab 域模块清单 / Open#9 应急状态 / cacorrect defer 终局）
- [x] `status: validated` + `nyquist_compliant: true`；TODO/LESSONS/AGENTS/REQUIREMENTS 同批更新（§3.1 commit guard）
- [x] 终轮全 suite 0 fail（touch Tests + build-for-testing 重编复跑防增量吞更新）

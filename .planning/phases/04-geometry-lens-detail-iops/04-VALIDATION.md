---
phase: 4
slug: geometry-lens-detail-iops
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-20
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (unit) + headless ROI/golden harness |
| **Config file** | `Project.swift` (Tuist) — LightamerTests target |
| **Quick run command** | `xcodebuild test -project Lightamer.xcodeproj -scheme Lightamer -destination 'platform=macOS' -only-testing:LightamerTests` |
| **Full suite command** | `xcodebuild test -project Lightamer.xcodeproj -scheme Lightamer -destination 'platform=macOS'` |
| **Estimated runtime** | ~60-120 seconds（ROI harness + geometry/detail parity） |

---

## Sampling Rate

- **After every task commit:** quick unit tests (LightamerTests only)
- **After every plan wave:** full suite
- **Before `$gsd-verify-work`:** full suite must be green
- **Max feedback latency:** ~120 seconds

---

## Per-Task Verification Map

> Task IDs filled by planner. Plan A（ROI 协商协议改造）必须全绿后模块 plan 才动工。

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 04-01-T1..T5 | 04-01 | 1 | FOUND-04 (ROI) | — | N/A | unit | ROINegotiationTests: crop 前向收缩（下游平面=窗口尺寸）、sharpen 后向外扩（<全图）、缓存 roi 字段联动 | ✅ | ✅ green（2026-09-20：8/8；halo e2e 24×24 hint → 30×30 expanded ≪128；全 suite 279 0 fail） |
| 04-02-T1/T3/T4 | 04-02 | 2 | IOP-GEO-01 | — | N/A | golden+unit | crop parity（CropParityTests 8/8 + GeometryGolden track A 3×4 <1e-6 + SC#4 ①③④真模块回归 + overlay drag=1 item）| ✅ | ✅ green（2026-09-20：GeometryGolden 4/4；ROINegotiation 8/8；CropOverlay 6/6；PanelWiring +3 crop） |
| 04-02-T2/T3 | 04-02 | 2 | IOP-GEO-04 | — | N/A | golden+unit | flip parity（FlipParityTests 8/8 + track A 4×4 <1e-6 + flip<crop 顺序硬约束）| ✅ | ✅ green（2026-09-20：V50OrderTests +1 order constraint） |
| 04-03-T1/T2/T4 | 04-03 | 2 | IOP-GEO-02 | — | N/A | golden+unit | rotate/perspective parity（HomographyTests 6/6 + AshiftParityTests 7/7：合成 float64 参考 7×4 <1e-5/<1e-5 + 恒等门 + 黑角 alpha + V50 ashift<flip<crop 双钉）| ✅ | ✅ green（2026-09-20：全 suite 331 0 fail；管线 union-clamp 修复含回归） |
| 04-03-T3 | 04-03 | 2 | IOP-GEO-02 auto-detect | — | N/A | unit | VisionDetectTests 4/4（θ<0.2°/矩形<0.5%/符号钉死；真机抽检 pending-manual 见 .work/04-03/vision-field-notes.md）| ✅ | ✅ green（合成探针全绿） |
| 04-02-T3 | 04-02 | 2 | 轨 B 回归 | — | N/A | golden | crop-full + flip-none 插链后 ColorSync 中性度+交叉一致性不回归（D-COL1 双判据）| ✅ | ✅ green（2026-09-20：GeometryGolden track B 2/2） |
| 04-04-T1/T2/T4 | 04-04 | 3 | IOP-GEO-03 | — | N/A | golden+unit | lens parity（LensParityTests 7/7：合成 float64 参考 6×4 <1e-5/<1e-5 + k=0 恒等门 + vignette 解析点检 + CA 方向 + 统一出口逐字节；LensfunDBTests 15/15：子集钉参 + Hermite/IDW/d-factor 手算 + 4 文件交叉；ROINegotiation +1 收缩回归）| ✅ | ✅ green（2026-09-21：全 suite 355 0 fail；含管线级子域 CI 翻转修复 + ROI 宽度原点修复） |
| 04-04-T3 | 04-04 | 3 | D-G1 三层完整性 | — | N/A | unit | (a) 模块头 + 面板注记文档化；(b)(c) 同一 kernel 逐字节一致（testUnifiedExitMatchesManual）+ 降级路径（无数据 → 恒等 + 手动可用）；LensPanelView 三段 + a11y 全套 + catalog 20 keys + PanelWiring +2 + launch resolve hook | ✅ | ✅ green（2026-09-21：PanelWiring 19/19；手动滑块 7 键；下载服务失败降级） |
| 04-04-T4 | 04-04 | 3 | 轨 B 回归 | — | N/A | golden | neutral lens 插链后 ColorSync 中性度+交叉一致性不回归（D-COL1 双判据，GeometryGolden track B 链已含 lens）| ✅ | ✅ green（2026-09-21：GeometryGolden 4/4 含 lens 腿） |
| 04-05-T1/T5 | 04-05 | 3 | IOP-DETAIL-01 | — | N/A | golden+unit | sharpen parity（SharpenParityTests 5/5：合成 float64 参考 4×4 <1e-4/<1e-4 + amount=0 逐字节 + 平场恒等 + σ链钉参 + 注册35.0；ROINegotiation +1 真模块后向扩展 36×36≪全图）| ✅ | ✅ green（2026-09-21：全 suite 386 0 fail；D-G5 主证兑现） |
| 04-05-T2/T5 | 04-05 | 3 | IOP-DETAIL-02 | — | N/A | golden+unit | local-contrast parity（LocalContrastTests 6/6：合成 EIGF 参考 4×4 <1e-4 + detail=0 逐字节 + 台阶方向 + D6 映射 + 分块一致 <1e-4 + 注册bilat54.0；TilingPlan FULL 第二消费者）| ✅ | ✅ green（2026-09-21） |
| 04-05-T3/T5 | 04-05 | 3 | IOP-DETAIL-03 | — | N/A | golden+unit | highpass/soften parity（HighpassSoftenTests 7/7：双合成参考 <1e-4 + soften 平场恒等 + amount=0 逐字节 + 去饱和断言 + 半径链 + 注册34.0/66.0；soften dt-cli probe 免跑先验结论落 DECISIONS D5）| ✅ | ✅ green（2026-09-21） |
| 04-05-T4/T5 | 04-05 | 3 | IOP-DETAIL-04 | — | N/A | golden+unit | equalizer parity（EqualizerParityTests 4/4：合成金字塔参考 4×4 <1e-4 + 全零逐字节 + 带能量内容断言 + 注册27.0；V50OrderTests +1 五槽位约束）| ✅ | ✅ green（2026-09-21） |
| 04-05-T5 | 04-05 | 3 | 轨 B 回归 | — | N/A | golden | 五 detail 中性实例插链后 ColorSync 中性度+交叉一致性不回归（D-COL1 双判据，GeometryGolden track B 链已含 detail 腿）| ✅ | ✅ green（2026-09-21：GeometryGolden 4/4 含 detail 腿） |
| 04-05-T5 | 04-05 | 3 | 面板 + PERF | — | N/A | unit | 四面板（Sharpen/LocalContrast/HighpassSoften/Equalizer）各拖动恰 1 commit + dispatch 全覆盖（PanelWiring +5，24/24）；catalog 29 keys zh/en；PERF 增量落 .work/04-05/perf.md | ✅ | ✅ green（2026-09-21） |
*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `Tests/LightamerTests/ROINegotiationTests.swift` — ROI 协商 4 断言（8/8 独立复跑通过）（research §7）
- [x] gen_fixtures.py lens 节（合成 float64 参考：径向 warp + vignette，LENS_CASES 7 钉参 × 4 fixture）
- [x] Lensfun XML 固定子集（`input/golden/fixtures/lensfun/` 4 文件：ptlens/poly3/poly5/linear 全覆盖）

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| crop overlay 手柄交互 | IOP-GEO-01 SC#1 | 交互时序 + 手柄拖拽 | 拖角手柄/旋转手柄/比例锁定 → 确认实时预览与网格 |
| crop 比例锁手感（3:2/16:9/original）| IOP-GEO-01 | 锁比拖角的短边贴合手感 | 选 3:2 → 拖角 → 矩形保持 3:2（以短边为准）；original → 以当前图幅比锁定 |
| 镜头校正视觉（门框/建筑直线） | IOP-GEO-03 | 畸变还原需人眼直线判据 | input/RAW 现有 DSC00012/DSC09991 建筑：lens 面板 distortionK1 ±0.1 拖动 → 边缘直线由弯变直、CA 边缘紫边收敛；复位归零（L011 口径 pending-manual）|
| crop overlay 拖角 → viewport 纹理尺寸变化 | IOP-GEO-01 SC#1 | XCUITest 需解锁控制台（L011）；自动化腿已由 CropOverlayTests 覆盖（drag=1 item + live-disabled + neutral seed）| 打开图片 → 选 crop 面板 → 拖右下角手柄向内 → viewport 图像变小、暗膜在拖动中可见、松手后 history +1 |
| crop 三分/黄金网格视觉 | IOP-GEO-01 SC#1 | 像素级视觉（自动化只断言几何存在）| 拖动中确认三分线；切换 phi 网格（showsPhiGrid）确认 0.3819/0.6181 线位 |
| detail 五模块视觉抽检（clarity/Orton/高通/均衡器） | IOP-DETAIL-01..04 | 增强方向/强度需人眼判据（自动化已钉方向 + 能量 + parity）| DSC00012：sharpen amount 0.5→ 细节起颗粒但无振铃；bilat detail +1 → 局部对比提升无 halo；soften amount 50 → 高光柔化（Orton）；highpass contrast 50 → 灰底浮雕；equalizer g0 +0.5 → 细纹理增强；复位归零（L011 口径 pending-manual）|

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

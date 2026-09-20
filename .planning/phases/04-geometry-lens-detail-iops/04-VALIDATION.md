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

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `Tests/LightamerTests/ROINegotiationTests.swift` — ROI 协商 4 断言（8/8 独立复跑通过）（research §7）
- [ ] gen_fixtures.py 增 geometry/detail 节（合成 float64 参考：旋转/透视/畸变/USM 已知向量）
- [ ] Lensfun XML 数据文件获取 + 解析器 stub（如走 (c) 层）

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| crop overlay 手柄交互 | IOP-GEO-01 SC#1 | 交互时序 + 手柄拖拽 | 拖角手柄/旋转手柄/比例锁定 → 确认实时预览与网格 |
| 镜头校正视觉效果 | IOP-GEO-03 | 视觉验收 | 开关镜头校正对比畸变线（门框/建筑直线）|
| crop overlay 拖角 → viewport 纹理尺寸变化 | IOP-GEO-01 SC#1 | XCUITest 需解锁控制台（L011）；自动化腿已由 CropOverlayTests 覆盖（drag=1 item + live-disabled + neutral seed）| 打开图片 → 选 crop 面板 → 拖右下角手柄向内 → viewport 图像变小、暗膜在拖动中可见、松手后 history +1 |
| crop 三分/黄金网格视觉 | IOP-GEO-01 SC#1 | 像素级视觉（自动化只断言几何存在）| 拖动中确认三分线；切换 phi 网格（showsPhiGrid）确认 0.3819/0.6181 线位 |
| crop 比例锁手感（3:2/16:9/original）| IOP-GEO-01 | 锁比拖角的短边贴合手感 | 选 3:2 → 拖角 → 矩形保持 3:2（以短边为准）；original → 以当前图幅比锁定 |
---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

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
| (planner) | — | 2 | IOP-GEO-01/02/04 | — | N/A | golden+unit | crop/rotate/flip parity（crop/flip 可直用 dt-cli；rotate 合成 float64 参考）| ❌ W0 | ⬜ pending |
| (planner) | — | 2 | IOP-GEO-03 | — | N/A | golden+unit | lens distortion/CA/vignette parity（合成 float64 参考 + uniform dt 探针）| ❌ W0 | ⬜ pending |
| (planner) | — | 3 | IOP-DETAIL-01/02/03/04 | — | N/A | golden+unit | sharpen USM/local contrast(EIGF)/highpass-soften/equalizer parity（Lab 域经 LabRoundTrip）| ❌ W0 | ⬜ pending |
| (planner) | — | — | 轨 B 回归 | — | N/A | golden | 全模块插链后 ColorSync 中性度+交叉一致性不回归（D-COL1 双判据）| ✓ | ⬜ pending |
| 04-01-T5 | 04-01 | 1 | 内存记账 | D-C1/C2 | N/A | unit | crop 后 FULL 平面记账下降、sharpen 外扩 < 全图 | ✅ | ✅ green（2026-09-20：MemoryBudgetTests 9/9；crop 1/4 bytes；halo 30×30+24×24 ≪128） |

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

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

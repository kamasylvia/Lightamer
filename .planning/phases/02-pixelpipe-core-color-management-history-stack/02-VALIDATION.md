---
phase: 2
slug: pixelpipe-core-color-management-history-stack
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-18
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (unit) + headless smoke harnesses (`.work/*/smoke.swift` 模式) |
| **Config file** | `Project.swift` (Tuist) — LightamerTests target |
| **Quick run command** | `xcodebuild test -project Lightamer.xcodeproj -scheme Lightamer -destination 'platform=macOS' -only-testing:LightamerTests` |
| **Full suite command** | `xcodebuild test -project Lightamer.xcodeproj -scheme Lightamer -destination 'platform=macOS'` |
| **Estimated runtime** | ~30-90 seconds（golden 色彩 harness 含 60MP 渲染会拉长） |

---

## Sampling Rate

- **After every task commit:** quick unit tests (LightamerTests only)
- **After every plan wave:** full suite
- **Before `$gsd-verify-work`:** full suite must be green
- **Max feedback latency:** ~90 seconds

---

## Per-Task Verification Map

> Task IDs filled by planner. Seeds from RESEARCH §Validation Architecture.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| (planner) | — | 1 | FOUND-04 | — | N/A | unit | PipeCache: run1 全 miss → 改 testGain → colorin hit/testGain miss → undo → 双 hit（计数器断言）| ❌ W0 | ⬜ pending |
| (planner) | — | 1 | HIST-01..04 | — | N/A | unit | HistoryStack: drag-end 提交一步、undo/redo 指针、paramsHash 稳定（FNV-1a 跨进程）| ❌ W0 | ⬜ pending |
| (planner) | — | 1 | HIST-03 | — | N/A | unit | Sidecar round-trip: 写→清状态→重开→逐字段一致；漂移注入→检测不回写 | ❌ W0 | ⬜ pending |
| (planner) | — | 1 | COLOR-01 | — | N/A | golden | 中性度（灰块通道差<2/255）+ 交叉一致性（vs ColorSync 基准逐像素<2/255）| ❌ W0 | ⬜ pending |
| (planner) | — | 1 | RAW-03 | — | N/A | unit | 32f TIFF/EXR 解码位深保真 | ❌ W0 | ⬜ pending |
| (planner) | — | 1 | D-C1/C2 | — | N/A | unit | 内存 harness：N 图连续加载，PipeCache.totalBytes < 3GB 且 load 入口触发清理 | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Tests/LightamerTests/PipeCacheTests.swift` — FOUND-04 缓存快路径 + 失效语义
- [ ] `Tests/LightamerTests/HistoryStackTests.swift` — HIST-01..04
- [ ] `Tests/LightamerTests/SidecarRoundTripTests.swift` — HIST-03
- [ ] `Tests/LightamerTests/GoldenColorTests.swift` — COLOR-01 双判据（需 ColorChecker 样本采集）
- [ ] `Tests/LightamerTests/RAW03Tests.swift` — RAW-03 位深保真
- [ ] `Tests/LightamerTests/MemoryBudgetTests.swift` — D-C1/C2 回归
- [ ] testGain dev-only 参数模块（SC#2 演示载体，LightamerIOP）
- [ ] ColorChecker ARW 样本采集（CC0 源）

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 拖动滑块 60fps 无全链重算 | FOUND-04 SC#2 | 交互时序 + Instruments signpost 目检 | 打开 100MP → 拖 testGain → Instruments 确认 colorin 无重算、缓存命中计数递增 |
| 屏幕色彩正确性（非 headless 可测部分）| COLOR-01 SC#1 | 已知中性目标上屏目检 | 打开中性目标 RAW → 灰块在屏无偏色 |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

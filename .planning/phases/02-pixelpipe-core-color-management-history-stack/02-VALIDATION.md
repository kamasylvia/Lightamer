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
| 02-02-06 | 02-02 | 2 | FOUND-04 | — | N/A | unit | PipeCacheTests：run1 全 miss → 改 testGain → 上游命中/下游 miss → undo 全命中（精确计数器断言）| ✅ | ✅ green（9/9）|
| 02-03-05 | 02-03 | 3 | FOUND-04 | Risk #8 | N/A | unit | MultiResolutionTests：scale-at-entry 60MP→2560px 长边、PREVIEW@360 ≠ THUMBNAIL key（两套缓存行）、THUMBNAIL lazy（dirty 才渲）、FULL scale-1.0 + 只缓存输入/终帧、EXPORT typed `.notImplemented`、roi.scale<1 断言（6 测试）+ PreviewBucketTests 梯子边界（5 测试）| ✅ | ✅ green（63 全套，1 skip 既有）|
| (planner) | — | 4 | HIST-01..04 | — | N/A | unit | HistoryStack: drag-end 提交一步、undo/redo 指针、paramsHash 稳定（FNV-1a 跨进程）| ❌ W0 | ⬜ pending |
| (planner) | — | 5 | HIST-03 | — | N/A | unit | Sidecar round-trip: 写→清状态→重开→逐字段一致；漂移注入→检测不回写 | ❌ W0 | ⬜ pending |
| (planner) | — | 3 | COLOR-01 | — | N/A | golden | 中性度（灰块通道差<2/255）+ 交叉一致性（vs ColorSync 基准逐像素<2/255）| ❌ W0 | ⬜ pending |
| (planner) | — | 5 | RAW-03 | — | N/A | unit | 32f TIFF/EXR 解码位深保真 | ❌ W0 | ⬜ pending |
| (planner) | — | 5 | D-C1/C2 | — | N/A | unit | 内存 harness：N 图连续加载，PipeCache.totalBytes < 3GB 且 load 入口触发清理 | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `Tests/LightamerTests/PipeCacheTests.swift` — FOUND-04 缓存快路径 + 失效语义（02-02：9 测试全绿，含 SC#2 主链/禁用跳过/FULL 政策/LRU 淘汰/decodeHash 失效/PipeHash 组成/invalidate 扫除）
- [x] `Tests/LightamerTests/PreviewBucketTests.swift` — D-C3 量化梯子边界（02-03：5 测试全绿，纯函数）
- [x] `Tests/LightamerTests/MultiResolutionTests.swift` — FOUND-04 多分辨率生命周期（02-03：6 测试全绿；手测 resize 防抖见 `.work/02-03/resize-verification.md`）
- [x] testGain dev-only 参数模块（SC#2 演示载体，LightamerIOP）——02-02 交付
- [ ] `Tests/LightamerTests/HistoryStackTests.swift` — HIST-01..04
- [ ] `Tests/LightamerTests/SidecarRoundTripTests.swift` — HIST-03
- [ ] `Tests/LightamerTests/GoldenColorTests.swift` — COLOR-01 双判据（需 ColorChecker 样本采集）
- [ ] `Tests/LightamerTests/RAW03Tests.swift` — RAW-03 位深保真
- [ ] `Tests/LightamerTests/MemoryBudgetTests.swift` — D-C1/C2 回归
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

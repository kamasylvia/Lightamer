---
phase: 3
slug: tone-filmic-iops
status: draft
nyquist_compliant: false
wave_0_complete: false
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
| (planner) | — | 1 | IOP-TONE-01 (exposure) | — | N/A | golden parity | 合成 fixture → dt-cli 单模块钉参 → EXR vs Lightamer → 逐像素 <1e-5 相对误差 | ❌ W0 | ⬜ pending |
| (planner) | — | 1 | IOP-TONE-02 (WB) | — | N/A | unit+golden | K→增益 CPU 单测（已知向量）+ 吸管数学 + fixture golden | ❌ W0 | ⬜ pending |
| (planner) | — | 1 | IOP-TONE-03 (tonecurve) | — | N/A | unit+golden | 10001 点 1D 阶梯 LUT round-trip + dt-cli parity | ❌ W0 | ⬜ pending |
| (planner) | — | 2 | IOP-TONE-04 (shadhi) | — | N/A | golden parity | Lab 往返 + bilateral 容差 <1e-4 + ΔE<1.0 99% 分位 | ❌ W0 | ⬜ pending |
| (planner) | — | 2 | IOP-TONE-05 (colisa contrast) | — | N/A | golden parity | Lab 域对比度 parity | ❌ W0 | ⬜ pending |
| (planner) | — | 2 | IOP-TONE-06 (levels) | — | N/A | unit+golden | levels black/white/灰色点 parity | ❌ W0 | ⬜ pending |
| (planner) | — | 3 | IOP-TONE-07 (toneequal) | — | N/A | unit+golden | CPU correction LUT 单测 + EIGF Metal golden（TilingPlan 首战 FULL 管线）| ❌ W0 | ⬜ pending |
| (planner) | — | 3 | IOP-FILM-02 (sigmoid) | — | N/A | unit+golden | commit_params 四标量 CPU 互验 + fixture parity <1e-5 | ❌ W0 | ⬜ pending |
| (planner) | — | 4 | IOP-FILM-01 (filmicrgb) | — | N/A | unit+golden | F0-F4 五子阶段独立 golden + 组合 parity | ❌ W0 | ⬜ pending |
| (planner) | — | 4 | IOP-FILM-03 (variants) | — | N/A | unit | filmic 变体参数组 round-trip | ❌ W0 | ⬜ pending |
| (planner) | — | 5 | PERF-5 | — | N/A | signpost | PREVIEW 全模块链单帧 <16.6ms CI 记录（Phase 1 模式）| ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `input/golden/fixtures/` — 合成 fixture 组脚本（灰阶 ramp −8..0EV、平场、饱和色块、深阴影梯度、中性灰阶梯、1D 阶梯）
- [ ] darktable-cli 重建（当前树 dc58cf0ba1）+ XMP attach 验证（修复预构建版丢历史缺陷）
- [ ] `Tests/LightamerTests/GoldenParityTests.swift` — dt-cli parity 双轨 harness
- [ ] `Tests/LightamerTests/CPUDerivationTests.swift` — 各模块 CPU 推导公式直译互验
- [ ] 各 iop 的 `.swift + .metal` 文件对 stubs（exposure/temperature/tonecurve/shadhi/colisa/levels/toneequal/sigmoid/filmicrgb）

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 滑块拖动 60fps | PERF-5 SC#3 | 交互时序 + Instruments | 拖任一 tone 滑块 → Instruments 确认 PREVIEW 链 <16.6ms |
| 色彩视觉效果 | IOP-TONE-01..07 | 视觉验收 | 对真实照片逐模块开关对比，确认无伪影/带状/跳变 |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

---
phase: 1
slug: foundation-app-skeleton-capability-spikes
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-03
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (unit) + XCUITest (UI) — macOS native, ships with Xcode |
| **Config file** | `Project.swift` (Tuist) — `LightamerTests` + `LightamerUITests` targets (run `tuist generate` first) |
| **Quick run command** | `xcodebuild test -project Lightamer.xcodeproj -scheme Lightamer -destination 'platform=macOS' -only-testing:LightamerTests` |
| **Full suite command** | `xcodebuild test -project Lightamer.xcodeproj -scheme Lightamer -destination 'platform=macOS'` |
| **Estimated runtime** | ~30-60 seconds (Phase 1 is skeleton — few tests, no golden-image harness yet) |

---

## Sampling Rate

- **After every task commit:** Run quick unit tests (`LightamerTests` only)
- **After every plan wave:** Run full suite (unit + UI)
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

> Task IDs reference the real plan task that implements each requirement (format `01-XX-YY` where XX = plan number).
> Each task MUST have an `<automated>` verify or a Wave 0 dependency.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-03 | 01 | 1 | FOUND-02 | — | N/A | unit | Source assertion: `WorkingSpace.colorSpace` = `rec2020Linear`, `WorkingSpace.pixelFormat` = `.rgba32Float`, `bytesPerPixel` = 16 | ❌ W0 | ⬜ pending |
| 01-01-06 | 01 | 1 | FOUND-01 | — | N/A | build+manual | `xcodebuild build -project Lightamer.xcodeproj -scheme Lightamer` succeeds on macOS 27 SDK; app launches, three-column shell visible, dark mode forced | ❌ W0 | ⬜ pending |
| 01-02-03 | 02 | 1 | RAW-01 | — | N/A | unit | `RAWDecoderTests: decode CR3/NEF/ARW/RAF succeeds, CIImage non-nil` | ❌ W0 | ⬜ pending |
| 01-02-03 | 02 | 1 | RAW-02 | — | N/A | unit | `RAWDecoderTests: decode DNG succeeds` | ❌ W0 | ⬜ pending |
| 01-02-03 | 02 | 1 | RAW-04 | — | N/A | unit | `RAWDecoderTests: decode JPEG/HEIC/PNG/WebP/TIFF via CGImageSource path` | ❌ W0 | ⬜ pending |
| 01-02-03 | 02 | 1 | RAW-05 | — | N/A | unit | `RAWDecoderTests: decoderVersion=.version9 under #available(macOS 27,*); fallback .version8` | ❌ W0 | ⬜ pending |
| 01-02-03 | 02 | 1 | RAW-06 | — | N/A | unit | `MetadataTests: camera/lens/focal/aperture/shutter/ISO/GPS/capture-time extracted from CR3+NEF` | ❌ W0 | ⬜ pending |
| 01-03-06 | 03 | 1 | FOUND-05 | — | N/A | manual+unit | `EditorMTKView displays decoded RAW without error` (manual: File → Open CR3 → pixels visible in center column) | ❌ W0 | ⬜ pending |
| 01-03-07 | 03 | 1 | FOUND-06 | — | N/A | unit | `MetalContextTests: pass-through kernel bit-exact (buffer in == buffer out)` | ❌ W0 | ⬜ pending |
| 01-04-02 | 04 | 1 | FOUND-03 | — | N/A | unit | `IOPModuleTests: PassthroughModule conforms, Params: Codable & Hashable` | ❌ W0 | ⬜ pending |
| 01-04-03 | 04 | 1 | FOUND-03 | — | N/A | unit | `V50OrderTests: entries count ~76, no duplicate opName except deliberate collisions` | ❌ W0 | ⬜ pending |
| 01-04-04 / 01-06-02 | 04/06 | 1/2 | D-03a | — | N/A | unit | `LayerSkeletonTests: LayerStack(baseLayer:) constructs; BlendMode.normal.rawValue == 1` | ❌ W0 | ⬜ pending |
| 01-05-01 | 05 | 2 | FOUND-07 | — | N/A | spike-doc | `Spike A report: CIRAW 9 capability table committed` | ❌ W0 | ⬜ pending |
| 01-05-02 | 05 | 2 | FOUND-07 | — | N/A | spike-doc | `Spike B report: 100MP GFX100S decode+display, no jetsam, perf data recorded` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Tests/LightamerTests/RAWDecoderTests.swift` — stubs for RAW-01/02/04/05/06 (decode CR3/NEF/ARW/RAF/DNG + non-RAW + decoderVersion opt-in + metadata)
- [ ] `Tests/LightamerTests/MetalContextTests.swift` — stub for FOUND-06 (pass-through kernel bit-exact)
- [ ] `Tests/LightamerTests/IOPModuleTests.swift` — stub for FOUND-03 (PassthroughModule conformance + Codable/Hashable)
- [ ] `Tests/LightamerTests/V50OrderTests.swift` — stub for FOUND-03 (entries count + duplicate detection)
- [ ] `Tests/LightamerTests/LayerSkeletonTests.swift` — stub for D-03a (LayerStack constructs, BlendMode raw values)
- [ ] `Tests/LightamerTests/MetadataTests.swift` — stub for RAW-06 (EXIF/IPTC/XMP/GPS extraction)
- [ ] `Tests/LightamerUITests/AppLaunchTests.swift` — stub for FOUND-01/05 (app launches, three-column shell, dark mode, empty state)
- [ ] Test sample RAW files in `Resources/TestFixtures/` (at least 1× CR3, NEF, ARW, RAF, DNG, JPEG, HEIC, PNG, TIFF) — small representative samples, not full-size

*Framework (XCTest/XCUITest) ships with Xcode — no install needed; Tuist declares test targets in Project.swift (run `tuist generate` first).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Decoded RAW visibly displays in editor viewport | FOUND-05 | Visual confirmation of MTKView rendering — automated screenshot diff is Phase 2 (golden-image harness) | Open a CR3/NEF/ARW via File→Open; confirm image appears in center column, no blank/black viewport, no console errors |
| 100MP GFX100S RAF opens without memory failure | FOUND-07 (spike B) | jetsam kill is a system-level event; visual + Activity Monitor confirmation | Open GFX100S RAF; watch Activity Monitor memory < 4GB steady-state; no jetsam log; image displays |
| Three-column shell layout correct | FOUND-01 | Layout/visual correctness | Launch app; confirm left nav / center / right Inspector visible; dark mode forced; empty-state prompt shown |
| os.signpost intervals visible in Instruments | D-31 | Instruments is a GUI tool | Open Instruments → Metal System Trace; open a RAW; confirm signpost intervals for decode+display appear |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

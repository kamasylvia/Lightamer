---
phase: 1
slug: foundation-app-skeleton-capability-spikes
status: draft
nyquist_compliant: true
wave_0_complete: true
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
| 01-01-03 | 01 | 1 | FOUND-02 | — | N/A | unit | Source assertion: `WorkingSpace.colorSpace` = `rec2020Linear`, `WorkingSpace.pixelFormat` = `.rgba32Float`, `bytesPerPixel` = 16 | ✅ | ✅ green (exercised by `MetalContextTests.testPassThroughKernelBitExact` — allocates via `WorkingSpace.pixelFormat`/`bytesPerPixel` and proves bit-exact float32 RGBA round-trip; Plan 01 smoke) |
| 01-01-06 | 01 | 1 | FOUND-01 | — | N/A | build+manual | `xcodebuild build -project Lightamer.xcodeproj -scheme Lightamer` succeeds on macOS 27 SDK; app launches, three-column shell visible, dark mode forced | ✅ | ⚠️ pending-manual — build ✅ (rebuilt repeatedly 2026-09-16); shell/dark-mode visual blocked: host screen LOCKED, XCUITest runner times out enabling automation (`AppLaunchTests` ready + label-matched to String Catalog, runs green once unlocked) |
| 01-02-03 | 02 | 1 | RAW-01 | — | N/A | unit | `RAWDecoderTests: decode CR3/NEF/ARW/RAF succeeds, CIImage non-nil` | ✅ | ✅ green (Plan 05 CC0 samples; GPS-less CR3 skip is a fixture property) |
| 01-02-03 | 02 | 1 | RAW-02 | — | N/A | unit | `RAWDecoderTests: decode DNG succeeds` | ✅ | ✅ green |
| 01-02-03 | 02 | 1 | RAW-04 | — | N/A | unit | `RAWDecoderTests: decode JPEG/HEIC/PNG/WebP/TIFF via CGImageSource path` | ✅ | ✅ green (JPEG/HEIC/PNG/TIFF; WebP has no fixture this phase — rides the same raster path, noted in test) |
| 01-02-03 | 02 | 1 | RAW-05 | — | N/A | unit | `RAWDecoderTests: decoderVersion=.version9 under #available(macOS 27,*); fallback .version8` | ✅ | ✅ green (A7R V → v9; Z8 → silent v8 fallback, version-pinned to GM camera list) |
| 01-02-03 | 02 | 1 | RAW-06 | — | N/A | unit | `MetadataTests: camera/lens/focal/aperture/shutter/ISO/GPS/capture-time extracted from CR3+NEF` | ✅ | ✅ green (surfaced + fixed the CR3 EXIF-2.3 ISO gap, commit 93c4eb6; GPS row skips on GPS-less fixture) |
| 01-03-06 | 03 | 1 | FOUND-05 | — | N/A | manual+unit | `EditorMTKView displays decoded RAW without error` (manual: File → Open CR3 → pixels visible in center column) | ✅ | ⚠️ pending-manual — decode→PixelPipe→display-texture path exercised headless (Plan 04 smoke 13/13 + Plan 06 perf harness 6/6 files rendered); on-screen visual check needs an unlocked session |
| 01-03-07 | 03 | 1 | FOUND-06 | — | N/A | unit | `MetalContextTests: pass-through kernel bit-exact (buffer in == buffer out)` | ✅ | ✅ green (bit-exact + PSO cache hit + function-constants specialization) |
| 01-04-02 | 04 | 1 | FOUND-03 | — | N/A | unit | `IOPModuleTests: PassthroughModule conforms, Params: Codable & Hashable` | ✅ | ✅ green (incl. bit-exact no-op `process`) |
| 01-04-03 | 04 | 1 | FOUND-03 | — | N/A | unit | `V50OrderTests: entries count ~76, no duplicate opName except deliberate collisions` | ✅ | ✅ green (count = **93** — verbatim iop_order.c port; plan's "~76" estimate undercounted, recorded in 01-04-SUMMARY) |
| 01-04-04 / 01-06-02 | 04/06 | 1/2 | D-03a | — | N/A | unit | `LayerSkeletonTests: LayerStack(baseLayer:) constructs; BlendMode.normal.rawValue == 1` | ✅ | ✅ green |
| 01-05-01 | 05 | 2 | FOUND-07 | — | N/A | spike-doc | `Spike A report: CIRAW 9 capability table committed` | ✅ | ✅ green (`spike-a-ciraw9-boundary.md`, commit 2273f1e) |
| 01-05-02 | 05 | 2 | FOUND-07 | — | N/A | spike-doc | `Spike B report: 100MP GFX100S decode+display, no jetsam, perf data recorded` | ✅ | ✅ green (`spike-b-100mp-perf.md`, commit d3b3cb7; consolidated into `01-PERF-BASELINE.md` by Plan 06) |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky/pending-manual. Suite tally 2026-09-16: LightamerTests **36 executed, 1 skipped (fixture carries no GPS), 0 failed — TEST SUCCEEDED**. LightamerUITests: environment-blocked on the locked-screen host (runner signature fixed by ad-hoc re-sign; then "timed out while enabling automation mode") — pending manual run.*

---

## Wave 0 Requirements

- [x] `Tests/LightamerTests/RAWDecoderTests.swift` — stubs for RAW-01/02/04/05/06 (decode CR3/NEF/ARW/RAF/DNG + non-RAW + decoderVersion opt-in + metadata)
- [x] `Tests/LightamerTests/MetalContextTests.swift` — stub for FOUND-06 (pass-through kernel bit-exact)
- [x] `Tests/LightamerTests/IOPModuleTests.swift` — stub for FOUND-03 (PassthroughModule conformance + Codable/Hashable)
- [x] `Tests/LightamerTests/V50OrderTests.swift` — stub for FOUND-03 (entries count + duplicate detection)
- [x] `Tests/LightamerTests/LayerSkeletonTests.swift` — stub for D-03a (LayerStack constructs, BlendMode raw values)
- [x] `Tests/LightamerTests/MetadataTests.swift` — stub for RAW-06 (EXIF/IPTC/XMP/GPS extraction)
- [x] `Tests/LightamerUITests/AppLaunchTests.swift` — stub for FOUND-01/05 (app launches, three-column shell, dark mode, empty state)
- [x] Test sample RAW files — satisfied by the recorded two-tier strategy: tracked rasters in `Resources/TestFixtures/` (JPEG/HEIC/PNG/TIFF; the 1.2 GB Plan 05 CC0 RAW samples (CR3/NEF/ARW/RAF/DNG + 8 more) stay untracked at `.work/01-05/samples/` with an internal-disk mirror for test runs — bundling 1.2 GB into the repo/target was rejected (Fixtures.swift, 01-06-SUMMARY)

*Framework (XCTest/XCUITest) ships with Xcode — no install needed; Tuist declares test targets in Project.swift (run `tuist generate` first).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions | Status (2026-09-16 evening session) |
|----------|-------------|------------|-------------------|-------------------------------------|
| Decoded RAW visibly displays in editor viewport | FOUND-05 | Visual confirmation of MTKView rendering — automated screenshot diff is Phase 2 (golden-image harness) | Open a CR3/NEF/ARW via File→Open; confirm image appears in center column, no blank/black viewport, no console errors | ⚠️✅ pipeline+app-level PASS: A7R5 60MP ARW loaded via open-Apple Event; previously-fatal Metal validation abort (uncommitted encoder, L008) fixed; app alive with image >40 min, zero crash reports, draw commits clean. Pixel-exact blit already proven headless (13/13). Eyeball confirm pending unlocked display (screen slept) |
| 100MP GFX100S RAF opens without memory failure | FOUND-07 (spike B) | jetsam kill is a system-level event; visual + Activity Monitor confirmation | Open GFX100S RAF; watch Activity Monitor memory < 4GB steady-state; no jetsam log; image displays | ✅ covered by Spike B headless measurement (peak 2.0-2.8 GB single-image, no jetsam) |
| Three-column shell layout correct | FOUND-01 | Layout/visual correctness | Launch app; confirm left nav / center / right Inspector visible; dark mode forced; empty-state prompt shown | ⚠️✅ AX-tree verified (empty-state copy, inspector, toolbar disabled semantics, menus, status bar "就绪"); eyeball confirm pending unlocked display |
| os.signpost intervals visible in Instruments | D-31 | Instruments is a GUI tool | Open Instruments → Metal System Trace; open a RAW; confirm signpost intervals for decode+display appear | ⚠️ pending GUI session (signposts emitted in code; smoke harnesses read timings programmatically) |
| XCUITest launch suite (AppLaunchTests) | FOUND-01/05 | Requires TCC Automation/Accessibility trust for LightamerUITests-Runner | System Settings → Privacy & Security → Accessibility & Automation → enable LightamerUITests-Runner; unlock display; re-run `xcodebuild test -only-testing:LightamerUITests` | ⚠️ blocked: "Timed out while enabling automation mode" — TCC trust not granted (prompt suppressed) + display sleep; test code ready |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s (LightamerTests: ~19 s wall via `xcodebuild test -only-testing:LightamerTests` on the M4 host; USB-volume cold I/O can inflate wall time — see LESSONS L009)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** executor — GSD executor, 2026-09-16 (Plan 06 task 01-06-06); updated 2026-09-16 evening (on-screen verification session — fixed two real bugs found during visual verification: L008 uncommitted-encoder abort, open-Apple-Event gap; see commits after 5a8c175). Automated unit suite green (36/36 executed, 1 documented skip); manual-only rows as annotated above — remaining eyeball/Instruments/XCUITest items wait on an unlocked, TCC-trusted GUI session, recorded as pending-manual, not assumed green. D-29 confirmed: no CI config exists; local `xcodebuild test` is the Phase 1 verification mechanism.

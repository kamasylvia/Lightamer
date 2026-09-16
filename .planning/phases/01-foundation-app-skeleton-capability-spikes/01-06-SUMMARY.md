---
phase: 1
plan: 06
status: complete
completed: 2026-09-16
duration: two executor sessions (first session wrote all artifacts and stalled before the test run; second session ran tests to green, recorded the perf baseline, signed VALIDATION and committed)
commits:
  - 93c4eb6 fix(01-06): read CR3 ISO from EXIF 2.3 ISOSpeed keys
  - ed42138 test(01-06): fill LightamerTests bodies and add boundary, error and fixture suites
  - a07c936 docs(01-06): module API contracts for Core, IOP and app
  - 537acb2 docs(01-06): validation sign-off + perf baseline + TODO status
  - (this commit) docs(01-06): plan summary
---

# Plan 01-06 — Summary

Phase 1's verification wrapper is closed. The test skeleton Plans 02-04
created now has real bodies, the module contracts are documented (D-03c),
the perf baseline is recorded against the D-32 budgets (D-30/D-31/D-32),
and `01-VALIDATION.md` is signed with `nyquist_compliant: true` +
`wave_0_complete: true`.

## Test results (2026-09-16, `xcodebuild test -project Lightamer.xcodeproj -scheme Lightamer -destination 'platform=macOS' -only-testing:LightamerTests`)

**36 executed · 1 skipped · 0 failed — TEST SUCCEEDED.**

| Suite | Tests | Result |
|---|---|---|
| AppErrorTests (D-25) | 6 | pass |
| IOPModuleTests (FOUND-03) | 3 | pass |
| LayerSkeletonTests (D-03a) | 3 | pass |
| MetalContextTests (FOUND-06, D-16/D-17) | 4 | pass |
| MetadataTests (RAW-06) | 4 | pass, 1 skip (CR3 fixture carries no GPS dict — fixture property, documented) |
| ModuleBoundaryTests (D-02/§9) | 2 | pass |
| RAWDecoderTests (RAW-01/02/04/05/06, D-25, D-34) | 11 | pass (all decode against the real Plan 05 CC0 camera samples) |
| V50OrderTests (FOUND-03) | 3 | pass |

The one skip is a legit XCTSkip (fixture carries no GPS). The GPU guards
(`XCTSkipIf(MTLCreateSystemDefaultDevice() == nil)`) did not trigger — the
M4 host has Metal.

**LightamerUITests (`AppLaunchTests`): environment-blocked, pending-manual —
not a false green.** Attempted twice. Attempt 1 failed at bundle load:
runner/bundle Team-ID mismatch (infrastructure signing). After an ad-hoc
re-sign of the runner the runner launched but timed out *"while enabling
automation mode"* — XCUITest on macOS needs an unlocked GUI session and the
host screen was LOCKED for this entire execution window
(`CGSessionScreenIsLocked = 1` verified). The test code is in place and its
a11y queries were verified verbatim against the String Catalog (en + zh
values for `sessions`, `editor_viewport`, `a11y_inspector_label`,
`a11y_empty_state_label`); re-running
`xcodebuild test -only-testing:LightamerUITests` on an unlocked session
should exercise it.

## Two real bugs the tests caught (and their fixes)

1. **CR3 ISO metadata gap** (`93c4eb6`): `RAWDecoder.readCaptureMetadata`
   read only the legacy `kCGImagePropertyExifISOSpeedRatings` key; modern
   Canon CR3 reports ISO solely under EXIF 2.3 `ISOSpeed` /
   `RecommendedExposureIndex` — so `capture.iso` was nil for CR3. Fixed by
   extending the ISO chain. This was the first execution of the metadata
   path against real camera RAW (Plans 02-04 smoke ran rasters only).
2. **Metal fatal assertion in PSO-cache probes** (in `ed42138`):
   `testPSOCacheHit` / `testFunctionConstantsSpecialization` dropped the
   `ComputeEncoderSession` without `endEncoding()` + `commit()` — Metal's
   validator aborted the runner ("Command encoder released without
   endEncoding"), crashing the test session twice per run. Tests now close
   each probe session per the documented `makeEncoder` caller contract.
   Source untouched for this one (the contract is caller-owns-cleanup by
   design).

## Per-task record

- **01-06-01 (RAWDecoder/Metadata/AppError tests)** — filled with real
  assertions through the public surface only (no `@testable`). RAW samples
  resolve by path (see fixture-strategy deviation); rasters ride in the
  test bundle. `testCorruptRAWThrowsTypedError` proves typed `AppError` on
  a truncated CR3; `testDecodeIsCancellable` covers pre-cancelled and
  mid-flight cancellation.
- **01-06-02 (MetalContext/IOPModule/V50Order/Layer tests)** — filled; GPU
  dispatches run for real (bit-exact identity `pass_through` texture
  dispatch, PSO cache instance-identity hits, function-constants
  specialization).
- **01-06-03 (ModuleBoundary + AppLaunch tests)** — `ModuleBoundaryTests`
  passes and documents the executor-verified negative compile check
  (`PSOKey` invisible across the boundary:
  `error: cannot find 'PSOKey' in scope`). `AppLaunchTests` written +
  label-verified; run blocked by the locked screen (above).
- **01-06-04 (three API.md)** — committed (`a07c936`); public surfaces match
  what `ModuleBoundaryTests` instantiates.
- **01-06-05 (perf baseline)** — `01-PERF-BASELINE.md` committed in
  `537acb2`: two legs (Spike B raw matrix + the real app pipeline measured
  through `RAWDecoder.decode` signpost → `RenderPipeline` → internal
  PixelPipe on six fixtures, 22–102 MP). Budget verdicts: 100MP decode PASS
  except lossless-compressed GFX RAF (20.9 s — Apple decompressor cliff);
  display PASS cached (4–6 ms blit) / FAIL pre-cache first render
  (0.2–3.4 s — the Phase 2 cache fast-path target); memory PASS per-image /
  CONDITIONAL per-session (needs `clearCaches()` on image switch — app leg
  drifted to 5.4 GB over six files, reproducing Spike B's finding in the
  real pipeline); frame PASS with the pixelpipe cache (15.6 ms @ 102 MP).
  Harness source: `.work/01-06/perf-baseline.swift` (compiled against
  DerivedData frameworks, not a build target).
- **01-06-06 (suite green + verification gate)** — unit suite green;
  VALIDATION map fully updated (automated rows ✅, manual rows
  ⚠️ pending-manual); D-29 re-confirmed (no CI config exists — no
  `.github/workflows/`, no `azure-pipelines.yml`). The manual end-to-end
  (launch app → open CR3/JPEG/NEF visually) could NOT be performed on the
  locked-screen host — recorded as pending-manual, honestly.

## Deviations (all recorded)

1. **RAW fixtures are not bundled** (plan text suggested
   `Resources/TestFixtures/**` for everything): the ~1.2 GB Plan 05 CC0 RAW
   samples stay untracked at `.work/01-05/samples/` (repo bloat + CI
   checkout cost); tracked rasters (JPEG/HEIC/PNG/TIFF) ride in the test
   bundle. `Fixtures.swift` documents the two-tier strategy plus a
   three-tier path search: `LIGHTAMER_RAW_SAMPLES_DIR` env override →
   `~/Library/Application Support/Lightamer/TestRAW/` internal-disk mirror →
   repo checkout.
2. **The internal-disk mirror exists for a real environment constraint
   (new finding, recorded):** the repo lives on a USB volume
   (`/Volumes/UNITEK`, TCC *Removable Volumes* protected). An xctest agent
   whose responsible process lacks the grant blocks FOREVER inside
   `open()` when the screen is locked (the consent prompt cannot be
   presented) — diagnosed via sampled stacks stuck in `__open` on the
   fixture, reproduced twice, and eliminated by the internal-disk mirror.
   Shell processes (granted attribution) are unaffected. Machines wanting
   locked-headless runs must copy the RAW samples to an internal-disk path
   (or grant the volume permission and unlock).
3. **V50Order count assertion = 93, not "~76"** (inherited from Plan 04's
   verbatim `iop_order.c` port; the plan's estimate undercounted — test
   documents the source count).
4. **WebP raster case absent**: no WebP fixture in the Wave 0 list; the
   raster test covers JPEG/HEIC/PNG/TIFF and documents that WebP decode
   rides the same CGImageSource path.
5. **UITests blocked by host (locked screen), not code** — pending-manual in
   VALIDATION; not skipped-faked, not marked green.

## VALIDATION final state

`nyquist_compliant: true`, `wave_0_complete: true`, Sign-Off approved
(executor, 2026-09-16). Map: 12 of 14 rows ✅ green; 2 rows ⚠️
pending-manual (01-01-06 shell/dark-mode visual, 01-03-06 on-screen RAW
display) — both blocked solely by the locked GUI session; the underlying
automated evidence (build success, decode→pipe→texture renders in the perf
harness + Plan 03/04 smoke) is recorded in the rows. TODO.md Phase 1 marked
executed 6/6; `.planning/STATE.md` moved to `executed_pending_verify`.

## Handoff to Phase 2

- `01-PERF-BASELINE.md` is the comparison point for the cache fast-path
  (its §6 lists the four expected improvements).
- The three `API.md` files are the contract index to extend when adding
  `public` types.
- Phase 2 actions inherited from the baseline: `clearCaches()` on image
  switch, warm-up render-to-texture (first-write-empty defect), re-measure
  GFX lossless RAF on macOS 27.x, v9 downstream render cost check.
- Before closing Phase 1 manually: unlock the host and run
  `xcodebuild test -project Lightamer.xcodeproj -scheme Lightamer
  -destination 'platform=macOS'` (full suite incl. UITests), then do the
  three visual passes (shell, dark mode, File→Open CR3/JPEG/NEF).

# Plan 02-01 Summary — Tracer: issue #1 fix (D-X1) + CIContext warm-up spike + StableHash

**Status:** ✅ COMPLETE (2026-09-19) — all six tasks done; tracer UAT sequence green (9/9 display steps incl. stress cycles); unit suite 43/43 green (1 pre-existing skip).

> The plan executed with one checkpoint: Task 05 initially failed (black viewport on 2nd+ open) despite the D-X1 fix being verifiably correct. The coordinator authorized continuing the debug inside 02-01; the REAL root cause turned out to be SwiftUI `WindowGroup` window-per-odoc behavior — orthogonal to the planned render-path race, which WAS real and fixed as specified. Details in Task 05/06 below and LESSONS L012.

## Task results

### 02-01-01 — Unify the render path (D-X1) — commit `0c54a68`
- `EditorAreaView`: `.task(id:)` render trigger deleted; doc updated — display-only view restored.
- `EditorState`: `displayTextureRenderedForURL` deleted; `renderDisplayTexture` → `rerender(using:)` (no URL idempotence guard; doc names it the ONLY re-render entry, coordinator-facing from 02-03, never view-called). `load`'s decodeTask success path is the sole `displayTexture` writer (single-producer invariant documented on the property).
- Acceptance greps: no `.task(id:` in EditorAreaView, no `displayTextureRenderedForURL` in App/, 1 `func rerender`, 0 `renderDisplayTexture`.

### 02-01-02 — CIContext render-to-texture warm-up spike — `.work/plans/02-01/spike-render-leg.{swift,md}`
Headless harness (N=6 fresh contexts + controls), results:
- **Warm-up hypothesis REFUTED**: direct `render(_:toMTLTexture:)` is a **silent no-op** on this host — 0/6 non-empty cold AND 0/6 post-warm-up with an owned command buffer (0.0ms elapsed = CI enqueues no work), EMPTY with a real CIRAW-backed image, EMPTY even on a DEFAULT CIContext + rgba8Unorm + deviceRGB (option set ruled out). Phase 1's "first-render empty, second works" theory is revised: the direct path never works.
- **Decision: `bitmap`** — decode leg (and FULL) keeps `CIContextPool` bitmap+replace; the drag hot path is all-Metal regardless (research §5).
- Test B (bitmap leg): preview-2560 median **19.3ms**; full-60MP median **291–314ms**.
- Test C (decode-at-scale, Open Question #3): first CIRAW render at any scale costs seconds (11.2s cold compile) → **Phase 3 PREVIEW first-render needs a progress affordance**; scaled rendering gives NO reliable decode win (medians inverted; CIRAW re-executes with `cacheIntermediates:false`) — target-resolution input planes save **memory** (70MB vs 1.55GB), not decode time.

### 02-01-03 — Spike outcome applied — commit `a97ea65`
Bitmap branch: `CIContextPool` header rewritten — cites the spike file, quotes the decision verbatim, records 16–20ms PREVIEW / ~0.3s 60MP bitmap costs, notes direct-path re-test only on future macOS point releases. `API.md` Metal section carries the one-line decode-leg status. `MetalContext.renderToTexture` facade unchanged.

### 02-01-04 — StableHash — commit `376ddaa`
`LightamerCore/Sources/Foundation/StableHash.swift`: `public enum StableHash` — `fnvOffsetBasis`, `combine(_:_:)` (incremental fold), `hash(DataProtocol)` (region-wise), `hash(StringProtocol)` (UTF-8). Doc comments name the three consumers (PipeCacheKey 02-02, paramsHash/HistoryHash 02-05, sidecar drift 02-06) and the Swift-`Hasher` ban. `StableHashTests` (7): published vectors (`"foobar"`→`0x85944171f73967e8`, empty→`0xcbf29ce484222325`), distinctness, determinism, byte-order sensitivity, incremental==one-shot, string/Data agreement. `API.md` Foundation entry appended.

### 02-01-05 — Tracer UAT — checkpoint then GREEN
- First runs: (a) cold JPEG displayed ✅ but (b)/(c)/(d) black ❌ → CHECKPOINT (evidence in git history `ee48963` + `.work/plans/02-01/uat-results.md`).
- Coordinator authorized in-plan debug. Forensic instruments added then retired: `framebufferOnly=false` (made readback legal — dropped frames provably held image pixels), drawable-identity probe (reuse refuted), `commandBuffer.error` probe (zero errors), continuous-60fps mode (no change → ruled out present timing), view-identity probes (**10 `MTKView CREATE` for 9 opens** — the smoking gun).
- **ROOT CAUSE: SwiftUI `WindowGroup` opens a new window per odoc Apple Event on macOS 27.** Stacked windows raced the shared state; first-open worked only because launch-time opens are buffered into the first window.
- **Fix (commit `ac84596`)**: `WindowGroup` → single `Window("Lightamer", id: "main")` in `LightamerApp` (Phase 9 revisits multi-window Session management). Rerun: **9/9 display steps, `MTKView CREATE` = 1**.
- Continuous-draw detour REVERTED — paused mode (D-13) verified green with the single window; no power-consumption deviation shipped.
- Suites: `LightamerTests` 43/43 green. UITests not run (Phase 1 pending-manual environment precedent; assertions unaffected — tracer display proof carried by screenshots).

### 02-01-06 — D-X2 probe retirement — commit `88afa0c`
Gated on 05 green — executed: drawable 2×2 readback block, `drawProbe` logger + DRAW/UPDATE logs, drawable-identity probe, `MTKView CREATE` probe, `CB ERROR` probe, and the `framebufferOnly`/`maximumDrawableCount` diagnostic overrides all removed; `import os` dropped from the view. Grep clean (`DRAWABLE sample|drawProbe|RENDER skip|RENDER ok|RENDER FAIL` → 0). Kept: drawable-nil retry (correct paused-mode behavior), PSO-failure `AppError.logger` errors, structured `os.signpost` intervals (D-31), `EditorState` structured decode logs (`pixelpipe output ready:` — the UAT evidence channel). Post-cleanup: rebuild green + full UAT rerun green + eyes-on screenshot.

## Deviations from plan text (both coordinator-sanctioned)
1. Task 05/06 scope: the presentation-layer debug + `LightamerApp` single-`Window` fix landed inside 02-01 per the coordinator's ruling (tracer success = UAT green). The fix touches `LightamerApp.swift`, which was not in the plan's `files_modified`.
2. The D-13 "no behavior change to EditorMTKView" premise (research §5) was preserved in the end — the continuous-draw fallback was tested and reverted; final state keeps the Phase-1 paused blit exactly.

## Artifacts (as planned + extras)
- `LightamerCore/Sources/Foundation/StableHash.swift`, `Tests/LightamerTests/StableHashTests.swift`, `LightamerCore/API.md` — as planned.
- `App/Sources/Lightamer/UI/{EditorAreaView,EditorState,EditorMTKView}.swift`, `LightamerCore/Sources/Metal/CIContextPool.swift` — as planned.
- **Extra:** `App/Sources/Lightamer/UI/LightamerApp.swift` (single-`Window` root-cause fix).
- `.work/plans/02-01/`: `spike-render-leg.{swift,md}`, `uat-results.md`, `uat-sequence.sh` + `sample-png.swift` (reusable headless UAT harness), logs + screenshots (t1..t7/final evidence chain).
- `LESSONS.md` L012 (WindowGroup-per-odoc black-viewport pattern), `TODO.md` Phase 2 progress.

## Downstream handoffs
- **02-02** consumes `StableHash` + the single-producer `displayTexture` skeleton.
- **02-03** routes ALL re-renders through `EditorState.rerender(using:)`; decode leg = bitmap at target resolution (memory win, no decode-time win); progress affordance deferred to Phase 3 UX.
- **02-05/02-06** consume `StableHash` for history/sidecar hashing.
- Phase 9: multi-window returns via controlled Session windows, NOT WindowGroup odoc defaults (L012).

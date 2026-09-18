# Plan 02-03 — Manual resize verification (D-C3 anti-jitter, in-app)

- **Date:** 2026-09-19 03:34–03:39 (Apple M4, macOS 27.0, 1504×846pt display @2×)
- **Fixture:** `input/RAW/DSC09991.ARW` (60MP Sony A7R V, decoded via RAW 9)
- **Method:** osascript/AX window resizing is unavailable to headless drivers
  (`osascript` lacks the Accessibility grant: `“osascript”不允许辅助访问
  (-1719)`; the app's own `bounds` Apple Event times out — SwiftUI `Window`
  scenes carry no scripting dictionary). Per the D-X2 probe policy, a
  DEBUG-only `-la_resize_probe` launch argument drives the REAL geometry
  chain — `NSWindow.setFrame` → drawable resize → SwiftUI GeometryReader →
  `PipeCoordinator.drawableDidChange` — through a scripted sequence.
  **The probe retires after this verification** (D-X2: probes leave after
  the fix is proven).
- **Log channel:** `log stream --predicate 'subsystem == "com.kamasylvia.lightamer"' --level debug`

## Two bugs found and fixed BY the verification (before the passing run)

1. **Double-scaling** (run 1): the view multiplied point size by the
   backing scale before calling `PreviewBucket.longEdge(forDrawable:)`,
   whose contract is POINTS (it applies `pixelScale` itself). Every drawable
   double-scaled → every bucket pinned at the 2560 cap → no bucket could
   ever change. Fix: pass points (`EditorAreaView.sendDrawableGeometry`).
2. **Load-time bucket reconciliation** (run 2): the view's `onAppear`
   geometry input arrives before the decode finishes and was dropped by the
   `decoded != nil` guard, so the first PREVIEW rendered at the cap
   fallback and waited for a resize to correct. Fix:
   `PipeCoordinator.lastDrawableLongEdge` remembers pre-image inputs and
   `load` reconciles the bucket before its first render.

## Passing run (03:37:30–03:37:53, log excerpts)

| t | Event | Geometry input | Bucket decision | Re-render? | Evidence |
|---|-------|----------------|-----------------|------------|----------|
| 0.4s | launch + load | 621pt (onAppear, pre-decode, remembered) | 1120 (reconciled at load) | 1 (load render) | `render-scaled 747×1120 (scale 0.117845)` → `pixelpipe output ready: PREVIEW bucket 1120px` |
| t+6s | probe → 1460×920 | resize ANIMATION streams two snapshots: 673pt then ~745pt | 1120 (within, logged no-op) then 1480 (cross) | **0 for the within event; exactly 1 for the cross** | `drawable 673px within bucket 1120px — no re-render (D-C3)` + `render-scaled 987×1480` → `output ready: bucket 1480px` |
| t+14s | probe → 1000×700 | 621pt | 1480 → 1120 cross | **exactly 1 — and a PURE CACHE HIT** | `output ready: PREVIEW bucket 1120px (1 hits / 0 misses, 0 planes)` — the load-time 1120 planes were still cached; research §2.3's jitter-back-across-the-boundary hit, observed in-app |
| t+22s | probe → 990×695 | 621pt | 1120 (within) | **0** | `drawable 621px within bucket 1120px — no re-render (D-C3)` |

## Result vs the plan's acceptance

- **Within-bucket resize → 0 re-renders:** ✅ (two explicit
  `within bucket … — no re-render (D-C3)` debug lines; the t+6 step's
  within-snapshot rendered nothing).
- **Cross-bucket resize → exactly one re-render:** ✅ (one `render-scaled`
  + one `output ready` per crossing; the resize animation's intermediate
  snapshot still produced only ONE render for the step — the generation
  counter coalesces).
- **Jitter back across a boundary = cache hit, not a re-render** (research
  §2.3 bonus): ✅ observed at t+14 (`1 hits / 0 misses / 0 planes`).
- **PREVIEW drives the viewport via the coordinator (D-X1):** ✅ all
  `output ready` lines come from the `coordinator` category; no view-level
  render trigger exists (`grep -rn "\.task(id:" App/Sources/Lightamer/UI/`
  clean). Display visually confirmed: `.work/02-03/viewport-1120.png`
  (cropped screenshot: the 60MP ARW on screen at bucket 1120).

## Notes

- The load render reconciles to the window bucket, but if the window is
  still ANIMATING IN at first appearance, the remembered snapshot is
  mid-animation (this run: 1120 instead of the settled 1480) — the next
  geometry event corrects it, and the stale bucket's planes stay cached for
  the return (observed). Accepted: self-correcting, and the app ships no
  launch-time window animation of its own.
- FULL/THUMBNAIL were exercised by `MultiResolutionTests` + the headless
  smoke (`.work/02-03/smoke-run.md`), not by this GUI sequence (no zoom UI
  until Phase 4; no browser until Phase 9).

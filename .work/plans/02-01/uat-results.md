# UAT Results — Plan 02-01 Task 02-01-05 (tracer: issue #1 sequence) — FINAL GREEN

**Date:** 2026-09-19 00:43–01:45 · host macOS 27.0 / Apple M4 · Debug build (final: ac84596 + 88afa0c)
**Method:** headless — fresh `open -n` launch, odoc opens via `open -a Lightamer <file>`, `log stream --level debug` capture, `screencapture -x` at +1s after each `pixelpipe output ready`, pixel-sampled via `.work/02-01/sample-png.swift` (viewport region 640,200 → 1560×1300; canvas mat ≈ [25,22,22]). Harness: `.work/02-01/uat-sequence.sh`.

## Final run (single-`Window` fix, paused mode, probes retired)

| step | action | screen (screenshot @ +1s) | verdict |
|---|---|---|---|
| (a) | cold launch → open `DSC00012.jpg` | `shot-final-a-jpeg.png` | ✅ CONTENT DISPLAYED |
| (b) | open `DSC09991.ARW` | `shot-final-b-arw.png` | ✅ CONTENT DISPLAYED |
| (c) | reopen `DSC00012.jpg` | `shot-final-c-jpeg.png` | ✅ CONTENT DISPLAYED |
| (d) | 3× stress open/switch cycles (d2..d4) | `shot-final-d*.png` | ✅ ALL CONTENT DISPLAYED |

**SEQUENCE GREEN — canvas-verdicts=0/9.** Visual confirmation: `shot-final-d4-jpeg.png` shows the reopened JPEG (the original issue #1 failure scenario) fully rendered, single window. Each load logs exactly one `pixelpipe output ready:` (decodeTask = sole render producer); zero `RENDER skip|ok|FAIL` lines; `MTKView CREATE` count = 1 for the whole run.

## Root cause (discovered during the checkpoint→fix loop)

**SwiftUI `WindowGroup` opens a NEW WINDOW per odoc Apple Event on macOS 27.** The 9-open UAT sequence created **10 windows / 10 MTKViews** (view-identity probes). Each new window appeared over the one that actually displayed, its fresh `EditorMTKView` created while `displayTexture` was still nil mid-decode — the screen showed canvas frames stacked over the real image. First-open always worked because opens arriving during launch are buffered by `AppDelegate` and flushed into the FIRST window (`flushBuffered()`).

Evidence chain that pinned it:
1. D-X1 invariants all held (single producer, no `.task` race) — so the dual-render theory was NOT the visible mechanism.
2. `framebufferOnly=false` made the drawable readback legal → every dropped-frame drawable **provably contained the image**; zero `commandBuffer.error`; fresh drawable every frame (`DRAWABLE reuse=false`) → draw/present/GPU side fully innocent.
3. Continuous 60fps mode (candidate 4) did NOT help → not a present-timing issue → suspicion moved to the view/window layer.
4. View-identity probes: 10 `MTKView CREATE` for 9 opens, two views drawing in lockstep → SwiftUI tree/window proliferation → visual: two window title bars stacked in screenshots.
5. Fix `WindowGroup` → `Window` (single editor window, Phase 9 revisits multi-window): **9/9 steps display, 1 MTKView total**.

Hypotheses tested and refuted on the way (kept for the record): double-present/drawable-reuse (refuted by identity probe), command-buffer errors (zero), present-timing (refuted by continuous mode), draw storms (log multiplicity was a log-stream ×2 artifact).

## Verification state at close

- Manual-equivalent sequence (a)–(d): **green** (table above) — validated headless with screenshot pixel sampling + eyes-on screenshots; UX-equal to the manual sequence (odoc opens = same code path as File → Open).
- `LightamerTests`: **43 tests, 0 failures** (1 pre-existing skip) — exit 0.
- `LightamerUITests`: not run this session — Phase 1 pending-manual environment precedent (L011); three-column assertions exist and are unaffected by this plan's changes; the tracer's display proof is carried by the screenshots above.
- Probes (D-X2, Task 06): retired — `grep -rn "DRAWABLE sample|drawProbe|RENDER skip|RENDER ok|RENDER FAIL" App/` clean; `framebufferOnly`/`maximumDrawableCount` diagnostic overrides removed; structured `os.signpost` intervals (decode/pixelpipe/metal) survive; `EditorState.decodeLogger` structured logs (`pixelpipe output ready:`) survive as UAT evidence channel.

## Verdict

**PLAN COMPLETE** — Tasks 02-01-01..06 all done. Commits: 0c54a68 (D-X1), a97ea65 (bitmap decision), 376ddaa (StableHash), ee48963 (diagnostic probe), ac84596 (single-window root-cause fix), 88afa0c (probe retirement), b6b93c7+ (docs).

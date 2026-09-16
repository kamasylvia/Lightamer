# Phase 1 Performance Baseline

**Plan:** 01-06 Task 01-06-05 · **Recorded:** 2026-09-16 · **Owner:** GSD executor
**Machine:** Apple M4 (Mac mini, Mac16,10), 16 GB unified memory · macOS 27.0 (build 26A428) · Xcode 27.0 (27A266a) · Swift 6.4 · `recommendedMaxWorkingSetSize` = 12 124 MB
**Samples:** 13 real camera RAW files, CC0, **raw.pixls.us** (provenance + license: `.planning/spikes/spike-b-100mp-perf/samples/README.md`). Working copies untracked at `.work/01-05/samples/`; an internal-disk mirror for test runs lives at `~/Library/Application Support/Lightamer/TestRAW/` (the repo checkout sits on a TCC *Removable Volumes* USB volume — see 01-06-SUMMARY environment note).

> **Phase 1 is baseline-establishing, not budget-gating** (RESEARCH "Performance validation"; 01-CONTEXT D-32). Meeting the hard budgets is Phase 2's gate — the per-module per-ROI cache fast-path is the expected improvement lever. Every gap below is recorded so Phase 2 can be measured against it.

---

## 1. Method

Two measurement legs, both through public APIs only, both `os.signpost`-instrumented (D-31):

1. **Spike B raw-pipeline matrix** (Plan 05, `.planning/spikes/spike-b-100mp-perf/`): headless harness, one process per file, warm-up + n=5 steady-state runs (median/min/max); memory = `task_vm_info.phys_footprint` sampled every 10 ms; signpost log `com.kamasylvia.lightamer.spikeb`. Full detail in `spike-b-100mp-perf.md` §2.
2. **Real-app pipeline leg** (this plan, harness source `.work/01-06/perf-baseline.swift`): the actual Phase 1 chain — `RAWDecoder.decode` (signpost `decode`, Plan 02) → `RenderPipeline.render` → internal PixelPipe → float32 linear-Rec2020 display texture (signpost `pixelpipe`, Plan 04). Compiled against the app's built frameworks (`swiftc -F <DerivedData products>`), n=3 medians, same footprint probe. Six fixtures spanning 22–102 MP.

p95 is not reported for the app leg (n=3); Spike B's n=5 min/max spread carries the variance record. GPU-only kernel time was **not** separately captured headless (Instruments GPU trace stays a manual verification); the `pixelpipe` signpost bounds it, and Spike B measured the display blit directly (bitmap render + `texture.replace` = 4–6 ms at 1024×768).

---

## 2. Per-fixture results (app leg, this plan, n=3 medians)

| Fixture | MP | Decoder | decode med (cached) | pixelpipe med (first full-res float32 render) | decode+pipe total | footprint Δ during pipeline | Budget verdict (D-32) |
|---|---|---|---|---|---|---|---|
| Nikon Z8 NEF lossless | 45.4 | v8 | 65 ms | 598 ms | 658 ms | +192 MB | display ✗ pre-cache |
| Sony A7R V ARW lossless-c | 60.2 | **v9** | 76 ms | 3 286 ms | 3 378 ms | +61 MB | display ✗ pre-cache |
| Canon R10 CR3 | 24.0 | v8 | 67 ms | 532 ms | 603 ms | +318 MB | display ✗ pre-cache |
| Fujifilm X-T5 RAF lossless-c | 39.8 | **v9** | 54 ms | 2 438 ms | 2 492 ms | +393 MB | display ✗ pre-cache |
| Pentax DNG lossless | 22.1 | v8 | 34 ms | 177 ms | 211 ms | +113 MB | display ✗ pre-cache (closest) |
| **GFX100S RAF uncompressed** | **101.8** | v8 | 51 ms | 1 728 ms | 1 773 ms | **+1 563 MB** | display ✗ pre-cache; memory ✓ |

**App-leg observations:**

- The sub-100 ms "decode" column is the **app decode cache** (Plan 02's probe cache) serving repeat decodes of the same file — the real first-decode costs are the Spike B matrix below. Recorded as the Phase 1 baseline for the *cached* path.
- The `pixelpipe` leg is the whole cost of first display: it renders the lazy `CIRAW` chain through CIContext into the full-res float32 texture. **v9-decoded images render measurably slower downstream** (A7R V v9 3 286 ms vs Spike B's v8 848 ms float32 render on the same file; X-T5 v9 likewise) — RAW 9's CoreML-fused output costs more in the CI render leg. Phase 2 should measure v9-vs-v8 display cost per camera when wiring the cache.
- Process footprint grew to **5 364 MB** after the six fixtures in one process — reproducing Spike B's cache-accumulation finding in the *real* app pipeline (`CIContext.clearCaches()` on image switch is a hard Phase 2 requirement).

## 3. First-decode / display / frame matrix (Spike B, n=5 steady medians)

| Image | MP | decode+full render (med) | min / max | footprint peak (med / max) |
|---|---|---|---|---|
| Nikon Z8 NEF (lossless) | 45.4 | 345 ms | 335 / 355 | +88 / +283 MB |
| Sony A7R V ARW (lossless-c) | 60.2 | 763 ms (v8) / 766 ms (v9) | 754 / 829 | +2 / +398 MB |
| Hasselblad X2D 3FR | 102.1 | 833 ms | 811 / 877 | +480 / +616 MB |
| **GFX100S RAF (lossless-c)** | 101.8 | **20 894 ms** | 20 635 / 24 388 | +330 / +503 MB |
| GFX100S RAF (uncompressed) | 101.8 | 848 ms | 835 / 876 | — |
| Fujifilm X-T5 RAF lossless-c | 39.8 | 414 ms (v8) / 1 793 ms (v9) | — | — |

Display-path (Spike B §2.3): blit B (bitmap render + `texture.replace`, 1024×768) **4–6 ms**; blit A (`CIContext.render` → `MTLTexture`) 27–335 ms with the **first-call-in-process writes-empty** defect (reproduces Plan 03's macOS 27 finding at GM). Frame cost at 2560×1440 viewport: **cached plane 15.60 ms @ 102 MP (≈64 fps)**, 17.51 ms X2D, 8.50 ms A7R V, 6.73 ms Z8; **uncached** lazy-CIImage re-render 330–1 020 ms/frame (1–3 fps — catastrophic, hence the pixelpipe cache).

## 4. Verdict per D-32 hard budget

| Budget | Measured | Verdict |
|---|---|---|
| 100MP decode ≤ 2 s | Bayer 100MP: 833 ms; GFX 100MP uncompressed RAF: 848 ms; **GFX 100MP lossless-c RAF: 20.9 s (10× over)** | **PASS for Bayer + uncompressed RAF; FAIL for lossless-compressed GFX RAF** — the cliff is Apple's lossless-RAF decompressor at GFX width, not the pixel count (X-T5 lossless 40MP = 414 ms). Phase 2: re-measure on macOS 27.x point updates; consider preview-scale UX path for lossless RAF. |
| Display ≤ 500 ms (decode → drawable) | Cached display path: 4–6 ms blit. First display (this plan's `pixelpipe` leg): 211 ms – 3 378 ms; worst-case 100MP first display ≈ 0.9 s (Spike B) | **PASS for the cached display path; FAIL pre-cache** for ≥24 MP first render — expected Phase 1 shape; the Phase 2 per-module cache fast-path is precisely the lever this baseline exists to measure against. |
| Steady-state memory ≤ 4 GB | Single 100MP float32 plane: 1.55 GB alloc, 2.0–2.8 GB process peak. Multi-image session without `clearCaches()`: 4.3–4.8 GB (Spike B) / 5.4 GB (app leg, 6 files) | **PASS per-image; CONDITIONAL per-session** — budget holds only with `CIContext.clearCaches()` on image switch (Phase 2 action, already on the books). |
| Drag frame ≤ 16 ms @ viewport res | 15.60 ms @ 102MP cached (<1 ms headroom; 17/60 frames exceeded on M4), 6.7–8.5 ms @ 45–60MP; uncached 330–1 020 ms | **PASS with the pixelpipe cache; FAIL without it.** Thin 100MP margin → Phase 2 tiling/multi-resolution caching is a hard requirement (D-20 evidence, `spike-b-100mp-perf.md` §4). |

## 5. Signpost instrumentation (D-31)

Intervals live in four sources, all emitted on the app's `com.kamasylvia.lightamer` subsystem: `RAWDecoder.swift` (`decode`), `PixelPipe.swift` (`pixelpipe`), `CIContextPool.swift`, `MetalContext.swift` (dispatch). The numbers above were captured via `ContinuousClock` in the harnesses; **visual confirmation of the intervals in Instruments (Time Profiler / os_signpost) remains a manual verification** (VALIDATION "Manual-Only") — Instruments needs a GUI session, and this baseline was recorded on a locked-screen headless host (see 01-06-SUMMARY environment note).

## 6. What Phase 2's cache fast-path is expected to improve

1. **First-display (`pixelpipe` leg)** — 0.2–3.4 s today → target ≤ 500 ms by caching the decoded plane / terminal texture per (module, ROI) instead of re-rendering the lazy CIRAW chain.
2. **Per-frame drag** — already 15.6 ms @ 102MP from a cached plane; the cache fast-path must keep the per-frame path OFF the lazy chain (uncached = 1–3 fps).
3. **v9 display cost** — investigate the v9-downstream render penalty (3.3 s on A7R V) before locking RAW 9 as the per-camera default.
4. **Session memory** — `clearCaches()` on image switch keeps ≤ 4 GB; tiling/multi-resolution cache for > 60 MP or > 2 cached planes (D-20).

## 7. Honest caveats

- All numbers are steady-state medians on a warm page cache; cold-start (first touch after USB volume sleep) decodes ran up to 33× slower in Spike B — UX work must assume the cold number.
- The app leg ran while the host screen was LOCKED (no GUI session): Metal compute and CIContext are unaffected, but this host cannot currently run XCUITest or Instruments GUI — see 01-06-SUMMARY.
- n=3 (app leg) / n=5 (Spike B); medians only for the app leg, min/max recorded in Spike B. No number here is synthesized; every row traces to a logged run (`/tmp` transcripts of 2026-09-16 for the app leg; tracked `spike-b-*.txt` for Spike B).

# Plan 02-03 — Headless smoke run (multi-resolution on a real RAW)

- **Date:** 2026-09-19 · **Harness:** `.work/02-03/smoke.swift` (01-04 pattern,
  swiftc against DerivedData Debug frameworks, `#if DEBUG`-free public surface)
- **Fixture:** `input/RAW/DSC09991.ARW` — 6336×9504 (60MP), decoded via RAW 9

## Result: SMOKE PASS (11/11)

```
PASS  0. 60MP-class fixture decoded
PASS  1a. PREVIEW long edge == 2560 (1707x2560)      ← scale-at-entry, D-C3 bucket
PASS  1b. PREVIEW pixels finite
PASS  1c. PREVIEW non-black (mean 0.311)
PASS  2a. FULL == extent (6336x9504)                 ← scale 1.0 on-demand
PASS  2b. FULL finite + non-black (mean 0.308)
PASS  2c. FULL caches input+final only (misses 2)    ← 02-02 lock #4 per-resolution
PASS  3. THUMBNAIL long edge == 360 (240x360)        ← fixed defaultLongEdge
PASS  4. EXPORT typed .notImplemented                ← Phase 11 placeholder
PASS  5. cache byte-accounting live (2069557248 bytes)
```

## Notes

- Memory statement: one PREVIEW (bucket 2560) + one FULL + one THUMBNAIL of a
  60MP image hold ≈ 2.07 GB in the shared `PipeCache` (FULL input+final =
  2 × 963MB; PREVIEW set ≈ 210MB) — under the 3 GB D-C1 budget, and exactly
  the spike-b plane-multiplication scenario the FULL no-intermediate-cache
  policy exists for.
- Harness gotchas hit (both recorded in code comments): pixel probes need a
  queue DRAIN after the pipe returns (dispatches are committed without
  waiting — same-queue ordering is the only pipe-side guarantee), and
  `addCompletedHandler` must precede `commit()` (L008's sibling).
- Same imageID + shared cache across all four resolutions — PREVIEW/THUMBNAIL
  key separation proven separately in `MultiResolutionTests`.

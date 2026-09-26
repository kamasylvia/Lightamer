---
phase: 1
plan: 05
status: complete
completed: 2026-09-16
duration: one executor session
commits:
  - 2273f1e docs(01-05): spike A report — CIRAW 9 GM capability boundary
  - d3b3cb7 docs(01-05): spike B report — 100MP performance vertebra
  - (this commit) docs(01-05): plan summary + spike back-port notes + TODO wave-2 status
---

# Plan 01-05 — Summary

Both Phase 1 capability spikes executed on **macOS 27.0 official (26A428)**,
Apple M4 / 16 GB, Xcode 27.0 — with **13 real camera RAW samples** (CC0,
raw.pixls.us, ~1 GB downloaded; all five sensor families; zero fabricated
files). Reports: `spike-a-ciraw9-boundary.md` + `spike-b-100mp-perf.md`
(this directory); durable artifacts (probe/harness sources, raw outputs,
golden samples, provenance READMEs) under `.planning/spikes/spike-a-*` and
`.planning/spikes/spike-b-*`.

## Execution-form deviation (documented, per coordinator protocol)

The plan specified standalone Tuist spike apps on branches
`spike/ciraw9-boundary` + `spike/100mp-perf`. Since Plans 01-04 already
delivered the real verification apps + smoke-harness pattern, the spikes ran
as **headless public-API-driven Swift harnesses** (same pattern, zero
Lightamer dependencies) under `.work/plans/01-05/`, with tracked copies + raw
outputs + golden samples committed under `.planning/spikes/`. No spike
branches were created; D-06's intent (verification code preserved, reports
versioned, main app untouched) is met. Zoom/pan in Spike B is a measured
per-frame viewport-cost proxy, not an interactive MTKView session (labeled
as such in the report).

## Headline findings

**Spike A — CIRAW 9 boundary (GM evidence, replaces research assumptions):**
- **RAW 9 covers only 69 camera models at GM** (v8: 465). GFX100S, X100VI,
  X-H2S, Nikon Z8, OM-1 II, X2D, Canon R10 are **NOT** v9-capable at GM —
  D-22's fallback fires for most target bodies. Only X-T5/X-T50 among Fuji.
- WWDC26/305 no-op NR keys **confirmed twice over**: `colorNoiseReduction`,
  `detail`, `moire` flags drop to UNSUPPORTED under v9; `luminanceNR`
  keeps its flag but is pixel-proven inert under v9.
- **Phase One IQ4 150MP IIQ is not decodable by CIRAWFilter at all**
  (`[None]`, 0×0) — first concrete case for the deferred libraw fallback.
- ProRAW `semanticSegmentationSkyMatte` observed present on an iPhone 12 Pro
  DNG (mattes are capture-dependent, L004 stands).
- Setting `decoderVersion = .version9` on an unsupported file **silently
  clamps** (no throw) — `decoderVersionUsed` must always be recorded.
- Golden 100% crops: v8 X-Trans shows visible maze artifacts on diagonal
  edges; v9 (X-T5) is cleaner; Bayer base-ISO clean in both.

**Decision recommendation (user decides at phase verification):** do NOT
make the per-method demosaic menu a v1 hard requirement (Bayer base-ISO is
clean; Apple default per D-22 for v1). Schedule the X-Trans Metal port as
the first Phase 3 backlog candidate — it is the only family with a measured
quality gap, and GFX/X100VI/X-H2S are stuck on v8 at GM.

**Spike B — 100MP vertebra (steady-state medians, n=5):**
- Decode: Bayer 100MP (X2D 3FR) **833 ms**, A7R V 60MP **763 ms**, Z8 45MP
  **345 ms** — all within the 2 s budget. **GFX100S lossless-compressed RAF
  = 20.9 s (10× over budget)**, isolated to Apple's lossless-RAF
  decompressor: the same 101.8MP sensor decodes in **848 ms uncompressed**.
- RAW 9 does NOT speed up full-size decode at GM (A7R V v9≈v8; X-T5 v9
  4.3× slower than v8).
- Memory: 100MP float32 RGBA plane (1.55 GB) fits; peak 2.0–2.8 GB with CI
  overhead; `cacheIntermediates: false` validated (CIRAW-4 closed). New
  requirement: `clearCaches()` on image switch (footprint drifts to
  4.3–4.8 GB without it; one CI SIGSEGV under accumulated pressure).
- Display: render-to-MTLTexture **first-use writes empty** (reproduced 6/6
  processes — refines Plan 03's GM finding); bitmap+`replace` = 4–6 ms.
- Frames: cached-plane path **15.6 ms @ 100MP (≈64 fps)**, 6.7–8.5 ms at
  45–60MP; uncached lazy-CIImage path 330–1020 ms/frame (lazy CIImage is
  not a frame cache — Phase 2 pixelpipe cache is what buys 60fps).

**Decision recommendation (user decides): D-20 confirmed for Phase 1** (no
tiling needed to decode+display 100MP). Phase 2 must treat tiling /
multi-resolution caching as a **hard requirement**: <1 ms frame-budget
headroom at 100MP, and the per-module cache's plane multiplication crosses
the 4 GB budget at ~2–3 cached planes. Recorded threshold suggestion:
untiled full-res float32 up to ~60MP with ≤3 planes; tile beyond that.

## Task 01-05-03 (downstream feeding)

- `01-RESEARCH.md` §2 appended `2.a Spike A back-port` (9 items) and §3
  appended `3.a Spike B back-port` (5 items) — append-only, per plan.
- `01-CONTEXT.md` / `STATE.md` NOT changed: D-20 was confirmed, not
  overturned (the plan's escalation condition targets a D-20 overturn).
  The Phase 2 hard-requirement evidence lives in the Spike B report +
  RESEARCH §3.a for Phase 2 planning to consume.
- `ROADMAP.md` NOT changed: Spike A did NOT expand Phase 3 scope to v1-hard
  (the plan's edit condition was not met); the demosaic-menu recommendation
  is recorded in the Spike A report for the phase-verification decision.
- Plan 02's `RAWDecoder` needs **no code change** (its probe+fallback
  pattern is validated by GM data); the `supportedCameraModels(with:)`
  fast-path is noted for a future polish, not a defect.

## Verification (plan-level criteria)

| Criterion | Result |
|---|---|
| Spike A capability table + API evidence + decision | ✅ report §2-§5 (13 files, all 5 families) |
| Spike B measured numbers vs D-32 + D-20 evidence | ✅ report §2-§4 (5-run medians + isolation runs) |
| Sample provenance documented | ✅ `samples/README.md` in both spike dirs (CC0, per-file URLs) |
| Golden samples checked in | ✅ 13 crops (spike A) + 4 viewport PNGs (spike B) |
| os.signpost intervals | ✅ both harnesses (`com.kamasylvia.lightamer.spikea/spikeb`) |
| Reports committed | ✅ 2273f1e (A), d3b3cb7 (B) |
| No fabricated data | ✅ every number from `.work/plans/01-05/*.txt` raw outputs; anomalies/crashes disclosed in report §5 |

## Known leftovers

- IQ4 150MP sample = Plan 06 fixture candidate for the unsupported-RAW
  typed-error path (CIRAW returns `[None]`).
- GFX lossless-RAF decode cost should be re-measured on macOS 27.x point
  updates (Apple may fix the decompressor).
- Corner-crop lens-correction behavioral check (center crop shows no change
  by design) — cheap follow-up when a GUI spike is next open.

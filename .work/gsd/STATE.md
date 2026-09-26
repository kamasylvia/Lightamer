---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: Phase 1 — Foundation, App Skeleton & Capability Spikes
status: complete
stopped_at: Phase 4 context gathered (autonomous YOLO decisions)
last_updated: "2026-09-19T23:30:54.637Z"
progress:
  total_phases: 4
  completed_phases: 3
  total_plans: 18
  completed_plans: 18
---

# Project State: Lightamer

**Last updated:** 2026-09-16
**Current phase:** Phase 1 — Foundation, App Skeleton & Capability Spikes
**Status:** complete (UAT closed 2026-09-18: 5 pass + 1 partial; issue #1 reclassified as multi-window presentation contention → Phase 2 backlog)

## Roadmap Snapshot

- **Phases:** 13
- **Granularity:** fine
- **Mode:** standard (Horizontal Layers)
- **Total v1 requirements:** 123
- **Mapped:** 123 (100%)
- **Completed phases:** 1 / 13 (Phase 1 UAT closed; next: Phase 2 Pixelpipe Core)

## Phase Progress

| # | Phase | Status | Requirements |
|---|-------|--------|--------------|
| 1 | Foundation, App Skeleton & Capability Spikes | executed_pending_verify | 11 |
| 2 | Pixelpipe Core, Color Management & History Stack | pending | 8 |
| 3 | Tone & Filmic iops | pending | 10 |
| 4 | Geometry, Lens & Detail iops | pending | 8 |
| 5 | Color & Denoise iops | pending | 12 |
| 6 | Layers & Masking System | pending | 14 |
| 7 | AI Modules (Native Vision Masking & Retouching) | pending | 4 |
| 8 | HDR/Stacking & Effects iops | pending | 10 |
| 9 | Capture One Session Management | pending | 8 |
| 10 | yiyin Border/Watermark Panel | pending | 8 |
| 11 | Export Pipeline & Batch Queue | pending | 8 |
| 12 | Metadata, Rating, Presets & LUT | pending | 11 |
| 13 | System Integration & Distribution | pending | 11 |

## Active Context

### Current Phase (Phase 1)

- **Goal:** Stand up the macOS 27 native app, Metal dispatch framework, CIRAW 9 RAW decode, the `IOPModule` protocol + `v50_order` table, and an MTKView viewport blitting a decoded RAW. Resolve the CIRAW 9 capability boundary and 100MP Metal performance vertebra — these determine v1 iop scope.
- **Requirements:** FOUND-01, FOUND-02, FOUND-03, FOUND-05, FOUND-06, FOUND-07, RAW-01, RAW-02, RAW-04, RAW-05, RAW-06
- **Spikes (run here):** CIRAW 9 vs RAW 8 capability boundary (done — `spike-a-ciraw9-boundary.md`); 100MP Metal performance (done — `spike-b-100mp-perf.md` + `01-PERF-BASELINE.md`); preliminary filmicrgb port feasibility; preliminary raw denoise profiling.
- **Locked decisions (per research):** macOS 27 floor; linear Rec2020 scene-referred working space; float32 RGBA premultiplied-alpha pipe buffers; `v50_order` module ordering; Metal-first pipe with CIRAW strictly as decoder; Lightamer-own-format sidecar (NOT Darktable-binary-compatible).
- **Execution state (2026-09-16):** Plans 01-06 all executed and committed. LightamerTests green (36 executed / 1 skip / 0 failed). Pending-manual (host screen locked during execution): XCUITest run, on-screen shell/viewport visual, Instruments signpost view — see `01-VALIDATION.md` and `01-06-SUMMARY.md`.

### Phase Build Order (dependency-driven)

Foundation (1) → Pixelpipe core + history (2) → Tone/Filmic (3) → Geometry/Detail (4) → Color/Denoise (5) → Layers/Masking (6) → Native AI Modules (7) → HDR/Effects (8) → Session (9) → yiyin (10) → Export (11) → Metadata/Presets/LUT (12) → System/Distribution (13).

## Decisions Log

- 2026-09-16 (Plan 05): D-20 evidence recorded — tiling deferred is correct for Phase 1; Phase 2 must treat tiling/multi-resolution caching as a hard requirement (see `spike-b-100mp-perf.md` §4).
- 2026-09-16 (Plan 05): demosaic algorithm menu NOT a v1 hard requirement (CIRAW 8/9 boundary; user phase-verification call recorded in 01-05-SUMMARY).

---
*Initialized: 2026-08-03 after roadmap creation*
*Updated: 2026-08-03 — Phase 7 rescoped to native-only AI (4 reqs); AI-02/03/04 moved to v2*
*Updated: 2026-09-18 — Phase 1 UAT closed (executed_pending_verify → complete); next Phase 2*

## Session

**Last session:** 2026-09-19T23:30:54.294Z
**Stopped at:** Phase 4 context gathered (autonomous YOLO decisions)
**Resume file:** .planning/phases/04-geometry-lens-detail-iops/04-CONTEXT.md

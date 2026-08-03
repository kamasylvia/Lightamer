---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: Phase 1 — Foundation, App Skeleton & Capability Spikes
status: not_started
stopped_at: Phase 1 context gathered
last_updated: "2026-08-03T15:29:34.142Z"
progress:
  total_phases: 1
  completed_phases: 0
  total_plans: 6
  completed_plans: 0
---

# Project State: Lightamer

**Last updated:** 2026-08-03
**Current phase:** Phase 1 — Foundation, App Skeleton & Capability Spikes
**Status:** not_started

## Roadmap Snapshot

- **Phases:** 13
- **Granularity:** fine
- **Mode:** standard (Horizontal Layers)
- **Total v1 requirements:** 123
- **Mapped:** 123 (100%)
- **Completed phases:** 0 / 13

## Phase Progress

| # | Phase | Status | Requirements |
|---|-------|--------|--------------|
| 1 | Foundation, App Skeleton & Capability Spikes | not_started | 11 |
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
- **Spikes (run here):** CIRAW 9 vs RAW 8 capability boundary; 100MP Metal performance; preliminary filmicrgb port feasibility; preliminary raw denoise profiling.
- **Locked decisions (per research):** macOS 27 floor; linear Rec2020 scene-referred working space; float32 RGBA premultiplied-alpha pipe buffers; `v50_order` module ordering; Metal-first pipe with CIRAW strictly as decoder; Lightamer-own-format sidecar (NOT Darktable-binary-compatible).

### Phase Build Order (dependency-driven)

Foundation (1) → Pixelpipe core + history (2) → Tone/Filmic (3) → Geometry/Detail (4) → Color/Denoise (5) → Layers/Masking (6) → Native AI Modules (7) → HDR/Effects (8) → Session (9) → yiyin (10) → Export (11) → Metadata/Presets/LUT (12) → System/Distribution (13).

## Decisions Log

(To be updated at phase transitions and milestone boundaries.)

---
*Initialized: 2026-08-03 after roadmap creation*
*Updated: 2026-08-03 — Phase 7 rescoped to native-only AI (4 reqs); AI-02/03/04 moved to v2*

## Session

**Last session:** 2026-08-03T14:46:44.607Z
**Stopped at:** Phase 1 context gathered
**Resume file:** .planning/phases/01-foundation-app-skeleton-capability-spikes/01-CONTEXT.md

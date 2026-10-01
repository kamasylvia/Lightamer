---
gsd_state_version: 1.0
milestone: M2
milestone_name: Alcedo V1 (2026-09-27 project redefinition)
current_phase: M2-9 — Export Options Alcedo-fication (next: discuss/research drafting)
status: M2-8 complete (VALIDATION signed 2026-10-02); M2-9 next
last_updated: "2026-10-02T00:00:00.000Z"
progress:
  total_phases: 16
  completed_phases: 12
  total_plans: 140
  completed_plans: 128
  m2_phases_total: 12
  m2_phases_complete: 9
---

# Project State: Lightamer

**Last updated:** 2026-10-02
**Current phase:** M2-9 — Export Options Alcedo-fication (M2-8 validated; discuss/research drafting is the next action)
**Status:** Milestone 1 Phases 1-12 complete / 13 in progress (historical record); Milestone 2: M2-0..M2-8 complete (M2-8 VALIDATION signed 2026-10-02, terminal suite 2577/16skip/0fail), M2-9 next

## Completion Ledger

| Phase | Name | Status | Terminal tests |
|---|---|---|---|
| 1 | Foundation, App Skeleton & Capability Spikes | complete (UAT closed 2026-09-18) | 36→282 (Phase 2 baseline) |
| 2 | Pixelpipe Core, Color Management & History Stack | complete (2026-09-19/20; 6 plans accepted) | 282/3skip/0fail |
| 3 | Tone & Filmic iops | complete (2026-09-23; 6 plans accepted) | 267/3skip/0fail |
| 4 | Geometry, Lens & Detail iops | complete (2026-09-23; accepted) | 355/0skip/0fail |
| 5 | Color & Denoise iops | complete (2026-09-23; 8 plans accepted) | 609/3skip/0fail |
| 6 | Layers & Masking System | complete (2026-09-24; 7 plans accepted) | 788/3skip/0fail |
| 7 | AI Modules (Native Vision) | complete (2026-09-24; 3 plans accepted) | 845/6skip/0fail |
| 8 | yiyin Border/Watermark Panel | complete (2026-09-25; 3 plans accepted) | 973/6skip/0fail |
| 9 | Capture One Session Management | complete (2026-09-27 UAT exemption; 5 plans accepted) | 1437/6skip/0fail |
| 10 | yiyin Border/Watermark Panel (executed as Phase 8) | complete (merged into Phase 8 execution) | — |
| 11 | Export Pipeline & Batch Queue | complete (2026-09-27 UAT exemption; 5 plans accepted) | 1437/6skip/0fail |
| 12 | Metadata, Rating, Presets & LUT | complete (2026-09-27; 5 plans accepted, terminal verification pending UAT exemption) | 1437/6skip/0fail |
| 13 | System Integration & Distribution | complete (13-VALIDATION signed 2026-09-28; scope revised — Apple distribution channel cut per user ruling) | 1553/9skip/0fail |
| 14 | MCP Server | complete (14-VALIDATION signed 2026-09-28) | 1553-era |
| 15 | Performance | merged into M2-11 (ROADMAP M2 era) | — |
| 16 | Catalogs Mode | complete (16-VALIDATION signed 2026-09-27) | 1553/9skip/0fail |

## Milestone 2 Ledger (Alcedo V1 — 2026-09-27 redefinition)

| Phase | Name | Status | Terminal tests |
|---|---|---|---|
| M2-0 | Survey & spec (ALCEDO-FEATURE-MAP) | complete (2026-09-27; D1-D6 signed "all per recommendation") | — |
| M2-1 | dt feature-flag disable | complete (executed + accepted) | — |
| M2-2 | Library & project model (Alcedo way) | complete (executed + accepted) | — |
| M2-3 | UI shell redesign (Alcedo clone) | complete (P1..P4; full-suite baseline cited 2160/14skip/0fail @ M2-3-3 R2) | 2160/14skip/0fail |
| M2-4 | Node editing model | complete (M2-4-0..3; phase-level `M2-4-ACCEPTANCE.md`) | 2240/14skip/0fail |
| M2-5 | Color Grade control set | complete (M2-5-1..3; M2GRADE all Delivered) | 2327/16skip/0fail |
| M2-6 | DRT: ACES 2.0 + OpenDRT | complete (M2-6-1..3; M2DRT all Delivered) | 2464/16skip/0fail |
| M2-7 | Masking system (Alcedo + Nitro) | complete (M2-7-1..3; M2MASK all Delivered) | 2525/16skip/0fail |
| M2-8 | Versions & History (mini-git) | **complete (VALIDATION signed 2026-10-02; 3 plans accepted; both error-level walkthrough findings fixed & re-verified — `phases/m2-8-versions/M2-8-VALIDATION.md`)** | **2577/16skip/0fail** |
| M2-9 | Export Options Alcedo-fication | **next** (discuss/research drafting) | — |
| M2-10 | AI library features | scoped | — |
| M2-11 | Performance + closeout | scoped | — |

## Notes

- Phase 9/11/12 UAT: user exemption 2026-09-27（四期翻转一句话豁免；材料全齐：09-UAT.md 12 pass/3 skip/0 真缺陷 + 各 VALIDATION validated）。
- Phase 10 (yiyin) was executed as Phase 8 (execution-order 08 = ROADMAP §Phase 10).
- Phase 16 backend ruling: v1 = local SQLite (user 2026-09-27); pg = v2 evaluation item.
- push: local-only per user instruction (~370+ commits ahead of Azure DevOps origin; GitHub repo not yet created — 13-4 DIST-01).

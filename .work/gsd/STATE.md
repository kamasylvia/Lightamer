---
gsd_state_version: 1.0
milestone: M4
milestone_name: Raster & Masks, narrowed (RAW + TIFF only; 2026-10-10 chartered from V2/Maintenance station plan B items)
current_phase: M4 chartered（M4-0 closed by charter batch 2026-10-10——五正本落账 + pack 政策 B 证据分仓同批执行）；next: M4-1 TIFF 栅格开发链 research
status: M4 chartered 2026-10-10（范围收窄 = RAW + TIFF only，2026-10-08 用户裁决；EXR/JPEG/PNG 移出）；M3 milestone closed 2026-10-10（omp 回溯 16/16 PASS 门清，夜间授权在案）；M3-4 closed 2026-10-10 (dual acceptance zcode PASS + omp FAIL→fix d8d72d9→reverify PASS; terminal 3174/16/0); M3-1 closed 2026-10-08 (terminal 3024/16/0); M3-2 closed 2026-10-08; M2 closed 2026-10-07 (terminal 2961/16/0)
last_updated: "2026-10-10T23:30:00.000Z"
progress:
  total_phases: 16
  completed_phases: 14
  total_plans: 145
  completed_plans: 145
  m2_phases_total: 12
  m2_phases_complete: 12
  m3_phases_total: 5
  m3_phases_complete: 5
---

# Project State: Lightamer

**Last updated:** 2026-10-10
**Current phase:** **M4 chartered（栅格与蒙版·收窄版，2026-10-10 charter 批立项）**——范围收窄 = RAW + TIFF 编辑（2026-10-08 用户裁决；RASTER-IN-01 收窄 TIFF only，EXR/JPEG/PNG 移出；ALCE-02 随 RASTER-IN 推迟）。M4-0 闭环 = charter 五正本落账（ROADMAP §Milestone 4 + REQUIREMENTS 注记 + 本文件 + TODO 头部 + GOAL-STATE 续接点）+ pack 政策 B 证据分仓同批执行（evidence 仓 `lightamer-evidence` ADO 私有 + 主仓 filter-repo 剥证据大对象，终值见 GOAL-STATE）。next: M4-1 research（M3 已 closed：M3-0..M3-4 全 5 phase complete，M3-4-02 VALIDATION signed 终验 `TOTAL|3174/16/0|1470s`——`phases/m3-4-latitude/M3-4-02-VALIDATION.md`；closure 门 2026-10-10 夜收官批翻正 = OMP-RETRO-QUEUE 16 项 omp 回溯 16/16 PASS〔checkpoint `81114d4`→`5f6860d`〕；「全史瘦身手术第二次」预检证伪停手后由 pack 政策 B 证据分仓接替——见 GOAL-STATE 手术队列行与续接点）
**Status:** Milestone 1 Phases 1-16 = 历史记录；Milestone 2 **closed**（M2-0..M2-11 全 complete；M2-11 VALIDATION 兼收口 signed 2026-10-07，终验 TOTAL|2961/16/0|1081s 干净绿；挂账移交 = `phases/m2-11-performance/M2-11-VALIDATION-INPUT.md` §4.4 单一清单）；**Milestone 3 = closed（2026-10-10 全 5 phase complete + 门清翻正）**（M3-1 closed 2026-10-08 终态 3024/16/0 → M3-2 closed 2026-10-08 → M3-3 三波闭环 3152/16/0 → M3-4-01 双验收 + M3-4-02 VALIDATION 终态 **3174/16/0**；翻账正本 = `phases/m3-4-latitude/M3-4-02-VALIDATION.md`——SC 三列 M3-0..M3-4 全相 Delivered + 挂账单一清单总汇编 Maintenance M1-M7 / V2 V1-V12 / 手术前置 S1-S2；**「milestone closed」名分 2026-10-10 夜由收官批翻正生效**〔omp 回溯 16/16 PASS，checkpoint `81114d4`→`5f6860d`〕，晨审可推翻）；**Milestone 4 = chartered（2026-10-10）**——M4-1 TIFF 栅格开发链 / M4-2 Follow Edges V2 换锚重做 / M4-3 Depth 蒙版，wave 序 = M4-1 research 起

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
| M2-9 | Export Options Alcedo-fication | **complete (VALIDATION signed 2026-10-03; 5 plans accepted; M2EXP-01..05 all Delivered with five annotation obligations; zero error-level findings — F-2 minor walkthrough finding fixed & re-verified in acceptance batch `afb1f88`; pending items: F-1 Import crash / SidecarV5 hygiene / L055 script / collision-tier selector — `phases/m2-9-export/M2-9-VALIDATION.md`)** | **2693/16skip/0fail** |
| M2-10 | AI library features | **complete (VALIDATION signed 2026-10-07; 7 plans accepted; M2AI-01..10 all Delivered — flip ledger carried by `de68703`, zero error-level findings across six acceptance rounds; minor ×3 fixed in acceptance batches `6f768c0`/`ede45f8`/`b766cf5` + 06 memory M-1 closed by `c573087`; 07 execution batch closed by continuation worker after predecessor death — D16; SidecarV5 ANE flake five-wave ledger closed, environment attribution — `phases/m2-10-ai-library/M2-10-VALIDATION.md`)** | **2955/16skip/0fail** |
| M2-11 | Performance + closeout | **complete — M2 milestone closed** (VALIDATION 兼收口 signed 2026-10-07 — `phases/m2-11-performance/M2-11-VALIDATION.md`; five plans accepted; M2PERF-01/02 + M2DRT-06 + M2NODE-03 Delivered via closeout flip; terminal round `TOTAL|2961/16/0|1081s` clean green after recovery protocol — ToneEqual latent crash family + L057-family LUT-import SIGSEGV registered with .ips evidence, ownership to morning review; red-line domains zero diff; PERF-07 0.543s in-band; GUI round four meanings done — zoom/pan hitch >50ms = 0 live, O-2 8557MB reproduced; backlog single list = VALIDATION-INPUT §4.4) | **2961/16skip/0fail** |

## Milestone 3 Ledger (Film Darkroom — 2026-10-08 chartered, V2 station plan A)

| Phase | Name | Status | Terminal tests |
|---|---|---|---|
| M3-0 | Charter & station spec | **complete** (2026-10-08: V2 proposal `4f84351` + OQ-V2-1..10 all-recommendations ruling `6e265ee`; five ledgers updated — ROADMAP M3 block / REQUIREMENTS → M3 marks + FSIM-01a..d drafts / STATE / GOAL-STATE append-only continuation / TODO header; M3-1 discuss/research/plan/execute subsequently delivered, charter discharged) | — |
| M3-1 | W1 lead batch: M2GRADE-08 + YIYIN-09 + small-items family (zh cleanup / collision-tier selector / peak-ICC / denoise drag-down semantics) | **complete (VALIDATION signed 2026-10-08, night-autobatch authorization on record — `phases/m3-1-w1/M3-1-VALIDATION.md`; 3 plans accepted, all PASS / 0 error; M2GRADE-08 + YIYIN-09 + small-items Delivered with M2-9 backlog#4 closed; backlog single list = VALIDATION 挂账总汇编 seven items led by L057 panel-family hardening; morning review may overturn)** | **3024/16skip/0fail** |
| M3-2 | FSIM research round (+ M7 spike + FSIM-03 note riders) | **complete** (2026-10-08: RESEARCH-NOTES 定稿 `b4049b8` + OQ-M3-2-1..7 all-recommendations user ruling `e02dcc7` + M7 RAF warm-bimodal spike adjudicated — bench sampling-window artifact + idle-decay effect, steady RAF 14-19ms / ARW 12.3-15.6ms deterministic, no pipeline defect; verdict + data = `phases/m2-11-performance/perf.md` §O-1 SPIKE, evidence pack = `phases/m3-2-fsim-research/evidence/`; probe zero production diff, night-relay authorization on record) | — |
| M3-3 | FSIM-01 two-stage film simulation (stage model + auto printing-filter solve + Y/M offsets) | **complete** (three waves 2026-10-08/09, all accepted PASS / 0 error — 01 data foundation: FilmRecord + CC BY-SA asset quintet + solver + sidecar v9; 02 pipeline: film sub-run seam + fused kernel + print bake + filmPlacement op + export seam; 03 golden four gates + m=1 shadow sign production fix + determinism suite five + Film panel/readonly card; terminal 3152/16/0 = 03 full-suite verified; VALIDATION carried by M3-4 signoff batch per plan) | **3152/16skip/0fail** |
| M3-4 | FSIM-02 latitude panel + M3 VALIDATION closeout | **complete — M3 milestone closed（gate cleared, flipped 2026-10-10 night closeout batch）** (2026-10-10: M3-4-01 dual acceptance — zcode PASS/0E+3obs + omp FAIL→fix `d8d72d9`→OMP-REVERIFY PASS〔dual-acceptance first live run〕; M3-4-02 VALIDATION signed 2026-10-10 night-autobatch — `phases/m3-4-latitude/M3-4-02-VALIDATION.md`; M3 full-phase SC three-column reconciliation all Delivered + SC numeric gate met; backlog single list = Maintenance M1-M7 + V2 V1-V12 + surgery-precondition S1-S2; **milestone "closed" title flips only after OMP-RETRO-QUEUE 16 items all-PASS (user directive a2d3c0a, main-session serial sweep) → then history-slim surgery triggers**〔→ 已翻正（2026-10-10 夜）：16/16 PASS，checkpoint `81114d4`→`5f6860d`，「closed」名分生效；手术预检证伪停手——GOAL-STATE 手术队列行〕) | **3174/16skip/0fail** (M3 terminal) |

## Notes

- Phase 9/11/12 UAT: user exemption 2026-09-27（四期翻转一句话豁免；材料全齐：09-UAT.md 12 pass/3 skip/0 真缺陷 + 各 VALIDATION validated）。
- Phase 10 (yiyin) was executed as Phase 8 (execution-order 08 = ROADMAP §Phase 10).
- Phase 16 backend ruling: v1 = local SQLite (user 2026-09-27); pg = v2 evaluation item.
- Milestone 3 chartered 2026-10-08 per V2/Maintenance station proposal plan A (film darkroom); OQ-V2-1..10 all-recommendations pre-ruling (user can overturn at any time). Plan B (RASTER-IN-01 / IOP-MASK-06 V2 / IOP-MASK-07) rolls to M4; ALCE-02/03 (EXR / Ultra HDR) M4; Mertens M4-W2; TRACK-01..05 M4; IOP-PANO-01 M5. In-flight fix batch (FINDING-F / ToneEqual) isolation discipline carries over to all M3 waves.
- push: local-only per user instruction (~370+ commits ahead of Azure DevOps origin; GitHub repo not yet created — 13-4 DIST-01).

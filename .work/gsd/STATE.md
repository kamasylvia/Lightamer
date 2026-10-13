---
gsd_state_version: 1.0
milestone: M6
milestone_name: 互操作与图库强化 (Interoperability & Library Hardening — 2026-10-16 chartered from the LightCraft six-ruling batch: MCP-09-A single-writer + connect / ALCE-03 UltraHDR unfreeze / per-photo process version / native AI-segmentation spike / stacks + auto-stack / FEATURE-MAP ID-ification + CI parity gate)
current_phase: M6-0 closed（charter 批 2026-10-16——五正本落账 + M6-1 research 同批起草完成，C 档第 1 停待 OQ-M6-1-1..6 用户裁决）；next: OQ 裁决回批 → M6-1 plan round（执行分工照 Phase 执行模型 = omp 执行 + subagent 验收）→ M6-2 process version → M6-3 UltraHDR → M6-4 stacks + AI spike → M6-5 挂账清算 → M6-6 FEATURE-MAP + VALIDATION 收口
status: M6-0 closed 2026-10-16 (charter five ledgers landed — ROADMAP §Milestone 6 + REQUIREMENTS M6INT family ×4 + MCP-09-A/ALCE-03 in-place annotations + STATE + TODO M6 header + GOAL-STATE continuation; M6-1 research drafted same batch — `phases/m6-1-interop/` CONTEXT (OQ-M6-1-1..6 all with recommendations, C-gate stop 1) + RESEARCH-NOTES (project-level single-writer lock on the 14-1 five-state flock machinery + headless --connect arbitration + UltraHDR native-vs-Rust spike survey with SDK availability facts + process version design preview); two doc-only commits, not pushed); M5 closed 2026-10-13 (M5-0..M5-4 complete, milestone_closeout: M5 carried by `phases/m5-3-pano/M5-3-VALIDATION.md`, terminal full-suite 3631/24/0; backlog single list = three VALIDATION 挂账汇编 → M6-5 clearing batch); surgery (2nd) trigger remains handed to the main session (strip set recompute, act only if non-empty); M4 closed 2026-10-11; M3 closed 2026-10-10 (gate cleared); M2 closed 2026-10-07 (terminal 2961/16/0)
last_updated: "2026-10-16T00:00:00.000Z"
progress:
  total_phases: 16
  completed_phases: 14
  total_plans: 154
  completed_plans: 154
  m2_phases_total: 12
  m2_phases_complete: 12
  m3_phases_total: 5
  m3_phases_complete: 5
  m4_phases_total: 4
  m4_phases_complete: 4
  m5_phases_total: 5
  m5_phases_complete: 5
  m6_phases_total: 7
  m6_phases_complete: 1
---

# Project State: Lightamer

**Last updated:** 2026-10-16（M6 立项批：charter 五正本落账 + M6-1 research 起草，doc-only 两 commit 未 push）
**Current phase:** **M6-0 closed（charter 2026-10-16）→ M6-1 research drafted（C 档第 1 停：OQ-M6-1-1..6 交用户裁决，全带推荐）→ 裁决回批后 M6-1 plan round → M6-2 → M6-3 → M6-4 → M6-5 → M6-6 VALIDATION 收口**。M6「互操作与图库强化」= LightCraft 六裁决点全按推荐（`research/LIGHTCRAFT-NOTES.md` §六）：①MCP-09-A 项目级单写者锁 + `--connect`（14-1 宿主级锁已关闭，残面 = 无头实例与活 GUI 同开同一项目的 `.lalb`/`.lra` 双写——M6-1 兑现项目级）②ALCE-03 UltraHDR 解冻（ImageIO auxiliary 原生路先试——SDK 实测 `kCGImageAuxiliaryDataTypeISOGainMap` macOS 15+ / `kCGImageDestinationEncodeGenerateGainMapWithBaseImage` macOS 16+ 均在 27 底线内；LightCraft Rust 移植对照臂）③per-photo process version（`.lra` additive 键 + 旧号冻结 + legacy 不序列化 hash 不变）④AI 分割蒙版原生 spike（对照 Phase 7 AI-01 审计 SAM 3 缺口，Vision + M2-10 CLIP 零模型成本路）⑤stacks + auto-stack（`.lalb` schema 迁移）⑥FEATURE-MAP ID 化 + CI 对账门（落 M6-6，编排偏差登记在案）。M6-5 = M5 三 VALIDATION 挂账汇编清偿批。范围红线：瘦身手术第二次触发不在 M6（主会话专属，GOAL-STATE 在案）；ALCE-02 维持 V2；零新 SPM。〔前一站〕**M5 closed（milestone 收口 2026-10-13；签核兼收口正本 = `phases/m5-3-pano/M5-3-VALIDATION.md`，`milestone_closeout: M5`；M5 Ledger 5/5 + plans 154/154；终态全套 `TOTAL 3631/24/0` exit 0；挂账单一清单 = 三 VALIDATION 挂账汇编 → M6-5）**。

**Status:** **Milestone 6 = chartered, M6-0 closed + M6-1 research drafted（2026-10-16，doc-only 两 commit 未 push；M6 Ledger 1/7；C 档第 1 停 = OQ-M6-1-1..6 待用户裁决，晨审可推翻）**；Milestone 5 = closed（2026-10-13，`milestone_closeout: M5` 单文档收口先例）；Milestone 4 = closed（2026-10-11）；Milestone 3 = closed（2026-10-10 门清翻正）；Milestone 1 Phases 1-16 = 历史记录；Milestone 2 closed（2026-10-07，terminal 2961/16/0）。

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

## Milestone 4 Ledger (Raster & Masks, narrowed — 2026-10-10 chartered, RAW + TIFF only)

| Phase | Name | Status | Terminal tests |
|---|---|---|---|
| M4-0 | Charter & scope narrowing | **complete** (2026-10-10: charter 五正本落账 = ROADMAP §Milestone 4 + REQUIREMENTS RASTER-IN-01/ALCE-02 原位注记 + STATE + TODO 头部 + GOAL-STATE 续接点；范围收窄 = TIFF only 入账；pack 政策 B 证据分仓同批落地——evidence 仓 `lightamer-evidence` ADO 私有 + 主仓 filter-repo 剥证据大对象) | — |
| M4-1 | TIFF raster develop chain (RASTER-IN-01 narrowed) | **complete (VALIDATION signed 2026-10-10 — `phases/m4-1-tiff-raster/M4-1-VALIDATION.md`; 2 plans accepted, dual acceptance 4-lane PASS / 0 error: 01 zcode 0E+0M+3obs + omp 0E+1M+3obs〔omp-minor-1 literal correction closed by 02 batch〕/ 02 zcode 0E+0M+3obs + omp 0E+1M+2obs〔omp-minor-1 test-hygiene carried as backlog〕; SC#1 round-trip real-queue / SC#2 ICC golden + IOP·IOPParity bitwise / SC#3 HDR viewport five tests all Delivered; OQ-1..7 rulings all landed; backlog single list = six items — deep-shadow desaturation / HDR LUT-arm face / CMYK·16-bit-gray UX / 16-bit-gray leg / RGC-off morning-review-flippable / omp-minor-1 fix batch; morning review may overturn)** | **3335/16skip/0fail** |
| M4-2 | IOP-MASK-06 Follow Edges V2 (re-anchor) | **closed — deleted & parked (2026-10-10 user ruling: V1 fuse + V2 gate FAIL 0/8→2/8 < 6/8; walker failure = junction-continuation drop, algorithm-layer deep water, zero OSS precedent; M4-2-03 walker-discipline plan ruled all-A but NOT executed — user ordered deletion instead; V2 code face removed as the exact inverse of M4-2-01/02 code commits, tree back to M4-1 baseline; docs/evidence preserved in `phases/m4-2-follow-edges/`; REQUIREMENTS IOP-MASK-06 = parked, restart = a reliable open-source reference〔edge-following brush class〕)** | **3335/16skip/0fail (M4-1 baseline restored; Layers 394/3/0 + App 704/0/0 verified bitwise post-deletion)** |
| M4-3 | IOP-MASK-07 Depth mask (MiDaS) | **complete — M4 milestone closed（VALIDATION signed 2026-10-11 — `phases/m4-3-depth/M4-3-VALIDATION.md`; single plan M4-3-01, dual acceptance zcode PASS/0E+2M + omp PASS/0E+2M zero substantive divergence: m-a LESSONS renumber L072→L074 fixed `57596d3` / m-b absent-vs-installed App skip-state ledger annotation / o-2 q95 anchor 1-ulp tolerance note; SC#1 pipeline numpy anchors + golden triple / SC#2 raster channel + worker three-leg crash-safe with AIWorkerProtocol zero-diff / SC#3 asset fail-closed chain digest triple-source + real-download e2e all Delivered; OQ-1..7 all-A rulings + D-1..D-5 landed; targeted terminal 1748/11/0 dual-lane verified — Layers 411/3/0 + Library 626/4/0 + App 711/4/0 absent / 711/2/0 installed, baseline 1717+31 exact, full-suite implied 3366/16/0 not run = zero IOP touch; backlog six items: m-b annotation closed / o-2 tolerance discipline / enhancement resolver deferral / guided-filter walkthrough observation V2 / M4-1 backlog#6 carried / far-scene second entry)** | **1748/11/0 targeted (three bundles; full-suite implied 3366/16/0)** |

## Milestone 5 Ledger (追色与合成 — 2026-10-11 chartered, V2 rolled-over approved items)

| Phase | Name | Status | Terminal tests |
|---|---|---|---|
| M5-0 | Charter & station spec | **complete** (2026-10-11: charter 五正本落账 = ROADMAP §Milestone 5 + REQUIREMENTS TRACK V2 节/IOP-HDR-06/IOP-PANO-01「→ M5」注记 + STATE + TODO M5 头部 + GOAL-STATE 续接点；组成 = TRACK-01..05 + IOP-HDR-06 Mertens + IOP-PANO-01 + M5-4 VALIDATION 兼手术第二次〔strip 集重算非空才动手〕；zero source code, doc-only) | — |
| M5-1 | TRACK color-transfer family (research + execution + MCP `match_color`) | **complete (VALIDATION signed 2026-10-13 — `phases/m5-1-track/M5-1-VALIDATION.md`; 3 plans accepted + out-of-window fix(film-leg) `7bc6365`; dual acceptance all three waves PASS — 01 zcode 0E+3M + omp 0E+0M zero divergence / 02 zcode PASS + omp FAIL→fix `3ae3daf`→omp reverify PASS (E-omp1 GUI reachability) / 03 zcode PASS + omp PASS 0E+2M; TRACK-01..05 + MCP-09 research item C all Delivered; five gates all green — G1 bit-identity / G2 dual-face parity (well-conditioned ≤1e-5 + crossover 2.95e-3/3.68e-2 pinned, mechanism-noted non-degradation) / G3 synthetic recovery + Manual-Only eyeball rows / G4 MCP e2e byte-identical / G5 identity passthrough; terminal full-suite `TOTAL\|3477/21/0\|` split-rerun table with reconciliation chain 3335+32+38+47+1+24 exact; film-leg latent race root-caused + M4-1 backlog#6 closed by `7bc6365`; backlog single list = VALIDATION 挂账总汇编) | **3477/21skip/0fail** (split-rerun table; peak IOPParity 8107MB < 8192 gate, zero MEMFAIL) |
| M5-2 | IOP-HDR-06 Mertens exposure fusion | **complete (VALIDATION signed 2026-10-15 — `phases/m5-2-mertens/M5-2-VALIDATION.md`; 2 plans accepted + acceptance-batch fix `358abd8`; dual acceptance all waves PASS — 01 zcode 0E+0M+4obs + omp 0E+0M zero divergence / 02 zcode PASS〔1E = production-leg LUT missing merge.py:145 all-grid fallback, fixed in acceptance batch〕+ omp 0E+2M zero substantive divergence〔both minor out-of-batch: Library Import stall + L057-B family〕; IOP-HDR-06 Delivered three-column — MertensFusion pure-function family + free-EV precheck + hdrMertens streaming production leg〔band-outer + substitution in-pass + shared union mask〕+ sRGB-tagged 32f raster ingest + UI two menu items + `_mertens` accounting; six gates G1-G5 green〔G2 p99.9 pinned 1e-6 measured 6.95e-7; G4 structural compare ρ=0.990 non-gate〕+ G6 rows 2/5 omp-verified backfilled, rows 1/3/4 carried to M5-4; terminal split-rerun table `TOTAL 3538/22/0` — reconciliation 3477+39+22 exact, post-fix baseline 3539/22/0; budget ru_maxrss 6248MB < 8G gate, fusion core 172.24s@100MP×5 zero GPU-trigger; backlog single list = VALIDATION 挂账总汇编) | **3538/22skip/0fail** (split-rerun table; post-fix 3539/22/0; peak IOPParity 7738MB < 8192 gate, zero MEMFAIL) |
| M5-3 | IOP-PANO-01 panorama stitch | **complete — M5 milestone closed（VALIDATION signed 2026-10-13 兼收口 `milestone_closeout: M5` — `phases/m5-3-pano/M5-3-VALIDATION.md`; 3 plans accepted, dual acceptance all three waves PASS — 01 zcode 0E+3M + omp 0E+0M zero divergence / 02 zcode PASS〔1E = HEAD Export compile break, fixed in acceptance batch `7ece3d3`〕+ omp FAIL→fix `60aad61`→OMP-REVERDICT PASS〔E-omp-1 band-span X guard missed originX + asymmetric regression test + 8/8 participation dual-run〕/ 03 zcode PASS 0E+1M+3obs〔m-1 SC-anchor 88/93→85/90 corrected in batch〕+ omp PASS 0E+1M+3obs zero substantive divergence〔omp minor = on-screen FAIL-toast pixel not captured, semantics closed three-way〕; IOP-PANO-01 Delivered three-column — self-implemented feature chain〔DoG + 128-d descriptors + knn Lowe 0.3 + RANSAC + BFS, PanoRNG LCG seed 121 single-stream determinism〕+ single-focal f + N×R LM BA + lateral wave correct + spherical projection + chunked feather blending + FloatTIFFWriter streaming + sRGB 32f raster ingest + `_pano` accounting + typed three-state zh + minimal sheet zero controls; v1 all-CPU zero `.metal`; gates G1-G5 + budget gate all green — G5 eleven-item battery + omp twelve-item recheck, ru_maxrss probe 5033/5653MB, full-suite rounds all <8G zero MEMFAIL; G6 rows 1(partial)/4(log face) omp-verified backfilled, rows 2/3/5 + 4 screen face carried; backlog single list = VALIDATION 挂账汇编) | **3631/24skip/0fail** (full-suite approved round, single command exit 0 — closeout 2102s + zcode acceptance rerun 2104s bitwise cross-checked, reconciliation 3539+43+44+5 exact; peak IOPParity 7803MB < 8192 gate, zero MEMFAIL) |
| M5-4 | VALIDATION closeout + history-slim surgery (2nd) | **complete — discharged by the closeout batch (VALIDATION summary carried by `phases/m5-3-pano/M5-3-VALIDATION.md` `milestone_closeout: M5` — three phase VALIDATIONs + SC three-column reconciliations all on file, m2-11/m4-3 single-document closeout precedent; REQUIREMENTS flips all landed — TRACK-01..05 + IOP-HDR-06 + IOP-PANO-01 Delivered; **surgery (2nd) trigger handed to the main session** — SPEC = `research/HISTORY-SLIM-SURGERY-SPEC.md`, strip set recomputed per SPEC, **act only if non-empty**〔M3 precheck falsified to zero once; M4 evidence-repo split + M4/M5 batch additions changed the picture, recompute required〕; L070 re-add remotes after filter-repo; push converges in main session) | — |

## Milestone 6 Ledger (互操作与图库强化 — 2026-10-16 chartered, LightCraft six-ruling station)

| Phase | Name | Status | Terminal tests |
|---|---|---|---|
| M6-0 | Charter & station spec | **complete** (2026-10-16: charter 五正本落账 = ROADMAP §Milestone 6 + REQUIREMENTS M6INT 族四条 + MCP-09-A/ALCE-03 原位注记 + STATE + TODO M6 头部 + GOAL-STATE 续接点；M6-1 research 同批起草完成 = `phases/m6-1-interop/`（CONTEXT OQ-M6-1-1..6 + RESEARCH-NOTES），C 档第 1 停待裁决；doc-only 零源码) | — |
| M6-1 | MCP-09-A project-level single-writer lock + `--connect` forwarding (ruling ①) | pending (research drafted 2026-10-16 — C-gate stop 1; OQ rulings → plan round → execute) | — |
| M6-2 | per-photo process version (ruling ③) | pending (`.lra` additive process key + frozen-old-version discipline + legacy non-serialization hash invariance; design preview in M6-1 RESEARCH-NOTES) | — |
| M6-3 | ALCE-03 UltraHDR gain-map JPEG export unfreeze (ruling ②) | pending (native ImageIO route spike first — `kCGImageAuxiliaryDataTypeISOGainMap` macOS 15+ / `kCGImageDestinationEncodeGenerateGainMapWithBaseImage` macOS 16+, both inside the macOS 27 floor per SDK probe; LightCraft Rust-port contrast arm) | — |
| M6-4 | Library stacks + auto-stack + native AI-segmentation mask spike (rulings ⑤④) | pending (`.lalb` schema migration + time-gap clustering; audit vs Phase 7 AI-01 delivered face, zero-model-cost native route first, SAM CoreML only on fail) | — |
| M6-5 | M5 backlog clearing batch | pending (three VALIDATION 挂账汇编 — L057-B tail / depth backlog / McpServerController stale header / o-2 resolver tighten ride-along candidate / G6 residual walkthrough rows / full-suite rerun round〔orchestrator approval + 8G gate〕) | — |
| M6-6 | FEATURE-MAP ID-ification + CI parity gate + M6 VALIDATION closeout (ruling ⑥) | pending (编排偏差登记 = ruling ⑥ "first plan" phrasing superseded by interop-first ordering, flippable at morning review) | — |

## Notes

- Phase 9/11/12 UAT: user exemption 2026-09-27（四期翻转一句话豁免；材料全齐：09-UAT.md 12 pass/3 skip/0 真缺陷 + 各 VALIDATION validated）。
- Phase 10 (yiyin) was executed as Phase 8 (execution-order 08 = ROADMAP §Phase 10).
- Phase 16 backend ruling: v1 = local SQLite (user 2026-09-27); pg = v2 evaluation item.
- Milestone 3 chartered 2026-10-08 per V2/Maintenance station proposal plan A (film darkroom); OQ-V2-1..10 all-recommendations pre-ruling (user can overturn at any time). Plan B (RASTER-IN-01 / IOP-MASK-06 V2 / IOP-MASK-07) rolls to M4; ALCE-02/03 (EXR / Ultra HDR) M4; Mertens M4-W2; TRACK-01..05 M4; IOP-PANO-01 M5. In-flight fix batch (FINDING-F / ToneEqual) isolation discipline carries over to all M3 waves.
- push: local-only per user instruction (~370+ commits ahead of Azure DevOps origin; GitHub repo not yet created — 13-4 DIST-01).

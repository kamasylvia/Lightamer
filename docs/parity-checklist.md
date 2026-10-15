# Lightamer parity checklist (vs Alcedo Studio)

> **Last updated:** 2026-10-16; **Target:** Alcedo Studio 0.3.2 (GPL-3.0,
> surveyed read-only at commit `34241d0` + upstream delta through `f1fae5d`)
> ; **Gate:** `python3 Scripts/parity-audit.py --check` (CI job `parity`)

Row-by-row feature checklist against Alcedo Studio, the app Lightamer's UI
and feature surface mirrors (2026-09-27 project re-definition). One row per
Alcedo feature surface, plus rows for the LightCraft-derived gallery pieces
and the Lightamer-exclusive surface. It answers *does the feature exist?*;
the prose survey (source index, errata, upstream-delta mapping) stays in the
internal research copy. Whoever lands a feature updates its row in the same
commit.

Methodology credit: the id'd-row checklist + generated summary/gaps blocks +
a CI gate that re-checks every cited path are borrowed from **LightCraft**
(`storytold/lightcraft`, MIT OR Apache-2.0). Method and form only - zero
code ported, no NOTICE obligation.

**Dual-source note:** the long-form survey lives at
`.work/gsd/research/ALCEDO-FEATURE-MAP.md` (internal tree, not part of the
public checkout). That file is the research master; **this checklist is the
reconciliation master and the only place new `FEAT-` ids are minted** - the
survey never mints ids.

**Granularity:** one row per Alcedo feature surface; closely-related knobs
may share a row (e.g. the four Post-owned detail controls), with the survey
carrying the fine detail. Coverage rule: no Alcedo feature surface may be
missing from a row; the row count band (120-140) is an estimate, not a gate.

**Id discipline:** `FEAT-<DOM>-NN`, zero-padded two-digit sequence inside
the domain. Ids are stable; never renumber. A retired feature keeps its id
and flips Status (to Parked/OOS as appropriate); freed numbers are not
reused.

## Vocabularies

- **Domain** (12): `SHELL` workspace shell, windows, theme, settings pages |
  `LIB` library and project model | `EDT` editor chassis and panels |
  `ADJ` adjustment catalog (18-piece + color wheels + look grouping) |
  `DEV` develop / raw decode surface | `GEO` geometry | `NODE` node graph
  model and versions | `MASK` mask system | `DRT` display rendering
  transform | `EXP` export | `AI` AI features | `OWN` Lightamer-exclusive
  surface (yiyin, MCP, FSIM, TRACK, Mertens, PANO, depth, denoise family,
  LUT library, process versions).
- **Source** (3): `Alcedo` = parity row against an Alcedo feature |
  `LightCraft` = semantic port of a LightCraft gallery/pipeline piece |
  `Lightamer` = exclusive surface (no Alcedo counterpart).
- **Status** (6): `Delivered` = usable end to end, ledger evidence on file |
  `Partial` = some of the surface delivered, note says what is missing |
  `Missing` = not built (note says what) | `V2` = deferred to the V2
  station, row carries the V2-PROPOSAL/REQUIREMENTS anchor | `Parked` =
  deliberately dormant with a restart condition on file | `OOS` = out of
  scope by ruling, row carries the ruling anchor.

**Status determination order (no re-acceptance):** REQUIREMENTS Delivered
marks -> STATE milestone ledgers -> phase VALIDATION/ACCEPTANCE records ->
AGENTS architecture-increment sections. A surface none of these mention
defaults to Missing with a note (conservative side); acceptance or morning
review may flip it.

**Evidence pointers, two levels:**

- `src:<repo-path>[:line]` - code evidence under the repo tree (exists in
  both the local and the public checkout); existence is always
  machine-checked. `:line` is used only on low-churn files; high-churn
  files get path-level pointers so unrelated edits do not break the gate
  (LightCraft's rule). Line drift on a cited line is fixed by whichever
  commit moves that line.
- `doc:<path>` - process evidence under the internal `.work/` tree. Checked
  when a `.work/` root exists (local tree); in the public checkout these
  are format-only and reported as local-only evidence. Disclosure: `doc:`
  paths appear in this public-tree file while their contents stay out of
  the public checkout (phase slugs only) - accepted trade-off. Evidence
  under `.work/gui-acceptance/` and `phases/*/evidence/` is format-only
  everywhere (gitignored evidence domains).

## Summary

<!-- parity:summary -->
| Domain | Delivered | Partial | Missing | V2 | Parked | OOS | Rows |
|---|---:|---:|---:|---:|---:|---:|---:|
| SHELL | 4 | 1 | 0 | 0 | 0 | 1 | 6 |
| LIB | 14 | 1 | 1 | 0 | 0 | 0 | 16 |
| EDT | 15 | 0 | 0 | 0 | 0 | 0 | 15 |
| ADJ | 18 | 1 | 0 | 0 | 0 | 0 | 19 |
| DEV | 5 | 1 | 0 | 0 | 0 | 3 | 9 |
| GEO | 3 | 0 | 0 | 0 | 0 | 0 | 3 |
| NODE | 8 | 0 | 0 | 0 | 0 | 0 | 8 |
| MASK | 10 | 0 | 0 | 1 | 1 | 0 | 12 |
| DRT | 10 | 0 | 0 | 0 | 0 | 0 | 10 |
| EXP | 13 | 0 | 1 | 1 | 0 | 0 | 15 |
| AI | 10 | 0 | 0 | 1 | 0 | 0 | 11 |
| OWN | 11 | 1 | 0 | 0 | 0 | 0 | 12 |
| **Total** | 121 | 5 | 2 | 3 | 1 | 4 | 136 |
<!-- /parity:summary -->

## Gaps

<!-- parity:gaps -->
| Id | Domain | Status | Feature |
|---|---|---|---|
| FEAT-EXP-15 | EXP | Missing | PNG compression-level option (UI 0-9) |
| FEAT-LIB-15 | LIB | Missing | Watched folders (auto-ingest on folder change) |
| FEAT-AI-10 | AI | V2 | AI segmentation masks (subject/sky/people via SAM-class models) |
| FEAT-EXP-02 | EXP | V2 | OpenEXR export |
| FEAT-MASK-11 | MASK | V2 | AI subject/sky/people masks (segmentation) |
| FEAT-MASK-12 | MASK | Parked | Edge-following brush (contour-aware stroke) |
| FEAT-DEV-05 | DEV | OOS | Demosaic algorithm menu (RCD / AMaZE / Markesteijn / ... selectable) |
| FEAT-DEV-06 | DEV | OOS | Highlights reconstruction (raw-domain, default on) |
| FEAT-DEV-09 | DEV | OOS | Nikon HE (high-efficiency NEF) recovery |
| FEAT-SHELL-06 | SHELL | OOS | In-app updates page (signed auto-update channel) |
| FEAT-ADJ-19 | ADJ | Partial | dt-derived adjustment superset (39 modules: channel mixers, filmic/sigmoid/AgX, tone equal, denoise family, retouch, liquify, borders, watermark, etc.) |
| FEAT-DEV-07 | DEV | Partial | Lens calibration (enable + scale + projection with profile database and auto-detection) |
| FEAT-LIB-14 | LIB | Partial | Culling/pick pass over the library |
| FEAT-OWN-12 | OWN | Partial | Denoise family (bilateral / NL-means / profiled) plus retouch, liquify, borders, watermark and the remaining dt-era modules |
| FEAT-SHELL-05 | SHELL | Partial | Keyboard settings page with conflict display and restore defaults |
<!-- /parity:gaps -->

## SHELL - workspace shell

| Id | Feature | Source | Status | Evidence | Notes |
|---|---|---|---|---|---|
| FEAT-SHELL-01 | Dual workspace shell (library workspace and editor workspace behind one window host) | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift`, `src:App/Sources/Lightamer/UI/Shell/EditorWorkspaceShellView.swift`, `doc:.work/gsd/phases/m2-3-ui-shell/M2-3-1-ACCEPTANCE.md` | Native SwiftUI chrome replaces Alcedo's custom frameless-window layer by design |
| FEAT-SHELL-02 | Workspace navigation (library <-> editor switching, sidebar structure) | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/ContentView.swift`, `src:App/Sources/Lightamer/UI/SidebarView.swift` | |
| FEAT-SHELL-03 | Dark theme token family (card surface/border colors) | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/Theme/ThemeTokens.swift`, `doc:.work/gsd/REQUIREMENTS.md` | Seven self-written glass families are the single color source for the new shell (values self-authored per the GPL red line, not a one-for-one copy); M2UIW-01 delivered, machine-checked in M2-3-1 AC1 |
| FEAT-SHELL-04 | Settings page family (language/theme, default behavior, cache, local content recognition, advanced content analysis, about) | Alcedo | Delivered | `src:App/Sources/Lightamer/Settings/SettingsPages.swift`, `src:App/Sources/Lightamer/Settings/LCRSettingsModel.swift`, `src:App/Sources/Lightamer/Settings/ACASettingsModel.swift` | 7 of Alcedo's 9 pages plus 4 Lightamer-only pages (import defaults, displays, MCP, gated catalogs face) |
| FEAT-SHELL-05 | Keyboard settings page with conflict display and restore defaults | Alcedo | Partial | `src:App/Sources/Lightamer/Settings/SettingsPages.swift` | Page shows/detects conflicts and restores defaults (v1); per-shortcut rebinding not implemented |
| FEAT-SHELL-06 | In-app updates page (signed auto-update channel) | Alcedo | OOS | `doc:.work/gsd/PROJECT.md` | 2026-09-27 ruling: Apple distribution channel cut; unsigned DMG/zip distribution, no updater |

## LIB - library and project model

| Id | Feature | Source | Status | Evidence | Notes |
|---|---|---|---|---|---|
| FEAT-LIB-01 | Single-file project model (one file carrying albums and full edit history, freely movable/backable) | Alcedo | Delivered | `src:LightamerCore/Sources/Library/ProjectFileStore.swift`, `src:LightamerCore/Sources/Library/LibrarySchema.swift`, `doc:.work/gsd/phases/m2-2-library-project/M2-2-1-ACCEPTANCE.md` | `.lalb` SQLite project, Alcedo `.alcd`/DuckDB analogue; media stays by reference |
| FEAT-LIB-02 | Thumbnail grid browsing (GPU-rendered thumbnails, on-disk thumbnail cache) | Alcedo | Delivered | `src:App/Sources/Lightamer/Library/Views/LibraryGridView.swift`, `src:App/Sources/Lightamer/Library/LibraryGridModel.swift`, `src:App/Sources/Lightamer/Library/LibraryThumbnailBridge.swift` | |
| FEAT-LIB-03 | Library inspector (overview card, grouping by capture date/camera/label/lens, active search-filter readout) | Alcedo | Delivered | `src:App/Sources/Lightamer/Library/Views/LibraryInspectorView.swift`, `src:App/Sources/Lightamer/Library/LibraryInspectorModel.swift`, `src:LightamerCore/Sources/Library/LibraryQueries.swift` | |
| FEAT-LIB-04 | Activity view (photos-per-day chart, click a day to filter) | Alcedo | Delivered | `src:App/Sources/Lightamer/Library/Views/LibraryInspectorView.swift`, `src:App/Sources/Lightamer/Library/LibraryInspectorModel.swift`, `src:LightamerCore/Sources/Library/LibraryQueries.swift`, `doc:.work/gsd/REQUIREMENTS.md` | |
| FEAT-LIB-05 | EXIF lexical search (camera/lens/date/ISO/focal/aperture/file-type tokens, AND-composable) | Alcedo | Delivered | `src:LightamerCore/Sources/Library/ExifSearchParser.swift`, `src:LightamerCore/Sources/Library/ExifSearchIndexer.swift`, `src:App/Sources/Lightamer/Library/Views/GlobalSearchDialog.swift` | Materialized search columns + word-boundary index, Alcedo `image_search_columns` analogue |
| FEAT-LIB-06 | Natural-language semantic search (CLIP-family local embeddings) | Alcedo | Delivered | `src:LightamerCore/Sources/AI/SemanticEngine.swift`, `src:App/Sources/Lightamer/Library/Views/GlobalSearchDialog.swift`, `doc:.work/gsd/phases/m2-10-ai-library/M2-10-VALIDATION.md` | |
| FEAT-LIB-07 | AI caption/tag full-text search | Alcedo | Delivered | `src:LightamerCore/Sources/AI/LabelEngine.swift`, `src:LightamerCore/Sources/AI/SemanticStore.swift`, `doc:.work/gsd/phases/m2-10-ai-library/M2-10-VALIDATION.md` | |
| FEAT-LIB-08 | Folder import with progress overlay, reference-based linking | Alcedo | Delivered | `src:LightamerCore/Sources/Library/ImportService.swift`, `src:App/Sources/Lightamer/Library/ImportProgressView.swift`, `src:App/Sources/Lightamer/Library/LibraryRelinkModel.swift` | Import-mode dialog (copy/reference); relink sheet goes beyond Alcedo, whose deleted files cannot be relinked |
| FEAT-LIB-09 | Import file-type selector (raw/tiff family mask) | Alcedo | Delivered | `src:App/Sources/Lightamer/Library/ImportModeDialog.swift`, `src:LightamerCore/Sources/Library/ImportFilter.swift` | Alcedo 0.3.1 selector counterpart, delivered with the M4-1 raster input route |
| FEAT-LIB-10 | Project welcome/open/create flow with recents | Alcedo | Delivered | `src:App/Sources/Lightamer/Library/LibraryProjectController.swift`, `src:App/Sources/Lightamer/UI/EmptyStateView.swift` | Welcome sheet when no project is open; recents dedupe + dead-path sweep |
| FEAT-LIB-11 | Image stacks (manual stack/unstack, cover = first slot, badge in grid) | LightCraft | Delivered | `src:LightamerCore/Sources/Library/LibraryStore.swift`, `src:App/Sources/Lightamer/Library/Views/LibraryAutoStackDialog.swift`, `doc:.work/gsd/phases/m6-4-gallery-stacks/M6-4-VALIDATION.md` | M6 charter ruling 5 |
| FEAT-LIB-12 | Auto-stack by capture time (preview-first, full semantics) | LightCraft | Delivered | `src:LightamerCore/Sources/Library/LibraryStore.swift`, `doc:.work/gsd/phases/m6-4-gallery-stacks/M6-4-VALIDATION.md` | |
| FEAT-LIB-13 | Smart albums (saved filter collections) | Alcedo | Delivered | `src:LightamerCore/Sources/Session/SmartAlbumStore.swift`, `src:App/Sources/Lightamer/UI/SidebarView.swift`, `src:App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift`, `src:App/Sources/Lightamer/Library/Views/LibraryInspectorView.swift`, `doc:.work/gsd/REQUIREMENTS.md` | CRUD, project-workspace assembly and the evaluate(.library) member loop are delivered (M2LIB-02/M2LIB-05); the LightCraft-semantic enhancement left unchartered by charter ruling 5 stays a separate candidate |
| FEAT-LIB-14 | Culling/pick pass over the library | LightCraft | Partial | `src:App/Sources/Lightamer/UI/CullingView.swift` | Phase 9 two-pane compare mode delivered; a flag-driven culling pass is not chartered (ruling 5) |
| FEAT-LIB-15 | Watched folders (auto-ingest on folder change) | LightCraft | Missing | | Charter ruling 5 left watched folders unchartered |
| FEAT-LIB-16 | Project move and consistent backup | Alcedo | Delivered | `src:LightamerCore/Sources/Library/ProjectFileStore.swift`, `doc:.work/gsd/phases/m2-2-library-project/M2-2-3-ACCEPTANCE.md` | Online-consistent `sqlite3_backup` copy; move = whole project directory |

## EDT - editor chassis and panels

| Id | Feature | Source | Status | Evidence | Notes |
|---|---|---|---|---|---|
| FEAT-EDT-01 | Left tool rail (history / versions / nodes panels, push-in reveal) | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/Shell/EditorToolRailView.swift`, `src:App/Sources/Lightamer/UI/Shell/VersionsPanelView.swift`, `src:App/Sources/Lightamer/UI/Shell/Nodes/EditorNodesPanelView.swift` | |
| FEAT-EDT-02 | Direct-render viewport (fit/zoom readout, pan, high-zoom visible-region rendering, EDR) | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/EditorMTKView.swift`, `src:App/Sources/Lightamer/UI/EditorAreaView.swift`, `doc:.work/gsd/phases/m2-11-performance/M2-11-VALIDATION.md` | Metal `MTKView` leg; 100MP latency budget verified in M2-11 |
| FEAT-EDT-03 | Editor filmstrip bound to the library collection/filter | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/Shell/FilmstripView.swift` | |
| FEAT-EDT-04 | Scope panel (histogram / waveform toggle, GPU-sampled, throttled) | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/Shell/ScopePanelView.swift`, `doc:.work/gsd/phases/m2-3-ui-shell/M2-3-3-ACCEPTANCE.md` | |
| FEAT-EDT-05 | Right adjustment stack in Alcedo's panel order (tone / look / LUT / display transform / geometry / raw decode / mask) | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/Shell/EditorAdjustmentStackView.swift`, `src:App/Sources/Lightamer/UI/Shell/EditorTabRoute.swift`, `doc:.work/gsd/phases/m2-3-ui-shell/M2-3-3-ACCEPTANCE.md` | Routing table pin: every enabled module lands in exactly one tab |
| FEAT-EDT-06 | Adjustment header with node name + focal/aperture/shutter/ISO readout | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/Shell/EditorNodeHeaderView.swift` | |
| FEAT-EDT-07 | History panel (undo/redo, one row per committed edit, jump to state) | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/Shell/VersionsPanelView.swift`, `src:LightamerCore/Sources/Sidecar/LightamerSidecar.swift` | History stack persisted in the sidecar; named versions are the sibling panel family |
| FEAT-EDT-08 | Crash-safe persistence (continuous sidecar autosave, forced flush on quit/image switch) | Alcedo | Delivered | `src:LightamerCore/Sources/Sidecar/LightamerSidecar.swift` | Alcedo answers crashes with a save-recovery bar; Lightamer persists continuously so no recovery bar exists |
| FEAT-EDT-09 | Copy Adjustments dialog (pick source version, select per node/per item, paste) | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/Shell/AdjustmentTransferView.swift`, `doc:.work/gsd/phases/m2-8-versions/M2-8-VALIDATION.md` | Paste lands as a new version, Alcedo 0.3.0 semantics |
| FEAT-EDT-10 | Background task surface for AI work (bar + dialog, cancellable) | Alcedo | Delivered | `src:App/Sources/Lightamer/Library/BackgroundTaskHosting.swift`, `src:App/Sources/Lightamer/UI/Shell/BackgroundTaskBarView.swift` | |
| FEAT-EDT-11 | Semantic-analysis prompt on import with remember-my-choice | Alcedo | Delivered | `src:App/Sources/Lightamer/AI/LabelingPromptController.swift`, `doc:.work/gsd/phases/m2-10-ai-library/M2-10-VALIDATION.md` | |
| FEAT-EDT-12 | Two-level busy indication (decode preparation vs adjustment re-render) | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/EditorAreaView.swift` | |
| FEAT-EDT-13 | LUT panel (library browse, open library root, per-LUT input/output encoding selectors) | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/Inspector/LutPanelView.swift`, `src:LightamerIOP/Sources/Lut3d/LutLibraryStore.swift`, `doc:.work/gsd/phases/m2-5-color-grade/M2-5-3-ACCEPTANCE.md` | Encoding dimension delivered on top (M3-1), Alcedo upstream #271-274 counterpart |
| FEAT-EDT-14 | Preset system over module parameters | Lightamer | Delivered | `src:LightamerCore/Sources/Presets/PresetsStore.swift`, `src:LightamerCore/Sources/Presets/PresetApplier.swift` | Beyond Alcedo (no preset panel there); retained dt-era surface |
| FEAT-EDT-15 | AI enhance dialog (super-resolution / denoise into an editable copy) | Lightamer | Delivered | `src:App/Sources/Lightamer/UI/Views/EnhanceDialog.swift`, `src:LightamerCore/Sources/AI/EnhanceEngine.swift`, `src:App/Sources/Lightamer/AI/EnhanceCopyWriter.swift` | Beyond Alcedo; UX pattern credited to Lumen (MIT) in the survey notes |

## ADJ - adjustment catalog

| Id | Feature | Source | Status | Evidence | Notes |
|---|---|---|---|---|---|
| FEAT-ADJ-01 | CAT02 white balance (grade-level creative WB, AP1 identity near 6000 K) | Alcedo | Delivered | `src:LightamerIOP/Sources/Cat02WB/Cat02WBModule.swift`, `src:App/Sources/Lightamer/UI/Inspector/TemperaturePanelView.swift`, `doc:.work/gsd/phases/m2-5-color-grade/M2-5-1-ACCEPTANCE.md` | |
| FEAT-ADJ-02 | Exposure (EV slider) | Alcedo | Delivered | `src:LightamerIOP/Sources/Exposure`, `src:App/Sources/Lightamer/UI/Inspector/ExposurePanelView.swift` | |
| FEAT-ADJ-03 | Contrast (midtone-neighborhood lightness, hue-preserving) | Alcedo | Delivered | `src:LightamerIOP/Sources/Contrast`, `doc:.work/gsd/phases/m2-5-color-grade/M2-5-1-ACCEPTANCE.md` | Alcedo 0.3.0 semantics adopted |
| FEAT-ADJ-04 | White / Black points | Alcedo | Delivered | `src:LightamerIOP/Sources/WhiteBlack`, `src:App/Sources/Lightamer/UI/Inspector/GradeScalarPanels.swift` | |
| FEAT-ADJ-05 | Shadows / Highlights (local tone mapping) | Alcedo | Delivered | `src:LightamerIOP/Sources/Shadhi`, `src:App/Sources/Lightamer/UI/Inspector/ShadhiPanelView.swift` | |
| FEAT-ADJ-06 | Tone curve (unit-square control points; add by drag, delete, reset) | Alcedo | Delivered | `src:LightamerIOP/Sources/ToneCurve`, `src:App/Sources/Lightamer/UI/Inspector/CurveEditorView.swift` | |
| FEAT-ADJ-07 | Selective color, 8-hue-bin H/L/S with hue smoothness | Alcedo | Delivered | `src:LightamerIOP/Sources/Hls`, `src:App/Sources/Lightamer/UI/Inspector/HlsPanelView.swift` | Alcedo HLS model counterpart |
| FEAT-ADJ-08 | Saturation | Alcedo | Delivered | `src:LightamerIOP/Sources/Saturation`, `src:App/Sources/Lightamer/UI/Inspector/GradeScalarPanels.swift` | |
| FEAT-ADJ-09 | Vibrance | Alcedo | Delivered | `src:LightamerIOP/Sources/Vibrance`, `src:App/Sources/Lightamer/UI/Inspector/VibrancePanelView.swift` | |
| FEAT-ADJ-10 | Color wheels (lift/gamma/gain trackballs, strength + luminance offset, ACEScc envelope) | Alcedo | Delivered | `src:LightamerIOP/Sources/ColorWheels`, `src:App/Sources/Lightamer/UI/Inspector/ColorWheelsPanelView.swift`, `doc:.work/gsd/phases/m2-5-color-grade/M2-5-1-ACCEPTANCE.md` | ACEScc grading envelope per Alcedo's pipeline diagram |
| FEAT-ADJ-11 | LMT (CUBE LUT applied inside a grade) | Alcedo | Delivered | `src:LightamerIOP/Sources/Lut3d`, `doc:.work/gsd/phases/m2-5-color-grade/M2-5-3-ACCEPTANCE.md` | Backed by the LUT library row in the OWN domain |
| FEAT-ADJ-12 | Tint | Alcedo | Delivered | `src:LightamerIOP/Sources/Tint`, `src:App/Sources/Lightamer/UI/Inspector/GradeScalarPanels.swift` | |
| FEAT-ADJ-13 | Clarity (single mid-frequency contrast scalar) | Alcedo | Delivered | `src:LightamerIOP/Sources/Equalizer`, `src:App/Sources/Lightamer/UI/Inspector/EqualizerPanelView.swift` | Post-owned in the DRT tail; own engine is finer-grained than Alcedo's scalar |
| FEAT-ADJ-14 | Sharpen (amount / radius / threshold, post-owned) | Alcedo | Delivered | `src:LightamerIOP/Sources/Sharpen`, `src:App/Sources/Lightamer/UI/Inspector/SharpenPanelView.swift` | |
| FEAT-ADJ-15 | Halation | Alcedo | Delivered | `src:LightamerIOP/Sources/Bloom`, `src:App/Sources/Lightamer/UI/Inspector/BloomPanelView.swift` | |
| FEAT-ADJ-16 | Film grain (physical model, post-owned) | Alcedo | Delivered | `src:LightamerIOP/Sources/Grain`, `src:App/Sources/Lightamer/UI/Inspector/GrainPanelView.swift` | |
| FEAT-ADJ-17 | Ownership model (detail tools cannot enter a grade; post items apply once, full frame, after the display transform) | Alcedo | Delivered | `src:LightamerIOP/Sources/NodeOwnershipCatalog.swift`, `src:LightamerCore/Sources/Graph/NodeOwnership.swift` | Alcedo `color_grade_node_model` ownership check counterpart |
| FEAT-ADJ-18 | Default look on new documents (non-identity default grade) | Alcedo | Delivered | `src:LightamerIOP/Sources/NodeOwnershipCatalog.swift` | Catalog carries the default look; raster documents mint it with the M4-1 exceptions |
| FEAT-ADJ-19 | dt-derived adjustment superset (39 modules: channel mixers, filmic/sigmoid/AgX, tone equal, denoise family, retouch, liquify, borders, watermark, etc.) | Lightamer | Partial | `src:LightamerIOP/Sources/Registry.swift`, `doc:.work/gsd/phases/m2-1-dt-disable/M2-1-MATRIX.md` | Beyond-parity surface; Alcedo-parity pieces delivered, dt-only pieces kept behind feature flags (default-off face per M2-1) |

## DEV - develop / raw decode

| Id | Feature | Source | Status | Evidence | Notes |
|---|---|---|---|---|---|
| FEAT-DEV-01 | Raw decode via the OS raw engine (demosaic + denoise, Apple Neural Engine on the v9 decoder) | Alcedo | Delivered | `src:LightamerCore/Sources/Decode/RAWDecoder.swift`, `src:App/Sources/Lightamer/UI/Shell/RawDecodePanelView.swift` | CIRAW route (decoder version selectable default/v8/v9); replaces Alcedo's LibRaw fork |
| FEAT-DEV-02 | Noise-reduction controls on the raw page (amount / luminance / chroma / sharpness, boost, persisted) | Alcedo | Delivered | `src:LightamerCore/Sources/Decode/RAWTechnicalParams.swift`, `src:App/Sources/Lightamer/UI/Shell/RawDecodePanelView.swift` | Alcedo has no raw NR at all; surface answer to its absence |
| FEAT-DEV-03 | Camera white balance (as-shot, custom temperature/tint) | Alcedo | Delivered | `src:LightamerCore/Sources/Decode/RAWDecoder.swift`, `src:App/Sources/Lightamer/UI/Shell/RawDecodePanelView.swift` | |
| FEAT-DEV-04 | Camera color profile (embedded matrix / DNG profile honored) | Alcedo | Delivered | `src:LightamerCore/Sources/Decode/RAWDecoder.swift` | Embedded profiles via the OS engine; external DCP files out of scope (same as Alcedo) |
| FEAT-DEV-05 | Demosaic algorithm menu (RCD / AMaZE / Markesteijn / ... selectable) | Alcedo | OOS | `doc:.work/gsd/research/STACK.md` | Structurally unreachable on the CIRAW route (STACK decoder-strategy section); Alcedo's own menu is only 3 entries (default/legacy/neural) |
| FEAT-DEV-06 | Highlights reconstruction (raw-domain, default on) | Alcedo | OOS | `doc:.work/gsd/research/STACK.md` | Raw-domain stage unreachable on the CIRAW route; the engine handles recovery internally |
| FEAT-DEV-07 | Lens calibration (enable + scale + projection with profile database and auto-detection) | Alcedo | Partial | `src:LightamerIOP/Sources/Lens`, `src:App/Sources/Lightamer/UI/Inspector/LensPanelView.swift` | Embedded lens opcodes applied at decode; no user-tunable lens database (Lensfun data-only approach is the recorded v1 stance) |
| FEAT-DEV-08 | Raster input route (TIFF/raster files enter the editor; display-referred inverse chain for LUT-ICC payloads) | Alcedo | Delivered | `src:LightamerCore/Sources/Decode/RasterDecoder.swift`, `src:LightamerCore/Sources/Pipe/Input/RasterInputStage.swift`, `doc:.work/gsd/phases/m4-1-tiff-raster/M4-1-VALIDATION.md` | Upstream delta #265-270 counterpart (RASTER-IN family), delivered for TIFF + raster in M4-1 |
| FEAT-DEV-09 | Nikon HE (high-efficiency NEF) recovery | Alcedo | OOS | `doc:.work/gsd/research/STACK.md` | A separate HE-recovery path is unreachable/unneeded on the CIRAW route (the OS raw engine owns HE decode); Alcedo surface = NikonHeRecoveryDialog |

## GEO - geometry

| Id | Feature | Source | Status | Evidence | Notes |
|---|---|---|---|---|---|
| FEAT-GEO-01 | Crop (normalized X/Y/W/H + aspect-ratio presets, on-canvas overlay) | Alcedo | Delivered | `src:LightamerIOP/Sources/Crop`, `src:App/Sources/Lightamer/UI/Overlay/CropOverlayView.swift` | |
| FEAT-GEO-02 | Rotation (plus/minus 180 with on-canvas handle and angle badge) | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/Overlay/CropOverlayHost.swift` | |
| FEAT-GEO-03 | Global geometry semantics (crop/rotate apply to the whole image, not per node/mask) | Alcedo | Delivered | `src:LightamerCore/Sources/Pipe/GeometryPointMapper.swift` | |

## NODE - node graph model and versions

| Id | Feature | Source | Status | Evidence | Notes |
|---|---|---|---|---|---|
| FEAT-NODE-01 | Pipeline document (develop -> color grades x N -> display transform) | Alcedo | Delivered | `src:LightamerCore/Sources/Graph/PipelineDocument.swift`, `doc:.work/gsd/phases/m2-4-node-model/M2-4-1-ACCEPTANCE.md` | |
| FEAT-NODE-02 | Node graph editor (add / rename / delete / connect grades, fit view) | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/Shell/Nodes/EditorNodesPanelView.swift`, `src:App/Sources/Lightamer/UI/Shell/Nodes/NodeCanvasGeometry.swift` | SwiftUI canvas replaces Alcedo's QuickQanava |
| FEAT-NODE-03 | Graph commands (insert identity grade, remove-and-bridge, reconnect, enable, per-node mix) | Alcedo | Delivered | `src:LightamerCore/Sources/Graph/NodeGraphCommand.swift`, `doc:.work/gsd/phases/m2-4-node-model/M2-4-2-ACCEPTANCE.md` | |
| FEAT-NODE-04 | Ordered adjustment list inside a grade (user order preserved) | Alcedo | Delivered | `src:LightamerCore/Sources/Graph/PipelineDocument.swift` | |
| FEAT-NODE-05 | Deletion protection (first grade locked) | Alcedo | Delivered | `src:LightamerCore/Sources/Graph/NodeGraphCommand.swift` | |
| FEAT-NODE-06 | Named versions (create / branch from current / fork from root / paste as version, instant swap) | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/Shell/VersionsPanelView.swift`, `src:LightamerCore/Sources/Sidecar/LightamerSidecar.swift`, `doc:.work/gsd/phases/m2-8-versions/M2-8-VALIDATION.md` | Sidecar v7 version records + project-side version refs |
| FEAT-NODE-07 | Unbounded undo (immutable edit chain, jump to any state) | Alcedo | Delivered | `src:LightamerCore/Sources/Pipe/History`, `src:LightamerCore/Sources/Sidecar/LightamerSidecar.swift` | |
| FEAT-NODE-08 | Per-photo process version (view-change = new process number, old renders frozen) | LightCraft | Delivered | `src:LightamerCore/Sources/Pipe/RenderProcess.swift`, `doc:.work/gsd/phases/m6-2-process-version/M6-2-VALIDATION.md` | M6 charter ruling 3 |

## MASK - mask system

| Id | Feature | Source | Status | Evidence | Notes |
|---|---|---|---|---|---|
| FEAT-MASK-01 | Radial mask (center/radii/rotation/inner-outer feather) | Alcedo | Delivered | `src:LightamerCore/Sources/Layers/Masks/MaskSpec.swift`, `src:LightamerCore/Sources/Layers/Masks/DrawnMaskRasterizer.swift`, `doc:.work/gsd/phases/m2-7-masks/M2-7-1-ACCEPTANCE.md` | |
| FEAT-MASK-02 | Linear gradient mask (origin/normal/transition) | Alcedo | Delivered | `src:LightamerCore/Sources/Layers/Masks/MaskSpec.swift`, `doc:.work/gsd/phases/m2-7-masks/M2-7-1-ACCEPTANCE.md` | |
| FEAT-MASK-03 | Brush mask (strokes with per-mask enable/opacity/invert) | Alcedo | Delivered | `src:LightamerCore/Sources/Layers/Masks/MaskSpec.swift`, `src:App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift` | Alcedo ships brush behind a compile flag; Lightamer ships it |
| FEAT-MASK-04 | Parametric range masks (luminance trapezoid + color-range curves with eyedropper) | Alcedo | Delivered | `src:LightamerCore/Sources/Layers/Masks/ParametricMask.swift`, `src:App/Sources/Lightamer/UI/Inspector/LuminanceColorRangePanelView.swift`, `doc:.work/gsd/phases/m2-7-masks/M2-7-2-ACCEPTANCE.md` | Beyond Alcedo, whose range models are disabled placeholders |
| FEAT-MASK-05 | Mask parameters (per-mask enable/opacity/invert/feather; display order independent of pixel order) | Alcedo | Delivered | `src:LightamerCore/Sources/Layers/Masks/MaskSpec.swift` | |
| FEAT-MASK-06 | On-canvas mask editing (draw directly, drag handles, guide overlays) | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/Overlay/MaskOverlayHost.swift`, `doc:.work/gsd/phases/m2-7-masks/M2-7-1-ACCEPTANCE.md` | |
| FEAT-MASK-07 | Mask groups panel (grouped per grade, thumbnails, reorder, deletion lock on the base group) | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/Inspector/MaskGroupsPanelView.swift`, `src:LightamerCore/Sources/Layers/Masks/MaskThumbnailRenderer.swift` | |
| FEAT-MASK-08 | Mask content revision (monotonic revision, optimistic concurrency on stroke append) | Alcedo | Delivered | `src:LightamerCore/Sources/Layers/LayerStackProjection.swift`, `doc:.work/gsd/phases/m2-7-masks/M2-7-2-ACCEPTANCE.md` | |
| FEAT-MASK-09 | Default mask-draw behavior setting (ask / new layer / current node) | Alcedo | Delivered | `src:App/Sources/Lightamer/Settings/SettingsPages.swift`, `src:App/Sources/Lightamer/State` | defaultBehavior settings page |
| FEAT-MASK-10 | Depth mask (monocular depth estimation) | Lightamer | Delivered | `src:LightamerCore/Sources/AI/DepthMaskPipeline.swift`, `doc:.work/gsd/phases/m4-3-depth/M4-3-VALIDATION.md` | Beyond Alcedo; MiDaS-based approach credited to Lumen in the survey notes |
| FEAT-MASK-11 | AI subject/sky/people masks (segmentation) | Alcedo | V2 | `src:LightamerCore/Sources/AI/AIMaskService.swift`, `doc:.work/gsd/phases/v2-station/V2-PROPOSAL.md` | Subject sugar + person instances delivered on existing engines; SAM CoreML deferred (M6 charter ruling 7) |
| FEAT-MASK-12 | Edge-following brush (contour-aware stroke) | Lightamer | Parked | `src:LightamerCore/Sources/Layers/Masks/FollowEdges.swift`, `doc:.work/gsd/REQUIREMENTS.md` | IOP-MASK-06: deleted after the V2 gate failed; restart condition = a reliable open-source reference implementation (REQUIREMENTS parked entry) |

## DRT - display rendering transform

| Id | Feature | Source | Status | Evidence | Notes |
|---|---|---|---|---|---|
| FEAT-DRT-01 | Display transform panel (method always expanded + color/encoding group) | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/Shell/DrtPanelView.swift`, `doc:.work/gsd/phases/m2-6-drt/M2-6-1-ACCEPTANCE.md` | |
| FEAT-DRT-02 | ACES 2.0 method with limiting-space picker (7 spaces) | Alcedo | Delivered | `src:LightamerCore/Sources/Pipe/Drt/Aces2Reference.swift`, `src:LightamerCore/Sources/Pipe/Drt/Aces2Limiting.swift`, `doc:.work/gsd/phases/m2-6-drt/M2-6-1-ACCEPTANCE.md` | |
| FEAT-DRT-03 | OpenDRT method with preset trio (look / tonescale / creative white) | Alcedo | Delivered | `src:LightamerCore/Sources/Pipe/Drt/DrtPresets.swift`, `src:LightamerCore/Sources/Pipe/Drt/OpenDrtReference.swift`, `doc:.work/gsd/phases/m2-6-drt/M2-6-1-ACCEPTANCE.md` | |
| FEAT-DRT-04 | Editor-owned detailed parameter group (53 params, serialized as a whole) | Alcedo | Delivered | `src:LightamerCore/Sources/Graph/DrtRecord.swift` | Count corrected to 53 in the survey errata; schema follows the real enumeration |
| FEAT-DRT-05 | Encoding space + EOTF linkage (Rec.709/P3 family/XYZ/Rec.2020; BT.1886/gamma/PQ/HLG) | Alcedo | Delivered | `src:LightamerCore/Sources/Pipe/Drt/DrtEotf.swift`, `src:App/Sources/Lightamer/UI/Shell/DrtPanelView.swift` | sRGB piecewise EOTF added on top (M4-1) |
| FEAT-DRT-06 | Peak luminance slider (100-1000 nits) | Alcedo | Delivered | `src:App/Sources/Lightamer/UI/Shell/DrtPanelView.swift` | |
| FEAT-DRT-07 | HDR encoding detection + HDR viewport (PQ/HLG -> EDR display) | Alcedo | Delivered | `src:LightamerCore/Sources/Graph/DrtRecord.swift`, `src:App/Sources/Lightamer/UI/EDRControlView.swift`, `doc:.work/gsd/phases/m2-6-drt/M2-6-2-ACCEPTANCE.md` | Drives library HDR flags and export; EDR viewport four states |
| FEAT-DRT-08 | ACES reference gamut compression ahead of the transform | Alcedo | Delivered | `src:LightamerCore/Sources/Pipe/Drt/Aces2Reference.swift` | RGC-off policy for raster documents (M4-1) |
| FEAT-DRT-09 | Post-four application point (clarity/sharpen/halation/grain applied once after the display transform, preview = product) | Alcedo | Delivered | `src:LightamerCore/Sources/Pipe/Terminal`, `doc:.work/gsd/phases/m2-6-drt/M2-6-3-ACCEPTANCE.md` | Alcedo 0.3.0 display-domain semantics |
| FEAT-DRT-10 | Film simulation tail (film/paper density model with latitude panel) | Lightamer | Delivered | `src:LightamerCore/Sources/Film/FilmProfile.swift`, `src:App/Sources/Lightamer/UI/Shell/FilmPanelView.swift`, `doc:.work/gsd/phases/m3-3-fsim/M3-3-03-ACCEPTANCE.md` | Beyond Alcedo (own FSIM family); read-only card in the node graph |

## EXP - export

| Id | Feature | Source | Status | Evidence | Notes |
|---|---|---|---|---|---|
| FEAT-EXP-01 | Core format matrix (JPEG/PNG/TIFF/HEIF plus WebP/AVIF) | Alcedo | Delivered | `src:LightamerCore/Sources/Export/ImageIOEncoders.swift`, `src:LightamerCore/Sources/Export/WebPEncoder.swift`, `doc:.work/gsd/phases/m2-9-export/M2-9-VALIDATION.md` | Six-format matrix is a superset of Alcedo's four (it dropped WebP; we never dropped it) |
| FEAT-EXP-02 | OpenEXR export | Alcedo | V2 | `doc:.work/gsd/phases/v2-station/V2-PROPOSAL.md`, `doc:.work/gsd/phases/v2-station/OQ.md` | ALCE-02, deferred with the EXR dependency question (OQ-V2-5) |
| FEAT-EXP-03 | Ultra HDR JPEG export (gain map + dither, size cap) | Alcedo | Delivered | `src:LightamerCore/Sources/Export/ExportGainMapEncoder.swift`, `doc:.work/gsd/phases/m6-3-ultrahdr/M6-3-VALIDATION.md` | ISO 21496-1 gain map; M6 charter ruling 2 |
| FEAT-EXP-04 | Bit depth selection (8/16/32-bit where the format allows) | Alcedo | Delivered | `src:LightamerCore/Sources/Export/ExportQuantizer.swift` | |
| FEAT-EXP-05 | Sizing modes (original / long edge / bounds / physical with DPI, upscale gate, edge-pixel cap) | Alcedo | Delivered | `src:LightamerCore/Sources/Export/ExportRecipe.swift`, `doc:.work/gsd/phases/m2-9-export/M2-9-VALIDATION.md` | |
| FEAT-EXP-06 | Metadata policy (standard strips location / device serials / editing history) | Alcedo | Delivered | `src:LightamerCore/Sources/Export/ExportMetadataPolicy.swift` | |
| FEAT-EXP-07 | ICC embed/omit + output profile derived from the image's display transform (space/EOTF/peak) | Alcedo | Delivered | `src:LightamerCore/Sources/Export/DrtOutputColorSpace.swift`, `doc:.work/gsd/phases/m2-9-export/M2-9-VALIDATION.md` | Export and display share the same DRT encoding, Alcedo semantics |
| FEAT-EXP-08 | Output file name template (date/camera/lens/ISO/aperture/shutter/rating/sequence tokens, fallback stem) | Alcedo | Delivered | `src:LightamerCore/Sources/Export/ExportFileNameTemplate.swift`, `src:App/Sources/Lightamer/Export/ExportNamingEditor.swift` | |
| FEAT-EXP-09 | Collision policy (increment / fail / replace) | Alcedo | Delivered | `src:LightamerCore/Sources/Export/ExportNamer.swift`, `src:App/Sources/Lightamer/Export/ExportPanelView.swift` | Selector delivered on the M2 export page (M3-1) |
| FEAT-EXP-10 | Optional export subfolder | Alcedo | Delivered | `src:LightamerCore/Sources/Export/ExportNamer.swift` | |
| FEAT-EXP-11 | Export queue (per-item states, progress, retry, bounded queue) | Alcedo | Delivered | `src:LightamerCore/Sources/Export/ExportQueue.swift`, `src:App/Sources/Lightamer/Export/ExportQueueFaceView.swift` | |
| FEAT-EXP-12 | Cross-session quality memory (per-format quality + last directory) | Alcedo | Delivered | `src:App/Sources/Lightamer/Export/ExportPanelView.swift`, `doc:.work/gsd/phases/m2-9-export/M2-9-VALIDATION.md` | Defaults keys per format |
| FEAT-EXP-13 | TIFF compression options (none / LZW / zip) | Alcedo | Delivered | `src:LightamerCore/Sources/Export/ImageIOEncoders.swift`, `src:App/Sources/Lightamer/Export/ExportInspectorView.swift`, `doc:.work/gsd/REQUIREMENTS.md` | 8/16/32-bit TIFF with all three compression values delivered; picker on the M2 export page and the legacy sheet, wired into the format spec (v1 EXP-01) |
| FEAT-EXP-14 | Software tag written into exports (producer identification) | Alcedo | Delivered | `src:LightamerCore/Sources/Export/ExportQueue.swift` | EXIF Software via the TIFF dictionary seat |
| FEAT-EXP-15 | PNG compression-level option (UI 0-9) | Alcedo | Missing | | Not exposed; the PNG encoder runs ImageIO defaults with no compression-level control |

## AI - AI features

| Id | Feature | Source | Status | Evidence | Notes |
|---|---|---|---|---|---|
| FEAT-AI-01 | Local semantic engine (CLIP-family on-device embeddings, images never leave the machine) | Alcedo | Delivered | `src:LightamerCore/Sources/AI/SemanticEngine.swift`, `src:LightamerCore/Sources/AI/SemanticStore.swift`, `doc:.work/gsd/phases/m2-10-ai-library/M2-10-VALIDATION.md` | |
| FEAT-AI-02 | Model catalog with multiple models/dimensions and hybrid acquisition (bundled default + release assets) | Alcedo | Delivered | `src:LightamerCore/Sources/AI/ModelAssetCatalog.swift`, `src:LightamerCore/Sources/AI/ModelAssetStore.swift`, `src:App/Sources/Lightamer/UI/AIDownloadPrompt.swift` | Alcedo's in-app HF download is broken upstream; hybrid strategy sidesteps it |
| FEAT-AI-03 | Approximate nearest-neighbor index for semantic search | Alcedo | Delivered | `src:LightamerCore/Sources/AI/SemanticStore.swift` | Alcedo uses DuckDB HNSW; ours is a SQLite-side index |
| FEAT-AI-04 | Automatic tagging (preset bilingual label queries, score/margin/confidence) | Alcedo | Delivered | `src:LightamerCore/Sources/AI/LabelEngine.swift`, `src:LightamerCore/Sources/AI/LabelQueries.swift` | |
| FEAT-AI-05 | AI caption/description via OpenAI/Anthropic-compatible providers | Alcedo | Delivered | `src:LightamerCore/Sources/AI/AIDescriptionService.swift`, `src:LightamerCore/Sources/AI/AIProviderClient.swift` | |
| FEAT-AI-06 | AI rating (1-5 stars + short reasons, written back to the library) | Alcedo | Delivered | `src:LightamerCore/Sources/AI/AIRatingService.swift`, `src:App/Sources/Lightamer/AI/AIRatingController.swift` | |
| FEAT-AI-07 | Credential storage in the system keychain | Alcedo | Delivered | `src:LightamerCore/Sources/AI/AICredentialStore.swift` | |
| FEAT-AI-08 | Provider settings (severity, output language, prompt profile guard) | Alcedo | Delivered | `src:App/Sources/Lightamer/Settings/ACASettingsModel.swift` | |
| FEAT-AI-09 | Isolated AI inference worker (crash-safe, worker-process boundary) | Lightamer | Delivered | `src:App/Sources/Lightamer/AI/AIWorkerClient.swift`, `src:App/Sources/Lightamer/AI/AIWorkerMain.swift` | Beyond Alcedo (in-process sidecar); isolation pattern credited to Lumen |
| FEAT-AI-10 | AI segmentation masks (subject/sky/people via SAM-class models) | Alcedo | V2 | `src:LightamerCore/Sources/AI/AIMaskTypes.swift`, `doc:.work/gsd/phases/v2-station/V2-PROPOSAL.md` | SAM CoreML is a V2 item (M6 charter ruling 7); native text-segmentation API verified absent (M6-4) |
| FEAT-AI-11 | Focus/bracket stack merge utilities | Lightamer | Delivered | `src:LightamerCore/Sources/Stack/FocusStackMerge.swift`, `src:LightamerCore/Sources/Stack/GhostMaskWriter.swift` | Own stack family (beyond Alcedo) |

## OWN - Lightamer-exclusive surface

| Id | Feature | Source | Status | Evidence | Notes |
|---|---|---|---|---|---|
| FEAT-OWN-01 | yiyin print-frame/watermark panel (first-class citizen, sheet + export sizing) | Lightamer | Delivered | `src:App/Sources/Lightamer/Yiyin/YiyinPanelView.swift`, `src:App/Sources/Lightamer/Yiyin/YiyinSheetSizing.swift` | |
| FEAT-OWN-02 | MCP server (tool registry over the library and editor) | Lightamer | Delivered | `src:App/Sources/Lightamer/MCP/McpServerController.swift`, `src:App/Sources/Lightamer/MCP/McpToolRegistry.swift` | Phase 14 surface |
| FEAT-OWN-03 | MCP single-writer lock + live-instance forwarding (`--connect`) | LightCraft | Delivered | `src:App/Sources/Lightamer/MCP/McpServerController.swift`, `doc:.work/gsd/phases/m6-1-interop/M6-1-VALIDATION.md` | M6 charter ruling 1 (project-level lock + connect) |
| FEAT-OWN-04 | Launch dialog for the MCP agent sidecar (status/log/copy surface) | Lightamer | Delivered | `src:App/Sources/Lightamer/UI/McpLauncherPanelView.swift` | |
| FEAT-OWN-05 | Film simulation family (scene->film->print chain, session solve, 28 profile set) | Lightamer | Delivered | `src:LightamerCore/Sources/Film/FilmMaterialStore.swift`, `src:LightamerCore/Sources/Graph/FilmRecord.swift`, `doc:.work/gsd/phases/m3-3-fsim/M3-3-03-ACCEPTANCE.md` | FSIM family; the display-tail row in the DRT domain mirrors it |
| FEAT-OWN-06 | Latitude panel (film latitude readouts, fit suggestion, placement solver) | Lightamer | Delivered | `src:App/Sources/Lightamer/UI/Shell/FilmPanelView.swift`, `doc:.work/gsd/phases/m3-4-latitude` | M3-4 descriptor runtime + panel |
| FEAT-OWN-07 | HDR merge (exposure bracket fusion, ghost suppression) | Lightamer | Delivered | `src:LightamerCore/Sources/Stack`, `doc:.work/gsd/phases/m5-2-mertens/M5-2-VALIDATION.md` | Robertson + Mertens legs |
| FEAT-OWN-08 | Mertens exposure fusion (streaming, MTB alignment, shared union mask) | Lightamer | Delivered | `src:LightamerCore/Sources/Stack/BandStreamer.swift`, `doc:.work/gsd/phases/m5-2-mertens/M5-2-VALIDATION.md` | |
| FEAT-OWN-09 | Panorama merge (feature matching, bundle adjustment, fused strip writer) | Lightamer | Delivered | `src:LightamerCore/Sources/Stack`, `doc:.work/gsd/phases/m5-3-pano/M5-3-VALIDATION.md` | SIFT-family + LM BA + row-streaming fusion |
| FEAT-OWN-10 | Tracking-assisted masks (TRACK family) | Lightamer | Delivered | `doc:.work/gsd/phases/m5-1-track/M5-1-VALIDATION.md` | |
| FEAT-OWN-11 | LUT library (recursive scan, configurable root, bundled spectral film set, encoding-aware) | Lightamer | Delivered | `src:LightamerIOP/Sources/Lut3d/LutLibraryStore.swift`, `doc:.work/gsd/phases/m2-5-color-grade/M2-5-3-ACCEPTANCE.md` | 40-film MIT-licensed set; encoding dimension per M3-1 |
| FEAT-OWN-12 | Denoise family (bilateral / NL-means / profiled) plus retouch, liquify, borders, watermark and the remaining dt-era modules | Lightamer | Partial | `src:LightamerIOP/Sources/NLMeans`, `src:LightamerIOP/Sources/DenoiseProfile`, `doc:.work/gsd/phases/m2-1-dt-disable/M2-1-MATRIX.md` | Beyond Alcedo (it has no denoise at all); disabled by default behind feature flags, opt-in face |

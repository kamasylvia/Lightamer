# Roadmap: Lightamer

**Created:** 2026-08-03
**Phases:** 13
**Granularity:** fine
**Mode:** standard (Horizontal Layers)

A macOS-native (Swift 6 + SwiftUI + Metal 3 + Core Image RAW) non-destructive RAW
editor combining Darktable-grade iop depth with a Capture One Session workflow and
Capture One-style adjustment layers. Phases are ordered by dependency: foundation →
pixelpipe core → iop clusters → layers/masking → native AI masking/retouching →
session/export → yiyin/metadata → system/distribution. Every v1 requirement maps to
exactly one phase.

## Phase Overview

| # | Phase | Goal | Requirements | Success Criteria |
|---|-------|------|--------------|------------------|
| 1 | Foundation, App Skeleton & Capability Spikes | Stand up the macOS 27 app, Metal dispatch, CIRAW 9 decode, IOPModule protocol + v50_order, MTKView viewport; resolve the CIRAW 9 / 100MP Metal capability boundary | FOUND-01, FOUND-02, FOUND-03, FOUND-05, FOUND-06, FOUND-07, RAW-01, RAW-02, RAW-04, RAW-05, RAW-06 | 5 |
| 2 | Pixelpipe Core, Color Management & History Stack | The load-bearing architectural phase: per-module per-ROI cache, multi-resolution pipes, terminal trio (colorin/colorout/gamma), linear Rec2020 color pipeline, history stack + hash, Lightamer-format sidecar | FOUND-04, COLOR-01, COLOR-04, HIST-01, HIST-02, HIST-03, HIST-04, RAW-03 | 5 |
| 3 | Tone & Filmic iops | Daily-workflow tone modules + the filmicrgb scene-referred tone mapper (hardest single port — spike-validated) | IOP-TONE-01, IOP-TONE-02, IOP-TONE-03, IOP-TONE-04, IOP-TONE-05, IOP-TONE-06, IOP-TONE-07, IOP-FILM-01, IOP-FILM-02, IOP-FILM-03 | 4 |
| 4 | Geometry, Lens & Detail iops | Crop/rotate/flip/lens correction + sharpen/local-contrast/highpass/equalizer; prove ROI negotiation end-to-end | IOP-GEO-01, IOP-GEO-02, IOP-GEO-03, IOP-GEO-04, IOP-DETAIL-01, IOP-DETAIL-02, IOP-DETAIL-03, IOP-DETAIL-04 | 4 |
| 5 | Color & Denoise iops | Advanced color modules + profiled/NLMeans/bilateral denoise (raw denoise spike — second-hardest port) | IOP-COLOR-01, IOP-COLOR-02, IOP-COLOR-03, IOP-COLOR-04, IOP-COLOR-05, IOP-COLOR-06, IOP-COLOR-07, IOP-COLOR-09, IOP-DENOISE-01, IOP-DENOISE-02, IOP-DENOISE-03, IOP-DENOISE-04 | 4 |
| 6 | Layers & Masking System | Capture One adjustment layers (base + named layers, per-layer iop + mask + blend) interdependent with drawn/parametric/raster masks; liquify + retouch depend on the mask framework | LAYER-01, LAYER-02, LAYER-03, LAYER-04, LAYER-05, LAYER-06, LAYER-07, IOP-MASK-01, IOP-MASK-02, IOP-MASK-03, IOP-MASK-04, IOP-MASK-05, IOP-GEO-05, IOP-GEO-06 | 5 |
| 7 | AI Modules (Native Vision Masking & Retouching) | Native Apple Vision subject-isolation masking + frequency-separation skin retouching (no custom Core ML models), feeding AI masks into the Phase 6 layer/mask system as editable inputs | AI-01, AI-05, AI-06, AI-07 | 4 |
| 8 | HDR/Stacking & Effects iops | HDR merge, focus/average/median stacking, 32-bit float HDR pipeline, EDR display output, creative effects (vignette/grain/bloom/dehaze/watermark iop) | IOP-HDR-01, IOP-HDR-02, IOP-HDR-03, IOP-HDR-04, IOP-HDR-05, IOP-FX-01, IOP-FX-02, IOP-FX-03, IOP-FX-04, IOP-FX-05 | 4 |
| 9 | Capture One Session Management | Folder-as-session model, Capture/Crop/Output three-tier dirs, FSEvents watcher, multi-session, browse modes, copy/paste + before/after compare | SESS-01, SESS-02, SESS-03, SESS-04, SESS-05, SESS-06, HIST-05, HIST-06 | 5 |
| 10 | yiyin Border/Watermark Panel | Port yiyin (white border/EXIF overlay/date/logo/custom fonts/model-map) to native Core Image/CoreText as borders+watermark iop modules + SwiftUI panel | YIYIN-01, YIYIN-02, YIYIN-03, YIYIN-04, YIYIN-05, YIYIN-06, YIYIN-07, YIYIN-08 | 5 |
| 11 | Export Pipeline & Batch Queue | EXPORT pixelpipe, all 6 formats, multi-spec recipes, background queue with yiyin application as final step | EXP-01, EXP-02, EXP-03, EXP-04, EXP-05, EXP-06, EXP-07, EXP-08 | 5 |
| 12 | Metadata, Rating, Presets & LUT | Rating/labels/keywords, filtering/smart albums, native preset system, .cube LUT (1D/3D) as IOP-COLOR-08 module | META-01, META-02, META-03, META-04, META-05, META-06, PRES-01, PRES-02, PRES-03, PRES-04, IOP-COLOR-08 | 4 |
| 13 | System Integration & Distribution | Quick Look + Spotlight, soft proofing + multi-display ICC, gestures + drag-drop + i18n, GitHub open source + signed/notarized DMG + CI | SYS-01, SYS-02, SYS-03, SYS-04, SYS-05, DIST-01, DIST-02, DIST-03, DIST-04, COLOR-02, COLOR-03 | 4 |

## Phase Details

### Phase 1: Foundation, App Skeleton & Capability Spikes
**Goal:** Stand up the macOS 27 native app with the Metal dispatch framework, CIRAW 9
RAW decode, the `IOPModule` protocol + `v50_order` table, and an MTKView viewport
blitting a decoded RAW. Resolve the CIRAW 9 capability boundary and 100MP Metal
performance vertebra here — these determine v1 iop scope.
**Success Criteria**:
1. App launches on macOS 27 and opens a CR3/NEF/ARW RAW via CIRAW 9 (`decoderVersion = .version9`, gated behind `#available`), displaying the decoded image (unprocessed) in the MTKView viewport.
2. A trivial Metal compute pass-through kernel executes end-to-end (buffer in → buffer out), proving the `MetalContext` dispatch framework (device, library, `dispatch2D`, PSO caching, function-constants).
3. The `IOPModule` protocol and `v50_order` order table (`iop_order.swift`) compile, and a no-op pixelpipe chain (single pass-through piece) runs without error through the `EditorMTKView` NSViewRepresentable bridge.
4. CIRAW 9 capability spike documented (which demosaic/denoise/lens features it covers natively vs. which need Metal), and a 100MP GFX100S RAF decodes + displays without jetsman/memory failure (the architectural vertebra).
5. EXIF/IPTC/XMP (camera, lens, focal length, aperture, shutter, ISO, GPS, capture time) reads correctly via ImageIO; non-RAW formats (JPEG/HEIC/PNG/WebP/TIFF/PSD-flat) and Adobe DNG also decode.
**Requirements:** FOUND-01, FOUND-02, FOUND-03, FOUND-05, FOUND-06, FOUND-07, RAW-01, RAW-02, RAW-04, RAW-05, RAW-06
**Notes:** This is the architectural vertebra — every later phase plugs into this skeleton. Foundation decisions are expensive to reverse and are locked here (per research): macOS 27 floor, linear Rec2020 scene-referred working space, float32 RGBA premultiplied-alpha pipe buffers, `v50_order` module ordering, Metal-first pipe with CIRAW strictly as decoder. **Spikes (research-flagged, run in this phase):** (a) CIRAW 9 vs RAW 8 capability boundary — determines whether the demosaic-algorithm menu is a v1 hard requirement (large Metal port) or can defer to Apple-default; (b) 100MP Metal performance — confirm 60fps target is feasible at zoom/pan on a GFX100S file before committing the iop list; (c) preliminary filmicrgb port feasibility (full validation in Phase 3); (d) preliminary raw denoise profiling (full validation in Phase 5). Stand up the golden-image color harness scaffolding here (full harness lands in Phase 2 before any algorithm port). Risks: CIRAW-1/2/3, METAL-3/4, SOLO-1.

### Phase 2: Pixelpipe Core, Color Management & History Stack
**Goal:** The load-bearing architectural phase. Port the Darktable recursive pixelpipe
with per-module per-ROI cache + hash-hit fast path, multi-resolution pipes
(FULL/PREVIEW/THUMBNAIL/EXPORT), the terminal trio (colorin/colorout/gamma) for correct
display color, the history stack with stable identity tuple + history hash, and
Lightamer-format sidecar persistence.
**Success Criteria**:
1. Opening a RAW displays correct color on screen: camera RGB → linear Rec2020 working → display profile (from `NSScreen.colorSpace`) via the colorin/colorout/gamma terminal trio, verified against a known-neutral target.
2. Dragging a parameter invalidates only modules at or after the changed module's `iop_order`; upstream modules (rawprepare/demosaic/lens) hit the per-module per-ROI cache — verifiable via cache-hit logging (the 60fps mechanism).
3. History stack persists to a Lightamer-own-format sidecar (NOT Darktable-binary-compatible) and round-trips: write → close → reopen → identical params and rendered image.
4. Multi-resolution pixelpipe instantiated (FULL at zoom ROI, PREVIEW at ~1080px always-current, THUMBNAIL, EXPORT); tiling fallback scaffolding in place for buffers exceeding GPU working set.
5. History hash detects drift between in-memory and on-disk sidecar; the golden-image color harness (torture images: deep-shadow Bayer, saturated LED, X-Trans RAF, 100MP GFX, HDR stack) is live and gating before any Phase 3+ algorithm port.
**Requirements:** FOUND-04, COLOR-01, COLOR-04, HIST-01, HIST-02, HIST-03, HIST-04, RAW-03
**Notes:** The hardest pure-architecture phase. The recursive `processRec` + cache-hit fast path is the single most important pattern (Darktable `pixelpipe_hb.c:1838/1893`). Mirror Darktable's stable history identity `(op, multi_priority, multi_name, iop_order, blendop_version)` + per-module `version` int + mask-form versioning by id — getting this subtly wrong causes silent mask invalidation later (NDE-1/2/3/6). Lock `Codable & Hashable` params encoding strategy before writing the second module. CIRAW is strictly the decode layer here — never the engine. Risks: CIRAW-4/5, METAL-1/2/4/5/7, NDE-1..4/6, COLOR-1/2, PERF-1/2, SOLO-2/3/5.

### Phase 3: Tone & Filmic iops
**Goal:** Deliver the daily-workflow tone modules (exposure, white balance, tonecurve,
shadow/highlight, contrast, levels, tone equalizer) plus the filmicrgb scene-referred
tone mapper — the hardest single Darktable port (~2000 lines of scene-linear math) —
and its variants (sigmoid, other filmic). These close the core daily editing loop.
**Success Criteria**:
1. Exposure, white balance (with eyedropper sampling), tonecurve (per-channel RGB), levels, contrast, shadow/highlight recovery, and tone equalizer all render correctly against Darktable golden-image references at pinned params.
2. filmicrgb Metal port matches Darktable reference output within perceptual tolerance on the torture-image set (spike-validated — this is the decisive scene-referred port).
3. Slider drag on any tone module holds 60fps on a 100MP image at viewport resolution through the preview pipe (per-module cache + debounce working).
4. sigmoid and other filmic variants produce correct scene-referred tone mapping without highlight clipping; modules declare correct input/output colorspaces for auto-inserted conversions.
**Requirements:** IOP-TONE-01, IOP-TONE-02, IOP-TONE-03, IOP-TONE-04, IOP-TONE-05, IOP-TONE-06, IOP-TONE-07, IOP-FILM-01, IOP-FILM-02, IOP-FILM-03
**Notes:** filmicrgb is research's flagged "hardest single port" — the early spike (Phase 1 preliminary, full validation here) decides whether it lands in v1. Every module ships a `.swift` + `.metal` file pair and passes its golden test before merge (SOLO-2). All modules operate in linear Rec2020 scene-referred (COLOR-1). Risks: METAL-6/7, NDE-3, COLOR-1/2, PERF-5.

### Phase 4: Geometry, Lens & Detail iops
**Goal:** Geometry (crop, rotate/perspective, lens correction, flip/orientation) and
detail (sharpen, local contrast, highpass/soften, equalizer/detail enhancement) modules.
These prove the ROI negotiation (`modifyROIOut`/`modifyROIIn`) end-to-end and cover the
remaining daily-workflow table-stakes.
**Success Criteria**:
1. Crop with aspect-ratio lock + rotation micro-adjust, rotate/perspective correction (with auto-detect), and flip/orientation all behave correctly with live preview.
2. Lens correction (geometric distortion, lateral CA, vignette) applies via embedded DNG opcodes + manual sliders; CIRAW coverage gaps are filled by a Metal warp shader (Lensfun-XML-data-read-only or self-profile — open decision resolved in this phase).
3. Sharpen (USM + Gaussian/Laplacian variants), local contrast (clarity equivalent), highpass/soften, and equalizer/detail enhancement render against golden-image references.
4. ROI negotiation correctly handles crop's output shrink (forward pass) and sharpen/blur's wider input requirement (backward pass) — the minimal-region processing works.
**Requirements:** IOP-GEO-01, IOP-GEO-02, IOP-GEO-03, IOP-GEO-04, IOP-DETAIL-01, IOP-DETAIL-02, IOP-DETAIL-03, IOP-DETAIL-04
**Notes:** Lens-correction scope (Lensfun C++ link vs XML-data-only + Metal warp) is an open decision resolved here — affects v1 dependency surface (research recommends XML-data-only for v1). liquify (IOP-GEO-05) and retouch (IOP-GEO-06) are deferred to Phase 6 — they depend on the mask framework. Risks: CIRAW-3 (lens coverage holes), METAL-6/7, PERF-5.

### Phase 5: Color & Denoise iops
**Goal:** Advanced color modules (colorbalancergb, color calibration, channel mixer,
color zones, monochrome/B&W, vibrance, velvia, color contrast/curves) and the denoise
family (profiled raw denoise — the second-hardest port — NLMeans, bilateral/surface
blur, hot pixels/dark frame/chromatic noise).
**Success Criteria**:
1. colorbalancergb, color calibration (channel-mixer successor), channel mixer, color zones (per-hue/sat/lum zones), monochrome/B&W (with color-filter emulation), velvia, vibrance, and color contrast/correction curves all match Darktable references.
2. Profiled raw denoise (Metal port of Darktable `denoise (profiled)`, `denoiseprofile.cl`) matches Darktable reference within tolerance; per-camera noise profile is loaded from EXIF/metadata (spike validates the profiling approach — second-hardest port).
3. NLMeans, bilateral/surface blur, and hot-pixel/dark-frame/chromatic-noise reduction all reduce noise without detail loss on the torture images (deep-shadow Bayer, X-Trans RAF, 100MP GFX).
4. All color and denoise modules maintain 60fps drag on the preview pipe; tiling fallback engages when a denoise module's working set exceeds GPU memory on 100MP.
**Requirements:** IOP-COLOR-01, IOP-COLOR-02, IOP-COLOR-03, IOP-COLOR-04, IOP-COLOR-05, IOP-COLOR-06, IOP-COLOR-07, IOP-COLOR-09, IOP-DENOISE-01, IOP-DENOISE-02, IOP-DENOISE-03, IOP-DENOISE-04
**Notes:** IOP-COLOR-08 (.cube LUT) is grouped with the Presets phase (Phase 12) since it is the same feature as PRES-03. Raw denoise profiling is research's flagged spike (Phase 1 preliminary, full validation here) — decides whether per-camera noise profiles land in v1 or defer. Tiling fallback becomes load-bearing here (NLMeans/denoise on 100MP). Risks: METAL-1/6/7, NDE-3, COLOR-1/2/6, PERF-1/5.

### Phase 6: Layers & Masking System
**Goal:** The Capture One adjustment-layer architecture — the fundamental differentiator
from Darktable's per-iop masks. Base layer + named adjustment layers, each carrying
independent iop params + a mask + blend mode, coexisting with global iops in the same
pixelpipe. Masking (drawn/parametric/raster + combine ops) is interdependent with layers
and ships together. liquify and retouch depend on the mask framework and land here.
**Success Criteria**:
1. Background base layer + multiple named adjustment layers operate independently — each layer's exposure/color/sharpen iops apply only within that layer's scope (same iop can have different params per layer).
2. Drawn mask (brush, polygon, ellipse, path, bezier), parametric mask (luminance/color range with feather/invert/blur), raster mask (baked from other masks), and mask-combining operations (union/difference/intersection, mask groups) all functional and applicable to any adjustment layer.
3. PS-style blend modes (normal, multiply, screen, overlay, soft light, hard light, color dodge, burn, difference, hue, saturation, color, luminosity) composite correctly with per-layer opacity.
4. liquify (portrait distortion) and retouch (heal/clone brush) modules work — both architecturally depend on the mask/distortion framework.
5. Full layer stack (layers + per-layer iop params + masks + blend modes + opacity + visibility/reorder/duplicate/merge/group) persists to sidecar and round-trips; the architecture cleanly coexists global-iop and per-layer adjustments in one pixelpipe.
**Requirements:** LAYER-01, LAYER-02, LAYER-03, LAYER-04, LAYER-05, LAYER-06, LAYER-07, IOP-MASK-01, IOP-MASK-02, IOP-MASK-03, IOP-MASK-04, IOP-MASK-05, IOP-GEO-05, IOP-GEO-06
**Notes:** The largest architectural phase. Layers + masking are interdependent (research key finding) and must be designed into the pixelpipe from Phase 2 — they cannot be bolted on. This is the fundamental departure from Darktable's global-pipe + per-iop-mask model: the layer stack is the organizing mechanism for local adjustments. Mask versioning by stable id (not ordinal) and the history identity tuple from Phase 2 are what make this survive reorder/refactor (NDE-1). Risks: NDE-1/3, METAL-8, PERF-2.

### Phase 7: AI Modules (Native Vision Masking & Retouching)
**Goal:** Ship the subset of AI masking/retouching that Apple's **native** Vision/Core
Image frameworks implement directly — with no custom-trained Core ML models. That means
subject isolation via `VNGenerateForegroundInstanceMaskRequest` (AI-01) and frequency-
separation skin retouching built from Vision face/segmentation landmarks + Core Image
filters (AI-05) — with every AI mask feeding into the Phase 6 layer/mask system as an
editable input (AI-06) rather than as a black box (AI-07). All detection runs natively
on the Apple Silicon Neural Engine — no third-party ML models, no network calls.
**Success Criteria**:
1. Subject lifting (people/animals/food/generic objects, class-agnostic) via `VNGenerateForegroundInstanceMaskRequest` generates a correct mask on any demosaiced RAW image (not limited to iPhone ProRAW), and the macOS 27 WWDC26 enhancements (iterative tap/scribble/lasso refinement) are usable interactively.
2. AI frequency-separation retouching (high-pass/low-pass decomposition on the skin region located by Vision face landmarks + person segmentation, blurred via Core Image) produces natural-looking skin that preserves pores/edges — no plastic look; implemented purely from public Vision/Core Image APIs, no custom model.
3. AI masks integrate as layer/parametric mask inputs — an AI-generated mask can be baked to a raster mask (IOP-MASK-03) or applied directly as a parametric mask (IOP-MASK-02) on any Phase 6 adjustment layer (AI-06).
4. AI masks are editable, not black-box — manual edge refinement, feather, invert, and combine with other masks (IOP-MASK-04 operations) all work on a baked AI mask (AI-07).
5. All AI detection runs locally on the Neural Engine (offline, no network); latency on a 100MP image is acceptable for interactive use (cache result so re-edit does not re-run Vision).
**Requirements:** AI-01, AI-05, AI-06, AI-07
**Notes:** Depends on Phase 6 (Layers & Masking) — AI masks are consumed by the layer/mask system, so this phase ships after it. **Native-only scope decision:** research confirmed Apple's native AI capability boundary on macOS 27 — `VNGenerateForegroundInstanceMaskRequest` (subject) and Vision landmarks + Core Image filters (frequency-separation skin) are the only capabilities achievable without a custom-trained Core ML model. AI-02 (sky), AI-03 (portrait body-parts), AI-04 (generic semantic seg) were dropped from v1 because they have no public native multi-class API: `CIRAWFilter.semanticSegmentationSkyMatteImage` and `AVSemanticSegmentationMatte` only read iPhone-captured/ProRAW embedded mattes, and arbitrary-RAW versions would each need a custom DeepLab/face-parsing model — those now ship as AIV2-03/04/05 in the v2 section. AI-01 is implemented via `VNGenerateForegroundInstanceMaskRequest` (available macOS 14+, enhanced in macOS 27); AI-05 uses `VNFaceLandmarks2D` + `VNGeneratePersonSegmentationRequest` for skin-region location and a Metal/Core Image compute pass for the frequency separation. AI masks are NOT black-box — on generation they bake to an editable raster mask (Phase 6 IOP-MASK-03) and from there inherit all Phase 6 mask-edit affordances (AI-07); the baked mask is what is versioned in the history hash (NDE-1). Keep a pluggable segmentation interface so a higher-fidelity custom-model backend can be swapped in later (v2 AIV2 items) without rewriting AI-06/07 integration. Risks: PERF-1 (Neural Engine scheduling vs. Metal pipe), NDE-1/3.

### Phase 8: HDR/Stacking & Effects iops
**Goal:** HDR merge (bracketed exposures, alignment, de-ghosting), focus stacking,
average/median stacking for noise reduction, 32-bit float HDR pipeline continuation in
linear Rec2020, HDR/EDR display output, and the creative effects cluster (vignette,
grain, bloom/glow, dehaze, watermark/text overlay as an iop layer distinct from the
yiyin final-output watermark).
**Success Criteria**:
1. HDR merge of bracketed exposures produces an aligned, de-ghosted 32-bit float HDR image in linear Rec2020 that can continue through the normal edit pipeline.
2. Focus stacking and average/median stacking produce clean combined output with correct alignment.
3. HDR/EDR display output renders real high dynamic range on EDR-capable displays (`CAMetalLayer.wantsExtendedDynamicRangeContent`, headroom above 1.0 treated correctly — not as a different color space).
4. vignette, grain, bloom/glow, dehaze, and watermark/text-overlay iops render correctly and match references; watermark iop (order 77) is distinct from the yiyin final-export watermark.
**Requirements:** IOP-HDR-01, IOP-HDR-02, IOP-HDR-03, IOP-HDR-04, IOP-HDR-05, IOP-FX-01, IOP-FX-02, IOP-FX-03, IOP-FX-04, IOP-FX-05
**Notes:** 32-bit float TIFF/EXR/HIF source reading is already enabled by RAW-03 (Phase 2). EDR display work carries COLOR-4 risk (calibration, tone curve headroom) — test on both XDR and external HDR. HDR export depth (HEIC 10-bit gain map / AVIF 10/12-bit PQ/HLG) is an open decision; EDR preview ships here, full HDR export can lean on Phase 11. Risks: COLOR-4/5, METAL-1.

### Phase 9: Capture One Session Management
**Goal:** The Capture One Session workflow — folder-as-session, automatic
Capture/Crop/Output three-tier subdirectories, sidecar co-location, multi-session
switching with recent list, FSEvents folder watching with resilient out-of-band
handling, and browse modes (grid/single/culling). Adjustment copy/paste and before/after
compare (the remaining history-stack workflow features) land here.
**Success Criteria**:
1. Selecting a folder makes it a Session; Capture (originals + sidecars)/Crop (working copies)/Output (exports) subdirectories are auto-created and maintained (Capture One convention).
2. FSEvents watcher detects Finder add/move/delete and syncs the session view; orphaned sidecars (`.xmp` with no original) and original-orphaned sidecars are handled gracefully with a reconcile action — never a hard fail.
3. Multi-session switching with a recent-sessions list works with no state leakage between sessions (explicit session-scope teardown of pixelpipe + caches).
4. Browse modes functional: thumbnail grid, single large image, culling compare (multi-image side-by-side).
5. Adjustment copy/paste (full or partial params, batch apply across multi-select) and before/after compare (split, snapshot point, temporary-hold-to-view-original) work.
**Requirements:** SESS-01, SESS-02, SESS-03, SESS-04, SESS-05, SESS-06, HIST-05, HIST-06
**Notes:** Do NOT rely solely on FSEvents (coalescing, 4096-path limit, rename loss — Watchexec publicly called choosing FSEvents "a mistake"); use it as a hint and reconcile with a directory scan on focus. Treat the session folder as mutable and untrusted — re-derive state on access. HIST-05 (copy/paste) and HIST-06 (before/after) are workflow features layered on the Phase 2 history stack. Risks: SESS-1..5, NDE-5, PERF-2/3, UI-1/3.

### Phase 10: yiyin Border/Watermark Panel
**Goal:** Port the yiyin (壹印) border/watermark capability to a first-class native panel,
implemented as two terminal iop modules (borders at order 76, watermark at order 77,
matching Darktable) plus a SwiftUI panel. Feature parity with the standalone yiyin
project (which continues independent maintenance). Layout algorithm, EXIF extraction,
font management, and model-map normalization ported from Electron/Svelte/sharp to
Swift/Core Image/Core Text.
**Success Criteria**:
1. White border/frame generation (margin, ratio, color, aspect-ratio expansion, portrait↔landscape transform) produces output matching yiyin parity.
2. EXIF overlay (camera/lens/focal length/aperture/shutter/ISO/capture time — configurable fields and formats), date text (configurable font/size/color/position/rotation), and logo watermark (PNG/transparent, configurable position/size/opacity) render correctly.
3. Custom font management (.ttf/.otf upload, local-only, no network) works via CoreText; text-template system (preset + user-custom template strings) functional.
4. Make/Model brand normalization (Sony ILCE→α, Nikon Z→ℤ, etc.) ported from yiyin's model-map.
5. Output size/resolution config (DPI, long/short edge pixels, preserve original) drives both the in-editor preview and the export-time application.
**Requirements:** YIYIN-01, YIYIN-02, YIYIN-03, YIYIN-04, YIYIN-05, YIYIN-06, YIYIN-07, YIYIN-08
**Notes:** yiyin is a first-class panel, not a plugin. The yiyin repo stays independent; the Lightamer panel is a native rewrite with feature alignment. Implemented as terminal iop modules so the same config is shared between editor preview and export (EXP-05 in Phase 11 depends on this). Risks: none domain-specific beyond color-management correctness (COLOR-2).

### Phase 11: Export Pipeline & Batch Queue
**Goal:** The EXPORT pixelpipe variant (full-res, chosen output profile, no caches) with
all six formats, resize/DPI/color-space config, multi-spec simultaneous export recipes,
a background queue with progress/cancel/retry, yiyin border/watermark application as the
final step, and post-export actions.
**Success Criteria**:
1. All six formats export correctly: JPEG (quality), PNG (8/16-bit), TIFF (8/16/32-bit float + compression), HEIF/HEIC (quality, 10-bit), WebP (libwebp SPM, lossy/lossless), AVIF (native macOS 27 `CGImageDestination`, libavif SPM fallback, 8/10/12-bit).
2. Export queue runs in the background with progress reporting, cancellation, and failure retry; does not block editing (separate MTLCommandQueue, lower priority, bounded concurrency).
3. Multi-spec simultaneous export works: one source → many size/format/watermark combos (export recipes) in one queue action.
4. Export applies yiyin border/watermark as the final step (sharing config with the Phase 10 panel); output color space (sRGB/Display P3/Adobe RGB/ProPhoto/Rec2020) selectable with embedded ICC profile.
5. Post-export actions (run shell script, open folder in Finder) execute; files land in Session/Output/.
**Requirements:** EXP-01, EXP-02, EXP-03, EXP-04, EXP-05, EXP-06, EXP-07, EXP-08
**Notes:** Ordered after Phase 10 (yiyin) because EXP-05 applies the yiyin border/watermark. AVIF uses native macOS 27 encode (the macOS 27 floor removes the libavif dependency that SUMMARY.md flagged for older OS); libavif retained as a fallback SPM dep. WebP always needs the libwebp SPM dep (Apple does not expose WebP write). EXIF + XMP packet embedded in output (round-tripped + edited metadata). Risks: PERF-4, INTEROP-1.

### Phase 12: Metadata, Rating, Presets & LUT
**Goal:** Metadata/organization (star rating, color labels, hierarchical keywords,
standard EXIF/IPTC/XMP read-write, filtering/sorting, smart albums), the native preset
system (save full adjustment stacks as `.lightamer-preset`), preset manager, and `.cube`
LUT import + application as the IOP-COLOR-08 module (1D/3D, DOMAIN_MIN/MAX, tetrahedral
interpolation).
**Success Criteria**:
1. Star rating (0-5), C1-style color labels, and hierarchical keywords are editable and synced to both the Lightamer sidecar and standard EXIF/IPTC/XMP (interop with other tools).
2. Filter and sort by rating/label/keyword/camera/lens/date/ISO/focal length; smart albums (rule-based virtual groupings, no file copies) work.
3. Native preset system saves/loads complete adjustment stacks as `.lightamer-preset` (JSON/Codable); preset manager supports create/edit/delete/import/export/categorize; presets apply to single or batch.
4. `.cube` LUT (1D or 3D, honoring DOMAIN_MIN/MAX for float/HDR, tetrahedral interpolation as default) imports and applies as the IOP-COLOR-08 module with an explicit application color space selector (Darktable lut3d equivalent).
**Requirements:** META-01, META-02, META-03, META-04, META-05, META-06, PRES-01, PRES-02, PRES-03, PRES-04, IOP-COLOR-08
**Notes:** Presets are NOT interoperable with Darktable/Lightroom (locked decision) — `.lightamer-preset` is the own format; `.cube` LUT is the standard interop point. IOP-COLOR-08 and PRES-03 are the same feature (the `.cube` LUT module) and ship together here. `.cube` carries an explicit application color space to avoid the "LUT authored for sRGB applied in Rec2020" bug (INTEROP-2/3). Risks: INTEROP-2/3, NDE-6.

### Phase 13: System Integration & Distribution
**Goal:** macOS system integration (Quick Look extension with edited-preview rendering,
Spotlight indexing of rating/labels/keywords/EXIF, trackpad/mouse gestures, drag-drop
import, system-language localization via String Catalog) plus color-management
completeness (soft proofing, multi-display ICC auto-switch) and the release pipeline
(GitHub open source, Developer ID signing + notarization, DMG/zip, CI).
**Success Criteria**:
1. Quick Look extension previews RAW files from Finder (with edits applied, not just original thumbnails); Spotlight importer indexes rating/labels/keywords/EXIF so session photos are searchable system-wide.
2. Soft proofing (printer/output device gamut simulation with out-of-gamut warning, relative-colorimetric + BPC, applied as the last transform before display — never baked into the edit) and multi-display ICC profile auto-switch work.
3. Trackpad/mouse gestures (two-finger zoom, pinch, rotate, two-finger pan), drag-drop import (Finder → session or editor), and system-language localization (zh/en via String Catalog, structure prepared for more) all functional.
4. GitHub repository public (MIT or similar permissive license); Developer ID signed + notarized DMG/zip distribution (non-sandbox); CI (GitHub Actions) builds, tests, signs, notarizes, and publishes on tag.
**Requirements:** SYS-01, SYS-02, SYS-03, SYS-04, SYS-05, DIST-01, DIST-02, DIST-03, DIST-04, COLOR-02, COLOR-03
**Notes:** Spotlight importers and Quick Look extensions are separate processes with their own entitlements — keep them decoupled from the main (non-sandboxed) app so the non-sandbox decision holds (DIST-3). Deep-sign every embedded binary before notarizing; treat notarytool warnings as errors (Gatekeeper enforces what notarization only warns — DIST-1). Resolve all resource paths from `Bundle.main` (Gatekeeper translocation — DIST-2). COLOR-02 (soft proof) and COLOR-03 (multi-display ICC) complete the color-management pipeline started in Phase 2. Risks: CIRAW-2 (per-OS CI matrix), DIST-1..5, SOLO-4/5, UI-4, COLOR-3/4.

## Coverage
- Total v1 requirements: 123
- Mapped: 123 (100%)
- Unmapped: 0 ✓

### Per-phase counts
| Phase | Requirements |
|-------|--------------|
| 1 — Foundation, App Skeleton & Spikes | 11 |
| 2 — Pixelpipe Core, Color Mgmt & History | 8 |
| 3 — Tone & Filmic iops | 10 |
| 4 — Geometry, Lens & Detail iops | 8 |
| 5 — Color & Denoise iops | 12 |
| 6 — Layers & Masking System | 14 |
| 7 — AI Modules (Native Vision Masking & Retouching) | 4 |
| 8 — HDR/Stacking & Effects iops | 10 |
| 9 — Capture One Session Management | 8 |
| 10 — yiyin Border/Watermark Panel | 8 |
| 11 — Export Pipeline & Batch Queue | 8 |
| 12 — Metadata, Rating, Presets & LUT | 11 |
| 13 — System Integration & Distribution | 11 |
| **Total** | **123** |

### Spike summary (research-flagged)
| Spike | Phase (preliminary) | Phase (full validation) |
|-------|---------------------|-------------------------|
| CIRAW 9 vs RAW 8 capability boundary (determines demosaic-menu v1 scope) | 1 | — (decision) |
| 100MP Metal performance vertebra (60fps feasibility on GFX100S) | 1 | 2 (cache fast path) |
| filmicrgb Metal port validation vs Darktable reference (~2000 lines) | 1 | 3 |
| Raw denoise profiling feasibility (per-camera noise profiles) | 1 | 5 |
| Darktable XMP import round-trip (validate import-tolerant parser) | — | 2 (sidecar) |

---
*Last updated: 2026-08-03 — Phase 7 rescoped to native-only AI (4 reqs); AI-02/03/04 moved to v2*

# Project Research Summary — Lightamer

> Synthesis of STACK, FEATURES, ARCHITECTURE, and PITFALLS research.
> Audience: roadmap creation. Date: 2026-08-03.

## Key Findings

1. **CRITICAL CORRECTION — "Core Image RAW 9" is NOT macOS 14/15.** PROJECT.md and several downstream assumptions conflate RAW 9 with the current macOS line. RAW 9 is Apple's ML-fused demosaic+denoise engine (a tiled CoreML model run on the Neural Engine) that ships in **macOS 27 / iOS 27 (WWDC26 Session 305)**, currently in beta for fall 2026 GA. The shipping OSes — macOS 14 (Sonoma), 15 (Sequoia), and 26 (Tahoe) — all ship **RAW 8**, which is the realistic decode floor for at least the first ~12 months of the project. **Implication:** v1 cannot require RAW 9. Plan to *opt in* to RAW 9 per-image (`decoderVersion = .version9`, gated behind `if #available(macOS 27, *)`) and fall back to RAW 8 otherwise. Rewrite PROJECT.md's "Core Image RAW 9" framing to "Core Image RAW, with RAW 9 as an opt-in upgrade on macOS 27+."

2. **CIRAW (RAW 8 or 9) is a decoder, not an engine.** It directly covers only ~8–10 of Darktable's 91 iop modules (demosaic-as-a-black-box, exposure, WB, luminance NR, sharpen, baseline, lens-embedded geometry, flip, crop). It explicitly does NOT cover: algorithm-selectable demosaic, profiled denoise, a lens database, DCP profiles, or any creative tone/color iop (filmic, sigmoid, colorbalancergb, colorzones, toneequal, diffuse). The Metal iop pipeline is the project, not a gap-filler. Build the pixelpipe as Metal-first; treat CIRAW strictly as the RAW-to-linear-scene-RGB decode layer plus a small handful of optional iops.

3. **The Darktable pixelpipe pattern is the load-bearing performance architecture.** 60fps on 100MP images is achieved by the *composition* of: a low-res preview pipe (always-current, fast), a full pipe (zoom ROI), per-module per-ROI caching keyed on a params hash, tiling fallback when a buffer exceeds GPU memory, and a "drag = preview-only" fast path. A single 100MP RGBA32F plane is ~1.6 GB — full re-render on every slider tick is fatal. The recursive cache-hit-fast-path (walk modules backwards, hash-check, return cached buffer to skip all upstream work) is the single most important pattern to port from `src/develop/pixelpipe_hb.c:1838`.

4. **Darktable sidecar binary-blob round-trip is unachievable; scope to import-tolerant.** Darktable's `darktable:params` is base64 of a raw in-memory C struct, versioned per-module via `modversion`, and even Darktable itself can drop params across versions. "Binary-compatible sidecars" promised in PROJECT.md is a trap. Scope v1 to **import-tolerant** (read Darktable XMP, reconstruct an equivalent history best-effort, document lossy mappings) and store Lightamer's own params in a versioned namespace. Round-trip-faithful is a non-goal.

5. **macOS floor should be macOS 14 (Sonoma), with macOS 26 (Tahoe) as the recommended runtime.** macOS 14 is the SwiftUI-stability floor (`NavigationSplitView`, `@Observable`, String Catalog all stable). All load-bearing Metal 3 features ship from macOS 13. macOS 26 removes the libavif AVIF-encode dependency (native `CGImageDestination` AVIF write landed in Tahoe) but costs the ~24% still on Sequoia. Set `MACOSX_DEPLOYMENT_TARGET = 14.0`, gate Tahoe-only features behind `#available`, document macOS 26 as recommended runtime, and re-evaluate the floor upward once Tahoe crosses ~70% adoption (likely mid-2027). **Do not target macOS 27** — install base will be near-zero at launch.

6. **WebP export always needs an SPM dependency; AVIF needs one below macOS 26.** Apple does not expose WebP *write* through `CGImageDestination` even on Tahoe, and AVIF write is gated to macOS 26+. Ship two tiny SPM packages (`swift-libwebp`, `swift-libavif`/`avif.swift`); use `#available(macOS 26, *)` to prefer native AVIF encode where available. This satisfies the minimal-dependency constraint (2 packages total).

7. **91 iop modules is multi-milestone scope, not v1 scope.** CIRAW covers ~8–10; ~80 must be Metal-compute ports from Darktable's OpenCL `.cl` kernels. Porting all 91 in v1 guarantees a non-converging roadmap (the RapidRAW/RethinkRAW lesson). v1 should ship a bounded working-set of ~15–20 highest-value iops that close the daily workflow loop; long-term parity is a multi-milestone arc. Publish the priority list so "parity" is bounded publicly.

8. **Half-float (`half`) and CIImage-lazy chains are silent correctness/performance killers.** Using `float` literals inside `half` math, or storing intermediates as `RGBA16Float`, will band in deep shadows — invisible until a GFX100S RAF gets pushed. Chaining 8–12 `CIFilter`s on a 100MP image holds gigabytes of lazy ROI descriptors. Standardize the pipe on **float32 RGBA throughout**, render CIImage chains to `MTLTexture` at well-defined cache points, and stand up a golden-image color harness (torture images: deep-shadow Bayer, saturated LED, X-Trans RAF, 100MP GFX, HDR stack) before porting any algorithm.

## Stack Recommendation

**Adopt:**
- **Swift 6 + SwiftUI** (`NavigationSplitView`, `@Observable`, String Catalog zh/en). `NSViewRepresentable` is used in exactly one place — the editor viewport.
- **Metal 3** (`MTKView`/`CAMetalLayer` direct-render viewport + `MTLComputeCommandEncoder` MSL compute kernels for the iop pipeline). Apple-Silicon-unified-memory; tile shaders, programmable blending, rasterization order groups Tier 2, `half` throughput, build-time `.metal` compilation.
- **Core Image RAW** (`CIRAWFilter` + `CIRAWFilterOption`) — RAW-to-linear-scene-RGB decode only. Pin `decoderVersion` explicitly (RAW 8 default, RAW 9 opt-in on macOS 27+).
- **ImageIO / `CGImageDestination`** — JPG/PNG/TIFF/HEIF encode (always), AVIF encode (macOS 26+).
- **ColorSync + EDR** (`CGColorSpace`, `NSScreen.colorSpace`, `CAMetalLayer.wantsExtendedDynamicRangeContent`, `.rgba16Float` for display, float32 in the pipe) — color management + HDR viewing.
- **MPS (Metal Performance Shaders) selectively** — separable Gaussian for `lowpass`/`shadhi`, Sobel for edge detection, area resample, histogram. Not a substitute for bespoke iop math.
- **SPM dependencies (exactly 2):** `swift-libwebp` (WebP encode, always), `swift-libavif`/`avif.swift` (AVIF encode below macOS 26).

**macOS floor:** `MACOSX_DEPLOYMENT_TARGET = 14.0` (Sonoma). Rationale: SwiftUI stability (`NavigationSplitView`/`@Observable`/String Catalog), Metal 3 full Apple-GPU feature set, EDR maturity. Document macOS 26 (Tahoe) as the recommended runtime (removes the libavif dependency, aligns with pro-photo upgrade cadence). Do not require macOS 27.

**Do NOT use:**
- OpenCV (CPU-bound, wrong layer; iop algorithms live in Darktable `.cl` kernels).
- Electron / Qt / Flutter (violates native + Metal-direct-render + SwiftUI constraints; cannot interop with CIRAW/EDR cleanly).
- libraw / dcraw as a primary decode path (Apple already decodes ~600+ cameras natively; defer to v2+ only if a real coverage gap appears).
- SDL / GLFW / GLKit for the viewport (OpenGL-era; the viewport must be `MTKView`).
- Lensfun C++ as a hard dependency in v1 (ship Lensfun XML *data* read-only + a Metal warp shader, or rely on embedded DNG opcodes; revisit linking only if data-only proves insufficient).
- A custom RAW decoder (out of scope; Apple's decoder is good and getting better).
- ImageMagick (massive C dep; use `CGImageDestination` + 2 SPM bindings).
- Standalone Little-CMS / skia (ColorSync is the macOS-native equivalent and already wired into `CIContext`).

## Table Stakes Features (v1 must include)

- RAW decode for major formats (CR3/NEF/ARW/RAF/RW2/ORF/DNG) + JPEG/HEIC/PNG/WebP/TIFF
- Non-destructive editing: ordered history stack, sidecar (.XMP) persistence, never writes source RAW
- Core tone/color iops (the v1 working-set, see "Darktable iop Scope Reality Check"): exposure, white balance, curves, levels, contrast, vibrance
- Crop / rotate / flip + aspect-ratio presets
- Lens correction (distortion/CA/vignette) — embedded-opcode + manual sliders minimum; Lensfun-database-driven is an open decision
- Sharpening + basic denoise
- Highlight/shadow recovery + highlight reconstruction
- Histogram + clipping warnings
- Before/after compare (split / snapshot)
- Rating + color labels + flags synced to sidecar/XMP
- Metadata (IPTC/XMP title/desc/keywords) + keyword tagging
- Export to JPG/PNG/TIFF/HEIF/WebP/AVIF with resize/quality/color-space
- Batch export queue + multi-spec simultaneous export
- Adjustment copy/paste sync across images
- Presets/styles (save/load named adjustment stacks)
- Spotlight + Quick Look integration
- Undo/redo
- Color management (ICC profiles, soft-proof)

## Differentiators (Lightamer's competitive edge)

- **Metal-native at 100MP** — MTKView direct-render, 60fps target on GFX100S/A7R V/Phase One. Darktable (OpenCL/CPU) struggles here.
- **Capture One Session workflow in a native app** — folder-as-session, Capture/Crop/Output/Trash, per-image sidecars, multi-session switching, recent-sessions list. No Mac RAW editor offers DT-grade edits in a C1-Session model.
- **Darktable iop depth** — long-term goal is the full ~91-module set; v1 ships the daily-15 working-set but the architecture is built for full parity.
- **Integrated yiyin border/watermark panel** — first-class, not a plugin. White border / date / EXIF overlay / logo watermark / custom fonts / portrait↔landscape transform, all native Core Image/Core Text.
- **Darktable preset interop** — read/write `.dtstyle`; treat `.cube` LUT as an iop module (DT LUT-module interop).
- **Darktable sidecar interop** — import-tolerant XMP reading.
- **Multi-spec simultaneous export** — one source → many (size/format/watermark) outputs in one queue action.
- **Native macOS UX** — SwiftUI panels, gestures, Spotlight/Quick Look, no Electron/Qt/JNI overhead.
- **Open-source + native** — DT is open but C/GTK; C1/Lr are closed. Lightamer fills the open-native gap.

## Anti-Features (deliberately exclude)

- **Lightroom-style central catalog** — conflicts with Session philosophy (folder-as-truth).
- **Cloud sync / cloud storage** — local-first; adds accounts/infra, conflicts with the portable-folder model.
- **AI auto-tagging / AI scene detection** — battery/privacy cost; personal-use users tag manually.
- **iOS / iPadOS companion** — macOS-only (Metal/Core Image/SwiftUI dependency).
- **Windows / Linux ports** — depend on Metal/Core Image; fundamental.
- **Mac App Store / sandbox** — sandbox blocks arbitrary folder access needed for Session mode.
- **Account system / subscriptions / login** — open-source, free, personal-use.
- **Social sharing / community features** — export is the deliverable.
- **Mobile-camera capture / phone-as-camera** — tethering targets real cameras.
- **Video editing** — stills-only RAW editor; yiyin's ffmpeg dep is out-of-scope.
- **NFT / blockchain / content credentials (C2PA)** — not requested; scope creep.

## Darktable iop Scope Reality Check

Darktable ships **91 distinct registered iop modules** (verified in `src/iop/CMakeLists.txt`), grouped into Tone (17), Filmic (5), Color (21), Detail (6), Denoise (8), Geometry (13), Local/Masking (4), Effects (16), Internal (6). Of these, **CIRAW (RAW 8 or 9) directly covers only ~8–10**: demosaic (as an opaque Apple algorithm), exposure, baseline, white balance, basic luminance NR, basic sharpen, lens-embedded geometry, flip, crop, simple contrast. The remaining **~80 are Metal-compute ports**, sourced line-by-line from Darktable's OpenCL `.cl` kernels in `data/kernels/` — the project's single biggest algorithmic asset.

**Recommendation: a bounded v1 working-set of ~15–20 highest-value iops, not all 91.** A v1 set that closes the daily workflow loop:

- **Head/decode (CIRAW):** rawprepare, demosaic (Apple default), temperature (WB)
- **Reconstruction:** highlights (ship one algorithm — opposed or laplacian)
- **Geometry:** flip, crop/clipping, lens (manual distortion/CA/vignette; Lensfun-DB-driven is an open decision)
- **Tone:** exposure, tonecurve (or rgblevels), shadhi
- **Color:** colorin (input ICC — mandatory), colorout (output ICC — mandatory), basicadj or colorbalance (v1 stand-in), vibrance, velvia
- **Detail/denoise:** sharpen, denoiseprofile (simple version) or CIRAW luma NR
- **Display/terminal:** gamma, filmicrgb OR sigmoid (pick one — filmic is the harder port but is *the* DT tone mapper), borders (yiyin), watermark (yiyin)

Masking, liquify, retouch, colorbalancergb, colorzones, channelmixerrgb, toneequal, diffuse, negadoctor, agx, LUT3D, and the full per-method demosaic menu (RCD/AMaZE/VNG/Mark.3-pass/dual) are deferred to post-1.0 milestones. **Publish this priority list publicly** so "Darktable parity" is a bounded claim, not an open-ended one.

## Architecture Vision

**Components:** SwiftUI shell (NavigationSplitView: session sidebar / lighttable grid / darkroom) → Viewport Bridge (the single `NSViewRepresentable` wrapping `MTKView`, with an `EditorRenderer` owning the per-frame render loop) → Application/Domain layer (`EditorController` actor: owns Develop history, owns three PixelPipes, debounces param changes; `SessionManager`; `ExportQueue`) → iop Module System (`IOPModule` protocol with `associatedtype Params: Codable & Hashable`, `ModuleRegistry`, one `.swift` + `.metal` file per module) → Metal Kernel Dispatch (`MetalContext` actor: device, library, dispatch2D helper) → RAW Decode Layer (thin `CIRAWFilter` wrapper) → Session subsystem (FolderWatcher, SidecarManager, MipmapCache three-tier thumbnail store) → System integration (Spotlight importer extension, Quick Look extension, ColorSync/EDR, soft-proof).

**The load-bearing pattern** is the **Darktable pixelpipe + per-module per-ROI cache**: a multi-resolution DAG of iop instances. Three pipes (preview ~1080px always-current; full at zoom ROI; export full-res). The recursive `processRec` walks modules backwards, hash-checks each module's cacheline (`imgid, pipeType, position, roi, paramsHash`), and on hit returns the cached buffer — skipping all upstream reprocessing. When you drag exposure, only modules *after* exposure invalidate; everything upstream (rawprepare, demosaic, lens) is a microsecond cache hit. Tiling fallback (tile grid computed from `device.recommendedMaxWorkingSetSize` + module `factor_cl`) handles 100MP buffers that exceed GPU memory; CPU fallback is the third tier. The OpenCL `process_cl`/`dt_opencl_enqueue_kernel_2d` pattern maps 1:1 to `MTLComputeCommandEncoder` + `dispatchThreadgroups:threadsPerThreadgroup:`. Module ordering is Darktable's `v50_order` verbatim (`iop_order.c:298-415`), so the decades of ordering rationale and sidecar round-trip semantics carry over.

**Suggested build order (one paragraph):** Phase 0 foundation skeleton — project + MetalContext actor + CIRAW wrapper + `PixelPipe` no-op skeleton + `EditorMTKView` blitting a static texture; **resolve the CIRAW capability boundary here** because it determines v1 iop scope. Phase 1 pixelpipe core — `PipeCache` + recursive `processRec` with cache-hit fast path + ROI negotiation + the terminal trio (`colorout`, `gamma`, minimal `rawprepare`) + golden-image color harness (built before any algorithm port). Phase 2 first real iops + preview/full pipe split + HistoryStack + histogram. Phase 3 Session model + sidecar + lighttable grid + MipmapCache. Phase 4 export (EXPORT pipe + queue + encoders). Phase 5 advanced iops (the long arc toward parity). Phase 6 yiyin panel. Phase 7 system integration + EDR/HDR + localization + presets/interop + polish/distribution.

## Top Risks & Pitfalls

1. **Treating CIRAW as "the engine" rather than "the decoder."** It locks you out of Darktable parity (no algorithm-selectable demosaic, no per-camera noise profile, no lens DB, no creative iop). **Prevention:** Metal-first pipe; CIRAW strictly decodes RAW→linear-scene-RGB and supplies a handful of optional iops. *(CIRAW-1, CIRAW-3)*
2. **Full-pipeline re-render on every slider drag kills 100MP interaction.** A 100MP RGBA32F plane is ~1.6 GB. **Prevention:** preview/full dual-pipe, per-module cache with hash-hit fast path, viewport-resolution rendering during drag, full-res on release, tiling fallback. *(PERF-1, PERF-2, METAL-8, NDE-4)*
3. **History/sidecar data model gets subtly wrong.** Skipping `iop_order`/`blendop_version`/`multi_priority`/per-module `version`/history-hash causes silent mask invalidation and un-reproducible edits after refactor. **Prevention:** mirror Darktable's stable identity tuple `(op, multi_priority, multi_name, iop_order, blendop_version)`, versioned mask forms by id (not ordinal), per-module `version` int with explicit migration, history hash for drift detection. *(NDE-1, NDE-2, NDE-3, NDE-6)*
4. **Half-float banding in shadows + CIImage lazy-chain memory blowup.** Invisible until a deep-shadow RAF/GFX file is pushed; chaining 8–12 CIFilters on 100MP holds gigabytes. **Prevention:** float32 RGBA throughout the pipe, `0.5h`/explicit `half(...)` casts in half code, render CIImage chains to `MTLTexture` at well-defined cache points, push-a-(-4 EV)-shadow-ramp golden test. *(METAL-2, CIRAW-4)*
5. **DecoderVersion / filter-key meaning drift across macOS releases.** Same CR3 renders differently across OS versions; RAW 9 silently downgrades on older OS. **Prevention:** pin `decoderVersion`, version-stamp sidecars with the decoder used, golden-image regression per supported OS in CI. *(CIRAW-2)*
6. **Darktable XMP round-trip fidelity is a trap.** Promise = byte-identical sidecars; reality = Darktable's non-standard namespaces are ignored by everything else, including Darktable across versions. **Prevention:** scope v1 to **import-tolerant** (read + reconstruct best-effort, document lossy mappings), Lightamer-native params in a versioned namespace, never promise round-trip-faithful. *(INTEROP-1)*
7. **Scope creep from "parity with Darktable" (91 modules).** Roadmap never converges; v1 keeps slipping. **Prevention:** define the ~15–20-module v1 working-set publicly, treat the rest as post-1.0 milestones. *(SOLO-1)*
8. **Algorithm porting without a test harness.** Hand-porting C→MSL with no way to verify equivalence; bugs surface months later. **Prevention:** golden-image harness FIRST (Darktable reference output at pinned params for torture images, per-pixel + perceptual diff in CI), no module merges without passing its golden test, re-baseline per macOS version. *(SOLO-2, SOLO-3)*

## Implications for Roadmap

- **Phase ordering is dependency-driven; do not parallelize the foundation.** Foundation (RAW decode + MetalContext + pixelpipe skeleton + viewport bridge) → pipe core with cache + terminal trio + golden harness → first real iops + dual-pipe + history → Session model + sidecar → export → advanced iops (long arc) → yiyin panel → system integration/polish. Skipping ahead (UI before pipe renders, iops before cache) creates throwaway work.
- **The CIRAW capability spike must be Phase 0**, not Phase 2. It determines v1 iop scope: if the demosaic algorithm menu is a hard requirement, that's a large Metal port (`demosaic_rcd.cl` ~200 lines, `demosaic_markesteijn.cl` ~700); if Apple-default-only demosaic is acceptable for v1, the menu defers. Resolve before committing the iop list.
- **The golden-image color harness must be Phase 1, alongside the cache.** It is the prerequisite for every algorithm port (Darktable C → Metal MSL verification). Defer it and you ship silent color regressions with no way to attribute them.
- **Foundation decisions are expensive to reverse — they thread through every component.** Working color space, pipe buffer format, iop ordering scheme, module flag taxonomy, params encoding strategy, and the sidecar fidelity target all lock in Phase 0/1. Schedule explicit decision milestones; do not let them default.
- **RAW 9 gating decision (a spike, not a roadmap item):** spike on macOS 27 GM (fall 2026) to determine the GA camera list and whether RAW 9's ML denoise absorbs the `denoiseprofile` requirement. Until then, the roadmap treats RAW 9 as an opt-in future upgrade and plans against RAW 8.
- **Sidecar interop scope decision: ship import-tolerant, not round-trip-faithful.** The roadmap should explicitly drop "binary-compatible sidecars" (PROJECT.md constraint) in favor of "import-tolerant sidecars + Lightamer-native params." This is a scope-decreasing decision that unblocks the sidecar milestone and avoids an unachievable promise.
- **Where spikes are needed before commitment:** (a) CIRAW RAW 8 vs RAW 9 capability boundary on macOS 27 GM; (b) 100MP Metal performance (can we hold 60fps on a GFX100S file at zoom/pan — Phase 0 vertebra test); (c) filmicrgb Metal port validation against Darktable reference (the hardest single port, ~2000 lines of scene-linear math); (d) Darktable XMP import (round-trip a simple exposure+WB history to validate the parser).
- **Masking should ship in v1.1, not v1.** It's a framework that unlocks many iops but v1 ships global-adjustment-only; drawn brush masks in v1.1, parametric in v1.2. This keeps v1 converged.
- **Long-term Darktable parity is a multi-milestone arc, openly bounded.** Each post-1.0 milestone ships a cluster (tone mappers; color iops; detail/frequency; geometry/retouch; masks/blend; effects/creative). Publish the priority list in the roadmap.

## Open Decisions for Phase 1

These must be resolved early because they are expensive to reverse (they thread through every component):

1. **macOS floor.** Recommended: macOS 14.0 deployment target, macOS 26 recommended runtime, gate Tahoe/RAW-9 features behind `#available`. Confirm before Phase 0 Xcode project creation.
2. **Working color space.** Recommended: linear scene-referred Rec.2020 RGB (Darktable's default; enables round-tripping; all primaries real). Reject Lab as primary (used only inside specific modules via auto-conversion). Reject ProPhoto as default (imaginary green primary).
3. **Pixelpipe data type.** Recommended: float32 RGBA premultiplied alpha, in working space, throughout the pipe (Metal-native, supports masks in alpha). Changing this post-hoc rewrites every kernel.
4. **Module ordering scheme.** Recommended: adopt Darktable `v50_order` verbatim as a single source-of-truth `iop_order.swift` table — required for sidecar round-tripping and decades of ordering rationale.
5. **Sidecar fidelity target.** Recommended: import-tolerant (read Darktable XMP, reconstruct equivalent history best-effort, document lossy mappings), Lightamer-native params in a versioned namespace. Drop the "binary-compatible" promise from PROJECT.md.
6. **Demosaic algorithm menu.** Open: ship Apple-default-only (smaller v1, CIRAW covers) or expose DT's per-method menu (large Metal port: PPG/RCD/AMaZE/VNG4/Mark.3-pass/dual). Decide via the Phase 0 CIRAW spike.
7. **Lens-correction scope.** Open: embedded DNG opcodes + manual distortion/CA/vignette sliders (minimal v1), or Lensfun-database-driven correction (link Lensfun C++ vs ship XML data-only + Metal warp). Affects v1 dependency surface.
8. **iop params encoding strategy.** Recommended: `Codable & Hashable` Swift structs (Hashable feeds the PipeCache hash), with a custom `BinaryCodable` protocol for any module targeting Darktable XMP round-trip. Decide before writing the second module.
9. **ACES working space.** Open: ACEScg/ACES2065-1 a v1 requirement (ship the ACES ICC) or a v2 feature? Display P3 + linear Rec.2020 cover most photographers; recommend deferring ACES.
10. **HDR/EDR export depth.** Open: full EDR preview on HDR displays (well-supported); HDR *export* (HEIC 10-bit gain map / AVIF 10/12-bit PQ/HLG) in v1 scope or deferred? Recommend deferring HDR export; ship EDR preview in Phase 7.
11. **Hardware floor.** Recommended: Apple Silicon only (Intel+AMD fallback adds `.managed` vs `.shared` storage complexity, ROG/tile-shader gating, and serves a shrinking minority). Make this an explicit decision, not an accident.
12. **DCP support.** Open: Adobe DCP camera profile loading a v1 requirement (scope a DCP reader + Metal application) or rely on embedded matrices? Recommend deferring; revisit if target users explicitly need Adobe interop.

## Sources

### Apple developer documentation
- Core Image — `CIRAWFilter`: https://developer.apple.com/documentation/coreimage/cirawfilter
- `CIRAWFilterOption` keys (incl. `decoderVersion`, `supportedDecoderVersions`, `noiseReductionAmount`): https://developer.apple.com/documentation/coreimage/cirawfilteroption
- RAW Image Options: https://developer.apple.com/documentation/coreimage/raw-image-options
- ImageIO — `CGImageDestination`: https://developer.apple.com/documentation/imageio/cgimagedestination
- Metal — Tailor apps for Apple GPUs / TBDR: https://developer.apple.com/documentation/metal/tailor-your-apps-for-apple-gpus-and-tile-based-deferred-rendering
- Metal — HDR content: https://developer.apple.com/documentation/metal/hdr-content
- Metal — Setting Resource Storage Modes: https://developer.apple.com/documentation/metal/setting-resource-storage-modes
- Metal — Function specialization: https://developer.apple.com/documentation/metal/using-function-specialization-to-build-pipeline-variants
- Metal — Creating a custom Metal view: https://developer.apple.com/documentation/metal/creating-a-custom-metal-view
- SwiftUI — `NavigationSplitView`: https://developer.apple.com/documentation/swiftui/navigationsplitview

### WWDC sessions
- WWDC26/305 — Enhance RAW image processing with Core Image (RAW 9): https://developer.apple.com/videos/play/wwdc2026/305/
- WWDC23 — Optimize GPU renderers with Metal
- WWDC22/10054 — The SwiftUI Cookbook for Navigation
- WWDC22/10114 — Display EDR content with Core Image, Metal, and SwiftUI
- WWDC21/10161 — Explore HDR rendering with EDR
- WWDC21/10160 — Capture and process ProRAW images
- WWDC20/10602 — Harness Apple GPUs with Metal (programmable blending)
- WWDC20/10632 — Optimize Metal Performance for Apple silicon Macs
- WWDC16/606 — Advanced Metal Shader Optimization (half-float literal warning)
- Tech Talks 604/605 — Metal 2 tile shading / raster order groups

### Apple support / news
- RAW formats supported by iOS 18 / macOS Sequoia (120534): https://support.apple.com/en-us/120534
- RAW formats supported by iOS 26 / macOS 26 (122870): https://support.apple.com/en-us/122870
- Notarizing macOS software: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- File System Events (FSEvents): https://developer.apple.com/documentation/coreservices/file_system_events

### RAW 9 analysis (August 2026)
- PetaPixel — Apple's RAW Processing Finally Evolving After a Decade: https://petapixel.com/2026/06/10/apples-raw-processing-is-finally-evolving-after-a-decade-and-its-a-big-deal/
- 9to5Mac — iOS 27's new RAW 9 engine: https://9to5mac.com/2026/07/06/apple-overhauls-raw-photo-processing-with-ios-27-showcases-impressive-results/
- DPReview forums — Apple Raw Engine v9 hands-on (camera list): https://www.dpreview.com/forums/threads/apple-raw-engine-v9-new-noise-reduction-king.4838453/
- DPReview — Apple Core Image RAW 9 processing: https://www.dpreview.com/articles/6744459009/apple-core-image-raw-9-processing/
- RedSharkNews — Apple RAW 9 CoreML denoising: https://www.redsharknews.com/apple-raw-9-core-image-machine-learning-denoising
- Reddit r/MacOSBeta — Tahoe native AVIF writing: https://www.reddit.com/r/MacOSBeta/comments/1lb4ayr/tahoe_brings_support_for_writing_avif_files/

### macOS install-base statistics
- TelemetryDeck — macOS versions market share 2026: https://telemetrydeck.com/survey/apple/macOS/versions/
- BusinessStats — worldwide macOS version market share: https://businesstats.com/worldwide-macos-version-market-share/

### Swift Package options
- `avif.swift` (libavif binding): https://github.com/awxkee/avif.swift

### Color science
- PIXLS — "linear Rec. 2020 RGB" WHY!: https://discuss.pixls.us/t/linear-rec-2020-rgb-why/50611
- Darktable #13141 Rec2020 vs ProPhoto export: https://github.com/darktable-org/darktable/issues/13141
- Ansel — Scene-referred workflow: https://ansel.photos/en/workflows/scene-referred/
- Nine Degrees Below — Display-referred vs Scene-referred: https://ninedegreesbelow.com/photography/display-referred-scene-referred.html

### LUT
- parse-cube-lut (reference parser): https://github.com/thibauts/parse-cube-lut
- ACESCentral — 1D vs 3D in `.cube`: https://community.acescentral.com/t/using-aces-shaper-spaces-in-ocio-bakelut/589
- Tetrahedral vs Trilinear: https://www.alestemple.net/blog/tetrahedral-vs-trilinear-lut-interpolation.html

### FSEvents / file watching
- Watchexec — Mac FSEvents limitations: https://watchexec.github.io/docs/macos-fsevents.html
- fsnotify/fsevents (4096 path limit): https://github.com/fsnotify/fsevents

### HDR/EDR
- Greg Benz Photography — HDR: https://gregbenzphotography.com/hdr/
- BetterDisplay HDR discussion: https://github.com/waydab1/BetterDisplay/discussions/2706

### Solo-dev / scope precedents
- RapidRAW intro (PIXLS): https://discuss.pixls.us/t/introduction-rapidraw-a-gpu-accelerated-open-source-raw-editor/53585
- RethinkRAW: https://github.com/ncruces/rethinkraw

### Darktable source (local, `/Volumes/UNITEK/Documents/Development/darktable/`, build `nightly-496-gdc58cf0ba1`)
- `src/iop/CMakeLists.txt` — 91 registered iop modules (authoritative count)
- `src/iop/*.c` / `*.cc` — per-module implementations; key port sources: `demosaic.c`, `denoiseprofile.c`, `filmicrgb.c`, `sigmoid.c`, `colorbalancergb.c`, `colorzones.c`, `channelmixerrgb.c`, `toneequal.c`, `diffuse.c`, `lens.cc`, `cacorrect.c`, `cacorrectrgb.c`, `sharpen.c`, `rgbcurve.c`, `rgblevels.c`, `retouch.c`, `liquify.c`, `lut3d.c`, `exposure.c`, `colorin.c`, `colorout.c`
- `src/iop/demosaicing/` — 10 demosaic algorithms (amaze/ppg/vng/rcd/lmmse/dual/xtrans/etc.)
- `src/iop/hlreconstruct/` — 5 highlight-reconstruction algorithms
- `data/kernels/*.cl` — OpenCL kernels that port line-by-line to Metal Shading Language: `demosaic_rcd.cl`, `demosaic_ppg.cl`, `demosaic_markesteijn.cl`, `demosaic_vng.cl`, `denoiseprofile.cl`, `nlmeans.cl`, `filmic.cl`, `sigmoid.cl`, `colorbalancergb.cl` (in `extended.cl`), `locallaplacian.cl`, `guided_filter.cl`, `diffuse.cl`, `sharpen.cl`, `lut3d.cl`, `basic.cl` (CA, hot pixels), `atrous.cl`, `gaussian.cl`, `blendop.cl`
- `src/develop/pixelpipe.h` / `pixelpipe_hb.h` / `pixelpipe_hb.c` — pixelpipe types, recursive `processRec` core (line 1838), cache-hit fast path (1893)
- `src/develop/pixelpipe_cache.c` — `basichash` composition (99-120), cacheline LRU
- `src/develop/develop.h` / `develop.c` — `dt_develop_t`, `dt_dev_history_item_t`, history hash, reprocess/invalidation
- `src/develop/imageop.h` / `src/iop/iop_api.h` — module API contract, `dt_iop_module_t`, `dt_iop_flags_t`
- `src/develop/tiling.h` / `tiling.c` — `dt_develop_tiling_t`, tile-grid solver
- `src/common/iop_order.c` — `v50_order` canonical module ordering (298-415)
- `src/common/opencl.c` — OpenCL dispatch (maps 1:1 to Metal compute)
- `src/common/exif.cc` — `_set_xmp_dt_history` (4796), XMP key list (418-433), base64 blob encode/decode
- `src/common/history.c` / `.h` — `iop_order`, `blendop_version`, `multi_priority`, mask-form versioning, history hash
- `src/common/mipmap_cache.h` / `.c` — three-tier thumbnail cache (0-10, F, FULL)
- `src/common/colorspaces.c` — ICC profile matrices reference
- `src/imageio/imageio.c` — `dt_imageio_export_with_flags` (EXPORT pixelpipe, 1045)
- `src/control/control.h` / `jobs.c` — worker thread pool, reserved resources
- `src/views/{lighttable,darkroom,tethering,map,slideshow,print}.c` — 6 views
- `src/libs/` — 40+ lib panels; `src/libs/scopes/{histogram,waveform,vectorscope,split}.c`

### yiyin source (local, `/Volumes/UNITEK/Documents/Development/yiyin/`, v1.7.1)
- `README.md`, `package.json` — overview, Electron+Svelte+sharp+fluent-ffmpeg+exifreader
- `electron/src/interface.ts` — `IConfig`, `IFont`, `IPosition`, `IFieldInfoItem`
- `electron/src/config.ts` — 19 default output params
- `common/const/def-fields.ts` — 15 EXIF fields
- `common/const/def-temps.ts` — system templates with per-template font/position
- `electron/src/modules/image-tool/interface.ts` — canonical `OutputOption` spec
- `web/util/model-map.ts` — per-brand Make/Model normalization rules

### Capture One Session docs
- Sessions 101: Discussing the Concept: https://www.captureone.com/blog/sessions-101-discussing-the-concept
- Complete Guide to Sessions: https://support.captureone.com/hc/en-us/articles/360003115137

### Project context
- `/Volumes/UNITEK/Documents/Development/Lightamer/.planning/PROJECT.md`

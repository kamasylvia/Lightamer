# Project Research — Pitfalls (Lightamer)

> Domain-specific failure modes for a macOS-native (Swift + SwiftUI + Metal + Core Image RAW 9)
> non-destructive RAW editor with a Capture-One Session model and Darktable-parity iop target.
> Each pitfall lists **Warning signs**, **Prevention**, and the **Phase** that must address it.
> Phase shorthand: P0=Research/Spike · P1=RAW+Metal foundation · P2=iop modules · P3=Session/UI/Perf · P4=Interop/Export · P5=Polish/Distribution.

## Summary — Top 5 most dangerous pitfalls

1. **Core Image RAW cannot be the whole engine** — it gives no control over demosaic algorithm, noise-profile per-camera, or lens-correction coverage, and its `DecoderVersion`/filter keys shift meaning across macOS releases; treating CIRAW as "the decoder" without a Metal fallback layer locks you out of Darktable parity. *(CIRAW-1, CIRAW-3)*
2. **The non-destructive history/hash design is easy to get subtly wrong** — Darktable spent years on `iop_order`, `blendop_version`, `multi_priority`, mask-form versioning, and a history *hash* to detect drift; skipping these causes silent mask invalidation and un-reproducible edits after refactor. *(NDE-1, NDE-2, NDE-3)*
3. **Full-pipeline re-render on every slider drag kills the 100MP target** — a single 100MP RGBA16F plane is ~800 MB; without tiling, a dirty-flag DAG, and GPU-side preview/half-res interaction, the app will stall on every parameter tweak. *(PERF-1, PERF-2, METAL-8)*
4. **Half-float (`half`) precision silently bands in shadows** — using `float` literals inside `half` math, or storing intermediates as `RGBA16Float`, clips shadow gradients; this is invisible until a deep-shadow RAF/GFX file is pushed. *(METAL-2)*
5. **Darktable XMP round-trip fidelity is a trap** — Darktable writes its own non-standard XMP namespaces that nothing else reads; "binary-compatible sidecars" is unachievable for iop params and must be scoped to *import-tolerant*, not *round-trip-faithful*. *(INTEROP-1)*

---

## Pitfalls by Area

### Core Image RAW

- **CIRAW-1: Cannot select or override the demosaic algorithm.**
  - Warning signs: CIRAW picks its own demosaic (bilinear/PPG-ish) with no `kCIInputDemosaicAlgorithm` key; X-Trans (Fuji RAF) and Bayer detail look softer/different than Darktable AMaZE/VNG4; no way to expose a "demosaic method" dropdown backed by CIRAW.
  - Prevention: Treat CIRAW strictly as a *RAW-to-linear-scene-RGB* decoder (use `kCIRAWDecoderVersion` to pin behavior). Run a separate Metal demosaic stage you own (port Darktable `demosaic.c` algorithms: PPG, AMaZE, VNG4, LMMSE, passthrough, and the X-Trans variants). Never promise "CIRAW covers demosaic."
  - Phase: **P0/P1** — decide the decoder boundary before writing the pipeline.

- **CIRAW-2: `DecoderVersion` / `.v9` and filter-key meaning drift across macOS.**
  - Warning signs: Same CR3 renders differently on macOS 14 vs 15; `Boost`, `BaseNoise`, `NoiseReduction`/`noiseReductionAmount` produce different output after an OS upgrade; RAW "Engine 9" requires explicitly setting the `.v9` enum and silently downgrades on older OS.
  - Prevention: Pin a minimum macOS (14+ recommended; 15+ if you depend on Engine 9 features) and *fail loud* if `CIRAWFilter.decoderVersion` cannot be set to your target. Version-stamp sidecars with the decoder version used. Add a golden-image regression per supported OS in CI.
  - Phase: **P0** (min-OS decision) + **P5** (CI matrix).

- **CIRAW-3: Camera/lens coverage holes — no DCP, lagging camera support.**
  - Warning signs: A brand-new body (e.g., a 2026 Sony/Fuji) is unsupported until Apple ships an OS update; CIRAW has no Adobe-DCP equivalent so you cannot ship your own camera color profile; lens-correction (vignette/distortion/chromatic-aberration) coverage is whatever Apple baked in, with visible gaps vs Lensfun/Darktable lens database.
  - Prevention: Do not make CIRAW the sole RAW loader. Plan a LibRaw/RawSpeed-equivalent fallback (or a thin bundled libraw via Swift bridging) for camera coverage, and port Darktable's lens-correction module (Lensfun data) as a Metal stage. Treat "camera support" as a tracked matrix, not an assumption.
  - Phase: **P0** (decide fallback strategy) + **P2** (lens module).

- **CIRAW-4: CIImage filter-chain memory blowup from lazy evaluation.**
  - Warning signs: Memory climbs monotonically as you chain `CIFilter`s; chaining 8–12 filters on a 100MP image can hold gigabytes of intermediate ROI descriptors; Instruments shows the growth on-device but not in Simulator.
  - Prevention: Render CIImage chains to an `MTLTexture` early and cache *that*, not the live `CIImage`. Use `CIContext.render(_:to:)` into a Metal texture and break the lazy chain at well-defined cache points. Set `CIContext` with a Metal device and a `workingColorSpace` you control (see COLOR-1). Never let the viewport hold the unrendered chain.
  - Phase: **P1** (pipeline cache design).

- **CIRAW-5: Hidden color-management assumptions in CIRAW output.**
  - Warning signs: CIRAW tags output with a working space you didn't ask for; `CIContext.workingColorSpace` defaults can shift; tone curves / "Boost" assume display-referred handling and clip scene-linear highlights.
  - Prevention: Explicitly set `workingColorSpace` on every `CIContext`, force linear scene-referred output, and disable any CIRAW "look"/tone curve you don't control. Verify with a known-neutral test target.
  - Phase: **P1** + **P2** (color module).

### Metal Image Processing

- **METAL-1: Tile size vs texture size — writing one giant kernel for 100MP.**
  - Warning signs: GPU timeout / "GPU hang" on large images; one dispatch covers the whole image and stalls; memory spikes to multiple GB per pass.
  - Prevention: Tile the image (e.g., 512–2048 px tiles with overlap >= largest kernel radius) and dispatch per-tile into a compute pass. Reuse a ring of intermediate textures. Make tile size a tunable queried from `MTLDevice.maxThreadgroupMemoryLength` / `MTLTileRenderPipelineDescriptor`.
  - Phase: **P1** (core architecture).

- **METAL-2: Half-float (`half`) precision banding in shadows.**
  - Warning signs: Smooth shadow gradients show stair-steps; deep shadows posterize after multiple passes; using `0.5` (a `float` literal) inside `half` math silently widens to float then truncates back.
  - Prevention: Keep scene-linear intermediates in `RGBA32Float` (or at minimum `RGBA16Float` *only* for display-side buffers). Use `0.5h` / explicit `half(...)` casts for literals in half code. Add a "push a -4 EV shadow ramp through the full pipe" golden-image test. (WWDC16 #606 explicitly warns about float literals in half ops.)
  - Phase: **P1** + testing harness.

- **METAL-3: Rasterization Order Groups / tile shaders are Apple-Silicon-only.**
  - Warning signs: Code compiles on M-series, hard-crashes or no-ops on Intel+AMD Macs; you assumed ROG/tile-shader TBDR features are universal macOS.
  - Prevention: If min-OS allows Intel Macs, gate ROG/tile-shader paths behind `MTLDevice.supportsFamily(.apple1)`/`apple`-family checks and provide a discrete-GPU fallback. Simpler: set min-OS + min-hardware to Apple Silicon and drop the fallback — but make this an *explicit* decision, not an accident.
  - Phase: **P0** (hardware floor decision).

- **METAL-4: `MTLBuffer` vs `MTLTexture` storage modes and unified memory.**
  - Warning signs: Using `.managed` on Apple Silicon is pointless overhead; using `.shared` on Intel+AMD is wrong; forgetting `didModifyRange:` / `synchronize()` on managed buffers causes stale reads.
  - Prevention: Pick storage mode by device: `.shared` (default) on Apple Silicon UMA; `.managed` only on discrete GPUs. Prefer `.private` for GPU-only big textures and stage through a blit encoder. If Apple-Silicon-only (see METAL-3), `.shared` everywhere simplifies a lot.
  - Phase: **P1**.

- **METAL-5: Shader compilation cold-start latency.**
  - Warning signs: First interaction with a module stalls for hundreds of ms–seconds while the PSO compiles; ANGLE reported ~7 s cold starts — your permutations can be worse with 100+ iop modules.
  - Prevention: Use **function constants** (`[[function_constant(n)]]`) and `MTLPipelineDescriptor` function specialization to fold branches into PSO variants at pipeline-creation time, not per-draw. Pre-warm / async-compile PSOs for the active history stack on image open. Persist a pipeline-state cache. Consider `MTLDynamicLibrary` to ship pre-compiled metallib. (WWDC23 "Optimize GPU renderers with Metal".)
  - Phase: **P1/P3**.

- **METAL-6: MPS (Metal Performance Shaders) vs custom kernel tradeoffs.**
  - Warning signs: Reaching for MPS for everything, then hitting algorithms MPS doesn't have (e.g., guided filter, local tone map, wavelet); or rewriting everything custom when MPS convolution/median would be faster and maintained by Apple.
  - Prevention: Decide per-module: use MPS where it matches (convolution, area resample, histogram) and write custom Metal kernels for Darktable-specific algorithms. Document the boundary so contributors don't re-roll MPS equivalents.
  - Phase: **P2**.

- **METAL-7: Compute shader threadgroup shared-memory limits.**
  - Warning signs: Kernel fails to dispatch or silently runs single-threaded; `[[threadgroup]]` buffer exceeds `maxThreadgroupMemoryLength` (often 32 KB–64 KB depending on family).
  - Prevention: Query `MTLComputePipelineState.maxTotalThreadsPerThreadgroup` and threadgroup memory limit per device; size tiles to fit. Prefer sampling from textures over stuffing big tiles into threadgroup memory.
  - Phase: **P1/P2**.

- **METAL-8: Re-entrancy / invalidation storms on parameter drag.**
  - Warning signs: Dragging a slider queues dozens of in-flight compute encoders that pile up and then all commit, freezing the UI; writing-then-reading the same texture in one encoder triggers hazards.
  - Prevention: Coalesce parameter changes (debounce / latest-wins), cancel superseded encoders before they commit, use a single low-res "live" pipeline during drag and full-res only on release. Never read a texture you wrote in the same encoder without a barrier; use separate encoders or raster-order groups where available.
  - Phase: **P3** (interaction) — but the pipeline DAG must support it from **P1**.

- **METAL-9: Window resize / drawable scaling desync.**
  - Warning signs: Image blurs or letterboxes wrongly on resize; drawable size and viewport size disagree; content jumps when the window crosses a HiDPI boundary.
  - Prevention: Drive the drawable size from `MTKView`'s `drawableSize` callback, recompute the viewport in `draw(in:)`, and decouple *image* resolution (tiles) from *drawable* resolution (layer scale). Re-read size only on change, not every frame.
  - Phase: **P3**.

### SwiftUI + Metal Integration

- **UI-1: SwiftUI re-render storms invalidating the viewport.**
  - Warning signs: Frame rate drops whenever any `@Published`/`@State` changes; the whole SwiftUI tree above the `NSViewRepresentable` rebuilds on each slider tick; `updateNSView` fires per frame.
  - Prevention: Keep the Metal viewport's per-frame state *outside* SwiftUI (in a renderer object the `NSViewRepresentable` holds by reference). Push parameter changes via a command queue, not via SwiftUI bindings on the heavy view. Use `EquatableView` / `@ObservationIgnored` (macOS 14+) to cut re-renders.
  - Phase: **P3**.

- **UI-2: NSViewRepresentable/MTKView bridging overhead.**
  - Warning signs: Wrapping `MTKView` via `NSViewRepresentable` and then mutating `@State` inside `updateNSView` causes a SwiftUI→AppKit→SwiftUI feedback loop.
  - Prevention: `updateNSView` should only forward *genuine* config changes (device, color space, drawable size), never per-frame data. Let `MTKViewDelegate.draw(in:)` own the render loop. Consider a raw `NSView`+`CAMetalLayer` (Apple's "Creating a custom Metal view") if `MTKView`'s defaults fight you.
  - Phase: **P1/P3**.

- **UI-3: Gesture conflicts — trackpad pinch (zoom) vs scroll (pan).**
  - Warning signs: Pinch-to-zoom also scrolls; magnification gestures fight scroll-wheel; Wacom/tablet events behave differently.
  - Prevention: Adopt `NSMagnificationGestureRecognizer`/`NSScrollWheel` distinctions explicitly; separate zoom (magnification) from pan (scroll). Test with both trackpad and mouse-scroll-wheel — they deliver different event types.
  - Phase: **P3**.

- **UI-4: Dark-mode color assumptions.**
  - Warning signs: Hardcoded panel backgrounds that look wrong in Light mode; accent colors that clip on HDR/EDR displays; assume `NSColor.windowBackgroundColor` is dark.
  - Prevention: Use semantic `NSColor`s and SwiftUI `Color(.xxx)` tokens; never bake in RGB for chrome. Keep the *image* viewport color-managed and independent of chrome appearance.
  - Phase: **P3/P5**.

### Non-Destructive Editor Design

- **NDE-1: History stack that can't survive module reorder / mask invalidation.**
  - Warning signs: Reordering modules silently breaks masks; a drawn mask references a module instance that no longer exists; "history" is a flat list with no identity so reordering corrupts it.
  - Prevention: Mirror Darktable's design: each history entry carries a stable `(op, multi_priority, multi_name, iop_order, blendop_version)`; masks are versioned *forms* referenced by id, and a reorder recomputes `iop_order` with explicit validation (`dt_ioppr_check_iop_order` equivalent). Never store masks by ordinal position.
  - Phase: **P1** (data model) — get this right before any iop.

- **NDE-2: No history hash → can't detect drift / can't write sidecars correctly.**
  - Warning signs: You can't tell whether the on-disk sidecar matches the in-memory edit; "save" writes unnecessarily or misses changes; duplicate/compare behaves wrong.
  - Prevention: Implement a history hash (Darktable: `history_hash` over modules + masks + module order, with current/auxiliary variants). Use it to decide when to write the sidecar and to detect out-of-band edits.
  - Phase: **P1**.

- **NDE-3: Param storage that doesn't survive a module refactor.**
  - Warning signs: Renaming a field or changing its semantics breaks old sidecars; there's no version per module so old params deserialize into wrong values.
  - Prevention: Every iop module has a `version` integer; bump it on any param-shape change and write an explicit migration. Sidecar stores `(module, version, params_blob)`. Never reuse a field id for a new meaning.
  - Phase: **P1/P2**.

- **NDE-4: Pipeline reordering cost is unbounded.**
  - Warning signs: Dragging a module up the stack re-runs the entire pixelpipe; no cache reuse; UI freezes on reorder.
  - Prevention: Implement a pixelpipe *cache* keyed by `(module_id, params_hash, upstream_hash)` like Darktable's `pixelpipe_cache`, with an "important" cacheline concept so the currently-viewed module's input/output stay warm. Invalidate only downstream of the change.
  - Phase: **P1**.

- **NDE-5: Before/after compare doubles memory.**
  - Warning signs: Split-view before/after holds two full-res buffers; 100MP × 2 × RGBA16F ≈ 1.6 GB just for compare.
  - Prevention: Cache the "before" at *viewport* resolution, not full-res; re-render full-res only on demand/export. Snapshot points store *params*, not pixels.
  - Phase: **P3**.

- **NDE-6: Sidecar format drift / forward-compat.**
  - Warning signs: Old sidecars fail to open after an app update; future versions of the file are unreadable by older app builds.
  - Prevention: Version the sidecar format at the document level (separate from per-module version), write a schema version, and design the reader to ignore-unknown-fields rather than reject. Document the namespace.
  - Phase: **P1/P4**.

### Session Model

- **SESS-1: FSEvents unreliability — coalescing, 4096-path limit, rename loss.**
  - Warning signs: Files moved/renamed out-of-band (Finder, ingest tool) aren't detected; events lump together so you can't tell delete+create from rename; with many sessions the watcher errors out.
  - Prevention: Do not rely solely on FSEvents. Use it as a *hint* and reconcile with a directory scan on focus/rescan. Consider `DispatchSource` (kqueue) for finer rename/attribute events on specific files. Watchexec publicly called choosing FSEvents "a mistake" — learn from that. Always handle "file vanished between event and read".
  - Phase: **P3**.

- **SESS-2: Capture/Crop/Output path edge cases — files moved out of band.**
  - Warning signs: User drags a file out of `Capture/` in Finder; sidecar becomes orphaned; Output refers to a Crop that was deleted.
  - Prevention: Treat the session folder as *mutable and untrusted*: re-derive state on access, detect orphaned sidecars (`.xmp` with no matching original), and never hard-fail on a missing sibling. Offer a "reconcile/repair session" action.
  - Phase: **P3**.

- **SESS-3: Sidecar-orphaned originals and original-orphaned sidecars.**
  - Warning signs: Deleting a `.CR3` leaves a stale `.CR3.xmp`; renaming the original doesn't rename the sidecar.
  - Prevention: Pair originals and sidecars by *basename rule* and re-scan on open. Provide cleanup tooling. When *you* rename/move, always move the sidecar atomically with the original.
  - Phase: **P3/P4**.

- **SESS-4: Multi-session state leakage.**
  - Warning signs: Switching sessions carries over selection/active edit/cache from the previous one; a global singleton pipeline gets confused about which image is "current".
  - Prevention: Make session state an explicit, owned object; tear down / swap the pixelpipe and caches on session switch. No global mutable "current image".
  - Phase: **P3**.

- **SESS-5: Concurrent access from two app instances.**
  - Warning signs: Two Lightamer windows edit the same session; sidecars get clobbered; cache files collide.
  - Prevention: Single-instance enforcement (or, if multi-window, a single shared engine with a write lock on sidecars). Detect a "session already open elsewhere" lock file and offer "open read-only" / "take over".
  - Phase: **P3**.

### RAW/Color Science

- **COLOR-1: Working space choice — ProPhoto vs linear Rec2020 vs scene-referred.**
  - Warning signs: Edits clip in saturated cyans/greens; ProPhoto's imaginary green primary breaks some ops; you assumed one size fits all.
  - Prevention: Default to **linear scene-referred Rec.2020** (Darktable's choice) — all primaries are real, well-defined. Offer linear ProPhoto as an option but document the imaginary-primary caveat. Keep the working space explicit and consistent end-to-end; never let a module assume sRGB.
  - Phase: **P1/P2**.

- **COLOR-2: Color profile mismatches causing silent clipping.**
  - Warning signs: Export looks different from the viewport; soft-proof and edit views disagree; an untagged intermediate gets interpreted as sRGB.
  - Prevention: Tag every intermediate texture/buffer with its color space; do conversions on the GPU via a color-management module (not `vImage` on CPU). Assert at pipeline boundaries that spaces match expected.
  - Phase: **P1/P2**.

- **COLOR-3: Soft-proofing correctness.**
  - Warning signs: Soft proof doesn't match actual CMYK/output gamut; out-of-gamut warning is wrong; proof applies in the wrong order.
  - Prevention: Apply soft-proof as the *last* transform before display, using proper ICC profiles and relative-colorimetric + BPC. Never bake the proof into the edit.
  - Phase: **P4**.

- **COLOR-4: HDR/EDR display calibration.**
  - Warning signs: Enabling HDR on macOS throws off your existing calibration; the image looks "dull/grey" in HDR mode; EDR extends headroom but your tone curve doesn't use it.
  - Prevention: Read `NSScreen.maximumExtendedDynamicRangeColorComponentValue` / `maximumPotentialExtendedDynamicRangeColorComponentValue`; render the viewport in EDR (`CAMetalLayer.wantsExtendedDynamicRangeContent = true`, `extendedDynamicRangeColorSpace`). Treat HDR as *headroom above 1.0*, not as a different color space. Test on both XDR and external HDR monitors — their behavior differs.
  - Phase: **P3/P4**.

- **COLOR-5: Wide-gamut HDR output correctness (AVIF/HEIF).**
  - Warning signs: Exported HDR AVIF/HEIF is clipped to SDR or has wrong tone mapping; PQ vs HLG mismatch; gain-map missing.
  - Prevention: Follow the "HDR gain map" / ISO 21496-1 approach for SDR-compatible HDR JPEG, and PQ/HLG signaling for HEIF/AVIF. Validate output with a reference viewer and known HDR test charts.
  - Phase: **P4**.

- **COLOR-6: Camera profile (DCP) absence.**
  - Warning signs: Colors don't match the camera's JPEG; no per-camera color matrix; CIRAW's built-in profile is the only option and it's not great.
  - Prevention: Bundle or import Adobe DCP profiles (or dcamprof-generated ones) and apply as a color module. This dovetails with CIRAW-3 — you need your own profile path.
  - Phase: **P2**.

### Performance at 100MP+

- **PERF-1: Loading the entire image into memory.**
  - Warning signs: Opening a 100MP file allocates 1–2 GB and climbs with each iop; app gets killed by jetsam/Memory Pressure.
  - Prevention: Stream/decode in tiles; keep only the working tile + viewport-resolution cache resident. A 100MP Bayer at 16-bit is ~400 MB *just for the sensor data*; budget every buffer.
  - Phase: **P1**.

- **PERF-2: Full-pipeline re-render on every parameter tweak.**
  - Warning signs: Every slider tick re-runs 30 modules over 100MP; interaction is a slideshow.
  - Prevention: During drag, render only the *viewport region* at *viewport resolution* through the pipeline; on release, schedule a full-res recompute. Use the pixelpipe cache (NDE-4) so unchanged modules upstream are not re-run.
  - Phase: **P1/P3**.

- **PERF-3: Thumbnail cache thrash.**
  - Warning signs: Scrolling the grid re-decodes thumbnails; LRU evicts the visible ones; first paint of a row is blank.
  - Prevention: Persistent on-disk thumbnail cache keyed by `(file_id, mtime, decode_version)`, plus an in-memory cache sized to visible rows × 2. Decode thumbnails at low priority off the main thread. Never block scrolling on a RAW decode.
  - Phase: **P3**.

- **PERF-4: Export queue blocking the UI.**
  - Warning signs: Batch export of 200 images freezes editing; export and edit fight for the GPU.
  - Prevention: Run export on a *separate* `MTLCommandQueue` with lower priority, or a separate device if available; cap concurrent exports; report progress without touching the edit pipeline.
  - Phase: **P4**.

- **PERF-5: Color conversion on CPU not GPU.**
  - Warning signs: Profile conversions run on `vImage`/Accelerate and dominate time; the GPU idles while CPU chews.
  - Prevention: Move all color transforms (working→display, working→output profile) into Metal shaders or CIColorMatrix-equivalent kernels. Use the GPU for resize/resample too.
  - Phase: **P2**.

### Interoperability (Darktable/LUT)

- **INTEROP-1: Darktable `.xmp` sidecar round-trip fidelity is unachievable for iop params.**
  - Warning signs: You promise "Darktable-compatible sidecars" but Lightroom/other tools ignore Darktable's non-standard namespaces; even re-importing into Darktable can drop params across versions.
  - Prevention: Scope the goal: **import-tolerant** (read Darktable sidecars and reconstruct an equivalent history, best-effort) — *not* byte-identical round-trip. Store your own params in a versioned namespace. Document explicitly which Darktable modules map 1:1, which are lossy, and which are unsupported. Set user expectations in the UI.
  - Phase: **P0** (scope) + **P4** (impl).

- **INTEROP-2: `.cube` LUT format edge cases — 1D vs 3D, shaper, indexing, domain.**
  - Warning signs: Colors come out swapped/channels flipped; HDR LUTs clamp; linear data bands through a 3D LUT with no shaper; parser rejects valid files.
  - Prevention: Per the Adobe spec, a `.cube` holds **either** a 1D **or** a 3D LUT, never both; 3D data is R-fastest (index ordering is the #1 bug). Honor `DOMAIN_MIN`/`DOMAIN_MAX` for float/HDR. Use **tetrahedral** interpolation (Darktable default) over trilinear for accuracy. Apply a shaper (linear→log) before 3D LUTs on scene-linear data to avoid banding. Validate row count == `LUT_3D_SIZE³`. (Darktable `lut3d.c` defaults to tetrahedral and supports `application color space` selection — mirror that.)
  - Phase: **P2/P4**.

- **INTEROP-3: LUT color-space assumption baked in.**
  - Warning signs: A LUT authored for sRGB is applied in Rec2020, producing wrong colors; no "application color space" selector.
  - Prevention: Always carry an explicit application color space for each LUT (Darktable exposes this in the LUT 3D module); convert into it before the LUT and out after.
  - Phase: **P2**.

- **INTEROP-4: Preset (`.dtstyle`) format drift.**
  - Warning signs: A Darktable preset import breaks across Darktable versions; module names/params renamed.
  - Prevention: Version the preset importer per Darktable version; map by module *op name* + version, with a fallback table for renames. Treat presets as lossy imports.
  - Phase: **P4**.

- **INTEROP-5: Hald CLUT / gmz / other LUT container formats.**
  - Warning signs: Users bring `.hald.png`, G'MIC `.gmz`, or Resolve `.cube` variants.
  - Prevention: Decide a v1 scope: `.cube` (3D) only, document the rest as future. If supporting gmz, note Darktable delegates to G'MIC (`lut3dgmic.cpp`) — you'd need a G'MIC dependency or a reimplementation.
  - Phase: **P0** (scope).

### Solo-Developer / Open-Source

- **SOLO-1: Scope creep from "parity with Darktable" (100+ modules).**
  - Warning signs: Roadmap never converges; each module is "just one more"; v1 keeps slipping; RapidRAW/RethinkRAW show how lean scopes ship while kitchen-sinks stall.
  - Prevention: Define a **v1 working-set** of modules that close the workflow loop (exposure, white-balance, demosaic, tone curve, color calibration, filmic/curve, sharpen, denoise, lens correction, crop, watermark/yiyin). Treat the rest as post-1.0. Publicly publish the module priority list so "parity" is bounded.
  - Phase: **P0** (scope decision).

- **SOLO-2: Unmaintainable algorithm porting without a test harness.**
  - Warning signs: Porting Darktable's C to Metal by hand with no way to verify equivalence; bugs appear months later with no reproduction.
  - Prevention: Before porting *any* algorithm, stand up a **golden-image harness**: run Darktable's reference output for a fixed set of test images + param vectors, and diff your Metal output per-pixel (with tolerance) and perceptually. No module merges without passing its golden test.
  - Phase: **P1** (harness first).

- **SOLO-3: No golden-image testing for color correctness.**
  - Warning signs: Color regressions ship unnoticed; "looks fine on my monitor" is the only QA.
  - Prevention: Curate a small set of torture images (deep shadows, saturated LED, X-Trans, 100MP GFX, HDR stack). Render through the full pipeline at known params; store references; fail CI on delta > threshold. Add per-OS-version references (CIRAW-2).
  - Phase: **P1/P5**.

- **SOLO-4: Dependency on undocumented / private Apple APIs.**
  - Warning signs: Reaching for private CIRAW keys or SPI; app breaks on the next OS; App Store-style review risk even though you're not on the store.
  - Prevention: Stay on documented `CIRAWFilter` keys only; if you must probe, gate behind a runtime availability check and degrade gracefully. Keep a list of every "edge of documented" API you use.
  - Phase: **All** — review at each OS release.

- **SOLO-5: Bus-factor / contribution friction.**
  - Warning signs: Only the founder understands the pixelpipe; no architecture doc; PRs stall.
  - Prevention: Write an ARCHITECTURE doc (pixelpipe DAG, cache, history model) as part of P1. Keep module ports faithful to Darktable's structure so contributors can map concepts. CI from day one.
  - Phase: **P1/P5**.

### Distribution

- **DIST-1: Notarization — unsigned nested libraries / frameworks.**
  - Warning signs: Notarytool fails on a bundled dylib/framework; Gatekeeper blocks at runtime even though notarization "passed" with warnings.
  - Prevention: Sign *every* embedded binary/framework/dylib with your Developer ID before notarizing; treat notarytool warnings as errors (Gatekeeper enforces what notarization only warns). Script the full deep-sign + staple in CI.
  - Phase: **P5**.

- **DIST-2: Gatekeeper translocation breaks relative paths.**
  - Warning signs: Quarantined app runs from `/private/var/folders/...` (randomized read-only path), so relative resource/asset paths break; users see "missing LUT" or "missing profile".
  - Prevention: Resolve all resource paths from the bundle (`Bundle.main.resourceURL`) and use proper `@rpath`/`@loader_path` for embedded libraries; never assume CWD. Test the *quarantined* build, not just a clean copy.
  - Phase: **P5**.

- **DIST-3: App sandbox incompatibility (already chose non-sandbox — verify consequences).**
  - Warning signs: Forgetting why sandbox was rejected; later adding a feature (Spotlight/Quick Look extension) that *requires* App Sandbox / App Group, creating a contradiction.
  - Prevention: Document the non-sandbox decision and its tradeoffs. Spotlight *importers* and Quick Look *extensions* are separate processes with their own entitlements — keep them decoupled from the main app so the main app stays non-sandboxed. Do not introduce security-scoped bookmarks assumptions.
  - Phase: **P0** (decision) + **P5** (verify extensions).

- **DIST-4: Spotlight importer reindexing cost.**
  - Warning signs: Installing/launching triggers a huge Spotlight reindex of the user's photo library; CPU/disk spike; user complaints.
  - Prevention: Make the Spotlight importer opt-in or scoped to session folders; only index metadata you actually provide. Test on a large library. Avoid re-indexing on every app version bump by keying on stable identifiers.
  - Phase: **P5**.

- **DIST-5: Unsigned/hardened-runtime tension with Metal/JIT.**
  - Warning signs: Hardened Runtime + library validation blocks a Metal shader path or a bundled lib; "disable library validation" feels like the easy out but weakens security.
  - Prevention: Enable Hardened Runtime; only disable library validation if truly needed and document why. Ensure all third-party (e.g., a potential libraw) is statically linked or properly signed. Verify on a clean, quarantined install.
  - Phase: **P5**.

---

## Phase Risk Mapping

| Phase theme | Highest-risk pitfalls |
|---|---|
| **P0 Research/Spike** | CIRAW-1, CIRAW-2, CIRAW-3 (decoder boundary, min-OS, camera coverage); METAL-3 (hardware floor); INTEROP-1, INTEROP-5, SOLO-1 (scope the interop & parity promises); DIST-3 (sandbox decision) |
| **P1 RAW+Metal foundation** | CIRAW-4, CIRAW-5 (CIImage chain, color mgmt); METAL-1, METAL-2, METAL-4, METAL-5, METAL-7 (tile, precision, storage, cold-start, threadgroup); NDE-1..NDE-4, NDE-6 (history/order/hash/cache/version — the data model); COLOR-1, COLOR-2; PERF-1, PERF-2; SOLO-2, SOLO-3, SOLO-5 (harness + arch doc) |
| **P2 iop modules** | CIRAW-3 (lens module); METAL-6, METAL-7 (MPS vs custom); NDE-3 (module versioning); COLOR-3, COLOR-6 (soft proof, DCP); PERF-5 (GPU color); INTEROP-2, INTEROP-3 (.cube, color space) |
| **P3 Session/UI/Perf** | METAL-8, METAL-9 (drag storms, drawable); UI-1..UI-4 (SwiftUI re-render, gestures, dark mode); NDE-5 (compare memory); SESS-1..SESS-5 (watcher, out-of-band, multi-session); PERF-2, PERF-3 (interactive, thumbnails); COLOR-4 (EDR) |
| **P4 Interop/Export** | NDE-6 (sidecar drift); INTEROP-1, INTEROP-2, INTEROP-4 (Darktable XMP, LUT, presets); COLOR-3, COLOR-5 (soft proof, HDR export); PERF-4 (export queue) |
| **P5 Polish/Distribution** | CIRAW-2 (per-OS CI); UI-4; SOLO-4, SOLO-5 (API hygiene, docs); DIST-1..DIST-5 (notarization, translocation, sandbox, Spotlight, hardened runtime) |

---

## Validation / Testing Strategy Recommendations

1. **Golden-image color harness (highest priority).** Curate torture inputs: deep-shadow Bayer, saturated-LED scene, Fuji X-Trans RAF, 100MP GFX, an HDR stack source, a CR3 and a NEF. For each, capture Darktable reference output at pinned params for the modules you port. CI diff (per-pixel tolerance + perceptual) your Metal output. Re-baseline per macOS version (CIRAW-2). This single thing de-risks more pitfalls than any other (SOLO-2, SOLO-3, METAL-2, COLOR-1/2).

2. **Performance budgets, codified.** Document and assert: first-paint of 100MP < N ms; slider-drag frame time < 16 ms at viewport res; full-res recompute < N s on a baseline machine (e.g., M1 Pro). CI warns on regressions > 10%. Covers PERF-1..PERF-5.

3. **Sidecar round-trip corpus.** A set of real Darktable `.xmp` sidecars (one per supported module mix) that the importer must load without data loss beyond the documented mapping. Covers INTEROP-1, NDE-3, NDE-6.

4. **LUT conformance suite.** Known `.cube` files (1D, 3D, with DOMAIN_MIN/MAX, HDR) validated against reference tetrahedral/trilinear output. Covers INTEROP-2/3.

5. **Session resilience tests.** Out-of-band delete/rename/move of originals and sidecars; two-instance open; FSEvents coalescing simulation. Covers SESS-1..SESS-5.

6. **Notarization/quarantine drill.** A CI job that deep-signs, notarizes, staples, then launches the *quarantined* build and exercises resource loading. Covers DIST-1, DIST-2, DIST-5.

7. **EDR/HDR display tests.** At least one XDR-class and one external-HDR test ensuring tone mapping and headroom are correct. Covers COLOR-4, COLOR-5.

## Sources

- CIRAW / Core Image: [CIRAWFilter docs](https://developer.apple.com/documentation/coreimage/cirawfilter); [WWDC26 Enhance RAW image processing with Core Image](https://www.youtube.com/watch?v=DaFkjE2EO6A); [Apple Support — RAW formats supported (iOS 18)](https://support.apple.com/en-us/120534); [Core Image: The Basics (Jacob Bartlett)](https://blog.jacobstechtavern.com/p/core-image-the-basics); [CoreImage memory build up (Apple Dev Forums)](https://origin-devforums.apple.com/forums/thread/808418).
- Metal: [Advanced Metal Shader Optimization WWDC16 #606](https://devstreaming-cdn.apple.com/videos/wwdc/2016/606oluchfgwakjbymy8/606/606_advanced_metal_shader_optimization.pdf?dl=1); [Performance Best Practices for Metal Shaders](https://developer.apple.com/videos/play/tech-talks/111373/); [WWDC23 Optimize GPU renderers with Metal](https://www.youtube.com/watch?v=yCvSvtPPVlI); [Function specialization](https://developer.apple.com/documentation/metal/using-function-specialization-to-build-pipeline-variants); [Metal 4 compilation API](https://developer.apple.com/documentation/metal/using-the-metal-4-compilation-api); [Setting Resource Storage Modes](https://developer.apple.com/documentation/metal/setting-resource-storage-modes); [MTLStorageMode.shared](https://developer.apple.com/documentation/metal/mtlstoragemode/shared); [Tailor apps for Apple GPUs / TBDR](https://developer.apple.com/documentation/metal/tailor-your-apps-for-apple-gpus-and-tile-based-deferred-rendering); [Raster Order Groups (Metal 2 / A11)](https://developer.apple.com/br/videos/play/tech-talks/605/); [Creating a custom Metal view](https://developer.apple.com/documentation/metal/creating-a-custom-metal-view); [Display EDR content with Core Image, Metal, and SwiftUI (WWDC22)](https://developer.apple.com/videos/play/wwdc2022/10114/).
- SwiftUI+Metal: [Using MTKView in SwiftUI (r/SwiftUI)](https://www.reddit.com/r/SwiftUI/comments/oq6wb6/using_mtkview_in_swiftui/).
- FSEvents: [Watchexec — Mac FSEvents limitations](https://watchexec.github.io/docs/macos-fsevents.html); [fsnotify/fsevents (4096 path limit)](https://github.com/fsnotify/fsevents); [kqueue vs FSEvents (HN)](https://news.ycombinator.com/item?id=47508710); [Apple File System Events](https://developer.apple.com/documentation/coreservices/file_system_events).
- Color science: [PIXLS — "linear Rec. 2020 RGB" WHY!](https://discuss.pixls.us/t/linear-rec-2020-rgb-why/50611); [Darktable #13141 Rec2020 vs ProPhoto export](https://github.com/darktable-org/darktable/issues/13141); [Scene-referred workflow (Ansel)](https://ansel.photos/en/workflows/scene-referred/); [Display-referred vs Scene-referred (Nine Degrees Below)](https://ninedegreesbelow.com/photography/display-referred-scene-referred.html).
- LUT: [parse-cube-lut (reference parser)](https://github.com/thibauts/parse-cube-lut); [ACESCentral — 1D vs 3D in .cube](https://community.acescentral.com/t/using-aces-shaper-spaces-in-ocio-bakelut/589); [Tetrahedral vs Trilinear](https://www.alestemple.net/blog/tetrahedral-vs-trilinear-lut-interpolation.html); Darktable source `src/iop/lut3d.c` and `src/iop/lut3dgmic.cpp` (tetrahedral default, application color space, G'MIC delegation).
- Non-destructive design: Darktable source `src/common/history.c` (`iop_order`, `blendop_version`, `multi_priority`, mask-form versioning, `dt_history_duplicate`); `src/common/history.h` (history hash); `src/develop/pixelpipe_cache.c` (cacheline, "important" lines, invalidate vs flush); [Darktable History Stack manual](https://docs.darktable.org/user/manual/development/en/module-reference/utility-modules/darkroom/history-stack/); [Module Order manual](https://docs.darktable.org/usermanual/development/en/module-reference/utility-modules/darkroom/module-order/); [History stack masking glitch (r/DarkTable)](https://www.reddit.com/r/DarkTable/comments/1p50my0/history_stack_masking_glitch/).
- Demosaic: [Darktable demosaic manual](https://docs.darktable.org/usermanual/4.2/en/module-reference/processing-modules/demosaic/); Darktable `src/iop/demosaic.c`.
- Distribution: [Notarizing macOS software (Apple)](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution); [GateKeeper — Not a Bypass](https://theevilbit.github.io/posts/gatekeeper_not_a_bypass/); [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox); [CVE-2025-31191 security-scoped bookmark sandbox escape (Microsoft)](https://www.microsoft.com/en-us/security/blog/2025/05/01/analyzing-cve-2025-31191-a-macos-security-scoped-bookmarks-based-sandbox-escape/).
- HDR/EDR: [Apple EDR on non-HDR displays (HN)](https://news.ycombinator.com/item?id=25315180); [Greg Benz Photography — HDR](https://gregbenzphotography.com/hdr/); [BetterDisplay HDR discussion](https://github.com/waydabber/BetterDisplay/discussions/2706).
- Solo-dev / scope: [RapidRAW intro (PIXLS)](https://discuss.pixls.us/t/introduction-rapidraw-a-gpu-accelerated-open-source-raw-editor/53585); [RethinkRAW](https://github.com/ncruces/rethinkraw); [Five open-source photography tools](https://marcrphoto.wordpress.com/2026/05/08/five-open-source-photography-tools-five-different-philosophies-from-control-to-speed/).

# LightamerCore — API Contract

> D-03c module contract index. The compiler enforces this boundary
> (Swift access control + the Tuist target DAG); this file is the
> human-readable index code review checks against. Mirrors RESEARCH §9b
> and the `ModuleBoundaryTests` executable mirror.
>
> **Code-review enforcement:** when a PR adds a `public` type here, the
> reviewer checks (a) is it listed in this file? (b) does it genuinely
> need to be cross-module, or could it stay `internal`? Adding `public`
> is a contract decision; removing it is a breaking change.

## Access-level strategy (RESEARCH §9a)

| Level | Meaning | Example |
|---|---|---|
| `public` | Cross-module API surface — stable contract; changes break IOP/app/tests at compile time | `RAWDecoder`, `MetalContext`, `protocol IOPModule`, `LayerStack` |
| `internal` (default) | Implementation detail — refactor freely, zero blast radius outside Core | `PSOKey`, `CIContextPool`, `PixelPipe` |
| `private`/`fileprivate` | Single-type/file detail | `psoCache` internals, EXIF parsing helpers |

## Public surface (cross-module, stable)

### Decode (`Sources/Decode/`)
- `actor RAWDecoder` — entry: `func decode(_ url: URL) async throws -> DecodedImage`
  (unified RAW + raster entry, D-24; RAW 9 opt-in + silent v8 fallback, D-22;
  cancellable, D-34; typed `AppError` only, D-25)
- `struct DecodedImage` — `ciImage`, `rawTech`, `capture`, `segmentationSkyMatte`,
  `decoderVersionUsed`; nested `enum DecoderVersion: String` (`v8` / `v9`)
- `struct RAWTechnicalParams` — D-23b (blackLevel / whiteLevel / baselineExposure /
  neutralChromaticity / NR fields); `Codable` (sidecar-ready)
- `struct CaptureMetadata` — D-23a (camera / lens / focal / aperture / shutter /
  ISO / captureTime / GPS / orientation / dimensions / dpi); nested
  `struct GPSInfo`; `Codable`

### Metal (`Sources/Metal/`)
- `actor MetalContext` — `device`, `commandQueue` (nonisolated let);
  `registerDefaultLibrary(in:)`; high-layer dispatch `dispatch2D(...)` /
  `dispatch2DTexture(...)` (nonisolated, D-19); low layer
  `makeEncoder(functionName:constants:)` → `ComputeEncoderSession`
  (`commandBuffer`, `encoder`, `pipelineState`); function-constants helpers
  `makeConstants(_:at:type:)` / `setConstant(_:at:type:into:)` (D-17);
  CIImage bridge facade `renderToTexture(_:) -> MTLTexture`
  (float32 linear-Rec2020, FOUND-02) + the scale-at-entry variant
  `renderToTexture(_ image:longEdge:)` (02-03: ONE-pass downscale to the
  target long edge — the D-C3 input-plane builder; signposted
  `render-scaled`, 02-01 spike Test C cited at the pool)
- `enum MetalError: LocalizedError` — `deviceUnavailable`, `functionNotFound`,
  `psoCreationFailed`, `bufferAllocationFailed`
- Decode-leg status (Plan 02-01 spike): `CIContext.render(_:toMTLTexture:)`
  is a silent no-op on the dev host even after warm-up — bitmap+replace is
  the primary AND fallback decode leg (`.work/02-01/spike-render-leg.md`)

### Pipe (`Sources/Pipe/`)
- `protocol IOPModule` — `associatedtype Params: Codable & Hashable`;
  statics `opName` / `iopOrder` / `flags` / `defaultColorspace`;
  `reloadDefaults`, `commitParams`, `modifyROIOut`, `modifyROIIn`,
  `process(input: any MTLTexture, output: any MTLTexture, roiIn: ROI, roiOut: ROI, piece: inout IOPiece, metal: MetalContext)` —
  **texture in/out** (02-02 checkpoint lock #1: textures are the pipe's
  currency; `MTLBuffer` only for `IOPiece.data` uniforms)
- `struct IOPFlags: OptionSet` — `supportsBlending`, `allowTiling`,
  `oneInstance`, `fence`, `writeDetails`, `allowFastPipe` (bit positions
  stable forever once sidecars ship)
- `enum IOPColorspace` — `raw`, `rawPrepared`, `RGB`, `Lab`
- `struct IOPiece` — `paramsHash: UInt64` (**StableHash FNV-1a over the
  JSON-encoded params — the only legal generator**, D-H4), `dscIn`,
  `dscOut`, `data` (uniforms `MTLBuffer?`)
- `struct IOPBufferDesc` — `width`, `height`, `channels`

### Layers — D-03a skeleton (`Sources/Layers/`)
- `protocol Layer: Sendable, Identifiable` — `id`, `name`, `isVisible`,
  `opacity`, `blendMode`, `enabled`, `kind` (no `mask`/`iopChain` until Phase 6)
- `struct LayerStack` — `baseLayer`, `adjustmentLayers`,
  `init(baseLayer: any Layer)`
- `enum LayerKind` — `background`, `adjustment`
- `enum BlendMode: Int, Codable` — Darktable blend.h raw values; **raw
  values FROZEN** (sidecar stability, LAYER-07): `normal = 0x01` …
  `difference = 0x17`
- `final class BackgroundLayer: Layer` — the always-present base layer

### Foundation (`Sources/Foundation/`)
- `enum V50Order` — `entries` (93 `(opName, order)` pairs, verbatim port of
  Darktable `iop_order.c:298-415`, rawprepare 1.0 → gamma 78.0),
  `order(for:) -> Float?`
- `struct ROI` — `x`, `y`, `width`, `height`, `scale`
- `enum AppError: LocalizedError` — D-25 unified typed error;
  `init(_ error: Error)` bridge (`CancellationError` → `.cancelled`,
  `MetalError` → tiered case, else `.decodeFailed`); shared `logger`;
  `.notImplemented(String)` reserved-seam placeholder (02-03: EXPORT →
  "Phase 11"; NEVER a `fatalError`)
- `enum WorkingSpace` — FOUND-02 locks: `colorSpace` (linear Rec2020),
  `pixelFormat` (`.rgba32Float`), `bytesPerPixel` (16)
- `enum StableHash` — stable 64-bit FNV-1a (`fnvOffsetBasis`,
  `combine(_:bytes:)`, `hash(_:)` over DataProtocol/StringProtocol UTF-8).
  The ONLY hash for cache keys (02-02), history hashes (02-05), and sidecar
  drift detection (02-06); Swift `Hasher` (per-process seed) is banned
  across persistence boundaries
- `enum ParamsCoding` (02-04) — `encode(_ params: some Encodable) -> Data`,
  the CANONICAL params encoder with `.sortedKeys` (MANDATORY: Foundation's
  keyed emission order is nondeterministic ACROSS CALLS within one process
  — host-proven, LESSONS L013 — and paramsHash hashes these bytes). All
  `commitParams` implementations MUST route through it; decoding stays
  plain `JSONDecoder` (order-agnostic)
- `enum DisplayProfile` (02-04, `@unchecked Sendable, Equatable`) — the
  resolved display profile (D-COL2): `displayP3` / `sRGB` (Metal fast-path
  families) / `colorSyncFallback(CGColorSpace)`. `resolve(_ NSColorSpace?)`
  matching table (CGColorSpace registered names → NSColorSpace equality →
  ICC-data equality → fallback); `current()` (NSScreen.main);
  `stableID: UInt64` (StableHash; the terminal-segment invalidation atom —
  fallback profiles hash their ICC bytes); `label` (log text);
  `linearCGColorSpace` / `displayCGColorSpace` (the linear workalike for
  the ColorSync leg is extendedLinearSRGB — documented approximation;
  exact unknown-profile primaries land with Phase 13 COLOR-03)

### Render bridge (`Sources/Pipe/PixelPipe.swift`)
- `enum RenderPipeline` — `static func render(image:layerStack:metal:) async
  throws -> MTLTexture`. **This is the app's ONLY render entry point.**

### Pipe cache & pipe machinery (02-02/02-03, `Sources/Pipe/`)
- `enum PipeResolution: String, Codable, Sendable, CaseIterable`
  (`PipeResolution.swift`, moved out of `PipeCacheKey.swift` in 02-03) —
  `preview` / `thumbnail` / `full` / `export`; computed policy properties
  `cachesIntermediatePlanes` (preview+thumbnail true; full+export false —
  spike-b: 3×100MP planes ≈ 4.7GB busts the budget), `isLazy`
  (thumbnail), and `defaultLongEdge` (02-03: thumbnail 360, others nil —
  the four-pipe lifecycle table lives on the type)
- `enum PreviewBucket` (`PreviewBucket.swift`, 02-03) — the D-C3
  quantization: `cap` 2560, `ladder` [2560, 2200, 1840, 1480, 1120, 760,
  360], pure `longEdge(forDrawable:pixelScale:)` (POINTS in, snap-DOWN,
  below-ladder/degenerate → 360 floor; 5K/6K soft-display note in header)
- `actor PipeCache` — byte-budget LRU plane cache (D-C1):
  `defaultBudget` 3GB / `evictTarget` 2GB hysteresis (effective floor
  scales with the constructor budget); `init(byteBudget:)`; `totalBytes`;
  `stats: CacheStats` (cumulative `hits`/`misses` — SC#2 counters);
  `invalidate(imageID:)` (02-03 load-entry anchor); `invalidateAll()`.
  **Public** (02-02 executor resolution): `RenderPipeline.process` injects
  a shared cache — a public parameter cannot expose an internal type
- `protocol ModuleBoxing: AnyObject, Sendable` — the type-erased pipe
  citizen: `instanceID/opName/multiPriority/multiName/iopOrder/enabled/
  paramsData/paramsHash`, `makeRunPiece()`, `processErased(...)`,
  `modifyROIOutErased/modifyROIInErased` (04-01 ROI negotiation seam),
  `tileHaloErased/tileWorkingSetBytesPerPixelErased` (03-05 tile seam)
- `final class ModuleBox<M: IOPModule>: ModuleBoxing` — wraps one module
  instance + its committed piece; `setParams(_:)` = the slider-drag
  mutation (re-encode → re-hash via StableHash → re-commit)
- `enum RenderPipeline.process(image:instances:imageID:resolution:cache:
  metal:longEdge:maxTileWorkingBytes:roiHint:) async throws -> (any MTLTexture, PipeRunStats)` — the
  REAL pipe entry (02-03 coordinator / 02-04 golden harness consumer);
  `struct PipeRunStats` — `hits` / `misses` / `planesRendered` (per-run
  delta). `imageID` (stable image UUID) parameter added beyond the plan's
  listed signature: cache keys need it and tests pass one across runs.
  **02-03: `longEdge` is LIVE** — scale-at-entry input plane (PREVIEW gets
  the D-C3 bucket; nil resolves to the resolution default or full extent).
  **04-01: `roiHint: ROI? = nil`** — test/probe-only sub-window entry
  (nil = full frame; clamped to the entry ROI inside `run`).
  `.export` throws `AppError.notImplemented("Phase 11")`
- `RenderPipeline.render(image:layerStack:metal:)` — KEPT: the Phase 1
  no-op display path (empty instances)
- `struct ROI` — `x/y/width/height/scale` + `clamped(to:)`/`aabb(of:)`
  (04-01 internal negotiation helpers); `struct IOPiece` gains
  `processedROIIn/Out` stamps (dt `processed_roi` mirror) + per-level
  `dscIn` (dt `buf_in`); `PixelPipe.bufInROI/levelROI/frameROI`
  (forward geometry + clamp bound, dt `get_dimensions` mirror)

### Terminal trio & module registry (02-04, `Sources/Pipe/Terminal/` + `Sources/Pipe/`)

> Terminal modules live in CORE (pipeline infrastructure — the pipe and the
> golden harness run with ZERO LightamerIOP dependency; research Open
> Question #2 resolution). Kernels in Core's own `default.metallib`
> (`TerminalKernels.metal`), resolved automatically via the
> `Bundle(for: MetalContextMarker.self)` walk.

- `final class ColorInModule: IOPModule` — `opName "colorin"`, `iopOrder
  28.0`; IDENTITY (copy via `terminal_copy`) — the pipeline input is
  CIRAW-developed imagery in linear Rec2020, NOT camera-RGB (architecture
  note in the file header; Phase 3 scene-referred iops calibrate golden
  tolerances to this). `Params.inputProfile: String?` = COLOR-04/DCP
  reservation (Phase 13+; nil = trust CIRAW)
- `final class ColorOutModule: IOPModule` — `opName "colorout"`,
  `iopOrder 70.0`; linear Rec2020 → linear display gamut (gamut matrix
  ONLY — TRC is gamma's job, D-COL4). Dual path: `colorout_matrix` kernel
  with function-constant `isP3` over two compile-time constant matrices
  (derivation cited in-source; generator `.work/02-04/matrix-derive.swift`)
  + ColorSync precise leg via `MetalContext.convertToLinearSpace` (internal)
  then `terminal_copy`. `Params.outputProfile` (.display/.sRGB/.displayP3)
  + `intent` = D-COL3 reservation (Phase 13 printer/soft-proof profiles).
  `displayProfileOverride: DisplayProfile?` — coordinator-injected live
  display; `commitParams` folds the resolved `DisplayProfile.stableID`
  into the piece hash (terminal-segment invalidation: display change ⇒
  keys ≥ colorout flip, upstream planes survive)
- `final class GammaModule: IOPModule` — `opName "gamma"`, `iopOrder 78.0`
  (the pipe TAIL); exact sRGB segmented TRC ENCODE
  (`c ≤ 0.04045 ? c/12.92 : 1.055·c^(1/2.4) − 0.055`, float math L006),
  clamp to [0,1] (THE only clamp in the pipe, D-COL4), writes
  `.bgra8Unorm` (`GammaModule.outputPixelFormat`; the EditorMTKView blit
  passthrough + CAMetalLayer colorspace complete the handoff)
- `enum TerminalKernels` — Core kernel names: `terminal_copy`,
  `colorout_matrix`, `gamma_encode`
- `actor ModuleRegistry` (02-04-01) — `opName → @Sendable (UUID) ->
  any ModuleBoxing` factory registry. `register(opName:factory:)`
  (idempotent last-wins + debug log); `makeBox(opName:instanceID:) -> nil`
  for unknown ops (02-06 degrade path); `makeDefaultChain()` = terminal
  trio v50-sorted; `static makeDefault()`. Self-registers the trio in
  `init()` (direct storage mutation — actor inits cannot hop). Phase 3+
  registers via `LightamerIOPRegistry.populate(_:)`
- `ModuleBox` additions (02-04): `init(module:instanceID:...)` — the
  identity-RESTORING initializer (sidecar/registry UUID injection); and
  `setParams` now ADOPTS the module-committed `committedPiece.paramsHash`
  (identity for standard modules; the colorout stableID fold for the
  terminal — without adoption the fold is invisible to the cache chain)

### History stack, identity & tiling (02-05, `Sources/Pipe/History/` + `Sources/Pipe/Tiling/`)
- `struct ModuleInstance: Codable, Sendable, Equatable, Hashable` — the
  persisted identity+params record (NDE-1: `(opName, multiPriority)` is
  the dedup tuple, UUID `id` the reference anchor, `iopOrder` the v50
  position). FROZEN CodingKeys `{id, opName, multiPriority, multiName,
  iopOrder, version, enabled, paramsData, paramsHash}` — the 02-06
  sidecar `instances[]` schema; renames after 02-06 are migrations.
  Typed `init(id:module:multiPriority:multiName:params:version:enabled:)`
  (canonical `ParamsCoding` encode + `StableHash`), `params(of:) throws`
  / `setParams(_:as:) throws` (typed `AppError` failures)
- `struct HistoryStack: Codable, Sendable, Equatable` + nested
  `HistoryItem: Identifiable` — HIST-01/02 value core. `commit(_:label:
  layerScope:)` (truncate redo tail + append — D-H1 drag-end lands
  here), `undo()/redo()/jump(to:)` (clamping; `position -1` = pristine,
  Darktable `history_end`), `currentValue`, `effectiveInstances()`
  (the `history.c:1600-1607` translation: newest-first first-occurrence
  per `(opName, multiPriority)`, v50-sorted with the
  `(iopOrder, multiPriority, opName)` stable tiebreak; disabled
  instances included). `HistoryItem` INLINES the full `ModuleInstance`
  snapshot (checkpoint lock #5) and reserves `layerScope: String?` for
  Phase 6 (D-H2); the stack is UNCAPPED (D-H2). Frozen CodingKeys
  `{items, position}` + `{id, snapshot, label, timestamp, layerScope}`
- `enum HistoryHash` — HIST-04/D-H4: `hash(instances:decodeParamsHash:)`
  / `hash(stack:decodeParamsHash:)` (enabled-only, caller-ordered v50
  chain: `opName` UTF-8 ‖ `multiPriority` LE ‖ `version` LE ‖
  `paramsData`; FNV-1a 64 via `StableHash` ONLY — Swift `Hasher` is
  banned in `Pipe/History/`). Plus `decodeParamsHash(for: DecodedImage)`
  — the shared decode-side atom (field-explicit `RAWTechnicalParams`
  fold, L013) consumed by `PixelPipe.run`'s position-0 cache seed AND
  the 02-06 sidecar drift check, so the two can never diverge
- `struct TilingPlan` + nested `Tile` — pure tile-grid geometry
  (`tiles(forWidth:height:maxTileBytes:bytesPerPixel:overlap:)`), D-20
  scaffolding; UNWIRED into `processRec` (Phase 5 engagement hook
  documented at `PixelPipe`); `overlap` = placeholder interior-edge
  shrink until Phase 5 defines kernel-specific halos
- `ModuleBoxing.apply(_ record: ModuleInstance)` (02-05) — the
  record→box re-materialization seam: identity-preserving
  (`record.id` must equal `instanceID`), syncs enabled/multiName,
  decodes + re-commits params; byte-identical params = committed-piece
  no-op (uniforms + cache keys untouched)
- `ModuleRegistry.makeDefaultInstances()` (02-05) — the pristine
  default-chain RECORDS (terminal trio, default params canonically
  committed); EditorState seeds its live instance set with them and the
  coordinator materializes boxes FROM the records

### Session memory budget (02-06, `Sources/Pipe/PipeCache.swift` + `Sources/Metal/`)

- `PipeCache.Keeper`→`KeepingPolicy` / `Freed` (nested types) +
  `PipeCache.enforceBudget(now:keeping:)` — the D-C1 3 GB POLICY EXECUTOR
  (pure function; the 60s timer is only a caller, OQ#7). Locked eviction
  order: other-image THUMBNAIL/EXPORT → other-image FULL → other-image
  PREVIEW (except `previousImageID`) → current-image non-PREVIEW;
  current-image PREVIEW planes are never touched. LRU-oldest first within
  a tier; stops at the hysteresis floor (`min(evictTarget, budget × 2/3)`).
  Tests inject tiny thresholds — CI never allocates 3 GB
- `MetalContext.clearCICaches()` (async) → `CIContextPool.clearCaches()`
  (`ciContext.clearCaches()`) — the D-C1 layer-2 accumulator clear
  (spike-b: CI/RawCamera internal per-camera state). PSO caches are
  deliberately NOT cleared (MB-scale; clearing costs rebuild stalls)
- **Host finding fixed en route (02-06-04):** `CIContextPool
  .convertTexture` race-read planes whose kernel writes were still
  in-flight on the app's queue (CI renders on its OWN queue) — restored
  5-dispatch renders lost the race deterministically (black output). Fix:
  an empty committed fence buffer + `waitUntilCompleted` before the CI leg
  (LESSONS L014)

### Sidecar — `.lra` persistence (02-06, `Sources/Sidecar/`)

- `struct LightamerSidecar: Codable, Sendable, Equatable` — the per-image
  persisted document (`<original FULL name>.lra`, D-S2). Schema v1 keys
  (checkpoint 02-06-01 lock, ONE-WAY): `schemaVersion`(=1)/`appVersion`/
  `imageID`(UUID)/`decoderVersionUsed`/`decodeParamsHash`/`instances`
  (02-05 `ModuleInstance` spelling verbatim)/`history`(`{items,position}`
  verbatim)/`historyHash`/`layerStack`(null; Phase 6 reservation).
  Pretty-printed + `.sortedKeys`. Members: `schemaVersionCurrent`,
  `sidecarURL(for:)` / `imageURL(for:)` (the D-S2 naming rule),
  `currentAppVersion`, `driftDetected` (HIST-04/SC#5 primitive — recompute
  vs stored anchor, seeded with the FILE's own decode hash so a decoder
  upgrade never false-positives), `degradedForUnknownOps(registry:)`
  (unknown-op degrade: keep `paramsData` verbatim + `enabled=false`;
  checkpoint lock #4 — user data is never dropped)
- `@propertyWrapper struct UInt64String: Codable, Sendable, Hashable` —
  the UInt64-as-Decimal-String JSON rule (checkpoint lock #2, ONE-WAY):
  FNV-1a 64 exceeds 2^53, so every persisted hash
  (`decodeParamsHash`/`historyHash`/`paramsHash`) serializes as a String;
  decode defensively accepts bare numbers too
- `actor SidecarStore` — per-image writer/reader (D-S3): `scheduleWrite(_)`
  (2s debounce, re-schedule resets the clock, LAST document wins),
  `flushNow()` (awaitable, idempotent), `load()` (nil = absent/corrupt →
  pristine + logged, never throws into the UI). Atomic write = same-dir
  tmp + `replaceItemAt`/rename (L009: same-volume rename or atomicity is
  lost). Injected `Clock` (default `ContinuousClock`) makes the debounce
  testable; per-image destination = `LightamerSidecar.sidecarURL(for:)`

## Internal (NOT for cross-module use — may change without notice)

- **Pipe internals (02-02/02-03):** `struct PipeCacheKey` (imageID/pipeType/
  position/upstreamHash/roi — in-memory only, synthesized Hashable is legal
  because the key never persists), `enum PipeHash` (upstream-chain combine
  helper), `PipeCache.CachedPlane` (@unchecked Sendable,
  write-once-then-readonly ownership contract), `PixelPipe.processRec` /
  `pieces` / `levelHash` / `decodeParamsHash` (the app goes through
  `RenderPipeline`). 02-03 per-resolution lifecycle: `PixelPipe.roi`
  (scale-at-entry ROI per run), `isDirty` / `runIfDirty(...)` (THUMBNAIL
  lazy fetch), `runOnce(...)` (FULL on-demand, no retention), scaled
  input-plane miss leg (`renderToTexture(_:longEdge:)` when
  `roi.scale < 1`). Test surface via `@testable import LightamerCore`
  (precedent: `RAWDecoderTests`).
- **02-04 pipe tail policy** (internal): when the TOP enabled module is
  `gamma`, the final plane is allocated `.bgra8Unorm` (4 B/px accounting)
  — cached planes at positions < gamma stay float32 linear (a display
  change re-runs only the colorout+gamma segment). FULL gets the same
  treatment (its output is display-format for 100% viewing).
- `struct TextureBox` — the pipe's `@unchecked Sendable` plane
  ownership-transfer wrap (also used by the colorout ColorSync leg).
- `MetalContext.convertToLinearSpace(_ sending any MTLTexture, target:)`
  + `CIContextPool.convertTexture(_:toLinearSpace:)` (02-04, internal —
  the colorout ColorSync leg: CIImage(mtlTexture:) tagged with the working
  space → bitmap render (RGBAf) with the per-call LINEAR target colorspace
  → replace; host finding referenced at the pool header).
- `PSOKey` (PSO cache key, D-16), `CIContextPool` (CIImage→texture bridge;
  02-03 adds the internal `renderToTexture(_:longEdge:)` scale-at-entry leg
  with the `render-scaled` signpost),
  `MetalContextMarker` (`Bundle(for:)` anchor), `MetalContext.psoCache` /
  `lruKeys` / `pipelineState(for:constants:)` / `functionNamed(_:constants:)`
- `PixelPipe` (layer-aware pipe skeleton — the app goes through
  `RenderPipeline` instead)
- `RAWDecoder.decodeRAW` / `decodeRaster` / `readCaptureMetadata` /
  `rawTechnicalParams` / `rawUTIs` / `utiForFile` / `isRAWUTI` /
  `parseEXIFDate` / the `supportedDecoderVersions` probe cache
- `MetalError.asAppError` (the internal tiered mapping — the app only ever
  sees `AppError`)
- `MTLFunctionConstantValues: @unchecked @retroactive Sendable` extension
  (`MetalSendability.swift`)

## Boundary guarantees (verified by `ModuleBoundaryTests`)

- IOP and the app reference ONLY the types above via plain `import`.
- Referencing an internal symbol (e.g. `PSOKey`) from another module fails
  to compile: `error: cannot find 'PSOKey' in scope`.
- Renaming any internal breaks nothing outside Core (RESEARCH §9d table).

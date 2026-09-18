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
  paramsData/paramsHash`, `makeRunPiece()`, `processErased(...)`
- `final class ModuleBox<M: IOPModule>: ModuleBoxing` — wraps one module
  instance + its committed piece; `setParams(_:)` = the slider-drag
  mutation (re-encode → re-hash via StableHash → re-commit)
- `enum RenderPipeline.process(image:instances:imageID:resolution:cache:
  metal:longEdge:) async throws -> (any MTLTexture, PipeRunStats)` — the
  REAL pipe entry (02-03 coordinator / 02-04 golden harness consumer);
  `struct PipeRunStats` — `hits` / `misses` / `planesRendered` (per-run
  delta). `imageID` (stable image UUID) parameter added beyond the plan's
  listed signature: cache keys need it and tests pass one across runs.
  **02-03: `longEdge` is LIVE** — scale-at-entry input plane (PREVIEW gets
  the D-C3 bucket; nil resolves to the resolution default or full extent).
  `.export` throws `AppError.notImplemented("Phase 11")`
- `RenderPipeline.render(image:layerStack:metal:)` — KEPT: the Phase 1
  no-op display path (empty instances)

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

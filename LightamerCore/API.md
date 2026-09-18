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
  (float32 linear-Rec2020, FOUND-02)
- `enum MetalError: LocalizedError` — `deviceUnavailable`, `functionNotFound`,
  `psoCreationFailed`, `bufferAllocationFailed`

### Pipe (`Sources/Pipe/`)
- `protocol IOPModule` — `associatedtype Params: Codable & Hashable`;
  statics `opName` / `iopOrder` / `flags` / `defaultColorspace`;
  `reloadDefaults`, `commitParams`, `modifyROIOut`, `modifyROIIn`, `process`
- `struct IOPFlags: OptionSet` — `supportsBlending`, `allowTiling`,
  `oneInstance`, `fence`, `writeDetails`, `allowFastPipe` (bit positions
  stable forever once sidecars ship)
- `enum IOPColorspace` — `raw`, `rawPrepared`, `RGB`, `Lab`
- `struct IOPiece` — `paramsHash`, `dscIn`, `dscOut`, `data`
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
  `MetalError` → tiered case, else `.decodeFailed`); shared `logger`
- `enum WorkingSpace` — FOUND-02 locks: `colorSpace` (linear Rec2020),
  `pixelFormat` (`.rgba32Float`), `bytesPerPixel` (16)

### Render bridge (`Sources/Pipe/PixelPipe.swift`)
- `enum RenderPipeline` — `static func render(image:layerStack:metal:) async
  throws -> MTLTexture`. **This is the app's ONLY render entry point.**

## Internal (NOT for cross-module use — may change without notice)

- `PSOKey` (PSO cache key, D-16), `CIContextPool` (CIImage→texture bridge),
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

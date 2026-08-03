# Phase 1 Research: Foundation, App Skeleton & Capability Spikes

**Researched:** 2026-08-03
**Status:** Ready for planning
**Scope:** Implementation detail for Phase 1 (FOUND-01/02/03/05/06/07, RAW-01/02/04/05/06). Project-level decisions (macOS 27 floor, CIRAW 9 boundary, Darktable pixelpipe architecture) were locked in prior research (STACK/ARCHITECTURE/PITFALLS) and are not re-litigated here.

## Summary

Phase 1 stands up a greenfield macOS 27 app from a `project.yml` (XcodeGen) with three subsystems in flight at once: (1) `RAWDecoder` wrapping `CIRAWFilter` with RAW 9 opt-in + RAW 8 fallback + ImageIO metadata, (2) `MetalContext` actor exposing a two-layer `dispatch2D`/raw-encoder dispatch with lazy memory-cached PSOs and `[[function_constant(N)]]`-driven specialization, and (3) `IOPModule` protocol + `v50_order` table ported verbatim from Darktable's `iop_order.c:298-415`, plus an `EditorMTKView` `NSViewRepresentable` that blits a decoded RAW via `MTKView`/`CAMetalLayer`. The two independent spikes (CIRAW 9 boundary, 100MP Metal perf) run on isolated spike branches with minimal verification apps because their outcomes determine v1 iop scope.

Confidence is **High** on the architectural shape (it is a faithful port of Darktable's OpenCL→Metal mapping) and **Med** on exact RAW 9 behavior on macOS 27 beta (camera list still expanding, `colorNoiseReductionAmount`/`detailAmount` are no-ops under RAW 9 per WWDC26/305). One CONTEXT decision warrants review: **D-15 (single `MTLCommandQueue`)** is correct for Phase 1 but the spec should leave a clear seam for the Phase 11 low-priority export queue, and **D-13's "no zoom/pan interaction"** means the MTKView can be a near-static blit in Phase 1 — full zoom/pan (PERF-2) is a Phase 2/3 concern.

## Implementation Approaches

### 1. XcodeGen project.yml for macOS 27 App

**Confidence: High** — XcodeGen's schema is well-documented; `.metal` files compile to the default library automatically.

**Schema skeleton** (honors D-01, D-02, D-03, D-04, D-05, D-28):

```yaml
name: Lightamer
options:
  bundleIdPrefix: com.kamasylvia
  deploymentTarget:
    macOS: "27.0"          # FOUND-01, AGENTS.md "最低部署目标 macOS 27"
  createIntermediateGroups: true
  developmentLanguage: en
  xcodeVersion: "16.3"     # adjust to the installed Xcode 26+ that ships macOS 27 SDK

settings:
  base:
    SWIFT_VERSION: "6.0"                    # D-33 Swift 6 strict concurrency
    SWIFT_STRICT_CONCURRENCY: complete      # data-race safety at compile time
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    CODE_SIGN_STYLE: Automatic
    CODE_SIGN_IDENTITY: "-"
    ENABLE_HARDENED_RUNTIME: YES
    METAL_ENABLE_DEBUGGING_INFO: YES        # Debug only — set per-config
    OTHER_SWIFT_FLAGS: "-suppress-warnings"

targets:
  Lightamer:
    type: application
    platform: macOS
    deploymentTarget: "27.0"
    sources:
      - path: Sources/Core      # RAWDecoder, MetalContext, pixelpipe skeleton
      - path: Sources/IOP       # iop .swift + .metal pairs, iop_order.swift
      - path: Sources/UI        # SwiftUI shell, EditorMTKView bridge
      - path: Sources/Session   # stub — Phase 9 fills in
      - path: Sources/Export    # stub
      - path: Sources/Yiyin     # stub
      - path: Sources/AI        # stub
      - path: Resources         # .metallib (built), String Catalog, golden samples
        type: group
      - path: App               # @main App.swift, Info.plist generation
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.kamasylvia.lightamer     # D-05 (one-way)
        INFOPLIST_KEY_NSPhotoLibraryUsageDescription: ""        # placeholder
        INFOPLIST_KEY_NSCameraUsageDescription: ""
        GENERATE_INFOPLIST_FILE: YES
        ENABLE_USER_SELECTED_FILES: read-write                 # non-sandboxed file access
        LD_RUNPATH_SEARCH_PATHS: "$(inherited) @executable_path/../Frameworks"
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: Lightamer
        CFBundleDocumentTypes:
          - CFBundleTypeName: RAW Image
            CFBundleTypeRole: Viewer
            LSItemContentTypes:
              - public.camera-raw-image
              - public.heic
              - public.jpeg
              - public.png
              - public.tiff
              - org.webmproject.webp
        UTExportedTypeDeclarations: []   # declare own UTIs later

  LightamerTests:                          # D-28
    type: bundle.unit-test
    platform: macOS
    sources: [Tests/LightamerTests]
    dependencies:
      - target: Lightamer
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.kamasylvia.lightamer.tests
        GENERATE_INFOPLIST_FILE: YES

  LightamerUITests:                        # D-28
    type: bundle.ui-testing
    platform: macOS
    sources: [Tests/LightamerUITests]
    dependencies:
      - target: Lightamer
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.kamasylvia.lightamer.uitests
        GENERATE_INFOPLIST_FILE: YES
        TEST_TARGET_NAME: Lightamer

schemes:
  Lightamer:
    build:
      targets:
        Lightamer: all
        LightamerTests: [test]
        LightamerUITests: [test]
    run:
      config: Debug
    test:
      config: Debug
      gatherCoverageData: true
    archive:
      config: Release
```

**Key schema points (verified against XcodeGen `ProjectSpec.md`):**
- `options.deploymentTarget.macOS: "27.0"` is the project-wide knob; per-target `deploymentTarget` overrides (set both — the GitHub issue #1577 reports `supportedDestinations` can override silently, so explicit `platform: macOS` + `deploymentTarget` is safest).
- `.metal` files do NOT need a custom build rule — XcodeGen routes them to the "Compile Sources" phase automatically, and Xcode's default Metal build rule emits `default.metallib` into the app bundle. Read it at runtime via `device.makeDefaultLibrary()`.
- `Resources/` should be `type: group` so its contents (String Catalog `.xcloc`, golden `.png`/`.tiff` samples, any bundled ICC profiles) land in "Copy Bundle Resources".
- **String Catalog localization** (SYS-05 zh/en): add `Resources/Localizable.xcstrings` as a source. XcodeGen picks it up as a resources-phase file. `knownRegions` auto-populates from the catalog; the `developmentLanguage: en` option sets `CFBundleDevelopmentRegion`.
- **Test targets** (D-28): `bundle.unit-test` and `bundle.ui-testing` product types give correct default settings (`TEST_HOST`, `TEST_TARGET_NAME` injected automatically). UI tests need `TEST_TARGET_NAME: Lightamer`.

**Function constants in `.metal` (D-17) — verified compatibility:**
XcodeGen does not need a special flag. Function constants are declared with `[[function_constant(N)]]` in `.metal` source and consumed via `MTLFunctionConstantValues` + `MTLComputePipelineDescriptor.functionConstants` at the Swift side. The `.metal` file compiles normally into the default library; specialization happens at PSO-creation time, not at file compile time. Confirmed by Apple's *Using function specialization to build pipeline variants* doc and MSL spec. **Confidence: High.**

**Pre-build command for asset gen (optional):** `options.postGenCommand:` can run `mint run yonaskolb/XcodeGen` itself or a shader-lint script — leave unset for Phase 1.

**Gotchas:**
- **Issue #1577**: If you also set `supportedDestinations`, Xcode 26 may reset `deploymentTarget` to the SDK default. Mitigation: set BOTH `platform: macOS` and `deploymentTarget: "27.0"` on each target; do not mix `supportedDestinations` with `platform` on the macOS-only app target.
- **`.metal` files in `Sources/IOP/`** will be compiled into `default.metallib`. Do NOT also list them under `Resources/` — double-inclusion is a build error.
- **Hardened Runtime + Metal** (DIST-5): `ENABLE_HARDENED_RUNTIME: YES` is fine for Metal compute (no JIT). Library Validation can stay on for v1 since there are no third-party dylibs. Revisit if libwebp/libavif (Phase 11) need different handling.

### 2. CIRAWFilter + RAW 9 Opt-in (macOS 27)

**Confidence: Med** — RAW 9 API surface is documented but beta behavior is still settling (camera list, no-op keys). Fallback to RAW 8 is **High** confidence.

**Instantiation pattern** (D-21, D-22, D-23, D-24):

`CIRAWFilter` is not a standalone Swift class — it's the modern spelling of `CIFilter.filterWithImageURL(_:options:)`. The Swift entry point is `CIFilter(imageURL:options:)`, which returns a `CIFilter` whose `outputImage` is the decoded `CIImage`. Properties are read/written via `CIRAWFilterOption` keys (`kCIInputDecoderVersionKey`, `kCIInputNeutralChromaticityXKey`, etc.). The header `CIRAWFilter.h` (verified from iOS SDK dump) is the canonical reference.

```swift
import CoreImage
import CoreImage.CIFilterBuiltins

public enum DecodeError: Error { case unsupportedFile, noRAWDecoder, decoderInitFailed }

public final class RAWDecoder: @unchecked Sendable {

    /// Unified entry for RAW + non-RAW (D-24). Internally branches:
    /// - RAW UTIs (CR3/NEF/ARW/RAF/RW2/ORF/DNG/IIQ/3FR/PEF/RWL/X3F) -> CIRAWFilter
    /// - Raster UTIs (JPEG/HEIC/PNG/WebP/TIFF/PSD-flat) -> CGImageSource
    public func decode(_ url: URL) async throws -> DecodedImage {
        let uti = (CGImageSourceCreateWithURL(url as CFURL, nil)
                   .flatMap { CGImageSourceGetType($0) }) ?? "public.data" as CFString
        if Self.rawUTIs.contains(uti as String) {
            return try await decodeRAW(url)
        } else {
            return try decodeRaster(url, uti: uti as String)
        }
    }

    private func decodeRAW(_ url: URL) async throws -> DecodedImage {
        // 1. Probe supported decoder versions ONCE per file (D-22).
        //    CIRAWFilter publishes supportedDecoderVersions as read-only.
        let probe = CIFilter(imageURL: url, options: nil) ?? CIFilter(imageData: Data(contentsOf: url), options: nil)

        guard let supported = probe?.value(forKey: "supportedDecoderVersions") as? [String] else {
            throw DecodeError.decoderInitFailed
        }

        // 2. RAW 9 opt-in behind #available (D-22, FOUND-07). Default = .version9 if listed.
        var options: [CIRAWFilterOption: Any] = [
            .init(rawValue: "EnableSharpening"): false,   // CIRAW is strictly the decoder (research lock)
            .init(rawValue: "EnableChromaticNoiseTracking"): false,
            .init(rawValue: "EnableVendorLensCorrection"): true,  // honor embedded opcodes
        ]
        if #available(macOS 27, *), supported.contains("9") {
            options[.init(rawValue: "decoderVersion")] = CIFilter.RawDecoders.version9
        } else {
            options[.init(rawValue: "decoderVersion")] = CIFilter.RawDecoders.version8
        }

        // 3. Build the real filter with the chosen decoder version.
        guard let filter = CIFilter(imageURL: url, options: options) else {
            throw DecodeError.decoderInitFailed
        }
        guard let ciImage = filter.outputImage else {
            throw DecodeError.decoderInitFailed
        }

        // 4. Read the three metadata classes (D-23).
        let rawTech = RAWTechnicalParams(
            blackLevel:           filter.value(forKey: "blackLevel")           as? Double ?? 0,
            whiteLevel:           filter.value(forKey: "whiteLevel")           as? Double ?? 1,
            baselineExposure:     filter.value(forKey: "baselineExposure")     as? Double ?? 0,
            neutralChromaticity:  CIVector(x: (filter.value(forKey: "neutralChromaticityX") as? Double ?? 0),
                                            y: (filter.value(forKey: "neutralChromaticityY") as? Double ?? 0)),
            noiseReductionAmount: filter.value(forKey: "noiseReductionAmount") as? Double ?? 0,
            // RAW 9 deprecates these (WWDC26/305) — read anyway for RAW 8 fallback path.
            luminanceNoiseReduction: filter.value(forKey: "luminanceNoiseReductionAmount") as? Double,
            colorNoiseReduction:     filter.value(forKey: "colorNoiseReductionAmount")     as? Double
        )
        let captureMeta = try Self.readCaptureMetadata(url: url)  // ImageIO (see §6)
        let segMatte: CIImage? = (filter.value(forKey: "semanticSegmentationSkyMatteImage") as? CIImage) // iPhone ProRAW only (L004)

        return DecodedImage(
            ciImage: ciImage,
            rawTech: rawTech,
            capture: captureMeta,
            segmentationSkyMatte: segMatte,
            decoderVersionUsed: (supported.contains("9") && #available(macOS 27, *)) ? .v9 : .v8
        )
    }

    private static let rawUTIs: Set<String> = [
        "public.canon-cr2", "public.canon-cr3",         // CR3 (RAW-01)
        "com.nikon.raw-image", "com.nikon.nrw-image",    // NEF
        "com.sony.raw-image", "com.sony.srf-image",      // ARW
        "com.fuji.raw-image",                            // RAF (X-Trans + Bayer)
        "com.panasonic.raw-image", "com.panasonic.rw2-image",
        "com.olympus.raw-image", "com.olympus.or-image",
        "com.pentax.raw-image",                          // PEF
        "com.leica.raw-image",                           // RWL/DNG
        "com.hasselblad.3fr", "com.phaseone.iiq",
        "public.adobe-dng",                              // DNG (RAW-02, incl. embedded + converted)
        "com.sigma.x3f"
    ]
}
```

**Key API facts (verified from `CIRAWFilter.h`):**
- `CIFilter(imageURL:options:)` is `NS_AVAILABLE(10_5, 10_0)` — always available. Returns `CIFilter?`.
- `kCIInputDecoderVersionKey` accepts `NSString`/`NSNumber`. The Swift spelling in modern SDKs is `CIFilter.RawDecoders.version8` / `.version9` (an enum imported from the `RawDecoders` typedef).
- `kCISupportedDecoderVersionsKey` is **read-only**; setting raises an exception. Probe it on a scratch filter, then set `decoderVersion` on the real one.
- `kCIInputNeutralChromaticityXKey`/`YKey`: `NSNumber (float)`. **No direct Kelvin slider** — convert K/tint → xy in Swift (research STACK.md boundary table).
- `kCIInputBaselineExposureKey`, `blackLevel`, `whiteLevel`: all `NSNumber (float)`.
- `kCIInputSemanticSegmentationSkyMatteKey` (macOS 11+): returns a `CIImage` **only for iPhone ProRAW embedded mattes** — silently nil for DSLR/Mirrorless RAW. (L004)
- **RAW 9 no-op keys** (WWDC26/305 verbatim): `colorNoiseReductionAmount`, `detailAmount`, `moireReductionAmount`. Effective keys under RAW 9: `exposure`, `luminanceNoiseReductionAmount`, `sharpnessAmount`, `contrastAmount`. The decoder-version-gated behavior means the RAWDecoder must NOT promise these sliders do anything under RAW 9 — the UI must hide/disable them when `decoderVersionUsed == .v9`.
- `supportedCameraModels` (`+ (NSArray<NSString*> *)supportedRawCameraModels`, macOS 10.15+): use for a "is this camera known" pre-flight, not for gating decode (Apple decodes by UTI, not model).
- **New in macOS 27** (WWDC26/305): RAW 9 supports "hundreds of models" at GA — broader than the early-beta X-T5/X-T50 subset. The spike (§8) confirms per-camera support.

**Gotchas:**
- **`CIFilter(imageURL:options:)` returns the SAME instance semantics as `CIRAWFilter`** — but Swift's static typing makes it a `CIFilter`, so all RAW-specific keys must be read via `setValue(_:forKey:)` / `value(forKey:)` (string-keyed KVC). The `CIFilter.CIRAWFilter` Swift overlay (recent SDKs) provides typed properties — check what's exposed in the macOS 27 SDK at build time and prefer the typed surface where it exists.
- **Two `CIFilter` instantiations per decode** (probe + real) doubles init cost. The probe's `supportedDecoderVersions` is a per-file property (the SAME image always reports the same list), so cache it in a `RAWDecoder` LRU keyed on file URL + mtime.
- **Draft Mode** (`kCIInputAllowDraftModeKey`) speeds decode at the cost of quality — useful for thumbnail generation (Phase 9), NOT for the editor viewport.
- **`kCIInputEnableVendorLensCorrectionKey`** defaults to `true` if the RAW contains lens opcodes (DNG OpcodeList). Leave it on for v1 — manual lens correction (IOP-GEO-03) is Phase 4.
- **Adobe DNG (RAW-02)** "just works" — Apple's DNG support is the universal fallback (STACK.md RAW Format Support). No special path needed; the UTI is `public.adobe-dng`.
- **`semanticSegmentationSkyMatteImage`** should be exposed (D-23) but documented as iPhone-ProRAW-only — the v1 sky-segmentation AI feature (AIV2-03) needs a custom Core ML model for DSLR RAW.

**⚠ DECISION REVIEW: D-22 (RAW 9 default + auto-fallback).** The pattern is feasible. One nuance: when RAW 9 silently produces different output for a camera (e.g. applies its own ML denoise the user did not ask for), the user has no in-app signal that "RAW 9 happened." Sidecars should stamp the decoder version used (per PITFALLS CIRAW-2: "version-stamp sidecars with the decoder used"). **Recommendation:** add `decoderVersionUsed` to the Phase 2 sidecar schema even though sidecars are Phase 2 — flagging here so the planner can reserve the field.

### 3. MetalContext Dispatch Framework

**Confidence: High** for the dispatch shape (1:1 port of Darktable's `dt_opencl_enqueue_kernel_2d` pattern). **Med** for PSO cache sizing under the full 91-module set (Phase 1 only has ~1 kernel, so memory is trivial here; the real test is Phase 3+).

**Two-layer dispatch API (D-19):**

```swift
import Metal

public enum MetalError: Error, LocalizedError {
    case deviceUnavailable, functionNotFound(String), psoCreationFailed(String, Error?)
    case bufferAllocationFailed(Int)
    public var errorDescription: String? { /* … */ }
}

public actor MetalContext {                 // D-33 actor-isolated
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue   // D-15 single queue for Phase 1
    private let library: MTLLibrary
    private var psoCache: [PSOKey: MTLComputePipelineState] = [:]  // D-16 lazy + memory

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw MetalError.deviceUnavailable }
        self.device = device
        guard let queue = device.makeCommandQueue() else { throw MetalError.deviceUnavailable }
        self.commandQueue = queue
        self.library = try device.makeDefaultLibrary(bundle: .main)
    }

    // ───────── High-level dispatch (D-19) ─────────
    // Used by simple iops that just want "process the whole image."
    // Mirrors dt_opencl_enqueue_kernel_2d_args (ARCHITECTURE.md OpenCL→Metal table).
    public func dispatch2D(
        functionName: String,
        input: MTLBuffer, output: MTLBuffer,
        width: Int, height: Int,
        threadgroupSize: MTLSize = MTLSizeMake(16, 16, 1),
        constants: MTLFunctionConstantValues? = nil,        // D-17 function-constants
        configure: (MTLComputeCommandEncoder) -> Void
    ) async throws {
        let pso = try await pipelineState(for: functionName, constants: constants)
        let buffer = commandQueue.makeCommandBufferWithUnretainedReferences()
        guard let encoder = buffer.makeComputeCommandEncoder() else {
            throw MetalError.psoCreationFailed(functionName, nil)
        }
        encoder.setComputePipelineState(pso)
        encoder.setBuffer(input, offset: 0, index: 0)
        encoder.setBuffer(output, offset: 0, index: 1)
        configure(encoder)   // caller binds additional args/uniforms
        let threadsPerGrid = MTLSizeMake(width, height, 1)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        buffer.commit()
        try await withCheckedThrowingContinuation { cont in
            buffer.addCompletedHandler { _ in cont.resume() }
        }
    }

    // Overload for texture-based dispatch (CIRAW CIImage → MTLTexture path)
    public func dispatch2DTexture(
        functionName: String,
        input: MTLTexture, output: MTLTexture,
        threadgroupSize: MTLSize = MTLSizeMake(8, 8, 1),
        constants: MTLFunctionConstantValues? = nil,
        configure: (MTLComputeCommandEncoder) -> Void
    ) async throws { /* analogous — setTexture instead of setBuffer */ }

    // ───────── Low-level encoder exposure (D-19) ─────────
    // Used by fine-grained iops (Phase 5 denoise, Phase 2 tiling).
    public func makeEncoder(functionName: String,
                            constants: MTLFunctionConstantValues? = nil) async throws
        -> (MTLCommandBuffer, MTLComputeCommandEncoder, MTLComputePipelineState) {
        let pso = try await pipelineState(for: functionName, constants: constants)
        let buffer = commandQueue.makeCommandBufferWithUnretainedReferences()
        let encoder = buffer.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pso)
        return (buffer, encoder, pso)
    }

    // ───────── PSO lazy cache (D-16) ─────────
    private func pipelineState(for functionName: String,
                               constants: MTLFunctionConstantValues?) async throws
        -> MTLComputePipelineState {
        let key = PSOKey(name: functionName, constantsFingerprint: constants?.fingerprint ?? "")
        if let cached = psoCache[key] { return cached }
        let fn = try await functionNamed(functionName, constants: constants)
        let pso = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<MTLComputePipelineState, Error>) in
            do {
                let descriptor = MTLComputePipelineDescriptor()
                descriptor.computeFunction = fn
                device.makeComputePipelineState(descriptor: descriptor,
                                                options: [],
                                                reflection: nil) { result in
                    switch result {
                    case .success(let pso): cont.resume(returning: pso)
                    case .failure(let err): cont.resume(throwing: MetalError.psoCreationFailed(functionName, err))
                    }
                }
            } catch { cont.resume(throwing: error) }
        }
        psoCache[key] = pso
        return pso
    }

    /// Resolves a function, applying function-constants specialization (D-17).
    private func functionNamed(_ name: String,
                               constants: MTLFunctionConstantValues?) async throws -> MTLFunction {
        let baseFn = try library.makeFunction(name: name)
        guard let constants = constants else { return baseFn! }
        // makeFunction(name:constantValues:) is the specialization entry point
        return try await library.makeFunction(name: name, constantValues: constants)
    }

    /// Convenience: build a constants object from a Swift dictionary of (index, value).
    public func makeConstants<T>(_ value: T, at index: Int, type: MTLDataType) -> MTLFunctionConstantValues {
        let cv = MTLFunctionConstantValues()
        cv.setConstantValue(UnsafeMutableRawPointer(&[value]), type: type, index: index)
        return cv
    }
}

private struct PSOKey: Hashable {
    let name: String
    let constantsFingerprint: String
}

extension MTLFunctionConstantValues {
    /// Stable hash so identical specialization values hit the PSO cache (D-16).
    var fingerprint: String { /* walk internal bytes -> sha256 hex */ "" }
}
```

**`.metal` function-constants usage (D-17):**

```metal
// Sources/IOP/PassThrough.metal — Phase 1 success criterion #2 (trivial pass-through)
#include <metal_stdlib>
using namespace metal;

// Constant declared at file scope; specialized at PSO creation.
// D-17: function-constants fold branches into PSO variants.
constant bool useSrgbGamma [[function_constant(0)]];
constant float exposureEV  [[function_constant(1)]];

kernel void pass_through(
    texture2d<float, access::read>    in     [[texture(0)]],
    texture2d<float, access::write>   out    [[texture(1)]],
    uint2 gid                                 [[thread_position_in_grid]])
{
    float4 c = in.read(gid);
    if (useSrgbGamma) { c = float4(pow(c.rgb, float3(1.0/2.2)), c.a); }
    c.rgb *= pow(2.0, exposureEV);   // trivial tone op to prove specialization
    out.write(c, gid);
}
```

Swift side then specializes with `MetalContext.makeConstants(useSrgbGamma, at: 0, type: .bool)` and the cache returns a distinct PSO per `(name, constants)` pair.

**CIImage → MTLTexture bridge (D-21 RAWDecoder output feeds MetalContext):**

```swift
// Per WWDC22/10114 and the render(_:to:commandBuffer:bounds:colorSpace:) docs:
public actor CIContextPool {
    private let ciContext: CIContext
    init(device: MTLDevice) {
        // ONE CIContext per MTLDevice (per WWDC "Optimize the Core Image pipeline").
        // workingColorSpace = linear Rec2020 (FOUND-02 lock).
        // LAB — pass an explicit CGColorSpace to avoid CIContext default surprises (PITFALLS CIRAW-5).
        let rec2020 = CGColorSpace(name: CGColorSpace.rec2020Linear)!
        self.ciContext = CIContext(mtlDevice: device, options: [
            .workingColorSpace: rec2020,
            .outputColorSpace: rec2020,
            .workingFormat: kCIFormatRGBAh,        // half-float working; render to float32 separately
            .cacheIntermediates: false,            // CIRAW-4: lazy chain blowup
        ])
    }

    func renderToTexture(_ image: CIImage, device: MTLDevice) async throws -> MTLTexture {
        let extent = image.extent
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,             // FOUND-02 float32 RGBA (L006)
            width: Int(extent.width), height: Int(extent.height),
            usage: [.shaderRead, .shaderWrite])
        desc.storageMode = .private                // GPU-local (METAL-4 Apple Silicon UMA = .shared; .private for intermediates)
        guard let texture = device.makeTexture(descriptor: desc) else { throw MetalError.deviceUnavailable }
        // render(_:to:commandBuffer:bounds:colorSpace:) — but the simpler sync overload:
        ciContext.render(image, to: texture,
                         commandBuffer: nil,
                         bounds: extent,
                         colorSpace: ciContext.workingColorSpace!)
        return texture
    }
}
```

**Key API facts:**
- `MTLCreateSystemDefaultDevice()` returns the Apple Silicon unified-memory GPU (D-14). `MTLDevice` is a class, not an actor — wrap the *queue* in your own actor (D-15).
- `device.makeDefaultLibrary(bundle: .main)` reads `default.metallib` from the app bundle. **Must use `Bundle.main`** even in tests because `Bundle(for:)` won't find the metallib without extra config.
- `library.makeFunction(name:constantValues:)` is the function-specialization entry (async since macOS 11; throws if constants mismatch). The non-async `makeFunction(name:)` returns `MTLFunction?`.
- `device.makeComputePipelineState(descriptor:options:reflection:completionHandler:)` is the async PSO builder — do NOT use the synchronous `makeComputePipelineState(function:)` on the MainActor; it stalls.
- `encoder.dispatchThreads(_:threadsPerThreadgroup:)` (macOS 10.14+, Metal 2) is the non-uniform-grid dispatch — preferred over the older `dispatchThreadgroups`. Caps at `pso.maxTotalThreadsPerThreadgroup` per threadgroup (METAL-7).
- `CIContext.render(_:to:commandBuffer:bounds:colorSpace:)` is the GPU-backed render-to-texture (verified against Apple docs). The `commandBuffer: nil` overload is synchronous and runs on `CIContext`'s internal queue — fine for one-shot decode, NOT for per-frame.
- **Storage mode (METAL-4):** on Apple Silicon UMA, `.shared` everywhere is correct and simplest. `.managed` is Intel+AMD-only and pointless here (Apple Silicon only — research Open Question 11 + AGENTS.md doesn't conflict). Use `.private` for large GPU-only intermediates and stage through a blit encoder.

**Gotchas:**
- **`makeFunction(name:constantValues:)` requires `MTLFunctionConstantValues` to set ALL constants the function declares** — partial specialization throws at PSO creation. Mirror the `[[function_constant(N)]]` indices in a Swift table to avoid drift.
- **CIContext workingFormat `kCIFormatRGBAh` vs float32 output**: CIContext internally works in half-float for performance but you can render to a `.rgba32Float` texture — the cast happens at the render step. For the pixelpipe core (Phase 2+), prefer rendering CIRAW output to a float32 buffer ONCE, then running everything else as Metal buffer-to-buffer (per ARCHITECTURE.md §5 "Metal, not Core Image, for the pipe core").
- **`cacheIntermediates: false`** (CIRAW-4) is mandatory — without it, lazy CIImage chains on 100MP hold gigabytes of ROI descriptors. Verify with the Spike B 100MP test.
- **Single `MTLCommandQueue` (D-15)** is fine for Phase 1 (display-only, no contention). The seam to add a low-priority export queue (Phase 11) is just `device.makeCommandQueue()` again — keep `commandQueue` as `private(set)` and add a second property later.

### 4. MTKView + NSViewRepresentable Bridge

**Confidence: High** — well-trodden macOS pattern. The "near-static blit" Phase 1 scope (D-13) means no input event routing yet.

**Bridge pattern:**

```swift
import SwiftUI
import MetalKit

// D-13 Phase 1: display-only (no zoom/pan interaction). Pure blit.
public struct EditorMTKView: NSViewRepresentable {
    let device: MTLDevice
    @Binding var sourceTexture: MTLTexture?   // driven by @Observable EditorState

    public func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = device
        view.delegate = context.coordinator
        view.preferredFramesPerSecond = 60       // D-30 baseline
        view.framebufferOnly = true
        view.colorSrgb = false                   // we manage color via CAMetalLayer
        view.isPaused = false                    // continuous rendering; flip to true when static (perf)
        // CAMetalLayer config (verified: MTKView.layer is CAMetalLayer)
        if let layer = view.layer as? CAMetalLayer {
            layer.pixelFormat = .rgba16Float     // EDR-ready (WWDC22/10114)
            // Phase 8 EDR: layer.wantsExtendedDynamicRangeContent = true
            //               layer.maximumExtendedDynamicRangeColorComponentValue = ...
        }
        return view
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        // UI-2: only forward genuine config changes. NEVER per-frame data here.
        context.coordinator.sourceTexture = sourceTexture
        nsView.isPaused = (sourceTexture == nil)  // pause when no image (UI-1: avoid re-render storms)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(sourceTexture: sourceTexture)
    }

    public final class Coordinator: NSObject, MTKViewDelegate {
        var sourceTexture: MTLTexture?
        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // METAL-9: recompute viewport from new drawable size. No-op for blit phase.
        }
        public func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let texture = sourceTexture,
                  let rpd = view.currentRenderPassDescriptor else { return }
            guard let cmd = view.device!.makeCommandQueue().makeCommandBuffer(),
                  let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
            // Trivial blit: copy full source texture into the drawable via a render pipeline.
            // Phase 2+ replaces this with EditorRenderer (zoom/pan transform, overlays).
            enc.endEncoding()
            cmd.present(drawable)
            cmd.commit()
        }
    }
}
```

**Key API facts (verified against Apple "Creating a custom Metal view" + CAMetalLayer docs):**
- `NSViewRepresentable` is the macOS analog of `UIViewRepresentable`. Methods: `makeNSView`, `updateNSView`, `makeCoordinator`. All run on MainActor.
- `MTKView` is an `NSView` (macOS) whose backing layer is `CAMetalLayer`. `view.layer as? CAMetalLayer` succeeds without extra setup.
- `MTKViewDelegate` has exactly two methods: `mtkView(_:drawableSizeWillChange:)` and `draw(in:)`. The delegate is the per-frame render loop owner — UI-2 pitfall prevention.
- `MTKView.isPaused = true` + `enableSetNeedsDisplay = true` switches from "60fps continuous" to "redraw on demand" — useful when the image is static (the Phase 1 case).
- `preferredFramesPerSecond = 60` is the D-30 baseline; the D-32 hard budget (60fps@100MP) cannot be measured until Phase 2 has the preview pipe (Phase 1 just proves the path works).
- **`CAMetalLayer.pixelFormat = .bgra8Unorm`** is the default; use `.rgba16Float` only if you intend EDR display (Phase 8). For Phase 1, `.bgra8Unorm` + sRGB conversion in the blit shader is simpler.

**Drawable sizing on window resize (METAL-9):**
`MTKView` auto-updates `drawableSize` from its frame * `contentsScale`. The `drawableSizeWillChange` callback fires before the next `draw(in:)`; cache the size and recompute the viewport matrix there. Do NOT reallocate textures per frame — only on size change.

**MainActor isolation (D-33):**
- `NSViewRepresentable` methods and `Coordinator` callbacks all run on MainActor.
- The `@Binding var sourceTexture` is a `MTLTexture?` (a thread-safe reference type); the binding write happens on MainActor when decode completes (see §7).
- `UI-1 pitfall prevention:` do NOT push per-frame data via `updateNSView` — it would cause SwiftUI→AppKit→SwiftUI re-render loops. The Coordinator owns the per-frame state; SwiftUI only updates the *source* of truth (`sourceTexture`).

**Gotchas:**
- **`MTKView`'s default `device` is nil** — you MUST set it in `makeNSView`. Bind to the same `MTLDevice` the `MetalContext` actor owns.
- **Don't use `view.currentDrawable` outside `draw(in:)`** — it's nil until the next frame, and acquiring it blocks.
- **`currentRenderPassDescriptor` load/store actions:** default is `.clear` with black — correct for Phase 1. Phase 2+ may want `.load` to preserve overlays.
- **Gestures (UI-3) deferred** — Phase 1 has no zoom/pan so no trackpad/scroll conflicts. Add `NSMagnificationGestureRecognizer` etc. in Phase 2/3.

### 5. IOPModule Protocol + v50_order

**Confidence: High** — the v50_order table is verbatim from `iop_order.c:298-415` (read in full). The protocol design is a faithful port of `iop_api.h`.

**Protocol (FOUND-03):**

```swift
// Sources/IOP/IOPModule.swift
public protocol IOPModule {
    associatedtype Params: Codable, Hashable       // FOUND-03 — Hashable feeds PipeCache

    static var opName: String { get }              // e.g. "exposure" (Darktable op name)
    static var iopOrder: Float { get }             // from v50_order table (Sources/IOP/iop_order.swift)
    static var flags: IOPFlags { get }             // Darktable IOP_FLAGS_* port
    static var defaultColorspace: IOPColorspace { get }  // iop_api.h:97

    // Init-time defaults; can be re-read after RAW load (e.g. WB from camera).
    func reloadDefaults(image: DecodedImage) async -> Params

    // Bridge GUI params into the per-piece uniform buffer (iop_api.h:196 commit_params).
    func commitParams(_ params: Params, into piece: inout IOPiece) async

    // ROI negotiation (iop_api.h:223-240). Forward & backward pass.
    func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece)
    func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPPiece)

    // The actual processing — Metal dispatch (iop_api.h:257 process / process_cl).
    func process(input: MTLBuffer, output: MTLBuffer,
                 roiIn: ROI, roiOut: ROI, piece: IOPPiece,
                 metal: MetalContext) async throws

    // Optional: tiling variant (iop_api.h:264) — Phase 2+
    // Optional: distort_transform / distort_backtransform (iop_api.h:298) — geometric iops
}

public struct IOPFlags: OptionSet {   // Darktable IOP_FLAGS_* port (imageop.h:84-110)
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let supportsBlending      = IOPFlags(rawValue: 1 << 0)
    public static let allowTiling           = IOPFlags(rawValue: 1 << 1)
    public static let oneInstance           = IOPFlags(rawValue: 1 << 2)
    public static let fence                 = IOPFlags(rawValue: 1 << 3)   // can't be reordered past
    public static let writeDetails          = IOPFlags(rawValue: 1 << 4)
    public static let allowFastPipe         = IOPFlags(rawValue: 1 << 5)
}

public enum IOPColorspace { case raw, RGB, Lab, rawPrepared }
public struct ROI: Equatable { var x, y, width, height: Int; var scale: Float }
public struct IOPPiece {       // per-instance pipe piece state (pixelpipe_hb.h:161)
    var paramsHash: Int        // for cache key
    var dscIn: IOPBufferDesc
    var dscOut: IOPBufferDesc
    var data: MTLBuffer?       // piece->data (iop_api.h:188) — uniforms
}
```

**`v50_order.swift` table (FOUND-03, ported from `iop_order.c:298-415`):**

```swift
// Sources/IOP/iop_order.swift
public enum V50Order {
    /// (opName, position) — verbatim from src/common/iop_order.c:298-415.
    public static let entries: [(opName: String, order: Float)] = [
        ("rawprepare",      1.0),  ("invert",          2.0),
        ("temperature",     3.0),  ("rasterfile",      3.1),
        ("highlights",      4.0),  ("cacorrect",       5.0),
        ("hotpixels",       6.0),  ("rawdenoise",      7.0),
        ("demosaic",        8.0),  ("denoiseprofile",  9.0),
        ("bilateral",      10.0),  ("rotatepixels",   11.0),
        ("scalepixels",    12.0),  ("lens",           13.0),
        ("cacorrectrgb",   13.5),  ("hazeremoval",    14.0),
        ("ashift",         15.0),  ("flip",           16.0),
        ("enlargecanvas",  16.5),  ("overlay",        16.7),
        ("clipping",       17.0),  ("liquify",        18.0),
        ("spots",          19.0),  ("retouch",        20.0),
        ("exposure",       21.0),  ("mask_manager",   22.0),
        ("tonemap",        23.0),  ("toneequal",      24.0),
        ("crop",           24.5),  ("graduatednd",    25.0),
        ("profile_gamma",  26.0),  ("equalizer",      27.0),
        ("colorin",        28.0),  ("channelmixerrgb",28.5),
        ("diffuse",        28.5),  ("censorize",      28.5),
        ("negadoctor",     28.5),  ("blurs",          28.5),
        ("primaries",      28.5),  ("nlmeans",        29.0),
        ("colorchecker",   30.0),  ("defringe",       31.0),
        ("atrous",         32.0),  ("lowpass",        33.0),
        ("highpass",       34.0),  ("sharpen",        35.0),
        ("colortransfer",  37.0),  ("colormapping",   38.0),
        ("channelmixer",   39.0),  ("basicadj",       40.0),
        ("colorharmonizer",40.5),  ("colorbalance",   41.0),
        ("colorequal",     41.2),  ("colorbalancergb",41.5),
        ("rgbcurve",       42.0),  ("rgblevels",      43.0),
        ("basecurve",      44.0),  ("filmic",         45.0),
        ("sigmoid",        45.3),  ("agx",            45.5),
        ("filmicrgb",      46.0),  ("lut3d",          36.0),
        ("colisa",         47.0),  ("tonecurve",      48.0),
        ("levels",         49.0),  ("shadhi",         50.0),
        ("zonesystem",     51.0),  ("globaltonemap",  52.0),
        ("relight",        53.0),  ("bilat",          54.0),
        ("colorcorrection",55.0),  ("colorcontrast",  56.0),
        ("velvia",         57.0),  ("vibrance",       58.0),
        ("colorzones",     60.0),  ("bloom",          61.0),
        ("colorize",       62.0),  ("lowlight",       63.0),
        ("monochrome",     64.0),  ("grain",          65.0),
        ("soften",         66.0),  ("splittoning",    67.0),
        ("vignette",       68.0),  ("colorreconstruct",69.0),
        ("finalscale",     69.4),  ("colorout",       70.0),
        ("clahe",          71.0),  ("overexposed",    73.0),
        ("rawoverexposed", 74.0),  ("dither",         75.0),
        ("borders",        76.0),  ("watermark",      77.0),
        ("gamma",          78.0)
    ]

    /// Lookup position by op name (linear scan — small list, fine).
    public static func order(for opName: String) -> Float? {
        entries.first { $0.opName == opName }?.order
    }
}
```

The `v50_order` table is **load-bearing**: the comments in `iop_order.c:298-415` explain *why* each module sits where it does (e.g. line 346 `nlmeans` "needs a signal as scene-referred as possible", line 380 `lut3d` placement rationale, line 404 `colorreconstruct` "salvage blown areas before ICC intents"). Adopt it verbatim (ARCHITECTURE.md Decision 3).

**No-op pass-through module (success criterion #3):**

```swift
// Sources/IOP/Passthrough.swift — proves the pixelpipe chain end-to-end
public struct PassthroughModule: IOPModule {
    public struct Params: Codable, Hashable { public init() {} }
    public static let opName = "passthrough_spike"
    public static let iopOrder: Float = 50.5    // arbitrary, between shadhi and zonesystem
    public static let flags: IOPFlags = []
    public static let defaultColorspace: IOPColorspace = .RGB

    public func reloadDefaults(image: DecodedImage) async -> Params { Params() }
    public func commitParams(_ params: Params, into piece: inout IOPPiece) async {
        piece.paramsHash = Params().hashValue
    }
    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPPiece) { roi = input }
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPPiece) { input = roi }
    public func process(input: MTLBuffer, output: MTLBuffer,
                        roiIn: ROI, roiOut: ROI, piece: IOPPiece,
                        metal: MetalContext) async throws {
        try await metal.dispatch2D(
            functionName: "pass_through",
            input: input, output: output,
            width: roiOut.width, height: roiOut.height)
        { _ in }   // no extra bindings
    }
}
```

**Gotchas:**
- **`Params: Codable & Hashable` (FOUND-03) is mandatory** — Hashable feeds the cache hash, Codable feeds the sidecar (Phase 2). Structs with all-Codable fields auto-synthesize both. Don't use classes for params.
- **`opName` must match Darktable's `op` string** for any module that will later read/write Darktable-compatible sidecar entries (Phase 2). For internal-only modules (like the Phase 1 passthrough spike), a custom name is fine but document it.
- **The protocol has an `associatedtype`** which prevents `any IOPModule` from being used as a concrete type — use type-erased wrappers (`AnyIOPModule`) or generics at the pixelpipe level. The Phase 2 `ModuleRegistry` maps `opName → IOPModule.Type`.
- **`defaultColorspace` (REQUIRED in Darktable — `REQUIRED(dt_iop_colorspace_type_t, default_colorspace, ...)` at iop_api.h:97)** is mandatory. Phase 1's pass-through uses `.RGB`; the terminal trio (`colorin`/`colorout`/`gamma`) is Phase 2 work.

### 6. ImageIO Metadata Extraction

**Confidence: High** — `CGImageSourceCopyPropertiesAtIndex` is the canonical, stable API. Verified against Apple docs and community examples.

**Pattern (RAW-06, D-23):**

```swift
import ImageIO
import CoreLocation

public struct CaptureMetadata: Codable {       // RAW-06
    public var cameraMake: String?
    public var cameraModel: String?
    public var lensModel: String?
    public var focalLength: Double?             // mm
    public var aperture: Double?                // f-number
    public var shutterSpeed: Double?            // seconds (1/200 = 0.005)
    public var iso: Int?
    public var captureTime: Date?               // DateTimeOriginal
    public var gps: GPSInfo?
    public var orientation: Int?                // EXIF 1..8
    public var width: Int?
    public var height: Int?
    public var dpi: Double?

    public struct GPSInfo: Codable {
        public var latitude: Double?
        public var longitude: Double?
        public var altitude: Double?
    }
}

extension RAWDecoder {
    static func readCaptureMetadata(url: URL) throws -> CaptureMetadata {
        guard let src = CGImageSourceCreateWithURL(url as CFURL,
                          [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw DecodeError.noRAWDecoder
        }
        // DON'T create CGImage — properties are independent of pixel decode.
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        var meta = CaptureMetadata()
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            meta.cameraMake  = (props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any])?[kCGImagePropertyExifAuxLensModel] as? String
                ?? (props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] as? String
            meta.lensModel   = (props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any])?[kCGImagePropertyExifAuxLensModel] as? String
            meta.focalLength = exif[kCGImagePropertyExifFocalLength]    as? Double
            meta.aperture    = exif[kCGImagePropertyExifFNumber]        as? Double
            meta.shutterSpeed = exif[kCGImagePropertyExifExposureTime]  as? Double
            meta.iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
            meta.captureTime = parseEXIFDate(exif[kCGImagePropertyExifDateTimeOriginal] as? String)
            meta.orientation = (props[kCGImagePropertyOrientation] as? Int).map { Int($0) }
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            meta.cameraMake  = meta.cameraMake  ?? (tiff[kCGImagePropertyTIFFMake]  as? String)
            meta.cameraModel = (tiff[kCGImagePropertyTIFFModel] as? String)
        }
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            meta.gps = .init(
                latitude:  gps[kCGImagePropertyGPSLatitude]     as? Double,
                longitude: gps[kCGImagePropertyGPSLongitude]    as? Double,
                altitude:  gps[kCGImagePropertyGPSAltitude]     as? Double
            )
        }
        meta.width  = (props[kCGImagePropertyPixelWidth]  as? Int)
        meta.height = (props[kCGImagePropertyPixelHeight] as? Int)
        meta.dpi    = (props[kCGImagePropertyDPIWidth]    as? Double)
        return meta
    }
}
```

**Key API facts (verified from `CGImageSourceCopyPropertiesAtIndex` docs + iOS SDK headers):**
- `CGImageSourceCreateWithURL(_:options:)` — `kCGImageSourceShouldCache: false` is critical for RAW files (avoids eagerly decoding into memory; we only want metadata here).
- `CGImageSourceCopyPropertiesAtIndex(_:0:_:)` returns the full metadata dictionary. Sub-dictionaries: `kCGImagePropertyExifDictionary`, `kCGImagePropertyExifAuxDictionary` (lens info lives here), `kCGImagePropertyTIFFDictionary` (Make/Model), `kCGImagePropertyGPSDictionary`, `kCGImagePropertyIPTCDictionary`, `kCGImagePropertyXMPDictionary`.
- Lens model lives in `kCGImagePropertyExifAuxDictionary` under `kCGImagePropertyExifAuxLensModel`, NOT in the EXIF main dict. Camera Make/Model are in TIFF dict.
- EXIF dates are strings ("yyyy:MM:dd HH:mm:ss") — write a parser.
- IPTC/XMP (RAW-06) similarly accessible via `kCGImagePropertyIPTCDictionary` / `kCGImagePropertyXMPDictionary` (the latter returns raw XMP as `Data`).
- `kCGImagePropertyOrientation` is 1..8 EXIF orientation. Pass it into CIRAWFilter via `kCIInputImageOrientationKey` for correct upright decode (or apply in the `flip` iop at order 16).
- **XMP read-write** (for Phase 12 META-04 standard EXIF/IPTC/XMP) uses `CGImageDestination` with the metadata in the properties dict. Phase 1 only reads.

**Gotchas:**
- **RAW vs. raster metadata differs:** for HEIC/JPEG/TIFF, `kCGImagePropertyExifDictionary` works directly. For RAW (CR3/NEF/ARW), `CGImageSourceCreateWithURL` may return a sparse dict — combine CIRAWFilter's own metadata (camera matrix, black/white level) with ImageIO's EXIF for the complete picture.
- **CIRAWFilter's metadata ≠ ImageIO's metadata.** CIRAWFilter exposes *RAW technical* params (blackLevel, whiteLevel, neutralChromaticity, baselineExposure) per D-23(b). ImageIO exposes *capture* metadata (camera/lens/EXIF) per D-23(a). The RAWDecoder must merge both.
- **Lensfun-style lens DB** (IOP-GEO-03, Phase 4) reads `lensModel` to pick a profile. Quality of `ExifAux.LensModel` varies by vendor — spike confirms what each camera reports.

### 7. Swift Concurrency for Background Decode

**Confidence: High** — this is the canonical Swift 6 + `@Observable` pattern. Verified against Apple docs and Swift evolution proposals.

**Pattern (D-33, D-34, D-35):**

```swift
import SwiftUI
import Observation

@Observable                  // D-35 — replaces ObservableObject (macOS 14+)
@MainActor                   // D-33 — UI isolation
public final class EditorState {
    public private(set) var image: DecodedImage?
    public private(set) var decodeError: AppError?
    public private(set) var isDecoding: Bool = false
    private var decodeTask: Task<Void, Never>?

    public func load(url: URL, decoder: RAWDecoder, logger: Logger) {
        decodeTask?.cancel()                       // D-34 cancel previous
        decodeTask = Task { [weak self] in
            await MainActor.run { self?.isDecoding = true; self?.decodeError = nil }
            let signpost = OSSignposter(subsystem: "com.kamasylvia.lightamer",
                                        category: "decode")          // D-31
            let id = signpost.beginInterval("decode", "url:\(url.lastPathComponent)")
            do {
                let decoded = try await decoder.decode(url)   // runs off MainActor
                if Task.isCancelled { return }                 // D-34 cancellation
                // Hop back to MainActor to mutate @Observable state.
                await MainActor.run { self?.image = decoded }
            } catch is CancellationError {
                logger.info("decode cancelled: \(url.path)")
            } catch {
                logger.error("decode failed: \(error.localizedDescription)")
                await MainActor.run { self?.decodeError = AppError(error) }  // D-25
            }
            signpost.endInterval("decode", id)
            await MainActor.run { self?.isDecoding = false }
        }
    }
}

// RAWDecoder.decode is async; not @MainActor — runs on background executor.
// Swift 6 enforces data-race safety: any mutable state in RAWDecoder must be actor-isolated.
```

**Key facts:**
- **`@Observable` macro (Swift 5.9+, macOS 14+)** replaces `ObservableObject` + `@Published`. SwiftUI views observe via plain property access; only accessed properties trigger re-renders (more efficient than ObservableObject).
- **`@MainActor` on the class** makes all stored property mutation happen on the main thread — matches D-33 ("MainActor 隔离 UI").
- **`Task { … }` for background decode** inherits the actor context if not detached. To run truly off-MainActor, either mark `RAWDecoder.decode` as `nonisolated`/`actor`-isolated, or use `Task.detached` (less preferred — loses structured cancellation).
- **Cancellation (D-34):** `Task.cancel()` propagates `CancellationError` at the next `try/await` boundary. Long-running CIRAW decode does NOT naturally respond to cancellation — wrap in `withTaskCancellationHandler` if you need to abort a stuck decode.
- **`OSSignposter` (D-31)** is the modern `os.signpost` Swift API. Instruments reads these intervals; `beginInterval`/`endInterval` pair wraps a timed region. Verified to exist since macOS 14.
- **`Logger` (D-27):** `import os; let logger = Logger(subsystem: "com.kamasylvia.lightamer", category: "decode")`. Use `.debug/.info/.error` levels; Console.app filters by subsystem.

**Gotchas:**
- **`RAWDecoder` must be `Sendable`** for Swift 6 strict concurrency. Mark it `final class @unchecked Sendable` (if internally synchronized) or `actor`. The CIRAWFilter instance is NOT Sendable (it's a `CIFilter` subclass) — wrap each decode in a fresh `CIFilter` and return a value type (`DecodedImage`), or actor-isolate the `RAWDecoder`.
- **`@Observable` doesn't work with `@StateObject`/`@ObservedObject`** — use `@State` for the owner in SwiftUI views. Lifetime: `@State` survives view re-renders.
- **`MainActor.run { … }` vs `await foo()` on a MainActor-isolated function:** the latter is preferred (compiler inserts the hop). Use `MainActor.run` only when crossing from a non-isolated context.

### 8. Spike A (CIRAW 9 Boundary) + Spike B (100MP Perf)

**Confidence: High** on methodology. Outcomes are unknown until the spikes run — that's the point.

#### Spike A: CIRAW 9 Capability Boundary

**Goal:** Determine, per camera family, which demosaic/denoise/lens features RAW 9 covers natively vs. which need a Metal port. Determines whether the per-method demosaic menu (Darktable's PPG/RCD/AMaZE/VNG4/Mark.3-pass/dual) is a v1 hard requirement.

**Methodology:**
1. **Branch:** `spike/ciraw9-boundary` (D-06 independent branch).
2. **App:** minimal SwiftUI macOS 27 app — file picker, two image views side-by-side ("RAW 8" / "RAW 9"), `decoderVersion` toggle, log of `supportedDecoderVersions` per file.
3. **Sample files** (one per sensor family, ~12 files total):
   - **Bayer pro:** Canon R5 CR3, Nikon Z8 NEF, Sony A7R V ARW, Phase One IQ4 IIQ, Hasselblad X2D 3FR
   - **Bayer consumer:** Canon R50 CR3, Sony a6700 ARW
   - **X-Trans:** Fuji X-T5 RAF, X100VI RAF, GFX100S RAF (also 100MP)
   - **Quad-Bayer:** OM-1 II ORF (high-res shot), Fuji X-H2S RAF
   - **DNG:** Apple iPhone 15 Pro Max ProRAW DNG, Adobe-converted DNG
4. **What to measure per file:**
   - `supportedDecoderVersions` (raw list)
   - Visual diff: RAW 8 vs RAW 9 at 100% on a noise + edge + detail region (capture screenshots at matched exposure)
   - Timing: decode time (RAW 8 vs RAW 9), via `os.signpost`
   - Memory peak during decode (Instruments Allocations)
   - Per WWDC26/305: which keys are no-ops under RAW 9 (`colorNoiseReductionAmount`, `detailAmount`, `moireReductionAmount`) — verify per camera
   - Lens correction coverage: is embedded opcodes applied? Are lateral CA / vignette corrected?
5. **Report doc** structure (`spike-report-A.md`):
   - Per-camera-row table: sensor family | RAW 9 supported? | demosaic quality (1-5) | denoise quality (1-5) | lens correction coverage | decode time | memory | notes
   - Decision: per camera family, is Apple-default demosaic acceptable for v1, or does the per-method menu become a v1 hard requirement?
   - Golden samples: 100% crops saved as PNG for the torture set (deep shadow, edge detail, X-Trans maze pattern)
6. **Decision criteria:**
   - If RAW 9 produces Darktable-AMaZE-class quality on **all** target cameras → per-method demosaic menu is **deferred** (smaller v1).
   - If RAW 9 is materially worse than Darktable reference on **any** target camera (e.g. Sony A7R V Bayer shows moire) → demosaic menu becomes **v1 hard requirement** → scope a large Metal port (`demosaic_rcd.cl` ~200 lines, `demosaic_markesteijn.cl` ~700 lines for X-Trans).
   - If RAW 9 covers Bayer but not X-Trans → X-Trans-only port (Markesteijn) lands in Phase 3.

#### Spike B: 100MP Metal Performance Vertebra

**Goal:** Confirm 60fps feasibility at zoom/pan on a 100MP GFX100S RAF before committing the iop list. Tests the architectural vertebra (Phase 1 success criterion #4: "100MP GFX100S RAF decodes + displays without jetsam/memory failure").

**Methodology:**
1. **Branch:** `spike/100mp-perf` (D-06).
2. **App:** minimal macOS 27 app — open one RAF, decode via CIRAW, blit to MTKView. Add: zoom (scroll), pan (drag), `os.signpost` interval per frame, FPS counter overlay.
3. **Sample files:**
   - **GFX100S RAF** (~11650×8738, the headline torture image)
   - Sony A7R V ARW (~60MP, the upper Bayer baseline)
   - Canon R5 CR3 (~45MP, common pro body)
4. **Hard budgets (D-32):**
   - 100MP decode ≤ 2.0s
   - Display (decode → drawable) ≤ 500ms
   - Steady-state memory ≤ 4GB
   - Drag frame time ≤ 16ms (60fps) at viewport resolution
5. **What to measure:**
   - **Decode time**: CIRAW 8 vs CIRAW 9, with `os.signpost` intervals.
   - **Memory peak**: Instruments Allocations during full decode. **Specifically test:** does a single 100MP `RGBA32Float` plane (~1.6GB) fit? Does the lazy `CIImage` chain blow up (CIRAW-4)? Confirm `cacheIntermediates: false` keeps memory bounded.
   - **Blit time**: `CIContext.render(_:to:)` into `MTLTexture(.rgba32Float)` — measure.
   - **Drag time**: while scrolling/panning, the MTKView should re-blit at 60fps. If the first attempt drops frames, the Phase 2 preview/full split is mandatory (it is).
   - **GPU working set**: `device.recommendedMaxWorkingSetSize` — confirm the 1.6GB plane is under budget.
6. **Report doc** structure (`spike-report-B.md`):
   - Per-resolution-row table: image | MP | decode time (RAW 8/9) | memory peak | blit time | drag fps | notes
   - Decision: is 100MP viable without tiling in Phase 1? (Per D-20, tiling is Phase 2.) Confirm or overturn D-20 here.
   - Identify the threshold (e.g. >80MP?) above which tiling becomes mandatory.
7. **Decision criteria:**
   - **Pass** (D-20 holds): decode <2s, display <500ms, memory <4GB, drag 60fps on viewport-res blit → tiling deferred to Phase 2.
   - **Fail** (D-20 overturned): if memory exceeds 4GB OR if decode >2s → tiling becomes a Phase 2 hard requirement (escalates Phase 2 scope).
   - **Partial pass**: if decode >2s but display <500ms after warm cache → acceptable (decode is one-shot per image; cache makes subsequent views fast). Document the trade-off.

**Gotchas (both spikes):**
- **Spike apps must NOT depend on the main app's `MetalContext`/`RAWDecoder`** — they're throwaway, but useful patterns will be back-ported. Keep the spike code self-contained.
- **`os.signpost` has near-zero overhead** when not attached to Instruments (D-31) — leave it in production code, not just spikes.
- **Instruments "Metal System Trace"** is the right tool for GPU-side timing; "Allocations" for memory. The combination is what catches the CIRAW-4 lazy-chain blowup.
- **Golden image samples** should be checked into the repo (or LFS) so CI (Phase 13) can re-baseline per macOS version (CIRAW-2 pitfall). Size: a handful of 100% crops, not full 100MP files.

## Validation Architecture

For Nyquist validation: what observable behaviors/edge cases must Phase 1 plans verify?

**Functional correctness:**
- RAW decode succeeds for at least one CR3, one NEF, one ARW, one RAF, one DNG, one HEIC, one JPEG, one PNG, one TIFF (RAW-01/02/04).
- 100MP GFX100S RAF opens without jetsam kill (success criterion #4).
- Decode of a corrupt/truncated RAW fails gracefully with a typed `AppError` (D-25), not a crash.
- `decoderVersion` opt-in: a RAW 9-supported camera reports `.version9` under `#available(macOS 27, *)`; an unsupported camera falls back to `.version8` silently (D-22).
- Metadata reads camera make/model/lens/focal/aperture/shutter/ISO/GPS/capture-time on at least one CR3 and one NEF (RAW-06).
- The trivial Metal pass-through kernel executes end-to-end (success criterion #2): `MTLBuffer` in → identical `MTLBuffer` out, bit-exact.
- The no-op pixelpipe (single pass-through piece) runs through `EditorMTKView` without error (success criterion #3): the decoded RAW appears on screen.
- `IOPModule` protocol compiles with `Params: Codable & Hashable` (FOUND-03) and the `PassthroughModule` conforms.
- `V50Order.entries` count matches Darktable's `v50_order` (~76 entries, no duplicates by opName except deliberate collisions like the 28.5 cluster).
- Three-column `NavigationSplitView` launches with empty-state, dark mode forced (D-10, D-11).
- App icon + menu bar + top toolbar exist (D-12) — content can be stubs.

**Performance validation (D-30, D-32):**
- Decode time, display time, memory peak, drag fps are **measured and recorded** (not necessarily meeting the hard budget yet — that's Phase 2's gate). Phase 1 just establishes the baseline.
- `os.signpost` intervals emit on the decode + display paths and are visible in Instruments.

**Edge cases to handle:**
- File with no EXIF (synthetic test image).
- File with EXIF but no lens info (older bodies).
- File with orientation = 3/6/8 (rotated) — does it display upright? (CIRAWFilter's `kCIInputImageOrientationKey` or the `flip` iop at order 16.)
- RAW 9 supported but `supportedDecoderVersions` does NOT contain "9" (older macOS 27 build pre-OTA camera-list update).
- DNG with embedded original (Adobe round-trip).
- WebP decode (macOS 11+) — verify raster path.
- 16-bit TIFF (raster path).
- 32-bit float TIFF — Phase 2 scope (RAW-03), but the raster path should not crash.
- Multi-image TIFF — first image only.
- Re-opening the same file is fast (no decode re-run in Phase 2 — Phase 1 just measures the cold path).

**Non-goals for Phase 1 (must NOT be validated):**
- Color management correctness (linear Rec2020 → display). Phase 2 (`colorin`/`colorout`/`gamma`).
- History stack persistence. Phase 2.
- Zoom/pan interaction. Phase 2/3 (D-13).
- Tiling fallback. Phase 2 (D-20).
- Golden-image color harness. Phase 2 (D-28 — deferred).
- Any creative iop. Phase 3+.
- CI. Later (D-29).

## Risks & Gotchas

Beyond what PITFALLS.md covers project-wide, Phase 1-specific risks:

1. **`CIFilter.RawDecoders.version9` enum may not yet exist in the macOS 27 SDK at the time of writing.** The string spelling `"9"` passed via `kCIInputDecoderVersionKey` is a safer fallback if the typed enum isn't exposed. **Mitigation:** probe both at build time; prefer the typed enum when available.

2. **`CIContext.render(_:to: MTLTexture)` synchronous overload may block the MainActor if accidentally called there.** The async `render(_:to:commandBuffer:bounds:colorSpace:)` is preferred but requires a `MTLCommandBuffer`. **Mitigation:** the `RAWDecoder.decode` is `async` and runs off-MainActor; CIContextPool is actor-isolated.

3. **`.rgba32Float` texture creation on 100MP is ~1.6GB.** `MTLDevice.makeTexture` can return nil if `recommendedMaxWorkingSetSize` is exceeded (rare on 16GB unified memory, but possible if other GPU work is resident). **Mitigation:** check `maxBufferLength` / `recommendedMaxWorkingSetSize` before allocation; if exceeded, the Phase 2 tiling path engages (D-20).

4. **CIRAWFilter caching across decode calls is undocumented.** Re-instantiating `CIFilter(imageURL:options:)` for the same URL may re-decode from scratch. **Mitigation:** the MipmapCache (Phase 9) caches the *decoded* buffer; Phase 1 just measures the cold cost.

5. **`MTKView.preferredFramesPerSecond = 60` may exceed the display's refresh rate on ProMotion (120Hz) or fall below on 30Hz external displays.** Use `NSScreen.backingScaleFactor` and `maximumFramesPerSecond` to set dynamically. **Mitigation:** for Phase 1 (static blit), set `isPaused = true` and `enableSetNeedsDisplay = true` — redraw only on source change.

6. **`os.Logger` string interpolation uses OSLogMessage runtime interpolation** — interpolating user-controlled strings can leak data into system logs. **Mitigation:** mark user-data interpolations as `.private` (e.g. `logger.info("opened \(url.path, privacy: .public)")` — file paths are fine to log public).

7. **`@Observable` macro requires `import Observation` and a minimum macOS 14 deployment** — satisfied by the macOS 27 floor but worth flagging in case the floor is ever lowered.

8. **XcodeGen's `INFOPLIST_KEY_*` shortcuts** (e.g. `INFOPLIST_KEY_LSApplicationCategoryType`) may not all be supported in the XcodeGen version installed. Verify against `ProjectSpec.md` — fall back to explicit `info.properties` dict if a key doesn't generate correctly.

9. **Test target discovery for `.metal` kernels:** unit tests cannot easily verify Metal compute output because Metal requires a GPU context. **Mitigation:** Phase 1 tests verify *structure* (RAWDecoder returns non-nil, MetalContext initializes, IOPModule conforms) — algorithmic correctness tests are Phase 2 golden-image harness (D-28).

10. **Spike A outcome may invalidate the v1 iop list.** If RAW 9 demosaic is materially worse than Darktable on a target camera, the per-method demosaic port becomes a v1 hard requirement, expanding Phase 3 scope. **Mitigation:** run Spike A early (before Phase 3 planning); the spike report is a planning input.

## Open Questions for Planning

Decisions the planner still needs to make (not already locked in CONTEXT.md):

1. **`RAWDecoder` actor vs. `@unchecked Sendable` class?** Actor is safer (compiler-enforced isolation) but adds hop overhead per property access. Class with internal locks may be faster but requires manual discipline. **Recommendation:** actor — Swift 6 strict concurrency favors it; decode latency dominates over actor hops.

2. **Where does `MetalContext` live in the dependency graph?** Owned by the App `@State`? A singleton? Injected into `EditorState`? **Recommendation:** inject via SwiftUI Environment or pass explicitly — avoids global mutable state (matches Swift Concurrency best practice).

3. **PSO cache eviction policy?** D-16 says "lazy + memory cache" but doesn't specify LRU vs. unbounded. With ~91 modules × N specialization variants, the cache could grow. **Recommendation:** LRU bounded at, say, 256 entries (well above the realistic "active modules in one edit" count). Phase 3+ validates the actual working set.

4. **String Catalog zh/en — do we ship both in Phase 1?** SYS-05 is Phase 13, but the *infrastructure* (the `.xcstrings` file) is cheap to add now. **Recommendation:** add the catalog with English source strings only; defer zh translation to Phase 13. Avoids a retrofit later.

5. **`AppError` enum exhaustiveness — what categories?** D-25 says "RAW/Metal/Session tiers" but the Phase 1 surface is narrower. **Recommendation:** enumerate Phase 1 errors (`.unsupportedFile`, `.decodeFailed`, `.metalDeviceUnavailable`, `.metalPSOFailed`, `.memoryExceeded`, `.cancelled`) and design for extension (Swift `case` exhaustion with `@unknown default` in switches).

6. **Spike deliverable artifact format.** D-06 says "report doc + golden samples + verification app code." Where do these live? **Recommendation:** under `.planning/spikes/spike-a-ciraw9-boundary/` and `.planning/spikes/spike-b-100mp-perf/`, with the verification app code in a sibling `app/` subdir. Golden samples in `app/samples/`.

7. **Should Phase 1 ship the `IOPColorspace` enum and a minimal `colorin`/`colorout`/`gamma` stub?** The terminal trio is Phase 2 (per ROADMAP), but if the Phase 1 no-op pixelpipe needs *something* at the end to produce displayable output, a stub may be required. **Recommendation:** keep Phase 1 strictly to the pass-through; the CIRAW output is displayable as-is (it's already gamma-encoded for screen). Phase 2 introduces the linear-pipe terminal trio.

8. **macOS 27 SDK availability for the build environment.** The user's machine must be running macOS 27 beta (or have the macOS 27 SDK installed) to compile `if #available(macOS 27, *)` checks. **Flag for the planner:** confirm the build environment is on macOS 27 beta before Phase 1 execution begins; otherwise Spike A (RAW 9) cannot run.

9. **App icon and asset catalog.** No explicit CONTEXT decision. **Recommendation:** add `Resources/Assets.xcassets` with a placeholder app icon — required for notarization later (Phase 13) and trivial to add now.

## Sources

### Apple developer documentation
- `CIRAWFilter` (Obj-C header, canonical API): https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS13.0.sdk/System/Library/Frameworks/CoreImage.framework/Headers/CIRAWFilter.h
- `CIRAWFilterOption`: https://developer.apple.com/documentation/coreimage/cirawfilteroption
- `init(imageURL:options:)`: https://developer.apple.com/documentation/coreimage/cifilter-swift.class/init(imageurl:options:)
- RAW Image Options: https://developer.apple.com/documentation/coreimage/raw-image-options
- `CGImageSourceCopyPropertiesAtIndex`: https://developer.apple.com/documentation/imageio/cgimagesourcecopypropertiesatindex(_:_:_:)
- `CGImageProperties` (EXIF/IPTC/TIFF/GPS keys): https://developer.apple.com/documentation/imageio/cgimageproperties
- `MTLFunctionConstantValues`: https://developer.apple.com/documentation/metal/mtlfunctionconstantvalues
- Function specialization: https://developer.apple.com/documentation/metal/using-function-specialization-to-build-pipeline-variants
- `CIContext.render(_:to:commandBuffer:bounds:colorSpace:)`: https://developer.apple.com/documentation/coreimage/cicontext/render(_:to:commandbuffer:bounds:colorspace:)
- `CAMetalLayer`: https://developer.apple.com/documentation/quartzcore/cametallayer
- Creating a custom Metal view: https://developer.apple.com/documentation/metal/creating-a-custom-metal-view
- Setting Resource Storage Modes: https://developer.apple.com/documentation/metal/setting-resource-storage-settings
- Tailor apps for Apple GPUs (TBDR): https://developer.apple.com/documentation/metal/tailor-your-apps-for-apple-gpus-and-tile-based-deferred-rendering
- HDR content (Metal): https://developer.apple.com/documentation/metal/hdr-content
- `NavigationSplitView`: https://developer.apple.com/documentation/swiftui/navigationsplitview
- `MTKView`: https://developer.apple.com/documentation/metalkit/mtkview
- `os.Logger` / `os.signpost` / `OSSignposter`: https://developer.apple.com/documentation/os/logging
- `@Observable` macro: https://developer.apple.com/documentation/observation/observable()

### WWDC sessions
- WWDC26/305 — Enhance RAW image processing with Core Image (RAW 9): https://developer.apple.com/videos/play/wwdc2026/305/
- WWDC23 — Optimize GPU renderers with Metal (function constants, PSO pre-warm)
- WWDC22/10114 — Display EDR content with Core Image, Metal, and SwiftUI: https://developer.apple.com/videos/play/wwdc2022/10114/
- WWDC22/10054 — The SwiftUI Cookbook for Navigation (`NavigationSplitView`)
- WWDC21/10161 — Explore HDR rendering with EDR
- WWDC21/10160 — Capture and process ProRAW images
- WWDC20/10602 — Harness Apple GPUs with Metal (programmable blending)
- WWDC20/10632 — Optimize Metal Performance for Apple silicon Macs
- WWDC16/606 — Advanced Metal Shader Optimization (half-float literal warning, L006)

### XcodeGen
- ProjectSpec.md (canonical schema): https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md
- XcodeGen repo: https://github.com/yonaskolb/XcodeGen
- Issue #1577 (deploymentTarget under supportedDestinations): https://github.com/yonaskolb/XcodeGen/issues/1577

### Darktable source (local, `/Volumes/UNITEK/Documents/Development/darktable/`)
- `src/common/iop_order.c:298-415` — `v50_order` table (ported verbatim into `iop_order.swift`)
- `src/iop/iop_api.h:60-313` — module plugin contract (REQUIRED/DEFAULT/OPTIONAL macros, process/modify_roi_*/commit_params/legacy_params/distort_*)
- `src/develop/imageop.h:84-110` — `dt_iop_flags_t` bitfield (SUPPORTS_BLENDING, ALLOW_TILING, FENCE, etc.)
- `src/develop/pixelpipe_hb.c:1838-1925` — `_dev_pixelpipe_process_rec` recursive core + cache-hit fast path
- `src/develop/pixelpipe_cache.c:99-120` — basichash composition (imgid, pipeType, position, roi, paramsHash)
- `src/iop/exposure.c` — reference `process_cl` shape for the Metal compute translation
- `src/common/exif.cc:418-433, 4796` — XMP key list + `_set_xmp_dt_history` (Phase 2 sidecar reference)

### Project context
- `.planning/PROJECT.md` — macOS 27 floor, linear Rec2020, float32 RGBA, v50_order, Metal-first/CIRAW-as-decoder locks
- `.planning/research/STACK.md` — CIRAW 9 capability boundary table
- `.planning/research/ARCHITECTURE.md` — Darktable pixelpipe/iop architecture, OpenCL→Metal mapping
- `.planning/research/PITFALLS.md` — CIRAW/Metal/NDE/perf pitfalls with prevention
- `.planning/research/SUMMARY.md` — project-level research synthesis
- `AGENTS.md` — Swift/macOS conventions (macOS 27 floor, iop `.swift`+`.metal` pairs, linear Rec2020)
- `LESSONS.md` — L001 (RAW 9 = macOS 27), L005 (layers from pixelpipe start), L006 (half-float banding)

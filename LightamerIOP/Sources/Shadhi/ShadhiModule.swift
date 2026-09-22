import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// SHADHI — shadows & highlights recovery (Plan 03-04-T2, IOP-TONE-04).
// Phase 3's first neighborhood-op module: a gaussian-blurred, inverted
// base layer drives the per-pixel overlay (local contrast enhancement).
//
// Darktable reference: `src/iop/shadhi.c` (tree dc58cf0ba1, 705 lines)
//   - params v5    :66-80   radius/shadows/whitepoint/highlights/compress/
//                           ccors + flags + low_approximation + shadhi_algo
//   - derived      :353-368 strength ×2 rescales, compress ≤ 0.99, the
//                           sign-folded ccorrect pair, unbound_mask
//   - gaussian leg :370-385 dt_gaussian blur of the RAW Lab buffer with
//                           the (0..100, ±128, 0..1) box — or ±FLT_MAX
//                           when unbound — sigma = radius × roi.scale/iscale
//   - overlay math :399-490 CPU form (cross-checked vs gaussian.cl:480-573)
//   - CL leg       :530-575 prep-blur-mix, the shape this module mirrors
//
// LAB DOMAIN (Plan 03-03 LabRoundTrip, the 03-04 hard dependency): the
// blur base AND the overlay both live in Lab (L drives everything, a/b
// ride the chroma factor); the shared LabMath.h conversion brackets the
// three passes (prep → GaussianBlur → mix) in-kernel.
//
// SCOPE DECISIONS (plan checkpoint T2, both recorded):
//   1. Bilateral leg DEFERRED to Phase 5 (shares dt_bilateral with
//      IOP-DENOISE-03, ~1 week of splat/blur/slice work): the enum case
//      stays for XMP/sidecar fidelity, `process` runs the gaussian leg
//      for BOTH algo values (documented divergence — dt would run
//      bilateral), and the panel shows the option disabled. Golden cases
//      pin `shadhi_algo = gaussian` so both sides compare the same
//      algorithm.
//   2. Golden references are SYNTHESIZED (L017 route, like the other Lab
//      modules): dt-cli float export is spatially corrupt on this host
//      and the Lab probe route is piece-state broken (manifest 03-03);
//      dt-side evidence = XMP op_params adoption + uniform-flat PFM
//      probes (the blur of a flat is the flat, so probes pin the OVERLAY
//      math exactly).
//
// PARAM MAPPING: `unbound` (default true) = dt flags & UNBOUND_GAUSSIAN —
// dt's UNBOUND_DEFAULT (flags 127) sets every unbound bit; when false,
// flags = 63 keeps the channel bits (per-channel clamps stay unbound per
// the dt default word) and only clears the gaussian box/unbound_mask
// bit. `order` (dt_gaussian_order_t) is fixed ZERO in v1 (dt default).
//
// MEMORY note: the three scratch planes (Lab prep + column temp + mask)
// make the stage ~4× the input plane (dt's tiling factor for the gaussian
// leg is 3+1); FULL-resolution 100MP export needs the Phase 5 TilingPlan
// wiring (IOP_FLAGS_ALLOW_TILING declared), PREVIEW is unaffected.
// ─────────────────────────────────────────────────────────────────────────

public enum ShadhiKernel {
    public static let prepFunction = "shadhi_prep"
    public static let mixFunction = "shadhi_mix"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class ShadhiModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {

        /// `shadhi_algo` (shadhi.c:60-64) — raw values aligned with dt's
        /// enum for XMP blob fidelity. `.bilateral` is the dt DEFAULT but
        /// is UNREACHABLE in v1 (Phase 5 leg): process falls back to the
        /// gaussian leg (header note above).
        public enum Algo: Int, Codable, Hashable, Sendable {
            case gaussian = 0
            case bilateral = 1
        }

        /// ∈ [0.1, 500], default 100 (shadhi.c:69).
        public var radius: Float
        /// ∈ [-100, 100], default 50 (shadhi.c:70).
        public var shadows: Float
        /// ∈ [-10, 10], default 0 (shadhi.c:71).
        public var whitepoint: Float
        /// ∈ [-100, 100], default -50 (shadhi.c:72).
        public var highlights: Float
        /// ∈ [0, 100], default 50 (shadhi.c:74).
        public var compress: Float
        /// ∈ [0, 100], default 100 (shadhi.c:75).
        public var shadowsCCorrect: Float
        /// ∈ [0, 100], default 50 (shadhi.c:76).
        public var highlightsCCorrect: Float
        /// dt default 1e-6 (shadhi.c:78).
        public var lowApproximation: Float
        /// dt flags & UNBOUND_GAUSSIAN (default flags 127 = UNBOUND_DEFAULT).
        public var unbound: Bool
        /// v1 default = the only reachable leg (dt default is bilateral —
        /// documented divergence, header note).
        public var algo: Algo

        public init(
            radius: Float = 100,
            shadows: Float = 50,
            whitepoint: Float = 0,
            highlights: Float = -50,
            compress: Float = 50,
            shadowsCCorrect: Float = 100,
            highlightsCCorrect: Float = 50,
            lowApproximation: Float = 0.000_001,
            unbound: Bool = true,
            algo: Algo = .gaussian
        ) {
            self.radius = radius
            self.shadows = shadows
            self.whitepoint = whitepoint
            self.highlights = highlights
            self.compress = compress
            self.shadowsCCorrect = shadowsCCorrect
            self.highlightsCCorrect = highlightsCCorrect
            self.lowApproximation = lowApproximation
            self.unbound = unbound
            self.algo = algo
        }
    }

    public static let opName = "shadhi"
    public static let iopOrder: Float = 50.0
    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .Lab

    /// dt UNBOUND_DEFAULT (shadhi.c:54-56) — every per-channel unbound bit
    /// plus UNBOUND_GAUSSIAN.
    public static let unboundFlags: UInt32 = 0b111_1111 // 127
    /// The same word minus UNBOUND_GAUSSIAN (the `unbound = false` mapping).
    public static let boundFlags: UInt32 = 0b011_1111 // 63

    private let device: (any MTLDevice)?
    private var resolvedDevice: (any MTLDevice)?
    private var pieceBuffer: (any MTLBuffer)?
    private var committed: Params?

    // Scratch planes, cached per (width × height) — the module instance is
    // owned by one pipe run's isolation domain (ColisaModule contract).
    private var scratchWidth = 0
    private var scratchHeight = 0
    private var prepTexture: (any MTLTexture)?
    private var blurPlanesBuffer: (any MTLBuffer)?
    private var maskTexture: (any MTLTexture)?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    // MARK: Derived params (shadhi.c:353-368 verbatim)

    /// The commit-time derived uniforms; `internal` for the
    /// CPUDerivationTests shadhi section (known vectors).
    struct Derived: Equatable {
        var radius: Float            // clamped ≥ 0.1
        var shadows: Float           // ±2
        var highlights: Float        // ±2
        var whitepoint: Float        // ≥ 0.01
        var compress: Float          // [0, 0.99]
        var shadowsCCorrect: Float
        var highlightsCCorrect: Float
        var unboundMask: Int32
        var flags: UInt32
    }

    static func derive(_ params: Params) -> Derived {
        let shadows = 2.0 * min(max(-1.0, params.shadows / 100.0), 1.0)
        let highlights = 2.0 * min(max(-1.0, params.highlights / 100.0), 1.0)
        let whitepoint = max(1.0 - params.whitepoint / 100.0, 0.01)
        let compress = min(max(0.0, params.compress / 100.0), 0.99)
        // sign() = x < 0 ? −1 : 1 (shadhi.c:330-333); shadows_ccorrect folds
        // under sign(shadows), highlights_ccorrect under sign(−highlights).
        let shadowsCCorrect = (min(max(0.0, params.shadowsCCorrect / 100.0), 1.0) - 0.5)
            * (shadows < 0 ? -1 : 1) + 0.5
        let highlightsCCorrect = (min(max(0.0, params.highlightsCCorrect / 100.0), 1.0) - 0.5)
            * (highlights > 0 ? -1 : 1) + 0.5
        let flags = params.unbound ? unboundFlags : boundFlags
        // unbound_mask (shadhi.c:366-367): gaussian & UNBOUND_GAUSSIAN
        // (the bilateral branch needs UNBOUND_BILATERAL — deferred leg).
        let unboundMask: Int32 = (params.algo == .gaussian && (flags & unboundFlags) != 0) ? 1 : 0
        return Derived(
            radius: max(0.1, params.radius),
            shadows: shadows,
            highlights: highlights,
            whitepoint: whitepoint,
            compress: compress,
            shadowsCCorrect: shadowsCCorrect,
            highlightsCCorrect: highlightsCCorrect,
            unboundMask: unboundMask,
            flags: flags
        )
    }

    /// MSL mirror of `ShadhiMixUniforms` (ShadhiKernels.metal).
    struct MixUniforms {
        var shadows: Float
        var highlights: Float
        var compress: Float
        var whitepoint: Float
        var shadowsCCorrect: Float
        var highlightsCCorrect: Float
        var lowApproximation: Float
        var unboundMask: Int32
        var flags: UInt32
        var radius: Float // sigma derivation at process time (roi.scale)

        init(derived: Derived, lowApproximation: Float) {
            self.shadows = derived.shadows
            self.highlights = derived.highlights
            self.compress = derived.compress
            self.whitepoint = derived.whitepoint
            self.shadowsCCorrect = derived.shadowsCCorrect
            self.highlightsCCorrect = derived.highlightsCCorrect
            self.lowApproximation = lowApproximation
            self.unboundMask = derived.unboundMask
            self.flags = derived.flags
            self.radius = derived.radius
        }
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        guard let resolved = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }
        resolvedDevice = resolved

        if pieceBuffer == nil || committed != params {
            var uniforms = MixUniforms(derived: Self.derive(params), lowApproximation: params.lowApproximation)
            if pieceBuffer == nil {
                pieceBuffer = resolved.makeBuffer(
                    length: MemoryLayout<MixUniforms>.stride, options: .storageModeShared
                )
            }
            if let buffer = pieceBuffer {
                withUnsafeBytes(of: &uniforms) {
                    buffer.contents().copyMemory(from: $0.baseAddress!, byteCount: MemoryLayout<MixUniforms>.stride)
                }
            }
            committed = params
        }
        piece.data = pieceBuffer
    }

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
    }

    // MARK: Scratch management

    private func ensureScratch(width: Int, height: Int) throws {
        guard width != scratchWidth || height != scratchHeight else { return }
        guard let resolved = resolvedDevice else {
            throw MetalError.psoCreationFailed(ShadhiKernel.prepFunction, nil)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        prepTexture = resolved.makeTexture(descriptor: descriptor)
        maskTexture = resolved.makeTexture(descriptor: descriptor)
        // The blur planes are a device BUFFER (dt gaussian.cl's __global
        // float4* shape — read_write textures drop the backward pass's
        // in-thread read of the forward's write, see GaussianBlurKernels);
        // TWO plane halves (col writes half 0, the row pass reads it and
        // writes half 1 — dt's horizontal phase reads one buffer and
        // writes another, never in place). .shared, not .private: the
        // private allocator interacts badly with later in-process CI
        // renders on macOS 27 (half-frame corruption — L018); on UMA the
        // storage mode carries no bandwidth cost.
        blurPlanesBuffer = resolved.makeBuffer(
            length: width * height * MemoryLayout<Float>.stride * 4 * 2,
            options: .storageModeShared)
        scratchWidth = width
        scratchHeight = height
    }

    // MARK: Process (prep → blur → mix, shadhi.c:530-575 CL shape)

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let uniformsBuffer = piece.data else {
            throw MetalError.psoCreationFailed(ShadhiKernel.mixFunction, nil)
        }
        try ensureScratch(width: input.width, height: input.height)
        guard let prep = prepTexture, let blurPlanes = blurPlanesBuffer, let mask = maskTexture else {
            throw MetalError.psoCreationFailed(ShadhiKernel.prepFunction, nil)
        }

        // The committed uniforms carry the derived values + the clamped
        // radius (sigma needs the per-run roi.scale, shadhi.c:354-355 —
        // iscale 1, the Lightamer pipe carries dt's full-res piece scale).
        let uniforms = uniformsBuffer.contents().assumingMemoryBound(to: MixUniforms.self).pointee
        let sigma = uniforms.radius * roiIn.scale

        // Step 1 — Rec2020 → raw Lab.
        try await metal.dispatch2DTexture(
            functionName: ShadhiKernel.prepFunction,
            input: input,
            output: prep
        )

        // Step 2 — the domain blur (bounds = the Lab box, ±FLT_MAX unbound).
        let unbounded = uniforms.flags == Self.unboundFlags
        let boundsMin: SIMD4<Float> =
            unbounded
            ? SIMD4(repeating: -Float.greatestFiniteMagnitude)
            : SIMD4(0, -128, -128, 0)
        let boundsMax: SIMD4<Float> =
            unbounded
            ? SIMD4(repeating: Float.greatestFiniteMagnitude)
            : SIMD4(100, 128, 128, 1)
        try await GaussianBlur.blur(
            input: prep, output: mask, planes: blurPlanes,
            sigma: sigma, order: .zero,
            boundsMin: boundsMin, boundsMax: boundsMax,
            metal: metal
        )

        // Step 3 — the overlay mix (3 textures + the uniforms buffer).
        let session = try await metal.makeEncoder(functionName: ShadhiKernel.mixFunction)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(mask, index: 1)
        session.encoder.setTexture(output, index: 2)
        session.encoder.setBuffer(uniformsBuffer, offset: 0, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: input.width, height: input.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }
}

import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// SKINSMOOTH — frequency-separation skin smoothing (Plan 07-2, AI-05).
//
// NO DARKTABLE COUNTERPART (L017 route: SELF-SYNTHESIZED float64 reference
// + identity triple — dt has no AI skin-smoothing module; Apple has no
// built-in skin-smoothing CIFilter, 07-RESEARCH §2). The math is the
// classic Photoshop frequency-separation technique:
//
//   low  = GaussianBlur(I, σ_spatial)       ← the SHARED Deriche IIR
//                                             (Common/GaussianBlur.swift,
//                                             reused verbatim — zero
//                                             reimplementation)
//   high = I − low                          ← per-channel split
//   out  = low + attenuate(high)            ← SkinSmoothKernels.metal
//
// THRESHOLD ATTENUATION (D-07-CONTEXT-6 — the anti-plastic key):
// low-amplitude high frequencies (blemishes / noise) are attenuated hard,
// high-amplitude high frequencies (pores, hair, contours) pass through:
//
//   mag = max(|high_R|, |high_G|, |high_B|)     (shared window factor —
//                                                per-channel windows would
//                                                shift hue)
//   g(mag) = raised-cosine soft window centered on t (D-07-2-T2-1):
//            mag ≤ t·(1−w) → 1;  mag ≥ t·(1+w) → 0;  cosine in between
//   attenuate(high) = high · (1 − a·m·g(mag))
//
// where a = strength ∈ [0,1], t = detailPreserve (linear Rec2020
// amplitude), w = 0.25 (transition half-width ratio, DECISIONS D-07-2-T2-1
// — smooth transition, NOT a hard step: a hard |h| ≤ t cut bands at the
// segmentation boundary).
//
// RGB LINEAR DOMAIN: the split runs per-channel independently on linear
// Rec2020 RGB (SoftenModule.swift same-domain precedent — blemish COLOR
// lives in the low band and survives; attenuation touches amplitude only).
//
// IDENTITY TRIPLE (T2 evidence):
//   1. a=0 ⇒ blit fast path — byte-exact (SoftenModule D9 pattern).
//   2. mask == nil ⇒ m ≡ 1: bit-identical to an all-ones mask texture —
//      the mask channel is a NO-OP when absent (the layer mask's spatial
//      limiting rides the Phase 6 blendop, NOT this module — "mask is a
//      layer property", 07-CONTEXT specifics; the in-kernel m is the
//      direct-drive seam for parity + future base-chain use).
//   3. flat field ⇒ any DC-1 blur preserves the flat ⇒ high ≈ 0 ⇒
//      out ≈ flat (L017-proof vacuous identity, soften D5 twin).
//
// MASK SEAM (T2 action 2): `maskPlane` is a DIRECT-DRIVE property (single
// owner, never set by the pipe — `processErased` has no mask parameter and
// none is invented). Production spatial limiting = the layer's mask slot
// through MaskCombiner.effectivePlane → blendop (unchanged Phase 6 model).
//
// σ CHAIN (highpass.c:140 citation — same correlation as soften/highpass):
// r = max(1, ceil(radius·scale)); σ = √((r·(r+1)·8+2)/3).
//
// ROI/HALO (L020/L021/L023, GaussianBlur halo semantics inherited):
// identity-ROI module — forward keeps input; backward widens ceil(3σ)
// symmetrically (D7, soften/highpass twin; tileHalo the same constant).
// ─────────────────────────────────────────────────────────────────────────

public enum SkinSmoothKernel {
    public static let mixFunction = "skin_smooth_mix"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class SkinSmoothModule: IOPModule {

    /// D-07-CONTEXT-6: v1 = two-band Gaussian separation. The enum is the
    /// RESERVED VARIANT SLOT — v2 adds multi-scale wavelet / bilateral
    /// edge-aware cases here (kernel dispatch switches on it); the sidecar
    /// payload is the rawValue, so v2 cases decode without a schema bump.
    public enum Variant: String, Codable, Hashable, Sendable {
        case twoBandGaussian
        // v2 reserved (D-07-CONTEXT-6 deferred): multiScaleWavelet,
        // bilateralEdgeAware — add as cases; the switch below forces the
        // exhaustiveness review at that point.
    }

    public struct Params: Codable, Hashable, Sendable {
        /// Spot-scale radius in FULL-resolution pixels ∈ [1, 32], default 8
        /// (typical blemish scale 4-12px, 07-RESEARCH §2.1). Scaled per-run
        /// by roi.scale like every neighborhood iop.
        public var radius: Float
        /// Strength a ∈ [0, 1], default 0 — the seed's identity value
        /// (a=0 ⇒ blit ⇒ byte-exact, cache-neutral, liquify-empty-path
        /// disposition).
        public var strength: Float
        /// Detail-preserve threshold t (linear Rec2020 |high| amplitude)
        /// ∈ [0, 0.2], default 0.02 — |high| above ~t passes through.
        public var detailPreserve: Float
        /// The variant slot (v1: only .twoBandGaussian).
        public var variant: Variant

        public init(
            radius: Float = 8.0,
            strength: Float = 0.0,
            detailPreserve: Float = 0.02,
            variant: Variant = .twoBandGaussian
        ) {
            self.radius = radius
            self.strength = strength
            self.detailPreserve = detailPreserve
            self.variant = variant
        }
    }

    public static let opName = "skinSmooth"

    /// LIGHTAMER-NATIVE v50 slot 66.5 (the FIRST non-dt row in the
    /// otherwise verbatim table, D-07-CONTEXT-2) — after soften (66.0),
    /// before splittoning (67.0): the blur/creative neighborhood.
    public static let iopOrder: Float = 66.5

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    static let neutralEps: Float = 1e-6
    /// D-07-2-T2-1: the raised-cosine transition half-width, as a ratio of
    /// the threshold t (w=0.25 ⇒ full window = t·0.5 wide).
    static let softnessRatio: Float = 0.25

    private let device: (any MTLDevice)?
    private var resolvedDevice: (any MTLDevice)?
    private var pieceBuffer: (any MTLBuffer)?
    private var committed: Params?

    /// The DIRECT-DRIVE mask seam (T2 action 2): a single-channel r32Float
    /// skin-mask plane, same size as the run plane. NEVER set by the pipe
    /// (processErased has no mask parameter — production spatial limiting
    /// is the layer mask through the blendop). Tests + the future base-
    /// chain API drive it; nil ⇒ m ≡ 1 (identity triple #2).
    public var maskPlane: (any MTLTexture)?

    // Scratch planes, cached per (width × height) — single-owner contract.
    private var scratchWidth = 0
    private var scratchHeight = 0
    private var lowTexture: (any MTLTexture)?
    private var blurPlanesBuffer: (any MTLBuffer)?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
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
            var uniforms = MixUniforms(
                strength: params.strength,
                threshold: params.detailPreserve,
                softness: Self.softnessRatio)
            if pieceBuffer == nil {
                pieceBuffer = resolved.makeBuffer(
                    length: MemoryLayout<MixUniforms>.stride, options: .storageModeShared)
            }
            if let buffer = pieceBuffer {
                withUnsafeBytes(of: &uniforms) {
                    buffer.contents().copyMemory(
                        from: $0.baseAddress!, byteCount: MemoryLayout<MixUniforms>.stride)
                }
            }
            committed = params
        }
        piece.data = pieceBuffer
    }

    /// MSL mirror of `SkinSmoothMixUniforms`. srcOffset rides per-run
    /// (sharpen/soften precedent — the committed buffer carries the
    /// commit-time half).
    struct MixUniforms {
        var strength: Float
        var threshold: Float
        var softness: Float
        var hasMask: Int32 = 0
        var pad0: Int32 = 0
        var srcOffsetX: Int32 = 0
        var srcOffsetY: Int32 = 0
        // 4·float + 2·int32 + 2·int32 = 24 bytes; MSL mirror pads
        // identically (scalar struct, no vec alignment surprises).
    }

    /// The σ chain (highpass.c:140 citation, BOX_ITERATIONS = 8): radius
    /// (FULL-equivalent px) → per-scale int radius → correlation σ.
    /// `internal` for tests.
    static func sigma(radius: Float, scale: Float) -> Float {
        let r = Float(Self.scaledRadius(radius: radius, scale: scale))
        return ((r * (r + 1) * 8 + 2) / 3).squareRoot()
    }

    /// Per-scale integer radius: ceil(radius·scale), floored at 1 (σ=0
    /// degenerates the IIR — radius 0 is not a useful skin scale anyway).
    /// `internal` for tests.
    static func scaledRadius(radius: Float, scale: Float) -> Int {
        max(1, Int((max(1, radius) * max(scale, 0)).rounded(.up)))
    }

    /// The ROI/tile halo (D7, soften/highpass twin): ceil(3σ).
    /// `internal` for tests.
    static func halo(radius: Float, scale: Float) -> Int {
        Int((3 * sigma(radius: radius, scale: scale)).rounded(.up))
    }

    /// Neutral predicate: a ≈ 0 ⇒ blit identity (the attenuation factor
    /// reaches 1 everywhere). `internal` for tests.
    func isNeutral(_ p: Params) -> Bool {
        abs(p.strength) < Self.neutralEps
    }

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    /// D-G5 backward expansion (L020 frame convention, soften twin):
    /// symmetric halo widen; the pipe clamps to the upstream plane.
    /// Neutral → verbatim.
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        guard let uniforms = piece.data?.contents()
            .assumingMemoryBound(to: MixUniforms.self) else {
            input = roi
            return
        }
        if abs(uniforms.pointee.strength) < Self.neutralEps { input = roi; return }
        let h = Self.halo(radius: committed?.radius ?? 8, scale: roi.scale)
        guard h > 0 else { input = roi; return }
        input = roi
        input.x -= h
        input.y -= h
        input.width += 2 * h
        input.height += 2 * h
    }

    // MARK: Tile seam (D7 — halo == the GaussianBlur overlap convention)

    public func tileHalo(roi: ROI, piece: IOPiece) -> Int {
        guard let uniforms = piece.data?.contents()
            .assumingMemoryBound(to: MixUniforms.self) else { return 0 }
        if abs(uniforms.pointee.strength) < Self.neutralEps { return 0 }
        return Self.halo(radius: committed?.radius ?? 8, scale: roi.scale)
    }

    public func tileWorkingSetBytesPerPixel(piece: IOPiece) -> Int {
        guard let uniforms = piece.data?.contents()
            .assumingMemoryBound(to: MixUniforms.self) else { return 0 }
        return abs(uniforms.pointee.strength) < Self.neutralEps ? 0 : 48
        // low (16 B) + IIR planes share (32 B); in/out are the pipe's.
    }

    // MARK: Scratch management (per-size cached; .shared storage — L018)

    private func ensureScratch(width: Int, height: Int) throws {
        guard width != scratchWidth || height != scratchHeight else { return }
        guard let resolved = resolvedDevice else {
            throw MetalError.psoCreationFailed(SkinSmoothKernel.mixFunction, nil)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        lowTexture = resolved.makeTexture(descriptor: descriptor)
        blurPlanesBuffer = resolved.makeBuffer(
            length: width * height * MemoryLayout<Float>.stride * 4 * 2,
            options: .storageModeShared)
        scratchWidth = width
        scratchHeight = height
    }

    // MARK: Process (IIR low leg → threshold attenuation mix)

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let uniformsBuffer = piece.data else {
            throw MetalError.psoCreationFailed(SkinSmoothKernel.mixFunction, nil)
        }
        let committed = committed ?? Params()
        var runUniforms = uniformsBuffer.contents()
            .assumingMemoryBound(to: MixUniforms.self).pointee
        runUniforms.srcOffsetX = Int32(roiOut.x - roiIn.x)
        runUniforms.srcOffsetY = Int32(roiOut.y - roiIn.y)
        runUniforms.hasMask = maskPlane != nil ? 1 : 0

        // Identity fast path (triple #1): a=0 ⇒ out == in, byte-exact blit.
        if abs(runUniforms.strength) < Self.neutralEps {
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }

        let sigma = Self.sigma(radius: committed.radius, scale: roiIn.scale)
        try ensureScratch(width: input.width, height: input.height)
        guard let low = lowTexture, let blurPlanes = blurPlanesBuffer else {
            throw MetalError.psoCreationFailed(SkinSmoothKernel.mixFunction, nil)
        }

        // Step 1 — the LOW band: the shared Deriche IIR at the σ chain
        // (UNBOUNDED — linear Rec2020 is unbounded; the split needs the
        // true low band, clamping would corrupt high = I − low).
        try await GaussianBlur.blur(
            input: input, output: low, planes: blurPlanes,
            sigma: sigma, order: .zero,
            boundsMin: SIMD4(repeating: -Float.greatestFiniteMagnitude),
            boundsMax: SIMD4(repeating: Float.greatestFiniteMagnitude),
            metal: metal
        )

        // Step 2 — the threshold-attenuation mix (per-run uniforms:
        // shared-buffer upload, NOT setBytes — ashift/lens postmortem).
        guard let runBuffer = metal.device.makeBuffer(
            bytes: &runUniforms,
            length: MemoryLayout<MixUniforms>.stride,
            options: .storageModeShared)
        else {
            throw MetalError.deviceUnavailable
        }
        let session = try await metal.makeEncoder(functionName: SkinSmoothKernel.mixFunction)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(low, index: 1)
        if let mask = maskPlane {
            session.encoder.setTexture(mask, index: 2)
        }
        session.encoder.setTexture(output, index: 3)
        session.encoder.setBuffer(runBuffer, offset: 0, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    /// Whole-window blit (dt `copy_image_roi` fast path — soften twin).
    /// Sync (same-queue FIFO orders it; the caller's fence covers
    /// readback, L014).
    private func blitIdentity(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        metal: MetalContext
    ) throws {
        let dx = roiOut.x - roiIn.x
        let dy = roiOut.y - roiIn.y
        guard dx >= 0, dy >= 0 else { return }
        let width = min(roiOut.width, roiIn.width, output.width, max(0, input.width - dx))
        let height = min(roiOut.height, roiIn.height, output.height, max(0, input.height - dy))
        guard width > 0, height > 0 else { return }
        guard let commandBuffer = metal.commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            throw MetalError.deviceUnavailable
        }
        blit.copy(
            from: input, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: dx, y: dy, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: output, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding() // L008: encode close precedes commit, never defer
        commandBuffer.commit()
    }
}

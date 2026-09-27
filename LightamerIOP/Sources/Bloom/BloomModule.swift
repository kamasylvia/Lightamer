import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// BloomModule — Plan 08-2 T3, IOP-FX-03 (op "bloom", v50 slot 61.0).
//
// Darktable reference (tree dc58cf0ba1): `src/iop/bloom.c:47-51` (the
// parameter face) + `:135-180` (the three-stage process shape) +
// `data/kernels/bloom.cl:22-38` (the threshold kernel — the port master
// of stage ①).
//
//   - params :47-51  THREE sliders verbatim: size (0-100, 20),
//                    threshold (0-100, 90), strength (0-100, 25).
//   - geometry: rad = 256·min(100, size+1)/100 (:140); the exec-domain
//                    radius = min(256, ⌈rad·roi.scale/iscale⌉) (:141-142);
//                    scale = 1/exp2(−min(100, strength+1)/100) (:144) —
//                    dt's exponential-brighten form KEPT (research §9.2).
//   - domain adaptation (research §9.2): dt thresholds on Lab L ∈ [0,100];
//                    Lightamer thresholds on the LINEAR Rec2020 luma / 4.0
//                    (the filmic white anchor — a parameterized constant),
//                    thr_lin = (threshold/100)³; the screen blend becomes
//                    the linear 1 − (1−a)(1−b). Default FEEL = the
//                    Manual-Only appearance round (R4) — the numeric
//                    anchors are the formulas, never pre-tuned.
//   - cascade blur  (research §9.3, the P5 winner 0.29s vs 1.87s): ÷8 box
//                    → small-σ separable gaussian at 1/8 resolution →
//                    in-kernel bilinear upsample in the screen pass.
//   - HDR >1.0 ZERO special-casing (research §9.4): screen is
//                    well-defined above 1.0 — the tests pin it.
//
// NO NEUTRAL BLIT FAST PATH: unlike vignette/grain there is no static
// parameter face that zeroes the glow (threshold 100 still blooms HDR
// input above luma 4.0) — every run goes through the kernel chain. Every
// GPU submission rides MetalContext.makeEncoder (the routed acquisition
// point, L031); the SEED instance is DISABLED (the dt defaults
// threshold 90 / strength 25 are not pixel-identity — the creative-
// module disposition; the 08-2 panel drives this instance).
// ─────────────────────────────────────────────────────────────────────────

public enum BloomKernel {
    public static let thresholdFunction = "bloom_threshold"
    public static let boxFunction = "bloom_box_downsample"
    public static let gaussFunction = "bloom_gauss_pass"
    public static let screenFunction = "bloom_screen"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)

    /// All four kernels (the Registry PSO pre-warm list).
    public static let allFunctionNames = [
        thresholdFunction, boxFunction, gaussFunction, screenFunction,
    ]
}

public final class BloomModule: IOPModule {

    /// dt `dt_iop_bloom_params_t` (:47-51) — VERBATIM.
    public struct Params: Codable, Hashable, Sendable {
        /// dt `size` ∈ [0, 100] $DEFAULT 20 — the glow radius driver.
        public var size: Float
        /// dt `threshold` ∈ [0, 100] $DEFAULT 90 — the glow gate.
        public var threshold: Float
        /// dt `strength` ∈ [0, 100] $DEFAULT 25 — the exponential brighten.
        public var strength: Float

        public init(size: Float = 20.0, threshold: Float = 90.0, strength: Float = 25.0) {
            self.size = size
            self.threshold = threshold
            self.strength = strength
        }
    }

    public static let opName = "bloom"

    /// Darktable v50 order slot 61.0 — creative head of the effect tail;
    /// < the 70.0 terminal floor → layer-mask eligible.
    public static let iopOrder: Float = 61.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    // MARK: - the derived geometry (ONE source of truth — the float64
    // reference and the tests consume the SAME static function)

    /// The per-run derived quantities. `internal` for the parity tests.
    struct Geometry {
        /// dt :144 — `1/exp2(−min(100, strength+1)/100)`.
        var scale: Double
        /// research §9.2 — `(threshold/100)³`.
        var thrLin: Double
        /// The 1/8-domain gaussian σ and truncation radius (D-08-2-B1).
        var sigmaSmall: Double
        var gaussRadiusSmall: Int
    }

    /// The dt geometry chain, verbatim where dt has a formula and pinned by
    /// research §9 where it has the mapping. `roiIn.scale / iscale` is the
    /// dt `roi_in->scale / piece->iscale` pair (:141-142). `internal` for
    /// tests.
    static func geometry(
        _ params: Params, roiScale: Double, iscale: Double
    ) -> Geometry {
        // bloom.c:140 — rad in ORIGINAL-image pixels.
        let rad = 256.0 * Double(min(100.0, params.size + 1.0)) / 100.0
        // bloom.c:141-142 — the exec-domain radius, capped at 256 (dt).
        let radiusExec = min(256.0, (rad * roiScale / max(iscale, 1e-9)).rounded(.up))
        // D-08-2-B1 — the small-domain σ: the exec radius ÷ 16 lands the
        // gaussian's ~2σ support on the dt radius feel, ÷8 again for the
        // cascade lattice; floored so tiny radii still smooth.
        let sigmaExec = max(0.5, radiusExec / 16.0)
        let sigmaSmall = max(0.3, sigmaExec / 8.0)
        let gaussRadiusSmall = max(1, Int((2.0 * sigmaSmall).rounded(.up)))
        return Geometry(
            scale: 1.0 / Foundation.exp2(-1.0 * Double(min(100.0, params.strength + 1.0)) / 100.0),
            thrLin: Foundation.pow(Double(params.threshold) / 100.0, 3.0),
            sigmaSmall: sigmaSmall,
            gaussRadiusSmall: gaussRadiusSmall)
    }

    // MSL mirrors (Float half of Geometry).
    struct ThresholdUniforms {
        var scale: Float
        var thrLin: Float
    }

    struct GaussUniforms {
        var sigma: Float
        var radius: Int32
        var horizontal: Int32
        var pad0: Int32 = 0
    }

    /// The thresholded full-res plane + the 1/8 cascade planes
    /// (per-size cached, .shared storage — the soften scratch shape, L018).
    private var thresholdTexture: (any MTLTexture)?
    private var smallA: (any MTLTexture)?
    private var smallB: (any MTLTexture)?
    private var scratchFullW = 0
    private var scratchFullH = 0

    private var committed: Params?

    // MARK: - test seams (L020 — the cascade-intermediate shape pin)

    /// The cached full-res thresholded plane (nil until the first run).
    var thresholdTextureForTesting: (any MTLTexture)? { thresholdTexture }
    /// The cached 1/8 cascade plane that the screen pass consumes.
    var smallTextureForTesting: (any MTLTexture)? { smallA }

    public init() {}

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)
        committed = params
        piece.data = nil
    }

    // MARK: - scratch (per-size cached)

    private func makeTexture(
        _ device: any MTLDevice, width: Int, height: Int
    ) -> (any MTLTexture) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)!
    }

    private func ensureScratch(
        _ device: any MTLDevice, fullW: Int, fullH: Int, smallW: Int, smallH: Int
    ) {
        guard fullW != scratchFullW || fullH != scratchFullH else { return }
        thresholdTexture = makeTexture(device, width: fullW, height: fullH)
        smallA = makeTexture(device, width: smallW, height: smallH)
        smallB = makeTexture(device, width: smallW, height: smallH)
        scratchFullW = fullW
        scratchFullH = fullH
    }

    // MARK: - process (the three-stage chain, bloom.c:135-180 shape)

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let params = committed else {
            throw MetalError.psoCreationFailed(BloomKernel.thresholdFunction, nil)
        }
        let geometry = Self.geometry(
            params, roiScale: Double(roiIn.scale),
            iscale: Double(max(piece.iscale, 1e-9)))
        let smallW = (input.width + 7) / 8
        let smallH = (input.height + 7) / 8
        ensureScratch(
            metal.device, fullW: input.width, fullH: input.height,
            smallW: smallW, smallH: smallH)
        guard let thresholded = thresholdTexture,
              let smallA = smallA, let smallB = smallB else {
            throw MetalError.psoCreationFailed(BloomKernel.thresholdFunction, nil)
        }

        // Stage ① — the thresholded glow (bloom.cl:22-38 + §9.2 mapping).
        do {
            var uniforms = ThresholdUniforms(
                scale: Float(geometry.scale), thrLin: Float(geometry.thrLin))
            guard let buffer = metal.device.makeBuffer(
                bytes: &uniforms, length: MemoryLayout<ThresholdUniforms>.stride,
                options: .storageModeShared)
            else { throw MetalError.deviceUnavailable }
            let session = try await metal.makeEncoder(
                functionName: BloomKernel.thresholdFunction)
            session.encoder.setTexture(input, index: 0)
            session.encoder.setTexture(thresholded, index: 1)
            session.encoder.setBuffer(buffer, offset: 0, index: 0)
            session.encoder.dispatchThreads(
                MTLSize(width: input.width, height: input.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            session.encoder.endEncoding() // L008
            session.commandBuffer.commit()
        }

        // Stage ②a — the ÷8 box downsample.
        do {
            let session = try await metal.makeEncoder(
                functionName: BloomKernel.boxFunction)
            session.encoder.setTexture(thresholded, index: 0)
            session.encoder.setTexture(smallA, index: 1)
            session.encoder.dispatchThreads(
                MTLSize(width: smallW, height: smallH, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            session.encoder.endEncoding() // L008
            session.commandBuffer.commit()
        }

        // Stage ②b — the small-σ separable gaussian (X then Y).
        for horizontal in [true, false] {
            var uniforms = GaussUniforms(
                sigma: Float(geometry.sigmaSmall),
                radius: Int32(geometry.gaussRadiusSmall),
                horizontal: horizontal ? 1 : 0)
            guard let buffer = metal.device.makeBuffer(
                bytes: &uniforms, length: MemoryLayout<GaussUniforms>.stride,
                options: .storageModeShared)
            else { throw MetalError.deviceUnavailable }
            let session = try await metal.makeEncoder(
                functionName: BloomKernel.gaussFunction)
            session.encoder.setTexture(horizontal ? smallA : smallB, index: 0)
            session.encoder.setTexture(horizontal ? smallB : smallA, index: 1)
            session.encoder.setBuffer(buffer, offset: 0, index: 0)
            session.encoder.dispatchThreads(
                MTLSize(width: smallW, height: smallH, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            session.encoder.endEncoding() // L008
            session.commandBuffer.commit()
        }

        // Stage ③ — the linear screen blend with the in-kernel bilinear
        // upsample of the 1/8 glow (smallA now holds the Y-passed result).
        do {
            let session = try await metal.makeEncoder(
                functionName: BloomKernel.screenFunction)
            session.encoder.setTexture(input, index: 0)
            session.encoder.setTexture(smallA, index: 1)
            session.encoder.setTexture(output, index: 2)
            session.encoder.dispatchThreads(
                MTLSize(width: output.width, height: output.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            session.encoder.endEncoding() // L008
            session.commandBuffer.commit()
        }
    }
}

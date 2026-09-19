import Foundation
import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// TONEEQUAL — tone equalizer (Plan 03-05, IOP-TONE-07). Phase 3's heaviest
// module: a three-stage Metal graph (luma mask estimate → detail-preserving
// filter → correction-LUT apply) plus the FIRST TilingPlan-driven FULL
// pipeline (T6).
//
// Darktable reference (tree dc58cf0ba1):
//   - src/iop/toneequal.c   params v2 :170-190; commit :1592-1651;
//                           luminance mask :866-934; LUT apply :771-803;
//                           modify_roi_in :1342-1358 (the radius/halo
//                           semantics the tile seam reports)
//   - src/common/luminance_mask.h   the SEVEN luma estimators + linear_contrast
//                           (plan erratum: "9 estimators" — the enum is 7;
//                           the 9 refers to the user BANDS)
//   - src/common/eigf.h             fast_eigf_surface_blur — the EIGF
//                           detail leg (Gaussian, NOT box mean; plan erratum
//                           recorded on the kernel file)
//   - src/common/fast_guided_filter.h  fast_surface_blur — the guided leg
//                           (box mean)
//
// D-T3 SEMANTICS (checkpoint, plan T3): toneequal = GLOBAL multi-band
// (dt's default mode; no mask dependency — per-region arrives in Phase 6).
// Golden acceptance TWO-TIER: details=none <1e-5 first, EIGF (dt default)
// <1e-4 + ΔE p99 <1.0 second.
//
// DARKTABLE HAS NO OpenCL for this iop (toneequal.c:313 TODO) — the Metal
// port is free-form but the MATH is transcribed formula-by-formula from the
// CPU sources above, and the golden references replicate that math in
// float64 (L017 synthesized route; dt-side evidence = XMP blob adoption +
// uniform-flat PFM probes).
//
// APPLY QUIRK (dt verbatim): `apply_toneequalizer` multiplies ALL FOUR
// channels by the correction (`for_each_channel` = 4) — including alpha.
// We follow: the golden compare sees the same 4th-channel semantics.
// ─────────────────────────────────────────────────────────────────────────

public enum ToneEqualKernel {
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
    // T2-T4 fill these as the kernels land.
    public static let lumaEstimateFunction = "toneeq_luma_estimate"
    public static let bilinear1cFunction = "toneeq_bilinear_1c"
    public static let quantizeFunction = "toneeq_quantize"
    public static let pack4Function = "toneeq_pack4"
    public static let boxMeanXFunction = "toneeq_box_mean_x"
    public static let boxMeanYFunction = "toneeq_box_mean_y"
    public static let guidedABFunction = "toneeq_guided_ab"
    public static let blendFunction = "toneeq_blend"
    public static let applyFunction = "toneeq_apply"
}

/// dt `dt_iop_toneequalizer_filter_t` (:158-165) — raw values for XMP
/// fidelity.
public enum ToneEqualDetails: Int, Codable, Hashable, Sendable {
    case none = 0
    case averagedGuided = 1
    case guided = 2
    case averagedEIGF = 3
    /// dt DEFAULT (:184).
    case eigf = 4
}

/// dt `dt_iop_luminance_mask_method_t` (luminance_mask.h:40-48) — the
/// SEVEN estimators, raw values aligned.
public enum ToneEqualMethod: Int, Codable, Hashable, Sendable {
    case mean = 0
    case lightness = 1
    case value = 2
    case norm1 = 3
    /// dt DEFAULT (:186).
    case norm2 = 4
    case normPower = 5
    case geomean = 6
}

public final class ToneEqualModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {

        /// The 9 EV bands, each ∈ [−2, 2] default 0 (toneequal.c:171-179).
        public var noise: Float
        public var ultraDeepBlacks: Float
        public var deepBlacks: Float
        public var blacks: Float
        public var shadows: Float
        public var midtones: Float
        public var highlights: Float
        public var whites: Float
        public var speculars: Float
        /// smoothing diameter, % of the largest dimension ∈ [0.01, 100],
        /// default 5 (:180).
        public var blending: Float
        /// RBF sigma, default √2 (:181).
        public var smoothing: Float
        /// edges feathering ∈ [0.01, 10000], default 1 (:182); commit
        /// INVERTS it (d->feathering = 1/p — :1617).
        public var feathering: Float
        /// mask quantization step ∈ [0, 2], default 0 (:183).
        public var quantization: Float
        /// mask contrast compensation ±16 EV, default 0 (:184).
        public var contrastBoost: Float
        /// mask exposure compensation ±16 EV, default 0 (:185).
        public var exposureBoost: Float
        /// detail preservation, default EIGF (:186).
        public var details: ToneEqualDetails
        /// luma estimator, default NORM_2 (:187).
        public var method: ToneEqualMethod
        /// filter diffusion iterations ∈ [1, 20], default 1 (:188).
        public var iterations: Int

        public init(
            noise: Float = 0,
            ultraDeepBlacks: Float = 0,
            deepBlacks: Float = 0,
            blacks: Float = 0,
            shadows: Float = 0,
            midtones: Float = 0,
            highlights: Float = 0,
            whites: Float = 0,
            speculars: Float = 0,
            blending: Float = 5,
            smoothing: Float = 1.414_213_5,
            feathering: Float = 1,
            quantization: Float = 0,
            contrastBoost: Float = 0,
            exposureBoost: Float = 0,
            details: ToneEqualDetails = .eigf,
            method: ToneEqualMethod = .norm2,
            iterations: Int = 1
        ) {
            self.noise = noise
            self.ultraDeepBlacks = ultraDeepBlacks
            self.deepBlacks = deepBlacks
            self.blacks = blacks
            self.shadows = shadows
            self.midtones = midtones
            self.highlights = highlights
            self.whites = whites
            self.speculars = speculars
            self.blending = blending
            self.smoothing = smoothing
            self.feathering = feathering
            self.quantization = quantization
            self.contrastBoost = contrastBoost
            self.exposureBoost = exposureBoost
            self.details = details
            self.method = method
            self.iterations = iterations
        }

        /// The 9 bands in dt's order (noise → speculars), for the LUT and
        /// the panel.
        public var bands: [Float] {
            [noise, ultraDeepBlacks, deepBlacks, blacks, shadows,
             midtones, highlights, whites, speculars]
        }
    }

    public static let opName = "toneequal"
    public static let iopOrder: Float = 24.0
    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    /// Commit-time derived state (dt `dt_iop_toneequalizer_data_t` scalar
    /// half, :192-205 + commit :1596-1620). `internal` for the derivation
    /// tests.
    struct Derived: Equatable {
        var blending: Float        // params.blending / 100
        var feathering: Float      // 1 / params.feathering (dt INVERTS)
        var contrastBoost: Float   // exp2(params.contrastBoost)
        var exposureBoost: Float   // exp2(params.exposureBoost)
        var smoothing: Float
        var quantization: Float
        var iterations: Int32
        var details: Int32
        var method: Int32
    }

    static func derive(_ params: Params) -> Derived {
        Derived(
            blending: params.blending / 100.0,
            feathering: 1.0 / params.feathering,
            contrastBoost: Foundation.exp2f(params.contrastBoost),
            exposureBoost: Foundation.exp2f(params.exposureBoost),
            smoothing: params.smoothing,
            quantization: params.quantization,
            iterations: Int32(params.iterations),
            details: Int32(params.details.rawValue),
            method: Int32(params.method.rawValue)
        )
    }

    private let device: (any MTLDevice)?
    private var resolvedDevice: (any MTLDevice)?
    private var pieceBuffer: (any MTLBuffer)?
    private var lutBuffer: (any MTLBuffer)?
    private var committed: Params?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    // MARK: Commit (toneequal.c:1592-1651)

    public func commitParams(_ params: Params, into piece: inout IOPiece) async {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        guard let resolved = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }
        resolvedDevice = resolved

        if pieceBuffer == nil || committed != params {
            var derived = Self.derive(params)
            let bands = params.bands
            let weights = CorrectionLUT.weights(bands: bands, sigma: params.smoothing)
                ?? [Float](repeating: 0, count: CorrectionLUT.controlPointCount)
            let lut = CorrectionLUT.lut(weights: weights, sigma: params.smoothing)

            if pieceBuffer == nil {
                pieceBuffer = resolved.makeBuffer(
                    length: MemoryLayout<Derived>.stride, options: .storageModeShared
                )
                lutBuffer = resolved.makeBuffer(
                    length: CorrectionLUT.lutCount * MemoryLayout<Float>.stride,
                    options: .storageModeShared
                )
            }
            if let buffer = pieceBuffer {
                withUnsafeBytes(of: &derived) {
                    buffer.contents().copyMemory(
                        from: $0.baseAddress!, byteCount: MemoryLayout<Derived>.stride)
                }
            }
            if let buffer = lutBuffer {
                lut.withUnsafeBytes {
                    buffer.contents().copyMemory(
                        from: $0.baseAddress!, byteCount: CorrectionLUT.lutCount * MemoryLayout<Float>.stride)
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

    // MARK: Process — T2/T3/T4 fill the three stages; T1 ships identity.

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        // T1 interim: identity copy (the apply stage replaces this in T4).
        try await metal.dispatch2DTexture(
            functionName: "gaussian_copy", input: input, output: output
        )
    }
}

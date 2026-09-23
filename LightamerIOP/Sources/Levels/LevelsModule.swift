import LightamerCore
import Metal
import simd

// ─────────────────────────────────────────────────────────────────────────
// LEVELS — the Lab-domain black/gray/white points iop (Phase 3 Plan
// 03-03-T4/T5, IOP-TONE-06).
//
// Darktable reference: `src/iop/levels.c` (tree dc58cf0ba1)
//   - params v2      :65-72   mode (manual/automatic), black/gray/white
//                             ∈ [0,100] (defaults 0/50/100 — REUSED AS
//                             PERCENTILES in automatic mode :514-516),
//                             levels[3] (manual points, normalized
//                             [0,1], defaults 0/0.5/1 — init() :588-592)
//   - compute_lut    :252-267  delta=(l2−l0)/2, mid, tmp=(l1−mid)/delta,
//                             in_inv_gamma = 10^tmp, lut[i] = 100·(i/0x10000)^g
//   - process        :387-435  L_in ≤ black → 0; percentage < 1 → LUT
//                             (nearest); else 100·percentage^inv_gamma;
//                             chroma a,b × L_out/max(L,0.01)
//   - kernel         basic.cl:3074 levels (CL chroma branch differs from
//                             CPU — this port follows the CPU form per
//                             plan; recorded below)
//
// LAB DOMAIN: fused Rec2020→Lab→Rec2020 via Common/LabMath.h (Plan 03-03
// Goal) — dt's pixelpipe converts around the IOP_CS_LAB module.
//
// RECORDED DIVERGENCES:
// 1. **Automatic-mode histogram**: dt runs 16384 bins over the module
//    input (:503-516) and syncs the FULL pipe from the preview pipe's
//    histogram (commit_params_late :337-385). Lightamer: 256 bins
//    (plan mandate) computed per pipe run from THIS pipe's input via the
//    shared HistogramReduce (03-03-T5) — the FULL/preview hash-sync
//    machinery is out of scope; the automatic levels are recomputed per
//    run (deterministic per input).
// 2. **Chroma branch**: the CPU process multiplies a,b by
//    L_out/max(L_in, 0.01) (:430-433); the CL kernel instead uses
//    L_out/L_in above the 0.01 gate and L_out alone below it. This port
//    follows the CPU form (plan T4 action 2) — they diverge only for
//    L < 1.0.
// 3. **LUT index rounding**: like colisa/tonecurve — dt truncates, this
//    port rounds (≤1 LSB; the neutral-boundary rationale is on
//    ColisaModule).
// 4. **Degenerate delta guard**: levels[0] == levels[2] makes dt's
//    tmp = 0/0 → NaN LUT; Lightamer clamps delta ≥ 1e-9 (NaN-poisoning
//    guard; dt's GUI prevents the state, Lightamer's sliders allow it).
// ─────────────────────────────────────────────────────────────────────────

public enum LevelsKernel {
    public static let functionName = "levels_apply"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class LevelsModule: IOPModule {

    public enum Mode: Int, Codable, Hashable, Sendable {
        case manual = 0
        case automatic = 1
    }

    /// dt `dt_iop_levels_params_t` v2 (levels.c:65-72).
    public struct Params: Codable, Hashable, Sendable {
        public var mode: Mode
        /// Manual mode: unused (the levels[] points are the truth).
        /// Automatic mode: the three PERCENTILES in [0,100].
        public var black: Float
        public var gray: Float
        public var white: Float
        /// Manual-mode points, normalized [0,1] (dt levels[3], defaults
        /// 0/0.5/1 from init()).
        public var levels: [Float]

        public init(
            mode: Mode = .manual,
            black: Float = 0,
            gray: Float = 50,
            white: Float = 100,
            levels: [Float] = [0, 0.5, 1]
        ) {
            self.mode = mode
            self.black = black
            self.gray = gray
            self.white = white
            self.levels = levels
        }
    }

    public static let opName = "levels"
    public static let iopOrder: Float = 49.0
    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .Lab

    /// LUT resolution (dt `0x10000`).
    public static let lutResolution = 0x10000

    private let device: (any MTLDevice)?
    private var pieceBuffer: (any MTLBuffer)?
    private var committedParams: Params?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    // MARK: CPU LUT derivation (dt compute_lut :252-267)

    /// The gamma from the three points: `in_inv_gamma = 10^((l1−mid)/delta)`.
    public static func inverseGamma(levels l: [Float]) -> Double {
        let l0 = Double(l[0]), l1 = Double(l[1]), l2 = Double(l[2])
        let delta = max((l2 - l0) / 2.0, 1e-9) // divergence #4 (NaN guard)
        let mid = l0 + delta
        let tmp = (l1 - mid) / delta
        return Foundation.pow(10.0, tmp)
    }

    /// `lut[i] = 100 · (i/0x10000)^in_inv_gamma` (levels.c:262-266).
    public static func buildLUT(levels: [Float]) -> [Float] {
        let gamma = inverseGamma(levels: levels)
        var lut = [Float](repeating: 0, count: lutResolution)
        for i in 0..<lutResolution {
            lut[i] = 100.0 * Foundation.pow(Float(i) / Float(lutResolution), Float(gamma))
        }
        return lut
    }

    // MARK: Buffer layout (single MTLBuffer, 16-byte-aligned sections)

    static let lutOffset = 0
    static let lutBytes = lutResolution * MemoryLayout<Float>.size // 262144
    static let uniformOffset = lutBytes
    static let uniformLength = 16

    /// MSL mirror of the trailing uniform section.
    struct LevelsUniforms {
        var levelBlack: Float  // levels[0] (normalized)
        var levelRange: Float  // levels[2] − levels[0]
        var invGamma: Float
        private var _pad: Float = 0

        init(levelBlack: Float, levelRange: Float, invGamma: Float) {
            self.levelBlack = levelBlack
            self.levelRange = levelRange
            self.invGamma = invGamma
        }
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        guard let resolvedDevice = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }

        // Automatic mode: T5 wires the HistogramReduce-derived levels into
        // process(); the commit path builds the IDENTITY LUT as the
        // placeholder (divergence #1 — per-run recompute replaces it).
        let levels: [Float]
        switch params.mode {
        case .manual:
            levels = params.levels
        case .automatic:
            levels = [0, 0.5, 1]
        }

        if pieceBuffer == nil || committedParams != params {
            let lut = Self.buildLUT(levels: levels)
            let gamma = Self.inverseGamma(levels: levels)
            var uniforms = LevelsUniforms(
                levelBlack: levels[0],
                levelRange: levels[2] - levels[0],
                invGamma: Float(gamma)
            )
            if pieceBuffer == nil {
                pieceBuffer = resolvedDevice.makeBuffer(
                    length: Self.uniformOffset + Self.uniformLength,
                    options: .storageModeShared
                )
            }
            if let buffer = pieceBuffer {
                let contents = buffer.contents()
                lut.withUnsafeBytes {
                    contents.advanced(by: Self.lutOffset)
                        .copyMemory(from: $0.baseAddress!, byteCount: Self.lutBytes)
                }
                withUnsafeBytes(of: &uniforms) {
                    contents.advanced(by: Self.uniformOffset)
                        .copyMemory(from: $0.baseAddress!, byteCount: Self.uniformLength)
                }
            }
            committedParams = params
        }
        piece.data = pieceBuffer
    }

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
    }

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        // AUTOMATIC mode (T5): histogram the input → percentile levels →
        // rewrite the piece LUT → apply (dt commit_params_late semantics;
        // recomputed per run — divergence #1). The CPU rewrite completes
        // before the apply dispatch encodes (shared storage), so the
        // kernel reads the fresh LUT.
        if committedParams?.mode == .automatic {
            let histogram = try await HistogramReduce.histogramL(of: input, metal: metal)
            let p = committedParams ?? Params()
            let derived = HistogramReduce.percentileLevels(
                histogram: histogram, percentiles: (p.black, p.gray, p.white)
            )
            rewriteLUT(levels: derived)
        }

        let buffer = piece.data
        try await metal.dispatch2DTexture(
            functionName: LevelsKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            if let buffer {
                encoder.setBuffer(buffer, offset: Self.lutOffset, index: 0)
                encoder.setBuffer(buffer, offset: Self.uniformOffset, index: 1)
            }
        }
    }

    /// Rewrite the LUT + uniform sections of the piece buffer for the
    /// freshly-derived automatic levels (T5).
    private func rewriteLUT(levels: [Float]) {
        guard let buffer = pieceBuffer else { return }
        let lut = Self.buildLUT(levels: levels)
        let gamma = Self.inverseGamma(levels: levels)
        var uniforms = LevelsUniforms(
            levelBlack: levels[0],
            levelRange: levels[2] - levels[0],
            invGamma: Float(gamma)
        )
        let contents = buffer.contents()
        lut.withUnsafeBytes {
            contents.advanced(by: Self.lutOffset)
                .copyMemory(from: $0.baseAddress!, byteCount: Self.lutBytes)
        }
        withUnsafeBytes(of: &uniforms) {
            contents.advanced(by: Self.uniformOffset)
                .copyMemory(from: $0.baseAddress!, byteCount: Self.uniformLength)
        }
    }
}

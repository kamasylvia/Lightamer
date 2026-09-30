import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// BlackModule (Plan M2-5-1 T4; KD-5) — the Alcedo `black` catalog op:
// scene-referred black-endpoint calibration, a ±100 scalar riding the
// ACEScc grade domain (behavior 4): offset = value·0.001 added to every
// channel. Zero is the exact identity (the CPU packs the early-exit flag
// for a byte-identical copy). Shares WhiteBlack.metal with WhiteModule
// (one kernel file, two entries — KD-5's "一枚 kernel 双方向"). Params key
// 照抄 BlackTraits ("black", 0, ±100).
// ─────────────────────────────────────────────────────────────────────────

public enum BlackKernel {
    /// MSL function name (`WhiteBlack.metal` black entry).
    public static let functionName = "grade_black"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class BlackModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {
        /// Alcedo BlackTraits: default 0, clamp ±100.
        public var black: Float

        public init(black: Float = 0) {
            self.black = black
        }
    }

    public static let blackRange: ClosedRange<Float> = (-100.0...100.0)

    public static let opName = "black"

    /// LIGHTAMER V50Order row 41.95 — the KD-3 ±0.05 escape: the planned
    /// 42.0 collides with the (unregistered) dt rgbcurve row, and ONLY the
    /// colorWheels↔colorbalance pair is a declared exception (DECISIONS).
    public static let iopOrder: Float = 41.95

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    public static func clamped(_ params: Params) -> Params {
        Params(black: min(max(params.black, blackRange.lowerBound), blackRange.upperBound))
    }

    private let device: (any MTLDevice)?
    private var uniformsBuffer: (any MTLBuffer)?
    private var committedFlag: Float = -1

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        let clamped = Self.clamped(params)
        // Uniforms: [flag, offset, pad, pad]. The offset = value·0.001
        // (Alcedo behavior 4 — additive in the ACEScc domain).
        var floats: [Float] = [0, clamped.black * 0.001, 0, 0]
        if clamped.black != 0 {
            floats[0] = 1
        }
        if uniformsBuffer == nil || committedFlag != floats[0] {
            let resolved = device ?? MTLCreateSystemDefaultDevice()
            uniformsBuffer = resolved?.makeBuffer(
                length: 4 * MemoryLayout<Float>.stride, options: .storageModeShared)
            committedFlag = floats[0]
        }
        guard let buffer = uniformsBuffer else {
            piece.data = nil
            return
        }
        floats.withUnsafeBytes {
            buffer.contents().copyMemory(
                from: $0.baseAddress!, byteCount: 4 * MemoryLayout<Float>.stride)
        }
        piece.data = buffer
    }

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let buffer = piece.data else { return }
        try await metal.dispatch2DTexture(
            functionName: BlackKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }

    /// The Float64 reference (KD-8): the channel offset in ACEScc space.
    public static func reference(acescc: SIMD3<Double>, black: Double) -> SIMD3<Double> {
        if black == 0 { return acescc }
        let offset = black * 0.001
        return acescc + offset
    }
}

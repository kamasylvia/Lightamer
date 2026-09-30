import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// WhiteModule (Plan M2-5-1 T4; KD-5) — the Alcedo `white` catalog op:
// scene-referred white-endpoint calibration, a ±100 scalar riding the
// ACEScc grade domain (behavior 3): gain = 1 + max(value, 0)·0.005
// multiplied into every channel. Values ≤ 0 are the exact identity (the
// Alcedo max() shape) — the CPU packs the early-exit flag for a
// byte-identical copy. Shares WhiteBlack.metal with BlackModule (one
// kernel file, two entries). Params key照抄 WhiteTraits ("white", 0, ±100).
// ─────────────────────────────────────────────────────────────────────────

public enum WhiteKernel {
    /// MSL function name (`WhiteBlack.metal` white entry).
    public static let functionName = "grade_white"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class WhiteModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {
        /// Alcedo WhiteTraits: default 0, clamp ±100.
        public var white: Float

        public init(white: Float = 0) {
            self.white = white
        }
    }

    public static let whiteRange: ClosedRange<Float> = (-100.0...100.0)

    public static let opName = "white"

    /// LIGHTAMER V50Order row 41.8.
    public static let iopOrder: Float = 41.8

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    public static func clamped(_ params: Params) -> Params {
        Params(white: min(max(params.white, whiteRange.lowerBound), whiteRange.upperBound))
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
        // Uniforms: [flag, gain, pad, pad]. The gain = 1 + max(v,0)·0.005
        // (Alcedo behavior 3 — the negative half is the exact identity).
        var floats: [Float] = [0, 1 + max(clamped.white, 0) * 0.005, 0, 0]
        if clamped.white > 0 {
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
            functionName: WhiteKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }

    /// The Float64 reference (KD-8): the channel gain in ACEScc space.
    public static func reference(acescc: SIMD3<Double>, white: Double) -> SIMD3<Double> {
        if white <= 0 { return acescc }
        let gain = 1.0 + white * 0.005
        return acescc * gain
    }
}

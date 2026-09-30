import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// SaturationModule (Plan M2-5-1 T5; KD-5) — the Alcedo `saturation` catalog
// op: 0–4 multiplicative saturation in the ACEScc grade domain (luma-pivot
// scaling with the peak-raise limiter — Alcedo behavior 9; ≠ colisa's
// saturation which shares the display-referred colisa kernel). Params key
// 照抄 SaturationTraits ("saturation", default 1.0, 0...4).
// ─────────────────────────────────────────────────────────────────────────

public enum SaturationKernel {
    /// MSL function name (`Saturation.metal`).
    public static let functionName = "grade_saturation"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class SaturationModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {
        /// Alcedo SaturationTraits: default 1.0 (= identity), clamp 0...4.
        public var saturation: Float

        public init(saturation: Float = 1.0) {
            self.saturation = saturation
        }
    }

    public static let saturationRange: ClosedRange<Float> = (0.0...4.0)

    public static let opName = "saturation"

    /// LIGHTAMER V50Order row 42.2.
    public static let iopOrder: Float = 42.2

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    public static func clamped(_ params: Params) -> Params {
        Params(
            saturation: min(
                max(params.saturation, saturationRange.lowerBound), saturationRange.upperBound))
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
        var floats: [Float] = [0, clamped.saturation, 0, 0]
        if clamped.saturation != 1.0 {
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
            functionName: SaturationKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }

    /// The Float64 reference (KD-8): the luma-pivot scale + the peak-raise
    /// limiter, on the ACEScc texels (Alcedo behavior 9 — no decode).
    public static func reference(acescc: SIMD3<Double>, saturation: Double) -> SIMD3<Double> {
        if saturation == 1.0 { return acescc }
        var scale = saturation
        let luma = 0.272229 * acescc.x + 0.674082 * acescc.y + 0.053689 * acescc.z
        if scale > 1.5 {
            let peak = max(acescc.x, max(acescc.y, acescc.z))
            let peakRaise = (peak - luma) * (scale - 1.0)
            if peakRaise > 0.1 {
                scale = 1.0 + 0.1 / max(peak - luma, 1.0e-6)
            }
        }
        return SIMD3(
            luma + (acescc.x - luma) * scale,
            luma + (acescc.y - luma) * scale,
            luma + (acescc.z - luma) * scale)
    }
}

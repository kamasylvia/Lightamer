import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// TintModule (Plan M2-5-1 T5; KD-5) — the Alcedo `tint` catalog op: an
// independent ±100 tint scalar (a gentle luma-pivot chroma scale — the
// primary_grade.metal numeric behavior-14 branch; Alcedo's own Tint is
// catalog-only/dormant, DECISIONS §八), DELIBERATELY SEPARATE from the
// CAT02 WB's embedded tint (the catalog carries both, 照抄目录). Params
// key照抄 TintTraits ("tint", 0, ±100).
// ─────────────────────────────────────────────────────────────────────────

public enum TintKernel {
    /// MSL function name (`Tint.metal`).
    public static let functionName = "grade_tint"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class TintModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {
        /// Alcedo TintTraits: default 0, clamp ±100.
        public var tint: Float

        public init(tint: Float = 0) {
            self.tint = tint
        }
    }

    public static let tintRange: ClosedRange<Float> = (-100.0...100.0)

    public static let opName = "tint"

    /// LIGHTAMER V50Order row 42.4.
    public static let iopOrder: Float = 42.4

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    public static func clamped(_ params: Params) -> Params {
        Params(tint: min(max(params.tint, tintRange.lowerBound), tintRange.upperBound))
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
        var floats: [Float] = [0, 1 + clamped.tint * 0.0025, 0, 0]
        if clamped.tint != 0 {
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
            functionName: TintKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }

    /// The Float64 reference (KD-8): the luma-pivot chroma scale
    /// (the primary_grade.metal numeric behavior-14 branch — on the
    /// ACEScc texels, no decode; DECISIONS §八).
    public static func reference(acescc: SIMD3<Double>, tint: Double) -> SIMD3<Double> {
        if tint == 0 { return acescc }
        let scale = 1.0 + tint * 0.0025
        let luma = 0.272229 * acescc.x + 0.674082 * acescc.y + 0.053689 * acescc.z
        return SIMD3(
            luma + (acescc.x - luma) * scale,
            luma + (acescc.y - luma) * scale,
            luma + (acescc.z - luma) * scale)
    }
}

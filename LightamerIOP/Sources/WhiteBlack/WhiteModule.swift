import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// WhiteModule (Plan M2-5-1 T4; KD-5) — the Alcedo `white` catalog op:
// scene-referred white-endpoint calibration, a ±100 scalar. Shares the
// WhiteBlack.metal kernel (two entry points — the endpoint math is shared,
// the direction differs). Params key照抄 WhiteTraits ("white", 0, ±100).
//
// T1 CARRIER NOTE: param/op face only — kernel + registration land with the
// T4 commit (GradeCarrierKernelPending tripwire; op unregistered meanwhile).
// ─────────────────────────────────────────────────────────────────────────

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

    public init() {}

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
    }

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        throw GradeCarrierKernelPending(op: Self.opName)
    }
}

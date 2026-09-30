import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// BlackModule (Plan M2-5-1 T4; KD-5) — the Alcedo `black` catalog op:
// scene-referred black-endpoint calibration, a ±100 scalar. Shares the
// WhiteBlack.metal kernel with WhiteModule (one kernel, two entry points —
// KD-5's "一枚 kernel 双方向"). Params key照抄 BlackTraits ("black", 0,
// ±100).
//
// T1 CARRIER NOTE: param/op face only — kernel + registration land with the
// T4 commit (GradeCarrierKernelPending tripwire; op unregistered meanwhile).
// ─────────────────────────────────────────────────────────────────────────

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

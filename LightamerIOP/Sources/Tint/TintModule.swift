import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// TintModule (Plan M2-5-1 T5; KD-5) — the Alcedo `tint` catalog op: an
// independent ±100 tint scalar (a gentle luma-pivot chroma scale — Alcedo
// behavior 14), DELIBERATELY SEPARATE from the CAT02 WB's embedded tint
// (the catalog carries both,照抄目录). Params key照抄 TintTraits
// ("tint", 0, ±100).
//
// T1 CARRIER NOTE: param/op face only — kernel + registration land with the
// T5 commit (GradeCarrierKernelPending tripwire; op unregistered meanwhile).
// ─────────────────────────────────────────────────────────────────────────

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

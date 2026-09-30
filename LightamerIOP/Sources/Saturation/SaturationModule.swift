import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// SaturationModule (Plan M2-5-1 T5; KD-5) — the Alcedo `saturation` catalog
// op: 0–4 multiplicative saturation in the ACEScc grade domain (luma-pivot
// scaling with the peak-raise limiter — Alcedo behavior 9; ≠ colisa's
// saturation which shares the display-referred colisa kernel). Params key
// 照抄 SaturationTraits ("saturation", default 1.0, 0...4).
//
// T1 CARRIER NOTE: param/op face only — kernel + registration land with the
// T5 commit (GradeCarrierKernelPending tripwire; op unregistered meanwhile).
// ─────────────────────────────────────────────────────────────────────────

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

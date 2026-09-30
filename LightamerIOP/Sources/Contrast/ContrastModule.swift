import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// ContrastModule (Plan M2-5-1 T4; KD-5) — the Alcedo `contrast` catalog op,
// 0.3.0 semantics: an S-curve on OkLab lightness of scene-linear AP1 around
// the 18%-grey pivot, chroma scaled so HUE NEVER DRIFTS — a different
// family from colisa's display-referred RGB scaling (colisa stays its own
// D6 module). Params key照抄 scalar_operator_model.hpp ContrastTraits
// ("contrast", default 0, ±100; the +15 new-image default is defaultLook's
// business, not Params').
//
// T1 CARRIER NOTE: param/op face only — kernel + registration land with the
// T4 commit (GradeCarrierKernelPending tripwire; op unregistered meanwhile).
// ─────────────────────────────────────────────────────────────────────────

public enum ContrastKernel {
    /// MSL function name (`Contrast.metal`, lands with the T4 commit).
    public static let functionName = "grade_contrast"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class ContrastModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {
        /// Alcedo ContrastTraits: default 0, clamp ±100.
        public var contrast: Float

        public init(contrast: Float = 0) {
            self.contrast = contrast
        }
    }

    public static let contrastRange: ClosedRange<Float> = (-100.0...100.0)

    public static let opName = "contrast"

    /// LIGHTAMER V50Order row 41.6 (after colorbalancergb 41.5).
    public static let iopOrder: Float = 41.6

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    /// Alcedo ScalarOperatorModel.SetValue clamp.
    public static func clamped(_ params: Params) -> Params {
        Params(contrast: min(max(params.contrast, contrastRange.lowerBound), contrastRange.upperBound))
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

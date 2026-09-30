import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// Cat02WBModule (Plan M2-5-1 T3; KD-4) — the Alcedo `cat02_white_balance`
// catalog op: creative CAT02 white balance applied in the ACEScc grade
// domain (the envelope's own kernel decodes to linear AP1, this op's 3×3
// adaptation rides between decode/encode; camera WB stays on the RAW Decode
// / CIRAW layer, M2GRADE-04). Params keys照抄
// cat02_white_balance_model.hpp:18-23 ("temperature"/"tint") with the
// AP1-white identity pair 5999.9934 K / 9.7112783 (the Alcedo
// AcesWhiteTemperatureTint() solution, KD-4).
//
// T1 CARRIER NOTE: this commit lands the param/op face the GradeCatalog
// table needs (opName constant + identity + clamp). The adaptation-matrix
// uniforms + kernel + registry.register land with the T3 implementation
// commit; `process` throws GradeCarrierKernelPending until then (the op is
// NOT registered meanwhile — nothing can dispatch it).
// ─────────────────────────────────────────────────────────────────────────

public enum Cat02WBKernel {
    /// MSL function name (`Cat02WB.metal`, lands with the T3 commit).
    public static let functionName = "grade_cat02_wb"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class Cat02WBModule: IOPModule {

    /// Alcedo Cat02WhiteBalancePayload tunable face (the `enabled` field is
    /// the Lightamer ModuleInstance.enabled flag here, not a param).
    public struct Params: Codable, Hashable, Sendable {
        /// Illuminant CCT in Kelvin (2000–15000); the AP1-white default is
        /// identity (KD-4).
        public var temperature: Float
        /// Illuminant tint on the RAW Custom WB tint scale (±150).
        public var tint: Float

        public init(temperature: Float = 5999.9934, tint: Float = 9.7112783) {
            self.temperature = temperature
            self.tint = tint
        }
    }

    /// The identity pair (KD-4) — also the Alcedo header constants.
    public static let identityTemperature: Float = 5999.9934
    public static let identityTint: Float = 9.7112783

    /// Alcedo kCat02TemperatureMin/Max, kCat02TintMin/Max.
    public static let temperatureRange: (ClosedRange<Float>) = (2000.0...15000.0)
    public static let tintRange: (ClosedRange<Float>) = (-150.0...150.0)

    public static let opName = "cat02WhiteBalance"

    /// LIGHTAMER V50Order row 41.4 (colorequal 41.2 之后).
    public static let iopOrder: Float = 41.4

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    /// Alcedo ApplyUpdate clamp (finite → min/max).
    public static func clamped(_ params: Params) -> Params {
        Params(
            temperature: min(max(params.temperature, temperatureRange.lowerBound), temperatureRange.upperBound),
            tint: min(max(params.tint, tintRange.lowerBound), tintRange.upperBound))
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

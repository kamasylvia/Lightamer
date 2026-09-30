import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// HlsModule (Plan M2-5-1 T7; KD-7) — the Alcedo `hls` catalog op
// ("Selective Color"): an 8-bin hue-table adjustment. Params are
// FIELD-FOR-FIELD the Alcedo hls_model.hpp:16-39 payload; JSON keys照抄
// the .cpp ToJson spelling (hue_bins / hls_adj_table / h_range_table /
// target_hls / hls_adj / h_range / l_range / s_range; each HlsVec3 rides as
// an [h, l, s] ARRAY — the Alcedo VecToJson form).
//
// The single-target UI ↔ 8-bin mapping is the `applyTargetEdit` pure
// function (Alcedo editor_hls_model.cpp saveActiveProfile + currentHlsWrite):
// editing one target hue writes THAT bin's adj row and re-projects the
// current-target face (hlsAdj / hRange / targetHls / the fixed l/s ranges).
//
// T1 CARRIER NOTE: param/op face only — kernel + registration land with the
// T7 commit (GradeCarrierKernelPending tripwire; op unregistered meanwhile).
// ─────────────────────────────────────────────────────────────────────────

/// Alcedo `HlsVec3` — encodes as the [h, l, s] JSON array (VecToJson).
public struct HlsVec3: Codable, Hashable, Sendable {
    public var h: Float
    public var l: Float
    public var s: Float

    public init(h: Float = 0, l: Float = 0, s: Float = 0) {
        self.h = h
        self.l = l
        self.s = s
    }

    public init(from decoder: any Decoder) throws {
        var unkeyed = try decoder.unkeyedContainer()
        self.h = try unkeyed.decode(Float.self)
        self.l = try unkeyed.decode(Float.self)
        self.s = try unkeyed.decode(Float.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var unkeyed = encoder.unkeyedContainer()
        try unkeyed.encode(h)
        try unkeyed.encode(l)
        try unkeyed.encode(s)
    }
}

/// The plan-facing alias (KD-7's `applyTargetEdit(...) -> HlsParams`
/// signature name); the canonical nested type is `HlsModule.Params`.
public typealias HlsParams = HlsModule.Params

public final class HlsModule: IOPModule {

    /// Alcedo `HlsPayload` (hls_model.hpp:16-39) — 8 hue bins.
    public struct Params: Codable, Hashable, Sendable {
        /// Bin center hues in degrees (default 0..315 step 45).
        public var hueBins: [Float]
        /// The per-bin {hueShift°, lightness, chroma} adjustments (all-zero
        /// default = identity).
        public var adjTable: [HlsVec3]
        /// Per-bin hue window widths in degrees (default all 45).
        public var hRangeTable: [Float]
        /// The current target's HSL probe point (model default {0, 0.5, 1}).
        public var targetHls: HlsVec3
        /// The current target's adjustment projection (mirrors the active
        /// bin's row — Alcedo `hls_adj`).
        public var hlsAdj: HlsVec3
        /// The active bin's hue window (mirrors hRangeTable[active]).
        public var hRange: Float
        public var lRange: Float
        public var sRange: Float

        public init(
            hueBins: [Float] = [0, 45, 90, 135, 180, 225, 270, 315],
            adjTable: [HlsVec3] = Array(repeating: HlsVec3(), count: 8),
            hRangeTable: [Float] = Array(repeating: 45, count: 8),
            targetHls: HlsVec3 = HlsVec3(h: 0, l: 0.5, s: 1),
            hlsAdj: HlsVec3 = HlsVec3(),
            hRange: Float = 45,
            lRange: Float = 0.1,
            sRange: Float = 0.1
        ) {
            self.hueBins = hueBins
            self.adjTable = adjTable
            self.hRangeTable = hRangeTable
            self.targetHls = targetHls
            self.hlsAdj = hlsAdj
            self.hRange = hRange
            self.lRange = lRange
            self.sRange = sRange
        }

        private enum CodingKeys: String, CodingKey {
            case hueBins = "hue_bins"
            case adjTable = "hls_adj_table"
            case hRangeTable = "h_range_table"
            case targetHls = "target_hls"
            case hlsAdj = "hls_adj"
            case hRange = "h_range"
            case lRange = "l_range"
            case sRange = "s_range"
        }
    }

    /// Alcedo kHlsHueBinCount.
    public static let binCount = 8

    public static let opName = "hls"

    /// LIGHTAMER V50Order row 42.6.
    public static let iopOrder: Float = 42.6

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    // MARK: - The single-target UI ↔ 8-bin mapping (KD-7; OQ-6 销账点)

    /// Alcedo editor_hls_model.cpp mapping constants.
    public static let maxHueShiftDegrees: Float = 30
    public static let adjUIMin: Float = -100
    public static let adjUIMax: Float = 100
    /// The UI lightness/chroma slider is 1000× the stored param value.
    public static let adjUIToParamScale: Float = 1000
    /// The UI's fixed target probe HSL (editor_support hls.hpp — note the
    /// UI writes 0.5/0.5, distinct from the MODEL defaults {0, 0.5, 1}).
    public static let fixedTargetLightness: Float = 0.5
    public static let fixedTargetSaturation: Float = 0.5
    /// The UI's fixed l/s range face (1.0 — the model defaults 0.1 are
    /// only the pristine payload; every UI write re-stamps 1.0/1.0).
    public static let fixedLightnessRange: Float = 1.0
    public static let fixedSaturationRange: Float = 1.0

    /// The Selective Color single-target edit (KD-7): writing the sliders
    /// for `targetBin` stores THAT bin's row — hueShift in degrees (±30),
    /// lightness/chroma as UI units (±100, stored /1000) — and re-projects
    /// the current-target face exactly as Alcedo's `currentHlsWrite`:
    /// hlsAdj/hRange mirror the active bin, targetHls pins the UI probe
    /// {binHue, 0.5, 0.5}, and lRange/sRange re-stamp the fixed 1.0 face.
    public static func applyTargetEdit(
        params: HlsParams, targetBin: Int, dh: Float, dl: Float, ds: Float
    ) -> HlsParams {
        var p = params
        let bin = min(max(targetBin, 0), binCount - 1)
        let hueShift = min(max(dh, -maxHueShiftDegrees), maxHueShiftDegrees)
        let lightness = min(max(dl, adjUIMin), adjUIMax) / adjUIToParamScale
        let chroma = min(max(ds, adjUIMin), adjUIMax) / adjUIToParamScale
        p.adjTable[bin] = HlsVec3(h: hueShift, l: lightness, s: chroma)
        p.hlsAdj = p.adjTable[bin]
        p.hRange = p.hRangeTable[bin]
        p.targetHls = HlsVec3(h: p.hueBins[bin], l: fixedTargetLightness, s: fixedTargetSaturation)
        p.lRange = fixedLightnessRange
        p.sRange = fixedSaturationRange
        return p
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

import CoreImage

/// RAW technical parameters (D-23b) — the Phase 2 color-management inputs
/// (black/white level, baseline exposure, neutral chromaticity) plus the
/// noise-reduction defaults CIRAW reports.
///
/// `public` + `Codable` + `Sendable`: the InspectorState display contract and
/// the Phase 2 sidecar schema. `neutralChromaticity` is a `CIVector` (xy white
/// point, 0...1); `CIVector` is not `Codable`, so it round-trips as `[x, y]`.
public struct RAWTechnicalParams: Codable, Equatable, Sendable {

    /// Sensor black level, normalized to the decoded 0...1 domain.
    /// Sourced from the ImageIO DNG dictionary when present; `0.0` fallback
    /// for proprietary RAW (no public CIRAW key exposes it on macOS 27).
    public var blackLevel: Double

    /// Sensor white level, normalized to the decoded 0...1 domain.
    /// `1.0` fallback when the DNG dictionary is absent (CIRAW output is
    /// already normalized to 0...1).
    public var whiteLevel: Double

    /// Baseline exposure (EV) reported by CIRAW — the offset the in-camera
    /// tone curve implies; Phase 2 `colorin` uses it.
    public var baselineExposure: Double

    /// Neutral (as-shot) white balance chromaticity, xy in 0...1 (D-23b).
    public var neutralChromaticity: CIVector

    /// Aggregate noise-reduction amount CIRAW applies by default.
    public var noiseReductionAmount: Double

    /// Luminance noise reduction (RAW 8 fallback value; no-op under RAW 9 —
    /// WWDC26/305). Recorded for transparency.
    public var luminanceNoiseReduction: Double?

    /// Chroma noise reduction (RAW 8 fallback value; no-op under RAW 9).
    public var colorNoiseReduction: Double?

    // MARK: M2-3-3 T4 (KD-4 膨胀字段规则, plan-scoped exception) — the readback
    // carriers for the USER override legs that have no default readback
    // today. Optional + encodeIfPresent: a nil field keeps the encoded JSON
    // byte-shape AND the HistoryHash folds identical to the pre-M2-3-3
    // documents (the identity-override zero-drift contract). Populated ONLY
    // when the corresponding RAWTechnicalOverrides leg is set — per-image
    // CIRAW defaults never backfill (they would flip every existing
    // decodeParamsHash).

    /// The user's decode sharpness override (`sharpnessAmount`, 0...1).
    public var sharpnessAmount: Double?

    /// The user's decode boost override (`boostAmount`, 0...1).
    public var boost: Double?

    public init(
        blackLevel: Double = 0.0,
        whiteLevel: Double = 1.0,
        baselineExposure: Double = 0.0,
        neutralChromaticity: CIVector = CIVector(x: 0.0, y: 0.0),
        noiseReductionAmount: Double = 0.0,
        luminanceNoiseReduction: Double? = nil,
        colorNoiseReduction: Double? = nil,
        sharpnessAmount: Double? = nil,
        boost: Double? = nil
    ) {
        self.blackLevel = blackLevel
        self.whiteLevel = whiteLevel
        self.baselineExposure = baselineExposure
        self.neutralChromaticity = neutralChromaticity
        self.noiseReductionAmount = noiseReductionAmount
        self.luminanceNoiseReduction = luminanceNoiseReduction
        self.colorNoiseReduction = colorNoiseReduction
        self.sharpnessAmount = sharpnessAmount
        self.boost = boost
    }

    // MARK: Codable — CIVector is not Codable; encode as [x, y].

    private enum CodingKeys: String, CodingKey {
        case blackLevel, whiteLevel, baselineExposure
        case neutralChromaticity
        case noiseReductionAmount, luminanceNoiseReduction, colorNoiseReduction
        case sharpnessAmount, boost
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blackLevel = try c.decode(Double.self, forKey: .blackLevel)
        whiteLevel = try c.decode(Double.self, forKey: .whiteLevel)
        baselineExposure = try c.decode(Double.self, forKey: .baselineExposure)
        let xy = try c.decode([Double].self, forKey: .neutralChromaticity)
        neutralChromaticity = CIVector(x: xy.count > 0 ? xy[0] : 0, y: xy.count > 1 ? xy[1] : 0)
        noiseReductionAmount = try c.decode(Double.self, forKey: .noiseReductionAmount)
        luminanceNoiseReduction = try c.decodeIfPresent(Double.self, forKey: .luminanceNoiseReduction)
        colorNoiseReduction = try c.decodeIfPresent(Double.self, forKey: .colorNoiseReduction)
        sharpnessAmount = try c.decodeIfPresent(Double.self, forKey: .sharpnessAmount)
        boost = try c.decodeIfPresent(Double.self, forKey: .boost)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(blackLevel, forKey: .blackLevel)
        try c.encode(whiteLevel, forKey: .whiteLevel)
        try c.encode(baselineExposure, forKey: .baselineExposure)
        try c.encode([neutralChromaticity.x, neutralChromaticity.y], forKey: .neutralChromaticity)
        try c.encode(noiseReductionAmount, forKey: .noiseReductionAmount)
        try c.encodeIfPresent(luminanceNoiseReduction, forKey: .luminanceNoiseReduction)
        try c.encodeIfPresent(colorNoiseReduction, forKey: .colorNoiseReduction)
        try c.encodeIfPresent(sharpnessAmount, forKey: .sharpnessAmount)
        try c.encodeIfPresent(boost, forKey: .boost)
    }

    // MARK: M2-3-3 T4 (KD-4) — the override readback

    /// Land the USER-SET override legs into the technical record (the cache
    /// key drift carrier). NIL legs never write — per-image CIRAW defaults
    /// must not backfill (the identity zero-drift contract: an identity
    /// request leaves this record, its JSON and its HistoryHash folds
    /// byte-identical to the pre-M2-3-3 decode).
    public mutating func applyOverrides(_ overrides: RAWTechnicalOverrides) {
        if let value = overrides.noiseReductionAmount {
            noiseReductionAmount = value
        }
        if let value = overrides.luminanceNoiseReduction {
            luminanceNoiseReduction = value
        }
        if let value = overrides.colorNoiseReduction {
            colorNoiseReduction = value
        }
        if let value = overrides.sharpness {
            sharpnessAmount = value
        }
        if let value = overrides.boost {
            boost = value
        }
    }
}

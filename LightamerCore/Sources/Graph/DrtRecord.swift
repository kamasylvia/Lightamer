import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// DrtRecord — the Display Transform document-level parameter record
// (Plan M2-6-1 T1, KD-1: the linkage/HDR-judgment knowledge lives in THIS
// one file — OQ-2-A / OQ-5-A / OQ-6-A land here).
//
// SCHEMA PROVENANCE (KD-1): the field set, spelling and defaults mirror the
// Alcedo `drt_node_model.hpp` payload (`OpenDrtDetailedParams` :45-99,
// `DrtPayload` :101-115) field-for-field — the JSON keys are the hpp
// snake_case spellings verbatim (explicit CodingKeys; no Swift camelCase
// conversion). rawValue TERMINAL FORMS were nailed by reading the Alcedo
// `drt_node_model.cpp` ToJson (:23-74) — they are NOT the naive snake_case
// of the enum names:
//   method        → "aces_2_0" / "open_drt"          (cpp :23-25)
//   spaces        → "rec709" / "rec2020" / "p3_d65"  (cpp :27-40)
//   eotf          → "linear" / "st2084" / "hlg" / "gamma_2_6" / "bt1886"
//                    / "gamma_2_2" / "gamma_1_8"      (cpp :53-74)
// VALUE-DOMAIN DEVIATION (KD-1 m4 bullet): the Alcedo `DrtColorSpace` enum
// carries only THREE values (Rec709 / Rec2020 / P3D65, hpp :29-33) shared by
// encoding_space and limiting_space. Lightamer's `DrtEncodingSpace` (6) and
// `DrtLimitingSpace` (7) exceed that domain — the extra values have NO hpp/cpp
// source; their rawValues are Lightamer spellings following the cpp
// convention (`p3_d60`, `p3_dci` by direct analogy; `xyz`, `pro_photo`,
// `adobe_rgb` self-coined). Do NOT claim "copied from hpp" for these.
//
// LICENSING: schema/field facts only — no GPL code or text was copied into
// this file (D-M2-6-CONTEXT-1; NOTICE at the repo root records provenance).
// ─────────────────────────────────────────────────────────────────────────────

/// The DRT method (M2DRT-06 registration gate — the rawValue space IS the
/// registration surface). `aces20`'s render arm is an explicit stub in this
/// plan (KD-6); P2 fills it. filmic/sigmoid/agx are deliberately NOT cases
/// here (D-M2-6-CONTEXT-12: v1 zero registration — new methods join by
/// adding a case, which breaks every exhaustive switch at compile time).
public enum DrtMethod: String, Codable, Sendable, CaseIterable {
    /// ACES 2.0 — render arm stubbed (M2-6-2 fills it). rawValue per the
    /// Alcedo cpp ToJson terminal form.
    case aces20 = "aces_2_0"
    /// OpenDRT (jedypod v1.1.0 algorithm) — the default method.
    case opendrt = "open_drt"
}

/// The encoding/display color space (model layer carries ALL six; the UI
/// exposes the legal subset through `legalEOTFs(for:)` — D-M2-6-CONTEXT-5).
public enum DrtEncodingSpace: String, Codable, Sendable, CaseIterable {
    case rec709
    /// P3-D65 — rawValue per the Alcedo cpp ToJson terminal form.
    case p3d65 = "p3_d65"
    /// Beyond-hpp extension (m4): self-coined spelling, no Alcedo source.
    case p3d60 = "p3_d60"
    /// Beyond-hpp extension (m4): self-coined spelling, no Alcedo source.
    case p3dci = "p3_dci"
    /// Beyond-hpp extension (m4): self-coined spelling, no Alcedo source.
    case xyz
    case rec2020
}

/// The encoding EOTF (model layer carries ALL seven values — `linear` and
/// `gamma18` are legal to PERSIST but appear in no space's legal set; the
/// linkage table expresses that by simply never listing them).
public enum DrtEotf: String, Codable, Sendable, CaseIterable {
    case linear
    /// ST 2084 PQ.
    case st2084
    /// BT.2100 HLG (1000-nit reference OOTF).
    case hlg
    /// Pure 2.6 power (DCI).
    case gamma26 = "gamma_2_6"
    /// ITU-R BT.1886 (γ 2.4; Lightamer terminal form Lb=0 → β=0, see
    /// M2-6-1-DECISIONS).
    case bt1886
    /// Pure 2.2 power (sRGB display).
    case gamma22 = "gamma_2_2"
    /// Pure 1.8 power.
    case gamma18 = "gamma_1_8"
    /// The IEC 61966-2-1 piecewise (M4-1-01 OQ-1①: the rawValue is the
    /// Alcedo serialization spelling, hpp `SrgbPiecewise` → "srgb_piecewise").
    case srgbPiecewise = "srgb_piecewise"
}

/// The limiting color space (ACES 2.0 method only — OpenDRT ignores it).
public enum DrtLimitingSpace: String, Codable, Sendable, CaseIterable {
    case rec709
    case rec2020
    case p3d65 = "p3_d65"
    /// Beyond-hpp extension (m4): self-coined spelling, no Alcedo source.
    case p3d60 = "p3_d60"
    /// Beyond-hpp extension (m4): self-coined spelling, no Alcedo source.
    case p3dci = "p3_dci"
    /// Beyond-hpp extension (m4): self-coined spelling, no Alcedo source.
    case proPhoto = "pro_photo"
    /// Beyond-hpp extension (m4): self-coined spelling, no Alcedo source.
    case adobeRGB = "adobe_rgb"
}

// MARK: - Detailed parameters (the 53-float editor-owned group)

/// The OpenDRT detailed parameter group — ONE Codable object serialized
/// whole (the Alcedo hpp `OpenDrtDetailedParams` model; the editor owns the
/// group as a unit, presets are named snapshots of it — OQ-2-A). Field
/// order/spelling/defaults mirror hpp :45-98 verbatim. There are exactly 53
/// fields: tn×9 + cwp_lm + rs×3 + pt_lml×4 + pt_lmh×3 + ptl×3 + ptm×6 +
/// brl×6 + brlp×4 + hc×2 + hs×12.
public struct OpenDrtDetailedParams: Codable, Hashable, Sendable {
    public var tnCon: Float
    public var tnSh: Float
    public var tnToe: Float
    public var tnOff: Float
    public var tnHcon: Float
    public var tnHconPv: Float
    public var tnHconSt: Float
    public var tnLcon: Float
    public var tnLconW: Float
    public var cwpLm: Float
    public var rsSa: Float
    public var rsRw: Float
    public var rsBw: Float
    public var ptLml: Float
    public var ptLmlR: Float
    public var ptLmlG: Float
    public var ptLmlB: Float
    public var ptLmh: Float
    public var ptLmhR: Float
    public var ptLmhB: Float
    public var ptlC: Float
    public var ptlM: Float
    public var ptlY: Float
    public var ptmLow: Float
    public var ptmLowRng: Float
    public var ptmLowSt: Float
    public var ptmHigh: Float
    public var ptmHighRng: Float
    public var ptmHighSt: Float
    public var brl: Float
    public var brlR: Float
    public var brlG: Float
    public var brlB: Float
    public var brlRng: Float
    public var brlSt: Float
    public var brlp: Float
    public var brlpR: Float
    public var brlpG: Float
    public var brlpB: Float
    public var hcR: Float
    public var hcRRng: Float
    public var hsR: Float
    public var hsRRng: Float
    public var hsG: Float
    public var hsGRng: Float
    public var hsB: Float
    public var hsBRng: Float
    public var hsC: Float
    public var hsCRng: Float
    public var hsM: Float
    public var hsMRng: Float
    public var hsY: Float
    public var hsYRng: Float

    /// Defaults = hpp :46-98 verbatim (the Standard look's numbers — the
    /// dctl look_preset==0 branch carries the same values).
    public init() {
        tnCon = 1.66
        tnSh = 0.5
        tnToe = 0.003
        tnOff = 0.005
        tnHcon = 0.0
        tnHconPv = 1.0
        tnHconSt = 4.0
        tnLcon = 0.0
        tnLconW = 0.5
        cwpLm = 0.25
        rsSa = 0.35
        rsRw = 0.25
        rsBw = 0.55
        ptLml = 0.25
        ptLmlR = 0.5
        ptLmlG = 0.0
        ptLmlB = 0.1
        ptLmh = 0.25
        ptLmhR = 0.5
        ptLmhB = 0.0
        ptlC = 0.06
        ptlM = 0.08
        ptlY = 0.06
        ptmLow = 0.4
        ptmLowRng = 0.25
        ptmLowSt = 0.5
        ptmHigh = -0.8
        ptmHighRng = 0.35
        ptmHighSt = 0.4
        brl = 0.0
        brlR = -2.5
        brlG = -1.5
        brlB = -1.5
        brlRng = 0.5
        brlSt = 0.35
        brlp = -0.5
        brlpR = -1.25
        brlpG = -1.25
        brlpB = -0.25
        hcR = 1.0
        hcRRng = 0.3
        hsR = 0.6
        hsRRng = 0.6
        hsG = 0.35
        hsGRng = 1.0
        hsB = 0.66
        hsBRng = 1.0
        hsC = 0.25
        hsCRng = 1.0
        hsM = 0.0
        hsMRng = 1.0
        hsY = 0.0
        hsYRng = 1.0
    }

    private enum CodingKeys: String, CodingKey {
        case tnCon = "tn_con"
        case tnSh = "tn_sh"
        case tnToe = "tn_toe"
        case tnOff = "tn_off"
        case tnHcon = "tn_hcon"
        case tnHconPv = "tn_hcon_pv"
        case tnHconSt = "tn_hcon_st"
        case tnLcon = "tn_lcon"
        case tnLconW = "tn_lcon_w"
        case cwpLm = "cwp_lm"
        case rsSa = "rs_sa"
        case rsRw = "rs_rw"
        case rsBw = "rs_bw"
        case ptLml = "pt_lml"
        case ptLmlR = "pt_lml_r"
        case ptLmlG = "pt_lml_g"
        case ptLmlB = "pt_lml_b"
        case ptLmh = "pt_lmh"
        case ptLmhR = "pt_lmh_r"
        case ptLmhB = "pt_lmh_b"
        case ptlC = "ptl_c"
        case ptlM = "ptl_m"
        case ptlY = "ptl_y"
        case ptmLow = "ptm_low"
        case ptmLowRng = "ptm_low_rng"
        case ptmLowSt = "ptm_low_st"
        case ptmHigh = "ptm_high"
        case ptmHighRng = "ptm_high_rng"
        case ptmHighSt = "ptm_high_st"
        case brl
        case brlR = "brl_r"
        case brlG = "brl_g"
        case brlB = "brl_b"
        case brlRng = "brl_rng"
        case brlSt = "brl_st"
        case brlp
        case brlpR = "brlp_r"
        case brlpG = "brlp_g"
        case brlpB = "brlp_b"
        case hcR = "hc_r"
        case hcRRng = "hc_r_rng"
        case hsR = "hs_r"
        case hsRRng = "hs_r_rng"
        case hsG = "hs_g"
        case hsGRng = "hs_g_rng"
        case hsB = "hs_b"
        case hsBRng = "hs_b_rng"
        case hsC = "hs_c"
        case hsCRng = "hs_c_rng"
        case hsM = "hs_m"
        case hsMRng = "hs_m_rng"
        case hsY = "hs_y"
        case hsYRng = "hs_y_rng"
    }

    /// Tolerant decode: every field decodeIfPresent with the hpp default as
    /// the fallback (a partial/hand-edited record still yields a valid
    /// group — the same defensive posture the sidecar readers carry).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        tnCon = try c.decodeIfPresent(Float.self, forKey: .tnCon) ?? d.tnCon
        tnSh = try c.decodeIfPresent(Float.self, forKey: .tnSh) ?? d.tnSh
        tnToe = try c.decodeIfPresent(Float.self, forKey: .tnToe) ?? d.tnToe
        tnOff = try c.decodeIfPresent(Float.self, forKey: .tnOff) ?? d.tnOff
        tnHcon = try c.decodeIfPresent(Float.self, forKey: .tnHcon) ?? d.tnHcon
        tnHconPv = try c.decodeIfPresent(Float.self, forKey: .tnHconPv) ?? d.tnHconPv
        tnHconSt = try c.decodeIfPresent(Float.self, forKey: .tnHconSt) ?? d.tnHconSt
        tnLcon = try c.decodeIfPresent(Float.self, forKey: .tnLcon) ?? d.tnLcon
        tnLconW = try c.decodeIfPresent(Float.self, forKey: .tnLconW) ?? d.tnLconW
        cwpLm = try c.decodeIfPresent(Float.self, forKey: .cwpLm) ?? d.cwpLm
        rsSa = try c.decodeIfPresent(Float.self, forKey: .rsSa) ?? d.rsSa
        rsRw = try c.decodeIfPresent(Float.self, forKey: .rsRw) ?? d.rsRw
        rsBw = try c.decodeIfPresent(Float.self, forKey: .rsBw) ?? d.rsBw
        ptLml = try c.decodeIfPresent(Float.self, forKey: .ptLml) ?? d.ptLml
        ptLmlR = try c.decodeIfPresent(Float.self, forKey: .ptLmlR) ?? d.ptLmlR
        ptLmlG = try c.decodeIfPresent(Float.self, forKey: .ptLmlG) ?? d.ptLmlG
        ptLmlB = try c.decodeIfPresent(Float.self, forKey: .ptLmlB) ?? d.ptLmlB
        ptLmh = try c.decodeIfPresent(Float.self, forKey: .ptLmh) ?? d.ptLmh
        ptLmhR = try c.decodeIfPresent(Float.self, forKey: .ptLmhR) ?? d.ptLmhR
        ptLmhB = try c.decodeIfPresent(Float.self, forKey: .ptLmhB) ?? d.ptLmhB
        ptlC = try c.decodeIfPresent(Float.self, forKey: .ptlC) ?? d.ptlC
        ptlM = try c.decodeIfPresent(Float.self, forKey: .ptlM) ?? d.ptlM
        ptlY = try c.decodeIfPresent(Float.self, forKey: .ptlY) ?? d.ptlY
        ptmLow = try c.decodeIfPresent(Float.self, forKey: .ptmLow) ?? d.ptmLow
        ptmLowRng = try c.decodeIfPresent(Float.self, forKey: .ptmLowRng) ?? d.ptmLowRng
        ptmLowSt = try c.decodeIfPresent(Float.self, forKey: .ptmLowSt) ?? d.ptmLowSt
        ptmHigh = try c.decodeIfPresent(Float.self, forKey: .ptmHigh) ?? d.ptmHigh
        ptmHighRng = try c.decodeIfPresent(Float.self, forKey: .ptmHighRng) ?? d.ptmHighRng
        ptmHighSt = try c.decodeIfPresent(Float.self, forKey: .ptmHighSt) ?? d.ptmHighSt
        brl = try c.decodeIfPresent(Float.self, forKey: .brl) ?? d.brl
        brlR = try c.decodeIfPresent(Float.self, forKey: .brlR) ?? d.brlR
        brlG = try c.decodeIfPresent(Float.self, forKey: .brlG) ?? d.brlG
        brlB = try c.decodeIfPresent(Float.self, forKey: .brlB) ?? d.brlB
        brlRng = try c.decodeIfPresent(Float.self, forKey: .brlRng) ?? d.brlRng
        brlSt = try c.decodeIfPresent(Float.self, forKey: .brlSt) ?? d.brlSt
        brlp = try c.decodeIfPresent(Float.self, forKey: .brlp) ?? d.brlp
        brlpR = try c.decodeIfPresent(Float.self, forKey: .brlpR) ?? d.brlpR
        brlpG = try c.decodeIfPresent(Float.self, forKey: .brlpG) ?? d.brlpG
        brlpB = try c.decodeIfPresent(Float.self, forKey: .brlpB) ?? d.brlpB
        hcR = try c.decodeIfPresent(Float.self, forKey: .hcR) ?? d.hcR
        hcRRng = try c.decodeIfPresent(Float.self, forKey: .hcRRng) ?? d.hcRRng
        hsR = try c.decodeIfPresent(Float.self, forKey: .hsR) ?? d.hsR
        hsRRng = try c.decodeIfPresent(Float.self, forKey: .hsRRng) ?? d.hsRRng
        hsG = try c.decodeIfPresent(Float.self, forKey: .hsG) ?? d.hsG
        hsGRng = try c.decodeIfPresent(Float.self, forKey: .hsGRng) ?? d.hsGRng
        hsB = try c.decodeIfPresent(Float.self, forKey: .hsB) ?? d.hsB
        hsBRng = try c.decodeIfPresent(Float.self, forKey: .hsBRng) ?? d.hsBRng
        hsC = try c.decodeIfPresent(Float.self, forKey: .hsC) ?? d.hsC
        hsCRng = try c.decodeIfPresent(Float.self, forKey: .hsCRng) ?? d.hsCRng
        hsM = try c.decodeIfPresent(Float.self, forKey: .hsM) ?? d.hsM
        hsMRng = try c.decodeIfPresent(Float.self, forKey: .hsMRng) ?? d.hsMRng
        hsY = try c.decodeIfPresent(Float.self, forKey: .hsY) ?? d.hsY
        hsYRng = try c.decodeIfPresent(Float.self, forKey: .hsYRng) ?? d.hsYRng
    }
}

// MARK: - DrtRecord (the 12 top-level fields + the nested parameter group)

/// The document-level Display Transform record (sidecar v6
/// `displayTransform`, OQ-2-A). Defaults = the Alcedo hpp `DrtPayload`
/// (:101-115): OpenDRT / Rec709 / Gamma2.2 / peak 100 / standard /
/// use_look_preset ×2.
///
/// HASH (KD-1): `stableHash()` digests the canonical JSON bytes
/// (`.sortedKeys`, L013 — FNV-1a over bytes, never Swift `Hasher`). The
/// hash enters RENDER cache identity (set-fields-move — the record changes
/// → the render changes), NOT the rawOverrides-style hash isolation.
public struct DrtRecord: Codable, Hashable, Sendable {
    public var method: DrtMethod
    public var encodingSpace: DrtEncodingSpace
    public var encodingEotf: DrtEotf
    public var limitingSpace: DrtLimitingSpace
    /// Peak display luminance in nits. Producer range [100, 1000] (the dctl
    /// slider bounds); the Core-layer pure functions do NOT clamp — the P3
    /// panel/consumer owns validation (KD-2 peak-semantics note).
    public var peakLuminance: Float
    public var lookPreset: String
    public var tonescalePreset: String
    public var creativeWhite: String
    public var creativeWhiteLimit: Float
    public var displayGreyLuminance: Float
    public var hdrGreyBoost: Float
    public var hdrPurity: Float
    /// The editor-owned OpenDRT parameter group (serialized whole).
    public var parameters: OpenDrtDetailedParams

    /// Preset-name constants (the dctl combo spellings; `use_look_preset`
    /// means "follow the look preset" for both tonescale and creative white).
    public enum PresetNames {
        public static let standard = "standard"
        public static let useLookPreset = "use_look_preset"
    }

    public init() {
        method = .opendrt
        encodingSpace = .rec709
        encodingEotf = .gamma22
        limitingSpace = .rec709
        peakLuminance = 100.0
        lookPreset = PresetNames.standard
        tonescalePreset = PresetNames.useLookPreset
        creativeWhite = PresetNames.useLookPreset
        creativeWhiteLimit = 0.25
        displayGreyLuminance = 10.0
        hdrGreyBoost = 0.13
        hdrPurity = 0.5
        parameters = OpenDrtDetailedParams()
    }

    private enum CodingKeys: String, CodingKey {
        case method
        case encodingSpace = "encoding_space"
        case encodingEotf = "encoding_eotf"
        case limitingSpace = "limiting_space"
        case peakLuminance = "peak_luminance"
        case lookPreset = "look_preset"
        case tonescalePreset = "tonescale_preset"
        case creativeWhite = "creative_white"
        case creativeWhiteLimit = "creative_white_limit"
        case displayGreyLuminance = "display_grey_luminance"
        case hdrGreyBoost = "hdr_grey_boost"
        case hdrPurity = "hdr_purity"
        case parameters
    }

    /// Tolerant decode (per-field decodeIfPresent with the hpp default —
    /// the same posture as `OpenDrtDetailedParams`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        method = try c.decodeIfPresent(DrtMethod.self, forKey: .method) ?? d.method
        encodingSpace = try c.decodeIfPresent(DrtEncodingSpace.self, forKey: .encodingSpace) ?? d.encodingSpace
        encodingEotf = try c.decodeIfPresent(DrtEotf.self, forKey: .encodingEotf) ?? d.encodingEotf
        limitingSpace = try c.decodeIfPresent(DrtLimitingSpace.self, forKey: .limitingSpace) ?? d.limitingSpace
        peakLuminance = try c.decodeIfPresent(Float.self, forKey: .peakLuminance) ?? d.peakLuminance
        lookPreset = try c.decodeIfPresent(String.self, forKey: .lookPreset) ?? d.lookPreset
        tonescalePreset = try c.decodeIfPresent(String.self, forKey: .tonescalePreset) ?? d.tonescalePreset
        creativeWhite = try c.decodeIfPresent(String.self, forKey: .creativeWhite) ?? d.creativeWhite
        creativeWhiteLimit = try c.decodeIfPresent(Float.self, forKey: .creativeWhiteLimit) ?? d.creativeWhiteLimit
        displayGreyLuminance = try c.decodeIfPresent(Float.self, forKey: .displayGreyLuminance) ?? d.displayGreyLuminance
        hdrGreyBoost = try c.decodeIfPresent(Float.self, forKey: .hdrGreyBoost) ?? d.hdrGreyBoost
        hdrPurity = try c.decodeIfPresent(Float.self, forKey: .hdrPurity) ?? d.hdrPurity
        parameters = try c.decodeIfPresent(OpenDrtDetailedParams.self, forKey: .parameters) ?? d.parameters
    }

    /// FNV-1a over the canonical JSON bytes (`.sortedKeys`, L013). The
    /// rendering-cache identity for the DRT tail (KD-6: folded into the
    /// tail plane's upstreamHash; EOTF switches flip this hash and re-run
    /// only the tail).
    public func stableHash() -> UInt64 {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else {
            // Codable over plain data cannot fail in practice; the fallback
            // keeps the function total without a throws surface.
            return 0
        }
        return StableHash.hash(data)
    }
}

// MARK: - Linkage table + HDR judgment (the single-source knowledge)

/// The space→legal-EOTF table (FEATURE-MAP §5, row-for-row; D-M2-6-CONTEXT-5
/// — the Core single source; the UI snaps to the first legal value on a
/// space switch). Every space has a non-empty legal set; `linear` and
/// `gamma18` appear in NO set (the model layer keeps them persistable, the
/// UI never offers them).
public func legalEOTFs(for space: DrtEncodingSpace) -> [DrtEotf] {
    // M4-1-01 (KD-8): the srgbPiecewise rows join the SDR-power display
    // spaces — the order IS the KD-9 fallback chain (the UI snap order on
    // a space switch). The HDR族 and the p3d60/p3dci/xyz single-value sets
    // are untouched (the accept-set mirror).
    switch space {
    case .rec709: return [.srgbPiecewise, .gamma22, .bt1886]
    case .p3d65: return [.gamma22, .st2084, .srgbPiecewise]
    case .p3d60, .p3dci, .xyz: return [.gamma26]
    case .rec2020: return [.st2084, .hlg]
    }
}

/// The HDR judgment (OQ-6-A; Alcedo `IsHdrExportEncoding` semantics — the
/// encoding EOTF alone decides, nothing else is consulted).
public func isHdrEncoding(_ eotf: DrtEotf) -> Bool {
    switch eotf {
    case .st2084, .hlg: return true
    case .linear, .gamma26, .bt1886, .gamma22, .gamma18, .srgbPiecewise: return false
    }
}

/// The persistence-pristine judgment (KD-4: NOT a render-identity claim —
/// the default parameter point still tone-maps; this only says "the user
/// never touched DRT", driving sidecar key-absence and UI state).
public func isDrtRecordDefault(_ r: DrtRecord) -> Bool {
    r == DrtRecord()
}

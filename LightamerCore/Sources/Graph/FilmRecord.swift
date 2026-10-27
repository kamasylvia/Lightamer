import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// FilmRecord — the film-simulation document-level parameter record
// (Plan M3-3-01 T1, KD-1: DrtRecord.swift is the structural template —
// the same tolerant-decode / stableHash / pristine-gate machinery, a
// different payload domain).
//
// SCHEMA PROVENANCE (KD-1): the field set models a dichroic enlarger
// print session (one enlarger × one negative × one paper per document —
// the document-level singleton judgment, M3-2 D-M3-2-1). Domain facts
// (CC-point filter domain 0-100, C fixed at its neutral 0, manual Y/M
// shifts always present, density-domain strength mixing) follow the
// SpektraLab printing parameter semantics (printing.cpp/params.hpp —
// schema facts read-only; RESEARCH-NOTES §1.3 / §4.1). The record shape,
// key spellings and defaults are Lightamer's own (no upstream payload is
// mirrored field-for-field — unlike DrtRecord there is no hpp schema to
// copy; the spectrum-replay face of the upstream engine is architecturally
// unreachable here, M3-2 D-M3-2-2).
//
// The film/paper stock ids are OPEN STRINGS (the asset set is extensible —
// KD-1: no enum; illegal ids degrade typed at the store/loader layer,
// KD-3/M3-3-01-DECISIONS), NOT enum cases.
//
// LICENSING: schema/model facts only — no GPL code and no CC BY-SA asset
// bytes are embedded here; the profile DATA lives in
// Resources/FilmProfiles/ under its own license (NOTICE in that directory).
// ─────────────────────────────────────────────────────────────────────────────

/// The document-level film-simulation record (sidecar v9 `filmRecord`,
/// M3-3-01 KD-1/KD-6). One print session per document: film stock +
/// paper stock + the enlarger filter-pack adjustments + effect strength.
/// Placement (scene-positioning) parameters do NOT live here — they are
/// the `filmPlacement` grade op's domain (M3-2 D-M3-2-1 / OQ-M3-2-7).
///
/// Defaults = the pristine session: empty stock ids (no materials bound)
/// and zeroed adjustments. A document with the default record is
/// indistinguishable from one without the key (KD-6 pristine gate — the
/// default record is never written to the sidecar and never enters a
/// carrier).
///
/// HASH (KD-1): `stableHash()` digests the canonical JSON bytes
/// (`.sortedKeys`, L013 — FNV-1a over bytes, never Swift `Hasher`). The
/// hash enters the film sub-run plane identity (M3-3-02 wiring) and the
/// historyHash fold tail (KD-6) — set-fields-move, same posture as
/// DrtRecord.
public struct FilmRecord: Codable, Hashable, Sendable {
    /// Profile `info.stock` id of the negative ("" = unbound — part of
    /// the pristine default; the loader/store resolve the id against the
    /// indexed asset set).
    public var filmStock: String
    /// Profile `info.stock` id of the paper ("" = unbound).
    public var paperStock: String
    /// Manual Yellow filter offset, CC points 0-100 (the Y dial's
    /// user shift on top of the solved neutral pack; FSIM-01b keeps the
    /// manual pair ALWAYS present — M3-2 OQ-M3-2-2 ③). Producer range
    /// [0, 100]; the Core pure functions do NOT clamp — the panel/consumer
    /// owns validation (DrtRecord.peakLuminance same split).
    public var yFilterShift: Float
    /// Manual Magenta filter offset, CC points 0-100 (see yFilterShift).
    public var mFilterShift: Float
    /// The optional content-adaptive channel-shift arm (default false =
    /// SpektraLab-aligned behavior: bake-time neutral pack + exposure
    /// normalization only — M3-2 OQ-M3-2-2 ③; the runtime statistical leg
    /// is M3-3-02).
    public var contentAdaptiveShift: Bool
    /// Effect strength, RFC-025 semantics: `out = in + k·(film − in)` in
    /// the density domain, `1.0` = as-modelled (default). Producer range
    /// [0, 1]; NOT clamped here (panel/consumer owns validation).
    public var strength: Float
    /// Manual print-exposure trim in EV on top of the automatic
    /// normalization arm (default 0 = no trim; the SpektraLab Post-Dev
    /// exposure's material-domain seat).
    public var exposureEv: Float
    /// M9-2 T3: the camera (taking) filter — a `camera_filters.json` key
    /// ("w8"..."w58"), nil/"" = none. The filter multiplies the build-time
    /// sensW input (X-M92-1 — the film leg is the input-side seat). OPEN
    /// STRING by the same KD-1 judgment as the stock ids: illegal keys
    /// degrade typed at the CameraFilterTable layer, not here.
    public var cameraFilter: String?
    /// M9-2 T2: the paper CONTRAST GRADE — `"00"..."5"` verbatim (MAJ-1:
    /// the seven upstream grades include BOTH "00" and "0", so Int
    /// encodings are ambiguous; the key maps 1:1 onto paper_grades.json).
    /// nil = the solver's own neutral pack (zero-drift default).
    public var paperGrade: String?

    /// Preset-name placeholder constants (KD-1). Deliberately EMPTY for
    /// this plan: no named film-look presets exist yet — M3-3-03 owns the
    /// preset registration face and appends its spellings here so the key
    /// vocabulary keeps a single home (DrtRecord.PresetNames same shape).
    public enum PresetNames {
    }

    public init() {
        filmStock = ""
        paperStock = ""
        yFilterShift = 0.0
        mFilterShift = 0.0
        contentAdaptiveShift = false
        strength = 1.0
        exposureEv = 0.0
        cameraFilter = nil
        paperGrade = nil
    }

    private enum CodingKeys: String, CodingKey {
        case filmStock = "film_stock"
        case paperStock = "paper_stock"
        case yFilterShift = "y_filter_shift"
        case mFilterShift = "m_filter_shift"
        case contentAdaptiveShift = "content_adaptive_shift"
        case strength
        case exposureEv = "exposure_ev"
        // M9-2 (MIN-6: the three faces moved in ONE batch — a key missing
        // here compiles fine but decodes nil / encodes nothing / stays out
        // of the hash: one omission, three silent failures).
        case cameraFilter = "camera_filter"
        case paperGrade = "paper_grade"
    }

    /// Tolerant decode: every field decodeIfPresent with the pristine
    /// default as the fallback (a partial/hand-edited record still yields
    /// a valid record — the same defensive posture the sidecar readers
    /// and DrtRecord carry).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        filmStock = try c.decodeIfPresent(String.self, forKey: .filmStock) ?? d.filmStock
        paperStock = try c.decodeIfPresent(String.self, forKey: .paperStock) ?? d.paperStock
        yFilterShift = try c.decodeIfPresent(Float.self, forKey: .yFilterShift) ?? d.yFilterShift
        mFilterShift = try c.decodeIfPresent(Float.self, forKey: .mFilterShift) ?? d.mFilterShift
        contentAdaptiveShift = try c.decodeIfPresent(
            Bool.self, forKey: .contentAdaptiveShift) ?? d.contentAdaptiveShift
        strength = try c.decodeIfPresent(Float.self, forKey: .strength) ?? d.strength
        exposureEv = try c.decodeIfPresent(Float.self, forKey: .exposureEv) ?? d.exposureEv
        cameraFilter = try c.decodeIfPresent(String.self, forKey: .cameraFilter) ?? d.cameraFilter
        paperGrade = try c.decodeIfPresent(String.self, forKey: .paperGrade) ?? d.paperGrade
    }

    /// FNV-1a over the canonical JSON bytes (`.sortedKeys`, L013). The
    /// film sub-run plane identity term (M3-3-02) and the historyHash
    /// fold tail (KD-6).
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

/// The persistence-pristine judgment (KD-1; `isDrtRecordDefault` same
/// shape): the record equals the pristine default (unbound stocks, zeroed
/// adjustments). NOT a render-identity claim — a default-carrier document
/// renders as the legacy path by the M3-3-02 wiring, but this predicate
/// only says "the user never touched the film session", driving sidecar
/// key-absence and UI state.
public func isFilmRecordDefault(_ r: FilmRecord) -> Bool {
    r == FilmRecord()
}

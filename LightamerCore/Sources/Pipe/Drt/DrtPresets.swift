import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// DrtPresets — the preset triple as named snapshots (Plan M2-6-1 T5, KD-7 /
// OQ-1-A): Look ×7 + Tonescale ×14 (USE LOOK PRESET + 13 — the m3 correction:
// REQUIREMENTS' "15" was a miscount; the dctl enum is tsprst0..13) +
// Creative White ×6 (+ use-look). Numbers are TRANSCRIBED FACTS from the
// jedypod/open-display-transform v1.1.0 dctl (GPLv3, read-only) — the value
// tables carry no creative expression and no code was copied (NOTICE at the
// repo root records provenance). custom is a DERIVED display value, never
// persisted (OQ-2-A).
//
// ENABLE→VALUE PROJECTION (DECISIONS §D6): the dctl carries explicit enable
// bits; Lightamer's 53-param model is value-domain only. Every dctl
// enable=0 state maps to the neutral value 0 — including the tsprst11 trap
// (ACES 2.0 tonescale sets tn_hcon = 1.0 / tn_lcon = 1.0 WITH enable = 0,
// dctl :818: behaviorally disabled, so our table stores 0).
//
// SPOT-CHECK (KD-7, executed 2026-10-01, recorded in DECISIONS §D7): the
// transcribed tables were compared against the Alcedo
// tests/resources/expected_parameters/drt/cuda_opendrt_*.bin parameter
// dumps (GPL assets, read-only, never shipped): standard + arriba 53/53
// float32-exact; the 14 derived tonescale constants match the KD-3
// derivations to float32 rounding; the PQ row's ts_dsc differs by the
// documented peak-normalization fold (mathematically identical placement).
// ─────────────────────────────────────────────────────────────────────────────

/// The Look preset — a full 53-parameter snapshot + the look's creative
/// white (the dctl look branches set `cwp`; our record resolves
/// `use_look_preset` through `resolvedCreativeWhiteOrdinal`).
public enum DrtLookPreset: String, Codable, Sendable, CaseIterable {
    case standard
    case arriba
    case sylvan
    case colorful
    case aery
    case dystopic
    case umbra

    /// The look's creative-white ordinal (dctl cwp: 0 D93 / 1 D75 / 2 D65 /
    /// 3 D60 / 4 D55 / 5 D50) — what `use_look_preset` resolves to.
    public var creativeWhiteOrdinal: Int {
        switch self {
        case .standard, .arriba, .sylvan, .colorful: return 2  // D65
        case .aery: return 1                                   // D75
        case .dystopic: return 3                               // D60
        case .umbra: return 5                                  // D50
        }
    }

    public var snapshot: OpenDrtDetailedParams {
        switch self {
        case .standard: return DrtPresets.Snapshots.makeStandard()
        case .arriba: return DrtPresets.Snapshots.makeArriba()
        case .sylvan: return DrtPresets.Snapshots.makeSylvan()
        case .colorful: return DrtPresets.Snapshots.makeColorful()
        case .aery: return DrtPresets.Snapshots.makeAery()
        case .dystopic: return DrtPresets.Snapshots.makeDystopic()
        case .umbra: return DrtPresets.Snapshots.makeUmbra()
        }
    }
}

/// The Tonescale preset — a tonescale-subset override (the tn* fields only;
/// the look owns everything else). `useLookPreset` = no override.
public enum DrtTonescalePreset: String, Codable, Sendable, CaseIterable {
    case useLookPreset = "use_look_preset"
    case lowContrast = "low_contrast"
    case mediumContrast = "medium_contrast"
    case highContrast = "high_contrast"
    case arribaTonescale = "arriba_tonescale"
    case sylvanTonescale = "sylvan_tonescale"
    case colorfulTonescale = "colorful_tonescale"
    case aeryTonescale = "aery_tonescale"
    case dystopicTonescale = "dystopic_tonescale"
    case umbraTonescale = "umbra_tonescale"
    case aces1x = "aces_1_x"
    case aces20 = "aces_2_0"
    case marvelousTonscape = "marvelous_tonscape"
    case dagrinchiTonegroan = "dagrinchi_tonegroan"

    /// The tn-subset override (enable→value projection — see the header).
    /// Returns nil for `useLookPreset`.
    public var tonescaleOverride: (tnCon: Float, tnSh: Float, tnToe: Float,
                                   tnOff: Float, tnHcon: Float, tnHconPv: Float,
                                   tnHconSt: Float, tnLcon: Float, tnLconW: Float)? {
        switch self {
        case .useLookPreset:
            return nil
        case .lowContrast:
            return (1.4, 0.5, 0.003, 0.005, 0, 1.0, 4.0, 0, 0.5)
        case .mediumContrast:
            return (1.66, 0.5, 0.003, 0.005, 0, 1.0, 4.0, 0, 0.5)
        case .highContrast:
            return (1.4, 0.5, 0.003, 0.005, 0, 1.0, 4.0, 1.0, 0.5)
        case .arribaTonescale:
            return (1.05, 0.5, 0.1, 0.01, 0, 1.0, 4.0, 1.5, 0.2)
        case .sylvanTonescale:
            return (1.6, 0.5, 0.01, 0.01, 0, 1.0, 4.0, 0.25, 0.75)
        case .colorfulTonescale:
            return (1.5, 0.5, 0.003, 0.003, 0, 1.0, 4.0, 0.4, 0.5)
        case .aeryTonescale:
            return (1.15, 0.5, 0.04, 0.006, 0, 0.0, 0.5, 0.5, 2.0)
        case .dystopicTonescale:
            return (1.6, 0.5, 0.01, 0.008, 0.25, 0.0, 1.0, 1.0, 0.75)
        case .umbraTonescale:
            return (1.8, 0.5, 0.001, 0.015, 0, 1.0, 4.0, 1.0, 1.0)
        case .aces1x:
            return (1.0, 0.35, 0.02, 0.0, 0.55, 0.0, 2.0, 1.13, 1.0)
        case .aces20:
            // dctl :818 — the enable=0-with-value trap: hcon/lcon are 1.0 in
            // the dctl text but DISABLED; our projection stores 0.
            return (1.15, 0.5, 0.04, 0.0, 0, 1.0, 1.0, 0, 0.6)
        case .marvelousTonscape:
            return (1.5, 0.5, 0.003, 0.01, 0.25, 0.0, 4.0, 1.0, 1.0)
        case .dagrinchiTonegroan:
            return (1.2, 0.5, 0.02, 0.0, 0, 1.0, 1.0, 0, 0.6)
        }
    }
}

/// The Creative White preset (dctl `_cwp` combo: use-look + the six CIE
/// illuminants; FEATURE-MAP's "6" counts the named whites).
public enum DrtCreativeWhite: String, Codable, Sendable, CaseIterable {
    case useLookPreset = "use_look_preset"
    case d93
    case d75
    case d65
    case d60
    case d55
    case d50

    /// The dctl cwp ordinal (0 D93 / 1 D75 / 2 D65 / 3 D60 / 4 D55 / 5 D50).
    public var ordinal: Int? {
        switch self {
        case .useLookPreset: return nil
        case .d93: return 0
        case .d75: return 1
        case .d65: return 2
        case .d60: return 3
        case .d55: return 4
        case .d50: return 5
        }
    }
}

public enum DrtPresets {

    /// The atomic preset application (the P3 panel's single discrete commit
    /// consumes this): look snapshot wholesale, then the tonescale override,
    /// then the creative white. All three decisions land in ONE record.
    public static func applyPreset(
        record: DrtRecord, look: DrtLookPreset, tonescale: DrtTonescalePreset,
        white: DrtCreativeWhite
    ) -> DrtRecord {
        var out = record
        out.lookPreset = look.rawValue
        out.tonescalePreset = tonescale.rawValue
        out.creativeWhite = white.rawValue
        out.parameters = look.snapshot
        if let o = tonescale.tonescaleOverride {
            out.parameters.tnCon = o.tnCon
            out.parameters.tnSh = o.tnSh
            out.parameters.tnToe = o.tnToe
            out.parameters.tnOff = o.tnOff
            out.parameters.tnHcon = o.tnHcon
            out.parameters.tnHconPv = o.tnHconPv
            out.parameters.tnHconSt = o.tnHconSt
            out.parameters.tnLcon = o.tnLcon
            out.parameters.tnLconW = o.tnLconW
        }
        return out
    }

    /// The derived custom judgment (OQ-2-A): the 53 params match NO built-in
    /// look snapshot → custom. A pure display value — nothing persists.
    public static func isCustomLook(_ record: DrtRecord) -> Bool {
        !DrtLookPreset.allCases.contains { record.parameters == $0.snapshot }
    }

    /// The resolved creative-white ordinal the record's DRT math consumes
    /// ("use_look_preset" rides the look's white; an explicit white wins —
    /// the dctl `_cwp!=0` override path).
    public static func resolvedCreativeWhiteOrdinal(_ record: DrtRecord) -> Int {
        if let explicit = DrtCreativeWhite(rawValue: record.creativeWhite)?.ordinal {
            return explicit
        }
        if let look = DrtLookPreset(rawValue: record.lookPreset) {
            return look.creativeWhiteOrdinal
        }
        return 2  // D65 fallback (the standard look's white)
    }

    /// The look snapshots (namespaced to keep the enum body readable).
    enum Snapshots {
        /// dctl :758 — the Standard look branch (numeric facts).
        static func makeStandard() -> OpenDrtDetailedParams {
            var p = OpenDrtDetailedParams()
            p.tnCon = 1.66
            p.tnSh = 0.5
            p.tnToe = 0.003
            p.tnOff = 0.005
            p.tnHcon = 0.0
            p.tnHconPv = 1.0
            p.tnHconSt = 4.0
            p.tnLcon = 0.0
            p.tnLconW = 0.5
            p.cwpLm = 0.25
            p.rsSa = 0.35
            p.rsRw = 0.25
            p.rsBw = 0.55
            p.ptLml = 0.25
            p.ptLmlR = 0.5
            p.ptLmlG = 0.0
            p.ptLmlB = 0.1
            p.ptLmh = 0.25
            p.ptLmhR = 0.5
            p.ptLmhB = 0.0
            p.ptlC = 0.06
            p.ptlM = 0.08
            p.ptlY = 0.06
            p.ptmLow = 0.4
            p.ptmLowRng = 0.25
            p.ptmLowSt = 0.5
            p.ptmHigh = -0.8
            p.ptmHighRng = 0.35
            p.ptmHighSt = 0.4
            p.brl = 0.0
            p.brlR = -2.5
            p.brlG = -1.5
            p.brlB = -1.5
            p.brlRng = 0.5
            p.brlSt = 0.35
            p.brlp = -0.5
            p.brlpR = -1.25
            p.brlpG = -1.25
            p.brlpB = -0.25
            p.hcR = 1.0
            p.hcRRng = 0.3
            p.hsR = 0.6
            p.hsRRng = 0.6
            p.hsG = 0.35
            p.hsGRng = 1.0
            p.hsB = 0.66
            p.hsBRng = 1.0
            p.hsC = 0.25
            p.hsCRng = 1.0
            p.hsM = 0.0
            p.hsMRng = 1.0
            p.hsY = 0.0
            p.hsYRng = 1.0
            return p
        }

        /// dctl :761 — the Arriba look branch (numeric facts).
        static func makeArriba() -> OpenDrtDetailedParams {
            var p = OpenDrtDetailedParams()
            p.tnCon = 1.05
            p.tnSh = 0.5
            p.tnToe = 0.1
            p.tnOff = 0.01
            p.tnHcon = 0.0
            p.tnHconPv = 1.0
            p.tnHconSt = 4.0
            p.tnLcon = 1.5
            p.tnLconW = 0.2
            p.cwpLm = 0.25
            p.rsSa = 0.35
            p.rsRw = 0.25
            p.rsBw = 0.55
            p.ptLml = 0.25
            p.ptLmlR = 0.45
            p.ptLmlG = 0.0
            p.ptLmlB = 0.1
            p.ptLmh = 0.25
            p.ptLmhR = 0.25
            p.ptLmhB = 0.0
            p.ptlC = 0.06
            p.ptlM = 0.08
            p.ptlY = 0.06
            p.ptmLow = 1.0
            p.ptmLowRng = 0.4
            p.ptmLowSt = 0.5
            p.ptmHigh = -0.8
            p.ptmHighRng = 0.66
            p.ptmHighSt = 0.6
            p.brl = 0.0
            p.brlR = -2.5
            p.brlG = -1.5
            p.brlB = -1.5
            p.brlRng = 0.5
            p.brlSt = 0.35
            p.brlp = 0.0
            p.brlpR = -1.7
            p.brlpG = -2.0
            p.brlpB = -0.5
            p.hcR = 1.0
            p.hcRRng = 0.3
            p.hsR = 0.6
            p.hsRRng = 0.8
            p.hsG = 0.35
            p.hsGRng = 1.0
            p.hsB = 0.66
            p.hsBRng = 1.0
            p.hsC = 0.15
            p.hsCRng = 1.0
            p.hsM = 0.0
            p.hsMRng = 1.0
            p.hsY = 0.0
            p.hsYRng = 1.0
            return p
        }

        /// dctl :764 — the Sylvan look branch (numeric facts).
        static func makeSylvan() -> OpenDrtDetailedParams {
            var p = OpenDrtDetailedParams()
            p.tnCon = 1.6
            p.tnSh = 0.5
            p.tnToe = 0.01
            p.tnOff = 0.01
            p.tnHcon = 0.0
            p.tnHconPv = 1.0
            p.tnHconSt = 4.0
            p.tnLcon = 0.25
            p.tnLconW = 0.75
            p.cwpLm = 0.25
            p.rsSa = 0.25
            p.rsRw = 0.25
            p.rsBw = 0.55
            p.ptLml = 0.15
            p.ptLmlR = 0.5
            p.ptLmlG = 0.15
            p.ptLmlB = 0.1
            p.ptLmh = 0.25
            p.ptLmhR = 0.15
            p.ptLmhB = 0.15
            p.ptlC = 0.05
            p.ptlM = 0.08
            p.ptlY = 0.05
            p.ptmLow = 0.5
            p.ptmLowRng = 0.5
            p.ptmLowSt = 0.5
            p.ptmHigh = -0.8
            p.ptmHighRng = 0.5
            p.ptmHighSt = 0.5
            p.brl = -1.0
            p.brlR = -2.0
            p.brlG = -2.0
            p.brlB = 0.0
            p.brlRng = 0.25
            p.brlSt = 0.25
            p.brlp = -1.0
            p.brlpR = -0.5
            p.brlpG = -0.25
            p.brlpB = -0.25
            p.hcR = 1.0
            p.hcRRng = 0.4
            p.hsR = 0.6
            p.hsRRng = 1.15
            p.hsG = 0.8
            p.hsGRng = 1.25
            p.hsB = 0.6
            p.hsBRng = 1.0
            p.hsC = 0.25
            p.hsCRng = 0.25
            p.hsM = 0.25
            p.hsMRng = 0.5
            p.hsY = 0.35
            p.hsYRng = 0.5
            return p
        }

        /// dctl :767 — the Colorful look branch (numeric facts).
        static func makeColorful() -> OpenDrtDetailedParams {
            var p = OpenDrtDetailedParams()
            p.tnCon = 1.5
            p.tnSh = 0.5
            p.tnToe = 0.003
            p.tnOff = 0.003
            p.tnHcon = 0.0
            p.tnHconPv = 1.0
            p.tnHconSt = 4.0
            p.tnLcon = 0.4
            p.tnLconW = 0.5
            p.cwpLm = 0.25
            p.rsSa = 0.35
            p.rsRw = 0.25
            p.rsBw = 0.55
            p.ptLml = 0.5
            p.ptLmlR = 1.0
            p.ptLmlG = 0.0
            p.ptLmlB = 0.5
            p.ptLmh = 0.15
            p.ptLmhR = 0.15
            p.ptLmhB = 0.15
            p.ptlC = 0.05
            p.ptlM = 0.06
            p.ptlY = 0.05
            p.ptmLow = 0.8
            p.ptmLowRng = 0.5
            p.ptmLowSt = 0.4
            p.ptmHigh = -0.8
            p.ptmHighRng = 0.4
            p.ptmHighSt = 0.4
            p.brl = 0.0
            p.brlR = -1.25
            p.brlG = -1.25
            p.brlB = -0.25
            p.brlRng = 0.3
            p.brlSt = 0.5
            p.brlp = -0.5
            p.brlpR = -1.25
            p.brlpG = -1.25
            p.brlpB = -0.5
            p.hcR = 1.0
            p.hcRRng = 0.4
            p.hsR = 0.5
            p.hsRRng = 0.8
            p.hsG = 0.35
            p.hsGRng = 1.0
            p.hsB = 0.5
            p.hsBRng = 1.0
            p.hsC = 0.25
            p.hsCRng = 1.0
            p.hsM = 0.0
            p.hsMRng = 1.0
            p.hsY = 0.25
            p.hsYRng = 1.0
            return p
        }

        /// dctl :770 — the Aery look branch (numeric facts).
        static func makeAery() -> OpenDrtDetailedParams {
            var p = OpenDrtDetailedParams()
            p.tnCon = 1.15
            p.tnSh = 0.5
            p.tnToe = 0.04
            p.tnOff = 0.006
            p.tnHcon = 0.0
            p.tnHconPv = 0.0
            p.tnHconSt = 0.5
            p.tnLcon = 0.5
            p.tnLconW = 2.0
            p.cwpLm = 0.25
            p.rsSa = 0.25
            p.rsRw = 0.2
            p.rsBw = 0.5
            p.ptLml = 0.0
            p.ptLmlR = 0.5
            p.ptLmlG = 0.15
            p.ptLmlB = 0.1
            p.ptLmh = 0.0
            p.ptLmhR = 0.1
            p.ptLmhB = 0.0
            p.ptlC = 0.05
            p.ptlM = 0.08
            p.ptlY = 0.05
            p.ptmLow = 0.8
            p.ptmLowRng = 0.35
            p.ptmLowSt = 0.5
            p.ptmHigh = -0.9
            p.ptmHighRng = 0.5
            p.ptmHighSt = 0.3
            p.brl = -3.0
            p.brlR = 0.0
            p.brlG = 0.0
            p.brlB = 1.0
            p.brlRng = 0.8
            p.brlSt = 0.15
            p.brlp = -1.0
            p.brlpR = -1.0
            p.brlpG = -1.0
            p.brlpB = 0.0
            p.hcR = 0.5
            p.hcRRng = 0.25
            p.hsR = 0.6
            p.hsRRng = 1.0
            p.hsG = 0.35
            p.hsGRng = 2.0
            p.hsB = 0.5
            p.hsBRng = 1.5
            p.hsC = 0.35
            p.hsCRng = 1.0
            p.hsM = 0.25
            p.hsMRng = 1.0
            p.hsY = 0.35
            p.hsYRng = 0.5
            return p
        }

        /// dctl :773 — the Dystopic look branch (numeric facts).
        static func makeDystopic() -> OpenDrtDetailedParams {
            var p = OpenDrtDetailedParams()
            p.tnCon = 1.6
            p.tnSh = 0.5
            p.tnToe = 0.01
            p.tnOff = 0.008
            p.tnHcon = 0.25
            p.tnHconPv = 0.0
            p.tnHconSt = 1.0
            p.tnLcon = 1.0
            p.tnLconW = 0.75
            p.cwpLm = 0.25
            p.rsSa = 0.2
            p.rsRw = 0.25
            p.rsBw = 0.55
            p.ptLml = 0.15
            p.ptLmlR = 0.0
            p.ptLmlG = 0.0
            p.ptLmlB = 0.0
            p.ptLmh = 0.0
            p.ptLmhR = 0.0
            p.ptLmhB = 0.0
            p.ptlC = 0.05
            p.ptlM = 0.08
            p.ptlY = 0.05
            p.ptmLow = 0.25
            p.ptmLowRng = 0.25
            p.ptmLowSt = 0.8
            p.ptmHigh = -0.8
            p.ptmHighRng = 0.6
            p.ptmHighSt = 0.25
            p.brl = -2.0
            p.brlR = -2.0
            p.brlG = -2.0
            p.brlB = 0.0
            p.brlRng = 0.35
            p.brlSt = 0.35
            p.brlp = 0.0
            p.brlpR = -1.0
            p.brlpG = -1.0
            p.brlpB = -1.0
            p.hcR = 1.0
            p.hcRRng = 0.25
            p.hsR = 0.7
            p.hsRRng = 1.33
            p.hsG = 1.0
            p.hsGRng = 2.0
            p.hsB = 0.75
            p.hsBRng = 2.0
            p.hsC = 1.0
            p.hsCRng = 0.5
            p.hsM = 1.0
            p.hsMRng = 1.0
            p.hsY = 1.0
            p.hsYRng = 0.765
            return p
        }

        /// dctl :776 — the Umbra look branch (numeric facts).
        static func makeUmbra() -> OpenDrtDetailedParams {
            var p = OpenDrtDetailedParams()
            p.tnCon = 1.8
            p.tnSh = 0.5
            p.tnToe = 0.001
            p.tnOff = 0.015
            p.tnHcon = 0.0
            p.tnHconPv = 1.0
            p.tnHconSt = 4.0
            p.tnLcon = 1.0
            p.tnLconW = 1.0
            p.cwpLm = 0.25
            p.rsSa = 0.35
            p.rsRw = 0.25
            p.rsBw = 0.55
            p.ptLml = 0.0
            p.ptLmlR = 0.5
            p.ptLmlG = 0.0
            p.ptLmlB = 0.15
            p.ptLmh = 0.25
            p.ptLmhR = 0.25
            p.ptLmhB = 0.0
            p.ptlC = 0.05
            p.ptlM = 0.06
            p.ptlY = 0.05
            p.ptmLow = 0.4
            p.ptmLowRng = 0.35
            p.ptmLowSt = 0.66
            p.ptmHigh = -0.6
            p.ptmHighRng = 0.45
            p.ptmHighSt = 0.45
            p.brl = -2.0
            p.brlR = -4.5
            p.brlG = -3.0
            p.brlB = -4.0
            p.brlRng = 0.35
            p.brlSt = 0.3
            p.brlp = 0.0
            p.brlpR = -2.0
            p.brlpG = -1.0
            p.brlpB = -0.5
            p.hcR = 1.0
            p.hcRRng = 0.35
            p.hsR = 0.66
            p.hsRRng = 1.0
            p.hsG = 0.5
            p.hsGRng = 2.0
            p.hsB = 0.85
            p.hsBRng = 2.0
            p.hsC = 0.0
            p.hsCRng = 1.0
            p.hsM = 0.25
            p.hsMRng = 1.0
            p.hsY = 0.66
            p.hsYRng = 0.66
            return p
        }

    }
}

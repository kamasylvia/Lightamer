import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────
// LutEncodingCatalog (Plan M3-1-01 T1, M2GRADE-08 / KD-1) — the table-driven
// LUT authoring-encoding catalog: 17 rows (11 scene = 10 camera logs +
// linear working, 6 display), each `{id, referral, transfer, gamut,
// peakNits, displayName}`.
//
// PROVENANCE: the ROW SET and FIELD FORM mirror the upstream (Alcedo)
// `color_encoding_catalog` shape-for-shape (GPL-3.0 — table form only, zero
// numeric copies); every transfer curve's math lives in `LutTransferMath`
// (public standards) and every gamut matrix is COMPUTED here from the
// published primaries via the standard Bradford chromatic adaptation —
// no upstream matrix constants are transcribed.
//
// Gamut notes (manufacturer specs, checker M2): F-Gamut and N-Log have no
// independent primaries — both factory specs reuse BT.2020 primaries +
// white, so rows 7/9 reference the `rec2020` gamut directly (Apple Log's
// gamut likewise). No separate "gamma 2.4" row exists — BT.1886 IS the
// 2.4 family (the M2-6 EOTF terminal form, DECISIONS §D2). SDR display
// rows carry peak = 100 nits exactly (checker M3 — no `peak == 0`
// special case anywhere; PQ/HLG carry 1000).
//
// Adding a row = adding a `LutEncodingId` case + a table entry (the
// exhaustive switches in `LutTransferMath` break at compile time when a
// new transfer curve is introduced).
// ─────────────────────────────────────────────────────────────────────────

/// The catalog row id (the params-side spelling). Raw values are the
/// persisted form — NEVER rename (one-way params lock).
public enum LutEncodingId: String, Codable, Sendable, CaseIterable {
    case acescc
    case acescct
    case arriLogC4AWG4 = "arri_logc4_awg4"
    case arriLogC3AWG3 = "arri_logc3_awg3"
    case sonySLog3 = "sony_slog3"
    case canonCLog3 = "canon_clog3"
    case fujiFLog = "fuji_flog"
    case panasonicVLog = "panasonic_vlog"
    case nikonNLog = "nikon_nlog"
    case appleLog = "apple_log"
    // M9-4 T3 (X5/D-M9SP-3): the 10-row expansion — id spellings照上游
    // color_encoding_catalog.cpp at c740f7b (X5 case list is the
    // master).
    case sonySLog3SGamut3Cine = "sony_slog3_sgamut3cine"
    case fujiFLog2FGamut = "fujifilm_flog2_fgamut"
    case canonCLog2CinemaGamut = "canon_clog2_cinemagamut"
    case redLog3G10RWG = "red_log3g10_rwg"
    case blackmagicFilmGen5BMDWG = "blackmagic_film_gen5_bmdwg"
    case davinciIntermediateDWG = "davinci_intermediate_dwg"
    case djiDLogDGamut = "dji_dlog_dgamut"
    case p3D65Gamma26 = "p3d65_gamma26"
    case p3DCIGamma26 = "p3dci_gamma26"
    case rec2020BT1886 = "rec2020_bt1886"
    case linearRec2020 = "linear_rec2020"
    case rec709BT1886 = "rec709_bt1886"
    case rec709SRGB = "rec709_srgb"
    case rec709Gamma22 = "rec709_gamma22"
    case displayP3SRGB = "displayp3_srgb"
    case rec2100PQ1000 = "rec2100_pq1000"
    case rec2100HLG1000 = "rec2100_hlg1000"
}

/// scene = camera-native/working encodings (peak-free); display = display-
/// referred encodings mediated through 100-nit display light.
public enum LutEncodingReferral: String, Codable, Sendable {
    case scene
    case display
}

/// One catalog row (the KD-1 field form).
public struct LutEncoding: Equatable, Sendable {
    public let id: LutEncodingId
    public let referral: LutEncodingReferral
    public let transfer: LutTransferCurve
    /// The gamut id in `LutEncodingCatalog.gamuts`.
    public let gamutId: String
    /// 0 for scene rows; the SDR family carries 100, PQ/HLG 1000.
    public let peakNits: Double
    public let displayName: String
}

/// A color gamut: published primaries + white, with the matrices to/from
/// the working linear Rec2020 space COMPUTED at first touch via standard
/// Bradford chromatic adaptation (never hand-copied matrix constants).
public struct LutGamut: Sendable {
    public let id: String
    public let name: String
    /// The primaries' CIE xy chromaticities (R, G, B).
    public let primariesXY: (SIMD2<Double>, SIMD2<Double>, SIMD2<Double>)
    /// The white point's CIE xy.
    public let whiteXY: SIMD2<Double>
    /// gamut linear → working linear Rec2020.
    public let toRec2020: simd_double3x3
    /// working linear Rec2020 → gamut linear (the exact inverse).
    public let fromRec2020: simd_double3x3
}

public enum LutEncodingCatalog {

    /// The default (unannotated) pair = the working space itself, both
    /// ends — the byte-preserving fast path (OQ-1①).
    public static let defaultInputId = LutEncodingId.linearRec2020
    public static let defaultOutputId = LutEncodingId.linearRec2020

    /// D65 (the BT.2020/BT.709/P3-D65 reference white).
    public static let d65XY = SIMD2(0.3127, 0.3290)
    /// The ACES (AP0/AP1) white.
    public static let acesWhiteXY = SIMD2(0.32168, 0.33767)

    // MARK: - Gamuts (published primaries; matrices computed)

    /// xy → XYZ (Y = 1 normalization).
    static func xyToXYZ(_ xy: SIMD2<Double>) -> SIMD3<Double> {
        SIMD3(xy.x / xy.y, 1, (1 - xy.x - xy.y) / xy.y)
    }

    /// The RGB→XYZ matrix whose columns are the primaries' XYZ (rows X,Y,Z).
    static func rgbToXYZ(
        r: SIMD2<Double>, g: SIMD2<Double>, b: SIMD2<Double>, white: SIMD2<Double>
    ) -> simd_double3x3 {
        let R = xyToXYZ(r), G = xyToXYZ(g), B = xyToXYZ(b)
        let base = simd_double3x3(R, G, B)  // columns R, G, B
        let s = base.inverse * xyToXYZ(white)
        return simd_double3x3(R * s.x, G * s.y, B * s.z)
    }

    /// Bradford chromatic adaptation from white `srcXY` to white `dstXY`.
    static func bradford(from srcXY: SIMD2<Double>, to dstXY: SIMD2<Double>) -> simd_double3x3 {
        // Row-major Bradford cone response; simd takes columns, hence the
        // transposed literal.
        let mb = simd_double3x3(
            SIMD3(0.8951, 0.2664, -0.1614),
            SIMD3(-0.7502, 1.7135, 0.0367),
            SIMD3(0.0389, -0.0685, 1.0296)
        ).transpose
        let rhoS = mb * xyToXYZ(srcXY)
        let rhoD = mb * xyToXYZ(dstXY)
        let scale = simd_double3x3(diagonal: rhoD / rhoS)
        return mb.inverse * scale * mb
    }

    /// Build one gamut (matrices derived here — the only place).
    static func makeGamut(
        id: String, name: String, r: SIMD2<Double>, g: SIMD2<Double>, b: SIMD2<Double>,
        white: SIMD2<Double>
    ) -> LutGamut {
        let rgbToXYZSelf = rgbToXYZ(r: r, g: g, b: b, white: white)
        // Rec2020's own RGB→XYZ (D65) for the XYZ→Rec2020 leg.
        let rec2020RGBToXYZ = rgbToXYZ(
            r: SIMD2(0.708, 0.292), g: SIMD2(0.170, 0.797), b: SIMD2(0.131, 0.046),
            white: d65XY)
        let adapt = white != d65XY ? bradford(from: white, to: d65XY) : simd_double3x3(1)
        // gamut RGB → Rec2020 RGB = XYZ→Rec2020 · adapt · RGB→XYZ(gamut)
        let to = rec2020RGBToXYZ.inverse * adapt * rgbToXYZSelf
        return LutGamut(
            id: id, name: name, primariesXY: (r, g, b), whiteXY: white,
            toRec2020: to, fromRec2020: to.inverse)
    }

    /// The gamut registry (9 entries; rows 7/9/10 of the encoding table
    /// reference `rec2020` per the manufacturer specs).
    public static let gamuts: [String: LutGamut] = [
        "ap1": makeGamut(
            id: "ap1", name: "ACES AP1",
            r: SIMD2(0.713, 0.293), g: SIMD2(0.165, 0.830), b: SIMD2(0.128, 0.044),
            white: acesWhiteXY),
        "awg4": makeGamut(
            id: "awg4", name: "ARRI Wide Gamut 4",
            r: SIMD2(0.7347, 0.2653), g: SIMD2(0.1424, 0.8576), b: SIMD2(0.0991, -0.0308),
            white: d65XY),
        "awg3": makeGamut(
            id: "awg3", name: "ARRI Wide Gamut 3",
            r: SIMD2(0.6840, 0.3139), g: SIMD2(0.2210, 0.8480), b: SIMD2(0.0861, -0.1026),
            white: d65XY),
        "sgamut3": makeGamut(
            id: "sgamut3", name: "Sony S-Gamut3",
            r: SIMD2(0.700, 0.281), g: SIMD2(0.225, 0.810), b: SIMD2(0.089, -0.087),
            white: d65XY),
        "cinema_gamut": makeGamut(
            id: "cinema_gamut", name: "Canon Cinema Gamut",
            r: SIMD2(0.740, 0.270), g: SIMD2(0.170, 1.140), b: SIMD2(0.080, -0.100),
            white: d65XY),
        "rec2020": makeGamut(
            id: "rec2020", name: "ITU-R BT.2020",
            r: SIMD2(0.708, 0.292), g: SIMD2(0.170, 0.797), b: SIMD2(0.131, 0.046),
            white: d65XY),
        "vgamut": makeGamut(
            id: "vgamut", name: "Panasonic V-Gamut",
            r: SIMD2(0.730, 0.280), g: SIMD2(0.170, 1.060), b: SIMD2(0.084, -0.102),
            white: d65XY),
        "rec709": makeGamut(
            id: "rec709", name: "ITU-R BT.709",
            r: SIMD2(0.640, 0.330), g: SIMD2(0.300, 0.600), b: SIMD2(0.150, 0.060),
            white: d65XY),
        "display_p3": makeGamut(
            id: "display_p3", name: "Display P3",
            r: SIMD2(0.680, 0.320), g: SIMD2(0.265, 0.690), b: SIMD2(0.150, 0.060),
            white: d65XY),
        // M9-4 T3 (X5/D-M9SP-3): the 6-gamut expansion — primaries/white
        // 逐值照上游 kGamuts at c740f7b.
        "sgamut3cine": makeGamut(
            id: "sgamut3cine", name: "Sony S-Gamut3.Cine",
            r: SIMD2(0.766, 0.275), g: SIMD2(0.225, 0.800), b: SIMD2(0.089, -0.087),
            white: d65XY),
        "redwidegamutrgb": makeGamut(
            id: "redwidegamutrgb", name: "REDWideGamutRGB",
            r: SIMD2(0.780308, 0.304253), g: SIMD2(0.121595, 1.493994),
            b: SIMD2(0.095612, -0.084589),
            white: d65XY),
        "bmdwg_gen5": makeGamut(
            id: "bmdwg_gen5", name: "Blackmagic Wide Gamut Gen 5",
            r: SIMD2(0.7177215, 0.3171181), g: SIMD2(0.2280410, 0.8615690),
            b: SIMD2(0.1005841, -0.0820452),
            white: SIMD2(0.3127170, 0.3290312)),
        "davinci_wide_gamut": makeGamut(
            id: "davinci_wide_gamut", name: "DaVinci Wide Gamut",
            r: SIMD2(0.8000, 0.3130), g: SIMD2(0.1682, 0.9877), b: SIMD2(0.0790, -0.1155),
            white: d65XY),
        "dgamut": makeGamut(
            id: "dgamut", name: "DJI D-Gamut",
            r: SIMD2(0.71, 0.31), g: SIMD2(0.21, 0.88), b: SIMD2(0.09, -0.08),
            white: d65XY),
        "p3dci": makeGamut(
            id: "p3dci", name: "P3-DCI",
            r: SIMD2(0.680, 0.320), g: SIMD2(0.265, 0.690), b: SIMD2(0.150, 0.060),
            white: SIMD2(0.314, 0.351)),
    ]

    /// Typed gamut lookup (nil on an unknown id — catalog-internal ids only).
    public static func gamut(id: String) -> LutGamut? { gamuts[id] }

    // MARK: - Encoding rows (KD-1, 17 entries)

    public static let all: [LutEncoding] = [
        // Scene — camera log family (10).
        LutEncoding(
            id: .acescc, referral: .scene, transfer: .acescc, gamutId: "ap1",
            peakNits: 0, displayName: "ACEScc (AP1)"),
        LutEncoding(
            id: .acescct, referral: .scene, transfer: .acescct, gamutId: "ap1",
            peakNits: 0, displayName: "ACEScct (AP1)"),
        LutEncoding(
            id: .arriLogC4AWG4, referral: .scene, transfer: .logC4, gamutId: "awg4",
            peakNits: 0, displayName: "ARRI LogC4 (AWG4)"),
        LutEncoding(
            id: .arriLogC3AWG3, referral: .scene, transfer: .logC3, gamutId: "awg3",
            peakNits: 0, displayName: "ARRI LogC3 (AWG3)"),
        LutEncoding(
            id: .sonySLog3, referral: .scene, transfer: .slog3, gamutId: "sgamut3",
            peakNits: 0, displayName: "Sony S-Log3 (S-Gamut3)"),
        LutEncoding(
            id: .canonCLog3, referral: .scene, transfer: .clog3, gamutId: "cinema_gamut",
            peakNits: 0, displayName: "Canon C-Log3 (Cinema Gamut)"),
        LutEncoding(
            id: .fujiFLog, referral: .scene, transfer: .flog, gamutId: "rec2020",
            peakNits: 0, displayName: "Fujifilm F-Log"),
        LutEncoding(
            id: .panasonicVLog, referral: .scene, transfer: .vlog, gamutId: "vgamut",
            peakNits: 0, displayName: "Panasonic V-Log (V-Gamut)"),
        LutEncoding(
            id: .nikonNLog, referral: .scene, transfer: .nlog, gamutId: "rec2020",
            peakNits: 0, displayName: "Nikon N-Log"),
        LutEncoding(
            id: .appleLog, referral: .scene, transfer: .appleLog, gamutId: "rec2020",
            peakNits: 0, displayName: "Apple Log"),
        // M9-4 T3 (X5): the 7 scene rows — peakNits 0 逐行照上游(the
        // scene family), 行序按上游 scene 分组尾插.
        LutEncoding(
            id: .sonySLog3SGamut3Cine, referral: .scene, transfer: .slog3,
            gamutId: "sgamut3cine",
            peakNits: 0, displayName: "Sony S-Log3 / S-Gamut3.Cine"),
        LutEncoding(
            id: .fujiFLog2FGamut, referral: .scene, transfer: .flog2,
            gamutId: "rec2020",
            peakNits: 0, displayName: "Fujifilm F-Log2 / F-Gamut"),
        LutEncoding(
            id: .canonCLog2CinemaGamut, referral: .scene, transfer: .clog2,
            gamutId: "cinema_gamut",
            peakNits: 0, displayName: "Canon Log 2 / Cinema Gamut"),
        LutEncoding(
            id: .redLog3G10RWG, referral: .scene, transfer: .log3g10,
            gamutId: "redwidegamutrgb",
            peakNits: 0, displayName: "RED Log3G10 / REDWideGamutRGB"),
        LutEncoding(
            id: .blackmagicFilmGen5BMDWG, referral: .scene, transfer: .bmdFilmGen5,
            gamutId: "bmdwg_gen5",
            peakNits: 0,
            displayName: "Blackmagic Film Gen 5 / BMD Wide Gamut Gen 5"),
        LutEncoding(
            id: .davinciIntermediateDWG, referral: .scene,
            transfer: .davinciIntermediate, gamutId: "davinci_wide_gamut",
            peakNits: 0,
            displayName: "DaVinci Intermediate / DaVinci Wide Gamut"),
        LutEncoding(
            id: .djiDLogDGamut, referral: .scene, transfer: .dlog,
            gamutId: "dgamut",
            peakNits: 0, displayName: "DJI D-Log / D-Gamut"),
        // Scene — the working space row (the default pair both ends;
        // POSITION UNCHANGED — X5).
        LutEncoding(
            id: .linearRec2020, referral: .scene, transfer: .linear, gamutId: "rec2020",
            peakNits: 0, displayName: "Linear Rec2020 (working)"),
        // Display — 6.
        LutEncoding(
            id: .rec709BT1886, referral: .display, transfer: .bt1886, gamutId: "rec709",
            peakNits: 100, displayName: "Rec.709 BT.1886"),
        LutEncoding(
            id: .rec709SRGB, referral: .display, transfer: .srgb, gamutId: "rec709",
            peakNits: 100, displayName: "Rec.709 sRGB"),
        LutEncoding(
            id: .rec709Gamma22, referral: .display, transfer: .gamma22, gamutId: "rec709",
            peakNits: 100, displayName: "Rec.709 Gamma 2.2"),
        LutEncoding(
            id: .displayP3SRGB, referral: .display, transfer: .srgb, gamutId: "display_p3",
            peakNits: 100, displayName: "Display P3 sRGB"),
        LutEncoding(
            id: .rec2100PQ1000, referral: .display, transfer: .pq, gamutId: "rec2020",
            peakNits: 1000, displayName: "Rec.2100 PQ (1000 nits)"),
        LutEncoding(
            id: .rec2100HLG1000, referral: .display, transfer: .hlg, gamutId: "rec2020",
            peakNits: 1000, displayName: "Rec.2100 HLG (1000 nits)"),
        // M9-4 T3 (X5): the 3 display rows — peakNits 逐行照上游
        // (勘误④: the P3 gamma-2.6 rows carry DCI reference white 48,
        // NOT our display family's 100 convention).
        LutEncoding(
            id: .p3D65Gamma26, referral: .display, transfer: .gamma26,
            gamutId: "display_p3",
            peakNits: 48, displayName: "P3-D65 Gamma 2.6"),
        LutEncoding(
            id: .p3DCIGamma26, referral: .display, transfer: .gamma26,
            gamutId: "p3dci",
            peakNits: 48, displayName: "P3-DCI Gamma 2.6"),
        LutEncoding(
            id: .rec2020BT1886, referral: .display, transfer: .bt1886,
            gamutId: "rec2020",
            peakNits: 100, displayName: "Rec.2020 BT.1886"),
    ]

    /// Typed lookup: nil for an unknown id (the typed-rejection posture —
    /// callers degrade, never guess).
    public static func find(id: String) -> LutEncoding? {
        guard let raw = LutEncodingId(rawValue: id) else { return nil }
        return all.first { $0.id == raw }
    }

    public static func find(id: LutEncodingId) -> LutEncoding {
        all.first { $0.id == id }!
    }

    /// The panel grouping halves (scene 11 / display 6 — the explicit
    /// count contract, checker M1).
    public static var sceneEncodings: [LutEncoding] {
        all.filter { $0.referral == .scene }
    }

    public static var displayEncodings: [LutEncoding] {
        all.filter { $0.referral == .display }
    }
}

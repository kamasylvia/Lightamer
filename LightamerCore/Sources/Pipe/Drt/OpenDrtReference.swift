import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────────
// OpenDrtReference — the Float64 reference implementation of the OpenDRT
// display render transform (Plan M2-6-1 T3, KD-3 / OQ-11-A). THE algorithm-
// structure authority for this phase: the Metal kernel (OpenDrtKernels.metal)
// mirrors these stages stage-for-stage and the golden tests pin the parity.
//
// PROVENANCE & LICENSING: a walk-through transcription of the algorithm
// STRUCTURE of jedypod/open-display-transform v1.1.0 (`OpenDRT.dctl`,
// GPLv3, read-only reference). Formulas are re-derived from the math (the
// dctl's own desmos anchors are cited per function); preset NUMBERS are
// transcribed facts. ZERO GPL code or text copied — Swift, written fresh
// (D-M2-6-CONTEXT-1; NOTICE at the repo root). Every stage below cites its
// dctl anchor line as a factual pointer.
//
// ═══ ALGORITHM STRUCTURE MAP (dctl `transform()` OpenDRT.dctl:737-1211;
//     stage numbers = the shared vocabulary for the kernel + tests) ═══
//
//   Pre-run constants (dctl :943-959 — the Tonescale Constraint Calculations;
//   the kernel derives these per-thread like the dctl does, keeping ONE
//   derivation for both faces):
//     ts_x1/ts_y1/ts_x0/ts_y0/ts_s0/ts_p/ts_s10/ts_m1/ts_m2/ts_s/ts_dsc
//     pt_cmp_Lf/s_Lp100/ts_s1
//   [0] Input linearization — FIXED identity (v1 input is always working-
//       space linear Rec2020; the dctl in_oetf menu is not exposed, CONTEXT
//       衔界面; dctl :933 skipped).
//   [1] Input gamut → P3-D65 render gamut (dctl :962-964: in_to_xyz →
//       xyz_to_p3d65; our in_to_xyz = matrix_rec2020_to_xyz).
//   [2] Render-space desaturation (dctl :967-971, rs_w/sat_L lerp).
//   [3] Offset (dctl :974-976, rgb += tn_off).
//   [4] Tonescale norm + RGB ratios (dctl :979-983: tsn = ‖rgb‖/√3,
//       rgb /= tsn).
//   [5] Opponent/hue-angle constants (dctl :985-1013: opp, ach_d smoothing,
//       hue rotation, ha_rgb / ha_rgb_hs / ha_cmy gauss windows).
//   [6] Pre-Brilliance (dctl :1016-1022, brl gauges × gauss hue weights).
//   [7] Contrast Low (dctl :1024-1036, toe-cubic + ts_x0 constraint norm).
//   [8] Contrast High (dctl :1038-1044, contrast_high power+linear ext).
//   [9] Hyperbolic compression (dctl :1046-1055: tsn_pt / tsn_const /
//       tsn through compress_hyperbolic_power with ts_s1 / s_Lp100 / ts_s).
//   [10] Hue Contrast R (dctl :1062-1072, g/b scaled by hc_f).
//   [11] Hue Shift RGB (dctl :1080-1088, toward Y/C shifts on tsn_pt).
//   [12] Hue Shift CMY (dctl :1090-1100, inverse-intensity shifts).
//   [13] Purity Limit Low (dctl :1108-1110, ptf = 1 − tsn_pt^p).
//   [14] Purity Limit High (dctl :1112-1114, ptf^= ach-modulated exponent).
//   [15] Mid-Range Purity (dctl :1122-1130, gauss-windowed ptm pair).
//   [16] Lerp to peak achromatic (dctl :1133, rgb·ptf + 1 − ptf).
//   [17] Inverse render space (dctl :1135-1137, the [2] inverse form).
//   [18] Display gamut + creative whitepoint (dctl :1139-1140 →
//        display_gamut_whitepoint :593-732: CAT to the chosen white +
//        cwp_lm intensity mix + the precomputed cwp_norm peak renormalize).
//   [19] Post Brilliance (dctl :1142-1152, brlp on re-measured opponent).
//   [20] Purity Compress Low (dctl :1154-1155, per-channel softplus).
//   [21] Final tonescale adjustments (dctl :1157-1160: tsn·= ts_m2 →
//        toe-quadratic → ·= ts_dsc).
//   [22] Return from RGB ratios (dctl :1174, rgb ·= tsn).
//   [23] Rec.2020 (P3 Limited) clamp + matrix (dctl :1177-1180, gamut 2).
//   [24] Display clamp (dctl :1182-1183, presets mode hard-codes clamp=1).
//   [—]  EOTF encode — NOT HERE. The dctl's final EOTF block (:1185-1195)
//        is the EotfBox's job (KD-4 separation): this function outputs
//        PEAK-NORMALIZED display-linear RGB (1.0 = tn_Lp nits), so ts_dsc
//        is the SDR form 100/tn_Lp UNCONDITIONALLY (the dctl's per-EOTF
//        ts_dsc variants fold into the EotfBox's peak normalization —
//        DECISIONS §D3).
//
//   HDR grey rail (dctl :946 ts_y0 tn_gb term + :956 pt_cmp_Lf) rides the
//   pre-run constants — peak 100→1000 grey boost + purity-compression
//   lerp both enter through ts_y0/ts_s1.
// ─────────────────────────────────────────────────────────────────────────────

/// Row-major 3×3 (rows stored as SIMD3 — `M * v` = Σ_j M[i][j]·v_j, the
/// same convention as the reference's `vdot`).
struct DrtMat3 {
    var r0, r1, r2: SIMD3<Double>

    @inline(__always) func multiply(_ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            r0.x * v.x + r0.y * v.y + r0.z * v.z,
            r1.x * v.x + r1.y * v.y + r1.z * v.z,
            r2.x * v.x + r2.y * v.y + r2.z * v.z
        )
    }
}

public enum OpenDrtReference {

    // MARK: Constants (dctl :303-304 + the gamut/CAT tables :228-294)

    static let sqrt3 = 1.73205080756887729353
    static let pi = Double.pi

    // Primaries matrices (numeric facts — BT./SMPTE standard derivations as
    // tabulated by the reference; Double re-state).
    static let rec2020ToXYZ = DrtMat3(
        r0: SIMD3(0.636958048301290991, 0.144616903586208406, 0.168880975164172054),
        r1: SIMD3(0.26270021201126692, 0.677998071518871148, 0.0593017164698619384),
        r2: SIMD3(4.9999999999999999e-17, 0.0280726930490874452, 1.06098505771079066))
    static let p3d65ToXYZ = DrtMat3(
        r0: SIMD3(0.486570948648216151, 0.265667693169093, 0.198217285234362467),
        r1: SIMD3(0.228974564069748754, 0.691738521836506193, 0.079286914093744984),
        r2: SIMD3(-4.00000000000000029e-17, 0.0451133818589026167, 1.04394436890097575))
    static let xyzToP3D65 = DrtMat3(
        r0: SIMD3(2.49349691194142542, -0.93138361791912383, -0.402710784450716841),
        r1: SIMD3(-0.829488969561574696, 1.76266406031834655, 0.0236246858419435941),
        r2: SIMD3(0.0358458302437844531, -0.0761723892680418041, 0.956884524007687309))
    static let xyzToRec709 = DrtMat3(
        r0: SIMD3(3.24096994190452348, -1.53738317757009435, -0.498610760293003552),
        r1: SIMD3(-0.969243636280879506, 1.87596750150771996, 0.0415550574071755843),
        r2: SIMD3(0.0556300796969936354, -0.20397695888897649, 1.05697151424287816))
    static let p3ToRec2020 = DrtMat3(
        r0: SIMD3(0.753833034361722221, 0.198597369052616435, 0.0475695965856618441),
        r1: SIMD3(0.0457438489653582137, 0.9417772198116936, 0.0124789312229481135),
        r2: SIMD3(-0.0012103403545183941, 0.0176017173010899926, 0.983608623053428777))

    // CAT (chromatic adaptation) matrices — DCI/D65/D60 sources to the six
    // creative whites (dctl :259-294).
    static let catD65ToD93 = DrtMat3(
        r0: SIMD3(0.95703423023223877, -0.0247171502560377121, 0.0624028593301773071),
        r1: SIMD3(-0.0179296955466270447, 0.990019857883453369, 0.0248119533061981201),
        r2: SIMD3(0.00127589143812656403, 0.00427919067442417058, 1.29345715045928955))
    static let catD65ToD75 = DrtMat3(
        r0: SIMD3(0.981001079082489014, -0.0116619253531098366, 0.0265614092350006104),
        r1: SIMD3(-0.00843488052487373352, 0.996506094932556152, 0.0105696544051170349),
        r2: SIMD3(0.000552809564396739006, 0.00179840810596942902, 1.12374722957611084))
    static let catD65ToD60 = DrtMat3(
        r0: SIMD3(1.01182246208190918, 0.00778879318386316299, -0.0157783031463623047),
        r1: SIMD3(0.00561682833358645439, 1.00150644779205322, -0.00628517568111419678),
        r2: SIMD3(-0.000335735734552145004, -0.0010509500280022619, 0.927366673946380615))
    static let catD65ToD55 = DrtMat3(
        r0: SIMD3(1.02585089206695557, 0.0179439820349216461, -0.0332137793302536011),
        r1: SIMD3(0.0129133854061365128, 1.00214779376983643, -0.0132421031594276428),
        r2: SIMD3(-0.000719940289855003032, -0.00218106806278228803, 0.84868013858795166))
    static let catD65ToD50 = DrtMat3(
        r0: SIMD3(1.04257404804229736, 0.03089117631316185, -0.052812620997428894),
        r1: SIMD3(0.0221935361623764038, 1.00185668468475342, -0.0210737623274326324),
        r2: SIMD3(-0.00116488314233720303, -0.00342052709311246915, 0.761789083480834961))
    static let catD60ToD93 = DrtMat3(
        r0: SIMD3(0.946056902408599854, -0.0319503024220466614, 0.0831701457500457764),
        r1: SIMD3(-0.0231979694217443466, 0.988745808601379395, 0.0330617502331733704),
        r2: SIMD3(0.00169203430414199807, 0.00572328735142946243, 1.39483106136322021))
    static let catD60ToD75 = DrtMat3(
        r0: SIMD3(0.969659984111785889, -0.019138311967253685, 0.0450099557638168335),
        r1: SIMD3(-0.0138545772065751972, 0.995133817195892334, 0.0179062262177469243),
        r2: SIMD3(0.000931452261283994185, 0.00306008197367191315, 1.21179807186126709))
    static let catD60ToD65 = DrtMat3(
        r0: SIMD3(0.988363921642303467, -0.00766910053789615631, 0.0167641639709472656),
        r1: SIMD3(-0.0055409618653357029, 0.998546123504638672, 0.00667332112789153871),
        r2: SIMD3(0.000351537019014359008, 0.00112883746223492898, 1.07833576202392578))
    static let catD60ToD55 = DrtMat3(
        r0: SIMD3(1.01380288600921631, 0.0100131509825587271, -0.018498346209526062),
        r1: SIMD3(0.00720565160736441612, 1.00057685160336, -0.00737529997758865356),
        r2: SIMD3(-0.000401133671402941998, -0.00121434964239597299, 0.915135681629180908))
    static let catD60ToD50 = DrtMat3(
        r0: SIMD3(1.03025269508361816, 0.02279104662176056, -0.0392656922340393066),
        r1: SIMD3(0.0163766480982303619, 1.00020599270233, -0.015666823834180931),
        r2: SIMD3(-0.000864576781168579947, -0.00254668481647968292, 0.821422040462493896))
    static let catDCIToD93 = DrtMat3(
        r0: SIMD3(0.965685009956359863, 0.00183745240792632103, 0.0912967324256896973),
        r1: SIMD3(0.000514572137035429044, 0.965166747570037842, 0.036014653742313385),
        r2: SIMD3(0.00154250487685203596, 0.00702651776373386383, 1.47287476062774658))
    static let catDCIToD75 = DrtMat3(
        r0: SIMD3(0.990120768547058105, 0.0151389474049210548, 0.0511047691106796265),
        r1: SIMD3(0.0102197211235761642, 0.971718132495880127, 0.0200536623597145081),
        r2: SIMD3(0.000743072712793946049, 0.0042176349088549614, 1.27959656715393066))
    static let catDCIToD65 = DrtMat3(
        r0: SIMD3(1.00951600074768066, 0.0269675441086292267, 0.0213620811700820923),
        r1: SIMD3(0.0187991037964820862, 0.975330352783203125, 0.0082273334264755249),
        r2: SIMD3(0.000134543282911180989, 0.00217903498560190201, 1.138663649559021))
    static let catDCIToD60 = DrtMat3(
        r0: SIMD3(1.02159523963928223, 0.034848678857088089, 0.00371252000331878705),
        r1: SIMD3(0.0244968775659799576, 0.976937234401702881, 0.00120301544666290305),
        r2: SIMD3(-0.00023391586728393999, 0.000986687839031219049, 1.05594265460968018))
    static let catDCIToD55 = DrtMat3(
        r0: SIMD3(1.03594577312469482, 0.0450937561690807343, -0.0157573819160461426),
        r1: SIMD3(0.0318740680813789368, 0.977744519710540771, -0.00655744969844818115),
        r2: SIMD3(-0.000653609400615095984, -0.000297372229397297014, 0.966327786445617676))
    static let catDCIToD50 = DrtMat3(
        r0: SIMD3(1.05306875705718994, 0.0581297315657138824, -0.0376100838184356689),
        r1: SIMD3(0.0412359423935413361, 0.977693676948547363, -0.0152792222978786826),
        r2: SIMD3(-0.00113777676597237609, -0.00170759297907352404, 0.867368340492248535))
    static let catD65ToDCI = DrtMat3(
        r0: SIMD3(0.991085588932037354, -0.0273622870445251465, -0.0183956623077392578),
        r1: SIMD3(-0.0191021915525197983, 1.02583777904510498, -0.00705372542142868042),
        r2: SIMD3(-8.05503223091359977e-05, -0.00195988826453685804, 0.878238439559936523))

    /// The dctl display-gamut ordinal (0 Rec709 / 1 P3D65 / 2 Rec2020
    /// P3-limited / 3 P3D60 / 4 P3DCI / 5 XYZ).
    public static func displayGamutID(for space: DrtEncodingSpace) -> Int {
        switch space {
        case .rec709: return 0
        case .p3d65: return 1
        case .rec2020: return 2
        case .p3d60: return 3
        case .p3dci: return 4
        case .xyz: return 5
        }
    }

    /// The surround compensation ordinal (dctl tn_su: 0 dark / 1 dim /
    /// 2 bright), derived from the (space, eotf) pair following the dctl's
    /// display_encoding_preset table (:858-902) — DECISIONS §D3. Legal
    /// combos only (the linkage table's rows).
    public static func surround(for space: DrtEncodingSpace, eotf: DrtEotf) -> Int {
        switch (space, eotf) {
        case (.rec709, .bt1886): return 1      // Rec.1886 → dim
        case (.rec709, .gamma22): return 2     // sRGB display → bright
        case (.p3d65, .gamma22): return 2      // Display P3 → bright
        case (.p3d65, .st2084): return 0       // Dolby PQ → dark
        case (.p3d60, .gamma26), (.p3dci, .gamma26), (.xyz, .gamma26): return 0
        case (.rec2020, .st2084), (.rec2020, .hlg): return 0
        default: return 0
        }
    }

    // MARK: - Stage primitives (dctl :503-589; desmos anchors cited by the
    // reference — factual URL pointers, not copied code)

    /// dctl :503 compress_hyperbolic_power (desmos ofwtcmzc3w).
    static func compressHyperbolicPower(_ x: Double, _ s: Double, _ p: Double) -> Double {
        safePow(x / (x + s), p)
    }

    /// dctl :508 compress_toe_quadratic (desmos skk8ahmnws).
    static func compressToeQuadratic(_ x: Double, _ toe: Double, inverse: Bool) -> Double {
        if toe == 0 { return x }
        if !inverse {
            return safePow(x, 2) / (x + toe)
        } else {
            return (x + Foundation.sqrt(x * (4 * toe + x))) / 2
        }
    }

    /// dctl :518 compress_toe_cubic (desmos ubgteikoke).
    static func compressToeCubic(_ x: Double, _ m: Double, _ w: Double, inverse: Bool) -> Double {
        if m == 1 { return x }
        let x2 = x * x
        if !inverse {
            return x * (x2 + m * w) / (x2 + w)
        } else {
            let p0 = x2 - 3 * m * w
            let p1 = 2 * x2 + 27 * w - 9 * m * w
            let p2 = Foundation.pow(
                Foundation.sqrt(x2 * p1 * p1 - 4 * p0 * p0 * p0) / 2 + x * p1 / 2,
                1.0 / 3.0)
            return p0 / (3 * p2) + p2 / 3 + x / 3
        }
    }

    /// dctl :542 contrast_high (desmos etjgwyrgad) — high-exposure power
    /// adjustment with linear extension above the pivot knee.
    static func contrastHigh(
        _ x: Double, _ p: Double, _ pv: Double, _ pvLx: Double, inverse: Bool
    ) -> Double {
        let x0 = 0.18 * Foundation.pow(2, pv)
        if x < x0 || p == 1 { return x }
        let o = x0 - x0 / p
        let s0 = Foundation.pow(x0, 1 - p) / p
        let x1 = x0 * Foundation.pow(2, pvLx)
        let k1 = p * s0 * Foundation.pow(x1, p) / x1
        let y1 = s0 * Foundation.pow(x1, p) + o
        if inverse {
            return x > y1 ? (x - y1) / k1 + x1 : Foundation.pow((x - o) / s0, 1 / p)
        } else {
            return x > x1 ? k1 * (x - x1) + y1 : s0 * Foundation.pow(x, p) + o
        }
    }

    /// dctl :569 softplus (desmos mr9rmujsmn).
    static func softplus(_ x: Double, _ s: Double) -> Double {
        if x > 10 * s || s < 1e-4 { return x }
        return s * Foundation.log(max(0, 1 + Foundation.exp(x / s)))
    }

    /// dctl :576 gauss_window (desmos vhr9hstlyk).
    static func gaussWindow(_ x: Double, _ w: Double) -> Double {
        Foundation.exp(-x * x / w)
    }

    /// dctl :581 opponent — the cyan-yellow / green-magenta opponent pair.
    static func opponent(_ rgb: SIMD3<Double>) -> SIMD2<Double> {
        SIMD2(rgb.x - rgb.z, rgb.y - (rgb.x + rgb.z) / 2)
    }

    /// dctl :586 hue_offset — modulo-preserved hue shift, −π..π.
    static func hueOffset(_ h: Double, _ o: Double) -> Double {
        Foundation.fmod(h - o + pi, 2 * pi) - pi
    }

    /// The reference's spowf: a ≤ 0 stays a (finite garbage-in guard).
    static func safePow(_ a: Double, _ b: Double) -> Double {
        a <= 0 ? a : Foundation.pow(a, b)
    }

    @inline(__always) private static func hypot2(_ v: SIMD2<Double>) -> Double {
        Foundation.sqrt(max(0, v.x * v.x + v.y * v.y))
    }

    @inline(__always) private static func hypot3(_ v: SIMD3<Double>) -> Double {
        Foundation.sqrt(max(0, v.x * v.x + v.y * v.y + v.z * v.z))
    }

    // MARK: - Pre-run tonescale constants (dctl :943-959)

    /// The per-run constraint block. Computed from the record + the resolved
    /// context (display gamut ordinal, creative-white ordinal, surround).
    /// The Metal kernel derives the SAME block per-thread (one derivation,
    /// two faces — see the structure map preamble).
    public struct TonescaleConstants {
        public var tsX1: Double
        public var tsY1: Double
        public var tsX0: Double
        public var tsY0: Double
        public var tsS0: Double
        public var tsP: Double
        public var tsS10: Double
        public var tsM1: Double
        public var tsM2: Double
        public var tsS: Double
        /// 100/tn_Lp unconditionally — the peak-normalized terminal (§ header).
        public var tsDsc: Double
        public var ptCmpLf: Double
        public var sLp100: Double
        public var tsS1: Double
    }

    public static func tonescaleConstants(
        record: DrtRecord, displayGamut: Int, surround: Int
    ) -> TonescaleConstants {
        let p = record.parameters
        let tnLp = Double(record.peakLuminance)
        let tnGb = Double(record.hdrGreyBoost)
        let tnLg = Double(record.displayGreyLuminance)
        let tnCon = Double(p.tnCon)
        let tnSh = Double(p.tnSh)
        let tnToe = Double(p.tnToe)
        let tnOff = Double(p.tnOff)

        let tsX1 = Foundation.pow(2, 6 * tnSh + 4)
        let tsY1 = tnLp / 100
        let tsX0 = 0.18 + tnOff
        let tsY0 = tnLg / 100 * (1 + tnGb * Foundation.log2(tsY1))
        let tsS0 = compressToeQuadratic(tsY0, tnToe, inverse: true)
        let tsP = tnCon / (1 + Double(surround) * 0.05)
        let tsS10 = tsX0 * (Foundation.pow(tsS0, -1 / tnCon) - 1)
        let tsM1 = tsY1 / Foundation.pow(tsX1 / (tsX1 + tsS10), tnCon)
        let tsM2 = compressToeQuadratic(tsM1, tnToe, inverse: true)
        let tsS = tsX0 * (Foundation.pow(tsS0 / tsM2, -1 / tnCon) - 1)
        // dctl :953 carries the per-EOTF ts_dsc; ours is the SDR form — the
        // EotfBox owns the HDR rescale (structure map [—]).
        let tsDsc = 100 / tnLp
        let ptCmpLf = Double(record.hdrPurity) * min(1, (tnLp - 100) / 900)
        let sLp100 = tsX0 * (Foundation.pow(tnLg / 100, -1 / tnCon) - 1)
        let tsS1 = tsS * ptCmpLf + sLp100 * (1 - ptCmpLf)
        return TonescaleConstants(
            tsX1: tsX1, tsY1: tsY1, tsX0: tsX0, tsY0: tsY0, tsS0: tsS0,
            tsP: tsP, tsS10: tsS10, tsM1: tsM1, tsM2: tsM2, tsS: tsS,
            tsDsc: tsDsc, ptCmpLf: ptCmpLf, sLp100: sLp100, tsS1: tsS1)
    }

    // MARK: - Display gamut + creative whitepoint (dctl :593-732)

    /// Stage [18]. `cwp` = the resolved creative-white ordinal
    /// (0 D93 / 1 D75 / 2 D65 / 3 D60 / 4 D55 / 5 D50).
    static func displayGamutWhitepoint(
        _ rgbIn: SIMD3<Double>, _ tsnConst: Double, _ cwpLm: Double,
        _ displayGamut: Int, _ cwp: Int
    ) -> SIMD3<Double> {
        var rgb = p3d65ToXYZ.multiply(rgbIn)
        let cwpNeutralBase = rgb
        var cwpNeutral = cwpNeutralBase
        let cwpF = Foundation.pow(tsnConst, 2 * cwpLm)

        if displayGamut < 3 {  // D65-aligned P3 / Rec.709 / Rec2020-P3-limited
            switch cwp {
            case 0: rgb = catD65ToD93.multiply(rgb)
            case 1: rgb = catD65ToD75.multiply(rgb)
            case 3: rgb = catD65ToD60.multiply(rgb)
            case 4: rgb = catD65ToD55.multiply(rgb)
            case 5: rgb = catD65ToD50.multiply(rgb)
            default: break  // cwp 2 = D65 — identity
            }
        } else if displayGamut == 3 {  // P3-D60 source
            switch cwp {
            case 0: rgb = catD60ToD93.multiply(rgb)
            case 1: rgb = catD60ToD75.multiply(rgb)
            case 2: rgb = catD60ToD65.multiply(rgb)
            case 4: rgb = catD60ToD55.multiply(rgb)
            case 5: rgb = catD60ToD50.multiply(rgb)
            default: break  // D60 — identity
            }
        } else {  // DCI P3 or DCDM XYZ — keep the neutral axis D65
            cwpNeutral = catDCIToD65.multiply(rgb)
            switch cwp {
            case 0: rgb = catDCIToD93.multiply(rgb)
            case 1: rgb = catDCIToD75.multiply(rgb)
            case 2: rgb = cwpNeutral
            case 3: rgb = catDCIToD60.multiply(rgb)
            case 4: rgb = catDCIToD55.multiply(rgb)
            case 5: rgb = catDCIToD50.multiply(rgb)
            default: break
            }
        }

        // Mix toward the creative white by the range control.
        rgb = rgb * cwpF + cwpNeutral * (1 - cwpF)

        // Back to the target display gamut.
        switch displayGamut {
        case 0:
            rgb = xyzToRec709.multiply(rgb)
        case 5:  // DCDM XYZ — whitepoint D65 → DCI
            rgb = catD65ToDCI.multiply(rgb)
        default:  // all others → P3D65
            rgb = xyzToP3D65.multiply(rgb)
        }

        // Post-whitepoint peak renormalization (the precomputed cwp_norm
        // tables, dctl :653-729 — numeric facts).
        var cwpNorm = 1.0
        switch displayGamut {
        case 0:  // Rec.709
            switch cwp {
            case 0: cwpNorm = 0.744192699063
            case 1: cwpNorm = 0.873470832146
            case 3: cwpNorm = 0.955936992163
            case 4: cwpNorm = 0.905671332781
            case 5: cwpNorm = 0.850004385027
            default: break
            }
        case 1, 2:  // P3D65 / Rec2020 P3-limited
            switch cwp {
            case 0: cwpNorm = 0.762687057298
            case 1: cwpNorm = 0.884054083328
            case 3: cwpNorm = 0.964320186739
            case 4: cwpNorm = 0.923076518860
            case 5: cwpNorm = 0.876572837784
            default: break
            }
        case 3:  // P3D60
            switch cwp {
            case 0: cwpNorm = 0.704956321013
            case 1: cwpNorm = 0.816715709816
            case 2: cwpNorm = 0.923382193663
            case 4: cwpNorm = 0.956138500287
            case 5: cwpNorm = 0.906801453023
            default: break
            }
        case 4:  // P3DCI
            switch cwp {
            case 0: cwpNorm = 0.665336141225
            case 1: cwpNorm = 0.770397131382
            case 2: cwpNorm = 0.870572343302
            case 3: cwpNorm = 0.891354547503
            case 4: cwpNorm = 0.855327825187
            case 5: cwpNorm = 0.814566436117
            default: break
            }
        case 5:  // DCDM XYZ
            switch cwp {
            case 0: cwpNorm = 0.707142784007
            case 1: cwpNorm = 0.815561082617
            default: cwpNorm = 0.916555279740  // D65 and warmer (DCI spec)
            }
        default: break
        }

        // Only the range-affected share normalizes.
        rgb *= cwpNorm * cwpF + 1 - cwpF
        return rgb
    }

    // MARK: - The total function

    /// Stage [0]–[24]. `linearRec2020`: scene-linear working-space RGB.
    /// `cwp`: the RESOLVED creative-white ordinal ("use_look_preset"
    /// resolves through the look snapshot's white — DrtPresets, T5).
    public static func run(
        record: DrtRecord, linearRec2020: SIMD3<Double>, cwp: Int
    ) -> SIMD3<Double> {
        let p = record.parameters
        let gamut = displayGamutID(for: record.encodingSpace)
        let su = surround(for: record.encodingSpace, eotf: record.encodingEotf)
        let ts = tonescaleConstants(record: record, displayGamut: gamut, surround: su)

        var rgb = linearRec2020

        // [1] input gamut → P3-D65 (working space is Rec2020).
        rgb = xyzToP3D65.multiply(rec2020ToXYZ.multiply(rgb))

        // [2] render-space desaturation.
        let rsW = SIMD3(Double(p.rsRw), 1 - Double(p.rsRw) - Double(p.rsBw), Double(p.rsBw))
        let rsSa = Double(p.rsSa)
        var satL = rgb.x * rsW.x + rgb.y * rsW.y + rgb.z * rsW.z
        rgb = satL * rsSa + rgb * (1 - rsSa)

        // [3] offset.
        rgb += Double(p.tnOff)

        // [4] tonescale norm + RGB ratios.
        var tsn = hypot3(rgb) / sqrt3
        rgb /= tsn

        // [5] opponent + hue-angle constants.
        let opp = opponent(rgb)
        var achD = hypot2(opp) / 2
        achD = 1.25 * compressToeQuadratic(achD, 0.25, inverse: false)
        let hue = Foundation.fmod(
            Foundation.atan2(opp.x, opp.y) + pi + 1.10714931, 2 * pi)
        let haRgb = SIMD3(
            gaussWindow(hueOffset(hue, 0.1), 0.66),
            gaussWindow(hueOffset(hue, 4.3), 0.66),
            gaussWindow(hueOffset(hue, 2.3), 0.66))
        let haRgbHs = SIMD3(
            gaussWindow(hueOffset(hue, -0.4), 0.66),
            haRgb.y,
            gaussWindow(hueOffset(hue, 2.5), 0.66))
        let haCmy = SIMD3(
            gaussWindow(hueOffset(hue, 3.3), 0.5),
            gaussWindow(hueOffset(hue, 1.3), 0.5),
            gaussWindow(hueOffset(hue, -1.15), 0.5))

        // [6] pre-brilliance.
        let brlRng = Double(p.brlRng)
        let brlTsf = Foundation.pow(tsn / (tsn + 1), 1 - brlRng)
        let brlExf =
            (Double(p.brl) + Double(p.brlR) * haRgb.x + Double(p.brlG) * haRgb.y
                + Double(p.brlB) * haRgb.z) * Foundation.pow(achD, 1 / Double(p.brlSt))
        let brlEx = Foundation.pow(2, brlExf * (brlExf < 0 ? brlTsf : 1 - brlTsf))
        tsn *= brlEx

        // [7] contrast low. (The dctl's tn_lcon_enable maps to the value:
        // every enable=0 preset carries tn_lcon = 0, and m = 2^0 = 1 makes
        // the cubic a no-op — a value-driven enable, no flag field.)
        let tnLcon = Double(p.tnLcon)
        if tnLcon != 0 {
            let lconM = Foundation.pow(2, -tnLcon)
            var lconW = Double(p.tnLconW) / 4
            lconW *= lconW
            let lconCnstSc = compressToeCubic(ts.tsX0, lconM, lconW, inverse: true) / ts.tsX0
            tsn *= lconCnstSc
            tsn = compressToeCubic(tsn, lconM, lconW, inverse: false)
        }

        // [8] contrast high (p = 2^0 = 1 early-outs to the identity — the
        // same value-driven enable as [7]).
        let tnHcon = Double(p.tnHcon)
        if tnHcon != 0 {
            let hconP = Foundation.pow(2, tnHcon)
            tsn = contrastHigh(tsn, hconP, Double(p.tnHconPv), Double(p.tnHconSt), inverse: false)
        }

        // [9] hyperbolic compression.
        let tsP = ts.tsP
        let tsnPt = compressHyperbolicPower(tsn, ts.tsS1, tsP)
        let tsnConst = compressHyperbolicPower(tsn, ts.sLp100, tsP)
        tsn = compressHyperbolicPower(tsn, ts.tsS, tsP)

        // [10] hue contrast R. (hc_r = 0 → hc_f = 1, the value-driven
        // no-op; the 1/hc_r_rng power needs a nonzero range.)
        let hcRRng = Double(p.hcRRng)
        if hcRRng > 0 {
            let hcTs0 = 1 - tsnConst
            let hcC0 = hcTs0 * (1 - achD) + achD * (1 - hcTs0)
            let hcC = hcC0 * achD * haRgb.x
            let hcTs = Foundation.pow(hcTs0, 1 / hcRRng)
            let hcF = Double(p.hcR) * (hcC - 2 * hcC * hcTs) + 1
            rgb = SIMD3(rgb.x, rgb.y * hcF, rgb.z * hcF)
        }

        // [11] hue shift RGB.
        let tsnPtHS = SIMD3(
            haRgbHs.x * achD * Foundation.pow(tsnPt, 1 / Double(p.hsRRng)),
            haRgbHs.y * achD * Foundation.pow(tsnPt, 1 / Double(p.hsGRng)),
            haRgbHs.z * achD * Foundation.pow(tsnPt, 1 / Double(p.hsBRng)))
        var hsf = SIMD3(
            tsnPtHS.x * Double(p.hsR), tsnPtHS.y * -Double(p.hsG),
            tsnPtHS.z * -Double(p.hsB))
        hsf = SIMD3(hsf.z - hsf.y, hsf.x - hsf.z, hsf.y - hsf.x)
        rgb += hsf

        // [12] hue shift CMY.
        let tsnPtCompl = 1 - tsnPt
        let tsnPtCmy = SIMD3(
            haCmy.x * achD * Foundation.pow(tsnPtCompl, 1 / Double(p.hsCRng)),
            haCmy.y * achD * Foundation.pow(tsnPtCompl, 1 / Double(p.hsMRng)),
            haCmy.z * achD * Foundation.pow(tsnPtCompl, 1 / Double(p.hsYRng)))
        hsf = SIMD3(
            tsnPtCmy.x * -Double(p.hsC), tsnPtCmy.y * Double(p.hsM),
            tsnPtCmy.z * Double(p.hsY))
        hsf = SIMD3(hsf.z - hsf.y, hsf.x - hsf.z, hsf.y - hsf.x)
        rgb += hsf

        // [13] purity limit low.
        let ptLmlP = 1 + 4 * (1 - tsnPt) *
            (Double(p.ptLml) + Double(p.ptLmlR) * haRgbHs.x
                + Double(p.ptLmlG) * haRgbHs.y + Double(p.ptLmlB) * haRgbHs.z)
        var ptf = 1 - Foundation.pow(tsnPt, ptLmlP)

        // [14] purity limit high.
        let ptLmhP = (1 - achD * (Double(p.ptLmhR) * haRgbHs.x + Double(p.ptLmhB) * haRgbHs.z))
            * (1 - Double(p.ptLmh) * achD)
        ptf = Foundation.pow(ptf, ptLmhP)

        // [15] mid-range purity.
        let ptmLowSt = Double(p.ptmLowSt)
        let ptmLowRng = Double(p.ptmLowRng)
        let ptmLowF: Double =
            (ptmLowSt == 0 || ptmLowRng == 0)
            ? 1
            : 1 + Double(p.ptmLow) * Foundation.exp(-2 * achD * achD / ptmLowSt)
                * Foundation.pow(1 - tsnConst, 1 / ptmLowRng)
        let ptmHighSt = Double(p.ptmHighSt)
        let ptmHighRng = Double(p.ptmHighRng)
        let ptmHighF: Double =
            (ptmHighSt == 0 || ptmHighRng == 0)
            ? 1
            : 1 + Double(p.ptmHigh) * Foundation.exp(-2 * achD * achD / ptmHighSt)
                * Foundation.pow(tsnPt, 1 / (4 * ptmHighRng))
        ptf *= ptmLowF * ptmHighF

        // [16] lerp to peak achromatic in rgb ratios.
        rgb = rgb * ptf + 1 - ptf

        // [17] inverse render space.
        satL = rgb.x * rsW.x + rgb.y * rsW.y + rgb.z * rsW.z
        rgb = (satL * rsSa - rgb) / (rsSa - 1)

        // [18] display gamut + creative whitepoint.
        rgb = displayGamutWhitepoint(rgb, tsnConst, Double(p.cwpLm), gamut, cwp)

        // [19] post brilliance.
        let brlpOpp = opponent(rgb)
        var brlpAchD = hypot2(brlpOpp) / 4
        brlpAchD = 1.1 * (brlpAchD * brlpAchD / (brlpAchD + 0.1))
        let brlpHaRgb = achD * haRgb
        let brlpM = Double(p.brlp) + Double(p.brlpR) * brlpHaRgb.x
            + Double(p.brlpG) * brlpHaRgb.y + Double(p.brlpB) * brlpHaRgb.z
        let brlpEx = Foundation.pow(2, brlpM * brlpAchD * tsn)
        rgb *= brlpEx

        // [20] purity compress low (per-channel softplus).
        rgb = SIMD3(
            softplus(rgb.x, Double(p.ptlC)),
            softplus(rgb.y, Double(p.ptlM)),
            softplus(rgb.z, Double(p.ptlY)))

        // [21] final tonescale adjustments.
        tsn *= ts.tsM2
        tsn = compressToeQuadratic(tsn, Double(p.tnToe), inverse: false)
        tsn *= ts.tsDsc

        // [22] return from rgb ratios.
        rgb *= tsn

        // [23] Rec.2020 (P3 Limited): clamp negatives then P3 → Rec2020.
        if gamut == 2 {
            rgb = SIMD3(max(rgb.x, 0), max(rgb.y, 0), max(rgb.z, 0))
            rgb = p3ToRec2020.multiply(rgb)
        }

        // [24] display clamp (presets-mode clamp=1).
        rgb = SIMD3(
            Swift.min(Swift.max(rgb.x, 0), 1),
            Swift.min(Swift.max(rgb.y, 0), 1),
            Swift.min(Swift.max(rgb.z, 0), 1))

        return rgb
    }
}

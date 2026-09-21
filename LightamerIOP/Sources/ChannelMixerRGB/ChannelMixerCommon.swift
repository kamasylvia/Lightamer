import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────
// ChannelMixerCommon (Plan 05-03-T1, IOP-COLOR-02 shared math) — dt's
// illuminant + chromatic-adaptation core for `channelmixerrgb` ("color
// calibration", v50 28.5), transliterated from
//   - src/common/illuminants.h (illuminant enums :26-73; F/LED tables
//     :86-116; CCT_to_xy_daylight :138-155; CCT_to_xy_blackbody :157-178;
//     illuminant_xy_to_XYZ :181-187; illuminant_to_xy :220-324;
//     xy_to_CCT (Lee) :124-136)
//     NOT PORTED: WB_coeffs_to_illuminant_xy :325-345,
//     find_temperature_from_raw_coeffs :389-453 — both need the live RAW
//     image + pipe WB channel (commit :3115/process :2200+:2311), which
//     the post-CIRAW commit path has no access to. .camera falls back to
//     the daylight model (divergence #1 on ChannelMixerRGBModule).
//   - src/common/chromatic_adaptation.h (XYZ_to_Bradford_LMS :37-55;
//     XYZ_to_CAT16_LMS :91-109; convert_any_* :145-214;
//     bradford_adapt_D50 :256-285; CAT16_adapt_D50 :313-338;
//     XYZ_adapt_D50 :360-375; D65/D50 LMS targets :239/:267/:300/:322)
//   - src/iop/channelmixerrgb.c (_gamut_mapping :648-705;
//     _luma_chroma :706-769; commit illuminant/p/MIX derivation :3047-3150)
// (tree dc58cf0ba1).
//
// SCOPE (05-CONTEXT D-05-CONTEXT-5): the color-checker subtree
// (_extract_color_checker, run_profile/run_validation, colorchecker.h) and
// the AI WB detection (#ifdef AI_ACTIVATED) are NOT ported — not one line.
// `_check_if_close_to_daylight` (channelmixerrgb.c:1216, daylight-GUI
// ergonomics switch) is not ported either: our panel always shows the
// temperature slider, so the switch has no consumer; the camera-illuminant
// adaptation override it feeds is likewise skipped (user adaptation kept).
// The camera illuminant is a runtime behaviour (commit :3115/process
// per-frame re-detection), not a preset prohibiting a pure-function port —
// see MARK note at the port site. Falls back to the daylight model at the
// params temperature (commit-time fallback, ChannelMixerRGBModule #1).
//
// D65-NATIVE (05-02-DECISIONS D2 applies here unchanged): Lightamer's
// working space is linear Rec2020 D65-native, so RGB⇄XYZ uses
// LabRoundTrip.rec2020ToXYZ/xyzToRec2020 DIRECTLY — no D50 ICC detour.
// The Bradford `p` exponent keeps dt's D50-blue reference 0.818155
// verbatim (channelmixerrgb.c:3146-3150); it is a property of the
// illuminant, not of the pipe.
// ─────────────────────────────────────────────────────────────────────────

/// dt `dt_illuminant_t` (illuminants.h:26-40) — raw values kept for XMP
/// fidelity. DETECT_* (8/9) need the color-checker/AI subtree (v1
/// unported) — the panel hides them; the resolver returns nil for them.
public enum ChannelMixerIlluminant: Int, Codable, Hashable, Sendable {
    case pipe = 0
    case a = 1
    case d = 2
    case e = 3
    case f = 4
    case led = 5
    case blackbody = 6
    case custom = 7
    case detectSurfaces = 8
    case detectEdges = 9
    case camera = 10
}

/// dt `dt_illuminant_fluo_t` (illuminants.h:43-58).
public enum ChannelMixerFluo: Int, Codable, Hashable, Sendable {
    case f1 = 0, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
}

/// dt `dt_illuminant_led_t` (illuminants.h:61-73).
public enum ChannelMixerLED: Int, Codable, Hashable, Sendable {
    case b1 = 0, b2, b3, b4, b5, bh1, rgb1, v1, v2
}

/// dt `dt_adaptation_t` (chromatic_adaptation.h:25-33) — the 5 kernel
/// matrix paths (channelmixer.cl:106-685 one kernel each).
public enum ChannelMixerAdaptation: Int, Codable, Hashable, Sendable {
    case linearBradford = 0
    case cat16 = 1
    case fullBradford = 2
    case xyz = 3
    case rgb = 4
}

/// dt `dt_iop_channelmixer_rgb_version_t` (channelmixerrgb.c:20-25) —
/// the saturation-algorithm generation (luma_chroma branches).
public enum ChannelMixerVersion: Int, Codable, Hashable, Sendable {
    case v1 = 0
    case v2 = 1
    case v3 = 2
}

public enum ChannelMixerMath {

    // MARK: - Constants

    /// dt `NORM_MIN` (math.h:30): 2^-16 floor for norms/scales.
    public static let normMin: Double = 1.52587890625e-05

    /// dt `D50xyY` (colorspace.h:35).
    public static let d50xy: (x: Double, y: Double) = (0.34567, 0.35850)

    /// dt `D50[2]` uv (channelmixerrgb.c:672, colorspace.h u'v').
    public static let d50uv: (u: Double, v: Double) =
        (0.20915914598542354, 0.488075320769787)

    /// dt `fluorescent` table (illuminants.h:86-97).
    public static let fluorescent: [(x: Double, y: Double)] = [
        (0.31310, 0.33727), (0.37208, 0.37529), (0.40910, 0.39430),
        (0.44018, 0.40329), (0.31379, 0.34531), (0.37790, 0.38835),
        (0.31292, 0.32933), (0.34588, 0.35875), (0.37417, 0.37281),
        (0.34609, 0.35986), (0.38052, 0.37713), (0.43695, 0.40441),
    ]

    /// dt `led` table (illuminants.h:108-116).
    public static let led: [(x: Double, y: Double)] = [
        (0.4560, 0.4078), (0.4357, 0.4012), (0.3756, 0.3723),
        (0.3422, 0.3502), (0.3118, 0.3236), (0.4474, 0.4066),
        (0.4557, 0.4211), (0.4560, 0.4548), (0.3781, 0.3775),
    ]

    /// dt Bradford XYZ→LMS (chromatic_adaptation.h:37-39).
    public static let xyzToBradfordLMS: [[Double]] = [
        [0.8951, 0.2664, -0.1614],
        [-0.7502, 1.7135, 0.0367],
        [0.0389, -0.0685, 1.0296],
    ]

    /// dt Bradford LMS→XYZ (chromatic_adaptation.h:42-44).
    public static let bradfordLMSToXYZ: [[Double]] = [
        [0.9870, -0.1471, 0.1600],
        [0.4323, 0.5184, 0.0493],
        [-0.0085, 0.0400, 0.9685],
    ]

    /// dt CAT16 XYZ→LMS (chromatic_adaptation.h:91-93).
    public static let xyzToCAT16LMS: [[Double]] = [
        [0.401288, 0.650173, -0.051461],
        [-0.250268, 1.204414, 0.045854],
        [-0.002079, 0.048952, 0.953127],
    ]

    /// dt CAT16 LMS→XYZ (chromatic_adaptation.h:96-98).
    public static let cat16LMSToXYZ: [[Double]] = [
        [1.862068, -1.011255, 0.149187],
        [0.38752, 0.621447, -0.008974],
        [-0.015841, -0.034123, 1.049964],
    ]

    // MARK: - CCT ⇄ xy (illuminants.h:124-178)

    /// dt `xy_to_CCT` — Lee's approximation, valid 3000-50000K
    /// (illuminants.h:124-136).
    public static func xyToCCT(x: Double, y: Double) -> Double {
        let n = (x - 0.3366) / (y - 0.1735)
        return -949.86315 + 6253.80338 * exp(-n / 0.92159)
            + 28.70599 * exp(-n / 0.20039) + 0.00004 * exp(-n / 0.07125)
    }

    /// dt `CCT_to_xy_daylight` — valid 4000-25000K, else (0,0)
    /// (illuminants.h:138-155).
    public static func cctToXYDaylight(_ t: Double) -> (x: Double, y: Double) {
        var x = 0.0
        if t >= 4000, t <= 7000 {
            x = ((-4.6070e9 / t + 2.9678e6) / t + 0.09911e3) / t + 0.244063
        } else if t > 7000, t <= 25000 {
            x = ((-2.0064e9 / t + 1.9018e6) / t + 0.24748e3) / t + 0.237040
        }
        guard x != 0 else { return (0, 0) }
        return (x, (-3.0 * x + 2.87) * x - 0.275)
    }

    /// dt `CCT_to_xy_blackbody` — valid 1667-25000K, else (0,0)
    /// (illuminants.h:157-178).
    public static func cctToXYBlackbody(_ t: Double) -> (x: Double, y: Double) {
        var x = 0.0
        if t >= 1667, t <= 4000 {
            x = ((-0.2661239e9 / t - 0.2343589e6) / t + 0.8776956e3) / t + 0.179910
        } else if t > 4000, t <= 25000 {
            x = ((-3.0258469e9 / t + 2.1070379e6) / t + 0.2226347e3) / t + 0.240390
        }
        guard x != 0 else { return (0, 0) }
        let y: Double
        if t >= 1667, t <= 2222 {
            y = ((-1.1063814 * x - 1.34811020) * x + 2.18555832) * x - 0.20219683
        } else if t > 2222, t <= 4000 {
            y = ((-0.9549476 * x - 1.37418593) * x + 2.09137015) * x - 0.16748867
        } else {
            y = ((3.0817580 * x - 5.87338670) * x + 3.75112997) * x - 0.37001483
        }
        return (x, y)
    }

    // MARK: - illuminant → xy (illuminants.h:220-324, minus camera/detect)

    /// dt `illuminant_xy_to_XYZ` (illuminants.h:181-187): Y == 1 by
    /// definition for an illuminant.
    public static func xyToXYZ(x: Double, y: Double) -> SIMD3<Double> {
        SIMD3<Double>(x / y, 1.0, (1.0 - x - y) / y)
    }

    /// dt `illuminant_to_xy` for the preset families (illuminants.h:220-324).
    /// Returns nil for `.detectSurfaces/.detectEdges` (unported AI subtree)
    /// and `.camera` (needs the live RAW image + pipe WB channel — NOT
    /// PORTED, see MARK below; the module falls back to the daylight
    /// model). D falls back to the blackbody model when the daylight model
    /// is out of range, and BB falls back to custom (dt fallthrough verbatim).
    public static func illuminantToXY(
        _ illuminant: ChannelMixerIlluminant,
        fluo: ChannelMixerFluo, led: ChannelMixerLED,
        temperature: Double, customX: Double, customY: Double
    ) -> (x: Double, y: Double)? {
        switch illuminant {
        case .pipe: return d50xy
        case .e: return (1.0 / 3.0, 1.0 / 3.0)
        case .a: return (0.44757, 0.40745)
        case .f: return fluorescent[fluo.rawValue]
        case .led: return self.led[led.rawValue]
        case .d:
            let (x, y) = cctToXYDaylight(temperature)
            if x != 0, y != 0 { return (x, y) }
            fallthrough
        case .blackbody:
            let (x, y) = cctToXYBlackbody(temperature)
            if x != 0, y != 0 { return (x, y) }
            return (customX, customY)
        case .custom: return (customX, customY)
        case .camera, .detectSurfaces, .detectEdges: return nil
        }
    }

    // MARK: - Camera WB path — NOT PORTED (illuminants.h:325-453)

    // dt's camera illuminant is a runtime *behaviour*, not a preset:
    // commit calls illuminant_to_xy with the live RAW image + user WB
    // coeffs; process re-runs find_temperature_from_raw_coeffs per frame
    // (channelmixerrgb.c:2200-2228, :2311-2335, :3115-3121). Both need the
    // pipeline RAW WB channel + embedded/adobe XYZ→CAM matrix, which the
    // post-CIRAW commit path has no access to — so .camera falls back to
    // the daylight model at params temperature (ChannelMixerRGBModule
    // divergence #1). The WB_coeffs_to_illuminant_xy helper below was
    // removed as dead code (no caller, no pipe channel to feed it);
    // re-adding it requires the .camera plumbing first.

    // MARK: - Chromatic adaptation (chromatic_adaptation.h)

    public enum AdaptTarget {
        case d50
        case d65
    }

    /// dt Bradford LMS white of D65 (chromatic_adaptation.h:239).
    public static let bradfordD65 = SIMD3<Double>(0.941238, 1.040633, 1.088932)
    /// dt Bradford LMS white of D50 (:267).
    public static let bradfordD50 = SIMD3<Double>(0.996078, 1.020646, 0.818155)
    /// dt CAT16 LMS white of D65 (:300).
    public static let cat16D65 = SIMD3<Double>(0.97553267, 1.01647859, 1.0848344)
    /// dt CAT16 LMS white of D50 (:322).
    public static let cat16D50 = SIMD3<Double>(0.994535, 1.000997, 0.833036)
    /// dt XYZ white of D65 (:352-353).
    public static let xyzD65 = SIMD3<Double>(0.9504285453771807, 1.0, 1.0889003707981277)
    /// dt XYZ white of D50 (:367-368).
    public static let xyzD50 = SIMD3<Double>(0.9642119944211994, 1.0, 0.8251882845188288)

    /// dt `bradford_adapt_D50` generalized to either target
    /// (chromatic_adaptation.h:256-285 + bradford_adapt_D65 :230-250).
    /// `illuminant` = origin white in LMS; `p` precomputed.
    public static func bradfordAdapt(
        _ lmsIn: SIMD3<Double>, illuminant: SIMD3<Double>,
        p: Double, full: Bool, target: AdaptTarget
    ) -> SIMD3<Double> {
        let dest = target == .d50 ? bradfordD50 : bradfordD65
        var t = lmsIn / illuminant
        // "use linear Bradford if B is negative" (dt comment verbatim).
        if full, t.z > 0 { t.z = pow(t.z, p) }
        return dest * t
    }

    /// dt `CAT16_adapt_D50/D65` generalized (chromatic_adaptation.h:290-343).
    /// channelmixerrgb forces full adaptation (D = 1).
    public static func cat16Adapt(
        _ lmsIn: SIMD3<Double>, illuminant: SIMD3<Double>,
        target: AdaptTarget
    ) -> SIMD3<Double> {
        let dest = target == .d50 ? cat16D50 : cat16D65
        return lmsIn * dest / illuminant
    }

    /// dt `XYZ_adapt_D50/D65` generalized (:346-375).
    public static func xyzAdapt(
        _ xyzIn: SIMD3<Double>, illuminant: SIMD3<Double>,
        target: AdaptTarget
    ) -> SIMD3<Double> {
        let dest = target == .d50 ? xyzD50 : xyzD65
        return xyzIn * dest / illuminant
    }

    /// dt `convert_any_XYZ_to_LMS` (chromatic_adaptation.h:193-214).
    public static func xyzToLMS(_ xyz: SIMD3<Double>, adaptation: ChannelMixerAdaptation) -> SIMD3<Double> {
        switch adaptation {
        case .linearBradford, .fullBradford: return mul(xyzToBradfordLMS, xyz)
        case .cat16: return mul(xyzToCAT16LMS, xyz)
        case .xyz, .rgb: return xyz
        }
    }

    /// dt `convert_any_LMS_to_XYZ` (:171-191).
    public static func lmsToXYZ(_ lms: SIMD3<Double>, adaptation: ChannelMixerAdaptation) -> SIMD3<Double> {
        switch adaptation {
        case .linearBradford, .fullBradford: return mul(bradfordLMSToXYZ, lms)
        case .cat16: return mul(cat16LMSToXYZ, lms)
        case .xyz, .rgb: return lms
        }
    }

    // (bradfordAdaptTM removed with the dead WB helper above — it had no
    // other caller. bradfordAdapt is the single Bradford entry point.)

    // MARK: - Gamut mapping + luma/chroma (channelmixerrgb.c:648-769)

    static func xyYToUvY(_ xyY: SIMD3<Double>) -> SIMD3<Double> {
        let d = -2.0 * xyY.x + 12.0 * xyY.y + 3.0
        return SIMD3(4.0 * xyY.x / d, 9.0 * xyY.y / d, xyY.z)
    }

    static func uvYToXY(_ uvY: SIMD3<Double>) -> SIMD3<Double> {
        let d = 6.0 * uvY.x - 16.0 * uvY.y + 12.0
        return SIMD3(9.0 * uvY.x / d, 4.0 * uvY.y / d, uvY.z)
    }

    static func xyYToXYZ(_ xyY: SIMD3<Double>) -> SIMD3<Double> {
        guard xyY.y != 0 else { return .zero }
        return SIMD3(xyY.z * xyY.x / xyY.y, xyY.z, xyY.z * (1.0 - xyY.x - xyY.y) / xyY.y)
    }

    /// dt `_gamut_mapping` (channelmixerrgb.c:648-705) in Double.
    public static func gamutMapping(
        _ input: SIMD3<Double>, compression: Double, clip: Bool
    ) -> SIMD3<Double> {
        let sum = input.x + input.y + input.z
        var xyY = SIMD3(
            sum > 0 ? input.x / sum : d50xy.x,
            sum > 0 ? input.y / sum : d50xy.y,
            input.y)
        var uvY = xyYToUvY(xyY)
        let deltaU = d50uv.u - uvY.x, deltaV = d50uv.v - uvY.y
        let delta = input.y * (deltaU * deltaU + deltaV * deltaV)
        let correction = compression == 0 ? 0.0 : pow(delta, compression)
        for c in 0..<2 {
            let tmp = correction * (c == 0 ? deltaU : deltaV) + (c == 0 ? uvY.x : uvY.y)
            if c == 0 {
                uvY.x = uvY.x > d50uv.u ? max(tmp, d50uv.u) : min(tmp, d50uv.u)
            } else {
                uvY.y = uvY.y > d50uv.v ? max(tmp, d50uv.v) : min(tmp, d50uv.v)
            }
        }
        xyY = uvYToXY(uvY)
        if clip {
            xyY.x = max(xyY.x, 0); xyY.y = max(xyY.y, 0)
        }
        xyY.y = max(xyY.y, normMin)
        let scale = xyY.x + xyY.y
        if scale >= 1.0 { xyY.x /= scale; xyY.y /= scale }
        return xyYToXYZ(xyY)
    }

    public static func euclideanNorm(_ v: SIMD3<Double>) -> Double {
        max(sqrt(v.x * v.x + v.y * v.y + v.z * v.z), normMin)
    }

    public static func downscale(_ v: inout SIMD3<Double>, _ s: Double) {
        v /= (s > normMin) ? (s + normMin) : normMin
    }

    public static func upscale(_ v: inout SIMD3<Double>, _ s: Double) {
        v *= (s > normMin) ? (s + normMin) : normMin
    }

    /// dt `_luma_chroma` (channelmixerrgb.c:706-769) in Double.
    /// `saturation`/`lightness` are the COMMIT-DERIVED vectors (already
    /// negated/normalized per commit_params :3067-3090).
    public static func lumaChroma(
        _ input: SIMD3<Double>, saturation: SIMD3<Double>,
        lightness: SIMD3<Double>, version: ChannelMixerVersion
    ) -> SIMD3<Double> {
        var norm = euclideanNorm(input)
        let avg = max((input.x + input.y + input.z) / 3.0, normMin)
        guard norm > 0, avg > 0 else { return input }
        let mix = input.x * lightness.x + input.y * lightness.y + input.z * lightness.z
        if version == .v3 { norm *= 0.5773502691896258 }
        var output = input / norm
        let coeffRatio: Double
        if version == .v1 {
            coeffRatio = (1.0 - output.x) * saturation.x
                + (1.0 - output.y) * saturation.y + (1.0 - output.z) * saturation.z
        } else {
            coeffRatio = (output.x * saturation.x + output.y * saturation.y
                + output.z * saturation.z) / 3.0
        }
        let minR = output.x < 0 ? output.x : 0.0
        let minG = output.y < 0 ? output.y : 0.0
        let minB = output.z < 0 ? output.z : 0.0
        output.x = max((1.0 - output.x) * coeffRatio + output.x, minR)
        output.y = max((1.0 - output.y) * coeffRatio + output.y, minG)
        output.z = max((1.0 - output.z) * coeffRatio + output.z, minB)
        if version == .v3 { norm /= euclideanNorm(output) * 0.5773502691896258 }
        norm *= max(1.0 + mix / avg, 0.0)
        return output * norm
    }

    // MARK: - Matrix helpers

    public static func mul(_ m: [[Double]], _ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z,
            m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
            m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z)
    }

    public static func mul(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        [
            [a[0][0] * b[0][0] + a[0][1] * b[1][0] + a[0][2] * b[2][0],
             a[0][0] * b[0][1] + a[0][1] * b[1][1] + a[0][2] * b[2][1],
             a[0][0] * b[0][2] + a[0][1] * b[1][2] + a[0][2] * b[2][2]],
            [a[1][0] * b[0][0] + a[1][1] * b[1][0] + a[1][2] * b[2][0],
             a[1][0] * b[0][1] + a[1][1] * b[1][1] + a[1][2] * b[2][1],
             a[1][0] * b[0][2] + a[1][1] * b[1][2] + a[1][2] * b[2][2]],
            [a[2][0] * b[0][0] + a[2][1] * b[1][0] + a[2][2] * b[2][0],
             a[2][0] * b[0][1] + a[2][1] * b[1][1] + a[2][2] * b[2][1],
             a[2][0] * b[0][2] + a[2][1] * b[1][2] + a[2][2] * b[2][2]],
        ]
    }
}

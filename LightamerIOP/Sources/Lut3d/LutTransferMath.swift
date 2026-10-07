import Foundation
import LightamerCore
import simd

// ─────────────────────────────────────────────────────────────────────────
// LutTransferMath (Plan M3-1-01 T1, M2GRADE-08 / KD-2) — the Float64
// transfer-curve function family for LUT authoring-encoding modeling.
//
// PROVENANCE (GPL zero-copy discipline): the math comes from the PUBLIC
// standards and manufacturer white papers — SMPTE ST 2065-1 / ACES
// S-2014-004 (ACEScc) + S-2016-002 (ACEScct), ARRI A0042 (LogC4) /
// A0011 (LogC3 EI 800), Sony S-Log3 technical summary, Canon C-Log3
// white paper (v1.2 normalized form), Fujifilm F-Log spec, Panasonic
// V-Log/V-Gamut manual, Nikon N-Log specification v1.0.0, Apple Log
// white paper, IEC 61966-2-1 (sRGB). The Alcedo catalog is referenced
// for the TABLE SHAPE only (row set / field form), never numerics.
//
// Float64 (the CPU authority) — the bake composes these per voxel in
// double precision before the rgba32Float upload (L048: log-domain
// op comparisons live in decode space; the f32 table storage is the
// documented representation step).
//
// DISPLAY ARM (checker E1/M3): display-referred rows mediate through
// display light with 1.0 = 100 nits (the Alcedo `DisplayEncode/
// DisplayDecode` semantics). `DrtEotfMath` is peak-normalized (1.0 =
// peak nits), so the adapter applies `× peak/100` (or its inverse)
// EXACTLY ONCE here — callers must not re-scale (double scaling =
// a ×100² peak error). SDR rows carry peak = 100, where the factor is
// naturally 1 — no `peak == 0` special case exists (checker M3).
// ─────────────────────────────────────────────────────────────────────────

/// The transfer curve of a `LutEncodingCatalog` row. Adding a catalog row
/// with a new curve = adding a case here (every exhaustive switch in this
/// file breaks at compile time — the M2DRT-06 discipline).
public enum LutTransferCurve: String, Codable, Sendable, CaseIterable {
    // Scene (camera log family).
    case acescc
    case acescct
    case logC4
    case logC3
    case slog3
    case clog3
    case flog
    case vlog
    case nlog
    case appleLog
    // Scene (working space identity).
    case linear
    // Display family.
    case srgb
    case bt1886
    case gamma22
    case pq
    case hlg
}

/// The Float64 curve authority (the golden target; M2-6 `DrtEotfMath`
/// supplies the display family — this file ZERO-DIFFS that file and only
/// routes through it).
public enum LutTransferMath {

    // MARK: - ACEScc (S-2014-004)

    public static let acesccOffset: Double = 9.72
    public static let acesccDivisor: Double = 17.52
    /// 2^-16 — the ACEScc toe pivot inside the half-stop piece.
    public static let acesccA: Double = Foundation.pow(2, -16)
    /// 2^-15 — the half-stop piece's upper break (S-2014-004: the
    /// `log2(2^-16 + 0.5x)` piece covers 0 < x < 2^-15; the decode knee
    /// (9.72 − 15)/17.52 is its exact image).
    public static let acesccMidBreak: Double = Foundation.pow(2, -15)
    /// The constant code for x <= 0: (log2(2^-16) + 9.72) / 17.52.
    public static let acesccBlackCode: Double =
        (Foundation.log2(acesccA) + acesccOffset) / acesccDivisor
    /// The 2^16 high knee: (log2(65504) + 9.72) / 17.52.
    public static let acesccWhiteCode: Double =
        (Foundation.log2(65504.0) + acesccOffset) / acesccDivisor

    public static func acesccEncode(_ x: Double) -> Double {
        if x < 0 { return acesccBlackCode }
        if x < acesccMidBreak {
            // The (0, 2^-15) half-stop piece (S-2014-004).
            return (Foundation.log2(acesccA + 0.5 * x) + acesccOffset) / acesccDivisor
        }
        return (Foundation.log2(x) + acesccOffset) / acesccDivisor
    }

    /// The low knee: (9.72 − 15) / 17.52.
    public static let acesccDecodeKnee: Double =
        (acesccOffset - 15.0) / acesccDivisor

    public static func acesccDecode(_ c: Double) -> Double {
        if c < acesccDecodeKnee {
            return (Foundation.pow(2, c * acesccDivisor - acesccOffset) - acesccA) * 2
        }
        let x = Foundation.pow(2, c * acesccDivisor - acesccOffset)
        return c >= acesccWhiteCode ? min(x, 65504) : x
    }

    // MARK: - ACEScct (S-2016-002)

    public static let acescctXBrk: Double = 0.0078125
    public static let acescctYBrk: Double = 0.155251141552511
    public static let acescctA: Double = 10.5402377416545
    public static let acescctB: Double = 0.0729055341958355

    public static func acescctEncode(_ x: Double) -> Double {
        x <= acescctXBrk
            ? acescctA * x + acescctB
            : (Foundation.log2(x) + acesccOffset) / acesccDivisor
    }

    public static func acescctDecode(_ c: Double) -> Double {
        c > acescctYBrk
            ? Foundation.pow(2, c * acesccDivisor - acesccOffset)
            : (c - acescctB) / acescctA
    }

    // MARK: - ARRI LogC4 (A0042 — constants COMPUTED from the published
    // definitions, never hand-copied decimals)

    /// a = (2^18 − 16) / 117.45
    public static let logC4A: Double = (Foundation.pow(2, 18) - 16) / 117.45
    /// b = (1023 − 95) / 1023
    public static let logC4B: Double = (1023.0 - 95.0) / 1023.0
    /// c = 95 / 1023
    public static let logC4C: Double = 95.0 / 1023.0
    /// s = (7·ln2·2^(7 − 14c/b)) / (a·b) — the linear-toe slope.
    public static let logC4S: Double =
        (7 * Foundation.log(2) * Foundation.pow(2, 7 - 14 * logC4C / logC4B))
        / (logC4A * logC4B)
    /// t = (2^(14·(−c/b) + 6) − 64) / a — the toe cut on scene linear.
    public static let logC4T: Double =
        (Foundation.pow(2, 14 * (-logC4C / logC4B) + 6) - 64) / logC4A

    public static func logC4Encode(_ x: Double) -> Double {
        if x >= logC4T {
            return (Foundation.log2(logC4A * x + 64) - 6) / 14 * logC4B + logC4C
        }
        return (x - logC4T) / logC4S
    }

    public static func logC4Decode(_ c: Double) -> Double {
        if c >= 0 {
            return (Foundation.pow(2, 14 * ((c - logC4C) / logC4B) + 6) - 64) / logC4A
        }
        return c * logC4S + logC4T
    }

    // MARK: - ARRI LogC3, EI 800 (A0011 — the "Linear Scene Exposure
    // Factor" camera-native method)

    public static let logC3Cut: Double = 0.010591
    public static let logC3A: Double = 5.555556
    public static let logC3B: Double = 0.052272
    public static let logC3C: Double = 0.247190
    public static let logC3D: Double = 0.385537
    public static let logC3E: Double = 5.367655
    public static let logC3F: Double = 0.092809
    /// The decode knee in code space: e·cut + f.
    public static let logC3Knee: Double = logC3E * logC3Cut + logC3F

    public static func logC3Encode(_ x: Double) -> Double {
        if x > logC3Cut {
            return logC3C * Foundation.log10(logC3A * x + logC3B) + logC3D
        }
        return logC3E * x + logC3F
    }

    public static func logC3Decode(_ c: Double) -> Double {
        if c > logC3Knee {
            return (Foundation.pow(10, (c - logC3D) / logC3C) - logC3B) / logC3A
        }
        return (c - logC3F) / logC3E
    }

    // MARK: - Sony S-Log3

    public static let slog3KneeScene: Double = 0.01125000
    public static let slog3KneeCode: Double = 171.2102946929 / 1023.0

    public static func slog3Encode(_ x: Double) -> Double {
        if x >= slog3KneeScene {
            return (420.0 + 261.5 * Foundation.log10((x + 0.01) / (0.18 + 0.01))) / 1023.0
        }
        return (x * (171.2102946929 - 95.0) / slog3KneeScene + 95.0) / 1023.0
    }

    public static func slog3Decode(_ c: Double) -> Double {
        if c >= slog3KneeCode {
            return Foundation.pow(10, (c * 1023.0 - 420.0) / 261.5) * 0.19 - 0.01
        }
        return (c * 1023.0 - 95.0) * slog3KneeScene / (171.2102946929 - 95.0)
    }

    // MARK: - Canon C-Log3 (white paper v1.2 — normalized full-range form;
    // the input is scene REFLECTION, so 18% gray enters as x/0.9 = 0.2
    // exposure — mirrored on decode by ×0.9)

    public static let clog3LowBreak: Double = 0.097465473
    public static let clog3HighBreak: Double = 0.15277891

    public static func clog3Encode(_ reflection: Double) -> Double {
        let x = reflection / 0.9
        if x < -0.014 {
            return -0.36726845 * Foundation.log10(1 - 14.98325 * x) + 0.12783901
        }
        if x <= 0.014 {
            return 1.9754798 * x + 0.12512219
        }
        return 0.36726845 * Foundation.log10(14.98325 * x + 1) + 0.12240537
    }

    public static func clog3Decode(_ c: Double) -> Double {
        let x: Double
        if c < clog3LowBreak {
            x = -(Foundation.pow(10, (0.12783901 - c) / 0.36726845) - 1) / 14.98325
        } else if c <= clog3HighBreak {
            x = (c - 0.12512219) / 1.9754798
        } else {
            x = (Foundation.pow(10, (c - 0.12240537) / 0.36726845) - 1) / 14.98325
        }
        return x * 0.9
    }

    // MARK: - Fujifilm F-Log

    public static let flogCutScene: Double = 0.00089
    public static let flogCutCode: Double = 0.100537775223865

    public static func flogEncode(_ x: Double) -> Double {
        if x < flogCutScene {
            return 8.735631 * x + 0.092864
        }
        return 0.344676 * Foundation.log10(0.555556 * x + 0.009468) + 0.790453
    }

    public static func flogDecode(_ c: Double) -> Double {
        if c < flogCutCode {
            return (c - 0.092864) / 8.735631
        }
        return Foundation.pow(10, (c - 0.790453) / 0.344676) / 0.555556 - 0.009468 / 0.555556
    }

    // MARK: - Panasonic V-Log

    public static let vlogCutScene: Double = 0.01
    public static let vlogCutCode: Double = 0.181

    public static func vlogEncode(_ x: Double) -> Double {
        if x < vlogCutScene {
            return 5.6 * x + 0.125
        }
        return 0.241514 * Foundation.log10(x + 0.00873) + 0.598206
    }

    public static func vlogDecode(_ c: Double) -> Double {
        if c < vlogCutCode {
            return (c - 0.125) / 5.6
        }
        return Foundation.pow(10, (c - 0.598206) / 0.241514) - 0.00873
    }

    // MARK: - Nikon N-Log (specification v1.0.0)

    public static let nlogCutScene: Double = 0.328
    public static let nlogCutCode: Double = 452.0 / 1023.0
    public static let nlogA: Double = 650.0 / 1023.0
    public static let nlogB: Double = 0.0075
    public static let nlogC: Double = 150.0 / 1023.0
    public static let nlogD: Double = 619.0 / 1023.0

    public static func nlogEncode(_ x: Double) -> Double {
        if x < nlogCutScene {
            // Real cube root (negative scene values stay real; Foundation
            // pow(x, 1/3) would NaN below zero).
            return nlogA * cbrt(x + nlogB)
        }
        return nlogC * Foundation.log(x) + nlogD
    }

    public static func nlogDecode(_ c: Double) -> Double {
        if c < nlogCutCode {
            let t = c / nlogA
            return t * t * t - nlogB
        }
        return Foundation.exp((c - nlogD) / nlogC)
    }

    // MARK: - Apple Log (white paper 2023)

    public static let appleLogR0: Double = -0.05641088
    public static let appleLogRt: Double = 0.01
    public static let appleLogSigma: Double = 47.28711236
    public static let appleLogBeta: Double = 0.00964052
    public static let appleLogGamma: Double = 0.08550479
    public static let appleLogDelta: Double = 0.69336945
    /// P_t = sigma·(R_t − R_0)² — the quadratic/log knee in code space.
    public static let appleLogPt: Double =
        appleLogSigma * Foundation.pow(appleLogRt - appleLogR0, 2)

    public static func appleLogEncode(_ r: Double) -> Double {
        if r < appleLogR0 { return 0 }
        if r < appleLogRt {
            return appleLogSigma * Foundation.pow(r - appleLogR0, 2)
        }
        return appleLogGamma * Foundation.log2(r + appleLogBeta) + appleLogDelta
    }

    public static func appleLogDecode(_ p: Double) -> Double {
        if p < 0 { return appleLogR0 }
        if p < appleLogPt {
            return Foundation.sqrt(p / appleLogSigma) + appleLogR0
        }
        return Foundation.pow(2, (p - appleLogDelta) / appleLogGamma) - appleLogBeta
    }

    // MARK: - sRGB (IEC 61966-2-1, sign-symmetric)

    public static func srgbEncodeChannel(_ v: Double) -> Double {
        let sign = v < 0 ? -1.0 : 1.0
        let a = abs(v)
        return a <= 0.0031308
            ? sign * 12.92 * a
            : sign * (1.055 * Foundation.pow(a, 1 / 2.4) - 0.055)
    }

    public static func srgbDecodeChannel(_ v: Double) -> Double {
        let sign = v < 0 ? -1.0 : 1.0
        let a = abs(v)
        return a <= 0.04045 ? sign * a / 12.92 : sign * Foundation.pow((a + 0.055) / 1.055, 2.4)
    }

    // MARK: - Scene dispatch (exhaustive — no default arms)

    /// Scene-linear → code (per channel). Scene rows only (display rows
    /// route through `displayEncode`).
    public static func encode(_ curve: LutTransferCurve, _ x: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(encodeChannel(curve, x.x), encodeChannel(curve, x.y), encodeChannel(curve, x.z))
    }

    /// Code → scene-linear (the exact inverse per curve).
    public static func decode(_ curve: LutTransferCurve, _ c: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(decodeChannel(curve, c.x), decodeChannel(curve, c.y), decodeChannel(curve, c.z))
    }

    public static func encodeChannel(_ curve: LutTransferCurve, _ v: Double) -> Double {
        switch curve {
        case .acescc: return acesccEncode(v)
        case .acescct: return acescctEncode(v)
        case .logC4: return logC4Encode(v)
        case .logC3: return logC3Encode(v)
        case .slog3: return slog3Encode(v)
        case .clog3: return clog3Encode(v)
        case .flog: return flogEncode(v)
        case .vlog: return vlogEncode(v)
        case .nlog: return nlogEncode(v)
        case .appleLog: return appleLogEncode(v)
        case .linear: return v
        case .srgb: return srgbEncodeChannel(v)
        case .bt1886: return DrtEotfMath.powerEncode(v, gamma: 2.4)
        case .gamma22: return DrtEotfMath.powerEncode(v, gamma: 2.2)
        case .pq: return DrtEotfMath.st2084EncodeY(v, peak: DrtEotfMath.st2084PeakNits)
        case .hlg: return DrtEotfMath.hlgEncode(SIMD3(v, v, v), peak: DrtEotfMath.hlgReferencePeakNits).x
        }
    }

    public static func decodeChannel(_ curve: LutTransferCurve, _ c: Double) -> Double {
        switch curve {
        case .acescc: return acesccDecode(c)
        case .acescct: return acescctDecode(c)
        case .logC4: return logC4Decode(c)
        case .logC3: return logC3Decode(c)
        case .slog3: return slog3Decode(c)
        case .clog3: return clog3Decode(c)
        case .flog: return flogDecode(c)
        case .vlog: return vlogDecode(c)
        case .nlog: return nlogDecode(c)
        case .appleLog: return appleLogDecode(c)
        case .linear: return c
        case .srgb: return srgbDecodeChannel(c)
        case .bt1886: return DrtEotfMath.powerDecode(c, gamma: 2.4)
        case .gamma22: return DrtEotfMath.powerDecode(c, gamma: 2.2)
        case .pq: return DrtEotfMath.st2084DecodeY(c, peak: DrtEotfMath.st2084PeakNits)
        case .hlg: return DrtEotfMath.hlgDecode(SIMD3(c, c, c), peak: DrtEotfMath.hlgReferencePeakNits).x
        }
    }

    // MARK: - Display mediator (1.0 light = 100 nits; peak applied ONCE)

    /// Codes → display light in 100-nit units (the Alcedo `DisplayDecode`
    /// middle): the peak-normalized `DrtEotfMath` result is scaled by
    /// `peak/100` exactly once here.
    public static func displayDecode(
        _ curve: LutTransferCurve, _ code: SIMD3<Double>, peakNits: Double
    ) -> SIMD3<Double> {
        let scale = peakNits / 100.0
        switch curve {
        case .pq:
            let normalized = SIMD3(
                DrtEotfMath.st2084DecodeY(code.x, peak: peakNits),
                DrtEotfMath.st2084DecodeY(code.y, peak: peakNits),
                DrtEotfMath.st2084DecodeY(code.z, peak: peakNits))
            return normalized * scale
        case .hlg:
            return DrtEotfMath.hlgDecode(code, peak: peakNits) * scale
        case .bt1886:
            return DrtEotfMath.decode(.bt1886, rgb: code, peak: peakNits) * scale
        case .gamma22:
            return DrtEotfMath.decode(.gamma22, rgb: code, peak: peakNits) * scale
        case .srgb:
            return SIMD3(
                srgbDecodeChannel(code.x), srgbDecodeChannel(code.y),
                srgbDecodeChannel(code.z)) * scale
        // Scene curves are unreachable through display catalog rows (the
        // referral column routes them to `decode`); the scene math keeps
        // the switch exhaustive without a runtime trap.
        default:
            return decode(curve, code)
        }
    }

    /// Display light (100-nit units) → codes (the Alcedo `DisplayEncode`
    /// middle): inputs scale by `100/peak` exactly once, then encode.
    public static func displayEncode(
        _ curve: LutTransferCurve, _ light: SIMD3<Double>, peakNits: Double
    ) -> SIMD3<Double> {
        let normalized = light * (100.0 / peakNits)
        switch curve {
        case .pq:
            return SIMD3(
                DrtEotfMath.st2084EncodeY(clamp01(normalized.x), peak: peakNits),
                DrtEotfMath.st2084EncodeY(clamp01(normalized.y), peak: peakNits),
                DrtEotfMath.st2084EncodeY(clamp01(normalized.z), peak: peakNits))
        case .hlg:
            return DrtEotfMath.hlgEncode(clamp3(normalized), peak: peakNits)
        case .bt1886:
            return DrtEotfMath.encode(.bt1886, rgb: clamp3(normalized), peak: peakNits)
        case .gamma22:
            return DrtEotfMath.encode(.gamma22, rgb: clamp3(normalized), peak: peakNits)
        case .srgb:
            return SIMD3(
                srgbEncodeChannel(clamp01(normalized.x)),
                srgbEncodeChannel(clamp01(normalized.y)),
                srgbEncodeChannel(clamp01(normalized.z)))
        // Scene curves unreachable through display rows (see displayDecode).
        default:
            return encode(curve, normalized)
        }
    }

    private static func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }

    private static func clamp3(_ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(clamp01(v.x), clamp01(v.y), clamp01(v.z))
    }
}

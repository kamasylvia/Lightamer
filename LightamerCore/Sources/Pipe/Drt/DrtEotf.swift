import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────────
// DrtEotf — the seven-function encoding core for the Display Transform tail
// (Plan M2-6-1 T2, KD-2; M2DRT-04 encoding leg; the M2-9 export leg reuses
// the same functions through this seam — OQ-7-A's "record + pixel → encoded
// plane" pure-function face).
//
// SEVEN FUNCTIONS: linear (identity) / st2084 (PQ, ITU-R BT.2100) / hlg
// (BT.2100 reference OOTF γ=1.2 + inverse OETF, 1000-nit reference) /
// gamma26 / bt1886 / gamma22 / gamma18. Encode + decode per function.
//
// ── CONSTANT SINGLE SOURCE (KD-2 双落笔纪律) ──
// DrtEotf.swift is THE constant source; `DrtEotfKernels.metal` re-states the
// same derivations in float for the GPU — a re-statement, never a second
// authority. The tests pin constants parity via the
// `drt_eotf_constants_probe` kernel (every constant read back from the GPU
// and compared ≤1e-6). Do NOT add a constant to one side only.
//
// ── TERMINAL FORMS (DECISIONS §D2) ──
// • BT.1886: Lb = 0 (β = 0) → the pure 2.4 power. The dctl reference applies
//   a bare 2.4 power (`eotf_p = 2 + eotf*0.2`); true BT.1886 black lifting is
//   a DISPLAY calibration concern, not a content-encoding one — the encode
//   side has no Lb to lift toward.
// • HLG OOTF: the BT.2100 REFERENCE environment (γ = 1.2 fixed, 1000-nit
//   reference peak) — the dctl eotf_hlg uses the same fixed form; ambient-
//   -dependent γ modulation (Table 5's general γ) is not modeled.
// • Input domain: peak-normalized display linear (1.0 = `peak` nits — the
//   DrtMethodBox output contract, KD-4). st2084 normalizes by /10000 nits,
//   hlg by /1000 nits; the SDR power family and bt1886 use the value as-is
//   (0..1 = 0..peak).
// • Clamping: st2084/hlg and the SDR power family clamp the input to [0,1]
//   before encoding (PQ/HLG codes are defined on [0,1]; the SDR display range
//   ends at white — the D-COL4 clamp home moves here for DRT tails).
//   `.linear` is the deliberate exception: identity, UNclamped (the EDR
//   linear-leg semantics — >1.0 headroom values must survive).
// • Peak semantics (KD-2): `peak` enters ONLY st2084 and hlg; the SDR family
//   output is independent of peak (test-pinned).
// ─────────────────────────────────────────────────────────────────────────────

public extension DrtEotf {

    /// The kernel/uniform ordinal — mirrors the Alcedo hpp `DrtEotf` int
    /// enum order (hpp :35-43). Part of the GPU contract (the uniform
    /// buffer carries this id; MSL switches on it exhaustively).
    var kernelIndex: Int {
        switch self {
        case .linear: return 0
        case .st2084: return 1
        case .hlg: return 2
        case .gamma26: return 3
        case .bt1886: return 4
        case .gamma22: return 5
        case .gamma18: return 6
        case .srgbPiecewise: return 7 // Alcedo hpp:46 `SrgbPiecewise = 7` (M4-1-01 KD-8)
        }
    }

    /// The inverse gamma (encode exponent denominator) of the power family.
    /// Non-power cases are unreachable by construction (callers only ask
    /// the power family).
    var powerExponent: Double {
        switch self {
        case .gamma26: return 2.6
        case .bt1886: return 2.4
        case .gamma22: return 2.2
        case .gamma18: return 1.8
        case .linear, .st2084, .hlg, .srgbPiecewise: return 2.2 // never consumed
        }
    }
}

/// The Float64 reference math (the CPU authority — the golden target for
/// the Metal kernels and the M2-9 export encoding reference).
public enum DrtEotfMath {

    // MARK: BT.2100 ST 2084 (PQ) constants — the canonical ITU fractions.

    public static let st2084M1: Double = 2610.0 / 16384.0
    public static let st2084M2: Double = 2523.0 / 32.0
    public static let st2084C1: Double = 107.0 / 128.0
    public static let st2084C2: Double = 2413.0 / 128.0
    public static let st2084C3: Double = 2392.0 / 128.0

    /// BT.2100 HLG reference OOTF exponent (γ = 1.2, the 1000-nit reference
    /// viewing environment — DECISIONS §D2).
    public static let hlgGamma: Double = 1.2
    /// HLG reference peak (nits) — the OOTF's home container.
    public static let hlgReferencePeakNits: Double = 1000.0
    /// ST 2084 absolute domain (nits) — 1.0 code = 10000 nits.
    public static let st2084PeakNits: Double = 10000.0

    /// HLG inverse-OETF constants (the BT.2100 piecewise form; the same
    /// 12-digit literals the reference EOTF implementations carry).
    public static let hlgA: Double = 0.17883277
    public static let hlgB: Double = 0.28466892
    public static let hlgC: Double = 0.55991073

    // MARK: Safe power (the reference's spowf semantics — DECISIONS §D2)

    /// `x <= 0 → x` guard: keeps the HLG OOTF scaling finite at black
    /// (0 × pow(0, negative) would be 0×inf = NaN without it).
    public static func safePow(_ x: Double, _ p: Double) -> Double {
        x <= 0 ? x : Foundation.pow(x, p)
    }

    // MARK: - ST 2084 (PQ)

    /// Signal code for the normalized linear luminance `y` (0..1 = 0..peak).
    public static func st2084EncodeY(_ y: Double, peak: Double) -> Double {
        let yNits = min(max(y, 0), 1) * peak / st2084PeakNits
        let yPow = Foundation.pow(yNits, st2084M1)
        return Foundation.pow(
            (st2084C1 + st2084C2 * yPow) / (1 + st2084C3 * yPow), st2084M2)
    }

    /// The exact inverse over the VALID code range (any code an encode can
    /// emit). Codes below the PQ black floor are outside the defined domain;
    /// the outer power carries the reference's spowf guard (a ≤ 0 → a) so
    /// such garbage input degrades to a finite negative instead of NaN.
    public static func st2084DecodeY(_ code: Double, peak: Double) -> Double {
        let ePow = Foundation.pow(min(max(code, 0), 1), 1 / st2084M2)
        let fraction = (ePow - st2084C1) / (st2084C2 - st2084C3 * ePow)
        let yNits = safePow(fraction, 1 / st2084M1)
        return yNits * st2084PeakNits / peak
    }

    // MARK: - HLG (BT.2100 reference OOTF γ=1.2, 1000-nit reference)

    /// The OETF inverse (scene linear channel → signal).
    public static func hlgOETFInverse(_ scene: Double) -> Double {
        scene <= 1.0 / 12.0
            ? Foundation.sqrt(3 * scene)
            : hlgA * Foundation.log(12 * scene - hlgB) + hlgC
    }

    /// The OETF (signal → scene linear channel).
    public static func hlgOETF(_ signal: Double) -> Double {
        signal <= 0.5
            ? signal * signal / 3
            : (Foundation.exp((signal - hlgC) / hlgA) + hlgB) / 12
    }

    /// Encode peak-normalized display-linear RGB → HLG signal RGB.
    /// The OOTF runs in the ABSOLUTE 1000-nit domain: convert in
    /// (×peak/1000), apply the inverse OOTF (Yd luminance of the absolute
    /// rgb), inverse OETF per channel. Round-trips identically for ANY peak
    /// because decode mirrors the same domain hop.
    public static func hlgEncode(_ rgb: SIMD3<Double>, peak: Double) -> SIMD3<Double> {
        let absolute = clamp01(rgb) * (peak / hlgReferencePeakNits)
        let yd = 0.2627 * absolute.x + 0.6780 * absolute.y + 0.0593 * absolute.z
        let scale = safePow(yd, (1 - hlgGamma) / hlgGamma)
        let scaled = absolute * scale
        return SIMD3(
            hlgOETFInverse(scaled.x), hlgOETFInverse(scaled.y), hlgOETFInverse(scaled.z))
    }

    /// Decode HLG signal RGB → peak-normalized display-linear RGB
    /// (OETF per channel, forward OOTF in the absolute 1000-nit domain,
    /// then back to the peak-normalized container).
    public static func hlgDecode(_ rgb: SIMD3<Double>, peak: Double) -> SIMD3<Double> {
        let scene = SIMD3(hlgOETF(rgb.x), hlgOETF(rgb.y), hlgOETF(rgb.z))
        let ys = 0.2627 * scene.x + 0.6780 * scene.y + 0.0593 * scene.z
        let scale = safePow(ys, hlgGamma - 1)
        return scene * scale * (hlgReferencePeakNits / peak)
    }

    // MARK: - sRGB piecewise (IEC 61966-2-1 — the M4-1-01 KD-8 case)

    /// The sRGB EOTF: code → linear (the exact standard piecewise).
    public static func srgbPiecewiseDecode(_ code: Double) -> Double {
        let c = min(max(code, 0), 1)
        return c <= 0.04045 ? c / 12.92 : Foundation.pow((c + 0.055) / 1.055, 2.4)
    }

    /// The sRGB inverse EOTF: linear → code. Clamps to [0,1] (the SDR
    /// display range — the same D-COL4 home as the power family).
    public static func srgbPiecewiseEncode(_ linear: Double) -> Double {
        let v = min(max(linear, 0), 1)
        return v <= 0.0031308 ? v * 12.92 : 1.055 * Foundation.pow(v, 1 / 2.4) - 0.055
    }

    // MARK: - Power family (gamma26 / bt1886 / gamma22 / gamma18)

    /// SDR power encode (the pure `1/γ` power; bt1886's terminal form Lb=0
    /// collapses to γ=2.4 — DECISIONS §D2). Clamps to [0,1] (D-COL4 home).
    public static func powerEncode(_ x: Double, gamma: Double) -> Double {
        Foundation.pow(min(max(x, 0), 1), 1 / gamma)
    }

    /// The exact inverse.
    public static func powerDecode(_ code: Double, gamma: Double) -> Double {
        Foundation.pow(min(max(code, 0), 1), gamma)
    }

    // MARK: - Dispatch (exhaustive — no default arms, M2DRT-06 discipline)

    /// Encode peak-normalized display-linear RGB → the EOTF's code values.
    public static func encode(
        _ eotf: DrtEotf, rgb: SIMD3<Double>, peak: Double
    ) -> SIMD3<Double> {
        switch eotf {
        case .linear:
            return rgb
        case .st2084:
            return SIMD3(
                st2084EncodeY(rgb.x, peak: peak),
                st2084EncodeY(rgb.y, peak: peak),
                st2084EncodeY(rgb.z, peak: peak))
        case .hlg:
            return hlgEncode(rgb, peak: peak)
        case .gamma26:
            return perChannel(rgb) { powerEncode($0, gamma: 2.6) }
        case .bt1886:
            return perChannel(rgb) { powerEncode($0, gamma: 2.4) }
        case .gamma22:
            return perChannel(rgb) { powerEncode($0, gamma: 2.2) }
        case .gamma18:
            return perChannel(rgb) { powerEncode($0, gamma: 1.8) }
        case .srgbPiecewise:
            return perChannel(rgb) { srgbPiecewiseEncode($0) }
        }
    }

    /// Decode code values → peak-normalized display-linear RGB (the exact
    /// inverse per function).
    public static func decode(
        _ eotf: DrtEotf, rgb: SIMD3<Double>, peak: Double
    ) -> SIMD3<Double> {
        switch eotf {
        case .linear:
            return rgb
        case .st2084:
            return SIMD3(
                st2084DecodeY(rgb.x, peak: peak),
                st2084DecodeY(rgb.y, peak: peak),
                st2084DecodeY(rgb.z, peak: peak))
        case .hlg:
            return hlgDecode(rgb, peak: peak)
        case .gamma26:
            return perChannel(rgb) { powerDecode($0, gamma: 2.6) }
        case .bt1886:
            return perChannel(rgb) { powerDecode($0, gamma: 2.4) }
        case .gamma22:
            return perChannel(rgb) { powerDecode($0, gamma: 2.2) }
        case .gamma18:
            return perChannel(rgb) { powerDecode($0, gamma: 1.8) }
        case .srgbPiecewise:
            return perChannel(rgb) { srgbPiecewiseDecode($0) }
        }
    }

    /// Per-channel map (the power family is channel-independent).
    private static func perChannel(
        _ rgb: SIMD3<Double>, _ f: (Double) -> Double
    ) -> SIMD3<Double> {
        SIMD3(f(rgb.x), f(rgb.y), f(rgb.z))
    }

    /// Element-wise clamp to [0,1].
    private static func clamp01(_ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            min(max(v.x, 0), 1), min(max(v.y, 0), 1), min(max(v.z, 0), 1))
    }
}

// MARK: - GPU uniform bridge

/// The uniform buffer layout shared with `DrtEotfUniforms` in
/// `DrtEotfKernels.metal` (8 bytes: uint + float, alignment 4 on both
/// sides — the tests pin the layout sizes).
public struct DrtEotfUniforms: Sendable {
    public var eotf: UInt32
    public var peak: Float

    public init(eotf: DrtEotf, peak: Float) {
        self.eotf = UInt32(eotf.kernelIndex)
        self.peak = peak
    }
}

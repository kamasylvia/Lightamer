import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────
// LutColorspaceMatrices (Plan 12-5 T2/T4, RESEARCH §6.6) — the application
// color-space assets for the lut3d iop: working linear-Rec2020 → LUT domain
// (fwd) and back (inv), row-major 3×3 tuples consumed by the fused kernel
// uniforms.
//
// Derivation (same generator method as ColorOutModule's header comment —
// `.work/plans/02-04/matrix-derive.swift` lineage; the sRGB/P3 numbers
// below agree with ColorOut's published constants TO ALL PRINTED DIGITS,
// which is the "同源单实现" verification):
//
//   M = XYZ→RGB(target) · Bradford(D50→D65 if needed) · RGB→XYZ(Rec2020)
//
// - sRGB (BT.709, D65) / Display P3 (DCI-P3 D65, SMPTE EG 432-1): plain
//   primaries conversions, shared D65 — NO chromatic adaptation. VERBATIM
//   the ColorOutModule constants (the single source of truth for these two).
// - rec2020: identity (the LUT is authored in the working space).
// - proPhotoLinear (ROMM RGB, D50): the ICC relative-colorimetric shape —
//   Bradford chromatic adaptation D65→D50 into the ProPhoto (D50) space,
//   inverse on the way back. ProPhoto primaries R(0.734699,0.265301)
//   G(0.159597,0.840403) B(0.036598,0.000001), white D50 (0.34567,0.35850).
//
//   Rec2020 → sRGB (linear):
//     [  1.661272640, -0.588487320, -0.072785321 ]
//     [ -0.126189204,  1.134531230, -0.008342025 ]
//     [ -0.017014775, -0.100723728,  1.117738502 ]
//   Rec2020 → Display P3 (linear):
//     [  1.343930183, -0.282585998, -0.061344185 ]
//     [ -0.066855841,  1.077337009, -0.010481169 ]
//     [  0.003750840, -0.019626716,  1.015875875 ]
//   Rec2020 → ProPhoto linear (Bradford D65→D50):
//     [  0.554637491,  0.210524851,  0.165023118 ]
//     [  0.374273474,  0.526661261,  0.088756885 ]
//     [ -0.001793109,  0.013138034,  0.669590780 ]
//   ProPhoto linear → Rec2020 (the exact inverse of the above):
//     [  2.455869729, -0.969804801, -0.476706722 ]
//     [ -1.752173721,  2.596973508,  0.087590649 ]
//     [  0.040955998, -0.053552247,  1.490454281 ]
//
// Invariants (tested in Lut3dGoldenImageTests, T4): grays stay gray through
// every fwd (D65 maps to a neutral-axis point in each target), fwd·inv =
// identity (chromatic round trip), and each matrix is the published
// 4-decimal form to rounding.
// ─────────────────────────────────────────────────────────────────────────

enum LutColorspaceMatrices {

    typealias Matrix9 = (
        Float, Float, Float, Float, Float, Float, Float, Float, Float)

    static let identity: Matrix9 = (1, 0, 0, 0, 1, 0, 0, 0, 1)

    /// (fwd: working → LUT domain, inv: LUT domain → working), row-major.
    static func matrices(for colorspace: LutColorspace) -> (fwd: Matrix9, inv: Matrix9) {
        switch colorspace {
        case .rec2020:
            return (identity, identity)
        case .sRGB:
            return (rec2020ToSRGB, rec2020ToSRGBInverse)
        case .displayP3:
            return (rec2020ToP3, rec2020ToP3Inverse)
        case .proPhotoLinear:
            return (rec2020ToProPhoto, proPhotoToRec2020)
        }
    }

    /// simd_double3x3 view of a row-major tuple (the golden tests' CPU
    /// reference path).
    static func simdMatrix(_ m: Matrix9) -> simd_double3x3 {
        simd_double3x3(
            SIMD3(Double(m.0), Double(m.3), Double(m.6)),
            SIMD3(Double(m.1), Double(m.4), Double(m.7)),
            SIMD3(Double(m.2), Double(m.5), Double(m.8)))
    }

    // ColorOutModule constants verbatim (the same-source gamut family);
    // inverses are the numpy-exact inversions of the printed forward rows
    // (round-trip identity to <1e-8 in float64, verified by T4's tests).
    static let rec2020ToSRGB: Matrix9 = (
        1.661272640, -0.588487320, -0.072785321,
        -0.126189204, 1.134531230, -0.008342025,
        -0.017014775, -0.100723728, 1.117738502)
    static let rec2020ToSRGBInverse: Matrix9 = (
        0.627403896, 0.329283038, 0.043313066,
        0.069900074, 0.918691669, 0.011408257,
        0.015849621, 0.087799361, 0.896351018)
    static let rec2020ToP3: Matrix9 = (
        1.343930183, -0.282585998, -0.061344185,
        -0.066855841, 1.077337009, -0.010481169,
        0.003750840, -0.019626716, 1.015875875)
    static let rec2020ToP3Inverse: Matrix9 = (
        0.753833034, 0.198597369, 0.047569597,
        0.046762004, 0.940708608, 0.012529388,
        -0.001879878, 0.017441219, 0.984438659)
    // Bradford-adapted ProPhoto pair (derivation above).
    static let rec2020ToProPhoto: Matrix9 = (
        0.554637491, 0.210524851, 0.165023118,
        0.374273474, 0.526661261, 0.088756885,
        -0.001793109, 0.013138034, 0.669590780)
    static let proPhotoToRec2020: Matrix9 = (
        2.455869729, -0.969804801, -0.476706722,
        -1.752173721, 2.596973508, 0.087590649,
        0.040955998, -0.053552247, 1.490454281)
}

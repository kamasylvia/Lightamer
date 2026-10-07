import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────────
// Aces2Limiting — the Limiting-Space seven-choice tables + the ACES 1.3
// reference gamut compression pure functions (Plan M2-6-2 T2, KD-4/KD-3).
// Float64 CPU authority; the Metal twin restates these in
// `Aces2Kernels.metal` (constants single source discipline, KD-2).
//
// ── PART 1: the limiting spaces (KD-4) ──
// DATA SOURCES, per row (署名纪律):
//   • primaries/white xy = the public specification facts of each space
//     (ITU-R BT.709 / BT.2020; DCI P3 + SMPTE RP 431-2 + the D60 variant;
//     ROMM/ProPhoto ISO 22028; Adobe RGB (1998)). Transcribed numbers.
//   • the RGB→XYZ construction = the aces-core `RGBtoXYZ_f33` formula
//     (Lib.Academy.Utilities.ctl :273-316, upstream SHA 069b0bc3,
//     Apache-2.0 — Portions Copyright Contributors to the ACES Project;
//     see NOTICE) evaluated at Float64 through `Aces2Cam.rgbToXyzMat`.
//   • the per-space CAM16 param set (the `limit_params` of the upstream
//     `init_ODTParams(peakLuminance, limitingPrimaries)`) is derived, not
//     tabulated — one `Aces2Cam.JMhParams(primaries:)` per space.
//
// ── PART 2: the ACES 1.3 reference gamut compression (KD-3) ──
// PORTED FROM aces-core tag v1.3 (`transforms/ctl/lmt/LMT.Academy.
// GamutCompress.ctl`, transformId LMT.Academy.GamutCompress.a1.3.0) —
// the AMPAS BSD-era license (License Terms for Academy Color Encoding
// System Components, Copyright © 2015 A.M.P.A.S.); ported with
// attribution per NOTICE. Cross-validated read-only against the Alcedo
// `aces_reference_gamut_compression.h` shape (GPL, NOT copied — zero
// text/code taken; the constant table agrees).
//
// The RGC is the FIXED前置 stage of the aces20 method kernel (OQ-4-A:
// a kernel-constant on/off, default ON; NOT an op, NOT a user parameter,
// NOT in the node graph). The OpenDRT method path NEVER runs it (its
// render-space purity handling is its own; the dispatch-side assertion
// lives in Aces2KernelGoldenTests).
// ─────────────────────────────────────────────────────────────────────────────

/// The seven limiting spaces (KD-4 — enum-driven completeness).
enum Aces2Limiting {

    struct Space {
        /// The specification primaries + white (xy).
        let primaries: Aces2Cam.Chromaticities
        /// RGB→XYZ (math rows; derived from the primaries).
        let rgbToXyz: DrtMat3
        /// The CAM16 param set for THIS limiting space (the upstream
        /// `limit_params` — built by the same `init_JMhParams` chain).
        let params: Aces2Cam.JMhParams

        fileprivate init(primaries: Aces2Cam.Chromaticities) {
            self.primaries = primaries
            self.rgbToXyz = Aces2Cam.rgbToXyzMat(primaries)
            self.params = Aces2Cam.JMhParams(primaries: primaries)
        }
    }

    // The seven specification primary sets (数值事实, sources per row).
    private static func makeTable() -> [DrtLimitingSpace: Space] {
        var t: [DrtLimitingSpace: Space] = [:]
        // ITU-R BT.709 (rec709/sRGB primaries), D65.
        t[.rec709] = Space(primaries: Aces2Cam.Chromaticities(
            red: SIMD2(0.64, 0.33), green: SIMD2(0.30, 0.60),
            blue: SIMD2(0.15, 0.06), white: SIMD2(0.3127, 0.3290)))
        // ITU-R BT.2020/BT.2100, D65.
        t[.rec2020] = Space(primaries: Aces2Cam.rec2020Primaries)
        // DCI P3 (P3-D65 variant), D65.
        t[.p3d65] = Space(primaries: Aces2Cam.Chromaticities(
            red: SIMD2(0.680, 0.320), green: SIMD2(0.265, 0.690),
            blue: SIMD2(0.150, 0.060), white: SIMD2(0.3127, 0.3290)))
        // DCI P3 (D60 variant), the D60 white.
        t[.p3d60] = Space(primaries: Aces2Cam.Chromaticities(
            red: SIMD2(0.680, 0.320), green: SIMD2(0.265, 0.690),
            blue: SIMD2(0.150, 0.060), white: SIMD2(0.327, 0.338)))
        // DCI P3 (theater), the SMPTE RP 431-2 white.
        t[.p3dci] = Space(primaries: Aces2Cam.Chromaticities(
            red: SIMD2(0.680, 0.320), green: SIMD2(0.265, 0.690),
            blue: SIMD2(0.150, 0.060), white: SIMD2(0.314, 0.351)))
        // ProPhoto RGB (ROMM ISO 22028-2/-3), D50.
        t[.proPhoto] = Space(primaries: Aces2Cam.Chromaticities(
            red: SIMD2(0.7347, 0.2653), green: SIMD2(0.1596, 0.8404),
            blue: SIMD2(0.0366, 0.0001), white: SIMD2(0.3457, 0.3585)))
        // Adobe RGB (1998), D65.
        t[.adobeRGB] = Space(primaries: Aces2Cam.Chromaticities(
            red: SIMD2(0.64, 0.33), green: SIMD2(0.21, 0.71),
            blue: SIMD2(0.15, 0.06), white: SIMD2(0.3127, 0.3290)))
        return t
    }

    /// The table (built once; enum-driven completeness pinned by tests).
    static let spaces: [DrtLimitingSpace: Space] = makeTable()
}

// ─────────────────────────────────────────────────────────────────────────────
// The ACES 1.3 reference gamut compression (KD-3) — Float64 pure functions.
// ─────────────────────────────────────────────────────────────────────────────

/// The RGC namespace (the constant table IS the upstream's — the Alcedo hpp
/// cross-check agrees on every value; DECISIONS §D4).
enum Aces2RGC {

    // Gamut Compress Parameters (v1.3 LMT.Academy.GamutCompress.ctl:29-46).
    // Distance from achromatic which will be compressed to the gamut
    // boundary — calculated to encompass the encoding gamuts of common
    // digital cinema cameras.
    static let limCyan: Double = 1.147
    static let limMagenta: Double = 1.264
    static let limYellow: Double = 1.312
    // Percentage of the core gamut to protect — calculated to protect all
    // the colors of the ColorChecker Classic 24 (ISO 17321-1 / Ohta 1997).
    static let thrCyan: Double = 0.815
    static let thrMagenta: Double = 0.803
    static let thrYellow: Double = 0.880
    // Aggressiveness of the compression curve (the plan's 幂 1.2 anchor).
    static let pwr: Double = 1.2

    /// The per-channel `compress` distance shaper (upstream :50-82).
    /// `dist < thr` → UNCHANGED (exact — bit-for-bit, the AC#3 identity
    /// face); otherwise the threshold/limit power curve.
    static func compressDistance(
        _ dist: Double, limit: Double, threshold: Double
    ) -> Double {
        if dist < threshold {
            return dist
        }
        // Scale factor for the y = 1 intersect.
        let scl = (limit - threshold)
            / Foundation.pow(
                Foundation.pow((1.0 - threshold) / (limit - threshold), -pwr) - 1.0,
                1.0 / pwr)
        // Normalize the distance outside the threshold by the scale factor.
        let nd = (dist - threshold) / scl
        let p = Foundation.pow(nd, pwr)
        // Compress (the forward arm only — the inverse lives upstream for
        // the LMT's invert flag, which the fixed前置 stage never uses).
        return threshold + scl * nd / Foundation.pow(1.0 + p, 1.0 / pwr)
    }

    /// The full RGC on ACES2065-1 (AP0) linear input — the upstream `main`
    /// body: AP0 → AP1, achromatic-axis distance per channel, compress,
    /// recompose, AP1 → AP0. The fixed前置 stage of the aces20 kernel.
    static func compress(_ acesAP0: SIMD3<Double>) -> SIMD3<Double> {
        // Convert to AP1 (ACEScg-equivalent working primaries).
        let linAP1 = Aces2Cam.ap0ToAP1.multiply(acesAP0)
        // The achromatic axis.
        let ach = max(linAP1.x, max(linAP1.y, linAP1.z))
        // Distance from the achromatic axis per component (inverse RGB
        // ratios); black collapses to zero distance.
        let mag = abs(ach)
        let dist = mag == 0
            ? SIMD3<Double>.zero
            : SIMD3(
                (ach - linAP1.x) / mag,
                (ach - linAP1.y) / mag,
                (ach - linAP1.z) / mag)
        // Compress each distance with the parameterized shaper — cyan↔R,
        // magenta↔G, yellow↔B (the channel-parameter pairing upstream).
        let comprDist = SIMD3(
            compressDistance(dist.x, limit: limCyan, threshold: thrCyan),
            compressDistance(dist.y, limit: limMagenta, threshold: thrMagenta),
            compressDistance(dist.z, limit: limYellow, threshold: thrYellow))
        // Recompose RGB from the compressed distance + achromatic.
        let comprLinAP1 = SIMD3(
            ach - comprDist.x * mag,
            ach - comprDist.y * mag,
            ach - comprDist.z * mag)
        // Back to ACES2065-1.
        return Aces2Cam.ap1ToAP0.multiply(comprLinAP1)
    }
}

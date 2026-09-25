import LightamerCore
import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────
// YiyinColor (Plan 08-01 T3, COLOR-2) — sRGB hex → display-domain linear.
//
// The borders module runs AFTER colorout (terminal segment): the plane is
// LINEAR display-gamut RGB. A user-picked sRGB hex (the yiyin
// `solid_color` / the 08-2 text colors) must be written as the value whose
// RENDERED color equals the hex on the target display:
//
//   hex --sRGB EOTF--> sRGB-linear --M(sRGB→Rec2020)--> Rec2020-linear
//      --M(Rec2020→display) = the ColorOutModule matrix--> display-linear
//
// M(sRGB→Rec2020) is the exact inverse of ColorOutModule's quoted
// Rec2020→sRGB matrix, so the round trip through colorout is exact and the
// two faces share ONE matrix family (the "ColorOutModule 同源 profile"
// requirement). Per-profile targets:
// - `.displayP3`: Rec2020→P3 quoted matrix.
// - `.sRGB` / `.colorSyncFallback`: identity (the fallback's documented
//   linear-sRGB workalike — DisplayProfile.linearCGColorSpace).
// Neutrals are exact in every target (all three spaces share D65 — the
// D-COL1 precondition): white hex → (1,1,1) exactly.
//
// The Phase-11 EXPORT face applies the export-profile matrix with the same
// formula (the module has no opinion about which profile colorout
// produced — D-08-CONTEXT COLOR-2 bullet).
// ─────────────────────────────────────────────────────────────────────────

public enum YiyinColor {

    /// Parse `#rrggbb` (or `#rgb`) → 0..1 sRGB-ENCODED triple. nil on any
    /// malformed input (the caller degrades to white — yiyin `|| '#fff'`).
    public static func parseSRGBHex(_ hex: String) -> SIMD3<Double>? {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let chars = Array(s.lowercased())
        func hexValue(_ c: Character) -> Double? {
            guard let v = c.hexDigitValue else { return nil }
            return Double(v)
        }
        if chars.count == 3 {
            guard let r = hexValue(chars[0]), let g = hexValue(chars[1]),
                let b = hexValue(chars[2])
            else { return nil }
            return SIMD3(r / 15, g / 15, b / 15)
        }
        if chars.count == 6 {
            func pair(_ a: Character, _ b: Character) -> Double? {
                guard let hi = hexValue(a), let lo = hexValue(b) else { return nil }
                return (hi * 16 + lo) / 255
            }
            guard let r = pair(chars[0], chars[1]), let g = pair(chars[2], chars[3]),
                let b = pair(chars[4], chars[5])
            else { return nil }
            return SIMD3(r, g, b)
        }
        return nil
    }

    /// sRGB EOTF decode (IEC 61966-2-1) — the exact segmented formula the
    /// GammaModule encodes with, inverted.
    public static func linearizeSRGB(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : Foundation.pow((c + 0.055) / 1.055, 2.4)
    }

    /// sRGB OETF encode — the inverse of `linearizeSRGB` (the GammaModule
    /// TRC). Maps a linear value back to the 0-1 ENCODED scale (the T5
    /// brightness tiers are calibrated on that scale, yiyin :31-42).
    public static func linearizeSRGBInverse(_ c: Double) -> Double {
        c <= 0.0031308 ? c * 12.92 : 1.055 * Foundation.pow(c, 1.0 / 2.4) - 0.055
    }

    /// M(sRGB-linear → Rec2020-linear) — the inverse of ColorOutModule's
    /// quoted Rec2020→sRGB matrix (ColorOutModule.swift derivation header;
    /// shared D65 ⇒ grays invariant). 9-decimal constants from the
    /// 08-1 T3 derivation (float64; consumers publish Float32).
    /// simd matrices are COLUMN-major: the quoted row-major rows are
    /// transposed into the initializer arguments.
    static let sRGBToRec2020 = simd_double3x3(
        .init(0.627403896, 0.069900073, 0.015849621), // ← quoted row 0
        .init(0.329283039, 0.918691669, 0.087799361), // ← quoted row 1
        .init(0.043313066, 0.011408257, 0.896351018)) // ← quoted row 2

    /// M(Rec2020-linear → Display-P3-linear) — ColorOutModule's quoted
    /// compile-time constant, restated here so the hex face composes the
    /// SAME family (column-major: quoted rows transposed).
    static let rec2020ToP3 = simd_double3x3(
        .init(1.343930183, -0.066855841, 0.003750840),
        .init(-0.282585998, 1.077337009, -0.019626716),
        .init(-0.061344185, -0.010481169, 1.015875875))

    /// The display-domain linear fill for an sRGB hex under the resolved
    /// display profile. nil when the hex is malformed (caller degrades).
    public static func linearDisplay(
        fromSRGBHex hex: String, target: DisplayProfile
    ) -> SIMD3<Float>? {
        guard let encoded = parseSRGBHex(hex) else { return nil }
        let srgbLinear = SIMD3(
            linearizeSRGB(encoded.x), linearizeSRGB(encoded.y), linearizeSRGB(encoded.z))
        switch target {
        case .displayP3:
            // sRGB-linear → Rec2020-linear → P3-linear (the colorout matrix
            // chain — the composed value the post-colorout plane carries).
            let rec2020 = sRGBToRec2020 * srgbLinear
            let p3 = rec2020ToP3 * rec2020
            return SIMD3(Float(p3.x), Float(p3.y), Float(p3.z))
        case .sRGB, .colorSyncFallback:
            // Identity primaries (the fallback's sRGB workalike): the plane
            // IS linear sRGB — no intermediation.
            return SIMD3(Float(srgbLinear.x), Float(srgbLinear.y), Float(srgbLinear.z))
        }
    }

    /// The composed M(sRGB-linear → display-linear) ROWS for the watermark
    /// row kernel (COLOR-2's ColorOutModule-source chain — the same family
    /// `linearDisplay` composes for fills), flattened ROW-major as 9
    /// floats (layout-safe against float3 alignment). Neutrals map to
    /// themselves under every target (shared D65): row_i · (1,1,1) = 1.
    public static func sRGBToDisplayMatrixRows(target: DisplayProfile) -> [Float] {
        let display: simd_double3x3
        switch target {
        case .displayP3:
            display = rec2020ToP3
        case .sRGB, .colorSyncFallback:
            display = simd_double3x3(diagonal: simd_double3(1, 1, 1))
        }
        let m = display * sRGBToRec2020 // m * sRGBLinear = displayLinear
        // Row i of the math matrix = (columns.0[i], columns.1[i], columns.2[i]).
        var rows = [Float]()
        rows.reserveCapacity(9)
        for i in 0..<3 {
            rows.append(Float(m.columns.0[i]))
            rows.append(Float(m.columns.1[i]))
            rows.append(Float(m.columns.2[i]))
        }
        return rows
    }

    /// The gray overlay ramp for the blur-mode adaptive backdrop (T5's
    /// consumer; declared here to keep ALL color constants in one file).
    /// yiyin web `image-tool/index.ts:28-46`: rgba(g, g, g, 0.2) per tier
    /// — g ∈ {180, 158, 128, 0} by mean brightness (<15 / <20 / <40 / ≥40
    /// on the 0-255 sRGB-encoded scale).
    public static let overlayAlpha: Double = 0.2
    public static let overlayGrayTiers: [(below: Double, gray8: UInt8)] = [
        (15, 180), (20, 158), (40, 128), (.infinity, 0),
    ]

    /// The four-tier selection (yiyin :31-42 verbatim thresholds, 0-255
    /// encoded scale) → the tier index; `brightness8` = the CPU-computed
    /// mean mapped back to the encoded scale (T5 DECISIONS).
    public static func overlayTierIndex(brightness8: Double) -> Int {
        for (index, tier) in overlayGrayTiers.enumerated()
        where brightness8 < tier.below {
            return index
        }
        return overlayGrayTiers.count - 1
    }
}

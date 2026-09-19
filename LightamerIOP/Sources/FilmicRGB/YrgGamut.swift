import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────
// YrgGamut (Plan 03-06-T4, F3) — the Kirk/Filmlight Yrg gamut-mapping
// support for filmicrgb V5: the pipeline RGB ⇄ CIE 2006 LMS D65 matrices,
// the Yrg ⇄ Ych polar conversions and the Yrg gamut clip — transliterated
// from
//   - src/common/gamut_mapping.h     (prepare_RGB_Yrg_matrices,
//                                     CIE_Y_1931_to_CIE_Y_2006, clip-chroma)
//   - src/common/chromatic_adaptation.h (XYZ_D50_to_D65_CAT16 matrices)
//   - data/kernels/colorspace.h      (XYZ_to_LMS 2006, LMS_to_Yrg/Ych)
//   - src/iop/filmicrgb.c:1639-1746  (filmic_desaturate_v4, gamut_check_*)
// (tree dc58cf0ba1).
//
// WORKING-DOMAIN CONSTANT (the plan's "编译期常量" decision): the Lightamer
// pipeline is ALWAYS linear Rec2020, so `matrixIn/matrixOut` collapse to
//
//   matrixIn  = XYZ_D65→LMS2006 · XYZ_D50→D65_CAT16 · M_in(Rec2020 D50)
//   matrixOut = M_out(Rec2020 D50) · XYZ_D65→D50_CAT16 · LMS2006→XYZ_D65
//
// where M_in/M_out(Rec2020 D50) are the project's LabRoundTrip constants
// (the SAME Bradford-adapted Rec2020⇄XYZ D50 pair every Lab module uses).
// dt builds the identical product from its LIN_REC2020 work profile.
//
// The clip-chroma constants (0.979381443298969… etc.) are the Kirk Yrg
// triangle geometry baked by dt's derive_filmic_v6_gamut_mapping.py —
// moved verbatim (they are NOT Rec2020-dependent: they act in LMS 2006 /
// Yrg space, and `matrixOut` rows enter as arguments).
// ─────────────────────────────────────────────────────────────────────────

public enum YrgGamut {

    // MARK: - Constants (verbatim from the dt headers)

    /// CAT16 D50→D65 XYZ adaptation (chromatic_adaptation.h:375-378).
    public static let xyzD50toD65CAT16: [[Double]] = [
        [9.89466254e-01, -4.00304626e-02, 4.40530317e-02],
        [-5.40518733e-03, 1.00666069e+00, -1.75551955e-03],
        [-4.03920992e-04, 1.50768030e-02, 1.30210211e+00],
    ]

    /// CAT16 D65→D50 XYZ adaptation (chromatic_adaptation.h:390-393).
    public static let xyzD65toD50CAT16: [[Double]] = [
        [1.01085433e+00, 4.07086103e-02, -3.41445825e-02],
        [5.42814201e-03, 9.93581926e-01, 1.15592039e-03],
        [2.50722468e-04, -1.14918759e-02, 7.67964947e-01],
    ]

    /// CIE 1931 XYZ D65 → CIE 2006 LMS D65 (Kirk approximation,
    /// colorspace.h:453-465).
    public static let xyzD65toLMS2006: [[Double]] = [
        [0.257085, 0.859943, -0.031061],
        [-0.394427, 1.175800, 0.106423],
        [0.064856, -0.076250, 0.559067],
    ]

    /// CIE 2006 LMS D65 → XYZ D65 (colorspace.h:468-476).
    public static let lms2006toXYZD65: [[Double]] = [
        [1.80794659, -1.29971660, 0.34785879],
        [0.61783960, 0.39595453, -0.04104687],
        [-0.12546960, 0.20478038, 1.74274183],
    ]

    /// CIE Y 1931 → CIE Y 2006 (gamut_mapping.h:33; 1 Y1931 = 1.05785528
    /// Y2006 — also accounts for the CAT16 D50→D65 adaptation; achromatic
    /// pixels only, dt's own warning).
    public static let cieY1931to2006Factor: Double = 1.05785528

    public static func cieY1931to2006(_ y: Double) -> Double { cieY1931to2006Factor * y }

    // MARK: - Compiled working-domain matrices (linear Rec2020)

    /// Pipeline (linear Rec2020) RGB → CIE 2006 LMS D65. The dt product
    /// (gamut_mapping.h prepare_RGB_Yrg_matrices) is
    /// `XYZ_D65→LMS2006 · XYZ_D50→D65_CAT16 · M_in(work)` where M_in(work)
    /// is the ICC work profile's BRADFORD-ADAPTED RGB(D50)→XYZ(D50) —
    /// bradfordD65ToD50 · rec2020ToXYZ here.
    public static let matrixIn: [[Double]] = matMul(
        xyzD65toLMS2006,
        matMul(
            xyzD50toD65CAT16,
            matMul(LabRoundTrip.bradfordD65ToD50, LabRoundTrip.rec2020ToXYZ)
        )
    )

    /// CIE 2006 LMS D65 → pipeline RGB (the exact inverse product).
    public static let matrixOut: [[Double]] = matMul(
        LabRoundTrip.xyzToRec2020,
        matMul(
            LabRoundTrip.bradfordD50ToD65,
            matMul(xyzD65toD50CAT16, lms2006toXYZD65)
        )
    )

    /// Rec2020 luminance coefficients (the LUMINANCE norm — the row of
    /// the D65 Rec2020→XYZ matrix; dt uses the work profile matrix).
    public static let rec2020Luminance: SIMD3<Double> = SIMD3<Double>(
        LabRoundTrip.rec2020ToXYZ[1][0],
        LabRoundTrip.rec2020ToXYZ[1][1],
        LabRoundTrip.rec2020ToXYZ[1][2]
    )

    // MARK: - Yrg ⇄ Ych (colorspace.h:498-585)

    /// Kirk Filmlight RGB (normalized LMS) → LMS (colorspace.h:513-521).
    static let filmlightRGBtoLMS: [[Double]] = [
        [0.95, 0.38, 0.00],
        [0.05, 0.62, 0.03],
        [0.00, 0.00, 0.97],
    ]

    /// LMS → Kirk Filmlight RGB (colorspace.h:524-532).
    static let lmsToFilmlightRGB: [[Double]] = [
        [1.0877193, -0.66666667, 0.02061856],
        [-0.0877193, 1.66666667, -0.05154639],
        [0.0, 0.0, 1.03092784],
    ]

    /// The Yrg white point (the r, g of Rec2020 D65 white through
    /// XYZ→LMS 2006→grading RGB; colorspace.h:555-570).
    public static let yrgWhiteR: Double = 0.21902143
    public static let yrgWhiteG: Double = 0.54371398

    /// Double-precision (Y, Yrg) from pipeline RGB. Returns
    /// (Y, r, g) — Y is the LMS-luminance (CIE 2006).
    public static func rgbToYrg(_ rgb: SIMD3<Double>) -> (y: Double, r: Double, g: Double) {
        let lms = mul(matrixIn, rgb)
        // LMS_to_Yrg: luminance + normalize + grading RGB.
        let y = 0.68990272 * lms.x + 0.34832189 * lms.y
        let a = lms.x + lms.y + lms.z
        let nlms = a == 0 ? SIMD3<Double>.zero : lms / a
        let rgbFilmlight = mul(lmsToFilmlightRGB, nlms)
        return (y, rgbFilmlight.x, rgbFilmlight.y)
    }

    /// Yrg → pipeline RGB (the return leg).
    public static func yrgToRGB(y: Double, r: Double, g: Double) -> SIMD3<Double> {
        let b = 1.0 - r - g
        let lmsNormalized = mul(filmlightRGBtoLMS, SIMD3<Double>(r, g, b))
        let denom = 0.68990272 * lmsNormalized.x + 0.34832189 * lmsNormalized.y
        let scale = denom == 0 ? 0.0 : y / denom
        return mul(matrixOut, lmsNormalized * scale)
    }

    /// RGB → Ych polar (cos/sin of the hue angle, dt stores no angle).
    public static func rgbToYch(_ rgb: SIMD3<Double>) -> SIMD4<Double> {
        let (y, r, g) = rgbToYrg(rgb)
        let rr = r - yrgWhiteR
        let gg = g - yrgWhiteG
        let c = (gg * gg + rr * rr).squareRoot() // dt_fast_hypot(g, r)
        let cosH = c != 0 ? rr / c : 1.0
        let sinH = c != 0 ? gg / c : 0.0
        return SIMD4<Double>(y, c, cosH, sinH)
    }

    /// Ych → Yrg cartesian.
    public static func ychToYrg(_ ych: SIMD4<Double>) -> (y: Double, r: Double, g: Double) {
        (ych.x, ych.y * ych.z + yrgWhiteR, ych.y * ych.w + yrgWhiteG)
    }

    // MARK: - gamut_check_Yrg (filmicrgb.c:1697-1731 / colorspace.h:751-780)

    /// Clip the Ych chroma into the Yrg triangle at constant hue+luma.
    public static func gamutCheckYrg(_ ychIn: SIMD4<Double>) -> SIMD4<Double> {
        var ych = ychIn
        let yrg = ychToYrg(ych)
        var maxC = ych.y
        let cosH = ych.z
        let sinH = ych.w

        if yrg.r < 0 {
            maxC = Swift.min(-yrgWhiteR / cosH, maxC)
        }
        if yrg.g < 0 {
            maxC = Swift.min(-yrgWhiteG / sinH, maxC)
        }
        if yrg.r + yrg.g > 1.0 {
            maxC = Swift.min((1.0 - yrgWhiteR - yrgWhiteG) / (cosH + sinH), maxC)
        }
        ych.y = maxC
        return ych
    }

    // MARK: - clip-chroma family (gamut_mapping.h:23-104, filmic.cl:382-477)

    /// `_clip_chroma_white_raw` — one matrixOut row.
    static func clipChromaWhiteRaw(
        _ coeffs: SIMD3<Double>, targetWhite: Double, y: Double, cosH: Double, sinH: Double
    ) -> Double {
        let denominatorYCoeff = coeffs.x * (0.979381443298969 * cosH + 0.391752577319588 * sinH)
            + coeffs.y * (0.0206185567010309 * cosH + 0.608247422680412 * sinH)
            - coeffs.z * (cosH + sinH)
        let denominatorTargetTerm = targetWhite * (0.68285981628866 * cosH + 0.482137060515464 * sinH)
        if denominatorYCoeff == 0 { return .greatestFiniteMagnitude }
        let yAsymptote = denominatorTargetTerm / denominatorYCoeff
        if y <= yAsymptote { return .greatestFiniteMagnitude }
        let denominator = y * denominatorYCoeff - denominatorTargetTerm
        let numerator = -0.427506877216495
            * (y * (coeffs.x + 0.856492345150334 * coeffs.y + 0.554995960637719 * coeffs.z)
                - 0.988237752433297 * targetWhite)
        return numerator / denominator
    }

    /// `_clip_chroma_white` — the eps interpolation near max luminance.
    static func clipChromaWhite(
        _ coeffs: SIMD3<Double>, targetWhite: Double, y: Double, cosH: Double, sinH: Double
    ) -> Double {
        let eps = 1e-3
        let maxY = cieY1931to2006(targetWhite)
        let deltaY = Swift.max(maxY - y, 0.0)
        var maxChroma: Double
        if deltaY < eps {
            maxChroma = deltaY / (eps * maxY)
                * clipChromaWhiteRaw(coeffs, targetWhite: targetWhite, y: (1.0 - eps) * maxY, cosH: cosH, sinH: sinH)
        } else {
            maxChroma = clipChromaWhiteRaw(coeffs, targetWhite: targetWhite, y: y, cosH: cosH, sinH: sinH)
        }
        return maxChroma >= 0 ? maxChroma : .greatestFiniteMagnitude
    }

    /// `_clip_chroma_black` — the target-zero form.
    static func clipChromaBlack(_ coeffs: SIMD3<Double>, cosH: Double, sinH: Double) -> Double {
        let denominator = coeffs.x * (0.979381443298969 * cosH + 0.391752577319588 * sinH)
            + coeffs.y * (0.0206185567010309 * cosH + 0.608247422680412 * sinH)
            - coeffs.z * (cosH + sinH)
        if denominator == 0 { return .greatestFiniteMagnitude }
        let numerator = -0.427506877216495
            * (coeffs.x + 0.856492345150334 * coeffs.y + 0.554995960637719 * coeffs.z)
        let maxChroma = numerator / denominator
        return maxChroma >= 0 ? maxChroma : .greatestFiniteMagnitude
    }

    /// `clip_chroma` (filmic.cl:457-477) — the brute-force min over the
    /// three RGB channels' black and white chroma limits.
    public static func clipChroma(
        targetWhite: Double, y: Double, cosH: Double, sinH: Double, chroma: Double
    ) -> Double {
        func row(_ m: [[Double]], _ r: Int) -> SIMD3<Double> {
            SIMD3<Double>(m[r][0], m[r][1], m[r][2])
        }
        let cRW = clipChromaWhite(row(matrixOut, 0), targetWhite: targetWhite, y: y, cosH: cosH, sinH: sinH)
        let cGW = clipChromaWhite(row(matrixOut, 1), targetWhite: targetWhite, y: y, cosH: cosH, sinH: sinH)
        let cBW = clipChromaWhite(row(matrixOut, 2), targetWhite: targetWhite, y: y, cosH: cosH, sinH: sinH)
        let maxWhite = Swift.min(Swift.min(cRW, cGW), cBW)
        let cRB = clipChromaBlack(row(matrixOut, 0), cosH: cosH, sinH: sinH)
        let cGB = clipChromaBlack(row(matrixOut, 1), cosH: cosH, sinH: sinH)
        let cBB = clipChromaBlack(row(matrixOut, 2), cosH: cosH, sinH: sinH)
        let maxBlack = Swift.min(Swift.min(cRB, cGB), cBB)
        return Swift.min(Swift.min(chroma, maxBlack), maxWhite)
    }

    // MARK: - gamut_check_RGB (filmicrgb.c:1650-1695 / filmic.cl:480-508)

    /// Bring a Ych color back into the pipeline RGB gamut: white-mix
    /// heuristic + luminance-mean + clip-chroma + the final catch-all.
    public static func gamutCheckRGB(
        ychIn: SIMD4<Double>, displayBlack: Double, displayWhite: Double
    ) -> SIMD3<Double> {
        var rgbBrightened = yrgToRGB(y: ychIn.x, r: ychToYrg(ychIn).r, g: ychToYrg(ychIn).g)
        let minPix = Swift.min(Swift.min(rgbBrightened.x, rgbBrightened.y), rgbBrightened.z)
        let blackOffset = Swift.max(-minPix, 0.0)
        rgbBrightened += SIMD3<Double>(repeating: blackOffset)
        let ychBrightened = rgbToYch(rgbBrightened)

        let y = Swift.min(
            Swift.max((ychIn.x + ychBrightened.x) / 2.0, cieY1931to2006(displayBlack)),
            cieY1931to2006(displayWhite)
        )
        let cosH = ychIn.z
        let sinH = ychIn.w
        let newChroma = clipChroma(
            targetWhite: displayWhite, y: y, cosH: cosH, sinH: sinH, chroma: ychIn.y
        )

        let ychOut = SIMD4<Double>(y, newChroma, cosH, sinH)
        let yrg = ychToYrg(ychOut)
        var rgbOut = yrgToRGB(y: yrg.y, r: yrg.r, g: yrg.g)
        for c in 0..<3 {
            rgbOut[c] = Swift.min(Swift.max(rgbOut[c], 0.0), displayWhite)
        }
        return rgbOut
    }

    // MARK: - filmic_desaturate_v4 (filmicrgb.c:1639-1680 / filmic.cl:336-370)

    /// The chroma massage between the original and tone-mapped Ych.
    /// Mutating form mirroring dt (returns the updated Ych).
    public static func filmicDesaturateV4(
        original: SIMD4<Double>, finalIn: SIMD4<Double>, saturation: Double
    ) -> SIMD4<Double> {
        var finalYch = finalIn
        let chromaOriginal = original.y * original.x   // c2
        var chromaFinal = finalYch.y * finalYch.x      // c1
        let deltaChroma = saturation * (chromaOriginal - chromaFinal)

        let filmicBrightens = finalYch.x > original.x
        let filmicResat = chromaOriginal < chromaFinal
        let filmicDesat = chromaOriginal > chromaFinal
        let userResat = saturation > 0
        let userDesat = saturation < 0

        chromaFinal =
            (filmicBrightens && filmicResat)
            ? (chromaOriginal + chromaFinal) / 2.0
            : ((userResat && filmicDesat) || userDesat)
                ? chromaFinal + deltaChroma
                : chromaFinal

        finalYch.y = Swift.max(chromaFinal / finalYch.x, 0.0)
        return finalYch
    }

    // MARK: - linear-algebra helpers

    static func matMul(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        var out = [[Double]](repeating: [0, 0, 0], count: 3)
        for r in 0..<3 { for c in 0..<3 {
            out[r][c] = a[r][0] * b[0][c] + a[r][1] * b[1][c] + a[r][2] * b[2][c]
        } }
        return out
    }

    static func mul(_ m: [[Double]], _ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(
            m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z,
            m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
            m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z
        )
    }

    /// Row-major 3×3 → 9 floats (the kernel buffer layout, no padding).
    public static func flatten(_ m: [[Double]]) -> [Float] {
        m.flatMap { $0.map { Float($0) } }
    }

    /// The 12-float dt_colormatrix layout (3 rows × 4 columns, 4th column
    /// zero) — unused by the kernel (we use the 9-float dense form) but
    /// kept for potential XMP/introspection parity work.
    public static func flatten12(_ m: [[Double]]) -> [Float] {
        var out: [Float] = []
        for r in 0..<3 {
            out.append(Float(m[r][0]))
            out.append(Float(m[r][1]))
            out.append(Float(m[r][2]))
            out.append(0)
        }
        return out
    }
}

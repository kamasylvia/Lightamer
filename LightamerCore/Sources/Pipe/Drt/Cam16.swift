import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────────
// Cam16 — the CAM16 JMh color-appearance core for the ACES 2.0 display
// render transform (Plan M2-6-2 T1, KD-2). Float64 CPU authority; the Metal
// twin lives in `Aces2Kernels.metal` (T4) and restates — never re-authors —
// these constants (the M2-6-1 KD-2 double-transcription discipline; the
// constant single source is THIS file).
//
// PORTED FROM aces-core (upstream SHA
// 069b0bc3e1f6c62820f19fdae2fecec3f4fc0f80, v2.0 main, 2026-09-01):
//   • `lib/Lib.Academy.OutputTransform.ctl` — the JMhParams construction
//     (`init_JMhParams` :926-999), the forward/inverse JMh conversions
//     (`RGB_to_Aab`/`Aab_to_JMh`/`RGB_to_JMh` :254-296,
//     `JMh_to_Aab`/`Aab_to_RGB`/`JMh_to_RGB` :298-337), the
//     post-adaptation cone response compression (:185-212), the
//     AP0/AP1/CAM16 chromaticities (:12-39), and the FIXED ACES 2.0
//     viewing-condition constants (:60-71).
//   Portions Copyright Contributors to the ACES Project; Apache-2.0;
//     see NOTICE. (The plan's "AMPAS BSD" assumption held for the v1.3
//     RGC segment only — the v2.0 main branch re-licensed to Apache-2.0;
//     M2-6-2-DECISIONS §D1.)
//
// CONVENTION (transpose discipline): the CTL stores matrices TRANSPOSED
// (its `mult_f3_f33(v, M)` is the row-vector form). Everything here is
// re-derived in the plain math form (column vectors, DrtMat3 rows =
// matrix rows). The per-function comments carry the upstream identity
// chain so the transcription is auditable line-for-line.
//
// FIXED VIEWING CONDITIONS (ACES 2.0 — a single hard-coded environment):
//   L_A = 100 cd/m², Y_b = 20, dim surround = (0.9, 0.59, 0.9),
//   reference luminance 100 (white). The Hellwig/HKE appearance of the
//   model enters through cz = model_gamma = surround_b·(1.48+√(Y_b/ref))
//   (the Hellwig 2022 exponent form ACES 2.0 adopts) — there is no
//   separate HKE term in the upstream; DECISIONS §D2.
// ─────────────────────────────────────────────────────────────────────────────

/// Row-major 3×3 inverse (the CTL `invert_f33` — adjugate/determinant;
/// Float64 all the way).
extension DrtMat3 {
    func inverted() -> DrtMat3 {
        // inv row i = (cofactor[0][i], cofactor[1][i], cofactor[2][i])/det
        // (the adjugate's rows are the cofactor matrix's columns).
        let det = r0.x * (r1.y * r2.z - r1.z * r2.y)
            - r0.y * (r1.x * r2.z - r1.z * r2.x)
            + r0.z * (r1.x * r2.y - r1.y * r2.x)
        let invDet = 1.0 / det
        return DrtMat3(
            r0: SIMD3(
                (r1.y * r2.z - r1.z * r2.y) * invDet,
                (r0.z * r2.y - r0.y * r2.z) * invDet,
                (r0.y * r1.z - r0.z * r1.y) * invDet),
            r1: SIMD3(
                (r1.z * r2.x - r1.x * r2.z) * invDet,
                (r0.x * r2.z - r0.z * r2.x) * invDet,
                (r0.z * r1.x - r0.x * r1.z) * invDet),
            r2: SIMD3(
                (r1.x * r2.y - r1.y * r2.x) * invDet,
                (r0.y * r2.x - r0.x * r2.y) * invDet,
                (r0.x * r1.y - r0.y * r1.x) * invDet))
    }

    func transposed() -> DrtMat3 {
        DrtMat3(
            r0: SIMD3(r0.x, r1.x, r2.x),
            r1: SIMD3(r0.y, r1.y, r2.y),
            r2: SIMD3(r0.z, r1.z, r2.z))
    }
}

/// The ACES 2.0 CAM16 JMh namespace (constant single source — KD-2).
enum Aces2Cam {

    // MARK: - Chromaticities (upstream OutputTransform.ctl :12-39, :928-932)

    struct Chromaticities: Sendable, Equatable {
        var red: SIMD2<Double>
        var green: SIMD2<Double>
        var blue: SIMD2<Double>
        var white: SIMD2<Double>

        init(
            red: SIMD2<Double>, green: SIMD2<Double>,
            blue: SIMD2<Double>, white: SIMD2<Double>
        ) {
            self.red = red
            self.green = green
            self.blue = blue
            self.white = white
        }
    }

    /// Academy Primaries 0 — ACES2065-1 (SMPTE ST 2065-1).
    static let ap0 = Chromaticities(
        red: SIMD2(0.73470, 0.26530),
        green: SIMD2(0.00000, 1.00000),
        blue: SIMD2(0.00010, -0.07700),
        white: SIMD2(0.32168, 0.33767))

    /// Academy Primaries 1 — the working/reach primaries.
    static let ap1 = Chromaticities(
        red: SIMD2(0.713, 0.293),
        green: SIMD2(0.165, 0.830),
        blue: SIMD2(0.128, 0.044),
        white: SIMD2(0.32168, 0.33767))

    /// The CAM16 sharpened-cone primaries (upstream :928-932 — inside
    /// `init_JMhParams`; hoisted here as the single source).
    static let cam16Primaries = Chromaticities(
        red: SIMD2(0.8336, 0.1735),
        green: SIMD2(2.3854, -1.4659),
        blue: SIMD2(0.087, -0.125),
        white: SIMD2(0.333, 0.333))

    // MARK: - Fixed ACES 2.0 viewing conditions (:60-71 —逐常数断言面)

    /// Reference luminance (nits) — white in the J/Y scale.
    static let refLuminance: Double = 100.0
    /// Adapting luminance (cd/m²).
    static let luminousAscent: Double = 100.0   // L_A
    /// Background luminance (cd/m²).
    static let backgroundLuminance: Double = 20.0 // Y_b
    /// Dim surround (c, nc, F? — upstream `surround[3] = {0.9, 0.59, 0.9}`;
    /// index 1 drives model_gamma, index 2 scales the a/b columns).
    static let surround: SIMD3<Double> = SIMD3(0.9, 0.59, 0.9)
    /// J full-scale.
    static let jScale: Double = 100.0
    /// The nonlinear-response normalization reference/offset/scale
    /// (`cam_nl_Y_reference`/`cam_nl_offset`/`cam_nl_scale`, :67-69).
    static let camNlYReference: Double = 100.0
    static let camNlOffset: Double = 0.2713 * camNlYReference
    static let camNlScale: Double = 4.0 * camNlYReference

    /// The Hellwig-form model gamma (`model_gamma`, :71) — cz in CAM16:
    /// surround[1]·(1.48 + √(Y_b/ref)).
    static let modelGamma: Double =
        surround.y * (1.48 + (backgroundLuminance / refLuminance).squareRoot())

    // MARK: - Primaries → matrix plumbing (Utilities.ctl RGBtoXYZ_f33)

    /// RGB→XYZ (math form, rows = matrix rows; the CTL formula restated —
    /// Utilities.ctl :273-316; Y normalized to 1). The CTL assembles its
    /// TRANSPOSED storage (its row 0 = the scaled red primary = the math
    /// COLUMN 0) — here the scaled primaries land in the columns so
    /// `M·(1,1,1) = whiteXYZ` and `M·primRGB = primXYZ` hold directly.
    public static func rgbToXyzMat(_ c: Chromaticities) -> DrtMat3 {
        let x = c.white.x / c.white.y
        let z = (1 - c.white.x - c.white.y) / c.white.y
        let d = c.red.x * (c.blue.y - c.green.y)
            + c.blue.x * (c.green.y - c.red.y)
            + c.green.x * (c.red.y - c.blue.y)
        let sr = (x * (c.blue.y - c.green.y)
            - c.green.x * ((c.blue.y - 1) + c.blue.y * (x + z))
            + c.blue.x * ((c.green.y - 1) + c.green.y * (x + z))) / d
        let sg = (x * (c.red.y - c.blue.y)
            + c.red.x * ((c.blue.y - 1) + c.blue.y * (x + z))
            - c.blue.x * ((c.red.y - 1) + c.red.y * (x + z))) / d
        let sb = (x * (c.green.y - c.red.y)
            - c.red.x * ((c.green.y - 1) + c.green.y * (x + z))
            + c.green.x * ((c.red.y - 1) + c.red.y * (x + z))) / d
        return DrtMat3(
            r0: SIMD3(sr * c.red.x, sg * c.green.x, sb * c.blue.x),
            r1: SIMD3(sr * c.red.y, sg * c.green.y, sb * c.blue.y),
            r2: SIMD3(
                sr * (1 - c.red.x - c.red.y),
                sg * (1 - c.green.x - c.green.y),
                sb * (1 - c.blue.x - c.blue.y)))
    }

    /// XYZ→RGB — the exact inverse.
    static func xyzToRgbMat(_ c: Chromaticities) -> DrtMat3 {
        rgbToXyzMat(c).inverted()
    }

    /// Rec2020 → AP0 (ACES2065-1) — the kernel's FIRST-stage matrix (KD-2:
    /// input is always working-space linear Rec2020; derived from primaries,
    /// independently asserted in Aces2MathTests — never cross-derived from
    /// the ACEScc Rec2020↔AP1 pair).
    static let rec2020ToAP0: DrtMat3 = multiply(
        xyzToRgbMat(ap0), rgbToXyzMat(rec2020Primaries))
    static let ap0ToRec2020: DrtMat3 = rec2020ToAP0.inverted()

    /// Rec2020 primaries (BT.2020/BT.2100, D65) — the working space.
    static let rec2020Primaries = Chromaticities(
        red: SIMD2(0.708, 0.292),
        green: SIMD2(0.170, 0.797),
        blue: SIMD2(0.131, 0.046),
        white: SIMD2(0.3127, 0.3290))

    /// AP0 → AP1 / AP1 → AP0 (the `clamp_AP0_to_AP1` legs).
    static let ap0ToAP1: DrtMat3 = multiply(
        xyzToRgbMat(ap1), rgbToXyzMat(ap0))
    static let ap1ToAP0: DrtMat3 = ap0ToAP1.inverted()

    /// Row-major multiply convenience (A·B in math order).
    static func multiply(_ a: DrtMat3, _ b: DrtMat3) -> DrtMat3 {
        DrtMat3(
            r0: SIMD3(
                a.r0.x * b.r0.x + a.r0.y * b.r1.x + a.r0.z * b.r2.x,
                a.r0.x * b.r0.y + a.r0.y * b.r1.y + a.r0.z * b.r2.y,
                a.r0.x * b.r0.z + a.r0.y * b.r1.z + a.r0.z * b.r2.z),
            r1: SIMD3(
                a.r1.x * b.r0.x + a.r1.y * b.r1.x + a.r1.z * b.r2.x,
                a.r1.x * b.r0.y + a.r1.y * b.r1.y + a.r1.z * b.r2.y,
                a.r1.x * b.r0.z + a.r1.y * b.r1.z + a.r1.z * b.r2.z),
            r2: SIMD3(
                a.r2.x * b.r0.x + a.r2.y * b.r1.x + a.r2.z * b.r2.x,
                a.r2.x * b.r0.y + a.r2.y * b.r1.y + a.r2.z * b.r2.y,
                a.r2.x * b.r0.z + a.r2.y * b.r1.z + a.r2.z * b.r2.z))
    }

    // MARK: - Post-adaptation cone response compression (:185-212)

    /// The nonlinear response (`_post_adaptation_cone_response_compression_fwd`,
    /// :185-190) — signless core.
    static func prcFwdCore(_ rc: Double) -> Double {
        let fLY = pow(rc, 0.42)
        return fLY / (camNlOffset + fLY)
    }

    /// The inverse (:192-198) — clamps Ra at 0.99 (upstream `min(Ra, 0.99)`).
    static func prcInvCore(_ ra: Double) -> Double {
        let raLim = min(ra, 0.99)
        let fLY = (camNlOffset * raLim) / (1 - raLim)
        return pow(fLY, 1 / 0.42)
    }

    /// Signed forward (:200-205, copysign form).
    static func postAdaptationCompressionFwd(_ v: Double) -> Double {
        copysign(prcFwdCore(abs(v)), v)
    }

    /// Signed inverse (:207-212).
    static func postAdaptationCompressionInv(_ v: Double) -> Double {
        copysign(prcInvCore(abs(v)), v)
    }

    // MARK: - J/Achromatic bridges (:214-242)

    /// `Achromatic_n_to_J` = J_scale·A^cz.
    static func achromaticToJ(_ a: Double, cz: Double) -> Double {
        jScale * pow(a, cz)
    }

    /// `J_to_Achromatic_n` = (J/J_scale)^invCz.
    static func jToAchromatic(_ j: Double, invCz: Double) -> Double {
        pow(j / jScale, invCz)
    }

    // MARK: - JMhParams (the per-primaries precomputed set, :926-999)

    /// The precomputed conversion set for ONE primaries triple — the
    /// upstream `JMhParams` struct in math form. Built once per (space,
    /// peak) parameter point; the kernel consumes the float restatement
    /// through the uniforms buffer.
    struct JMhParams: Sendable {
        let rgbToCam16C: DrtMat3       // MATRIX_RGB_to_CAM16_c
        let cam16CToRgb: DrtMat3       // its inverse
        let coneResponseToAab: DrtMat3 // MATRIX_cone_response_to_Aab
        let aabToConeResponse: DrtMat3 // its inverse
        let fLn: Double                // F_L normalized
        public let cz: Double
        public let invCz: Double
        public let awJ: Double                // A_w_J
        public let invAwJ: Double

        /// `init_JMhParams` (:926-999) — math-form derivation:
        /// rgbToCam16C = 100·diag(D)·XYZtoRGB(CAM16_PRI)·RGBtoXYZ(primaries)
        /// (adaptation D rides the CAM16-cone channel scale).
        init(primaries: Chromaticities) {
            let matrix16 = xyzToRgbMat(cam16Primaries)
            let baseConeResponseToAab = DrtMat3(
                // math rows (the CTL stores the transpose):
                // A = 2r + g + b/20 · a = r − 12g/11 + b/11 · b = (r+g−2b)/9
                r0: SIMD3(2.0, 1.0, 1.0 / 20.0),
                r1: SIMD3(1.0, -12.0 / 11.0, 1.0 / 11.0),
                r2: SIMD3(1.0 / 9.0, 1.0 / 9.0, -2.0 / 9.0))

            let rgbToXyz = rgbToXyzMat(primaries)
            // XYZ_w = 100·whiteXYZ; Y_w = 100 exactly.
            let xyzW = rgbToXyz.multiply(SIMD3(
                refLuminance, refLuminance, refLuminance))
            let yW = xyzW.y

            // Step 0 — sharpened RGB of the adapting white.
            let rgbW = matrix16.multiply(xyzW)

            // Viewing-condition parameters.
            let k = 1 / (5 * luminousAscent + 1)
            let k4 = k * k * k * k
            let fL = 0.2 * k4 * (5 * luminousAscent)
                + 0.1 * pow(1 - k4, 2) * pow(5 * luminousAscent, 1.0 / 3.0)
            let fLn = fL / refLuminance
            let cz = modelGamma

            // The exact-adaptation coefficients (D rides per channel).
            let d = SIMD3(
                fLn * yW / rgbW.x, fLn * yW / rgbW.y, fLn * yW / rgbW.z)
            let rgbWc = d * rgbW   // = F_L_n·Y_w in ALL channels (exact form)
            let rgbAw = SIMD3(
                postAdaptationCompressionFwd(rgbWc.x),
                postAdaptationCompressionFwd(rgbWc.y),
                postAdaptationCompressionFwd(rgbWc.z))

            // A_w = 400·(2·aw.x + aw.y + aw.z/20) — the base matrix's first
            // row (×400, the cam_nl_scale) applied to the adapted white.
            let aW = camNlScale * (
                baseConeResponseToAab.r0.x * rgbAw.x
                    + baseConeResponseToAab.r0.y * rgbAw.y
                    + baseConeResponseToAab.r0.z * rgbAw.z)
            let aWJ = prcFwdCore(fL)

            // rgbToCam16C = 100·diag(D)·XYZtoRGB(CAM16)·RGBtoXYZ(primaries).
            let rgbToCam16 = multiply(
                matrix16, rgbToXyz) // cam16 cone response of source RGB
            let scaled = DrtMat3(
                r0: rgbToCam16.r0 * refLuminance,
                r1: rgbToCam16.r1 * refLuminance,
                r2: rgbToCam16.r2 * refLuminance)
            let withAdaptation = DrtMat3(
                r0: scaled.r0 * d.x,
                r1: scaled.r1 * d.y,
                r2: scaled.r2 * d.z)

            // coneResponseToAab: row 0 (A) ÷ A_w; rows a/b × 400·43·surround.z.
            let abScale = 43.0 * surround.z
            let coneResponseToAab = DrtMat3(
                r0: baseConeResponseToAab.r0 * (camNlScale / aW),
                r1: baseConeResponseToAab.r1 * (camNlScale * abScale),
                r2: baseConeResponseToAab.r2 * (camNlScale * abScale))

            self.rgbToCam16C = withAdaptation
            self.cam16CToRgb = withAdaptation.inverted()
            self.coneResponseToAab = coneResponseToAab
            self.aabToConeResponse = coneResponseToAab.inverted()
            self.fLn = fLn
            self.cz = cz
            self.invCz = 1 / cz
            self.awJ = aWJ
            self.invAwJ = 1 / aWJ
        }
    }

    // MARK: - Forward: RGB → Aab → JMh (:254-296)

    /// `RGB_to_Aab` — cone response, PRC compression, Aab matrix.
    static func rgbToAab(
        _ rgb: SIMD3<Double>, _ p: JMhParams
    ) -> SIMD3<Double> {
        let rgbM = p.rgbToCam16C.multiply(rgb)
        let rgbA = SIMD3(
            postAdaptationCompressionFwd(rgbM.x),
            postAdaptationCompressionFwd(rgbM.y),
            postAdaptationCompressionFwd(rgbM.z))
        return p.coneResponseToAab.multiply(rgbA)
    }

    /// `Aab_to_JMh` — A ≤ 0 collapses to (0, 0, 0) (upstream :273-276).
    static func aabToJMh(
        _ aab: SIMD3<Double>, _ p: JMhParams
    ) -> SIMD3<Double> {
        if aab.x <= 0 { return .zero }
        let j = achromaticToJ(aab.x, cz: p.cz)
        let m = (aab.y * aab.y + aab.z * aab.z).squareRoot()
        let h = wrapTo360(radiansToDegrees(atan2(aab.z, aab.y)))
        return SIMD3(j, m, h)
    }

    static func rgbToJMh(
        _ rgb: SIMD3<Double>, _ p: JMhParams
    ) -> SIMD3<Double> {
        aabToJMh(rgbToAab(rgb, p), p)
    }

    // MARK: - Inverse: JMh → Aab → RGB (:298-337)

    /// `JMh_to_Aab` — exact algebraic inverse (no iteration: the ACES 2.0
    /// form inverts the A/J power directly, KD-2 risk note resolved — the
    /// upstream 2.0 simplified form has a CLOSED inverse).
    static func jmhToAab(
        _ jmh: SIMD3<Double>, _ p: JMhParams
    ) -> SIMD3<Double> {
        let a = jToAchromatic(jmh.x, invCz: p.invCz)
        let hRad = degreesToRadians(jmh.z)
        return SIMD3(a, jmh.y * cos(hRad), jmh.y * sin(hRad))
    }

    static func aabToRGB(
        _ aab: SIMD3<Double>, _ p: JMhParams
    ) -> SIMD3<Double> {
        let rgbA = p.aabToConeResponse.multiply(aab)
        let rgbM = SIMD3(
            postAdaptationCompressionInv(rgbA.x),
            postAdaptationCompressionInv(rgbA.y),
            postAdaptationCompressionInv(rgbA.z))
        return p.cam16CToRgb.multiply(rgbM)
    }

    static func jmhToRGB(
        _ jmh: SIMD3<Double>, _ p: JMhParams
    ) -> SIMD3<Double> {
        aabToRGB(jmhToAab(jmh, p), p)
    }

    // MARK: - AP0↔AP1 clamp leg (:339-348)

    /// `clamp_AP0_to_AP1` — project AP0 through AP1, clamp, return to AP0.
    static func clampAP0ToAP1(
        _ aces: SIMD3<Double>, lower: Double, upper: Double
    ) -> SIMD3<Double> {
        let ap1 = ap0ToAP1.multiply(aces)
        let clamped = SIMD3(
            min(max(ap1.x, lower), upper),
            min(max(ap1.y, lower), upper),
            min(max(ap1.z, lower), upper))
        return ap1ToAP0.multiply(clamped)
    }

    // MARK: - Angle helpers (Utilities.ctl :216-224 + OutputTransform :155-163)

    static func radiansToDegrees(_ r: Double) -> Double { r * 180.0 / .pi }
    static func degreesToRadians(_ d: Double) -> Double { d / 180.0 * .pi }

    /// `wrap_to_360` (:155-163).
    static func wrapTo360(_ hue: Double) -> Double {
        let y = hue.truncatingRemainder(dividingBy: 360)
        return y < 0 ? y + 360 : y
    }
}

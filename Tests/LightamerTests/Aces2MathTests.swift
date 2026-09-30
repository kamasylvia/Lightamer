@testable import LightamerCore
import Foundation
import simd
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// Aces2MathTests (Plan M2-6-2 T1/T2/T3, AC#1-#4 — LAYERS bundle, Core level):
// the Float64 ACES 2.0 math face.
//
//   T1 (this section): the CAM16 JMh core — viewing-condition constants
//   asserted one by one, the SMPTE ST 2065-1 matrix anchors, the white/prim
//   anchors, RGB→JMh→RGB round-trips over ramps + colorchecker-like
//   sampling + extreme saturations, and the AP0/AP1 white-invariance
//   (same XYZ → same JMh under either primaries' params).
//
//   T2 (the section below): the limiting-space seven tables + the RGC
//   pure functions.
//
//   T3 (the section after): the ACES 2.0 ODT Float64 reference — tonescale
//   monotonicity, endpoint boundedness, peak-dependence semantics.
// ─────────────────────────────────────────────────────────────────────────────

final class Aces2MathTests: XCTestCase {

    // MARK: - T1: viewing-condition constants (逐常数断言, upstream :60-71)

    func testViewingConditionConstants() {
        XCTAssertEqual(Aces2Cam.refLuminance, 100.0, accuracy: 0)
        XCTAssertEqual(Aces2Cam.luminousAscent, 100.0, accuracy: 0) // L_A
        XCTAssertEqual(Aces2Cam.backgroundLuminance, 20.0, accuracy: 0) // Y_b
        XCTAssertEqual(Aces2Cam.surround.x, 0.9, accuracy: 0)
        XCTAssertEqual(Aces2Cam.surround.y, 0.59, accuracy: 0)
        XCTAssertEqual(Aces2Cam.surround.z, 0.9, accuracy: 0)
        XCTAssertEqual(Aces2Cam.jScale, 100.0, accuracy: 0)
        XCTAssertEqual(Aces2Cam.camNlYReference, 100.0, accuracy: 0)
        XCTAssertEqual(Aces2Cam.camNlOffset, 27.13, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.camNlScale, 400.0, accuracy: 0)
        // The Hellwig-form model gamma (cz): 0.59·(1.48+√0.2) ≈ 1.13705602…
        XCTAssertEqual(Aces2Cam.modelGamma, 0.59 * (1.48 + (0.2).squareRoot()), accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.modelGamma, 1.137056021344975, accuracy: 1e-12)
    }

    // MARK: - T1: chromaticity constants (逐值)

    func testChromaticityConstants() {
        // AP0 (SMPTE ST 2065-1).
        XCTAssertEqual(Aces2Cam.ap0.red.x, 0.73470, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.ap0.red.y, 0.26530, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.ap0.green.x, 0.00000, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.ap0.green.y, 1.00000, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.ap0.blue.x, 0.00010, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.ap0.blue.y, -0.07700, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.ap0.white.x, 0.32168, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.ap0.white.y, 0.33767, accuracy: 1e-12)
        // AP1.
        XCTAssertEqual(Aces2Cam.ap1.red.x, 0.713, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.ap1.red.y, 0.293, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.ap1.green.x, 0.165, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.ap1.green.y, 0.830, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.ap1.blue.x, 0.128, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.ap1.blue.y, 0.044, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.ap1.white.x, 0.32168, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.ap1.white.y, 0.33767, accuracy: 1e-12)
        // The CAM16 sharpened primaries (upstream :928-932).
        XCTAssertEqual(Aces2Cam.cam16Primaries.red.x, 0.8336, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.cam16Primaries.red.y, 0.1735, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.cam16Primaries.green.x, 2.3854, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.cam16Primaries.green.y, -1.4659, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.cam16Primaries.blue.x, 0.087, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.cam16Primaries.blue.y, -0.125, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.cam16Primaries.white.x, 0.333, accuracy: 1e-12)
        XCTAssertEqual(Aces2Cam.cam16Primaries.white.y, 0.333, accuracy: 1e-12)
    }

    // MARK: - T1: SMPTE ST 2065-1 matrix anchors (published spec facts)

    func testAP0MatricesMatchThePublishedAnchors() {
        // Published AP0↔XYZ (ACES documentation; row-major math form —
        // scaled primaries in the COLUMNS, M·(1,1,1) = whiteXYZ).
        let ap0ToXyz = Aces2Cam.rgbToXyzMat(Aces2Cam.ap0)
        XCTAssertEqual(ap0ToXyz.r0.x, 0.952552395938841, accuracy: 1e-9)
        XCTAssertEqual(ap0ToXyz.r0.z, 0.000093678631604, accuracy: 1e-9)
        XCTAssertEqual(ap0ToXyz.r1.x, 0.343966449765075, accuracy: 1e-9)
        XCTAssertEqual(ap0ToXyz.r1.y, 0.728166096613485, accuracy: 1e-9)
        XCTAssertEqual(ap0ToXyz.r1.z, -0.072132546375727, accuracy: 1e-9)
        XCTAssertEqual(ap0ToXyz.r2.z, 1.008825184435015, accuracy: 1e-9)
        let xyzToAp0 = Aces2Cam.xyzToRgbMat(Aces2Cam.ap0)
        XCTAssertEqual(xyzToAp0.r0.x, 1.049811017458754, accuracy: 1e-9)
        XCTAssertEqual(xyzToAp0.r0.z, -0.000097484540577, accuracy: 1e-9)
        XCTAssertEqual(xyzToAp0.r1.x, -0.495903023069619, accuracy: 1e-9)
        XCTAssertEqual(xyzToAp0.r1.y, 1.373313045835589, accuracy: 1e-9)
        XCTAssertEqual(xyzToAp0.r1.z, 0.098240036058067, accuracy: 1e-9)
        XCTAssertEqual(xyzToAp0.r2.z, 0.991252018189460, accuracy: 1e-9)
    }

    func testAP1MatrixMatchesThePublishedAnchor() {
        // The published AP1→XYZ (row-major math form) — the AP1-side
        // INDEPENDENT anchor (KD-2: AP0 and AP1 facts asserted separately,
        // never cross-derived; the AP0→AP1 conversion itself is asserted
        // structurally — same white → unit white map — in the next test).
        // Tolerance 1e-4: the published matrix is itself derived from
        // 3-decimal chromaticities, so its last digits carry that rounding
        // (the AP0 anchors are exact — ST 2065-1 publishes more digits).
        let ap1ToXyz = Aces2Cam.rgbToXyzMat(Aces2Cam.ap1)
        XCTAssertEqual(ap1ToXyz.r0.x, 0.662454181063565, accuracy: 1e-9)
        XCTAssertEqual(ap1ToXyz.r0.y, 0.134004206456433, accuracy: 1e-9)
        XCTAssertEqual(ap1ToXyz.r0.z, 0.156261860668380, accuracy: 1e-4)
        XCTAssertEqual(ap1ToXyz.r1.x, 0.272228716780914, accuracy: 1e-9)
        XCTAssertEqual(ap1ToXyz.r1.y, 0.674081765811148, accuracy: 1e-9)
        XCTAssertEqual(ap1ToXyz.r1.z, 0.053689517418023, accuracy: 1e-9)
        XCTAssertEqual(ap1ToXyz.r2.x, -0.005574649490394, accuracy: 1e-9)
        XCTAssertEqual(ap1ToXyz.r2.y, 0.004060733805703, accuracy: 1e-9)
        XCTAssertEqual(ap1ToXyz.r2.z, 1.010334100679690, accuracy: 1e-4)
    }

    func testAP0ToAP1PreservesXYZAndWhite() {
        // AP0 and AP1 share the SAME white → (1,1,1) must map to (1,1,1)
        // EXACTLY (the structural anchor; the upstream derives this matrix
        // from the same primaries facts — no published table to compare).
        let white = Aces2Cam.ap0ToAP1.multiply(SIMD3(1, 1, 1))
        XCTAssertEqual(simd.reduce_max(abs(white - SIMD3(1, 1, 1))), 0, accuracy: 1e-9)
        // Every color's XYZ survives the hop.
        for v in [SIMD3(1.0, 0.0, 0.0), SIMD3(0.0, 1.0, 0.0), SIMD3(0.0, 0.0, 1.0),
                  SIMD3(0.3, 0.5, 0.2), SIMD3(1.2, 0.1, 0.9)] {
            let xyz = Aces2Cam.rgbToXyzMat(Aces2Cam.ap0).multiply(v)
            let back = Aces2Cam.rgbToXyzMat(Aces2Cam.ap1)
                .multiply(Aces2Cam.ap0ToAP1.multiply(v))
            XCTAssertLessThanOrEqual(
                simd.reduce_max(abs(back - xyz)), 1e-9, "AP0→AP1 XYZ drift at \(v)")
        }
    }

    func testRec2020ToAP0IsSpaceConsistent() {
        // rec2020ToAP0 must carry EVERY color's XYZ unchanged: for the three
        // rec2020 primaries, XYZ(ap0 space) of the mapped value == XYZ of
        // the original (the definition of a gamut conversion matrix).
        for v in [SIMD3(1.0, 0.0, 0.0), SIMD3(0.0, 1.0, 0.0), SIMD3(0.0, 0.0, 1.0)] {
            let xyz2020 = Aces2Cam.rgbToXyzMat(Aces2Cam.rec2020Primaries).multiply(v)
            let inAP0 = Aces2Cam.rec2020ToAP0.multiply(v)
            let xyzAP0 = Aces2Cam.rgbToXyzMat(Aces2Cam.ap0).multiply(inAP0)
            let err = simd.reduce_max(abs(xyz2020 - xyzAP0))
            XCTAssertLessThanOrEqual(err, 1e-9, "rec2020→AP0 XYZ drift at \(v)")
        }
        // Round-trip is the identity.
        let back = Aces2Cam.ap0ToRec2020.multiply(
            Aces2Cam.rec2020ToAP0.multiply(SIMD3(0.3, 0.5, 0.2)))
        XCTAssertEqual(simd.reduce_max(abs(back - SIMD3(0.3, 0.5, 0.2))), 0, accuracy: 1e-9)
    }

    // MARK: - T1: white / primary anchors

    func testWhiteAnchorIsJ100M0() {
        // AP0 white (1,1,1) → J = 100, M = 0 (the ref_luminance identity —
        // exact by construction, asserted ≤1e-9).
        let params = Aces2Cam.JMhParams(primaries: Aces2Cam.ap0)
        let jmh = Aces2Cam.rgbToJMh(SIMD3(1, 1, 1), params)
        XCTAssertEqual(jmh.x, 100.0, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(jmh.y, 1e-9)
    }

    func testHueIsWhiteEncodingInvariant() {
        // AP0 and AP1 share the same white → the same XYZ must produce the
        // same JMh under either primaries' params (a strong transcription
        // anchor: any matrix-order error breaks this immediately).
        let ap0Params = Aces2Cam.JMhParams(primaries: Aces2Cam.ap0)
        let ap1Params = Aces2Cam.JMhParams(primaries: Aces2Cam.ap1)
        // Sample the AP0 unit cube (includes out-of-AP1 saturations).
        for r in stride(from: -0.2, through: 1.2, by: 0.35) {
            for g in stride(from: -0.2, through: 1.2, by: 0.35) {
                for b in stride(from: -0.2, through: 1.2, by: 0.35) {
                    let c0 = SIMD3(r, g, b)
                    let xyz = Aces2Cam.rgbToXyzMat(Aces2Cam.ap0).multiply(c0)
                    let c1 = Aces2Cam.xyzToRgbMat(Aces2Cam.ap1).multiply(xyz)
                    let j0 = Aces2Cam.rgbToJMh(c0, ap0Params)
                    let j1 = Aces2Cam.rgbToJMh(c1, ap1Params)
                    // J/M invariance holds everywhere; the hue angle is
                    // meaningless near achromatic (M→0 — the atan2 of a
                    // vanishing vector), so it is only asserted when both
                    // sides carry real chroma.
                    var dh = abs(j0.z - j1.z)
                    if dh > 180 { dh = 360 - dh }
                    let err = max(abs(j0.x - j1.x), abs(j0.y - j1.y))
                    XCTAssertLessThanOrEqual(err, 1e-8, "JMh drift at \(c0)")
                    if j0.y > 1e-3 && j1.y > 1e-3 {
                        XCTAssertLessThanOrEqual(dh, 1e-6, "hue drift at \(c0)")
                    }
                }
            }
        }
    }

    func testPrimaryHuesAreOrderedAndAnchored() {
        // The AP1 primaries' CAM16 hue angles (recorded baseline — upstream
        // ships no numeric example table; the invariance anchor above is the
        // algorithm-fidelity face, this pins the values; DECISIONS §D3).
        let params = Aces2Cam.JMhParams(primaries: Aces2Cam.ap1)
        // 50%-white blends — the pure AP1 primaries (even at 18%) sit
        // OUTSIDE the CAM16 response domain (A ≤ 0 → the upstream
        // `Aab_to_JMh` guard collapses them to (0,0,0); the ACES 2.0
        // pipeline never asks JMh of them — clamp_AP0_to_AP1 + the RRT keep
        // the working domain inside), so the hue anchor uses in-domain
        // blends. Values = the transcription's recorded baseline (upstream
        // ships no numeric table; DECISIONS §D3).
        let red = Aces2Cam.rgbToJMh(SIMD3(0.18, 0.09, 0.09), params)
        let green = Aces2Cam.rgbToJMh(SIMD3(0.09, 0.18, 0.09), params)
        let blue = Aces2Cam.rgbToJMh(SIMD3(0.09, 0.09, 0.18), params)
        print("ACES2-ANCHOR AP1-red-blend JMh = \(red)")
        print("ACES2-ANCHOR AP1-green-blend JMh = \(green)")
        print("ACES2-ANCHOR AP1-blue-blend JMh = \(blue)")
        // Recorded baseline (self-consistent — regression pins; corrected
        // for the fixed primaries matrices):
        XCTAssertEqual(red.z, 13.98281323068272, accuracy: 1e-6)
        XCTAssertEqual(green.z, 155.6313261207179, accuracy: 1e-6)
        XCTAssertEqual(blue.z, 278.3981706110758, accuracy: 1e-6)
        // Hue ordering around the circle: red < green < blue (no wrap).
        XCTAssertLessThan(red.z, green.z)
        XCTAssertLessThan(green.z, blue.z)
        // M > 0 for all three (they are chromatic by definition).
        XCTAssertGreaterThan(red.y, 0)
        XCTAssertGreaterThan(green.y, 0)
        XCTAssertGreaterThan(blue.y, 0)
    }

    // MARK: - T1: round-trips (≤1e-6, ramp + colorchecker-like + extreme)

    func testRGBJMhRoundTripOverRampsAndSaturations() {
        let paramSets: [(String, Aces2Cam.JMhParams)] = [
            ("ap0", Aces2Cam.JMhParams(primaries: Aces2Cam.ap0)),
            ("ap1", Aces2Cam.JMhParams(primaries: Aces2Cam.ap1)),
        ]
        var samples: [SIMD3<Double>] = []
        // ① grey ramp 0..4 (the working-space scene range).
        for i in 0..<128 {
            let x = 4.0 * Double(i) / 127.0
            samples.append(SIMD3(x, x, x))
        }
        // ② hue × saturation grid (the "colorchecker-like" face — 8 hues ×
        // 5 saturations × 3 luminances around 18% grey).
        for h in 0..<8 {
            let theta = 2.0 * Double.pi * Double(h) / 8.0
            for s in stride(from: 0.0, through: 1.0, by: 0.25) {
                for lum in [0.02, 0.18, 1.2] {
                    var rgb = SIMD3(
                        0.5 + 0.5 * cos(theta),
                        0.5 + 0.5 * sin(theta),
                        0.5 + 0.5 * cos(theta + 2.0943951))
                    rgb = SIMD3(min(max(rgb.x, 0), 1), min(max(rgb.y, 0), 1), min(max(rgb.z, 0), 1))
                    samples.append((SIMD3(lum, lum, lum)) + (rgb - 0.5) * 2.0 * s * lum)
                }
            }
        }
        // ③ extreme saturations: AP0/Rec2020 primaries and secondaries over
        // a log luminance sweep.
        let primaries = [
            SIMD3<Double>(1, 0, 0), SIMD3<Double>(0, 1, 0), SIMD3<Double>(0, 0, 1),
            SIMD3<Double>(1, 1, 0), SIMD3<Double>(1, 0, 1), SIMD3<Double>(0, 1, 1),
        ]
        for p in primaries {
            for i in 0..<12 {
                let lum = 0.01 * pow(10, 4 * Double(i) / 11.0) // 0.01..100
                samples.append(p * lum)
            }
        }
        for (name, params) in paramSets {
            var worst = 0.0
            var worstAt = SIMD3<Double>.zero
            var collapsed = 0
            for rgb in samples {
                let jmh = Aces2Cam.rgbToJMh(rgb, params)
                if jmh.x == 0 {
                    // The upstream `Aab_to_JMh` guard collapses A ≤ 0 to
                    // (0,0,0) — the round-trip is undefined there BY DESIGN
                    // (the real pipeline keeps colors in the A>0 domain via
                    // clamp_AP0_to_AP1 + the tonescale); count and skip.
                    collapsed += 1
                    continue
                }
                let back = Aces2Cam.jmhToRGB(jmh, params)
                let err = simd.reduce_max(abs(back - rgb))
                let rel = err / max(1e-9, simd.reduce_max(abs(rgb)))
                let score = min(err, rel)
                if score > worst { worst = score; worstAt = rgb }
            }
            XCTAssertLessThanOrEqual(
                worst, 1e-6, "\(name) round-trip drift at \(worstAt)")
            XCTAssertLessThan(collapsed, samples.count / 4,
                "\(name): the collapse guard ate too much of the domain")
        }
    }

    func testAabJmhDegenerateFaces() {
        let params = Aces2Cam.JMhParams(primaries: Aces2Cam.ap0)
        // A ≤ 0 collapses to (0, 0, 0) — the upstream :273-276 guard.
        XCTAssertEqual(Aces2Cam.aabToJMh(SIMD3(-1, 3, 4), params), .zero)
        XCTAssertEqual(Aces2Cam.aabToJMh(SIMD3(0, 3, 4), params), .zero)
        // J = 0 → A = 0 → finite RGB (never NaN).
        let rgb = Aces2Cam.jmhToRGB(SIMD3(0, 5, 200), params)
        XCTAssertFalse(rgb.x.isNaN || rgb.y.isNaN || rgb.z.isNaN)
    }

    func testPostAdaptationCompressionRoundTrip() {
        // Fwd/inv round-trip below the 0.99 clamp knee (≤1e-9); the clamp
        // region (> 0.99) is documented non-invertible (upstream :194).
        for i in 0..<256 {
            let x = 0.99 * Double(i) / 255.0
            let back = Aces2Cam.postAdaptationCompressionInv(
                Aces2Cam.postAdaptationCompressionFwd(x))
            XCTAssertEqual(back, x, accuracy: 1e-9)
        }
        // The clamp face: inv(min(fwd(huge), 0.99)) caps below fwd⁻¹(0.99).
        let clamped = Aces2Cam.postAdaptationCompressionInv(1.5)
        XCTAssertLessThanOrEqual(clamped, Aces2Cam.postAdaptationCompressionInv(0.99) + 1e-12)
        // Negative side mirrors by copysign.
        XCTAssertEqual(
            Aces2Cam.postAdaptationCompressionFwd(-0.5),
            -Aces2Cam.postAdaptationCompressionFwd(0.5), accuracy: 0)
    }
}

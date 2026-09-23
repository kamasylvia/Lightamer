import LightamerCore
import LightamerIOP
import simd
import XCTest

/// Plan 06-02 — the blendop composite engine gates.
///
/// T1 batch (this file's CPU section): the L023 FULL round-trip contract on
/// the JzCzhz chain (never a half contract — the five-leg chain rgb → XYZ →
/// JzAzBz → JzCzhz → RGB is pinned as a whole) + the float64 reference
/// sanity gates the GPU parity tests (T2/T3) are defined against.
///
/// T2/T3/T4 batches: GPU `compositeLayer` vs `BlendOpReference` <1e-5 rel
/// per mode × opacity, the Jz matrix-pair GPU probe <1e-6, the hue
/// full-circle sweep, REVERSE byte semantics and the new-mode parity.
final class BlendOpParityTests: XCTestCase {

    /// Component-wise SIMD3 equality with accuracy (XCTest's accuracy
    /// overload needs FloatingPoint — SIMD3<Double> isn't).
    private func assertEqual(
        _ got: SIMD3<Double>, _ ref: SIMD3<Double>, accuracy: Double,
        _ message: String = "", file: StaticString = #filePath, line: UInt = #line
    ) {
        for c in 0..<3 {
            XCTAssertEqual(
                got[c], ref[c], accuracy: accuracy, message,
                file: file, line: line)
        }
    }

    // MARK: - T1: JzCzhz round trip (L023, float64 chain)

    /// The five-leg round trip over a demanding grid (achromatic, primaries,
    /// deep shadows, HDR >1).
    ///
    /// GATE RATIONALE (measured, not aspirational): the dt constant set is
    /// ASYMMETRIC by construction — the forward XYZ→LMS/LMS→IzAzBz matrices
    /// are 7-digit rounded (colorspaces_inline_conversions.h) while the
    /// inverse pair carries 16 digits. The mismatch (~1e-7 relative) is
    /// amplified by the PQ encode leg (pow p = 134.03) to ≈3e-5 relative —
    /// dt's own round trip lives with exactly this, so the float64 gate is
    /// 1e-4 rel with a 1e-6 absolute floor (deep shadows). The EXACT legs
    /// (matrix pair identity, polar trig) are pinned separately below —
    /// that is where the L023 <1e-6-class gates live.
    func testJzCzhzRoundTripFloat64() {
        var samples: [SIMD3<Double>] = [
            SIMD3(0, 0, 0), SIMD3(1, 1, 1), SIMD3(0.5, 0.5, 0.5),
            SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1),
            SIMD3(0.18, 0.18, 0.18), SIMD3(1e-6, 1e-6, 1e-6),
            SIMD3(2.5, 1.0, 0.4), SIMD3(0.01, 0.02, 0.005),
            SIMD3(4.0, 0.02, 1.5), SIMD3(0.55, 0.30, 0.25),
        ]
        for i in 0..<8 {
            samples.append(SIMD3(
                0.05 + 0.13 * Double(i), 0.3 + 0.07 * Double(i), 0.9 - 0.1 * Double(i)))
        }
        var compared = 0
        var maxRel = 0.0
        for rgb in samples {
            let back = JzCzhz.toRGB(JzCzhz.fromRGB(rgb))
            for c in 0..<3 {
                let denom = max(abs(rgb[c]), 1e-9)
                let rel = abs(back[c] - rgb[c]) / denom
                XCTAssertTrue(
                    rel < 1e-4 || abs(back[c] - rgb[c]) < 1e-6,
                    "round trip diverged for \(rgb): got \(back) (rel \(rel))")
                maxRel = max(maxRel, rel)
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")
        XCTAssertLessThanOrEqual(
            maxRel, 1e-4, "float64 round trip gate (dt constant-set floor)")
    }

    /// The EXACT legs of the chain (the L023-style identity gates): the
    /// Rec2020↔XYZ matrix pair is an exact inverse pair, and the polar
    /// JzAzBz⇄JzCzhz conversions round-trip to float64 exactness — no pow
    /// chain, no rounded constants on either side.
    func testJzCzhzExactLegs() {
        // Matrix pair: each COLUMN of xyzToRec2020 must map back through
        // rec2020ToXYZ to a unit vector.
        var maxDev = 0.0
        for c in 0..<3 {
            let col = SIMD3(
                LabRoundTrip.xyzToRec2020[0][c],
                LabRoundTrip.xyzToRec2020[1][c],
                LabRoundTrip.xyzToRec2020[2][c])
            for row in 0..<3 {
                let m = LabRoundTrip.rec2020ToXYZ[row]
                let dot = m[0] * col.x + m[1] * col.y + m[2] * col.z
                let target: Double = row == c ? 1.0 : 0.0
                maxDev = max(maxDev, abs(dot - target))
            }
        }
        XCTAssertLessThan(maxDev, 1e-12, "Rec2020↔XYZ matrix identity")

        // Polar round trip over a hue/chroma grid.
        var compared = 0
        for i in 0..<24 {
            for cz in [0.0001, 0.001, 0.01, 0.05] {
                let h = Double(i) / 24.0
                let jch = SIMD3(0.01, cz, h)
                let back = JzCzhz.fromJzAzBz(JzCzhz.toJzAzBz(jch))
                for c in 0..<3 {
                    XCTAssertEqual(back[c], jch[c], accuracy: 1e-12)
                }
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转")
    }

    /// Achromatic pixels map to (near-)zero chroma. The residual ~3.5e-5 at
    /// mid gray is the 7-digit constant floor of dt's forward Jz matrices
    /// (the Rec2020 D65 white through rec2020ToXYZ differs from the JzAzBz
    /// reference white in the 7th digit) — dt inherits the same behavior on
    /// its own constants, so the gate pins the floor, not zero.
    func testJzCzhzAchromaticChromaIsZero() {
        for v in [0.0, 1e-4, 0.18, 0.5, 1.0, 2.0] {
            let jch = JzCzhz.fromRGB(SIMD3(v, v, v))
            XCTAssertLessThan(
                jch.y, 5e-5, "achromatic \(v) must have ~zero Cz, got \(jch.y)")
            let back = JzCzhz.toRGB(jch)
            for c in 0..<3 {
                XCTAssertLessThan(
                    abs(back[c] - v), 1e-4,
                    "achromatic \(v) round trip channel \(c)")
            }
        }
    }

    /// The dt shortest-path hue formula (blendop.cl:713-733) spot gates:
    /// wrap-around goes the SHORT way through 0, identical hues are exact,
    /// and op=1 lands exactly on hz_b.
    func testMixedHueShortestPath() {
        // Identical hues: s = op branch, result == the hue (mod 1).
        XCTAssertEqual(JzCzhz.mixedHue(0.3, 0.3, opacity: 0.7), 0.3, accuracy: 1e-12)
        // op=1 → hz_b regardless of branch.
        XCTAssertEqual(JzCzhz.mixedHue(0.98, 0.02, opacity: 1.0), 0.02, accuracy: 1e-12)
        XCTAssertEqual(JzCzhz.mixedHue(0.02, 0.98, opacity: 1.0), 0.98, accuracy: 1e-12)
        // The d > 0.5 branch (wrap): 0.98 → 0.02 crosses 0, so at op=0.5
        // the result is 0.0 (half of the short path 0.04 wide).
        let wrapped = JzCzhz.mixedHue(0.98, 0.02, opacity: 0.5)
        XCTAssertTrue(
            abs(wrapped - 0.0) < 1e-12 || abs(wrapped - 1.0) < 1e-12,
            "wrap must cross 0, got \(wrapped)")
        // The direct branch (d < 0.5): plain linear mix at op=0.5.
        XCTAssertEqual(JzCzhz.mixedHue(0.10, 0.30, opacity: 0.5), 0.20, accuracy: 1e-12)
    }

    // MARK: - T1: float64 reference gates (the parity source of truth)

    /// Identity gates at the reference level: op=1 → b for NORMAL (the
    /// composite identity triple), op=0 → a for every mode EXCEPT
    /// colorAdjust — dt's COLORADJUST takes b's lightness UNMIXED
    /// (`to.x = tb.x`, blendop.cl:736 — no opacity factor), so op=0 keeps
    /// b's Jz by formula-inherent dt semantics (recorded in DECISIONS).
    /// REVERSE swaps a/b (normal op=1 + reverse → a).
    func testReferenceIdentityGates() {
        let a = SIMD3(0.3, 1.7, 0.02)
        let b = SIMD3(0.9, 0.1, 2.2)
        for mode in BlendMode.allCases {
            // Perceptual modes round-trip a through JzCzhz even at op=0 —
            // the 1e-4 accuracy is the dt constant-set floor (T1 gate).
            if mode == .colorAdjust { continue }
            assertEqual(
                BlendOpReference.blend(mode, a: a, b: b, opacity: 0), a,
                accuracy: 1e-4, "\(mode) at op=0 must equal a")
        }
        // colorAdjust op=0: Jz == jz_b (unmixed), chroma/hue from a.
        let ja = JzCzhz.fromRGB(a)
        let jb = JzCzhz.fromRGB(b)
        let caOut = JzCzhz.fromRGB(BlendOpReference.blend(.colorAdjust, a: a, b: b, opacity: 0))
        XCTAssertEqual(caOut.x, jb.x, accuracy: 1e-4, "colorAdjust keeps b's Jz at op=0")
        XCTAssertEqual(caOut.y, ja.y, accuracy: 1e-4)
        assertEqual(
            BlendOpReference.blend(.normal, a: a, b: b, opacity: 1), b,
            accuracy: 0, "normal at op=1 must equal b (the identity triple)")
        assertEqual(
            BlendOpReference.blend(.normal, a: a, b: b, opacity: 1, reverse: true), a,
            accuracy: 0, "REVERSE normal op=1 → a (a/b swapped)")
        // 防空转: the fixture really exercises divergence.
        XCTAssertNotEqual(a, b)
    }

    /// Hand-computable spot values per formula family (the table the kernel
    /// transliterates — a wrong formula shows up here first).
    func testReferenceModeSpotValues() {
        let a = SIMD3(0.25, 0.5, 0.75)
        let b = SIMD3(0.6, 0.2, 0.9)
        // multiply: a·b (p=1); with p = exp2(1) = 2 → a·b·2
        assertEqual(BlendOpReference.multiply(a, b, 1, 1), a * b, accuracy: 1e-12, "multiply")
        assertEqual(BlendOpReference.multiply(a, b, 1, 2), a * b * 2, accuracy: 1e-12, "multiply p=2")
        // screen: 1−(1−a)(1−b) = a+b−ab
        assertEqual(BlendOpReference.screen(a, b, 1), a + b - a * b, accuracy: 1e-12, "screen")
        // overlay at a=0.75 (>0.5): 1−2(1−a)(1−b); at a=0.25 (≤0.5): 2ab
        assertEqual(
            BlendOpReference.overlay(a, b, 1),
            SIMD3(2 * 0.25 * 0.6, 2 * 0.5 * 0.2, 1 - 2 * 0.25 * 0.1),
            accuracy: 1e-12, "overlay")
        // softlight keyed on b: b.x=0.6>0.5 → 1−(1−a)(1.5−b); b.y=0.2≤0.5 →
        // a·(b+0.5); b.z=0.9>0.5 → 1−(1−a)(1.5−b)
        assertEqual(
            BlendOpReference.softLight(a, b, 1),
            SIMD3(1 - 0.75 * 0.9, 0.5 * 0.7, 1 - 0.25 * 0.6),
            accuracy: 1e-12, "softlight")
        // hardlight at b=0.6>0.5: 1−2(1−a)(1−b); b=0.2≤0.5: 2ab; b=0.9>0.5: 1−2(1−a)(1−b)
        assertEqual(
            BlendOpReference.hardLight(a, b, 1),
            SIMD3(1 - 2 * 0.75 * 0.4, 2 * 0.5 * 0.2, 1 - 2 * 0.25 * 0.1),
            accuracy: 1e-12, "hardlight")
        // linearBurn: a+b−1, lmin clamp — x: −0.15 → 0; z: 0.65
        assertEqual(
            BlendOpReference.linearBurn(a, b, 1), SIMD3(0, 0, 0.65),
            accuracy: 1e-12, "linearBurn")
        // difference: |a−b|
        assertEqual(
            BlendOpReference.difference(a, b, 1), SIMD3(0.35, 0.3, 0.15),
            accuracy: 1e-12, "difference")
        // lighten/darken: max/min per channel
        assertEqual(BlendOpReference.lighten(a, b, 1), max(a, b), accuracy: 1e-12, "lighten")
        assertEqual(BlendOpReference.darken(a, b, 1), min(a, b), accuracy: 1e-12, "darken")
        // PS dodge: cs=1 → 1; cb=0 → 0; interior min(1, cb/(1−cs))
        assertEqual(
            BlendOpReference.psColorDodge(SIMD3(0, 0.5, 0.5), SIMD3(0.5, 1, 0.75), 1),
            SIMD3(0, 1, 1), accuracy: 1e-12, "dodge")
        // PS burn: cb=1 → 1; cs=0 → 0; interior 1−min(1,(1−cb)/cs)
        assertEqual(
            BlendOpReference.psColorBurn(SIMD3(1, 0.5, 0.5), SIMD3(0.5, 0, 0.25), 1),
            SIMD3(1, 0, 0), accuracy: 1e-12, "burn")
        // opacity mixing: normal op=0.25
        assertEqual(
            BlendOpReference.normal(a, b, 0.25), a * 0.75 + b * 0.25,
            accuracy: 1e-12, "normal mix")
        // opacity² on overlay: op=0.5 → the overlay term weighs 0.25
        assertEqual(
            BlendOpReference.overlay(a, b, 0.5),
            SIMD3(a.x * 0.75 + (2.0 * a.x * b.x) * 0.25,
                  a.y * 0.75 + (2.0 * a.y * b.y) * 0.25,
                  a.z * 0.75 + (1.0 - 2.0 * (1.0 - a.z) * (1.0 - b.z)) * 0.25),
            accuracy: 1e-12, "overlay op²")
    }

    /// The perceptual formulas' structural gates: luminosity keeps a's
    /// chroma but takes b's lightness (Jz), hue keeps a's Jz/Cz with b's hue
    /// angle, colorAdjust takes b's Jz outright (the "adjusted color only"
    /// semantic).
    func testReferencePerceptualStructure() {
        let a = SIMD3(0.55, 0.30, 0.25)
        let b = SIMD3(0.10, 0.45, 0.80)
        let ja = JzCzhz.fromRGB(a)
        let jb = JzCzhz.fromRGB(b)
        XCTAssertGreaterThan(ja.y, 0.001, "fixture a must be chromatic")
        XCTAssertGreaterThan(jb.y, 0.001, "fixture b must be chromatic")

        // hue op=1: out polar == (jz_a, cz_a, hz_b)
        let hueOut = JzCzhz.fromRGB(BlendOpReference.hue(a, b, 1))
        XCTAssertEqual(hueOut.x, ja.x, accuracy: 1e-9)
        XCTAssertEqual(hueOut.y, ja.y, accuracy: 1e-9)
        let hDist = abs(hueOut.z - jb.z)
        XCTAssertTrue(min(hDist, abs(hDist - 1)) < 1e-6, "hue op=1 takes hz_b, got \(hueOut.z)")

        // luminosity op=1: Jz == jz_b, Cz == cz_a
        let lumOut = JzCzhz.fromRGB(BlendOpReference.luminosity(a, b, 1))
        XCTAssertEqual(lumOut.x, jb.x, accuracy: 1e-9)
        XCTAssertEqual(lumOut.y, ja.y, accuracy: 1e-9)

        // saturation op=1: Cz == cz_b, Jz == jz_a
        let satOut = JzCzhz.fromRGB(BlendOpReference.saturation(a, b, 1))
        XCTAssertEqual(satOut.x, ja.x, accuracy: 1e-9)
        XCTAssertEqual(satOut.y, jb.y, accuracy: 1e-9)

        // color op=1: Jz == jz_a, Cz == cz_b, hz == hz_b
        let colOut = JzCzhz.fromRGB(BlendOpReference.color(a, b, 1))
        XCTAssertEqual(colOut.x, ja.x, accuracy: 1e-9)
        XCTAssertEqual(colOut.y, jb.y, accuracy: 1e-9)

        // colorAdjust op=1: Jz == jz_b (the "adjusted color only" semantic)
        let adjOut = JzCzhz.fromRGB(BlendOpReference.colorAdjust(a, b, 1))
        XCTAssertEqual(adjOut.x, jb.x, accuracy: 1e-9)
        XCTAssertEqual(adjOut.y, jb.y, accuracy: 1e-9)
    }
}

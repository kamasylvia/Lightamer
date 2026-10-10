@testable import LightamerCore
import simd
import XCTest

/// ColorMatchOklabTests (Plan M5-1-01 T1, KD-1) — the Oklab statistics-domain
/// conversion proofs:
///
/// - published constant anchors: the D65 white point maps to (1, 0, 0)
///   (Ottosson's published construction — M1/M2 rows sum to 1/1/0) and the
///   Rec2020 primaries land on the values derived from the published
///   constants (hardcoded to 8 digits, derivation in OklabMath.swift's
///   constant single-source header);
/// - gray-axis neutrality: the merged M1C rows sum to 1, so Rec2020 grays
///   stay on the neutral axis;
/// - the round-trip gate (Rec2020 gamut corners + gray axis + a seeded
///   random set) — the Float32 measured band feeds DECISIONS;
/// - the Float32/Float64 twin band (production vs golden twin);
/// - negative-component / out-of-domain behavior: the conversion clamps
///   NOTHING (the matrix-arm full-domain ruling) — negative inputs are
///   finite and sign-symmetric (the signed-cbrt contract; a bare pow(x,1/3)
///   would NaN — banned on both sides).
final class ColorMatchOklabTests: XCTestCase {

    /// Deterministic LCG (FilmPrintBake precedent) — the random sets are
    /// reproducible run-to-run and machine-to-machine.
    private struct LCG {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            // Numerical Recipes LCG constants (public domain).
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
        /// Float in [-scale, scale].
        mutating func uniform(_ scale: Double) -> Double {
            Double(next() >> 11) / Double(1 << 53) * 2 * scale - scale
        }
        /// Float in [0, scale].
        mutating func uniformPositive(_ scale: Double) -> Double {
            Double(next() >> 11) / Double(1 << 53) * scale
        }
    }

    // MARK: - Published constant anchors

    /// White (D65 in Rec2020 coords = (1,1,1)) maps to Oklab (1, 0, 0) —
    /// the published construction identity (M1C/M2 row sums).
    func testWhitePointAnchor() {
        let lab = OklabMath.linearRec2020ToOklab(SIMD3<Float>(1, 1, 1))
        XCTAssertEqual(Double(lab.x), 1.0, accuracy: 1e-6, "white L")
        XCTAssertEqual(Double(lab.y), 0.0, accuracy: 1e-6, "white a")
        XCTAssertEqual(Double(lab.z), 0.0, accuracy: 1e-6, "white b")
        let lab64 = OklabMath.linearRec2020ToOklab64(SIMD3<Double>(1, 1, 1))
        // 1e-7, not 1e-8: the twin elevates the PUBLISHED Float32-rounded
        // constants (L048 ②), whose row sums carry a ~3e-8 residual — the
        // anchor tolerance sits just above the constant rounding, not the
        // math's ideal 1e-8 face.
        XCTAssertEqual(lab64.x, 1.0, accuracy: 1e-7, "white L (64)")
        XCTAssertEqual(lab64.y, 0.0, accuracy: 1e-7, "white a (64)")
        XCTAssertEqual(lab64.z, 0.0, accuracy: 1e-7, "white b (64)")
    }

    /// The Rec2020 primaries' Oklab coordinates — derived from the published
    /// constant set (Float64, derivation in the OklabMath header); hardcoded
    /// here at 8 digits. These anchor the domain rotation: a Rec2020 red must
    /// NOT land on the sRGB-red anchor (the merged chain is live).
    func testRec2020PrimaryAnchors() {
        let anchors: [(SIMD3<Float>, SIMD3<Double>, String)] = [
            (SIMD3<Float>(1, 0, 0), SIMD3<Double>(0.68708904, 0.33273042, 0.14943825), "R"),
            (SIMD3<Float>(0, 1, 0), SIMD3<Double>(0.82977721, -0.41577437, 0.21556253), "G"),
            (SIMD3<Float>(0, 0, 1), SIMD3<Double>(0.42344826, -0.16137844, -0.34713245), "B"),
        ]
        for (rgb, want, name) in anchors {
            let got = OklabMath.linearRec2020ToOklab64(SIMD3<Double>(rgb))
            for ch in 0..<3 {
                // 1e-7 = the elevated-constant rounding face (see the white
                // anchor note) + the derivation print precision.
                XCTAssertEqual(got[ch], want[ch], accuracy: 1e-7, "\(name)[\(ch)] (64)")
            }
            // The Float32 production face agrees to its own band.
            let got32 = OklabMath.linearRec2020ToOklab(rgb)
            for ch in 0..<3 {
                XCTAssertEqual(Double(got32[ch]), want[ch], accuracy: 1e-6, "\(name)[\(ch)] (32)")
            }
        }
    }

    /// Gray-axis neutrality: every Rec2020 gray maps to a=b=0 (the merged
    /// M1C rows sum to 1 — the chain preserves the neutral axis).
    func testGrayAxisNeutrality() {
        var rng = LCG(seed: 0xA1)
        for _ in 0..<64 {
            let t = Float(rng.uniformPositive(8.0))
            let lab = OklabMath.linearRec2020ToOklab(SIMD3<Float>(t, t, t))
            XCTAssertEqual(Double(lab.y), 0.0, accuracy: 1e-5, "gray a at t=\(t)")
            XCTAssertEqual(Double(lab.z), 0.0, accuracy: 1e-5, "gray b at t=\(t)")
            let back = OklabMath.oklabToLinearRec2020(lab)
            XCTAssertEqual(Double(back.x), Double(t), accuracy: 1e-4, "gray L roundtrip at t=\(t)")
        }
    }

    // MARK: - Round-trip gate

    /// Float32 round-trip over the Rec2020 gamut corners, the gray axis and
    /// a seeded random set. The measured band is recorded in DECISIONS.
    func testRoundTripFloat32() {
        var worst: Float = 0
        func probe(_ rgb: SIMD3<Float>) {
            let lab = OklabMath.linearRec2020ToOklab(rgb)
            let back = OklabMath.oklabToLinearRec2020(lab)
            let err = max(
                abs(back.x - rgb.x), abs(back.y - rgb.y), abs(back.z - rgb.z))
            // Relative to the magnitude for large values (HDR inputs reach
            // 8.0 — the relative band is the honest face; the floor handles
            // the near-zero arm).
            let rel = err / max(max(abs(rgb.x), abs(rgb.y), abs(rgb.z)), 1e-3)
            worst = max(worst, rel)
            XCTAssertFalse(lab.x.isNaN, "L NaN at \(rgb)")
            XCTAssertFalse(lab.y.isNaN, "a NaN at \(rgb)")
            XCTAssertFalse(lab.z.isNaN, "b NaN at \(rgb)")
        }
        // Gamut corners (unit + HDR).
        for s: Float in [1.0, 4.0, 8.0] {
            probe(SIMD3(s, 0, 0)); probe(SIMD3(0, s, 0)); probe(SIMD3(0, 0, s))
            probe(SIMD3(s, s, 0)); probe(SIMD3(0, s, s)); probe(SIMD3(s, 0, s))
            probe(SIMD3(s, s, s))
        }
        // Gray axis.
        for i in 0..<16 { probe(SIMD3(repeating: Float(i) / 15)) }
        // Seeded random set (full domain — negatives included).
        var rng = LCG(seed: 0xC0FFEE)
        for _ in 0..<2048 {
            probe(SIMD3<Float>(
                Float(rng.uniform(2.0)), Float(rng.uniform(2.0)), Float(rng.uniform(2.0))))
        }
        // The measured band (DECISIONS): worst 1.19e-6 relative over the
        // drive set — the gate pins ~8× headroom around it (实测带收窄钉门).
        XCTAssertLessThanOrEqual(Double(worst), 1e-5, "Float32 roundtrip rel band, worst=\(worst)")
    }

    /// The Float64 golden twin round-trip — the reference band (~1e-8 over
    /// the same drive set; constants are the elevated Float32 literals).
    func testRoundTripFloat64Twin() {
        var worst = 0.0
        var rng = LCG(seed: 0xC0FFEE)
        func probe(_ rgb: SIMD3<Double>) {
            let lab = OklabMath.linearRec2020ToOklab64(rgb)
            let back = OklabMath.oklabToLinearRec202064(lab)
            let err = max(
                abs(back.x - rgb.x), abs(back.y - rgb.y), abs(back.z - rgb.z))
            worst = max(worst, err / max(max(abs(rgb.x), abs(rgb.y), abs(rgb.z)), 1e-3))
        }
        for s in [1.0, 4.0, 8.0] {
            probe(SIMD3(s, 0, 0)); probe(SIMD3(0, s, 0)); probe(SIMD3(0, 0, s))
        }
        for _ in 0..<2048 {
            probe(SIMD3(rng.uniform(2.0), rng.uniform(2.0), rng.uniform(2.0)))
        }
        XCTAssertLessThanOrEqual(worst, 5e-7, "Float64 twin roundtrip rel band, worst=\(worst)")
    }

    /// The twin band: production Float32 vs the Float64 twin on the same
    /// drive set (the L048 comparison face — the twin is the production
    /// math's reference; the band feeds the G2 parity expectations).
    func testProductionTwinBand() {
        var worst: Float = 0
        var rng = LCG(seed: 0xBEEF)
        for _ in 0..<1024 {
            let rgb64 = SIMD3<Double>(rng.uniform(2.0), rng.uniform(2.0), rng.uniform(2.0))
            let lab32 = OklabMath.linearRec2020ToOklab(SIMD3<Float>(rgb64))
            let lab64 = OklabMath.linearRec2020ToOklab64(rgb64)
            let diff = abs(lab32 - SIMD3<Float>(lab64))
            worst = max(worst, max(diff.x, max(diff.y, diff.z)))
        }
        // Measured band (DECISIONS): worst 5.72e-6 abs in Oklab units over
        // the drive set (Float32 input quantization + the pow faces) — the
        // gate pins ~3.5× headroom (实测带收窄钉门).
        XCTAssertLessThanOrEqual(Double(worst), 2e-5, "production/twin abs band, worst=\(worst)")
    }

    // MARK: - Negative / out-of-domain behavior (the zero-clamp policy)

    /// Negative and out-of-gamut inputs are FINITE and sign-symmetric: the
    /// conversion is a pure analytic map with no clamp anywhere (the
    /// matrix-arm full-domain ruling, OQ-M5-1-4). The signed-cbrt contract:
    /// odd symmetry through the origin.
    func testNegativeInputsFiniteAndOdd() {
        let neg = OklabMath.linearRec2020ToOklab(SIMD3<Float>(-0.4, 0.2, -1.5))
        for v in [neg.x, neg.y, neg.z] {
            XCTAssertFalse(v.isNaN, "NaN leaked from a negative input")
            XCTAssertFalse(v.isInfinite, "inf leaked from a negative input")
        }
        // Odd symmetry: ok(-v) == -ok(v) channel-wise (the signed cube root
        // and the linear maps are odd; exact sign symmetry at ±same input).
        let pos = OklabMath.linearRec2020ToOklab(SIMD3<Float>(0.4, -0.2, 1.5))
        let mirror = OklabMath.linearRec2020ToOklab(SIMD3<Float>(-0.4, 0.2, -1.5))
        for ch in 0..<3 {
            XCTAssertEqual(Double(pos[ch]), Double(-mirror[ch]), accuracy: 1e-5, "odd[\(ch)]")
        }
        // HDR far-out input stays finite.
        let hdr = OklabMath.linearRec2020ToOklab(SIMD3<Float>(64, -8, 128))
        for v in [hdr.x, hdr.y, hdr.z] {
            XCTAssertFalse(v.isNaN)
            XCTAssertFalse(v.isInfinite)
        }
        // Inverse direction: an out-of-domain Oklab triplet round-trips.
        let rgb = OklabMath.oklabToLinearRec2020(SIMD3<Float>(2.0, -1.2, 0.9))
        for v in [rgb.x, rgb.y, rgb.z] {
            XCTAssertFalse(v.isNaN)
            XCTAssertFalse(v.isInfinite)
        }
    }
}

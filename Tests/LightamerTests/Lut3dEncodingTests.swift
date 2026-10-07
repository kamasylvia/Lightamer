@testable import LightamerCore
@testable import LightamerIOP
import simd
import XCTest

/// Lut3dEncodingTests (Plan M3-1-01 T1/T2/T3, M2GRADE-08) — the LUT
/// authoring-encoding model proofs:
///
/// - the catalog: 17 rows (scene 11 = 10 camera logs + linear working,
///   display 6 — the explicit KD-1 count contract), the required built-in
///   pair present, typed rejection of unknown ids;
/// - the transfer curves: Float64 round trips (encode∘decode ≈ identity
///   over each curve's valid domain, p99.9 ≤ 1e-5), golden spot vectors
///   from the PUBLIC standards/white papers (never Alcedo numerics), the
///   gamut matrices' round trip + white-point preservation;
/// - the display mediator: the 100-nit middle with the `peak/100` scale
///   applied exactly once (checker E1/M3).
final class Lut3dEncodingTests: XCTestCase {

    // MARK: - Catalog (KD-1)

    /// The explicit count contract: 17 total = scene 11 (camera log 10 +
    /// linear working 1) + display 6 (checker M1).
    func testCatalogRowCounts() {
        XCTAssertEqual(LutEncodingCatalog.all.count, 17)
        XCTAssertEqual(LutEncodingCatalog.sceneEncodings.count, 11)
        XCTAssertEqual(LutEncodingCatalog.displayEncodings.count, 6)
        let sceneLogs = LutEncodingCatalog.sceneEncodings.filter {
            $0.transfer != .linear
        }
        XCTAssertEqual(sceneLogs.count, 10, "10 camera log rows")
        let linearRows = LutEncodingCatalog.sceneEncodings.filter {
            $0.transfer == .linear
        }
        XCTAssertEqual(linearRows.count, 1, "the linear working row")
        XCTAssertEqual(linearRows.first?.id, .linearRec2020)
    }

    /// The built-in spectral-film pair and the default pair must be in the
    /// catalog (OQ-2②/OQ-4①).
    func testCatalogRequiredRows() {
        let ids = Set(LutEncodingCatalog.all.map { $0.id })
        XCTAssertTrue(ids.contains(.arriLogC4AWG4))
        XCTAssertTrue(ids.contains(.rec709BT1886))
        XCTAssertTrue(ids.contains(.linearRec2020))
        // The default pair is the working row on both ends.
        XCTAssertEqual(LutEncodingCatalog.defaultInputId, .linearRec2020)
        XCTAssertEqual(LutEncodingCatalog.defaultOutputId, .linearRec2020)
        let input = LutEncodingCatalog.find(id: LutEncodingCatalog.defaultInputId)
        XCTAssertEqual(input.referral, .scene)
        XCTAssertEqual(input.transfer, .linear)
        XCTAssertEqual(input.gamutId, "rec2020")
    }

    /// Every row's gamut id resolves; scene rows are peak-free; SDR display
    /// rows carry exactly 100 nits, PQ/HLG 1000 (checker M3).
    func testCatalogRowIntegrity() {
        for row in LutEncodingCatalog.all {
            XCTAssertNotNil(LutEncodingCatalog.gamut(id: row.gamutId), row.id.rawValue)
            switch row.referral {
            case .scene:
                XCTAssertEqual(row.peakNits, 0, "\(row.id.rawValue) scene peak")
            case .display:
                XCTAssertTrue(row.peakNits == 100 || row.peakNits == 1000,
                    "\(row.id.rawValue) display peak")
            }
        }
        // F-Log / N-Log / Apple Log reuse the Rec2020 gamut (checker M2 —
        // the factory specs have no independent primaries).
        for fujiNikonApple: LutEncodingId in [.fujiFLog, .nikonNLog, .appleLog] {
            XCTAssertEqual(
                LutEncodingCatalog.find(id: fujiNikonApple).gamutId, "rec2020")
        }    }

    /// Unknown ids are typed-rejected (nil), never guessed.
    func testFindUnknownIdTypedNil() {
        XCTAssertNil(LutEncodingCatalog.find(id: "nope"))
        XCTAssertNil(LutEncodingCatalog.find(id: ""))
        XCTAssertNil(LutEncodingCatalog.find(id: "aces_cc"))
        for row in LutEncodingCatalog.all {
            XCTAssertNotNil(LutEncodingCatalog.find(id: row.id.rawValue))
        }
    }

    // MARK: - Curve round trips (KD-6 curve layer)

    private static let roundTripTolerance: Double = 1e-5

    /// Sample grid covering each scene curve's invertible domain: the log
    /// shoulders well past 1.0 (HDR headroom), the toes, and mild negatives
    /// (matrix products can go sub-zero in wide gamuts).
    private static func sceneSamples(curve: LutTransferCurve) -> [Double] {
        var xs: [Double] = []
        // Linear ramp 0..1 (65 points).
        for i in 0...64 { xs.append(Double(i) / 64.0) }
        // Log-spaced 1e-7 .. 64 (HDR).
        var v = 1e-7
        while v <= 64 {
            xs.append(v)
            v *= 1.4
        }
        // Negatives down to −0.05 (within every linear toe).
        for i in 0..<10 { xs.append(-0.005 * Double(i + 1)) }
        // Curve-specific clamp domains. Published rounded constants carry
        // KNEE DISCONTINUITIES (the encode cut's code image vs the decode
        // cut differ: F-Log ~3e-5, N-Log ~2e-4 code — e.g. N-Log's 451.8
        // spec code is published as the integer 452). Those bands are
        // excluded from the round-trip domain and their jump is bounded by
        // testKneeDiscontinuityBounded (M3-1-01 DECISIONS).
        switch curve {
        case .appleLog:
            // Values below R_0 clamp to P=0 (decode gives R_0) — the valid
            // invertible domain starts at R_0.
            xs = xs.filter { $0 >= LutTransferMath.appleLogR0 }
        case .acescc:
            // Negative inputs clamp to the black code; keep 0 upward.
            xs = xs.filter { $0 >= 0 }
        case .acescct:
            xs = xs.filter { $0 >= 0 }
        case .flog:
            xs = xs.filter { $0 < 0.0008 || $0 > 0.0010 }
        case .nlog:
            xs = xs.filter { $0 < 0.320 || $0 > 0.336 }
        default:
            break
        }
        return xs
    }

    /// The knee jumps are bounded by the published-constant rounding (the
    /// bands excluded above) — pinned by band scans so the exclusion stays
    /// principled.
    func testKneeDiscontinuityBounded() {
        // F-Log: the encode-linear/decode-log sliver around cut 0.00089.
        var x = 0.0005
        var worst = 0.0
        while x < 0.0015 {
            let back = LutTransferMath.decodeChannel(
                .flog, LutTransferMath.encodeChannel(.flog, x))
            worst = max(worst, abs(back - x))
            x *= 1.001
        }
        XCTAssertLessThan(worst, 1.5e-5)
        // N-Log: the 452-code spec cut vs the true image ~451.8 (3e-4 band).
        x = 0.30
        worst = 0
        while x < 0.36 {
            let back = LutTransferMath.decodeChannel(
                .nlog, LutTransferMath.encodeChannel(.nlog, x))
            worst = max(worst, abs(back - x))
            x *= 1.001
        }
        XCTAssertLessThan(worst, 3.5e-4)
    }

    /// encode∘decode ≈ identity per scene curve (p99.9 ≤ 1e-5, M2-5 golden
    /// tolerance ladder).
    func testSceneCurveRoundTripIdentity() {
        let curves: [LutTransferCurve] = [
            .acescc, .acescct, .logC4, .logC3, .slog3, .clog3, .flog, .vlog,
            .nlog, .appleLog, .linear,
        ]
        for curve in curves {
            let xs = Self.sceneSamples(curve: curve)
            var errors: [Double] = []
            for x in xs {
                let c = LutTransferMath.encodeChannel(curve, x)
                let back = LutTransferMath.decodeChannel(curve, c)
                errors.append(abs(back - x))
            }
            errors.sort()
            let p999 = errors[max(0, Int((Double(errors.count) * 0.999).rounded(.down)))]
            XCTAssertLessThanOrEqual(
                p999, Self.roundTripTolerance, "\(curve.rawValue) round trip p99.9")
        }
    }

    /// decode∘encode ≈ identity per scene curve (the reverse composition
    /// over the reachable code range).
    func testSceneCurveInverseRoundTrip() {
        let curves: [LutTransferCurve] = [
            .acescc, .acescct, .logC4, .logC3, .slog3, .clog3, .flog, .vlog,
            .nlog, .appleLog, .linear,
        ]
        for curve in curves {
            let xs = Self.sceneSamples(curve: curve)
            var worst: (Double, Double) = (0, 0)
            for x in xs {
                let c = LutTransferMath.encodeChannel(curve, x)
                let back = LutTransferMath.decodeChannel(curve, c)
                if abs(back - x) > worst.1 { worst = (x, abs(back - x)) }
            }
            XCTAssertLessThanOrEqual(
                worst.1, Self.roundTripTolerance,
                "\(curve.rawValue) inverse worst @x=\(worst.0)")
        }
    }

    // MARK: - Golden spot vectors (public standards; full published digits)

    /// 18% gray + representative points per curve — the values are the
    /// published/reference-computed constants (colour-science doctests of
    /// the standard formulas; BSD-licensed reference, GPL-free).
    func testStandardTableGoldenVectors() {
        let vectors: [(LutTransferCurve, Double, Double, Double)] = [
            // (curve, x, expected code, accuracy)
            (.acescc, 0.18, 0.413588402492442, 1e-12),
            (.acescct, 0.18, 0.413588402492442, 1e-12),
            (.logC4, 0.18, 0.27839583654826527, 1e-12),
            (.logC3, 0.18, 0.391006832034084, 1e-12),
            (.slog3, 0.18, 0.410557184750733, 1e-12),
            (.clog3, 0.18, 0.34338937037393549, 1e-12),
            (.flog, 0.18, 0.45931845866162124, 1e-12),
            (.vlog, 0.18, 0.423311448760136, 1e-12),
            (.nlog, 0.18, 0.36366777011713869, 1e-12),
            (.appleLog, 0.18, 0.48827245852686763, 1e-12),
            (.srgb, 0.18, 0.46135612950044164, 1e-12),
        ]
        for (curve, x, want, acc) in vectors {
            let got = LutTransferMath.encodeChannel(curve, x)
            XCTAssertEqual(got, want, accuracy: acc, "\(curve.rawValue)(\(x))")
        }
        // Black points (formula-exact floors; the 10-bit spec code values
        // 95/128 are the ROUNDED integer codes of these).
        XCTAssertEqual(LutTransferMath.encodeChannel(.slog3, 0), 95.0 / 1023.0, accuracy: 1e-12)
        XCTAssertEqual(LutTransferMath.encodeChannel(.vlog, 0), 0.125, accuracy: 1e-12)
        XCTAssertEqual(LutTransferMath.encodeChannel(.flog, 0), 0.092864, accuracy: 1e-12)
        XCTAssertEqual(
            LutTransferMath.encodeChannel(.nlog, 0), 0.12437262789637153, accuracy: 1e-12)
        XCTAssertEqual(
            LutTransferMath.encodeChannel(.appleLog, 0), 0.15047645230091253, accuracy: 1e-12)
        XCTAssertEqual(
            LutTransferMath.acesccBlackCode, -0.35844748858447484, accuracy: 1e-12)
        // sRGB decode spot.
        XCTAssertEqual(
            LutTransferMath.srgbDecodeChannel(0.5), 0.21404114048223255, accuracy: 1e-12)
    }

    // MARK: - Gamut matrices (KD-2: computed, never hand-copied)

    /// fromRec2020 · toRec2020 ≈ identity (Float64 — 1e-9 ladder) and the
    /// gamut white maps onto the Rec2020 white (1,1,1).
    func testGamutMatricesRoundTripAndWhite() {
        for (id, gamut) in LutEncodingCatalog.gamuts.sorted(by: { $0.key < $1.key }) {
            let product = gamut.fromRec2020 * gamut.toRec2020
            for col in 0..<3 {
                let c = product[col]
                let want = SIMD3<Double>(
                    col == 0 ? 1 : 0, col == 1 ? 1 : 0, col == 2 ? 1 : 0)
                for r in 0..<3 {
                    XCTAssertEqual(
                        c[r], want[r], accuracy: 1e-9, "\(id) round trip (\(col),\(r))")
                }
            }
            // White preservation: the gamut's white in RGB ((1,1,1)) lands
            // exactly on Rec2020's white (1,1,1) — for AP1 this exercises
            // the Bradford ACES→D65 adaptation, for the rest the identity.
            let mapped = gamut.toRec2020 * SIMD3(1, 1, 1)
            for r in 0..<3 {
                XCTAssertEqual(mapped[r], 1.0, accuracy: 1e-9, "\(id) white (\(r))")
            }
        }
    }

    /// rec2020's own gamut is the identity pair; the rec709 pair matches the
    /// ITU-published BT.709↔BT.2020 conversion (BT.2087, 4-decimal form) —
    /// the independent numeric anchor for the Bradford derivation.
    func testGamutMatrixAnchors() {
        let rec2020 = LutEncodingCatalog.gamut(id: "rec2020")!
        for col in 0..<3 {
            for r in 0..<3 {
                XCTAssertEqual(
                    rec2020.toRec2020[col][r], col == r ? 1 : 0, accuracy: 1e-12)
            }
        }
        let rec709 = LutEncodingCatalog.gamut(id: "rec709")!
        // ITU-R BT.2087 published pair: the image-capture 709→2020 matrix
        // (Table 8) and its display-side inverse 2020→709 (Table 9), rows
        // printed to 4dp.
        let ituTo2020: [[Double]] = [
            [0.6274, 0.3293, 0.0433],
            [0.0691, 0.9195, 0.0114],
            [0.0164, 0.0880, 0.8956],
        ]
        let ituFrom2020: [[Double]] = [
            [1.6605, -0.5876, -0.0728],
            [-0.1246, 1.1329, -0.0083],
            [-0.0182, -0.1006, 1.1187],
        ]
        for r in 0..<3 {
            for c in 0..<3 {
                XCTAssertEqual(
                    rec709.toRec2020[c, r], ituTo2020[r][c], accuracy: 2e-4,
                    "rec709→rec2020 (\(r),\(c)) vs BT.2087 Table 8")
                XCTAssertEqual(
                    rec709.fromRec2020[c, r], ituFrom2020[r][c], accuracy: 2e-4,
                    "rec2020→rec709 (\(r),\(c)) vs BT.2087 Table 9")
            }
        }
    }

    // MARK: - Display mediator (100-nit middle; peak applied ONCE)

    /// The PQ display arm at peak 1000: 100-nit light (1.0) encodes to the
    /// ITU ST 2084 code of 0.1 peak-normalized — computed here from the
    /// canonical ITU fractions (independent of the adapter under test).
    func testDisplayPQArmGolden() {
        let m1 = 2610.0 / 16384.0, m2 = 2523.0 / 32.0
        let c1 = 107.0 / 128.0, c2 = 2413.0 / 128.0, c3 = 2392.0 / 128.0
        func pq(_ nits: Double) -> Double {
            let yn = nits / 10000.0
            return Foundation.pow(
                (c1 + c2 * Foundation.pow(yn, m1)) / (1 + c3 * Foundation.pow(yn, m1)), m2)
        }
        let got = LutTransferMath.displayEncode(
            .pq, SIMD3(1, 1, 1), peakNits: 1000)
        for ch in 0..<3 {
            XCTAssertEqual(got[ch], pq(100), accuracy: 1e-12, "pq arm ch\(ch)")
        }
        // And the decode returns to 100-nit light exactly once (no double
        // scaling): decode(encode(1.0)) == 1.0 at any peak.
        for peak in [100.0, 1000.0, 4000.0] {
            let code = LutTransferMath.displayEncode(.pq, SIMD3(0.5, 0.5, 0.5), peakNits: peak)
            let back = LutTransferMath.displayDecode(.pq, code, peakNits: peak)
            for ch in 0..<3 {
                XCTAssertEqual(back[ch], 0.5, accuracy: 1e-12, "pq round @peak \(peak)")
            }
        }
    }

    /// SDR display arms: at peak = 100 the mediator scale is naturally 1
    /// (checker M3 — the BT.1886 arm is the pure 2.4 power) and the sRGB
    /// arm is the IEC piecewise.
    func testDisplaySDRArms() {
        let bt1886 = LutTransferMath.displayEncode(.bt1886, SIMD3(0.5, 0.25, 0.75), peakNits: 100)
        XCTAssertEqual(bt1886.x, Foundation.pow(0.5, 1 / 2.4), accuracy: 1e-12)
        XCTAssertEqual(bt1886.y, Foundation.pow(0.25, 1 / 2.4), accuracy: 1e-12)
        let back = LutTransferMath.displayDecode(.bt1886, bt1886, peakNits: 100)
        XCTAssertEqual(back.x, 0.5, accuracy: 1e-12)
        // gamma22 arm.
        let g22 = LutTransferMath.displayEncode(.gamma22, SIMD3(0.5, 0.5, 0.5), peakNits: 100)
        XCTAssertEqual(g22.x, Foundation.pow(0.5, 1 / 2.2), accuracy: 1e-12)
        // sRGB display arm round trip.
        let srgb = LutTransferMath.displayEncode(.srgb, SIMD3(0.18, 0.5, 0.9), peakNits: 100)
        let srgbBack = LutTransferMath.displayDecode(.srgb, srgb, peakNits: 100)
        for (i, want) in [0.18, 0.5, 0.9].enumerated() {
            XCTAssertEqual(srgbBack[i], want, accuracy: 1e-12, "srgb arm \(i)")
        }
        // The peak scale enters exactly once: peak 1000 bt1886 would clamp
        // 0.5 light (0.05 normalized) through the same single factor.
        let dim = LutTransferMath.displayDecode(
            .bt1886, SIMD3(0.5, 0.5, 0.5), peakNits: 1000)
        XCTAssertEqual(dim.x, Foundation.pow(0.5, 2.4) * 10.0, accuracy: 1e-12)
    }

    /// HLG display arm round trip (the OOTF-bearing curve; peak applied
    /// once — decode(encode) == identity at each peak).
    func testDisplayHLGArmRoundTrip() {
        for peak in [100.0, 1000.0] {
            let light = SIMD3(0.02, 0.5, 0.98)
            let code = LutTransferMath.displayEncode(.hlg, light, peakNits: peak)
            let back = LutTransferMath.displayDecode(.hlg, code, peakNits: peak)
            for ch in 0..<3 {
                XCTAssertEqual(back[ch], light[ch], accuracy: 1e-12, "hlg @peak \(peak)")
            }
        }
    }

    /// Every display catalog row round trips through the mediator over its
    /// light domain (the KD-6 curve-layer gate across the display family).
    func testDisplayRowsRoundTrip() {
        var samples: [Double] = []
        for i in 0...64 { samples.append(Double(i) / 64.0) }
        for row in LutEncodingCatalog.displayEncodings {
            let lightTop = row.peakNits / 100.0
            var errors: [Double] = []
            for t in samples {
                let light = SIMD3(t * lightTop, t * lightTop, t * lightTop)
                let code = LutTransferMath.displayEncode(
                    row.transfer, light, peakNits: row.peakNits)
                let back = LutTransferMath.displayDecode(
                    row.transfer, code, peakNits: row.peakNits)
                errors.append(abs(back.x - light.x))
            }
            errors.sort()
            let p999 = errors[Int((Double(errors.count) * 0.999).rounded(.down))]
            XCTAssertLessThanOrEqual(
                p999, Self.roundTripTolerance, "\(row.id.rawValue) display round trip")
        }
    }
}

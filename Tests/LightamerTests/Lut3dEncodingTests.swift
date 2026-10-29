@testable import LightamerCore
@testable import LightamerIOP
import Foundation
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
        // M9-4 T3: the catalog expanded 17 -> 27 (scene 11 -> 18, display
        // 6 -> 9) — the add-only pin lives in LutEncodingExpansionTests.
        XCTAssertEqual(LutEncodingCatalog.all.count, 27)
        XCTAssertEqual(LutEncodingCatalog.sceneEncodings.count, 18)
        XCTAssertEqual(LutEncodingCatalog.displayEncodings.count, 9)
        let sceneLogs = LutEncodingCatalog.sceneEncodings.filter {
            $0.transfer != .linear
        }
        XCTAssertEqual(sceneLogs.count, 17, "17 camera log rows")
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
                // M9-4 T3 (勘误④): the P3 gamma-2.6 rows carry the DCI
                // reference white 48 (the upstream literal — NOT our
                // 100-nit display convention).
                XCTAssertTrue(row.peakNits == 100 || row.peakNits == 1000
                    || row.peakNits == 48,
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

// MARK: - Params additive + bake (M3-1-01 T2, KD-3)

final class Lut3dBakeTests: XCTestCase {

    private final class Resolver: Lut3dModule.LutResolving, @unchecked Sendable {
        var tables: [String: CubeLut] = [:]
        func lut(named: String) -> CubeLut? { tables[named] }
    }

    private var resolver: Resolver!
    private var metal: MetalContext!

    override func setUpWithError() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        resolver = Resolver()
        metal = try MetalContext()
    }

    private func makeModule() -> Lut3dModule {
        Lut3dModule(device: metal.device, resolver: resolver)
    }

    /// An identity lattice table (table value = its own position — the
    /// "log-domain identity table" that eats the sampling arm).
    private func identityTable(level: Int) -> CubeLut {
        let d = Double(level - 1)
        let data: [SIMD3<Float>] = (0..<(level * level * level)).map { i in
            let r = i % level, g = (i / level) % level, b = i / (level * level)
            return SIMD3(
                Float(Double(r) / d), Float(Double(g) / d), Float(Double(b) / d))
        }
        return CubeLut(kind: .lut3d(size: level), data: data)
    }

    // MARK: - Hash zero drift (OQ-1① byte contract)

    /// The default (unannotated) params MUST encode byte-identically to the
    /// legacy two-key blob — no new keys emitted for the nil pair, so every
    /// pre-M3 paramsHash survives bit-for-bit (PipeCacheKey zero invalidation).
    func testParamsEncodingZeroDrift() {
        let encoded = ParamsCoding.encode(Lut3dModule.Params())
        let legacy =
            #"{"colorspace":"sRGB","interpolation":"tetrahedral"}"#
        XCTAssertEqual(String(data: encoded, encoding: .utf8), legacy)
        XCTAssertEqual(
            StableHash.hash(encoded),
            StableHash.hash(Data(legacy.utf8)),
            "paramsHash over the default params = the legacy hash")
        // Named fields present → they appear; nil pair never does.
        let withPair = ParamsCoding.encode(
            Lut3dModule.Params(
                lutName: "a.cube", inputEncoding: .arriLogC4AWG4,
                outputEncoding: .rec709BT1886))
        let json = String(data: withPair, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains(#""inputEncoding":"arri_logc4_awg4""#))
        XCTAssertTrue(json.contains(#""outputEncoding":"rec709_bt1886""#))
    }

    /// Tolerant decode: missing keys = nil pair; unknown rawValue degrades
    /// to nil (never throws into the sidecar/history loader).
    func testParamsDecodeTolerant() throws {
        let legacy =
            #"{"colorspace":"sRGB","interpolation":"tetrahedral","lutName":"a.cube"}"#
        let params = try JSONDecoder().decode(
            Lut3dModule.Params.self, from: Data(legacy.utf8))
        XCTAssertNil(params.inputEncoding)
        XCTAssertNil(params.outputEncoding)
        XCTAssertEqual(params.lutName, "a.cube")

        let unknownPair =
            #"{"colorspace":"sRGB","interpolation":"tetrahedral","inputEncoding":"made_up_id","outputEncoding":"also_made_up"}"#
        let degraded = try JSONDecoder().decode(
            Lut3dModule.Params.self, from: Data(unknownPair.utf8))
        XCTAssertNil(degraded.inputEncoding)
        XCTAssertNil(degraded.outputEncoding)

        let validPair =
            #"{"colorspace":"sRGB","interpolation":"tetrahedral","inputEncoding":"arri_logc4_awg4","outputEncoding":"rec709_bt1886"}"#
        let good = try JSONDecoder().decode(
            Lut3dModule.Params.self, from: Data(validPair.utf8))
        XCTAssertEqual(good.inputEncoding, .arriLogC4AWG4)
        XCTAssertEqual(good.outputEncoding, .rec709BT1886)
    }

    // MARK: - Bake vs Float64 CPU reference (KD-6 bake layer)

    /// A synthetic log-coded gradient table with a KNOWN inverse (the
    /// table = logc4-encoded identity), pair (logc4 → bt1886): the baked
    /// composite vs the Float64 CPU chain per voxel (p99.9 ≤ 1e-5). The
    /// CPU chain uses the TEST-side sampler (Lut3dKernelTests.cpuLut3d,
    /// an independent double-write of the kernel sample leg).
    func testBakeCompositeVsCPUReference() throws {
        let level = 9
        let d = Double(level - 1)
        // table(position) = LogC4_encode(position) — a "log domain" table.
        let table = CubeLut(
            kind: .lut3d(size: level),
            data: (0..<(level * level * level)).map { i in
                let r = i % level, g = (i / level) % level, b = i / (level * level)
                let v = SIMD3(Double(r) / d, Double(g) / d, Double(b) / d)
                let e = LutTransferMath.encode(.logC4, v)
                return SIMD3(Float(e.x), Float(e.y), Float(e.z))
            })
        resolver.tables["logc4.cube"] = table

        let inputRow = LutEncodingCatalog.find(id: .arriLogC4AWG4)
        let outputRow = LutEncodingCatalog.find(id: .rec709BT1886)
        let inGamut = LutEncodingCatalog.gamut(id: inputRow.gamutId)!
        let outGamut = LutEncodingCatalog.gamut(id: outputRow.gamutId)!

        let module = makeModule()
        var piece = IOPiece()
        module.commitParams(
            Lut3dModule.Params(
                lutName: "logc4.cube", colorspace: .rec2020,
                inputEncoding: .arriLogC4AWG4, outputEncoding: .rec709BT1886),
            into: &piece)
        let baked = try XCTUnwrap(module.lastCompositedTable)

        var errors: [Double] = []
        for (i, voxel32) in baked.enumerated() {
            let r = i % level, g = (i / level) % level, b = i / (level * level)
            let voxel = SIMD3(Double(r) / d, Double(g) / d, Double(b) / d)
            // CPU reference: encode arm → independent test sampler → decode arm.
            let linear = inGamut.fromRec2020 * voxel
            let pos = LutTransferMath.encode(.logC4, linear)
            let sampled = Lut3dKernelTests.cpuLut3d(
                pos, table: table.data, level: level,
                domainMin: table.domainMin, domainMax: table.domainMax,
                interpolation: .tetrahedral)
            let light = LutTransferMath.displayDecode(
                .bt1886, sampled, peakNits: outputRow.peakNits)
            let want = outGamut.toRec2020 * light
            let got = SIMD3<Double>(voxel32)
            for ch in 0..<3 {
                errors.append(abs(got[ch] - want[ch]))
            }
        }
        errors.sort()
        let p999 = errors[Int((Double(errors.count) * 0.999).rounded(.down))]
        XCTAssertLessThanOrEqual(p999, 1e-5, "composite vs Float64 CPU reference")
    }

    // MARK: - Direction-probe goldens (checker E1 — anti-misread-self-reference)

    /// Probe A (input arm): the identity table eats the sample arm — with
    /// pair (logc4 → linear) the composite IS `LogC4_encode(FromRec2020(AWG4)·voxel)`.
    /// An arm-order misread (input DECODE first) produces a wildly
    /// different curve and this goes red.
    func testDirectionProbeInputEncodeArm() throws {
        resolver.tables["identity.cube"] = identityTable(level: 7)
        let module = makeModule()
        var piece = IOPiece()
        module.commitParams(
            Lut3dModule.Params(
                lutName: "identity.cube", colorspace: .rec2020,
                inputEncoding: .arriLogC4AWG4, outputEncoding: .linearRec2020),
            into: &piece)
        let baked = try XCTUnwrap(module.lastCompositedTable)
        assertDirection(
            baked, level: 7,
            closedForm: { voxel in
                let linear = LutEncodingCatalog.gamut(id: "awg4")!.fromRec2020 * voxel
                return LutTransferMath.encode(.logC4, linear)
            }, label: "input encode arm")
    }

    /// Probe B (output arm): identity table, pair (linear → bt1886) —
    /// the composite IS `ToRec2020(Rec709)·pow(voxel, 2.4)`. An arm-order
    /// misread (output ENCODE) goes red.
    func testDirectionProbeOutputDecodeArm() throws {
        resolver.tables["identity.cube"] = identityTable(level: 7)
        let module = makeModule()
        var piece = IOPiece()
        module.commitParams(
            Lut3dModule.Params(
                lutName: "identity.cube", colorspace: .rec2020,
                inputEncoding: .linearRec2020, outputEncoding: .rec709BT1886),
            into: &piece)
        let baked = try XCTUnwrap(module.lastCompositedTable)
        assertDirection(
            baked, level: 7,
            closedForm: { voxel in
                let code = SIMD3(
                    Foundation.pow(voxel.x, 2.4),
                    Foundation.pow(voxel.y, 2.4),
                    Foundation.pow(voxel.z, 2.4))
                return LutEncodingCatalog.gamut(id: "rec709")!.toRec2020 * code
            }, label: "output decode arm")
    }

    /// Probe C (full pair): identity table, pair (logc4 → bt1886) —
    /// `ToRec2020(Rec709)·pow(LogC4_encode(FromRec2020(AWG4)·voxel), 2.4)`.
    func testDirectionProbeFullPair() throws {
        resolver.tables["identity.cube"] = identityTable(level: 7)
        let module = makeModule()
        var piece = IOPiece()
        module.commitParams(
            Lut3dModule.Params(
                lutName: "identity.cube", colorspace: .rec2020,
                inputEncoding: .arriLogC4AWG4, outputEncoding: .rec709BT1886),
            into: &piece)
        let baked = try XCTUnwrap(module.lastCompositedTable)
        assertDirection(
            baked, level: 7,
            closedForm: { voxel in
                let linear = LutEncodingCatalog.gamut(id: "awg4")!.fromRec2020 * voxel
                let code = LutTransferMath.encode(.logC4, linear)
                let light = SIMD3(
                    Foundation.pow(code.x, 2.4),
                    Foundation.pow(code.y, 2.4),
                    Foundation.pow(code.z, 2.4))
                return LutEncodingCatalog.gamut(id: "rec709")!.toRec2020 * light
            }, label: "full pair direction")
    }

    private func assertDirection(
        _ baked: [SIMD3<Float>], level: Int,
        closedForm: (SIMD3<Double>) -> SIMD3<Double>, label: String
    ) {
        let d = Double(level - 1)
        var worst: (Double, Double) = (0, 0)
        for (i, v32) in baked.enumerated() {
            let r = i % level, g = (i / level) % level, b = i / (level * level)
            let voxel = SIMD3(Double(r) / d, Double(g) / d, Double(b) / d)
            let want = closedForm(voxel)
            let got = SIMD3<Double>(v32)
            for ch in 0..<3 {
                let e = abs(got[ch] - want[ch])
                if e > worst.1 { worst = (voxel.x, e) }
            }
        }
        XCTAssertLessThanOrEqual(worst.1, 1e-5, "\(label) worst @x=\(worst.0)")
    }

    // MARK: - Bake counter three states + LRU (KD-3)

    /// Default pair (or legacy params with the nil pair) = fast path: zero
    /// bake. A pair change = exactly one bake. Repeating the pair = LRU
    /// hit, zero bake. Past 16 entries the least-recent composite is
    /// evicted and re-baked on demand.
    func testBakeCountThreeStatesAndLRU() {
        let level = 5
        resolver.tables["t.cube"] = identityTable(level: level)
        let module = makeModule()

        // Fast path (nil pair = the default pair, unit domain).
        var piece = IOPiece()
        module.commitParams(Lut3dModule.Params(lutName: "t.cube"), into: &piece)
        XCTAssertEqual(module.bakeCount, 0, "fast path: zero bake")
        XCTAssertNil(module.lastCompositedTable, "fast path: source verbatim")

        // One pair = exactly one bake.
        module.commitParams(
            Lut3dModule.Params(
                lutName: "t.cube", colorspace: .rec2020,
                inputEncoding: .arriLogC4AWG4, outputEncoding: .rec709BT1886),
            into: &piece)
        XCTAssertEqual(module.bakeCount, 1)
        // Same pair again = LRU hit.
        module.commitParams(
            Lut3dModule.Params(
                lutName: "t.cube", colorspace: .rec2020,
                inputEncoding: .arriLogC4AWG4, outputEncoding: .rec709BT1886),
            into: &piece)
        XCTAssertEqual(module.bakeCount, 1, "LRU hit: zero rebake")

        // Fill the LRU past 16 with distinct OUTPUT ids, then return to the
        // first pair — it was evicted and bakes once more.
        let outputs: [LutEncodingId] = [
            .rec709BT1886, .rec709SRGB, .rec709Gamma22, .displayP3SRGB,
            .rec2100PQ1000, .rec2100HLG1000, .linearRec2020,
        ]
        var combos: [(LutEncodingId, LutEncodingId)] = []
        outer: for input in LutEncodingCatalog.sceneEncodings.map({ $0.id }) {
            for output in outputs {
                combos.append((input, output))
                if combos.count >= Lut3dModule.compositeCacheLimit { break outer }
            }
        }
        XCTAssertEqual(combos.count, Lut3dModule.compositeCacheLimit)
        let firstPair = (LutEncodingId.arriLogC4AWG4, LutEncodingId.rec709BT1886)
        var expectedBakes = 1  // the first-pair bake above; the repeat was a hit
        for combo in combos where combo != firstPair {
            module.commitParams(
                Lut3dModule.Params(
                    lutName: "t.cube", colorspace: .rec2020,
                    inputEncoding: combo.0, outputEncoding: combo.1),
                into: &piece)
            expectedBakes += 1
        }
        // 15 fresh bakes (the combo equal to the cached first pair is an
        // LRU hit) — the cache now holds 16 entries exactly.
        XCTAssertEqual(module.bakeCount, expectedBakes, "each distinct pair bakes once")
        // One MORE distinct pair pushes past 16 — the least-recent entry
        // (the first pair) is evicted…
        module.commitParams(
            Lut3dModule.Params(
                lutName: "t.cube", colorspace: .rec2020,
                inputEncoding: .canonCLog3, outputEncoding: .rec709SRGB),
            into: &piece)
        expectedBakes += 1
        XCTAssertEqual(module.bakeCount, expectedBakes, "17th insert evicts")
        // …so the first pair re-bakes on demand.
        module.commitParams(
            Lut3dModule.Params(
                lutName: "t.cube", colorspace: .rec2020,
                inputEncoding: .arriLogC4AWG4, outputEncoding: .rec709BT1886),
            into: &piece)
        expectedBakes += 1
        XCTAssertEqual(module.bakeCount, expectedBakes, "evicted entry rebakes")
    }

    /// Non-unit-domain tables under the DEFAULT pair stay byte-verbatim
    /// (the OQ-1① contract is STRONGER than Alcedo's `HasUnitDomain` fast
    /// path: the HDR-domain storage tests pin the native domain uniforms —
    /// the domain remap only happens inside a real pair bake).
    func testNonUnitDomainDefaultPairStaysVerbatim() {
        let level = 5
        var lut = identityTable(level: level)
        lut.domainMin = SIMD3(-0.5, -0.5, -0.5)
        lut.domainMax = SIMD3(1.5, 1.5, 1.5)
        resolver.tables["wide.cube"] = lut
        let module = makeModule()
        var piece = IOPiece()
        module.commitParams(
            Lut3dModule.Params(lutName: "wide.cube", colorspace: .rec2020), into: &piece)
        XCTAssertEqual(module.bakeCount, 0, "default pair: verbatim even off-unit-domain")
        XCTAssertNil(module.lastCompositedTable)
        XCTAssertNotNil(piece.data)
    }

    /// Encoding pairs never apply to 1D tables (KD-3 boundary) — the ramp
    /// uploads verbatim, zero bake.
    func test1DSkipsEncodingBake() {
        let ramp = CubeLut(
            kind: .lut1d(size: 8),
            data: (0..<8).map {
                SIMD3(Float($0) / 7, Float($0) / 7, Float($0) / 7)
            })
        resolver.tables["ramp.cube"] = ramp
        let module = makeModule()
        var piece = IOPiece()
        module.commitParams(
            Lut3dModule.Params(
                lutName: "ramp.cube", colorspace: .rec2020,
                inputEncoding: .arriLogC4AWG4, outputEncoding: .rec709BT1886),
            into: &piece)
        XCTAssertEqual(module.bakeCount, 0, "1D boundary: no bake")
        XCTAssertNil(module.lastCompositedTable)
        XCTAssertNotNil(piece.data, "1D still commits the ramp")
    }

    /// Concurrent commitParams/process on ONE shared instance stays alive
    /// (the stateLock regression, 08dd061 shape — overlapping pipe runs).
    func testConcurrentCommitProcessStayAlive() async throws {
        let level = 9
        resolver.tables["t.cube"] = identityTable(level: level)
        let module = makeModule()

        let width = 16, height = 16
        func makeTexture() -> (any MTLTexture) {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .shared
            return metal.device.makeTexture(descriptor: descriptor)!
        }
        let input = makeTexture()
        let output = makeTexture()
        // A deliberate-race carrier: the module under test is deliberately
        // shared across overlapping tasks (the coordinator's live box set
        // shape). @unchecked here is the POINT of the test.
        final class Box: @unchecked Sendable {
            let module: Lut3dModule
            let metal: MetalContext
            let input: any MTLTexture
            let output: any MTLTexture
            init(_ m: Lut3dModule, _ ctx: MetalContext, _ i: any MTLTexture, _ o: any MTLTexture) {
                module = m; metal = ctx; input = i; output = o
            }
        }
        let box = Box(module, metal, input, output)

        await withTaskGroup(of: Void.self) { group in
            for round in 0..<8 {
                group.addTask {
                    var piece = IOPiece()
                    let params: Lut3dModule.Params =
                        round % 2 == 0
                        ? Lut3dModule.Params(
                            lutName: "t.cube", colorspace: .rec2020,
                            inputEncoding: .arriLogC4AWG4, outputEncoding: .rec709BT1886)
                        : Lut3dModule.Params(lutName: "t.cube", colorspace: .rec2020)
                    box.module.commitParams(params, into: &piece)
                    if piece.data != nil {
                        try? await box.module.process(
                            input: box.input, output: box.output,
                            roiIn: ROI(x: 0, y: 0, width: width, height: height, scale: 1),
                            roiOut: ROI(x: 0, y: 0, width: width, height: height, scale: 1),
                            piece: &piece, metal: box.metal)
                    }
                }
            }
            await group.waitForAll()
        }
        _ = module.bakeCount  // post-storm state read must not trap
    }
}

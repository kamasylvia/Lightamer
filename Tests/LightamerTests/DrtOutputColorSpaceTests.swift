import CoreGraphics
import CoreImage
import Foundation
import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// DrtOutputColorSpaceTests (Plan M2-9-02 T1, KD-1 — EXPORT bundle) — the
// OQ-7-A output-ICC resolver:
//
//   1. THE CARTESIAN DOMAIN: all 42 (space × eotf) combos behave — the 9
//      legalEOTFs combos RESOLVE, the other 33 are TYPED rejections
//      (AppError.invalidParameter; the record layer may persist linear /
//      gamma18, the export mapping refuses them).
//   2. THE PRIMARIES ANCHORS: the calibrated arms' ICC rXYZ/gXYZ/bXYZ equal
//      the canonical Bradford-D50 constants (the same values Alcedo's
//      generator ships — read-only benchmark) within the s15Fixed16 storage
//      floor; the XYZ basis arm carries the adapted identity matrix.
//   3. THE TRC ANCHORS: the curv-1 gamma decodes EXACTLY — a value encoded
//      in the arm's space decodes to value^gamma in linear Rec709 (the
//      0.7297 → {0.5, 0.4694, 0.4405} family, u8Fixed8 carrier precision).
//   4. THE HDR SYSTEM ARMS: rec2020+st2084/hlg → the kCGColorSpaceITUR_2100_*
//      named profiles, p3d65+st2084 → kCGColorSpaceDisplayP3_PQ (the m2-6-3
//      D2 viewport precedent's same system-space choice).
//   5. THE EXIT-LEG IDENTITY: source == target (the SAME cached instance)
//      passes gray bytes unchanged through ColorSync — the E3 consumption
//      face the DRT export leg rides.
//   6. DETERMINISM + CACHE: identical bytes per combo across calls; one
//      instance per combo forever (the D-13-2-7 instance-stability rule).
// ─────────────────────────────────────────────────────────────────────────────

final class DrtOutputColorSpaceTests: XCTestCase {

    // MARK: - 1: the cartesian domain (42 combos, no default arms)

    func testLegalLinkageCombosResolve() throws {
        // The legalEOTFs mirror — every UI-reachable pair.
        let legal: [(DrtEncodingSpace, DrtEotf)] = [
            (.rec709, .bt1886), (.rec709, .gamma22),
            (.p3d65, .gamma22), (.p3d65, .st2084),
            (.p3d60, .gamma26), (.p3dci, .gamma26), (.xyz, .gamma26),
            (.rec2020, .st2084), (.rec2020, .hlg),
        ]
        for (space, eotf) in legal {
            let resolved = try DrtOutputColorSpace.drtOutputColorSpace(
                space: space, eotf: eotf)
            XCTAssertEqual(
                resolved.model, .rgb,
                "\(space.rawValue)+\(eotf.rawValue) must resolve to an RGB profile")
        }
    }

    func testEveryLegalCombosMatchesTheLinkageTable() throws {
        // The resolver's accept set must EQUAL legalEOTFs — no drift between
        // the linkage table and the mapping (a UI-reachable pair the mapping
        // refuses would be a dead export menu; a refused pair it accepts
        // would betray the linkage ruling).
        for space in DrtEncodingSpace.allCases {
            for eotf in DrtEotf.allCases {
                let isLegal = legalEOTFs(for: space).contains(eotf)
                if isLegal {
                    _ = try DrtOutputColorSpace.drtOutputColorSpace(
                        space: space, eotf: eotf)
                } else {
                    do {
                        _ = try DrtOutputColorSpace.drtOutputColorSpace(
                            space: space, eotf: eotf)
                        XCTFail(
                            "\(space.rawValue)+\(eotf.rawValue) is outside "
                                + "legalEOTFs — the mapping must refuse it")
                    } catch let error as AppError {
                        guard case .invalidParameter = error else {
                            return XCTFail(
                                "expected .invalidParameter for "
                                    + "\(space.rawValue)+\(eotf.rawValue), got \(error)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - 2: the primaries anchors (canonical Bradford-D50 constants)

    /// ICC tag reader: the first `sig` XYZType triple.
    private func xyzTag(_ space: CGColorSpace, _ sig: String) -> [Double]? {
        guard let icc = space.copyICCData() as Data?, icc.count > 132 else { return nil }
        let bytes = [UInt8](icc)
        func u32(_ o: Int) -> Int {
            Int(bytes[o]) << 24 | Int(bytes[o + 1]) << 16
                | Int(bytes[o + 2]) << 8 | Int(bytes[o + 3])
        }
        func s15(_ o: Int) -> Double {
            Double(Int32(bitPattern: UInt32(u32(o)))) / 65536.0
        }
        for i in 0..<u32(128) {
            let entry = 132 + i * 12
            guard String(bytes: bytes[entry..<(entry + 4)], encoding: .ascii) == sig
            else { continue }
            let offset = u32(entry + 4)
            guard String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii) == "XYZ "
            else { return nil }
            return [s15(offset + 8), s15(offset + 12), s15(offset + 16)]
        }
        return nil
    }

    /// The curv-1 TRC reader: (count, u8Fixed8 gamma raw).
    private func trcGamma(_ space: CGColorSpace) -> (count: Int, raw: UInt16)? {
        guard let icc = space.copyICCData() as Data?, icc.count > 132 else { return nil }
        let bytes = [UInt8](icc)
        func u32(_ o: Int) -> Int {
            Int(bytes[o]) << 24 | Int(bytes[o + 1]) << 16
                | Int(bytes[o + 2]) << 8 | Int(bytes[o + 3])
        }
        for i in 0..<u32(128) {
            let entry = 132 + i * 12
            guard String(bytes: bytes[entry..<(entry + 4)], encoding: .ascii) == "rTRC"
            else { continue }
            let offset = u32(entry + 4)
            guard String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii) == "curv"
            else { return nil }
            let count = u32(offset + 8)
            guard count == 1 else { return (count, 0) }
            let raw = UInt16(bytes[offset + 12]) << 8 | UInt16(bytes[offset + 13])
            return (1, raw)
        }
        return nil
    }

    /// The s15Fixed16 storage floor: parsed tag values are quantized to
    /// 1/65536 — a half-LSB tolerance is the exactness bound (the plan's
    /// ≤1e-6 read against the QUANTIZED constants below).
    private let s15Floor = 1.0 / 65536.0 / 2.0

    func testRec709PrimariesAnchor() throws {
        let space = try DrtOutputColorSpace.drtOutputColorSpace(
            space: .rec709, eotf: .gamma22)
        // The canonical Bradford-D50 Rec709 matrix (the public sRGB ICC
        // constants family; byte-identical to Alcedo's generator output).
        let expected: [String: [Double]] = [
            "rXYZ": [0.436035, 0.222488, 0.013916],
            "gXYZ": [0.385117, 0.716904, 0.097061],
            "bXYZ": [0.143051, 0.060608, 0.713913],
        ]
        for (sig, value) in expected {
            let parsed = try XCTUnwrap(xyzTag(space, sig), "\(sig) missing")
            for (i, component) in value.enumerated() {
                XCTAssertEqual(
                    parsed[i], component, accuracy: s15Floor,
                    "\(sig)[\(i)] must equal the Bradford-D50 constant")
            }
        }
    }

    func testP3AndXYZPrimariesAnchors() throws {
        let p3d65 = try DrtOutputColorSpace.drtOutputColorSpace(
            space: .p3d65, eotf: .gamma22)
        let p3d65R = try XCTUnwrap(xyzTag(p3d65, "rXYZ"))
        XCTAssertEqual(p3d65R[0], 0.515121, accuracy: s15Floor)
        XCTAssertEqual(p3d65R[1], 0.241196, accuracy: s15Floor)
        // P3's red sits outside the D50-adapted neutral axis — a slightly
        // negative Z is the CORRECT Bradford output, not a defect.
        XCTAssertEqual(p3d65R[2], -0.001053, accuracy: s15Floor)

        // The XYZ basis arm: the identity matrix Bradford-adapted from white
        // E — R ≈ (1, 0, 0) tilted by the adaptation, never singular.
        let xyz = try DrtOutputColorSpace.drtOutputColorSpace(
            space: .xyz, eotf: .gamma26)
        let xyzR = try XCTUnwrap(xyzTag(xyz, "rXYZ"))
        XCTAssertEqual(xyzR[0], 0.997787, accuracy: s15Floor)
        let xyzG = try XCTUnwrap(xyzTag(xyz, "gXYZ"))
        XCTAssertEqual(xyzG[1], 1.018326, accuracy: s15Floor)
        let xyzB = try XCTUnwrap(xyzTag(xyz, "bXYZ"))
        XCTAssertEqual(xyzB[2], 0.818878, accuracy: s15Floor)
    }

    // MARK: - 3: the TRC anchors (curv-1 power decode)

    func testPowerGammaTRCAnchor() throws {
        let space = try DrtOutputColorSpace.drtOutputColorSpace(
            space: .rec709, eotf: .gamma22)
        let trc = try XCTUnwrap(trcGamma(space), "the TRC must be a curv tag")
        XCTAssertEqual(trc.count, 1, "count 1 = the u8Fixed8 power face")
        // u8Fixed8 floor: 2.2 → 563/256 (2.19922) — exact raw pin.
        XCTAssertEqual(trc.raw, 563, "gamma 2.2 rides the u8Fixed8 lattice")
    }

    /// The value encoded in the arm's space decodes to value^gamma in linear
    /// Rec709 — the TRC is the record's EOTF, not an approximation of sRGB.
    func testTRCDecodesExactlyPerArm() throws {
        let linear = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB))
        let context = CIContext(options: nil)
        let cases: [(DrtEncodingSpace, DrtEotf, Double)] = [
            (.rec709, .gamma22, 2.2), (.rec709, .bt1886, 2.4),
            (.p3d65, .gamma22, 2.2), (.p3d60, .gamma26, 2.6),
            (.p3dci, .gamma26, 2.6), (.xyz, .gamma26, 2.6),
        ]
        for (space, eotf, gamma) in cases {
            let arm = try DrtOutputColorSpace.drtOutputColorSpace(
                space: space, eotf: eotf)
            // 0.7297 encoded (linear 0.5 under γ2.2) — each arm decodes its
            // own power. Expected uses the u8Fixed8-quantized gamma (the
            // carrier floor, ≤1/256 relative).
            let encoded = 0.7297 as CGFloat
            var plane = [Float](repeating: 0, count: 4)
            plane[0] = Float(encoded); plane[1] = Float(encoded)
            plane[2] = Float(encoded); plane[3] = 1
            let image = CIImage(
                bitmapData: plane.withUnsafeBytes { Data($0) }, bytesPerRow: 16,
                size: CGSize(width: 1, height: 1), format: .RGBAf, colorSpace: arm)
            var out = [Float](repeating: 0, count: 4)
            context.render(
                image, toBitmap: &out, rowBytes: 16,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: CIFormat.RGBAf, colorSpace: linear)
            let carrierGamma = Double(UInt16((gamma * 256.0).rounded())) / 256.0
            let expected = pow(Double(encoded), carrierGamma)
            XCTAssertEqual(
                Double(out[0]), expected, accuracy: 1e-3,
                "\(space.rawValue)+\(eotf.rawValue): the TRC is the record's "
                    + "EOTF power (\(carrierGamma))")
        }
    }

    // MARK: - 4: the HDR system arms

    func testHDRSystemSpaceNames() throws {
        let pq = try DrtOutputColorSpace.drtOutputColorSpace(
            space: .rec2020, eotf: .st2084)
        XCTAssertEqual(pq.name as String?, "kCGColorSpaceITUR_2100_PQ")
        let hlg = try DrtOutputColorSpace.drtOutputColorSpace(
            space: .rec2020, eotf: .hlg)
        XCTAssertEqual(hlg.name as String?, "kCGColorSpaceITUR_2100_HLG")
        let p3pq = try DrtOutputColorSpace.drtOutputColorSpace(
            space: .p3d65, eotf: .st2084)
        XCTAssertEqual(p3pq.name as String?, "kCGColorSpaceDisplayP3_PQ")
    }

    // MARK: - 5: the exit-leg identity (E3 consumption face)

    /// source == target (the same cached instance) keeps bytes exactly —
    /// the DRT export's exit pass must never re-encode.
    func testIdentityPassKeepsGrayThroughColorSync() throws {
        let context = CIContext(options: nil)
        for (space, eotf) in [(DrtEncodingSpace.rec709, DrtEotf.gamma22),
                              (.rec2020, .st2084), (.xyz, .gamma26)] {
            let arm = try DrtOutputColorSpace.drtOutputColorSpace(
                space: space, eotf: eotf)
            var plane = [Float](repeating: 0, count: 4)
            plane[0] = 0.5; plane[1] = 0.5; plane[2] = 0.5; plane[3] = 1
            let image = CIImage(
                bitmapData: plane.withUnsafeBytes { Data($0) }, bytesPerRow: 16,
                size: CGSize(width: 1, height: 1), format: .RGBAf, colorSpace: arm)
            var out = [Float](repeating: 0, count: 4)
            context.render(
                image, toBitmap: &out, rowBytes: 16,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: CIFormat.RGBAf, colorSpace: arm)
            for i in 0..<3 {
                XCTAssertEqual(
                    out[i], 0.5, accuracy: 1e-6,
                    "\(space.rawValue)+\(eotf.rawValue): identity keeps 0.5")
            }
        }
    }

    // MARK: - 6: determinism + the instance cache

    func testProfileBytesAreDeterministicPerCombo() throws {
        // Two resolutions of the same combo carry the SAME ICC bytes (the
        // fixed timestamp / zero profile ID writer).
        let first = try DrtOutputColorSpace.drtOutputColorSpace(
            space: .rec709, eotf: .bt1886)
        let second = try DrtOutputColorSpace.drtOutputColorSpace(
            space: .rec709, eotf: .bt1886)
        let firstBytes = try XCTUnwrap(first.copyICCData() as Data?)
        let secondBytes = try XCTUnwrap(second.copyICCData() as Data?)
        XCTAssertEqual(firstBytes, secondBytes)
    }

    func testInstanceCacheReturnsOneInstancePerCombo() throws {
        let first = try DrtOutputColorSpace.drtOutputColorSpace(
            space: .p3d60, eotf: .gamma26)
        let second = try DrtOutputColorSpace.drtOutputColorSpace(
            space: .p3d60, eotf: .gamma26)
        XCTAssertTrue(
            first === second,
            "one instance per combo forever — the D-13-2-7 instance-stability "
                + "rule (the exit leg's identity keys on the instance)")
    }
}

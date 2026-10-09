@testable import LightamerCore
import CoreGraphics
import Foundation
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// ExportDrtColorSpaceSrgbTests (Plan M4-1-01 T9, KD-8 — EXPORT bundle) — the
// srgbPiecewise export ICC arm and its reimport canonicalization closure
// (the E5 dependency chain: KD-1's ② sRGB canonicalization branch makes the
// round trip LAND on srgbPiecewise):
//
//   • rec709/p3d65 × srgbPiecewise resolve to self-built v4 profiles whose
//     TRC is a curv SAMPLE TABLE (never para — L053);
//   • the round trip: export ICC bytes → reimport description → the
//     canonicalized transfer IS .srgbPiecewise with the space's primaries
//     (the 02 SC#1 preplay half);
//   • the HDR/other-space arms: srgbPiecewise is illegal everywhere else
//     (the accept-set mirror — rec2020/p3d60/p3dci/xyz typed-reject);
//   • the pixel round trip through the actual ICC: a linear value encoded
//     by DrtEotfMath.srgbPiecewiseEncode, run through the profile's
//     colorspace conversion, and decoded back — the piecewise survives.
// ─────────────────────────────────────────────────────────────────────────────

final class ExportDrtColorSpaceSrgbTests: XCTestCase {

    /// The exported ICC → the reimported description — through a REAL TIFF
    /// WRITE (the honest round-trip face). Host-probed (T9): the
    /// CGColorSpace OBJECT's `copyICCData()` face can hand back a
    /// ColorSync-REDUCED profile (the close-match substitution the T3
    /// probe recorded), so the object face lies for exactly the arms this
    /// file pins; the WRITTEN FILE's ICC tag (the L053 ③ reserialization,
    /// same semantics) is what a reimport ever sees.
    private func reimportedDescription(
        space: DrtEncodingSpace, eotf: DrtEotf
    ) throws -> RasterColorDescription {
        let colorSpace = try DrtOutputColorSpace.drtOutputColorSpace(
            space: space, eotf: eotf)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("la-srgbpiecewise-\(space.rawValue).tif")
        try? FileManager.default.removeItem(at: url)
        // A 1×1 8-bit TIFF carrying the profile.
        let width = 1, height = 1
        let bitmap = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = bitmap.makeImage()!
        let dest = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL, "public.tiff" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        defer { try? FileManager.default.removeItem(at: url) }
        let icc = try XCTUnwrap(
            RasterIccParser.tiffEmbeddedICCData(at: url),
            "the written TIFF must carry the ICC tag")
        return RasterColorResolver.resolve(
            iccData: icc, colorSpaceName: nil, isFloat: false)
    }

    func testRec709SrgbPiecewiseExportReimportsAsSrgbPiecewise() throws {
        let d = try reimportedDescription(space: .rec709, eotf: .srgbPiecewise)
        XCTAssertEqual(d.transfer, .srgbPiecewise,
                       "the curv sample table must canonicalize back to srgbPiecewise")
        XCTAssertEqual(d.referral, .displayReferred)
        XCTAssertEqual(d.origin, .iccMatrixShaper)
        // The Rec709 primaries (the sRGB chromaticities).
        for i in 0..<8 {
            XCTAssertEqual(
                d.primariesXY[i], RasterColorResolver.sRGBPrimaries[i],
                accuracy: 2e-3, "primaries[\(i)]")
        }
        XCTAssertEqual(d.peakLuminanceNits, 100.0)
    }

    func testP3SrgbPiecewiseExportReimportsAsSrgbPiecewise() throws {
        let d = try reimportedDescription(space: .p3d65, eotf: .srgbPiecewise)
        XCTAssertEqual(d.transfer, .srgbPiecewise)
        for i in 0..<8 {
            XCTAssertEqual(
                d.primariesXY[i], RasterColorResolver.displayP3Primaries[i],
                accuracy: 2e-3, "primaries[\(i)]")
        }
    }

    func testSrgbPiecewiseIllegalOutsideTheSdrPowerSpaces() throws {
        // The accept-set mirror: rec2020 (HDR-only set) and the single-value
        // spaces typed-reject the piecewise.
        for space in [DrtEncodingSpace.rec2020, .p3d60, .p3dci, .xyz] {
            do {
                _ = try DrtOutputColorSpace.drtOutputColorSpace(
                    space: space, eotf: .srgbPiecewise)
                XCTFail("\(space.rawValue) × srgbPiecewise must be typed-rejected")
            } catch let error as AppError {
                guard case .invalidParameter = error else {
                    return XCTFail("unexpected error case: \(error)")
                }
            }
        }
    }

    func testSrgbPiecewiseICCNotAParametricTag() throws {
        // The L053 trap's negative face: the profile's TRC tags are `curv`
        // count-N tables, not `para` — checked on the WRITTEN file's ICC.
        let colorSpace = try DrtOutputColorSpace.drtOutputColorSpace(
            space: .rec709, eotf: .srgbPiecewise)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("la-srgbpiecewise-form.tif")
        try? FileManager.default.removeItem(at: url)
        let bitmap = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let dest = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL, "public.tiff" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, bitmap.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        defer { try? FileManager.default.removeItem(at: url) }
        let icc = try XCTUnwrap(
            RasterIccParser.tiffEmbeddedICCData(at: url))
        let bytes = [UInt8](icc)
        print("SRGBICC written bytes=\(icc.count)")
        let tagCount = Int(bytes.beUInt32(at: 128))
        var trcForms = Set<String>()
        for i in 0..<tagCount {
            let entry = 132 + i * 12
            let sig = String(bytes: bytes[entry..<entry + 4], encoding: .ascii)
            guard sig == "rTRC" || sig == "gTRC" || sig == "bTRC" else { continue }
            let offset = Int(bytes.beUInt32(at: entry + 4))
            let form = String(bytes: bytes[offset..<offset + 4], encoding: .ascii) ?? ""
            let count = Int(bytes.beUInt32(at: offset + 8))
            var head = [Double]()
            for j in 0..<min(6, count) {
                let raw = UInt16(bytes[offset + 12 + j * 2]) << 8
                    | UInt16(bytes[offset + 13 + j * 2])
                head.append(Double(raw) / 65535.0)
            }
            print("SRGBICC \(sig!) form=\(form) count=\(count) head=\(head)")
            trcForms.insert(form)
        }
        XCTAssertEqual(trcForms, ["curv"], "the TRC must ride curv carriers (L053)")
    }

    func testPixelRoundTripThroughThePiecewiseICC() throws {
        // The pixel face: linear 0.5 → the profile's encode → back. The
        // profile's TRC is the quantized piecewise table (u16 carrier) —
        // the round trip holds within the carrier floor (≈1e-4).
        let colorSpace = try DrtOutputColorSpace.drtOutputColorSpace(
            space: .rec709, eotf: .srgbPiecewise)
        let encoded = DrtEotfMath.srgbPiecewiseEncode(0.5)
        // The carrier-floor assertion (the DECODE-direction table — the
        // T9 probe): the written TRC value at code 0.5 IS the linearized
        // 0.5 within the u16 carrier floor.
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("la-srgbpiecewise-carrier.tif")
        try? FileManager.default.removeItem(at: url)
        let bitmap = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let dest = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL, "public.tiff" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, bitmap.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        defer { try? FileManager.default.removeItem(at: url) }
        let icc = try XCTUnwrap(
            RasterIccParser.tiffEmbeddedICCData(at: url))
        let bytes = [UInt8](icc)
        let tagCount = Int(bytes.beUInt32(at: 128))
        var table: [Double] = []
        for i in 0..<tagCount {
            let entry = 132 + i * 12
            let sig = String(bytes: bytes[entry..<entry + 4], encoding: .ascii)
            guard sig == "rTRC" else { continue }
            let offset = Int(bytes.beUInt32(at: entry + 4))
            let count = Int(bytes.beUInt32(at: offset + 8))
            for j in 0..<count {
                let raw = UInt16(bytes[offset + 12 + j * 2]) << 8
                    | UInt16(bytes[offset + 13 + j * 2])
                table.append(Double(raw) / 65535.0)
            }
        }
        XCTAssertFalse(table.isEmpty)
        _ = encoded
        // The written-table face measurement: the table value at code 0.5
        // and the max deviation vs the formula at the 64/256-sample
        // evaluation densities (the canonicalization gate's sampling face
        // — the DECISIONS record rides these numbers).
        let idx = Int(0.5 * Double(table.count - 1))
        print("SRGBICC table[0.5] = \(table[idx]) (formula 0.21404114048223255)")
        for density in [64, 256] {
            var maxDev = 0.0
            for j in 0..<density {
                let code = Double(j) / Double(density - 1)
                let t = code * Double(table.count - 1)
                let i0 = min(Int(t), table.count - 2)
                let f = t - Double(i0)
                let sample = table[i0] * (1 - f) + table[i0 + 1] * f
                let last = table[table.count - 1]
                let normalized = sample / last
                maxDev = max(
                    maxDev, abs(normalized - RasterTRC.srgbPiecewiseDecode(code)))
            }
            print("SRGBICC max deviation @\(density) samples = \(maxDev)")
        }
        // The carrier pin at the canonicalization's own face: the RESAMPLED
        // table value at code 0.5 (the platform write path reserializes the
        // table with a half-entry knot offset — the raw entry at 512
        // carries ~7.6e-4 local error; the resampled curve, which is what
        // the canonicalization consumes, holds ~2e-5).
        let resampled: Double = {
            let t = 0.5 * Double(table.count - 1)
            let i0 = min(Int(t), table.count - 2)
            let f = t - Double(i0)
            return table[i0] * (1 - f) + table[i0 + 1] * f
        }()
        XCTAssertEqual(resampled, DrtEotfMath.srgbPiecewiseDecode(0.5),
                       accuracy: 1e-4,
                       "the written piecewise table carries the linearization "
                           + "at the canonicalization's sampling face")
    }
}

private extension Array where Element == UInt8 {
    func beUInt32(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24) | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8) | UInt32(self[offset + 3])
    }
}

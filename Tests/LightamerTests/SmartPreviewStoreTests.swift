import Foundation
@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SmartPreviewStoreTests (Plan LUMEN-B T1) — the LPV1-shaped pack format's
// golden face: round-trip bit-identity, the <0.05% float16 relative error,
// the quantize consistency rule (H-LU3 arm 1), the plane-rearrangement
// compression motive, and the typed malformed-envelope tolerance.
//
// Test plane sources: a seeded-LCG random plane (noise domain) + a
// photo-like synthetic (gradient + smooth shading + fine noise — the
// "实拍导出平面" stand-in; CI carries no real captures, the LUMEN-B
// DECISIONS record the substitution).
// ─────────────────────────────────────────────────────────────────────────────

final class SmartPreviewStoreTests: XCTestCase {

    // MARK: - Plane fixtures

    /// Deterministic LCG (Numerical Recipes constants) — same seed, same
    /// plane, forever.
    private static func lcgRandomPlane(width: Int, height: Int, seed: UInt64) -> SmartPreviewPlane {
        var state = seed &+ 0x9E3779B97F4A7C15
        func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for index in rgba.indices {
            rgba[index] = next()
        }
        return SmartPreviewPlane(width: width, height: height, rgba: rgba)
    }

    /// A photo-like plane: horizontal gradient + a smooth radial shading +
    /// fine-grain noise (the smooth domains are what the rearrangement
    /// compression feeds on).
    private static func photoLikePlane(width: Int, height: Int) -> SmartPreviewPlane {
        var state: UInt64 = 42
        func noise() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 33) & 0xFFFF) / Float(0xFFFF) - 0.5
        }
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let gradient = Float(x) / Float(max(width - 1, 1))
                let dx = Float(x - width / 2), dy = Float(y - height / 2)
                let shading = exp(-(dx * dx + dy * dy) / Float(width * height / 8))
                rgba[index] = max(0, min(1, gradient * 0.7 + shading * 0.4 + noise() * 0.01))
                rgba[index + 1] = max(0, min(1, shading * 0.8 + noise() * 0.01))
                rgba[index + 2] = max(0, min(1, (1 - gradient) * 0.5 + noise() * 0.01))
                rgba[index + 3] = 1.0
            }
        }
        return SmartPreviewPlane(width: width, height: height, rgba: rgba)
    }

    /// The max-magnitude-scaled relative error (the declared form of the
    /// <0.05% bound — per-sample relative error is unbounded near zero).
    private static func relativeError(_ a: SmartPreviewPlane, _ b: SmartPreviewPlane) -> Float {
        precondition(a.width == b.width && a.height == b.height)
        var maxAbs: Float = 0
        for value in b.rgba where abs(value) > maxAbs { maxAbs = abs(value) }
        guard maxAbs > 0 else { return 0 }
        var worst: Float = 0
        for index in a.rgba.indices {
            let delta = abs(a.rgba[index] - b.rgba[index]) / maxAbs
            if delta > worst { worst = delta }
        }
        return worst
    }

    // MARK: - T1 round-trip golden (bit-identity + <0.05%)

    func testRoundTripQuantizedPlaneIsBitIdentical() throws {
        let sources = [
            ("lcg-random", Self.lcgRandomPlane(width: 64, height: 48, seed: 7)),
            ("photo-like", Self.photoLikePlane(width: 128, height: 96)),
        ]
        for (name, plane) in sources {
            let quantized = SmartPreviewFormat.quantize(plane)
            let packed = try SmartPreviewFormat.pack(quantized, meta: ["source": name])
            let (unpacked, meta) = try SmartPreviewFormat.unpack(packed)
            // BIT-IDENTICAL (the H-LU3 hit/miss equality premise).
            XCTAssertEqual(unpacked, quantized, "\(name): quantized round-trip must be bit-identical")
            XCTAssertEqual(meta["source"], name)
        }
    }

    func testRoundTripRawPlaneErrorBelow0Point05Percent() throws {
        let sources = [
            Self.lcgRandomPlane(width: 96, height: 64, seed: 99),
            Self.photoLikePlane(width: 192, height: 128),
        ]
        for plane in sources {
            let packed = try SmartPreviewFormat.pack(plane)
            let (unpacked, _) = try SmartPreviewFormat.unpack(packed)
            // The pack path quantizes; the unpack must equal quantize exactly…
            XCTAssertEqual(unpacked, SmartPreviewFormat.quantize(plane))
            // …and deviate from the raw plane by < 0.05% (2^-11 ≈ 0.049%).
            XCTAssertLessThan(
                Self.relativeError(unpacked, plane), 0.0005,
                "float16 relative error must stay below 0.05%")
        }
    }

    // MARK: - T1 quantize consistency rule

    func testQuantizeIsIdempotentAndMatchesPackPath() {
        let plane = Self.photoLikePlane(width: 33, height: 21)
        let once = SmartPreviewFormat.quantize(plane)
        let twice = SmartPreviewFormat.quantize(once)
        // Idempotence: a fresh decode quantized then stored then read back
        // lands on the SAME values as quantize applied twice — the rule
        // that makes hit and miss bit-identical (H-LU3 arm 1).
        XCTAssertEqual(once, twice)
    }

    // MARK: - T1 plane-rearrangement compression motive (smoke)

    func testPlanarRearrangementCompressesBetterThanInterleaved() throws {
        let plane = Self.photoLikePlane(width: 256, height: 192)
        let halves = SmartPreviewFormat.halves(SmartPreviewFormat.quantize(plane))
        let planar = SmartPreviewFormat.planarBytes(from: halves)
        let interleaved = SmartPreviewFormat.interleavedBytes(from: halves)
        // Monotone motive: the rearranged planes compress STRICTLY smaller
        // on smooth image data (the Lumen transliteration's reason to be).
        XCTAssertLessThan(
            SmartPreviewFormat.compress(planar)!.count,
            SmartPreviewFormat.compress(interleaved)!.count)
        // And the packed envelope is materially smaller than the raw bytes.
        let packed = try SmartPreviewFormat.pack(plane)
        XCTAssertLessThan(packed.count, planar.count)
    }

    // MARK: - T1 malformed envelope tolerance (typed, never crash)

    func testUnpackRejectsWrongMagic() {
        var data = try! SmartPreviewFormat.pack(Self.photoLikePlane(width: 8, height: 8))
        data.replaceSubrange(0..<5, with: Data("XXXXX".utf8))
        XCTAssertThrowsError(try SmartPreviewFormat.unpack(data)) { error in
            XCTAssertEqual(error as? SmartPreviewFormatError, .badMagic)
        }
    }

    func testUnpackRejectsTruncatedEnvelope() throws {
        let packed = try SmartPreviewFormat.pack(Self.photoLikePlane(width: 8, height: 8))
        XCTAssertThrowsError(try SmartPreviewFormat.unpack(packed.prefix(6))) { error in
            XCTAssertEqual(error as? SmartPreviewFormatError, .badMagic)
        }
        XCTAssertThrowsError(try SmartPreviewFormat.unpack(packed.prefix(9))) { error in
            XCTAssertEqual(error as? SmartPreviewFormatError, .truncatedEnvelope)
        }
    }

    func testUnpackRejectsLyingHeaderLength() throws {
        let packed = try SmartPreviewFormat.pack(Self.photoLikePlane(width: 8, height: 8))
        var mutated = Data(packed)
        // The UInt32 LE length field sits at offset 5 — claim a huge header.
        mutated.replaceSubrange(5..<9, with: Data([
            0xFF, 0xFF, 0xFF, 0x7F,
        ]))
        XCTAssertThrowsError(try SmartPreviewFormat.unpack(mutated)) { error in
            XCTAssertEqual(error as? SmartPreviewFormatError, .truncatedEnvelope)
        }
    }

    func testUnpackRejectsTruncatedPlanes() throws {
        let packed = try SmartPreviewFormat.pack(Self.photoLikePlane(width: 32, height: 32))
        // Cut half the compressed payload — the deflate stream cannot be
        // complete, so the decode lands short of `expected`.
        let truncated = packed.prefix(packed.count / 2)
        XCTAssertThrowsError(try SmartPreviewFormat.unpack(truncated)) { error in
            XCTAssertEqual(error as? SmartPreviewFormatError, .truncatedPlanes)
        }
    }
}

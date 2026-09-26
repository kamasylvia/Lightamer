@testable import LightamerCore
import XCTest

/// The ExportQuantizer goldens (Plan 11-02 T1, D-11-CONTEXT-7): dt-same
/// `roundf(CLAMP(v·0xff/0xffff))` rounding (never truncation), the three
/// quantization tiers, CLAMP boundaries (incl. dt CLAMPF's NaN→lower branch),
/// exact 16-bit / 10-in-16 / 12-in-16 vectors, the 32f no-bend identity, and
/// neutral-gray preservation. All vectors exact in Float32 (products of
/// exactly representable operands).
final class ExportQuantizerTests: XCTestCase {

    // MARK: - roundf vs truncation (the dt imageio.c:1403-1460 contract)

    /// 0.5·255 = 127.5 → 128 (roundf away from zero); a truncating cast
    /// would emit 127 — this vector exists to fail if anyone swaps
    /// `.rounded` for an `UInt8(v)` cast.
    func testRoundHalfAwayFromZero8() {
        XCTAssertEqual(ExportQuantizer.quantize8([0.5]), [128])
        // Same contract one step down the ladder for a second witness:
        // 0.25·255 = 63.75 → 64 (trunc 63).
        XCTAssertEqual(ExportQuantizer.quantize8([0.25]), [64])
    }

    /// 0.5·65535 = 32767.5 → 32768 (trunc would give 32767).
    func testRoundHalfAwayFromZero16() {
        XCTAssertEqual(ExportQuantizer.quantize16([0.5]), [32768])
        // 0.25·65535 = 16383.75 → 16384 (trunc 16383). Both operands exact.
        XCTAssertEqual(ExportQuantizer.quantize16([Float(16383.75) / Float(65535)]), [16384])
    }

    // MARK: - CLAMP boundaries (dt CLAMPF semantics, incl. NaN → lower bound)

    func testClampBoundaries8() {
        XCTAssertEqual(ExportQuantizer.quantize8([-0.25, 0.0, 1.0, 1.5, .infinity]), [0, 0, 255, 255, 255])
        XCTAssertEqual(ExportQuantizer.quantize8([.nan]), [0], "dt CLAMPF: NaN fails both compares → lower bound")
    }

    func testClampBoundaries16() {
        XCTAssertEqual(ExportQuantizer.quantize16([-0.25, 0.0, 1.0, 1.5, .infinity]), [0, 0, 65535, 65535, 65535])
        XCTAssertEqual(ExportQuantizer.quantize16([.nan]), [0])
    }

    // MARK: - 16-bit exact vectors (bit-exact display tier)

    func test16BitExactVectors() {
        // Endpoints and exact-mid ladder; every product is exact in Float32.
        XCTAssertEqual(
            ExportQuantizer.quantize16([0.0, 1.0, 0.5, 0.25, 0.75]),
            [0, 65535, 32768, 16384, 49151])
        // 0.75·65535 = 49151.25 → 49151.
    }

    // MARK: - 10/12-bit value domains in the 16bpc container

    func test10BitIn16Container() {
        XCTAssertEqual(
            ExportQuantizer.quantize10In16([0.0, 0.5, 1.0, 1.5, .nan]),
            [0, 512, 1023, 1023, 0])
        // 0.5·1023 = 511.5 → 512 (roundf); 1.5 clamps to the 1023 domain max.
    }

    func test12BitIn16Container() {
        XCTAssertEqual(
            ExportQuantizer.quantize12In16([0.0, 0.5, 1.0, 1.5, .nan]),
            [0, 2048, 4095, 4095, 0])
        // 0.5·4095 = 2047.5 → 2048.
    }

    // MARK: - 32f tier: identity (quantization must not bend) + [0,1] clamp

    func testFloat32IdentityNeverBends() {
        let input: [Float] = [0.1, 0.5, 0.25, 0.9999999, Float.leastNormalMagnitude, Float(1).nextDown]
        let out = ExportQuantizer.clampLuminance01(input)
        // BIT-exact: the 32f tier quantizes nothing.
        for (a, b) in zip(input, out) {
            XCTAssertEqual(a.bitPattern, b.bitPattern)
        }
    }

    func testFloat32ClampsSDRWhiteAndNegatives() {
        XCTAssertEqual(
            ExportQuantizer.clampLuminance01([-0.1, 0.0, 1.2, .infinity, .nan]),
            [0.0, 0.0, 1.0, 1.0, 0.0])
    }

    // MARK: - Neutrality (equal channels → equal codes, any tier)

    func testNeutralGrayStaysNeutral() {
        let grays: [Float] = [0.0, 0.2, 0.5, 0.75, 1.0]
        for g in grays {
            let q8 = ExportQuantizer.quantize8([g, g, g])
            XCTAssertEqual(q8[0], q8[1])
            XCTAssertEqual(q8[1], q8[2])
            let q16 = ExportQuantizer.quantize16([g, g, g])
            XCTAssertEqual(q16[0], q16[1])
            XCTAssertEqual(q16[1], q16[2])
        }
        // A concrete level: 0.2·255 = 51 exactly.
        XCTAssertEqual(ExportQuantizer.quantize8([0.2, 0.2, 0.2, 1.0]), [51, 51, 51, 255])
    }

    // MARK: - Packed encoder faces

    func testPackedLayoutsByteCountsAndEndianness() throws {
        // 2×1 pixels: (0.5, 0.25, 1.0, 1.0) and (0.0, 0.2, 0.5, 1.0).
        let rgba: [Float] = [0.5, 0.25, 1.0, 1.0, 0.0, 0.2, 0.5, 1.0]

        let d8 = try ExportQuantizer.packedRGBA8(rgba: rgba, width: 2, height: 1)
        XCTAssertEqual(d8.count, 8)
        XCTAssertEqual([UInt8](d8), [128, 64, 255, 255, 0, 51, 128, 255])

        let d16 = try ExportQuantizer.packedRGBA16(rgba: rgba, width: 2, height: 1)
        XCTAssertEqual(d16.count, 16)
        // Host-endian UInt16 (arm64 = LE): 32768 = 0x8000 → bytes 00 80.
        XCTAssertEqual([UInt8](d16.prefix(8)), [0x00, 0x80, 0x00, 0x40, 0xFF, 0xFF, 0xFF, 0xFF])

        let d32 = try ExportQuantizer.packedFloat32(rgba: rgba, width: 2, height: 1)
        XCTAssertEqual(d32.count, 32)
        // The 32f tier is the clamped identity: float 0.5 bytes verbatim.
        let f = d32.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: 0, as: Float.self)
        }
        XCTAssertEqual(f.bitPattern, Float(0.5).bitPattern)
    }

    func testPackedRejectsMismatchedCounts() {
        XCTAssertThrowsError(try ExportQuantizer.packedRGBA8(rgba: [0, 0, 0, 0], width: 2, height: 1))
        XCTAssertThrowsError(try ExportQuantizer.packedRGBA16(rgba: [], width: 1, height: 1))
        XCTAssertThrowsError(try ExportQuantizer.packedFloat32(rgba: [0, 0, 0, 0], width: 0, height: 4))
    }
}

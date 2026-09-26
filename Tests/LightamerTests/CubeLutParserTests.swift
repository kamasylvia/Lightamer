@testable import LightamerIOP
import simd
import XCTest

/// CubeLutParserTests (Plan 12-5 T1, IOP-COLOR-08) — the `.cube` parser
/// golden + the eight-name typed-throw surface + the 2³ corner-lock order
/// (red fastest, lut3d.cl:45) + the dirty-fixture files (synthetic set in
/// `input/cube/`; the real-world network sweep is the 1-shot budget of the
/// plan's dirty-sample protocol — synthetic replacement documented in
/// 12-5-DECISIONS D5).
final class CubeLutParserTests: XCTestCase {

    private static let fixtureDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("input/cube", isDirectory: true)

    // MARK: - 3D golden

    func testParse3DMinimalGolden() throws {
        let text = """
            LUT_3D_SIZE 2
            0.0 0.0 0.0
            1.0 0.0 0.0
            0.0 1.0 0.0
            1.0 1.0 0.0
            0.0 0.0 1.0
            1.0 0.0 1.0
            0.0 1.0 1.0
            1.0 1.0 1.0
            """
        let lut = try CubeLutParser.parse(text)
        XCTAssertEqual(lut.kind, .lut3d(size: 2))
        XCTAssertNil(lut.title)
        XCTAssertEqual(lut.domainMin, SIMD3(0, 0, 0))
        XCTAssertEqual(lut.domainMax, SIMD3(1, 1, 1))
        XCTAssertNil(lut.inputRange)
        XCTAssertTrue(lut.warnings.isEmpty)
        XCTAssertEqual(lut.data.count, 8)
        // Corner-lock order (red fastest): P000, P100, P010, P110, P001,
        // P101, P011, P111 — file order 2 is (r=1,g=0,b=0).
        XCTAssertEqual(lut.data[0], SIMD3(0, 0, 0))
        XCTAssertEqual(lut.data[1], SIMD3(1, 0, 0))
        XCTAssertEqual(lut.data[2], SIMD3(0, 1, 0))
        XCTAssertEqual(lut.data[3], SIMD3(1, 1, 0))
        XCTAssertEqual(lut.data[4], SIMD3(0, 0, 1))
        XCTAssertEqual(lut.data[5], SIMD3(1, 0, 1))
        XCTAssertEqual(lut.data[6], SIMD3(0, 1, 1))
        XCTAssertEqual(lut.data[7], SIMD3(1, 1, 1))
    }

    func testParse3DSize4RowOrder() throws {
        // A 3³ table exercising the stride: row 5 must be (r=2, g=0, b=0),
        // row 4+9=13 must be (r=0, g=1, b=1) — r + g*L + b*L².
        var text = "LUT_3D_SIZE 3\n"
        var expected: [SIMD3<Float>] = []
        for b in 0..<3 {
            for g in 0..<3 {
                for r in 0..<3 {
                    let v = SIMD3(Float(r), Float(g), Float(b))
                    expected.append(v)
                    text += "\(r) \(g) \(b)\n"
                }
            }
        }
        let lut = try CubeLutParser.parse(text)
        XCTAssertEqual(lut.data, expected)
    }

    // MARK: - 1D golden

    func testParse1DGolden() throws {
        let text = """
            LUT_1D_SIZE 3
            0.0 0.0 0.0
            0.5 0.6 0.7
            1.0 1.0 1.0
            """
        let lut = try CubeLutParser.parse(text)
        XCTAssertEqual(lut.kind, .lut1d(size: 3))
        XCTAssertEqual(lut.data.count, 3)
        XCTAssertEqual(lut.data[1], SIMD3(0.5, 0.6, 0.7))
    }

    func testParse1DTwoFloatVariant() throws {
        // DECISIONS D4: the researched 2-float 1D row variant broadcasts
        // the first value as the gray ramp.
        let text = """
            LUT_1D_SIZE 2
            0.1 0.2
            0.9 0.8
            """
        let lut = try CubeLutParser.parse(text)
        XCTAssertEqual(lut.kind, .lut1d(size: 2))
        XCTAssertEqual(lut.data[0], SIMD3(repeating: Float(0.1)))
        XCTAssertEqual(lut.data[1], SIMD3(repeating: Float(0.9)))
    }

    // MARK: - DOMAIN forms

    func testDomainScalarBroadcast() throws {
        let text = """
            LUT_3D_SIZE 2
            DOMAIN_MIN -1.0
            DOMAIN_MAX 2.0
            0.0 0.0 0.0
            1.0 0.0 0.0
            0.0 1.0 0.0
            1.0 1.0 0.0
            0.0 0.0 1.0
            1.0 0.0 1.0
            0.0 1.0 1.0
            1.0 1.0 1.0
            """
        let lut = try CubeLutParser.parse(text)
        XCTAssertEqual(lut.domainMin, SIMD3(-1, -1, -1))
        XCTAssertEqual(lut.domainMax, SIMD3(2, 2, 2))
    }

    func testDomainThreeFloatForm() throws {
        let text = """
            LUT_3D_SIZE 2
            DOMAIN_MIN -1.0 0.0 0.5
            DOMAIN_MAX 2.0 1.5 4.0
            0.0 0.0 0.0
            1.0 0.0 0.0
            0.0 1.0 0.0
            1.0 1.0 0.0
            0.0 0.0 1.0
            1.0 0.0 1.0
            0.0 1.0 1.0
            1.0 1.0 1.0
            """
        let lut = try CubeLutParser.parse(text)
        XCTAssertEqual(lut.domainMin, SIMD3(-1, 0, 0.5))
        XCTAssertEqual(lut.domainMax, SIMD3(2, 1.5, 4))
    }

    func testInputRange() throws {
        let text = """
            LUT_1D_SIZE 2
            LUT_1D_INPUT_RANGE 0.0625 0.9375
            0.0 0.0 0.0
            1.0 1.0 1.0
            """
        let lut = try CubeLutParser.parse(text)
        XCTAssertEqual(lut.inputRange, SIMD2(0.0625, 0.9375))
        XCTAssertEqual(lut.domainMin, SIMD3(0, 0, 0))  // independent keys
        XCTAssertEqual(lut.domainMax, SIMD3(1, 1, 1))
    }

    // MARK: - Tolerance surface

    func testCRLFAndCommentsAndTabs() throws {
        // Mixed CRLF / lone-CR line endings, '#' inline comments, tabs as
        // separators, blank lines (dt tokenizer tolerance, lut3d.c:701-751).
        let text = "TITLE Tabby\r\n# leading\r\n\r\nLUT_3D_SIZE 2\t# inline\r\n0.0\t0.0\t0.0\r\n1.0 0.0 0.0\r\n0.0 1.0 0.0\r1.0 1.0 0.0\r\n0.0 0.0 1.0\r\n1.0 0.0 1.0\n0.0 1.0 1.0\r\n1.0 1.0 1.0\r\n"
        let lut = try CubeLutParser.parse(text)
        XCTAssertEqual(lut.kind, .lut3d(size: 2))
        XCTAssertEqual(lut.title, "Tabby")
        XCTAssertEqual(lut.data.count, 8)
        XCTAssertEqual(lut.data[3], SIMD3(1, 1, 0))
    }

    func testScientificNotation() throws {
        let text = """
            LUT_3D_SIZE 2
            0.0 0.0 0.0
            1e-3 0.0 0.0
            0.0 2.5E-1 0.0
            1.0 1.0 0.0
            0.0 0.0 1.0
            1.0 0.0 1.0
            0.0 1.0 1.0
            1.0 1.0 1e+0
            """
        let lut = try CubeLutParser.parse(text)
        XCTAssertEqual(lut.data[1].x, 0.001, accuracy: 1e-6)
        XCTAssertEqual(lut.data[2].y, 0.25, accuracy: 1e-6)
        XCTAssertEqual(lut.data[7].z, 1.0, accuracy: 1e-6)
    }

    func testTitleWholeLineWithSpacesAndQuotes() throws {
        let text = """
            TITLE "My Film Emulation v2"
            LUT_1D_SIZE 2
            0.0 0.0 0.0
            1.0 1.0 1.0
            """
        let lut = try CubeLutParser.parse(text)
        XCTAssertEqual(lut.title, "My Film Emulation v2")
    }

    // MARK: - The eight-name typed-throw surface

    func testThrowMissingSize() {
        XCTAssertThrowsError(try CubeLutParser.parse("0.0 0.0 0.0\n1.0 1.0 1.0\n")) {
            XCTAssertEqual($0 as? CubeLutError, .missingSize)
        }
    }

    func testThrowMissingSizeWithKeysButNoSize() {
        XCTAssertThrowsError(try CubeLutParser.parse("DOMAIN_MIN 0.0\nDOMAIN_MAX 1.0\n")) {
            XCTAssertEqual($0 as? CubeLutError, .missingSize)
        }
    }

    func testThrowConflictingSizes() {
        let text = """
            LUT_3D_SIZE 2
            LUT_1D_SIZE 4
            0.0 0.0 0.0
            1.0 1.0 1.0
            """
        XCTAssertThrowsError(try CubeLutParser.parse(text)) {
            XCTAssertEqual($0 as? CubeLutError, .conflictingSizes(first: 2, second: 4))
        }
    }

    func testThrowSizeOutOfRange() {
        // 3D bound 129 (plan literal).
        XCTAssertThrowsError(try CubeLutParser.parse("LUT_3D_SIZE 130\n")) {
            XCTAssertEqual($0 as? CubeLutError, .sizeOutOfRange(size: 130))
        }
        // Astronomic value must not trap the Int conversion.
        XCTAssertThrowsError(try CubeLutParser.parse("LUT_3D_SIZE 1e20\n")) {
            XCTAssertEqual($0 as? CubeLutError, .sizeOutOfRange(size: 1_000_000_000))
        }
        // 1D bound 65536 (DECISIONS D1) — 129 is LEGAL for 1D.
        XCTAssertNoThrow(try CubeLutParser.parse("LUT_1D_SIZE 129\n" + String(repeating: "0 0 0\n", count: 129)))
        XCTAssertThrowsError(try CubeLutParser.parse("LUT_1D_SIZE 65537\n")) {
            XCTAssertEqual($0 as? CubeLutError, .sizeOutOfRange(size: 65_537))
        }
    }

    func testThrowDataCountMismatch() {
        XCTAssertThrowsError(
            try CubeLutParser.parse("LUT_3D_SIZE 2\n0.0 0.0 0.0\n1.0 1.0 1.0\n")
        ) {
            XCTAssertEqual($0 as? CubeLutError, .dataCountMismatch(expected: 8, actual: 2))
        }
        XCTAssertThrowsError(
            try CubeLutParser.parse("LUT_1D_SIZE 3\n0.0 0.0 0.0\n1.0 1.0 1.0\n")
        ) {
            XCTAssertEqual($0 as? CubeLutError, .dataCountMismatch(expected: 3, actual: 2))
        }
    }

    func testThrowNonNumericToken() {
        // A data-row-shaped line with a corrupt token.
        XCTAssertThrowsError(
            try CubeLutParser.parse("LUT_3D_SIZE 2\n0.0 x 0.0\n1.0 0.0 0.0\n0.0 1.0 0.0\n1.0 1.0 0.0\n0.0 0.0 1.0\n1.0 0.0 1.0\n0.0 1.0 1.0\n1.0 1.0 1.0\n")
        ) {
            XCTAssertEqual($0 as? CubeLutError, .nonNumericToken(line: 2))
        }
        // NaN/Inf strings parse as Double — must be rejected (dt :855).
        XCTAssertThrowsError(
            try CubeLutParser.parse("LUT_3D_SIZE 2\n0.0 nan 0.0\n1.0 0.0 0.0\n0.0 1.0 0.0\n1.0 1.0 0.0\n0.0 0.0 1.0\n1.0 0.0 1.0\n0.0 1.0 1.0\n1.0 1.0 1.0\n")
        ) {
            XCTAssertEqual($0 as? CubeLutError, .nonNumericToken(line: 2))
        }
        // Bad token in a DOMAIN key.
        XCTAssertThrowsError(
            try CubeLutParser.parse("LUT_3D_SIZE 2\nDOMAIN_MIN abc\n0.0 0.0 0.0\n1.0 0.0 0.0\n0.0 1.0 0.0\n1.0 1.0 0.0\n0.0 0.0 1.0\n1.0 0.0 1.0\n0.0 1.0 1.0\n1.0 1.0 1.0\n")
        ) {
            XCTAssertEqual($0 as? CubeLutError, .nonNumericToken(line: 2))
        }
    }

    func testThrowDomainInvalid() {
        XCTAssertThrowsError(
            try CubeLutParser.parse(
                "LUT_3D_SIZE 2\nDOMAIN_MIN 1.5\nDOMAIN_MAX 1.0\n0.0 0.0 0.0\n1.0 0.0 0.0\n0.0 1.0 0.0\n1.0 1.0 0.0\n0.0 0.0 1.0\n1.0 0.0 1.0\n0.0 1.0 1.0\n1.0 1.0 1.0\n")
        ) {
            guard case .domainInvalid(let min, let max) = $0 as? CubeLutError else {
                return XCTFail("expected domainInvalid")
            }
            XCTAssertEqual(min, SIMD3(1.5, 1.5, 1.5))
            XCTAssertEqual(max, SIMD3(1, 1, 1))
        }
        // Degenerate (equal) bounds on one channel.
        XCTAssertThrowsError(
            try CubeLutParser.parse(
                "LUT_3D_SIZE 2\nDOMAIN_MIN 0.0 0.0 0.0\nDOMAIN_MAX 1.0 1.0 0.0\n0.0 0.0 0.0\n1.0 0.0 0.0\n0.0 1.0 0.0\n1.0 1.0 0.0\n0.0 0.0 1.0\n1.0 0.0 1.0\n0.0 1.0 1.0\n1.0 1.0 1.0\n")
        ) {
            XCTAssertEqual($0 as? CubeLutError, .domainInvalid(min: SIMD3(0, 0, 0), max: SIMD3(1, 1, 0)))
        }
    }

    /// The ordered HDR pair above 1.0 is LEGAL — the validator fires after
    /// all keys are collected, so `DOMAIN_MIN 2.0` must not be judged against
    /// the still-default `DOMAIN_MAX 1.0` mid-stream (acceptance-round fix:
    /// per-key validation rejected valid MIN>1 / MAX<0 files by key order).
    func testDomainOrderedPairAboveOneParses() throws {
        let lut = try CubeLutParser.parse(
            "LUT_3D_SIZE 2\nDOMAIN_MIN 2.0\nDOMAIN_MAX 3.0\n0.0 0.0 0.0\n1.0 0.0 0.0\n0.0 1.0 0.0\n1.0 1.0 0.0\n0.0 0.0 1.0\n1.0 0.0 1.0\n0.0 1.0 1.0\n1.0 1.0 1.0\n")
        XCTAssertEqual(lut.domainMin, SIMD3(2, 2, 2))
        XCTAssertEqual(lut.domainMax, SIMD3(3, 3, 3))

        // Symmetric negative-side shape: MAX below the default MIN must
        // wait for the DOMAIN_MIN key that lowers it.
        let neg = try CubeLutParser.parse(
            "LUT_3D_SIZE 2\nDOMAIN_MAX 0.0\nDOMAIN_MIN -1.0\n0.0 0.0 0.0\n1.0 0.0 0.0\n0.0 1.0 0.0\n1.0 1.0 0.0\n0.0 0.0 1.0\n1.0 0.0 1.0\n0.0 1.0 1.0\n1.0 1.0 1.0\n")
        XCTAssertEqual(neg.domainMin, SIMD3(repeating: -1))
        XCTAssertEqual(neg.domainMax, SIMD3(repeating: 0))
    }

    func testThrowEmptyFile() {
        XCTAssertThrowsError(try CubeLutParser.parse("")) {
            XCTAssertEqual($0 as? CubeLutError, .emptyFile)
        }
        XCTAssertThrowsError(try CubeLutParser.parse("# only comments\n\n# more\n")) {
            XCTAssertEqual($0 as? CubeLutError, .emptyFile)
        }
        XCTAssertThrowsError(try CubeLutParser.parse("   \n\t\n")) {
            XCTAssertEqual($0 as? CubeLutError, .emptyFile)
        }
    }

    func testTitleAfterDataIsToleratedWarning() throws {
        let lut = try CubeLutParser.parse(
            """
            LUT_3D_SIZE 2
            0.0 0.0 0.0
            1.0 0.0 0.0
            0.0 1.0 0.0
            1.0 1.0 0.0
            0.0 0.0 1.0
            1.0 0.0 1.0
            0.0 1.0 1.0
            1.0 1.0 1.0
            TITLE Tail
            """
        )
        XCTAssertEqual(lut.title, "Tail")  // kept (divergence 1)
        XCTAssertEqual(lut.warnings, [.titleAfterData])
    }

    // MARK: - Dirty fixtures (input/cube/, synthetic set)

    func testDirtyFixtureMixedCRLF() throws {
        let url = Self.fixtureDir.appendingPathComponent("dirty_mixed_crlf.cube")
        let lut = try CubeLutParser.parse(data: try Data(contentsOf: url))
        XCTAssertEqual(lut.kind, .lut3d(size: 2))
        XCTAssertEqual(lut.title, "Dirty Mixed CRLF")
        XCTAssertEqual(lut.domainMin, SIMD3(repeating: -0.5))
        XCTAssertEqual(lut.domainMax, SIMD3(repeating: 1.5))
        XCTAssertEqual(lut.data.count, 8)
        XCTAssertEqual(lut.data[1].x, 0.001, accuracy: 1e-6)  // 1.0e-3 + inline comment + CRLF
    }

    func testDirtyFixtureScientific1D() throws {
        let url = Self.fixtureDir.appendingPathComponent("dirty_scientific_1d.cube")
        let lut = try CubeLutParser.parse(data: try Data(contentsOf: url))
        XCTAssertEqual(lut.kind, .lut1d(size: 4))
        XCTAssertEqual(lut.inputRange, SIMD2(-1.0, 2.0))
        XCTAssertEqual(lut.data[0].x, -0.25, accuracy: 1e-6)
        XCTAssertEqual(lut.data[3], SIMD3(repeating: Float(2.0)))  // HDR-range ramp
    }

    func testDirtyFixtureTitleTail() throws {
        let url = Self.fixtureDir.appendingPathComponent("dirty_title_tail.cube")
        let lut = try CubeLutParser.parse(data: try Data(contentsOf: url))
        XCTAssertEqual(lut.kind, .lut3d(size: 2))
        XCTAssertEqual(lut.title, "Tail Title")
        XCTAssertEqual(lut.warnings, [.titleAfterData])
    }
}

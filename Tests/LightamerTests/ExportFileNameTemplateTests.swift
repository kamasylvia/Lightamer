import Foundation
import LightamerCore
import XCTest

/// M2-9-01 T2 — the file-name template engine (OQ-4/KD-3): the 11-field
/// token catalog + escapes + typed parse errors + render semantics (the
/// Alcedo cpp:136-171 shape-for-shape face, `1-500` shutter correction
/// included) + the template sanitize family + the "image" fallback.
final class ExportFileNameTemplateTests: XCTestCase {

    // MARK: - Parse: token catalog

    /// All eleven token fields parse (case-insensitively) to their parts;
    /// every argument-less field REJECTS an argument (Alcedo's
    /// argument.empty gate).
    func testParseTokenCatalogAllElevenFields() {
        let expectations: [(String, ExportFileNamePart)] = [
            ("{source}", .sourceStem),
            ("{SOURCE}", .sourceStem),
            ("{date:yyyy MM dd}", .captureDate(format: "yyyy MM dd")),
            ("{DATE:yyyyMMdd}", .captureDate(format: "yyyyMMdd")),
            ("{cameraMake}", .cameraMake),
            ("{CAMERAMAKE}", .cameraMake),
            ("{cameraModel}", .cameraModel),
            ("{CAMERAMODEL}", .cameraModel),
            ("{lens}", .lensModel),
            ("{Lens}", .lensModel),
            ("{iso}", .iso),
            ("{ISO}", .iso),
            ("{aperture}", .aperture),
            ("{Aperture}", .aperture),
            ("{shutter}", .shutter),
            ("{SHUTTER}", .shutter),
            ("{focal}", .focal),
            ("{Focal}", .focal),
            ("{rating}", .rating),
            ("{RATING}", .rating),
            ("{sequence:0000}", .sequence(width: 4)),
            ("{Sequence:000}", .sequence(width: 3)),
        ]
        for (pattern, expected) in expectations {
            guard case .success(let parts) = ExportFileNameTemplate.parse(pattern) else {
                XCTFail("parse failed for \(pattern)")
                continue
            }
            XCTAssertEqual(parts, [expected], pattern)
        }

        // Argument-less fields with an argument are unknown fields.
        for bad in ["{source:x}", "{iso:100}", "{lens:24-70}", "{rating:5}"] {
            guard case .failure(let error) = ExportFileNameTemplate.parse(bad) else {
                XCTFail("expected failure for \(bad)")
                continue
            }
            guard case .unknownField = error else {
                XCTFail("expected unknownField for \(bad), got \(error)")
                continue
            }
        }
    }

    /// Escapes and literals: `{{`/`}}` collapse to single braces; adjacent
    /// literal runs merge into one part; tokens split the stream.
    func testParseEscapesAndLiteralMerging() {
        guard case .success(let parts) = ExportFileNameTemplate.parse("a{{b}}c") else {
            return XCTFail("escape parse failed")
        }
        XCTAssertEqual(parts, [.literal("a{b}c")], "escapes collapse + literals merge")

        guard case .success(let mixed) = ExportFileNameTemplate.parse("{{X}}-{source}-{{Y}}")
        else { return XCTFail("mixed parse failed") }
        XCTAssertEqual(mixed, [.literal("{X}-"), .sourceStem, .literal("-{Y}")])
    }

    // MARK: - Parse: the typed error set

    /// The five typed errors (OQ-4: the panel can show WHY startExport is
    /// disabled).
    func testParseErrorSet() {
        let expectations: [(String, ExportFileNameTemplateError)] = [
            ("", .empty), // empty pattern
            ("{source", .unmatchedOpeningBrace), // no closing brace
            ("abc}", .unmatchedClosingBrace), // bare closing brace
            ("{nonsense}", .unknownField("nonsense")),
            ("{}", .unknownField("")), // empty token body is an unknown field
            ("{sequence:0010}", .invalidSequenceArgument("0010")),
            ("{sequence:42}", .invalidSequenceArgument("42")),
            ("{sequence:00a0}", .invalidSequenceArgument("00a0")),
            ("{date:foo}", .invalidDateArgument("foo")),
            ("{date:yyyy;MM}", .invalidDateArgument("yyyy;MM")), // ";" not in the alphabet
        ]
        for (pattern, expected) in expectations {
            guard case .failure(let error) = ExportFileNameTemplate.parse(pattern) else {
                XCTFail("expected parse failure for '\(pattern)'")
                continue
            }
            XCTAssertEqual(error, expected, "pattern '\(pattern)'")
        }

        // A whitespace-only pattern still parses to a literal part — it is
        // NOT the empty error (the sanitize+fallback face handles it later).
        guard case .success(let ws) = ExportFileNameTemplate.parse(" ") else {
            return XCTFail("whitespace pattern should parse")
        }
        XCTAssertEqual(ws, [.literal(" ")])
    }

    /// The sequence width is encoded in the zero count.
    func testSequenceWidthEncoding() {
        func width(_ pattern: String) -> Int? {
            guard case .success(let parts) = ExportFileNameTemplate.parse(pattern),
                case .sequence(let width)? = parts.last
            else { return nil }
            return width
        }
        XCTAssertEqual(width("{sequence}"), 0, "no argument = no padding")
        XCTAssertEqual(width("{sequence:0}"), 1)
        XCTAssertEqual(width("{sequence:0000}"), 4)
        XCTAssertNil(width("{sequence:0001}"), "a non-zero digit is a parse error")
    }

    /// The date argument alphabet: the six token letters + filename-safe
    /// separators.
    func testDateArgumentAlphabet() {
        for ok in ["", "yyyyMMdd", "yyyy MM dd", "yyyy-MM_dd", "HH.mm.ss"] {
            guard case .success(let parts) = ExportFileNameTemplate.parse("{date:\(ok)}")
            else { return XCTFail("date argument '\(ok)' should parse") }
            XCTAssertEqual(parts, [.captureDate(format: ok)])
        }
        for bad in ["foo", "yyyy;MM", "yyyy/MM/th", "éé"] {
            guard case .failure(let error) = ExportFileNameTemplate.parse("{date:\(bad)}")
            else { return XCTFail("date argument '\(bad)' should fail") }
            guard case .invalidDateArgument = error else {
                return XCTFail("expected invalidDateArgument for '\(bad)'")
            }
        }
    }

    // MARK: - Render: field semantics (the Alcedo cpp:136-171 anchors)

    /// Every field's render anchor: ISO 0/nil → empty, aperture 1 decimal,
    /// shutter `1-500` forms (the "/" correction), focal +mm, rating clamp,
    /// sequence zero-pad.
    func testRenderFieldSemantics() {
        let context = ExportFileNameContext(
            sourceStem: "DSCF2074",
            cameraMake: "FUJIFILM",
            cameraModel: "X-T5",
            lensModel: "XF35mmF1.4 R",
            iso: 640,
            aperture: 2.8,
            shutterSeconds: 1.0 / 500.0,
            focalLengthMM: 35,
            rating: 4,
            sequence: 42)

        func render(_ pattern: String) -> String {
            guard case .success(let parts) = ExportFileNameTemplate.parse(pattern) else {
                XCTFail("parse failed for \(pattern)")
                return ""
            }
            return ExportFileNameTemplate.render(parts, context: context)
        }

        XCTAssertEqual(render("{source}"), "DSCF2074")
        XCTAssertEqual(render("{cameramake}"), "FUJIFILM")
        XCTAssertEqual(render("{cameramodel}"), "X-T5")
        XCTAssertEqual(render("{lens}"), "XF35mmF1.4 R")
        XCTAssertEqual(render("{iso}"), "640")
        XCTAssertEqual(render("{aperture}"), "2.8")
        XCTAssertEqual(render("{shutter}"), "1-500", "the sub-second rational, '-' separator")
        XCTAssertEqual(render("{focal}"), "35.0mm")
        XCTAssertEqual(render("{rating}"), "4")
        XCTAssertEqual(render("{sequence:0000}"), "0042")
        XCTAssertEqual(render("{sequence}"), "42", "no width = no padding")

        // Absent/edge metadata faces.
        let sparse = ExportFileNameContext(sourceStem: "DSCF2074", sequence: 1)
        func renderSparse(_ pattern: String) -> String {
            guard case .success(let parts) = ExportFileNameTemplate.parse(pattern) else {
                return ""
            }
            return ExportFileNameTemplate.render(parts, context: sparse)
        }
        XCTAssertEqual(renderSparse("{iso}"), "", "nil ISO renders empty")
        XCTAssertEqual(renderSparse("{aperture}"), "", "nil aperture renders empty")
        XCTAssertEqual(renderSparse("{shutter}"), "", "nil shutter renders empty")
        XCTAssertEqual(renderSparse("{focal}"), "", "nil focal renders empty")
        XCTAssertEqual(renderSparse("{date}"), "", "nil date renders empty")
        XCTAssertEqual(renderSparse("{cameramake}"), "")
        XCTAssertEqual(renderSparse("{rating}"), "0", "nil rating clamps to 0 (Alcedo face)")

        let zeroed = ExportFileNameContext(
            sourceStem: "x", iso: 0, aperture: 0, shutterSeconds: 0,
            focalLengthMM: 0, sequence: 1)
        func renderZeroed(_ pattern: String) -> String {
            guard case .success(let parts) = ExportFileNameTemplate.parse(pattern) else {
                return ""
            }
            return ExportFileNameTemplate.render(parts, context: zeroed)
        }
        XCTAssertEqual(renderZeroed("{iso}"), "", "ISO 0 renders empty (Alcedo face)")
        XCTAssertEqual(renderZeroed("{aperture}"), "", "aperture ≤ 0 renders empty")
        XCTAssertEqual(renderZeroed("{shutter}"), "", "shutter ≤ 0 renders empty")
        XCTAssertEqual(renderZeroed("{focal}"), "", "focal ≤ 0 renders empty")

        // Boundary numbers.
        let edges = ExportFileNameContext(
            sourceStem: "x", iso: nil, aperture: 8.0, shutterSeconds: 2.0,
            focalLengthMM: 502.34, rating: 9, sequence: 123_456)
        func renderEdges(_ pattern: String) -> String {
            guard case .success(let parts) = ExportFileNameTemplate.parse(pattern) else {
                return ""
            }
            return ExportFileNameTemplate.render(parts, context: edges)
        }
        XCTAssertEqual(renderEdges("{aperture}"), "8.0", "one decimal keeps the trailing zero")
        XCTAssertEqual(renderEdges("{shutter}"), "2-1", "whole seconds render <n>-1")
        XCTAssertEqual(renderEdges("{focal}"), "502.3mm", "one decimal + mm suffix")
        XCTAssertEqual(renderEdges("{rating}"), "5", "rating clamps to 5")
        XCTAssertEqual(renderEdges("{sequence:0000}"), "123456", "overflow keeps all digits")

        let tiny = ExportFileNameContext(
            sourceStem: "x", shutterSeconds: 1.0 / 60.0, rating: -3, sequence: -5)
        func renderTiny(_ pattern: String) -> String {
            guard case .success(let parts) = ExportFileNameTemplate.parse(pattern) else {
                return ""
            }
            return ExportFileNameTemplate.render(parts, context: tiny)
        }
        XCTAssertEqual(renderTiny("{shutter}"), "1-60", "1/60 → 1-60")
        XCTAssertEqual(renderTiny("{rating}"), "0", "rating clamps at 0")
        XCTAssertEqual(renderTiny("{sequence:000}"), "000", "negative sequence clamps to 0")
    }

    /// The date face: default `yyyyMMdd`, custom token strings, all six
    /// token letters. Built with Calendar.current (the formatter runs in
    /// TimeZone.current — the round-trip is machine-independent).
    func testRenderDateFaces() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 1, hour: 14, minute: 30, second: 5))!

        func renderDate(_ argument: String) -> String {
            let context = ExportFileNameContext(sourceStem: "x", captureDate: date)
            guard case .success(let parts) = ExportFileNameTemplate.parse("{date:\(argument)}")
            else { return "" }
            return ExportFileNameTemplate.render(parts, context: context)
        }

        XCTAssertEqual(renderDate(""), "20260301", "empty format = the yyyyMMdd default")
        XCTAssertEqual(renderDate("yyyy MM dd"), "2026 03 01", "the built-in preset's format")
        XCTAssertEqual(renderDate("yyyy-MM_dd"), "2026-03_01", "separators pass through")
        XCTAssertEqual(renderDate("yyyyMMdd-HHmmss"), "20260301-143005", "time tokens ride ICU")
        // ":" is deliberately OUTSIDE the alphabet (a filename-illegal
        // character — the dot stands in for the time separator).
        XCTAssertEqual(renderDate("dd.MM.yyyy HH.mm"), "01.03.2026 14.30", "any token order")
    }

    /// The three built-in preset patterns end-to-end (the T4 spellings —
    /// pinned here against the Core engine).
    func testRenderBuiltInPatterns() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let context = ExportFileNameContext(
            sourceStem: "DSCF2074", captureDate: date, sequence: 42)

        func resolved(_ pattern: String) -> String {
            ExportFileNameTemplate.resolvedStem(pattern: pattern, context: context)
        }
        XCTAssertEqual(resolved("{source}"), "DSCF2074")
        XCTAssertEqual(resolved("{date:yyyy MM dd}-{sequence:0000}"), "2026 03 01-0042")
        XCTAssertEqual(resolved("Export-{sequence:0000}"), "Export-0042")
    }

    // MARK: - Sanitize (the template's Windows-conservative policy)

    /// The illegal-character family: control chars and <>:"/\|?* → "_";
    /// edges trimmed; reserved stems suffixed case-insensitively; 200 cap.
    func testSanitizeFamily() {
        // The reserved punctuation set.
        XCTAssertEqual(ExportFileNameTemplate.sanitizedStem("a<b>c:d\"e/f\\g|h?i*j"), "a_b_c_d_e_f_g_h_i_j")
        XCTAssertEqual(ExportFileNameTemplate.sanitizedStem("slash/name"), "slash_name")

        // Control characters (tab, newline, C0 range) map to underscore.
        XCTAssertEqual(ExportFileNameTemplate.sanitizedStem("a\tb\nc"), "a_b_c")
        XCTAssertEqual(ExportFileNameTemplate.sanitizedStem("a\u{1}b"), "a_b")

        // Edge trimming: trailing spaces AND dots; leading spaces only (a
        // LEADING dot is legal and stays — Alcedo's front loop takes spaces).
        XCTAssertEqual(ExportFileNameTemplate.sanitizedStem("  stem. . "), "stem")
        XCTAssertEqual(ExportFileNameTemplate.sanitizedStem(" .stem. "), ".stem")
        XCTAssertEqual(ExportFileNameTemplate.sanitizedStem(".leading-dot"), ".leading-dot",
                       "a LEADING dot is legal and stays")

        // Windows reserved names (case-insensitive) gain a trailing "_".
        XCTAssertEqual(ExportFileNameTemplate.sanitizedStem("CON"), "CON_")
        XCTAssertEqual(ExportFileNameTemplate.sanitizedStem("con"), "con_")
        XCTAssertEqual(ExportFileNameTemplate.sanitizedStem("Com1"), "Com1_")
        XCTAssertEqual(ExportFileNameTemplate.sanitizedStem("lpt9"), "lpt9_")
        XCTAssertEqual(ExportFileNameTemplate.sanitizedStem("CONX"), "CONX", "only exact stems")
        XCTAssertEqual(ExportFileNameTemplate.sanitizedStem("CON 2026"), "CON 2026", "only exact stems")

        // The 200-character cap.
        let long = String(repeating: "x", count: 500)
        XCTAssertEqual(ExportFileNameTemplate.sanitizedStem(long).count, 200)
        XCTAssertEqual(
            ExportFileNameTemplate.sanitizedStem(long),
            String(repeating: "x", count: 200))

        // All-illegal input sanitizes to underscores (NOT empty — the
        // fallback only triggers on an all-empty RENDER).
        XCTAssertEqual(ExportFileNameTemplate.sanitizedStem("???"), "___")
        XCTAssertEqual(ExportFileNameTemplate.sanitizedStem(""), "")
    }

    // MARK: - Fallback

    /// An all-empty render falls back to "image" (Alcedo hpp:93 + the
    /// cpp:369-371 face) through `resolvedStem`.
    func testFallbackWhenRenderEmpty() {
        let sparse = ExportFileNameContext(sourceStem: "")
        XCTAssertEqual(
            ExportFileNameTemplate.resolvedStem(pattern: "{iso}", context: sparse),
            "image", "an all-empty render falls back")
        XCTAssertEqual(
            ExportFileNameTemplate.resolvedStem(pattern: "{date}", context: sparse),
            "image")
        // A failed parse also lands on the fallback (the queue face never
        // throws — parse errors gate the panel, not the per-job render).
        XCTAssertEqual(
            ExportFileNameTemplate.resolvedStem(pattern: "{nonsense}", context: sparse),
            "image")
        // A custom fallback round-trips through the sanitize too
        // ("UNTITLED" is not a Windows reserved stem — it passes as-is).
        XCTAssertEqual(
            ExportFileNameTemplate.resolvedStem(
                pattern: "{iso}", context: sparse, fallback: "UNTITLED"),
            "UNTITLED")
        XCTAssertEqual(
            ExportFileNameTemplate.resolvedStem(
                pattern: "{iso}", context: sparse, fallback: "con"),
            "con_", "the fallback sanitizes identically (reserved stem)")
        // A non-empty render never falls back.
        XCTAssertEqual(
            ExportFileNameTemplate.resolvedStem(
                pattern: "{source}", context: ExportFileNameContext(sourceStem: "IMG_0001")),
            "IMG_0001")
    }

    /// The composite anchor: source + date + sequence with a source stem
    /// that needs sanitizing.
    func testResolvedStemSanitizesTheRender() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let context = ExportFileNameContext(
            sourceStem: "IMG_0001:copy", captureDate: date, sequence: 7)
        XCTAssertEqual(
            ExportFileNameTemplate.resolvedStem(
                pattern: "{source} {date:yyyy MM dd}-{sequence:000}", context: context),
            "IMG_0001_copy 2026 03 01-007", "the ':' sanitizes to '_' inside the render")
    }
}

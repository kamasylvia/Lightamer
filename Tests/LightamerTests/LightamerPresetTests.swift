import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 12-4 T1 — the `.lightamer-preset` CONTAINER suite:
//
//   • sortedKeys golden: every projected key line asserted EXACT and IN
//     ORDER (the SidecarMetadataV3 line-based golden convention — the
//     prettyPrinted form is part of the one-way format lock), plus
//     encode→decode→encode byte identity
//   • the L013 projection: `instances` ride the sidecar's
//     `SidecarInstanceRecord` spelling — `paramsHash` is a decimal STRING
//     in the persisted bytes (one spelling, never a second one to migrate)
//   • absent-vs-present: optionals (category/layerStack/exportRecipe) are
//     OMITTED when nil (encodeIfPresent form locked — the plan's 「省略」)
//   • reader tolerance: a v1 file with missing optionals degrades-read;
//     a FUTURE schemaVersion (> 1) is tolerated (the D-S1 posture)
//   • the kind mutual exclusion: develop + exportRecipe = the TYPED error
//   • ExportRecipe direct mounting (Phase 11 移交①): recipe round-trips
//     verbatim; the recipe bytes carry ZERO hash keys (L013-clean by
//     construction)
// ─────────────────────────────────────────────────────────────────────────────

final class LightamerPresetTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    /// A FULLY DETERMINISTIC develop instance (fixed UUID / params bytes /
    /// hash) so the byte golden is stable run-to-run.
    private func goldenInstance() -> ModuleInstance {
        ModuleInstance(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            opName: "testgain",
            multiPriority: 0,
            multiName: "",
            iopOrder: 21.5,
            version: 1,
            enabled: true,
            paramsData: Data("abc".utf8),
            paramsHash: 1_234_567_890_123_456_789)
    }

    private func goldenDevelopPreset() -> LightamerPreset {
        LightamerPreset(
            kind: .develop,
            name: "Warm Film",
            category: "Tone",
            appVersion: "test",
            createdAt: Date(timeIntervalSince1970: 1_770_000_000),
            instances: [goldenInstance()])
    }

    // MARK: - The sortedKeys golden (line-based, in order)

    func testSortedKeysGoldenLinesInOrder() throws {
        let document = goldenDevelopPreset()
        let data = try encoder.encode(document)
        let text = String(decoding: data, as: UTF8.self)

        // The container's projected key lines, in sortedKeys order — the
        // `key : value` spelling (prettyPrinted + sortedKeys, the sidecar
        // aesthetic).
        let containerLines = [
            "\"appVersion\" : \"test\"",
            "\"category\" : \"Tone\"",
            "\"createdAt\" : 791692800",
            "\"kind\" : \"develop\"",
            "\"name\" : \"Warm Film\"",
            "\"schemaVersion\" : 1",
        ]
        var cursor = text.startIndex
        for line in containerLines {
            guard let found = text.range(of: line, range: cursor..<text.endIndex) else {
                XCTFail("missing out-of-order golden line: \(line)\n---\n\(text)")
                return
            }
            cursor = found.upperBound
        }
        // The instance record's projected key lines, in sortedKeys order —
        // the SIDECAR spelling verbatim (identical keys, L013 hash as a
        // decimal STRING).
        let instanceLines = [
            "\"enabled\" : true",
            "\"id\" : \"11111111-2222-3333-4444-555555555555\"",
            "\"iopOrder\" : 21.5",
            "\"multiName\" : \"\"",
            "\"multiPriority\" : 0",
            "\"opName\" : \"testgain\"",
            "\"paramsData\" : \"YWJj\"",
            "\"paramsHash\" : \"1234567890123456789\"",
            "\"version\" : 1",
        ]
        cursor = text.startIndex
        for line in instanceLines {
            guard let found = text.range(of: line, range: cursor..<text.endIndex) else {
                XCTFail("missing out-of-order instance golden line: \(line)\n---\n\(text)")
                return
            }
            cursor = found.upperBound
        }

        // The L013 lock: the persisted paramsHash is a quoted decimal
        // String — never a JSON number (2^53+ precision loses in non-Swift
        // tools).
        XCTAssertTrue(
            text.contains("\"paramsHash\" : \"1234567890123456789\""),
            "paramsHash must serialize as a decimal String (L013)")

        // Round-trip equality + encode→decode→encode BYTE identity (the
        // deterministic-diff face).
        let decoded = try JSONDecoder().decode(LightamerPreset.self, from: data)
        XCTAssertEqual(decoded, document)
        XCTAssertEqual(try encoder.encode(decoded), data)
    }

    // MARK: - Absent-vs-present (the encodeIfPresent form lock)

    func testNilOptionalsAreOmittedFromBytes() throws {
        let document = LightamerPreset(
            kind: .develop,
            name: "Bare",
            appVersion: "test",
            createdAt: Date(timeIntervalSince1970: 1_770_000_000))
        let text = String(
            decoding: try encoder.encode(document), as: UTF8.self)
        // category / layerStack / exportRecipe are ABSENT (never null —
        // the plan's 「恒 nil/省略」 form is the golden).
        XCTAssertFalse(text.contains("\"category\""))
        XCTAssertFalse(text.contains("\"layerStack\""))
        XCTAssertFalse(text.contains("\"exportRecipe\""))
        // The core keys always stand.
        XCTAssertTrue(text.contains("\"schemaVersion\" : 1"))
        XCTAssertTrue(text.contains("\"instances\""))
    }

    // MARK: - Reader tolerance

    func testV1FileWithMissingOptionalFieldsDegradesRead() throws {
        let json = """
        {
          "appVersion" : "old",
          "createdAt" : 1770000000,
          "instances" : [],
          "kind" : "develop",
          "name" : "Old Friend",
          "schemaVersion" : 1
        }
        """
        let document = try JSONDecoder().decode(
            LightamerPreset.self, from: Data(json.utf8))
        XCTAssertEqual(document.name, "Old Friend")
        XCTAssertNil(document.category)
        XCTAssertNil(document.layerStack)
        XCTAssertNil(document.exportRecipe)
        XCTAssertEqual(document.kind, .develop)
    }

    func testReaderToleratesFutureSchemaVersion() throws {
        let json = """
        {
          "appVersion" : "future",
          "category" : "Tone",
          "createdAt" : 1770000000,
          "instances" : [],
          "kind" : "develop",
          "name" : "From The Future",
          "schemaVersion" : 2,
          "someFutureKey" : {"nested": true}
        }
        """
        // The D-S1 posture: a newer document DEGRADES-READ (known fields
        // yield, unknown keys ignore) — never a hard failure.
        let document = try JSONDecoder().decode(
            LightamerPreset.self, from: Data(json.utf8))
        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.name, "From The Future")
        XCTAssertEqual(document.category, "Tone")
        XCTAssertTrue(document.instances.isEmpty)
    }

    // MARK: - The kind mutual exclusion (the typed violation)

    func testDevelopCarryingExportRecipeIsTypedInvalid() throws {
        var document = goldenDevelopPreset()
        document.exportRecipe = [
            ExportVariant(
                format: .jpeg(quality: 0.9), colorSpace: .sRGB)
        ]
        XCTAssertThrowsError(try document.validate()) { error in
            XCTAssertEqual(
                error as? LightamerPreset.ValidationError,
                .developCarriesExportRecipe(name: "Warm Film"))
        }
        // A pure develop preset validates.
        XCTAssertNoThrow(try goldenDevelopPreset().validate())
        // A pure export preset validates (its recipe gate lives at the
        // store's load face — T4).
        var export = LightamerPreset(
            kind: .export, name: "Web 2000",
            exportRecipe: [
                ExportVariant(
                    format: .jpeg(quality: 0.9), colorSpace: .sRGB)
            ])
        XCTAssertNoThrow(try export.validate())
        export.exportRecipe = nil
        XCTAssertNoThrow(try export.validate())
    }

    // MARK: - ExportRecipe direct mounting (Phase 11 移交①)

    func testExportRecipeMountsVerbatimWithZeroHashKeys() throws {
        let recipe: ExportRecipe = [
            ExportVariant(
                sizing: YiyinExportSettings(mode: .longEdge(px: 2048), dpi: 300),
                scalePercent: nil,
                format: .jpeg(quality: 0.9),
                colorSpace: .sRGB,
                yiyin: false,
                outputTag: "2048"),
            ExportVariant(
                sizing: YiyinExportSettings(mode: .original, dpi: 300),
                scalePercent: 50,
                format: .tiff(bitDepth: .sixteen, compression: .lzw),
                colorSpace: .displayP3,
                yiyin: true,
                outputTag: nil),
        ]
        let document = LightamerPreset(
            kind: .export,
            name: "Journal Set",
            appVersion: "test",
            createdAt: Date(timeIntervalSince1970: 1_770_000_000),
            exportRecipe: recipe)

        let data = try encoder.encode(document)
        let decoded = try JSONDecoder().decode(LightamerPreset.self, from: data)
        // The Phase 11 types mount VERBATIM — Codable is the whole story
        // (移交①: wiring, not migration).
        XCTAssertEqual(decoded.exportRecipe, recipe)
        XCTAssertEqual(decoded.kind, .export)
        XCTAssertEqual(try encoder.encode(decoded), data)

        // L013 note (the zero-hash face): the export recipe introduces NO
        // hash keys into the persisted bytes — ExportVariant carries no
        // hash fields by construction.
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(
            text.contains("\"paramsHash\""),
            "an export preset's bytes carry no pipeline hash keys")
    }
}

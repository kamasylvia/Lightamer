import Foundation
import LightamerCore
import LightamerIOP
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 12-1 T1 — sidecar v3 METADATA face (D-12-CONTEXT-1):
//
//   • v2 documents degrade-read: the five metadata fields decode nil
//   • the reader tolerance contract (schemaVersion > current) survives v3:
//     a hand-written v4 document decodes (five fields still project)
//   • encode ALWAYS writes the five keys (`null` for nil) — the plan-pinned
//     constant-write form, locked byte-golden
//   • HASH ISOLATION (D-8): setting the five fields leaves
//     historyHash / paramsHash byte-identical and driftDetected false —
//     metadata is not a pipeline parameter
//   • sortedKeys stable diff: a v2→v3 upgrade of the same logical document
//     adds ONLY the five keys (diff = added lines, never changed lines)
//
// All fixtures in FileManager.temporaryDirectory (L009: never external volume).
// ─────────────────────────────────────────────────────────────────────────────

final class SidecarMetadataV3Tests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("sidecarv3-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Fixtures

    /// A canonical one-commit document (the Perf07 fixture shape).
    private func makeDocument(
        rating: Int? = nil, flag: Int? = nil, colorLabel: Int? = nil,
        keywords: [String]? = nil, note: String? = nil,
        schemaVersion: Int? = nil
    ) -> LightamerSidecar {
        var history = HistoryStack()
        let exposure = ModuleInstance(
            module: ExposureModule.self, multiName: "e0",
            params: ExposureModule.Params(exposure: 0.3))
        history.commit(exposure, label: "exposure")
        let document = LightamerSidecar(
            imageID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000001")!,
            decoderVersionUsed: "v8", decodeParamsHash: 42,
            instances: history.effectiveInstances(), history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: 42),
            appVersion: "12-1-test",
            layerStack: nil,
            rating: rating, flag: flag, colorLabel: colorLabel,
            keywords: keywords, note: note)
        if let schemaVersion {
            var upgraded = document
            upgraded.schemaVersion = schemaVersion
            return upgraded
        }
        return document
    }

    private func encode(_ document: LightamerSidecar) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    private func decode(_ data: Data) throws -> LightamerSidecar {
        try JSONDecoder().decode(LightamerSidecar.self, from: data)
    }

    // MARK: - v2 downgrade read

    /// A v2 document (hand-written: no metadata keys at all) decodes with
    /// all five fields nil — the additive downgrade contract.
    func testV2DocumentDegradeReadsFiveFieldsNil() throws {
        let v3Bytes = try encode(makeDocument(
            rating: 4, flag: 1, colorLabel: 2,
            keywords: ["Nature|Flower"], note: "keep"))
        var json = try JSONSerialization.jsonObject(with: v3Bytes) as! [String: Any]
        json["schemaVersion"] = 2
        for key in ["rating", "flag", "colorLabel", "keywords", "note"] {
            json.removeValue(forKey: key) // the v2 spelling: keys absent
        }
        let v2Bytes = try JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .sortedKeys])

        let document = try decode(v2Bytes)
        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertNil(document.rating)
        XCTAssertNil(document.flag)
        XCTAssertNil(document.colorLabel)
        XCTAssertNil(document.keywords)
        XCTAssertNil(document.note)
        // The v2 parameter face is untouched by the upgrade.
        XCTAssertEqual(document.history.items.count, 1)
        XCTAssertFalse(document.driftDetected)
    }

    /// A v2 document WITH explicit `null` metadata keys (defensive hybrid)
    /// also decodes nil — decodeIfPresent handles both absent and null.
    func testV2DocumentWithExplicitNullsDegradeReads() throws {
        let v3Bytes = try encode(makeDocument()) // all-nil → five nulls
        var json = try JSONSerialization.jsonObject(with: v3Bytes) as! [String: Any]
        json["schemaVersion"] = 2 // nulls stay, version reads 2
        let hybridBytes = try JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        let document = try decode(hybridBytes)
        XCTAssertNil(document.rating)
        XCTAssertNil(document.keywords)
        XCTAssertNil(document.note)
    }

    // MARK: - Reader tolerance (> current)

    /// The tolerance contract (readers MUST tolerate schemaVersion >
    /// schemaVersionCurrent): a hand-written v4 document decodes — the
    /// metadata fields still project, nothing throws, drift stays honest.
    func testFutureVersionDocumentStillDecodes() throws {
        let bytes = try encode(makeDocument(
            rating: 5, note: "future", schemaVersion: 4))
        let document = try decode(bytes)
        XCTAssertEqual(document.schemaVersion, 4)
        XCTAssertEqual(document.rating, 5)
        XCTAssertEqual(document.note, "future")
        XCTAssertFalse(document.driftDetected, "hash inputs unchanged by v4 stamp")
    }

    // MARK: - Encode constant-write (the golden lock)

    /// The five keys are ALWAYS written — a fully-nil document serializes
    /// with five explicit `null`s (never absent). Byte-golden on the
    /// projected key lines (the sortedKeys form).
    func testEncodeAlwaysWritesFiveKeysWithNulls() throws {
        let bytes = try encode(makeDocument())
        let text = String(data: bytes, encoding: .utf8)!
        for key in ["colorLabel", "flag", "keywords", "note", "rating"] {
            let pattern = "\"" + key + "\" : null"
            XCTAssertTrue(
                text.contains(pattern),
                "constant-write form: '\(key)' must serialize as null, got: \(text)")
        }
    }

    /// The byte golden for the LOCKED shape (12-1 T1): the five metadata
    /// key lines are exactly these (sortedKeys form, null for nil), the
    /// top-level key set is exactly the 15 frozen keys, and a
    /// decode→encode round-trip is byte-stable. (The history/instance
    /// sub-objects carry dynamic UUIDs/timestamps — their spelling is
    /// locked by the 02-06 golden tests, not duplicated here.)
    func testAllNilV3ByteGolden() throws {
        let first = try encode(makeDocument())
        let text = String(data: first, encoding: .utf8)!

        let metadataLines: Set<String> = [
          "  \"colorLabel\" : null,",
          "  \"flag\" : null,",
          "  \"keywords\" : null,",
          "  \"note\" : null,",
          "  \"rating\" : null,",
        ]
        for line in metadataLines {
            XCTAssertTrue(text.contains(line), "missing golden line: \(line)")
        }
        XCTAssertTrue(text.contains("  \"schemaVersion\" : 3\n"))

        let json = try JSONSerialization.jsonObject(with: first) as! [String: Any]
        XCTAssertEqual(
            Set(json.keys),
            [
              "appVersion", "colorLabel", "decoderVersionUsed",
              "decodeParamsHash", "flag", "history", "historyHash",
              "imageID", "instances", "keywords", "note",
              "rating", "schemaVersion",
            ],
            "the top-level key set IS the format (14 keys; nil layerStack rides encodeIfPresent — key absent, the 02-06 form)")

        // Round-trip byte stability (the SC#3 contract on the v3 face).
        let second = try encode(try decode(first))
        XCTAssertEqual(first, second)
    }

    // MARK: - Hash isolation (D-8)

    /// Setting the five metadata fields leaves historyHash (and every
    /// snapshot paramsHash) byte-identical, and driftDetected stays false —
    /// a rating change must never false-positive as external drift nor
    /// stale a thumbnail.
    func testMetadataWriteKeepsHashesByteIdentical() throws {
        let before = makeDocument()
        var after = makeDocument()
        after.rating = 3
        after.flag = 2
        after.colorLabel = 5
        after.keywords = ["Nature", "Nature|Flower|Rose"]
        after.note = "picked for the calendar"

        XCTAssertEqual(before.historyHash, after.historyHash)
        XCTAssertEqual(before.decodeParamsHash, after.decodeParamsHash)
        for (a, b) in zip(before.history.items, after.history.items) {
            XCTAssertEqual(a.snapshot.paramsHash, b.snapshot.paramsHash)
        }
        XCTAssertFalse(after.driftDetected)
    }

    /// The doc-level recomputation: HistoryHash.hash over the restored
    /// stack of a metadata-laden document equals the stored hash — the
    /// five fields are provably OUTSIDE the hash input.
    func testHistoryHashProjectionIgnoresMetadata() throws {
        let document = try decode(try encode(makeDocument(
            rating: 1, flag: 1, colorLabel: 0,
            keywords: ["A|B"], note: "n")))
        let recomputed = HistoryHash.hash(
            stack: document.history,
            decodeParamsHash: document.decodeParamsHash,
            layerSnapshot: document.layerStack?.snapshot)
        XCTAssertEqual(recomputed, document.historyHash)
    }

    // MARK: - sortedKeys stable diff (v2→v3 upgrade = added keys only)

    /// Upgrading the same logical document v2→v3 diffs as ADDED LINES only
    /// (the five metadata keys) — no existing line changes value. The v2
    /// byte form is derived from the v3 encoder output itself (strip the
    /// five metadata lines + swap the version line) — the authentic shape
    /// the v2-era binary wrote (its encoder had no metadata keys).
    func testV2ToV3UpgradeDiffIsAdditiveKeysOnly() throws {
        let v3Text = String(data: try encode(makeDocument()), encoding: .utf8)!
        let metadataPrefixes = [
          "  \"colorLabel\"", "  \"flag\"", "  \"keywords\"",
          "  \"note\"", "  \"rating\"",
        ]
        var v2Lines: [String] = []
        for line in v3Text.split(separator: "\n").map(String.init) {
            if metadataPrefixes.contains(where: { line.hasPrefix($0) }) { continue }
            if line == "  \"schemaVersion\" : 3" {
                v2Lines.append("  \"schemaVersion\" : 2")
            } else {
                v2Lines.append(line)
            }
        }
        let v3Lines = Set(v3Text.split(separator: "\n").map(String.init))
        let v2LineSet = Set(v2Lines)

        // The stripped form must still be valid JSON (a real v2 document).
        let v2Document = try decode(Data(v2Lines.joined(separator: "\n").utf8))
        XCTAssertEqual(v2Document.schemaVersion, 2)

        let added = v3Lines.subtracting(v2LineSet)
        let removed = v2LineSet.subtracting(v3Lines)
        XCTAssertEqual(
            removed, ["  \"schemaVersion\" : 2"],
            "the ONLY changed line is the version bump (2 gone, 3 added)")
        XCTAssertEqual(
            added,
            [
              "  \"colorLabel\" : null,",
              "  \"flag\" : null,",
              "  \"keywords\" : null,",
              "  \"note\" : null,",
              "  \"rating\" : null,",
              "  \"schemaVersion\" : 3",
            ],
            "the diff is exactly the five metadata keys + the version bump")
    }

    // MARK: - Round-trip with values

    func testMetadataValuesRoundTrip() throws {
        let original = makeDocument(
            rating: 0, flag: 0, colorLabel: 6,
            keywords: [], note: "")
        let restored = try decode(try encode(original))
        XCTAssertEqual(restored.rating, 0, "0 is a VALUE (rated zero), not nil")
        XCTAssertEqual(restored.flag, 0)
        XCTAssertEqual(restored.colorLabel, 6)
        XCTAssertEqual(restored.keywords, [], "empty array survives (cleared, not untagged)")
        XCTAssertEqual(restored.note, "")
        XCTAssertEqual(restored.schemaVersion, 3)
    }
}

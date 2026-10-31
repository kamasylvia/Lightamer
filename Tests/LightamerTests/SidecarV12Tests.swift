@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SidecarV12Tests (Plan M9-2 T2 — LIBRARY, the SidecarV10/V11 chain's seat):
// the v12 bump's three byte faces (the persisted-face precedent chain —
// v8 aiProvenance / v9 filmRecord / v10 process / v11 note / v12 the film
// record's camera_filter + paper_grade riding INSIDE the filmRecord
// Codable payload):
//
//   1. THE v11 ZERO-DRIFT FACE: a v11 document decodes and re-encodes
//      byte-identically apart from the schemaVersion digit (the two new
//      keys stay ABSENT for every grade-less record).
//   2. THE v12 ROUND-TRIP: a record with cameraFilter/paperGrade set
//      survives encode → decode with both keys verbatim.
//   3. THE ABSENT-IDENTITY FACE: the same record with the fields nil
//      serializes WITHOUT the keys (nil = omitted, not null — the v9
//      filmRecord pristine discipline) and the record hash changes when
//      the grade moves (the HistoryHash fold tail's premise).
// ─────────────────────────────────────────────────────────────────────────────

final class SidecarV12Tests: XCTestCase {

    private static let imageID = UUID(
        uuidString: "B2E3F4A5-2C4E-4F6A-8B1C-3D4E5F6A7B8D")!

    private func makeDocument(
        schemaVersion: Int, record: FilmRecord?
    ) -> LightamerSidecar {
        let decodeHash = UInt64(0x0123_4567_89AB_CDEF)
        var doc = LightamerSidecar(
            imageID: Self.imageID,
            decoderVersionUsed: "v9",
            decodeParamsHash: decodeHash,
            instances: [],
            history: HistoryStack(),
            historyHash: decodeHash,
            appVersion: "test")
        doc.schemaVersion = schemaVersion
        if let record {
            doc.filmRecord = record
        }
        return doc
    }

    private func encode(_ doc: LightamerSidecar) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(doc)
    }

    // MARK: - 1: the v11 zero-drift face

    func testV11DocumentRoundTripsByteIdenticallyExceptTheDigit() throws {
        var record = FilmRecord()
        record.filmStock = "kodak_portra_400"
        record.paperStock = "kodak_portra_endura"
        record.exposureEv = 0.25
        let doc = makeDocument(schemaVersion: 11, record: record)

        let bytes = try encode(doc)
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertTrue(text.contains("\"schemaVersion\":11"), "v11 digit kept")
        XCTAssertFalse(text.contains("camera_filter"),
                       "the new keys stay absent on a grade-less record")
        XCTAssertFalse(text.contains("paper_grade"),
                       "the new keys stay absent on a grade-less record")

        let decoded = try JSONDecoder().decode(LightamerSidecar.self, from: bytes)
        XCTAssertNil(decoded.filmRecord?.cameraFilter)
        XCTAssertNil(decoded.filmRecord?.paperGrade)
        // Re-encode from the decoded face: byte-identical.
        let reencoded = try encode(decoded)
        XCTAssertEqual(bytes, reencoded, "v11 zero-drift (byte face)")
    }

    // MARK: - 2: the v12 round-trip

    func testV12CarriesBothKeysVerbatim() throws {
        var record = FilmRecord()
        record.filmStock = "kodak_tri_x_400"
        record.paperStock = "ilford_multigrade_iv_rc"
        record.paperGrade = "3"
        record.cameraFilter = "w25"
        let doc = makeDocument(schemaVersion: 12, record: record)

        let bytes = try encode(doc)
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertTrue(text.contains("\"paper_grade\":\"3\""), "grade verbatim")
        XCTAssertTrue(text.contains("\"camera_filter\":\"w25\""), "filter verbatim")

        let decoded = try JSONDecoder().decode(LightamerSidecar.self, from: bytes)
        XCTAssertEqual(decoded.filmRecord?.paperGrade, "3")
        XCTAssertEqual(decoded.filmRecord?.cameraFilter, "w25")
        // M8-3+ T3: the live digit moved to 13 (the v12 digit is the
        // document's own face above — the current-digit pin lives in
        // SidecarV13Tests now).
    }

    // MARK: - 3: the absent-identity face + the hash movement

    func testNilFieldsOmitKeysAndGradeMovesTheRecordHash() throws {
        var record = FilmRecord()
        record.filmStock = "ilford_hp5_plus_400"
        record.paperStock = "ilford_multigrade_iv_rc"
        let without = record.stableHash()
        let bytes = try encode(makeDocument(schemaVersion: 12, record: record))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("paper_grade"))

        record.paperGrade = "00"
        let withGrade = record.stableHash()
        XCTAssertNotEqual(without, withGrade,
                          "a grade move changes the record hash (the fold tail)")

        record.paperGrade = nil
        record.cameraFilter = "w47"
        XCTAssertNotEqual(record.stableHash(), without,
                          "a filter move changes the record hash")
    }
}

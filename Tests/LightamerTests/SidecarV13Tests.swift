@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SidecarV13Tests (Plan M8-3+ T3 — LIBRARY, the SidecarV10/V11/V12 chain's
// seat): the v13 bump's three byte faces (the persisted-face precedent
// chain — v12 camera_filter+paper_grade / v13 the reversal mode + the four
// spatial legs riding INSIDE the filmRecord Codable payload):
//
//   1. THE v12 ZERO-DRIFT FACE: a v12 document decodes and re-encodes
//      byte-identically (the five new keys stay ABSENT for every
//      untouched record).
//   2. THE v13 ROUND-TRIP: a record with all five fields set survives
//      encode → decode with every key verbatim.
//   3. THE T2-WINDOW FACE: a v12-byte document carrying reversal_print_mode
//      (written in the T2→T3 window) decodes with the mode intact (the
//      R-M83P-8 seam — the mode key the T2 intermediate wrote is the
//      SAME key v13 activates).
// ─────────────────────────────────────────────────────────────────────────────

final class SidecarV13Tests: XCTestCase {

    private static let imageID = UUID(
        uuidString: "C3D4E5F6-3D5F-4A7B-9C2D-4E5F6A7B8C9E")!

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

    // MARK: - 1: the v12 zero-drift face

    func testV12DocumentRoundTripsByteIdentically() throws {
        var record = FilmRecord()
        record.filmStock = "kodak_portra_400"
        record.paperStock = "kodak_portra_endura"
        record.exposureEv = 0.25
        record.paperGrade = "3"
        let doc = makeDocument(schemaVersion: 12, record: record)

        let bytes = try encode(doc)
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertTrue(text.contains("\"schemaVersion\":12"), "v12 digit kept")
        for key in ["reversal_print_mode", "grain_amount", "halation_amount",
                    "diffusion_family", "diffusion_amount"] {
            XCTAssertFalse(text.contains(key),
                           "the v13 keys stay absent on a v12 record")
        }

        let decoded = try JSONDecoder().decode(LightamerSidecar.self, from: bytes)
        XCTAssertNil(decoded.filmRecord?.reversalPrintMode)
        XCTAssertNil(decoded.filmRecord?.grainAmount)
        XCTAssertNil(decoded.filmRecord?.halationAmount)
        XCTAssertNil(decoded.filmRecord?.diffusionFamily)
        XCTAssertNil(decoded.filmRecord?.diffusionAmount)
        // The v12 keys survive (the bump never drops the past).
        XCTAssertEqual(decoded.filmRecord?.paperGrade, "3")
        let reencoded = try encode(decoded)
        XCTAssertEqual(bytes, reencoded, "v12 zero-drift (byte face)")
    }

    // MARK: - 2: the v13 round-trip

    func testV13CarriesAllFiveKeysVerbatim() throws {
        var record = FilmRecord()
        record.filmStock = "fujifilm_velvia_100"
        record.paperStock = "kodak_portra_endura"
        record.reversalPrintMode = SpectralNeutralSolve.directPositiveMode
        record.grainAmount = 2.5
        record.halationAmount = 0.75
        record.diffusionFamily = "pro-mist"
        record.diffusionAmount = 0.5
        let doc = makeDocument(schemaVersion: 13, record: record)

        let bytes = try encode(doc)
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertTrue(text.contains("\"reversal_print_mode\":\"direct-positive\""))
        XCTAssertTrue(text.contains("\"grain_amount\":2.5"))
        XCTAssertTrue(text.contains("\"halation_amount\":0.75"))
        XCTAssertTrue(text.contains("\"diffusion_family\":\"pro-mist\""))
        XCTAssertTrue(text.contains("\"diffusion_amount\":0.5"))

        let decoded = try JSONDecoder().decode(LightamerSidecar.self, from: bytes)
        XCTAssertEqual(decoded.filmRecord?.reversalPrintMode,
                       SpectralNeutralSolve.directPositiveMode)
        XCTAssertEqual(decoded.filmRecord?.grainAmount, 2.5)
        XCTAssertEqual(decoded.filmRecord?.halationAmount, 0.75)
        XCTAssertEqual(decoded.filmRecord?.diffusionFamily, "pro-mist")
        XCTAssertEqual(decoded.filmRecord?.diffusionAmount, 0.5)
        XCTAssertEqual(LightamerSidecar.schemaVersionCurrent, 13)
    }

    // MARK: - 3: the T2-window face (R-M83P-8)

    func testT2WindowModeKeyDecodesUnderV13() throws {
        // A document written in the T2→T3 window: the v12 digit with
        // the reversal key already set (the T2 intermediate wrote the
        // SAME key v13 activates — byte-compatible by construction).
        var record = FilmRecord()
        record.filmStock = "fujifilm_velvia_100"
        record.paperStock = "kodak_portra_endura"
        record.reversalPrintMode = SpectralNeutralSolve.directPositiveMode
        let doc = makeDocument(schemaVersion: 12, record: record)

        let bytes = try encode(doc)
        let decoded = try JSONDecoder().decode(LightamerSidecar.self, from: bytes)
        XCTAssertEqual(decoded.filmRecord?.reversalPrintMode,
                       SpectralNeutralSolve.directPositiveMode,
                       "the T2-window mode key decodes intact (R-M83P-8)")
    }
}

@testable import LightamerIOP
@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// GrainCalibrationTests (Plan M9-2 T4 — IOP) — the calibration-table face:
//
//   1. ROUND-TRIP: the persisted grain_calibration.json parses with the
//      four BW stocks; the T1-verified RMS finals ride verbatim; HP5's
//      null stays null (and null RMS ⇒ null recommendation, the honest
//      degrade — no interpolation was invented).
//   2. THE MAPPING (pure + deterministic): the same table answers the
//      same entry; unknown stocks answer nil; the monotonicity premise
//      (higher published RMS ⇒ higher-or-equal strength) holds on the
//      persisted values.
//   3. GrainModule ZERO-DIFF: this layer never touches the operator —
//      the machine check is the file diff itself (T5's gate); the test
//      face pins only that the recommended values live in the operator's
//      OWN strength domain [0,100].
// ─────────────────────────────────────────────────────────────────────────────

final class GrainCalibrationTests: XCTestCase {

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var tableURL: URL {
        repoRoot.appendingPathComponent(
            "Resources/FilmProfilesBW/grain_calibration.json")
    }

    private func loadTable() throws -> [String: GrainCalibration.Entry] {
        try GrainCalibration.load(url: Self.tableURL)
    }

    func testTableRoundTripsWithVerifiedRmsFinals() throws {
        let table = try loadTable()
        XCTAssertEqual(
            Set(table.keys),
            ["kodak_tri_x_400", "kodak_tmax_100",
             "fujifilm_neopan_acros_100_ii", "ilford_hp5_plus_400"])
        XCTAssertEqual(table["kodak_tri_x_400"]?.publishedRms, 17,
                       "F-4017 p6 '17 (fine)'")
        XCTAssertEqual(table["kodak_tmax_100"]?.publishedRms, 8,
                       "F-4016 p8 image-structure table (the R4 correction)")
        XCTAssertEqual(table["fujifilm_neopan_acros_100_ii"]?.publishedRms, 7,
                       "AF3-0258E 'DIFFUSE RMS GRANULARITY VALUE: 7'")
        XCTAssertNil(table["ilford_hp5_plus_400"]?.publishedRms,
                     "Harman prints no RMS for HP5 — the honest null")
        XCTAssertNil(table["ilford_hp5_plus_400"]?.recommendedStrength,
                     "null RMS ⇒ null recommendation (no invented interpolation)")
    }

    func testMappingIsPureDeterministicAndTypedDegrading() throws {
        let table = try loadTable()
        // Deterministic: the same bytes answer the same entry.
        let again = try loadTable()
        for (id, entry) in table {
            XCTAssertEqual(again[id], entry, "\(id): deterministic identity")
        }
        // Unknown stock → nil (the readout hides).
        XCTAssertNil(
            GrainCalibration.recommendedStrength(forStock: "kodak_portra_400", in: table))
        XCTAssertNil(
            GrainCalibration.publishedRms(forStock: "unknown_stock", in: table))
        // The three calibrated films answer in the operator's domain.
        for id in ["kodak_tri_x_400", "kodak_tmax_100",
                   "fujifilm_neopan_acros_100_ii"] {
            let s = try XCTUnwrap(
                GrainCalibration.recommendedStrength(forStock: id, in: table),
                "\(id): carries a recommendation")
            XCTAssertTrue((0...100).contains(s),
                          "\(id): strength \(s) in GrainModule's [0,100] domain")
        }
        // The monotonicity premise (the inverse of a monotone map).
        XCTAssertTrue(GrainCalibration.isMonotone(table),
                      "higher published RMS ⇒ higher-or-equal strength")
        // Fail-closed: a document without the `films` key rejects typed.
        XCTAssertThrowsError(
            try GrainCalibration.parse(Data("{}".utf8)))
        XCTAssertThrowsError(
            try GrainCalibration.parse(Data("nope".utf8)))
    }
}

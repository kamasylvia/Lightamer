@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// FilmRecordTests (Plan M3-3-01 T1, KD-1) — the film record schema face
// (DrtRecordTests same shape, LAYERS/Core level):
//
//   1. DEFAULTS: the pristine session ("" stocks, zeroed shifts, strength
//      1.0, adaptive off, EV 0).
//   2. CODABLE: canonical sortedKeys byte stability (two encodes byte-equal
//      — L013) + round-trip equality + snake_case key spellings on disk.
//   3. TOLERANT DECODE: a partial record (subset of keys) and an
//      unknown-key record both decode to valid values (decodeIfPresent).
//   4. STABLEHASH: same value → same hash; one-field change → new hash;
//      cross-launch determinism (the hash is pure canonical-JSON FNV-1a).
//   5. PRISTINE JUDGMENT: isFilmRecordDefault == the default record and it
//      is not a render-identity claim (documented semantics).
// ─────────────────────────────────────────────────────────────────────────────

final class FilmRecordTests: XCTestCase {

    // MARK: - 1: defaults

    func testDefaultsAreThePristineSession() {
        let record = FilmRecord()
        XCTAssertEqual(record.filmStock, "")
        XCTAssertEqual(record.paperStock, "")
        XCTAssertEqual(record.yFilterShift, 0.0)
        XCTAssertEqual(record.mFilterShift, 0.0)
        XCTAssertFalse(record.contentAdaptiveShift)
        XCTAssertEqual(record.strength, 1.0)
        XCTAssertEqual(record.exposureEv, 0.0)
    }

    // MARK: - 2: Codable byte stability + round-trip

    func testCanonicalEncodingIsByteStableAcrossEncodes() throws {
        var record = FilmRecord()
        record.filmStock = "kodak_portra_400"
        record.paperStock = "kodak_portra_endura"
        record.yFilterShift = 12.5
        record.mFilterShift = 3.25
        record.contentAdaptiveShift = true
        record.strength = 0.8
        record.exposureEv = -0.3

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let first = try encoder.encode(record)
        let second = try encoder.encode(record)
        XCTAssertEqual(
            String(decoding: first, as: UTF8.self),
            String(decoding: second, as: UTF8.self),
            "two canonical encodes must be byte-equal (L013)")
    }

    func testDiskKeysAreSnakeCase() throws {
        var record = FilmRecord()
        record.filmStock = "kodak_ektar_100"
        record.exposureEv = 0.5
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encoder.encode(record)) as? [String: Any])
        XCTAssertEqual(
            Set(object.keys),
            ["film_stock", "paper_stock", "y_filter_shift", "m_filter_shift",
             "content_adaptive_shift", "strength", "exposure_ev"],
            "the on-disk key set is the KD-1 snake_case spelling, exactly seven keys")
    }

    func testRoundTripPreservesEveryField() throws {
        var record = FilmRecord()
        record.filmStock = "kodak_portra_400"
        record.paperStock = "kodak_portra_endura"
        record.yFilterShift = 40.0
        record.mFilterShift = 51.5
        record.contentAdaptiveShift = true
        record.strength = 0.5
        record.exposureEv = 1.25

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(
            FilmRecord.self, from: encoder.encode(record))
        XCTAssertEqual(decoded, record)
    }

    // MARK: - 3: tolerant decode

    func testPartialRecordDecodesWithDefaults() throws {
        // Only two keys on disk — the rest fall back to the pristine
        // defaults (decodeIfPresent posture).
        let json = Data("""
        {"film_stock": "kodak_portra_400", "strength": 0.25}
        """.utf8)
        let decoded = try JSONDecoder().decode(FilmRecord.self, from: json)
        XCTAssertEqual(decoded.filmStock, "kodak_portra_400")
        XCTAssertEqual(decoded.strength, 0.25)
        XCTAssertEqual(decoded.paperStock, "")
        XCTAssertEqual(decoded.yFilterShift, 0.0)
        XCTAssertEqual(decoded.mFilterShift, 0.0)
        XCTAssertFalse(decoded.contentAdaptiveShift)
        XCTAssertEqual(decoded.exposureEv, 0.0)
    }

    func testUnknownKeysAreIgnoredByDecode() throws {
        let json = Data("""
        {"film_stock": "f", "spectral_footnote": {"a": 1}, "future_knob": 3}
        """.utf8)
        let decoded = try JSONDecoder().decode(FilmRecord.self, from: json)
        XCTAssertEqual(decoded.filmStock, "f")
        XCTAssertEqual(decoded, {
            var r = FilmRecord()
            r.filmStock = "f"
            return r
        }())
    }

    // MARK: - 4: stableHash

    func testStableHashIsDeterministicAndDifferenceFaceMoves() {
        var a = FilmRecord()
        a.filmStock = "kodak_portra_400"
        var b = a
        b.yFilterShift = 1.0

        XCTAssertEqual(a.stableHash(), a.stableHash(), "same value → same hash")
        XCTAssertEqual(FilmRecord().stableHash(), FilmRecord().stableHash())
        XCTAssertNotEqual(a.stableHash(), b.stableHash(), "one-field change → new hash")
        XCTAssertNotEqual(
            FilmRecord().stableHash(), a.stableHash(),
            "pristine vs non-pristine differ (stock id enters the digest)")
    }

    func testStableHashMatchesTheCanonicalJSONFormula() throws {
        // The documented formula, computed independently: FNV-1a over the
        // .sortedKeys canonical JSON bytes.
        var record = FilmRecord()
        record.paperStock = "kodak_portra_endura"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        XCTAssertEqual(record.stableHash(), StableHash.hash(data))
    }

    // MARK: - 5: pristine judgment

    func testPristineJudgmentTracksTheDefaultRecord() {
        XCTAssertTrue(isFilmRecordDefault(FilmRecord()))
        var touched = FilmRecord()
        touched.mFilterShift = 0.001
        XCTAssertFalse(isFilmRecordDefault(touched))
        var bound = FilmRecord()
        bound.filmStock = "kodak_portra_400"
        XCTAssertFalse(isFilmRecordDefault(bound), "binding a stock leaves pristine")
    }
}

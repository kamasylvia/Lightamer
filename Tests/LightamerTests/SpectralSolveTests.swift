@testable import LightamerCore
import Foundation
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralSolveTests (Plan M8-2 T2 — IOP) — the spectral-domain solve face
// (D-M8-8's consumption layer):
//
//   1. THE NEUTRAL FACE: the spectral AUTO core's neutral pair (the
//      build's self-solved print CC) holds its REGISTERED offset from the
//      measured neutral_print_filters anchor (portra_400 ×
//      kodak_portra_endura × TH-KG3 = [0, 51.568, 52.534]) — the anchor
//      JSON stays byte-verbatim; the offset is the M8-1a self-solve
//      deviation's registration (the plan's ±10 CC premise predates that
//      pivot — declared in M8-2-DECISIONS).
//   2. THE K CALIBRATION (the session operating point's spectral face):
//      the build's midgrayPrintRaw log-channel ratios are EXACTLY zero
//      (the RFC-028 gray-error-0 discipline平移 — the solved pair IS the
//      calibration; the runtime solve adds nothing to it).
//   3. THE KEY SHAPE: the additive cacheKey(modeTag:) overload folds the
//      same three terms in the same canonical order (the exact-value FNV
//      pin), and the spectral tags are a DISTINCT keyspace — the density
//      and spectral cores never share a cache slot for identical
//      pair ⊕ stats (the cross-core isolation).
//   4. THE EXPOSURE CONSUMPTION LAYER: the record's exposureEv folds into
//      the solution GAIN (× 2^ev) — the neutral pair holds bit-identical,
//      the cache gains exactly ONE entry for both records (no exposure
//      term in the key).
//   5. THE DETERMINISM GATE: solve ×2 on the same inputs is bit-identical
//      (the FSIM-01b gate, spectral face).
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralSolveTests: XCTestCase {

    // MARK: - Fixtures

    private func profilesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FilmProfiles/profiles")
    }

    private var portra: FilmProfile {
        get throws {
            try XCTUnwrap(try FilmMaterialStore(
                profilesDirectory: profilesDirectory()
            ).profile(id: "kodak_portra_400"))
        }
    }

    private var endura: FilmProfile {
        get throws {
            try XCTUnwrap(try FilmMaterialStore(
                profilesDirectory: profilesDirectory()
            ).profile(id: "kodak_portra_endura"))
        }
    }

    /// The tables memo box (the class-instance form — Swift 6 strict
    /// concurrency rejects static mutable globals).
    private static let tablesBox = SolveFixtureBox()

    private final class SolveFixtureBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: SpectralFilmTables?
        func tables(make: () throws -> SpectralFilmTables) throws -> SpectralFilmTables {
            lock.lock()
            defer { lock.unlock() }
            if let value { return value }
            lock.unlock()
            let made = try make()
            lock.lock()
            value = made
            lock.unlock()
            return made
        }
    }

    private func spectralTables() throws -> SpectralFilmTables {
        try Self.tablesBox.tables {
            try SpectralBuildEngine.build(film: try portra, paper: try endura)
        }
    }

    /// The measured anchor row from the vendored neutral_print_filters
    /// table (CC BY-SA byte-verbatim — read, never embedded).
    private func measuredNeutralAnchor() throws -> (m: Double, y: Double) {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let tableURL = root.appendingPathComponent(
            "Resources/FilmProfiles/neutral_print_filters.json")
        let data = try Data(contentsOf: tableURL)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data)
            as? [String: Any])
        let paper = try XCTUnwrap(object["kodak_portra_endura"] as? [String: Any])
        let illuminant = try XCTUnwrap(paper["TH-KG3"] as? [String: Any])
        let row = try XCTUnwrap(illuminant["kodak_portra_400"] as? [Double])
        XCTAssertEqual(row.count, 3)
        XCTAssertEqual(row[0], 0.0, "the C dial stays neutral-fixed in the table")
        return (m: row[1], y: row[2])
    }

    /// A per-test histogram: the offset shifts every count so two tests'
    /// fixtures never share a statsHash — the shared FilmSolveCache's
    /// entries from earlier tests in this suite cannot satisfy a later
    /// test's key (each test owns its keyspace slice).
    private func histogram(offset: Int) -> FilmStatsSeam.PlaneHistogram {
        var counts = [[UInt32]]()
        for channel in 0..<4 {
            var bins = [UInt32](repeating: 0, count: 256)
            for bin in 0..<256 {
                bins[bin] = UInt32((bin * 7 + channel * 13 + offset) % 97)
            }
            counts.append(bins)
        }
        return FilmStatsSeam.PlaneHistogram(perChannel: counts)
    }

    // MARK: - 1: the neutral face (the registration pin + the pristine face)

    /// The REGISTERED offset of the spectral self-solved pair from the
    /// measured anchor. The plan's "±10 CC band against
    /// neutral_print_filters" premise was written before M8-1a's
    /// build-time self-solve pivot: our self-approximated dichroic/SPD
    /// curves (X6) solve their OWN neutral at a materially different CC
    /// than the real dichroic head did (M8-1A-DECISIONS III.1 measured
    /// the 0.441 channel scatter AT the measured CC — the measured
    /// table's premises do not carry over). The neutrality ITSELF is the
    /// invariant (test 2's gray-error-zero); the anchor offset is a
    /// REGISTERED model deviation — pinned here (±2 CC) so a solver or
    /// dichroic drift flips this test through the re-pin process, and the
    /// measured JSON stays byte-verbatim regardless.
    func testSpectralNeutralPairHoldsTheRegisteredOffsetFromTheAnchor() throws {
        let tables = try spectralTables()
        let anchor = try measuredNeutralAnchor()
        let registeredOffsetM = 18.5   // measured M − solved M (52.534-class anchor)
        let registeredOffsetY = 25.7   // measured Y − solved Y
        let pinBand = 2.0              // CC points — the drift catcher
        XCTAssertEqual(anchor.m - Double(tables.solvedPrintCC.y), registeredOffsetM,
                       accuracy: pinBand,
                       "the solved-vs-measured M offset drifted past the "
                       + "registration pin (re-pin through DECISIONS)")
        XCTAssertEqual(anchor.y - Double(tables.solvedPrintCC.z), registeredOffsetY,
                       accuracy: pinBand,
                       "the solved-vs-measured Y offset drifted past the "
                       + "registration pin (re-pin through DECISIONS)")
        // The physical CC domain (the dials' producer range).
        XCTAssertGreaterThanOrEqual(Double(tables.solvedPrintCC.y), 0)
        XCTAssertLessThanOrEqual(Double(tables.solvedPrintCC.y), 250)
        XCTAssertGreaterThanOrEqual(Double(tables.solvedPrintCC.z), 0)
        XCTAssertLessThanOrEqual(Double(tables.solvedPrintCC.z), 250)
        XCTAssertEqual(tables.solvedPrintCC.x, 0.0, "the C dial stays neutral-fixed")

        // The solve returns the SAME pair (the consumption face adds only
        // the record deltas, all zero on the pristine record).
        let film = try portra
        let paper = try endura
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)
        var record = FilmRecord()
        record.filmStock = film.info.stock ?? ""
        record.paperStock = paper.info.stock ?? ""
        let solution = try FilmRuntimeSolve.solveSpectral(
            record: record, tables: tables, materialPairHash: pairHash, histogram: nil)
        XCTAssertEqual(
            solution.magentaCC.bitPattern, Double(tables.solvedPrintCC.y).bitPattern,
            "pristine record: the solved M IS the neutral pair")
        XCTAssertEqual(
            solution.yellowCC.bitPattern, Double(tables.solvedPrintCC.z).bitPattern,
            "pristine record: the solved Y IS the neutral pair")
        XCTAssertEqual(solution.exposureGain.bitPattern, Double(1.0).bitPattern,
                       "no histogram: the gain rides 2^0 = 1")
    }

    // MARK: - 2: the K calibration (gray error exactly 0)

    func testSessionOperatingPointCarriesGrayErrorZero() throws {
        let tables = try spectralTables()
        // midgrayPrintRaw = the mid-gray chain-head print raw × midgrayFactor
        // — the K calibration's measurement face. The log-channel ratios
        // must be EXACTLY zero at the solved pair (the build's Newton solve
        // converged; the RFC-028 discipline's spectral-domain form).
        let raw = tables.midgrayPrintRaw
        let ratioGY = Foundation.log(Double(raw.y > 0 ? raw.y : 1e-300))
            - Foundation.log(Double(raw.x > 0 ? raw.x : 1e-300))
        let ratioBY = Foundation.log(Double(raw.z > 0 ? raw.z : 1e-300))
            - Foundation.log(Double(raw.x > 0 ? raw.x : 1e-300))
        XCTAssertEqual(ratioGY, 0.0, accuracy: 1e-9,
                       "the G:R log ratio at the session operating point is zero")
        XCTAssertEqual(ratioBY, 0.0, accuracy: 1e-9,
                       "the B:R log ratio at the session operating point is zero")
        // The midgrayFactor is the finite geometric-mean normalization the
        // calibration baked (positive, finite — the exposure face).
        XCTAssertGreaterThan(tables.midgrayFactor, 0)
        XCTAssertTrue(tables.midgrayFactor.isFinite)
    }

    // MARK: - 3: the key shape (canonical fold + cross-core isolation)

    func testSpectralCacheKeyIsCanonicalFNVAndCrossCoreIsolated() throws {
        let pair: UInt64 = 0x1234_5678_9ABC_DEF0
        let stats: UInt64 = 0x0FED_CBA9_8765_4321
        for contentAdaptive in [false, true] {
            // The exact-value pin: the additive overload folds the same
            // three terms in the same canonical order (little-endian byte
            // face — the production fold's withUnsafeBytes order).
            var h: UInt64 = 0xCBF29CE484222325
            for shift in stride(from: 0, through: 56, by: 8) {
                h ^= (pair >> UInt64(shift)) & 0xFF
                h = h &* 0x100000001B3
            }
            for shift in stride(from: 0, through: 56, by: 8) {
                h ^= (stats >> UInt64(shift)) & 0xFF
                h = h &* 0x100000001B3
            }
            for byte in FilmRuntimeSolve.spectralModeTag(contentAdaptive: contentAdaptive).utf8 {
                h ^= UInt64(byte)
                h = h &* 0x100000001B3
            }
            XCTAssertEqual(
                FilmRuntimeSolve.cacheKey(
                    materialPairHash: pair, statsHash: stats,
                    modeTag: FilmRuntimeSolve.spectralModeTag(contentAdaptive: contentAdaptive)),
                h,
                "the spectral key IS fnv(pair ⊕ stats ⊕ tag) in the pinned fold "
                    + "order (exact-value pin, mode \(contentAdaptive))")
        }
        // The cross-core isolation: identical terms, different cores →
        // different keys (no shared slot), and the density face's own
        // exact form is untouched.
        let density = FilmRuntimeSolve.cacheKey(
            materialPairHash: pair, statsHash: stats, contentAdaptive: false)
        let spectral = FilmRuntimeSolve.cacheKey(
            materialPairHash: pair, statsHash: stats,
            modeTag: FilmRuntimeSolve.spectralModeTag(contentAdaptive: false))
        XCTAssertNotEqual(density, spectral,
                          "the spectral tags are a distinct keyspace")
        // The shared-cache no-bleed face: a spectral entry is invisible to
        // the density key and vice versa.
        let film = try portra
        let paper = try endura
        let realPair = FilmMaterialStore.materialPairHash(film: film, paper: paper)
        var record = FilmRecord()
        record.filmStock = film.info.stock ?? ""
        record.paperStock = paper.info.stock ?? ""
        let tables = try spectralTables()
        let realStats = histogram(offset: 101).statsHash
        let before = FilmSolveCache.shared.countForTesting
        _ = try FilmRuntimeSolve.solveSpectral(
            record: record, tables: tables, materialPairHash: realPair,
            histogram: histogram(offset: 101))
        let afterSpectral = FilmSolveCache.shared.countForTesting
        XCTAssertEqual(afterSpectral, before + 1,
                       "the spectral solve stored exactly one entry")
        XCTAssertNil(
            FilmSolveCache.shared.autoSolution(for: FilmRuntimeSolve.cacheKey(
                materialPairHash: realPair, statsHash: realStats,
                contentAdaptive: false)),
            "the density key must NOT see the spectral entry (no cross-core bleed)")
    }

    // MARK: - 4: the exposure consumption layer (record terms never cached)

    func testExposureEvFoldsIntoTheGainAndNeverTheCache() throws {
        let film = try portra
        let paper = try endura
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)
        let tables = try spectralTables()
        let hist = histogram(offset: 202)

        func solve(ev: Float) throws -> FilmSolveCache.Solution {
            var record = FilmRecord()
            record.filmStock = film.info.stock ?? ""
            record.paperStock = paper.info.stock ?? ""
            record.exposureEv = ev
            return try FilmRuntimeSolve.solveSpectral(
                record: record, tables: tables,
                materialPairHash: pairHash, histogram: hist)
        }

        let before = FilmSolveCache.shared.countForTesting
        let base = try solve(ev: 0)
        let afterBase = FilmSolveCache.shared.countForTesting
        let trimmed = try solve(ev: 0.25)
        let afterTrim = FilmSolveCache.shared.countForTesting

        XCTAssertEqual(afterBase, before + 1, "the first solve stores one entry")
        XCTAssertEqual(afterTrim, afterBase,
                       "the exposureEv trim must NOT store a second entry — "
                       + "the record terms are NEVER cache terms")
        XCTAssertEqual(
            trimmed.magentaCC.bitPattern, base.magentaCC.bitPattern,
            "the neutral M holds bit-identical under the exposure trim")
        XCTAssertEqual(
            trimmed.yellowCC.bitPattern, base.yellowCC.bitPattern,
            "the neutral Y holds bit-identical under the exposure trim")
        let expectedGain = base.exposureGain * Foundation.pow(2.0, 0.25)
        XCTAssertEqual(
            trimmed.exposureGain.bitPattern, expectedGain.bitPattern,
            "the trim folds into the gain exactly as × 2^ev")
    }

    // MARK: - 5: the determinism gate (the FSIM-01b face, spectral arm)

    func testSpectralSolveIsBitIdenticalAcrossCalls() throws {
        let film = try portra
        let paper = try endura
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)
        let tables = try spectralTables()
        var record = FilmRecord()
        record.filmStock = film.info.stock ?? ""
        record.paperStock = paper.info.stock ?? ""
        record.mFilterShift = 7
        record.exposureEv = 0.25
        let hist = histogram(offset: 303)
        let a = try FilmRuntimeSolve.solveSpectral(
            record: record, tables: tables, materialPairHash: pairHash, histogram: hist)
        let b = try FilmRuntimeSolve.solveSpectral(
            record: record, tables: tables, materialPairHash: pairHash, histogram: hist)
        XCTAssertEqual(a.magentaCC.bitPattern, b.magentaCC.bitPattern, "M bit-identical")
        XCTAssertEqual(a.yellowCC.bitPattern, b.yellowCC.bitPattern, "Y bit-identical")
        XCTAssertEqual(
            a.exposureGain.bitPattern, b.exposureGain.bitPattern,
            "the gain bit-identical (the FSIM-01b gate, spectral face)")
        XCTAssertEqual(a, b)
    }
}

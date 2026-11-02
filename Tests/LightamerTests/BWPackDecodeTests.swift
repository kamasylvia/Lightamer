import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// BWPackDecodeTests (v0.3.3 BW pack repair batch — IOP domain) — the three
// SPEC-02-verbatim B&W profiles (kodak_2302 / kodak_doublex / kodak_trix)
// carry two shapes the M8-1a decoder never met:
//
//   1. log_sensitivity with JSON nulls at unmeasured wavelengths (30-56 of
//      81 rows) — decode preserves them verbatim ([Float?] storage, the
//      channel_density family); the engine reads null as zero sensitivity
//      (upstream hanatos.cpp:164 `np.nan_to_num` — null → NaN → 0).
//   2. density_curves 256×5 + base_density 81×5 on doublex/2302 — the
//      per-development-time monochrome family (5 development_time entries);
//      decode normalizes to the 256×3 / 81-vector consumer face via the
//      MEDIAN column (sorted by the mid-axis response, central regime).
//
// Tri-X carries plain 256×3 curves (the no-op path) but the same null
// log_sensitivity face. The suite pins the pinned facts, not replays.
// ─────────────────────────────────────────────────────────────────────────────

final class BWPackDecodeTests: XCTestCase {

    /// `…/Lightamer/Resources/FilmProfiles/profiles` — walked from #filePath
    /// (Core tests never depend on the App bundle, KD-2).
    private static var profilesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FilmProfiles/profiles")
    }

    private static let trio = ["kodak_2302", "kodak_doublex", "kodak_trix"]

    // MARK: - 1: the trio loads with the BW identity

    func testTrioLoadsWithBWChannelModel() throws {
        for id in Self.trio {
            let profile = try FilmProfile.load(
                Self.profilesDirectory.appendingPathComponent("\(id).json"))
            XCTAssertEqual(profile.info.channelModel, "bw", id)
            XCTAssertEqual(profile.info.densitometer, "diffuse_visual", id)
            XCTAssertEqual(profile.wavelengths.count, 81, id)
            XCTAssertEqual(profile.logExposure.count, 256, id)
            XCTAssertEqual(profile.densityCurves.count, 256, id)
            for row in profile.densityCurves {
                XCTAssertEqual(row.count, 3, "\(id): normalized 256×3")
            }
            XCTAssertEqual(profile.baseDensity.count, 81, id)
        }
        // The type split (the asset set fact): trix is a REVERSAL film.
        let trix = try FilmProfile.load(
            Self.profilesDirectory.appendingPathComponent("kodak_trix.json"))
        XCTAssertEqual(trix.info.type, "positive")
    }

    // MARK: - 2: the null log-sensitivity face (verbatim + pinned counts)

    func testNullLogSensitivityDecodesVerbatimWithPinnedCounts() throws {
        // The pinned null-row counts (whole-row nulls, all 3 channels —
        // machine-surveyed from the vendored pack).
        let expectedNullRows = [
            "kodak_2302": 56, "kodak_doublex": 33, "kodak_trix": 30,
        ]
        for id in Self.trio {
            let profile = try FilmProfile.load(
                Self.profilesDirectory.appendingPathComponent("\(id).json"))
            let log = try XCTUnwrap(profile.logSensitivity, id)
            XCTAssertEqual(log.count, 81, id)
            let nullRows = log.count(where: { $0.allSatisfy { $0 == nil } })
            XCTAssertEqual(nullRows, expectedNullRows[id], "\(id) null rows")
            // No PARTIAL rows (the pack's shape fact — a partial row would
            // mean a new shape, fail loudly here).
            XCTAssertTrue(
                log.allSatisfy { row in
                    row.allSatisfy({ $0 == nil }) || row.allSatisfy({ $0 != nil })
                }, "\(id): no partial-null rows")
            // Non-null values stay in the measured band.
            for value in log.flatMap({ $0 }).compactMap({ $0 }) {
                XCTAssertTrue(value.isFinite, id)
                XCTAssertGreaterThanOrEqual(value, -20, id)
                XCTAssertLessThanOrEqual(value, 20, id)
            }
        }
    }

    // MARK: - 3: the median development column (deterministic selection)

    func testMedianDevelopmentColumnIsDeterministic() throws {
        // The mid-exposure sort puts column 2 (the central development
        // time) in the median seat for BOTH family keys on 2302; on
        // doublex the curves key agrees (col 2 = 6.5min) while the Dmin
        // key sorts column 0 (4.0min) to the median — the two keys sort
        // INDEPENDENTLY (machine-surveyed; each key's own response wins).
        let stock2302 = try FilmProfile.load(
            Self.profilesDirectory.appendingPathComponent("kodak_2302.json"))
        XCTAssertEqual(stock2302.densityCurves[128][0], 1.9514, accuracy: 1e-3,
                       "2302 curves median col = 2 (5.0min)")
        XCTAssertEqual(stock2302.baseDensity[34] ?? -1, 0.0057, accuracy: 1e-4,
                       "2302 base median col = 2 (5.0min)")
        let doublex = try FilmProfile.load(
            Self.profilesDirectory.appendingPathComponent("kodak_doublex.json"))
        XCTAssertEqual(doublex.densityCurves[128][0], 1.0957, accuracy: 1e-3,
                       "doublex curves median col = 2 (6.5min)")
        XCTAssertEqual(doublex.baseDensity[34] ?? -1, 0.2196, accuracy: 1e-4,
                       "doublex base median col = 0 (4.0min)")
        // Triplicated monochrome truth on the normalized curves.
        for profile in [stock2302, doublex] {
            for (i, row) in profile.densityCurves.enumerated() {
                XCTAssertEqual(row[0], row[1], "row \(i): c0 == c1")
                XCTAssertEqual(row[1], row[2], "row \(i): c1 == c2")
            }
        }
    }

    // MARK: - 4: the pair hash sees the normalized face

    func testPairHashFoldsTheNormalizedFace() throws {
        let store = try FilmMaterialStore(
            profilesDirectory: Self.profilesDirectory)
        let doublex = try XCTUnwrap(store.profile(id: "kodak_doublex"))
        let trix = try XCTUnwrap(store.profile(id: "kodak_trix"))
        let paper = try XCTUnwrap(store.profile(id: "kodak_endura_premier"))
        // Two different BW films against the same paper never share a
        // slot (the fold covers the normalized curves + tagged nulls).
        XCTAssertNotEqual(
            FilmMaterialStore.materialPairHash(film: doublex, paper: paper),
            FilmMaterialStore.materialPairHash(film: trix, paper: paper))
        // Deterministic across loads (the store is immutable after init;
        // a second construction hashes identically).
        let store2 = try FilmMaterialStore(
            profilesDirectory: Self.profilesDirectory)
        let doublex2 = try XCTUnwrap(store2.profile(id: "kodak_doublex"))
        XCTAssertEqual(
            FilmMaterialStore.materialPairHash(film: doublex, paper: paper),
            FilmMaterialStore.materialPairHash(film: doublex2, paper: paper))
    }
}

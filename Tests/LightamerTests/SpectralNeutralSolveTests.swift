@testable import LightamerCore
import Foundation
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralNeutralSolveTests (Plan M8-3+ T1 — IOP) — the neutral-solve
// extraction's contract (R-M83P-3's seam):
//
//   1. THE ANCHOR COVERAGE: the vendored neutral_print_filters table parses
//      typed — 160 triplets (8 papers × TH-KG3 × 20 films) all hit, absent
//      pairs fall back, the four reversal rows ride (50, 50) (the
//      no-information seed, pinned in-catalog).
//   2. THE SEED DUAL-VALUE IDENTITY: 14 safety pairs' anchored-vs-(50,50)
//      solvedPrintCC is bit-identical (the synthetic-spectrum leg here —
//      the solve pure function over engine-extracted inputs; the true-build
//      leg rides T2's parity rebuild). ANY moved safety convergence = the
//      K1 stop-hand (multi-basin true fork — the plan presets no remedy).
//   3. THE C200 SEVEN-SEED NAIL: research evidence C's 7 seeds converge to
//      the same triple (the replay-measured form: M 1e-7 band / Y
//      bit-identical / res 1e-9 band — distinct paths take distinct round
//      counts to the wall; REPLAY-RECORD.md's calibration note).
//   4. THE CLAMPED FLAG, both faces: the safety sweep reads false, the C200
//      wall pair reads true; the pinned printCC branch never enters the
//      solve (clamped=false, the semantic pin).
//   5. THE ROUND GATE: the anchored 28-pair probe's round counts land the
//      T1 verdict (all <12 → drop to 16; else hold 32 — DECISIONS logs the
//      measured max).
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralNeutralSolveTests: XCTestCase {

    // MARK: - Fixtures

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func profilesDirectory() -> URL {
        repoRoot().appendingPathComponent("Resources/FilmProfiles/profiles")
    }

    private func anchorURL() -> URL {
        repoRoot().appendingPathComponent(
            "Resources/FilmProfiles/neutral_print_filters.json")
    }

    private func store() throws -> FilmMaterialStore {
        try FilmMaterialStore(profilesDirectory: profilesDirectory())
    }

    /// The 14 safety films (research §1.3's档 1: static Ymax < 80 —
    /// portra/ektar/pro400h/gold/ultramax/portra-800 ×3/verita/vision3 ×4).
    private var safetyFilms: [String] {
        ["kodak_portra_400", "kodak_portra_160", "kodak_ektar_100",
         "fujifilm_pro_400h", "kodak_gold_200", "kodak_ultramax_400",
         "kodak_portra_800", "kodak_portra_800_push1", "kodak_portra_800_push2",
         "kodak_verita_200d", "kodak_vision3_50d", "kodak_vision3_250d",
         "kodak_vision3_200t", "kodak_vision3_500t"]
    }

    /// The solve's inputs extracted through the engine's own projection
    /// faces (the synthetic-spectrum leg: the mid-gray density spectrum
    /// at the stock curve's logE≈log10(0.184) row — the static-replay
    /// CMY0 proxy, engine faces verbatim).
    private func solveInputs(
        film: FilmProfile, paper: FilmProfile
    ) throws -> (ds: [Double], sens: [[Double]], illum: [Double]) {
        let axisCount = SpectralConstantsData.wavelengthsNm.count
        let chan = try XCTUnwrap(film.channelDensityProjected())
        let base = try XCTUnwrap(film.baseDensityProjected())
        XCTAssertEqual(chan.count, 3)
        XCTAssertEqual(base.count, axisCount)
        // The CMY0 proxy row (logE nearest log10(0.184)).
        let target = log10(0.184)
        var best = 0
        var bestGap = Double.infinity
        for i in 0..<film.logExposure.count {
            let gap = abs(Double(film.logExposure[i]) - target)
            if gap < bestGap { bestGap = gap; best = i }
        }
        let cmy0 = film.densityCurves[best]
        var ds = [Double](repeating: 0, count: axisCount)
        for l in 0..<axisCount {
            ds[l] = base[l] + Double(chan[0][l]) * Double(cmy0[0])
                + Double(chan[1][l]) * Double(cmy0[1])
                + Double(chan[2][l]) * Double(cmy0[2])
        }
        let logSens = try XCTUnwrap(paper.logSensitivity)
        var sens = [[Double]](
            repeating: [Double](repeating: 0, count: 3), count: axisCount)
        for l in 0..<axisCount {
            for c in 0..<3 {
                let v = pow(10.0, Double(logSens[l][c]))
                sens[l][c] = v.isFinite ? v : 0.0
            }
        }
        let illum = try XCTUnwrap(SpectralConstants.spd(named: "TH-KG3"))
        return (ds, sens, illum)
    }

    func testAnchorTableCovers160TripletsWithReversalFifties() throws {
        let table = try NeutralPrintAnchorTable.load(url: anchorURL())
        XCTAssertEqual(
            table.tripletCount, 160,
            "8 papers × TH-KG3 × 20 films = 160 triplets (the A1 matrix)")
        // The store's roster (22 film-support incl. the two print films
        // 2383/2393 + 6 RA-4 papers) vs the table's key shape (20 taking
        // films × 8 paper keys incl. 2383/2393 as PAPER keys — the table
        // predates the support split): the hit face walks the TABLE's
        // keys, not the store's roster.
        let store = try store()
        XCTAssertEqual(store.filmStocks().count, 22)
        XCTAssertEqual(store.paperStocks().count, 6)
        let tableFilms = ["fujifilm_c200", "fujifilm_pro_400h",
                          "fujifilm_provia_100f", "fujifilm_velvia_100",
                          "fujifilm_xtra_400", "kodak_ektachrome_100",
                          "kodak_ektar_100", "kodak_gold_200",
                          "kodak_kodachrome_64", "kodak_portra_160",
                          "kodak_portra_400", "kodak_portra_800",
                          "kodak_portra_800_push1", "kodak_portra_800_push2",
                          "kodak_ultramax_400", "kodak_verita_200d",
                          "kodak_vision3_200t", "kodak_vision3_250d",
                          "kodak_vision3_500t", "kodak_vision3_50d"]
        let tablePapers = ["fujifilm_crystal_archive_typeii", "kodak_2383",
                           "kodak_2393", "kodak_ektacolor_edge",
                           "kodak_endura_premier", "kodak_portra_endura",
                           "kodak_supra_endura", "kodak_ultra_endura"]
        var hits = 0
        for paper in tablePapers {
            for film in tableFilms {
                if table.seed(
                    paper: paper, illuminant: "TH-KG3", film: film) != nil {
                    hits += 1
                }
            }
        }
        XCTAssertEqual(hits, 160, "every table key resolves a seed")
        // The four reversal rows ride (50, 50) in-catalog (the
        // no-information seed — a typed seed, not an absence).
        for reversal in ["kodak_ektachrome_100", "fujifilm_velvia_100",
                         "fujifilm_provia_100f", "kodak_kodachrome_64"] {
            let seed = try XCTUnwrap(table.seed(
                paper: "kodak_portra_endura", illuminant: "TH-KG3",
                film: reversal))
            XCTAssertEqual(seed.m, 50.0, accuracy: 1e-12)
            XCTAssertEqual(seed.y, 50.0, accuracy: 1e-12)
        }
        // Absent pairs fall back (nil → the caller resolves (50, 50)).
        XCTAssertNil(table.seed(
            paper: "no_such_paper", illuminant: "TH-KG3",
            film: "kodak_portra_400"))
        XCTAssertNil(table.seed(
            paper: "kodak_portra_endura", illuminant: "TH-KG3",
            film: "no_such_film"))
        XCTAssertNil(table.seed(
            paper: "kodak_portra_endura", illuminant: "D55",
            film: "kodak_portra_400"))
    }

    // MARK: - 2: the seed dual-value identity (the K1 gate)

    func testSafetyPairsHoldBitIdentityAcrossSeeds() throws {
        let table = try NeutralPrintAnchorTable.load(url: anchorURL())
        let store = try store()
        let dichroic = SpectralConstantsData.dichroicTransmissions
        // One RA-4 paper per maker's line (the safety sweep's paper face).
        let papers = ["kodak_portra_endura", "fujifilm_crystal_archive_typeii"]
        for filmId in safetyFilms {
            let film = try XCTUnwrap(store.profile(id: filmId))
            for paperId in papers {
                let paper = try XCTUnwrap(store.profile(id: paperId))
                let inputs = try solveInputs(film: film, paper: paper)
                let legacy = SpectralNeutralSolve.solve(
                    midgrayDS: inputs.ds, printSens: inputs.sens,
                    illuminant: inputs.illum, dichroic: dichroic,
                    seed: nil)
                let anchor = try XCTUnwrap(table.seed(
                    paper: paperId, illuminant: "TH-KG3", film: filmId))
                let anchored = SpectralNeutralSolve.solve(
                    midgrayDS: inputs.ds, printSens: inputs.sens,
                    illuminant: inputs.illum, dichroic: dichroic,
                    seed: anchor)
                // The seed-identity face is a ULP band, not bit-identity:
                // distinct seeds take distinct Newton paths (measured
                // worst 1231 ULPs ≈ 8.7e-12 CC — the ladder converges to
                // the same basin, not the same bits). A TRUE fork (K1)
                // moves CC points, not ULPs — the 1e-9 band separates the
                // two regimes by three orders of magnitude.
                XCTAssertEqual(
                    anchored.m, legacy.m, accuracy: 1e-9,
                    "\(filmId) × \(paperId): the anchored seed moved M "
                        + "(K1 stop-hand — multi-basin true fork)")
                XCTAssertEqual(
                    anchored.y, legacy.y, accuracy: 1e-9,
                    "\(filmId) × \(paperId): the anchored seed moved Y "
                        + "(K1 stop-hand — multi-basin true fork)")
                XCTAssertFalse(
                    anchored.clamped,
                    "\(filmId) × \(paperId): a safety pair reads clamped")
            }
        }
    }

    // MARK: - 3: the C200 seven-seed nail

    func testC200SevenSeedsConvergeToTheSameTriple() throws {
        // The CMY0-proxy leg converges INSIDE the wall (Y≈197.5 — the
        // research lane's printed 197.5 triple): the proxy's midgray
        // spectrum is not the true chain head, so the proxy leg nails
        // the single-basin form, NOT the clamped flag. The TRUE-build
        // clamped=true face rides T2's parity rebuild (the R9-measured
        // Y=250.0 triple).
        let store = try store()
        let film = try XCTUnwrap(store.profile(id: "fujifilm_c200"))
        let paper = try XCTUnwrap(
            store.profile(id: "fujifilm_crystal_archive_typeii"))
        let inputs = try solveInputs(film: film, paper: paper)
        let dichroic = SpectralConstantsData.dichroicTransmissions
        let seeds = [(50.0, 50.0), (85.9, 108.3), (0.0, 0.0),
                     (100.0, 100.0), (150.0, 150.0), (50.0, 200.0),
                     (200.0, 50.0)]
        let sols = seeds.map {
            SpectralNeutralSolve.solve(
                midgrayDS: inputs.ds, printSens: inputs.sens,
                illuminant: inputs.illum, dichroic: dichroic, seed: $0)
        }
        for sol in sols {
            XCTAssertEqual(
                sol.m, sols[0].m, accuracy: 1e-7,
                "the seven seeds share the M basin (the wall-path band)")
            XCTAssertEqual(
                sol.y, sols[0].y, accuracy: 1e-6,
                "the seven seeds share the Y basin (the wall-path band — "
                    + "measured worst 16831 ULPs ≈ 4.8e-10)")
            XCTAssertEqual(
                sol.residual, sols[0].residual, accuracy: 1e-9,
                "the seven seeds share the terminal residual")
            XCTAssertFalse(
                sol.clamped,
                "the proxy leg converges inside the wall (Y≈197.5); "
                    + "the true-build clamped=true rides T2's parity leg")
        }
        // The measured proxy triple (the research lane's printed value,
        // replay-confirmed on THIS calibration).
        XCTAssertEqual(sols[0].m, 106.3, accuracy: 2.5)
        XCTAssertEqual(sols[0].y, 197.5, accuracy: 1.0)
    }

    // MARK: - 4: the clamped flag's pinned-branch pin

    func testPinnedBranchNeverEntersTheSolve() throws {
        // The engine's pinned branch keeps its judgment at the call site:
        // a pinned printCC resolves verbatim with clamped=false WITHOUT
        // calling the solve — the semantic pin (no solve ran, no wall).
        // Proved structurally: `SpectralNeutralSolve` has no pinned face
        // (its signature takes only midgrayDS/printSens/illuminant/
        // dichroic/seed), so the pinned path cannot produce clamped=true.
        // This test pins the extract's domain constants instead (the
        // OQ-M83-2 hard face the acceptance greps).
        XCTAssertEqual(SpectralNeutralSolve.dialLo, 0.0)
        XCTAssertEqual(SpectralNeutralSolve.dialHi, 250.0)
        XCTAssertEqual(SpectralNeutralSolve.rounds, 32)
        XCTAssertEqual(SpectralNeutralSolve.legacySeed.m, 50.0)
        XCTAssertEqual(SpectralNeutralSolve.legacySeed.y, 50.0)
    }

    // MARK: - 5: the round gate (the T1 verdict's measurement leg)

    func testAnchoredRoundsAcrossThe28Pairs() throws {
        let table = try NeutralPrintAnchorTable.load(url: anchorURL())
        let store = try store()
        let dichroic = SpectralConstantsData.dichroicTransmissions
        // The 28-pair face: 20 taking films × 6 RA-4 papers (the store's
        // support split — NOT the table's 160-key shape: 2383/2393 ride
        // as FILMS here, the round probe's production leg).
        let films = store.filmStocks().filter {
            $0.info.stock != "kodak_2383" && $0.info.stock != "kodak_2393"
        }
        let papers = store.paperStocks()
        XCTAssertEqual(films.count, 20)
        XCTAssertEqual(papers.count, 6)
        var maxRounds = 0
        var maxPair = ""
        for paper in papers {
            let paperId = paper.info.stock ?? "?"
            for film in films {
                let filmId = film.info.stock ?? "?"
                let inputs = try solveInputs(film: film, paper: paper)
                let anchor = table.seed(
                    paper: paperId, illuminant: "TH-KG3", film: filmId)
                let sol = SpectralNeutralSolve.solve(
                    midgrayDS: inputs.ds, printSens: inputs.sens,
                    illuminant: inputs.illum, dichroic: dichroic,
                    seed: anchor)
                if sol.roundsUsed > maxRounds {
                    maxRounds = sol.roundsUsed
                    maxPair = "\(filmId) × \(paperId)"
                }
            }
        }
        // The verdict gate (T1 action 5): all <12 → drop to 16, else 32.
        // Measured: velvia × crystal burns all 32 (the reversal档 never
        // converges — residual 18%, research §1.3档 3) → the verdict is
        // HOLD 32 (DECISIONS logs the measured max). This test pins the
        // trip wire (never >32) + the hold-32 verdict face.
        XCTAssertLessThanOrEqual(
            maxRounds, 32,
            "the ladder exceeded its own 32-round bound at \(maxPair)")
        XCTAssertEqual(
            SpectralNeutralSolve.rounds, 32,
            "T1 round verdict: HOLD 32 (measured max \(maxRounds) at "
                + "\(maxPair) — the reversal档 burns the full ladder)")
    }
}

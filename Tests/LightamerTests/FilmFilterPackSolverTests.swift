@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// FilmFilterPackSolverTests (Plan M3-3-01 T5, KD-5 — LAYERS/Core level) —
// the bake-time neutral pack solve against the REAL vendored assets:
//
//   1. SANITY BANDS (two named combos ONLY — KD-5's anti-false-failure
//      ruling: the full 160-combo table spans M 28-92 / Y 25-116 with
//      33 combos outside [40,90], so widening the surface is a false-
//      failure source). Band = the measured table value ± 10 CC:
//        portra_400 × portra_endura   (table M 51.568 / Y 52.534)
//        ektar_100  × ultra_endura    (table M 71.217 / Y 55.584)
//      The solve values themselves are pinned below (Float32 storage
//      path, DECISIONS §solver) — ±10 CC is the sanest band the table
//      justifies; M3-3-03's golden gate does NOT depend on it (the main
//      gate is the independent math recompute).
//   2. DISCRIMINATION SELF-CHECK (E3): re-solving with the wrong Magenta
//      vector k_m·[0,1,1] must throw the Y solution OUT of the band (the
//      M solution is invariant by construction — the wrong vector cannot
//      disturb the G equation). A wrong vector passing in-band = the band
//      cannot discriminate = STOP AND REPORT, never widen silently.
//   3. DETERMINISM GATE: solve twice → BIT-identical (Float bitPattern);
//      fresh disk loads of the same assets → identical solutions (no
//      load-order or instance state can leak into the math).
//   4. MONOTONE-BRACKET PRECONDITION: at zero filters the G and B
//      outputs sit BELOW the anchor (bracket lower end), the residual
//      strictly rises with each dial, and at the solved pack the three
//      outputs agree to the epsilon (the neutrality actually holds).
//   5. THE NEGATIVE-SEGMENT REFERENCE: midGrayDensities lands the
//      documented model values (curve interp + the E2 projection).
// ─────────────────────────────────────────────────────────────────────────────

final class FilmFilterPackSolverTests: XCTestCase {

    // MARK: - Paths (the #filePath walk, FilmProfileTests' convention)

    private static var profilesDirectory: URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent("Resources/FilmProfiles/profiles")
    }

    private static func loadProfile(_ name: String) throws -> FilmProfile {
        try FilmProfile.load(
            profilesDirectory.appendingPathComponent("\(name).json"))
    }

    // MARK: - 1: the two named-combo sanity bands

    func testPortraEnduraNamedComboLandsInsideTheTableBand() throws {
        let film = try Self.loadProfile("kodak_portra_400")
        let paper = try Self.loadProfile("kodak_portra_endura")
        let solution = try FilmFilterPackSolver.solveNeutralPack(
            film: film, paper: paper)
        // Band: measured table ± 10 CC (KD-5 narrow band).
        XCTAssertEqual(solution.magentaCC, 51.568, accuracy: 10.0)
        XCTAssertEqual(solution.yellowCC, 52.534, accuracy: 10.0)
        // Pinned solve values (the execution-time calibration, DECISIONS
        // §solver; tolerance = bisection-ladder ulp):
        XCTAssertEqual(solution.magentaCC, 57.9322, accuracy: 1e-4)
        XCTAssertEqual(solution.yellowCC, 49.2372, accuracy: 1e-4)
    }

    func testEktarUltraNamedComboLandsInsideTheTableBand() throws {
        let film = try Self.loadProfile("kodak_ektar_100")
        let paper = try Self.loadProfile("kodak_ultra_endura")
        let solution = try FilmFilterPackSolver.solveNeutralPack(
            film: film, paper: paper)
        XCTAssertEqual(solution.magentaCC, 71.217, accuracy: 10.0)
        XCTAssertEqual(solution.yellowCC, 55.584, accuracy: 10.0)
        XCTAssertEqual(solution.magentaCC, 63.1549, accuracy: 1e-4)
        XCTAssertEqual(solution.yellowCC, 59.1051, accuracy: 1e-4)
    }

    // MARK: - 2: the E3 discrimination self-check

    func testWrongMagentaVectorThrowsTheYellowSolutionOutOfBand() throws {
        let pairs: [(film: String, paper: String, tableY: Double)] = [
            ("kodak_portra_400", "kodak_portra_endura", 52.534),
            ("kodak_ektar_100", "kodak_ultra_endura", 55.584),
        ]
        for pair in pairs {
            let film = try Self.loadProfile(pair.film)
            let paper = try Self.loadProfile(pair.paper)
            let correct = try FilmFilterPackSolver.solveNeutralPack(
                film: film, paper: paper)
            let wrong = try FilmFilterPackSolver.solveNeutralPackWrongMagentaVector(
                film: film, paper: paper)

            // The M solution is INVARIANT (the wrong vector cannot disturb
            // the G equation — documented in KD-5).
            XCTAssertEqual(wrong.magentaCC, correct.magentaCC)
            // The Y solution falls OUT of the ±10 table band — the wrong
            // vector is discriminable (measured shift ≈ −29 / −32 CC).
            XCTAssertGreaterThan(
                abs(wrong.yellowCC - pair.tableY), 10.0,
                "\(pair.film): the wrong magenta vector must be discriminable")
        }
    }

    // MARK: - 3: the determinism gate

    func testSolveIsBitIdenticalAcrossCalls() throws {
        let film = try Self.loadProfile("kodak_portra_400")
        let paper = try Self.loadProfile("kodak_portra_endura")
        let first = try FilmFilterPackSolver.solveNeutralPack(
            film: film, paper: paper)
        let second = try FilmFilterPackSolver.solveNeutralPack(
            film: film, paper: paper)
        // BIT-identical: compared on the raw bit patterns, not ==.
        XCTAssertEqual(first.magentaCC.bitPattern, second.magentaCC.bitPattern)
        XCTAssertEqual(first.yellowCC.bitPattern, second.yellowCC.bitPattern)
    }

    func testFreshDiskLoadsSolveIdentically() throws {
        // Re-loading the same assets from disk must not move the solve
        // (no instance/load-order state in the math).
        let a = try FilmFilterPackSolver.solveNeutralPack(
            film: Self.loadProfile("kodak_ektar_100"),
            paper: Self.loadProfile("kodak_ultra_endura"))
        let b = try FilmFilterPackSolver.solveNeutralPack(
            film: Self.loadProfile("kodak_ektar_100"),
            paper: Self.loadProfile("kodak_ultra_endura"))
        XCTAssertEqual(a.magentaCC.bitPattern, b.magentaCC.bitPattern)
        XCTAssertEqual(a.yellowCC.bitPattern, b.yellowCC.bitPattern)
    }

    // MARK: - 4: the monotone-bracket precondition

    func testBracketPreconditionAndSolvedResidual() throws {
        let film = try Self.loadProfile("kodak_portra_400")
        let paper = try Self.loadProfile("kodak_portra_endura")

        // At zero filters both G and B sit below the R anchor (the
        // bracket's lower end — the negative's cast needs POSITIVE dials).
        let zero = try FilmFilterPackSolver.paperOutputs(
            paper: paper, film: film, magentaCC: 0, yellowCC: 0)
        XCTAssertLessThan(zero.g, zero.r)
        XCTAssertLessThan(zero.b, zero.g)

        // Strict monotone rise with each dial (the bisection premise).
        let mid = try FilmFilterPackSolver.paperOutputs(
            paper: paper, film: film, magentaCC: 30, yellowCC: 30)
        XCTAssertGreaterThan(mid.g, zero.g)
        XCTAssertGreaterThan(mid.b, zero.b)

        // At the solved pack the three outputs agree (neutrality holds to
        // the fixed epsilon's resolution).
        let solution = try FilmFilterPackSolver.solveNeutralPack(
            film: film, paper: paper)
        let solved = try FilmFilterPackSolver.paperOutputs(
            paper: paper, film: film,
            magentaCC: solution.magentaCC, yellowCC: solution.yellowCC)
        XCTAssertEqual(solved.g, solved.r, accuracy: 1e-9)
        XCTAssertEqual(solved.b, solved.g, accuracy: 1e-9)
    }

    // MARK: - 5: the negative-segment reference

    func testMidGrayDensitiesMatchTheDocumentedModel() throws {
        let film = try Self.loadProfile("kodak_portra_400")
        let f = try FilmFilterPackSolver.midGrayDensities(film: film)
        // curve interp at log10(0.184) + the E2 projection constants
        // (0.1945546 / 0.6023984 / 0.8150475) — the registered values.
        XCTAssertEqual(f.r, 0.489136888, accuracy: 1e-6)
        XCTAssertEqual(f.g, 0.947016837, accuracy: 1e-6)
        XCTAssertEqual(f.b, 1.272824936, accuracy: 1e-6)
    }

    func testRegisteredConstantsArePinned() {
        // The registered constant family (DECISIONS §solver): the 2:1
        // dichroic dial ratio and the fixed-ladder parameters.
        XCTAssertEqual(
            FilmFilterPackSolver.yellowExposurePerCC,
            2.0 * FilmFilterPackSolver.magentaExposurePerCC,
            accuracy: 0)
        XCTAssertEqual(FilmFilterPackSolver.magentaExposurePerCC, 0.0085)
        XCTAssertEqual(FilmFilterPackSolver.yellowExposurePerCC, 0.017)
        XCTAssertEqual(FilmFilterPackSolver.midGraySceneLinear, 0.184)
        XCTAssertEqual(FilmFilterPackSolver.ccLowerBound, 0.0)
        XCTAssertEqual(FilmFilterPackSolver.ccUpperBound, 100.0)
        XCTAssertEqual(FilmFilterPackSolver.maxIterations, 60)
        XCTAssertEqual(FilmFilterPackSolver.convergenceEpsilon, 1e-12)
    }
}

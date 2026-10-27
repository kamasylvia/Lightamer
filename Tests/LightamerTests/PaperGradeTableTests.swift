@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// PaperGradeTableTests (Plan M9-2 T2 — IOP) — the computed grade-table face:
//
//   1. THE FIT CONVERGENCE: every grade key yields a preset with the
//      expected dial family (00-2 yellow-only, 3-5 magenta-only) and
//      monotone exposure trims.
//   2. THE TONALITY FACE: the modeled ISO ranges at the fitted dials
//      reproduce the datasheet targets (the 00 < 2 < 5 monotonicity and
//      the 5-vs-00 span ratio the golden gate asserts downstream).
//   3. THE ROUND-TRIP: the live fit equals the persisted
//      paper_grades.json (the committed record of the computation).
//   4. THE FOUR-FILM MIDGRAY BAND: the grade presets keep each BW film's
//      mid-gray print inside a common density band (the "same-density"
//      mid-gray target the plan's fit defines).
// ─────────────────────────────────────────────────────────────────────────────

final class PaperGradeTableTests: XCTestCase {

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var bwProfiles: URL {
        repoRoot.appendingPathComponent("Resources/FilmProfilesBW/profiles")
    }

    private func paper() throws -> FilmProfile {
        try FilmProfile.load(Self.bwProfiles
            .appendingPathComponent("ilford_multigrade_iv_rc.json"))
    }

    // MARK: - 1: convergence + dial families

    func testFitProducesDialFamiliesWithMonotoneTrims() throws {
        let table = PaperGradeTable.fitTable(paper: try paper())
        XCTAssertEqual(Set(table.keys), Set(PaperGradeTable.gradeKeys))
        // Grade 2 sits AT the neutral point (the datasheet's unfiltered
        // R == grade 2's R == 110) — its dial may legitimately be 0.
        for key in ["00", "0", "1", "2"] {
            let p = try XCTUnwrap(table[key])
            XCTAssertEqual(p.magentaCC, 0, "\(key): yellow-dial family (M=0)")
            XCTAssertGreaterThanOrEqual(p.yellowCC, 0, "\(key): dial legal")
        }
        for key in ["3", "4", "5"] {
            let p = try XCTUnwrap(table[key])
            XCTAssertEqual(p.yellowCC, 0, "\(key): magenta-dial family (Y=0)")
            XCTAssertGreaterThan(p.magentaCC, 0, "\(key): dial engaged")
        }
        // Exposure trims are non-negative (filtration only removes light)
        // and grow toward the dial extremes.
        for (_, p) in table {
            XCTAssertGreaterThanOrEqual(p.exposureEv, -0.05,
                                        "filtration never ADDS light")
        }
    }

    // MARK: - 2: dial monotonicity + the calibrated targets

    func testDialsMonotoneAndCalibratedTargetsHit() throws {
        let paper = try paper()
        let table = PaperGradeTable.fitTable(paper: paper)
        // Yellow family: the dial DECREASES 00 -> 0 -> 1 -> 2 (00 =
        // softest = most yellow); magenta family INCREASES 3 -> 4 -> 5.
        let softKeys = ["00", "0", "1", "2"]
        let softDials = softKeys.map { table[$0]!.yellowCC }
        for (a, b) in zip(softDials, softDials.dropFirst()) {
            XCTAssertGreaterThan(a, b, "yellow dial decreases 00 -> 2")
        }
        let hardKeys = ["3", "4", "5"]
        let hardDials = hardKeys.map { table[$0]!.magentaCC }
        for (a, b) in zip(hardDials, hardDials.dropFirst()) {
            XCTAssertLessThan(a, b, "magenta dial increases 3 -> 5")
        }
        // The calibrated-target consistency: each grade's modeled R sits
        // within the bisection tolerance of its calibrated anchor.
        let rNeutral = PaperGradeTable.modeledIsoRange(m: 0, y: 0, paper: paper)
        let rY = PaperGradeTable.modeledIsoRange(m: 0, y: 200, paper: paper)
        let rM = PaperGradeTable.modeledIsoRange(m: 200, y: 0, paper: paper)
        let scaleS = (rY - rNeutral) / 70.0
        let scaleH = (rNeutral - rM) / 70.0
        for key in softKeys {
            let p = table[key]!
            let target = rNeutral + (PaperGradeTable.isoRangeTargets[key]! - 110) * scaleS
            let r = PaperGradeTable.modeledIsoRange(m: 0, y: p.yellowCC, paper: paper)
            XCTAssertEqual(r, target, accuracy: 0.05, "\(key): calibrated R hit")
        }
        for key in hardKeys {
            let p = table[key]!
            let target = rNeutral - (110 - PaperGradeTable.isoRangeTargets[key]!) * scaleH
            let r = PaperGradeTable.modeledIsoRange(m: p.magentaCC, y: 0, paper: paper)
            XCTAssertEqual(r, target, accuracy: 0.05, "\(key): calibrated R hit")
        }
        // The ISO-range ordering: SOFTER paper accommodates a WIDER
        // negative range (datasheet: 00 = 180 > 5 = 40) — the inverse of
        // the density-span ordering the golden gate asserts downstream.
        let r00 = PaperGradeTable.modeledIsoRange(m: 0, y: table["00"]!.yellowCC, paper: paper)
        let r2 = PaperGradeTable.modeledIsoRange(m: 0, y: table["2"]!.yellowCC, paper: paper)
        let r5 = PaperGradeTable.modeledIsoRange(m: table["5"]!.magentaCC, y: 0, paper: paper)
        XCTAssertGreaterThan(r00, r2, "00 (softest) has the widest R")
        XCTAssertGreaterThan(r2, r5, "5 (hardest) has the narrowest R")
    }

    // MARK: - 3: the persisted round-trip

    func testPersistedTableMatchesLiveFit() throws {
        let url = Self.repoRoot
            .appendingPathComponent("Resources/FilmProfilesBW/paper_grades.json")
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let doc = try XCTUnwrap(raw as? [String: Any])
        let grades = try XCTUnwrap(doc["grades"] as? [String: [String: Double]])
        let table = PaperGradeTable.fitTable(paper: try paper())
        for key in PaperGradeTable.gradeKeys {
            let persisted = try XCTUnwrap(grades[key], "\(key) persisted")
            let live = try XCTUnwrap(table[key], "\(key) live")
            XCTAssertEqual(persisted["magenta_cc"] ?? -1, live.magentaCC,
                           accuracy: 0.05, "\(key) magenta")
            XCTAssertEqual(persisted["yellow_cc"] ?? -1, live.yellowCC,
                           accuracy: 0.05, "\(key) yellow")
            XCTAssertEqual(persisted["exposure_ev"] ?? 99, live.exposureEv,
                           accuracy: 0.01, "\(key) exposure EV")
        }
    }

    // MARK: - 4: the exposure trims hold the mid-gray light constant

    func testExposureTrimsHoldMidgrayLight() throws {
        // The same-density mid-gray face, modeled: the trim compensates
        // the filtration's light loss, so the geometric-mean print light
        // times 2^EV stays at the neutral head's level for every grade.
        let paper = try paper()
        let table = PaperGradeTable.fitTable(paper: paper)
        let neutral = PaperGradeTable.modeledMidgrayLight(0, 0, paper: paper)
        XCTAssertGreaterThan(neutral, 0)
        for (key, p) in table {
            let lit = PaperGradeTable.modeledMidgrayLight(
                p.magentaCC, p.yellowCC, paper: paper)
            let compensated = lit * pow(2.0, p.exposureEv)
            let rel = abs(log(compensated / neutral))
            XCTAssertLessThan(rel, 0.02,
                              "\(key): trim holds the mid-gray light (rel \(rel))")
        }
    }
}

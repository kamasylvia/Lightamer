@testable import Lightamer
import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────
// SmallPoolUITests (Plan M9-4 T4, X6; acceptance-2ND M-1 repair) — the tail
// items' APP-domain gates:
//
//   (1) the XPan trio's dn arms + the CaseIterable surface + the rawValue
//       spellings (D-M9SP-6 — the autonomous enhancement's data face);
//   (2) the filmstrip rating-stars table (rating 0..5 + the extremes —
//       the model seam the row view consumes; the AX identifier ride is
//       asserted in the gui-acceptance walkthrough recipe, m9-4
//       MANIFEST);
//   (3) the Show-in-Finder doors — REAL production coupling (M-1 repair):
//       the three mounts consume `FinderReveal.revealIfPresent` (the
//       existence-guard + reveal decision path, exercised here through the
//       injected seam) and register the `FinderReveal` AX-id production
//       constants (spelled and pinned here — a mount can no longer drift
//       from these symbols). The AX-tree REACHABILITY walk itself is not
//       unit-reachable (SwiftUI context menus / NSMenu items) and stays
//       the gui-acceptance walkthrough face (m9-4 MANIFEST — DECISIONS
//       §11 declaration, merged with the stars ride).
//
// The CROP BITS round trip: the picker's N/D bits mapping lives in the
// panel's private aspectBinding; its WRITE face is exercised by the
// walkthrough (the three picker rows land the (65,24)/(11,4)/(17,6)
// bits through the SAME integer storage — zero schema impact). The dn
// arms here pin the DATA half.
// ─────────────────────────────────────────────────────────────────────────

@MainActor
final class SmallPoolUITests: XCTestCase {

    // MARK: - The XPan trio (D-M9SP-6)

    func testXPanTrioDnArmsAndSurface() {
        // The three dn arms (d ≥ n discipline) — labeled tuples are not
        // Equatable in this Swift mode; compare component-wise.
        let xpan = (dn: CropAspectPreset.ratio65x24.dn, ultra: CropAspectPreset.ratio2_75x1.dn, g617: CropAspectPreset.ratio6x17.dn)
        XCTAssertEqual(xpan.dn?.d, 65); XCTAssertEqual(xpan.dn?.n, 24)
        XCTAssertEqual(xpan.ultra?.d, 11); XCTAssertEqual(xpan.ultra?.n, 4)
        XCTAssertEqual(xpan.g617?.d, 17); XCTAssertEqual(xpan.g617?.n, 6)
        // The rawValue spellings (the persisted/lookup form).
        XCTAssertEqual(CropAspectPreset.ratio65x24.rawValue, "65:24")
        XCTAssertEqual(CropAspectPreset.ratio2_75x1.rawValue, "2.75:1")
        XCTAssertEqual(CropAspectPreset.ratio6x17.rawValue, "6:17")
        // The CaseIterable surface grew by exactly the three (7 legacy + 3).
        XCTAssertEqual(CropAspectPreset.allCases.count, 10)
        // The legacy seven keep their arms (the add-only pin).
        XCTAssertEqual(CropAspectPreset.ratio4x3.dn?.d, 4)
        XCTAssertEqual(CropAspectPreset.ratio4x3.dn?.n, 3)
        XCTAssertEqual(CropAspectPreset.ratio16x10.dn?.d, 16)
        XCTAssertEqual(CropAspectPreset.ratio16x10.dn?.n, 10)
        XCTAssertNil(CropAspectPreset.free.dn)
        XCTAssertNil(CropAspectPreset.original.dn)
    }

    // MARK: - The filmstrip stars table

    func testFilmstripRatingStarsTable() {
        XCTAssertEqual(FilmstripModel.ratingStars(0), "–")
        XCTAssertEqual(FilmstripModel.ratingStars(1), "★")
        XCTAssertEqual(FilmstripModel.ratingStars(2), "★★")
        XCTAssertEqual(FilmstripModel.ratingStars(3), "★★★")
        XCTAssertEqual(FilmstripModel.ratingStars(4), "★★★★")
        XCTAssertEqual(FilmstripModel.ratingStars(5), "★★★★★")
        // Beyond the scale clamps at five (the ratingBadge twin).
        XCTAssertEqual(FilmstripModel.ratingStars(6), "★★★★★")
        XCTAssertEqual(FilmstripModel.ratingStars(Int64.max), "★★★★★")
        // Negative ratings render the zero tier (defensive parity with
        // the grid badge).
        XCTAssertEqual(FilmstripModel.ratingStars(-1), "–")
    }

    // MARK: - The Show in Finder doors (acceptance-2ND M-1 repair)

    /// The three doors' AX identifiers ARE the production constants: the
    /// mounts register `FinderReveal.gridActionID` /
    /// `.filmstripActionID` / `.menuActionID` (single source), and this
    /// pins the spellings against those symbols — a rename in a view can
    /// no longer silently drift from the walkthrough-registered AX tree.
    /// (Reachability in the live AX tree stays the walkthrough recipe —
    /// DECISIONS §11.)
    func testFinderDoorsAccessibilityRegistration() {
        XCTAssertEqual(FinderReveal.gridActionID, "library.grid.action.finder")
        XCTAssertEqual(FinderReveal.filmstripActionID, "filmstrip.action.finder")
        XCTAssertEqual(FinderReveal.menuActionID, "menu.image.finder")
        // The three doors are distinct mounts (no cross-door collision).
        XCTAssertEqual(
            Set([FinderReveal.gridActionID, FinderReveal.filmstripActionID,
                 FinderReveal.menuActionID]).count, 3)
    }

    /// The typed degrade through the PRODUCTION seam: a missing file
    /// reveals nothing (the guard rides BEFORE the reveal — the shared
    /// decision path all three doors consume); an existing file reveals
    /// exactly once with its URL. This exercises the real
    /// `FinderReveal.revealIfPresent` guard/reveal logic with the injected
    /// seam — not a Foundation-behavior mirror.
    func testFinderExistenceGuardSemantics() throws {
        let existing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("m94-finder-seam-probe.arw")
        try Data("probe".utf8).write(to: existing)
        defer { try? FileManager.default.removeItem(at: existing) }

        var revealed: [URL] = []
        let hit = FinderReveal.revealIfPresent(
            existing.path,
            exists: { FileManager.default.fileExists(atPath: $0) },
            reveal: { revealed.append($0) })
        XCTAssertTrue(hit, "an existing file must reveal")
        XCTAssertEqual(revealed, [existing])

        revealed = []
        let missing = "/nonexistent/m9-4-probe/definitely-missing.arw"
        var revealCalls = 0
        let miss = FinderReveal.revealIfPresent(
            missing,
            exists: { _ in false },
            reveal: { _ in revealCalls += 1 })
        XCTAssertFalse(miss, "a missing file must degrade typed — no reveal")
        XCTAssertEqual(revealCalls, 0, "the guard must ride BEFORE the reveal")
        XCTAssertTrue(revealed.isEmpty)
    }
}

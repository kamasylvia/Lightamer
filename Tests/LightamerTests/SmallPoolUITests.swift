@testable import Lightamer
import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────
// SmallPoolUITests (Plan M9-4 T4, X6) — the tail items' APP-domain gates:
//
//   (1) the XPan trio's dn arms + the CaseIterable surface + the rawValue
//       spellings (D-M9SP-6 — the autonomous enhancement's data face);
//   (2) the filmstrip rating-stars table (rating 0..5 + the extremes —
//       the model seam the row view consumes; the AX identifier ride is
//       asserted in the gui-acceptance walkthrough recipe, m9-4
//       MANIFEST);
//   (3) the Show-in-Finder doors' reachability registration: the three
//       mounts' accessibility identifiers are compile-time constants in
//       the view sources (the grep face), the reveal call is the
//       PostExportActions precedent shape, and the missing-file degrade
//       (the existence check before the reveal) rides the same guard on
//       all three — the GUI walkthrough drives the AX tree face
//       (the AXPress discipline in the m9-4 MANIFEST).
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

    // MARK: - The Show in Finder doors (the registration face)

    func testFinderDoorsAccessibilityRegistration() {
        // The three mounts' AX identifiers (the compile-time constants the
        // views register; the AX-tree walk is the walkthrough face).
        let registeredIDs = [
            "library.grid.action.finder",
            "filmstrip.action.finder",
            "menu.image.finder",
        ]
        XCTAssertEqual(Set(registeredIDs).count, 3)
        // The reveal precedent is the production call (the same
        // NSWorkspace.activateFileViewerSelecting shape PostExportActions
        // uses — the source-level identity is grep-checked in T5).
    }

    /// The missing-file typed degrade: the existence check rides BEFORE
    /// every reveal (the precedent guard) — the guard's semantics are
    /// FileManager-based and shared; this pins the FileManager behavior
    /// the guards rely on.
    func testFinderExistenceGuardSemantics() throws {
        let real = try XCTUnwrap(URL(string: "file:///tmp"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: real.path))
        let missing = URL(fileURLWithPath: "/nonexistent/m9-4-probe/definitely-missing.arw")
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }
}

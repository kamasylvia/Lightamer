@testable import Lightamer
@testable import LightamerCore
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
//       the gui-acceptance walkthrough recipe (m9-4 MANIFEST — DECISIONS
//       §11 declaration, merged with the stars ride);
//   (4) the doors' RESOLVE leg (omp M-1′): the mounts pass the row's
//       three-form carrier through the ImageLinker face BEFORE the reveal
//       — the raw `images.image_path` column's kind0/1 spellings resolve
//       against the process CWD (the omp-reproduced silent no-op). The
//       test drives the EXACT production composition —
//       `LibraryThumbnailBridge.sourceURLResolver` (the host-built
//       closure) + `FinderReveal.revealIfPresent(row:)` (the shared
//       guard/reveal path) — over real fixture files, asserting the
//       RESOLVED file URL reaches the injected reveal seam for all three
//       kinds and that a stale row reveals nothing.
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

    /// The doors' resolve leg (omp M-1′): all three path kinds resolve
    /// through the PRODUCTION resolver before the reveal. kind0/1 were
    /// the silent no-op (the raw column resolved against the process
    /// CWD); now the doors hand the ImageLinker-resolved file URL to the
    /// reveal seam. Real fixture files under the temp volume — the kind1
    /// leg stats real candidates and matches the recorded volume UUID
    /// against the project's volume.
    func testFinderDoorsResolveAllThreePathKindsBeforeReveal() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "m94-finder-resolve-\(UUID().uuidString)", isDirectory: true)
        let media = root.appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(
            at: media, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let kind2File = root.appendingPathComponent("abs-DSC00012.ARW")
        let kind0File = media.appendingPathComponent("DSC00013.ARW")
        let kind1File = root.appendingPathComponent("vol-DSC00014.ARW")
        for file in [kind2File, kind0File, kind1File] {
            try Data("probe".utf8).write(to: file)
        }

        // kind1 — the linker's OWN record face over a same-volume file
        // (the firmlink reality: the /-rooted spelling for temp roots).
        let kind1 = ImageLinker.record(for: kind1File, projectDirectory: root)
        XCTAssertEqual(
            kind1.pathKind, .volumeRelative,
            "the fixture must mint the same-volume carrier")
        // kind2 — the cross-volume link import, forced through the record
        // probe seam (no second physical disk needed): the probe answers
        // the source's volume only, so the project volume reads absent →
        // the absolute branch mints (absolute path + the source UUID).
        let kind2 = ImageLinker.record(
            for: kind2File, projectDirectory: root,
            uuidProbe: { $0 == kind2File ? "cross-volume-uuid" : nil })
        XCTAssertEqual(kind2.pathKind, .absolute)

        let rows: [(row: LibraryImageRow, expected: URL)] = [
            // kind0 — the project import's Media/ form (record never
            // mints it; LibrarySchema stores it exactly this way).
            (makeFinderRow(
                imagePath: "Media/DSC00013.ARW", pathKind: 0,
                volumeUUID: nil), kind0File),
            (makeFinderRow(
                imagePath: kind1.imagePath,
                pathKind: kind1.pathKind.rawValue,
                volumeUUID: kind1.volumeUUID), kind1File),
            (makeFinderRow(
                imagePath: kind2.imagePath,
                pathKind: kind2.pathKind.rawValue,
                volumeUUID: kind2.volumeUUID), kind2File),
        ]

        // The EXACT production composition: the host-built resolver + the
        // row door. The injected reveal seam captures what Finder receives.
        let resolver = LibraryThumbnailBridge.sourceURLResolver(
            projectDirectory: root)
        let exists: (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        }
        var revealed: [URL] = []
        for (row, expected) in rows {
            revealed = []
            let hit = FinderReveal.revealIfPresent(
                row: row,
                resolve: resolver,
                exists: exists,
                reveal: { revealed.append($0) })
            XCTAssertTrue(
                hit,
                "kind \(row.pathKind) (\(row.imagePath)) must resolve and reveal")
            XCTAssertEqual(
                revealed, [expected],
                "kind \(row.pathKind) must hand the RESOLVED file URL to Finder")
        }

        // The stale face extends through the resolve: a row whose file is
        // gone resolves nil — the door reveals nothing.
        revealed = []
        let stale = makeFinderRow(
            imagePath: "Media/gone.ARW", pathKind: 0, volumeUUID: nil)
        let miss = FinderReveal.revealIfPresent(
            row: stale,
            resolve: resolver,
            exists: exists,
            reveal: { revealed.append($0) })
        XCTAssertFalse(miss, "a stale row must degrade typed — no reveal")
        XCTAssertTrue(revealed.isEmpty)
    }

    /// A row for the resolve-leg test (the internal memberwise init is
    /// @testable-visible — Core stays zero-diff).
    private func makeFinderRow(
        imagePath: String, pathKind: Int64, volumeUUID: String?
    ) -> LibraryImageRow {
        LibraryImageRow(
            id: 1, imagePath: imagePath, pathKind: pathKind,
            volumeUUID: volumeUUID,
            cameraMake: nil, cameraModel: nil, lensModel: nil, iso: nil,
            focalLength: nil, aperture: nil, exposure: nil, captureDate: nil,
            fileStem: nil, fileExt: nil, exifSearchText: nil,
            exifSearchWords: nil, rating: nil, colorLabel: nil, keywords: nil,
            filename: nil, dir: nil, flag: nil, note: nil, hasEdits: 0,
            paramsHash: nil, refCount: 0, addedTime: nil, modifiedTime: nil)
    }
}

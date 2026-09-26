@testable import Lightamer
import LightamerCore
import XCTest

/// F-11-04-1 — the export targets derivation (`ExportState.targetRelPaths`):
/// symlink-spelling tolerance + the empty-targets gate consistency.
///
/// Host finding (11-04 GUI walkthrough): a session under `/tmp` (→
/// `/private/tmp`) made the header read "0 张图" — the loaded odoc URL
/// carries the RESOLVED spelling (the scanner enumerates with a realpath'd
/// root) while the session root kept the link spelling. Foundation's
/// `resolvingSymlinksInPath` does NOT resolve the prefix link (L027), so
/// the fix matches BOTH spellings via realpath(3).
@MainActor
final class ExportTargetsTests: XCTestCase {

    func testMatchesBothSymlinkSpellingsOfTheSessionRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("f11041-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        // On macOS the temp dir's URL spelling (/var/…) differs from the
        // realpath (/private/var/…) — the two shapes this fix tolerates.
        // The image file EXISTS (a loaded odoc URL is always live, and the
        // spelling resolution needs the realpath of the file itself).
        let physical = try XCTUnwrap(physicalPath(of: root.path), "realpath failed")
        let physicalRoot = URL(fileURLWithPath: physical)
        try Data().write(to: physicalRoot.appendingPathComponent("IMG_0001.ARW"))
        let imageURL = physicalRoot.appendingPathComponent("IMG_0001.ARW")

        // Loaded URL in the PHYSICAL spelling, root in the LINK spelling
        // (the exact 11-04 walkthrough shape) → the rel path resolves.
        XCTAssertEqual(
            ExportState.targetRelPaths(selection: [], loadedImageURL: imageURL, sessionRoot: root),
            ["IMG_0001.ARW"])
        // …and the inverse shape (loaded keeps the link spelling).
        let linkImage = root.appendingPathComponent("IMG_0001.ARW")
        XCTAssertEqual(
            ExportState.targetRelPaths(
                selection: [], loadedImageURL: linkImage, sessionRoot: physicalRoot),
            ["IMG_0001.ARW"])
    }

    func testSelectionWinsAndEmptyComponentsAreDropped() {
        XCTAssertEqual(
            ExportState.targetRelPaths(
                selection: ["a.jpg", ""], loadedImageURL: nil, sessionRoot: nil),
            ["a.jpg"])
        // A whitespace-only selection IS empty (the gate stays off).
        XCTAssertEqual(
            ExportState.targetRelPaths(selection: [""], loadedImageURL: nil, sessionRoot: nil),
            [])
    }

    func testLoadedImageOutsideTheSessionYieldsNoTargets() {
        XCTAssertEqual(
            ExportState.targetRelPaths(
                selection: [],
                loadedImageURL: URL(fileURLWithPath: "/somewhere/else/IMG.jpg"),
                sessionRoot: URL(fileURLWithPath: "/sessions/day1")),
            [])
    }

    func testNilInputsYieldNoTargets() {
        XCTAssertEqual(
            ExportState.targetRelPaths(selection: [], loadedImageURL: nil, sessionRoot: nil), [])
    }

    /// realpath(3) once (the test-side twin of the production helper).
    private func physicalPath(of path: String) -> String? {
        path.withCString { cpath -> String? in
            var buffer = [CChar](repeating: 0, count: 4096)
            if realpath(cpath, &buffer) != nil {
                return String(cString: buffer)
            }
            return nil
        }
    }
}

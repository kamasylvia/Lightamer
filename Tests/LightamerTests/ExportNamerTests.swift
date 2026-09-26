import Foundation
import LightamerCore
import XCTest

/// `ExportNamer` vector table (Plan 11-01 T2, D-11-CONTEXT-4): shape
/// `<stem>[_<tag>].<ext>`, `-1/-2` collision increments, NO filesystem
/// access (the occupied set is caller-supplied).
final class ExportNamerTests: XCTestCase {

    private let dir = URL(fileURLWithPath: "/session/Output")

    private func name(
        _ stem: String, _ tag: String? = nil, _ ext: String = "jpg",
        occupied: Set<String> = []
    ) -> String {
        ExportNamer.destinationURL(
            directory: dir, stem: stem, tag: tag, ext: ext, occupiedNames: occupied
        ).lastPathComponent
    }

    // MARK: - Shape vectors

    func testBareNameWithoutTag() {
        XCTAssertEqual(name("DSC09991"), "DSC09991.jpg")
        XCTAssertEqual(name("DSC09991", nil, "tif"), "DSC09991.tif")
    }

    func testTagConcatenation() {
        XCTAssertEqual(name("DSC09991", "1200"), "DSC09991_1200.jpg")
        XCTAssertEqual(name("DSC09991", "print", "webp"), "DSC09991_print.webp")
    }

    func testURLPointsIntoDirectory() {
        let url = ExportNamer.destinationURL(
            directory: dir, stem: "a", tag: nil, ext: "png", occupiedNames: [])
        XCTAssertEqual(url.deletingLastPathComponent().path, dir.path)
        XCTAssertEqual(url.lastPathComponent, "a.png")
    }

    // MARK: - Collision increments

    func testNoCollisionKeepsBaseName() {
        XCTAssertEqual(name("photo", occupied: ["other.jpg"]), "photo.jpg")
    }

    func testSingleCollisionIncrementsTo1() {
        XCTAssertEqual(name("photo", occupied: ["photo.jpg"]), "photo-1.jpg")
    }

    func testMultiCollisionIncrementsThroughTheRun() {
        XCTAssertEqual(
            name("photo", occupied: ["photo.jpg", "photo-1.jpg"]), "photo-2.jpg")
        XCTAssertEqual(
            name("photo", occupied: ["photo.jpg", "photo-1.jpg", "photo-2.jpg"]),
            "photo-3.jpg")
    }

    func testGappedRunTakesFirstFree() {
        // The resolver takes the FIRST free increment, not max+1 semantics —
        // a deleted photo-2 keeps photo-3 from being reused only if occupied.
        XCTAssertEqual(
            name("photo", occupied: ["photo.jpg", "photo-2.jpg"]), "photo-1.jpg")
    }

    func testTaggedCollisionIncrementsAfterTag() {
        XCTAssertEqual(
            name("photo", "1200", occupied: ["photo_1200.jpg"]), "photo_1200-1.jpg")
    }

    /// The default APFS volume is case-insensitive: an occupied `Photo.JPG`
    /// must block a `photo.jpg` candidate (execution decision D7).
    func testOccupancyIsCaseInsensitive() {
        XCTAssertEqual(name("photo", occupied: ["PHOTO.JPG"]), "photo-1.jpg")
        XCTAssertEqual(
            name("photo", occupied: ["Photo.jpg", "PHOTO-1.JPG"]), "photo-2.jpg")
    }

    // MARK: - Special-character policy (execution decision D6)

    func testIllegalCharactersReplacedWithDash() {
        XCTAssertEqual(name("a/b:c"), "a-b-c.jpg")
        // "/" → "-": "100% / final" keeps its surrounding spaces verbatim.
        XCTAssertEqual(name("100% / final"), "100% - final.jpg")
    }

    func testWhitespaceTrimmed() {
        XCTAssertEqual(name("  spaced  "), "spaced.jpg")
    }

    func testEmptyStemFallsBackToUntitled() {
        XCTAssertEqual(name(""), "Untitled.jpg")
        XCTAssertEqual(name("///"), "Untitled.jpg")
        XCTAssertEqual(name("   "), "Untitled.jpg")
    }

    func testUnicodeStemPassesThrough() {
        // Conservative policy: Chinese/emoji stems are legal APFS names.
        XCTAssertEqual(name("长城日落"), "长城日落.jpg")
        XCTAssertEqual(name("🌅 shore"), "🌅 shore.jpg")
    }

    func testIllegalTagSanitizedSameWay() {
        XCTAssertEqual(name("photo", "a/b"), "photo_a-b.jpg")
    }

    func testEmptyTagTreatedAsAbsent() {
        XCTAssertEqual(name("photo", "   "), "photo.jpg")
        XCTAssertEqual(name("photo", "/"), "photo.jpg")
    }

    // MARK: - Purity (no filesystem access)

    /// A nonexistent directory path must not throw or create anything — the
    /// function is pure string/join math; 11-04 owns the mkdir/EXP-08 zone.
    func testPurityNoDirectoryRequirement() {
        let ghost = URL(fileURLWithPath: "/definitely/not/a/real/dir")
        let url = ExportNamer.destinationURL(
            directory: ghost, stem: "x", tag: nil, ext: "avif",
            occupiedNames: ["x.avif"])
        XCTAssertEqual(url.lastPathComponent, "x-1.avif")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: ghost.path),
            "the namer must not create directories")
    }
}

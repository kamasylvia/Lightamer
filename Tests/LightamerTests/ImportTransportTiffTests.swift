import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ImportTransportTiffTests (Plan M4-1-02 T6, OQ-7 — LIB bundle) — the import
// three-mode zero-special-case face over REAL TIFF bytes:
//
//   • move/copy/link transport the TIFF byte-faithfully with the `.lra`
//     riding along (the M2LIB-07 ①②③ discipline, tiff flavor);
//   • copy duplicates skip (the dedupe face on tiff bytes);
//   • link's BY-DESIGN external swap: replacing the linked file re-decodes
//     with a FRESH description (a different ICC → different primaries) and
//     a fresh `contentDedupeID` (the mtime+size legs) — the description
//     re-resolves per decode, never cached into persistence.
// ─────────────────────────────────────────────────────────────────────────────

final class ImportTransportTiffTests: XCTestCase {

    private static let fixtureDirectory: URL = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent("Tests/Fixtures/TiffRaster", isDirectory: true)
    }()

    private func fixtureBytes(_ name: String) throws -> Data {
        let url = Self.fixtureDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("fixture missing: \(name)")
        }
        return try Data(contentsOf: url)
    }

    private var root: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var service: ImportService!

    override func setUp() async throws {
        try await super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("import-tiff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        packageURL = root.appendingPathComponent("Proj.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "Proj")
        service = ImportService(store: fileStore)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        service = nil
        fileStore = nil
        packageURL = nil
        root = nil
        try await super.tearDown()
    }

    private var packageDirectory: URL {
        packageURL.deletingLastPathComponent()
    }

    private func makeFile(_ path: String, bytes: Data) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url)
        return url
    }

    private func makePlan(
        sourceFolder: URL, mode: ImportMode
    ) async throws -> ImportPlan {
        try await service.makePlan(
            sourceFolder: sourceFolder, projectDirectory: packageDirectory,
            mode: mode)
    }

    private func mediaFiles() throws -> [String] {
        let media = packageDirectory.appendingPathComponent("Media", isDirectory: true)
        guard FileManager.default.fileExists(atPath: media.path) else { return [] }
        let enumerator = FileManager.default.enumerator(
            at: media, includingPropertiesForKeys: nil)!
        var files: [String] = []
        for case let url as URL in enumerator {
            files.append(String(url.path.dropFirst(media.path.count + 1)))
        }
        return files.sorted()
    }

    // MARK: - Move (OQ-7 ①)

    func testMoveTransportsTiffBytesAndSidecarRidesAlong() async throws {
        let bytes = try fixtureBytes("srgb-matrix-8.tif")
        let tiff = try makeFile("SessionTiff/Capture/IMG0001.tif", bytes: bytes)
        try makeFile(
            "SessionTiff/Capture/IMG0001.tif.lra", bytes: Data([0x4C]))

        let plan = try await makePlan(
            sourceFolder: root.appendingPathComponent("SessionTiff", isDirectory: true),
            mode: .move)
        XCTAssertEqual(plan.items.count, 1, "the tiff family passes double-on")
        let outcome = try await service.importFolder(plan)

        XCTAssertEqual(outcome.imported, 1)
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tiff.path))
        let placed = packageDirectory.appendingPathComponent(
            "Media/SessionTiff/Capture/IMG0001.tif")
        XCTAssertTrue(FileManager.default.fileExists(atPath: placed.path))
        XCTAssertEqual(try Data(contentsOf: placed), bytes, "byte-faithful transport")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: placed.path + ".lra", isDirectory: nil), "the .lra rides along")
        // The transported bytes still DECODE through the native leg.
        let decoded = try await RAWDecoder().decode(placed)
        XCTAssertNotNil(decoded.rasterColor)
        XCTAssertNotNil(decoded.rasterNative)
    }

    // MARK: - Copy (OQ-7 ②)

    func testCopyTransportsTiffAndDuplicateSkips() async throws {
        let bytes = try fixtureBytes("p3-matrix-16.tif")
        _ = try makeFile("SessionCopy/IMG0002.tif", bytes: bytes)

        let plan = try await makePlan(
            sourceFolder: root.appendingPathComponent("SessionCopy", isDirectory: true),
            mode: .copy)
        let first = try await service.importFolder(plan)
        XCTAssertEqual(first.imported, 1)

        // The SAME bytes again (a re-import of the same source) → the
        // duplicate account skips it.
        let second = try await service.importFolder(plan)
        XCTAssertEqual(second.imported, 0, "the duplicate skips")
        XCTAssertEqual(second.skippedDuplicates, 1)
        // The placed face, direct (the enumerator's firmlink spelling
        // makes relative-prefix cuts unsound — the M2-2-1 lesson).
        let placed = packageDirectory.appendingPathComponent(
            "Media/SessionCopy/IMG0002.tif")
        XCTAssertTrue(FileManager.default.fileExists(atPath: placed.path))
        XCTAssertEqual(try Data(contentsOf: placed), bytes, "byte-faithful")
    }

    // MARK: - Link (OQ-7 ③)

    func testLinkLeavesTiffBytesInPlace() async throws {
        let bytes = try fixtureBytes("srgb-matrix-16.tif")
        let tiff = try makeFile("SessionLink/IMG0003.tif", bytes: bytes)
        try makeFile("SessionLink/IMG0003.tif.lra", bytes: Data([0x4C]))

        let plan = try await makePlan(
            sourceFolder: root.appendingPathComponent("SessionLink", isDirectory: true),
            mode: .link)
        let outcome = try await service.importFolder(plan)

        XCTAssertEqual(outcome.imported, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tiff.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tiff.path + ".lra"))
        XCTAssertEqual(try mediaFiles(), [], "no bytes land in Media/")
    }

    func testLinkExternalSwapReDecodesWithFreshDescription() async throws {
        let original = try fixtureBytes("srgb-matrix-16.tif")
        let tiff = try makeFile("SessionSwap/IMG0004.tif", bytes: original)
        _ = try await makePlan(
            sourceFolder: root.appendingPathComponent("SessionSwap", isDirectory: true),
            mode: .link)

        // The pre-swap decode: the sRGB description + this file's identity.
        let before = try await RAWDecoder().decode(tiff)
        let beforeDescription = try XCTUnwrap(before.rasterColor)

        // The BY-DESIGN external swap (OQ-7): replace the linked file in
        // place with a DIFFERENT-ICC tiff (Display P3 primaries).
        let replacement = try fixtureBytes("p3-matrix-16.tif")
        try replacement.write(to: tiff)

        // A fresh decode re-resolves the description from the FILE (never
        // from any cached face) and the dedupe identity refreshes on the
        // mtime+size legs.
        let after = try await RAWDecoder().decode(tiff)
        let afterDescription = try XCTUnwrap(after.rasterColor)
        // The parsed chromaticities carry the file's u16ICC quantization —
        // the NEAREST-LIMITING match is the semantic face.
        XCTAssertEqual(
            RasterInputStage.limitingSpace(for: afterDescription.primariesXY),
            .p3d65,
            "the swap re-parses the embedded ICC (Display P3)")
        XCTAssertNotEqual(
            RasterInputStage.limitingSpace(for: beforeDescription.primariesXY),
            RasterInputStage.limitingSpace(for: afterDescription.primariesXY))
        XCTAssertNotEqual(
            before.contentDedupeID, after.contentDedupeID,
            "the swapped file is a new content identity")
    }
}

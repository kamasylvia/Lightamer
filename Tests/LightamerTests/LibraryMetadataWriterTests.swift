import Foundation
import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibraryMetadataWriterTests (R1 mark-chain repair, 2026-10-20) — the
// library-face metadata write for the mark commands:
//
//   • the PRISTINE mint: no sidecar → the self-consistent metadata document
//     lands beside the image AND the projection row updates (the double
//     write the P1 acceptance's triple-zero criterion demands);
//   • the ROUND-TRIP preservation: an existing sidecar keeps every edit
//     field (note / instances / history) — only the mark trio mutates;
//   • the SC#2 skip: an existing-but-unreadable sidecar is never clobbered
//     (skipped + bytes unchanged + projection unchanged);
//   • the grid patch face: `LibraryGridModel.refreshRows` re-reads ONLY the
//     written ids in place (order/pagination/selection untouched).
//
// All faces run against a REAL .lalb package + REAL image files (the writer
// touches the filesystem through the same tmp-sibling promotion the
// production sidecar writers use). @MainActor class-wide: the grid patch
// face instantiates the MainActor-isolated LibraryGridModel (the
// LibraryInspectorModelTests hosting shape).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class LibraryMetadataWriterTests: XCTestCase {

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var store: LibraryStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("library-mark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("MarkProj.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "MarkProj")
        store = LibraryStore(store: fileStore)
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Fixtures

    /// A REAL image file (the writer probes/writes its sibling `.lra`).
    private func makeImageFile(named name: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try Data("fixture-bytes".utf8).write(to: url)
        return url
    }

    @discardableResult
    private func insertImage(at url: URL) async throws -> Int64 {
        try await store.insertImage(
            record: LibraryImageRecord(
                imagePath: url.path, pathKind: .absolute,
                fileStem: url.deletingPathExtension().lastPathComponent,
                fileExt: url.pathExtension,
                filename: url.lastPathComponent, dir: ""))
    }

    private func sidecarJSON(_ imageURL: URL) throws -> Data {
        try Data(
            contentsOf: LightamerSidecar.sidecarURL(for: imageURL))
    }

    // MARK: - Pristine mint + projection

    func testPristineTargetWritesSidecarAndProjection() async throws {
        let imageURL = try makeImageFile(named: "Pristine.ARW")
        let id = try await insertImage(at: imageURL)

        let outcome = try await LibraryMetadataWriter.apply(
            edits: [LibraryMetadataEdit(
                imageID: id, imageURL: imageURL,
                rating: 4, colorLabel: 2, flag: 1)],
            store: store, seed: [])

        // The sidecar truth landed with the trio.
        XCTAssertEqual(outcome.appliedImageIDs, [id])
        XCTAssertTrue(outcome.skippedImageIDs.isEmpty)
        let document = try JSONDecoder().decode(
            LightamerSidecar.self, from: try sidecarJSON(imageURL))
        XCTAssertEqual(document.rating, 4)
        XCTAssertEqual(document.colorLabel, 2)
        XCTAssertEqual(document.flag, 1)

        // The projection row mirrors it (the grid badge's read face).
        let rows = try await LibraryQueries(store: fileStore).rows(byIDs: [id])
        XCTAssertEqual(rows.first?.rating, 4)
        XCTAssertEqual(rows.first?.colorLabel, 2)
        XCTAssertEqual(rows.first?.flag, 1)
        XCTAssertNotNil(rows.first?.modifiedTime, "the mark stamps modified_time")
    }

    // MARK: - Round-trip preservation

    func testExistingSidecarRoundTripsWithOnlyTheTrioMutated() async throws {
        let imageURL = try makeImageFile(named: "Edited.ARW")
        let id = try await insertImage(at: imageURL)

        // A pre-existing document with edit state + a DIFFERENT old rating.
        let existing = LightamerSidecar(
            imageID: UUID(),
            decoderVersionUsed: "v8",
            decodeParamsHash: 123,
            instances: [],
            history: HistoryStack(),
            historyHash: 456,
            rating: 5, note: "keep-me")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(existing).write(
            to: LightamerSidecar.sidecarURL(for: imageURL))

        _ = try await LibraryMetadataWriter.apply(
            edits: [LibraryMetadataEdit(
                imageID: id, imageURL: imageURL,
                rating: nil, colorLabel: 3, flag: nil)],
            store: store, seed: [])

        let document = try JSONDecoder().decode(
            LightamerSidecar.self, from: try sidecarJSON(imageURL))
        XCTAssertEqual(document.rating, 5, "the old rating survives a color mark")
        XCTAssertEqual(document.note, "keep-me", "the edit-state fields survive")
        XCTAssertEqual(document.decodeParamsHash, 123, "decode stamp preserved")
        XCTAssertEqual(document.colorLabel, 3, "only the trio mutated")
        let rows = try await LibraryQueries(store: fileStore).rows(byIDs: [id])
        XCTAssertEqual(rows.first?.colorLabel, 3)
        XCTAssertEqual(rows.first?.rating, 5, "the projection mirrors the truth")
    }

    // MARK: - SC#2 skip

    func testUnreadableSidecarIsSkippedNeverClobbered() async throws {
        let imageURL = try makeImageFile(named: "Broken.ARW")
        let id = try await insertImage(at: imageURL)
        let sidecarURL = LightamerSidecar.sidecarURL(for: imageURL)
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: sidecarURL)

        let outcome = try await LibraryMetadataWriter.apply(
            edits: [LibraryMetadataEdit(
                imageID: id, imageURL: imageURL,
                rating: 4, colorLabel: nil, flag: nil)],
            store: store, seed: [])

        // Skipped: bytes unchanged, projection untouched.
        XCTAssertEqual(outcome.skippedImageIDs, [id])
        XCTAssertTrue(outcome.appliedImageIDs.isEmpty)
        XCTAssertEqual(try Data(contentsOf: sidecarURL), garbage)
        let rows = try await LibraryQueries(store: fileStore).rows(byIDs: [id])
        XCTAssertNil(rows.first?.rating, "the projection never moves without the truth")
    }

    // MARK: - The grid patch face

    func testRefreshRowsPatchesOnlyTheWrittenIdsInPlace() async throws {
        // Three rows in filename walk order.
        let urls = try ["A.ARW", "B.ARW", "C.ARW"].map { try makeImageFile(named: $0) }
        var ids: [Int64] = []
        for url in urls { ids.append(try await insertImage(at: url)) }

        let grid = LibraryGridModel(
            queries: LibraryQueries(store: fileStore),
            store: LibraryStore(store: fileStore))
        try await grid.reloadFirstPage()
        XCTAssertEqual(grid.rows.map(\.filename), ["A.ARW", "B.ARW", "C.ARW"])

        // The middle row is marked OUTSIDE the grid (the shell's write face)
        // and the grid patch re-reads exactly that id.
        try await store.setMetadataMarks([
            LibraryMetadataMark(
                imageID: ids[1], rating: 5, colorLabel: nil, flag: nil)
        ])
        try await grid.refreshRows(ids: [ids[1]])

        XCTAssertEqual(grid.rows.map(\.filename), ["A.ARW", "B.ARW", "C.ARW"],
                       "order untouched")
        XCTAssertNil(grid.rows[0].rating, "unmarked rows stay untouched")
        XCTAssertEqual(grid.rows[1].rating, 5, "the marked row patched in place")
        XCTAssertNil(grid.rows[2].rating)
        XCTAssertEqual(grid.selectedIDs, [], "selection untouched")
    }
}

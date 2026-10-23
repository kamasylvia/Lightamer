import Foundation
import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibraryMarkWiringTests (R3 mark-chain wiring, the r12-repairs D5 handover) —
// the production seam the R1 writer batch left unwired: the shell mark
// commands (menu + keyboard 0-5 / P / X) route through
// `workspace.pendingMarkCommand` into `LibraryMarkApplier`, which translates
// the command into `LibraryMetadataEdit`s (walk-order selection, ImageLinker
// resolution, the explicit clear channels) and drives `LibraryMetadataWriter`.
//
// Covered here, against a REAL .lalb + REAL image files (the
// LibraryMetadataWriterTests shape):
//   • the rating command end-to-end: command → sidecar truth → projection →
//     in-place grid patch (the badge face);
//   • the CLEAR faces: rating(nil) / flag(nil) nil the composed document (the
//     D5「writer 层 v1 无 clear 通道」closure — a clear is a first-class
//     write, never the untouched absence);
//   • the P/X toggle's uniform-Lr rule: ALL selected rows carrying the value
//     clears it, otherwise it sets — the toggle READ rides the grid
//     projection;
//   • the no-op guards: empty selection / no project store write nothing.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class LibraryMarkWiringTests: XCTestCase {

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var store: LibraryStore!
    private var grid: LibraryGridModel!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("library-mark-wiring-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("WiringProj.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "WiringProj")
        store = LibraryStore(store: fileStore)
        grid = LibraryGridModel(
            queries: LibraryQueries(store: fileStore),
            store: LibraryStore(store: fileStore))
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Fixtures (the LibraryMetadataWriterTests shape)

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

    /// Three rows in filename walk order, the first two selected.
    private func makeSelectedGrid() async throws -> [Int64] {
        var ids: [Int64] = []
        for name in ["A.ARW", "B.ARW", "C.ARW"] {
            ids.append(try await insertImage(at: makeImageFile(named: name)))
        }
        try await grid.reloadFirstPage()
        grid.setSelection([ids[0], ids[1]])
        return ids
    }

    private func sidecarDocument(_ imageURL: URL) throws -> LightamerSidecar {
        try JSONDecoder().decode(
            LightamerSidecar.self,
            from: Data(contentsOf: LightamerSidecar.sidecarURL(for: imageURL)))
    }

    // MARK: - The rating command end-to-end

    func testRatingCommandWritesSidecarProjectionAndPatchesGrid() async throws {
        let ids = try await makeSelectedGrid()

        await LibraryMarkApplier.apply(
            .rating(4), grid: grid, packageURL: packageURL, store: fileStore,
            inspectorModel: nil, seed: [])

        // The sidecar truth landed for BOTH selected rows (C untouched).
        for id in [ids[0], ids[1]] {
            let row = try await LibraryQueries(store: fileStore).rows(byIDs: [id]).first
            XCTAssertEqual(row?.rating, 4, "projection row \(id) mirrors the mark")
        }
        let unmarked = try await LibraryQueries(store: fileStore).rows(byIDs: [ids[2]]).first
        XCTAssertNil(unmarked?.rating, "the unselected row never moves")
        let document = try sidecarDocument(tempDirectory.appendingPathComponent("A.ARW"))
        XCTAssertEqual(document.rating, 4)

        // The in-place grid patch (the badge face): order/selection intact.
        XCTAssertEqual(grid.rows.map(\.filename), ["A.ARW", "B.ARW", "C.ARW"])
        XCTAssertEqual(grid.rows[0].rating, 4)
        XCTAssertEqual(grid.rows[1].rating, 4)
        XCTAssertNil(grid.rows[2].rating)
        XCTAssertEqual(grid.selectedIDs.count, 2, "selection untouched")
    }

    // MARK: - The clear faces (the D5 writer-clear-channel closure)

    func testRatingClearNilTheComposedDocument() async throws {
        let ids = try await makeSelectedGrid()
        // Seed a surviving rating first.
        try await store.setMetadataMarks([
            LibraryMetadataMark(imageID: ids[0], rating: 5, colorLabel: nil, flag: nil)
        ])
        try await grid.refreshRows(ids: [ids[0]])
        XCTAssertEqual(grid.rows[0].rating, 5)

        // The menu's Clear Rating (rating nil) is a first-class write.
        await LibraryMarkApplier.apply(
            .rating(nil), grid: grid, packageURL: packageURL, store: fileStore,
            inspectorModel: nil, seed: [])

        let document = try sidecarDocument(tempDirectory.appendingPathComponent("A.ARW"))
        XCTAssertNil(document.rating, "the clear nilled the composed document")
        let row = try await LibraryQueries(store: fileStore).rows(byIDs: [ids[0]]).first
        XCTAssertNil(row?.rating, "the projection mirrors the cleared truth")
        XCTAssertEqual(grid.rows[0].rating, nil, "the badge face patched to cleared")
    }

    // MARK: - The P/X toggle's uniform-Lr rule (read = the grid projection)

    func testToggleFlagClearsWhenAllSelectionCarriesAndSetsOtherwise() async throws {
        let ids = try await makeSelectedGrid()

        // Neither row carries pick(1) → the toggle SETS it on both.
        await LibraryMarkApplier.apply(
            .toggleFlag(1), grid: grid, packageURL: packageURL, store: fileStore,
            inspectorModel: nil, seed: [])
        XCTAssertEqual(grid.rows[0].flag, 1)
        XCTAssertEqual(grid.rows[1].flag, 1)
        XCTAssertNil(grid.rows[2].flag)

        // Now ALL selected rows carry it → the toggle CLEARS it on both.
        await LibraryMarkApplier.apply(
            .toggleFlag(1), grid: grid, packageURL: packageURL, store: fileStore,
            inspectorModel: nil, seed: [])
        XCTAssertNil(grid.rows[0].flag)
        XCTAssertNil(grid.rows[1].flag)
        let document = try sidecarDocument(tempDirectory.appendingPathComponent("B.ARW"))
        XCTAssertNil(document.flag, "the toggle's clear reached the sidecar truth")
        let row = try await LibraryQueries(store: fileStore).rows(byIDs: [ids[1]]).first
        XCTAssertNil(row?.flag)

        // Mixed carry (only A re-flagged, B clean) → the toggle SETS on all
        // (never clears the carrier).
        await LibraryMarkApplier.apply(
            .toggleFlag(1), grid: grid, packageURL: packageURL, store: fileStore,
            inspectorModel: nil, seed: [])
        grid.setSelection([ids[0]])
        await LibraryMarkApplier.apply(
            .toggleFlag(1), grid: grid, packageURL: packageURL, store: fileStore,
            inspectorModel: nil, seed: [])
        grid.setSelection([ids[0], ids[1]])
        await LibraryMarkApplier.apply(
            .toggleFlag(1), grid: grid, packageURL: packageURL, store: fileStore,
            inspectorModel: nil, seed: [])
        XCTAssertEqual(grid.rows[0].flag, 1)
        XCTAssertEqual(grid.rows[1].flag, 1, "the clean row joined the set")
    }

    // MARK: - The no-op guards

    func testEmptySelectionWritesNothing() async throws {
        let ids = try await makeSelectedGrid()
        grid.clearSelection()

        await LibraryMarkApplier.apply(
            .rating(5), grid: grid, packageURL: packageURL, store: fileStore,
            inspectorModel: nil, seed: [])

        for id in ids {
            let row = try await LibraryQueries(store: fileStore).rows(byIDs: [id]).first
            XCTAssertNil(row?.rating, "no selection = no writes")
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: LightamerSidecar.sidecarURL(
                    for: tempDirectory.appendingPathComponent("A.ARW")).path),
            "no selection = no sidecars minted")
    }

    func testMissingProjectStoreWritesNothing() async throws {
        let ids = try await makeSelectedGrid()

        await LibraryMarkApplier.apply(
            .rating(5), grid: grid, packageURL: nil, store: nil,
            inspectorModel: nil, seed: [])

        for id in ids {
            let row = try await LibraryQueries(store: fileStore).rows(byIDs: [id]).first
            XCTAssertNil(row?.rating, "no open project = no writes")
        }
    }
}

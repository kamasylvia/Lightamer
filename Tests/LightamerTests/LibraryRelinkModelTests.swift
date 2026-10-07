import Foundation
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibraryRelinkModelTests (Plan M2-3-2 T4, AC #6) — the batch-relink face
// over a REAL `.lalb` + real temp files:
//
//   • the two stale forms classify separately (pathMissing / volumeAbsent)
//     and healthy rows stay out of the sheet
//   • the batch loop relives rows whose name-matched file exists in the
//     picked directory, persists the rebuilt record (verifiable through the
//     query face), and marks rows whose file is absent stillStale — a
//     failing row never blocks the rest
//   • cancellation at a row boundary counts the remainder cancelled
//     (relived/stillStale/cancelled exact)
//   • the BackgroundTaskHosting leg: monotonic clamped snapshots + cancel
//     transit + the finished flag
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class LibraryRelinkModelTests: XCTestCase {

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var sourceDirectory: URL!
    private var fileStore: ProjectFileStore!
    private var queries: LibraryQueries!
    private var model: LibraryRelinkModel!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("library-relink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("Relink.lalb")
        sourceDirectory = tempDirectory.appendingPathComponent("Relinked", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory, withIntermediateDirectories: true)
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "Relink")
        queries = LibraryQueries(store: fileStore)
        model = LibraryRelinkModel()
        try await seed()
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        model = nil
        queries = nil
        fileStore = nil
        try await super.tearDown()
    }

    /// The row carrier: an absolute broken row (pathMissing), a
    /// volume-relative row with a never-mounted UUID (volumeAbsent), a
    /// healthy absolute row, and a second broken absolute row whose file
    /// never appears in the picked directory.
    private func seed() async throws {
        let sourcePath = sourceDirectory.path
        try await fileStore.withWriteBatch { handle -> Bool in
            let insert = try handle.prepare("""
                INSERT INTO images (image_path, path_kind, volume_uuid,
                    file_stem, filename, dir)
                VALUES (?, ?, ?, ?, ?, ?)
                """)
            let rows: [(String, Int64, String?, String)] = [
                ("/nonexistent/rel/MissingA.arw", 2, nil, "MissingA.arw"),
                ("Volumes/Nope/RemoteB.arw", 1, "00112233-4455-6677-8899-AABBCCDDEEFF", "RemoteB.arw"),
                (sourcePath + "/MissingC.arw", 2, nil, "MissingC.arw"),
                ("/nonexistent/rel/GoneD.arw", 2, nil, "GoneD.arw"),
            ]
            for (index, row) in rows.enumerated() {
                try insert.reset()
                try insert.bindText(1, row.0)
                try insert.bindInt(2, row.1)
                try insert.bindText(3, row.2)
                try insert.bindText(4, String(format: "DSC%05d", index))
                try insert.bindText(5, row.3)
                try insert.bindText(6, "Media")
                _ = try insert.step()
            }
            return true
        }
    }

    /// The rows in seed order (A pathMissing / B volumeAbsent / C+D stale
    /// without a source file).
    private func fetchRows() async throws -> [LibraryImageRow] {
        try await queries.searchPage(
            sort: FilterSort(key: .filename, ascending: true), limit: 10)
    }

    /// A real file the batch can relink row A (and C) onto.
    private func makeSourceFile(_ name: String) throws -> URL {
        let url = sourceDirectory.appendingPathComponent(name)
        try Data("relinked".utf8).write(to: url)
        return url
    }

    /// The REAL persistence leg (the production shape): re-point the images
    /// row at the rebuilt record through the store's write batch — a static
    /// literal with bound parameters, `changes()` pinning the row. The App
    /// layer reaches this seam only via the testable import (the production
    /// leg waits for the public Core write face — the model's D-note).
    private func makeStoreWriteLeg() -> LibraryRelinkModel.PersistLeg {
        return { [weak fileStore] imageID, record in
            guard let fileStore else {
                throw LibraryError.constraintViolation(detail: "store gone")
            }
            _ = try await fileStore.withWriteBatch { handle -> Bool in
                let update = try handle.prepare(
                    "UPDATE images SET image_path = ?, path_kind = ?,"
                        + " volume_uuid = ?, modified_time = ? WHERE id = ?")
                try update.bindText(1, record.imagePath)
                try update.bindInt(2, record.pathKind.rawValue)
                try update.bindText(3, record.volumeUUID)
                try update.bindDouble(4, Date().timeIntervalSince1970)
                try update.bindInt(5, imageID)
                _ = try update.step()
                guard handle.changes() == 1 else {
                    throw LibraryError.constraintViolation(
                        detail: "relink touched no row for id \(imageID)")
                }
                return true
            }
        }
    }

    // MARK: - The two stale forms (classification)

    func testClassifySplitsTheTwoStaleFormsAndSkipsHealthyRows() async throws {
        // Row C gets a real source file — it resolves healthy.
        _ = try makeSourceFile("MissingC.arw")
        let rows = try await fetchRows()
        XCTAssertEqual(rows.count, 4)

        let classification = LibraryRelinkModel.classify(
            rows: rows, projectDirectory: packageURL.deletingLastPathComponent())

        XCTAssertEqual(
            classification.pathMissing.map(\.filename), ["GoneD.arw", "MissingA.arw"],
            "a concrete path with the file gone = pathMissing (filename order)")
        XCTAssertEqual(
            classification.volumeAbsent.map(\.filename), ["RemoteB.arw"],
            "a never-mounted volume UUID = volumeAbsent")
        XCTAssertEqual(classification.staleCount, 3)
        XCTAssertFalse(
            classification.pathMissing.contains { $0.filename == "MissingC.arw" },
            "a row whose recorded file exists is healthy — not in the sheet")
    }

    // MARK: - The batch loop (relived / stillStale / no blocking)

    func testBatchRelivesPersistedRowsAndCountsStillStale() async throws {
        _ = try makeSourceFile("MissingA.arw")
        let rows = try await fetchRows()
        // A = has a source file; D = never appears in the picked directory.
        let batch = rows.filter { $0.filename == "MissingA.arw" || $0.filename == "GoneD.arw" }

        model.persistLeg = makeStoreWriteLeg()
        let result = await model.runBatch(
            rows: batch,
            sourceDirectory: sourceDirectory,
            projectDirectory: packageURL.deletingLastPathComponent(),
            store: fileStore,
            handle: nil)

        XCTAssertEqual(
            result,
            LibraryRelinkModel.BatchResult(relived: 1, stillStale: 1, cancelled: 0),
            "the name-matched row relives; the absent one stays stale")

        // The persisted record is visible through the query face — the row
        // now points INTO the picked directory (the firmlink-trimmed
        // volume-relative spelling on this root volume).
        try await gridAssertRowRelinked(filename: "MissingA.arw")
    }

    private func gridAssertRowRelinked(filename: String) async throws {
        let rows = try await queries.searchPage(
            sort: FilterSort(key: .filename, ascending: true), limit: 10)
        let row = try XCTUnwrap(rows.first { $0.filename == filename })
        XCTAssertNotEqual(row.imagePath, "/nonexistent/rel/MissingA.arw")
        XCTAssertTrue(row.imagePath.hasSuffix("MissingA.arw"))
        // The rebuilt record resolves (the honest relived post-check).
        let kind = try XCTUnwrap(LibrarySchema.PathKind(rawValue: row.pathKind))
        guard case .resolved = ImageLinker.resolve(
            imagePath: row.imagePath,
            pathKind: kind,
            volumeUUID: row.volumeUUID,
            projectDirectory: packageURL.deletingLastPathComponent()) else {
            XCTFail("the relinked row must resolve")
            return
        }
    }

    func testFailingRowDoesNotBlockTheRest() async throws {
        _ = try makeSourceFile("MissingA.arw")
        _ = try makeSourceFile("MissingC.arw")
        let rows = try await fetchRows()
        // C fails at the persist leg (injected throw); A relives after it.
        let batch = rows.filter { $0.filename == "MissingA.arw" || $0.filename == "MissingC.arw" }
        model.persistLeg = { id, _ in
            if id == batch.map(\.id).min() {
                throw LibraryError.constraintViolation(detail: "injected persist failure")
            }
        }

        let result = await model.runBatch(
            rows: batch,
            sourceDirectory: sourceDirectory,
            projectDirectory: packageURL.deletingLastPathComponent(),
            store: fileStore,
            handle: nil)

        XCTAssertEqual(
            result.relived, 1,
            "the row AFTER the failing one still relives")
        XCTAssertEqual(result.stillStale, 1)
    }

    // MARK: - Cancellation (the three-way exact count)

    func testCancelAtARowBoundaryCountsTheRemainderCancelled() async throws {
        _ = try makeSourceFile("MissingA.arw")
        let rows = try await fetchRows()
        let batch = rows.filter { $0.filename != "RemoteB.arw" }  // A, C, D
        XCTAssertEqual(batch.count, 3)

        // Cancel INSIDE the first row's persist: the first row still
        // processes (the boundary is checked BETWEEN rows).
        model.persistLeg = { [weak model] _, _ in
            model?.cancel()
        }

        let result = await model.runBatch(
            rows: batch,
            sourceDirectory: sourceDirectory,
            projectDirectory: packageURL.deletingLastPathComponent(),
            store: fileStore,
            handle: nil)

        XCTAssertEqual(
            result,
            LibraryRelinkModel.BatchResult(relived: 0, stillStale: 1, cancelled: 2),
            "row 1 (GoneD, filename order) processed, rows 2-3 cancelled at the boundary")
    }

    // MARK: - The BackgroundTaskHosting leg (monotonic + cancel + finish)

    func testHandleMirrorsMonotonicProgressAndCancel() async {
        let handle = RelinkTaskHandle(title: "batch") {
            // cancel transit — asserted through the snapshot copy below.
        }
        handle.apply(processed: 3, total: 10)
        XCTAssertEqual(handle.snapshot.progress, 0.3)
        handle.apply(processed: 6, total: 10)
        XCTAssertEqual(handle.snapshot.progress, 0.6)
        // A replayed/out-of-order snapshot never moves the bar backwards.
        handle.apply(processed: 2, total: 10)
        XCTAssertEqual(handle.snapshot.progress, 0.6, "the monotonic clamp")
        // Locale-independent counts (M2-3-4 T1 localized tasks_relink_counts;
        // zh renders "已处理 6 / 10" — only the numbers are contractual).
        XCTAssertTrue(handle.snapshot.detail.contains("6"))
        XCTAssertTrue(handle.snapshot.detail.contains("10"))

        await handle.cancel()
        XCTAssertEqual(handle.snapshot.progress, 0.6, "cancel keeps the floor")
        XCTAssertFalse(handle.isFinished)

        handle.finish()
        XCTAssertTrue(handle.isFinished)
    }

    func testBatchProgressThroughTheHandleIsMonotonicToFull() async throws {
        _ = try makeSourceFile("MissingA.arw")
        let rows = try await fetchRows()
        let batch = Array(rows.prefix(3))

        // The persist leg observes the snapshot the host would see at each
        // row boundary (the @Observable field read on the main actor), and
        // performs the real write.
        var seen: [Double?] = []
        let write = makeStoreWriteLeg()
        let handle = RelinkTaskHandle(title: "batch") { self.model.cancel() }
        model.persistLeg = { imageID, record in
            seen.append(handle.snapshot.progress)
            try await write(imageID, record)
        }
        let result = await model.runBatch(
            rows: batch,
            sourceDirectory: sourceDirectory,
            projectDirectory: packageURL.deletingLastPathComponent(),
            store: fileStore,
            handle: handle)

        XCTAssertEqual(result.total, 3)
        // Each row's boundary read is non-decreasing; the FINAL snapshot is
        // the full fraction (processed == total).
        XCTAssertEqual(seen.count, 3)
        let fractions = seen.compactMap { $0 }
        XCTAssertEqual(fractions, fractions.sorted(), "monotonic per row")
        XCTAssertEqual(handle.snapshot.progress, 1.0, "the final snapshot is full")
    }
}

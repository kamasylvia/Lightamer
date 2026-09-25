import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 09-01 T4 — the session index DB suite:
//
//   • schema v1 FROZEN spelling: every column (name/type/order) asserted
//     against PRAGMA table_info VERBATIM + meta + idx_images_dir + the
//     L013 decimal-TEXT hash columns + WAL/synchronous pragmas
//   • incremental sync three vectors (added / removed / mtime-drift
//     changed) with EXACT diff counts + exact row set
//   • single-transaction atomicity (mid-sync failure injections →
//     ROLLBACK → row set unchanged)
//   • future-schema refusal (v2 file against a v1 binary)
//
// Fixtures live in `FileManager.temporaryDirectory` (internal SSD — L009).
// ─────────────────────────────────────────────────────────────────────────────

final class SessionIndexStoreTests: XCTestCase {

    private var tempDirectory: URL!
    private var sessionRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("sessionindex-\(UUID().uuidString)", isDirectory: true)
        sessionRoot = tempDirectory.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionRoot, withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeStore() -> SessionIndexStore {
        SessionIndexStore(sessionRoot: sessionRoot)
    }

    private func write(_ rel: String, bytes: Int = 8, mtimeOffset: TimeInterval = 0) throws {
        let url = sessionRoot.appendingPathComponent(rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(repeating: 0xAB, count: bytes).write(to: url)
        if mtimeOffset != 0 {
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(mtimeOffset)],
                ofItemAtPath: url.path
            )
        }
    }

    private func statEntry(_ rel: String) throws -> SessionScanEntry {
        let url = sessionRoot.appendingPathComponent(rel)
        let values = try url.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        return SessionScanEntry(
            relPath: rel,
            mtime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
            size: Int64(values.fileSize ?? 0)
        )
    }

    private func page(_ entries: [SessionScanEntry], orphans: [String] = []) -> SessionScanPage {
        SessionScanPage(entries: entries, orphanSidecarRelPaths: orphans)
    }

    private func stream(of pages: [SessionScanPage]) -> AsyncStream<SessionScanPage> {
        AsyncStream { continuation in
            for p in pages {
                continuation.yield(p)
            }
            continuation.finish()
        }
    }

    // MARK: - Schema freeze

    func testSchemaV1FrozenColumnSpelling() async throws {
        let store = makeStore()
        _ = try await store.openSession(root: sessionRoot, scan: stream(of: []))

        let verification = try await store.schemaVerification()
        XCTAssertEqual(
            verification.columnNames,
            SessionIndexSchema.imagesColumns.map(\.name),
            "column ORDER is part of the freeze contract"
        )
        XCTAssertEqual(
            verification.columnTypes,
            SessionIndexSchema.imagesColumns.map(\.type),
            "column TYPES are part of the freeze contract"
        )
        XCTAssertEqual(verification.columnNames.count, 25, "v1 = 25 columns exactly")

        // L013: the two hash columns are TEXT (decimal strings), never INTEGER.
        let hashPairs = zip(verification.columnNames, verification.columnTypes).filter {
            $0.0 == "params_hash" || $0.0 == "thumb_params_hash"
        }
        XCTAssertEqual(hashPairs.count, 2)
        for pair in hashPairs {
            XCTAssertEqual(pair.1, "TEXT", "\(pair.0) must be TEXT (L013)")
        }

        XCTAssertEqual(verification.primaryKeyColumns, ["path"], "path PRIMARY KEY")
        XCTAssertEqual(
            verification.schemaVersionMeta, "1", "meta.schemaVersion stamped"
        )
        XCTAssertTrue(verification.hasDirIndex, "idx_images_dir must exist")
        XCTAssertEqual(verification.journalMode, "wal", "WAL pinned (D-09-CONTEXT-1)")
        XCTAssertEqual(
            verification.synchronous, 1, "synchronous=NORMAL (1) — never OFF"
        )

        await store.close()
    }

    func testFutureSchemaVersionRefused() async throws {
        // Hand-craft a v2-stamped database.
        let dbURL = SessionIndexSchema.databaseURL(forSessionRoot: sessionRoot)
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let handle = try SQLiteHandle(path: dbURL.path)
        try handle.exec("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
        try handle.exec(
            "INSERT INTO meta (key, value) VALUES ('schemaVersion', '99')"
        )
        handle.close()

        let store = makeStore()
        do {
            _ = try await store.openSession(root: sessionRoot, scan: stream(of: []))
            XCTFail("a v99 database must be REFUSED by a v1 binary")
        } catch let error as SessionIndexError {
            guard case .schemaFailed = error else {
                XCTFail("expected schemaFailed, got \(error)")
                return
            }
        }
        await store.close()
    }

    // MARK: - Incremental sync: three vectors

    func testIncrementalSyncThreeVectorsExact() async throws {
        try write("a.arw")
        try write("b.arw")
        try write("sub/c.arw")

        let store = makeStore()
        let first = try await store.openSession(
            root: sessionRoot,
            scan: stream(of: [
                page(try [statEntry("a.arw"), statEntry("b.arw"), statEntry("sub/c.arw")]),
            ])
        )
        XCTAssertEqual(first.added, 3)
        XCTAssertEqual(first.removed, 0)
        XCTAssertEqual(first.changed, 0)
        XCTAssertEqual(first.counts.total, 3)
        XCTAssertEqual(first.firstImageRelPath, "a.arw", "lexicographic first image")

        // Mutate the tree: add d.arw, delete a.arw, DRIFT b.arw (new mtime+size).
        try write("d.arw", bytes: 32)
        try FileManager.default.removeItem(at: sessionRoot.appendingPathComponent("a.arw"))
        try write("b.arw", bytes: 64, mtimeOffset: 3600)

        let second = try await store.openSession(
            root: sessionRoot,
            scan: stream(of: [
                page(try [statEntry("b.arw"), statEntry("sub/c.arw"), statEntry("d.arw")]),
            ])
        )
        XCTAssertEqual(second.added, 1, "d.arw added")
        XCTAssertEqual(second.removed, 1, "a.arw removed")
        XCTAssertEqual(second.changed, 1, "b.arw mtime/size drift")
        XCTAssertEqual(second.counts.total, 3)

        // Exact row set + drift effects.
        let rows = try await store.fetchAllRows()
        XCTAssertEqual(Set(rows.map(\.path)), ["b.arw", "sub/c.arw", "d.arw"])
        let drifted = rows.first { $0.path == "b.arw" }
        XCTAssertEqual(drifted?.fileSize, 64)
        XCTAssertNil(drifted?.paramsHash, "drift clears the sidecar summary (T5 re-reads)")
        XCTAssertNil(drifted?.hasEdits, "drift clears has_edits (T5 re-reads)")

        // No-op reopen: third sync must be all zeros.
        let third = try await store.openSession(
            root: sessionRoot,
            scan: stream(of: [
                page(try [statEntry("b.arw"), statEntry("sub/c.arw"), statEntry("d.arw")]),
            ])
        )
        XCTAssertEqual(third.added, 0)
        XCTAssertEqual(third.removed, 0)
        XCTAssertEqual(third.changed, 0, "identical stat triples → zero diff")

        // Epoch monotonicity.
        let verification = try await store.schemaVerification()
        XCTAssertEqual(verification.scanEpoch, 3, "one bump per open")
        await store.close()
    }

    func testOrphanRowsRideTheSameSync() async throws {
        try write("a.arw")

        let store = makeStore()
        let first = try await store.openSession(
            root: sessionRoot,
            scan: stream(of: [
                page(try [statEntry("a.arw")], orphans: ["GONE.arw.lra"]),
            ])
        )
        XCTAssertEqual(first.orphanAdded, 1)
        XCTAssertEqual(first.counts.orphans, 1)
        XCTAssertEqual(first.counts.total, 1, "orphans are NOT browse rows")

        // The orphan resolves (original reappeared): removed from the orphan
        // lane, and the ORIGINAL's own row comes in via the entries set.
        try write("GONE.arw")
        let second = try await store.openSession(
            root: sessionRoot,
            scan: stream(of: [
                page(try [statEntry("a.arw"), statEntry("GONE.arw")]),
            ])
        )
        XCTAssertEqual(second.orphanRemoved, 1)
        XCTAssertEqual(second.counts.orphans, 0)
        XCTAssertEqual(second.counts.total, 2)
        await store.close()
    }

    // MARK: - Single-transaction atomicity

    func testMidSyncFailureRollsBackEverything() async throws {
        try write("a.arw")
        try write("b.arw")
        // Capture the ORIGINAL stat triples up front — a.arw gets deleted
        // from disk below and cannot be re-stat'd.
        let originalEntries = try [statEntry("a.arw"), statEntry("b.arw")]

        let store = makeStore()
        _ = try await store.openSession(
            root: sessionRoot, scan: stream(of: [page(originalEntries)])
        )
        await store.close()

        // Mutate: one added (c.arw), one removed (a.arw) — the injected
        // failure lands mid-transaction of the NEXT open.
        try write("c.arw")
        try FileManager.default.removeItem(at: sessionRoot.appendingPathComponent("a.arw"))
        let mutatedEntries = try [statEntry("b.arw"), statEntry("c.arw")]

        for injection in [SessionIndexSyncFailureInjection.afterAdded, .beforeCommit] {
            let failingStore = makeStore()
            await failingStore.setFailureInjection(injection)
            do {
                _ = try await failingStore.openSession(
                    root: sessionRoot, scan: stream(of: [page(mutatedEntries)])
                )
                XCTFail("\(injection) injection must throw")
            } catch {
                // expected — the sync rolls back
            }
            await failingStore.close()
        }

        // Fresh store re-synced against the ORIGINAL scan — proves the two
        // failed transactions left NO partial diff behind: a.arw's row must
        // still exist (nothing was deleted), so re-adding it is a no-op.
        let originalStore = makeStore()
        let final = try await originalStore.openSession(
            root: sessionRoot, scan: stream(of: [page(originalEntries)])
        )
        XCTAssertEqual(
            final.added, 0,
            "a.arw's row must STILL EXIST (the injected removal rolled back)"
        )
        XCTAssertEqual(
            final.removed, 0,
            "c.arw's row must NOT EXIST (the injected INSERT rolled back)"
        )
        XCTAssertEqual(final.changed, 0, "the final sync vs the ORIGINAL scan is a pure no-op")
        let rows = try await originalStore.fetchAllRows()
        XCTAssertEqual(
            Set(rows.map(\.path)), ["a.arw", "b.arw"],
            "the pre-failure row set survived the two failed opens verbatim"
        )
        await originalStore.close()
    }

    // MARK: - Round-trip + close semantics

    func testReopenAfterCloseKeepsData() async throws {
        try write("x.arw")
        let store = makeStore()
        _ = try await store.openSession(
            root: sessionRoot, scan: stream(of: [page(try [statEntry("x.arw")])])
        )
        await store.close()
        let closed = await store.isClosed
        XCTAssertTrue(closed)

        let reopened = makeStore()
        _ = try await reopened.openSession(
            root: sessionRoot, scan: stream(of: [page(try [statEntry("x.arw")])])
        )
        let rows = try await reopened.fetchAllRows()
        XCTAssertEqual(rows.count, 1, "data survives close/reopen")
        XCTAssertEqual(rows.first?.path, "x.arw")
        await reopened.close()
    }

    // MARK: - L013 grep guard (build-time companion)

    func testHashColumnsAreTextInDDLSource() {
        // Runtime twin of the freeze-grep: the DDL source itself must
        // declare TEXT for both hash columns.
        XCTAssertTrue(SessionIndexSchema.createImagesTableSQL.contains("params_hash TEXT"))
        XCTAssertTrue(
            SessionIndexSchema.createImagesTableSQL.contains("thumb_params_hash TEXT")
        )
        XCTAssertFalse(
            SessionIndexSchema.createImagesTableSQL.contains("params_hash INTEGER"),
            "L013: hash columns are NEVER INTEGER"
        )
    }
}

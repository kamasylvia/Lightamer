import CoreGraphics
import ImageIO
import LightamerCore
import LightamerIOP
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

// MARK: - T5: sidecar summary backfill + EXIF light columns

extension SessionIndexStoreTests {

    /// Encode a sidecar document to the fixture's `.lra` path.
    private func writeSidecar(
        _ rel: String, document: LightamerSidecar
    ) throws -> LightamerSidecar {
        let url = sessionRoot.appendingPathComponent(rel + ".lra")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url)
        return document
    }

    private func makeSidecar(
        imageID: UUID,
        instances: [ModuleInstance],
        historyHash: UInt64,
        layers: [SidecarLayerRecord]? = nil
    ) -> LightamerSidecar {
        var stack = HistoryStack()
        for instance in instances {
            stack.commit(instance, label: "test")
        }
        if instances.isEmpty {
            stack = HistoryStack() // position stays −1 (pristine-with-sidecar)
        }
        return LightamerSidecar(
            imageID: imageID,
            decoderVersionUsed: "v8",
            decodeParamsHash: 42,
            instances: instances,
            history: stack,
            historyHash: historyHash,
            layerStack: layers.map(SidecarLayerStackRecord.init(layers:))
        )
    }

    func testSidecarSummaryRoundTripPerColumn() async throws {
        try write("DSC001.ARW")
        let imageID = UUID()
        let gain = ModuleInstance(
            module: TestGainModule.self, multiName: "t", params: .init(gain: 2.0)
        )
        let hash = HistoryHash.hash(instances: [gain], decodeParamsHash: 42)
        let document = makeSidecar(
            imageID: imageID,
            instances: [gain],
            historyHash: hash
        )
        try writeSidecar("DSC001.ARW", document: document)

        let store = makeStore()
        _ = try await store.openSession(
            root: sessionRoot, scan: stream(of: [page(try [statEntry("DSC001.ARW")])])
        )
        let rows = try await store.fetchAllRows()
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)

        // Per-column round-trip — the SIDECAR is the authority.
        XCTAssertEqual(row.imageID, imageID.uuidString)
        XCTAssertEqual(row.sidecarPresent, 1)
        XCTAssertEqual(row.hasEdits, 1, "history.position ≥ 0 (one commit)")
        XCTAssertEqual(
            row.paramsHash, String(document.historyHash),
            "params_hash == sidecar historyHash, DECIMAL TEXT, byte-for-byte (L013)"
        )
        XCTAssertNil(row.layerCount)
        XCTAssertNil(row.layerSummary)
        XCTAssertGreaterThan(row.sidecarMtime ?? 0, 0)
        await store.close()
    }

    func testLayerSummaryJSONRoundTrip() async throws {
        try write("DSC002.ARW")
        let layerA = SidecarLayerRecord(AdjustmentLayer(
            id: UUID(), name: "warm", isVisible: true, opacity: 0.8, enabled: true
        ))
        let layerB = SidecarLayerRecord(AdjustmentLayer(
            id: UUID(), name: "soft", isVisible: false, opacity: 1.0, enabled: true
        ))
        let gain = ModuleInstance(
            module: TestGainModule.self, multiName: "t", params: .init(gain: 1.5)
        )
        let document = makeSidecar(
            imageID: UUID(),
            instances: [gain],
            historyHash: HistoryHash.hash(instances: [gain], decodeParamsHash: 42),
            layers: [layerA, layerB]
        )
        try writeSidecar("DSC002.ARW", document: document)

        let store = makeStore()
        _ = try await store.openSession(
            root: sessionRoot, scan: stream(of: [page(try [statEntry("DSC002.ARW")])])
        )
        let rows = try await store.fetchAllRows()
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.layerCount, 2)

        // Decode the frozen summary JSON and verify the fields verbatim.
        let summaryData = try XCTUnwrap(row.layerSummary?.data(using: .utf8))
        struct Entry: Codable {
            var name: String
            var blend: Int
            var visible: Bool
        }
        let entries = try JSONDecoder().decode([Entry].self, from: summaryData)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].name, "warm")
        XCTAssertEqual(entries[0].visible, true)
        XCTAssertEqual(entries[0].blend, Int(layerA.blendMode))
        XCTAssertEqual(entries[1].name, "soft")
        XCTAssertEqual(entries[1].visible, false)
        await store.close()
    }

    func testPristineRowStaysNullAndUneditedSidecarHasEditsZero() async throws {
        try write("PRISTINE.ARW") // no sidecar at all
        try write("UNEDITED.ARW")
        let unedited = makeSidecar(
            imageID: UUID(), instances: [], historyHash: 12345678901234567890
        )
        try writeSidecar("UNEDITED.ARW", document: unedited) // position stays −1

        let store = makeStore()
        _ = try await store.openSession(
            root: sessionRoot, scan: stream(of: [
                page(try [statEntry("PRISTINE.ARW"), statEntry("UNEDITED.ARW")]),
            ])
        )
        let rows = try await store.fetchAllRows()
        let pristine = try XCTUnwrap(rows.first { $0.path == "PRISTINE.ARW" })
        XCTAssertNil(pristine.imageID)
        XCTAssertNil(pristine.hasEdits, "no sidecar → summary columns NULL")
        XCTAssertNil(pristine.paramsHash)
        XCTAssertEqual(pristine.sidecarPresent, 0)

        let uneditedRow = try XCTUnwrap(rows.first { $0.path == "UNEDITED.ARW" })
        XCTAssertEqual(uneditedRow.sidecarPresent, 1)
        XCTAssertEqual(uneditedRow.hasEdits, 0, "position −1 = present but UNEDITED")
        XCTAssertEqual(uneditedRow.paramsHash, "12345678901234567890")
        await store.close()
    }

    func testYiyinInstanceFlipsHasEditsAndParamsHash() async throws {
        // Phase 8 handoff-④ line assertion: borders (terminal-tail 76.0)
        // instances are ORDINARY history items — has_edits flips to 1 and
        // params_hash moves when the印框参数 changes. NO special-casing.
        try write("FRAMED.ARW")
        let bordersV1 = ModuleInstance(
            module: BordersModule.self,
            params: BordersModule.Params(
                mode: .solid(color: "#101010"), mainImageWidthRate: 85
            )
        )
        let bordersV2 = ModuleInstance(
            module: BordersModule.self,
            params: BordersModule.Params(
                mode: .solid(color: "#101010"), mainImageWidthRate: 70
            )
        )
        XCTAssertNotEqual(
            HistoryHash.hash(instances: [bordersV1], decodeParamsHash: 42),
            HistoryHash.hash(instances: [bordersV2], decodeParamsHash: 42),
            "the watermark/border param change MUST move the hash"
        )
        let docV1 = makeSidecar(
            imageID: UUID(), instances: [bordersV1],
            historyHash: HistoryHash.hash(instances: [bordersV1], decodeParamsHash: 42)
        )
        try writeSidecar("FRAMED.ARW", document: docV1)

        let store = makeStore()
        _ = try await store.openSession(
            root: sessionRoot, scan: stream(of: [page(try [statEntry("FRAMED.ARW")])])
        )
        let rows = try await store.fetchAllRows()
        var row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.hasEdits, 1, "yiyin instance ⇒ edited (handoff-④)")
        let hashV1 = row.paramsHash

        // Flip the border param → the sidecar's hash moves → the row follows.
        let docV2 = makeSidecar(
            imageID: docV1.imageID, instances: [bordersV2],
            historyHash: HistoryHash.hash(instances: [bordersV2], decodeParamsHash: 42)
        )
        try writeSidecar("FRAMED.ARW", document: docV2)
        // Touch the row into the pending class (sidecar mtime drifted).
        _ = try await store.openSession(
            root: sessionRoot, scan: stream(of: [page(try [statEntry("FRAMED.ARW")])])
        )
        let rows2 = try await store.fetchAllRows()
        row = try XCTUnwrap(rows2.first)
        XCTAssertEqual(row.hasEdits, 1)
        XCTAssertNotEqual(
            row.paramsHash, hashV1, "params_hash must track the border param"
        )
        XCTAssertEqual(row.paramsHash, String(docV2.historyHash))
        await store.close()
    }

    func testDegradedSidecarNeverHardFails() async throws {
        try write("BROKEN.ARW")
        try Data("not json at all {{{".utf8).write(
            to: sessionRoot.appendingPathComponent("BROKEN.ARW.lra")
        )
        let store = makeStore()
        // Must NOT throw.
        _ = try await store.openSession(
            root: sessionRoot, scan: stream(of: [page(try [statEntry("BROKEN.ARW")])])
        )
        let rows = try await store.fetchAllRows()
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.sidecarPresent, 1, "the file exists")
        XCTAssertNil(row.paramsHash, "degraded: summary stays in the NULL/retry class")
        let counts = try await store.counts()
        XCTAssertEqual(counts.total, 1)
        await store.close()
    }

    func testExifLightColumnsFromImageIO() async throws {
        // Real JPEG with EXIF orientation + DateTimeOriginal — written via
        // CGImageDestination, read back through the store's ImageIO leg.
        try write("EXIF.jpg")
        let width = 64, height = 32
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.5, green: 0.6, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!

        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            sessionRoot.appendingPathComponent("EXIF.jpg") as CFURL,
            "public.jpeg" as CFString, 1, nil
        ))
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: formatter.string(from: stamp),
            ],
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let store = makeStore()
        _ = try await store.openSession(
            root: sessionRoot, scan: stream(of: [page(try [statEntry("EXIF.jpg")])])
        )
        let rows = try await store.fetchAllRows()
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.orientation, 6, "EXIF orientation survives the ImageIO leg")
        XCTAssertEqual(row.width, 64)
        XCTAssertEqual(row.height, 32)
        let capture = try XCTUnwrap(row.captureDate, "DateTimeOriginal parsed")
        XCTAssertEqual(
            capture, stamp.timeIntervalSince1970, accuracy: 1.0,
            "capture_date == EXIF DateTimeOriginal (UTC-pinned parse)"
        )
        await store.close()
    }
}

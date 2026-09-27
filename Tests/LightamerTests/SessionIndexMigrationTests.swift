import Foundation
import LightamerCore
import LightamerIOP
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 12-1 T2 — the FIRST real schema migration (v1 25 cols → v2 34 cols,
// D-12-CONTEXT-1's explicit freeze-contract exception):
//
//   • hand-written v1 fixture database (the authentic 25-column DDL +
//     boundary-value rows) opens against the v2 binary
//   • post-migration: 34 columns / meta schemaVersion=2 / every OLD column
//     byte-identical / every NEW column NULL
//   • idempotence: a second migrate over migrated columns is a no-op (the
//     per-column skip path), and a re-open with a reset meta stamp re-runs
//     it harmlessly
//   • v99 REFUSAL preserved + unparsable meta stamp refuses (fail closed)
//   • MIGRATION FAILURE NEVER REWRITES THE ORIGINAL FILE: a mid-migration
//     failure ROLLS BACK (columns stay 25, data intact); a read-only file
//     refuses to open byte-untouched
//   • delete-and-rebuild parity extended to the FULL v2 column set
//     (SESS-07 gate, all 34 columns via an independent raw read)
//
// Fixtures in FileManager.temporaryDirectory (L009: never external volume).
// ─────────────────────────────────────────────────────────────────────────────

final class SessionIndexMigrationTests: XCTestCase {

    private var tempDirectory: URL!
    private var sessionRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
        sessionRoot = tempDirectory.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - The authentic v1 DDL (Plan 09-01, 25 columns IN ORDER)

    static let v1CreateImagesSQL = """
        CREATE TABLE IF NOT EXISTS images (
          path TEXT PRIMARY KEY,
          dir TEXT,
          filename TEXT,
          file_size INTEGER,
          file_mtime REAL,
          scan_epoch INTEGER,
          imageID TEXT,
          sidecar_present INTEGER,
          sidecar_mtime REAL,
          has_edits INTEGER,
          params_hash TEXT,
          layer_count INTEGER,
          layer_summary TEXT,
          orientation INTEGER,
          width INTEGER,
          height INTEGER,
          capture_date REAL,
          thumb_state INTEGER,
          thumb_path TEXT,
          thumb_params_hash TEXT,
          rating INTEGER,
          color_label INTEGER,
          keywords TEXT,
          orphan_sidecar INTEGER,
          dirty INTEGER DEFAULT 0
        )
        """

    /// The nine v2 tail columns (the migration's target set).
    static let v2NewColumns: [(String, String)] = [
        ("flag", "INTEGER"), ("note", "TEXT"),
        ("camera_make", "TEXT"), ("camera_model", "TEXT"), ("lens_model", "TEXT"),
        ("iso", "INTEGER"), ("focal_length", "REAL"), ("aperture", "REAL"),
        ("exposure", "REAL"),
    ]

    static let v1Columns: [String] = [
        "path", "dir", "filename", "file_size", "file_mtime", "scan_epoch",
        "imageID", "sidecar_present", "sidecar_mtime", "has_edits",
        "params_hash", "layer_count", "layer_summary", "orientation",
        "width", "height", "capture_date", "thumb_state", "thumb_path",
        "thumb_params_hash", "rating", "color_label", "keywords",
        "orphan_sidecar", "dirty",
    ]

    /// Fixture row values — the scan stream must REPLAY these exact stats
    /// so the open sync's changed-leg skips the rows (byte-identical read).
    static let fixturePathA = "a.arw"
    static let fixtureMtimeA = -12_345.678
    static let fixtureSizeA: Int64 = 9_223_372_036_854_775_000
    static let fixtureOrphan = "b.orphan.lra"

    /// Write a v1 database with boundary-value rows (ints at range edges,
    /// negative doubles, NULLs, empty strings, decimal-TEXT hashes).
    /// `withMeta = false` omits the meta table (the mid-migration failure
    /// fixture).
    @discardableResult
    private func writeV1Fixture(withMeta: Bool = true) throws -> URL {
        let dbURL = SessionIndexSchema.databaseURL(forSessionRoot: sessionRoot)
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let handle = try SQLiteHandle(path: dbURL.path)
        try handle.exec(Self.v1CreateImagesSQL)
        if withMeta {
            try handle.exec(
                "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)")
            try handle.exec("INSERT INTO meta (key, value) VALUES ('schemaVersion', '1')")
        }

        // Row 1: fully populated (boundary values: max-ish int, negative
        // double, empty string, decimal-TEXT hash).
        try handle.exec("""
            INSERT INTO images (
              path, dir, filename, file_size, file_mtime, scan_epoch,
              imageID, sidecar_present, sidecar_mtime, has_edits,
              params_hash, layer_count, layer_summary, orientation,
              width, height, capture_date, thumb_state, thumb_path,
              thumb_params_hash, rating, color_label, keywords,
              orphan_sidecar, dirty
            ) VALUES (
              'a.arw', '.', 'a.arw', 9223372036854775000, -12345.678, 7,
              'AAAAAAAA-BBBB-CCCC-DDDD-00000000000A', 1, 1770000000.125, 1,
              '1311768467463790320', 2, '[{"blend":0,"name":"L1","visible":true}]', 6,
              8192, 5464, 1770000000.5, 2, '/tmp/thumb-a.jpg',
              '98765432109876543210', 5, 3, 'Nature|Flower',
              0, 0
            )
            """)
        // Row 2: NULLs everywhere optional + empty-string text.
        try handle.exec("""
            INSERT INTO images (path, filename, scan_epoch, keywords, orphan_sidecar, dirty)
            VALUES ('b.orphan.lra', 'b.orphan.lra', 7, '', 1, 0)
            """)
        handle.close()
        return dbURL
    }

    /// The synthetic scan replaying the fixture stats (changed-leg skip —
    /// the rows survive the open sync untouched).
    private func fixtureScan() -> AsyncStream<SessionScanPage> {
        let page = SessionScanPage(
            entries: [
                SessionScanEntry(
                    relPath: Self.fixturePathA,
                    mtime: Self.fixtureMtimeA,
                    size: Self.fixtureSizeA),
            ],
            orphanSidecarRelPaths: [Self.fixtureOrphan])
        return AsyncStream { continuation in
            continuation.yield(page)
            continuation.finish()
        }
    }

    /// Raw full read of the images table through an independent handle
    /// (column order per `PRAGMA table_info`) — decoupled from the store's
    /// row projection.
    private func rawRows(_ dbURL: URL) throws -> (names: [String], rows: [[String?]]) {
        let handle = try SQLiteHandle(path: dbURL.path)
        var names: [String] = []
        let info = try handle.prepare("PRAGMA table_info(images)")
        while try info.step() {
            names.append(info.columnText(1) ?? "")
        }
        let statement = try handle.prepare("SELECT * FROM images ORDER BY path")
        var rows: [[String?]] = []
        while try statement.step() {
            rows.append((0..<names.count).map { statement.columnText(Int32($0)) })
        }
        handle.close()
        return (names, rows)
    }

    private func columnNames(_ dbURL: URL) throws -> [(String, String)] {
        let handle = try SQLiteHandle(path: dbURL.path)
        var names: [(String, String)] = []
        let info = try handle.prepare("PRAGMA table_info(images)")
        while try info.step() {
            names.append((info.columnText(1) ?? "", info.columnText(2) ?? ""))
        }
        handle.close()
        return names
    }

    private func metaVersion(_ dbURL: URL) throws -> String? {
        let handle = try SQLiteHandle(path: dbURL.path)
        let statement = try handle.prepare(
            "SELECT value FROM meta WHERE key = 'schemaVersion'")
        let value = try statement.step() ? statement.columnText(0) : nil
        handle.close()
        return value
    }

    // MARK: - v1 → v2 happy path

    func testV1FixtureMigratesToV2WithOldRowsIntact() async throws {
        let dbURL = try writeV1Fixture()
        let before = try rawRows(dbURL)
        XCTAssertEqual(before.rows.count, 2)
        XCTAssertEqual(before.names, Self.v1Columns)

        let store = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await store.openSession(root: sessionRoot, scan: fixtureScan())

        // 34 columns in the FROZEN v2 order; meta stamped 2.
        XCTAssertEqual(
            try columnNames(dbURL).map(\.0),
            SessionIndexSchema.imagesColumns.map(\.name))
        XCTAssertEqual(
            try columnNames(dbURL).map(\.1),
            SessionIndexSchema.imagesColumns.map(\.type))
        XCTAssertEqual(try columnNames(dbURL).count, 34)
        XCTAssertEqual(try metaVersion(dbURL), "2")

        // Every OLD column of every row is BYTE-identical (the ALTER-only
        // red line); every NEW column is NULL. The synthetic scan replays
        // the fixture stats, so the sync's diff is a no-op and the rows
        // survive untouched.
        let after = try rawRows(dbURL)
        XCTAssertEqual(after.rows.count, before.rows.count)
        let nameList = after.names
        for (rowIndex, oldRow) in before.rows.enumerated() {
            let newRow = after.rows[rowIndex]
            for (columnIndex, name) in nameList.enumerated() {
                if Self.v1Columns.contains(name) {
                    XCTAssertEqual(
                        newRow[columnIndex], oldRow[columnIndex],
                        "old column \(name) must survive migration byte-identical")
                } else {
                    XCTAssertNil(
                        newRow[columnIndex],
                        "new column \(name) must start NULL")
                }
            }
        }
        await store.close()
    }

    // MARK: - Idempotence

    /// A second migrate over ALREADY-migrated columns is a no-op: the
    /// per-column skip path runs, nothing throws, values stay.
    func testMigrateIsIdempotentPerColumn() async throws {
        let dbURL = try writeV1Fixture()
        let store = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await store.openSession(root: sessionRoot, scan: fixtureScan())
        let once = try rawRows(dbURL)
        await store.close()

        // The skip path: every column exists → no ALTER executes.
        let handle = try SQLiteHandle(path: dbURL.path)
        try SessionIndexSchema.migrate(from: 1, to: 2, on: handle)
        handle.close()

        let again = try rawRows(dbURL)
        XCTAssertEqual(again.rows, once.rows)
        XCTAssertEqual(try columnNames(dbURL).count, 34)
    }

    /// A re-open with the meta stamp reset to 1 re-runs the migration
    /// (the crash-during-stamp shape) — again a no-op on real data.
    func testReopenWithResetStampReMigratesHarmlessly() async throws {
        let dbURL = try writeV1Fixture()
        let store = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await store.openSession(root: sessionRoot, scan: fixtureScan())
        let once = try rawRows(dbURL)
        await store.close()

        // Reset the stamp: the next open takes the `1 → migrate` branch
        // again (every column present → skips → re-stamps).
        let handle = try SQLiteHandle(path: dbURL.path)
        try handle.exec("UPDATE meta SET value='1' WHERE key='schemaVersion'")
        handle.close()

        let store2 = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await store2.openSession(root: sessionRoot, scan: fixtureScan())
        XCTAssertEqual(try metaVersion(dbURL), "2")
        XCTAssertEqual(try rawRows(dbURL).rows, once.rows)
        XCTAssertEqual(try columnNames(dbURL).count, 34)
        await store2.close()
    }

    // MARK: - Refusals preserved

    func testV99DatabaseStillRefusedAndUnchanged() async throws {
        let dbURL = try writeV1Fixture()
        // Stamp a FUTURE version (the "newer binary wrote this" shape).
        let handle = try SQLiteHandle(path: dbURL.path)
        try handle.exec("UPDATE meta SET value='99' WHERE key='schemaVersion'")
        handle.close()
        let beforeRows = try rawRows(dbURL)

        let store = SessionIndexStore(sessionRoot: sessionRoot)
        do {
            _ = try await store.openSession(root: sessionRoot, scan: fixtureScan())
            XCTFail("v99 must be refused by the v2 binary")
        } catch let error as SessionIndexError {
            guard case .schemaFailed = error else {
                XCTFail("expected schemaFailed, got \(error)")
                return
            }
        }
        await store.close()
        // DATA-level preservation is the red line: the refused library
        // keeps its 25-column schema, every row byte-identical, and the
        // meta stamp untouched. (Raw BYTES may shift: the frozen open
        // order runs the WAL/index DDL before the version check — 09-01
        // behavior, preserved; the refusal never rewrites user data.)
        let after = try rawRows(dbURL)
        XCTAssertEqual(after.names, beforeRows.names, "schema stays v1")
        XCTAssertEqual(after.rows, beforeRows.rows, "rows byte-identical")
        XCTAssertEqual(try metaVersion(dbURL), "99")
    }

    func testUnparsableMetaStampRefuses() async throws {
        let dbURL = try writeV1Fixture()
        let handle = try SQLiteHandle(path: dbURL.path)
        try handle.exec("UPDATE meta SET value='not-a-version' WHERE key='schemaVersion'")
        handle.close()

        let store = SessionIndexStore(sessionRoot: sessionRoot)
        do {
            _ = try await store.openSession(root: sessionRoot, scan: fixtureScan())
            XCTFail("an unparsable stamp must refuse (fail closed)")
        } catch let error as SessionIndexError {
            guard case .schemaFailed = error else {
                XCTFail("expected schemaFailed, got \(error)")
                return
            }
        }
        await store.close()
    }

    // MARK: - Failed migration never rewrites the file

    /// A MID-MIGRATION failure rolls the whole transaction back: the meta
    /// stamp UPDATE fails (no meta table), so the ALTERs revert — the
    /// database keeps its 25 columns and every row, byte-identical.
    func testMidMigrationFailureRollsBackToV1() async throws {
        let dbURL = try writeV1Fixture(withMeta: false)
        let before = try rawRows(dbURL)
        XCTAssertEqual(before.names.count, 25)

        let handle = try SQLiteHandle(path: dbURL.path)
        do {
            try SessionIndexSchema.migrate(from: 1, to: 2, on: handle)
            XCTFail("the stamp UPDATE must fail without a meta table")
        } catch {
            // expected — the ROLLBACK is the assertion's subject
        }
        handle.close()

        let after = try rawRows(dbURL)
        XCTAssertEqual(after.names, Self.v1Columns, "the ALTERs must roll back")
        XCTAssertEqual(after.rows, before.rows, "the rows must be byte-untouched")
    }

    /// A read-only database file refuses to open and its bytes stay
    /// IDENTICAL — the destructive red line at the open gate.
    func testReadOnlyDatabaseRefusesOpenByteUntouched() async throws {
        let dbURL = try writeV1Fixture()
        let before = try Data(contentsOf: dbURL)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o444], ofItemAtPath: dbURL.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644], ofItemAtPath: dbURL.path)
        }

        let store = SessionIndexStore(sessionRoot: sessionRoot)
        var threw = false
        do {
            _ = try await store.openSession(root: sessionRoot, scan: fixtureScan())
        } catch {
            threw = true
        }
        XCTAssertTrue(threw, "a read-only database must refuse to open")
        await store.close()

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: dbURL.path)
        XCTAssertEqual(
            try Data(contentsOf: dbURL), before,
            "the original database file must be byte-untouched")
        XCTAssertEqual(try metaVersion(dbURL), "1", "still an unmigrated v1 library")
    }

    // MARK: - Delete-and-rebuild parity (SESS-07 gate, all 34 columns)

    /// Delete the index → reopen → the rebuilt rows equal the first-open
    /// rows on EVERY v2 column (except scan_epoch, which legitimately
    /// bumps). The metadata columns re-derive from the sidecar truth
    /// (assertions tightened in T3 when the five-column backfill lands).
    func testDeleteAndRebuildParityAcrossAllV2Columns() async throws {
        // Fixture: one edited+metadata sidecar, one pristine, one orphan.
        let edited = sessionRoot.appendingPathComponent("one.arw")
        try Data(repeating: 0xAB, count: 16).write(to: edited)
        var history = HistoryStack()
        history.commit(
            ModuleInstance(
                module: ExposureModule.self, multiName: "e0",
                params: ExposureModule.Params(exposure: 0.7)),
            label: "exposure")
        let document = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8", decodeParamsHash: 77,
            instances: history.effectiveInstances(), history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: 77),
            appVersion: "parity", layerStack: nil,
            rating: 4, flag: 1, colorLabel: 2,
            keywords: ["Nature|Flower", "Street"], note: "keeper")
        try JSONEncoder().encode(document).write(
            to: LightamerSidecar.sidecarURL(for: edited))

        let pristine = sessionRoot.appendingPathComponent("two.arw")
        try Data(repeating: 0xCD, count: 16).write(to: pristine)
        try Data(repeating: 0xEF, count: 8).write(
            to: sessionRoot.appendingPathComponent("three.orphan.lra"))

        var page = SessionScanPage()
        for rel in ["one.arw", "two.arw"] {
            let values = try sessionRoot.appendingPathComponent(rel).resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey])
            page.entries.append(SessionScanEntry(
                relPath: rel,
                mtime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
                size: Int64(values.fileSize ?? 0)))
        }
        page.orphanSidecarRelPaths = ["three.orphan.lra"]
        // A fresh stream per open — AsyncStream is single-consumption.
        func makeScan() -> AsyncStream<SessionScanPage> {
            AsyncStream { continuation in
                continuation.yield(page)
                continuation.finish()
            }
        }

        let dbURL = SessionIndexSchema.databaseURL(forSessionRoot: sessionRoot)

        // ── First open on a FRESH v2 database (the no-migration path).
        let storeA = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await storeA.openSession(root: sessionRoot, scan: makeScan())
        let firstRows = try rawRows(dbURL)
        await storeA.close()

        // ── Delete the index (incl. WAL sidecars); rebuild.
        try FileManager.default.removeItem(at: dbURL)
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: dbURL.path + suffix))
        }

        let storeB = SessionIndexStore(sessionRoot: sessionRoot)
        let result = try await storeB.openSession(root: sessionRoot, scan: makeScan())
        let rebuiltRows = try rawRows(dbURL)
        await storeB.close()

        XCTAssertEqual(result.added, 2, "two browsable originals")
        XCTAssertEqual(result.orphanAdded, 1, "plus the orphan classification row")
        XCTAssertEqual(firstRows.rows.count, 3)
        XCTAssertEqual(firstRows.names.count, 34)
        var compared = 0
        for (old, new) in zip(firstRows.rows, rebuiltRows.rows) {
            for (index, name) in firstRows.names.enumerated() where name != "scan_epoch" {
                // file_mtime/sidecar_mtime: identical files → identical
                // mtimes (Double equality is deterministic here).
                XCTAssertEqual(old[index], new[index], "column \(name) diverged")
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 3 * 30, "parity must cover the FULL v2 set")
    }

    // MARK: - EXIF sweep (Plan 12-1 T5 — the v2 seven columns)

    /// Write a real JPEG (4×3 solid) with the given TIFF/EXIF properties.
    private func writeJPEG(
        _ rel: String, tiff: [CFString: Any] = [:], exif: [CFString: Any] = [:]
    ) throws {
        let url = sessionRoot.appendingPathComponent(rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let width = 4, height = 3
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.5, green: 0.25, blue: 0.75, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.jpeg" as CFString, 1, nil)
        XCTAssertNotNil(destination)
        var properties: [CFString: Any] = [:]
        if !tiff.isEmpty { properties[kCGImagePropertyTIFFDictionary] = tiff }
        if !exif.isEmpty { properties[kCGImagePropertyExifDictionary] = exif }
        CGImageDestinationAddImage(destination!, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination!))
    }

    /// The seven columns fill with EXACT values from a real image (L020
    /// content-level), and the sweep collects the row in ONE pass.
    func testExifSevenColumnsFillExactFromRealImage() async throws {
        try writeJPEG(
            "one.jpg",
            tiff: [
                kCGImagePropertyTIFFMake: "Sony",
                kCGImagePropertyTIFFModel: "ILCE-7RM5",
            ],
            exif: [
                kCGImagePropertyExifLensModel: "FE 24-70mm F2.8 GM II",
                kCGImagePropertyExifISOSpeedRatings: [1250],
                kCGImagePropertyExifFocalLength: 46.0,
                kCGImagePropertyExifFNumber: 2.8,
                kCGImagePropertyExifExposureTime: 0.004,
            ])

        let store = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await store.openSession(root: sessionRoot, scan: {
            let values = try! sessionRoot.appendingPathComponent("one.jpg").resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey])
            let page = SessionScanPage(entries: [SessionScanEntry(
                relPath: "one.jpg",
                mtime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
                size: Int64(values.fileSize ?? 0))])
            return AsyncStream { $0.yield(page); $0.finish() }
        }())

        let row = try await store.fetchRow(relPath: "one.jpg")
        XCTAssertEqual(row?.cameraMake, "Sony")
        XCTAssertEqual(row?.cameraModel, "ILCE-7RM5")
        XCTAssertEqual(row?.lensModel, "FE 24-70mm F2.8 GM II")
        XCTAssertEqual(row?.iso, 1250)
        XCTAssertEqual(row?.focalLength ?? 0, 46.0, accuracy: 0.001)
        XCTAssertEqual(row?.aperture ?? 0, 2.8, accuracy: 0.001)
        XCTAssertEqual(row?.exposure ?? 0, 0.004, accuracy: 0.0000001)

        // The anchor is now satisfied — a DIRECT second sweep processes
        // ZERO rows (no-EXIF columns cannot re-enter pending).
        let second = try await store.backfillExifMetadata(rootPath: sessionRoot.path)
        XCTAssertEqual(second, 0, "the sentinel/anchor must prevent re-scans")
        await store.close()
    }

    /// A no-EXIF image: text columns take the '' sentinel in the SAME
    /// sweep, numerics stay NULL (honest absence), and the row never
    /// re-enters pending (swept exactly once).
    func testNoExifImageSentinelSweepsExactlyOnce() async throws {
        try writeJPEG("plain.jpg")

        let store = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await store.openSession(root: sessionRoot, scan: {
            let values = try! sessionRoot.appendingPathComponent("plain.jpg").resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey])
            let page = SessionScanPage(entries: [SessionScanEntry(
                relPath: "plain.jpg",
                mtime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
                size: Int64(values.fileSize ?? 0))])
            return AsyncStream { $0.yield(page); $0.finish() }
        }())

        let row = try await store.fetchRow(relPath: "plain.jpg")
        XCTAssertEqual(row?.cameraMake, "", "the attempted sentinel")
        XCTAssertEqual(row?.cameraModel, "")
        XCTAssertEqual(row?.lensModel, "")
        XCTAssertNil(row?.iso, "numerics stay NULL (no EXIF)")
        XCTAssertNil(row?.focalLength)
        XCTAssertNil(row?.aperture)
        XCTAssertNil(row?.exposure)

        let second = try await store.backfillExifMetadata(rootPath: sessionRoot.path)
        XCTAssertEqual(second, 0, "swept exactly once — never re-scanned")
        await store.close()
    }

    /// A pre-existing v1-era row (orientation already filled, the new
    /// columns NULL) is collected by the SAME single sweep.
    func testV1RowsWithOrientationAreCollectedByOneSweep() async throws {
        try writeJPEG(
            "legacy.jpg",
            tiff: [kCGImagePropertyTIFFMake: "Fujifilm"])
        let dbURL = SessionIndexSchema.databaseURL(forSessionRoot: sessionRoot)
        // Hand-open the FRESH v2 database and clear the EXIF four + seven
        // to simulate the v1 population (orientation/capture filled by the
        // 09 sweep, everything else NULL).
        let store = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await store.openSession(root: sessionRoot, scan: {
            let values = try! sessionRoot.appendingPathComponent("legacy.jpg").resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey])
            let page = SessionScanPage(entries: [SessionScanEntry(
                relPath: "legacy.jpg",
                mtime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
                size: Int64(values.fileSize ?? 0))])
            return AsyncStream { $0.yield(page); $0.finish() }
        }())
        var row = try await store.fetchRow(relPath: "legacy.jpg")
        XCTAssertEqual(row?.cameraMake, "Fujifilm")

        // Simulate the v1 shape: orientation filled, camera_make NULL.
        let handle = try SQLiteHandle(path: dbURL.path)
        try handle.exec("UPDATE images SET camera_make = NULL WHERE path = 'legacy.jpg'")
        handle.close()

        let swept = try await store.backfillExifMetadata(rootPath: sessionRoot.path)
        XCTAssertEqual(swept, 1, "the v1-shaped row is collected in this one sweep")
        row = try await store.fetchRow(relPath: "legacy.jpg")
        XCTAssertEqual(row?.cameraMake, "Fujifilm")
        XCTAssertNotNil(row?.orientation, "the pre-existing v1 fill survives")
        await store.close()
    }
}

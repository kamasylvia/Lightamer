@testable import Lightamer
@testable import LightamerCore
import Foundation
import XCTest

// ImportDropTests (Plan 13-3 T4, SYS-04, D-13-CONTEXT-7) — the drop-import
// safety pins:
//
//   复制语义源零改动 golden — the source files' bytes AND mtimes, and the
//                          source directory's own mtime, survive a copy
//                          import untouched.
//   无修饰键绝不 Move      — the default path (move: false) leaves every
//                          source alive.
//   Option=Move 显式意图   — move: true relocates exactly the batch.
//   批量失败单列不中断     — a collision (and an unimportable file) among
//                          good files lists failures and imports the rest.
//   重名不覆盖             — a colliding destination keeps the ORIGINAL.
//   reconcile 收编         — after an import the explicit reconcile lands
//                          the lindex row (the grid picks it up).
@MainActor
final class ImportDropTests: XCTestCase {

    private var root: URL!
    private var sourceDir: URL!
    private var sessionRoot: URL!
    private var captureDir: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)
        sourceDir = root.appendingPathComponent("source", isDirectory: true)
        sessionRoot = root.appendingPathComponent("session", isDirectory: true)
        captureDir = sessionRoot.appendingPathComponent("Capture", isDirectory: true)
        try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: captureDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? fileManager.removeItem(at: root) }
        try super.tearDownWithError()
    }

    private func makeSourceFile(_ name: String, bytes: [UInt8] = Array(0..<64)) throws -> URL {
        let url = sourceDir.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    private func sourceSnapshot(_ urls: [URL]) throws -> [URL: (bytes: Data, mtime: Date)] {
        var snapshot: [URL: (Data, Date)] = [:]
        for url in urls {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            snapshot[url] = (
                try Data(contentsOf: url),
                attributes[.modificationDate] as! Date
            )
        }
        return snapshot
    }

    // MARK: - 复制语义源零改动 golden

    func testCopyImportLeavesSourceByteAndMtimeIdentical() throws {
        let a = try makeSourceFile("IMG_0001.ARW")
        let b = try makeSourceFile("IMG_0002.jpg", bytes: Array(repeating: 7, count: 32))
        let sources = [a, b]
        let before = try sourceSnapshot(sources)
        let sourceDirMtimeBefore = try fileManager.attributesOfItem(
            atPath: sourceDir.path)[.modificationDate] as! Date

        let outcome = ImportService.importFiles(at: sources, into: captureDir, move: false)

        XCTAssertTrue(outcome.isFullySuccessful, "\(outcome.failures)")
        XCTAssertEqual(outcome.imported.count, 2)
        // The copies land in Capture/ with identical bytes.
        for source in sources {
            let copy = captureDir.appendingPathComponent(source.lastPathComponent)
            XCTAssertTrue(fileManager.fileExists(atPath: copy.path))
            XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: source))
        }
        // The sources: bytes + mtimes byte-identical (the golden).
        let after = try sourceSnapshot(sources)
        for source in sources {
            XCTAssertEqual(after[source]?.bytes, before[source]?.bytes)
            XCTAssertEqual(
                after[source]!.mtime.timeIntervalSince1970,
                before[source]!.mtime.timeIntervalSince1970, accuracy: 0.001)
        }
        // The source DIRECTORY's own mtime is untouched too (nothing was
        // written next to the sources).
        let sourceDirMtimeAfter = try fileManager.attributesOfItem(
            atPath: sourceDir.path)[.modificationDate] as! Date
        XCTAssertEqual(
            sourceDirMtimeAfter.timeIntervalSince1970,
            sourceDirMtimeBefore.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - 无修饰键绝不 Move

    func testDefaultPathNeverMovesSources() throws {
        let sources = [
            try makeSourceFile("IMG_0003.nef"),
            try makeSourceFile("IMG_0004.png"),
        ]
        let outcome = ImportService.importFiles(at: sources, into: captureDir, move: false)
        XCTAssertTrue(outcome.isFullySuccessful)
        // Every source is STILL alive.
        for source in sources {
            XCTAssertTrue(fileManager.fileExists(atPath: source.path))
        }
        XCTAssertEqual(outcome.imported.count, 2)
    }

    // MARK: - Option=Move 显式意图 golden

    func testExplicitMoveRelocatesAndImports() throws {
        let fixtureBytes = Data(Array(0..<64))
        let sources = [try makeSourceFile("IMG_0005.cr3")]
        let outcome = ImportService.importFiles(at: sources, into: captureDir, move: true)
        XCTAssertTrue(outcome.isFullySuccessful)
        XCTAssertFalse(fileManager.fileExists(atPath: sources[0].path), "move relocates")
        let moved = captureDir.appendingPathComponent("IMG_0005.cr3")
        XCTAssertTrue(fileManager.fileExists(atPath: moved.path))
        // The relocated bytes are the fixture (the source is GONE — never
        // re-read it; the KNOWN bytes are the comparison anchor).
        XCTAssertEqual(try Data(contentsOf: moved), fixtureBytes)
    }

    // MARK: - 批量失败单列不中断 + 重名不覆盖

    func testBatchFailureIsolatesAndContinues() throws {
        let good1 = try makeSourceFile("IMG_0006.raf")
        let good2 = try makeSourceFile("IMG_0007.tif")
        // A name collision with an EXISTING Capture member.
        let existing = try Data(Array(repeating: 9, count: 16))
        try existing.write(
            to: captureDir.appendingPathComponent("IMG_0007.tif"))
        // An unimportable file (a directory + a sidecar + a random ext).
        let directory = sourceDir.appendingPathComponent("subdir", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let sidecar = try makeSourceFile("IMG_0006.ARW.lra")
        _ = sidecar

        let outcome = ImportService.importFiles(
            at: [good1, directory, good2, sidecar], into: captureDir, move: false)

        // The good file imported DESPITE the failures (不中断).
        XCTAssertTrue(fileManager.fileExists(
            atPath: captureDir.appendingPathComponent("IMG_0006.raf").path))
        XCTAssertEqual(outcome.imported.map(\.lastPathComponent),
                       ["IMG_0006.raf"])
        // The failures are LISTED per file (单列): the directory, the
        // sidecar (notImportable) AND the colliding good2 (its name was
        // pre-seeded in the destination).
        XCTAssertEqual(outcome.failures.count, 3)
        XCTAssertTrue(outcome.failures.contains {
            $0.source == directory && $0.reason == "notImportable"
        })
        XCTAssertTrue(outcome.failures.contains {
            $0.source == sidecar && $0.reason == "notImportable"
        })
        XCTAssertTrue(outcome.failures.contains {
            $0.source == good2 && $0.reason == "collision"
        })
        // The collision SKIPPED — the pre-existing destination's bytes
        // survive (never overwritten).
        XCTAssertEqual(
            try Data(contentsOf: captureDir.appendingPathComponent("IMG_0007.tif")),
            existing)
    }

    func testCollisionSkipsWithoutOverwriting() throws {
        let sources = [try makeSourceFile("IMG_0008.dng")]
        let original = try Data(Array(repeating: 3, count: 16))
        try original.write(to: captureDir.appendingPathComponent("IMG_0008.dng"))

        let outcome = ImportService.importFiles(at: sources, into: captureDir, move: false)

        XCTAssertEqual(outcome.imported.count, 0)
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertEqual(outcome.failures.first?.reason, "collision")
        // The source is untouched too (a skip never relocates).
        XCTAssertTrue(fileManager.fileExists(atPath: sources[0].path))
        XCTAssertEqual(
            try Data(contentsOf: captureDir.appendingPathComponent("IMG_0008.dng")),
            original)
    }

    func testInSessionSourceSkips() throws {
        // A file already living in this Capture tier never self-copies.
        let member = captureDir.appendingPathComponent("IMG_0009.rw2")
        try Data([1, 2, 3]).write(to: member)
        let outcome = ImportService.importFiles(at: [member], into: captureDir, move: false)
        XCTAssertEqual(outcome.imported.count, 0)
        XCTAssertEqual(outcome.failures.first?.reason, "inSession")
        XCTAssertTrue(fileManager.fileExists(atPath: member.path))
    }

    // MARK: - reconcile 收编（导入后 lindex 行就位）

    func testImportLandsLindexRowThroughExplicitReconcile() async throws {
        // The Catalogs projector face stays out of the test (the shared
        // .lcat is app-runtime state — the seam keeps the test temp-only).
        let controller = SessionIndexController()
        controller.catalogProjectorProvider = { nil }
        defer { Task { await controller.close() } }

        // Session with ONE existing image AT THE ROOT (the browse set —
        // the root-level Capture tier is excluded per D-09-CONTEXT-3,
        // which is why the import destination is the session root).
        _ = try makeSourceFile("IMG_0010.arw")
        try fileManager.copyItem(
            at: sourceDir.appendingPathComponent("IMG_0010.arw"),
            to: sessionRoot.appendingPathComponent("IMG_0010.arw"))
        let sync = await controller.openAndSync(root: sessionRoot)
        XCTAssertFalse(sync.failed)
        let baseline = try await controller.currentStore!.fetchAllRows()
        XCTAssertEqual(baseline.count, 1)
        XCTAssertEqual(baseline.first?.path, "IMG_0010.arw")

        // DROP: the import lands a NEW file into the session root.
        let dropped = try makeSourceFile("IMG_0011.nef")
        let outcome = ImportService.importFiles(
            at: [dropped], into: sessionRoot, move: false)
        XCTAssertEqual(outcome.imported.count, 1)

        // The EXPLICIT reconcile (never FSEvents timing): the row arrives.
        let reconcile = await controller.reconcile(root: sessionRoot)
        XCTAssertNotNil(reconcile)
        let rows = try await controller.currentStore!.fetchAllRows()
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.contains { $0.path == "IMG_0011.nef" })
        XCTAssertEqual(reconcile?.counts?.total, 2)
    }
}

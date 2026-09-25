import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// Session tree tests (Plan 09-01 T2/T3) — fixtures are built IN TESTS inside
// `FileManager.temporaryDirectory` (the internal SSD — L009: NEVER on the
// external-volume USB volume for anything timing-adjacent).
//
// T2 sections: the three-tier idempotent creation (run twice → zero diff in
// mtimes AND directory set) + the `outputDirectory` pure-function vectors.
// T3 extends this class with the walkTree golden classification + exclude
// rule unit vectors.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class SessionTreeScannerTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("sessiontree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeSessionRoot(named: String = "session") -> URL {
        let url = tempDirectory.appendingPathComponent(named, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Snapshot (relative path → modification time) of every DIRECTORY
    /// under `root` (inclusive).
    private func directorySnapshot(_ root: URL) throws -> [String: Date] {
        var result: [String: Date] = [:]
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]
        )!
        for case let url as URL in enumerator {
            let values = try url.resourceValues(
                forKeys: [.isDirectoryKey, .contentModificationDateKey]
            )
            if values.isDirectory == true {
                let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
                result[rel] = values.contentModificationDate
            }
        }
        result["."] = try root.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
        return result
    }

    // MARK: - T2: three-tier idempotent creation

    func testEnsureDirectoriesCreatesExactlyThreeTiers() throws {
        let root = makeSessionRoot()
        try SessionLayout.ensureDirectories(at: root)

        let contents = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        )
        let names = Set(contents.map(\.lastPathComponent))
        XCTAssertEqual(
            names,
            ["Capture", "Crop", "Output"],
            "REQUIREMENTS SESS-02 literal three tiers — Trash/Selects NOT "
                + "created (D-09-CONTEXT-3)"
        )
        for url in contents {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            XCTAssertEqual(values.isDirectory, true, "\(url) must be a directory")
        }
    }

    func testEnsureDirectoriesIsIdempotentZeroDiff() throws {
        let root = makeSessionRoot()
        try SessionLayout.ensureDirectories(at: root)
        // Touch a marker file inside Capture to prove a second run leaves
        // EXISTING content untouched.
        let marker = root.appendingPathComponent("Capture/.keep")
        try Data("x".utf8).write(to: marker)

        let before = try directorySnapshot(root)
        try SessionLayout.ensureDirectories(at: root)
        try SessionLayout.ensureDirectories(at: root) // a THIRD run: open-path repeats
        let after = try directorySnapshot(root)

        XCTAssertEqual(before, after, "second/third ensureDirectories runs must be "
            + "zero-diff: no new directories, no mtime churn")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path),
                      "existing content must survive re-runs")
    }

    func testEnsureDirectoriesOnDeeplyMissingRoot() throws {
        // withIntermediateDirectories must conjure the root itself.
        let root = tempDirectory
            .appendingPathComponent("missing/parent/root", isDirectory: true)
        try SessionLayout.ensureDirectories(at: root)
        for name in ["Capture", "Crop", "Output"] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(name).path
                )
            )
        }
    }

    // MARK: - T2: consumption-point pure functions (Phase 11 takeover)

    func testOutputDirectoryConstantVectors() {
        let root = URL(fileURLWithPath: "/tmp/whatever", isDirectory: true)
        XCTAssertEqual(
            SessionLayout.outputDirectory(for: root),
            root.appendingPathComponent("Output", isDirectory: true)
        )
        XCTAssertEqual(
            SessionLayout.outputDirectory(for: root).lastPathComponent, "Output"
        )
        XCTAssertEqual(
            SessionLayout.captureDirectory(for: root).lastPathComponent, "Capture"
        )
    }

    func testReservedRootDirectorySetIsTheThreeTiers() {
        XCTAssertEqual(
            SessionLayout.reservedRootDirectoryNames,
            ["Capture", "Crop", "Output"]
        )
        XCTAssertFalse(
            SessionLayout.reservedRootDirectoryNames.contains("Trash"),
            "Trash is NOT part of the v1 directory set (D-09-CONTEXT-3)"
        )
    }

    func testDerivedCacheDirectoryNameIsHiddenDotDirectory() {
        XCTAssertEqual(SessionLayout.derivedCacheDirectoryName, ".lightamer")
    }

    // MARK: - T3: exclusion predicates (one case per rule)

    func testExcludedFilePredicatesPerRule() {
        XCTAssertTrue(SessionTreeScanner.isExcludedFile(".DS_Store"), "dotfile rule")
        XCTAssertTrue(
            SessionTreeScanner.isExcludedFile(".DSC0002.ARW.lra.tmp-UUID"),
            "SidecarStore promotion residue (dot + .tmp-)"
        )
        XCTAssertTrue(SessionTreeScanner.isExcludedFile("x.tmp-1234"), "*.tmp-* rule")
        XCTAssertTrue(
            SessionTreeScanner.isExcludedFile("cousin.cosessiondb"), "C1 artifact rule"
        )
        XCTAssertTrue(SessionTreeScanner.isExcludedFile("DSC.ARW.lra"), ".lra attachment rule")
        XCTAssertFalse(SessionTreeScanner.isExcludedFile("DSC0001.ARW"))
        XCTAssertFalse(SessionTreeScanner.isExcludedFile("vacation.jpg"))
    }

    func testExcludedDirectoryPredicatesRootGate() {
        XCTAssertTrue(
            SessionTreeScanner.isExcludedDirectory("Capture", isDirectlyUnderRoot: true)
        )
        XCTAssertTrue(
            SessionTreeScanner.isExcludedDirectory("Output", isDirectlyUnderRoot: true)
        )
        XCTAssertTrue(
            SessionTreeScanner.isExcludedDirectory("Crop", isDirectlyUnderRoot: true)
        )
        XCTAssertFalse(
            SessionTreeScanner.isExcludedDirectory("Capture", isDirectlyUnderRoot: false),
            "nested same-name user folders stay browsable (root gate only)"
        )
        XCTAssertTrue(
            SessionTreeScanner.isExcludedDirectory(".lightamer", isDirectlyUnderRoot: false),
            "own cache excluded ANYWHERE"
        )
        XCTAssertTrue(
            SessionTreeScanner.isExcludedDirectory(".hidden", isDirectlyUnderRoot: true)
        )
        XCTAssertFalse(
            SessionTreeScanner.isExcludedDirectory("2024-05", isDirectlyUnderRoot: false)
        )
    }

    func testBrowsableExtensionVectors() {
        for name in ["A.ARW", "b.Cr3", "c.JPG", "d.webp", "e.dng", "f.3FR", "g.iiq"] {
            XCTAssertTrue(SessionTreeScanner.isBrowsableFile(name), name)
        }
        for name in ["h.mov", "noext", "i.txt", "j.lra"] {
            XCTAssertFalse(SessionTreeScanner.isBrowsableFile(name), name)
        }
    }

    // MARK: - T3: golden classification fixture

    /// Build the golden fixture tree; returns nothing — assertions name the
    /// exact expected paths.
    private func buildGoldenFixture() throws -> URL {
        let root = makeSessionRoot(named: "golden")
        func write(_ rel: String) throws {
            let url = root.appendingPathComponent(rel)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data("x".utf8).write(to: url)
        }
        // Browsable originals.
        try write("DSC0001.ARW") // pristine
        try write("DSC0002.ARW") // edited (sidecar below)
        try write("DSC0002.ARW.lra")
        try write("nested/IMG_0001.CR3") // nested subfolder
        try write("scan.jpg") // raster fallback
        try write("deeper/Capture/RAW1.ARW") // nested reserved-NAME folder stays browsable
        // Orphan sidecar.
        try write("DSC0003.ARW.lra")
        // Excluded noise.
        try write("Capture/DSC_A.ARW") // root-level reserved dir
        try write("Output/export.jpg")
        try write(".lightamer/session.lindex")
        try write(".DS_Store")
        try write(".DSC0002.ARW.lra.tmp-residue")
        try write("cousin.cosessiondb")
        try write("photo.tmp-backup.jpg")
        return root
    }

    func testGoldenClassificationExactPaths() async throws {
        let root = try buildGoldenFixture()
        let (entries, orphans) = await SessionTreeScanner.collect(root: root)

        let expectedEntries: Set<String> = [
            "DSC0001.ARW", "DSC0002.ARW", "nested/IMG_0001.CR3", "scan.jpg",
            "deeper/Capture/RAW1.ARW",
        ]
        XCTAssertEqual(
            Set(entries.map(\.relPath)), expectedEntries,
            "browse set must match the golden set EXACTLY"
        )

        // pristine vs edited by sidecar presence (the T5 has_edits leg).
        var pristine: Set<String> = []
        var edited: Set<String> = []
        for entry in entries {
            let sidecar = root.appendingPathComponent(entry.relPath + ".lra")
            if FileManager.default.fileExists(atPath: sidecar.path) {
                edited.insert(entry.relPath)
            } else {
                pristine.insert(entry.relPath)
            }
        }
        XCTAssertEqual(pristine, ["DSC0001.ARW", "nested/IMG_0001.CR3", "scan.jpg",
                                  "deeper/Capture/RAW1.ARW"])
        XCTAssertEqual(pristine.count, 4)
        XCTAssertEqual(edited, ["DSC0002.ARW"])
        XCTAssertEqual(edited.count, 1)

        // Orphan sidecars: exact path, count 1.
        XCTAssertEqual(orphans, ["DSC0003.ARW.lra"])

        // Stat triples must carry REAL values (non-vacuous).
        for entry in entries {
            XCTAssertGreaterThan(entry.size, 0, entry.relPath)
            XCTAssertGreaterThan(entry.mtime, 0, entry.relPath)
        }

        // Excluded noise must appear NOWHERE.
        let excludedNoise = [
            "Capture/DSC_A.ARW", "Output/export.jpg", ".lightamer/session.lindex",
            ".DS_Store", ".DSC0002.ARW.lra.tmp-residue", "cousin.cosessiondb",
            "photo.tmp-backup.jpg",
        ]
        for noise in excludedNoise {
            XCTAssertFalse(
                Set(entries.map(\.relPath)).contains(noise),
                "excluded noise leaked into the browse set: \(noise)"
            )
            XCTAssertFalse(orphans.contains(noise))
        }
    }

    func testScanIsProgressiveMultiPage() async throws {
        let root = makeSessionRoot(named: "progressive")
        for i in 0..<600 { // > 2 pages of 256
            let url = root.appendingPathComponent("img\(String(format: "%04d", i)).jpg")
            try Data("x".utf8).write(to: url)
        }

        var iterator = SessionTreeScanner.scan(root: root).makeAsyncIterator()
        let firstPage = await iterator.next()
        XCTAssertNotNil(firstPage)
        XCTAssertEqual(
            firstPage?.entries.count, SessionTreeScanner.pageSize,
            "the FIRST page is full-size — rows flow out BEFORE the walk ends "
                + "(progressive-ingest structural proof)"
        )
        var pages = 1
        var total = firstPage?.entries.count ?? 0
        while let page = await iterator.next() {
            pages += 1
            total += page.entries.count
        }
        XCTAssertEqual(total, 600, "the stream is complete")
        XCTAssertGreaterThanOrEqual(pages, 3, "multiple pages — not one final batch")
    }

    func testScanOrphansNeverHardFail() async throws {
        // A sidecar WITHOUT its original plus an unreadable directory must
        // not throw the walk away (SC#2 gracefully).
        let root = makeSessionRoot(named: "orphans")
        try Data("x".utf8).write(to: root.appendingPathComponent("GONE.ARW.lra"))
        try Data("x".utf8).write(to: root.appendingPathComponent("KEEP.ARW"))

        let (entries, orphans) = await SessionTreeScanner.collect(root: root)
        XCTAssertEqual(entries.map(\.relPath), ["KEEP.ARW"])
        XCTAssertEqual(orphans, ["GONE.ARW.lra"])
    }
}

// MARK: - T7: open-session timing baseline (10k, SSD temp fixture — L009)

extension SessionTreeScannerTests {

    /// COLD first open (full walk + 10k inserts + backfill passes) and WARM
    /// second open (rescan + zero-diff) — the perf.md 「开卷」 baseline
    /// numbers (printed; target: warm ≤ 2s, cold recorded no-gate).
    func testOpenSessionTenThousandWarmAndColdBaseline() async throws {
        let root = makeSessionRoot(named: "tenk")
        let fileManager = FileManager.default
        for i in 0..<10_000 {
            let url = root
                .appendingPathComponent("img\(String(format: "%05d", i)).jpg")
            try Data("x".utf8).write(to: url)
        }
        _ = fileManager

        let store = SessionIndexStore(sessionRoot: root)
        let clock = ContinuousClock()

        // COLD.
        let coldStart = clock.now
        let cold = try await store.openSession(
            root: root, scan: SessionTreeScanner.scan(root: root)
        )
        let coldElapsed = Double((clock.now - coldStart).components.seconds)
            + Double((clock.now - coldStart).components.attoseconds) / 1e18
        XCTAssertEqual(cold.added, 10_000)
        XCTAssertEqual(cold.counts.total, 10_000)
        print("SESSION-OPEN-10k COLD seconds: \(coldElapsed)")

        // WARM.
        let warmStart = clock.now
        let warm = try await store.openSession(
            root: root, scan: SessionTreeScanner.scan(root: root)
        )
        let warmElapsed = Double((clock.now - warmStart).components.seconds)
            + Double((clock.now - warmStart).components.attoseconds) / 1e18
        XCTAssertEqual(warm.added, 0)
        XCTAssertEqual(warm.changed, 0)
        XCTAssertEqual(warm.removed, 0)
        print("SESSION-OPEN-10k WARM seconds: \(warmElapsed)")

        // The stated target: 暖 ≤ 2s (SSD fixture; USB-volume cold reads are
        // L009's recorded risk, no gate — see .work/09/perf.md).
        XCTAssertLessThan(warmElapsed, 2.0, "warm reopen must beat the 2s target")
        await store.close()
    }
}

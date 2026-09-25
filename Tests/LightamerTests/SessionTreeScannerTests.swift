import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// Session tree tests (Plan 09-01 T2/T3) — fixtures are built IN TESTS inside
// `FileManager.temporaryDirectory` (the internal SSD — L009: NEVER on the
// UNITEK USB volume for anything timing-adjacent).
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
}

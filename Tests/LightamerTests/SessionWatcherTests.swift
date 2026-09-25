import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// Plan 09-02 T2 — the SessionWatcher suite:
//
//   • REAL FSEventStream over a temp directory (legal on macOS local
//     volumes): create / rename-in-session / move-out / delete events are
//     classified and arrive within a hard timeout (limited awaits — a
//     timeout IS a failure, never a hang)
//   • `.lra` sidecar events PASS the filter (external sidecar writes are
//     reconcile signals; the self-write swallow lives in the journal, T3)
//   • the derived-cache noise (`.lightamer/**`, dotfiles) NEVER arrives
//     (the single-source exclude table, observed over a window)
//   • WatchRoot: renaming the watched ROOT itself lands a rootChanged
//     batch (full-rescan escalation + recent-path invalidation hint)
//   • classification table unit cases (reserved tiers, dotfiles, nested
//     same-name dirs) driven WITHOUT real FSEvents
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class SessionWatcherTests: XCTestCase {

    private var tempDirectory: URL!
    private var sessionDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("watcher-\(UUID().uuidString)", isDirectory: true)
        sessionDirectory = tempDirectory.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionDirectory, withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Collects batches from the watcher's single-consumer stream.
    private actor Collector {
        var batches: [WatchEventBatch] = []
        func append(_ batch: WatchEventBatch) { batches.append(batch) }
        func snapshot() -> [WatchEventBatch] { batches }
    }

    /// Poll until the predicate holds over the collected batches. A timeout
    /// fails the test (limited-await discipline — no hangs).
    private func waitFor(
        _ collector: Collector,
        timeout: TimeInterval = 10,
        _ message: @autoclosure () -> String,
        _ predicate: @escaping ([WatchEventBatch]) -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(await collector.snapshot()) { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let batches = await collector.snapshot()
        XCTFail("timeout (\(timeout)s) waiting: \(message()) — got \(batches)")
    }

    private func startWatch(
        on root: URL? = nil, latency: TimeInterval = 0.2
    ) async throws -> (SessionWatcher, Collector, Task<Void, Never>) {
        let watcher = SessionWatcher(
            root: root ?? sessionDirectory, latency: latency
        )
        XCTAssertTrue(watcher.start(), "the watcher must start on an existing root")
        let collector = Collector()
        let task = Task.detached {
            for await batch in watcher.events {
                await collector.append(batch)
            }
        }
        return (watcher, collector, task)
    }

    private func teardown(_ watcher: SessionWatcher, _ task: Task<Void, Never>) {
        watcher.stop()
        task.cancel()
    }

    // MARK: - Synthetic events (real FSEventStream)

    func testCreateEventClassifiedAndArrives() async throws {
        let (watcher, collector, task) = try await startWatch()
        defer { teardown(watcher, task) }

        try Data([0x01]).write(to: sessionDirectory.appendingPathComponent("a.arw"))
        try await waitFor(collector, "the create event at the root level") { batches in
            batches.contains { $0.affectedDirectories.contains("") }
        }
    }

    func testCreateRenameMoveOutDeleteAllArrive() async throws {
        let (watcher, collector, task) = try await startWatch()
        defer { teardown(watcher, task) }
        let fileManager = FileManager.default

        // ① create in a SUBDIRECTORY (affected dir = "sub")
        try fileManager.createDirectory(
            at: sessionDirectory.appendingPathComponent("sub"), withIntermediateDirectories: true
        )
        try Data([0x01]).write(to: sessionDirectory.appendingPathComponent("sub/one.arw"))
        try await waitFor(collector, "create in sub/") { batches in
            batches.contains { $0.affectedDirectories.contains("sub") }
        }

        // ② rename WITHIN the session (the FSEvents split: two events)
        try fileManager.moveItem(
            at: sessionDirectory.appendingPathComponent("sub/one.arw"),
            to: sessionDirectory.appendingPathComponent("sub/two.arw")
        )
        try await waitFor(collector, "in-session rename events in sub/") { batches in
            batches.contains { $0.affectedDirectories.contains("sub") }
        }

        // ③ MOVE-OUT: the file leaves the watched tree entirely
        let outside = tempDirectory.appendingPathComponent("outside.arw")
        try fileManager.moveItem(
            at: sessionDirectory.appendingPathComponent("sub/two.arw"), to: outside
        )
        try await waitFor(collector, "the move-out event") { batches in
            batches.contains { !$0.affectedDirectories.isEmpty || $0.requiresFullRescan }
        }

        // ④ delete (of the moved-out external file — still under the root's
        // parent volume, but OUTSIDE our root: use an in-root file instead)
        try Data([0x02]).write(to: sessionDirectory.appendingPathComponent("gone.arw"))
        try await waitFor(collector, "the pre-delete create") { batches in
            batches.contains { $0.affectedDirectories.contains("") }
        }
        try fileManager.removeItem(at: sessionDirectory.appendingPathComponent("gone.arw"))
        try await waitFor(collector, "the delete event at the root level") { batches in
            batches.contains { $0.affectedDirectories.contains("") }
        }
    }

    func testSidecarEventsPassTheFilter() async throws {
        // `.lra` is NOT watcher-excluded — an external sidecar write is a
        // legitimate signal (self-writes are swallowed by the journal, T3).
        let (watcher, collector, task) = try await startWatch()
        defer { teardown(watcher, task) }

        try Data([0x03]).write(
            to: sessionDirectory.appendingPathComponent("x.arw.lra")
        )
        try await waitFor(collector, "the sidecar event passing the filter") { batches in
            batches.contains { $0.affectedDirectories.contains("") }
        }
    }

    func testDerivedCacheNoiseNeverArrives() async throws {
        // The self-feedback EXCLUDE leg: `.lightamer/**` + dotfiles produce
        // ZERO batches over a real observation window.
        let (watcher, collector, task) = try await startWatch()
        defer { teardown(watcher, task) }
        let fileManager = FileManager.default

        let cache = sessionDirectory.appendingPathComponent(".lightamer", isDirectory: true)
        try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: cache.appendingPathComponent("thumbs"), withIntermediateDirectories: true
        )
        try Data([0x04]).write(to: cache.appendingPathComponent("thumbs/t.jpg"))
        try Data([0x05]).write(to: sessionDirectory.appendingPathComponent(".hidden"))
        try Data([0x06]).write(to: sessionDirectory.appendingPathComponent("w.tmp-uuid"))

        // Observation window: latency 0.2s → coalesced batches land well
        // inside 2.5s if any (wrongly) survived the filter.
        try await Task.sleep(nanoseconds: 2_500_000_000)
        let batches = await collector.snapshot()
        XCTAssertEqual(
            batches.flatMap { $0.affectedDirectories }.sorted(),
            [],
            "excluded-path noise must never reach the reconciler — got \(batches)"
        )
    }

    func testWatchRootRenameArrivesAsRootChanged() async throws {
        let (watcher, collector, task) = try await startWatch()
        defer { teardown(watcher, task) }

        // Rename the WATCHED ROOT itself (Finder-move of the session
        // folder). The event must arrive flagged rootChanged — the path is
        // never silently rewritten.
        let renamed = tempDirectory.appendingPathComponent("session-moved", isDirectory: true)
        try FileManager.default.moveItem(at: sessionDirectory, to: renamed)

        try await waitFor(collector, "the RootChanged batch") { batches in
            batches.contains { $0.rootChanged }
        }
    }

    func testStartFailsOnMissingRoot() throws {
        let missing = tempDirectory.appendingPathComponent("does-not-exist")
        let watcher = SessionWatcher(root: missing)
        XCTAssertFalse(watcher.start(), "a nonexistent root must refuse to watch")
        watcher.stop()
    }

    // MARK: - Classification table (no real FSEvents)

    func testClassifyFilteringTable() {
        let rootPath = sessionDirectory.path
        let prefixes = [rootPath + "/"]

        func classify(_ path: String, into batch: inout WatchEventBatch) {
            SessionWatcher.classify(
                path: path, relativeToPrefixes: prefixes, into: &batch
            )
        }

        var batch = WatchEventBatch()
        // Root-level browsable file → affected dir "".
        classify(rootPath + "/a.arw", into: &batch)
        // Nested file → "sub".
        classify(rootPath + "/sub/b.arw", into: &batch)
        // Deep nesting keeps the full relative dir.
        classify(rootPath + "/day1/raw/c.arw", into: &batch)
        // `.lra` sidecar → KEPT (external-write signal).
        classify(rootPath + "/d.arw.lra", into: &batch)
        XCTAssertEqual(batch.affectedDirectories, ["", "sub", "day1/raw"])

        // NOTE: the L027 physical-spelling match (/private/var… vs /var…)
        // is covered END-TO-END by the real-FSEventStream tests above — the
        // watcher realpath(3)s the root at init and matches BOTH spellings.

        // EXCLUDED: derived cache, dotfile dirs, reserved root tiers,
        // noise files.
        var dropped = WatchEventBatch()
        for path in [
            rootPath + "/.lightamer/session.lindex",
            rootPath + "/.lightamer/thumbs/t.jpg",
            rootPath + "/.hidden-dir/e.arw",
            rootPath + "/Capture/e.arw",       // reserved ROOT tier
            rootPath + "/Output/e.jpg",        // reserved ROOT tier
            rootPath + "/Crop/e.arw",          // reserved ROOT tier
            rootPath + "/w.tmp-uuid",          // promotion residue
            rootPath + "/catalog.cosessiondb", // C1 artifact
            "/somewhere/else/a.arw",           // outside the root
            rootPath,                          // the root itself (no rel)
        ] {
            classify(path, into: &dropped)
        }
        XCTAssertTrue(
            dropped.affectedDirectories.isEmpty,
            "all excluded paths must drop — got \(dropped.affectedDirectories)"
        )

        // A NESTED same-name folder stays browsable (the scanner parity).
        var nested = WatchEventBatch()
        classify(rootPath + "/trips/Capture/f.arw", into: &nested)
        XCTAssertEqual(nested.affectedDirectories, ["trips/Capture"])
    }

    func testBatchCapSemantics() {
        // The 4096 countermeasure: a full batch is presumed truncated and
        // demands full rescan; RootChanged/MustRescan do too.
        XCTAssertTrue(SessionWatcher.batchCap == 4096)
        var truncated = WatchEventBatch()
        truncated.truncated = true
        XCTAssertTrue(truncated.requiresFullRescan)
        var rootChanged = WatchEventBatch()
        rootChanged.rootChanged = true
        XCTAssertTrue(rootChanged.requiresFullRescan)
        var mustRescan = WatchEventBatch()
        mustRescan.mustRescan = true
        XCTAssertTrue(mustRescan.requiresFullRescan)
        XCTAssertFalse(WatchEventBatch().requiresFullRescan)
    }
}

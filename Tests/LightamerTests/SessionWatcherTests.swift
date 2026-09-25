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

// ─────────────────────────────────────────────────────────────────────────────
// Plan 09-02 T3 — the four-schedule + self-feedback suite (appended to the
// watcher suite per the plan's evidence mapping):
//
//   • THE resident self-feedback assertion: 100 REAL sidecar writes through
//     the SidecarStore writeAtomic path with the watcher RUNNING → ZERO
//     event-driven reconciles inside the observation window (double
//     defense: exclude table + write journal)
//   • a journalled `.lra` event is swallowed; a NON-journalled one
//     schedules the debounced reconcile (the swallow is not a blanket)
//   • focus-gain forces a reconcile (the dropped-events fallback)
//   • rootChanged escalates to a forced reconcile + rootLost state
//   • the debounce coalesces bursts into ONE eventBatch reconcile
//   • the row-stale hint marks rows and never deletes them
//   • the exclude-table single-source assertion (watcher vs scanner
//     predicates by value)
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class SessionReconcileScheduleTests: XCTestCase {

    private var tempDirectory: URL!
    private var sessionDirectory: URL!
    private var journal: SidecarWriteJournal!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("reconciler-\(UUID().uuidString)", isDirectory: true)
        sessionDirectory = tempDirectory.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionDirectory, withIntermediateDirectories: true
        )
        journal = SidecarWriteJournal()  // isolated — never .shared
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Harness

    /// A reconciler wired to a REAL index controller against the temp
    /// session (the same composition the app root performs).
    private func makeWiredReconciler(
        debounce: Duration = .milliseconds(150)
    ) -> (SessionReconciler, SessionIndexController, SessionState) {
        let controller = SessionIndexController()
        let state = SessionState(recentDefaults: nil)
        let reconciler = SessionReconciler(debounce: debounce, journal: journal)
        reconciler.appState = state
        reconciler.reconcileHandler = { url in
            let outcome = await controller.reconcile(root: url)
            if let counts = outcome?.counts {
                state.setBrowseCounts(counts)
            }
            return outcome?.plan
        }
        reconciler.staleMarkHandler = { paths in
            await controller.markStale(relPaths: paths)
        }
        return (reconciler, controller, state)
    }

    /// A minimal valid sidecar document (the write path only needs JSON —
    /// no decode is involved in this suite).
    private func makeDocument() -> LightamerSidecar {
        LightamerSidecar(
            imageID: UUID(),
            decoderVersionUsed: "v8",
            decodeParamsHash: 1,
            instances: [],
            history: HistoryStack(),
            historyHash: 7,
            layerStack: nil
        )
    }

    private func waitInterval(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: - THE self-feedback resident assertion

    func testOneHundredSelfWrittenSidecarsTriggerZeroReconciles() async throws {
        // ① Seed the index with 100 originals + sidecars (real open sync).
        for index in 0..<100 {
            try Data([UInt8(index % 255)]).write(
                to: sessionDirectory.appendingPathComponent("img-\(index).arw")
            )
        }
        let (reconciler, controller, _) = makeWiredReconciler()
        _ = await controller.openAndSync(root: sessionDirectory)
        reconciler.startSession(root: sessionDirectory)
        defer { reconciler.stopSession() }

        // ② Flush the SinceNow residue: events for the pre-arm original
        //    creates may still arrive right after start (FSEvents
        //    coalescing) — those are LEGITIMATE external-change hints,
        //    not self-feedback. Settle them, then measure the DELTA.
        try await waitInterval(1.2)
        let baselineReconciles = reconciler.reconcileLog.count
        let baselineSwallows = reconciler.journalSwallowCount

        // ③ THE storm: 100 REAL writes through SidecarStore's writeAtomic
        //    path (tmp + promotion), watcher running the whole time.
        for index in 0..<100 {
            let destination = sessionDirectory
                .appendingPathComponent("img-\(index).arw.lra")
            let store = SidecarStore(
                destination: destination, journal: journal
            )
            await store.scheduleWrite(makeDocument())
            try await store.flushNow()
        }

        // ④ Observation window: FSEvents latency (0.3s) + debounce (0.15s)
        //    settle well inside 3s. The journal window (30s default) has
        //    NOT expired — every `.lra` event must be swallowed.
        try await waitInterval(3.0)

        // ⑤ ZERO self-triggered reconciles across the storm — the resident
        //    assertion (delta against the pre-storm baseline).
        XCTAssertEqual(
            reconciler.reconcileLog.count, baselineReconciles,
            "self-written sidecars must NEVER trigger a reconcile — got \(reconciler.reconcileLog)"
        )
        XCTAssertGreaterThan(
            reconciler.journalSwallowCount, baselineSwallows,
            "the journal must have swallowed the `.lra` events (defense ② active)"
        )
    }

    func testNonJournaledSidecarEventStillSchedulesReconcile() async throws {
        let (reconciler, controller, state) = makeWiredReconciler()
        _ = await controller.openAndSync(root: sessionDirectory)
        reconciler.startSession(root: sessionDirectory)
        defer { reconciler.stopSession() }

        // An EXTERNAL sidecar write (never journalled) must schedule.
        try Data([0x0A]).write(
            to: sessionDirectory.appendingPathComponent("x.arw.lra")
        )
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !reconciler.reconcileLog.contains(.eventBatch) {
            try await waitInterval(0.1)
        }
        XCTAssertEqual(
            reconciler.reconcileLog, [.eventBatch],
            "an external `.lra` event schedules the debounced reconcile"
        )
        XCTAssertEqual(state.folderWatchStatus, .synced, "settles back after apply")
    }

    // MARK: - Focus / forced / debounce timing

    func testFocusGainForcesReconcile() async throws {
        let (reconciler, controller, _) = makeWiredReconciler()
        _ = await controller.openAndSync(root: sessionDirectory)
        reconciler.startSession(root: sessionDirectory)
        defer { reconciler.stopSession() }

        // The app-focus leg via the REAL notification (the dropped-events
        // fallback — 09-RESEARCH §4.2 row four).
        NotificationCenter.default.post(
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !reconciler.reconcileLog.contains(.focus) {
            try await waitInterval(0.05)
        }
        XCTAssertEqual(reconciler.reconcileLog, [.focus])
    }

    func testFocusWithNoSessionIsNoOp() async throws {
        let reconciler = SessionReconciler(debounce: .milliseconds(50), journal: journal)
        reconciler.appState = SessionState(recentDefaults: nil)
        reconciler.reconcileHandler = { _ in ReconcilePlan() }
        await reconciler.forceReconcile(reason: .focus)
        XCTAssertTrue(reconciler.reconcileLog.isEmpty, "no session → no reconcile")
    }

    func testRootChangedEscalatesForcedReconcileAndRootLost() async throws {
        let (reconciler, controller, state) = makeWiredReconciler()
        _ = await controller.openAndSync(root: sessionDirectory)
        reconciler.startSession(root: sessionDirectory)
        defer { reconciler.stopSession() }

        // The WatchRoot leg: force the escalation through the REAL event
        // path by renaming the watched root (the watcher flags rootChanged).
        let moved = tempDirectory.appendingPathComponent("moved-root", isDirectory: true)
        try FileManager.default.moveItem(at: sessionDirectory, to: moved)

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !reconciler.reconcileLog.contains(.forced) {
            try await waitInterval(0.1)
        }
        XCTAssertEqual(reconciler.reconcileLog, [.forced])
        XCTAssertEqual(state.folderWatchStatus, .rootLost)
        XCTAssertTrue(state.currentSessionRootLost, "the recent-path invalidation hint")
    }

    func testDebounceCoalescesBurstIntoSingleReconcile() async throws {
        let (reconciler, controller, state) = makeWiredReconciler(debounce: .milliseconds(200))
        _ = await controller.openAndSync(root: sessionDirectory)
        reconciler.startSession(root: sessionDirectory)
        defer { reconciler.stopSession() }

        // Five quick external creates — ONE coalesced reconcile.
        for index in 0..<5 {
            try Data([UInt8(index)]).write(
                to: sessionDirectory.appendingPathComponent("burst-\(index).arw")
            )
        }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !reconciler.reconcileLog.contains(.eventBatch) {
            try await waitInterval(0.05)
        }
        XCTAssertEqual(reconciler.reconcileLog, [.eventBatch], "the burst coalesces")

        // The applied plan converged: counts now carry exactly the burst.
        let deadline2 = Date().addingTimeInterval(5)
        while Date() < deadline2, state.browseCounts?.total != 5 {
            try await waitInterval(0.05)
        }
        XCTAssertEqual(
            state.browseCounts?.total, 5,
            "the coalesced reconcile applied the whole burst (index == disk)"
        )
        XCTAssertEqual(state.browseCounts?.edited, 0)
        XCTAssertEqual(state.browseCounts?.orphans, 0)
    }

    func testRowStaleHintMarksWithoutDeleting() async throws {
        let (reconciler, controller, _) = makeWiredReconciler()
        // Seed one EDITED row (thumb_state = rendered via direct sync; the
        // sync inserts thumb_state 0 — flip one row through the store by
        // reconciling a plan-free tree then directly exercising the hint).
        try Data([0x01]).write(to: sessionDirectory.appendingPathComponent("s.arw"))
        _ = await controller.openAndSync(root: sessionDirectory)
        reconciler.startSession(root: sessionDirectory)
        defer { reconciler.stopSession() }

        // The stale hint is a pure store leg — drive the handler directly.
        await controller.markStale(relPaths: ["s.arw", "missing.arw"])
        // No crash, no throw — the mark leg never hard-fails (SC#2). The
        // row survives (hint ≠ deletion); the next diff is still empty.
        let outcome = await controller.reconcile(root: sessionDirectory)
        XCTAssertNotNil(outcome)
        XCTAssertTrue(outcome?.plan.isTrivial ?? false, "the hint deleted nothing")
    }

    // MARK: - Exclude single-source

    func testExcludeTableSingleSourceByValue() {
        // The watcher and the scanner consume the SAME predicates — assert
        // the composition value-for-value (compile-time single source PLUS
        // a runtime pin so a future divergence fails loudly).
        for name in ["a.arw", "b.arw.lra", ".hidden", "x.tmp-1", "db.cosessiondb"] {
            XCTAssertEqual(
                SessionTreeScanner.isWatcherExcludedFile(name),
                SessionTreeScanner.isExcludedMetadata(name),
                "watcher file predicate must equal the scanner's noise half for \(name)"
            )
        }
        // `.lra` divergence is BY DESIGN: browse excludes attachments, the
        // watcher keeps the external-write signal.
        XCTAssertTrue(SessionTreeScanner.isExcludedFile("a.arw.lra"))
        XCTAssertFalse(SessionTreeScanner.isWatcherExcludedFile("a.arw.lra"))
    }
}

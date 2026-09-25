import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// Plan 09-01 T1 — the session orchestration suite:
//
//   • recent list vectors (dedupe-move-front / cap 10 / prune missing /
//     persistence round-trip through an ISOLATED UserDefaults suite)
//   • the open/switch teardown five-step ORDER (spy closures record steps;
//     RESEARCH §1.4: flush → cancelThumbnails → invalidateRenderer →
//     closeIndex → updateSessionState, then ensureDirectories → syncIndex →
//     promoteRecent)
//   • first-open fast path (the flush/teardown leg is idempotent no-op)
//   • first-image routing (L012: the SAME-window EditorState.load path —
//     one route call per open)
//   • the ensureDirectories failure path (watch falls back, sync skipped)
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class SessionSwitchTests: XCTestCase {

    private var tempDirectory: URL!
    private var defaultsSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("sessionswitch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true
        )
        defaultsSuiteName = "test.session.\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        if let suiteName = defaultsSuiteName {
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// A real (existing) directory URL inside the temp tree.
    private func makeSessionDir(named name: String) -> URL {
        let url = tempDirectory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: defaultsSuiteName)!
    }

    /// A coordinator + state pair with per-step spy recording.
    private func makeWired(
        ensureThrows: Bool = false,
        syncResult: SessionCoordinator.SessionOpenSyncResult? = nil
    ) -> (SessionCoordinator, SessionState, () -> [String]) {
        let state = SessionState(recentDefaults: makeDefaults())
        var steps: [String] = []
        let lock = NSLock()
        func record(_ name: String) {
            lock.lock()
            steps.append(name)
            lock.unlock()
        }
        let coordinator = SessionCoordinator(
            flushCurrentImage: { record("flush") },
            teardownRenderer: { record("invalidateRenderer") },
            cancelThumbnailTasks: { record("cancelThumbnails") },
            closeIndexHandler: { record("closeIndex") },
            ensureDirectoriesHandler: { url in
                if ensureThrows {
                    throw NSError(domain: "test", code: 1)
                }
                record("ensureDirectories(\(url.lastPathComponent))")
            },
            syncIndexHandler: { url in
                record("syncIndex(\(url.lastPathComponent))")
                return syncResult ?? SessionCoordinator.SessionOpenSyncResult()
            },
            routeImage: { url in
                record("routeImage(\(url.lastPathComponent))")
            },
            reportError: { message in
                record("reportError(\(message))")
            }
        )
        coordinator.appState = state
        return (coordinator, state, { steps })
    }

    // MARK: - Recent list vectors

    func testRecentDedupeMovesToFront() {
        let state = SessionState(recentDefaults: makeDefaults())
        let a = makeSessionDir(named: "a")
        let b = makeSessionDir(named: "b")
        let c = makeSessionDir(named: "c")

        state.promoteRecent(a)
        state.promoteRecent(b)
        state.promoteRecent(c)
        XCTAssertEqual(
            state.recentSessions, [c, b, a],
            "promote order must be most-recent-first"
        )
        state.promoteRecent(a)
        XCTAssertEqual(
            state.recentSessions, [a, c, b],
            "re-promote must DEDUPE and move to front, not duplicate"
        )
        XCTAssertEqual(state.recentSessions.count, 3, "dedupe must not grow the list")
    }

    func testRecentCapTen() {
        let state = SessionState(recentDefaults: makeDefaults())
        for i in 0..<14 {
            state.promoteRecent(makeSessionDir(named: "s\(i)"))
        }
        XCTAssertEqual(
            state.recentSessions.count, SessionState.recentLimit,
            "recent list must cap at \(SessionState.recentLimit)"
        )
        // The OLDEST entries (s0, s1, s2, s3) must be the evicted tail.
        XCTAssertFalse(
            state.recentSessions.contains(where: { $0.lastPathComponent == "s0" }),
            "oldest entry must be evicted past the cap"
        )
        XCTAssertEqual(state.recentSessions.first?.lastPathComponent, "s13")
        XCTAssertEqual(state.recentSessions.last?.lastPathComponent, "s4")
    }

    func testRecentPrunesMissingPathsOnPromoteAndLoad() {
        let state = SessionState(recentDefaults: makeDefaults())
        let keep = makeSessionDir(named: "keep")
        let doomed = makeSessionDir(named: "doomed")
        state.promoteRecent(doomed)
        state.promoteRecent(keep)
        try? FileManager.default.removeItem(at: doomed)

        // On promote: the missing path ahead of the promoted one is pruned.
        state.promoteRecent(keep)
        XCTAssertEqual(
            state.recentSessions.map(\.lastPathComponent), ["keep"],
            "missing paths must be pruned on promote"
        )

        // On load: a persisted missing path is dropped at init.
        let gone = makeSessionDir(named: "gone")
        state.promoteRecent(gone)
        let persistedPaths = state.recentSessions.map(\.path)
        makeDefaults().set(persistedPaths, forKey: SessionState.recentStorageKey)
        try? FileManager.default.removeItem(at: gone)
        let reloaded = SessionState(recentDefaults: makeDefaults())
        XCTAssertEqual(
            reloaded.recentSessions.map(\.lastPathComponent), ["keep"],
            "missing paths must be pruned at load"
        )
    }

    func testRecentPersistenceRoundTrip() {
        let suite = makeDefaults()
        let state = SessionState(recentDefaults: suite)
        let a = makeSessionDir(named: "alpha")
        let b = makeSessionDir(named: "beta")
        state.promoteRecent(a)
        state.promoteRecent(b)

        let reloaded = SessionState(recentDefaults: suite)
        XCTAssertEqual(
            reloaded.recentSessions, [b, a],
            "recent list must survive a state-object reload (UserDefaults)"
        )
    }

    // MARK: - Open/switch orchestration

    func testFirstOpenRunsStepsInOrder() async {
        let (coordinator, state, steps) = makeWired()
        let session = makeSessionDir(named: "first")

        await coordinator.openSession(url: session)

        XCTAssertEqual(
            coordinator.stepLog.map(\.rawValue),
            [
                "flush", "cancelThumbnails", "invalidateRenderer", "closeIndex",
                "updateSessionState", "ensureDirectories", "syncIndex",
                "promoteRecent",
            ],
            "first open = teardown leg no-op through the SAME five-step path, "
                + "then directories → sync → recent (RESEARCH §1.4)"
        )
        XCTAssertEqual(
            steps().count, 6,
            "every recorded step actually invoked its closure "
                + "(updateSessionState is the coordinator's own write)"
        )
        XCTAssertEqual(state.currentSessionURL, session.standardizedFileURL)
        XCTAssertEqual(state.folderWatchStatus, .synced)
        XCTAssertEqual(state.recentSessions.first, session.standardizedFileURL)
    }

    func testSwitchRunsFiveTeardownStepsBeforeStateUpdate() async {
        let (coordinator, state, steps) = makeWired()
        let a = makeSessionDir(named: "alpha")
        let b = makeSessionDir(named: "beta")
        await coordinator.openSession(url: a)

        await coordinator.openSession(url: b)

        let log = coordinator.stepLog.map(\.rawValue)
        let firstOpenLength = 8
        let switchLog = Array(log.dropFirst(firstOpenLength))
        // The five-step teardown prefix, IN ORDER, then the new-session leg.
        XCTAssertEqual(
            Array(switchLog.prefix(5)),
            ["flush", "cancelThumbnails", "invalidateRenderer", "closeIndex",
             "updateSessionState"],
            "switch must run the teardown five steps IN ORDER"
        )
        XCTAssertEqual(
            switchLog,
            ["flush", "cancelThumbnails", "invalidateRenderer", "closeIndex",
             "updateSessionState", "ensureDirectories", "syncIndex",
             "promoteRecent"],
            "switch and open share ONE path (L012)"
        )
        XCTAssertEqual(steps().count, 6 + 6, "closures fired on both opens")
        _ = state // state assertions live in the dedicated tests below
    }

    func testOpenRoutesFirstImageOnce() async {
        let first = makeSessionDir(named: "shoot")
            .appendingPathComponent("DSC0001.ARW")
        let (coordinator, _, steps) = makeWired(
            syncResult: SessionCoordinator.SessionOpenSyncResult(
                counts: SessionBrowseCounts(total: 12, edited: 3, orphans: 0),
                firstImage: first
            )
        )

        await coordinator.openSession(url: makeSessionDir(named: "shoot"))

        XCTAssertEqual(
            steps().filter { $0.hasPrefix("routeImage") }.count, 1,
            "exactly ONE same-window route per open (L012 probe — no window/odoc fan-out)"
        )
    }

    func testOpenSyncFailureKeepsStateAndReports() async {
        let (coordinator, state, steps) = makeWired(
            syncResult: SessionCoordinator.SessionOpenSyncResult(failed: true)
        )

        await coordinator.openSession(url: makeSessionDir(named: "broken"))

        XCTAssertEqual(state.folderWatchStatus, .notWatching, "failed sync → not watching")
        XCTAssertEqual(
            steps().filter { $0.hasPrefix("reportError") }.count, 0,
            "sync failure is reported BY the sync handler, not double-reported"
        )
    }

    func testEnsureDirectoriesFailureAbortsOpenLeg() async {
        let (coordinator, state, steps) = makeWired(ensureThrows: true)

        await coordinator.openSession(url: makeSessionDir(named: "nope"))

        XCTAssertEqual(state.currentSessionURL, nil, "failed open must not leave a bound session")
        XCTAssertFalse(steps().contains(where: { $0.hasPrefix("syncIndex") }))
        XCTAssertFalse(steps().contains("promoteRecent"), "no promote on failed open")
        XCTAssertEqual(
            steps().filter { $0.hasPrefix("reportError") }.count, 1,
            "the failure is reported once"
        )
        XCTAssertEqual(state.folderWatchStatus, .notWatching)
    }

    // MARK: - SessionState watch-status state machine

    func testWatchStatusEnumDisplayKeys() {
        // L025 anchors: each status has a distinct catalog key.
        let keys = [
            FolderWatchStatus.notWatching.displayKey,
            FolderWatchStatus.scanning.displayKey,
            FolderWatchStatus.synced.displayKey,
            FolderWatchStatus.stale.displayKey,
        ]
        XCTAssertEqual(Set(keys).count, 4, "four distinct display keys")
        for key in keys {
            XCTAssertTrue(key.hasPrefix("session_watch_"), key)
        }
    }

    func testBrowseCountsSnapshotPublishesAndClears() {
        let state = SessionState(recentDefaults: makeDefaults())
        XCTAssertNil(state.browseCounts)
        state.setBrowseCounts(SessionBrowseCounts(total: 5, edited: 1, orphans: 2))
        XCTAssertEqual(state.browseCounts, SessionBrowseCounts(total: 5, edited: 1, orphans: 2))
        state.setCurrentSession(nil)
        XCTAssertNil(state.browseCounts, "closing the session clears the counts snapshot")
    }
}

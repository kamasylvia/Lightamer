import Foundation
import LightamerCore
import Observation
import os

// ─────────────────────────────────────────────────────────────────────────────
// SessionCoordinator (Plan 09-01 T1) — the open/switch/teardown orchestrator.
//
// SESS-01/04: "folder = session" is PURE app-layer orchestration — Core is
// untouched, and the existing single-image load path (`EditorState.load` →
// `PipeCoordinator.load`) stays the only render route. This coordinator owns
// the SESSION lifecycle around it:
//
//   openSession(url):
//     ① flush the outgoing image's pending sidecar   (flushNow semantics)
//     ② TEARDOWN five steps (09-RESEARCH §1.4):
//          flush → thumbnail-task cancel seam → `cache.invalidateAll()` +
//          `clearCICaches()` + D-C2 sweep → index close → SessionState update
//     ③ idempotent Capture/Crop/Output creation      (SessionLayout, T2)
//     ④ open the index + incremental sync            (SessionIndexStore, T4)
//     ⑤ recent-list promote (dedupe-move-front, cap 10)
//
// Switching sessions and opening a recent entry take EXACTLY this one path
// (L012: same-window routing; the WindowGroup odoc model stays banned —
// LightamerApp.swift's `Window("Lightamer", id: "main")` comment is the
// canonical rationale).
//
// D-03b: the coordinator holds NO references to EditorState/PipeCoordinator/
// SessionState. Every cross-object hop is an injected closure — the app root
// wires them in `LightamerApp` (the same shape as the openHandler/
// terminateHandler closures). The recorded `stepLog` lets tests assert the
// five-step ORDER with spy closures.
// ─────────────────────────────────────────────────────────────────────────────

@Observable
@MainActor
final class SessionCoordinator {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "session"
    )

    /// Orchestration step names recorded in `stepLog` (test assertions pin
    /// the five-step teardown ORDER).
    enum Step: String, Sendable {
        case flush
        case cancelThumbnails
        case invalidateRenderer
        case closeIndex
        case updateSessionState
        case ensureDirectories
        case syncIndex
        case promoteRecent
        case routeFirstImage
    }

    /// Ordered record of the steps the last `openSession` executed (tests).
    private(set) var stepLog: [Step] = []

    // MARK: - Injection seams (D-03b — closures, never state references)
    //
    // Settable post-init: the app root constructs with defaults and wires
    // the REAL closures in `.task` (the same shape as AppDelegate's
    // openHandler/terminateHandler). Tests inject at init.

    /// ① `PipeCoordinator.flushSidecar()` (flushNow semantics).
    private var flushCurrentImage: () async -> Void

    /// ②-c `cache.invalidateAll()` + `clearCICaches()` + the D-C2 sweep —
    /// `PipeCoordinator.prepareForSessionSwitch()`.
    private var teardownRenderer: () async -> Void

    /// ②-b the thumbnail-pipeline task cancel SEAM. 9-1 has no background
    /// thumbnail tasks yet (the 9-3 provider lands them); the closure is
    /// the spy/count anchor for the leak assertion (SESS-04).
    private var cancelThumbnailTasks: () -> Void

    /// ②-d close the CURRENT session's index DB (before the state update).
    private var closeIndexHandler: () async -> Void

    /// ③ `SessionLayout.ensureDirectories(at:)` (T2 wires the real one).
    private var ensureDirectoriesHandler: (URL) throws -> Void

    /// ④ open the index + incremental sync; returns the sidebar counts and
    /// the first browsable image (routed into the editor, T4 wires real).
    private var syncIndexHandler: (URL) async -> SessionOpenSyncResult

    /// First-image routing after a session open — the EXISTING
    /// `EditorState.load` path (same window, L012). Skipped when nil.
    private var routeImage: ((URL) -> Void)?

    /// D-26 background error reporting (app root wires a toast).
    private var reportError: ((String) -> Void)?

    /// Plan 09-02 T4: the orphan reconcile actions (the app root wires them
    /// to the index controller; the defaults keep the 09-01 test wiring a
    /// no-op). REMOVE returns false on failure — the UI surfaces a no-op,
    /// never an error (SC#2).
    var removeOrphanSidecar: (String) async -> Bool = { _ in false }
    var ignoreOrphanSidecar: (String) async -> Void = { _ in }

    /// Plan 16-2 T6 (RQ-16-10): the EDIT-LOOP projection hook — returning
    /// from the editor to the Catalogs grid projects the edited session
    /// (the 16-1 single-session entry; the guard lives inside the
    /// projector, so a disabled Catalogs mode is a cheap no-op).
    var projectToCatalog: (URL) async -> Void = { _ in }

    /// Plan 16-2 T6 (RQ-16-4 trigger face c): the Catalogs-mode startup
    /// sweep — entering Catalogs mode / enabling the mode sweeps every
    /// registered + recent session in the BACKGROUND (never the first
    /// frame budget; RQ-16-4: the grid shows the committed state).
    var sweepCatalog: ([URL]) async -> Void = { _ in }

    /// Plan 13-3 T4 (SYS-04, D-13-CONTEXT-7): the drop-import seam — the
    /// app root wires the orchestration (ImportService copy/move into
    /// the session ROOT — D-09-CONTEXT-3 excludes the `Capture/` tier
    /// from the browse set, 13-3-DECISIONS — + the EXPLICIT reconcile
    /// ingest + the grid reload).
    /// `move` = the caller's Option-modifier intent; false (the default
    /// path) copies. nil (the default) = no drop targets wired.
    var importHandler: ((_ urls: [URL], _ move: Bool) async -> Void)?

    init(
        flushCurrentImage: @escaping () async -> Void = {},
        teardownRenderer: @escaping () async -> Void = {},
        cancelThumbnailTasks: @escaping () -> Void = {},
        closeIndexHandler: @escaping () async -> Void = {},
        ensureDirectoriesHandler: @escaping (URL) throws -> Void = { _ in },
        syncIndexHandler: @escaping (URL) async -> SessionOpenSyncResult = { _ in
            SessionOpenSyncResult()
        },
        routeImage: ((URL) -> Void)? = nil,
        reportError: ((String) -> Void)? = nil
    ) {
        self.flushCurrentImage = flushCurrentImage
        self.teardownRenderer = teardownRenderer
        self.cancelThumbnailTasks = cancelThumbnailTasks
        self.closeIndexHandler = closeIndexHandler
        self.ensureDirectoriesHandler = ensureDirectoriesHandler
        self.syncIndexHandler = syncIndexHandler
        self.routeImage = routeImage
        self.reportError = reportError
    }

    /// ④'s result: sidebar counts + the first browsable image of the NEW
    /// session (routed into the editor so the single window never shows a
    /// stale cross-session frame). `failed` = the sync errored (watch
    /// status falls back to `.notWatching`).
    struct SessionOpenSyncResult: Sendable {
        var counts: SessionBrowseCounts?
        var firstImage: URL?
        var failed: Bool = false

        init(
            counts: SessionBrowseCounts? = nil, firstImage: URL? = nil,
            failed: Bool = false
        ) {
            self.counts = counts
            self.firstImage = firstImage
            self.failed = failed
        }
    }

    // MARK: - Open / switch / recent (ONE path — L012)

    /// Open (or switch to) the session rooted at `url`. Idempotent for an
    /// already-current URL (re-promotes recent, re-syncs the index).
    func openSession(url: URL) async {
        let root = url.standardizedFileURL
        Self.logger.info("open session: \(root.path, privacy: .public)")

        // ① flush the outgoing image's pending sidecar (flushNow semantics;
        // a no-op when nothing is loaded — the closure itself is idempotent).
        stepLog.append(.flush)
        await flushCurrentImage()

        // ② teardown five steps (flush above → cancel seam → invalidate +
        // CI sweep → index close → state update).
        stepLog.append(.cancelThumbnails)
        cancelThumbnailTasks()

        stepLog.append(.invalidateRenderer)
        await teardownRenderer()

        stepLog.append(.closeIndex)
        await closeIndexHandler()

        stepLog.append(.updateSessionState)
        appState?.setCurrentSession(root)
        appState?.setWatchStatus(.scanning)

        // ③ idempotent Capture/Crop/Output creation (C1 convention; D-09-
        // CONTEXT-3: Trash/Selects are NOT created). Failure = the folder
        // is not usable as a session: unbind (no half-open state), report.
        stepLog.append(.ensureDirectories)
        do {
            try ensureDirectoriesHandler(root)
        } catch {
            Self.logger.error(
                "session directory creation failed: \(error.localizedDescription, privacy: .public)"
            )
            appState?.setCurrentSession(nil)
            appState?.setWatchStatus(.notWatching)
            reportError?(String(localized: "toast_session_open_failed"))
            return
        }

        // ④ open the index + incremental single-transaction sync.
        stepLog.append(.syncIndex)
        let sync = await syncIndexHandler(root)
        appState?.setBrowseCounts(sync.counts)
        appState?.setWatchStatus(sync.failed ? .notWatching : .synced)

        // ⑤ recent promote (dedupe-move-front, cap, prune missing).
        stepLog.append(.promoteRecent)
        appState?.promoteRecent(root)

        // Keep the single editor coherent: route the new session's first
        // browsable image through the EXISTING load path (same window,
        // L012; the 9-3 grid takes over the visual model).
        if let first = sync.firstImage {
            stepLog.append(.routeFirstImage)
            routeImage?(first)
        }
    }

    /// The SessionState this coordinator writes (injected post-init by the
    /// app root — NOT a D-03b state reference held at construction; the
    /// coordinator only ever WRITES the four documented entries).
    var appState: SessionState?

    /// App-root wiring (runs once in `LightamerApp`'s `.task`, after the
    /// state objects exist; mirrors the openHandler/terminateHandler
    /// closure pattern). Tests skip this and inject at init.
    func configure(
        appState: SessionState,
        flushCurrentImage: @escaping () async -> Void,
        teardownRenderer: @escaping () async -> Void,
        cancelThumbnailTasks: @escaping () -> Void = {},
        closeIndexHandler: @escaping () async -> Void = {},
        ensureDirectoriesHandler: @escaping (URL) throws -> Void = { _ in },
        syncIndexHandler: @escaping (URL) async -> SessionOpenSyncResult = { _ in
            SessionOpenSyncResult()
        },
        routeImage: ((URL) -> Void)? = nil,
        reportError: ((String) -> Void)? = nil
    ) {
        self.appState = appState
        self.flushCurrentImage = flushCurrentImage
        self.teardownRenderer = teardownRenderer
        self.cancelThumbnailTasks = cancelThumbnailTasks
        self.closeIndexHandler = closeIndexHandler
        self.ensureDirectoriesHandler = ensureDirectoriesHandler
        self.syncIndexHandler = syncIndexHandler
        self.routeImage = routeImage
        self.reportError = reportError
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SessionIndexController (Plan 09-01 T4) — the App-side owner of the
// `SessionIndexStore` + the real ④/②-d closure bodies. The controller is the
// ONLY App object that talks to the store; the coordinator sees closures.
// The scan stream comes from `SessionTreeScanner` (App — the exclude table's
// home), the store lives in Core.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class SessionIndexController {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "session-index-ctl"
    )

    private var store: SessionIndexStore?

    /// Plan 16-1 T2 — the app-level catalog projector (ONE .lcat writer
    /// per process; CatalogIndexStore opens its own read connection).
    ///
    /// Plan 16-2 T1: `var` — the location preference (RQ-16-1②) rebuilds
    /// the shared pair on a re-point via `repointSharedCatalog`. All reads
    /// and writes stay on the MainActor (the SessionIndexController is
    /// @MainActor and so is every access site); `nonisolated(unsafe)` only
    /// lifts the static-isolation flag for the provider closure below.
    nonisolated(unsafe) static var sharedCatalogProjector = CatalogProjector()

    /// Plan 16-2 T1 (the 16-1 handover): the shared READ store singleton —
    /// ONE `CatalogIndexStore` per process, rebuilt by the same re-point,
    /// its COUNT memo invalidated by the projector's `countsInvalidator`
    /// hook (wired at build time below). The Catalogs UI (browser model,
    /// smart-album evaluation, thumbnail router) consumes THIS instance.
    nonisolated(unsafe) static var sharedCatalogStore = CatalogIndexStore()

    /// Plan 16-3 T3: the organization write/read face singleton (categories
    /// tree / collections / memberships — the catalog's OWN asset). Same
    /// lifecycle as the pair above: rebuilt by the re-point, its
    /// membership-affecting COMMITs killing the shared READ store's COUNT
    /// memo via the invalidator wired at build time.
    nonisolated(unsafe) static var sharedCatalogOrganization =
        CatalogOrganizationStore()

    /// The location the shared pair currently targets (re-point idempotence;
    /// nil = not yet built this launch — the first repoint always builds so
    /// the invalidator wiring is guaranteed).
    nonisolated(unsafe) private static var sharedCatalogURL: URL?

    /// Plan 16-2 T2: fired after every `repointSharedCatalog` rebuild — the
    /// app root re-binds the Catalogs consumers (browser model / thumbnail
    /// router) to the NEW store instance (the old instance's handles are
    /// closed by then).
    nonisolated(unsafe) static var sharedCatalogStoreRebuilt:
        ((CatalogIndexStore) -> Void)?

    /// Plan 16-4 T2 — the destructive-rebuild support seam: close the shared
    /// trio WITHOUT recreating (and clear `sharedCatalogURL` so a subsequent
    /// `repointSharedCatalog` at the SAME url re-runs). The CatalogRebuilder's
    /// rename promotion requires every writer of the outgoing `.lcat` closed
    /// first — a live handle would keep writing into the orphaned inode.
    static func closeSharedCatalogHandles() async {
        await sharedCatalogProjector.close()
        await sharedCatalogStore.close()
        await sharedCatalogOrganization.close()
        sharedCatalogURL = nil
    }

    /// Plan 16-2 T1 — the location preference's runtime leg (RQ-16-1②:
    /// re-point, never migrate). Closes the outgoing handles FIRST, rebuilds
    /// the projector + store pair at `url`, and wires the COUNT-memo
    /// invalidation. When Catalogs is enabled the tail-touch creates an
    /// EMPTY `.lcat` on demand (RQ-16-1③ — the schema-apply read, never a
    /// bare file write); a disabled Catalogs mode never creates the file.
    /// Idempotent per URL.
    static func repointSharedCatalog(databaseURL url: URL) async {
        guard sharedCatalogURL != url else { return }
        await sharedCatalogProjector.close()
        await sharedCatalogStore.close()
        await sharedCatalogOrganization.close()
        let projector = CatalogProjector(databaseURL: url)
        let store = CatalogIndexStore(databaseURL: url)
        let organization = CatalogOrganizationStore(databaseURL: url)
        await projector.setCountsInvalidator { [store] in
            await store.invalidateCounts()
        }
        await organization.setCountsInvalidator { [store] in
            await store.invalidateCounts()
        }
        sharedCatalogProjector = projector
        sharedCatalogStore = store
        sharedCatalogOrganization = organization
        sharedCatalogURL = url
        if CatalogPreferences.catalogsEnabled() {
            _ = try? await store.fetchSessions()
        }
        sharedCatalogStoreRebuilt?(store)
    }

    /// The projection-hook seam (tests inject a temp-directory factory;
    /// the default wires the shared projector). The enable guard runs
    /// BEFORE the factory, so a disabled Catalogs mode never constructs or
    /// touches a projector — zero .lcat handles on the Sessions path.
    var catalogProjectorProvider: () -> CatalogProjector? = {
        SessionIndexController.sharedCatalogProjector
    }

    /// The CURRENT store (Plan 09-3 wiring: the thumbnail provider binds to
    /// it after each open; nil before the first open / after a close).
    var currentStore: SessionIndexStore? { store }

    /// Plan 09-3 progressive-ingest seam: every scanner page lands here
    /// BEFORE the sync transaction commits (the grid's placeholder cells
    /// render while the walk runs). App-root wired to the browser model.
    var scanPageObserver: ((SessionScanPage) -> Void)?

    /// ④ the real sync leg: open + scan + single-transaction diff.
    func openAndSync(root: URL) async -> SessionCoordinator.SessionOpenSyncResult {
        let store = SessionIndexStore(sessionRoot: root)
        self.store = store
        do {
            let result = try await store.openSession(
                root: root, scan: SessionTreeScanner.scan(root: root)
            )
            Self.logger.info(
                "index sync: +\(result.added) -\(result.removed) ~\(result.changed) orphans \(result.orphanAdded)/\(result.orphanRemoved)"
            )
            var syncResult = SessionCoordinator.SessionOpenSyncResult(
                counts: SessionBrowseCounts(
                    total: result.counts.total,
                    edited: result.counts.edited,
                    orphans: result.counts.orphans
                )
            )
            if let first = result.firstImageRelPath {
                syncResult.firstImage = root.appendingPathComponent(first)
            }
            // Plan 16-1 T2 — the catalog projection hook (RQ-16-4 trigger
            // face a): the five-step open+sync has RETURNED; the projection
            // runs in a detached background task (never the open budget —
            // pull-on-open, lag is harmless). The enable guard lives INSIDE
            // CatalogProjector.project, BEFORE any handle exists — a
            // disabled Catalogs mode runs this task only to return
            // skippedByGuard: zero .lcat handles end-to-end.
            if let projector = catalogProjectorProvider() {
                Task.detached(priority: .utility) {
                    _ = try? await projector.project(sessionRoot: root)
                }
            }
            return syncResult
        } catch {
            Self.logger.error(
                "index sync failed: \(error.localizedDescription, privacy: .public)"
            )
            await store.close()
            self.store = nil
            return SessionCoordinator.SessionOpenSyncResult(failed: true)
        }
    }

    /// ②-d close the index (before the next session's sync opens a new one).
    func close() async {
        await store?.close()
        store = nil
    }

    // MARK: - Reconcile (Plan 09-02 T3)

    /// The reconcile outcome: the pure-diff PLAN (the App logs it, the
    /// sidebar counts follow the apply) + the post-apply counts + the
    /// actionable orphan snapshot (ignored filtered).
    struct SessionReconcileOutcome: Sendable {
        var plan: ReconcilePlan
        var counts: SessionBrowseCounts?
        var orphanRelPaths: [String] = []

        init(
            plan: ReconcilePlan, counts: SessionBrowseCounts? = nil,
            orphanRelPaths: [String] = []
        ) {
            self.plan = plan
            self.counts = counts
            self.orphanRelPaths = orphanRelPaths
        }
    }

    /// The reconcile WORK (the injected handler's real body): scan → pure
    /// diff → single-transaction apply (rename rulings included) → the
    /// NULL-class backfills re-read drifted sidecars (真身恒 sidecar).
    /// Errors are logged and returned as nil — a failed reconcile never
    /// hard-fails into the UI (SC#2).
    func reconcile(root: URL) async -> SessionReconcileOutcome? {
        guard let store else { return nil }
        do {
            let (entries, orphans) = await SessionTreeScanner.collect(root: root)
            let previousRows = try await store.fetchAllRows()

            // The externalEdits ruling needs the CURRENT sidecar mtimes —
            // stat only the DRIFT candidates (the changed set is small; a
            // whole-tree sidecar stat would defeat the point on USB).
            let currentByKey = Dictionary(
                uniqueKeysWithValues: entries.map { ($0.relPath, $0) }
            )
            var sidecarMtimes: [String: Double] = [:]
            for row in previousRows where row.orphanSidecar != 1 {
                guard let entry = currentByKey[row.path] else { continue }
                guard row.fileMtime != entry.mtime || row.fileSize != entry.size
                else { continue }
                let sidecarURL = LightamerSidecar.sidecarURL(
                    for: root.appendingPathComponent(row.path)
                )
                if let attributes = try? FileManager.default.attributesOfItem(
                    atPath: sidecarURL.path
                ),
                   let modified = attributes[.modificationDate] as? Date {
                    sidecarMtimes[row.path] = modified.timeIntervalSince1970
                }
            }

            let snapshot = ReconcileScanSnapshot(
                entries: entries,
                sidecarMtimes: sidecarMtimes,
                orphanSidecars: orphans
            )
            let plan = ReconcileDiff.diff(
                previousRows: previousRows, current: snapshot
            )
            let result = try await store.reconcile(
                root: root,
                scan: Self.stream(of: entries, orphans: orphans),
                renames: plan.renamedSurvived
            )
            Self.logger.info(
                "reconcile apply: +\(result.added) -\(result.removed) ~\(result.changed) ⇄\(plan.renamedSurvived.count) orphans \(result.orphanAdded)/\(result.orphanRemoved)"
            )
            return SessionReconcileOutcome(
                plan: plan,
                counts: SessionBrowseCounts(
                    total: result.counts.total,
                    edited: result.counts.edited,
                    orphans: result.counts.orphans
                ),
                orphanRelPaths: await store.actionableOrphanRelPaths()
            )
        } catch {
            Self.logger.error(
                "reconcile failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// The row-level stale hint leg (thumbnail/pipe caches; rows are never
    /// deleted here — the diff's stat ruling owns removals).
    func markStale(relPaths: Set<String>) async {
        guard let store, !relPaths.isEmpty else { return }
        _ = try? await store.markRowsStale(relPaths: relPaths)
    }

    // MARK: - Orphan actions (Plan 09-02 T4 — NEVER hard-fail into the UI)

    /// REMOVE: `.lra` file + classification row, then the actionable
    /// snapshot refresh. False on failure — the caller surfaces a no-op.
    func removeOrphanSidecar(root: URL, relPath: String) async -> Bool {
        guard let store else { return false }
        let removed = await store.removeOrphanSidecar(root: root, relPath: relPath)
        return removed
    }

    /// IGNORE: persist the flag; the row stays (stable classification).
    func setOrphanIgnored(relPath: String, ignored: Bool) async {
        await store?.setOrphanIgnored(relPath: relPath, ignored: ignored)
    }

    /// The current actionable orphan snapshot (post-action refresh).
    func actionableOrphans() async -> [String] {
        await store?.actionableOrphanRelPaths() ?? []
    }

    /// A plain finished stream over already-collected pages (the store's
    /// reconcile consumes the same shape the scanner produces live).
    private static func stream(
        of entries: [SessionScanEntry], orphans: [String]
    ) -> AsyncStream<SessionScanPage> {
        AsyncStream { continuation in
            if !entries.isEmpty {
                continuation.yield(SessionScanPage(entries: entries))
            }
            if !orphans.isEmpty {
                continuation.yield(SessionScanPage(orphanSidecarRelPaths: orphans))
            }
            continuation.finish()
        }
    }
}

import AppKit
import Foundation
import LightamerCore
import Observation
import os

// ─────────────────────────────────────────────────────────────────────────────
// SessionReconciler (Plan 09-02 T3) — the four-schedule reconcile owner.
//
// SESS-05: external changes converge into the index through reconcile —
// the FSEvents watcher only ever HINTS. Four trigger points
// (09-RESEARCH §4.3):
//
//   ① session open     — the full incremental sync inside
//                        `SessionCoordinator.openSession` (09-01 T4); the
//                        reconciler's `startSession` arms AFTER it (the app
//                        root composes the watcher lifecycle into the
//                        coordinator's closure seams — no Step-enum change,
//                        the 09-01 stepLog order assertions stay intact).
//   ② app focus gain   — NSApplication.didBecomeActiveNotification forces
//                        a reconcile (the dropped-events countermeasure:
//                        whatever FSEvents missed while backgrounded is
//                        re-ruled by the diff).
//   ③ event batch      — debounced (300 ms, the coalescing window); the
//                        batch's surviving paths drive the row-stale hint.
//   ④ forced full      — WatchRoot / MustScanSubDirs / a 4096-cap
//                        truncated batch escalates immediately, and a
//                        rootChanged batch ALSO flips the session state to
//                        `.rootLost` + the recent-path invalidation hint
//                        (never a silent path rewrite, L012).
//
// SELF-FEEDBACK DEFENSE (the 100-sidecars-zero-retrigger assertion):
//   line ① the exclude table — `.lightamer/**`, dotfiles, `*.tmp-*`,
//          `*.cosessiondb` never become events at all (the watcher
//          consumes the scanner's SINGLE-SOURCE predicates);
//   line ② the write journal — SidecarStore journals every successful
//          `.lra` promotion; this reconciler swallows event paths the
//          journal saw within the TTL window (both path spellings — L027).
// A fully-swallowed batch triggers NO reconcile; the residual risk of a
// missed swallow is ONE harmless empty reconcile (idempotent diff), never
// a storm.
//
// D-03b: no state references at construction — `appState` is injected
// post-init (the SessionCoordinator pattern) and only the documented
// entries are written; the index work goes through injected handlers.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class SessionReconciler {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "session-reconcile"
    )

    /// The trigger reason recorded in `reconcileLog` (test + diagnostics).
    enum ReconcileReason: String, Sendable {
        case focus
        case eventBatch
        case forced
    }

    /// The debounce window after an event batch (execution decision —
    /// matches the watcher latency's coalescing window; tests shrink it).
    static let defaultDebounce: Duration = .milliseconds(300)

    // MARK: - Test/diagnostics seams

    /// Every reconcile that RAN, in order (the self-feedback assertion
    /// reads this: event-driven reasons must stay absent during the
    /// sidecar-write storm).
    private(set) var reconcileLog: [ReconcileReason] = []

    /// Event paths swallowed by the write journal (defense line ②).
    private(set) var journalSwallowCount = 0

    // MARK: - Injection seams (D-03b)

    /// The reconcile WORK: scan → pure diff → single-transaction apply.
    /// Injected post-init (the app root wires the SessionIndexController
    /// leg); returns the applied plan for the counts publish.
    var reconcileHandler: ((URL) async -> ReconcilePlan?)?

    /// The row-level stale hint leg (rows marked stale, never deleted).
    var staleMarkHandler: ((Set<String>) async -> Void)?

    /// Post-init state injection (the SessionCoordinator pattern).
    var appState: SessionState?

    // MARK: - Live session wiring

    private var watcher: SessionWatcher?
    private var root: URL?
    private var consumerTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var focusObserver: NSObjectProtocol?
    private let debounce: Duration
    private let journal: SidecarWriteJournal

    init(
        debounce: Duration = SessionReconciler.defaultDebounce,
        journal: SidecarWriteJournal = .shared
    ) {
        self.debounce = debounce
        self.journal = journal
    }

    // MARK: - ① Lifecycle (the open/switch seams)

    /// Arm the watcher + the focus observer for an opened session. Called
    /// by the app root AFTER the open-session sync landed (watching a
    /// half-synced session would race the first reconcile).
    func startSession(root newRoot: URL) {
        stopSession()  // idempotent re-arm (a switch lands here too)
        root = newRoot.standardizedFileURL

        let watcher = SessionWatcher(root: newRoot)
        guard watcher.start() else {
            Self.logger.error(
                "watcher refused to start for \(newRoot.path, privacy: .public)"
            )
            appState?.setWatchStatus(.notWatching)
            return
        }
        self.watcher = watcher

        consumerTask = Task { [weak self] in
            for await batch in watcher.events {
                guard let self else { return }
                await self.handleBatch(batch)
            }
        }

        // ② the focus leg (the dropped-events fallback). Queue .main so the
        // hop into MainActor is trivial; posting is rare.
        focusObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.runReconcile(reason: .focus)
            }
        }

        appState?.setWatchStatus(.synced)
        Self.logger.info("reconciler armed for \(newRoot.path, privacy: .public)")
    }

    /// Disarm everything (session switch teardown / close). Idempotent.
    func stopSession() {
        if let focusObserver {
            NotificationCenter.default.removeObserver(focusObserver)
            self.focusObserver = nil
        }
        debounceTask?.cancel()
        debounceTask = nil
        consumerTask?.cancel()
        consumerTask = nil
        watcher?.stop()
        watcher = nil
        root = nil
    }

    /// Test/diagnostics entry for legs ②/④.
    func forceReconcile(reason: ReconcileReason) async {
        await runReconcile(reason: reason)
    }

    // MARK: - ③/④ Batch handling

    private func handleBatch(_ batch: WatchEventBatch) {
        guard root != nil else { return }

        // ④ the full-rescan escalations.
        if batch.requiresFullRescan {
            if batch.rootChanged {
                // The watched root itself moved: hint + status flip. The
                // path is NEVER silently rewritten (L012).
                Self.logger.warning("watch root changed — full rescan + rootLost")
                appState?.markCurrentSessionRootLost()
            }
            Task { [weak self] in
                await self?.runReconcile(reason: .forced)
            }
            return
        }

        // ② the write-journal swallow (self-feedback defense line two).
        // L027: check BOTH path spellings — FSEvents reports the realized
        // prefix while the writer journalled the URL.path spelling.
        var surviving = Set<String>()
        let prefixPairs = watcherPrefixPairs()
        for path in batch.affectedFilePaths {
            let variants = pathVariants(path, prefixPairs: prefixPairs)
            if variants.contains(where: { journal.containsRecent(path: $0) }) {
                journalSwallowCount += 1
                continue
            }
            surviving.insert(path)
        }
        guard !surviving.isEmpty else {
            // Fully self-swallowed batch: NO reconcile (the storm guard).
            Self.logger.debug("batch fully self-swallowed (\(batch.affectedFilePaths.count) paths)")
            return
        }

        // Row-level stale hint (the rename countermeasure: rows are marked,
        // never deleted — the diff's stat ruling decides). A `.lra` event
        // hints at its ORIGINAL's row (sidecar drift → re-read pending).
        let rowKeys = Set(surviving.map { rowKey(of: $0) })
        Task { [weak self] in
            await self?.staleMarkHandler?(rowKeys)
        }

        // ③ the debounced reconcile (bursts coalesce into ONE full diff).
        scheduleDebouncedReconcile()
    }

    private func scheduleDebouncedReconcile() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: self.debounce)
            } catch {
                return  // superseded by a newer batch
            }
            guard !Task.isCancelled else { return }
            await self.runReconcile(reason: .eventBatch)
        }
    }

    private func runReconcile(reason: ReconcileReason) async {
        guard let root else { return }
        // A rootLost session KEEPS its status through rescans — a rescan
        // cannot unmove a folder (the hint clears only on the next open).
        let rootLost = appState?.currentSessionRootLost ?? false
        if !rootLost {
            appState?.setWatchStatus(.scanning)
        }
        let plan = await reconcileHandler?(root)
        reconcileLog.append(reason)
        if let plan {
            Self.logger.info(
                "reconcile(\(reason.rawValue)): +\(plan.added.count) -\(plan.removed.count) ~\(plan.changed.count) ⇄\(plan.renamedSurvived.count) orphan:\(plan.orphanSidecars.count) ext:\(plan.externalEdits.count)"
            )
        }
        appState?.setWatchStatus(rootLost ? .rootLost : .synced)
        journal.purge()
    }

    // MARK: - Path math (L027 helpers)

    private func watcherPrefixPairs() -> [(url: String, physical: String)] {
        guard let prefixes = watcher?.rootPrefixes, prefixes.count == 2 else { return [] }
        return [(prefixes[0], prefixes[1]), (prefixes[1], prefixes[0])]
    }

    /// Both spellings of an absolute path (the event spelling + the writer
    /// spelling) — the journal check must not miss on the /var mirror.
    private func pathVariants(
        _ path: String, prefixPairs: [(url: String, physical: String)]
    ) -> [String] {
        guard !prefixPairs.isEmpty else { return [path] }
        var out = [path]
        for pair in prefixPairs {
            if path.hasPrefix(pair.physical) {
                out.append(pair.url + path.dropFirst(pair.physical.count))
            } else if path.hasPrefix(pair.url) {
                out.append(pair.physical + path.dropFirst(pair.url.count))
            }
        }
        return out
    }

    /// Event path → the index row key (relative original path, `.lra`
    /// stripped). Unmappable paths yield a key no row carries (the stale
    /// hint no-ops) — never a crash.
    private func rowKey(of path: String) -> String {
        guard let root else { return path }
        let prefixes = watcher?.rootPrefixes ?? [root.path + "/"]
        var relative: String?
        for prefix in prefixes
        where path.hasPrefix(prefix) && path.count > prefix.count {
            relative = String(path.dropFirst(prefix.count))
            break
        }
        guard var rel = relative else { return path }
        if rel.hasSuffix(".lra") { rel = String(rel.dropLast(4)) }
        return rel
    }
}

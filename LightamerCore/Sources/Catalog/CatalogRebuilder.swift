import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// CatalogRebuilder (Plan 16-4 T2) — the TWO-MODE full rebuild (RQ-16-14, the
// research correction ②).
//
// The context teaching this implements (16-3 SUMMARY's organization-truth
// section): the METADATA mirror is rebuildable from the session face
// (sidecar → lindex → catalog); the ORGANIZATION data (categories tree /
// collections / memberships) is the catalog's OWN asset — the session face
// does not know it exists. The two rebuild modes differ in exactly that
// boundary:
//
//   ┌─ reconcileRebuild (DEFAULT) ── the row-set integrity repair.
//   │   Zero every `last_projected_epoch`, then re-project every registered
//   │   session through the UPSERT core (the id is KEPT on conflict, R1).
//   │   Organization data FULLY SURVIVES (member references stay valid).
//   │   Applies to: row drift / partial-corruption suspicion / sweep
//   │   catch-up. Cancellable at SESSION boundaries (each session is one
//   │   committed transaction — completed sessions are retained and a rerun
//   │   is idempotent: zeroing re-projects everything, the UPSERT converges).
//   │   Completion copy: 「目录已与 N 个会话对账」.
//   │
//   └─ destructiveRebuild (FILE-LEVEL RECOVERY) ── the `.lcat` is lost /
//       unreadable / `schemaFailed`. NO in-database DELETE-of-everything
//       (F12: deleting 1M rows strands ~470MB of freelist in the old file).
//       Instead: write a FRESH `catalog.lcat.tmp` in the SAME directory,
//       project the session face into it, VERIFY the row counts, then
//       promote by rename (L009 same-directory discipline). The OLD file is
//       kept one step as `catalog.lcat.bak` before the promotion; a failed
//       promotion rolls the `.bak` back — the original stays usable.
//       Organization data is LOST (the fresh file has no categories rows —
//       the honest CONTEXT boundary; the ONLY recovery source is a `.lcat`
//       file backup, RQ-16-15).
//       Completion copy: 「元数据已恢复；分类与集合需从备份恢复或重新整理」.
//
// The session source of truth for BOTH modes = the session FOLDERS (the
// registry's `root_path` set for reconcile; the old registry when readable
// merged with the caller's recent list for destructive). The projector's
// realpath normalization + registry reuse make each root land on a stable
// session_id (L027).
//
// Isolation (the inherited failure semantics): a rebuild NEVER touches the
// session face — projection reads the lindex through a READ-ONLY connection
// inside the projector actor; Sessions mode does not know any of this
// happened. A `schemaFailed` catalog degrades Catalogs mode alone; the
// destructive path EXPECTS the old file to be unreadable and simply proceeds
// from the caller's roots.
// ─────────────────────────────────────────────────────────────────────────────

public actor CatalogRebuilder {

    // MARK: - Typed failures (the rebuild-specific surface)

    public enum RebuildError: Error, Equatable {
        /// destructiveRebuild with the Catalogs enable switch off — a
        /// disabled mode has no catalog to rebuild (the guard is the same
        /// face the projector reads).
        case catalogsDisabled
        /// The freshly built tmp file's row count did not reconcile with the
        /// projection's own accounting. The original file is untouched.
        case verificationFailed(expected: Int, actual: Int)
        /// The same-directory rename promotion failed (or its safety
        /// precondition did not hold — e.g. a `-wal` sidecar still present
        /// after the writer closed). The rollback has restored the original.
        case promotionFailed(reason: String)
    }

    /// Per-session progress (the UI's X/N 浮层 payload).
    public struct RebuildProgress: Sendable, Equatable {
        public var completedSessions: Int
        public var totalSessions: Int

        public init(completedSessions: Int, totalSessions: Int) {
            self.completedSessions = completedSessions
            self.totalSessions = totalSessions
        }
    }

    private let databaseURL: URL
    private let defaultsSuiteName: String?
    private var progressHandler: (@Sendable (RebuildProgress) async -> Void)?

    /// Test seam: the promotion-leg failure injection (the projector's
    /// `CatalogProjectionFailureInjection` precedent — the rollback leg must
    /// be driven, not assumed).
    public enum PromotionFailureInjection: Sendable, Equatable {
        case none
        /// Throw AFTER the old file moved to `.bak`, BEFORE the promotion
        /// rename — drives the rollback leg (the original must come back).
        case afterBackupMove
    }

    private var promotionInjection: PromotionFailureInjection = .none

    public func setPromotionFailureInjection(_ mode: PromotionFailureInjection) {
        promotionInjection = mode
    }

    /// Progress seam (the projector's `setCountsInvalidator` pattern — an
    /// isolated setter so the closure never crosses the actor boundary
    /// unsafely).
    public func setProgressHandler(
        _ handler: (@Sendable (RebuildProgress) async -> Void)?
    ) {
        progressHandler = handler
    }

    /// Injected-location init (the settings face passes the CURRENT
    /// `CatalogPreferencesModel.catalogURL`; tests pass a temp URL — L009:
    /// never external-volume).
    public init(databaseURL: URL, defaultsSuiteName: String? = nil) {
        self.databaseURL = databaseURL
        self.defaultsSuiteName = defaultsSuiteName
    }

    // MARK: - Mode 1: reconcile rebuild (the DEFAULT)

    /// 清水位 → 全会话重投影. Zeroes every registry watermark in ONE bulk
    /// transaction, then re-projects each registered session (plus the
    /// caller's still-existing recent roots that are not yet registered —
    /// the sweep's backfill semantics). Returns the number of sessions
    /// successfully reconciled. Per-session projection failures are SKIPPED
    /// (the `sweepAll` precedent — one broken session must not abort the
    /// library-wide repair) and reported in the progress stream; a task
    /// cancellation aborts at the next session boundary (completed sessions
    /// stay committed).
    @discardableResult
    public func reconcileRebuild(recentRoots: [URL] = []) async throws -> Int {
        guard CatalogPreferences.catalogsEnabled(defaultsSuiteName: defaultsSuiteName) else {
            return 0
        }

        // ① The zero-watermark bulk step (ONE transaction — one bulk change).
        let handle = try openCatalogHandle()
        defer { handle.close() }
        try handle.exec("BEGIN IMMEDIATE")
        do {
            try handle.execute(
                "UPDATE catalog_sessions SET last_projected_epoch = 0")
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }

        // ② The registered roots (the registry is the reconcile's source).
        var roots: [String] = []
        let statement = try handle.prepare(
            "SELECT root_path FROM catalog_sessions ORDER BY root_path")
        while try statement.step() {
            if let path = statement.columnText(0) { roots.append(path) }
        }

        // ③ Merge the caller's not-yet-registered roots (dedupe by the
        // realpath-normalized string — the registry key; L027).
        var seen = Set(roots)
        var allRoots = roots
        for recent in recentRoots {
            let normalized = recent.resolvingSymlinksInPath().path
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            allRoots.append(normalized)
        }

        return try await projectRoots(
            allRoots.map { URL(fileURLWithPath: $0, isDirectory: true) },
            into: databaseURL
        ).sessions
    }

    // MARK: - Mode 2: destructive rebuild (file-level recovery)

    /// 新文件换名晋升 (L009): build `catalog.lcat.tmp` fresh, project the
    /// session face into it, verify, promote. The OLD file is preserved one
    /// step as `catalog.lcat.bak` (ONE generation — the next rebuild
    /// overwrites it); a failed promotion rolls the `.bak` back. Returns the
    /// number of sessions restored. ORGANIZATION DATA IS LOST in the new
    /// file — the caller's completion copy must say so (the discipline).
    ///
    /// The caller must have CLOSED every catalog handle that points at the
    /// current file (the App wires `SessionIndexController
    /// .closeSharedCatalogHandles()` first) — a writer holding the old inode
    /// would strand its committed state in the orphaned file.
    @discardableResult
    public func destructiveRebuild(recentRoots: [URL]) async throws -> Int {
        guard CatalogPreferences.catalogsEnabled(defaultsSuiteName: defaultsSuiteName) else {
            throw RebuildError.catalogsDisabled
        }

        let directory = databaseURL.deletingLastPathComponent()
        let tmpURL = directory.appendingPathComponent(
            CatalogIndexSchema.databaseFileName + ".tmp")
        let bakURL = directory.appendingPathComponent(
            CatalogIndexSchema.databaseFileName + ".bak")
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true)

        // A stale tmp from an earlier failed attempt is NOT user data.
        for stale in [tmpURL,
                      directory.appendingPathComponent(tmpURL.lastPathComponent + "-wal"),
                      directory.appendingPathComponent(tmpURL.lastPathComponent + "-shm")] {
            try? fileManager.removeItem(at: stale)
        }

        // The session source: the OLD registry when the old file is readable
        // (schema-failed / truncated / unparsable → the recent list carries
        // the rebuild alone — this is the 损坏处置 entry point), merged with
        // the caller's recents. Only roots that still exist on disk project.
        var rootPaths = Self.readRegistryRoots(gracefully: databaseURL)
        for recent in recentRoots {
            let normalized = recent.resolvingSymlinksInPath().path
            if !rootPaths.contains(normalized) { rootPaths.append(normalized) }
        }
        let roots = rootPaths
            .filter { fileManager.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }

        // Build the fresh library.
        let projected = try await projectRoots(roots, into: tmpURL)
        if projected.sessions == 0, roots.isEmpty {
            // Nothing on disk to restore from — an EMPTY fresh library is
            // still a valid recovery of a corrupt file (the corruption is
            // gone; the user re-opens sessions into it).
        }

        // VERIFY (行集计数对账): the tmp's own row count must equal the
        // projection's accounting (a fresh file → every row is `added`).
        let actual = try Self.countCatalogImages(tmpURL)
        guard actual == projected.rows else {
            try? fileManager.removeItem(at: tmpURL)
            throw RebuildError.verificationFailed(
                expected: projected.rows, actual: actual)
        }

        // PROMOTE (same-directory renames — L009). First make checkpointing
        // DETERMINISTIC: the promotion needs every committed page IN the
        // tmp's main file, and SQLite's close-time checkpoint is best-
        // effort — force a TRUNCATE checkpoint through our own handle.
        let tmpWALName = tmpURL.lastPathComponent + "-wal"
        let tmpSHMName = tmpURL.lastPathComponent + "-shm"
        do {
            let checkpoint = try SQLiteHandle(path: tmpURL.path)
            try CatalogIndexSchema.checkpointTruncate(on: checkpoint)
            checkpoint.close()
        } catch {
            try? fileManager.removeItem(at: tmpURL)
            throw RebuildError.promotionFailed(
                reason: "the TRUNCATE checkpoint failed: "
                    + error.localizedDescription)
        }
        // After a TRUNCATE checkpoint the -wal is zero bytes (or gone) and
        // every reader is gone with our handle closed — the leftovers are
        // empty shells, safe to clear before the rename.
        let tmpWAL = directory.appendingPathComponent(tmpWALName)
        let tmpSHM = directory.appendingPathComponent(tmpSHMName)
        var walSize = 0
        if let attributes = try? fileManager.attributesOfItem(atPath: tmpWAL.path) {
            walSize = (attributes[.size] as? Int) ?? 0
        }
        if walSize > 0 {
            try? fileManager.removeItem(at: tmpURL)
            throw RebuildError.promotionFailed(
                reason: "the tmp -wal still holds \(walSize) checkpointed "
                    + "bytes — refusing to promote a partial file")
        }
        try? fileManager.removeItem(at: tmpWAL)
        try? fileManager.removeItem(at: tmpSHM)

        var promotedBackup = false
        do {
            // ① Keep the old file one step back (exactly one generation).
            if fileManager.fileExists(atPath: databaseURL.path) {
                if fileManager.fileExists(atPath: bakURL.path) {
                    try fileManager.removeItem(at: bakURL)
                }
                try fileManager.moveItem(at: databaseURL, to: bakURL)
                promotedBackup = true
            }
            if promotionInjection == .afterBackupMove {
                throw SessionIndexError.execFailed(
                    sql: "test-injection(afterBackupMove)", code: 1,
                    message: "injected")
            }
            // ② The promotion rename.
            try fileManager.moveItem(at: tmpURL, to: databaseURL)
        } catch {
            // Rollback: the original MUST stay usable (the discipline).
            try? fileManager.removeItem(at: tmpURL)
            if promotedBackup {
                try? fileManager.moveItem(at: bakURL, to: databaseURL)
            }
            throw RebuildError.promotionFailed(
                reason: "rename promotion failed: \(error.localizedDescription)")
        }
        return projected.sessions
    }

    // MARK: - Shared internals

    private struct ProjectionAccounting {
        var sessions = 0
        var rows = 0
    }

    /// Project each root through a FRESH inner projector at `target` (a
    /// fresh projector = a fresh handle; the shared projector's lifecycle
    /// belongs to the caller). Per-session failures skip (the sweep
    /// precedent); progress reports successes AND skips in the total. The
    /// inner handle is closed (and its `-wal` checkpointed away) BEFORE
    /// returning — the promotion's safety precondition depends on it.
    private func projectRoots(
        _ roots: [URL], into target: URL
    ) async throws -> ProjectionAccounting {
        var accounting = ProjectionAccounting()
        guard !roots.isEmpty else { return accounting }
        let projector = CatalogProjector(
            databaseURL: target, defaultsSuiteName: defaultsSuiteName)
        do {
            let total = roots.count
            for (index, root) in roots.enumerated() {
                if Task.isCancelled {
                    // Session-boundary abort: completed sessions stay
                    // committed (idempotent — a rerun converges).
                    throw CancellationError()
                }
                if let result = try? await projector.project(sessionRoot: root),
                   !result.offline, !result.skippedByGuard {
                    accounting.sessions += 1
                    accounting.rows += result.added + result.changed
                }
                if let progress = progressHandler {
                    await progress(RebuildProgress(
                        completedSessions: index + 1, totalSessions: total))
                }
            }
        } catch {
            await projector.close()
            throw error
        }
        await projector.close()
        return accounting
    }

    /// The old registry's roots, or [] when the old file cannot answer
    /// (schemaFailed / truncated / not a database — the graceful read IS
    /// the 损坏处置 entry's tolerance).
    private static func readRegistryRoots(gracefully url: URL) -> [String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let handle = try? SQLiteHandle(path: url.path) else { return [] }
        defer { handle.close() }
        var roots: [String] = []
        guard let statement = try? handle.prepare(
            "SELECT root_path FROM catalog_sessions ORDER BY root_path")
        else { return [] }
        while (try? statement.step()) == true {
            if let path = statement.columnText(0) { roots.append(path) }
        }
        return roots
    }

    private static func countCatalogImages(_ url: URL) throws -> Int {
        let handle = try SQLiteHandle(path: url.path)
        defer { handle.close() }
        let statement = try handle.prepare("SELECT COUNT(*) FROM catalog_images")
        guard try statement.step() else { return 0 }
        return Int(statement.columnInt(0) ?? 0)
    }

    private func openCatalogHandle() throws -> SQLiteHandle {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let handle = try SQLiteHandle(path: databaseURL.path)
        try CatalogIndexSchema.apply(to: handle)
        return handle
    }
}

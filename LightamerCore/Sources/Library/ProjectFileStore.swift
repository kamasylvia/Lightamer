import Foundation
import SQLite3

// ─────────────────────────────────────────────────────────────────────────────
// ProjectFileStore (Plan M2-2-1 T2) — the `.lalb` PACKAGE LIFECYCLE owner:
// create / open / close / backup / checkpoint discipline. One actor, ONE
// handle (the CatalogProjector actor-holds-handle precedent) — the single
// writer for the whole package; `LibraryStore` and `ExifSearchIndexer`
// consume the SAME connection through `withHandle` (never a second
// connection to the same file).
//
// CHECKPOINT DISCIPLINE (KD-6, probe P3): WAL + synchronous=NORMAL leave a
// non-empty `-wal` between write batches; a bare main-file copy would lose
// the tail transactions. Countermeasures, all HERE:
//   • after every write batch exit, `checkpointIfNeeded()` runs
//     `wal_checkpoint(TRUNCATE)` — throttled (≥2s since the last checkpoint
//     OR ≥64 commits since) so interactive editing checkpoints at most
//     once per 2s and import storms checkpoint every 64 batches
//     (the SidecarStore 2s debounce, same family);
//   • `close()` FORCES the TRUNCATE checkpoint before the handle close and
//     surfaces a non-zero counter as a TYPED error (recorded, never silent);
//   • `backup(to:)` = the `sqlite3_backup_init/step/finish` online copy —
//     a consistent single file taken while open (probe P3 empirical). This
//     is the ONLY sanctioned "copy the project" path; the UI must never
//     expose a bare file copy (M2-2-1 SUMMARY declares the posture).
//
// VERSION DISPATCH (KD-2): open reads `PRAGMA user_version` — 0 → fresh
// create (fresh DDL + manifest seed + stamp N); 0 < stored < N → the
// AUTOMATIC pre-migration `sqlite3_backup` snapshot, then
// `LibrarySchema.migrate`; >N → typed `.futureSchema` REFUSE before any
// write (the future file stays byte-untouched). Snapshot names carry
// their stored→to GENERATION and rotate (M2-8-1 E2: the old fixed-name +
// must-not-exist form deadlocked every second-generation reopen).
//
// `synchronous=NORMAL` is pinned (NOT OFF — the SessionIndexSchema header
// rationale carries over: checkpoint discipline already bounds the loss
// window; OFF would trade committed-transaction crash safety for nothing
// this rebuildable-from-.lra projection needs).
// ─────────────────────────────────────────────────────────────────────────────

public actor ProjectFileStore {

    /// KD-6 throttle: minimum seconds between TRUNCATE checkpoints.
    private static let checkpointMinimumInterval: TimeInterval = 2.0
    /// KD-6 throttle: minimum committed write batches between checkpoints.
    private static let checkpointMinimumBatches = 64

    private var handle: SQLiteHandle?
    private let url: URL

    // ── M6-1-01 (KD-2): the project-level single-writer lock ──────────────
    // The lock is a `<stem>.lalb.lock` SIBLING (never inside the package —
    // `LibrarySchema`/`project_meta`/backups are untouched; the flock is the
    // sole arbiter, the payload is diagnostics). `role == nil` = the caller
    // opted OUT of locking (every pre-existing call site and the double-store
    // LIB test family — flock is per open file description, so an
    // always-locking open() would EWOULDBLOCK the second in-process handle).
    // Production call paths lock through the assembly layer only
    // (LibraryProjectController always `.gui`, the headless `--project` arm
    // always `.headless`).

    /// The held project lock (nil = unlocked / the role-nil open paths).
    private var lock: SingleWriterLock?

    /// Whether this store is the READ-ONLY face (the second instance's
    /// fallback). Write legs (`withWriteBatch`) typed-reject; reads and
    /// `backup(to:)` stay available.
    private var readOnlyMode = false

    /// The sibling lock path (`<stem>.lalb.lock`).
    private var lockURL: URL {
        url.deletingPathExtension().appendingPathExtension("lalb.lock")
    }

    /// Last TRUNCATE checkpoint wall time (throttle clock).
    private var lastCheckpointAt: TimeInterval = 0
    /// Committed write batches since the last checkpoint.
    private var batchesSinceCheckpoint = 0

    // MARK: - Init

    /// The package file URL (`<stem>.lalb`). Use `create`/`open`; the init
    /// stores the path only.
    public init(at url: URL) {
        self.url = url
    }

    /// The package file URL.
    public var fileURL: URL { url }

    /// Whether a package is currently open.
    public var isOpen: Bool { handle != nil }

    // MARK: - Create / open / close

    /// Create a NEW package at `url`: suffix-validated `.lalb`, refuse an
    /// existing file, fresh-create the schema (KD-2 fresh leg) with the
    /// project name seeded. Returns self (the open store) for call-chain
    /// ergonomics. M6-1-01: `role != nil` acquires the sibling project lock
    /// BEFORE any write leg (the payload rides the lock fd; a held lock is
    /// the typed `projectHeldByOther` with the holder summary).
    @discardableResult
    public func create(
        name: String, role: SingleWriterRole? = nil
    ) throws -> ProjectFileStore {
        guard url.pathExtension.lowercased() == LibrarySchema.fileExtension else {
            throw LibraryError.openFailed(
                path: url.path, code: 0,
                message: "not a .\(LibrarySchema.fileExtension) package path")
        }
        guard FileManager.default.fileExists(atPath: url.path) == false else {
            throw LibraryError.openFailed(
                path: url.path, code: 0, message: "package already exists")
        }
        try acquireProjectLockIfRoled(role)
        // Ensure the parent directory exists (a save panel can target a
        // fresh folder).
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            do {
                try FileManager.default.createDirectory(
                    at: parent, withIntermediateDirectories: true)
            } catch {
                releaseProjectLock()
                throw error
            }
        }
        let opened: SQLiteHandle
        do {
            opened = try SQLiteHandle(path: url.path)
        } catch {
            releaseProjectLock()
            throw error
        }
        do {
            try LibrarySchema.apply(to: opened, projectName: name)
        } catch {
            opened.close()
            // A failed fresh create must not leave a half-born file.
            try? FileManager.default.removeItem(at: url)
            releaseProjectLock()
            throw error
        }
        handle = opened
        batchesSinceCheckpoint = 0
        lastCheckpointAt = Date().timeIntervalSince1970
        readOnlyMode = false
        return self
    }

    /// Open an EXISTING package: existence check + the KD-2 three-way
    /// dispatch (fresh on absent/0 — a zero-byte stub file heals into a
    /// valid package; ok on 1; typed REFUSE on >1 BEFORE any write).
    /// M6-1-01: `role != nil` acquires the sibling project lock BEFORE the
    /// handle opens — a lock failure precedes EVERY write leg (the
    /// migration snapshot included) and is the typed `projectHeldByOther`.
    @discardableResult
    public func open(role: SingleWriterRole? = nil) throws -> ProjectFileStore {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LibraryError.openFailed(
                path: url.path, code: 0, message: "package file does not exist")
        }
        try acquireProjectLockIfRoled(role)
        let opened: SQLiteHandle
        do {
            opened = try SQLiteHandle(path: url.path)
        } catch {
            releaseProjectLock()
            throw error
        }
        do {
            try dispatchSchema(on: opened)
        } catch {
            opened.close()
            releaseProjectLock()
            throw error
        }
        handle = opened
        batchesSinceCheckpoint = 0
        lastCheckpointAt = Date().timeIntervalSince1970
        readOnlyMode = false
        return self
    }

    /// Open an EXISTING package READ-ONLY (the M6-1-01 second-instance
    /// fallback): NO lock is taken or probed-held, write legs are
    /// typed-rejected at `withWriteBatch`, `backup(to:)` stays available.
    ///
    /// E2 (checker 回注) — the schema three-way is pinned HERE: the
    /// `dispatchSchema` legs for `stored == 0` (zero-byte stub = the full
    /// fresh DDL) and `0 < stored < current` (pre-migrate snapshot
    /// rotation + migrate) are WRITE legs; a lockless read-only open must
    /// NEVER trigger them (a stale-read concurrent migrate = double
    /// snapshot/migrate window; a stub silently self-healing = the
    /// read-only semantics lie). So: only `stored == current` opens;
    /// older/zero stubs typed-reject with the「需要一次读写打开」copy;
    /// `stored > current` keeps the existing `futureSchema` refusal.
    @discardableResult
    public func openReadOnly() throws -> ProjectFileStore {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LibraryError.openFailed(
                path: url.path, code: 0, message: "package file does not exist")
        }
        let opened = try SQLiteHandle(path: url.path)
        do {
            // Connection-local read-face pragmas ONLY — no journal_mode
            // write leg on this path.
            try opened.exec("PRAGMA synchronous=NORMAL")
            try opened.exec("PRAGMA foreign_keys=ON")
            let stored = try LibrarySchema.readUserVersion(from: opened)
            guard stored <= LibrarySchema.schemaVersion else {
                throw LibraryError.futureSchema(version: stored)
            }
            guard stored == LibrarySchema.schemaVersion else {
                opened.close()
                throw LibraryError.projectReadOnly(detail:
                    "package needs a read-write open to create or migrate the "
                        + "schema (stored user_version \(stored), current "
                        + "\(LibrarySchema.schemaVersion))")
            }
            handle = opened
            batchesSinceCheckpoint = 0
            readOnlyMode = true
            return self
        } catch {
            opened.close()
            throw error
        }
    }

    // MARK: - Project lock legs (M6-1-01 KD-2)

    /// Acquire the sibling lock when a role is given. A `heldByOther`
    /// becomes the typed conflict carrying the holder summary; a real I/O
    /// failure rethrows as openFailed. Idempotent for a store that already
    /// holds the lock (the reopen flows never double-acquire — the same
    /// process's second fd would EWOULDBLOCK against itself).
    private func acquireProjectLockIfRoled(_ role: SingleWriterRole?) throws {
        guard role != nil else { return }
        guard lock == nil else { return }
        switch SingleWriterLock.acquire(at: lockURL) {
        case .success(let acquired):
            lock = acquired
            acquired.writePayload(
                SingleWriterLockPayload(
                    role: role ?? .headless, pid: getpid(),
                    startedAt: SingleWriterLockPayload.nowISO8601()))
        case .failure(.heldByOther):
            throw LibraryError.projectHeldByOther(
                detail: SingleWriterLock.holderSummary(at: lockURL))
        case .failure(.ioError(let reason)):
            throw LibraryError.openFailed(
                path: lockURL.path, code: 0, message: reason)
        }
    }

    /// Release the held lock (idempotent; the close leg calls this AFTER
    /// the checkpoint — WAL tail safety, KD-2's release order).
    private func releaseProjectLock() {
        lock?.unlock()
        lock = nil
    }

    /// The KD-2 dispatch, shared by create/open (and the migration hook).
    private func dispatchSchema(on handle: SQLiteHandle) throws {
        try handle.execute("PRAGMA journal_mode=WAL")
        try handle.execute("PRAGMA synchronous=NORMAL")
        try handle.execute("PRAGMA foreign_keys=ON")
        let stored = try LibrarySchema.readUserVersion(from: handle)
        guard stored <= LibrarySchema.schemaVersion else {
            throw LibraryError.futureSchema(version: stored)
        }
        if stored == 0 {
            try LibrarySchema.apply(to: handle)
        } else if stored < LibrarySchema.schemaVersion {
            // The KD-2 pre-migration hook: snapshot BEFORE the migration.
            // M2-8-1 (checker E2): the snapshot ROTATES — named by its
            // stored→to GENERATION (`<stem>.pre-migrate.<stored>-<to>.bak`,
            // generations coexist) and a same-name stale snapshot (a prior
            // failed attempt at the same leg) is cleared before the
            // re-shot. The old fixed `.pre-migrate.bak` +
            // destination-must-not-exist refusal DEADLOCKED every second
            // migration: a v1→v2-migrated package reopened by a v3 binary
            // hit "destination already exists" and could never open again.
            let snapshotURL = url.deletingPathExtension()
                .appendingPathExtension("pre-migrate.\(stored)-\(LibrarySchema.schemaVersion).bak")
            if FileManager.default.fileExists(atPath: snapshotURL.path) {
                try? FileManager.default.removeItem(at: snapshotURL)
            }
            try backup(from: url.path, to: snapshotURL)
            try LibrarySchema.migrate(
                from: stored, to: LibrarySchema.schemaVersion, on: handle)
        }
    }

    /// Close the package: FORCED `wal_checkpoint(TRUNCATE)` first (a
    /// non-zero busy/log counter = typed error — surfaced, never silent),
    /// then the deterministic handle close. Idempotent (a closed store
    /// reports `.notOpen` for further work but `close()` again is a no-op).
    /// M6-1-01: the project lock releases AFTER the checkpoint + handle
    /// close (KD-2's release order — the WAL tail is safe before another
    /// instance can acquire). The read-only face resets here too.
    public func close() throws {
        if let handle {
            try checkpointTruncate(handle)
            handle.close()
            self.handle = nil
            batchesSinceCheckpoint = 0
        }
        releaseProjectLock()
        readOnlyMode = false
    }

    // MARK: - Checkpoint discipline (KD-6)

    /// Call at EVERY write-batch exit. Executes the TRUNCATE checkpoint
    /// when throttled-worthy — KD-6's literal OR semantics: ≥2s since the
    /// last checkpoint (interactive edit cadence — at most one TRUNCATE
    /// per 2s during a storm of single-edit batches) OR ≥64 committed
    /// batches since (import storms — bounded per-64-batch cost, no
    /// per-batch checkpoint). A forced checkpoint (close) bypasses this.
    public func checkpointIfNeeded() throws {
        guard handle != nil else { return }
        batchesSinceCheckpoint += 1
        let now = Date().timeIntervalSince1970
        let intervalElapsed =
            now - lastCheckpointAt >= Self.checkpointMinimumInterval
        guard intervalElapsed || batchesSinceCheckpoint >= Self.checkpointMinimumBatches
        else { return }
        guard let handle else { return }
        try checkpointTruncate(handle)
        lastCheckpointAt = Date().timeIntervalSince1970
        batchesSinceCheckpoint = 0
    }

    /// The forced TRUNCATE checkpoint (close leg + internal). A non-zero
    /// busy OR log counter means pages stayed in the WAL — typed failure,
    /// the caller decides (close keeps the handle open on failure).
    private func checkpointTruncate(_ handle: SQLiteHandle) throws {
        let statement = try handle.prepare("PRAGMA wal_checkpoint(TRUNCATE)")
        guard try statement.step() else {
            throw LibraryError.checkpointFailed(
                code: 0, message: "wal_checkpoint returned no row")
        }
        // Columns: (busy, log, checkpointed) — busy != 0 means another
        // reader blocked the truncation; log != 0 means pages remain.
        let busy = statement.columnInt(0) ?? 1
        let log = statement.columnInt(1) ?? 1
        guard busy == 0, log == 0 else {
            throw LibraryError.checkpointFailed(
                code: Int32(busy),
                message: "wal_checkpoint(TRUNCATE) left WAL pages (busy=\(busy), log=\(log))")
        }
    }

    // MARK: - Backup (the ONLY sanctioned copy path)

    /// Online-consistent full copy via `sqlite3_backup_init/step/finish`
    /// (probe P3: a consistent single file taken while the source stays
    /// open). The destination must NOT exist (typed refusal — never
    /// silently overwrite a user file).
    public func backup(to destination: URL) throws {
        guard handle != nil else { throw LibraryError.notOpen }
        if FileManager.default.fileExists(atPath: destination.path) {
            throw LibraryError.backupFailed(
                detail: "destination already exists: \(destination.path)")
        }
        try backup(from: url.path, to: destination)
    }

    /// The backup core (also the KD-2 pre-migration snapshot's engine).
    /// The SOURCE is a short-lived SECOND connection (read-only) to the
    /// same file — in WAL mode it reads the latest committed snapshot, and
    /// `sqlite3_backup` holds it consistent for the whole copy (probe P3).
    /// This keeps `SQLiteHandle` (the frozen Session connection layer)
    /// untouched; the raw handles live entirely inside this actor.
    /// EXISTENCE POLICY BELONGS TO THE CALLER (M2-8-1 E2): the public
    /// `backup(to:)` keeps its typed refusal; the pre-migrate hook
    /// ROTATES (clears a same-generation stale snapshot first). The
    /// former `allowExisting` parameter died with that change — no caller
    /// ever passed `true`, and the flag's refusal now lives one frame up.
    private func backup(from sourcePath: String, to destination: URL) throws {
        var sourcePointer: OpaquePointer?
        var destinationPointer: OpaquePointer?
        let sourceCode = sqlite3_open_v2(
            sourcePath, &sourcePointer,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard sourceCode == SQLITE_OK, let source = sourcePointer else {
            let message = sourcePointer.map { String(cString: sqlite3_errmsg($0)) }
                ?? "sqlite3_open_v2 returned nil handle"
            if let sourcePointer { sqlite3_close_v2(sourcePointer) }
            throw LibraryError.backupFailed(
                detail: "backup source open failed (\(sourceCode)): \(message)")
        }
        defer { sqlite3_close_v2(source) }

        let destinationCode = sqlite3_open_v2(
            destination.path, &destinationPointer,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil)
        guard destinationCode == SQLITE_OK, let dest = destinationPointer else {
            let message = destinationPointer.map {
                String(cString: sqlite3_errmsg($0))
            } ?? "sqlite3_open_v2 returned nil handle"
            if let destinationPointer { sqlite3_close_v2(destinationPointer) }
            try? FileManager.default.removeItem(at: destination)
            throw LibraryError.backupFailed(
                detail: "destination open failed (\(destinationCode)): \(message)")
        }
        defer { sqlite3_close_v2(dest) }

        guard let backup = sqlite3_backup_init(dest, "main", source, "main") else {
            let message = String(cString: sqlite3_errmsg(dest))
            try? FileManager.default.removeItem(at: destination)
            throw LibraryError.backupFailed(detail: "backup_init failed: \(message)")
        }
        // step(-1): copy the WHOLE database in one call.
        let stepCode = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        guard stepCode == SQLITE_DONE else {
            let message = String(cString: sqlite3_errmsg(dest))
            try? FileManager.default.removeItem(at: destination)
            throw LibraryError.backupFailed(
                detail: "backup_step returned \(stepCode): \(message)")
        }
    }

    // MARK: - The single-connection seam (LibraryStore / ExifSearchIndexer)

    /// Run `body` with the open handle — the INTERNAL single-writer seam.
    /// The handle is actor-confined (SQLiteHandle is deliberately
    /// non-Sendable); every library write/read rides THIS connection so
    /// the WAL discipline (one writer, throttled checkpoints) holds. The
    /// `sending` closure transfers caller-owned regions into the actor
    /// (SE-0414) — the handle itself NEVER leaves this isolation domain;
    /// results must be Sendable (counts/ids/strings — the callers' faces).
    func withHandle<T: Sendable>(
        _ body: sending (SQLiteHandle) throws -> T
    ) throws -> T {
        guard let handle else { throw LibraryError.notOpen }
        return try body(handle)
    }

    /// Batch wrapper: run a write batch inside ONE `BEGIN IMMEDIATE`
    /// transaction, then honor the checkpoint discipline at the exit. The
    /// transaction IS the point: multi-statement invariants (KD-4 — the
    /// album_content write and the ref_count movement; the removeAlbum
    /// decrement-then-delete sequence) are atomic per batch, and any body
    /// error ROLLBACKs the whole batch. (M2-2-1 acceptance fix: the batch
    /// ran the body in autocommit — the KD-4 same-transaction contract was
    /// structural, not enforced.) The checkpoint runs AFTER the COMMIT so
    /// TRUNCATE never races an active transaction; a checkpoint failure
    /// still surfaces typed (the write is committed, close re-forces).
    func withWriteBatch<T: Sendable>(
        _ body: sending (SQLiteHandle) throws -> T
    ) throws -> T {
        // M6-1-01 (KD-3): the read-only face's write-leg circuit breaker —
        // the SINGLE point every library write exits through
        // (LibraryStore + ExifSearchIndexer), so the second instance's
        // fallback is typed at the seam, never silent.
        if readOnlyMode {
            throw LibraryError.projectReadOnly(detail:
                "the package is open read-only (another instance holds the "
                    + "project lock)")
        }
        guard let handle else { throw LibraryError.notOpen }
        try handle.exec("BEGIN IMMEDIATE")
        do {
            let result = try body(handle)
            try handle.exec("COMMIT")
            try checkpointIfNeeded()
            return result
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
    }
}

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// LibraryError (Plan M2-2-1 T1) — the typed failure face of the `.lalb`
// project-package subsystem (the SessionIndexError 三分 template extended
// with the package-lifecycle families: checkpoint/backup).
//
// Every case is Equatable so tests pin exact failures, and Sendable so the
// actor boundaries can rethrow them freely.
// ─────────────────────────────────────────────────────────────────────────────

public enum LibraryError: Error, Equatable, Sendable {
    /// `sqlite3_open_v2` failed, or the target is not a valid `.lalb`
    /// package path (suffix check; code 0 = pre-open validation).
    case openFailed(path: String, code: Int32, message: String)
    /// The file's `PRAGMA user_version` is NEWER than this binary's
    /// `LibrarySchema.schemaVersion` — refuse, never guess at a future
    /// schema (the file stays byte-untouched).
    case futureSchema(version: Int)
    /// A schema migration N→N+1 failed and ROLLED BACK (the original file
    /// is untouched; the pre-migration backup hook has the snapshot).
    case migrationFailed(detail: String)
    /// `wal_checkpoint(TRUNCATE)` returned a non-zero busy/log counter
    /// (close-path checkpoint failures are surfaced, never silent — KD-6).
    case checkpointFailed(code: Int32, message: String)
    /// The `sqlite3_backup` online copy failed (init/step/finish leg
    /// recorded in the detail).
    case backupFailed(detail: String)
    /// A store-level constraint was violated (illegal album kind, blank
    /// name, missing parent, unknown image id …) — the typed face that
    /// keeps SQL errors from leaking as raw exec failures.
    case constraintViolation(detail: String)
    /// The operation needs an open package but the store holds no handle.
    case notOpen
}

import Foundation
import SQLite3

// ─────────────────────────────────────────────────────────────────────────────
// SQLiteHandle (Plan 09-01 T4; D-09-CONTEXT-1) — a THIN wrapper over the
// system libsqlite3 C API (Xcode SDK's `SQLite3` module — auto-linked, ZERO
// new SPM dependencies; GRDB was rejected by the dependency red line).
//
// Shape: prepare/bind/step/finalize + explicit transactions. The wrapper is
// deliberately dumb — the SQL lives in `SessionIndexSchema`/`SessionIndexStore`
// where tests can freeze it. NOT an actor itself: the owning
// `SessionIndexStore` actor provides the single-writer isolation; this class
// is confined to it.
//
// PRAGMAs are the STORE's business (WAL + synchronous=NORMAL), applied at
// open by the schema layer.
//
// Error surface (D-09-CONTEXT-1's typed三分): `SessionIndexError` —
// openFailed / schemaFailed / execFailed, each carrying the sqlite error
// code + message so failures diagnose without re-running.
// ─────────────────────────────────────────────────────────────────────────────

/// The typed failure face of the session-index subsystem (execution
/// decision: three families — open/schema/exec — per D-09-CONTEXT-1).
public enum SessionIndexError: Error, Sendable, Equatable {
    /// `sqlite3_open_v2` failed (unwritable path, unreadable file).
    case openFailed(path: String, code: Int32, message: String)
    /// Schema create/verify/migrate failed (I/O, corrupt file, FUTURE
    /// schema version — v1 readers never open a vN>1 database).
    case schemaFailed(detail: String, code: Int32, message: String)
    /// Statement prepare/step/bind failed. `sql` is the offending
    /// statement text (diagnostics only — never user data).
    case execFailed(sql: String, code: Int32, message: String)
}

/// A prepared statement. 1-based bind indices (sqlite convention);
/// `step()` returns true for a ROW, false for DONE. Finalized on deinit.
public final class SQLiteStatement {

    /// Non-Sendable sqlite handle confined to the owning store actor.
    fileprivate let handle: OpaquePointer
    private let sql: String

    fileprivate init(handle: OpaquePointer, sql: String) {
        self.handle = handle
        self.sql = sql
    }

    deinit {
        sqlite3_finalize(handle)
    }

    private func fail(_ code: Int32, _ message: String) -> SessionIndexError {
        .execFailed(sql: sql, code: code, message: message)
    }

    // MARK: Bind (1-based)

    public func bindText(_ index: Int32, _ value: String?) throws {
        let code: Int32
        if let value {
            code = sqlite3_bind_text(handle, index, value, -1, SQLITE_TRANSIENT)
        } else {
            code = sqlite3_bind_null(handle, index)
        }
        guard code == SQLITE_OK else { throw fail(code, lastMessage) }
    }

    public func bindInt(_ index: Int32, _ value: Int64?) throws {
        let code: Int32
        if let value {
            code = sqlite3_bind_int64(handle, index, value)
        } else {
            code = sqlite3_bind_null(handle, index)
        }
        guard code == SQLITE_OK else { throw fail(code, lastMessage) }
    }

    public func bindDouble(_ index: Int32, _ value: Double?) throws {
        let code: Int32
        if let value {
            code = sqlite3_bind_double(handle, index, value)
        } else {
            code = sqlite3_bind_null(handle, index)
        }
        guard code == SQLITE_OK else { throw fail(code, lastMessage) }
    }

    public func bindNull(_ index: Int32) throws {
        let code = sqlite3_bind_null(handle, index)
        guard code == SQLITE_OK else { throw fail(code, lastMessage) }
    }

    // MARK: Step

    /// true = a row is available (columns readable); false = DONE.
    @discardableResult
    public func step() throws -> Bool {
        let code = sqlite3_step(handle)
        switch code {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw fail(code, lastMessage)
        }
    }

    public func reset() throws {
        let code = sqlite3_reset(handle)
        guard code == SQLITE_OK else { throw fail(code, lastMessage) }
    }

    // MARK: Columns (0-based)

    public func columnText(_ index: Int32) -> String? {
        guard sqlite3_column_type(handle, index) != SQLITE_NULL else { return nil }
        guard let cString = sqlite3_column_text(handle, index) else { return nil }
        return String(cString: cString)
    }

    public func columnInt(_ index: Int32) -> Int64? {
        guard sqlite3_column_type(handle, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(handle, index)
    }

    public func columnDouble(_ index: Int32) -> Double? {
        guard sqlite3_column_type(handle, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(handle, index)
    }

    /// The sqlite error message for the LAST failure on this statement.
    private var lastMessage: String { String(cString: sqlite3_errmsg(sqlite3_db_handle(handle))) }
}

/// One open sqlite database. Confined to its owning actor (the store);
/// `close()` is explicit so session switches release the file handle
/// deterministically (the teardown ②-d step) — deinit backs it up with
/// `sqlite3_close_v2`.
public final class SQLiteHandle {

    /// The read-only open flags (projection-style readers: the catalog
    /// projector NEVER writes the lindex — the read side declares it).
    public static let readOnlyFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX

    private let db: OpaquePointer?
    private let path: String
    private var closed = false

    public init(
        path: String,
        flags: Int32 = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    ) throws {
        self.path = path
        var handle: OpaquePointer?
        let code = sqlite3_open_v2(path, &handle, flags, nil)
        guard code == SQLITE_OK, let opened = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) }
                ?? "sqlite3_open_v2 returned nil handle"
            if let handle { sqlite3_close_v2(handle) }
            throw SessionIndexError.openFailed(path: path, code: code, message: message)
        }
        db = opened
        // 5s busy timeout — WAL multi-handle waits (session-switch close →
        // reopen races, the crash-recovery leg) instead of instant
        // SQLITE_BUSY.
        sqlite3_busy_timeout(opened, 5000)
    }

    deinit {
        if !closed {
            sqlite3_close_v2(db) // v2: safe even with unfinalized statements
        }
    }

    /// The sqlite error message for the LAST operation on this handle.
    public var lastErrorMessage: String {
        guard let db else { return "no handle" }
        return String(cString: sqlite3_errmsg(db))
    }

    public var lastErrorCode: Int32 {
        guard let db else { return SQLITE_INTERNAL }
        return sqlite3_errcode(db)
    }

    /// Rows changed by the most recent statement on this connection
    /// (sqlite3_changes — the per-row UPDATE loop's flip counter).
    public func changes() -> Int {
        guard let db else { return 0 }
        return Int(sqlite3_changes(db))
    }

    /// The rowid of the most recent successful INSERT on this connection
    /// (Plan 16-3: the create faces' id return — the `id INTEGER PRIMARY
    /// KEY` alias is stable across VACUUM, RQ-16-7②).
    public func lastInsertRowID() -> Int64 {
        guard let db else { return 0 }
        return sqlite3_last_insert_rowid(db)
    }

    // MARK: Exec / prepare

    /// Run a zero-result statement (PRAGMA/BEGIN/COMMIT/ROLLBACK/DDL).
    public func exec(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(db, sql, nil, nil, &errorPointer)
        let message = errorPointer.map { String(cString: $0) } ?? lastErrorMessage
        if let errorPointer { sqlite3_free(errorPointer) }
        guard code == SQLITE_OK else {
            throw SessionIndexError.execFailed(sql: sql, code: code, message: message)
        }
    }

    public func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else {
            let message = lastErrorMessage
            if let statement { sqlite3_finalize(statement) }
            throw SessionIndexError.execFailed(sql: sql, code: code, message: message)
        }
        return SQLiteStatement(handle: statement, sql: sql)
    }

    /// Convenience: prepare + step a zero-row statement.
    public func execute(_ sql: String) throws {
        let statement = try prepare(sql)
        _ = try statement.step()
    }

    // MARK: Lifecycle

    /// Deterministic close (session-switch teardown ②-d). Idempotent.
    public func close() {
        guard !closed else { return }
        closed = true
        _ = sqlite3_close_v2(db)
    }
}

/// `SQLITE_TRANSIENT` — sqlite copies the bound string (the Swift side may
/// release it before step).
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

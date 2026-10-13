import Darwin
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Plan M6-1-01 T1 (KD-1) — the Core-level single-writer lock, generalized
// from the Plan 14-1 MCP endpoint machinery (App/Sources/Lightamer/MCP/
// McpEndpointFile.swift). Every semantic below is INHERITED VERBATIM from
// that file — the five flock states, the fd-lifetime discipline, the L009
// directory leg — so App-side薄封装 wrappers keep byte-identical behavior
// (the T3 zero-diff gate: McpHostTests green untouched).
//
// Lock semantics are the probe-verified five states (lock-probe 终判):
//   1. acquire succeeds        → this process is THE writer
//   2. acquire → EWOULDBLOCK   → a live holder exists → the caller takes its
//     read-only / conflict fallback (never a blocking wait, never an exit)
//   3. holder exits            → kernel releases (no cleanup code)
//   4. holder crashes          → kernel releases (the O_EXCL + pid dance is
//     EXPLICITLY NOT implemented — flock has no stale residue)
//   5. probe: try-flock. Lock succeeds = residue (the holder is dead);
//     lock fails = a live holder. `pid` rides the payload for DIAGNOSTICS
//     only, never as a liveness test (pid reuse).
//
// The payload file is a DIAGNOSTIC face written INTO the lock fd (truncate +
// write, no second file): its absence or staleness is NEVER a judgment
// criterion — flock is the sole arbiter. A crash between acquire and the
// payload write leaves the summary face at the「pid 未知」fallback.
//
// Darwin flock(2) arbiters per OPEN FILE DESCRIPTION: two independent
// open() fds IN THE SAME PROCESS also EWOULDBLOCK (checker o1, cc-verified
// 2026-10-16). Consequence: a holder must never probe its own lock (callers
// carry the self-held exemption, KD-5).
// ─────────────────────────────────────────────────────────────────────────────

/// The role a holder claims in the lock payload (the diagnostics face).
/// String rawValues are the frozen v1 spellings.
public enum SingleWriterRole: String, Codable, Sendable {
    /// The GUI app holding the project open.
    case gui
    /// A headless server (the `--project` MCP arm).
    case headless
}

/// The lock payload (schema v1 — FROZEN spelling; additive-only ever).
/// Diagnostic only: the flock is the sole arbiter, so an unreadable or
/// missing payload never changes any judgment.
public struct SingleWriterLockPayload: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var role: String
    public var pid: Int32
    public var startedAt: String

    public static let schemaVersionV1 = 1

    public init(role: SingleWriterRole, pid: Int32, startedAt: String) {
        self.schemaVersion = Self.schemaVersionV1
        self.role = role.rawValue
        self.pid = pid
        self.startedAt = startedAt
    }

    /// The `startedAt` rendering (RFC 3339 / ISO 8601 UTC) — the
    /// `McpEndpointInfo.nowISO8601` family.
    public static func nowISO8601() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }
}

/// An owned flock. The file descriptor stays open for the object's lifetime —
/// the lock releases on `unlock()` OR process death (whichever comes first;
/// the kernel is the sole arbiter, there is no residue to clean).
/// `@unchecked Sendable`: the fd lifecycle IS the lock lifecycle (the
/// McpEndpointLock shape).
public final class SingleWriterLock: @unchecked Sendable {

    public enum AcquireError: Error, Equatable {
        /// Another live process holds the writer right → the caller must
        /// take its read-only / conflict fallback (never exit — the five
        /// states ② discipline).
        case heldByOther
        /// Opening/locking failed for a real I/O reason.
        case ioError(String)
    }

    private let fileDescriptor: Int32
    private let path: String

    private init(fileDescriptor: Int32, path: String) {
        self.fileDescriptor = fileDescriptor
        self.path = path
    }

    /// Tries one non-blocking EX flock. Blocking waits do not exist in this
    /// design: you are the writer, or you are read-only, immediately.
    /// The parent directory is created when absent (the L009 leg — tests
    /// bootstrap on NSTemporaryDirectory, never on a slow external volume).
    public static func acquire(at lockURL: URL) -> Result<SingleWriterLock, AcquireError> {
        let fm = FileManager.default
        let directory = lockURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: directory.path) {
            do {
                try fm.createDirectory(
                    at: directory, withIntermediateDirectories: true)
            } catch {
                return .failure(.ioError("mkdir \(directory.path): \(error)"))
            }
        }
        // O_RDWR (not O_CREAT-exclusive — the lock file itself is a fixture,
        // flock is the mutual-exclusion primitive).
        let fd = open(lockURL.path, O_RDWR | O_CREAT, 0o600)
        guard fd >= 0 else {
            return .failure(.ioError("open \(lockURL.path): errno \(errno)"))
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let heldByOther = errno == EWOULDBLOCK || errno == EAGAIN
            close(fd)
            if heldByOther {
                return .failure(.heldByOther)
            }
            return .failure(.ioError("flock \(lockURL.path): errno \(errno)"))
        }
        let lock = SingleWriterLock(fileDescriptor: fd, path: lockURL.path)
        return .success(lock)
    }

    /// Whether the writer right is IMMEDIATELY available WITHOUT keeping it
    /// (the non-holding probe — OQ-5's per-write-call check shape). A
    /// successful probe means nobody alive holds the lock.
    public static func probeLockAvailable(at lockURL: URL) -> Bool {
        let fd = open(lockURL.path, O_RDWR | O_CREAT, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return false }
        flock(fd, LOCK_UN)
        return true
    }

    /// Releases the writer right (idempotent through the fd lifecycle).
    public func unlock() {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }

    public var lockPath: String { path }

    // MARK: - The diagnostic payload (rides the lock fd; never a criterion)

    /// Writes the payload INTO the held lock file (truncate + write — one
    /// file, no promotion dance). Best-effort by design: a failure here
    /// leaves the summary at the「pid 未知」fallback and MUST NOT fail the
    /// acquire path (the payload is diagnostics, flock is the arbitration).
    public func writePayload(_ payload: SingleWriterLockPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        ftruncate(fileDescriptor, 0)
        lseek(fileDescriptor, 0, SEEK_SET)
        data.withUnsafeBytes { raw in
            guard let pointer = raw.baseAddress else { return }
            _ = write(fileDescriptor, pointer, raw.count)
        }
    }

    /// Reads the payload off a lock file (any lock file, held or not).
    /// nil = absent / unparsable / unknown schema — the caller falls back.
    public static func readPayload(at lockURL: URL) -> SingleWriterLockPayload? {
        guard let data = FileManager.default.contents(atPath: lockURL.path),
              !data.isEmpty
        else { return nil }
        return try? JSONDecoder().decode(SingleWriterLockPayload.self, from: data)
    }

    /// The holder summary for typed conflict details: `role=<role> pid=<pid>
    /// startedAt=<ts>` when the payload reads, else the「pid 未知」fallback
    /// (a crash between acquire and the payload write, or a foreign file).
    public static func holderSummary(at lockURL: URL) -> String {
        guard let payload = readPayload(at: lockURL) else {
            return "pid 未知 / pid unknown"
        }
        return "role=\(payload.role) pid=\(payload.pid) startedAt=\(payload.startedAt)"
    }
}

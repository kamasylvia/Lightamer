import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// SidecarWriteJournal (Plan 09-02 T3) — the self-write swallow registry
// (the SECOND self-feedback defense line).
//
// FSEvents sees our OWN sidecar writes. The FIRST defense line is the
// exclude table (dotfiles / `.lightamer/` / `*.tmp-*` — those never even
// become events); but the co-located `.lra` itself is deliberately NOT
// excluded (an EXTERNAL sidecar write is a legitimate reconcile signal —
// sidecar-drift re-read). So every successful `SidecarStore` atomic write
// records its destination here, and the App reconciler swallows `.lra`
// events whose path is journaled inside the TTL window. A journal MISS
// degrades gracefully: the event triggers one extra idempotent reconcile
// whose diff comes back empty.
//
// Injected (default `.shared`) — tests build an isolated journal per
// fixture so suites never leak write state into each other.
// ─────────────────────────────────────────────────────────────────────────────

public final class SidecarWriteJournal: @unchecked Sendable {
    // @unchecked: `writeTimes` is guarded by `lock` on EVERY access — the
    // compiler cannot see the lock discipline, the runtime guarantees it.

    /// The process-wide journal (the default injection for both the write
    /// side and the reconciler).
    public static let shared = SidecarWriteJournal()

    /// How long a recorded write keeps swallowing its events. Generous by
    /// design: FSEvents latency (0.3 s) + the reconcile debounce (0.3 s)
    /// need ~1 s; 30 s absorbs heavy-queue delays. A late event past the
    /// window costs one harmless empty reconcile, nothing more.
    public static let defaultWindow: TimeInterval = 30

    private let lock = NSLock()
    private var writeTimes: [String: TimeInterval] = [:]

    public init() {}

    /// Record a successful sidecar write (absolute `.lra` path).
    public func record(path: String, at time: TimeInterval? = nil) {
        lock.lock()
        defer { lock.unlock() }
        writeTimes[path] = time ?? Date().timeIntervalSince1970
    }

    /// True when `path` was recorded within `window` seconds of `now`.
    public func containsRecent(
        path: String,
        window: TimeInterval = SidecarWriteJournal.defaultWindow,
        now: TimeInterval? = nil
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let written = writeTimes[path] else { return false }
        let reference = now ?? Date().timeIntervalSince1970
        return reference - written <= window
    }

    /// Drop entries older than the window (bounded memory; called on the
    /// reconcile legs — cadence is plenty).
    @discardableResult
    public func purge(
        olderThan window: TimeInterval = SidecarWriteJournal.defaultWindow,
        now: TimeInterval? = nil
    ) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let reference = now ?? Date().timeIntervalSince1970
        let stale = writeTimes.filter { reference - $0.value > window }
        for key in stale.keys { writeTimes.removeValue(forKey: key) }
        return stale.count
    }
}

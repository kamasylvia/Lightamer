import CoreServices
import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// SessionWatcher (Plan 09-02 T2; SESS-05) — the hint-only FSEvents wrapper.
//
// FSEvents has FOUR publicized defects (09-RESEARCH §4.2, LESSONS L007, the
// Watchexec "a mistake" finding) and this design trusts it for NOTHING:
//
//   | defect                    | countermeasure here                        |
//   |---------------------------|--------------------------------------------|
//   | coalescing (merge in the  | an event NEVER edits an index row — it     |
//   | latency window)           | only feeds the reconcile diff (the pure    |
//   |                           | ReconcileDiff plan is the sole arbiter)    |
//   | 4096-path batch cap       | events are classified to AFFECTED          |
//   |                           | DIRECTORIES, and a batch at/over the cap   |
//   |                           | sets `truncated` → the reconciler          |
//   |                           | escalates to a FULL reconcile              |
//   | rename split (old path +  | removed rows are stale-marked, never       |
//   | new path, independently)  | deleted on the event's word; the diff's    |
//   |                           | stat ruling re-pairs survivors (T1)        |
//   | dropped events under load | the app-focus leg forces a reconcile       |
//   |                           | (T3's four-schedule point ②)               |
//
// Flags (the configuration rationale, pinned per read_first ⑥):
//   • kFSEventStreamCreateFlagFileEvents — per-file paths (still treated as
//     directory-level hints only)
//   • kFSEventStreamCreateFlagUseCFTypes — CFArray/CFString event paths
//   • kFSEventStreamCreateFlagNoDefer — don't hold back the latency window
//     when the process is idle (external edits should surface promptly)
//   • kFSEventStreamCreateFlagWatchRoot — the SESSION ROOT ITSELF being
//     renamed/moved arrives as a RootChanged event → `rootChanged` batch →
//     full rescan + the recent-path invalidation hint. The path is NEVER
//     silently rewritten (L012 same-window routing owns open semantics).
//
// Exclusion: the watcher reuses the scanner's SINGLE-SOURCE exclude table
// (SessionTreeScanner) — `.lightamer/` + every dotfile dir, `*.tmp-*`,
// `*.cosessiondb`, and the root-level reserved tiers. `.lra` events pass
// (an external sidecar write is a legitimate signal); the SELF-written
// ones are swallowed by the write journal (T3's second defense line).
// ─────────────────────────────────────────────────────────────────────────────

/// One callback's worth of classified events — a HINT, never a row edit.
struct WatchEventBatch: Sendable, Equatable {
    /// Relative directories under the session root that saw a surviving
    /// event ("" = the root level itself). Summary seam for logs/diagnostics;
    /// the reconciler derives its OWN filtered dirs from `affectedFilePaths`
    /// (the journal swallow must be able to empty a directory's influence).
    var affectedDirectories: Set<String> = []
    /// Absolute paths of surviving events (capped at `batchCap` entries —
    /// beyond the cap the batch is `truncated` and escalates full anyway).
    /// The reconciler checks these against the self-write journal (T3).
    var affectedFilePaths: Set<String> = []
    /// The batch reached the 4096-path cap → likely truncated → escalate
    /// to a full reconcile.
    var truncated = false
    /// kFSEventStreamEventFlagRootChanged: the watched root itself was
    /// renamed/moved → full rescan + recent-path invalidation hint.
    var rootChanged = false
    /// kFSEventStreamEventFlagMustScanSubDirs: kernel-level drop suspicion
    /// → full rescan.
    var mustRescan = false

    var isEmpty: Bool {
        affectedDirectories.isEmpty && affectedFilePaths.isEmpty
            && !truncated && !rootChanged && !mustRescan
    }

    /// True when the batch demands a FULL reconcile (vs a subtree hint).
    var requiresFullRescan: Bool { truncated || rootChanged || mustRescan }
}

/// The FSEventStream lifecycle owner. `start`/`stop` are called from the
/// SessionCoordinator's open/switch flow (T3); the C callback lands on the
/// private serial queue and yields into the AsyncStream the reconciler
/// consumes. @unchecked Sendable: `streamRef` is guarded by `stateLock`,
/// the continuation is Sendable, and the C callback only reads immutables.
final class SessionWatcher: @unchecked Sendable {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "session-watch"
    )

    /// The FSEvents latency window (coalescing window). Execution decision
    /// (09-02-DECISIONS): 0.3 s — the research's 0.3-0.5 s range taken at
    /// the responsive end; bursts still merge, single edits stay snappy.
    static let defaultLatency: TimeInterval = 0.3

    /// The 4096-path batch cap (the FSEvents truncation countermeasure
    /// threshold; a full batch is presumed truncated).
    static let batchCap = 4096

    /// The watched session root.
    let root: URL

    private let latency: TimeInterval
    /// Private SERIAL queue — FSEvents callbacks never touch the main queue.
    private let queue = DispatchQueue(label: "com.kamasylvia.lightamer.session-watch")
    /// Path prefixes for event classification. L027 lesson: FSEvents
    /// reports REALIZED paths (/private/var/…) while `URL.path` keeps the
    /// /var spelling (Foundation's resolvingSymlinksInPath does NOT resolve
    /// the prefix link either) — realpath(3) once at init, match BOTH.
    /// Internal-readable: the reconciler builds path-spelling VARIANTS off
    /// these for the journal swallow + row-key math (T3).
    private(set) var rootPrefixes: [String] = []
    private let continuation: AsyncStream<WatchEventBatch>.Continuation

    /// The reconciler consumes this (single consumer).
    let events: AsyncStream<WatchEventBatch>

    private let stateLock = NSLock()
    private var streamRef: FSEventStreamRef?
    private var started = false

    init(root: URL, latency: TimeInterval = SessionWatcher.defaultLatency) {
        self.root = root
        self.latency = latency
        let physical: String = root.path.withCString { cpath -> String in
            // withCString — a caller-owned buffer scope; the buffer must
            // NOT be handed to free/deallocate (L027 heap-corruption note).
            var buffer = [CChar](repeating: 0, count: 4096)
            if realpath(cpath, &buffer) != nil {
                return String(cString: buffer)
            }
            return root.path
        }
        self.rootPrefixes = Array(Set([root.path + "/", physical + "/"]))
        var incoming: AsyncStream<WatchEventBatch>.Continuation!
        events = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            incoming = continuation
        }
        self.continuation = incoming
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Create + schedule + start the stream. Idempotent (a second start on
    /// a live watcher is a no-op). Requires the root to exist.
    @discardableResult
    func start() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !started else { return true }
        guard FileManager.default.fileExists(atPath: root.path) else {
            Self.logger.error(
                "watch root missing: \(self.root.path, privacy: .public)"
            )
            return false
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(self).toOpaque(),
            retain: nil,
            release: { pointer in
                guard let pointer else { return }
                Unmanaged<SessionWatcher>.fromOpaque(pointer).release()
            },
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot
        )
        guard
            let ref = FSEventStreamCreate(
                kCFAllocatorDefault,
                Self.callback,
                &context,
                [root.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                flags
            )
        else {
            Unmanaged<SessionWatcher>.fromOpaque(context.info!).release()
            Self.logger.error("FSEventStreamCreate failed for \(self.root.path, privacy: .public)")
            return false
        }
        FSEventStreamSetDispatchQueue(ref, queue)
        guard FSEventStreamStart(ref) else {
            FSEventStreamInvalidate(ref)
            FSEventStreamRelease(ref)
            Self.logger.error("FSEventStreamStart failed for \(self.root.path, privacy: .public)")
            return false
        }
        streamRef = ref
        started = true
        Self.logger.info("watching \(self.root.path, privacy: .public) (latency \(self.latency))")
        return true
    }

    /// Stop + invalidate + release. Idempotent; finishes the event stream
    /// so the consumer's `for await` loop ends deterministically.
    func stop() {
        stateLock.lock()
        let ref = streamRef
        streamRef = nil
        started = false
        stateLock.unlock()
        guard let ref else { return }
        FSEventStreamStop(ref)
        FSEventStreamInvalidate(ref)
        FSEventStreamRelease(ref)
        continuation.finish()
    }

    // MARK: - The C callback (private queue context)

    private static let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
        guard let info else { return }
        let watcher = Unmanaged<SessionWatcher>.fromOpaque(info).takeUnretainedValue()
        watcher.consume(numEvents: numEvents, eventPaths: eventPaths, eventFlags: eventFlags)
    }

    private func consume(
        numEvents: Int, eventPaths: UnsafeMutableRawPointer,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>
    ) {
        // UseCFTypes: eventPaths is a CFArray of CFString.
        let paths = unsafeBitCast(eventPaths, to: CFArray.self)
        var batch = WatchEventBatch()
        if numEvents >= Self.batchCap {
            batch.truncated = true  // the 4096 countermeasure
        }
        for index in 0..<numEvents {
            let flags = eventFlags[index]
            if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
                batch.rootChanged = true
                continue
            }
            if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0 {
                // The API's "I may have dropped events" flag → full rescan.
                batch.mustRescan = true
                continue
            }
            guard index < CFArrayGetCount(paths),
                  let raw = CFArrayGetValueAtIndex(paths, index)
            else { continue }
            let path = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
            Self.classify(path: path, relativeToPrefixes: rootPrefixes, into: &batch)
        }
        guard !batch.isEmpty else { return }
        continuation.yield(batch)
    }

    /// Hint classification — the single-source exclude table decides what
    /// even counts as a hint. The event's own word is never trusted for a
    /// row edit (the coalescing countermeasure).
    static func classify(
        path: String, relativeToPrefixes prefixes: [String], into batch: inout WatchEventBatch
    ) {
        var matchedRelative: String?
        for prefix in prefixes
        where path.hasPrefix(prefix) && path.count > prefix.count {
            matchedRelative = String(path.dropFirst(prefix.count))
            break
        }
        guard let relative = matchedRelative, !relative.isEmpty else { return }  // outside / the root itself

        let components = relative.split(separator: "/").map(String.init)
        // Directory components: the FIRST one sits directly under the root
        // (the reserved-tier gate applies only there — nested same-name
        // user folders stay browsable, exactly like the scanner).
        for (index, component) in components.dropLast().enumerated() {
            if SessionTreeScanner.isExcludedDirectory(
                component, isDirectlyUnderRoot: index == 0
            ) {
                return
            }
        }
        guard let fileName = components.last else { return }
        if SessionTreeScanner.isWatcherExcludedFile(fileName) { return }

        // The cap is the truncation countermeasure: at/over it the batch
        // already escalates full — stop paying per-path costs.
        guard batch.affectedFilePaths.count < batchCap else { return }
        batch.affectedFilePaths.insert(path)
        let directory = components.dropLast().joined(separator: "/")
        batch.affectedDirectories.insert(directory)
    }
}

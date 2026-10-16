import Darwin
import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 14-1 T3 (research §RQ-14-2 / §RQ-14-3②): the single-writer machinery.
//
// TWO ARTIFACTS, deliberately separate:
//   - mcp-endpoint.lock  → the WRITER-RIGHT primitive (flock EX|NB). Both
//     hosts hold it (GUI-embedded and headless), regardless of transport.
//   - mcp-endpoint.json  → the DISCOVERY payload (only hosts with a network
//     endpoint write it; the stdio host holds the lock but writes NO json —
//     D2: stdio's "endpoint" is its own stdin/stdout, nobody discovers it).
//
// Lock semantics are the probe-verified five states (lock-probe 终判):
//   1. acquire succeeds        → this process is THE writer
//   2. acquire → EWOULDBLOCK   → a live holder exists → READ-ONLY mode
//   3. holder exits            → kernel releases (no cleanup code)
//   4. holder crashes          → kernel releases (the O_EXCL + pid dance is
//     EXPLICITLY NOT implemented — flock has no stale residue)
//   5. discovery probe: read json → try-flock. Lock succeeds = residue (the
//     holder is dead) → delete the json and treat as no-service; lock fails
//     = a live server. `pid` rides the json for DIAGNOSTICS only, never as
//     a liveness test (pid reuse).
// ─────────────────────────────────────────────────────────────────────────────

/// The filesystem layout for the MCP single-writer machinery. Injectable so
/// tests run in per-case temp directories (L009: never on the UNITEK volume
/// — NSTemporaryDirectory is on the boot volume).
struct McpEndpointPaths: Sendable {
    let directory: URL

    var lockURL: URL { directory.appendingPathComponent("mcp-endpoint.lock") }
    var jsonURL: URL { directory.appendingPathComponent("mcp-endpoint.json") }

    /// M7-2-01 T4 (F-2 甲): the read-only face's discovery file — a
    /// DIFFERENT name so a read-only face can never overwrite the writer's
    /// `mcp-endpoint.json` (that file is the connect-guidance truth: the
    /// holder's live endpoint). DEBUG test-domain only (the writer gate
    /// keeps the release semantics); the schema is the SAME
    /// `McpEndpointInfo` v1.
    var readonlyJsonURL: URL {
        directory.appendingPathComponent("mcp-endpoint-readonly.json")
    }

    static func makeDefault() -> McpEndpointPaths {
        // create:false — the URL is built lazily; acquire()/write() create
        // the directory tree when they actually need it.
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first
        return McpEndpointPaths(
            directory: (base ?? FileManager.default.temporaryDirectory)
                .appendingPathComponent("Lightamer/mcp", isDirectory: true))
    }
}

/// The discovery file payload (schema verbatim §RQ-14-2, additive schema v1).
/// `auth` is a MARKER only ("none" | "bearer") — the bearer token's true body
/// NEVER enters this file (§RQ-14-13: keychain or the 0600 fallback file).
struct McpEndpointInfo: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var transport: String
    var host: String
    var port: Int
    var pid: Int32
    var startedAt: String
    var serverName: String
    var serverVersion: String
    var auth: String

    static let schemaVersionV1 = 1
    static let authNone = "none"
    static let authBearer = "bearer"
    static let transportStreamableHTTP = "streamable-http"

    /// The `startedAt` rendering (RFC 3339 / ISO 8601 UTC).
    static func nowISO8601() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }
}

// MARK: - The writer lock

/// An owned flock. The file descriptor stays open for the object's lifetime —
/// the lock releases on `unlock()` OR process death (whichever comes first;
/// the kernel is the sole arbiter, there is no residue to clean).
///
/// M6-1-01 (KD-1): the implementation now DELEGATES to the Core-level
/// `SingleWriterLock` generalization (LightamerCore/Foundation) — every
/// public signature, the five-state header discipline and the observable
/// behavior are unchanged (the zero-diff gate = McpHostTests green
/// untouched). This App-side wrapper keeps the `McpEndpointPaths`-shaped
/// call sites and the endpoint machinery's vocabulary intact.
final class McpEndpointLock: @unchecked Sendable {

    enum AcquireError: Error, Equatable {
        /// Another live process holds the writer right → the caller must
        /// start in READ-ONLY mode (never exit — research §RQ-14-3③).
        case heldByOther
        /// Opening/locking failed for a real I/O reason.
        case ioError(String)

        /// M6-1-01: mirror the Core error into this file's own vocabulary
        /// (the existing call sites pattern-match THESE cases).
        static func from(_ core: SingleWriterLock.AcquireError) -> AcquireError {
            switch core {
            case .heldByOther: .heldByOther
            case .ioError(let reason): .ioError(reason)
            }
        }
    }

    private let inner: SingleWriterLock

    private init(inner: SingleWriterLock) {
        self.inner = inner
    }

    /// Tries one non-blocking EX flock. Blocking waits do not exist in this
    /// design: you are the writer, or you are read-only, immediately.
    static func acquire(in paths: McpEndpointPaths) -> Result<McpEndpointLock, AcquireError> {
        switch SingleWriterLock.acquire(at: paths.lockURL) {
        case .success(let inner):
            return .success(McpEndpointLock(inner: inner))
        case .failure(let error):
            return .failure(.from(error))
        }
    }

    /// Whether a writer right is IMMEDIATELY available WITHOUT keeping it
    /// (the discovery probe's stale-residue test: a successful probe means
    /// nobody alive holds the lock, so a json on disk is residue).
    static func probeLockAvailable(in paths: McpEndpointPaths) -> Bool {
        SingleWriterLock.probeLockAvailable(at: paths.lockURL)
    }

    /// Releases the writer right (idempotent through the fd lifecycle).
    func unlock() {
        inner.unlock()
    }

    var lockPath: String { inner.lockPath }
}

// MARK: - The discovery file

enum McpEndpointFile {

    /// Atomic write: SAME-DIRECTORY tmp file + rename promotion (L009 — a
    /// rename across volumes or into /tmp is forbidden; the discovery file
    /// must never be observed half-written).
    static func write(_ info: McpEndpointInfo, in paths: McpEndpointPaths) throws {
        try writePayload(info, to: paths.jsonURL, in: paths)
    }

    /// M7-2-01 T4 (R-1 additive variant): the read-only face's discovery
    /// write — SAME payload schema and the SAME atomic promotion, the
    /// DIFFERENT file (`mcp-endpoint-readonly.json`, DEBUG test-domain
    /// only at the call site). The writer's `mcp-endpoint.json` semantics
    /// are byte-identical to before.
    static func writeReadOnly(
        _ info: McpEndpointInfo, in paths: McpEndpointPaths
    ) throws {
        try writePayload(info, to: paths.readonlyJsonURL, in: paths)
    }

    static func read(in paths: McpEndpointPaths) -> McpEndpointInfo? {
        readPayload(at: paths.jsonURL)
    }

    /// The read-only variant's read face (the test parent's port-discovery
    /// seam — F-2 甲).
    static func readReadOnly(in paths: McpEndpointPaths) -> McpEndpointInfo? {
        readPayload(at: paths.readonlyJsonURL)
    }

    static func remove(in paths: McpEndpointPaths) {
        try? FileManager.default.removeItem(at: paths.jsonURL)
    }

    /// The read-only variant's cleanup (the test-side case-boundary
    /// sweep — the plan's F-2 collision note).
    static func removeReadOnly(in paths: McpEndpointPaths) {
        try? FileManager.default.removeItem(at: paths.readonlyJsonURL)
    }

    // The shared bodies (ONE atomic-write / read implementation; the two
    // public name families only differ in the target URL — the discovery
    // logic is never re-implemented at the call sites).

    private static func writePayload(
        _ info: McpEndpointInfo, to url: URL, in paths: McpEndpointPaths
    ) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: paths.directory.path) {
            try fm.createDirectory(at: paths.directory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = try encoder.encode(info)
        let tmp = paths.directory.appendingPathComponent(
            "\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try payload.write(to: tmp)
        // The L009-visible promotion: tmp → final name within the SAME
        // directory (an atomic rename from the kernel's point of view).
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try fm.moveItem(at: tmp, to: url)
    }

    private static func readPayload(at url: URL) -> McpEndpointInfo? {
        guard let data = FileManager.default.contents(atPath: url.path) else {
            return nil
        }
        return try? JSONDecoder().decode(McpEndpointInfo.self, from: data)
    }
}

// MARK: - The discovery protocol (the finder's side)

enum McpEndpointDiscovery {

    enum Outcome: Equatable {
        /// No json on disk (and by extension no discoverable HTTP service).
        case noEndpointFile
        /// json existed but the lock is FREE → dead holder's residue; the
        /// json has been removed. Discoverer treats this as no service.
        case staleResidueRemoved
        /// A live writer holds the lock; the endpoint payload is fresh.
        case alive(McpEndpointInfo)
    }

    /// Read json → probe the lock. The probe decides — the file alone never
    /// does (crash residue is exactly "json present, lock free"; the pid
    /// field is display-only, §RQ-14-2).
    static func discover(in paths: McpEndpointPaths) -> Outcome {
        guard let info = McpEndpointFile.read(in: paths) else { return .noEndpointFile }
        if McpEndpointLock.probeLockAvailable(in: paths) {
            McpEndpointFile.remove(in: paths)
            return .staleResidueRemoved
        }
        return .alive(info)
    }
}

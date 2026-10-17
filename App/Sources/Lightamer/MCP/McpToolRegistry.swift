import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Plan 14-1 T2 (D-14-CONTEXT-1④): the pure-Swift tool registry seam.
//
// IRON RULE: this file has ZERO `import MCP` / `import NIO` — it compiles
// against nothing but Foundation, so the whole tool surface (descriptors,
// handlers, error codes, timeouts) survives an SDK swap with only the
// adapter layer (McpAdapters.swift, the sole import-MCP site) rewritten.
// A grep self-proof runs in the plan verification.
//
// The JSON value type is hand-rolled (not [String: Any]) because handlers
// are @Sendable and cross the actor boundary under Swift 6 strict
// concurrency — `Any` carries no Sendability proof (execution decision
// D-14-1-T2-1); the adapter converts SDK `Value` ↔ `McpJSON` at the seam.
// ─────────────────────────────────────────────────────────────────────────────

/// A minimal, Sendable JSON value — the lingua franca between the MCP
/// adapter layer and tool handlers. `null` arguments stay `null` (not
/// dropped) so handlers can distinguish "absent" (key missing) from
/// "explicit null".
public enum McpJSON: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([McpJSON])
    case object([String: McpJSON])

    /// Convenience accessor for string values.
    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// Convenience accessor for integer values.
    public var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    /// Convenience accessor for boolean values (Plan 14-2 tool arguments).
    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    /// Convenience accessor for object members.
    public subscript(key: String) -> McpJSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
}

/// The typed error-code table — ONE table for the whole Phase 14 tool face
/// (plan §A error-code column; §RQ-14-5④). Each tool plan consumes; the
/// adapter maps `code`+`message` into the JSON-RPC error text
/// `"[<code>] <message>"` (the inherited failure semantics: typed errors,
/// never silent degradation).
public enum McpToolError: Error, Sendable {
    case unknownOp(String)
    case invalidParams(String)
    case imageLiveInEditor(String)
    case notSessionMember(String)
    case serverReadOnly(String)
    case renderFailed(String)
    case renderTimeout(String)
    case exportFailed(String)
    case invalidFilter(String)
    case roiOutOfBounds(String)
    case keywordContainsSeparator(String)
    case exportPresetNotApplicable(String)
    case unknownPreset(String)
    case projectReadOnly(String)
    case internalError(String)
    /// M7-2-01 (D-M7-2-6): the semantic runtime is unavailable FOR THIS
    /// QUERY — the bundled CLIP assets are missing/failed to load, the
    /// model/runner vector widths disagree, or the AI worker process is
    /// unavailable/crashed/exhausted/request-failed (the F-3 mapping: the
    /// worker family rides the same code — "the semantic runtime cannot
    /// serve this query" is the honest family; `internalError` would
    /// misreport an absent asset/process as our bug). Retrying with
    /// different parameters cannot help; the message says which leg.
    case modelUnavailable(String)
    /// M7-5-01 (D-M7-5-1, ≙ Alcedo -32003): a state-changing command was
    /// dispatched while this agent session does NOT hold the GUI control —
    /// the message says to `control_acquire` first.
    case controlNotHeld(String)
    /// M7-5-01 (D-M7-5-1, ≙ Alcedo -32004): the user STOPPED the agent
    /// (the activity card's Stop) — the message tells the agent to stop
    /// working and ask the user before acquiring again.
    case controlRevokedByUser(String)
    /// M7-5-01 (D-M7-5-1, ≙ Alcedo -32005): another holder already holds
    /// the control (the message carries the holder), or the acquisition
    /// wait timed out on an unsealed editor input (the message carries the
    /// unsealed semantics).
    case controlBusy(String)

    /// The stable snake_case code surfaced to MCP clients.
    public var code: String {
        switch self {
        case .unknownOp: "unknownOp"
        case .invalidParams: "invalidParams"
        case .imageLiveInEditor: "imageLiveInEditor"
        case .notSessionMember: "notSessionMember"
        case .serverReadOnly: "serverReadOnly"
        case .renderFailed: "renderFailed"
        case .renderTimeout: "renderTimeout"
        case .exportFailed: "exportFailed"
        case .invalidFilter: "invalidFilter"
        case .roiOutOfBounds: "roiOutOfBounds"
        case .keywordContainsSeparator: "keywordContainsSeparator"
        case .exportPresetNotApplicable: "exportPresetNotApplicable"
        case .unknownPreset: "unknownPreset"
        case .projectReadOnly: "projectReadOnly"
        case .internalError: "internalError"
        case .modelUnavailable: "modelUnavailable"
        case .controlNotHeld: "controlNotHeld"
        case .controlRevokedByUser: "controlRevokedByUser"
        case .controlBusy: "controlBusy"
        }
    }

    /// The human-readable message carried inside the JSON-RPC error.
    public var message: String {
        switch self {
        case .unknownOp(let m), .invalidParams(let m), .imageLiveInEditor(let m),
            .notSessionMember(let m), .serverReadOnly(let m), .renderFailed(let m),
            .renderTimeout(let m), .exportFailed(let m), .invalidFilter(let m),
            .roiOutOfBounds(let m), .keywordContainsSeparator(let m),
            .exportPresetNotApplicable(let m), .unknownPreset(let m),
            .projectReadOnly(let m), .internalError(let m), .modelUnavailable(let m),
            .controlNotHeld(let m), .controlRevokedByUser(let m), .controlBusy(let m):
            m
        }
    }
}

/// M6-1-01 T7 (KD-5): the project-lock probe verdict — `.writable` (the
/// caller holds the project write right or the lock is free) or `.held`
/// (another live instance owns it). The probe is NON-HOLDING
/// (`probeLockAvailable` semantics — OQ-5's per-write-call check, no lock
/// handle kept); the SELF-HELD exemption belongs to the assembly closure
/// (a holder probing its own lock would EWOULDBLOCK against itself —
/// flock arbiters per open file description).
public enum McpProjectLockVerdict: Sendable {
    case writable
    case held(holderSummary: String, guidance: String)

    /// The typed rejection message (the copy SINGLE SOURCE): the localized
    /// key + the holder summary + the connect guidance / fallback line.
    public var errorMessage: String {
        switch self {
        case .writable:
            ""
        case .held(let holderSummary, let guidance):
            String(
                localized: "mcp_error_project_read_only",
                defaultValue: "项目由另一实例持有（\(holderSummary)）——\(guidance)")
        }
    }
}

/// A tool description in the registry's own vocabulary (SDK-independent).
/// `inputSchemaJSON` is a verbatim JSON-Schema object string — the snapshot
/// tests assert it literally (D-14-CONTEXT-3③: the tool face is a security
/// face; changes must edit the snapshot).
public struct McpToolDescriptor: Sendable, Equatable {
    public var name: String
    public var description: String
    public var inputSchemaJSON: String
    public var readOnlyHint: Bool?
    public var destructiveHint: Bool?
    public var idempotentHint: Bool?

    public init(
        name: String,
        description: String,
        inputSchemaJSON: String,
        readOnlyHint: Bool? = nil,
        destructiveHint: Bool? = nil,
        idempotentHint: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.inputSchemaJSON = inputSchemaJSON
        self.readOnlyHint = readOnlyHint
        self.destructiveHint = destructiveHint
        self.idempotentHint = idempotentHint
    }
}

/// A tool's output — text and inline image are the two Phase 14 shapes
/// (D-14-CONTEXT-4: base64 inline JPEG is the only image form).
public struct McpToolOutput: Sendable, Equatable {
    public enum Content: Sendable, Equatable {
        case text(String)
        case imageBase64(String, mimeType: String)
    }

    public var content: [Content]
    /// `true` = the call itself failed inside the tool (reported through the
    /// result face). Typed errors throw instead — this flag is for partial
    /// failure payloads.
    public var isError: Bool

    public init(_ content: [Content], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    public static func text(_ s: String) -> McpToolOutput {
        McpToolOutput([.text(s)])
    }
}

/// The handler seam: pure-Swift arguments in, output (or a typed error)
/// out. All tool implementations across Phases 14-2/14-3 conform to THIS.
public typealias McpToolHandler =
    @Sendable (_ arguments: [String: McpJSON]) async throws -> McpToolOutput

/// Request-scoped timeout table (§RQ-14-14 — one table, no bare numbers in
/// tool implementations; the QL render-time constant family).
public enum McpTimeouts {
    /// Metadata writes (set_rating/flag/color/note/keywords).
    public static let metadataWrite: Duration = .seconds(5)
    /// list_photos / list_iops / list_bursts / list_presets.
    public static let list: Duration = .seconds(10)
    /// get_thumbnails / get_contact_sheet.
    public static let thumbnailsAndContact: Duration = .seconds(20)
    /// render_preview / get_detail_crop (= QuickLookRenderer.renderTimeout
    /// family, :69).
    public static let renderAndCrop: Duration = .seconds(30)
    /// apply_params (single/normal batch).
    public static let apply: Duration = .seconds(10)
    /// apply_params with relPaths ≤ 1000 (the bulk tier).
    public static let applyBatch: Duration = .seconds(60)
    /// export_image.
    public static let export: Duration = .seconds(120)
    /// Graceful-shutdown in-flight drain (§RQ-14-14 停机处置).
    public static let shutdownDrain: Duration = .seconds(5)
    /// M7-5-01 (D-M7-5-7): `control_acquire` waiting on an unsealed editor
    /// input (the user mid-drag) — the bounded wait before the typed busy
    /// answer. The coordinator's injected default reads THIS
    /// (tests pass a short window; the tool face never hard-codes a bare
    /// number).
    public static let controlAcquire: Duration = .seconds(10)
}

/// The render serial gate (§RQ-14-13): every GPU render-class tool
/// (render_preview/get_detail_crop/get_contact_sheet/export_image) runs
/// EXCLUSIVELY — concurrency 1. 14-1 lays the base; 14-2/14-3 consume.
/// A plain actor semaphore: waiters queue on a FIFO continuation list, so
/// no spinning and the lock hand-off is exact.
public actor McpRenderGate {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// Suspends until the gate is free, then takes it.
    public func acquire() async {
        if locked || !waiters.isEmpty {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waiters.append(continuation)
            }
        }
        // Either we found it free, or a release() handed the lock to this
        // resumed waiter directly.
        locked = true
    }

    /// Hands the lock to the next waiter (if any) or frees the gate.
    public func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        } else {
            locked = false
        }
    }

    /// The tool wrapper (the plan's `withRenderGate`): serializes `body`
    /// against every other render-class call.
    public func withRenderGate<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        await acquire()
        do {
            let value = try await body()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }
}

/// The registry itself: an actor so registration (host assembly) and
/// dispatch (request path) are both isolation-safe. The SDK adapter is the
/// only caller.
public actor McpToolRegistry {

    private struct Entry {
        var descriptor: McpToolDescriptor
        var requiresWriter: Bool
        /// M7-5-01 (D-M7-5-3): the third gate — the tool changes the GUI
        /// session state and must pass the control-admit seam BEFORE the
        /// handler (the agent must hold the control). `false` default keeps
        /// every pre-M7-5 registration byte-identical; the control commands
        /// themselves stay `false` (changing the control IS the control).
        var requiresControl: Bool
        var handler: McpToolHandler
    }

    private var entries: [String: Entry] = [:]

    /// The writer check seam (T3 wires the flock face): when set, tools
    /// registered with `requiresWriter: true` call it BEFORE the handler and
    /// fail with `serverReadOnly` when it returns false (this process does
    /// not hold the endpoint lock). `nil` = no gate (tests, and the
    /// single-writer default).
    private var writerCheck: (@Sendable () async -> Bool)?

    /// M7-5-01 (D-M7-5-3): the control-admit seam — same mechanical shape
    /// as `writerCheck`. When set, tools registered with
    /// `requiresControl: true` call it BEFORE the handler (after the writer
    /// gate — the two gates stack, never substitute) and it throws the typed
    /// control errors when the agent session may not act (the D-M7-5-1
    /// tier). `nil` = no gate (headless always-admit
    /// arm, tests). NOT counted in `writeCallCount` — the write counter
    /// still rides the writer gate only.
    private var controlAdmit: (@Sendable (_ toolName: String) async throws -> Void)?

    /// The process-wide write-face call counter (Plan 14-4 T2): every
    /// `requiresWriter` CALL that passed the gate increments this — the
    /// launcher panel's honest「本次会话无写回」face reads the delta across
    /// one agent session. Every write-face tool in the closed set registers
    /// with `requiresWriter: true`, so the counter needs no per-tool glue.
    public private(set) var writeCallCount = 0

    public init() {}

    /// Registers (or replaces) a tool. Replacement keeps the closed-set
    /// discipline honest: the snapshot tests fail if a registration change
    /// is not deliberate.
    public func register(
        _ descriptor: McpToolDescriptor,
        requiresWriter: Bool = false,
        requiresControl: Bool = false,
        handler: @escaping McpToolHandler
    ) {
        entries[descriptor.name] = Entry(
            descriptor: descriptor, requiresWriter: requiresWriter,
            requiresControl: requiresControl, handler: handler)
    }

    /// Installs the writer gate (T3: the flock owner check).
    public func setWriterCheck(_ check: (@Sendable () async -> Bool)?) {
        writerCheck = check
    }

    /// Installs the control-admit gate (M7-5-01 T1: the GUI coordinator
    /// backs it; the headless arm leaves it nil = always admit).
    public func setControlAdmit(
        _ admit: (@Sendable (_ toolName: String) async throws -> Void)?
    ) {
        controlAdmit = admit
    }

    /// The registered tool descriptors in registration order (stable for
    /// tools/list snapshots).
    public func descriptors() -> [McpToolDescriptor] {
        entries.values
            .sorted { $0.descriptor.name < $1.descriptor.name }
            .map(\.descriptor)
    }

    /// Dispatches one tool call. Unknown names are `internalError`
    /// (protocol-level; §A's implicit error). Write-face tools pass through
    /// the writer gate first (the T3 只读降级 hook) and count on the
    /// process-wide write-call counter (Plan 14-4 T2).
    public func call(
        name: String,
        arguments: [String: McpJSON]
    ) async throws -> McpToolOutput {
        guard let entry = entries[name] else {
            throw McpToolError.internalError("unknownTool: no tool named '\(name)'")
        }
        if entry.requiresWriter {
            if let writerCheck, !(await writerCheck()) {
                throw McpToolError.serverReadOnly(
                    "this MCP server instance is read-only (another Lightamer "
                        + "instance holds the writer lock); connect to the GUI "
                        + "HTTP endpoint listed in mcp-endpoint.json instead")
            }
            writeCallCount += 1
        }
        // M7-5-01 (D-M7-5-3): the control gate AFTER the writer gate, BEFORE
        // the handler. The admit throw face is the coordinator's typed
        // control errors; writeCallCount stays untouched here (the counter
        // rides the writer gate only — D-M7-5-3).
        if entry.requiresControl, let controlAdmit {
            try await controlAdmit(name)
        }
        return try await entry.handler(arguments)
    }
}

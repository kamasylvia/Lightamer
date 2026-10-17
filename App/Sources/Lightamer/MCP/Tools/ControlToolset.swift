import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ControlToolset (M7-5-01 T1, D-M7-5-2) — the FIFTH tool domain: the GUI
// session turn-taking face (control_acquire / control_release / control_get).
//
// Semantics anchor: Alcedo AU14's control triple (automation_control_
// commands.hpp) — command semantics and error-code tiers only; the copy,
// schema text and code are all self-written (GPL no-copy red line).
//
// The control state value rides everywhere as `McpControlState`
// {held, revokedByUser, holder}; the providers are optional closures
// (McpSearchStateContext / McpProjectContext 同款 — registration consumes no
// provider, so the union fixture registers the domain with an all-nil
// context). The control commands themselves register WITHOUT the third-gate
// flag (changing the control IS the control — the admit gate never applies
// to them).
//
// admit (the third registry gate) is NOT part of this context — it is the
// registry's structural seam (`setControlAdmit`), the same layering as the
// writer gate.
// ─────────────────────────────────────────────────────────────────────────────

/// The GUI-session control state — the one value every control tool answers
/// and `get_state`'s `control.agent` face mirrors. The headless constant is
/// the TURN-04 always-held face (null owner = the agent always holds).
public struct McpControlState: Sendable, Equatable {
    public var held: Bool
    public var revokedByUser: Bool
    public var holder: String

    public init(held: Bool, revokedByUser: Bool, holder: String) {
        self.held = held
        self.revokedByUser = revokedByUser
        self.holder = holder
    }

    /// The headless constant (D-M7-5-2/TURN-04): `{held: true,
    /// revokedByUser: false, holder: ""}` — the single source both
    /// `makeHeadlessControlContext` and the tests consume.
    public static let headlessConstant = McpControlState(
        held: true, revokedByUser: false, holder: "")

    /// The JSON face (three keys, stable order).
    public var json: McpJSON {
        .object([
            "held": .bool(held),
            "revokedByUser": .bool(revokedByUser),
            "holder": .string(holder),
        ])
    }
}

/// The control providers (all optional, all nil-defaulted — the union
/// fixture registers the domain without any live face; the tools answer the
/// honest not-assembled errors until a host wires them).
public struct McpControlContext: Sendable {
    /// Acquire the control for `holderName` (the coordinator resolves the
    /// busy / wait-for-unsealed-input semantics and throws the typed
    /// control errors).
    public var acquire:
        (@Sendable (_ holderName: String) async throws -> McpControlState)?
    /// Release the control (idempotent — releasing without holding changes
    /// nothing; the provider owns that face).
    public var release: (@Sendable () async throws -> McpControlState)?
    /// Read the current state (nil provider → the typed not-assembled
    /// error; the tools never invent a state).
    public var state: (@Sendable () async -> McpControlState)?

    public init(
        acquire: (@Sendable (_ holderName: String) async throws -> McpControlState)? = nil,
        release: (@Sendable () async throws -> McpControlState)? = nil,
        state: (@Sendable () async -> McpControlState)? = nil
    ) {
        self.acquire = acquire
        self.release = release
        self.state = state
    }
}

/// The fifth domain's registrar (three tools, alphabetical answers in
/// `descriptors()` — control_acquire / control_get / control_release).
enum McpControlToolset {

    static func registerAll(
        on registry: McpToolRegistry, context: McpControlContext
    ) async {
        // control_acquire — holder_name? (default "agent"). The wait-for-
        // unsealed-input semantics ride the provider's injected timeout
        // (the coordinator defaults to McpTimeouts.controlAcquire — the
        // tool face adds NO second cap: a double wrap would race the typed
        // busy answer at the 10s boundary and mask it with a generic
        // internalError).
        await registry.register(
            McpToolDescriptor(
                name: "control_acquire",
                description: String(
                    localized: "mcp_tool_desc_control_acquire",
                    defaultValue: String.LocalizationValue(
                        "Take the GUI session's agent control (turn-taking: "
                            + "while the agent holds control the user's editing "
                            + "faces are disabled; state-changing tools answer "
                            + "controlNotHeld unless it is held). holder_name: "
                            + "your session label (default \"agent\") — resuming "
                            + "with the SAME label after a user Stop continues "
                            + "the previous task; a DIFFERENT label starts a new "
                            + "one. While another holder has control the answer "
                            + "is controlBusy carrying that holder; while the "
                            + "user is mid-drag in the editor the call WAITS "
                            + "until the input settles (bounded wait, then "
                            + "controlBusy). Poll control_get / get_state for "
                            + "changes (no push notifications in v1).")),
                inputSchemaJSON:
                    #"{"type":"object","properties":{"holder_name":{"type":"string","description":"Session label for this holder (default agent)"}}}"#),
            handler: { arguments in
                guard let acquire = context.acquire else {
                    throw McpToolError.internalError(
                        "the control face is not assembled on this host")
                }
                let holderName = arguments["holder_name"]?.stringValue
                    ?? "agent"
                let state = try await acquire(holderName)
                return .text(McpJSONSerialization.text(from: state.json))
            })
        // control_release — idempotent (the provider owns the no-op arm).
        await registry.register(
            McpToolDescriptor(
                name: "control_release",
                description: String(
                    localized: "mcp_tool_desc_control_release",
                    defaultValue: String.LocalizationValue(
                        "Release the agent control back to the user. Idempotent "
                            + "— releasing while NOT holding control changes "
                            + "nothing (the state object still answers).")),
                inputSchemaJSON: #"{"type":"object","properties":{}}"#),
            handler: { _ in
                guard let release = context.release else {
                    throw McpToolError.internalError(
                        "the control face is not assembled on this host")
                }
                let state = try await release()
                return .text(McpJSONSerialization.text(from: state.json))
            })
        // control_get — the pure read (readOnlyHint: true).
        await registry.register(
            McpToolDescriptor(
                name: "control_get",
                description: String(
                    localized: "mcp_tool_desc_control_get",
                    defaultValue: String.LocalizationValue(
                        "Read the current control state {held, revokedByUser, "
                            + "holder} without changing anything (the polling "
                            + "face — v1 has no control-changed notifications). "
                            + "revokedByUser = the user stopped the agent: stop "
                            + "working and ask the user before acquiring again.")),
                inputSchemaJSON: #"{"type":"object","properties":{}}"#,
                readOnlyHint: true),
            handler: { _ in
                guard let stateProvider = context.state else {
                    throw McpToolError.internalError(
                        "the control face is not assembled on this host")
                }
                let state = await stateProvider()
                return .text(McpJSONSerialization.text(from: state.json))
            })
    }
}

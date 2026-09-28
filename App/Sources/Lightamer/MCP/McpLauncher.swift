import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Plan 14-4 T1/T2 (MCP-10, D-14-CONTEXT-10): the launcher — the user's OWN
// shell command template, run through /bin/zsh -c with two placeholders and
// the endpoint discovery path injected, at most ONE agent process at a time,
// SIGTERM → 5s → SIGKILL that can only ever reach the child THIS launcher
// spawned and still has registered.
//
// INJECTION-FACE DISCIPLINE — DELIBERATELY OUT OF SYNC WITH EXP-08, DO NOT
// MERGE (D-14-CONTEXT-10③): the launcher executes the USER'S OWN template
// (the user is the command author — the injection face is self-injection,
// which the documentation states). PostExportActions.runScriptDirect
// (EXP-08) is an app-BUILTIN action and therefore pins the narrower
// argv-direct form ("no shell string, ever"). Two call sites, two different
// disciplines — this comment lives here AND in PostExportActions so an
// audit can never read one as a regression of the other.
//
// APP-ZERO-AI red line: nothing here calls a model, engineers prompts or
// configures providers. The prompt template is the user's own text; the app
// only substitutes placeholders.
// ─────────────────────────────────────────────────────────────────────────────

/// Template rendering: placeholder substitution only — the command text is
/// otherwise the user's own and is passed through VERBATIM (old templates
/// without placeholders run unchanged).
public enum McpLauncherTemplate {

    /// The endpoint discovery file placeholder (the agent reads host/port/
    /// auth from the file this expands to).
    public static let endpointPlaceholder = "{{LIGHTAMER_MCP}}"

    /// The task-prompt placeholder (expanded to a single-quoted shell word).
    public static let promptPlaceholder = "{{PROMPT}}"

    /// The shell single-quote wrapping discipline (§RQ-14-12): the prompt
    /// rides as `'…'` with every inner `'` spelled `'\''` — after zsh
    /// evaluates the template, the child command sees the ORIGINAL text
    /// byte-for-byte (backticks, `$()`, `$VAR` and quotes stay inert DATA).
    public static func shellSingleQuoteEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "'\\''")
    }

    public struct Rendered: Equatable, Sendable {
        /// The command string to hand to /bin/zsh -c.
        public var command: String
        /// The template mentioned {{PROMPT}} at all.
        public var hasPromptPlaceholder: Bool
        /// Non-empty prompt content was actually inlined.
        public var promptInlined: Bool
    }

    /// Renders the template. An empty/whitespace prompt collapses the
    /// {{PROMPT}} placeholder to `''` (an empty shell word — still safe
    /// mid-sentence; the caller surfaces the honest hint).
    public static func render(
        command: String, prompt: String?, endpointPath: String
    ) -> Rendered {
        var text = command.replacingOccurrences(
            of: endpointPlaceholder, with: endpointPath)
        let hasPromptPlaceholder = text.contains(promptPlaceholder)
        let trimmed = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // "Inlined" means the placeholder existed AND non-empty content
        // replaced it (a prompt without a placeholder slot is unused).
        let inlined = hasPromptPlaceholder && !trimmed.isEmpty
        let replacement = trimmed.isEmpty
            ? "''"
            : "'\(shellSingleQuoteEscaped(trimmed))'"
        text = text.replacingOccurrences(of: promptPlaceholder, with: replacement)
        return Rendered(
            command: text, hasPromptPlaceholder: hasPromptPlaceholder,
            promptInlined: inlined)
    }
}

/// The agent-output log buffer: a FIXED ring of the last `capacity` merged
/// stdout/stderr lines (research §RQ-14-12: 2000 lines, drop-from-head).
/// Lines keep accumulating while the panel is closed; the panel snapshots it.
public final class McpLauncherLogBuffer: @unchecked Sendable {

    public static let defaultCapacity = 2000

    private let lock = NSLock()
    private var lines: [String] = []
    public let capacity: Int

    public init(capacity: Int = McpLauncherLogBuffer.defaultCapacity) {
        self.capacity = capacity
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return lines.count
    }

    public func append(_ line: String) {
        lock.lock()
        lines.append(line)
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)  // ring: drop from head
        }
        lock.unlock()
    }

    /// A point-in-time copy (the panel renders the copy; the ring keeps
    /// filling underneath).
    public func snapshot() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return lines
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        lines.removeAll()
    }
}

/// The launcher core. Thread-safe (NSLock-guarded, no actor hop needed by
/// the panel or the tests); at most ONE registered child at a time — the
/// app-side serial gate (research item A's precondition: two agents writing
/// back concurrently has no countermeasure in v1).
public final class McpLauncher: @unchecked Sendable {

    public enum LaunchFailure: Error, Equatable, Sendable {
        /// The serial gate: a second start while one agent is in flight.
        case alreadyRunning
        /// Process.run() itself failed (missing executable, permission…).
        case launchFailed(String)
    }

    public enum StopOutcome: Equatable, Sendable {
        /// SIGTERM sufficed — the child exited before the kill bound.
        case terminated
        /// The 5s bound elapsed; SIGKILL finished the job.
        case killed
        /// A pid was named that is NOT the registered child — refused
        /// (termination only ever reaches our own registered pid, §8.5).
        case notOurs
        /// No child is registered (nothing in flight).
        case notRunning
    }

    /// The SIGTERM → SIGKILL bound (§RQ-14-12: 5s).
    public static let killGrace: TimeInterval = 5

    private let lock = NSLock()
    private var process: Process?

    /// The merged agent log (stdout + stderr lines, ring-capped).
    public let logBuffer = McpLauncherLogBuffer()

    /// An extra per-line tap (the panel's scroll-follow pump). Lines ALSO
    /// always land in `logBuffer`.
    public var onLogLine: (@Sendable (String) -> Void)?

    /// Fires exactly once per started child, with its exit status
    /// (0..255, or a negative signal face from the shell).
    public var onExit: (@Sendable (Int32) -> Void)?

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let process else { return false }
        return process.isRunning
    }

    /// The registered child's pid (nil = nothing in flight).
    public var runningPID: Int32? {
        lock.lock(); defer { lock.unlock() }
        return process?.processIdentifier
    }

    public init() {}

    /// Spawns `<shellPath> -c <renderedCommand>` with `LIGHTAMER_MCP`
    /// injected into the child environment (the placeholder-free discovery
    /// route). Throws `alreadyRunning` (serial gate) or `launchFailed`
    /// (the spawn itself failed — no child was registered). `shellPath`
    /// exists so tests can exercise the launch-failure face with a
    /// nonexistent executable; production always omits it (→ /bin/zsh).
    @discardableResult
    public func start(
        renderedCommand: String,
        environment: [String: String] = [:],
        shellPath: String = "/bin/zsh"
    ) throws -> Int32 {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: shellPath)
        child.arguments = ["-c", renderedCommand]
        var env = ProcessInfo.processInfo.environment
        if let endpoint = environment["LIGHTAMER_MCP"] {
            env["LIGHTAMER_MCP"] = endpoint
        }
        child.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        child.standardOutput = stdout
        child.standardError = stderr

        lock.lock()
        if let existing = process, existing.isRunning {
            lock.unlock()
            throw LaunchFailure.alreadyRunning
        }
        // Take over the registration slot BEFORE run() so a synchronously
        // failing spawn can't race a second start into the slot.
        process = child
        lock.unlock()

        McpLauncher.pipeReader(stdout.fileHandleForReading) { [weak self] line in
            self?.emit(line)
        }
        McpLauncher.pipeReader(stderr.fileHandleForReading) { [weak self] line in
            self?.emit(line)
        }

        child.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.lock.lock()
            if self.process === process { self.process = nil }
            self.lock.unlock()
            self.onExit?(process.terminationStatus)
        }

        do {
            try child.run()
        } catch {
            // Registration rolled back — the serial gate is free again and
            // the UI surfaces the toast + a log line (the launch-failure
            // face, §RQ-14-12).
            lock.lock()
            if process === child { process = nil }
            lock.unlock()
            throw LaunchFailure.launchFailed("\(error)")
        }
        return child.processIdentifier
    }

    /// Stops the registered child: SIGTERM first; if it is still alive
    /// after `killGrace` seconds, SIGKILL — sent ONLY to the registered
    /// own pid. A `pid` argument that does not match the registration is
    /// refused (`notOurs`) and NOTHING is signalled. Bounded: returns as
    /// soon as the child exits or the bound fires.
    @discardableResult
    public func stop(pid wanted: Int32? = nil) -> StopOutcome {
        lock.lock()
        guard let child = process else {
            lock.unlock()
            return .notRunning
        }
        let own = child.processIdentifier
        if let wanted, wanted != own {
            lock.unlock()
            return .notOurs
        }
        lock.unlock()

        // SIGTERM (terminate() on a live child; the isRunning guard keeps
        // the already-exited race from raising through Foundation).
        lock.lock()
        let alive = child.isRunning
        lock.unlock()
        if alive { child.terminate() }

        let deadline = Date().addingTimeInterval(McpLauncher.killGrace)
        while Date() < deadline {
            lock.lock()
            let stillAlive = child.isRunning
            lock.unlock()
            if !stillAlive { return .terminated }
            usleep(20_000)  // 20ms poll — bounded, no semaphore coupling
        }
        // The bound fired: SIGKILL the REGISTERED pid only (§8.5 — never a
        // global hunt; the pid came from our own registration table).
        kill(own, SIGKILL)
        return .killed
    }

    private func emit(_ line: String) {
        logBuffer.append(line)
        onLogLine?(line)
    }

    /// A line-splitting readability pump: chunks → newline-terminated
    /// lines; the final partial line flushes at EOF. stdout and stderr
    /// each run their own reader (merged at the LINE level — the two
    /// streams interleave, nothing is reordered inside a line).
    private static func pipeReader(
        _ handle: FileHandle, _ onLine: @escaping @Sendable (String) -> Void
    ) {
        let box = LineBox(onLine: onLine)
        handle.readabilityHandler = { fh in
            let chunk = fh.availableData
            if chunk.isEmpty {
                fh.readabilityHandler = nil
                box.flushTail()
                return
            }
            box.ingest(chunk)
        }
    }

    /// The incremental line splitter (lock-guarded; the readability
    /// handler's queue is not the caller's).
    private final class LineBox: @unchecked Sendable {
        private let lock = NSLock()
        private var pending = Data()
        private let onLine: @Sendable (String) -> Void

        init(onLine: @escaping @Sendable (String) -> Void) {
            self.onLine = onLine
        }

        func ingest(_ chunk: Data) {
            lock.lock()
            pending.append(chunk)
            var complete: [Data] = []
            while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                complete.append(pending[pending.startIndex..<newline])
                pending.removeSubrange(pending.startIndex...newline)
            }
            lock.unlock()
            for data in complete { deliver(data) }
        }

        func flushTail() {
            lock.lock()
            let tail = pending
            pending = Data()
            lock.unlock()
            if !tail.isEmpty { deliver(tail) }
        }

        private func deliver(_ data: Data) {
            guard let text = String(data: data, encoding: .utf8) else { return }
            onLine(text)
        }
    }
}

import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// AIWorkerClient (Plan M2-10-05 KD-3) — the editor-side face of the worker
// process: spawn, frame transport, the generation-counter lifecycle, and the
// device fallback chain. Lumen `Worker` (ai_worker.py:147-214) +
// `RemoteSession._call` (:266-282) paradigm, MIT read-only (structure
// ported, never code).
//
// M2AI-10 CONTRACT: an inference crash (native exit, timeout, pipe break)
// never escapes to the editor — the culprit units are recorded into the
// CompatRecord, the worker restarts (generation+1), and the request is
// retried on the next compute-units rung. There is NO in-process fallback
// (OQ-5-A): when the chain is exhausted the caller gets the typed
// `.workerExhausted`, and when the worker cannot even spawn it gets
// `.workerUnavailable` — an honest functional degradation, never a silent
// return of the crash risk into the editor process.
//
// THREADING: one serial queue owns the request lifecycle (spawn / write /
// deadline wait / chain), so requests are strictly single-flight; the async
// `AIInferencing` entry hops onto it via checked continuations. A pump
// thread blocks on the stdout pipe and deposits complete frames into a
// size-1 mailbox (single-flight = no queue), signalling a semaphore the
// deadline loop waits on in 1s slices so process death is noticed promptly
// (the Lumen 1s poll granularity).
// ─────────────────────────────────────────────────────────────────────────────

/// The typed failure face (consumers map these to honest UI states; the
/// search dialog / analysis registry already render unknown errors).
public enum AIWorkerClientError: Error, Equatable, Sendable {
    /// Spawn failed (executable absent, not runnable). The editor surfaces
    /// it as the feature-degraded face — NEVER an in-process fallback.
    case workerUnavailable(String)
    /// The worker died natively (crash hook / GPU fault), was killed after
    /// a timeout, or the pipe broke. Carries the Lumen-style detail.
    case workerCrashed(String)
    /// Every compute-units rung was consumed (recorded crashes plus
    /// MAX_RETRIES) — the M2-10-07 settings page points at the reset.
    case workerExhausted
    /// An error frame without a culprit (profile-level failure, e.g. assets
    /// absent) — retrying other units cannot help, so it surfaces directly.
    case requestFailed(String)
}

public final class AIWorkerClient: AIInferencing, @unchecked Sendable {

    // MARK: - Configuration (everything a test needs to inject)

    public struct Configuration {
        /// The spawned binary; nil = `Bundle.main.executableURL` (the
        /// same-binary fork — production and the direct-launch test host).
        public var executableURL: URL?
        /// The crash memo (path injected; the default path resolves at the
        /// App assembly point).
        public var record: CompatRecord
        /// Injected machine identity (tests never read sysctl).
        public var machineKey: String
        /// First-use model open may compile CoreML kernels (900s, Lumen
        /// parity); runs get 600s; the tests inject milliseconds.
        public var openTimeout: TimeInterval
        public var runTimeout: TimeInterval
        public var pingTimeout: TimeInterval
        /// The chain budget (Lumen MAX_RETRIES = 4).
        public var maxRetries: Int
        /// Explicit child environment; nil = inherit (the crash hook rides
        /// the inheritance in the lifecycle tests).
        public var childEnvironment: [String: String]?

        public init(
            executableURL: URL? = nil,
            record: CompatRecord,
            machineKey: String = CompatRecord.currentMachineKey(),
            openTimeout: TimeInterval = 900,
            runTimeout: TimeInterval = 600,
            pingTimeout: TimeInterval = 10,
            maxRetries: Int = 4,
            childEnvironment: [String: String]? = nil
        ) {
            self.executableURL = executableURL
            self.record = record
            self.machineKey = machineKey
            self.openTimeout = openTimeout
            self.runTimeout = runTimeout
            self.pingTimeout = pingTimeout
            self.maxRetries = maxRetries
            self.childEnvironment = childEnvironment
        }
    }

    /// The chain attempt order (KD-3; the ANE→GPU→CPU degradation ladder).
    static let attemptOrder: [AIComputeUnits] = [.all, .cpuAndGPU, .cpuOnly]

    private let configuration: Configuration
    /// The single-flight request domain (spawn/write/wait/chain live here).
    private let queue = DispatchQueue(label: "lightamer.ai.worker-client")

    // Process state — queue-confined.
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var generation = 0
    private var pumpThread: Thread?
    /// The (profile, units) session the CURRENT process has open (nil after
    /// every respawn — the session cache dies with the process).
    private var openSessionKey: String?
    /// The units of the last open attempt on the current process — the
    /// culprit attribution input for a death WITH no response (Lumen
    /// `self.provider`/`trying` parity).
    private var lastOpenedUnits: AIComputeUnits?

    // Response mailbox — lock + semaphore shared with the pump thread.
    private let mailboxLock = NSLock()
    private var mailboxFrame: Data?
    private var mailboxEOF = false
    private let mailboxSignal = DispatchSemaphore(value: 0)

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// Convenience for production/test assembly: default executable (this
    /// binary) + the injected record.
    public convenience init(record: CompatRecord) {
        self.init(configuration: Configuration(record: record))
    }

    // MARK: - Diagnostics / test observation

    /// The child's pid while it lives (tests: external kill legs).
    public var childProcessIdentifier: Int32? {
        queue.sync {
            guard let process, process.isRunning else { return nil }
            return process.processIdentifier
        }
    }

    /// The respawn counter (each crash-driven restart bumps it; the test
    /// asserts the generation restart chain).
    public var currentGeneration: Int {
        queue.sync { generation }
    }

    // MARK: - AIInferencing (the seam: consumers unchanged)

    public func embedText(
        _ profileID: String, tokens: [Int64], mask: [Int64]
    ) async throws -> [Float] {
        try await runOnQueue {
            try self.withFallbackChain(profile: profileID) { units in
                let response = try self.requestSync(
                    AIWorkerRequest(
                        id: self.nextRequestID(), op: AIWorkerOp.run.rawValue,
                        profile: profileID, units: units.rawValue,
                        payload: AIWorkerPayload(tokens: tokens, mask: mask)),
                    timeout: self.configuration.runTimeout)
                guard let embedding = response.result?.embedding else {
                    throw AIWorkerClientError.requestFailed(
                        response.error ?? "run returned no embedding")
                }
                return embedding
            }
        }
    }

    public func embedImage(
        _ profileID: String, jpeg: Data
    ) async throws -> [Float] {
        try await runOnQueue {
            try self.withFallbackChain(profile: profileID) { units in
                // The BYTE channel (OQ-10-C): the construction-time 8MB
                // boundary rejects oversized payloads — large images must
                // travel the path channel, never the pipe.
                let response = try self.requestSync(
                    AIWorkerRequest(
                        id: self.nextRequestID(), op: AIWorkerOp.run.rawValue,
                        profile: profileID, units: units.rawValue,
                        payload: AIWorkerPayload(
                            jpegBase64: jpeg.base64EncodedString())),
                    timeout: self.configuration.runTimeout)
                guard let embedding = response.result?.embedding else {
                    throw AIWorkerClientError.requestFailed(
                        response.error ?? "run returned no embedding")
                }
                return embedding
            }
        }
    }

    // MARK: - Enhancement tile channel (Plan M2-10-06 T3a, additive)

    /// The enhancement open's model facts (the supported tile edges + the
    /// super-resolution factor) — reported by the worker's open leg and
    /// memoized here on the LAST successful open (queue-confined; the
    /// embed paths never populate it, nil until an enhancement open).
    public private(set) var lastEnhancementModelFacts: (tileEdges: [Int], scale: Int)?

    /// Open the enhancement profile through the fallback chain and return
    /// the model facts. The session stays open for the subsequent tile
    /// runs (the same (profile, units) open cache).
    public func openEnhancement(
        _ profileID: String
    ) async throws -> (tileEdges: [Int], scale: Int) {
        try await runOnQueue {
            try self.withFallbackChain(profile: profileID) { units in
                try self.ensureOpen(profile: profileID, units: units)
                guard let facts = self.lastEnhancementModelFacts else {
                    throw AIWorkerClientError.requestFailed(
                        "enhancement open returned no model facts")
                }
                return facts
            }
        }
    }

    /// One tile through the PATH channel (the red line — the 8MB frame
    /// bound never applies to enhancement frames): the worker decodes
    /// `inPath` (16-bit RGB TIFF), runs the model at the feed shape
    /// (denoise blends output with input by amount/100 in the worker —
    /// the models carry no strength input), and writes `outPath`.
    /// Returns the output path (echo).
    @discardableResult
    public func enhanceTile(
        _ profileID: String, inPath: String, outPath: String,
        feedHeight: Int, feedWidth: Int, amount: Double?
    ) async throws -> String {
        try await runOnQueue {
            try self.withFallbackChain(profile: profileID) { units in
                let response = try self.requestSync(
                    AIWorkerRequest(
                        id: self.nextRequestID(), op: AIWorkerOp.run.rawValue,
                        profile: profileID, units: units.rawValue,
                        payload: AIWorkerPayload(
                            inPath: inPath, outPath: outPath,
                            tile: AITileParameters(
                                height: feedHeight, width: feedWidth,
                                amount: amount))),
                    timeout: self.configuration.runTimeout)
                guard response.ok, let outPath = response.result?.outPath else {
                    // A run-level error frame: the worker is healthy (the
                    // session was already opened) — surface typed, no chain
                    // consumption (the embedText precedent).
                    throw AIWorkerClientError.requestFailed(
                        response.error ?? "tile run returned no output path")
                }
                return outPath
            }
        }
    }

    // MARK: - Liveness (tests + health diagnostics)

    /// One ping round trip against a (possibly freshly spawned) worker.
    /// Returns the child pid. Deliberately OUTSIDE the fallback chain — a
    /// liveness probe surfaces crashes to the caller directly.
    @discardableResult
    public func ping(timeout: TimeInterval? = nil) async throws -> Int {
        try await runOnQueue {
            let response = try self.requestSync(
                AIWorkerRequest(
                    id: self.nextRequestID(), op: AIWorkerOp.ping.rawValue),
                timeout: timeout ?? self.configuration.pingTimeout)
            guard let pid = response.result?.pid else {
                throw AIWorkerClientError.requestFailed("ping returned no pid")
            }
            return pid
        }
    }

    /// The graceful stop: a `stop` op (the worker clears its session cache
    /// and exits 0), bounded; a hung child is killed. Idempotent.
    public func stop() async {
        try? await runOnQueue {
            if let process = self.process, process.isRunning {
                let request = AIWorkerRequest(
                    id: self.nextRequestID(), op: AIWorkerOp.stop.rawValue)
                if let frame = try? AIWorkerFrameCodec.encode(request: request),
                   let stdin = self.stdinHandle {
                    try? stdin.write(contentsOf: frame)
                }
                let deadline = Date().addingTimeInterval(5)
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning {
                    _ = self.killChild(process)
                }
            }
            self.teardownProcess()
        }
    }

    // MARK: - The fallback chain (KD-3)

    /// The digestible failure shapes INSIDE the chain (the public errors
    /// above are what escapes it).
    private enum ChainFailure: Error {
        /// Timeout / death / exit != 0 — the process is gone.
        case crash(String)
        /// An error frame WITH a culprit: the worker is healthy but the
        /// model cannot run on those units.
        case unitsRejected(AIComputeUnits, String)
        /// An error frame WITHOUT a culprit: profile-level — other units
        /// cannot help.
        case profileFailed(String)
    }

    private func withFallbackChain<R>(
        profile: String, body: (AIComputeUnits) throws -> R
    ) throws -> R {
        let excluded = configuration.record.excluded(
            machineKey: configuration.machineKey, model: profile)
        var chain = Self.attemptOrder.filter { !excluded.contains($0) }
        var attempts = 0
        while attempts < configuration.maxRetries {
            guard let units = chain.first else {
                throw AIWorkerClientError.workerExhausted
            }
            do {
                try ensureOpen(profile: profile, units: units)
                return try body(units)
            } catch {
                // Two error worlds meet here: the requestSync transport
                // failures are PUBLIC errors (ping surfaces them directly),
                // the response-frame failures are ChainFailures. The chain
                // digests crashes + units rejections; everything else —
                // notably a run-level requestFailed — surfaces untouched.
                let failure: ChainFailure
                switch error as? AIWorkerClientError {
                case .workerCrashed(let detail):
                    failure = .crash(detail)
                default:
                    if let chainFailure = error as? ChainFailure {
                        failure = chainFailure
                    } else {
                        throw error  // a run-level failure: the worker is healthy
                    }
                }
                attempts += 1
                switch failure {
                case .crash(let detail):
                    // Culprit = the crash's victim (the last-opened attempt
                    // units — no response frame ever arrived). The CPU floor
                    // is never recorded (CompatRecord ignores it too), but it
                    // IS dropped from the chain so the ladder terminates.
                    let culprit = lastOpenedUnits ?? units
                    configuration.record.record(
                        machineKey: configuration.machineKey, model: profile,
                        units: culprit, detail: detail)
                    chain.removeAll { $0 == culprit }
                    respawn()
                case .unitsRejected(let rejected, let message):
                    configuration.record.record(
                        machineKey: configuration.machineKey, model: profile,
                        units: rejected, detail: message)
                    chain.removeAll { $0 == rejected }
                    // The worker survived — no respawn; the next open runs
                    // on the same process.
                    openSessionKey = nil
                case .profileFailed(let message):
                    throw AIWorkerClientError.requestFailed(message)
                }
                // The chain stays INCREMENTAL: re-deriving it from the
                // record would resurrect a CPU-removed rung (the record
                // never carries CPU crashes by design).
            }
        }
        throw AIWorkerClientError.workerExhausted
    }

    private func ensureOpen(profile: String, units: AIComputeUnits) throws {
        let key = profile + "␟" + units.rawValue
        if openSessionKey == key, let process, process.isRunning {
            return
        }
        // Attribute a death during THIS open to THESE units.
        lastOpenedUnits = units
        let response = try requestSync(
            AIWorkerRequest(
                id: self.nextRequestID(), op: AIWorkerOp.open.rawValue,
                profile: profile, units: units.rawValue),
            timeout: configuration.openTimeout)
        guard response.ok else {
            if let culprit = response.culpritUnitsKind {
                throw ChainFailure.unitsRejected(culprit, response.error ?? "open failed")
            }
            throw ChainFailure.profileFailed(response.error ?? "open failed")
        }
        openSessionKey = key
        // The enhancement model facts ride the open response (M2-10-06);
        // cleared with the session so a CLIP open never leaves stale facts.
        if let edges = response.result?.tileEdges, let scale = response.result?.scale {
            lastEnhancementModelFacts = (tileEdges: edges, scale: scale)
        } else {
            lastEnhancementModelFacts = nil
        }
    }

    // MARK: - The request cycle (queue-confined)

    private func requestSync(
        _ request: AIWorkerRequest, timeout: TimeInterval
    ) throws -> AIWorkerResponse {
        if process == nil || !(process?.isRunning ?? false) {
            do {
                try spawn()
            } catch let error as AIWorkerClientError {
                throw error
            } catch {
                throw AIWorkerClientError.workerUnavailable("\(error)")
            }
        }
        // Clear the mailbox (single-flight: nothing stale can be pending).
        mailboxLock.lock()
        mailboxFrame = nil
        mailboxEOF = false
        mailboxLock.unlock()
        while mailboxSignal.wait(timeout: .now()) == .success {}

        guard let frame = try? AIWorkerFrameCodec.encode(request: request) else {
            throw AIWorkerClientError.requestFailed("request encode failed")
        }
        do {
            try stdinHandle?.write(contentsOf: frame)
        } catch {
            throw foldDeath(detail: "write failed: \(error.localizedDescription)")
        }

        let started = Date()
        var deadline = started.addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                // Lumen :197-199: kill, then fold into WorkerCrashed.
                _ = killAndTeardown()
                throw AIWorkerClientError.workerCrashed(
                    "no response within \(Int(timeout)) s")
            }
            let slice = min(remaining, 1)
            if mailboxSignal.wait(timeout: .now() + slice) == .success {
                mailboxLock.lock()
                let frame = mailboxFrame
                let eof = mailboxEOF
                mailboxLock.unlock()
                if let frame {
                    let response: AIWorkerResponse
                    do {
                        // The pump hands us the payload bytes only (the
                        // prefix was consumed by the reader).
                        response = try AIWorkerFrameCodec.decodeResponse(frame)
                    } catch {
                        // A response frame that cannot be decoded means the
                        // peer is broken — survivable for the WORKER side,
                        // but on the client it is a protocol violation: fold
                        // (a respawn realigns everything).
                        throw foldDeath(detail: "response decode failed")
                    }
                    if response.id != request.id {
                        // Not ours (defensive; single-flight makes this
                        // unreachable) — keep waiting.
                        continue
                    }
                    return response
                }
                if eof {
                    throw foldDeath(detail: "pipe closed")
                }
            }
            if let process, !process.isRunning {
                throw foldDeath(detail: "process exited")
            }
        }
    }

    // MARK: - Process lifecycle

    private func spawn() throws {
        guard process == nil else { return }
        // A dead child's pipe must surface as an EPIPE error (folded into
        // the typed crash below), never as the default SIGPIPE process
        // death. Process-wide and idempotent — a GUI app never relies on
        // being killed by SIGPIPE.
        signal(SIGPIPE, SIG_IGN)
        let executableURL = configuration.executableURL
            ?? Bundle.main.executableURL
        guard let executableURL,
              FileManager.default.fileExists(atPath: executableURL.path)
        else {
            throw AIWorkerClientError.workerUnavailable(
                "AI worker executable not found at "
                    + "\(executableURL?.path ?? "<nil>")")
        }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [AIWorkerMain.launchFlag]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        if let childEnvironment = configuration.childEnvironment {
            process.environment = childEnvironment
        }
        do {
            try process.run()
        } catch {
            throw AIWorkerClientError.workerUnavailable(
                "spawn failed: \(error.localizedDescription)")
        }
        self.process = process
        stdinHandle = stdin.fileHandleForWriting
        generation += 1
        openSessionKey = nil
        lastOpenedUnits = nil
        startPump(reader: AIWorkerFrameReader(handle: stdout.fileHandleForReading))
    }

    /// Crash-driven restart: reap whatever remains and let the next request
    /// spawn a fresh generation (Lumen `generation += 1` per start parity).
    private func respawn() {
        teardownProcess()
    }

    private func killAndTeardown() -> AIWorkerClientError {
        if let process = process {
            _ = killChild(process)
        }
        teardownProcess()
        let code = process.map { "\($0.terminationStatus)" } ?? "?"
        return .workerCrashed("killed after timeout, exit code \(code)")
    }

    /// SIGKILL + bounded reap — no zombies (the plan's risk item: the
    /// termination status must stay readable).
    private func killChild(_ process: Process) -> AIWorkerClientError {
        var detail = "killed"
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            detail = "killed, exit code \(process.terminationStatus)"
        } else {
            detail = "exit code \(process.terminationStatus)"
        }
        return .workerCrashed(detail)
    }

    private func teardownProcess() {
        if let process = process, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
        process = nil
        stdinHandle = nil
        openSessionKey = nil
        lastOpenedUnits = nil
        lastEnhancementModelFacts = nil
        pumpThread = nil
    }

    /// Folds any transport-level damage into the typed crash with the
    /// exit code attached (the Lumen detail format), after reaping.
    private func foldDeath(detail: String) -> AIWorkerClientError {
        var exitDetail = ""
        if let process {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            exitDetail = ", exit code \(process.terminationStatus)"
        }
        teardownProcess()
        return .workerCrashed("\(detail)\(exitDetail)")
    }

    private func startPump(reader: AIWorkerFrameReader) {
        let thread = Thread { [weak self] in
            while true {
                let read: AIWorkerFrameRead?
                do {
                    read = try reader.readFrame()
                } catch {
                    self?.deposit(nil, eof: true)
                    break
                }
                guard let read else {
                    self?.deposit(nil, eof: true)
                    break
                }
                guard case .frame(let payload) = read else {
                    // An oversize RESPONSE frame is a protocol violation —
                    // surface it as EOF (the request loop folds).
                    self?.deposit(nil, eof: true)
                    break
                }
                self?.deposit(payload, eof: false)
            }
        }
        thread.name = "LightamerAIWorkerPump"
        thread.stackSize = 1 << 20
        pumpThread = thread
        thread.start()
    }

    private func deposit(_ frame: Data?, eof: Bool) {
        mailboxLock.lock()
        if eof {
            mailboxEOF = true
        } else {
            mailboxFrame = frame
        }
        mailboxLock.unlock()
        mailboxSignal.signal()
    }

    private func runOnQueue<R>(_ body: @escaping () throws -> R) async throws -> R {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try body())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Request ids

    /// Queue-confined monotonic ids (unique per connection is the only
    /// requirement — single-flight makes matching trivial).
    private var requestID: UInt64 = 0

    private func nextRequestID() -> UInt64 {
        requestID += 1
        return requestID
    }
}

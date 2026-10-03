import CoreML
import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// AIWorkerMain (Plan M2-10-05 KD-2) — the inference worker PROCESS BODY.
//
// Forked from the same binary via `Lightamer --ai-worker` (OQ-5-A, the
// Phase 14 `--mcp` headless-fork precedent: this arm NEVER constructs the
// SwiftUI App — `LightamerEntryPoint.main` returns before `LightamerApp.main()`
// and this file parks the process in the frame loop forever). The arm order
// in the entry point is: flock fixture (DEBUG) → `--mcp` → `--ai-worker` →
// GUI.
//
// HEADLESS DISCIPLINE: this file imports Foundation/CoreML/LightamerCore
// only — no SwiftUI, no AppKit.
//
// SESSION CACHE: one `InProcessMLModelRunner` per `(profileID, units)` — the
// SAME Core conformer the M2-10-02/03 assembly used in-process, now living
// on the worker side of the pipe (it compiles/caches the .mlmodelc and runs
// the towers; reuse = zero duplicated loading code). The compiled-model
// cache directory is the worker's own tree so the (retained-as-test-fixture)
// in-process cache never collides.
//
// CRASH INJECTION HOOK (test-only, DEBUG + env DOUBLE gate — RELEASE builds
// carry no such code path): `LIGHTAMER_TEST_AI_WORKER_CRASH=<profileID>`
// makes the OPEN of that profile exit(9) (a native-crash simulation; Lumen
// `LUMEN_TEST_WORKER_CRASH` ai_worker.py:73-75 paradigm). The extended
// form `<profileID>@all,cpuAndGPU` restricts the crash to the listed units
// (no `@` = crash on every open) so tests can inject crash SEQUENCES down
// the fallback chain. Default: off.
//
// PROTOCOL EDGE (KD-1): a decode-failed frame or an oversize prefix is
// survivable — the worker answers an error frame and keeps reading (the
// length prefix keeps the stream aligned). Only EOF/persistent damage ends
// the loop (exit 0 — the parent reads it as a pipe close, not a crash).
// ─────────────────────────────────────────────────────────────────────────────

enum AIWorkerMain {

    /// The launch flag the entry point forks on (also the client's spawn
    /// argument — one constant, both sides).
    static let launchFlag = "--ai-worker"

    /// The entry-point fork arm. Returns false when the flag is absent (the
    /// GUI path continues); on the worker arm this NEVER returns.
    @discardableResult
    static func runIfRequested(
        arguments: [String] = CommandLine.arguments
    ) -> Bool {
        guard arguments.contains(launchFlag) else { return false }
        run()
    }

    /// Parks the process in the frame loop forever. The loop itself runs on
    /// a detached task (the tower forwards are async); the main thread —
    /// which entered through `LightamerEntryPoint.main` — is parked with
    /// `dispatchMain()` so it can never unwind back into the GUI path.
    static func run(
        input: FileHandle = .standardInput,
        output: FileHandle = .standardOutput
    ) -> Never {
        // SIGTERM = the graceful stop (Lumen ai_worker.py:44-47 parity): a
        // clean exit 0. The tmp files of the enhancement channel are the
        // PARENT's jurisdiction; this side only releases its own session
        // memory (and the OS reclaims the CoreML caches with the process).
        signal(SIGTERM) { _ in exit(0) }
        let loop = WorkerLoop(input: input, output: output)
        Task.detached(priority: .userInitiated) {
            await loop.serve()  // returns on EOF / stop / fatal pipe damage
            exit(0)
        }
        dispatchMain()  // never returns
    }

    // MARK: - Crash injection hook (DEBUG + env double gate)

    #if DEBUG
    static let crashHookEnvironment = "LIGHTAMER_TEST_AI_WORKER_CRASH"

    /// `<profileID>` crashes every open of that profile;
    /// `<profileID>@all,cpuAndGPU` crashes only the listed units.
    static func crashHookShouldFire(
        profile: String, units: AIComputeUnits
    ) -> Bool {
        let raw = ProcessInfo.processInfo.environment[crashHookEnvironment] ?? ""
        guard !raw.isEmpty else { return false }
        let parts = raw.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.first == profile else { return false }
        guard parts.count == 2 else { return true }
        return parts[1].split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .contains(units.rawValue)
    }
    #endif

    // MARK: - IPC spike op (DEBUG-only; the OQ-10-C microbenchmark)

    #if DEBUG
    /// The DEBUG-only transport probe: echoes the byte-channel payload size
    /// or the file size at the path channel, so the spike measures the REAL
    /// end-to-end pipe round trip through the worker process. RELEASE
    /// binaries do not know this op (an unknown-op error frame).
    static let spikeOp = "spike"
    #endif

    // MARK: - Session keying + cache

    static func sessionKey(profile: String, units: AIComputeUnits) -> String {
        "\(profile)␟\(units.rawValue)"
    }

    /// The worker's OWN compiled-model cache (a rebuildable Caches-class
    /// derivative), per profile — never the in-process fixture's tree.
    static func compiledCacheDirectory(profile: String) -> URL? {
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        return caches
            .appendingPathComponent("Lightamer", isDirectory: true)
            .appendingPathComponent("compiled-models-worker", isDirectory: true)
            .appendingPathComponent(profile, isDirectory: true)
    }
}

/// The sequential frame loop. One request at a time, answered in order —
/// the worker is a dedicated single-purpose process, so no pipelining.
private actor WorkerLoop {

    private let input: FileHandle
    private let output: FileHandle
    private let locator = ModelLocator()
    private var sessions: [String: InProcessMLModelRunner] = [:]
    /// The enhancement family's sessions (Plan M2-10-06): one per
    /// (profile, units), carrying the model's shape facts.
    private var enhancementSessions: [String: EnhancementSession] = [:]
    private var anonymousID: UInt64 = 0

    init(input: FileHandle, output: FileHandle) {
        self.input = input
        self.output = output
    }

    /// Sequential frame loop. The async tower forwards are AWAITED INLINE:
    /// a child Task would deadlock here — `serve` hogs this actor's executor
    /// with the blocking pipe reads, so a detached forward could never run.
    /// Await suspension is the only release point (and the client is
    /// strictly single-flight, so inline ordering is the contract anyway).
    func serve() async {
        let reader = AIWorkerFrameReader(handle: input)
        while true {
            let read: AIWorkerFrameRead?
            do {
                read = try reader.readFrame()
            } catch {
                return  // mid-frame EOF: the parent is gone or the pipe broke
            }
            guard let read else { return }  // clean EOF
            guard case .frame(let payload) = read else {
                // Survivable corruption: the reader skipped the oversized
                // payload; the connection stays alive (KD-1 tolerance).
                let declared: UInt32
                if case .oversize(let bytes) = read { declared = bytes } else {
                    declared = 0
                }
                sendError(
                    anonymousID,
                    "frame of \(declared) bytes exceeds the "
                        + "\(AIWorkerFrameCodec.maxFrameBytes)-byte bound",
                    nil)
                anonymousID += 1
                continue
            }

            let request: AIWorkerRequest
            do {
                request = try AIWorkerFrameCodec.decodeRequest(payload)
            } catch {
                sendError(anonymousID, "\(error)", nil)
                anonymousID += 1
                continue
            }

            switch request.opKind {
            case .ping:
                send(AIWorkerResponse(
                    id: request.id, ok: true,
                    result: AIWorkerResult(pid: Int(getpid()))))
            case .open:
                open(request)
            case .run:
                await run(request)
            case .stop:
                send(AIWorkerResponse(id: request.id, ok: true))
                sessions.removeAll()
                enhancementSessions.removeAll()
                return
            case nil:
                #if DEBUG
                if request.op == AIWorkerMain.spikeOp {
                    spike(request)
                    break
                }
                #endif
                sendError(request.id, "unknown op: \(request.op)", nil)
            }
        }
    }

    // MARK: - senders

    private func send(_ response: AIWorkerResponse) {
        if let frame = try? AIWorkerFrameCodec.encode(response: response) {
            try? output.write(contentsOf: frame)
        }
    }

    private func sendError(
        _ id: UInt64, _ message: String, _ culprit: AIComputeUnits?
    ) {
        send(AIWorkerResponse(
            id: id, ok: false, error: message,
            culpritUnits: culprit?.rawValue))
    }

    // MARK: - open

    private func open(_ request: AIWorkerRequest) {
        guard let profile = request.profile, !profile.isEmpty,
              let units = request.unitsKind
        else {
            sendError(request.id, "open requires profile and units", nil)
            return
        }
        let key = AIWorkerMain.sessionKey(profile: profile, units: units)
        if sessions[key] != nil {
            send(AIWorkerResponse(
                id: request.id, ok: true,
                result: AIWorkerResult(profile: profile, units: units.rawValue)))
            return
        }
        // The crash hook fires BEFORE any asset resolution — a toy profile
        // with no real assets still crashes (the tests rely on this).
        #if DEBUG
        if AIWorkerMain.crashHookShouldFire(profile: profile, units: units) {
            Darwin.exit(9)
        }
        #endif
        // Profile-level failure (assets absent from THIS install): answered
        // WITHOUT a culprit — retrying other compute units cannot help.
        guard let manifest = ModelAssetCatalog.manifest(for: profile) else {
            sendError(
                request.id, "profile assets absent: \(profile)", nil)
            return
        }
        // The enhancement family opens through its OWN leg (M2-10-06): one
        // package, the static-shape facts read from the model description.
        guard manifest.embeddingDim != nil else {
            openEnhancementLeg(
                request, profile: profile, units: units, manifest: manifest)
            return
        }
        guard let profileDirectory = locator.bundledProfileURL(profile) else {
            sendError(
                request.id, "profile assets absent: \(profile)", nil)
            return
        }
        // Units-level load failure (the ANE/GPU compilation can genuinely
        // fail per device): answered WITH the culprit — the client's
        // degradation bookkeeping input (KD-2).
        do {
            let imageURL = profileDirectory.appendingPathComponent(
                manifest.assetFileName)
            let textURL = profileDirectory.appendingPathComponent(
                manifest.assetFileName.replacingOccurrences(
                    of: "-img.", with: "-txt."))
            let runner = try InProcessMLModelRunner(
                imageModelURL: imageURL, textModelURL: textURL,
                computeUnits: units.mlComputeUnits,
                compileCacheDirectory: AIWorkerMain.compiledCacheDirectory(
                    profile: profile))
            sessions[key] = runner
        } catch {
            sendError(
                request.id,
                "model load failed on \(units.rawValue): \(error)", units)
            return
        }
        send(AIWorkerResponse(
            id: request.id, ok: true,
            result: AIWorkerResult(profile: profile, units: units.rawValue)))
    }

    /// The enhancement open leg (Plan M2-10-06): resolve the package
    /// (bundled folder reference first, then the installed Application
    /// Support root), compile+load with the requested compute units, and
    /// report the model's shape facts (supported tile edges + the
    /// super-resolution factor) so the editor's planner never guesses.
    /// Asset absence = profile-level (no culprit); a load failure on the
    /// requested units = units-level (the degradation input).
    private func openEnhancementLeg(
        _ request: AIWorkerRequest,
        profile: String, units: AIComputeUnits,
        manifest: ModelAssetManifest
    ) {
        let key = AIWorkerMain.sessionKey(profile: profile, units: units)
        if enhancementSessions[key] != nil {
            respondEnhancementFacts(request, profile: profile, units: units)
            return
        }
        guard let package = EnhancementSession.resolvePackage(
            profile: profile, manifest: manifest, locator: locator)
        else {
            sendError(
                request.id, "profile assets absent: \(profile)", nil)
            return
        }
        do {
            let session = try EnhancementSession(
                packageURL: package, manifest: manifest,
                computeUnits: units.mlComputeUnits,
                compileCacheDirectory: AIWorkerMain.compiledCacheDirectory(
                    profile: profile))
            enhancementSessions[key] = session
        } catch {
            sendError(
                request.id,
                "model load failed on \(units.rawValue): \(error)", units)
            return
        }
        respondEnhancementFacts(request, profile: profile, units: units)
    }

    private func respondEnhancementFacts(
        _ request: AIWorkerRequest, profile: String, units: AIComputeUnits
    ) {
        let key = AIWorkerMain.sessionKey(profile: profile, units: units)
        guard let session = enhancementSessions[key] else { return }
        send(AIWorkerResponse(
            id: request.id, ok: true,
            result: AIWorkerResult(
                profile: profile, units: units.rawValue,
                tileEdges: session.supportedEdges, scale: session.scale)))
    }

    // MARK: - run

    private func run(_ request: AIWorkerRequest) async {
        guard let profile = request.profile,
              let units = request.unitsKind,
              let payload = request.payload
        else {
            sendError(
                request.id, "run before open: \(request.profile ?? "-")", nil)
            return
        }
        let key = AIWorkerMain.sessionKey(profile: profile, units: units)
        if let runner = sessions[key] {
            await forwardRun(request, runner: runner, payload: payload)
            return
        }
        if let enhancement = enhancementSessions[key] {
            await forwardPathRun(request, session: enhancement, payload: payload)
            return
        }
        sendError(
            request.id, "run before open: \(request.profile ?? "-")", nil)
    }

    private func forwardRun(
        _ request: AIWorkerRequest,
        runner: InProcessMLModelRunner,
        payload: AIWorkerPayload
    ) async {
        do {
            if let tokens = payload.tokens, let mask = payload.mask {
                let embedding = try await runner.embedText(
                    request.profile ?? "", tokens: tokens, mask: mask)
                send(AIWorkerResponse(
                    id: request.id, ok: true,
                    result: AIWorkerResult(embedding: embedding)))
                return
            }
            if let base64 = payload.jpegBase64,
               let jpeg = Data(base64Encoded: base64) {
                let embedding = try await runner.embedImage(
                    request.profile ?? "", jpeg: jpeg)
                send(AIWorkerResponse(
                    id: request.id, ok: true,
                    result: AIWorkerResult(embedding: embedding)))
                return
            }
            if payload.inPath != nil {
                // A path-channel run without an open enhancement session:
                // the open leg must run first (the run-before-open face).
                sendError(
                    request.id,
                    "path-channel run before open: \(request.profile ?? "-")",
                    nil)
                return
            }
            sendError(request.id, "run payload carries no known variant", nil)
        } catch {
            // A run-level failure leaves the worker healthy — answered, not
            // crashed (Lumen `'error'` string parity, ai_worker.py:94-96).
            sendError(request.id, "run failed: \(error)", nil)
        }
    }

    /// The PATH channel's inference leg (Plan M2-10-06, the M2-10-05
    /// placeholder retired): the enhancement session decodes the input
    /// tile (16-bit RGB TIFF), runs the model at the FEED shape from
    /// `tile`, blends the denoise amount (worker-side — the models carry
    /// no strength input), and writes the output tile (16-bit TIFF).
    private func forwardPathRun(
        _ request: AIWorkerRequest, session: EnhancementSession,
        payload: AIWorkerPayload
    ) async {
        guard let inPath = payload.inPath,
              let outPath = payload.outPath
        else {
            sendError(
                request.id,
                "path-channel run requires inPath and outPath", nil)
            return
        }
        let feedHeight = payload.tile?.height ?? session.supportedEdges.first ?? 0
        let feedWidth = payload.tile?.width ?? session.supportedEdges.first ?? 0
        do {
            try await session.runTile(
                inPath: URL(fileURLWithPath: inPath),
                outPath: URL(fileURLWithPath: outPath),
                feedHeight: feedHeight, feedWidth: feedWidth,
                amount: payload.tile?.amount)
            send(AIWorkerResponse(
                id: request.id, ok: true,
                result: AIWorkerResult(outPath: outPath)))
        } catch {
            // The worker stays healthy (the Lumen error-frame parity).
            sendError(request.id, "run failed: \(error)", nil)
        }
    }

    // MARK: - spike (DEBUG)

    #if DEBUG
    private func spike(_ request: AIWorkerRequest) {
        guard let payload = request.payload else {
            sendError(request.id, "spike requires a payload", nil)
            return
        }
        if let base64 = payload.jpegBase64,
           let bytes = Data(base64Encoded: base64) {
            send(AIWorkerResponse(
                id: request.id, ok: true,
                result: AIWorkerResult(bytes: bytes.count)))
            return
        }
        if let path = payload.inPath,
           let attributes = try? FileManager.default.attributesOfItem(
                atPath: path),
           let size = attributes[.size] as? Int {
            // The path channel's transport cost = the worker READING the
            // file; a full read proves the file leg (the bytes are not
            // consumed further — the inference leg is 06).
            if let handle = FileHandle(forReadingAtPath: path) {
                var remaining = size
                while remaining > 0 {
                    let chunk = handle.readData(
                        ofLength: min(remaining, 1 << 20))
                    if chunk.isEmpty { break }
                    remaining -= chunk.count
                }
                try? handle.close()
                send(AIWorkerResponse(
                    id: request.id, ok: true,
                    result: AIWorkerResult(bytes: size - remaining)))
                return
            }
            sendError(request.id, "spike cannot read \(path)", nil)
            return
        }
        sendError(request.id, "spike payload carries no known variant", nil)
    }
    #endif
}

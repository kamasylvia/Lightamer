import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// ExportQueue (Plan 11-04 T1, EXP-06/07) — the session-scoped export queue
// actor. Structural twin of the 9-3 SessionThumbnailProvider skeleton
// (:112-310): actor isolation + generation epoch + bounded concurrency + an
// execute-time gate — with the export deltas from RESEARCH §4.1:
//
//   • concurrency LOCKED to 1 (ExportQueueContract.concurrency — NOT a
//     parameter). The memory red line: a full-res float32 working plane is
//     ≈1.6 GB at 100 MP; with pipe intermediates and the exit bitmap a
//     single job peaks ≈5 GB (RESEARCH §4.5), so two concurrent jobs break
//     the budget. (Named constant keeps Phase-15 tuning a one-line diff.)
//   • NO idle-delay / visible-jump scheduling — export is THROUGHPUT, not
//     interactive (RESEARCH §4.1 explicit); jobs run pure FIFO by seq.
//   • NO automatic retry (dt `control_jobs.c` `_control_export_job_run`
//     posture — a failed store cancels the job; the user re-queues via the
//     explicit `retry(jobID)`).
//   • TWO-LAYER progress: queue `(done, total)` (N variants → N jobs count
//     into total, EXP-07) + the in-flight job's coarse `phase`
//     (rendering|encoding — no intra-render percentage exists: a single
//     pipe call has no progress points).
//   • `yieldsToEditor` interface slot stays UNIMPLEMENTED (OQ-11-8 —
//     `ExportQueueContract.yieldsToEditor`).
//
// TaskLocal discipline (the 11-03 handoff note): the job runner submits as
// `Task.detached(priority: .utility)` — a detached task inherits NO
// TaskLocals — so EVERY leg call is wrapped in
// `MetalContext.$routesToExportQueue.withValue(true)` at this level. The
// default legs also re-wrap internally (the 11-03 renderer); the explicit
// wrapper here is the structural guarantee the handoff note pins.
//
// Deltas from the 9-3 skeleton (execution decisions, 11-04-DECISIONS):
//   • NO per-job waiter continuations — export is fire-and-forget; results
//     are observed through `snapshots()` + the `onProgressChange` hook
//     (the 9-3 `thumbnail(for:)` await face does not exist here).
//   • The render→encode split across the leg boundary (D-11-01 D3's real
//     fill): a cancelled in-flight job at the boundary leaves NOTHING on
//     disk — the render stage names the destination but writes nothing.
// ─────────────────────────────────────────────────────────────────────────────

public actor ExportQueue {

    private static let logger = AppError.logger

    // MARK: - The job record (actor-private; never crosses the boundary)

    private struct ExportJob {
        let id: UUID
        let imageURL: URL
        let relPath: String
        let variant: ExportVariant
        let destinationDirectory: URL
        let instancesOverride: [ModuleInstance]?
        let editorSignature: String?
        /// FIFO arrival order (retried jobs get a FRESH seq — the re-queue
        /// lands at the tail; only `retry` mutates this).
        var seq: Int
        /// The cancel epoch this job belongs to.
        var generation: Int
        var state: ExportJobState

        func snapshot() -> ExportJobSnapshot {
            ExportJobSnapshot(
                id: id, imageURL: imageURL, relPath: relPath,
                variants: [variant], seq: seq, generation: generation,
                state: state)
        }
    }

    // MARK: - Dependencies

    private let metal: MetalContext?
    private let registry: ModuleRegistry
    private let yiyinInjector: ExportYiyinInjector?
    private let decodeLeg: (@Sendable (URL) async throws -> DecodedImage)?
    private let renderLeg: ExportRenderLeg
    private let encodeLeg: ExportEncodeLeg
    /// Occupancy enumeration at DEQUEUE time (the 11-03 E2E collision
    /// lesson — names must be re-read when the job actually runs, so a
    /// same-batch predecessor's promoted file is seen). The default
    /// provider lists the directory's entries; tests inject fixed sets.
    private let occupiedNamesProvider: @Sendable (URL) -> Set<String>

    // MARK: - Queue state (the 9-3 shape)

    /// The worker width: EXACTLY ONE (D-11-CONTEXT-2 — the contract
    /// constant, never a parameter).
    public static let concurrency = ExportQueueContract.concurrency

    /// Jobs in arrival order, still waiting for a worker slot.
    private var pending: [ExportJob] = []
    private var inFlight = 0
    private var jobs: [UUID: ExportJob] = [:]
    /// Monotonic FIFO order (never reset — retried jobs queue at the tail).
    private var seqCounter = 0
    /// The cancel epoch — `cancelAll` bumps it; results from stale
    /// generations are discarded at the execute gate.
    private var generation = 0
    /// In-flight jobs the user cancelled (the render→encode boundary and
    /// the gates consult this; pending cancels resolve synchronously).
    private var cancelledInFlight: Set<UUID> = []
    /// Per-generation progress window (`total` counts every enqueue of the
    /// current epoch — settled jobs decrement `done` no earlier than their
    /// terminal transition).
    private var progressTotal = 0
    private var progressDone = 0

    /// Fired after every state/progress mutation. The ExportState bridge
    /// installs a closure that hops to the MainActor and re-reads the
    /// snapshots; tests usually leave it nil. (Actor-isolated storage —
    /// set through `setProgressHook`; notifications detach a task so the
    /// hook never blocks the pump.)
    private var progressHook: (@Sendable () async -> Void)?

    public func setProgressHook(_ hook: (@Sendable () async -> Void)?) {
        progressHook = hook
    }

    /// The per-job COMPLETION hook (EXP-08's per-job post-action trigger,
    /// OQ-11-7: every promoted FILE fires once — the dt `darktable|exported`
    /// per-image semantics). Fired ONLY for `.done` jobs (a failed job
    /// never triggers a post-action); NOT fired for stale-generation
    /// stragglers (their files never landed). Fire-and-forget — the queue
    /// never awaits the hook.
    private var completionHook: (@Sendable (ExportJobSnapshot, URL) async -> Void)?

    public func setCompletionHook(
        _ hook: (@Sendable (ExportJobSnapshot, URL) async -> Void)?
    ) {
        completionHook = hook
    }

    public init(
        metal: MetalContext?,
        registry: ModuleRegistry,
        yiyinInjector: ExportYiyinInjector? = nil,
        decodeLeg: (@Sendable (URL) async throws -> DecodedImage)? = nil,
        renderLeg: ExportRenderLeg? = nil,
        encodeLeg: ExportEncodeLeg? = nil,
        occupiedNamesProvider: (@Sendable (URL) -> Set<String>)? = nil
    ) {
        self.metal = metal
        self.registry = registry
        self.yiyinInjector = yiyinInjector
        self.decodeLeg = decodeLeg
        if let renderLeg, let encodeLeg {
            self.renderLeg = renderLeg
            self.encodeLeg = encodeLeg
        } else {
            (self.renderLeg, self.encodeLeg) = Self.productionLegs(
                metal: metal, registry: registry, yiyinInjector: yiyinInjector,
                decodeLeg: decodeLeg)
        }
        self.occupiedNamesProvider = occupiedNamesProvider ?? Self.defaultOccupiedNames
    }

    // MARK: - Enqueue (EXP-07: N images × M variants → N×M jobs, ONE call)

    /// Fan a queue action out: one job PER VARIANT per image (the variant
    /// order interleaves per image — image0-v0, image0-v1, … — so a
    /// cancelled batch still completes whole files of the earlier
    /// images first). Returns the fresh snapshots in enqueue order.
    @discardableResult
    public func enqueue(
        images: [(url: URL, relPath: String)],
        variants: [ExportVariant],
        destinationDirectory: URL,
        instancesOverride: [ModuleInstance]? = nil,
        editorSignature: String? = nil
    ) -> [ExportJobSnapshot] {
        var fresh: [ExportJobSnapshot] = []
        fresh.reserveCapacity(images.count * variants.count)
        for image in images {
            for variant in variants {
                seqCounter += 1
                progressTotal += 1
                let job = ExportJob(
                    id: UUID(),
                    imageURL: image.url,
                    relPath: image.relPath,
                    variant: variant,
                    destinationDirectory: destinationDirectory,
                    instancesOverride: instancesOverride,
                    editorSignature: editorSignature,
                    seq: seqCounter,
                    generation: generation,
                    state: .pending)
                jobs[job.id] = job
                pending.append(job)
                fresh.append(job.snapshot())
            }
        }
        pump()
        notify()
        return fresh
    }

    // MARK: - Cancellation (the generation epoch + the per-job face)

    /// Teardown (session switch / panel abort): drop the pending jobs
    /// (marked `.cancelled` — settled in the OLD generation's books, which
    /// the progress reset below retires), bump the epoch, and let the
    /// in-flight render finish into the void (a GPU render cannot be
    /// aborted mid-flight safely — the gates discard its result). The
    /// progress window RESETS: a fresh epoch starts at 0/0.
    public func cancelAll() {
        generation += 1
        for index in pending.indices {
            jobs[pending[index].id]?.state = .cancelled
        }
        pending.removeAll()
        cancelledInFlight.removeAll()
        progressTotal = 0
        progressDone = 0
        notify()
    }

    /// Per-job cancel. A PENDING job is removed and marked `.cancelled`
    /// immediately; an IN-FLIGHT job gets a cancel request honored at the
    /// next gate (execute entry / render→encode boundary — the artifact is
    /// discarded before anything is written). A job already past the
    /// encode boundary completes `.done` honestly: its file is fully
    /// promoted and cannot be un-written (the state never lies about disk).
    ///
    /// The cancel flag is armed BEFORE the pending removal — the pump may
    /// have just handed the job to a runner (dequeue race); execute's
    /// gate ② then discards it and the settled tally is counted exactly
    /// once (whichever path wins the race).
    public func cancel(jobID: UUID) {
        guard var job = jobs[jobID], !job.state.isTerminal else { return }
        cancelledInFlight.insert(jobID)
        if pending.contains(where: { $0.id == jobID }) {
            pending.removeAll { $0.id == jobID }
            job.state = .cancelled
            jobs[jobID] = job
            progressDone += 1
            notify()
        }
        // The in-flight case settles through finishCancelled at the gate.
    }

    /// The explicit re-queue (NO automatic retry — dt posture). Only a
    /// `.failed` job retries: it returns to `.pending` AT THE TAIL (fresh
    /// seq + the CURRENT generation). The failed job's settled tally is
    /// unwound so `done ≤ total` holds throughout.
    public func retry(jobID: UUID) throws {
        guard var job = jobs[jobID] else {
            throw AppError.invalidParameter("export retry: unknown job \(jobID)")
        }
        guard case .failed = job.state else {
            throw AppError.invalidParameter(
                "export retry: job \(jobID) is not in the failed state")
        }
        job.state = .pending
        job.generation = generation
        seqCounter += 1
        job.seq = seqCounter
        let requeued = job
        jobs[jobID] = requeued
        // Re-append AT THE TAIL with a fresh seq; the failed job's settled
        // tally unwinds HERE (markTerminal will re-add it when the retried
        // run settles), so `done ≤ total` holds throughout.
        pending.append(requeued)
        progressDone -= 1
        pump()
        notify()
    }

    // MARK: - Observation (the bridge/UI face)

    /// All known jobs of this queue instance, FIFO by seq (terminal jobs
    /// keep their rows — the panel's inline error face reads these).
    public func snapshots() -> [ExportJobSnapshot] {
        liveJobs.map { $0.snapshot() }
    }

    /// The two-layer progress snapshot (queue `done/total` for the CURRENT
    /// generation + the in-flight job's coarse phase; concurrency 1 ⇒ at
    /// most one active phase).
    public func progress() -> ExportProgress {
        var phase: ExportJobPhase?
        if let active = liveJobs.first(where: { job in
            switch job.state {
            case .rendering, .encoding: return true
            case .pending, .done, .failed, .cancelled: return false
            }
        }) {
            if case .rendering = active.state { phase = .rendering }
            if case .encoding = active.state { phase = .encoding }
        }
        return ExportProgress(
            done: progressDone, total: progressTotal, activePhase: phase)
    }

    /// The per-job state map lookup the snapshot helpers ride. (Kept as a
    /// tiny computed face so `snapshots`/`progress` share one truth.)
    private var liveJobs: [ExportJob] {
        jobs.values.sorted { $0.seq < $1.seq }
    }

    // MARK: - The pump (FIFO — no visible jump, no idle delay)

    private func pump() {
        while inFlight < Self.concurrency, !pending.isEmpty {
            let job = pending.removeFirst()
            inFlight += 1
            // TaskLocal discipline: a detached task inherits NO TaskLocals,
            // so the runner wraps every leg call in
            // `$routesToExportQueue.withValue(true)` inside `execute` —
            // the whole job tree lands on exportCommandQueue.
            Task.detached(priority: .utility) { [weak self] in
                await self?.execute(job)
            }
        }
    }

    private func execute(_ queued: ExportJob) async {
        // Gate ①: the generation epoch (a stale job leaves at the gate
        // without paying ANY leg).
        guard queued.generation == generation else {
            await finishCancelled(jobID: queued.id)
            return
        }
        // Gate ②: a cancel that landed between dequeue and entry.
        guard !cancelledInFlight.contains(queued.id) else {
            await finishCancelled(jobID: queued.id)
            return
        }

        let context = ExportJobContext(
            destinationDirectory: queued.destinationDirectory,
            occupiedNames: occupiedNamesProvider(queued.destinationDirectory),
            instancesOverride: queued.instancesOverride,
            editorSignature: queued.editorSignature)

        // ── render leg (Utility QoS detached task + export-queue routing) ─
        await markState(jobID: queued.id, state: .rendering)
        var artifact: ExportRenderArtifact?
        do {
            artifact = try await MetalContext.$routesToExportQueue.withValue(true) {
                try await renderLeg(queued.snapshot(), context)
            }
        } catch {
            await finish(jobID: queued.id, generation: queued.generation, error: error)
            return
        }

        // Gate ③: the render→encode boundary. A cancel landing during the
        // render discards the artifact — NOTHING was written (the render
        // stage only NAMES the destination).
        guard queued.generation == generation,
              !cancelledInFlight.contains(queued.id), let artifact else {
            await finishCancelled(jobID: queued.id)
            return
        }

        // ── encode leg (quantized plane → file, atomic promote) ──────────
        await markState(jobID: queued.id, state: .encoding)
        let url: URL
        do {
            url = try await MetalContext.$routesToExportQueue.withValue(true) {
                try await encodeLeg(artifact, queued.variant)
            }
        } catch {
            await finish(jobID: queued.id, generation: queued.generation, error: error)
            return
        }

        // Past the encode boundary the file is fully promoted — a cancel
        // arriving NOW cannot un-write it; the job completes .done.
        await markTerminal(jobID: queued.id, state: .done(url))
    }

    // MARK: - State transitions (every mutation rides the contract table)

    private func markState(jobID: UUID, state: ExportJobState) async {
        guard var job = jobs[jobID] else { return }
        // The contract asserts every transition (11-01's vector table); a
        // nonconforming move here is a BUG, so log loudly instead of
        // silently corrupting the state machine.
        guard job.state.canTransition(to: state) else {
            Self.logger.error(
                "export queue: illegal transition \(String(describing: job.state), privacy: .public) → \(String(describing: state), privacy: .public) for \(jobID, privacy: .public)")
            return
        }
        job.state = state
        jobs[jobID] = job
        notify()
    }

    private func markTerminal(jobID: UUID, state: ExportJobState) async {
        guard var job = jobs[jobID] else { return }
        guard job.state.canTransition(to: state) else {
            Self.logger.error(
                "export queue: illegal terminal transition for \(jobID, privacy: .public)")
            return
        }
        job.state = state
        jobs[jobID] = job
        cancelledInFlight.remove(jobID)
        // Settle the in-flight slot + the progress tally — ONLY for the
        // CURRENT generation (a stale straggler's exit must not pollute
        // the fresh epoch's window).
        let currentGeneration = job.generation == generation
        if currentGeneration {
            progressDone += 1
        }
        await settleInFlight()
        // The per-job post-action trigger (done ONLY, current generation
        // only — OQ-11-7). Fired after the settle so the UI already sees
        // the row as done when the action runs.
        if case .done(let url) = state, currentGeneration {
            let snapshot = job.snapshot()
            if let completionHook {
                Task.detached(priority: .utility) { await completionHook(snapshot, url) }
            }
        }
    }

    private func finish(jobID: UUID, generation jobGeneration: Int, error: Error) async {
        // A STALE generation's failure is a silent void — the job already
        // reads .cancelled in the books (cancelAll marked the pendings;
        // in-flight stragglers get the terminal stamp here).
        guard jobGeneration == generation else {
            await finishCancelled(jobID: jobID)
            return
        }
        let typed: AppError
        if let appError = error as? AppError {
            typed = appError
        } else {
            typed = .encodeFailed(String(describing: error))
        }
        if case .cancelled = typed {
            await finishCancelled(jobID: jobID)
            return
        }
        await markTerminal(jobID: jobID, state: .failed(typed))
        Self.logger.error(
            "export job failed: \(error.localizedDescription, privacy: .public)")
    }

    /// The cancel exit for an IN-FLIGHT slot (the gates + stale stragglers
    /// route here): stamp `.cancelled` if not yet terminal, settle the
    /// progress tally (current generation only), release the worker, pump.
    private func finishCancelled(jobID: UUID) async {
        cancelledInFlight.remove(jobID)
        if var job = jobs[jobID], !job.state.isTerminal {
            job.state = .cancelled
            jobs[jobID] = job
            if job.generation == generation {
                progressDone += 1
            }
        }
        await settleInFlight()
    }

    /// Release the worker slot + refill the pump (every in-flight exit).
    private func settleInFlight() async {
        inFlight -= 1
        pump()
        notify()
    }

    /// The change hook + the completion bookkeeping shared by every exit.
    private func notify() {
        guard let hook = progressHook else { return }
        Task.detached(priority: .utility) { await hook() }
    }

    // MARK: - Default production legs (the 11-03 renderer, split)

    /// The REAL legs: render = `ExportRenderer.renderStage` (full-frame
    /// decode → EXPORT pipe → exit conversion → quantize, the 11-03
    /// chain), encode = `ExportRenderer.encodeStage` (naming already done
    /// at the render boundary → encoder → atomic promote). Both re-wrap
    /// their bodies in `$routesToExportQueue.withValue(true)` — the
    /// renderer does it internally for the pipe calls; this wrapper keeps
    /// the guarantee structural at the queue level too.
    private static func productionLegs(
        metal: MetalContext?,
        registry: ModuleRegistry,
        yiyinInjector: ExportYiyinInjector?,
        decodeLeg: (@Sendable (URL) async throws -> DecodedImage)?
    ) -> (ExportRenderLeg, ExportEncodeLeg) {
        let renderLeg: ExportRenderLeg = { snapshot, context in
            guard let metal else {
                throw AppError.metalDeviceUnavailable
            }
            guard let variant = snapshot.variants.first else {
                throw AppError.invalidParameter(
                    "export job \(snapshot.id): no variant")
            }
            let request = ExportRenderer.Request(
                imageURL: snapshot.imageURL,
                destinationDirectory: context.destinationDirectory,
                occupiedNames: context.occupiedNames,
                variant: variant,
                instancesOverride: context.instancesOverride,
                editorSignature: context.editorSignature)
            let stage = try await ExportRenderer.renderStage(
                request: request, metal: metal, registry: registry,
                decodeLeg: decodeLeg, yiyinInjector: yiyinInjector)
            return ExportRenderArtifact(
                token: snapshot.seq,
                width: stage.outputWidth,
                height: stage.outputHeight,
                stage: ExportRenderStage(
                    plane: stage.plane,
                    formatSpec: stage.formatSpec,
                    targetColorSpace: stage.targetColorSpace,
                    dpi: stage.dpi,
                    destination: stage.destination,
                    sourceURL: stage.sourceURL,
                    editorSignature: stage.editorSignature))
        }
        let encodeLeg: ExportEncodeLeg = { artifact, _ in
            guard let stage = artifact.stage else {
                throw AppError.invalidParameter(
                    "export encode leg: synthetic artifact (no stage payload)")
            }
            return try ExportRenderer.encodeStage(
                plane: stage.plane, formatSpec: stage.formatSpec,
                targetColorSpace: stage.targetColorSpace, dpi: stage.dpi,
                sourceURL: stage.sourceURL, editorSignature: stage.editorSignature,
                destination: stage.destination)
        }
        return (renderLeg, encodeLeg)
    }

    /// The default occupancy face: every entry name in the directory (dot
    /// files included — a collision is a collision). A missing/unreadable
    /// directory enumerates EMPTY (the encoder's own atomic write then
    /// surfaces the real filesystem error).
    public nonisolated static func defaultOccupiedNames(in directory: URL) -> Set<String> {
        Set(
            (try? FileManager.default.contentsOfDirectory(atPath: directory.path))
                ?? [])
    }

    // MARK: - Test seams (never called by app code)

    /// The in-flight occupancy probe (the concurrency-1 test's window).
    public func inFlightCountForTesting() -> Int { inFlight }
}

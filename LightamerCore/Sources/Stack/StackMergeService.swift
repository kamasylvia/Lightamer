import CoreImage
import Foundation
import Metal
import os

// ─────────────────────────────────────────────────────────────────────────────
// StackMergeService (Plan 08-1 T1; D-08-CONTEXT-1/11) — the DOCUMENT-LEVEL
// N-source merge service (NOT an in-pipe iop).
//
// Shape (the ExportQueue structural twin, Plan 11-04): an actor + a DEDICATED
// low-priority `MTLCommandQueue` + a cancel generation epoch + a
// `(done, total)` progress window + NO automatic retry (the dt
// `control_jobs.c` posture — the user re-queues through the explicit
// `retry(jobID)`). Concurrency is LOCKED to 1: a 100 MP merge peaks at the
// accumulator planes (≈2.0–2.4 GB, RESEARCH §6) plus one transient
// full-frame decode render — two concurrent jobs would break the memory
// budget exactly the way two export jobs would (D-11-CONTEXT-2).
//
// `MTLCommandQueue` has no priority API (11-RESEARCH §4.4 fact), so "low
// priority" lands as an INDEPENDENT queue owned by this service (the
// producer and its readbacks share it — a self-contained domain, so the
// L031 unique-routing red line is satisfied by construction: nothing inside
// the service submits to, or shares a plane with, the editor/export queues;
// the discipline doc records the routing posture).
//
// Failure TYPING (RESEARCH §12):
//   • decode failure  → HARD failure (`AppError.decodeFailed`) — retry-able
//   • write failure   → HARD failure (`AppError.encodeFailed`) — retry-able
//   • align failure   → NOT an error: the merge DEGRADES (merge with
//     identity shifts) and the product's provenance carries the label
//     (`"skipped-low-texture"` / `"degraded"` — T2)
//
// Source immutability (CONVENTIONS non-destructive red line): the service
// only ever READS the sources; every product is a NEW file (the ExportNamer
// collision increment never overwrites). Products are 32-bit float TIFF
// documents in the session root — ordinary single documents the moment they
// land (the IOP-HDR-04 zero-new-mechanism chain).
//
// Legs injection (the 11-04 test seam): production legs are the static
// factories below; tests inject synthetic decode/merge legs to pin the
// cancel/progress/failure gates deterministically.
// ─────────────────────────────────────────────────────────────────────────────

/// The decode leg — one source file → its decoded CIImage + metadata.
/// Production = `RAWDecoder.decode` (the RAW-9-opt-in unified entry).
public typealias StackDecodeLeg = @Sendable (URL) async throws -> DecodedImage

/// The merge leg — the align→weight→write pipeline for ONE job. Reports
/// progress through the stepper (each `bump()` advances the queue's
/// `(done, total)` window by one step). Throwing a typed `AppError` fails
/// the job (`.decodeFailed`/`.fileUnreadable` = decode-side hard failures,
/// `.encodeFailed` = write-side hard failures — both retry-able).
public typealias StackMergeLeg = @Sendable (StackMergeWork) async throws -> StackMergeOutcome

/// One rendered full-frame float32 RGBA plane (the CIContext render output;
/// the buffer frees on deinit — the transient decode-render big chunk).
public final class StackRenderedPlane: @unchecked Sendable {
    public let pointer: UnsafeMutableRawPointer
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int

    init(pointer: UnsafeMutableRawPointer, width: Int, height: Int, bytesPerRow: Int) {
        self.pointer = pointer
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
    }

    deinit { pointer.deallocate() }

    /// The plane as a raw buffer view (the BandStreamer consumers).
    public var buffer: UnsafeRawBufferPointer {
        UnsafeRawBufferPointer(start: pointer, count: bytesPerRow * height)
    }
}

/// The render face the merge legs use to materialize a decoded CIImage
/// into a full-frame float32 RGBA linear-Rec2020 plane. The context rides
/// the service's DEDICATED queue (the self-contained GPU domain) and pins
/// the CIContextPool's working-space recipe (linear Rec2020, RGBAh working
/// format, cacheIntermediates false — CIRAW-4).
public struct StackRenderFace: Sendable {

    let context: CIContext

    public init(context: CIContext) {
        self.context = context
    }

    /// Render the WHOLE frame at full extent into a freshly allocated
    /// float32 RGBA plane. CIRAW re-executes per call (cacheIntermediates
    /// false) — the ×N decode passes of the research §12 budget.
    public func renderFullFloatRGBA(_ image: CIImage) throws -> StackRenderedPlane {
        let extent = image.extent
        guard extent.width >= 1, extent.height >= 1 else {
            throw AppError.decodeFailed("stack render: empty CIImage extent")
        }
        let width = Int(extent.width)
        let height = Int(extent.height)
        let bytesPerRow = width * 16
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: bytesPerRow * height, alignment: 64)
        context.render(
            image, toBitmap: pointer, rowBytes: bytesPerRow,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: CIFormat.RGBAf, colorSpace: WorkingSpace.colorSpace)
        return StackRenderedPlane(
            pointer: pointer, width: width, height: height,
            bytesPerRow: bytesPerRow)
    }
}

/// The per-job work description handed to the merge leg (and replayed
/// verbatim by `retry`).
public struct StackMergeWork: Sendable {

    /// The merge kind (v1 implements `.hdrMerge`; the stack kinds swap the
    /// terminal segment behind this same interface).
    public let kind: StackMergeService.MergeKind

    /// The source file URLs, REFERENCE frame FIRST (sources[0] is the
    /// alignment reference; the order is also the provenance sources order).
    public let sources: [URL]

    /// The decoded frames (SAME order — the CIImage payloads are lazy
    /// recipes; each render re-executes CIRAW, the ×N decode budget).
    public let decoded: [DecodedImage]

    /// The user-facing parameters (de-ghost toggle, weight gates, override).
    public let params: StackMergeService.MergeParams

    /// The session root (provenance `relPath` anchor + product landing
    /// directory). nil = land beside the first source.
    public let sessionRoot: URL?

    /// The progress stepper (`(done, total)` bumps; thread-safe — the leg
    /// runs on the detached utility task).
    public let progress: StackMergeProgress

    /// The render face (the dedicated-queue CIContext).
    public let render: StackRenderFace

    /// The GPU domain the legs may submit to (Plan 08-3: the SML focus
    /// measure rides THIS dedicated queue — never an editor/export queue).
    public let device: any MTLDevice
    public let mergeQueue: any MTLCommandQueue

    public init(
        kind: StackMergeService.MergeKind,
        sources: [URL],
        decoded: [DecodedImage],
        params: StackMergeService.MergeParams,
        sessionRoot: URL?,
        progress: StackMergeProgress,
        render: StackRenderFace,
        device: any MTLDevice,
        mergeQueue: any MTLCommandQueue
    ) {
        self.kind = kind
        self.sources = sources
        self.decoded = decoded
        self.params = params
        self.sessionRoot = sessionRoot
        self.progress = progress
        self.render = render
        self.device = device
        self.mergeQueue = mergeQueue
    }
}

/// The `(done, total)` stepper the merge leg bumps from inside its
/// alignment/merge/write segments. Actor-hops through the owning service —
/// sendable closure, safe from the detached runner.
public struct StackMergeProgress: Sendable {

    let bump: @Sendable () async -> Void

    public init(bump: @escaping @Sendable () async -> Void) {
        self.bump = bump
    }

    /// Advance the window by one step (one decoded source / one finished
    /// segment — the leg decides the granularity; the total was declared at
    /// enqueue).
    public func step() async {
        await bump()
    }
}

/// The merge product description (the queue's `.done` payload + the fields
/// the provenance sidecar records).
public struct StackMergeOutcome: Sendable {

    /// The promoted product file (a NEW float32 TIFF — never a source).
    public let productURL: URL

    /// The Σw==0 pixel fraction (the HOLE/coverage toast number).
    public let holeFraction: Float

    /// Per-source alignment label, provenance vocabulary
    /// (`"full"` / `"degraded"` / `"skipped-low-texture"` /
    /// `"skipped-user-override"`), reference frame first.
    public let alignment: [String]

    /// Per-source runtime exposure-ratio verification (the §1.2 >5% check).
    public let exposureRatioVerified: [Bool]

    /// The landed ghost mask (nil = de-ghost off or no ghost pixels).
    public let ghostMask: GhostMaskWriter.LandedMask?

    /// The merged frame's exposure ratios tᵢ (reference first; the merge
    /// weights' actual inputs — the provenance `sources[].exposureEV`).
    public let exposureEVs: [Double]

    /// Non-fatal notices the App surfaces with the completion toast
    /// (Plan 08-3: the NCC scale-drift and the N=3 σ-clip warnings).
    public let warnings: [String]

    public init(
        productURL: URL,
        holeFraction: Float,
        alignment: [String],
        exposureRatioVerified: [Bool],
        ghostMask: GhostMaskWriter.LandedMask? = nil,
        exposureEVs: [Double] = [],
        warnings: [String] = []
    ) {
        self.productURL = productURL
        self.holeFraction = holeFraction
        self.alignment = alignment
        self.exposureRatioVerified = exposureRatioVerified
        self.ghostMask = ghostMask
        self.exposureEVs = exposureEVs
        self.warnings = warnings
    }
}

public actor StackMergeService {

    private static let logger = AppError.logger

    // MARK: - Types

    /// The merge backend selector (D-08-CONTEXT-3 — one service, the stack
    /// kinds only swap the terminal segment; v1 implements hdr-merge).
    /// `hdrMertens` (Plan M5-2-01 KD-4) is PURELY additive — the five
    /// existing kinds' rows are byte-identical (the G5 zero-regression lock).
    public enum MergeKind: String, Codable, Sendable, CaseIterable {
        case hdrMerge = "hdr-merge"
        case focusStack = "focus-stack"
        case stackAverage = "stack-average"
        case stackMedian = "stack-median"
        case stackSigma = "stack-sigma"
        case hdrMertens = "hdr-merge-mertens"

        /// The provenance vocabulary mapping (identical raw values).
        public var provenanceKind: SidecarProvenance.Kind {
            switch self {
            case .hdrMerge: return .hdrMerge
            case .focusStack: return .focusStack
            case .stackAverage: return .stackAverage
            case .stackMedian: return .stackMedian
            case .stackSigma: return .stackSigma
            case .hdrMertens: return .hdrMertens
            }
        }
    }

    /// The user-facing merge parameters (the provenance `algorithm.params`
    /// snapshot — every field is Codable for the v4 sidecar).
    public struct MergeParams: Codable, Sendable, Equatable {

        /// De-ghost pass on (T4). `false` = skip residual statistics and
        /// mask generation entirely (zero extra decode passes, zero IO).
        public var deGhost: Bool

        /// Gaussian weight σ (research §1.1 — the P2 insensitivity verdict
        /// fixed 0.2; parameterized per D-08-CONTEXT-1 Reversibility).
        public var sigma: Float

        /// The clip gate — p ≥ this reads as sensor clipping (w=0).
        public var clipGate: Float

        /// The floor gate — p ≤ this reads as underexposure noise (w=0).
        public var floorGate: Float

        /// The additive noise-cap-weight knob (research §1.1 — v1 default
        /// OFF; kept per the Reversibility clause).
        public var weightNoiseFloor: Bool

        /// The aperture/ISO override (research §2.4 — default REJECT a
        /// bracket with differing aperture/ISO; override admits with a
        /// warning and routes the aperture delta into the runtime ratio
        /// self-check).
        public var allowApertureISOOverride: Bool

        /// The ExportNamer tag (`"hdr"` default → `<base>_hdr.tif`).
        public var tag: String?

        /// Focus-stack pyramid depth (Plan 08-3; nil = the default 5 / not
        /// a focus merge). Additive optional — old sidecars decode fine and
        /// re-encode byte-identical (the synthesized encodeIfPresent).
        public var pyramidLevels: Int?

        /// Sigma-clip rejection k (Plan 08-3; nil = the default 2.5 / not a
        /// sigma merge).
        public var sigmaClipK: Float?

        /// The NCC scale-drift warn threshold + the measured per-merge
        /// minimum (the params snapshot's mode-specific record — the
        /// measurement is deterministic, so the provenance identity stays
        /// stable across replays; D-08-3-T4-1).
        public var nccThreshold: Double?
        public var nccMeasuredMin: Double?

        /// The Mertens deghost tier (`off/low/medium/high`; Plan M5-2-01
        /// KD-4). nil = UNSPECIFIED — the leg resolves it to `medium`
        /// (OQ-3's default; the UI always passes an explicit tier).
        /// Additive optional — old sidecars decode fine and re-encode
        /// byte-identical (the synthesized encodeIfPresent).
        public var mertensDeghost: String?

        /// The Mertens pyramid depth override (nil = the resolution-adaptive
        /// `MertensFusion.adaptiveLevels`; a measured run writes the parsed
        /// value back — the 08-3 `pyramidLevels` snapshot precedent).
        public var mertensLevels: Int?

        public init(
            deGhost: Bool = true,
            sigma: Float = 0.2,
            clipGate: Float = 0.995,
            floorGate: Float = 0.001,
            weightNoiseFloor: Bool = false,
            allowApertureISOOverride: Bool = false,
            tag: String? = "hdr",
            pyramidLevels: Int? = nil,
            sigmaClipK: Float? = nil,
            nccThreshold: Double? = nil,
            nccMeasuredMin: Double? = nil,
            mertensDeghost: String? = nil,
            mertensLevels: Int? = nil
        ) {
            self.deGhost = deGhost
            self.sigma = sigma
            self.clipGate = clipGate
            self.floorGate = floorGate
            self.weightNoiseFloor = weightNoiseFloor
            self.allowApertureISOOverride = allowApertureISOOverride
            self.tag = tag
            self.pyramidLevels = pyramidLevels
            self.sigmaClipK = sigmaClipK
            self.nccThreshold = nccThreshold
            self.nccMeasuredMin = nccMeasuredMin
            self.mertensDeghost = mertensDeghost
            self.mertensLevels = mertensLevels
        }
    }

    /// The coarse in-flight phase (the export queue's two-layer progress —
    /// the queue window counts STEPS, the phase names the segment).
    public enum JobPhase: Sendable, Equatable {
        case queued
        case aligning
        case merging
        case writing
    }

    /// The job state machine (`ExportJobState` twin, minus the export
    /// render/encode split — merge exposes its segments as the phase enum).
    /// (NOT Equatable — the `.failed` payload is a typed `AppError`, which
    /// has no equality; assertions pattern-match instead.)
    public enum JobState: Sendable {
        case pending
        case running(JobPhase)
        case done(URL)
        case failed(AppError)
        case cancelled

        public var isTerminal: Bool {
            switch self {
            case .done, .failed, .cancelled: return true
            case .pending, .running: return false
            }
        }
    }

    /// The cross-boundary job record (the panel/observer face).
    public struct JobSnapshot: Sendable {
        public let id: UUID
        public let kind: MergeKind
        public let sources: [URL]
        public let seq: Int
        public let generation: Int
        public let state: JobState
    }

    /// The actor-private job record (never crosses the boundary).
    private struct MergeJob {
        let id: UUID
        let kind: MergeKind
        let sources: [URL]
        let params: MergeParams
        let sessionRoot: URL?
        let totalSteps: Int
        var seq: Int
        var generation: Int
        var state: JobState

        func snapshot() -> JobSnapshot {
            JobSnapshot(
                id: id, kind: kind, sources: sources, seq: seq,
                generation: generation, state: state)
        }
    }

    // MARK: - Dependencies

    /// The dedicated command queue — this service's SELF-CONTAINED GPU
    /// domain (producer/consumer on the SAME queue; within-queue readbacks
    /// obey the L014 fence). Never crossed with the editor/export queues.
    public nonisolated let mergeQueue: any MTLCommandQueue

    private let decodeLeg: StackDecodeLeg
    private let mergeLeg: StackMergeLeg

    /// The render face — a CIContext on THIS service's dedicated queue with
    /// the CIContextPool working-space recipe (the self-contained domain;
    /// nothing here submits to the editor/export queues).
    private let renderFace: StackRenderFace

    // MARK: - Queue state (the 9-3/11-04 shape)

    /// Worker width: EXACTLY ONE (the memory red line — see header).
    public static let concurrency = 1

    private var pending: [UUID] = []
    private var jobs: [UUID: MergeJob] = [:]
    /// Monotonic FIFO order (retried jobs re-queue at the tail with a fresh
    /// seq — the export queue posture).
    private var seqCounter = 0
    /// The cancel epoch — `cancelAll` bumps it; stale-generation results
    /// are discarded at the execute gates.
    private var generation = 0
    private var inFlight = false
    /// Jobs the user cancelled while in flight (honored at the next gate).
    private var cancelledInFlight: Set<UUID> = []
    /// The current-generation progress window.
    private var progressDone = 0
    private var progressTotal = 0
    /// Fired after every state/progress mutation (the export-queue hook
    /// shape; fire-and-forget detached).
    private var progressHook: (@Sendable () async -> Void)?

    public func setProgressHook(_ hook: (@Sendable () async -> Void)?) {
        progressHook = hook
    }

    /// The per-job COMPLETION hook (the export queue's post-action trigger
    /// shape): fired ONCE per `.done` job of the CURRENT generation — the
    /// App wiring toasts the holeFraction and reloads the grid. A failed
    /// job never triggers it. Fire-and-forget.
    private var completionHook:
        (@Sendable (JobSnapshot, StackMergeOutcome) async -> Void)?

    public func setCompletionHook(
        _ hook: (@Sendable (JobSnapshot, StackMergeOutcome) async -> Void)?
    ) {
        completionHook = hook
    }

    /// The per-job FAILURE hook (the completion hook's typed twin): fired
    /// ONCE per `.failed` job of the CURRENT generation — the App wiring
    /// toasts the typed error. Cancelled jobs never fire it.
    private var failureHook: (@Sendable (JobSnapshot, AppError) async -> Void)?

    public func setFailureHook(
        _ hook: (@Sendable (JobSnapshot, AppError) async -> Void)?
    ) {
        failureHook = hook
    }

    // MARK: - Lifecycle

    /// - Parameters:
    ///   - device: the GPU (tests inject the shared `MTLCreateSystemDefaultDevice`
    ///     result; the service mints its OWN queue on it — never the editor's).
    ///   - decodeLeg/mergeLeg: nil = the production legs.
    /// - Throws: `AppError.metalDeviceUnavailable` when the dedicated queue
    ///   cannot be minted (the same class as MetalContext's queue failures).
    public init(
        device: any MTLDevice,
        decodeLeg: StackDecodeLeg? = nil,
        mergeLeg: StackMergeLeg? = nil
    ) throws {
        guard let queue = device.makeCommandQueue() else {
            AppError.logger.error("StackMergeService queue allocation failed")
            throw AppError.metalDeviceUnavailable
        }
        self.mergeQueue = queue
        self.renderFace = StackRenderFace(context: CIContext(
            mtlDevice: device, options: [
                .workingColorSpace: WorkingSpace.colorSpace,
                .outputColorSpace: WorkingSpace.colorSpace,
                .workingFormat: CIFormat.RGBAh,
                .cacheIntermediates: false,
            ]))
        self.decodeLeg = decodeLeg ?? Self.productionDecodeLeg
        self.mergeLeg = mergeLeg ?? Self.productionMergeLeg
    }

    // MARK: - Enqueue

    /// Queue one merge job. Sources must be ≥ 2 (a merge needs a bracket)
    /// and the FIRST entry is the alignment/exposure reference. The step
    /// total = N decode steps per pass (align + base merge + optional ghost
    /// pass) + 2 (write + sidecar) — declared up front so `done ≤ total`
    /// holds throughout.
    @discardableResult
    public func enqueue(
        kind: MergeKind,
        sources: [URL],
        params: MergeParams,
        sessionRoot: URL? = nil
    ) throws -> JobSnapshot {
        guard sources.count >= 2 else {
            throw AppError.invalidParameter(
                "stack merge needs ≥ 2 sources, got \(sources.count)")
        }
        seqCounter += 1
        progressTotal += Self.stepTotal(for: sources.count, params: params, kind: kind)
        let job = MergeJob(
            id: UUID(),
            kind: kind,
            sources: sources,
            params: params,
            sessionRoot: sessionRoot,
            totalSteps: Self.stepTotal(for: sources.count, params: params, kind: kind),
            seq: seqCounter,
            generation: generation,
            state: .pending)
        jobs[job.id] = job
        pending.append(job.id)
        pump()
        notify()
        return job.snapshot()
    }

    /// The occupancy face for the product namer — the export queue's
    /// directory enumeration, reused verbatim (single source of the
    /// collision-increment contract).
    nonisolated public static func defaultOccupiedNames(in directory: URL) -> Set<String> {
        ExportQueue.defaultOccupiedNames(in: directory)
    }

    /// The declared progress window: (align N, the service's steps) +
    /// (base-merge N + write 1 + sidecar 1, the merge leg's bump duty) +
    /// (deGhost ? N : 0) + 1 (the terminal settle step). The 08-3 kinds
    /// declare align + stage + fuse/aggregate per source (+ the same tail).
    nonisolated static func stepTotal(for sources: Int, params: MergeParams) -> Int {
        let passes = 2 + (params.deGhost ? 1 : 0)
        return sources * passes + 3
    }

    /// The kind-aware total (Plan 08-3): HDR keeps its formula verbatim;
    /// focus/stack kinds run THREE per-source passes (align, stage,
    /// fuse/aggregate) + the same 3-step tail. Mertens (Plan M5-2-01 KD-8)
    /// declares honestly from day one: decode N + align N + stage/encode N
    /// + fuse N + write 1 + sidecar 1 + settle 1 = 4N+3 (the 08-3 kinds'
    /// declared 3N+3 omits the decode N — the recorded observation, NOT
    /// fixed here: changing their declared total is an existing-kind
    /// behavior change, the G5 red line).
    nonisolated static func stepTotal(
        for sources: Int, params: MergeParams, kind: MergeKind
    ) -> Int {
        switch kind {
        case .hdrMerge:
            return Self.stepTotal(for: sources, params: params)
        case .focusStack, .stackAverage, .stackMedian, .stackSigma:
            return sources * 3 + 3
        case .hdrMertens:
            return sources * 4 + 3
        }
    }

    /// The ExportNamer tag vocabulary per kind (research §3.3; the compound
    /// stack tags are D-08-3-T4-2). `params.tag` (when non-nil) wins.
    nonisolated public static func defaultTag(for kind: MergeKind) -> String {
        switch kind {
        case .hdrMerge: return "hdr"
        case .focusStack: return "fstack"
        case .stackAverage: return "stack_avg"
        case .stackMedian: return "stack_med"
        case .stackSigma: return "stack_sig"
        case .hdrMertens: return "mertens"
        }
    }

    // MARK: - Cancellation (the generation-epoch face)

    /// Teardown: drop the pendings (`.cancelled`), bump the epoch, let the
    /// in-flight leg finish into the void (a running decode cannot be
    /// aborted mid-flight — the gates discard its result). The progress
    /// window RESETS for the fresh epoch.
    public func cancelAll() {
        generation += 1
        for id in pending {
            jobs[id]?.state = .cancelled
        }
        pending.removeAll()
        cancelledInFlight.removeAll()
        progressTotal = 0
        progressDone = 0
        notify()
    }

    /// Per-job cancel: pending → `.cancelled` immediately; in-flight →
    /// honored at the next gate; already-past-the-write-boundary jobs
    /// complete `.done` honestly (the file landed — the state never lies
    /// about disk).
    public func cancel(jobID: UUID) {
        guard var job = jobs[jobID], !job.state.isTerminal else { return }
        cancelledInFlight.insert(jobID)
        if let index = pending.firstIndex(of: jobID) {
            pending.remove(at: index)
            job.state = .cancelled
            jobs[jobID] = job
            progressDone += 1
            notify()
        }
        // In-flight settles through finishCancelled at the gate.
    }

    /// The explicit re-queue (NO automatic retry). Only a `.failed` job
    /// retries: back to `.pending` at the TAIL, fresh seq, CURRENT
    /// generation; the failed tally unwinds so `done ≤ total` holds.
    public func retry(jobID: UUID) throws {
        guard var job = jobs[jobID] else {
            throw AppError.invalidParameter("stack merge retry: unknown job \(jobID)")
        }
        guard case .failed = job.state else {
            throw AppError.invalidParameter(
                "stack merge retry: job \(jobID) is not in the failed state")
        }
        // Reset the window for a fresh run of this job's steps.
        progressTotal += job.totalSteps
        job.state = .pending
        job.generation = generation
        seqCounter += 1
        job.seq = seqCounter
        jobs[jobID] = job
        pending.append(jobID)
        pump()
        notify()
    }

    // MARK: - Observation

    public func snapshots() -> [JobSnapshot] {
        jobs.values.sorted { $0.seq < $1.seq }.map { $0.snapshot() }
    }

    /// `(done, total)` for the CURRENT generation (no per-job phase — the
    /// single worker means the phase rides the one running job's state).
    public func progress() -> (done: Int, total: Int) {
        (progressDone, progressTotal)
    }

    /// The running job's phase, if any (concurrency 1 ⇒ at most one).
    public func activePhase() -> JobPhase? {
        guard let active = jobs.values.first(where: {
            if case .running = $0.state { return true }
            return false
        }) else { return nil }
        if case .running(let phase) = active.state { return phase }
        return nil
    }

    // MARK: - The pump + gates (ExportQueue twin)

    private func pump() {
        while inFlight == false, !pending.isEmpty {
            let jobID = pending.removeFirst()
            inFlight = true
            Task.detached(priority: .utility) { [weak self] in
                await self?.execute(jobID)
            }
        }
    }

    private func execute(_ jobID: UUID) async {
        guard var job = jobs[jobID] else {
            await settleInFlight()
            return
        }
        // Gate ①: the generation epoch.
        guard job.generation == generation else {
            await finishCancelled(jobID: jobID)
            return
        }
        // Gate ②: a cancel landing between dequeue and entry.
        guard !cancelledInFlight.contains(jobID) else {
            await finishCancelled(jobID: jobID)
            return
        }

        // The progress stepper the legs bump (actor-hop through self).
        let stepper = StackMergeProgress { [weak self] in
            await self?.bumpProgress()
        }

        // ── align segment ─────────────────────────────────────────────
        job.state = .running(.aligning)
        jobs[jobID] = job
        notify()

        // Decode the reference FIRST (its failure is the cheapest early
        // exit), then the comparisons — each completed decode re-checks the
        // cancel gates BEFORE its progress step lands (a stale-generation
        // step must never pollute the fresh window).
        var decoded: [DecodedImage] = []
        decoded.reserveCapacity(job.sources.count)
        for url in job.sources {
            do {
                let image = try await decodeLeg(url)
                decoded.append(image)
            } catch {
                await finish(jobID: jobID, generation: job.generation, error: error)
                return
            }
            // Gate ③: between-segment cancel checks.
            guard job.generation == generation,
                  !cancelledInFlight.contains(jobID) else {
                await finishCancelled(jobID: jobID)
                return
            }
            await stepper.step()
        }

        // ── merge + write segment (the leg owns both; its typed failures
        // map through the SAME finish face — `.encodeFailed` from the
        // write boundary stays a retry-able hard failure). ──────────────
        job.state = .running(.merging)
        jobs[jobID] = job
        notify()

        let work = StackMergeWork(
            kind: job.kind, sources: job.sources, decoded: decoded,
            params: job.params, sessionRoot: job.sessionRoot,
            progress: stepper, render: renderFace,
            device: mergeQueue.device, mergeQueue: mergeQueue)
        let outcome: StackMergeOutcome
        do {
            outcome = try await mergeLeg(work)
        } catch {
            await finish(jobID: jobID, generation: job.generation, error: error)
            return
        }
        // Gate ③ (post-write): a cancel that landed during the merge+write
        // still cannot un-write the product — the job completes `.done`
        // honestly (the export-queue encode-boundary posture).
        await markTerminal(jobID: jobID, state: .done(outcome.productURL))
        // The per-job post-action trigger (done ONLY, current generation
        // only — fired after the settle so the UI already sees the row).
        if let job = jobs[jobID], case .done = job.state,
           job.generation == generation {
            let snapshot = job.snapshot()
            if let completionHook {
                Task.detached(priority: .utility) {
                    await completionHook(snapshot, outcome)
                }
            }
        }
    }

    // MARK: - State transitions

    private func bumpProgress() {
        progressDone += 1
        notify()
    }

    private func markTerminal(jobID: UUID, state: JobState) async {
        guard var job = jobs[jobID], !job.state.isTerminal else { return }
        job.state = state
        jobs[jobID] = job
        cancelledInFlight.remove(jobID)
        if job.generation == generation {
            progressDone += 1
        }
        await settleInFlight()
    }

    private func finish(jobID: UUID, generation jobGeneration: Int, error: Error) async {
        guard jobGeneration == generation else {
            await finishCancelled(jobID: jobID)
            return
        }
        let typed = AppError(error)
        if case .cancelled = typed {
            await finishCancelled(jobID: jobID)
            return
        }
        await markTerminal(jobID: jobID, state: .failed(typed))
        Self.logger.error(
            "stack merge job failed: \(error.localizedDescription, privacy: .public)")
        if let snapshot = jobs[jobID]?.snapshot(), snapshot.generation == generation {
            if let failureHook {
                Task.detached(priority: .utility) { await failureHook(snapshot, typed) }
            }
        }
    }

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

    private func settleInFlight() async {
        inFlight = false
        pump()
        notify()
    }

    private func notify() {
        guard let hook = progressHook else { return }
        Task.detached(priority: .utility) { await hook() }
    }

    // MARK: - Production legs

    /// Production decode = the unified RAWDecoder entry (RAW-9 opt-in,
    /// raster fallback — the HDR bracket legs ride the SAME decode surface
    /// as the editor).
    nonisolated private static let productionDecodeLeg: StackDecodeLeg = { url in
        try await RAWDecoder().decode(url)
    }

    nonisolated private static let productionMergeLeg: StackMergeLeg = { work in
        try await runProductionMerge(work)
    }

    /// The PRODUCTION pipeline (T2-T5 assembled): EXIF precheck → MTB
    /// alignment + the runtime exposure-ratio self-check → the band-
    /// streamed Robertson merge (phase 1 + the de-ghost phase 2) → the
    /// ExportNamer-collision-free product landing (float TIFF) → the ghost
    /// mask PNG → the outcome payload. Sources are only ever READ.
    nonisolated private static func runProductionMerge(
        _ work: StackMergeWork
    ) async throws -> StackMergeOutcome {
        // The D-08-CONTEXT-3 dispatch: ONE service, the kinds swap the
        // terminal segment (the alignment/precheck/landing posture is
        // shared; the v1 HDR leg below is 08-1's accepted body verbatim).
        switch work.kind {
        case .hdrMerge:
            return try await runHDRLeg(work)
        case .focusStack:
            return try await runFocusStackLeg(work)
        case .stackAverage, .stackMedian, .stackSigma:
            return try await runStackAggregateLeg(work)
        case .hdrMertens:
            return try await runMertensLeg(work)
        }
    }

    /// The Mertens production leg — a TYPED STUB in Plan M5-2-01 (KD-4, the
    /// M4-1-01 "route-don't-switch" posture): the dispatch arm is final
    /// structure (M5-2-02 only swaps the body for the band-outer streaming
    /// leg, zero second-pass dispatch edits); the typed failure pins the
    /// not-yet-landed state so an accidental enqueue fails honestly instead
    /// of silently no-op'ing.
    nonisolated private static func runMertensLeg(
        _ work: StackMergeWork
    ) async throws -> StackMergeOutcome {
        throw AppError.invalidParameter(
            "hdr-merge-mertens production leg lands in M5-2-02")
    }

    /// The 08-1 HDR production pipeline (T2-T6, accepted verbatim — only
    /// moved behind the kind dispatch, zero semantic change): EXIF precheck
    /// → MTB alignment + the runtime exposure-ratio self-check → the
    /// band-streamed Robertson merge (phase 1 + the de-ghost phase 2) →
    /// the ExportNamer-collision-free product landing (float TIFF) → the
    /// ghost mask PNG → the outcome payload. Sources are only ever READ.
    nonisolated private static func runHDRLeg(
        _ work: StackMergeWork
    ) async throws -> StackMergeOutcome {
        guard work.decoded.count == work.sources.count, work.decoded.count >= 2
        else {
            throw AppError.invalidParameter(
                "stack merge: \(work.decoded.count) decoded frames for "
                    + "\(work.sources.count) sources")
        }

        // ── extent uniformity (a bracket is same-sensor by precheck; a
        // mismatch here is a hard input error) ──────────────────────────
        let refExtent = work.decoded[0].ciImage.extent
        for image in work.decoded.dropFirst()
        where image.ciImage.extent != refExtent {
            throw AppError.invalidParameter(
                "bracket frames differ in extent: \(refExtent.size) vs "
                    + "\(image.ciImage.extent.size)")
        }
        let width = Int(refExtent.width)
        let height = Int(refExtent.height)

        // ── EXIF precheck (research §2.4) — from the DECODED captures ──
        let verdicts = ExifPrecheck.precheck(
            captures: work.decoded.map(\.capture),
            allowOverrides: work.params.allowApertureISOOverride)
        var exposureEVs: [Double] = []
        for (index, verdict) in verdicts.enumerated() {
            switch verdict {
            case .ok(let ev):
                exposureEVs.append(ev)
            case .admittedWithWarning(let ev, let reasons):
                exposureEVs.append(ev)
                AppError.logger.warning(
                    "stack merge source \(index, privacy: .public): \(reasons.joined(separator: "; "), privacy: .public)")
            case .rejected(let reasons):
                throw AppError.invalidParameter(
                    "bracket source \(index) rejected: "
                        + reasons.joined(separator: "; "))
            }
        }
        // The merge weights' exposure ratios (reference = 1).
        let exposures: [Float] = exposureEVs.map { Float(pow(2.0, $0)) }

        // ── the alignment pass (research §2) ────────────────────────────
        var shifts: [(dx: Int, dy: Int)] = [(0, 0)]
        var alignmentLabels: [String] = ["full"]
        var ratioVerified: [Bool] = [true]
        do {
            let refPlane = try work.render.renderFullFloatRGBA(
                work.decoded[0].ciImage)
            let refFrame = AlignmentFrame(
                rgbaFloat: refPlane.buffer, width: width, height: height,
                bytesPerRow: refPlane.bytesPerRow)
            let refPyramid = MTBAlign.pyramid(refFrame.luma)
            // The reference plane's ratio surface stays (the joint-band
            // anchor); the FULL luma plane dies with refPlane here — only
            // the pyramids (≈17 MB/source) + the small ratio surfaces live.
            let refRatio = refFrame.ratioLuma
            await work.progress.step() // align step: reference

            for index in work.decoded.indices.dropFirst() {
                let plane = try work.render.renderFullFloatRGBA(
                    work.decoded[index].ciImage)
                let frame = AlignmentFrame(
                    rgbaFloat: plane.buffer, width: width, height: height,
                    bytesPerRow: plane.bytesPerRow)
                let shift = MTBAlign.findShift(
                    reference: refPyramid, compare: MTBAlign.pyramid(frame.luma))
                shifts.append((dx: shift.dx, dy: shift.dy))
                alignmentLabels.append(shift.label)
                // The §1.2 runtime self-check: the measured joint-band
                // median ratio vs the EXIF expectation 2^ΔEV.
                let check = ExifPrecheck.exposureRatioCheck(
                    reference: refRatio, candidate: frame.ratioLuma,
                    expectedEV: exposureEVs[index])
                ratioVerified.append(check.verified)
                if !check.verified {
                    AppError.logger.warning(
                        "stack merge source \(index, privacy: .public): exposure ratio \(check.measuredRatio, privacy: .public) deviates from the EXIF expectation — merging unverified")
                }
                await work.progress.step() // align step: comparison
                // plane (the 1.63 GB transient) dies here; frame's luma too.
            }
        }

        // ── the merge pass (research §6 — band-streamed) ────────────────
        let pixelCount = width * height
        var sumW = [Float](repeating: 0, count: pixelCount * 3)
        var sumWP = [Float](repeating: 0, count: pixelCount * 3)
        var ghostUnion: [UInt8]? = work.params.deGhost
            ? [UInt8](repeating: 0, count: pixelCount) : nil
        let bands = BandStreamer.bands(height: height, width: width)

        func mergePass(lHatBand: [Float]?, sumW: inout [Float], sumWP: inout [Float])
            async throws
        {
            for index in work.decoded.indices {
                let plane = try work.render.renderFullFloatRGBA(
                    work.decoded[index].ciImage)
                for band in bands {
                    let pixels = BandStreamer.shiftedBandPixels(
                        fromPlane: plane.buffer,
                        bytesPerRow: plane.bytesPerRow,
                        width: width, height: height, band: band,
                        dx: shifts[index].dx, dy: shifts[index].dy)
                    HDRMergeMath.accumulateSourceBand(
                        HDRMergeMath.SourceBand(
                            pixels: pixels, width: width,
                            height: band.height, exposure: exposures[index]),
                        params: work.params, lHatBand: lHatBand,
                        ghostUnion: &ghostUnion, sumW: &sumW, sumWP: &sumWP,
                        planeRowOffset: band.y * width)
                }
                await work.progress.step() // one merge-pass step per source
                // The 1.63 GB transient plane dies at the loop iteration.
            }
        }

        // Phase 1 (the base merge) → L̂0.
        try await mergePass(lHatBand: nil, sumW: &sumW, sumWP: &sumWP)
        let lHatZero = HDRMergeMath.finalizeBand(sumW: sumW, sumWP: sumWP)

        // Phase 2 (the de-ghost re-aggregation) — a SECOND accumulator; the
        // phase-1 pair is consumed into L̂0 above (the 41 B/px peak shape).
        var finalSumW = sumW
        var finalSumWP = sumWP
        if work.params.deGhost {
            finalSumW = [Float](repeating: 0, count: pixelCount * 3)
            finalSumWP = [Float](repeating: 0, count: pixelCount * 3)
            try await mergePass(
                lHatBand: lHatZero, sumW: &finalSumW, sumWP: &finalSumWP)
        }

        // ── finalize: L̂ + the HOLE fraction ─────────────────────────────
        let lHat = HDRMergeMath.finalizeBand(sumW: finalSumW, sumWP: finalSumWP)
        let holes = HDRMergeMath.countHoles(sumW: finalSumW)
        let holeFraction = pixelCount > 0 ? Float(holes) / Float(pixelCount) : 0
        var rgba = [Float](repeating: 0, count: pixelCount * 4)
        for index in 0..<pixelCount {
            rgba[index * 4] = lHat[index * 3]
            rgba[index * 4 + 1] = lHat[index * 3 + 1]
            rgba[index * 4 + 2] = lHat[index * 3 + 2]
            rgba[index * 4 + 3] = 1
        }

        // ── the product landing (research §3.2/§3.3 — the session root +
        // ExportNamer collision increment; sources are never touched) ────
        let directory = work.sessionRoot
            ?? work.sources[0].deletingLastPathComponent()
        let occupied = StackMergeService.defaultOccupiedNames(in: directory)
        let productURL = ExportNamer.destinationURL(
            directory: directory,
            stem: work.sources[0].deletingPathExtension().lastPathComponent,
            tag: work.params.tag ?? "hdr",
            ext: "tif",
            occupiedNames: occupied)
        try BandStreamer.writeFloatTIFF(
            rgba, width: width, height: height, to: productURL)
        await work.progress.step() // write step

        // ── the ghost mask (research §4 — dilate + the RasterMaskRef
        // landing; NOTHING lands when de-ghost is off or no pixel deviated)
        var landedMask: GhostMaskWriter.LandedMask?
        if let union = ghostUnion, union.contains(1) {
            let dilated = GhostMaskWriter.dilate(
                union, width: width, height: height)
            landedMask = try GhostMaskWriter.land(
                dilated, width: width, height: height,
                productURL: productURL, maskID: UUID())
        }
        // ── the product's birth sidecar (T6 — the v4 provenance + the
        // Ghost Suppression layer stack; the ordinary-document chain takes
        // over from here) ────────────────────────────────────────────────
        let sessionRoot = work.sessionRoot
            ?? work.sources[0].deletingLastPathComponent()
        let provenanceSources: [SidecarProvenance.Source] = try work.sources
            .enumerated()
            .map { (index: Int, url: URL) -> SidecarProvenance.Source in
                let absolute = url.path
                let rootPrefix = sessionRoot.path + "/"
                let relPath = absolute.hasPrefix(rootPrefix)
                    ? String(absolute.dropFirst(rootPrefix.count))
                    : url.lastPathComponent
                guard let hash = ProvenanceReplay.fileHash(url) else {
                    throw AppError.fileUnreadable(url.path)
                }
                return SidecarProvenance.Source(
                    relPath: relPath, stableHash: hash,
                    exposureEV: exposureEVs[index])
            }
        let provenance = SidecarProvenance(
            kind: .hdrMerge,
            algorithm: SidecarProvenance.Algorithm(
                name: ProvenanceReplay.hdrAlgorithmName,
                implementationVersion: ProvenanceReplay.hdrImplementationVersion,
                params: work.params),
            sources: provenanceSources,
            alignment: alignmentLabels,
            exposureRatioVerified: ratioVerified,
            holeFraction: holeFraction,
            createdAt: Date(),
            appVersion: LightamerSidecar.currentAppVersion)
        let decodeHash = HistoryHash.decodeParamsHash(for: work.decoded[0])
        let emptyStack = HistoryStack(items: [], position: 0)
        let sidecar = LightamerSidecar(
            imageID: UUID(),
            decoderVersionUsed: work.decoded[0].decoderVersionUsed.rawValue,
            decodeParamsHash: decodeHash,
            instances: [],
            history: emptyStack,
            historyHash: HistoryHash.hash(stack: emptyStack, decodeParamsHash: decodeHash),
            layerStack: GhostMaskWriter.ghostSuppressionLayerStack(landedMask),
            provenance: provenance)
        let sidecarEncoder = JSONEncoder()
        sidecarEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let sidecarData = try sidecarEncoder.encode(sidecar)
        try sidecarData.write(
            to: LightamerSidecar.sidecarURL(for: productURL), options: .atomic)
        await work.progress.step() // sidecar step

        return StackMergeOutcome(
            productURL: productURL,
            holeFraction: holeFraction,
            alignment: alignmentLabels,
            exposureRatioVerified: ratioVerified,
             ghostMask: landedMask,
            exposureEVs: exposureEVs)
    }

    // ───────────────────────────────────────────────────────────────────
    // Plan 08-3 legs (T4 dispatch): the focus-stack and the three-mode
    // stacking-denoise pipelines. The alignment/precheck/landing posture
    // is 08-1's (REUSED — zero re-implementation); only the TERMINAL
    // SEGMENT differs (D-08-CONTEXT-3).
    //
    // The memory shape (research §6, the R3 hard constraint): each source
    // is decoded ONCE into a transient full-frame plane and STAGED to a
    // temporary file (the system temp dir — never the session; sources
    // stay read-only), then the terminal segment streams BAND BY BAND
    // from the staged files. The resident set = the N-independent output
    // plane + ONE band's N-value strip — never N full frames and never an
    // N×full quality map (research §5.4's band-streamed verdict). The
    // staging IO is the honest price of the band-outer access pattern
    // (D-08-3-T4-3, perf.md records it).
    // ───────────────────────────────────────────────────────────────────

    /// The focus-stack algorithm family name (the provenance identity).
    nonisolated static let focusAlgorithmName = "sml-pyramid-fusion"
    /// The stacking-denoise algorithm family name (mode rides the kind).
    nonisolated static let stackAlgorithmName = "band-aggregate"

    /// The shared STACK-variant front half: the precheck (shutter/ISO are
    /// NOT required to differ — the rail/stack shutter is constant; the
    /// aperture stays STRICT) + the MTB alignment pass (08-1 T2 reused
    /// verbatim) + the optional NCC scale-drift self-check (research §5.3
    /// — focus only; a WARNING, never a merge block).
    nonisolated private static func runStackPrecheckAndAlignment(
        _ work: StackMergeWork, width: Int, height: Int, withNCC: Bool
    ) async throws -> (shifts: [(dx: Int, dy: Int)], labels: [String],
                       warnings: [String], nccMin: Double) {
        let verdicts = ExifPrecheck.precheckStack(
            captures: work.decoded.map(\.capture),
            allowOverrides: work.params.allowApertureISOOverride)
        for (index, verdict) in verdicts.enumerated() {
            switch verdict {
            case .ok:
                break
            case .admittedWithWarning(_, let reasons):
                AppError.logger.warning(
                    "stack source \(index, privacy: .public): \(reasons.joined(separator: "; "), privacy: .public)")
            case .rejected(let reasons):
                throw AppError.invalidParameter(
                    "stack source \(index) rejected: "
                        + reasons.joined(separator: "; "))
            }
        }

        var shifts: [(dx: Int, dy: Int)] = [(0, 0)]
        var labels: [String] = ["full"]
        var warnings: [String] = []
        var nccMin = 1.0
        let refPlane = try work.render.renderFullFloatRGBA(work.decoded[0].ciImage)
        let refFrame = AlignmentFrame(
            rgbaFloat: refPlane.buffer, width: width, height: height,
            bytesPerRow: refPlane.bytesPerRow)
        let refPyramid = MTBAlign.pyramid(refFrame.luma)
        await work.progress.step() // align step: reference
        for index in work.decoded.indices.dropFirst() {
            let plane = try work.render.renderFullFloatRGBA(work.decoded[index].ciImage)
            let frame = AlignmentFrame(
                rgbaFloat: plane.buffer, width: width, height: height,
                bytesPerRow: plane.bytesPerRow)
            let shift = MTBAlign.findShift(
                reference: refPyramid, compare: MTBAlign.pyramid(frame.luma))
            shifts.append((dx: shift.dx, dy: shift.dy))
            labels.append(shift.label)
            if withNCC {
                let ncc = FocusStackMerge.normalizedCrossCorrelation(
                    reference: refFrame.ratioLuma, candidate: frame.ratioLuma,
                    dx: shift.dx, dy: shift.dy)
                nccMin = min(nccMin, ncc)
                if ncc < work.params.nccThreshold
                    ?? FocusStackMerge.nccWarnThreshold {
                    warnings.append(
                        "source \(index): NCC \(String(format: "%.3f", ncc)) "
                            + "below \(FocusStackMerge.nccWarnThreshold) — "
                            + "large magnification difference; edges may ghost")
                }
            }
            await work.progress.step() // align step: comparison
        }
        return (shifts, labels, warnings, nccMin)
    }

    /// The FOCUS-STACK production leg (research §5): stack precheck → MTB
    /// alignment + the NCC drift self-check → staged SML quality maps →
    /// the band-streamed quality-weighted pyramid fusion → landing.
    nonisolated private static func runFocusStackLeg(
        _ work: StackMergeWork
    ) async throws -> StackMergeOutcome {
        guard work.decoded.count == work.sources.count, work.decoded.count >= 2
        else {
            throw AppError.invalidParameter(
                "focus stack: \(work.decoded.count) decoded frames for "
                    + "\(work.sources.count) sources")
        }
        let refExtent = work.decoded[0].ciImage.extent
        for image in work.decoded.dropFirst()
        where image.ciImage.extent != refExtent {
            throw AppError.invalidParameter(
                "focus-stack frames differ in extent: \(refExtent.size) vs "
                    + "\(image.ciImage.extent.size)")
        }
        let width = Int(refExtent.width)
        let height = Int(refExtent.height)
        let levels = work.params.pyramidLevels
            ?? FocusStackMerge.defaultPyramidLevels

        let (shifts, labels, warnings, nccMin) = try await runStackPrecheckAndAlignment(
            work, width: width, height: height, withNCC: true)

        // ── the stage pass: pixels + GPU SML quality maps, ONE source
        // resident at a time ─────────────────────────────────────────────
        let staging = StagedSet(count: work.decoded.count, width: width, height: height)
        defer { staging.cleanUp() }
        for index in work.decoded.indices {
            let plane = try work.render.renderFullFloatRGBA(work.decoded[index].ciImage)
            try staging.writePixels(plane, index: index)
            let map = try FocusMeasure.qualityMap(
                plane: plane.buffer, width: width, height: height,
                bytesPerRow: plane.bytesPerRow, device: work.device,
                queue: work.mergeQueue)
            try staging.writeQuality(map, index: index)
            await work.progress.step() // stage step
            // The transient plane + map die with the loop iteration.
        }

        // ── the fuse pass: band-outer, map 只留行带 ─────────────────────
        let halo = FocusStackMerge.defaultHaloRows
        var outputPlane = [Float](repeating: 0, count: width * height * 4)
        var bumpBudget = work.decoded.count // the fuse segment declares N steps
        for band in BandStreamer.bands(height: height, width: width) {
                let stripFirst = max(0, band.y - halo)
                let stripRows = min(height, band.y + band.height + halo) - stripFirst
                var strips: [([Float], [Float])] = []
                strips.reserveCapacity(work.decoded.count)
                for index in work.decoded.indices {
                    strips.append((
                        try staging.readShiftedPixels(
                            index: index, firstRow: stripFirst, rows: stripRows,
                            dx: shifts[index].dx, dy: shifts[index].dy),
                        try staging.readShiftedQuality(
                            index: index, firstRow: stripFirst, rows: stripRows,
                            dx: shifts[index].dx, dy: shifts[index].dy)))
                }
                let fused = FocusStackMerge.fuseStrip(
                    width: width, height: stripRows, sources: work.decoded.count,
                    levels: levels) { sourceIndex in strips[sourceIndex] }
                // Copy the band's rows (strip-local offset) into the output.
                let offsetInStrip = band.y - stripFirst
                for row in 0..<band.height {
                    let sourceRow = offsetInStrip + row
                    let destinationRow = band.y + row
                    for x in 0..<width {
                        let s = (sourceRow * width + x) * 3
                        let d = (destinationRow * width + x) * 4
                        outputPlane[d] = fused[s]
                        outputPlane[d + 1] = fused[s + 1]
                        outputPlane[d + 2] = fused[s + 2]
                        outputPlane[d + 3] = 1
                    }
                }
                if bumpBudget > 0 {
                    bumpBudget -= 1
                    await work.progress.step() // fuse step (band-paced)
                }
        }
        while bumpBudget > 0 {
            bumpBudget -= 1
            await work.progress.step() // pad to the declared total
        }

        // The params snapshot carries the mode-specific record (the NCC
        // measurement is deterministic — identity-stable, D-08-3-T4-1).
        var provenanceParams = work.params
        provenanceParams.pyramidLevels = levels
        provenanceParams.nccThreshold =
            work.params.nccThreshold ?? FocusStackMerge.nccWarnThreshold
        provenanceParams.nccMeasuredMin = nccMin

        return try await landStackProduct(
            work, width: width, height: height, rgba: outputPlane,
            holeFraction: 0, alignmentLabels: labels, warnings: warnings,
            provenanceParams: provenanceParams,
            algorithmName: Self.focusAlgorithmName)
    }

    /// The stacking-denoise production leg (average/median/sigma; research
    /// §6): stack precheck → MTB alignment → staged band-outer aggregation
    /// (the N-value stack exists ONLY within one band) → landing.
    nonisolated private static func runStackAggregateLeg(
        _ work: StackMergeWork
    ) async throws -> StackMergeOutcome {
        guard work.decoded.count == work.sources.count, work.decoded.count >= 2
        else {
            throw AppError.invalidParameter(
                "stack denoise: \(work.decoded.count) decoded frames for "
                    + "\(work.sources.count) sources")
        }
        let mode: StackAggregate.Mode
        switch work.kind {
        case .stackAverage: mode = .average
        case .stackMedian: mode = .median
        case .stackSigma: mode = .sigmaClip
        default:
            throw AppError.invalidParameter(
                "\(work.kind.rawValue) is not a stacking-denoise kind")
        }
        let refExtent = work.decoded[0].ciImage.extent
        for image in work.decoded.dropFirst()
        where image.ciImage.extent != refExtent {
            throw AppError.invalidParameter(
                "stack frames differ in extent: \(refExtent.size) vs "
                    + "\(image.ciImage.extent.size)")
        }
        let width = Int(refExtent.width)
        let height = Int(refExtent.height)
        let sigmaK = work.params.sigmaClipK ?? StackAggregate.defaultSigmaK

        // The N=3 σ-clip degenerate (research R6): the warning rides the
        // outcome (the statistics are too weak to reject anything).
        var warnings: [String] = []
        if mode == .sigmaClip, work.decoded.count <= 3 {
            warnings.append(
                "sigma-clip with N=\(work.decoded.count) is statistically weak "
                    + "(nothing can be rejected) — quality rises with more frames")
        }

        let (shifts, labels, _, _) = try await runStackPrecheckAndAlignment(
            work, width: width, height: height, withNCC: false)

        // ── the stage pass (pixels only — stacks need no quality map) ───
        let staging = StagedSet(count: work.decoded.count, width: width, height: height)
        defer { staging.cleanUp() }
        for index in work.decoded.indices {
            let plane = try work.render.renderFullFloatRGBA(work.decoded[index].ciImage)
            try staging.writePixels(plane, index: index)
            await work.progress.step() // stage step
        }

        // ── the aggregate pass: band-outer, the N-value stack in-band ───
        var outputPlane = [Float](repeating: 0, count: width * height * 4)
        var holes = 0
        var bumpBudget = work.decoded.count
        for band in BandStreamer.bands(height: height, width: width) {
            var stack: [[Float]] = []
            stack.reserveCapacity(work.decoded.count)
            for index in work.decoded.indices {
                stack.append(try staging.readShiftedPixels(
                    index: index, firstRow: band.y, rows: band.height,
                    dx: shifts[index].dx, dy: shifts[index].dy))
            }
            let rowFloats = band.height * width * 4
            var aggregated = [Float](repeating: 0, count: rowFloats)
            for index in 0..<rowFloats {
                if index % 4 == 3 {
                    aggregated[index] = 1
                    continue
                }
                var valid: [Float] = []
                valid.reserveCapacity(stack.count)
                for plane in stack where plane[index].isFinite {
                    valid.append(plane[index])
                }
                if valid.isEmpty {
                    aggregated[index] = 0
                    if index % 4 == 0 { holes += 1 }
                    continue
                }
                aggregated[index] = StackAggregate.aggregate(
                    valid, mode: mode, sigmaK: sigmaK)
            }
            outputPlane.replaceSubrange(
                band.y * width * 4..<(band.y + band.height) * width * 4,
                with: aggregated)
            if bumpBudget > 0 {
                bumpBudget -= 1
                await work.progress.step() // aggregate step (band-paced)
            }
        }
        while bumpBudget > 0 {
            bumpBudget -= 1
            await work.progress.step()
        }
        let holeFraction =
            width * height > 0 ? Float(holes) / Float(width * height) : 0

        var provenanceParams = work.params
        if mode == .sigmaClip {
            provenanceParams.sigmaClipK = sigmaK
        }

        return try await landStackProduct(
            work, width: width, height: height, rgba: outputPlane,
            holeFraction: holeFraction, alignmentLabels: labels,
            warnings: warnings, provenanceParams: provenanceParams,
            algorithmName: Self.stackAlgorithmName)
    }

    /// The shared 08-3 product landing (the 08-1 tail shape: the
    /// ExportNamer-collision-free float TIFF + the v4 provenance sidecar;
    /// stacks land NO ghost mask and a nil layer stack).
    nonisolated private static func landStackProduct(
        _ work: StackMergeWork, width: Int, height: Int, rgba: [Float],
        holeFraction: Float, alignmentLabels: [String], warnings: [String],
        provenanceParams: StackMergeService.MergeParams, algorithmName: String
    ) async throws -> StackMergeOutcome {
        let directory = work.sessionRoot
            ?? work.sources[0].deletingLastPathComponent()
        let occupied = StackMergeService.defaultOccupiedNames(in: directory)
        let productURL = ExportNamer.destinationURL(
            directory: directory,
            stem: work.sources[0].deletingPathExtension().lastPathComponent,
            tag: work.params.tag ?? Self.defaultTag(for: work.kind),
            ext: "tif",
            occupiedNames: occupied)
        try BandStreamer.writeFloatTIFF(rgba, width: width, height: height, to: productURL)
        await work.progress.step() // write step

        let sessionRoot = work.sessionRoot
            ?? work.sources[0].deletingLastPathComponent()
        let provenanceSources: [SidecarProvenance.Source] = try work.sources
            .map { url -> SidecarProvenance.Source in
                let absolute = url.path
                let rootPrefix = sessionRoot.path + "/"
                let relPath = absolute.hasPrefix(rootPrefix)
                    ? String(absolute.dropFirst(rootPrefix.count))
                    : url.lastPathComponent
                guard let hash = ProvenanceReplay.fileHash(url) else {
                    throw AppError.fileUnreadable(url.path)
                }
                // Stacks carry no exposure weighting — the EV is a
                // flat zero for every source.
                return SidecarProvenance.Source(
                    relPath: relPath, stableHash: hash, exposureEV: 0)
            }
        let provenance = SidecarProvenance(
            kind: work.kind.provenanceKind,
            algorithm: SidecarProvenance.Algorithm(
                name: algorithmName,
                implementationVersion: ProvenanceReplay.hdrImplementationVersion,
                params: provenanceParams),
            sources: provenanceSources,
            alignment: alignmentLabels,
            exposureRatioVerified: Array(repeating: true, count: work.sources.count),
            holeFraction: holeFraction,
            createdAt: Date(),
            appVersion: LightamerSidecar.currentAppVersion)
        let decodeHash = HistoryHash.decodeParamsHash(for: work.decoded[0])
        let emptyStack = HistoryStack(items: [], position: 0)
        let sidecar = LightamerSidecar(
            imageID: UUID(),
            decoderVersionUsed: work.decoded[0].decoderVersionUsed.rawValue,
            decodeParamsHash: decodeHash,
            instances: [],
            history: emptyStack,
            historyHash: HistoryHash.hash(stack: emptyStack, decodeParamsHash: decodeHash),
            layerStack: nil,
            provenance: provenance)
        let sidecarEncoder = JSONEncoder()
        sidecarEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let sidecarData = try sidecarEncoder.encode(sidecar)
        try sidecarData.write(
            to: LightamerSidecar.sidecarURL(for: productURL), options: .atomic)
        await work.progress.step() // sidecar step

        return StackMergeOutcome(
            productURL: productURL,
            holeFraction: holeFraction,
            alignment: alignmentLabels,
            exposureRatioVerified: Array(repeating: true, count: work.sources.count),
            ghostMask: nil,
            exposureEVs: [],
            warnings: warnings)
    }

    /// The staged-files working set (the temp-dir cleanup discipline: the
    /// whole directory dies with the leg — error paths included, via the
    /// caller's `defer`).
    private struct StagedSet {
        let directory: URL
        let width: Int
        let height: Int

        init(count: Int, width: Int, height: Int) {
            self.width = width
            self.height = height
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("la-stack-\(UUID().uuidString)",
                    isDirectory: true)
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }

        private func pixelsURL(_ index: Int) -> URL {
            directory.appendingPathComponent("pixels_\(index).f32")
        }
        private func qualityURL(_ index: Int) -> URL {
            directory.appendingPathComponent("quality_\(index).f16")
        }

        /// Stream one plane's rows to the staged file (no whole-file Data).
        func writePixels(_ plane: StackRenderedPlane, index: Int) throws {
            FileManager.default.createFile(atPath: pixelsURL(index).path, contents: nil)
            let handle = try FileHandle(forWritingTo: pixelsURL(index))
            defer { try? handle.close() }
            let rowsPerChunk = 64
            var y = 0
            while y < plane.height {
                let rows = min(rowsPerChunk, plane.height - y)
                let chunk = Data(
                    bytes: plane.pointer.advanced(by: y * plane.bytesPerRow),
                    count: rows * plane.bytesPerRow)
                try handle.write(contentsOf: chunk)
                y += rows
            }
        }

        func writeQuality(_ map: [UInt16], index: Int) throws {
            let data = map.withUnsafeBufferPointer { Data(buffer: $0) }
            try data.write(to: qualityURL(index), options: .atomic)
        }

        /// The ALIGNED read: output pixel (x, y) samples the staged source
        /// at (x − dx, y − dy); out-of-frame → NaN (the alpha 1 fill marks
        /// in-frame pixels).
        func readShiftedPixels(
            index: Int, firstRow: Int, rows: Int, dx: Int, dy: Int
        ) throws -> [Float] {
            var result = [Float](repeating: .nan, count: rows * width * 4)
            let sourceFirst = max(0, firstRow - dy)
            let sourceLast = min(height, firstRow + rows - dy) // exclusive
            guard sourceLast > sourceFirst else { return result }
            let handle = try FileHandle(forReadingFrom: pixelsURL(index))
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(sourceFirst * width * 16))
            let want = (sourceLast - sourceFirst) * width * 16
            guard let data = try handle.read(upToCount: want), data.count == want
            else {
                throw AppError.fileUnreadable("staged pixels truncated")
            }
            result.withUnsafeMutableBytes { raw in
                let out = raw.bindMemory(to: Float.self)
                data.withUnsafeBytes { stagedRaw in
                    let staged = stagedRaw.bindMemory(to: Float.self)
                    for row in 0..<rows {
                        let sy = firstRow + row - dy
                        guard sy >= sourceFirst, sy < sourceLast else { continue }
                        let stagedRowBase = ((sy - sourceFirst) * width)
                        let outRowBase = (row * width)
                        for x in 0..<width {
                            let sx = x - dx
                            guard sx >= 0, sx < width else { continue }
                            let s = (stagedRowBase + sx) * 4
                            let d = (outRowBase + x) * 4
                            out[d] = staged[s]
                            out[d + 1] = staged[s + 1]
                            out[d + 2] = staged[s + 2]
                            out[d + 3] = 1
                        }
                    }
                }
            }
            return result
        }

        /// The quality read (half bits → float); out-of-frame → 0
        /// (WEIGHTLESS — the shifted-out strip carries no vote).
        func readShiftedQuality(
            index: Int, firstRow: Int, rows: Int, dx: Int, dy: Int
        ) throws -> [Float] {
            var result = [Float](repeating: 0, count: rows * width)
            let sourceFirst = max(0, firstRow - dy)
            let sourceLast = min(height, firstRow + rows - dy)
            guard sourceLast > sourceFirst else { return result }
            let handle = try FileHandle(forReadingFrom: qualityURL(index))
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(sourceFirst * width * 2))
            let want = (sourceLast - sourceFirst) * width * 2
            guard let data = try handle.read(upToCount: want), data.count == want
            else {
                throw AppError.fileUnreadable("staged quality truncated")
            }
            result.withUnsafeMutableBufferPointer { out in
                data.withUnsafeBytes { stagedRaw in
                    let staged = stagedRaw.bindMemory(to: UInt16.self)
                    for row in 0..<rows {
                        let sy = firstRow + row - dy
                        guard sy >= sourceFirst, sy < sourceLast else { continue }
                        let stagedRowBase = (sy - sourceFirst) * width
                        let outRowBase = row * width
                        for x in 0..<width {
                            let sx = x - dx
                            guard sx >= 0, sx < width else { continue }
                            out[outRowBase + x] = Float(Float16(
                                bitPattern: staged[stagedRowBase + sx]))
                        }
                    }
                }
            }
            return result
        }
    }
}
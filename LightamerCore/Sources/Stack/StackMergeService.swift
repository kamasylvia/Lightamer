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
        /// The spherical-feature panorama merge (Plan M5-3-01 KD-6). PURELY
        /// additive — the six existing kinds' rows are byte-identical (the
        /// G5 zero-regression lock); the production leg lands in M5-3-02
        /// (this plan ships the typed stub).
        case pano = "pano-merge"

        /// The provenance vocabulary mapping (identical raw values).
        public var provenanceKind: SidecarProvenance.Kind {
            switch self {
            case .hdrMerge: return .hdrMerge
            case .focusStack: return .focusStack
            case .stackAverage: return .stackAverage
            case .stackMedian: return .stackMedian
            case .stackSigma: return .stackSigma
            case .hdrMertens: return .hdrMertens
            case .pano: return .panoMerge
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

        /// The resolved panorama canvas [w, h] (Plan M5-3-01 KD-7). nil =
        /// not a pano merge / not yet resolved. Additive optional — old
        /// sidecars decode fine and re-encode byte-identical (the
        /// synthesized encodeIfPresent). Consumption + write-back = the
        /// M5-3-02 leg (the 08-3 `pyramidLevels` resolved-snapshot
        /// precedent — provenance states what ran).
        public var panoCanvas: [Int]?

        /// The resolved exposure gains, reference frame first (KD-7).
        /// nil = not a pano merge / not yet resolved.
        public var panoGains: [Double]?

        /// The resolved inner-crop rectangle [x0, y0, x1, y1] (KD-7).
        /// nil = not a pano merge / not yet resolved.
        public var panoCrop: [Int]?

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
            mertensLevels: Int? = nil,
            panoCanvas: [Int]? = nil,
            panoGains: [Double]? = nil,
            panoCrop: [Int]? = nil
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
            self.panoCanvas = panoCanvas
            self.panoGains = panoGains
            self.panoCrop = panoCrop
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
        // The pano 2..32 gate (Plan M5-3-01 KD-6; OQ-4): the kind-
        // CONDITIONAL upper bound — the six existing kinds' path is
        // byte-identical (a pure additive if).
        if kind == .pano, sources.count > 32 {
            throw AppError.invalidParameter(
                "pano merge accepts at most 32 sources, got \(sources.count)")
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
        case .pano:
            // The honest pano declaration (Plan M5-3-01 KD-6): decode N +
            // features N + fusion N (the tile-paced leg consumption,
            // M5-3-02) + 6 = matching/BA/wave 1 + canvas/ROI 1 + gains 1 +
            // write 1 + sidecar 1 + settle 1.
            return sources * 3 + 6
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
        case .pano: return "pano"
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
        case .pano:
            return try await runPanoLeg(work)
        }
    }

    /// The pano production leg (Plan M5-3-02 T4; KD-10): the staged
    /// pipeline — ① per source ONE decode-render, sRGB display-encoded in
    /// place (KD-1's Mertens-leg domain), staged to disk, and the preview
    /// gray derived from the SAME encoded plane (the checker-minor-2 seam:
    /// the M5-3-01 `rgbaEncoded` face, no second encode) — the feature step
    /// per source; ② the M5-3-01 chain over the previews (all-pairs knn →
    /// Lowe → ONE seeded RANSAC stream → the edge gate → the reference BFS
    /// connectivity → focal initials → LM BA → wave correct) — one step;
    /// ③ the canvas segment (preview-focal back-projection, the median
    /// scale, the bounded shrink loop) — one step; ④ the gain segment (the
    /// ≤900px sample canvases over the staged planes + the anchored min-
    /// norm lstsq) — one step; ⑤ pass 1: the geometry-only valid mask
    /// (weight > 0 is pure geometry — the crop resolves before any staged
    /// pixel is read, the memory red line's mathematical basis) + the
    /// histogram-stack inner crop; ⑥ pass 2: the 512px tile fusion
    /// streaming crop rows band by band through the rowProvider into the
    /// `FloatTIFFWriter` — N band-paced steps (padded after landing).
    ///
    /// THE EXTENT GATE IS DELIBERATELY ABSENT (KD-10): different viewpoints
    /// legitimately differ in size — the key divergence from the
    /// Mertens/HDR bracket legs (the DECISIONS note).
    ///
    /// Progress = 2N+5 inside this leg (features N + chain 1 + canvas 1 +
    /// gains 1 + fusion N + write 1 + sidecar 1); with the service's decode
    /// N and the settle 1 the declared total is exactly 3N+6.
    nonisolated private static func runPanoLeg(
        _ work: StackMergeWork
    ) async throws -> StackMergeOutcome {
        guard work.decoded.count == work.sources.count,
              work.decoded.count >= 2
        else {
            throw AppError.invalidParameter(
                "pano merge: \(work.decoded.count) decoded frames for "
                    + "\(work.sources.count) sources")
        }
        let sourceCount = work.decoded.count

        let staging = StagedSet(count: sourceCount, width: 1, height: 1)
        defer { staging.cleanUp() }

        // ── ① the stage pass: encode → staged → preview gray → features ──
        var keypoints: [[PanoKeypoint]] = []
        var descriptors: [[PanoDescriptor]] = []
        var sourceSizes: [(width: Int, height: Int)] = []
        var previewSizes: [(width: Int, height: Int)] = []
        keypoints.reserveCapacity(sourceCount)
        descriptors.reserveCapacity(sourceCount)
        sourceSizes.reserveCapacity(sourceCount)
        previewSizes.reserveCapacity(sourceCount)
        for index in work.decoded.indices {
            let plane = try work.render.renderFullFloatRGBA(
                work.decoded[index].ciImage)
            let sourceSize = (width: plane.width, height: plane.height)
            mertensDisplayEncodeInPlace(plane)
            try staging.writePixels(plane, index: index)
            let preview = panoPreviewGrayFromEncoded(plane)
            // The transient full plane dies with the loop iteration.
            let detection = PanoFeature.detectAndDescribe(preview)
            guard detection.keypoints.count >= PanoFeature.minFeaturesPerImage
            else {
                throw AppError.invalidParameter(
                    PanoMatch.FailurePrefix.alignment + "image \(index) has "
                        + "\(detection.keypoints.count) features (< "
                        + "\(PanoFeature.minFeaturesPerImage))")
            }
            keypoints.append(detection.keypoints)
            descriptors.append(detection.descriptors)
            sourceSizes.append(sourceSize)
            previewSizes.append(
                (width: preview.width, height: preview.height))
            await work.progress.step() // feature step
        }

        // ── ② the match chain (all pairs; ONE seeded stream) ─────────────
        var rng = PanoRNG()
        var adjacency: [Set<Int>] = (0..<sourceCount).map { [$0] }
        var bundles: [PanoMatchBundle] = []
        var edgeHomographies: [Mat3D] = []
        var edgePairs: [(first: Int, second: Int)] = []
        for i in 0..<sourceCount {
            let centerI = (
                x: (Double(previewSizes[i].width) - 1) / 2,
                y: (Double(previewSizes[i].height) - 1) / 2)
            for j in (i + 1)..<sourceCount {
                let centerJ = (
                    x: (Double(previewSizes[j].width) - 1) / 2,
                    y: (Double(previewSizes[j].height) - 1) / 2)
                let matches = PanoMatch.ratioFilter(PanoMatch.knn2(
                    query: descriptors[i], train: descriptors[j]))
                guard !matches.isEmpty else { continue }
                let correspondences = matches.map { match -> PanoCorrespondence in
                    let first = keypoints[i][match.queryIndex]
                    let second = keypoints[j][match.bestIndex]
                    return PanoCorrespondence(
                        first.x - centerI.x, first.y - centerI.y,
                        second.x - centerJ.x, second.y - centerJ.y)
                }
                guard let estimate = PanoMatch.ransacHomography(
                    correspondences, rng: &rng)
                else { continue }
                let confidence = PanoMatch.matchConfidence(
                    inliers: estimate.inliers.count,
                    matches: correspondences.count)
                guard PanoMatch.isValidEdge(
                    confidence: confidence,
                    inliers: estimate.inliers.count)
                else { continue }
                adjacency[i].insert(j)
                adjacency[j].insert(i)
                edgePairs.append((i, j))
                edgeHomographies.append(estimate.homography)
                bundles.append(PanoMatchBundle(
                    first: i, second: j,
                    correspondences: estimate.inliers.map {
                        correspondences[$0]
                    }))
            }
        }
        guard let initialFocal = PanoCamera.medianFocal(edgeHomographies) else {
            throw AppError.invalidParameter(
                PanoMatch.FailurePrefix.alignment
                    + "no image pair carries focal information")
        }
        let component = PanoMatch.connectedComponent(
            imageCount: sourceCount, adjacency: adjacency, reference: 0)
        guard component.count == sourceCount else {
            throw AppError.invalidParameter(
                PanoMatch.FailurePrefix.disconnected + "\(component.count) of "
                    + "\(sourceCount) images in the closure")
        }
        // The rotation seeds: BFS from the reference over the valid edges,
        // R_child = orthogonalize(K⁻¹·H_parent→child·K) · R_parent (the
        // H ≈ K·R_child·R_parentᵀ·K⁻¹ decomposition; the gauge rides on
        // the reference identity — the G2 wiring shape).
        var initialRotations = [Mat3D](
            repeating: Mat3D.identity, count: sourceCount)
        var visited: Set<Int> = [0]
        var queue = [0]
        while !queue.isEmpty {
            let parent = queue.removeFirst()
            for child in adjacency[parent].sorted() where !visited.contains(child) {
                visited.insert(child)
                queue.append(child)
                // The stored homography maps edge.first → edge.second.
                let homography: Mat3D
                if let edgeIndex = edgePairs.firstIndex(where: {
                    ($0.first == parent && $0.second == child)
                        || ($0.first == child && $0.second == parent)
                }) {
                    homography = edgePairs[edgeIndex].first == parent
                        ? edgeHomographies[edgeIndex]
                        : (edgeHomographies[edgeIndex].inverted()
                            ?? Mat3D.identity)
                } else {
                    continue
                }
                guard let relative = PanoCamera.initialRotation(
                    from: homography, focal: initialFocal)
                else { continue }
                initialRotations[child] = Mat3D.mul(relative, initialRotations[parent])
            }
        }
        guard let solution = PanoCamera.bundleAdjust(
            matches: bundles, imageCount: sourceCount,
            initialFocal: initialFocal, initialRotations: initialRotations)
        else {
            throw AppError.invalidParameter(
                PanoMatch.FailurePrefix.alignment
                    + "bundle adjustment did not converge")
        }
        let rotations = PanoCamera.waveCorrectHorizontally(solution.rotations)
        await work.progress.step() // the matching/BA/wave step

        // ── ③ the canvas segment (KD-3/KD-4) ────────────────────────────
        var sources: [PanoSourceGeometry] = []
        sources.reserveCapacity(sourceCount)
        for index in 0..<sourceCount {
            let focal = PanoWarp.fullResolutionFocal(
                previewFocal: solution.focal,
                previewWidth: previewSizes[index].width,
                fullWidth: sourceSizes[index].width)
            sources.append(PanoSourceGeometry(
                width: sourceSizes[index].width,
                height: sourceSizes[index].height,
                focal: focal, rotation: rotations[index]))
        }
        let scale = PanoWarp.globalScale(focals: sources.map(\.focal))
        let canvas = try PanoWarp.boundedCanvas(sources: sources, scale: scale)
        await work.progress.step() // the canvas/ROI step

        // ── ④ the gains segment (KD-6) ──────────────────────────────────
        let sampleSize = PanoGain.sampleCanvasSize(
            canvasWidth: canvas.width, canvasHeight: canvas.height)
        let sampleRatio = Double(sampleSize.width) / Double(max(1, canvas.width))
        var samplePlanes: [PanoGainSamplePlane] = []
        samplePlanes.reserveCapacity(sourceCount)
        for index in 0..<sourceCount {
            let source = sources[index]
            let plane = try PanoGain.samplePlane(
                rectX: Double(canvas.originX) * sampleRatio,
                rectY: Double(canvas.originY) * sampleRatio,
                width: sampleSize.width, height: sampleSize.height,
                scale: canvas.scale * sampleRatio, source: source,
                rowReader: { first, count in
                    try staging.readRows(
                        index: index, firstRow: first, rows: count,
                        bytesPerRow: source.width * 16)
                })
            samplePlanes.append(plane)
        }
        let (gains, gainsClipped) = PanoGain.gains(
            planes: samplePlanes, reference: 0)
        var warnings: [String] = []
        if gainsClipped {
            warnings.append(
                "panorama exposure gains clamped at the ±"
                    + "\(PanoGain.clipLimit) log ceiling")
        }
        await work.progress.step() // the gains step

        // ── ⑤ pass 1: the geometry valid mask + the inner crop ──────────
        let valid = panoValidMask(
            sources: sources, rois: canvas.rois, canvas: canvas)
        let crop = try PanoCrop.innerCrop(
            valid: valid, width: canvas.width, height: canvas.height)
        // The mask dies here — pass 2 rides the crop bounds only.

        // ── ⑥ pass 2 + landing: the streaming row-band provider ─────────
        let gainFactors = gains.map { Float($0) }
        var fusionBudget = sourceCount
        let rowProvider: (_ firstRow: Int, _ rowCount: Int) async throws -> [Float] =
            { firstRow, rowCount in
                let rows = try Self.panoFuseRows(
                    staging: staging, sources: sources, rois: canvas.rois,
                    gains: gainFactors, canvas: canvas,
                    cropX0: crop.x0, cropX1: crop.x1,
                    firstRow: crop.y0 + firstRow, rowCount: rowCount)
                // The Lumen finite gate (merge_images tail) — the typed
                // non-prefix pass-through (the zh mapping's non-prefix arm).
                for value in rows where !value.isFinite {
                    throw AppError.invalidParameter(
                        "panorama merge produced non-finite pixels")
                }
                if fusionBudget > 0 {
                    fusionBudget -= 1
                    await work.progress.step() // the fusion step (band-paced)
                }
                return rows
            }

        // The provenance snapshot states what ran (the 08-3 pyramidLevels
        // resolved-snapshot precedent).
        var provenanceParams = work.params
        provenanceParams.panoCanvas = [canvas.width, canvas.height]
        provenanceParams.panoGains = gains
        provenanceParams.panoCrop = [crop.x0, crop.y0, crop.x1, crop.y1]

        // The alignment vocabulary (KD-9): deterministic per-source labels.
        var alignmentLabels: [String] = []
        alignmentLabels.reserveCapacity(sourceCount)
        for index in 0..<sourceCount {
            if index == 0 {
                alignmentLabels.append("reference")
            } else {
                let inliers = bundles.reduce(0) { total, bundle in
                    bundle.first == index || bundle.second == index
                        ? total + bundle.correspondences.count : total
                }
                alignmentLabels.append("inliers=\(inliers)")
            }
        }

        let outcome = try await landStackProduct(
            work, width: crop.width, height: crop.height, rgba: [],
            holeFraction: 0, alignmentLabels: alignmentLabels,
            warnings: warnings, provenanceParams: provenanceParams,
            algorithmName: ProvenanceReplay.panoAlgorithmName,
            implementationVersion: ProvenanceReplay.panoImplementationVersion,
            exposureEVs: nil, ghostUnion: nil,
            productColorSpace: CGColorSpace(name: CGColorSpace.sRGB),
            rowProvider: rowProvider)
        // The tiny-canvas pad (fewer bands than N — the honest count still
        // closes to the declared total).
        while fusionBudget > 0 {
            fusionBudget -= 1
            await work.progress.step()
        }
        return outcome
    }

    // MARK: - Pano leg internals (T4; the probe's direct-drive seams)

    /// The sRGB-encoded preview gray off an ALREADY-ENCODED plane buffer
    /// (the checker-minor-2 seam consumed from the buffer): the fused
    /// luma+box-downsample walk — NO full-resolution intermediates (the
    /// 01 `preparePreviewGray(rgbaEncoded:)` face with the encode skipped
    /// and the array copy fused into the box walk; bit-identical, pinned
    /// by the drift-guard test).
    nonisolated static func panoPreviewGrayFromEncoded(
        _ plane: StackRenderedPlane
    ) -> PanoGrayPlane {
        let cr = Double(MertensFusion.grayCoefficients.r)
        let cg = Double(MertensFusion.grayCoefficients.g)
        let cb = Double(MertensFusion.grayCoefficients.b)
        let floats = UnsafeRawBufferPointer(
            start: plane.pointer, count: plane.bytesPerRow * plane.height)
            .bindMemory(to: Float.self)
        func lumaAt(_ index: Int) -> Float {
            let base = index * 4
            return Float(
                cr * Double(floats[base]) + cg * Double(floats[base + 1])
                    + cb * Double(floats[base + 2]))
        }
        let longEdge = max(plane.width, plane.height)
        guard longEdge > PanoFeature.previewMaxEdge else {
            var luma = [Float](
                repeating: 0, count: plane.width * plane.height)
            for index in luma.indices {
                luma[index] = lumaAt(index)
            }
            return PanoGrayPlane(
                width: plane.width, height: plane.height, pixels: luma)
        }
        // The box downsample (the PanoFeature.prepare walk verbatim — the
        // pinned fractional-boundary shared-pixel property included).
        let scale = Double(PanoFeature.previewMaxEdge) / Double(longEdge)
        let tw = max(1, Int((Double(plane.width) * scale).rounded()))
        let th = max(1, Int((Double(plane.height) * scale).rounded()))
        var out = [Float](repeating: 0, count: tw * th)
        for y in 0..<th {
            let y0 = y * plane.height / th
            let y1 = min(plane.height, ((y + 1) * plane.height + th - 1) / th)
            for x in 0..<tw {
                let x0 = x * plane.width / tw
                let x1 = min(plane.width, ((x + 1) * plane.width + tw - 1) / tw)
                var sum = Float(0)
                for yy in y0..<y1 {
                    let row = yy * plane.width
                    for xx in x0..<x1 {
                        sum += lumaAt(row + xx)
                    }
                }
                out[y * tw + x] = sum / Float((y1 - y0) * (x1 - x0))
            }
        }
        return PanoGrayPlane(width: tw, height: th, pixels: out)
    }

    /// The per-source geometric feather alpha (merge.py:279-281 — the 12%
    /// short-edge fade band): clip(edge/(min(ih,iw)×0.12), 0.001, 1) ×
    /// inside. PURE GEOMETRY (no pixel values — the pass-1/pass-2 weight
    /// identity's basis).
    nonisolated static func panoFeatherAlpha(
        mx: Float, my: Float, source: PanoSourceGeometry
    ) -> Float {
        guard mx >= 0, my >= 0, mx <= Float(source.width - 1),
              my <= Float(source.height - 1)
        else { return 0 }
        let edge = min(
            min(mx + 1, Float(source.width) - mx),
            min(my + 1, Float(source.height) - my))
        let feather = edge / (Float(min(source.height, source.width)) * 0.12)
        return min(max(feather, 0.001), 1)
    }

    /// The geometry pass (KD-5 pass 1): the canvas valid mask (UInt8 1 B/px
    /// — 200 MB at the 200 MP cap). A pixel is valid iff ANY source maps
    /// it inside (weight = Σ alpha > 0 ⟺ some alpha > 0, the pure-geometry
    /// identity). Tile-walked; the ROI intersect only skips provably-empty
    /// tiles (the ROIs err large).
    nonisolated static func panoValidMask(
        sources: [PanoSourceGeometry], rois: [PanoROI],
        canvas: PanoCanvasPlan, tileSize: Int = 512
    ) -> [UInt8] {
        var valid = [UInt8](
            repeating: 0, count: canvas.width * canvas.height)
        for tileY in stride(from: 0, to: canvas.height, by: tileSize) {
            let tileHeight = min(tileSize, canvas.height - tileY)
            for tileX in stride(from: 0, to: canvas.width, by: tileSize) {
                let tileWidth = min(tileSize, canvas.width - tileX)
                let rectX = Double(canvas.originX + tileX)
                let rectY = Double(canvas.originY + tileY)
                for (index, source) in sources.enumerated() {
                    let roi = rois[index]
                    if roi.x + roi.width < canvas.originX + tileX
                        || roi.x > canvas.originX + tileX + tileWidth
                        || roi.y + roi.height < canvas.originY + tileY
                        || roi.y > canvas.originY + tileY + tileHeight {
                        continue
                    }
                    let (mx, my) = PanoWarp.sphericalMap(
                        rectX: rectX, rectY: rectY, width: tileWidth,
                        height: tileHeight, scale: canvas.scale, source: source)
                    for row in 0..<tileHeight {
                        let canvasRow = (tileY + row) * canvas.width
                        let tileRow = row * tileWidth
                        for column in 0..<tileWidth
                        where valid[canvasRow + tileX + column] == 0 {
                            let sx = mx[tileRow + column]
                            let sy = my[tileRow + column]
                            if sx >= 0, sy >= 0,
                               sx <= Float(source.width - 1),
                               sy <= Float(source.height - 1) {
                                valid[canvasRow + tileX + column] = 1
                            }
                        }
                    }
                }
            }
        }
        return valid
    }

    /// The tile-fusion core (KD-5 pass 2; the probe's direct-drive seam —
    /// the `mertensBandOuterFuse` precedent): fuses canvas rows
    /// [firstRow, firstRow+rowCount) restricted to canvas columns
    /// [cropX0, cropX1) into crop-local RGBA rows (alpha 1). Per band and
    /// source: ONE union row-span staged read (the span from a strided map
    /// sampling of the band, padded — the probe-round finding: per-TILE
    /// reads re-read the same source rows 84× per band, and the read
    /// volume carried a linear phys_footprint climb that system-killed
    /// the 200 MP probe rounds at ~25 GB; the band-level read cuts the
    /// volume ~84× and holds the footprint flat). Per col-tile then: the
    /// spherical map, the clamped bilinear gather out of the band strip
    /// (the BORDER_REPLICATE semantics — the alpha gate zeroes the
    /// outside), the feather alpha and the gain; the per-pixel normalize
    /// rides `accum/max(weight,1e-8)` clamped to [0,1] (merge.py:283-288).
    /// Deterministic order: tiles top-to-bottom/left-to-right, sources in
    /// index order (G1's anchor).
    nonisolated static func panoFuseRows(
        staging: StagedSet, sources: [PanoSourceGeometry], rois: [PanoROI],
        gains: [Float], canvas: PanoCanvasPlan,
        cropX0: Int, cropX1: Int,
        firstRow: Int, rowCount: Int, tileSize: Int = 512
    ) throws -> [Float] {
        let outWidth = cropX1 - cropX0
        precondition(outWidth >= 1 && rowCount >= 1, "degenerate fuse band")

        // ── the band's per-source union spans + the staged strips ────────
        // The span sampler walks the band on a 64×64 grid (the map varies
        // smoothly — the sample miss is bounded well under the pad) and
        // the pad covers the sampling grid plus the rotation stretch.
        let sampleStride = 64
        let spanPad = 2 * sampleStride
        var spans = [(first: Int, last: Int, count: Int)](
            repeating: (0, 0, 0), count: sources.count)
        var strips = [[Float]](repeating: [], count: sources.count)
        for (index, source) in sources.enumerated() {
            let roi = rois[index]
            // The ROIs live in the angle·scale frame — both crop bounds
            // need the origin shift into that frame (the Y pair below
            // already carries it; the X pair lost it once — E-omp-1: any
            // non-zero originX opened a |originX|-wide kill band that
            // skipped whole sources).
            guard roi.x + roi.width > canvas.originX + cropX0,
                  roi.x < canvas.originX + cropX1,
                  roi.y + roi.height > canvas.originY + firstRow,
                  roi.y < canvas.originY + firstRow + rowCount
            else { continue }
            var minRow = Int.max
            var maxRow = Int.min
            var y = firstRow
            while y < firstRow + rowCount {
                var x = cropX0
                let sampleHeight = min(sampleStride, firstRow + rowCount - y)
                while x < cropX1 {
                    let sampleWidth = min(sampleStride, cropX1 - x)
                    let (mx, my) = PanoWarp.sphericalMap(
                        rectX: Double(canvas.originX + x),
                        rectY: Double(canvas.originY + y),
                        width: sampleWidth, height: sampleHeight,
                        scale: canvas.scale, source: source)
                    for sampleIndex in mx.indices {
                        let sx = mx[sampleIndex]
                        let sy = my[sampleIndex]
                        if sx >= 0, sy >= 0, sx <= Float(source.width - 1),
                           sy <= Float(source.height - 1) {
                            let row = Int(sy)
                            minRow = min(minRow, row)
                            maxRow = max(maxRow, row + 1)
                        }
                    }
                    x += sampleStride
                }
                y += sampleStride
            }
            guard minRow != Int.max else { continue }
            let first = max(0, minRow - spanPad)
            let last = min(source.height - 1, maxRow + spanPad)
            let count = try staging.readRows(
                index: index, firstRow: first, rows: last - first + 1,
                bytesPerRow: source.width * 16, into: &strips[index])
            spans[index] = (first, last, count)
        }

        // ── the tile walk (maps + gathers out of the band strips) ────────
        var accum = [Float](repeating: 0, count: rowCount * outWidth * 3)
        var weight = [Float](repeating: 0, count: rowCount * outWidth)
        for tileY in stride(
            from: firstRow, to: firstRow + rowCount, by: tileSize) {
            let tileHeight = min(tileSize, firstRow + rowCount - tileY)
            for tileX in stride(from: cropX0, to: cropX1, by: tileSize) {
                let tileWidth = min(tileSize, cropX1 - tileX)
                let rectX = Double(canvas.originX + tileX)
                let rectY = Double(canvas.originY + tileY)
                for (index, source) in sources.enumerated() {
                    let span = spans[index]
                    guard span.count > 0 else { continue }
                    let roi = rois[index]
                    if roi.x + roi.width < canvas.originX + tileX
                        || roi.x > canvas.originX + tileX + tileWidth
                        || roi.y + roi.height < canvas.originY + tileY
                        || roi.y > canvas.originY + tileY + tileHeight {
                        continue
                    }
                    let (mx, my) = PanoWarp.sphericalMap(
                        rectX: rectX, rectY: rectY, width: tileWidth,
                        height: tileHeight, scale: canvas.scale,
                        source: source)
                    let rows = strips[index]
                    let strideFloats = source.width * 4
                    let gain = gains[index]
                    let sourceWidth = source.width
                    let sourceHeight = source.height
                    for row in 0..<tileHeight {
                        let outputRow = tileY + row - firstRow
                        for column in 0..<tileWidth {
                            let tileIndex = row * tileWidth + column
                            let sx = mx[tileIndex]
                            let sy = my[tileIndex]
                            let alpha = panoFeatherAlpha(
                                mx: sx, my: sy, source: source)
                            if alpha <= 0 { continue }
                            // Clamped bilinear gather (BORDER_REPLICATE
                            // semantics; inside ⇒ sx, sy ∈ [0, dim−1]).
                            let ix0 = min(max(Int(sx), 0), sourceWidth - 1)
                            let fx = sx - Float(ix0)
                            let ix1 = min(ix0 + 1, sourceWidth - 1)
                            let iy0 = min(max(Int(sy), 0), sourceHeight - 1)
                            let fy = sy - Float(iy0)
                            let iy1 = min(iy0 + 1, sourceHeight - 1)
                            let row0 = (iy0 - span.first) * strideFloats
                            let row1 = (iy1 - span.first) * strideFloats
                            let c0 = ix0 * 4
                            let c1 = ix1 * 4
                            // The filled-prefix bound (the union span
                            // covers every inside neighborhood; the guard
                            // is the honest stale-tail defense).
                            if row0 < 0 || row1 + c1 + 3 >= span.count {
                                continue
                            }
                            let invFx = 1 - fx
                            let invFy = 1 - fy
                            let topR = rows[row0 + c0] * invFx
                                + rows[row0 + c1] * fx
                            let topG = rows[row0 + c0 + 1] * invFx
                                + rows[row0 + c1 + 1] * fx
                            let topB = rows[row0 + c0 + 2] * invFx
                                + rows[row0 + c1 + 2] * fx
                            let bottomR = rows[row1 + c0] * invFx
                                + rows[row1 + c1] * fx
                            let bottomG = rows[row1 + c0 + 1] * invFx
                                + rows[row1 + c1 + 1] * fx
                            let bottomB = rows[row1 + c0 + 2] * invFx
                                + rows[row1 + c1 + 2] * fx
                            let shared = alpha * gain
                            let outputIndex =
                                (outputRow * outWidth + tileX + column - cropX0)
                            accum[outputIndex * 3]
                                += (topR * invFy + bottomR * fy) * shared
                            accum[outputIndex * 3 + 1]
                                += (topG * invFy + bottomG * fy) * shared
                            accum[outputIndex * 3 + 2]
                                += (topB * invFy + bottomB * fy) * shared
                            weight[outputIndex] += alpha
                        }
                    }
                }
            }
        }
        var out = [Float](repeating: 0, count: rowCount * outWidth * 4)
        for index in 0..<(rowCount * outWidth) {
            let denominator = max(weight[index], 1e-8)
            out[index * 4] = min(max(accum[index * 3] / denominator, 0), 1)
            out[index * 4 + 1] =
                min(max(accum[index * 3 + 1] / denominator, 0), 1)
            out[index * 4 + 2] =
                min(max(accum[index * 3 + 2] / denominator, 0), 1)
            out[index * 4 + 3] = 1
        }
        return out
    }

    /// The Mertens production leg (Plan M5-2-02 T1, KD-1): the exposure
    /// fusion streaming pipeline — ① the EV-free precheck (OQ-5: warnings
    /// never reject, the composed ΔEV is RECORDED in provenance, never
    /// consumed) → ② the MTB alignment (the KD-3 helper, `withNCC: false`)
    /// → ③ the stage pass: per source ONE decode-render, display-encoded
    /// in place (sRGB piecewise + the curve's own [0,1] clamp — the 01
    /// KD-1 convention) and staged to disk; the deghost segment (tier ≠
    /// off) accumulates the per-frame binary motion against the resident
    /// reference gray, then the union dilates + feathers ONCE (merge.py
    /// :120-138 exact order) and stages as a SHARED UInt8 soft mask → ④
    /// the substitution LUTs (129 points/channel) estimated over the
    /// static cells of the FINAL mask from the staged pixels' decimation
    /// grid (merge.py:141-159; the whole-frame faces stay untouched) → ⑤
    /// the band-outer fusion: grid-aligned bands (band starts divisible by
    /// 2^(L−1) — the 01 DECISIONS §6 constraint), halo rows
    /// `haloRows(L)`, the reference substitution runs IN-PASS inside the
    /// provider (`prepared = strip·(1−α) + LUT(refStrip)·α`), NaN
    /// out-of-overlap samples sanitize to 0 (natural E³≈8.5e-5 weight
    /// suppression — the 01 G3③ constant) → ⑥ the shared landing path
    /// (`landStackProduct`, the additive EV/ghost arms).
    ///
    /// Resident set: the output plane (16 B/px) + ONE band's strips + the
    /// stage-time reference gray (single plane, freed per source) + the
    /// mask finalization transient. Full-resolution masks NEVER ride the
    /// fusion pass (the staged 1 B/px channel). Progress = 4N+3 exactly
    /// (decode N + align N + stage N + fuse N + write + sidecar + settle),
    /// the SAME window with tier off (the skipped substitution is not a
    /// step — KD-1's off-contract).
    nonisolated private static func runMertensLeg(
        _ work: StackMergeWork
    ) async throws -> StackMergeOutcome {
        guard work.decoded.count == work.sources.count, work.decoded.count >= 2
        else {
            throw AppError.invalidParameter(
                "mertens merge: \(work.decoded.count) decoded frames for "
                    + "\(work.sources.count) sources")
        }
        let refExtent = work.decoded[0].ciImage.extent
        for image in work.decoded.dropFirst()
        where image.ciImage.extent != refExtent {
            throw AppError.invalidParameter(
                "mertens frames differ in extent: \(refExtent.size) vs "
                    + "\(image.ciImage.extent.size)")
        }
        let width = Int(refExtent.width)
        let height = Int(refExtent.height)

        // ── the EV-free precheck (OQ-5): zero rejections, the ΔEV rides
        // provenance only ────────────────────────────────────────────────
        let verdicts = ExifPrecheck.mertensVerdicts(
            captures: work.decoded.map(\.capture))
        var exposureEVs: [Double] = []
        var warnings: [String] = []
        for (index, verdict) in verdicts.enumerated() {
            switch verdict {
            case .ok(let ev):
                exposureEVs.append(ev)
            case .admittedWithWarning(let ev, let reasons):
                exposureEVs.append(ev)
                warnings.append(
                    "source \(index): " + reasons.joined(separator: "; "))
                AppError.logger.warning(
                    "mertens source \(index, privacy: .public): \(reasons.joined(separator: "; "), privacy: .public)")
            case .rejected(let reasons):
                // Unreachable by the mertensVerdicts zero-rejection face —
                // kept as the typed honesty arm.
                throw AppError.invalidParameter(
                    "mertens source \(index) rejected: "
                        + reasons.joined(separator: "; "))
            }
        }

        // ── the alignment pass (the KD-3 helper; no NCC for brackets) ───
        let (shifts, labels, _, _) = try await runMTBAlignment(
            work, width: width, height: height, withNCC: false)

        let tier = MertensFusion.DeghostLevel.resolved(
            from: work.params.mertensDeghost)
        let levels = max(1, work.params.mertensLevels
            ?? MertensFusion.adaptiveLevels(minEdge: min(width, height)))
        let halo = MertensFusion.haloRows(levels: levels)

        // ── the stage pass: encode + deghost motion + staged pixels ─────
        let staging = StagedSet(count: work.decoded.count, width: width, height: height)
        defer { staging.cleanUp() }
        // The union motion accumulator (pre-dilation binary, merge.py :127)
        // and the reference-side precomputes — one plane each, freed after
        // the mask finalizes.
        var union: [Float]?
        var referenceGray: [Float]?
        var referenceBlur: [Float]?
        var referenceQuantiles: [Float] = []
        if tier != .off {
            union = [Float](repeating: 0, count: width * height)
        }
        for index in work.decoded.indices {
            let plane = try work.render.renderFullFloatRGBA(work.decoded[index].ciImage)
            mertensDisplayEncodeInPlace(plane)
            if tier != .off {
                let luma = mertensGrayFromPlane(plane)
                if index == 0 {
                    referenceGray = luma
                    referenceBlur = MertensFusion.gaussianBlurGray(
                        luma, width: width, height: height,
                        sigma: MertensFusion.residualBlurSigma)
                    let step = MertensFusion.decimationStep(width: width, height: height)
                    let sortedReference = stridedSorted(
                        luma, width: width, height: height, step: step)
                    referenceQuantiles = MertensFusion.linspace(2, 98, 33)
                        .map { MertensFusion.percentileOfSorted(sortedReference, $0) }
                } else {
                    accumulateMertensMotion(
                        luma, into: &union!, referenceGray: referenceGray!,
                        referenceBlur: referenceBlur!,
                        referenceQuantiles: referenceQuantiles,
                        tier: tier, width: width, height: height)
                }
            }
            try staging.writePixels(plane, index: index)
            await work.progress.step() // stage/encode step
            // The transient plane dies with the loop iteration.
        }

        // ── the mask finalization (merge.py :136-138 order: the union is
        // complete FIRST, then one dilate + one feather) → staged shared ─
        var softMask: [Float]?
        if tier != .off, union != nil {
            let radius = max(1, Int(
                (Float(tier.baseDilateRadius) * Float(max(width, height)) / 1800)
                    .rounded()))
            var dilated = mertensSeparableDilate(
                union!, radius: radius, width: width, height: height)
            dilated = MertensFusion.gaussianBlurGray(
                dilated, width: width, height: height,
                sigma: max(1, Float(radius) / 2))
            for pixel in dilated.indices {
                dilated[pixel] = min(max(dilated[pixel], 0), 1)
            }
            softMask = dilated
            try staging.writeMask(
                dilated.map { UInt8(($0 * 255).rounded()) })
        }
        union = nil
        referenceGray = nil
        referenceBlur = nil

        // ── the substitution LUTs (129 points/channel, static cells of the
        // FINAL mask — the staged pixels' decimation grid) ────────────────
        var luts: [[MertensFusion.ChannelLUT]] = []
        if tier != .off, let mask = softMask {
            let step = MertensFusion.decimationStep(width: width, height: height)
            // The static grid rides the 01 whole-frame face (the SAME
            // walk + the merge.py:145 degenerate fallback `static < 64 →
            // the whole grid counts as static` — the 01 checker minor-1
            // rule). The inline walk this replaces had NO fallback: an
            // all-motion mask would estimate over an empty sample set
            // (the percentile precondition crash) and a near-all-motion
            // one over a starved sample (silent divergence from the
            // reference).
            let (staticGrid, gridWidth, gridHeight, _) = MertensFusion
                .staticSampleMask(motion: mask, width: width, height: height)
            luts.reserveCapacity(work.decoded.count)
            for index in work.decoded.indices {
                luts.append(try mertensStageSubstituteLUTs(
                    staging: staging, width: width, height: height, step: step,
                    referenceIndex: 0, frameIndex: index,
                    staticGrid: staticGrid, gridWidth: gridWidth,
                    gridHeight: gridHeight))
            }
        }
        softMask = nil // the full-resolution mask never rides the fusion pass

        // ── the band-outer fusion (grid-aligned bands; the substitution
        // runs IN-PASS inside the provider) ──────────────────────────────
        var ghostUnion: [UInt8]? = tier != .off
            ? [UInt8](repeating: 0, count: width * height) : nil
        let outputPlane = try await mertensBandOuterFuse(
            staging: staging, width: width, height: height,
            sources: work.decoded.count, levels: levels, halo: halo,
            tier: tier, luts: luts, shifts: shifts,
            ghostUnion: &ghostUnion, progress: work.progress,
            bumpBudget: work.decoded.count)

        // The params snapshot carries the resolved Mertens record (the
        // 08-3 `pyramidLevels` precedent — provenance states what ran).
        var provenanceParams = work.params
        provenanceParams.mertensDeghost = tier.rawValue
        provenanceParams.mertensLevels = levels

        return try await landStackProduct(
            work, width: width, height: height, rgba: outputPlane,
            holeFraction: 0, alignmentLabels: labels, warnings: warnings,
            provenanceParams: provenanceParams,
            algorithmName: ProvenanceReplay.mertensAlgorithmName,
            implementationVersion: ProvenanceReplay.mertensImplementationVersion,
            exposureEVs: exposureEVs, ghostUnion: ghostUnion,
            productColorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    // MARK: - Mertens stage/fuse internals (T1; shared with the perf probe)

    /// In-place sRGB piecewise display encode over the plane's RGB channels
    /// (the curve clamps to [0,1] by construction — the 01 KD-1 convention;
    /// alpha rides through untouched). Bit-identical to
    /// `MertensFusion.displayEncodePlane` per element (the same curve
    /// function) without the full-plane array copy.
    nonisolated private static func mertensDisplayEncodeInPlace(
        _ plane: StackRenderedPlane
    ) {
        let floats = plane.pointer.bindMemory(to: Float.self, capacity: plane.width * plane.height * 4)
        for index in 0..<(plane.width * plane.height) {
            let base = index * 4
            for channel in 0..<3 {
                floats[base + channel] = Float(
                    DrtEotfMath.srgbPiecewiseEncode(Double(floats[base + channel])))
            }
        }
    }

    /// Rec709 luma straight off the rendered plane buffer (the
    /// `MertensFusion.grayPlane` math without the plane array copy).
    nonisolated private static func mertensGrayFromPlane(
        _ plane: StackRenderedPlane
    ) -> [Float] {
        let c = MertensFusion.grayCoefficients
        let pixelCount = plane.width * plane.height
        let floats = UnsafeRawBufferPointer(
            start: plane.pointer, count: plane.bytesPerRow * plane.height)
            .bindMemory(to: Float.self)
        var gray = [Float](repeating: 0, count: pixelCount)
        for index in 0..<pixelCount {
            let base = index * 4
            gray[index] = c.r * floats[base] + c.g * floats[base + 1]
                + c.b * floats[base + 2]
        }
        return gray
    }

    /// The sorted strided samples (`plane[::step, ::step]`, sorted) — the
    /// quantile input face shared by the motion + LUT passes.
    nonisolated private static func stridedSorted(
        _ plane: [Float], width: Int, height: Int, step: Int
    ) -> [Float] {
        MertensFusion.stridedSamples(plane, width: width, height: height, step: step)
            .sorted()
    }

    /// One frame's binary motion against the reference (merge.py :125-134
    /// verbatim decomposition: quantile brightness mapping → σ1.2 blur →
    /// absolute difference → threshold → the (0.015, 0.985) usable gate),
    /// MAX-accumulated into the union (the merge.py `np.maximum` fold).
    nonisolated private static func accumulateMertensMotion(
        _ luma: [Float], into union: inout [Float],
        referenceGray: [Float], referenceBlur: [Float],
        referenceQuantiles: [Float], tier: MertensFusion.DeghostLevel,
        width: Int, height: Int
    ) {
        let step = MertensFusion.decimationStep(width: width, height: height)
        let samples = stridedSorted(luma, width: width, height: height, step: step)
        let quantiles = MertensFusion.linspace(2, 98, 33)
        let values = quantiles.map { MertensFusion.percentileOfSorted(samples, $0) }
        let (unique, positions) = MertensFusion.uniqueWithFirstPositions(values)
        let mappedTargets = positions.map { referenceQuantiles[$0] }
        var mapped = [Float](repeating: 0, count: width * height)
        for pixel in mapped.indices {
            mapped[pixel] = MertensFusion.interp(
                luma[pixel], xs: unique, ys: mappedTargets)
        }
        let mappedBlur = MertensFusion.gaussianBlurGray(
            mapped, width: width, height: height,
            sigma: MertensFusion.residualBlurSigma)
        for pixel in union.indices {
            let usable = luma[pixel] > MertensFusion.usableGateLow
                && luma[pixel] < MertensFusion.usableGateHigh
                && referenceGray[pixel] > MertensFusion.usableGateLow
                && referenceGray[pixel] < MertensFusion.usableGateHigh
            if abs(mappedBlur[pixel] - referenceBlur[pixel]) > tier.residualThreshold,
               usable {
                union[pixel] = 1
            }
        }
    }

    /// Separable square max filter (horizontal pass then vertical pass,
    /// clamp edges) — output-IDENTICAL to `MertensFusion.dilate` (the max
    /// filter decomposes exactly over its two axes) at O(radius) per pixel
    /// per axis instead of O(radius²) per pixel: the production 100 MP
    /// dilate radius is 32-58 (tier-scaled), where the quadratic form is
    /// minutes and this form is seconds. The golden face stays untouched.
    nonisolated static func mertensSeparableDilate(
        _ plane: [Float], radius: Int, width: Int, height: Int
    ) -> [Float] {
        precondition(
            plane.count == width * height, "mertens dilate: plane size mismatch")
        let clampedRadius = max(0, radius)
        var horizontal = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                var maximum: Float = 0
                let lower = max(0, x - clampedRadius)
                let upper = min(width - 1, x + clampedRadius)
                for sx in lower...upper {
                    maximum = max(maximum, plane[row + sx])
                }
                horizontal[row + x] = maximum
            }
        }
        var out = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let lower = max(0, y - clampedRadius)
            let upper = min(height - 1, y + clampedRadius)
            for x in 0..<width {
                var maximum: Float = 0
                for sy in lower...upper {
                    maximum = max(maximum, horizontal[sy * width + x])
                }
                out[y * width + x] = maximum
            }
        }
        return out
    }

    /// The per-channel 129-point quantile LUTs estimated over the static
    /// cells of the decimation grid, reading ONLY the grid rows from the
    /// staged pixel files (merge.py :147-159 — `im[::step, ::step][static]`;
    /// the whole-frame `MertensFusion.substituteLUTs` face stays untouched).
    /// Sample order is grid order (y-major), the same walk the whole-frame
    /// face performs — the percentile multisets are order-independent.
    nonisolated static func mertensStageSubstituteLUTs(
        staging: StagedSet, width: Int, height: Int, step: Int,
        referenceIndex: Int, frameIndex: Int,
        staticGrid: [Bool], gridWidth: Int, gridHeight: Int
    ) throws -> [MertensFusion.ChannelLUT] {
        let quantiles = MertensFusion.linspace(0, 100, 129)
        var referenceRows = [[Float]](repeating: [], count: gridHeight)
        var frameRows = [[Float]](repeating: [], count: gridHeight)
        for gy in 0..<gridHeight {
            let y = min(gy * step, height - 1)
            referenceRows[gy] = try staging.readPixelRow(
                index: referenceIndex, row: y)
            frameRows[gy] = try staging.readPixelRow(index: frameIndex, row: y)
        }
        var luts: [MertensFusion.ChannelLUT] = []
        for channel in 0..<3 {
            var referenceSamples: [Float] = []
            var frameSamples: [Float] = []
            referenceSamples.reserveCapacity(staticGrid.count)
            frameSamples.reserveCapacity(staticGrid.count)
            for gy in 0..<gridHeight {
                for gx in 0..<gridWidth where staticGrid[gy * gridWidth + gx] {
                    let x = min(gx * step, width - 1)
                    let base = (x * 4) + channel
                    referenceSamples.append(referenceRows[gy][base])
                    frameSamples.append(frameRows[gy][base])
                }
            }
            let sortedReference = referenceSamples.sorted()
            let sortedFrame = frameSamples.sorted()
            let values = quantiles.map { MertensFusion.percentileOfSorted(sortedReference, $0) }
            let target = quantiles.map { MertensFusion.percentileOfSorted(sortedFrame, $0) }
            let (unique, positions) = MertensFusion.uniqueWithFirstPositions(values)
            luts.append(MertensFusion.ChannelLUT(
                xs: unique, ys: positions.map { target[$0] }))
        }
        return luts
    }

    /// The grid-aligned band list: band starts divisible by 2^(L−1) (the
    /// deepest reduce grid — the 01 DECISIONS §6 constraint that keeps the
    /// strip pyramids' decimation grids aligned with the frame grid), band
    /// heights rounded up to the same multiple (≈ the 256-row default).
    nonisolated static func mertensAlignedBands(
        height: Int, width: Int, levels: Int
    ) -> [TilingPlan.Tile] {
        guard height > 0, width > 0 else { return [] }
        let align = 1 << max(0, max(1, levels) - 1)
        let baseRows = BandStreamer.defaultBandHeight
        let bandRows = max(align, (baseRows + align - 1) / align * align)
        var result: [TilingPlan.Tile] = []
        var y = 0
        while y < height {
            result.append(TilingPlan.Tile(
                x: 0, y: y, width: width, height: min(bandRows, height - y)))
            y += bandRows
        }
        return result
    }

    /// The band-outer fusion driver (KD-1 ⑤⑥): per aligned band, the N
    /// shifted pixel strips + the shared mask band feed `fuseStrip` with
    /// the reference substitution running IN-PASS inside the provider
    /// (`prepared = strip·(1−α) + LUT(refStrip)·α`; the reference source
    /// rides untouched — merge.py :154). NaN out-of-overlap samples
    /// sanitize to 0 BEFORE the weights (the E³≈8.5e-5 natural suppression
    /// — the caller-side contract from the MertensFusion header). The
    /// fused band's rows copy into the RGBA output plane; the ghost union
    /// accumulates any band row the substitution actually touched (α > 0).
    /// Fuse-step progress is band-paced with the focus leg's bump budget.
    nonisolated static func mertensBandOuterFuse(
        staging: StagedSet, width: Int, height: Int,
        sources: Int, levels: Int, halo: Int,
        tier: MertensFusion.DeghostLevel,
        luts: [[MertensFusion.ChannelLUT]],
        shifts: [(dx: Int, dy: Int)],
        ghostUnion: inout [UInt8]?,
        progress: StackMergeProgress, bumpBudget: Int
    ) async throws -> [Float] {
        var outputPlane = [Float](repeating: 0, count: width * height * 4)
        var bumpBudget = bumpBudget
        for band in mertensAlignedBands(height: height, width: width, levels: levels) {
            let stripFirst = max(0, band.y - halo)
            let stripRows = min(height, band.y + band.height + halo) - stripFirst
            let maskBand: [UInt8]? = tier != .off
                ? try staging.readMaskBand(firstRow: stripFirst, rows: stripRows)
                : nil
            var maskStrip: [Float]?
            if let maskBand {
                maskStrip = maskBand.map { Float($0) / 255 }
            }
            let referenceStrip = sanitizedStrip(try staging.readShiftedPixels(
                index: 0, firstRow: stripFirst, rows: stripRows,
                dx: shifts[0].dx, dy: shifts[0].dy))
            // The provider contract is non-throwing (the 01 fuseStrip
            // face); the staged reads ride a captured error box — the
            // dummy strip only flows on the corrupted path, which throws
            // right after the fold returns.
            var readError: Error?
            let fused = MertensFusion.fuseStrip(
                width: width, height: stripRows, sources: sources,
                levels: levels) { sourceIndex in
                    do {
                        let strip = sanitizedStrip(try staging.readShiftedPixels(
                            index: sourceIndex, firstRow: stripFirst,
                            rows: stripRows,
                            dx: shifts[sourceIndex].dx, dy: shifts[sourceIndex].dy))
                        guard tier != .off, sourceIndex != 0,
                              let mask = maskStrip, !luts.isEmpty else {
                            return strip
                        }
                        return MertensFusion.applySubstitution(
                            original: strip, reference: referenceStrip,
                            motion: mask, luts: luts[sourceIndex],
                            width: width, height: stripRows)
                    } catch {
                        readError = error
                        return [Float](repeating: 0, count: stripRows * width * 4)
                    }
                }
            if let readError { throw readError }
            // Copy the band's rows (strip-local offset) into the output +
            // the ghost union (any pixel the substitution touched).
            let offsetInStrip = band.y - stripFirst
            for row in 0..<band.height {
                let sourceRow = offsetInStrip + row
                let destinationRow = band.y + row
                if let maskBand, ghostUnion != nil {
                    let unionRow = destinationRow * width
                    let maskRow = sourceRow * width
                    for x in 0..<width where maskBand[maskRow + x] > 0 {
                        ghostUnion![unionRow + x] = 1
                    }
                }
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
                await progress.step() // fuse step (band-paced)
            }
        }
        while bumpBudget > 0 {
            bumpBudget -= 1
            await progress.step() // pad to the declared total
        }
        return outputPlane
    }

    /// The staged-strip NaN sanitize (the MertensFusion header contract):
    /// out-of-alignment-overlap samples read NaN and become 0 — the black
    /// code carries the near-zero E³≈8.5e-5 weight (the 01 G3③ constant),
    /// so no explicit weight gating is needed.
    nonisolated private static func sanitizedStrip(
        _ strip: [Float]
    ) -> [Float] {
        var strip = strip
        for index in strip.indices where strip[index].isNaN {
            strip[index] = 0
        }
        return strip
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
            provenance: provenance,
            // M6-2-01 T4 (KD-7 ③④): the merge product is a NEW document —
            // its birth sidecar stamps the current process generation.
            process: .current)
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
    /// aperture stays STRICT) + the MTB alignment pass (delegated to
    /// `runMTBAlignment` — the Plan M5-2-02 KD-3 behavior-preserving
    /// extraction; the precheck stays HERE because the Mertens bracket runs
    /// EV-free and must never see the aperture-strict stack precheck).
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
        return try await runMTBAlignment(
            work, width: width, height: height, withNCC: withNCC)
    }

    /// The MTB alignment pass (Plan M5-2-02 KD-3): the 08-1 T2 body extracted
    /// VERBATIM from `runStackPrecheckAndAlignment` (behavior-preserving —
    /// the existing focus/stack/HDR tests are the zero-diff witness) so the
    /// Mertens leg can ride the same alignment vocabulary (labels + the
    /// align-step bump duty) WITHOUT the stack precheck (OQ-5: the Mertens
    /// bracket is EV-free, aperture differences are warnings at most).
    /// `withNCC` = the focus leg's scale-drift self-check; NCC is meaningless
    /// for exposure brackets (same framing), so Mertens passes false.
    nonisolated private static func runMTBAlignment(
        _ work: StackMergeWork, width: Int, height: Int, withNCC: Bool
    ) async throws -> (shifts: [(dx: Int, dy: Int)], labels: [String],
                       warnings: [String], nccMin: Double) {
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
    ///
    /// Plan M5-2-02 KD-4 additive arms — every new parameter defaults nil
    /// and the nil path is BYTE-IDENTICAL to the pre-M5-2-02 behavior (the
    /// pinned negative test):
    ///   • `exposureEVs` — non-nil = the per-source provenance EVs (the
    ///     Mertens verdicts; OQ-5 "EV 有则记 provenance 不消费"); nil = the
    ///     stack-family flat-zero per source.
    ///   • `ghostUnion` — non-nil AND containing 1 = the runHDRLeg tail
    ///     shape (dilate + the Ghost Suppression layer stack; the Mertens
    ///     mask semantics = the substitution mask); nil = no mask, nil
    ///     layer stack.
    ///   • `implementationVersion` — non-nil = the algorithm-specific
    ///     version constant (the Mertens identity is independent of the
    ///     Robertson02 one); nil = the historical HDR version (the stack
    ///     legs' existing value).
    ///   • `productColorSpace` (T2, KD-2) — non-nil = the product TIFF's
    ///     embedded color space tag; nil = the working space (zero drift).
    ///   • `rowProvider` (Plan M5-3-02 KD-9) — non-nil = the ROW-BAND
    ///     landing: the provider streams (crop-region) RGBA rows band by
    ///     band into the `FloatTIFFWriter` (the full plane NEVER rides
    ///     memory — the pano red line); nil = the `writeFloatTIFF` full-
    ///     plane path, BYTE-IDENTICAL to the pre-M5-3-02 behavior (the
    ///     existing legs' tests are the pinned negative witness).
    nonisolated private static func landStackProduct(
        _ work: StackMergeWork, width: Int, height: Int, rgba: [Float],
        holeFraction: Float, alignmentLabels: [String], warnings: [String],
        provenanceParams: StackMergeService.MergeParams, algorithmName: String,
        implementationVersion: String? = nil,
        exposureEVs: [Double]? = nil,
        ghostUnion: [UInt8]? = nil,
        productColorSpace: CGColorSpace? = nil,
        rowProvider: ((_ firstRow: Int, _ rowCount: Int) async throws -> [Float])? = nil
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
        if let rowProvider {
            let writer = try BandStreamer.FloatTIFFWriter(
                width: width, height: height, destination: productURL,
                colorSpace: productColorSpace ?? WorkingSpace.colorSpace)
            var firstRow = 0
            while firstRow < height {
                let rowCount = min(BandStreamer.defaultBandHeight, height - firstRow)
                let band = try await rowProvider(firstRow, rowCount)
                guard band.count == rowCount * width * 4 else {
                    throw AppError.encodeFailed(
                        "rowProvider band size mismatch: \(band.count) floats"
                            + " for \(rowCount)×\(width)")
                }
                try writer.write(rows: band)
                firstRow += rowCount
            }
            try writer.finish()
        } else {
            try BandStreamer.writeFloatTIFF(
                rgba, width: width, height: height, to: productURL,
                colorSpace: productColorSpace ?? WorkingSpace.colorSpace)
        }
        await work.progress.step() // write step

        // The ghost mask (the runHDRLeg tail shape — the additive
        // `ghostUnion` arm; NOTHING lands when nil or all-zero).
        var landedMask: GhostMaskWriter.LandedMask?
        if let union = ghostUnion, union.contains(1) {
            let dilated = GhostMaskWriter.dilate(
                union, width: width, height: height)
            landedMask = try GhostMaskWriter.land(
                dilated, width: width, height: height,
                productURL: productURL, maskID: UUID())
        }

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
                // Stacks carry no exposure weighting — the EV is a
                // flat zero for every source; the Mertens arm records
                // its composed verdicts (recorded, never consumed).
                return SidecarProvenance.Source(
                    relPath: relPath, stableHash: hash,
                    exposureEV: exposureEVs?[index] ?? 0)
            }
        let provenance = SidecarProvenance(
            kind: work.kind.provenanceKind,
            algorithm: SidecarProvenance.Algorithm(
                name: algorithmName,
                implementationVersion: implementationVersion
                    ?? ProvenanceReplay.hdrImplementationVersion,
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
            layerStack: GhostMaskWriter.ghostSuppressionLayerStack(landedMask),
            provenance: provenance,
            // M6-2-01 T4 (KD-7 ③④): the merge product is a NEW document —
            // its birth sidecar stamps the current process generation.
            process: .current)
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
            ghostMask: landedMask,
            exposureEVs: exposureEVs ?? [],
            warnings: warnings)
    }

    /// The staged-files working set (the temp-dir cleanup discipline: the
    /// whole directory dies with the leg — error paths included, via the
    /// caller's `defer`). Plan M5-2-02: the nested type widened private →
    /// internal (the 01 KD-2 one-line access precedent) so the perf probe
    /// can drive the REAL band-outer fusion face; zero behavior change.
    struct StagedSet {
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
        /// The SHARED soft mask (the Mertens deghost union — one channel
        /// for the whole set, UInt8 1 B/px; the per-source split would
        /// double-count: merge.py's motion mask is a single union plane).
        fileprivate func maskURL() -> URL {
            directory.appendingPathComponent("mask.u8")
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

        /// Stream the SHARED soft mask to the staged file (KD-1's mask byte
        /// channel; UInt8 [0,255] quantized, 1 B/px on disk).
        func writeMask(_ bytes: [UInt8]) throws {
            FileManager.default.createFile(atPath: maskURL().path, contents: nil)
            let handle = try FileHandle(forWritingTo: maskURL())
            defer { try? handle.close() }
            let rowsPerChunk = 512
            var y = 0
            while y < height {
                let rows = min(rowsPerChunk, height - y)
                try handle.write(contentsOf: Data(
                    bytes[y * width..<((y + rows) * width)]))
                y += rows
            }
        }

        /// The soft-mask band read — NO shift (the mask lives in the
        /// reference/output frame; the substitution α does not ride the
        /// MTB shift). Out-of-frame rows read 0.
        func readMaskBand(firstRow: Int, rows: Int) throws -> [UInt8] {
            var result = [UInt8](repeating: 0, count: rows * width)
            let sourceFirst = max(0, firstRow)
            let sourceLast = min(height, firstRow + rows) // exclusive
            guard sourceLast > sourceFirst else { return result }
            let handle = try FileHandle(forReadingFrom: maskURL())
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(sourceFirst * width))
            let want = (sourceLast - sourceFirst) * width
            guard let data = try handle.read(upToCount: want), data.count == want
            else {
                throw AppError.fileUnreadable("staged mask truncated")
            }
            result.withUnsafeMutableBytes { raw in
                data.withUnsafeBytes { raw.copyBytes(from: $0) }
            }
            return result
        }

        /// One FULL-WIDTH row band, NO shift (Plan M5-3-02 KD-1: the pano
        /// tile gather's row source — the pano displacement is a continuous
        /// warp, so the integer-shift `readShiftedPixels` face does not
        /// apply). `bytesPerRow` nil = the set's uniform width stride (the
        /// byte-identical default); the pano leg passes each source's own
        /// stride (mixed source sizes are legal — the KD-10 no-extent-gate
        /// posture). Rows outside the set's height zero-fill (the
        /// readMaskBand shape).
        ///
        /// The `into` variant (the probe-round finding) reads into the
        /// CALLER's reusable buffer — the fusion walk churns hundreds of
        /// multi-MB row spans per band, and fresh large allocations put
        /// the resident footprint on a monotonic climb (libmalloc's freed
        /// large blocks stay resident — the probe-pinned 10 GB-per-4-bands
        /// growth) where one grown-once buffer keeps the working set flat.
        /// Returns the float count actually filled (prefix of the buffer).
        func readRows(
            index: Int, firstRow: Int, rows: Int, bytesPerRow: Int? = nil,
            into buffer: inout [Float]
        ) throws -> Int {
            let strideBytes = bytesPerRow ?? width * 16
            let floatsPerRow = strideBytes / 4
            let wantFloats = max(0, rows) * floatsPerRow
            if buffer.count < wantFloats {
                buffer = [Float](repeating: 0, count: wantFloats)
            }
            guard rows > 0 else { return 0 }
            let sourceFirst = max(0, firstRow)
            let sourceLast = min(height, firstRow + rows) // exclusive
            guard sourceLast > sourceFirst else { return 0 }
            let handle = try FileHandle(forReadingFrom: pixelsURL(index))
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(sourceFirst * strideBytes))
            let want = (sourceLast - sourceFirst) * strideBytes
            guard let data = try handle.read(upToCount: want),
                  data.count == want
            else {
                throw AppError.fileUnreadable("staged pixels rows truncated")
            }
            let filled = (sourceLast - sourceFirst) * floatsPerRow
            let destinationRow0 = sourceFirst - firstRow
            buffer.withUnsafeMutableBytes { raw in
                data.withUnsafeBytes { stagedRaw in
                    raw.baseAddress!
                        .advanced(by: destinationRow0 * strideBytes)
                        .copyMemory(
                            from: stagedRaw.baseAddress!, byteCount: want)
                }
            }
            return filled
        }

        func readRows(
            index: Int, firstRow: Int, rows: Int, bytesPerRow: Int? = nil
        ) throws -> [Float] {
            let strideBytes = bytesPerRow ?? width * 16
            precondition(
                strideBytes > 0 && strideBytes % 4 == 0,
                "row stride must be positive and float-aligned")
            let floatsPerRow = strideBytes / 4
            var result = [Float](
                repeating: 0, count: max(0, rows) * floatsPerRow)
            guard rows > 0 else { return result }
            let sourceFirst = max(0, firstRow)
            let sourceLast = min(height, firstRow + rows) // exclusive
            guard sourceLast > sourceFirst else { return result }
            let handle = try FileHandle(forReadingFrom: pixelsURL(index))
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(sourceFirst * strideBytes))
            let want = (sourceLast - sourceFirst) * strideBytes
            guard let data = try handle.read(upToCount: want),
                  data.count == want
            else {
                throw AppError.fileUnreadable("staged pixels rows truncated")
            }
            result.withUnsafeMutableBytes { raw in
                data.withUnsafeBytes { stagedRaw in
                    let destinationRow0 = sourceFirst - firstRow
                    raw.baseAddress!
                        .advanced(by: destinationRow0 * strideBytes)
                        .copyMemory(
                            from: stagedRaw.baseAddress!, byteCount: want)
                }
            }
            return result
        }

        /// One staged pixel row, unshifted (the substitution-LUT grid pass
        /// reads ONLY the decimation rows — `plane[::step, ::step]` needs
        /// whole rows, not the grid cells' scattered addresses).
        func readPixelRow(index: Int, row: Int) throws -> [Float] {
            var result = [Float](repeating: 0, count: width * 4)
            guard row >= 0, row < height else { return result }
            let handle = try FileHandle(forReadingFrom: pixelsURL(index))
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(row * width * 16))
            let want = width * 16
            guard let data = try handle.read(upToCount: want), data.count == want
            else {
                throw AppError.fileUnreadable("staged pixels row truncated")
            }
            result.withUnsafeMutableBytes { raw in
                data.withUnsafeBytes { raw.copyBytes(from: $0) }
            }
            return result
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
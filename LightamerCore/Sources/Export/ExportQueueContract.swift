import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ExportQueue contract skeleton (Plan 11-01 T3, EXP-06's CONTRACT face — the
// actor implementation lands in 11-04; nothing here runs a queue).
//
// Structural twin of the 9-3 SessionThumbnailProvider face
// (SessionThumbnailProvider.swift:107-310): generation-cancel + bounded
// concurrency + injected test legs — with the export deltas from RESEARCH
// §4.1: NO idle-delay/visible-jump scheduling (throughput, not interactive),
// concurrency locked to 1, and a two-layer progress snapshot.
//
// Placement correction (recorded in 11-01-DECISIONS D1): this contract lives
// in Core, NOT the RESEARCH §4.1 literal "App/State layer" — LightamerTests
// only imports Core (the 02-05 red line), and the 9-3 queue skeleton itself
// already lives in Core. The actor body (11-04) may still be wired App-side
// without moving these types.
// ─────────────────────────────────────────────────────────────────────────────

/// One export job's lifecycle state (RESEARCH §4.1):
/// `pending → rendering → encoding → done(URL) / failed(AppError) /
/// cancelled`.
///
/// Illegal transitions are made UNREACHABLE two ways: (a) `canTransition`
/// switches exhaustively per source case with NO `default` — adding a new
/// case is a compile error until its row is authored; (b) the 11-04 actor
/// guards every mutation through `canTransition` and asserts (the vector
/// table lives in ExportQueueContractTests). Terminal states never transition.
public enum ExportJobState: Sendable {

    /// Queued, not yet started.
    case pending

    /// The render leg is running (full-res EXPORT pipe).
    case rendering

    /// The encode leg is running (quantize + format encode + atomic promote).
    case encoding

    /// Terminal: the file is on disk at this URL.
    case done(URL)

    /// Terminal: the leg threw; `AppError` carries the typed cause
    /// (RESEARCH §4.1: NO automatic retry — explicit `retry(jobID)` re-queues).
    case failed(AppError)

    /// Terminal: cancelled while pending or in flight (in-flight results are
    /// DISCARDED at the generation gate — never partially written).
    case cancelled

    /// The legal-transition table (exhaustive, no `default` — see header).
    public func canTransition(to next: ExportJobState) -> Bool {
        switch self {
        case .pending:
            switch next {
            case .rendering, .cancelled: return true
            case .pending, .encoding, .done, .failed: return false
            }
        case .rendering:
            switch next {
            case .encoding, .failed, .cancelled: return true
            // `.rendering` = the SELF case: not a legal transition (the old
            // `default:` branch covered it; db8fa32's explicit-list fix
            // dropped it and broke the build — exhaustiveness needs all six
            // target cases listed, self included).
            case .pending, .done, .rendering: return false
            }
        case .encoding:
            switch next {
            case .done, .failed, .cancelled: return true
            case .pending, .rendering, .encoding: return false
            }
        case .done, .failed, .cancelled:
            return false // terminal — nothing leaves a terminal state
        }
    }

    /// Terminal states (no outgoing edges).
    public var isTerminal: Bool {
        switch self {
        case .done, .failed, .cancelled: return true
        case .pending, .rendering, .encoding: return false
        }
    }
}

/// The UI-facing per-job snapshot: a Sendable VALUE copied out of the
/// 11-04 actor (the actor-private `ExportJob` additionally carries the
/// document payload — instances + layer stack — which never crosses this
/// contract). Shape per Plan 11-01 T3 / RESEARCH §4.1.
public struct ExportJobSnapshot: Sendable {

    /// Stable job identity (queue-scoped).
    public let id: UUID

    /// The source image file.
    public let imageURL: URL

    /// The session-relative path of `imageURL` (the 9-3 `relPath` twin).
    public let relPath: String

    /// The variant(s) this job exports (N variants → N jobs per EXP-07; the
    /// array shape follows the Plan contract verbatim — 11-04 may carry a
    /// single element per job).
    public let variants: [ExportVariant]

    /// FIFO arrival order (export has NO visible-first jump — RESEARCH §4.1).
    public let seq: Int

    /// The cancel epoch this job belongs to (`cancelAll` bumps it; results
    /// from stale generations are discarded before they reach a waiter).
    public let generation: Int

    /// The job's current lifecycle state.
    public let state: ExportJobState

    public init(
        id: UUID,
        imageURL: URL,
        relPath: String,
        variants: [ExportVariant],
        seq: Int,
        generation: Int,
        state: ExportJobState
    ) {
        self.id = id
        self.imageURL = imageURL
        self.relPath = relPath
        self.variants = variants
        self.seq = seq
        self.generation = generation
        self.state = state
    }
}

/// Which leg the in-flight job is currently inside (job-layer progress —
/// RESEARCH §4.1: NO intra-render percentage is promised; a single pipe
/// call has no progress points).
public enum ExportJobPhase: Sendable {
    case rendering
    case encoding
}

/// The two-layer progress snapshot (RESEARCH §4.1): queue-level
/// `done/total` (N variants → N jobs count into total) + the in-flight
/// job's coarse phase. Sendable — crosses to the UI through ExportState.
public struct ExportProgress: Sendable {

    /// Jobs that reached a terminal state (done + failed + cancelled count
    /// as settled; UI differentiates via the snapshot list).
    public let done: Int

    /// Total jobs the queue action fanned out to.
    public let total: Int

    /// The in-flight job's phase; nil when the queue is idle.
    public let activePhase: ExportJobPhase?

    public init(done: Int, total: Int, activePhase: ExportJobPhase? = nil) {
        self.done = done
        self.total = total
        self.activePhase = activePhase
    }
}

/// The per-job request context the queue hands its render leg at DEQUEUE
/// time (11-04): the landing zone + the occupancy snapshot enumerated at
/// that instant (the 11-03 E2E collision lesson — occupancy must be read at
/// execution time, not enqueue time) + the optional live-records override.
/// Not part of the UI snapshot — this is leg-internal plumbing.
public struct ExportJobContext: Sendable {

    /// The variant's landing directory (EXP-08 default = Session/Output/,
    /// user-selectable — the App layer decides at enqueue).
    public let destinationDirectory: URL

    /// File names ALREADY occupied there, enumerated by the queue at
    /// dequeue via its `occupiedNamesProvider`.
    public let occupiedNames: Set<String>

    /// `nil` = the renderer reads the DISK SIDECAR (the truth); non-nil =
    /// explicit records (the live-edit export face).
    public let instancesOverride: [ModuleInstance]?

    /// Reserved provenance face (TIFF Software tag; nil = omit).
    public let editorSignature: String?

    public init(
        destinationDirectory: URL,
        occupiedNames: Set<String>,
        instancesOverride: [ModuleInstance]? = nil,
        editorSignature: String? = nil
    ) {
        self.destinationDirectory = destinationDirectory
        self.occupiedNames = occupiedNames
        self.instancesOverride = instancesOverride
        self.editorSignature = editorSignature
    }
}

/// The render→encode handoff payload. The synthetic face (11-01 D3) stays:
/// queue-semantics tests pass tokens only. The 11-04 REAL fill is the
/// `stage` payload — the quantized plane the render leg produced plus the
/// encode-stage inputs (name/colorspace/dpi already resolved at the render
/// boundary, so a cancelled job between the legs leaves NOTHING on disk).
public struct ExportRenderArtifact: Sendable, Hashable {

    /// Opaque identity token — synthetic in tests, `job.seq` in the real
    /// wiring.
    public let token: Int

    /// The plane dimensions the render leg produced (real wiring: the
    /// targetSize result; tests: any synthetic value).
    public let width: Int
    public let height: Int

    /// The real render-stage payload (nil = synthetic token mode, tests).
    public let stage: ExportRenderStage?

    public init(token: Int, width: Int, height: Int, stage: ExportRenderStage? = nil) {
        self.token = token
        self.width = width
        self.height = height
        self.stage = stage
    }

    // Hashability stays on the CHEAP identity face — the stage payload can
    // carry gigabytes of plane data (100MP float32); hashing it would be a
    // multi-second stall on a pure identity comparison.
    public static func == (lhs: ExportRenderArtifact, rhs: ExportRenderArtifact) -> Bool {
        lhs.token == rhs.token && lhs.width == rhs.width && lhs.height == rhs.height
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(token)
        hasher.combine(width)
        hasher.combine(height)
    }
}

/// The real render→encode handoff (11-04 D3 fill). `CGColorSpace` is a
/// thread-safe CF type without a compiler Sendable annotation — the
/// `@unchecked` boundary cost is ≈0 (the RESEARCH §1 posture). Hashability
/// is deliberately NOT synthesized: the plane data is huge and identity
/// lives in the artifact's token face.
public struct ExportRenderStage: @unchecked Sendable {

    /// The quantized plane (D-11-CONTEXT-7 tiers) the render leg produced.
    public let plane: ExportQuantizedPlane

    /// The format spec the encode stage encodes with (the variant's
    /// format face rides the boundary with its plane).
    public let formatSpec: ExportFormatSpec

    /// The color space the plane samples are ALREADY in (the export
    /// target — E3 identity-pass discipline).
    public let targetColorSpace: CGColorSpace

    /// The DPI the encoder writes into the file metadata.
    public let dpi: Double

    /// The collision-free destination the render stage NAMED (via
    /// `ExportNamer`, against the context's occupancy snapshot).
    public let destination: URL

    /// The source image (the EXIF round-trip carrier).
    public let sourceURL: URL

    /// The provenance face (TIFF Software tag; nil = omit).
    public let editorSignature: String?

    public init(
        plane: ExportQuantizedPlane, formatSpec: ExportFormatSpec,
        targetColorSpace: CGColorSpace, dpi: Double,
        destination: URL, sourceURL: URL, editorSignature: String?
    ) {
        self.plane = plane
        self.formatSpec = formatSpec
        self.targetColorSpace = targetColorSpace
        self.dpi = dpi
        self.destination = destination
        self.sourceURL = sourceURL
        self.editorSignature = editorSignature
    }
}

/// The injected render leg (the `ThumbnailRenderLeg` twin): snapshot +
/// context → full-res rendered artifact. The DEFAULT implementation wraps
/// the 11-03 `ExportRenderer.renderStage` (real EXPORT pipe + exit
/// conversion + quantize); queue tests inject an async no-op so
/// CANCELLATION/GATE/ORDER tests run in milliseconds.
public typealias ExportRenderLeg = @Sendable (
    _ snapshot: ExportJobSnapshot, _ context: ExportJobContext
) async throws -> ExportRenderArtifact

/// The injected encode leg (test seam): artifact + variant → the written
/// file URL. The real leg quantizes, encodes (CGImageDestination or
/// libwebp), and atomically promotes from tmp (L009 discipline); tests
/// return a synthetic URL without touching disk.
public typealias ExportEncodeLeg = @Sendable (
    _ artifact: ExportRenderArtifact, _ variant: ExportVariant
) async throws -> URL

/// The queue-wide constants (the D-11-CONTEXT-2 derivation, pinned where
/// the 11-04 actor will consume them).
public enum ExportQueueContract {

    /// The worker width: EXACTLY ONE job at a time. NOT laziness — the
    /// memory red line: a full-res float32 working plane is ≈1.6 GB at
    /// 100 MP; with pipe intermediates and the exit bitmap a single job
    /// peaks ≈5 GB (RESEARCH §4.5), so two concurrent jobs break the
    /// budget. Phase 15 may revisit with measurement; the constant stays
    /// named so tuning is a one-line diff.
    public static let concurrency = 1

    /// OQ-11-8 interface slot — NOT implemented in v1 (fixed Utility QoS +
    /// concurrency 1 per the DISCUSSION-LOG verdict). Phase 15 wires
    /// "editor active → pump pause" here IF measurement shows export
    /// starving the editor GPU; the named seam lets ExportState/UI reference
    /// the concept without re-deriving it. Kept as a constant (not a
    /// callable) so nothing can accidentally depend on behavior that does
    /// not exist yet.
    public static let yieldsToEditor = false
}

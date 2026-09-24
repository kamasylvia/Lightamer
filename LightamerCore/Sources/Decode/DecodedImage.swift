import CoreImage

/// The product of `RAWDecoder.decode(_:)` (D-21) — a display-ready `CIImage`
/// plus the three D-23 metadata classes and the decoder-version stamp.
///
/// Phase 1: `ciImage` is handed straight to the render path (Plan 03
/// `CIContextPool` → `EditorMTKView`). Phase 2 feeds it into the linear
/// pixelpipe instead. `Sendable` value type — crosses the module boundary to
/// the app's `EditorState` and to `LightamerTests`. (Not `Codable` — the
/// pixel payload is not serializable; the metadata members are.)
public struct DecodedImage: Sendable {

    /// The decoded image. Display-ready as-is for Phase 1 (CIRAW output is
    /// already tone-mapped for screen); the pixelpipe input in Phase 2.
    public let ciImage: CIImage

    /// RAW technical params (D-23b). Defaults for raster inputs — they carry
    /// no RAW technical state.
    public let rawTech: RAWTechnicalParams

    /// Capture metadata (D-23a — EXIF/IPTC/XMP).
    public let capture: CaptureMetadata

    /// Embedded semantic sky matte (D-23c). iPhone ProRAW only (L004) —
    /// silently nil for DSLR/mirrorless files.
    /// Phase 7: richer SegmentationMatte type (skin/hair/glasses/teeth) —
    /// CIRAWFilter exposes those mattes too; reserved until then.
    public let segmentationSkyMatte: CIImage?

    /// Which CIRAW decoder produced `ciImage` (D-22). Stamp into sidecars
    /// from day one (Phase 2 sidecar field reservation — RESEARCH §2
    /// DECISION REVIEW): RAW 9 silently changes output vs RAW 8, so the
    /// sidecar must record what happened. `.v8` for raster inputs (n/a).
    public let decoderVersionUsed: DecoderVersion

    /// GUI-22 (2026-09-24): the SOURCE FILE fingerprint (path ⊕ size ⊕
    /// mtime, StableHash) — the content identity the CI input-plane render
    /// memo dedupes on (a re-decode of the same file must reuse the frozen
    /// first render; CIRAW re-execution is speckle-nondeterministic).
    /// nil for in-memory/synthetic images (tests) — those dedupe on the
    /// CIImage identity instead, never on (decodeParams, imageID) — two
    /// different synthetic images can share both (the RetouchParity
    /// collision the first cut shipped).
    public let contentDedupeID: UInt64?

    public enum DecoderVersion: String, Codable, Sendable {
        case v8
        case v9
    }

    public init(
        ciImage: CIImage,
        rawTech: RAWTechnicalParams,
        capture: CaptureMetadata,
        segmentationSkyMatte: CIImage?,
        decoderVersionUsed: DecoderVersion,
        contentDedupeID: UInt64? = nil
    ) {
        self.ciImage = ciImage
        self.rawTech = rawTech
        self.capture = capture
        self.segmentationSkyMatte = segmentationSkyMatte
        self.decoderVersionUsed = decoderVersionUsed
        self.contentDedupeID = contentDedupeID
    }
}

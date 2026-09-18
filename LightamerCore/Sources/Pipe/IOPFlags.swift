/// Capability flags for an `IOPModule` — the port of Darktable's
/// `IOP_FLAGS_*` bitfield (`src/iop/imageop.h:84-110`).
///
/// Phase 1: declaration only. Phase 2+ the pixelpipe consults these when
/// scheduling (tiling eligibility, fast-pipe preview, reordering bounds).
/// Flag BIT POSITIONS are stable forever once sidecars ship (Phase 2):
/// they ride along in serialized history entries, exactly as Darktable's do.
public struct IOPFlags: OptionSet, Sendable {

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Module supports the blend framework (per-module masks / blending).
    /// (`IOP_FLAGS_SUPPORTS_BLENDING`)
    public static let supportsBlending = IOPFlags(rawValue: 1 << 0)

    /// Module can run on tiles (sub-ROI) — tiling framework is Phase 2 (D-20).
    /// (`IOP_FLAGS_ALLOW_TILING`)
    public static let allowTiling = IOPFlags(rawValue: 1 << 1)

    /// Only one instance of this module may be active in a pipe.
    /// (`IOP_FLAGS_ONE_INSTANCE`)
    public static let oneInstance = IOPFlags(rawValue: 1 << 2)

    /// Module cannot be reordered past (fence — e.g. the colorspace terminal
    /// trio). (`IOP_FLAGS_FENCE`)
    public static let fence = IOPFlags(rawValue: 1 << 3)

    /// Module writes detail to the history/sidecar beyond params.
    /// (`IOP_FLAGS_WRITE_DETAILS`)
    public static let writeDetails = IOPFlags(rawValue: 1 << 4)

    /// Module participates in the low-res fast preview pipe.
    /// (`IOP_FLAGS_ALLOW_FAST_PIPE`)
    public static let allowFastPipe = IOPFlags(rawValue: 1 << 5)
}

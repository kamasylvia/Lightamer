import Foundation

/// The pixelpipe resolution buckets (02-RESEARCH §2.1; Darktable
/// `pixelpipe.h:41-62` FULL/PREVIEW/THUMBNAIL/EXPORT analog) — one pipe
/// instance + one cache-key namespace per case (`PipeCacheKey.pipeType`).
///
/// `public` (cross-module): the coordinator (Plan 02-03) selects the
/// resolution per run; `Codable` for the sidecar-adjacent state it
/// persists later.
///
/// **The four-pipe lifecycle table (02-RESEARCH §2.1, D-C3) — implemented
/// across `PipeResolution` + `PixelPipe` + the app `PipeCoordinator`:**
///
/// | Pipe      | Resolution                                            | Creation / drive                       | Invalidation coupling                        |
/// |-----------|-------------------------------------------------------|----------------------------------------|----------------------------------------------|
/// | preview   | `min(drawable×2, 2560)` long edge, D-C3 ladder bucket | load → render immediately; always warm | params change → re-render NOW; bucket cross → re-render |
/// | thumbnail | `defaultLongEdge` = 360 fixed                         | LAZY: `isLazy`; dirty on params, rendered on next fetch (Phase 9 browser) | params change → `isDirty = true` only |
/// | full      | scale 1.0 full extent                                 | on-demand ONLY (`PixelPipe.runOnce`; tests / Phase 4 zoom) | params change → never auto-renders |
/// | export    | export target size (Phase 11)                         | reserved stub — runs throw `.notImplemented` | none (no caching at all) |
public enum PipeResolution: String, Codable, Sendable, CaseIterable {

    /// Interactive workhorse — `min(drawableSize×2, 2560px)` long edge,
    /// quantized to the 360px ladder (D-C3, `PreviewBucket`). Always-current.
    case preview

    /// Fixed 360px browser strip (Phase 9 consumer). Rendered once, kept.
    case thumbnail

    /// scale-1.0 full extent — on-demand (100% view / export pre-pass).
    /// Short-lived: intermediates ping-pong uncached.
    case full

    /// Phase 11 target-size run — no caching (Darktable parity:
    /// `pixelpipe_hb.h:346-355` — export/thumbnail pipes build no history
    /// cache; thumbnail IS cached here, export is not).
    case export

    /// Per-pipeType intermediate-caching policy (02-02 checkpoint lock #4).
    /// PREVIEW/THUMBNAIL cache every module output plane (~70MB/plane at
    /// 2560px float32); FULL must NOT (spike-b §4: a 100MP float32 plane is
    /// 1.55GB — three concurrent planes ≈ 4.7GB, over the 4GB session
    /// budget), EXPORT caches nothing at all.
    public var cachesIntermediatePlanes: Bool {
        switch self {
        case .preview, .thumbnail: return true
        case .full, .export: return false
        }
    }

    /// THUMBNAIL dirty-lifecycle flag: a lazy pipe is not re-rendered on
    /// param change — it is marked dirty and rebuilt on next fetch, which
    /// `PipeCache` provides for free (new keys miss, old planes stay until
    /// evicted). Consumed by `PixelPipe.runIfDirty` and mirrored by the
    /// app coordinator's thumbnail flag.
    public var isLazy: Bool {
        self == .thumbnail
    }

    /// The fixed input-plane long edge a resolution renders at (nil = the
    /// ROI decides — PREVIEW follows the D-C3 bucket, FULL renders scale
    /// 1.0). Only THUMBNAIL carries a constant: 360px (D-C3).
    public var defaultLongEdge: Int? {
        switch self {
        case .thumbnail: return 360
        case .preview, .full, .export: return nil
        }
    }
}

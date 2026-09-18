import Foundation

/// The pixelpipe resolution buckets (02-RESEARCH §2.1; Darktable
/// `pixelpipe.h:41-62` FULL/PREVIEW/THUMBNAIL/EXPORT analog) — one pipe
/// instance + one cache-key namespace per case (`PipeCacheKey.pipeType`).
///
/// `public` (cross-module): Plan 02-03 grows the pipe lifecycle around it;
/// `Codable` for the sidecar-adjacent state the coordinator persists later.
public enum PipeResolution: String, Codable, Sendable, CaseIterable {

    /// Interactive workhorse — `min(drawableSize×2, 2560px)` long edge,
    /// quantized to the 360px ladder (D-C3). Always-current.
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

    /// THUMBNAIL dirty-lifecycle flag (Plan 02-03 consumes): a lazy pipe is
    /// not re-rendered on param change — it is marked dirty and rebuilt on
    /// next fetch, which `PipeCache.texture(for:make:)` provides for free
    /// (new keys miss, old planes stay until evicted).
    public var isLazy: Bool {
        self == .thumbnail
    }
}

/// One pipe-cache line's identity — the Swift translation of Darktable's
/// cache-line hash (`pixelpipe_cache.c:99-172`), simplified to a dictionary
/// key (02-02 checkpoint lock #3). **Internal + in-memory only**: the key is
/// never persisted; the persisted hashes are `paramsHash`/`upstreamHash`
/// (StableHash-based). Synthesized `Hashable` is therefore legal here even
/// though Swift `Hasher` is banned across persistence boundaries (the ban
/// covers bytes that leave the process — this struct never does).
internal struct PipeCacheKey: Hashable {

    /// Per-image namespace (sidecar-persisted UUID; D-C1 cleanup keys on it).
    let imageID: UUID

    /// Resolution bucket (Darktable `pipe->type`).
    let pipeType: PipeResolution

    /// Chain index — position in the piece array, NOT iop_order
    /// (`pixelpipe_cache.c:113` note). Position 0 = the input plane.
    let position: Int

    /// FNV-1a chain over `decodeParamsHash` + every ENABLED piece's
    /// `paramsHash` at positions < `position`. A param change at module m
    /// flips `upstreamHash` for all keys at positions ≥ m and preserves it
    /// for positions < m — SC#2's invalidation semantics fall out of the
    /// hash chain for free (no `cache_obsolete_order` machinery).
    let upstreamHash: UInt64

    /// The ROI the plane was produced for. Pass-through era: identical for
    /// every position in a pipe run (processRec asserts the invariant —
    /// Risk #7 — and Phase 4's ROI negotiation starts exploiting it).
    let roi: ROI
}

/// The incremental upstream-hash combine helper (test seam for the chain
/// math — the pipe threads a running hash per level, O(1) per level; this
/// recomputes-from-prefix form exists so `PipeCacheTests` can assert the
/// chain composition independently of the recursion).
internal enum PipeHash {

    /// Fold the `paramsHash` of every entry positioned before `position`
    /// (ascending) into `seed` via `StableHash.combine`. The pipe seeds with
    /// `decodeParamsHash` (§1.3 gotcha — decode-side param changes must
    /// invalidate every module, not just the input plane).
    static func upstream(
        seed: UInt64,
        _ paramsHashes: [(position: Int, hash: UInt64)],
        upTo position: Int
    ) -> UInt64 {
        var running = seed
        for entry in paramsHashes.sorted(by: { $0.position < $1.position })
        where entry.position < position {
            var hash = entry.hash
            running = withUnsafeBytes(of: &hash) { StableHash.combine(running, $0) }
        }
        return running
    }
}

import Foundation

// NOTE (Plan 02-03-03): `PipeResolution` moved to its own file,
// `PipeResolution.swift`, which now also carries the lifecycle surface
// (`defaultLongEdge`, `isLazy`, `cachesIntermediatePlanes`) and the
// four-pipe lifecycle table. This file keeps ONLY the cache-key machinery.

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

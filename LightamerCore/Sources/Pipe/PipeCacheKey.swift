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
///
/// **Layer dimension (Plan 06-01 T3):** `layerID` namespaces every cached
/// plane by the layer sub-run that produced it (D-06-01-T3-1):
/// - base + terminal-segment sub-runs key on `baseLayer.id` — or the
///   `baseLayerSentinelID` when the pipe has no stack (Phase 2-5 test paths
///   keep today's key space exactly);
/// - each adjustment layer's sub-run keys on the layer's UUID (NDE-1) —
///   editing layer K can never flip layer J's lines, and a REORDER flips
///   nothing at all (the key carries the layer identity, not its index);
/// - composite-prefix planes key on the OWNING layer at the reserved
///   `compositePosition`.
internal struct PipeCacheKey: Hashable {

    /// The layer namespace anchor (see the header). Defaults to the base
    /// sentinel so every Phase 2-5 call site and test keeps its exact
    /// historical key space.
    let layerID: UUID

    /// Per-image namespace (sidecar-persisted UUID; D-C1 cleanup keys on it).
    let imageID: UUID

    /// Resolution bucket (Darktable `pipe->type`).
    let pipeType: PipeResolution

    /// Chain index — position in the piece array, NOT iop_order
    /// (`pixelpipe_cache.c:113` note). Position 0 = the input plane.
    /// Negative values are RESERVED plane classes:
    /// `compositePosition` (-1) = the composite-prefix plane C_k,
    /// `maskPosition` (-2) = a mask plane (6-3/6-4 tier placeholder).
    let position: Int

    /// FNV-1a chain over `decodeParamsHash` + every ENABLED piece's
    /// `paramsHash` at positions < `position`. A param change at module m
    /// flips `upstreamHash` for all keys at positions ≥ m and preserves it
    /// for positions < m — SC#2's invalidation semantics fall out of the
    /// hash chain for free (no `cache_obsolete_order` machinery).
    /// Composite-prefix keys fold the layer chain hash ⊕ the blend triple
    /// (opacity/blendMode/maskVersion) hash instead — see the driver.
    let upstreamHash: UInt64

    /// The ROI the plane was produced for. Pass-through era: identical for
    /// every position in a pipe run (processRec asserts the invariant —
    /// Risk #7 — and Phase 4's ROI negotiation starts exploiting it).
    let roi: ROI

    /// The namespace anchor for base + terminal-segment sub-runs when the
    /// pipe has no real layer stack (Phase 2-5 paths). Fixed so cache keys
    /// stay stable across runs; distinct from any minted layer UUID in
    /// practice (layer UUIDs are random v4).
    internal static let baseLayerSentinelID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000001")!

    /// Reserved position: the composite-prefix plane after folding layer k
    /// (C_k). Never collides with chain positions (they count from 0).
    internal static let compositePosition = -1

    /// Reserved position: a mask plane (the mask tier is an EMPTY
    /// placeholder until 6-3/6-4 render masks — the enforceBudget tier
    /// exists from day one per the plan).
    internal static let maskPosition = -2

    /// Reserved position: the retouch stroke-leg output plane (Plan 06-07)
    /// — keyed on (input prefix ⊕ stroke-list hash); the same layer-output
    /// eviction tier as a chain plane.
    internal static let retouchPosition = -3

    init(
        imageID: UUID,
        pipeType: PipeResolution,
        position: Int,
        upstreamHash: UInt64,
        roi: ROI,
        layerID: UUID = PipeCacheKey.baseLayerSentinelID
    ) {
        self.layerID = layerID
        self.imageID = imageID
        self.pipeType = pipeType
        self.position = position
        self.upstreamHash = upstreamHash
        self.roi = roi
    }

    /// The mask-plane key (Plan 06-03 T3 — the 06-01 placeholder tier now
    /// active): (imageID, pipeType, layerID, maskVersionHash, roi) at the
    /// reserved `maskPosition`. `maskHash` = `MaskSpec.stableHash()` — a
    /// mask edit flips exactly this key while every chain-output key
    /// (positions ≥ 0) stays untouched (the maskVersion ⊥ chainHash
    /// independence, METAL-8 double insurance).
    static func maskKey(
        imageID: UUID,
        pipeType: PipeResolution,
        layerID: UUID,
        maskHash: UInt64,
        roi: ROI
    ) -> PipeCacheKey {
        PipeCacheKey(
            imageID: imageID, pipeType: pipeType, position: PipeCacheKey.maskPosition,
            upstreamHash: maskHash, roi: roi, layerID: layerID)
    }

    /// The layer-dimension plane class (Plan 06-01 T3 enforceBudget tiers).
    /// The base/terminal namespace (sentinel) is NOT a layer plane — those
    /// planes stay governed by the Phase 2-6 image tiers (current-image
    /// PREVIEW exemption intact).
    internal var layerTier: LayerPlaneTier? {
        if layerID == Self.baseLayerSentinelID { return nil }
        if position == Self.maskPosition { return .maskPlane }
        if position == Self.compositePosition { return .compositePrefix }
        return .layerChainOutput
    }}

/// The layer-dimension eviction tiers (Plan 06-01 T3; 06-RESEARCH §7) —
/// ordered by REBUILD COST across a budget sweep: chain outputs (full sub-run
/// re-render) go before composite prefixes (N cheap blend passes), and mask
/// planes (the 6-3/6-4 placeholder tier) are the last resort — they will be
/// the cheapest to re-rasterize AND the planes downstream caches lean on.
internal enum LayerPlaneTier: Int, Comparable {
    case layerChainOutput = 0
    case compositePrefix = 1
    case maskPlane = 2

    static func < (lhs: LayerPlaneTier, rhs: LayerPlaneTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
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

/// Layer-plane cache policy constants (Plan 06-01 T3; D-06-CONTEXT-8) —
/// injected into the `LayerCompositeDriver`; the 6-5 benchmark owns the
/// fallback decision between `fullColdLayer` and `fullCacheAll`.
public struct LayerCachePolicy: Sendable, Equatable {

    /// Cache the composite-prefix planes (C_k) for every layer. Windowed
    /// FULL prefixes are tens of MB — cheap insurance for layer-K edits.
    public let cachesAllPrefixes: Bool

    /// Cache every layer's chain-output planes. `false` = only the HOT
    /// layer's chain output is retained; cold layers composite-and-discard
    /// (FULL's O(viewport) working set, D-06-CONTEXT-8).
    public let cachesAllLayerOutputs: Bool

    public init(cachesAllPrefixes: Bool, cachesAllLayerOutputs: Bool) {
        self.cachesAllPrefixes = cachesAllPrefixes
        self.cachesAllLayerOutputs = cachesAllLayerOutputs
    }

    /// PREVIEW/THUMBNAIL — everything cached (the D-C3 ladder unchanged;
    /// per-layer planes ~70 MB @2560).
    public static let preview = LayerCachePolicy(
        cachesAllPrefixes: true, cachesAllLayerOutputs: true)

    /// FULL (D-06-CONTEXT-8): hot layer chain output + prefixes only; cold
    /// layers composite-and-discard. Benchmark fallback switch lands in 6-5
    /// (`fit 视图 N 层全幅重渲超预算 → 回退 fullCacheAll`).
    public static let fullColdLayer = LayerCachePolicy(
        cachesAllPrefixes: true, cachesAllLayerOutputs: false)

    /// FULL fallback (post-benchmark): every layer cached, same as preview.
    public static let fullCacheAll = LayerCachePolicy(
        cachesAllPrefixes: true, cachesAllLayerOutputs: true)
}

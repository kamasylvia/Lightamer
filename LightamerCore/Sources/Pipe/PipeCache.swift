import Metal
import os

/// The per-module per-ROI pipe-plane cache (FOUND-04) — the Swift
/// translation of Darktable's cacheline pool (`pixelpipe_cache.c:174-354`),
/// simplified to a dictionary-keyed actor (02-02 checkpoint lock #5):
/// dictionary keys make the fixed cacheline pool, the `used[]` aging
/// counters, and the size-mismatch dirtying (`:261-271`) structurally
/// unnecessary — a key is either present (exact plane) or absent.
///
/// Budget policy (D-C1): byte-budget LRU. Cross the 3 GB budget → evict
/// least-recently-hit planes down to the 2 GB hysteresis floor (anti-
/// thrash). `MetalContext`'s PSO LRU is the same pattern, keyed by entries;
/// this one is keyed by BYTES (planes are MB..GB, not KB).
///
/// Texture ownership (checkpoint lock #7, Phase 1 `RenderedTexture`
/// contract): stored planes are write-once-then-read-only — the pipe hands
/// over a finished output plane and never writes it again; eviction merely
/// drops the reference (MTLTexture deallocation returns memory to the
/// device allocator). Ping-pong scratch planes are pipe-private and NEVER
/// enter this cache.
///
/// Verification channel (SC#2): hit/miss counters + `cache HIT`/`cache
/// MISS` signposts — the exact counts `PipeCacheTests` asserts.
///
/// `public` (02-02 executor resolution): `RenderPipeline.process` injects a
/// shared cache instance — a `public` parameter cannot expose an `internal`
/// type, so the ACTOR is public while the key machinery (`PipeCacheKey`/
/// `PipeHash`) and the stored-plane type (`CachedPlane`) stay internal.
/// Tests share one actor across runs to prove hits.
public actor PipeCache {

    /// D-C1: 4 GB session budget − 1 GB headroom. Constructor constant —
    /// tests shrink it via `init(byteBudget:)`.
    public static let defaultBudget = 3 * 1024 * 1024 * 1024

    /// Eviction floor (0.66 × budget): once over budget, evict until back
    /// here — evicting line-by-line to the exact budget would thrash on
    /// every insert while hovering at the threshold. The EFFECTIVE floor is
    /// `min(Self.evictTarget, byteBudget × 2/3)` per instance so test-sized
    /// budgets get the same hysteresis as the 3 GB production budget.
    public static let evictTarget = 2 * 1024 * 1024 * 1024

    /// One cached plane. `@unchecked Sendable` carries the OWNERSHIP
    /// transfer contract (not free-for-all sharing): the producing pipe run
    /// renounces write access at handover; readers only ever `shaderRead`.
    internal struct CachedPlane: @unchecked Sendable {

        /// The finished output plane (float32 RGBA linear Rec2020,
        /// FOUND-02). Write-once-then-readonly per the lock #7 contract.
        let texture: any MTLTexture

        /// `width × height × bytesPerPixel` — tracked incrementally by the
        /// cache (`totalBytes` never walks textures).
        let byteCount: Int

        /// LRU clock — touched on every hit.
        var lastHit: ContinuousClock.Instant
    }

    /// SC#2 verification counters (cumulative over the cache's lifetime —
    /// NOT reset by invalidation, so tests can assert across runs).
    public struct CacheStats: Sendable {
        public private(set) var hits: Int = 0
        public private(set) var misses: Int = 0

        public init(hits: Int = 0, misses: Int = 0) {
            self.hits = hits
            self.misses = misses
        }

        /// Mutation seam for the enclosing actor (the fields are publicly
        /// read-only; only these counters move them).
        internal mutating func incrementHit() { hits += 1 }
        internal mutating func incrementMiss() { misses += 1 }

        public static func + (lhs: CacheStats, rhs: CacheStats) -> CacheStats {
            CacheStats(hits: lhs.hits + rhs.hits, misses: lhs.misses + rhs.misses)
        }

        public static func - (lhs: CacheStats, rhs: CacheStats) -> CacheStats {
            CacheStats(hits: lhs.hits - rhs.hits, misses: lhs.misses - rhs.misses)
        }
    }

    private var planes: [PipeCacheKey: CachedPlane] = [:]
    private var trackedBytes = 0
    private var statsValue = CacheStats()
    private let byteBudget: Int

    private static let signposter = OSSignposter(
        subsystem: "com.kamasylvia.lightamer", category: "pixelpipe"
    )

    public init(byteBudget: Int = PipeCache.defaultBudget) {
        self.byteBudget = byteBudget
    }

    /// Bytes currently held (incrementally tracked — never walked).
    public var totalBytes: Int { trackedBytes }

    /// Cumulative hit/miss counters (SC#2 assertions).
    public var stats: CacheStats { statsValue }

    /// Probe the cache; on miss build the plane through `make`, store it,
    /// and enforce the budget. The hit path never invokes `make` (upstream
    /// zero-computation — the whole point of the fast path).
    ///
    /// Reentrancy note: `await make()` suspends actor isolation; concurrent
    /// probes of the SAME key may both miss and build (duplicated work, not
    /// a correctness issue — the pipe serializes per pipe run).
    func plane(
        for key: PipeCacheKey,
        byteCount: Int,
        make: @Sendable () async throws -> sending any MTLTexture
    ) async throws -> CachedPlane {
        if var cached = planes[key] {
            cached.lastHit = .now // LRU touch (Darktable sets used = -entries)
            planes[key] = cached
            statsValue.incrementHit()
            Self.signposter.emitEvent("cache HIT")
            return cached
        }
        statsValue.incrementMiss()
        Self.signposter.emitEvent("cache MISS")
        let texture = try await make()
        let plane = CachedPlane(texture: texture, byteCount: byteCount, lastHit: .now)
        planes[key] = plane
        trackedBytes += byteCount
        evictUnderBudget(keeping: key)
        return plane
    }

    /// Per-image sweep — the load-entry cleanup anchor (D-C1/D-C2; Plan
    /// 02-03 wires the coordinator, 02-06 the budget enforcement).
    public func invalidate(imageID: UUID) {
        for key in planes.keys where key.imageID == imageID {
            trackedBytes -= planes[key]?.byteCount ?? 0
            planes.removeValue(forKey: key)
        }
    }

    /// Tests / teardown.
    public func invalidateAll() {
        planes.removeAll()
        trackedBytes = 0
    }

    /// Surgical layer sweep (Plan 06-01 T3/T4): drop the CHAIN-OUTPUT lines
    /// of one layer (position ≥ 0 — composite prefixes at the reserved
    /// negative positions survive). The cold-layer leg of
    /// `LayerCachePolicy.fullColdLayer` uses this after a cold blend.
    public func invalidateLayer(imageID: UUID, layerID: UUID) {
        for key in planes.keys
        where key.imageID == imageID && key.layerID == layerID && key.position >= 0 {
            trackedBytes -= planes[key]?.byteCount ?? 0
            planes.removeValue(forKey: key)
        }
    }

    // MARK: - Session-level budget enforcement (Plan 02-06-05; D-C1/D-C2)

    /// The keep policy for `enforceBudget` (checkpoint 02-06-01 lock #6):
    /// the CURRENT image's planes and the PREVIOUS image's PREVIEW planes
    /// survive the session sweep.
    public struct KeepingPolicy: Sendable {
        /// The image being edited — its FULL+PREVIEW planes are kept.
        public let currentImageID: UUID
        /// The image loaded before the current one — only its PREVIEW
        /// planes are kept (D-C1: "保留当前图 FULL+PREVIEW、最近 1 张历史
        /// 图的 PREVIEW").
        public let previousImageID: UUID?

        public init(currentImageID: UUID, previousImageID: UUID?) {
            self.currentImageID = currentImageID
            self.previousImageID = previousImageID
        }
    }

    /// What an `enforceBudget` pass evicted (the D-26 toast input).
    public struct Freed: Sendable {
        public let bytesFreed: Int
        public let planesEvicted: Int

        public init(bytesFreed: Int, planesEvicted: Int) {
            self.bytesFreed = bytesFreed
            self.planesEvicted = planesEvicted
        }
    }

    /// The 3 GB policy EXECUTOR (D-C1) — deliberately a pure function of
    /// (cache contents, threshold, policy): the 60-second sweep timer is
    /// only a CALLER (research Open Question #7), so unit tests drive this
    /// directly with an injected threshold and never allocate 3 GB.
    ///
    /// No-op at or under `threshold`. Over it, evicts LRU-oldest-first in
    /// the LOCKED tier order, stopping when bytes fall to the hysteresis
    /// floor (`min(evictTarget, budget × 2/3)`):
    ///   1. OTHER images' THUMBNAIL + EXPORT planes (browser/export
    ///      by-products — cheapest to rebuild),
    ///   2. OTHER images' FULL planes (on-demand by contract),
    ///   3. OTHER images' PREVIEW planes, EXCEPT `previousImageID`'s
    ///      (D-C1 keeps exactly the most recent previous PREVIEW),
    ///   4. the CURRENT image's non-PREVIEW planes (thumbnail/full —
    ///      inactive resolutions; its PREVIEW planes are never touched).
    ///
    /// The previous image's THUMBNAIL/FULL planes still fall in tiers 1-2
    /// (only its PREVIEW is protected), and the current image's PREVIEW
    /// planes are exempt from every tier by construction.
    public func enforceBudget(
        now threshold: Int = PipeCache.defaultBudget,
        keeping policy: KeepingPolicy
    ) async -> Freed {
        let floor = min(Self.evictTarget, byteBudget * 2 / 3)
        guard trackedBytes > threshold else {
            return Freed(bytesFreed: 0, planesEvicted: 0)
        }

        func candidates(match: (PipeResolution, UUID) -> Bool) -> [PipeCacheKey] {
            planes
                .filter { key, _ in match(key.pipeType, key.imageID) }
                .sorted { $0.value.lastHit < $1.value.lastHit }
                .map { $0.key }
        }
        let isOther = { (imageID: UUID) in imageID != policy.currentImageID }

        var ordered: [PipeCacheKey] = []
        // Tier 1: other images' THUMBNAIL + EXPORT.
        ordered += candidates { res, id in
            isOther(id) && (res == .thumbnail || res == .export)
        }
        // Tier 2: other images' FULL.
        ordered += candidates { res, id in
            isOther(id) && res == .full
        }
        // Tier 3: other images' PREVIEW except the previous image's.
        ordered += candidates { res, id in
            isOther(id) && res == .preview && id != policy.previousImageID
        }
        // Tier 4: the CURRENT image's inactive resolutions (non-PREVIEW).
        ordered += candidates { res, id in
            !isOther(id) && res != .preview
        }
        // Tier 5 (Plan 06-01 T3): the CURRENT image's LAYER-dimension
        // planes, in `LayerPlaneTier` order (chain outputs → composite
        // prefixes → mask planes). The base/terminal namespace (sentinel
        // layerID) is deliberately NOT a layer plane — its current-image
        // PREVIEW planes keep the historical exemption from every sweep.
        // D-06-01-T3-1: the plan's "终端/输入" leg of the layer order is
        // anchored by the existing image tiers (other-image FULL at tier 2,
        // current-image non-PREVIEW at tier 4) — re-evicting the current
        // image's base input/terminal planes here would thrash the D-C3
        // preview ladder for zero headroom gain.
        let layerTierCandidates: [(
            key: PipeCacheKey, tier: LayerPlaneTier, lastHit: ContinuousClock.Instant
        )] = planes.compactMap { element in
            element.key.layerTier.map { (element.key, $0, element.value.lastHit) }
        }
        let currentImageLayerCandidates = layerTierCandidates.filter { !isOther($0.key.imageID) }
        let tierOrdered = currentImageLayerCandidates.sorted(by: { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            return lhs.lastHit < rhs.lastHit
        })
        ordered += tierOrdered.map(\.key)

        var freedBytes = 0
        var evicted = 0
        for key in ordered {
            guard trackedBytes > floor else { break }
            guard let plane = planes.removeValue(forKey: key) else { continue }
            trackedBytes -= plane.byteCount
            freedBytes += plane.byteCount
            evicted += 1
        }
        if evicted > 0 {
            Self.signposter.emitEvent("enforceBudget")
            AppError.logger.info(
                "enforceBudget: evicted \(evicted, privacy: .public) planes (\(freedBytes, privacy: .public) bytes) at threshold \(threshold, privacy: .public)"
            )
        }
        return Freed(bytesFreed: freedBytes, planesEvicted: evicted)
    }

    // MARK: - Eviction (lock #5: LRU by lastHit, budget → target hysteresis)

    /// Only fires after crossing `byteBudget`; evicts oldest-`lastHit` first
    /// (the freshly inserted plane is never its own eviction victim — a
    /// single plane larger than the whole budget is tolerated here and left
    /// to 02-06's session-level enforcement).
    private func evictUnderBudget(keeping freshlyInserted: PipeCacheKey) {
        guard trackedBytes > byteBudget else { return }
        let floor = min(Self.evictTarget, byteBudget * 2 / 3)
        while trackedBytes > floor {
            guard let oldest = planes
                .filter({ $0.key != freshlyInserted })
                .min(by: { $0.value.lastHit < $1.value.lastHit })
            else { break }
            trackedBytes -= oldest.value.byteCount
            planes.removeValue(forKey: oldest.key)
        }
    }
}

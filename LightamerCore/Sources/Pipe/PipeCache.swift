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
    /// every insert while hovering at the threshold.
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

    // MARK: - Eviction (lock #5: LRU by lastHit, budget → target hysteresis)

    /// Only fires after crossing `byteBudget`; evicts oldest-`lastHit` first
    /// (the freshly inserted plane is never its own eviction victim — a
    /// single plane larger than the whole budget is tolerated here and left
    /// to 02-06's session-level enforcement).
    private func evictUnderBudget(keeping freshlyInserted: PipeCacheKey) {
        guard trackedBytes > byteBudget else { return }
        while trackedBytes > Self.evictTarget {
            guard let oldest = planes
                .filter({ $0.key != freshlyInserted })
                .min(by: { $0.value.lastHit < $1.value.lastHit })
            else { break }
            trackedBytes -= oldest.value.byteCount
            planes.removeValue(forKey: oldest.key)
        }
    }
}

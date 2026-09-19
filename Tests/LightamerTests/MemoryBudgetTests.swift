@testable import LightamerCore
import CoreImage
import Metal
import XCTest

/// Session memory budget enforcement (Plan 02-06-05/07; D-C1/D-C2, spike-b
/// 4.3-5.4 GB cross-decode accumulation evidence — the header citation the
/// plan requires lives at `PipeCoordinator`'s load-entry trigger).
///
/// `enforceBudget(now:keeping:)` is the PURE policy executor (research Open
/// Question #7): every test here injects a tiny threshold + byte budget, so
/// CI never allocates gigabytes. The production 3 GB constant is exercised
/// only as the default parameter.
///
/// Locked policy (checkpoint 02-06-01 lock #6), tiers in eviction order:
/// other-image THUMBNAIL/EXPORT → other-image FULL → other-image PREVIEW
/// (except `previousImageID`) → current-image non-PREVIEW; current-image
/// PREVIEW planes are never touched. LRU-oldest-first within a tier; stops
/// at the hysteresis floor (`min(evictTarget, budget × 2/3)`).
final class MemoryBudgetTests: XCTestCase {

    /// 1×1 float32 texture (the byteCount drives accounting, not the size).
    private func tinyTexture(_ metal: MetalContext) -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat, width: 1, height: 1,
            mipmapped: false
        )
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        return metal.device.makeTexture(descriptor: d)!
    }

    private static func makeDescriptor() -> MTLTextureDescriptor {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat, width: 1, height: 1,
            mipmapped: false
        )
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        return d
    }

    private func insert(
        _ cache: PipeCache, metal: MetalContext,
        imageID: UUID, _ resolution: PipeResolution, position: Int = 1,
        bytes: Int, upstream: UInt64 = 1
    ) async throws {
        let key = PipeCacheKey(
            imageID: imageID, pipeType: resolution, position: position,
            upstreamHash: upstream,
            roi: ROI(width: 1, height: 1, scale: 1)
        )
        _ = try await cache.plane(for: key, byteCount: bytes) { [metal] in
            metal.device.makeTexture(descriptor: Self.makeDescriptor())!
        }
    }

    /// Probe survival: a hit means the plane survived the sweep.
    private func survives(
        _ cache: PipeCache, metal: MetalContext,
        imageID: UUID, _ resolution: PipeResolution, position: Int = 1,
        bytes: Int, upstream: UInt64 = 1
    ) async throws -> Bool {
        let before = await cache.stats
        let key = PipeCacheKey(
            imageID: imageID, pipeType: resolution, position: position,
            upstreamHash: upstream,
            roi: ROI(width: 1, height: 1, scale: 1)
        )
        _ = try await cache.plane(for: key, byteCount: bytes) { [metal] in
            metal.device.makeTexture(descriptor: Self.makeDescriptor())!
        }
        let after = await cache.stats
        return after.hits > before.hits
    }

    // ── 1. The keep/evict matrix (one row per locked tier) ──────────────

    func testEnforceBudgetKeepEvictMatrix() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        // Budget 1200 → floor = min(2 GB, 1200 × 2/3) = 800. Total exactly
        // 1200 (the insert-time LRU never fires at ≤ budget); the sweep
        // entry at 1199 evicts the 400 oldest tier-1..3 bytes and STOPS at
        // the floor — deep enough to prove tiers 1-3 + the keeps, without
        // tier 4 (covered by the dedicated scenario below).
        let cache = PipeCache(byteBudget: 1200)
        let current = UUID()
        let previous = UUID()
        let other = UUID()

        try await insert(cache, metal: metal, imageID: current, .preview, bytes: 400)
        try await insert(cache, metal: metal, imageID: current, .thumbnail, bytes: 100)
        try await insert(cache, metal: metal, imageID: current, .full, bytes: 100)
        try await insert(cache, metal: metal, imageID: previous, .preview, bytes: 100)
        try await insert(cache, metal: metal, imageID: previous, .thumbnail, bytes: 100)
        try await insert(cache, metal: metal, imageID: previous, .full, bytes: 100)
        try await insert(cache, metal: metal, imageID: other, .preview, bytes: 100)
        try await insert(cache, metal: metal, imageID: other, .thumbnail, bytes: 100)
        try await insert(cache, metal: metal, imageID: other, .full, bytes: 100)
        let total = await cache.totalBytes
        XCTAssertEqual(total, 1200)

        let freed = await cache.enforceBudget(
            now: 1199,
            keeping: PipeCache.KeepingPolicy(currentImageID: current, previousImageID: previous)
        )
        XCTAssertEqual(freed.planesEvicted, 4, "tier 1×2 + tier 2 + tier 3")
        XCTAssertEqual(freed.bytesFreed, 400)

        // SURVIVORS (the locked keep set): current PREVIEW + previous
        // PREVIEW — everything else falls in tiers 1-4.
        // (survives() is async — XCTest autoclosures are not; hoist first.)
        let totalAfterSweep = await cache.totalBytes
        XCTAssertEqual(totalAfterSweep, 800, "1200 − the four tier-1/2 planes = the floor")

        let curPreview = try await survives(cache, metal: metal, imageID: current, .preview, bytes: 400)
        let prevPreview = try await survives(cache, metal: metal, imageID: previous, .preview, bytes: 100)
        let otherPreview = try await survives(cache, metal: metal, imageID: other, .preview, bytes: 100)
        let otherThumb = try await survives(cache, metal: metal, imageID: other, .thumbnail, bytes: 100)
        let otherFull = try await survives(cache, metal: metal, imageID: other, .full, bytes: 100)
        let prevThumb = try await survives(cache, metal: metal, imageID: previous, .thumbnail, bytes: 100)
        let prevFull = try await survives(cache, metal: metal, imageID: previous, .full, bytes: 100)
        let curThumb = try await survives(cache, metal: metal, imageID: current, .thumbnail, bytes: 100)
        let curFull = try await survives(cache, metal: metal, imageID: current, .full, bytes: 100)
        let totalAfter = await cache.totalBytes

        XCTAssertTrue(curPreview, "current-image PREVIEW planes are never evicted")
        XCTAssertTrue(prevPreview, "the previous image's PREVIEW plane survives (D-C1 keep)")
        XCTAssertTrue(otherPreview,
                      "the floor stopped the sweep BEFORE tier 3 (scenario 3c covers tier 3)")
        XCTAssertFalse(otherThumb, "other images' THUMBNAIL planes evict (tier 1)")
        XCTAssertFalse(otherFull, "other images' FULL planes evict (tier 2)")
        XCTAssertFalse(prevThumb, "the previous image's THUMBNAIL is NOT protected (tier 1)")
        XCTAssertFalse(prevFull, "the previous image's FULL is NOT protected (tier 2)")
        XCTAssertTrue(curThumb, "the sweep stopped at the floor BEFORE tier 3/4")
        XCTAssertTrue(curFull, "the floor protected every deeper tier in this scenario")
    }

    // ── 2. Tier ORDER within one sweep (LRU-oldest first per tier) ─────

    func testEnforceBudgetEvictionOrderWithinTiers() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        // Floor = min(2 GB, 300 × 2/3) = 200; total exactly 300 (no
        // insert-time eviction), trigger 299: the sweep evicts exactly ONE
        // 100-byte plane — the tier-1 LRU-OLDEST one.
        let cache = PipeCache(byteBudget: 300)
        let current = UUID()
        let otherA = UUID()
        let otherB = UUID()

        try await insert(cache, metal: metal, imageID: current, .preview, bytes: 100)
        // Tier 1 candidates, oldest FIRST (insertion order = lastHit order).
        try await insert(cache, metal: metal, imageID: otherA, .thumbnail, bytes: 100)
        try await insert(cache, metal: metal, imageID: otherB, .thumbnail, bytes: 100)

        let freed = await cache.enforceBudget(
            now: 299,
            keeping: PipeCache.KeepingPolicy(currentImageID: current, previousImageID: nil)
        )
        XCTAssertEqual(freed.planesEvicted, 1, "evict to the floor, no further")
        XCTAssertEqual(freed.bytesFreed, 100)
        let otherBThumb = try await survives(cache, metal: metal, imageID: otherB, .thumbnail, bytes: 100)
        let curPreview2 = try await survives(cache, metal: metal, imageID: current, .preview, bytes: 100)
        let otherAThumb = try await survives(cache, metal: metal, imageID: otherA, .thumbnail, bytes: 100)
        XCTAssertTrue(otherBThumb, "the OLDEST tier-1 plane (otherA) evicts first")
        XCTAssertTrue(curPreview2, "current PREVIEW untouched")
        XCTAssertFalse(otherAThumb, "oldest-first: otherA's thumbnail went first")
    }

    // ── 3. Tier 4: the current image's inactive resolutions ────────────

    func testEnforceBudgetEvictsCurrentInactiveResolutions() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        // No other-image planes at all: budget 1000 → floor 666; total
        // 1000, trigger 999 → the sweep must take the tier-4 planes
        // (thumbnail, then full) and stop only when the PREVIEW remains.
        let cache = PipeCache(byteBudget: 1000)
        let current = UUID()
        try await insert(cache, metal: metal, imageID: current, .preview, bytes: 400)
        try await insert(cache, metal: metal, imageID: current, .thumbnail, bytes: 300)
        try await insert(cache, metal: metal, imageID: current, .full, bytes: 300)
        let totalBefore = await cache.totalBytes
        XCTAssertEqual(totalBefore, 1000)

        let freed = await cache.enforceBudget(
            now: 999,
            keeping: PipeCache.KeepingPolicy(currentImageID: current, previousImageID: nil)
        )
        XCTAssertEqual(freed.planesEvicted, 2)
        XCTAssertEqual(freed.bytesFreed, 600)
        let curPreview = try await survives(cache, metal: metal, imageID: current, .preview, bytes: 400)
        let curThumb = try await survives(cache, metal: metal, imageID: current, .thumbnail, bytes: 300)
        let curFull = try await survives(cache, metal: metal, imageID: current, .full, bytes: 300)
        XCTAssertTrue(curPreview, "current PREVIEW survives the tier-4 sweep")
        XCTAssertFalse(curThumb, "current THUMBNAIL is an inactive resolution (tier 4)")
        XCTAssertFalse(curFull, "current FULL is an inactive resolution (tier 4)")
    }

    // ── 3c. Tier 3: other images' PREVIEW except the previous image's ──

    func testEnforceBudgetEvictsOtherImagePreviewsButKeepsPrevious() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        // Only PREVIEW planes: budget 600 → floor 400; total 600, trigger
        // 599 → the sweep must take OTHER images' previews (tier 3) while
        // the previous image's PREVIEW survives (the D-C1 keep).
        let cache = PipeCache(byteBudget: 600)
        let current = UUID()
        let previous = UUID()
        let other = UUID()
        try await insert(cache, metal: metal, imageID: current, .preview, bytes: 400)
        try await insert(cache, metal: metal, imageID: previous, .preview, bytes: 100)
        try await insert(cache, metal: metal, imageID: other, .preview, bytes: 100)

        let freed = await cache.enforceBudget(
            now: 599,
            keeping: PipeCache.KeepingPolicy(currentImageID: current, previousImageID: previous)
        )
        XCTAssertEqual(freed.planesEvicted, 1)
        XCTAssertEqual(freed.bytesFreed, 100)

        let curPreview = try await survives(cache, metal: metal, imageID: current, .preview, bytes: 400)
        let prevPreview = try await survives(cache, metal: metal, imageID: previous, .preview, bytes: 100)
        let otherPreview = try await survives(cache, metal: metal, imageID: other, .preview, bytes: 100)
        XCTAssertTrue(curPreview, "current PREVIEW untouched")
        XCTAssertTrue(prevPreview, "previous PREVIEW kept (D-C1)")
        XCTAssertFalse(otherPreview, "other images' PREVIEW planes evict (tier 3)")
    }

    // ── 3b. No-op under threshold ───────────────────────────────────────

    func testEnforceBudgetNoOpUnderThreshold() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        let cache = PipeCache(byteBudget: 300)
        let current = UUID()
        try await insert(cache, metal: metal, imageID: current, .preview, bytes: 50)

        let freed = await cache.enforceBudget(
            now: PipeCache.defaultBudget, // 3 GB trigger, 50 bytes cached
            keeping: PipeCache.KeepingPolicy(currentImageID: current, previousImageID: nil)
        )
        XCTAssertEqual(freed.bytesFreed, 0)
        XCTAssertEqual(freed.planesEvicted, 0)
        let total = await cache.totalBytes
        XCTAssertEqual(total, 50, "under threshold the sweep is a no-op")
    }

    // ── 4. Load-loop scenario (the D-C1/C2 regression harness) ──────────

    func testSequentialLoadLoopStaysUnderBudget() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        // Budget 1000 → floor 666. Per load: preview 150 + thumbnail 90 +
        // full 90 = 330 ≤ (budget − floor) = 334, so the INSERT-time LRU
        // never fires and the ENFORCE sweep does all the work (the real
        // coordinator shape). Six sequential loads; the enforce threshold
        // (900) fires from the second load on, evicting the previous
        // loads' planes (LRU-oldest) down to the floor.
        let cache = PipeCache(byteBudget: 1000)
        var previous: UUID?
        var evictedOnce = false
        var peakBytes = 0

        for _ in 0..<6 {
            let current = UUID()
            try await insert(cache, metal: metal, imageID: current, .preview, bytes: 150)
            try await insert(cache, metal: metal, imageID: current, .thumbnail, bytes: 90)
            try await insert(cache, metal: metal, imageID: current, .full, bytes: 90)

            let freed = await cache.enforceBudget(
                now: 900,
                keeping: PipeCache.KeepingPolicy(
                    currentImageID: current, previousImageID: previous
                )
            )
            if freed.planesEvicted > 0 { evictedOnce = true }

            let total = await cache.totalBytes
            XCTAssertLessThanOrEqual(total, 666, "each sweep lands at or under the floor")
            peakBytes = max(peakBytes, total)
            previous = current
        }
        XCTAssertTrue(evictedOnce, "at least one load-entry sweep must have evicted")
        XCTAssertLessThanOrEqual(peakBytes, 1000, "the budget itself is never crossed")
    }

    // ── 5. CI clear smoke (D-C1 layer 2) ────────────────────────────────

    func testClearCICachesCallableWithoutCorruption() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        // The clear itself: callable with no state to corrupt.
        await metal.clearCICaches()
        // Smoke: the render path still works right after the clear (the
        // lazily created pool is reusable, not invalidated by the clear).
        let gradient = CIImage(color: CIColor(red: 0.4, green: 0.5, blue: 0.6))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let image = DecodedImage(
            ciImage: gradient, rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )
        let texture = try await metal.renderToTexture(image.ciImage)
        XCTAssertEqual(texture.width, 16)
        XCTAssertEqual(texture.height, 16)
        await metal.clearCICaches() // idempotent
    }
}

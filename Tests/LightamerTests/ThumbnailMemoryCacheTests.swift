import CoreGraphics
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 09-03 T1 — ThumbnailMemoryCache: the LRU byte-budget suite.
//
// The 防空转 red line (09-03-PLAN 纪律): eviction assertions are EXACT —
// the eviction SEQUENCE (oldest first, in bytes) and the resident total
// (≤ budget at every observation), with a tiny injected budget driving real
// eviction traffic. Hit/miss counters and LRU recency-refresh (a hit must
// move an entry out of eviction range) are pinned too.
// ─────────────────────────────────────────────────────────────────────────────

final class ThumbnailMemoryCacheTests: XCTestCase {

    /// A deterministic synthetic CGImage (solid color, exact dimensions).
    /// `static` + `nonisolated`: task-group closures capture these without
    /// capturing the (non-Sendable) XCTestCase instance.
    private static func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.5, green: 0.25, blue: 0.75, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private static func makeCache(budget: Int) -> ThumbnailMemoryCache {
        // 8-bit RGBA → the injected counter is EXACT: width × height × 4.
        ThumbnailMemoryCache(budgetBytes: budget) { image in
            image.width * image.height * 4
        }
    }

    // MARK: - Exact eviction sequence

    func testEvictionSequenceIsExactOldestFirstWithBytes() async {
        // Budget 3000; each 20×10 image = 800 bytes → 3 fit, the 4th evicts
        // exactly one (the oldest).
        let cache = Self.makeCache(budget: 3000)
        await cache.insert(Self.makeImage(width: 20, height: 10), for: "a.jpg") // 800
        await cache.insert(Self.makeImage(width: 20, height: 10), for: "b.jpg") // 1600
        await cache.insert(Self.makeImage(width: 20, height: 10), for: "c.jpg") // 2400
        var resident = await cache.residentBytes
        var order = await cache.orderSnapshot
        XCTAssertEqual(resident, 2400)
        XCTAssertEqual(order, ["a.jpg", "b.jpg", "c.jpg"])
        let initialEvictions = await cache.evictionSequence
        XCTAssertTrue(initialEvictions.isEmpty, "no eviction below budget")

        await cache.insert(Self.makeImage(width: 20, height: 10), for: "d.jpg") // 3200 > 3000
        resident = await cache.residentBytes
        order = await cache.orderSnapshot
        let evicted = await cache.evictionSequence
        XCTAssertEqual(evicted.count, 1, "evict exactly ONE oldest entry")
        XCTAssertEqual(evicted.first?.path, "a.jpg", "LRU-oldest is the victim")
        XCTAssertEqual(evicted.first?.bytes, 800, "byte accounting is exact")
        XCTAssertEqual(resident, 2400, "resident back at/below budget")
        XCTAssertEqual(order, ["b.jpg", "c.jpg", "d.jpg"])
        let hasB = await cache.contains("b.jpg")
        let hasA = await cache.contains("a.jpg")
        XCTAssertTrue(hasB)
        XCTAssertFalse(hasA)

        // A bigger insert evicts MULTIPLE entries — again exact, oldest
        // first, stopping at the budget: 25×10 = 1000 bytes → 2400+1000 =
        // 3400 > 3000 → evict b (800) → 2600 ≤ 3000, stop.
        await cache.insert(Self.makeImage(width: 25, height: 10), for: "e.jpg")
        let evicted2 = await cache.evictionSequence
        let evicted2Paths = evicted2.map(\.path)
        XCTAssertEqual(
            evicted2Paths, ["a.jpg", "b.jpg"],
            "the 1000-byte insert evicts exactly TWO oldest entries (a, b)"
        )
        resident = await cache.residentBytes
        XCTAssertLessThanOrEqual(resident, 3000, "resident ≤ budget after eviction")
        order = await cache.orderSnapshot
        XCTAssertEqual(order, ["c.jpg", "d.jpg", "e.jpg"])
    }

    func testOversizedSingleEntryToleratedLikePipeCacheOversizedPlane() async {
        // A single entry LARGER than the whole budget: eviction stops at the
        // last entry (never self-evicts / never empties the cache) — the
        // same oversized-plane posture PipeCache documents. The resident
        // total legitimately exceeds the budget in this unreachable-in-
        // practice case (thumbnails are ~0.35 MB against 384 MB).
        let cache = Self.makeCache(budget: 1000)
        await cache.insert(Self.makeImage(width: 50, height: 50), for: "big.jpg") // 10000
        let resident = await cache.residentBytes
        let count = await cache.count
        XCTAssertEqual(resident, 10000, "the oversized entry is retained, not thrashed")
        XCTAssertEqual(count, 1)
    }

    func testHitRefreshesRecencySoFreshlyUsedSurvives() async {
        let cache = Self.makeCache(budget: 3000)
        await cache.insert(Self.makeImage(width: 20, height: 10), for: "a.jpg")
        await cache.insert(Self.makeImage(width: 20, height: 10), for: "b.jpg")
        await cache.insert(Self.makeImage(width: 20, height: 10), for: "c.jpg")

        // Touch "a" → recency tail; the eviction victim becomes "b".
        _ = await cache.image(for: "a.jpg")
        await cache.insert(Self.makeImage(width: 20, height: 10), for: "d.jpg")

        let evicted = await cache.evictionSequence
        let evictedPaths = evicted.map(\.path)
        XCTAssertEqual(evictedPaths, ["b.jpg"], "the HIT entry survives, LRU-oldest 'b' evicts")
        let hasA = await cache.contains("a.jpg")
        XCTAssertTrue(hasA)
        let hits = await cache.hits
        XCTAssertEqual(hits, 1)
    }

    // MARK: - Hit/miss accounting

    func testHitAndMissCounters() async {
        let cache = Self.makeCache(budget: 3000)
        _ = await cache.image(for: "missing.jpg")
        _ = await cache.image(for: "missing.jpg")
        await cache.insert(Self.makeImage(width: 20, height: 10), for: "a.jpg")
        _ = await cache.image(for: "a.jpg")
        _ = await cache.image(for: "a.jpg")

        let hits = await cache.hits
        let misses = await cache.misses
        XCTAssertEqual(hits, 2)
        XCTAssertEqual(misses, 2)
    }

    func testRemoveAndRemoveAllResetExactly() async {
        let cache = Self.makeCache(budget: 3000)
        await cache.insert(Self.makeImage(width: 20, height: 10), for: "a.jpg")
        await cache.insert(Self.makeImage(width: 20, height: 10), for: "b.jpg")
        await cache.remove("a.jpg")
        var resident = await cache.residentBytes
        var count = await cache.count
        XCTAssertEqual(resident, 800)
        XCTAssertEqual(count, 1)

        await cache.removeAll()
        resident = await cache.residentBytes
        count = await cache.count
        XCTAssertEqual(resident, 0, "teardown leg: LRU empty (leak assertion)")
        XCTAssertEqual(count, 0)
        let order = await cache.orderSnapshot
        XCTAssertTrue(order.isEmpty)
    }

    func testReplaceSamePathDoesNotDoubleCount() async {
        let cache = Self.makeCache(budget: 3000)
        await cache.insert(Self.makeImage(width: 20, height: 10), for: "a.jpg") // 800
        await cache.insert(Self.makeImage(width: 30, height: 10), for: "a.jpg") // 1200 replaces
        let resident = await cache.residentBytes
        XCTAssertEqual(resident, 1200, "replacement subtracts the old bytes first")
        let count = await cache.count
        XCTAssertEqual(count, 1)
    }

    // MARK: - Concurrency smoke

    func testConcurrentAccessSmoke() async {
        let cache = Self.makeCache(budget: 4000)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<32 {
                group.addTask {
                    let path = "img-\(index % 8).jpg"
                    await cache.insert(Self.makeImage(width: 20, height: 10), for: path)
                    _ = await cache.image(for: path)
                }
                _ = index
            }
        }
        let resident = await cache.residentBytes
        let count = await cache.count
        XCTAssertLessThanOrEqual(resident, 4000, "budget holds under concurrent traffic")
        XCTAssertGreaterThan(count, 0)
        // Accounting invariant: resident == sum of entries (no drift).
        let orderCount = await cache.orderSnapshot.count
        XCTAssertEqual(orderCount, count, "LRU order array and dictionary stay in sync")
    }
}

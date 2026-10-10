@testable import Lightamer
@testable import LightamerCore
import Metal
import XCTest

/// Plan M4-2-01 T4 (KD-4, OQ-3-A) — the ridge-graph carrier: folded key
/// (prefixHash ⊕ threshold bitPattern, no strength — checker E1), LRU 8
/// eviction, and the coordinator injection seam with the machine-checked
/// carrier contract (threshold drag re-extracts WITHOUT re-running the GPU
/// pass; repeated fetches never re-extract). The walker's stale-carrier
/// refusal (RidgeGraph.high stamp) is pinned at Core level in
/// FollowEdgesTests; here the carrier face is what's under test.
@MainActor
final class FollowEdgesRidgeCacheTests: XCTestCase {

    private var coordinator: PipeCoordinator!
    private var metal: MetalContext!
    private var plane: (any MTLTexture)!

    override func setUp() async throws {
        try await super.setUp()
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
        coordinator = PipeCoordinator()
        coordinator.attach(metal: metal)
        // A luma step at x=32 over 64×64 — the Sobel ridge the walker rides.
        let w = 64, h = 64
        var pixels = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let v: Float = x < 32 ? 0.2 : 0.7
                let base = (y * w + x) * 4
                pixels[base] = v
                pixels[base + 1] = v
                pixels[base + 2] = v
                pixels[base + 3] = 1
            }
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        plane = try XCTUnwrap(metal.device.makeTexture(descriptor: d))
        try pixels.withUnsafeBytes {
            plane.replace(
                region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: w * 16)
        }
    }

    // MARK: the folded key (pure)

    func testFoldedKeyDistinguishesThresholdsAndPrefixes() {
        let low = PipeCoordinator.FollowEdgesRidgeCache.key(prefixHash: 7, edgeThreshold: 0.25)
        let high = PipeCoordinator.FollowEdgesRidgeCache.key(prefixHash: 7, edgeThreshold: 0.4)
        XCTAssertNotEqual(low, high, "same prefixHash, different threshold = two keys")
        XCTAssertNotEqual(
            low, PipeCoordinator.FollowEdgesRidgeCache.key(prefixHash: 8, edgeThreshold: 0.25),
            "different prefixHash = different key")
        // Deterministic round trip.
        XCTAssertEqual(
            low, PipeCoordinator.FollowEdgesRidgeCache.key(prefixHash: 7, edgeThreshold: 0.25))
    }

    // MARK: LRU eviction (explicit recency order, limit 8)

    func testLRUEvictsLeastRecentBeyondEight() {
        var cache = PipeCoordinator.FollowEdgesRidgeCache()
        func graph(_ seed: UInt64) -> RidgeGraph {
            var g = RidgeGraph(high: Float(seed))
            g.chains = [RidgeChain(vertices: [SIMD2(Double(seed), 0)])]
            return g
        }
        for seed in 1...8 {
            cache.insert(graph(UInt64(seed)), key: UInt64(seed))
        }
        XCTAssertEqual(cache.count, 8)
        // Touch key 2 (refresh to front), then insert 9: key 1 is the LRU.
        _ = cache.graph(for: 2)
        cache.refresh(key: 2)
        cache.insert(graph(9), key: 9)
        XCTAssertNil(cache.graph(for: 1), "the least-recent entry evicted")
        XCTAssertNotNil(cache.graph(for: 2), "the refreshed entry survives")
        XCTAssertNotNil(cache.graph(for: 9))
        XCTAssertEqual(cache.count, 8, "the limit holds")
    }

    // MARK: the injection seam + the carrier contract

    func testEdgeMapFieldInjectsRidgesAndThresholdDragAvoidsGPURerun() async throws {
        let surfaceA = PipeCoordinator.FollowEdgesSurface(
            plane: plane, imageID: UUID(), prefixHash: 42, edgeThreshold: 0.25)
        let first = await coordinator.edgeMapField(for: surfaceA)
        XCTAssertNotNil(first?.ridges, "the carrier injects the ridge graph")
        XCTAssertEqual(first?.ridges?.high, 0.25)
        XCTAssertEqual(coordinator.followEdgesEdgeMapRuns, 1)
        XCTAssertEqual(coordinator.followEdgesRidgeExtractions, 1)

        // Repeat fetch: both caches hit — zero GPU passes, zero extractions.
        let repeated = await coordinator.edgeMapField(for: surfaceA)
        XCTAssertEqual(repeated?.ridges, first?.ridges, "byte-identical carrier")
        XCTAssertEqual(coordinator.followEdgesEdgeMapRuns, 1)
        XCTAssertEqual(coordinator.followEdgesRidgeExtractions, 1)

        // Threshold drag at the SAME prefixHash: the FIELD cache serves the
        // GPU plane (零阈折 — no rerun), the ridge cache re-extracts.
        let surfaceB = PipeCoordinator.FollowEdgesSurface(
            plane: plane, imageID: UUID(), prefixHash: 42, edgeThreshold: 0.4)
        let dragged = await coordinator.edgeMapField(for: surfaceB)
        XCTAssertEqual(dragged?.ridges?.high, 0.4, "the fresh threshold stamps the graph")
        XCTAssertEqual(coordinator.followEdgesEdgeMapRuns, 1, "拖阈不重跑 GPU pass")
        XCTAssertEqual(coordinator.followEdgesRidgeExtractions, 2)
    }

    // MARK: strength never reaches the key or the extraction (E1)

    func testFollowStrengthDoesNotAffectCarrierOrWalk() async throws {
        let surface = PipeCoordinator.FollowEdgesSurface(
            plane: plane, imageID: UUID(), prefixHash: 7, edgeThreshold: 0.25)
        let fetched = await coordinator.edgeMapField(for: surface)
        let field = try XCTUnwrap(fetched)
        // The carrier carries no strength anywhere: two walks on the SAME
        // injected field with different strengths take identical chains on
        // this junction-free scene (the key face is pinned by the pure-key
        // test above).
        let loose = FollowEdges.streamline(
            seed: MaskPoint(x: 0.5, y: 0.5), field: field,
            params: FollowEdgesParams(edgeThreshold: 0.25, followStrength: 0.2))
        let tight = FollowEdges.streamline(
            seed: MaskPoint(x: 0.5, y: 0.5), field: field,
            params: FollowEdgesParams(edgeThreshold: 0.25, followStrength: 0.8))
        XCTAssertEqual(loose, tight, "junction-free scene: strength cannot bend the walk")
        XCTAssertEqual(coordinator.followEdgesRidgeExtractions, 1)
    }
}

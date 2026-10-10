@testable import LightamerCore
import Metal
import XCTest

/// Plan M2-7-1 T6 (KD-6; M2MASK-05, D-M2-7-CONTEXT-4) — the Follow-Edges
/// walker goldens on SYNTHETIC edge fields (the CPU walker is pure, so the
/// scenes construct EdgeMapField directly), the .snap degrade branch, the
/// empty-map degrade, determinism, and one GPU smoke pass of the
/// `mask_edge_map` kernel (luma Sobel magnitude, threshold-pre
/// normalization).
final class FollowEdgesTests: XCTestCase {

    // MARK: synthetic fields

    /// A vertical ridge at x = `edgeX` with a ±1.5 px falloff.
    private func verticalRidgeField(
        width: Int = 64, height: Int = 64, edgeX: Int
    ) -> EdgeMapField {
        var values = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                values[y * width + x] = max(0, 1 - abs(Float(x - edgeX)) / 1.5)
            }
        }
        return EdgeMapField(width: width, height: height, values: values)
    }

    /// The L corner: horizontal ridge y = 32 for x ≥ 32, vertical ridge
    /// x = 32 for y ≥ 32 (both with a ±1.5 px falloff).
    private func cornerField(width: Int = 64, height: Int = 64) -> EdgeMapField {
        var values = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let horizontal: Float = x >= 32 ? max(0, 1 - abs(Float(y - 32)) / 1.5) : 0
                let vertical: Float = y >= 32 ? max(0, 1 - abs(Float(x - 32)) / 1.5) : 0
                values[y * width + x] = max(horizontal, vertical)
            }
        }
        return EdgeMapField(width: width, height: height, values: values)
    }

    /// Deterministic low-amplitude ripple (below every sane threshold).
    private func rippleField(width: Int = 64, height: Int = 64) -> EdgeMapField {
        var values = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                values[y * width + x] = 0.05 + 0.05 * sin(Float(x) * 0.7) * cos(Float(y) * 0.9)
            }
        }
        return EdgeMapField(width: width, height: height, values: values)
    }

    private func pixel(_ p: MaskPoint, _ field: EdgeMapField) -> SIMD2<Double> {
        SIMD2(Double(p.x) * Double(field.width - 1), Double(p.y) * Double(field.height - 1))
    }

    // MARK: scene 1 — the straight edge

    func testStreamlineFollowsStraightEdge() {
        let field = verticalRidgeField(edgeX: 32)
        let seed = MaskPoint(x: Float(32) / 63, y: 0.6)
        let chain = FollowEdges.streamline(
            seed: seed, field: field,
            params: FollowEdgesParams(edgeThreshold: 0.25, followStrength: 0.5))

        // V2 point-count gate recalibrated (M4-2-01): the adaptive
        // resampling emits ~4px spacing on straight runs — the measured
        // count on this 64px ridge is 16 (was the V1 ≥30 step-per-pixel
        // gate; recalibration recorded in M4-2-01 DECISIONS).
        XCTAssertGreaterThanOrEqual(chain.count, 12, "the chain spans the ridge")
        var maxY = 0.0, minY = 1.0
        for point in chain {
            let px = pixel(point, field)
            XCTAssertEqual(px.x, 32, accuracy: 2.0, "every point hugs the ridge")
            maxY = max(maxY, px.y)
            minY = min(minY, px.y)
        }
        XCTAssertLessThanOrEqual(minY, 6, "the walk reaches the top boundary")
        XCTAssertGreaterThanOrEqual(maxY, 57, "…and the bottom boundary (双步进)")
    }

    // MARK: scene 2 — the corner bend

    func testStreamlineTurnsTheCorner() {
        let field = cornerField()
        // Seed mid-horizontal-arm: the walk must round (32,32) into the
        // vertical arm. The L bend is a degree-2 vertex (no junction), so
        // followStrength (the V2 junction gate) is not consumed here —
        // the value rides along unchanged from the V1 era.
        let seed = MaskPoint(x: Float(55) / 63, y: Float(32) / 63)
        let chain = FollowEdges.streamline(
            seed: seed, field: field,
            params: FollowEdgesParams(edgeThreshold: 0.25, followStrength: 0.25))

        // V2 point-count gate recalibrated: measured 17 (bends densify to
        // 0.75px around the corner, straights ~4px).
        XCTAssertGreaterThanOrEqual(chain.count, 12)
        // The corner is visited (within the tolerance band).
        let corner = SIMD2(32.0, 32.0)
        let minCornerDistance = chain.map { p in
            let px = pixel(p, field)
            return hypot(px.x - corner.x, px.y - corner.y)
        }.min() ?? 1e30
        XCTAssertLessThanOrEqual(minCornerDistance, 3.0, "the walk reaches the corner")
        // …and continues INTO the vertical arm (y well past the corner).
        let maxPointY = chain.map { pixel($0, field).y }.max() ?? 0
        XCTAssertGreaterThanOrEqual(maxPointY, 45, "the walk bends into the vertical arm")
        // Every point stays on the L (one of the two arms, tolerance band).
        for p in chain {
            let px = pixel(p, field)
            let onL = abs(px.x - 32) <= 3 || abs(px.y - 32) <= 3
            XCTAssertTrue(onL, "the chain never leaves the L: \(px)")
        }
    }

    // MARK: scene 3 — noise below threshold degrades to the empty chain

    func testNoiseFieldDegradesToEmptyChain() {
        let field = rippleField()
        let chain = FollowEdges.streamline(
            seed: MaskPoint(x: 0.5, y: 0.5), field: field,
            params: FollowEdgesParams(edgeThreshold: 0.25))
        XCTAssertTrue(chain.isEmpty, "no edge above threshold → the empty-chain degrade")
    }

    // MARK: the degradations + the .snap branch

    func testEmptyAndNilFieldsDegradeToEmpty() {
        XCTAssertTrue(FollowEdges.streamline(
            seed: MaskPoint(x: 0.5, y: 0.5), field: nil,
            params: FollowEdgesParams()).isEmpty, "nil map → empty chain")
        XCTAssertTrue(FollowEdges.streamline(
            seed: MaskPoint(x: 0.5, y: 0.5),
            field: EdgeMapField(width: 8, height: 8, values: [Float](repeating: 0, count: 64)),
            params: FollowEdgesParams()).isEmpty, "all-zero map → empty chain")
        XCTAssertTrue(FollowEdges.snap(
            seed: MaskPoint(x: 0.5, y: 0.5), field: nil,
            params: FollowEdgesParams()).isEmpty, "snap: nil map → empty chain")
    }

    func testSnapModeReturnsTheSeedAndNearestEdge() {
        let field = verticalRidgeField(edgeX: 40)
        let seed = MaskPoint(x: Float(30) / 63, y: 0.3)
        let chain = FollowEdges.snap(
            seed: seed, field: field,
            params: FollowEdgesParams(edgeThreshold: 0.25))
        XCTAssertEqual(chain.count, 2, "snap = [seed, target] — straight stamps between")
        XCTAssertEqual(chain[0], seed)
        let target = pixel(chain[1], field)
        XCTAssertEqual(target.x, 40, accuracy: 1.5, "the target snaps onto the ridge")
    }

    func testModeDispatcherRoutesBothCases() {
        let field = verticalRidgeField(edgeX: 40)
        let seed = MaskPoint(x: Float(40) / 63, y: 0.5)
        let streamline = FollowEdges.chain(
            seed: seed, field: field,
            params: FollowEdgesParams(mode: .streamline))
        let snap = FollowEdges.chain(
            seed: seed, field: field, params: FollowEdgesParams(mode: .snap))
        XCTAssertGreaterThan(streamline.count, 2, ".streamline runs the walker")
        XCTAssertEqual(snap.count, 2, ".snap runs the two-point degrade shape")
    }

    // MARK: determinism (the pure-function contract)

    func testWalkerIsPureSameInputSameOutput() {
        let field = cornerField()
        let seed = MaskPoint(x: Float(55) / 63, y: Float(32) / 63)
        let params = FollowEdgesParams(edgeThreshold: 0.25, followStrength: 0.5)
        let first = FollowEdges.streamline(seed: seed, field: field, params: params)
        let second = FollowEdges.streamline(seed: seed, field: field, params: params)
        XCTAssertEqual(first, second, "same input → point-identical chain")
    }

    // MARK: M4-2-01 V2 walker goldens (arc / bridge crossing / fuse / degrade)

    /// The arc: the walk rides the curved crest with subpixel radial accuracy.
    func testStreamlineWalksTheArc() {
        let w = 48, h = 48
        var values = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                guard x >= 20, y >= 20 else { continue }
                let r = hypot(Double(x - 20), Double(y - 20))
                values[y * w + x] = Float(max(0, 1 - abs(r - 20) / 1.5))
            }
        }
        let chain = FollowEdges.streamline(
            seed: MaskPoint(x: Float(40) / 47, y: Float(20) / 47),
            field: EdgeMapField(width: w, height: h, values: values),
            params: FollowEdgesParams(edgeThreshold: 0.25))
        XCTAssertGreaterThanOrEqual(chain.count, 4, "the arc walks (measured 5)")
        for point in chain {
            let px = pixel(point, EdgeMapField(width: w, height: h, values: values))
            let radius = hypot(px.x - 20, px.y - 20)
            XCTAssertEqual(radius, 20, accuracy: 1.5, "the chain hugs the arc")
        }
    }

    /// The bridge crossing: an INJECTED graph with a recorded ≤3px bridge —
    /// the walk continues onto the bridged chain without re-gating (the
    /// alignment gate already passed at extraction, checker E1).
    func testStreamlineCrossesBridgeOnInjectedGraph() {
        // Field is geometry-only here (the V2 walk consumes the graph); the
        // painted crest gives the seed something to attach to.
        let field = verticalRidgeField(width: 64, height: 16, edgeX: 10)
        var graph = RidgeGraph(high: 0.25)
        let chainA = RidgeChain(vertices: (2...20).map { SIMD2(Double($0), 8.0) })
        let chainB = RidgeChain(vertices: (23...40).map { SIMD2(Double($0), 8.0) })
        graph.chains = [chainA, chainB]
        graph.bridges = [RidgeBridge(chainA: 0, endA: 1, chainB: 1, endB: 0)]
        RidgeExtract.buildLookups(&graph)
        let chain = FollowEdges.streamline(
            seed: MaskPoint(x: Float(10) / 63, y: 0.5),
            field: field.withRidges(graph),
            params: FollowEdgesParams(edgeThreshold: 0.25))
        XCTAssertGreaterThanOrEqual(chain.count, 8, "the walk spans both chains")
        let xs = chain.map { Double($0.x) * 63.0 }
        XCTAssertLessThanOrEqual((xs.min() ?? 99), 4, "reaches chain A's far end")
        XCTAssertGreaterThanOrEqual((xs.max() ?? -1), 39, "crosses the bridge into chain B")
    }

    /// The chain fuse: the withdrawn params field, now the walker-internal
    /// 256 constant (checker M1) — a 2000px ridge emits at most 256 points.
    func testStreamlineFuseCapsAt256() {
        let w = 8, h = 2000
        var values = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w { values[y * w + x] = max(0, 1 - abs(Float(x - 4)) / 1.5) }
        }
        let chain = FollowEdges.streamline(
            seed: MaskPoint(x: 0.5, y: 0.5),
            field: EdgeMapField(width: w, height: h, values: values),
            params: FollowEdgesParams())
        XCTAssertEqual(chain.count, 256, "the fuse caps the emitted chain")
    }

    /// The no-attachment degrade: a seed far from any ridge (path A miss +
    /// path B snap miss) yields the empty chain — V1-verbatim semantics.
    func testStreamlineDegradesWhenNoRidgeNearby() {
        let chain = FollowEdges.streamline(
            seed: MaskPoint(x: 5.0 / 63, y: 5.0 / 63),
            field: verticalRidgeField(edgeX: 32),
            params: FollowEdgesParams())
        XCTAssertTrue(chain.isEmpty, "no ridge within the 8px reach → empty")
    }

    /// The junction ring crossing: a seed on one arm walks THROUGH the
    /// crossing onto the collinear continuation (greedy strongest, cos 1.0
    /// beats the perpendicular branches) — the extracted ring topology is
    /// traversed transparently.
    func testStreamlineCrossesJunctionRing() {
        var values = [Float](repeating: 0, count: 64 * 64)
        for y in 0..<64 {
            for x in 0..<64 {
                let horizontal: Float = (16...48).contains(x)
                    ? max(0, 1 - abs(Float(y - 32)) / 1.5) : 0
                let vertical: Float = (16...48).contains(y)
                    ? max(0, 1 - abs(Float(x - 32)) / 1.5) : 0
                values[y * 64 + x] = max(horizontal, vertical)
            }
        }
        let chain = FollowEdges.streamline(
            seed: MaskPoint(x: Float(20) / 63, y: Float(32) / 63),
            field: EdgeMapField(width: 64, height: 64, values: values),
            params: FollowEdgesParams(edgeThreshold: 0.25, followStrength: 0.0))
        var minX = 100.0, maxX = -100.0
        for point in chain {
            let px = pixel(point, EdgeMapField(width: 64, height: 64, values: values))
            XCTAssertEqual(px.y, 32, accuracy: 1.5, "the through-walk stays on the arm")
            minX = min(minX, px.x)
            maxX = max(maxX, px.x)
        }
        XCTAssertLessThanOrEqual(minX, 18, "the walk passes the crossing leftward")
        // Measured 45 (the last emission lands within one spacing of the
        // arm's end — the 4px straight-run bound).
        XCTAssertGreaterThanOrEqual(maxX, 44, "…and rightward (greedy straight-through)")
    }

    /// The carrier contract at Core level (checker E1): lazy in-chain
    /// extraction == injected-carrier walk, and a THRESHOLD-STALE carrier is
    /// refused (the walk re-extracts at its own threshold).
    func testInjectedRidgesMatchLazyAndStaleCarrierIsRefused() {
        var field = verticalRidgeField(edgeX: 32)
        let seed = MaskPoint(x: Float(32) / 63, y: 0.6)
        let lazy = FollowEdges.streamline(
            seed: seed, field: field, params: FollowEdgesParams())
        let injected = FollowEdges.streamline(
            seed: seed,
            field: field.withRidges(RidgeExtract.graph(from: field, high: 0.25)),
            params: FollowEdgesParams())
        XCTAssertEqual(lazy, injected, "injected == lazy (byte-identical walk)")

        let stale = FollowEdges.streamline(
            seed: seed,
            field: field.withRidges(RidgeExtract.graph(from: field, high: 0.25)),
            params: FollowEdgesParams(edgeThreshold: 0.4))
        let fresh = FollowEdges.streamline(
            seed: seed, field: field, params: FollowEdgesParams(edgeThreshold: 0.4))
        XCTAssertEqual(stale, fresh, "stale-threshold carrier refused → fresh extraction")
    }

    /// The `.snap` frozen baseline: three scenes pinned to exact constants —
    /// the behavioral nail on the zero-diff face (snap body untouched).
    func testSnapFrozenConstants() {
        let a = FollowEdges.snap(
            seed: MaskPoint(x: Float(30) / 63, y: 0.3),
            field: verticalRidgeField(edgeX: 40),
            params: FollowEdgesParams(edgeThreshold: 0.25))
        XCTAssertEqual(a.count, 2)
        XCTAssertEqual(a[0].x, 0.476190478, accuracy: 1e-6)
        XCTAssertEqual(a[0].y, 0.300000012, accuracy: 1e-6)
        XCTAssertEqual(a[1].x, 0.634920657, accuracy: 1e-6)
        XCTAssertEqual(a[1].y, 0.111111112, accuracy: 1e-6)

        let b = FollowEdges.snap(
            seed: MaskPoint(x: Float(32) / 63, y: 0.6),
            field: verticalRidgeField(edgeX: 32),
            params: FollowEdgesParams(edgeThreshold: 0.25))
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(b[0].x, 0.507936537, accuracy: 1e-6)
        XCTAssertEqual(b[0].y, 0.600000024, accuracy: 1e-6)
        XCTAssertEqual(b[1].x, 0.507936537, accuracy: 1e-6)
        XCTAssertEqual(b[1].y, 0.412698418, accuracy: 1e-6)

        let c = FollowEdges.snap(
            seed: MaskPoint(x: Float(55) / 63, y: Float(32) / 63),
            field: cornerField(),
            params: FollowEdgesParams(edgeThreshold: 0.25))
        XCTAssertEqual(c.count, 2)
        XCTAssertEqual(c[0].x, 0.873015881, accuracy: 1e-6)
        XCTAssertEqual(c[0].y, 0.507936537, accuracy: 1e-6)
        XCTAssertEqual(c[1].x, 0.682539701, accuracy: 1e-6)
        XCTAssertEqual(c[1].y, 0.507936537, accuracy: 1e-6)
    }

    // MARK: the GPU kernel smoke pass

    func testEdgeMapKernelSmokePass() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        let w = 32, h = 32
        // A vertical step in the below plane: left half 0.2, right half 0.7
        // (luma step → the Sobel ridge at the step column).
        let below = try makeRGBA(w, h, metal: metal) { x, _ in x < 16 ? 0.2 : 0.7 }
        let edge = try await FollowEdges.edgeMap(below: below, metal: metal)
        let values = readR32(edge, metal: metal)
        // The ridge column reads high; the flats read ~0.
        let ridge = Double(values[(10 * w) + 16])
        let flatLeft = Double(values[(10 * w) + 3])
        let flatRight = Double(values[(10 * w) + 29])
        XCTAssertGreaterThan(ridge, 0.25, "the step column carries the magnitude")
        XCTAssertLessThan(flatLeft, 0.01, "flat regions ~0")
        XCTAssertLessThan(flatRight, 0.01, "flat regions ~0")
        print("[M2-7-1] edge kernel: ridge=\(ridge) flats=\(flatLeft)/\(flatRight)")
    }

    /// L014: getBytes does not wait for in-flight encoders — fence first
    /// (sync helper: waitUntilCompleted is unavailable in async contexts).
    private func readR32(_ texture: any MTLTexture, metal: MetalContext) -> [Float] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        var values = [Float](repeating: -1, count: texture.width * texture.height)
        values.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0)
        }
        return values
    }

    private func makeRGBA(
        _ w: Int, _ h: Int, metal: MetalContext, value: (Int, Int) -> Float
    ) throws -> any MTLTexture {
        var pixels = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let v = value(x, y)
                pixels[(y * w + x) * 4 + 0] = v
                pixels[(y * w + x) * 4 + 1] = v
                pixels[(y * w + x) * 4 + 2] = v
                pixels[(y * w + x) * 4 + 3] = 1
            }
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: d))
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: w * 16)
        }
        return texture
    }
}

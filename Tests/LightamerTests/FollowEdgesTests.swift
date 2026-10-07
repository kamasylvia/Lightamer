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

        XCTAssertGreaterThanOrEqual(chain.count, 30, "the chain spans the ridge")
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
        // Seed mid-horizontal-arm, heading −x: the walk must round (32,32)
        // into the vertical arm.
        let seed = MaskPoint(x: Float(55) / 63, y: Float(32) / 63)
        // Lower momentum (tangent-dominant): the corner rotation completes
        // before the stop gate's pixel rounding can drop the walker off
        // the ridge flank.
        let chain = FollowEdges.streamline(
            seed: seed, field: field,
            params: FollowEdgesParams(
                edgeThreshold: 0.25, followStrength: 0.25, stepPixels: 1.0))

        XCTAssertGreaterThanOrEqual(chain.count, 20)
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

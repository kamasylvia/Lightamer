@testable import LightamerCore
import XCTest

/// Plan M4-2-01 T1 (KD-1) — the ridge-extractor stage goldens on synthetic
/// edge fields: NMS (crest kept / flanks suppressed / the pinned asymmetric
/// tie convention), hysteresis (weak-by-connectivity in, isolated weak out),
/// linking (L bend → one chain; cross → junction with degree recording),
/// bridging (≤3px gaps join, >3px stay split), subpixel centroid (δ ≤ 0.3px
/// on a symmetric ridge + the 1.5px clamp), and the double-run bit-identity.
/// The Steger 1D-Taylor A/B leg lives here too (test-file-only — OQ-1).
final class RidgeExtractTests: XCTestCase {

    // MARK: fixtures

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

    /// A horizontal ridge band [x0, x1] at y = `ridgeY` (±1.5 px falloff).
    private func painted(
        _ base: EdgeMapField, segments: [(x0: Int, x1: Int, y: Int)]
    ) -> EdgeMapField {
        var values = base.values
        let w = base.width, h = base.height
        for seg in segments {
            for y in 0..<h {
                for x in 0..<w {
                    let dist: Float
                    if x < seg.x0 { dist = hypot(Float(seg.x0 - x), Float(y - seg.y)) }
                    else if x > seg.x1 { dist = hypot(Float(x - seg.x1), Float(y - seg.y)) }
                    else { dist = abs(Float(y - seg.y)) }
                    values[y * w + x] = max(values[y * w + x], max(0, 1 - dist / 1.5))
                }
            }
        }
        return EdgeMapField(width: w, height: h, values: values)
    }

    private let high: Float = 0.25

    // MARK: stage ③ — NMS

    func testNMSKeepsCrestSuppressesFlanks() {
        let field = verticalRidgeField(edgeX: 32)
        let s = RidgeExtract.gaussianSmooth(field)
        let g = RidgeExtract.gradients(of: s, width: 64, height: 64)
        let o = RidgeExtract.orientations(of: g, width: 64, height: 64)
        let candidates = RidgeExtract.nmsCandidates(
            smoothed: s, orientation: o, width: 64, height: 64,
            low: Double(high) * RidgeExtract.hysteresisRatio)
        for y in 0..<64 {
            XCTAssertTrue(candidates[y * 64 + 32], "crest column survives at y=\(y)")
            if y > 2, y < 61 { // away from the vertical falloff caps
                XCTAssertFalse(candidates[y * 64 + 31], "left flank suppressed at y=\(y)")
                XCTAssertFalse(candidates[y * 64 + 33], "right flank suppressed at y=\(y)")
            }
        }
    }

    /// The pinned asymmetric tie convention: a perfectly symmetric two-row
    /// plateau resolves to ONE surviving row — the row whose along-orientation
    /// (+e) neighbor is the falling flank (strict side). Deterministic.
    func testNMSTieResolvesToASingleRow() {
        // Horizontal ridge: rows 31 and 32 both 1.0, ±1.5 falloff, uniform in x.
        var values = [Float](repeating: 0, count: 64 * 64)
        for y in 0..<64 {
            for x in 0..<64 {
                let dy = min(abs(Float(y - 31)), abs(Float(y - 32)))
                values[y * 64 + x] = max(0, 1 - dy / 1.5)
            }
        }
        let field = EdgeMapField(width: 64, height: 64, values: values)
        let s = RidgeExtract.gaussianSmooth(field)
        let g = RidgeExtract.gradients(of: s, width: 64, height: 64)
        let o = RidgeExtract.orientations(of: g, width: 64, height: 64)
        let candidates = RidgeExtract.nmsCandidates(
            smoothed: s, orientation: o, width: 64, height: 64,
            low: Double(high) * RidgeExtract.hysteresisRatio)
        for x in 4..<60 {
            XCTAssertFalse(candidates[31 * 64 + x], "plateau row A suppressed at x=\(x)")
            XCTAssertTrue(candidates[32 * 64 + x], "plateau row B kept (strict +e side) at x=\(x)")
        }
    }

    // MARK: stage ④ — hysteresis

    func testHysteresisWeakSectionJoinsStrongSeedsIsolatedWeakDropped() {
        // One vertical ridge (x=32) whose amplitude dips to 0.2 (below high,
        // above low) across rows 20..40: the weak crest section joins the
        // chain via connectivity to the strong rows; an isolated weak blob
        // (no strong seed) is dropped entirely.
        var values = [Float](repeating: 0, count: 64 * 64)
        for y in 0..<64 {
            let amplitude: Float = (20..<40).contains(y) ? 0.2 : 1.0
            for x in 0..<64 {
                values[y * 64 + x] = amplitude * max(0, 1 - abs(Float(x - 32)) / 1.5)
            }
        }
        // Isolated weak 2×2 blob (no strong seed anywhere near).
        for (y, x) in [(8, 8), (8, 9), (9, 8), (9, 9)] {
            values[y * 64 + x] = 0.3
        }
        let field = EdgeMapField(width: 64, height: 64, values: values)
        let s = RidgeExtract.gaussianSmooth(field)
        let g = RidgeExtract.gradients(of: s, width: 64, height: 64)
        let o = RidgeExtract.orientations(of: g, width: 64, height: 64)
        let low = Double(high) * RidgeExtract.hysteresisRatio
        let candidates = RidgeExtract.nmsCandidates(
            smoothed: s, orientation: o, width: 64, height: 64, low: low)
        let domain = RidgeExtract.hysteresis(
            candidates: candidates, smoothed: s, width: 64, height: 64, high: Double(high))

        XCTAssertTrue(domain[10 * 64 + 32], "strong crest enters")
        XCTAssertTrue(domain[30 * 64 + 32], "weak mid-section joins via connectivity")
        XCTAssertTrue(domain[50 * 64 + 32], "second strong section enters")
        XCTAssertFalse(
            domain[8 * 64 + 8] || domain[8 * 64 + 9] || domain[9 * 64 + 8] || domain[9 * 64 + 9],
            "isolated weak blob never enters (no strong seed)")
    }

    // MARK: stage ⑤ — linking + junction recording

    func testLinkingLCornerSingleChainNoJunction() {
        var values = [Float](repeating: 0, count: 64 * 64)
        for y in 0..<64 {
            for x in 0..<64 {
                let horizontal: Float = x >= 32 ? max(0, 1 - abs(Float(y - 32)) / 1.5) : 0
                let vertical: Float = y >= 32 ? max(0, 1 - abs(Float(x - 32)) / 1.5) : 0
                values[y * 64 + x] = max(horizontal, vertical)
            }
        }
        let graph = RidgeExtract.graph(
            from: EdgeMapField(width: 64, height: 64, values: values), high: high)
        XCTAssertEqual(graph.chains.count, 1, "the L is ONE connected polyline")
        XCTAssertEqual(graph.junctions.count, 0, "a degree-2 bend is not a junction")
        XCTAssertTrue(graph.bridges.isEmpty)
        XCTAssertEqual(graph.chains[0].vertices.first?.x.rounded(), 63, "row-major first endpoint")
        XCTAssertEqual(graph.chains[0].vertices.last?.y.rounded(), 63, "…bends to the far end")
    }

    func testLinkingCrossRecordsJunctionDegree() {
        // A plus-cross: horizontal ridge y=32 x=16..48, vertical x=32 y=16..48.
        // Value-NMS thins the crossing to a small ring (the center pixel is a
        // plateau along every arm — intrinsic to ridge NMS), so the pinned
        // asserts are TOPOLOGY-level: connectedness, junction degrees at the
        // crossing, and the four arm tips reached (observed-topology golden).
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
        let graph = RidgeExtract.graph(
            from: EdgeMapField(width: 64, height: 64, values: values), high: high)
        XCTAssertGreaterThanOrEqual(graph.junctions.count, 1, "the crossing records junctions")

        // Every chain links into the graph (junction attachment or bridge).
        var linked = Set<Int>()
        for junction in graph.junctions {
            for att in junction.attachments { linked.insert(att.chain) }
        }
        for bridge in graph.bridges {
            linked.insert(bridge.chainA)
            linked.insert(bridge.chainB)
        }
        XCTAssertEqual(linked.count, graph.chains.count, "no orphan chains")

        // All junctions sit at the crossing (within 2px of the center) with
        // degree ≥ 3, each attachment a distinct chain end at that junction.
        for junction in graph.junctions {
            let dx = junction.position.x - 32.0, dy = junction.position.y - 32.0
            XCTAssertLessThanOrEqual(
                (dx * dx + dy * dy).squareRoot(), 2.0,
                "junction at the crossing: \(junction.position)")
            XCTAssertGreaterThanOrEqual(junction.attachments.count, 3)
            let ends = Set(junction.attachments.map { ChainEndKey(chain: $0.chain, end: $0.end) })
            XCTAssertEqual(ends.count, junction.attachments.count)
        }

        // The four arm tips are reached by the extracted chains.
        let allPoints = graph.chains.flatMap(\.vertices)
        func distanceToTip(_ p: SIMD2<Double>, _ tip: SIMD2<Double>) -> Double {
            (p - tip).x * (p - tip).x + (p - tip).y * (p - tip).y
        }
        for tip in [SIMD2(16.0, 32.0), SIMD2(48.0, 32.0), SIMD2(32.0, 16.0), SIMD2(32.0, 48.0)] {
            let minDist2 = allPoints.map { distanceToTip($0, tip) }.min() ?? 1e30
            XCTAssertLessThanOrEqual(
                minDist2.squareRoot(), 1.5, "arm tip reached: \(tip)")
        }
    }

    // MARK: stage ⑤ — bridging

    func testBridgeJoinsThreePixelGapNotBeyond() {
        // Pure pairing pass on hand-built collinear chains (the σ0.9 smoothing
        // already merges small straight gaps in painted fixtures, so the gate
        // logic is pinned at its own level — the walker-level bridge crossing
        // rides the fragmented-scene golden in the T3 matrix).
        let chainA = RidgeChain(vertices: (10...28).map { SIMD2(Double($0), 32.0) })
        let chainB = RidgeChain(vertices: (31...50).map { SIMD2(Double($0), 32.0) })
        let bridges = RidgeExtract.pairBridges(chains: [chainA, chainB], junctionAttached: [])
        XCTAssertEqual(bridges.count, 1, "the 3px gap bridges (≤ B)")
        if let bridge = bridges.first {
            XCTAssertNotEqual(bridge.chainA, bridge.chainB, "the bridge joins the two segments")
        }

        // Same geometry with a 6px gap: no bridge.
        let chainC = RidgeChain(vertices: (34...50).map { SIMD2(Double($0), 32.0) })
        let none = RidgeExtract.pairBridges(chains: [chainA, chainC], junctionAttached: [])
        XCTAssertTrue(none.isEmpty, "> 3px gaps stay split")

        // Misaligned ends (one chain perpendicular): the alignment gate refuses.
        let chainD = RidgeChain(vertices: (31...50).map { SIMD2(28.0, Double($0)) })
        let refused = RidgeExtract.pairBridges(chains: [chainA, chainD], junctionAttached: [])
        XCTAssertTrue(refused.isEmpty, "perpendicular ends never bridge")

        // Junction-attached ends are not free: no bridge even at zero distance.
        let attached: Set<ChainEndKey> = [ChainEndKey(chain: 0, end: 1)]
        let reserved = RidgeExtract.pairBridges(
            chains: [chainA, chainB], junctionAttached: attached)
        XCTAssertTrue(reserved.isEmpty, "junction-attached ends are reserved")
    }

    // MARK: stage ⑥ — subpixel centroid

    func testCentroidOnSymmetricRidgeWithinThirdOfPixel() {
        let field = verticalRidgeField(edgeX: 32)
        let graph = RidgeExtract.graph(from: field, high: high)
        XCTAssertEqual(graph.chains.count, 1)
        for vertex in graph.chains[0].vertices {
            XCTAssertLessThanOrEqual(abs(vertex.x - 32), 0.3, "δ ≤ 0.3px on the crest")
        }
    }

    func testCentroidClampsToOneAndHalfPixel() {
        // Micro-field: the profile along +x at row 2 yields w = [0,0,0.8,0,2.9]
        // → raw δ = 1.57 → clamped to 1.5. The orientation is hand-set +x.
        let w = 16, h = 5
        var s = [Double](repeating: 0.0, count: w * h)
        let profile: [Double] = [0.1, 0.1, 0.9, 0.1, 3.0] // k = -2...+2 at x=6...10
        for (i, v) in profile.enumerated() { s[2 * w + 6 + i] = v }
        var o = [SIMD2<Double>](repeating: SIMD2(1.0, 0.0), count: w * h)
        var graph = RidgeGraph(high: high)
        graph.chains = [RidgeChain(vertices: [SIMD2(8.0, 2.0)])]
        RidgeExtract.refineCentroids(
            &graph, smoothed: s, orientation: o, width: w, height: h,
            low: Double(high) * RidgeExtract.hysteresisRatio)
        let vertex = graph.chains[0].vertices[0]
        XCTAssertEqual(vertex.x, 9.5, accuracy: 1e-9, "raw δ 1.57 clamps to 1.5")
        XCTAssertEqual(vertex.y, 2.0, accuracy: 1e-9)
        _ = o
    }

    // MARK: determinism (the pure-function contract)

    func testExtractionIsBitIdenticalAcrossRuns() {
        var values = [Float](repeating: 0, count: 64 * 64)
        for y in 0..<64 {
            for x in 0..<64 {
                let horizontal: Float = x >= 32 ? max(0, 1 - abs(Float(y - 32)) / 1.5) : 0
                let vertical: Float = y >= 32 ? max(0, 1 - abs(Float(x - 32)) / 1.5) : 0
                values[y * 64 + x] = max(horizontal, vertical)
            }
        }
        let field = EdgeMapField(width: 64, height: 64, values: values)
        let first = RidgeExtract.graph(from: field, high: high)
        let second = RidgeExtract.graph(from: field, high: high)
        XCTAssertEqual(first, second, "same (field, threshold) → identical graph")
    }

    // MARK: Steger 1D-Taylor A/B leg (test-file-only reference — OQ-1)

    /// Steger's 1D Taylor displacement δ = −d1/d2 on the normal profile
    /// (classic 3-tap derivatives, |d2| guard) vs the production centroid —
    /// evidence of centroid quality, generous band, NOT a gate (OQ-1: Steger
    /// never ships).
    func testCentroidAgainstStegerTaylorDisplacement() {
        let field = verticalRidgeField(edgeX: 32)
        let s = RidgeExtract.gaussianSmooth(field)
        let g = RidgeExtract.gradients(of: s, width: 64, height: 64)
        let o = RidgeExtract.orientations(of: g, width: 64, height: 64)
        let graph = RidgeExtract.graph(from: field, high: high)
        XCTAssertFalse(graph.chains.isEmpty, "the ridge extracts")
        var maxDeviation = 0.0
        for vertex in graph.chains[0].vertices {
            let x = Int(vertex.x.rounded()), y = Int(vertex.y.rounded())
            let n = o[y * 64 + x]
            let p = SIMD2(Double(x), Double(y))
            func profile(_ k: Double) -> Double {
                RidgeExtract.bilinear(s, width: 64, height: 64, p + SIMD2(k * n.x, k * n.y))
            }
            let d1 = (profile(1) - profile(-1)) / 2
            let d2 = profile(1) - 2 * profile(0) + profile(-1)
            guard abs(d2) > 1e-9 else { continue }
            let taylor = -d1 / d2
            let shift = vertex - p
            let centroidShift = shift.x * n.x + shift.y * n.y
            maxDeviation = max(maxDeviation, abs(taylor - centroidShift))
        }
        XCTAssertLessThanOrEqual(
            maxDeviation, 0.5,
            "centroid stays within the Taylor displacement evidence band (measured \(maxDeviation))")
        print("[M4-2-01] Steger-Taylor vs centroid max deviation: \(maxDeviation)")
    }
}

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
            smoothed: s, raw: field.values, orientation: o, width: 64, height: 64,
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
            smoothed: s, raw: field.values, orientation: o, width: 64, height: 64,
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
        // Isolated weak 2×2 blob (no strong seed anywhere near; raw 0.2 is
        // above low but below the 0.25 high → candidate-only, dropped).
        for (y, x) in [(8, 8), (8, 9), (9, 8), (9, 9)] {
            values[y * 64 + x] = 0.2
        }
        let field = EdgeMapField(width: 64, height: 64, values: values)
        let s = RidgeExtract.gaussianSmooth(field)
        let g = RidgeExtract.gradients(of: s, width: 64, height: 64)
        let o = RidgeExtract.orientations(of: g, width: 64, height: 64)
        let low = Double(high) * RidgeExtract.hysteresisRatio
        let candidates = RidgeExtract.nmsCandidates(
            smoothed: s, raw: field.values, orientation: o, width: 64, height: 64, low: low)
        let domain = RidgeExtract.hysteresis(
            candidates: candidates, raw: field.values, width: 64, height: 64, high: Double(high))

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


/// 2D helpers for the matrix fixtures and gates (all local to the tests).
private func matrixDistToPolyline(_ p: SIMD2<Double>, _ poly: [SIMD2<Double>]) -> Double {
    var best = 1e30
    for i in 0..<(poly.count - 1) {
        let a = poly[i], b = poly[i + 1]
        let ab = b - a
        let len2 = ab.x * ab.x + ab.y * ab.y
        let t = len2 > 0 ? max(0, min(1, (((p - a).x * ab.x + (p - a).y * ab.y) / len2))) : 0
        let proj = a + ab * t
        let d = p - proj
        best = min(best, (d.x * d.x + d.y * d.y).squareRoot())
    }
    return best
}

/// Arc-span coverage: the chain's projected extent along the truth polyline
/// over its total length (the walk must SPAN the ridge, not just touch it).
private func matrixCoverage(_ chain: [SIMD2<Double>], along poly: [SIMD2<Double>]) -> Double {
    var arc: [Double] = [0]
    for i in 1..<poly.count {
        let d = poly[i] - poly[i - 1]
        arc.append(arc[i - 1] + (d.x * d.x + d.y * d.y).squareRoot())
    }
    let total = arc.last ?? 0
    guard total > 0 else { return 0 }
    var minS = 1e30, maxS = -1e30
    for p in chain {
        var bestS = 0.0, bestD = 1e30
        for i in 0..<(poly.count - 1) {
            let a = poly[i], b = poly[i + 1]
            let ab = b - a
            let len2 = ab.x * ab.x + ab.y * ab.y
            let t = len2 > 0 ? max(0, min(1, (((p - a).x * ab.x + (p - a).y * ab.y) / len2))) : 0
            let proj = a + ab * t
            let d = p - proj
            let dist = (d.x * d.x + d.y * d.y).squareRoot()
            if dist < bestD { bestD = dist; bestS = arc[i] + t * len2.squareRoot() }
        }
        minS = min(minS, bestS); maxS = max(maxS, bestS)
    }
    return (maxS - minS) / total
}

/// Distance-painted ridge fixture (the /1.5 fat falloff).
private func matrixPaint(
    _ truth: [SIMD2<Double>], amplitude: Double = 1.0, falloff: Double = 1.5,
    w: Int = 64, h: Int = 64
) -> EdgeMapField {
    var values = [Float](repeating: 0, count: w * h)
    for y in 0..<h {
        for x in 0..<w {
            let p = SIMD2(Double(x), Double(y))
            var dist = 1e30
            for i in 0..<(truth.count - 1) {
                let a = truth[i], b = truth[i + 1]
                let ab = b - a
                let len2 = ab.x * ab.x + ab.y * ab.y
                let t = len2 > 0 ? max(0, min(1, (((p - a).x * ab.x + (p - a).y * ab.y) / len2))) : 0
                let proj = a + ab * t
                let d = p - proj
                dist = min(dist, (d.x * d.x + d.y * d.y).squareRoot())
            }
            values[y * w + x] = Float(max(0, amplitude * (1 - dist / falloff)))
        }
    }
    return EdgeMapField(width: w, height: h, values: values)
}

/// 8-connected single-pixel line (1px crest — no dual-track ladders).
private func matrixBresenham(_ from: SIMD2<Int>, _ to: SIMD2<Int>) -> [SIMD2<Int>] {
    var pts: [SIMD2<Int>] = []
    var x0 = from.x, y0 = from.y
    let dx = abs(to.x - x0), dy = -abs(to.y - y0)
    let sx = x0 < to.x ? 1 : -1, sy = y0 < to.y ? 1 : -1
    var err = dx + dy
    while true {
        pts.append(SIMD2(x0, y0))
        if x0 == to.x && y0 == to.y { break }
        let e2 = 2 * err
        if e2 >= dy { err += dy; x0 += sx }
        if e2 <= dx { err += dx; y0 += sy }
    }
    return pts
}

private func matrixStamp(
    _ pixels: [SIMD2<Int>], amplitude: Float, into values: inout [Float], w: Int, h: Int
) {
    for p in pixels where p.x >= 0 && p.y >= 0 && p.x < w && p.y < h {
        values[p.y * w + p.x] = max(values[p.y * w + p.x], amplitude)
    }
}

/// Walk quality gate: every emitted point within `hugGate` px of the truth
/// and the arc-span coverage ≥ `coverageGate`. Measured bands (M4-2-01
/// DECISIONS §2): the worst scene hugs at 0.235px (texture) and the worst
/// coverage is 0.90 (bridged gap) — the plan's 0.75px / 80% gates hold
/// WITHOUT recalibration.
private func matrixAssertWalk(
    _ field: EdgeMapField, truths: [[SIMD2<Double>]], seed: MaskPoint,
    strength: Double = 0.5, direction: Float = 1,
    hugGate: Double = 0.75, coverageGate: Double = 0.8,
    file: StaticString = #filePath, line: UInt = #line
) -> [MaskPoint] {
    let chain = FollowEdges.streamline(
        seed: seed, field: field,
        params: FollowEdgesParams(
            edgeThreshold: 0.25, followStrength: Float(strength), direction: direction))
    let W = Double(field.width - 1), H = Double(field.height - 1)
    var hug = 0.0
    var pts: [SIMD2<Double>] = []
    for p in chain {
        let px = SIMD2(Double(p.x) * W, Double(p.y) * H)
        pts.append(px)
        hug = max(hug, truths.map { matrixDistToPolyline(px, $0) }.min() ?? 1e30)
    }
    XCTAssertLessThanOrEqual(
        hug, hugGate, "walk hugs the truth polyline (measured \(hug))",
        file: file, line: line)
    let cov = truths.map { matrixCoverage(pts, along: $0) }.max() ?? 0
    XCTAssertGreaterThanOrEqual(
        cov, coverageGate, "walk spans the truth arc (measured \(cov))",
        file: file, line: line)
    return chain
}

// Scenes 1-3 (straight / arc / L) — truth-distance + coverage gates.
func testMatrixStraightArcAndLStayOnTruth() {
    let straight = matrixPaint([SIMD2(32, 2), SIMD2(32, 62)])
    matrixAssertWalk(
        straight, truths: [[SIMD2(32, 2), SIMD2(32, 62)]],
        seed: MaskPoint(x: Float(32) / 63, y: 0.6))

    var arcVals = [Float](repeating: 0, count: 48 * 48)
    var arcTruth: [SIMD2<Double>] = []
    for i in 0...20 {
        let t = Double(i) / 20 * Double.pi / 2
        arcTruth.append(SIMD2(20 + 20 * cos(t), 20 + 20 * sin(t)))
    }
    for y in 0..<48 {
        for x in 0..<48 {
            guard x >= 20, y >= 20 else { continue }
            let r = hypot(Double(x - 20), Double(y - 20))
            arcVals[y * 48 + x] = Float(max(0, 1 - abs(r - 20) / 1.5))
        }
    }
    matrixAssertWalk(
        EdgeMapField(width: 48, height: 48, values: arcVals), truths: [arcTruth],
        seed: MaskPoint(x: Float(40) / 47, y: Float(20) / 47))

    var lv = [Float](repeating: 0, count: 64 * 64)
    for y in 0..<64 {
        for x in 0..<64 {
            let horizontal: Float = x >= 32 ? max(0, 1 - abs(Float(y - 32)) / 1.5) : 0
            let vertical: Float = y >= 32 ? max(0, 1 - abs(Float(x - 32)) / 1.5) : 0
            lv[y * 64 + x] = max(horizontal, vertical)
        }
    }
    let lTruth = [SIMD2(63.0, 32.0), SIMD2(32.0, 32.0), SIMD2(32.0, 63.0)]
    matrixAssertWalk(
        EdgeMapField(width: 64, height: 64, values: lv), truths: [lTruth],
        seed: MaskPoint(x: Float(55) / 63, y: Float(32) / 63))
}

// Scene 4 — the T fork: followStrength {0.2, 0.8} walk differential
// (the gate is WALK-phase only: the extracted graphs are byte-equal).
func testMatrixTForkFollowStrengthDifferential() {
    var tv = [Float](repeating: 0, count: 64 * 64)
    matrixStamp((8...33).map { SIMD2($0, 32) }, amplitude: 1.0, into: &tv, w: 64, h: 64)
    matrixStamp(matrixBresenham(SIMD2(33, 32), SIMD2(44, 19)), amplitude: 1.0, into: &tv, w: 64, h: 64)
    matrixStamp(matrixBresenham(SIMD2(33, 32), SIMD2(38, 46)), amplitude: 1.0, into: &tv, w: 64, h: 64)
    let field = EdgeMapField(width: 64, height: 64, values: tv)

    // E1 machine-check: extraction never consumes strength.
    XCTAssertEqual(
        RidgeExtract.graph(from: field, high: 0.25),
        RidgeExtract.graph(from: field, high: 0.25))

    // strength 0.2: the walk extends onto the shallow branch (A, ~45°).
    let loose = FollowEdges.streamline(
        seed: MaskPoint(x: Float(20) / 63, y: Float(32) / 63), field: field,
        params: FollowEdgesParams(edgeThreshold: 0.25, followStrength: 0.2))
    let looseMaxX = loose.map { Double($0.x) * 63 }.max() ?? 0
    XCTAssertGreaterThanOrEqual(
        looseMaxX, 40, "the loose gate extends onto branch A (measured \(looseMaxX))")
    let looseYs = loose.map { Double($0.y) * 63 }
    XCTAssertLessThanOrEqual(
        looseYs.min() ?? 99, 24, "the walk climbs branch A (measured min y)")

    // strength 0.8: no branch clears the gate (A's continuation cosine
    // ≈ 0.72) — the walk stops at the junction (measured max x 32).
    let tight = FollowEdges.streamline(
        seed: MaskPoint(x: Float(20) / 63, y: Float(32) / 63), field: field,
        params: FollowEdgesParams(edgeThreshold: 0.25, followStrength: 0.8))
    let tightMaxX = tight.map { Double($0.x) * 63 }.max() ?? 0
    XCTAssertLessThanOrEqual(
        tightMaxX, 33, "the tight gate stops before the junction branches (measured \(tightMaxX))")
}

// Scene 5 — the bridged gap: two collinear 1px diagonals with a 1px
// gap; extraction records the bridge, the walk crosses it.
func testMatrixBridgedGapWalkCrosses() {
    var bv = [Float](repeating: 0, count: 64 * 64)
    matrixStamp(matrixBresenham(SIMD2(20, 40), SIMD2(32, 28)), amplitude: 1.0, into: &bv, w: 64, h: 64)
    matrixStamp(matrixBresenham(SIMD2(34, 26), SIMD2(46, 14)), amplitude: 1.0, into: &bv, w: 64, h: 64)
    let field = EdgeMapField(width: 64, height: 64, values: bv)
    let graph = RidgeExtract.graph(from: field, high: 0.25)
    XCTAssertEqual(graph.chains.count, 2, "the gap splits extraction")
    XCTAssertEqual(graph.bridges.count, 1, "the ≤3px gap bridges")
    matrixAssertWalk(
        field, truths: [[SIMD2(20.0, 40.0), SIMD2(46.0, 14.0)]],
        seed: MaskPoint(x: Float(20) / 63, y: Float(40) / 63))
}

// Scene 6 — parallel double ridge: deterministic single-side attach and
// direction-flipped output order over the SAME point set.
func testMatrixParallelRidgesSingleSideSelection() {
    var pv = matrixPaint([SIMD2(20, 4), SIMD2(20, 58)]).values
    let second = matrixPaint([SIMD2(28, 4), SIMD2(28, 58)])
    for i in 0..<pv.count { pv[i] = max(pv[i], second.values[i]) }
    let field = EdgeMapField(width: 64, height: 64, values: pv)
    let plus = FollowEdges.streamline(
        seed: MaskPoint(x: Float(24) / 63, y: 0.5), field: field,
        params: FollowEdgesParams(direction: 1))
    let minus = FollowEdges.streamline(
        seed: MaskPoint(x: Float(24) / 63, y: 0.5), field: field,
        params: FollowEdgesParams(direction: -1))
    XCTAssertFalse(plus.isEmpty)
    XCTAssertEqual(Set(plus), Set(minus), "same point set under direction flip")
    XCTAssertEqual(plus.first, minus.first, "the attach point leads both orders")
    // Single side: every point sits on ONE ridge column (±0.75px).
    let xs = plus.map { Double($0.x) * 63 }
    let ridge = xs.min() ?? 0
    for x in xs { XCTAssertEqual(x, ridge, accuracy: 0.75, "single-side selection") }
}

// Scene 7 — the low-contrast dip: the walk continues through the
// low..high section and stops at the sub-low break.
func testMatrixLowContrastDipContinuity() {
    var vv = [Float](repeating: 0, count: 64 * 64)
    for y in 0..<64 {
        let amplitude: Double = y < 20 ? 1.0 : (y < 40 ? 0.2 : (y < 44 ? 1.0 : 0.04))
        for x in 0..<64 {
            vv[y * 64 + x] = Float(amplitude * max(0, 1 - abs(Double(x - 32)) / 1.5))
        }
    }
    let chain = FollowEdges.streamline(
        seed: MaskPoint(x: Float(32) / 63, y: Float(10) / 63),
        field: EdgeMapField(width: 64, height: 64, values: vv),
        params: FollowEdgesParams())
    let ys = chain.map { Double($0.y) * 63 }
    let inDip = chain.filter { (25...35).contains(Double($0.y) * 63) }.count
    XCTAssertGreaterThanOrEqual(inDip, 2, "the weak section joins via hysteresis")
    XCTAssertLessThanOrEqual(
        ys.max() ?? 0, 43, "the sub-low break stops the walk (measured \(ys.max() ?? 0))")
    XCTAssertGreaterThanOrEqual(ys.max() ?? 0, 38, "…but only after the strong tail")
}

// Scene 8 — the texture background: deterministic noise below the
// candidate floor away from a hidden 1px diagonal ridge; the walk rides
// the ridge and a noise-region seed degrades to the empty chain.
func testMatrixTextureBackgroundRidge() {
    func noise(_ x: Int, _ y: Int) -> Double {
        let s = sin(Double(x) * 12.9898 + Double(y) * 78.233) * 43758.5453
        return s - floor(s)
    }
    let diag = [SIMD2(10.0, 50.0), SIMD2(54.0, 10.0)]
    var nv = [Float](repeating: 0, count: 64 * 64)
    for y in 0..<64 {
        for x in 0..<64 {
            let d = matrixDistToPolyline(SIMD2(Double(x), Double(y)), diag)
            let fade = min(1, max(0, (d - 2) / 4))
            nv[y * 64 + x] = Float(noise(x, y) * 0.12 * fade)
        }
    }
    matrixStamp(matrixBresenham(SIMD2(10, 50), SIMD2(54, 10)), amplitude: 0.85, into: &nv, w: 64, h: 64)
    let field = EdgeMapField(width: 64, height: 64, values: nv)
    matrixAssertWalk(
        field, truths: [diag], seed: MaskPoint(x: Float(30) / 63, y: Float(33) / 63))
    let noiseSeed = FollowEdges.streamline(
        seed: MaskPoint(x: Float(8) / 63, y: Float(8) / 63), field: field,
        params: FollowEdgesParams())
    XCTAssertTrue(noiseSeed.isEmpty, "a noise-region seed yields the empty chain")
}

// Scene 9 — the varying ridge: amplitude 0.3..1.0 along the crest; the
// extraction and walk are amplitude-independent.
func testMatrixVaryingAmplitudeRidge() {
    var av = [Float](repeating: 0, count: 64 * 64)
    for y in 0..<64 {
        for x in 0..<64 {
            let amp = 0.3 + 0.7 * Double(y) / 63
            av[y * 64 + x] = Float(amp * max(0, 1 - abs(Double(x - 32)) / 1.5))
        }
    }
    matrixAssertWalk(
        EdgeMapField(width: 64, height: 64, values: av),
        truths: [[SIMD2(32, 2), SIMD2(32, 62)]],
        seed: MaskPoint(x: Float(32) / 63, y: 0.6))
}

// The determinism gate across the WHOLE matrix: graphs + walks double-run
// byte-identical (Equatable deep-equality on every stored field).
func testMatrixDoubleRunBitIdentical() {
    func buildScenes() -> [(EdgeMapField, MaskPoint, Double)] {
        var scenes: [(EdgeMapField, MaskPoint, Double)] = []
        scenes.append((matrixPaint([SIMD2(32, 2), SIMD2(32, 62)]), MaskPoint(x: Float(32) / 63, y: 0.6), 0.5))
        var arcVals = [Float](repeating: 0, count: 48 * 48)
        for y in 0..<48 {
            for x in 0..<48 {
                guard x >= 20, y >= 20 else { continue }
                let r = hypot(Double(x - 20), Double(y - 20))
                arcVals[y * 48 + x] = Float(max(0, 1 - abs(r - 20) / 1.5))
            }
        }
        scenes.append((EdgeMapField(width: 48, height: 48, values: arcVals), MaskPoint(x: Float(40) / 47, y: Float(20) / 47), 0.5))
        var tv = [Float](repeating: 0, count: 64 * 64)
        matrixStamp((8...33).map { SIMD2($0, 32) }, amplitude: 1.0, into: &tv, w: 64, h: 64)
        matrixStamp(matrixBresenham(SIMD2(33, 32), SIMD2(44, 19)), amplitude: 1.0, into: &tv, w: 64, h: 64)
        matrixStamp(matrixBresenham(SIMD2(33, 32), SIMD2(38, 46)), amplitude: 1.0, into: &tv, w: 64, h: 64)
        scenes.append((EdgeMapField(width: 64, height: 64, values: tv), MaskPoint(x: Float(20) / 63, y: Float(32) / 63), 0.2))
        var bv = [Float](repeating: 0, count: 64 * 64)
        matrixStamp(matrixBresenham(SIMD2(20, 40), SIMD2(32, 28)), amplitude: 1.0, into: &bv, w: 64, h: 64)
        matrixStamp(matrixBresenham(SIMD2(34, 26), SIMD2(46, 14)), amplitude: 1.0, into: &bv, w: 64, h: 64)
        scenes.append((EdgeMapField(width: 64, height: 64, values: bv), MaskPoint(x: Float(20) / 63, y: Float(40) / 63), 0.5))
        return scenes
    }
    let scenes = buildScenes()
    for (i, scene) in scenes.enumerated() {
        let first = RidgeExtract.graph(from: scene.0, high: 0.25)
        let second = RidgeExtract.graph(from: scene.0, high: 0.25)
        XCTAssertEqual(first, second, "scene \(i): graph bit-identical")
        let params = FollowEdgesParams(edgeThreshold: 0.25, followStrength: Float(scene.2))
        let walkA = FollowEdges.streamline(seed: scene.1, field: scene.0, params: params)
        let walkB = FollowEdges.streamline(seed: scene.1, field: scene.0, params: params)
        XCTAssertEqual(walkA, walkB, "scene \(i): walk bit-identical")
        let injected = scene.0.withRidges(first)
        let walkC = FollowEdges.streamline(seed: scene.1, field: injected, params: params)
        XCTAssertEqual(walkA, walkC, "scene \(i): injected == lazy walk")
    }
}

// The snap-comparison track (KD-3③): the V2 first point and the snapTarget
// (12px arm) result hug the SAME edge — each within 2px of the truth
// polyline — and the whole chain stays within the brush radius (2.5px
// field-domain). The literal point-distance reading is unsatisfiable by
// construction: snapTarget returns the STRONGEST pixel within reach (ties
// → first in scan order), which on a uniform crest sits up to 12px
// ALONG the ridge from the nearest-vertex attach (measured 12.0); the
// plan's stated intent is the shared edge-hug geometry ("共享贴边几何").
func testSnapComparisonTrack() {
    var lv = [Float](repeating: 0, count: 64 * 64)
    for y in 0..<64 {
        for x in 0..<64 {
            let horizontal: Float = x >= 32 ? max(0, 1 - abs(Float(y - 32)) / 1.5) : 0
            let vertical: Float = y >= 32 ? max(0, 1 - abs(Float(x - 32)) / 1.5) : 0
            lv[y * 64 + x] = max(horizontal, vertical)
        }
    }
    let lField = EdgeMapField(width: 64, height: 64, values: lv)
    let lTruth = [SIMD2(63.0, 32.0), SIMD2(32.0, 32.0), SIMD2(32.0, 63.0)]
    let straight = matrixPaint([SIMD2(32, 2), SIMD2(32, 62)])
    let straightTruth = [SIMD2(32.0, 2.0), SIMD2(32.0, 62.0)]
    let cases: [(EdgeMapField, MaskPoint, [SIMD2<Double>], String)] = [
        (straight, MaskPoint(x: Float(32) / 63, y: 0.6), straightTruth, "straight"),
        (lField, MaskPoint(x: Float(55) / 63, y: Float(32) / 63), lTruth, "L"),
    ]
    for (field, seed, truth, label) in cases {
        let snap = FollowEdges.snap(
            seed: seed, field: field, params: FollowEdgesParams(edgeThreshold: 0.25))
        guard snap.count == 2 else {
            XCTFail("\(label): snap shape changed")
            continue
        }
        let chain = FollowEdges.streamline(
            seed: seed, field: field, params: FollowEdgesParams(edgeThreshold: 0.25))
        guard let first = chain.first else {
            XCTFail("\(label): empty walk")
            continue
        }
        let W = Double(field.width - 1), H = Double(field.height - 1)
        let fx = SIMD2(Double(first.x) * W, Double(first.y) * H)
        let snapTargetPx = SIMD2(Double(snap[1].x) * W, Double(snap[1].y) * H)
        _ = snapTargetPx
        XCTAssertLessThanOrEqual(
            matrixDistToPolyline(fx, truth), 2.0,
            "\(label): first point hugs the snapped edge (measured \(matrixDistToPolyline(fx, truth)))")
        let snapHug = matrixDistToPolyline(snapTargetPx, truth)
        XCTAssertLessThanOrEqual(
            snapHug, 2.0, "\(label): the snap result hugs the same edge")
        for p in chain {
            let px = SIMD2(Double(p.x) * W, Double(p.y) * H)
            XCTAssertLessThanOrEqual(
                matrixDistToPolyline(px, truth), 2.5,
                "\(label): the whole chain stays within the brush radius")
        }
    }
}
}

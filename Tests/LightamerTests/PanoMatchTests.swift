@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// PanoMatchTests (Plan M5-3-01 T2; KD-2/KD-3/KD-4) — the matching segment's
// hand-value set: the seed-121 RNG anchor + deterministic streams, the knn-2
// top-2 with the index tie-break, the Lowe ratio gate boundary rows, the DLT
// recovery of a known homography (≤1e-9), the RANSAC recovery under noise +
// double-run bit identity, the confidence formula truth table, the edge gate
// positive/negative rows, and the BFS component + the typed-failure prefixes.
// ─────────────────────────────────────────────────────────────────────────────

final class PanoMatchTests: XCTestCase {

    /// A 128-dim one-hot unit descriptor (the knn fixtures).
    private func oneHot(_ index: Int) -> PanoDescriptor {
        var vector = [Float](repeating: 0, count: 128)
        vector[index] = 1
        return PanoDescriptor(keypointIndex: 0, vector: vector)
    }

    private func elementWiseError(_ a: Mat3D, _ b: Mat3D) -> Double {
        var worst = 0.0
        for i in 0..<3 {
            for j in 0..<3 {
                worst = max(worst, abs(a[i, j] - b[i, j]))
            }
        }
        return worst
    }

    // MARK: - PanoRNG (KD-3)

    func testRNGSeedAnchorAndDeterministicStream() {
        // The Lumen determinism anchor (merge.py:220).
        XCTAssertEqual(PanoRNG.defaultSeed, 121)
        var first = PanoRNG(seed: 121)
        var second = PanoRNG(seed: 121)
        for _ in 0..<16 {
            XCTAssertEqual(first.next(), second.next())
            XCTAssertEqual(first.nextUniform(), second.nextUniform())
            XCTAssertEqual(first.nextInt(1000), second.nextInt(1000))
        }
        var third = PanoRNG(seed: 122)
        var firstAgain = PanoRNG(seed: 121)
        XCTAssertNotEqual(firstAgain.next(), third.next())
    }

    // MARK: - knn-2 (KD-2)

    func testKnn2Top2AndIndexTieBreak() {
        // Orthogonal one-hot trains: the self match scores distance 0, the
        // others √2 — the second-best tie among equals MUST break to the
        // lowest train index (two identical trains: best = the lower one).
        let trains: [PanoDescriptor] = (0..<8).map { oneHot($0) }
        let query = oneHot(3)
        let matches = PanoMatch.knn2(query: [query], train: trains)
        XCTAssertEqual(matches.count, 1)
        let match = matches[0]
        XCTAssertEqual(match.bestIndex, 3)
        XCTAssertEqual(match.bestDistance, 0, accuracy: 1e-6)
        XCTAssertEqual(match.secondIndex, 0, "tie must break to the lowest index")
        XCTAssertEqual(match.secondDistance, sqrt(2), accuracy: 1e-5)
        // Two IDENTICAL trains: the best must be the lower index.
        let duplicate = oneHot(5)
        let tiedMatches = PanoMatch.knn2(query: [query], train: [trains[3], duplicate])
        XCTAssertEqual(tiedMatches[0].bestIndex, 0)
        XCTAssertEqual(tiedMatches[0].secondIndex, 1)
        // Single-descriptor train: the second neighbor is absent.
        let lone = PanoMatch.knn2(query: [query], train: [trains[3]])
        XCTAssertEqual(lone[0].secondIndex, -1)
        XCTAssertTrue(lone[0].secondDistance.isInfinite)
    }

    // MARK: - Lowe ratio gate (KD-2)

    func testLoweRatioGateBoundary() {
        // The strict gate `best < 0.3 · second`: ratio 0.31 rejects,
        // ratio 0.29 accepts.
        let reject = PanoMatch2(
            queryIndex: 0, bestIndex: 1, secondIndex: 2,
            bestDistance: 0.2, secondDistance: 0.2 / 0.31)
        let accept = PanoMatch2(
            queryIndex: 0, bestIndex: 1, secondIndex: 2,
            bestDistance: 0.2, secondDistance: 0.2 / 0.29)
        let filtered = PanoMatch.ratioFilter([reject, accept])
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].secondDistance, 0.2 / 0.29)
        // A missing second neighbor keeps the match.
        let lone = PanoMatch2(
            queryIndex: 0, bestIndex: 1, secondIndex: -1,
            bestDistance: 0.5, secondDistance: .infinity)
        XCTAssertEqual(PanoMatch.ratioFilter([lone]).count, 1)
    }

    // MARK: - DLT (KD-4)

    func testDLTRecoversKnownHomography() throws {
        // An arbitrary projective map with h22 = 1 — exact data recovers H
        // element-wise to machine precision (a stale/transposed system
        // lands O(1) away, never 1e-9).
        let truth = Mat3D(
            0.936, -0.352, 12.0,
            0.2, 1.1, -5.0,
            0.0003, -0.0002, 1.0)
        var from: [(Double, Double)] = []
        var to: [(Double, Double)] = []
        for y in stride(from: 5.0, through: 95.0, by: 15.0) {
            for x in stride(from: 5.0, through: 95.0, by: 20.0) {
                from.append((x, y))
                to.append(truth.project(x, y))
            }
        }
        XCTAssertEqual(from.count, 35)
        let recovered = try XCTUnwrap(PanoMatch.homographyDLT(from: from, to: to))
        XCTAssertLessThanOrEqual(elementWiseError(recovered, truth), 1e-9)
    }

    // MARK: - RANSAC (KD-4)

    /// 35 jittered inliers + 20 outliers under the same truth homography.
    private func noisyCorrespondences() -> (truth: Mat3D, pairs: [PanoCorrespondence]) {
        let truth = Mat3D(
            0.936, -0.352, 12.0,
            0.2, 1.1, -5.0,
            0.0003, -0.0002, 1.0)
        var rng = PanoRNG(seed: 7919)
        var pairs: [PanoCorrespondence] = []
        for y in stride(from: 5.0, through: 95.0, by: 15.0) {
            for x in stride(from: 5.0, through: 95.0, by: 20.0) {
                let projected = truth.project(x, y)
                let noiseX = (rng.nextUniform() * 2 - 1) * 1.0
                let noiseY = (rng.nextUniform() * 2 - 1) * 1.0
                pairs.append(PanoCorrespondence(
                    x, y, projected.x + noiseX, projected.y + noiseY))
            }
        }
        for _ in 0..<20 {
            let x1 = rng.nextUniform() * 120
            let y1 = rng.nextUniform() * 120
            let x2 = rng.nextUniform() * 120
            let y2 = rng.nextUniform() * 120
            pairs.append(PanoCorrespondence(x1, y1, x2, y2))
        }
        return (truth, pairs)
    }

    func testRANSACRecoversUnderNoise() throws {
        let (truth, pairs) = noisyCorrespondences()
        var rng = PanoRNG(seed: 121)
        let homography = try XCTUnwrap(PanoMatch.ransacHomography(pairs, rng: &rng))
        XCTAssertGreaterThanOrEqual(
            homography.inliers.count, 33,
            "at least 33 of the 35 true inliers must survive (±1px jitter)")
        // The recovery band in the PROJECTION domain (the meaningful
        // accuracy measure for a near-affine truth: its perspective terms
        // are O(1e-4), so element-wise deltas absorb noise into huge
        // correlated h2 swings while projections stay put).
        var worst = 0.0
        for y in stride(from: 0.0, through: 100.0, by: 10.0) {
            for x in stride(from: 0.0, through: 100.0, by: 10.0) {
                let got = homography.homography.project(x, y)
                let want = truth.project(x, y)
                worst = max(worst, hypot(got.x - want.x, got.y - want.y))
            }
        }
        XCTAssertLessThanOrEqual(
            worst, 2.5, "projection-domain recovery band (±1px noise)")
        XCTAssertLessThanOrEqual(homography.iterations, 3000)
    }

    func testRANSACDoubleRunBitIdentity() throws {
        let (_, pairs) = noisyCorrespondences()
        var rngFirst = PanoRNG(seed: 121)
        var rngSecond = PanoRNG(seed: 121)
        let a = try XCTUnwrap(PanoMatch.ransacHomography(pairs, rng: &rngFirst))
        let b = try XCTUnwrap(PanoMatch.ransacHomography(pairs, rng: &rngSecond))
        // The single-RNG-stream contract: identical draw sequence → identical
        // model, inliers, and iteration count, BIT-identical.
        for i in 0..<3 {
            for j in 0..<3 {
                XCTAssertEqual(
                    a.homography[i, j].bitPattern, b.homography[i, j].bitPattern,
                    "RANSAC double run diverged at (\(i),\(j))")
            }
        }
        XCTAssertEqual(a.inliers, b.inliers)
        XCTAssertEqual(a.iterations, b.iterations)
    }

    // MARK: - Confidence formula + edge gate (KD-2)

    func testConfidenceFormulaTruthTable() {
        // The OpenCV detail form inliers/(8 + 0.3·matches) — hand values.
        let table: [(inliers: Int, matches: Int, confidence: Double)] = [
            (0, 0, 0.0),
            (8, 0, 1.0),
            (10, 40, 0.5),
            (10, 100, 10.0 / 38.0),
            (30, 300, 30.0 / 98.0),
            (100, 200, 100.0 / 68.0),
        ]
        for row in table {
            XCTAssertEqual(
                PanoMatch.matchConfidence(inliers: row.inliers, matches: row.matches),
                row.confidence, accuracy: 1e-12,
                "inliers \(row.inliers), matches \(row.matches)")
        }
    }

    func testEdgeGatePositiveNegative() {
        // confidence > 0.6 AND inliers >= 10 — both legs strict.
        XCTAssertTrue(PanoMatch.isValidEdge(confidence: 0.61, inliers: 10))
        XCTAssertTrue(PanoMatch.isValidEdge(confidence: 0.9, inliers: 25))
        XCTAssertFalse(PanoMatch.isValidEdge(confidence: 0.6, inliers: 100),
            "confidence == 0.6 must reject (strict >)")
        XCTAssertFalse(PanoMatch.isValidEdge(confidence: 0.7, inliers: 9),
            "inliers < 10 must reject")
        XCTAssertFalse(PanoMatch.isValidEdge(confidence: 0.59, inliers: 999))
    }

    // MARK: - Connectivity + typed vocabulary (KD-4)

    func testBFSComponentAndTypedPrefixes() {
        // Four images, only 0↔1 matched: the reference closure stays {0, 1}.
        var adjacency: [Set<Int>] = [[1], [0], [], []]
        XCTAssertEqual(
            PanoMatch.connectedComponent(imageCount: 4, adjacency: adjacency, reference: 0),
            [0, 1])
        // A fully connected chain closes over all four.
        adjacency = [[1], [0, 2], [1, 3], [2]]
        XCTAssertEqual(
            PanoMatch.connectedComponent(imageCount: 4, adjacency: adjacency, reference: 0),
            [0, 1, 2, 3])
        // The typed-failure canonical prefixes (KD-4 — the P3 zh mapping's
        // consumption contract).
        XCTAssertEqual(PanoMatch.FailurePrefix.alignment, "panorama alignment failed: ")
        XCTAssertEqual(PanoMatch.FailurePrefix.disconnected, "panorama images disconnected: ")
        XCTAssertEqual(PanoMatch.FailurePrefix.canvas, "panorama canvas invalid: ")
        let message = PanoMatch.FailurePrefix.disconnected + "2 of 4 images in the closure"
        XCTAssertTrue(message.hasPrefix("panorama images disconnected: "))
    }
}

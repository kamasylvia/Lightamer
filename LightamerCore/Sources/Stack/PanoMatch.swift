import Accelerate
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// PanoMatch (Plan M5-3-01 T2; KD-2/KD-3/KD-4) — the panorama matching
// segment: the seeded LCG, the BF knn-2 matcher with the Lowe ratio gate,
// the 4-point DLT homography, the RANSAC loop with adaptive iterations, the
// pair-confidence formula, the edge gate, and the reference BFS connectivity
// gate. Pure CPU, sequential, deterministic (G1's anchor).
//
// MIT ATTRIBUTION (CONVENTIONS 参考项目节): Portions derived from Lumen RAW
// (lumen-raw, MIT) — the MATCHING-SEGMENT PARAMETERS: the Lowe ratio 0.3
// (merge.py:227 `BestOf2NearestMatcher_create(False, .3, ...)`), the edge
// gate `confidence > .6 ∧ inliers ≥ 10` (merge.py:231-233), the RANSAC 3px
// threshold + 3000-iteration hard cap (the stack_transforms
// `ransacReprojThreshold=3, maxIters=3000` precedent, merge.py:62), the
// seed-121 RNG anchor (merge.py:220 `cv2.setRNGSeed(121)`), and the BFS
// connectivity gate from the reference frame (merge.py:235-238). Swift
// rewrite; OpenCV itself NEVER enters this repository.
//
// DETERMINISM (KD-3): every random decision draws from ONE PanoRNG stream —
// the RANSAC samples and the adaptive iteration accounting share it; the
// system RNG sources are banned from this file (the T6 grep gate, including
// the `\.random\(` low-level form per checker minor-4).
//
// CONFIDENCE FORMULA (KD-2; DECISIONS): `inliers / (8 + 0.3·matches)` — the
// OpenCV detail `MatchesInfo.confidence` form (HIGHER = better, bounded by
// 10/3 as matches→∞ — the merge.py:225-227 comment's own bound). The plan
// text's `1 −` prefix is a transcription slip: a 1−x form has upper bound 1
// and cannot carry the 10/3 bound, and `confidence > .6` as a KEEP gate
// only parses with the higher-is-better form.
// ─────────────────────────────────────────────────────────────────────────────

/// One query→train nearest-2 result (the top-2 by Euclidean distance over
/// root-normalized descriptors; ties break to the LOWER train index).
public struct PanoMatch2: Sendable, Equatable {
    public let queryIndex: Int
    public let bestIndex: Int
    public let secondIndex: Int
    public let bestDistance: Float
    public let secondDistance: Float

    public init(
        queryIndex: Int, bestIndex: Int, secondIndex: Int,
        bestDistance: Float, secondDistance: Float
    ) {
        self.queryIndex = queryIndex
        self.bestIndex = bestIndex
        self.secondIndex = secondIndex
        self.bestDistance = bestDistance
        self.secondDistance = secondDistance
    }
}

/// One RANSAC point pair (image-1 pixel → image-2 pixel, preview domain).
public struct PanoCorrespondence: Sendable {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }
}

/// The RANSAC outcome (the best model + its inlier correspondence indices).
public struct PanoHomographyEstimate: Sendable {
    public let homography: Mat3D
    public let inliers: [Int]
    public let iterations: Int

    public init(homography: Mat3D, inliers: [Int], iterations: Int) {
        self.homography = homography
        self.inliers = inliers
        self.iterations = iterations
    }
}

/// The 64-bit MMIX-family LCG (the HDRMergeMathTests/GradeKernelGoldenTests
/// test-fixture family, promoted to production for the panorama segment's
/// determinism anchor).
public struct PanoRNG: Sendable {
    /// The determinism anchor (merge.py:220 `cv2.setRNGSeed(121)` — a
    /// reproducibility pin for the RANSAC-class random process, NOT a
    /// statistical-quality claim).
    public static let defaultSeed: UInt64 = 121

    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public init() {
        self.init(seed: Self.defaultSeed)
    }

    /// One MMIX step: state = state·6364136223846793005 + 1442695040888963407.
    public mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    /// Uniform [0, 1) off the high 53 bits.
    public mutating func nextUniform() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Uniform integer [0, bound) (modulo form — the negligible bias is
    /// accepted for the RANSAC sample indices; determinism is the contract).
    public mutating func nextInt(_ bound: Int) -> Int {
        precondition(bound > 0, "nextInt bound must be positive")
        return Int(next() % UInt64(bound))
    }
}

public enum PanoMatch {

    // MARK: - Constants (KD-2/KD-4: file constants, NOT parameters)

    /// The typed-failure canonical prefixes (KD-4 — the P3 zh mapping's
    /// consumption contract; carriers are `AppError.invalidParameter`).
    public enum FailurePrefix {
        public static let alignment = "panorama alignment failed: "
        public static let disconnected = "panorama images disconnected: "
        public static let canvas = "panorama canvas invalid: "
    }

    /// The Lowe ratio gate (merge.py:227).
    public static let loweRatio = 0.3
    /// The edge confidence gate (merge.py:233 — strict >).
    public static let edgeConfidence = 0.6
    /// The edge minimum inlier count (merge.py:233).
    public static let edgeMinInliers = 10
    /// The RANSAC inlier threshold in preview pixels (merge.py:62 anchor).
    public static let ransacThreshold = 3.0
    /// The RANSAC iteration hard cap (merge.py:62 anchor).
    public static let ransacMaxIters = 3000
    /// The adaptive-iteration target confidence.
    public static let ransacConfidence = 0.999

    // MARK: - BF knn-2 (KD-2)

    /// Best-of-2 nearest neighbors over root-normalized descriptors: for
    /// unit vectors, Euclidean² = 2 − 2·dot, so the chunked vDSP matmul's
    /// dot products rank (and score) every pair; ties break to the LOWER
    /// train index (strict-> scan keeps the first maximum). Chunking keeps
    /// the dot matrix bounded (a 512-row chunk of 6000 trains ≈ 12 MB).
    public static func knn2(
        query: [PanoDescriptor], train: [PanoDescriptor]
    ) -> [PanoMatch2] {
        guard !query.isEmpty, !train.isEmpty else { return [] }
        let dimensions = PanoDescriptor.dimensions
        // The train matrix transposed ([dim × n]) — vDSP_mmul's B operand.
        var trainTransposed = [Float](repeating: 0, count: dimensions * train.count)
        for (index, descriptor) in train.enumerated() {
            for dimension in 0..<dimensions {
                trainTransposed[dimension * train.count + index] = descriptor.vector[dimension]
            }
        }
        let chunkSize = 512
        var results: [PanoMatch2] = []
        results.reserveCapacity(query.count)
        var chunkStart = 0
        while chunkStart < query.count {
            let rows = min(chunkSize, query.count - chunkStart)
            var a = [Float](repeating: 0, count: rows * dimensions)
            for row in 0..<rows {
                let vector = query[chunkStart + row].vector
                for dimension in 0..<dimensions {
                    a[row * dimensions + dimension] = vector[dimension]
                }
            }
            var dots = [Float](repeating: 0, count: rows * train.count)
            a.withUnsafeBufferPointer { aBuffer in
                trainTransposed.withUnsafeBufferPointer { bBuffer in
                    dots.withUnsafeMutableBufferPointer { cBuffer in
                        vDSP_mmul(
                            aBuffer.baseAddress!, 1,
                            bBuffer.baseAddress!, 1,
                            cBuffer.baseAddress!, 1,
                            vDSP_Length(rows), vDSP_Length(train.count),
                            vDSP_Length(dimensions))
                    }
                }
            }
            for row in 0..<rows {
                let base = row * train.count
                var bestIndex = 0
                var secondIndex = -1
                var bestDot = dots[base]
                var secondDot = -Float.infinity
                for column in 1..<train.count {
                    let dot = dots[base + column]
                    if dot > bestDot {
                        secondDot = bestDot
                        secondIndex = bestIndex
                        bestDot = dot
                        bestIndex = column
                    } else if dot > secondDot {
                        secondDot = dot
                        secondIndex = column
                    }
                }
                // Euclidean over unit vectors: d = √(2 − 2·dot) (clamped —
                // a dot can exceed 1 by an ulp).
                let bestDistance = sqrt(max(0, 2 - 2 * bestDot))
                let secondDistance = secondIndex >= 0
                    ? sqrt(max(0, 2 - 2 * secondDot)) : Float.infinity
                results.append(PanoMatch2(
                    queryIndex: chunkStart + row,
                    bestIndex: bestIndex,
                    secondIndex: secondIndex,
                    bestDistance: bestDistance,
                    secondDistance: secondDistance))
            }
            chunkStart += rows
        }
        return results
    }

    /// The Lowe ratio gate: keep the match when
    /// `bestDistance < ratio · secondDistance` (strict — the boundary row
    /// rejects). A missing second neighbor (single-descriptor train) keeps
    /// the best match.
    public static func ratioFilter(
        _ matches: [PanoMatch2], ratio: Double = PanoMatch.loweRatio
    ) -> [PanoMatch2] {
        matches.filter { match in
            guard match.secondIndex >= 0 else { return true }
            return Double(match.bestDistance) < ratio * Double(match.secondDistance)
        }
    }

    // MARK: - 4-point DLT (KD-4)

    /// The Hartley-normalized DLT homography (least-squares over all given
    /// pairs): symmetric isotropic normalization (centroid → origin, mean
    /// radius → √2) per image, the 2N×9 constraint matrix, the null vector
    /// = the smallest eigenvector of AᵀA (symmetric Jacobi — deterministic
    /// closed iteration), denormalized back and scaled to h₂₂ = 1.
    /// nil for < 4 points or a degenerate normalization (all points equal).
    public static func homographyDLT(
        from: [(Double, Double)], to: [(Double, Double)]
    ) -> Mat3D? {
        guard from.count >= 4, from.count == to.count else { return nil }
        guard let t1 = normalization(from), let t2 = normalization(to) else {
            return nil
        }
        var rows: [[Double]] = []
        rows.reserveCapacity(2 * from.count)
        for index in 0..<from.count {
            let p = t1.applied(from[index].0, from[index].1)
            let q = t2.applied(to[index].0, to[index].1)
            rows.append([p.x, p.y, 1, 0, 0, 0, -q.x * p.x, -q.x * p.y, -q.x])
            rows.append([0, 0, 0, p.x, p.y, 1, -q.y * p.x, -q.y * p.y, -q.y])
        }
        // M = AᵀA (9×9 symmetric), fixed accumulation order.
        var matrix = [Double](repeating: 0, count: 81)
        for row in rows {
            for i in 0..<9 {
                for j in 0..<9 {
                    matrix[i * 9 + j] += row[i] * row[j]
                }
            }
        }
        guard let (eigenvalues, eigenvectors) = symmetricEigen(matrix, size: 9) else {
            return nil
        }
        // The null direction = the eigenvector of the smallest eigenvalue.
        var smallest = 0
        for index in 1..<9 where eigenvalues[index] < eigenvalues[smallest] {
            smallest = index
        }
        var h = [Double](repeating: 0, count: 9)
        for i in 0..<9 {
            h[i] = eigenvectors[i * 9 + smallest]
        }
        let hn = Mat3D(h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8])
        guard let t2Inverse = t2.inverted() else { return nil }
        let homography = Mat3D.mul(Mat3D.mul(t2Inverse, hn), t1)
        // Scale to h₂₂ = 1 (guard the degenerate denominator by the largest
        // absolute component — a degenerate null vector never wins inliers).
        let pivot = homography[2, 2]
        if abs(pivot) > 1e-12 {
            return homography.scaled(by: 1.0 / pivot)
        }
        var largest = abs(homography[0, 0])
        for i in 0..<3 {
            for j in 0..<3 {
                largest = max(largest, abs(homography[i, j]))
            }
        }
        return abs(largest) > 1e-12 ? homography.scaled(by: 1.0 / largest) : homography
    }

    private static func normalization(
        _ points: [(Double, Double)]
    ) -> Mat3D? {
        var centroidX = 0.0
        var centroidY = 0.0
        for point in points {
            centroidX += point.0
            centroidY += point.1
        }
        centroidX /= Double(points.count)
        centroidY /= Double(points.count)
        var meanRadius = 0.0
        for point in points {
            meanRadius += hypot(point.0 - centroidX, point.1 - centroidY)
        }
        meanRadius /= Double(points.count)
        guard meanRadius > 1e-12 else { return nil }
        let scale = sqrt(2.0) / meanRadius
        return Mat3D(scale, 0, -scale * centroidX, 0, scale, -scale * centroidY, 0, 0, 1)
    }

    /// The symmetric Jacobi eigenvalue iteration (deterministic closed
    /// form): sweeps zero the largest off-diagonal until the off-diagonal
    /// Frobenius norm drops below 1e-14 or 100 sweeps elapse. Returns the
    /// eigenvalues (unordered) and the eigenvectors as columns in a
    /// row-major size×size matrix.
    static func symmetricEigen(
        _ matrix: [Double], size: Int
    ) -> (eigenvalues: [Double], eigenvectors: [Double])? {
        precondition(matrix.count == size * size, "eigen input size mismatch")
        var a = matrix
        var v = [Double](repeating: 0, count: size * size)
        for i in 0..<size {
            v[i * size + i] = 1
        }
        for _ in 0..<100 {
            // The largest |off-diagonal| element.
            var offNorm = 0.0
            var pivotRow = 0
            var pivotCol = 1
            var pivotAbs = 0.0
            for i in 0..<size {
                for j in (i + 1)..<size {
                    let value = abs(a[i * size + j])
                    offNorm += value * value
                    if value > pivotAbs {
                        pivotAbs = value
                        pivotRow = i
                        pivotCol = j
                    }
                }
            }
            if offNorm < 1e-28 {
                break
            }
            let apq = a[pivotRow * size + pivotCol]
            if abs(apq) < 1e-300 {
                continue
            }
            let app = a[pivotRow * size + pivotRow]
            let aqq = a[pivotCol * size + pivotCol]
            let theta = (aqq - app) / (2 * apq)
            let sign = theta >= 0 ? 1.0 : -1.0
            let t = sign / (abs(theta) + sqrt(theta * theta + 1))
            let c = 1 / sqrt(t * t + 1)
            let s = t * c
            // Apply the rotation to rows/cols pivotRow & pivotCol.
            for k in 0..<size {
                let akp = a[k * size + pivotRow]
                let akq = a[k * size + pivotCol]
                a[k * size + pivotRow] = c * akp - s * akq
                a[k * size + pivotCol] = s * akp + c * akq
            }
            for k in 0..<size {
                let apk = a[pivotRow * size + k]
                let aqk = a[pivotCol * size + k]
                a[pivotRow * size + k] = c * apk - s * aqk
                a[pivotCol * size + k] = s * apk + c * aqk
            }
            for k in 0..<size {
                let vkp = v[k * size + pivotRow]
                let vkq = v[k * size + pivotCol]
                v[k * size + pivotRow] = c * vkp - s * vkq
                v[k * size + pivotCol] = s * vkp + c * vkq
            }
        }
        var eigenvalues = [Double](repeating: 0, count: size)
        for i in 0..<size {
            eigenvalues[i] = a[i * size + i]
        }
        return (eigenvalues, v)
    }

    // MARK: - RANSAC (KD-4)

    /// RANSAC over the correspondence set: 4-point minimal samples from the
    /// SINGLE rng stream, forward-transfer inliers at `threshold` preview
    /// pixels, the best model by inlier count with the earliest-achieved
    /// tie-break, adaptive iteration target
    /// `log(1 − confidence)/log(1 − w⁴)` under the hard cap, one final
    /// least-squares refit over the winning inliers. nil when no model
    /// reaches 4 inliers.
    public static func ransacHomography(
        _ correspondences: [PanoCorrespondence],
        rng: inout PanoRNG,
        threshold: Double = PanoMatch.ransacThreshold,
        maxIterations: Int = PanoMatch.ransacMaxIters,
        confidence: Double = PanoMatch.ransacConfidence
    ) -> PanoHomographyEstimate? {
        let count = correspondences.count
        guard count >= 4 else { return nil }
        var bestInliers: [Int] = []
        var bestHomography: Mat3D?
        var iterationLimit = maxIterations
        var iteration = 0
        while iteration < iterationLimit {
            iteration += 1
            // Four distinct samples (fixed draw order — the stream is the
            // determinism contract).
            var sample: [Int] = []
            sample.reserveCapacity(4)
            while sample.count < 4 {
                let candidate = rng.nextInt(count)
                if !sample.contains(candidate) {
                    sample.append(candidate)
                }
            }
            let points = sample.map { correspondences[$0] }
            guard let candidateHomography = homographyDLT(
                from: points.map { ($0.x1, $0.y1) },
                to: points.map { ($0.x2, $0.y2) })
            else { continue }
            let inliers = inlierIndices(
                candidateHomography, correspondences: correspondences,
                threshold: threshold)
            if inliers.count > bestInliers.count {
                bestInliers = inliers
                bestHomography = candidateHomography
                // Adaptive limit: the four-point sampling probability
                // w⁴ (guarded against w = 1 → log 0).
                let w = Double(inliers.count) / Double(count)
                if w < 1 {
                    let needed = min(
                        Double(maxIterations),
                        ceil(log(1 - confidence) / log(1 - pow(w, 4))))
                    iterationLimit = min(
                        maxIterations, max(iteration, Int(needed)))
                } else {
                    iterationLimit = iteration
                }
            }
        }
        guard bestInliers.count >= 4, let bestModel = bestHomography else {
            return nil
        }
        // One least-squares refit over the winning inliers (no loop).
        let inlierPoints = bestInliers.map { correspondences[$0] }
        guard let refitted = homographyDLT(
            from: inlierPoints.map { ($0.x1, $0.y1) },
            to: inlierPoints.map { ($0.x2, $0.y2) })
        else {
            return PanoHomographyEstimate(
                homography: bestModel, inliers: bestInliers, iterations: iteration)
        }
        let refittedInliers = inlierIndices(
            refitted, correspondences: correspondences, threshold: threshold)
        if refittedInliers.count >= bestInliers.count {
            return PanoHomographyEstimate(
                homography: refitted, inliers: refittedInliers, iterations: iteration)
        }
        return PanoHomographyEstimate(
            homography: bestModel, inliers: bestInliers, iterations: iteration)
    }

    private static func inlierIndices(
        _ homography: Mat3D, correspondences: [PanoCorrespondence],
        threshold: Double
    ) -> [Int] {
        var inliers: [Int] = []
        inliers.reserveCapacity(correspondences.count)
        for (index, pair) in correspondences.enumerated() {
            let projected = homography.project(pair.x1, pair.y1)
            let residual = hypot(projected.x - pair.x2, projected.y - pair.y2)
            if residual.isFinite, residual <= threshold {
                inliers.append(index)
            }
        }
        return inliers
    }

    // MARK: - Edge confidence + gate (KD-2)

    /// The OpenCV detail pair confidence (HIGHER = better; bounded by 10/3
    /// as matches→∞ — see the header note): `inliers / (8 + 0.3·matches)`.
    public static func matchConfidence(inliers: Int, matches: Int) -> Double {
        Double(inliers) / (8.0 + 0.3 * Double(matches))
    }

    /// The Lumen edge gate (merge.py:231-233 semantics): a pair is a graph
    /// edge iff confidence > 0.6 AND inliers ≥ 10.
    public static func isValidEdge(confidence: Double, inliers: Int) -> Bool {
        confidence > PanoMatch.edgeConfidence && inliers >= PanoMatch.edgeMinInliers
    }

    // MARK: - Connectivity (KD-4)

    /// The reference-frame BFS closure over the undirected match graph
    /// (merge.py:235-238 semantics: loop until the closure fixpoint). The
    /// caller compares `component.count` against the image count and types
    /// the failure with `FailurePrefix.disconnected`.
    public static func connectedComponent(
        imageCount: Int, adjacency: [Set<Int>], reference: Int
    ) -> Set<Int> {
        precondition(adjacency.count == imageCount, "adjacency size mismatch")
        var connected: Set<Int> = [reference]
        var previous: Set<Int> = []
        while previous != connected {
            previous = connected
            for index in previous {
                connected.formUnion(adjacency[index])
            }
        }
        return connected
    }
}

extension Mat3D {
    /// Scalar scale (the DLT h₂₂ normalization's local helper).
    fileprivate func scaled(by factor: Double) -> Mat3D {
        Mat3D(
            m.0 * factor, m.1 * factor, m.2 * factor,
            m.3 * factor, m.4 * factor, m.5 * factor,
            m.6 * factor, m.7 * factor, m.8 * factor)
    }
}

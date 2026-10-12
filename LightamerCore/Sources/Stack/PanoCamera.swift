import Accelerate
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// PanoCamera (Plan M5-3-01 T3; KD-5) — the panorama camera segment: the
// focal-from-homography initial estimate, the single-focal + N-rotation
// Levenberg-Marquardt bundle adjustment (3N+1 parameters, Double internals,
// Accelerate dgesv linear solves), and the horizontal wave correction. Pure
// CPU, sequential, deterministic (G1's anchor).
//
// MIT ATTRIBUTION (CONVENTIONS 参考项目节): Portions derived from Lumen RAW
// (lumen-raw, MIT) — the CAMERA-SEGMENT STRUCTURE: the homography-based
// estimator + the ray bundle adjuster refining ONLY f + all R components
// (the 3×3 refinement mask with the first two rows open, merge.py:243-245),
// the horizontal wave correct (merge.py:246), and the median focal anchor
// for the multi-pair initial scale (merge.py:251). Swift rewrite; OpenCV
// detail API semantics read-only, code zero-copied.
//
// MODEL: each image has ONE rotation R (world→camera: cam_ray = R·world_dir)
// and the set shares a SINGLE focal f (square pixels, principal point at the
// optical center): K = diag(f, f, 1). COORDINATE CONTRACT: the pixel
// coordinates fed to every entry point here are CENTERED on the principal
// point (the M5-3-02 leg centers by the frame midline) — an un-centered H
// mixes principal-point terms into the h2 row and biases the focal estimate
// ~4-6× (the probe-pinned inflation). The reprojection residual is the
// CHORDAL ANGULAR error between matched rays' WORLD directions (the
// BundleAdjusterRay semantics): for a match (x₁ in image i, x₂ in image j)
// both rays lift to the unit sphere and the residual is Rᵀ·u₁ − Rᵀ·u₂ — the
// world side is load-bearing (R·u is the transpose family, whose fitted
// rotations come out transposed).
//
// GAUGE: pure-rotation cameras carry a global gauge freedom — replacing
// every Rᵢ by Q·Rᵢ leaves every pairwise ray constraint unchanged. The
// solver therefore recovers cameras UP TO a global rotation; callers anchor
// the gauge (e.g. on the reference frame) before comparing to truth (the
// G2 golden does exactly that). The focal is gauge-free.
//
// FAILURE TYPING (KD-5): a non-converging BA returns nil — the production
// leg maps it into the "panorama alignment failed: " typed family.
// ─────────────────────────────────────────────────────────────────────────────

/// The bundle-adjusted camera set (rotations are world→camera; the set is
/// defined up to the global gauge, see the header).
public struct PanoCameraSolution: Sendable {
    public let focal: Double
    public let rotations: [Mat3D]
    public let residualRMS: Double
    public let iterations: Int

    public init(focal: Double, rotations: [Mat3D], residualRMS: Double, iterations: Int) {
        self.focal = focal
        self.rotations = rotations
        self.residualRMS = residualRMS
        self.iterations = iterations
    }
}

/// One bundle-adjustment match bundle: the image pair + their inlier
/// correspondences (preview-domain pixels).
public struct PanoMatchBundle: Sendable {
    public let first: Int
    public let second: Int
    public let correspondences: [PanoCorrespondence]

    public init(first: Int, second: Int, correspondences: [PanoCorrespondence]) {
        self.first = first
        self.second = second
        self.correspondences = correspondences
    }
}

public enum PanoCamera {

    // MARK: - K construction (the Lumen camera.K() shape)

    /// K(f) = [f 0 0; 0 f 0; 0 0 1] — square pixels, principal point at the
    /// origin (the pixel coordinates are centered on the principal ray by
    /// the callers).
    public static func calibrationK(focal: Double) -> Mat3D {
        Mat3D(focal, 0, 0, 0, focal, 0, 0, 0, 1)
    }

    // MARK: - focal-from-homography (the classical closed form)

    /// The single-focal initial estimate from H = K R K⁻¹: with H's columns
    /// c₀, c₁ (c₂), the relation H·K = K·R gives R's first two columns as
    /// (c₀ₓ, c₀ᵧ, f·c₀_z) and (c₁ₓ, c₁ᵧ, f·c₁_z). Their orthogonality and
    /// equal norm yield two independent closed forms:
    ///   orthogonality:  f² = −(c₀ₓc₁ₓ + c₀ᵧc₁ᵧ) / (c₀_z·c₁_z)
    ///   equal norm:     f² = (|c₁_xy|² − |c₀_xy|²) / (c₀_z² − c₁_z²)
    /// All positive finite candidates are pooled and the MEDIAN is returned
    /// (deterministic; exact inputs make every candidate equal). nil when H
    /// carries no focal information (pure in-plane rotation → H = I: both
    /// denominators vanish) or no positive candidate exists.
    public static func focalFromHomography(_ homography: Mat3D) -> Double? {
        let c0 = (homography[0, 0], homography[1, 0], homography[2, 0])
        let c1 = (homography[0, 1], homography[1, 1], homography[2, 1])
        var candidates: [Double] = []
        let orthoDenominator = c0.2 * c1.2
        if abs(orthoDenominator) > 1e-12 {
            let f2 = -(c0.0 * c1.0 + c0.1 * c1.1) / orthoDenominator
            if f2.isFinite, f2 > 0 {
                candidates.append(sqrt(f2))
            }
        }
        let normDenominator = c0.2 * c0.2 - c1.2 * c1.2
        if abs(normDenominator) > 1e-12 {
            let f2 = ((c1.0 * c1.0 + c1.1 * c1.1)
                - (c0.0 * c0.0 + c0.1 * c0.1)) / normDenominator
            if f2.isFinite, f2 > 0 {
                candidates.append(sqrt(f2))
            }
        }
        guard !candidates.isEmpty else { return nil }
        return median(candidates)
    }

    /// The multi-pair initial focal: the median of the per-pair estimates
    /// (the merge.py:251 median anchor — robust to a single outlier pair).
    /// nil when no pair yields an estimate.
    public static func medianFocal(_ homographies: [Mat3D]) -> Double? {
        let estimates = homographies.compactMap { focalFromHomography($0) }
        guard !estimates.isEmpty else { return nil }
        return median(estimates)
    }

    /// The classical initial rotation from one pair homography (the
    /// HomographyBasedEstimator semantics): R = orthogonalize(K⁻¹·H·K) for
    /// CENTERED pixel coordinates and the given focal. This is the bundle
    /// adjustment's rotation seed — identity initialization descends into
    /// the transpose family of the chordal cost (an exact symmetry: the
    /// probe-pinned 2θ anchored error) and never reaches the true basin.
    /// nil when H's K⁻¹·H·K is degenerate (non-invertible H).
    public static func initialRotation(
        from homography: Mat3D, focal: Double
    ) -> Mat3D? {
        let k = calibrationK(focal: focal)
        guard let kInverse = k.inverted() else { return nil }
        let candidate = Mat3D.mul(Mat3D.mul(kInverse, homography), k)
        // Deterministic Gram-Schmidt over the rows (the projection's
        // nearest rotation).
        var rows = [
            (candidate[0, 0], candidate[0, 1], candidate[0, 2]),
            (candidate[1, 0], candidate[1, 1], candidate[1, 2]),
            (candidate[2, 0], candidate[2, 1], candidate[2, 2]),
        ]
        for r in 1..<3 {
            for q in 0..<r {
                let dot = rows[r].0 * rows[q].0 + rows[r].1 * rows[q].1
                    + rows[r].2 * rows[q].2
                rows[r].0 -= dot * rows[q].0
                rows[r].1 -= dot * rows[q].1
                rows[r].2 -= dot * rows[q].2
            }
        }
        for r in 0..<3 {
            let norm = sqrt(rows[r].0 * rows[r].0 + rows[r].1 * rows[r].1
                + rows[r].2 * rows[r].2)
            guard norm > 1e-12 else { return nil }
            rows[r].0 /= norm
            rows[r].1 /= norm
            rows[r].2 /= norm
        }
        return Mat3D(
            rows[0].0, rows[0].1, rows[0].2,
            rows[1].0, rows[1].1, rows[1].2,
            rows[2].0, rows[2].1, rows[2].2)
    }

    /// The median (odd → the middle; even → the mean of the two middles —
    /// the numpy.median convention).
    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let count = sorted.count
        guard count > 0 else { return 0 }
        if count % 2 == 1 {
            return sorted[count / 2]
        }
        return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
    }

    // MARK: - Rotation parameterization (Rodrigues)

    /// Axis-angle → rotation matrix (exact identity below 1e-12).
    public static func rotation(fromAxisAngle axisAngle: SIMD3<Double>) -> Mat3D {
        let theta = sqrt(
            axisAngle.x * axisAngle.x + axisAngle.y * axisAngle.y
                + axisAngle.z * axisAngle.z)
        guard theta > 1e-12 else { return Mat3D.identity }
        let k = axisAngle / theta
        let sinTheta = sin(theta)
        let cosTheta = cos(theta)
        let oneMinus = 1 - cosTheta
        return Mat3D(
            cosTheta + k.x * k.x * oneMinus,
            k.x * k.y * oneMinus - k.z * sinTheta,
            k.x * k.z * oneMinus + k.y * sinTheta,
            k.y * k.x * oneMinus + k.z * sinTheta,
            cosTheta + k.y * k.y * oneMinus,
            k.y * k.z * oneMinus - k.x * sinTheta,
            k.z * k.x * oneMinus - k.y * sinTheta,
            k.z * k.y * oneMinus + k.x * sinTheta,
            cosTheta + k.z * k.z * oneMinus)
    }

    /// Rotation matrix → axis-angle (the log map; near-identity returns the
    /// zero vector, near-π stays on the branch cut — the solver never
    /// travels that far from its initialization).
    public static func axisAngle(from rotation: Mat3D) -> SIMD3<Double> {
        let trace = rotation[0, 0] + rotation[1, 1] + rotation[2, 2]
        let cosTheta = min(max((trace - 1) / 2, -1), 1)
        let theta = acos(cosTheta)
        guard theta > 1e-9 else { return SIMD3(0, 0, 0) }
        let sinTheta = sin(theta)
        guard sinTheta > 1e-9 else { return SIMD3(0, 0, 0) }
        let scale = theta / (2 * sinTheta)
        return SIMD3(
            scale * (rotation[2, 1] - rotation[1, 2]),
            scale * (rotation[0, 2] - rotation[2, 0]),
            scale * (rotation[1, 0] - rotation[0, 1]))
    }

    /// The angle between two rotation matrices' relative frames (the
    /// gauge-invariant comparison metric, radians).
    public static func relativeAngle(_ a: Mat3D, _ b: Mat3D) -> Double {
        let relative = Mat3D.mul(a, b.inverted() ?? Mat3D.identity)
        return sqrt(
            axisAngle(from: relative).x * axisAngle(from: relative).x
                + axisAngle(from: relative).y * axisAngle(from: relative).y
                + axisAngle(from: relative).z * axisAngle(from: relative).z)
    }

    // MARK: - LM bundle adjustment (3N+1)

    /// Levenberg-Marquardt over p = [f, rotvec₁ … rotvec_N] (3N+1 scalars,
    /// Double internals): chordal angular residuals over all match bundles,
    /// a dense forward-difference Jacobian, the damped normal equations
    /// solved by dgesv, λ adaptive (÷3 on accept, ×10 on reject, fail past
    /// 1e12). SUCCESS = the fit meaningfully reduced the cost — the final
    /// cost sits ≤ (1 − improvementFloor)·initial — checked on EVERY exit
    /// path (the relative-decrease early exit, the λ explosion, or the
    /// iteration cap). An absolute RMS gate cannot work here: pixel-domain
    /// quantization floors the achievable angular residual at ~pixel/f
    /// (the probe-pinned all-nil), so the verdict is data-relative. nil
    /// (typed failure) when no meaningful fit was reached, or the inputs
    /// are empty.
    public static func bundleAdjust(
        matches: [PanoMatchBundle], imageCount: Int,
        initialFocal: Double, initialRotations: [Mat3D],
        maxIterations: Int = 50, tolerance: Double = 1e-10,
        improvementFloor: Double = 1e-6
    ) -> PanoCameraSolution? {
        guard imageCount >= 1, initialRotations.count == imageCount,
              !matches.isEmpty
        else { return nil }
        let parameterCount = 1 + 3 * imageCount

        // The parameter vector ⇄ cameras.
        func evaluate(_ p: [Double]) -> (residual: [Double], cost: Double) {
            let focal = max(p[0], 1e-6)
            var residual: [Double] = []
            let totalPairs = matches.reduce(0) { $0 + $1.correspondences.count }
            residual.reserveCapacity(totalPairs * 3)
            for bundle in matches {
                let ri = rotation(fromAxisAngle: SIMD3(
                    p[1 + 3 * bundle.first], p[2 + 3 * bundle.first],
                    p[3 + 3 * bundle.first]))
                let rj = rotation(fromAxisAngle: SIMD3(
                    p[1 + 3 * bundle.second], p[2 + 3 * bundle.second],
                    p[3 + 3 * bundle.second]))
                for pair in bundle.correspondences {
                    // K⁻¹(x, y, 1) = (x/f, y/f, 1); the WORLD direction of
                    // a camera ray is Rᵀ·u (cam = R·world — the stored
                    // world→camera convention). The chordal cost is
                    // invariant under the R ↔ Rᵀ family, so this side is
                    // load-bearing: R·u silently fits the transposed
                    // rotations (the probe-pinned 2θ anchored-error).
                    let d1 = SIMD3(pair.x1 / focal, pair.y1 / focal, 1)
                    let d2 = SIMD3(pair.x2 / focal, pair.y2 / focal, 1)
                    let lifted1 = rotate(ri.transposed(), d1)
                    let lifted2 = rotate(rj.transposed(), d2)
                    let n1 = lifted1.x * lifted1.x + lifted1.y * lifted1.y
                        + lifted1.z * lifted1.z
                    let n2 = lifted2.x * lifted2.x + lifted2.y * lifted2.y
                        + lifted2.z * lifted2.z
                    guard n1 > 1e-300, n2 > 1e-300 else { continue }
                    let ray1 = lifted1 / sqrt(n1)
                    let ray2 = lifted2 / sqrt(n2)
                    // Rays pointing backward carry no usable constraint —
                    // the deterministic exclusion keeps the residual at 0
                    // for them (z = the optical axis component).
                    if ray1.z <= 1e-9 || ray2.z <= 1e-9 {
                        residual.append(contentsOf: [0, 0, 0])
                        continue
                    }
                    let difference = ray1 - ray2
                    residual.append(contentsOf: [difference.x, difference.y, difference.z])
                }
            }
            var cost = 0.0
            for value in residual {
                cost += value * value
            }
            return (residual, cost / 2)
        }
        var p = [Double](repeating: 0, count: parameterCount)
        p[0] = initialFocal
        for index in 0..<imageCount {
            let axis = axisAngle(from: initialRotations[index])
            p[1 + 3 * index] = axis.x
            p[2 + 3 * index] = axis.y
            p[3 + 3 * index] = axis.z
        }
        func solution(
            _ p: [Double], _ residual: [Double], _ cost: Double, _ iterations: Int
        ) -> PanoCameraSolution {
            PanoCameraSolution(
                focal: max(p[0], 1e-6),
                rotations: (0..<imageCount).map { index in
                    rotation(fromAxisAngle: SIMD3(
                        p[1 + 3 * index], p[2 + 3 * index], p[3 + 3 * index]))
                },
                residualRMS: sqrt(2 * cost / Double(max(1, residual.count / 3))),
                iterations: iterations)
        }
        var (residual, cost) = evaluate(p)
        let initialCost = cost
        var lambda = 1e-3
        var iterations = 0
        // The exit verdict: a MEANINGFUL joint fit happened (the data-
        // relative criterion — an absolute RMS gate cannot clear the
        // pixel-quantization floor).
        func meaningfulFit() -> Bool {
            cost <= initialCost * (1 - improvementFloor)
        }
        while iterations < maxIterations {
            iterations += 1
            // The dense forward-difference Jacobian (3M × (3N+1)).
            let residualCount = residual.count
            var jacobian = [Double](repeating: 0, count: residualCount * parameterCount)
            for k in 0..<parameterCount {
                let step = 1e-6 * max(1, abs(p[k]))
                var perturbed = p
                perturbed[k] += step
                let (perturbedResidual, _) = evaluate(perturbed)
                for i in 0..<residualCount {
                    jacobian[i * parameterCount + k] =
                        (perturbedResidual[i] - residual[i]) / step
                }
            }
            // H = JᵀJ, g = Jᵀr (fixed accumulation order).
            var normal = [Double](repeating: 0, count: parameterCount * parameterCount)
            var gradient = [Double](repeating: 0, count: parameterCount)
            for i in 0..<residualCount {
                let row = (jacobian, i * parameterCount)
                for a in 0..<parameterCount {
                    let jia = row.0[row.1 + a]
                    gradient[a] += jia * residual[i]
                    for b in 0..<parameterCount {
                        normal[a * parameterCount + b] += jia * row.0[row.1 + b]
                    }
                }
            }
            // (H + λ·diag(H)) δ = −g — dgesv, column-major.
            var aMatrix = [Double](repeating: 0, count: parameterCount * parameterCount)
            for a in 0..<parameterCount {
                for b in 0..<parameterCount {
                    aMatrix[b * parameterCount + a] = normal[a * parameterCount + b]
                }
                aMatrix[a * parameterCount + a] +=
                    lambda * max(normal[a * parameterCount + a], 1e-12)
            }
            var bVector = gradient.map { -$0 }
            var n = __CLPK_integer(parameterCount)
            var lda = n
            var ldb = n
            var nrhs = __CLPK_integer(1)
            var info = __CLPK_integer(0)
            var pivots = [__CLPK_integer](repeating: 0, count: parameterCount)
            dgesv_(&n, &nrhs, &aMatrix, &lda, &pivots, &bVector, &ldb, &info)
            guard info == 0 else {
                lambda *= 10
                if lambda > 1e12 { break }
                continue
            }
            var trial = p
            for k in 0..<parameterCount {
                trial[k] += bVector[k]
            }
            let (trialResidual, trialCost) = evaluate(trial)
            if trialCost < cost {
                let relativeDecrease = (cost - trialCost) / max(cost, 1e-300)
                p = trial
                residual = trialResidual
                cost = trialCost
                lambda = max(lambda / 3, 1e-12)
                if relativeDecrease < tolerance {
                    break // plateau — the meaningfulFit verdict rules below
                }
            } else {
                lambda *= 10
                if lambda > 1e12 { break }
            }
        }
        return meaningfulFit()
            ? solution(p, residual, cost, iterations) : nil
    }

    private static func rotate(_ r: Mat3D, _ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            r[0, 0] * v.x + r[0, 1] * v.y + r[0, 2] * v.z,
            r[1, 0] * v.x + r[1, 1] * v.y + r[1, 2] * v.z,
            r[2, 0] * v.x + r[2, 1] * v.y + r[2, 2] * v.z)
    }

    // MARK: - Horizontal wave correct (KD-5)

    /// The horizontal wave correction: the 3×3 second-moment matrix of the
    /// cameras' first rows, its SMALLEST eigenvector v (Jacobi), the sign
    /// oriented so Σᵢ row₀(Rᵢ)·v ≥ 0, and the global correction applied to
    /// every camera FROM THE RIGHT (Rᵢ ← Rᵢ·R_corrᵀ, where R_corr maps v
    /// onto +x). The right-multiplication is load-bearing: row₀(Rᵢ·R_corrᵀ)
    /// = row₀(Rᵢ)·R_corrᵀ, so the corrected second moment is exactly
    /// R_corr·S·R_corrᵀ and its smallest eigendirection lands on x — a
    /// second call rides the exact-identity guard (|v×x̂| < 1e-9) and stays
    /// bit-identical. (A LEFT multiplication would mix R's rows through a
    /// different factor and the eigendirection never settles — the
    /// probe-pinned non-idempotence.) The Σx ≥ 0 sign rule holds by
    /// construction: Σ row₀(Rᵢ·R_corrᵀ)[0] = Σ row₀(Rᵢ)·v ≥ 0.
    public static func waveCorrectHorizontally(_ rotations: [Mat3D]) -> [Mat3D] {
        guard !rotations.isEmpty else { return rotations }
        // S = Σ row₀ᵀ·row₀ (the symmetric second-moment matrix).
        var s = [Double](repeating: 0, count: 9)
        for r in rotations {
            let row = (r[0, 0], r[0, 1], r[0, 2])
            let entries: [(Int, Int, Double)] = [
                (0, 0, row.0 * row.0), (0, 1, row.0 * row.1),
                (0, 2, row.0 * row.2), (1, 1, row.1 * row.1),
                (1, 2, row.1 * row.2), (2, 2, row.2 * row.2),
            ]
            for (i, j, value) in entries {
                s[i * 3 + j] += value
                if i != j {
                    s[j * 3 + i] += value
                }
            }
        }
        guard let (eigenvalues, eigenvectors) = PanoMatch.symmetricEigen(s, size: 3)
        else { return rotations }
        var smallest = 0
        for index in 1..<3 where eigenvalues[index] < eigenvalues[smallest] {
            smallest = index
        }
        var v = SIMD3(
            eigenvectors[0 * 3 + smallest], eigenvectors[1 * 3 + smallest],
            eigenvectors[2 * 3 + smallest])
        let norm = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
        guard norm > 1e-12 else { return rotations }
        v = v / norm
        // The sign orientation: Σ first-row x-components ≥ 0 after the fix.
        var projection = 0.0
        for r in rotations {
            projection += r[0, 0] * v.x + r[0, 1] * v.y + r[0, 2] * v.z
        }
        if projection < 0 {
            v = -v
        }
        // The rotation mapping v onto +x̂ (exact identity in the guard band).
        let xAxis = SIMD3(1.0, 0.0, 0.0)
        let cross = SIMD3(
            v.y * xAxis.z - v.z * xAxis.y,
            v.z * xAxis.x - v.x * xAxis.z,
            v.x * xAxis.y - v.y * xAxis.x)
        let crossNorm = sqrt(cross.x * cross.x + cross.y * cross.y + cross.z * cross.z)
        let dot = v.x * xAxis.x + v.y * xAxis.y + v.z * xAxis.z
        if crossNorm < 1e-9 {
            return rotations
        }
        let correction = rotation(
            fromAxisAngle: cross / crossNorm * atan2(crossNorm, dot))
        // The transpose rides along: Rᵢ ← Rᵢ·R_corrᵀ (the right-multiply
        // contract above).
        return rotations.map { Mat3D.mul($0, correction.transposed()) }
    }
}

extension Mat3D {
    /// Matrix transpose (the wave-correction right-multiply's local helper).
    fileprivate func transposed() -> Mat3D {
        Mat3D(
            m.0, m.3, m.6,
            m.1, m.4, m.7,
            m.2, m.5, m.8)
    }
}

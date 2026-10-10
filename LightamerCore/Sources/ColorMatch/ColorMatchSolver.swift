import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────────
// ColorMatchSolver (Plan M5-1-01 T3, KD-3; OQ-M5-1-1) — the S1 Gaussian OT
// closed form + the S3 Reinhard diagonal, over the Oklab statistics of
// ColorMatchStats.
//
// S1 — the SYMMETRIC SANDWICH FORM (checker 回注 E1, 2026-10-09 — the
// textbook Bures-Wasserstein optimum; the originally drafted polar form
// `M = Σt^{1/2}·A·Σs^{−1/2}` double-squared the SPD root and was PROVEN
// wrong: diag substitution gives variance RATIO SQUARED, breaching the OT
// definition constraint):
//
//     M = Σs^{−1/2}·(Σs^{1/2}·Σt·Σs^{1/2})^{1/2}·Σs^{−1/2}
//     offset = μt − M·μs
//
// EQUIVALENT POLAR FACTOR (the checker's 复查轮补正): M = Σt^{1/2}·U·Σs^{−1/2}
// with U = polar(Σt^{1/2}·Σs^{1/2}) — NOT polar(Σt^{1/2}·Σs^{−1/2}), which is
// constraint-satisfying but suboptimal (Trace gap ~1e−2). The two forms agree
// to ≤1e−15; THIS IMPLEMENTATION = the sandwich (three symmetric Jacobi
// eigendecompositions, no SVD machinery — the declared internal freedom).
//
// DETERMINISM (G1): the solve is a FIXED algorithm ladder — cyclic Jacobi
// over the pairs (0,1),(0,2),(1,2) in that order, rotate-when-above-threshold
// with a fixed relative gate, fixed 60-sweep cap, fixed sign conventions; NO
// LAPACK/Accelerate calls (their cross-version paths are not bit-stable).
// The SPD principal square root is UNIQUE (eigenvector sign flips cancel in
// V·D^{1/2}·Vᵀ), so bit-identity is reachable — same stats bytes → same
// solution bytes, every process, every machine.
//
// REGULARIZATION + DEGENERATE FALLBACK (R1, pinned): Σ + εI first with
// ε = 1e−12·trace(Σ); if the regularized Σs's smallest eigenvalue <
// 1e−9·trace (rank-deficient — single-color / low-variance source images),
// the solve FALLS BACK to the S3 diagonal path and records it on
// `effectiveSolver = .reinhard` (diagnostics only — the params' solver keeps
// the user selection; `.reinhardFallback` is deliberately NOT an enum case,
// checker 回注 m2's two-value enum discipline). G1 asserts the fallback's
// determinism.
//
// S3 Reinhard diagonal: M = diag(σt_i/σs_i) over the SAME regularized
// matrices (the ε floor makes the divisor positive) + the same offset form —
// the S1 closed-covariance special case as an INDEPENDENT pure function (no
// shared internals with S1).
//
// FLOAT PRECISION (the pinned demotion point): all solving is Float64; the
// Float32 DEMOTION happens exactly once, at `ColorMatchSolution.matrix/.offset`
// storage (G1 asserts the stored byte face).
//
// STRENGTH (three solvers共用, OQ-M5-1-1): `out = (1−α)·x + α·(M·(x−μs)+μt)`,
// α ∈ [0,1], 0 = identity. α NEVER enters the solve (a kernel-run uniform —
// dragging strength re-runs no solve). The kernel's expanded form (KD-6):
// `x + α·((M−I)·x + c)` with the α-invariant constant c = offset — the
// ColorMatchUniforms carry (M−I) and c; `strengthKernelMI` below is the ONE
// demotion point for that form.
// ─────────────────────────────────────────────────────────────────────────────

/// The solver selection (checker 回注 m2: TWO values this batch — the `.cdf`
/// case is M5-1-02 additive and its arrival breaks every exhaustive switch on
/// purpose, the M2-7 discipline).
public enum ColorMatchSolverKind: String, Codable, Sendable, CaseIterable {
    /// S1 Gaussian OT closed form (the Bures-Wasserstein sandwich).
    case gaussianOT
    /// S3 Reinhard diagonal (the closed-covariance special case).
    case reinhard

    /// The solve-cache tag (the key's third term).
    var cacheTag: String {
        switch self {
        case .gaussianOT: return "colormatch.solve.gaussianOT.v1"
        case .reinhard: return "colormatch.solve.reinhard.v1"
        }
    }
}

/// One solved color match — the Float32 storage face of the Float64 solve.
public struct ColorMatchSolution: Codable, Equatable, Sendable {

    /// The user-selected solver (never rewritten by the fallback).
    public let solver: ColorMatchSolverKind
    /// The ACTUALLY taken path (`.reinhard` after a rank-deficient S1
    /// fallback — the diagnostics face; equals `solver` on a clean solve).
    public let effectiveSolver: ColorMatchSolverKind
    /// Row-major 3×3, Oklab domain (Float32 — THE demotion point).
    public let matrix: [Float]
    /// The offset c = μt − M·μs (Oklab domain, Float32).
    public let offset: [Float]
    /// The stats identities behind this solve (L013 decimal-String payloads
    /// — UInt64 never crosses a JSON boundary as a number).
    public let sourceStatsHash: UInt64
    public let referenceStatsHash: UInt64

    enum CodingKeys: String, CodingKey {
        case solver, effectiveSolver, matrix, offset
        case sourceStatsHash, referenceStatsHash
    }

    public init(
        solver: ColorMatchSolverKind, effectiveSolver: ColorMatchSolverKind,
        matrix: [Float], offset: [Float],
        sourceStatsHash: UInt64, referenceStatsHash: UInt64
    ) {
        self.solver = solver
        self.effectiveSolver = effectiveSolver
        self.matrix = matrix
        self.offset = offset
        self.sourceStatsHash = sourceStatsHash
        self.referenceStatsHash = referenceStatsHash
    }

    /// The L013 decimal-String face for the two UInt64 hashes (a JSON number
    /// would silently lose >2^53 precision in non-Swift tooling).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        solver = try c.decodeIfPresent(ColorMatchSolverKind.self, forKey: .solver) ?? .gaussianOT
        effectiveSolver = try c.decodeIfPresent(ColorMatchSolverKind.self, forKey: .effectiveSolver)
            ?? (try c.decodeIfPresent(ColorMatchSolverKind.self, forKey: .solver) ?? .gaussianOT)
        matrix = try c.decodeIfPresent([Float].self, forKey: .matrix)
            ?? [1, 0, 0, 0, 1, 0, 0, 0, 1]
        offset = try c.decodeIfPresent([Float].self, forKey: .offset) ?? [0, 0, 0]
        sourceStatsHash = UInt64(
            try c.decodeIfPresent(String.self, forKey: .sourceStatsHash) ?? "0") ?? 0
        referenceStatsHash = UInt64(
            try c.decodeIfPresent(String.self, forKey: .referenceStatsHash) ?? "0") ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(solver, forKey: .solver)
        try c.encode(effectiveSolver, forKey: .effectiveSolver)
        try c.encode(matrix, forKey: .matrix)
        try c.encode(offset, forKey: .offset)
        try c.encode(String(sourceStatsHash), forKey: .sourceStatsHash)
        try c.encode(String(referenceStatsHash), forKey: .referenceStatsHash)
    }

    /// FNV-1a over the canonical sorted-keys JSON bytes (L013/DrtRecord 同款
    /// — the G1 bit-identity byte face).
    public func stableHash() -> UInt64 {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return 0 }
        return StableHash.hash(data)
    }

    /// The identity solution (no-op map) — the params-default face.
    public static func identity(
        solver: ColorMatchSolverKind = .gaussianOT,
        sourceStatsHash: UInt64 = 0, referenceStatsHash: UInt64 = 0
    ) -> ColorMatchSolution {
        ColorMatchSolution(
            solver: solver, effectiveSolver: solver,
            matrix: [1, 0, 0, 0, 1, 0, 0, 0, 1], offset: [0, 0, 0],
            sourceStatsHash: sourceStatsHash, referenceStatsHash: referenceStatsHash)
    }
}

public enum ColorMatchSolver {

    // MARK: - Regularization / rank constants (R1, pinned)

    /// ε = 1e−12·trace(Σ) — added to BOTH covariance diagonals pre-solve.
    public static let epsilonRelative: Double = 1e-12
    /// The S1 rank floor: regularized min-eigenvalue < 1e−9·trace → the S3
    /// fallback (single-color / low-variance source images).
    public static let rankFloorRelative: Double = 1e-9

    // MARK: - The solve entry

    /// Solve the color match from source → reference statistics. Total: a
    /// rank-deficient S1 falls back to S3 (`effectiveSolver = .reinhard`)
    /// instead of failing — the caller always gets a usable solution.
    public static func solve(
        source: ColorMatchStats, reference: ColorMatchStats,
        solver: ColorMatchSolverKind
    ) -> ColorMatchSolution {
        let float64 = solveMatrix64(source: source, reference: reference, solver: solver)
        return assemble(
            solver: solver, effectiveSolver: float64.effective, m: float64.m,
            source: source, reference: reference,
            sourceHash: source.statsHash, referenceHash: reference.statsHash)
    }

    /// The Float64 solve face (internal — the G1 math-structure gate
    /// consumes it: the OT definition constraint is a FLOAT64 assertion;
    /// the Float32 demotion face rides `solve` above).
    static func solveMatrix64(
        source: ColorMatchStats, reference: ColorMatchStats,
        solver: ColorMatchSolverKind
    ) -> (m: [Double], effective: ColorMatchSolverKind) {
        switch solver {
        case .gaussianOT:
            // R1: the rank check rides the REGULARIZED source covariance.
            // The `<= 0` arm catches the zero-trace face (a constant-color
            // source: trace 0 → ε 0 → eigenvalues 0 — `min < 0·1e-9` would
            // be false and the sandwich would hit 1/√0 = inf).
            let s = regularizedCovariance(source)
            let (valuesS, vectorsS) = jacobiEigen(s)
            let traceS = s[0] + s[4] + s[8]
            if min(valuesS.0, valuesS.1, valuesS.2) <= 0
                || min(valuesS.0, valuesS.1, valuesS.2) < rankFloorRelative * traceS {
                return (reinhardMatrix64(source: source, reference: reference), .reinhard)
            }
            let m = gaussianOTMatrix(
                sourceCovEigen: (valuesS, vectorsS), source: source, reference: reference)
            return (m, .gaussianOT)
        case .reinhard:
            return (reinhardMatrix64(source: source, reference: reference), .reinhard)
        }
    }

    /// The S3 path (both the direct selection and the S1 fallback — one
    /// independent pure function, no shared internals with the sandwich).
    /// Zero-trace source (a constant-color image): the diagonal ratio is
    /// 0/0, so the honest face is the IDENTITY matrix + the pure-offset map
    /// c = μt − μs (any M is "optimal" against a zero covariance; identity
    /// is the neutral deterministic choice — DECISIONS).
    static func reinhardMatrix64(
        source: ColorMatchStats, reference: ColorMatchStats
    ) -> [Double] {
        let s = regularizedCovariance(source)
        let traceS = s[0] + s[4] + s[8]
        guard traceS > 0 else {
            return [1, 0, 0, 0, 1, 0, 0, 0, 1]
        }
        let t = regularizedCovariance(reference)
        // diag(√(Σt_ii/Σs_ii)) — the STANDARD-DEVIATION ratio (checker E1's
        // 对角归约 form: matching moments per axis means the transformed
        // variance M²·Σs_ii lands on Σt_ii; the regularized diagonals are
        // ≥ ε > 0 here).
        var m = [Double](repeating: 0, count: 9)
        for i in 0..<3 {
            m[i * 3 + i] = (t[i * 3 + i] / s[i * 3 + i]).squareRoot()
        }
        return m
    }

    /// The S1 sandwich: M = Σs^{−1/2}·(Σs^{1/2}·Σt·Σs^{1/2})^{1/2}·Σs^{−1/2}.
    /// The source covariance's eigendecomposition is PASSED IN (the caller
    /// already paid for it in the rank check — one ladder, no re-derivation).
    static func gaussianOTMatrix(
        sourceCovEigen: ((Double, Double, Double), simd_double3x3),
        source: ColorMatchStats, reference: ColorMatchStats
    ) -> [Double] {
        let (valuesS, vectorsS) = sourceCovEigen
        let halfS = reconstruct(valuesS, vectorsS) { sqrt($0) }
        let minusHalfS = reconstruct(valuesS, vectorsS) { 1.0 / sqrt($0) }
        let t = regularizedCovariance(reference)
        // inner = Σs^{1/2}·Σt·Σs^{1/2} — symmetric by construction.
        let inner = matMul(matMul(halfS, t), halfS)
        let (innerValues, innerVectors) = jacobiEigen(inner)
        let innerHalf = reconstruct(innerValues, innerVectors) { sqrt($0) }
        return matMul(matMul(minusHalfS, innerHalf), minusHalfS)
    }

    /// Package the solve: the Float64 matrix → the Float32 storage (THE
    /// demotion point) + the offset c = μt − M·μs.
    static func assemble(
        solver: ColorMatchSolverKind, effectiveSolver: ColorMatchSolverKind,
        m: [Double], source: ColorMatchStats, reference: ColorMatchStats,
        sourceHash: UInt64, referenceHash: UInt64
    ) -> ColorMatchSolution {
        let muS = SIMD3<Double>(source.mu)
        let muT = SIMD3<Double>(reference.mu)
        let r0 = SIMD3(m[0], m[1], m[2])
        let r1 = SIMD3(m[3], m[4], m[5])
        let r2 = SIMD3(m[6], m[7], m[8])
        let mRows = simd_double3x3(rows: [r0, r1, r2])
        let offset = muT - mRows * muS
        return ColorMatchSolution(
            solver: solver, effectiveSolver: effectiveSolver,
            matrix: m.map { Float($0) },
            offset: [Float(offset.x), Float(offset.y), Float(offset.z)],
            sourceStatsHash: sourceHash, referenceStatsHash: referenceHash)
    }

    /// The regularized covariance as a row-major 9-tuple: Σ + εI with
    /// ε = 1e−12·trace(Σ).
    static func regularizedCovariance(_ stats: ColorMatchStats) -> [Double] {
        let s = stats.sigma
        let trace = Double(s.0) + Double(s.3) + Double(s.5)
        let eps = epsilonRelative * trace
        return [
            Double(s.0) + eps, Double(s.1), Double(s.2),
            Double(s.1), Double(s.3) + eps, Double(s.4),
            Double(s.2), Double(s.4), Double(s.5) + eps,
        ]
    }

    // MARK: - Fixed Jacobi eigendecomposition (the determinism ladder)

    /// Cyclic Jacobi for a symmetric 3×3 (row-major 9-tuple). Fixed pair
    /// order (0,1),(0,2),(1,2); rotate when |a_pq| exceeds the relative
    /// gate; 60-sweep cap (3×3 converges quadratically — single digits in
    /// practice); eigenvalues returned DESCENDING with index tie-break;
    /// eigenvectors as the COLUMNS of the returned matrix. Pure Float64
    /// arithmetic — identical inputs give identical output bits (the G1
    /// contract; NO Accelerate/LAPACK on this path).
    static func jacobiEigen(_ a: [Double]) -> ((Double, Double, Double), simd_double3x3) {
        var m = a
        // Accumulated rotations, row-major.
        var v = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
        let scale = max(abs(a[0]) + abs(a[4]) + abs(a[8]), 1e-300)
        let gate = 1e-15 * scale

        func rotate(_ p: Int, _ q: Int) {
            let apq = m[p * 3 + q]
            if abs(apq) <= gate { return }
            let app = m[p * 3 + p]
            let aqq = m[q * 3 + q]
            // The tangent half-angle: t = sign(θ)/(|θ| + √(θ²+1)).
            let theta = (aqq - app) / (2.0 * apq)
            let sign = theta >= 0 ? 1.0 : -1.0
            let t = sign / (abs(theta) + (theta * theta + 1.0).squareRoot())
            let c = 1.0 / (t * t + 1.0).squareRoot()
            let s = t * c
            // M ← JᵀMJ, V ← VJ for the (p,q) plane rotation.
            for k in 0..<3 {
                let mkp = m[k * 3 + p]
                let mkq = m[k * 3 + q]
                m[k * 3 + p] = c * mkp - s * mkq
                m[k * 3 + q] = s * mkp + c * mkq
            }
            for k in 0..<3 {
                let mpk = m[p * 3 + k]
                let mqk = m[q * 3 + k]
                m[p * 3 + k] = c * mpk - s * mqk
                m[q * 3 + k] = s * mpk + c * mqk
            }
            for k in 0..<3 {
                let vkp = v[k * 3 + p]
                let vkq = v[k * 3 + q]
                v[k * 3 + p] = c * vkp - s * vkq
                v[k * 3 + q] = s * vkp + c * vkq
            }
        }

        for _ in 0..<60 {
            let off = abs(m[1]) + abs(m[2]) + abs(m[5])
            if off <= gate { break }
            rotate(0, 1)
            rotate(0, 2)
            rotate(1, 2)
        }

        // Diagonal = eigenvalues; sort DESCENDING with a fixed index
        // tie-break (d0 before d1 before d2 on exact equality).
        var entries: [(value: Double, column: Int)] = [
            (m[0], 0), (m[4], 1), (m[8], 2)
        ]
        entries.sort {
            $0.value != $1.value ? $0.value > $1.value : $0.column < $1.column
        }
        let c0 = entries[0].column
        let c1 = entries[1].column
        let c2 = entries[2].column
        // v is ROW-MAJOR: column j lives at stride 3 (v[j], v[3+j], v[6+j]).
        let col0 = SIMD3(v[c0], v[3 + c0], v[6 + c0])
        let col1 = SIMD3(v[c1], v[3 + c1], v[6 + c1])
        let col2 = SIMD3(v[c2], v[3 + c2], v[6 + c2])
        let vectors = simd_double3x3(columns: (col0, col1, col2))
        return ((entries[0].value, entries[1].value, entries[2].value), vectors)
    }

    /// Reconstruct V·f(D)·Vᵀ from a Jacobi result (the sign-invariant SPD
    /// function face — the principal square root's uniqueness lives here).
    static func reconstruct(
        _ values: (Double, Double, Double), _ vectors: simd_double3x3,
        _ f: (Double) -> Double
    ) -> [Double] {
        let d = SIMD3<Double>(f(values.0), f(values.1), f(values.2))
        // V·diag(d)·Vᵀ row-major entries: Σ_k d_k · V[i][k] · V[j][k].
        var out = [Double](repeating: 0, count: 9)
        let cols = vectors.columns
        let vCols = [cols.0, cols.1, cols.2]
        for i in 0..<3 {
            for j in 0..<3 {
                var sum = 0.0
                for k in 0..<3 {
                    sum += d[k] * vCols[k][i] * vCols[k][j]
                }
                out[i * 3 + j] = sum
            }
        }
        return out
    }

    // MARK: - Small matrix helpers (row-major)

    static func matMul(_ a: [Double], _ b: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: 9)
        for i in 0..<3 {
            for j in 0..<3 {
                var sum = 0.0
                for k in 0..<3 { sum += a[i * 3 + k] * b[k * 3 + j] }
                out[i * 3 + j] = sum
            }
        }
        return out
    }

    // MARK: - The kernel demotion seam (KD-6)

    /// The kernel's uniform face: (M−I) row-major Float32 + the offset c —
    /// the α-invariant pair (strength rides separately). The ONE demotion
    /// point for the KD-6 recommended expansion `x + α·((M−I)·x + c)`.
    public static func strengthKernelTerms(
        _ solution: ColorMatchSolution
    ) -> (mMinusI: [Float], c: [Float]) {
        precondition(solution.matrix.count == 9 && solution.offset.count == 3)
        var mi = solution.matrix
        mi[0] -= 1; mi[4] -= 1; mi[8] -= 1
        return (mi, solution.offset)
    }

    /// The CPU strength-application face (the semantic constant, Oklab
    /// domain): `out = (1−α)·x + α·(M·x + c)`.
    public static func apply(
        _ x: SIMD3<Float>, solution: ColorMatchSolution, strength: Float
    ) -> SIMD3<Float> {
        let m = solution.matrix
        let c = SIMD3<Float>(solution.offset[0], solution.offset[1], solution.offset[2])
        let mapped = SIMD3<Float>(
            m[0] * x.x + m[1] * x.y + m[2] * x.z,
            m[3] * x.x + m[4] * x.y + m[5] * x.z,
            m[6] * x.x + m[7] * x.y + m[8] * x.z) + c
        return (1 - strength) * x + strength * mapped
    }
}

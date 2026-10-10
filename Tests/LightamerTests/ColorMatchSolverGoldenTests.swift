@testable import LightamerCore
import simd
import XCTest

/// ColorMatchSolverGoldenTests (Plan M5-1-01 T4, KD-4 + checker E1; the T3
/// structural face rides here per the plan's task split) —
///
/// - THE MATH STRUCTURE HARD GATES (checker E1): ① the OT definition
///   constraint `M·Σs·Mᵀ ≈ Σt` over a NON-DIAGONAL, NON-COMMUTING solve
///   set (the solved Float32 matrix elevated — the shipped truth); ② the S1
///   diagonal-input ≡ S3-output agreement (≤1e-6 — the two paths' rounding
///   forms differ, so no per-bit expectation; the gate guards future formula
///   regressions) + the isotropic self-consistency `(σt/σs)·I`;
/// - the T3 structural face: the SPD principal root's basis invariance
///   (hand-built permuted/sign-flipped eigenbases of one matrix);
/// - G1: double-run bit-identity (Float32 matrix/offset bits + stableHash),
///   the degenerate fallback's determinism (zero-trace AND rank-deficient
///   faces), cache transparency, and the PINNED cache-key fold literals;
/// - G3: the synthetic reference-pair recovery — the moment-exact arm
///   (Σt := T·Σs·Tᵀ hand-built, ≤1e-3) and the sampled arm (LCG cloud,
///   measured band), plus the S3 diagonal recovery.
final class ColorMatchSolverGoldenTests: XCTestCase {

    /// Deterministic LCG (FilmPrintBake precedent) — the drive sets are
    /// reproducible run-to-run and machine-to-machine.
    private struct LCG {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
        mutating func uniform(_ scale: Double) -> Double {
            Double(next() >> 11) / Double(1 << 53) * 2 * scale - scale
        }
        mutating func uniformPositive(_ scale: Double) -> Double {
            Double(next() >> 11) / Double(1 << 53) * scale
        }
        mutating func gaussian() -> Double {
            let u1 = max(Double(next() >> 11) / Double(1 << 53), 1e-12)
            let u2 = Double(next() >> 11) / Double(1 << 53)
            return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
    }

    /// A hand-built stats value (the solve consumes μ/Σ only — the histogram
    /// fields ride as zero placeholders; sampleCount is declarative).
    private func makeStats(
        _ mu: SIMD3<Float>, _ s: (Float, Float, Float, Float, Float, Float)
    ) -> ColorMatchStats {
        ColorMatchStats(
            mu: mu, sigma: s,
            histograms: [[UInt32]](repeating: [UInt32](repeating: 0, count: 256), count: 3),
            supportLo: .zero, supportHi: SIMD3<Float>(1, 0.5, 0.5), sampleCount: 1)
    }

    /// The six-tuple → row-major 3×3 Float64.
    private func full(_ s: (Float, Float, Float, Float, Float, Float)) -> [Double] {
        [
            Double(s.0), Double(s.1), Double(s.2),
            Double(s.1), Double(s.3), Double(s.4),
            Double(s.2), Double(s.4), Double(s.5),
        ]
    }

    private func matMul(_ a: [Double], _ b: [Double]) -> [Double] {
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

    private func transpose(_ a: [Double]) -> [Double] {
        [
            a[0], a[3], a[6],
            a[1], a[4], a[7],
            a[2], a[5], a[8],
        ]
    }

    /// max |a−b| / max(‖b‖ entry scale, 1e-12) — the relative band face.
    private func relErr(_ a: [Double], _ b: [Double]) -> Double {
        let scale = b.map { abs($0) }.max() ?? 0
        let absErr = zip(a, b).map { abs($0 - $1) }.max() ?? 0
        return absErr / max(scale, 1e-12)
    }

    /// A fixed orthogonal V (product of three coordinate rotations at
    /// non-nice angles) — the G3 commuting family's eigenbasis.
    private var fixedV: simd_double3x3 {
        func rx(_ a: Double) -> simd_double3x3 {
            simd_double3x3(rows: [
                SIMD3(1.0, 0.0, 0.0),
                SIMD3(0.0, cos(a), -sin(a)),
                SIMD3(0.0, sin(a), cos(a)),
            ])
        }
        func ry(_ a: Double) -> simd_double3x3 {
            simd_double3x3(rows: [
                SIMD3(cos(a), 0.0, sin(a)),
                SIMD3(0.0, 1.0, 0.0),
                SIMD3(-sin(a), 0.0, cos(a)),
            ])
        }
        func rz(_ a: Double) -> simd_double3x3 {
            simd_double3x3(rows: [
                SIMD3(cos(a), -sin(a), 0.0),
                SIMD3(sin(a), cos(a), 0.0),
                SIMD3(0.0, 0.0, 1.0),
            ])
        }
        let a = rx(0.7) * ry(1.1)
        return a * rz(0.4)
    }

    private func simdRows(_ m: [Double]) -> simd_double3x3 {
        simd_double3x3(rows: [
            SIMD3(m[0], m[1], m[2]), SIMD3(m[3], m[4], m[5]), SIMD3(m[6], m[7], m[8]),
        ])
    }

    // MARK: - Math structure hard gates (checker E1)

    /// ① The OT definition constraint `M·Σs·Mᵀ ≈ Σt` over a non-diagonal,
    /// non-commuting solve set — TWO faces: the Float64 solve matrix (the
    /// math gate; the checker's ~4.9e-15 random-set face) and the PUBLIC
    /// solution's Float32 matrix elevated (the shipped truth; the demotion
    /// band). The non-commutation is ASSERTED so the gate cannot rot into a
    /// trivial diagonal drive set.
    func testOTConstraintReconstructionNonCommuting() throws {
        // Two full covariances with distinct off-diagonal structure.
        let src = makeStats(
            SIMD3<Float>(0.45, 0.02, -0.03),
            (0.010, 0.0021, -0.0004, 0.0036, 0.0009, 0.0064))
        let ref = makeStats(
            SIMD3<Float>(0.50, 0.05, 0.02),
            (0.020, -0.0030, 0.0011, 0.0050, -0.0007, 0.0030))
        let S = full(src.sigma)
        let T = full(ref.sigma)
        // The non-commutation pin (the drive set's honesty).
        XCTAssertGreaterThan(relErr(matMul(S, T), matMul(T, S)), 1e-3, "drive set must not commute")

        // The Float64 math gate (the checker E1 face). 1e-10: the Jacobi
        // termination gate (1e-15·scale) leaves an off-diagonal residual
        // that surfaces as ~1e-12 in the reconstruction — the gate sits
        // two orders above the observed face, six below the red line.
        let float64 = ColorMatchSolver.solveMatrix64(
            source: src, reference: ref, solver: .gaussianOT)
        XCTAssertEqual(float64.effective, .gaussianOT)
        let rebuilt64 = matMul(matMul(float64.m, S), transpose(float64.m))
        let band64 = relErr(rebuilt64, T)
        XCTAssertLessThanOrEqual(
            band64, 1e-10, "Float64 M·Σs·Mᵀ vs Σt, got \(band64)")
        XCTAssertLessThanOrEqual(
            band64, 1e-10, "Float64 M·Σs·Mᵀ vs Σt, got \(band64)")

        // The Float32 demotion face (the public solution).
        let solution = ColorMatchSolver.solve(source: src, reference: ref, solver: .gaussianOT)
        let m = solution.matrix.map(Double.init)
        let rebuilt = matMul(matMul(m, S), transpose(m))
        let band = relErr(rebuilt, T)
        XCTAssertLessThanOrEqual(
            band, 1e-6, "Float32-elevated M·Σs·Mᵀ vs Σt, got \(band) (the checker red line)")
        XCTAssertGreaterThan(band, 0, "the constraint is a measured face, not a tautology")
    }

    /// ② The S1-diagonal ≡ S3 agreement (≤1e-6) + the isotropic
    /// self-consistency `(σt/σs)·I` (the S3 special-case relation closing).
    func testS1DiagonalInputMatchesS3() {
        let src = makeStats(
            SIMD3<Float>(0.4, 0.0, 0.0), (0.040, 0, 0, 0.090, 0, 0.160))
        let ref = makeStats(
            SIMD3<Float>(0.5, 0.1, -0.1), (0.010, 0, 0, 0.030, 0, 0.090))
        let s1 = ColorMatchSolver.solve(source: src, reference: ref, solver: .gaussianOT)
        let s3 = ColorMatchSolver.solve(source: src, reference: ref, solver: .reinhard)
        XCTAssertEqual(s1.effectiveSolver, .gaussianOT)
        for i in 0..<9 {
            XCTAssertEqual(
                Double(s1.matrix[i]), Double(s3.matrix[i]), accuracy: 1e-6,
                "diagonal input S1 vs S3 [\(i)]")
        }
        for i in 0..<3 {
            XCTAssertEqual(
                Double(s1.offset[i]), Double(s3.offset[i]), accuracy: 1e-5, "offset[\(i)]")
        }
        // Isotropic: Σs = σs²I, Σt = σt²I → both solvers = (σt/σs)·I.
        let isoS = makeStats(SIMD3<Float>(0.4, 0, 0), (0.040, 0, 0, 0.040, 0, 0.040))
        let isoT = makeStats(SIMD3<Float>(0.5, 0, 0), (0.090, 0, 0, 0.090, 0, 0.090))
        for solver in [ColorMatchSolverKind.gaussianOT, .reinhard] {
            let sol = ColorMatchSolver.solve(source: isoS, reference: isoT, solver: solver)
            let want = 0.3 / 0.2  // √0.09 / √0.04
            for i in 0..<9 {
                let wantEntry = (i % 4 == 0) ? want : 0.0
                XCTAssertEqual(
                    Double(sol.matrix[i]), wantEntry, accuracy: 1e-9,
                    "isotropic \(solver) [\(i)]")
            }
            // And the offset: μt − (σt/σs)·μs — through the Float32
            // demotion (the storage face; 1e-6, not 1e-9).
            XCTAssertEqual(Double(sol.offset[0]), 0.5 - want * 0.4, accuracy: 1e-6)
        }
    }

    // MARK: - T3 structural face: SPD root basis invariance

    /// The principal square root is UNIQUE: reconstructing V·D^{1/2}·Vᵀ from
    /// a permuted, sign-flipped eigenbasis of the SAME matrix yields the same
    /// matrix to the Float64 rounding face (the eigenvector sign flips cancel
    /// in the reconstruction — the G1 bit-identity precondition's math side).
    func testSPDRootBasisInvariance() {
        // A fixed full SPD matrix.
        let values = (2.0, 0.5, 0.125)
        let v = fixedV
        let sqrtA = ColorMatchSolver.reconstruct(values, v) { sqrt($0) }
        // The permuted + sign-flipped basis of the same matrix.
        let flip = simd_double3x3(columns: (
            v.columns.2 * -1, v.columns.0, v.columns.1 * -1))
        let permutedValues = (values.2, values.0, values.1)
        let sqrtA2 = ColorMatchSolver.reconstruct(permutedValues, flip) { sqrt($0) }
        XCTAssertLessThanOrEqual(relErr(sqrtA2, sqrtA), 1e-12, "basis-invariant root")
        // The inverse root agrees too (the S1 minus-half face).
        let invA = ColorMatchSolver.reconstruct(values, v) { 1.0 / sqrt($0) }
        let invA2 = ColorMatchSolver.reconstruct(permutedValues, flip) { 1.0 / sqrt($0) }
        XCTAssertLessThanOrEqual(relErr(invA2, invA), 1e-12, "basis-invariant inverse root")
    }

    // MARK: - G1 determinism

    /// Double-run bit-identity: identical stats → identical Float32
    /// matrix/offset bits AND identical stableHash.
    func testG1DoubleRunBitIdentity() {
        var rng = LCG(seed: 0x91)
        var samples: [SIMD3<Float>] = []
        for _ in 0..<3000 {
            samples.append(SIMD3<Float>(
                Float(0.45 + 0.1 * rng.gaussian()),
                Float(0.02 + 0.06 * rng.gaussian()),
                Float(-0.03 + 0.08 * rng.gaussian())))
        }
        let src = try! ColorMatchStats.extract(samples: samples)
        var refSamples: [SIMD3<Float>] = []
        for _ in 0..<2500 {
            refSamples.append(SIMD3<Float>(
                Float(0.5 + 0.12 * rng.gaussian()),
                Float(0.05 + 0.05 * rng.gaussian()),
                Float(0.02 + 0.07 * rng.gaussian())))
        }
        let ref = try! ColorMatchStats.extract(samples: refSamples)

        for solver in [ColorMatchSolverKind.gaussianOT, .reinhard] {
            let a = ColorMatchSolver.solve(source: src, reference: ref, solver: solver)
            let b = ColorMatchSolver.solve(source: src, reference: ref, solver: solver)
            XCTAssertEqual(a, b, "\(solver) value identity")
            XCTAssertEqual(a.matrix.map { $0.bitPattern }, b.matrix.map { $0.bitPattern },
                           "\(solver) Float32 matrix bits")
            XCTAssertEqual(a.offset.map { $0.bitPattern }, b.offset.map { $0.bitPattern },
                           "\(solver) Float32 offset bits")
            XCTAssertEqual(a.stableHash(), b.stableHash(), "\(solver) stableHash")
        }
    }

    /// The degenerate fallback's determinism (R1/G1): a zero-trace source
    /// (constant color) and a rank-deficient source (single-channel variance)
    /// both fall to `.reinhard` for a gaussianOT request, deterministically.
    func testG1DegenerateFallbackDeterministic() {
        // Zero trace: 64 identical samples (the constant-color image).
        let constant = [SIMD3<Float>](repeating: SIMD3(0.5, 0.1, -0.2), count: 64)
        let constantStats = try! ColorMatchStats.extract(samples: constant)
        // Rank deficient: variance in L only (min eig 0, trace > 0).
        var ramp: [SIMD3<Float>] = []
        for i in 0..<128 {
            ramp.append(SIMD3(Float(0.2 + 0.6 * Double(i) / 127), 0.1, -0.05))
        }
        let rampStats = try! ColorMatchStats.extract(samples: ramp)
        let ref = makeStats(SIMD3<Float>(0.5, 0.0, 0.0), (0.010, 0.001, 0, 0.004, 0, 0.009))

        for (name, src) in [("constant", constantStats), ("rank-deficient", rampStats)] {
            let a = ColorMatchSolver.solve(source: src, reference: ref, solver: .gaussianOT)
            let b = ColorMatchSolver.solve(source: src, reference: ref, solver: .gaussianOT)
            XCTAssertEqual(a.effectiveSolver, .reinhard, "\(name) fallback recorded")
            XCTAssertEqual(a.solver, .gaussianOT, "\(name) user selection preserved")
            XCTAssertEqual(a, b, "\(name) fallback deterministic")
            // Zero-trace face: the identity matrix + the pure-offset map.
            if name == "constant" {
                XCTAssertEqual(a.matrix.map(Double.init), [1, 0, 0, 0, 1, 0, 0, 0, 1])
                XCTAssertEqual(Double(a.offset[0]), 0.0, accuracy: 1e-6, "offset x = μt−μs")
            }
        }
    }

    /// Cache transparency: a fresh solve equals a cache-consulted solve
    /// byte-for-byte; the LRU evicts past 8; invalidateAll clears.
    func testG1CacheTransparencyAndLRU() {
        let cache = ColorMatchSolveCache(capacity: 8)
        let src = makeStats(SIMD3<Float>(0.4, 0, 0), (0.040, 0.001, 0, 0.090, 0, 0.160))
        let ref = makeStats(SIMD3<Float>(0.5, 0.1, 0), (0.010, 0, 0, 0.030, 0, 0.090))
        let fresh = ColorMatchSolver.solve(source: src, reference: ref, solver: .gaussianOT)
        let key = ColorMatchSolveCache.cacheKey(
            sourceStatsHash: src.statsHash, referenceStatsHash: ref.statsHash,
            solver: .gaussianOT)
        cache.store(fresh, for: key)
        let consulted = cache.solution(for: key)
        XCTAssertEqual(consulted, fresh, "cache transparency")
        XCTAssertEqual(cache.countForTesting, 1)

        // LRU: 8 entries hold, the 9th evicts the least-recent.
        for i in 0..<8 {
            let s = makeStats(SIMD3<Float>(0.4, Float(i), 0), (0.040, 0, 0, 0.090, 0, 0.160))
            let k = ColorMatchSolveCache.cacheKey(
                sourceStatsHash: s.statsHash, referenceStatsHash: 0, solver: .gaussianOT)
            cache.store(fresh, for: k)
        }
        XCTAssertEqual(cache.countForTesting, 8, "the LRU cap holds 8 after the eviction")
        // The original key was least-recently used → evicted.
        XCTAssertNil(cache.solution(for: key))
        XCTAssertEqual(cache.countForTesting, 8, "a miss lookup does not insert")

        cache.invalidateAll()
        XCTAssertEqual(cache.countForTesting, 0)
    }

    /// The cache-key fold order is PINNED (FilmSolveCache precedent): the
    /// canonical (0, 0, gaussianOT) key's exact value; the tag participates;
    /// swapping source/reference flips the key.
    func testG1CacheKeyFoldOrderPinned() {
        XCTAssertEqual(
            ColorMatchSolveCache.cacheKey(sourceStatsHash: 0, referenceStatsHash: 0, solver: .gaussianOT),
            2495982924697081349,
            "the canonical gaussianOT key literal (DECISIONS)")
        XCTAssertEqual(
            ColorMatchSolveCache.cacheKey(sourceStatsHash: 0, referenceStatsHash: 0, solver: .reinhard),
            3458577883779271296,
            "the canonical reinhard key literal (DECISIONS)")
        let a = ColorMatchSolveCache.cacheKey(sourceStatsHash: 1, referenceStatsHash: 2, solver: .gaussianOT)
        let b = ColorMatchSolveCache.cacheKey(sourceStatsHash: 2, referenceStatsHash: 1, solver: .gaussianOT)
        XCTAssertNotEqual(a, b, "the fold is order-sensitive (source ⊕ reference)")
    }

    // MARK: - G3 synthetic recovery

    /// The moment-exact arm: hand-built stats with Σt := T·Σs·Tᵀ, μt :=
    /// T·μs + c — the solve recovers T EXACTLY (the commuting family
    /// T = V·diag(+)·Vᵀ is the OT map of the pair by construction — the
    /// sandwich algebra collapses onto T; a non-commuting T_true would NOT be
    /// the recovery target, the Gaussian stats cannot see it).
    func testG3MomentExactRecoveryS1() {
        let src = makeStats(
            SIMD3<Float>(0.45, 0.02, -0.03),
            (0.010, 0.0021, -0.0004, 0.0036, 0.0009, 0.0064))
        // T_true = V·diag(1.3, 0.8, 1.15)·Vᵀ (SPD, full in the standard
        // basis — non-diagonal, non-commuting with Σs).
        let v = fixedV
        let vT = v.transpose
        let scaled = simd_double3x3(columns: (
            v.columns.0 * 1.3, v.columns.1 * 0.8, v.columns.2 * 1.15))
        let t = scaled * vT
        let cTrue = SIMD3<Double>(0.05, -0.03, 0.02)
        let muS = SIMD3<Double>(src.mu)
        let muT = t * muS + cTrue
        // Σt = T·Σs·Tᵀ (exact in Float64 assembly).
        let S = full(src.sigma)
        let tRowMajor = rowMajor(t)
        let sigmaT = matMul(matMul(tRowMajor, S), transpose(tRowMajor))
        let ref = makeStats(
            SIMD3<Float>(Float(muT.x), Float(muT.y), Float(muT.z)),
            (Float(sigmaT[0]), Float(sigmaT[1]), Float(sigmaT[2]),
             Float(sigmaT[4]), Float(sigmaT[5]), Float(sigmaT[8])))

        let sol = ColorMatchSolver.solve(source: src, reference: ref, solver: .gaussianOT)
        let band = relErr(sol.matrix.map(Double.init), tRowMajor)
        // The plan gate: ≤1e-3 (the Float64 solve recovers to ~1e-15; the
        // Float32 demotion carries ~1e-7 — measured band → DECISIONS).
        XCTAssertLessThanOrEqual(band, 1e-3, "moment-exact S1 recovery band, got \(band)")
        for i in 0..<3 {
            XCTAssertEqual(Double(sol.offset[i]), cTrue[i], accuracy: 1e-4, "offset[\(i)]")
        }
    }

    /// The sampled arm: an LCG cloud mapped through the same T_true — the
    /// per-channel 1%/99% trims shuffle boundary samples (the mapped
    /// marginals' percentiles select a slightly different population), so the
    /// recovery carries a trim-shuffle band (measured → DECISIONS; the plan's
    /// "实测带" face).
    func testG3SampledRecoveryS1() {
        var rng = LCG(seed: 0x93)
        var source: [SIMD3<Float>] = []
        for _ in 0..<20000 {
            source.append(SIMD3<Float>(
                Float(0.45 + 0.10 * rng.gaussian()),
                Float(0.02 + 0.06 * rng.gaussian()),
                Float(-0.03 + 0.08 * rng.gaussian())))
        }
        let src = try! ColorMatchStats.extract(samples: source)
        // T_true (same commuting family).
        let v = fixedV
        let scaled = simd_double3x3(columns: (
            v.columns.0 * 1.3, v.columns.1 * 0.8, v.columns.2 * 1.15))
        let t = scaled * v.transpose
        let tRowMajor = rowMajor(t)
        let cTrue = SIMD3<Double>(0.05, -0.03, 0.02)
        let mapped = source.map { s -> SIMD3<Float> in
            let m = t * SIMD3<Double>(s) + cTrue
            return SIMD3<Float>(Float(m.x), Float(m.y), Float(m.z))
        }
        let ref = try! ColorMatchStats.extract(samples: mapped)

        let sol = ColorMatchSolver.solve(source: src, reference: ref, solver: .gaussianOT)
        let band = relErr(sol.matrix.map(Double.init), tRowMajor)
        // The measured band (DECISIONS): worst 1.73e-2 relative — the
        // per-channel trim shuffle sits orders above the moment-exact arm;
        // the gate pins ~3.5× headroom (实测带收窄钉门).
        XCTAssertLessThanOrEqual(band, 0.06, "sampled S1 recovery band, got \(band)")
        XCTAssertGreaterThanOrEqual(band, 0, "the band is a measurement")
        // And the LCG regenerates (the re-derivation identity face).
        var rng2 = LCG(seed: 0x93)
        var source2: [SIMD3<Float>] = []
        for _ in 0..<20000 {
            source2.append(SIMD3<Float>(
                Float(0.45 + 0.10 * rng2.gaussian()),
                Float(0.02 + 0.06 * rng2.gaussian()),
                Float(-0.03 + 0.08 * rng2.gaussian())))
        }
        XCTAssertEqual(source2, source, "LCG seed regenerates the drive set")
    }

    /// The S3 diagonal recovery: a diagonal source covariance and a diagonal
    /// T_true (positive) — per-axis variance ratios recover the entries.
    func testG3DiagonalRecoveryS3() {
        let src = makeStats(
            SIMD3<Float>(0.45, 0.02, -0.03), (0.040, 0, 0, 0.090, 0, 0.160))
        // T_true diag = (0.5, 1.5, 0.25); Σt = diag(T²·σ²).
        let t = [0.5, 1.5, 0.25]
        let sigmaS = [0.040, 0.090, 0.160]
        let sigmaT = (0.25 * sigmaS[0], 2.25 * sigmaS[1], 0.0625 * sigmaS[2])
        let muT = SIMD3<Float>(0.6, 0.1, 0.0)
        let ref = makeStats(muT, (Float(sigmaT.0), 0, 0, Float(sigmaT.1), 0, Float(sigmaT.2)))
        let sol = ColorMatchSolver.solve(source: src, reference: ref, solver: .reinhard)
        for i in 0..<3 {
            XCTAssertEqual(
                Double(sol.matrix[i * 3 + i]), t[i], accuracy: 1e-6, "T diag [\(i)]")
        }
        // Off-diagonal entries stay zero (a diagonal map).
        for (i, want) in [1, 2, 3, 5, 6, 7].enumerated() {
            XCTAssertEqual(Double(sol.matrix[want]), 0, accuracy: 1e-9, "off-diag \(i)")
        }
        // offset = μt − T·μs.
        XCTAssertEqual(Double(sol.offset[0]), 0.6 - t[0] * 0.45, accuracy: 1e-6)
        XCTAssertEqual(Double(sol.offset[1]), 0.1 - t[1] * 0.02, accuracy: 1e-6)
        XCTAssertEqual(Double(sol.offset[2]), 0.0 - t[2] * -0.03, accuracy: 1e-6)
    }

    // MARK: - helpers

    /// The row-major 9-tuple of a simd matrix (column face → row-major).
    private func rowMajor(_ m: simd_double3x3) -> [Double] {
        let c = m.columns
        return [
            Double(c.0.x), Double(c.1.x), Double(c.2.x),
            Double(c.0.y), Double(c.1.y), Double(c.2.y),
            Double(c.0.z), Double(c.1.z), Double(c.2.z),
        ]
    }

    private func transpose(_ m: simd_double3x3) -> [Double] {
        rowMajor(m)
    }
}

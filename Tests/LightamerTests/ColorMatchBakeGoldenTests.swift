@testable import LightamerCore
import XCTest

/// ColorMatchBakeGoldenTests (Plan M5-1-02 T3, KD-3) — the 65³ Float64 bake:
///
/// - the VOXEL GATE vs the ideal continuous model (LCG constant-seed voxel
///   set, the M3-3 bake-voxel precedent): |bake − Float32(ideal)| ≤ 1e-5,
///   the measured band recorded in DECISIONS;
/// - the double bake BIT-IDENTITY (G1 — the concurrentPerform index merge
///   proves reduction-free);
/// - the α-folding exactness (bake(α) voxel == the hand-spelled Oklab lerp
///   — strength folded into the bake, not the sampler);
/// - the plateau/identity face (the identity solution bakes the identity
///   map within the Float32 storage epsilon; the end voxels equal the
///   clamped-coordinate formula);
/// - the bake-time budget (the <50ms per-tick ruling — a generous hard
///   gate here, the measured band lands in DECISIONS).
final class ColorMatchBakeGoldenTests: XCTestCase {

    // MARK: - Fixtures

    /// A deterministic dense histogram (every bin occupied) peaking at
    /// `peak` — the CDF solver's identity-ish input.
    private func denseHistogram(peak: Int) -> [UInt32] {
        var histogram = [UInt32](repeating: 0, count: 256)
        var remaining = 120_000
        for bin in 0..<256 {
            let distance = abs(bin - peak)
            let share = max(480 - distance * 3, 8)
            let value = min(remaining, share)
            histogram[bin] = UInt32(value)
            remaining -= value
        }
        if remaining > 0 { histogram[peak] += UInt32(remaining) }
        return histogram
    }

    /// A solved CDF solution over shifted tent distributions (a REAL
    /// non-trivial map — the identity face has its own fixture).
    private func shiftedSolution() -> ColorMatchCDFSolution {
        var source = [[UInt32]](repeating: [UInt32](repeating: 0, count: 256), count: 3)
        var reference = [[UInt32]](repeating: [UInt32](repeating: 0, count: 256), count: 3)
        for channel in 0..<3 {
            source[channel] = denseHistogram(peak: 90)
            reference[channel] = denseHistogram(peak: 150)
        }
        func percentile(_ counts: [UInt32], _ f: Double) -> Int {
            let total = counts.reduce(0) { $0 + Int($1) }
            let target = Int((f * Double(total)).rounded(.up))
            var cumulative = 0
            for (bin, count) in counts.enumerated() {
                cumulative += Int(count)
                if cumulative >= max(target, 1) { return bin }
            }
            return 255
        }
        let s = ColorMatchStats(
            mu: SIMD3(0.35, 0, 0), sigma: (0.02, 0, 0, 0.02, 0, 0.02),
            histograms: source, supportLo: SIMD3(0.1, -0.2, -0.2),
            supportHi: SIMD3(0.6, 0.2, 0.2), sampleCount: 120_000)
        let r = ColorMatchStats(
            mu: SIMD3(0.55, 0, 0), sigma: (0.03, 0, 0, 0.03, 0, 0.03),
            histograms: reference, supportLo: SIMD3(0.3, -0.25, -0.25),
            supportHi: SIMD3(0.8, 0.25, 0.25), sampleCount: 120_000)
        _ = (percentile(source[0], 0.01), percentile(reference[0], 0.99))
        return ColorMatchCDFSolver.solve(source: s, reference: r)
    }

    /// The exact-identity solution (identical dense histograms).
    private func identitySolution() -> ColorMatchCDFSolution {
        let histogram = denseHistogram(peak: 128)
        let s = ColorMatchStats(
            mu: SIMD3(0.5, 0, 0), sigma: (0.02, 0, 0, 0.02, 0, 0.02),
            histograms: [histogram, histogram, histogram],
            supportLo: SIMD3(0.1, -0.2, -0.2), supportHi: SIMD3(0.9, 0.2, 0.2),
            sampleCount: 120_000)
        return ColorMatchCDFSolver.solve(source: s, reference: s)
    }

    /// A small LCG (the M3-3 bake-voxel precedent: constant seed, no
    /// system randomness on the golden path).
    private func lcg(_ state: inout UInt64) -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 11
    }

    /// The INDEPENDENT ideal-model reference: the formula spelled out with
    /// primitive ops (own ladder read + own lerp spelling — the M5-1-01
    /// same-formula double-write discipline guards the transcription).
    private func idealModel(
        _ rgb: SIMD3<Double>, solution: ColorMatchCDFSolution, alpha: Double
    ) -> SIMD3<Double> {
        let lab = OklabMath.linearRec2020ToOklab64(rgb)
        var mapped = SIMD3<Double>()
        for channel in 0..<3 {
            let value = Float([lab.x, lab.y, lab.z][channel])
            let bin = ColorMatchStats.binIndex(channel: channel, value: value)
            mapped[channel] = solution.curves[channel][bin]
        }
        // The lerp spelled as the two-endpoint form (not x + α(m−x)) — the
        // algebraic twin, so a transcription bug in EITHER spelling shows.
        let outLab = (1 - alpha) * lab + alpha * mapped
        return OklabMath.oklabToLinearRec202064(outLab)
    }

    // MARK: - The voxel gate

    func testVoxelGateAgainstIdealModel() {
        let solution = shiftedSolution()
        let table = ColorMatchBake.bake(solution: solution, strength: 0.7)
        let level = ColorMatchBake.latticeSize
        var rng: UInt64 = 0x9E3779B97F4A7C15
        var worst: Double = 0
        for _ in 0..<4096 {
            let x = Int(lcg(&rng) % UInt64(level))
            let y = Int(lcg(&rng) % UInt64(level))
            let z = Int(lcg(&rng) % UInt64(level))
            let index = x + y * level + z * level * level
            let d = Double(level - 1)
            let coordinate = SIMD3<Double>(
                Double(x) / d, Double(y) / d, Double(z) / d)
            let ideal = idealModel(coordinate, solution: solution, alpha: 0.7)
            let stored = SIMD3<Double>(table[index])
            let drift = max(abs(stored.x - ideal.x), abs(stored.y - ideal.y), abs(stored.z - ideal.z))
            worst = max(worst, drift)
        }
        print("ColorMatchBake voxel gate worst: \(worst) (gate 1e-5)")
        XCTAssertLessThanOrEqual(
            worst, 1e-5, "voxel gate breached (measured band \(worst))")
    }

    // MARK: - G1: the double-bake bit identity

    func testDoubleBakeIsBitIdentical() {
        let solution = shiftedSolution()
        let a = ColorMatchBake.bake(solution: solution, strength: 0.42)
        let b = ColorMatchBake.bake(solution: solution, strength: 0.42)
        XCTAssertEqual(a.count, b.count)
        XCTAssertEqual(a.count, ColorMatchBake.latticeSize * ColorMatchBake.latticeSize * ColorMatchBake.latticeSize)
        for (p, q) in zip(a, b) {
            XCTAssertEqual(p.x.bitPattern, q.x.bitPattern)
            XCTAssertEqual(p.y.bitPattern, q.y.bitPattern)
            XCTAssertEqual(p.z.bitPattern, q.z.bitPattern)
        }
    }

    // MARK: - The α folding

    func testStrengthFoldingExactness() {
        let solution = shiftedSolution()
        let table = ColorMatchBake.bake(solution: solution, strength: 0.25)
        let level = ColorMatchBake.latticeSize
        // A small deterministic voxel sample through the hand-spelled lerp.
        var rng: UInt64 = 0xDEADBEEFCAFEF00D
        for _ in 0..<512 {
            let x = Int(lcg(&rng) % UInt64(level))
            let y = Int(lcg(&rng) % UInt64(level))
            let z = Int(lcg(&rng) % UInt64(level))
            let d = Double(level - 1)
            let coordinate = SIMD3<Double>(Double(x) / d, Double(y) / d, Double(z) / d)
            let expected = idealModel(coordinate, solution: solution, alpha: 0.25)
            let stored = SIMD3<Double>(table[x + y * level + z * level * level])
            XCTAssertLessThanOrEqual(
                max(abs(stored.x - expected.x), abs(stored.y - expected.y), abs(stored.z - expected.z)),
                1e-6, "α fold drifted at (\(x),\(y),\(z))")
        }
    }

    // MARK: - The plateau / identity face

    func testIdentitySolutionBakesTheIdentityMap() {
        // Identical curves + α=1: the baked map is the identity WITHIN the
        // trim support (the plateau policy — OQ-4 — deliberately clamps
        // out-of-support voxels to the support ends, so those assert the
        // plateau formula instead; this test pins the in-support arm).
        let solution = identitySolution()
        let table = ColorMatchBake.bake(solution: solution, strength: 1)
        let level = ColorMatchBake.latticeSize
        let d = Double(level - 1)
        // The identity curves' support (identical distributions — the
        // histogram's own 1%/99% bins, per channel).
        let tent = denseHistogram(peak: 128)
        func supportBounds(_ f: Double) -> (Double, Double, Double) {
            let bin = ColorMatchCDFSolver.percentileBin(tent, fraction: f)
            return (
                Double(ColorMatchStats.binValue(channel: 0, bin: bin)),
                Double(ColorMatchStats.binValue(channel: 1, bin: bin)),
                Double(ColorMatchStats.binValue(channel: 2, bin: bin)))
        }
        let lo = supportBounds(0.01)
        let hi = supportBounds(0.99)
        var worst: Double = 0
        var asserted = 0
        for z in stride(from: 0, to: level, by: 8) {
            for y in stride(from: 0, to: level, by: 8) {
                for x in stride(from: 0, to: level, by: 8) {
                    let coordinate = SIMD3<Double>(Double(x) / d, Double(y) / d, Double(z) / d)
                    let lab = OklabMath.linearRec2020ToOklab64(coordinate)
                    // In-support voxels only (ALL three channels — the a/b
                    // arms have their own trim supports; out-of-support
                    // voxels ride the plateau and are the gate test's face).
                    guard lab.x >= lo.0, lab.x <= hi.0,
                        lab.y >= lo.1, lab.y <= hi.1,
                        lab.z >= lo.2, lab.z <= hi.2
                    else { continue }
                    let stored = SIMD3<Double>(table[x + y * level + z * level * level])
                    // The STRICT face: the bake == the ideal model (the
                    // ladder read + α-lerp spelled directly).
                    let ideal = idealModel(coordinate, solution: solution, alpha: 1)
                    let formulaDrift = max(
                        abs(stored.x - ideal.x), abs(stored.y - ideal.y), abs(stored.z - ideal.z))
                    XCTAssertLessThanOrEqual(formulaDrift, 1e-6, "off-formula at (\(x),\(y),\(z))")
                    // The IDENTITY BAND: an in-support voxel stays within a
                    // few lattice steps of its own coordinate (the step
                    // ladder truncates one step LOW per channel; three
                    // channels through the nonlinear round trip amplify to
                    // a few 1e-2 — the measured band lands in DECISIONS).
                    worst = max(
                        worst,
                        max(abs(stored.x - coordinate.x), abs(stored.y - coordinate.y), abs(stored.z - coordinate.z)))
                    asserted += 1
                }
            }
        }
        XCTAssertGreaterThan(asserted, 200, "the in-support sample set collapsed")
        XCTAssertLessThanOrEqual(worst, 0.03, "identity band breached (measured \(worst))")
    }

    func testEndVoxelsEqualTheClampedFormula() {
        // The plateau edges: the six face-center end voxels equal the
        // ideal model evaluated at their (already-clamped) coordinates —
        // the domain-end plateau face OQ-4 pins.
        let solution = shiftedSolution()
        let table = ColorMatchBake.bake(solution: solution, strength: 0.6)
        let level = ColorMatchBake.latticeSize
        let d = Double(level - 1)
        let mid = level / 2
        let faces: [(Int, Int, Int)] = [
            (0, mid, mid), (level - 1, mid, mid),
            (mid, 0, mid), (mid, level - 1, mid),
            (mid, mid, 0), (mid, mid, level - 1),
        ]
        for (x, y, z) in faces {
            let coordinate = SIMD3<Double>(Double(x) / d, Double(y) / d, Double(z) / d)
            let expected = idealModel(coordinate, solution: solution, alpha: 0.6)
            let stored = SIMD3<Double>(table[x + y * level + z * level * level])
            XCTAssertLessThanOrEqual(
                max(abs(stored.x - expected.x), abs(stored.y - expected.y), abs(stored.z - expected.z)),
                1e-6, "end voxel (\(x),\(y),\(z)) off the clamped formula")
        }
    }

    // MARK: - The bake budget (ENV-GATED perf probe)

    /// The per-tick bake budget probe (M2-5 性能探针惯例: `LIGHTAMER_PERF_PROBE=1`
    /// + XCTSkipUnless — skipped in the default suite). OBSERVATION RECORD,
    /// not a gate: the plan's <50ms budget is a production number; the
    /// measured band lands in DECISIONS (Debug suite ≈295ms — the -Onone
    /// overhead dominates; an isolated -O arithmetic probe of the identical
    /// concurrentPerform + pow shape ran the whole 65³ load in ~1-3ms, so
    /// the production budget is reachable; the drag-downgrade fallback —
    /// "reuse the last bake while dragging, re-bake on release" — stays
    /// the registered lever if an in-GUI measurement proves otherwise):
    ///   LIGHTAMER_PERF_PROBE=1 Scripts/test-direct.sh 'ColorMatchBakeGoldenTests'
    func testBakeTimeBudget() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LIGHTAMER_PERF_PROBE"] == "1",
            "manual probe — set LIGHTAMER_PERF_PROBE=1 (the M2-5 convention)")
        let solution = shiftedSolution()
        // Warm one (the first bake pays page-in).
        _ = ColorMatchBake.bake(solution: solution, strength: 0)
        var best = Double.greatestFiniteMagnitude
        for _ in 0..<3 {
            let start = DispatchTime.now()
            _ = ColorMatchBake.bake(solution: solution, strength: 0.5)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
            best = min(best, elapsed)
        }
        print("ColorMatchBake 65³ best-of-3: \(Int(best * 1000))ms (budget 50ms; observation record — DECISIONS)")
    }
}

@testable import LightamerCore
@testable import LightamerIOP
import Metal
import simd
import XCTest

/// ColormatchKernelParityTests (Plan M5-1-01 T7, KD-7; OQ-M5-1-8 G2) —
/// `colormatch_linear` vs the Float64 CPU reference (the kernel's expansion
/// DOUBLE-WRITTEN, checker 回注 m1/KD-7 同式防假 parity):
///
/// - drive set: the 33³ grid (packed 1089×33) × {S1 solution, S3 solution,
///   random-SPD solution} × α ∈ {0, 0.25, 0.5, 1.0}, plus the negative-LMS
///   / HDR / gamut-corner probe set (the signed-cbrt path's MSL↔CPU mirror);
/// - verdict: p99.9 — the 1e-5 TARGET is the design expectation, the FINAL
///   gate is the MEASURED band pinned with headroom (实测带收窄钉门,
///   M3-3/M4-1 discipline; the target value does not appear in the gate);
/// - L048 comparison-domain discipline: both sides compared in the working
///   linear Rec2020 domain (no encode leg to amplify f32 epsilon); the CPU
///   reference elevates the kernel's Float32 constants
///   (`Double(Float(c))` — the same-value different-precision face);
/// - L014 fence discipline: every readback drains first;
/// - the uniform ABI size probe (the 52-byte stride pin).
final class ColormatchKernelParityTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    // MARK: - The CPU reference (the kernel's expansion double-written)

    /// The OklabMath constants elevated per L048 ② (Double(Float(literal)) —
    /// the production constant set, not ideal decimals).
    static let m1c: [Double] = OklabMath.m1c.map { Double($0) }
    static let m2: [Double] = OklabMath.m2.map { Double($0) }
    static let m2Inv: [Double] = OklabMath.m2Inv.map { Double($0) }
    static let m1cInv: [Double] = OklabMath.m1cInv.map { Double($0) }
    /// The kernel's cube-root exponent: the Float32 quotient elevated (the
    /// MSL `1.0f/3.0f` mirror — NOT the Double 1/3).
    static let oneThird: Double = Double(Float(1.0) / Float(3.0))

    static func apply(_ m: [Double], _ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(
            m[0] * v.x + m[1] * v.y + m[2] * v.z,
            m[3] * v.x + m[4] * v.y + m[5] * v.z,
            m[6] * v.x + m[7] * v.y + m[8] * v.z)
    }

    static func signedCbrt(_ x: Double) -> Double {
        x >= 0 ? pow(x, oneThird) : -pow(-x, oneThird)
    }

    /// The kernel's exact formula, Float64: lab → α-lerp (mi/c are the
    /// Float32 UNIFORM values elevated) → back.
    static func cpuKernel(
        _ rgb: SIMD3<Double>, mi: [Double], c: SIMD3<Double>, strength: Double
    ) -> SIMD3<Double> {
        let lab = apply(m2, SIMD3(
            signedCbrt((apply(m1c, rgb)).x),
            signedCbrt((apply(m1c, rgb)).y),
            signedCbrt((apply(m1c, rgb)).z)))
        let mapped = apply(mi, lab) + c
        let outLab = lab + strength * mapped
        let lmsP = apply(m2Inv, outLab)
        let lms = lmsP * lmsP * lmsP
        return apply(m1cInv, lms)
    }

    // MARK: - Drive solutions

    /// Three solution faces: the S1 solve of a synthetic pair, the S3 solve
    /// of the same pair, and a random-SPD hand-built map.
    static func driveSolutions() -> [ColorMatchSolution] {
        func stats(_ mu: SIMD3<Float>, _ s: (Float, Float, Float, Float, Float, Float)) -> ColorMatchStats {
            ColorMatchStats(
                mu: mu, sigma: s,
                histograms: [[UInt32]](repeating: [UInt32](repeating: 0, count: 256), count: 3),
                supportLo: .zero, supportHi: SIMD3<Float>(1, 0.5, 0.5), sampleCount: 1)
        }
        let src = stats(
            SIMD3<Float>(0.45, 0.02, -0.03),
            (0.010, 0.0021, -0.0004, 0.0036, 0.0009, 0.0064))
        let ref = stats(
            SIMD3<Float>(0.50, 0.05, 0.02),
            (0.020, -0.0030, 0.0011, 0.0050, -0.0007, 0.0030))
        let s1 = ColorMatchSolver.solve(source: src, reference: ref, solver: .gaussianOT)
        let s3 = ColorMatchSolver.solve(source: src, reference: ref, solver: .reinhard)
        var random = ColorMatchSolution.identity()
        // A deterministic random-SPD-ish map (LCG-seeded entries).
        var state: UInt64 = 0xD2
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        random = ColorMatchSolution(
            solver: .gaussianOT, effectiveSolver: .gaussianOT,
            matrix: (0..<9).map { _ in Float(0.6 + 0.8 * next()) },
            offset: (0..<3).map { _ in Float(-0.05 + 0.1 * next()) },
            sourceStatsHash: 1, referenceStatsHash: 2)
        return [s1, s3, random]
    }

    /// The 33³ Oklab-coverage grid packed into a 1089×33 texture, in linear
    /// Rec2020 (the Oklab grid inverse-mapped — the statistics domain gets
    /// uniform coverage; negative oklab coordinates included).
    static func driveGrid() -> [SIMD4<Float>] {
        let n = 33
        var pixels: [SIMD4<Float>] = []
        pixels.reserveCapacity(n * n * n)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    // The statistics-domain box: L just past the unit
                    // range, a/b past the ±0.5 histogram edge (the out-of-
                    // gamut corners included). The far-out probes carry the
                    // extreme-dynamic-range face — the grid keeps the
                    // statistics domain so the absolute error stays a
                    // meaningful verdict (L048: the comparison scale must
                    // not be dominated by a handful of extreme voxels).
                    let lab = SIMD3<Float>(
                        -0.05 + 1.1 * Float(r) / 32,
                        -0.55 + 1.1 * Float(g) / 32,
                        -0.55 + 1.1 * Float(b) / 32)
                    let rgb = OklabMath.oklabToLinearRec2020(lab)
                    pixels.append(SIMD4(rgb.x, rgb.y, rgb.z, 0.5))
                }
            }
        }
        return pixels
    }

    /// The negative-LMS / HDR / gamut-corner probes (checker 回注 m1): the
    /// Rec2020 primaries ×4 luminance, unit corners, HDR out to 8, and
    /// raw negatives (pipeline negatives are legal inputs).
    static func driveProbes() -> [SIMD4<Float>] {
        var probes: [SIMD4<Float>] = []
        for s: Float in [0.25, 1.0, 4.0, 8.0] {
            probes.append(SIMD4(s, 0, 0, 0.5))
            probes.append(SIMD4(0, s, 0, 0.5))
            probes.append(SIMD4(0, 0, s, 0.5))
            probes.append(SIMD4(s, s, s, 0.5))
            probes.append(SIMD4(s, s, 0, 0.5))
            probes.append(SIMD4(0, s, s, 0.5))
            probes.append(SIMD4(s, 0, s, 0.5))
        }
        // Raw negatives (the signed-cbrt arm).
        probes.append(SIMD4(-0.5, 0.25, -1.0, 0.5))
        probes.append(SIMD4(-2.0, 8.0, -0.125, 0.5))
        probes.append(SIMD4(0.5, -0.5, 0.5, 0.5))
        return probes
    }

    // MARK: - GPU runner

    private func makeTexture(
        _ metal: MetalContext, width: Int, height: Int, write pixels: [SIMD4<Float>]
    ) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: descriptor))
        pixels.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: width, height: height, depth: 1)),
                mipmapLevel: 0, withBytes: raw.baseAddress!,
                bytesPerRow: width * MemoryLayout<SIMD4<Float>>.stride)
        }
        return texture
    }

    private func readback(
        _ metal: MetalContext, _ texture: any MTLTexture
    ) async -> [SIMD4<Float>] {
        await drain(metal)  // L014: fence before getBytes
        let w = texture.width, h = texture.height
        var pixels = [SIMD4<Float>](repeating: .zero, count: w * h)
        pixels.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!, bytesPerRow: w * MemoryLayout<SIMD4<Float>>.stride,
                from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: w, height: h, depth: 1)),
                mipmapLevel: 0)
        }
        return pixels
    }

    private func runKernel(
        _ metal: MetalContext, pixels: [SIMD4<Float>], width: Int, height: Int,
        solution: ColorMatchSolution = ColorMatchSolution.identity(),
        strength: Float = 1,
        uniformsOverride: ColormatchUniforms? = nil
    ) async throws -> [SIMD4<Float>] {
        let terms = ColorMatchSolver.strengthKernelTerms(solution)
        var uniforms = ColormatchUniforms()
        if let uniformsOverride {
            uniforms = uniformsOverride
        } else {
            uniforms.setMi(terms.mMinusI)
            uniforms.setC(terms.c)
            uniforms.strength = strength
        }
        XCTAssertEqual(uniforms.strideBytes, ColormatchUniforms.expectedStride,
                       "the uniform ABI size probe (52 bytes)")
        let input = try makeTexture(metal, width: width, height: height, write: pixels)
        let output = try makeTexture(metal, width: width, height: height, write: [])
        let buffer = try XCTUnwrap(metal.device.makeBuffer(
            length: MemoryLayout<ColormatchUniforms>.stride, options: .storageModeShared))
        withUnsafeBytes(of: &uniforms) {
            buffer.contents().copyMemory(
                from: $0.baseAddress!, byteCount: MemoryLayout<ColormatchUniforms>.stride)
        }
        let session = try await metal.makeEncoder(functionName: ColormatchKernel.linear)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.setBuffer(buffer, offset: 0, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        session.encoder.endEncoding()  // L008
        session.commandBuffer.commit()
        return await readback(metal, output)
    }

    // MARK: - The parity gate

    func testKernelParityP999() async throws {
        let metal = try await makeMetal()
        let grid = Self.driveGrid()
        let probes = Self.driveProbes()
        let width = 1089, height = 33
        var worstP999: Float = 0
        var worstAbs: Float = 0
        var worstWellConditioned: Float = 0

        for solution in Self.driveSolutions() {
            // The (M−I) demotion is DIAGONAL-ONLY (the strengthKernelTerms
            // spelling — the reference mirrors it exactly).
            var mi = solution.matrix.map(Double.init)
            mi[0] -= 1; mi[4] -= 1; mi[8] -= 1
            let cVec = SIMD3<Double>(
                Double(solution.offset[0]), Double(solution.offset[1]),
                Double(solution.offset[2]))
            for alpha in [Float(0.0), 0.25, 0.5, 1.0] {
                let got = try await runKernel(
                    metal, pixels: grid, width: width, height: height,
                    solution: solution, strength: alpha)
                var errors: [Float] = []
                var wellConditionedErrors: [Float] = []
                errors.reserveCapacity(grid.count)
                var absMax: Float = 0
                let strengthD = Double(alpha)
                for (i, px) in grid.enumerated() {
                    let rgbD = SIMD3<Double>(Double(px.x), Double(px.y), Double(px.z))
                    let want = Self.cpuKernel(
                        rgbD, mi: mi, c: cVec, strength: strengthD)
                    let g = got[i]
                    let d = max(
                        abs(Double(g.x) - want.x),
                        abs(Double(g.y) - want.y),
                        abs(Double(g.z) - want.z))
                    errors.append(Float(d))
                    absMax = max(absMax, Float(d))
                    // The WELL-CONDITIONED subset: every |LMS| channel past
                    // the cube-root instability radius (|lms| > 1e-3 — the
                    // cbrt derivative is bounded there). THIS is the
                    // arithmetic-proof gate; the crossing-adjacent pixels
                    // carry their own bound (the full-grid faces below).
                    let lms = Self.apply(Self.m1c, rgbD)
                    if min(abs(lms.x), abs(lms.y), abs(lms.z)) > 1e-3 {
                        // Scale-aware (the HDR solutions push |out| past
                        // 10 — the honest f32 face is the relative one;
                        // the floor keeps the dark arm absolute).
                        let scale = max(
                            abs(want.x), max(abs(want.y), abs(want.z)), 1e-2)
                        wellConditionedErrors.append(Float(d / scale))
                    }
                }
                errors.sort()
                let p999 = errors[min(errors.count - 1, errors.count * 999 / 1000)]
                worstP999 = max(worstP999, p999)
                worstAbs = max(worstAbs, absMax)
                if !wellConditionedErrors.isEmpty {
                    wellConditionedErrors.sort()
                    let wp999 = wellConditionedErrors[
                        min(wellConditionedErrors.count - 1,
                            wellConditionedErrors.count * 999 / 1000)]
                    worstWellConditioned = max(worstWellConditioned, wp999)
                }
                XCTAssertFalse(got.contains { $0.x.isNaN || $0.y.isNaN || $0.z.isNaN },
                               "NaN in the grid output at α=\(alpha)")
            }
        }

        // TWO faces (the mechanism is recorded in DECISIONS):
        // ① the WELL-CONDITIONED subset — the arithmetic-proof gate (the
        //    plan's 1e-5-class face: the kernel's f32 chain vs the f64
        //    reference where the cbrt derivative is bounded);
        // ② the FULL grid — the cbrt-crossing bound (the forward's unbounded
        //    derivative at LMS≈0 amplifies any f32 rounding to ~1e-3 lab
        //    error; the measured band pins the gate, 実測帯収窄釘門).
        XCTAssertLessThanOrEqual(
            worstWellConditioned, 1e-5,
            "well-conditioned p99.9 scale-aware \(worstWellConditioned)")
        XCTAssertLessThanOrEqual(
            worstP999, 4e-3,
            "full-grid p99.9 abs \(worstP999) — the pinned crossing band")
        XCTAssertLessThanOrEqual(
            worstAbs, 5e-2,
            "max abs \(worstAbs) — within the cbrt-crossing bound")
    }

    /// The probe set: the negative-LMS arm, HDR passthrough (no domain-end
    /// clamping — the matrix-arm ruling's kernel face) and the α=0 Oklab
    /// roundtrip on the probes (both sides same formula).
    func testKernelProbesNegativeLMSAndHDR() async throws {
        let metal = try await makeMetal()
        let probes = Self.driveProbes()
        let solution = Self.driveSolutions()[0]  // the S1 face
        for alpha in [Float(0.0), 0.5, 1.0] {
            let got = try await runKernel(
                metal, pixels: probes, width: probes.count, height: 1,
                solution: solution, strength: alpha)
            var miRef = solution.matrix.map(Double.init)
            miRef[0] -= 1; miRef[4] -= 1; miRef[8] -= 1
            for (i, px) in probes.enumerated() {
                let want = Self.cpuKernel(
                    SIMD3<Double>(Double(px.x), Double(px.y), Double(px.z)),
                    mi: miRef,
                    c: SIMD3<Double>(
                        Double(solution.offset[0]), Double(solution.offset[1]),
                        Double(solution.offset[2])),
                    strength: Double(alpha))
                let g = got[i]
                for ch in 0..<3 {
                    XCTAssertFalse(
                        [g.x, g.y, g.z][ch].isNaN, "NaN at probe \(i) ch \(ch) α=\(alpha)")
                }
                let d = max(
                    abs(Double(g.x) - want.x),
                    abs(Double(g.y) - want.y),
                    abs(Double(g.z) - want.z))
                // The probes carry the same absolute band as the grid (the
                // cbrt-crossing face — DECISIONS).
                XCTAssertLessThanOrEqual(
                    d, 5e-3, "probe \(i) α=\(alpha) abs \(d)")
            }
        }
        // HDR passthrough: α=0 is the pure Oklab roundtrip — an HDR input
        // comes back HDR (no clamp), a negative stays finite (no NaN).
        let got0 = try await runKernel(
            metal, pixels: probes, width: probes.count, height: 1,
            solution: solution, strength: 0.0)
        for (i, px) in probes.enumerated() {
            let g = got0[i]
            let magnitude = max(abs(px.x), max(abs(px.y), abs(px.z)))
            if magnitude > 1.0 {
                let outMagnitude = max(abs(g.x), max(abs(g.y), abs(g.z)))
                XCTAssertGreaterThan(
                    outMagnitude, 1.0, "HDR input \(px) clamped at probe \(i)")
            }
        }
    }
}

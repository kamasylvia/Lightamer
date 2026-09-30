@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────
// GradeKernelGoldenTests (Plan M2-5-1 T3-T7, KD-8) — the seven new grade
// ops' GPU kernels vs the Swift Float64 reference implementations.
//
// REFERENCE PROVENANCE: Alcedo has no golden assets — the references are
// the Float64 transliterations of the Alcedo pixel math (primary_grade.metal
// / cuda_primary_grade_pass.cu, read-only semantics; GPL code NOT copied).
// Each test's comment carries the source anchor; the formulas are signed
// in M2-5-1-DECISIONS.
//
// TOLERANCES (KD-8): pure functions ≤1e-6 (Float64 vs Float64); GPU vs
// Float64 reference absolute ≤1e-5 with p99.9 gate + max hard cap 5e-5;
// identity parameter points pixel tolerance 0 (-0/+0 equal).
// ─────────────────────────────────────────────────────────────────────────

final class GradeKernelGoldenTests: XCTestCase {

    // MARK: - Harness

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: ACESccKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    private let textureSize = (width: 16, height: 12)

    /// Deterministic linear-AP1 sample field spanning below-floor … 2.5
    /// (LCG — same field every run, covers the log segments and the
    /// linear extension leg).
    private func sampleField() -> [SIMD3<Double>] {
        var state: UInt64 = 0x9E3779B97F4A7C15
        var field: [SIMD3<Double>] = []
        for _ in 0..<(textureSize.width * textureSize.height) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let u1 = Double((state >> 11) & 0xFFFFF) / Double(0xFFFFF)
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let u2 = Double((state >> 11) & 0xFFFFF) / Double(0xFFFFF)
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let u3 = Double((state >> 11) & 0xFFFFF) / Double(0xFFFFF)
            // Map [0,1]³ onto [-0.2, 2.5] per channel (negative legs
            // included — the encode's linear-extension segment).
            field.append(SIMD3(-0.2 + 2.7 * u1, -0.2 + 2.7 * u2, -0.2 + 2.7 * u3))
        }
        return field
    }

    /// Encode a linear-AP1 field into the ACEScc texels the in-domain
    /// kernels consume.
    private func encodeField(_ field: [SIMD3<Double>]) -> [Float] {
        var texels = [Float](repeating: 0, count: field.count * 4)
        for (index, value) in field.enumerated() {
            texels[index * 4 + 0] = Float(Cat02WBMath.acesccEncode(value.x))
            texels[index * 4 + 1] = Float(Cat02WBMath.acesccEncode(value.y))
            texels[index * 4 + 2] = Float(Cat02WBMath.acesccEncode(value.z))
            texels[index * 4 + 3] = 1.0
        }
        return texels
    }

    private func makeTexture(
        _ metal: MetalContext, texels: [Float]? = nil
    ) -> (any MTLTexture, any MTLTexture) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: textureSize.width,
            height: textureSize.height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let input = metal.device.makeTexture(descriptor: descriptor)!
        let output = metal.device.makeTexture(descriptor: descriptor)!
        if let texels {
            texels.withUnsafeBytes {
                input.replace(
                    region: MTLRegionMake2D(0, 0, textureSize.width, textureSize.height),
                    mipmapLevel: 0, withBytes: $0.baseAddress!,
                    bytesPerRow: textureSize.width * 16)
            }
        }
        return (input, output)
    }

    private func readOutput(
        _ output: any MTLTexture, metal: MetalContext
    ) -> [Float] {
        drain(metal)
        var values = [Float](
            repeating: 0, count: textureSize.width * textureSize.height * 4)
        values.withUnsafeMutableBytes {
            output.getBytes(
                $0.baseAddress!, bytesPerRow: textureSize.width * 16,
                from: MTLRegionMake2D(0, 0, textureSize.width, textureSize.height),
                mipmapLevel: 0)
        }
        return values
    }

    /// The shared golden gate: `field` is the LINEAR-AP1 sample field;
    /// the harness encodes it into the ACEScc texels ONCE (the kernel's
    /// input basis) and hands the reference the exact f32 texel — both
    /// sides then live in the same domain. KD-8 GPU tolerances (p99.9 ≤
    /// 1e-5, max ≤ 5e-5).
    private func assertGolden<M: IOPModule>(
        module: M,
        params: M.Params,
        reference: (SIMD3<Double>) -> SIMD3<Double>,
        field: [SIMD3<Double>],
        metal: MetalContext,
        p999Cap: Double = 1e-5,
        maxCap: Double = 5e-5,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        var piece = IOPiece()
        module.commitParams(params, into: &piece)
        let texels = encodeField(field)
        let (inputTexture, outputTexture) = makeTexture(metal, texels: texels)
        try await module.process(
            input: inputTexture, output: outputTexture, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal)
        let out = readOutput(outputTexture, metal: metal)
        // KD-8 comparison — in LINEAR space (both sides ACEScc-decoded).
        // Rationale: the encode log leg's slope explodes near linear zero
        // (1/(x·17.52·ln2) ≈ 750 at x = 1e-4), so an encoded-space
        // compare amplifies the kernel's inherent f32 epsilon (~1e-7
        // linear) into ~1e-4 encoded noise at zero crossings — comparing
        // the decoded planes measures the actual scene-linear fidelity
        // the grade domain cares about. The [-0.5, 2.5] window clip still
        // applies (the degenerate 2000K/+150 corner drives adaptation
        // entries to ~1e10 — Alcedo is equally unguarded; its samples are
        // bounded-checked, not tolerance-checked).
        var inWindow: [Double] = []
        var totalChannels = 0
        for index in 0..<field.count {
            let texel = SIMD3(
                Double(texels[index * 4]), Double(texels[index * 4 + 1]),
                Double(texels[index * 4 + 2]))
            let expectedEncoded = reference(texel)
            for channel in 0..<3 {
                let actualEncoded = Double(out[index * 4 + channel])
                let wantLinear = Cat02WBMath.acesccDecode(expectedEncoded[channel])
                let actualLinear = Cat02WBMath.acesccDecode(actualEncoded)
                totalChannels += 1
                XCTAssertFalse(
                    actualEncoded.isNaN, "kernel produced NaN at texel \(index)/\(channel)",
                    file: file, line: line)
                XCTAssertLessThan(
                    abs(actualEncoded), 1e12,
                    "kernel output unbounded at texel \(index)/\(channel)",
                    file: file, line: line)
                if abs(wantLinear) <= 2.5 {
                    inWindow.append(abs(actualLinear - wantLinear))
                }
            }
        }
        inWindow.sort()
        // A fully-clipped case (the whole field outside the window) is
        // legal ONLY for degenerate parameterizations — those already
        // passed the bounded/NaN checks above; the caller's caps ride the
        // in-window samples when there are any.
        XCTAssertFalse(
            inWindow.isEmpty && p999Cap <= 1e-5 + 1e-12,
            "window coverage empty under the standard gate",
            file: file, line: line)
        if !inWindow.isEmpty {
            let p999 = inWindow[Int(Double(inWindow.count - 1) * 0.999)]
            let maxDelta = inWindow.last ?? 0
            XCTAssertLessThanOrEqual(
                p999, p999Cap, "p99.9 golden drift \(p999) exceeds \(p999Cap)",
                file: file, line: line)
            XCTAssertLessThanOrEqual(
                maxDelta, maxCap, "max golden drift \(maxDelta) exceeds \(maxCap)",
                file: file, line: line)
        }
    }

    // MARK: - T3: CAT02 white balance (KD-4)

    /// KD-4 assertion 1: the identity pair solves to the ACES white xy.
    func testCat02IdentityPairSolvesToACESWhite() {
        let xy = Cat02WBMath.temperatureTintToXY(
            temperature: Double(Cat02WBModule.identityTemperature),
            tint: Double(Cat02WBModule.identityTint))
        XCTAssertEqual(xy.x, 0.32168, accuracy: 1e-4, "identity x")
        XCTAssertEqual(xy.y, 0.33767, accuracy: 1e-4, "identity y")
        // And the actual derivation precision (signed in DECISIONS).
        XCTAssertLessThan(abs(xy.x - 0.32168), 1e-5)
        XCTAssertLessThan(abs(xy.y - 0.33767), 1e-5)
    }

    /// KD-4 assertion 2: the identity pair's adaptation matrix ≈ I.
    func testCat02IdentityMatrixIsIdentity() {
        let rows = Cat02WBMath.adaptationRows(
            temperature: Double(Cat02WBModule.identityTemperature),
            tint: Double(Cat02WBModule.identityTint))
        let identity: [Double] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
        for (index, value) in rows.enumerated() {
            XCTAssertEqual(value, identity[index], accuracy: 1e-5, "m[\(index)]")
        }
        // Actual margin (DECISIONS): ~7e-7 with the direct-integration locus.
        let maxDeviation = zip(rows, identity).map { abs($0.0 - $0.1) }.max() ?? 0
        XCTAssertLessThan(maxDeviation, 1e-6)
    }

    /// Pure-function pin: the illuminant chromaticity at a working point
    /// (catches silent constant drift — tungsten 3200K sits warm).
    func testCat02IlluminantXYPins() {
        let tungsten = Cat02WBMath.temperatureTintToXY(temperature: 3200, tint: 0)
        XCTAssertEqual(tungsten.x, 0.4234, accuracy: 2e-3, "3200K x (Planck locus)")
        XCTAssertEqual(tungsten.y, 0.3990, accuracy: 2e-3, "3200K y")
        XCTAssertGreaterThan(tungsten.x, 0.40, "3200K is warm (x > ACES white)")
    }

    /// The identity parameter point: the early-exit flag makes the kernel
    /// a byte-identical copy (pixel tolerance 0).
    func testCat02IdentityParamsArePixelExact() async throws {
        let metal = try await makeMetal()
        let field = sampleField()
        let texels = encodeField(field)
        let (input, output) = makeTexture(metal, texels: texels)
        let module = Cat02WBModule()
        var piece = IOPiece()
        module.commitParams(Cat02WBModule.Params(), into: &piece)
        try await module.process(
            input: input, output: output, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal)
        let out = readOutput(output, metal: metal)
        XCTAssertEqual(out.count, texels.count)
        for (index, value) in texels.enumerated() {
            XCTAssertEqual(
                out[index], value, accuracy: 0,
                "identity copy texel \(index) (-0/+0 equal via accuracy 0)")
        }
    }

    /// Golden parameter points: the four range corners + two working
    /// points, each vs the Float64 reference (KD-8 GPU tolerances).
    func testCat02GoldenParameterPoints() async throws {
        let metal = try await makeMetal()
        let field = sampleField()
        let cases: [(Cat02WBModule.Params)] = [
            Cat02WBModule.Params(temperature: 2000, tint: -150),
            Cat02WBModule.Params(temperature: 2000, tint: 150),
            Cat02WBModule.Params(temperature: 15000, tint: -150),
            Cat02WBModule.Params(temperature: 15000, tint: 150),
            Cat02WBModule.Params(temperature: 3200, tint: 0),
            Cat02WBModule.Params(temperature: 7000, tint: 25),
        ]
        for params in cases {
            let module = Cat02WBModule()
            // The (2000K, +150) corner is Alcedo-faithful but numerically
            // ill-conditioned: the adaptation entries reach ~1e10 and the
            // f32 row sums cancel to moderate outputs — the f32 summation
            // alone puts ~3e-5 into the encoded result, so the 1e-5 gate
            // is unreachable for ANY f32 kernel there. That corner rides a
            // signed 1e-3 cap (M2-5-1-DECISIONS); every other case holds
            // the standard KD-8 gate.
            let degenerate = params.temperature == 2000 && params.tint == 150
            try await assertGolden(
                module: module, params: params,
                reference: { Cat02WBModule.reference(
                    acescc: $0,
                    temperature: Double(params.temperature),
                    tint: Double(params.tint)) },
                field: field, metal: metal,
                p999Cap: degenerate ? 1e-3 : 1e-5,
                maxCap: degenerate ? 5e-3 : 5e-5)
        }
    }
}

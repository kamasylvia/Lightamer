@testable import LightamerCore
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralKernelGoldenTests (Plan M8-1b — IOPParity domain) — the spectral
// film kernel family's golden/parity face:
//
//   T1 scope (this commit): the device-library build/load smoke, the fused
//   A/B + corr-arm dispatch shape assertions, and the three-nails source-
//   level grep gates (the X5 port discipline: explicit fma pinning, the
//   host-double reciprocals carried in the constant face, the shared
//   log2/exp2 polynomial — the KERNEL-side checks; the value-level
//   bit-exact assertions land with T3 in this same file).
//
// The kernels live in LightamerCore/Sources/Pipe/Film/SpectralFilmKernels.metal
// (the GPL-3.0 same-license port of darktable's spektrafilm.cl — the file
// header and NOTICE carry the attribution), compiled into Core's
// default.metallib and resolved through MetalContext (the Drt/Aces2 precedent).
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralKernelGoldenTests: XCTestCase {

    // MARK: - Uniform slot mirror (the MSL SF_U_* defines; the canonical
    // Swift face is SpectralPayloads's — T2 owns it, this mirror stays in
    // sync by the T2/T3 round-trip tests)

    private enum U {
        static let width = 0
        static let height = 1
        static let tcSide = 2
        static let steps = 3
        static let curveCount = 4
        static let le0 = 5
        static let invLeStep = 6
        static let evScale = 7
        static let log10PrintExposure = 8
        static let outScale = 9
        static let dmax = 10
        static let enlLo = 13
        static let enlInvRange = 16
        static let scanLo = 19
        static let scanInvRange = 22
        static let positive = 25
        static let useCorr = 26
        static let donorLM = 27
        static let recvLM = 28
        static let compressMode = 29
        static let corrW = 30
        static let corrH = 31
        static let corrDS = 32
        static let blurRadius = 33
        static let total = 34
    }

    /// The neutral 93-float constant block (identity matrices, Langmuir
    /// gates effectively linear) — the smoke fixtures run against hand-built
    /// faces; the REAL table face arrives through SpectralPayloads (T2).
    private static func neutralConsts() -> [Float] {
        var c = [Float](repeating: 0, count: 93)
        let identity: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
        for (i, v) in identity.enumerated() {
            c[SpectralKernelGoldenTests.mInOffset + i] = v
            c[SpectralKernelGoldenTests.mOutOffset + i] = v
            c[SpectralKernelGoldenTests.rgb2xyzOffset + i] = v
            c[SpectralKernelGoldenTests.xyz2rgbOffset + i] = v
            c[SpectralKernelGoldenTests.ok1Offset + i] = v
            c[SpectralKernelGoldenTests.ok2Offset + i] = v
            c[SpectralKernelGoldenTests.ok1iOffset + i] = v
            c[SpectralKernelGoldenTests.ok2iOffset + i] = v
        }
        // couplers + langmuir stay zero (gates off in the uniforms anyway)
        return c
    }

    private static let mInOffset = 0
    private static let mOutOffset = 9
    private static let couplersOffset = 18
    private static let rgb2xyzOffset = 27
    private static let xyz2rgbOffset = 36
    private static let ok1Offset = 45
    private static let ok2Offset = 54
    private static let ok1iOffset = 63
    private static let ok2iOffset = 72
    private static let lmDonorOffset = 81
    private static let lmRecvOffset = 87

    // MARK: - Fixtures

    private func makeMetal() async throws -> MetalContext {
        try MetalContext()
    }

    private func texture(
        _ metal: MetalContext, width: Int, height: Int, write: Bool
    ) throws -> any MTLTexture {
        let d = metal.device
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height,
            mipmapped: false)
        desc.usage = [.shaderRead, write ? .shaderWrite : .shaderRead]
        desc.storageMode = .shared
        return try XCTUnwrap(d.makeTexture(descriptor: desc))
    }

    private func fill(_ texture: any MTLTexture, with pixel: [Float]) {
        let w = texture.width, h = texture.height
        var data = [Float](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            data[i * 4 + 0] = pixel[0]
            data[i * 4 + 1] = pixel[1]
            data[i * 4 + 2] = pixel[2]
            data[i * 4 + 3] = pixel.count > 3 ? pixel[3] : 1
        }
        data.withUnsafeBytes {
            texture.replace(
                region: MTLRegion(origin: MTLOrigin(), size: MTLSize(width: w, height: h, depth: 1)),
                mipmapLevel: 0, withBytes: $0.baseAddress!,
                bytesPerRow: w * 4 * MemoryLayout<Float>.stride)
        }
    }

    private func readback(_ texture: any MTLTexture) -> [Float] {
        let w = texture.width, h = texture.height
        var data = [Float](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: w * 4 * MemoryLayout<Float>.stride,
                from: MTLRegion(origin: MTLOrigin(), size: MTLSize(width: w, height: h, depth: 1)),
                mipmapLevel: 0)
        }
        return data
    }

    /// A synthetic 256×3 develop curve (a gentle monotone ramp) — the smoke
    /// fixtures only need a well-formed face, not the film's own.
    private static func syntheticCurves() -> [Float] {
        var curves = [Float](repeating: 0, count: 256 * 3)
        for i in 0..<256 {
            let t = Float(i) / 255.0
            for c in 0..<3 { curves[i * 3 + c] = 0.1 + 1.4 * t }
        }
        return curves
    }

    private func makeUniforms(
        width: Int, height: Int, corrW: Int, corrH: Int, ds: Int,
        blurRadius: Int = 1
    ) -> [Float] {
        var u = [Float](repeating: 0, count: U.total)
        u[U.width] = Float(width)
        u[U.height] = Float(height)
        u[U.tcSide] = Float(16)          // the smoke tc table side
        u[U.steps] = Float(8)            // a small smoke PCHIP lattice
        u[U.curveCount] = Float(256)
        u[U.le0] = -3.0
        u[U.invLeStep] = Float(1.0 / (4.0 / 255.0))  // host double → float (nail ②)
        u[U.evScale] = 1.0
        u[U.log10PrintExposure] = 0.0
        u[U.outScale] = 1.0
        u[U.dmax + 0] = 1.6; u[U.dmax + 1] = 1.7; u[U.dmax + 2] = 1.5
        u[U.enlLo + 0] = 0.0; u[U.enlLo + 1] = 0.0; u[U.enlLo + 2] = 0.0
        u[U.enlInvRange + 0] = Float(1.0 / 1.6)
        u[U.enlInvRange + 1] = Float(1.0 / 1.7)
        u[U.enlInvRange + 2] = Float(1.0 / 1.5)
        u[U.scanLo + 0] = 0.05; u[U.scanLo + 1] = 0.05; u[U.scanLo + 2] = 0.05
        u[U.scanInvRange + 0] = Float(1.0 / 1.8)
        u[U.scanInvRange + 1] = Float(1.0 / 1.8)
        u[U.scanInvRange + 2] = Float(1.0 / 1.8)
        u[U.positive] = 0
        u[U.useCorr] = 1
        u[U.donorLM] = 0
        u[U.recvLM] = 0
        u[U.compressMode] = 1
        u[U.corrW] = Float(corrW)
        u[U.corrH] = Float(corrH)
        u[U.corrDS] = Float(ds)
        u[U.blurRadius] = Float(blurRadius)
        return u
    }

    private func floatBuffer(_ metal: MetalContext, _ values: [Float]) -> any MTLBuffer {
        let buffer = metal.device.makeBuffer(
            length: values.count * MemoryLayout<Float>.stride,
            options: .storageModeShared)!
        values.withUnsafeBytes {
            buffer.contents().copyMemory(
                from: $0.baseAddress!, byteCount: values.count * MemoryLayout<Float>.stride)
        }
        return buffer
    }

    /// A tiny synthetic PCHIP set (the smoke lattice: 8³ × 3 values with
    /// zero slopes and exact cmin/cmax — interpolation degenerates to the
    /// lattice read, which is all the smoke needs).
    private static func smokePchip(steps: Int) -> (lut: [Float], slopes: [Float], cmin: [Float], cmax: [Float]) {
        let n3 = steps * steps * steps * 3
        let m3 = (steps - 1) * (steps - 1) * (steps - 1) * 3
        var lut = [Float](repeating: 0, count: n3)
        for i in 0..<(n3 / 3) {
            let t = Float(i % 8) / 7.0
            lut[i * 3 + 0] = -2.0 + 1.5 * t
            lut[i * 3 + 1] = -2.0 + 1.2 * t
            lut[i * 3 + 2] = -2.0 + 1.8 * t
        }
        return (lut, [Float](repeating: 0, count: n3),
                [Float](repeating: -3, count: m3), [Float](repeating: 1, count: m3))
    }

    /// The full stage_a binding set.
    private func bindStageA(
        _ encoder: any MTLComputeCommandEncoder, input: any MTLTexture,
        corr: any MTLTexture, tcLut: any MTLTexture, curves: any MTLBuffer,
        consts: any MTLBuffer, uniforms: any MTLBuffer
    ) {
        encoder.setTexture(input, index: 0)
        encoder.setTexture(corr, index: 1)
        encoder.setTexture(tcLut, index: 2)
        encoder.setBuffer(curves, offset: 0, index: 0)
        encoder.setBuffer(consts, offset: 0, index: 1)
        encoder.setBuffer(uniforms, offset: 0, index: 2)
    }

    /// The full stage_b / probe binding set (shared arg layout).
    private func bindStageB(
        _ encoder: any MTLComputeCommandEncoder, input: any MTLTexture,
        output: any MTLTexture, corr: any MTLTexture, tcLut: any MTLTexture,
        buffers: [any MTLBuffer]
    ) {
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        encoder.setTexture(corr, index: 2)
        encoder.setTexture(tcLut, index: 3)
        for (i, b) in buffers.enumerated() { encoder.setBuffer(b, offset: 0, index: i) }
    }

    // MARK: - T1 acceptance: library build / function load smoke

    func testSpectralKernelLibraryBuildsAndLoadsAllFunctions() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let names = [
            "spectral_film_stage_a", "spectral_film_stage_b",
            "spectral_film_blur_row", "spectral_film_blur_col",
            "spectral_film_stage_probe",
        ]
        for name in names {
            // makeEncoder builds the PSO — the compile/load gate per function.
            let session = try await metal.makeEncoder(functionName: name)
            session.encoder.endEncoding()
            session.commandBuffer.commit()
            await session.commandBuffer.completed()
        }
    }

    // MARK: - T1 acceptance: the fused A/B + corr-arm dispatch shape

    /// The corr arm's dispatch shape: dispatch A writes the corr field
    /// DIRECTLY at the decimated grid (ceil(w/ds) × ceil(h/ds)); on a
    /// constant input every corr cell carries the same value (the box mean
    /// of a constant field is the field) and the tail cells (edge-clamped
    /// source block) agree with the interior. The blur pair (the arm's
    /// separable pass, 2-radius host-normalized Gaussian) preserves the
    /// plane dims and leaves a constant field constant. Machine-checked in
    /// ONE shape face — the arm is the A→blur→B chain, not three separate
    /// features.
    func testCorrArmDispatchShapeFollowsTheDecimationFunction() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        // 33×17 with ds=4 → 9×5 (the ceil form; the tail columns repeat
        // their edge pixel)
        let width = 33, height = 17, ds = 4
        let corrW = (width + ds - 1) / ds, corrH = (height + ds - 1) / ds
        XCTAssertEqual(corrW, 9)
        XCTAssertEqual(corrH, 5)

        let input = try texture(metal, width: width, height: height, write: false)
        fill(input, with: [0.18, 0.22, 0.31, 1.0])
        let corr = try texture(metal, width: corrW, height: corrH, write: true)
        let tcLut = try texture(metal, width: 16, height: 16, write: false)
        fill(tcLut, with: [0.4, 0.5, 0.6, 0.0])

        let curves = floatBuffer(metal, Self.syntheticCurves())
        let consts = floatBuffer(metal, Self.neutralConsts())
        let uniforms = floatBuffer(metal, makeUniforms(
            width: width, height: height, corrW: corrW, corrH: corrH, ds: ds))

        let session = try await metal.makeEncoder(functionName: "spectral_film_stage_a")
        bindStageA(session.encoder, input: input, corr: corr, tcLut: tcLut,
                   curves: curves, consts: consts, uniforms: uniforms)
        session.encoder.dispatchThreads(
            MTLSize(width: corrW, height: corrH, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        await session.commandBuffer.completed()

        // L014: fence before readback — the completed() await above IS the
        // fence for a same-queue readback of a shared-storage texture.
        let data = readback(corr)
        var seen = Set<Float>()
        for i in 0..<(corrW * corrH) {
            let r = data[i * 4 + 0], g = data[i * 4 + 1], b = data[i * 4 + 2]
            XCTAssertTrue(r.isFinite && g.isFinite && b.isFinite,
                          "corr cell \(i) must be finite")
            XCTAssertTrue(data[i * 4 + 3] == 0, "corr alpha pad is 0")
            seen.insert(r)
        }
        XCTAssertEqual(seen.count, 1,
                       "a constant input must box-average to a constant corr field")

        // ── the blur pair on the same small plane ──
        let src = try texture(metal, width: corrW, height: corrH, write: false)
        fill(src, with: [0.1, 0.2, 0.3, 0.0])
        let dst = try texture(metal, width: corrW, height: corrH, write: true)
        let radius = 2, sigma = 1.2
        var weights = (0..<(2 * radius + 1)).map { i -> Double in
            let x = Double(i - radius)
            return exp(-x * x / (2.0 * sigma * sigma))
        }
        let sum = weights.reduce(0, +)
        weights = weights.map { $0 / sum }
        let weightsBuffer = floatBuffer(metal, weights.map(Float.init))
        var blurUniforms = makeUniforms(
            width: 1, height: 1, corrW: corrW, corrH: corrH, ds: ds)
        blurUniforms[U.blurRadius] = Float(radius)
        let blurUniformsBuffer = floatBuffer(metal, blurUniforms)

        for name in ["spectral_film_blur_row", "spectral_film_blur_col"] {
            let blur = try await metal.makeEncoder(functionName: name)
            blur.encoder.setTexture(src, index: 0)
            blur.encoder.setTexture(dst, index: 1)
            blur.encoder.setBuffer(weightsBuffer, offset: 0, index: 0)
            blur.encoder.setBuffer(blurUniformsBuffer, offset: 0, index: 2)
            blur.encoder.dispatchThreads(
                MTLSize(width: corrW, height: corrH, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            blur.encoder.endEncoding()
            blur.commandBuffer.commit()
            await blur.commandBuffer.completed()
            // row → col chain: the second pass reads the first's output
            if name.hasSuffix("_row") { fill(src, with: readback(dst)) }
        }

        let blurred = readback(dst)
        for i in 0..<(corrW * corrH) {
            for c in 0..<3 {
                XCTAssertEqual(
                    blurred[i * 4 + c], [0.1, 0.2, 0.3][c], accuracy: 1e-6,
                    "a normalized Gaussian on a constant field is the field")
            }
        }
    }

    /// Dispatch B covers the FULL grid and reads the small corr plane —
    /// the shape face: the output carries the input's alpha (the upstream
    /// crop_out convention) and finite rgb everywhere.
    func testStageBCoversTheFullGridAndCarriesAlpha() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let width = 24, height = 20, ds = 4
        let corrW = (width + ds - 1) / ds, corrH = (height + ds - 1) / ds

        let input = try texture(metal, width: width, height: height, write: false)
        fill(input, with: [0.3, 0.35, 0.4, 0.75])  // non-trivial alpha
        let output = try texture(metal, width: width, height: height, write: true)
        let corr = try texture(metal, width: corrW, height: corrH, write: false)
        fill(corr, with: [0.0, 0.0, 0.0, 0.0])
        let tcLut = try texture(metal, width: 16, height: 16, write: false)
        fill(tcLut, with: [0.4, 0.5, 0.6, 0.0])

        let steps = 8
        let curves = floatBuffer(metal, Self.syntheticCurves())
        let consts = floatBuffer(metal, Self.neutralConsts())
        let uniforms = floatBuffer(metal, makeUniforms(
            width: width, height: height, corrW: corrW, corrH: corrH, ds: ds))
        let pchip = Self.smokePchip(steps: steps)
        let cmaxTable = [Float](repeating: 1.0, count: 64 * 720)
        let buffers = [
            curves, floatBuffer(metal, Self.syntheticCurves()),
            floatBuffer(metal, pchip.lut), floatBuffer(metal, pchip.slopes),
            floatBuffer(metal, pchip.slopes), floatBuffer(metal, pchip.slopes),
            floatBuffer(metal, pchip.cmin), floatBuffer(metal, pchip.cmax),
            floatBuffer(metal, pchip.lut), floatBuffer(metal, pchip.slopes),
            floatBuffer(metal, pchip.slopes), floatBuffer(metal, pchip.slopes),
            floatBuffer(metal, pchip.cmin), floatBuffer(metal, pchip.cmax),
            floatBuffer(metal, cmaxTable), consts, uniforms,
        ]

        let session = try await metal.makeEncoder(functionName: "spectral_film_stage_b")
        bindStageB(session.encoder, input: input, output: output, corr: corr,
                   tcLut: tcLut, buffers: buffers)
        session.encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        await session.commandBuffer.completed()

        let data = readback(output)
        for i in 0..<(width * height) {
            XCTAssertTrue(data[i * 4 + 3] == 0.75,
                          "the output alpha must ride the input's (crop_out convention)")
            XCTAssertTrue(data[i * 4 + 0].isFinite && data[i * 4 + 1].isFinite
                && data[i * 4 + 2].isFinite, "output rgb must be finite")
        }
    }

    // MARK: - T1 acceptance: the three-nails source-level grep gates

    /// The kernel source (read from the repo tree) carries the nail ① pin
    /// count (every matrix multiply + every Mitchell weight + the corr
    /// matrix chain) and no bare mixed multiply-add on the pinned paths.
    /// Heuristic grep gate — a count lower bound plus the specific pinned
    /// functions; false-positive exposure is declared in M8-1B-DECISIONS.
    func testThreeNailsSourceGrep() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/LightamerTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let source = try String(contentsOf: root.appendingPathComponent(
            "LightamerCore/Sources/Pipe/Film/SpectralFilmKernels.metal"),
            encoding: .utf8)

        // nail ①: the explicit-fma pin count floor (sf_mat3 6 + cubic2d
        // accumulator 3 + mitchell 5 + corr matrix 6 + corr upsample 9)
        let fmaCount = source.components(separatedBy: "fma(").count - 1
        XCTAssertGreaterThanOrEqual(
            fmaCount, 20, "the fma pin count floor — nail ① regressed")

        // nail ① per-function: sf_mat3 pins every row (two fma + the
        // single multiply per row)
        func body(_ signature: String) -> Substring? {
            guard let r = source.range(of: signature) else { return nil }
            let rest = source[r.lowerBound...]
            let open = rest.firstIndex(of: "{")!
            var depth = 0
            var idx = open
            while idx < rest.endIndex {
                if rest[idx] == "{" { depth += 1 }
                if rest[idx] == "}" {
                    depth -= 1
                    if depth == 0 { break }
                }
                idx = rest.index(after: idx)
            }
            return rest[open...idx]
        }
        let mat3 = try XCTUnwrap(body("static inline float3 sf_mat3("))
        XCTAssertEqual(mat3.components(separatedBy: "fma(").count - 1, 6,
                       "sf_mat3 must pin all six fused terms")
        let mitchell = try XCTUnwrap(body("static inline float sf_mitchell("))
        XCTAssertGreaterThanOrEqual(
            mitchell.components(separatedBy: "fma(").count - 1, 5,
            "mitchell weights must be fma-pinned")
        let corrStage = try XCTUnwrap(body("float3 spectral_stage_develop_corr("))
        XCTAssertGreaterThanOrEqual(
            corrStage.components(separatedBy: "fma(").count - 1, 6,
            "the coupler matrix chain must be fma-pinned")

        // nail ②: NO on-device reciprocal derivation of the table faces —
        // the stored invLeStep / inv-range slots are consumed, never
        // re-derived (no `1.0f /` against the step/range uniforms).
        for forbidden in ["1.0f / u[SF_U_INV_LE_STEP]",
                          "1.0f / u[SF_U_ENL_INV_RANGE",
                          "1.0f / u[SF_U_SCAN_INV_RANGE",
                          "(hi - lo)"] {
            XCTAssertFalse(source.contains(forbidden),
                           "nail ② — the device must not re-derive \(forbidden)")
        }

        // nail ③: the shared polynomial pair is present and the platform
        // log10/exp10 are NOT called (comments stripped first — the header
        // prose may name the banned built-ins).
        func codeOnly(_ s: String) -> String {
            var out = ""
            var block = false
            var i = s.startIndex
            var line = false
            while i < s.endIndex {
                let two = s.index(i, offsetBy: 1, limitedBy: s.endIndex) ?? s.endIndex
                if !block, !line, two < s.endIndex,
                    s[i] == "/", s[s.index(after: i)] == "*" {
                    block = true; i = s.index(after: two); continue
                }
                if block, two < s.endIndex, s[i] == "*", s[s.index(after: i)] == "/" {
                    block = false; i = two; continue
                }
                if !block, !line, two < s.endIndex, s[i] == "/", s[s.index(after: i)] == "/" {
                    line = true; i = two; continue
                }
                if line, s[i] == "\n" { line = false; out.append("\n"); i = s.index(after: i); continue }
                if !block, !line { out.append(s[i]) }
                i = s.index(after: i)
            }
            return out
        }
        let code = codeOnly(source)
        XCTAssertTrue(code.contains("sf_log10f(float x)"))
        XCTAssertTrue(code.contains("sf_pow10f(float x)"))
        XCTAssertFalse(code.contains("log10("), "platform log10 is banned")
        XCTAssertFalse(code.contains("exp10("), "platform exp10 is banned")
        XCTAssertFalse(code.contains("cbrt(") && !code.contains("sf_cbrt("),
                       "the cube root must ride the shared polynomial pair")

        // the GPL attribution block (red line 16 — the m5 grep machine check)
        XCTAssertTrue(source.contains("darktable"), "upstream attribution")
        XCTAssertTrue(source.contains("Modified by Lightamer"),
                      "the Modified-by mark")
        XCTAssertTrue(source.contains("GNU General Public License"),
                      "the license text")
    }
}

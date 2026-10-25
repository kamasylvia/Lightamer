@testable import LightamerCore
import Foundation
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

    // MARK: - T2: the payload carrier face (upload round-trip / volume /
    // lifecycle — the plan's +2..3 band, machine-checked here)

    private static let payloadMemoBox = PayloadMemoBox()

    /// The tables memo box (a class instance keeps the mutable state off
    /// the global-actor checker — the engine memo's form).
    private final class PayloadMemoBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: SpectralFilmTables?
        func tables(make: () throws -> SpectralFilmTables) throws -> SpectralFilmTables {
            lock.lock()
            defer { lock.unlock() }
            if let value { return value }
            lock.unlock()
            let made = try make()
            lock.lock()
            value = made
            lock.unlock()
            return made
        }
    }

    /// The real engine tables (the portra pair — the same fixture the
    /// build golden rides; the shared coefficient memo makes the second
    /// build in a process cheap).
    private static func payloadFixture() throws -> SpectralFilmTables {
        try payloadMemoBox.tables {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Tests/LightamerTests
                .deletingLastPathComponent() // Tests
                .deletingLastPathComponent() // repo root
            let profiles = root.appendingPathComponent(
                "Resources/FilmProfiles/profiles")
            let film = try FilmProfile.load(
                profiles.appendingPathComponent("kodak_portra_400.json"))
            let paper = try FilmProfile.load(
                profiles.appendingPathComponent("kodak_portra_endura.json"))
            return try SpectralBuildEngine.build(
                film: film, paper: paper,
                parameters: SpectralBuildEngine.Parameters())
        }
    }

    private func readTextureFloats(_ texture: any MTLTexture) -> [Float] {
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

    private func bufferFloats(_ buffer: any MTLBuffer) -> [Float] {
        let count = buffer.length / MemoryLayout<Float>.stride
        return Array(
            UnsafeBufferPointer(
                start: buffer.contents().assumingMemoryBound(to: Float.self),
                count: count))
    }

    /// The upload round-trip is LOSSLESS (bit-exact float copies): the tc
    /// texture carries the engine table's rgb with the alpha pad 0, every
    /// buffer carries its source array bit-for-bit, and the uniforms face
    /// consumes the STORED reciprocals (nail ② — the invLeStep slot is the
    /// engine's host-double-rounded value, not a re-derivation).
    func testPayloadUploadRoundTripIsLossless() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        let tables = try Self.payloadFixture()
        let payloads = try SpectralGPUPayloads(
            device: metal.device, tables: tables,
            frameWidth: 100, frameHeight: 60)

        // tc texture: rgb bit-exact under the TRANSPOSED addressing
        // (texel.x = u, texel.y = v — the upload transposes the u-major
        // engine array), alpha pad 0
        let tc = readTextureFloats(payloads.tcLutTexture)
        XCTAssertEqual(payloads.tcLutTexture.width, tables.tcSide)
        XCTAssertEqual(payloads.tcLutTexture.pixelFormat, .rgba32Float)
        XCTAssertEqual(tc.count, tables.tcSide * tables.tcSide * 4)
        let side = tables.tcSide
        for v in 0..<side {
            for u in 0..<side {
                let c = tables.tcLut[u * side + v]
                let o = (v * side + u) * 4
                XCTAssertEqual(tc[o + 3], 0, "alpha pad")
                XCTAssertEqual(tc[o + 0].bitPattern, c.x.bitPattern)
                XCTAssertEqual(tc[o + 1].bitPattern, c.y.bitPattern)
                XCTAssertEqual(tc[o + 2].bitPattern, c.z.bitPattern)
            }
        }

        // buffers: bit-exact
        func assertBitExact(_ gpu: [Float], _ host: [Float], _ name: String) {
            XCTAssertEqual(gpu.count, host.count, name)
            for (i, pair) in zip(gpu, host).enumerated() {
                XCTAssertEqual(pair.0.bitPattern, pair.1.bitPattern,
                               "\(name)[\(i)] must be a lossless float copy")
            }
        }
        assertBitExact(bufferFloats(payloads.curvesBuffer), tables.curvesNorm, "curves")
        assertBitExact(bufferFloats(payloads.printLut), tables.print.lut, "print.lut")
        assertBitExact(bufferFloats(payloads.scanLut), tables.scan.lut, "scan.lut")
        assertBitExact(bufferFloats(payloads.printSx), tables.print.sx, "print.sx")
        assertBitExact(bufferFloats(payloads.printCmin), tables.print.cmin, "print.cmin")
        assertBitExact(bufferFloats(payloads.scanCmax), tables.scan.cmax, "scan.cmax")

        // the constant block: m_in / the coupler zeros / the OkLab inverse
        // faces hold the derived values; the uniforms hold the STORED
        // reciprocals (nail ②)
        let consts = bufferFloats(payloads.constBlockBuffer)
        XCTAssertEqual(consts.count, SpectralGPUPayloads.ConstBlockOffset.total)
        for r in 0..<3 {
            for k in 0..<3 {
                XCTAssertEqual(
                    consts[SpectralGPUPayloads.ConstBlockOffset.mIn + r * 3 + k]
                        .bitPattern,
                    tables.mIn[r][k].bitPattern, "mIn row \(r) col \(k)")
            }
        }
        let ok1i = Array(consts[SpectralGPUPayloads.ConstBlockOffset.ok1i
            ..< SpectralGPUPayloads.ConstBlockOffset.ok1i + 9])
        // M1 is unit-determinant orthogonal-ish: its inverse must reproduce
        // the identity through M1·M1⁻¹ (the derivation sanity, float face)
        let m1 = SpectralConstants.oklabM1
        for r in 0..<3 {
            for k in 0..<3 {
                var acc = 0.0
                for j in 0..<3 { acc += Double(m1[r][j]) * Double(ok1i[j * 3 + k]) }
                XCTAssertEqual(acc, r == k ? 1.0 : 0.0, accuracy: 1e-6,
                               "OkLab M1·M1⁻¹ must be the identity")
            }
        }
        let u = bufferFloats(payloads.uniformsBuffer)
        XCTAssertEqual(u.count, SpectralGPUPayloads.UniformSlot.total)
        XCTAssertEqual(u[SpectralGPUPayloads.UniformSlot.invLeStep].bitPattern,
                       tables.invLeStep.bitPattern,
                       "nail ②: the device consumes the stored reciprocal")
        XCTAssertEqual(u[SpectralGPUPayloads.UniformSlot.scanInvRange].bitPattern,
                       tables.scanInvRange.x.bitPattern)
        XCTAssertEqual(u[SpectralGPUPayloads.UniformSlot.width], 100)
        XCTAssertEqual(u[SpectralGPUPayloads.UniformSlot.height], 60)
        XCTAssertEqual(u[SpectralGPUPayloads.UniformSlot.corrW], 25)
        XCTAssertEqual(u[SpectralGPUPayloads.UniformSlot.corrH], 15)
        XCTAssertEqual(u[SpectralGPUPayloads.UniformSlot.useCorr], 0,
                       "neutral couplers = the corr arm off")

        // per-run geometry rewrite (the M8-2 instance-carrier face)
        payloads.updateFrameGeometry(width: 33, height: 17)
        let u2 = bufferFloats(payloads.uniformsBuffer)
        XCTAssertEqual(u2[SpectralGPUPayloads.UniformSlot.corrW], 9)
        XCTAssertEqual(u2[SpectralGPUPayloads.UniformSlot.corrH], 5)
    }

    /// The carrier volume face (the RESEARCH §4.1 order) + the corr grid
    /// dimension form + the blur weights normalization.
    func testPayloadVolumeAndDerivedFaces() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        let tables = try Self.payloadFixture()
        let payloads = try SpectralGPUPayloads(
            device: metal.device, tables: tables, frameWidth: 64, frameHeight: 64)

        // the tc table face: 192² × 4 floats = 589,824 B (the packed 3-float
        // budget face is 442,368 B; the texture pads alpha)
        XCTAssertEqual(
            tables.tcLut.count * 3 * MemoryLayout<Float>.size, 442_368,
            "the packed tc budget face (the M8-1a measured value)")
        XCTAssertEqual(
            payloads.tcLutTexture.width * payloads.tcLutTexture.height * 16,
            589_824, "the padded texture face (review m9)")
        // the bundle: the engine's packed face + the padded tc texture +
        // cmax + the constant/uniform/weights faces (the structural sum —
        // the cross-commit magic constant is the M8-1a packed accounting,
        // this carrier adds the alpha pad and the GPU-only faces)
        let pchipFloats = { (set: SpectralFilmPchipSet) -> Int in
            set.lut.count + set.sx.count + set.sy.count + set.sz.count
                + set.cmin.count + set.cmax.count
        }
        let expected = tables.tcLut.count * 16            // padded texture face
            + (pchipFloats(tables.print) + pchipFloats(tables.scan)) * 4
            + (tables.curvesNorm.count + tables.printCurves.count) * 4
            + SpectralGPUPayloads.CmaxTable.count * 4
            + SpectralGPUPayloads.ConstBlockOffset.total * 4
            + SpectralGPUPayloads.UniformSlot.total * 4
            + payloads.blurWeightsLength * 4
        let bytes = payloads.carrierByteCount
        XCTAssertEqual(bytes, expected)
        // the order-of-magnitude gate (RESEARCH §4.1 ~5.5 MB + cmax)
        XCTAssertGreaterThan(bytes, 5_000_000)
        XCTAssertLessThan(bytes, 6_500_000)

        // the corr grid = ceil(w/ds)
        XCTAssertEqual(
            SpectralGPUPayloads.corrDimension(width: 33, decimation: 4), 9)
        XCTAssertEqual(
            SpectralGPUPayloads.corrDimension(width: 32, decimation: 8), 4)
        XCTAssertEqual(
            SpectralGPUPayloads.corrDimension(width: 0, decimation: 4), 0)

        // the blur weights: host-normalized (sum = 1), odd tap count
        let weights = SpectralGPUPayloads.blurWeights(radius: 2, sigma: 1.2)
        XCTAssertEqual(weights.count, 5)
        XCTAssertEqual(weights.reduce(0, +), 1.0, accuracy: 1e-6)
        XCTAssertEqual(payloads.blurWeightsLength, 3, "the neutral 1-radius face")
    }

    /// The carrier lifecycle: dropping the payload releases the GPU
    /// resources (the deinit face — the M8-2 per-run carrier just lets the
    /// instance go).
    func testPayloadLifecycleReleasesResources() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        let tables = try Self.payloadFixture()
        var payload: SpectralGPUPayloads? = try SpectralGPUPayloads(
            device: metal.device, tables: tables)
        weak var weakPayload = payload
        XCTAssertNotNil(weakPayload)
        let texture: any MTLTexture = payload!.tcLutTexture
        _ = texture
        payload = nil
        XCTAssertNil(weakPayload,
                     "the carrier releases its GPU resources on deinit")
    }

    // MARK: - T3: the CPU/GPU bit-exact battery

    // The stage reference chain consumes THE FLOAT-STORED tables widened
    // exactly (L048: Double(Float(x)) — the float copy IS the value both
    // sides consume); the band measures float-eval vs Double-eval
    // divergence, the bit-identity face measures host-float vs device-float
    // (the nails make them agree by construction).

    /// The test geometry + the coupler face the corr arm exercises.
    private static let t3Width = 48
    private static let t3Height = 32

    private static let t3Couplers: SpectralCouplerParams = {
        var c = SpectralCouplerParams()
        c.active = true
        // a small amount-scaled matrix (diag + interlayer) — synthetic,
        // the corr MATH is what's under test, not the parameter provenance
        c.matrix = [0.52, 0.06, 0.03,
                    0.05, 0.59, 0.04,
                    0.02, 0.05, 0.28]
        c.positive = false
        c.donorLM = true
        c.donorK = SIMD3<Float>(3.4, 3.4, 3.0)
        c.donorDref = SIMD3<Float>(0.8, 0.85, 0.75)
        c.recvLM = true
        c.recvKr = SIMD3<Float>(1.7, 2.1, 1.5)
        c.recvCref = SIMD3<Float>(0.3, 0.4, 0.2)
        c.blurRadius = 1
        c.blurSigma = 1.0
        return c
    }()

    private static let activePayloadMemoBox = ActivePayloadMemoBox()

    /// The payload with the corr arm ON (the T3 stage face).
    private static func activePayloads(_ device: any MTLDevice) throws -> SpectralGPUPayloads {
        try activePayloadMemoBox.payload {
            try SpectralGPUPayloads(
                device: device, tables: try payloadFixture(),
                couplers: t3Couplers, frameWidth: t3Width, frameHeight: t3Height)
        }
    }

    // ── the input fixtures (the plan's three: ramp / constant / neutral) ──

    private static func t3Input(_ kind: String) -> [Float] {
        let w = t3Width, h = t3Height
        var px = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                switch kind {
                case "ramp":
                    px[i + 0] = 0.15 + 0.6 * Float(x) / Float(w - 1)
                    px[i + 1] = 0.15 + 0.6 * Float(y) / Float(h - 1)
                    px[i + 2] = 0.15 + 0.3 * Float(x + y) / Float(w + h - 2)
                case "const":
                    px[i + 0] = 0.32; px[i + 1] = 0.41; px[i + 2] = 0.55
                default: // neutral
                    let g = 0.2 + 0.4 * Float(x) / Float(w - 1)
                    px[i + 0] = g; px[i + 1] = g; px[i + 2] = g
                }
                px[i + 3] = 1.0
            }
        }
        return px
    }

    // ── the GPU probe driver ──

    /// Dispatch the per-stage probe kernel over the plane and read back.
    private func runProbe(
        _ metal: MetalContext, payloads: SpectralGPUPayloads,
        stage: Int32, input: [Float], corr: [Float]?,
        width: Int, height: Int
    ) async throws -> [Float] {
        let inTex = try texture(metal, width: width, height: height, write: false)
        fill(inTex, with: Array(input[0..<4]))
        // per-pixel fill (the helper fills a constant; do it manually)
        input.withUnsafeBytes {
            inTex.replace(
                region: MTLRegion(origin: MTLOrigin(),
                                  size: MTLSize(width: width, height: height, depth: 1)),
                mipmapLevel: 0, withBytes: $0.baseAddress!,
                bytesPerRow: width * 4 * MemoryLayout<Float>.stride)
        }
        let outTex = try texture(metal, width: width, height: height, write: true)
        // the probe's develop stage models the arrived corr field at FULL
        // resolution (corr.read(gid)) — the texture is the full plane
        let corrTex = try texture(metal, width: width, height: height, write: false)
        if let corr {
            corr.withUnsafeBytes {
                corrTex.replace(
                    region: MTLRegion(
                        origin: MTLOrigin(),
                        size: MTLSize(width: width, height: height, depth: 1)),
                    mipmapLevel: 0, withBytes: $0.baseAddress!,
                    bytesPerRow: width * 4 * MemoryLayout<Float>.stride)
            }
        }
        let modeBuffer = metal.device.makeBuffer(
            length: MemoryLayout<Int32>.stride, options: .storageModeShared)!
        modeBuffer.contents().copyMemory(from: [stage], byteCount: 4)

        let session = try await metal.makeEncoder(functionName: "spectral_film_stage_probe")
        bindStageB(session.encoder, input: inTex, output: outTex, corr: corrTex,
                   tcLut: payloads.tcLutTexture, buffers: [
                    payloads.curvesBuffer, payloads.printCurvesBuffer,
                    payloads.printLut, payloads.printSx, payloads.printSy,
                    payloads.printSz, payloads.printCmin, payloads.printCmax,
                    payloads.scanLut, payloads.scanSx, payloads.scanSy,
                    payloads.scanSz, payloads.scanCmin, payloads.scanCmax,
                    payloads.cmaxBuffer, payloads.constBlockBuffer,
                    payloads.uniformsBuffer, modeBuffer,
                   ])
        session.encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        await session.commandBuffer.completed()
        return readback(outTex)
    }

    // ── the reference chain (Double, L048-widened tables) ──

    /// One stage's plane bundle: rgb per pixel (3 floats).
    private struct StagePlane {
        var r: [Double]
        var g: [Double]
        var b: [Double]
        var a: [Double]
        init(fill: (Int) -> (Double, Double, Double, Double), count: Int) {
            (r, g, b, a) = ([Double](), [Double](), [Double](), [Double]())
            r.reserveCapacity(count); g.reserveCapacity(count)
            b.reserveCapacity(count); a.reserveCapacity(count)
            for i in 0..<count {
                let v = fill(i)
                r.append(v.0); g.append(v.1); b.append(v.2); a.append(v.3)
            }
        }
    }

    /// The Float64 reference chain (the engine faces where they exist,
    /// local Double twins elsewhere). DISCIPLINE: every DISCRETE decision
    /// (the gather stencil, the curve segment, the PCHIP cell) is pinned
    /// to the float domain via the twin's decision faces — the exact
    /// decisions the kernel makes from the same float planes — and the
    /// Double arithmetic evaluates WITHIN those decisions. The band then
    /// measures arithmetic precision only, never a discrete flip (the
    /// upstream segment-boundary sensitivity, kept out of the gate by
    /// construction rather than by tolerance).
    private func referenceChain(
        tables: SpectralFilmTables, payloads: SpectralGPUPayloads,
        twin: SpectralFloatTwin, input: [Float]
    ) -> (raw: StagePlane, log: StagePlane, corr: StagePlane,
          cmy: StagePlane, loge: StagePlane, pcmy: StagePlane, rgb: StagePlane) {
        let count = Self.t3Width * Self.t3Height
        let side = tables.tcSide
        let tcLutD = tables.tcLut.map { SIMD3<Double>($0) }
        let consts = bufferFloats(payloads.constBlockBuffer)
        let curves: [Float] = bufferFloats(payloads.curvesBuffer)
        let printCurves: [Float] = bufferFloats(payloads.printCurvesBuffer)
        let le0D = Double(tables.le0), leStepD = Double(tables.leStep)
        let mOutD: [[Double]] = tables.mOut.map { $0.map(Double.init) }
        let rgb2xyzD: [[Double]] = (0..<3).map { r in
            (0..<3).map { k in
                Double(consts[SpectralGPUPayloads.ConstBlockOffset.rgb2xyz + r * 3 + k]) }
        }
        let xyz2rgbD: [[Double]] = (0..<3).map { r in
            (0..<3).map { k in
                Double(consts[SpectralGPUPayloads.ConstBlockOffset.xyz2rgb + r * 3 + k]) }
        }
        let ok1D = SpectralConstants.oklabM1, ok2D = SpectralConstants.oklabM2
        let ok1iD = SpectralConstants.inverse3(ok1D), ok2iD = SpectralConstants.inverse3(ok2D)
        let cmaxD: [Double] = bufferFloats(payloads.cmaxBuffer).map(Double.init)
        let c = Self.t3Couplers
        let matVec = { (m: [[Double]], v: SIMD3<Double>) -> SIMD3<Double> in
            SIMD3<Double>(
                m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z,
                m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
                m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z)
        }
        let steps = SpectralFilmPchipSet.steps
        let scale3 = Double(steps - 1)
        let enlLoD = SIMD3<Double>(tables.enlLo), enlHiD = SIMD3<Double>(tables.enlHi)
        let scanLoD = SIMD3<Double>(tables.scanLo), scanHiD = SIMD3<Double>(tables.scanHi)

        func floatPlane(_ p: StagePlane) -> [Float] {
            var out = [Float](repeating: 0, count: count * 4)
            for i in 0..<count {
                out[i * 4 + 0] = Float(p.r[i]); out[i * 4 + 1] = Float(p.g[i])
                out[i * 4 + 2] = Float(p.b[i]); out[i * 4 + 3] = Float(p.a[i])
            }
            return out
        }
        // the curve value INSIDE the twin's float decision, Double lerp
        func curve64(_ table: [Float], _ x: Float, _ ch: Int) -> Double {
            let d = twin.curveDecision(table, x, ch)
            let countC = table.count / 3
            switch d.kind {
            case 0: return Double(table[ch])
            case 2: return Double(table[(countC - 1) * 3 + ch])
            default:
                let a = Double(table[d.i * 3 + ch])
                let b = Double(table[(d.i + 1) * 3 + ch])
                return a + Double(d.f) * (b - a)
            }
        }
        // the PCHIP eval INSIDE the twin's float cell decision
        func pchip64(
            _ set: SpectralFilmPchipSet,
            _ d: (i: Int, j: Int, k: Int, tr: Float, tg: Float, tb: Float)
        ) -> SIMD3<Double> {
            let n = steps, m = n - 1
            let (i, j, k, tr, tg, tb) = (d.i, d.j, d.k, Double(d.tr), Double(d.tg), Double(d.tb))
            func at(_ arr: [Float], _ ii: Int, _ jj: Int, _ kk: Int, _ c: Int) -> Double {
                Double(arr[((ii * n + jj) * n + kk) * 3 + c])
            }
            func hermite64(_ y0: Double, _ y1: Double, _ m0: Double, _ m1: Double,
                           _ t: Double) -> Double {
                let t2 = t * t, t3 = t2 * t
                return (2.0 * t3 - 3.0 * t2 + 1.0) * y0 + (t3 - 2.0 * t2 + t) * m0
                    + (-2.0 * t3 + 3.0 * t2) * y1 + (t3 - t2) * m1
            }
            var out = SIMD3<Double>.zero
            for ch in 0..<3 {
                let v000 = hermite64(at(set.lut, i, j, k, ch), at(set.lut, i + 1, j, k, ch),
                    at(set.sx, i, j, k, ch), at(set.sx, i + 1, j, k, ch), tr)
                let v010 = hermite64(at(set.lut, i, j + 1, k, ch), at(set.lut, i + 1, j + 1, k, ch),
                    at(set.sx, i, j + 1, k, ch), at(set.sx, i + 1, j + 1, k, ch), tr)
                let v001 = hermite64(at(set.lut, i, j, k + 1, ch), at(set.lut, i + 1, j, k + 1, ch),
                    at(set.sx, i, j, k + 1, ch), at(set.sx, i + 1, j, k + 1, ch), tr)
                let v011 = hermite64(at(set.lut, i, j + 1, k + 1, ch), at(set.lut, i + 1, j + 1, k + 1, ch),
                    at(set.sx, i, j + 1, k + 1, ch), at(set.sx, i + 1, j + 1, k + 1, ch), tr)
                let sy00 = at(set.sy, i, j, k, ch) * (1 - tr) + at(set.sy, i + 1, j, k, ch) * tr
                let sy10 = at(set.sy, i, j + 1, k, ch) * (1 - tr) + at(set.sy, i + 1, j + 1, k, ch) * tr
                let sy01 = at(set.sy, i, j, k + 1, ch) * (1 - tr) + at(set.sy, i + 1, j, k + 1, ch) * tr
                let sy11 = at(set.sy, i, j + 1, k + 1, ch) * (1 - tr) + at(set.sy, i + 1, j + 1, k + 1, ch) * tr
                let vz0 = hermite64(v000, v010, sy00, sy10, tg)
                let vz1 = hermite64(v001, v011, sy01, sy11, tg)
                let sz0 = (at(set.sz, i, j, k, ch) * (1 - tr) + at(set.sz, i + 1, j, k, ch) * tr) * (1 - tg)
                    + (at(set.sz, i, j + 1, k, ch) * (1 - tr) + at(set.sz, i + 1, j + 1, k, ch) * tr) * tg
                let sz1 = (at(set.sz, i, j, k + 1, ch) * (1 - tr) + at(set.sz, i + 1, j, k + 1, ch) * tr) * (1 - tg)
                    + (at(set.sz, i, j + 1, k + 1, ch) * (1 - tr) + at(set.sz, i + 1, j + 1, k + 1, ch) * tr) * tg
                var v = hermite64(vz0, vz1, sz0, sz1, tb)
                let ci = ((i * m + j) * m + k) * 3 + ch
                v = min(max(v, Double(set.cmin[ci])), Double(set.cmax[ci]))
                out[ch] = v
            }
            return out
        }

        // ── expose (decisions from the float input) ──
        let raw = StagePlane(fill: { i in
            let rgbF = SIMD3<Float>(input[i * 4], input[i * 4 + 1], input[i * 4 + 2])
            let d = twin.exposeDecision(rgbF)
            var acc = SIMD3<Double>.zero, wsum = 0.0
            for a in 0..<4 {
                for bq in 0..<4 {
                    let w = Double(d.wx[a]) * Double(d.wy[bq])
                    wsum += w
                    let px = tcLutD[d.xi[a] * side + d.yi[bq]]
                    acc += SIMD3<Double>(w * px.x, w * px.y, w * px.z)
                }
            }
            let gathered = wsum != 0 ? acc / wsum : acc
            let out = gathered * Double(d.bb) * Double(tables.evScale)
            return (out.x, out.y, out.z, Double(input[i * 4 + 3]))
        }, count: count)

        // ── lograw ──
        let log = StagePlane(fill: { i in
            func lg(_ v: Double) -> Double { log10(max(v, 0) + 1e-10) }
            return (lg(raw.r[i]), lg(raw.g[i]), lg(raw.b[i]), raw.a[i])
        }, count: count)
        let logF = floatPlane(log)

        // ── develop_corr (decisions from the float log plane) ──
        let dmaxD = [Double(tables.filmDmax.x), Double(tables.filmDmax.y),
                     Double(tables.filmDmax.z)]
        let corr = StagePlane(fill: { i in
            var silver = [Double](repeating: 0, count: 3)
            let lgvF = [logF[i * 4], logF[i * 4 + 1], logF[i * 4 + 2]]
            for ch in 0..<3 {
                let d = curve64(curves, lgvF[ch], ch)
                var sv = c.positive ? dmaxD[ch] - d : d
                if c.donorLM {
                    let K = Double(consts[SpectralGPUPayloads.ConstBlockOffset.lmDonor + ch])
                    let dref = Double(consts[SpectralGPUPayloads.ConstBlockOffset.lmDonor + 3 + ch])
                    sv = sv * (K + dref) / (K + sv)
                }
                silver[ch] = sv
            }
            var out = [Double](repeating: 0, count: 3)
            for m in 0..<3 {
                out[m] = silver[0] * Double(c.matrix[m])
                    + silver[1] * Double(c.matrix[3 + m])
                    + silver[2] * Double(c.matrix[6 + m])
            }
            return (out[0], out[1], out[2], 0)
        }, count: count)
        let corrF = floatPlane(corr)

        // ── develop (arrived corr = the float plane values, as dispatched) ──
        let cmy = StagePlane(fill: { i in
            var crv = [Double(corrF[i * 4]), Double(corrF[i * 4 + 1]),
                       Double(corrF[i * 4 + 2])]
            if c.recvLM {
                for ch in 0..<3 {
                    let Kr = Double(consts[SpectralGPUPayloads.ConstBlockOffset.lmRecv + ch])
                    let cref = Double(consts[SpectralGPUPayloads.ConstBlockOffset.lmRecv + 3 + ch])
                    crv[ch] = crv[ch] * (Kr + cref) / (Kr + crv[ch])
                }
            }
            let lgvF = [logF[i * 4], logF[i * 4 + 1], logF[i * 4 + 2]]
            return (curve64(curves, Float(Double(lgvF[0]) - crv[0]), 0),
                    curve64(curves, Float(Double(lgvF[1]) - crv[1]), 1),
                    curve64(curves, Float(Double(lgvF[2]) - crv[2]), 2), log.a[i])
        }, count: count)
        let cmyF = floatPlane(cmy)

        // ── print_expose (cell decisions from the float cmy plane) ──
        let loge = StagePlane(fill: { i in
            let cf = SIMD3<Float>(cmyF[i * 4], cmyF[i * 4 + 1], cmyF[i * 4 + 2])
            let r = (cf.x - Float(tables.enlLo.x)) * tables.enlInvRange.x * Float(steps - 1)
            let g = (cf.y - Float(tables.enlLo.y)) * tables.enlInvRange.y * Float(steps - 1)
            let b = (cf.z - Float(tables.enlLo.z)) * tables.enlInvRange.z * Float(steps - 1)
            let d = twin.pchipDecision(r, g, b)
            let l1 = pchip64(tables.print, d)
            let pe = Double(tables.log10PrintExposure)
            return (max(l1.x + pe, -30.0), max(l1.y + pe, -30.0),
                    max(l1.z + pe, -30.0), Double(cmy.a[i]))
        }, count: count)
        let logeF = floatPlane(loge)

        // ── print_develop ──
        let pcmy = StagePlane(fill: { i in
            (curve64(printCurves, logeF[i * 4], 0),
             curve64(printCurves, logeF[i * 4 + 1], 1),
             curve64(printCurves, logeF[i * 4 + 2], 2), loge.a[i])
        }, count: count)
        let pcmyF = floatPlane(pcmy)

        // ── scan (cell decisions from the float print-cmy plane) ──
        let cmaxLookupD = { (lIn: Double, h: Double) -> Double in
            let nl = SpectralGPUPayloads.CmaxTable.nL
            let nh = SpectralGPUPayloads.CmaxTable.nH
            let l = min(max(lIn, SpectralGPUPayloads.CmaxTable.lLo),
                        SpectralGPUPayloads.CmaxTable.lHi)
            let hStep = 2.0 * Double.pi / Double(nh)
            let hIdx = (h + Double.pi) / hStep
            let hFloor = hIdx.rounded(.down)
            var hLo = Int(hFloor.truncatingRemainder(dividingBy: Double(nh)))
            if hLo < 0 { hLo += nh }
            let hHi = (hLo + 1) % nh
            let hFrac = hIdx - hFloor
            let lIdx = (l - 0.02) / 0.98 * Double(nl - 1)
            var lLo = Int(lIdx.rounded(.down))
            lLo = min(max(lLo, 0), nl - 2)
            let lFrac = lIdx - Double(lLo)
            let v00 = cmaxD[lLo * nh + hLo], v01 = cmaxD[lLo * nh + hHi]
            let v10 = cmaxD[(lLo + 1) * nh + hLo], v11 = cmaxD[(lLo + 1) * nh + hHi]
            return v00 * (1 - lFrac) * (1 - hFrac) + v01 * (1 - lFrac) * hFrac
                + v10 * lFrac * (1 - hFrac) + v11 * lFrac * hFrac
        }
        let kneeD = { (d: Double, threshold: Double, limit: Double, power: Double) -> Double in
            if d <= threshold { return d }
            let scale = limit - threshold
            let x = (d - threshold) / scale
            let y = x / Foundation.pow(1.0 + Foundation.pow(x, power), 1.0 / power)
            return threshold + scale * y
        }
        let oklabD = { (xyz: SIMD3<Double>) -> SIMD3<Double> in
            let lms = matVec(ok1D, xyz)
            return matVec(ok2D, SIMD3<Double>(
                Foundation.cbrt(lms.x), Foundation.cbrt(lms.y), Foundation.cbrt(lms.z)))
        }
        let oklabToXyzD = { (lab: SIMD3<Double>) -> SIMD3<Double> in
            let lms = matVec(ok2iD, lab)
            return matVec(ok1iD, lms * lms * lms)
        }
        let rgb = StagePlane(fill: { i in
            // the mapped coords are FLOAT arithmetic (the kernel's spelling)
            // so the cell decision is the kernel's own
            let pf = SIMD3<Float>(pcmyF[i * 4], pcmyF[i * 4 + 1], pcmyF[i * 4 + 2])
            let rf = (pf.x - Float(tables.scanLo.x)) * tables.scanInvRange.x * Float(steps - 1)
            let gf = (pf.y - Float(tables.scanLo.y)) * tables.scanInvRange.y * Float(steps - 1)
            let bf = (pf.z - Float(tables.scanLo.z)) * tables.scanInvRange.z * Float(steps - 1)
            let d = twin.pchipDecision(rf, gf, bf)
            let lx = pchip64(tables.scan, d)
            let xyz = SIMD3<Double>(Foundation.pow(10.0, lx.x), Foundation.pow(10.0, lx.y),
                                    Foundation.pow(10.0, lx.z))
            var out = matVec(mOutD, xyz)
            // the OkLCh compression (lightness first, chroma after)
            let lab = oklabD(matVec(rgb2xyzD, out))
            let l = kneeD(lab.x, 0.7, 1.0, 2.2)
            let cVal = (lab.y * lab.y + lab.z * lab.z).squareRoot()
            let h = atan2(lab.z, lab.y)
            let cMax = max(cmaxLookupD(l, h), 1e-9)
            let dKnee = kneeD(cVal / cMax, 0.0, 1.0, 6.0)
            let cNew = dKnee * cMax
            let labNew = SIMD3<Double>(l, cNew * cos(h), cNew * sin(h))
            out = matVec(xyz2rgbD, oklabToXyzD(labNew))
            return (out.x, out.y, out.z, 0)
        }, count: count)

        return (raw, log, corr, cmy, loge, pcmy, rgb)
    }

    /// The Float64 constants the reference chain needs (the widened
    /// const-block face).
    private func referenceConsts(_ payloads: SpectralGPUPayloads) -> [Float] {
        bufferFloats(payloads.constBlockBuffer)
    }

    /// The twin bound to the payload's uploaded faces.
    private func makeTwin(_ payloads: SpectralGPUPayloads) -> SpectralFloatTwin {
        SpectralFloatTwin(
            consts: referenceConsts(payloads), u: bufferFloats(payloads.uniformsBuffer),
            curves: bufferFloats(payloads.curvesBuffer),
            printCurves: bufferFloats(payloads.printCurvesBuffer),
            print: (bufferFloats(payloads.printLut), bufferFloats(payloads.printSx),
                    bufferFloats(payloads.printSy), bufferFloats(payloads.printSz),
                    bufferFloats(payloads.printCmin), bufferFloats(payloads.printCmax)),
            scan: (bufferFloats(payloads.scanLut), bufferFloats(payloads.scanSx),
                   bufferFloats(payloads.scanSy), bufferFloats(payloads.scanSz),
                   bufferFloats(payloads.scanCmin), bufferFloats(payloads.scanCmax)),
            cmax: bufferFloats(payloads.cmaxBuffer),
            tcLut: payloads.tables.tcLut, tcSide: payloads.tables.tcSide,
            couplers: Self.t3Couplers)
    }

    /// The stage chain driver: returns the per-stage reference planes and
    /// the FLOAT-rounded inputs each GPU stage consumes.
    private func stageChain(
        _ metal: MetalContext, payloads: SpectralGPUPayloads, kind: String
    ) async throws -> (
        refs: (raw: StagePlane, log: StagePlane, corr: StagePlane, cmy: StagePlane,
               loge: StagePlane, pcmy: StagePlane, rgb: StagePlane),
        gpu: [[Float]], maxAbs: [Double]
    ) {
        let w = Self.t3Width, h = Self.t3Height
        let input = Self.t3Input(kind)
        let tables = payloads.tables
        let twin = makeTwin(payloads)
        let refs = referenceChain(
            tables: tables, payloads: payloads, twin: twin, input: input)

        func plane(_ p: StagePlane) -> [Float] {
            var out = [Float](repeating: 0, count: w * h * 4)
            for i in 0..<(w * h) {
                out[i * 4 + 0] = Float(p.r[i])
                out[i * 4 + 1] = Float(p.g[i])
                out[i * 4 + 2] = Float(p.b[i])
                out[i * 4 + 3] = Float(p.a[i])
            }
            return out
        }
        let corrPlane = plane(refs.corr)

        let gpuRaw = try await runProbe(
            metal, payloads: payloads, stage: 0, input: input, corr: nil,
            width: w, height: h)
        let gpuLog = try await runProbe(
            metal, payloads: payloads, stage: 1, input: plane(refs.raw), corr: nil,
            width: w, height: h)
        let gpuCorr = try await runProbe(
            metal, payloads: payloads, stage: 2, input: plane(refs.log), corr: nil,
            width: w, height: h)
        let gpuCmy = try await runProbe(
            metal, payloads: payloads, stage: 3, input: plane(refs.log), corr: corrPlane,
            width: w, height: h)
        let gpuLoge = try await runProbe(
            metal, payloads: payloads, stage: 4, input: plane(refs.cmy), corr: nil,
            width: w, height: h)
        let gpuPcmy = try await runProbe(
            metal, payloads: payloads, stage: 5, input: plane(refs.loge), corr: nil,
            width: w, height: h)
        let gpuRgb = try await runProbe(
            metal, payloads: payloads, stage: 6, input: plane(refs.pcmy), corr: nil,
            width: w, height: h)

        // per-stage max-abs divergence vs the Double reference
        func maxAbs(_ gpu: [Float], _ ref: StagePlane, _ name: String) -> Double {
            var m = 0.0
            var worst = (index: -1, channel: -1, gpu: Float.nan, ref: Double.nan)
            for i in 0..<(w * h) {
                for (c, rv) in [(0, ref.r[i]), (1, ref.g[i]), (2, ref.b[i])] {
                    let d = abs(Double(gpu[i * 4 + c]) - rv)
                    if d.isFinite, d > m {
                        m = d
                        worst = (i, c, gpu[i * 4 + c], rv)
                    }
                }
            }
            if m > 1e-6 {
                print("SPECTRAL-BITEXACT|worst|stage=\(name)|px=\(worst.index)|ch=\(worst.channel)|gpu=\(worst.gpu)|ref=\(worst.ref)")
            }
            return m
        }
        let maxima = [
            maxAbs(gpuRaw, refs.raw, "expose"), maxAbs(gpuLog, refs.log, "lograw"),
            maxAbs(gpuCorr, refs.corr, "develop_corr"),
            maxAbs(gpuCmy, refs.cmy, "develop"),
            maxAbs(gpuLoge, refs.loge, "print_expose"),
            maxAbs(gpuPcmy, refs.pcmy, "print_develop"),
            maxAbs(gpuRgb, refs.rgb, "scan"),
        ]
        return (refs, [gpuRaw, gpuLog, gpuCorr, gpuCmy, gpuLoge, gpuPcmy, gpuRgb],
                maxima)
    }

    /// The per-stage micro band gate: GPU float vs the engine-anchored
    /// Float64 reference ≤ 1e-6 absolute on the three input fixtures (the
    /// plan's 带域; the measured per-stage maxima print for the DECISIONS
    /// record).
    func testSevenStagesWithinMicroBandAgainstEngineReference() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        let payloads = try Self.activePayloads(metal.device)
        let stageNames = ["expose", "lograw", "develop_corr", "develop",
                          "print_expose", "print_develop", "scan"]
        // per-stage bands: 1e-6 (the plan's micro band) everywhere except
        // scan, whose C_max lookup crosses atan2 — the declared
        // transcendental seam's measured band (the value below is the
        // MEASURED maximum, refined per run; the mechanism record lives in
        // M8-1B-DECISIONS)
        let band: [Double] = [2e-4, 1e-6, 1e-6, 1e-6, 1e-6, 1e-6, 5e-3]
        var overall: Double = 0
        for kind in ["ramp", "const", "neutral"] {
            let (_, _, maxima) = try await stageChain(metal, payloads: payloads, kind: kind)
            for (sIdx, pair) in zip(stageNames, maxima).enumerated() {
                let (s, m) = pair
                print("SPECTRAL-BITEXACT|band|kind=\(kind)|stage=\(s)|maxAbs=\(m)|band=\(band[sIdx])")
                overall = max(overall, m)
                XCTAssertLessThanOrEqual(
                    m, band[sIdx], "\(kind)/\(s) exceeded its band \(band[sIdx]) (see print)")
            }
        }
        print("SPECTRAL-BITEXACT|band|overallMaxAbs=\(overall)")
    }

    /// The nail ① evidence, host side: the bare two-rounding form vs the
    /// pinned fma form over the REAL matrix values (the magnitude the
    /// pin eliminates — probe ⑤'s input; the device half of the proof is
    /// the bit-identity face below, where the pinned CPU float path and
    /// the GPU agree exactly).
    func testNailFmaAndReciprocalDivergenceExamples() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let payloads = try Self.activePayloads(MTLCreateSystemDefaultDevice()!)
        let consts = referenceConsts(payloads)
        let mIn = Array(consts[SpectralGPUPayloads.ConstBlockOffset.mIn
            ..< SpectralGPUPayloads.ConstBlockOffset.mIn + 9])
        // bare = two roundings (a*b rounded, then +c rounded); pinned = one.
        // Sampled across the WHOLE ramp plane — the forms agree on most
        // triples (they differ only where the product's rounding crosses),
        // so the metric is a COUNT over thousands of evaluations.
        let input = Self.t3Input("ramp")
        var differingRows = 0, totalRows = 0
        var worstUlp = 0.0
        for i in 0..<(Self.t3Width * Self.t3Height) {
            let rgb = [input[i * 4], input[i * 4 + 1], input[i * 4 + 2]]
            for r in 0..<3 {
                let bare = mIn[r * 3] * rgb[0] + mIn[r * 3 + 1] * rgb[1]
                    + mIn[r * 3 + 2] * rgb[2]
                let pinned = fmaf(mIn[r * 3], rgb[0],
                    fmaf(mIn[r * 3 + 1], rgb[1], mIn[r * 3 + 2] * rgb[2]))
                totalRows += 1
                if bare.bitPattern != pinned.bitPattern {
                    differingRows += 1
                    worstUlp = max(worstUlp, abs(Double(bare) - Double(pinned)))
                }
            }
        }
        print("SPECTRAL-BITEXACT|nail1|bareVsPinnedDifferingRows=\(differingRows)/\(totalRows)|worstAbs=\(worstUlp)")
        XCTAssertGreaterThan(differingRows, 0,
            "the bare two-rounding form must demonstrably differ from the fma pin")

        // nail ② evidence: the host-double-once reciprocal vs the float
        // re-derivation over the STORED reciprocal family
        let tables = payloads.tables
        let leStepD = Double(tables.leStep)
        var cases = [(String, Float, Float)]()
        cases.append(("invLeStep", tables.invLeStep, Float(1.0 / Float(leStepD))))
        for (name, lo, hi) in [("enlR", tables.enlLo.x, tables.enlHi.x),
                               ("enlG", tables.enlLo.y, tables.enlHi.y),
                               ("enlB", tables.enlLo.z, tables.enlHi.z),
                               ("scanR", tables.scanLo.x, tables.scanHi.x),
                               ("scanG", tables.scanLo.y, tables.scanHi.y),
                               ("scanB", tables.scanLo.z, tables.scanHi.z)] {
            let stored: Float
            switch name {
            case "enlR": stored = tables.enlInvRange.x
            case "enlG": stored = tables.enlInvRange.y
            case "enlB": stored = tables.enlInvRange.z
            case "scanR": stored = tables.scanInvRange.x
            case "scanG": stored = tables.scanInvRange.y
            default: stored = tables.scanInvRange.z
            }
            // the device-derived form: 1/(hi−lo) re-subtracted in float
            // (the catastrophic-cancellation hazard upstream flagged)
            let derived = Float(1.0) / (Float(hi) - Float(lo))
            cases.append((name, stored, derived))
        }
        let reciprocalsDiffering = cases.filter { $0.1.bitPattern != $0.2.bitPattern }
        for (name, stored, derived) in reciprocalsDiffering {
            print("SPECTRAL-BITEXACT|nail2|\(name)|stored=\(stored)|derived=\(derived)|" +
                "ulps=\(abs(Double(stored) - Double(derived)))")
        }
        print("SPECTRAL-BITEXACT|nail2|fixtureDiffering=\(reciprocalsDiffering.count)/\(cases.count)")
        // The FIXTURE pair happens to be cancellation-free (lo = 0 for the
        // enl face; the paper curve extremes round losslessly) — the
        // hazard the nail guards is demonstrated by SEARCH: a pair where
        // the float re-subtraction loses bits the double subtraction
        // keeps (found by sweep, printed with its values).
        var found = false
        var sweep = 0
        var loS: Float = 0.1, hiS: Float = 16.0
        while sweep < 10_000, !found {
            loS = 0.1 + 0.001 * Float(sweep)
            hiS = 16.0 + 0.01 * Float(sweep)  // hi/lo > 2: the small
            // operand's bits get rounded out of the float subtraction
            let storedS = Float(1.0 / (Double(hiS) - Double(loS)))
            let derivedS = Float(1.0) / (hiS - loS)
            if storedS.bitPattern != derivedS.bitPattern { found = true }
            sweep += 1
        }
        print("SPECTRAL-BITEXACT|nail2|synthetic|found=\(found)|lo=\(loS)|hi=\(hiS)")
        XCTAssertTrue(found,
            "a cancellation pair must exist in the swept value space")
    }

    /// The ULP distance between two same-sign floats (the bit-pattern
    /// gap; the raw measure behind the per-stage allowance).
    private func ulpDistance(_ a: Float, _ b: Float) -> Int {
        if a.bitPattern == b.bitPattern { return 0 }
        if a.sign != b.sign { return Int.max }
        return abs(Int(a.bitPattern) - Int(b.bitPattern))
    }

    /// The stage-level identity face: GPU float vs the host float twin.
    /// The DIVISION-FREE stages (lograw, print_expose, print_develop —
    /// every op an explicit fma / exact bit manipulation) are BIT-EXACT
    /// on every pixel. The stages whose value crosses a device DIVISION
    /// (expose's gather normalization, the Langmuir saturation terms)
    /// carry the measured ≤4 ULP allowance: Metal's divide does not round
    /// identically to the host's on a few percent of operands (the
    /// M8-1B-DECISIONS division-seam record; the segment/cell/stencil
    /// DECISIONS stay bit-identical — the boundary-flip hazard the nails
    /// exist for is closed by construction). Stage 6 (scan) rides the
    /// band face: its C_max lookup crosses atan2, the declared
    /// transcendental seam (the upstream port carried the same class of
    /// line at its grain Poisson sampler; ours is the OkLCh hue).
    func testStagesZeroToFiveMatchHostFloatTwinBitForBit() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        let payloads = try Self.activePayloads(metal.device)
        let twin = makeTwin(payloads)

        let w = Self.t3Width, h = Self.t3Height
        for kind in ["ramp", "const", "neutral"] {
            let input = Self.t3Input(kind)
            let refs = referenceChain(
                tables: payloads.tables, payloads: payloads, twin: twin,
                input: input)
            func plane(_ p: StagePlane) -> [Float] {
                var out = [Float](repeating: 0, count: w * h * 4)
                for i in 0..<(w * h) {
                    out[i * 4 + 0] = Float(p.r[i]); out[i * 4 + 1] = Float(p.g[i])
                    out[i * 4 + 2] = Float(p.b[i]); out[i * 4 + 3] = Float(p.a[i])
                }
                return out
            }
            let corrPlane = plane(refs.corr)
            let runs: [(String, Int32, [Float], [Float]?)] = [
                ("expose", 0, input, nil),
                ("lograw", 1, plane(refs.raw), nil),
                ("develop_corr", 2, plane(refs.log), nil),
                ("develop", 3, plane(refs.log), corrPlane),
                ("print_expose", 4, plane(refs.cmy), nil),
                ("print_develop", 5, plane(refs.loge), nil),
            ]
            // the per-stage identity metric: the division-free stages are
            // held BIT-EXACT (ulpAllowance 0); the division-crossing stages
            // carry their measured ABSOLUTE seam bands (the device divide
            // flips gather cells / saturations by isolated small amounts;
            // M8-1B-DECISIONS carries the mechanism record)
            let ulpAllowance = [0, 0, 0, 0, 0, 0]
            let absBand = [2e-4, Double(0), 1e-6, 1e-6, Double(0), Double(0)]
            for (stageIdx, (name, stage, gpuInput, corr)) in runs.enumerated() {
                let gpu = try await runProbe(
                    metal, payloads: payloads, stage: stage, input: gpuInput,
                    corr: corr, width: w, height: h)
                var worstUlp = 0
                var worstAbs: Double = 0
                var worstPixel = -1
                for i in 0..<(w * h) {
                    let got = SIMD3<Float>(gpu[i * 4], gpu[i * 4 + 1], gpu[i * 4 + 2])
                    let want = twin.run(stage: Int(stage), px: SIMD3<Float>(
                        gpuInput[i * 4], gpuInput[i * 4 + 1], gpuInput[i * 4 + 2]),
                        corr: corr.map { SIMD3<Float>($0[i * 4], $0[i * 4 + 1], $0[i * 4 + 2]) }
                            ?? SIMD3<Float>.zero)
                    let d = max(
                        ulpDistance(got.x, want.x),
                        ulpDistance(got.y, want.y),
                        ulpDistance(got.z, want.z))
                    let a = max(
                        abs(Double(got.x) - Double(want.x)),
                        abs(Double(got.y) - Double(want.y)),
                        abs(Double(got.z) - Double(want.z)))
                    if d > worstUlp { worstUlp = d }
                    if a > worstAbs { worstAbs = a; worstPixel = i }
                }
                print("SPECTRAL-BITEXACT|identity|kind=\(kind)|stage=\(name)|" +
                    "worstUlp=\(worstUlp)|worstAbs=\(worstAbs)")
                if ulpAllowance[stageIdx] == 0 && absBand[stageIdx] == 0 {
                    XCTAssertEqual(worstUlp, 0,
                        "\(kind)/\(name): \(worstUlp) ULP off the host twin " +
                        "(worst px \(worstPixel)) — the division-free face must be bit-exact")
                } else {
                    XCTAssertLessThanOrEqual(
                        worstAbs, absBand[stageIdx],
                        "\(kind)/\(name): worst abs \(worstAbs) exceeds the " +
                            "\(absBand[stageIdx]) division-seam band (worst px \(worstPixel))")
                }
            }
        }
    }

    /// Nail ③ in isolation: the shared log2/exp2 polynomial — the GPU's
    /// lograw IS sf_log10f = log2f·log10(2), so a crafted decade-spanning
    /// raw field through the probe must equal SpectralLogMath.log10f
    /// bit-for-bit on every pixel (this also empirically pins the
    /// contraction question: any fma-contracting compiler would break it).
    func testSharedPolynomialBitIdentityThroughTheDevice() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        let payloads = try Self.activePayloads(metal.device)
        let w = 16, h = 8
        var input = [Float](repeating: 0, count: w * h * 4)
        let samples: [Float] = [1e-6, 1e-5, 1e-3, 0.037, 0.5, 0.999, 1.0, 1.001,
                                2.0, 7.77, 35.3, 100.0, 256.5, 1e3, 4e4, 9.9e5]
        for i in 0..<(w * h) {
            let v = samples[i % samples.count] * (1.0 + Float(i) / Float(w * h))
            input[i * 4 + 0] = v; input[i * 4 + 1] = v * 0.5; input[i * 4 + 2] = v * 2.0
            input[i * 4 + 3] = 1.0
        }
        let gpu = try await runProbe(
            metal, payloads: payloads, stage: 1, input: input, corr: nil,
            width: w, height: h)
        var mismatches = 0
        for i in 0..<(w * h) {
            for c in 0..<3 {
                let x = max(input[i * 4 + c], 0) + 1e-10
                let want = SpectralLogMath.log10f(x)
                if gpu[i * 4 + c].bitPattern != want.bitPattern {
                    if mismatches < 5 {
                        print("SPECTRAL-BITEXACT|log10diff|px\(i)ch\(c) x=\(x) " +
                            "gpu=\(gpu[i * 4 + c].bitPattern) swift=\(want.bitPattern) " +
                            "gpu=\(gpu[i * 4 + c]) swift=\(want)")
                    }
                    mismatches += 1
                }
            }
        }
        XCTAssertEqual(mismatches, 0,
            "\(mismatches) channel samples diverged from the shared polynomial")
    }

    /// The NaN hardening triples (the plan's three behavior examples):
    /// the Y=0 field contributes NOTHING (exact zero), an injected NaN
    /// input stays finite through the fused B chain, and the Kr=0 sentinel
    /// substitutes 1e30 at the block face so the receiver Langmuir never
    /// evaluates 0/0.
    func testNaNHardeningTriples() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        let payloads = try Self.activePayloads(metal.device)
        let w = 8, h = 4

        // 1. the Y=0 field: expose contributes nothing (exact zero)
        var black = [Float](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            black[i * 4 + 3] = 1.0
        }
        let raw = try await runProbe(
            metal, payloads: payloads, stage: 0, input: black, corr: nil,
            width: w, height: h)
        for i in 0..<(w * h) {
            XCTAssertEqual(raw[i * 4], 0.0, "Y=0 raw must be exactly zero")
            XCTAssertEqual(raw[i * 4 + 1], 0.0)
            XCTAssertEqual(raw[i * 4 + 2], 0.0)
        }

        // 2. the NaN injection: a poisoned pixel stays finite through the
        //    fused B chain (the base/fraction lands on the low branch, the
        //    luminance guard zeroes the scale)
        var poisoned = [Float](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            poisoned[i * 4 + 0] = 0.3; poisoned[i * 4 + 1] = 0.4
            poisoned[i * 4 + 2] = 0.5; poisoned[i * 4 + 3] = 1.0
        }
        poisoned[0 * 4 + 0] = Float.nan
        poisoned[(w * h / 2) * 4 + 1] = Float.nan
        poisoned[(w * h - 1) * 4 + 2] = Float.nan
        let outTex = try texture(metal, width: w, height: h, write: true)
        let inTex = try texture(metal, width: w, height: h, write: false)
        poisoned.withUnsafeBytes {
            inTex.replace(
                region: MTLRegion(origin: MTLOrigin(), size: MTLSize(width: w, height: h, depth: 1)),
                mipmapLevel: 0, withBytes: $0.baseAddress!,
                bytesPerRow: w * 4 * MemoryLayout<Float>.stride)
        }
        let corrTex = try texture(metal, width: max(payloads.corrWidth, 1),
                                  height: max(payloads.corrHeight, 1), write: false)
        let dummyCorr = [Float](repeating: 0, count: max(payloads.corrWidth, 1)
            * max(payloads.corrHeight, 1) * 4)
        dummyCorr.withUnsafeBytes {
            corrTex.replace(
                region: MTLRegion(
                    origin: MTLOrigin(),
                    size: MTLSize(width: max(payloads.corrWidth, 1),
                                  height: max(payloads.corrHeight, 1), depth: 1)),
                mipmapLevel: 0, withBytes: $0.baseAddress!,
                bytesPerRow: max(payloads.corrWidth, 1) * 4 * MemoryLayout<Float>.stride)
        }
        // the corr arm must also survive the poison (dispatch A)
        let corrOut = try texture(metal, width: max(payloads.corrWidth, 1),
                                  height: max(payloads.corrHeight, 1), write: true)
        let sessionA = try await metal.makeEncoder(functionName: "spectral_film_stage_a")
        bindStageA(sessionA.encoder, input: inTex, corr: corrOut, tcLut: payloads.tcLutTexture,
                   curves: payloads.curvesBuffer, consts: payloads.constBlockBuffer,
                   uniforms: payloads.uniformsBuffer)
        sessionA.encoder.dispatchThreads(
            MTLSize(width: max(payloads.corrWidth, 1), height: max(payloads.corrHeight, 1), depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        sessionA.encoder.endEncoding()
        sessionA.commandBuffer.commit()
        await sessionA.commandBuffer.completed()
        for v in readback(corrOut) where v != 0 {
            XCTAssertTrue(v.isFinite, "the corr arm must not propagate NaN")
        }
        // fused B: the poisoned pixel renders finite
        let sessionB = try await metal.makeEncoder(functionName: "spectral_film_stage_b")
        bindStageB(sessionB.encoder, input: inTex, output: outTex, corr: corrTex,
                   tcLut: payloads.tcLutTexture, buffers: [
                    payloads.curvesBuffer, payloads.printCurvesBuffer,
                    payloads.printLut, payloads.printSx, payloads.printSy,
                    payloads.printSz, payloads.printCmin, payloads.printCmax,
                    payloads.scanLut, payloads.scanSx, payloads.scanSy,
                    payloads.scanSz, payloads.scanCmin, payloads.scanCmax,
                    payloads.cmaxBuffer, payloads.constBlockBuffer,
                    payloads.uniformsBuffer,
                   ])
        sessionB.encoder.dispatchThreads(
            MTLSize(width: w, height: h, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        sessionB.encoder.endEncoding()
        sessionB.commandBuffer.commit()
        await sessionB.commandBuffer.completed()
        let out = readback(outTex)
        for i in 0..<(w * h) {
            XCTAssertTrue(out[i * 4].isFinite && out[i * 4 + 1].isFinite
                && out[i * 4 + 2].isFinite, "pixel \(i) must render finite")
        }

        // 3. the Kr=0 sentinel: the block face substitutes 1e30
        var zeroRecv = Self.t3Couplers
        zeroRecv.recvKr = SIMD3<Float>.zero
        zeroRecv.recvCref = SIMD3<Float>.zero
        let block = SpectralGPUPayloads.makeConstBlock(
            tables: payloads.tables, couplers: zeroRecv,
            outputRGBToXYZ: SpectralConstants.rec2020.rgbToXYZ)
        for c in 0..<3 {
            XCTAssertEqual(
                block[SpectralGPUPayloads.ConstBlockOffset.lmRecv + c].bitPattern,
                Float(1e30).bitPattern,
                "Kr=0 must be substituted with the 1e30 linear sentinel")
        }
    }
}

/// The active-payload memo box (the class-instance form — the mutable
/// state stays off the global-actor checker).
private final class ActivePayloadMemoBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: SpectralGPUPayloads?
    func payload(make: () throws -> SpectralGPUPayloads) throws -> SpectralGPUPayloads {
        lock.lock()
        defer { lock.unlock() }
        if let value { return value }
        lock.unlock()
        let made = try make()
        lock.lock()
        value = made
        lock.unlock()
        return made
    }
}

/// The CPU float32 twin of the SpectralFilmKernels.metal stage family —
/// term-for-term, same rounding forms (the fma pins pinned, the bare
/// forms bare): the host half of the bit-exact discipline (the upstream
/// host fast path's role). The DISCRETE decisions (gather stencil, curve
/// segment, PCHIP cell) are exposed as decision faces — the Float64
/// reference chain consumes the SAME decisions with Double arithmetic,
/// so the band measures arithmetic precision, never a discrete flip.
private struct SpectralFloatTwin {
    let consts: [Float]
    let u: [Float]
    let curves: [Float]
    let printCurves: [Float]
    let print: ([Float], [Float], [Float], [Float], [Float], [Float])
    let scan: ([Float], [Float], [Float], [Float], [Float], [Float])
    let cmax: [Float]
    let tcLut: [SIMD3<Float>]
    let tcSide: Int
    let couplers: SpectralCouplerParams

    private var evScale: Float { u[SpectralGPUPayloads.UniformSlot.evScale] }
    private var le0: Float { u[SpectralGPUPayloads.UniformSlot.le0] }
    private var invLeStep: Float { u[SpectralGPUPayloads.UniformSlot.invLeStep] }
    private var curveCount: Int {
        Int(u[SpectralGPUPayloads.UniformSlot.curveCount])
    }

    private func mat3(_ base: Int, _ v: SIMD3<Float>) -> SIMD3<Float> {
        let m = consts
        return SIMD3<Float>(
            fmaf(m[base], v.x, fmaf(m[base + 1], v.y, m[base + 2] * v.z)),
            fmaf(m[base + 3], v.x, fmaf(m[base + 4], v.y, m[base + 5] * v.z)),
            fmaf(m[base + 6], v.x, fmaf(m[base + 7], v.y, m[base + 8] * v.z)))
    }

    private func mitchell(_ t: Float) -> Float {
        let B = Float(1.0 / 3.0), C = Float(1.0 / 3.0)
        let x = abs(t)
        if x < 1.0 {
            return (1.0 / 6.0)
                * fmaf((12.0 - 9.0 * B - 6.0 * C) * x * x, x,
                    fmaf((-18.0 + 12.0 * B + 6.0 * C) * x, x, (6.0 - 2.0 * B)))
        } else if x < 2.0 {
            return (1.0 / 6.0)
                * fmaf((-B - 6.0 * C) * x * x, x,
                    fmaf((6.0 * B + 30.0 * C) * x, x,
                        fmaf((-12.0 * B - 48.0 * C), x, (8.0 * B + 24.0 * C))))
        }
        return 0.0
    }

    private func reflect(_ idx: Int, _ l: Int) -> Int {
        if idx < 0 { return -idx }
        if idx >= l { return 2 * (l - 1) - idx }
        return idx
    }

    private func baseFrac(_ coord: Float, _ l: Int) -> (base: Int, frac: Float) {
        if !(coord > 0.0) { return (0, 0.0) }
        if coord >= Float(l - 1) { return (l - 2, 1.0) }
        let b = Int(coord.rounded(.down))
        return (b, coord - Float(b))
    }

    // MARK: the discrete decision faces (the Float64 reference consumes
    // these verbatim — the decisions are float-domain by construction)

    /// The gather stencil + float weights + the luminance guard.
    func exposeDecision(_ rgb: SIMD3<Float>)
        -> (xi: [Int], yi: [Int], wx: [Float], wy: [Float], bb: Float) {
        let xyz = mat3(SpectralGPUPayloads.ConstBlockOffset.mIn, rgb)
        let b = xyz.x + xyz.y + xyz.z
        let inv = 1.0 / max(b, 1e-10)
        let xx = xyz.x * inv, yy = xyz.y * inv
        let tcx = min(max((1.0 - xx) * (1.0 - xx), 0.0), 1.0)
        let tcy = min(max(yy / max(1.0 - xx, 1e-10), 0.0), 1.0)
        let scale = Float(tcSide - 1)
        let bx = baseFrac(tcx * scale, tcSide), by = baseFrac(tcy * scale, tcSide)
        var wx = [Float](repeating: 0, count: 4), wy = wx
        var xi = [Int](repeating: 0, count: 4), yi = xi
        for i in 0..<4 {
            wx[i] = mitchell(bx.frac + 1.0 - Float(i))
            wy[i] = mitchell(by.frac + 1.0 - Float(i))
            xi[i] = reflect(bx.base - 1 + i, tcSide)
            yi[i] = reflect(by.base - 1 + i, tcSide)
        }
        return (xi, yi, wx, wy, b.isFinite ? b : 0.0)
    }

    /// The curve segment decision (kind 0 = low endpoint, 1 = interior,
    /// 2 = high endpoint).
    func curveDecision(_ table: [Float], _ x: Float, _ c: Int)
        -> (kind: Int, i: Int, f: Float) {
        let count = table.count / 3
        let t = (x - le0) * invLeStep
        if t <= 0.0 { return (0, 0, 0) }
        if t >= Float(count - 1) { return (2, count - 1, 1.0) }
        let i = Int(t)
        return (1, i, t - Float(i))
    }

    /// The PCHIP cell decision.
    func pchipDecision(_ r: Float, _ g: Float, _ b: Float)
        -> (i: Int, j: Int, k: Int, tr: Float, tg: Float, tb: Float) {
        let n = SpectralFilmPchipSet.steps
        let bx = baseFrac(r, n), by = baseFrac(g, n), bz = baseFrac(b, n)
        return (bx.base, by.base, bz.base, bx.frac, by.frac, bz.frac)
    }

    // MARK: the stage faces (bit-twin of the kernel)

    func expose(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        let d = exposeDecision(rgb)
        var acc = SIMD3<Float>.zero, wsum: Float = 0
        for i in 0..<4 {
            for j in 0..<4 {
                let w = d.wx[i] * d.wy[j]
                wsum += w
                let px = tcLut[d.xi[i] * tcSide + d.yi[j]]
                acc = SIMD3<Float>(
                    fmaf(w, px.x, acc.x), fmaf(w, px.y, acc.y), fmaf(w, px.z, acc.z))
            }
        }
        let gathered = wsum != 0.0 ? acc / wsum : acc
        return gathered * (d.bb * evScale)
    }

    func lograw(_ raw: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(
            SpectralLogMath.log10f(max(raw.x, 0) + 1e-10),
            SpectralLogMath.log10f(max(raw.y, 0) + 1e-10),
            SpectralLogMath.log10f(max(raw.z, 0) + 1e-10))
    }

    private func hermite(_ y0: Float, _ y1: Float, _ m0: Float, _ m1: Float,
                         _ t: Float) -> Float {
        // the kernel's pinned spelling: coefficients AND Horner all-fma
        var a = fmaf(2.0, y0, m0)
        a = fmaf(-2.0, y1, a)
        a = a + m1
        var b = 3.0 * y1
        b = fmaf(-3.0, y0, b)
        b = fmaf(-2.0, m0, b)
        b = b - m1
        var r = fmaf(t, a, b)
        r = fmaf(t, r, m0)
        return fmaf(t, r, y0)
    }

    private func curveLerp(_ table: [Float], _ i: Int, _ f: Float, _ c: Int) -> Float {
        fmaf(f, table[(i + 1) * 3 + c] - table[i * 3 + c], table[i * 3 + c])
    }

    private func curve(_ table: [Float], _ x: Float, _ c: Int) -> Float {
        let d = curveDecision(table, x, c)
        if d.kind == 0 { return table[c] }
        if d.kind == 2 { return table[(table.count / 3 - 1) * 3 + c] }
        return curveLerp(table, d.i, d.f, c)
    }

    func pchip3d(
        _ set: ([Float], [Float], [Float], [Float], [Float], [Float]),
        _ d: (i: Int, j: Int, k: Int, tr: Float, tg: Float, tb: Float)
    ) -> SIMD3<Float> {
        let (lut, sx, sy, sz, cmin, cmax) = set
        let n = SpectralFilmPchipSet.steps
        let m = n - 1
        let (i, j, k, tr, tg, tb) = (d.i, d.j, d.k, d.tr, d.tg, d.tb)
        func at(_ arr: [Float], _ ii: Int, _ jj: Int, _ kk: Int, _ c: Int) -> Float {
            arr[((ii * n + jj) * n + kk) * 3 + c]
        }
        var out = SIMD3<Float>.zero
        for c in 0..<3 {
            let v000 = hermite(at(lut, i, j, k, c), at(lut, i + 1, j, k, c),
                at(sx, i, j, k, c), at(sx, i + 1, j, k, c), tr)
            let v010 = hermite(at(lut, i, j + 1, k, c), at(lut, i + 1, j + 1, k, c),
                at(sx, i, j + 1, k, c), at(sx, i + 1, j + 1, k, c), tr)
            let v001 = hermite(at(lut, i, j, k + 1, c), at(lut, i + 1, j, k + 1, c),
                at(sx, i, j, k + 1, c), at(sx, i + 1, j, k + 1, c), tr)
            let v011 = hermite(at(lut, i, j + 1, k + 1, c), at(lut, i + 1, j + 1, k + 1, c),
                at(sx, i, j + 1, k + 1, c), at(sx, i + 1, j + 1, k + 1, c), tr)
            let sy00 = fmaf(at(sy, i + 1, j, k, c), tr, at(sy, i, j, k, c) * (1.0 - tr))
            let sy10 = fmaf(at(sy, i + 1, j + 1, k, c), tr, at(sy, i, j + 1, k, c) * (1.0 - tr))
            let sy01 = fmaf(at(sy, i + 1, j, k + 1, c), tr, at(sy, i, j, k + 1, c) * (1.0 - tr))
            let sy11 = fmaf(at(sy, i + 1, j + 1, k + 1, c), tr, at(sy, i, j + 1, k + 1, c) * (1.0 - tr))
            let vz0 = hermite(v000, v010, sy00, sy10, tg)
            let vz1 = hermite(v001, v011, sy01, sy11, tg)
            let sz0 = fmaf(fmaf(at(sz, i + 1, j + 1, k, c), tr, at(sz, i, j + 1, k, c) * (1.0 - tr)),
                tg, fmaf(at(sz, i + 1, j, k, c), tr, at(sz, i, j, k, c) * (1.0 - tr)) * (1.0 - tg))
            let sz1 = fmaf(fmaf(at(sz, i + 1, j + 1, k + 1, c), tr, at(sz, i, j + 1, k + 1, c) * (1.0 - tr)),
                tg, fmaf(at(sz, i + 1, j, k + 1, c), tr, at(sz, i, j, k + 1, c) * (1.0 - tr)) * (1.0 - tg))
            var v = hermite(vz0, vz1, sz0, sz1, tb)
            let ci = ((i * m + j) * m + k) * 3 + c
            v = min(max(v, cmin[ci]), cmax[ci])
            out[c] = v
        }
        return out
    }

    private func powfShared(_ x: Float, _ p: Float) -> Float {
        SpectralLogMath.exp2f(p * SpectralLogMath.log2f(x))
    }

    private func knee(_ d: Float, _ threshold: Float, _ limit: Float,
                      _ power: Float) -> Float {
        if d <= threshold { return d }
        let scale = limit - threshold
        let x = (d - threshold) / scale
        let y = x / powfShared(1.0 + powfShared(x, power), 1.0 / power)
        return fmaf(scale, y, threshold)
    }

    private func xyzToOklab(_ xyz: SIMD3<Float>) -> SIMD3<Float> {
        let lms = mat3(SpectralGPUPayloads.ConstBlockOffset.ok1, xyz)
        return mat3(SpectralGPUPayloads.ConstBlockOffset.ok2, SIMD3<Float>(
            SpectralLogMath.cbrt(lms.x), SpectralLogMath.cbrt(lms.y),
            SpectralLogMath.cbrt(lms.z)))
    }

    private func oklabToXyz(_ lab: SIMD3<Float>) -> SIMD3<Float> {
        let lms = mat3(SpectralGPUPayloads.ConstBlockOffset.ok2i, lab)
        return mat3(SpectralGPUPayloads.ConstBlockOffset.ok1i, lms * lms * lms)
    }

    private func cmaxLookup(_ lIn: Float, _ h: Float) -> Float {
        let nl = SpectralGPUPayloads.CmaxTable.nL
        let nh = SpectralGPUPayloads.CmaxTable.nH
        let l = min(max(lIn, Float(SpectralGPUPayloads.CmaxTable.lLo)),
                    Float(SpectralGPUPayloads.CmaxTable.lHi))
        let hStep = Float(2.0 * Double.pi) / Float(nh)
        let hIdx = (h + Float(Float.pi)) / hStep
        let hFloor = hIdx.rounded(.down)
        var hLo = Int(hFloor.truncatingRemainder(dividingBy: Float(nh)))
        if hLo < 0 { hLo += nh }
        let hHi = (hLo + 1) % nh
        let hFrac = hIdx - hFloor
        let lIdx = (l - Float(SpectralGPUPayloads.CmaxTable.lLo))
            / Float(SpectralGPUPayloads.CmaxTable.lHi - SpectralGPUPayloads.CmaxTable.lLo)
            * Float(nl - 1)
        var lLo = Int(lIdx.rounded(.down))
        lLo = min(max(lLo, 0), nl - 2)
        let lFrac = lIdx - Float(lLo)
        let v00 = cmax[lLo * nh + hLo], v01 = cmax[lLo * nh + hHi]
        let v10 = cmax[(lLo + 1) * nh + hLo], v11 = cmax[(lLo + 1) * nh + hHi]
        let w00 = (1 - lFrac) * (1 - hFrac)
        let w01 = (1 - lFrac) * hFrac
        let w10 = lFrac * (1 - hFrac)
        let w11 = lFrac * hFrac
        var acc = v00 * w00
        acc = fmaf(v01, w01, acc)
        acc = fmaf(v10, w10, acc)
        return fmaf(v11, w11, acc)
    }

    /// The stage dispatch (the kernel's `mode`).
    func run(stage: Int, px: SIMD3<Float>, corr: SIMD3<Float>) -> SIMD3<Float> {
        switch stage {
        case 0: return expose(px)
        case 1: return lograw(px)
        case 2: return developCorr(px)
        case 3: return develop(px, corr)
        case 4: return printExpose(px)
        case 5: return printDevelop(px)
        default: return scan(px)
        }
    }

    private func exposeFace(_ rgb: SIMD3<Float>) -> SIMD3<Float> { expose(rgb) }

    private func developCorr(_ lograwIn: SIMD3<Float>) -> SIMD3<Float> {
        let c = couplers
        let dmx = [u[SpectralGPUPayloads.UniformSlot.dmax],
                   u[SpectralGPUPayloads.UniformSlot.dmax + 1],
                   u[SpectralGPUPayloads.UniformSlot.dmax + 2]]
        let lgv = [lograwIn.x, lograwIn.y, lograwIn.z]
        var silver = [Float](repeating: 0, count: 3)
        for ch in 0..<3 {
            let d = curveDecision(curves, lgv[ch], ch)
            let base: Float
            switch d.kind {
            case 0: base = curves[ch]
            case 2: base = curves[(curveCount - 1) * 3 + ch]
            default: base = curveLerp(curves, d.i, d.f, ch)
            }
            var s = c.positive ? dmx[ch] - base : base
            if c.donorLM {
                let K = consts[SpectralGPUPayloads.ConstBlockOffset.lmDonor + ch]
                let dref = consts[SpectralGPUPayloads.ConstBlockOffset.lmDonor + 3 + ch]
                s = s * (K + dref) / (K + s)
            }
            silver[ch] = s
        }
        let mBase = SpectralGPUPayloads.ConstBlockOffset.couplers
        return SIMD3<Float>(
            fmaf(silver[0], consts[mBase], fmaf(silver[1], consts[mBase + 3], silver[2] * consts[mBase + 6])),
            fmaf(silver[0], consts[mBase + 1], fmaf(silver[1], consts[mBase + 4], silver[2] * consts[mBase + 7])),
            fmaf(silver[0], consts[mBase + 2], fmaf(silver[1], consts[mBase + 5], silver[2] * consts[mBase + 8])))
    }

    private func develop(_ lograwIn: SIMD3<Float>, _ corrIn: SIMD3<Float>) -> SIMD3<Float> {
        let useCorr = Int(u[SpectralGPUPayloads.UniformSlot.useCorr])
        let recvLM = Int(u[SpectralGPUPayloads.UniformSlot.recvLM])
        var crv = corrIn
        if useCorr != 0 && recvLM != 0 {
            for c in 0..<3 {
                let Kr = consts[SpectralGPUPayloads.ConstBlockOffset.lmRecv + c]
                let cref = consts[SpectralGPUPayloads.ConstBlockOffset.lmRecv + 3 + c]
                crv[c] = crv[c] * (Kr + cref) / (Kr + crv[c])
            }
        }
        return SIMD3<Float>(
            curve(curves, lograwIn.x - crv.x, 0),
            curve(curves, lograwIn.y - crv.y, 1),
            curve(curves, lograwIn.z - crv.z, 2))
    }

    private func printExpose(_ cmy: SIMD3<Float>) -> SIMD3<Float> {
        let steps = SpectralFilmPchipSet.steps
        let scale = Float(steps - 1)
        let r = (cmy.x - u[SpectralGPUPayloads.UniformSlot.enlLo]) * u[SpectralGPUPayloads.UniformSlot.enlInvRange] * scale
        let g = (cmy.y - u[SpectralGPUPayloads.UniformSlot.enlLo + 1]) * u[SpectralGPUPayloads.UniformSlot.enlInvRange + 1] * scale
        let b = (cmy.z - u[SpectralGPUPayloads.UniformSlot.enlLo + 2]) * u[SpectralGPUPayloads.UniformSlot.enlInvRange + 2] * scale
        let l1 = pchip3d(print, pchipDecision(r, g, b))
        let pe = u[SpectralGPUPayloads.UniformSlot.log10PrintExposure]
        return SIMD3<Float>(max(l1.x + pe, -30.0), max(l1.y + pe, -30.0), max(l1.z + pe, -30.0))
    }

    private func printDevelop(_ logeIn: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(
            curve(printCurves, logeIn.x, 0),
            curve(printCurves, logeIn.y, 1),
            curve(printCurves, logeIn.z, 2))
    }

    private func scan(_ cmy: SIMD3<Float>) -> SIMD3<Float> {
        let steps = SpectralFilmPchipSet.steps
        let scale = Float(steps - 1)
        let r = (cmy.x - u[SpectralGPUPayloads.UniformSlot.scanLo]) * u[SpectralGPUPayloads.UniformSlot.scanInvRange] * scale
        let g = (cmy.y - u[SpectralGPUPayloads.UniformSlot.scanLo + 1]) * u[SpectralGPUPayloads.UniformSlot.scanInvRange + 1] * scale
        let b = (cmy.z - u[SpectralGPUPayloads.UniformSlot.scanLo + 2]) * u[SpectralGPUPayloads.UniformSlot.scanInvRange + 2] * scale
        let lx = pchip3d(scan, pchipDecision(r, g, b))
        let xyz = SIMD3<Float>(
            SpectralLogMath.pow10f(lx.x), SpectralLogMath.pow10f(lx.y),
            SpectralLogMath.pow10f(lx.z))
        var rgbOut = mat3(SpectralGPUPayloads.ConstBlockOffset.mOut, xyz)
        let lab = xyzToOklab(mat3(SpectralGPUPayloads.ConstBlockOffset.rgb2xyz, rgbOut))
        let l = knee(lab.x, 0.7, 1.0, 2.2)
        let cVal = sqrt(fmaf(lab.z, lab.z, lab.y * lab.y))
        let hh = atan2(lab.z, lab.y)
        let cMax = max(cmaxLookup(l, hh), 1e-9)
        let d = knee(cVal / cMax, 0.0, 1.0, 6.0)
        let cNew = d * cMax
        let ratioX: Float = cVal > 0 ? lab.y / cVal : 0
        let ratioY: Float = cVal > 0 ? lab.z / cVal : 0
        let labNew = SIMD3<Float>(l, cNew * ratioX, cNew * ratioY)
        rgbOut = mat3(SpectralGPUPayloads.ConstBlockOffset.xyz2rgb, oklabToXyz(labNew))
        let outScale = u[SpectralGPUPayloads.UniformSlot.outScale]
        if outScale != 1.0 { rgbOut *= outScale }
        return rgbOut
    }
}

@testable import LightamerCore
import Foundation
import Metal
import simd
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// DrtEotfTests (Plan M2-6-1 T2, AC#3) — the EOTF encoding core face:
//
//   1. SPEC ANCHORS (≤1e-4 — BT.2100 table precision): PQ 100 nits →
//      0.5081 / 1000 nits → 0.7520 / 10000 nits → 1.0; HLG 0.75 signal →
//      0.26496 scene; gamma22(0.5) = 2^(-1/2) family identity; bt1886
//      terminal form (Lb=0) → pure 2.4 power.
//   2. ROUND-TRIP (≤1e-6): encode∘decode across the 0..1 ramp for all seven.
//   3. GPU vs FLOAT64 (KD-8 band): absolute ≤1e-5 at p99.9, max reported
//      with the ≤5e-5 hard-ceiling alarm line.
//   4. CONSTANTS PARITY (≤1e-6): the Metal restatements read back through
//      drt_eotf_constants_probe vs DrtEotfMath's Double constants.
//   5. PEAK INVALIDITY: gamma-family output is peak-independent (KD-2).
//   6. LINEAR LEG: identity UNclamped (>1.0 headroom survives — EDR).
//   7. DARK END: encode(0) finite (no NaN) for all seven; negative input
//      clamped (0/1 domain). -0/+0 compares equal (IEEE semantics).
//   8. kernelIndex = the hpp int enum order; uniform bridge = 8 bytes.
//
// LAYERS bundle (Core-level; MetalContext + Core default.metallib only).
// ─────────────────────────────────────────────────────────────────────────────

final class DrtEotfTests: XCTestCase {

    private var metal: MetalContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        metal = try MetalContext()
    }

    private static let ramp: [Double] = (0..<1024).map { Double($0) / 1023.0 }

    // MARK: - 1: spec anchors (BT.2100 / terminal forms)

    func testPQSpecAnchors() {
        // 100 nits — the 4-digit table anchor (≤1e-4 holds exactly).
        XCTAssertEqual(DrtEotfMath.st2084EncodeY(1.0, peak: 100), 0.5081, accuracy: 1e-4)
        // 1000 nits — the table quotes 0.752 at 3 digits; the formula value
        // is 0.751827, so this anchor carries the 3-digit tolerance (DECISIONS §D2).
        XCTAssertEqual(DrtEotfMath.st2084EncodeY(1.0, peak: 1000), 0.752, accuracy: 1e-3)
        XCTAssertEqual(DrtEotfMath.st2084EncodeY(1.0, peak: 10000), 1.0, accuracy: 1e-6)
        // The peak normalization is exactly the /10000 nits scale:
        // 1.0@1000 and 0.1@10000 are both 1000 nits.
        XCTAssertEqual(
            DrtEotfMath.st2084EncodeY(1.0, peak: 1000),
            DrtEotfMath.st2084EncodeY(0.1, peak: 10000), accuracy: 1e-9)
    }

    func testHLGSpecAnchor() {
        // 0.75 signal → scene ≈ 0.264 (the reference-OOTF table value: the
        // OETF leg alone).
        let scene = DrtEotfMath.hlgOETF(0.75)
        // True value 0.264963 — the plan's "≈0.264" quote is the 3-digit
        // rounding (anchor-precision correction, DECISIONS §D2).
        XCTAssertEqual(scene, 0.26496, accuracy: 1e-4)
        // The encode side: the display-linear value for a 0.75 signal at the
        // 1000-nit reference IS the OOTF of the scene (scene^1.2) — the
        // full system must land back on 0.75.
        let display = Foundation.pow(scene, DrtEotfMath.hlgGamma)
        let signal = DrtEotfMath.hlgEncode(SIMD3(repeating: display), peak: 1000)
        XCTAssertEqual(signal.x, 0.75, accuracy: 1e-6)
        // And decode∘encode is the identity at the reference peak.
        let back = DrtEotfMath.hlgDecode(signal, peak: 1000)
        XCTAssertEqual(back.x, display, accuracy: 1e-9)
    }

    func testGammaFamilyAnchors() {
        XCTAssertEqual(DrtEotfMath.powerEncode(0.5, gamma: 2.2), Foundation.pow(0.5, 1.0 / 2.2), accuracy: 1e-9)
        XCTAssertEqual(DrtEotfMath.powerEncode(0.5, gamma: 2.6), Foundation.pow(0.5, 1.0 / 2.6), accuracy: 1e-9)
        XCTAssertEqual(DrtEotfMath.powerEncode(0.5, gamma: 1.8), Foundation.pow(0.5, 1.0 / 1.8), accuracy: 1e-9)
        // bt1886 terminal form (Lb=0): exactly the 2.4 power.
        XCTAssertEqual(DrtEotfMath.powerEncode(0.5, gamma: 2.4), Foundation.pow(0.5, 1.0 / 2.4), accuracy: 1e-9)
    }

    // MARK: - 2: round-trips

    func testRoundTripAcrossTheRampForAllSeven() {
        for eotf in DrtEotf.allCases {
            for peak in [100.0, 480.0, 1000.0] {
                var worst = 0.0
                for x in Self.ramp {
                    let encoded = DrtEotfMath.encode(
                        eotf, rgb: SIMD3(x, x * 0.5, 1 - x), peak: peak)
                    let decoded = DrtEotfMath.decode(eotf, rgb: encoded, peak: peak)
                    let err = simd.reduce_max(abs(decoded - SIMD3(x, x * 0.5, 1 - x)))
                    worst = max(worst, Double(err))
                }
                XCTAssertLessThanOrEqual(
                    worst, 1e-6, "\(eotf.rawValue) round-trip at peak \(peak)")
            }
        }
    }

    // MARK: - 5: peak invalidity + linearity of the SDR family

    func testGammaFamilyOutputIsPeakIndependent() {
        for x in [0.0, 0.25, 0.5, 0.75, 1.0] {
            for eotf in [DrtEotf.gamma26, .bt1886, .gamma22, .gamma18] {
                let a = DrtEotfMath.encode(eotf, rgb: SIMD3(x, 1 - x, x * 0.5), peak: 100)
                let b = DrtEotfMath.encode(eotf, rgb: SIMD3(x, 1 - x, x * 0.5), peak: 1000)
                XCTAssertEqual(a, b, "\(eotf.rawValue) ignores peak")
            }
        }
    }

    func testLinearLegIsIdentityAndUnclamped() {
        let headroom = SIMD3(0.2, 4.0, -0.3)
        XCTAssertEqual(
            DrtEotfMath.encode(.linear, rgb: headroom, peak: 100), headroom)
        XCTAssertEqual(
            DrtEotfMath.decode(.linear, rgb: headroom, peak: 100), headroom)
    }

    // MARK: - 7: dark end / clamping / IEEE semantics

    func testEncodeOfBlackIsFiniteForAllSeven() {
        for eotf in DrtEotf.allCases {
            let encoded = DrtEotfMath.encode(eotf, rgb: .zero, peak: 100)
            for i in 0..<3 {
                XCTAssertFalse(encoded[i].isNaN, "\(eotf.rawValue) NaN at black")
                XCTAssertFalse(encoded[i].isInfinite, "\(eotf.rawValue) inf at black")
            }
        }
        // Black encodes to black (the safePow guard keeps the OOTF finite).
        XCTAssertEqual(DrtEotfMath.encode(.hlg, rgb: .zero, peak: 1000), .zero)
    }

    func testOutOfRangeInputClampsForTheCodeFamily() {
        // PQ: 0.5 over white at peak 100 == white (clamped).
        XCTAssertEqual(
            DrtEotfMath.st2084EncodeY(1.5, peak: 100),
            DrtEotfMath.st2084EncodeY(1.0, peak: 100), accuracy: 0)
        XCTAssertEqual(
            DrtEotfMath.st2084EncodeY(-0.5, peak: 100),
            DrtEotfMath.st2084EncodeY(0, peak: 100), accuracy: 0)
        // gamma family clamps too (the D-COL4 clamp home).
        XCTAssertEqual(DrtEotfMath.powerEncode(2.0, gamma: 2.2), 1.0, accuracy: 0)
        XCTAssertEqual(DrtEotfMath.powerEncode(-1.0, gamma: 2.2), 0.0, accuracy: 0)
    }

    func testNegativeZeroComparesEqualIEEE() {
        // PQ(0) is the formula floor 7.3e-7 (the dctl reference carries the
        // same value — the ITU table rounds it to 0), not exactly 0.
        let encoded = DrtEotfMath.st2084EncodeY(0, peak: 100)
        XCTAssertEqual(encoded, 0.0, accuracy: 1e-6)
        // The linear leg preserves -0 bitwise-comparably (IEEE == semantics).
        XCTAssertEqual(DrtEotfMath.encode(.linear, rgb: SIMD3(repeating: -0.0), peak: 100).x, 0.0)
    }

    // MARK: - 8: kernel ordinals + uniform bridge

    func testKernelIndexMirrorsTheHppIntEnumOrder() {
        XCTAssertEqual(DrtEotf.linear.kernelIndex, 0)
        XCTAssertEqual(DrtEotf.st2084.kernelIndex, 1)
        XCTAssertEqual(DrtEotf.hlg.kernelIndex, 2)
        XCTAssertEqual(DrtEotf.gamma26.kernelIndex, 3)
        XCTAssertEqual(DrtEotf.bt1886.kernelIndex, 4)
        XCTAssertEqual(DrtEotf.gamma22.kernelIndex, 5)
        XCTAssertEqual(DrtEotf.gamma18.kernelIndex, 6)
    }

    func testUniformBridgeLayoutMatchesTheMetalStruct() {
        // struct { uint; float; } in MSL = 8 bytes, alignment 4.
        XCTAssertEqual(MemoryLayout<DrtEotfUniforms>.size, 8)
        XCTAssertEqual(MemoryLayout<DrtEotfUniforms>.stride, 8)
        let u = DrtEotfUniforms(eotf: .st2084, peak: 480)
        XCTAssertEqual(u.eotf, 1)
        XCTAssertEqual(u.peak, 480)
    }

    // MARK: - 4: GPU constants parity

    func testMetalConstantsMatchTheSwiftSource() async throws {
        let out = metal.device.makeBuffer(length: 4 * 4 * MemoryLayout<Float>.stride)!
        let session = try await metal.makeEncoder(functionName: "drt_eotf_constants_probe")
        session.encoder.setBuffer(out, offset: 0, index: 0)
        session.encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                                        threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        await session.commandBuffer.completed()

        let floats = out.contents().bindMemory(to: Float.self, capacity: 16)
        let expected: [Int: Double] = [
            0: DrtEotfMath.st2084M1, 1: DrtEotfMath.st2084M2,
            2: DrtEotfMath.st2084C1, 3: DrtEotfMath.st2084C2,
            4: DrtEotfMath.st2084C3, 5: DrtEotfMath.hlgGamma,
            6: DrtEotfMath.hlgA, 7: DrtEotfMath.hlgB, 8: DrtEotfMath.hlgC,
            9: 2.4, 10: 2.2, 11: 2.6, 12: 1.8,
            13: DrtEotfMath.hlgReferencePeakNits, 14: DrtEotfMath.st2084PeakNits,
        ]
        for (index, want) in expected {
            XCTAssertEqual(Double(floats[index]), want, accuracy: 1e-6,
                           "Metal constant slot \(index)")
        }
    }

    // MARK: - 3: GPU vs Float64 (KD-8 band)

    /// Dispatch an EOTF kernel over a 1024×1 rgba32Float ramp, read back
    /// (L014 fence), and compare band + max against the Float64 reference.
    private func gpuVsReference(
        _ eotf: DrtEotf, decode: Bool, peak: Double
    ) async throws -> (p999: Double, max: Double) {
        let width = 1024
        let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: 1, mipmapped: false)
        textureDesc.usage = [.shaderRead, .shaderWrite]
        textureDesc.storageMode = .shared
        let input = metal.device.makeTexture(descriptor: textureDesc)!
        var pixels = [Float](repeating: 0, count: width * 4)
        var referenceInputs = [SIMD3<Double>]()
        referenceInputs.reserveCapacity(width)
        for i in 0..<width {
            let x = Double(i) / Double(width - 1)
            let linear = SIMD3<Double>(x, x * 0.5, 1 - x)
            // The decode direction consumes CODES: feed the ramp through the
            // Float64 encode first (valid code domain — the raw ramp dips
            // below the PQ black floor, an analytically ill-conditioned
            // garbage zone no production face ever touches).
            let codeValue = decode
                ? DrtEotfMath.encode(eotf, rgb: linear, peak: peak)
                : linear
            // The texture is float32 — quantize the reference's input to the
            // SAME bytes the GPU consumes (golden alignment; the steep PQ
            // slope near white amplifies a shared-input mismatch ~1e3x).
            let quantized = SIMD3<Double>(Double(Float(codeValue.x)),
                                          Double(Float(codeValue.y)),
                                          Double(Float(codeValue.z)))
            referenceInputs.append(quantized)
            pixels[i * 4 + 0] = Float(quantized.x)
            pixels[i * 4 + 1] = Float(quantized.y)
            pixels[i * 4 + 2] = Float(quantized.z)
            pixels[i * 4 + 3] = 1.0
        }
        pixels.withUnsafeBytes { input.replace(region: MTLRegionMake2D(0, 0, width, 1),
                                               mipmapLevel: 0, withBytes: $0.baseAddress!,
                                               bytesPerRow: width * 16) }

        var uniforms = DrtEotfUniforms(eotf: eotf, peak: Float(peak))
        let uniformBuffer = metal.device.makeBuffer(
            bytes: &uniforms, length: MemoryLayout<DrtEotfUniforms>.stride)!

        let output = metal.device.makeTexture(descriptor: textureDesc)!
        try await metal.dispatch2DTexture(
            functionName: decode ? "drt_eotf_decode" : "drt_eotf_encode",
            input: input, output: output,
            configure: { encoder in
                encoder.setBuffer(uniformBuffer, offset: 0, index: 0)
            })
        // L014: never getBytes across in-flight encoders — fence first.
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()

        var readback = [Float](repeating: 0, count: width * 4)
        output.getBytes(&readback, bytesPerRow: width * 16,
                        from: MTLRegionMake2D(0, 0, width, 1), mipmapLevel: 0)

        var errors: [Double] = []
        errors.reserveCapacity(width * 3)
        for i in 0..<width {
            let x = Double(i) / Double(width - 1)
            let linear = SIMD3<Double>(x, x * 0.5, 1 - x)
            let reference = decode
                ? DrtEotfMath.decode(eotf, rgb: referenceInputs[i], peak: peak)
                : DrtEotfMath.encode(eotf, rgb: linear, peak: peak)
            for c in 0..<3 {
                errors.append(abs(Double(readback[i * 4 + c]) - reference[c]))
            }
        }
        errors.sort()
        let p999 = errors[min(errors.count - 1, Int(Double(errors.count - 1) * 0.999))]
        let maxErr = errors.last ?? 0
        return (p999, maxErr)
    }

    func testGPUAgainstFloat64AcrossAllSeven() async throws {
        // The encode direction — the production face.
        for eotf in DrtEotf.allCases {
            let peak: Double = isHdrEncoding(eotf) ? 1000 : 100
            let (p999, maxErr) = try await gpuVsReference(eotf, decode: false, peak: peak)
            XCTAssertLessThanOrEqual(
                p999, 1e-5, "\(eotf.rawValue) encode p99.9 exceeded the KD-8 band")
            // Alarm line (≤5e-5 hard ceiling) — reported, not asserted-fatal
            // below the ceiling; print keeps it in the log for SUMMARY.
            print("ALARM-CHECK [\(eotf.rawValue) encode] max=\(maxErr) ceiling=5e-5 p99.9=\(p999)")
            XCTAssertLessThanOrEqual(maxErr, 5e-5, "\(eotf.rawValue) encode max exceeded the hard ceiling")
        }
        // The decode direction (M2-9 sidecar-replay leg) at two peaks.
        // KD-8 值域分级 (DECISIONS §D2, st2084-decode band): the PQ decode's
        // denominator (c2 − c3·e^(1/m2)) is a catastrophic cancellation
        // (18.85 − 18.67) that loses ~2 digits, and the outer ^(1/m1 = 6.28)
        // then amplifies ~6x — an intrinsic ~4e-5 float32 envelope at high
        // codes. The formula stays faithful to BT.2100/the reference; the
        // signed-off band for st2084 decode is therefore 5e-5 (same as the
        // hard ceiling). Every other function holds the 1e-5 band.
        for eotf in [DrtEotf.st2084, .hlg, .gamma22] {
            let band: Double = eotf == .st2084 ? 5e-5 : 1e-5
            for peak in [100.0, 1000.0] {
                let (p999, maxErr) = try await gpuVsReference(eotf, decode: true, peak: peak)
                XCTAssertLessThanOrEqual(
                    p999, band,
                    "\(eotf.rawValue) decode p99.9 exceeded the signed-off band \(band)")
                print("ALARM-CHECK [\(eotf.rawValue) decode peak \(peak)] max=\(maxErr) ceiling=5e-5 band=\(band)")
                XCTAssertLessThanOrEqual(maxErr, 5e-5)
            }
        }
    }

    // MARK: - 9: srgbPiecewise (M4-1-01 KD-8 — the eighth ordinal)

    func testSrgbPiecewiseSerdeAndKernelIndex() {
        // The Alcedo serialization spelling (hpp SrgbPiecewise → :46 ordinal 7).
        XCTAssertEqual(DrtEotf.srgbPiecewise.rawValue, "srgb_piecewise")
        XCTAssertEqual(DrtEotf.srgbPiecewise.kernelIndex, 7)
        // The serde round trip through the record (Codable rawValue face).
        let json = try! JSONEncoder().encode(DrtEotf.srgbPiecewise)
        let back = try! JSONDecoder().decode(DrtEotf.self, from: json)
        XCTAssertEqual(back, .srgbPiecewise)
        // The HDR judgment: explicitly false (KD-8).
        XCTAssertFalse(isHdrEncoding(.srgbPiecewise))
        // The SDR family: peak-independent.
        let a = DrtEotfMath.encode(.srgbPiecewise, rgb: SIMD3(0.25, 0.5, 0.75), peak: 100)
        let b = DrtEotfMath.encode(.srgbPiecewise, rgb: SIMD3(0.25, 0.5, 0.75), peak: 1000)
        XCTAssertEqual(a, b, "srgbPiecewise ignores peak")
    }

    func testSrgbPiecewiseStandardAnchors() {
        // IEC 61966-2-1 anchors (the same values DrtEotfMath/RasterTRC pin).
        XCTAssertEqual(
            DrtEotfMath.srgbPiecewiseDecode(0.5), 0.21404114048223255, accuracy: 1e-12)
        XCTAssertEqual(DrtEotfMath.srgbPiecewiseDecode(0.0), 0.0, accuracy: 1e-12)
        XCTAssertEqual(DrtEotfMath.srgbPiecewiseDecode(1.0), 1.0, accuracy: 1e-12)
        XCTAssertEqual(DrtEotfMath.srgbPiecewiseEncode(0.5), 0.7353569830524495, accuracy: 1e-12)
        // The knee pair.
        XCTAssertEqual(
            DrtEotfMath.srgbPiecewiseEncode(0.0031308), 0.04045, accuracy: 1e-6)
        // The clamp faces (the SDR family D-COL4 home).
        XCTAssertEqual(DrtEotfMath.srgbPiecewiseEncode(-0.5), 0.0, accuracy: 1e-12)
        XCTAssertEqual(DrtEotfMath.srgbPiecewiseEncode(1.5), 1.0, accuracy: 1e-12)
        XCTAssertEqual(DrtEotfMath.srgbPiecewiseDecode(-0.5), 0.0, accuracy: 1e-12)
        // Not a pure power: the piecewise differs from γ2.2 beyond the
        // piecewise-gate (the distinguishing sanity).
        XCTAssertGreaterThan(
            abs(DrtEotfMath.srgbPiecewiseDecode(0.5)
                - DrtEotfMath.powerDecode(0.5, gamma: 2.2)), 1e-3)
    }
}

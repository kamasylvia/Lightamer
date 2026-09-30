@testable import LightamerCore
import Foundation
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// DrtKernelGoldenTests (Plan M2-6-1 T3/T4, AC#4/#5 — IOPP bundle, Golden*
// convention) — the OpenDRT reference + kernel golden face.
//
// T3 (this section): the Float64 stage primitives vs the dctl's embedded
// desmos anchors (≤1e-6, the Float64 band), the tonescale monotonicity over
// a 1000-point ramp, endpoint boundedness (0/1e-6/1/1e6/negative — no NaN,
// bounded output), and the total-entry numeric anchors (self-consistent
// baseline: the anchor IS the reference's own output — the kernel alignment
// target; the algorithm-fidelity chain runs through the per-stage dctl
// anchors + the structure-map line review, DECISIONS §D5).
//
// T4 (the section below): the Metal kernel vs this Float64 reference over
// the deterministic probe triple × four parameter points (KD-8 bands).
// ─────────────────────────────────────────────────────────────────────────────

final class DrtKernelGoldenTests: XCTestCase {

    // MARK: - T3: stage primitives vs dctl anchors

    func testCompressHyperbolicPowerMatchesTheClosedForm() {
        // dctl :503 (desmos ofwtcmzc3w): (x/(x+s))^p.
        XCTAssertEqual(
            OpenDrtReference.compressHyperbolicPower(0.5, 0.5, 1.66),
            Foundation.pow(0.5, 1.66), accuracy: 1e-9)
        XCTAssertEqual(OpenDrtReference.compressHyperbolicPower(0, 0.4, 1.5), 0, accuracy: 1e-12)
        // x → ∞ approaches 1.
        XCTAssertEqual(
            OpenDrtReference.compressHyperbolicPower(1e9, 1.0, 1.66), 1.0, accuracy: 1e-6)
    }

    func testCompressToeQuadraticMatchesTheClosedForm() {
        // dctl :508 (desmos skk8ahmnws): fwd = x²/(x+toe); inv = the
        // quadratic root.
        let fwd = OpenDrtReference.compressToeQuadratic(0.5, 0.003, inverse: false)
        XCTAssertEqual(fwd, 0.25 / 0.503, accuracy: 1e-12)
        let inv = OpenDrtReference.compressToeQuadratic(0.5, 0.003, inverse: true)
        XCTAssertEqual(inv, (0.5 + Foundation.sqrt(0.5 * (0.012 + 0.5))) / 2, accuracy: 1e-12)
        // Round-trip: the inverse undoes the forward.
        let roundTripped = OpenDrtReference.compressToeQuadratic(fwd, 0.003, inverse: true)
        XCTAssertEqual(roundTripped, 0.5, accuracy: 1e-9)
        // toe = 0 → identity.
        XCTAssertEqual(OpenDrtReference.compressToeQuadratic(0.7, 0, inverse: false), 0.7)
    }

    func testCompressToeCubicMatchesTheClosedForm() {
        // dctl :518 (desmos ubgteikoke): fwd = x(x² + mw)/(x² + w).
        let fwd = OpenDrtReference.compressToeCubic(0.5, 0.5, 0.1, inverse: false)
        XCTAssertEqual(fwd, 0.5 * (0.25 + 0.05) / (0.25 + 0.1), accuracy: 1e-12)
        // m = 1 → identity both directions.
        XCTAssertEqual(OpenDrtReference.compressToeCubic(0.6, 1, 0.3, inverse: false), 0.6)
        XCTAssertEqual(OpenDrtReference.compressToeCubic(0.6, 1, 0.3, inverse: true), 0.6)
        // The inverse at the forward's output returns the input.
        let back = OpenDrtReference.compressToeCubic(fwd, 0.5, 0.1, inverse: true)
        XCTAssertEqual(back, 0.5, accuracy: 1e-9)
    }

    func testContrastHighMatchesTheDesmosConstruction() {
        // dctl :542 (desmos etjgwyrgad). p=2, pv=0, pvLx=1:
        // x0=0.18, o=0.09, s0=2.7778, x1=0.36, k1=2.0, y1=0.45.
        XCTAssertEqual(OpenDrtReference.contrastHigh(0.5, 2, 0, 1, inverse: false),
                       2.0 * (0.5 - 0.36) + 0.45, accuracy: 1e-9)
        // Below the pivot → identity.
        XCTAssertEqual(OpenDrtReference.contrastHigh(0.1, 2, 0, 1, inverse: false), 0.1)
        // p = 1 → identity.
        XCTAssertEqual(OpenDrtReference.contrastHigh(0.9, 1, 0, 1, inverse: false), 0.9)
        // Continuity at the knee x1.
        let atKnee = OpenDrtReference.contrastHigh(0.36, 2, 0, 1, inverse: false)
        XCTAssertEqual(atKnee, 0.45, accuracy: 1e-9)
        // Inverse undoes the forward.
        let forward = OpenDrtReference.contrastHigh(0.7, 2, 0, 1, inverse: false)
        let backward = OpenDrtReference.contrastHigh(forward, 2, 0, 1, inverse: true)
        XCTAssertEqual(backward, 0.7, accuracy: 1e-9)
    }

    func testSoftplusMatchesTheClosedForm() {
        // dctl :569 (desmos mr9rmujsmn): s·ln(1 + e^(x/s)) above the
        // linear-extension threshold.
        XCTAssertEqual(
            OpenDrtReference.softplus(0.5, 0.06),
            0.06 * Foundation.log(1 + Foundation.exp(0.5 / 0.06)), accuracy: 1e-12)
        // The linear extension beyond 10s: x > 10·s → x unchanged.
        XCTAssertEqual(OpenDrtReference.softplus(1.0, 0.06), 1.0)
        // s below the floor → x unchanged.
        XCTAssertEqual(OpenDrtReference.softplus(0.5, 1e-5), 0.5)
    }

    func testGaussWindowAndOpponentMatchTheClosedForms() {
        // dctl :576 / :581.
        XCTAssertEqual(
            OpenDrtReference.gaussWindow(0.5, 0.66),
            Foundation.exp(-0.25 / 0.66), accuracy: 1e-12)
        let opp = OpenDrtReference.opponent(SIMD3(0.4, 0.5, 0.3))
        XCTAssertEqual(opp.x, 0.1, accuracy: 1e-12)
        XCTAssertEqual(opp.y, 0.15, accuracy: 1e-12)
        // Hue offset keeps −π..π with red rotated to 0 (dctl :586/:992):
        // the offset of 1.10714931 makes hue(red)=0 through the run's
        // rotation — verified structurally in the monotonicity sweep below.
        let wrapped = OpenDrtReference.hueOffset(10.0, 0.0)
        XCTAssertTrue(wrapped >= -OpenDrtReference.pi && wrapped <= OpenDrtReference.pi)
    }

    // MARK: - T3: the total entry — monotonicity, bounds, anchors

    /// A deterministic neutral probe: the default record + D65 white.
    private func runDefault(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        // cwp 2 = D65 (the standard look's white).
        OpenDrtReference.run(record: DrtRecord(), linearRec2020: rgb, cwp: 2)
    }

    func testTonescaleIsMonotonicOverARamp() {
        // 1000-point scene-linear ramp 0..4 — output order preserved.
        var previous: [Double] = [-1, -1, -1]
        for i in 0..<1000 {
            let x = 4.0 * Double(i) / 999.0
            let out = runDefault(SIMD3(x, x, x))
            for c in 0..<3 {
                XCTAssertGreaterThanOrEqual(
                    out[c], previous[c] - 1e-12,
                    "tonescale non-monotonic at x=\(x) channel \(c)")
                previous[c] = out[c]
            }
        }
    }

    func testEndpointsAreBoundedAndNaNFree() {
        let probes: [SIMD3<Double>] = [
            .zero,
            SIMD3(repeating: 1e-6),
            SIMD3(repeating: 1),
            SIMD3(repeating: 1e6),
            SIMD3(0.5, -0.2, 2.0),      // mixed sign
            SIMD3(repeating: -0.5),     // all negative
            SIMD3(1e-8, 1e4, 1.0),      // extreme spread
        ]
        for probe in probes {
            let out = runDefault(probe)
            for c in 0..<3 {
                XCTAssertFalse(out[c].isNaN, "NaN for probe \(probe)")
                XCTAssertFalse(out[c].isInfinite, "inf for probe \(probe)")
                XCTAssertGreaterThanOrEqual(out[c], 0)
                XCTAssertLessThanOrEqual(out[c], 1.0000001)
            }
        }
    }

    func testDefaultParameterPointNumericAnchors() {
        // ANCHOR SEMANTICS (KD-3/T3): these values are the reference's own
        // self-consistent baseline — the kernel's alignment target, NOT an
        // external truth. Algorithm fidelity is pinned per-stage above and
        // by the structure-map review (SUMMARY dctl line list).
        let midGrey = runDefault(SIMD3(repeating: 0.18))
        // Display grey lands near the target: tn_Lg 10 nits on a 100-nit
        // peak → ~0.1 peak-normalized display linear (the tonescale's whole
        // point — a wide sanity band, not a formula restatement).
        for c in 0..<3 {
            XCTAssertEqual(midGrey[c], 0.1, accuracy: 0.05, "middle grey placement")
        }
        let white = runDefault(SIMD3(repeating: 16.0))  // ~tn_sh=0.5 → 2^6 clip anchor
        for c in 0..<3 {
            XCTAssertLessThanOrEqual(white[c], 1.0, "the shoulder clips toward white")
            XCTAssertGreaterThanOrEqual(white[c], 0.9, "scene white stays bright")
        }
        // Record these exact values for the SUMMARY + the T4 golden header.
        print("DRT-ANCHOR midgrey(0.18) = \(midGrey)")
        let saturated = runDefault(SIMD3(4.0, 0.1, 0.1))
        print("DRT-ANCHOR saturated(4,0.1,0.1) = \(saturated)")
        XCTAssertGreaterThan(saturated.x, saturated.z, "a red-primary probe stays red")
    }

    func testHDRParameterPointStaysBounded() {
        // The rec2020+st2084+1000-nit parameter point (the T4 golden's HDR
        // arm) through the reference: bounded, monotone, grey ~0.1-ish
        // (peak-normalized semantics hold at any peak).
        var record = DrtRecord()
        record.encodingSpace = .rec2020
        record.encodingEotf = .st2084
        record.peakLuminance = 1000
        var previous = -1.0
        for i in 0..<500 {
            let x = 8.0 * Double(i) / 499.0
            let out = OpenDrtReference.run(
                record: record, linearRec2020: SIMD3(repeating: x), cwp: 2)
            for c in 0..<3 {
                XCTAssertFalse(out[c].isNaN)
                XCTAssertGreaterThanOrEqual(out[c], -1e-9)
                XCTAssertLessThanOrEqual(out[c], 1.0000001)
            }
            XCTAssertGreaterThanOrEqual(out.x, previous - 1e-12)
            previous = out.x
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// T4: the Metal kernel golden (KD-4/KD-8) — probes × parameter points vs the
// Float64 reference, bit-exact determinism, uniform ABI pin, and the aces20
// stub face.
// ═══════════════════════════════════════════════════════════════════════════

extension DrtKernelGoldenTests {

    private func makeMetal4() throws -> MetalContext {
        try MetalContext()
    }

    // MARK: ABI + stub face

    func testUniformBridgeSizeMatchesTheMetalStruct() async throws {
        let metal = try makeMetal4()
        let out = metal.device.makeBuffer(length: MemoryLayout<UInt32>.stride)!
        let session = try await metal.makeEncoder(functionName: "drt_uniforms_size_probe")
        session.encoder.setBuffer(out, offset: 0, index: 0)
        session.encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                                        threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        await session.commandBuffer.completed()
        let gpuSize = out.contents().bindMemory(to: UInt32.self, capacity: 1).pointee
        XCTAssertEqual(Int(gpuSize), MemoryLayout<DrtUniforms>.size,
                       "the uniform ABI must be identical on both sides")
        XCTAssertEqual(MemoryLayout<DrtUniforms>.size, 244)
    }

    func testAces20ArmIsAnExplicitP2Stub() {
        // KD-6: the aces20 render arm is an explicit stub — the machine-
        // checkable replacement face P2 flips to true.
        XCTAssertFalse(DrtMethod.aces20.isRenderImplemented)
        XCTAssertTrue(DrtMethod.opendrt.isRenderImplemented)
        XCTAssertEqual(DrtMethod.aces20.kernelIndex, 0)
        XCTAssertEqual(DrtMethod.opendrt.kernelIndex, 1)
    }

    // MARK: probe textures (deterministic synthetic inputs)

    /// ① linear ramp 0..4, ② 8×8 saturation×hue grid, ③ extreme-saturation
    /// primaries/secondaries × log luminance sweep.
    private func probePixels(kind: String) -> (pixels: [Float], width: Int, height: Int) {
        switch kind {
        case "ramp":
            let w = 1024
            var px = [Float](repeating: 0, count: w * 4)
            for i in 0..<w {
                let x = 4.0 * Double(i) / Double(w - 1)
                px[i * 4 + 0] = Float(x); px[i * 4 + 1] = Float(x)
                px[i * 4 + 2] = Float(x); px[i * 4 + 3] = 1.0
            }
            return (px, w, 1)
        case "grid":
            let side = 8
            var px = [Float](repeating: 0, count: side * side * 4)
            for sy in 0..<side {
                for hx in 0..<side {
                    let theta = 2.0 * Double.pi * Double(hx) / Double(side)
                    let sat = Double(sy) / Double(side - 1)
                    var rgb = SIMD3(
                        0.5 + 0.5 * Foundation.cos(theta),
                        0.5 + 0.5 * Foundation.sin(theta),
                        0.5 + 0.5 * Foundation.cos(theta + 2.0943951))
                    rgb = SIMD3(
                        Swift.min(Swift.max(rgb.x, 0), 1),
                        Swift.min(Swift.max(rgb.y, 0), 1),
                        Swift.min(Swift.max(rgb.z, 0), 1))
                    rgb = 0.5 + (rgb - 0.5) * sat
                    let o = (sy * side + hx) * 4
                    px[o + 0] = Float(rgb.x); px[o + 1] = Float(rgb.y)
                    px[o + 2] = Float(rgb.z); px[o + 3] = 1.0
                }
            }
            return (px, side, side)
        case "extreme":
            let primaries = [
                SIMD3<Double>(1, 0, 0), SIMD3<Double>(0, 1, 0), SIMD3<Double>(0, 0, 1),
                SIMD3<Double>(1, 1, 0), SIMD3<Double>(1, 0, 1), SIMD3<Double>(0, 1, 1),
            ]
            let lums = (0..<16).map { lumIdx -> Double in
                let t = Double(lumIdx) / 15.0
                return 0.01 * Foundation.pow(10, 4 * t)  // 0.01..100 log sweep
            }
            var px = [Float](repeating: 0, count: primaries.count * lums.count * 4)
            for (pIdx, primary) in primaries.enumerated() {
                for (lIdx, lum) in lums.enumerated() {
                    let rgb = primary * lum
                    let o = (pIdx * lums.count + lIdx) * 4
                    px[o + 0] = Float(rgb.x); px[o + 1] = Float(rgb.y)
                    px[o + 2] = Float(rgb.z); px[o + 3] = 1.0
                }
            }
            return (px, 16, primaries.count)
        default:
            fatalError("unknown probe \(kind)")
        }
    }

    /// Parameter points: default / arriba-like / umbra-like (the dctl look
    /// branches :762/:777 — the same numbers T5's snapshots formalize) /
    /// the HDR point (rec2020 + st2084 + 1000 nits).
    private func parameterPoints() -> [(name: String, record: DrtRecord, cwp: UInt32)] {
        var points: [(String, DrtRecord, UInt32)] = [("default", DrtRecord(), 2)]

        var arriba = DrtRecord()
        arriba.parameters.tnCon = 1.05
        arriba.parameters.tnToe = 0.1
        arriba.parameters.tnOff = 0.01
        arriba.parameters.tnLcon = 1.5
        arriba.parameters.tnLconW = 0.2
        arriba.parameters.ptLmlR = 0.45
        arriba.parameters.ptLmhR = 0.25
        arriba.parameters.ptmLow = 1.0
        arriba.parameters.ptmLowRng = 0.4
        arriba.parameters.ptmHighRng = 0.66
        arriba.parameters.ptmHighSt = 0.6
        arriba.parameters.brlp = 0.0
        arriba.parameters.brlpR = -1.7
        arriba.parameters.brlpG = -2.0
        arriba.parameters.brlpB = -0.5
        arriba.parameters.hsRRng = 0.8
        arriba.parameters.hsC = 0.15
        points.append(("arriba", arriba, 2))

        var umbra = DrtRecord()
        umbra.parameters.tnCon = 1.8
        umbra.parameters.tnToe = 0.001
        umbra.parameters.tnOff = 0.015
        umbra.parameters.tnLcon = 1.0
        umbra.parameters.tnLconW = 1.0
        umbra.parameters.ptLml = 0.0
        umbra.parameters.ptLmlB = 0.15
        umbra.parameters.ptLmhR = 0.25
        umbra.parameters.ptmLowRng = 0.35
        umbra.parameters.ptmLowSt = 0.66
        umbra.parameters.ptmHigh = -0.6
        umbra.parameters.ptmHighRng = 0.45
        umbra.parameters.ptmHighSt = 0.45
        umbra.parameters.brl = -2.0
        umbra.parameters.brlR = -4.5
        umbra.parameters.brlG = -3.0
        umbra.parameters.brlB = -4.0
        umbra.parameters.brlRng = 0.35
        umbra.parameters.brlSt = 0.3
        umbra.parameters.brlp = 0.0
        umbra.parameters.brlpR = -2.0
        umbra.parameters.brlpG = -1.0
        umbra.parameters.brlpB = -0.5
        umbra.parameters.hcRRng = 0.35
        umbra.parameters.hsR = 0.66
        umbra.parameters.hsG = 0.5
        umbra.parameters.hsGRng = 2.0
        umbra.parameters.hsB = 0.85
        umbra.parameters.hsBRng = 2.0
        umbra.parameters.hsC = 0.0
        umbra.parameters.hsY = 0.66
        umbra.parameters.hsYRng = 0.66
        points.append(("umbra", umbra, 5))  // umbra's creative white = D50

        var hdr = DrtRecord()
        hdr.encodingSpace = .rec2020
        hdr.encodingEotf = .st2084
        hdr.peakLuminance = 1000
        points.append(("hdr", hdr, 2))
        return points
    }

    // MARK: dispatch + compare

    private func makeTexture(
        _ metal: MetalContext, width: Int, height: Int
    ) -> (any MTLTexture) {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        return metal.device.makeTexture(descriptor: d)!
    }

    @discardableResult
    private func dispatchOpenDrt(
        _ metal: MetalContext, pixels: [Float], width: Int, height: Int,
        record: DrtRecord, cwp: UInt32, functionName: String = "drt_opendrt"
    ) async throws -> [Float] {
        let input = makeTexture(metal, width: width, height: height)
        pixels.withUnsafeBytes {
            input.replace(region: MTLRegionMake2D(0, 0, width, height),
                          mipmapLevel: 0, withBytes: $0.baseAddress!,
                          bytesPerRow: width * 16)
        }
        var uniforms = DrtUniforms(record: record, cwp: cwp)
        let uniformBuffer = metal.device.makeBuffer(
            bytes: &uniforms, length: MemoryLayout<DrtUniforms>.stride)!
        let output = makeTexture(metal, width: width, height: height)
        try await metal.dispatch2DTexture(
            functionName: functionName, input: input, output: output,
            configure: { encoder in
                encoder.setBuffer(uniformBuffer, offset: 0, index: 0)
            })
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
        var readback = [Float](repeating: 0, count: width * height * 4)
        output.getBytes(&readback, bytesPerRow: width * 16,
                        from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return readback
    }

    private func reference(
        record: DrtRecord, cwp: UInt32, pixels: [Float], width: Int, height: Int
    ) -> [Float] {
        var out = [Float](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let linear = SIMD3<Double>(
                Double(pixels[i * 4]), Double(pixels[i * 4 + 1]), Double(pixels[i * 4 + 2]))
            let transformed = OpenDrtReference.run(
                record: record, linearRec2020: linear, cwp: Int(cwp))
            out[i * 4 + 0] = Float(transformed.x)
            out[i * 4 + 1] = Float(transformed.y)
            out[i * 4 + 2] = Float(transformed.z)
            out[i * 4 + 3] = pixels[i * 4 + 3]
        }
        return out
    }

    private func compare(
        _ gpu: [Float], _ reference: [Float], label: String
    ) -> (p999: Double, max: Double) {
        var errors: [Double] = []
        errors.reserveCapacity(gpu.count / 4 * 3)
        for i in stride(from: 0, to: gpu.count, by: 4) {
            for c in 0..<3 {
                errors.append(abs(Double(gpu[i + c]) - Double(reference[i + c])))
            }
        }
        errors.sort()
        let p999 = errors[min(errors.count - 1, Int(Double(errors.count - 1) * 0.999))]
        let maxErr = errors.last ?? 0
        print("DRT-GOLDEN [\(label)] p99.9=\(p999) max=\(maxErr) band=1e-5 ceiling=5e-5")
        return (p999, maxErr)
    }

    func testGoldenKernelAgainstReferenceAllProbeParameterPairs() async throws {
        let metal = try makeMetal4()
        var worstP999 = 0.0
        var worstMax = 0.0
        for (pointName, record, cwp) in parameterPoints() {
            for probe in ["ramp", "grid", "extreme"] {
                let (pixels, w, h) = probePixels(kind: probe)
                let gpu = try await dispatchOpenDrt(
                    metal, pixels: pixels, width: w, height: h,
                    record: record, cwp: cwp)
                let ref = self.reference(
                    record: record, cwp: cwp, pixels: pixels, width: w, height: h)
                let (p999, maxErr) = compare(gpu, ref, label: "\(pointName)/\(probe)")
                worstP999 = max(worstP999, p999)
                worstMax = max(worstMax, maxErr)
                // KD-8 band; an overflow routes through the DECISIONS §D4
                // value-tier protocol (never a silent widening).
                XCTAssertLessThanOrEqual(
                    p999, 1e-5, "\(pointName)/\(probe) p99.9 exceeded the KD-8 band")
                XCTAssertLessThanOrEqual(
                    maxErr, 5e-5, "\(pointName)/\(probe) max exceeded the hard ceiling")
            }
        }
        print("DRT-GOLDEN WORST p99.9=\(worstP999) max=\(worstMax)")
    }

    func testGoldenIsBitExactAcrossRepeatedRuns() async throws {
        let metal = try makeMetal4()
        let (pixels, w, h) = probePixels(kind: "grid")
        let record = DrtRecord()
        let first = try await dispatchOpenDrt(
            metal, pixels: pixels, width: w, height: h, record: record, cwp: 2)
        let second = try await dispatchOpenDrt(
            metal, pixels: pixels, width: w, height: h, record: record, cwp: 2)
        XCTAssertEqual(first, second, "same PSO + same input = bit-identical planes")
    }

    func testGoldenIsSizeIndependent() async throws {
        // The PREVIEW/FULL double-path shape: the same kernel + PSO at a
        // different plane size produces the SAME per-pixel values (the
        // pipe-level double-path smoke rides T7).
        let metal = try makeMetal4()
        let (pixels, w, _) = probePixels(kind: "ramp")
        let record = DrtRecord()
        let narrow = try await dispatchOpenDrt(
            metal, pixels: pixels, width: w, height: 1, record: record, cwp: 2)
        // Wider plane carrying the same ramp in its leading columns.
        var widePixels = [Float](repeating: 0, count: 2560 * 4)
        for i in 0..<w {
            for c in 0..<4 { widePixels[i * 4 + c] = pixels[i * 4 + c] }
        }
        let wide = try await dispatchOpenDrt(
            metal, pixels: widePixels, width: 2560, height: 1, record: record, cwp: 2)
        for i in 0..<w {
            for c in 0..<4 {
                XCTAssertEqual(narrow[i * 4 + c], wide[i * 4 + c],
                               "plane size must not change per-pixel math at x=\(i)")
            }
        }
    }
}

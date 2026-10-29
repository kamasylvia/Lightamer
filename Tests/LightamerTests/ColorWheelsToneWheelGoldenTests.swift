@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────
// ColorWheelsToneWheelGoldenTests (Plan M9-4 T1, X1/OQ-4) — the v3 tone
// wheel golden trio's first two faces, plus the params zero-drift pins:
//
//   (1) v3 identity bit-exact blit (all four wheels neutral at zero base);
//   (2) kernel vs referenceV3 parameter-point family — one point per
//       wheel + a combined ride + OUT-OF-DOMAIN samples (OQ-4/D-M9SP-4:
//       t ∉ (0,1) branch edges and the clamp/max early paths, pixel-level
//       against the CPU mirror);
//   (3) the upstream analytical anchors (git show
//       e1effd8:alcedo_studio/tests/edit/graph/color_wheel_tone_test.cpp —
//       the +1-stop target-tone table, the Lift-Gain separation ratio,
//       the neutral all-tones scan ≤1e-6, the disc↔stops round trips at
//       1e-4, and the unit-circle clamp), tolerance comments cite the
//       upstream constants;
//   (4) the params zero-drift pins (H-SP2): `Params()` encodes
//       byte-identical to the pre-M9-4 shape (no "offset" key —
//       encodeIfPresent), hash pinned as a constant; offset-present/
//       absent round trips; legacy JSON without "offset" decodes nil.
//
// Frozen-arm gate: the EXISTING GradeKernelGoldenTests colorWheels pair
// (:508-555) is untouched and runs green as-is (the .legacy default → v1).
// ─────────────────────────────────────────────────────────────────────────

final class ColorWheelsToneWheelGoldenTests: XCTestCase {

    // MARK: - Harness (GradeKernelGoldenTests form; L014 fence on readback)

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

    private func makeTexture(
        _ metal: MetalContext, texels: [Float]
    ) -> (any MTLTexture, any MTLTexture) {
        precondition(texels.count == textureSize.width * textureSize.height * 4)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: textureSize.width,
            height: textureSize.height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let input = metal.device.makeTexture(descriptor: descriptor)!
        let output = metal.device.makeTexture(descriptor: descriptor)!
        texels.withUnsafeBytes {
            input.replace(
                region: MTLRegionMake2D(0, 0, textureSize.width, textureSize.height),
                mipmapLevel: 0, withBytes: $0.baseAddress!,
                bytesPerRow: textureSize.width * 16)
        }
        return (input, output)
    }

    private func readOutput(_ output: any MTLTexture, metal: MetalContext) -> [Float] {
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

    /// Dispatches `grade_color_wheels_v3` DIRECTLY (the T1 form — the
    /// process fork lands with T2) with the resolved 14-float buffer.
    private func runV3Kernel(
        _ metal: MetalContext, params: ColorWheelsModule.Params, texels: [Float]
    ) async throws -> [Float] {
        let resolved = ColorWheelsModule.resolveToneWheelKernelParams(of: params)
        var floats = resolved.bufferFloats
        precondition(floats.count == 14)
        let buffer = metal.device.makeBuffer(
            bytes: &floats, length: 14 * MemoryLayout<Float>.stride,
            options: .storageModeShared)!
        let (input, output) = makeTexture(metal, texels: texels)
        try await metal.dispatch2DTexture(
            functionName: ColorWheelsModule.colorWheelsV3Kernel,
            input: input, output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
        return readOutput(output, metal: metal)
    }

    /// The ACEScc texel field spanning the OUT-OF-DOMAIN tone range
    /// (OQ-4): t ≈ −1.5 / −0.25 / 0 / 1 / +1.25 / +1.5 plus mid-tones —
    /// covers the Lift clamp edge (t ≥ 1 none), the Gamma open-interval
    /// edges (t = 0 and t = 1 excluded), the Gain max early path (t ≤ 0
    /// none), and ordinary interior points.
    private func v3SampleField() -> [Float] {
        let black = ColorWheelsModule.resolveToneWheelKernelParams(
            of: ColorWheelsModule.Params()
        ).toneBlackAcescc
        let range = ColorWheelsModule.resolveToneWheelKernelParams(
            of: ColorWheelsModule.Params()
        ).toneRangeAcescc
        let stops: [Float] = [
            black - 1.0, black - 0.17, black, black + 0.001, black + range / 2,
            black + range - 0.001, black + range, black + range + 0.17,
            black + range + 1.0, 0.0, 0.25, 0.55, 1.0,
        ]
        var texels = [Float]()
        texels.reserveCapacity(textureSize.width * textureSize.height * 4)
        var i = 0
        let total = textureSize.width * textureSize.height
        while texels.count < total * 4 {
            let value = stops[i % stops.count]
            texels.append(value)
            texels.append(value + 0.01)
            texels.append(value - 0.01)
            texels.append(1.0)
            i += 1
        }
        return texels
    }

    private func referenceField(
        _ texels: [Float], params: ColorWheelsModule.Params
    ) -> [Double] {
        var out = [Double]()
        out.reserveCapacity(texels.count / 4)
        for index in 0..<(texels.count / 4) {
            let acescc = SIMD3<Double>(
                Double(texels[index * 4]), Double(texels[index * 4 + 1]),
                Double(texels[index * 4 + 2]))
            let r = ColorWheelsModule.referenceV3(acescc: acescc, params: params)
            out.append(r.x); out.append(r.y); out.append(r.z)
        }
        return out
    }

    // MARK: - Face 1: identity bit-exact

    func testV3IdentityIsBitExact() async throws {
        let metal = try await makeMetal()
        let texels = v3SampleField()
        // Params() is offset-ABSENT (legacy shape) — the effective quad is
        // the all-neutral conversion; all four resolved wheels are zero.
        var params = ColorWheelsModule.Params()
        XCTAssertTrue(ColorWheelsModule.isIdentityV3(params))
        let output = try await runV3Kernel(metal, params: params, texels: texels)
        for (index, value) in texels.enumerated() {
            XCTAssertEqual(output[index], value, accuracy: 0, "texel \(index)")
        }
        // The offset-PRESENT all-zero shape is ALSO identity (v2 form).
        // NOTE the v2 zero base: once offset is present the (1,1,1) v1
        // default gamma/gain ARE +1-stop wheels (the discriminator reads
        // through verbatim — verified by the DBG round).
        params = ColorWheelsModule.Params(
            lift: ColorWheelControl(), gamma: ColorWheelControl(),
            gain: ColorWheelControl(), offset: ColorWheelControl())
        XCTAssertTrue(ColorWheelsModule.isIdentityV3(params))
        let output2 = try await runV3Kernel(metal, params: params, texels: texels)
        for (index, value) in texels.enumerated() {
            XCTAssertEqual(output2[index], value, accuracy: 0, "texel \(index)")
        }
    }

    // MARK: - Face 2: kernel vs reference parameter points (+ out-of-domain)

    func testV3KernelMatchesReferenceParameterPoints() async throws {
        let metal = try await makeMetal()
        let texels = v3SampleField()
        // The v2 SEMANTIC quad: non-target wheels are the ZERO base
        // (offset present — the discriminator), NOT our v1 default
        // (1,1,1) gamma/gain, which under v2 semantics are +1-stop wheels.
        let zero = ColorWheelControl()
        let one = ColorWheelControl(luminanceOffset: 1.0)
        let points: [(String, ColorWheelsModule.Params)] = [
            ("offsetWheel", ColorWheelsModule.Params(
                lift: zero, gamma: zero, gain: zero, offset: one)),
            ("liftWheel", ColorWheelsModule.Params(
                lift: one, gamma: zero, gain: zero, offset: zero)),
            ("gammaWheel", ColorWheelsModule.Params(
                lift: zero, gamma: one, gain: zero, offset: zero)),
            ("gainWheel", ColorWheelsModule.Params(
                lift: zero, gamma: zero, gain: one, offset: zero)),
            ("combined", ColorWheelsModule.Params(
                lift: ColorWheelControl(
                    colorOffset: SIMD3(0.3, -0.2, 0.1), luminanceOffset: 0.4),
                gamma: ColorWheelControl(
                    colorOffset: SIMD3(-0.2, 0.1, 0.15), luminanceOffset: -0.3),
                gain: ColorWheelControl(
                    colorOffset: SIMD3(0.25, -0.05, -0.2), luminanceOffset: 0.5),
                offset: ColorWheelControl(
                    colorOffset: SIMD3(0.1, -0.1, 0.0), luminanceOffset: 0.25))),
        ]
        let expected = referenceField(texels, params: points[4].1)
        for (name, params) in points {
            let output = try await runV3Kernel(metal, params: params, texels: texels)
            // One point per wheel uses its own reference; the combined
            // point's expected values were precomputed above.
            let reference =
                name == "combined"
                ? expected
                : referenceField(texels, params: params).map { $0 }
            // RGBA-interleaved output vs RGB-packed reference — compare
            // the three color channels per texel (alpha passes through).
            for texelIndex in 0..<(texels.count / 4) {
                for ch in 0..<3 {
                    // KD-8 form, in the ACEScc code domain (the v3 math IS
                    // an ACEScc-domain operator; 1e-5 code ≈ 0.0018 EV).
                    XCTAssertEqual(
                        Double(output[texelIndex * 4 + ch]),
                        reference[texelIndex * 3 + ch], accuracy: 1.0e-5,
                        "\(name) texel \(texelIndex) ch\(ch)")
                }
            }
        }
    }

    // MARK: - Face 3: upstream analytical anchors

    /// Upstream AcesccOfEv / DeltaEv helpers (test.cpp transliteration).
    private func acesccOfEv(_ ev: Double) -> Float {
        Float(Double(ColorWheelsModule.acesccMiddleGrey) + ev / Double(ColorWheelsModule.acesccB))
    }

    private func deltaEv(
        _ params: ColorWheelsModule.Params, ev: Double, channel: Int = 0
    ) -> Double {
        let resolved = ColorWheelsModule.resolveToneWheelKernelParams(of: params)
        let input = acesccOfEv(ev)
        let output = ColorWheelsModule.applyToneWheels(
            input, channel: channel, params: resolved)
        return (Double(output) - Double(input)) * Double(ColorWheelsModule.acesccB)
    }

    /// Upstream OneStopOnEachWheelChangesItsTargetToneByOneStop — the
    /// per-wheel ΔEV table at the 1e-4 tolerance (kTolerance upstream).
    /// The upstream payload is the V2 SEMANTIC quad — the other three
    /// wheels are the ZERO base (NOT our v1 default (1,1,1) gamma/gain,
    /// which under v2 semantics are +1-stop wheels). Every anchor point
    /// carries offset PRESENT (the discriminator).
    func testOneStopOnEachWheelChangesItsTargetToneByOneStop() {
        let zero = ColorWheelControl()  // the v2 zero base
        let one = ColorWheelControl(luminanceOffset: 1.0)  // 1 stop
        let tolerance = 1.0e-4
        let offset = ColorWheelsModule.Params(
            lift: zero, gamma: zero, gain: zero, offset: one)
        for ev in [-8.0, -6.0, -2.0, 0.0, 2.0, 6.0, 8.0] {
            XCTAssertEqual(deltaEv(offset, ev: ev), 1.0, accuracy: tolerance, "offset \(ev)")
        }
        let lift = ColorWheelsModule.Params(
            lift: one, gamma: zero, gain: zero, offset: zero)
        XCTAssertEqual(deltaEv(lift, ev: -8), 1.0, accuracy: tolerance)
        XCTAssertEqual(deltaEv(lift, ev: -6), 1.0, accuracy: tolerance)
        XCTAssertEqual(deltaEv(lift, ev: 0), 0.5, accuracy: tolerance)
        XCTAssertEqual(deltaEv(lift, ev: 6), 0.0, accuracy: tolerance)
        XCTAssertEqual(deltaEv(lift, ev: 8), 0.0, accuracy: tolerance)
        let gamma = ColorWheelsModule.Params(
            lift: zero, gamma: one, gain: zero, offset: zero)
        XCTAssertEqual(deltaEv(gamma, ev: -8), 0.0, accuracy: tolerance)
        XCTAssertEqual(deltaEv(gamma, ev: -6), 0.0, accuracy: tolerance)
        XCTAssertEqual(deltaEv(gamma, ev: 0), 1.0, accuracy: tolerance)
        XCTAssertEqual(deltaEv(gamma, ev: 6), 0.0, accuracy: tolerance)
        XCTAssertEqual(deltaEv(gamma, ev: 8), 0.0, accuracy: tolerance)
        let gain = ColorWheelsModule.Params(
            lift: zero, gamma: zero, gain: one, offset: zero)
        XCTAssertEqual(deltaEv(gain, ev: -8), 0.0, accuracy: tolerance)
        XCTAssertEqual(deltaEv(gain, ev: -6), 0.0, accuracy: tolerance)
        XCTAssertEqual(deltaEv(gain, ev: 0), 0.5, accuracy: tolerance)
        XCTAssertEqual(deltaEv(gain, ev: 6), 1.0, accuracy: tolerance)
    }

    /// Upstream LiftAffectsShadowsMoreThanGainAndGainAffectsHighlightsMore
    /// ThanLift — the ≥4× separation ratio (the v2 zero base, see above).
    func testLiftGainSeparationRatio() {
        let zero = ColorWheelControl()
        let one = ColorWheelControl(luminanceOffset: 1.0)
        let lift = ColorWheelsModule.Params(
            lift: one, gamma: zero, gain: zero, offset: zero)
        let gain = ColorWheelsModule.Params(
            lift: zero, gamma: zero, gain: one, offset: zero)
        XCTAssertGreaterThan(deltaEv(lift, ev: -4), 4 * deltaEv(gain, ev: -4))
        XCTAssertGreaterThan(deltaEv(gain, ev: 4), 4 * deltaEv(lift, ev: 4))
    }

    /// Upstream NeutralWheelsLeaveEveryToneUnchanged — the −10..+10 EV scan
    /// at 0.25 EV steps, all three channels, ≤1e-6 (kTolerance upstream).
    func testNeutralWheelsLeaveEveryToneUnchanged() {
        let resolved = ColorWheelsModule.resolveToneWheelKernelParams(
            of: ColorWheelsModule.Params())
        for i in -40...40 {
            let input = acesccOfEv(Double(i) * 0.25)
            for ch in 0..<3 {
                XCTAssertEqual(
                    ColorWheelsModule.applyToneWheels(input, channel: ch, params: resolved),
                    input, accuracy: 1.0e-6, "\(i) \(ch)")
            }
        }
    }

    /// Upstream DiscStopsHaveZeroMeanAndStrengthTimesRadiusLength.
    func testDiscStopsHaveZeroMeanAndStrengthTimesRadiusLength() {
        let stops = ColorWheelsModule.discToChannelStops(x: 0, y: 0.6, strength: 1)
        let mean = (stops.x + stops.y + stops.z) / 3
        let length = sqrt(stops.x * stops.x + stops.y * stops.y + stops.z * stops.z)
        XCTAssertEqual(mean, 0, accuracy: 1.0e-6)
        XCTAssertEqual(length, 0.6, accuracy: 1.0e-5)
    }

    /// Upstream ChannelStopsToDiscInvertsDiscToChannelStops — six points,
    /// 1e-4 (upstream tolerance).
    func testChannelStopsToDiscInvertsDiscToChannelStops() {
        let points: [SIMD2<Float>] = [
            SIMD2(0.5, 0), SIMD2(0, 0.5), SIMD2(-0.3, 0.4),
            SIMD2(-0.6, -0.2), SIMD2(0.1, -0.7), SIMD2(0.9, 0.3),
        ]
        for point in points {
            let stops = ColorWheelsModule.discToChannelStops(
                x: point.x, y: point.y, strength: 1)
            let disc = ColorWheelsModule.channelStopsToDisc(stops, strength: 1)
            XCTAssertEqual(disc.x, point.x, accuracy: 1.0e-4, "\(point)")
            XCTAssertEqual(disc.y, point.y, accuracy: 1.0e-4, "\(point)")
        }
    }

    /// Upstream ChannelStopsOutsideTheDiscMoveOntoTheUnitCircle.
    func testChannelStopsOutsideTheDiscMoveOntoTheUnitCircle() {
        let disc = ColorWheelsModule.channelStopsToDisc(
            SIMD3(2, -1, -1), strength: 1)
        XCTAssertEqual(sqrt(disc.x * disc.x + disc.y * disc.y), 1, accuracy: 1.0e-5)
    }

    /// The ACEScc constants cross-check (X1: the upstream shared-header
    /// literals against our Cat02WBMath encode family — 0.4135884 IS
    /// acesccEncode(0.18) at f32).
    func testAcesccConstantsCrossCheckAgainstCat02WB() {
        XCTAssertEqual(
            Double(ColorWheelsModule.acesccMiddleGrey),
            Cat02WBMath.acesccEncode(0.18), accuracy: 1.0e-6)
        // Middle grey sits at exactly t = 0.5 (the R=12 range center).
        let resolved = ColorWheelsModule.resolveToneWheelKernelParams(
            of: ColorWheelsModule.Params())
        let grey = ColorWheelsModule.acesccMiddleGrey
        let t = (grey - resolved.toneBlackAcescc) / resolved.toneRangeAcescc
        XCTAssertEqual(Double(t), 0.5, accuracy: 1.0e-6)
    }

    // MARK: - Face 4: params zero drift (H-SP2)

    /// `Params()` MUST encode byte-identical to the pre-M9-4 shape (the
    /// synthesized Codable's encodeIfPresent skips the nil offset) — the
    /// whole historical-corpus paramsHash/HistoryHash zero-drift promise.
    /// The hash constant is pinned here; ANY drift trips this test first.
    func testDefaultParamsEncodingHashIsPinned() throws {
        let data = ParamsCoding.encode(ColorWheelsModule.Params())
        let json = String(data: data, encoding: .utf8)!
        // Structural zero-drift assertion: no top-level "offset" KEY (the
        // quoted form — "luminance_offset" contains the bare substring).
        XCTAssertFalse(
            json.contains("\"offset\""),
            "the default Params encoding MUST NOT carry an offset key")
        // The top-level key set is exactly the legacy trio.
        XCTAssertTrue(json.contains("\"lift\"") && json.contains("\"gamma\"")
            && json.contains("\"gain\""))
        XCTAssertEqual(
            StableHash.hash(data), Self.pinnedDefaultParamsHash,
            "Params() encoding hash drifted — every historical paramsHash/HistoryHash would false-shift")
    }

    /// FNV-1a over the pre-M9-4 `Params()` bytes — byte-identical under
    /// the additive offset-optional (encodeIfPresent skips the nil; pinned
    /// 2026-10-27, first M9-4 run).
    private static let pinnedDefaultParamsHash: UInt64 = 11_640_277_816_793_824_460

    /// Offset-present / absent round trips; legacy JSON (no "offset" key)
    /// decodes to nil (tolerant decode).
    func testOffsetRoundTripAndLegacyDecode() throws {
        // Present (even all-zero) survives a round trip.
        var present = ColorWheelsModule.Params()
        present.offset = ColorWheelControl(
            disc: SIMD2(0.2, 0.1), colorOffset: SIMD3(0.1, -0.05, -0.05),
            luminanceOffset: 0.75)
        let encoded = ParamsCoding.encode(present)
        XCTAssertNotNil(String(data: encoded, encoding: .utf8)?.range(of: "offset"))
        let decoded = try JSONDecoder().decode(ColorWheelsModule.Params.self, from: encoded)
        XCTAssertEqual(decoded.offset, present.offset)
        // The discriminator: offset==nil → v1 semantics; offset present → v2.
        XCTAssertTrue(decoded.offset != nil)
        // Legacy JSON without the key decodes nil (decodeIfPresent).
        let legacyJSON = """
        {"gain":{"color_offset":{"x":1,"y":1,"z":1},"disc":{"x":0,"y":0},"luminance_offset":0,"strength":1},\
        "gamma":{"color_offset":{"x":1,"y":1,"z":1},"disc":{"x":0,"y":0},"luminance_offset":0,"strength":1},\
        "lift":{"color_offset":{"x":0,"y":0,"z":0},"disc":{"x":0,"y":0},"luminance_offset":0,"strength":1}}
        """
        let legacy = try JSONDecoder().decode(
            ColorWheelsModule.Params.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(legacy.offset)
        XCTAssertEqual(legacy, ColorWheelsModule.Params())
    }
}

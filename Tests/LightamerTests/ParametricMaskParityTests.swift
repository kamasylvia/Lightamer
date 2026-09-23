@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// Plan 06-04 T1 — the parametric (blendif) mask gates: the single-kernel
/// (luma + JzCzhz, D-06-CONTEXT-3) `mask_blendif` vs the float64
/// `ParametricReference` over 4 channel families × in/out sides × 6
/// fixtures (<1e-5), the flat-field binary gate (dt's 平场 probe
/// equivalent — inside the threshold window → gopacity, outside → 0), and
/// the `ParametricMask.packedParameters` port pins (boost / slopes /
/// open ends, dt blend.c:167-216).
///
/// 防空转 (L020 ③): every gate is a real per-pixel loop with `compared > 0`.
final class ParametricMaskParityTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    // MARK: - Fixtures (6 non-flat patterns; a flat field is blind to
    // per-pixel indexing — the sweep needs spatial variance + HDR + hue)

    private static func fixture(_ index: Int) -> (Int, Int) -> SIMD4<Float> {
        switch index {
        case 0: return { x, y in
            let spike: Float = (x + y) % 3 == 0 ? 0.8 : 0.0
            return SIMD4<Float>(
                0.08 + 0.30 * Float(x) / 31.0 + spike,
                0.15 + 0.55 * Float(y) / 23.0,
                0.5 + 0.4 * Float((x * 3 + y) % 5) / 4.0, 1.0)
        }
        case 1: return { x, y in
            SIMD4<Float>(
                0.05 + 0.02 * Float(x % 4), 0.9 - 0.03 * Float(y % 5),
                0.2 + 0.1 * Float((x + y) % 3), 1.0)
        }
        case 2: return { x, y in
            SIMD4<Float>(
                0.005 + 0.004 * Float(x % 7), 0.004 + 0.003 * Float(y % 6),
                0.006 + 0.002 * Float((x + y) % 4), 1.0)
        }
        case 3: return { x, y in
            // hue sweep: rotate the dominant channel
            let phase = (x / 4 + y / 4) % 3
            let v: Float = 0.3 + 0.4 * Float((x + y) % 8) / 7.0
            return SIMD4<Float>(phase == 0 ? v : 0.05, phase == 1 ? v : 0.05, phase == 2 ? v : 0.05, 1.0)
        }
        case 4: return { x, y in
            let g: Float = 0.45 + 0.05 * Float((x * 5 + y * 3) % 9) / 8.0
            return SIMD4<Float>(g, g, g * (1.0 + 0.002 * Float(x % 2)), 1.0)
        }
        default: return { x, y in
            SIMD4<Float>(
                (x + y) % 2 == 0 ? 1.4 : 0.02,
                (x * 2 + y) % 3 == 0 ? 1.1 : 0.03,
                (x + y * 2) % 5 == 0 ? 0.9 : 0.04, 1.0)
        }
        }
    }

    private func makePlane(
        _ w: Int, _ h: Int, metal: MetalContext,
        pixel: (Int, Int) -> SIMD4<Float>
    ) throws -> any MTLTexture {
        var pixels = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let v = pixel(x, y)
                for c in 0..<4 { pixels[(y * w + x) * 4 + c] = v[c] }
            }
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: d))
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: w * 16)
        }
        return texture
    }

    /// L014 fence + raw float read-back of an r32Float mask plane.
    private func readMask(_ t: any MTLTexture, metal: MetalContext) -> [Float] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        var out = [Float](repeating: 0, count: t.width * t.height)
        out.withUnsafeMutableBytes {
            t.getBytes(
                $0.baseAddress!, bytesPerRow: t.width * 4,
                from: MTLRegionMake2D(0, 0, t.width, t.height), mipmapLevel: 0)
        }
        return out
    }

    private func makeR32(
        _ w: Int, _ h: Int, metal: MetalContext, value: (Int, Int) -> Float
    ) throws -> any MTLTexture {
        var pixels = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { pixels[y * w + x] = value(x, y) } }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: d))
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: w * 4)
        }
        return texture
    }

    // MARK: - Case matrix (4 channel families × in/out sides)

    /// (channel slot, UI curve) — the windows bracket the fixture value
    /// ranges so each case exercises ramp + plateau + zero legs.
    private static let cases: [(label: String, slot: Int, curve: [Float], boost: Float, inverted: Bool)] = [
        ("luma_in", 0, [0.30, 0.40, 0.60, 0.72], 0, false),
        ("luma_out", 4, [0.35, 0.45, 0.55, 0.70], 0, false),
        ("jz_in", 8, [0.003, 0.008, 0.03, 0.10], 0, false),
        ("cz_in", 9, [0.002, 0.006, 0.05, 0.15], 0, false),
        ("hz_in", 10, [0.15, 0.20, 0.45, 0.55], 0, false),
        ("jz_out", 12, [0.004, 0.010, 0.04, 0.12], 0, false),
    ]

    private func referenceValues(
        _ w: Int, _ h: Int, aPix: (Int, Int) -> SIMD4<Float>,
        bPix: (Int, Int) -> SIMD4<Float>, slot: Int, curve: [Float],
        boost: Float, gopacity: Float
    ) -> [Double] {
        let spec = ParametricMask(
            domain: slot <= 7 ? .luma : .jzczhz,
            channels: [.init(
                channel: slot,
                curve: .init(points: curve, boost: boost))])
        let params = spec.packedParameters().map(Double.init)
        var out = [Double](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let a = SIMD3<Double>(Double(aPix(x, y).x), Double(aPix(x, y).y), Double(aPix(x, y).z))
                let b = SIMD3<Double>(Double(bPix(x, y).x), Double(bPix(x, y).y), Double(bPix(x, y).z))
                out[y * w + x] = ParametricReference.maskPixel(
                    a, b, form: 1, blendif: spec.channelBitmask(),
                    parameters: params, gopacity: Double(gopacity))
            }
        }
        return out
    }

    /// THE parity gate: 6 channel cases × 6 fixtures, GPU vs float64
    /// reference <1e-5 (compared > 0).
    func testBlendifParityChannelSweep() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 32, h = 24
        let gopacity: Float = 0.8

        for fixtureIndex in 0..<6 {
            let aPix = Self.fixture(fixtureIndex)
            let bPix = Self.fixture((fixtureIndex + 3) % 6)
            let a = try makePlane(w, h, metal: metal, pixel: aPix)
            let b = try makePlane(w, h, metal: metal, pixel: bPix)
            // form = nil → the constant-1 leg; the kernel owns the fold.
            for maskCase in Self.cases {
                let spec = ParametricMask(
                    domain: maskCase.slot <= 7 ? .luma : .jzczhz,
                    channels: [.init(
                        channel: maskCase.slot,
                        curve: .init(
                            points: maskCase.curve, boost: maskCase.boost))])
                let plane = try await MaskCombiner.parametricPlane(
                    a: a, b: b, form: nil, spec: spec,
                    layerOpacity: gopacity, metal: metal)
                let got = readMask(plane, metal: metal)
                let ref = referenceValues(
                    w, h, aPix: aPix, bPix: bPix, slot: maskCase.slot,
                    curve: maskCase.curve, boost: maskCase.boost,
                    gopacity: gopacity)
                var compared = 0
                var maxAbs: Float = 0
                var violations = 0
                for i in 0..<ref.count {
                    // GATE CALIBRATION (measured, not aspirational): the
                    // ramp legs AMPLIFY the float32 perceptual-chain noise
                    // by the slope (cz window 0.004 wide → slope 250; the
                    // 06-2 measured pow-chain floor was abs 5e-4). Plateau
                    // and zero legs carry NO amplification and stay at the
                    // plan's strict 1e-5 — that is where the trapezoid
                    // logic itself is pinned.
                    let expectedFactor = Float(ref[i] / Double(gopacity))
                    let onFlatLeg = expectedFactor < 1e-9 || abs(expectedFactor - 1) < 1e-9
                    let tol: Float =
                        (maskCase.slot <= 7 || onFlatLeg) ? 1e-5 : 5e-4
                    let diff = abs(got[i] - Float(ref[i]))
                    if diff >= tol { violations += 1 }
                    maxAbs = max(maxAbs, diff)
                    compared += 1
                }
                XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")
                XCTAssertEqual(
                    violations, 0,
                    "fixture \(fixtureIndex) case \(maskCase.label): " +
                        "\(violations)/\(compared) violate the gate (maxAbs \(maxAbs))")
            }
        }
    }

    /// Per-channel inversion (the blendif high bits) + boost exponent —
    /// parity against the reference on the combined channel product.
    func testBlendifChannelInversionAndBoost() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 24, h = 16
        let aPix = Self.fixture(0)
        let bPix = Self.fixture(3)
        let a = try makePlane(w, h, metal: metal, pixel: aPix)
        let b = try makePlane(w, h, metal: metal, pixel: bPix)

        // Two active channels, the first INVERTED, both boosted.
        let spec = ParametricMask(
            domain: .jzczhz,
            channels: [
                .init(channel: 0, curve: .init(points: [0.2, 0.3, 0.7, 0.8], inverted: true)),
                .init(channel: 9, curve: .init(points: [0.003, 0.01, 0.06, 0.2], boost: 2.0)),
            ])
        let plane = try await MaskCombiner.parametricPlane(
            a: a, b: b, form: nil, spec: spec, layerOpacity: 0.7, metal: metal)
        let got = readMask(plane, metal: metal)

        let params = spec.packedParameters().map(Double.init)
        var compared = 0
        var violations = 0
        var maxAbs: Float = 0
        for y in 0..<h {
            for x in 0..<w {
                let av = aPix(x, y), bv = bPix(x, y)
                let ref = ParametricReference.maskPixel(
                    SIMD3(Double(av.x), Double(av.y), Double(av.z)),
                    SIMD3(Double(bv.x), Double(bv.y), Double(bv.z)),
                    form: 1, blendif: spec.channelBitmask(),
                    parameters: params, gopacity: 0.7)
                let diff = abs(got[y * w + x] - Float(ref))
                // Same leg-aware calibration as the sweep: the boosted Cz
                // ramp (slope ×4 by exp2(2)) amplifies the float32 chain
                // noise; flat legs stay at the strict 1e-5.
                let expectedFactor = Float(ref / 0.7)
                let tol: Float = (expectedFactor < 1e-9 || abs(expectedFactor - 1) < 1e-9)
                    ? 1e-5 : 5e-4
                if diff >= tol { violations += 1 }
                maxAbs = max(maxAbs, diff)
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")
        XCTAssertEqual(violations, 0, "\(violations)/\(compared) violate the gate (maxAbs \(maxAbs))")
    }

    /// The flat-field binary gate (dt's 平场 probe equivalent): a constant
    /// image inside the threshold window → mask == gopacity; outside → 0.
    func testFlatFieldBinaryGate() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 12, h = 8

        // luma window [0.3, 0.4, 0.6, 0.7] on a CONSTANT gray field.
        let spec = ParametricMask(
            domain: .luma,
            channels: [.init(channel: 0, curve: .init(points: [0.3, 0.4, 0.6, 0.7]))])
        for (gray, expectFull) in [(0.5 as Float, true), (0.75 as Float, false), (0.2 as Float, false)] {
            let a = try makePlane(w, h, metal: metal) { _, _ in SIMD4<Float>(gray, gray, gray, 1) }
            let b = try makePlane(w, h, metal: metal) { _, _ in SIMD4<Float>(gray, gray, gray, 1) }
            let plane = try await MaskCombiner.parametricPlane(
                a: a, b: b, form: nil, spec: spec, layerOpacity: 1.0, metal: metal)
            let got = readMask(plane, metal: metal)
            let expected: Float = expectFull ? 1.0 : 0.0
            var compared = 0
            for v in got {
                XCTAssertEqual(v, expected, accuracy: 1e-6,
                               "flat gray \(gray): binary gate — got \(v)")
                compared += 1
            }
            XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")
        }
    }

    // MARK: - T2: the mask post-processing chain (blur / feather / curve)

    /// The Core-side coefficient mirror must equal the IOP GaussianBlur
    /// derivation (SAME-SOURCE duplicate — they cannot drift).
    func testMaskBlurCoeffsMatchIOPGaussianBlur() {
        var compared = 0
        for sigma in [0.5, 1.0, 2.5, 4.0, 8.0, 16.0, 40.0] {
            let core = MaskCombiner.maskGaussCoeffs(sigma: Float(sigma))
            let iop = GaussianBlur.coeffs(sigma: Float(sigma))
            for (a, b) in [
                (core.a0, iop.a0), (core.a1, iop.a1), (core.a2, iop.a2), (core.a3, iop.a3),
                (core.b1, iop.b1), (core.b2, iop.b2),
                (core.coefp, iop.coefp), (core.coefn, iop.coefn),
            ] {
                XCTAssertEqual(a, b, accuracy: 1e-6, "sigma \(sigma) coeff drift")
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")
    }

    /// The float64 Deriche recursion (the MSL float1 recursion in Double,
    /// cols-then-rows, forward store + backward accumulate, [0,1] clamp).
    private func referenceBlur(
        _ mask: [Float], width: Int, height: Int, coeffs: GaussianMaskCoeffs
    ) -> [Float] {
        let a0 = Double(coeffs.a0), a1 = Double(coeffs.a1)
        let a2 = Double(coeffs.a2), a3 = Double(coeffs.a3)
        let b1 = Double(coeffs.b1), b2 = Double(coeffs.b2)
        let coefp = Double(coeffs.coefp), coefn = Double(coeffs.coefn)
        let clamp01 = { (v: Double) -> Double in min(max(v, 0.0), 1.0) }
        var colPlane = [Double](repeating: 0, count: width * height)
        // columns
        for x in 0..<width {
            var xp = clamp01(Double(mask[x])), yb = xp * coefp, yp = yb
            for y in 0..<height {
                let xc = clamp01(Double(mask[y * width + x]))
                let yc = a0 * xc + a1 * xp - b1 * yp - b2 * yb
                xp = xc; yb = yp; yp = yc
                colPlane[y * width + x] = yc
            }
            var xn = clamp01(Double(mask[(height - 1) * width + x])), xa = xn
            var yn = xn * coefn, ya = yn
            for k in 0..<height {
                let y = height - 1 - k
                let xc = clamp01(Double(mask[y * width + x]))
                let yc = a2 * xn + a3 * xa - b1 * yn - b2 * ya
                xa = xn; xn = xc; ya = yn; yn = yc
                colPlane[y * width + x] += yc
            }
        }
        // rows
        var out = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            let base = y * width
            var xp = clamp01(colPlane[base]), yb = xp * coefp, yp = yb
            for x in 0..<width {
                let xc = clamp01(colPlane[base + x])
                let yc = a0 * xc + a1 * xp - b1 * yp - b2 * yb
                xp = xc; yb = yp; yp = yc
                out[base + x] = yc
            }
            var xn = clamp01(colPlane[base + width - 1]), xa = xn
            var yn = xn * coefn, ya = yn
            for k in 0..<width {
                let x = width - 1 - k
                let xc = clamp01(colPlane[base + x])
                let yc = a2 * xn + a3 * xa - b1 * yn - b2 * ya
                xa = xn; xn = xc; ya = yn; yn = yc
                out[base + x] += yc
            }
        }
        return out.map(Float.init)
    }

    /// GPU mask blur vs the float64 recursion <1e-6 + sigma-0 identity.
    func testMaskBlurParityFloat64Recursion() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 40, h = 28
        let source = try makeR32(w, h, metal: metal) { x, y in
            // a step edge + a soft blob + HDR clamp probes
            let edge: Float = x < w / 2 ? 0.1 : 0.9
            let blob = 0.7 * exp(-pow(Float(x - 28), 2) / 40 - pow(Float(y - 8), 2) / 18)
            return min(edge + blob, 1.2) // >1 exercises the [0,1] clamp
        }
        for sigma: Float in [1.5, 4.0, 12.0] {
            let blurred = try await MaskCombiner.blur(
                mask: source, sigma: sigma, metal: metal)
            let got = readMask(blurred, metal: metal)
            let ref = referenceBlur(
                readMask(source, metal: metal), width: w, height: h,
                coeffs: MaskCombiner.maskGaussCoeffs(sigma: sigma))
            var compared = 0
            var maxAbs: Float = 0
            var violations = 0
            for i in 0..<ref.count {
                let diff = abs(got[i] - ref[i])
                if diff >= 1e-6 { violations += 1 }
                maxAbs = max(maxAbs, diff)
                compared += 1
            }
            XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")
            XCTAssertEqual(
                violations, 0,
                "sigma \(sigma): \(violations)/\(compared) violate <1e-6 (maxAbs \(maxAbs))")
        }
    }

    /// The tone-curve post op vs the float64 reference <1e-6 (both
    /// brightness branches + the epsilon gates).
    func testMaskToneCurveParity() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 32, h = 16
        let gopacity: Float = 0.8
        for (contrast, brightness) in [(0.4 as Float, 0.0 as Float), (0.0, 0.3), (0.0, -0.3), (-0.6, 0.15)] {
            let source = try makeR32(w, h, metal: metal) { x, y in
                // sweep 0..1 (beyond gopacity included — dt divides it out)
                Float(x * 7 + y) / Float(w * 7 + h) * 1.1
            }
            let curved = try await MaskCombiner.toneCurve(
                mask: source, contrast: contrast, brightness: brightness,
                gopacity: gopacity, metal: metal)
            let got = readMask(curved, metal: metal)
            let e = Foundation.exp(3.0 * Double(contrast))
            var compared = 0
            var maxAbs: Float = 0
            var violations = 0
            for y in 0..<h {
                for x in 0..<w {
                    let input = Double(readMask(source, metal: metal)[y * w + x])
                    let ref = ParametricReference.toneCurve(
                        input, e: e, brightness: Double(brightness),
                        gopacity: Double(gopacity))
                    let diff = abs(got[y * w + x] - Float(ref))
                    if diff >= 1e-6 { violations += 1 }
                    maxAbs = max(maxAbs, diff)
                    compared += 1
                }
            }
            XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")
            XCTAssertEqual(
                violations, 0,
                "contrast \(contrast) brightness \(brightness): " +
                    "\(violations)/\(compared) violate <1e-6 (maxAbs \(maxAbs))")
        }
    }

    /// The chain ORDER is pinned: postProcess output == the manual
    /// [blur → feather → tone curve] application; and the reversed
    /// [feather → blur] genuinely differs (the order-sensitivity probe —
    /// if the two orders agreed, the pin would be vacuous).
    func testPostChainOrderPinned() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 32, h = 24
        let source = try makeR32(w, h, metal: metal) { x, y in
            (x < w / 2) == (y < h / 2) ? 0.95 : 0.05
        }
        let blurR: Float = 3.0, featherR: Float = 2.0
        let contrast: Float = 0.4, brightness: Float = 0.1, gopacity: Float = 0.9

        // The pinned chain.
        let chained = try await MaskCombiner.postProcess(
            mask: source, blurRadius: blurR, featherRadius: featherR,
            contrast: contrast, brightness: brightness, gopacity: gopacity,
            metal: metal)

        // Manual reference: blur → feather → tone curve.
        let manual = try await MaskCombiner.blur(mask: source, sigma: blurR, metal: metal)
        let manual2 = try await MaskCombiner.blur(mask: manual, sigma: featherR, metal: metal)
        let manual3 = try await MaskCombiner.toneCurve(
            mask: manual2, contrast: contrast, brightness: brightness,
            gopacity: gopacity, metal: metal)

        let gotChain = readMask(chained, metal: metal)
        let gotManual = readMask(manual3, metal: metal)
        var compared = 0
        for i in 0..<gotChain.count {
            XCTAssertEqual(
                gotChain[i], gotManual[i], accuracy: 1e-6,
                "chain order deviates from the pinned blur→feather→curve at \(i)")
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")

        // Order sensitivity: feather→blur (both blurs, reversed) must
        // genuinely differ somewhere — the pin is not vacuous.
        let reversed = try await MaskCombiner.blur(mask: source, sigma: featherR, metal: metal)
        let reversed2 = try await MaskCombiner.blur(mask: reversed, sigma: blurR, metal: metal)
        let gotReversed = readMask(reversed2, metal: metal)
        let maxDiff = zip(gotChain, gotReversed).map { abs($0 - $1) }.max() ?? 0
        XCTAssertGreaterThan(
            maxDiff, 1e-4,
            "blur/feather order produced identical output — the pin is vacuous")
    }

    // MARK: - T1 legacy tail (packing pins)

    /// Boost = exp2 scaling, slopes = 1/max(0.001, span), open ends at 0/1,
    /// inactive slots full-range.
    func testProcessParametersPacking() {
        let spec = ParametricMask(
            domain: .jzczhz,
            channels: [
                .init(channel: 8, curve: .init(points: [0.5, 0.5, 0.5, 0.5], boost: 2.0)),
                .init(channel: 0, curve: .init(points: [0.0, 0.0, 1.0, 1.0])),
                .init(channel: 9, curve: .init(points: [0.1, 0.1, 0.2, 0.2])),
            ])
        let p = spec.packedParameters()
        // boost: slot 8 points scale by exp2(2) = 4.
        XCTAssertEqual(p[8 * 6 + 0], 2.0, accuracy: 1e-6)
        // slope up = 1/max(0.001, p1'−p0') — equal points → 1/0.001 floor.
        XCTAssertEqual(p[8 * 6 + 4], 1.0 / 0.001, accuracy: 1e-4)
        // open low end: slot 1 both lower points at 0 → −FLT_MAX.
        XCTAssertEqual(p[1 * 6 + 0], -Float.greatestFiniteMagnitude)
        XCTAssertEqual(p[1 * 6 + 1], -Float.greatestFiniteMagnitude)
        // open high end: slot 1 both upper points at 1 → FLT_MAX.
        XCTAssertEqual(p[1 * 6 + 2], Float.greatestFiniteMagnitude)
        XCTAssertEqual(p[1 * 6 + 3], Float.greatestFiniteMagnitude)
        // inactive slot 10: full-range pass-through bounds + zero slopes.
        XCTAssertEqual(p[10 * 6 + 0], -Float.greatestFiniteMagnitude)
        XCTAssertEqual(p[10 * 6 + 2], Float.greatestFiniteMagnitude)
        XCTAssertEqual(p[10 * 6 + 4], 0)
        XCTAssertEqual(p[10 * 6 + 5], 0)
        // the bitmask: enabled slot 8 + 0 + 9; no inverted bits.
        XCTAssertEqual(spec.channelBitmask() & 0xFFFF, (1 << 8) | (1 << 0) | (1 << 9))
        XCTAssertEqual(spec.channelBitmask() >> 16, 0)
        // inverted curve sets the high-bit mask.
        let inv = ParametricMask(
            domain: .luma,
            channels: [.init(channel: 0, curve: .init(points: [0.1, 0.2, 0.3, 0.4], inverted: true))])
        XCTAssertEqual(inv.channelBitmask() >> 16, 1)
    }
}

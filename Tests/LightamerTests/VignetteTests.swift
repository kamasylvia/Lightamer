@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

/// VignetteTests (Plan 08-2 T1) — IOP-FX-01 (vignette 68.0).
///
/// GOLDEN AUTHORITY: `VignetteReference` — the CPU float64 twin of
/// `vignette_apply` (`extended.cl:308-349` OpenCL form + the module's
/// float64 `uniformSetup`, vignette.c:719-786). The kernel is compared at
/// 1e-6 ABSOLUTE (the plan's falloff-curve tolerance): at the default
/// shape 1 the pow legs are exact squares, the cosine smoothing is
/// contractive, and the |brightness|/|saturation| ≤ 1 domain keeps the
/// accumulated float32 narrowing + rounding under 1e-6.
///
/// ANTI-VACUUM (L020): every comparison runs over real pixels with a
/// compared>0 gate. L014: every GPU readback drains first.
final class VignetteTests: XCTestCase {

    private static let tol = Float(1e-6)

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: VignetteKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    private func makeTexture(
        _ metal: MetalContext, width: Int, height: Int
    ) -> (any MTLTexture) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        return metal.device.makeTexture(descriptor: descriptor)!
    }

    private func gradientImage(width: Int, height: Int) -> [Float] {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for j in 0..<height {
            for i in 0..<width {
                let k = (j * width + i) * 4
                pixels[k] = Float(i) / Float(max(width - 1, 1)) * 0.8 + 0.1
                pixels[k + 1] = Float(j) / Float(max(height - 1, 1)) * 0.6 + 0.2
                pixels[k + 2] = 0.15 + Float((i + j) % 7) / 7.0 * 0.5
                pixels[k + 3] = 1.0
            }
        }
        return pixels
    }

    private func fill(
        _ texture: any MTLTexture, _ pixels: [Float]
    ) {
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0, withBytes: $0.baseAddress!,
                bytesPerRow: texture.width * 16)
        }
    }

    private func read(_ texture: any MTLTexture) -> [Float] {
        var pixels = [Float](repeating: 0, count: texture.width * texture.height * 4)
        pixels.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        return pixels
    }

    @discardableResult
    private func runVignette(
        _ params: VignetteModule.Params, input: [Float],
        width: Int, height: Int, metal: MetalContext
    ) async throws -> [Float] {
        let module = VignetteModule()
        var piece = IOPiece()
        piece.dscIn = IOPBufferDesc(width: width, height: height)
        piece.dscOut = piece.dscIn
        piece.iscale = 1.0
        module.commitParams(params, into: &piece)
        let inTexture = makeTexture(metal, width: width, height: height)
        let outTexture = makeTexture(metal, width: width, height: height)
        fill(inTexture, input)
        let roi = ROI(x: 0, y: 0, width: width, height: height, scale: 1.0)
        try await module.process(
            input: inTexture, output: outTexture, roiIn: roi, roiOut: roi,
            piece: &piece, metal: metal)
        await drain(metal) // L014
        return read(outTexture)
    }

    // MARK: - float64 falloff-curve parity (the plan's 1e-6 golden)

    func testFalloffCurveFloat64Parity() async throws {
        let metal = try await makeMetal()
        let width = 64, height = 48
        let params = VignetteModule.Params() // dt defaults: brightness/saturation −0.5
        let input = gradientImage(width: width, height: height)
        let output = try await runVignette(
            params, input: input, width: width, height: height, metal: metal)

        // The float64 authority: the SAME uniformSetup feeds both legs.
        let setup = VignetteModule.uniformSetup(
            params, bufW: Double(width), bufH: Double(height),
            roiIn: ROI(x: 0, y: 0, width: width, height: height, scale: 1.0),
            roiOut: ROI(x: 0, y: 0, width: width, height: height, scale: 1.0))
        var compared = 0
        var maxDiff: Float = 0
        var failures: [String] = []
        for j in 0..<height {
            for i in 0..<width {
                let k = (j * width + i) * 4
                let rgb = SIMD3<Double>(
                    Double(input[k]), Double(input[k + 1]), Double(input[k + 2]))
                let expected = VignetteReference.pixel(
                    rgb, x: Double(i), y: Double(j), u: setup)
                for c in 0..<3 {
                    let got = output[k + c]
                    let want = Float(expected[c])
                    let diff = abs(got - want)
                    maxDiff = max(maxDiff, diff)
                    compared += 1
                    if diff > Self.tol, failures.count < 8 {
                        failures.append(
                            "(\(i),\(j)) ch\(c): kernel=\(got) ref=\(want) diff=\(diff)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(compared, 0, "parity must compare real pixels (anti-vacuum)")
        XCTAssertTrue(
            failures.isEmpty,
            "falloff float64 parity exceeded \(Self.tol) (max \(maxDiff)):\n"
                + failures.joined(separator: "\n"))
    }

    /// Analytic anchors ON TOP of the reference parity: the exact image
    /// center sits at cplen 0 < dscale (weight 0 → verbatim pixel) and the
    /// far corner is fully outside the falloff (weight 1 → px·0.5 at the
    /// dt-default brightness −0.5, saturation −0.5 → gray 0.5·0.5+…).
    func testFalloffAnalyticAnchors() async throws {
        let metal = try await makeMetal()
        let width = 64, height = 48
        let params = VignetteModule.Params()
        let input = gradientImage(width: width, height: height)
        let output = try await runVignette(
            params, input: input, width: width, height: height, metal: metal)

        // Center (32, 24): weight 0 → untouched.
        let c = (24 * width + 32) * 4
        for offset in 0..<3 {
            XCTAssertEqual(
                output[c + offset], input[c + offset], accuracy: Self.tol,
                "center pixel must be untouched (weight 0)")
        }
        // Corner (0, 0): the hand-spelled closed form (independent of
        // VignetteReference): xscale = yscale = 2/max(64,48) = 2/64
        // (whratio 1), roi_center_scaled = (1.0, 0.75) → pv = (1.0, 0.75);
        // shape 1 → cplen = √(1² + 0.75²) = 1.25; dscale 0.8 / fscale 0.5
        // → wRaw = 0.9, weight = 0.5 − cos(π·0.9)/2 — NOT the full weight
        // (the default falloff radius extends past the corner diagonal).
        let pvx = 1.0, pvy = 0.75
        let cplen = (pow(pvx, 2.0) + pow(pvy, 2.0)).squareRoot()
        XCTAssertEqual(cplen, 1.25, accuracy: 1e-12)
        let wRaw = (cplen - 0.8) / 0.5
        XCTAssertEqual(wRaw, 0.9, accuracy: 1e-12)
        let weight = 0.5 - cos(Double.pi * wRaw) / 2.0
        let corner = SIMD3<Double>(
            Double(input[0]), Double(input[1]), Double(input[2]))
        var expected = corner * (1.0 + weight * (-0.5)) // brightness × leg
        let mv = (expected.x + expected.y + expected.z) / 3.0
        let wss = weight * (-0.5)
        expected = expected - (SIMD3<Double>(repeating: mv) - expected) * wss
        for offset in 0..<3 {
            XCTAssertEqual(
                output[offset], Float(expected[offset]), accuracy: 4 * Self.tol,
                "corner anchor ch\(offset)")
        }
    }

    // MARK: - brightness ± branch fork

    func testBrightnessBranchesDiverge() async throws {
        let metal = try await makeMetal()
        let width = 32, height = 32
        let input = gradientImage(width: width, height: height)
        var positive = VignetteModule.Params()
        positive.brightness = 0.4
        positive.saturation = 0 // isolate the brightness leg
        var negative = positive
        negative.brightness = -0.4

        let plus = try await runVignette(
            positive, input: input, width: width, height: height, metal: metal)
        let minus = try await runVignette(
            negative, input: input, width: width, height: height, metal: metal)

        // Corner: weight 1 — additive +0.4 vs multiplicative ×0.6, spelled
        // out against the ORIGINAL pixel (saturation 0 → untouched).
        var compared = 0
        for offset in 0..<3 {
            let original = input[offset]
            XCTAssertEqual(plus[offset], original + 0.4, accuracy: 4 * Self.tol)
            XCTAssertEqual(minus[offset], original * 0.6, accuracy: 4 * Self.tol)
            XCTAssertGreaterThan(plus[offset], minus[offset])
            compared += 1
        }
        // Mid-falloff pixel: the branches must DIVERGE (not sign-flips of
        // one number) — additive rises, multiplicative falls.
        let mid = (16 * width + 16) * 4
        let setup = VignetteModule.uniformSetup(
            positive, bufW: Double(width), bufH: Double(height),
            roiIn: ROI(x: 0, y: 0, width: width, height: height, scale: 1.0),
            roiOut: ROI(x: 0, y: 0, width: width, height: height, scale: 1.0))
        let midPixel = SIMD3<Double>(
            Double(input[mid]), Double(input[mid + 1]), Double(input[mid + 2]))
        let midExpectedPlus = VignetteReference.pixel(
            midPixel, x: 16, y: 16, u: setup)
        var negativeSetup = setup
        negativeSetup.brightness = -0.4
        let midExpectedMinus = VignetteReference.pixel(
            midPixel, x: 16, y: 16, u: negativeSetup)
        for offset in 0..<3 {
            XCTAssertEqual(plus[mid + offset], Float(midExpectedPlus[offset]), accuracy: 4 * Self.tol)
            XCTAssertEqual(minus[mid + offset], Float(midExpectedMinus[offset]), accuracy: 4 * Self.tol)
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0, "anti-vacuum")
    }

    // MARK: - unbound clipping semantics

    func testUnboundClippingSemantics() async throws {
        let metal = try await makeMetal()
        let width = 32, height = 32
        let input = gradientImage(width: width, height: height)
        var unbound = VignetteModule.Params()
        unbound.brightness = 1.0 // weight 1 corner: +1.0 additive
        unbound.saturation = 0
        var bound = unbound
        bound.unbound = false

        let free = try await runVignette(
            unbound, input: input, width: width, height: height, metal: metal)
        let clipped = try await runVignette(
            bound, input: input, width: width, height: height, metal: metal)

        // Corner (weight 1): 0.9-ish input + 1.0 → HDR-side output (>1.0,
        // NO clamp — the scene-referred pass-through); unbound=false pins
        // the value at exactly 1.0.
        for offset in 0..<3 {
            let original = input[offset]
            XCTAssertGreaterThan(
                free[offset], 1.0,
                "unbound must NOT clamp (got \(free[offset]))")
            XCTAssertEqual(free[offset], original + 1.0, accuracy: 4 * Self.tol)
            XCTAssertEqual(clipped[offset], 1.0, accuracy: 4 * Self.tol)
        }
    }

    // MARK: - neutral routed-blit byte identity (L031 fast path)

    func testNeutralBlitByteIdentity() async throws {
        let metal = try await makeMetal()
        let width = 24, height = 16
        var input = gradientImage(width: width, height: height)
        // Include a value that the compute path would perturb at −0.0
        // semantics; the blit must be BYTE-identical regardless.
        input[0] = -0.0
        var params = VignetteModule.Params()
        params.scale = 137 // non-default geometry — the value identity is
        params.falloffScale = 91 // PARAM-based, not geometry-based
        params.brightness = 0
        params.saturation = 0

        let module = VignetteModule()
        XCTAssertTrue(
            module.isNeutral(params),
            "brightness 0 + saturation 0 is the neutral contract")
        var piece = IOPiece()
        piece.dscIn = IOPBufferDesc(width: width, height: height)
        piece.dscOut = piece.dscIn
        piece.iscale = 1.0
        module.commitParams(params, into: &piece)
        let inTexture = makeTexture(metal, width: width, height: height)
        let outTexture = makeTexture(metal, width: width, height: height)
        fill(inTexture, input)
        let roi = ROI(x: 0, y: 0, width: width, height: height, scale: 1.0)
        try await module.process(
            input: inTexture, output: outTexture, roiIn: roi, roiOut: roi,
            piece: &piece, metal: metal)
        await drain(metal)
        let output = read(outTexture)
        XCTAssertEqual(input.count, output.count)
        for i in 0..<input.count {
            XCTAssertEqual(
                output[i].bitPattern, input[i].bitPattern,
                "byte identity broken at \(i): \(output[i]) ≠ \(input[i])")
        }
    }

    // MARK: - registration + layer eligibility

    func testRegistrationAndLayerEligibility() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let made = await registry.makeBox(opName: VignetteModule.opName)
        XCTAssertNotNil(made, "vignette must register")
        XCTAssertEqual(VignetteModule.iopOrder, 68.0)
        // The V50 table slot pre-exists (zero rows inserted).
        let slot = V50Order.entries.first { $0.opName == "vignette" }
        XCTAssertEqual(slot?.order, 68.0, "the v50 slot is the pre-existing 68.0 row")
        // Layer-mask eligibility: strictly below the terminal tail floor.
        XCTAssertLessThan(
            VignetteModule.iopOrder, LayerCompositeDriver.terminalTailFloor)
    }
}

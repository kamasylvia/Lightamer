@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

/// BloomTests (Plan 08-2 T3) — IOP-FX-03 (bloom 61.0).
///
/// GOLDEN AUTHORITY: `BloomReference` — the CPU float64 twin of the whole
/// three-stage chain (threshold + cascade + screen; 12-5 遗留#5
/// double-write doctrine). Cross-implementation comparison at 1e-5
/// ABSOLUTE (the chain stacks box + two gaussian passes + bilinear + a
/// screen blend; the float32 accumulation floor is ~1e-5 — D-08-2-B5).
///
/// ANTI-VACUUM (L020): every comparison runs over real pixels with a
/// compared>0 gate. L014: every GPU readback drains first.
final class BloomTests: XCTestCase {

    private static let tol = Float(1e-5)

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: BloomKernel.metalBundle)
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

    private func fill(_ texture: any MTLTexture, _ pixels: [Float]) {
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

    /// A gradient + a few HDR hot pixels — real structure for the cascade
    /// and the bilinear upsample to chew on.
    private func sceneImage(width: Int, height: Int) -> [Float] {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for j in 0..<height {
            for i in 0..<width {
                let k = (j * width + i) * 4
                pixels[k] = Float(i) / Float(max(width - 1, 1)) * 0.9 + 0.05
                pixels[k + 1] = Float(j) / Float(max(height - 1, 1)) * 0.5 + 0.1
                pixels[k + 2] = 0.1 + Float((i * j) % 5) / 5.0 * 0.4
                pixels[k + 3] = 1.0
            }
        }
        // Three HDR highlight sources (above the white anchor: luma > 4).
        for (x, y, v) in [(width / 2, height / 2, 12.0), (8, 8, 6.0), (width - 4, height - 3, 9.0)] {
            let k = (y * width + x) * 4
            pixels[k] = Float(v); pixels[k + 1] = Float(v); pixels[k + 2] = Float(v)
        }
        return pixels
    }

    @discardableResult
    private func runBloom(
        _ params: BloomModule.Params, input: [Float],
        width: Int, height: Int, metal: MetalContext
    ) async throws -> [Float] {
        let module = BloomModule()
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

    // MARK: - float64 whole-chain parity (the golden)

    func testFloat64ChainParityDefaults() async throws {
        let metal = try await makeMetal()
        let width = 96, height = 64
        let params = BloomModule.Params() // dt defaults 20/90/25
        let input = sceneImage(width: width, height: height)
        let output = try await runBloom(
            params, input: input, width: width, height: height, metal: metal)

        let geometry = BloomModule.geometry(params, roiScale: 1.0, iscale: 1.0)
        let expected = BloomReference.chain(
            input, width: width, height: height, geometry: geometry)
        var compared = 0
        var maxDiff: Float = 0
        var failures: [String] = []
        for k in stride(from: 0, to: input.count, by: 4) {
            for c in 0..<4 {
                let got = output[k + c]
                let want = Float(expected[k + c])
                let diff = abs(got - want)
                maxDiff = max(maxDiff, diff)
                compared += 1
                if diff > Self.tol, failures.count < 8 {
                    failures.append(
                        "px\(k / 4) ch\(c): kernel=\(got) ref=\(want) diff=\(diff)")
                }
            }
        }
        XCTAssertGreaterThan(compared, 0, "parity must compare real pixels (anti-vacuum)")
        XCTAssertTrue(
            failures.isEmpty,
            "float64 chain parity exceeded \(Self.tol) (max \(maxDiff)):\n"
                + failures.joined(separator: "\n"))
    }

    // MARK: - the threshold linear-mapping numeric anchor (research §9.2)

    func testThresholdLinearMappingAnchor() async throws {
        let metal = try await makeMetal()
        let width = 64, height = 48

        // thr_lin = (90/100)³ = 0.729 EXACTLY (the §9.2 anchor).
        let geometry = BloomModule.geometry(
            BloomModule.Params(threshold: 90), roiScale: 1.0, iscale: 1.0)
        XCTAssertEqual(geometry.thrLin, 0.729, accuracy: 1e-12)

        // LDR plateau (luma 1.0): L_lin = 1.0/4 · scale(25) ≈ 0.2996 —
        // BELOW 0.729 → zero glow → the screen blend is the identity up
        // to one float rounding (1−(1−a)·1). The whole image passes
        // through untouched (no bloom from mid-gray).
        let params = BloomModule.Params() // 20/90/25
        var flat = [Float](repeating: 0, count: width * height * 4)
        for k in stride(from: 0, to: flat.count, by: 4) {
            flat[k] = 1.0; flat[k + 1] = 1.0; flat[k + 2] = 1.0; flat[k + 3] = 1.0
        }
        let output = try await runBloom(
            params, input: flat, width: width, height: height, metal: metal)
        var compared = 0
        for k in stride(from: 0, to: flat.count, by: 4) {
            for c in 0..<3 {
                XCTAssertEqual(output[k + c], flat[k + c], accuracy: 2 * Self.tol)
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "anti-vacuum")

        // The brighten form is dt's :144 EXPONENT: scale(25) = 2^0.26.
        XCTAssertEqual(
            geometry.scale, Foundation.pow(2.0, 26.0 / 100.0), accuracy: 1e-12)
    }

    // MARK: - the point-light halo radius + amplitude

    func testPointLightHaloRadiusAndAmplitude() async throws {
        let metal = try await makeMetal()
        let width = 128, height = 64
        var black = [Float](repeating: 0, count: width * height * 4)
        for k in stride(from: 3, to: black.count, by: 4) { black[k] = 1.0 }
        // One HDR point source at the center (luma 12 → L_lin ≈ 3.0·scale).
        let cx = width / 2, cy = height / 2
        let ck = (cy * width + cx) * 4
        black[ck] = 12.0; black[ck + 1] = 12.0; black[ck + 2] = 12.0

        let params = BloomModule.Params(size: 20, threshold: 0, strength: 25)
        let output = try await runBloom(
            params, input: black, width: width, height: height, metal: metal)

        let geometry = BloomModule.geometry(params, roiScale: 1.0, iscale: 1.0)
        // AMPLITUDE: the source pixel itself screens with the local glow —
        // the glow NEVER exceeds the thresholded peak (the gaussian/box
        // cascade cannot amplify), and the source output follows the
        // float64 screen formula (not a clamp).
        let refChain = BloomReference.chain(
            black, width: width, height: height, geometry: geometry)
        for c in 0..<3 {
            XCTAssertEqual(
                output[ck + c], Float(refChain[ck + c]), accuracy: 2 * Self.tol,
                "source pixel ch\(c)")
        }
        // A neighbor 4 px away glows > 0 (the halo EXISTS — anti-vacuum).
        let nk = (cy * width + cx + 4) * 4
        XCTAssertGreaterThan(output[nk], 0.01, "the halo must exist near the source")

        // RADIUS: the source's small cell ± gaussRadiusSmall cells is the
        // FIR support; the bilinear upsample adds ONE more cell and the
        // cell itself spans 8 full px — beyond (gaussRadiusSmall + 2)
        // small cells the glow is EXACTLY zero and the pixels stay
        // byte-near black.
        let reach = (geometry.gaussRadiusSmall + 2) * 8 + 1
        let fx = min(cx + reach, width - 1)
        let fk = (cy * width + fx) * 4
        for c in 0..<3 {
            XCTAssertEqual(
                output[fk + c], 0.0, accuracy: 1e-6,
                "glow must not reach \(reach) px (ch\(c))")
        }
    }

    // MARK: - HDR >1.0 zero special-casing (research §9.4)

    func testHDRAboveOneRidesThroughNoClamp() async throws {
        let metal = try await makeMetal()
        let width = 48, height = 32
        // A uniform HDR plate (luma 2.0) with threshold 0 → the whole
        // plane blooms (a CONSTANT glow) — the screen blend evaluates on
        // a > 1 operand and must return the FORMULA value, not clamp.
        var hdr = [Float](repeating: 0, count: width * height * 4)
        for k in stride(from: 0, to: hdr.count, by: 4) {
            hdr[k] = 2.0; hdr[k + 1] = 2.0; hdr[k + 2] = 2.0; hdr[k + 3] = 1.0
        }
        let params = BloomModule.Params(size: 20, threshold: 0, strength: 0)
        let output = try await runBloom(
            params, input: hdr, width: width, height: height, metal: metal)

        let geometry = BloomModule.geometry(params, roiScale: 1.0, iscale: 1.0)
        // The analytic HDR answer: constant field → glow c = 2/4·scale;
        // screen = 1 − (1−2)(1−c) = 1 + (1−c) — for strength 0 the glow
        // rides through UNCLAMPED and stays ≠ 1.0.
        let c = 2.0 / 4.0 * geometry.scale
        let expected = 1.0 + (1.0 - c)
        var compared = 0
        for k in stride(from: 0, to: hdr.count - 3, by: 4) {
            for ch in 0..<3 {
                XCTAssertEqual(
                    output[k + ch], Float(expected), accuracy: 2 * Self.tol,
                    "HDR screen must follow the formula (got \(output[k + ch]))")
                XCTAssertNotEqual(output[k + ch], 1.0, "no clamp to 1.0")
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "anti-vacuum")
    }

    // MARK: - the cascade intermediate (the 1/8 plane exists → shape)

    func testCascadeGeometryAndIntermediateResolutions() async throws {
        // The geometry chain: dt :140-142 radius + the D-08-2-B1 σ legs.
        let small = BloomReference.smallSize(fullW: 100, fullH: 50)
        XCTAssertEqual(small.w, 13, "ceil(100/8)")
        XCTAssertEqual(small.h, 7, "ceil(50/8)")

        // size 0 → rad 2.56; size 100 → rad 256 (the dt :140 span).
        let lo = BloomModule.geometry(
            BloomModule.Params(size: 0), roiScale: 1.0, iscale: 1.0)
        let hi = BloomModule.geometry(
            BloomModule.Params(size: 100), roiScale: 1.0, iscale: 1.0)
        XCTAssertLessThan(lo.sigmaSmall, hi.sigmaSmall)
        XCTAssertLessThanOrEqual(hi.gaussRadiusSmall, 20, "the 1/8 lattice caps the work")

        // A nonzero run leaves the cached scratch at the 1/8 geometry —
        // the cascade INTERMEDIATE exists with the expected shape.
        let metal = try await makeMetal()
        let width = 100, height = 50
        let input = sceneImage(width: width, height: height)
        let module = BloomModule()
        var piece = IOPiece()
        piece.dscIn = IOPBufferDesc(width: width, height: height)
        piece.dscOut = piece.dscIn
        piece.iscale = 1.0
        module.commitParams(BloomModule.Params(), into: &piece)
        let inTexture = makeTexture(metal, width: width, height: height)
        let outTexture = makeTexture(metal, width: width, height: height)
        fill(inTexture, input)
        let roi = ROI(x: 0, y: 0, width: width, height: height, scale: 1.0)
        try await module.process(
            input: inTexture, output: outTexture, roiIn: roi, roiOut: roi,
            piece: &piece, metal: metal)
        await drain(metal)
        XCTAssertNotNil(module.thresholdTextureForTesting, "threshold plane cached")
        XCTAssertEqual(module.smallTextureForTesting?.width, small.w)
        XCTAssertEqual(module.smallTextureForTesting?.height, small.h)
    }

    // MARK: - registration + layer eligibility

    func testRegistrationAndLayerEligibility() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let made = await registry.makeBox(opName: BloomModule.opName)
        XCTAssertNotNil(made, "bloom must register")
        XCTAssertEqual(BloomModule.iopOrder, 61.0)
        // The V50 table slot pre-exists (zero rows inserted).
        let slot = V50Order.entries.first { $0.opName == "bloom" }
        XCTAssertEqual(slot?.order, 61.0, "the v50 slot is the pre-existing 61.0 row")
        // Layer-mask eligibility: strictly below the terminal tail floor.
        XCTAssertLessThan(
            BloomModule.iopOrder, LayerCompositeDriver.terminalTailFloor)
    }
}

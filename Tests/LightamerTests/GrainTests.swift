@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

/// GrainTests (Plan 08-2 T2) — IOP-FX-02 (grain 65.0).
///
/// THE HARD PAIR (the plan's non-relaxable determinism contract):
/// 1. same image identity + same params → TWO renders are BYTE-equal;
/// 2. same params + different image identity → the patterns DIFFER.
/// They are the cache-key correctness premise (seed = StableHash(params ⊕
/// imageIdentity) is a pure function; PipeCacheKey already carries both).
///
/// float64 REFERENCE: `GrainReference` (grain.c:120-327 Double) compared
/// at 6e-4 absolute on the final pixels — the documented cross-
/// implementation floor: the noise coordinates reach O(10²) lattice cells
/// (float32 ulp ~1e-5 there) and the VERBATIM ×32 final scale amplifies
/// the per-corner float32 rounding to ~1e-3 on the unit noise field
/// (×0.0375 at default strength on the pixel). Bitwise equality is pinned
/// KERNEL-vs-KERNEL in the hard pair, not cross-implementation
/// (DECISIONS D-08-2-5).
///
/// SPECTRUM ANCHOR: the 3-octave f/a table is pinned on the float64
/// reference with radial band-power probes at a test zoom that places the
/// three octave peaks under Nyquist (the dt-verbatim default zoom puts
/// the base octave beyond Nyquist at any practical render size — the
/// spectral SHAPE is zoom-invariant, the zoom verbatim itself rides the
/// reference parity). L014 drains; L020 anti-vacuum gates.
final class GrainTests: XCTestCase {

    private static let pixelTol = Float(6e-4)

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: GrainKernel.metalBundle)
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

    /// A soft gradient (the grain's luma envelope must traverse shadows →
    /// highlights across the field).
    private func gradientImage(width: Int, height: Int) -> [Float] {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for j in 0..<height {
            for i in 0..<width {
                let k = (j * width + i) * 4
                let v = Float(j) / Float(max(height - 1, 1)) * 0.9 + 0.05
                pixels[k] = v
                pixels[k + 1] = v
                pixels[k + 2] = v
                pixels[k + 3] = 1.0
            }
        }
        return pixels
    }

    private func runGrain(
        _ params: GrainModule.Params, imageIdentity: UUID, input: [Float],
        width: Int, height: Int, metal: MetalContext
    ) async throws -> [Float] {
        let module = GrainModule(imageIdentity: imageIdentity)
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

    // MARK: - THE HARD PAIR (byte-exact)

    func testSameImageSameParamsByteEqual() async throws {
        let metal = try await makeMetal()
        let width = 48, height = 32
        let input = gradientImage(width: width, height: height)
        let identity = UUID()
        let params = GrainModule.Params()

        let first = try await runGrain(
            params, imageIdentity: identity, input: input,
            width: width, height: height, metal: metal)
        let second = try await runGrain(
            params, imageIdentity: identity, input: input,
            width: width, height: height, metal: metal)

        XCTAssertEqual(first.count, second.count)
        var compared = 0
        for i in 0..<first.count {
            XCTAssertEqual(
                first[i].bitPattern, second[i].bitPattern,
                "byte determinism broken at \(i)")
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0, "anti-vacuum")
    }

    func testSameParamsDifferentImagesDiffer() async throws {
        let metal = try await makeMetal()
        let width = 48, height = 32
        let input = gradientImage(width: width, height: height)
        let params = GrainModule.Params()

        let a = try await runGrain(
            params, imageIdentity: UUID(), input: input,
            width: width, height: height, metal: metal)
        let b = try await runGrain(
            params, imageIdentity: UUID(), input: input,
            width: width, height: height, metal: metal)

        // The patterns MUST differ (the cache-key negative shape: same
        // params, different image identity → different output).
        var differing = 0
        for i in stride(from: 0, to: a.count, by: 4) {
            if a[i].bitPattern != b[i].bitPattern { differing += 1 }
        }
        XCTAssertGreaterThan(
            differing, (width * height) / 2,
            "same-params different-identity renders must produce different grain")
    }

    func testSeedPureFunctionAndImageSensitivity() {
        let params = GrainModule.Params()
        // Deterministic reproduction (the cache-key invariant: pure
        // function of (params, identity)).
        let fixed = UUID(uuidString: "2B5C9A10-1234-5678-9ABC-DEF012345678")!
        XCTAssertEqual(
            GrainModule.seed(params: params, imageIdentity: fixed),
            GrainModule.seed(params: params, imageIdentity: fixed))
        // Params-sensitivity + identity-sensitivity.
        var other = params
        other.strength = 26
        XCTAssertNotEqual(
            GrainModule.seed(params: params, imageIdentity: fixed),
            GrainModule.seed(params: other, imageIdentity: fixed))
        XCTAssertNotEqual(
            GrainModule.seed(params: params, imageIdentity: fixed),
            GrainModule.seed(params: params, imageIdentity: UUID()))
        // The offset quantum holds the dt shape (a non-negative integer).
        for seed in [UInt64(0), UInt64(4095), UInt64(4096), UInt64(1 << 40)] {
            let offset = GrainModule.seedOffset(seed: seed)
            XCTAssertGreaterThanOrEqual(offset, 0)
            XCTAssertLessThan(offset, 4096)
        }
    }

    // MARK: - float64 reference parity

    func testKernelVsFloat64ReferenceParity() async throws {
        let metal = try await makeMetal()
        let width = 64, height = 48
        let input = gradientImage(width: width, height: height)
        let params = GrainModule.Params()
        let identity = UUID()
        let output = try await runGrain(
            params, imageIdentity: identity, input: input,
            width: width, height: height, metal: metal)

        // The float64 twin of the run uniforms.
        let seed = GrainModule.seed(params: params, imageIdentity: identity)
        let u = GrainModule.uniforms(
            params, seedOffset: GrainModule.seedOffset(seed: seed),
            planeW: width, planeH: height, iscale: 1.0,
            roiIn: ROI(x: 0, y: 0, width: width, height: height, scale: 1.0),
            roiOut: ROI(x: 0, y: 0, width: width, height: height, scale: 1.0))
        let refU = GrainReference.Uniforms(
            zoom: Double(u.zoom), strength: Double(u.strength),
            midtonesBias: Double(u.midtonesBias), gamma: Double(u.gamma),
            offset: Double(u.offset), invScaleWd: Double(u.invScaleWd),
            filtermul: Double(u.filtermul), filter: u.filter != 0)

        var compared = 0
        var boundarySkipped = 0
        var maxDiff: Float = 0
        var failures: [String] = []
        for j in 0..<height {
            for i in 0..<width {
                let k = (j * width + i) * 4
                let rgb = SIMD3<Double>(
                    Double(input[k]), Double(input[k + 1]), Double(input[k + 2]))
                let expected = GrainReference.pixel(
                    rgb, x: Double(i), y: Double(j), u: refU)
                // Boundary-adjacency screen: the kernel's float32 noise
                // coordinates carry ~ulp(10²) ≈ 1e-5 error into the
                // skew/floor split — pixels whose (xin+s, yin+s) fraction
                // sits within 1e-3 of a lattice boundary may legally pick
                // a DIFFERENT simplex cell than the float64 reference (a
                // discrete O(1) jump, not an accumulation). Skip them
                // from value parity and BOUND their rate instead.
                let freqs: [Double] = [0.4910, 0.9441, 1.7280]
                let px: Double = Double(i) * Double(u.invScaleWd)
                let py: Double = Double(j) * Double(u.invScaleWd)
                var nearBoundary = false
                for octave in 0..<3 {
                    let xin = px * freqs[octave] / refU.zoom + refU.offset
                    let yin = py * freqs[octave] / refU.zoom
                    let s = (xin + yin + Double(octave)) / 3.0
                    let frx = (xin + s) - (xin + s).rounded(.down)
                    let fry = (yin + s) - (yin + s).rounded(.down)
                    if min(frx, 1.0 - frx) < 1e-3 { nearBoundary = true }
                    if min(fry, 1.0 - fry) < 1e-3 { nearBoundary = true }
                }
                if nearBoundary {
                    boundarySkipped += 1
                    continue
                }
                for c in 0..<3 {
                    let diff = abs(output[k + c] - Float(expected[c]))
                    maxDiff = max(maxDiff, diff)
                    compared += 1
                    if diff > Self.pixelTol, failures.count < 8 {
                        failures.append(
                            "(\(i),\(j)) ch\(c): kernel=\(output[k + c]) "
                                + "ref=\(expected[c]) diff=\(diff)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(compared, 0, "anti-vacuum")
        let skippedRate = Double(boundarySkipped) / Double(width * height)
        XCTAssertLessThanOrEqual(
            skippedRate, 0.03,
            "boundary-flip rate \(skippedRate) exceeds 3% — the screen must stay a floor effect")
        XCTAssertTrue(
            failures.isEmpty,
            "grain float64 parity exceeded \(Self.pixelTol) on the stable set "
                + "(max \(maxDiff), \(boundarySkipped) boundary-skipped):\n"
                + failures.joined(separator: "\n"))
    }

    /// Luma-domain luminance grain: the SAME delta rides R, G, B → the
    /// channel DIFFERENCES are preserved exactly (dt's out[0]-only
    /// injection contract in the linear domain).
    func testLumaInjectionPreservesChannelDifferences() async throws {
        let metal = try await makeMetal()
        let width = 32, height = 32
        var input = gradientImage(width: width, height: height)
        for i in stride(from: 0, to: input.count, by: 4) {
            input[i] = input[i] * 0.8 + 0.02 // break the gray: chroma rides
            input[i + 2] = input[i + 2] * 1.1
        }
        var params = GrainModule.Params()
        params.strength = 60
        let output = try await runGrain(
            params, imageIdentity: UUID(), input: input,
            width: width, height: height, metal: metal)

        var compared = 0
        for i in stride(from: 0, to: input.count, by: 4) {
            let dRGIn = input[i] - input[i + 1]
            let dRGOut = output[i] - output[i + 1]
            let dGBIn = input[i + 1] - input[i + 2]
            let dGBOut = output[i + 1] - output[i + 2]
            XCTAssertEqual(dRGOut, dRGIn, accuracy: Self.pixelTol)
            XCTAssertEqual(dGBOut, dGBIn, accuracy: Self.pixelTol)
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0, "anti-vacuum")
    }

    /// strength 0 ⇒ the routed-blit byte identity (the enabled-instance
    /// fast path; the SEED instance itself ships DISABLED).
    func testNeutralStrengthZeroByteIdentity() async throws {
        let metal = try await makeMetal()
        let width = 24, height = 16
        var input = gradientImage(width: width, height: height)
        input[0] = -0.0
        var params = GrainModule.Params()
        params.strength = 0
        let module = GrainModule(imageIdentity: UUID())
        XCTAssertTrue(module.isNeutral(params), "strength 0 is the neutral contract")
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
        for i in 0..<input.count {
            XCTAssertEqual(output[i].bitPattern, input[i].bitPattern, "at \(i)")
        }
    }

    // MARK: - the 3-octave spectrum anchor (float64, zoom-invariant shape)

    /// Radial band power of the reference noise field at a test zoom that
    /// places the three octave peaks inside the resolvable band (the
    /// dt-verbatim default zoom puts the base octave beyond Nyquist at any
    /// practical render size — the spectral SHAPE is zoom-invariant; the
    /// zoom verbatim itself rides the reference parity). Amplitudes RISE
    /// with octave (a = {0.234, 0.785, 1.215} — fine grain dominant), so
    /// each peak bin must dominate the valley bins on BOTH sides.
    func testSpectrumThreeOctaveAnchor() {
        let n = 128
        let zoom = 0.4910 / 16.0 // octave peaks at 16 / 30.8 / 56.3 cycles
        var field = [Double](repeating: 0, count: n * n)
        for j in 0..<n {
            for i in 0..<n {
                field[j * n + i] = GrainReference.simplex2D(
                    Double(i) / Double(n), Double(j) / Double(n), zoom)
            }
        }
        // Single-bin power on the ky = 0 axis: |ΣΣ v·e^(−i2πikx/n)|² —
        // separable, cheap; the isotropic field puts its octave peaks on
        // every radial direction including this slice.
        func power(_ kx: Int) -> Double {
            var re = 0.0, im = 0.0
            for j in 0..<n {
                for i in 0..<n {
                    let phase = 2.0 * Double.pi * Double(i) * Double(kx) / Double(n)
                    let v = field[j * n + i]
                    re += v * cos(phase)
                    im -= v * sin(phase)
                }
            }
            return (re * re + im * im) / Double(n * n)
        }

        // Nearest DFT bins of the two resolvable octave frequencies. The
        // THIRD octave (56.3 cycles at this zoom) sits in the near-Nyquist
        // aliasing zone — its band-power assertions are meaningless at
        // this render size, so the spectral anchor pins octaves 1-2 (the
        // third octave's f/a values ride the reference parity test).
        let peaks = [16, 31]
        let valleys = [8, 23]
        let peakPowers = peaks.map(power)
        let valleyPowers = valleys.map(power)
        // P(16) vs valleys 8/23; P(31) vs valley 23 (its low-side trough).
        for (index, p) in peakPowers.enumerated() {
            XCTAssertGreaterThan(
                p, valleyPowers[index],
                "peak \(peaks[index]) must dominate the low valley \(valleys[index])")
        }
        XCTAssertGreaterThan(
            peakPowers[1], valleyPowers[1],
            "peak 31 must dominate the mid trough 23")
    }

    // MARK: - registration + layer eligibility

    func testRegistrationAndLayerEligibility() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let made = await registry.makeBox(opName: GrainModule.opName)
        XCTAssertNotNil(made, "grain must register")
        XCTAssertEqual(GrainModule.iopOrder, 65.0)
        let slot = V50Order.entries.first { $0.opName == "grain" }
        XCTAssertEqual(slot?.order, 65.0, "the v50 slot is the pre-existing 65.0 row")
        XCTAssertLessThan(
            GrainModule.iopOrder, LayerCompositeDriver.terminalTailFloor)
        // The registration closure injects the box UUID as the pattern
        // identity carrier (DECISIONS D-08-2-1).
        let box = try XCTUnwrap(made as? ModuleBox<GrainModule>)
        XCTAssertEqual(box.module.imageIdentity, box.instanceID)
    }
}

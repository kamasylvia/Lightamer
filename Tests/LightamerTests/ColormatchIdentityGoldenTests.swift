@testable import LightamerCore
@testable import LightamerIOP
import Metal
import simd
import XCTest

/// ColormatchIdentityGoldenTests (Plan M5-1-01 T8, KD-7; OQ-M5-1-8 G5, the
/// L031 identity discipline) — the op's three identity states pass pixels
/// through BYTE-EXACTLY:
///
/// ① ABSENT — the editing seed carries NO colormatch instance (registration
///    with seed ABSENT, the grade-op precedent): the default render chain
///    never dispatches the op (structural);
/// ② DISABLED — a disabled instance is skipped by the pipe walk (the
///    ModuleInstance contract): at the module face, nothing dispatches;
/// ③ STRENGTH 0 (and the unsolved face) — the module takes the routed-blit
///    identity: output ≡ input byte-for-byte.
///
/// ANTI-VACUUM: a solved strength-1 instance CHANGES the bytes (the identity
/// faces are not "the kernel always copies"). L014 fences on the readbacks.
final class ColormatchIdentityGoldenTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    private func makeTexture(
        _ metal: MetalContext, width: Int, height: Int, write pixels: [SIMD4<Float>]
    ) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: descriptor))
        pixels.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: width, height: height, depth: 1)),
                mipmapLevel: 0, withBytes: raw.baseAddress!,
                bytesPerRow: width * MemoryLayout<SIMD4<Float>>.stride)
        }
        return texture
    }

    private func readback(
        _ metal: MetalContext, _ texture: any MTLTexture
    ) async -> [SIMD4<Float>] {
        await drain(metal)  // L014
        let w = texture.width, h = texture.height
        var pixels = [SIMD4<Float>](repeating: .zero, count: w * h)
        pixels.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!, bytesPerRow: w * MemoryLayout<SIMD4<Float>>.stride,
                from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: w, height: h, depth: 1)),
                mipmapLevel: 0)
        }
        return pixels
    }

    /// The deterministic probe plane (LCG seed): negative + HDR + grays —
    /// byte comparisons need exactness, the content just needs coverage.
    private static func probePlane(width: Int = 33, height: Int = 17) -> [SIMD4<Float>] {
        var state: UInt64 = 0x51D
        func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(Double(state >> 11) / Double(1 << 53))
        }
        return (0..<(width * height)).map { i -> SIMD4<Float> in
            let v = next()
            let w = next()
            return SIMD4(
                v * 2.0 - 0.4, w * 3.0 - 0.5, next() * 1.6 - 0.3, 0.5 + next() * 0.5)
        }
    }

    // MARK: - ① the seed-absent structural face

    func testColormatchAbsentFromEditingSeed() async {
        // The registration face: the op RESOLVES from a populated registry.
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let box = await registry.makeBox(opName: ColormatchModule.opName)
        XCTAssertNotNil(box, "colormatch is registered (the add-face material)")
        // The SEED faces: no colormatch instance in the editing seed — the
        // default render chain never dispatches the op (state ①).
        let fullSeed = LightamerIOPRegistry.editingDefaultInstances()
        XCTAssertFalse(
            fullSeed.contains { $0.opName == ColormatchModule.opName },
            "the full-face seed carries no colormatch (seed ABSENT)")
        let narrowSeed = LightamerIOPRegistry.editingDefaultInstances(defaultFace: true)
        XCTAssertFalse(
            narrowSeed.contains { $0.opName == ColormatchModule.opName },
            "the default-face seed carries no colormatch (seed ABSENT)")
        // And the disabled-set discipline: colormatch is NOT in it.
        XCTAssertFalse(
            LightamerIOPRegistry.defaultFaceDisabledOpNames.contains(
                ColormatchModule.opName),
            "the disable set is zero-touch")
    }

    // MARK: - ②③ the blit-identity faces (byte-exact)

    func testIdentityStatesBlitByteExact() async throws {
        let metal = try await makeMetal()
        let plane = Self.probePlane()
        let width = 33, height = 17

        func run(_ params: ColormatchModule.Params) async throws -> [SIMD4<Float>] {
            let module = ColormatchModule(device: metal.device)
            var piece = IOPiece()
            module.commitParams(params, into: &piece)
            let input = try makeTexture(metal, width: width, height: height, write: plane)
            let output = try makeTexture(metal, width: width, height: height, write: [])
            try await module.process(
                input: input, output: output,
                roiIn: ROI(x: 0, y: 0, width: width, height: height, scale: 1),
                roiOut: ROI(x: 0, y: 0, width: width, height: height, scale: 1),
                piece: &piece, metal: metal)
            return await readback(metal, output)
        }

        // ③a the default instance (strength 0 — the addable placeholder):
        // the routed blit — byte-exact.
        let a = try await run(ColormatchModule.Params())
        XCTAssertEqual(a, plane, "strength 0 → byte-exact passthrough")

        // ③b the unsolved face (strength 1, hashes missing): byte-exact.
        var unsolved = ColormatchModule.Params()
        unsolved.strength = 1.0
        let b = try await run(unsolved)
        XCTAssertEqual(b, plane, "the unsolved state → byte-exact passthrough")

        // The disabled face rides the same blit (a disabled instance never
        // reaches process; its COMMIT face is the identity too).
        var pieceDisabled = IOPiece()
        ColormatchModule().commitParams(ColormatchModule.Params(), into: &pieceDisabled)
        XCTAssertNil(pieceDisabled.data, "the disabled/default commit packs no uniforms")

        // ANTI-VACUUM: the solved strength-1 instance is NOT the identity —
        // the identity faces pass because the op chooses to, not because it
        // cannot change pixels.
        var solved = ColormatchModule.Params()
        solved.strength = 1.0
        solved.matrix = [1.3, 0.1, 0, 0, 0.8, 0.05, 0, 0, 1.1]
        solved.offset = [0.02, -0.01, 0.01]
        solved.sourceStatsHash = "1"
        solved.referenceStatsHash = "2"
        let c = try await run(solved)
        XCTAssertNotEqual(c, plane, "the solved strength-1 instance moves pixels")
        XCTAssertEqual(c.count, plane.count)
    }

    // MARK: - The S2 LUT-arm extension states (M5-1-02 T8, G5)

    /// The in-memory resolver (the module tests' twin).
    private final class GoldenResolver: ColormatchAssetResolving, @unchecked Sendable {
        var solution: ColorMatchCDFSolution?
        var table: [SIMD3<Float>]?
        var degradeReason: String?
        func loadCube(
            assetRef: String, expectedHash: String?
        ) -> ColormatchCubeAsset.LoadResult {
            if let degradeReason { return .degraded(reason: degradeReason) }
            guard let table else { return .degraded(reason: "no table") }
            return .loaded(table: table, bytesHash: 1)
        }
        func cdfSolution(
            sourceStatsHash: String, referenceStatsHash: String
        ) -> ColorMatchCDFSolution? {
            solution
        }
    }

    func testLutArmIdentityStatesBlitByteExact() async throws {
        let metal = try await makeMetal()
        try await metal.registerDefaultLibrary(in: ColormatchKernel.metalBundle)
        let plane = Self.probePlane()
        let width = 33, height = 17

        func run(
            _ params: ColormatchModule.Params, resolver: GoldenResolver
        ) async throws -> [SIMD4<Float>] {
            let module = ColormatchModule(device: metal.device, resolver: resolver)
            var piece = IOPiece()
            module.commitParams(params, into: &piece)
            let input = try makeTexture(metal, width: width, height: height, write: plane)
            let output = try makeTexture(metal, width: width, height: height, write: [])
            try await module.process(
                input: input, output: output,
                roiIn: ROI(x: 0, y: 0, width: width, height: height, scale: 1),
                roiOut: ROI(x: 0, y: 0, width: width, height: height, scale: 1),
                piece: &piece, metal: metal)
            return await readback(metal, output)
        }

        func cdfParams(assetRef: String?) -> ColormatchModule.Params {
            var p = ColormatchModule.Params()
            p.solver = .cdf
            p.strength = 0.9
            p.sourceStatsHash = "1"
            p.referenceStatsHash = "2"
            p.assetRef = assetRef
            return p
        }

        // ④ assetRef nil (the unsolved LUT arm): the routed blit — exact.
        let a = try await run(cdfParams(assetRef: nil), resolver: GoldenResolver())
        XCTAssertEqual(a, plane, "cdf + assetRef nil → byte-exact passthrough")

        // ⑤ the degraded asset: the routed blit — exact.
        let degrading = GoldenResolver()
        degrading.degradeReason = "colormatch asset hash mismatch"
        let b = try await run(cdfParams(assetRef: "x.cube"), resolver: degrading)
        XCTAssertEqual(b, plane, "cdf + degraded asset → byte-exact passthrough")

        // ANTI-VACUUM (the LUT arm): a real table MOVES pixels.
        let armed = GoldenResolver()
        armed.solution = {
            var histogram = [UInt32](repeating: 0, count: 256)
            for bin in 0..<256 { histogram[bin] = 100 }
            let stats = ColorMatchStats(
                mu: SIMD3(0.5, 0, 0), sigma: (0.02, 0, 0, 0.02, 0, 0.02),
                histograms: [histogram, histogram, histogram],
                supportLo: SIMD3(0.05, -0.4, -0.4), supportHi: SIMD3(0.95, 0.4, 0.4),
                sampleCount: 25_600)
            return ColorMatchCDFSolver.solve(
                source: {
                    var shifted = [[UInt32]](repeating: [UInt32](repeating: 0, count: 256), count: 3)
                    for channel in 0..<3 {
                        for bin in 40..<216 { shifted[channel][bin] = 100 }
                    }
                    return ColorMatchStats(
                        mu: SIMD3(0.3, 0, 0), sigma: (0.02, 0, 0, 0.02, 0, 0.02),
                        histograms: shifted, supportLo: SIMD3(0.1, -0.3, -0.3),
                        supportHi: SIMD3(0.7, 0.3, 0.3), sampleCount: 17_600)
                }(), reference: stats)
        }()
        let c = try await run(cdfParams(assetRef: "x.cube"), resolver: armed)
        XCTAssertNotEqual(c, plane, "the LUT arm with a real table moves pixels")
    }
}

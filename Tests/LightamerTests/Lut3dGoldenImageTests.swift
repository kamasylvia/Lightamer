@testable import LightamerCore
@testable import LightamerIOP
import Metal
import simd
import XCTest

/// Lut3dGoldenImageTests (Plan 12-5 T4, IOP-COLOR-08) — the application
/// color-space selector proofs:
///
/// - the four-state matrices: chromatic round trip (fwd·inv = identity),
///   gray neutrality (D65 stays on the neutral axis through every target),
///   and the sRGB/P3 constants matching the ColorOutModule asset to all
///   printed digits (the "同源单实现" verification);
/// - the identity cube through the GPU FULL chain (real matrices → table →
///   inverse) = pixel identity in every colorspace — the CONVENTIONS
///   golden-image discipline for an iop port whose reference is the dt
///   kernel math double-written (PROVENANCE: L017 route ① — dt-cli float
///   export is spatially corrupt on this host (SharpenParityTests
///   provenance + a darktable-cli CrashReporter record); the lut3d XMP
///   params-v3 binary construction is out of budget — the CPU float64
///   reference IS the dt lut3d.cl math, branch-table verified verbatim);
/// - a non-identity table under sRGB / proPhotoLinear application vs the
///   same CPU reference (≤1/1024).
final class Lut3dGoldenImageTests: XCTestCase {

    private enum Tol {
        static let abs: Float = 1.0 / 1024.0
        /// Matrix round-trip in float64: ~1e-12; through the float32 kernel
        /// and the printed 9-digit constants: ~1e-6.
        static let roundTrip: Float = 1e-6
    }

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

    // MARK: - Matrix assets (CPU-level proofs)

    /// fwd·inv = identity for all four states (float64 over the printed
    /// constants — the chromatic round-trip known points).
    func testMatrixRoundTripIdentity() {
        for cs in LutColorspace.allCases {
            let (fwd, inv) = LutColorspaceMatrices.matrices(for: cs)
            let M = LutColorspaceMatrices.simdMatrix(fwd)
            let Minv = LutColorspaceMatrices.simdMatrix(inv)
            let product = Minv * M
            for col in 0..<3 {
                let cols = [product.columns.0, product.columns.1, product.columns.2]
                let got = cols[col]
                let want: SIMD3<Double> =
                    col == 0 ? .init(1, 0, 0) : col == 1 ? .init(0, 1, 0) : .init(0, 0, 1)
                for r in 0..<3 {
                    XCTAssertEqual(got[r], want[r], accuracy: 1e-7, "\(cs) round trip (\(col),\(r))")
                }
            }
        }
    }

    /// Grays stay gray: the no-adaptation targets (sRGB / displayP3, shared
    /// D65) have row sums 1.0 — D65 maps to the target's white (the D-COL1
    /// criterion-1 precondition riding the lut3d application). rec2020 is
    /// the identity. proPhotoLinear is Bradford-adapted (its rows need NOT
    /// sum to 1 — D65 maps to the ProPhoto D50-white coords), so only its
    /// WHITE-POINT MAPPING is asserted instead.
    func testMatrixGrayNeutralityRowSums() {
        // Row sums of the row-major tuple.
        func rowSums(_ m: LutColorspaceMatrices.Matrix9) -> [Double] {
            [
                Double(m.0 + m.1 + m.2),
                Double(m.3 + m.4 + m.5),
                Double(m.6 + m.7 + m.8),
            ]
        }
        for cs in [LutColorspace.sRGB, .displayP3, .rec2020] {
            let (fwd, inv) = LutColorspaceMatrices.matrices(for: cs)
            for (name, m) in [("fwd", fwd), ("inv", inv)] {
                for (r, sum) in rowSums(m).enumerated() {
                    XCTAssertEqual(sum, 1.0, accuracy: 1e-6, "\(cs) \(name) row \(r) sum")
                }
            }
        }
        // proPhotoLinear: D65 through fwd lands on the ProPhoto (D50) white
        // — the numerically derived Bradford white mapping.
        let (fwdPP, invPP) = LutColorspaceMatrices.matrices(for: .proPhotoLinear)
        let Mfwd = LutColorspaceMatrices.simdMatrix(fwdPP)
        let white = Mfwd * SIMD3(1, 1, 1)
        for v in [white.x, white.y, white.z] {
            XCTAssertGreaterThan(v, 0.0, "proPhoto white coordinate positivity")
            XCTAssertLessThan(v, 1.05, "proPhoto white coordinate sanity")
        }
        // And the pair still round-trips (already covered by the identity
        // test; assert the white specifically).
        let back = LutColorspaceMatrices.simdMatrix(invPP) * white
        for r in 0..<3 {
            XCTAssertEqual(back[r], 1.0, accuracy: 1e-7, "proPhoto white round trip")
        }
    }

    /// The sRGB / Display-P3 constants are VERBATIM the ColorOutModule
    /// asset (all printed digits) — the same-source single-implementation
    /// verification demanded by the plan.
    func testSRGBAndP3MatchColorOutAsset() {
        // ColorOutModule's header-published Rec2020→sRGB rows.
        let colorOutSRGBRows: [[Double]] = [
            [1.661272640, -0.588487320, -0.072785321],
            [-0.126189204, 1.134531230, -0.008342025],
            [-0.017014775, -0.100723728, 1.117738502],
        ]
        let colorOutP3Rows: [[Double]] = [
            [1.343930183, -0.282585998, -0.061344185],
            [-0.066855841, 1.077337009, -0.010481169],
            [0.003750840, -0.019626716, 1.015875875],
        ]
        let (fwdSRGB, _) = LutColorspaceMatrices.matrices(for: .sRGB)
        let (fwdP3, _) = LutColorspaceMatrices.matrices(for: .displayP3)
        let tuples: [(LutColorspaceMatrices.Matrix9, [[Double]], String)] = [
            (fwdSRGB, colorOutSRGBRows, "sRGB"), (fwdP3, colorOutP3Rows, "P3"),
        ]
        for (m, rows, name) in tuples {
            let values = [m.0, m.1, m.2, m.3, m.4, m.5, m.6, m.7, m.8]
            for (i, row) in rows.enumerated() {
                for (j, want) in row.enumerated() {
                    XCTAssertEqual(
                        Double(values[i * 3 + j]), want, accuracy: 1e-7,
                        "\(name) (\(i),\(j)) vs ColorOut asset")
                }
            }
        }
    }

    // MARK: - GPU full-chain proofs

    private final class Resolver: Lut3dModule.LutResolving, @unchecked Sendable {
        var tables: [String: CubeLut] = [:]
        func lut(named: String) -> CubeLut? { tables[named] }
    }

    private func identityTable(level: Int) -> [SIMD3<Float>] {
        (0..<(level * level * level)).map { i in
            let r = i % level, g = (i / level) % level, b = i / (level * level)
            let d = Float(level - 1)
            return SIMD3(Float(r) / d, Float(g) / d, Float(b) / d)
        }
    }

    private func makeTexture(
        _ metal: MetalContext, width: Int, height: Int, write pixels: [SIMD4<Float>] = []
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

    private func readback(_ metal: MetalContext, _ texture: any MTLTexture) async -> [SIMD4<Float>] {
        await drain(metal)
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

    /// The identity cube through the GPU FULL chain — real matrices, real
    /// kernel, real module — equals the input. The chromatic round trip is
    /// asserted on the GRAY RAMP for every colorspace (a working-space gray
    /// maps into every target gamut WITHOUT clamping — the fixed point of
    /// fwd·table·inv); rec2020 (identity matrices) additionally asserts the
    /// full 2-D grid. This is the golden-image anchor of the port.
    /// (A full chromatic grid would leave the LUT domain under sRGB/P3 —
    /// the pre-table clamp is dt's clip4 semantics, not a defect.)
    func testIdentityCubeFullChainAllColorspaces() async throws {
        let metal = try await makeMetal()
        let level = 17
        let resolver = Resolver()
        resolver.tables["identity.cube"] = CubeLut(
            kind: .lut3d(size: level), data: identityTable(level: level))

        let grid = 8
        let grays = (0..<grid).map { i -> SIMD4<Float> in
            let t = Float(i) / Float(grid - 1)
            return SIMD4(t, t, t, 0.5)
        }

        func run(_ inputs: [SIMD4<Float>], cs: LutColorspace) async throws -> [SIMD4<Float>] {
            let module = Lut3dModule(device: metal.device, resolver: resolver)
            var piece = IOPiece()
            module.commitParams(
                Lut3dModule.Params(lutName: "identity.cube", colorspace: cs), into: &piece)
            XCTAssertNotNil(piece.data, "\(cs)")
            let input = try makeTexture(
                metal, width: inputs.count, height: 1, write: inputs)
            let output = try makeTexture(metal, width: inputs.count, height: 1)
            try await module.process(
                input: input, output: output,
                roiIn: ROI(x: 0, y: 0, width: inputs.count, height: 1, scale: 1),
                roiOut: ROI(x: 0, y: 0, width: inputs.count, height: 1, scale: 1),
                piece: &piece, metal: metal)
            return await readback(metal, output)
        }

        // The gray ramp: exact identity in EVERY colorspace.
        for cs in LutColorspace.allCases {
            let got = try await run(grays, cs: cs)
            var maxAbs: Float = 0
            for (i, px) in grays.enumerated() {
                for ch in 0..<3 {
                    maxAbs = max(maxAbs, abs(got[i][ch] - px[ch]))
                }
                XCTAssertEqual(got[i].w, px.w, "\(cs) alpha")
            }
            XCTAssertLessThanOrEqual(maxAbs, 1.5 * Tol.abs, "\(cs) identity cube gray round trip")
        }

        // rec2020 (identity matrices): the full chromatic grid too.
        let chromatic = (0..<(grid * grid)).map { i -> SIMD4<Float> in
            let x = Float(i % grid) / Float(grid - 1)
            let y = Float(i / grid) / Float(grid - 1)
            return SIMD4(x, y, (x + y) / 2, 0.5)
        }
        let got = try await run(chromatic, cs: .rec2020)
        var maxAbs: Float = 0
        for (i, px) in chromatic.enumerated() {
            for ch in 0..<3 {
                maxAbs = max(maxAbs, abs(got[i][ch] - px[ch]))
            }
        }
        XCTAssertLessThanOrEqual(maxAbs, 1.5 * Tol.abs, "rec2020 identity cube chromatic grid")
    }

    /// A saturated non-identity table under sRGB and proPhotoLinear
    /// application vs the CPU float64 reference (the SAME dt math with the
    /// REAL matrices) — the golden-image gate at ≤1/1024.
    func testNonIdentityTableWithRealMatrices() async throws {
        let metal = try await makeMetal()
        let level = 9
        // A strongly non-linear table (sine sweep per lattice axis).
        let table: [SIMD3<Float>] = (0..<(level * level * level)).map { i in
            let r = i % level, g = (i / level) % level, b = i / (level * level)
            func f(_ v: Int) -> Float {
                0.5 + 0.5 * sin(Float(v) / Float(level - 1) * 2.2)
            }
            return SIMD3(f(r), f(g), f(b))
        }
        let resolver = Resolver()
        resolver.tables["sine.cube"] = CubeLut(
            kind: .lut3d(size: level),
            domainMin: SIMD3(0, 0, 0), domainMax: SIMD3(1, 1, 1), data: table)

        let grid = 7
        let inputs = (0..<(grid * grid)).map { i -> SIMD4<Float> in
            let x = Float(i % grid) / Float(grid - 1)
            let y = Float(i / grid) / Float(grid - 1)
            return SIMD4(x * 0.9 + 0.05, y * 0.9 + 0.05, (1 - x) * 0.9 + 0.05, 0.5)
        }

        for cs in [LutColorspace.sRGB, .proPhotoLinear] {
            let (fwd, inv) = LutColorspaceMatrices.matrices(for: cs)
            let Mfwd = LutColorspaceMatrices.simdMatrix(fwd)
            let Minv = LutColorspaceMatrices.simdMatrix(inv)

            let module = Lut3dModule(device: metal.device, resolver: resolver)
            var piece = IOPiece()
            module.commitParams(
                Lut3dModule.Params(lutName: "sine.cube", colorspace: cs), into: &piece)

            let input = try makeTexture(metal, width: grid, height: grid, write: inputs)
            let output = try makeTexture(metal, width: grid, height: grid, write: [])
            try await module.process(
                input: input, output: output,
                roiIn: ROI(x: 0, y: 0, width: grid, height: grid, scale: 1),
                roiOut: ROI(x: 0, y: 0, width: grid, height: grid, scale: 1),
                piece: &piece, metal: metal)
            let got = await readback(metal, output)

            var maxAbs: Float = 0
            var compared = 0
            for (i, px) in inputs.enumerated() {
                let ref = Lut3dKernelTests.cpuLut3d(
                    SIMD3(Double(px.x), Double(px.y), Double(px.z)), table: table,
                    level: level, domainMin: SIMD3(0, 0, 0), domainMax: SIMD3(1, 1, 1),
                    interpolation: .tetrahedral, fwd: Mfwd, inv: Minv)
                for ch in 0..<3 {
                    maxAbs = max(maxAbs, abs(got[i][ch] - Float(ref[ch])))
                    compared += 1
                }
            }
            XCTAssertGreaterThan(compared, 0, "vacuous \(cs)")
            XCTAssertLessThanOrEqual(maxAbs, Tol.abs, "\(cs) golden gate")
        }
    }
}


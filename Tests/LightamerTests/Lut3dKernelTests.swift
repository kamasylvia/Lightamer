@testable import LightamerCore
@testable import LightamerIOP
import Metal
import simd
import XCTest

/// Lut3dKernelTests (Plan 12-5 T2, IOP-COLOR-08) — the tetrahedral/trilinear
/// kernel port proofs:
/// - tetrahedral & trilinear vs the CPU float64 reference (the SAME math
///   double-written: lattice map + DOMAIN remap + the lut3d.cl:51-77 weight
///   branches), absolute tolerance 1/1024 (the rgba16Float gate — RESEARCH
///   §6.4; a breach would trigger the rgba32Float upgrade DECISION);
/// - DOMAIN remap known points (HDR domain >1, negative domain);
/// - lattice-point exactness (d=0 → the exact table entry, both states);
/// - identity cube → pixel identity through the full kernel;
/// - the module-level neutral (lutName nil) and missing-library blit
///   identity (L031: routed through makeRoutedCommandBuffer — the source
///   grep is the T6 build walkthrough).
/// ANTI-VACUUM: every comparison loop has a compared>0 gate. L014: every
/// readback drains first.
final class Lut3dKernelTests: XCTestCase {

    private enum Tol {
        /// 1/1024 absolute (plan literal — the rgba16Float default verdict).
        static let abs: Float = 1.0 / 1024.0
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

    // MARK: - Case book

    struct Case {
        var name: String
        var level: Int
        var domainMin: SIMD3<Double>
        var domainMax: SIMD3<Double>
        var inputMin: SIMD3<Double>
        var inputMax: SIMD3<Double>
    }

    /// The default 0..1 domain (dt parity shape) + the two capability-
    /// extension domains (RESEARCH §6.3): HDR >1 and negative.
    static let cases: [Case] = [
        Case(name: "unit", level: 9, domainMin: SIMD3(0, 0, 0), domainMax: SIMD3(1, 1, 1),
             inputMin: SIMD3(-0.2, -0.2, -0.2), inputMax: SIMD3(1.2, 1.2, 1.2)),
        Case(name: "hdr", level: 8, domainMin: SIMD3(0, 0, 0), domainMax: SIMD3(2.5, 2.5, 2.5),
             inputMin: SIMD3(-0.5, -0.5, -0.5), inputMax: SIMD3(3.0, 3.0, 3.0)),
        Case(name: "negative", level: 7, domainMin: SIMD3(-1, -1, -1), domainMax: SIMD3(1, 1, 1),
             inputMin: SIMD3(-1.5, -1.5, -1.5), inputMax: SIMD3(1.5, 1.5, 1.5)),
        Case(name: "mixed", level: 5, domainMin: SIMD3(-0.5, 0, 0.25),
             domainMax: SIMD3(0.5, 1.5, 1.75), inputMin: SIMD3(-1, -0.5, 0),
             inputMax: SIMD3(1, 2, 2)),
    ]

    // MARK: - CPU float64 reference (the double-written math)

    /// The kernel's prologue: forward matrix (identity in T2's table tests —
    /// T4's golden tests pass the real matrices), DOMAIN remap, lattice map.
    /// convert_int default rounding = round-to-nearest-even in BOTH OpenCL
    /// and Metal — the Swift mirror uses .toNearestOrEven.
    static func cpuLut3d(
        _ rgbIn: SIMD3<Double>, table: [SIMD3<Float>], level: Int,
        domainMin: SIMD3<Double>, domainMax: SIMD3<Double>,
        interpolation: LutInterpolation, fwd: simd_double3x3 = simd_double3x3(1),
        inv: simd_double3x3 = simd_double3x3(1)
    ) -> SIMD3<Double> {
        let v0 = fwd * rgbIn
        let v = (simd_clamp(v0, domainMin, domainMax) - domainMin) / (domainMax - domainMin)
        var scaled = v * Double(level - 1)
        func clampInt(_ x: Int, _ lo: Int, _ hi: Int) -> Int { min(max(x, lo), hi) }
        let rgbi = SIMD3<Int>(
            clampInt(Int(scaled.x.rounded(.toNearestOrEven)), 0, level - 2),
            clampInt(Int(scaled.y.rounded(.toNearestOrEven)), 0, level - 2),
            clampInt(Int(scaled.z.rounded(.toNearestOrEven)), 0, level - 2))
        scaled = scaled - SIMD3<Double>(rgbi)

        func entry(_ x: Int, _ y: Int, _ z: Int) -> SIMD3<Double> {
            // Kernel index order r + g*L + b*L² (the parser's red-fastest
            // lock makes the array index direct).
            SIMD3<Double>(table[x + y * level + z * level * level])
        }
        let c000 = entry(rgbi.x, rgbi.y, rgbi.z)
        let c100 = entry(rgbi.x + 1, rgbi.y, rgbi.z)
        let c010 = entry(rgbi.x, rgbi.y + 1, rgbi.z)
        let c110 = entry(rgbi.x + 1, rgbi.y + 1, rgbi.z)
        let c001 = entry(rgbi.x, rgbi.y, rgbi.z + 1)
        let c101 = entry(rgbi.x + 1, rgbi.y, rgbi.z + 1)
        let c011 = entry(rgbi.x, rgbi.y + 1, rgbi.z + 1)
        let c111 = entry(rgbi.x + 1, rgbi.y + 1, rgbi.z + 1)

        let d = scaled
        let out: SIMD3<Double>
        switch interpolation {
        case .trilinear:
            out = (1 - d.x) * (1 - d.y) * (1 - d.z) * c000
                + d.x * (1 - d.y) * (1 - d.z) * c100
                + (1 - d.x) * d.y * (1 - d.z) * c010
                + d.x * d.y * (1 - d.z) * c110
                + (1 - d.x) * (1 - d.y) * d.z * c001
                + d.x * (1 - d.y) * d.z * c101
                + (1 - d.x) * d.y * d.z * c011
                + d.x * d.y * d.z * c111
        case .tetrahedral:
            // lut3d.cl:51-77 verbatim branch table.
            if d.x > d.y {
                if d.y > d.z {
                    out = (1 - d.x) * c000 + (d.x - d.y) * c100 + (d.y - d.z) * c110 + d.z * c111
                } else if d.x > d.z {
                    out = (1 - d.x) * c000 + (d.x - d.z) * c100 + (d.z - d.y) * c101 + d.y * c111
                } else {
                    out = (1 - d.z) * c000 + (d.z - d.x) * c001 + (d.x - d.y) * c101 + d.y * c111
                }
            } else {
                if d.z > d.y {
                    out = (1 - d.z) * c000 + (d.z - d.y) * c001 + (d.y - d.x) * c011 + d.x * c111
                } else if d.z > d.x {
                    out = (1 - d.y) * c000 + (d.y - d.z) * c010 + (d.z - d.x) * c011 + d.x * c111
                } else {
                    out = (1 - d.y) * c000 + (d.y - d.x) * c010 + (d.x - d.z) * c110 + d.z * c111
                }
            }
        }
        return inv * out
    }

    // MARK: - GPU plumbing

    private func makeTexture(
        _ metal: MetalContext, width: Int, height: Int, write pixels: [SIMD4<Float>]? = nil
    ) throws -> (any MTLTexture) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: descriptor))
        if let pixels {
            pixels.withUnsafeBytes { raw in
                texture.replace(
                    region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                        size: MTLSize(width: width, height: height, depth: 1)),
                    mipmapLevel: 0, withBytes: raw.baseAddress!,
                    bytesPerRow: width * MemoryLayout<SIMD4<Float>>.stride)
            }
        }
        return texture
    }

    private func makeClut(_ metal: MetalContext, table: [SIMD3<Float>], level: Int) throws
        -> any MTLTexture
    {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba32Float
        descriptor.width = level
        descriptor.height = level
        descriptor.depth = level
        descriptor.mipmapLevelCount = 1
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: descriptor))
        var floats = [Float]()
        floats.reserveCapacity(table.count * 4)
        for v in table {
            floats.append(v.x); floats.append(v.y)
            floats.append(v.z); floats.append(1.0)
        }
        floats.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: level, height: level, depth: level)),
                mipmapLevel: 0, slice: 0, withBytes: raw.baseAddress!,
                bytesPerRow: level * 16, bytesPerImage: level * level * 16)
        }
        return texture
    }

    private struct Uniforms {
        var width: UInt32
        var height: UInt32
        var level: UInt32
        var domainMinX: Float = 0, domainMinY: Float = 0, domainMinZ: Float = 0
        var domainMaxX: Float = 1, domainMaxY: Float = 1, domainMaxZ: Float = 1
        var fwd: (Float, Float, Float, Float, Float, Float, Float, Float, Float) = (1, 0, 0, 0, 1, 0, 0, 0, 1)
        var inv: (Float, Float, Float, Float, Float, Float, Float, Float, Float) = (1, 0, 0, 0, 1, 0, 0, 0, 1)
    }

    private func dispatch(
        _ metal: MetalContext, functionName: String, input: any MTLTexture,
        output: any MTLTexture, clut: any MTLTexture, uniforms: Uniforms
    ) async throws {
        let session = try await metal.makeEncoder(functionName: functionName)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.setTexture(clut, index: 2)
        var u = uniforms
        let buffer = metal.device.makeBuffer(
            bytes: &u, length: MemoryLayout<Uniforms>.stride, options: .storageModeShared)!
        session.encoder.setBuffer(buffer, offset: 0, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
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

    // Deterministic PRNG (stable across runs — no XCTestCase-seeded drift).
    private func lcg(_ seed: inout UInt64) -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 11) & 0xFFFF_FFFF_FFFF) / Double(0xFFFF_FFFF_FFFF)
    }

    private func randomTable(level: Int, range: ClosedRange<Double>, seed: UInt64) -> [SIMD3<Float>] {
        var s = seed
        return (0..<(level * level * level)).map { _ in
            SIMD3(Float(range.lowerBound + lcg(&s) * (range.upperBound - range.lowerBound)),
                  Float(range.lowerBound + lcg(&s) * (range.upperBound - range.lowerBound)),
                  Float(range.lowerBound + lcg(&s) * (range.upperBound - range.lowerBound)))
        }
    }

    /// The exact identity cube: entry(r,g,b) = (r,g,b)/(L-1).
    private func identityTable(level: Int) -> [SIMD3<Float>] {
        (0..<(level * level * level)).map { i in
            let r = i % level, g = (i / level) % level, b = i / (level * level)
            let d = Float(level - 1)
            return SIMD3(Float(r) / d, Float(g) / d, Float(b) / d)
        }
    }

    private func runCase(
        _ metal: MetalContext, functionName: String, c: Case, table: [SIMD3<Float>],
        interpolation: LutInterpolation, grid: Int = 9
    ) async throws -> (maxAbs: Float, compared: Int) {
        // Grid of inputs spanning (and exceeding) the domain, alpha 0.5.
        var inputs: [SIMD4<Float>] = []
        inputs.reserveCapacity(grid * grid)
        for y in 0..<grid {
            for x in 0..<grid {
                let t = Double(x) / Double(grid - 1), u = Double(y) / Double(grid - 1)
                let v = (t + u) / 2
                inputs.append(SIMD4(
                    Float(c.inputMin.x + t * (c.inputMax.x - c.inputMin.x)),
                    Float(c.inputMin.y + u * (c.inputMax.y - c.inputMin.y)),
                    Float(c.inputMin.z + v * (c.inputMax.z - c.inputMin.z)), 0.5))
            }
        }
        let input = try makeTexture(metal, width: grid, height: grid, write: inputs)
        let output = try makeTexture(metal, width: grid, height: grid)
        let clut = try makeClut(metal, table: table, level: c.level)
        var uniforms = Uniforms(width: UInt32(grid), height: UInt32(grid), level: UInt32(c.level))
        uniforms.domainMinX = Float(c.domainMin.x)
        uniforms.domainMinY = Float(c.domainMin.y)
        uniforms.domainMinZ = Float(c.domainMin.z)
        uniforms.domainMaxX = Float(c.domainMax.x)
        uniforms.domainMaxY = Float(c.domainMax.y)
        uniforms.domainMaxZ = Float(c.domainMax.z)
        try await dispatch(metal, functionName: functionName, input: input, output: output,
            clut: clut, uniforms: uniforms)
        let got = await readback(metal, output)

        var maxAbs: Float = 0
        var compared = 0
        var samples: [String] = []
        for (i, px) in inputs.enumerated() {
            let ref = Self.cpuLut3d(
                SIMD3(Double(px.x), Double(px.y), Double(px.z)), table: table,
                level: c.level, domainMin: c.domainMin, domainMax: c.domainMax,
                interpolation: interpolation)
            compared += 3
            for ch in 0..<3 {
                let d = Swift.abs(got[i][ch] - Float(ref[ch]))
                maxAbs = Swift.max(maxAbs, d)
            }
            if samples.count < 3, Swift.abs(got[i].x - Float(ref.x)) > Tol.abs {
                samples.append(
                    "in=\(px) got=\(got[i]) ref=\(ref)")
            }
        }
        if !samples.isEmpty {
            print("[lut3d-debug] \(c.name) \(interpolation): \(samples.joined(separator: " | "))")
        }
        return (maxAbs, compared)
    }

    // MARK: - Parity vs CPU float64 (≤1/1024)

    func testTetrahedralVsCPUFloat64() async throws {
        let metal = try await makeMetal()
        for c in Self.cases {
            let table = randomTable(level: c.level, range: -0.2...2.8, seed: 0xC0FFEE)
            let (maxAbs, compared) = try await runCase(
                metal, functionName: Lut3dModule.Kernel.tetrahedral, c: c, table: table,
                interpolation: .tetrahedral)
            XCTAssertGreaterThan(compared, 0, "\(c.name): vacuous")
            XCTAssertLessThanOrEqual(
                maxAbs, Tol.abs,
                "\(c.name): tetrahedral max abs \(maxAbs) > 1/1024")
        }
    }

    func testTrilinearVsCPUFloat64() async throws {
        let metal = try await makeMetal()
        for c in Self.cases {
            let table = randomTable(level: c.level, range: -0.2...2.8, seed: 0xBEEF)
            let (maxAbs, compared) = try await runCase(
                metal, functionName: Lut3dModule.Kernel.trilinear, c: c, table: table,
                interpolation: .trilinear)
            XCTAssertGreaterThan(compared, 0, "\(c.name): vacuous")
            XCTAssertLessThanOrEqual(maxAbs, Tol.abs, "\(c.name): trilinear max abs \(maxAbs)")
        }
    }

    // MARK: - Known-point proofs

    func testLatticePointsExactBothStates() async throws {
        // Input exactly ON a lattice point → the output IS the table entry
        // (both interpolations agree exactly there — the golden comparison
        // anchor between the two states).
        let metal = try await makeMetal()
        let level = 4
        let table = randomTable(level: level, range: 0...1, seed: 42)
        for probe: SIMD3<Float> in [SIMD3(0, 0, 0), SIMD3(1.0 / 3, 2.0 / 3, 0), SIMD3(1, 1, 1)] {
            let entry = table[Int(probe.x * 3) + Int(probe.y * 3) * level + Int(probe.z * 3) * 16]
            for functionName in [Lut3dModule.Kernel.tetrahedral, Lut3dModule.Kernel.trilinear] {
                let c = Case(name: "lattice", level: level, domainMin: .zero, domainMax: .one,
                    inputMin: .zero, inputMax: .one)
                var inputs = [SIMD4<Float>]()
                // 1×1 plane with the probe value.
                inputs = [SIMD4(probe.x, probe.y, probe.z, 0.5)]
                let input = try makeTexture(metal, width: 1, height: 1, write: inputs)
                let output = try makeTexture(metal, width: 1, height: 1)
                let clut = try makeClut(metal, table: table, level: level)
                var uniforms = Uniforms(width: 1, height: 1, level: UInt32(level))
                try await dispatch(metal, functionName: functionName, input: input,
                    output: output, clut: clut, uniforms: uniforms)
                let got = await readback(metal, output)
                XCTAssertEqual(got[0].x, entry.x, accuracy: Tol.abs, "\(functionName) x")
                XCTAssertEqual(got[0].y, entry.y, accuracy: Tol.abs, "\(functionName) y")
                XCTAssertEqual(got[0].z, entry.z, accuracy: Tol.abs, "\(functionName) z")
            }
        }
    }

    func testIdentityCubeFullIdentity() async throws {
        // The identity cube through EITHER interpolation = pixel identity
        // (convex weights sum to 1; identity entries at lattice corners).
        let metal = try await makeMetal()
        let level = 8
        let c = Case(name: "identity", level: level, domainMin: .zero, domainMax: .one,
            inputMin: SIMD3(0, 0, 0), inputMax: SIMD3(1, 1, 1))
        let table = identityTable(level: level)
        for functionName in [Lut3dModule.Kernel.tetrahedral, Lut3dModule.Kernel.trilinear] {
            let interpolation: LutInterpolation =
                functionName == Lut3dModule.Kernel.tetrahedral ? .tetrahedral : .trilinear
            var inputs: [SIMD4<Float>] = []
            let grid = 8
            for y in 0..<grid {
                for x in 0..<grid {
                    inputs.append(SIMD4(
                        Float(x) / Float(grid - 1), Float(y) / Float(grid - 1),
                        Float((x + y) % grid) / Float(grid - 1), 0.5))
                }
            }
            let input = try makeTexture(metal, width: grid, height: grid, write: inputs)
            let output = try makeTexture(metal, width: grid, height: grid)
            let clut = try makeClut(metal, table: table, level: level)
            var uniforms = Uniforms(
                width: UInt32(grid), height: UInt32(grid), level: UInt32(level))
            try await dispatch(metal, functionName: functionName, input: input,
                output: output, clut: clut, uniforms: uniforms)
            let got = await readback(metal, output)
            for (i, px) in inputs.enumerated() {
                for ch in 0..<3 {
                    XCTAssertEqual(
                        got[i][ch], px[ch], accuracy: 1.5 * Tol.abs,
                        "\(functionName) identity violated at \(i) ch\(ch)")
                }
                XCTAssertEqual(got[i].w, 0.5, "\(functionName) alpha passthrough")
            }
            _ = interpolation
        }
    }

    // MARK: - 1D ramp kernel (T3 — the capability extension beyond dt's
    // "1D cube LUT is not supported", lut3d.c:808-815)

    /// CPU reference for the 1D ramp: per-channel piecewise-linear with the
    /// INPUT_RANGE remap (RESEARCH §6.3 formula) — mirrors `lut3d_1d`.
    static func cpu1d(
        _ rgbIn: SIMD3<Double>, ramps: [SIMD3<Float>], fwd: simd_double3x3 = simd_double3x3(1),
        inv: simd_double3x3 = simd_double3x3(1), inMin: Double = 0, inMax: Double = 1
    ) -> SIMD3<Double> {
        let size = ramps.count
        let v0 = fwd * rgbIn
        let v = (min(max(v0, SIMD3(repeating: inMin)), SIMD3(repeating: inMax)) - inMin)
            / (inMax - inMin)
        let scaled = v * Double(size - 1)
        func sample(_ x: Double, _ ch: Int) -> Double {
            // Segment base clamps to size-2, sample point to size-1 — the
            // top vertex must reach the final ramp entry (kernel mirror).
            let clipped = min(max(x, 0), Double(size - 1))
            let base = min(clipped.rounded(.down), Double(size - 2))
            let fr = clipped - base
            let i0 = Int(base)
            let a = Double(ramps[i0][ch]), b = Double(ramps[i0 + 1][ch])
            return a + (b - a) * fr
        }
        return inv * SIMD3(
            sample(scaled.x, 0), sample(scaled.y, 1), sample(scaled.z, 2))
    }

    private func makeRamp(
        _ metal: MetalContext, ramps: [SIMD3<Float>]
    ) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type1D
        descriptor.pixelFormat = .rgba32Float
        descriptor.width = ramps.count
        descriptor.mipmapLevelCount = 1
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: descriptor))
        var floats = [Float]()
        floats.reserveCapacity(ramps.count * 4)
        for v in ramps {
            floats.append(v.x); floats.append(v.y); floats.append(v.z); floats.append(1)
        }
        floats.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: ramps.count, height: 1, depth: 1)),
                mipmapLevel: 0, slice: 0, withBytes: raw.baseAddress!,
                bytesPerRow: ramps.count * 16, bytesPerImage: ramps.count * 16)
        }
        return texture
    }

    private func dispatch1D(
        _ metal: MetalContext, input: any MTLTexture, output: any MTLTexture,
        ramps: any MTLTexture, size: Int, inMin: Double, inMax: Double
    ) async throws {
        var u = Uniforms(width: UInt32(output.width), height: UInt32(output.height),
            level: UInt32(size))
        u.domainMinX = Float(inMin); u.domainMinY = Float(inMin); u.domainMinZ = Float(inMin)
        u.domainMaxX = Float(inMax); u.domainMaxY = Float(inMax); u.domainMaxZ = Float(inMax)
        let session = try await metal.makeEncoder(functionName: Lut3dModule.Kernel.ramp1D)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.setTexture(ramps, index: 2)
        let buffer = metal.device.makeBuffer(
            bytes: &u, length: MemoryLayout<Uniforms>.stride, options: .storageModeShared)!
        session.encoder.setBuffer(buffer, offset: 0, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    /// Identity 1D ramp = pixel identity through the FULL module path; then
    /// known points, out-of-domain endpoint clamps, and the INPUT_RANGE
    /// remap vs the CPU reference (the plan's two-case anchor resolved:
    /// texture1d integer reads work — the wide-strip fallback stays unused,
    /// DECISIONS D8).
    func test1DRamp() async throws {
        let metal = try await makeMetal()
        let size = 16

        // Identity ramp through the module (1D commit → ramp kernel).
        let resolver = Resolver()
        resolver.tables["id1d.cube"] = CubeLut(
            kind: .lut1d(size: size),
            data: (0..<size).map { i in
                let v = Float(i) / Float(size - 1)
                return SIMD3(v, v, v)
            })
        let module = Lut3dModule(device: metal.device, resolver: resolver)
        var piece = IOPiece()
        // rec2020 = identity matrices — the pure-ramp identity proof (the
        // sRGB matrix round trip is T4's separate chromatic identity).
        module.commitParams(
            Lut3dModule.Params(lutName: "id1d.cube", colorspace: .rec2020), into: &piece)
        XCTAssertNotNil(piece.data)

        let grid = 4
        let inputs = (0..<(grid * grid)).map { i -> SIMD4<Float> in
            let t = Float(i) / Float(grid * grid - 1)
            return SIMD4(t, 1 - t, t * t, 0.5)
        }
        let input = try makeTexture(metal, width: grid, height: grid, write: inputs)
        let output = try makeTexture(metal, width: grid, height: grid)
        try await module.process(
            input: input, output: output,
            roiIn: ROI(x: 0, y: 0, width: grid, height: grid, scale: 1),
            roiOut: ROI(x: 0, y: 0, width: grid, height: grid, scale: 1),
            piece: &piece, metal: metal)
        let got = await readback(metal, output)
        for (i, px) in inputs.enumerated() {
            for ch in 0..<3 {
                XCTAssertEqual(got[i][ch], px[ch], accuracy: Tol.abs, "identity 1D ch\(ch)")
            }
        }

        // Known-point + clamp + INPUT_RANGE remap on the direct kernel path.
        var ramps: [SIMD3<Float>] = []
        for i in 0..<size {
            let t = Float(i) / Float(size - 1)
            ramps.append(SIMD3(t * t, 1 - t * t, sin(Float(i) * 0.4)))
        }
        let rampsTex = try makeRamp(metal, ramps: ramps)
        let inMin = -0.25, inMax = 1.75
        let probes: [SIMD4<Float>] = [
            SIMD4(-0.25, 0.75, 1.75, 0.5),   // range endpoints + middle
            SIMD4(-5.0, 5.0, 0.0, 0.5),      // outside both ends → endpoint clamp
            SIMD4(0.333, 0.777, 1.111, 0.5), // interior fractions
        ]
        let pin = try makeTexture(metal, width: probes.count, height: 1, write: probes)
        let pout = try makeTexture(metal, width: probes.count, height: 1)
        try await dispatch1D(
            metal, input: pin, output: pout, ramps: rampsTex, size: size,
            inMin: inMin, inMax: inMax)
        let pgot = await readback(metal, pout)
        var compared = 0
        for (i, px) in probes.enumerated() {
            let ref = Self.cpu1d(
                SIMD3(Double(px.x), Double(px.y), Double(px.z)), ramps: ramps,
                inMin: inMin, inMax: inMax)
            for ch in 0..<3 {
                XCTAssertEqual(pgot[i][ch], Float(ref[ch]), accuracy: Tol.abs,
                    "1d probe \(i) ch\(ch)")
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "vacuous 1d")
    }

    // MARK: - Module-level neutral / degraded identity (L031 routed blit)

    private final class Resolver: Lut3dModule.LutResolving, @unchecked Sendable {
        var tables: [String: CubeLut] = [:]
        func lut(named: String) -> CubeLut? { tables[named] }
    }

    /// Neutral (lutName nil) → blit identity: output bytes == input bytes.
    func testNeutralIsBlitIdentity() async throws {
        let metal = try await makeMetal()
        let module = Lut3dModule(device: metal.device, resolver: nil)
        var piece = IOPiece()
        module.commitParams(Lut3dModule.Params(lutName: nil), into: &piece)
        XCTAssertNil(piece.data, "neutral must commit no uniforms (blit path)")

        let grid = 4
        let inputs = (0..<(grid * grid)).map { i -> SIMD4<Float> in
            SIMD4(Float(i) / Float(grid * grid), 0.25, 0.75, 0.5)
        }
        let input = try makeTexture(metal, width: grid, height: grid, write: inputs)
        let output = try makeTexture(metal, width: grid, height: grid)
        try await module.process(
            input: input, output: output,
            roiIn: ROI(x: 0, y: 0, width: grid, height: grid, scale: 1),
            roiOut: ROI(x: 0, y: 0, width: grid, height: grid, scale: 1),
            piece: &piece, metal: metal)
        let got = await readback(metal, output)
        for (i, px) in inputs.enumerated() {
            for ch in 0..<4 {
                XCTAssertEqual(got[i][ch], px[ch], accuracy: 0, "neutral blit byte-identity ch\(ch)")
            }
        }
    }

    /// Missing library entry (D-12-CONTEXT-5/D-6 degraded reference) →
    /// same blit identity, never a throw.
    func testMissingLibraryEntryDegradesToIdentity() async throws {
        let metal = try await makeMetal()
        let resolver = Resolver()  // empty — every name is missing
        let module = Lut3dModule(device: metal.device, resolver: resolver)
        var piece = IOPiece()
        module.commitParams(Lut3dModule.Params(lutName: "gone.cube"), into: &piece)
        XCTAssertNil(piece.data, "missing entry must degrade to the blit path")

        let grid = 2
        let inputs = [SIMD4<Float>](
            repeating: SIMD4(0.1, 0.5, 0.9, 0.5), count: grid * grid)
        let input = try makeTexture(metal, width: grid, height: grid, write: inputs)
        let output = try makeTexture(metal, width: grid, height: grid)
        try await module.process(
            input: input, output: output,
            roiIn: ROI(x: 0, y: 0, width: grid, height: grid, scale: 1),
            roiOut: ROI(x: 0, y: 0, width: grid, height: grid, scale: 1),
            piece: &piece, metal: metal)
        let got = await readback(metal, output)
        for px in got {
            for (ch, v) in [0.1 as Float, 0.5, 0.9, 0.5].enumerated() {
                XCTAssertEqual(px[ch], v, accuracy: 0)
            }
        }
    }

    /// A real resolved table drives the KERNEL path (not the blit): a
    /// strongly non-identity table must move the pixels.
    func testResolvedTableRunsKernelPath() async throws {
        let metal = try await makeMetal()
        let resolver = Resolver()
        let level = 4
        // Max-out table: entry = (1-r,1-g,1-b)/(L-1) — clearly non-identity.
        var table = identityTable(level: level)
        for i in table.indices {
            table[i] = SIMD3(1, 1, 1) - table[i]
        }
        resolver.tables["neg.cube"] = CubeLut(
            kind: .lut3d(size: level), data: table)
        let module = Lut3dModule(device: metal.device, resolver: resolver)
        var piece = IOPiece()
        module.commitParams(Lut3dModule.Params(lutName: "neg.cube"), into: &piece)
        XCTAssertNotNil(piece.data, "resolved table must commit uniforms")

        let inputs = [SIMD4<Float>](repeating: SIMD4(0, 0, 0, 0.5), count: 1)
        let input = try makeTexture(metal, width: 1, height: 1, write: inputs)
        let output = try makeTexture(metal, width: 1, height: 1)
        try await module.process(
            input: input, output: output,
            roiIn: ROI(x: 0, y: 0, width: 1, height: 1, scale: 1),
            roiOut: ROI(x: 0, y: 0, width: 1, height: 1, scale: 1),
            piece: &piece, metal: metal)
        let got = await readback(metal, output)
        // Input (0,0,0) → lattice corner entry = (1,1,1) — moved, not blit.
        XCTAssertEqual(got[0].x, 1.0, accuracy: Tol.abs)
        XCTAssertEqual(got[0].z, 1.0, accuracy: Tol.abs)
    }
}

@testable import LightamerCore
@testable import LightamerIOP
import XCTest

/// ColormatchModuleTests (Plan M5-1-01 T5, KD-5 + checker E2) — the op's
/// module face:
///
/// - the statics: opName / the 36.5 slot / the lut3d twin flags / the RGB
///   colorspace;
/// - the default Params() encoding = the BYTE identity core (the hash
///   zero-drift专测 — M3-1 precedent) and the GradeCatalog identityJSON
///   agreement;
/// - the EXPLICIT-null encoding (checker E2): the three optionals appear as
///   JSON nulls in the default encoding (the IopCatalog guard's key-set
///   closure);
/// - the serde round trip with a solved payload + the tolerant decode faces
///   (missing keys → defaults; an unknown solver rawValue degrades, never
///   throws into the sidecar loader);
/// - the identity-blit commit path: strength 0 / unsolved → piece.data nil
///   (no uniforms — the GPU byte-identity ride is T8's G5); a solved
///   non-identity payload packs uniforms and a distinct paramsHash.
final class ColormatchModuleTests: XCTestCase {

    // MARK: - Statics

    func testFlagsOrderAndOpNameStatics() {
        XCTAssertEqual(ColormatchModule.opName, "colormatch")
        XCTAssertEqual(ColormatchModule.iopOrder, 36.5)
        XCTAssertEqual(ColormatchModule.defaultColorspace, .RGB)
        XCTAssertTrue(ColormatchModule.flags.contains(.supportsBlending))
        XCTAssertTrue(ColormatchModule.flags.contains(.allowTiling))
        // The V50Order row agrees with the module (the add-only row).
        XCTAssertEqual(V50Order.order(for: ColormatchModule.opName), 36.5)
        // The grade catalog row agrees on owner + identity bytes.
        let row = GradeCatalog.item(opName: ColormatchModule.opName)
        XCTAssertEqual(row?.catalogID, "colormatch")
        XCTAssertEqual(row?.owner, .grade)
        XCTAssertEqual(
            row?.identityJSON,
            String(data: ParamsCoding.encode(ColormatchModule.Params()), encoding: .utf8))
    }

    // MARK: - The byte identity core

    func testDefaultParamsEncodingIsByteIdentityCore() throws {
        // Double encode → identical bytes (the canonical coder).
        let a = ParamsCoding.encode(ColormatchModule.Params())
        let b = ParamsCoding.encode(ColormatchModule.Params())
        XCTAssertEqual(a, b, "canonical encoding determinism")
        XCTAssertEqual(
            StableHash.hash(a), StableHash.hash(b), "paramsHash zero drift")
        // The identity core's key facts: strength 0, identity matrix, zero
        // offset, no hashes.
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: a) as? [String: Any])
        XCTAssertEqual(object["strength"] as? Double, 0.0)
        XCTAssertEqual(
            object["matrix"] as? [Double], [1, 0, 0, 0, 1, 0, 0, 0, 1])
        XCTAssertEqual(object["offset"] as? [Double], [0, 0, 0])
        XCTAssertEqual(object["solver"] as? String, "gaussianOT")
    }

    /// The EXPLICIT-null face (checker E2): the three optionals are PRESENT
    /// keys with null values in the default encoding — the IopCatalog key
    /// set closes over them.
    func testExplicitNullEncoding() throws {
        let json = String(
            data: ParamsCoding.encode(ColormatchModule.Params()), encoding: .utf8)!
        for key in ["sourceStatsHash", "referenceStatsHash", "effectiveSolver"] {
            XCTAssertTrue(
                json.contains("\"\(key)\""),
                "\(key) must be an encoded key (explicit null, not absent)")
        }
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        for key in ["sourceStatsHash", "referenceStatsHash", "effectiveSolver"] {
            XCTAssertTrue(
                object.keys.contains(key), "\(key) present in the decoded key set")
            // JSONSerialization materializes JSON null as NSNull (the
            // explicit-null proof — an absent key would not be in the dict).
            XCTAssertTrue(object[key] is NSNull, "\(key) encodes null")
        }
    }

    // MARK: - Serde round trip + tolerant decode

    func testSerdeRoundTripWithSolvedPayload() throws {
        var params = ColormatchModule.Params()
        params.strength = 0.75
        params.matrix = [1.1, 0.2, 0, 0, 0.9, 0.1, 0, 0, 1.05]
        params.offset = [0.01, -0.02, 0.03]
        params.sourceStatsHash = "18446744073709551615"
        params.referenceStatsHash = "12345678901234567890"
        params.effectiveSolver = .reinhard
        let data = ParamsCoding.encode(params)
        let decoded = try JSONDecoder().decode(ColormatchModule.Params.self, from: data)
        XCTAssertEqual(decoded, params)
        // Re-encode → identical bytes (the canonical closure).
        XCTAssertEqual(ParamsCoding.encode(decoded), data)
    }

    func testUnknownSolverDegradesWithoutThrowing() throws {
        // A FUTURE archive (an unknown rawValue this binary predates) read
        // by THIS binary: degrade to the default, never throw into the
        // sidecar loader (the Lut3dModule inputEncoding 款). NOTE: since
        // M5-1-02 the `.cdf` rawValue is a REGISTERED case — it decodes
        // verbatim (the additive-switch discipline).
        let json = """
        {"effectiveSolver":null,"matrix":[1,0,0,0,1,0,0,0,1],"offset":[0,0,0],
         "referenceStatsHash":null,"solver":"futureThing","sourceStatsHash":null,"strength":0}
        """
        let decoded = try JSONDecoder().decode(ColormatchModule.Params.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.solver, .gaussianOT, "unknown rawValue → the default")
        XCTAssertEqual(decoded.strength, 0)
        // The M5-1-02 additive case decodes verbatim now.
        let cdf = """
        {"solver":"cdf","strength":0.5}
        """
        let cdfDecoded = try JSONDecoder().decode(
            ColormatchModule.Params.self, from: Data(cdf.utf8))
        XCTAssertEqual(cdfDecoded.solver, .cdf)
        // Missing keys entirely → the identity defaults.
        let empty = try JSONDecoder().decode(
            ColormatchModule.Params.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, ColormatchModule.Params())
    }

    // MARK: - The additive asset keys (M5-1-02 T4, omit-nil serde)

    func testAssetKeysOmitNilPreservingP1Bytes() throws {
        // The default Params() encoding must NOT carry the asset keys
        // (omit-nil) — the P1 byte-identity core stays untouched.
        let json = String(
            data: ParamsCoding.encode(ColormatchModule.Params()), encoding: .utf8)!
        XCTAssertFalse(json.contains("assetRef"), "omit-nil: no assetRef in the default")
        XCTAssertFalse(json.contains("assetHash"), "omit-nil: no assetHash in the default")
        // A payload WITH the asset attached carries both keys and round
        // trips (L013 decimal String hashes).
        var params = ColormatchModule.Params()
        params.solver = .cdf
        params.strength = 0.8
        params.assetRef = "img.raw.lra.colormatch/00ab-3f800000.cube"
        params.assetHash = "18446744073709551615"
        let encoded = ParamsCoding.encode(params)
        let decoded = try JSONDecoder().decode(ColormatchModule.Params.self, from: encoded)
        XCTAssertEqual(decoded, params)
        XCTAssertEqual(ParamsCoding.encode(decoded), encoded)
    }

    // MARK: - The LUT arm commit faces (M5-1-02 T5, KD-3/KD-5)

    /// The in-memory resolver (the LutResolving 测试 同形).
    private final class MemoryResolver: ColormatchAssetResolving, @unchecked Sendable {
        var solution: ColorMatchCDFSolution?
        var table: [SIMD3<Float>]?
        var degradeReason: String?
        func loadCube(
            assetRef: String, expectedHash: String?
        ) -> ColormatchCubeAsset.LoadResult {
            if let degradeReason { return .degraded(reason: degradeReason) }
            guard let table else {
                return .degraded(reason: "no table in memory")
            }
            return .loaded(table: table, bytesHash: 1)
        }
        func cdfSolution(
            sourceStatsHash: String, referenceStatsHash: String
        ) -> ColorMatchCDFSolution? {
            solution
        }
    }

    /// A tiny solved solution (the identity ladder suffices for the commit
    /// faces — the numeric face is the bake/bake-golden's business).
    private static func identitySolution() -> ColorMatchCDFSolution {
        var histogram = [UInt32](repeating: 0, count: 256)
        for bin in 0..<256 { histogram[bin] = 100 }
        let stats = ColorMatchStats(
            mu: SIMD3(0.5, 0, 0), sigma: (0.02, 0, 0, 0.02, 0, 0.02),
            histograms: [histogram, histogram, histogram],
            supportLo: SIMD3(0.05, -0.4, -0.4), supportHi: SIMD3(0.95, 0.4, 0.4),
            sampleCount: 25_600)
        return ColorMatchCDFSolver.solve(source: stats, reference: stats)
    }

    func testLutArmCurvesPathBakesOncePerStrength() {
        let resolver = MemoryResolver()
        resolver.solution = Self.identitySolution()
        let module = ColormatchModule(device: nil, resolver: resolver)
        var params = ColormatchModule.Params()
        params.solver = .cdf
        params.strength = 0.5
        params.sourceStatsHash = "11"
        params.referenceStatsHash = "22"
        params.assetRef = "img.raw.lra.colormatch/x.cube"
        params.assetHash = "1"

        var piece = IOPiece()
        module.commitParams(params, into: &piece)
        XCTAssertNotNil(piece.data, "the curves path packs the LUT uniforms")
        XCTAssertEqual(module.bakeCountForTesting, 1, "the first commit bakes")

        // A strength tick: a DIFFERENT bake key → a real rebake (α folded).
        params.strength = 0.6
        var piece2 = IOPiece()
        module.commitParams(params, into: &piece2)
        XCTAssertNotNil(piece2.data)
        XCTAssertEqual(module.bakeCountForTesting, 2, "the α tick rebakes")

        // Revisiting the first strength: LRU hit (no rebake).
        params.strength = 0.5
        var piece3 = IOPiece()
        module.commitParams(params, into: &piece3)
        XCTAssertNotNil(piece3.data)
        XCTAssertEqual(module.bakeCountForTesting, 2, "the LRU serves revisits")
    }

    func testLutArmRestorePathAppliesAssetVerbatim() {
        let resolver = MemoryResolver()
        // NO session curves (the restore posture) + a table asset.
        resolver.table = [SIMD3<Float>](repeating: SIMD3(0.9, 0.1, 0.5), count: 65 * 65 * 65)
        let module = ColormatchModule(device: nil, resolver: resolver)
        var params = ColormatchModule.Params()
        params.solver = .cdf
        params.strength = 0.8
        params.sourceStatsHash = "11"
        params.referenceStatsHash = "22"
        params.assetRef = "img.raw.lra.colormatch/x.cube"
        params.assetHash = "1"
        var piece = IOPiece()
        module.commitParams(params, into: &piece)
        XCTAssertNotNil(piece.data, "the asset path packs uniforms (table verbatim)")
        XCTAssertEqual(module.bakeCountForTesting, 0, "the restore path never bakes")
    }

    func testLutArmDegradeAndMissingAssetBlit() {
        let resolver = MemoryResolver()
        resolver.degradeReason = "hash mismatch"
        let module = ColormatchModule(device: nil, resolver: resolver)
        var params = ColormatchModule.Params()
        params.solver = .cdf
        params.strength = 0.7
        params.sourceStatsHash = "11"
        params.referenceStatsHash = "22"
        params.assetRef = "img.raw.lra.colormatch/x.cube"
        var piece = IOPiece()
        module.commitParams(params, into: &piece)
        XCTAssertNil(piece.data, "the degraded asset → the blit face")

        // The G5 extension state: assetRef nil → blit.
        let noAssetModule = ColormatchModule(device: nil, resolver: resolver)
        var params2 = params
        params2.assetRef = nil
        var piece2 = IOPiece()
        noAssetModule.commitParams(params2, into: &piece2)
        XCTAssertNil(piece2.data, "assetRef nil → the blit face")
    }

    // MARK: - The G2 chain assertion (shared tetrahedral sampling)

    func testLutArmOutputMatchesTheSharedTetrahedralSampling() async throws {
        // The G2 extension: the colormatch LUT arm output == the SAME
        // table through the shared lut3d_tetrahedral sampling path (the
        // CPU double-write of the kernel's lattice map + branch table).
        let metal = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "no Metal GPU")
        let context = try MetalContext()
        try await context.registerDefaultLibrary(in: ColormatchKernel.metalBundle)

        // A known non-trivial table.
        let level = ColorMatchBake.latticeSize
        var table = [SIMD3<Float>](repeating: .zero, count: level * level * level)
        for index in 0..<table.count {
            let x = Float(index % level) / Float(level - 1)
            let y = Float((index / level) % level) / Float(level - 1)
            let z = Float(index / (level * level)) / Float(level - 1)
            table[index] = SIMD3(
                x * 0.8 + 0.1 * z, y * 0.9 + 0.05 * x, 0.2 + 0.6 * z)
        }
        let resolver = MemoryResolver()
        resolver.table = table
        let module = ColormatchModule(device: metal, resolver: resolver)
        var params = ColormatchModule.Params()
        params.solver = .cdf
        params.strength = 0.9
        params.sourceStatsHash = "11"
        params.referenceStatsHash = "22"
        params.assetRef = "img.raw.lra.colormatch/x.cube"
        var piece = IOPiece()
        module.commitParams(params, into: &piece)
        XCTAssertNotNil(piece.data)

        // The probe plane (in-domain grays + mild colors — the lattice
        // interior; the domain-clamp edge is the kernel's own face).
        let width = 8, height = 6
        var plane = [SIMD4<Float>]()
        for y in 0..<height {
            for x in 0..<width {
                let v = Float(x * y) / Float(width * height)
                plane.append(SIMD4(0.1 + 0.8 * v, 0.2 + 0.6 * (1 - v), 0.3 + 0.4 * v, 1))
            }
        }
        func makeTexture(write pixels: [SIMD4<Float>]) throws -> any MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .shared
            let texture = try XCTUnwrap(metal.makeTexture(descriptor: descriptor))
            pixels.withUnsafeBytes { raw in
                texture.replace(
                    region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                        size: MTLSize(width: width, height: height, depth: 1)),
                    mipmapLevel: 0, withBytes: raw.baseAddress!,
                    bytesPerRow: width * MemoryLayout<SIMD4<Float>>.stride)
            }
            return texture
        }
        let input = try makeTexture(write: plane)
        let output = try makeTexture(write: [])
        try await module.process(
            input: input, output: output,
            roiIn: ROI(x: 0, y: 0, width: width, height: height, scale: 1),
            roiOut: ROI(x: 0, y: 0, width: width, height: height, scale: 1),
            piece: &piece, metal: context)
        // L014 fence + readback.
        let fence = context.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
        var readback = [SIMD4<Float>](repeating: .zero, count: width * height)
        readback.withUnsafeMutableBytes { raw in
            output.getBytes(
                raw.baseAddress!, bytesPerRow: width * MemoryLayout<SIMD4<Float>>.stride,
                from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: width, height: height, depth: 1)),
                mipmapLevel: 0)
        }

        // The CPU reference: the SAME tetrahedral branch table (the shared
        // lut3d path's double-write) at each pixel's position.
        let lut = CubeLut(
            kind: .lut3d(size: level), domainMin: SIMD3(0, 0, 0), domainMax: SIMD3(1, 1, 1),
            data: table)
        for (index, pixel) in readback.enumerated() {
            let position = SIMD3<Double>(
                Double(plane[index].x), Double(plane[index].y), Double(plane[index].z))
            let expected = Lut3dModule.sampleTable(lut, position: position)
            let drift = max(
                abs(Double(pixel.x) - expected.x),
                abs(Double(pixel.y) - expected.y),
                abs(Double(pixel.z) - expected.z))
            XCTAssertLessThanOrEqual(
                drift, 1e-5, "the LUT arm diverged from the shared sampler at \(index)")
        }
    }

    // MARK: - The identity-blit commit path

    func testIdentityCommitCarriesNoUniforms() {
        let module = ColormatchModule()
        var piece = IOPiece()
        module.commitParams(ColormatchModule.Params(), into: &piece)
        XCTAssertNil(piece.data, "strength 0 → no uniforms (the blit face)")
        XCTAssertEqual(
            piece.paramsHash,
            StableHash.hash(ParamsCoding.encode(ColormatchModule.Params())))

        // The unsolved face: strength > 0 but the hash pair missing → still
        // the identity (a hand-edited params blob cannot half-render).
        var unsolved = ColormatchModule.Params()
        unsolved.strength = 1.0
        var piece2 = IOPiece()
        module.commitParams(unsolved, into: &piece2)
        XCTAssertNil(piece2.data, "missing stats hashes → the unsolved blit face")
    }

    func testSolvedCommitPacksUniformsAndDistinctHash() {
        let module = ColormatchModule()
        var solved = ColormatchModule.Params()
        solved.strength = 1.0
        solved.matrix = [1.2, 0.1, 0, 0, 0.8, 0.1, 0, 0, 1.1]
        solved.offset = [0.01, 0.0, -0.01]
        solved.sourceStatsHash = "42"
        solved.referenceStatsHash = "43"
        var piece = IOPiece()
        module.commitParams(solved, into: &piece)
        XCTAssertNotNil(piece.data, "the non-identity state packs uniforms")
        let identityHash = StableHash.hash(ParamsCoding.encode(ColormatchModule.Params()))
        XCTAssertNotEqual(piece.paramsHash, identityHash, "solved params ≠ identity hash")
        // And a params change flips the hash (the cache-identity face).
        var other = solved
        other.strength = 0.5
        var piece2 = IOPiece()
        module.commitParams(other, into: &piece2)
        XCTAssertNotEqual(piece.paramsHash, piece2.paramsHash)
    }
}

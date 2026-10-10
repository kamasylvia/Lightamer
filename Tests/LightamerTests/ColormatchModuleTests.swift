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
        // A future `.cdf` archive (M5-1-02's additive case) read by THIS
        // binary: the rawValue is unknown → degrade to the default, never
        // throw into the sidecar loader (the Lut3dModule inputEncoding 款).
        let json = """
        {"effectiveSolver":null,"matrix":[1,0,0,0,1,0,0,0,1],"offset":[0,0,0],
         "referenceStatsHash":null,"solver":"cdf","sourceStatsHash":null,"strength":0}
        """
        let decoded = try JSONDecoder().decode(ColormatchModule.Params.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.solver, .gaussianOT, "unknown rawValue → the default")
        XCTAssertEqual(decoded.strength, 0)
        // Missing keys entirely → the identity defaults.
        let empty = try JSONDecoder().decode(
            ColormatchModule.Params.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, ColormatchModule.Params())
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

@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// PanoProvenanceTests (Plan M5-3-01 T4; KD-8; the MertensProvenanceTests
// LIB-face precedent) — the provenance vocabulary mirror for the additive
// pano kind: the two Kind enums' raw values aligned one-to-one, the OLD
// MergeParams JSON byte-identical (the additive encodeIfPresent zero-drift
// lock), the new pano fields' absence/presence semantics, and the
// independent pano algorithm identity constants.
// ─────────────────────────────────────────────────────────────────────────────

final class PanoProvenanceTests: XCTestCase {

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    /// The pre-Mertens golden: a default (11-field-era, 7-key materialized)
    /// MergeParams serializes EXACTLY as before every additive field —
    /// every old sidecar re-encodes byte-identical (the KD-7 zero-drift
    /// lock; synthesized Codable omits nil optionals).
    private static let legacyParamsJSON = """
        {
          "allowApertureISOOverride" : false,
          "clipGate" : 0.995,
          "deGhost" : true,
          "floorGate" : 0.001,
          "sigma" : 0.2,
          "tag" : "hdr",
          "weightNoiseFloor" : false
        }
        """

    func testKindRawValuesMirrorElementwiseAcrossEnums() {
        let serviceKinds = StackMergeService.MergeKind.allCases.map(\.rawValue)
        let provenanceKinds = SidecarProvenance.Kind.allCases.map(\.rawValue)
        XCTAssertEqual(serviceKinds, provenanceKinds,
            "the two Kind vocabularies must stay aligned one-to-one")
        XCTAssertTrue(serviceKinds.contains("pano-merge"))
    }

    func testLegacyMergeParamsEncodesByteIdentical() throws {
        let params = StackMergeService.MergeParams()
        let data = try Self.encoder.encode(params)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), Self.legacyParamsJSON)
    }

    func testLegacyJSONDecodesAndReencodesByteIdentical() throws {
        let legacy = Self.legacyParamsJSON.data(using: .utf8)!
        let params = try JSONDecoder().decode(StackMergeService.MergeParams.self, from: legacy)
        XCTAssertNil(params.panoCanvas)
        XCTAssertNil(params.panoGains)
        XCTAssertNil(params.panoCrop)
        let reencoded = try Self.encoder.encode(params)
        XCTAssertEqual(String(decoding: reencoded, as: UTF8.self), Self.legacyParamsJSON,
            "a decoded old document must re-encode byte-identical")
    }

    func testPanoFieldsEncodeOnlyWhenPresent() throws {
        var params = StackMergeService.MergeParams()
        params.panoCanvas = [12000, 9000]
        params.panoGains = [1.0, 1.1]
        params.panoCrop = [0, 0, 11999, 8999]
        let data = try Self.encoder.encode(params)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"panoCanvas\""))
        XCTAssertTrue(json.contains("\"panoGains\""))
        XCTAssertTrue(json.contains("\"panoCrop\""))
        let back = try JSONDecoder().decode(StackMergeService.MergeParams.self, from: data)
        XCTAssertEqual(back.panoCanvas, [12000, 9000])
        XCTAssertEqual(back.panoGains, [1.0, 1.1])
        XCTAssertEqual(back.panoCrop, [0, 0, 11999, 8999])
        // One set field appears; the others stay absent.
        var one = StackMergeService.MergeParams()
        one.panoGains = [1.0, 0.9]
        let oneJSON = String(decoding: try Self.encoder.encode(one), as: UTF8.self)
        XCTAssertFalse(oneJSON.contains("panoCanvas"))
        XCTAssertTrue(oneJSON.contains("\"panoGains\" : [\n    1,\n    0.9\n  ]"))
        XCTAssertFalse(oneJSON.contains("panoCrop"))
    }

    func testPanoAlgorithmIdentityConstants() {
        XCTAssertEqual(ProvenanceReplay.panoAlgorithmName, "spherical-feature-panorama")
        XCTAssertEqual(ProvenanceReplay.panoImplementationVersion, "1")
        // Independent from the HDR and Mertens identities (the three
        // algorithms evolve without entangling each other's replay
        // warnings).
        XCTAssertNotEqual(ProvenanceReplay.panoAlgorithmName, ProvenanceReplay.hdrAlgorithmName)
        XCTAssertNotEqual(ProvenanceReplay.panoAlgorithmName, ProvenanceReplay.mertensAlgorithmName)
        XCTAssertEqual(ProvenanceReplay.hdrAlgorithmName, "robertson02-mtb")
        XCTAssertEqual(ProvenanceReplay.mertensAlgorithmName, "mertens-exposure-fusion")
    }
}

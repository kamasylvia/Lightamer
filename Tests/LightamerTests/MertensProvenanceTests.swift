@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// MertensProvenanceTests (Plan M5-2-01 T2; the ProvenanceV4Tests LIB-face
// precedent) — the provenance vocabulary mirror for the additive Mertens
// kind: the two Kind enums' raw values aligned one-to-one, the OLD
// MergeParams JSON byte-identical (the additive encodeIfPresent zero-drift
// lock), the new fields' absence/presence semantics, and the independent
// Mertens algorithm identity constants (KD-5).
// ─────────────────────────────────────────────────────────────────────────────

final class MertensProvenanceTests: XCTestCase {

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    /// The pre-Mertens golden: a default (11-field-era, 7-key materialized)
    /// MergeParams serializes EXACTLY as before the additive fields —
    /// every old sidecar re-encodes byte-identical (the KD-4 zero-drift
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
        XCTAssertTrue(serviceKinds.contains("hdr-merge-mertens"))
    }

    func testLegacyMergeParamsEncodesByteIdentical() throws {
        let params = StackMergeService.MergeParams()
        let data = try Self.encoder.encode(params)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), Self.legacyParamsJSON)
    }

    func testLegacyJSONDecodesAndReencodesByteIdentical() throws {
        let legacy = Self.legacyParamsJSON.data(using: .utf8)!
        let params = try JSONDecoder().decode(StackMergeService.MergeParams.self, from: legacy)
        XCTAssertNil(params.mertensDeghost)
        XCTAssertNil(params.mertensLevels)
        let reencoded = try Self.encoder.encode(params)
        XCTAssertEqual(String(decoding: reencoded, as: UTF8.self), Self.legacyParamsJSON,
            "a decoded old document must re-encode byte-identical")
    }

    func testNewFieldsEncodeOnlyWhenPresent() throws {
        var params = StackMergeService.MergeParams()
        params.mertensDeghost = "medium"
        params.mertensLevels = 5
        let data = try Self.encoder.encode(params)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"mertensDeghost\""))
        XCTAssertTrue(json.contains("\"mertensLevels\""))
        let back = try JSONDecoder().decode(StackMergeService.MergeParams.self, from: data)
        XCTAssertEqual(back.mertensDeghost, "medium")
        XCTAssertEqual(back.mertensLevels, 5)
        // A single set field appears; the other stays absent.
        var one = StackMergeService.MergeParams()
        one.mertensLevels = 3
        let oneJSON = String(
            decoding: try Self.encoder.encode(one), as: UTF8.self)
        XCTAssertFalse(oneJSON.contains("mertensDeghost"))
        XCTAssertTrue(oneJSON.contains("\"mertensLevels\" : 3"))
    }

    func testMertensAlgorithmIdentityConstants() {
        XCTAssertEqual(ProvenanceReplay.mertensAlgorithmName, "mertens-exposure-fusion")
        XCTAssertEqual(ProvenanceReplay.mertensImplementationVersion, "1")
        // Independent from the HDR identity (the two algorithms evolve
        // without entangling each other's replay warnings).
        XCTAssertNotEqual(ProvenanceReplay.mertensAlgorithmName, ProvenanceReplay.hdrAlgorithmName)
        XCTAssertEqual(ProvenanceReplay.hdrAlgorithmName, "robertson02-mtb")
    }
}

@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// DrtRecordTests (Plan M2-6-1 T1, AC#1/#2) — the DRT record schema face:
//
//   1. ENUM COUNTS: CaseIterable 2/7/6/7 (method/eotf/encoding/limiting).
//   2. RAWVALUE TERMINAL FORMS: the Alcedo drt_node_model.cpp ToJson
//      spellings (aces_2_0 / open_drt / p3_d65 / gamma_2_2 …) — the working
//      assumption "hpp name snake_case" was corrected at execution; these
//      assertions pin the corrected forms (DECISIONS §D1).
//   3. DEFAULTS: every field vs the hpp payload defaults.
//   4. LINKAGE TABLE: legalEOTFs space-for-space vs the literal table;
//      every space non-empty; linear/gamma18 illegal everywhere;
//      isHdrEncoding exact on all seven values.
//   5. CODABLE: canonical sortedKeys byte stability (two encodes byte-equal
//      — L013) + round-trip equality + tolerant partial decode.
//   6. STABLEHASH: same value → same hash; one-field change → new hash.
//   7. JSON KEY SETS: the 53 detailed keys and the 13 record keys match the
//      hpp field-name inventories exactly (machine check vs hpp :45-98 /
//      :101-115).
//   8. PRISTINE JUDGMENT: isDrtRecordDefault == the default record, and it
//      is NOT a render-identity claim (documented semantics, KD-4).
//
// Core-level suite (LAYERS bundle — PipelineDocumentTests precedent).
// ─────────────────────────────────────────────────────────────────────────────

final class DrtRecordTests: XCTestCase {

    // MARK: - 1: enum counts

    func testEnumCaseCountsAreTwoSevenSixSeven() {
        XCTAssertEqual(DrtMethod.allCases.count, 2)
        XCTAssertEqual(DrtEotf.allCases.count, 7)
        XCTAssertEqual(DrtEncodingSpace.allCases.count, 6)
        XCTAssertEqual(DrtLimitingSpace.allCases.count, 7)
    }

    // MARK: - 2: rawValue terminal forms (Alcedo cpp ToJson)

    func testMethodRawValuesFollowTheAlcedoToJsonForms() {
        XCTAssertEqual(DrtMethod.aces20.rawValue, "aces_2_0")
        XCTAssertEqual(DrtMethod.opendrt.rawValue, "open_drt")
    }

    func testEotfRawValuesFollowTheAlcedoToJsonForms() {
        XCTAssertEqual(DrtEotf.linear.rawValue, "linear")
        XCTAssertEqual(DrtEotf.st2084.rawValue, "st2084")
        XCTAssertEqual(DrtEotf.hlg.rawValue, "hlg")
        XCTAssertEqual(DrtEotf.gamma26.rawValue, "gamma_2_6")
        XCTAssertEqual(DrtEotf.bt1886.rawValue, "bt1886")
        XCTAssertEqual(DrtEotf.gamma22.rawValue, "gamma_2_2")
        XCTAssertEqual(DrtEotf.gamma18.rawValue, "gamma_1_8")
    }

    func testSpaceRawValuesFollowTheAlcedoToJsonFormsPlusDeclaredExtensions() {
        // hpp/cpp-backed three:
        XCTAssertEqual(DrtEncodingSpace.rec709.rawValue, "rec709")
        XCTAssertEqual(DrtEncodingSpace.rec2020.rawValue, "rec2020")
        XCTAssertEqual(DrtEncodingSpace.p3d65.rawValue, "p3_d65")
        // Beyond-hpp extensions (m4 deviation — self-coined spellings):
        XCTAssertEqual(DrtEncodingSpace.p3d60.rawValue, "p3_d60")
        XCTAssertEqual(DrtEncodingSpace.p3dci.rawValue, "p3_dci")
        XCTAssertEqual(DrtEncodingSpace.xyz.rawValue, "xyz")
        // Limiting: hpp-backed three + the four extensions.
        XCTAssertEqual(DrtLimitingSpace.rec709.rawValue, "rec709")
        XCTAssertEqual(DrtLimitingSpace.rec2020.rawValue, "rec2020")
        XCTAssertEqual(DrtLimitingSpace.p3d65.rawValue, "p3_d65")
        XCTAssertEqual(DrtLimitingSpace.p3d60.rawValue, "p3_d60")
        XCTAssertEqual(DrtLimitingSpace.p3dci.rawValue, "p3_dci")
        XCTAssertEqual(DrtLimitingSpace.proPhoto.rawValue, "pro_photo")
        XCTAssertEqual(DrtLimitingSpace.adobeRGB.rawValue, "adobe_rgb")
    }

    // MARK: - 3: defaults (hpp :46-98 / :101-115 field-by-field)

    func testDetailedParamsDefaultsMatchTheHppPayload() {
        let p = OpenDrtDetailedParams()
        // tn ×9
        XCTAssertEqual(p.tnCon, 1.66)
        XCTAssertEqual(p.tnSh, 0.5)
        XCTAssertEqual(p.tnToe, 0.003)
        XCTAssertEqual(p.tnOff, 0.005)
        XCTAssertEqual(p.tnHcon, 0.0)
        XCTAssertEqual(p.tnHconPv, 1.0)
        XCTAssertEqual(p.tnHconSt, 4.0)
        XCTAssertEqual(p.tnLcon, 0.0)
        XCTAssertEqual(p.tnLconW, 0.5)
        // cwp_lm
        XCTAssertEqual(p.cwpLm, 0.25)
        // rs ×3
        XCTAssertEqual(p.rsSa, 0.35)
        XCTAssertEqual(p.rsRw, 0.25)
        XCTAssertEqual(p.rsBw, 0.55)
        // pt_lml ×4
        XCTAssertEqual(p.ptLml, 0.25)
        XCTAssertEqual(p.ptLmlR, 0.5)
        XCTAssertEqual(p.ptLmlG, 0.0)
        XCTAssertEqual(p.ptLmlB, 0.1)
        // pt_lmh ×3
        XCTAssertEqual(p.ptLmh, 0.25)
        XCTAssertEqual(p.ptLmhR, 0.5)
        XCTAssertEqual(p.ptLmhB, 0.0)
        // ptl ×3
        XCTAssertEqual(p.ptlC, 0.06)
        XCTAssertEqual(p.ptlM, 0.08)
        XCTAssertEqual(p.ptlY, 0.06)
        // ptm ×6
        XCTAssertEqual(p.ptmLow, 0.4)
        XCTAssertEqual(p.ptmLowRng, 0.25)
        XCTAssertEqual(p.ptmLowSt, 0.5)
        XCTAssertEqual(p.ptmHigh, -0.8)
        XCTAssertEqual(p.ptmHighRng, 0.35)
        XCTAssertEqual(p.ptmHighSt, 0.4)
        // brl ×6
        XCTAssertEqual(p.brl, 0.0)
        XCTAssertEqual(p.brlR, -2.5)
        XCTAssertEqual(p.brlG, -1.5)
        XCTAssertEqual(p.brlB, -1.5)
        XCTAssertEqual(p.brlRng, 0.5)
        XCTAssertEqual(p.brlSt, 0.35)
        // brlp ×4
        XCTAssertEqual(p.brlp, -0.5)
        XCTAssertEqual(p.brlpR, -1.25)
        XCTAssertEqual(p.brlpG, -1.25)
        XCTAssertEqual(p.brlpB, -0.25)
        // hc ×2
        XCTAssertEqual(p.hcR, 1.0)
        XCTAssertEqual(p.hcRRng, 0.3)
        // hs ×12
        XCTAssertEqual(p.hsR, 0.6)
        XCTAssertEqual(p.hsRRng, 0.6)
        XCTAssertEqual(p.hsG, 0.35)
        XCTAssertEqual(p.hsGRng, 1.0)
        XCTAssertEqual(p.hsB, 0.66)
        XCTAssertEqual(p.hsBRng, 1.0)
        XCTAssertEqual(p.hsC, 0.25)
        XCTAssertEqual(p.hsCRng, 1.0)
        XCTAssertEqual(p.hsM, 0.0)
        XCTAssertEqual(p.hsMRng, 1.0)
        XCTAssertEqual(p.hsY, 0.0)
        XCTAssertEqual(p.hsYRng, 1.0)
    }

    func testRecordDefaultsMatchTheHppPayload() {
        let r = DrtRecord()
        XCTAssertEqual(r.method, .opendrt)
        XCTAssertEqual(r.encodingSpace, .rec709)
        XCTAssertEqual(r.encodingEotf, .gamma22)
        XCTAssertEqual(r.limitingSpace, .rec709)
        XCTAssertEqual(r.peakLuminance, 100.0)
        XCTAssertEqual(r.lookPreset, "standard")
        XCTAssertEqual(r.tonescalePreset, "use_look_preset")
        XCTAssertEqual(r.creativeWhite, "use_look_preset")
        XCTAssertEqual(r.creativeWhiteLimit, 0.25)
        XCTAssertEqual(r.displayGreyLuminance, 10.0)
        XCTAssertEqual(r.hdrGreyBoost, 0.13)
        XCTAssertEqual(r.hdrPurity, 0.5)
        XCTAssertEqual(r.parameters, OpenDrtDetailedParams())
    }

    // MARK: - 4: linkage table + HDR judgment (AC#2)

    func testLegalEOTFsMatchTheLiteralTable() {
        // FEATURE-MAP §5 row-for-row (KD-1 literal table).
        XCTAssertEqual(Set(legalEOTFs(for: .rec709)), [.bt1886, .gamma22])
        XCTAssertEqual(Set(legalEOTFs(for: .p3d65)), [.gamma22, .st2084])
        XCTAssertEqual(Set(legalEOTFs(for: .p3d60)), [.gamma26])
        XCTAssertEqual(Set(legalEOTFs(for: .p3dci)), [.gamma26])
        XCTAssertEqual(Set(legalEOTFs(for: .xyz)), [.gamma26])
        XCTAssertEqual(Set(legalEOTFs(for: .rec2020)), [.st2084, .hlg])
    }

    func testEverySpaceHasANonEmptyLegalSetAndLinearGamma18AreAlwaysIllegal() {
        for space in DrtEncodingSpace.allCases {
            let legal = legalEOTFs(for: space)
            XCTAssertFalse(legal.isEmpty, "\(space.rawValue) has no legal EOTF")
            XCTAssertFalse(legal.contains(.linear), "linear must be illegal for \(space.rawValue)")
            XCTAssertFalse(legal.contains(.gamma18), "gamma18 must be illegal for \(space.rawValue)")
            // Every legal value IS a model-layer EOTF (no phantom members).
            for eotf in legal {
                XCTAssertTrue(DrtEotf.allCases.contains(eotf))
            }
        }
    }

    func testIsHdrEncodingIsExactlySt2084AndHlg() {
        for eotf in DrtEotf.allCases {
            XCTAssertEqual(isHdrEncoding(eotf), eotf == .st2084 || eotf == .hlg)
        }
        XCTAssertTrue(isHdrEncoding(.st2084))
        XCTAssertTrue(isHdrEncoding(.hlg))
        XCTAssertFalse(isHdrEncoding(.linear))
        XCTAssertFalse(isHdrEncoding(.gamma26))
        XCTAssertFalse(isHdrEncoding(.bt1886))
        XCTAssertFalse(isHdrEncoding(.gamma22))
        XCTAssertFalse(isHdrEncoding(.gamma18))
    }

    // MARK: - 5: Codable — canonical bytes + round-trip + tolerance

    private var canonicalEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }

    func testCanonicalEncodingIsByteStableAcrossEncodes() throws {
        var record = DrtRecord()
        record.peakLuminance = 480
        record.encodingSpace = .rec2020
        record.encodingEotf = .st2084
        record.parameters.tnCon = 1.42
        let a = try canonicalEncoder.encode(record)
        let b = try canonicalEncoder.encode(record)
        XCTAssertEqual(a, b, "sortedKeys canonical bytes must be deterministic (L013)")
    }

    func testCodableRoundTripPreservesEveryField() throws {
        var record = DrtRecord()
        record.method = .aces20
        record.encodingSpace = .p3d65
        record.encodingEotf = .st2084
        record.limitingSpace = .p3d60
        record.peakLuminance = 1000
        record.lookPreset = "umbra"
        record.tonescalePreset = "umbra_tonescale"
        record.creativeWhite = "d50"
        record.creativeWhiteLimit = 0.4
        record.displayGreyLuminance = 12
        record.hdrGreyBoost = 0.2
        record.hdrPurity = 0.75
        record.parameters.hsB = 0.9
        let data = try canonicalEncoder.encode(record)
        let decoded = try JSONDecoder().decode(DrtRecord.self, from: data)
        XCTAssertEqual(decoded, record)
    }

    func testPartialDecodeFallsBackToDefaults() throws {
        // A hand-edited/partial record: only two keys present — the tolerant
        // decode fills the rest from the hpp defaults (KD-1 posture).
        let json = Data("{\"encoding_eotf\":\"st2084\",\"method\":\"open_drt\"}".utf8)
        let decoded = try JSONDecoder().decode(DrtRecord.self, from: json)
        XCTAssertEqual(decoded.method, .opendrt)
        XCTAssertEqual(decoded.encodingEotf, .st2084)
        XCTAssertEqual(decoded.encodingSpace, .rec709)
        XCTAssertEqual(decoded.parameters.tnCon, 1.66)
    }

    // MARK: - 6: stableHash stability + sensitivity

    func testStableHashIsDeterministicForTheSameValue() {
        let a = DrtRecord().stableHash()
        let b = DrtRecord().stableHash()
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, 0)
    }

    func testStableHashChangesWhenAnySampledFieldChanges() {
        let baseline = DrtRecord().stableHash()
        // One sample per structural group: top-level scalar, enum, nested param.
        var r1 = DrtRecord(); r1.peakLuminance = 200
        XCTAssertNotEqual(r1.stableHash(), baseline)
        var r2 = DrtRecord(); r2.encodingEotf = .bt1886
        XCTAssertNotEqual(r2.stableHash(), baseline)
        var r3 = DrtRecord(); r3.parameters.hsC = 0.5
        XCTAssertNotEqual(r3.stableHash(), baseline)
        // EOTF switch changes the record hash (KD-6 m1: the tail plane's key
        // rides recordHash, so an EOTF switch re-runs only the tail).
        var r4 = DrtRecord(); r4.encodingEotf = .st2084; r4.encodingSpace = .rec2020
        XCTAssertNotEqual(r4.stableHash(), baseline)
    }

    // MARK: - 7: JSON key inventories vs hpp

    func testDetailedParamsJSONKeySetMatchesTheHppFieldInventory() throws {
        let data = try canonicalEncoder.encode(OpenDrtDetailedParams())
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object.count, 53, "detailed group must carry exactly 53 fields")
        // hpp :45-98 spelling inventory (53 names, grouped as in the header).
        let hppKeys: Set<String> = [
            "tn_con", "tn_sh", "tn_toe", "tn_off", "tn_hcon", "tn_hcon_pv",
            "tn_hcon_st", "tn_lcon", "tn_lcon_w", "cwp_lm", "rs_sa", "rs_rw",
            "rs_bw", "pt_lml", "pt_lml_r", "pt_lml_g", "pt_lml_b", "pt_lmh",
            "pt_lmh_r", "pt_lmh_b", "ptl_c", "ptl_m", "ptl_y", "ptm_low",
            "ptm_low_rng", "ptm_low_st", "ptm_high", "ptm_high_rng",
            "ptm_high_st", "brl", "brl_r", "brl_g", "brl_b", "brl_rng",
            "brl_st", "brlp", "brlp_r", "brlp_g", "brlp_b", "hc_r",
            "hc_r_rng", "hs_r", "hs_r_rng", "hs_g", "hs_g_rng", "hs_b",
            "hs_b_rng", "hs_c", "hs_c_rng", "hs_m", "hs_m_rng", "hs_y",
            "hs_y_rng",
        ]
        XCTAssertEqual(Set(object.keys), hppKeys)
    }

    func testRecordJSONKeySetMatchesTheHppPayloadInventory() throws {
        let data = try canonicalEncoder.encode(DrtRecord())
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // hpp :101-115 — the 12 top-level fields + the nested parameters
        // object (13 keys total; Alcedo's extra "open_drt" nesting level is
        // an Alcedo-serialization detail Lightamer flattens — our record IS
        // the payload).
        let expectedKeys: Set<String> = [
            "method", "encoding_space", "encoding_eotf", "limiting_space",
            "peak_luminance", "look_preset", "tonescale_preset",
            "creative_white", "creative_white_limit", "display_grey_luminance",
            "hdr_grey_boost", "hdr_purity", "parameters",
        ]
        XCTAssertEqual(Set(object.keys), expectedKeys)
        let params = try XCTUnwrap(object["parameters"] as? [String: Any])
        XCTAssertEqual(params.count, 53)
    }

    // MARK: - 8: pristine judgment

    func testIsDrtRecordDefaultIsFullEqualityNotRenderIdentity() {
        XCTAssertTrue(isDrtRecordDefault(DrtRecord()))
        var changed = DrtRecord()
        changed.parameters.brlG = -1.4
        XCTAssertFalse(isDrtRecordDefault(changed))
        var space = DrtRecord()
        space.encodingSpace = .rec2020
        XCTAssertFalse(isDrtRecordDefault(space))
    }
}

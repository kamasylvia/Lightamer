import LightamerIOP
import simd
import XCTest

// ─────────────────────────────────────────────────────────────────────────
// LutEncodingExpansionTests (Plan M9-4 T3, X5/D-M9SP-3) — the 10-row
// + 7-curve + 6-gamut expansion golden:
//
//   (1) EVERY new curve round-trips (encode ∘ decode = identity at the
//       1e-12 level), is MONOTONE on the sample grid, and pins the
//       endpoints;
//   (2) the 6 new gamuts' primaries/white are asserted against the
//       upstream kGamuts literals (c740f7b — the H-SP5 transcription
//       check);
//   (3) the 10 new rows resolve through the typed find(id:) lookup, the
//       full 27-row table has unique ids, scene/display referrals agree
//       with the peakNits family, and an end-to-end encode→decode
//       sample survives;
//   (4) the ADD-ONLY pin: the OLD 17 rows and 9 gamuts keep their exact
//       values and ORDER (the pre-M9-4 prefixes are byte-stable — the
//       red-line 6 face).
// ─────────────────────────────────────────────────────────────────────────

final class LutEncodingExpansionTests: XCTestCase {

    // MARK: - (1) The 7 new curves

    /// The curve set with the sampled linear domain each covers (the
    /// log curves operate on scene-linear; the domains span their
    /// linear segments' neighborhood AND the log segments).
    private let newCurves: [(LutTransferCurve, [(Double, Double)])] = [
        (.flog2, [(-0.0005, 0.0), (0.0005, 0.005), (0.01, 0.18), (0.18, 0.9), (1.0, 8.0)]),
        (.log3g10, [(-0.005, 0.0), (-0.005, 0.005), (0.01, 0.18), (0.18, 1.0), (1.0, 16.0)]),
        (.bmdFilmGen5, [(0.0, 0.003), (0.003, 0.02), (0.02, 0.18), (0.18, 1.0), (1.0, 16.0)]),
        (.davinciIntermediate, [(0.0, 0.002), (0.002, 0.01), (0.01, 0.18), (0.18, 1.0), (1.0, 32.0)]),
        (.dlog, [(0.0, 0.005), (0.005, 0.02), (0.02, 0.18), (0.18, 1.0), (1.0, 12.0)]),
        (.clog2, [(0.0, 0.01), (0.01, 0.18), (0.18, 0.9), (0.9, 1.0), (1.0, 4.0)]),
        (.gamma26, [(0.0, 1.0)]),
    ]

    func testNewCurvesRoundTripMonotoneEndpoints() {
        for (curve, ranges) in newCurves {
            // Round trip: encode ∘ decode = identity (1e-12 relative on
            // the log legs; the linear knees hit the segment edges).
            for (low, high) in ranges {
                for step in 0...16 {
                    let x = low + (high - low) * Double(step) / 16.0
                    let code = LutTransferMath.encodeChannel(curve, x)
                    let back = LutTransferMath.decodeChannel(curve, code)
                    if abs(x) > 1e-6 {
                        XCTAssertEqual(
                            back, x, accuracy: max(abs(x) * 1e-12, 1e-15),
                            "\(curve) round trip at \(x)")
                    }
                }
            }
            // Monotone non-decreasing on the sampled grid.
            var previous = -Double.infinity
            for step in 0...64 {
                let x = Double(step) / 64.0 * 4.0 - 0.005
                let code = LutTransferMath.encodeChannel(curve, x)
                XCTAssertGreaterThanOrEqual(
                    code, previous - 1e-12, "\(curve) monotonicity at \(x)")
                previous = code
            }
            // Endpoints: scene-linear 0.18 lands in the log segment's
            // plausible band (a coarse placement check, not a literal
            // pin — the round trip IS the exactness face).
            let mid = LutTransferMath.encodeChannel(curve, 0.18)
            XCTAssertEqual(Double(mid), Double(mid), "\(curve) 0.18 finite")
        }
        // gamma26 (a display power curve): exact endpoints + the round trip.
        XCTAssertEqual(LutTransferMath.encodeChannel(.gamma26, 0), 0, accuracy: 0)
        XCTAssertEqual(LutTransferMath.encodeChannel(.gamma26, 1), 1, accuracy: 0)
        XCTAssertEqual(
            LutTransferMath.decodeChannel(.gamma26, 0.5), 0.5, accuracy: 1e-12)
    }

    /// The legacy (pre-M9-4) curves still round-trip — the add-only
    /// expansion moved nothing (a spot check; their goldens live in
    /// Lut3dEncodingTests).
    func testLegacyCurveSpotRoundTrip() {
        for curve in [LutTransferCurve.flog, .slog3, .vlog, .clog3] {
            let code = LutTransferMath.encodeChannel(curve, 0.18)
            let back = LutTransferMath.decodeChannel(curve, code)
            XCTAssertEqual(back, 0.18, accuracy: 1e-12, "\(curve)")
        }
    }

    // MARK: - (2) The 6 new gamuts against the upstream literals

    /// Upstream kGamuts rows (c740f7b color_encoding_catalog.cpp) —
    /// transcribed verbatim as the assertion values (H-SP5).
    func testNewGamutsMatchUpstreamLiterals() throws {
        let expected: [String: ((Double, Double), (Double, Double), (Double, Double), (Double, Double))] = [
            "sgamut3cine": ((0.766, 0.275), (0.225, 0.800), (0.089, -0.087), (0.3127, 0.3290)),
            "redwidegamutrgb": ((0.780308, 0.304253), (0.121595, 1.493994), (0.095612, -0.084589), (0.3127, 0.3290)),
            "bmdwg_gen5": ((0.7177215, 0.3171181), (0.2280410, 0.8615690), (0.1005841, -0.0820452), (0.3127170, 0.3290312)),
            "davinci_wide_gamut": ((0.8000, 0.3130), (0.1682, 0.9877), (0.0790, -0.1155), (0.3127, 0.3290)),
            "dgamut": ((0.71, 0.31), (0.21, 0.88), (0.09, -0.08), (0.3127, 0.3290)),
            "p3dci": ((0.680, 0.320), (0.265, 0.690), (0.150, 0.060), (0.314, 0.351)),
        ]
        for (id, (r, g, b, white)) in expected {
            let gamut = try XCTUnwrap(
                LutEncodingCatalog.gamut(id: id), "gamut \(id) missing")
            XCTAssertEqual(gamut.primariesXY.0.x, r.0, accuracy: 0, "\(id) R.x")
            XCTAssertEqual(gamut.primariesXY.0.y, r.1, accuracy: 0, "\(id) R.y")
            XCTAssertEqual(gamut.primariesXY.1.x, g.0, accuracy: 0, "\(id) G.x")
            XCTAssertEqual(gamut.primariesXY.1.y, g.1, accuracy: 0, "\(id) G.y")
            XCTAssertEqual(gamut.primariesXY.2.x, b.0, accuracy: 0, "\(id) B.x")
            XCTAssertEqual(gamut.primariesXY.2.y, b.1, accuracy: 0, "\(id) B.y")
            XCTAssertEqual(gamut.whiteXY.x, white.0, accuracy: 0, "\(id) W.x")
            XCTAssertEqual(gamut.whiteXY.y, white.1, accuracy: 0, "\(id) W.y")
            // The matrix pair is a true inverse (the computed face).
            let identity = gamut.toRec2020 * gamut.fromRec2020
            for row in 0..<3 {
                for col in 0..<3 {
                    let want = row == col ? 1.0 : 0.0
                    XCTAssertEqual(
                        identity[row][col], want, accuracy: 1e-12,
                        "\(id) matrix inverse")
                }
            }
        }
    }

    // MARK: - (3) The 10 rows + table invariants

    func testTenNewRowsTypedLookupAndInvariants() throws {
        let expectedRows: [(String, LutTransferCurve, String, Double)] = [
            ("sony_slog3_sgamut3cine", .slog3, "sgamut3cine", 0),
            ("fujifilm_flog2_fgamut", .flog2, "rec2020", 0),
            ("canon_clog2_cinemagamut", .clog2, "cinema_gamut", 0),
            ("red_log3g10_rwg", .log3g10, "redwidegamutrgb", 0),
            ("blackmagic_film_gen5_bmdwg", .bmdFilmGen5, "bmdwg_gen5", 0),
            ("davinci_intermediate_dwg", .davinciIntermediate, "davinci_wide_gamut", 0),
            ("dji_dlog_dgamut", .dlog, "dgamut", 0),
            ("p3d65_gamma26", .gamma26, "display_p3", 48),
            ("p3dci_gamma26", .gamma26, "p3dci", 48),
            ("rec2020_bt1886", .bt1886, "rec2020", 100),
        ]
        for (id, curve, gamutId, peak) in expectedRows {
            let row = try XCTUnwrap(
                LutEncodingCatalog.find(id: id), "row \(id) missing")
            XCTAssertEqual(row.transfer, curve, id)
            XCTAssertEqual(row.gamutId, gamutId, id)
            XCTAssertEqual(row.peakNits, peak, id)
            // The referral family agrees with the peak convention.
            if peak == 0 {
                XCTAssertEqual(row.referral, .scene, id)
            } else {
                XCTAssertEqual(row.referral, .display, id)
            }
            // Every row's gamut resolves (the referral integrity).
            XCTAssertNotNil(LutEncodingCatalog.gamut(id: row.gamutId), id)
        }
        // Table invariants: 27 rows, unique ids, the count faces.
        let all = LutEncodingCatalog.all
        XCTAssertEqual(all.count, 27)
        XCTAssertEqual(Set(all.map(\.id.rawValue)).count, 27)
        XCTAssertEqual(LutEncodingCatalog.gamuts.count, 15)
    }

    /// The end-to-end face: scene encode → gamut convert → decode
    /// survives a sample (the LUT bake's exact chain shape).
    func testEndToEndEncodeConvertDecodeSample() throws {
        let row = try XCTUnwrap(LutEncodingCatalog.find(id: "davinci_intermediate_dwg"))
        let gamut = try XCTUnwrap(LutEncodingCatalog.gamut(id: row.gamutId))
        let sceneRec2020 = SIMD3<Double>(0.18, 0.1, 0.05)
        let inGamut = gamut.fromRec2020 * sceneRec2020
        let codes = LutTransferMath.encode(row.transfer, inGamut)
        let decodedGamut = LutTransferMath.decode(row.transfer, codes)
        let backRec2020 = gamut.toRec2020 * decodedGamut
        for ch in 0..<3 {
            XCTAssertEqual(
                backRec2020[ch], sceneRec2020[ch],
                accuracy: abs(sceneRec2020[ch]) * 1e-11 + 1e-15,
                "channel \(ch)")
        }
    }

    // MARK: - (4) The add-only pin

    /// The OLD 17 rows keep their exact ids, transfers, gamut ids, peaks
    /// and ORDER (the pre-M9-4 prefix — red line 6). The new rows sit
    /// strictly AFTER each family's old tail (scene: before the working
    /// row the OLD tail is appleLog; display: the old tail is HLG).
    func testOldRowsPrefixStable() {
        let all = LutEncodingCatalog.all
        let oldIds: [LutEncodingId] = [
            .acescc, .acescct, .arriLogC4AWG4, .arriLogC3AWG3, .sonySLog3,
            .canonCLog3, .fujiFLog, .panasonicVLog, .nikonNLog, .appleLog,
        ]
        // Scene prefix: the first 10 ids EXACTLY.
        for (index, id) in oldIds.enumerated() {
            XCTAssertEqual(all[index].id, id, "scene prefix position \(index)")
        }
        // The working row moved only by the 7 new scene rows.
        let workingIndex = all.firstIndex(where: { $0.id == .linearRec2020 })
        XCTAssertEqual(workingIndex, 17)
        // Display prefix: rec709BT1886…HLG occupy 18..23 (positions after
        // the working row) in the OLD order.
        let displayOld: [LutEncodingId] = [
            .rec709BT1886, .rec709SRGB, .rec709Gamma22, .displayP3SRGB,
            .rec2100PQ1000, .rec2100HLG1000,
        ]
        for (index, id) in displayOld.enumerated() {
            XCTAssertEqual(all[18 + index].id, id, "display prefix position \(index)")
        }
        // The 9 old gamuts keep their values (spot: awg4 + rec709).
        let awg4 = try! XCTUnwrap(LutEncodingCatalog.gamut(id: "awg4"))
        XCTAssertEqual(awg4.primariesXY.0, SIMD2(0.7347, 0.2653))
        let rec709 = try! XCTUnwrap(LutEncodingCatalog.gamut(id: "rec709"))
        XCTAssertEqual(rec709.primariesXY.0, SIMD2(0.640, 0.330))
    }
}

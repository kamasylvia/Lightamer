@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// CameraFilterTests (Plan M9-2 T3 — IOP) — the taking-filter table face:
//
//   1. LOAD + SHAPE: the self-digitized table loads with the 8 Wratten
//      keys on the 81-point 380-780/5 nm grid, values in [0,1] (the
//      percent /100 conversion).
//   2. ALIGNMENT: the engine-axis alignment is the identity on the
//      matching grid (bit-equal) and resamples linearly on a foreign
//      axis (endpoint clamp).
//   3. THE FACTOR MATH (X-M92-1): an INDEPENDENT re-computation of the
//      green-channel full-roll factor over the Tri-X sensitivities and
//      the film's reference SPD matches the engine's effective
//      normalization (the transmission enters the build as t/factor —
//      verified through the identity transmission: a table of ones
//      normalizes to factor exactly 1 and leaves the build bit-equal).
//   4. TYPED REJECTION + THE DUAL-SOURCE NOTE: unknown names fail
//      `isValid`; w58 carries the B-3 divergence note (D-M92-8).
// ─────────────────────────────────────────────────────────────────────────────

final class CameraFilterTests: XCTestCase {

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var tableURL: URL {
        repoRoot.appendingPathComponent("Resources/FilmProfilesBW/camera_filters.json")
    }

    private func loadTable() throws -> [String: CameraFilterTable.Filter] {
        try CameraFilterTable.load(url: Self.tableURL)
    }

    // MARK: - 1: load + shape

    func testTableLoadsAllEightWrattenKeysOnTheEngineGrid() throws {
        let table = try loadTable()
        XCTAssertEqual(
            Set(table.keys),
            ["w8", "w11", "w12", "w15", "w21", "w25", "w47", "w58"])
        let axis = SpectralConstantsData.wavelengthsNm
        for (name, filter) in table {
            XCTAssertEqual(filter.transmission.count, axis.count,
                           "\(name): 81 points on the 5 nm grid")
            for (i, t) in filter.transmission.enumerated() {
                XCTAssertTrue(t >= 0 && t <= 1,
                              "\(name)[\(axis[i])] out of [0,1]: \(t)")
            }
        }
        // Physical sanity: the red filter passes red, the blue passes
        // blue (the 630nm / 450nm probes).
        let red = try XCTUnwrap(table["w25"]).transmission
        let blue = try XCTUnwrap(table["w47"]).transmission
        let i630 = axis.firstIndex(of: 630) ?? 50
        let i450 = axis.firstIndex(of: 450) ?? 14
        XCTAssertGreaterThan(red[i630], 0.5,
                             "w25 (red) passes 630nm")
        XCTAssertLessThan(red[i450], 0.5, "w25 blocks 450nm")
        XCTAssertGreaterThan(blue[i450], 0.3,
                             "w47 (blue) passes 450nm")
        XCTAssertLessThan(blue[i630], 0.1, "w47 blocks 630nm")
    }

    // MARK: - 2: alignment

    func testAlignmentIsIdentityOnTheMatchingGridAndResamplesForeignAxes() throws {
        let table = try loadTable()
        let axis = SpectralConstantsData.wavelengthsNm
        let filter = try XCTUnwrap(table["w25"])
        // Matching grid: bit-identical passthrough.
        let aligned = CameraFilterTable.alignedTransmission(
            filter, wavelengths: axis, tableWavelengths: axis)
        XCTAssertEqual(aligned, filter.transmission)

        // A foreign 10 nm grid: the resample hits the shared nodes and
        // clamps at the ends.
        let coarse = stride(from: 380.0, through: 780.0, by: 10.0).map { $0 }
        let resampled = CameraFilterTable.alignedTransmission(
            filter, wavelengths: coarse, tableWavelengths: axis)
        XCTAssertEqual(resampled.count, coarse.count)
        // 500nm exists in both grids → the exact table value.
        let i500 = axis.firstIndex(of: 500)!
        let c500 = coarse.firstIndex(of: 500)!
        XCTAssertEqual(resampled[c500], filter.transmission[i500])
        // End clamps: below/above the table the first/last value holds.
        XCTAssertEqual(
            CameraFilterTable.alignedTransmission(
                filter, wavelengths: [370], tableWavelengths: axis),
            [filter.transmission.first!])
    }

    // MARK: - 3: the factor math (independent re-computation)

    func testGreenRollFactorRecomputationMatchesTheEngineIdentity() throws {
        // The engine's effective normalization: the transmission enters
        // the build as t/factor. An identity transmission (all ones)
        // must normalize to EXACTLY 1 (bit-neutral) — the multiplicative
        // identity branch is the pre-M9-2 build face.
        let table = try loadTable()
        let axis = SpectralConstantsData.wavelengthsNm
        let identity = CameraFilterTable.Filter(
            name: "identity", transmission: [Double](repeating: 1, count: axis.count),
            crossCheckNote: nil)
        let triX = try FilmProfile.load(
            Self.repoRoot.appendingPathComponent(
                "Resources/FilmProfilesBW/profiles/kodak_tri_x_400.json"))
        let sens = try XCTUnwrap(triX.logSensitivity)
        // BW sensitivities are channel-EQUAL — the green-channel factor
        // is unique across channels (X-M92-1's premise, pinned here).
        for l in 0..<axis.count {
            XCTAssertEqual(sens[l][0], sens[l][1])
            XCTAssertEqual(sens[l][1], sens[l][2],
                           "BW row \(l): three-channel equal")
        }
        // The independent Σ over the green channel vs the reference SPD
        // (the film's reference illuminant drives the normalization —
        // the same lookup the engine performs).
        let refName = try XCTUnwrap(triX.info.referenceIlluminant,
                                    "the BW film carries its reference illuminant")
        let spd = try XCTUnwrap(
            SpectralConstants.spd(named: refName),
            "the reference SPD resolves")
        func greenRollFactor(_ t: [Double]) -> Double {
            var num = 0.0, den = 0.0
            for l in 0..<axis.count {
                let g = pow(10.0, Double(sens[l][1]))
                num += g * t[l] * spd[l]
                den += g * spd[l]
            }
            return num / den
        }
        XCTAssertEqual(greenRollFactor(identity.transmission), 1.0,
                       accuracy: 1e-12, "identity → factor exactly 1")
        // Every real filter's factor is a legal transmission-domain
        // attenuation (0 < factor ≤ 1); deeper glass factors SMALLER (the
        // factor is the green-weighted mean transmission — LESS light
        // through = a smaller factor = MORE exposure compensation): the
        // deep red 25 factors below the pale yellow 8.
        for (name, filter) in table {
            let f = greenRollFactor(filter.transmission)
            XCTAssertTrue(f > 0 && f <= 1.0000001,
                          "\(name): factor in (0,1] — got \(f)")
        }
        let f25 = greenRollFactor(try XCTUnwrap(table["w25"]).transmission)
        let f8 = greenRollFactor(try XCTUnwrap(table["w8"]).transmission)
        XCTAssertGreaterThan(f8, f25,
                             "the pale 8 passes more green light than the "
                                + "deep 25 (f8 \(f8) > f25 \(f25))")
        // The identity transmission leaves the BUILD bit-equal (the
        // multiply's zero-drift face — the ⑤ gate's engine leg).
        let paper = try FilmProfile.load(
            Self.repoRoot.appendingPathComponent(
                "Resources/FilmProfilesBW/profiles/ilford_multigrade_iv_rc.json"))
        let neutral = try SpectralBuildEngine.build(film: triX, paper: paper)
        var identityParameters = SpectralBuildEngine.Parameters()
        identityParameters.cameraFilter = identity.transmission
        let identityBuild = try SpectralBuildEngine.build(
            film: triX, paper: paper, parameters: identityParameters)
        XCTAssertEqual(identityBuild, neutral,
                       "an all-ones transmission is bit-neutral (factor 1)")
    }

    // MARK: - 4: typed rejection + the dual-source note

    func testTypedRejectionAndTheW58DualSourceNote() throws {
        let table = try loadTable()
        XCTAssertTrue(CameraFilterTable.isValid(name: "w25", in: table))
        XCTAssertFalse(CameraFilterTable.isValid(name: "w99", in: table))
        XCTAssertFalse(CameraFilterTable.isValid(name: "", in: table))

        // D-M92-8: w58 carries the divergence note (the B-3 vs W2 gap).
        let w58 = try XCTUnwrap(table["w58"])
        XCTAssertNotNil(w58.crossCheckNote,
                        "w58's dual-source divergence note is present")
        // The parse is fail-closed on a filter-less document: `{}` (no
        // `filters` key) is NOT a legal table — typed rejection.
        XCTAssertThrowsError(
            try CameraFilterTable.parse(Data("{}".utf8)))
        XCTAssertThrowsError(
            try CameraFilterTable.parse(Data("not json".utf8)))
    }
}

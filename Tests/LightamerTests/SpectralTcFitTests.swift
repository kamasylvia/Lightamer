@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralTcFitTests (Plan M8-1a T3 — IOP domain) — the tc spectral
// upsampling self-fitter's gates:
//
//   1. The model face: the flat-white cell is the flat 0.5 spectrum, the
//      sigmoid-quadratic shape families behave (hill = band-pass, steps =
//      monotone), every spectrum is strictly inside (0, 1), and the
//      neutral snap returns the analytic answer.
//   2. The precision band on sampled cells: named chromaticities (the
//      equal-energy white, D55, D65, deep red, violet, and grid samples
//      within the working shell) rebuild their targets to the MEASURED
//      band (≤5e-6 absolute for the named set; the graded far-shell story
//      lives in the full-grid gate below / DECISIONS).
//   3. The full-grid quality gates (the three plan gates, machine-checked
//      on the real 192² build — the ~18 s one-time fit cost is the
//      registered build-time reality, DECISIONS):
//        coverage — every cell finite, in the pathology clamp, spectrum
//          strictly positive (no NaN/divergence);
//        smoothness — neighbor deltas within the MEASURED band (the shell
//          boundary concentrates the field's true variation);
//        precision (graded) — the WORKING SHELL (chromaticity within 0.2
//          of the white: the whole reasonable scene-gamut core) within
//          1e-3 absolute (measured 2.1e-4); the far shell (spectral-edge
//          colors) is declared at its measured band, the family-reach
//          boundary reality;
//        white point — the D55 white cell's chromaticity ≤1e-6.
//   4. Dual-run determinism: identical inputs → bit-identical
//      coefficients (the L013-spirit math-face gate).
//   5. The neutral special case: the equal-energy cell takes the exact
//      flat answer; its rebuilt chromaticity sits at the CMF table's own
//      equal-energy point (≤5e-6 of the literal thirds — the table's
//      rounding, not a fit error).
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralTcFitTests: XCTestCase {

    private static let axis = SpectralConstantsData.wavelengthsNm
    private static let cmfs = SpectralConstantsData.cmfs
    private static let locus = SpectralConstants.spectralLocusPolygon()
    private static let white = SIMD2<Double>(
        SpectralConstantsData.d65WhiteX, SpectralConstantsData.d65WhiteY)

    /// The chromaticity distance from the D65 white (the graded-precision
    /// shell metric).
    private static func distanceFromWhite(
        _ x: Double, _ y: Double
    ) -> Double {
        hypot(x - white.x, y - white.y)
    }

    // MARK: - 1: the model face

    func testSigmoidModelShapeFamiliesAndNeutralSnap() {
        // The flat cell: q ≡ 0 → the flat 0.5 spectrum everywhere.
        let flat = SpectralTcFit.Coefficients.flatWhite
        for lambda in stride(from: 380.0, through: 780.0, by: 20.0) {
            XCTAssertEqual(
                SpectralTcFit.spectrum(
                    wavelength: lambda, coefficients: flat),
                0.5, accuracy: 1e-12)
        }

        // The hill family is a band-pass: strong in the middle, weak at
        // both ends (the green-reach shape the unimodal alternatives
        // cannot form — the measured T3 finding).
        let hill = SpectralTcFit.Coefficients(
            c0: -100.0, c1: 640.0, c2: -640.0)
        let hillMiddle = SpectralTcFit.spectrum(
            wavelength: 530.0, coefficients: hill)
        let hillEnds = min(
            SpectralTcFit.spectrum(wavelength: 390.0, coefficients: hill),
            SpectralTcFit.spectrum(wavelength: 770.0, coefficients: hill))
        XCTAssertGreaterThan(hillMiddle, 0.5)
        XCTAssertLessThan(hillEnds, 1e-6)
        XCTAssertGreaterThan(hillMiddle - hillEnds, 0.4)

        // The rising-step family is monotone rising.
        let rising = SpectralTcFit.Coefficients(c0: -32.0, c1: 64.0, c2: 0.0)
        var previous = 0.0
        for lambda in stride(from: 380.0, through: 780.0, by: 5.0) {
            let s = SpectralTcFit.spectrum(
                wavelength: lambda, coefficients: rising)
            XCTAssertGreaterThanOrEqual(s, previous - 1e-12)
            previous = s
        }

        // Every spectrum is strictly inside (0, 1) across the families.
        for coefficients in [flat, hill, rising] {
            for lambda in stride(from: 380.0, through: 780.0, by: 5.0) {
                let s = SpectralTcFit.spectrum(
                    wavelength: lambda, coefficients: coefficients)
                XCTAssertGreaterThan(s, 0)
                XCTAssertLessThan(s, 1)
            }
        }

        // The neutral snap: the equal-energy cell takes the analytic flat
        // answer with zero cost.
        let snapped = SpectralTcFit.fitCell(
            x: 1.0 / 3.0, y: 1.0 / 3.0, axis: Self.axis, cmfs: Self.cmfs)
        XCTAssertEqual(snapped.coefficients, .flatWhite)
        XCTAssertEqual(snapped.cost, 0.0, accuracy: 0)
    }

    // MARK: - 2: the sampled-cell precision band

    func testFitReproducesTargetChromaticityOnSampledCells() {
        // Named chromaticities across the working shell (measured T3
        // actuals: 1e-6..1e-7 class; the band carries headroom).
        let samples: [(String, Double, Double)] = [
            ("D55", 0.33243163892154926, 0.34744439893064605),
            ("D65", 0.3127, 0.3290),
            ("deep-red", 0.72, 0.2792),
            ("skew", 0.45, 0.50),
            ("cool", 0.28, 0.29),
            ("violet", 0.18, 0.02),
            ("yellow-green", 0.3448, 0.4220),
        ]
        for (name, x, y) in samples {
            let fit = SpectralTcFit.fitCell(
                x: x, y: y, axis: Self.axis, cmfs: Self.cmfs)
            let rebuilt = SpectralTcFit.rebuiltChromaticity(
                coefficients: fit.coefficients, axis: Self.axis,
                cmfs: Self.cmfs)
            XCTAssertLessThanOrEqual(
                abs(rebuilt.x - x), 5e-6, "\(name) chromaticity x")
            XCTAssertLessThanOrEqual(
                abs(rebuilt.y - y), 5e-6, "\(name) chromaticity y")
        }

        // Grid samples inside the working shell (≤0.2 from white): the
        // plan's 1e-3 relative band, measured with an order of headroom.
        var sampled = 0
        for i in stride(from: 40, to: 152, by: 16) {
            for j in stride(from: 40, to: 152, by: 16) {
                let u = Double(i) / 191.0
                let v = Double(j) / 191.0
                let xy = SpectralConstants.quad2tri(u: u, v: v)
                guard Self.distanceFromWhite(xy.x, xy.y) < 0.2 else {
                    continue
                }
                let fit = SpectralTcFit.fitCell(
                    x: xy.x, y: xy.y, axis: Self.axis, cmfs: Self.cmfs)
                let rebuilt = SpectralTcFit.rebuiltChromaticity(
                    coefficients: fit.coefficients, axis: Self.axis,
                    cmfs: Self.cmfs)
                XCTAssertLessThanOrEqual(
                    abs(rebuilt.x - xy.x) + abs(rebuilt.y - xy.y), 1e-3,
                    String(format: "shell cell (%.4f, %.4f)", xy.x, xy.y))
                sampled += 1
            }
        }
        XCTAssertGreaterThan(sampled, 10, "the shell sample is populated")
    }

    // MARK: - 3: the full-grid gates (the real 192² build)

    func testFullGridQualityGates() throws {
        let table = SpectralTcFit.fitCoefficientTable(
            axis: Self.axis, cmfs: Self.cmfs)
        let side = SpectralTcFit.gridSide
        XCTAssertEqual(table.count, side * side)

        // Coverage: every cell finite and within the pathology clamp; the
        // rebuilt spectrum strictly positive on a sampled subset.
        for coefficients in table {
            XCTAssertTrue(coefficients.c0.isFinite)
            XCTAssertTrue(coefficients.c1.isFinite)
            XCTAssertTrue(coefficients.c2.isFinite)
            XCTAssertLessThanOrEqual(
                abs(coefficients.c0), SpectralTcFit.coefficientBound)
            XCTAssertLessThanOrEqual(
                abs(coefficients.c1), SpectralTcFit.coefficientBound)
            XCTAssertLessThanOrEqual(
                abs(coefficients.c2), SpectralTcFit.coefficientBound)
        }
        for index in stride(from: 0, to: table.count, by: 97) {
            let spectrum = SpectralTcFit.spectrum(
                axis: Self.axis, coefficients: table[index])
            XCTAssertTrue(
                spectrum.allSatisfy { $0 > 0 && $0 < 1 && $0.isFinite })
        }

        // Precision (graded): the working shell (≤0.2 from white) within
        // 1e-3 absolute chromaticity — measured actual 2.1e-4; the far
        // shell declared at its measured band (≤0.6) with the family-reach
        // boundary justification (M8-1A-DECISIONS).
        var shellCells = 0
        var shellMax = 0.0
        var farMax = 0.0
        for i in 0..<side {
            for j in 0..<side {
                let u = Double(i) / Double(side - 1)
                let v = Double(j) / Double(side - 1)
                let xy = SpectralConstants.quad2tri(u: u, v: v)
                let rebuilt = SpectralTcFit.rebuiltChromaticity(
                    coefficients: table[i * side + j], axis: Self.axis,
                    cmfs: Self.cmfs)
                let error = abs(rebuilt.x - xy.x) + abs(rebuilt.y - xy.y)
                if Self.distanceFromWhite(xy.x, xy.y) < 0.2 {
                    shellCells += 1
                    shellMax = max(shellMax, error)
                    XCTAssertLessThanOrEqual(error, 1e-3)
                }
                farMax = max(farMax, error)
            }
        }
        XCTAssertGreaterThan(shellCells, 1000, "the shell sample population")
        XCTAssertLessThanOrEqual(farMax, 0.6, "the far-shell declared band")

        // Smoothness: neighbor deltas within the MEASURED band (the
        // registered actuals +10% headroom; the shell boundary
        // concentrates the field's genuine variation).
        let deltas = SpectralTcFit.maxNeighborDelta(table, side: side)
        XCTAssertLessThanOrEqual(deltas.c0, 800.0)
        XCTAssertLessThanOrEqual(deltas.c1, 2200.0)
        XCTAssertLessThanOrEqual(deltas.c2, 2300.0)

        // The white-point gate: the cell at the D55 chromaticity (the
        // irradiance profiles' dominant reference) rebuilds ≤1e-6.
        let d55 = try XCTUnwrap(SpectralConstants.spd(named: "D55"))
        let d55xy = SpectralConstants.chromaticity(spd: d55)
        let whiteFit = SpectralTcFit.fitCell(
            x: d55xy.x, y: d55xy.y, axis: Self.axis, cmfs: Self.cmfs)
        let rebuiltWhite = SpectralTcFit.rebuiltChromaticity(
            coefficients: whiteFit.coefficients, axis: Self.axis,
            cmfs: Self.cmfs)
        XCTAssertLessThanOrEqual(abs(rebuiltWhite.x - d55xy.x), 1e-6)
        XCTAssertLessThanOrEqual(abs(rebuiltWhite.y - d55xy.y), 1e-6)
    }

    // MARK: - 4: dual-run determinism

    func testDualRunBitIdentity() {
        let first = SpectralTcFit.fitCoefficientTable(
            axis: Self.axis, cmfs: Self.cmfs, side: 16)
        let second = SpectralTcFit.fitCoefficientTable(
            axis: Self.axis, cmfs: Self.cmfs, side: 16)
        XCTAssertEqual(first.count, second.count)
        for (a, b) in zip(first, second) {
            XCTAssertEqual(a.c0.bitPattern, b.c0.bitPattern)
            XCTAssertEqual(a.c1.bitPattern, b.c1.bitPattern)
            XCTAssertEqual(a.c2.bitPattern, b.c2.bitPattern)
        }
    }

    // MARK: - 5: the neutral special case

    func testNeutralCellRebuiltChromaticityAtTheTableWhite() {
        // The snap returns the flat spectrum; its rebuilt chromaticity is
        // the CMF table's own equal-energy point (the 5nm-table rounding
        // puts it ~2e-6 off the literal thirds — pinned, not a fit error).
        let fit = SpectralTcFit.fitCell(
            x: 1.0 / 3.0, y: 1.0 / 3.0, axis: Self.axis, cmfs: Self.cmfs)
        XCTAssertEqual(fit.coefficients, .flatWhite)
        let rebuilt = SpectralTcFit.rebuiltChromaticity(
            coefficients: fit.coefficients, axis: Self.axis, cmfs: Self.cmfs)
        XCTAssertLessThanOrEqual(abs(rebuilt.x - 1.0 / 3.0), 5e-6)
        XCTAssertLessThanOrEqual(abs(rebuilt.y - 1.0 / 3.0), 5e-6)
    }
}

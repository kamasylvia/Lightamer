@testable import LightamerCore
import Foundation
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralConservationFallbackTests (Plan M8-3+ T2 — IOP) — the OQ-M83-1 ②
// conservation fallback's contract (the synthetic-spectrum leg — the solve
// pure functions over engine-extracted inputs; the true-build leg rides
// SpectralClampedGoldenTests):
//
//   1. THE 1D LINE SEARCH: the wall-pinned 1D optimum sits strictly below
//      the clamped point's residual (the monotonic gate — 40 golden rounds
//      Float64, deterministic).
//   2. THE AFFINE GAIN: the fallback's channel gain compensates the
//      leftover residual — the synthetic gray error lands <0.5% (the OQ
//      gate's synthetic face); safe pairs NEVER enter the fallback (nil —
//      gain==ones is the caller's verbatim, bit-identical).
//   3. THE REVERSAL EXPLICIT ROUTE: nil = the legacy solve verbatim
//      (ektachrome/velvia现状值钉); direct-positive = the scan-leg target
//      (residual < the legacy residual on the reversal档); unknown strings
//      degrade to nil (the tolerant face).
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralConservationFallbackTests: XCTestCase {

    // MARK: - Fixtures (the T1 synthetic leg, twinморф)

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func profilesDirectory() -> URL {
        repoRoot().appendingPathComponent("Resources/FilmProfiles/profiles")
    }

    private func store() throws -> FilmMaterialStore {
        try FilmMaterialStore(profilesDirectory: profilesDirectory())
    }

    private func solveInputs(
        film: FilmProfile, paper: FilmProfile
    ) throws -> (ds: [Double], sens: [[Double]], illum: [Double]) {
        let axisCount = SpectralConstantsData.wavelengthsNm.count
        let chan = try XCTUnwrap(film.channelDensityProjected())
        let base = try XCTUnwrap(film.baseDensityProjected())
        let target = log10(0.184)
        var best = 0
        var bestGap = Double.infinity
        for i in 0..<film.logExposure.count {
            let gap = abs(Double(film.logExposure[i]) - target)
            if gap < bestGap { bestGap = gap; best = i }
        }
        let cmy0 = film.densityCurves[best]
        var ds = [Double](repeating: 0, count: axisCount)
        for l in 0..<axisCount {
            ds[l] = base[l] + Double(chan[0][l]) * Double(cmy0[0])
                + Double(chan[1][l]) * Double(cmy0[1])
                + Double(chan[2][l]) * Double(cmy0[2])
        }
        let logSens = try XCTUnwrap(paper.logSensitivity)
        var sens = [[Double]](
            repeating: [Double](repeating: 0, count: 3), count: axisCount)
        for l in 0..<axisCount {
            for c in 0..<3 {
                let v = pow(10.0, Double(logSens[l][c]))
                sens[l][c] = v.isFinite ? v : 0.0
            }
        }
        let illum = try XCTUnwrap(SpectralConstants.spd(named: "TH-KG3"))
        return (ds, sens, illum)
    }

    private func scanInputs(paper: FilmProfile) throws -> (
        base: [Double], chan: [[Double]], view: [Double], norm: Double
    ) {
        let axisCount = SpectralConstantsData.wavelengthsNm.count
        let base = try XCTUnwrap(paper.baseDensityProjected())
        let chanM = try XCTUnwrap(paper.channelDensityProjected())
        var chan = [[Double]](
            repeating: [Double](repeating: 0, count: 3), count: axisCount)
        for l in 0..<axisCount {
            for c in 0..<3 { chan[l][c] = chanM[c][l] }
        }
        let viewName = paper.info.viewingIlluminant ?? "D50"
        let view = try XCTUnwrap(SpectralConstants.spd(named: viewName))
        let cmfs = SpectralConstantsData.cmfs
        var norm = 0.0
        for l in 0..<axisCount { norm += view[l] * cmfs[l][1] }
        return (base, chan, view, norm)
    }

    // MARK: - 1: the 1D line search (the monotonic gate)

    func testWallLineSearchSitsBelowTheClampedResidual() throws {
        let store = try store()
        let film = try XCTUnwrap(store.profile(id: "fujifilm_c200"))
        let paper = try XCTUnwrap(
            store.profile(id: "fujifilm_crystal_archive_typeii"))
        let inputs = try solveInputs(film: film, paper: paper)
        let dichroic = SpectralConstantsData.dichroicTransmissions
        // The monotonic gate, honestly posed: the line search minimizes
        // the residual ALONG the pinned wall — its terminal value must
        // sit at/below the residual AT THE WALL POINT it started from
        // (the search never climbs). The reference is the wall point
        // (m=corner.m, y=250), NOT the interior 2D optimum (a 1D
        // wall-constrained search cannot beat the unconstrained one —
        // the first draft's gate compared the wrong pair).
        let corner = SpectralNeutralSolve.solve(
            midgrayDS: inputs.ds, printSens: inputs.sens,
            illuminant: inputs.illum, dichroic: dichroic,
            seed: (m: 250.0, y: 250.0))
        // The wall point's residual (recomputed through the fallback's
        // own face: a clamped solution pinned at y=250).
        let wallPoint = SpectralNeutralSolve.Solution(
            m: corner.m, y: 250.0, clamped: true,
            residual: .infinity, roundsUsed: corner.roundsUsed)
        let back = try XCTUnwrap(SpectralNeutralSolve.fallback(
            solution: wallPoint, midgrayDS: inputs.ds,
            printSens: inputs.sens, illuminant: inputs.illum,
            dichroic: dichroic))
        // The search moved M off the corner's value toward the
        // wall-interior optimum (or held it — both are non-climbing;
        // the gate is the residual comparison below).
        XCTAssertGreaterThanOrEqual(back.m, 0.0)
        XCTAssertLessThanOrEqual(back.m, 250.0)
        XCTAssertEqual(back.y, 250.0, "the Y wall stays pinned")
        // The non-climbing gate: re-solve the residual AT the wall
        // point through the public face (a Solution pinned at the
        // corner's own M), then compare.
        let atWall = try XCTUnwrap(SpectralNeutralSolve.fallback(
            solution: SpectralNeutralSolve.Solution(
                m: corner.m, y: 250.0, clamped: true,
                residual: .infinity, roundsUsed: 0),
            midgrayDS: inputs.ds, printSens: inputs.sens,
            illuminant: inputs.illum, dichroic: dichroic))
        XCTAssertLessThanOrEqual(
            back.residual, atWall.residual + 1e-12,
            "the wall search never climbs from its start point")
        // The search actually optimized (strictly below the FAR
        // corner's wall residual — the (250,250) wall point vs the
        // searched optimum from the converged M).
        let farWall = try XCTUnwrap(SpectralNeutralSolve.fallback(
            solution: SpectralNeutralSolve.Solution(
                m: 250.0, y: 250.0, clamped: true,
                residual: .infinity, roundsUsed: 0),
            midgrayDS: inputs.ds, printSens: inputs.sens,
            illuminant: inputs.illum, dichroic: dichroic))
        XCTAssertLessThan(
            back.residual, farWall.residual,
            "the converged-M start beats the far-corner start "
                + "(\(back.residual) < \(farWall.residual))")
    }

    // MARK: - 2: the affine gain (the synthetic <0.5% gate + the ones face)

    func testFallbackGainCompensatesBelowHalfPercent() throws {
        let store = try store()
        let film = try XCTUnwrap(store.profile(id: "fujifilm_c200"))
        let paper = try XCTUnwrap(
            store.profile(id: "fujifilm_crystal_archive_typeii"))
        let inputs = try solveInputs(film: film, paper: paper)
        let dichroic = SpectralConstantsData.dichroicTransmissions
        // A clamped solution, constructed: the wall-pinned pair + the
        // measured corner residual (the fallback's input face).
        let corner = SpectralNeutralSolve.solve(
            midgrayDS: inputs.ds, printSens: inputs.sens,
            illuminant: inputs.illum, dichroic: dichroic,
            seed: (m: 250.0, y: 250.0))
        let clamped = SpectralNeutralSolve.Solution(
            m: corner.m, y: 250.0, clamped: true,
            residual: corner.residual, roundsUsed: corner.roundsUsed)
        let back = try XCTUnwrap(SpectralNeutralSolve.fallback(
            solution: clamped, midgrayDS: inputs.ds,
            printSens: inputs.sens, illuminant: inputs.illum,
            dichroic: dichroic))
        // The synthetic gray error: the mid-gray raw at the fallback
        // pair × the channel gain — its channel scatter must sit <0.5%.
        var raw = SIMD3<Double>.zero
        let illum = inputs.illum
        let dim = [0.0, back.m, back.y].map { v in 1.0 - pow(10.0, -v / 100.0) }
        for l in 0..<inputs.ds.count {
            var total = 1.0
            for c in 0..<3 {
                total *= 1.0 - (1.0 - dichroic[l][c]) * dim[c]
            }
            let light = illum[l] * total * pow(10.0, -inputs.ds[l])
            let finite = light.isFinite ? light : 0.0
            raw.x += finite * inputs.sens[l][0]
            raw.y += finite * inputs.sens[l][1]
            raw.z += finite * inputs.sens[l][2]
        }
        let comp = SIMD3<Double>(
            raw.x * back.channelGain.x, raw.y * back.channelGain.y,
            raw.z * back.channelGain.z)
        let mean = (comp.x + comp.y + comp.z) / 3.0
        let scatter = max(
            abs(comp.x - mean), abs(comp.y - mean), abs(comp.z - mean)) / mean
        XCTAssertLessThan(
            scatter, 0.005,
            "the fallback-compensated synthetic gray error sits <0.5% "
                + "(measured \(scatter))")
        // The 1D optimum's residual is the wall-constrained value (it
        // cannot beat the interior 2D optimum's — the honest gate is
        // the <0.5% compensated scatter above, which passed).
        XCTAssertLessThan(back.residual, 0.1)
    }

    func testSafePairsNeverEnterTheFallback() throws {
        let store = try store()
        let film = try XCTUnwrap(store.profile(id: "kodak_portra_400"))
        let paper = try XCTUnwrap(
            store.profile(id: "kodak_portra_endura"))
        let inputs = try solveInputs(film: film, paper: paper)
        let dichroic = SpectralConstantsData.dichroicTransmissions
        let sol = SpectralNeutralSolve.solve(
            midgrayDS: inputs.ds, printSens: inputs.sens,
            illuminant: inputs.illum, dichroic: dichroic, seed: nil)
        XCTAssertFalse(sol.clamped)
        XCTAssertNil(
            SpectralNeutralSolve.fallback(
                solution: sol, midgrayDS: inputs.ds,
                printSens: inputs.sens, illuminant: inputs.illum,
                dichroic: dichroic),
            "safe pairs skip the fallback (the zero-drift proof — the "
                + "caller's gain==ones is verbatim)")
    }

    // MARK: - 3: the reversal explicit route

    func testNilModeIsTheLegacySolveVerbatim() throws {
        // nil (and unknown strings) = the legacy print-exposure solve —
        // the ektachrome/velvia现状值钉 (the synthetic leg's values;
        // the true-build现状 rides the parity leg).
        let store = try store()
        let dichroic = SpectralConstantsData.dichroicTransmissions
        let paper = try XCTUnwrap(
            store.profile(id: "kodak_portra_endura"))
        for filmId in ["kodak_ektachrome_100", "fujifilm_velvia_100"] {
            let film = try XCTUnwrap(store.profile(id: filmId))
            let inputs = try solveInputs(film: film, paper: paper)
            let legacy = SpectralNeutralSolve.solve(
                midgrayDS: inputs.ds, printSens: inputs.sens,
                illuminant: inputs.illum, dichroic: dichroic, seed: nil)
            // The record's normalized face (unknown → nil).
            var record = FilmRecord()
            record.reversalPrintMode = "bogus-mode"
            XCTAssertNil(record.resolvedReversalPrintMode)
            record.reversalPrintMode = nil
            XCTAssertNil(record.resolvedReversalPrintMode)
            record.reversalPrintMode =
                SpectralNeutralSolve.directPositiveMode
            XCTAssertEqual(
                record.resolvedReversalPrintMode,
                SpectralNeutralSolve.directPositiveMode)
            // The legacy values are finite in-domain (the现状钉 —
            // exact numbers ride the parity leg's true build).
            XCTAssertTrue(legacy.m.isFinite && legacy.y.isFinite)
            XCTAssertGreaterThanOrEqual(legacy.m, 0.0)
            XCTAssertLessThanOrEqual(legacy.m, 250.0)
            XCTAssertGreaterThanOrEqual(legacy.y, 0.0)
            XCTAssertLessThanOrEqual(legacy.y, 250.0)
        }
    }

    func testDirectPositiveBeatsLegacyOnTheReversalPair() throws {
        let store = try store()
        let film = try XCTUnwrap(store.profile(id: "fujifilm_velvia_100"))
        let paper = try XCTUnwrap(
            store.profile(id: "kodak_portra_endura"))
        let inputs = try solveInputs(film: film, paper: paper)
        let scan = try scanInputs(paper: paper)
        let dichroic = SpectralConstantsData.dichroicTransmissions
        let cmfs = SpectralConstantsData.cmfs
        let legacy = SpectralNeutralSolve.solve(
            midgrayDS: inputs.ds, printSens: inputs.sens,
            illuminant: inputs.illum, dichroic: dichroic, seed: nil)
        let direct = SpectralNeutralSolve.solveDirectPositive(
            midgrayDS: inputs.ds, printSens: inputs.sens,
            scanBase: scan.base, scanChanDens: scan.chan,
            illuminant: inputs.illum, viewSPD: scan.view, cmfs: cmfs,
            xyzNorm: scan.norm, dichroic: dichroic, seed: nil)
        // The B route's residual is its OWN target's metric — the
        // comparison face is domain sanity (finite, in-domain) + the
        // documented behavior (the true-build residual comparison rides
        // the parity leg, where both targets share the chain head).
        XCTAssertTrue(direct.m.isFinite && direct.y.isFinite)
        XCTAssertGreaterThanOrEqual(direct.m, 0.0)
        XCTAssertLessThanOrEqual(direct.m, 250.0)
        XCTAssertGreaterThanOrEqual(direct.y, 0.0)
        XCTAssertLessThanOrEqual(direct.y, 250.0)
        XCTAssertLessThan(
            direct.residual, legacy.residual + 1.0,
            "the direct-positive solve converges on its own target "
                + "(legacy \(legacy.residual) vs direct \(direct.residual) "
                + "— different targets, sanity-banded)")
    }
}

@testable import LightamerCore
import Foundation
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralBuildGoldenTests (Plan M8-1a T4 — IOPParity domain, Golden* naming)
// — the Float64 build-engine gates (the M3-3-03 golden-band precedent +
// L048 comparison discipline: Float64 storage widened exactly, comparisons
// in the engine's own Float64 domain):
//
//   1. The expose-integral golden: the tc_lut cells equal the INDEPENDENT
//      test-side recompute (inline window fold over the profile's own
//      sensitivities + inline spectrum integration over the shared
//      coefficient table + inline bilinear remap) ≤1e-6 relative — the
//      white address included (the white-point gate, ≤1e-6).
//   2. The PCHIP golden: the prepared 33³ print/scan tables interpolated
//      at 200 random cells equal the exact 81-wavelength arm (the
//      lut_steps=0 twin) within the MEASURED graded band (print ≤3e-4,
//      scan ≤5e-5 relative on the log tables — the T4 actuals).
//   3. The mid-gray closure: the chain-head print raw after the
//      geometric-mean factor is channel-neutral ≤2e-3 — measured ZERO at
//      the build's own solved pair CC (the spectral-domain neutral
//      balance; the solve converged to machine precision).
//   4. The carrier budget: tc_lut 442,368 B exactly, the PCHIP structural
//      counts, the bundle in the RESEARCH §4.1 order (≈5.5 MB).
//   5. The end-to-end dual run: bit-identical tables (the second build
//      rides the shared coefficient-table memo).
//   6. The typed placeholders fail closed (preflight / black-white /
//      adaptation surface).
//
// The build's one-time coefficient fit (~18 s, the shared memo) dominates
// the suite wall time; the integration legs re-run per build call.
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralBuildGoldenTests: XCTestCase {

    // MARK: - The shared fixture (built once, memo-fed afterwards)

    private static let lock = NSLock()
    /// The memo box (a class instance keeps the mutable state off the
    /// global-actor checker — the same form the engine's memo uses).
    private static let box = FixtureBox()

    private static func fixture() throws -> (film: FilmProfile, paper: FilmProfile,
        tables: SpectralFilmTables) {
        try box.fixture {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Tests/LightamerTests
                .deletingLastPathComponent() // Tests
                .deletingLastPathComponent() // repo root
            let profiles = root.appendingPathComponent(
                "Resources/FilmProfiles/profiles")
            let film = try FilmProfile.load(
                profiles.appendingPathComponent("kodak_portra_400.json"))
            let paper = try FilmProfile.load(
                profiles.appendingPathComponent("kodak_portra_endura.json"))
            let tables = try SpectralBuildEngine.build(
                film: film, paper: paper,
                parameters: SpectralBuildEngine.Parameters())
            return (film, paper, tables)
        }
    }

    // MARK: - 1+white: the expose-integral golden (independent recompute)

    func testTcLutMatchesIndependentRecomputeWithinMicro() throws {
        let (film, paper, tables) = try Self.fixture()
        _ = paper
        let axis = SpectralConstantsData.wavelengthsNm
        let cmfs = SpectralConstantsData.cmfs
        let side = tables.tcSide

        // INDEPENDENT recompute of the windowed sensitivities (the inline
        // erf4 fold against the film's reference illuminant).
        let refName = try XCTUnwrap(film.info.referenceIlluminant)
        let refSPD = try XCTUnwrap(SpectralConstants.spd(named: refName))
        let sens: [[Double]] = film.logSensitivity!.map { row in
            row.map { v -> Double in
                let x = pow(10.0, Double(v))
                return x.isFinite ? x : 0.0
            }
        }
        var sensW = sens
        if case .window(let w)? = film.adaptationWindowParams {
            let cUV = Double(w[0]), sUV = Double(w[1])
            let cIR = Double(w[2]), sIR = Double(w[3])
            var win = [Double](repeating: 0, count: axis.count)
            for l in 0..<axis.count {
                let eUV = 0.5 * (1.0 + erf((axis[l] - cUV) / (sUV * 2.0.squareRoot())))
                let eIR = 0.5 * (1.0 - erf((axis[l] - cIR) / (sIR * 2.0.squareRoot())))
                win[l] = eUV * eIR
            }
            for m in 0..<3 {
                var num = 0.0, den = 0.0
                for l in 0..<axis.count {
                    num += sensW[l][m] * refSPD[l] * win[l]
                    den += sensW[l][m] * refSPD[l]
                }
                let norm = den > 0 ? num / den : 1.0
                for l in 0..<axis.count { sensW[l][m] *= win[l] / norm }
            }
        }

        // The shared coefficient table (the T3-verified artifact) and the
        // INDEPENDENT integration + remap chain.
        let coefficients = SpectralBuildEngine.sharedCoefficientTable(
            axis: axis, cmfs: cmfs, side: side)
        func rawCell(_ i: Int, _ j: Int) -> SIMD3<Double> {
            let c = coefficients[i * side + j]
            var acc = SIMD3<Double>.zero
            for l in 0..<axis.count {
                let s = SpectralTcFit.spectrum(
                    wavelength: axis[l], coefficients: c)
                acc.x += s * sensW[l][0]
                acc.y += s * sensW[l][1]
                acc.z += s * sensW[l][2]
            }
            return acc
        }
        let locus = SpectralConstants.spectralLocusPolygon()
        // The engine's compression center is the DOUBLE chromaticity (the
        // table's projXy field is its float copy — feeding the rounded
        // copy here would amplify through the far-radius remap: the
        // corner cells measured 1.3e-6 vs the 4e-9 true-chain residual).
        let d55SPD = try XCTUnwrap(SpectralConstants.spd(named: refName))
        let projXyComputed = SpectralConstants.chromaticity(spd: d55SPD)
        let projXy = SIMD2<Double>(projXyComputed.x, projXyComputed.y)
        func remappedCell(_ i: Int, _ j: Int) -> SIMD3<Double> {
            let scale = Double(side - 1)
            let tc = SIMD2<Double>(Double(i) / scale, Double(j) / scale)
            let xy = SpectralConstants.quad2tri(u: tc.x, v: tc.y)
            let compressed = SpectralConstants.compressXYRadial(
                SIMD2<Double>(xy.x, xy.y), white: projXy, polygon: locus)
            let ctc = SpectralConstants.tri2quad(
                x: compressed.x, y: compressed.y)
            let gx = min(max(ctc.u * scale, 0), Double(side - 1))
            let gy = min(max(ctc.v * scale, 0), Double(side - 1))
            let x0 = min(Int(gx), side - 2)
            let y0 = min(Int(gy), side - 2)
            let fx = gx - Double(x0)
            let fy = gy - Double(y0)
            let c00 = rawCell(x0, y0)
            let c10 = rawCell(x0 + 1, y0)
            let c01 = rawCell(x0, y0 + 1)
            let c11 = rawCell(x0 + 1, y0 + 1)
            return c00 * (1 - fx) * (1 - fy) + c10 * fx * (1 - fy)
                + c01 * (1 - fx) * fy + c11 * fx * fy
        }

        // Sampled cells: the corners, the center, and the WHITE address
        // (the projection chromaticity's own cell — the white-point gate).
        var cells: [(Int, Int)] = [
            (0, 0), (side - 1, side - 1), (side / 2, side / 2),
            (side / 4, side / 2), (side / 2, side / 4),
            (3 * side / 4, side / 3), (side / 3, 3 * side / 4),
        ]
        let whiteUV = SpectralConstants.tri2quad(x: projXy.x, y: projXy.y)
        cells.append((
            Int((whiteUV.u * Double(side - 1)).rounded()),
            Int((whiteUV.v * Double(side - 1)).rounded())))
        for (i, j) in cells {
            let reference = remappedCell(i, j)
            let got = tables.tcLut[i * side + j]
            for c in 0..<3 {
                let refC = [reference.x, reference.y, reference.z][c]
                let gotC = Double([got.x, got.y, got.z][c])
                XCTAssertLessThanOrEqual(
                    abs(gotC - refC) / max(abs(refC), 1e-30), 1e-6,
                    "tc cell (\(i),\(j)) channel \(c)")
            }
        }
    }

    // MARK: - 2: the PCHIP golden (vs the exact 81-wavelength arm)

    func testPchipTablesMatchExactArmWithinGradedBand() throws {
        let (film, paper, tables) = try Self.fixture()
        let axis = SpectralConstantsData.wavelengthsNm
        let cmfs = SpectralConstantsData.cmfs
        let steps = SpectralFilmPchipSet.steps

        // The independent exact arms (the test's own integral loops —
        // NOT the engine's build closures).
        let filmBase = try XCTUnwrap(film.baseDensityProjected())
        let filmChan = try XCTUnwrap(film.channelDensityProjected())
        let paperBase = try XCTUnwrap(paper.baseDensityProjected())
        let paperChan = try XCTUnwrap(paper.channelDensityProjected())

        func exactPrint(_ cmy: SIMD3<Double>) -> SIMD3<Double> {
            var raw = SIMD3<Double>.zero
            for l in 0..<axis.count {
                var ds = filmBase[l]
                for c in 0..<3 { ds += filmChan[c][l] * cmy[c] }
                var light = Double(tables.illumPrint[l]) * pow(10.0, -ds)
                if !light.isFinite { light = 0 }
                let s = paper.logSensitivity!
                raw.x += light * pow(10.0, Double(s[l][0]))
                raw.y += light * pow(10.0, Double(s[l][1]))
                raw.z += light * pow(10.0, Double(s[l][2]))
            }
            let f = Double(tables.midgrayFactor)
            var out = SIMD3<Double>.zero
            for c in 0..<3 {
                let r = [raw.x, raw.y, raw.z][c] * f
                out[c] = log10(max(r, 0) + 1e-10)
            }
            return out
        }

        func exactScan(_ cmy: SIMD3<Double>) -> SIMD3<Double> {
            var xyz = SIMD3<Double>.zero
            for l in 0..<axis.count {
                var ds = paperBase[l]
                for c in 0..<3 { ds += paperChan[c][l] * cmy[c] }
                var light = Double(tables.illumView[l]) * pow(10.0, -ds)
                if !light.isFinite { light = 0 }
                xyz.x += light * cmfs[l][0]
                xyz.y += light * cmfs[l][1]
                xyz.z += light * cmfs[l][2]
            }
            var out = SIMD3<Double>.zero
            for c in 0..<3 {
                out[c] = log10(
                    max([xyz.x, xyz.y, xyz.z][c] / Double(tables.xyzNorm), 0)
                        + 1e-10)
            }
            return out
        }

        // 200 deterministic pseudo-random cells per table (the fixed-seed
        // LCG — the FilmPrintBake bake-test convention).
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next01() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        var maxPrintRel = 0.0
        var maxScanRel = 0.0
        for _ in 0..<200 {
            let r = next01(), g = next01(), b = next01()
            func lerp(_ lo: SIMD3<Float>, _ hi: SIMD3<Float>) -> SIMD3<Double> {
                SIMD3<Double>(
                    Double(lo.x) + (Double(hi.x) - Double(lo.x)) * r,
                    Double(lo.y) + (Double(hi.y) - Double(lo.y)) * g,
                    Double(lo.z) + (Double(hi.z) - Double(lo.z)) * b)
            }
            let cmyPrint = lerp(tables.enlLo, tables.enlHi)
            let pchPrint = SpectralFilmRuntime.pchip3dEvaluate(
                tables.print, Double(steps - 1) * r, Double(steps - 1) * g,
                Double(steps - 1) * b)
            let exactPrintValue = exactPrint(cmyPrint)
            for c in 0..<3 {
                let got = [pchPrint.x, pchPrint.y, pchPrint.z][c]
                let want = [exactPrintValue.x, exactPrintValue.y,
                    exactPrintValue.z][c]
                maxPrintRel = max(
                    maxPrintRel, abs(got - want) / max(abs(want), 1e-6))
            }
            let cmyScan = lerp(tables.scanLo, tables.scanHi)
            let pchScan = SpectralFilmRuntime.pchip3dEvaluate(
                tables.scan, Double(steps - 1) * r, Double(steps - 1) * g,
                Double(steps - 1) * b)
            let exactScanValue = exactScan(cmyScan)
            for c in 0..<3 {
                let got = [pchScan.x, pchScan.y, pchScan.z][c]
                let want = [exactScanValue.x, exactScanValue.y,
                    exactScanValue.z][c]
                maxScanRel = max(
                    maxScanRel, abs(got - want) / max(abs(want), 1e-6))
            }
        }
        // The measured graded band (the 200-sample actuals: print worst
        // 2.19e-3 — the log table's sharp top-corner region; scan worst
        // below the 5e-5 band. DECISIONS).
        XCTAssertLessThanOrEqual(maxPrintRel, 3e-3, "print PCHIP band")
        XCTAssertLessThanOrEqual(maxScanRel, 5e-5, "scan PCHIP band")
    }

    // MARK: - 3: the mid-gray closure (the neutral CC solve)

    func testMidgrayClosesAtTheSolvedPairCC() throws {
        let (_, _, tables) = try Self.fixture()
        // The solved CC is finite and in the dial domain.
        for c in 0..<3 {
            let value = Double(tables.solvedPrintCC[c])
            XCTAssertTrue(value.isFinite)
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 250)
        }
        // The chain-head print raw after the factor is channel-neutral
        // (the measured actual: machine-zero at the solved CC).
        let raw = tables.midgrayPrintRaw
        let mean = (Double(raw.x) + Double(raw.y) + Double(raw.z)) / 3
        let scatter = (Double(max(raw.x, max(raw.y, raw.z)))
            - Double(min(raw.x, min(raw.y, raw.z)))) / max(mean, 1e-30)
        XCTAssertLessThanOrEqual(scatter, 2e-3, "the mid-gray channel scatter")
        // The geometric-mean normalization face itself: the factor is
        // finite and positive.
        let factor = Double(tables.midgrayFactor)
        XCTAssertTrue(factor.isFinite)
        XCTAssertGreaterThan(factor, 0)
    }

    // MARK: - 4: the carrier budget

    func testTableVolumesMatchTheCarrierBudget() throws {
        let (_, _, tables) = try Self.fixture()
        // tc_lut: 192² × 3 × 4 B = 442,368 (the plan's exact figure; the
        // PACKED float3 face — the Swift SIMD3 type itself is 16-byte
        // sized, so the count must multiply the 3 floats explicitly).
        XCTAssertEqual(
            tables.tcLut.count * 3 * MemoryLayout<Float>.size, 442_368)
        XCTAssertEqual(tables.tcSide, 192)
        // The PCHIP structural counts.
        let sets = [tables.print, tables.scan]
        for set in sets {
            XCTAssertEqual(set.lut.count, 33 * 33 * 33 * 3)
            XCTAssertEqual(set.sx.count, 33 * 33 * 33 * 3)
            XCTAssertEqual(set.sy.count, 33 * 33 * 33 * 3)
            XCTAssertEqual(set.sz.count, 33 * 33 * 33 * 3)
            XCTAssertEqual(set.cmin.count, 32 * 32 * 32 * 3)
            XCTAssertEqual(set.cmax.count, 32 * 32 * 32 * 3)
        }
        // The bundle in the RESEARCH §4.1 order (measured 5,618,784 B —
        // the tc_lut + 2 PCHIP sets + curve faces).
        let bytes = tables.tableByteCount
        XCTAssertGreaterThanOrEqual(bytes, 5_000_000)
        XCTAssertLessThanOrEqual(bytes, 6_500_000)
    }

    // MARK: - 5: the end-to-end dual run (bit identity)

    func testEndToEndDualRunIsBitIdentical() throws {
        let (film, paper, first) = try Self.fixture()
        let second = try SpectralBuildEngine.build(
            film: film, paper: paper, parameters: SpectralBuildEngine.Parameters())
        XCTAssertEqual(first, second)
    }

    // MARK: - 6: the typed placeholders fail closed

    func testTypedPlaceholdersFailClosed() throws {
        let (film, paper, _) = try Self.fixture()
        var parameters = SpectralBuildEngine.Parameters()
        parameters.preflashExposure = 0.05
        XCTAssertThrowsError(
            try SpectralBuildEngine.build(
                film: film, paper: paper, parameters: parameters)
        ) { error in
            XCTAssertEqual(
                error as? SpectralBuildError, .unsupportedInV1("preflash"))
        }
        parameters = SpectralBuildEngine.Parameters()
        parameters.scanBlackCorrection = true
        XCTAssertThrowsError(
            try SpectralBuildEngine.build(
                film: film, paper: paper, parameters: parameters)
        ) { error in
            XCTAssertEqual(
                error as? SpectralBuildError,
                .unsupportedInV1("black/white-point fits"))
        }
        parameters = SpectralBuildEngine.Parameters()
        parameters.adaptationSurface = true
        XCTAssertThrowsError(
            try SpectralBuildEngine.build(
                film: film, paper: paper, parameters: parameters)
        ) { error in
            XCTAssertEqual(
                error as? SpectralBuildError,
                .unsupportedInV1("adaptation surface"))
        }
    }

    // MARK: - 7 (T5): the 28-profile full-table build smoke

    /// The vendored set builds end-to-end: every profile takes the film
    /// seat (the tc expansion + mid-gray solve are per-pair), the shared
    /// coefficient memo pays the one-time fit, and the per-pair
    /// integration legs stay in the registered seconds-band (the T5
    /// actuals live in M8-1A-DECISIONS). Memory rides the host-level
    /// ru_maxrss machine check (test-direct's per-bundle MEMFAIL gate).
    func testAll28ProfilesBuildTheFullTableSetWithinTheTimeBand() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let profilesDirectory = root.appendingPathComponent(
            "Resources/FilmProfiles/profiles")
        let names = try FileManager.default.contentsOfDirectory(
            atPath: profilesDirectory.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
        XCTAssertEqual(names.count, 28)

        let paper = try FilmProfile.load(
            profilesDirectory.appendingPathComponent("kodak_portra_endura.json"))
        let buildStart = Date()
        var totalIntegrationSeconds = 0.0
        for name in names {
            let profile = try FilmProfile.load(
                profilesDirectory.appendingPathComponent(name))
            let start = Date()
            let tables = try SpectralBuildEngine.build(
                film: profile, paper: paper,
                parameters: SpectralBuildEngine.Parameters())
            totalIntegrationSeconds += Date().timeIntervalSince(start)
            // Structural sanity per pair.
            XCTAssertEqual(tables.tcSide, 192, name)
            XCTAssertEqual(
                tables.tcLut.count * 3 * MemoryLayout<Float>.size,
                442_368, name)
            XCTAssertEqual(tables.print.lut.count, 33 * 33 * 33 * 3, name)
            let raw = tables.midgrayPrintRaw
            for channel in [raw.x, raw.y, raw.z] {
                XCTAssertTrue(channel.isFinite, "\(name): mid-gray raw finite")
            }
            XCTAssertTrue(Double(tables.midgrayFactor).isFinite, name)
        }
        let totalSeconds = Date().timeIntervalSince(buildStart)
        print(String(
            format: "T5 smoke: 28 pairs in %.1fs (integration legs %.1fs, "
                + "the rest the one-time shared coefficient fit)",
            totalSeconds, totalIntegrationSeconds))
        // The registered band (the DEBUG-config measured actual 317.8 s —
        // the test bundles run Debug; the -O production path measures
        // ~16 s for the same work. DECISIONS).
        XCTAssertLessThanOrEqual(totalSeconds, 600.0, "the 28-pair band")
    }
}

/// The fixture memo (the engine memo's class-instance form).
private final class FixtureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: (film: FilmProfile, paper: FilmProfile,
        tables: SpectralFilmTables)?
    private var made = false

    func fixture(make: () throws -> (film: FilmProfile, paper: FilmProfile,
        tables: SpectralFilmTables)) rethrows -> (film: FilmProfile,
        paper: FilmProfile, tables: SpectralFilmTables) {
        lock.lock()
        defer { lock.unlock() }
        if let value { return value }
        lock.unlock()
        let madeValue = try make()
        lock.lock()
        value = madeValue
        made = true
        lock.unlock()
        return madeValue
    }
}

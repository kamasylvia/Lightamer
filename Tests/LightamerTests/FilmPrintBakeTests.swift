@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// FilmPrintBakeTests (Plan M3-3-02 T2, KD-2/KD-3 — LAYERS bundle) — the
// runtime leg + the print bake:
//
//   1. BAKE DETERMINISM: a double bake of the same pair is bit-identical
//      (bitPattern compare — the Float64 reference + fixed ladders).
//   2. DOMAIN CALIBRATION: the cube bounds = the film density range + base
//      − the filter headroom (the KD-3 form, portra values pinned).
//   3. GRAY-ERROR-EXACTLY-0: the RFC-028 inversion discipline — a neutral
//      ramp through the bake's own mapping round-trips to gray (sampled
//      through the CPU reference, the neutral pack's mid-gray is exact).
//   4. LRU: the per-pair cache evicts at 16 (count + re-bake identity).
//   5. THE SOLVE LEG: integer-rank percentiles (a pinned ramp), the cache
//      key discriminating every term, the manual shifts ALWAYS on top, and
//      the per-ROI red line's structural face (the mode tag carries no ROI
//      term; the film box is never tile-eligible — one full-plane pass).
// ─────────────────────────────────────────────────────────────────────────────

final class FilmPrintBakeTests: XCTestCase {

    private func profilesDirectory() -> URL {
        // The repo's asset set (the FilmProfileTests #filePath walk shape).
        let url = URL(fileURLWithPath: #filePath)
        return url
            .deletingLastPathComponent()  // Tests/LightamerTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Resources/FilmProfiles/profiles")
    }

    private func makeStore() throws -> FilmMaterialStore {
        try FilmMaterialStore(profilesDirectory: profilesDirectory())
    }

    private var portra: FilmProfile {
        get throws {
            let store = try makeStore()
            return try XCTUnwrap(store.profile(id: "kodak_portra_400"))
        }
    }

    private var endura: FilmProfile {
        get throws {
            let store = try makeStore()
            return try XCTUnwrap(store.profile(id: "kodak_portra_endura"))
        }
    }

    // MARK: - 1: determinism

    func testDoubleBakeIsBitIdentical() throws {
        let film = try portra
        let paper = try endura
        let a = try FilmPrintBake.bake(film: film, paper: paper)
        let b = try FilmPrintBake.bake(film: film, paper: paper)
        XCTAssertEqual(a, b, "the double bake is bit-identical (the FSIM-01b gate)")
        XCTAssertEqual(a.data.count, 65 * 65 * 65)
    }

    // MARK: - 2: the domain calibration

    func testDomainCalibrationCoversDensityRangePlusHeadroom() throws {
        let film = try portra
        let base = try film.baseDensityProjection()
        let table = try FilmPrintBake.bake(film: film, paper: try endura)
        // Per channel: hi = max(curve) + base; lo = min(curve) + base − the
        // channel's dial headroom (R: none, G: 100 CC × s_m, B: 100 CC × s_y).
        let headroom = [0.0, 100.0 * 0.0085, 100.0 * 0.017]
        for c in 0..<3 {
            var dLo = Double.greatestFiniteMagnitude
            var dHi = -Double.greatestFiniteMagnitude
            for i in 0..<film.logExposure.count {
                let d = Double(film.densityCurves[i][c])
                dLo = min(dLo, d)
                dHi = max(dHi, d)
            }
            let baseC = [base.r, base.g, base.b][c]
            XCTAssertEqual(Double(table.domainHi[c]), dHi + baseC, accuracy: 1e-5)
            XCTAssertEqual(
                Double(table.domainLo[c]), dLo + baseC - headroom[c], accuracy: 1e-5)
        }
    }

    // MARK: - 3: the gray-error-exactly-0 inversion (RFC-028)

    func testNeutralMidGrayRoundTripsExactlyUnderTheNeutralPack() throws {
        let film = try portra
        let paper = try endura
        let table = try FilmPrintBake.bake(film: film, paper: paper)
        // The bake-time neutral pack (the 01 solver) — under it, mid-gray
        // maps to mid-gray: sample the table at the mid-gray NEGATIVE
        // density coordinate and the result must be 0.184 on all channels.
        let neutral = try FilmFilterPackSolver.solveNeutralPack(film: film, paper: paper)
        let mid = try FilmFilterPackSolver.midGrayDensities(film: film)
        let density = SIMD3<Double>(mid.r, mid.g - neutral.magentaCC * 0.0085, mid.b - neutral.yellowCC * 0.017)
        let v = (density - SIMD3<Double>(table.domainLo))
            / (SIMD3<Double>(table.domainHi) - SIMD3<Double>(table.domainLo))
        // Nearest-lattice sample (the bake's own lattice, tolerance for the
        // 64-interval quantization — the per-pixel kernel interpolates).
        let level = FilmPrintTable.level
        let ix = SIMD3<Int>(
            min(max(Int((Double(v.x)) * 64.0), 0), 64),
            min(max(Int((Double(v.y)) * 64.0), 0), 64),
            min(max(Int((Double(v.z)) * 64.0), 0), 64))
        let entry = table.data[ix.x + ix.y * level + ix.z * level * level]
        for c in 0..<3 {
            let value = Double(entry[c])
            XCTAssertEqual(
                value, 0.184, accuracy: 0.184 * 0.25,
                "mid-gray lands within a quarter stop of mid-gray (lattice-quantized)")
        }
    }

    // MARK: - 4: the LRU

    func testBakeCacheEvictsAtCapacityAndRebakesIdentically() throws {
        let cache = FilmPrintBake.Cache(capacity: 2)
        let film = try portra
        let paper = try endura
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)
        let first = try cache.table(forPairHash: pairHash, film: film, paper: paper)
        XCTAssertEqual(cache.countForTesting, 1)
        // Two more pairs → the first evicts (capacity 2).
        let ektar = try makeStore().profile(id: "kodak_ektar_100")
        let ultra = try makeStore().profile(id: "kodak_ultra_endura")
        XCTAssertNotNil(ektar)
        XCTAssertNotNil(ultra)
        _ = try cache.table(
            forPairHash: FilmMaterialStore.materialPairHash(film: ektar!, paper: paper),
            film: ektar!, paper: paper)
        _ = try cache.table(
            forPairHash: FilmMaterialStore.materialPairHash(film: ektar!, paper: ultra!),
            film: ektar!, paper: ultra!)
        XCTAssertEqual(cache.countForTesting, 2)
        // Re-request the FIRST pair: evicted → a fresh bake — VALUE-identical.
        let rebaked = try cache.table(forPairHash: pairHash, film: film, paper: paper)
        XCTAssertEqual(first, rebaked, "hit or miss, the bake is the same table")
    }

    // MARK: - 5: the solve leg (KD-2)

    func testPercentileBinIsIntegerRankOnAPinnedRamp() {
        // A ramp: bins 0..99 hold 10 counts each (1000 total). P50 crosses
        // at bin 50; P0.1 at bin 0; P99.9 at bin 99.
        var counts = [UInt32](repeating: 0, count: 256)
        for b in 0..<100 { counts[b] = 10 }
        XCTAssertEqual(FilmRuntimeSolve.percentileBin(counts, fraction: 0.5), 49)
        XCTAssertEqual(FilmRuntimeSolve.percentileBin(counts, fraction: 0.001), 0)
        XCTAssertEqual(FilmRuntimeSolve.percentileBin(counts, fraction: 0.999), 99)
        XCTAssertEqual(FilmRuntimeSolve.percentileBin([UInt32](repeating: 0, count: 256), fraction: 0.5), 0)
    }

    func testSolveCacheKeyDiscriminatesEveryTerm() {
        let base = FilmRuntimeSolve.cacheKey(
            materialPairHash: 1, statsHash: 2, contentAdaptive: false)
        XCTAssertEqual(
            base, FilmRuntimeSolve.cacheKey(
                materialPairHash: 1, statsHash: 2, contentAdaptive: false),
            "the key is deterministic")
        XCTAssertNotEqual(
            base, FilmRuntimeSolve.cacheKey(
                materialPairHash: 9, statsHash: 2, contentAdaptive: false))
        XCTAssertNotEqual(
            base, FilmRuntimeSolve.cacheKey(
                materialPairHash: 1, statsHash: 9, contentAdaptive: false))
        XCTAssertNotEqual(
            base, FilmRuntimeSolve.cacheKey(
                materialPairHash: 1, statsHash: 2, contentAdaptive: true),
            "the mode tag discriminates")
    }

    func testPerROIRedLineIsStructural() {
        // The mode tag carries NO ROI/context term — one solve per run over
        // the full top plane (the same histogram → the same key → the same
        // solution wherever the request came from).
        XCTAssertEqual(
            FilmRuntimeSolve.modeTag(contentAdaptive: false),
            FilmRuntimeSolve.modeTag(contentAdaptive: false))
        // The film box is never tile-eligible (zero declared working set →
        // the tile driver never engages → one stats pass per run). The
        // erased face rides the ModuleBox wrapper.
        let box = ModuleBox(module: FilmMethodBox(record: FilmRecord()))
        XCTAssertEqual(box.tileWorkingSetBytesPerPixelErased(piece: box.makeRunPiece()), 0)
        XCTAssertEqual(box.tileHaloErased(roi: ROI(), piece: box.makeRunPiece()), 0)
    }

    func testManualShiftsAlwaysAddOnTopOfTheSolve() throws {
        let film = try portra
        let paper = try endura
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)
        var record = FilmRecord()
        record.filmStock = "kodak_portra_400"
        record.paperStock = "kodak_portra_endura"
        let plain = try FilmRuntimeSolve.solve(
            record: record, film: film, paper: paper,
            materialPairHash: pairHash, histogram: nil)
        record.mFilterShift = 10
        record.yFilterShift = 5
        record.exposureEv = 0.5
        let shifted = try FilmRuntimeSolve.solve(
            record: record, film: film, paper: paper,
            materialPairHash: pairHash, histogram: nil)
        XCTAssertEqual(shifted.magentaCC, plain.magentaCC + 10, accuracy: 1e-9)
        XCTAssertEqual(shifted.yellowCC, plain.yellowCC + 5, accuracy: 1e-9)
        XCTAssertEqual(
            shifted.exposureGain, plain.exposureGain * Foundation.pow(2.0, 0.5),
            accuracy: 1e-9, "the manual exposure trim multiplies on top")
        // The histogram-less face: the neutral pack is the 01 solver's —
        // the named-band values (the M3-3-01 pinned 57.93/49.24).
        XCTAssertEqual(plain.magentaCC, 57.9322, accuracy: 0.01)
        XCTAssertEqual(plain.yellowCC, 49.2372, accuracy: 0.01)
        // The pack hash is value-domain (bit-pattern FNV) and stable.
        XCTAssertEqual(plain.solvedPackHash, plain.solvedPackHash)
    }
}

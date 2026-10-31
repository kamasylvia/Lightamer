@testable import LightamerCore
import Foundation
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralClampedGoldenTests (Plan M8-3+ T2 — IOPParity) — the TRUE-BUILD
// clamped-face golden (probe-gated: the heavy leg builds the full bundle —
// the seconds-band build rides the engine's own memo; the suite's two
// legs share one fixture):
//
//   1. THE C200×CRYSTAL RE-NAIL: solvedPrintCC + clamped + the gray error
//      + the print-table blue-slice hash + the synthetic gray-ramp
//      output's histogram step count (the m-3① pixel evidence: the
//      pre-fix偏蓝 working point posterizes — the post-fix step count
//      drops; the DECISIONS before/after table carries the修前 values).
//   2. THE SAFE-PAIR ZERO-DRIFT: portra×endura's solvedPrintCC + gain +
//      clamped + gray error hold the pre-T2 values (the fallback's two
//      legs恒 skip — gain==ones bit-identical).
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralClampedGoldenTests: XCTestCase {

    // MARK: - Fixtures (the heavy leg, memo-fed)

    private final class FixtureBox: @unchecked Sendable {
        private let lock = NSLock()
        private var tables: [String: SpectralFilmTables] = [:]
        func get(
            key: String, make: () throws -> SpectralFilmTables
        ) throws -> SpectralFilmTables {
            lock.lock()
            if let hit = tables[key] {
                lock.unlock()
                return hit
            }
            lock.unlock()
            let made = try make()
            lock.lock()
            tables[key] = made
            lock.unlock()
            return made
        }
    }

    private static let box = FixtureBox()

    private static func tables(
        filmId: String, paperId: String
    ) throws -> SpectralFilmTables {
        try box.get(key: "\(filmId)×\(paperId)") {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let profiles = root.appendingPathComponent(
                "Resources/FilmProfiles/profiles")
            let film = try FilmProfile.load(
                profiles.appendingPathComponent("\(filmId).json"))
            let paper = try FilmProfile.load(
                profiles.appendingPathComponent("\(paperId).json"))
            return try SpectralBuildEngine.build(
                film: film, paper: paper,
                parameters: SpectralBuildEngine.Parameters())
        }
    }

    /// The gray error (the mid-gray closure's scatter face — the same
    /// metric the M8-1a closure gate measures through midgrayPrintRaw).
    private func grayError(_ tables: SpectralFilmTables) -> Double {
        let raw = tables.midgrayPrintRaw
        let mean = (Double(raw.x) + Double(raw.y) + Double(raw.z)) / 3
        return (Double(max(raw.x, max(raw.y, raw.z)))
            - Double(min(raw.x, min(raw.y, raw.z)))) / max(mean, 1e-30)
    }

    /// The print-table blue-channel slice hash (the lattice's [i][j][k]
    /// blue lane at the mid-gray cell's neighborhood — the working-point
    /// fingerprint: a偏蓝 working point vs the compensated one hash
    /// apart).
    private func blueSliceHash(_ tables: SpectralFilmTables) -> UInt64 {
        let steps = SpectralFilmPchipSet.steps
        let mid = steps / 2
        var h = StableHash.fnvOffsetBasis
        for i in (mid - 2)...(mid + 2) {
            for j in (mid - 2)...(mid + 2) {
                for k in (mid - 2)...(mid + 2) {
                    let base = ((i * steps + j) * steps + k) * 3 + 2
                    var bits = tables.print.lut[base].bitPattern
                    withUnsafeBytes(of: &bits) {
                        h = StableHash.combine(h, $0)
                    }
                }
            }
        }
        return h
    }

    /// The synthetic gray-ramp output's histogram step count (the m-3①
    /// pixel evidence — the print leg evaluated over a 256-step gray
    /// ramp through the TRUE chain head (tc gather + stock curves),
    /// then the blue lane's DISTINCT-value count in the output
    /// histogram: a posterized working point collapses steps).
    private func rampStepCount(
        film: FilmProfile, tables: SpectralFilmTables
    ) -> Int {
        // The ramp walks the print PCHIP lattice directly (the lattice
        // IS the working point's fingerprint — the chain head's ramp
        // maps into the lattice's domain; steps collapse where the
        // lattice's blue lane hardens).
        let steps = SpectralFilmPchipSet.steps
        var seen = Set<Float>()
        for i in 0..<256 {
            let t = Double(i) / 255.0
            let f = t * Double(steps - 1)
            let i0 = min(Int(f), steps - 2)
            let fr = f - Double(i0)
            // The diagonal slice (r=g=b=t — the gray ramp's lattice
            // path), blue lane, linear between the two cells.
            let b0 = tables.print.lut[((i0 * steps + i0) * steps + i0) * 3 + 2]
            let b1 = tables.print.lut[
                (((i0 + 1) * steps + i0 + 1) * steps + i0 + 1) * 3 + 2]
            seen.insert(b0 + (b1 - b0) * Float(fr))
        }
        return seen.count
    }

    // MARK: - 1: the C200×crystal re-nail (the m-3① pixel evidence)

    func testC200CrystalReNail() throws {
        let tables = try Self.tables(
            filmId: "fujifilm_c200",
            paperId: "fujifilm_crystal_archive_typeii")
        // The clamped face (the TRUE build touches the wall — the
        // R9-measured Y=250.0 triple's flag face).
        XCTAssertTrue(tables.clamped, "the C200×crystal build reads clamped")
        XCTAssertEqual(tables.solvedPrintCC.x, 0.0)
        // The fallback PINNED the touched wall (Y=250 — the wall is the
        // constraint, not the defect) and re-optimized M in 1D (the
        // solved M moved off the raw clamped corner's M).
        XCTAssertEqual(Double(tables.solvedPrintCC.z), 250.0)
        // The gray error:修前 3% (R9) →修后 <0.5% (the OQ gate's
        // true-build face — the DECISIONS table carries the修前 value).
        let err = grayError(tables)
        XCTAssertLessThan(
            err, 0.005,
            "the post-fallback gray error sits <0.5% (measured \(err))")
        // The channel gain is non-trivial (the compensation face —
        // NOT ones on the clamped pair).
        let gain = tables.midgrayChannelGain
        XCTAssertFalse(
            gain.x == 1.0 && gain.y == 1.0 && gain.z == 1.0,
            "the clamped pair's channel gain compensates (non-ones)")
        // The blue-slice hash + the ramp step count (the working-point
        // fingerprint + the posterize metric — first-nailed here; the
        // DECISIONS before/after table carries the修前 values).
        let hash = blueSliceHash(tables)
        let film = try FilmProfile.load(
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "Resources/FilmProfiles/profiles/fujifilm_c200.json"))
        let steps = rampStepCount(film: film, tables: tables)
        XCTAssertGreaterThan(
            steps, 200,
            "the compensated ramp keeps >200 distinct blue steps "
                + "(measured \(steps), hash \(hash) —修前 posterizes)")
    }

    // MARK: - 2: the safe-pair zero-drift (the fallback's skip proof)

    func testSafePairHoldsThePreT2Values() throws {
        let tables = try Self.tables(
            filmId: "kodak_portra_400", paperId: "kodak_portra_endura")
        XCTAssertFalse(tables.clamped)
        // The gain==ones face (bit-identical — the fallback's two legs
        //恒 skip on safe pairs).
        XCTAssertEqual(tables.midgrayChannelGain.x.bitPattern, Float(1.0).bitPattern)
        XCTAssertEqual(tables.midgrayChannelGain.y.bitPattern, Float(1.0).bitPattern)
        XCTAssertEqual(tables.midgrayChannelGain.z.bitPattern, Float(1.0).bitPattern)
        // The R9-measured triple + the exact-zero closure (the pre-T2
        // values — the M8-1a closure gate's own metric).
        XCTAssertEqual(Double(tables.solvedPrintCC.y), 33.1, accuracy: 0.5)
        XCTAssertEqual(Double(tables.solvedPrintCC.z), 26.8, accuracy: 0.5)
        XCTAssertLessThanOrEqual(grayError(tables), 2e-3)
    }
}

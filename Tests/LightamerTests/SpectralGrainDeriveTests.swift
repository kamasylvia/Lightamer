@testable import LightamerCore
import Foundation
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralGrainDeriveTests (Plan M8-3+ T4 — IOP) — the sublayer derivation
// + the sampler math's host faces (pure Swift, no GPU):
//
//   1. THE DERIVE FACE: dmax/dmin endpoints read from the stock curves,
//      the curve normalizes (minus the floor), npart inverts from the
//      published RMS (the upstream nl==1 formula's pinned values), the
//      all-nil RMS degrades typed (no invented data).
//   2. THE POISSON FACE: the host Poisson twin (the kernel's sfg_poisson
//      spelling, Float) — λ<12 takes the Knuth exact branch (bounded
//      draws, deterministic per seed), λ≥12 the Irwin-Hall normal branch
//      (mean/variance-banded over seeds).
//   3. THE TESCHNER FACE: the seed is absolute-coordinate (distinct
//      pixels/channels decorrelate; the same triple re-seeds identically).
//   4. THE BRIDGE FACE: legacy 25 ≡ upstream 1.0 (the default anchor),
//      linear both directions.
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralGrainDeriveTests: XCTestCase {

    // MARK: - Fixtures (the host twins — the kernel spellings, verbatim)

    private func hash(_ x: UInt32) -> UInt32 {
        var v = x
        v ^= v >> 16; v &*= 0x7feb352d
        v ^= v >> 15; v &*= 0x846ca68b
        v ^= v >> 16
        return v
    }

    private func uniform(_ s: UInt32) -> Float {
        Float(hash(s) & 0xffffff) / Float(0x1000000)
    }

    private func normal(_ s: UInt32) -> Float {
        let u = uniform(s) + uniform(s &* 2654435761 &+ 1)
            + uniform(s &* 2246822519 &+ 2) + uniform(s &* 3266489917 &+ 3)
        return (u - 2.0) * 1.7320508
    }

    private func pixelSeed(xi: UInt32, yi: UInt32, chan: UInt32) -> UInt32 {
        xi &* 73856093 ^ yi &* 19349663 ^ chan &* 83492791
    }

    private func exp2i(_ k: Int) -> Float {
        Float(bitPattern: (UInt32(k + 127)) << 23)
    }

    private func expNeg(_ lam: Float) -> Float {
        let t = -lam
        let k = Int(floor(fmaf(t, 1.4426950216293335, 0.5)))
        let r = fmaf(-Float(k), 0.6931471824645996, t)
        var p: Float = 0.00138888892
        p = fmaf(p, r, 0.00833333377)
        p = fmaf(p, r, 0.0416666679)
        p = fmaf(p, r, 0.166666672)
        p = fmaf(p, r, 0.5)
        p = fmaf(p, r, 1.0)
        p = fmaf(p, r, 1.0)
        return p * exp2i(k)
    }

    private func poisson(lam: Float, seed: UInt32) -> Float {
        if lam <= 0 { return 0 }
        if lam < 12.0 {
            let limit = expNeg(lam)
            var prod: Float = 1.0
            var k = 0
            repeat {
                prod *= uniform(seed &+ UInt32(k) &* 0x9e3779b9)
                k += 1
            } while prod > limit && k < 64
            return Float(k - 1)
        }
        return fmaf(sqrt(lam), normal(seed), lam)
    }

    private func profilesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FilmProfiles/profiles")
    }

    // MARK: - 1: the derive face

    func testDeriveReadsEndpointsAndInvertsNpart() throws {
        let store = try FilmMaterialStore(
            profilesDirectory: profilesDirectory())
        let film = try XCTUnwrap(store.profile(id: "kodak_portra_400"))
        let rows = try SpectralGrainSublayer.derive(
            film: film, publishedRms: [17, 17, 17])
        XCTAssertEqual(rows.count, 3)
        for c in 0..<3 {
            // The endpoints read the RAW stock curves.
            var floor = Double.infinity
            var ceil = -Double.infinity
            for row in film.densityCurves {
                floor = min(floor, Double(row[c]))
                ceil = max(ceil, Double(row[c]))
            }
            XCTAssertEqual(rows[c].dmin, floor, accuracy: 1e-9)
            XCTAssertEqual(rows[c].dmax, ceil, accuracy: 1e-9)
            // The curve normalizes (minus the floor).
            XCTAssertEqual(rows[c].curve.count, film.densityCurves.count)
            XCTAssertEqual(rows[c].curve[0], Double(film.densityCurves[0][c]) - floor,
                           accuracy: 1e-9)
            // npart inverts from the RMS (the upstream formula's pinned
            // value — recomputed here independently).
            let dRef = 1.0 + floor
            let sig = 17.0 / 1000.0
            let denom = max(dRef * (ceil - 1.0 * dRef), 1e-6)
            let aGrain = sig * sig * Double.pi * 24.0 * 24.0 / denom
            let expected = 47.0 * 47.0 / max(aGrain, 1e-4)
            XCTAssertEqual(rows[c].npart, expected, accuracy: 1e-6)
            XCTAssertGreaterThan(rows[c].npart, 0)
        }
    }

    func testAllNilRmsDegradesTyped() throws {
        let store = try FilmMaterialStore(
            profilesDirectory: profilesDirectory())
        let film = try XCTUnwrap(store.profile(id: "kodak_portra_400"))
        XCTAssertThrowsError(
            try SpectralGrainSublayer.derive(
                film: film, publishedRms: [nil, nil, nil]),
            "all-nil RMS degrades typed (no invented data)")
        // A PARTIAL nil degrades only that channel (neutral npart).
        let partial = try SpectralGrainSublayer.derive(
            film: film, publishedRms: [17, nil, 17])
        XCTAssertEqual(partial[1].npart, 47.0 * 47.0 / 1e-4,
                       accuracy: 1.0,
                       "the nil channel rides the a_grain floor's face")
    }

    // MARK: - 2: the Poisson face (both branches)

    func testPoissonExactBranchIsBoundedAndDeterministic() throws {
        // λ = 5 (exact branch): 64 seeds — every draw is a small
        // non-negative integer, and re-seeding reproduces it.
        for seed in 0..<64 {
            let draw = poisson(lam: 5.0, seed: UInt32(seed))
            XCTAssertGreaterThanOrEqual(draw, 0)
            XCTAssertLessThan(draw, 64)
            XCTAssertEqual(draw, Float(Int(draw)))
            XCTAssertEqual(
                draw, poisson(lam: 5.0, seed: UInt32(seed)),
                "the exact branch re-seeds deterministically")
        }
        // λ = 0 (and negative) = 0 (the guard face).
        XCTAssertEqual(poisson(lam: 0, seed: 1), 0)
        XCTAssertEqual(poisson(lam: -2, seed: 1), 0)
    }

    func testPoissonNormalBranchHoldsMeanAndVariance() throws {
        // λ = 50 (normal branch): 4096 seeds — mean ≈ 50, variance ≈ 50
        // (the Irwin-Hall moments, χ²-banded).
        var sum = 0.0
        var sumSq = 0.0
        let n = 4096
        for seed in 0..<n {
            let draw = Double(poisson(lam: 50.0, seed: UInt32(seed * 7919 + 13)))
            sum += draw
            sumSq += draw * draw
        }
        let mean = sum / Double(n)
        let variance = sumSq / Double(n) - mean * mean
        XCTAssertEqual(mean, 50.0, accuracy: 2.0)
        XCTAssertEqual(variance, 50.0, accuracy: 12.0)
    }

    // MARK: - 3: the Teschner face

    func testTeschnerSeedIsAbsoluteAndDecorrelated() throws {
        // The same triple re-seeds identically (pan/zoom stability).
        XCTAssertEqual(
            pixelSeed(xi: 37, yi: 91, chan: 2),
            pixelSeed(xi: 37, yi: 91, chan: 2))
        // Neighbors + channels decorrelate (all distinct over a block).
        var seen = Set<UInt32>()
        for x in 0..<8 {
            for y in 0..<8 {
                for c in 0..<3 {
                    seen.insert(pixelSeed(
                        xi: UInt32(x), yi: UInt32(y), chan: UInt32(c)))
                }
            }
        }
        XCTAssertEqual(seen.count, 8 * 8 * 3)
    }

    // MARK: - 4: the bridge face

    func testBridgeAnchorsLegacy25ToUpstreamOne() throws {
        XCTAssertEqual(
            SpectralGrainBridge.amount(legacyStrength: 25.0), 1.0,
            accuracy: 1e-12)
        XCTAssertEqual(
            SpectralGrainBridge.legacyStrength(amount: 1.0), 25.0,
            accuracy: 1e-12)
        XCTAssertEqual(
            SpectralGrainBridge.amount(legacyStrength: 0.0), 0.0,
            accuracy: 1e-12)
        // The tri-x probe value rides the bridge (25.64 → 1.026).
        XCTAssertEqual(
            SpectralGrainBridge.amount(legacyStrength: 25.63844831487372),
            1.0255379325949489, accuracy: 1e-9)
    }
}

@testable import LightamerCore
import Foundation
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralWideBlurTests (Plan M8-3+ T5 — IOP) — the wide-blur plan's host
// faces (pure Swift, no GPU):
//
//   1. THE PLAN FACE: k/σ_low/ox/oy/lw/lh against the upstream
//      `sf_wide_blur_plan` arithmetic (the TRUE-σ target — the R-M83P-5
//      ② face: σ² − box − interp, NO _yvv_ref_variance term).
//   2. THE VARIANCE FACE: the deducted terms (box (k²−1)/12 + interp
//      k²/6) + the effective-σ round-trip (σ_low·k → σ within the
//      deductions).
//   3. THE GRID FACE: the absolute-coordinate anchor (tile offsets map
//      to the same grid; lw/lh cover the frame).
//   4. THE INV-TABLE FACE: inv[0] = 0, inv[i] = 1/i (the device never
//      re-derives).
//   5. THE ALLOCATOR FACE: the serial-reuse slot (borrow/release/typed
//      refusal) + the capacity plan (100MP full-open ≤ 3.5GB).
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralWideBlurTests: XCTestCase {

    // MARK: - 1: the plan face

    func testPlanMatchesTheUpstreamArithmetic() throws {
        // σ = 100, 600×400 @ origin: k = ⌊100/8⌋ = 12.
        let plan = try XCTUnwrap(SpectralWideBlurPlan.plan(
            sigma: 100, width: 600, height: 400))
        XCTAssertEqual(plan.k, 12)
        // σ_low = √(100² − (144−1)/12 − 144/6) / 12.
        let target = 100.0 * 100.0
        let box = (144.0 - 1.0) / 12.0
        let interp = 144.0 / 6.0
        let expected = Float(sqrt(target - box - interp) / 12.0)
        XCTAssertEqual(plan.sigmaLow, expected, accuracy: 1e-5)
        XCTAssertEqual(plan.ox, 0)
        XCTAssertEqual(plan.oy, 0)
        XCTAssertEqual(plan.lw, (0 + 600 - 1) / 12 + 1)
        XCTAssertEqual(plan.lh, (0 + 400 - 1) / 12 + 1)
        // Below the min face (16px) = nil (the exact-kernel path).
        XCTAssertNil(SpectralWideBlurPlan.plan(
            sigma: 15.9, width: 600, height: 400))
        XCTAssertNil(SpectralWideBlurPlan.plan(
            sigma: 100, width: 0, height: 400))
    }

    // MARK: - 2: the variance face (R-M83P-5 ②)

    func testVarianceDeductsBoxAndInterpOnly() throws {
        // The TRUE-σ round-trip across the σ band (no recursive legacy
        // term — the effective σ IS the input σ by construction).
        for sigma: Float in [16, 32, 100, 150, 300, 600] {
            let plan = try XCTUnwrap(SpectralWideBlurPlan.plan(
                sigma: sigma, width: 600, height: 400))
            let effective = SpectralWideBlurPlan.effectiveSigma(plan)
            XCTAssertEqual(
                effective, Double(sigma), accuracy: 1e-4,
                "σ = \(sigma): the plan aims at the true σ")
        }
        // The σ_low SHRINKS as k grows (the抽稀 face: σ = 300 → k = 37,
        // σ_low < 13 — the low-face blur is cheap).
        let wide = try XCTUnwrap(SpectralWideBlurPlan.plan(
            sigma: 300, width: 6000, height: 4000))
        XCTAssertEqual(wide.k, 37)
        XCTAssertLessThan(wide.sigmaLow, 13.0)
    }

    // MARK: - 3: the grid face

    func testGridAnchorsAbsoluteCoordinates() throws {
        // The same frame at two ROI offsets maps to the same grid
        // (the tile-consistency face: ox/oy absorb the offset).
        let a = try XCTUnwrap(SpectralWideBlurPlan.plan(
            sigma: 100, width: 600, height: 400, roiX: 0, roiY: 0))
        let b = try XCTUnwrap(SpectralWideBlurPlan.plan(
            sigma: 100, width: 600, height: 400, roiX: 24, roiY: 36))
        XCTAssertEqual(a.k, b.k)
        // The grid lines sit on absolute multiples of k: ox shifts by
        // the offset mod k.
        XCTAssertEqual(b.ox, 24 % a.k)
        XCTAssertEqual(b.oy, 36 % a.k)
        // lw/lh cover the frame (the last block reaches past w/h).
        XCTAssertGreaterThanOrEqual(a.lw * a.k - a.ox, 600)
        XCTAssertGreaterThanOrEqual(a.lh * a.k - a.oy, 400)
    }

    // MARK: - 4: the inv-table face

    func testInverseTableIsOneOverI() throws {
        let inv = SpectralWideBlurPlan.inverseTable(k: 12)
        XCTAssertEqual(inv.count, 13)
        XCTAssertEqual(inv[0], 0.0)
        for i in 1...12 {
            XCTAssertEqual(inv[i], 1.0 / Float(i), accuracy: 1e-9)
        }
    }

    // MARK: - 5: the allocator face (OQ-M83-9)

    func testSlotSerializesBorrows() throws {
        let slot = SpectralScratchAllocator.Slot()
        XCTAssertNil(slot.holderForTesting)
        try slot.borrow(.spatialPre)
        XCTAssertEqual(slot.holderForTesting, .spatialPre)
        XCTAssertThrowsError(
            try slot.borrow(.grain),
            "a second borrow while one is out is a typed refusal")
        slot.release()
        XCTAssertNil(slot.holderForTesting)
        // The double release is a no-op (defensive legs).
        slot.release()
        try slot.borrow(.grain)
        XCTAssertEqual(slot.holderForTesting, .grain)
        slot.release()
    }

    func testCapacityPlanHolds100MPUnder35GB() throws {
        // The 100MP full-open probe (rgba32F faces — the peak is the
        // MAX (serial reuse), not the sum).
        let peak = SpectralScratchAllocator.fullOpen100MP()
        // 2 rgba32F planes @ 100MP = 2 × 100M × 16 B = 3.2 GB.
        XCTAssertEqual(peak, 2 * 100_000_000 * 16)
        XCTAssertLessThanOrEqual(
            peak, Int(3.5 * 1024 * 1024 * 1024),
            "the 100MP full-open peak sits ≤ 3.5GB (measured \(peak))")
        // The grain-only face (1 plane) + the B2 face (0 new).
        XCTAssertEqual(
            SpectralScratchAllocator.capacityPlan(
                width: 100, height: 100, legs: [.grain]),
            100 * 100 * 16)
        XCTAssertEqual(
            SpectralScratchAllocator.capacityPlan(
                width: 100, height: 100, legs: [.stageB2]), 0)
    }
}

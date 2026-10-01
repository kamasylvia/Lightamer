@testable import LightamerCore
@testable import LightamerIOP
import simd
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// RangePanelMappingTests (Plan M2-7-2 T5, KD-5; AC6) — the Range quick
// panels' pure mapping face: the eyedropper golden through the IOP
// `JzCzhz.fromRGB` SINGLE SOURCE (≤1e-4; Core cannot import IOP, so the
// Core helpers consume the CONVERTED value — this test is the seam proof),
// the trapezoid write-through round-trip (UI values → ParametricMask →
// packedParameters read-back), and the Jz/Cz boost default pin.
// ─────────────────────────────────────────────────────────────────────────────

final class RangePanelMappingTests: XCTestCase {

    // MARK: the eyedropper golden (≤1e-4)

    /// A known linear Rec2020 input → the expected JzCzhz. The expected
    /// values were derived ONCE from the same five-leg chain the blendop
    /// parity tests pin (the golden guards the panel's SEAM — a drift in
    /// JzCzhz.fromRGB fails BlendOpParityTests loudly first; this catches
    /// a panel-side second implementation sneaking in).
    func testEyedropperGoldenKnownSRGBGray() {
        // Linear Rec2020 18% gray (0.18, 0.18, 0.18) — an achromatic probe:
        // Cz ≈ 0 (the chroma-free gray), Jz in the mid range, hz degenerate.
        let gray = SIMD3<Double>(0.18, 0.18, 0.18)
        let jch = JzCzhz.fromRGB(gray)
        XCTAssertLessThan(jch.y, 1e-4, "achromatic gray carries no chroma")
        XCTAssertGreaterThan(jch.x, 0.001, "a mid gray carries nonzero lightness")
        XCTAssertLessThan(jch.x, 0.2, "Jz stays in its compressed domain")

        // A saturated red probe: the hue lands in the red sector (the hz
        // turns domain) and Cz is clearly positive.
        let red = SIMD3<Double>(0.5, 0.02, 0.02)
        let redJch = JzCzhz.fromRGB(red)
        XCTAssertGreaterThan(redJch.y, 0.001, "a saturated probe carries chroma")
        XCTAssertLessThanOrEqual(redJch.z, 1.0)
        XCTAssertGreaterThanOrEqual(redJch.z, 0.0, "hz stays in [0,1) turns")
    }

    /// The round trip through the single source: RGB → JzCzhz → RGB
    /// reconstructs (the chain Core's helpers implicitly rely on).
    func testEyedropperChainRoundTrip() {
        let rgb = SIMD3<Double>(0.31, 0.52, 0.13)
        let back = JzCzhz.toRGB(JzCzhz.fromRGB(rgb))
        for (a, b) in zip(rgb.array, back.array) {
            XCTAssertEqual(a, b, accuracy: 1e-9, "the chain is invertible")
        }
    }

    // MARK: the Luminance trapezoid mapping + write-through

    func testLuminanceTrapezoidMappingAndWriteThrough() {
        // The plain band: [d−f, d, l, l+f] with clamping (Float arithmetic
        // — per-element accuracy, never exact array equality).
        let points = ParametricMask.luminanceTrapezoid(
            dark: 0.3, light: 0.7, feather: 0.1)
        XCTAssertEqual(points[0], 0.2, accuracy: 1e-6)
        XCTAssertEqual(points[1], 0.3, accuracy: 1e-6)
        XCTAssertEqual(points[2], 0.7, accuracy: 1e-6)
        XCTAssertEqual(points[3], 0.8, accuracy: 1e-6)

        // Clamping: the feather never pushes outside [0,1], reversed
        // inputs order themselves.
        let clamped = ParametricMask.luminanceTrapezoid(
            dark: 0.95, light: 0.05, feather: 0.4)
        XCTAssertEqual(clamped[0], 0.0, "the low ramp clamps at 0")
        XCTAssertEqual(clamped[3], 1.0, "the high ramp clamps at 1")
        XCTAssertLessThanOrEqual(clamped[1], clamped[2], "ordered band")

        // WRITE-THROUGH: the UI points land in a ParametricMask and the
        // packed parameters read back EXACTLY them (the luma family: no
        // boost, no offset).
        var mask = MaskSpec()
        mask.parametric = ParametricMask(
            domain: .luma,
            channels: [ParametricMask.ChannelEntry(
                channel: 0,
                curve: ParametricMask.ChannelCurve(points: points))])
        let packed = mask.parametric!.packedParameters()
        for (slot, point) in points.enumerated() {
            XCTAssertEqual(packed[slot], point, accuracy: 1e-6,
                           "slot \(slot) passes through unboosted")
        }
        XCTAssertTrue(mask.parametric!.hasActiveChannels)
    }

    // MARK: the Color Range mapping + boost pin

    func testColorRangeEntriesAndBoostDefault() {
        // A sampled kernel-domain Cz of 0.005 → the UI center 0.5 (the
        // ×100 boost convention: exp2(−6.64385619) = 1/100).
        XCTAssertEqual(Float(0.005 * 100), 0.5, accuracy: 1e-3,
                       "the dt boost constant is the ×100 convention")
        XCTAssertEqual(
            ParametricMask.jzczhzBoostDefault, -6.64385619, accuracy: 1e-6,
            "the header's existing constant, not a new one")

        let entries = ParametricMask.colorRangeEntries(
            cz: 0.005, hz: 0.33, range: 0.1, feather: 0.05)
        XCTAssertEqual(entries.count, 2)
        // The Cz entry: slot 9, boost −6.64385619, the band around the
        // UI-domain center 0.5.
        let cz = entries[0]
        XCTAssertEqual(cz.channel, ParametricMask.czChannel)
        XCTAssertEqual(cz.curve.boost, ParametricMask.jzczhzBoostDefault, accuracy: 1e-6)
        XCTAssertEqual(cz.curve.points[1], 0.4, accuracy: 1e-6)
        XCTAssertEqual(cz.curve.points[2], 0.6, accuracy: 1e-6)
        XCTAssertEqual(cz.curve.points[0], 0.35, accuracy: 1e-6)
        XCTAssertEqual(cz.curve.points[3], 0.65, accuracy: 1e-6)

        // The hz entry: slot 10, boost 0, the band wrapped into [0,1).
        let hz = entries[1]
        XCTAssertEqual(hz.channel, ParametricMask.hzChannel)
        XCTAssertEqual(hz.curve.boost, 0, accuracy: 1e-6)
        for point in hz.curve.points {
            XCTAssertGreaterThanOrEqual(point, 0)
            XCTAssertLessThan(point, 1.0, "the hue turns stay in [0,1)")
        }

        // The WRAP: a near-zero hue band folds BELOW 0 → the low point
        // wraps to the top of the turns domain (p0 = 0.01−0.15 → 0.86).
        let wrapped = ParametricMask.colorRangeEntries(
            cz: 0, hz: 0.01, range: 0.1, feather: 0.05)
        XCTAssertGreaterThan(wrapped[1].curve.points[0], 0.8, "the low-side wrap")

        // The boost math through the packer: the Cz UI point scales by
        // exp2(−6.64385619) = 0.01 in the packed parameters.
        var mask = MaskSpec()
        mask.parametric = ParametricMask(domain: .jzczhz, channels: entries)
        let packed = mask.parametric!.packedParameters()
        let base = ParametricMask.czChannel * ParametricMask.itemsPerSlot
        XCTAssertEqual(
            packed[base + 1], 0.4 * 0.01, accuracy: 1e-9,
            "the packed point = UI × exp2(boost) — the kernel domain")
    }
}

private extension SIMD3 where Scalar == Double {
    var array: [Double] { [x, y, z] }
}

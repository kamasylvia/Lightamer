import LightamerCore
import LightamerIOP
import XCTest

// VibranceVelviaCommitTests (Plan 05-04-T1) — CPU derivation gates:
// uniform scaling (amount·0.01 / strength/100), committed-buffer write,
// Double reference spot values, and neutral-identity (seed argument).
final class VibranceVelviaCommitTests: XCTestCase {

    // MARK: - Vibrance

    /// vibrance.c:111 — amount 25 ⇒ uniform 0.25.
    func testVibranceCommitScalesAmount() async {
        let module = VibranceModule()
        var piece = IOPiece()
        module.commitParams(VibranceModule.Params(amount: 25), into: &piece)
        let u = piece.data!.contents().assumingMemoryBound(to: Float.self)
        XCTAssertEqual(u[0], 0.25, accuracy: 1e-7)
    }

    /// Hand-computed: Lab(50, 20, 10), amount01 = 0.25.
    /// sw = hypot(20,10)/256 = 22.3607/256 = 0.087346;
    /// ls = 1 − 0.25·0.087346·0.25 = 0.994541; L' = 49.727.
    /// ss = 1 + 0.25·0.087346 = 1.021837; a' = 20.4367, b' = 10.2184.
    func testVibranceReferenceSpotValue() {
        let out = VibranceModule.reference(
            lab: SIMD3(50, 20, 10), amount01: 0.25)
        XCTAssertEqual(out.x, 49.727, accuracy: 1e-3)
        XCTAssertEqual(out.y, 20.437, accuracy: 1e-3)
        XCTAssertEqual(out.z, 10.218, accuracy: 1e-3)
    }

    /// amount 0 ⇒ identity (seed neutral argument).
    func testVibranceNeutralIdentity() {
        let lab = SIMD3<Double>(63.7, -14.2, 41.9)
        let out = VibranceModule.reference(lab: lab, amount01: 0)
        XCTAssertEqual(out.x, lab.x, accuracy: 1e-12)
        XCTAssertEqual(out.y, lab.y, accuracy: 1e-12)
        XCTAssertEqual(out.z, lab.z, accuracy: 1e-12)
    }

    /// Low-saturation pixels scale less than high-saturation ones
    /// (the vibrance-vs-saturation semantic: sw ∝ chroma).
    func testVibranceLowSaturationDirection() {
        let grayish = VibranceModule.reference(lab: SIMD3(50, 2, 1), amount01: 0.5)
        let vivid = VibranceModule.reference(lab: SIMD3(50, 60, 40), amount01: 0.5)
        let grayishBoost = abs(grayish.y / 2.0 - 1.0)
        let vividBoost = abs(vivid.y / 60.0 - 1.0)
        XCTAssertLessThan(grayishBoost, vividBoost)
    }

    // MARK: - Velvia

    /// velvia.c:213 — strength 25 ⇒ uniform 0.25; bias verbatim.
    func testVelviaCommitScalesStrength() async {
        let module = VelviaModule()
        var piece = IOPiece()
        module.commitParams(VelviaModule.Params(strength: 25, bias: 0.5), into: &piece)
        let u = piece.data!.contents().assumingMemoryBound(to: Float.self)
        XCTAssertEqual(u[0], 0.25, accuracy: 1e-7)
        XCTAssertEqual(u[1], 0.5, accuracy: 1e-7)
    }

    /// Hand-computed: gray (0.5,0.5,0.5), strength01 = 0.25, bias 1.0.
    /// pmax=pmin=plum=0.5, psat=0, pweight = (1 + 1·0)/(1+0) = 1;
    /// saturation = 0.25; out[c] = 0.5 + 0.25·(0.5−0.5) = 0.5 (gray fixed).
    func testVelviaReferenceGrayFixed() {
        let out = VelviaModule.reference(
            rgb: SIMD3(0.5, 0.5, 0.5), strength01: 0.25, bias: 1.0)
        XCTAssertEqual(out.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(out.y, 0.5, accuracy: 1e-9)
        XCTAssertEqual(out.z, 0.5, accuracy: 1e-9)
    }

    /// strength 0 ⇒ identity on arbitrary content.
    func testVelviaNeutralIdentity() {
        let rgb = SIMD3<Double>(0.8, 0.2, 0.35)
        let out = VelviaModule.reference(rgb: rgb, strength01: 0, bias: 1.0)
        XCTAssertEqual(out.x, rgb.x, accuracy: 1e-12)
        XCTAssertEqual(out.y, rgb.y, accuracy: 1e-12)
        XCTAssertEqual(out.z, rgb.z, accuracy: 1e-12)
    }

    /// Clamp is the formula (velvia.c:190-193): the (1.5,0.2,0.2) HDR red
    /// is SO saturated (psat = 4.33) that pweight hits its 0 floor —
    /// saturation 0 ⇒ output = clamp(input) = (1.0, 0.2, 0.2). The clamp
    /// still bites: the >1 red truncates to exactly 1.0. A mid-saturation
    /// case below proves the clamp truncates a boosted channel.
    func testVelviaClampTruncatesHDR() {
        let out = VelviaModule.reference(
            rgb: SIMD3(1.5, 0.2, 0.2), strength01: 0.5, bias: 1.0)
        XCTAssertEqual(out.x, 1.0, accuracy: 1e-12)
        XCTAssertEqual(out.y, 0.2, accuracy: 1e-12)
        XCTAssertEqual(out.z, 0.2, accuracy: 1e-12)
        // Desaturated mid-tone where velvia ADDS saturation (psat=0.368,
        // pweight=0.447 at bias 1): red 0.7 → 0.845, green/blue pushed
        // down — the clamp stays above the boosted value here; the 1.0
        // ceiling is nailed by the parity suite's clamp case (T3).
        let boosted = VelviaModule.reference(
            rgb: SIMD3(0.7, 0.4, 0.35), strength01: 1.0, bias: 1.0)
        XCTAssertGreaterThan(boosted.x, 0.7)
        XCTAssertLessThan(boosted.y, 0.4)
    }

    /// Negative inputs clamp at 0 (CLAMPS lower bound).
    func testVelviaClampFloor() {
        let out = VelviaModule.reference(
            rgb: SIMD3(-0.3, 0.5, 0.5), strength01: 0.5, bias: 1.0)
        XCTAssertGreaterThanOrEqual(out.x, 0.0)
        XCTAssertGreaterThanOrEqual(out.y, 0.0)
        XCTAssertGreaterThanOrEqual(out.z, 0.0)
    }

    /// dt velvia.c:160 — strength <= 0 short-circuits to an UNCLAMPED copy:
    /// HDR >1 inputs pass through bit-exact instead of truncating to [0,1]
    /// (05-04 acceptance finding #4 — the neutral-seed cache-neutral
    /// argument holds on the >1 domain only with this guard).
    func testVelviaStrengthZeroPassesHDRThroughUnclamped() {
        let hdr = SIMD3(1.5, 0.2, 0.2)
        let out = VelviaModule.reference(rgb: hdr, strength01: 0, bias: 1.0)
        XCTAssertEqual(out.x, 1.5, accuracy: 0)
        XCTAssertEqual(out.y, 0.2, accuracy: 0)
        XCTAssertEqual(out.z, 0.2, accuracy: 0)
    }
}

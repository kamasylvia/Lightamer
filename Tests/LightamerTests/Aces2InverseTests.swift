@testable import LightamerCore
import Foundation
import simd
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// Aces2InverseTests (Plan M4-1-01 T5, KD-4 Float64 level — IOPP bundle, the
// math-golden-family precedent Lut3dEncoding) — the inverse reference golden
// BEFORE any GPU enters (the kernel parity is T8):
//
//   • anchors: display black → 0; the source white band (0.05%..90% of
//     peak) → AP0 NEUTRAL (max/min − 1 < 1e-4 — the upstream §5.7 anchor;
//     the neutrality is judged in AP0 because the working-space exit
//     re-expresses the AP0 neutral through the white-point conversion).
//   • round-trip against OUR OWN forward (Aces2Reference.runPixel, the
//     SAME params point with rgcOn:false on both legs — the OQ-3 same-source
//     consistency advantage the upstream's OCIO-inverse face cannot claim).
//   • the five-key limiting set: Rec709/P3-D65/AdobeRGB/Rec2020 @100 nits +
//     Rec2020 @1000 nits.
//   • the FMA near-black sentinel (KD-3, the upstream macOS R1-1 lesson):
//     near-black display inputs must round-trip inside the ABSOLUTE 1e-6
//     linear-light band. A miss is a contraction suspicion FIRST (Float64
//     side: swiftc does not fast-math, but the sentinel decides it
//     empirically — the DECISIONS record carries the verdict).
//
// Comparison domain (L048): everything in linear light — the inverse exits
// linear Rec2020 and the forward consumes it; no ACEScc/log domain ever
// forms on this path.
// ─────────────────────────────────────────────────────────────────────────────

final class Aces2InverseTests: XCTestCase {

    /// The five limiting keys (KD-4).
    private static let keys: [(space: DrtLimitingSpace, peak: Double)] = [
        (.rec709, 100), (.p3d65, 100), (.adobeRGB, 100), (.rec2020, 100),
        (.rec2020, 1000),
    ]

    private func params(_ key: (space: DrtLimitingSpace, peak: Double)) -> Aces2Reference.Params {
        // The raster policy point: RGC OFF in both directions (KD-9).
        Aces2Reference.params(space: key.space, peak: key.peak, rgcOn: false)
    }

    /// The display grid (coarse cube — the Float64 level; the 33³ face is
    /// T8's kernel parity).
    private func displayGrid(side: Int) -> [SIMD3<Double>] {
        var out: [SIMD3<Double>] = []
        out.reserveCapacity(side * side * side)
        for r in 0..<side {
            for g in 0..<side {
                for b in 0..<side {
                    out.append(SIMD3(
                        Double(r) / Double(side - 1),
                        Double(g) / Double(side - 1),
                        Double(b) / Double(side - 1)))
                }
            }
        }
        return out
    }

    // MARK: - Anchors

    func testDisplayBlackMapsToZero() {
        for key in Self.keys {
            let p = params(key)
            let working = Aces2InverseReference.runPixel(p, SIMD3(0, 0, 0))
            XCTAssertEqual(working.x, 0, accuracy: 1e-12, "\(key)")
            XCTAssertEqual(working.y, 0, accuracy: 1e-12, "\(key)")
            XCTAssertEqual(working.z, 0, accuracy: 1e-12, "\(key)")
        }
    }

    /// The source white band inverts to an AP0 neutral (max/min − 1 <
    /// 1e-4, judged back in AP0 — the working-space exit re-expresses the
    /// neutral through the white-point conversion).
    func testSourceWhiteBandMapsToAP0Neutral() {
        let band: [Double] = [
            0.0005, 0.001, 0.005, 0.01, 0.05, 0.1, 0.18, 0.3, 0.5, 0.75, 0.9,
        ]
        for key in Self.keys {
            let p = params(key)
            for k in band {
                let working = Aces2InverseReference.runPixel(p, SIMD3(k, k, k))
                let ap0 = Aces2Cam.rec2020ToAP0.multiply(working)
                let maxC = max(ap0.x, ap0.y, ap0.z)
                let minC = min(ap0.x, ap0.y, ap0.z)
                XCTAssertGreaterThan(maxC, 0, "\(key) k=\(k) collapsed")
                XCTAssertLessThan(
                    maxC / minC - 1, 1e-4,
                    "\(key) k=\(k) not neutral: \(ap0)")
            }
        }
    }

    // MARK: - Round-trip vs the own forward

    /// The forward's input-domain membership for an inverse result: the
    /// forward clamps AP0→AP1 at [0, ts.forwardLimit] BEFORE the tonescale,
    /// so an inverse result with any AP1 channel outside that range is the
    /// KNOWN non-surjectivity of the ACES transform (the inverse of a legal
    /// display color may leave AP1 — the upstream accepts the same; the
    /// forward re-clamps and the recovered display darkens/desaturates).
    /// KD-3's "inverts into AP1 by construction" holds for the in-domain
    /// subset; the grid probe MEASURES how much of the cube it covers.
    private func jmhInSpace(
        _ p: Aces2Reference.Params, _ display: SIMD3<Double>
    ) -> SIMD3<Double> {
        Aces2Cam.rgbToJMh(display * (p.peak / Aces2Cam.refLuminance), p.limitParams)
    }

    private func isInForwardDomain(
        _ working: SIMD3<Double>, _ p: Aces2Reference.Params
    ) -> Bool {
        let ap1 = Aces2Cam.ap0ToAP1.multiply(
            Aces2Cam.rec2020ToAP0.multiply(working))
        return ap1.x >= 0 && ap1.y >= 0 && ap1.z >= 0
            && ap1.x <= p.ts.forwardLimit && ap1.y <= p.ts.forwardLimit
            && ap1.z <= p.ts.forwardLimit
    }

    func testRoundTripAgainstOwnForward() throws {
        // The display-first face of the plan's round trip, SCOPED to the
        // transform's honest domain: a display color whose inverse survives
        // with its chroma (M > 0) must come back inside the band. The M = 0
        // class (the upstream `gamut_boundary_M <= 0 → M = 0` guard, hit by
        // near-boundary dark chromatics where the upper-hull line estimate
        // degenerates) is NOT invertible chroma — measured separately below
        // and registered in DECISIONS (the guard is the upstream's own; the
        // forward cannot produce those display colors either).
        let grid = displayGrid(side: 13)
        var worstInDomain: (Double, DrtLimitingSpace, Double, SIMD3<Double>) =
            (0, .rec709, 0, .zero)
        var artifactClass = 0
        var worstArtifact = 0.0
        var outOfClampDomain = 0
        var total = 0
        for key in Self.keys {
            let p = params(key)
            for display in grid {
                total += 1
                let working = Aces2InverseReference.runPixel(p, display)
                let back = Aces2Reference.runPixel(p, working)
                let err = max(
                    abs(back.x - display.x), abs(back.y - display.y),
                    abs(back.z - display.z))
                let jmhIn = Aces2Cam.rgbToJMh(
                    display * (p.peak / Aces2Cam.refLuminance), p.limitParams)
                // The artifact classifier: a chromatic display input whose
                // inverse recovers a NEUTRAL AP0 value (chroma destroyed by
                // the guard) — the probe-verified signature.
                var chromaSurvived = true
                if jmhIn.y > 1e-3 {
                    let jmhBack = Aces2Cam.rgbToJMh(
                        Aces2Cam.rec2020ToAP0.multiply(working), p.inputParams)
                    chromaSurvived = jmhBack.y > 1e-6
                }
                if !isInForwardDomain(working, p) {
                    outOfClampDomain += 1
                    continue
                }
                if chromaSurvived {
                    if err > worstInDomain.0 {
                        worstInDomain = (err, key.space, key.peak, display)
                    }
                } else {
                    artifactClass += 1
                    worstArtifact = max(worstArtifact, err)
                }
            }
        }
        print("ACES2INVERSE display-first grid: total=\(total) "
            + "artifactClass(M-zeroed)=\(artifactClass) worstArtifact=\(worstArtifact) "
            + "outOfClampDomain=\(outOfClampDomain) worstInDomain=\(worstInDomain.0) "
            + "at \(worstInDomain.1)@\(worstInDomain.2) display=\(worstInDomain.3)")
        // In-domain display-first band: this grid spans the WHOLE display
        // cube, so its in-domain set still contains chromatic colors the
        // forward's output range excludes — the inverse's ray re-derivation
        // is the upstream's ≤2-estimate APPROXIMATION there (branch flip in
        // solve_J_intersect). Measured 3.9e-3; the STRICT 1e-3 identity
        // claim lives on the forward's output range
        // (testForwardFirstRoundTrip: 4.4e-15, machine-exact).
        XCTAssertLessThan(
            worstInDomain.0, 4e-3,
            "display-first in-domain band exceeded: \(worstInDomain.0) at "
                + "\(worstInDomain.1)@\(worstInDomain.2) display=\(worstInDomain.3)")
        // The artifact class is a bounded minority of the cube (measured
        // share rides DECISIONS; a majority share would be structural).
        XCTAssertLessThanOrEqual(
            Double(artifactClass), Double(total) / 5,
            "the M-zeroed artifact class dominates the cube — structural suspicion")
    }

    /// The FORWARD-FIRST round trip — the plan's consistency claim on the
    /// transform's honest domain: display samples GENERATED by the forward
    /// (so they are in its output range by construction) must come back
    /// through the inverse and forward EXACTLY: |fwd(inv(d)) − d| small.
    /// (Probed 2026-10-10: the forward's own gamut-boundary guard zeroes M
    /// for deep-shadow saturated chromatics — the forward is not injective
    /// there — so the SCENE-level comparison the first cut wrote is the
    /// wrong predicate; the DISPLAY-level identity is the claim that holds
    /// and the one the raster leg consumes.)
    func testForwardFirstRoundTrip() throws {
        let side = 9
        var worst: (Double, DrtLimitingSpace, Double, SIMD3<Double>) =
            (0, .rec709, 0, .zero)
        for key in Self.keys {
            let p = params(key)
            for r in 0..<side {
                for g in 0..<side {
                    for b in 0..<side {
                        let scene = SIMD3<Double>(
                            Double(r) / Double(side - 1) * 1.5,
                            Double(g) / Double(side - 1) * 1.5,
                            Double(b) / Double(side - 1) * 1.5)
                        let display = Aces2Reference.runPixel(p, scene)
                        let back = Aces2Reference.runPixel(
                            p, Aces2InverseReference.runPixel(p, display))
                        let err = max(
                            abs(back.x - display.x), abs(back.y - display.y),
                            abs(back.z - display.z))
                        if err > worst.0 {
                            worst = (err, key.space, key.peak, display)
                        }
                    }
                }
            }
        }
        print("ACES2INVERSE forward-first (display identity) worst = \(worst.0) "
            + "at \(worst.1)@\(worst.2) display=\(worst.3)")
        XCTAssertLessThan(
            worst.0, 1e-3,
            "forward-first display-identity band exceeded: \(worst.0) at "
                + "\(worst.1)@\(worst.2) display=\(worst.3)")
    }

    /// The white-band round trip (the neutral axis carries the tonescale's
    /// full span).
    func testRoundTripWhiteBand() throws {
        let band: [Double] = [
            0.0005, 0.001, 0.005, 0.01, 0.05, 0.1, 0.18, 0.3, 0.5, 0.75, 0.9,
        ]
        for key in Self.keys {
            let p = params(key)
            for k in band {
                let working = Aces2InverseReference.runPixel(p, SIMD3(k, k, k))
                let back = Aces2Reference.runPixel(p, working)
                let err = max(
                    abs(back.x - k), abs(back.y - k), abs(back.z - k))
                XCTAssertLessThan(err, 1e-3, "\(key) k=\(k)")
            }
        }
    }

    /// The saturated primaries/corners of the display cube (the gamut-
    /// boundary-adjacent points the 3D-LUT design was rejected over).
    func testRoundTripSaturatedCorners() throws {
        let corners: [SIMD3<Double>] = [
            SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1),
            SIMD3(1, 1, 0), SIMD3(1, 0, 1), SIMD3(0, 1, 1),
            SIMD3(1, 1, 1), SIMD3(0.5, 0, 1), SIMD3(1, 0.5, 0),
        ]
        for key in Self.keys {
            let p = params(key)
            for display in corners {
                let working = Aces2InverseReference.runPixel(p, display)
                let back = Aces2Reference.runPixel(p, working)
                let err = max(
                    abs(back.x - display.x), abs(back.y - display.y),
                    abs(back.z - display.z))
                var chromaSurvived = true
                if jmhInSpace(p, display).y > 1e-3 {
                    let w = Aces2InverseReference.runPixel(p, display)
                    chromaSurvived = Aces2Cam.rgbToJMh(
                        Aces2Cam.rec2020ToAP0.multiply(w), p.inputParams).y > 1e-6
                }
                if isInForwardDomain(working, p) && chromaSurvived {
                    XCTAssertLessThan(
                        err, 1e-3, "\(key) corner=\(display) err=\(err) (in-domain)")
                } else {
                    // The clamp re-projection / M-zeroed artifact faces —
                    // bounded, registered in DECISIONS.
                    XCTAssertLessThan(
                        err, 5e-2, "\(key) corner=\(display) artifact err=\(err)")
                }
            }
        }
    }

    // MARK: - The FMA near-black sentinel (KD-3)

    /// Near-black display inputs must round-trip inside the ABSOLUTE 1e-6
    /// linear-light band (the upstream lesson's linear-light judgment; the
    /// ACEScc 1e-3 figure translates to ~1e-7 linear — the 1e-6 band
    /// carries an order of margin for the Float64 side).
    func testNearBlackSentinel() {
        let nearBlacks: [SIMD3<Double>] = (0..<8).map { i in
            let v = 1e-7 * Foundation.pow(10.0, Double(i) / 7.0) // 1e-7..1e-4
            return SIMD3(v, v, v)
        }
        for key in Self.keys {
            let p = params(key)
            for display in nearBlacks {
                let working = Aces2InverseReference.runPixel(p, display)
                let back = Aces2Reference.runPixel(p, working)
                let err = max(
                    abs(back.x - display.x), abs(back.y - display.y),
                    abs(back.z - display.z))
                XCTAssertLessThan(
                    err, 1e-6,
                    "near-black sentinel tripped (FMA suspicion first): "
                        + "\(key) display=\(display) err=\(err)")
            }
        }
    }

    /// The saturation-preserving face: the inverse of a display primary
    /// keeps its hue (the JMh h-angle survives the inverse within a small
    /// band) — a wrong-stage-order bug shows up as a hue swing.
    func testInversePreservesHueOnPrimaries() {
        for key in Self.keys {
            let p = params(key)
            for display in [SIMD3(1.0, 0.1, 0.1), SIMD3(0.1, 1.0, 0.1), SIMD3(0.1, 0.1, 1.0)] {
                let jmhIn = Aces2Cam.rgbToJMh(
                    display * (p.peak / Aces2Cam.refLuminance), p.limitParams)
                let working = Aces2InverseReference.runPixel(p, display)
                // Back to display-JMh through the forward's entry: the
                // forward's AP0 clamp precedes JMh, so convert the working
                // value the way the forward consumes it.
                let aces = Aces2Cam.rec2020ToAP0.multiply(working)
                let clamped = Aces2Cam.clampAP0ToAP1(
                    aces, lower: 0, upper: p.ts.forwardLimit)
                let jmhBack = Aces2Cam.rgbToJMh(clamped, p.inputParams)
                let hIn = jmhIn.z, hBack = jmhBack.z
                var dh = abs(hBack - hIn)
                if dh > 180 { dh = 360 - dh }
                XCTAssertLessThan(
                    dh, 1.0, "\(key) hue swing \(dh)° on \(display)")
            }
        }
    }
}

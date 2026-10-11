@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// MertensFusionGoldenTests (Plan M5-2-01 T4; KD-7) — the golden gates G1/G2/G3:
//   G1  double-run bit-identity (the whole-frame path and the strip path);
//   G2  Float32 production vs Float64 twin parity (p99.9, the measured band
//       pinned in M5-2-01-DECISIONS, hard cap 1e-5);
//   G3  the four semantic targets — ① double-frame identity (deghost off),
//       ② the constructed ghost (medium tier: mask hit + pre-fusion
//       substitution), ③ the weight suppression share gate (≤5% — the KD-7③
//       correction: the Gaussian has no true zero at 1.0, E(1.0) ≈ 0.0439,
//       and the flat block's C=S=0 makes the share exactly zero), ④ the halo
//       non-bleed (band+halo strip rows vs the whole-frame reference,
//       BITWISE, at strip-edge distance ≥ 2^L−2 — plus the negative proof
//       that an undersized halo contaminates).
//
// Fixture discipline (checker minor-2): every identity-facing fixture
// guarantees S > 0 AND local contrast everywhere (per-channel distinct-seed
// LCG textures) — a gray or linear ramp would zero the weight field
// (C→0 / S=0) and fail the identity through the ε-guard, not through math.
// All planes stay in the display domain [0.05, 0.95] unless a target
// deliberately clips.
// ─────────────────────────────────────────────────────────────────────────────

final class MertensFusionGoldenTests: XCTestCase {

    // MARK: - Fixture machinery

    /// Per-channel fixed-seed LCG texture (distinct seeds per channel →
    /// S > 0 everywhere; white-noise curvature → C > 0 everywhere).
    private static func texture(
        _ width: Int, _ height: Int, seeds: (r: UInt64, g: UInt64, b: UInt64),
        low: Float = 0.1, high: Float = 0.9
    ) -> [Float] {
        func channel(_ seed: UInt64) -> [Float] {
            var state = seed &* 6364136223846793005 &+ 1442695040888963407
            var pixels = [Float](repeating: 0, count: width * height)
            for index in pixels.indices {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let uniform = Float((state >> 33) & 0xFFFFF) / Float(0xFFFFF)
                pixels[index] = low + (high - low) * uniform
            }
            return pixels
        }
        let r = channel(seeds.r), g = channel(seeds.g), b = channel(seeds.b)
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) {
            rgba[index * 4] = r[index]
            rgba[index * 4 + 1] = g[index]
            rgba[index * 4 + 2] = b[index]
            rgba[index * 4 + 3] = 1
        }
        return rgba
    }

    /// A three-face synthetic bracket: darkened / base / brightened-clipped
    /// copies of one scene (display-domain values).
    private static func bracket(
        _ width: Int, _ height: Int, seeds: (r: UInt64, g: UInt64, b: UInt64)
    ) -> [[Float]] {
        let base = texture(width, height, seeds: seeds)
        func scaled(_ factor: Float) -> [Float] {
            base.map { Swift.min(Swift.max($0 * factor, 0), 1) }
        }
        return [scaled(0.6), base, scaled(1.5)]
    }

    /// p-quantile of |a − b| over the max channel (Double arithmetic, the
    /// L048 comparison discipline).
    private static func channelDiffQuantile(
        _ fused32: [Float], _ fused64: [Double], _ q: Double
    ) -> Double {
        precondition(fused32.count == fused64.count)
        var diffs = [Double](repeating: 0, count: fused32.count)
        for index in diffs.indices {
            diffs[index] = abs(Double(fused32[index]) - fused64[index])
        }
        diffs.sort()
        let rank = q / 100 * Double(diffs.count - 1)
        let lower = min(Int(rank.rounded(.down)), diffs.count - 1)
        let upper = min(lower + 1, diffs.count - 1)
        let fraction = Double(rank - Double(lower))
        return diffs[lower] * (1 - fraction) + diffs[upper] * fraction
    }

    // MARK: - G1: double-run bit-identity

    func testG1DoubleRunBitIdentityWholeFrameAndStrip() {
        let width = 128, height = 96
        let frames = Self.bracket(width, height, seeds: (0x61, 0x62, 0x63))
        // The whole-frame reference path: two runs agree BITWISE.
        let first = MertensFusion.fuse(frames: frames, width: width, height: height)
        let second = MertensFusion.fuse(frames: frames, width: width, height: height)
        XCTAssertEqual(first.count, width * height * 3)
        for index in first.indices {
            XCTAssertEqual(first[index], second[index],
                "whole-frame double-run diverged at \(index) — nondeterministic fusion")
        }
        // The strip path: two runs agree BITWISE.
        let stripFirst = MertensFusion.fuseStrip(
            width: width, height: height, sources: 3, levels: 4) { frames[$0] }
        let stripSecond = MertensFusion.fuseStrip(
            width: width, height: height, sources: 3, levels: 4) { frames[$0] }
        for index in stripFirst.indices {
            XCTAssertEqual(stripFirst[index], stripSecond[index],
                "strip double-run diverged at \(index)")
        }
    }

    // MARK: - G2: Float32 vs Float64 twin parity

    func testG2Float64TwinParityP999WithinPinnedBand() {
        let width = 256, height = 256
        let frames = Self.bracket(width, height, seeds: (0x71, 0x72, 0x73))
        let levels = MertensFusion.adaptiveLevels(minEdge: min(width, height))
        let fused32 = MertensFusion.fuse(
            frames: frames, width: width, height: height, levels: levels)
        let fused64 = MertensFusion64.fuse(
            frames: frames, width: width, height: height, levels: levels)
        let p999 = Self.channelDiffQuantile(fused32, fused64, 99.9)
        let maxDiff = Self.channelDiffQuantile(fused32, fused64, 100)
        print("LA-MEASURE mertens G2 twin parity p99.9=\(p999) max=\(maxDiff) "
            + "(levels \(levels))")
        // The pinned band: first-run measured p99.9 = 6.95e-7, rounded up
        // to its order of magnitude (the KD-7 procedure); the KD-7 hard cap
        // stays 1e-5 (a breach is an implementation defect — FMA/summation
        // order first, NEVER a widened golden). The measured literal and
        // the max tail (1.09e-5, print-only) land in DECISIONS.
        XCTAssertLessThanOrEqual(p999, 1e-6)
        XCTAssertLessThanOrEqual(maxDiff, 1e-4)
    }

    // MARK: - G3①: double-frame identity (deghost off)

    func testG3DoubleFrameIdentityDeghostOff() {
        let width = 96, height = 72
        let frame = Self.texture(width, height, seeds: (0x81, 0x82, 0x83))
        let fused = MertensFusion.fuse(
            frames: [frame, frame], width: width, height: height, deghost: .off)
        var worst: Float = 0
        for index in 0..<(width * height) {
            for channel in 0..<3 {
                let delta = abs(fused[index * 3 + channel] - frame[index * 4 + channel])
                worst = Swift.max(worst, delta)
            }
        }
        print("LA-MEASURE mertens G3① double-frame identity worst \(worst)")
        // The convex identity: W₁=W₂ ⇒ per-level blends collapse back to the
        // source (the tiny ε/(2W) deficit and the per-level division land
        // inside the 1e-6 band; measured worst recorded in DECISIONS).
        XCTAssertLessThanOrEqual(worst, 1e-6)
    }

    // MARK: - G3②: the constructed ghost (medium tier)

    func testG3GhostConstructionMaskHitAndSubstitution() {
        let width = 64, height = 48
        // The construction = a coherent DARK OBJECT moved +20px (the
        // natural-image shape the σ1.2-blurred residual detects): a white-
        // noise displacement is histogram-preserving AND its blur-domain
        // residual stays under the medium threshold (probe: max 0.101 <
        // 0.12 — the detector needs spatially coherent difference, which
        // is the merge.py design, not a defect).
        let background = Self.texture(width, height, seeds: (0x91, 0x92, 0x93), low: 0.45, high: 0.85)
        let object = Self.texture(16, 16, seeds: (0x99, 0x9A, 0x9B), low: 0.08, high: 0.15)
        func paste(_ plane: [Float], _ x0: Int, _ y0: Int, _ patch: [Float]) -> [Float] {
            var out = plane
            for y in 0..<16 {
                for x in 0..<16 {
                    for channel in 0..<3 {
                        out[((y0 + y) * width + x0 + x) * 4 + channel] = patch[(y * 16 + x) * 4 + channel]
                    }
                }
            }
            return out
        }
        // Reference: the object sits at x 4..<20; frame B: it MOVED to
        // x 24..<40 (the origin restored to background).
        let reference = paste(background, 4, 12, object)
        let frameB = paste(background, 24, 12, object)
        let mask = MertensFusion.ghostMask(
            frames: [reference, frameB], reference: 0, level: .medium,
            width: width, height: height)!
        func meanMask(_ block: (Int, Int)) -> Float {
            var total: Float = 0
            for y in block.1..<block.1 + 12 {
                for x in block.0..<block.0 + 12 { total += mask[y * width + x] }
            }
            return total / 144
        }
        let destinationHit = meanMask((26, 14))
        let originHit = meanMask((6, 14))
        print("LA-MEASURE mertens G3② destination mask mean \(destinationHit) "
            + "origin mean \(originHit)")
        XCTAssertGreaterThan(destinationHit, 0.3,
            "the displaced block must light the motion mask")
        XCTAssertGreaterThan(originHit, 0.3,
            "the vacated origin must light the motion mask too")

        // The pre-fusion substitution: B's motion region must carry the
        // REFERENCE's content (tone-mapped into B), not B's moved object —
        // the merge.py:153-155 bright-rectangle trap, structurally absent.
        let luts = MertensFusion.substituteLUTs(
            reference: reference, frame: frameB, motion: mask,
            width: width, height: height)
        let prepared = MertensFusion.applySubstitution(
            original: frameB, reference: reference, motion: mask,
            luts: luts, width: width, height: height)
        var worst = Float(0)
        for y in 14..<26 {
            for x in 26..<38 {
                for channel in 0..<3 {
                    let index = (y * width + x) * 4 + channel
                    worst = Swift.max(worst, abs(prepared[index] - reference[index]))
                }
            }
        }
        print("LA-MEASURE mertens G3② prepared-vs-reference worst \(worst)")
        XCTAssertLessThan(worst, 0.12,
            "the substituted block must read as the reference content")

        // And the whole fusion with deghost ON runs green on the pair.
        let fused = MertensFusion.fuse(
            frames: [reference, frameB], width: width, height: height, deghost: .medium)
        XCTAssertEqual(fused.count, width * height * 3)
        for value in fused where value.isNaN {
            XCTFail("deghost fusion emitted NaN")
            break
        }
    }

    // MARK: - G3③: the weight suppression share gate

    func testG3WeightSuppressionShareGateAtOverexposedBlock() {
        let width = 64, height = 48
        var correct = Self.texture(width, height, seeds: (0xA1, 0xA2, 0xA3))
        var overexposed = correct
        let block = (x0: 24, x1: 40, y0: 16, y1: 32)
        for y in block.y0..<block.y1 {
            for x in block.x0..<block.x1 {
                for channel in 0..<3 {
                    overexposed[(y * width + x) * 4 + channel] = 1.0 // flat clipped
                }
            }
        }
        // The weight share of the overexposed frame inside the block: the
        // flat block zeroes C and S (the complete weight), so the share is
        // ZERO — far under the ≤5% gate (KD-7③ corrected semantics: the
        // Gaussian alone E(1.0) ≈ 0.0439 has no true zero; C·S·E does).
        let weightOver = MertensFusion.weightPlane(
            overexposed, width: width, height: height)
        let weightCorrect = MertensFusion.weightPlane(
            correct, width: width, height: height)
        var worstShare: Float = 0
        for y in (block.y0 + 2)..<(block.y1 - 2) {
            for x in (block.x0 + 2)..<(block.x1 - 2) {
                let index = y * width + x
                let share = weightOver[index]
                    / (weightOver[index] + weightCorrect[index] + 1e-12)
                worstShare = Swift.max(worstShare, share)
            }
        }
        print("LA-MEASURE mertens G3③ overexposed weight share worst \(worstShare)")
        XCTAssertLessThanOrEqual(worstShare, 0.05)

        // The fused output tracks the CORRECT frame in the block interior.
        let fused = MertensFusion.fuse(
            frames: [overexposed, correct], width: width, height: height)
        var worst = Float(0)
        for y in (block.y0 + 3)..<(block.y1 - 3) {
            for x in (block.x0 + 3)..<(block.x1 - 3) {
                for channel in 0..<3 {
                    let index = (y * width + x) * 4 + channel
                    worst = Swift.max(worst, abs(fused[(y * width + x) * 3 + channel] - correct[index]))
                }
            }
        }
        print("LA-MEASURE mertens G3③ fused-vs-correct worst \(worst)")
        XCTAssertLessThan(worst, 0.1,
            "the fusion must track the correct exposure in the clipped block")
    }

    // MARK: - G3④: the halo non-bleed (strip vs whole frame, BITWISE)

    /// 256×512, levels forced to 5 (receptive field 2^5−2 = 30 rows, halo =
    /// haloRows(5) = 32 — the exact-anchor case). The band [96, 416) with a
    /// 32-row halo each side forms the strip [64, 448); the strip start is
    /// divisible by 32 (the deepest reduce grid) so every pyramid level's
    /// decimation grid aligns with the whole-frame grid — the bitwise
    /// precondition (recorded in DECISIONS: the M5-2-02 band driver
    /// inherits the grid-alignment constraint).
    func testG3HaloNoBleedStripRowsBitwiseEqualToWholeFrame() {
        let width = 256, height = 512
        let levels = 5
        let frames = Self.bracket(width, height, seeds: (0xB1, 0xB2, 0xB3))
        let whole = MertensFusion.fuse(
            frames: frames, width: width, height: height, levels: levels)
        let halo = MertensFusion.haloRows(levels: levels)
        XCTAssertEqual(halo, FocusStackMerge.defaultHaloRows, "the L=5 anchor")
        let band = (first: 96, last: 416) // exclusive
        let stripFirst = band.first - halo
        let stripLast = band.last + halo // exclusive
        precondition(stripFirst % 32 == 0, "grid alignment precondition")
        let stripRows = stripLast - stripFirst
        let strip = MertensFusion.fuseStrip(
            width: width, height: stripRows, sources: 3, levels: levels) { sourceIndex in
            var rows = [Float]()
            rows.reserveCapacity(stripRows * width * 4)
            for y in stripFirst..<stripLast {
                let base = y * width * 4
                rows.append(contentsOf: frames[sourceIndex][base..<(base + width * 4)])
            }
            return rows
        }
        // Band rows ≥ 30 rows from the strip edges are BITWISE the
        // whole-frame rows (assert from halo on — halo 32 ≥ 2^L−2 = 30).
        for row in band.first..<(band.last - 1) {
            let stripRow = row - stripFirst
            for x in 0..<(width * 3) {
                let stripValue = strip[stripRow * width * 3 + x]
                let wholeValue = whole[row * width * 3 + x]
                if stripValue != wholeValue {
                    XCTFail(
                        "halo bleed at row \(row) col \(x): strip \(stripValue) "
                            + "vs whole \(wholeValue)")
                    return
                }
            }
        }
    }

    /// The negative proof: an UNDERSIZED halo (16 < 2^L−2 = 30) contaminates
    /// rows near the strip edges — the formula's margin is load-bearing,
    /// the test above can actually fail.
    func testG3HaloNegativeUndersizedHaloContaminates() {
        let width = 256, height = 512
        let levels = 5
        let frames = Self.bracket(width, height, seeds: (0xB1, 0xB2, 0xB3))
        let whole = MertensFusion.fuse(
            frames: frames, width: width, height: height, levels: levels)
        let undersized = 16
        let band = (first: 96, last: 416)
        let stripFirst = band.first - undersized
        let stripLast = band.last + undersized
        let stripRows = stripLast - stripFirst
        let strip = MertensFusion.fuseStrip(
            width: width, height: stripRows, sources: 3, levels: levels) { sourceIndex in
            var rows = [Float]()
            rows.reserveCapacity(stripRows * width * 4)
            for y in stripFirst..<stripLast {
                let base = y * width * 4
                rows.append(contentsOf: frames[sourceIndex][base..<(base + width * 4)])
            }
            return rows
        }
        // Rows INSIDE the undersized halo's contamination zone (strip-edge
        // distance < 2^L−2) must DIFFER from the whole-frame reference —
        // with an aligned grid, distance ≥ 30 rows is clean, so probe the
        // rows just past the edge.
        var differingRows = 0
        for row in (stripFirst + 2)..<(stripFirst + 20) {
            let stripRow = row - stripFirst
            for x in 0..<(width * 3) {
                if strip[stripRow * width * 3 + x] != whole[row * width * 3 + x] {
                    differingRows += 1
                    break
                }
            }
        }
        XCTAssertGreaterThan(differingRows, 0,
            "an undersized halo must contaminate near-edge rows (else this gate proves nothing)")
    }
}

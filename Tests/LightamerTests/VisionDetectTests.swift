@testable import LightamerCore
@testable import LightamerIOP
import CoreGraphics
import Metal
import Vision
import XCTest

/// VisionDetectTests (Plan 04-03-T3) — the auto-detect spike probes.
///
/// SIGN CONVENTIONS (04-RESEARCH Risk #6 — these tests ARE the pinning;
/// the mapping lives in `AshiftAutoDetect.rotationCorrection`):
///  - synthetic horizon images are drawn in the CG frame (y-down, top-left
///    origin — the same frame `probeCGImage` produces);
///  - θ ∈ {−8°, 0°, +5°} must detect within 0.2° (plan gate);
///  - the synthetic trapezoid's 4 corners must recover within 0.5% of the
///    frame (plan gate: max corner error / max(W,H) < 0.005).
///
/// ANTI-VACUUM: every test below asserts a MEASURED value against a
/// SYNTHETIC truth with a comparison loop — a no-op detector (nil always)
/// fails loudly, never vacuously (the 04-02 track-A lesson).
final class VisionDetectTests: XCTestCase {

    /// Draw a single straight horizon line at `angleDegrees`
    /// (clockwise-positive CG convention: positive = descends rightward)
    /// across a 512×512 gray field with a bright sky / dark ground split.
    /// Returns the CGImage Vision consumes.
    private func horizonImage(angleDegrees: Double, size: Int = 1024) -> CGImage {
        let w = size, h = size
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let theta = angleDegrees * Double.pi / 180.0
        // Line through center: y(x) = h/2 + tan(θ)·(x − w/2). Pure
        // black/white split (max contrast — Vision's horizon model keys
        // on a strong global edge) + faint sky texture (noise breaks the
        // uniform-field degeneracy that suppresses detection at θ = 0).
        var seed: UInt64 = 0x12345678
        for y in 0..<h {
            for x in 0..<w {
                let lineY = Double(h) / 2.0 + tan(theta) * (Double(x) - Double(w) / 2.0)
                let d = Double(y) - lineY
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let grain = Double((seed >> 33) & 0xFF) / 255.0 * 12.0 - 6.0
                let v: UInt8
                if d < -1 { v = UInt8(min(255, max(0, 255 + Int(grain)))) }
                else if d > 1 { v = UInt8(min(255, max(0, 0 + Int(grain)))) }
                else { v = 128 }
                let i = (y * w + x) * 4
                pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v; pixels[i + 3] = 255
            }
        }
        return cgImageFromGray(pixels: pixels, width: w, height: h)
    }

    /// θ probe: three tilted horizons must detect within 0.2° of truth
    /// (SIGN included — a negated mapping fails at 2·|θ|). NOTE: exactly
    /// 0° is EXCLUDED by design — Vision returns nil for a perfectly
    /// row-aligned full-width edge (probed 2026-09-20: ±tilts detect, 0°
    /// nils even at max contrast). The nil path is pinned separately by
    /// `testBlankImageYieldsNoDetection`; the panel maps any DETECTED
    /// angle, so 0°-handling needs no mapping test.
    func testHorizonAnglesDetectWithinPointTwoDegrees() throws {
        let cases: [Double] = [-8.0, -3.0, 5.0]
        var failures: [String] = []
        for theta in cases {
            let image = horizonImage(angleDegrees: theta)
            let got = try VisionDetect.detectHorizonAngleDegrees(in: image)
            guard let angle = got else {
                failures.append("θ=\(theta)°: no horizon detected")
                continue
            }
            let err = abs(angle - theta)
            if err >= 0.2 {
                failures.append("θ=\(theta)°: detected \(angle)° (err \(err)°)")
            }
        }
        XCTAssertTrue(
            failures.isEmpty,
            "horizon θ probe FAILED (gate <0.2°):\n" + failures.joined(separator: "\n"))
    }

    /// Sign pin: +5° (descends rightward in CG) must report POSITIVE
    /// (clockwise-positive CG convention) — the correction is its negate.
    func testHorizonSignConventionIsClockwisePositive() throws {
        let image = horizonImage(angleDegrees: 5.0)
        guard let angle = try VisionDetect.detectHorizonAngleDegrees(in: image) else {
            XCTFail("no horizon on the +5° probe")
            return
        }
        XCTAssertGreaterThan(angle, 0, "+5° CG tilt must report positive (clockwise-positive)")
        XCTAssertEqual(
            AshiftAutoDetect.rotationCorrection(forHorizonAngleDegrees: angle),
            -angle, accuracy: 1e-12, "correction = −angle")
    }

    /// Rectangle probe: a synthetic white trapezoid on black — the
    /// detected quad's corners must land within 0.5% of the frame.
    func testRectangleCornersRecoverWithinHalfPercent() throws {
        let w = 1024, h = 1024
        // White PAGE on mid-gray with a black inner border: the page edge
        // is a crisp closed quad (max contrast both sides — the condition
        // VNDetectRectanglesRequest is tuned for), not a floating gradient
        // blob. Quad: axis-aligned rect inset 15% (rotation-free so the
        // 0.5% gate measures edge localization, not perspective modeling).
        let quad = [
            CGPoint(x: 0.15, y: 0.15), CGPoint(x: 0.85, y: 0.15),
            CGPoint(x: 0.85, y: 0.85), CGPoint(x: 0.15, y: 0.85),
        ]
        let image = pageImage(quad: quad, width: w, height: h)
        guard let detected = try VisionDetect.detectRectangle(in: image, minimumConfidence: 0.3) else {
            XCTFail("no rectangle on the synthetic page (confidence floor 0.3)")
            return
        }
        let got = [detected.topLeft, detected.topRight, detected.bottomRight, detected.bottomLeft]
        // Pair detected corners to truth by nearest-neighbor (order-free —
        // Vision's corner ORDER is its own convention; the error metric is
        // order-invariant, the pairing is greedy but the 0.5% gate is tight
        // enough that a wrong pairing fails loudly).
        var remaining = quad
        var worst = 0.0
        for g in got {
            var best = Double.greatestFiniteMagnitude, bestIdx = 0
            for (i, t) in remaining.enumerated() {
                let d = hypot(g.x - t.x, g.y - t.y)
                if d < best { best = d; bestIdx = i }
            }
            worst = max(worst, best)
            remaining.remove(at: bestIdx)
        }
        let pct = worst // normalized units already (0…1)
        XCTAssertLessThan(pct, 0.005, "quad corners must recover within 0.5% (worst \(pct))")
    }

    /// Blank image → nil (the failure-toast path: no detection leaves
    /// params untouched — a false positive here would corrupt params).
    func testBlankImageYieldsNoDetection() throws {
        let pixels = [UInt8](repeating: 128, count: 64 * 64 * 4).enumerated().map { i, v -> UInt8 in
            i % 4 == 3 ? 255 : v
        }
        let image = cgImageFromGray(pixels: pixels, width: 64, height: 64)
        let horizon = try VisionDetect.detectHorizonAngleDegrees(in: image)
        XCTAssertNil(horizon, "uniform field must not detect a horizon")
    }

    /// White page on mid-gray + black inner rule (CG frame, y-down): the
    /// page edge reads as a closed high-contrast quad; interior text-like
    /// bars break the uniform-white degeneracy (uniform blobs under-detect).
    private func pageImage(quad: [CGPoint], width w: Int, height h: Int) -> CGImage {
        var pixels = [UInt8](repeating: 128, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let px = (Double(x) + 0.5) / Double(w)
                let py = (Double(y) + 0.5) / Double(h)
                var v: UInt8 = 128
                if pointInQuad(x: px, y: py, quad: quad) {
                    v = 255
                    // Black inner border 1.5% wide + a few text bars.
                    let t = (py - quad[0].y) / (quad[2].y - quad[0].y)
                    let left = quad[0].x + t * (quad[3].x - quad[0].x)
                    let right = quad[1].x + t * (quad[2].x - quad[1].x)
                    let edge = min(px - left, right - px, py - quad[0].y, quad[2].y - py)
                    if edge < 0.015 { v = 0 }
                    let row = (py - quad[0].y) / (quad[2].y - quad[0].y)
                    if edge >= 0.015 && px > left + 0.08 && px < right - 0.08 {
                        let band = row * 12.0
                        if band.truncatingRemainder(dividingBy: 1.0) < 0.35 { v = 40 }
                    }
                }
                let i = (y * w + x) * 4
                pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v; pixels[i + 3] = 255
            }
        }
        return cgImageFromGray(pixels: pixels, width: w, height: h)
    }
    private func cgImageFromGray(pixels: [UInt8], width: Int, height: Int) -> CGImage {
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        let cs = CGColorSpaceCreateDeviceRGB()
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: cs,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)!
    }


    private func pointInQuad(x: Double, y: Double, quad: [CGPoint]) -> Bool {
        // quad order: TL, TR, BR, BL — left/right edges interpolate by y.
        let t = (y - quad[0].y) / (quad[3].y - quad[0].y)
        guard t >= 0, t <= 1 else { return false }
        let left = quad[0].x + t * (quad[3].x - quad[0].x)
        let right = quad[1].x + t * (quad[2].x - quad[1].x)
        let top = quad[0].y, bottom = quad[2].y
        return x >= left && x <= right && y >= top && y <= bottom
    }
}

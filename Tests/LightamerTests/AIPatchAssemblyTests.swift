@testable import LightamerCore
import XCTest

/// AIPatchAssemblyTests (Plan M6-4-02 T1, KD-1) — the patch planner/composer
/// pure-function pins: bbox + pad + image-bounds clamp, the three SKIP GATES
/// (empty / >60% frame / min-side floor), the composer's in/out byte
/// identity, the seam ramp band and linear profile, the patch-rect →
/// view-normalized → Vision Y-flip conversion round-trip, the ≤4 FIFO cap,
/// and run-to-run determinism. Zero Metal, zero Vision — CPU floats only.
final class AIPatchAssemblyTests: XCTestCase {

    // MARK: - fixtures

    /// A `w×h` plane with a filled block [x0,x1) × [y0,y1) at `v`.
    private func plane(
        _ w: Int, _ h: Int, block x0: Int, _ x1: Int, _ y0: Int, _ y1: Int,
        value v: Float = 1, background: Float = 0
    ) -> AIMaskPlane {
        precondition(x1 > x0 && y1 > y0)
        var floats = [Float](repeating: background, count: w * h)
        for y in y0..<y1 {
            for x in x0..<x1 { floats[y * w + x] = v }
        }
        return AIMaskPlane(width: w, height: h, floats: floats)
    }

    // MARK: ① bbox + pad + image-bounds clamp

    /// A 20×20 bbox in open field → pad = round(20·0.25) = 5 → a 30×30 rect
    /// around it. The EDGE-TOUCHING case clamps at the image bounds (the pad
    /// never grows past x/y 0 or the right/bottom edge).
    func testPlannerBBoxPadAndImageBoundsClamp() {
        // Open field: block [10,34)×[20,44) in 100×80 → bbox 24×24 → pad 6 →
        // rect (4,14,36,36) (clears the 32 px min-side floor).
        let open = plane(100, 80, block: 10, 34, 20, 44)
        XCTAssertEqual(
            AIPatchPlanner.planPatch(plane: open),
            AIPatchRect(x: 4, y: 14, width: 36, height: 36))

        // Corner-touching: block [0,28)×[0,28) — the left/top pad has no room
        // (clamps to 0) → rect (0,0,35,35), still clearing the 32 px floor.
        let corner = plane(100, 80, block: 0, 28, 0, 28)
        XCTAssertEqual(
            AIPatchPlanner.planPatch(plane: corner),
            AIPatchRect(x: 0, y: 0, width: 35, height: 35))

        // Bottom-right corner: block [70,100)×[50,80) — bbox 30×30 → pad 8,
        // the right/bottom clamp keeps 38×38.
        let br = plane(100, 80, block: 70, 100, 50, 80)
        XCTAssertEqual(
            AIPatchPlanner.planPatch(plane: br),
            AIPatchRect(x: 62, y: 42, width: 38, height: 38))
    }

    // MARK: ② oversized-bbox skip gate

    /// A mask whose bbox exceeds 60% of the frame area → nil (the full frame
    /// is already the accurate pass's product — a patch has no gain).
    func testPlannerSkipsOversizedBBox() {
        // 70% coverage: block [10,80)×[10,80) in 100×100 = 70×70 = 49%…
        // use [5,85)×[5,95) = 80×90 = 72% > 60%.
        let big = plane(100, 100, block: 5, 85, 5, 95)
        XCTAssertNil(AIPatchPlanner.planPatch(plane: big),
                     "a >60%-frame bbox must skip (no patch)")
        // Just under the gate: 59×59 = 34.8%… stay clearly inside: 55×55=30%.
        let fine = plane(100, 100, block: 10, 65, 10, 65)
        XCTAssertNotNil(AIPatchPlanner.planPatch(plane: fine),
                        "a patch-sized bbox must plan")
    }

    // MARK: ③ empty-mask skip gate

    func testPlannerSkipsEmptyMask() {
        let empty = AIMaskPlane(width: 64, height: 64, floats: [Float](repeating: 0, count: 64 * 64))
        XCTAssertNil(AIPatchPlanner.planPatch(plane: empty))
        // All-sub-threshold mass is still empty (the ≥0.5 coverage gate).
        let soft = AIMaskPlane(
            width: 64, height: 64,
            floats: [Float](repeating: 0.3, count: 64 * 64))
        XCTAssertNil(AIPatchPlanner.planPatch(plane: soft),
                     "all-sub-threshold pixels = empty coverage")
    }

    // MARK: ④ min-side floor skip gate

    func testPlannerSkipsBelowMinSideFloor() {
        // A 10×10 bbox → pad 3 → a 16×16 patch < 32 px → nil (noise domain).
        let tiny = plane(400, 400, block: 100, 110, 100, 110)
        XCTAssertNil(AIPatchPlanner.planPatch(plane: tiny))
        // Exactly at the floor: a 26×26 bbox → pad 7 → 40×40 ≥ 32 → plans.
        let at = plane(400, 400, block: 100, 126, 100, 126)
        XCTAssertNotNil(AIPatchPlanner.planPatch(plane: at))
    }

    // MARK: ⑤ composer in/out byte identity + the KD-4 row-2 numeric gates

    /// (A) Inside the rect (deeper than the seam band) the value is the
    /// PATCH's exactly; outside every rect the base floats pass through
    /// byte-identical. The patch plane arrives at a DIFFERENT resolution
    /// (the layer-B ROI runtime fact) — the composer's bilinear absorbs it.
    /// (B)+(C) the KD-4 row-2 dual-resolution fixture: the SAME analytic
    /// circle rendered as the full-frame leg (soft) and the hi-res patch
    /// leg (twice-finer softness) — the composed transition's 10-90 rise
    /// is ≤ 0.6× the full-frame leg's (the patch carries real detail), and
    /// the 0.5-contour lands within 1 px of ground truth (the seam/
    /// resample misalignment gate).
    func testComposerInsidePatchOutsideBaseByteIdentity() {
        let w = 60, h = 40
        var baseFloats = [Float](repeating: 0, count: w * h)
        for i in stride(from: 0, to: baseFloats.count, by: 7) {
            baseFloats[i] = Float(i % 13) / 12.0 // non-trivial base values
        }
        let base = AIMaskPlane(width: w, height: h, floats: baseFloats)

        // Patch: 16×16 all-ones for a 32×32 rect (upsample leg)…
        let rect = AIPatchRect(x: 10, y: 4, width: 32, height: 32)
        let ones = AIMaskPlane(
            width: 16, height: 16, floats: [Float](repeating: 1, count: 256))
        let out = AIPatchComposer.compose(base: base, patches: [
            AIPatch(rect: rect, plane: ones)
        ])

        let band = AIPatchComposer.seamBand(for: rect)
        var comparedInside = 0, comparedOutside = 0
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let insideX = x >= rect.x + band && x < rect.maxX - band
                let insideY = y >= rect.y + band && y < rect.maxY - band
                if insideX && insideY {
                    XCTAssertEqual(out.floats[i], 1.0, accuracy: 1e-6,
                                   "deep inside the rect = the patch value (at \(x),\(y))")
                    comparedInside += 1
                } else if x < rect.x || x >= rect.maxX || y < rect.y || y >= rect.maxY {
                    XCTAssertEqual(out.floats[i], base.floats[i],
                                   "outside the rect = base byte-identical (at \(x),\(y))")
                    comparedOutside += 1
                }
            }
        }
        XCTAssertGreaterThan(comparedInside, 0, "防空转: no inside pixels compared")
        XCTAssertGreaterThan(comparedOutside, 0, "防空转: no outside pixels compared")

        // (B)+(C) the dual-resolution synthetic scene (KD-4 row 2).
        let fw = 64, fh = 64
        let center = SIMD2<Double>(32, 32), radius = 12.0
        func circle(_ x: Double, _ y: Double, softness s: Double) -> Float {
            let r = ((x - center.x) * (x - center.x)
                   + (y - center.y) * (y - center.y)).squareRoot()
            return Float(1.0 / (1.0 + exp(-(r - radius) / s)))
        }
        // The full-frame leg: softness 2 px in output space.
        var fullFloats = [Float](repeating: 0, count: fw * fh)
        for y in 0..<fh {
            for x in 0..<fw {
                fullFloats[y * fw + x] = circle(Double(x) + 0.5, Double(y) + 0.5, softness: 2.0)
            }
        }
        let fullFrame = AIMaskPlane(width: fw, height: fh, floats: fullFloats)
        // The hi-res patch leg: the SAME circle over the patch rect,
        // rendered at 2× the rect's resolution, softness 2 px in PATCH
        // space = 1 px in output space (twice finer physically). The pixel
        // grid follows the composer's half-texel convention (dst j ← src
        // (j + 0.5)·scale − 0.5 in rect-local coordinates).
        let scale = 2
        let pRect = AIPatchRect(x: 16, y: 16, width: 32, height: 32)
        let pw = pRect.width * scale, ph = pRect.height * scale
        var patchFloats = [Float](repeating: 0, count: pw * ph)
        for j in 0..<ph {
            for i in 0..<pw {
                let ox = Double(pRect.x) + (Double(i) + 0.5) / Double(scale) - 0.5
                let oy = Double(pRect.y) + (Double(j) + 0.5) / Double(scale) - 0.5
                patchFloats[j * pw + i] = circle(ox, oy, softness: 2.0 / Double(scale))
            }
        }
        let patch = AIPatch(rect: pRect, plane: AIMaskPlane(width: pw, height: ph, floats: patchFloats))
        let composed = AIPatchComposer.compose(base: fullFrame, patches: [patch])

        // Measure the 10-90 rise along the center row's LEFT edge (well
        // clear of the seam band: the edge at x ≈ 20 is 4 px inside the
        // rect whose band is 2 px).
        func rise(_ plane: AIMaskPlane) -> (width: Double, x05: Double) {
            let y = 32
            var x10 = -1.0, x90 = -1.0, x05 = -1.0
            for x in 1..<fw {
                let v = Double(plane.floats[y * fw + x])
                let pv = Double(plane.floats[y * fw + x - 1])
                if x90 < 0 && pv >= 0.9 && v < 0.9 { x90 = Double(x) }
                if x05 < 0 && pv >= 0.5 && v < 0.5 { x05 = Double(x) - 0.5 }
                if x10 < 0 && pv >= 0.1 && v < 0.1 { x10 = Double(x) - 0.5 }
            }
            return (x10 - x90, x05)
        }
        let fullRise = rise(fullFrame)
        let composedRise = rise(composed)
        XCTAssertGreaterThan(fullRise.width, 0, "防空转: the full-frame rise measured")
        XCTAssertLessThanOrEqual(
            composedRise.width, 0.6 * fullRise.width,
            "KD-4 row 2: the patch leg's transition ≤ 0.6× the full-frame leg's " +
                "(got \(composedRise.width) vs \(fullRise.width))")
        // The 0.5 contour = ground truth edge (center.x − radius = 20).
        XCTAssertEqual(composedRise.x05, center.x - radius, accuracy: 1.0,
                       "KD-4 row 2: the seam/resample misalignment ≤ 1 px " +
                           "(got \(composedRise.x05))")
    }

    // MARK: ⑥ seam ramp band + linear profile

    /// Over a zero base and an all-ones patch, the seam profile along a row
    /// is EXACTLY the ramp w = min((d+1)/band, 1) (d = distance from the rect
    /// edge) — the band spans `band` pixels and is linear; the transition
    /// width equals the band.
    func testComposerSeamRampBandAndLinearProfile() {
        let base = AIMaskPlane(width: 64, height: 64, floats: [Float](repeating: 0, count: 64 * 64))
        let rect = AIPatchRect(x: 8, y: 8, width: 48, height: 48)
        let ones = AIMaskPlane(width: 48, height: 48, floats: [Float](repeating: 1, count: 48 * 48))
        let out = AIPatchComposer.compose(base: base, patches: [AIPatch(rect: rect, plane: ones)])

        let band = AIPatchComposer.seamBand(for: rect)
        XCTAssertEqual(band, 2, "5% of 48 = 2.4 → Int floor 2, inside the 2...16 clamp")
        let y = rect.y + rect.height / 2 // a mid row: wy saturates
        // Left seam: x = rect.x + k → value = min((k+1)/band, 1), exact floats.
        for k in 0..<(band + 2) {
            let expected = min(1.0, Float(k + 1) / Float(band))
            XCTAssertEqual(
                out.floats[y * 64 + rect.x + k], expected, accuracy: 1e-6,
                "ramp profile at k=\(k)")
        }
        // The transition WIDTH (0→1 rise) is exactly the band.
        let firstFull = (0..<rect.width).first {
            out.floats[y * 64 + rect.x + $0] >= 1.0
        }
        XCTAssertEqual(firstFull, band - 1,
                       "the ramp saturates at k = band−1 (width = band)")
        // Symmetry: the right seam mirrors the left.
        XCTAssertEqual(
            out.floats[y * 64 + rect.maxX - 1],
            Float(1) / Float(band), accuracy: 1e-6,
            "the outermost right column sits at 1/band")
    }

    // MARK: ⑦ patch rect → view-normalized → Vision Y-flip round-trip

    /// The rect's normalized form rides the AIMaskRect seam: visionRect is
    /// the y-flipped box (vision y = 1 − y − height); the pixel round-trip
    /// (`AIPatchRect.from(normalized:)`) restores the original rect.
    func testPatchRectNormalizedYFlipRoundTrip() {
        let rect = AIPatchRect(x: 40, y: 20, width: 100, height: 50)
        let norm = rect.normalized(imageWidth: 200, imageHeight: 100)
        XCTAssertEqual(norm.x, 0.2, accuracy: 1e-6)
        XCTAssertEqual(norm.y, 0.2, accuracy: 1e-6)
        XCTAssertEqual(norm.width, 0.5, accuracy: 1e-6)
        XCTAssertEqual(norm.height, 0.5, accuracy: 1e-6)

        // The single Y-flip seam (the top-left view corner becomes the
        // Vision-space MAX-y corner): vision y = 1 − 0.2 − 0.5 = 0.3.
        let vision = norm.visionRect
        XCTAssertEqual(Double(vision.origin.x), 0.2, accuracy: 1e-6)
        XCTAssertEqual(Double(vision.origin.y), 0.3, accuracy: 1e-6)
        XCTAssertEqual(Double(vision.width), 0.5, accuracy: 1e-6)
        XCTAssertEqual(Double(vision.height), 0.5, accuracy: 1e-6)

        // The pixel round-trip restores the original rect.
        XCTAssertEqual(
            AIPatchRect.from(normalized: norm, imageWidth: 200, imageHeight: 100),
            rect)
    }

    // MARK: ⑧ cap ≤4 + FIFO replacement determinism

    /// Six patches → `capped` keeps the LAST four in order (the earliest two
    /// are the replaced ones); below the cap the list is identity.
    func testComposerCapFourFIFOReplacesEarliest() {
        func patch(_ n: Int) -> AIPatch {
            AIPatch(
                rect: AIPatchRect(x: n * 2, y: n * 2, width: 40, height: 40),
                plane: AIMaskPlane(width: 8, height: 8, floats: [Float](repeating: Float(n), count: 64)))
        }
        let six = [patch(0), patch(1), patch(2), patch(3), patch(4), patch(5)]
        let capped = AIPatchComposer.capped(six)
        XCTAssertEqual(capped.count, 4, "the cap is 4")
        XCTAssertEqual(capped, [patch(2), patch(3), patch(4), patch(5)],
                       "FIFO: the earliest two replaced, order preserved")
        XCTAssertEqual(AIPatchComposer.capped(Array(six[0..<4])), Array(six[0..<4]),
                       "below the cap: identity")
    }

    // MARK: ⑨ determinism

    /// The same base + patches compose to the identical float plane twice
    /// (bit-identical — the composer is a pure function, no hidden state).
    func testComposerDeterministicAcrossRuns() {
        let w = 50, h = 30
        var baseFloats = [Float](repeating: 0, count: w * h)
        for i in 0..<baseFloats.count { baseFloats[i] = Float(i % 11) / 10.0 }
        let base = AIMaskPlane(width: w, height: h, floats: baseFloats)
        let patches = [
            AIPatch(
                rect: AIPatchRect(x: 5, y: 2, width: 36, height: 24),
                plane: AIMaskPlane(width: 18, height: 12, floats: (0..<216).map { Float($0 % 9) / 8.0 })),
            AIPatch(
                rect: AIPatchRect(x: 30, y: 4, width: 18, height: 20),
                plane: AIMaskPlane(width: 9, height: 10, floats: (0..<90).map { Float($0 % 5) / 4.0 })),
        ]
        let a = AIPatchComposer.compose(base: base, patches: patches)
        let b = AIPatchComposer.compose(base: base, patches: patches)
        XCTAssertEqual(a, b, "two runs must be bit-identical")
        XCTAssertEqual(a.byteIdentity, b.byteIdentity)
    }
}

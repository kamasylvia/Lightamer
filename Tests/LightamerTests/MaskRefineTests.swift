@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// MaskRefineTests (Plan LUMEN-C T1) — the five-step sample-based matting
// refinement pins:
//   ① golden vs the cv2/NumPy reference (the committed fixture pair —
//     generator = .work/gsd/phases/lumen-culling/evidence/lumenc/
//     maskrefine_reference.py, a verbatim transcription of Lumen v2.0.1
//     selection.py fine(); the tolerance band absorbs the registered
//     kernel-shape deltas: chamfer erosion vs cv2's ellipse raster,
//     rect running-max vs the ellipse dilate, analytic-Gaussian radii);
//   ② the twigs scene reference (Lumen test_v170_masks.py
//     test_fine_pass_recovers_twigs_the_quick_mask_misses semantics —
//     edge error halves and thin-branch cores flip below .5);
//   ③ broad ramps keep the quick mask + known regions stay exact (the
//     test_fine_pass_keeps_broad_ramps_and_known_regions semantics);
//   ④ the confidence gate, table-driven (haze ramp → the quick mask
//     survives; a sharp colour edge → the band moves);
//   ⑤ grow/shrink clamp boundaries;
//   ⑥ malformed inputs pass through bit-exact (all-inside / all-outside /
//     no certain regions — Lumen's early return);
//   ⑦ the fineSize clamp math (Lumen's 9504×6336 → 4096×2731) + the
//     in-fine oversize-guide clamp;
//   ⑧ the refine-duration probe (LIGHTAMER_PERF_PROBE=1 — CPU timing,
//     skip by default; the red-line-14 family).
// ─────────────────────────────────────────────────────────────────────────────

final class MaskRefineTests: XCTestCase {

    // MARK: shared deterministic LCG (the fixture generator's twin)

    private final class LCG {
        var x: UInt32
        init(seed: UInt32) { x = seed & 0x7FFF_FFFF }
        func next() -> Float {
            x = (1_103_515_245 &* x &+ 12345) & 0x7FFF_FFFF
            return Float(x) / Float(0x8000_0000)
        }
    }

    // MARK: fixture reader

    private struct GoldenFixture {
        let guide: MaskRefineGuide
        let alpha: AIMaskPlane
        let networkPx: Int
        let grow: Double
        let shrink: Double
        let expected: AIMaskPlane

        init(data: Data) throws {
            let bytes = [UInt8](data)
            guard bytes.count > 20, String(bytes: bytes[0..<4], encoding: .ascii) == "MRG1"
            else { throw NSError(domain: "MaskRefineGolden", code: 1) }
            func i32(_ offset: Int) -> Int {
                Int(UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                    | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24)
            }
            func f32(_ offset: Int) -> Float {
                Float(bitPattern: UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                    | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24)
            }
            let gw = i32(4), gh = i32(8), aw = i32(12), ah = i32(16)
            networkPx = i32(20)
            grow = Double(f32(24))
            shrink = Double(f32(28))
            var offset = 32
            func takeFloats(_ count: Int) -> [Float] {
                defer { offset += count * 4 }
                return (0..<count).map { f32(offset + $0 * 4) }
            }
            guide = MaskRefineGuide(
                width: gw, height: gh, rgba: takeFloats(gw * gh * 4))
            alpha = AIMaskPlane(width: aw, height: ah, floats: takeFloats(aw * ah))
            expected = AIMaskPlane(width: gw, height: gh, floats: takeFloats(gw * gh))
        }
    }

    private func loadGoldenFixture() throws -> GoldenFixture {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(
            forResource: "maskrefine_golden", withExtension: "bin")
        else { throw NSError(domain: "MaskRefineGolden", code: 2) }
        return try GoldenFixture(data: try Data(contentsOf: url))
    }

    // MARK: ① golden vs the cv2/NumPy reference

    func testGoldenAgainstNumPyReference() throws {
        let fixture = try loadGoldenFixture()
        let refined = MaskRefine.fine(
            alpha: fixture.alpha, guide: fixture.guide,
            networkPx: fixture.networkPx, grow: fixture.grow, shrink: fixture.shrink)
        XCTAssertEqual(refined.width, fixture.expected.width)
        XCTAssertEqual(refined.height, fixture.expected.height)
        var sum: Float = 0
        var maxDiff: Float = 0
        for i in 0..<refined.floats.count {
            let d = abs(refined.floats[i] - fixture.expected.floats[i])
            sum += d
            maxDiff = max(maxDiff, d)
        }
        let mean = sum / Float(refined.floats.count)
        // The registered band: the cv2-vs-Accelerate kernel-shape deltas
        // (erode/dilate boundary class, Gaussian radii) land within this.
        XCTAssertLessThan(mean, 0.02, "golden mean |Δ| vs NumPy reference")
        XCTAssertLessThan(maxDiff, 0.15, "golden max |Δ| vs NumPy reference")
        // Deep-known pixels stay exact in BOTH implementations (the
        // smoothstep weight saturates to the certain face there).
        let known = try knownRegionTruth(fixture)
        // The deep-known faces land within half a percent of exact (the
        // smoothstep saturates away from the band; the exact-1.0 face is
        // pinned geometrically in the broad-ramps test).
        for i in known.inside {
            XCTAssertGreaterThanOrEqual(refined.floats[i], 0.995)
        }
        for i in known.outside {
            XCTAssertLessThanOrEqual(refined.floats[i], 0.005)
        }
    }

    /// Pixels CERTAIN-deep inside/outside: the (band+1)-Chebyshev
    /// neighborhood maps to quick ≥ .99 (≤ .01) — the conservative
    /// stand-in for the eroded known region, whose refined face must be
    /// exactly 1 (0) in BOTH implementations (the smoothstep saturates).
    private func knownRegionTruth(_ fixture: GoldenFixture) throws
        -> (inside: [Int], outside: [Int]) {
        let w = fixture.guide.width, h = fixture.guide.height
        let band = max(3, Int((Float(max(h, w)) / Float(fixture.networkPx) * 0.75).rounded()))
        let reach = band + 1
        func allNeighborQuick(_ x: Int, _ y: Int, _ test: (Float) -> Bool) -> Bool {
            for dy in -reach...reach {
                for dx in -reach...reach {
                    let gx = min(max(x + dx, 0), w - 1)
                    let gy = min(max(y + dy, 0), h - 1)
                    let ax = min(gx * fixture.alpha.width / w, fixture.alpha.width - 1)
                    let ay = min(gy * fixture.alpha.height / h, fixture.alpha.height - 1)
                    if !test(fixture.alpha.floats[ay * fixture.alpha.width + ax]) {
                        return false
                    }
                }
            }
            return true
        }
        var inside: [Int] = []
        var outside: [Int] = []
        for y in stride(from: 2 * reach, to: h - 2 * reach, by: 3) {
            for x in stride(from: 2 * reach, to: w - 2 * reach, by: 3) {
                let i = y * w + x
                if allNeighborQuick(x, y, { $0 >= 0.99 }) { inside.append(i) }
                else if allNeighborQuick(x, y, { $0 <= 0.01 }) { outside.append(i) }
            }
        }
        XCTAssertFalse(inside.isEmpty, "fixture must carry deep-known inside pixels")
        XCTAssertFalse(outside.isEmpty, "fixture must carry deep-known outside pixels")
        return (inside, outside)
    }

    // MARK: ② twigs scene reference

    /// Synthetic thin dark branches over a sky; the refined edge error
    /// halves vs the plain upsample and thin-branch cores flip below .5
    /// (Lumen's twigs test semantics, synthesized — review m-3's
    /// upstream-vector-missing posture: self-woven vector, behavior pins).
    func testTwigsRecoveredFromQuickMask() {
        let (scene, truth) = Self.branchesScene(width: 300, height: 200, seed: 7)
        // Lumen's quick() stand-in: the area-downscaled truth — NO added
        // noise (the uncertainty band comes from the downscale mixing).
        let quick = Self.downsampleGray(truth, sw: 300, sh: 200, dw: 60, dh: 40)
        let alpha = AIMaskPlane(width: 60, height: 40, floats: quick)
        let refined = MaskRefine.fine(
            alpha: alpha, guide: scene, networkPx: 320, grow: 0.3, shrink: 0.02)
        let up = MaskRefine.resizeBilinear(
            quick, sw: 60, sh: 40, dw: 300, dh: 200)
        // Edge band: within 5 px of the truth boundary.
        var edge: [Int] = []
        for y in 0..<200 {
            for x in 0..<300 {
                let t = truth[y * 300 + x]
                if t > 0.02, t < 0.98 { edge.append(y * 300 + x) }
            }
        }
        XCTAssertFalse(edge.isEmpty)
        let before = edge.map { abs(up[$0] - truth[$0]) }.reduce(0, +) / Float(edge.count)
        let after = edge.map { abs(refined.floats[$0] - truth[$0]) }.reduce(0, +) / Float(edge.count)
        XCTAssertLessThan(after, before * 0.5, "the edge error halves (\(before) → \(after))")
        // Thin-branch cores: mostly-covered pixels become not-sky.
        var twigTotal = 0
        var twigBelowUp = 0
        var twigBelowRefined = 0
        for y in 0..<(200 / 2) {
            for x in 0..<300 {
                let i = y * 300 + x
                if truth[i] < 0.5, up[i] > 0.45 {
                    twigTotal += 1
                    if up[i] < 0.5 { twigBelowUp += 1 }
                    if refined.floats[i] < 0.5 { twigBelowRefined += 1 }
                }
            }
        }
        XCTAssertGreaterThan(twigTotal, 20, "the scene must carry thin cores")
        XCTAssertGreaterThan(
            Float(twigBelowRefined) / Float(twigTotal),
            Float(twigBelowUp) / Float(twigTotal),
            "refinement moves the cores toward not-sky")
    }

    // MARK: ③ broad ramps + known regions

    func testBroadRampsKeepTheQuickMaskAndKnownRegions() {
        // The haze ramp + a pure value ramp as the coarse mask (Lumen's
        // second fine-pass scene): the colours cannot explain a broad ramp
        // → the output tracks the plain upsample.
        let w = 300, h = 200
        var haze = [Float](repeating: 0, count: w * h * 4)
        var ramp = [Float](repeating: 0, count: 400 * 600)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let v = Float(y) / Float(h)
                haze[i] = 0.9 - 0.5 * v
                haze[i + 1] = 0.7 - 0.4 * v
                haze[i + 2] = 0.5 - 0.3 * v
                haze[i + 3] = 1
            }
        }
        for y in 0..<400 {
            let v = min(max(1.6 - 2 * Float(y) / 400, 0), 1)
            for x in 0..<600 { ramp[y * 600 + x] = v }
        }
        let coarse = MaskRefine.resizeBilinear(ramp, sw: 400, sh: 600, dw: w, dh: h)
        let refined = MaskRefine.fine(
            alpha: AIMaskPlane(width: 400, height: 600, floats: ramp),
            guide: MaskRefineGuide(width: w, height: h, rgba: haze),
            networkPx: 320, grow: 0.05, shrink: 0.05)
        var sum: Float = 0
        for i in 0..<(w * h) { sum += abs(refined.floats[i] - coarse[i]) }
        XCTAssertLessThan(
            sum / Float(w * h), 0.03,
            "a broad ramp over smooth tones keeps the quick mask")
        // Known regions: a confident block stays exact. The exterior is
        // 0 (≤ .01 — certain-outside), the block 1 (≥ .99 — certain-inside).
        var solidAlpha = [Float](repeating: 0, count: 80 * 60)
        for y in 10..<50 {
            for x in 10..<70 { solidAlpha[y * 80 + x] = 1 }
        }
        var flatScene = [Float](repeating: 0, count: 240 * 180 * 4)
        for i in stride(from: 0, to: flatScene.count, by: 4) {
            flatScene[i] = 0.6; flatScene[i + 1] = 0.55; flatScene[i + 2] = 0.5
            flatScene[i + 3] = 1
        }
        let solid = MaskRefine.fine(
            alpha: AIMaskPlane(width: 80, height: 60, floats: solidAlpha),
            guide: MaskRefineGuide(width: 240, height: 180, rgba: flatScene),
            networkPx: 320, grow: 0.05, shrink: 0.05)
        // Far inside (the block's center after the 3× upsample) → exactly
        // 1; far outside → exactly 0 (the smoothstep saturates; Lumen's
        // `np.all(refined[far] == 1)` semantics).
        let deepInside = solid.floats[90 * 240 + 120]
        let deepOutside = solid.floats[5 * 240 + 5]
        XCTAssertEqual(deepInside, 1, accuracy: 1e-6)
        XCTAssertEqual(deepOutside, 0, accuracy: 1e-6)
    }

    // MARK: ④ confidence gate, table-driven

    func testConfidenceGateTableDriven() {
        // Sharp colour edge (high confidence → the band moves off the
        // quick edge). The quick mask is a SMOOTH ramp (the network's soft
        // edge) centered at column 126, biased +6 off the true colour edge
        // at 120 — the uncertain band then carries movable alpha values (a
        // hard binary edge would be clamped immobile by grow/shrink by
        // design — the same immobility the broad-ramp test pins).
        let w = 240, h = 160
        var sharp = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if x < 120 {
                    sharp[i] = 0.15; sharp[i + 1] = 0.1; sharp[i + 2] = 0.08
                } else {
                    sharp[i] = 0.85; sharp[i + 1] = 0.8; sharp[i + 2] = 0.7
                }
                sharp[i + 3] = 1
            }
        }
        func smoothstep(_ t: Float) -> Float {
            let c = min(max(t, 0), 1)
            return c * c * (3 - 2 * c)
        }
        var quick = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                quick[y * w + x] = smoothstep((Float(x) - 118) / 16)
            }
        }
        func midCrossing(_ plane: AIMaskPlane) -> Float {
            var acc: Float = 0
            var samples: Float = 0
            for y in 40..<120 {
                var x = 100
                while x < 160, plane.floats[y * w + x] < 0.5 { x += 1 }
                acc += Float(x)
                samples += 1
            }
            return acc / samples
        }
        let refined = MaskRefine.fine(
            alpha: AIMaskPlane(width: w, height: h, floats: quick),
            guide: MaskRefineGuide(width: w, height: h, rgba: sharp),
            networkPx: 320, grow: 0.05, shrink: 0.05)
        // The refined boundary sits near the TRUE colour edge column (120),
        // pulled off the quick ramp's biased 126.
        let meanBoundary = midCrossing(refined)
        XCTAssertLessThan(abs(meanBoundary - 120), 3, "the colour edge wins (\(meanBoundary))")
        // The boundary moved off the quick ramp's bias (the refined
        // crossing lands ≈120, not the biased 126).
        XCTAssertLessThan(meanBoundary, 124, "the boundary moved off the quick bias (\(meanBoundary))")
    }

    // MARK: ⑤ grow/shrink clamp boundaries

    func testGrowShrinkClampBoundaries() {
        let (_, truth) = Self.branchesScene(width: 240, height: 160, seed: 3)
        // The quick mask is the truth's area-downscale (a real 0/1 mask —
        // the guide's own colours are NOT 0/1 and never pass the .99/.01
        // certain-region thresholds).
        let quick = Self.downsampleGray(truth, sw: 240, sh: 160, dw: 60, dh: 40)
        let sceneGuide = Self.branchesScene(width: 240, height: 160, seed: 3).guide
        let alpha = AIMaskPlane(width: 60, height: 40, floats: quick)
        let up = MaskRefine.resizeBilinear(quick, sw: 60, sh: 40, dw: 240, dh: 160)
        let restricted = MaskRefine.fine(
            alpha: alpha, guide: sceneGuide, networkPx: 320, grow: 0.9, shrink: 0.9)
        let free = MaskRefine.fine(
            alpha: alpha, guide: sceneGuide, networkPx: 320, grow: 0.01, shrink: 0.01)
        // The clamp is per-pixel SCALING (the transliteration): a rise from
        // coarse c is bounded by (1−c)·min(1, c/grow), a fall by
        // c·min(1, (1−c)/shrink) — at coarse .5/grow .9 that is ≈.278, NOT
        // an absolute .05 pin. Assert the exact per-pixel bounds.
        var maxRiseRestricted: Float = 0
        var maxRiseFree: Float = 0
        var maxFallRestricted: Float = 0
        var maxFallFree: Float = 0
        var clampViolated = false
        for i in 0..<(240 * 160) {
            let c = up[i]
            maxRiseRestricted = max(maxRiseRestricted, restricted.floats[i] - up[i])
            maxRiseFree = max(maxRiseFree, free.floats[i] - up[i])
            maxFallRestricted = max(maxFallRestricted, up[i] - restricted.floats[i])
            maxFallFree = max(maxFallFree, up[i] - free.floats[i])
            let riseBound = (1 - c) * min(1, c / 0.9)
            let fallBound = c * min(1, (1 - c) / 0.9)
            if restricted.floats[i] > up[i] + riseBound + 1e-4
                || restricted.floats[i] < up[i] - fallBound - 1e-4 {
                clampViolated = true
            }
        }
        XCTAssertFalse(clampViolated, "grow=.9/shrink=.9 holds the per-pixel bounds")
        XCTAssertGreaterThan(
            maxRiseFree + maxFallFree, maxRiseRestricted + maxFallRestricted,
            "the loose clamp allows strictly more movement")
        // grow=0/shrink=0 fall through the 1e-3 guard (the transliteration)
        // — no crash, bounded output.
        let extreme = MaskRefine.fine(
            alpha: alpha, guide: sceneGuide, networkPx: 320, grow: 0, shrink: 0)
        for v in extreme.floats {
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
        }
    }

    // MARK: ⑥ malformed inputs pass through

    func testMalformedInputsPassThroughBitExact() throws {
        let guide = MaskRefineGuide(width: 40, height: 30, rgba: Self.flatRGBA(
            40, 30, r: 0.5, g: 0.45, b: 0.4))
        let w = 40, h = 30
        // All-inside (no outside) → Lumen's early return: the coarse face.
        let allInside = AIMaskPlane(width: w, height: h, floats: [Float](repeating: 1, count: w * h))
        let r1 = MaskRefine.fine(
            alpha: allInside, guide: guide, networkPx: 320, grow: 0.05, shrink: 0.05)
        XCTAssertEqual(r1.floats, allInside.floats)
        // All-outside.
        let allOutside = AIMaskPlane(width: w, height: h, floats: [Float](repeating: 0, count: w * h))
        let r2 = MaskRefine.fine(
            alpha: allOutside, guide: guide, networkPx: 320, grow: 0.05, shrink: 0.05)
        XCTAssertEqual(r2.floats, allOutside.floats)
        // No certain region at all (uniform .5).
        let uncertain = AIMaskPlane(width: w, height: h, floats: [Float](repeating: 0.5, count: w * h))
        let r3 = MaskRefine.fine(
            alpha: uncertain, guide: guide, networkPx: 320, grow: 0.05, shrink: 0.05)
        XCTAssertEqual(r3.floats, uncertain.floats)
        // Sub-network alpha (5×4) against the guide upsamples cleanly.
        let tiny = AIMaskPlane(width: 5, height: 4, floats: (0..<20).map {
            $0 % 5 == 2 ? 1 : ($0 % 5 == 3 ? 0 : 0.5)
        })
        let r4 = MaskRefine.fine(
            alpha: tiny, guide: guide, networkPx: 320, grow: 0.05, shrink: 0.05)
        XCTAssertEqual(r4.width, w)
        XCTAssertEqual(r4.height, h)
        for v in r4.floats {
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
        }
    }

    // MARK: ⑦ fineSize clamp math

    func testFineSizeClampMath() {
        // Lumen's own numbers (test_kinds_and_guide_size).
        XCTAssertEqual(MaskRefine.fineSize(width: 9504, height: 6336).width, 4096)
        XCTAssertEqual(MaskRefine.fineSize(width: 9504, height: 6336).height, 2731)
        XCTAssertEqual(MaskRefine.fineSize(width: 3000, height: 2000).width, 3000)
        XCTAssertEqual(MaskRefine.fineSize(width: 3000, height: 2000).height, 2000)
        // In-fine clamp: an oversize guide comes back at the clamped size.
        let guide = MaskRefineGuide(
            width: 5000, height: 2,
            rgba: [Float](repeating: 0.5, count: 5000 * 2 * 4))
        let alpha = AIMaskPlane(
            width: 100, height: 1,
            floats: (0..<100).map { $0 < 40 ? 0 : ($0 < 60 ? 0.5 : 1) })
        let out = MaskRefine.fine(
            alpha: alpha, guide: guide, networkPx: 320, grow: 0.05, shrink: 0.05)
        XCTAssertEqual(out.width, 4096)
        XCTAssertEqual(out.height, 2)
    }

    // MARK: ⑧ duration probe (CPU timing — the red-line-14 family)

    func testRefineDurationProbe() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["LIGHTAMER_PERF_PROBE"] == "1" else {
            throw XCTSkip("perf probe gated by LIGHTAMER_PERF_PROBE=1 (M2-5 惯例)")
        }
        let (scene, _) = Self.branchesScene(width: 1024, height: 768, seed: 5)
        let quick = Self.downsample(scene.rgba, sw: 1024, sh: 768, dw: 256, dh: 192)
        let alpha = AIMaskPlane(width: 256, height: 192, floats: quick)
        let clock = ContinuousClock()
        let started = clock.now
        let refined = MaskRefine.fine(
            alpha: alpha, guide: scene, networkPx: 320, grow: 0.05, shrink: 0.05)
        let elapsed = clock.now - started
        let ms = Float(elapsed.components.attoseconds) / 1e15
        print("MASKREFINE PROBE: 1024×768 fine() = \(Int(ms)) ms")
        XCTAssertEqual(refined.width, 1024)
        XCTAssertLessThan(ms, 30_000, "sanity bound (Lumen 33MP ≈ 7s reference)")
    }

    // MARK: synthetic scene helpers

    /// Dark thin branches over a hazy sky gradient; returns the RGBA guide
    /// and the soft truth mask.
    private static func branchesScene(
        width: Int, height: Int, seed: UInt32
    ) -> (guide: MaskRefineGuide, truth: [Float]) {
        var rng = LCG(seed: seed)
        var rgba = [Float](repeating: 0, count: width * height * 4)
        var truth = [Float](repeating: 1, count: width * height)
        for y in 0..<height {
            let v = Float(y) / Float(height)
            for x in 0..<width {
                let i = (y * width + x) * 4
                rgba[i] = 0.72 - 0.3 * v
                rgba[i + 1] = 0.62 - 0.22 * v
                rgba[i + 2] = 0.84 - 0.14 * v
                rgba[i + 3] = 1
            }
        }
        for k in 0..<4 {
            let y0 = Float(height) * (0.15 + 0.2 * Float(k))
            let amp = Float(5 + 2 * k)
            let phase = rng.next() * 6.2831853
            let thick = Float(1.0 + Float(k) * 0.5)
            let tone = Float(0.05 + 0.06 * Float(k))
            for x in 0..<width {
                let cy = y0 + amp * sin(Float(x) / 16 + phase)
                let lo = max(0, Int(cy - thick - 1.5))
                let hi = min(height - 1, Int(cy + thick + 1.5))
                for y in lo...hi {
                    let d = abs(Float(y) - cy)
                    let cov = max(0, min(1, thick - d + 0.5))
                    if cov <= 0 { continue }
                    let i = (y * width + x) * 4
                    rgba[i] = rgba[i] * (1 - cov) + tone * cov
                    rgba[i + 1] = rgba[i + 1] * (1 - cov) + tone * 0.8 * cov
                    rgba[i + 2] = rgba[i + 2] * (1 - cov) + tone * 0.7 * cov
                    truth[y * width + x] *= (1 - cov)
                }
            }
        }
        // The solid dark foreground band (Lumen's bottom-half tree) — the
        // deep-outside region the fine pass meets.
        let bandY = height * 62 / 100
        if bandY < height {
            for y in bandY..<height {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    rgba[i] = rgba[i] * 0.15 + 0.08 * 0.85
                    rgba[i + 1] = rgba[i + 1] * 0.15 + 0.10 * 0.85
                    rgba[i + 2] = rgba[i + 2] * 0.15 + 0.05 * 0.85
                    truth[y * width + x] = 0
                }
            }
        }
        for i in stride(from: 0, to: rgba.count, by: 4) {
            let n = (rng.next() - 0.5) * 0.04
            rgba[i] = min(max(rgba[i] + n, 0), 1)
            rgba[i + 1] = min(max(rgba[i + 1] + n, 0), 1)
            rgba[i + 2] = min(max(rgba[i + 2] + n, 0), 1)
        }
        return (MaskRefineGuide(width: width, height: height, rgba: rgba), truth)
    }

    /// Bilinear downscale stand-in for the quick pass (any-resolution read).
    private static func downsample(
        _ src: [Float], sw: Int, sh: Int, dw: Int, dh: Int
    ) -> [Float] {
        var out = [Float](repeating: 0, count: dw * dh)
        for dy in 0..<dh {
            let sy0 = dy * sh / dh, sy1 = max((dy + 1) * sh / dh, sy0 + 1)
            for dx in 0..<dw {
                let sx0 = dx * sw / dw, sx1 = max((dx + 1) * sw / dw, sx0 + 1)
                var acc: Float = 0
                var count: Float = 0
                for sy in sy0..<min(sy1, sh) {
                    for sx in sx0..<min(sx1, sw) {
                        acc += (src[(sy * sw + sx) * 4] + src[(sy * sw + sx) * 4 + 1]) / 2
                        count += 1
                    }
                }
                out[dy * dw + dx] = acc / count
            }
        }
        return out
    }

    /// The single-channel variant (the truth mask's quick-alpha stand-in).
    private static func downsampleGray(
        _ src: [Float], sw: Int, sh: Int, dw: Int, dh: Int
    ) -> [Float] {
        var out = [Float](repeating: 0, count: dw * dh)
        for dy in 0..<dh {
            let sy0 = dy * sh / dh, sy1 = max((dy + 1) * sh / dh, sy0 + 1)
            for dx in 0..<dw {
                let sx0 = dx * sw / dw, sx1 = max((dx + 1) * sw / dw, sx0 + 1)
                var acc: Float = 0
                var count: Float = 0
                for sy in sy0..<min(sy1, sh) {
                    for sx in sx0..<min(sx1, sw) {
                        acc += src[sy * sw + sx]
                        count += 1
                    }
                }
                out[dy * dw + dx] = acc / count
            }
        }
        return out
    }

    private static func flatRGBA(
        _ w: Int, _ h: Int, r: Float, g: Float, b: Float
    ) -> [Float] {
        var out = [Float](repeating: 0, count: w * h * 4)
        for i in stride(from: 0, to: out.count, by: 4) {
            out[i] = r; out[i + 1] = g; out[i + 2] = b; out[i + 3] = 1
        }
        return out
    }
}

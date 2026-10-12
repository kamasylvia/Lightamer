@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// PanoFeatureTests (Plan M5-3-01 T1; KD-1) — the feature segment's hand-value
// set: the octave-count table, the preview downsample size table (checker
// annotation: SIX rows, not eight), the encoded-input seam split (checker
// minor-2: the encoded seam must NOT re-encode), the preparation double-run
// bit identity, the synthetic dot-lattice DoG detection, the orientation
// rotation equivariance (±45°), the descriptor discriminativeness, the root
// normalization unit norm, and the response cap truncation.
// ─────────────────────────────────────────────────────────────────────────────

final class PanoFeatureTests: XCTestCase {

    // MARK: - Fixture machinery

    private func renderPlane(
        width: Int, height: Int, _ value: (Int, Int) -> Float
    ) -> PanoGrayPlane {
        var pixels = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = value(x, y)
            }
        }
        return PanoGrayPlane(width: width, height: height, pixels: pixels)
    }

    /// Replicate a gray plane into an RGBA float32 buffer (the prepare
    /// seams' input shape).
    private func rgba(_ gray: PanoGrayPlane) -> [Float] {
        var pixels = [Float](repeating: 0, count: gray.width * gray.height * 4)
        for index in 0..<(gray.width * gray.height) {
            pixels[index * 4] = gray.pixels[index]
            pixels[index * 4 + 1] = gray.pixels[index]
            pixels[index * 4 + 2] = gray.pixels[index]
            pixels[index * 4 + 3] = 1
        }
        return pixels
    }

    // MARK: - The octave-count table (KD-1 adaptive octaves)

    func testOctaveCountTable() {
        // floor(log2(minEdge)) − 3 clamped to [1, 6] — six hand rows.
        let table: [(minEdge: Int, octaves: Int)] = [
            (64, 3), (128, 4), (150, 4), (300, 5), (512, 6), (1200, 6),
        ]
        for row in table {
            XCTAssertEqual(
                PanoFeature.octaveCount(minEdge: row.minEdge), row.octaves,
                "minEdge \(row.minEdge)")
        }
        // Degenerate edges never return zero.
        XCTAssertEqual(PanoFeature.octaveCount(minEdge: 1), 1)
        XCTAssertEqual(PanoFeature.octaveCount(minEdge: 0), 1)
    }

    // MARK: - The preview downsample size table (checker annotation: 6 rows)

    func testPreviewDownsampleSizeTable() {
        // scale = min(1, 1200/max(w,h)); tw = max(1, round(w·scale)).
        let table: [(w: Int, h: Int, expectedW: Int, expectedH: Int)] = [
            (1200, 800, 1200, 800),   // at the cap — identity
            (2400, 1600, 1200, 800),  // exact ×0.5
            (1201, 900, 1200, 899),   // 900·(1200/1201) = 899.25 → 899
            (3000, 100, 1200, 40),    // extreme aspect — 0.4
            (2401, 1, 1200, 1),       // round(0.4998) = 0 → the max(1) guard
            (100, 50, 100, 50),       // below the cap — identity
        ]
        for row in table {
            let plane = renderPlane(width: row.w, height: row.h) { _, _ in 0.5 }
            let prepared = PanoFeature.preparePreviewGray(
                rgbaLinear: rgba(plane), width: row.w, height: row.h)
            XCTAssertEqual(
                prepared.width, row.expectedW, "\(row.w)×\(row.h) width")
            XCTAssertEqual(
                prepared.height, row.expectedH, "\(row.w)×\(row.h) height")
        }
    }

    // MARK: - The encoded seam split (checker minor-2)

    func testEncodedSeamSkipsReencode() {
        // A linear ramp with strong dynamic range.
        let width = 64
        let height = 48
        let linear = renderPlane(width: width, height: height) { x, y in
            Float(0.02 + 0.9 * Double(x) / Double(width - 1)
                + 0.05 * Double(y % 8) / 8)
        }
        let linearRGBA = rgba(linear)
        // Encode per channel by hand (the staged-plane shape the 02 leg has).
        var encodedRGBA = [Float](repeating: 0, count: linearRGBA.count)
        for index in 0..<(width * height) {
            for channel in 0..<3 {
                encodedRGBA[index * 4 + channel] = Float(
                    DrtEotfMath.srgbPiecewiseEncode(Double(linearRGBA[index * 4 + channel])))
            }
            encodedRGBA[index * 4 + 3] = 1
        }
        // The two seams must agree exactly: encoded input through the
        // encoded seam == linear input through the linear seam.
        let fromLinear = PanoFeature.preparePreviewGray(
            rgbaLinear: linearRGBA, width: width, height: height)
        let fromEncoded = PanoFeature.preparePreviewGray(
            rgbaEncoded: encodedRGBA, width: width, height: height)
        XCTAssertEqual(fromLinear.width, fromEncoded.width)
        XCTAssertEqual(fromLinear.height, fromEncoded.height)
        for index in fromLinear.pixels.indices {
            XCTAssertEqual(
                fromLinear.pixels[index], fromEncoded.pixels[index],
                "encoded seam drifted at \(index)")
        }
        // Negative pin: routing the ENCODED pixels through the linear seam
        // (the double-encode defect) must produce a DIFFERENT luma.
        let doubleEncoded = PanoFeature.preparePreviewGray(
            rgbaLinear: encodedRGBA, width: width, height: height)
        var differing = 0
        for index in fromLinear.pixels.indices
        where fromLinear.pixels[index] != doubleEncoded.pixels[index] {
            differing += 1
        }
        XCTAssertGreaterThan(
            differing, fromLinear.pixels.count / 2,
            "double-encode must diverge (the silent brightening defect)")
    }

    // MARK: - Preparation double-run bit identity (G1's local anchor)

    func testPrepareDoubleRunBitIdentity() {
        let width = 96
        let height = 72
        let linear = renderPlane(width: width, height: height) { x, y in
            Float(0.1 + 0.6 * Double((x * 7 + y * 13) % 32) / 32)
        }
        let first = PanoFeature.preparePreviewGray(
            rgbaLinear: rgba(linear), width: width, height: height)
        let second = PanoFeature.preparePreviewGray(
            rgbaLinear: rgba(linear), width: width, height: height)
        XCTAssertEqual(first.width, second.width)
        XCTAssertEqual(first.height, second.height)
        for index in first.pixels.indices {
            XCTAssertEqual(
                first.pixels[index].bitPattern, second.pixels[index].bitPattern,
                "preparation is not bit-identical at \(index)")
        }
    }

    // MARK: - DoG detection on a synthetic dot lattice

    func testDoGDetectsSyntheticDotLattice() {
        // 6×6 bright 5×5 dots on a dark field, pitch 14 — the blob centers
        // are DoG extrema by construction.
        let width = 90
        let height = 90
        let centers: [(Int, Int)] = (0..<6).flatMap { gy in
            (0..<6).map { gx in (7 + 14 * gx, 7 + 14 * gy) }
        }
        let plane = renderPlane(width: width, height: height) { x, y in
            let onDot = centers.contains { cx, cy in
                abs(x - cx) <= 2 && abs(y - cy) <= 2
            }
            return onDot ? Float(0.9) : Float(0.05)
        }
        let (keypoints, descriptors) = PanoFeature.detectAndDescribe(plane)
        XCTAssertGreaterThanOrEqual(
            keypoints.count, PanoFeature.minFeaturesPerImage,
            "the lattice must clear the <10-feature typed-failure floor")
        // Most dot centers are hit within a 4px radius.
        var hit = 0
        for (cx, cy) in centers
        where keypoints.contains(where: {
            abs($0.x - Double(cx)) <= 4 && abs($0.y - Double(cy)) <= 4
        }) {
            hit += 1
        }
        XCTAssertGreaterThan(
            hit, 24, "only \(hit)/36 dot centers detected")
        XCTAssertGreaterThan(descriptors.count, 0)
        for descriptor in descriptors {
            XCTAssertEqual(descriptor.vector.count, 128)
        }
    }

    // MARK: - Orientation rotation equivariance (KD-1 acceptance)

    func testOrientationFollowsBlockRotation() throws {
        // A bright bar on a dark field, axis-aligned vs +45°-rotated (both
        // rendered through the same supersampled pipeline). The detector's
        // coarse-scale bar-end keypoints appear at the rotated positions and
        // their orientations follow the rotation (probe-pinned: the two
        // counterparts land within 3° of the exact +45°). The comparison is
        // mod 180° — a bar end's gradient field is bimodal (the two long
        // edges point in opposite directions), in BOTH scenes alike.
        let width = 96
        let height = 96
        let center = 48.0
        func barScene(degrees: Double) -> PanoGrayPlane {
            let radians = -degrees * Double.pi / 180
            let supersample = 4
            return renderPlane(width: width, height: height) { x, y in
                var sum = 0.0
                for subY in 0..<supersample {
                    for subX in 0..<supersample {
                        let px = Double(x) + (Double(subX) + 0.5) / Double(supersample)
                        let py = Double(y) + (Double(subY) + 0.5) / Double(supersample)
                        let dx = px - center
                        let dy = py - center
                        let rx = center + Foundation.cos(radians) * dx
                            - Foundation.sin(radians) * dy
                        let ry = center + Foundation.sin(radians) * dx
                            + Foundation.cos(radians) * dy
                        let inside = rx >= 42 && rx <= 54 && ry >= 20 && ry <= 76
                        sum += inside ? 1.0 : 0.0
                    }
                }
                let coverage = sum / Double(supersample * supersample)
                return Float(0.05 + (0.9 - 0.05) * coverage)
            }
        }
        let keypointsA = PanoFeature.detect(barScene(degrees: 0))
            .filter { $0.sigma >= 4 }
        let keypointsB = PanoFeature.detect(barScene(degrees: 45))
            .filter { $0.sigma >= 4 }
        // Coarse-scale keypoints only: their orientation windows integrate a
        // wide neighborhood, so the long-edge frame dominates (probe-pinned:
        // the σ=6.4 counterparts track the rotation within 3°); fine-scale
        // corner keypoints are bimodal-noisy (single-pixel cap edges swing
        // the peak by ±90°) and would test corner pathology, not equivariance.
        let radians = 45.0 * Double.pi / 180
        var deltas: [Double] = []
        for keypointA in keypointsA {
            let dx = keypointA.x - center
            let dy = keypointA.y - center
            let expectedX = center + cos(radians) * dx - sin(radians) * dy
            let expectedY = center + sin(radians) * dx + cos(radians) * dy
            // The B counterpart: the detected keypoint nearest the rotated
            // position (the detector keeps a different keypoint SUBSET per
            // scene — position correspondence, not array order, pairs them).
            var best: PanoKeypoint?
            var bestDistance = 5.0
            for keypointB in keypointsB {
                let d = hypot(keypointB.x - expectedX, keypointB.y - expectedY)
                if d < bestDistance {
                    bestDistance = d
                    best = keypointB
                }
            }
            guard let keypointB = best else { continue }
            var delta = keypointB.orientation - keypointA.orientation - radians
            // mod 180° (the bimodal bar-end frame).
            while delta > Double.pi { delta -= 2 * Double.pi }
            while delta < -Double.pi { delta += 2 * Double.pi }
            if abs(delta) > Double.pi / 2 {
                delta = delta > 0 ? delta - Double.pi : delta + Double.pi
            }
            deltas.append(delta * 180 / Double.pi)
        }
        XCTAssertGreaterThanOrEqual(
            deltas.count, 2,
            "the rotated scene must keep >= 2 position-corresponding keypoints")
        for delta in deltas {
            XCTAssertLessThanOrEqual(
                abs(delta), 15,
                "orientation must follow the +45° rotation (residual \(delta)°)")
        }
    }

    // MARK: - Descriptor discriminativeness (KD-2 acceptance)

    func testDescriptorDiscriminativeAcrossShiftedViews() {
        let width = 160
        let height = 160
        // A field of scattered bright squares with UNIQUE sizes (repeated
        // same-size squares are locally indistinguishable — the strongest
        // descriptor would legitimately match any twin) and its (4, 3)-
        // shifted copy — the same physical patches appear in both views.
        let squares: [(cx: Int, cy: Int, half: Int)] = [
            (20, 20, 2), (60, 15, 3), (105, 25, 4), (140, 40, 5),
            (25, 60, 6), (70, 65, 7), (115, 75, 8), (145, 105, 9),
            (30, 105, 10), (75, 120, 11), (120, 135, 12), (40, 145, 13),
        ]
        func scene(_ offsetX: Int, _ offsetY: Int) -> PanoGrayPlane {
            renderPlane(width: width, height: height) { x, y in
                let onSquare = squares.contains { square in
                    abs(x + offsetX - square.cx) <= square.half
                        && abs(y + offsetY - square.cy) <= square.half
                }
                return onSquare ? Float(0.85) : Float(0.05)
            }
        }
        let (keypointsA, descriptorsA) = PanoFeature.detectAndDescribe(scene(0, 0))
        let (keypointsB, descriptorsB) = PanoFeature.detectAndDescribe(scene(4, 3))
        XCTAssertGreaterThanOrEqual(
            descriptorsA.count, PanoFeature.minFeaturesPerImage,
            "scattered-square field must clear the feature floor")
        guard !descriptorsA.isEmpty, !descriptorsB.isEmpty else { return }
        // The strongest descriptor in A must match its shifted twin in B,
        // and the match must beat every far-away distractor decisively.
        var bestA = descriptorsA[0]
        var bestNorm: Float = -1
        for descriptor in descriptorsA {
            let norm = descriptor.vector.reduce(0) { $0 + $1 * $1 }
            if norm > bestNorm {
                bestNorm = norm
                bestA = descriptor
            }
        }
        let source = keypointsA[bestA.keypointIndex]
        // BF over B (root vectors: Euclidean). The distance is broken into
        // an explicit accumulation loop — the one-expression zip/reduce form
        // blows the type-checker's time budget.
        var ranked: [(distance: Float, index: Int)] = []
        ranked.reserveCapacity(descriptorsB.count)
        for descriptor in descriptorsB {
            var sum: Float = 0
            for (a, b) in zip(bestA.vector, descriptor.vector) {
                let d = a - b
                sum += d * d
            }
            ranked.append((sqrt(sum), descriptor.keypointIndex))
        }
        ranked.sort { $0.distance < $1.distance }
        XCTAssertGreaterThanOrEqual(ranked.count, 2)
        let match = ranked[0]
        let matched = keypointsB[match.index]
        // The matched keypoint lands within ~3px of the shifted twin:
        // scene(offset) renders content at (cx − offset), so the expected
        // position is source − (4, 3).
        XCTAssertLessThanOrEqual(
            hypot(matched.x - (source.x - 4), matched.y - (source.y - 3)), 3.0,
            "the strongest descriptor did not match its shifted twin")
        // Discriminative: the winner beats the best far-away distractor.
        var distractorBest = Float.greatestFiniteMagnitude
        for (distance, index) in ranked {
            let candidate = keypointsB[index]
            if hypot(candidate.x - (source.x - 4), candidate.y - (source.y - 3)) > 15 {
                distractorBest = min(distractorBest, distance)
                break
            }
        }
        XCTAssertLessThan(
            match.distance, 0.5 * distractorBest,
            "the true match must decisively beat far-away distractors")
    }

    // MARK: - Root normalization unit norm (KD-2)

    func testRootNormalizationUnitNorm() {
        // The dot lattice (the detection test's scene — its center keypoints
        // carry non-degenerate descriptor windows).
        let width = 90
        let height = 90
        let centers: [(Int, Int)] = (0..<6).flatMap { gy in
            (0..<6).map { gx in (7 + 14 * gx, 7 + 14 * gy) }
        }
        let plane = renderPlane(width: width, height: height) { x, y in
            let onDot = centers.contains { cx, cy in
                abs(x - cx) <= 2 && abs(y - cy) <= 2
            }
            return onDot ? Float(0.9) : Float(0.05)
        }
        let (_, descriptors) = PanoFeature.detectAndDescribe(plane)
        XCTAssertGreaterThan(descriptors.count, 0)
        for descriptor in descriptors {
            let norm = sqrt(descriptor.vector.reduce(Float(0)) {
                $0 + $1 * $1
            })
            XCTAssertEqual(norm, 1, accuracy: 1e-4, "root vector is not unit")
            for value in descriptor.vector {
                XCTAssertGreaterThanOrEqual(value, 0)
            }
        }
    }

    // MARK: - Feature cap truncation (merge.py:219 semantics)

    func testFeatureCapTruncation() {
        // 30 distinct responses, cap 10 → the top 10 by response.
        var keypoints: [PanoKeypoint] = []
        for index in 0..<30 {
            keypoints.append(PanoKeypoint(
                x: Double(index), y: 0, octave: 0, sigma: 1,
                response: Double(index) + 1, orientation: 0))
        }
        let capped = PanoFeature.applyFeatureCap(keypoints, limit: 10)
        XCTAssertEqual(capped.count, 10)
        for (offset, keypoint) in capped.enumerated() {
            XCTAssertEqual(keypoint.response, Double(30 - offset))
        }
        // Equal responses tie-break by the ORIGINAL index (a total order —
        // Swift's sort is not stable, the cap must not depend on it).
        var ties: [PanoKeypoint] = []
        for index in 0..<5 {
            ties.append(PanoKeypoint(
                x: Double(index), y: 0, octave: 0, sigma: 1,
                response: 1, orientation: 0))
        }
        let tiedCap = PanoFeature.applyFeatureCap(ties, limit: 2)
        XCTAssertEqual(tiedCap.map(\.x), [0, 1])
    }
}

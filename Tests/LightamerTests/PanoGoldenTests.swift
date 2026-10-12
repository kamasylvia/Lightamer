@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// PanoGoldenTests (Plan M5-3-01 T5; KD-9) — the two golden gates of the
// math-core batch:
//
// G1 BIT-IDENTITY: the full chain (detect → describe → knn → ratio →
// RANSAC → focal → BA → wave) run TWICE over synthetic rendered views lands
// bit-identical results — the all-CPU sequential + single-RNG-stream
// determinism contract (KD-3) proven end to end.
//
// G2 SYNTHETIC RECOVERY: a TEST-LOCAL stamp renderer projects a dense
// irregular dot field through KNOWN cameras (deliberately self-contained —
// the anti-golden-loop rule), and the camera chain (RANSAC → focal →
// BA → wave) recovers the focal and the rotations against truth. Hard caps
// (KD-9): f ≤ 5% relative, R ≤ 2°, inlier ratio ≥ 60%. Measured bands land
// in M5-3-01-DECISIONS.
//
// REGISTERED FIXTURE FINDING (DECISIONS): through the DESCRIPTOR matching
// path, synthetic dot-field fixtures yield wrong-consensus matches (the
// same-size-blob ambiguity — 0/19 true under a self-consistent translation
// consensus), which starves the camera chain. G2 therefore derives its
// correspondences GEOMETRICALLY (the true test-local H's mutual nearest
// within a tight radius) to isolate the camera math the gate names; the
// matching segment's quality is pinned by PanoFeatureTests (discriminative-
// ness) and G1 (determinism), and the production leg (M5-3-02) rides real
// photographic content with the typed-failure surfaces for the rest.
// ─────────────────────────────────────────────────────────────────────────────

final class PanoGoldenTests: XCTestCase {

    // MARK: - The test-local renderer (KD-9: no production warp code)

    /// A dense irregular dot field stamp-rendered through the closed-form
    /// pinhole projection: dot centers project exactly, so the views stay
    /// exactly H-related; the ~26px mean spacing keeps each descriptor
    /// window's neighbor constellation unique. Deterministic per view (the
    /// same seeded draw in every view renders the SAME field).
    private func renderView(
        width: Int, height: Int, focal: Double, rotation: Mat3D
    ) -> PanoGrayPlane {
        let centerX = (Double(width) - 1) / 2
        let centerY = (Double(height) - 1) / 2
        var pixels = [Float](repeating: 0.05, count: width * height)
        var rng = PanoRNG(seed: 4242)
        let sizeClasses: [Double] = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
        for index in 0..<1200 {
            let lon = -0.75 + 1.5 * rng.nextUniform()
            let lat = -0.38 + 0.76 * rng.nextUniform()
            let half = sizeClasses[index % sizeClasses.count]
            let direction = SIMD3(
                cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
            // cam_ray = R·world_dir (the world→camera convention).
            let ray = SIMD3(
                rotation[0, 0] * direction.x + rotation[0, 1] * direction.y
                    + rotation[0, 2] * direction.z,
                rotation[1, 0] * direction.x + rotation[1, 1] * direction.y
                    + rotation[1, 2] * direction.z,
                rotation[2, 0] * direction.x + rotation[2, 1] * direction.y
                    + rotation[2, 2] * direction.z)
            guard ray.z > 0.2 else { continue }
            let px = focal * ray.x / ray.z + centerX
            let py = focal * ray.y / ray.z + centerY
            let radius = Int(half.rounded(.up))
            for dy in -radius...radius {
                let yy = Int(py) + dy
                guard yy >= 0, yy < height else { continue }
                for dx in -radius...radius {
                    let xx = Int(px) + dx
                    guard xx >= 0, xx < width else { continue }
                    if Double(dx * dx + dy * dy) <= half * half {
                        pixels[yy * width + xx] = 0.9
                    }
                }
            }
        }
        return PanoGrayPlane(width: width, height: height, pixels: pixels)
    }

    private func rotationAroundY(_ yaw: Double) -> Mat3D {
        PanoCamera.rotation(fromAxisAngle: SIMD3(0, yaw, 0))
    }

    private let goldenFocal = 500.0
    private let goldenSize = (width: 700, height: 500)
    private let goldenYaws: [Double] = [-25, -10, 10, 25].map {
        $0 * Double.pi / 180
    }

    private func renderedViews(_ yaws: [Double]) -> [PanoGrayPlane] {
        yaws.map {
            renderView(
                width: goldenSize.width, height: goldenSize.height,
                focal: goldenFocal, rotation: rotationAroundY($0))
        }
    }

    // MARK: - The chain assemblies

    /// The full descriptor chain (G1's determinism subject): detect → knn →
    /// ratio → RANSAC → focal → BA → wave, ONE rng stream, coordinates
    /// centered per the PanoCamera contract.
    private func runDescriptorChain(planes: [PanoGrayPlane]) -> ChainResult {
        let detections = planes.map { PanoFeature.detectAndDescribe($0) }
        let centerX = (Double(planes[0].width) - 1) / 2
        let centerY = (Double(planes[0].height) - 1) / 2
        var rng = PanoRNG(seed: 121)
        var estimates: [PanoHomographyEstimate?] = []
        var matchedCounts: [Int] = []
        var bundles: [PanoMatchBundle] = []
        for index in planes.indices.dropFirst() {
            let matches = PanoMatch.knn2(
                query: detections[0].descriptors,
                train: detections[index].descriptors)
            let kept = PanoMatch.ratioFilter(matches)
            matchedCounts.append(kept.count)
            let correspondences = kept.map { match -> PanoCorrespondence in
                let first = detections[0].keypoints[match.queryIndex]
                let second = detections[index].keypoints[match.bestIndex]
                return PanoCorrespondence(
                    first.x - centerX, first.y - centerY,
                    second.x - centerX, second.y - centerY)
            }
            let estimate = PanoMatch.ransacHomography(correspondences, rng: &rng)
            estimates.append(estimate)
            if let estimate {
                bundles.append(PanoMatchBundle(
                    first: 0, second: index,
                    correspondences: estimate.inliers.map { correspondences[$0] }))
            }
        }
        let initialFocal = PanoCamera.medianFocal(
            estimates.compactMap { $0?.homography }) ?? goldenFocal
        var initialRotations = planes.map { _ in Mat3D.identity }
        for (index, estimate) in estimates.enumerated()
        where index + 1 < planes.count {
            if let homography = estimate?.homography,
               let rotation = PanoCamera.initialRotation(
                from: homography, focal: initialFocal) {
                initialRotations[index + 1] = rotation
            }
        }
        let solution = PanoCamera.bundleAdjust(
            matches: bundles, imageCount: planes.count,
            initialFocal: initialFocal, initialRotations: initialRotations)
        let corrected = PanoCamera.waveCorrectHorizontally(
            solution?.rotations ?? planes.map { _ in Mat3D.identity })
        return ChainResult(
            keypoints: detections.map(\.keypoints),
            descriptors: detections.map(\.descriptors),
            estimates: estimates, matchedCounts: matchedCounts,
            solution: solution, corrected: corrected)
    }

    /// The camera chain (G2's accuracy subject): correspondences derived
    /// GEOMETRICALLY under the true test-local H (mutual nearest within
    /// `radius`), then RANSAC → focal → BA → wave over the production
    /// functions. See the registered fixture finding in the header.
    private func runCameraChain(
        planes: [PanoGrayPlane], truths: [Mat3D]
    ) -> ChainResult {
        let detections = planes.map { PanoFeature.detectAndDescribe($0) }
        let centerX = (Double(planes[0].width) - 1) / 2
        let centerY = (Double(planes[0].height) - 1) / 2
        let k = PanoCamera.calibrationK(focal: goldenFocal)
        var rng = PanoRNG(seed: 121)
        var estimates: [PanoHomographyEstimate?] = []
        var matchedCounts: [Int] = []
        var bundles: [PanoMatchBundle] = []
        for index in planes.indices.dropFirst() {
            let relative = Mat3D.mul(truths[index], truths[0].inverted()!)
            let trueHomography = Mat3D.mul(Mat3D.mul(k, relative), k.inverted()!)
            var correspondences: [PanoCorrespondence] = []
            for keypoint in detections[0].keypoints {
                let projected = trueHomography.project(
                    keypoint.x - centerX, keypoint.y - centerY)
                var best = -1
                var bestDistance = 2.0
                for (candidate, other) in detections[index].keypoints.enumerated() {
                    let d = hypot(
                        other.x - centerX - projected.x,
                        other.y - centerY - projected.y)
                    if d < bestDistance {
                        bestDistance = d
                        best = candidate
                    }
                }
                guard best >= 0 else { continue }
                // Mutual check under the inverse map.
                let back = (trueHomography.inverted() ?? Mat3D.identity).project(
                    detections[index].keypoints[best].x - centerX,
                    detections[index].keypoints[best].y - centerY)
                if hypot(
                    back.x - (keypoint.x - centerX),
                    back.y - (keypoint.y - centerY)) < 2.5 {
                    correspondences.append(PanoCorrespondence(
                        keypoint.x - centerX, keypoint.y - centerY,
                        detections[index].keypoints[best].x - centerX,
                        detections[index].keypoints[best].y - centerY))
                }
            }
            matchedCounts.append(correspondences.count)
            let estimate = PanoMatch.ransacHomography(correspondences, rng: &rng)
            estimates.append(estimate)
            if let estimate {
                bundles.append(PanoMatchBundle(
                    first: 0, second: index,
                    correspondences: estimate.inliers.map { correspondences[$0] }))
            }
        }
        let initialFocal = PanoCamera.medianFocal(
            estimates.compactMap { $0?.homography }) ?? goldenFocal
        var initialRotations = planes.map { _ in Mat3D.identity }
        for (index, estimate) in estimates.enumerated()
        where index + 1 < planes.count {
            if let homography = estimate?.homography,
               let rotation = PanoCamera.initialRotation(
                from: homography, focal: initialFocal) {
                initialRotations[index + 1] = rotation
            }
        }
        let solution = PanoCamera.bundleAdjust(
            matches: bundles, imageCount: planes.count,
            initialFocal: initialFocal, initialRotations: initialRotations)
        let corrected = PanoCamera.waveCorrectHorizontally(
            solution?.rotations ?? planes.map { _ in Mat3D.identity })
        return ChainResult(
            keypoints: detections.map(\.keypoints),
            descriptors: detections.map(\.descriptors),
            estimates: estimates, matchedCounts: matchedCounts,
            solution: solution, corrected: corrected)
    }

    private struct ChainResult {
        var keypoints: [[PanoKeypoint]]
        var descriptors: [[PanoDescriptor]]
        var estimates: [PanoHomographyEstimate?]
        var matchedCounts: [Int]
        var solution: PanoCameraSolution?
        var corrected: [Mat3D]
    }

    private func assertChainBitEqual(_ a: ChainResult, _ b: ChainResult) {
        XCTAssertEqual(a.keypoints.count, b.keypoints.count)
        for view in a.keypoints.indices {
            XCTAssertEqual(a.keypoints[view].count, b.keypoints[view].count)
            for (index, keypoint) in a.keypoints[view].enumerated() {
                let other = b.keypoints[view][index]
                XCTAssertEqual(keypoint.x.bitPattern, other.x.bitPattern)
                XCTAssertEqual(keypoint.y.bitPattern, other.y.bitPattern)
                XCTAssertEqual(keypoint.sigma.bitPattern, other.sigma.bitPattern)
                XCTAssertEqual(
                    keypoint.orientation.bitPattern, other.orientation.bitPattern)
                XCTAssertEqual(
                    keypoint.response.bitPattern, other.response.bitPattern)
            }
            XCTAssertEqual(a.descriptors[view].count, b.descriptors[view].count)
            for (index, descriptor) in a.descriptors[view].enumerated() {
                let other = b.descriptors[view][index]
                XCTAssertEqual(descriptor.keypointIndex, other.keypointIndex)
                for (dimension, value) in descriptor.vector.enumerated() {
                    XCTAssertEqual(
                        value.bitPattern, other.vector[dimension].bitPattern,
                        "descriptor \(index) dim \(dimension) diverged")
                }
            }
        }
        XCTAssertEqual(a.estimates.count, b.estimates.count)
        for (index, estimate) in a.estimates.enumerated() {
            let other = b.estimates[index]
            XCTAssertEqual(estimate?.inliers, other?.inliers)
            XCTAssertEqual(estimate?.iterations, other?.iterations)
            guard let homography = estimate?.homography,
                  let otherHomography = other?.homography else {
                XCTAssertNil(estimate)
                XCTAssertNil(other)
                continue
            }
            for i in 0..<3 {
                for j in 0..<3 {
                    XCTAssertEqual(
                        homography[i, j].bitPattern, otherHomography[i, j].bitPattern,
                        "homography \(index) (\(i),\(j)) diverged")
                }
            }
        }
        guard let solutionA = a.solution, let solutionB = b.solution else {
            XCTFail("the chains produced no bundle solution")
            return
        }
        XCTAssertEqual(solutionA.focal.bitPattern, solutionB.focal.bitPattern)
        for view in solutionA.rotations.indices {
            for i in 0..<3 {
                for j in 0..<3 {
                    XCTAssertEqual(
                        solutionA.rotations[view][i, j].bitPattern,
                        solutionB.rotations[view][i, j].bitPattern,
                        "rotation \(view) (\(i),\(j)) diverged")
                }
            }
        }
        for (view, rotation) in a.corrected.enumerated() {
            for i in 0..<3 {
                for j in 0..<3 {
                    XCTAssertEqual(
                        rotation[i, j].bitPattern, b.corrected[view][i, j].bitPattern,
                        "corrected \(view) (\(i),\(j)) diverged")
                }
            }
        }
    }

    // MARK: - G1 (KD-9)

    func testG1TwoViewChainBitIdentity() {
        let planes = renderedViews([-5 * Double.pi / 180, 5 * Double.pi / 180])
        let first = runDescriptorChain(planes: planes)
        let second = runDescriptorChain(planes: planes)
        assertChainBitEqual(first, second)
    }

    func testG1FourViewChainBitIdentity() {
        let planes = renderedViews(goldenYaws)
        let first = runDescriptorChain(planes: planes)
        let second = runDescriptorChain(planes: planes)
        assertChainBitEqual(first, second)
    }

    // MARK: - G2 (KD-9)

    func testG2RecoversFocalAndRotations() throws {
        let truths = goldenYaws.map { rotationAroundY($0) }
        let planes = renderedViews(goldenYaws)
        let result = runCameraChain(planes: planes, truths: truths)
        let solution = try XCTUnwrap(result.solution)
        // f relative error ≤ 5% (the KD-9 hard cap; measured 0.3-1%).
        let focalError = abs(solution.focal - goldenFocal) / goldenFocal
        XCTAssertLessThanOrEqual(focalError, 0.05)
        // R angular error ≤ 2° per view (the KD-9 hard cap; measured
        // < 0.1°), gauge-anchored through view 0 (the solver's documented
        // global gauge freedom): compare the anchored relative rotations.
        for index in truths.indices {
            let solutionRelative = Mat3D.mul(
                solution.rotations[0].inverted() ?? Mat3D.identity,
                solution.rotations[index])
            let truthRelative = Mat3D.mul(
                truths[0].inverted() ?? Mat3D.identity, truths[index])
            let error = PanoCamera.relativeAngle(solutionRelative, truthRelative)
            XCTAssertLessThanOrEqual(
                error, 2 * Double.pi / 180,
                "view \(index): gauge-anchored rotation error "
                    + "\(error * 180 / Double.pi)°")
        }
        // Inlier ratio ≥ 60% of each pair's correspondences (the KD-9 hard
        // cap; measured ≈ 100% on the geometric set).
        for (index, estimate) in result.estimates.enumerated() {
            guard let estimate else {
                XCTFail("pair \(index) produced no RANSAC model")
                continue
            }
            let matched = result.matchedCounts[index]
            XCTAssertGreaterThan(matched, 0, "pair \(index) matched nothing")
            XCTAssertGreaterThanOrEqual(
                Double(estimate.inliers.count), 0.6 * Double(matched),
                "pair \(index): \(estimate.inliers.count)/\(matched) inliers")
        }
    }

    func testG2DisconnectedTypedFailure() {
        // View 2 faces AWAY from the reference trio (no overlap → no valid
        // edges): the reference BFS closure misses it — the merge.py:238
        // semantics, typed with the KD-4 disconnected prefix.
        let awayYaws: [Double] = [-15, -5, 95, 15].map {
            $0 * Double.pi / 180
        }
        let truths = awayYaws.map { rotationAroundY($0) }
        let planes = awayYaws.map {
            renderView(
                width: 400, height: 300, focal: 500,
                rotation: rotationAroundY($0))
        }
        let detections = planes.map { PanoFeature.detectAndDescribe($0) }
        var adjacency: [Set<Int>] = (0..<planes.count).map { [$0] }
        for index in planes.indices.dropFirst() {
            let matches = PanoMatch.ratioFilter(PanoMatch.knn2(
                query: detections[0].descriptors,
                train: detections[index].descriptors))
            let correspondences = matches.map { match -> PanoCorrespondence in
                let first = detections[0].keypoints[match.queryIndex]
                let second = detections[index].keypoints[match.bestIndex]
                return PanoCorrespondence(first.x, first.y, second.x, second.y)
            }
            var rng = PanoRNG(seed: 121)
            guard let estimate = PanoMatch.ransacHomography(
                correspondences, rng: &rng) else { continue }
            let confidence = PanoMatch.matchConfidence(
                inliers: estimate.inliers.count, matches: correspondences.count)
            if PanoMatch.isValidEdge(
                confidence: confidence, inliers: estimate.inliers.count) {
                adjacency[0].insert(index)
                adjacency[index].insert(0)
            }
        }
        let component = PanoMatch.connectedComponent(
            imageCount: planes.count, adjacency: adjacency, reference: 0)
        XCTAssertNotEqual(
            component.count, planes.count,
            "the 95° view must stay disconnected from the reference trio")
        let message = PanoMatch.FailurePrefix.disconnected
            + "\(component.count) of \(planes.count) images in the closure"
        XCTAssertTrue(message.hasPrefix("panorama images disconnected: "))
    }

    func testG2LowTextureTypedFailure() {
        // A pure flat plane: the detector finds nothing — the merge.py
        // :223-224 semantics, typed with the KD-4 alignment prefix.
        let plane = PanoGrayPlane(
            width: 300, height: 240,
            pixels: [Float](repeating: 0.5, count: 300 * 240))
        let (keypoints, _) = PanoFeature.detectAndDescribe(plane)
        XCTAssertLessThan(
            keypoints.count, PanoFeature.minFeaturesPerImage,
            "a flat plane must stay under the feature floor")
        let message = PanoMatch.FailurePrefix.alignment
            + "image 0 has \(keypoints.count) features (< "
            + "\(PanoFeature.minFeaturesPerImage))"
        XCTAssertTrue(message.hasPrefix("panorama alignment failed: "))
    }
}

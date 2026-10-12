@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// PanoCameraTests (Plan M5-3-01 T3; KD-5) — the camera segment's hand-value
// set: the focal-from-homography closed form (known f, pure rotation → nil),
// the median focal anchor, the LM bundle recovery of known cameras
// (gauge-invariant pairwise comparison), the N=2 degenerate convergence, the
// typed failure gates, the wave-correct idempotence (bit-identical second
// call), and the sign orientation rule for both roll directions.
// ─────────────────────────────────────────────────────────────────────────────

final class PanoCameraTests: XCTestCase {

    /// The header homography H = K(f)·R·K(f)⁻¹ for a known focal.
    private func homography(focal: Double, rotation: Mat3D) -> Mat3D {
        let k = PanoCamera.calibrationK(focal: focal)
        // K is diagonal-positive — the inverse always exists.
        let kInverse = k.inverted()!
        return Mat3D.mul(Mat3D.mul(k, rotation), kInverse)
    }

    // MARK: - focal-from-homography (KD-5)

    func testFocalFromHomographyKnownFocal() throws {
        let focal = 800.0
        let r = PanoCamera.rotation(fromAxisAngle: SIMD3(0.1, 0.2, 0.05))
        let estimate = try XCTUnwrap(
            PanoCamera.focalFromHomography(homography(focal: focal, rotation: r)))
        XCTAssertEqual(estimate, focal, accuracy: focal * 1e-9)
        // The median anchor over several pairs (one extreme outlier pair
        // must not move it — the merge.py:251 semantics).
        let homographies = [500.0, 610.0, 620.0, 630.0, 9999.0].map {
            homography(focal: $0, rotation: r)
        }
        let median = try XCTUnwrap(PanoCamera.medianFocal(homographies))
        XCTAssertEqual(median, 620.0, accuracy: 1e-6)
    }

    func testFocalFromHomographyPureRotationNil() {
        // H = I carries no focal information: D = 0 and A = B = 0.
        XCTAssertNil(PanoCamera.focalFromHomography(Mat3D.identity))
    }

    // MARK: - LM bundle adjustment (KD-5)

    /// Four cameras (known f + small rotations) viewing a ray fan; the
    /// matches are the exact projections (no noise).
    private func syntheticScene(
        focal: Double
    ) -> (rotations: [Mat3D], matches: [PanoMatchBundle]) {
        let rotvecs: [SIMD3<Double>] = [
            SIMD3(0.0, 0.05, 0.10),
            SIMD3(0.0, -0.05, -0.10),
            SIMD3(0.08, 0.03, 0.15),
            SIMD3(-0.06, 0.0, -0.12),
        ]
        let rotations = rotvecs.map { PanoCamera.rotation(fromAxisAngle: $0) }
        var directions: [SIMD3<Double>] = []
        for elevation in stride(from: -0.12, through: 0.12, by: 0.06) {
            for azimuth in stride(from: -0.15, through: 0.15, by: 0.075) {
                let ce = cos(elevation)
                directions.append(SIMD3(
                    sin(azimuth) * ce, sin(elevation), cos(azimuth) * ce))
            }
        }
        func pixels(_ rotation: Mat3D) -> [(Double, Double)] {
            directions.map { direction in
                let camera = SIMD3(
                    rotation[0, 0] * direction.x + rotation[0, 1] * direction.y
                        + rotation[0, 2] * direction.z,
                    rotation[1, 0] * direction.x + rotation[1, 1] * direction.y
                        + rotation[1, 2] * direction.z,
                    rotation[2, 0] * direction.x + rotation[2, 1] * direction.y
                        + rotation[2, 2] * direction.z)
                return (focal * camera.x / camera.z, focal * camera.y / camera.z)
            }
        }
        let allPixels = rotations.map { pixels($0) }
        let pairIndices: [(Int, Int)] = [(0, 1), (0, 2), (0, 3), (1, 2)]
        let matches: [PanoMatchBundle] = pairIndices.map { first, second in
            let firstPixels = allPixels[first]
            let secondPixels = allPixels[second]
            let correspondences = zip(firstPixels, secondPixels).map {
                PanoCorrespondence($0.0, $0.1, $1.0, $1.1)
            }
            return PanoMatchBundle(
                first: first, second: second, correspondences: correspondences)
        }
        return (rotations, matches)
    }

    func testLMBundleRecoversKnownCameras() throws {
        let focal = 600.0
        let (truth, matches) = syntheticScene(focal: focal)
        // A deliberately wrong start: focal off by 1/6, rotations off by
        // ~2-4° — the LM must pull it back (gauge aside).
        var initialRotations: [Mat3D] = []
        for rotation in truth {
            initialRotations.append(PanoCamera.rotation(
                fromAxisAngle: PanoCamera.axisAngle(from: rotation)
                    + SIMD3(0.03, -0.04, 0.05)))
        }
        let solution = try XCTUnwrap(PanoCamera.bundleAdjust(
            matches: matches, imageCount: truth.count,
            initialFocal: 700, initialRotations: initialRotations))
        XCTAssertEqual(solution.focal, focal, accuracy: focal * 1e-4)
        XCTAssertLessThanOrEqual(solution.residualRMS, 1e-6)
        // The gauge-invariant comparison: pairwise relative rotations.
        for i in 0..<truth.count {
            for j in (i + 1)..<truth.count {
                let truthAngle = PanoCamera.relativeAngle(truth[i], truth[j])
                let gotAngle = PanoCamera.relativeAngle(
                    solution.rotations[i], solution.rotations[j])
                XCTAssertLessThanOrEqual(
                    abs(truthAngle - gotAngle), 0.05 * Double.pi / 180,
                    "pair (\(i),\(j)) relative angle drifted")
            }
        }
    }

    func testLMBundleN2DegenerateConverges() throws {
        // The KD-5 N=2 note: 7 parameters from one pair's rays is an
        // underdetermined surface — LM damping + the initial anchor must
        // still land a low-residual solution.
        let focal = 500.0
        let truth = [
            PanoCamera.rotation(fromAxisAngle: SIMD3(0.0, 0.04, 0.08)),
            PanoCamera.rotation(fromAxisAngle: SIMD3(0.0, -0.04, -0.08)),
        ]
        var directions: [SIMD3<Double>] = []
        for elevation in stride(from: -0.10, through: 0.10, by: 0.05) {
            for azimuth in stride(from: -0.12, through: 0.12, by: 0.06) {
                let ce = cos(elevation)
                directions.append(SIMD3(
                    sin(azimuth) * ce, sin(elevation), cos(azimuth) * ce))
            }
        }
        func pixels(_ rotation: Mat3D) -> [(Double, Double)] {
            directions.map { direction in
                let camera = SIMD3(
                    rotation[0, 0] * direction.x + rotation[0, 1] * direction.y
                        + rotation[0, 2] * direction.z,
                    rotation[1, 0] * direction.x + rotation[1, 1] * direction.y
                        + rotation[1, 2] * direction.z,
                    rotation[2, 0] * direction.x + rotation[2, 1] * direction.y
                        + rotation[2, 2] * direction.z)
                return (focal * camera.x / camera.z, focal * camera.y / camera.z)
            }
        }
        let correspondences = zip(pixels(truth[0]), pixels(truth[1])).map {
            PanoCorrespondence($0.0, $0.1, $1.0, $1.1)
        }
        let matches = [PanoMatchBundle(
            first: 0, second: 1, correspondences: correspondences)]
        let initial = truth.map {
            PanoCamera.rotation(
                fromAxisAngle: PanoCamera.axisAngle(from: $0)
                    + SIMD3(0.02, 0.02, -0.02))
        }
        let solution = try XCTUnwrap(PanoCamera.bundleAdjust(
            matches: matches, imageCount: 2,
            initialFocal: 560, initialRotations: initial))
        XCTAssertLessThanOrEqual(solution.residualRMS, 1e-6)
    }

    func testLMBundleTypedFailureGates() {
        // Empty inputs and an exhausted iteration cap both land the typed
        // nil (the production leg maps it into the "panorama alignment
        // failed: " family).
        let rotation = PanoCamera.rotation(fromAxisAngle: SIMD3(0, 0.1, 0))
        XCTAssertNil(PanoCamera.bundleAdjust(
            matches: [], imageCount: 2, initialFocal: 500,
            initialRotations: [rotation, rotation]))
        let correspondence = PanoCorrespondence(10, 10, 12, 11)
        XCTAssertNil(PanoCamera.bundleAdjust(
            matches: [PanoMatchBundle(
                first: 0, second: 1, correspondences: [correspondence])],
            imageCount: 2, initialFocal: 500,
            initialRotations: [rotation, rotation], maxIterations: 0))
    }

    // MARK: - Wave correct (KD-5)

    /// A horizontal pan family rolled by `roll` about the view axis.
    private func rolledPan(roll: Double) -> [Mat3D] {
        let yaws: [Double] = [-0.15, -0.05, 0.05, 0.15]
        return yaws.map { yaw in
            let rollRotation = PanoCamera.rotation(fromAxisAngle: SIMD3(0, 0, roll))
            let yawRotation = PanoCamera.rotation(fromAxisAngle: SIMD3(0, yaw, 0))
            return Mat3D.mul(rollRotation, yawRotation)
        }
    }

    func testWaveCorrectStraightensAndSignOrients() {
        // Both roll signs must end with Σ first-row x-components ≥ 0 (the
        // plan-pinned sign rule) and the x direction carrying the smallest
        // first-row variance (the least-varying direction becomes x).
        for roll in [20.0 * Double.pi / 180, -20.0 * Double.pi / 180] {
            let corrected = PanoCamera.waveCorrectHorizontally(rolledPan(roll: roll))
            var sumX = 0.0
            var sumX2 = 0.0
            var sumY2 = 0.0
            for r in corrected {
                sumX += r[0, 0]
                sumX2 += r[0, 0] * r[0, 0]
                sumY2 += r[0, 1] * r[0, 1]
            }
            XCTAssertGreaterThanOrEqual(
                sumX, 0, "roll \(roll): the sign orientation must hold")
            XCTAssertLessThanOrEqual(
                sumX2, sumY2 + 1e-9,
                "roll \(roll): x must carry the smallest first-row variance")
        }
    }

    func testWaveCorrectIdempotentBitwise() {
        let once = PanoCamera.waveCorrectHorizontally(rolledPan(roll: 0.3))
        let twice = PanoCamera.waveCorrectHorizontally(once)
        XCTAssertEqual(once.count, twice.count)
        for index in once.indices {
            for i in 0..<3 {
                for j in 0..<3 {
                    XCTAssertEqual(
                        once[index][i, j].bitPattern, twice[index][i, j].bitPattern,
                        "wave correct is not idempotent at \(index) (\(i),\(j))")
                }
            }
        }
        // The already-straightened set rides the exact-identity guard.
        XCTAssertEqual(PanoCamera.waveCorrectHorizontally([]).count, 0)
    }
}

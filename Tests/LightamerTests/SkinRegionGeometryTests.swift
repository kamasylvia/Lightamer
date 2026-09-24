@testable import LightamerCore
@testable import LightamerIOP
import CoreGraphics
import CoreImage
import XCTest

// SkinRegionGeometryTests (Plan 07-2 T3) — the skin-mask geometry chain,
// PURE SWIFT on synthesized point lists (NO model inference needed — the
// testability hinge of 07-RESEARCH §2.2):
//   - frontal face: hull interior = 1 / protection zones = 0 / outside = 0 /
//     forehead band = 1 (the U-closure);
//   - yaw gate: > 45° excluded with a typed warning; all-gated = typed error;
//   - multi-face union;
//   - empty landmarks / no faces = typed errors (never a degrade);
//   - ⊗ person matte (bilinear resample when sizes differ);
//   - the Vision lower-left → top-left coordinate conversion (the
//     VNImagePointForFaceLandmarkPoint-equivalent formula).
//
// The REAL-MODEL leg (VisionFaceLandmarkProvider on a synthesized face
// drawing) is directional (bbox tolerance) and skips with a recorded
// reason when the test host cannot run Vision (the 07-1 layer-B
// entitlement precedent).
final class SkinRegionGeometryTests: XCTestCase {

    // MARK: - Synthetic face factory

    /// An oval frontal face: 12-point jaw contour (ear to ear through the
    /// chin), eye blobs, brow lines, lip quad, nostril triple — everything
    /// in TOP-LEFT normalized coordinates.
    private func synthFace(
        center: SIMD2<Double>, faceWidth: Double, faceHeight: Double,
        yaw: Double? = nil
    ) -> FaceLandmarkSet {
        var contour: [SIMD2<Double>] = []
        for i in 0..<12 {
            // Half-ellipse angle: right ear (t=0) → chin (t=0.5) → left ear.
            // TOP-LEFT coords: the chin (sin = 1) sits BELOW the center —
            // y GROWS downward, so the jaw arc adds.
            let t = Double(i) / 12.0
            let angle = Double.pi * t
            let x = center.x + cos(angle) * faceWidth / 2
            let y = center.y + sin(angle) * faceHeight / 2
            contour.append(SIMD2(x: x, y: y))
        }
        func blob(_ c: SIMD2<Double>, _ r: Double, _ n: Int) -> [SIMD2<Double>] {
            (0..<n).map { i in
                let a = Double(i) / Double(n) * 2 * .pi
                return SIMD2(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            }
        }
        func line(_ from: SIMD2<Double>, _ to: SIMD2<Double>, _ n: Int) -> [SIMD2<Double>] {
            (0..<n).map { i in
                let t = Double(i) / Double(max(n - 1, 1))
                return SIMD2(
                    x: from.x + (to.x - from.x) * t,
                    y: from.y + (to.y - from.y) * t)
            }
        }
        let eyeY = center.y - faceHeight * 0.10
        let browY = center.y - faceHeight * 0.22
        let leftEyeC = SIMD2(x: center.x - faceWidth * 0.20, y: eyeY)
        let rightEyeC = SIMD2(x: center.x + faceWidth * 0.20, y: eyeY)
        return FaceLandmarkSet(
            faceContour: contour,
            leftEye: blob(leftEyeC, faceWidth * 0.08, 6),
            rightEye: blob(rightEyeC, faceWidth * 0.08, 6),
            leftEyebrow: line(
                SIMD2(x: center.x - faceWidth * 0.32, y: browY),
                SIMD2(x: center.x - faceWidth * 0.08, y: browY - faceHeight * 0.02), 5),
            rightEyebrow: line(
                SIMD2(x: center.x + faceWidth * 0.08, y: browY - faceHeight * 0.02),
                SIMD2(x: center.x + faceWidth * 0.32, y: browY), 5),
            outerLips: blob(SIMD2(x: center.x, y: center.y + faceHeight * 0.28), faceWidth * 0.18, 8),
            nostrils: blob(SIMD2(x: center.x, y: center.y + faceHeight * 0.12), faceWidth * 0.10, 5),
            yawDegrees: yaw)
    }

    private let size = 200
    private var config: SkinRegionConfig { SkinRegionConfig() }

    private func sample(
        _ mask: [Float], x: Double, y: Double, width: Int = 200
    ) -> Float {
        mask[Int(y * Double(width)) * width + Int(x * Double(width))]
    }

    // MARK: - Case 1: frontal face (hull / protection / forehead / outside)

    func testFrontalFaceMaskDirections() throws {
        let face = synthFace(
            center: SIMD2(x: 0.5, y: 0.5), faceWidth: 0.4, faceHeight: 0.5)
        let (plane, warnings) = try SkinRegionLocator.skinMask(
            faces: [face], personMatte: nil, width: size, height: size, config: config)
        XCTAssertEqual(warnings.isEmpty, true, "frontal full-landmark face yields no warnings")
        let mask = plane.floats

        // Hull interior, clear of protections: the cheeks — 1.
        XCTAssertEqual(sample(mask, x: 0.5, y: 0.72), 1, "chin-adjacent cheek inside hull")
        XCTAssertEqual(sample(mask, x: 0.34, y: 0.52), 1, "left cheek inside hull")
        XCTAssertEqual(sample(mask, x: 0.66, y: 0.52), 1, "right cheek inside hull")

        // Protection zones: eye centers — 0.
        XCTAssertEqual(sample(mask, x: 0.5 - 0.4 * 0.20, y: 0.5 - 0.5 * 0.10), 0, "left eye protected")
        XCTAssertEqual(sample(mask, x: 0.5 + 0.4 * 0.20, y: 0.5 - 0.5 * 0.10), 0, "right eye protected")
        // Lips + nostrils — 0.
        XCTAssertEqual(sample(mask, x: 0.5, y: 0.5 + 0.5 * 0.28), 0, "lips protected")
        XCTAssertEqual(sample(mask, x: 0.5, y: 0.5 + 0.5 * 0.12), 0, "nostrils protected")

        // Forehead band (above the brows, inside the hull's top closure) — 1.
        // browY = 0.39, forehead top = 0.33 (brow − 12% lift): sample
        // inside the band.
        XCTAssertEqual(sample(mask, x: 0.5, y: 0.36), 1, "forehead inside the band closure")

        // Outside the hull — 0.
        XCTAssertEqual(sample(mask, x: 0.05, y: 0.05), 0, "corner outside the hull")
        XCTAssertEqual(sample(mask, x: 0.9, y: 0.9), 0, "opposite corner outside the hull")

        // Directional mass check (anti-vacuum): neither empty nor full.
        let ones = mask.filter { $0 > 0.5 }.count
        XCTAssertGreaterThan(ones, size * size / 20, "substantial skin area")
        XCTAssertLessThan(ones, size * size / 2, "not everything is skin")
    }

    // MARK: - Case 2: yaw gate

    func testYawGateExcludesAndWarns() throws {
        let frontal = synthFace(center: SIMD2(x: 0.35, y: 0.5), faceWidth: 0.3, faceHeight: 0.4)
        let profile = synthFace(
            center: SIMD2(x: 0.75, y: 0.5), faceWidth: 0.3, faceHeight: 0.4, yaw: 60)

        // Mixed: the profile is excluded with a warning; the frontal survives.
        let (plane, warnings) = try SkinRegionLocator.skinMask(
            faces: [frontal, profile], personMatte: nil,
            width: size, height: size, config: config)
        XCTAssertEqual(warnings.count, 1)
        guard case let .faceExcludedHighYaw(index, yaw, limit) = warnings[0] else {
            return XCTFail("expected faceExcludedHighYaw, got \(warnings[0])")
        }
        XCTAssertEqual(index, 1, "the second (profile) face is the gated one")
        XCTAssertEqual(yaw, 60, accuracy: 1e-9)
        XCTAssertEqual(limit, 45, accuracy: 1e-9)
        // The frontal's cheek is still skin; the profile's center is NOT.
        XCTAssertEqual(sample(plane.floats, x: 0.26, y: 0.58), 1)
        XCTAssertEqual(sample(plane.floats, x: 0.66, y: 0.58), 0, "gated face contributes nothing")

        // All faces gated ⇒ typed error (never a silently degraded mask).
        XCTAssertThrowsError(
            try SkinRegionLocator.skinMask(
                faces: [profile], personMatte: nil,
                width: size, height: size, config: config)
        ) { error in
            guard case SkinRegionError.noUsableFace(let gated) = error else {
                return XCTFail("expected noUsableFace, got \(error)")
            }
            XCTAssertEqual(gated, 1)
        }

        // At the limit exactly (45°) the face is still USED (strictly-greater gate).
        let atLimit = synthFace(
            center: SIMD2(x: 0.5, y: 0.5), faceWidth: 0.3, faceHeight: 0.4, yaw: 45)
        let (atPlane, atWarnings) = try SkinRegionLocator.skinMask(
            faces: [atLimit], personMatte: nil, width: size, height: size, config: config)
        XCTAssertEqual(atWarnings.count, 0)
        XCTAssertEqual(sample(atPlane.floats, x: 0.41, y: 0.58), 1)
    }

    // MARK: - Case 3: multi-face union

    func testMultiFaceUnion() throws {
        let a = synthFace(center: SIMD2(x: 0.28, y: 0.5), faceWidth: 0.26, faceHeight: 0.34)
        let b = synthFace(center: SIMD2(x: 0.72, y: 0.5), faceWidth: 0.26, faceHeight: 0.34)
        let (plane, _) = try SkinRegionLocator.skinMask(
            faces: [a, b], personMatte: nil, width: size, height: size, config: config)
        XCTAssertEqual(sample(plane.floats, x: 0.20, y: 0.55), 1, "face A's cheek")
        XCTAssertEqual(sample(plane.floats, x: 0.80, y: 0.55), 1, "face B's cheek")
        XCTAssertEqual(sample(plane.floats, x: 0.5, y: 0.5), 0, "the gap between faces")
    }

    // MARK: - Case 4: empty-landmark degradation legs

    func testEmptyLandmarksAndNoFacesTypedErrors() {
        XCTAssertThrowsError(
            try SkinRegionLocator.skinMask(
                faces: [], personMatte: nil, width: size, height: size, config: config)
        ) { error in
            guard case SkinRegionError.noFaces = error else {
                return XCTFail("expected noFaces, got \(error)")
            }
        }
        let stub = FaceLandmarkSet(
            faceContour: [SIMD2(x: 0.4, y: 0.4), SIMD2(x: 0.6, y: 0.4)], // 2 points < 3
            leftEye: [], rightEye: [], leftEyebrow: [], rightEyebrow: [],
            outerLips: [], nostrils: [])
        XCTAssertThrowsError(
            try SkinRegionLocator.skinMask(
                faces: [stub], personMatte: nil, width: size, height: size, config: config)
        ) { error in
            guard case SkinRegionError.emptyLandmarks = error else {
                return XCTFail("expected emptyLandmarks, got \(error)")
            }
        }
    }

    // MARK: - ⊗ person matte (with resample)

    func testPersonMatteIntersectionWithResample() throws {
        let face = synthFace(
            center: SIMD2(x: 0.5, y: 0.5), faceWidth: 0.4, faceHeight: 0.5)
        // A HALF person matte at a DIFFERENT (smaller) resolution: the left
        // half of the frame is person (1), the right half is not (0).
        let mw = 67, mh = 53
        var floats = [Float](repeating: 0, count: mw * mh)
        for y in 0..<mh {
            for x in 0..<mw where x < mw / 2 {
                floats[y * mw + x] = 1
            }
        }
        let matte = AIMaskPlane(width: mw, height: mh, floats: floats)

        let (plane, _) = try SkinRegionLocator.skinMask(
            faces: [face], personMatte: matte, width: size, height: size, config: config)
        XCTAssertEqual(sample(plane.floats, x: 0.34, y: 0.52), 1, "left cheek = face ∧ person")
        XCTAssertEqual(
            sample(plane.floats, x: 0.66, y: 0.52), 0,
            "right cheek ⊓ ¬person = 0 despite being inside the hull")
    }

    // MARK: - Coordinate conversion (VNImagePointForFaceLandmarkPoint-equiv)

    func testLandmarkCoordinateConversion() throws {
        // faceBox (x, y, w, h) in Vision's LOWER-LEFT normalized space.
        let faceBox = SIMD4<Double>(0.3, 0.2, 0.4, 0.5)
        let regionCenter = SIMD2<Double>(x: 0.5, y: 0.5)
        let converted = FaceLandmarkSet.convert([regionCenter], faceBox: faceBox)
        // x = 0.3 + 0.5·0.4 = 0.5; y = 1 − (0.2 + 0.5·0.5) = 0.55.
        XCTAssertEqual(converted[0].x, 0.5, accuracy: 1e-12)
        XCTAssertEqual(converted[0].y, 0.55, accuracy: 1e-12)

        // Region origin (Vision's lower-left of the face box) → the
        // TOP-LEFT of the face box in image space.
        let origin = FaceLandmarkSet.convert([SIMD2<Double>(x: 0, y: 0)], faceBox: faceBox)
        XCTAssertEqual(origin[0].x, 0.3, accuracy: 1e-12)
        XCTAssertEqual(origin[0].y, 1.0 - 0.2, accuracy: 1e-12)

        // The boxed init runs the same math + guards degenerate contours.
        XCTAssertThrowsError(
            try FaceLandmarkSet(
                faceBox: faceBox, contour: [SIMD2(x: 0, y: 0), SIMD2(x: 1, y: 1)],
                leftEye: [], rightEye: [], leftEyebrow: [], rightEyebrow: [],
                outerLips: [], nostrils: [], yawDegrees: nil)
        ) { error in
            guard case SkinRegionError.emptyLandmarks = error else {
                return XCTFail("expected emptyLandmarks, got \(error)")
            }
        }
        let boxed = try FaceLandmarkSet(
            faceBox: faceBox,
            contour: [regionCenter, SIMD2(x: 1, y: 1), SIMD2(x: 0, y: 1)],
            leftEye: [], rightEye: [], leftEyebrow: [], rightEyebrow: [],
            outerLips: [], nostrils: [], yawDegrees: 12)
        XCTAssertEqual(boxed.faceContour[0].y, 0.55, accuracy: 1e-12)
        XCTAssertEqual(boxed.yawDegrees ?? -1, 12)
    }

    // MARK: - Geometry primitives (hull / point-in-polygon pins)

    func testConvexHullAndPointInPolygon() {
        let square = [
            SIMD2(x: 0.0, y: 0.0), SIMD2(x: 1.0, y: 0.0),
            SIMD2(x: 1.0, y: 1.0), SIMD2(x: 0.0, y: 1.0),
        ]
        let interior = square + [SIMD2(x: 0.5, y: 0.45)]
        let hull = SkinGeometry.convexHull(interior)
        XCTAssertEqual(hull.count, 4, "interior point expelled from the hull")
        XCTAssertTrue(SkinGeometry.pointInPolygon(SIMD2(x: 0.5, y: 0.5), hull))
        XCTAssertFalse(SkinGeometry.pointInPolygon(SIMD2(x: 1.5, y: 0.5), hull))

        // scaleAbout keeps convexity and the centroid fixed.
        let center = SkinGeometry.centroid(hull)
        let shrunk = SkinGeometry.scaleAbout(hull, center: center, factor: 0.5)
        XCTAssertFalse(
            SkinGeometry.pointInPolygon(SIMD2(x: 0.99, y: 0.5), shrunk),
            "a corner point leaves the shrunk hull")
        XCTAssertTrue(SkinGeometry.pointInPolygon(SIMD2(x: 0.5, y: 0.5), shrunk))
        XCTAssertEqual(SkinGeometry.centroid(shrunk).x, center.x, accuracy: 1e-12)
    }

    // MARK: - Real-model leg (directional; skip-with-reason on host limits)

    /// Draw a simple cartoon face (skin oval + dark eyes + mouth) and run
    /// the REAL `VisionFaceLandmarkProvider`. Directional assertions only
    /// (07-RESEARCH §6): a face IS detected and its converted landmarks
    /// land inside the drawn oval's bbox tolerance. Skips when the test
    /// host cannot run Vision inference (07-1 layer-B entitlement
    /// precedent — the 07-3 GUI round re-verifies end-to-end).
    func testVisionProviderOnSynthesizedFaceDrawing() async throws {
        let w = 512, h = 512
        // Draw the face oval + features into a CGContext-backed CIImage.
        let cg = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func fillRect(_ rect: CGRect, _ color: (CGFloat, CGFloat, CGFloat)) {
            cg.setFillColor(CGColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1))
            cg.fill(rect)
        }
        let wf = CGFloat(w)
        let hf = CGFloat(h)
        fillRect(CGRect(x: 0, y: 0, width: w, height: h), (0.06, 0.06, 0.08))
        cg.setFillColor(CGColor(srgbRed: 0.78, green: 0.60, blue: 0.48, alpha: 1)) // skin tone
        cg.fillEllipse(in: CGRect(x: wf * 0.28, y: hf * 0.10, width: wf * 0.44, height: hf * 0.68))
        let dark = CGColor(srgbRed: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        cg.setFillColor(dark)
        let eyeY = hf * 0.56
        let eyeW = wf * 0.07
        let eyeH = hf * 0.05
        cg.fillEllipse(in: CGRect(x: wf * 0.37, y: eyeY, width: eyeW, height: eyeH)) // L eye
        cg.fillEllipse(in: CGRect(x: wf * 0.56, y: eyeY, width: eyeW, height: eyeH)) // R eye
        cg.fillEllipse(in: CGRect(x: wf * 0.44, y: hf * 0.24, width: wf * 0.12, height: hf * 0.04)) // mouth
        guard let cgImage = cg.makeImage() else {
            throw XCTSkip("face drawing failed")
        }
        let input = AIMaskInput(ciImage: CIImage(cgImage: cgImage))

        let provider = VisionFaceLandmarkProvider()
        let faces: [FaceLandmarkSet]
        do {
            faces = try await provider.detectFaces(input: input, device: .anePreferred)
        } catch let error as AIMaskError {
            throw XCTSkip("Vision inference unavailable on this host: \(error)")
        }
        guard !faces.isEmpty else {
            throw XCTSkip("no face detected in the cartoon drawing (host Vision state)")
        }
        // Directional: the (converted, top-left) contour centroid sits in
        // the drawn oval's central area (bbox tolerance — not exact).
        for face in faces {
            let centroid = SkinGeometry.centroid(face.faceContour)
            XCTAssertEqual(centroid.x, 0.5, accuracy: 0.15, "contour centroid near the oval's x")
            XCTAssertEqual(centroid.y, 0.5, accuracy: 0.2, "contour centroid near the oval's y")
        }
        // And the full locator chain runs on the real payload.
        let (plane, _) = try SkinRegionLocator.skinMask(
            faces: faces, personMatte: nil, width: 128, height: 128, config: SkinRegionConfig())
        let ones = plane.floats.filter { $0 > 0.5 }.count
        XCTAssertGreaterThan(ones, 0, "the real-payload mask is non-empty")
        XCTAssertLessThan(ones, 128 * 128, "and not everything")
    }
}

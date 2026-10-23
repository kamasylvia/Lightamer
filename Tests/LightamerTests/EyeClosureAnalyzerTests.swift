import CoreGraphics
import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// EyeClosureAnalyzerTests (Plan LUMEN-A T4) — the eye-opening math + the
// injected-provider analysis face. ZERO Vision imports: the request factory
// seam (`FaceLandmarkProviding`) is what makes the CI face model-free — the
// synthetic provider weaves landmark faces and the tests pin the RATIO MATH,
// the max(right,left) verdict semantics, the 3% face gate and the threshold
// injection (D-LU-4: the 0.16 default is a semantic initial value, injectable
// everywhere).
// ─────────────────────────────────────────────────────────────────────────────

final class EyeClosureAnalyzerTests: XCTestCase {

    // MARK: - Synthetic landmark weaving

    /// An 8-point eye contour in image-normalized coords: corners at
    /// (x, cy) ± width; three upper-lid points at cy - span/2, three
    /// lower-lid points at cy + span/2 — every lid pair distances exactly
    /// `span`, the corner width is `width` → the opening ratio = span/width.
    private func eyeContour(
        x: CGFloat, cy: CGFloat, width: CGFloat, span: CGFloat
    ) -> [CGPoint] {
        [
            CGPoint(x: x, y: cy),
            CGPoint(x: x + width * 0.25, y: cy - span / 2),
            CGPoint(x: x + width * 0.5, y: cy - span / 2),
            CGPoint(x: x + width * 0.75, y: cy - span / 2),
            CGPoint(x: x + width, y: cy),
            CGPoint(x: x + width * 0.75, y: cy + span / 2),
            CGPoint(x: x + width * 0.5, y: cy + span / 2),
            CGPoint(x: x + width * 0.25, y: cy + span / 2),
        ]
    }

    private func makeCGImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    /// The synthetic provider: returns the woven faces verbatim.
    private final class SyntheticProvider: FaceLandmarkProviding {
        let faces: [FaceLandmarkFace]
        init(faces: [FaceLandmarkFace]) { self.faces = faces }
        func detectFaces(image: CGImage) throws -> [FaceLandmarkFace] {
            faces
        }
    }

    private func face(
        box: CGRect, rightRatio: Double, leftRatio: Double
    ) -> FaceLandmarkFace {
        // Eyes sit inside the box's upper half; the eye width is 0.2 of the
        // box width and the lid spans encode the WANTED RATIO exactly
        // (ratio = span / eyeWidth by the weaver's construction).
        let eyeWidth = box.width * 0.2
        let rightEye = eyeContour(
            x: box.minX + box.width * 0.2, cy: box.minY + box.height * 0.35,
            width: eyeWidth, span: CGFloat(rightRatio * Double(eyeWidth)))
        let leftEye = eyeContour(
            x: box.minX + box.width * 0.6, cy: box.minY + box.height * 0.35,
            width: eyeWidth, span: CGFloat(leftRatio * Double(eyeWidth)))
        return FaceLandmarkFace(
            boundingBox: box, rightEye: rightEye, leftEye: leftEye)
    }

    // MARK: - ① The ratio math (table-driven)

    func testOpeningRatioMathTableDriven() throws {
        let width: CGFloat = 100
        // span/width pairs — the ratio IS span/width by construction.
        let cases: [(span: CGFloat, expected: Double)] = [
            (40, 0.4),   // open
            (16, 0.16),  // at the semantic threshold
            (8, 0.08),   // closed
        ]
        for row in cases {
            let ratio = try XCTUnwrap(EyeOpeningMath.openingRatio(
                eyeContour(x: 10, cy: 50, width: width, span: row.span)))
            XCTAssertEqual(
                ratio, row.expected, accuracy: 0.02,
                "span \(row.span) must read \(row.expected)")
        }
        // Degenerate contours → nil.
        XCTAssertNil(EyeOpeningMath.openingRatio([]))
        XCTAssertNil(EyeOpeningMath.openingRatio([
            CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 1), CGPoint(x: 3, y: 1),
        ]))
        // Zero-width (all points on one vertical) → nil.
        XCTAssertNil(EyeOpeningMath.openingRatio([
            CGPoint(x: 5, y: 1), CGPoint(x: 5, y: 2), CGPoint(x: 5, y: 3),
            CGPoint(x: 5, y: 4),
        ]))
    }

    // MARK: - ② max(right, left) verdict + threshold injection

    func testClosedVerdictMaxOfBothEyesAndThresholdInjection() {
        let image = makeCGImage(width: 1000, height: 1000)
        let box = CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3)

        // One wide-open eye keeps the face OUT of the closed bucket
        // (Lumen's wider-open-eye rule — max(right, left)).
        let winking = EyeClosureAnalyzer.analyze(
            image: image,
            provider: SyntheticProvider(faces: [
                face(box: box, rightRatio: 0.4, leftRatio: 0.08)
            ]))
        XCTAssertEqual(winking.faces.count, 1)
        XCTAssertFalse(winking.faces[0].closed)
        XCTAssertEqual(winking.closedCount, 0)
        XCTAssertEqual(winking.faces[0].ratioRight ?? 0, 0.4, accuracy: 0.02)
        XCTAssertEqual(winking.faces[0].ratioLeft ?? 0, 0.08, accuracy: 0.02)

        // Both eyes under the threshold → closed.
        let asleep = EyeClosureAnalyzer.analyze(
            image: image,
            provider: SyntheticProvider(faces: [
                face(box: box, rightRatio: 0.08, leftRatio: 0.10)
            ]))
        XCTAssertTrue(asleep.faces[0].closed)
        XCTAssertEqual(asleep.closedCount, 1)

        // Threshold injection: 0.5 makes the winking face read closed (the
        // 0.16 default is a semantic initial value, never load-bearing).
        let strict = EyeClosureAnalyzer.analyze(
            image: image,
            provider: SyntheticProvider(faces: [
                face(box: box, rightRatio: 0.4, leftRatio: 0.08)
            ]),
            closedThreshold: 0.5)
        XCTAssertTrue(strict.faces[0].closed)

        // Both-eye ratios absent (empty/collinear contours → nil) →
        // widerOpen nil → NOT closed (the hint arm never fires on absent data).
        let noLandmarks = FaceLandmarkFace(
            boundingBox: box, rightEye: [
                CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.4, y: 0.3),
                CGPoint(x: 0.5, y: 0.3), CGPoint(x: 0.6, y: 0.3),
            ], leftEye: [])
        let blind = EyeClosureAnalyzer.analyze(
            image: image, provider: SyntheticProvider(faces: [noLandmarks]))
        XCTAssertFalse(blind.faces[0].closed)
        XCTAssertNil(blind.faces[0].maxRatio)
    }

    // MARK: - ③ The 3% face gate + empty/no-face faces

    func testFaceGateAndNoFaceResult() {
        let image = makeCGImage(width: 1000, height: 1000)
        let bigBox = CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4)
        let tinyBox = CGRect(x: 0.8, y: 0.8, width: 0.02, height: 0.02)

        let result = EyeClosureAnalyzer.analyze(
            image: image,
            provider: SyntheticProvider(faces: [
                face(box: bigBox, rightRatio: 0.4, leftRatio: 0.4),
                face(box: tinyBox, rightRatio: 0.4, leftRatio: 0.4),
            ]))
        // The 2% face falls under Lumen MIN_FACE=.03 — only the big one counts.
        XCTAssertEqual(result.faces.count, 1)
        XCTAssertEqual(result.faces[0].box, bigBox)
        XCTAssertFalse(result.faces[0].closed)

        // No faces at all → an empty (never-crashing) result.
        let empty = EyeClosureAnalyzer.analyze(
            image: image, provider: SyntheticProvider(faces: []))
        XCTAssertTrue(empty.faces.isEmpty)
        XCTAssertEqual(empty.closedCount, 0)

        // A throwing provider degrades to the honest empty result (the
        // analysis pass logs-and-continues; never a crash face).
        struct ThrowingProvider: FaceLandmarkProviding {
            func detectFaces(image: CGImage) throws -> [FaceLandmarkFace] {
                throw NSError(domain: "probe", code: 1)
            }
        }
        let degraded = EyeClosureAnalyzer.analyze(
            image: image, provider: ThrowingProvider())
        XCTAssertTrue(degraded.faces.isEmpty)
    }
}

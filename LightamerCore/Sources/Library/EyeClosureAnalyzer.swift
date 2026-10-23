import CoreGraphics
import Foundation
import Vision

// ─────────────────────────────────────────────────────────────────────────────
// EyeClosureAnalyzer (Plan LUMEN-A T4, X3/D-LU-4) — the face/eye-opening
// analysis behind the culling pass.
//
// ATTRIBUTION (NOTICE entry Q, Lumen RAW): the eye-opening RATIO idea and
// the CLOSED threshold semantics derive from LUMEN RAW
// (https://github.com/LeisureLinux/lumen, MIT License, Copyright (c) 2026
// LUMEN RAW contributors, `lumen/culling.py` Faces.opening / CLOSED=.16).
// The landmark vocabulary is ours: Apple Vision's VNDetectFaceLandmarksRequest
// 76-point model replaces Lumen's MediaPipe 478-point mesh — the 0.16 number
// is a SEMANTIC INITIAL VALUE, not a portable calibration (D-LU-4: the
// absolute hint arm awaits our own 10-20-shot calibration set; the best-of-
// burst arm consumes the raw ratios threshold-free, so nothing load-bearing
// depends on the initial value).
//
// Pipeline (the CullingToolset.swift:1281 Vision precedent, zero-touch):
// VNDetectFaceRectanglesRequest on a ≤1280px view (Lumen DETECT_EDGE, zero
// download — Vision ships the detector) → per-face
// VNDetectFaceLandmarksRequest → per-eye opening ratio = mean of the
// upper/lower lid pair distances over the corner-to-corner width (Lumen
// `opening()`: pairs distance / max(width, 1e-6)) → closed when
// max(right, left) < threshold.
//
// TESTABILITY SEAM: `FaceLandmarkProviding` is the injected factory — the
// production face is `VisionEyeLandmarkProvider` (real Vision); tests weave
// synthetic landmark faces and NEVER touch Vision (the CI face pins the
// ratio MATH, not the model). The request factory must stay in this file —
// no other LightamerCore file may grow a Vision face-analysis dependency.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Provider seam (the injected request factory)

/// One detected face with its per-eye landmark point sets, normalized to
/// the IMAGE (0-1, top-left origin — the Vision bottom-left convention is
/// flipped here, once, at the provider boundary).
public struct FaceLandmarkFace: Sendable, Equatable {
    public let boundingBox: CGRect
    public let rightEye: [CGPoint]
    public let leftEye: [CGPoint]

    public init(boundingBox: CGRect, rightEye: [CGPoint], leftEye: [CGPoint]) {
        self.boundingBox = boundingBox
        self.rightEye = rightEye
        self.leftEye = leftEye
    }
}

/// The injected request factory (see the file header). Async because the
/// Vision requests are synchronous-per-call under the hood but the analyzer
/// runs on the analysis actor's lane.
public protocol FaceLandmarkProviding: Sendable {
    func detectFaces(image: CGImage) throws -> [FaceLandmarkFace]
}

/// The production face: real Vision requests (macOS 10.13+ rectangles,
/// 76-point landmarks). Detection rides a ≤1280px view (Lumen DETECT_EDGE);
/// landmarks run per detected face on the same view.
public struct VisionEyeLandmarkProvider: FaceLandmarkProviding {

    /// Long edge faces are detected on (Lumen `DETECT_EDGE`).
    public static let detectEdge = 1280

    public init() {}

    public func detectFaces(image: CGImage) throws -> [FaceLandmarkFace] {
        let width = image.width
        let height = image.height
        let longEdge = max(width, height)
        let scale = Double(VisionEyeLandmarkProvider.detectEdge) / Double(longEdge)
        let view: CGImage
        if scale < 1 {
            let newW = max(1, Int((Double(width) * scale).rounded()))
            let newH = max(1, Int((Double(height) * scale).rounded()))
            guard let resized = image.resized(toWidth: newW, toHeight: newH) else {
                return []
            }
            view = resized
        } else {
            view = image
        }

        // ① Face rectangles.
        let rectRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: view, options: [:])
        try handler.perform([rectRequest])
        let observations = rectRequest.results ?? []

        // ② Per-face landmarks (the landmark regions are normalized to the
        // FACE BOX; the conversion to image space happens below, with the
        // top-left flip applied exactly once).
        var faces: [FaceLandmarkFace] = []
        for observation in observations {
            let landmarkRequest = VNDetectFaceLandmarksRequest()
            landmarkRequest.inputFaceObservations = [observation]
            let landmarkHandler = VNImageRequestHandler(cgImage: view, options: [:])
            try? landmarkHandler.perform([landmarkRequest])
            guard let landmarks = landmarkRequest.results?.first?.landmarks else {
                continue
            }
            // Vision box: normalized, BOTTOM-left origin → flip to top-left.
            let visionBox = observation.boundingBox
            let box = CGRect(
                x: visionBox.origin.x,
                y: 1 - visionBox.origin.y - visionBox.height,
                width: visionBox.width,
                height: visionBox.height)

            func imagePoints(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
                guard let region else { return [] }
                return (0..<region.pointCount).map { index in
                    let p = region.normalizedPoints[index]
                    return CGPoint(
                        x: box.origin.x + p.x * box.width,
                        y: box.origin.y + (1 - p.y) * box.height)
                }
            }
            faces.append(FaceLandmarkFace(
                boundingBox: box,
                rightEye: imagePoints(landmarks.rightEye),
                leftEye: imagePoints(landmarks.leftEye)))
        }
        return faces
    }
}

extension CGImage {
    /// Nearest-friendly downscale for the detection view (the provider's
    /// ≤1280 leg; the analyzer math is resolution-independent).
    func resized(toWidth newW: Int, toHeight newH: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(self, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return context.makeImage()
    }
}

// MARK: - The ratio math (the CI-pinned face)

public enum EyeOpeningMath {

    /// Eye-opening ratio of one eye's contour points (image-normalized):
    /// corners = the leftmost/rightmost points; the corner line splits the
    /// remaining points into upper/lower lids; lid pairs match in x-order;
    /// ratio = mean pair distance / max(corner width, 1e-6) — Lumen
    /// `opening()`'s shape over Vision's sparser vocabulary. nil when the
    /// contour is degenerate (< 4 points or zero-width).
    public static func openingRatio(_ points: [CGPoint]) -> Double? {
        guard points.count >= 4 else { return nil }
        guard let outer = points.min(by: { $0.x < $1.x }),
              let inner = points.max(by: { $0.x < $1.x }) else { return nil }
        let width = hypot(
            Double(inner.x - outer.x), Double(inner.y - outer.y))
        guard width > 1e-6 else { return nil }
        let dx = Double(inner.x - outer.x)
        let dy = Double(inner.y - outer.y)
        func side(_ p: CGPoint) -> Double {
            dx * (Double(p.y) - Double(outer.y))
                - dy * (Double(p.x) - Double(outer.x))
        }
        var upper = points.filter { side($0) < 0 }
        var lower = points.filter { side($0) > 0 }
        guard !upper.isEmpty, !lower.isEmpty else { return nil }
        upper.sort { $0.x < $1.x }
        lower.sort { $0.x < $1.x }
        var spanSum = 0.0
        var count = 0.0
        for pair in zip(upper, lower) {
            spanSum += hypot(
                Double(pair.0.x - pair.1.x), Double(pair.0.y - pair.1.y))
            count += 1
        }
        return spanSum / count / max(width, 1e-6)
    }
}

// MARK: - The analyzer

/// The per-image analysis product (T5 persists: faces count → `faces`,
/// closed count → `eyes_closed`, the boxes+ratios → `face_boxes` JSON).
public struct EyeClosureResult: Sendable, Equatable {

    public struct Face: Sendable, Equatable {
        /// Normalized 0-1, top-left origin.
        public let box: CGRect
        public let ratioRight: Double?
        public let ratioLeft: Double?
        /// max(right, left) < threshold (Lumen's wider-open-eye rule —
        /// one open eye keeps the face out of the closed bucket).
        public let closed: Bool

        public init(
            box: CGRect, ratioRight: Double?, ratioLeft: Double?, closed: Bool
        ) {
            self.box = box
            self.ratioRight = ratioRight
            self.ratioLeft = ratioLeft
            self.closed = closed
        }

        /// The wider-open eye's ratio (T6's threshold-free best-sort key;
        /// nil = no landmark on either eye).
        public var maxRatio: Double? {
            switch (ratioRight, ratioLeft) {
            case let (.some(r), .some(l)): return max(r, l)
            case let (.some(r), .none): return r
            case let (.none, .some(l)): return l
            default: return nil
            }
        }
    }

    public let faces: [Face]

    public var closedCount: Int { faces.filter(\.closed).count }

    public init(faces: [Face]) {
        self.faces = faces
    }
}

public enum EyeClosureAnalyzer {

    /// The CLOSED semantic initial value (Lumen `CLOSED=.16` — NOT a
    /// portable calibration; the threshold is injectable and the calibration
    /// set may re-issue the constant, D-LU-4). The single source for the
    /// default across the analysis pass and any hint copy.
    public static let defaultClosedThreshold = 0.16

    /// Faces smaller than this share of the image LONG EDGE are not
    /// counted (Lumen `MIN_FACE=.03`).
    public static let minimumFaceFraction = 0.03

    /// Analyze one view through the INJECTED provider. The 3% gate filters
    /// sub-threshold faces; ratio math via `EyeOpeningMath`; the closed
    /// verdict rides max(right, left) against the injected threshold.
    public static func analyze(
        image: CGImage,
        provider: FaceLandmarkProviding,
        closedThreshold: Double = EyeClosureAnalyzer.defaultClosedThreshold,
        minimumFaceFraction: Double = EyeClosureAnalyzer.minimumFaceFraction
    ) -> EyeClosureResult {
        guard let detected = try? provider.detectFaces(image: image) else {
            return EyeClosureResult(faces: [])
        }
        let longEdge = Double(max(image.width, image.height))
        let smallestFace = minimumFaceFraction * longEdge
        var faces: [EyeClosureResult.Face] = []
        for face in detected {
            let facePixelLong = max(
                face.boundingBox.width * Double(image.width),
                face.boundingBox.height * Double(image.height))
            guard facePixelLong >= smallestFace else { continue }
            let right = EyeOpeningMath.openingRatio(face.rightEye)
            let left = EyeOpeningMath.openingRatio(face.leftEye)
            let widerOpen: Double?
            switch (right, left) {
            case let (.some(r), .some(l)): widerOpen = max(r, l)
            case let (.some(r), .none): widerOpen = r
            case let (.none, .some(l)): widerOpen = l
            default: widerOpen = nil
            }
            let closed = (widerOpen ?? 1) < closedThreshold
            faces.append(EyeClosureResult.Face(
                box: face.boundingBox, ratioRight: right,
                ratioLeft: left, closed: closed))
        }
        return EyeClosureResult(faces: faces)
    }
}

import CoreGraphics
import CoreImage
import Foundation
import LightamerCore
import Vision

// ─────────────────────────────────────────────────────────────────────────
// VisionDetect — horizon + rectangle auto-detect (Plan 04-03-T3,
// IOP-GEO-02). Apple-native, zero dependencies (D-G1 Vision tendency).
//
// Apple reference: `VNDetectHorizonRequest` / `VNHorizonObservation`
// (angle/transform) + `VNDetectRectanglesRequest` /
// `VNRectangleObservation` (normalized corners + confidence), macOS 10.13+.
//
// SIGN CONVENTIONS (04-RESEARCH Risk #6 — probe-pinned, never doc-guessed;
// VisionDetectTests nails all three):
//  - `detectHorizonAngleDegrees` returns CLOCKWISE-positive degrees in the
//    CG image frame (y-down): a horizon line tilted `/` (rises rightward)
//    reports NEGATIVE. Feeding `rotation = −angle` into AshiftParams
//    straightens it (dt's rotation is counter-clockwise-positive in the
//    math frame; the flip through the y-down CG frame negates the sign).
//  - `detectRectangle` returns corners in the CG frame (origin top-left,
//    y-down): (topLeft, topRight, bottomRight, bottomLeft). The DLT caller
//    (Homography.fitParams via `rectangleCorrespondences`) must pair them
//    against source corners in the SAME y-down order — do not pre-flip.
// ─────────────────────────────────────────────────────────────────────────

/// Horizon + rectangle detection over a `CGImage` (the caller renders a
/// small probe — `decoded.ciImage` scaled, zero pipe-plane readback).
enum VisionDetect {

    /// Clockwise-positive horizon tilt in degrees, CG frame (y-down).
    /// nil = no horizon found (caller toasts, leaves params untouched).
    static func detectHorizonAngleDegrees(in image: CGImage) throws -> Double? {
        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let obs = request.results?.first as? VNHorizonObservation else {
            return nil
        }
        return obs.angle * 180.0 / Double.pi
    }

    /// The highest-confidence rectangle's four corners (CG frame,
    /// normalized 0…1): (topLeft, topRight, bottomRight, bottomLeft).
    /// nil = no rectangle above `minimumConfidence`.
    static func detectRectangle(
        in image: CGImage,
        minimumConfidence: Float = 0.5,
        maximumObservations: Int = 5
    ) throws -> (topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint)? {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = VNConfidence(minimumConfidence)
        request.maximumObservations = maximumObservations
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let obs = (request.results as? [VNRectangleObservation])?.first else {
            return nil
        }
        return (obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft)
    }
}

/// Public facade (plan Artifacts access note): the App panel calls these —
/// `VisionDetect` itself stays internal to LightamerIOP.
public enum AshiftAutoDetect {

    /// Render a small probe of the source image and detect the horizon
    /// tilt (clockwise-positive CG degrees). nil = nothing found.
    /// `ciImage` should be the DECODED source (zero pipe-plane readback).
    public static func horizonAngleDegrees(ciImage: CIImage, maxDimension: CGFloat = 512) -> Double? {
        guard let cg = probeCGImage(ciImage: ciImage, maxDimension: maxDimension) else {
            return nil
        }
        return try? VisionDetect.detectHorizonAngleDegrees(in: cg)
    }

    /// The rotation correction (AshiftParams.rotation degrees,
    /// counter-clockwise-positive math frame) that straightens a detected
    /// horizon tilt: negate the clockwise-positive CG angle.
    public static func rotationCorrection(forHorizonAngleDegrees angle: Double) -> Double {
        -angle
    }

    /// Render a small probe and detect the dominant rectangle (CG
    /// normalized corners). nil = nothing above confidence.
    public static func rectangleCorners(
        ciImage: CIImage,
        maxDimension: CGFloat = 512,
        minimumConfidence: Float = 0.5
    ) -> (topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint)? {
        guard let cg = probeCGImage(ciImage: ciImage, maxDimension: maxDimension) else {
            return nil
        }
        return try? VisionDetect.detectRectangle(in: cg, minimumConfidence: minimumConfidence)
    }

    /// Smallest-side probe render (CI lazy — no full-frame buffer).
    static func probeCGImage(ciImage: CIImage, maxDimension: CGFloat) -> CGImage? {
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let scale = min(1.0, maxDimension / max(extent.width, extent.height))
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: [.workingColorSpace: WorkingSpace.colorSpace])
        return context.createCGImage(scaled, from: scaled.extent)
    }
}

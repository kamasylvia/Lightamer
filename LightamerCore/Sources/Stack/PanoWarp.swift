import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// PanoWarp (Plan M5-3-02 T1; KD-2/KD-3/KD-4) — the panorama projection
// segment: the spherical map pure function, the preview→full-resolution K
// back-projection (the matrices = inv(preview_scale) @ K shape), the global
// projection scale (the median focal anchor), and the bounded-canvas shrink
// loop with the 200 MP cap. Pure CPU, stateless, deterministic (G3's anchor).
//
// MIT ATTRIBUTION (CONVENTIONS 参考项目节): Portions derived from Lumen RAW
// (lumen-raw, MIT) — the PROJECTION-SEGMENT STRUCTURE: `sphericalMap` is a
// literal transcription of `spherical_map` (merge.py:205-211, the z > 1e-6
// validity branch and the −1 invalid marker included), the bounded-canvas
// shrink loop of `bounded_rois` (merge.py:192-202, ≤8 rounds × the
// sqrt(cap/area)·0.998 equal-ratio contraction), and the 200 MP canvas cap
// (`PANORAMA_MAX_PIXELS = 200_000_000`, merge.py:12 — the same-value
// constant). Swift rewrite; OpenCV `PyRotationWarper` semantics are read-only
// reference (the ROI = the projected source border's bounding box), code
// zero-copied.
//
// CONVENTIONS (KD-2/KD-3, the self-consistent frame):
//   • Canvas pixel (x, y) ↔ sphere angles u = (x + x0)/scale,
//     v = (y + y0)/scale; the world ray is
//     (sin v·sin u, −cos v, sin v·cos u) — the Lumen row form verbatim.
//   • Rotations are WORLD→CAMERA (the PanoCamera convention: cam = R·world),
//     so the backward map is px = f·(R·ray).x/(R·ray).z + centerX.
//   • K = diag(f, f, 1) with the principal point folded into the coordinate
//     centering — the pixel coordinates are centered on ((w−1)/2, (h−1)/2),
//     the frame midline (the PanoCamera coordinate contract, D-4).
//   • The camera segment estimates the focal in PREVIEW pixels; the leg
//     back-projects per source: f_full = f_preview · fullW/previewW — the
//     `inv(preview_scale) @ K()` product (with K diagonal, the matrix
//     product reduces to the focal rescale; the principal point rides the
//     centering, which is size-relative and needs no rescale).
//   • PRECISION: the per-pixel map computes in Double and stores Float32
//     (the Lumen map's actual path — its f32 `arange` promotes against the
//     f64 rect/scale and only the RETURN is `astype(np.float32)`; the G3①
//     point-wise comparison's precision premise, L048). The ROI bounding
//     walk projects in Double throughout (few points, bounds headroom).
// ─────────────────────────────────────────────────────────────────────────────

/// One source image's projection geometry (the full-resolution facts).
public struct PanoSourceGeometry: Sendable {
    /// The full-resolution pixel size.
    public let width: Int
    public let height: Int
    /// The focal in FULL-RESOLUTION pixels (the preview estimate rescaled —
    /// see the header's back-projection note).
    public let focal: Double
    /// The world→camera rotation (the PanoCameraSolution convention).
    public let rotation: Mat3D

    public init(width: Int, height: Int, focal: Double, rotation: Mat3D) {
        self.width = width
        self.height = height
        self.focal = focal
        self.rotation = rotation
    }
}

/// One source's warped footprint on the canvas (integer bounds, conservative:
/// floor/ceil so the tile loop's ROI intersect can only over-cover).
public struct PanoROI: Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// The resolved canvas plan (the bounded_rois return shape).
public struct PanoCanvasPlan: Sendable {
    /// Per-source ROIs in the ANGLE·scale frame (possibly negative — the
    /// bounds origin shifts them into the canvas frame).
    public let rois: [PanoROI]
    /// The union bounds origin (the canvas frame's (0, 0) anchor).
    public let originX: Int
    public let originY: Int
    /// The canvas size in pixels (≤ `maxCanvasPixels` by construction).
    public let width: Int
    public let height: Int
    /// The accepted projection scale (possibly shrunk by the loop).
    public let scale: Double

    public init(
        rois: [PanoROI], originX: Int, originY: Int,
        width: Int, height: Int, scale: Double
    ) {
        self.rois = rois
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
        self.scale = scale
    }
}

public enum PanoWarp {

    // MARK: - Constants (KD-4: file constants, NOT parameters)

    /// The output canvas cap (merge.py:12 `PANORAMA_MAX_PIXELS` — the same
    /// value; Lumen's constant transplanted verbatim).
    public static let maxCanvasPixels = 200_000_000
    /// The shrink-loop round budget (merge.py:192-202 `for _ in range(8)`).
    public static let maxShrinkRounds = 8
    /// The per-round contraction safety (merge.py:201 `* .998` — never
    /// oscillating exactly on the cap boundary).
    public static let shrinkSafety = 0.998
    /// The backward map's z validity floor (merge.py:205-211 `z > 1e-6`).
    public static let zEpsilon = 1e-6

    // MARK: - The global scale (KD-3)

    /// The global projection scale = the MEDIAN of the per-source focals
    /// (merge.py:251 — robust to a single outlier focal; with the
    /// single-focal model every entry is equal and the median is the focal).
    /// The numpy.median convention: odd → the middle, even → the mean of
    /// the two middles. Empty input returns 0 (the caller's geometry was
    /// already typed-failed upstream).
    public static func globalScale(focals: [Double]) -> Double {
        guard !focals.isEmpty else { return 0 }
        let sorted = focals.sorted()
        let count = sorted.count
        if count % 2 == 1 {
            return sorted[count / 2]
        }
        return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
    }

    /// The preview→full-resolution focal back-projection (KD-3): the
    /// preview camera segment estimates f in PREVIEW pixels; the full-
    /// resolution focal rescales by the preview downsample factor
    /// (`f_full = f_preview · fullW / previewW` — the diagonal-K reduction
    /// of `inv(preview_scale) @ K()`). A preview that skipped the
    /// downsample (≤ the preview cap) rescales by 1.
    public static func fullResolutionFocal(
        previewFocal: Double, previewWidth: Int, fullWidth: Int
    ) -> Double {
        guard previewWidth > 0 else { return previewFocal }
        return previewFocal * Double(fullWidth) / Double(previewWidth)
    }

    // MARK: - The spherical map (KD-2; merge.py:205-211 literal)

    /// The backward spherical map: canvas pixel (rectX + x, rectY + y) →
    /// the source pixel that projects there. Row-major `width×height` Float
    /// arrays; a pixel whose camera-space z ≤ 1e-6 maps to −1 (the Lumen
    /// invalid marker — it can never be a valid source coordinate, which
    /// are ≥ 0).
    ///
    /// PRECISION (the G3① premise): the angles and the rotation application
    /// run in Double, the RESULT truncates to Float32 — the Lumen map's
    /// actual path (its f32 `arange` promotes against the f64 rect/scale,
    /// the K product runs f64, only the RETURN is `astype(np.float32)`).
    /// The closed form (merge.py:205-211): u = (x + x0)/scale,
    /// v = (y + y0)/scale; ray = (sin v·sin u, −cos v, sin v·cos u);
    /// camera = R·ray; mx = f·camera.x/camera.z + centerX,
    /// my = f·camera.y/camera.z + centerY.
    public static func sphericalMap(
        rectX: Double, rectY: Double, width: Int, height: Int,
        scale: Double, source: PanoSourceGeometry
    ) -> (mx: [Float], my: [Float]) {
        var mx = [Float](repeating: -1, count: width * height)
        var my = [Float](repeating: -1, count: width * height)
        let rotation = source.rotation
        let focal = source.focal
        let centerX = Double(source.width - 1) / 2
        let centerY = Double(source.height - 1) / 2
        for y in 0..<height {
            let v = (rectY + Double(y)) / scale
            let sinV = sin(v)
            let rayY = -cos(v)
            let rowBase = y * width
            for x in 0..<width {
                let u = (rectX + Double(x)) / scale
                let sinU = sin(u)
                let cosU = cos(u)
                let rayX = sinV * sinU
                let rayZ = sinV * cosU
                // camera = R·ray (world→camera — the stored convention).
                let camX = rotation[0, 0] * rayX
                    + rotation[0, 1] * rayY
                    + rotation[0, 2] * rayZ
                let camY = rotation[1, 0] * rayX
                    + rotation[1, 1] * rayY
                    + rotation[1, 2] * rayZ
                let camZ = rotation[2, 0] * rayX
                    + rotation[2, 1] * rayY
                    + rotation[2, 2] * rayZ
                guard camZ > Self.zEpsilon else { continue }
                mx[rowBase + x] = Float(focal * (camX / camZ) + centerX)
                my[rowBase + x] = Float(focal * (camY / camZ) + centerY)
            }
        }
        return (mx, my)
    }

    /// The forward map (source pixel → the canvas' angle·scale frame): the
    /// ROI bounding walk's primitive. cam_ray = ((x−cx)/f, (y−cy)/f, 1);
    /// world = Rᵀ·cam_ray; u = atan2(world.x, world.z),
    /// v = acos(−world.y/‖world‖); returns (u·scale, v·scale). Exact
    /// inverse of `sphericalMap` on the z > 0 branch (the G3① anchor).
    public static func projectToCanvas(
        x: Double, y: Double, scale: Double, source: PanoSourceGeometry
    ) -> (u: Double, v: Double) {
        let centerX = Double(source.width - 1) / 2
        let centerY = Double(source.height - 1) / 2
        let camX = (x - centerX) / source.focal
        let camY = (y - centerY) / source.focal
        let camZ = 1.0
        // world = Rᵀ·cam (the transpose: cam = R·world ⟺ world = Rᵀ·cam).
        let r = source.rotation
        let worldX = r[0, 0] * camX + r[1, 0] * camY + r[2, 0] * camZ
        let worldY = r[0, 1] * camX + r[1, 1] * camY + r[2, 1] * camZ
        let worldZ = r[0, 2] * camX + r[1, 2] * camY + r[2, 2] * camZ
        let norm = sqrt(worldX * worldX + worldY * worldY + worldZ * worldZ)
        let u = atan2(worldX, worldZ)
        let v = acos(min(max(-worldY / norm, -1), 1))
        return (u * scale, v * scale)
    }

    /// One source's warped-footprint ROI at a candidate scale: the bounding
    /// box of the projected FULL BORDER (the spherical curvature bulges
    /// outside the corners — the border walk is the PyRotationWarper
    /// `warpRoi` semantics; the floor/ceil rounding errs conservative).
    static func roi(
        at scale: Double, source: PanoSourceGeometry
    ) -> PanoROI? {
        var minU = Double.infinity
        var minV = Double.infinity
        var maxU = -Double.infinity
        var maxV = -Double.infinity
        func project(_ x: Int, _ y: Int) -> Bool {
            let uv = projectToCanvas(
                x: Double(x), y: Double(y), scale: scale, source: source)
            guard uv.u.isFinite, uv.v.isFinite else { return false }
            minU = min(minU, uv.u)
            minV = min(minV, uv.v)
            maxU = max(maxU, uv.u)
            maxV = max(maxV, uv.v)
            return true
        }
        // The four borders (every pixel — the walk is O(w+h) per source).
        for x in 0..<source.width {
            if !project(x, 0) { return nil }
            if !project(x, source.height - 1) { return nil }
        }
        for y in 1..<(source.height - 1) {
            if !project(0, y) { return nil }
            if !project(source.width - 1, y) { return nil }
        }
        let x = Int(floor(minU))
        let y = Int(floor(minV))
        return PanoROI(
            x: x, y: y,
            width: Int(ceil(maxU)) - x,
            height: Int(ceil(maxV)) - y)
    }

    // MARK: - The bounded canvas (KD-4; merge.py:192-202 literal)

    /// The bounded-canvas shrink loop: at each round, project every
    /// source's border ROI at the candidate scale, take the union bounds;
    /// accept when w·h ≤ `maxCanvasPixels`; otherwise rescale by
    /// `sqrt(cap/(w·h))·0.998` and retry. Typed failures (the KD-4
    /// vocabulary, `PanoMatch.FailurePrefix.canvas`):
    ///   • a non-finite projection / empty bounds → "panorama projection
    ///     invalid" (merge.py:199),
    ///   • the round budget exhausted → the 200 MP bound failure
    ///     (merge.py:203).
    public static func boundedCanvas(
        sources: [PanoSourceGeometry], scale: Double
    ) throws -> PanoCanvasPlan {
        var scale = scale
        for _ in 0..<maxShrinkRounds {
            var rois: [PanoROI] = []
            rois.reserveCapacity(sources.count)
            for source in sources {
                guard let roi = roi(at: scale, source: source) else {
                    throw AppError.invalidParameter(
                        PanoMatch.FailurePrefix.canvas
                            + "panorama projection invalid")
                }
                rois.append(roi)
            }
            let originX = rois.map(\.x).min() ?? 0
            let originY = rois.map(\.y).min() ?? 0
            let endX = rois.map { $0.x + $0.width }.max() ?? 0
            let endY = rois.map { $0.y + $0.height }.max() ?? 0
            let width = endX - originX
            let height = endY - originY
            guard width > 0, height > 0, scale.isFinite else {
                throw AppError.invalidParameter(
                    PanoMatch.FailurePrefix.canvas
                        + "panorama projection invalid")
            }
            if width <= maxCanvasPixels, height <= maxCanvasPixels,
               width * height <= maxCanvasPixels {
                return PanoCanvasPlan(
                    rois: rois, originX: originX, originY: originY,
                    width: width, height: height, scale: scale)
            }
            scale *= sqrt(Double(maxCanvasPixels) / Double(width * height))
                * shrinkSafety
        }
        throw AppError.invalidParameter(
            PanoMatch.FailurePrefix.canvas
                + "cannot bound the canvas within \(maxCanvasPixels) pixels "
                + "in \(maxShrinkRounds) rounds")
    }
}

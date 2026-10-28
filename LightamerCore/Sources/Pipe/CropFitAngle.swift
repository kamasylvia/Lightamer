import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// CropFitAngle — the rotated-frame crop geometry (Plan M9-3-T1).
//
// Portions derived from lightcraft (https://github.com/tom97/lightcraft,
// `crates/geom/src/crop.rs`, MIT OR Apache-2.0) at upstream commit
// 54c6c43b; this file is an independent Swift re-expression (see NOTICE).
//
// The image (w × h pixels) is rotated by `angle` about its centre; the
// crop is an axis-aligned rectangle in that rotated frame, stored
// NORMALIZED to the frame size, so it is resolution-independent. The
// geometry answers three questions (upstream's with_angle, which converged
// three generations of UX bugs — #742 / #1388 / #1794):
//   1. `fitRect` — the largest crop of a given aspect that fits at an angle
//      (upstream `crop_fit_angle`, closed form).
//   2. `isWithinImage` — whether a crop still lies inside the rotated image.
//   3. `withAngle` — what a crop becomes when the angle changes: kept when
//      it still fits, shrunk about its own centre (aspect kept) when it no
//      longer does, and replaced by the largest fit when it WAS the largest
//      (so the crop grows back as the angle returns to 0°).
// `shouldAutoRefit` is the single-source predicate the rotate/straighten
// tools consult (D-M9G-1): the angle is the truth, the frame is derived —
// but a hand-adjusted frame is never auto-modified beyond what
// `withAngle` would do.
//
// All math is Double; comparison tolerances mirror upstream's 1e-9/1e-6.
// ─────────────────────────────────────────────────────────────────────────────

/// Straighten-angle crop geometry (Core-level pure functions).
public enum CropFitAngle {

    /// Minimum crop fraction the shrink-in-place path must preserve
    /// (dt `MIN_CROP_SIZE` = 0.01, the IOP `CropLimits.minFraction` value;
    /// duplicated here because Core cannot import IOP).
    static let minFraction: Double = 0.01

    /// A normalized axis-aligned rectangle (fractions of the frame), stored
    /// as edges (x0/y0 inclusive, x1/y1 exclusive — the crop op's edge
    /// convention).
    public struct Rect: Equatable, Sendable {
        public var x0: Double
        public var y0: Double
        public var x1: Double
        public var y1: Double

        public init(x0: Double, y0: Double, x1: Double, y1: Double) {
            self.x0 = x0
            self.y0 = y0
            self.x1 = x1
            self.y1 = y1
        }

        /// The full-frame identity.
        public static let unit = Rect(x0: 0, y0: 0, x1: 1, y1: 1)

        public var width: Double { x1 - x0 }
        public var height: Double { y1 - y0 }

        public var center: SIMD2<Double> {
            SIMD2((x0 + x1) / 2, (y0 + y1) / 2)
        }

        /// Pixel-domain width/height inside a `w × h` frame.
        public func pixelWidth(in w: Double) -> Double { width * w }
        public func pixelHeight(in h: Double) -> Double { height * h }

        /// The pixel aspect (width / height); nil when degenerate.
        public var aspect: Double? {
            let a = width / height
            return a.isFinite && a > 0 ? a : nil
        }

        public static func fromCenter(
            _ c: SIMD2<Double>, width: Double, height: Double
        ) -> Rect {
            Rect(x0: c.x - width / 2, y0: c.y - height / 2, x1: c.x + width / 2, y1: c.y + height / 2)
        }

        /// Scale the rect (normalized stays normalized).
        public func scaled(sx: Double, sy: Double) -> Rect {
            Rect(x0: x0 * sx, y0: y0 * sy, x1: x1 * sx, y1: y1 * sy)
        }

        public func isFiniteAll() -> Bool {
            [x0, y0, x1, y1].allSatisfy { $0.isFinite }
        }
    }

    // ── pixel-domain helpers (the math runs in pixels, mirrors upstream) ──

    struct PixelRect: Equatable {
        var x0: Double
        var y0: Double
        var x1: Double
        var y1: Double

        var width: Double { x1 - x0 }
        var height: Double { y1 - y0 }
        var center: SIMD2<Double> { SIMD2((x0 + x1) / 2, (y0 + y1) / 2) }
        var corners: [SIMD2<Double>] {
            [SIMD2(x0, y0), SIMD2(x1, y0), SIMD2(x0, y1), SIMD2(x1, y1)]
        }

        var aspect: Double? {
            let a = width / height
            return a.isFinite && a > 0 ? a : nil
        }

        static func fromCenter(_ c: SIMD2<Double>, width: Double, height: Double) -> PixelRect {
            PixelRect(x0: c.x - width / 2, y0: c.y - height / 2, x1: c.x + width / 2, y1: c.y + height / 2)
        }
    }

    /// Rotate a point about the image centre by `angleDegrees` (the inverse
    /// of the crop frame's rotation; upstream `Affine::rotate_about`).
    static func rotateAboutCenter(_ p: SIMD2<Double>, angleDegrees: Double, w: Double, h: Double) -> SIMD2<Double> {
        let a = -angleDegrees * .pi / 180
        let s = sin(a)
        let c = cos(a)
        let cx = w / 2
        let cy = h / 2
        let d = SIMD2(p.x - cx, p.y - cy)
        return SIMD2(cx + c * d.x - s * d.y, cy + s * d.x + c * d.y)
    }

    /// Whether every (pixel) crop corner lies within the rotated image
    /// (upstream `is_within_image`, tolerance 1e-6).
    public static func isWithinImage(
        _ rect: Rect, angleDegrees: Double, w: Double, h: Double
    ) -> Bool {
        let r = PixelRect(
            x0: rect.x0 * w, y0: rect.y0 * h, x1: rect.x1 * w, y1: rect.y1 * h)
        return r.corners.allSatisfy { corner in
            let q = rotateAboutCenter(corner, angleDegrees: angleDegrees, w: w, h: h)
            return q.x >= -1e-6 * w && q.y >= -1e-6 * h
                && q.x <= w * (1.0 + 1e-6) && q.y <= h * (1.0 + 1e-6)
        }
    }

    /// Largest scale `s` such that a crop shrunk about its OWN centre by `s`
    /// lies inside the rotated image; nil when its centre is outside the
    /// rotated image (upstream `fit_scale_about_centre`).
    static func fitScaleAboutCentre(
        rect: Rect, angleDegrees: Double, w: Double, h: Double
    ) -> Double? {
        let r = PixelRect(
            x0: rect.x0 * w, y0: rect.y0 * h, x1: rect.x1 * w, y1: rect.y1 * h)
        let c = rotateAboutCenter(r.center, angleDegrees: angleDegrees, w: w, h: h)
        if !(0.0...w).contains(c.x) || !(0.0...h).contains(c.y) {
            return nil
        }
        var s = 1.0
        for corner in r.corners {
            let d = rotateAboutCenter(corner, angleDegrees: angleDegrees, w: w, h: h) - c
            for (q, dq, bound) in [(c.x, d.x, w), (c.y, d.y, h)] {
                if dq > 0 {
                    s = min(s, (bound - q) / dq)
                } else if dq < 0 {
                    s = min(s, q / -dq)
                }
            }
        }
        return s.isFinite && s > 0 ? s : nil
    }

    /// Largest scale `s` such that a CENTRED `cw·s × ch·s` rectangle fits
    /// inside a `w × h` image rotated by `angleDegrees` about its centre
    /// (upstream `max_inscribed_scale`, closed form):
    /// `|x|c + |y|s ≤ w/2`, `|x|s + |y|c ≤ h/2` for the crop half-extents.
    public static func maxInscribedScale(
        w: Double, h: Double, angleDegrees: Double, cropW: Double, cropH: Double
    ) -> Double {
        let a = abs(angleDegrees) * .pi / 180
        let s = sin(a)
        let c = cos(a)
        let hx = cropW / 2
        let hy = cropH / 2
        let s1 = (w / 2) / (hx * c + hy * s)
        let s2 = (h / 2) / (hx * s + hy * c)
        return min(s1, s2)
    }

    /// The biggest crop of the image's own aspect (or `aspect` if given)
    /// that fits at `angleDegrees` (upstream `crop_fit_angle`, closed form;
    /// normalized output).
    public static func fitRect(
        w: Double, h: Double, angleDegrees: Double, aspect: Double?
    ) -> Rect {
        let a = aspect ?? w / h
        // the largest aspect-`a` rectangle inside the unrotated frame
        let frameAspect = w / h
        let baseW: Double
        let baseH: Double
        if frameAspect >= a {
            baseH = h
            baseW = h * a
        } else {
            baseW = w
            baseH = w / a
        }
        let s = min(maxInscribedScale(w: w, h: h, angleDegrees: angleDegrees, cropW: baseW, cropH: baseH), 1.0)
        let r = PixelRect.fromCenter(SIMD2(w / 2, h / 2), width: baseW * s, height: baseH * s)
        return Rect(x0: r.x0 / w, y0: r.y0 / h, x1: r.x1 / w, y1: r.y1 / h)
    }

    /// What a crop becomes when the angle turns from `angleDegrees` to
    /// `newAngleDegrees` on a `w × h` image (upstream `with_angle` — every
    /// way of setting the angle funnels here, M9-3-T3's rotate handle and
    /// straighten slider both consult it):
    /// - a crop that IS the largest of its aspect at its own angle (the
    ///   full photo, or one an earlier turn shrank to fit) stays the
    ///   largest at the new angle — so it grows back as the angle returns
    ///   towards 0° (upstream #1388);
    /// - any other crop that still fits keeps its rect (never grows);
    /// - a crop that no longer fits shrinks about its own centre, keeping
    ///   its aspect (upstream #1794), falling to a centred crop at its own
    ///   size when its centre leaves the rotated photo.
    public static func withAngle(
        _ rect: Rect, angleDegrees: Double, newAngleDegrees: Double, w: Double, h: Double
    ) -> Rect {
        let r = PixelRect(
            x0: rect.x0 * w, y0: rect.y0 * h, x1: rect.x1 * w, y1: rect.y1 * h)
        // a degenerate rect has no aspect to keep: fall back to the frame's own
        let aspect = r.aspect
        let largest = fitRect(w: w, h: h, angleDegrees: angleDegrees, aspect: aspect)
        let largestPx = PixelRect(
            x0: largest.x0 * w, y0: largest.y0 * h, x1: largest.x1 * w, y1: largest.y1 * h)
        let isLargest = abs(r.x0 - largestPx.x0) < 1e-9
            && abs(r.y0 - largestPx.y0) < 1e-9
            && abs(r.x1 - largestPx.x1) < 1e-9
            && abs(r.y1 - largestPx.y1) < 1e-9

        func normalized(_ p: PixelRect) -> Rect {
            Rect(x0: p.x0 / w, y0: p.y0 / h, x1: p.x1 / w, y1: p.y1 / h)
        }

        // still fits and not the largest: the angle changes, the rect does not
        if !isLargest && isWithinImage(rect, angleDegrees: newAngleDegrees, w: w, h: h) {
            return rect
        }
        let fitted = fitRect(w: w, h: h, angleDegrees: newAngleDegrees, aspect: aspect)
        if isLargest || aspect == nil {
            return fitted
        }
        // shrunk in place, as long as that leaves a crop the drag model would allow
        let minSide = minFraction * min(w, h)
        if let s = fitScaleAboutCentre(rect: rect, angleDegrees: newAngleDegrees, w: w, h: h),
            min(r.width, r.height) * s >= minSide
        {
            return normalized(PixelRect.fromCenter(r.center, width: r.width * s, height: r.height * s))
        }
        // its centre is off the turned photo (a sliver in a corner): centred,
        // at its own size at most
        let f = PixelRect(
            x0: fitted.x0 * w, y0: fitted.y0 * h, x1: fitted.x1 * w, y1: fitted.y1 * h)
        let scale = r.width / f.width
        guard scale.isFinite, scale < 1.0 else {
            return fitted
        }
        return normalized(PixelRect.fromCenter(f.center, width: f.width * scale, height: f.height * scale))
    }

    /// The linked-refit single-source predicate (D-M9G-1): whether turning
    /// the angle from `oldAngleDegrees` to `newAngleDegrees` moves the crop
    /// at all (the angle is the truth, the frame is derived — a frame the
    /// predicate leaves untouched is NEVER turned into a second history
    /// item). Callers that refit take `withAngle`'s output verbatim.
    public static func shouldAutoRefit(
        _ current: Rect, oldAngleDegrees: Double, newAngleDegrees: Double, w: Double, h: Double
    ) -> Bool {
        withAngle(current, angleDegrees: oldAngleDegrees, newAngleDegrees: newAngleDegrees, w: w, h: h) != current
    }
}

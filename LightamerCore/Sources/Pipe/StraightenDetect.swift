import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// StraightenDetect — the auto-straighten line detector (Plan M9-3-T3).
//
// Portions derived from lightcraft (https://github.com/tom97/lightcraft,
// `crates/pipeline/src/upright.rs` `detect_segments` / `level_degrees`,
// MIT OR Apache-2.0) at upstream commit 693c3593; this file is an
// independent Swift re-expression (see NOTICE).
//
// What it does (upstream's own summary): pixels with a strong luminance
// gradient are grown into regions of consistent level-line orientation
// (seeded from the strongest gradients), and each elongated region is
// fitted with a segment (weighted principal axis). The segments feed
// UprightMath's level solve; `levelDegrees` answers the crop panel's
// Auto-straighten button with the calibrated guard gates:
//   STRAIGHTEN_MAX_DEGREES = 10.0 — measured upstream on 68 photos
//   straightened by hand in Lightroom Classic and 300 left as shot: none
//   was turned by more than 6°, while a larger "level" came from texture.
//   STRAIGHTEN_MIN_LINES = 3 — one line (a frame edge, a branch) said
//   nothing about the horizon in that measurement.
//
// Coordinates: segments come out in centred-normalized coordinates of the
// luminance plane, `((x,y) − centre) / (long edge / 2)`, so detection is
// resolution-independent (the T1 solve domain). Sign convention: the
// returned angle UNDOES the measured tilt — a right-drooping horizon
// (y grows with x in image coordinates) reads NEGATIVE (golden gate 4).
//
// All math is Double/Float mixed per upstream (the plane stays Float32 —
// a luminance buffer, L006's raster domain; the fitting is f64).
// ─────────────────────────────────────────────────────────────────────────────

/// Auto-straighten line detection (Core-level pure functions; CPU Swift,
/// the upstream analysis route — no GPU detector).
public enum StraightenDetect {

    /// The most Auto straighten turns a photo (degrees; upstream
    /// `STRAIGHTEN_MAX_DEGREES`, the 68+300-photo calibration).
    public static let maxDegrees: Double = 10.0

    /// The fewest agreeing lines Auto straighten acts on (upstream
    /// `STRAIGHTEN_MIN_LINES`).
    public static let minLines: Int = 3

    /// Detect line segments in a luminance plane (values roughly 0..1,
    /// perceptual). Returns segments in centred-normalized coordinates of
    /// the plane (upstream `detect_segments`; deterministic — the seed
    /// order is a total sort, the region growth is a deterministic stack).
    public static func detectSegments(
        luminance: [Float], width: Int, height: Int
    ) -> [UprightMath.Segment] {
        let w = width, h = height
        guard w >= 16, h >= 16, luminance.count >= w * h else { return [] }
        let img = gaussianBlur(luminance, width: w, height: h, sigma: 0.8)
        let n = w * h
        var mag = [Float](repeating: 0, count: n)
        var ang = [Float](repeating: 0, count: n)  // level-line angle, mod π
        func at(_ x: Int, _ y: Int) -> Float { img[y * w + x] }
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let gx = (at(x + 1, y - 1) + 2 * at(x + 1, y) + at(x + 1, y + 1))
                    - (at(x - 1, y - 1) + 2 * at(x - 1, y) + at(x - 1, y + 1))
                let gy = (at(x - 1, y + 1) + 2 * at(x, y + 1) + at(x + 1, y + 1))
                    - (at(x - 1, y - 1) + 2 * at(x, y - 1) + at(x + 1, y - 1))
                let i = y * w + x
                mag[i] = (gx * gx + gy * gy).squareRoot() / 8.0
                var a = atan2(gy, gx) + Float.pi / 2
                a = a.remainder(dividingBy: Float.pi)
                if a < 0 { a += Float.pi }
                ang[i] = a
            }
        }
        // adaptive threshold: strong edges relative to the image's own contrast
        var sorted = mag.filter { $0 > 1e-4 }
        guard sorted.count >= 32 else { return [] }
        sorted.sort()
        let p90 = sorted[sorted.count * 9 / 10]
        let thr = max(p90 * 0.35, Float(0.008))
        var order = (0..<n).filter { mag[$0] > thr }
        order.sort { mag[$1] < mag[$0] }
        var used = [Bool](repeating: false, count: n)
        let tol = Float(22.5 * Double.pi / 180)
        let minLen = 0.04 * Double(max(w, h))
        let halfLong = Double(max(w, h)) / 2.0
        let cx = Double(w) / 2.0, cy = Double(h) / 2.0
        var out: [UprightMath.Segment] = []
        var stack: [Int] = []
        var region: [Int] = []
        for seed in order {
            if used[seed] { continue }
            used[seed] = true
            region.removeAll(keepingCapacity: true)
            region.append(seed)
            stack.removeAll(keepingCapacity: true)
            stack.append(seed)
            // region angle via doubled-angle mean
            var sc = cos(2 * ang[seed])
            var ss = sin(2 * ang[seed])
            while let i = stack.popLast() {
                let x = i % w, y = i / w
                let ra = atan2(ss, sc) / 2
                for dy in -1...1 {
                    for dx in -1...1 {
                        if dx == 0, dy == 0 { continue }
                        let nx = x + dx, ny = y + dy
                        guard nx >= 1, ny >= 1, nx < w - 1, ny < h - 1 else { continue }
                        let j = ny * w + nx
                        if used[j] || mag[j] <= thr { continue }
                        var d = (ang[j] - ra).remainder(dividingBy: Float.pi)
                        if d < 0 { d += Float.pi }
                        if d > Float.pi / 2 { d = Float.pi - d }
                        if d > tol { continue }
                        used[j] = true
                        region.append(j)
                        stack.append(j)
                        sc += cos(2 * ang[j])
                        ss += sin(2 * ang[j])
                    }
                }
            }
            guard region.count >= 12 else { continue }
            // weighted principal axis
            var sw = 0.0, mx = 0.0, my = 0.0
            for i in region {
                let wt = Double(mag[i])
                sw += wt
                mx += wt * Double(i % w)
                my += wt * Double(i / w)
            }
            mx /= sw
            my /= sw
            var sxx = 0.0, syy = 0.0, sxy = 0.0
            for i in region {
                let wt = Double(mag[i])
                let dx = Double(i % w) - mx
                let dy = Double(i / w) - my
                sxx += wt * dx * dx
                syy += wt * dy * dy
                sxy += wt * dx * dy
            }
            let theta = 0.5 * atan2(2 * sxy, sxx - syy)
            let ux = cos(theta), uy = sin(theta)
            var lo = Double.greatestFiniteMagnitude, hi = -Double.greatestFiniteMagnitude
            var wlo = Double.greatestFiniteMagnitude, whi = -Double.greatestFiniteMagnitude
            for i in region {
                let dx = Double(i % w) - mx
                let dy = Double(i / w) - my
                let t = dx * ux + dy * uy
                let s = -dx * uy + dy * ux
                lo = min(lo, t)
                hi = max(hi, t)
                wlo = min(wlo, s)
                whi = max(whi, s)
            }
            let length = hi - lo
            let widthExtent = max(whi - wlo, 1.0)
            guard length >= minLen, length / widthExtent >= 5.0 else { continue }
            let a = SIMD2<Double>((mx + 0.5 + ux * lo - cx) / halfLong, (my + 0.5 + uy * lo - cy) / halfLong)
            let b = SIMD2<Double>((mx + 0.5 + ux * hi - cx) / halfLong, (my + 0.5 + uy * hi - cy) / halfLong)
            out.append(UprightMath.Segment(a: a, b: b))
        }
        return out
    }

    /// Separable Gaussian blur (σ, radius 3σ, edge-clamped) — the
    /// `lightcraft_raster::blur::gaussian` face for this module's needs.
    static func gaussianBlur(
        _ src: [Float], width: Int, height: Int, sigma: Float
    ) -> [Float] {
        let radius = Int(ceil(Double(sigma) * 3))
        var kernel = [Float](repeating: 0, count: 2 * radius + 1)
        var sum: Float = 0
        for i in 0..<kernel.count {
            let x = Float(i - radius)
            kernel[i] = exp(-x * x / (2 * sigma * sigma))
            sum += kernel[i]
        }
        for i in 0..<kernel.count { kernel[i] /= sum }
        var tmp = [Float](repeating: 0, count: width * height)
        var dst = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var acc: Float = 0
                for k in 0..<kernel.count {
                    let sx = min(max(x + k - radius, 0), width - 1)
                    acc += kernel[k] * src[y * width + sx]
                }
                tmp[y * width + x] = acc
            }
        }
        for y in 0..<height {
            for x in 0..<width {
                var acc: Float = 0
                for k in 0..<kernel.count {
                    let sy = min(max(y + k - radius, 0), height - 1)
                    acc += kernel[k] * tmp[sy * width + x]
                }
                dst[y * width + x] = acc
            }
        }
        return dst
    }

    /// The rotation (degrees, clockwise +) that levels `luminance`'s
    /// dominant horizon/plumb lines, if they agree, within `maxDegrees`
    /// and backed by at least `minLines` lines (upstream `level_degrees`
    /// — the crop panel's Auto-straighten answer; the guard gates live in
    /// `UprightMath.levelAngleWithin`).
    public static func levelDegrees(
        luminance: [Float], width: Int, height: Int
    ) -> Double? {
        let segs = detectSegments(luminance: luminance, width: width, height: height)
        return straightenAngle(segs: segs)
    }

    /// `levelDegrees` over pre-detected segments (the upstream
    /// `straighten_angle` face — detection and gating stay separable so
    /// the T3 detection-source comparison can share one plane).
    public static func straightenAngle(segs: [UprightMath.Segment]) -> Double? {
        let vert = segs.filter { $0.tiltFromVertical <= UprightMath.familySplitDegrees }
        let horiz = segs.filter { $0.tiltFromVertical > UprightMath.familySplitDegrees }
        return UprightMath.levelAngleWithin(
            vert: vert, horiz: horiz, maxDegrees: maxDegrees, minLines: minLines)
    }
}

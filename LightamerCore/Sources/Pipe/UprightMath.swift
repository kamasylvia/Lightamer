import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// UprightMath — Guided Upright perspective correction (Plan M9-3-T1).
//
// Copyright 2025 the lightcraft authors
// Portions Copyright 2026 the Lightamer authors
//
// The vanishing-point mathematics is ported from lightcraft
// (https://github.com/tom97/lightcraft, `crates/pipeline/src/upright.rs`
// and `crates/pipeline/src/transform.rs`, MIT OR Apache-2.0) at upstream
// commits fbc927f0 / 7635b38c / 693c3593 / 54c6c43b / 7d3cd8af; this file
// is an independent Swift re-expression of that math (see NOTICE).
//
// What it does (three stages):
//   1. Families — segments are grouped near-vertical / near-horizontal by
//      `tiltFromVertical` (≤45° fold).
//   2. Vanishing points — the least-squares VP of a family is the smallest
//      eigenvector of `Σ w·l·lᵀ` (w = segment length, l = its normalized
//      homogeneous line; Jacobi rotations). For the Guided flow the user's
//      guides ARE the inliers, so no RANSAC is needed (upstream
//      `solve_guided` skips it too).
//   3. Correction — a virtual camera rotation `K·R·K⁻¹` that sends the
//      vertical vanishing direction to the image y axis (and, for two
//      families, the horizontal one to the x axis with the focal estimated
//      from their orthogonality), re-centred so the image centre stays put
//      and its local scale is preserved.
//
// Coordinates: centred, `(p − centre) / (long edge / 2)` of the op's input
// frame, so results are independent of resolution. Results map input →
// transformed coordinates. All math is Double (upstream f64); the kernel
// sampling stays float32 (L006). Departures from upstream are confined to
// what the plan's pathological defenses require and are marked inline:
//   - near-parallel guide families (cross-product norm² < 1e-24, i.e.
//     coincident lines) yield no VP (upstream relies on RANSAC, Guided
//     doesn't run it — M9-3 golden gate 5),
//   - a VP inside the frame (radius < 2.0) is rejected as a scene feature,
//     not camera tilt (upstream keeps this check in `reliable` for the
//     auto flow; Guided adopts it per plan).
// NOT ported (D-M9G-3): `detect_segments`, RANSAC scoring, the `reliable`
// consensus block, `analyze_source` caching, `upright_transform`
// persistence — the Guided guides carry the evidence themselves.
// ─────────────────────────────────────────────────────────────────────────────

/// Guided Upright math (Core-level pure functions; consumed by the IOP
/// `upright` op and the straighten detector).
public enum UprightMath {

    /// Assumed focal length in half-long-edge units (≈ 27 mm on a 36 mm
    /// frame; upstream `DEFAULT_FOCAL`).
    public static let defaultFocal: Double = 1.5

    /// Guides closer to vertical than this (degrees, 0 = vertical) join the
    /// vertical family; the rest the horizontal one.
    static let familySplitDegrees: Double = 45.0

    /// A detected (or user-drawn) line segment in centred coordinates.
    public struct Segment: Equatable, Sendable {

        public var a: SIMD2<Double>
        public var b: SIMD2<Double>

        public init(a: SIMD2<Double>, b: SIMD2<Double>) {
            self.a = a
            self.b = b
        }

        public var length: Double {
            let d = b - a
            return (d.x * d.x + d.y * d.y).squareRoot()
        }

        /// Homogeneous line through the endpoints, normalized so (l0, l1)
        /// is a unit normal (upstream `Segment::line`).
        var lineComponents: [Double] {
            let l0 = a.y - b.y
            let l1 = b.x - a.x
            let l2 = a.x * b.y - b.x * a.y
            let n = max((l0 * l0 + l1 * l1).squareRoot(), 1e-12)
            return [l0 / n, l1 / n, l2 / n]
        }

        /// Angle from vertical in degrees (0 = vertical), folded to 0..90
        /// (upstream `tilt_from_vertical`).
        public var tiltFromVertical: Double {
            let dx = abs(b.x - a.x)
            let dy = abs(b.y - a.y)
            return atan2(dx, dy) * 180 / .pi
        }
    }

    // ── small 3-vector helpers (upstream `cross`/`dot`/`norm`) ──

    static func cross3(_ a: [Double], _ b: [Double]) -> [Double] {
        [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
    }

    static func dot3(_ a: [Double], _ b: [Double]) -> Double {
        a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
    }

    static func norm3(_ a: [Double]) -> [Double] {
        let n = max(dot3(a, a).squareRoot(), 1e-300)
        return [a[0] / n, a[1] / n, a[2] / n]
    }

    // MARK: - Vanishing points

    /// Smallest eigenvector of a symmetric 3×3 matrix (Jacobi rotations;
    /// upstream `smallest_eigvec` — 50 rounds, convergence 1e-15).
    static func smallestEigvec(_ m0: [[Double]]) -> [Double] {
        var a = m0
        var v = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
        for _ in 0..<50 {
            var p = 0, q = 1
            var big = 0.0
            for i in 0..<3 {
                for j in (i + 1)..<3 where abs(a[i][j]) > big {
                    big = abs(a[i][j])
                    p = i
                    q = j
                }
            }
            if big < 1e-15 { break }
            let theta = (a[q][q] - a[p][p]) / (2.0 * a[p][q])
            var t = (theta < 0 ? -1.0 : 1.0) / (abs(theta) + (theta * theta + 1.0).squareRoot())
            if theta == 0.0 { t = 1.0 }
            let c = 1.0 / (t * t + 1.0).squareRoot()
            let s = t * c
            for k in 0..<3 {
                let akp = a[k][p], akq = a[k][q]
                a[k][p] = c * akp - s * akq
                a[k][q] = s * akp + c * akq
            }
            for k in 0..<3 {
                let apk = a[p][k], aqk = a[q][k]
                a[p][k] = c * apk - s * aqk
                a[q][k] = s * apk + c * aqk
            }
            for row in 0..<3 {
                let vp = v[row][p], vq = v[row][q]
                v[row][p] = c * vp - s * vq
                v[row][q] = s * vp + c * vq
            }
        }
        var best = 0
        for i in 1..<3 where a[i][i] < a[best][best] { best = i }
        return norm3([v[0][best], v[1][best], v[2][best]])
    }

    /// Least-squares vanishing point of `segs` (weights = lengths; upstream
    /// `refine_vp`).
    public static func refineVP(_ segs: [Segment]) -> [Double] {
        var m = [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
        for s in segs {
            let l = s.lineComponents
            let w = s.length
            for i in 0..<3 {
                for j in 0..<3 {
                    m[i][j] += w * l[i] * l[j]
                }
            }
        }
        return smallestEigvec(m)
    }

    /// Focal length (centred units) that makes two finite vanishing points
    /// orthogonal, when plausible (upstream `focal_from_vps`): the accepted
    /// range is 0.5..6.0 half-long-edge units; a VP at infinity (v[2] ≈ 0)
    /// or an out-of-range answer returns nil and the caller falls back to
    /// `defaultFocal` (golden gate 5, third defense).
    public static func focalFromVPs(_ v: [Double], _ h: [Double]) -> Double? {
        guard abs(v[2]) >= 1e-9, abs(h[2]) >= 1e-9 else { return nil }
        let vx = v[0] / v[2], vy = v[1] / v[2]
        let hx = h[0] / h[2], hy = h[1] / h[2]
        let f2 = -(vx * hx + vy * hy)
        guard f2 > 0 else { return nil }
        let f = f2.squareRoot()
        return (f >= 0.5 && f <= 6.0) ? f : nil
    }

    // MARK: - Solving

    /// Direction (camera frame) of a vanishing point for focal length `f`
    /// (upstream `direction`).
    static func direction(_ v: [Double], _ f: Double) -> [Double] {
        norm3([v[0] / f, v[1] / f, v[2]])
    }

    /// The rotation (rows) taking unit vector `a` to unit vector `b`
    /// (Rodrigues, minimal angle; upstream `rotation_between`).
    public static func rotationBetween(_ a: [Double], _ b: [Double]) -> Mat3D {
        let axis = cross3(a, b)
        let s = (dot3(axis, axis)).squareRoot()
        let c = dot3(a, b)
        if s < 1e-12 {
            return .identity
        }
        let k = [axis[0] / s, axis[1] / s, axis[2] / s]
        let kx = [[0.0, -k[2], k[1]], [k[2], 0.0, -k[0]], [-k[1], k[0], 0.0]]
        var r = [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
        for i in 0..<3 {
            for j in 0..<3 {
                var kk = 0.0
                for m in 0..<3 { kk += kx[i][m] * kx[m][j] }
                r[i][j] = (i == j ? 1.0 : 0.0) + s * kx[i][j] + (1.0 - c) * kk
            }
        }
        return Mat3D(
            r[0][0], r[0][1], r[0][2],
            r[1][0], r[1][1], r[1][2],
            r[2][0], r[2][1], r[2][2])
    }

    /// Vertical correction: send the vertical vanishing direction to the
    /// image y axis (upstream `solve_vertical`; the direction is flipped so
    /// the plumb lines fall the same way up they were shot).
    public static func solveVertical(_ v: [Double], _ f: Double) -> Mat3D {
        var d = direction(v, f)
        if d[1] < 0 {
            d = [-d[0], -d[1], -d[2]]
        }
        return rotationBetween(d, [0, 1, 0])
    }

    /// Full correction: vertical direction → y, horizontal direction → x
    /// (Gram–Schmidt; upstream `solve_full`).
    public static func solveFull(_ v: [Double], _ h: [Double], _ f: Double) -> Mat3D {
        var dv = direction(v, f)
        if dv[1] < 0 {
            dv = [-dv[0], -dv[1], -dv[2]]
        }
        var dh = direction(h, f)
        if dh[0] < 0 {
            dh = [-dh[0], -dh[1], -dh[2]]
        }
        let p = dot3(dh, dv)
        let r1 = norm3([dh[0] - p * dv[0], dh[1] - p * dv[1], dh[2] - p * dv[2]])
        let r3 = cross3(r1, dv)
        return Mat3D(
            r1[0], r1[1], r1[2],
            dv[0], dv[1], dv[2],
            r3[0], r3[1], r3[2])
    }

    /// `K·R·K⁻¹` for a rotation `r` (rows) and focal length `f` (upstream
    /// `rotation_homography`).
    public static func rotationHomography(_ r: Mat3D, _ f: Double) -> Mat3D {
        let k = Mat3D(f, 0, 0, 0, f, 0, 0, 0, 1)
        let ki = Mat3D(1 / f, 0, 0, 0, 1 / f, 0, 0, 0, 1)
        return Mat3D.mul(k, Mat3D.mul(r, ki))
    }

    /// Translate so the origin maps to itself and scale so the local area
    /// there is unchanged (upstream `recentre`; numerical Jacobian at the
    /// origin, e = 1e-4).
    public static func recentre(_ h: Mat3D) -> Mat3D {
        let o = h.project(0, 0)
        let t = Mat3D.mul(Mat3D(1, 0, -o.x, 0, 1, -o.y, 0, 0, 1), h)
        let e = 1e-4
        let px = t.project(e, 0)
        let py = t.project(0, e)
        let det = abs((px.x * py.y - px.y * py.x) / (e * e))
        let s = det > 1e-12 ? 1.0 / det.squareRoot() : 1.0
        return Mat3D.mul(Mat3D(s, 0, 0, 0, s, 0, 0, 0, 1), t)
    }

    /// Pure rotation (degrees, clockwise +) that levels the dominant lines
    /// (upstream `level_angle`).
    public static func levelAngle(vert: [Segment], horiz: [Segment]) -> Double? {
        levelAngleWithin(vert: vert, horiz: horiz, maxDegrees: 90.0, minLines: 1)
    }

    /// `levelAngle` that only answers for at most `maxDegrees`, backed by at
    /// least `minLines` agreeing segments (upstream `level_angle_within`).
    /// The sign convention: the answer is the rotation that UNDOES the
    /// measured tilt, so a right-drooping horizon (falling towards +x in
    /// image coordinates) reads negative.
    public static func levelAngleWithin(
        vert: [Segment], horiz: [Segment], maxDegrees: Double, minLines: Int
    ) -> Double? {
        func dev(_ s: Segment, vertical: Bool) -> Double {
            let dx = s.b.x - s.a.x
            let dy = s.b.y - s.a.y
            var a = (vertical ? atan2(dx, dy) : atan2(dy, dx)) * 180 / .pi
            if a > 90 {
                a -= 180
            } else if a < -90 {
                a += 180
            }
            return vertical ? -a : a
        }
        let lh = horiz.reduce(0.0) { $0 + $1.length }
        let lv = vert.reduce(0.0) { $0 + $1.length }
        // horizontal family wins when it carries at least half the vertical
        // length (upstream's priority for real horizons)
        let useHorizontal = lh >= lv * 0.5 && lh > 0
        let set = useHorizontal ? horiz : vert
        let vertical = !useHorizontal
        if set.isEmpty { return nil }
        // length-weighted median of the signed deviations
        var v = set.map { (dev($0, vertical: vertical), $0.length) }
        v.sort { $0.0 < $1.0 }
        let total = v.reduce(0.0) { $0 + $1.1 }
        var acc = 0.0
        guard let median = v.first(where: { acc += $0.1; return acc >= total / 2.0 }) else {
            return nil
        }
        // consensus: most of the line length must agree with the median
        // within 2°, otherwise the "lines" are scene texture rather than a
        // horizon or plumb lines
        let agreeing = v.filter { abs($0.0 - median.0) <= 2.0 }
        let agree = agreeing.reduce(0.0) { $0 + $1.1 }
        if agree >= 0.5 * total && agreeing.count >= minLines && abs(median.0) <= maxDegrees {
            return -median.0
        }
        return nil
    }

    /// Pure-Z rotation homography for `degrees` (upstream `rot_z_h`).
    public static func rotZH(_ degrees: Double) -> Mat3D {
        let a = degrees * .pi / 180
        let s = sin(a)
        let c = cos(a)
        return Mat3D(c, -s, 0, s, c, 0, 0, 0, 1)
    }

    /// Every entry finite (the pathological-defense net below never lets a
    /// non-finite matrix reach the warp).
    static func isFinite(_ h: Mat3D) -> Bool {
        (0..<3).allSatisfy { r in (0..<3).allSatisfy { c in h[r, c].isFinite } }
    }

    // MARK: - Guided solve

    /// Guided Upright from user guides (centred coordinates of the op's
    /// input frame; upstream `solve_guided`). Guides closer to vertical
    /// define the vertical vanishing point, the others the horizontal one;
    /// one guide of a kind only levels. Pathological defenses (M9-3 golden
    /// gate 5): a family whose lines coincide (cross-product norm² < 1e-24)
    /// yields no VP; a VP inside the frame (radius < 2.0 half-long-edges)
    /// is rejected as a scene feature; an out-of-range orthogonal focal
    /// falls back to `defaultFocal`. Degenerate input degrades down the
    /// chain (two families → vertical-only → level → identity) and never
    /// produces a non-finite matrix.
    public static func solveGuided(_ guides: [Segment]) -> Mat3D {
        let guides = Array(guides.filter { $0.length > 1e-6 }.prefix(4))
        let vert = guides.filter { $0.tiltFromVertical <= familySplitDegrees }
        let horiz = guides.filter { $0.tiltFromVertical > familySplitDegrees }
        func familyVP(_ family: [Segment]) -> [Double]? {
            guard family.count >= 2 else { return nil }
            // Defense 1: coincident lines carry no vanishing-point evidence
            // (their Σ w·l·lᵀ is rank-1; the smallest eigenvector would be
            // meaningless). Parallel lines at DIFFERENT positions are fine —
            // they legitimately point at a VP at infinity.
            var maxCross2 = 0.0
            for i in 0..<family.count {
                for j in (i + 1)..<family.count {
                    let c = cross3(family[i].lineComponents, family[j].lineComponents)
                    let c2 = c[0] * c[0] + c[1] * c[1] + c[2] * c[2]
                    maxCross2 = Swift.max(maxCross2, c2)
                }
            }
            guard maxCross2 >= 1e-24 else { return nil }
            let v = refineVP(family)
            // Defense 2: a VP inside the frame (radius < 2.0) is a scene
            // feature (sun rays, a road to the horizon), not camera tilt —
            // a camera-tilt VP lies far outside the frame.
            if abs(v[2]) > 1e-9 {
                let x = v[0] / v[2]
                let y = v[1] / v[2]
                if x * x + y * y < 4.0 { return nil }
            }
            return v
        }
        let (v, h) = (familyVP(vert), familyVP(horiz))
        // Degenerate-geometry net (M9-3 golden gate 5, first defense's
        // sibling): an extreme guide configuration (e.g. both VPs on the
        // y=0 line, tilting the virtual camera near 90°) can zero the
        // projective w row of K·R·K⁻¹ — a genuinely degenerate correction,
        // not a numeric bug. Any non-finite arm degrades down the chain
        // (level rotation is always finite), so the warp never sees NaN.
        switch (v, h) {
        case let (v?, h?):
            let f = focalFromVPs(v, h) ?? defaultFocal
            let solved = recentre(rotationHomography(solveFull(v, h, f), f))
            if isFinite(solved) { return solved }
            return levelAngle(vert: vert, horiz: horiz).map(rotZH) ?? .identity
        case let (v?, nil):
            let solved = recentre(rotationHomography(solveVertical(v, defaultFocal), defaultFocal))
            if isFinite(solved) { return solved }
            return levelAngle(vert: vert, horiz: horiz).map(rotZH) ?? .identity
        case (nil, .some):
            // two horizontal guides: make them parallel and horizontal
            // (rotate the problem by 90°, solve, rotate back)
            let hs = horiz.map { s in Segment(a: SIMD2(s.a.y, -s.a.x), b: SIMD2(s.b.y, -s.b.x)) }
            let r = solveVertical(refineVP(hs), defaultFocal)
            let inner = rotationHomography(r, defaultFocal)
            // (x, y) → (y, −x) and its inverse
            let to = Mat3D(0, 1, 0, -1, 0, 0, 0, 0, 1)
            guard let back = to.inverted() else { return .identity }
            let solved = recentre(Mat3D.mul(back, Mat3D.mul(inner, to)))
            if isFinite(solved) { return solved }
            return levelAngle(vert: vert, horiz: horiz).map(rotZH) ?? .identity
        default:
            return levelAngle(vert: vert, horiz: horiz).map(rotZH) ?? .identity
        }
    }
}

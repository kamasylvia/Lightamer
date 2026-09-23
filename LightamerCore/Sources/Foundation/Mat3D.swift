import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Mat3D — the row-major 3×3 Double matrix (moved to Core in Plan 06-03-T2,
// D-06-03-T2-1: the mask/liquify point-mapping machinery lives in Core and
// cannot import LightamerIOP where the type was born in 04-03).
//
// LightamerIOP re-exports it verbatim via `public typealias Mat3D =
// LightamerCore.Mat3D` (Ashift/Homography.swift) — every 04-03/04-04 API
// surface and test keeps compiling unchanged. The dt references below are
// the ORIGINAL 04-03 header's.
//
// Darktable reference: `src/common/math.h:195-228` (`mat3mul`/`mat3mulv`,
// row-major, dest = m1*m2) + `src/common/matrices.c:53-88` (`mat3inv`
// adjugate, eps 1e-7, error → caller falls back to identity).
// ─────────────────────────────────────────────────────────────────────────────

/// Row-major 3×3 Double matrix (`m[row * 3 + col]`, dt `float[3][3]`
/// layout, `math.h:213-228` multiplication order).
public struct Mat3D: Equatable, Sendable {
    public var m: (Double, Double, Double, Double, Double, Double, Double, Double, Double)

    public init(
        _ m00: Double, _ m01: Double, _ m02: Double,
        _ m10: Double, _ m11: Double, _ m12: Double,
        _ m20: Double, _ m21: Double, _ m22: Double
    ) {
        m = (m00, m01, m02, m10, m11, m12, m20, m21, m22)
    }

    public static let identity = Mat3D(
        1, 0, 0,
        0, 1, 0,
        0, 0, 1)

    public subscript(row: Int, col: Int) -> Double {
        get {
            let a = [m.0, m.1, m.2, m.3, m.4, m.5, m.6, m.7, m.8]
            return a[row * 3 + col]
        }
    }
    public static func == (lhs: Mat3D, rhs: Mat3D) -> Bool {
        lhs.m.0 == rhs.m.0 && lhs.m.1 == rhs.m.1 && lhs.m.2 == rhs.m.2 && lhs.m.3 == rhs.m.3 && lhs.m.4 == rhs.m.4 && lhs.m.5 == rhs.m.5 && lhs.m.6 == rhs.m.6 && lhs.m.7 == rhs.m.7 && lhs.m.8 == rhs.m.8
    }

    /// dt `mat3mul` (`math.h:213-228`): dest = a * b, in this order.
    public static func mul(_ a: Mat3D, _ b: Mat3D) -> Mat3D {
        let av = [a.m.0, a.m.1, a.m.2, a.m.3, a.m.4, a.m.5, a.m.6, a.m.7, a.m.8]
        let bv = [b.m.0, b.m.1, b.m.2, b.m.3, b.m.4, b.m.5, b.m.6, b.m.7, b.m.8]
        var out = [Double](repeating: 0, count: 9)
        for k in 0..<3 {
            for i in 0..<3 {
                var x = 0.0
                for j in 0..<3 { x += av[3 * k + j] * bv[3 * j + i] }
                out[3 * k + i] = x
            }
        }
        return Mat3D(out[0], out[1], out[2], out[3], out[4], out[5], out[6], out[7], out[8])
    }

    /// dt `mat3mulv` (`math.h:195-207`): homogeneous apply (no divide —
    /// the caller normalizes, dt `:1179-1180` / `:1259-1260` pattern).
    public func applied(_ x: Double, _ y: Double) -> (x: Double, y: Double, w: Double) {
        let v = [x, y, 1.0]
        let av = [m.0, m.1, m.2, m.3, m.4, m.5, m.6, m.7, m.8]
        var o = [0.0, 0.0, 0.0]
        for k in 0..<3 {
            var s = 0.0
            for i in 0..<3 { s += av[3 * k + i] * v[i] }
            o[k] = s
        }
        return (o[0], o[1], o[2])
    }

    /// Projective apply with homogeneous divide (dt `:1179-1182` shape).
    public func project(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
        let p = applied(x, y)
        return (p.x / p.w, p.y / p.w)
    }

    /// dt `mat3inv` (`matrices.c:53-88`): adjugate inverse; nil when
    /// |det| < 1e-7 (dt returns 1 → the caller falls back to identity).
    public func inverted() -> Mat3D? {
        let a = [m.0, m.1, m.2, m.3, m.4, m.5, m.6, m.7, m.8]
        func A(_ y: Int, _ x: Int) -> Double { a[(y - 1) * 3 + (x - 1)] }
        let det = A(1, 1) * (A(3, 3) * A(2, 2) - A(3, 2) * A(2, 3))
            - A(2, 1) * (A(3, 3) * A(1, 2) - A(3, 2) * A(1, 3))
            + A(3, 1) * (A(2, 3) * A(1, 2) - A(2, 2) * A(1, 3))
        guard abs(det) >= 1e-7 else { return nil }
        let inv = 1.0 / det
        return Mat3D(
            inv * (A(3, 3) * A(2, 2) - A(3, 2) * A(2, 3)),
            -inv * (A(3, 3) * A(1, 2) - A(3, 2) * A(1, 3)),
            inv * (A(2, 3) * A(1, 2) - A(2, 2) * A(1, 3)),
            -inv * (A(3, 3) * A(2, 1) - A(3, 1) * A(2, 3)),
            inv * (A(3, 3) * A(1, 1) - A(3, 1) * A(1, 3)),
            -inv * (A(2, 3) * A(1, 1) - A(2, 1) * A(1, 3)),
            inv * (A(3, 2) * A(2, 1) - A(3, 1) * A(2, 2)),
            -inv * (A(3, 2) * A(1, 1) - A(3, 1) * A(1, 2)),
            inv * (A(2, 2) * A(1, 1) - A(2, 1) * A(1, 2)))
    }
}

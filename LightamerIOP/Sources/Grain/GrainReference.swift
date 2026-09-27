import Foundation

// ─────────────────────────────────────────────────────────────────────────
// GrainReference — Plan 08-2 T2 golden authority (the CPU float64 twin of
// `grain_apply`). The 12-5 遗留#5 double-write doctrine.
//
// The simplex port is grain.c:120-327 in Double; the domain chain and the
// analytic paper-response envelope mirror the module/kernel. Cross-
// implementation comparison is at 6e-4 ABSOLUTE on the final pixel: the
// noise coordinates reach ~O(10³) lattice cells (float32 ulp ~2e-4 there)
// and the VERBATIM ×32 final scale amplifies the per-corner rounding to
// ~1e-2 on the unit noise field before the ×0.0375 strength/resp
// injection (DECISIONS D-08-2-5). Metal's permitted fma contraction plus
// the lattice-boundary sensitivity forbid BITWISE cross-implementation
// equality — the bitwise hard pair is kernel-vs-kernel determinism,
// which the tests pin byte-exactly.
// ─────────────────────────────────────────────────────────────────────────

public enum GrainReference {

    // grain.c:123-136.
    static let grad3: [[Double]] = [
        [1, 1, 0], [-1, 1, 0], [1, -1, 0], [-1, -1, 0],
        [1, 0, 1], [-1, 0, 1], [1, 0, -1], [-1, 0, -1],
        [0, 1, 1], [0, -1, 1], [0, 1, -1], [0, -1, -1],
    ]

    // grain.c:139-166.
    static let permutation: [Int] = [
        151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225,
        140, 36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148,
        247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32,
        57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175,
        74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122,
        60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54,
        65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169,
        200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64,
        52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212,
        207, 206, 59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213,
        119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9,
        129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104,
        218, 246, 97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241,
        81, 51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106, 157,
        184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93,
        222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180,
    ]

    static func perm(_ i: Int) -> Int { permutation[i & 255] }
    static func permMod(_ i: Int) -> Int { perm(i) % 12 }

    // grain.c:183-189.
    static func fastFloor(_ x: Double) -> Int {
        x > 0 ? Int(x) : Int(x) - 1
    }

    // grain.c:191-327 — the 3D simplex noise in Double, VERBATIM.
    public static func simplexNoise(_ xin: Double, _ yin: Double, _ zin: Double) -> Double {
        let F3 = 1.0 / 3.0
        let G3 = 1.0 / 6.0
        let s = (xin + yin + zin) * F3
        let i = fastFloor(xin + s)
        let j = fastFloor(yin + s)
        let k = fastFloor(zin + s)
        let t = Double(i + j + k) * G3
        let x0 = xin - (Double(i) - t)
        let y0 = yin - (Double(j) - t)
        let z0 = zin - (Double(k) - t)

        let i1: Int, j1: Int, k1: Int, i2: Int, j2: Int, k2: Int
        if x0 >= y0 {
            if y0 >= z0 {
                (i1, j1, k1, i2, j2, k2) = (1, 0, 0, 1, 1, 0) // X Y Z order
            } else if x0 >= z0 {
                (i1, j1, k1, i2, j2, k2) = (1, 0, 0, 1, 0, 1) // X Z Y order
            } else {
                (i1, j1, k1, i2, j2, k2) = (0, 0, 1, 1, 0, 1) // Z X Y order
            }
        } else {
            if y0 < z0 {
                (i1, j1, k1, i2, j2, k2) = (0, 0, 1, 0, 1, 1) // Z Y X order
            } else if x0 < z0 {
                (i1, j1, k1, i2, j2, k2) = (0, 1, 0, 0, 1, 1) // Y Z X order
            } else {
                (i1, j1, k1, i2, j2, k2) = (0, 1, 0, 1, 1, 0) // Y X Z order
            }
        }

        let x1 = x0 - Double(i1) + G3
        let y1 = y0 - Double(j1) + G3
        let z1 = z0 - Double(k1) + G3
        let x2 = x0 - Double(i2) + 2.0 * G3
        let y2 = y0 - Double(j2) + 2.0 * G3
        let z2 = z0 - Double(k2) + 2.0 * G3
        let x3 = x0 - 1.0 + 3.0 * G3
        let y3 = y0 - 1.0 + 3.0 * G3
        let z3 = z0 - 1.0 + 3.0 * G3

        let ii = i & 255
        let jj = j & 255
        let kk = k & 255
        let gi0 = permMod(ii + perm(jj + perm(kk)))
        let gi1 = permMod(ii + i1 + perm(jj + j1 + perm(kk + k1)))
        let gi2 = permMod(ii + i2 + perm(jj + j2 + perm(kk + k2)))
        let gi3 = permMod(ii + 1 + perm(jj + 1 + perm(kk + 1)))

        var n0 = 0.0, n1 = 0.0, n2 = 0.0, n3 = 0.0
        var t0 = 0.6 - x0 * x0 - y0 * y0 - z0 * z0
        if t0 > 0 { t0 *= t0; n0 = t0 * t0 * dot(grad3[gi0], x0, y0, z0) }
        var t1 = 0.6 - x1 * x1 - y1 * y1 - z1 * z1
        if t1 > 0 { t1 *= t1; n1 = t1 * t1 * dot(grad3[gi1], x1, y1, z1) }
        var t2 = 0.6 - x2 * x2 - y2 * y2 - z2 * z2
        if t2 > 0 { t2 *= t2; n2 = t2 * t2 * dot(grad3[gi2], x2, y2, z2) }
        var t3 = 0.6 - x3 * x3 - y3 * y3 - z3 * z3
        if t3 > 0 { t3 *= t3; n3 = t3 * t3 * dot(grad3[gi3], x3, y3, z3) }

        // :312 — scaled to stay just inside [-1,1].
        return 32.0 * (n0 + n1 + n2 + n3)
    }

    static func dot(_ g: [Double], _ x: Double, _ y: Double, _ z: Double) -> Double {
        g[0] * x + g[1] * y + g[2] * z
    }

    // grain.c:292-307 — the 3-octave spectrum (f/a VERBATIM). The seed
    // offset rides POST-scale in lattice-cell units (the float32
    // coordinate-magnitude bound — DECISIONS D-08-2-3; mirrors the
    // kernel).
    public static func simplex2D(_ x: Double, _ y: Double, _ zoom: Double, offset: Double = 0) -> Double {
        let f = [0.4910, 0.9441, 1.7280]
        let a = [0.2340, 0.7850, 1.2150]
        var total = 0.0
        for octave in 0..<3 {
            total += simplexNoise(x * f[octave] / zoom + offset, y * f[octave] / zoom, Double(octave)) * a[octave]
        }
        return total
    }

    // The analytic paper-response envelope (the kernel's grainRespCurve).
    public static func respCurve(_ luma: Double, midtonesBias: Double, gamma: Double) -> Double {
        let delta = 2.0 * exp((midtonesBias / 100.0) * log(0.0001))
        let l = min(max(luma, 1e-6), (1.0 + delta) * (1.0 - 1e-6))
        let u = -log((1.0 + 2.0 * delta) / (l + delta) - 1.0) * (1.0 + 2.0 * delta) / (4.0 * gamma) + 0.5
        let z = 4.0 * gamma * (0.5 - u) / (1.0 + 2.0 * delta)
        let e = exp(z)
        return 4.0 * gamma * e / ((1.0 + e) * (1.0 + e))
    }

    /// One pixel of grain (float64) — the kernel's body. `x`/`y` are the
    /// ROI-local buffer coordinates; the domain legs mirror the module's
    /// `uniforms` (shorter-side normalization + zoom + the seed offset +
    /// the rank-1 lattice when filtering).
    public static func pixel(
        _ rgb: SIMD3<Double>, x: Double, y: Double, u: Uniforms
    ) -> SIMD3<Double> {
        let px = x * u.invScaleWd
        let py = y * u.invScaleWd
        var noise: Double
        if u.filter {
            let fib1div2 = 34.0 / 21.0
            let fib2inv = 1.0 / 21.0
            noise = 0
            for l in 0..<21 {
                let sx = Double(l) / 21.0
                var sy = Double(l) * fib1div2
                sy -= (Double(Int(sy)))
                noise += fib2inv * simplex2D(px + sx * u.filtermul, py + sy * u.filtermul, u.zoom, offset: u.offset)
            }
        } else {
            noise = simplex2D(px, py, u.zoom, offset: u.offset)
        }
        let luma = 0.2627 * rgb.x + 0.6780 * rgb.y + 0.0593 * rgb.z
        let delta = noise * u.strength * 0.15 * respCurve(luma, midtonesBias: u.midtonesBias, gamma: u.gamma)
        return rgb + delta
    }

    /// The Double spelling of the kernel uniforms.
    public struct Uniforms {
        public var zoom: Double
        public var strength: Double
        public var midtonesBias: Double
        public var gamma: Double
        public var offset: Double
        public var invScaleWd: Double
        public var filtermul: Double
        public var filter: Bool

        public init(
            zoom: Double, strength: Double, midtonesBias: Double, gamma: Double,
            offset: Double, invScaleWd: Double, filtermul: Double, filter: Bool
        ) {
            self.zoom = zoom
            self.strength = strength
            self.midtonesBias = midtonesBias
            self.gamma = gamma
            self.offset = offset
            self.invScaleWd = invScaleWd
            self.filtermul = filtermul
            self.filter = filter
        }
    }
}

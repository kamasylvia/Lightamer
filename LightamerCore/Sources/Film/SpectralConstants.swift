import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────────
// SpectralConstants — the types/computation face of the spectral constant
// assets (M8-1a T2; the generated data half lives in SpectralConstantsData).
//
// CONTENT (all Float64, build-time faces — the runtime consumes the INTEGRATED
// tables the build engine emits, never these):
//   • the illuminant SPD lookup (by the profile vocabulary name);
//   • the spectral-locus polygon derived IN CODE from the CMFs (no stored
//     table — the X6 ruling: the locus is a code asset);
//   • the tc domain transforms tri2quad/quad2tri (Jakob & Hanika 2019 §3.2's
//     triangular-domain map, independently implemented from the paper's
//     math; BSD method reference, zero code copy) and the radial xy gamut
//     compression (Reinhard knee (0, 1, 6) toward the locus polygon);
//   • the RGB↔XYZ matrices derived at first touch from the CIE primary
//     chromaticities (no transcribed matrix constants — the derivation is
//     the standard linear system over primaries + white);
//   • the pinned public-standard constants: CAT16 (Li et al. 2017), CAT02
//     (Moroney et al. / CIECAM02), OkLab M1/M2 (Ottosson 2020) — verified
//     bit-for-bit against colour-science at generation time (the evidence
//     log: OkLab pinned-vs-colour-science max diff = 0.0);
//   • the neutral balance anchor (sRGB mid-gray 0.184 — the upstream
//     SF_MIDGRAY value is the same public fact; the single source is the
//     existing FilmFilterPackSolver constant).
//
// LICENSING: public standards and public papers only; no upstream (GPL or
// CC BY-SA) bytes are embedded (RESEARCH §2, X6).
// ─────────────────────────────────────────────────────────────────────────────

/// Float64 spectral colorimetry constants (build-time face, M8-1a T2).
public enum SpectralConstants {

    // MARK: - Basic chromaticity faces

    /// xy → XYZ at unit Y.
    public static func xyzFromChromaticity(x: Double, y: Double)
        -> SIMD3<Double> {
        SIMD3<Double>(x / y, 1.0, (1.0 - x - y) / y)
    }

    /// The chromaticity of a relative SPD under the CIE 1931 2° CMFs
    /// (plain Riemann sum over the 81-point axis — the integration form
    /// every build-time consumer shares, deterministic by construction).
    public static func chromaticity(spd: [Double]) -> (x: Double, y: Double) {
        let cmfs = SpectralConstantsData.cmfs
        var xyz = SIMD3<Double>.zero
        for l in 0..<spd.count {
            xyz += SIMD3<Double>(
                spd[l] * cmfs[l][0], spd[l] * cmfs[l][1], spd[l] * cmfs[l][2])
        }
        let sum = xyz.x + xyz.y + xyz.z
        return (xyz.x / sum, xyz.y / sum)
    }

    /// The illuminant SPD lookup by the profile vocabulary name
    /// ("D55", "TH-KG3", … — the generated set).
    public static func spd(named name: String) -> [Double]? {
        SpectralConstantsData.illuminants[name]
    }

    /// The deterministic illuminant name enumeration.
    public static var illuminantNames: [String] {
        SpectralConstantsData.illuminantNames
    }

    // MARK: - The tc domain (triangular ↔ square chromaticity map)

    /// The full-chromaticity-plane → unit-square map
    /// (u = (1−x)², v = y/(1−x), clamped — the whole real-chromaticity
    /// region maps into [0,1]² because Z ≥ 0 means x + y ≤ 1).
    public static func tri2quad(x: Double, y: Double)
        -> (u: Double, v: Double) {
        let tx = min(max(x, 0.0), 1.0)
        let ty = min(max(y, 0.0), 1.0)
        let denominator = max(1.0 - tx, 1e-10)
        return (min(max((1.0 - tx) * (1.0 - tx), 0.0), 1.0),
                min(max(ty / denominator, 0.0), 1.0))
    }

    /// The inverse map (x = 1−√u, y = v·√u).
    public static func quad2tri(u: Double, v: Double)
        -> (x: Double, y: Double) {
        let uu = min(max(u, 0.0), 1.0)
        let vv = min(max(v, 0.0), 1.0)
        let root = uu.squareRoot()
        return (1.0 - root, vv * root)
    }

    // MARK: - The spectral-locus polygon (a code asset — derived, not stored)

    /// The closed spectral-locus polygon in xy: one vertex per axis
    /// wavelength (380nm → 780nm along the locus), closed by repeating the
    /// first vertex (the purple-line closure is the polygon edge from the
    /// 780nm vertex back to the 380nm one). Float64.
    public static func spectralLocusPolygon() -> [(x: Double, y: Double)] {
        let cmfs = SpectralConstantsData.cmfs
        var ring: [(x: Double, y: Double)] = []
        ring.reserveCapacity(cmfs.count + 1)
        for row in cmfs {
            let sum = row[0] + row[1] + row[2]
            ring.append((row[0] / sum, row[1] / sum))
        }
        ring.append(ring[0])
        return ring
    }

    // MARK: - The radial xy gamut compression (input remap, upstream
    // `input_gamut_compress` default-on; M8-1A T4 review M1)

    /// The tc-domain knee constants (0, 1, 6) — the input gamut
    /// compression's Reinhard knee parameters (upstream
    /// InputGamutCompressSpec.knee, public module parameters).
    public static let tcKneeThreshold = 0.0
    public static let tcKneeLimit = 1.0
    public static let tcKneePower = 6.0

    /// The Reinhard knee: identity below the threshold, soft-compressed
    /// above it (d/(1+d^p)^(1/p) family, scaled to the limit).
    public static func reinhardKnee(
        _ d: Double, threshold: Double, limit: Double, power: Double
    ) -> Double {
        if d <= threshold { return d }
        let scale = limit - threshold
        let x = (d - threshold) / scale
        let y = x / Foundation.pow(1.0 + Foundation.pow(x, power), 1.0 / power)
        return threshold + scale * y
    }

    /// The distance along a ray from `origin` to the polygon's first edge
    /// crossing (INFINITY when no edge crosses — degenerate direction).
    static func rayPolygonDistance(
        origin: SIMD2<Double>, direction: SIMD2<Double>,
        polygon: [(x: Double, y: Double)]
    ) -> Double {
        var minimum = Double.infinity
        let n = polygon.count
        for k in 0..<(n - 1) {
            let ax = polygon[k].x, ay = polygon[k].y
            let ex = polygon[k + 1].x - ax
            let ey = polygon[k + 1].y - ay
            let denominator = direction.x * ey - direction.y * ex
            if abs(denominator) <= 1e-12 { continue }
            let ox = origin.x - ax
            let oy = origin.y - ay
            let t = (-ox * ey + oy * ex) / denominator
            let s = (-ox * direction.y + oy * direction.x) / denominator
            if t > 1e-9, s >= 0.0, s <= 1.0, t < minimum { minimum = t }
        }
        return minimum
    }

    /// The radial xy compression toward the spectral-locus polygon:
    /// chromaticities outside the locus pull in along the white-centered
    /// ray (Reinhard knee on the normalized distance); inside the locus
    /// the map is the identity.
    public static func compressXYRadial(
        _ xy: SIMD2<Double>, white: SIMD2<Double>,
        polygon: [(x: Double, y: Double)]
    ) -> SIMD2<Double> {
        let delta = xy - white
        let distance = simd_length(delta)
        if distance < 1e-9 { return xy }
        let direction = delta / distance
        let boundary = rayPolygonDistance(
            origin: white, direction: direction, polygon: polygon)
        let normalized = distance / max(boundary, 1e-12)
        let compressed = reinhardKnee(
            normalized, threshold: tcKneeThreshold, limit: tcKneeLimit,
            power: tcKneePower)
        return white + direction * compressed * boundary
    }

    // MARK: - RGB ↔ XYZ (derived from primaries — no transcribed matrices)

    /// A working-space definition: CIE primary chromaticities + white.
    public struct RGBSpace: Sendable, Equatable {
        public let redXy: SIMD2<Double>
        public let greenXy: SIMD2<Double>
        public let blueXy: SIMD2<Double>
        public let whiteXy: SIMD2<Double>

        public init(
            redXy: SIMD2<Double>, greenXy: SIMD2<Double>,
            blueXy: SIMD2<Double>, whiteXy: SIMD2<Double>
        ) {
            self.redXy = redXy
            self.greenXy = greenXy
            self.blueXy = blueXy
            self.whiteXy = whiteXy
        }

        /// The RGB→XYZ matrix (rows R/G/B), derived from the primaries:
        /// the standard linear system pinning each primary to its
        /// chromaticity direction and the white to the equal-energy-scaled
        /// white XYZ (unit Y). Deterministic pure Float64 algebra.
        public var rgbToXYZ: [[Double]] {
            let xyzR = xyzFromChromaticity(
                x: redXy.x, y: redXy.y)
            let xyzG = xyzFromChromaticity(
                x: greenXy.x, y: greenXy.y)
            let xyzB = xyzFromChromaticity(
                x: blueXy.x, y: blueXy.y)
            let white = xyzFromChromaticity(
                x: whiteXy.x, y: whiteXy.y)
            // Solve [R G B]·s = W for the primary scale factors.
            let matrix = [[xyzR.x, xyzG.x, xyzB.x],
                          [xyzR.y, xyzG.y, xyzB.y],
                          [xyzR.z, xyzG.z, xyzB.z]]
            let scales = SpectralConstants.solve3(
                matrix, rhs: [white.x, white.y, white.z])
            return [
                [xyzR.x * scales[0], xyzG.x * scales[1], xyzB.x * scales[2]],
                [xyzR.y * scales[0], xyzG.y * scales[1], xyzB.y * scales[2]],
                [xyzR.z * scales[0], xyzG.z * scales[1], xyzB.z * scales[2]],
            ]
        }

        /// The XYZ→RGB matrix (the exact inverse of `rgbToXYZ`).
        public var xyzToRGB: [[Double]] {
            SpectralConstants.inverse3(rgbToXYZ)
        }
    }

    /// Linear Rec2020 (the working space, D65 white).
    public static let rec2020 = RGBSpace(
        redXy: SIMD2<Double>(0.708, 0.292),
        greenXy: SIMD2<Double>(0.170, 0.797),
        blueXy: SIMD2<Double>(0.131, 0.046),
        whiteXy: SIMD2<Double>(SpectralConstantsData.d65WhiteX,
                               SpectralConstantsData.d65WhiteY))

    /// Linear sRGB (D65 white) — the mid-gray balance reference space
    /// (the balance gray is computed in sRGB regardless of the io space;
    /// the public upstream note).
    public static let srgb = RGBSpace(
        redXy: SIMD2<Double>(0.640, 0.330),
        greenXy: SIMD2<Double>(0.300, 0.600),
        blueXy: SIMD2<Double>(0.150, 0.060),
        whiteXy: SIMD2<Double>(SpectralConstantsData.d65WhiteX,
                               SpectralConstantsData.d65WhiteY))

    // MARK: - Pinned public-standard matrices

    /// CAT16 cone response matrix (Li et al. 2017 — the published
    /// constants; verified against colour-science at generation time).
    public static let cat16: [[Double]] = [
        [0.401288, 0.650173, -0.051461],
        [-0.250268, 1.204414, 0.045854],
        [-0.002079, 0.048952, 0.953127],
    ]

    /// CAT02 cone response matrix (CIECAM02 — the published constants;
    /// verified against colour-science at generation time).
    public static let cat02: [[Double]] = [
        [0.7328, 0.4296, -0.1624],
        [-0.7036, 1.6975, 0.0061],
        [0.0030, 0.0136, 0.9834],
    ]

    /// OkLab M1 (XYZ → LMS, linear) — Ottosson 2020 public constants.
    public static let oklabM1: [[Double]] = [
        [0.8189330101, 0.3618667424, -0.1288597137],
        [0.0329845436, 0.9293118715, 0.0361456387],
        [0.0482003018, 0.2643662691, 0.6338517070],
    ]

    /// OkLab M2 (LMS^(1/3) → Lab) — Ottosson 2020 public constants.
    public static let oklabM2: [[Double]] = [
        [0.2104542553, 0.7936177850, -0.0040720468],
        [1.9779984951, -2.4285922050, 0.4505937099],
        [0.0259040371, 0.7827717662, -0.8086757660],
    ]

    /// The chromatic-adaptation matrix (cone domain, von Kries form):
    /// M⁻¹·diag(adapted/source)·M mapping `srcXy` white onto `dstXy`.
    public static func catMatrix(
        coneMatrix: [[Double]], srcXy: SIMD2<Double>, dstXy: SIMD2<Double>
    ) -> [[Double]] {
        let src = coneMatrix.multiplyVector(
            xyzFromChromaticity(x: srcXy.x, y: srcXy.y))
        let dst = coneMatrix.multiplyVector(
            xyzFromChromaticity(x: dstXy.x, y: dstXy.y))
        let diagonal = [
            [dst.x / src.x, 0, 0],
            [0, dst.y / src.y, 0],
            [0, 0, dst.z / src.z],
        ]
        return Self.inverse3(coneMatrix)
            .multiply(diagonal.multiply(coneMatrix))
    }

    // MARK: - The neutral balance anchor

    /// The mid-gray the print balance anchors (sRGB 0.184 — the upstream
    /// SF_MIDGRAY value is the same public fact; the single source is the
    /// existing solver constant).
    public static let midGrayAnchor = FilmFilterPackSolver.midGraySceneLinear

    // MARK: - Small 3×3 linear algebra (row-major [[Double]])

    /// Cramer-rule solve of a 3×3 system (exact, deterministic; the
    /// callers pass well-conditioned colorimetric systems).
    public static func solve3(
        _ matrix: [[Double]], rhs: [Double]
    ) -> [Double] {
        let inverse = inverse3(matrix)
        return inverse.multiplyVector(rhs)
    }

    /// The 3×3 inverse (adjugate / determinant form).
    public static func inverse3(_ m: [[Double]]) -> [[Double]] {
        let a = m[0][0], b = m[0][1], c = m[0][2]
        let d = m[1][0], e = m[1][1], f = m[1][2]
        let g = m[2][0], h = m[2][1], i = m[2][2]
        let A = e * i - f * h
        let B = -(d * i - f * g)
        let C = d * h - e * g
        let determinant = a * A + b * B + c * C
        let invDet = 1.0 / determinant
        return [
            [A * invDet, -(b * i - c * h) * invDet, (b * f - c * e) * invDet],
            [B * invDet, (a * i - c * g) * invDet, -(a * f - c * d) * invDet],
            [C * invDet, -(a * h - b * g) * invDet, (a * e - b * d) * invDet],
        ]
    }
}

extension Array where Element == [Double] {
    /// row-major matrix × vector.
    func multiplyVector(_ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(
            self[0][0] * v.x + self[0][1] * v.y + self[0][2] * v.z,
            self[1][0] * v.x + self[1][1] * v.y + self[1][2] * v.z,
            self[2][0] * v.x + self[2][1] * v.y + self[2][2] * v.z)
    }

    /// row-major matrix × vector (array form).
    func multiplyVector(_ v: [Double]) -> [Double] {
        multiplyVector(SIMD3<Double>(v[0], v[1], v[2])).toArray()
    }

    /// row-major matrix × matrix.
    func multiply(_ other: [[Double]]) -> [[Double]] {
        var out = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        for r in 0..<3 {
            for c in 0..<3 {
                out[r][c] = self[r][0] * other[0][c]
                    + self[r][1] * other[1][c]
                    + self[r][2] * other[2][c]
            }
        }
        return out
    }
}

extension SIMD3 where Scalar == Double {
    /// The array-form twin of `multiplyVector`.
    func toArray() -> [Double] { [x, y, z] }
}

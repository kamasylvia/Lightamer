import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// OklabMath (Plan M5-1-01 T1, KD-1; OQ-M5-1-2) — the Oklab statistics-domain
// conversion: linear Rec2020 (the working space) ↔ Oklab, Float32 production
// + Float64 golden twin in one file.
//
// CONSTANT SINGLE SOURCE (this header IS the provenance record — the MSL
// mirror in ColorMatchKernels.metal points here):
//
//   1. Oklab's public analytic form (Björn Ottosson, "A perceptual color
//      space for image processing", bottosson.github.io/posts/colorwrong/ —
//      public-domain math constants, NOT sourced from any GPL repository):
//      linear sRGB → cone response (M1) → cube root → opponent axes (M2).
//      The published Float32-rounded constants are used verbatim (10
//      significant digits each).
//   2. Working-domain bridging (checker 回注 m1, 2026-10-09): M1's input
//      domain is linear sRGB while the working space is linear Rec2020, so
//      the chain is
//        linear Rec2020 → M(2020→709) → linear sRGB → M1 → cbrt → M2 → Oklab
//      (inverse chain: M2⁻¹ → cube → M1⁻¹ → M(709→2020)).
//      PRE-MERGED FORM (the declared internal freedom, DECISIONS): the two
//      linear prefixes are folded into ONE constant per direction —
//        M1C    = M1 · M(2020→709)
//        M1C⁻¹  = M(709→2020) · M1⁻¹
//      derived in Float64 from ITU-R BT.2020 / BT.709 primary chromaticities
//      (2020: R(0.708,0.292) G(0.170,0.797) B(0.131,0.046); 709:
//      R(0.64,0.33) G(0.30,0.60) B(0.15,0.06); both D65 (0.3127,0.3290))
//      via the standard RGB→XYZ primary matrix construction, printed at 11
//      significant digits. Both the CPU and the MSL sides hardcode the SAME
//      merged literals, so the fold is bit-identical across the boundary.
//      Rationale: one 3×3 per direction = fewer Float32 roundings on the
//      production path and one matrix multiply in the kernel.
//
// SIGN-PRESERVING cube root (checker 回注 m1): Rec2020 gamut corners and
// pipeline negatives produce negative LMS — both sides use
// `sign(lms)·pow(|lms|, 1/3)`; a bare `pow(x, 1/3)` is NaN for x < 0 and is
// BANNED. The same sign form appears in the MSL mirror.
//
// DOMAIN POLICY (OQ-M5-1-4, the matrix arm's full-domain ruling): the
// conversion clamps NOTHING — a pure analytic map, negative/ HDR inputs are
// legal in both directions (the G2 negative-LMS probes drive this).
//
// PRECISION FACES:
//   - Production (Float32): `linearRec2020ToOklab` / `oklabToLinearRec2020`.
//   - Golden twin (Float64): `linearRec2020ToOklab64` / `oklabToLinearRec202064`
//     — the SAME literals elevated via `Double(Float(c))` (L048 ②: the
//     reference mirrors the production constant set exactly, so a
//     constant-rounding systematic difference is never baked into a
//     parity band; measured round-trip bands live in
//     M5-1-01-DECISIONS).
// ─────────────────────────────────────────────────────────────────────────────

public enum OklabMath {

    // MARK: - Constants (the single source — see the header note)

    /// M1C = M1 · M(2020→709), row-major 9-tuple: linear Rec2020 → LMS.
    /// Rows sum to 1 (D65 gray maps to the neutral LMS axis).
    public static let m1c: [Float] = [
        0.6167557872, 0.36019839939, 0.023045813408,
        0.26513306398, 0.63583936408, 0.099027571839,
        0.10010263423, 0.2039065194, 0.69599084637,
    ]

    /// M2: LMS′ (cube-rooted) → Oklab. Published Ottosson constants.
    /// Row 0 sums to 1, row 1 sums to 1, row 2 sums to 0 (white → (1,0,0)).
    public static let m2: [Float] = [
        0.2104542553, 0.7936177850, -0.0040720468,
        1.9779984951, -2.4285922050, 0.4505937099,
        0.0259040371, 0.7827717662, -0.8086757660,
    ]

    /// M2⁻¹: Oklab → LMS′. Published Ottosson inverse constants.
    public static let m2Inv: [Float] = [
        0.99999999845051981432, 0.39633779217376785678, 0.21580375730991364839,
        1.00000000888176035663, -0.10556134232365634970, -0.06385417477170590340,
        1.00000005467241091770, -0.08948418209496575968, -1.29148553786409173990,
    ]

    /// M1C⁻¹ = M(709→2020) · M1⁻¹, row-major: LMS → linear Rec2020.
    public static let m1cInv: [Float] = [
        2.139906736, -1.2463895092, 0.1064827732,
        -0.88473586287, 2.1632309824, -0.27849511958,
        -0.04857375783, -0.45450314311, 1.5030769009,
    ]

    /// The cube-root exponent literal, ONE spelling on both sides (Swift
    /// `Float(1.0) / Float(3.0)` ≡ MSL `1.0f / 3.0f` — the exact Float32
    /// quotient 0.33333334; the sign-preserving pow form consumes it).
    public static let oneThird: Float = 1.0 / 3.0

    // MARK: - Row-major 3×3 apply (the exact operation order mirrored in MSL)

    @inline(__always)
    static func apply(_ m: [Float], _ v: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(
            m[0] * v.x + m[1] * v.y + m[2] * v.z,
            m[3] * v.x + m[4] * v.y + m[5] * v.z,
            m[6] * v.x + m[7] * v.y + m[8] * v.z)
    }

    @inline(__always)
    static func apply64(_ m: [Double], _ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(
            m[0] * v.x + m[1] * v.y + m[2] * v.z,
            m[3] * v.x + m[4] * v.y + m[5] * v.z,
            m[6] * v.x + m[7] * v.y + m[8] * v.z)
    }

    /// Sign-preserving cube root — `sign(x)·|x|^(1/3)` (NaN-free for x < 0;
    /// the ONLY cube-root spelling allowed on either side).
    @inline(__always)
    public static func signedCbrt(_ x: Float) -> Float {
        x >= 0 ? Foundation.pow(x, oneThird) : -Foundation.pow(-x, oneThird)
    }

    @inline(__always)
    public static func signedCbrt64(_ x: Double) -> Double {
        x >= 0 ? Foundation.pow(x, Double(oneThird)) : -Foundation.pow(-x, Double(oneThird))
    }

    // MARK: - Production face (Float32)

    /// linear Rec2020 → Oklab (Float32, full domain, zero clamp).
    @inline(__always)
    public static func linearRec2020ToOklab(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        let lms = apply(m1c, rgb)
        let lmsP = SIMD3<Float>(
            signedCbrt(lms.x), signedCbrt(lms.y), signedCbrt(lms.z))
        return apply(m2, lmsP)
    }

    /// Oklab → linear Rec2020 (Float32, full domain, zero clamp). The cube
    /// is a plain triple product on both sides (`l′·l′·l′` — exact mirror).
    @inline(__always)
    public static func oklabToLinearRec2020(_ lab: SIMD3<Float>) -> SIMD3<Float> {
        let lmsP = apply(m2Inv, lab)
        let lms = lmsP * lmsP * lmsP
        return apply(m1cInv, lms)
    }

    // MARK: - Golden twin (Float64 — the same constants, elevated per L048 ②)

    static let m1c64: [Double] = m1c.map { Double($0) }
    static let m2_64: [Double] = m2.map { Double($0) }
    static let m2Inv64: [Double] = m2Inv.map { Double($0) }
    static let m1cInv64: [Double] = m1cInv.map { Double($0) }

    /// linear Rec2020 → Oklab, Float64 golden twin.
    @inline(__always)
    public static func linearRec2020ToOklab64(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let lms = apply64(m1c64, rgb)
        let lmsP = SIMD3<Double>(
            signedCbrt64(lms.x), signedCbrt64(lms.y), signedCbrt64(lms.z))
        return apply64(m2_64, lmsP)
    }

    /// Oklab → linear Rec2020, Float64 golden twin.
    @inline(__always)
    public static func oklabToLinearRec202064(_ lab: SIMD3<Double>) -> SIMD3<Double> {
        let lmsP = apply64(m2Inv64, lab)
        let lms = lmsP * lmsP * lmsP
        return apply64(m1cInv64, lms)
    }
}

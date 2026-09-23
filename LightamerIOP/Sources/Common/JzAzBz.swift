import simd

// ─────────────────────────────────────────────────────────────────────────
// JzAzBz / JzCzhz (Plan 06-02 T1/T3) — the perceptual-domain round trip the
// blendop perceptual modes (hue/saturation/color/luminosity/colorAdjust)
// are defined in. SAME-SOURCE contract (the plan's "常量与 filmic/cb 链同源"):
//
//   - RGB → XYZ:      `LabRoundTrip.rec2020ToXYZ` (the project-wide D65
//                     Rec2020 matrix — the SAME constant set the filmic
//                     gamut LUT feeds dt-UCS/JzAzBz with, see
//                     ColorBalanceRGBMath.buildUCSGamutLUT).
//   - XYZ ⇄ JzAzBz:   `ColorBalanceRGBMath.xyzToJzAzBz` / `jzAzBzToXYZ`
//                     (dt colorspaces_inline_conversions.h:849-975,
//                     Safdar 2017 — already transliterated for the
//                     colorbalancergb gamut LUT; NOT redeclared here).
//   - JzAzBz ⇄ JzCzhz: the polar conversions of
//                     dt_JzAzBz_2_JzCzhz / dt_JzCzhz_2_JzAzBz
//                     (colorspaces_inline_conversions.h:895-910):
//                     Cz = hypot(az, bz), hz = atan2(bz, az) / 2π mapped
//                     to [0,1) turns; inverse = (cos·Cz, sin·Cz).
//
// ── L023 FULL ROUND-TRIP CONTRACT (the half-contract rule) ───────────────
// The GPU kernel (`BlendOpKernels.metal`) bakes the SAME chain as float32
// constants. The full round trip is FIVE legs, and the parity tests pin the
// WHOLE chain (never a single matrix pair — L023's half-contract lesson):
//
//   rgb ──rec2020ToXYZ──▶ xyz ──xyzToJzAzBz──▶ JzAzBz ──polar──▶ JzCzhz
//   rgb ◀──xyzToRec2020── xyz ◀──jzAzBzToXYZ── JzAzBz ◀──cartesian── JzCzhz
//
//   ⇒ mo·M·mi ≈ I leg gates (GPU float32, <1e-6): the matrix pairs
//     (rec2020ToXYZ, xyzToRec2020) and (jzA^T-applied, jzAI) are probed
//     inside the shader by `blendop_jz_matrix_probe`; the pow-chain legs
//     (PQ encode/decode) are pinned by the full-chain round-trip probe +
//     the hue-mode full-circle sweep against this Double reference
//     (BlendOpParityTests — the 1e-6 gate applies to the matrix legs, the
//     1e-5 gate to the float32 pow-chain parity, per plan T3 evidence).
//
// ANY change to these constants MUST re-run BlendOpParityTests in the same
// commit (L023: 矩阵定义变更与断言同批提交).
// ─────────────────────────────────────────────────────────────────────────
public enum JzCzhz {

    // MARK: Polar conversions (dt colorspaces_inline_conversions.h:895-910)

    /// `dt_JzAzBz_2_JzCzhz` — hz in [0,1) turns; hz = 0 when az = bz = 0
    /// (dt's atan2(0,0) = 0; a zero-radius rotation is a no-op so the hue
    /// blend formulas never need a special achromatic case).
    public static func fromJzAzBz(_ jab: SIMD3<Double>) -> SIMD3<Double> {
        var h = atan2(jab.z, jab.y) / (2.0 * Double.pi)
        if h < 0 { h += 1 }
        let cz = (jab.y * jab.y + jab.z * jab.z).squareRoot()
        return SIMD3(jab.x, cz, h)
    }

    /// `dt_JzCzhz_2_JzAzBz`.
    public static func toJzAzBz(_ jch: SIMD3<Double>) -> SIMD3<Double> {
        let angle = 2.0 * Double.pi * jch.z
        return SIMD3(jch.x, cos(angle) * jch.y, sin(angle) * jch.y)
    }

    // MARK: Full chain — pipeline RGB ⇄ JzCzhz (linear Rec2020)

    /// Linear Rec2020 → JzCzhz (the full five-leg chain, Double).
    public static func fromRGB(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let xyz = matVec(LabRoundTrip.rec2020ToXYZ, rgb)
        return fromJzAzBz(ColorBalanceRGBMath.xyzToJzAzBz(xyz))
    }

    /// JzCzhz → linear Rec2020 (the exact inverse chain).
    public static func toRGB(_ jch: SIMD3<Double>) -> SIMD3<Double> {
        let xyz = ColorBalanceRGBMath.jzAzBzToXYZ(toJzAzBz(jch))
        return matVec(LabRoundTrip.xyzToRec2020, xyz)
    }

    /// Row-major matrix × vector (the LabRoundTrip helper shape; local so
    /// the constant stays dependency-free).
    private static func matVec(_ m: [[Double]], _ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z,
            m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
            m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z)
    }

    /// dt hue shortest-path interpolation (blendop.cl:713-733, the Lab LCh
    /// formula family the perceptual modes are defined from — hz in turns):
    ///
    ///   d = |hz_a − hz_b|;  s = d > 0.5 ? −op·(1−d)/d : op
    ///   hz = fmod(hz_a·(1−s) + hz_b·s + 1, 1)
    ///
    /// d == 0 (identical hues) takes the s = op branch — exact.
    public static func mixedHue(_ ha: Double, _ hb: Double, opacity: Double) -> Double {
        let d = abs(ha - hb)
        let s = d > 0.5 ? -opacity * (1.0 - d) / d : opacity
        let v = (ha * (1.0 - s)) + (hb * s) + 1.0
        return v - v.rounded(.down) // fmod positive: v ≥ 1 > 0
    }
}

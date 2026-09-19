import simd

// ─────────────────────────────────────────────────────────────────────────
// LabRoundTrip (Plan 03-03-T1) — the CPU half of the shared Lab-domain
// component for the display-referred iops (colisa / tonecurve / levels /
// shadhi). The Metal half is `Common/LabMath.h` (+ `LabKernels.metal`
// standalone passes); BOTH sides use the identical constants, and
// `LabRoundTripTests` pins them against each other.
//
// DECISION (Plan 03-03 Goal, RESEARCH Open#3 closed): the four Lab modules
// convert Rec2020→Lab→Rec2020 INSIDE each module — the working space stays
// linear Rec2020 scene-referred; there is NO pipeline-level Lab domain in
// v1 (Phase 5+ optimization, RESEARCH Open#9: adjacent Lab modules could
// share one conversion). This component is LightamerIOP-internal shared
// infrastructure: it lives in `Sources/Common/` and carries no module
// identity.
//
// MATRIX PROVENANCE (identical to LabMath.h — the comment there is the
// canonical statement):
//   - Rec2020→XYZ: ITU BT.2020 primaries + D65 — the project's single
//     constant set (shared with `WhiteBalanceMath.rec2020ToXYZ` and
//     gen_fixtures.py `REC2020_TO_XYZ`).
//   - Bradford D65→D50: published 7-digit matrix (lcms-aligned semantics).
//   - Lab reference white: bradford × rec2020ToXYZ × (1,1,1) — the
//     Rec2020 pipeline white through the SAME constants. Consequence:
//     every neutral (r==g==b) maps to a==b==0 EXACTLY (both branches of
//     f() are homogeneous), so Lab-domain saturation/contrast ops add no
//     chroma noise on neutrals. The known-vector tests assert this to
//     Double precision.
//   - Lab math: standard CIE with dt's constants (κ = 24389/27,
//     ε = 216/24389) and dt's function shapes (cbrt forward / cube
//     inverse — colorspaces_inline_conversions.h:148-205): defined for
//     out-of-domain negatives (spectral fixtures carry them).
// ─────────────────────────────────────────────────────────────────────────

public enum LabRoundTrip {

    // MARK: Constants (mirrored in Common/LabMath.h)

    /// Linear Rec2020 → XYZ (D65) — ITU BT.2020 (project-wide constants).
    public static let rec2020ToXYZ: [[Double]] = [
        [0.636958, 0.144617, 0.168881],
        [0.262700, 0.678009, 0.059291],
        [0.000000, 0.028073, 1.060806],
    ]

    /// XYZ (D65) → linear Rec2020 — exact inverse of `rec2020ToXYZ`.
    public static let xyzToRec2020: [[Double]] = invert(rec2020ToXYZ)

    /// Bradford chromatic adaptation D65 → D50 (published 7-digit matrix).
    public static let bradfordD65ToD50: [[Double]] = [
        [1.0478112, 0.0228866, -0.0501270],
        [0.0295424, 0.9904844, -0.0170491],
        [-0.0092345, 0.0150436, 0.7521316],
    ]

    /// Bradford D50 → D65 — exact inverse of `bradfordD65ToD50`.
    public static let bradfordD50ToD65: [[Double]] = invert(bradfordD65ToD50)

    /// The Lab reference white: bradford × rec2020ToXYZ × (1,1,1) —
    /// (0.9642028042742, 0.9999987443755, 0.8252469185444). NOT the rounded
    /// ICC D50 (0.9642, 1, 0.8249): anchoring to the pipeline's own white
    /// is what makes neutrals exact.
    public static let labReferenceWhite: SIMD3<Double> = mulMatrix(
        bradfordD65ToD50, mulMatrix(rec2020ToXYZ, SIMD3(1, 1, 1))
    )

    /// CIE constants (dt colorspaces_inline_conversions.h:150-151).
    public static let epsilon: Double = 216.0 / 24389.0
    public static let kappa: Double = 24389.0 / 27.0

    // MARK: Conversion (Double — the CPU reference path)

    /// CIE Lab f(): cbrt above ε (signed — defined for negatives), linear
    /// below (dt's cbrtf shape).
    static func labF(_ t: Double) -> Double {
        t > epsilon ? cbrt(t) : (kappa * t + 16.0) / 116.0
    }

    /// dt `lab_f_inv` (colorspaces_inline_conversions.h:179-186).
    static func labFInverse(_ x: Double) -> Double {
        x > 0.20689655172413796 ? x * x * x : (116.0 * x - 16.0) / kappa
    }

    /// Linear Rec2020 → CIE Lab (L, a, b). Neutrals → a == b == 0 exactly;
    /// no clamping (out-of-domain in and out both stay defined).
    public static func rec2020ToLab(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let xyz50 = mulMatrix(bradfordD65ToD50, mulMatrix(rec2020ToXYZ, rgb))
        let fx = labF(xyz50.x / labReferenceWhite.x)
        let fy = labF(xyz50.y / labReferenceWhite.y)
        let fz = labF(xyz50.z / labReferenceWhite.z)
        return SIMD3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))
    }

    /// CIE Lab → Bradford-adapted D50 XYZ (Y ∈ [0,1] display range; the
    /// intermediate domain tonecurve's XYZ-linked mode maps through).
    public static func labToXYZ50(_ lab: SIMD3<Double>) -> SIMD3<Double> {
        let fy = (lab.x + 16.0) / 116.0
        let fx = fy + lab.y / 500.0
        let fz = fy - lab.z / 200.0
        return labReferenceWhite * SIMD3(
            labFInverse(fx), labFInverse(fy), labFInverse(fz)
        )
    }

    /// Bradford-adapted D50 XYZ → CIE Lab (inverse of `labToXYZ50`).
    public static func xyz50ToLab(_ xyz: SIMD3<Double>) -> SIMD3<Double> {
        let fx = labF(xyz.x / labReferenceWhite.x)
        let fy = labF(xyz.y / labReferenceWhite.y)
        let fz = labF(xyz.z / labReferenceWhite.z)
        return SIMD3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))
    }

    /// CIE Lab → linear Rec2020 (exact inverse of `rec2020ToLab`).
    public static func labToRec2020(_ lab: SIMD3<Double>) -> SIMD3<Double> {
        mulMatrix(xyzToRec2020, mulMatrix(bradfordD50ToD65, labToXYZ50(lab)))
    }

    // MARK: Float32 conveniences (kernel-mirror evaluation in CPU tests)

    public static func rec2020ToLabF(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(rec2020ToLab(SIMD3<Double>(rgb)))
    }

    public static func labToRec2020F(_ lab: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(labToRec2020(SIMD3<Double>(lab)))
    }

    // MARK: Matrix helpers

    static func mulMatrix(_ m: [[Double]], _ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(
            m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z,
            m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
            m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z
        )
    }

    static func invert(_ m: [[Double]]) -> [[Double]] {
        let a = m[0], b = m[1], c = m[2]
        let det = a[0] * (b[1] * c[2] - b[2] * c[1])
            - a[1] * (b[0] * c[2] - b[2] * c[0])
            + a[2] * (b[0] * c[1] - b[1] * c[0])
        return [
            [
                (b[1] * c[2] - b[2] * c[1]) / det,
                (a[2] * c[1] - a[1] * c[2]) / det,
                (a[1] * b[2] - a[2] * b[1]) / det,
            ],
            [
                (b[2] * c[0] - b[0] * c[2]) / det,
                (a[0] * c[2] - a[2] * c[0]) / det,
                (a[2] * b[0] - a[0] * b[2]) / det,
            ],
            [
                (b[0] * c[1] - b[1] * c[0]) / det,
                (a[1] * c[0] - a[0] * c[1]) / det,
                (a[0] * b[1] - a[1] * b[0]) / det,
            ],
        ]
    }
}

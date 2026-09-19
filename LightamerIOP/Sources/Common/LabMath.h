//
//  LabMath.h — Metal-side linear-Rec2020 ⇄ CIE Lab conversion (Plan 03-03-T1)
//
//  Shared inline component for the display-referred Lab-domain iops
//  (colisa / tonecurve / levels / shadhi). Included by each module's
//  .metal file (`#include "../Common/LabMath.h"`) so a module kernel does
//  the Rec2020→Lab transform, the Lab-domain operation, and the inverse
//  transform in ONE pass (dt does the equivalent via pixelpipe colorspace
//  conversions around IOP_CS_LAB modules — RESEARCH §Summary#3).
//
//  MATRIX PROVENANCE (documented decision, Plan 03-03 Goal):
//    - rec2020→XYZ : ITU BT.2020 primaries + D65 — the SAME 7-digit
//      constants as `WhiteBalanceMath.rec2020ToXYZ` (03-02) and
//      gen_fixtures.py `REC2020_TO_XYZ` (03-01). One constant set for the
//      whole project.
//    - Bradford adaptation D65→D50 : the published 7-digit Bradford
//      matrix (Lindbloom / ICC semantics — dt aligns through lcms).
//    - Lab reference white = bradford × (rec2020→XYZ) × (1,1,1) — the
//      Rec2020 pipeline white through the SAME constants. This anchoring
//      makes EVERY neutral (r==g==b) map to a==b==0 exactly, so the Lab
//      modules add zero chroma noise on neutrals (track-B criterion) and
//      the known-vector tests hold to float precision.
//    - Lab math = standard CIE with dt's constants (κ = 24389/27,
//      ε = 216/24389) and dt's function SHAPES (cbrt forward, cube
//      inverse — colorspaces_inline_conversions.h:148-205), which stay
//      well-defined for out-of-domain negatives (spectral fixtures).
//
//  L006: float32 only — no half anywhere in the pipe.
//

#ifndef LABMATH_H
#define LABMATH_H

#include <metal_stdlib>
using namespace metal;

// Linear Rec2020 → XYZ (D65), row-major 3×3 (BT.2020 constants).
constant float la_rec2020_to_xyz[9] = {
    0.636958, 0.144617, 0.168881,
    0.262700, 0.678009, 0.059291,
    0.000000, 0.028073, 1.060806,
};

// XYZ (D65) → linear Rec2020 — exact inverse of the matrix above
// (computed in Double at design time; constant-folded here).
constant float la_xyz_to_rec2020[9] = {
    1.716647800, -0.355662540, -0.253412603,
    -0.666671725, 1.616451804, 0.015787188,
    0.017642694, -0.042777522, 0.942261645,
};

// Bradford chromatic adaptation D65 → D50 (published 7-digit matrix).
constant float la_bradford_d65_d50[9] = {
    1.0478112, 0.0228866, -0.0501270,
    0.0295424, 0.9904844, -0.0170491,
    -0.0092345, 0.0150436, 0.7521316,
};

// Bradford D50 → D65 (exact inverse of the matrix above).
constant float la_bradford_d50_d65[9] = {
    0.955576656, -0.023039343, 0.063163668,
    -0.028289547, 1.009941621, 0.021007661,
    0.012298179, -0.020483004, 1.329909891,
};

// The Lab reference white: bradford × rec2020ToXYZ × (1,1,1) —
// (0.964202804274, 0.999998744376, 0.825246918544). Neutrals map to
// a==b==0 exactly by construction.
constant float3 la_lab_white = float3(0.964202804274200, 0.999998744375500, 0.825246918544400);

// CIE Lab constants (dt colorspaces_inline_conversions.h:150-151).
constant float la_epsilon = 216.0f / 24389.0f;
constant float la_kappa = 24389.0f / 27.0f;

// Metal has no cbrt(); signed 1/3-exponent powr (~2 ulp). The inverse
// leg compresses the error (÷116 then cube), keeping the GPU round-trip
// inside its 1e-6 gate (LabRoundTripTests).
inline float la_cbrt(float t) {
    return (t < 0.0f) ? -powr(-t, 0.33333333333333331f) : powr(t, 0.33333333333333331f);
}

inline float3 la_mul9(constant float* m, float3 v) {
    return float3(
        m[0] * v.x + m[1] * v.y + m[2] * v.z,
        m[3] * v.x + m[4] * v.y + m[5] * v.z,
        m[6] * v.x + m[7] * v.y + m[8] * v.z);
}

// CIE Lab f(): dt's shape — signed cbrt above ε, linear below (the cbrt
// keeps out-of-domain negatives defined; dt uses cbrtf for the same
// reason at colorspaces_inline_conversions.h:157).
inline float la_lab_f(float t) {
    return (t > la_epsilon) ? la_cbrt(t) : (la_kappa * t + 16.0f) / 116.0f;
}

// dt lab_f_inv (colorspaces_inline_conversions.h:179-186) verbatim shape.
inline float la_lab_f_inv(float x) {
    return (x > 0.20689655172413796f) ? x * x * x : (116.0f * x - 16.0f) / la_kappa;
}

/// Linear Rec2020 (r==g==b neutral stays neutral exactly) → CIE Lab,
/// Bradford-adapted to the Rec2020-D65 pipeline white. L ∈ rgb.x,
/// a ∈ rgb.y, b ∈ rgb.z. No clamping — out-of-domain values stay defined.
inline float3 la_rec2020_to_lab(float3 rgb) {
    float3 xyz50 = la_mul9(la_bradford_d65_d50, la_mul9(la_rec2020_to_xyz, rgb));
    float fx = la_lab_f(xyz50.x / la_lab_white.x);
    float fy = la_lab_f(xyz50.y / la_lab_white.y);
    float fz = la_lab_f(xyz50.z / la_lab_white.z);
    return float3(116.0f * fy - 16.0f, 500.0f * (fx - fy), 200.0f * (fy - fz));
}

/// CIE Lab → Bradford-adapted D50 XYZ (the intermediate domain dt's
/// tonecurve XYZ-linked mode maps through; Y ∈ [0,1] for display range).
inline float3 la_lab_to_xyz(float3 lab) {
    float fy = (lab.x + 16.0f) / 116.0f;
    float fx = fy + lab.y / 500.0f;
    float fz = fy - lab.z / 200.0f;
    return la_lab_white * float3(la_lab_f_inv(fx), la_lab_f_inv(fy), la_lab_f_inv(fz));
}

/// Bradford-adapted D50 XYZ → CIE Lab (inverse of la_lab_to_xyz).
inline float3 la_xyz_to_lab(float3 xyz) {
    float fx = la_lab_f(xyz.x / la_lab_white.x);
    float fy = la_lab_f(xyz.y / la_lab_white.y);
    float fz = la_lab_f(xyz.z / la_lab_white.z);
    return float3(116.0f * fy - 16.0f, 500.0f * (fx - fy), 200.0f * (fy - fz));
}

/// CIE Lab → linear Rec2020 (exact inverse of la_rec2020_to_lab).
inline float3 la_lab_to_rec2020(float3 lab) {
    float3 xyz50 = la_lab_to_xyz(lab);
    return la_mul9(la_xyz_to_rec2020, la_mul9(la_bradford_d50_d65, xyz50));
}

#endif // LABMATH_H

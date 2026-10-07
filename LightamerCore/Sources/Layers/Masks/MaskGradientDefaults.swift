import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MaskGradientDefaults (Plan M2-7-1 T2, KD-2; M2MASK-02) — the SINGLE SOURCE
// for the Alcedo LinearGradient → dt GradientForm mapping constants.
//
// ZERO schema change: the mapping reuses GradientForm verbatim (D-M2-7-CONTEXT-1);
// only the DEFAULT VALUE equivalence between the two parameter spaces is pinned
// here, derived once and consumed by the P2 panel. The equivalence goldens live
// in MaskFeatherAlignTests (plane-sampled ≤1e-6 on the square reference
// window, τ=0.2 default档 + τ=1.0 scale档).
//
// DERIVATION (line-referenced; both formulas read verbatim):
//
//   dt kernel (MaskRasterKernels.metal gradient段, dt gradient.c:1176-1232):
//     y0 = (sin v·px − cos v·py − yoff) · hwscale, hwscale = 1/√(wd²+ht²)
//     value = 0.5 + 0.5 · y0 / compression        (linear, curvature 0)
//   → the value-1 direction is −(sin rot, cos rot) in pixel space; the
//     plane transitions 0→1 across Δy0 = 2·compression (half-diagonal units).
//
//   Alcedo (grade_mask_coverage.cpp:155-158, Linear branch):
//     d = (n − origin)·n̂          (n in [0,1]² rectangular-normalized)
//     t = clamp(d / transition_distance + 0.5, 0, 1); value = start − t
//   → the value-1 direction is −n̂; the plane transitions across Δd = τ.
//
//   Direction: −(sin rot, cos rot) = −n̂ ⟹ rotation = atan2(nx, ny)
//   (rotation 0 ⇔ normal (0,1); pinned by testGradientDirectionSignAnchors).
//
//   Bandwidth on the SQUARE reference window (wd = ht = s, halfDiag = s√2,
//   normal (0,1)): y0 = (anchor_y·ht − py)·ht⁻¹·(ht/halfDiag) = −d·ht/halfDiag
//   = −d/√2. Equating the two value ramps, 0.5 + y0/(2c) = 0.5 − d/τ:
//     2·c·√2 = τ   ⟹   compression = τ / (2·√2)
//
//   τ = 0.2 (Alcedo's default transition_distance) → compression =
//   0.2/(2√2) ≈ 0.0707107. The constant is exact on square windows and is
//   the canonical reference-space default; non-square windows carry the
//   same slider semantics (profile width in half-diagonal units).
// ─────────────────────────────────────────────────────────────────────────────

public enum MaskGradientDefaults {

    /// The compression slider default equivalent to Alcedo's default
    /// linear-gradient transition band (transition_distance = 0.2 in the
    /// normalized reference space): τ/(2·√2). Derived and golden-pinned in
    /// MaskFeatherAlignTests (KD-2) — do not re-derive at call sites.
    public static let compressionDefault: Float = 0.2 / (2.0 * Float(2.0).squareRoot())

    /// The Alcedo reference transition band this default encodes (the P2
    /// panel's "Advanced" fold may surface the equivalence).
    public static let alcedoReferenceTransition: Float = 0.2
}

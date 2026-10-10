import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────────
// ColorMatchBake (Plan M5-1-02 T3, KD-3; OQ-4) — the S2 arm's 65³ Float64
// bake: the CDF ladders baked into a Float32 3D table over the WORKING
// linear Rec2020 unit cube (the application domain IS the working space —
// OQ-2: the linear arm carries no encoding semantics, LutEncodingCatalog
// zero-touched).
//
// PER VOXEL (Float64 channel math, the FilmPrintBake 体例):
//   rgb64   = lattice coordinate (the Rec2020 [0,1]³ normalised domain)
//   lab     = Oklab64(rgb64)                       (OklabMath golden twin)
//   mapped  = per-channel CDF ladder read (step — binIndex clamp = the
//             domain-end plateau; the trim plateaus are inside the curves)
//   out_lab = (1−α)·lab + α·mapped                 (the α-lerp, Oklab
//             domain — the SAME strength semantics the linear arm's
//             kernel expands, adjudicated FOLDED INTO THE BAKE here)
//   rgb_out = Oklab64⁻¹(out_lab)                   (Float32 STORAGE — the
//             single demotion point)
//
// STRENGTH IS A BAKE INPUT (the explicit ruling): strength never rides
// the table SAMPLING — dragging α re-bakes (the identity is
// `bakeKey = fnv(solutionHash ⊕ α bits)`, LRU 16 at the module). The
// asset lands ONLY at commit time (zero IO per tick); the persisted
// table is the committed α's bytes.
//
// PLATEAU EDGES (OQ-4): the lattice coordinates ARE the [0,1] clamp —
// the end voxels carry the clamped-coordinate values (the ladder's own
// end bins + the trim plateaus), and the SAMPLING side (the shared
// lut3d_tetrahedral kernel) clamps out-of-domain inputs into the same
// end voxels via its domain uniforms. HDR >1 inputs land on the end
// voxel = the adjudicated policy (the panel's readout discloses the
// support width).
//
// DETERMINISM (G1): Float64 math + `concurrentPerform` per lattice slice
// with the fixed index merge (no await, no reduction order dependence) —
// a double bake of the same (solution, α) is BIT-IDENTICAL.
// ─────────────────────────────────────────────────────────────────────────────

public enum ColorMatchBake {

    /// The lattice level (65 — the FilmPrintBake/film composite convention).
    public static let latticeSize = 65

    /// The bake key: `fnv(solutionHash ⊕ α bits)` — little-endian raw bytes
    /// chained over FNV-1a (the solve-cache fold 体例). The module's bake
    /// LRU keys on this.
    public static func bakeKey(solutionHash: UInt64, strength: Float) -> UInt64 {
        var h = StableHash.fnvOffsetBasis
        withUnsafeBytes(of: solutionHash) { h = StableHash.combine(h, $0) }
        var bits = strength.bitPattern
        h = withUnsafeBytes(of: &bits) { StableHash.combine(h, $0) }
        return h
    }

    /// The IDEAL continuous model — the same formula evaluated directly at
    /// an arbitrary Rec2020 coordinate (no lattice quantization). The
    /// golden gate measures the baked voxels against this (the bake inner
    /// loop calls this face verbatim, so the test's independent reference
    /// is the formula spelled out — same math, separately written).
    @inline(__always)
    public static func evaluateVoxel64(
        _ rgb: SIMD3<Double>, solution: ColorMatchCDFSolution, strength: Double
    ) -> SIMD3<Double> {
        let lab = OklabMath.linearRec2020ToOklab64(rgb)
        // The ladder read: the Float32 domain map's bin index (end clamp).
        let mapped = SIMD3<Double>(
            solution.evaluate(channel: 0, value: Float(lab.x)),
            solution.evaluate(channel: 1, value: Float(lab.y)),
            solution.evaluate(channel: 2, value: Float(lab.z)))
        let outLab = lab + strength * (mapped - lab)
        return OklabMath.oklabToLinearRec202064(outLab)
    }

    /// Bake the 65³ table. Float64 channel math; lattice slices run on the
    /// cooperative-perform pool (fixed index merge — no reduction).
    public static func bake(
        solution: ColorMatchCDFSolution, strength: Float
    ) -> [SIMD3<Float>] {
        let level = latticeSize
        let count = level * level * level
        var table = [SIMD3<Float>](repeating: .zero, count: count)
        let alpha = Double(strength)
        table.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: level) { z in
                let dz = Double(z) / Double(level - 1)
                for y in 0..<level {
                    let dy = Double(y) / Double(level - 1)
                    let base = z * level * level + y * level
                    for x in 0..<level {
                        let rgb = SIMD3<Double>(
                            Double(x) / Double(level - 1), dy, dz)
                        let out = evaluateVoxel64(rgb, solution: solution, strength: alpha)
                        buffer[base + x] = SIMD3<Float>(
                            Float(out.x), Float(out.y), Float(out.z))
                    }
                }
            }
        }
        return table
    }
}

import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ColormatchUniforms (Plan M5-1-01 T6, KD-6) — the flat uniform ABI of
// `colormatch_linear`. Zero function constants; 13 packed floats = 52 bytes
// (MSL float alignment 4 → no padding holes on either side; the size probe
// in ColormatchKernelParityTests pins the stride).
//
// PAYLOAD (the KD-6 recommended α-invariant expansion — strength drags
// re-run NO solve):
//     out_oklab = x + α·((M−I)·x + c)
// with mi = (M−I) row-major Float32, c = μt − M·μs (the ColorMatchSolution
// offset — the α-invariant constant), α = strength. The demotion point for
// both terms is `ColorMatchSolver.strengthKernelTerms` (one spelling).
// ─────────────────────────────────────────────────────────────────────────────

/// The MSL uniform mirror (`ColorMatchKernels.metal` — field-for-field).
/// All-Float flat struct: 9 (M−I row-major) + 3 (c) + 1 (strength) = 13
/// floats, 52 bytes, no function constants.
struct ColormatchUniforms {
    var mi0: Float = 0; var mi1: Float = 0; var mi2: Float = 0
    var mi3: Float = 0; var mi4: Float = 0; var mi5: Float = 0
    var mi6: Float = 0; var mi7: Float = 0; var mi8: Float = 0
    var c0: Float = 0; var c1: Float = 0; var c2: Float = 0
    var strength: Float = 0

    /// The stride probe face (the ABI pin — must equal the MSL struct size
    /// 52; a field change flips the parity test's size assertion red).
    static let expectedStride: Int = 52

    var strideBytes: Int { MemoryLayout<Self>.stride }

    mutating func setMi(_ v: [Float]) {
        precondition(v.count == 9)
        mi0 = v[0]; mi1 = v[1]; mi2 = v[2]
        mi3 = v[3]; mi4 = v[4]; mi5 = v[5]
        mi6 = v[6]; mi7 = v[7]; mi8 = v[8]
    }
    mutating func setC(_ v: [Float]) {
        precondition(v.count == 3)
        c0 = v[0]; c1 = v[1]; c2 = v[2]
    }
}

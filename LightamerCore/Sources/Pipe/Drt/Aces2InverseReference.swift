import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────────
// Aces2InverseReference — the Float64 reference implementation of the ACES 2.0
// OUTPUT transform INVERSE (Plan M4-1-01 T4, KD-3) — the raster input leg's
// authority. Same-directory sibling of `Aces2Reference` (the forward): it
// reuses the forward's parameter build (`Aces2Reference.params(space:peak:
// rgcOn:)` — the inverse leg ALWAYS passes rgcOn:false, KD-9: no RGC in any
// direction) and the forward's stage machinery (compressGamut carries the
// invert: face, chromaCompressInv/tonescaleInv were ported both directions
// in M2-6-2), adding only the inverse-side orchestration the forward never
// had. NO forward file's algorithm body is touched by this port (the
// Aces2Kernels.metal zero-diff red line).
//
// PORTED FROM aces-core (upstream SHA 069b0bc3e1f6c62820f19fdae2fecec3f4fc0
// f80, v2.0 main, 2026-09-01; Apache-2.0 — Portions Copyright Contributors
// to the ACES Project; see NOTICE §2, the inverse function list added
// additively by M4-1-01):
//   • `lib/Lib.Academy.OutputTransform.ctl` — outputTransform_inv
//     (:1690-1700), tonemap_and_compress_inv (:544-560), gamut_compress_inv
//     (:890-917). The rest of the call graph (RGB_to_JMh, JMh_to_RGB,
//     chroma_compress_inv :492-532, compress_gamut :728-774,
//     init_HueDependentGamutParams :850-864) landed with the forward port
//     (M2-6-2) and is REUSED here — the anchors for those live in
//     Aces2Reference.swift.
//   • `lib/Lib.Academy.Tonescale.ctl` — tonescale_inv (:88-97), ported both
//     directions in M2-6-2, reused.
// NOT ported (the OQ-3 effective ruling): the RGC inverse — no RGC inverse
// exists in the upstream either; the raster document policy keeps RGC OFF
// for the aces20 arm on both directions (KD-9), which dissolves the
// double-compression the forward's RGC pass would otherwise stack.
//
// ═══ INVERSE STAGE MAP (stage numbers = the forward's shared vocabulary,
//     primed; † = new in this file) ═══
//
//   [i7']† ×(peak/100) — the EotfBox contract inverse (the leg input is
//         peak-normalized display linear, 1.0 = peak nits; the upstream
//         hands JMh_to_RGB output in 100-nit units).
//   [i6'] RGB→JMh (limit_params = the limiting space) — the inverse of
//         forward [6]. The LIMITING gamut for the raster leg is the SOURCE
//         primaries (OQ-2 effective value ② — the description's gamut).
//   [i5']† gamut_compress_inv — ≤2 closed-form estimates (the second
//         compress_gamut evaluation consumes the first's Jx; no loop — the
//         upstream shape verbatim).
//   [i4']† tonemap_and_compress_inv — ORDER = DATA-DEPENDENCY ORDER, not
//         the forward's combination order: tonescale_inv FIRST restores
//         the ORIGINAL (pre-tonemap) J, then chroma_compress_inv consumes
//         that J to un-compress M (upstream :544-560 — "Applies the
//         inverse tonescale, then uncompresses M"; chroma_compress_inv
//         needs the restored J as its rescale denominator input, the
//         dependency is hard). Re-run note for the reader who arrived via
//         RESEARCH §3.3's unordered bullet: the plan's stage table states
//         the same thing — [4'] = tonescale_inv → chroma_compress_inv.
//   [i3'] JMh→RGB (input_params = AP0) — the inverse of forward [3]
//         (upstream carries AP0 scene-linear out of the inverse; our
//         forward consumes AP0 after [2]).
//   [i0']† AP0 → linear Rec2020 — the working-space exit (ap0ToRec2020,
//         the forward [0]'s inverse). THE structural divergence from the
//         upstream (which encodes ACEScc AP1 for its develop graph): our
//         pixelpipe working space is linear Rec2020 float32, so the
//         inverse exits there and the DRT tail's forward re-enters via
//         its own [0].
//   ([1] RGC / [2] clampAP0ToAP1 carry NO inverse segment: RGC is off for
//   raster documents (KD-9), and legal display-domain values invert into
//   AP1 by construction.)
//
//   FMA DISCIPLINE (KD-3, the upstream macOS R1-1 lesson): the near-black
//   round-trip sentinel lives in the golden tests (T5). The Swift Float64
//   side is not fast-math'ed (swiftc does not contract without fast-math);
//   the Metal side mirrors the same formulas in float and the kernel parity
//   golden (T8) carries the dual-judgment gate. A near-black miss is FMA
//   suspicion FIRST — pragma/flag treatment, not tolerance widening.
// ─────────────────────────────────────────────────────────────────────────────

enum Aces2InverseReference {

    /// `outputTransform_inv` (:1690-1700) + the EotfBox contract inverse
    /// ([i7']) + the working-space exit ([i0']) — ONE pixel of the raster
    /// input leg's display branch.
    ///
    /// - Parameters:
    ///   - p: the parameter point — build via
    ///     `Aces2Reference.params(space:peak:rgcOn:)` with the raster
    ///     policy values (limiting = source primaries, rgcOn: false).
    ///   - displayLinearPeakNormalized: the linearized display-linear RGB
    ///     in the limiting primaries, 1.0 = peak nits (the EotfBox
    ///     contract face the linearize step produces).
    /// - Returns: scene-linear linear Rec2020 (the working space).
    static func runPixel(
        _ p: Aces2Reference.Params, _ displayLinearPeakNormalized: SIMD3<Double>
    ) -> SIMD3<Double> {
        // [i7'] EotfBox contract inverse: 1.0 = peak nits → 1.0 = 100 nits.
        let rgb = displayLinearPeakNormalized * (p.peak / Aces2Cam.refLuminance)
        // [i6'] display RGB → JMh against the limiting gamut.
        let compressedJMh = Aces2Cam.rgbToJMh(rgb, p.limitParams)
        // [i5'] the gamut-compression inverse (≤2 estimates).
        let tonemappedJMh = gamutCompressInv(compressedJMh, p)
        // [i4'] the tonescale inverse restores J, then the chroma inverse
        // consumes it (the data-dependency order — see the stage map).
        let jmh = tonemapAndCompressInv(tonemappedJMh, p)
        // [i3'] JMh → AP0 scene-linear.
        let aces = Aces2Cam.jmhToRGB(jmh, p.inputParams)
        // [i0'] AP0 → linear Rec2020 (the working space).
        return Aces2Cam.ap0ToRec2020.multiply(aces)
    }

    /// `tonemap_and_compress_inv` (:544-560) — the inverse tonescale FIRST
    /// (restoring the original J), then the chroma-compression inverse
    /// consuming that J ("Applies the inverse tonescale, then uncompresses
    /// M" — the upstream comment verbatim in meaning).
    static func tonemapAndCompressInv(
        _ jmhTc: SIMD3<Double>, _ p: Aces2Reference.Params
    ) -> SIMD3<Double> {
        // Un-tonemap: J_ts → Y → scene-linear → the original J.
        let luminance = Aces2Reference.jToY(jmhTc.x, p.inputParams)
        let linear = Aces2Reference.tonescaleInv(
            luminance / Aces2Cam.refLuminance, p.ts)
        let j = Aces2Reference.yToJ(linear * Aces2Cam.refLuminance, p.inputParams)
        // Un-compress M against the restored J.
        return Aces2Reference.chromaCompressInv(jmhTc, j, p)
    }

    /// `gamut_compress_inv` (:890-917) — closed form, no iteration: at
    /// most TWO `compress_gamut` evaluations (the first estimates Jx above
    /// the analytic threshold, the second inverts with it).
    static func gamutCompressInv(
        _ jmh: SIMD3<Double>, _ p: Aces2Reference.Params
    ) -> SIMD3<Double> {
        let j = jmh.x
        let m = jmh.y
        let h = jmh.z
        if j <= 0 { return SIMD3(0, 0, h) }
        if m < 0 || j > p.limitJMax { return SIMD3(j, 0, h) }
        let hdp = Aces2Reference.initHueDependentGamutParams(h, p)
        var jx = j
        if jx > hdp.analyticalThreshold {
            jx = Aces2Reference.compressGamut(jmh, jx, p, hdp, invert: true).x
        }
        return Aces2Reference.compressGamut(jmh, jx, p, hdp, invert: true)
    }
}

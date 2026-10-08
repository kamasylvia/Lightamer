// ─────────────────────────────────────────────────────────────────────────
// FilmPlacementKernels.metal (Plan M3-3-02 T4, KD-5) — the filmPlacement
// scene-placement curve (RFC-023 §5.4/§5.6 formula-level transcription,
// GPL code NOT copied; SpektraLab rfc/RFC-023 is the math reference).
//
// The op places the subject's exposure on the print: an EXACT identity core
// between two knees, with smooth-min compression branches beyond them:
//   g_m(Δ) = Δ·(1 + (Δ/H)^m)^(−1/m)          (the smooth-min family)
//   f(E)   = K_h + g_m(E − K_h)   (E > K_h)  highlight branch
//   f(E)   = K_s − g_m(K_s − E)   (E < K_s)  shadow branch
//   f(E)   = E                    (core)     EXACT identity
// The kernel computes the DELTA (RFC-023 §5.6's bit-exact discipline):
//   δ(E) = ±(Δ − g_m(Δ)),  k = exp2(δ),  RGB' = k·RGB
// — log2/exp2 touch only the SCALAR gain; the signal stays scene-linear
// (re-encoded to ACEScc because the op runs inside the grade envelope).
//
// The knees/rooms arrive CPU-SOLVED (FilmPlacementModule.commitParams —
// RFC-023 §9.2: K and H are derived, never typed; the simplified
// descriptor-absent arm parameterizes them from the two pull-backs).
// Both flags 0 = the identity early exit — byte-identical copy (the
// kernel no-op point the GradeCatalog identityJSON pins).
// ─────────────────────────────────────────────────────────────────────────
#include <metal_stdlib>
#include "../ACEScc/ACESccMath.metal"
using namespace metal;

struct FilmPlacementUniforms {
    float K_h;      // highlight knee (stops rel. mid-gray)
    float H_h;      // highlight room (knee → medium boundary)
    float K_s;      // shadow knee
    float H_s;      // shadow room
    float m;        // roll-off order [1, 8]
    float flagHi;   // 1 = highlight branch armed (pull-back > 0)
    float flagLo;   // 1 = shadow branch armed
    float nFloor;   // the scalar norm's floor (n_ref · 2^−24)
};

kernel void film_placement(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant FilmPlacementUniforms& u   [[buffer(0)]],
    uint2 gid                           [[thread_position_in_grid]])
{
    float4 c = in.read(gid);
    if (u.flagHi < 0.5f && u.flagLo < 0.5f) {
        out.write(c, gid);   // the identity core op-wide: bit-exact copy
        return;
    }
    float3 lin = float3(acescc_decode(c.x), acescc_decode(c.y), acescc_decode(c.z));
    // The scalar magnitude (RFC-023 §5.2's power norm — the §15.5
    // recommendation: Y under-reports two-channel-black pixels and hands
    // them the largest shadow gain; the power norm tracks max(RGB,0) there).
    float ss = lin.r * lin.r + lin.g * lin.g + lin.b * lin.b;
    float n = ss > 0.0f
        ? (lin.r * lin.r * lin.r + lin.g * lin.g * lin.g + lin.b * lin.b * lin.b) / ss
        : 0.0f;
    const float nRef = 0.184f;   // metered mid-gray (the axis origin)
    float E = log2(max(n, u.nFloor) / nRef);
    // At most one branch is live per pixel (K_s < K_h by construction).
    float delta, room, sign;
    if (u.flagHi > 0.5f && E > u.K_h) {
        delta = E - u.K_h; room = u.H_h; sign = -1.0f;   // highlights pulled down
    } else if (u.flagLo > 0.5f && E < u.K_s) {
        delta = u.K_s - E; room = u.H_s; sign = +1.0f;   // shadows pulled up
    } else {
        out.write(c, gid);   // in the core: the RAW pixel verbatim (δ ≡ 0)
        return;
    }
    // g_m(Δ) and its delta form: δ = Δ − g_m(Δ), written without the
    // cancellation (RFC-023 §5.6) — expand for stability at small Δ:
    //   Δ − Δ(1+w)^(−1/m) = Δ·(1 − (1+w)^(−1/m)), w = (Δ/H)^m
    float w = precise::pow(delta / room, u.m);
    float d = sign * delta * (1.0f - precise::pow(1.0f + w, -1.0f / u.m));
    float k = precise::exp2(d);   // the scalar gain — the only exp2
    float3 placed = k * lin;
    out.write(
        float4(acescc_encode(placed.x), acescc_encode(placed.y), acescc_encode(placed.z), c.a),
        gid);
}

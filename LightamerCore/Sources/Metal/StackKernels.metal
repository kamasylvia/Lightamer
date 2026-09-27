#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────────
// Stack kernels (Plan 08-3 T1) — LightamerCore's own default.metallib, the
// focus-measurement leg of the StackMergeService domain.
//
// `focus_sml` — the modified-Laplacian Sum-of-Modified-Laplacian focus
// measure (Pech-Pacheco 2000; RESEARCH §5.1, the P5-probed operator):
//
//   f(x, y)      = luma (0.2126/0.7152/0.0722 — the MTB-align luma
//                  weights) of the linear float32 RGBA plane
//   ML(x, y)     = |2f − f(x−1) − f(x+1)| + |2f − f(y−1) − f(y+1)|
//   SML(x, y)    = Σ over the 3×3 window of ML²
//
// The map is stored HALF precision (research §5.4 — a quality weight needs
// no float32 dynamic range; the N=8 @100MP half map = 1.6 GB is exactly the
// residency the plan's band-streamed fusion avoids — the map is consumed
// band by band, never resident whole). Edge handling = clamp-to-edge (the
// execution decision D-08-3-T1-1; the P5 prototype clamped identically).
//
// SUBMISSION DISCIPLINE (L031 posture, D-08-3-T1-2): this kernel is the
// StackMergeService's self-contained GPU domain — it is submitted ONLY
// through `FocusMeasure.qualityMap` on the SERVICE's own dedicated
// MTLCommandQueue (never the editor/export queues; a MetalContext route
// would CREATE the cross-queue race the L031 red line exists to prevent).
// The readback is guarded by the L014 drain (the producing command buffer
// is waited BEFORE the CPU touches the output — FocusStackTests pins both
// the correctness and, with the `spin` knob, the necessity).
//
// `spin` is a TEST-ONLY knob (D-08-3-T1-3): it stalls each thread so the
// no-drain race demonstration reads a deterministically STALE output. It is
// always 0 in production.
// ─────────────────────────────────────────────────────────────────────────────

struct FocusSMLParams {
    uint32_t width;
    uint32_t height;
    uint32_t spin;
    uint32_t pad;
};

static inline float stack_luma(device const float* plane, uint2 p, uint32_t w, uint32_t h) {
    uint32_t x = min(p.x, w - 1);
    uint32_t y = min(p.y, h - 1);
    uint32_t base = (y * w + x) * 4;
    return 0.2126f * plane[base] + 0.7152f * plane[base + 1] + 0.0722f * plane[base + 2];
}

static inline float stack_ml(device const float* plane, uint2 p, uint32_t w, uint32_t h) {
    float c = stack_luma(plane, p, w, h);
    float left  = stack_luma(plane, uint2(p.x > 0 ? p.x - 1 : 0, p.y), w, h);
    float right = stack_luma(plane, uint2(min(p.x + 1, w - 1), p.y), w, h);
    float up    = stack_luma(plane, uint2(p.x, p.y > 0 ? p.y - 1 : 0), w, h);
    float down  = stack_luma(plane, uint2(p.x, min(p.y + 1, h - 1)), w, h);
    return fabs(2.0f * c - left - right) + fabs(2.0f * c - up - down);
}

kernel void focus_sml(
    device const float* plane [[buffer(0)]],
    device half*       map    [[buffer(1)]],
    constant FocusSMLParams& p [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= p.width || gid.y >= p.height) {
        return;
    }
    // Test-only stall (see header): keeps the kernel in flight long enough
    // that a no-drain readback deterministically observes the stale (zero)
    // output. The accumulator is loop-carried so it cannot be folded away.
    float dummy = 0.0f;
    for (uint32_t i = 0; i < p.spin; ++i) {
        dummy += float(i) * 1e-30f;
    }
    float sum = 0.0f;
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            int sx = int(gid.x) + dx;
            int sy = int(gid.y) + dy;
            sx = max(0, min(sx, int(p.width) - 1));
            sy = max(0, min(sy, int(p.height) - 1));
            float ml = stack_ml(plane, uint2(uint(sx), uint(sy)), p.width, p.height);
            sum += ml * ml;
        }
    }
    if (dummy == 42.0f) {
        sum += 1.0f; // unreachable (1e-30 accumulation); defeats DCE
    }
    map[gid.y * p.width + gid.x] = half(sum);
}

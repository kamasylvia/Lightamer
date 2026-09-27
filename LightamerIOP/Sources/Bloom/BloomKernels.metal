#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// Bloom kernels — Plan 08-2 T3 (op "bloom", v50 slot 61.0).
//
// Darktable reference (tree dc58cf0ba1): `src/iop/bloom.c:135-180` (the
// three-stage CPU shape) + `data/kernels/bloom.cl:22-38` (the threshold
// kernel — the port master for stage ①).
//
// THREE-STAGE ORCHESTRATION (bloom.c:135-180 structure verbatim):
//   ① bloom_threshold      — bloom.cl:22-38 direct translation with the
//                            LINEAR-domain mapping (research §9.2):
//                            L_lin = luma/4.0 · scale(strength),
//                            thr_lin = (threshold/100)³,
//                            h = L_lin > thr_lin ? L_lin : 0.
//                            dt's Lab-L [0,100] domain becomes the linear
//                            Rec2020 luma / 4.0 (4.0 = filmic white anchor,
//                            a parameterized constant — DECISIONS face);
//                            `scale = 1/exp2(−min(100,strength+1)/100)`
//                            keeps dt's exponential-brighten form (:144).
//   ② cascade blur         — the P5-measured winner (0.29s vs 1.87s
//                            3-pass box, research §9.3): ÷8 box downsample
//                            → small-σ SEPARABLE truncated gaussian at 1/8
//                            resolution (two 1-D passes; FIR not Deriche-
//                            IIR so the float64 reference is a line-by-
//                            line twin — the golden-authority choice;
//                            MPS not引入 per the plan's cascade shape).
//   ③ bloom_screen         — the linear-domain screen blend
//                            `out = 1 − (1−a)(1−b)` per channel, with the
//                            1/8 glow bilinearly upsampled IN-KERNEL
//                            (hand-written 4-tap — rgba32Float is not
//                            filterable on Apple GPUs, so no sampler).
//
// HDR >1.0 ZERO SPECIAL-CASING: screen is well-defined for a > 1 and the
// glow rides through unchanged — HDR input keeps HDR output (the test
// pins no-clamp; research §9.4).
//
// DETERMINISM: no atomics, no RNG; every pass is a pure function of its
// input texture + uniforms.
// ─────────────────────────────────────────────────────────────────────────

struct BloomThresholdUniforms {
    float scale;     // 1/exp2(−min(100,strength+1)/100) (bloom.c:144)
    float thrLin;    // (threshold/100)³ (research §9.2)
};

// Stage ① — the thresholded glow (bloom.cl:22-38 with the linear-domain
// mapping). dt thresholds on Lab L; Lightamer thresholds on the linear
// Rec2020 luma / 4.0 (the filmic white anchor). Writes (h,h,h,0).
kernel void bloom_threshold(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant BloomThresholdUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)out.get_width() || gid.y >= (uint)out.get_height()) return;

    const float4 pixel = in.read(gid);
    // Rec2020 linear luma → the linear mapped domain: luma / 4.0 (the
    // filmic white anchor — research §9.2), then dt's :144 brighten scale.
    const float luma = 0.2627f * pixel.x + 0.6780f * pixel.y + 0.0593f * pixel.z;
    const float L = luma * (1.0f / 4.0f) * u.scale;
    const float h = L > u.thrLin ? L : 0.0f;
    out.write(float4(h, h, h, 0.0f), gid);
}

// Stage ②a — the ÷8 box downsample (8×8 average, clamped borders). Each
// small pixel averages the 8×8 source block; this supplies the ~8-px
// low-pass leg of the cascade (research §9.3).
kernel void bloom_box_downsample(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)out.get_width() || gid.y >= (uint)out.get_height()) return;

    const int baseX = int(gid.x) * 8;
    const int baseY = int(gid.y) * 8;
    const int inW = in.get_width(), inH = in.get_height();
    float4 acc = 0.0f;
    for (int dy = 0; dy < 8; dy++) {
        const int y = clamp(baseY + dy, 0, inH - 1);
        for (int dx = 0; dx < 8; dx++) {
            const int x = clamp(baseX + dx, 0, inW - 1);
            acc += in.read(uint2(x, y));
        }
    }
    out.write(acc / 64.0f, gid);
}

struct BloomGaussUniforms {
    float sigma;      // the small-domain σ (exec σ / 8 — DECISIONS D-08-2-B1)
    int radius;       // ⌈2σ⌉
    int horizontal;   // 1 = X pass, 0 = Y pass
    int pad0;
};

// Stage ②b — the small-σ separable gaussian (ONE function, direction in
// uniforms; run X then Y). Truncated FIR, radius r = ⌈2σ⌉, clamped
// borders, weights normalized in-kernel. float64 twin: BloomReference.
kernel void bloom_gauss_pass(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant BloomGaussUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)out.get_width() || gid.y >= (uint)out.get_height()) return;

    const int span = (u.horizontal != 0) ? in.get_width() : in.get_height();
    const int cx = int(gid.x);
    const int cy = int(gid.y);

    float acc = 0.0f;
    float wsum = 0.0f;
    for (int k = -u.radius; k <= u.radius; k++) {
        const float w = exp(-(float(k) * float(k)) / (2.0f * u.sigma * u.sigma));
        int x = cx;
        int y = cy;
        if (u.horizontal != 0) {
            x = max((int)(cx + k), (int)0);
            x = min(x, (int)(span - 1));
        } else {
            y = max((int)(cy + k), (int)0);
            y = min(y, (int)(span - 1));
        }
        acc += w * in.read(uint2(x, y)).x;
        wsum += w;
    }
    out.write(float4(acc / wsum, acc / wsum, acc / wsum, 0.0f), gid);
}

// Stage ③ — the linear-domain screen blend with the in-kernel bilinear
// upsample of the 1/8 glow (hand-written 4-tap: rgba32Float is NOT
// filterable on Apple GPUs). out.rgb = 1 − (1−in.rgb)(1−b); alpha
// untouched; >1.0 rides through (research §9.4).
kernel void bloom_screen(
    texture2d<float, access::read>  in     [[texture(0)]],
    texture2d<float, access::read>  glow   [[texture(1)]],
    texture2d<float, access::write> out    [[texture(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)out.get_width() || gid.y >= (uint)out.get_height()) return;

    // Full-res pixel → the small-domain sample point (the ÷8 lattice's
    // center-preserving mapping: (p + 0.5)/8 − 0.5). The clamped-index
    // path below also covers degenerate ≤1px small textures.
    const float sx = (float(gid.x) + 0.5f) / 8.0f - 0.5f;
    const float sy = (float(gid.y) + 0.5f) / 8.0f - 0.5f;

    const float4 p = in.read(gid);

    const int w = glow.get_width(), h = glow.get_height();
    const int x0 = int(floor(sx)), y0 = int(floor(sy));
    const int x1 = min(x0 + 1, w - 1), y1 = min(y0 + 1, h - 1);
    const int cx0 = clamp(x0, 0, w - 1), cy0 = clamp(y0, 0, h - 1);
    const float tx = sx - float(x0), ty = sy - float(y0);
    const float g00 = glow.read(uint2(cx0, cy0)).x;
    const float g10 = glow.read(uint2(x1, cy0)).x;
    const float g01 = glow.read(uint2(cx0, y1)).x;
    const float g11 = glow.read(uint2(x1, y1)).x;
    const float b = (1.0f - tx) * (1.0f - ty) * g00
                  + tx * (1.0f - ty) * g10
                  + (1.0f - tx) * ty * g01
                  + tx * ty * g11;

    out.write(float4(1.0f - (1.0f - p.rgb) * (1.0f - b), p.a), gid);
}

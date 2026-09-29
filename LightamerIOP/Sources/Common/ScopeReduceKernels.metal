#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────────
// ScopeReduce kernels (Plan M2-3-3 T3, D6) — the editor scope reductions over
// the PREVIEW output plane (HistogramReduce's two-pass family):
//
//   1. scope_histogram_partial / scope_histogram_total — the 256-bin × 4
//      channel (R/G/B/Rec.709-luma) COUNTING histogram (atomic_uint bins;
//      float pixels bin by truncation — normalization stays in the draw
//      layer). Output = 256×4 uint = 4 KB buffer.
//   2. scope_waveform_accumulate / scope_waveform_total — the per-column
//      luma-band counts: each source 16-wide tile owns a contiguous output
//      column range, zeroes it (threadgroup barrier), atomically accumulates
//      band counts (integer atomics are order-independent → deterministic),
//      then the total pass copies the counts into the r16Uint present
//      texture (width ≤1080, height 256). Zero CPU readback on the data
//      path — the texture is the display carrier.
//
// L006 float32 textures; L014: every readback fences first; L031: command
// buffers come ONLY from MetalContext's routed acquisition (makeEncoder /
// makeRoutedCommandBuffer — never a second queue).
//
// Binning (the test-parity contract, mirrored exactly in Swift):
//   v = clamp(pixel, 0, 1); bin = min(uint(v * 255.0), 255)
//   luma = r*0.2126 + g*0.7152 + b*0.0722   (Rec.709 weights)
// ─────────────────────────────────────────────────────────────────────────────

constant float3 scope_luma_weights = float3(0.2126f, 0.7152f, 0.0722f);

static inline uint scope_bin(float v) {
    return min((uint)(clamp(v, 0.0f, 1.0f) * 255.0f), 255u);
}

kernel void scope_histogram_partial(
    texture2d<float, access::read> in [[texture(0)]],
    device uint*                   partials [[buffer(0)]],
    uint2 tgPos [[threadgroup_position_in_grid]],
    uint2 tpid [[thread_position_in_threadgroup]])
{
    // 4 channels × 256 bins (channel-major: channel*256 + bin).
    threadgroup atomic_uint localHist[1024];

    const uint linear = tpid.y * 16 + tpid.x;   // 0..255
    for (uint slot = linear; slot < 1024u; slot += 256u) {
        atomic_store_explicit(&localHist[slot], 0u, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    const uint2 pixel = tgPos * 16 + tpid;
    if (pixel.x < in.get_width() && pixel.y < in.get_height()) {
        const float3 rgb = in.read(pixel).rgb;
        const float luma = dot(rgb, scope_luma_weights);
        atomic_fetch_add_explicit(&localHist[0 * 256u + scope_bin(rgb.r)], 1u,
                                  memory_order_relaxed);
        atomic_fetch_add_explicit(&localHist[1 * 256u + scope_bin(rgb.g)], 1u,
                                  memory_order_relaxed);
        atomic_fetch_add_explicit(&localHist[2 * 256u + scope_bin(rgb.b)], 1u,
                                  memory_order_relaxed);
        atomic_fetch_add_explicit(&localHist[3 * 256u + scope_bin(luma)], 1u,
                                  memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    const uint tgLinear = tgPos.y * ((in.get_width() + 15) / 16) + tgPos.x;
    for (uint slot = linear; slot < 1024u; slot += 256u) {
        partials[tgLinear * 1024u + slot] =
            atomic_load_explicit(&localHist[slot], memory_order_relaxed);
    }
}

kernel void scope_histogram_total(
    device const uint* partials [[buffer(0)]],
    device uint*       total    [[buffer(1)]],
    constant uint&     nPartials [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= 1024u) return;
    uint sum = 0;
    for (uint p = 0; p < nPartials; p++) {
        sum += partials[p * 1024u + tid];
    }
    total[tid] = sum;
}

// The host memsets the partials buffer before the pass commits (the
// shared-buffer host write completes before the command buffer executes —
// no in-kernel zero phase, no ownership races). Each tile adds its pixels'
// (colOut, band) cell: integer atomic adds are order-independent → the
// accumulation is deterministic; the column mapping (mirrored in Swift):
//   colOut(x) = min(x * outW / srcW, outW-1)   (integer floor)
// Every source pixel lands in exactly one cell — nothing drops.
kernel void scope_waveform_accumulate(
    texture2d<float, access::read> in [[texture(0)]],
    device atomic_uint*            partials [[buffer(0)]],   // outW × 256
    constant uint&                 outWidth [[buffer(1)]],
    uint2 tgPos [[threadgroup_position_in_grid]],
    uint2 tpid [[thread_position_in_threadgroup]])
{
    const uint srcW = in.get_width();
    const uint2 base = tgPos * 16;
    const uint cols = min(16u, srcW - base.x);
    for (uint cx = tpid.x; cx < cols; cx += 16u) {
        const uint x = base.x + cx;
        const uint colOut = min(x * outWidth / srcW, outWidth - 1u);
        // ONE row per thread INSIDE this tile (y < base.y+16): the tile
        // grid walks the image in 16-row steps — a +16 inner stride would
        // make tile row 0 re-process every later tile's rows (the 1.5×
        // inflation this guard exists for).
        const uint y = base.y + tpid.y;
        if (y < in.get_height()) {
            const float3 rgb = in.read(uint2(x, y)).rgb;
            const float luma = dot(rgb, scope_luma_weights);
            atomic_fetch_add_explicit(
                &partials[colOut * 256u + scope_bin(luma)], 1u,
                memory_order_relaxed);
        }
    }
}

kernel void scope_waveform_total(
    device const atomic_uint*      partials [[buffer(0)]],   // outW × 256
    texture2d<uint, access::write> out [[texture(0)]],       // r16Uint
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
    out.write(
        uint4(atomic_load_explicit(
            &partials[gid.x * 256u + gid.y], memory_order_relaxed), 0u, 0u, 0u),
        gid);
}

#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// DehazeKernels (Plan 08-5 T1, IOP-FX-04 — op "hazeremoval", v50 slot 14.0)
//
// Port master: darktable `data/kernels/hazeremoval.cl:22-163` (tree
// dc58cf0ba1) + the CPU pieces of `src/iop/hazeremoval.c` the CL path also
// drives (the sliding-window box min/max kernels are verbatim line ports;
// the transition map and the restore are :338-352 / :678-692).
//
// PLANNER RULING (plan discipline, frozen): the dt guided filter
// (`guided_filter(w2, eps=sqrt(0.025))`) is replaced by a BOX MEAN applied
// in two separable passes (X then Y, radius w2) — one complex kernel fewer
// on the port table (R5 消解); the visual difference is a Manual-Only
// comparison item and the full guided port is the Reversibility upgrade
// seam. The float64 reference is the SAME box-approximation form, so the
// parity loop is closed regardless.
//
// The single-channel stages run on r32Float planes (dt: `sizeof(float)`
// temps). Scalar arguments ride packed constant-buffer structs (MSL takes
// no bare scalars on [[buffer(n)]]). L031: every dispatch rides
// MetalContext.makeEncoder — the routed acquisition point; this file only
// carries the kernel bodies.
// ─────────────────────────────────────────────────────────────────────────

struct DehazeGridParams {
  uint blockX;
  uint blockY;
};

struct DehazeBoxParams {
  uint width;
  uint height;
  uint w;
};

struct DehazeTransisionParams {
  uint width;
  uint height;
  float strength;
  float a0r;
  float a0g;
  float a0b;
};

struct DehazeApplyParams {
  uint width;
  uint height;
  float tMin;
  float a0r;
  float a0g;
  float a0b;
};

// The ambient-statistics grid: each output texel = the MEAN of its source
// block (the module reads this grid back — L014 same-CB drain — for the
// CPU ambient-light estimate AND the input-content hash; the fixed long-
// edge grid keeps the estimate bounded and scale-consistent, the
// Lightamer answer to the dt gui_data preview/full sync pit).
kernel void dehaze_ambient_grid(
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant DehazeGridParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
  const uint width = in.get_width();
  const uint height = in.get_height();
  const uint x0 = gid.x * params.blockX;
  const uint y0 = gid.y * params.blockY;
  const uint x1 = min(x0 + params.blockX, width);
  const uint y1 = min(y0 + params.blockY, height);
  float4 sum = 0.0f;
  // A block is at least 1x1 and the grid is bounded (long edge 1024), so
  // this loop is O(block area) with a hard cap in practice.
  for (uint y = y0; y < y1; ++y)
    for (uint x = x0; x < x1; ++x)
      sum += in.read(uint2(x, y));
  const float n = max(1.0f, float((x1 - x0) * (y1 - y0)));
  out.write(sum / n, gid);
}

// ── the four sliding-window box min/max kernels (hazeremoval.cl:22-100
// verbatim shape: O(N) restart-on-eviction; the window is [i-w, i+w] ∩
// [0, dim), i.e. a (2w+1) support). ─────────────────────────────────────

kernel void dehaze_box_min_x(
    constant DehazeBoxParams &params [[buffer(0)]],
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    const uint gid [[thread_position_in_grid]])
{
  const uint y = gid;
  if (y >= params.height) return;
  float m = INFINITY;
  for (uint i = 0, i_end = min(params.w + 1, params.width); i < i_end; ++i)
    m = min(in.read(uint2(i, y)).r, m);
  for (uint i = 0; i < params.width; ++i) {
    out.write(float4(m), uint2(i, y));
    if (i >= params.w && in.read(uint2(i - params.w, y)).r == m) {
      m = INFINITY;
      const uint lo = i + 1 >= params.w ? i + 1 - params.w : 0u;
      for (uint j = lo, j_end = min(i + params.w + 2, params.width); j < j_end; ++j)
        m = fmin(in.read(uint2(j, y)).r, m);
    }
    if (i + params.w + 1 < params.width) m = fmin(in.read(uint2(i + params.w + 1, y)).r, m);
  }
}

kernel void dehaze_box_min_y(
    constant DehazeBoxParams &params [[buffer(0)]],
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    const uint gid [[thread_position_in_grid]])
{
  const uint x = gid;
  if (x >= params.width) return;
  float m = INFINITY;
  for (uint i = 0, i_end = min(params.w + 1, params.height); i < i_end; ++i)
    m = fmin(in.read(uint2(x, i)).r, m);
  for (uint i = 0; i < params.height; ++i) {
    out.write(float4(m), uint2(x, i));
    if (i >= params.w && in.read(uint2(x, i - params.w)).r == m) {
      m = INFINITY;
      const uint lo = i + 1 >= params.w ? i + 1 - params.w : 0u;
      for (uint j = lo, j_end = min(i + params.w + 2, params.height); j < j_end; ++j)
        m = fmin(in.read(uint2(x, j)).r, m);
    }
    if (i + params.w + 1 < params.height) m = fmin(in.read(uint2(x, i + params.w + 1)).r, m);
  }
}

kernel void dehaze_box_max_x(
    constant DehazeBoxParams &params [[buffer(0)]],
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    const uint gid [[thread_position_in_grid]])
{
  const uint y = gid;
  if (y >= params.height) return;
  float m = -(INFINITY);
  for (uint i = 0, i_end = min(params.w + 1, params.width); i < i_end; ++i)
    m = fmax(in.read(uint2(i, y)).r, m);
  for (uint i = 0; i < params.width; ++i) {
    out.write(float4(m), uint2(i, y));
    if (i >= params.w && in.read(uint2(i - params.w, y)).r == m) {
      m = -(INFINITY);
      const uint lo = i + 1 >= params.w ? i + 1 - params.w : 0u;
      for (uint j = lo, j_end = min(i + params.w + 2, params.width); j < j_end; ++j)
        m = fmax(in.read(uint2(j, y)).r, m);
    }
    if (i + params.w + 1 < params.width) m = fmax(in.read(uint2(i + params.w + 1, y)).r, m);
  }
}

kernel void dehaze_box_max_y(
    constant DehazeBoxParams &params [[buffer(0)]],
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    const uint gid [[thread_position_in_grid]])
{
  const uint x = gid;
  if (x >= params.width) return;
  float m = -(INFINITY);
  for (uint i = 0, i_end = min(params.w + 1, params.height); i < i_end; ++i)
    m = fmax(in.read(uint2(x, i)).r, m);
  for (uint i = 0; i < params.height; ++i) {
    out.write(float4(m), uint2(x, i));
    if (i >= params.w && in.read(uint2(x, i - params.w)).r == m) {
      m = -(INFINITY);
      const uint lo = i + 1 >= params.w ? i + 1 - params.w : 0u;
      for (uint j = lo, j_end = min(i + params.w + 2, params.height); j < j_end; ++j)
        m = fmax(in.read(uint2(x, j)).r, m);
    }
    if (i + params.w + 1 < params.height) m = fmax(in.read(uint2(x, i + params.w + 1)).r, m);
  }
}

// The transition map (hazeremoval.cl:139-152; hazeremoval.c:338-352):
// t = 1 − min_c(p_c / A0_c) · strength. dt applies a box_max(w1) right
// after (the CPU `_transition_map` tail + `_transition_map_cl`); the
// module chains the box kernels explicitly.
kernel void dehaze_transision_map(
    constant DehazeTransisionParams &params [[buffer(0)]],
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= params.width || gid.y >= params.height) return;
  const float4 pixel = in.read(gid);
  float m = pixel.x / params.a0r;
  m = fmin(pixel.y / params.a0g, m);
  m = fmin(pixel.z / params.a0b, m);
  out.write(float4(1.0f - m * params.strength), gid);
}

// ── the guided-filter replacement (the planner ruling): a BOX MEAN with
// radius w2 in two separable passes. Straight windowed-sum O(N·w) — same
// windowed-mean FORM the float64 reference double-writes. ───────────────

kernel void dehaze_box_mean_x(
    constant DehazeBoxParams &params [[buffer(0)]],
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= params.width || gid.y >= params.height) return;
  const uint lo = gid.x >= params.w ? gid.x - params.w : 0u;
  const uint hi = min(gid.x + params.w, params.width - 1);
  float sum = 0.0f;
  for (uint k = lo; k <= hi; ++k)
    sum += in.read(uint2(k, gid.y)).r;
  out.write(float4(sum / float(hi - lo + 1)), gid);
}

kernel void dehaze_box_mean_y(
    constant DehazeBoxParams &params [[buffer(0)]],
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= params.width || gid.y >= params.height) return;
  const uint lo = gid.y >= params.w ? gid.y - params.w : 0u;
  const uint hi = min(gid.y + params.w, params.height - 1);
  float sum = 0.0f;
  for (uint k = lo; k <= hi; ++k)
    sum += in.read(uint2(gid.x, k)).r;
  out.write(float4(sum / float(hi - lo + 1)), gid);
}

// The restore (hazeremoval.cl:155-163; hazeremoval.c:678-692):
// out = (in − A0) / max(t, t_min) + A0, with
// t_min = clamp(exp(−distance·distance_max), 1/1024, 1) computed CPU-side.
kernel void dehaze_apply(
    constant DehazeApplyParams &params [[buffer(0)]],
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::read> trans_map [[texture(1)]],
    texture2d<float, access::write> out [[texture(2)]],
    uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= params.width || gid.y >= params.height) return;
  const float4 pixel = in.read(gid);
  const float t = fmax(trans_map.read(gid).r, params.tMin);
  const float3 result = float3(pixel.x - params.a0r, pixel.y - params.a0g, pixel.z - params.a0b) / t
      + float3(params.a0r, params.a0g, params.a0b);
  out.write(float4(result, pixel.a), gid);
}

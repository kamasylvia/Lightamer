#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// TextOverlayKernels (Plan 08-5 T2, IOP-FX-05 — op "textOverlay", v50 slot
// 66.7, the second Lightamer-native V50Order row).
//
// ONE kernel: the alpha composite of the rasterized text coverage over the
// plane — source-over with a UNIFORM color/opacity and an inverse-rotation
// coverage sample. NO color matrix (the text color rides as a plain linear
// RGB uniform; COLOR-2's float[9] matrix convention does not apply —
// research §11.2).
//
// The coverage texture is r8Unorm (the CoreText gray-AA coverage, 1 byte
// per pixel; the rasterizer uploads it raw). Sampling is NEAREST with
// zero-outside semantics — the rasterizer's block bounds are exact, and
// the rotation walks the SOURCE block through the inverse transform.
// ─────────────────────────────────────────────────────────────────────────

struct TextOverlayParams {
  uint width;
  uint height;
  uint blockW;
  uint blockH;
  float posX;    // normalized block-CENTER position, image space, y from TOP
  float posY;
  float rotationRadians; // counterclockwise, about the block center
  float opacity; // [0, 1]
  float colorR;  // linear Rec2020... actually the plane's working RGB —
  float colorG;  // the uniform text color, same domain as the plane
  float colorB;
};

kernel void text_overlay_composite(
    constant TextOverlayParams &p [[buffer(0)]],
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::read> coverage [[texture(1)]],
    texture2d<float, access::write> out [[texture(2)]],
    uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= p.width || gid.y >= p.height) return;
  const float4 pixel = in.read(gid);

  // The pixel's position relative to the block CENTER (image space, y
  // down — gid.y is the texture row).
  const float cx = float(p.posX * float(p.width));
  const float cy = float(p.posY * float(p.height));
  const float dx = float(gid.x) - cx;
  const float dy = float(gid.y) - cy;

  // The INVERSE rotation walks the output pixel back into the (rotated)
  // block's upright frame; the rasterized block is centered there.
  const float s = sin(-p.rotationRadians);
  const float c = cos(-p.rotationRadians);
  const float u = dx * c - dy * s + float(p.blockW) * 0.5f;
  const float v = dx * s + dy * c + float(p.blockH) * 0.5f;

  float coverageAlpha = 0.0f;
  if (u >= 0.0f && v >= 0.0f && u < float(p.blockW) && v < float(p.blockH)) {
    coverageAlpha = coverage.read(uint2((uint)u, (uint)v)).r;
  }
  const float aS = coverageAlpha * p.opacity;
  const float3 rgb = pixel.rgb * (1.0f - aS) + float3(p.colorR, p.colorG, p.colorB) * aS;
  out.write(float4(rgb, pixel.a), gid);
}

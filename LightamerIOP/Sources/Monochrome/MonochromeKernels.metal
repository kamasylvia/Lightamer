#include <metal_stdlib>
#include "../Common/LabMath.h"
using namespace metal;

// MonochromeKernels.metal (Plan 05-05-T1) — dt `monochrome` (64.0, Lab)
// filter + apply 的 MSL 直译。
//
// dt 对照（树 dc58cf0ba1）：
// - params v2 :47-53（a/b/size/highlights 4 float = 16B）；
// - `_color_filter` :168-175；`_envelope` :177-195；CPU process :197-239；
// - CL `monochrome_filter`/`monochrome`（basic.cl:2992-3035）。
//
// SIGMA² 裁决（plan 纪律「sigma² 钉 CPU 版」；RESEARCH §5.3）：
// - CPU `sigma2 = 2·(size·128)²`（monochrome.c:205）；
// - CL  `sigma2 = (size·128)²`（monochrome.c:257）——差 2 倍滤波宽度
//   （dt 源码自身分歧，见 05-05-DECISIONS D1）。
// - 本 kernel 按 CPU 版（dt-cli 无 OpenCL 走 CPU 路径，golden 与 dt-cli
//   互证以 CPU 版为准）；uniforms 载 sigma2CPU，中性恒等门 size→∞ 时
//   filter→1（RE 直接复用同一 uniforms 值）。
//
// LAB DOMAIN（03-03 Goal 模式）：LabMath.h fused Rec2020→Lab→Rec2020。
// filter 腿在 Lab 值上计算（dt pixelpipe 递 Lab；我方工作域 linear Rec2020）。
// bilateral grid 腿（T2）：filter 输出的 L 通道（100·f）是 grid splat 的
// luma 平面——grid 经 BilateralGrid3D.splalAsMTLBuffer 消费（filter 纹理
// 上传 + splat/blur/slice 后回读），apply kernel 读三纹理
// （in/filter_smooth/out）。
//
// dt_fast_expf（math.h:418-430）= ~exp（0 处 −0.06 偏置，>0 域爆炸）——
// 我方用精确 metal `exp`（与 dt CPU 腿的 dt_fast_expf 偏差 ~6% @0 ——
// plan 纪律：golden 钉 dt CPU 腿的 filter 公式形状，容差见 T3 parity 门；
// 参考实现用精确 exp，测试 pin 两者偏差上界）。

/// monochrome_filter（basic.cl:2992 直译 + CPU sigma² 修正）：
/// out.x = 100·exp(−clamp(((a−ai)²+(b−bi)²)/σ²,0,1))；y/z = 0。
kernel void monochrome_filter(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant float4& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= in.get_width() || gid.y >= in.get_height()) return;
    float4 px = in.read(gid);
    float3 lab = la_rec2020_to_lab(px.xyz);
    float dai = lab.y - u.x; // ai = u.x, bi = u.y, sigma2 = u.z
    float dbi = lab.z - u.y;
    float t = clamp((dai * dai + dbi * dbi) / u.z, 0.0f, 1.0f);
    float f = exp(-t);
    out.write(float4(100.0f * f, 0.0f, 0.0f, px.w), gid);
}

/// monochrome_apply（monochrome.c:232-238 直译）：
/// tt = envelope(L_in)；t = tt + (1−tt)·(1−highlights)；
/// out.x = (1−t)·L_in + t·F_smooth·L_in/100；out.y = out.z = 0
/// （F_smooth = grid slice 后的 filter 纹理 L 通道；dt :237
/// `out = (1−t)·in + t·out·(1/100)·in` 逐式）。
kernel void monochrome_apply(
    texture2d<float, access::read>  in      [[texture(0)]],
    texture2d<float, access::read>  filt    [[texture(1)]],
    texture2d<float, access::write> out     [[texture(2)]],
    constant float4& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= in.get_width() || gid.y >= in.get_height()) return;
    float4 px = in.read(gid);
    float3 lab = la_rec2020_to_lab(px.xyz);
    float Lin = lab.x;
    float F = filt.read(gid).x; // 100·f_smooth（grid 腿后）
    float xc = clamp(Lin / 100.0f, 0.0f, 1.0f);
    float tt;
    if (xc < 0.6f) {
        float tmp = xc / 0.6f - 1.0f;
        tt = 1.0f - tmp * tmp;
    } else {
        float tmp1 = (1.0f - xc) / 0.4f;
        float tmp2 = tmp1 * tmp1;
        float tmp3 = tmp2 * tmp1;
        tt = 3.0f * tmp2 - 2.0f * tmp3;
    }
    float t = tt + (1.0f - tt) * (1.0f - u.w); // u.w = highlights
    float Lout = (1.0f - t) * Lin + t * F * (1.0f / 100.0f) * Lin;
    float3 outLab = float3(Lout, 0.0f, 0.0f);
    float3 rgb = la_lab_to_rec2020(outLab);
    out.write(float4(rgb, px.w), gid);
}

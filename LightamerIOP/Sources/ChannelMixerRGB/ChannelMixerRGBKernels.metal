#include <metal_stdlib>
#include "../Common/LabMath.h"
using namespace metal;

// ChannelMixerRGB iop kernel (Plan 05-03-T2) — port of Darktable's
// `data/kernels/channelmixer.cl:106-685` 5 path kernels, fused into ONE
// kernel with a runtime adaptation switch (the 5 dt kernels are
// copy-pasted with only the adaptation kind differing — the file's own
// comment; the per-path math is identical).
//
// Pipeline RGB ⇄ XYZ uses LabMath.h's D65-native pair (05-02-DECISIONS D2:
// la_rec2020_to_xyz / la_xyz_to_rec2020 — NOT a D50-detour product).
// Per-pixel stages mirror `_loop_switch` (channelmixerrgb.c:771-1000):
// chroma-adapt → MIX → gamut → LMS/XYZ/pipe-RGB → clip → luma_chroma →
// clip → grey-mix or back-to-XYZ → back-to-RGB. Alpha restored from input
// (CL leg; header divergence #2). L006 float32; L008 endEncoding before
// commit (dispatch2DTexture).

struct ChannelMixerRGBUniforms {
    float rgbToLMS[9];
    float mixToXYZ[9];
    float xyzToLMS[9];
    float lmsToXYZ[9];
    float illuminant[3];
    float p;
    float gamut;
    float clip;
    float applyGrey;
    float version;
    float adaptation;
    float saturation[3];
    float lightness[3];
    float grey[3];
    float pad[2];
};

constant float cm_norm_min = 1.52587890625e-05f; // dt NORM_MIN (math.h:30)
constant float cm_inv_sqrt3 = 0.5773502691896258f;

inline float3 cm_mat_vec(constant float* m, float3 v) {
    return float3(
        m[0] * v.x + m[1] * v.y + m[2] * v.z,
        m[3] * v.x + m[4] * v.y + m[5] * v.z,
        m[6] * v.x + m[7] * v.y + m[8] * v.z);
}

inline float cm_euclidean_norm(float3 v) {
    return max(sqrt(v.x * v.x + v.y * v.y + v.z * v.z), cm_norm_min);
}

inline void cm_downscale(thread float3* v, float s) {
    *v /= (s > cm_norm_min) ? (s + cm_norm_min) : cm_norm_min;
}

inline void cm_upscale(thread float3* v, float s) {
    *v *= (s > cm_norm_min) ? (s + cm_norm_min) : cm_norm_min;
}

// dt convert_XYZ_to_bradford_LMS (chromatic_adaptation.h:60-64).
inline float3 cm_xyz_to_bradford(float3 xyz) {
    return float3(
        0.8951f * xyz.x + 0.2664f * xyz.y - 0.1614f * xyz.z,
        -0.7502f * xyz.x + 1.7135f * xyz.y + 0.0367f * xyz.z,
        0.0389f * xyz.x - 0.0685f * xyz.y + 1.0296f * xyz.z);
}

// dt convert_bradford_LMS_to_XYZ (:72-76).
inline float3 cm_bradford_to_xyz(float3 lms) {
    return float3(
        0.9870f * lms.x - 0.1471f * lms.y + 0.1600f * lms.z,
        0.4323f * lms.x + 0.5184f * lms.y + 0.0493f * lms.z,
        -0.0085f * lms.x + 0.0400f * lms.y + 0.9685f * lms.z);
}

// dt convert_XYZ_to_CAT16_LMS (:117-121).
inline float3 cm_xyz_to_cat16(float3 xyz) {
    return float3(
        0.401288f * xyz.x + 0.650173f * xyz.y - 0.051461f * xyz.z,
        -0.250268f * xyz.x + 1.204414f * xyz.y + 0.045854f * xyz.z,
        -0.002079f * xyz.x + 0.048952f * xyz.y + 0.953127f * xyz.z);
}

// dt convert_CAT16_LMS_to_XYZ (:129-133).
inline float3 cm_cat16_to_xyz(float3 lms) {
    return float3(
        1.862068f * lms.x - 1.011255f * lms.y + 0.149187f * lms.z,
        0.38752f * lms.x + 0.621447f * lms.y - 0.008974f * lms.z,
        -0.015841f * lms.x - 0.034123f * lms.y + 1.049964f * lms.z);
}

// dt bradford_adapt_D50 (:256-285).
inline float3 cm_bradford_adapt(float3 lms, float3 illum, float p, bool full) {
    float3 t = lms / illum;
    if (full && t.z > 0.0f) t.z = pow(t.z, p);
    return float3(0.996078f, 1.020646f, 0.818155f) * t;
}

// dt CAT16_adapt_D50, forced full (:313-338, channelmixerrgb forces D=1).
inline float3 cm_cat16_adapt(float3 lms, float3 illum) {
    return lms * float3(0.994535f, 1.000997f, 0.833036f) / illum;
}

// dt XYZ_adapt_D50 (:360-375).
inline float3 cm_xyz_adapt(float3 xyz, float3 illum) {
    return xyz * float3(0.9642119944211994f, 1.0f, 0.8251882845188288f) / illum;
}

// dt _gamut_mapping (channelmixerrgb.c:648-705).
inline float3 cm_gamut_map(float3 input, float compression, bool clip) {
    float sum = input.x + input.y + input.z;
    float3 xyY = float3(sum > 0.0f ? input.x / sum : 0.34567f,
                        sum > 0.0f ? input.y / sum : 0.35850f, input.y);
    float denom = -2.0f * xyY.x + 12.0f * xyY.y + 3.0f;
    float2 uv = float2(4.0f * xyY.x / denom, 9.0f * xyY.y / denom);
    float2 delta = float2(0.20915914598542354f, 0.488075320769787f) - uv;
    float Delta = input.y * (delta.x * delta.x + delta.y * delta.y);
    float correction = (compression == 0.0f) ? 0.0f : pow(Delta, compression);
    float2 tmp = correction * delta + uv;
    uv.x = (uv.x > 0.20915914598542354f) ? max(tmp.x, 0.20915914598542354f)
                                         : min(tmp.x, 0.20915914598542354f);
    uv.y = (uv.y > 0.488075320769787f) ? max(tmp.y, 0.488075320769787f)
                                       : min(tmp.y, 0.488075320769787f);
    float denom2 = 6.0f * uv.x - 16.0f * uv.y + 12.0f;
    xyY = float3(9.0f * uv.x / denom2, 4.0f * uv.y / denom2, xyY.z);
    if (clip) xyY.xy = max(xyY.xy, 0.0f);
    xyY.y = max(xyY.y, cm_norm_min);
    float scale = xyY.x + xyY.y;
    if (scale >= 1.0f) xyY.xy /= scale;
    return float3(xyY.z * xyY.x / xyY.y, xyY.z,
                  xyY.z * (1.0f - xyY.x - xyY.y) / xyY.y);
}

// dt _luma_chroma via channelmixer.cl luma_chroma (:112-158).
inline float3 cm_luma_chroma(float3 input, float3 saturation,
                             float3 lightness, int version) {
    float norm = cm_euclidean_norm(input);
    float avg = max((input.x + input.y + input.z) / 3.0f, cm_norm_min);
    if (!(norm > 0.0f && avg > 0.0f)) return input;
    float mix = dot(input, lightness);
    if (version == 2) norm *= cm_inv_sqrt3;
    float3 output = input / norm;
    float coeff = (version == 0) ? dot(1.0f - output, saturation)
                                 : dot(output, saturation) / 3.0f;
    float3 min_ratio = select(float3(0.0f), output, output < 0.0f);
    output = max((1.0f - output) * coeff + output, min_ratio);
    if (version == 2) norm /= cm_euclidean_norm(output) * cm_inv_sqrt3;
    norm *= max(1.0f + mix / avg, 0.0f);
    return output * norm;
}

kernel void channelmixerrgb_apply(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant ChannelMixerRGBUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    float4 pix_in = in.read(gid);
    float3 illum = float3(u.illuminant[0], u.illuminant[1], u.illuminant[2]);
    float3 sat = float3(u.saturation[0], u.saturation[1], u.saturation[2]);
    float3 light = float3(u.lightness[0], u.lightness[1], u.lightness[2]);
    float3 grey = float3(u.grey[0], u.grey[1], u.grey[2]);
    int adapt = (int)u.adaptation;
    int version = (int)u.version;
    bool clip = u.clip != 0.0f;
    bool applyGrey = u.applyGrey != 0.0f;
    float3 rgb = pix_in.xyz;
    if (clip) rgb = max(rgb, 0.0f);
    //   full/linear Bradford: rgbToLMS = B·R2X, mixToXYZ = Bi·MIX
    //   CAT16: rgbToLMS = C·R2X, mixToXYZ = Ci·MIX
    //   XYZ: rgbToLMS = R2X, mixToXYZ = MIX
    //   RGB: mixToXYZ = R2X·MIX (rgbToLMS unused).
    float3 XYZ;
    if (adapt == 2) {
        // FULL Bradford: RGB→XYZ→LMS, Y downscale, non-linear adapt,
        // upscale, MIX, back to XYZ (chroma_adapt_bradford full=TRUE).
        XYZ = cm_mat_vec(u.rgbToLMS, rgb);
        float Y = XYZ.y;
        float3 LMS = cm_xyz_to_bradford(XYZ);
        cm_downscale(&LMS, Y);
        LMS = cm_bradford_adapt(LMS, illum, u.p, true);
        cm_upscale(&LMS, Y);
        LMS = cm_mat_vec(u.mixToXYZ, LMS);
        XYZ = cm_bradford_to_xyz(LMS);
    } else if (adapt == 0) {
        // LINEAR Bradford: RGB→LMS direct, linear adapt, MIX, back
        // (no Y down/upscale — dt chroma_adapt_bradford full=FALSE).
        float3 LMS = cm_mat_vec(u.rgbToLMS, rgb);
        LMS = cm_bradford_adapt(LMS, illum, u.p, false);
        LMS = cm_mat_vec(u.mixToXYZ, LMS);
        XYZ = cm_bradford_to_xyz(LMS);
    } else if (adapt == 1) {
        XYZ = cm_mat_vec(u.rgbToLMS, rgb);
        float Y = XYZ.y;
        float3 LMS = cm_xyz_to_cat16(XYZ);
        cm_downscale(&LMS, Y);
        LMS = cm_cat16_adapt(LMS, illum);
        cm_upscale(&LMS, Y);
        XYZ = cm_cat16_to_xyz(cm_mat_vec(u.mixToXYZ, LMS));
    } else if (adapt == 3) {
        XYZ = cm_mat_vec(u.rgbToLMS, rgb);
        float Y = XYZ.y;
        cm_downscale(&XYZ, Y);
        XYZ = cm_xyz_adapt(XYZ, illum);
        cm_upscale(&XYZ, Y);
        XYZ = cm_mat_vec(u.mixToXYZ, XYZ);
    } else {
        XYZ = cm_mat_vec(u.mixToXYZ, rgb);
    }

    // Gamut mapping in XYZ (always).
    if (clip) XYZ = max(XYZ, 0.0f);
    XYZ = cm_gamut_map(XYZ, u.gamut, clip);

    // Convert to LMS / XYZ / pipeline RGB (unswitch_convert_XYZ_to_any_LMS).
    float3 LMS;
    if (adapt == 0 || adapt == 2) {
        LMS = cm_xyz_to_bradford(XYZ);
    } else if (adapt == 1) {
        LMS = cm_xyz_to_cat16(XYZ);
    } else if (adapt == 3) {
        LMS = XYZ;
    } else {
        LMS = cm_mat_vec(u.xyzToLMS, XYZ);
    }

    if (clip) LMS = max(LMS, 0.0f);
    LMS = cm_luma_chroma(LMS, sat, light, version);
    if (clip) LMS = max(LMS, 0.0f);

    float3 outRGB;
    if (applyGrey) {
        float g = max(dot(LMS, grey), 0.0f);
        outRGB = float3(g);
    } else {
        float3 backXYZ;
        if (adapt == 0 || adapt == 2) {
            backXYZ = cm_bradford_to_xyz(LMS);
        } else if (adapt == 1) {
            backXYZ = cm_cat16_to_xyz(LMS);
        } else if (adapt == 3) {
            backXYZ = LMS;
        } else {
            backXYZ = cm_mat_vec(u.lmsToXYZ, LMS);
        }
        if (clip) backXYZ = max(backXYZ, 0.0f);
        outRGB = cm_mat_vec(la_xyz_to_rec2020, backXYZ);
        if (clip) outRGB = max(outRGB, 0.0f);
    }
    out.write(float4(outRGB, pix_in.w), gid);
}

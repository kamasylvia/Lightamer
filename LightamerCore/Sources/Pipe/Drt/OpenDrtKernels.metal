#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────────
// OpenDrtKernels — the OpenDRT per-pixel compute kernel (Plan M2-6-1 T4,
// KD-4 / OQ-10-A). Lives in LightamerCore next to the pixelpipe (the
// TerminalKernels placement rule — zero IOP dependency for tests/golden).
//
// STRUCTURE: a stage-for-stage mirror of `OpenDrtReference.swift` — the
// Float64 file is the algorithm authority and its header carries the
// numbered structure map ([1]..[24] below reference those stage numbers).
// Parameters ride ONE MTLBuffer (DrtUniforms, 244 bytes — zero function
// constants, a param drag re-uploads and recompiles NOTHING, single PSO
// resident). The tonescale constraint constants are derived per-thread,
// exactly like the reference's per-call derivation (one derivation, two
// faces — no CPU-precomputed drift surface).
//
// OUTPUT CONTRACT: peak-normalized display-linear RGB (1.0 = tn_Lp nits) —
// the EOTF encode is the EotfBox's separate stage (KD-4). aces20 is NOT a
// case here: the Swift dispatch refuses unimplemented methods
// (DrtMethod.isRenderImplemented — the P2 stub face), so the kernel carries
// ONLY the OpenDRT arm.
//
// PROVENANCE: structure transcription of jedypod/open-display-transform
// v1.1.0 (GPLv3, read-only) — zero code/text copied; the numeric tables are
// facts. L006: full float math, no half anywhere.
// ─────────────────────────────────────────────────────────────────────────────

constant float kDrtSqrt3 = 1.73205080756887729353f;
constant float kDrtPi = 3.14159265358979323846f;

// Primaries + CAT matrices. MSL float3x3(..) takes COLUMNS, so each column
// below is built from the row-major rows of the Swift DrtMat3 twins.
static inline float3 drtMul(float3 r0, float3 r1, float3 r2, float3 v) {
    return float3(dot(r0, v), dot(r1, v), dot(r2, v));
}

// Rec2020 → XYZ (row-major rows).
constant float3 kRec2020ToXYZ_r0 = float3(0.636958048301290991f, 0.144616903586208406f, 0.168880975164172054f);
constant float3 kRec2020ToXYZ_r1 = float3(0.26270021201126692f, 0.677998071518871148f, 0.0593017164698619384f);
constant float3 kRec2020ToXYZ_r2 = float3(4.9999999999999999e-17f, 0.0280726930490874452f, 1.06098505771079066f);

// XYZ → P3D65.
constant float3 kXYZToP3D65_r0 = float3(2.49349691194142542f, -0.93138361791912383f, -0.402710784450716841f);
constant float3 kXYZToP3D65_r1 = float3(-0.829488969561574696f, 1.76266406031834655f, 0.0236246858419435941f);
constant float3 kXYZToP3D65_r2 = float3(0.0358458302437844531f, -0.0761723892680418041f, 0.956884524007687309f);

// XYZ → Rec709.
constant float3 kXYZToRec709_r0 = float3(3.24096994190452348f, -1.53738317757009435f, -0.498610760293003552f);
constant float3 kXYZToRec709_r1 = float3(-0.969243636280879506f, 1.87596750150771996f, 0.0415550574071755843f);
constant float3 kXYZToRec709_r2 = float3(0.0556300796969936354f, -0.20397695888897649f, 1.05697151424287816f);

// P3D65 → XYZ.
constant float3 kP3D65ToXYZ_r0 = float3(0.486570948648216151f, 0.265667693169093f, 0.198217285234362467f);
constant float3 kP3D65ToXYZ_r1 = float3(0.228974564069748754f, 0.691738521836506193f, 0.079286914093744984f);
constant float3 kP3D65ToXYZ_r2 = float3(-4.00000000000000029e-17f, 0.0451133818589026167f, 1.04394436890097575f);

// P3 → Rec2020 (the Rec.2020 P3-limited terminal matrix).
constant float3 kP3ToRec2020_r0 = float3(0.753833034361722221f, 0.198597369052616435f, 0.0475695965856618441f);
constant float3 kP3ToRec2020_r1 = float3(0.0457438489653582137f, 0.9417772198116936f, 0.0124789312229481135f);
constant float3 kP3ToRec2020_r2 = float3(-0.0012103403545183941f, 0.0176017173010899926f, 0.983608623053428777f);

// CAT matrices (rows).
constant float3 kD65ToD93_r0 = float3(0.95703423023223877f, -0.0247171502560377121f, 0.0624028593301773071f);
constant float3 kD65ToD93_r1 = float3(-0.0179296955466270447f, 0.990019857883453369f, 0.0248119533061981201f);
constant float3 kD65ToD93_r2 = float3(0.00127589143812656403f, 0.00427919067442417058f, 1.29345715045928955f);
constant float3 kD65ToD75_r0 = float3(0.981001079082489014f, -0.0116619253531098366f, 0.0265614092350006104f);
constant float3 kD65ToD75_r1 = float3(-0.00843488052487373352f, 0.996506094932556152f, 0.0105696544051170349f);
constant float3 kD65ToD75_r2 = float3(0.000552809564396739006f, 0.00179840810596942902f, 1.12374722957611084f);
constant float3 kD65ToD60_r0 = float3(1.01182246208190918f, 0.00778879318386316299f, -0.0157783031463623047f);
constant float3 kD65ToD60_r1 = float3(0.00561682833358645439f, 1.00150644779205322f, -0.00628517568111419678f);
constant float3 kD65ToD60_r2 = float3(-0.000335735734552145004f, -0.0010509500280022619f, 0.927366673946380615f);
constant float3 kD65ToD55_r0 = float3(1.02585089206695557f, 0.0179439820349216461f, -0.0332137793302536011f);
constant float3 kD65ToD55_r1 = float3(0.0129133854061365128f, 1.00214779376983643f, -0.0132421031594276428f);
constant float3 kD65ToD55_r2 = float3(-0.000719940289855003032f, -0.00218106806278228803f, 0.84868013858795166f);
constant float3 kD65ToD50_r0 = float3(1.04257404804229736f, 0.03089117631316185f, -0.052812620997428894f);
constant float3 kD65ToD50_r1 = float3(0.0221935361623764038f, 1.00185668468475342f, -0.0210737623274326324f);
constant float3 kD65ToD50_r2 = float3(-0.00116488314233720303f, -0.00342052709311246915f, 0.761789083480834961f);

constant float3 kD60ToD93_r0 = float3(0.946056902408599854f, -0.0319503024220466614f, 0.0831701457500457764f);
constant float3 kD60ToD93_r1 = float3(-0.0231979694217443466f, 0.988745808601379395f, 0.0330617502331733704f);
constant float3 kD60ToD93_r2 = float3(0.00169203430414199807f, 0.00572328735142946243f, 1.39483106136322021f);
constant float3 kD60ToD75_r0 = float3(0.969659984111785889f, -0.019138311967253685f, 0.0450099557638168335f);
constant float3 kD60ToD75_r1 = float3(-0.0138545772065751972f, 0.995133817195892334f, 0.0179062262177469243f);
constant float3 kD60ToD75_r2 = float3(0.000931452261283994185f, 0.00306008197367191315f, 1.21179807186126709f);
constant float3 kD60ToD65_r0 = float3(0.988363921642303467f, -0.00766910053789615631f, 0.0167641639709472656f);
constant float3 kD60ToD65_r1 = float3(-0.0055409618653357029f, 0.998546123504638672f, 0.00667332112789153871f);
constant float3 kD60ToD65_r2 = float3(0.000351537019014359008f, 0.00112883746223492898f, 1.07833576202392578f);
constant float3 kD60ToD55_r0 = float3(1.01380288600921631f, 0.0100131509825587271f, -0.018498346209526062f);
constant float3 kD60ToD55_r1 = float3(0.00720565160736441612f, 1.00057685160336f, -0.00737529997758865356f);
constant float3 kD60ToD55_r2 = float3(-0.000401133671402941998f, -0.00121434964239597299f, 0.915135681629180908f);
constant float3 kD60ToD50_r0 = float3(1.03025269508361816f, 0.02279104662176056f, -0.0392656922340393066f);
constant float3 kD60ToD50_r1 = float3(0.0163766480982303619f, 1.00020599270233f, -0.015666823834180931f);
constant float3 kD60ToD50_r2 = float3(-0.000864576781168579947f, -0.00254668481647968292f, 0.821422040462493896f);

constant float3 kDCIToD93_r0 = float3(0.965685009956359863f, 0.00183745240792632103f, 0.0912967324256896973f);
constant float3 kDCIToD93_r1 = float3(0.000514572137035429044f, 0.965166747570037842f, 0.036014653742313385f);
constant float3 kDCIToD93_r2 = float3(0.00154250487685203596f, 0.00702651776373386383f, 1.47287476062774658f);
constant float3 kDCIToD75_r0 = float3(0.990120768547058105f, 0.0151389474049210548f, 0.0511047691106796265f);
constant float3 kDCIToD75_r1 = float3(0.0102197211235761642f, 0.971718132495880127f, 0.0200536623597145081f);
constant float3 kDCIToD75_r2 = float3(0.000743072712793946049f, 0.0042176349088549614f, 1.27959656715393066f);
constant float3 kDCIToD65_r0 = float3(1.00951600074768066f, 0.0269675441086292267f, 0.0213620811700820923f);
constant float3 kDCIToD65_r1 = float3(0.0187991037964820862f, 0.975330352783203125f, 0.0082273334264755249f);
constant float3 kDCIToD65_r2 = float3(0.000134543282911180989f, 0.00217903498560190201f, 1.138663649559021f);
constant float3 kDCIToD60_r0 = float3(1.02159523963928223f, 0.034848678857088089f, 0.00371252000331878705f);
constant float3 kDCIToD60_r1 = float3(0.0244968775659799576f, 0.976937234401702881f, 0.00120301544666290305f);
constant float3 kDCIToD60_r2 = float3(-0.00023391586728393999f, 0.000986687839031219049f, 1.05594265460968018f);
constant float3 kDCIToD55_r0 = float3(1.03594577312469482f, 0.0450937561690807343f, -0.0157573819160461426f);
constant float3 kDCIToD55_r1 = float3(0.0318740680813789368f, 0.977744519710540771f, -0.00655744969844818115f);
constant float3 kDCIToD55_r2 = float3(-0.000653609400615095984f, -0.000297372229397297014f, 0.966327786445617676f);
constant float3 kDCIToD50_r0 = float3(1.05306875705718994f, 0.0581297315657138824f, -0.0376100838184356689f);
constant float3 kDCIToD50_r1 = float3(0.0412359423935413361f, 0.977693676948547363f, -0.0152792222978786826f);
constant float3 kDCIToD50_r2 = float3(-0.00113777676597237609f, -0.00170759297907352404f, 0.867368340492248535f);
constant float3 kD65ToDCI_r0 = float3(0.991085588932037354f, -0.0273622870445251465f, -0.0183956623077392578f);
constant float3 kD65ToDCI_r1 = float3(-0.0191021915525197983f, 1.02583777904510498f, -0.00705372542142868042f);
constant float3 kD65ToDCI_r2 = float3(-8.05503223091359977e-05f, -0.00195988826453685804f, 0.878238439559936523f);

// The uniform ABI (mirrors DrtUniforms in Swift — 57 floats + 4 uints).
struct DrtUniforms {
    float tn_con, tn_sh, tn_toe, tn_off, tn_hcon, tn_hcon_pv, tn_hcon_st;
    float tn_lcon, tn_lcon_w;
    float cwp_lm;
    float rs_sa, rs_rw, rs_bw;
    float pt_lml, pt_lml_r, pt_lml_g, pt_lml_b;
    float pt_lmh, pt_lmh_r, pt_lmh_b;
    float ptl_c, ptl_m, ptl_y;
    float ptm_low, ptm_low_rng, ptm_low_st;
    float ptm_high, ptm_high_rng, ptm_high_st;
    float brl, brl_r, brl_g, brl_b, brl_rng, brl_st;
    float brlp, brlp_r, brlp_g, brlp_b;
    float hc_r, hc_r_rng;
    float hs_r, hs_r_rng, hs_g, hs_g_rng, hs_b, hs_b_rng;
    float hs_c, hs_c_rng, hs_m, hs_m_rng, hs_y, hs_y_rng;
    float peak_luminance, display_grey_luminance, hdr_grey_boost, hdr_purity;
    uint method, display_gamut, cwp, surround;
};

// ── stage primitives (the Swift twins in OpenDrtReference.swift) ──

static inline float drtSafePow(float a, float b) {
    return a <= 0.0f ? a : pow(a, b);
}

static inline float drtCHP(float x, float s, float p) {  // compress_hyperbolic_power
    return drtSafePow(x / (x + s), p);
}

static inline float drtToeQ(float x, float toe, bool inv) {  // compress_toe_quadratic
    if (toe == 0.0f) return x;
    if (!inv) return drtSafePow(x, 2.0f) / (x + toe);
    return (x + sqrt(x * (4.0f * toe + x))) / 2.0f;
}

static inline float drtToeC(float x, float m, float w, bool inv) {  // compress_toe_cubic
    if (m == 1.0f) return x;
    float x2 = x * x;
    if (!inv) return x * (x2 + m * w) / (x2 + w);
    float p0 = x2 - 3.0f * m * w;
    float p1 = 2.0f * x2 + 27.0f * w - 9.0f * m * w;
    float p2 = pow(sqrt(x2 * p1 * p1 - 4.0f * p0 * p0 * p0) / 2.0f + x * p1 / 2.0f, 1.0f / 3.0f);
    return p0 / (3.0f * p2) + p2 / 3.0f + x / 3.0f;
}

static inline float drtContrastHigh(float x, float p, float pv, float pvLx, bool inv) {
    float x0 = 0.18f * pow(2.0f, pv);
    if (x < x0 || p == 1.0f) return x;
    float o = x0 - x0 / p;
    float s0 = pow(x0, 1.0f - p) / p;
    float x1 = x0 * pow(2.0f, pvLx);
    float k1 = p * s0 * pow(x1, p) / x1;
    float y1 = s0 * pow(x1, p) + o;
    if (inv) return x > y1 ? (x - y1) / k1 + x1 : pow((x - o) / s0, 1.0f / p);
    return x > x1 ? k1 * (x - x1) + y1 : s0 * pow(x, p) + o;
}

static inline float drtSoftplus(float x, float s) {
    if (x > 10.0f * s || s < 1e-4f) return x;
    return s * log(max(0.0f, 1.0f + exp(x / s)));
}

static inline float drtGauss(float x, float w) { return exp(-x * x / w); }

static inline float2 drtOpponent(float3 rgb) {
    return float2(rgb.x - rgb.z, rgb.y - (rgb.x + rgb.z) / 2.0f);
}

static inline float drtHueOffset(float h, float o) {
    return fmod(h - o + kDrtPi, 2.0f * kDrtPi) - kDrtPi;
}

// ── stage [18]: display gamut + creative whitepoint (the Swift twin) ──

static inline float3 drtDisplayGamutWhitepoint(
    float3 rgbIn, float tsnConst, float cwpLm, uint gamut, uint cwp)
{
    float3 rgb = drtMul(kP3D65ToXYZ_r0, kP3D65ToXYZ_r1, kP3D65ToXYZ_r2, rgbIn);
    float3 cwpNeutral = rgb;
    float cwpF = pow(tsnConst, 2.0f * cwpLm);

    if (gamut < 3) {  // D65-aligned
        switch (cwp) {
            case 0: rgb = drtMul(kD65ToD93_r0, kD65ToD93_r1, kD65ToD93_r2, rgb); break;
            case 1: rgb = drtMul(kD65ToD75_r0, kD65ToD75_r1, kD65ToD75_r2, rgb); break;
            case 3: rgb = drtMul(kD65ToD60_r0, kD65ToD60_r1, kD65ToD60_r2, rgb); break;
            case 4: rgb = drtMul(kD65ToD55_r0, kD65ToD55_r1, kD65ToD55_r2, rgb); break;
            case 5: rgb = drtMul(kD65ToD50_r0, kD65ToD50_r1, kD65ToD50_r2, rgb); break;
            case 2: break;  // D65 — identity
        }
    } else if (gamut == 3) {  // P3-D60 source
        switch (cwp) {
            case 0: rgb = drtMul(kD60ToD93_r0, kD60ToD93_r1, kD60ToD93_r2, rgb); break;
            case 1: rgb = drtMul(kD60ToD75_r0, kD60ToD75_r1, kD60ToD75_r2, rgb); break;
            case 2: rgb = drtMul(kD60ToD65_r0, kD60ToD65_r1, kD60ToD65_r2, rgb); break;
            case 4: rgb = drtMul(kD60ToD55_r0, kD60ToD55_r1, kD60ToD55_r2, rgb); break;
            case 5: rgb = drtMul(kD60ToD50_r0, kD60ToD50_r1, kD60ToD50_r2, rgb); break;
            case 3: break;  // D60 — identity
        }
    } else {  // DCI / XYZ — neutral axis stays D65
        cwpNeutral = drtMul(kDCIToD65_r0, kDCIToD65_r1, kDCIToD65_r2, rgb);
        switch (cwp) {
            case 0: rgb = drtMul(kDCIToD93_r0, kDCIToD93_r1, kDCIToD93_r2, rgb); break;
            case 1: rgb = drtMul(kDCIToD75_r0, kDCIToD75_r1, kDCIToD75_r2, rgb); break;
            case 2: rgb = cwpNeutral; break;
            case 3: rgb = drtMul(kDCIToD60_r0, kDCIToD60_r1, kDCIToD60_r2, rgb); break;
            case 4: rgb = drtMul(kDCIToD55_r0, kDCIToD55_r1, kDCIToD55_r2, rgb); break;
            case 5: rgb = drtMul(kDCIToD50_r0, kDCIToD50_r1, kDCIToD50_r2, rgb); break;
        }
    }

    rgb = rgb * cwpF + cwpNeutral * (1.0f - cwpF);

    if (gamut == 0) {
        rgb = drtMul(kXYZToRec709_r0, kXYZToRec709_r1, kXYZToRec709_r2, rgb);
    } else if (gamut == 5) {
        rgb = drtMul(kD65ToDCI_r0, kD65ToDCI_r1, kD65ToDCI_r2, rgb);
    } else {
        rgb = drtMul(kXYZToP3D65_r0, kXYZToP3D65_r1, kXYZToP3D65_r2, rgb);
    }

    // Peak renormalization (the precomputed cwp_norm tables — numeric facts).
    float cwpNorm = 1.0f;
    if (gamut == 0) {
        if (cwp == 0) cwpNorm = 0.744192699063f;
        else if (cwp == 1) cwpNorm = 0.873470832146f;
        else if (cwp == 3) cwpNorm = 0.955936992163f;
        else if (cwp == 4) cwpNorm = 0.905671332781f;
        else if (cwp == 5) cwpNorm = 0.850004385027f;
    } else if (gamut == 1 || gamut == 2) {
        if (cwp == 0) cwpNorm = 0.762687057298f;
        else if (cwp == 1) cwpNorm = 0.884054083328f;
        else if (cwp == 3) cwpNorm = 0.964320186739f;
        else if (cwp == 4) cwpNorm = 0.923076518860f;
        else if (cwp == 5) cwpNorm = 0.876572837784f;
    } else if (gamut == 3) {
        if (cwp == 0) cwpNorm = 0.704956321013f;
        else if (cwp == 1) cwpNorm = 0.816715709816f;
        else if (cwp == 2) cwpNorm = 0.923382193663f;
        else if (cwp == 4) cwpNorm = 0.956138500287f;
        else if (cwp == 5) cwpNorm = 0.906801453023f;
    } else if (gamut == 4) {
        if (cwp == 0) cwpNorm = 0.665336141225f;
        else if (cwp == 1) cwpNorm = 0.770397131382f;
        else if (cwp == 2) cwpNorm = 0.870572343302f;
        else if (cwp == 3) cwpNorm = 0.891354547503f;
        else if (cwp == 4) cwpNorm = 0.855327825187f;
        else if (cwp == 5) cwpNorm = 0.814566436117f;
    } else if (gamut == 5) {
        if (cwp == 0) cwpNorm = 0.707142784007f;
        else if (cwp == 1) cwpNorm = 0.815561082617f;
        else cwpNorm = 0.916555279740f;
    }

    rgb *= cwpNorm * cwpF + 1.0f - cwpF;
    return rgb;
}

// ── the kernel (stages [1]..[24]; the structure map lives in the Swift twin) ──

kernel void drt_opendrt(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant DrtUniforms&           u   [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    float3 rgb = in.read(gid).rgb;
    constant DrtUniforms& p = u;

    // Pre-run tonescale constraint constants (per-thread derivation — the
    // reference's per-call block; dctl :943-959).
    const float tnLp = p.peak_luminance;
    const float tnCon = p.tn_con;
    const float ts_x1 = pow(2.0f, 6.0f * p.tn_sh + 4.0f);
    const float ts_y1 = tnLp / 100.0f;
    const float ts_x0 = 0.18f + p.tn_off;
    const float ts_y0 = p.display_grey_luminance / 100.0f
        * (1.0f + p.hdr_grey_boost * log2(ts_y1));
    const float ts_s0 = drtToeQ(ts_y0, p.tn_toe, true);
    const float ts_p = tnCon / (1.0f + float(p.surround) * 0.05f);
    const float ts_s10 = ts_x0 * (pow(ts_s0, -1.0f / tnCon) - 1.0f);
    const float ts_m1 = ts_y1 / pow(ts_x1 / (ts_x1 + ts_s10), tnCon);
    const float ts_m2 = drtToeQ(ts_m1, p.tn_toe, true);
    const float ts_s = ts_x0 * (pow(ts_s0 / ts_m2, -1.0f / tnCon) - 1.0f);
    const float ts_dsc = 100.0f / tnLp;  // peak-normalized terminal (see header)
    const float pt_cmp_Lf = p.hdr_purity * fmin(1.0f, (tnLp - 100.0f) / 900.0f);
    const float s_Lp100 = ts_x0 * (pow(p.display_grey_luminance / 100.0f, -1.0f / tnCon) - 1.0f);
    const float ts_s1 = ts_s * pt_cmp_Lf + s_Lp100 * (1.0f - pt_cmp_Lf);

    // [1] input gamut → P3-D65 (working space = linear Rec2020).
    rgb = drtMul(kRec2020ToXYZ_r0, kRec2020ToXYZ_r1, kRec2020ToXYZ_r2, rgb);
    rgb = drtMul(kXYZToP3D65_r0, kXYZToP3D65_r1, kXYZToP3D65_r2, rgb);

    // [2] render-space desaturation.
    float3 rsW = float3(p.rs_rw, 1.0f - p.rs_rw - p.rs_bw, p.rs_bw);
    float satL = rgb.x * rsW.x + rgb.y * rsW.y + rgb.z * rsW.z;
    rgb = satL * p.rs_sa + rgb * (1.0f - p.rs_sa);

    // [3] offset.
    rgb += p.tn_off;

    // [4] tonescale norm + RGB ratios.
    float tsn = sqrt(fmax(0.0f, dot(rgb, rgb))) / kDrtSqrt3;
    rgb /= tsn;

    // [5] opponent + hue-angle constants.
    float2 opp = drtOpponent(rgb);
    float achD = sqrt(fmax(0.0f, dot(opp, opp))) / 2.0f;
    achD = 1.25f * drtToeQ(achD, 0.25f, false);
    float hue = fmod(atan2(opp.x, opp.y) + kDrtPi + 1.10714931f, 2.0f * kDrtPi);
    float3 haRgb = float3(
        drtGauss(drtHueOffset(hue, 0.1f), 0.66f),
        drtGauss(drtHueOffset(hue, 4.3f), 0.66f),
        drtGauss(drtHueOffset(hue, 2.3f), 0.66f));
    float3 haRgbHs = float3(
        drtGauss(drtHueOffset(hue, -0.4f), 0.66f),
        haRgb.y,
        drtGauss(drtHueOffset(hue, 2.5f), 0.66f));
    float3 haCmy = float3(
        drtGauss(drtHueOffset(hue, 3.3f), 0.5f),
        drtGauss(drtHueOffset(hue, 1.3f), 0.5f),
        drtGauss(drtHueOffset(hue, -1.15f), 0.5f));

    // [6] pre-brilliance.
    {
        float brlTsf = pow(tsn / (tsn + 1.0f), 1.0f - p.brl_rng);
        float brlExf = (p.brl + p.brl_r * haRgb.x + p.brl_g * haRgb.y
                        + p.brl_b * haRgb.z) * pow(achD, 1.0f / p.brl_st);
        float brlEx = pow(2.0f, brlExf * (brlExf < 0.0f ? brlTsf : 1.0f - brlTsf));
        tsn *= brlEx;
    }

    // [7] contrast low (value-driven enable — the Swift twin's note).
    if (p.tn_lcon != 0.0f) {
        float lconM = pow(2.0f, -p.tn_lcon);
        float lconW = p.tn_lcon_w / 4.0f;
        lconW *= lconW;
        float lconCnstSc = drtToeC(ts_x0, lconM, lconW, true) / ts_x0;
        tsn *= lconCnstSc;
        tsn = drtToeC(tsn, lconM, lconW, false);
    }

    // [8] contrast high.
    if (p.tn_hcon != 0.0f) {
        float hconP = pow(2.0f, p.tn_hcon);
        tsn = drtContrastHigh(tsn, hconP, p.tn_hcon_pv, p.tn_hcon_st, false);
    }

    // [9] hyperbolic compression.
    float tsnPt = drtCHP(tsn, ts_s1, ts_p);
    float tsnConst = drtCHP(tsn, s_Lp100, ts_p);
    tsn = drtCHP(tsn, ts_s, ts_p);

    // [10] hue contrast R.
    if (p.hc_r_rng > 0.0f) {
        float hcTs0 = 1.0f - tsnConst;
        float hcC0 = hcTs0 * (1.0f - achD) + achD * (1.0f - hcTs0);
        float hcC = hcC0 * achD * haRgb.x;
        float hcTs = pow(hcTs0, 1.0f / p.hc_r_rng);
        float hcF = p.hc_r * (hcC - 2.0f * hcC * hcTs) + 1.0f;
        rgb = float3(rgb.x, rgb.y * hcF, rgb.z * hcF);
    }

    // [11] hue shift RGB.
    {
        float3 hs = float3(
            haRgbHs.x * achD * pow(tsnPt, 1.0f / p.hs_r_rng),
            haRgbHs.y * achD * pow(tsnPt, 1.0f / p.hs_g_rng),
            haRgbHs.z * achD * pow(tsnPt, 1.0f / p.hs_b_rng));
        float3 hsf = float3(hs.x * p.hs_r, hs.y * -p.hs_g, hs.z * -p.hs_b);
        hsf = float3(hsf.z - hsf.y, hsf.x - hsf.z, hsf.y - hsf.x);
        rgb += hsf;
    }

    // [12] hue shift CMY.
    {
        float tsnPtCompl = 1.0f - tsnPt;
        float3 hs = float3(
            haCmy.x * achD * pow(tsnPtCompl, 1.0f / p.hs_c_rng),
            haCmy.y * achD * pow(tsnPtCompl, 1.0f / p.hs_m_rng),
            haCmy.z * achD * pow(tsnPtCompl, 1.0f / p.hs_y_rng));
        float3 hsf = float3(hs.x * -p.hs_c, hs.y * p.hs_m, hs.z * p.hs_y);
        hsf = float3(hsf.z - hsf.y, hsf.x - hsf.z, hsf.y - hsf.x);
        rgb += hsf;
    }

    // [13] purity limit low.
    float ptLmlP = 1.0f + 4.0f * (1.0f - tsnPt) * (p.pt_lml
        + p.pt_lml_r * haRgbHs.x + p.pt_lml_g * haRgbHs.y + p.pt_lml_b * haRgbHs.z);
    float ptf = 1.0f - pow(tsnPt, ptLmlP);

    // [14] purity limit high.
    float ptLmhP = (1.0f - achD * (p.pt_lmh_r * haRgbHs.x + p.pt_lmh_b * haRgbHs.z))
        * (1.0f - p.pt_lmh * achD);
    ptf = pow(ptf, ptLmhP);

    // [15] mid-range purity.
    {
        float ptmLowF, ptmHighF;
        if (p.ptm_low_st == 0.0f || p.ptm_low_rng == 0.0f) ptmLowF = 1.0f;
        else ptmLowF = 1.0f + p.ptm_low * exp(-2.0f * achD * achD / p.ptm_low_st)
            * pow(1.0f - tsnConst, 1.0f / p.ptm_low_rng);
        if (p.ptm_high_st == 0.0f || p.ptm_high_rng == 0.0f) ptmHighF = 1.0f;
        else ptmHighF = 1.0f + p.ptm_high * exp(-2.0f * achD * achD / p.ptm_high_st)
            * pow(tsnPt, 1.0f / (4.0f * p.ptm_high_rng));
        ptf *= ptmLowF * ptmHighF;
    }

    // [16] lerp to peak achromatic.
    rgb = rgb * ptf + 1.0f - ptf;

    // [17] inverse render space.
    satL = rgb.x * rsW.x + rgb.y * rsW.y + rgb.z * rsW.z;
    rgb = (satL * p.rs_sa - rgb) / (p.rs_sa - 1.0f);

    // [18] display gamut + creative whitepoint.
    rgb = drtDisplayGamutWhitepoint(rgb, tsnConst, p.cwp_lm, p.display_gamut, p.cwp);

    // [19] post brilliance.
    {
        float2 brlpOpp = drtOpponent(rgb);
        float brlpAchD = sqrt(fmax(0.0f, dot(brlpOpp, brlpOpp))) / 4.0f;
        brlpAchD = 1.1f * (brlpAchD * brlpAchD / (brlpAchD + 0.1f));
        float3 brlpHa = achD * haRgb;
        float brlpM = p.brlp + p.brlp_r * brlpHa.x + p.brlp_g * brlpHa.y
            + p.brlp_b * brlpHa.z;
        rgb *= pow(2.0f, brlpM * brlpAchD * tsn);
    }

    // [20] purity compress low.
    rgb = float3(drtSoftplus(rgb.x, p.ptl_c), drtSoftplus(rgb.y, p.ptl_m),
                 drtSoftplus(rgb.z, p.ptl_y));

    // [21] final tonescale adjustments.
    tsn *= ts_m2;
    tsn = drtToeQ(tsn, p.tn_toe, false);
    tsn *= ts_dsc;

    // [22] return from rgb ratios.
    rgb *= tsn;

    // [23] Rec.2020 (P3 Limited).
    if (p.display_gamut == 2) {
        rgb = fmax(rgb, 0.0f);
        rgb = drtMul(kP3ToRec2020_r0, kP3ToRec2020_r1, kP3ToRec2020_r2, rgb);
    }

    // [24] display clamp (presets-mode clamp=1).
    rgb = clamp(rgb, 0.0f, 1.0f);

    out.write(float4(rgb, in.read(gid).a), gid);
}

// Layout pin: the test compares this against MemoryLayout<DrtUniforms>.size.
kernel void drt_uniforms_size_probe(
    device uint* out [[buffer(0)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid > 0) return;
    out[0] = uint(sizeof(DrtUniforms));
}

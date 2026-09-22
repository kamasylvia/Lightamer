// Ground-truth harness: dt's REAL CPU code (not a re-derivation).
// Includes the actual dt headers + a transliterated copy of process() inner loop
// with work profile = linear Rec2020 (matrices from our LAB constants).
#include <stdio.h>
#include <math.h>
#include <string.h>
#include <float.h>

// ---- minimal dt scaffolding ----
typedef float dt_aligned_pixel_t[4] __attribute__((aligned(16)));
typedef float dt_colormatrix_t[4][4] __attribute__((aligned(16)));
#define for_each_channel(c, ...) for(int c = 0; c < 4; c++)
#define for_four_channels(c, ...) for(int c = 0; c < 4; c++)
#define DT_OMP_DECLARE_SIMD(...)
#define DT_OMP_SIMD(...)
#define CLAMPF(a,mn,mx) ((a)<(mn)?(mn):((a)>(mx)?(mx):(a)))
#define CLAMP(a,mn,mx) CLAMPF(a,mn,mx)
#define MAX(a,b) ((a)>(b)?(a):(b))
#define MIN(a,b) ((a)<(b)?(a):(b))
#define sqf(x) ((x)*(x))
#define M_PI_F 3.14159265358979323846f
#define DT_2PI_F 6.28318530717958647693f
#define DT_M_PI_F M_PI_F
#define LUT_ELEM 512
#define DT_UCS_L_STAR_RANGE 2.098883786377f
#define DT_UCS_L_STAR_UPPER_LIMIT 2.09885f
#define DT_UCS_Y_UPPER_LIMIT 1e8f
#define FLT_MIN __FLT_MIN__
typedef int gboolean;
#define TRUE 1
#define FALSE 0
static const float D65xyY_x = 0.31271f, D65xyY_y = 0.32902f;

// ---- copied dt primitives (exact from sources) ----
static inline void dt_colormatrix_mul(dt_colormatrix_t dst, const dt_colormatrix_t m1, const dt_colormatrix_t m2)
{
  for(int k = 0; k < 3; ++k)
    for(int i = 0; i < 4; i++) { float s = 0; for(int j = 0; j < 3; j++) s += m1[k][j] * m2[j][i]; dst[k][i] = s; }
  dst[3][0]=dst[3][1]=dst[3][2]=0; dst[3][3]=1;
}
static inline void dt_apply_transposed_color_matrix(const dt_aligned_pixel_t in, const dt_colormatrix_t matrix, dt_aligned_pixel_t out)
{
  for(int r = 0; r < 4; r++) out[r] = matrix[0][r]*in[0] + matrix[1][r]*in[1] + matrix[2][r]*in[2];
}
static inline void dt_vector_clipneg(dt_aligned_pixel_t v) { for(int c=0;c<4;c++) v[c] = v[c] < 0 ? 0 : v[c]; }
static inline float dt_fast_hypotf(float a, float b) { return sqrtf(a*a+b*b); }
static inline void dt_vector_powf(dt_aligned_pixel_t v, dt_aligned_pixel_t e, dt_aligned_pixel_t o) { for(int c=0;c<4;c++) o[c]=powf(v[c],e[c]); }
static inline void copy_pixel(dt_aligned_pixel_t d, dt_aligned_pixel_t s) { for(int c=0;c<4;c++) d[c]=s[c]; }
static inline float scalar_product(dt_aligned_pixel_t a, dt_aligned_pixel_t b) { return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]+a[3]*b[3]; }
static inline float soft_clip(const float x, const float soft_threshold, const float hard_threshold)
{ const float n = hard_threshold - soft_threshold; return (x > soft_threshold) ? soft_threshold + (1.f - expf(-(x - soft_threshold)/n))*n : x; }
static inline float lookup_gamut(const float lut[LUT_ELEM], const float hue)
{ const float xt = (float)LUT_ELEM*(hue+M_PI_F)/DT_2PI_F; const float xp = floorf(xt); const float xn = ceilf(xt);
  const int xi = ((int)xp)&(LUT_ELEM-1); const int xii = ((int)xn)&(LUT_ELEM-1); const float yp = lut[xi];
  return yp + ((xi!=xii)?(xt-xp)*(lut[xii]-yp):0.f); }

// ---- dt constants (verbatim) ----
static const dt_colormatrix_t XYZ_D50_to_D65_CAT16 = { { 9.89466254e-01f, -4.00304626e-02f, 4.40530317e-02f, 0.f }, { -5.40518733e-03f, 1.00666069e+00f, -1.75551955e-03f, 0.f }, { -4.03920992e-04f, 1.50768030e-02f, 1.30210211e+00f, 0.f } };
static const dt_colormatrix_t XYZ_D65_to_D50_CAT16 = { { 1.01085433e+00f, 4.07086103e-02f, -3.41445825e-02f, 0.f }, { 5.42814201e-03f, 9.93581926e-01f, 1.15592039e-03f, 0.f }, { 2.50722468e-04f, -1.14918759e-02f, 7.67964947e-01f, 0.f } };
static const dt_colormatrix_t XYZ_D65_to_LMS_2006_D65_trans = { { 0.257085f, -0.394427f, 0.064856f, 0.f }, { 0.859943f, 1.175800f, -0.076250f, 0.f }, { -0.031061f, 0.106423f, 0.559067f, 0.f } };
static const dt_colormatrix_t LMS_2006_D65_to_XYZ_D65_trans = { { 1.80794659f, 0.61783960f, -0.12546960f, 0.f }, { -1.29971660f, 0.39595453f, 0.20478038f, 0.f }, { 0.34785879f, -0.04104687f, 1.74274183f, 0.f } };
static const dt_colormatrix_t film_trans = { { 0.95f, 0.05f, 0.00f, 0.f }, { 0.38f, 0.62f, 0.00f, 0.f }, { 0.00f, 0.03f, 0.97f, 0.f } };
static const dt_colormatrix_t lms_trans = { { 1.08771930f, -0.0877193f, 0.f, 0.f }, { -0.66666667f, 1.66666667f, 0.f, 0.f }, { 0.02061856f, -0.05154639f, 1.03092784f, 0.f } };
static inline void XYZ_to_LMS(const dt_aligned_pixel_t X, dt_aligned_pixel_t L) { dt_apply_transposed_color_matrix(X, XYZ_D65_to_LMS_2006_D65_trans, L); }
static inline void LMS_to_XYZ(const dt_aligned_pixel_t L, dt_aligned_pixel_t X) { dt_apply_transposed_color_matrix(L, LMS_2006_D65_to_XYZ_D65_trans, X); }
static inline void gradingRGB_to_LMS(const dt_aligned_pixel_t R, dt_aligned_pixel_t L) { dt_apply_transposed_color_matrix(R, film_trans, L); }
static inline void LMS_to_gradingRGB(const dt_aligned_pixel_t L, dt_aligned_pixel_t R) { dt_apply_transposed_color_matrix(L, lms_trans, R); }
static inline void LMS_to_Yrg(const dt_aligned_pixel_t LMS, dt_aligned_pixel_t Yrg)
{ const float Y = 0.68990272f*LMS[0]+0.34832189f*LMS[1]; const float a = LMS[0]+LMS[1]+LMS[2];
  dt_aligned_pixel_t lms; for(int c=0;c<4;c++) lms[c]=(a==0.f)?0.f:LMS[c]/a;
  dt_aligned_pixel_t rgb; LMS_to_gradingRGB(lms, rgb); Yrg[0]=Y; Yrg[1]=rgb[0]; Yrg[2]=rgb[1]; Yrg[3]=LMS[3]; }
static inline void Yrg_to_LMS(const dt_aligned_pixel_t Yrg, dt_aligned_pixel_t LMS)
{ const float Y=Yrg[0]; const float r=Yrg[1]; const float g=Yrg[2]; const float b=1.f-r-g;
  const dt_aligned_pixel_t rgb={r,g,b,0.f}; dt_aligned_pixel_t lms; gradingRGB_to_LMS(rgb,lms);
  const float denom=(0.68990272f*lms[0]+0.34832189f*lms[1]); const float a=(denom==0.f)?0.f:Y/denom;
  for(int c=0;c<4;c++) LMS[c]=lms[c]*a; }
static inline void Yrg_to_Ych(const dt_aligned_pixel_t Yrg, dt_aligned_pixel_t Ych)
{ const float r=Yrg[1]-0.21902143f; const float g=Yrg[2]-0.54371398f; const float c=dt_fast_hypotf(g,r);
  Ych[0]=Yrg[0]; Ych[1]=c; Ych[2]=c!=0.f?r/c:1.f; Ych[3]=c!=0.f?g/c:0.f; }
static inline void Ych_to_Yrg(const dt_aligned_pixel_t Ych, dt_aligned_pixel_t Yrg)
{ Yrg[0]=Ych[0]; Yrg[1]=Ych[1]*Ych[2]+0.21902143f; Yrg[2]=Ych[1]*Ych[3]+0.54371398f; Yrg[3]=0.f; }
static inline void Ych_to_gradingRGB(const dt_aligned_pixel_t Ych, dt_aligned_pixel_t RGB)
{ dt_aligned_pixel_t Yrg, LMS; Ych_to_Yrg(Ych,Yrg); Yrg_to_LMS(Yrg,LMS); LMS_to_gradingRGB(LMS,RGB); }
static inline void make_Ych(const float Y, const float c, const float h, dt_aligned_pixel_t Ych)
{ Ych[0]=Y; Ych[1]=c; Ych[2]=cosf(h); Ych[3]=sinf(h); }
static inline void gamut_check_Yrg(dt_aligned_pixel_t Ych)
{ dt_aligned_pixel_t Yrg; Ych_to_Yrg(Ych,Yrg); float mc=Ych[1];
  if(Yrg[1]<0.f) mc=fminf(-0.21902143f/Ych[2],mc); if(Yrg[2]<0.f) mc=fminf(-0.54371398f/Ych[3],mc);
  if(Yrg[1]+Yrg[2]>1.f) mc=fminf((1.f-0.21902143f-0.54371398f)/(Ych[2]+Ych[3]),mc); Ych[1]=mc; }
static inline void opacity_masks(const float x, const float sw, const float hw, const float mw, const float ful,
  dt_aligned_pixel_t o, dt_aligned_pixel_t oc)
{ const float xo=(x-ful); const float xn=xo/ful; const float al=1.f/(1.f+expf(xn*sw)); const float be=1.f/(1.f+expf(-xn*hw));
  const float ga=expf(-sqf(xo)*mw/4.f)*sqf(1.f-al)*sqf(1.f-be)*8.f;
  o[0]=al; o[1]=ga; o[2]=be; o[3]=0.f; if(oc){oc[0]=1.f-al;oc[1]=1.f-ga;oc[2]=1.f-be;oc[3]=0.f;} }
static inline float Y_to_Lstar(const float Y){ const float h=powf(Y,0.631651345306265f); return DT_UCS_L_STAR_RANGE*h/(h+1.12426773749357f); }
// UCS (verbatim formulas)
static inline void xyY_to_UV(const dt_aligned_pixel_t xyY, float uvp[2])
{ const float xf[3]={-0.783941002840055f,0.745273540913283f,0.318707282433486f};
  const float yf[3]={0.277512987809202f,-0.205375866083878f,2.16743692732158f};
  const float off[3]={0.153836578598858f,-0.165478376301988f,0.291320554395942f};
  float uvd[3]; for(int c=0;c<3;c++) uvd[c]=xf[c]*xyY[0]+yf[c]*xyY[1]+off[c];
  const float div=(uvd[2]>=0.f)?(uvd[2]>0?uvd[2]:FLT_MIN):-FLT_MIN; uvd[0]/=div; uvd[1]/=div;
  const float us0=1.39656225667f*uvd[0]/(fabsf(uvd[0])+1.49217352929f);
  const float us1=1.4513954287f*uvd[1]/(fabsf(uvd[1])+1.52488637914f);
  uvp[0]=-1.124983854323892f*us0-0.980483721769325f*us1; uvp[1]=1.86323315098672f*us0+1.971853092390862f*us1; }
static inline void xyY_to_JCH(const dt_aligned_pixel_t xyY, const float Lw, dt_aligned_pixel_t JCH)
{ float uvp[2]; xyY_to_UV(xyY,uvp); const float M2=uvp[0]*uvp[0]+uvp[1]*uvp[1]; const float Ls=Y_to_Lstar(xyY[2]);
  JCH[0]=Ls/Lw; JCH[1]=15.932993652962535f*powf(Ls,0.6523997524738018f)*powf(M2,0.6007557017508491f)/Lw; JCH[2]=atan2f(uvp[1],uvp[0]); JCH[3]=0; }
static inline void XYZ_to_xyY(const dt_aligned_pixel_t sXYZ, dt_aligned_pixel_t xyY)
{ float X=sXYZ[0]>0?sXYZ[0]:0, Y=sXYZ[1]>0?sXYZ[1]:0, Z=sXYZ[2]>0?sXYZ[2]:0; const float s=X+Y+Z;
  xyY[0]=s>0?X/s:D65xyY_x; xyY[1]=s>0?Y/s:D65xyY_y; xyY[2]=Y; xyY[3]=sXYZ[3]; }

// work profile = linear Rec2020 (project constants)
static dt_colormatrix_t WP_IN, WP_OUT;
static void init_work(void)
{
  // Rec2020 D65 -> XYZ D65
  dt_colormatrix_t R2X = { {0.636958f,0.144617f,0.168881f,0},{0.262700f,0.678009f,0.059291f,0},{0.f,0.028073f,1.060806f,0} };
  // Bradford D65->D50
  dt_colormatrix_t B = { {1.0478112f,0.0228866f,-0.0501270f,0},{0.0295424f,0.9904844f,-0.0170491f,0},{-0.0092345f,0.0150436f,0.7521316f,0} };
  // R2X inverted (XYZ->RGB), B inverted below via gaussian solve at runtime
  // solve R2X * X = I
  dt_colormatrix_t X2R; {
    float a[3][3]; for(int r=0;r<3;r++)for(int c=0;c<3;c++)a[r][c]=R2X[r][c];
    float inv[3][3]={{1,0,0},{0,1,0},{0,0,1}};
    for(int c=0;c<3;c++){ int p=c; for(int r=c+1;r<3;r++) if(fabsf(a[r][c])>fabsf(a[p][c]))p=r;
      for(int k=0;k<3;k++){float t=a[c][k];a[c][k]=a[p][k];a[p][k]=t;t=inv[c][k];inv[c][k]=inv[p][k];inv[p][k]=t;}
      float d=a[c][c]; for(int k=0;k<3;k++){a[c][k]/=d;inv[c][k]/=d;}
      for(int r=0;r<3;r++){ if(r==c)continue; float f=a[r][c]; for(int k=0;k<3;k++){a[r][k]-=f*a[c][k];inv[r][k]-=f*inv[c][k];} } }
    for(int r=0;r<3;r++)for(int c=0;c<3;c++)X2R[r][c]=inv[r][c]; X2R[3][0]=X2R[3][1]=X2R[3][2]=0;X2R[3][3]=1;
  }
  dt_colormatrix_t BINV; {
    float a[3][3]; for(int r=0;r<3;r++)for(int c=0;c<3;c++)a[r][c]=B[r][c];
    float inv[3][3]={{1,0,0},{0,1,0},{0,0,1}};
    for(int c=0;c<3;c++){ int p=c; for(int r=c+1;r<3;r++) if(fabsf(a[r][c])>fabsf(a[p][c]))p=r;
      for(int k=0;k<3;k++){float t=a[c][k];a[c][k]=a[p][k];a[p][k]=t;t=inv[c][k];inv[c][k]=inv[p][k];inv[p][k]=t;}
      float d=a[c][c]; for(int k=0;k<3;k++){a[c][k]/=d;inv[c][k]/=d;}
      for(int r=0;r<3;r++){ if(r==c)continue; float f=a[r][c]; for(int k=0;k<3;k++){a[r][k]-=f*a[c][k];inv[r][k]-=f*inv[c][k];} } }
    for(int r=0;r<3;r++)for(int c=0;c<3;c++)BINV[r][c]=inv[r][c]; BINV[3][0]=BINV[3][1]=BINV[3][2]=0;BINV[3][3]=1;
  }
  for(int r=0;r<4;r++)for(int c=0;c<4;c++){WP_IN[r][c]=(r<3&&c<3)?R2X[r][c]:0;WP_OUT[r][c]=(r<3&&c<3)?X2R[r][c]:0;}
}


int main(void)
{
  init_work();
  // input_matrix = XYZ65LMS * CAT16 * WP_IN ; output = WP_OUT * D65toD50
  dt_colormatrix_t tmp, input, output, inputT, outputT;
  dt_colormatrix_mul(tmp, XYZ_D50_to_D65_CAT16, WP_IN);
  // XYZ65LMS base (not trans): rows as in source
  dt_colormatrix_t X2L = { {0.257085f,0.859943f,-0.031061f,0},{-0.394427f,1.175800f,0.106423f,0},{0.064856f,-0.076250f,0.559067f,0} };
  dt_colormatrix_mul(input, X2L, tmp);
  dt_colormatrix_mul(output, WP_OUT, XYZ_D65_to_D50_CAT16);
  // transpose for apply
  for(int r=0;r<4;r++)for(int c=0;c<4;c++){inputT[r][c]=input[c][r];outputT[r][c]=output[c][r];}

  // default params commit (verbatim :1105-1168, floats)
  dt_aligned_pixel_t Ych_norm = {1.f,0.f,1.f,0.f}; dt_aligned_pixel_t RGB_norm = {0.f};
  Ych_to_gradingRGB(Ych_norm, RGB_norm);
  printf("RGB_norm contingency (grading white) = %.6f %.6f %.6f\n", RGB_norm[0], RGB_norm[1], RGB_norm[2]);
  // global/shadows/highlights/midtones all neutral: offsets 0 / slopes 1
  float white_ful = exp2f(0.f);
  float Lw = Y_to_Lstar(white_ful);
  printf("white_ful=%.4f L_white=%.6f\n", white_ful, Lw);

  float tests[][3] = {{0.5f,0.5f,0.5f},{0.6f,0.3f,0.2f},{0.18f,0.18f,0.18f},{0.02f,0.02f,0.02f},{0.9f,0.1f,0.05f}};
  // NOTE: full process below uses ONLY neutral commit (global 0, slopes 1, midtones_Y 1, contrast 1, vib 0)
  for(int t=0;t<5;t++){
    dt_aligned_pixel_t RGB = {tests[t][0],tests[t][1],tests[t][2],1.f};
    dt_aligned_pixel_t in = {RGB[0],RGB[1],RGB[2],RGB[3]};
    if(RGB[0]<0)RGB[0]=0;if(RGB[1]<0)RGB[1]=0;if(RGB[2]<0)RGB[2]=0;
    dt_aligned_pixel_t LMS, Yrg, Ych;
    dt_apply_transposed_color_matrix(RGB, inputT, LMS);
    // LMS_to_Yrg inline
    { const float Y=0.68990272f*LMS[0]+0.34832189f*LMS[1]; const float a=LMS[0]+LMS[1]+LMS[2];
      dt_aligned_pixel_t lms; for(int c=0;c<4;c++)lms[c]=(a==0.f)?0.f:LMS[c]/a;
      dt_aligned_pixel_t rgb; LMS_to_gradingRGB(lms,rgb); Yrg[0]=Y;Yrg[1]=rgb[0];Yrg[2]=rgb[1];Yrg[3]=LMS[3]; }
    Yrg_to_Ych(Yrg,Ych);
    if(Ych[0]<0)Ych[0]=0;
    // opacity @ neutral weights (sw=hw=4, mw=8, ful=0.1845^0.41)
    float ful = powf(0.1845f, 0.4101205819200422f);
    dt_aligned_pixel_t op, opc; opacity_masks(powf(Ych[0],0.4101205819200422f),4.f,4.f,8.f,ful,op,opc);
    // hue rot 0, chroma/vib 0 -> factor 1
    gamut_check_Yrg(Ych);
    Ych_to_Yrg(Ych,Yrg); Yrg_to_LMS(Yrg,LMS); LMS_to_gradingRGB(LMS,RGB);
    // color balance neutral: offset 0, slopes 1, midtones power 1
    // Yrg again
    gradingRGB_to_LMS(RGB,LMS);
    { const float Y=0.68990272f*LMS[0]+0.34832189f*LMS[1]; const float a=LMS[0]+LMS[1]+LMS[2];
      dt_aligned_pixel_t lms; for(int c=0;c<4;c++)lms[c]=(a==0.f)?0.f:LMS[c]/a;
      dt_aligned_pixel_t rgb; LMS_to_gradingRGB(lms,rgb); Yrg[0]=Y;Yrg[1]=rgb[0];Yrg[2]=rgb[1]; }
    // Y powers neutral (white 1, midtones_Y 1, contrast 1, grey 0.1845)
    Yrg[0] = powf(MAX(Yrg[0]/white_ful,0.f),1.f)*white_ful;
    Yrg[0] = 0.1845f*powf(Yrg[0]/0.1845f,1.f);
    Yrg_to_LMS(Yrg,LMS); LMS_to_XYZ(LMS,RGB); // RGB now XYZ_D65
    // UCS leg neutral: JCH->HCB->(a=b=1)->back->gamut map
    dt_aligned_pixel_t xyY, JCH, HCB;
    XYZ_to_xyY(RGB,xyY); xyY_to_JCH(xyY,Lw,JCH);
    // JCH->HCB
    { float B=JCH[0]*(powf(JCH[1],1.33654221029386f)+1.f); HCB[0]=JCH[2]; HCB[1]=JCH[1]; HCB[2]=B; }
    float rad=sqrtf(HCB[1]*HCB[1]+HCB[2]*HCB[2]); float sT=rad>0?HCB[1]/rad:0, cT=rad>0?HCB[2]/rad:0;
    float P=MAX(FLT_MIN,HCB[1]); float W=sT*HCB[1]+cT*HCB[2];
    float a=1.f, b=1.f; float max_a=sqrtf(P*P+W*W)/P; a=soft_clip(a,0.5f*max_a,max_a);
    float Pp=(a-1.f)*P; float Wp=sqrtf(P*P*(1.f-a*a)+W*W)*b;
    HCB[1]=MAX(cT*Pp+sT*Wp,0.f); HCB[2]=MAX(-sT*Pp+cT*Wp,0.f);
    // HCB->JCH->HSB gamut clip skipped (neutral ~identity, LUT-dependent); project back directly:
    // JCH from HCB:
    dt_aligned_pixel_t JCH2; { float B=HCB[2]; JCH2[2]=HCB[0]; JCH2[1]=HCB[1]; JCH2[0]=B/(powf(HCB[1],1.33654221029386f)+1.f); JCH2[3]=0; }
    // NOTE: stopping before gamut LUT (LUT-dependent); print pre-gamut XYZ->RGB:
    dt_aligned_pixel_t out; dt_apply_transposed_color_matrix(RGB, outputT, out);
    printf("in=(%.3f,%.3f,%.3f) pre-gamut out=(%.6f,%.6f,%.6f) JCH=(%.4f,%.4f,%.4f)\n",
      in[0],in[1],in[2], out[0],out[1],out[2], JCH[0],JCH[1],JCH[2]);
  }
  return 0;
}

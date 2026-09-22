// Check the DTUCS gamut LUT + full neutral chain incl. gamut mapping (D65-native).
// LUT built by dt_UCS_22_build_gamut_LUT with input = R2X (D65).
#include <stdio.h>
#include <math.h>
#include <string.h>
#include <float.h>
typedef float dt_aligned_pixel_t[4] __attribute__((aligned(16)));
typedef float dt_colormatrix_t[4][4] __attribute__((aligned(16)));
#define MAX(a,b) ((a)>(b)?(a):(b))
#define MIN(a,b) ((a)<(b)?(a):(b))
#define LUT_ELEM 512
#define M_PI_F 3.14159265358979323846f
#define DT_2PI_F 6.28318530717958647693f
#define DT_UCS_L_STAR_RANGE 2.098883786377f
#define DT_UCS_Y_UPPER_LIMIT 1e8f
static inline float Y_to_Lstar(const float Y){const float h=powf(Y,0.631651345306265f);return DT_UCS_L_STAR_RANGE*h/(h+1.12426773749357f);}
static inline float Lstar_to_Y(const float L){return powf((1.12426773749357f*L/(DT_UCS_L_STAR_RANGE-L)),1.5831518565279648f);}
static inline float Delta_H(const float a,const float b){float d=a-b;d+=(d<-M_PI_F)?DT_2PI_F:0.f;d-=(d>M_PI_F)?DT_2PI_F:0.f;return d;}
static inline void tapply(const dt_aligned_pixel_t in, const dt_colormatrix_t m, dt_aligned_pixel_t out)
{ for(int r=0;r<4;r++) out[r]=m[0][r]*in[0]+m[1][r]*in[1]+m[2][r]*in[2]; }
static inline void cmul(dt_colormatrix_t d, const dt_colormatrix_t a, const dt_colormatrix_t b)
{ for(int k=0;k<3;k++)for(int i=0;i<4;i++){float s=0;for(int j=0;j<3;j++)s+=a[k][j]*b[j][i];d[k][i]=s;} }
static float gamut_LUT[LUT_ELEM];
static void build_lut(dt_colormatrix_t input)
{
  for(int k=0;k<LUT_ELEM;k++)gamut_LUT[k]=0.f;
  static float sampler[LUT_ELEM]; for(int k=0;k<LUT_ELEM;k++)sampler[k]=0.f;
  dt_aligned_pixel_t XYZr,XYZg,XYZb,xyR,xyG,xyB;
  dt_aligned_pixel_t R={1,0,0,0},G={0,1,0,0},B={0,0,1,0};
  // dot_product(rgb, input, XYZ): XYZ[c] = sum rgb[r]*input[r][c]
  for(int c=0;c<3;c++){XYZr[c]=R[0]*input[0][c]+R[1]*input[1][c]+R[2]*input[2][c];XYZg[c]=G[0]*input[0][c]+G[1]*input[1][c]+G[2]*input[2][c];XYZb[c]=B[0]*input[0][c]+B[1]*input[1][c]+B[2]*input[2][c];}
  // dt_D65_XYZ_to_xyY with fmax(0)
  #define TOXYY(X, O) do{float X0=(X)[0]>0?(X)[0]:0,X1=(X)[1]>0?(X)[1]:0,X2=(X)[2]>0?(X)[2]:0;float s=X0+X1+X2;\
    (O)[0]=s>0?X0/s:0.31271f;(O)[1]=s>0?X1/s:0.32902f;(O)[2]=X1;}while(0)
  TOXYY(XYZr,xyR);TOXYY(XYZg,xyG);TOXYY(XYZb,xyB);
  const float hR=atan2f(xyR[1]-0.32902f,xyR[0]-0.31271f),hG=atan2f(xyG[1]-0.32902f,xyG[0]-0.31271f),hB=atan2f(xyB[1]-0.32902f,xyB[0]-0.31271f);
  for(int i=0;i<50*LUT_ELEM;i++){
    const float ang=-M_PI_F+(float)i/(float)(50*LUT_ELEM)*DT_2PI_F; const float ta=tanf(ang);
    const float t1=Delta_H(ang,hB)/Delta_H(hR,hB), t2=Delta_H(ang,hR)/Delta_H(hG,hR), t3=Delta_H(ang,hG)/Delta_H(hB,hG);
    float xt=0,yt=0;
    if(t1==(t1<0?0:t1>1?1:t1)){const float t=(0.32902f-xyB[1]+ta*(xyB[0]-0.31271f))/(xyR[1]-xyB[1]+ta*(xyB[0]-xyR[0]));xt=xyB[0]+t*(xyR[0]-xyB[0]);yt=xyB[1]+t*(xyR[1]-xyB[1]);}
    else if(t2==(t2<0?0:t2>1?1:t2)){const float t=(0.32902f-xyR[1]+ta*(xyR[0]-0.31271f))/(xyG[1]-xyR[1]+ta*(xyR[0]-xyG[0]));xt=xyR[0]+t*(xyG[0]-xyR[0]);yt=xyR[1]+t*(xyG[1]-xyR[1]);}
    else if(t3==(t3<0?0:t3>1?1:t3)){const float t=(0.32902f-xyG[1]+ta*(xyG[0]-0.31271f))/(xyB[1]-xyG[1]+ta*(xyG[0]-xyB[0]));xt=xyG[0]+t*(xyB[0]-xyG[0]);yt=xyG[1]+t*(xyB[1]-xyG[1]);}
    dt_aligned_pixel_t xyY={xt,yt,1.f,0.f};
    // xyY_to_dt_UCS_UV
    const float xf[3]={-0.783941002840055f,0.745273540913283f,0.318707282433486f};
    const float yf[3]={0.277512987809202f,-0.205375866083878f,2.16743692732158f};
    const float off[3]={0.153836578598858f,-0.165478376301988f,0.291320554395942f};
    float uvd[3];for(int c=0;c<3;c++)uvd[c]=xf[c]*xyY[0]+yf[c]*xyY[1]+off[c];
    const float div=(uvd[2]>=0.f)?MAX(FLT_MIN,uvd[2]):-FLT_MIN;uvd[0]/=div;uvd[1]/=div;
    const float us0=1.39656225667f*uvd[0]/(fabsf(uvd[0])+1.49217352929f);
    const float us1=1.4513954287f*uvd[1]/(fabsf(uvd[1])+1.52488637914f);
    const float p0=-1.124983854323892f*us0-0.980483721769325f*us1, p1=1.86323315098672f*us0+1.971853092390862f*us1;
    const float hue=atan2f(p1,p0);
    int idx=(int)roundf((float)(LUT_ELEM-1)*(hue+M_PI_F)/DT_2PI_F); idx+=(idx<0)?LUT_ELEM:0; idx-=(idx>=LUT_ELEM)?LUT_ELEM:0;
    gamut_LUT[idx]+=p0*p0+p1*p1; sampler[idx]+=1.f;
  }
  for(int k=0;k<LUT_ELEM;k++)gamut_LUT[k]/=MAX(1.f,sampler[k]);
}
static inline float lookup_g(const float h){const float xt=(float)LUT_ELEM*(h+M_PI_F)/DT_2PI_F;const float xp=floorf(xt),xn=ceilf(xt);
  const int xi=((int)xp)&(LUT_ELEM-1),xii=((int)xn)&(LUT_ELEM-1);const float yp=gamut_LUT[xi];return yp+((xi!=xii)?(xt-xp)*(gamut_LUT[xii]-yp):0.f);}
static inline float sclip(const float x,const float s,const float h){const float n=h-s;return(x>s)?s+(1.f-expf(-(x-s)/n))*n:x;}
int main(void)
{
  dt_colormatrix_t R2X = { {0.636958f,0.144617f,0.168881f,0},{0.262700f,0.678009f,0.059291f,0},{0.f,0.028073f,1.060806f,0} };
  build_lut(R2X);
  float mn=gamut_LUT[0],mx=gamut_LUT[0];
  for(int k=0;k<LUT_ELEM;k++){if(gamut_LUT[k]<mn)mn=gamut_LUT[k];if(gamut_LUT[k]>mx)mx=gamut_LUT[k];}
  printf("UCS LUT (D65 Rec2020): min=%.6f max=%.6f\n",mn,mx);
  printf("L_white(white_ful=1) = %.6f\n", Y_to_Lstar(1.f));
  return 0;
}

// FINAL verification: dt-exact chain with D65-native matrices vs my Python reference.
// input = X2L * R2X (no CAT/Bradford); output = X2R * L2X.
#include <stdio.h>
#include <math.h>
#include <string.h>
#include <float.h>
typedef float dt_aligned_pixel_t[4] __attribute__((aligned(16)));
typedef float dt_colormatrix_t[4][4] __attribute__((aligned(16)));
#define MAX(a,b) ((a)>(b)?(a):(b))
#define MIN(a,b) ((a)<(b)?(a):(b))
static inline void tapply(const dt_aligned_pixel_t in, const dt_colormatrix_t m, dt_aligned_pixel_t out)
{ for(int r=0;r<4;r++) out[r]=m[0][r]*in[0]+m[1][r]*in[1]+m[2][r]*in[2]; }
static inline void cmul(dt_colormatrix_t d, const dt_colormatrix_t a, const dt_colormatrix_t b)
{ for(int k=0;k<3;k++)for(int i=0;i<4;i++){float s=0;for(int j=0;j<3;j++)s+=a[k][j]*b[j][i];d[k][i]=s;} }
static const dt_colormatrix_t X2L = { { 0.257085f, 0.859943f, -0.031061f, 0.f }, { -0.394427f, 1.175800f, 0.106423f, 0.f }, { 0.064856f, -0.076250f, 0.559067f, 0.f } };
static const dt_colormatrix_t film_trans = { { 0.95f, 0.05f, 0.00f, 0.f }, { 0.38f, 0.62f, 0.00f, 0.f }, { 0.00f, 0.03f, 0.97f, 0.f } };
static const dt_colormatrix_t lms_trans = { { 1.08771930f, -0.0877193f, 0.f, 0.f }, { -0.66666667f, 1.66666667f, 0.f, 0.f }, { 0.02061856f, -0.05154639f, 1.03092784f, 0.f } };
static const dt_colormatrix_t L2Xtrans = { { 1.80794659f, 0.61783960f, -0.12546960f, 0.f }, { -1.29971660f, 0.39595453f, 0.20478038f, 0.f }, { 0.34785879f, -0.04104687f, 1.74274183f, 0.f } };
static inline float fhyp(float a,float b){return sqrtf(a*a+b*b);}
int main(void)
{
  dt_colormatrix_t R2X = { {0.636958f,0.144617f,0.168881f,0},{0.262700f,0.678009f,0.059291f,0},{0.f,0.028073f,1.060806f,0} };
  dt_colormatrix_t X2R; { float a[3][3],inv[3][3]; for(int r=0;r<3;r++)for(int c=0;c<3;c++){a[r][c]=R2X[r][c];inv[r][c]=(r==c);}
    for(int c=0;c<3;c++){int p=c;for(int r=c+1;r<3;r++)if(fabsf(a[r][c])>fabsf(a[p][c]))p=r;
      for(int k=0;k<3;k++){float t=a[c][k];a[c][k]=a[p][k];a[p][k]=t;t=inv[c][k];inv[c][k]=inv[p][k];inv[p][k]=t;}
      float d=a[c][c];for(int k=0;k<3;k++){a[c][k]/=d;inv[c][k]/=d;}
      for(int r=0;r<3;r++){if(r==c)continue;float f=a[r][c];for(int k=0;k<3;k++){a[r][k]-=f*a[c][k];inv[r][k]-=f*inv[c][k];}}}
    for(int r=0;r<3;r++)for(int c=0;c<3;c++)X2R[r][c]=inv[r][c]; }
  for(int r=0;r<4;r++)for(int c=0;c<4;c++){ if(r>=3||c>=3){X2R[r][c]=(r==c);} }
  dt_colormatrix_t inM,outM,inT,outT;
  cmul(inM,X2L,R2X); cmul(outM,X2R,L2Xtrans);
  // NOTE: outM = X2R * L2Xtrans is garbage by itself (L2Xtrans is _trans storage!); proper:
  // LMS_to_XYZ = tapply(LMS, L2Xtrans) [apply_transposed semantics]. inM for tapply must be _trans storage too.
  // inM computed by cmul is BASE form. For tapply need transpose. Redo:
  dt_colormatrix_t inTT, outTT;
  for(int r=0;r<4;r++)for(int c=0;c<4;c++){inTT[r][c]=inM[c][r];}
  // out: XYZ->RGB is tapply(XYZ, outTransStorage) where outTransStorage = transpose(X2R):
  dt_colormatrix_t X2RT; for(int r=0;r<4;r++)for(int c=0;c<4;c++)X2RT[r][c]=X2R[c][r];
  float tests[][3] = {{0.5f,0.5f,0.5f},{0.6f,0.3f,0.2f},{0.18f,0.18f,0.18f}};
  for(int t=0;t<3;t++){
    dt_aligned_pixel_t RGB={tests[t][0],tests[t][1],tests[t][2],1.f};
    dt_aligned_pixel_t LMS,Yrg,Ych;
    tapply(RGB,inTT,LMS);
    { const float Y=0.68990272f*LMS[0]+0.34832189f*LMS[1]; const float a=LMS[0]+LMS[1]+LMS[2];
      dt_aligned_pixel_t lms; for(int c=0;c<4;c++)lms[c]=(a==0.f)?0.f:LMS[c]/a;
      dt_aligned_pixel_t rgb; tapply(lms,lms_trans,rgb); Yrg[0]=Y;Yrg[1]=rgb[0];Yrg[2]=rgb[1];Yrg[3]=LMS[3]; }
    { const float r=Yrg[1]-0.21902143f; const float g=Yrg[2]-0.54371398f; const float c=fhyp(g,r);
      Ych[0]=Yrg[0];Ych[1]=c;Ych[2]=c!=0.f?r/c:1.f;Ych[3]=c!=0.f?g/c:0.f; }
    if(Ych[0]<0)Ych[0]=0;
    // gamut check
    { dt_aligned_pixel_t Yr; Yr[0]=Ych[0];Yr[1]=Ych[1]*Ych[2]+0.21902143f;Yr[2]=Ych[1]*Ych[3]+0.54371398f;Yr[3]=0;
      float mc=Ych[1];
      if(Yr[1]<0.f)mc=fminf(-0.21902143f/Ych[2],mc); if(Yr[2]<0.f)mc=fminf(-0.54371398f/Ych[3],mc);
      if(Yr[1]+Yr[2]>1.f)mc=fminf((1.f-0.21902143f-0.54371398f)/(Ych[2]+Ych[3]),mc); Ych[1]=mc; }
    // back
    dt_aligned_pixel_t Yrg2,LMS2,RGB2;
    { Yrg2[0]=Ych[0];Yrg2[1]=Ych[1]*Ych[2]+0.21902143f;Yrg2[2]=Ych[1]*Ych[3]+0.54371398f;Yrg2[3]=0;
      const float Y=Yrg2[0],r=Yrg2[1],g=Yrg2[2],b=1.f-r-g;
      const dt_aligned_pixel_t rgb={r,g,b,0.f}; dt_aligned_pixel_t lms; tapply(rgb,film_trans,lms);
      const float denom=0.68990272f*lms[0]+0.34832189f*lms[1]; const float a=(denom==0.f)?0.f:Y/denom;
      for(int c=0;c<4;c++)LMS2[c]=lms[c]*a; }
    tapply(LMS2,lms_trans,RGB2);
    // neutral: same. backward Y:
    dt_aligned_pixel_t LMS4,Yrg4;
    tapply(RGB2,film_trans,LMS4);
    { const float Y=0.68990272f*LMS4[0]+0.34832189f*LMS4[1]; const float a=LMS4[0]+LMS4[1]+LMS4[2];
      dt_aligned_pixel_t lms; for(int c=0;c<4;c++)lms[c]=(a==0.f)?0.f:LMS4[c]/a;
      dt_aligned_pixel_t rgb; tapply(lms,lms_trans,rgb); Yrg4[0]=Y;Yrg4[1]=rgb[0];Yrg4[2]=rgb[1];Yrg4[3]=0; }
    // powers neutral. Yrg->LMS->XYZ:
    dt_aligned_pixel_t LMS5,XYZ,out;
    { const float Y=Yrg4[0],r=Yrg4[1],g=Yrg4[2],b=1.f-r-g;
      const dt_aligned_pixel_t rgb={r,g,b,0.f}; dt_aligned_pixel_t lms; tapply(rgb,film_trans,lms);
      const float denom=0.68990272f*lms[0]+0.34832189f*lms[1]; const float a=(denom==0.f)?0.f:Y/denom;
      for(int c=0;c<4;c++)LMS5[c]=lms[c]*a; }
    tapply(LMS5,L2Xtrans,XYZ);
    tapply(XYZ,X2RT,out);
    printf("in=(%.2f,%.2f,%.2f) FINAL out=(%.6f,%.6f,%.6f)\n",tests[t][0],tests[t][1],tests[t][2],out[0],out[1],out[2]);
  }
  return 0;
}

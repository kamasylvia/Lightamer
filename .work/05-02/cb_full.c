// FULL dt neutral chain with REAL commit + REAL output matrix + NO gamut LUT tricks.
// Answers: what SHOULD the final output be for neutral gray at default params?
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
static const dt_colormatrix_t CAT = { { 9.89466254e-01f, -4.00304626e-02f, 4.40530317e-02f, 0.f }, { -5.40518733e-03f, 1.00666069e+00f, -1.75551955e-03f, 0.f }, { -4.03920992e-04f, 1.50768030e-02f, 1.30210211e+00f, 0.f } };
static const dt_colormatrix_t CATinv = { { 1.01085433e+00f, 4.07086103e-02f, -3.41445825e-02f, 0.f }, { 5.42814201e-03f, 9.93581926e-01f, 1.15592039e-03f, 0.f }, { 2.50722468e-04f, -1.14918759e-02f, 7.67964947e-01f, 0.f } };
static const dt_colormatrix_t X2L = { { 0.257085f, 0.859943f, -0.031061f, 0.f }, { -0.394427f, 1.175800f, 0.106423f, 0.f }, { 0.064856f, -0.076250f, 0.559067f, 0.f } };
static const dt_colormatrix_t film_trans = { { 0.95f, 0.05f, 0.00f, 0.f }, { 0.38f, 0.62f, 0.00f, 0.f }, { 0.00f, 0.03f, 0.97f, 0.f } };
static const dt_colormatrix_t lms_trans = { { 1.08771930f, -0.0877193f, 0.f, 0.f }, { -0.66666667f, 1.66666667f, 0.f, 0.f }, { 0.02061856f, -0.05154639f, 1.03092784f, 0.f } };
static const dt_colormatrix_t L2Xtrans = { { 1.80794659f, 0.61783960f, -0.12546960f, 0.f }, { -1.29971660f, 0.39595453f, 0.20478038f, 0.f }, { 0.34785879f, -0.04104687f, 1.74274183f, 0.f } };
int main(void)
{
  dt_colormatrix_t R2X = { {0.636958f,0.144617f,0.168881f,0},{0.262700f,0.678009f,0.059291f,0},{0.f,0.028073f,1.060806f,0} };
  dt_colormatrix_t B = { {1.0478112f,0.0228866f,-0.0501270f,0},{0.0295424f,0.9904844f,-0.0170491f,0},{-0.0092345f,0.0150436f,0.7521316f,0} };
  // invert B and R2X
  dt_colormatrix_t BINV, X2R;
  { float a[3][3],inv[3][3]; for(int r=0;r<3;r++)for(int c=0;c<3;c++){a[r][c]=B[r][c];inv[r][c]=(r==c);}
    for(int c=0;c<3;c++){int p=c;for(int r=c+1;r<3;r++)if(fabsf(a[r][c])>fabsf(a[p][c]))p=r;
      for(int k=0;k<3;k++){float t=a[c][k];a[c][k]=a[p][k];a[p][k]=t;t=inv[c][k];inv[c][k]=inv[p][k];inv[p][k]=t;}
      float d=a[c][c];for(int k=0;k<3;k++){a[c][k]/=d;inv[c][k]/=d;}
      for(int r=0;r<3;r++){if(r==c)continue;float f=a[r][c];for(int k=0;k<3;k++){a[r][k]-=f*a[c][k];inv[r][k]-=f*inv[c][k];}}}
    for(int r=0;r<3;r++)for(int c=0;c<3;c++)BINV[r][c]=inv[r][c]; }
  { float a[3][3],inv[3][3]; for(int r=0;r<3;r++)for(int c=0;c<3;c++){a[r][c]=R2X[r][c];inv[r][c]=(r==c);}
    for(int c=0;c<3;c++){int p=c;for(int r=c+1;r<3;r++)if(fabsf(a[r][c])>fabsf(a[p][c]))p=r;
      for(int k=0;k<3;k++){float t=a[c][k];a[c][k]=a[p][k];a[p][k]=t;t=inv[c][k];inv[c][k]=inv[p][k];inv[p][k]=t;}
      float d=a[c][c];for(int k=0;k<3;k++){a[c][k]/=d;inv[c][k]/=d;}
      for(int r=0;r<3;r++){if(r==c)continue;float f=a[r][c];for(int k=0;k<3;k++){a[r][k]-=f*a[c][k];inv[r][k]-=f*inv[c][k];}}}
    for(int r=0;r<3;r++)for(int c=0;c<3;c++)X2R[r][c]=inv[r][c]; }
  for(int r=0;r<4;r++)for(int c=0;c<4;c++){ if(r>=3||c>=3){BINV[r][c]=(r==c);X2R[r][c]=(r==c);} }
  dt_colormatrix_t tmp,inM,outM,inT,outT;
  cmul(tmp,CAT,R2X); // NOTE: dt uses CAT * WP_IN where WP_IN = D50 matrix. We use D65 R2X: approximation under test
  cmul(inM,X2L,tmp);
  cmul(outM,X2R,CATinv);
  for(int r=0;r<4;r++)for(int c=0;c<4;c++){inT[r][c]=inM[c][r];outT[r][c]=outM[c][r];}
  // forward gray 0.5
  dt_aligned_pixel_t pix={0.5f,0.5f,0.5f,1.f}, LMS,Yrg,Ych;
  tapply(pix,inT,LMS);
  printf("forward LMS = %.6f %.6f %.6f\n",LMS[0],LMS[1],LMS[2]);
  // forward with PROPER D50 profile for comparison: tmp2 = B*R2X (D50), inM2 = X2L*(CAT*tmp2)
  dt_colormatrix_t d50,tmp2,inM2,inT2;
  cmul(d50,B,R2X); cmul(tmp2,CAT,d50); cmul(inM2,X2L,tmp2);
  for(int r=0;r<4;r++)for(int c=0;c<4;c++)inT2[r][c]=inM2[c][r];
  dt_aligned_pixel_t LMSb; tapply(pix,inT2,LMSb);
  printf("forward LMS (via D50 CAT round trip) = %.6f %.6f %.6f\n",LMSb[0],LMSb[1],LMSb[2]);
  // backward from grading 0.5 (as traced): XYZ=(0.916,0.53,0.833). Project with outT:
  dt_aligned_pixel_t XYZ={0.916095f,0.529540f,0.833466f,0.f}, out;
  tapply(XYZ,outT,out);
  printf("out via X2R*CATinv = %.6f %.6f %.6f\n",out[0],out[1],out[2]);
  // What SHOULD the round trip be? outM*inM should be ~I if consistent:
  dt_colormatrix_t rt; cmul(rt,outM,inM);
  printf("outM*inM row0 = %.4f %.4f %.4f\n",rt[0][0],rt[0][1],rt[0][2]);
  printf("outM*inM row1 = %.4f %.4f %.4f\n",rt[1][0],rt[1][1],rt[1][2]);
  printf("outM*inM row2 = %.4f %.4f %.4f\n",rt[2][0],rt[2][1],rt[2][2]);
  return 0;
}

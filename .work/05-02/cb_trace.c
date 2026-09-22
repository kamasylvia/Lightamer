// Trace dt's REAL backward leg step by step for neutral gray.
#include <stdio.h>
#include <math.h>
#include <string.h>
#include <float.h>
typedef float dt_aligned_pixel_t[4] __attribute__((aligned(16)));
typedef float dt_colormatrix_t[4][4] __attribute__((aligned(16)));
#define MAX(a,b) ((a)>(b)?(a):(b))
static inline void tapply(const dt_aligned_pixel_t in, const dt_colormatrix_t m, dt_aligned_pixel_t out)
{ for(int r=0;r<4;r++) out[r]=m[0][r]*in[0]+m[1][r]*in[1]+m[2][r]*in[2]; }
static const dt_colormatrix_t film_trans = { { 0.95f, 0.05f, 0.00f, 0.f }, { 0.38f, 0.62f, 0.00f, 0.f }, { 0.00f, 0.03f, 0.97f, 0.f } };
static const dt_colormatrix_t lms_trans = { { 1.08771930f, -0.0877193f, 0.f, 0.f }, { -0.66666667f, 1.66666667f, 0.f, 0.f }, { 0.02061856f, -0.05154639f, 1.03092784f, 0.f } };
static const dt_colormatrix_t L2Xtrans = { { 1.80794659f, 0.61783960f, -0.12546960f, 0.f }, { -1.29971660f, 0.39595453f, 0.20478038f, 0.f }, { 0.34785879f, -0.04104687f, 1.74274183f, 0.f } };
int main(void)
{
  dt_aligned_pixel_t RGB = {0.5f,0.5f,0.5f,1.f}; // grading-domain neutral (post color-balance)
  dt_aligned_pixel_t LMS, Yrg;
  tapply(RGB, film_trans, LMS);
  printf("LMS = %.6f %.6f %.6f\n", LMS[0],LMS[1],LMS[2]);
  { const float Y=0.68990272f*LMS[0]+0.34832189f*LMS[1]; const float a=LMS[0]+LMS[1]+LMS[2];
    dt_aligned_pixel_t lms; for(int c=0;c<4;c++)lms[c]=(a==0.f)?0.f:LMS[c]/a;
    dt_aligned_pixel_t rgb; tapply(lms, lms_trans, rgb);
    Yrg[0]=Y;Yrg[1]=rgb[0];Yrg[2]=rgb[1]; }
  printf("Yrg = %.6f %.6f %.6f\n", Yrg[0],Yrg[1],Yrg[2]);
  // powers neutral -> same. Yrg_to_LMS:
  dt_aligned_pixel_t LMS2;
  { const float Y=Yrg[0]; const float r=Yrg[1],g=Yrg[2],b=1.f-r-g;
    const dt_aligned_pixel_t rgb={r,g,b,0.f}; dt_aligned_pixel_t lms; tapply(rgb, film_trans, lms);
    const float denom=0.68990272f*lms[0]+0.34832189f*lms[1]; const float a=(denom==0.f)?0.f:Y/denom;
    for(int c=0;c<4;c++)LMS2[c]=lms[c]*a; }
  printf("LMS2 = %.6f %.6f %.6f\n", LMS2[0],LMS2[1],LMS2[2]);
  dt_aligned_pixel_t XYZ; tapply(LMS2, L2Xtrans, XYZ);
  printf("XYZ = %.6f %.6f %.6f\n", XYZ[0],XYZ[1],XYZ[2]);
  return 0;
}

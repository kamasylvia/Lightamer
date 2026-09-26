// Is LAB_R2X D65 or D50? Invert: X2R * white should give D50 (0.9642,1,0.8249) or D65 (0.95,1,1.089)?
#include <stdio.h>
#include <math.h>
int main(void)
{
  float R2X[3][3] = {{0.636958f,0.144617f,0.168881f},{0.262700f,0.678009f,0.059291f},{0.f,0.028073f,1.060806f}};
  // white = R2X * (1,1,1)
  float w[3] = {R2X[0][0]+R2X[0][1]+R2X[0][2], R2X[1][0]+R2X[1][1]+R2X[1][2], R2X[2][0]+R2X[2][1]+R2X[2][2]};
  printf("R2X white = %.6f %.6f %.6f\n", w[0],w[1],w[2]);
  printf("D50 white = 0.9642 1.0000 0.8249 | D65 white = 0.9505 1.0000 1.0890\n");
  return 0;
}

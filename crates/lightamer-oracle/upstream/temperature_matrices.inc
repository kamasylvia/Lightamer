static void dt_colorspaces_pseudoinverse(double (*in)[3],
                                         double (*out)[3],
                                         const int size)
{
  double work[3][6];

  for(int i = 0; i < 3; i++) {
    for(int j = 0; j < 6; j++)
      work[i][j] = j == i+3;
    for(int j = 0; j < 3; j++)
      for(int k = 0; k < size; k++)
        work[i][j] += in[k][i] * in[k][j];
  }
  for(int i = 0; i < 3; i++) {
    double num = work[i][i];
    for(int j = 0; j < 6; j++)
      work[i][j] /= num;
    for(int k = 0; k < 3; k++) {
      if(k==i) continue;
      num = work[k][i];
      for(int j = 0; j < 6; j++)
        work[k][j] -= work[i][j] * num;
    }
  }
  for(int i = 0; i < size; i++)
    for(int j = 0; j < 3; j++)
    {
      out[i][j] = 0.0f;
      for(int k = 0; k < 3; k++)
        out[i][j] += work[j][k+3] * in[i][k];
    }
}

gboolean dt_colorspaces_conversion_matrices_xyz(const float adobe_XYZ_to_CAM[4][3],
                                                float in_XYZ_to_CAM[9],
                                                double XYZ_to_CAM[4][3],
                                                double CAM_to_XYZ[3][4])
{
  if(dt_is_valid_colormatrix(in_XYZ_to_CAM[0]))
  {
    for(int i = 0; i < 9; i++)
        XYZ_to_CAM[i/3][i%3] = (double) in_XYZ_to_CAM[i];
    for(int i = 0; i < 3; i++)
      XYZ_to_CAM[3][i] = 0.0f;
  }
  else
  {
    if(!dt_is_valid_colormatrix(adobe_XYZ_to_CAM[0][0]))
      return FALSE;

    for(int i = 0; i < 4; i++)
      for(int j = 0; j < 3; j++)
        XYZ_to_CAM[i][j] = (double)adobe_XYZ_to_CAM[i][j];
  }

  // Invert the matrix
  double inverse[4][3];
  dt_colorspaces_pseudoinverse (XYZ_to_CAM, inverse, 4);
  for(int i = 0; i < 3; i++)
    for(int j = 0; j < 4; j++)
      CAM_to_XYZ[i][j] = inverse[j][i];

  return TRUE;
}

// Converted from dcraw's cam_xyz_coeff()
gboolean dt_colorspaces_conversion_matrices_rgb(const float adobe_XYZ_to_CAM[4][3],
                                                double out_RGB_to_CAM[4][3],
                                                double out_CAM_to_RGB[3][4],
                                                const float *embedded_matrix,
                                                double mul[4])
{
  double RGB_to_CAM[4][3];

  float XYZ_to_CAM[4][3];
  dt_mark_colormatrix_invalid(&XYZ_to_CAM[0][0]);

  if(embedded_matrix == NULL || !dt_is_valid_colormatrix(embedded_matrix[0]))
  {
    for(int k=0; k<4; k++)
      for(int i=0; i<3; i++)
        XYZ_to_CAM[k][i] = adobe_XYZ_to_CAM[k][i];
  }
  else
  {
    // keep in sync with reload_defaults from colorin.c
    // embedded matrix is used with higher priority than standard one
    XYZ_to_CAM[0][0] = embedded_matrix[0];
    XYZ_to_CAM[0][1] = embedded_matrix[1];
    XYZ_to_CAM[0][2] = embedded_matrix[2];

    XYZ_to_CAM[1][0] = embedded_matrix[3];
    XYZ_to_CAM[1][1] = embedded_matrix[4];
    XYZ_to_CAM[1][2] = embedded_matrix[5];

    XYZ_to_CAM[2][0] = embedded_matrix[6];
    XYZ_to_CAM[2][1] = embedded_matrix[7];
    XYZ_to_CAM[2][2] = embedded_matrix[8];
  }

  if(!dt_is_valid_colormatrix(XYZ_to_CAM[0][0]))
    return FALSE;

  static const double RGB_to_XYZ[3][3] = {
  // sRGB D65
    { 0.412453, 0.357580, 0.180423 },
    { 0.212671, 0.715160, 0.072169 },
    { 0.019334, 0.119193, 0.950227 },
  };

  // Multiply RGB matrix
  for(int i = 0; i < 4; i++)
    for(int j = 0; j < 3; j++)
    {
      RGB_to_CAM[i][j] = 0.0;
      for(int k = 0; k < 3; k++)
        RGB_to_CAM[i][j] += XYZ_to_CAM[i][k] * RGB_to_XYZ[k][j];
    }

  // Normalize cam_rgb so that cam_rgb * (1,1,1) is (1,1,1,1)
  for(int i = 0; i < 4; i++) {
    double num = 0.0;
    for(int j = 0; j < 3; j++)
      num += RGB_to_CAM[i][j];
    for(int j = 0; j < 3; j++)
       RGB_to_CAM[i][j] /= num;
    if(mul) mul[i] = 1.0 / num;
  }

  if(out_RGB_to_CAM)
    for(int i = 0; i < 4; i++)
      for(int j = 0; j < 3; j++)
        out_RGB_to_CAM[i][j] = RGB_to_CAM[i][j];

  if(out_CAM_to_RGB)
  {
    // Invert the matrix
    double inverse[4][3];
    dt_colorspaces_pseudoinverse (RGB_to_CAM, inverse, 4);
    for(int i = 0; i < 3; i++)
      for(int j = 0; j < 4; j++)
        out_CAM_to_RGB[i][j] = inverse[j][i];
  }

  return TRUE;
}

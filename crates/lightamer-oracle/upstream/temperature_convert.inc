static void _XYZ_to_temperature(cmsCIEXYZ XYZ, float *TempK, float *tint)
{
  double maxtemp = DT_IOP_HIGHEST_TEMPERATURE, mintemp = DT_IOP_LOWEST_TEMPERATURE;
  cmsCIEXYZ _xyz;

  for(*TempK = (maxtemp + mintemp) / 2.0;
      (maxtemp - mintemp) > 1.0;
      *TempK = (maxtemp + mintemp) / 2.0)
  {
    _xyz = _temperature_to_XYZ(*TempK);
    if(_xyz.Z / _xyz.X > XYZ.Z / XYZ.X)
      maxtemp = *TempK;
    else
      mintemp = *TempK;
  }

  // TODO: Fix this to move orthogonally to planckian locus
  *tint = (_xyz.Y / _xyz.X) / (XYZ.Y / XYZ.X);


  if(*TempK < DT_IOP_LOWEST_TEMPERATURE) *TempK = DT_IOP_LOWEST_TEMPERATURE;
  if(*TempK > DT_IOP_HIGHEST_TEMPERATURE) *TempK = DT_IOP_HIGHEST_TEMPERATURE;
  if(*tint < DT_IOP_LOWEST_TINT) *tint = DT_IOP_LOWEST_TINT;
  if(*tint > DT_IOP_HIGHEST_TINT) *tint = DT_IOP_HIGHEST_TINT;
}

static void _xyz2mul(dt_iop_module_t *self,
                    cmsCIEXYZ xyz,
                    double mul[4])
{
  dt_iop_temperature_gui_data_t *g = self->gui_data;

  double XYZ[3] = { xyz.X, xyz.Y, xyz.Z };

  double CAM[4];
  for(int k = 0; k < 4; k++)
  {
    CAM[k] = 0.0;
    for(int i = 0; i < 3; i++)
    {
      CAM[k] += g->XYZ_to_CAM[k][i] * XYZ[i];
    }
  }

  for(int k = 0; k < 4; k++) mul[k] = 1.0 / CAM[k];
}

static void _temp2mul(dt_iop_module_t *self,
                     const double TempK,
                     const double tint,
                     double mul[4])
{
  cmsCIEXYZ xyz = _temperature_to_XYZ(TempK);

  xyz.Y /= tint; // TODO: This is baaad!
  /**
   * TODO:
   * problem here is that tint as it is is just a nasty hack modifying Y component
   * and therefore changing RGB coefficients in wrong way,
   * because modifying only Y in that way doesn’t move XYZ point orthogonally
   * to planckian locus. That means it actually changes temperature and thus it lies!
   */

  _xyz2mul(self, xyz, mul);
}

static cmsCIEXYZ _mul2xyz(dt_iop_module_t *self,
                         const dt_iop_temperature_params_t *p)
{
  dt_iop_temperature_gui_data_t *g = self->gui_data;

  double CAM[4];
  _temp_array_from_params(CAM, p);

  for(int k = 0; k < 4; k++)
    CAM[k] = CAM[k] > 0.0f ? 1.0 / CAM[k] : 0.0f;

  double XYZ[3];
  for(int k = 0; k < 3; k++)
  {
    XYZ[k] = 0.0;
    for(int i = 0; i < 4; i++)
    {
      XYZ[k] += g->CAM_to_XYZ[k][i] * CAM[i];
    }
  }

  return (cmsCIEXYZ){ XYZ[0], XYZ[1], XYZ[2] };
}

static void _mul2temp(dt_iop_module_t *self,
                     dt_iop_temperature_params_t *p,
                     float *TempK,
                     float *tint)
{
  _XYZ_to_temperature(_mul2xyz(self, p), TempK, tint);
}

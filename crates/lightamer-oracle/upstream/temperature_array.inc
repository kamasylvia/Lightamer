static inline void _temp_params_from_array(dt_iop_temperature_params_t *p,
                                           const double a[4])
{
  float *coeffs = (float *)p;
  for_four_channels(c)
    coeffs[c] = (float)a[c];
}

static inline void _temp_array_from_params(double a[4],
                                           const dt_iop_temperature_params_t *p)
{
  float *coeffs = (float *)p;
  for_four_channels(c)
   a[c] = coeffs[c];
}

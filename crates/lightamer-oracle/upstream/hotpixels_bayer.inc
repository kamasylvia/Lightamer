static int _process_bayer(const dt_iop_hotpixels_data_t *data,
                          const void *const ivoid,
                          void *const ovoid,
                          const dt_iop_roi_t *const roi_out)
{
  const float threshold = data->threshold;
  const float multiplier = data->multiplier;
  const gboolean markfixed = data->markfixed;
  const int min_neighbours = data->permissive ? 3 : 4;
  const int width = roi_out->width;
  const int widthx2 = width * 2;
  int fixed = 0;

  DT_OMP_FOR(reduction(+ : fixed))
  for(int row = 2; row < roi_out->height - 2; row++)
  {
    const float *in = (float *)ivoid + (size_t)width * row + 2;
    float *out = (float *)ovoid + (size_t)width * row + 2;
    for(int col = 2; col < width - 2; col++, in++, out++)
    {
      float mid = *in * multiplier;
      if(*in > threshold)
      {
        int count = 0;
        float maxin = 0.0;
        float other;
#define TESTONE(OFFSET)                                                                                      \
  other = in[OFFSET];                                                                                        \
  if(mid > other)                                                                                            \
  {                                                                                                          \
    count++;                                                                                                 \
    if(other > maxin) maxin = other;                                                                         \
  }
        TESTONE(-2);
        TESTONE(-widthx2);
        TESTONE(+2);
        TESTONE(+widthx2);
#undef TESTONE
        if(count >= min_neighbours)
        {
          *out = maxin;
          fixed++;
          if(markfixed)
          {
            for(int i = -2; i >= -10 && i >= -col; i -= 2) out[i] = *in;
            for(int i = 2; i <= 10 && i < width - col; i += 2) out[i] = *in;
          }
        }
      }
    }
  }

  return fixed;
}

static int _process_monochrome(const dt_iop_hotpixels_data_t *data,
                              const void *const ivoid,
                              void *const ovoid,
                              const dt_iop_roi_t *const roi_out,
                              const int planes)
{
  const float threshold = data->threshold;
  const float multiplier = data->multiplier;
  const gboolean markfixed = data->markfixed;
  const int min_neighbours = data->permissive ? 3 : 4;
  const int width = roi_out->width;
  int fixed = 0;

  DT_OMP_FOR(reduction(+ : fixed))
  for(int row = 1; row < roi_out->height - 1; row++)
  {
    const float *in = (float *)ivoid + (size_t)planes * (width * row + 1);
    float *out = (float *)ovoid + (size_t)planes * (width * row + 1);
    for(int col = 1; col < width - 1; col++, in += planes, out += planes)
    {
      float mid = *in * multiplier;
      if(*in > threshold)
      {
        int count = 0;
        float maxin = 0.0f;
        float other;
#define TESTONE(OFFSET)                                                                                      \
  other = in[OFFSET];                                                                                        \
  if(mid > other)                                                                                            \
  {                                                                                                          \
    count++;                                                                                                 \
    if(other > maxin) maxin = other;                                                                         \
  }
        TESTONE(-planes);
        TESTONE(-planes*width);
        TESTONE(planes);
        TESTONE(planes*width);
#undef TESTONE
        if(count >= min_neighbours)
        {
          for(int c=0; c < planes; c++)
            out[c] = maxin;
          fixed++;
          if(markfixed)
          {
            for(int i = -1; i >= -10 && i >= -col; i -= 1)
              for(int c = 0; c < planes; c++) out[4*i + c] = *in;
            for(int i = 1; i <= 10 && i < width - col; i++)
              for(int c = 0; c < planes; c++) out[4*i + c] = *in;
          }
        }
      }
    }
  }
  return fixed;
}

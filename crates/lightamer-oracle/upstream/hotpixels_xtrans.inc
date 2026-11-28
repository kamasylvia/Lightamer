static int _process_xtrans(const dt_iop_hotpixels_data_t *data,
                           const void *const ivoid,
                           void *const ovoid,
                           const dt_iop_roi_t *const roi_out,
                           const uint8_t (*const xtrans)[6])
{
  // for each cell of sensor array, pre-calculate, a list of the x/y
  // offsets of the four radially nearest pixels of the same color
  int offsets[6][6][4][2];
  // increasing offsets from pixel to find nearest like-colored pixels
  const int search[20][2] = { { -1, 0 },
                              { 1, 0 },
                              { 0, -1 },
                              { 0, 1 },
                              { -1, -1 },
                              { -1, 1 },
                              { 1, -1 },
                              { 1, 1 },
                              { -2, 0 },
                              { 2, 0 },
                              { 0, -2 },
                              { 0, 2 },
                              { -2, -1 },
                              { -2, 1 },
                              { 2, -1 },
                              { 2, 1 },
                              { -1, -2 },
                              { 1, -2 },
                              { -1, 2 },
                              { 1, 2 } };
  for(int j = 0; j < 6; ++j)
  {
    for(int i = 0; i < 6; ++i)
    {
      const uint8_t c = FCNxtrans(j, i, xtrans);
      for(int s = 0, found = 0; s < 20 && found < 4; ++s)
      {
        if(c == FCNxtrans(j + search[s][1], i + search[s][0], xtrans))
        {
          offsets[j][i][found][0] = search[s][0];
          offsets[j][i][found][1] = search[s][1];
          ++found;
        }
      }
    }
  }

  const float threshold = data->threshold;
  const float multiplier = data->multiplier;
  const gboolean markfixed = data->markfixed;
  const int min_neighbours = data->permissive ? 3 : 4;
  const int width = roi_out->width;
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
        for(int n = 0; n < 4; ++n)
        {
          int xx = offsets[row % 6][col % 6][n][0];
          int yy = offsets[row % 6][col % 6][n][1];
          float other = *(in + xx + yy * (size_t)width);
          if(mid > other)
          {
            count++;
            if(other > maxin) maxin = other;
          }
        }
        // NOTE: it seems that detecting by 2 neighbors would help for extreme cases
        if(count >= min_neighbours)
        {
          *out = maxin;
          fixed++;
          if(markfixed)
          {
            const uint8_t c = FCNxtrans(row, col, xtrans);
            for(int i = -2; i >= -10 && i >= -col; --i)
            {
              if(c == FCNxtrans(row, col+i, xtrans))
              {
                out[i] = *in;
              }
            }
            for(int i = 2; i <= 10 && i < width - col; ++i)
            {
              if(c == FCNxtrans(row, col+i, xtrans))
              {
                out[i] = *in;
              }
            }
          }
        }
      }
    }
  }

  return fixed;
}

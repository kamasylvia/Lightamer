DT_OMP_DECLARE_SIMD(aligned(inp,outp))
static inline void scaled_copy_4wide(float *const outp,
                                     const float *const inp,
                                     const float *const coeffs)
{
  // this needs to be in a separate function to make GCC8 vectorize it
  // at -O2 as well as -O3
  for_four_channels(c, aligned(inp, coeffs, outp))
    outp[c] = inp[c] * coeffs[c];
}

static inline void _publish_chroma(dt_dev_pixelpipe_iop_t *piece)
{
  const dt_iop_temperature_data_t *const d = piece->data;
  dt_iop_module_t *self = piece->module;
  dt_dev_chroma_t *chr = &self->dev->chroma;

  piece->pipe->dsc.temperature.enabled = piece->enabled;
  for_four_channels(k)
  {
    piece->pipe->dsc.temperature.coeffs[k] = d->coeffs[k];
    piece->pipe->dsc.processed_maximum[k] =
      d->coeffs[k] * piece->pipe->dsc.processed_maximum[k];
    chr->wb_coeffs[k] = d->coeffs[k];
  }
  chr->late_correction = (d->preset == DT_IOP_TEMP_D65_LATE);
}

void process(dt_iop_module_t *self,
             dt_dev_pixelpipe_iop_t *piece,
             const void *const ivoid,
             void *const ovoid,
             const dt_iop_roi_t *const roi_in,
             const dt_iop_roi_t *const roi_out)
{
  const uint32_t filters = piece->filters;
  const uint8_t(*const xtrans)[6] = piece->xtrans;
  const dt_iop_temperature_data_t *const d = piece->data;

  const float *const in = (const float *const)ivoid;
  float *const out = (float *const)ovoid;
  const float *const d_coeffs = d->coeffs;
  const int width = roi_out->width;
  const int height = roi_out->height;

  if(filters == 9u)
  { // xtrans float mosaiced
    DT_OMP_FOR()
    for(int j = 0; j < height; j++)
    {
      const float DT_ALIGNED_PIXEL coeffs[3][4] =
      {
        { d_coeffs[FCNxtrans(j, 0, xtrans)],
          d_coeffs[FCNxtrans(j, 1, xtrans)],
          d_coeffs[FCNxtrans(j, 2, xtrans)],
          d_coeffs[FCNxtrans(j, 3, xtrans)] },
        { d_coeffs[FCNxtrans(j, 4, xtrans)],
          d_coeffs[FCNxtrans(j, 5, xtrans)],
          d_coeffs[FCNxtrans(j, 6, xtrans)],
          d_coeffs[FCNxtrans(j, 7, xtrans)] },
        { d_coeffs[FCNxtrans(j, 8, xtrans)],
          d_coeffs[FCNxtrans(j, 9, xtrans)],
          d_coeffs[FCNxtrans(j, 10, xtrans)],
          d_coeffs[FCNxtrans(j, 11, xtrans)] },
      };
      // process sensels four at a time (note that attempting to
      //ensure alignment for this main loop actually slowed things
      //down marginally)
      int i = 0;
      for(int coeff = 0; i + 4 < width; i += 4, coeff = (coeff+1)%3)
      {
        const size_t p = (size_t)j * width + i;
        for_four_channels(c) // in and out are NOT aligned when width is not a multiple of 4
          out[p+c] = in[p+c] * coeffs[coeff][c];
      }
      // process the leftover sensels
      for(; i < width; i++)
      {
        const size_t p = (size_t)j * width + i;
        out[p] = in[p] * d_coeffs[FCNxtrans(j, i, xtrans)];
      }
    }
  }
  else if(filters)
  { // bayer float mosaiced
    DT_OMP_FOR()
    for(int j = 0; j < height; j++)
    {
      int i = 0;

      const int alignment = 3 & (4 - ((j*width) & 3));

      // process the unaligned sensels at the start of the row (when
      // width is not a multiple of 4)
      for(; i < alignment; i++)
      {
        const size_t p = (size_t)j * width + i;
        out[p] = in[p] * d_coeffs[FC(j, i, filters)];
      }
      const dt_aligned_pixel_t coeffs =
        { d_coeffs[FC(j, i, filters)],
          d_coeffs[FC(j, i + 1,filters)],
          d_coeffs[FC(j, i + 2, filters)],
          d_coeffs[FC(j, i + 3, filters)] };

      // process sensels four at a time
      for(; i < width - 4; i += 4)
      {
        const size_t p = (size_t)j * width + i;
        scaled_copy_4wide(out + p,in + p, coeffs);
      }

      // process the leftover sensels
      for(; i < width; i++)
      {
        const size_t p = (size_t)j * width + i;
        out[p] = in[p] * d_coeffs[FC(j, i, filters)];
      }
    }
  }
  else
  { // non-mosaiced
    const size_t npixels = (size_t)height * width;

    DT_OMP_FOR()
    for(size_t k = 0; k < 4*npixels; k += 4)
    {
      for_each_channel(c,aligned(in,out))
      {
        out[k+c] = in[k+c] * d_coeffs[c];
      }
    }
  }

  _publish_chroma(piece);
}

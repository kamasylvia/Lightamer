void process(dt_iop_module_t *self,
             dt_dev_pixelpipe_iop_t *piece,
             const void *const ivoid,
             void *const ovoid,
             const dt_iop_roi_t *const roi_in,
             const dt_iop_roi_t *const roi_out)
{
  const dt_iop_rawprepare_data_t *const d = piece->data;

  const int csx = _compute_proper_crop(piece, roi_in, d->left);
  const int csy = _compute_proper_crop(piece, roi_in, d->top);

  float *const out = (float *const)ovoid;

  if(piece->pipe->dsc.filters && piece->dsc_in.channels == 1
     && piece->dsc_in.datatype == TYPE_UINT16)
  { // raw mosaic

    const uint16_t *const in = (const uint16_t *const)ivoid;

    DT_OMP_FOR_SIMD(collapse(2))
    for(int j = 0; j < roi_out->height; j++)
    {
      for(int i = 0; i < roi_out->width; i++)
      {
        const size_t pin = (size_t)(roi_in->width * (j + csy) + csx) + i;
        const size_t pout = (size_t)j * roi_out->width + i;

        const int id = _BL(roi_out, d, j, i);
        out[pout] = (in[pin] - d->sub[id]) / d->div[id];
      }
    }

    piece->pipe->dsc.filters =
      dt_rawspeed_crop_dcraw_filters(self->dev->image_storage.buf_dsc.filters, csx, csy);
    _adjust_xtrans_filters(piece->pipe, csx, csy);
  }
  else if(piece->pipe->dsc.filters && piece->dsc_in.channels == 1
          && piece->dsc_in.datatype == TYPE_FLOAT)
  { // raw mosaic, fp, unnormalized

    const float *const in = (const float *const)ivoid;

    DT_OMP_FOR_SIMD(collapse(2))
    for(int j = 0; j < roi_out->height; j++)
    {
      for(int i = 0; i < roi_out->width; i++)
      {
        const size_t pin = (size_t)(roi_in->width * (j + csy) + csx) + i;
        const size_t pout = (size_t)j * roi_out->width + i;

        const int id = _BL(roi_out, d, j, i);
        out[pout] = (in[pin] - d->sub[id]) / d->div[id];
      }
    }

    piece->pipe->dsc.filters =
      dt_rawspeed_crop_dcraw_filters(self->dev->image_storage.buf_dsc.filters, csx, csy);
    _adjust_xtrans_filters(piece->pipe, csx, csy);
  }
  else
  { // pre-downsampled buffer that needs black/white scaling

    const float *const in = (const float *const)ivoid;
    const int ch = piece->colors;

    DT_OMP_FOR_SIMD(collapse(3))
    for(int j = 0; j < roi_out->height; j++)
    {
      for(int i = 0; i < roi_out->width; i++)
      {
        for(int c = 0; c < ch; c++)
        {
          const size_t pin = (size_t)ch * (roi_in->width * (j + csy) + csx + i) + c;
          const size_t pout = (size_t)ch * (j * roi_out->width + i) + c;

          out[pout] = (in[pin] - d->sub[c]) / d->div[c];
        }
      }
    }
  }

  if(piece->pipe->dsc.filters && piece->dsc_in.channels == 1 && d->apply_gainmaps)
  {
    const uint32_t map_w = d->gainmaps[0]->map_points_h;
    const uint32_t map_h = d->gainmaps[0]->map_points_v;
    const float im_to_rel_x = 1.0f / piece->buf_in.width;
    const float im_to_rel_y = 1.0f / piece->buf_in.height;
    const float rel_to_map_x = 1.0f / d->gainmaps[0]->map_spacing_h;
    const float rel_to_map_y = 1.0f / d->gainmaps[0]->map_spacing_v;
    const float map_origin_h = d->gainmaps[0]->map_origin_h;
    const float map_origin_v = d->gainmaps[0]->map_origin_v;

    DT_OMP_FOR()
    for(int j = 0; j < roi_out->height; j++)
    {
      const float y_map = CLAMP(((roi_out->y + csy + j) * im_to_rel_y - map_origin_v) * rel_to_map_y, 0, map_h);
      const uint32_t y_i0 = MIN(y_map, map_h - 1);
      const uint32_t y_i1 = MIN(y_i0 + 1, map_h - 1);
      const float y_frac = y_map - y_i0;
      const float * restrict map_row0[4];
      const float * restrict map_row1[4];
      for(int f = 0; f < 4; f++)
      {
        map_row0[f] = &d->gainmaps[f]->map_gain[y_i0 * map_w];
        map_row1[f] = &d->gainmaps[f]->map_gain[y_i1 * map_w];
      }
      for(int i = 0; i < roi_out->width; i++)
      {
        const int id = _BL(roi_out, d, j, i);
        const float x_map = CLAMP(((roi_out->x + csx + i) * im_to_rel_x - map_origin_h) * rel_to_map_x, 0, map_w);
        const uint32_t x_i0 = MIN(x_map, map_w - 1);
        const uint32_t x_i1 = MIN(x_i0 + 1, map_w - 1);
        const float x_frac = x_map - x_i0;
        const float gain_top = (1.0f - x_frac) * map_row0[id][x_i0] + x_frac * map_row0[id][x_i1];
        const float gain_bottom = (1.0f - x_frac) * map_row1[id][x_i0] + x_frac * map_row1[id][x_i1];
        out[j * roi_out->width + i] *= (1.0f - y_frac) * gain_top + y_frac * gain_bottom;
      }
    }
  }

  const gboolean color_sraw = !(dt_image_is_raw(&piece->pipe->image) ||  dt_image_is_mono_sraw(&piece->pipe->image));
  if(color_sraw && piece->pipe->want_detail_mask)
    dt_dev_write_scharr_mask(piece, out, roi_out, FALSE);

  for(int k = 0; k < 4; k++) piece->pipe->dsc.processed_maximum[k] = 1.0f;
}

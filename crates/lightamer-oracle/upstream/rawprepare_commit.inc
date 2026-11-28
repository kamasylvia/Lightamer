void commit_params(dt_iop_module_t *self,
                   dt_iop_params_t *params,
                   dt_dev_pixelpipe_t *pipe,
                   dt_dev_pixelpipe_iop_t *piece)
{
  const dt_iop_rawprepare_params_t *const p = (dt_iop_rawprepare_params_t *)params;
  dt_iop_rawprepare_data_t *d = piece->data;

  d->left = p->left;
  d->top = p->top;
  d->right = p->right;
  d->bottom = p->bottom;

  if(piece->pipe->dsc.filters)
  {
    const float white = (float)p->raw_white_point;

    for(int i = 0; i < 4; i++)
    {
      d->sub[i] = (float)p->raw_black_level_separate[i];
      d->div[i] = (white - d->sub[i]);
    }
  }
  else
  {
    const float normalizer =
      ((piece->pipe->image.flags & DT_IMAGE_HDR) == DT_IMAGE_HDR)
      ? 1.0f
      : (float)UINT16_MAX;

    const float white = (float)p->raw_white_point / normalizer;
    for(int i = 0; i < 4; i++)
    {
      d->sub[i] = (float)p->raw_black_level_separate[i] / normalizer;
      d->div[i] = (white - d->sub[i]);
    }
  }

  float black = 0.0f;
  for(uint8_t i = 0; i < 4; i++)
  {
    black += (float)p->raw_black_level_separate[i];
  }
  d->rawprepare.raw_black_level = (uint16_t)roundf(black / 4.0f);
  d->rawprepare.raw_white_point = p->raw_white_point;

  if(p->flat_field == FLAT_FIELD_EMBEDDED)
    d->apply_gainmaps = _check_gain_maps(self, d->gainmaps);
  else
    d->apply_gainmaps = FALSE;

  if(_image_set_rawcrops(self, pipe->image.id, d->left, d->right, d->top, d->bottom))
    DT_CONTROL_SIGNAL_RAISE(DT_SIGNAL_METADATA_UPDATE);

  if(!(dt_image_is_rawprepare_supported(&piece->pipe->image))
     || _image_is_normalized(&piece->pipe->image))
    piece->enabled = FALSE;

  if(piece->pipe->want_detail_mask)
    piece->process_tiling_ready = FALSE;
}

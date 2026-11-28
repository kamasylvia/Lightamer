void commit_params(dt_iop_module_t *self, dt_iop_params_t *params, dt_dev_pixelpipe_t *pipe,
                   dt_dev_pixelpipe_iop_t *piece)
{
  dt_iop_hotpixels_params_t *p = (dt_iop_hotpixels_params_t *)params;
  dt_iop_hotpixels_data_t *d = piece->data;
  d->filters = piece->pipe->dsc.filters;
  d->multiplier = p->strength / 2.0;
  d->threshold = p->threshold;
  d->permissive = p->permissive;
  d->markfixed = p->markfixed && (!(dt_pipe_is_thumb(pipe) || dt_pipe_is_export(pipe)));

  const dt_image_t *img = &pipe->image;
  const gboolean monoraw = (img->flags & DT_IMAGE_S_RAW) && (img->flags & DT_IMAGE_MONOCHROME);
  const gboolean supported = dt_image_is_raw(img) || monoraw;
  d->monochrome = img->flags & DT_IMAGE_MONOCHROME_BAYER;
  d->pure_monochrome = monoraw;
  if(!supported || p->strength == 0.0) piece->enabled = FALSE;
}

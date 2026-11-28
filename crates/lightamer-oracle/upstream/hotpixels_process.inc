void process(dt_iop_module_t *self, dt_dev_pixelpipe_iop_t *piece, const void *const ivoid,
             void *const ovoid, const dt_iop_roi_t *const roi_in, const dt_iop_roi_t *const roi_out)
{
  dt_iop_hotpixels_gui_data_t *g = self->gui_data;
  const dt_iop_hotpixels_data_t *data = piece->data;

  // The processing loop should output only a few pixels, so just copy everything first
  const int planes = data->pure_monochrome ? 4 : 1;
  dt_iop_image_copy_by_size(ovoid, ivoid, roi_out->width, roi_out->height, planes);

  int fixed = 0;

  if(data->monochrome || data->pure_monochrome)
  {
    fixed = _process_monochrome(data, ivoid, ovoid, roi_out, planes);
  }
  else if(piece->pipe->dsc.filters == 9u)
  {
    fixed = _process_xtrans(data, ivoid, ovoid, roi_out, piece->xtrans);
  }
  else
  {
    fixed = _process_bayer(data, ivoid, ovoid, roi_out);
  }

  if(g && self->dev->gui_attached && dt_pipe_is_full(piece->pipe))
  {
    g->pixels_fixed = fixed;
  }
}

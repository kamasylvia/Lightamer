void dt_dev_prepare_piece_cfa(dt_dev_pixelpipe_iop_t *piece, const dt_iop_roi_t *roi)
{
  dt_iop_module_t *module = piece->module;
  if(module && (module->input_colorspace(module, piece->pipe, piece) == IOP_CS_RAW
              || module->default_colorspace(module, piece->pipe, piece) == IOP_CS_RAW))
  {
    piece->filters = dt_rawspeed_crop_dcraw_filters(piece->pipe->dsc.filters, roi->x, roi->y);
    for(int ii = 0; ii < 6; ++ii)
    {
      for(int jj = 0; jj < 6; ++jj)
      {
        piece->xtrans[jj][ii] = piece->pipe->dsc.xtrans[(jj + roi->y) % 6][(ii + roi->x) % 6];
      }
    }
  }
}

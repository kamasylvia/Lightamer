static void _adjust_xtrans_filters(dt_dev_pixelpipe_t *pipe,
                                   const uint32_t crop_x,
                                   const uint32_t crop_y)
{
  for(int i = 0; i < 6; ++i)
  {
    for(int j = 0; j < 6; ++j)
    {
      pipe->dsc.xtrans[j][i] = pipe->image.buf_dsc.xtrans[(j + crop_y) % 6][(i + crop_x) % 6];
    }
  }
}

static int _BL(const dt_iop_roi_t *const roi_out,
               const dt_iop_rawprepare_data_t *const d,
               const int row,
               const int col)
{
  return ((((row + roi_out->y + d->top) & 1) << 1) + ((col + roi_out->x + d->left) & 1));
}

static int _compute_proper_crop(dt_dev_pixelpipe_iop_t *piece,
                                const dt_iop_roi_t *const roi_in,
                                const int value)
{
  const float scale = roi_in->scale / piece->iscale;
  return (int)roundf((float)value * scale);
}

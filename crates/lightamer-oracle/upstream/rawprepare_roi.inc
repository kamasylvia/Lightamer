// we're not scaling here (bayer input), so just crop borders
void modify_roi_out(dt_iop_module_t *self,
                    dt_dev_pixelpipe_iop_t *piece,
                    dt_iop_roi_t *roi_out,
                    const dt_iop_roi_t *const roi_in)
{
  *roi_out = *roi_in;
  dt_iop_rawprepare_data_t *d = piece->data;

  roi_out->x = roi_out->y = 0;

  const int32_t x = d->left + d->right;
  const int32_t y = d->top + d->bottom;

  const float scale = roi_in->scale / piece->iscale;
  roi_out->width -= (int)roundf((float)x * scale);
  roi_out->height -= (int)roundf((float)y * scale);
}

void modify_roi_in(dt_iop_module_t *self,
                   dt_dev_pixelpipe_iop_t *piece,
                   const dt_iop_roi_t *const roi_out,
                   dt_iop_roi_t *roi_in)
{
  *roi_in = *roi_out;
  dt_iop_rawprepare_data_t *d = piece->data;

  const int32_t x = d->left + d->right;
  const int32_t y = d->top + d->bottom;

  const float scale = roi_in->scale / piece->iscale;
  roi_in->width += (int)roundf((float)x * scale);
  roi_in->height += (int)roundf((float)y * scale);
}

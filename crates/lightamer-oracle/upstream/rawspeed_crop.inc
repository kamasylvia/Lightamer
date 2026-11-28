uint32_t dt_rawspeed_crop_dcraw_filters(const uint32_t filters,
                                        const uint32_t crop_x,
                                        const uint32_t crop_y)
{
  if(!filters || filters == 9u)
    return filters;
  else
    return ColorFilterArray::shiftDcrawFilter(filters, crop_x, crop_y);
}

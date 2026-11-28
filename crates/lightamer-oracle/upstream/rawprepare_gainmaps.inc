// check if image contains GainMaps of the exact type that we can apply here
// we may reject some GainMaps that are valid according to Adobe DNG spec but we do not support
static gboolean _check_gain_maps(dt_iop_module_t *self, dt_dng_gain_map_t **gainmaps_out)
{
  const dt_image_t *const image = &(self->dev->image_storage);
  dt_dng_gain_map_t *gainmaps[4] = {0};

  if(g_list_length(image->dng_gain_maps) != 4)
    return FALSE;

  // FIXME checks for width / height might be wrong
  for(int i = 0; i < 4; i++)
  {
    // check that each GainMap applies to one filter of a Bayer image,
    // covers the entire image, and is not a 1x1 no-op
    dt_dng_gain_map_t *g = g_list_nth_data(image->dng_gain_maps, i);
    if(g == NULL
       || g->plane != 0
       || g->planes != 1
       || g->map_planes != 1
       || g->row_pitch != 2
       || g->col_pitch != 2
       || g->map_points_v < 2
       || g->map_points_h < 2
       || g->top > 1
       || g->left > 1
       || g->bottom != image->height
       || g->right != image->width)
      return FALSE;

    const uint32_t filter = ((g->top & 1) << 1) + (g->left & 1);
    gainmaps[filter] = g;
  }

  // check that there is a GainMap for each filter of the Bayer pattern
  if(gainmaps[0] == NULL || gainmaps[1] == NULL || gainmaps[2] == NULL || gainmaps[3] == NULL)
    return FALSE;

  // check that each GainMap has the same shape
  for(int i = 1; i < 4; i++)
  {
    if(gainmaps[i]->map_points_h != gainmaps[0]->map_points_h
       || gainmaps[i]->map_points_v != gainmaps[0]->map_points_v
       || gainmaps[i]->map_spacing_h != gainmaps[0]->map_spacing_h
       || gainmaps[i]->map_spacing_v != gainmaps[0]->map_spacing_v
       || gainmaps[i]->map_origin_h != gainmaps[0]->map_origin_h
       || gainmaps[i]->map_origin_v != gainmaps[0]->map_origin_v)
      return FALSE;
  }

  if(gainmaps_out)
    memcpy(gainmaps_out, gainmaps, sizeof(gainmaps));

  return TRUE;
}

typedef struct dt_dng_gain_map_t
{
  uint32_t top;
  uint32_t left;
  uint32_t bottom;
  uint32_t right;
  uint32_t plane;
  uint32_t planes;
  uint32_t row_pitch;
  uint32_t col_pitch;
  uint32_t map_points_v;
  uint32_t map_points_h;
  double map_spacing_v;
  double map_spacing_h;
  double map_origin_v;
  double map_origin_h;
  uint32_t map_planes;
  float map_gain[];
} dt_dng_gain_map_t;

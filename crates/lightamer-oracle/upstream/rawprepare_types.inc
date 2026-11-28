typedef enum dt_iop_rawprepare_flat_field_t
{
  FLAT_FIELD_OFF = 0,     // $DESCRIPTION: "disabled"
  FLAT_FIELD_EMBEDDED = 1 // $DESCRIPTION: "embedded GainMap"
} dt_iop_rawprepare_flat_field_t;

typedef struct dt_iop_rawprepare_params_t
{
  int32_t left; // $MIN: 0 $MAX: UINT16_MAX $DESCRIPTION: "crop left"
  int32_t top; // $MIN: 0 $MAX: UINT16_MAX $DESCRIPTION: "crop top"
  int32_t right; // $MIN: 0 $MAX: UINT16_MAX $DESCRIPTION: "crop right"
  int32_t bottom; // $MIN: 0 $MAX: UINT16_MAX $DESCRIPTION: "crop bottom"
  uint16_t raw_black_level_separate[4]; // $MIN: 0 $MAX: UINT16_MAX $DESCRIPTION: "black level"
  uint16_t raw_white_point; // $MIN: 0 $MAX: UINT16_MAX $DESCRIPTION: "white point"
  dt_iop_rawprepare_flat_field_t flat_field; // $DEFAULT: FLAT_FIELD_OFF $DESCRIPTION: "flat field correction"
} dt_iop_rawprepare_params_t;
typedef struct dt_iop_rawprepare_data_t
{
  int32_t left, top, right, bottom;
  float sub[4];
  float div[4];

  // cached for dt_iop_buffer_dsc_t::rawprepare
  struct
  {
    uint16_t raw_black_level;
    uint16_t raw_white_point;
  } rawprepare;

  // image contains GainMaps that should be applied
  gboolean apply_gainmaps;
  // GainMap for each filter of RGGB Bayer pattern
  dt_dng_gain_map_t *gainmaps[4];
} dt_iop_rawprepare_data_t;

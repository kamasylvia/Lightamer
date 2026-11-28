typedef struct dt_iop_hotpixels_params_t
{
  float strength;  // $MIN: 0.0 $MAX: 1.0 $DEFAULT: 0.25
  float threshold; // $MIN: 0.0 $MAX: 1.0 $DEFAULT: 0.05
  gboolean markfixed;  // $DEFAULT: FALSE $DESCRIPTION: "mark fixed pixels"
  gboolean permissive; // $DEFAULT: FALSE $DESCRIPTION: "detect by 3 neighbors"
} dt_iop_hotpixels_params_t;
typedef struct dt_iop_hotpixels_gui_data_t
{
  GtkWidget *threshold, *strength;
  GtkToggleButton *markfixed;
  GtkToggleButton *permissive;
  GtkLabel *message;
  int pixels_fixed;
} dt_iop_hotpixels_gui_data_t;
typedef struct dt_iop_hotpixels_data_t
{
  uint32_t filters;
  float threshold;
  float multiplier;
  gboolean permissive;
  gboolean markfixed;
  gboolean monochrome;
  gboolean pure_monochrome;
} dt_iop_hotpixels_data_t;

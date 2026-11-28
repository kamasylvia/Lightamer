typedef struct dt_iop_temperature_params_t
{
  float red;     // $MIN: 0.0 $MAX: 8.0
  float green;   // $MIN: 0.0 $MAX: 8.0
  float blue;    // $MIN: 0.0 $MAX: 8.0
  float various; // $MIN: 0.0 $MAX: 8.0
  int preset;
} dt_iop_temperature_params_t;
typedef struct dt_iop_temperature_gui_data_t
{
  GtkWidget *scale_k, *scale_tint, *scale_r, *scale_g, *scale_b, *scale_y;
  GtkWidget *presets;
  GtkWidget *finetune;
  GtkWidget *buttonbar;
  GtkWidget *colorpicker;
  GtkWidget *btn_asshot; //As Shot
  GtkWidget *btn_user;
  GtkWidget *btn_d65;
  GtkWidget *btn_d65_late;
  GtkWidget *temp_label;
  GtkWidget *balance_label;
  int preset_cnt;
  int preset_num[54];
  double mod_coeff[4];
  float mod_temp, mod_tint;
  double XYZ_to_CAM[4][3], CAM_to_XYZ[3][4];
  gboolean colored_sliders;
  gboolean blackbody_is_confusing;
  gboolean button_bar_visible;
  dt_gui_collapsible_section_t cs;
} dt_iop_temperature_gui_data_t;
typedef struct dt_iop_temperature_data_t
{
  float coeffs[4];
  int preset;
} dt_iop_temperature_data_t;

// dt_mark_colormatrix_invalid could/should be a function,
// but it was converted to macros due to this GCC compiler bug:
// https://gcc.gnu.org/bugzilla/show_bug.cgi?id=105689
#ifdef NO_COLORMATRIX_NAN
#define dt_mark_colormatrix_invalid(matrix) do{*(matrix) = -FLT_MAX;}while(0)

static inline int dt_is_valid_colormatrix(float matrix)
{
  return matrix != -FLT_MAX;
}
#else

#ifdef __GNUC__
#pragma GCC push_options
#pragma GCC optimize ("-fno-finite-math-only")
#endif

#define dt_mark_colormatrix_invalid(matrix) do{*(matrix) = NAN;}while(0)

static inline int dt_is_valid_colormatrix(float matrix)
{
  return isfinite(matrix);
}

#ifdef __GNUC__
#pragma GCC pop_options
#endif

#endif /* NO_COLORMATRIX_NAN */

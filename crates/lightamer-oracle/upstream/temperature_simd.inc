#define DT_ALIGNED_PIXEL __attribute__((aligned(16)))
#ifdef DT_NO_VECTORIZATION
#define DT_PIXEL_SIMD_CHANNELS 3
#else
#define DT_PIXEL_SIMD_CHANNELS 4
#endif
#if defined(_OPENMP) && defined(OPENMP_SIMD_) && !defined(DT_NO_SIMD_HINTS)
//https://stackoverflow.com/questions/45762357/how-to-concatenate-strings-in-the-arguments-of-pragma
#define _DT_Pragma_(x) _Pragma(#x)
#define _DT_Pragma(x) _DT_Pragma_(x)
#define for_each_channel(_var, ...) \
  _DT_Pragma(omp simd __VA_ARGS__) \
  for (size_t _var = 0; _var < DT_PIXEL_SIMD_CHANNELS; _var++)
#define for_four_channels(_var, ...) \
  _DT_Pragma(omp simd __VA_ARGS__) \
  for (size_t _var = 0; _var < 4; _var++)
#define for_three_channels(_var, ...) \
  _DT_Pragma(omp simd __VA_ARGS__) \
  for (size_t _var = 0; _var < 3; _var++)
#else
#define for_each_channel(_var, ...) \
  for (size_t _var = 0; _var < DT_PIXEL_SIMD_CHANNELS; _var++)
#define for_four_channels(_var, ...) \
  for (size_t _var = 0; _var < 4; _var++)
#define for_three_channels(_var, ...) \
  for (size_t _var = 0; _var < 3; _var++)
#endif

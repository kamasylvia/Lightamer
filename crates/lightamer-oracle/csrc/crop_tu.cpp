// SPDX-License-Identifier: GPL-3.0-or-later
// Glue: minimal rawspeed declaration plus the verbatim shift + wrapper.
// The wrapper matches the prior extern "C" declaration (as in upstream,
// where imageio_rawspeed.h wraps it in G_BEGIN_DECLS), so it keeps C
// linkage and the C translation units link against it.
#include <cstdint>
#include <cstdlib>

namespace rawspeed {
struct ColorFilterArray
{
  // Weak: test binaries also link decode's rawspeed, which defines the same
  // symbol from the same pinned source; the strong definition wins there
  // with no duplicate-symbol complaint, while oracle-only binaries use this
  // one. Same code either way (pure integer bit ops).
  static uint32_t shiftDcrawFilter(uint32_t filter, int x, int y) __attribute__((weak));
};
} // namespace rawspeed

using namespace rawspeed;

namespace rawspeed {
#include "shift_dcraw.inc"
} // namespace rawspeed

extern "C" uint32_t dt_rawspeed_crop_dcraw_filters(uint32_t filters, uint32_t crop_x,
                                                  uint32_t crop_y);
#include "rawspeed_crop.inc"

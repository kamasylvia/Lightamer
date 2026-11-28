uint32_t ColorFilterArray::shiftDcrawFilter(uint32_t filter, int x, int y) {
  // filter is a series of 4 bytes that describe a 2x8 matrix. 2 is the width,
  // 8 is the height. each byte describes a 2x2 pixel block. so each pixel has
  // 2 bits of information. This allows to distinguish 4 different colors.

  if (std::abs(x) & 1) {
    // A shift in x direction means swapping the first and second half of each
    // nibble.
    // see http://graphics.stanford.edu/~seander/bithacks.html#SwappingBitsXOR
    for (int n = 0; n < 8; ++n) {
      int i = n * 4;
      int j = i + 2;
      uint32_t t = ((filter >> i) ^ (filter >> j)) & ((1U << 2) - 1);
      filter = filter ^ ((t << i) | (t << j));
    }
  }

  if (y == 0)
    return filter;

  // A shift in y direction means rotating the whole int by 4 bits.
  y *= 4;
  y = y >= 0 ? y % 32 : 32 - ((-y) % 32);
  if (y != 0)
    filter = (filter >> y) | (filter << (32 - y));

  return filter;
}

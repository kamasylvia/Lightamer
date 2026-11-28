/** Calculate the xtrans pattern color from the row and column **/
static inline int FCNxtrans(const int row, const int col, const uint8_t (*const xtrans)[6])
{
  // Add +600 (which must be a multiple of CFA width 6) as offset can
  // be negative and need to ensure a non-negative array index. The
  // negative offsets in current code come from the demosaic iop:
  // Markesteijn 1-pass (-12), Markesteijn 3-pass (-17), and VNG (-2).
  const int irow = row + 600;
  const int icol = col + 600;
  assert(irow >= 0 && icol >= 0);

  return xtrans[irow % 6][icol % 6];
}

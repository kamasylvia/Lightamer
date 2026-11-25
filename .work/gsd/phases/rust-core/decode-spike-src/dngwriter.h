// dngwriter.h — rawspeed mosaic -> uncompressed CFA DNG (issue #24 P1 seam).
//
// Header-only so the spike's CLI (rs2dng.cpp) and the C ABI shim share ONE
// writer. The DNG carries: 16-bit uncompressed CFA plane, CFA pattern,
// per-cell black levels, white level, AsShotNeutral (G-normalised) and
// ColorMatrix1.
//
// COLOR MATRIX DIRECTION (verified empirically, see SPIKE.md §4.5-5):
//   rawspeed's `metadata.colorMatrix` is documented as XYZ->camera. CIRAW's DNG
//   reader needs that value VERBATIM as ColorMatrix1. Writing its inverse blows
//   the render out by ~2.5-3 stops and yields a nonsense neutralChromaticity.
//   `invertMatrix` exists only as the counter-example probe; do not enable it
//   in production.

#pragma once

#include "RawSpeed-API.h"

#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace rsdng {

namespace detail {

inline void put16(std::vector<uint8_t>& v, uint16_t x) {
  v.push_back(uint8_t(x & 0xFF));
  v.push_back(uint8_t(x >> 8));
}
inline void put32(std::vector<uint8_t>& v, uint32_t x) {
  for (int i = 0; i < 4; ++i) v.push_back(uint8_t((x >> (8 * i)) & 0xFF));
}
inline void patch32(std::vector<uint8_t>& v, size_t at, uint32_t x) {
  for (int i = 0; i < 4; ++i) v[at + i] = uint8_t((x >> (8 * i)) & 0xFF);
}

// 3x3 inverse (row-major); false when singular.
inline bool inv3(const double m[9], double out[9]) {
  const double a = m[0], b = m[1], c = m[2];
  const double d = m[3], e = m[4], f = m[5];
  const double g = m[6], h = m[7], i = m[8];
  const double A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g;
  const double det = a * A + b * B + c * C;
  if (std::fabs(det) < 1e-12) return false;
  const double id = 1.0 / det;
  out[0] = A * id;
  out[1] = -(b * i - c * h) * id;
  out[2] = (b * f - c * e) * id;
  out[3] = B * id;
  out[4] = (a * i - c * g) * id;
  out[5] = -(a * f - c * d) * id;
  out[6] = C * id;
  out[7] = -(a * h - b * g) * id;
  out[8] = (a * e - b * d) * id;
  return true;
}

constexpr uint16_t kByte = 1, kAscii = 2, kShort = 3, kLong = 4, kRational = 5,
                   kSRational = 10;

struct Entry {
  uint16_t tag;
  uint16_t type;
  uint32_t count;
  std::vector<uint8_t> payload;
  uint32_t valueOffset = 0;
};

}  // namespace detail

namespace detail {

// One output cell = the mean of the same-colour samples inside its DIV x DIV block.
template <int DIV, class Plane>
inline void binBlock(const Plane& plane, uint16_t* out, int ow, int oh, const int cfa[4]) {
  for (int y = 0; y < oh; ++y) {
    const uint16_t* rows[DIV];
    for (int sy = 0; sy < DIV; ++sy) rows[sy] = &plane(y * DIV + sy, 0);
    for (int x = 0; x < ow; ++x) {
      int sum[4] = {0, 0, 0, 0}, cnt[4] = {0, 0, 0, 0};
      for (int sy = 0; sy < DIV; ++sy) {
        const uint16_t* rp = rows[sy] + x * DIV;
        for (int sx = 0; sx < DIV; ++sx) {
          const int c = cfa[(sy & 1) * 2 + (sx & 1)];
          sum[c] += rp[sx];
          cnt[c] += 1;
        }
      }
      const int c = cfa[(y & 1) * 2 + (x & 1)];
      out[size_t(y) * ow + x] = uint16_t((sum[c] + cnt[c] / 2) / cnt[c]);
    }
  }
}

template <class Plane>
inline void binAuto(const Plane& plane, uint16_t* out, int ow, int oh, int div, const int cfa[4]) {
  if (div == 2) binBlock<2>(plane, out, ow, oh, cfa);
  else if (div == 4) binBlock<4>(plane, out, ow, oh, cfa);
  else binBlock<1>(plane, out, ow, oh, cfa);
}

}  // namespace detail

struct Result {
  std::vector<uint8_t> bytes;
  int32_t width = 0, height = 0;
  int32_t cfa[4] = {0, 1, 1, 2};
  int32_t black[4] = {0, 0, 0, 0};
  int32_t white = 0;
  uint64_t mosaicFnv = 0;
};

// `downsample`: 0 = full, 1 = 1/4 area, 2 = 1/16 area (same-colour box binning).
// `neutralOverride`: optional AsShotNeutral (3 floats, G-normalized); nullptr = from file wb.
inline Result build(rawspeed::RawImageData* r, int downsample,
                    bool invertMatrix = false, bool wantFnv = true,
                    const float* neutralOverride = nullptr) {
  using namespace detail;
  Result res;

  const int cw = r->dim.x, ch = r->dim.y;
  const auto plane = r->getU16DataAsCroppedArray2DRef();
  int blSep4[4] = {r->blackLevel, r->blackLevel, r->blackLevel, r->blackLevel};
  if (r->blackLevelSeparate) {
    const auto bl = *r->blackLevelSeparate;  // Array2DRef<int>, 2x2
    for (int y = 0; y < 2; ++y)
      for (int x = 0; x < 2; ++x) blSep4[y * 2 + x] = bl[y](x);
  }
  const uint32_t white = r->whitePoint.value_or((1U << 16) - 1);
  const int cfa[4] = {int(r->cfa.getColorAt(0, 0)), int(r->cfa.getColorAt(1, 0)),
                      int(r->cfa.getColorAt(0, 1)), int(r->cfa.getColorAt(1, 1))};

  const int div = 1 << downsample;
  const int ow = cw / div, oh = ch / div;
  std::vector<uint16_t> mosaic(size_t(ow) * oh);
  if (downsample == 0) {
    for (int y = 0; y < oh; ++y)
      std::memcpy(&mosaic[size_t(y) * ow], &plane(y, 0), size_t(ow) * sizeof(uint16_t));
  } else {
    // Same-colour box binning with hoisted row pointers and a compile-time div.
    detail::binAuto(plane, mosaic.data(), ow, oh, div, cfa);
  }
  uint64_t h = 0;
  if (wantFnv) {
    h = 0xcbf29ce484222325ULL;
    for (uint16_t v : mosaic) {
      h ^= uint64_t(v & 0xFF); h *= 0x100000001b3ULL;
      h ^= uint64_t(v >> 8);   h *= 0x100000001b3ULL;
    }
  }

  std::vector<Entry> es;
  auto E = [&](uint16_t tag, uint16_t type, uint32_t count) -> Entry& {
    es.push_back(Entry{tag, type, count, {}, 0});
    return es.back();
  };

  E(254, kLong, 1); put32(es.back().payload, 0);                    // NewSubfileType
  E(256, kLong, 1); put32(es.back().payload, uint32_t(ow));
  E(257, kLong, 1); put32(es.back().payload, uint32_t(oh));
  E(258, kShort, 1); put16(es.back().payload, 16);                  // BitsPerSample
  E(259, kShort, 1); put16(es.back().payload, 1);                   // Compression = none
  E(262, kShort, 1); put16(es.back().payload, 32803);               // CFA
  {
    const std::string mk = r->metadata.make.empty() ? "Unknown" : r->metadata.make;
    E(271, kAscii, uint32_t(mk.size() + 1));
    for (char c : mk) es.back().payload.push_back(uint8_t(c));
    es.back().payload.push_back(0);
    const std::string md = r->metadata.model.empty() ? "Unknown" : r->metadata.model;
    E(272, kAscii, uint32_t(md.size() + 1));
    for (char c : md) es.back().payload.push_back(uint8_t(c));
    es.back().payload.push_back(0);
  }
  E(273, kLong, 1); put32(es.back().payload, 0);                    // StripOffsets (patched)
  E(274, kShort, 1); put16(es.back().payload, 1);                   // Orientation
  E(277, kShort, 1); put16(es.back().payload, 1);                   // SamplesPerPixel
  E(278, kLong, 1); put32(es.back().payload, uint32_t(oh));         // RowsPerStrip
  E(279, kLong, 1); put32(es.back().payload, uint32_t(ow) * oh * 2);
  E(284, kShort, 1); put16(es.back().payload, 1);                   // PlanarConfiguration
  E(33421, kShort, 2);
  put16(es.back().payload, 2); put16(es.back().payload, 2);         // CFARepeatPatternDim
  E(33422, kByte, 4);                                               // CFAPattern
  for (int c : cfa) es.back().payload.push_back(uint8_t(c));
  E(50706, kByte, 4);                                               // DNGVersion
  for (uint8_t b : {1, 4, 0, 0}) es.back().payload.push_back(b);
  E(50707, kByte, 4);                                               // DNGBackwardVersion
  for (uint8_t b : {1, 1, 0, 0}) es.back().payload.push_back(b);
  {
    const std::string um = "rawspeed:" + r->metadata.make + " " + r->metadata.model;
    E(50708, kAscii, uint32_t(um.size() + 1));
    for (char c : um) es.back().payload.push_back(uint8_t(c));
    es.back().payload.push_back(0);
  }
  E(50713, kShort, 2);                                              // BlackLevelRepeatDim
  put16(es.back().payload, 2); put16(es.back().payload, 2);
  E(50714, kRational, 4);                                           // BlackLevel (2x2)
  for (int c : blSep4) {
    put32(es.back().payload, uint32_t(c));
    put32(es.back().payload, 1);
  }
  E(50717, kLong, 1); put32(es.back().payload, white);              // WhiteLevel
  E(50718, kRational, 2);                                           // DefaultScale
  put32(es.back().payload, 1); put32(es.back().payload, 1);
  put32(es.back().payload, 1); put32(es.back().payload, 1);
  E(50719, kLong, 2);                                               // DefaultCropOrigin
  put32(es.back().payload, 0); put32(es.back().payload, 0);
  E(50720, kLong, 2);                                               // DefaultCropSize
  put32(es.back().payload, uint32_t(ow)); put32(es.back().payload, uint32_t(oh));
  // ColorMatrix1: see the direction note at the top of this file.
  {
    double xyz2cam[9] = {0, 0, 0, 0, 0, 0, 0, 0, 0};
    if (r->metadata.colorMatrix.size() == 9) {
      for (int i = 0; i < 9; ++i) {
        const auto& q = r->metadata.colorMatrix[i];
        xyz2cam[i] = q.den ? double(q.num) / double(q.den) : 0.0;
      }
    } else {
      xyz2cam[0] = xyz2cam[4] = xyz2cam[8] = 1.0;
    }
    double m[9];
    if (invertMatrix) {
      if (!inv3(xyz2cam, m))
        for (int i = 0; i < 9; ++i) m[i] = (i % 4 == 0) ? 1.0 : 0.0;
    } else {
      for (int i = 0; i < 9; ++i) m[i] = xyz2cam[i];  // verbatim (the working form)
    }
    E(50721, kSRational, 9);
    for (double v : m) {
      put32(es.back().payload, uint32_t(int32_t(std::lround(v * 10000.0))));
      put32(es.back().payload, 10000);
    }
  }
  E(50710, kByte, 3);                                               // CFAPlaneColor
  for (uint8_t c : {0, 1, 2}) es.back().payload.push_back(c);
  E(50711, kShort, 1); put16(es.back().payload, 1);                 // CFALayout
  E(50727, kRational, 3);                                           // AnalogBalance
  for (int i = 0; i < 3; ++i) {
    put32(es.back().payload, 1); put32(es.back().payload, 1);
  }
  E(50730, kSRational, 1);                                          // BaselineExposure = 0
  put32(es.back().payload, 0); put32(es.back().payload, 1);
  E(50731, kRational, 1);                                           // BaselineNoise
  put32(es.back().payload, 1); put32(es.back().payload, 1);
  E(50732, kRational, 1);                                           // BaselineSharpness
  put32(es.back().payload, 1); put32(es.back().payload, 1);
  // AsShotNeutral = 1/wb normalised to G=1 (rawspeed wbCoeffs pin G at 1024).
  {
    float asn[3];
    if (neutralOverride) {
      for (int i = 0; i < 3; ++i) asn[i] = neutralOverride[i];
    } else {
      float wb[3] = {1, 1, 1};
      if (r->metadata.wbCoeffs) {
        const auto& w = *r->metadata.wbCoeffs;
        for (int i = 0; i < 3; ++i) wb[i] = w[i] > 0 ? w[i] : 1.0f;
      }
      const float g = wb[1];
      for (int i = 0; i < 3; ++i) asn[i] = g / wb[i];
    }
    E(50728, kRational, 3);
    for (int i = 0; i < 3; ++i) {
      put32(es.back().payload, uint32_t(int32_t(std::lround(1e6 * asn[i]))));
      put32(es.back().payload, 1000000);
    }
  }
  E(50778, kShort, 1); put16(es.back().payload, 21);                // CalibrationIlluminant1 = D65
  E(50829, kLong, 4);                                               // ActiveArea
  put32(es.back().payload, 0); put32(es.back().payload, 0);
  put32(es.back().payload, uint32_t(oh)); put32(es.back().payload, uint32_t(ow));

  std::sort(es.begin(), es.end(), [](const Entry& a, const Entry& b) { return a.tag < b.tag; });

  const uint32_t ifdOffset = 8;
  uint32_t valueOff = ifdOffset + 2 + uint32_t(es.size()) * 12 + 4;
  for (auto& e : es) {
    if (e.payload.size() > 4) {
      valueOff = (valueOff + 3) & ~3u;
      e.valueOffset = valueOff;
      valueOff += uint32_t(e.payload.size());
    }
  }
  const uint32_t pixelOff = (valueOff + 3) & ~3u;

  auto& out = res.bytes;
  out.reserve(size_t(pixelOff) + size_t(ow) * oh * 2 + 16);
  out.push_back('I'); out.push_back('I');
  put16(out, 42);
  put32(out, ifdOffset);
  put16(out, uint16_t(es.size()));
  for (auto& e : es) {
    put16(out, e.tag);
    put16(out, e.type);
    put32(out, e.count);
    if (e.payload.size() <= 4) {
      for (int i = 0; i < 4; ++i) out.push_back(i < int(e.payload.size()) ? e.payload[i] : 0);
    } else {
      put32(out, e.valueOffset);
    }
  }
  put32(out, 0);  // next IFD
  for (size_t i = 0; i < es.size(); ++i) {
    if (es[i].tag == 273) patch32(out, ifdOffset + 2 + i * 12 + 8, pixelOff);
  }
  for (auto& e : es) {
    if (e.payload.size() > 4) {
      while (out.size() < e.valueOffset) out.push_back(0);
      out.insert(out.end(), e.payload.begin(), e.payload.end());
    }
  }
  while (out.size() < pixelOff) out.push_back(0);
  out.resize(out.size() + size_t(ow) * oh * 2);
  std::memcpy(out.data() + pixelOff, mosaic.data(), size_t(ow) * oh * 2);

  res.width = ow;
  res.height = oh;
  for (int i = 0; i < 4; ++i) { res.cfa[i] = cfa[i]; res.black[i] = blSep4[i]; }
  res.white = int32_t(white);
  res.mosaicFnv = h;
  return res;
}

}  // namespace rsdng

// SPDX-License-Identifier: GPL-3.0-or-later
// rawspeed_shim.cpp — implementation of rawspeed_shim.h (B2-a).
//
// Exception discipline: every extern "C" entry is noexcept-in-effect. All
// rawspeed/std/unknown exceptions are caught at the boundary and mapped to
// RS_ERR_* by classify(). Nothing allocates past the point of failure on
// error paths (unique_ptr staging, release-on-success).

#include "rawspeed_shim.h"
#include "RawSpeed-API.h"
#include "tiff/TiffEntry.h"
#include "tiff/TiffIFD.h"
#include "tiff/TiffTag.h"

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cxxabi.h>
#include <fstream>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <utility>
#include <vector>

#ifndef RS_CAMERAS_XML_DEFAULT
#error "RS_CAMERAS_XML_DEFAULT must be -D by build.rs"
#endif

using namespace rawspeed;

struct rs_image {
  // Destruction order is the reverse of declaration: bytes die last, so the
  // Buffer views and the decoder (which borrows them) are always valid.
  std::vector<uint8_t> bytes;
  Buffer file;
  std::unique_ptr<RawParser> parser;
  std::unique_ptr<RawDecoder> decoder;
  std::shared_ptr<const CameraMetaData> meta;
  RawImage raw = RawImage::create();
  RawImageData* data = nullptr;
  bool decoded = false;
  bool probed = false;
  std::string decoderName;
};

namespace {

void setErr(rs_error* e, int32_t code, const char* msg) {
  if (!e)
    return;
  e->code = code;
  if (!msg) {
    e->message[0] = '\0';
    return;
  }
  std::strncpy(e->message, msg, sizeof(e->message) - 1);
  e->message[sizeof(e->message) - 1] = '\0';
}

bool contains(const char* hay, const char* needle) {
  return hay && needle && std::strstr(hay, needle) != nullptr;
}
// stage: 0 = rs_open, 1 = rs_decode. Order is significant: specific camera
// strings precede the generic "support" rule. Message wordings were captured
// from rawspeed 0c16fee77 (see B2a-REPORT §5).
int32_t classify(int stage, const char* msg) {
  if (!msg)
    return RS_ERR_INTERNAL;
  // Truncation family (observed: "File is 0 bytes.", "Buffer overflow: image
  // file may be truncated", "Out of bounds access in ByteStream", "Truncated
  // file").
  if (contains(msg, "0 bytes") || contains(msg, "runca") ||
      contains(msg, "Buffer overflow") || contains(msg, "Out of bounds") ||
      contains(msg, "out of range") || contains(msg, "past end") ||
      contains(msg, "End of buffer") || contains(msg, "unexpected end"))
    return RS_ERR_TRUNCATED;
  // Not a RAW (observed: "No decoder found. Sorry.").
  if (contains(msg, "No decoder found"))
    return RS_ERR_NOT_RAW;
  // Unknown camera (observed: "Camera '…' '…' mode '…' not supported, and
  // not allowed to ...", "Couldn't find camera %s %s",
  // "Camera not supported (explicit). Sorry.").
  if (contains(msg, "Couldn't find camera") ||
      contains(msg, "not supported (explicit)") ||
      contains(msg, "not supported, and not allowed") ||
      (contains(msg, "Camera '") && contains(msg, "not supported")))
    return RS_ERR_UNKNOWN_CAMERA;
  // Unsupported compression ("Unsupported compression %i", "%u stripes, and
  // not uncompressed. Unsupported.", "Couldn't find compression setting").
  // "ompress" deliberately matches compress/compressed/uncompressed.
  if ((contains(msg, "ompress") || contains(msg, "LJpeg")) &&
      (contains(msg, "upport") || contains(msg, "Couldn't find")))
    return RS_ERR_UNSUPPORTED_COMPRESSION;
  // Decompressor failures ("Error decompressing",
  // "JPEG Error while decompressing image.").
  if (contains(msg, "ecompress"))
    return RS_ERR_DECOMPRESS;
  // Generic support failures fall back to the stage default.
  if (contains(msg, "upport"))
    return stage == 0 ? RS_ERR_NOT_RAW : RS_ERR_DECOMPRESS;
  return stage == 0 ? RS_ERR_NOT_RAW : RS_ERR_DECOMPRESS;
}

std::once_flag metaOnce;
std::shared_ptr<const CameraMetaData> defaultMeta;
std::atomic<uint64_t> metaParseCount{0};
std::atomic<uint64_t> decodeCount{0};
std::atomic<uint64_t> probeCount{0};

// Throws on XML failure; callers map that to RS_ERR_INTERNAL (a broken
// cameras.xml is a packaging bug, never a property of the input file).
// Default OpenMP workers to blocking waits. libomp's default spin wastes CPU
// on a shared desktop and makes bursty decode latency swing with machine
// load (B2-a measured 66-186 ms active vs 65-75 ms passive on the 61 MP
// gate file); blocking is the sane embedding default. Explicit user
// settings win (overwrite = 0). Runs before any OpenMP region: libomp reads
// the variable lazily at runtime init, and meta parsing is serial.
void defaultOmpWaitPolicy() {
  ::setenv("OMP_WAIT_POLICY", "passive", 0);
}

std::shared_ptr<const CameraMetaData> getMeta(const char* path) {
  defaultOmpWaitPolicy();
  if (path && path[0] != '\0') {
    auto m = std::make_shared<CameraMetaData>(path);
    metaParseCount.fetch_add(1, std::memory_order_relaxed);
    return m;
  }
  std::call_once(metaOnce, [] {
    defaultMeta = std::make_shared<CameraMetaData>(RS_CAMERAS_XML_DEFAULT);
    metaParseCount.fetch_add(1, std::memory_order_relaxed);
  });
  return defaultMeta;
}

std::string demangleDecoder(const char* mangled) {
  int status = 0;
  char* out = abi::__cxa_demangle(mangled, nullptr, nullptr, &status);
  std::string full = (status == 0 && out) ? out : mangled;
  std::free(out);
  // "rawspeed::ArwDecoder" -> "ArwDecoder".
  const auto pos = full.rfind(':');
  if (pos != std::string::npos && pos + 1 < full.size())
    return full.substr(pos + 1);
  return full;
}

void copyStr(char* dst, size_t cap, const std::string& src) {
  if (cap == 0)
    return;
  std::strncpy(dst, src.c_str(), cap - 1);
  dst[cap - 1] = '\0';
}

// Mirrors darktable's camera-sample check
// (`dt_imageio_open_rawspeed[_sraw]`, `src/imageio/imageio_rawspeed.cc`):
// the camera is known but ships without RPU samples.
int cameraMissingSample(const CameraMetaData* meta, const RawImageData* r) {
  if (!meta || !r)
    return 0;
  const Camera* cam = meta->getCamera(r->metadata.make, r->metadata.model,
                                      r->metadata.mode);
  return (cam && cam->supportStatus == Camera::SupportStatus::SupportedNoSamples)
             ? 1
             : 0;
}

// The pixel-independent half of `rs_image_info`: CFA, levels, WB, color
// matrix, ISO, subsampling, and names. Shared by the decode fill and the
// probe fill (both run decodeMetaData, so these read identically).
void fillMetadataFields(const CameraMetaData* meta, RawImageData* r,
                         const std::string& decoderName, rs_image_info* out) {
  out->is_cfa = r->isCFA ? 1 : 0;
  const iPoint2D cfaSize = r->cfa.getSize();
  out->cfa_w = cfaSize.x;
  out->cfa_h = cfaSize.y;
  out->is_xtrans = (cfaSize.x == 6 && cfaSize.y == 6) ? 1 : 0;
  const int cells = cfaSize.x * cfaSize.y;
  out->cfa_valid = cells < RS_CFA_PATTERN_MAX ? cells : RS_CFA_PATTERN_MAX;
  for (int i = 0; i < out->cfa_valid; ++i) {
    const int y = i / cfaSize.x;
    const int x = i % cfaSize.x;
    out->cfa_pattern[i] = static_cast<int32_t>(r->cfa.getColorAt(x, y));
  }
  out->cfa_dcraw_filter = r->cfa.getDcrawFilter();
  out->black_level = r->blackLevel;
  if (r->blackLevelSeparate) {
    // Always 2x2 over blackLevelSeparateStorage at the pinned commit.
    const auto bl = *r->blackLevelSeparate;
    out->has_black_sep = 1;
    out->black_level_separate[0] = bl[0](0);
    out->black_level_separate[1] = bl[0](1);
    out->black_level_separate[2] = bl[1](0);
    out->black_level_separate[3] = bl[1](1);
  }
  if (r->whitePoint) {
    out->has_white = 1;
    out->white_level = *r->whitePoint;
  }
  if (r->metadata.wbCoeffs) {
    out->has_wb = 1;
    const auto& wb = *r->metadata.wbCoeffs;
    for (int i = 0; i < 4; ++i)
      out->wb_coeffs[i] = wb[i];
  }
  // Exactly-9 gate: upstream fills a 4x3 (`idx < msize`, else 0), so a
  // 12-value matrix loses its 4th row here; non-9 sizes report absent.
  if (r->metadata.colorMatrix.size() == 9) {
    out->has_color_matrix = 1;
    for (int i = 0; i < 9; ++i) {
      const auto& q = r->metadata.colorMatrix[i];
      out->color_matrix[i] =
          q.den ? static_cast<float>(q.num) / static_cast<float>(q.den) : 0.0F;
    }
  }
  out->iso_speed = r->metadata.isoSpeed;
  out->subsampling_x = r->metadata.subsampling.x;
  out->subsampling_y = r->metadata.subsampling.y;
  out->pixel_aspect_ratio = r->metadata.pixelAspectRatio;
  copyStr(out->make, sizeof(out->make), r->metadata.make);
  copyStr(out->model, sizeof(out->model), r->metadata.model);
  copyStr(out->canonical_make, sizeof(out->canonical_make),
          r->metadata.canonical_make);
  copyStr(out->canonical_model, sizeof(out->canonical_model),
          r->metadata.canonical_model);
  copyStr(out->mode, sizeof(out->mode), r->metadata.mode);
  copyStr(out->decoder, sizeof(out->decoder), decoderName);
  out->camera_missing_sample = cameraMissingSample(meta, r);
}

// Probe shape check plus uncropped dims from TIFF tags, mirroring the
// ArwDecoder dimension reads (`DecodeUncompressed` / `DecodeLJpeg`). The
// crop itself is NOT computed here: `rs_probe` presets `mRaw->dim` with the
// tag dims and lets rawspeed apply the crop (cameras.xml for compression 1
// via `setMetaData`, `SONYRAWIMAGESIZE` for compression 7 with `applyCrop =
// false`), exactly as the decode path does. Returns false for anything else
// (caller falls back to a full decode, which reports the precise error);
// never throws.
bool probeArwGeometry(const rs_image* img, int& uncroppedW, int& uncroppedH,
                       int& sonyCropW, int& sonyCropH, bool& useCamCrop) {
  try {
    if (!img || !img->decoder || img->decoderName != "ArwDecoder")
      return false;
    TiffIFD* root = img->decoder->getRootIFD();
    if (!root)
      return false;
    const std::vector<const TiffIFD*> data =
        root->getIFDsWithTag(TiffTag::STRIPOFFSETS);
    if (data.empty() || !data[0])
      return false;
    const TiffIFD* raw = data[0];
    const uint32_t compression =
        raw->getEntry(TiffTag::COMPRESSION)->getU32();
    const uint32_t width = raw->getEntry(TiffTag::IMAGEWIDTH)->getU32();
    const uint32_t height = raw->getEntry(TiffTag::IMAGELENGTH)->getU32();
    if (width == 0 || height == 0 || width > INT32_MAX || height > INT32_MAX)
      return false;
    if (compression == 7) {
      const uint32_t photometric =
          raw->getEntry(TiffTag::PHOTOMETRICINTERPRETATION)->getU32();
      const uint32_t bitPerPixel =
          raw->getEntry(TiffTag::BITSPERSAMPLE)->getU32();
      if (photometric != 32803)
        return false;
      if (bitPerPixel != 8 && bitPerPixel != 12 && bitPerPixel != 14)
        return false;
      if (width % 2 != 0 || height % 2 != 0 || width > 10240 || height > 7168)
        return false;
      const TiffEntry* sizeEntry = raw->getEntry(TiffTag::SONYRAWIMAGESIZE);
      const uint32_t cropW = sizeEntry->getU32(0);
      const uint32_t cropH = sizeEntry->getU32(1);
      if (cropW == 0 || cropH == 0 || cropW > width || cropH > height)
        return false;
      uncroppedW = static_cast<int>(width);
      uncroppedH = static_cast<int>(height);
      sonyCropW = static_cast<int>(cropW);
      sonyCropH = static_cast<int>(cropH);
      useCamCrop = false;
      return true;
    }
    if (compression == 1) {
      if (width > 9600 || height > 6376)
        return false;
      uncroppedW = static_cast<int>(width);
      uncroppedH = static_cast<int>(height);
      sonyCropW = 0;
      sonyCropH = 0;
      useCamCrop = true;
      return true;
    }
    return false;
  } catch (...) {
    return false;
  }
}

} // namespace

extern "C" {

rs_image* rs_open(const char* path, const char* cameras_xml, rs_error* err) {
  if (err) {
    err->code = RS_OK;
    err->message[0] = '\0';
  }
  if (!path || path[0] == '\0') {
    setErr(err, RS_ERR_NOT_FOUND, "empty path");
    return nullptr;
  }
  try {
    std::shared_ptr<const CameraMetaData> meta;
    try {
      meta = getMeta(cameras_xml);
    } catch (const std::exception& e) {
      std::string m = std::string("camera database failed to parse: ") + e.what();
      setErr(err, RS_ERR_INTERNAL, m.c_str());
      return nullptr;
    } catch (...) {
      setErr(err, RS_ERR_INTERNAL, "camera database failed to parse");
      return nullptr;
    }

    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f) {
      setErr(err, RS_ERR_NOT_FOUND, "file missing or unreadable");
      return nullptr;
    }
    const std::ifstream::pos_type end = f.tellg();
    if (end == std::ifstream::pos_type(-1)) {
      setErr(err, RS_ERR_NOT_FOUND, "file size unknown");
      return nullptr;
    }
    const auto size = static_cast<uint64_t>(end);
    if (size == 0) {
      setErr(err, RS_ERR_TRUNCATED, "file is empty (0 bytes)");
      return nullptr;
    }
    if (size > static_cast<uint64_t>(INT32_MAX)) {
      setErr(err, RS_ERR_INTERNAL, "file exceeds 2 GiB Buffer limit");
      return nullptr;
    }
    f.seekg(0, std::ios::beg);
    auto img = std::make_unique<rs_image>();
    img->bytes.resize(static_cast<size_t>(size));
    f.read(reinterpret_cast<char*>(img->bytes.data()),
           static_cast<std::streamsize>(size));
    if (!f) {
      setErr(err, RS_ERR_TRUNCATED, "file shrank while reading");
      return nullptr;
    }
    img->file =
        Buffer(img->bytes.data(), static_cast<Buffer::size_type>(size));
    img->parser = std::make_unique<RawParser>(img->file);
    img->decoder = img->parser->getDecoder(meta.get());
    if (!img->decoder) {
      setErr(err, RS_ERR_NOT_RAW, "no RAW decoder accepts this file");
      return nullptr;
    }
    img->decoder->failOnUnknown = true;
    img->decoder->checkSupport(meta.get());
    const RawDecoder& decRef = *img->decoder;
    img->decoderName = demangleDecoder(typeid(decRef).name());
    img->meta = std::move(meta);
    return img.release();
  } catch (const std::bad_alloc&) {
    setErr(err, RS_ERR_NOMEM, "out of memory");
  } catch (const std::exception& e) {
    setErr(err, classify(0, e.what()), e.what());
  } catch (...) {
    setErr(err, RS_ERR_INTERNAL, "unknown C++ exception in rs_open");
  }
  return nullptr;
}

int32_t rs_decode(rs_image* img, rs_error* err) {
  if (err) {
    err->code = RS_OK;
    err->message[0] = '\0';
  }
  if (!img) {
    setErr(err, RS_ERR_INTERNAL, "null handle");
    return -1;
  }
  if (img->decoded)
    return 0;
  if (img->probed) {
    setErr(err, RS_ERR_INTERNAL,
           "image already probed; open a new handle to decode");
    return -1;
  }
  try {
    img->raw = img->decoder->decodeRaw();
    img->decoder->decodeMetaData(img->meta.get());
    img->data = img->raw.get();
    img->decoded = true;
    decodeCount.fetch_add(1, std::memory_order_relaxed);
    return 0;
  } catch (const std::bad_alloc&) {
    setErr(err, RS_ERR_NOMEM, "out of memory");
  } catch (const std::exception& e) {
    setErr(err, classify(1, e.what()), e.what());
  } catch (...) {
    setErr(err, RS_ERR_INTERNAL, "unknown C++ exception in rs_decode");
  }
  return -1;
}

int32_t rs_fill_info(const rs_image* img, rs_image_info* out, rs_error* err) {
  if (err) {
    err->code = RS_OK;
    err->message[0] = '\0';
  }
  if (!img || !out) {
    setErr(err, RS_ERR_INTERNAL, "null handle");
    return -1;
  }
  if (!img->decoded || !img->data) {
    setErr(err, RS_ERR_INTERNAL, "image not decoded");
    return -1;
  }
  try {
    std::memset(out, 0, sizeof(*out));
    RawImageData* r = img->data;
    const bool isU16 = r->getDataType() == RawImageType::UINT16;
    out->data_type = isU16 ? RS_MOSAIC_U16 : RS_MOSAIC_F32;
    out->width = r->dim.x;
    out->height = r->dim.y;
    const iPoint2D un = r->getUncroppedDim();
    out->uncropped_width = un.x;
    out->uncropped_height = un.y;
    const iPoint2D off = r->getCropOffset();
    out->crop_left = off.x;
    out->crop_top = off.y;
    out->crop_right = un.x - r->dim.x - off.x;
    out->crop_bottom = un.y - r->dim.y - off.y;
    if (isU16)
      out->pitch_elems =
          static_cast<int32_t>(r->getU16DataAsCroppedArray2DRef()
                                   .getAsArray2DRef()
                                   .pitch());
    else
      out->pitch_elems =
          static_cast<int32_t>(r->getF32DataAsCroppedArray2DRef()
                                   .getAsArray2DRef()
                                   .pitch());
    out->cpp = static_cast<int32_t>(r->getCpp());
    out->bpp = static_cast<int32_t>(r->getBpp());
    fillMetadataFields(img->meta.get(), r, img->decoderName, out);
    out->mosaic_bytes =
        static_cast<uint64_t>(r->dim.x) * static_cast<uint64_t>(r->dim.y) *
        static_cast<uint64_t>(r->getCpp()) * (isU16 ? 2ULL : 4ULL);
    return 0;
  } catch (const std::exception& e) {
    setErr(err, RS_ERR_INTERNAL, e.what());
  } catch (...) {
    setErr(err, RS_ERR_INTERNAL, "unknown C++ exception in rs_fill_info");
  }
  return -1;
}

int32_t rs_probe_supported(const rs_image* img) {
  // Pure shape check: no metadata call, no state change. Any anomaly —
  // including a corrupt TIFF tree — degrades to 0 so the caller falls back
  // to `rs_decode`, which reports the precise error.
  if (!img || img->decoded || img->probed)
    return 0;
  int uw = 0, uh = 0, cw = 0, ch = 0;
  bool camCrop = false;
  return probeArwGeometry(img, uw, uh, cw, ch, camCrop) ? 1 : 0;
}

int32_t rs_probe(rs_image* img, rs_image_info* out, rs_error* err) {
  if (err) {
    err->code = RS_OK;
    err->message[0] = '\0';
  }
  if (!img || !out) {
    setErr(err, RS_ERR_INTERNAL, "null handle");
    return -1;
  }
  if (img->decoded) {
    setErr(err, RS_ERR_INTERNAL, "image already decoded");
    return -1;
  }
  if (img->probed) {
    setErr(err, RS_ERR_INTERNAL, "image already probed");
    return -1;
  }
  int uw = 0, uh = 0, cw = 0, ch = 0;
  bool camCrop = false;
  if (!probeArwGeometry(img, uw, uh, cw, ch, camCrop)) {
    setErr(err, RS_ERR_INTERNAL,
           "probe unsupported for this file; use rs_decode");
    return -1;
  }
  // Preset the dims decodeRaw would set, so decodeMetaData runs against a
  // sized (still pixel-less) image: the crop applies exactly as on the
  // decode path, including any CFA shift. No pixel memory is allocated.
  img->decoder->mRaw->dim = iPoint2D(uw, uh);
  if (!camCrop)
    img->decoder->applyCrop = false; // DecodeLJpeg does the same.
  try {
    img->decoder->decodeMetaData(img->meta.get());
  } catch (const std::bad_alloc&) {
    setErr(err, RS_ERR_NOMEM, "out of memory");
    return -1;
  } catch (const std::exception& e) {
    setErr(err, classify(1, e.what()), e.what());
    return -1;
  } catch (...) {
    setErr(err, RS_ERR_INTERNAL, "unknown C++ exception in rs_probe");
    return -1;
  }
  RawImageData* r = img->decoder->mRaw.get();
  if (!r) {
    setErr(err, RS_ERR_INTERNAL, "probe metadata missing");
    return -1;
  }
  try {
    std::memset(out, 0, sizeof(*out));
    if (!camCrop)
      r->subFrame(iRectangle2D(0, 0, cw, ch)); // DecodeLJpeg's trailing crop.
    // Geometry reads exactly as rs_fill_info does; only the sample layout
    // is probe-known: both shapes are single-component u16 (the LJPEG path
    // only ever creates u16 data). Pitch mirrors the fresh allocation
    // (see below), not the tag width.
    out->data_type = RS_MOSAIC_U16;
    out->width = r->dim.x;
    out->height = r->dim.y;
    // Uncropped dims come from the tags: `uncropped_dim` is only assigned in
    // `createData()` (pixel allocation), so `getUncroppedDim()` reads zero on
    // a pixel-less image. Offset and cropped dims read back as usual.
    out->uncropped_width = uw;
    out->uncropped_height = uh;
    const iPoint2D off = r->getCropOffset();
    out->crop_left = off.x;
    out->crop_top = off.y;
    out->crop_right = uw - r->dim.x - off.x;
    out->crop_bottom = uh - r->dim.y - off.y;
    // Pitch mirrors `createData()`: bytes round up to 16 (`roundUp(dim.x *
    // bpp, alignment)`), so elements are `roundUp(uw * 2, 16) / 2` — plain
    // `uw` only when `uw % 8 == 0`.
    out->pitch_elems = (uw * 2 + 15) / 16 * 16 / 2;
    out->cpp = 1;
    out->bpp = 2;
    fillMetadataFields(img->meta.get(), r, img->decoderName, out);
    out->mosaic_bytes = static_cast<uint64_t>(out->width) *
                        static_cast<uint64_t>(out->height) * 2ULL;
    img->probed = true;
    probeCount.fetch_add(1, std::memory_order_relaxed);
    return 0;
  } catch (const std::exception& e) {
    setErr(err, RS_ERR_INTERNAL, e.what());
  } catch (...) {
    setErr(err, RS_ERR_INTERNAL, "unknown C++ exception in rs_probe");
  }
  return -1;
}

const uint16_t* rs_mosaic_u16(const rs_image* img) {
  // Defensive: the callee chain is noexcept, but the contract is "no C++
  // exception crosses", so a throw (or a future API change) degrades to
  // NULL instead of escaping (M4).
  try {
    if (!img || !img->decoded || !img->data)
      return nullptr;
    if (img->data->getDataType() != RawImageType::UINT16)
      return nullptr;
    if (img->data->dim.x <= 0 || img->data->dim.y <= 0)
      return nullptr;
    return img->data->getU16DataAsCroppedArray2DRef()[0].begin();
  } catch (...) {
    return nullptr;
  }
}

const float* rs_mosaic_f32(const rs_image* img) {
  // Defensive: same contract as rs_mosaic_u16 (M4).
  try {
    if (!img || !img->decoded || !img->data)
      return nullptr;
    if (img->data->getDataType() != RawImageType::F32)
      return nullptr;
    if (img->data->dim.x <= 0 || img->data->dim.y <= 0)
      return nullptr;
    return img->data->getF32DataAsCroppedArray2DRef()[0].begin();
  } catch (...) {
    return nullptr;
  }
}

uint64_t rs_mosaic_hash(const rs_image* img, rs_error* err) {
  if (err) {
    err->code = RS_OK;
    err->message[0] = '\0';
  }
  if (!img || !img->decoded || !img->data) {
    setErr(err, RS_ERR_INTERNAL, "image not decoded");
    return 0;
  }
  try {
    RawImageData* r = img->data;
    uint64_t h = 14695981039346656037ULL;
    const int w = r->dim.x;
    const int hgt = r->dim.y;
    if (r->getDataType() == RawImageType::UINT16) {
      auto view = r->getU16DataAsCroppedArray2DRef();
      for (int y = 0; y < hgt; ++y) {
        const auto* row = view[y].begin();
        for (int x = 0; x < w; ++x) {
          const uint16_t v = row[x];
          h ^= static_cast<uint64_t>(v & 0xFF);
          h *= 1099511628211ULL;
          h ^= static_cast<uint64_t>((v >> 8) & 0xFF);
          h *= 1099511628211ULL;
        }
      }
    } else {
      auto view = r->getF32DataAsCroppedArray2DRef();
      for (int y = 0; y < hgt; ++y) {
        const auto* row = view[y].begin();
        for (int x = 0; x < w; ++x) {
          uint32_t u = 0;
          std::memcpy(&u, &row[x], sizeof(u));
          for (int b = 0; b < 4; ++b) {
            h ^= static_cast<uint64_t>((u >> (8 * b)) & 0xFF);
            h *= 1099511628211ULL;
          }
        }
      }
    }
    return h;
  } catch (const std::exception& e) {
    setErr(err, RS_ERR_INTERNAL, e.what());
  } catch (...) {
    setErr(err, RS_ERR_INTERNAL, "unknown C++ exception in rs_mosaic_hash");
  }
  return 0;
}

void rs_free(rs_image* img) { delete img; }

int32_t rs_ensure_meta(rs_error* err) {
  if (err) {
    err->code = RS_OK;
    err->message[0] = '\0';
  }
  try {
    getMeta(nullptr);
    return 0;
  } catch (const std::exception& e) {
    std::string m = std::string("camera database failed to parse: ") + e.what();
    setErr(err, RS_ERR_INTERNAL, m.c_str());
  } catch (...) {
    setErr(err, RS_ERR_INTERNAL, "camera database failed to parse");
  }
  return -1;
}

uint64_t rs_meta_parse_count(void) {
  return metaParseCount.load(std::memory_order_relaxed);
}

uint64_t rs_decode_count(void) {
  return decodeCount.load(std::memory_order_relaxed);
}

uint64_t rs_probe_count(void) {
  return probeCount.load(std::memory_order_relaxed);
}

size_t rs_info_size(void) { return sizeof(rs_image_info); }

size_t rs_error_size(void) { return sizeof(rs_error); }

int32_t rs_classify_for_test(int32_t stage, const char* msg) {
  if (!msg || (stage != 0 && stage != 1))
    return RS_ERR_INTERNAL;
  return classify(stage, msg);
}

} // extern "C"

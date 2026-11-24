#include "rawspeed_shim.h"
#include "RawSpeed-API.h"
#include "dngwriter.h"

#include <cstdlib>
#include <cstring>
#include <new>
#include <utility>

using namespace rawspeed;

struct rs_image {
    RawImage raw;
    RawImageData* data;   // owned by `raw`; kept non-const for the plane accessors
    std::unique_ptr<RawDecoder> decoder;
};

namespace {

void setErr(rs_error *e, int32_t code, const char *msg) {
    if (!e) return;
    e->code = code;
    std::strncpy(e->message, msg, sizeof(e->message) - 1);
    e->message[sizeof(e->message) - 1] = '\0';
}

} // namespace

extern "C" {

rs_image *rs_open(const char *path, const char *cameras_xml, rs_error *err) {
    if (err) { err->code = 0; err->message[0] = '\0'; }
    try {
        auto meta = std::make_unique<CameraMetaData>(cameras_xml);
        FileReader f(path);
        auto [storage, buf] = f.readFile();
        // storage must outlive parsing; hand it to the handle via a decoder that
        // copies the mosaic (decodeRaw allocates its own plane).
        auto parser = std::make_unique<RawParser>(buf);
        auto decoder = parser->getDecoder(meta.get());
        if (!decoder) {
            setErr(err, 4, "rawspeed: no decoder for file");
            return nullptr;
        }
        decoder->failOnUnknown = true;
        decoder->checkSupport(meta.get());
        decoder->decodeRaw();
        decoder->decodeMetaData(meta.get());
        RawImageData* plane = decoder->mRaw.get();
        auto *out = new (std::nothrow) rs_image{decoder->mRaw, plane, std::move(decoder)};
        if (!out) { setErr(err, 3, "out of memory"); return nullptr; }
        return out;
    } catch (const RawspeedException &e) {
        setErr(err, 2, e.what());
    } catch (const std::exception &e) {
        setErr(err, 3, e.what());
    } catch (...) {
        setErr(err, 3, "unknown C++ exception");
    }
    return nullptr;
}

int32_t rs_fill_info(const rs_image *img, rs_image_info *out, rs_error *err) {
    if (!img || !out) { setErr(err, 3, "null handle"); return -1; }
    try {
        std::memset(out, 0, sizeof(*out));
        RawImageData* r = img->data;
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
        out->pitch_elems = static_cast<int32_t>(r->getU16DataAsCroppedArray2DRef().getAsArray2DRef().pitch());
        out->cpp = static_cast<int32_t>(r->getCpp());
        out->bpp = static_cast<int32_t>(r->getBpp());
        out->is_cfa = r->isCFA ? 1 : 0;
        const iPoint2D cfaSize = r->cfa.getSize();
        out->is_xtrans = (cfaSize.x == 6 && cfaSize.y == 6) ? 1 : 0;
        out->cfa_dcraw_filter = r->cfa.getDcrawFilter();
        for (int y = 0; y < 2; ++y)
            for (int x = 0; x < 2; ++x)
                out->cfa_pattern[y * 2 + x] = static_cast<int32_t>(r->cfa.getColorAt(x, y));
        out->black_level = r->blackLevel;
        if (r->blackLevelSeparate) {
            const auto bl = *r->blackLevelSeparate;   // Array2DRef<int>, 2x2
            for (int y = 0; y < 2; ++y)
                for (int x = 0; x < 2; ++x)
                    out->black_level_separate[y * 2 + x] = bl[y](x);
        }
        out->white_level = r->whitePoint ? *r->whitePoint : 0;
        if (r->metadata.wbCoeffs) {
            out->has_wb = 1;
            for (int i = 0; i < 3; ++i)
                out->wb_coeffs[i] = (*(r->metadata.wbCoeffs))[i];
        } else {
            out->wb_coeffs[0] = out->wb_coeffs[1] = out->wb_coeffs[2] = 1.0f;
        }
        if (r->metadata.colorMatrix.size() == 9) {
            out->has_color_matrix = 1;
            for (int i = 0; i < 9; ++i) {
                const auto &q = r->metadata.colorMatrix[i];
                out->color_matrix[i] = q.den ? static_cast<float>(q.num) / static_cast<float>(q.den) : 0.0f;
            }
        } else {
            for (int i = 0; i < 9; ++i) out->color_matrix[i] = (i % 4 == 0) ? 1.0f : 0.0f;
        }
        std::strncpy(out->make, r->metadata.make.c_str(), sizeof(out->make) - 1);
        std::strncpy(out->model, r->metadata.model.c_str(), sizeof(out->model) - 1);
        return 0;
    } catch (const std::exception &e) {
        setErr(err, 3, e.what());
    }
    return -1;
}

const uint16_t *rs_mosaic(const rs_image *img) {
    if (!img || img->data->getDataType() != RawImageType::UINT16) return nullptr;
    const auto plane = img->data->getU16DataAsCroppedArray2DRef();
    return &plane(0, 0);
}

uint64_t rs_mosaic_hash(const rs_image *img) {
    if (!img) return 0;
    auto plane = img->data->getU16DataAsCroppedArray2DRef();
    uint64_t h = 0xcbf29ce484222325ULL;  // FNV-1a 64 offset basis
    for (int y = 0; y < plane.croppedHeight; ++y)
        for (int x = 0; x < plane.croppedWidth; ++x) {
            const uint16_t v = plane(y, x);
            h ^= static_cast<uint8_t>(v & 0xFF); h *= 1099511628211ULL;
            h ^= static_cast<uint8_t>(v >> 8);   h *= 1099511628211ULL;
        }
    return h;
}

int32_t rs_build_dng(const rs_image *img, int32_t downsample, uint8_t **outBytes,
                     size_t *outLen, rs_error *err) {
    if (!img || !outBytes || !outLen) { setErr(err, 3, "null argument"); return -1; }
    if (downsample < 0 || downsample > 2) { setErr(err, 3, "downsample must be 0..2"); return -1; }
    try {
        // wantFnv = false: the cross-check hash is a probe cost, not part of the seam.
        rsdng::Result res = rsdng::build(img->data, downsample, /*invertMatrix=*/false,
                                        /*wantFnv=*/false);
        auto *p = static_cast<uint8_t *>(std::malloc(res.bytes.size()));
        if (!p) { setErr(err, 3, "out of memory"); return -1; }
        std::memcpy(p, res.bytes.data(), res.bytes.size());
        *outBytes = p;
        *outLen = res.bytes.size();
        if (err) { err->code = 0; err->message[0] = '\0'; }
        return 0;
    } catch (const std::exception &e) {
        setErr(err, 3, e.what());
    }
    return -1;
}

void rs_free_bytes(uint8_t *bytes) { std::free(bytes); }

void rs_free(rs_image *img) { delete img; }

} // extern "C"

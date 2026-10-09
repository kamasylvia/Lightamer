#!/usr/bin/env python3
# gen-tiff-fixtures.py — the TIFF raster fixture matrix generator
# (Plan M4-1-01 T2, KD-2). Offline, deterministic, idempotent: two runs
# produce byte-identical files (fixed pixel data, metadata=None, fixed ICC
# bytes). Run:  uv run --with tifffile numpy python3 Scripts/gen-tiff-fixtures.py
#
# Output: Tests/Fixtures/TiffRaster/ (the plan's on-disk product assets —
# every file ≤ 512×512 per the IOP bundle discipline; the generator IS the
# provenance record, the README carries the matrix).
#
# ICC profiles are synthesized here with the same layout the Swift-side
# parser reads (RasterIccParser): matrix-shaper + Bradford chad + curv/
# para/identity TRCs + the v4.4 cicp tag + mDCv, and an mft2 (LUT16Type)
# A2B0 for the LUT-based forms. All TRCs ride curv carriers (never para) —
# the L053 para misparse trap stays out of the fixture set.

import os
import struct

import numpy as np
import tifffile

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "Tests", "Fixtures", "TiffRaster")
W = H = 64

# ────────────────────────────────────────────────────────────────────────
# ICC byte builders (big-endian; layout per ICC.1:2022)
# ────────────────────────────────────────────────────────────────────────

def s15(v):
    return struct.pack(">i", int(round(v * 65536.0)))


def xyz_tag(v):
    return b"XYZ " + b"\0" * 4 + s15(v[0]) + s15(v[1]) + s15(v[2])


def curv_identity():
    return b"curv" + b"\0" * 4 + struct.pack(">I", 0)


def curv_gamma(g):
    return b"curv" + b"\0" * 4 + struct.pack(">I", 1) + struct.pack(">H", int(round(g * 256.0))) + b"\0\0"


def curv_table(samples):
    out = b"curv" + b"\0" * 4 + struct.pack(">I", len(samples))
    for s in samples:
        out += struct.pack(">H", max(0, min(65535, int(round(s * 65535.0)))))
    if len(samples) % 2 == 1:
        out += b"\0\0"
    return out


def mluc(text):
    u = text.encode("utf-16-be")
    return (b"mluc" + b"\0" * 4 + struct.pack(">I", 1) + struct.pack(">I", 12)
            + b"en" + b"US" + struct.pack(">I", len(u)) + struct.pack(">I", 28) + u)


BRADFORD = np.array([
    [0.8951, 0.2664, -0.1614],
    [-0.7502, 1.7135, 0.0367],
    [0.0389, -0.0685, 1.0296]])
BRADFORD_INV = np.linalg.inv(BRADFORD)
D50 = np.array([0.96420288, 1.0, 0.82490539])


def xy_to_xyz(x, y):
    return np.array([x / y, 1.0, (1.0 - x - y) / y])


def chad_from_native_white(wx, wy):
    cone_s = BRADFORD @ xy_to_xyz(wx, wy)
    cone_t = BRADFORD @ D50
    scale = np.diag(cone_t / cone_s)
    return BRADFORD_INV @ scale @ BRADFORD


def mat9(m):
    out = b""
    for r in range(3):
        for c in range(3):
            out += s15(m[r][c])
    return out


def cicp_tag(prim, transfer):
    return b"cicp" + b"\0" * 4 + bytes([prim, transfer, 0, 1])


def mdcv_tag(max_nits, wx=0.3127, wy=0.3290):
    # 3 primaries × (x,y) ×50000 + white (x,y) + maxLum u32 ×10000 + minLum.
    prims = [(0.708, 0.292), (0.170, 0.797), (0.131, 0.046)]
    out = b"mdcv" + b"\0" * 4
    for (x, y) in prims:
        out += struct.pack(">H", int(round(x * 50000)))
        out += struct.pack(">H", int(round(y * 50000)))
    out += struct.pack(">H", int(round(wx * 50000)))
    out += struct.pack(">H", int(round(wy * 50000)))
    out += struct.pack(">I", int(round(max_nits * 10000)))
    out += struct.pack(">I", 1)
    return out


def mft2_identity():
    # LUT16Type A2B0: identity input/output tables + a 2³ identity CLUT —
    # structurally a LUT-based profile (the discriminator's target form).
    grid = 2
    n_in = 256
    out = b"mft2" + b"\0" * 4
    out += struct.pack(">H", n_in)   # input entries
    out += struct.pack(">H", n_in)   # output entries
    out += struct.pack(">H", grid)   # CLUT grid points
    for _ in range(3):               # input tables (identity ramps)
        for i in range(n_in):
            out += struct.pack(">H", i)
    for k in range(grid):            # CLUT: identity at every lattice point
        for j in range(grid):
            for i in range(grid):
                for v in (i, j, k):
                    out += struct.pack(">H", int(round(v / (grid - 1) * 65535)))
    for _ in range(3):               # output tables (identity ramps)
        for i in range(n_in):
            out += struct.pack(">H", i)
    return out


def build_icc(primaries_xy, white_xy, trc_bytes, *, model=b"RGB ",
              with_chad=True, extra_tags=(), only_lut=False, label="Lightamer fixture"):
    """Assemble a minimal v4.3 profile. primaries_xy = (rx,ry,gx,gy,bx,by)."""
    wx, wy = white_xy
    chad = chad_from_native_white(wx, wy)
    native = [xy_to_xyz(primaries_xy[i * 2], primaries_xy[i * 2 + 1]) for i in range(3)]
    pcs = [chad @ n for n in native]
    pcs_white = chad @ xy_to_xyz(wx, wy)

    tags = [("desc", mluc(label))]
    if not only_lut:
        tags.append(("wtpt", xyz_tag(pcs_white)))
        if with_chad:
            tags.append(("chad", b"sf32" + b"\0" * 4 + mat9(chad)))
        names = ["rXYZ", "gXYZ", "bXYZ"]
        for nm, v in zip(names, pcs):
            tags.append((nm, xyz_tag(v)))
        for nm in ("rTRC", "gTRC", "bTRC"):
            tags.append((nm, trc_bytes))
    for t in extra_tags:
        tags.append(t)
    if only_lut:
        tags.append(("A2B0", mft2_identity()))
        tags.append(("wtpt", xyz_tag(pcs_white)))

    tag_table_size = 4 + len(tags) * 12
    entries = []
    payload = b""
    for (name, data) in tags:
        while (128 + tag_table_size + len(payload)) % 4 != 0:
            payload += b"\0"
        entries.append((name.encode("ascii"), 128 + tag_table_size + len(payload), data))
        payload += data
    total = 128 + tag_table_size + len(payload)
    header = struct.pack(">I", total)
    header += struct.pack(">I", 0)           # preferred CMM
    header += struct.pack(">I", 0x04300000)  # v4.3
    header += b"mntr"
    header += model
    header += b"XYZ "
    header += struct.pack(">6H", 2026, 1, 1, 0, 0, 0)
    header += b"acsp"
    header += b"\0" * 28                     # platform/flags/mfg/model/attrs/intent
    header += s15(D50[0]) + s15(D50[1]) + s15(D50[2])
    header += struct.pack(">I", 0)           # creator
    header += b"\0" * 16                     # profile ID
    header += b"\0" * 28                     # reserved
    assert len(header) == 128, len(header)
    out = header + struct.pack(">I", len(tags))
    for (name, off, data) in entries:
        out += name + struct.pack(">II", off, len(data))
    return out + payload


# Chromaticities (x, y).
SRGB = (0.640, 0.330, 0.300, 0.600, 0.150, 0.060)
P3 = (0.680, 0.320, 0.265, 0.690, 0.150, 0.060)
ADOBE = (0.6400, 0.3300, 0.2100, 0.7100, 0.1500, 0.0600)
REC2020 = (0.708, 0.292, 0.170, 0.797, 0.131, 0.046)
PROPHOTO = (0.7347, 0.2653, 0.1596, 0.8404, 0.0366, 0.0001)
D65 = (0.3127, 0.3290)
D50W = (0.3457, 0.3585)

M1, M2, C1, C2, C3 = 2610 / 16384, 2523 / 32, 107 / 128, 2413 / 128, 2392 / 128


def pq_relative(code):
    e = code ** (1 / M2)
    frac = (e - C1) / (C2 - C3 * e)
    return max(0.0, frac ** (1 / M1)) if frac > 0 else 0.0


def pq_table(n=1024):
    return [pq_relative(i / (n - 1)) for i in range(n)]


# ────────────────────────────────────────────────────────────────────────
# Pixel patterns (deterministic; the T6 bit-fidelity probe values live at
# fixed pixels: 0 / 0.18 / 0.5 / 1.0 in the corners, a gradient elsewhere)
# ────────────────────────────────────────────────────────────────────────

def gradient_u8():
    img = np.zeros((H, W, 3), dtype=np.uint8)
    for c in range(3):
        img[:, :, c] = (np.arange(W) * 255 // (W - 1)).astype(np.uint8)[None, :]
    img[0, 0] = (0, 0, 0)
    img[0, 1] = (255, 255, 255)
    img[0, 2] = (46, 46, 46)      # ≈0.18
    img[0, 3] = (128, 128, 128)
    return img


def gradient_u16():
    img = np.zeros((H, W, 3), dtype=np.uint16)
    for c in range(3):
        img[:, :, c] = (np.arange(W) * 65535 // (W - 1)).astype(np.uint16)[None, :]
    img[0, 0] = (0, 0, 0)
    img[0, 1] = (65535, 65535, 65535)
    img[0, 2] = (11797, 11797, 11797)  # ≈0.18
    img[0, 3] = (32768, 32768, 32768)
    return img


def gradient_f32(max_value=1.0):
    img = np.zeros((H, W, 3), dtype=np.float32)
    ramp = (np.arange(W) / (W - 1)).astype(np.float32)
    for c in range(3):
        img[:, :, c] = ramp[None, :] * max_value
    img[0, 0] = (0.0, 0.0, 0.0)
    img[0, 1] = (max_value, max_value, max_value)
    img[0, 2] = (0.18 * max_value,) * 3
    img[0, 3] = (0.5 * max_value,) * 3
    return img


def write_tiff(name, data, icc=None, photometric="rgb", extrasamples=None,
               planarconfig=None):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    extratags = None
    if icc is not None:
        extratags = [(34675, 7, len(icc), icc, True)]
    kwargs = dict(photometric=photometric, metadata=None)
    if extratags:
        kwargs["extratags"] = extratags
    if extrasamples:
        kwargs["extrasamples"] = extrasamples
    if planarconfig:
        kwargs["planarconfig"] = planarconfig
    tifffile.imwrite(path, data, **kwargs)
    return path


def main():
    os.makedirs(OUT, exist_ok=True)
    written = []

    srgb_icc = build_icc(SRGB, D65, curv_gamma(2.19921875), label="Fixture sRGB")
    p3_icc = build_icc(P3, D65, curv_gamma(2.19921875), label="Fixture Display P3")
    adobe_icc = build_icc(ADOBE, D65, curv_gamma(2.19921875), label="Fixture AdobeRGB")
    rec2020_icc = build_icc(REC2020, D65, curv_gamma(2.19921875), label="Fixture Rec2020")
    prophoto_icc = build_icc(PROPHOTO, D50W, curv_gamma(2.19921875), label="Fixture ProPhoto")
    linear_rec2020_icc = build_icc(REC2020, D65, curv_identity(), label="Fixture Linear Rec2020")
    pq_table_icc = build_icc(
        REC2020, D65, curv_table(pq_table()),
        extra_tags=[("mdcv", mdcv_tag(4000.0))], label="Fixture PQ table")
    pq_cicp_icc = build_icc(
        REC2020, D65, curv_gamma(2.19921875),
        extra_tags=[("cicp", cicp_tag(9, 16))], label="Fixture PQ cicp")
    hlg_cicp_icc = build_icc(
        REC2020, D65, curv_gamma(2.19921875),
        extra_tags=[("cicp", cicp_tag(9, 18))], label="Fixture HLG cicp")
    dual_tag_icc = build_icc(
        SRGB, D65, curv_gamma(2.19921875),
        extra_tags=[("A2B0", mft2_identity())], label="Fixture dual-tag")
    lut_only_icc = build_icc(
        SRGB, D65, curv_gamma(2.19921875), only_lut=True, label="Fixture LUT A2B0")
    degenerate_icc = build_icc(
        SRGB, D65, curv_gamma(2.19921875), label="Fixture degenerate")
    # Degenerate: overwrite bXYZ with rXYZ's bytes (zero-area triangle).
    degenerate_icc = bytearray(degenerate_icc)
    tag_count = struct.unpack(">I", degenerate_icc[128:132])[0]
    rxyz_off = bxyz_off = None
    for i in range(tag_count):
        entry = 132 + i * 12
        sig = bytes(degenerate_icc[entry:entry + 4])
        if sig == b"rXYZ":
            rxyz_off = struct.unpack(">I", degenerate_icc[entry + 4:entry + 8])[0]
        if sig == b"bXYZ":
            bxyz_off = struct.unpack(">I", degenerate_icc[entry + 4:entry + 8])[0]
    degenerate_icc[bxyz_off:bxyz_off + 20] = degenerate_icc[rxyz_off:rxyz_off + 20]
    degenerate_icc = bytes(degenerate_icc)

    # ── the bit-depth × ICC main matrix ──
    write_tiff("srgb-matrix-8.tif", gradient_u8(), icc=srgb_icc)
    write_tiff("srgb-matrix-16.tif", gradient_u16(), icc=srgb_icc)
    write_tiff("srgb-matrix-32f.tif", gradient_f32(1.0), icc=srgb_icc)
    write_tiff("p3-matrix-16.tif", gradient_u16(), icc=p3_icc)
    write_tiff("adobergb-matrix-16.tif", gradient_u16(), icc=adobe_icc)
    write_tiff("rec2020-matrix-16.tif", gradient_u16(), icc=rec2020_icc)
    write_tiff("prophoto-matrix-16.tif", gradient_u16(), icc=prophoto_icc)
    written += [
        "srgb-matrix-8.tif", "srgb-matrix-16.tif", "srgb-matrix-32f.tif",
        "p3-matrix-16.tif", "adobergb-matrix-16.tif", "rec2020-matrix-16.tif",
        "prophoto-matrix-16.tif"]

    # ── ICC form specials ──
    write_tiff("lut-a2b0-8.tif", gradient_u8(), icc=lut_only_icc)
    write_tiff("dual-tag-matrix-a2b0-16.tif", gradient_u16(), icc=dual_tag_icc)
    write_tiff("pq-sampled-table-16.tif", gradient_u16(), icc=pq_table_icc)
    write_tiff("pq-cicp-16.tif", gradient_u16(), icc=pq_cicp_icc)
    write_tiff("hlg-cicp-16.tif", gradient_u16(), icc=hlg_cicp_icc)
    write_tiff("degenerate-primaries-8.tif", gradient_u8(), icc=degenerate_icc)
    written += [
        "lut-a2b0-8.tif", "dual-tag-matrix-a2b0-16.tif",
        "pq-sampled-table-16.tif", "pq-cicp-16.tif", "hlg-cicp-16.tif",
        "degenerate-primaries-8.tif"]

    # ── no-ICC defaults ──
    write_tiff("no-icc-8.tif", gradient_u8())
    write_tiff("no-icc-16.tif", gradient_u16())
    write_tiff("no-icc-float32.tif", gradient_f32(2.0))  # >1.0 content: HDR probe
    write_tiff("linear-icc-float32.tif", gradient_f32(1.0), icc=linear_rec2020_icc)
    written += ["no-icc-8.tif", "no-icc-16.tif", "no-icc-float32.tif",
                "linear-icc-float32.tif"]

    # ── shape specials ──
    # Multi-page (two pages; the decoder takes page 0).
    p0, p1 = gradient_u16(), gradient_u16()[:, ::-1]
    tifffile.imwrite(os.path.join(OUT, "multipage-16.tif"), np.stack([p0, p1]),
                     photometric="rgb", metadata=None)
    # Gray + gray ICC (GRAY model: data colorspace 'GRAY', one kTRC).
    gray_icc = build_icc(SRGB, D65, curv_gamma(2.19921875), model=b"GRAY",
                         label="Fixture Gray")
    # The GRAY model carries no rXYZ/gXYZ/bXYZ — strip the matrix tags.
    gray_icc = _strip_gray(gray_icc)
    gray = np.zeros((H, W), dtype=np.uint8)
    gray[:, :] = (np.arange(W) * 255 // (W - 1)).astype(np.uint8)[None, :]
    write_tiff("gray-icc-8.tif", gray, icc=gray_icc, photometric="minisblack")
    # Alpha (RGBA) — the decoder discards it.
    rgba = np.dstack([gradient_u8(), np.full((H, W), 128, dtype=np.uint8)])
    write_tiff("alpha-8.tif", rgba, icc=srgb_icc, extrasamples=["assocalpha"])
    # CMYK — the typed-reject fixture.
    cmyk = np.zeros((H, W, 4), dtype=np.uint8)
    for c in range(4):
        cmyk[:, :, c] = (np.arange(W) * 255 // (W - 1)).astype(np.uint8)[None, :]
    write_tiff("cmyk-8.tif", cmyk, photometric="separated")
    written += ["multipage-16.tif", "gray-icc-8.tif", "alpha-8.tif", "cmyk-8.tif"]

    with open(os.path.join(OUT, "MANIFEST.txt"), "w") as f:
        f.write("\n".join(sorted(written)) + "\n")
    print(f"wrote {len(written) + 1} files to {OUT}")


def _strip_gray(icc):
    """Remove the RGB matrix tags from a GRAY-model profile (the GRAY model
    carries wtpt + kTRC only)."""
    buf = bytearray(icc)
    count = struct.unpack(">I", buf[128:132])[0]
    keep = []
    trc_payload = None
    for i in range(count):
        entry = 132 + i * 12
        sig = bytes(buf[entry:entry + 4])
        off = struct.unpack(">I", buf[entry + 4:entry + 8])[0]
        size = struct.unpack(">I", buf[entry + 8:entry + 12])[0]
        if sig in (b"rXYZ", b"gXYZ", b"bXYZ"):
            continue
        if sig == b"rTRC":
            trc_payload = bytes(buf[off:off + size])  # becomes kTRC below
            continue
        if sig in (b"gTRC", b"bTRC"):
            continue
        keep.append((sig, off, size))
    if trc_payload is not None:
        keep.append((b"kTRC", 0, trc_payload))  # (sig, unused-offset, payload)
    # Rebuild the payload region: copy live tag payloads in keep order.
    payload_start = 132 + count * 12
    payloads = b""
    new_entries = []
    for (sig, off, size) in keep:
        if sig == b"kTRC":
            payload = size          # the renamed rTRC payload rides inline
        else:
            payload = bytes(buf[off:off + size])
        while (128 + 4 + len(keep) * 12 + len(payloads)) % 4 != 0:
            payloads += b"\0"
        new_entries.append((sig, 128 + 4 + len(keep) * 12 + len(payloads), payload))
        payloads += payload
    total = 128 + 4 + len(keep) * 12 + len(payloads)
    header = bytearray(buf[:128])
    header[0:4] = struct.pack(">I", total)
    out = bytes(header) + struct.pack(">I", len(keep))
    for (sig, off, data) in new_entries:
        out += sig + struct.pack(">II", off, len(data))
    return out + payloads


if __name__ == "__main__":
    main()

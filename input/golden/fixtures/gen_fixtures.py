#!/usr/bin/env python3
"""
Lightamer golden fixture generator (Phase 3, Plan 03-01-T2).

Produces the synthetic scene-linear EXR fixture set + the pinned-parameter
XMP cases consumed by `regenerate.sh` (dt-cli golden reference generation)
and by `Tests/LightamerTests/GoldenParityTests.swift` (track A parity).

PURE STDLIB — no numpy/OpenEXR dependency (the plan's uv fallback exists,
but a zero-dep writer cannot break on a machine without network).

EXR output: uncompressed scanline float32 RGB, channels in alphabetical
order (B, G, R) per the OpenEXR spec. Written WITHOUT chromaticities →
darktable reads it as linear Rec709 (imageio_exr.cc:273-275); the
`regenerate.sh` round-trip step (`--out-ext exr --icc-type LIN_REC2020`)
then produces the Rec2020-canonical fixture (values converted + attributes
marked) — RESEARCH §6.1.

Fixture set (RESEARCH §Validation Architecture #2):
  1. ramp_8ev      — 64×64 gray ramp −8..0EV (tone 主靶; +1EV case maps
                     0.25 → 0.5, the XMP-attach acceptance probe)
  2. flat_0ev / flat_-4ev / flat_-8ev — uniform grays (平场)
  3. saturated     — Rec2020 R,G,B,C,M,Y 100% + out-of-Rec2020 spectral
                     blocks (gamut 映射靶)
  4. deep_shadow   — 0..2^-6 fine gradient (banding 靶, METAL-2)
  5. gray_staircase— 12 neutral steps 0.02..1.0 (WB 吸管靶)
  6. stair_1d      — 10001-point 1D staircase (曲线 LUT 靶)

XMP cases (Plan 03-01-T2/T6 — exposure 钉参组): +1EV / −2EV / black=0.1 /
compensate 组合. The params blob is the little-endian direct pack of
`dt_iop_exposure_params_t` v7 = `<iffffii` (28 bytes), serialized as
lowercase HEX ASCII (the dt XMP encoding for uncompressed blobs — see
`exposure_params_blob`; base64 is only used behind the "gz" compressed
prefix). The dt↔Lightamer field mapping table lives in
manifest.md (RESEARCH Risk #5).

Usage:
  gen_fixtures.py raw   [OUTDIR]   # raw (pre-canonicalization) EXRs
  gen_fixtures.py cases [OUTDIR]   # pinned XMP cases
  gen_fixtures.py all   [OUTDIR]   # both (default OUTDIR = script dir)
Deterministic: same inputs → byte-identical outputs (manifest hashes hold).
"""

import base64
import binascii
import math
import os
import struct
import sys

# ──────────────────────────────────────────────────────────────────────
# Minimal EXR writer (uncompressed scanline float32 RGB)
# ──────────────────────────────────────────────────────────────────────

EXR_MAGIC = 20000630  # 0x01312f76
PIXEL_FLOAT = 2


def _attr(name: str, type_name: str, data: bytes) -> bytes:
    return (
        name.encode() + b"\0"
        + type_name.encode() + b"\0"
        + struct.pack("<i", len(data))
        + data
    )


def _chlist() -> bytes:
    # Alphabetical channel order (spec requirement); R=G=B grays make the
    # layout irrelevant for gray fixtures, but keep it correct anyway.
    body = b""
    for name in ("B", "G", "R"):
        body += (
            name.encode() + b"\0"
            + struct.pack("<i", PIXEL_FLOAT)  # pixel type: float32
            + struct.pack("<B", 0)            # pLinear
            + b"\0\0\0"                       # reserved
            + struct.pack("<i", 1)            # xSampling
            + struct.pack("<i", 1)            # ySampling
        )
    return body + b"\0"


def write_exr(path: str, width: int, height: int, pixel_fn) -> None:
    """Write an uncompressed scanline float32 RGB EXR.

    `pixel_fn(x, y)` returns the (R, G, B) float triple for pixel (x, y),
    x = column, y = row (top-left origin, scanlines written top-down,
    lineOrder = INCREASING_Y).
    """
    data_window = (0, 0, width - 1, height - 1)

    header = b""
    header += _attr("channels", "chlist", _chlist())
    header += _attr("compression", "compression", struct.pack("<B", 0))  # NONE
    header += _attr("dataWindow", "box2i", struct.pack("<4i", *data_window))
    header += _attr("displayWindow", "box2i", struct.pack("<4i", *data_window))
    header += _attr("lineOrder", "lineOrder", struct.pack("<B", 0))  # INCREASING_Y
    header += _attr("pixelAspectRatio", "float", struct.pack("<f", 1.0))
    header += _attr("screenWindowCenter", "v2f", struct.pack("<2f", 0.0, 0.0))
    header += _attr("screenWindowWidth", "float", struct.pack("<f", 1.0))
    header += b"\0"

    row_bytes = width * 3 * 4
    chunk_size = 4 + 4 + row_bytes

    # Offset table: one entry per scanline block (uncompressed = 1 line/chunk).
    # File prefix = magic(4) + version(4) + header — the 8 leading bytes MUST
    # be counted (2026-09-19: omitting them shifted every chunk −8B; both
    # libopenexr and dt still parsed the file into clean-looking garbage).
    offsets = b""
    offset = 8 + len(header) + 8 * height
    for _ in range(height):
        offsets += struct.pack("<Q", offset)
        offset += chunk_size

    lines = b""
    for y in range(height):
        lines += struct.pack("<i", y) + struct.pack("<i", row_bytes)
        row = bytearray(row_bytes)
        for x in range(width):
            r, g, b = pixel_fn(x, y)
            base = x * 12
            row[base:base + 4] = struct.pack("<f", b)   # chlist order: B, G, R
            row[base + 4:base + 8] = struct.pack("<f", g)
            row[base + 8:base + 12] = struct.pack("<f", r)
        lines += bytes(row)

    with open(path, "wb") as f:
        f.write(struct.pack("<I", EXR_MAGIC))
        f.write(struct.pack("<I", 2))  # version: scanline, single part
        f.write(header)
        f.write(offsets)
        f.write(lines)


# ──────────────────────────────────────────────────────────────────────
# Color matrices (scene-linear RGB domain)
# ──────────────────────────────────────────────────────────────────────

def mat_mul(a, b):
    return [
        [
            sum(a[i][k] * b[k][j] for k in range(3))
            for j in range(3)
        ]
        for i in range(3)
    ]


def mat_vec(m, v):
    return tuple(sum(m[i][k] * v[k] for k in range(3)) for i in range(3))


def mat_inv(m):
    det = (
        m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
        - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
        + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
    )
    return [
        [
            (m[(j + 1) % 3][(i + 1) % 3] * m[(j + 2) % 3][(i + 2) % 3]
             - m[(j + 1) % 3][(i + 2) % 3] * m[(j + 2) % 3][(i + 1) % 3]) / det
            for j in range(3)
        ]
        for i in range(3)
    ]


# Linear Rec2020 → XYZ (D65) and back — standard primaries/white point.
REC2020_TO_XYZ = [
    [0.636958, 0.144617, 0.168881],
    [0.262700, 0.678009, 0.059291],
    [0.000000, 0.028073, 1.060806],
]
XYZ_TO_REC2020 = mat_inv(REC2020_TO_XYZ)

# Linear Rec709 → XYZ (D65).
REC709_TO_XYZ = [
    [0.4123908, 0.3575843, 0.1804808],
    [0.2126390, 0.7151687, 0.0721923],
    [0.0193308, 0.1191948, 0.9505322],
]
XYZ_TO_REC709 = mat_inv(REC709_TO_XYZ)

# Linear Rec709 → Rec2020: the raw fixtures are read by dt as linear
# Rec709; to land on a Rec2020 target T after the canonicalization
# round-trip, the fixture must hold M(709→2020)^-1 · T.
REC709_TO_REC2020 = mat_mul(REC709_TO_XYZ, XYZ_TO_REC2020)  # 709→XYZ→2020
REC2020_TO_REC709 = mat_inv(REC709_TO_REC2020)


def clamp01(v):
    return max(0.0, min(1.0, v))


# ──────────────────────────────────────────────────────────────────────
# Fixture builders
# ──────────────────────────────────────────────────────────────────────

def ev_value(ev: float) -> float:
    """Scene-linear value of an EV offset relative to 0.5 mid-gray."""
    return 0.5 * (2.0 ** ev)


def gen_ramp(outdir: str) -> None:
    # 64 columns spanning −8..−0.125EV with POWER-OF-TWO-EXACT stops every
    # 8 columns (v(x) = 2^(−8 + x/8)): column 48 = 0.25 exactly, column 56
    # = 0.5 — the XMP-attach acceptance probe (+1EV maps 0.25 → 0.5 ±1e-6)
    # and half-float-safe values throughout.
    def px(x, y):
        v = 2.0 ** (-8.0 + x / 8.0)
        return (v, v, v)

    write_exr(os.path.join(outdir, "ramp_8ev.exr"), 64, 64, px)


def gen_flats(outdir: str) -> None:
    for name, ev in (("flat_0ev", 0.0), ("flat_-4ev", -4.0), ("flat_-8ev", -8.0)):
        v = ev_value(ev)
        write_exr(
            os.path.join(outdir, name + ".exr"), 64, 64,
            lambda x, y, v=v: (v, v, v),
        )


# Saturated blocks: Rec2020 primaries + secondaries at 100%, plus
# out-of-Rec2020 spectral colors (CIE 1931 2° xy at 10nm grid).
def gen_saturated(outdir: str) -> None:
    # Targets are LINEAR REC2020 values; pre-convert to the Rec709 domain
    # dt will assume when reading the raw fixture (see header note).
    targets_2020 = [
        ("R2020", (1.0, 0.0, 0.0)),
        ("G2020", (0.0, 1.0, 0.0)),
        ("B2020", (0.0, 0.0, 1.0)),
        ("C2020", (0.0, 1.0, 1.0)),
        ("M2020", (1.0, 0.0, 1.0)),
        ("Y2020", (1.0, 1.0, 0.0)),
    ]
    # Spectral xy (CIE 1931 2°, 10nm grid) — Y-normalized XYZ → Rec2020;
    # these carry negative/out-of-gamut components by design.
    spectral_xy = [
        ("spec500", (0.0082, 0.5384)),   # green spectral, far out of Rec2020
        ("spec520", (0.0743, 0.8338)),   # green-yellow spectral, out
        ("spec580", (0.5125, 0.4866)),   # yellow-orange spectral, out
        ("spec600", (0.6270, 0.3725)),   # orange spectral, marginally out
    ]
    for name, xy in spectral_xy:
        x, y = xy
        xyz = (x / y, 1.0, (1.0 - x - y) / y)
        targets_2020.append((name, mat_vec(XYZ_TO_REC2020, xyz)))

    # 10 blocks in a 5×2 grid on 100×64.
    width, height = 100, 64
    block_w = width / len(targets_2020)

    def px(x, y):
        idx = min(int(x / block_w), len(targets_2020) - 1)
        _, t2020 = targets_2020[idx]
        # Pre-image in the Rec709 domain (round-trip lands on t2020).
        pre = mat_vec(REC2020_TO_REC709, t2020)
        return pre

    write_exr(os.path.join(outdir, "saturated.exr"), width, height, px)


def gen_deep_shadow(outdir: str) -> None:
    # Fine gradient 0 → 2^-6 across the whole 64×64 (banding 靶).
    width = height = 64
    count = width * height

    def px(x, y):
        v = 2.0 ** -6 * (y * width + x) / (count - 1)
        return (v, v, v)

    write_exr(os.path.join(outdir, "deep_shadow.exr"), width, height, px)


def gen_gray_staircase(outdir: str) -> None:
    # 12 neutral steps, geometric-ish spread (WB 吸管靶).
    levels = [0.02, 0.04, 0.07, 0.10, 0.18, 0.25, 0.35, 0.50, 0.65, 0.80, 0.90, 1.00]
    width = height = 120  # 10px per block

    def px(x, y):
        idx = min(int(x / (width / len(levels))), len(levels) - 1)
        v = levels[idx]
        return (v, v, v)

    write_exr(os.path.join(outdir, "gray_staircase.exr"), width, height, px)


def gen_stair_1d(outdir: str) -> None:
    # 10001-point 1D staircase (曲线 LUT 靶): W = 10001, H = 2.
    points = 10001

    def px(x, y):
        v = x / (points - 1)
        return (v, v, v)

    write_exr(os.path.join(outdir, "stair_1d.exr"), points, 2, px)


# ──────────────────────────────────────────────────────────────────────
# XMP pinned-parameter cases (exposure 钉参组 + temperature 钉参组)
# ──────────────────────────────────────────────────────────────────────

EXPOSURE_PARAMS_FORMAT = "<iffffii"  # dt_iop_exposure_params_t v7, 28 bytes
EXPOSURE_MODVERSION = 7
EXPOSURE_IOP_ORDER = 21.0  # v50 slot; entry iop_order for the XMP
XMP_VERSION = 5

# dt_iop_temperature_params_t v4, 20 bytes: red/green/blue/various (f) +
# preset (int). `various` is the CYGM 4th channel — Lightamer does not port
# it (RGB pipe), golden blobs pin 1.0 so the alpha/CYGM semantics are inert.
TEMPERATURE_PARAMS_FORMAT = "<ffffi"
TEMPERATURE_MODVERSION = 4
TEMPERATURE_IOP_ORDER = 3.0  # v50 slot

# dt DT_IOP_TEMP_* raw values (temperature.c:56-62)
DT_IOP_TEMP_AS_SHOT = 0
DT_IOP_TEMP_SPOT = 1
DT_IOP_TEMP_USER = 2
DT_IOP_TEMP_D65 = 3


def exposure_params_blob(
    exposure: float,
    black: float = 0.0,
    compensate_exposure_bias: int = 0,
    mode: int = 0,
    deflicker_percentile: float = 50.0,
    deflicker_target_level: float = -4.0,
    compensate_hilite_pres: int = 1,
) -> str:
    """dt_iop_exposure_params_t v7 → lowercase HEX ASCII (2 chars/byte).

    XMP blob encoding (dt_exif_xmp_encode_internal, exif.cc:3292-3311):
    uncompressed params are HEX ASCII — NOT base64. Base64 appears ONLY in
    the compressed form ("gz" + 2-digit factor + base64, used when the
    encoded blob exceeds the compression threshold). The decoder
    (dt_exif_xmp_decode, exif.cc:3317+) dispatches on the "gz" prefix and
    otherwise expects hex — a base64 blob decodes to a garbage length and
    the history loader marks it "params WRONG" → dt silently falls back to
    default params (the exact failure that plan 03-01-T1 exists to catch).
    """
    packed = struct.pack(
        EXPOSURE_PARAMS_FORMAT,
        mode,
        black,
        exposure,
        deflicker_percentile,
        deflicker_target_level,
        compensate_exposure_bias,
        compensate_hilite_pres,
    )
    assert len(packed) == 28, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def temperature_params_blob(
    red: float,
    green: float,
    blue: float,
    preset: int = DT_IOP_TEMP_USER,
    various: float = 1.0,
) -> str:
    """dt_iop_temperature_params_t v4 → lowercase HEX ASCII (20 bytes).

    Plan 03-02-T2: the Kelvin→gain MODEL diverges between dt (sensor-domain
    XYZ_to_CAM) and Lightamer (Rec2020-native, post-CIRAW correction layer —
    RESEARCH §5), so the golden cases pin the THREE CHANNEL GAINS directly:
    the per-pixel `rgb × coeffs` apply is both sides' shared, fully
    determined semantic (whitebalance_4f). The Kelvin conversion itself is
    locked by CPUDerivationTests against the C reference harness instead.
    """
    packed = struct.pack(
        TEMPERATURE_PARAMS_FORMAT,
        red,
        green,
        blue,
        various,
        preset,
    )
    assert len(packed) == 20, len(packed)
    return binascii.hexlify(packed).decode("ascii")


XMP_TEMPLATE = """<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Lightamer golden fixture gen">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:darktable="http://darktable.sf.net/"
    darktable:xmp_version="{xmp_version}"
    darktable:raw_params="0"
    darktable:auto_presets_applied="1"
    darktable:history_end="1">
   <darktable:iop_order_version>{iop_order_version}</darktable:iop_order_version>
   <darktable:history>
    <rdf:Seq>
     <rdf:li rdf:parseType="Resource">
      <darktable:num>0</darktable:num>
      <darktable:module>3</darktable:module>
      <darktable:operation>{operation}</darktable:operation>
      <darktable:enabled>1</darktable:enabled>
      <darktable:modversion>{modversion}</darktable:modversion>
      <darktable:params>{params}</darktable:params>
      <darktable:iop_order>{iop_order}</darktable:iop_order>
      <darktable:multi_priority>0</darktable:multi_priority>
      <darktable:multi_name></darktable:multi_name>
     </rdf:li>
    </rdf:Seq>
   </darktable:history>
   <darktable:history_enabled>
    <rdf:Seq><rdf:li>1</rdf:li></rdf:Seq>
   </darktable:history_enabled>
   <darktable:history_modversion>
    <rdf:Seq><rdf:li>{modversion}</rdf:li></rdf:Seq>
   </darktable:history_modversion>
   <darktable:history_operation>
    <rdf:Seq><rdf:li>{operation}</rdf:li></rdf:Seq>
   </darktable:history_operation>
   <darktable:history_params>
    <rdf:Seq><rdf:li>{params}</rdf:li></rdf:Seq>
   </darktable:history_params>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
<?xpacket end="w"?>
"""


# The exposure 钉参组 (Plan 03-01-T2 action 3 / T6). Field mapping to the
# Lightamer ExposureModule.Params lives in manifest.md (Risk #5).
EXPOSURE_CASES = [
    # (case name, exposure EV, black, compensate_exposure_bias)
    ("exposure_plus1ev", 1.0, 0.0, 0),
    ("exposure_minus2ev", -2.0, 0.0, 0),
    ("exposure_black01", 0.0, 0.1, 0),
    ("exposure_combo", 0.5, -0.02, 1),  # compensate 组合: bias bit set, EXIF bias = 0 on EXR
]

# The temperature 钉参组 (Plan 03-02-T2 action 4): three-channel GAINS pinned
# directly (RESEARCH §5 — bypasses the Kelvin model domain divergence). The
# identity case doubles as an XMP-attach probe for the v4 blob layout.
TEMPERATURE_CASES = [
    # (case name, red, green, blue, preset)
    ("temperature_default", 1.0, 1.0, 1.0, DT_IOP_TEMP_AS_SHOT),
    ("temperature_r120_b080", 1.2, 1.0, 0.8, DT_IOP_TEMP_USER),
    ("temperature_r070_b140", 0.7, 1.0, 1.4, DT_IOP_TEMP_USER),
    ("temperature_spot_warm", 1.35, 1.0, 0.77, DT_IOP_TEMP_SPOT),
]


def gen_cases(outdir: str) -> None:
    os.makedirs(outdir, exist_ok=True)
    for name, ev, black, comp in EXPOSURE_CASES:
        params = exposure_params_blob(exposure=ev, black=black, compensate_exposure_bias=comp)
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION,
            iop_order_version=5,
            operation="exposure",
            modversion=EXPOSURE_MODVERSION,
            params=params,
            iop_order=f"{EXPOSURE_IOP_ORDER:.1f}",
        )
        with open(os.path.join(outdir, name + ".xmp"), "w") as f:
            f.write(xmp)
    for name, red, green, blue, preset in TEMPERATURE_CASES:
        params = temperature_params_blob(red=red, green=green, blue=blue, preset=preset)
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION,
            iop_order_version=5,
            operation="temperature",
            modversion=TEMPERATURE_MODVERSION,
            params=params,
            iop_order=f"{TEMPERATURE_IOP_ORDER:.1f}",
        )
        with open(os.path.join(outdir, name + ".xmp"), "w") as f:
            f.write(xmp)
    for name, c, b, s in COLISA_CASES:
        params = colisa_params_blob(c, b, s)
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION,
            iop_order_version=5,
            operation="colisa",
            modversion=COLISA_MODVERSION,
            params=params,
            iop_order=f"{COLISA_IOP_ORDER:.1f}",
        )
        with open(os.path.join(outdir, name + ".xmp"), "w") as f:
            f.write(xmp)
    for case in SHADHI_CASES:
        params = shadhi_params_blob(case)
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION,
            iop_order_version=5,
            operation="shadhi",
            modversion=SHADHI_MODVERSION,
            params=params,
            iop_order=f"{SHADHI_IOP_ORDER:.1f}",
        )
        with open(os.path.join(outdir, case["name"] + ".xmp"), "w") as f:
            f.write(xmp)
    for case in SIGMOID_CASES:
        params = sigmoid_params_blob(case)
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION,
            iop_order_version=5,
            operation="sigmoid",
            modversion=SIGMOID_MODVERSION,
            params=params,
            iop_order=f"{SIGMOID_IOP_ORDER:.2f}",
        )
        with open(os.path.join(outdir, case["name"] + ".xmp"), "w") as f:
            f.write(xmp)
    gen_tonecurve_cases(outdir)


# ──────────────────────────────────────────────────────────────────────
# Minimal EXR reader — the canonical fixtures are dt-roundtripped
# uncompressed float32 scanline files (regenerate.sh pins the writer conf).
# Used by `gen_temperature_refs` to synthesize the temperature golden
# references from the EXACT canonical fixture values.
# ──────────────────────────────────────────────────────────────────────

def read_exr_rgb(path):
    """Read an uncompressed float32 scanline RGB(A) EXR → (w, h, rgb list)."""
    data = open(path, "rb").read()
    if struct.unpack("<I", data[:4])[0] != EXR_MAGIC:
        raise ValueError(f"{path}: not an EXR")
    if struct.unpack("<I", data[4:8])[0] & 0xFF != 2:
        raise ValueError(f"{path}: not scanline")
    pos = 8
    channels = []  # chlist order
    compression = None
    dw = None
    while data[pos] != 0:
        e = data.index(b"\0", pos); name = data[pos:e].decode(); pos = e + 1
        e = data.index(b"\0", pos); typ = data[pos:e].decode(); pos = e + 1
        size = struct.unpack("<i", data[pos:pos + 4])[0]; pos += 4
        val = data[pos:pos + size]; pos += size
        if (name, typ) == ("channels", "chlist"):
            p = 0
            while val[p] != 0:
                e2 = val.index(b"\0", p); n = val[p:e2].decode(); p = e2 + 1
                pt = struct.unpack("<i", val[p:p + 4])[0]; p += 4 + 1 + 3 + 8
                channels.append((n, pt))
        elif (name, typ) == ("compression", "compression"):
            compression = val[0]
        elif (name, typ) == ("dataWindow", "box2i"):
            dw = struct.unpack("<4i", val)
    if compression != 0:
        raise ValueError(f"{path}: compression={compression} — regenerate with the pinned conf")
    pos += 1
    w = dw[2] - dw[0] + 1
    h = dw[3] - dw[1] + 1
    offsets = [struct.unpack("<Q", data[pos + i * 8:pos + i * 8 + 8])[0] for i in range(h)]
    planes = {n: [] for n, _ in channels}
    for off in offsets:
        sz = struct.unpack("<i", data[off + 4:off + 8])[0]
        row = data[off + 8:off + 8 + sz]
        nch = len(channels)
        for ci, (n, _) in enumerate(channels):
            vals = [
                struct.unpack("<f", row[(x * nch + ci) * 4:(x * nch + ci) * 4 + 4])[0]
                for x in range(w)
            ]
            planes[n].extend(vals)
    return w, h, [planes["R"], planes["G"], planes["B"]]


# Fixtures the temperature references cover (gray 系 — RESEARCH §5 track A
# scope; color-sensitive fixtures belong to the filmic/gamut plan 03-06).
TEMPERATURE_REF_FIXTURES = [
    "ramp_8ev", "flat_0ev", "flat_-4ev", "flat_-8ev", "gray_staircase",
]


def gen_temperature_refs(canonical_dir: str, out_dir: str) -> None:
    """Synthesize the temperature golden REFERENCES: canonical fixture ×
    pinned gains, float64 math, written with this script's proven EXR
    writer.

    WHY SYNTHESIZED (Plan 03-02 host finding): darktable-cli in this build
    environment (macOS 27 / Apple clang / libomp / M4) emits spatially
    corrupted pixel data for SPATIALLY-VARYING images through its float
    export writers (EXR: channel-plane mislayout; PFM/TIFF: horizontal
    smear), while uniform images export exactly. The temperature SEMANTIC
    (out.rgb = in.rgb × gains, `whitebalance_4f`) is a per-channel multiply
    with no algorithmic freedom; dt's adoption of the pinned params is
    verified via the library DB (`op_params` hex) + `--core -d params`, and
    dt's per-pixel semantic is probed on the UNIFORM fixtures where its
    export is trustworthy (regenerate.sh step ③b, PFM probes). The
    synthesized reference is the exact float64 evaluation of the shared
    semantic over the same canonical fixture bytes both sides consume.
    """
    os.makedirs(out_dir, exist_ok=True)
    for case_name, red, green, blue, _preset in TEMPERATURE_CASES:
        for fixture in TEMPERATURE_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)
            gains = (red, green, blue)

            def px(x, y, rgb=rgb, gains=gains, w=w):
                idx = y * w + x
                return (
                    rgb[0][idx] * gains[0],
                    rgb[1][idx] * gains[1],
                    rgb[2][idx] * gains[2],
                )

            write_exr(os.path.join(out_dir, f"{case_name}__{fixture}.exr"), w, h, px)


# ──────────────────────────────────────────────────────────────────────
# Lab-domain reference math (Plan 03-03-T1/T2) — the float64 mirror of
# LightamerIOP/Sources/Common/LabMath.h + LabRoundTrip.swift, used by the
# `refs` mode to synthesize the colisa/tonecurve/levels golden references
# (L017 protocol: dt-cli float export is spatially corrupt on this host,
# so track-A references are SYNTHESIZED from the documented shared
# semantic; dt's side is pinned by uniform-flat PFM probes + XMP
# adoption).
#
# Index-quantization discipline: the Lightamer kernels look LUTs up with
# dt's NEAREST truncation (`lut[int(x*0x10000)]`). The reference
# quantizes every value that FEEDS AN INDEX to float32 (f32) — matching
# the GPU's float32 pipeline grid — while keeping smooth quantities in
# float64. This keeps residual disagreement at the int-truncation
# boundaries below ~1e-5 probability per pixel (absorbed by the parity
# tests' dual gate: ≥99.9% of samples < 1e-5 relative, ALL samples
# within a 2e-4 LUT-LSB envelope).
# ──────────────────────────────────────────────────────────────────────

def f32(x):
    """Round a Python float to the float32 grid (GPU/storage semantics)."""
    return struct.unpack("<f", struct.pack("<f", x))[0]


LAB_R2X = [[0.636958, 0.144617, 0.168881],
           [0.262700, 0.678009, 0.059291],
           [0.000000, 0.028073, 1.060806]]
LAB_X2R = mat_inv(LAB_R2X)
LAB_B = [[1.0478112, 0.0228866, -0.0501270],
         [0.0295424, 0.9904844, -0.0170491],
         [-0.0092345, 0.0150436, 0.7521316]]
LAB_BINV = mat_inv(LAB_B)
# Lab reference white = bradford × rec2020ToXYZ × (1,1,1) — neutrals map
# to a==b==0 exactly (LabMath.h anchoring decision).
LAB_WHITE = mat_vec(LAB_B, mat_vec(LAB_R2X, (1.0, 1.0, 1.0)))
LAB_EPS = 216.0 / 24389.0
LAB_KAPPA = 24389.0 / 27.0


def _lab_f(t):
    # dt shape: cbrt above ε, linear below (signed — negatives defined).
    return t ** (1.0 / 3.0) if t > LAB_EPS else (LAB_KAPPA * t + 16.0) / 116.0


def _lab_f_inv(x):
    return x * x * x if x > 0.20689655172413796 else (116.0 * x - 16.0) / LAB_KAPPA


def lab_from_rec2020(rgb):
    x = mat_vec(LAB_B, mat_vec(LAB_R2X, rgb))
    fx = _lab_f(x[0] / LAB_WHITE[0])
    fy = _lab_f(x[1] / LAB_WHITE[1])
    fz = _lab_f(x[2] / LAB_WHITE[2])
    return (116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


def lab_to_rec2020(lab):
    fy = (lab[0] + 16.0) / 116.0
    fx = fy + lab[1] / 500.0
    fz = fy - lab[2] / 200.0
    xyz50 = (
        LAB_WHITE[0] * _lab_f_inv(fx),
        LAB_WHITE[1] * _lab_f_inv(fy),
        LAB_WHITE[2] * _lab_f_inv(fz),
    )
    return mat_vec(LAB_X2R, mat_vec(LAB_BINV, xyz50))


def dt_estimate_exp(xs, ys):
    """dt_iop_estimate_exp (develop/imageop_math.h:98) — coeff (1/x0, y0, g)."""
    x0, y0 = xs[-1], ys[-1]
    g = 0.0
    cnt = 0
    for k in range(len(xs) - 1):
        if ys[k] > 0 and xs[k] > 0:
            g += math.log(ys[k] / y0) / math.log(xs[k] / x0)
            cnt += 1
    g = g / cnt if cnt else 1.0
    return (1.0 / x0, y0, g)


def dt_eval_exp(coeff, x):
    """dt_iop_eval_exp: coeff[1] * pow(x*coeff[0], coeff[2])."""
    return coeff[1] * (x * coeff[0]) ** coeff[2]


def lut_index(x):
    """LUT index — ROUNDED (Plan 03-03 deviation): dt truncates
    (uint(x*0x10000)), but neutral pixels sit EXACTLY on truncation
    boundaries (a=0 → a_in=0.5 → 32768.0) where the GPU's float32 chroma
    noise flips the index ±1 systematically. Rounding to nearest keeps the
    ≤1-LSB semantic difference while making the index stable under noise."""
    if x <= 0.0:
        return 0
    return min(int(x * 0x10000 + 0.5), 0xFFFF)


# ──────────────────────────────────────────────────────────────────────
# Colisa (Plan 03-03-T2) — dt_iop_colisa_params_t v1 = <fff> (12 bytes)
# ──────────────────────────────────────────────────────────────────────

COLISA_PARAMS_FORMAT = "<fff"
COLISA_MODVERSION = 1
COLISA_IOP_ORDER = 47.0

# dt colisa.c:179-235 semantics in float64 (LUT values stored float32 at
# lookup time via f32(), matching the GPU buffer grid).
def colisa_tables(contrast_p, brightness_p):
    contrast = contrast_p + 1.0
    brightness = brightness_p * 2.0
    ctable = [0.0] * 0x10000
    if contrast <= 1.0:
        for k in range(0x10000):
            ctable[k] = contrast * (100.0 * k / 0x10000 - 50.0) + 50.0
    else:
        boost = 20.0
        m1sq = boost * (contrast - 1.0) * (contrast - 1.0)
        scale = math.sqrt(1.0 + m1sq)
        for k in range(0x10000):
            kx = 2.0 * k / 0x10000 - 1.0
            ctable[k] = 50.0 * (scale * kx / math.sqrt(1.0 + m1sq * kx * kx) + 1.0)
    gamma = 1.0 / (1.0 + brightness) if brightness >= 0 else (1.0 - brightness)
    ltable = [100.0 * (k / 0x10000) ** gamma for k in range(0x10000)]
    xs = [0.7, 0.8, 0.9, 1.0]
    cc = dt_estimate_exp(xs, [ctable[lut_index(x)] for x in xs])
    lc = dt_estimate_exp(xs, [ltable[lut_index(x)] for x in xs])
    return ctable, ltable, cc, lc


def colisa_apply_pixel(rgb, ctable, ltable, sat, cc, lc):
    lab = lab_from_rec2020(rgb)
    # contrast on L (index input quantized to the float32 grid)
    x = f32(f32(lab[0]) / 100.0)
    if x < 1.0:
        L = f32(ctable[lut_index(x)])
    else:
        L = dt_eval_exp(cc, x)
    # brightness on the RESULT (colisa.c:170)
    xn = f32(f32(L) / 100.0)
    if xn < 1.0:
        L2 = f32(ltable[lut_index(xn)])
    else:
        L2 = dt_eval_exp(lc, xn)
    return lab_to_rec2020((L2, lab[1] * sat, lab[2] * sat))


# The colisa 钉参组 (plan T2 action 4: contrast ±0.5 / brightness ±0.3 /
# saturation ±0.5 in combos).
COLISA_CASES = [
    ("colisa_default", 0.0, 0.0, 0.0),
    ("colisa_c05", 0.5, 0.0, 0.0),
    ("colisa_cm05_b03", -0.5, 0.3, 0.0),
    ("colisa_bm03_s05", 0.0, -0.3, 0.5),
    ("colisa_combo", 0.5, -0.3, -0.5),
]

COLISA_REF_FIXTURES = [
    "ramp_8ev", "gray_staircase", "flat_0ev", "flat_-4ev", "saturated",
    "deep_shadow",
]


def colisa_params_blob(contrast, brightness, saturation) -> str:
    """dt_iop_colisa_params_t v1 → lowercase HEX ASCII (12 bytes)."""
    packed = struct.pack(COLISA_PARAMS_FORMAT, contrast, brightness, saturation)
    assert len(packed) == 12, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def gen_colisa_refs(canonical_dir: str, out_dir: str) -> None:
    """Synthesize the colisa golden REFERENCES — the float64 evaluation of
    the documented shared semantic over the canonical fixture bytes both
    sides consume (L017 route; see the Lab-domain section header)."""
    os.makedirs(out_dir, exist_ok=True)
    for case_name, c, b, s in COLISA_CASES:
        ctable, ltable, cc, lc = colisa_tables(c, b)
        sat = s + 1.0
        for fixture in COLISA_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)

            def px(x, y, rgb=rgb, ctable=ctable, ltable=ltable, sat=sat,
                   cc=cc, lc=lc, w=w):
                idx = y * w + x
                return colisa_apply_pixel(
                    (rgb[0][idx], rgb[1][idx], rgb[2][idx]),
                    ctable, ltable, sat, cc, lc,
                )

            write_exr(os.path.join(out_dir, f"{case_name}__{fixture}.exr"), w, h, px)


# ──────────────────────────────────────────────────────────────────────
# Tonecurve (Plan 03-03-T3) — dt tonecurve.c commit_params + process,
# curve_tools.c interpolators. Interpolation in float64 with the SAME op
# order as ToneCurveLUT.swift (only +−×÷√ — bit-deterministic across
# implementations). LUT values are NOT integer-quantized (the recorded
# Lightamer deviation); the NEAREST truncation lookup is kept.
# ──────────────────────────────────────────────────────────────────────

TONECURVE_PARAMS_MODVERSION = 5
TONECURVE_IOP_ORDER = 48.0
TONECURVE_MAXNODES = 20

TONECURVE_EPSILON = 2.0 * 2.0 ** -126  # dt EPSILON = 2*FLT_MIN


def monotone_hermite_tangents(x, y):
    n = len(x)
    delta = [0.0] * n
    m = [0.0] * (n + 1)
    for i in range(n - 1):
        delta[i] = (y[i + 1] - y[i]) / (x[i + 1] - x[i])
    delta[n - 1] = delta[n - 2]
    m[0] = delta[0]
    m[n - 1] = delta[n - 1]
    for i in range(1, n - 1):
        m[i] = (delta[i - 1] + delta[i]) * 0.5
    for i in range(n):
        if abs(delta[i]) < TONECURVE_EPSILON:
            m[i] = 0.0
            m[i + 1] = 0.0
        else:
            alpha = m[i] / delta[i]
            beta = m[i + 1] / delta[i]
            tau = alpha * alpha + beta * beta
            if tau > 9.0:
                m[i] = 3.0 * alpha * delta[i] / math.sqrt(tau)
                m[i + 1] = 3.0 * beta * delta[i] / math.sqrt(tau)
    return m[0:n]


def catmull_rom_tangents(x, y):
    n = len(x)
    m = [0.0] * n
    m[0] = (y[1] - y[0]) / (x[1] - x[0])
    for i in range(1, n - 1):
        m[i] = (y[i + 1] - y[i - 1]) / (x[i + 1] - x[i - 1])
    m[n - 1] = (y[n - 1] - y[n - 2]) / (x[n - 1] - x[n - 2])
    return m


def cubic_spline_second_derivatives(x, y):
    """spline_cubic_set with dt's natural-BC wrapper (2,0)/(2,0)."""
    n = len(x)
    a = [0.0] * (3 * n)
    b = [0.0] * n
    b[0] = 0.0
    a[1] = 1.0
    a[0 + 3] = 0.0
    for i in range(1, n - 1):
        b[i] = (y[i + 1] - y[i]) / (x[i + 1] - x[i]) - (y[i] - y[i - 1]) / (x[i] - x[i - 1])
        a[2 + (i - 1) * 3] = (x[i] - x[i - 1]) / 6.0
        a[1 + i * 3] = (x[i + 1] - x[i - 1]) / 3.0
        a[0 + (i + 1) * 3] = (x[i + 1] - x[i]) / 6.0
    b[n - 1] = 0.0
    a[2 + (n - 2) * 3] = 0.0
    a[1 + (n - 1) * 3] = 1.0
    # d3_np_fs
    for i in range(n):
        if a[1 + i * 3] == 0.0:
            return None
    xx = list(b)
    for i in range(1, n):
        xmult = a[2 + (i - 1) * 3] / a[1 + (i - 1) * 3]
        a[1 + i * 3] = a[1 + i * 3] - xmult * a[0 + i * 3]
        xx[i] = xx[i] - xmult * xx[i - 1]
    xx[n - 1] = xx[n - 1] / a[1 + (n - 1) * 3]
    for i in range(n - 2, -1, -1):
        xx[i] = (xx[i] - a[0 + (i + 1) * 3] * xx[i + 1]) / a[1 + i * 3]
    return xx


def hermite_val(x, y, m, xval):
    n = len(x)
    ival = n - 2
    for i in range(n - 2):
        if xval < x[i + 1]:
            ival = i
            break
    m0, m1 = m[ival], m[ival + 1]
    h = x[ival + 1] - x[ival]
    dx = (xval - x[ival]) / h
    dx2 = dx * dx
    dx3 = dx2 * dx
    h00 = 2.0 * dx3 - 3.0 * dx2 + 1.0
    h10 = dx3 - 2.0 * dx2 + dx
    h01 = -2.0 * dx3 + 3.0 * dx2
    h11 = dx3 - dx2
    return h00 * y[ival] + h10 * h * m0 + h01 * y[ival + 1] + h11 * h * m1


def spline_val(x, y, ypp, tval):
    n = len(x)
    ival = n - 2
    for i in range(n - 1):
        if tval < x[i + 1]:
            ival = i
            break
    dt = tval - x[ival]
    h = x[ival + 1] - x[ival]
    return y[ival] + dt * (
        (y[ival + 1] - y[ival]) / h
        - (ypp[ival + 1] / 6.0 + ypp[ival] / 3.0) * h
        + dt * (0.5 * ypp[ival] + dt * ((ypp[ival + 1] - ypp[ival]) / (6.0 * h)))
    )


def tonecurve_build_table(nodes, curve_type):
    """dt draw.h CurveDataSample shape over [0,1], NO integer quantization
    (the recorded Lightamer deviation); flat outside the node x-range."""
    res = ToneCurveLUTResolution
    table = [0.0] * res
    if len(nodes) < 2:
        for k in range(res):
            table[k] = k / (res - 1)
        return table
    xs = [n[0] for n in nodes]
    ys = [n[1] for n in nodes]
    m = ypp = None
    if curve_type == 2:
        m = monotone_hermite_tangents(xs, ys)
    elif curve_type == 1:
        m = catmull_rom_tangents(xs, ys)
    else:
        ypp = cubic_spline_second_derivatives(xs, ys)
    if m is None and ypp is None:
        for k in range(res):
            table[k] = k / (res - 1)
        return table
    step = 1.0 / (res - 1)
    first_x, last_x = xs[0], xs[-1]
    first_y, last_y = ys[0], ys[-1]
    for k in range(res):
        xk = k * step
        if xk < first_x:
            v = first_y
        elif xk > last_x:
            v = last_y
        elif m is not None:
            v = hermite_val(xs, ys, m, xk)
        else:
            v = spline_val(xs, ys, ypp, xk)
        table[k] = max(0.0, min(1.0, v))
    return table


ToneCurveLUTResolution = 0x10000


def tonecurve_commit(curves, types, autoscale):
    """dt tonecurve.c:722-841. curves = [nodesL, nodesA, nodesB] with
    nodes as (x, y) tuples; types raw (0 cubic/1 catmull/2 hermite);
    autoscale raw (0 manual/1 Lab/2 XYZ/3 RGB — RGB over Rec2020)."""
    res = ToneCurveLUTResolution
    tableL = [v * 100.0 for v in tonecurve_build_table(curves[0], types[0])]
    tableA = [v * 256.0 - 128.0 for v in tonecurve_build_table(curves[1], types[1])]
    tableB = [v * 256.0 - 128.0 for v in tonecurve_build_table(curves[2], types[2])]

    if autoscale == 2:
        derived = [0.0] * res
        for k in range(res):
            t = k / res
            lab = _xyz50_to_lab((t, t, t))
            idx = lut_index(lab[0] / 100.0)
            lab_out = (tableL[idx], lab[1], lab[2])
            derived[k] = _lab_to_xyz50(lab_out)[1]
        tableL = derived
    elif autoscale == 3:
        derived = [0.0] * res
        for k in range(res):
            t = k / res
            lab = lab_from_rec2020((t, t, t))
            idx = lut_index(lab[0] / 100.0)
            lab_out = (tableL[idx], lab[1], lab[2])
            derived[k] = lab_to_rec2020(lab_out)[1]
        tableL = derived

    xs = [0.7, 0.8, 0.9, 1.0]

    def sample(t, x):
        return t[lut_index(x)]

    def fit(t, xm):
        return dt_estimate_exp([v * xm for v in xs], [sample(t, v * xm) for v in xs])

    def left_fit(t, xm):
        return dt_estimate_exp([v * xm for v in xs], [sample(t, 1.0 - v * xm) for v in xs])

    xm_l = curves[0][-1][0]
    xm_ar = curves[1][-1][0]
    xm_al = 1.0 - curves[1][0][0]
    xm_br = curves[2][-1][0]
    xm_bl = 1.0 - curves[2][0][0]
    return {
        "L": tableL, "A": tableA, "B": tableB,
        "cL": fit(tableL, xm_l),
        "cAR": fit(tableA, xm_ar), "cAL": left_fit(tableA, xm_al),
        "cBR": fit(tableB, xm_br), "cBL": left_fit(tableB, xm_bl),
        "low": tableL[lut_index(0.01)],
    }


def _xyz50_to_lab(xyz):
    fx = _lab_f(xyz[0] / LAB_WHITE[0])
    fy = _lab_f(xyz[1] / LAB_WHITE[1])
    fz = _lab_f(xyz[2] / LAB_WHITE[2])
    return (116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


def _lab_to_xyz50(lab):
    fy = (lab[0] + 16.0) / 116.0
    fx = fy + lab[1] / 500.0
    fz = fy - lab[2] / 200.0
    return (
        LAB_WHITE[0] * _lab_f_inv(fx),
        LAB_WHITE[1] * _lab_f_inv(fy),
        LAB_WHITE[2] * _lab_f_inv(fz),
    )


def tc_lookup_unbounded(table, x, c):
    if x < 1.0:
        return f32(table[lut_index(x)])
    return c[1] * (x * c[0]) ** c[2]


def tc_lookup_twosided(table, x, cr, cl):
    xm_r = 1.0 / cr[0]
    xm_l = 1.0 - 1.0 / cl[0]
    if xm_l <= x < xm_r:
        return f32(table[lut_index(x)])
    if x >= xm_r:
        return cr[1] * (x * cr[0]) ** cr[2]
    return cl[1] * ((1.0 - x) * cl[0]) ** cl[2]


def tc_rgb_norm(rgb, norm):
    if norm == 1:
        return rgb[0] * 0.262700 + rgb[1] * 0.678009 + rgb[2] * 0.059291
    if norm == 2:
        return max(rgb)
    if norm == 4:
        return sum(rgb)
    if norm == 5:
        return math.sqrt(rgb[0] ** 2 + rgb[1] ** 2 + rgb[2] ** 2)
    if norm == 6:
        r, g, b = rgb[0] ** 2, rgb[1] ** 2, rgb[2] ** 2
        return (rgb[0] * r + rgb[1] * g + rgb[2] * b) / (r + g + b)
    return sum(rgb) / 3.0


def tonecurve_apply_pixel(rgb, tables, autoscale, unbound, preserve):
    lab = lab_from_rec2020(rgb)
    l_in = f32(f32(lab[0]) / 100.0)
    L = tc_lookup_unbounded(tables["L"], l_in, tables["cL"])
    if autoscale == 0:
        a_in = f32((f32(lab[1]) + 128.0) / 256.0)
        b_in = f32((f32(lab[2]) + 128.0) / 256.0)
        if unbound:
            lab = (L, tc_lookup_twosided(tables["A"], a_in, tables["cAR"], tables["cAL"]),
                   tc_lookup_twosided(tables["B"], b_in, tables["cBR"], tables["cBL"]))
        else:
            lab = (L, f32(tables["A"][lut_index(max(a_in, 0.0))]),
                   f32(tables["B"][lut_index(max(b_in, 0.0))]))
    elif autoscale == 1:
        if l_in > 0.01:
            lab = (L, f32(lab[1]) * L / l_in, f32(lab[2]) * L / l_in)
        else:
            lab = (L, f32(lab[1]) * tables["low"], f32(lab[2]) * tables["low"])
    elif autoscale == 2:
        xyz = _lab_to_xyz50(lab)
        xyz = tuple(tc_lookup_unbounded(tables["L"], c, tables["cL"]) for c in xyz)
        lab = _xyz50_to_lab(xyz)
    elif autoscale == 3:
        rgbw = lab_to_rec2020(lab)
        if preserve == 0:
            rgbw = tuple(tc_lookup_unbounded(tables["L"], c, tables["cL"]) for c in rgbw)
        else:
            lum = tc_rgb_norm(rgbw, preserve)
            if lum > 0.0:
                ratio = tc_lookup_unbounded(tables["L"], lum, tables["cL"]) / lum
                rgbw = (rgbw[0] * ratio, rgbw[1] * ratio, rgbw[2] * ratio)
            else:
                rgbw = (rgbw[0], rgbw[1], rgbw[2])
        lab = lab_from_rec2020(rgbw)
    return lab_to_rec2020(lab)


def tonecurve_params_blob(curves, types, autoscale, unbound, preserve) -> str:
    """dt_iop_tonecurve_params_t v5 → HEX ASCII: 3×20×2 node floats +
    {nodes[3], type[3], autoscale, preset, unbound, preserve} ints."""
    floats = []
    for ch in range(3):
        nodes = list(curves[ch])[:TONECURVE_MAXNODES]
        for i in range(TONECURVE_MAXNODES):
            if i < len(nodes):
                floats.append(nodes[i][0])
                floats.append(nodes[i][1])
            else:
                floats.append(0.0)
                floats.append(0.0)
    ints = [len(curves[0]), len(curves[1]), len(curves[2]),
            types[0], types[1], types[2], autoscale, 0, 1 if unbound else 0, preserve]
    # 10 ints: nodes[3] + type[3] + autoscale + preset + unbound + preserve
    packed = struct.pack("<120f10i", *(floats + ints))
    assert len(packed) == 520, len(packed)
    return binascii.hexlify(packed).decode("ascii")


# The tonecurve 钉参组 (plan T3 action 4): identity / strong S on L
# (manual a/b) / RGB-linked / per-channel (preserve NONE).
_TONECURVE_S_NODES = [(0.0, 0.0), (0.25, 0.15), (0.5, 0.5), (0.75, 0.85), (1.0, 1.0)]
_TONECURVE_AB_NODES = [(0.0, 0.0), (0.5, 0.5), (1.0, 1.0)]
TONECURVE_CASES = [
    ("tonecurve_identity",
     [[(0.0, 0.0), (1.0, 1.0)], _TONECURVE_AB_NODES, _TONECURVE_AB_NODES],
     [2, 2, 2], 3, True, 3),
    ("tonecurve_s_manual",
     [_TONECURVE_S_NODES, _TONECURVE_AB_NODES, _TONECURVE_AB_NODES],
     [2, 2, 2], 0, True, 3),
    ("tonecurve_s_rgb",
     [_TONECURVE_S_NODES, _TONECURVE_AB_NODES, _TONECURVE_AB_NODES],
     [2, 2, 2], 3, True, 3),
    ("tonecurve_perchannel",
     [_TONECURVE_S_NODES, _TONECURVE_AB_NODES, _TONECURVE_AB_NODES],
     [2, 2, 2], 3, True, 0),
]

TONECURVE_REF_FIXTURES = [
    "stair_1d", "ramp_8ev", "gray_staircase", "flat_0ev", "saturated",
]


def gen_tonecurve_refs(canonical_dir: str, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for case_name, curves, types, autoscale, unbound, preserve in TONECURVE_CASES:
        tables = tonecurve_commit(curves, types, autoscale)
        for fixture in TONECURVE_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)

            def px(x, y, rgb=rgb, tables=tables, autoscale=autoscale,
                   unbound=unbound, preserve=preserve, w=w):
                idx = y * w + x
                return tonecurve_apply_pixel(
                    (rgb[0][idx], rgb[1][idx], rgb[2][idx]),
                    tables, autoscale, unbound, preserve,
                )

            write_exr(os.path.join(out_dir, f"{case_name}__{fixture}.exr"), w, h, px)


# ──────────────────────────────────────────────────────────────────────

def gen_tonecurve_cases(outdir: str) -> None:
    for case_name, curves, types, autoscale, unbound, preserve in TONECURVE_CASES:
        params = tonecurve_params_blob(curves, types, autoscale, unbound, preserve)
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION,
            iop_order_version=5,
            operation="tonecurve",
            modversion=TONECURVE_PARAMS_MODVERSION,
            params=params,
            iop_order=f"{TONECURVE_IOP_ORDER:.1f}",
        )
        with open(os.path.join(outdir, case_name + ".xmp"), "w") as f:
            f.write(xmp)
    auto_cases = LEVELS_CASES + [LEVELS_AUTO_CASE]
    for case_name, mode, levels in auto_cases:
        black, gray, white = (LEVELS_AUTO_PERCENTILES + (0.0, 100.0))[:3] \
            if mode == 1 else (0.0, 50.0, 100.0)
        params = levels_params_blob(mode, black, gray, white, levels)
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION,
            iop_order_version=5,
            operation="levels",
            modversion=LEVELS_MODVERSION,
            params=params,
            iop_order=f"{LEVELS_IOP_ORDER:.1f}",
        )
        with open(os.path.join(outdir, case_name + ".xmp"), "w") as f:
            f.write(xmp)


# ──────────────────────────────────────────────────────────────────────
# Levels (Plan 03-03-T4/T5) — dt_iop_levels_params_t v2 = <iffffff>
# (24 bytes): mode int + black/gray/white floats (PERCENTILES in
# automatic mode) + levels[3] floats (manual points, normalized).
# ──────────────────────────────────────────────────────────────────────

LEVELS_PARAMS_FORMAT = "<iffffff"
LEVELS_MODVERSION = 2
LEVELS_IOP_ORDER = 49.0


def levels_lut(levels, bins=0x10000):
    """dt compute_lut (levels.c:252-267) in float64."""
    l0, l1, l2 = levels
    delta = max((l2 - l0) / 2.0, 1e-9)  # Lightamer NaN guard (divergence #4)
    mid = l0 + delta
    tmp = (l1 - mid) / delta
    inv_gamma = 10.0 ** tmp
    return [100.0 * (i / bins) ** inv_gamma for i in range(bins)], inv_gamma


def levels_apply_pixel(rgb, lut, inv_gamma, l0, l2):
    """dt process (levels.c:412-434, CPU chroma form) — Lab fused."""
    lab = lab_from_rec2020(rgb)
    l_in = f32(f32(lab[0]) / 100.0)
    if l_in <= l0:
        l_out = 0.0
    else:
        percentage = f32((l_in - l0) / (l2 - l0))
        if percentage < 1.0:
            l_out = f32(lut[lut_index(percentage)])
        else:
            l_out = 100.0 * percentage ** inv_gamma
    denom = max(f32(lab[0]), 0.01)
    return lab_to_rec2020((l_out, lab[1] * l_out / denom, lab[2] * l_out / denom))


# The levels 钉参组 (plan T4 action 3): identity / black=20 white=80 /
# strong gamma (gray=25). T5 adds the automatic percentile case.
LEVELS_CASES = [
    ("levels_default", 0, [0.0, 0.5, 1.0]),
    ("levels_bw", 0, [0.2, 0.5, 0.8]),
    ("levels_gamma", 0, [0.0, 0.25, 1.0]),
]

# The automatic 钉参组 (plan T5): mode=1 with the black/gray/white fields
# carrying the PERCENTILES (dt levels.c:514-516 semantics). The XMP pins
# dt-side adoption (DB op_params); the Lightamer-side reference is the
# IN-TEST self-consistent evaluation (GPU histogram → percentile → LUT →
# apply) — a pre-generated per-pixel EXR reference would bake in the
# float64 histogram binning, which disagrees with the GPU's float32 bin
# assignment at ~1e-4 of pixels and shifts the percentile level by a bin
# (a GLOBAL LUT change the <1e-4 gate cannot absorb).
LEVELS_AUTO_CASE = ("levels_auto", 1, [0.0, 0.5, 1.0])
LEVELS_AUTO_PERCENTILES = (2.0, 50.0, 98.0)

LEVELS_REF_FIXTURES = [
    "stair_1d", "ramp_8ev", "gray_staircase", "flat_0ev", "flat_-4ev",
    "saturated",
]


def levels_params_blob(mode, black, gray, white, levels) -> str:
    packed = struct.pack(
        LEVELS_PARAMS_FORMAT, mode, black, gray, white,
        levels[0], levels[1], levels[2],
    )
    assert len(packed) == 28, len(packed)  # 1 int + 6 floats
    return binascii.hexlify(packed).decode("ascii")


def gen_levels_refs(canonical_dir: str, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for case_name, mode, levels in LEVELS_CASES:
        lut, inv_gamma = levels_lut(levels)
        l0, l2 = levels[0], levels[2]
        for fixture in LEVELS_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)

            def px(x, y, rgb=rgb, lut=lut, inv_gamma=inv_gamma, l0=l0, l2=l2, w=w):
                idx = y * w + x
                return levels_apply_pixel(
                    (rgb[0][idx], rgb[1][idx], rgb[2][idx]),
                    lut, inv_gamma, l0, l2,
                )

            write_exr(os.path.join(out_dir, f"{case_name}__{fixture}.exr"), w, h, px)


# ──────────────────────────────────────────────────────────────────────
# Shadhi (Plan 03-04-T2) — dt_iop_shadhi_params_t v5, 48 bytes:
#   order (i, dt_gaussian_order_t; 0 = ZERO) + radius/shadows/whitepoint/
#   highlights/reserved2/compress/shadows_ccorrect/highlights_ccorrect
#   (8f) + flags (I) + low_approximation (f) + shadhi_algo (i;
#   0 = GAUSSIAN — the plan checkpoint pins the gaussian leg; dt's
#   DEFAULT is bilateral but that leg is a Phase 5 port).
#
# Reference math (float64 transliteration of shadhi.c:336-490 + the
# gaussian.c:41-100/gaussian.cl recursion — dt's blur is a Deriche IIR,
# NOT a truncated FIR; recorded plan-source erratum):
#   1. Rec2020→Lab (project constants), raw Lab buffer (L 0..100).
#   2. 4-channel (L,a,b,alpha=1) IIR blur, columns then rows, unbounded
#      (the pinned flags = 127 = UNBOUND_DEFAULT make the box ±FLT_MAX).
#   3. Overlay: invert+desaturate the blur, whitepoint, highlights then
#      shadows loops (strength² chunking), chroma factor, Lab→Rec2020.
# ──────────────────────────────────────────────────────────────────────

SHADHI_PARAMS_FORMAT = "<i8fIfi"
SHADHI_MODVERSION = 5
SHADHI_IOP_ORDER = 50.0

SHADHI_FLAG_DEFAULT = 127  # UNBOUND_DEFAULT (shadhi.c:54-56)

SHADHI_CASES = [
    # dt defaults with shadhi_algo pinned to GAUSSIAN (0) — dt's default
    # enum is bilateral; the checkpoint decision makes gaussian the
    # comparable leg on both sides.
    dict(name="shadhi_default", radius=100.0, shadows=50.0, whitepoint=0.0,
         highlights=-50.0, compress=50.0, scc=100.0, hcc=50.0, algo=0),
    dict(name="shadhi_shadows80", radius=100.0, shadows=80.0, whitepoint=0.0,
         highlights=-50.0, compress=50.0, scc=100.0, hcc=50.0, algo=0),
    dict(name="shadhi_highlights80", radius=100.0, shadows=50.0, whitepoint=0.0,
         highlights=-80.0, compress=50.0, scc=100.0, hcc=50.0, algo=0),
    dict(name="shadhi_compress25", radius=100.0, shadows=50.0, whitepoint=0.0,
         highlights=-50.0, compress=25.0, scc=100.0, hcc=50.0, algo=0),
]

SHADHI_REF_FIXTURES = COLISA_REF_FIXTURES


def shadhi_params_blob(case) -> str:
    packed = struct.pack(
        SHADHI_PARAMS_FORMAT,
        0,                      # order = DT_IOP_GAUSSIAN_ZERO
        case["radius"],
        case["shadows"],
        case["whitepoint"],
        case["highlights"],
        0.0,                    # reserved2
        case["compress"],
        case["scc"],
        case["hcc"],
        SHADHI_FLAG_DEFAULT,
        0.000001,               # low_approximation (dt default)
        case["algo"],
    )
    assert len(packed) == 48, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def _sh_sign(x):
    return -1.0 if x < 0 else 1.0


def dt_gauss_coeffs(sigma):
    """gaussian.c:41-100 `_compute_gauss_params`, ZERO order, float64."""
    alpha = 1.695 / sigma
    ema = math.exp(-alpha)
    ema2 = math.exp(-2.0 * alpha)
    b1 = -2.0 * ema
    b2 = ema2
    k = (1.0 - ema) * (1.0 - ema) / (1.0 + (2.0 * alpha * ema) - ema2)
    a0 = k
    a1 = k * (alpha - 1.0) * ema
    a2 = k * (alpha + 1.0) * ema
    a3 = -k * ema2
    coefp = (a0 + a1) / (1.0 + b1 + b2)
    coefn = (a2 + a3) / (1.0 + b1 + b2)
    return a0, a1, a2, a3, b1, b2, coefp, coefn


def shadhi_blur_lab(channels, w, h, sigma):
    """The gaussian.c column-then-row recursion over 4 float64 planes.

    `channels` = [L, a, b, alpha] lists (w*h each); UNBOUNDED (flags 127
    → Labmin/Labmax ±FLT_MAX, clamp = no-op). Returns 4 blurred planes.
    """
    a0, a1, a2, a3, b1, b2, coefp, coefn = dt_gauss_coeffs(sigma)
    n = w * h
    temp = [[0.0] * n for _ in range(4)]
    out = [[0.0] * n for _ in range(4)]

    # vertical: column by column (forward write + backward accumulate)
    for x in range(w):
        xp = [channels[c][x] for c in range(4)]
        yb = [xp[c] * coefp for c in range(4)]
        yp = yb[:]
        for y in range(h):
            idx = y * w + x
            for c in range(4):
                xc = channels[c][idx]
                yc = a0 * xc + a1 * xp[c] - b1 * yp[c] - b2 * yb[c]
                xp[c] = xc
                yb[c] = yp[c]
                yp[c] = yc
                temp[c][idx] = yc
        xn = [channels[c][(h - 1) * w + x] for c in range(4)]
        xa = xn[:]
        yn = [xn[c] * coefn for c in range(4)]
        ya = yn[:]
        for y in range(h - 1, -1, -1):
            idx = y * w + x
            for c in range(4):
                xc = channels[c][idx]
                yc = a2 * xn[c] + a3 * xa[c] - b1 * yn[c] - b2 * ya[c]
                xa[c] = xn[c]
                xn[c] = xc
                ya[c] = yn[c]
                yn[c] = yc
                temp[c][idx] += yc

    # horizontal: line by line
    for y in range(h):
        base = y * w
        xp = [temp[c][base] for c in range(4)]
        yb = [xp[c] * coefp for c in range(4)]
        yp = yb[:]
        for x in range(w):
            idx = base + x
            for c in range(4):
                xc = temp[c][idx]
                yc = a0 * xc + a1 * xp[c] - b1 * yp[c] - b2 * yb[c]
                xp[c] = xc
                yb[c] = yp[c]
                yp[c] = yc
                out[c][idx] = yc
        xn = [temp[c][base + w - 1] for c in range(4)]
        xa = xn[:]
        yn = [xn[c] * coefn for c in range(4)]
        ya = yn[:]
        for x in range(w - 1, -1, -1):
            idx = base + x
            for c in range(4):
                xc = temp[c][idx]
                yc = a2 * xn[c] + a3 * xa[c] - b1 * yn[c] - b2 * ya[c]
                xa[c] = xn[c]
                xn[c] = xc
                ya[c] = yn[c]
                yn[c] = yc
                out[c][idx] += yc
    return out


def shadhi_overlay(ta, tb, opacity, xform, ccorrect, low_approx):
    """shadhi.c:428-454/:460-487 (unbound path — flags 127): the while
    loop applies strength-weighted chunks; ta mutates in place."""
    lmin, lmax, halfmax, doublemax = 0.0, 1.0, 0.5, 2.0
    strength2 = opacity * opacity
    while strength2 > 0.0:
        la = ta[0]  # unbound: no clamp
        lb = (tb[0] - halfmax) * _sh_sign(opacity) * _sh_sign(lmax - la) + halfmax
        # unbound: lb not clamped
        lref = math.copysign(
            1.0 / abs(la) if abs(la) > low_approx else 1.0 / low_approx, la)
        href = math.copysign(
            1.0 / abs(1.0 - la) if abs(1.0 - la) > low_approx else 1.0 / low_approx,
            1.0 - la)
        chunk = 1.0 if strength2 > 1.0 else strength2
        optrans = chunk * xform
        strength2 -= 1.0
        ta[0] = la * (1.0 - optrans) + (
            lmax - (lmax - doublemax * (la - halfmax)) * (lmax - lb)
            if la > halfmax else doublemax * la * lb
        ) * optrans
        chroma_factor = ta[0] * lref * ccorrect + (1.0 - ta[0]) * href * (1.0 - ccorrect)
        ta[1] = ta[1] * (1.0 - optrans) + (ta[1] + tb[1]) * chroma_factor * optrans
        ta[2] = ta[2] * (1.0 - optrans) + (ta[2] + tb[2]) * chroma_factor * optrans


def gen_shadhi_refs(canonical_dir: str, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for case in SHADHI_CASES:
        radius = max(0.1, case["radius"])
        shadows = 2.0 * max(-1.0, min(1.0, case["shadows"] / 100.0))
        highlights = 2.0 * max(-1.0, min(1.0, case["highlights"] / 100.0))
        whitepoint = max(1.0 - case["whitepoint"] / 100.0, 0.01)
        compress = max(0.0, min(0.99, case["compress"] / 100.0))
        scc = (max(0.0, min(1.0, case["scc"] / 100.0)) - 0.5) * _sh_sign(shadows) + 0.5
        hcc = (max(0.0, min(1.0, case["hcc"] / 100.0)) - 0.5) * _sh_sign(-highlights) + 0.5
        low_approx = 0.000001
        for fixture in SHADHI_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)
            n = w * h
            # raw Lab planes + alpha 1.0 (dt's 4c Lab buffer)
            lab_planes = [[0.0] * n for _ in range(3)]
            for i in range(n):
                l, a, b = lab_from_rec2020((rgb[0][i], rgb[1][i], rgb[2][i]))
                lab_planes[0][i] = l
                lab_planes[1][i] = a
                lab_planes[2][i] = b
            channels = lab_planes + [[1.0] * n]
            blurred = shadhi_blur_lab(channels, w, h, radius)  # sigma = radius × scale/iscale(1)

            def px(x, y, blurred=blurred, rgb=rgb, w=w, shadows=shadows,
                   highlights=highlights, whitepoint=whitepoint, compress=compress,
                   scc=scc, hcc=hcc, low_approx=low_approx):
                idx = y * w + x
                # ta: original Lab scaled; tb: blurred, inverted,
                # desaturated, scaled (shadhi.c:414-419)
                l, a, b = lab_from_rec2020((rgb[0][idx], rgb[1][idx], rgb[2][idx]))
                ta = [l / 100.0, a / 128.0, b / 128.0]
                tb = [(100.0 - blurred[0][idx]) / 100.0, 0.0, 0.0]
                # whitepoint (shadhi.c:421-422)
                ta[0] = ta[0] / whitepoint if ta[0] > 0.0 else ta[0]
                tb[0] = tb[0] / whitepoint if tb[0] > 0.0 else tb[0]
                # overlay highlights then shadows (shadhi.c:424-487)
                xform_h = max(0.0, min(1.0, 1.0 - tb[0] / (1.0 - compress)))
                shadhi_overlay(ta, tb, -highlights, xform_h, 1.0 - hcc, low_approx)
                xform_s = max(0.0, min(1.0, tb[0] / (1.0 - compress) - compress / (1.0 - compress)))
                shadhi_overlay(ta, tb, shadows, xform_s, scc, low_approx)
                out_lab = (ta[0] * 100.0, ta[1] * 128.0, ta[2] * 128.0)
                return lab_to_rec2020(out_lab)

            write_exr(os.path.join(out_dir, f"{case['name']}__{fixture}.exr"), w, h, px)


# ──────────────────────────────────────────────────────────────────────
# Sigmoid (Plan 03-04-T4) — dt_iop_sigmoid_params_t v3, 56 bytes:
#   contrast/skew/white/black (4f) + color_processing (i) +
#   hue_preservation + inset/rotation ×3 + purity (8f) + base_primaries (i).
#
# Reference math (float64 transliteration of sigmoid.c:300-761 + the
# primaries builder/rotation from custom_primaries.c + colorspaces.c):
#   - the four-scalar derivation (commit_params :318-407)
#   - per_channel: pipe→base → desaturate negatives → base→rendering →
#     the log-logistic curve per channel → hue+energy preservation →
#     rendering→pipe
#   - rgb_ratio: desaturate → luma curve → uniform scale → hyperbolic
#     gamut compression
#   - PRIMARIES DEVIATION (recorded on the Swift module): dt's stored-
#     matrix product order (sigmoid.c:453/:464-466) reads inverted
#     against the applied-matrix chain; this reference implements the
#     DOCUMENTED direction semantics (module header), which coincides
#     with dt exactly on the identity default path. The pinned
#     per-channel cases use base = work profile.
# ──────────────────────────────────────────────────────────────────────

SIGMOID_PARAMS_FORMAT = "<ffffiffffffffi"
SIGMOID_MODVERSION = 3
SIGMOID_IOP_ORDER = 45.3

SIGMOID_MIDDLE_GREY = 0.1845  # sigmoid.c:37


SIGMOID_CASES = [
    dict(name="sigmoid_default", contrast=1.5, skew=0.0, white=100.0,
         black=0.0152, mode=0, hue=100.0, insets=(0.0, 0.0, 0.0),
         rotations=(0.0, 0.0, 0.0), purity=0.0, base=0),
    # dt "neutral gray" preset
    dict(name="sigmoid_neutral", contrast=1.22, skew=0.65, white=100.0,
         black=0.0152, mode=0, hue=100.0, insets=(0.0, 0.0, 0.0),
         rotations=(0.0, 0.0, 0.0), purity=0.0, base=0),
    # dt "ACES 100-nit like" preset
    dict(name="sigmoid_aces", contrast=1.6, skew=-0.2, white=100.0,
         black=0.0152, mode=0, hue=0.0, insets=(0.0, 0.0, 0.0),
         rotations=(0.0, 0.0, 0.0), purity=0.0, base=0),
    # dt "Reinhard" preset — the rgb_ratio path
    dict(name="sigmoid_rgb_ratio", contrast=1.0, skew=0.0, white=100.0,
         black=0.0152, mode=1, hue=100.0, insets=(0.0, 0.0, 0.0),
         rotations=(0.0, 0.0, 0.0), purity=0.0, base=0),
    # dt "smooth" preset — exercises the primaries path (inset/rotation/
    # base). Pinned against the dual implementation, NOT dt (the dt-side
    # matrix-direction ambiguity, see the section header).
    dict(name="sigmoid_smooth", contrast=1.5, skew=-0.2, white=100.0,
         black=0.0152, mode=0, hue=0.0, insets=(0.1, 0.1, 0.15),
         rotations=(math.radians(2.0), math.radians(-1.0), math.radians(-3.0)),
         purity=0.0, base=1),
]

SIGMOID_REF_FIXTURES = [
    "ramp_8ev", "gray_staircase", "flat_0ev", "flat_-4ev", "saturated",
    "deep_shadow",
]


def sigmoid_params_blob(case) -> str:
    packed = struct.pack(
        SIGMOID_PARAMS_FORMAT,
        case["contrast"],
        case["skew"],
        case["white"],
        case["black"],
        case["mode"],
        case["hue"],
        case["insets"][0], case["rotations"][0],
        case["insets"][1], case["rotations"][1],
        case["insets"][2], case["rotations"][2],
        case["purity"],
        case["base"],
    )
    assert len(packed) == 56, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def sg_loglogistic(value, magnitude, paper_exp, film_fog, film_power, paper_power):
    """sigmoid.c:300-316 stable form."""
    v = max(value, 0.0)
    fr = (film_fog + v) ** film_power
    pr = magnitude * (fr / (paper_exp + fr)) ** paper_power
    return magnitude if pr != pr else pr  # NaN guard


def sigmoid_derive(contrast, skew, white, black):
    """sigmoid.c:318-392 float64."""
    ref_film_power = contrast
    ref_paper_power = 1.0
    ref_magnitude = 1.0
    ref_film_fog = 0.0
    ref_paper_exposure = (SIGMOID_MIDDLE_GREY + ref_film_fog) ** ref_film_power \
        * ((ref_magnitude / SIGMOID_MIDDLE_GREY) - 1.0)

    def slope(magnitude, paper_exp, film_fog, film_power, paper_power, delta=1e-6):
        hi = sg_loglogistic(SIGMOID_MIDDLE_GREY + delta, magnitude, paper_exp, film_fog, film_power, paper_power)
        lo = sg_loglogistic(SIGMOID_MIDDLE_GREY - delta, magnitude, paper_exp, film_fog, film_power, paper_power)
        return (hi - lo) / 2.0 / delta

    ref_slope = slope(ref_magnitude, ref_paper_exposure, ref_film_fog, ref_film_power, ref_paper_power)
    paper_power = 5.0 ** (-skew)
    temp_film_power = 1.0
    temp_white_target = 0.01 * white
    temp_wgr = (temp_white_target / SIGMOID_MIDDLE_GREY) ** (1.0 / paper_power) - 1.0
    temp_paper_exposure = SIGMOID_MIDDLE_GREY ** temp_film_power * temp_wgr
    temp_slope = slope(temp_white_target, temp_paper_exposure, ref_film_fog, temp_film_power, paper_power)
    film_power = ref_slope / temp_slope

    white_target = 0.01 * white
    black_target = 0.01 * black
    wgr = (white_target / SIGMOID_MIDDLE_GREY) ** (1.0 / paper_power) - 1.0
    wbr = (black_target / white_target) ** (-1.0 / paper_power) - 1.0
    film_fog = SIGMOID_MIDDLE_GREY * wgr ** (1.0 / film_power) \
        / (wbr ** (1.0 / film_power) - wgr ** (1.0 / film_power))
    paper_exposure = (film_fog + SIGMOID_MIDDLE_GREY) ** film_power * wgr
    return dict(white=white_target, black=black_target, paper_exposure=paper_exposure,
                film_fog=film_fog, film_power=film_power, paper_power=paper_power)


def sg_desaturate(v):
    """sigmoid.c:495-504."""
    avg = max((v[0] + v[1] + v[2]) / 3.0, 0.0)
    minv = min(v)
    sf = -avg / (minv - avg) if minv < 0 else 1.0
    return (avg + sf * (v[0] - avg), avg + sf * (v[1] - avg), avg + sf * (v[2] - avg))


def sg_order(v):
    """sigmoid.c:513-564 case table → (min, mid, max) indices."""
    if v[0] >= v[1]:
        if v[1] > v[2]:
            return (2, 1, 0)
        elif v[2] > v[0]:
            return (1, 0, 2)
        elif v[2] > v[1]:
            return (1, 2, 0)
        else:
            return (2, 1, 0)
    else:
        if v[0] >= v[2]:
            return (2, 0, 1)
        elif v[2] > v[1]:
            return (0, 1, 2)
        else:
            return (0, 2, 1)


def sg_preserve_hue_energy(pix, per_channel, order, hp):
    """sigmoid.c:658-701 — pix mutates in place."""
    omin, omid, omax = order
    pix_min, pix_mid, pix_max = pix[omin], pix[omid], pix[omax]
    per_min, per_mid, per_max = per_channel[omin], per_channel[omid], per_channel[omax]

    chroma = pix_max - pix_min
    midscale = (pix_mid - pix_min) / chroma if chroma != 0.0 else 0.0
    full_hue_correction = per_min + (per_max - per_min) * midscale
    naive_hue_mid = (1.0 - hp) * per_mid + hp * full_hue_correction

    per_energy = per_channel[0] + per_channel[1] + per_channel[2]
    naive_energy = per_min + naive_hue_mid + per_max
    min_plus_mid = pix_min + pix_mid
    blend = 2.0 * pix_min / min_plus_mid if min_plus_mid != 0.0 else 0.0
    energy_target = blend * per_energy + (1.0 - blend) * naive_energy

    if naive_hue_mid <= per_mid:
        corrected_mid = ((1.0 - hp) * per_mid
                         + hp * (midscale * per_max + (1.0 - midscale) * (energy_target - per_max))) \
            / (1.0 + hp * (1.0 - midscale))
        pix[omin] = energy_target - per_max - corrected_mid
        pix[omid] = corrected_mid
        pix[omax] = per_max
    else:
        corrected_mid = ((1.0 - hp) * per_mid
                         + hp * (per_min * (1.0 - midscale) + midscale * (energy_target - per_min))) \
            / (1.0 + hp * midscale)
        pix[omin] = per_min
        pix[omid] = corrected_mid
        pix[omax] = energy_target - per_min - corrected_mid


def _sg_determinant(a, b, c, d):
    return a * d - b * c


def sg_rotate_scale_primary(profile, scaling, rotation, index):
    """custom_primaries.c:76-96 float64."""
    px, py = profile["primaries"][index]
    wx, wy = profile["white"]
    dx, dy = px - wx, py - wy
    angle = math.atan2(dy, dx) + rotation
    ca, sa = math.cos(angle), math.sin(angle)
    x1, y1 = wx, wy
    x2, y2 = x1 + ca, y1 + sa
    distance = float("inf")
    for i in range(3):
        nxt = (i + 1) % 3
        x3, y3 = profile["primaries"][i]
        x4, y4 = profile["primaries"][nxt]
        den = _sg_determinant(x1 - x2, x3 - x4, y1 - y2, y3 - y4)
        if den == 0:
            t = float("inf")
        else:
            t = _sg_determinant(x1 - x3, x3 - x4, y1 - y3, y3 - y4) / den
            t = t if t >= 0 else float("inf")
        distance = min(distance, t)
    return (scaling * distance * ca + wx, scaling * distance * sa + wy)


# Named base profiles — D65 white. The WORK/Rec2020 profile matrix is
# BUILT FROM THE PRIMARIES (the same builder the custom-primaries path
# uses) so base==work composes to EXACT identity — the project's rounded
# REC2020_TO_XYZ constants would leave a ~1.8e-4 residue in the
# pipe_to_base ∘ base_to_pipe product (the xy chromaticities are
# themselves rounded). Swift side: SigmoidProfile.rec2020 (same choice).
SG_REC2020_PRIMARIES = [(0.708, 0.292), (0.170, 0.797), (0.131, 0.046)]
SG_PROFILES = {
    0: None,  # work / Rec2020 — built below (after the builder def)
    1: None,  # explicit Rec2020 — same profile object
    2: None,  # display P3, built below
    3: None,  # Adobe RGB
    4: None,  # sRGB
}


def _sg_build_profile(primaries, white):
    rgb_to_xyz = sg_build_rgb_to_xyz(primaries, white)
    return dict(primaries=primaries, white=white,
                rgb_to_xyz=rgb_to_xyz, xyz_to_rgb=mat_inv(rgb_to_xyz))


def sg_build_rgb_to_xyz(primaries, white):
    """colorspaces.c:2571-2600 float64 — logical RGB→XYZ matrix."""
    p = [[0.0] * 3 for _ in range(3)]  # p[c] = XYZ of primary c (column c)
    for c in range(3):
        y = max(primaries[c][1], sys.float_info.epsilon)
        p[c] = [primaries[c][0] / y, 1.0, (1.0 - primaries[c][0] - y) / y]
    # P·scale = XYZ_white with P[r][c] = p[c][r]
    mat = [[p[c][r] for c in range(3)] for r in range(3)]
    wy = max(white[1], sys.float_info.epsilon)
    xyz_white = [white[0] / wy, 1.0, (1.0 - white[0] - wy) / wy]
    scale = _sg_solve3(mat, xyz_white)
    return [[scale[c] * p[c][r] for c in range(3)] for r in range(3)]


def _sg_solve3(mat, b):
    a = [row[:] for row in mat]
    x = b[:]
    for col in range(3):
        pivot = max(range(col, 3), key=lambda r: abs(a[r][col]))
        if pivot != col:
            a[pivot], a[col] = a[col], a[pivot]
            x[pivot], x[col] = x[col], x[pivot]
        for row in range(col + 1, 3):
            f = a[row][col] / a[col][col]
            for k in range(col, 3):
                a[row][k] -= f * a[col][k]
            x[row] -= f * x[col]
    for row in (2, 1, 0):
        s = x[row]
        for k in range(row + 1, 3):
            s -= a[row][k] * x[k]
        x[row] = s / a[row][row]
    return x


_SG_REC2020 = _sg_build_profile(SG_REC2020_PRIMARIES, (0.3127, 0.3290))
SG_PROFILES[0] = _SG_REC2020
SG_PROFILES[1] = _SG_REC2020
SG_PROFILES[2] = _sg_build_profile([(0.680, 0.320), (0.265, 0.690), (0.150, 0.060)], (0.3127, 0.3290))
SG_PROFILES[3] = _sg_build_profile([(0.6400, 0.3300), (0.2100, 0.7100), (0.1500, 0.0600)], (0.3127, 0.3290))
SG_PROFILES[4] = _sg_build_profile([(0.6400, 0.3300), (0.3000, 0.6000), (0.1500, 0.0600)], (0.3127, 0.3290))


def _sg_matmul(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(3)) for c in range(3)] for r in range(3)]


def _sg_matvec(m, v):
    return tuple(sum(m[r][k] * v[k] for k in range(3)) for r in range(3))


def sg_adjusted_matrices(base, insets, rotations, purity):
    """SigmoidPrimaries.matrices mirror (see the section-header deviation
    note): pipe→base identity when base == work (dt sigmoid.c:423-442)."""
    work = SG_PROFILES[0]
    basep = SG_PROFILES[base]
    if base == 0:
        pipe_to_base = [[1.0 if r == c else 0.0 for c in range(3)] for r in range(3)]
        base_to_pipe = [row[:] for row in pipe_to_base]
    else:
        pipe_to_base = _sg_matmul(basep["xyz_to_rgb"], work["rgb_to_xyz"])
        base_to_pipe = _sg_matmul(work["xyz_to_rgb"], basep["rgb_to_xyz"])

    custom1 = [sg_rotate_scale_primary(basep, 1.0 - insets[i], rotations[i], i) for i in range(3)]
    c1_to_xyz = sg_build_rgb_to_xyz(custom1, basep["white"])
    # base → rendering = M_out(custom₁) · M_in(base) — the custom matrix
    # enters as its INVERSE (XYZ→custom direction).
    base_to_rendering = _sg_matmul(mat_inv(c1_to_xyz), basep["rgb_to_xyz"])

    custom2 = [sg_rotate_scale_primary(basep, 1.0 - purity * insets[i], rotations[i], i) for i in range(3)]
    c2_to_xyz = sg_build_rgb_to_xyz(custom2, basep["white"])
    # rendering₂ → base = M_out(base) · M_in(custom₂).
    r2_to_base = _sg_matmul(basep["xyz_to_rgb"], c2_to_xyz)
    base_to_r2 = mat_inv(r2_to_base)
    rendering_to_pipe = _sg_matmul(base_to_pipe, base_to_r2)
    return pipe_to_base, base_to_rendering, rendering_to_pipe


def sigmoid_apply_pixel(rgb, case, d, matrices):
    mode = case["mode"]
    if mode == 0:
        pipe_to_base, base_to_rendering, rendering_to_pipe = matrices
        v = _sg_matvec(pipe_to_base, rgb)
        v = sg_desaturate(v)
        v = _sg_matvec(base_to_rendering, v)
        per = [sg_loglogistic(v[c], d["white"], d["paper_exposure"], d["film_fog"],
                              d["film_power"], d["paper_power"]) for c in range(3)]
        pix = list(v)
        sg_preserve_hue_energy(pix, per, sg_order(v), case["hue"] * 0.01)
        return _sg_matvec(rendering_to_pipe, pix)
    # rgb_ratio (sigmoid.c:566-654)
    v = sg_desaturate(rgb)
    luma = (v[0] + v[1] + v[2]) / 3.0
    mapped = sg_loglogistic(luma, d["white"], d["paper_exposure"], d["film_fog"],
                            d["film_power"], d["paper_power"])
    if luma > 1e-9:
        sf = mapped / luma
        pre = (sf * v[0], sf * v[1], sf * v[2])
    else:
        pre = (mapped, mapped, mapped)
    pmin, pmax = min(pre), max(pre)
    eps = 1e-6
    dbw = (d["white"] - mapped) / (pmax - mapped + eps)
    dbb = (d["black"] - mapped) / (pmin - mapped - eps)
    dbc = min(dbw, dbb)
    cvmb = (mapped - pmin) / (mapped + eps)
    adj = 1.0 / (cvmb * dbc + eps)
    hc = 2.0 * cvmb / (1.0 - cvmb * cvmb + eps) * adj
    hz = math.sqrt(hc * hc + 1.0)
    cf = hc / (1.0 + hz) * dbc
    return tuple(mapped + cf * (pre[c] - mapped) for c in range(3))


def gen_sigmoid_refs(canonical_dir: str, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for case in SIGMOID_CASES:
        d = sigmoid_derive(case["contrast"], case["skew"], case["white"], case["black"])
        matrices = sg_adjusted_matrices(case["base"], case["insets"], case["rotations"], case["purity"])
        for fixture in SIGMOID_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)

            def px(x, y, rgb=rgb, case=case, d=d, matrices=matrices, w=w):
                idx = y * w + x
                return sigmoid_apply_pixel(
                    (rgb[0][idx], rgb[1][idx], rgb[2][idx]), case, d, matrices)

            write_exr(os.path.join(out_dir, f"{case['name']}__{fixture}.exr"), w, h, px)


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"
    outdir = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(os.path.abspath(__file__))
    os.makedirs(outdir, exist_ok=True)

    if mode in ("raw", "all"):
        for gen in (gen_ramp, gen_flats, gen_saturated, gen_deep_shadow,
                    gen_gray_staircase, gen_stair_1d):
            gen(outdir)
    if mode in ("cases", "all"):
        # Cases default to <golden>/cases — one level up from the fixtures
        # dir when the caller uses the default outdir.
        if mode == "cases" and len(sys.argv) <= 2:
            cases_dir = os.path.join(os.path.dirname(outdir), "cases")
        else:
            cases_dir = os.path.join(outdir, "cases")
        gen_cases(cases_dir)
    if mode == "refs":
        # Plan 03-02: temperature golden references — synthesizes
        # <outdir>/<temperature case>__<fixture>.exr from the canonical
        # fixtures in the fixtures dir (pass the fixtures dir as outdir).
        gen_temperature_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        # Plan 03-03-T2/T3/T4: colisa + tonecurve + levels golden
        # references (L017 route).
        gen_colisa_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        gen_tonecurve_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        gen_levels_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        # Plan 03-04-T2/T4: shadhi (gaussian leg) + sigmoid golden
        # references (L017 route; dt-side = XMP adoption + flat PFM
        # probes).
        gen_shadhi_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        gen_sigmoid_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))

    print(f"gen_fixtures[{mode}] → {outdir}")


if __name__ == "__main__":
    main()

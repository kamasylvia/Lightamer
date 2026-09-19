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
    for case in TONEEQUAL_CASES:
        params = toneequal_params_blob(case)
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION,
            iop_order_version=5,
            operation="toneequal",
            modversion=TONEEQUAL_MODVERSION,
            params=params,
            iop_order=f"{TONEEQUAL_IOP_ORDER:.1f}",
        )
        with open(os.path.join(outdir, case[0] + ".xmp"), "w") as f:
            f.write(xmp)
    for case in FILMIC_CASES:
        params = filmic_params_blob(case)
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION,
            iop_order_version=5,
            operation="filmicrgb",
            modversion=FILMIC_MODVERSION,
            params=params,
            iop_order=f"{FILMIC_IOP_ORDER:.1f}",
        )
        with open(os.path.join(outdir, case["name"] + ".xmp"), "w") as f:
            f.write(xmp)
    for case in AGX_CASES:
        params = agx_params_blob(case)
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION,
            iop_order_version=5,
            operation="agx",
            modversion=AGX_MODVERSION,
            params=params,
            iop_order=f"{AGX_IOP_ORDER:.2f}",
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


# ──────────────────────────────────────────────────────────────────────
# Tone equalizer (Plan 03-05-T5) — dt_iop_toneequalizer_params_t v2, 72
# bytes: 9 EV bands + blending + smoothing + feathering + quantization +
# contrast_boost + exposure_boost (15f) + details + method + iterations
# (3i). Darktable has NO OpenCL for this iop (toneequal.c:313 TODO) —
# the reference below is the float64 evaluation of the CPU sources
# (L017 synthesized route):
#   - CorrectionLUT: 9 linear band gains → 9×8 RBF least squares
#     (normal equations + Cholesky, REPLICATED IN float32 — dt's
#     published weights come from float choleski.h and a float64 solve
#     drifts ~3e-4 through the conditioning, enough to break the none
#     tier's 1e-5 gate) → 80001-entry LUT clamp [0.25, 4]
#   - luma mask: luminance_mask.h (NORM_2 default) + linear_contrast
#   - EIGF leg: eigf.h fast_eigf_surface_blur — bilinear downsample,
#     (g, g²) gaussian (gaussian.c recursion, per-channel data min/max
#     bounds), variance, eigf_blending_no_mask (the exposure-weighted
#     variance RATIO; NO final spatial averaging), blend at full res
#   - apply: exposure = clamp(log2(luma), −8, 0); LUT index round;
#     RGB × correction
# ──────────────────────────────────────────────────────────────────────

TONEEQUAL_PARAMS_FORMAT = "<15f3i"
TONEEQUAL_MODVERSION = 2
TONEEQUAL_IOP_ORDER = 24.0
TONEEQUAL_REF_FIXTURES = COLISA_REF_FIXTURES

# (name, bands9, blending, smoothing, feathering, quantization,
#  contrast_boost, exposure_boost, details, method, iterations)
TONEEQUAL_CASES = [
    ("toneequal_default",
     [0.0] * 9, 5.0, 1.414213562, 1.0, 0.0, 0.0, 0.0, 4, 4, 1),
    ("toneequal_shadow_lift",
     [0.0, 0.0, 0.5, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0],
     5.0, 1.414213562, 1.0, 0.0, 0.0, 0.0, 4, 4, 1),
    ("toneequal_highlight_compress",
     [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -1.0, -0.5, 0.0],
     5.0, 1.414213562, 1.0, 0.0, 0.0, 0.0, 4, 4, 1),
    ("toneequal_contrast_boost",
     [0.0, 0.0, 0.0, 0.0, 0.8, 0.0, 0.0, 0.0, 0.0],
     5.0, 1.414213562, 1.0, 0.0, 4.0, 0.0, 4, 4, 1),
    ("toneequal_none_ramp",
     [0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -0.5, 0.0, 0.0],
     5.0, 1.414213562, 1.0, 0.0, 0.0, 0.0, 0, 4, 1),
]


def toneequal_params_blob(case) -> str:
    (name, bands, blending, smoothing, feathering, quantization,
     contrast_boost, exposure_boost, details, method, iterations) = case
    packed = struct.pack(
        TONEEQUAL_PARAMS_FORMAT,
        *bands,
        blending, smoothing, feathering, quantization,
        contrast_boost, exposure_boost,
        details, method, iterations,
    )
    assert len(packed) == 72, len(packed)
    return binascii.hexlify(packed).decode("ascii")


_F32 = struct.Struct("<f")


def _f32(x):
    """Round to float32 (the C float arithmetic dt's choleski.h runs)."""
    return _F32.unpack(_F32.pack(x))[0]


def te_pseudo_solve_f32(A, y, m=9, n=8):
    """choleski.h pseudo_solve in float32 verbatim: the normal equations
    (lower triangle) + Cholesky-Banachiewicz + the triangular
    descent/ascent. Float32-faithful — see the section header."""
    # _transpose_dot_matrix (lower triangle only) + _transpose_dot_vector
    Asq = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i + 1):
            s = 0.0
            for k in range(m):
                s = _f32(s + _f32(_f32(A[k][i]) * _f32(A[k][j])))
            Asq[i][j] = s
    ysq = []
    for i in range(n):
        s = 0.0
        for k in range(m):
            s = _f32(s + _f32(_f32(A[k][i]) * _f32(y[k])))
        ysq.append(s)

    # _choleski_decompose
    L = [[0.0] * n for _ in range(n)]
    if Asq[0][0] <= 0.0:
        return None
    for i in range(n):
        for j in range(i + 1):
            s = 0.0
            for k in range(j):
                s = _f32(s + _f32(L[i][k] * L[j][k]))
            if i == j:
                t = _f32(Asq[i][i] - s)
                if t < 0.0:
                    return None
                L[i][j] = _f32(math.sqrt(t))
            else:
                d = L[j][j]
                if d == 0.0:
                    return None
                L[i][j] = _f32(_f32(Asq[i][j] - s) / d)
    # _triangular_descent
    b = [0.0] * n
    for i in range(n):
        s = ysq[i]
        for j in range(i):
            s = _f32(s - _f32(L[i][j] * b[j]))
        if L[i][i] == 0.0:
            return None
        b[i] = _f32(s / L[i][i])
    # _triangular_ascent
    x = [0.0] * n
    for i in range(n - 1, -1, -1):
        s = b[i]
        for j in range(n - 1, i, -1):
            s = _f32(s - _f32(L[j][i] * x[j]))
        if L[i][i] == 0.0:
            return None
        x[i] = _f32(s / L[i][i])
    return x


def te_build_lut(bands, sigma):
    """commit_params :1638-1651 + compute_correction_lut :1225-1243."""
    centers_params = [-8.0, -7.0, -6.0, -5.0, -4.0, -3.0, -2.0, -1.0, 0.0]
    centers_ops = [-56 / 7, -48 / 7, -40 / 7, -32 / 7, -24 / 7, -16 / 7, -8 / 7, 0.0]
    denom = 2.0 * sigma * sigma

    def gf(r):
        return math.exp(-r * r / denom)

    # build_interpolation_matrix (float32 entries — dt stores float)
    A = [[_f32(gf(centers_params[i] - centers_ops[j])) for j in range(8)] for i in range(9)]
    gains = [2.0 ** b for b in bands]
    weights = te_pseudo_solve_f32(A, gains)
    assert weights is not None, "toneequal choleski failed"

    lut = []
    for j in range(80001):
        exposure = j / 10000.0 - 8.0
        v = 0.0
        for i in range(8):
            v += gf(exposure - centers_ops[i]) * weights[i]
        lut.append(max(0.25, min(4.0, v)))
    return lut


TE_MIN_FLOAT = 2.0 ** -16
TE_FULCRUM = 2.0 ** -4.0


def te_luma_plane(rgb, w, h, exposure_boost, fulcrum, contrast_linear):
    """luminance_mask.h NORM_2 + linear_contrast over the fixture.
    `contrast_linear` is the ALREADY-linear slope (commit exp2 of the EV
    param — the caller applies dt's commit_params; exp2 here again would
    double it and crush dark lumas into the MIN_FLOAT floor)."""
    boost = 2.0 ** exposure_boost
    n = w * h
    luma = [0.0] * n
    for i in range(n):
        r, g, b = rgb[0][i], rgb[1][i], rgb[2][i]
        lum = boost * math.sqrt(r * r + g * g + b * b)
        luma[i] = max((lum - fulcrum) * contrast_linear + fulcrum, TE_MIN_FLOAT)
    return luma


def te_bilinear(src, w, h, dw, dh, ch):
    """fast_guided_filter.h interpolate_bilinear (dt's corner convention)."""
    out = [[0.0] * dw * dh for _ in range(ch)]
    for i in range(dh):
        for j in range(dw):
            x_in = j / dw * w
            y_in = i / dh * h
            xp = min(int(math.floor(x_in)), w - 1)
            xn = min(xp + 1, w - 1)
            yp = min(int(math.floor(y_in)), h - 1)
            yn = min(yp + 1, h - 1)
            dy_next = yn - y_in
            dy_prev = 1.0 - dy_next
            dx_next = xn - x_in
            dx_prev = 1.0 - dx_next
            for c in range(ch):
                nw = src[c][yp * w + xp]
                ne = src[c][yp * w + xn]
                sw = src[c][yn * w + xp]
                se = src[c][yn * w + xn]
                out[c][i * dw + j] = (dy_prev * (sw * dx_next + se * dx_prev)
                                      + dy_next * (nw * dx_next + ne * dx_prev))
    return out


def te_gaussian_blur(planes, w, h, sigma, mins, maxs):
    """gaussian.c recursion (col then row, forward+backward) with the
    per-channel CLAMPF bounds — the eigf_variance_analysis blur."""
    a0, a1, a2, a3, b1, b2, coefp, coefn = dt_gauss_coeffs(sigma)
    ch = len(planes)
    n = w * h
    temp = [[0.0] * n for _ in range(ch)]
    out = [[0.0] * n for _ in range(ch)]

    def clamp(v, c):
        return max(mins[c], min(maxs[c], v))

    for x in range(w):
        xp = [clamp(planes[c][x], c) for c in range(ch)]
        yb = [xp[c] * coefp for c in range(ch)]
        yp = yb[:]
        for y in range(h):
            idx = y * w + x
            for c in range(ch):
                xc = clamp(planes[c][idx], c)
                yc = a0 * xc + a1 * xp[c] - b1 * yp[c] - b2 * yb[c]
                xp[c] = xc
                yb[c] = yp[c]
                yp[c] = yc
                temp[c][idx] = yc
        xn = [clamp(planes[c][(h - 1) * w + x], c) for c in range(ch)]
        xa = xn[:]
        yn = [xn[c] * coefn for c in range(ch)]
        ya = yn[:]
        for y in range(h - 1, -1, -1):
            idx = y * w + x
            for c in range(ch):
                xc = clamp(planes[c][idx], c)
                yc = a2 * xn[c] + a3 * xa[c] - b1 * yn[c] - b2 * ya[c]
                xa[c] = xn[c]
                xn[c] = xc
                ya[c] = yn[c]
                yn[c] = yc
                temp[c][idx] += yc
    for y in range(h):
        base = y * w
        xp = [clamp(temp[c][base], c) for c in range(ch)]
        yb = [xp[c] * coefp for c in range(ch)]
        yp = yb[:]
        for x in range(w):
            idx = base + x
            for c in range(ch):
                xc = clamp(temp[c][idx], c)
                yc = a0 * xc + a1 * xp[c] - b1 * yp[c] - b2 * yb[c]
                xp[c] = xc
                yb[c] = yp[c]
                yp[c] = yc
                out[c][idx] = yc
        xn = [clamp(temp[c][base + w - 1], c) for c in range(ch)]
        xa = xn[:]
        yn = [xn[c] * coefn for c in range(ch)]
        ya = yn[:]
        for x in range(w - 1, -1, -1):
            idx = base + x
            for c in range(ch):
                xc = clamp(temp[c][idx], c)
                yc = a2 * xn[c] + a3 * xa[c] - b1 * yn[c] - b2 * ya[c]
                xa[c] = xn[c]
                xn[c] = xc
                ya[c] = yn[c]
                yn[c] = yc
                out[c][idx] += yc
    return out


def te_quantize(plane, n, sampling, clip_min, clip_max):
    """fast_guided_filter.h quantize."""
    if sampling == 0.0:
        return plane[:]
    out = [0.0] * n
    for k in range(n):
        if sampling == 1.0:
            v = 2.0 ** math.floor(math.log2(plane[k]))
        else:
            v = 2.0 ** (math.floor(math.log2(plane[k]) / sampling) * sampling)
        out[k] = max(clip_min, min(clip_max, v))
    return out


def te_eigf(luma, w, h, radius, feathering, iterations, geomean,
            quantization, qmin, qmax):
    """eigf.h fast_eigf_surface_blur, float64. The golden cases all ship
    dt's default quantization 0 (the no-mask path — the exact leg the
    parity gate pins; the mask path shares the variance+blend math)."""
    assert quantization == 0.0, "the reference pins the no-mask EIGF leg only"
    scaling = max(min(radius, 4.0), 1.0)
    ds_sigma = max(radius / scaling, 1.0)
    dsw = int(w / scaling)
    dsh = int(h / scaling)
    cur = luma[:]
    n = w * h
    for it in range(iterations):
        ds_image = te_bilinear([cur], w, h, dsw, dsh, 1)[0]
        # eigf_variance_analysis_no_mask: (guide, guide²) blurred with
        # the per-channel DATA min/max bounds (dt's CLAMPF inputs).
        g2 = [v * v for v in ds_image]
        mins = [min(ds_image), min(g2)]
        maxs = [max(ds_image), max(g2)]
        blurred = te_gaussian_blur([ds_image, g2], dsw, dsh, ds_sigma, mins, maxs)
        avg_p = te_bilinear([blurred[0], blurred[1]], dsw, dsh, w, h, 2)
        # eigf_blending_no_mask at full res (dt upsamples av, then blends
        # per-pixel with the same weights).
        geo = geomean and it == iterations - 1
        nxt = [0.0] * n
        for k in range(n):
            avg = avg_p[0][k]
            var = avg_p[1][k] - avg * avg
            img = cur[k]
            norm = max(avg * img, 1e-6)
            nvar = var / norm
            a = nvar / (nvar + feathering)
            b = avg - a * avg
            if geo:
                nxt[k] = math.sqrt(img * max(img * a + b, TE_MIN_FLOAT))
            else:
                nxt[k] = max(img * a + b, TE_MIN_FLOAT)
        cur = nxt
    return cur


def gen_toneequal_refs(canonical_dir: str, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for case in TONEEQUAL_CASES:
        (name, bands, blending, smoothing, feathering, quantization,
         contrast_boost, exposure_boost, details, method, iterations) = case
        lut = te_build_lut(bands, smoothing)
        # commit_params derived scalars (:1596-1620)
        feather_d = 1.0 / feathering
        boosted = details in (2, 4)  # GUIDED / EIGF
        fulcrum = TE_FULCRUM if boosted else 0.0
        contrast = 2.0 ** contrast_boost if boosted else 1.0
        geomean = details in (1, 3)  # AVG_GUIDED / AVG_EIGF
        for fixture in TONEEQUAL_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)
            n = w * h
            # dt keys the smoothing radius on the PIECE's full-image max
            # dimension (modify_roi_in :1352-1357) at scale 1 here.
            radius = int((blending / 100.0 * max(w, h) * 1.0 - 1.0) / 2.0)
            luma = te_luma_plane(rgb, w, h, exposure_boost, fulcrum, contrast)
            if details == 4:  # EIGF (the pinned golden leg)
                luma = te_eigf(luma, w, h, radius, feather_d, iterations,
                               geomean, quantization, 2.0 ** -14, 4.0)
            elif details != 0:
                raise ValueError(f"reference leg for details={details} not pinned")

            def px(x, y, rgb=rgb, luma=luma, lut=lut, w=w):
                idx = y * w + x
                l = luma[idx]
                e = max(-8.0, min(0.0, math.log2(l)))
                c = lut[min(int(round((e + 8.0) * 10000.0)), 80000)]
                return (rgb[0][idx] * c, rgb[1][idx] * c, rgb[2][idx] * c)

            write_exr(os.path.join(out_dir, f"{name}__{fixture}.exr"), w, h, px)


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
        # Plan 03-05-T5: toneequal golden references (two tiers: none +
        # EIGF; L017 route; dt-side = XMP adoption + flat PFM probes).
        gen_toneequal_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        # Plan 03-06: filmicrgb (V5) + agx golden references (L017 route;
        # dt-side = XMP adoption + uniform-flat PFM probes).
        gen_filmic_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        gen_agx_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))

    print(f"gen_fixtures[{mode}] → {outdir}")




# ──────────────────────────────────────────────────────────────────────
# FilmicRGB (Plan 03-06-T2..T5, IOP-FILM-01) — dt_iop_filmicrgb_params_t
# v6, 116 bytes: 18 floats (grey/black/white_point_source,
# reconstruct_threshold/feather/bloom_vs_details/grey_vs_color/
# structure_vs_texture, security_factor, grey/black/white_point_target,
# output_power, latitude, contrast, saturation, balance, noise_level) +
# 11 ints (preserve_color, version, auto_hardness, custom_grey,
# high_quality_reconstruction, noise_distribution, shadows, highlights,
# compensate_icc_black, spline_version, enable_highlight_reconstruction).
#
# Reference math (float64 transliteration of filmicrgb.c:2732-3046
# compute_spline + filmic.cl:651-719 filmic_chroma_v5 + the gamut stack):
# V5 colorscience ONLY (T0 decision 1), highlight reconstruction OFF
# (T0 decision 2 — the default; no rebuild in either leg), ratios
# WITHOUT sanitize (the plan text's "减 min_ratios" is the v1 path —
# 03-06-DECISIONS.md erratum), gamut-stage saturation pinned 0
# (filmic.cl:718). Output-power auto (auto_hardness) re-derived per dt's
# _compute_output_power (:2571-2581).
#
# Matrices: pipeline RGB (D50 Bradford) → LMS 2006 D65 per
# gamut_mapping.h prepare_RGB_Yrg_matrices — same constants as the Swift
# YrgGamut (LAB_R2X here is the D65 Rec2020→XYZ, Bradford D65→D50 = LAB_B).
# ──────────────────────────────────────────────────────────────────────

FILMIC_PARAMS_FORMAT = "<18f11i"
FILMIC_MODVERSION = 6
FILMIC_IOP_ORDER = 46.0
FILMIC_REF_FIXTURES = COLISA_REF_FIXTURES

FRB_SAFETY = 0.01

FRB_METHOD_NONE, FRB_METHOD_MAX_RGB, FRB_METHOD_LUMINANCE, \
    FRB_METHOD_POWER_NORM, FRB_METHOD_EUCLIDEAN_V1, FRB_METHOD_EUCLIDEAN_V2 = range(6)
FRB_CS_V1, FRB_CS_V2, FRB_CS_V3, FRB_CS_V4, FRB_CS_V5 = range(5)
FRB_SPLINE_V1, FRB_SPLINE_V2, FRB_SPLINE_V3 = range(3)


def _frb_default_case(**over):
    case = dict(
        name="filmic_default",
        grey_source=18.45, black_source=-8.0, white_source=4.0,
        security=0.0, grey_target=18.45, black_target=0.01517634,
        white_target=100.0, output_power=4.0, latitude=0.01,
        contrast=1.0, saturation=0.0, balance=0.0,
        preserve=FRB_METHOD_POWER_NORM, version=FRB_CS_V5,
        auto_hardness=1, custom_grey=0, shadows=0, highlights=0,
        spline_version=FRB_SPLINE_V3, enable_reconstruct=0,
    )
    case.update(over)
    return case


FILMIC_CASES = [
    _frb_default_case(),
    _frb_default_case(name="filmic_contrast_lat", contrast=1.8, latitude=15.0),
    _frb_default_case(name="filmic_balance", balance=-30.0, latitude=10.0),
    _frb_default_case(name="filmic_soft_safe", shadows=1, highlights=2, latitude=8.0),
    _frb_default_case(name="filmic_custom_grey", custom_grey=1, grey_target=25.0),
    _frb_default_case(name="filmic_saturation", saturation=60.0),
]


def filmic_params_blob(case) -> str:
    packed = struct.pack(
        FILMIC_PARAMS_FORMAT,
        case["grey_source"], case["black_source"], case["white_source"],
        0.0, 3.0, 100.0, 100.0, 0.0,          # reconstruct_* (F5 param slots)
        case["security"],
        case["grey_target"], case["black_target"], case["white_target"],
        case["output_power"], case["latitude"], case["contrast"],
        case["saturation"], case["balance"], 0.2,
        case["preserve"], case["version"],
        case["auto_hardness"], case["custom_grey"],
        1,                                     # high_quality_reconstruction
        1,                                     # noise_distribution gaussian
        case["shadows"], case["highlights"],
        0,                                     # compensate_icc_black
        case["spline_version"],
        case["enable_reconstruct"],
    )
    assert len(packed) == 116, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def frb_clamp(x):
    """dt clamp_simd: fmaxf(fminf(x, 1), 0) — fmin(NaN, 1) = 1."""
    if x != x:
        return 1.0
    return max(0.0, min(1.0, x))


def frb_log_encode(x, grey, black, dr):
    """log_tonemapping_v2 scalar; C log2f semantics for x ≤ 0."""
    if x > 0.0:
        lg = math.log2(x / grey)
    elif x == 0.0:
        lg = -math.inf
    else:
        lg = math.nan
    return frb_clamp((lg - black) / dr)


def frb_exp_decode(x, grey, black, dr):
    return grey * 2.0 ** (dr * x + black)


def frb_gauss_solve(a, b):
    """Row-major Gaussian elimination with partial pivoting (Double)."""
    n = len(a)
    m = [row[:] for row in a]
    x = b[:]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(m[r][col]))
        if pivot != col:
            m[pivot], m[col] = m[col], m[pivot]
            x[pivot], x[col] = x[col], x[pivot]
        for row in range(col + 1, n):
            f = m[row][col] / m[col][col]
            for k in range(col, n):
                m[row][k] -= f * m[col][k]
            x[row] -= f * x[col]
    for row in range(n - 1, -1, -1):
        s = x[row]
        for k in range(row + 1, n):
            s -= m[row][k] * x[k]
        x[row] = s / m[row][row]
    return x


def filmic_compute_spline(case, output_power):
    """filmicrgb.c:2732-3046 (spline_version v3 branch), float64."""
    # dt: CLAMP(p->grey_point_target, p->black_point_target,
    # p->white_point_target) clamps INTO [black_target, white_target].
    if case["custom_grey"]:
        grey_display = pow(
            max(case["black_target"],
                min(case["grey_target"], case["white_target"])) / 100.0,
            1.0 / output_power)
    else:
        grey_display = pow(0.1845, 1.0 / output_power)
    black_source, white_source = case["black_source"], case["white_source"]
    dr = white_source - black_source
    black_log, grey_log, white_log = 0.0, abs(black_source) / dr, 1.0
    black_display = pow(
        min(max(case["black_target"], 0.0), case["grey_target"]) / 100.0,
        1.0 / output_power)
    white_display = pow(
        max(case["white_target"], case["grey_target"]) / 100.0,
        1.0 / output_power)
    balance = max(-50.0, min(50.0, case["balance"])) / 100.0
    latitude = max(0.0, min(100.0, case["latitude"])) / 100.0

    slope = case["contrast"] * dr / 8.0
    min_contrast = max(
        max(1.0, (white_display - grey_display) / (white_log - grey_log)),
        (grey_display - black_display) / (grey_log - black_log),
    ) + FRB_SAFETY
    contrast = slope / (output_power * pow(grey_display, output_power - 1.0))
    clamped = min(max(contrast, min_contrast), 100.0)
    contrast = clamped
    intercept = grey_display - contrast * grey_log
    xmin = (black_display + FRB_SAFETY * (white_display - black_display) - intercept) / contrast
    xmax = (white_display - FRB_SAFETY * (white_display - black_display) - intercept) / contrast
    toe_log = (1.0 - latitude) * grey_log + latitude * xmin
    shoulder_log = (1.0 - latitude) * grey_log + latitude * xmax
    bc = (2.0 * balance * (shoulder_log - grey_log)) if balance > 0.0 \
        else (2.0 * balance * (grey_log - toe_log))
    toe_log -= bc
    shoulder_log -= bc
    toe_log = max(toe_log, xmin)
    shoulder_log = min(shoulder_log, xmax)
    toe_display = toe_log * contrast + intercept
    shoulder_display = shoulder_log * contrast + intercept

    x = [black_log, toe_log, grey_log, shoulder_log, white_log]
    y = [black_display, toe_display, grey_display, shoulder_display, white_display]

    # M coefficients: toe / shoulder / linear segments.
    M = [[0.0] * 3 for _ in range(5)]
    M[1][2] = contrast
    M[0][2] = y[1] - M[1][2] * x[1]

    tl, sl = x[1], x[3]
    if case["shadows"] == 0:  # poly4
        a = [
            [0, 0, 0, 0, 1],
            [0, 0, 0, 1, 0],
            [tl ** 4, tl ** 3, tl * tl, tl, 1],
            [4 * tl ** 3, 3 * tl * tl, 2 * tl, 1, 0],
            [12 * tl * tl, 6 * tl, 2, 0, 0],
        ]
        s = frb_gauss_solve(a, [y[0], 0.0, y[1], M[1][2], 0.0])
        M[4][0], M[3][0], M[2][0], M[1][0], M[0][0] = s
    elif case["shadows"] == 1:  # poly3
        a = [
            [0, 0, 0, 1],
            [tl ** 3, tl * tl, tl, 1],
            [3 * tl * tl, 2 * tl, 1, 0],
            [6 * tl, 2, 0, 0],
        ]
        s = frb_gauss_solve(a, [y[0], y[1], M[1][2], 0.0])
        M[4][0] = 0.0
        M[3][0], M[2][0], M[1][0], M[0][0] = s
    else:  # rational
        xx, yy, g = x[1] - x[0], y[1] - y[0], contrast
        b = g / (2.0 * yy) + (math.sqrt((xx * g / yy + 1.0) ** 2 - 4.0) - 1.0) / (2.0 * xx)
        c = yy / g * (b * xx * xx + xx) / (b * xx * xx + xx - (yy / g))
        M[0][0], M[1][0], M[2][0], M[3][0] = c * g, b, c, y[1]

    if case["highlights"] == 1:  # poly3
        a = [
            [1, 1, 1, 1],
            [sl ** 3, sl * sl, sl, 1],
            [3 * sl * sl, 2 * sl, 1, 0],
            [6 * sl, 2, 0, 0],
        ]
        s = frb_gauss_solve(a, [y[4], y[3], M[1][2], 0.0])
        M[4][1] = 0.0
        M[3][1], M[2][1], M[1][1], M[0][1] = s
    elif case["highlights"] == 0:  # poly4
        a = [
            [1, 1, 1, 1, 1],
            [4, 3, 2, 1, 0],
            [sl ** 4, sl ** 3, sl * sl, sl, 1],
            [4 * sl ** 3, 3 * sl * sl, 2 * sl, 1, 0],
            [12 * sl * sl, 6 * sl, 2, 0, 0],
        ]
        s = frb_gauss_solve(a, [y[4], 0.0, y[3], M[1][2], 0.0])
        M[4][1], M[3][1], M[2][1], M[1][1], M[0][1] = s
    else:  # rational
        xx, yy, g = x[4] - x[3], y[4] - y[3], contrast
        b = g / (2.0 * yy) + (math.sqrt((xx * g / yy + 1.0) ** 2 - 4.0) - 1.0) / (2.0 * xx)
        c = yy / g * (b * xx * xx + xx) / (b * xx * xx + xx - (yy / g))
        M[0][1], M[1][1], M[2][1], M[3][1] = c * g, b, c, y[3]

    # FLOAT32-PUBLISHED GRID (the toneequal float32-choleski precedent):
    # the Swift module publishes M/latitudes/display targets as Float32 to
    # the kernel, and the float32 rounding of the poly4/poly3 coefficients
    # shifts steep splines by ~3e-5 on a few % of pixels — dominating the
    # parity gate. The reference evaluates through the SAME published grid
    # (all other float32-vs-float64 residue stays ~1e-6).
    for seg in range(3):
        for k in range(5):
            M[k][seg] = _f32(M[k][seg])
    return dict(
        M=M, lat_min=_f32(x[1]), lat_max=_f32(x[3]), x=x, y=y,
        types=(case["shadows"], case["highlights"]),
        grey_display=grey_display, dr=dr, contrast=contrast,
    )


def frb_spline_eval(x, sp):
    """FLOAT32-FAITHFUL Horner evaluation (the kernel's arithmetic — every
    multiply/add rounded through the float32 grid, as in the GPU; the
    float64 evaluation of the same coefficients diverges ~3e-5 on the
    steep poly4 shoulder, ~100x the plain rounding, and swamped the 1e-5
    gate on 25% of the steep-case pixels)."""
    x = _f32(x)
    M = sp["M"]
    lat_min = _f32(sp["lat_min"])
    lat_max = _f32(sp["lat_max"])
    if x < lat_min:
        seg, lane = sp["types"][0], 0
    elif x > lat_max:
        seg, lane = sp["types"][1], 1
    else:
        return _f32(_f32(M[0][2]) + _f32(x * _f32(M[1][2])))
    if seg == 0 or seg == 1:
        order = 5 if seg == 0 else 4
        # Horner inner-out with FMA single-rounding — the Apple GPU
        # contracts a + b·c into fused multiply-add (fp-contract=fast,
        # filmicrgb.c header), so the product is NOT rounded separately.
        # math.fma(x, t, M) gives the same one-rounding semantics.
        t = M[order - 1][lane]
        for k in range(order - 2, -1, -1):
            t = _f32(math.fma(x, t, M[k][lane]))
        return _f32(t)
    if lane == 0:
        xi = _f32(lat_min - x)
        rat = _f32(xi * _f32(_f32(xi * _f32(M[1][0])) + 1.0))
        return _f32(_f32(M[3][0]) - _f32(_f32(M[0][0] * rat) / _f32(rat + _f32(M[2][0]))))
    xi = _f32(x - lat_max)
    rat = _f32(xi * _f32(_f32(xi * _f32(M[1][1])) + 1.0))
    return _f32(_f32(M[3][1]) + _f32(_f32(M[0][1] * rat) / _f32(rat + _f32(M[2][1]))))
    if seg == 0:
        return M[0][lane] + x * (M[1][lane] + x * (M[2][lane] + x * (M[3][lane] + x * M[4][lane])))
    if seg == 1:
        return M[0][lane] + x * (M[1][lane] + x * (M[2][lane] + x * M[3][lane]))
    if lane == 0:
        xi = sp["lat_min"] - x
        rat = xi * (xi * M[1][0] + 1.0)
        return M[3][0] - M[0][0] * rat / (rat + M[2][0])
    xi = x - sp["lat_max"]
    rat = xi * (xi * M[1][1] + 1.0)
    return M[3][1] + M[0][1] * rat / (rat + M[2][1])


# The Yrg stack — same constants as Swift YrgGamut (gamut_mapping.h +
# chromatic_adaptation.h + colorspace.h).
FRB_XYZ50_65 = [[9.89466254e-01, -4.00304626e-02, 4.40530317e-02],
                [-5.40518733e-03, 1.00666069e+00, -1.75551955e-03],
                [-4.03920992e-04, 1.50768030e-02, 1.30210211e+00]]
FRB_XYZ65_50 = [[1.01085433e+00, 4.07086103e-02, -3.41445825e-02],
                [5.42814201e-03, 9.93581926e-01, 1.15592039e-03],
                [2.50722468e-04, -1.14918759e-02, 7.67964947e-01]]
FRB_XYZ65_LMS = [[0.257085, 0.859943, -0.031061],
                 [-0.394427, 1.175800, 0.106423],
                 [0.064856, -0.076250, 0.559067]]
FRB_LMS_XYZ65 = [[1.80794659, -1.29971660, 0.34785879],
                 [0.61783960, 0.39595453, -0.04104687],
                 [-0.12546960, 0.20478038, 1.74274183]]
# M_in(work) = Bradford D65→D50 · Rec2020(D65)→XYZ (dt's ICC colorimetry).
FRB_MATRIX_IN = mat_mul(FRB_XYZ65_LMS, mat_mul(FRB_XYZ50_65, mat_mul(LAB_B, LAB_R2X)))
FRB_MATRIX_OUT = mat_mul(LAB_X2R, mat_mul(LAB_BINV, mat_mul(FRB_XYZ65_50, FRB_LMS_XYZ65)))
FRB_CIE_Y_FACTOR = 1.05785528


def frb_rgb_to_ych(rgb):
    lms = mat_vec(FRB_MATRIX_IN, rgb)
    y = 0.68990272 * lms[0] + 0.34832189 * lms[1]
    a = lms[0] + lms[1] + lms[2]
    nl = tuple(v / a for v in lms) if a != 0.0 else (0.0, 0.0, 0.0)
    grading = (
        1.0877193 * nl[0] - 0.66666667 * nl[1] + 0.02061856 * nl[2],
        -0.0877193 * nl[0] + 1.66666667 * nl[1] - 0.05154639 * nl[2],
        1.03092784 * nl[2],
    )
    r = grading[0] - 0.21902143
    g = grading[1] - 0.54371398
    c = math.sqrt(g * g + r * r) if r == r and g == g else math.nan
    cos_h = r / c if c != 0.0 else 1.0
    sin_h = g / c if c != 0.0 else 0.0
    return (y, c, cos_h, sin_h)


def frb_ych_to_rgb(ych):
    r = ych[2] * ych[1] + 0.21902143
    g = ych[3] * ych[1] + 0.54371398
    b = 1.0 - r - g
    nl = (0.95 * r + 0.38 * g,
          0.05 * r + 0.62 * g + 0.03 * b,
          0.97 * b)
    denom = 0.68990272 * nl[0] + 0.34832189 * nl[1]
    scale = 0.0 if denom == 0.0 else ych[0] / denom
    return mat_vec(FRB_MATRIX_OUT, tuple(v * scale for v in nl))


def frb_desaturate_v4(original, final):
    chroma_original = original[1] * original[0]
    chroma_final = final[1] * final[0]
    # gamut-stage saturation pinned 0 (filmic.cl:718) → delta 0, and the
    # branch flags reduce to: brightens+resat → mean; else keep final.
    filmic_brightens = final[0] > original[0]
    filmic_resat = chroma_original < chroma_final
    if filmic_brightens and filmic_resat:
        chroma_final = (chroma_original + chroma_final) / 2.0
    final = list(final)
    final[1] = max(chroma_final / final[0], 0.0) if final[0] != 0.0 else 0.0
    return tuple(final)


def frb_gamut_check_yrg(ych):
    y, c, cos_h, sin_h = ych
    r = c * cos_h + 0.21902143
    g = c * sin_h + 0.54371398
    max_c = c
    if r < 0.0:
        max_c = min(-0.21902143 / cos_h, max_c)
    if g < 0.0:
        max_c = min(-0.54371398 / sin_h, max_c)
    if r + g > 1.0:
        max_c = min((1.0 - 0.21902143 - 0.54371398) / (cos_h + sin_h), max_c)
    return (y, max_c, cos_h, sin_h)


def frb_clip_chroma_white_raw(coeffs, target_white, y, cos_h, sin_h):
    den_yc = (coeffs[0] * (0.979381443298969 * cos_h + 0.391752577319588 * sin_h)
              + coeffs[1] * (0.0206185567010309 * cos_h + 0.608247422680412 * sin_h)
              - coeffs[2] * (cos_h + sin_h))
    den_tt = target_white * (0.68285981628866 * cos_h + 0.482137060515464 * sin_h)
    if den_yc == 0.0:
        return float("inf")
    if y <= den_tt / den_yc:
        return float("inf")
    num = -0.427506877216495 * (y * (coeffs[0] + 0.856492345150334 * coeffs[1]
                                     + 0.554995960637719 * coeffs[2])
                                - 0.988237752433297 * target_white)
    return num / (y * den_yc - den_tt)


def frb_clip_chroma_white(coeffs, target_white, y, cos_h, sin_h):
    eps = 1e-3
    max_y = FRB_CIE_Y_FACTOR * target_white
    delta_y = max(max_y - y, 0.0)
    if delta_y < eps:
        mc = delta_y / (eps * max_y) * frb_clip_chroma_white_raw(
            coeffs, target_white, (1.0 - eps) * max_y, cos_h, sin_h)
    else:
        mc = frb_clip_chroma_white_raw(coeffs, target_white, y, cos_h, sin_h)
    return mc if mc >= 0.0 else float("inf")


def frb_clip_chroma_black(coeffs, cos_h, sin_h):
    den = (coeffs[0] * (0.979381443298969 * cos_h + 0.391752577319588 * sin_h)
           + coeffs[1] * (0.0206185567010309 * cos_h + 0.608247422680412 * sin_h)
           - coeffs[2] * (cos_h + sin_h))
    if den == 0.0:
        return float("inf")
    num = -0.427506877216495 * (coeffs[0] + 0.856492345150334 * coeffs[1]
                                + 0.554995960637719 * coeffs[2])
    mc = num / den
    return mc if mc >= 0.0 else float("inf")


def frb_clip_chroma(target_white, y, cos_h, sin_h, chroma):
    whites = [
        frb_clip_chroma_white(FRB_MATRIX_OUT[row], target_white, y, cos_h, sin_h)
        for row in range(3)
    ]
    blacks = [
        frb_clip_chroma_black(FRB_MATRIX_OUT[row], cos_h, sin_h)
        for row in range(3)
    ]
    return min(chroma, min(blacks), min(whites))


def frb_gamut_check_rgb(ych_in, display_black, display_white):
    rgb = frb_ych_to_rgb(ych_in)
    min_pix = min(rgb)
    black_offset = max(-min_pix, 0.0)
    rgb = tuple(v + black_offset for v in rgb)
    ych_b = frb_rgb_to_ych(rgb)
    y = max(FRB_CIE_Y_FACTOR * display_black,
            min(FRB_CIE_Y_FACTOR * display_white, (ych_in[0] + ych_b[0]) / 2.0))
    new_c = frb_clip_chroma(display_white, y, ych_in[2], ych_in[3], ych_in[1])
    out = frb_ych_to_rgb((y, new_c, ych_in[2], ych_in[3]))
    return tuple(max(0.0, min(display_white, v)) for v in out)


def frb_gamut_mapping(ych_final, ych_original, display_black, display_white):
    yf = list(ych_final)
    yf[2] = ych_original[2]
    yf[3] = ych_original[3]
    yf[0] = max(FRB_CIE_Y_FACTOR * display_black,
                min(FRB_CIE_Y_FACTOR * display_white, yf[0]))
    yf = frb_desaturate_v4(ych_original, tuple(yf))
    yf = frb_gamut_check_yrg(yf)
    return frb_gamut_check_rgb(yf, display_black, display_white)


def filmic_norm_max_rgb(pix):
    return max(pix)


def filmic_v5_pixel(rgb, case, sp, output_power, norm_min, norm_max,
                    black_display, white_display):
    """filmic_chroma_v5 (filmic.cl:651-719) — one pixel, float64."""
    grey = 0.1845 if not case["custom_grey"] else case["grey_source"] / 100.0
    dr = sp["dr"]
    black = case["black_source"]
    sat = case["saturation"] / 100.0

    pix = rgb
    norm = max(filmic_norm_max_rgb(pix), norm_min)
    norm = min(norm, norm_max)
    ratios = tuple(v / norm for v in pix)
    norm = frb_log_encode(norm, grey, black, dr)
    norm = min(max(frb_spline_eval(norm, sp), black_display), white_display)
    norm = norm ** output_power
    norm = _f32(norm)
    max_rgb = tuple(norm * r for r in ratios)

    naive = []
    for c in range(3):
        v = frb_log_encode(pix[c], grey, black, dr)
        v = frb_spline_eval(v, sp)
        v = max(0.0, min(white_display, v))
        naive.append(v ** output_power)
    naive = tuple(naive)

    o = tuple((0.5 - sat) * naive[c] + (0.5 + sat) * max_rgb[c] for c in range(3))
    ych_original = frb_rgb_to_ych(pix)
    ych_final = frb_rgb_to_ych(o)
    ych_final = (ych_final[0], min(ych_original[1], ych_final[1]),
                 ych_final[2], ych_final[3])
    return frb_gamut_mapping(ych_final, ych_original, black_display, white_display)


def gen_filmic_refs(canonical_dir: str, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for case in FILMIC_CASES:
        effective_power = case["output_power"]
        if case["auto_hardness"]:
            effective_power = _f32(max(1.0, min(10.0, math.log(
                case["grey_target"] / 100.0)
                / math.log(-case["black_source"]
                           / (case["white_source"] - case["black_source"])))))
        sp = filmic_compute_spline(case, effective_power)
        grey = case["grey_source"] / 100.0 if case["custom_grey"] else 0.1845
        black_source = _f32(case["black_source"])
        bounds = (_f32(frb_exp_decode(0.0, grey, black_source, sp["dr"])),
                  _f32(frb_exp_decode(1.0, grey, black_source, sp["dr"])))
        black_display = _f32(_f32(sp["y"][0]) ** effective_power)
        white_display = _f32(_f32(sp["y"][4]) ** effective_power)
        for fixture in FILMIC_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)

            def px(x, y, rgb=rgb, case=case, sp=sp, w=w, op=effective_power,
                   bounds=bounds, bd=black_display, wd=white_display):
                idx = y * w + x
                return filmic_v5_pixel(
                    (rgb[0][idx], rgb[1][idx], rgb[2][idx]),
                    case, sp, op, bounds[0], bounds[1], bd, wd)

            write_exr(os.path.join(out_dir, f"{case['name']}__{fixture}.exr"), w, h, px)


# ──────────────────────────────────────────────────────────────────────
# AgX (Plan 03-06-T6, IOP-FILM-03) — dt_iop_agx_params_t v7, 144 bytes:
# look (5f) + range (3f) + curve (8f) + auto_gamma (i) + target ratios
# (2f) + base_primaries (i) + disable_primaries_adjustments (i) +
# inset/rotation (6f) + master (2f) + outset/unrotation (6f) +
# completely_reverse_primaries (i).
#
# Reference math (float64 transliteration of agx.c:470-1005
# _calculate_tone_mapping_params + the kernel_agx leg):
#   - compress_into_gamut (Blender luminance compensation)
#   - log encoding (0.18 mid-gray, [black_ev, range] normalisation)
#   - the sigmoid trapezoid curve (scaled sigmoid toe/shoulder + line)
#   - look (slope-lift/power/luma-saturation) when tuned
#   - gamma linearisation + the HSV hue restore lerp
# PRIMARIES: the default path (base Rec2020 == work, zero inset/rotation)
# has IDENTITY matrices; the primaries/look cases carry the recorded
# deviation (dt builds the luma matrix from the ICC D50 media white,
# Lightamer from Rec2020 primaries + D65 white — pinned against this
# dual implementation, not dt; 03-06-DECISIONS.md).
# ──────────────────────────────────────────────────────────────────────

AGX_PARAMS_FORMAT = "<16fi2fii6f2f6fi"
AGX_MODVERSION = 7
AGX_IOP_ORDER = 45.5
AGX_REF_FIXTURES = COLISA_REF_FIXTURES

AGX_EPSILON = 1e-6
AGX_DEFAULT_GAMMA = 2.2
AGX_BASE_EXPORT, AGX_BASE_WORK, AGX_BASE_REC2020, \
    AGX_BASE_P3, AGX_BASE_ADOBE, AGX_BASE_SRGB = range(6)


def _agx_default_case(**over):
    case = dict(
        name="agx_default",
        look_lift=0.0, look_slope=1.0, look_brightness=1.0,
        look_saturation=1.0, look_hue_mix=0.6,
        black_ev=-10.0, white_ev=6.5, dr_scaling=0.1,
        pivot_x=0.606060606061, pivot_y_linear=0.18, contrast=3.0,
        linear_below=0.0, linear_above=0.0, toe_power=1.5,
        shoulder_power=3.3, gamma=2.2, auto_gamma=0,
        target_black=0.0, target_white=1.0,
        base=AGX_BASE_REC2020, disable_primaries=0,
        insets=(0.0, 0.0, 0.0), rotations=(0.0, 0.0, 0.0),
        master_outset=1.0, master_unrotation=1.0,
        outsets=(0.0, 0.0, 0.0), unrotations=(0.0, 0.0, 0.0),
        reverse_primaries=0,
    )
    case.update(over)
    return case


AGX_CASES = [
    _agx_default_case(),
    _agx_default_case(name="agx_no_hue", look_hue_mix=0.0),
    _agx_default_case(name="agx_contrast", contrast=5.0),
    _agx_default_case(name="agx_linear_zone", linear_below=0.2, linear_above=0.2),
    _agx_default_case(name="agx_look", look_brightness=1.5, look_saturation=1.2),
    _agx_default_case(name="agx_primaries",
                      insets=(0.1, 0.05, 0.15),
                      rotations=(0.05, -0.03, 0.04)),
]


def agx_params_blob(case) -> str:
    packed = struct.pack(
        AGX_PARAMS_FORMAT,
        case["look_lift"], case["look_slope"], case["look_brightness"],
        case["look_saturation"], case["look_hue_mix"],
        case["black_ev"], case["white_ev"], case["dr_scaling"],
        case["pivot_x"], case["pivot_y_linear"], case["contrast"],
        case["linear_below"], case["linear_above"],
        case["toe_power"], case["shoulder_power"], case["gamma"],
        case["auto_gamma"],
        case["target_black"], case["target_white"],
        case["base"],
        case["disable_primaries"],
        case["insets"][0], case["rotations"][0],
        case["insets"][1], case["rotations"][1],
        case["insets"][2], case["rotations"][2],
        case["master_outset"], case["master_unrotation"],
        case["outsets"][0], case["unrotations"][0],
        case["outsets"][1], case["unrotations"][1],
        case["outsets"][2], case["unrotations"][2],
        case["reverse_primaries"],
    )
    assert len(packed) == 144, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def agx_tone_mapping_params(case):
    """agx.c:794-964 float64."""
    p = {}
    # look
    p["look_lift"] = case["look_lift"]
    p["look_slope"] = case["look_slope"]
    p["look_saturation"] = case["look_saturation"]
    brightness = case["look_brightness"]
    p["look_power"] = 1.0 / math.sqrt(max(brightness, AGX_EPSILON)) if brightness < 1 else 1.0 / brightness
    p["look_tuned"] = (case["look_slope"] != 1.0 or case["look_brightness"] != 1.0
                       or case["look_lift"] != 0.0 or case["look_saturation"] != 1.0)
    p["restore_hue"] = case["look_hue_mix"] != 0.0
    # log mapping
    p["black_relative_ev"] = case["black_ev"]
    p["white_relative_ev"] = case["white_ev"]
    p["range_in_ev"] = p["white_relative_ev"] - p["black_relative_ev"]
    # pivot + gamma
    p["pivot_x"] = max(AGX_EPSILON, min(case["pivot_x"], 1.0 - AGX_EPSILON))
    if case["auto_gamma"]:
        p["curve_gamma"] = (
            math.log2(case["pivot_y_linear"]) / math.log2(p["pivot_x"])
            if p["pivot_x"] > 0.0 and case["pivot_y_linear"] > 0.0
            else case["gamma"]
        )
    else:
        p["curve_gamma"] = case["gamma"]

    def pivot_y_at(gamma):
        return pow(max(case["target_black"], min(case["pivot_y_linear"], case["target_white"])),
                   1.0 / gamma)

    p["pivot_y"] = pivot_y_at(p["curve_gamma"])
    # slope
    range_adjusted_slope = case["contrast"] * (p["range_in_ev"] / 16.5)
    py_default = pivot_y_at(AGX_DEFAULT_GAMMA)
    deriv_current = p["curve_gamma"] * pow(max(AGX_EPSILON, p["pivot_y"]), p["curve_gamma"] - 1.0)
    deriv_default = AGX_DEFAULT_GAMMA * pow(max(AGX_EPSILON, py_default), AGX_DEFAULT_GAMMA - 1.0)
    p["slope"] = range_adjusted_slope / (deriv_current / deriv_default)
    # toe
    p["target_black"] = pow(case["target_black"], 1.0 / p["curve_gamma"])
    p["toe_power"] = max(0.01, case["toe_power"])
    remaining_y_below = p["pivot_y"] - p["target_black"]
    toe_length_y = remaining_y_below * case["linear_below"]
    dx_below = toe_length_y / p["slope"]
    p["toe_transition_x"] = max(AGX_EPSILON, p["pivot_x"] - dx_below)
    dx_below = p["pivot_x"] - p["toe_transition_x"]
    toe_dy_below = p["slope"] * dx_below
    p["toe_transition_y"] = p["pivot_y"] - toe_dy_below
    inv_limit_x = 1.0
    inv_limit_y = 1.0 - p["target_black"]
    inv_tx = 1.0 - p["toe_transition_x"]
    inv_ty = 1.0 - p["toe_transition_y"]
    p["toe_scale"] = -_agx_scale(inv_limit_x, inv_limit_y, inv_tx, inv_ty,
                                 p["slope"], p["toe_power"])
    toe_length_x = p["toe_transition_x"]
    toe_dy_to_limit = max(AGX_EPSILON, p["toe_transition_y"] - p["target_black"])
    toe_slope_to_limit = toe_dy_to_limit / toe_length_x
    p["need_convex_toe"] = toe_slope_to_limit > p["slope"]
    p["toe_fallback_power"] = p["slope"] * toe_length_x / toe_dy_to_limit
    p["toe_fallback_coefficient"] = toe_dy_to_limit / (toe_length_x ** p["toe_fallback_power"])
    p["intercept"] = p["toe_transition_y"] - p["slope"] * p["toe_transition_x"]
    # shoulder
    p["target_white"] = pow(case["target_white"], 1.0 / p["curve_gamma"])
    remaining_y_above = p["target_white"] - p["pivot_y"]
    shoulder_length_y = remaining_y_above * case["linear_above"]
    dx_above = shoulder_length_y / p["slope"]
    p["shoulder_transition_x"] = min(1.0 - AGX_EPSILON, p["pivot_x"] + dx_above)
    dx_above = p["shoulder_transition_x"] - p["pivot_x"]
    shoulder_dy_above = p["slope"] * dx_above
    p["shoulder_transition_y"] = p["pivot_y"] + shoulder_dy_above
    p["shoulder_power"] = max(0.01, case["shoulder_power"])
    p["shoulder_scale"] = _agx_scale(1.0, p["target_white"],
                                     p["shoulder_transition_x"], p["shoulder_transition_y"],
                                     p["slope"], p["shoulder_power"])
    shoulder_length_x = 1.0 - p["shoulder_transition_x"]
    shoulder_dy_to_limit = max(AGX_EPSILON, p["target_white"] - p["shoulder_transition_y"])
    shoulder_slope_to_limit = shoulder_dy_to_limit / shoulder_length_x
    p["need_concave_shoulder"] = shoulder_slope_to_limit > p["slope"]
    p["shoulder_fallback_power"] = p["slope"] * shoulder_length_x / shoulder_dy_to_limit
    p["shoulder_fallback_coefficient"] = shoulder_dy_to_limit / (shoulder_length_x ** p["shoulder_fallback_power"])
    return p


def _agx_scale(limit_x, limit_y, transition_x, transition_y, slope, power):
    projected_rise = slope * max(AGX_EPSILON, limit_x - transition_x)
    actual_rise = max(AGX_EPSILON, limit_y - transition_y)
    tpr = projected_rise ** (-power)
    tar = actual_rise ** (-power)
    base = max(AGX_EPSILON, tar - tpr)
    return min(1e9, base ** (-1.0 / power))


def _agx_sigmoid(x, power):
    return x / (1.0 + x ** power) ** (1.0 / power)


def _agx_scaled_sigmoid(x, scale, slope, power, tx, ty):
    return scale * _agx_sigmoid(slope * (x - tx) / scale, power) + ty


def _agx_apply_curve(x, p):
    if x < p["toe_transition_x"]:
        if p["need_convex_toe"]:
            result = p["target_black"] if x < 0.0 else p["target_black"] + max(
                0.0, p["toe_fallback_coefficient"] * x ** p["toe_fallback_power"])
        else:
            result = _agx_scaled_sigmoid(x, p["toe_scale"], p["slope"], p["toe_power"],
                                         p["toe_transition_x"], p["toe_transition_y"])
    elif x <= p["shoulder_transition_x"]:
        result = p["slope"] * x + p["intercept"]
    else:
        if p["need_concave_shoulder"]:
            result = (p["target_white"] if x >= 1.0
                      else p["target_white"] - max(0.0, p["shoulder_fallback_coefficient"]
                                                   * (1.0 - x) ** p["shoulder_fallback_power"]))
        else:
            result = _agx_scaled_sigmoid(x, p["shoulder_scale"], p["slope"], p["shoulder_power"],
                                         p["shoulder_transition_x"], p["shoulder_transition_y"])
    return max(p["target_black"], min(p["target_white"], result))


def _agx_compress_into_gamut(pixel):
    coeffs = (0.2658180370250449, 0.59846986045365, 0.1357121025213052)
    input_y = sum(coeffs[c] * pixel[c] for c in range(3))
    max_rgb = max(pixel)
    opponent = tuple(max_rgb - pixel[c] for c in range(3))
    opponent_y = sum(coeffs[c] * opponent[c] for c in range(3))
    max_opponent = max(opponent)
    y_compensate = max_opponent - opponent_y + input_y
    min_rgb = min(pixel)
    offset = max(-min_rgb, 0.0)
    rgb_offset = tuple(v + offset for v in pixel)
    max_offset = max(rgb_offset)
    opponent_offset = tuple(max_offset - v for v in rgb_offset)
    max_inv = max(opponent_offset)
    y_inv = sum(coeffs[c] * opponent_offset[c] for c in range(3))
    y_new = sum(coeffs[c] * rgb_offset[c] for c in range(3))
    y_new = max_inv - y_inv + y_new
    ratio = (y_compensate / y_new) if (y_new > y_compensate and y_new > AGX_EPSILON) else 1.0
    return tuple(ratio * v for v in rgb_offset)


def _agx_rgb2hsv(rgb):
    mn, mx = min(rgb), max(rgb)
    delta = mx - mn
    v = mx
    if abs(mx) > 1e-6 and abs(delta) > 1e-6:
        s = delta / mx
        if rgb[0] == mx:
            hue = (rgb[1] - rgb[2]) / delta
        elif rgb[1] == mx:
            hue = 2.0 + (rgb[2] - rgb[0]) / delta
        else:
            hue = 4.0 + (rgb[0] - rgb[1]) / delta
        hue /= 6.0
        h = hue - math.floor(hue)
    else:
        s, h = 0.0, 0.0
    return (h, s, v)


def _agx_hsv2rgb(hsv):
    h, s, v = hsv
    c = s * v
    m = v - c
    hh = h * 6.0
    i = math.floor(hh)
    f = hh - i
    fc = f * c
    top = c + m
    inc = fc + m
    dec = top - fc
    idx = int(i)
    if idx == 0:
        return (top, inc, m)
    if idx == 1:
        return (dec, top, m)
    if idx == 2:
        return (m, top, inc)
    if idx == 3:
        return (m, dec, top)
    if idx == 4:
        return (inc, m, top)
    return (top, m, dec)


def _agx_lerp_hue(original, processed, mix):
    shortest = processed - original
    shortest -= round(shortest)
    mixed = (1.0 - mix) * shortest + original
    return mixed - math.floor(mixed)


# AgX look luminance: Rec2020 primaries + D65 white via the Lindbloom
# builder (SigmoidProfile semantics — the recorded deviation; dt uses the
# base ICC's D50 media white, only reachable when look_tuned).
_AGX_REC2020_RGB_XYZ = sg_build_rgb_to_xyz(
    SG_REC2020_PRIMARIES, (0.3127, 0.3290))


def _agx_look(pixel, p):
    slope, lift = p["look_slope"], p["look_lift"]
    power, sat = p["look_power"], p["look_saturation"]
    out = []
    for c in range(3):
        m = slope / (1.0 + lift)
        b = lift * m
        v = m * pixel[c] + b
        out.append(v ** power if v > 0.0 else v)
    xyz = mat_vec(_AGX_REC2020_RGB_XYZ, tuple(out))
    luma = xyz[1]
    return tuple(luma + sat * (out[c] - luma) for c in range(3))


def agx_pixel(rgb, case, p):
    """kernel_agx — the default-path primaries are identity (base Rec2020
    == work, zero inset/rotation OR disable_primaries), so the reference
    skips the matrix legs (the agx_primaries case is dual-impl-pinned via
    the Swift side only, NOT exercised here)."""
    base = _agx_compress_into_gamut(rgb)
    h_before = 0.0
    if p["restore_hue"]:
        h_before = _agx_rgb2hsv(base)[0]
    transformed = []
    for c in range(3):
        x_rel = max(AGX_EPSILON, base[c] / 0.18)
        mapped = max(0.0, min(1.0, (math.log2(max(x_rel, 0.0)) - p["black_relative_ev"])
                              / p["range_in_ev"]))
        transformed.append(_agx_apply_curve(mapped, p))
    if p["look_tuned"]:
        transformed = list(_agx_look(tuple(transformed), p))
    transformed = [max(0.0, v) ** p["curve_gamma"] for v in transformed]
    if p["restore_hue"]:
        h_after = _agx_rgb2hsv(tuple(transformed))[0]
        h_after = _agx_lerp_hue(h_before, h_after, case["look_hue_mix"])
        return _agx_hsv2rgb((h_after, _agx_rgb2hsv(tuple(transformed))[1],
                             _agx_rgb2hsv(tuple(transformed))[2]))
    return tuple(transformed)


def gen_agx_refs(canonical_dir: str, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for case in AGX_CASES:
        if case["insets"] != (0.0, 0.0, 0.0) or case["rotations"] != (0.0, 0.0, 0.0):
            # The primaries case carries the recorded matrix deviation —
            # it is pinned by the Swift↔Swift dual implementation in
            # AgXTests, not by a synthesized per-pixel EXR reference.
            continue
        p = agx_tone_mapping_params(case)
        for fixture in AGX_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)

            def px(x, y, rgb=rgb, case=case, p=p, w=w):
                idx = y * w + x
                return agx_pixel((rgb[0][idx], rgb[1][idx], rgb[2][idx]), case, p)

            write_exr(os.path.join(out_dir, f"{case['name']}__{fixture}.exr"), w, h, px)


if __name__ == "__main__":
    main()

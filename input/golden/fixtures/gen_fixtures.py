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
    """dt NEAREST LUT index: uint(max(x,0) * 0x10000) clamped to 0xffff."""
    if x <= 0.0:
        return 0
    return min(int(x * 0x10000), 0xFFFF)


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
        # Plan 03-03-T2: colisa golden references (same L017 route).
        gen_colisa_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))

    print(f"gen_fixtures[{mode}] → {outdir}")


if __name__ == "__main__":
    main()

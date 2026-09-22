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
import random
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


def gen_gradient_ramp(outdir: str) -> None:
    # 64×64 HORIZONTAL gradient ramp 0..1 (ashift warp 靶 — the warp
    # sampler's per-pixel identity is only provable on varying content;
    # v(x) = x/63 floats, written raw = canonical (no Rec709 pre-image:
    # warp fixtures bypass the dt round-trip entirely, L017 route).
    # NOTE: the ramp_8ev fixture keeps its power-of-two grid for the
    # exposure probe; this linear ramp serves the warp parity (uniform
    # texel spacing ⇒ bilinear weights land mid-tap, max interpolation
    # signal).
    write_exr(
        os.path.join(outdir, "gradient_ramp.exr"), 64, 64,
        lambda x, y: (x / 63.0, x / 63.0, x / 63.0),
    )


def gen_checkerboard(outdir: str) -> None:
    # 64×64 checkerboard, 8px cells (warp aliasing/visibility 靶 — a
    # rotated checkerboard shows sampling breakage as smeared cells;
    # binary values make any smoothing exactly measurable).
    write_exr(
        os.path.join(outdir, "checkerboard.exr"), 64, 64,
        lambda x, y: (1.0, 1.0, 1.0) if ((x // 8) + (y // 8)) % 2 == 0 else (0.0, 0.0, 0.0),
    )


# ──────────────────────────────────────────────────────────────────────
# Phase 5 denoise fixtures (Plan 05-01-T5) — 加噪器 + hue/delta/torture
# ──────────────────────────────────────────────────────────────────────
#
# 加噪器：`poisson_gaussian_noise(img, a, b, seed)` —— `var = a·I + b`
# （dt noiseprofiles.json 标定域 = 传感器线性域，RESEARCH §2），
# `random.Random(seed)` 高斯流（stdlib 确定性：同 seed → 逐值一致；
# 高斯近似 Poisson-Gaussian —— 剖面加噪的工程惯例，方差精确、均值无偏）。
# 逐通道独立（R/G/B 各自流）。输出走既有 uncompressed writer（float32）。
#
# Gaussians via Box-Muller over random.Random (stdlib-only — the fixture
# generator stays zero-dependency like the rest of this file).


def _gauss_stream(seed: int):
    rng = random.Random(seed)
    while True:
        u1 = max(rng.random(), 1e-12)
        u2 = rng.random()
        r = math.sqrt(-2.0 * math.log(u1))
        yield r * math.cos(2.0 * math.pi * u2)
        yield r * math.sin(2.0 * math.pi * u2)


def poisson_gaussian_noise(img, a, b, seed):
    """逐通道 Poisson-Gaussian 加噪：`out = img + N(0, a·I + b)`。
    `img` = (R, G, B) 三通道行主序 float 列表；`a`/`b` = 三元组；
    `seed` = 整数种子（通道 c 用 seed+c 独立流）。返回同形三通道列表。
    """
    out = []
    for c in range(3):
        g = _gauss_stream(seed + c)
        ch = []
        for v in img[c]:
            var = max(a[c] * v + b[c], 0.0)
            ch.append(v + math.sqrt(var) * next(g))
        out.append(ch)
    return out


# 剖面钉参：ILCE-9M3 ISO 125 / ISO 1600（T3 规范化产物的真实档 —
# 加噪集的 a/b authority = bundle noiseprofiles.json；此处硬编码值
# 与 bundle 一致，统计检验以同值为准）。
NOISE_TIERS = (
    ("iso125", 125, (7.65705497686894e-06, 1.54601975602981e-06, 2.30077680147848e-06),
     (2.00608030560566e-09, 3.03636277807135e-09, 4.74823179066283e-09)),
    ("iso1600", 1600, (2.99037019802356e-05, 8.86355041404361e-06, 1.37779541937624e-05),
     (4.43124422276964e-08, 2.60617465248865e-08, 3.62731233591954e-08)),
)

NOISE_SEED = 20260921
NOISE_SOURCES = ("ramp_8ev", "flat_-4ev", "flat_-8ev", "gray_staircase")


def gen_noisy_fixtures(outdir: str, canonical_dir: str = "") -> None:
    """加噪 fixture 集：canonical 子集（≥3 张）× 真实剖面档 2 档 → ≥6 张。
    源图读 canonical EXR（`read_exr_rgb`），加噪后写
    `<src>__noisy_<tier>_s<seed>.exr`。manifest 登记种子与剖面参数。
    """
    base = canonical_dir or outdir
    for src in NOISE_SOURCES:
        w, h, rgb = read_exr_rgb(os.path.join(base, src + ".exr"))
        for tier, iso, a, b in NOISE_TIERS:
            noisy = poisson_gaussian_noise(rgb, a, b, NOISE_SEED)
            name = f"{src}__noisy_{tier}_s{NOISE_SEED}.exr"

            def px(x, y, w=w, noisy=noisy):
                idx = y * w + x
                return (noisy[0][idx], noisy[1][idx], noisy[2][idx])

            write_exr(os.path.join(outdir, name), w, h, px)


def gen_hue_sweep(outdir: str) -> None:
    """hue 全环 sweep 渐变（色相域覆盖，喂自研 parity —— 无 L017 风险）：
    360×64，H = x/360 全环（S=V=1 HSV→RGB），中性行锚定。
    05-04 PEDELTA: S = 0.999（非 1.0）——纯 HSV 主色在 fixture 中含精确 0.0
    通道，相对误差在该通道上退化（除 ~0），恒等/近恒等 parity 的 maxRel
    被钉在 1e2 量级空转。0.999 饱和度保持全环 hue 覆盖（C ≈ 127.9/128），
    同时最小通道 ≈ 0.001，相对度量全程良态。
    """

    def px(x, y):
        h = (x % 360) / 360.0
        return _hsv_to_rgb(h, 0.999, 1.0)

    write_exr(os.path.join(outdir, "hue_sweep.exr"), 360, 64, px)

def _hsv_to_rgb(h, s, v):
    i = int(h * 6.0) % 6
    f = h * 6.0 - int(h * 6.0)
    p, q, t = v * (1.0 - s), v * (1.0 - f * s), v * (1.0 - (1.0 - f) * s)
    if i == 0:
        return (v, t, p)
    if i == 1:
        return (q, v, p)
    if i == 2:
        return (p, v, t)
    if i == 3:
        return (p, q, v)
    if i == 4:
        return (t, p, v)
    return (v, p, q)


def gen_delta_impulse(outdir: str) -> None:
    """delta 脉冲图（nlmeans/bilateral 核响应）：64×64 中灰 0.18 上单白脉冲
    （中心 1.0）+ 单黑脉冲（1/4 处 0.0）——核支撑/响应的直接探针。
    """
    w = h = 64

    def px(x, y):
        if x == 32 and y == 32:
            return (1.0, 1.0, 1.0)
        if x == 16 and y == 16:
            return (0.0, 0.0, 0.0)
        return (0.18, 0.18, 0.18)

    write_exr(os.path.join(outdir, "delta_impulse.exr"), w, h, px)


def gen_shadow_torture(outdir: str) -> None:
    """深阴影噪声 torture crop（SC#3 torture 直指，64-128px 级）：
    96×96 深阴影梯度（2^-8..2^-5）叠加 ISO 1600 档噪声（种子化）——
    denoise 最难区的直接靶。
    """
    w = h = 96
    base = []
    for y in range(h):
        for x in range(w):
            v = 2.0 ** (-8.0 + 3.0 * (x + y) / (w + h - 2))
            base.append(v)
    img = [list(base), list(base), list(base)]
    _, _, a, b = NOISE_TIERS[1]
    noisy = poisson_gaussian_noise(img, a, b, NOISE_SEED + 7)

    def px(x, y, w=w, noisy=noisy):
        idx = y * w + x
        return (noisy[0][idx], noisy[1][idx], noisy[2][idx])

    write_exr(os.path.join(outdir, "shadow_torture.exr"), w, h, px)


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


# ──────────────────────────────────────────────────────────────────────
# Crop + flip (Plan 04-02-T3) — dt_iop_crop_params_t v3 (24 bytes:
# cx/cy/cw/ch floats + ratio_n/ratio_d ints) + dt_iop_flip_params_t v2
# (4 bytes: orientation int). L017 route: dt-cli float export is
# spatially corrupt on this host (ramp PFM/EXR probe 2026-09-20), so
# track-A references are CPU-synthesized below; dt-side evidence = XMP
# adoption (DB op_params hex + "params v. N ok") + flat probes.
# ──────────────────────────────────────────────────────────────────────

CROP_PARAMS_FORMAT = "<ffffii"
CROP_MODVERSION = 3
CROP_IOP_ORDER = 24.5

FLIP_PARAMS_FORMAT = "<i"
FLIP_MODVERSION = 2
FLIP_IOP_ORDER = 16.0


def crop_params_blob(cx, cy, cw, ch, ratio_n=-1, ratio_d=-1) -> str:
    """dt_iop_crop_params_t v3 → lowercase HEX ASCII (24 bytes)."""
    packed = struct.pack(CROP_PARAMS_FORMAT, cx, cy, cw, ch, ratio_n, ratio_d)
    assert len(packed) == 24, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def flip_params_blob(orientation) -> str:
    """dt_iop_flip_params_t v2 → lowercase HEX ASCII (4 bytes)."""
    packed = struct.pack(FLIP_PARAMS_FORMAT, orientation)
    assert len(packed) == 4, len(packed)
    return binascii.hexlify(packed).decode("ascii")


# The crop 钉参组 (plan T3 action 2): full-frame / center 50% / 3:2-ratio
# center window (ratio bits ride inert until the Phase-11 export aligner;
# the overlay enforces the ratio at edit time).
CROP_CASES = [
    # (case name, cx, cy, cw, ch, ratio_n, ratio_d)
    ("crop_full", 0.0, 0.0, 1.0, 1.0, -1, -1),
    ("crop_center50", 0.25, 0.25, 0.75, 0.75, -1, -1),
    ("crop_3x2", 0.25, 0.25, 0.75, 0.75, 2, 3),
]

# The flip 钉参组 (plan T3 action 2): none / flipH / flipV / rotCCW90 —
# the 4 representative states (the other 4 ride the same kernel path;
# FlipParityTests covers all 8 in-pipe).
FLIP_CASES = [
    # (case name, orientation bits)
    ("flip_none", 0),
    ("flip_h", 2),
    ("flip_v", 1),
    ("flip_ccw90", 6),
]
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
    for name, cx, cy, cw, ch, rn, rd in CROP_CASES:
        params = crop_params_blob(cx, cy, cw, ch, rn, rd)
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION,
            iop_order_version=5,
            operation="crop",
            modversion=CROP_MODVERSION,
            params=params,
            iop_order=f"{CROP_IOP_ORDER:.1f}",
        )
        with open(os.path.join(outdir, name + ".xmp"), "w") as f:
            f.write(xmp)
    for name, orientation in FLIP_CASES:
        params = flip_params_blob(orientation)
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION,
            iop_order_version=5,
            operation="flip",
            modversion=FLIP_MODVERSION,
            params=params,
            iop_order=f"{FLIP_IOP_ORDER:.1f}",
        )
        with open(os.path.join(outdir, name + ".xmp"), "w") as f:
            f.write(xmp)
    gen_ashift_cases(outdir)
    gen_detail_cases(outdir)


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


# Fixtures the crop/flip references cover: the ramp (spatially varying —
# the window/remap identity is only provable on varying content) + the
# uniform flats (dt trustworthy there; doubles as the probe cross-check).
CROP_FLIP_REF_FIXTURES = [
    "ramp_8ev", "flat_0ev", "flat_-4ev", "gray_staircase",
]


def _crop_window(w, h, cx, cy, cw, ch):
    """dt crop.c:517-531 forward (minus the Phase-11 export aligner)."""
    x = max(0, int(w * cx))
    y = max(0, int(h * cy))
    ww = max(4, int(w * (cw - cx)))
    hh = max(4, int(h * (ch - cy)))
    return x, y, ww, hh


def _flip_remap(x, y, w, h, orientation):
    """dt basic.cl:2948-2960 forward map (flip X/Y, then swap)."""
    ox = (w - x - 1) if (orientation & 2) else x
    oy = (h - y - 1) if (orientation & 1) else y
    if orientation & 4:
        ox, oy = oy, ox
    return ox, oy


def gen_crop_refs(canonical_dir: str, out_dir: str) -> None:
    """Synthesize the crop golden REFERENCES: the canonical fixture's
    crop window (dt forward math above), written with this script's EXR
    writer. The reference SHAPE is the window (ww × hh) — the Lightamer
    leg renders `[crop]` through the pipe and compares same-size planes.
    """
    os.makedirs(out_dir, exist_ok=True)
    for case_name, cx, cy, cw, ch, _rn, _rd in CROP_CASES:
        for fixture in CROP_FLIP_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)
            x0, y0, ww, hh = _crop_window(w, h, cx, cy, cw, ch)

            def px(x, y, rgb=rgb, w=w, x0=x0, y0=y0):
                idx = (y + y0) * w + (x + x0)
                return (rgb[0][idx], rgb[1][idx], rgb[2][idx])

            write_exr(os.path.join(out_dir, f"{case_name}__{fixture}.exr"), ww, hh, px)


def gen_flip_refs(canonical_dir: str, out_dir: str) -> None:
    """Synthesize the flip golden REFERENCES: the canonical fixture
    remapped by the dt kernel swizzle (90° states transpose the shape).
    """
    os.makedirs(out_dir, exist_ok=True)
    for case_name, orientation in FLIP_CASES:
        for fixture in CROP_FLIP_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)
            ow, oh = (h, w) if (orientation & 4) else (w, h)

            def px(x, y, rgb=rgb, w=w, h=h, ow=ow, oh=oh, orientation=orientation):
                # Output (x,y) reads input = backward map (swap, then
                # flip against the POST-swap = output dims).
                sx, sy = x, y
                sw, sh = ow, oh
                if orientation & 4:
                    sx, sy = sy, sx
                    sw, sh = sh, sw
                if orientation & 2:
                    sx = sw - sx - 1
                if orientation & 1:
                    sy = sh - sy - 1
                idx = sy * w + sx
                return (rgb[0][idx], rgb[1][idx], rgb[2][idx])

            write_exr(os.path.join(out_dir, f"{case_name}__{fixture}.exr"), ow, oh, px)


# ──────────────────────────────────────────────────────────────────────
# Ashift warp (Plan 04-03-T4) — dt _homography (ashift.c:756-979, GENERIC
# fold) in float64 + texel-center bilinear with clamped taps +
# transparent-outside, mirroring AshiftKernels.metal + Homography.swift
# formula-for-formula (L017 route ① — warp is a spatial operator, dt-cli
# float export spatially corrupt on this host; dt-side evidence = XMP
# adoption + flat rotation probe, manifest §ashift).
#
# Frame convention (L020, Homography.swift header): forward matrix maps
# bufIn-frame → full-output-frame (step-10 offset included); the module's
# modifyROIOut keeps x/y and resizes to the forward AABB × clip; process
# re-bases per pixel (oroi + clip → Hinv → −iroi). The reference below
# renders the FULL pipeline contract: forward AABB sizing + inverse warp.
# ──────────────────────────────────────────────────────────────────────

ASHIFT_MODVERSION = 5
ASHIFT_IOP_ORDER = 15.0
ASHIFT_PARAMS_FORMAT = "<ffffffffii4f200fi8f"


def ashift_params_blob(rotation, lensshift_v=0.0, lensshift_h=0.0, shear=0.0,
                       f_length=28.0, crop_factor=1.0, mode=0, cropmode=0,
                       cl=0.0, cr=1.0, ct=0.0, cb=1.0) -> str:
    """dt_iop_ashift_params_t v5 → lowercase HEX ASCII.

    v5 layout: rotation/lensshift_v/lensshift_h/shear/f_length/
    crop_factor/orthocorr/aspect (8f) + mode/cropmode (ii) + cl/cr/ct/cb
    (4f) + last_drawn_lines[200] (200f) + count (i) + last_quad_lines[8]
    (8f). GENERIC cases pin orthocorr=0/aspect=1/mode=0/cropmode=0/lines=0.
    """
    floats = [rotation, lensshift_v, lensshift_h, shear, f_length,
              crop_factor, 0.0, 1.0]
    ints = [mode, cropmode]
    clip = [cl, cr, ct, cb]
    lines = [0.0] * 200
    quad = [0.0] * 8
    packed = struct.pack(
        "<ffffffffii4f200fi8f",
        *(floats + ints + clip + lines + [0] + quad))
    assert len(packed) == 8 * 4 + 2 * 4 + 4 * 4 + 200 * 4 + 4 + 8 * 4, len(packed)
    return binascii.hexlify(packed).decode("ascii")


# The ashift 钉参组 (plan T4 action 2): identity / ±rotations /
# rot+shift / perspective-ish shear+shift / inner-clip window.
ASHIFT_CASES = [
    # (case name, rotation, lensshift_v, lensshift_h, shear, cl, cr, ct, cb)
    ("ashift_identity", 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0),
    ("ashift_rot08", 8.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0),
    ("ashift_rot-08", -8.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0),
    ("ashift_rot30", 30.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0),
    ("ashift_rot08_shift", 8.0, 0.15, -0.1, 0.0, 0.0, 1.0, 0.0, 1.0),
    ("ashift_persp", 0.0, 0.3, 0.0, 0.08, 0.0, 1.0, 0.0, 1.0),
    ("ashift_clip", 8.0, 0.0, 0.0, 0.0, 0.1, 0.9, 0.05, 0.95),
]

ASHIFT_REF_FIXTURES = [
    "gradient_ramp", "flat_0ev", "flat_-4ev", "checkerboard",
]


def _ashift_mat_mul(a, b):
    """dt mat3mul (math.h:213-228): dest = a * b, row-major."""
    o = [0.0] * 9
    for k in range(3):
        for i in range(3):
            s = 0.0
            for j in range(3):
                s += a[3 * k + j] * b[3 * j + i]
            o[3 * k + i] = s
    return o


def _ashift_compose(rotation, shift_v, shift_h, shear, f_length_kb, width, height):
    """dt _homography (ashift.c:756-979) GENERIC fold in float64 — mirrors
    Homography.compose step-for-step (steps 5/8/9 run identity arithmetic).
    Returns the FORWARD row-major 3×3."""
    u, v = float(width), float(height)
    phi = math.radians(rotation)
    cosi, sini = math.cos(phi), math.sin(phi)
    exppa_v = math.exp(shift_v)
    fdb_v = f_length_kb / (14.4 + (v / u - 1.0) * 7.2)
    rad_v = fdb_v * (exppa_v - 1.0) / (exppa_v + 1.0)
    alpha_v = max(min(math.atan(rad_v), 1.5), -1.5)
    exppa_h = math.exp(shift_h)
    minput = [0, 1, 0, 1, 0, 0, 0, 0, 1]
    mwork = [cosi, -sini, -0.5 * v * cosi + 0.5 * u * sini + 0.5 * v,
             sini, cosi, -0.5 * v * sini - 0.5 * u * cosi + 0.5 * u,
             0, 0, 1]
    moutput = _ashift_mat_mul(mwork, minput)
    mwork = [1, shear, 0, shear, 1, 0, 0, 0, 1]
    moutput = _ashift_mat_mul(mwork, moutput)
    mwork = [exppa_v, 0, 0,
             0.5 * ((exppa_v - 1.0) * u) / v, 2.0 * exppa_v / (exppa_v + 1.0),
             -0.5 * ((exppa_v - 1.0) * u) / (exppa_v + 1.0),
             (exppa_v - 1.0) / v, 0, 1]
    moutput = _ashift_mat_mul(mwork, moutput)
    mwork = [1, 0, 0, 0, 1, 0.5 * u * 0.0, 0, 0, 1]
    moutput = _ashift_mat_mul(mwork, moutput)
    mwork = [0, 1, 0, 1, 0, 0, 0, 0, 1]
    moutput = _ashift_mat_mul(mwork, moutput)
    mwork = [exppa_h, 0, 0,
             0.5 * ((exppa_h - 1.0) * v) / u, 2.0 * exppa_h / (exppa_h + 1.0),
             -0.5 * ((exppa_h - 1.0) * v) / (exppa_h + 1.0),
             (exppa_h - 1.0) / u, 0, 1]
    moutput = _ashift_mat_mul(mwork, moutput)
    mwork = [1, 0, 0, 0, 1, 0.5 * v * 0.0, 0, 0, 1]
    moutput = _ashift_mat_mul(mwork, moutput)
    mwork = [1, 0, 0, 0, 1, 0, 0, 0, 1]
    moutput = _ashift_mat_mul(mwork, moutput)
    corners = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)] \
        if width > 1 and height > 1 else [(0, 0)]
    umin = min((_ashift_apply(moutput, x, y)[0] / _ashift_apply(moutput, x, y)[2]) for x, y in corners)
    vmin = min((_ashift_apply(moutput, x, y)[1] / _ashift_apply(moutput, x, y)[2]) for x, y in corners)
    moutput = _ashift_mat_mul([1, 0, -umin, 0, 1, -vmin, 0, 0, 1], moutput)
    return moutput


def _ashift_apply(m, x, y):
    return (m[0] * x + m[1] * y + m[2],
            m[3] * x + m[4] * y + m[5],
            m[6] * x + m[7] * y + m[8])


def _ashift_project(m, x, y):
    a, b, w = _ashift_apply(m, x, y)
    return (a / w, b / w)


def _ashift_invert(m):
    """dt mat3inv (matrices.c:53-88) in float64."""
    def A(y, x):
        return m[(y - 1) * 3 + (x - 1)]
    det = (A(1, 1) * (A(3, 3) * A(2, 2) - A(3, 2) * A(2, 3))
           - A(2, 1) * (A(3, 3) * A(1, 2) - A(3, 2) * A(1, 3))
           + A(3, 1) * (A(2, 3) * A(1, 2) - A(2, 2) * A(1, 3)))
    assert abs(det) >= 1e-7, "singular homography in fixture synthesis"
    inv = 1.0 / det
    return [
        inv * (A(3, 3) * A(2, 2) - A(3, 2) * A(2, 3)),
        -inv * (A(3, 3) * A(1, 2) - A(3, 2) * A(1, 3)),
        inv * (A(2, 3) * A(1, 2) - A(2, 2) * A(1, 3)),
        -inv * (A(3, 3) * A(2, 1) - A(3, 1) * A(2, 3)),
        inv * (A(3, 3) * A(1, 1) - A(3, 1) * A(1, 3)),
        -inv * (A(2, 3) * A(1, 1) - A(2, 1) * A(1, 3)),
        inv * (A(3, 2) * A(2, 1) - A(3, 1) * A(2, 2)),
        -inv * (A(3, 2) * A(1, 1) - A(3, 1) * A(1, 2)),
        inv * (A(2, 2) * A(1, 1) - A(2, 1) * A(1, 2)),
    ]


def _ashift_bilinear(src_rgb, w, h, sx, sy):
    """Pixel-center bilinear with clamped taps; None when outside
    [-0.5, w-0.5) x [-0.5, h-0.5) — mirrors ashift_sample_clamped (D4).
    Integer coords hit texel centers exactly (identity-exact)."""
    if sx < -0.5 or sy < -0.5 or sx >= w - 0.5 or sy >= h - 0.5:
        return None
    fx = min(max(sx, 0.0), w - 1)
    fy = min(max(sy, 0.0), h - 1)
    x0, y0 = int(math.floor(fx)), int(math.floor(fy))
    x1, y1 = min(x0 + 1, w - 1), min(y0 + 1, h - 1)
    tx, ty = fx - x0, fy - y0

    def at(x, y):
        idx = y * w + x
        return (src_rgb[0][idx], src_rgb[1][idx], src_rgb[2][idx])
    p00, p10, p01, p11 = at(x0, y0), at(x1, y0), at(x0, y1), at(x1, y1)
    top = tuple(p00[c] + (p10[c] - p00[c]) * tx for c in range(3))
    bot = tuple(p01[c] + (p11[c] - p01[c]) * tx for c in range(3))
    return tuple(top[c] + (bot[c] - top[c]) * ty for c in range(3))


def gen_ashift_refs(canonical_dir: str, out_dir: str) -> None:
    """Synthesize the ashift golden REFERENCES: forward AABB sizing +
    inverse-homography bilinear warp over the canonical fixture bytes in
    float64 (the gate is <1e-5, warp class). Output shape = the forward
    AABB (x clip fraction) — the Lightamer leg renders [colorin, ashift]
    through the pipe and compares same-size planes. Transparent-outside
    pixels write (0,0,0) RGB (alpha rides separately — the RGBA leg is
    pinned in AshiftParityTests, not in these RGB EXRs)."""
    os.makedirs(out_dir, exist_ok=True)
    for case_name, rot, sv, sh, shear, cl, cr, ct, cb in ASHIFT_CASES:
        for fixture in ASHIFT_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)
            fwd = _ashift_compose(rot, sv, sh, shear, 28.0, w, h)
            corners = [(0.0, 0.0), (float(w), 0.0), (0.0, float(h)), (float(w), float(h))]
            proj = [_ashift_project(fwd, x, y) for x, y in corners]
            xs = [p[0] for p in proj]
            ys = [p[1] for p in proj]
            ow = max(4, int(math.floor((max(xs) - min(xs)) * (cr - cl))))
            oh = max(4, int(math.floor((max(ys) - min(ys)) * (cb - ct))))
            # Clip fullwidth recovery (mirrors AshiftModule.fullOutputSpan):
            # full = floor(span*frac)/frac over the bufIn rect.
            full_w = math.floor((max(xs) - min(xs)) * max(cr - cl, 1e-6)) / max(cr - cl, 1e-6)
            full_h = math.floor((max(ys) - min(ys)) * max(cb - ct, 1e-6)) / max(cb - ct, 1e-6)
            cx, cy = full_w * cl, full_h * ct
            inv = _ashift_invert(fwd)

            def px(x, y, rgb=rgb, w=w, h=h, inv=inv, cx=cx, cy=cy):
                ox, oy = float(x) + cx, float(y) + cy
                ix, iy = _ashift_project(inv, ox, oy)
                s = _ashift_bilinear(rgb, w, h, ix, iy)
                return s if s is not None else (0.0, 0.0, 0.0)

            write_exr(os.path.join(out_dir, f"{case_name}__{fixture}.exr"), ow, oh, px)


# ──────────────────────────────────────────────────────────────────────
# Lens warp (Plan 04-04-T4) — radial distortion + TCA + devignette in
# float64 + texel-center bilinear with clamped taps, mirroring
# LensKernels.metal `lens_manual_warp` + LensModule.forwardRadius
# formula-for-formula (L017 route ① — warp is a spatial operator, dt-cli
# float export spatially corrupt; lens has no dt-cli leg at all: no
# liblens* in this dt build is exercised — dt-side evidence = uniform
# probes in-test + XML resolve pins in LensfunDBTests).
#
# Frame convention (L020): forward map is input-frame → input-frame
# (distortion is self-contained — output == input frame, no homography);
# the module's modifyROIOut keeps x/y and the reference renders the same
# window the pipe negotiates (identity for lens: same-size planes).
# Radius unit: u = (p − c)/halfW, c = frame center, halfW = W/2.
# ──────────────────────────────────────────────────────────────────────

# The lens 钉参组 (plan T4 action 2): identity / ±distortion / CA /
# vignette / combined. Coefficients are KERNEL-unit (u = (p−c)/halfW);
# the XML→kernel normalization is pinned separately in LensfunDBTests.
LENS_CASES = [
    # (case name, dc1, dc2, dc3, dc4, tcaR_vr, tcaB_vb, vk1, vk2, vk3)
    ("lens_identity", 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0),
    ("lens_distort_barrel", 0.0, 0.08, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0),
    ("lens_distort_pincushion", 0.0, -0.08, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0),
    ("lens_distort_ptlens", 0.02, -0.03, 0.01, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0),
    ("lens_ca", 0.0, 0.0, 0.0, 0.0, 1.002, 0.998, 0.0, 0.0, 0.0),
    ("lens_vignette", 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, -0.5, 0.2, -0.05),
    ("lens_combo", 0.0, 0.05, 0.0, 0.01, 1.0015, 0.9985, -0.3, 0.1, -0.02),
]

LENS_REF_FIXTURES = [
    "gradient_ramp", "flat_0ev", "flat_-4ev", "checkerboard",
]


def _lens_forward_radius(ru, dc1, dc2, dc3, dc4):
    return ru * (1.0 + dc1 * ru + dc2 * ru * ru + dc3 * ru ** 3 + dc4 * ru ** 4)


def _lens_bilinear(src_rgb, w, h, sx, sy):
    """Pixel-center bilinear with clamped taps; always in-domain (lens
    clamps, never transparent) — mirrors lens_sample_clamped."""
    fx = min(max(sx, 0.0), w - 1)
    fy = min(max(sy, 0.0), h - 1)
    x0, y0 = int(math.floor(fx)), int(math.floor(fy))
    x1, y1 = min(x0 + 1, w - 1), min(y0 + 1, h - 1)
    tx, ty = fx - x0, fy - y0

    def at(x, y):
        idx = y * w + x
        return (src_rgb[0][idx], src_rgb[1][idx], src_rgb[2][idx])
    p00, p10, p01, p11 = at(x0, y0), at(x1, y0), at(x0, y1), at(x1, y1)
    top = tuple(p00[c] + (p10[c] - p00[c]) * tx for c in range(3))
    bot = tuple(p01[c] + (p11[c] - p01[c]) * tx for c in range(3))
    return tuple(top[c] + (bot[c] - top[c]) * ty for c in range(3))


def gen_lens_refs(canonical_dir: str, out_dir: str) -> None:
    """Synthesize the lens golden REFERENCES: radial warp + per-channel
    TCA + devignette over the canonical fixture bytes in float64 (the
    gate is <1e-5, warp class). Output shape = input shape (lens never
    resizes the frame — modifyROIOut identity)."""
    os.makedirs(out_dir, exist_ok=True)
    for case_name, dc1, dc2, dc3, dc4, vr, vb, vk1, vk2, vk3 in LENS_CASES:
        for fixture in LENS_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)
            cx, cy, half = w / 2.0, h / 2.0, w / 2.0

            def px(x, y, rgb=rgb, w=w, h=h):
                # Normalized radius around the frame center (u units).
                dx, dy = (x - cx) / half, (y - cy) / half
                ru = math.hypot(dx, dy)
                if ru < 1e-12:
                    s = 1.0
                    rd = 0.0
                else:
                    rd = _lens_forward_radius(ru, dc1, dc2, dc3, dc4)
                    s = rd / ru
                # TCA at the post-distortion radius (D3): channel scales.
                rd2 = rd * rd
                sR = vr
                sB = vb
                # Per-channel sample coords (center-relative, scaled).
                srx, sry = cx + dx * s * sR * half, cy + dy * s * sR * half
                sgx, sgy = cx + dx * s * half, cy + dy * s * half
                sbx, sby = cx + dx * s * sB * half, cy + dy * s * sB * half
                # Devignette at the post-distortion radius (D1 division).
                rd4 = rd2 * rd2
                vmul = 1.0 / (1.0 + vk1 * rd2 + vk2 * rd4 + vk3 * rd4 * rd2)
                pr = _lens_bilinear(rgb, w, h, srx, sry)
                pg = _lens_bilinear(rgb, w, h, sgx, sgy)
                pb = _lens_bilinear(rgb, w, h, sbx, sby)
                return (pr[0] * vmul, pg[1] * vmul, pb[2] * vmul)

            write_exr(os.path.join(out_dir, f"{case_name}__{fixture}.exr"), w, h, px)



# ──────────────────────────────────────────────────────────────────────
# Detail (Plan 04-05-T5) — sharpen / local contrast / highpass / soften /
# equalizer golden references (L017 route ① — ALL are spatial operators;
# dt-cli float export is spatially corrupt on this host, manifest "dt-cli
# host finding" re-confirmed for geometry in 04-02-T3; NO dt-cli leg is
# exercised — dt-side evidence = in-test uniform probes + XMP param blobs
# below as parameter documentation + formula同源 with the Swift modules).
#
# Conventions shared with the 03-05 toneequal section:
#   - `dt_gauss_coeffs` + the gaussian.c column-then-row recursion model
#     the shared Deriche-IIR `GaussianBlur.blur` (NOT dt sharpen's
#     truncated FIR — DECISIONS D1/D4: the plan mandates the IIR reuse,
#     so the reference mirrors the IIR side and parity proves the port
#     correct, not dt-identical).
#   - Lab conversions use the project constants (LAB_R2X / LAB_B /
#     LAB_WHITE / _lab_f / lab_from_rec2020 / lab_to_rec2020 above).
#   - Every reference below renders the FULL pipeline contract: the blur
#     runs over the FULL plane (halo-correct), then the per-pixel mix
#     applies — the same contract the pipe negotiates via modifyROIIn.
# ──────────────────────────────────────────────────────────────────────

# dt_iop_sharpen_params_t v1 = <fff> (12 bytes: radius/amount/threshold).
SHARPEN_PARAMS_FORMAT = "<fff"
SHARPEN_MODVERSION = 1
SHARPEN_IOP_ORDER = 35.0

# dt_iop_bilat_params_t v3 = <i4f> (20 bytes: mode int + sigma_r/sigma_s/
# detail/midtone). Lightamer ports only detail/sigma_s/sigma_r semantics
# (D6 — mode/midtone unported; XMP pins the dt layout for documentation).
BILAT_PARAMS_FORMAT = "<i4f"
BILAT_MODVERSION = 3
BILAT_IOP_ORDER = 54.0

# dt_iop_highpass_params_t v1 = <ff> (8 bytes: sharpness/contrast).
HIGHPASS_PARAMS_FORMAT = "<ff"
HIGHPASS_MODVERSION = 1
HIGHPASS_IOP_ORDER = 34.0

# dt_iop_soften_params_t v1 = <4f> (16 bytes: size/saturation/brightness/
# amount).
SOFTEN_PARAMS_FORMAT = "<4f"
SOFTEN_MODVERSION = 1
SOFTEN_IOP_ORDER = 66.0

# equalizer has NO dt blob in v1 (D10 — single gain set vs dt 3x6 curves).


def sharpen_params_blob(radius, amount, threshold) -> str:
    """dt_iop_sharpen_params_t v1 → lowercase HEX ASCII (12 bytes)."""
    packed = struct.pack(SHARPEN_PARAMS_FORMAT, radius, amount, threshold)
    assert len(packed) == 12, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def bilat_params_blob(mode, sigma_r, sigma_s, detail, midtone=0.5) -> str:
    """dt_iop_bilat_params_t v3 → lowercase HEX ASCII (20 bytes).

    mode: 0 = bilateral grid, 1 = local laplacian (dt default)."""
    packed = struct.pack(BILAT_PARAMS_FORMAT, mode, sigma_r, sigma_s, detail, midtone)
    assert len(packed) == 20, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def highpass_params_blob(sharpness, contrast) -> str:
    """dt_iop_highpass_params_t v1 → lowercase HEX ASCII (8 bytes)."""
    packed = struct.pack(HIGHPASS_PARAMS_FORMAT, sharpness, contrast)
    assert len(packed) == 8, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def soften_params_blob(size, saturation, brightness, amount) -> str:
    """dt_iop_soften_params_t v1 → lowercase HEX ASCII (16 bytes)."""
    packed = struct.pack(SOFTEN_PARAMS_FORMAT, size, saturation, brightness, amount)
    assert len(packed) == 16, len(packed)
    return binascii.hexlify(packed).decode("ascii")


# The detail 钉参组 (plan T5 action 1 + T1/T2/T3/T4 acceptance): neutral /
# single-param-active / combined per module. Soften pins saturation=100 +
# brightness=0 on the flat probe (D5 vacuous-identity: overexposed+blur
# preserve flats, so ANY amount is identity there).
SHARPEN_CASES = [
    # (case name, radius, amount, threshold)
    ("sharpen_neutral", 2.0, 0.0, 0.5),
    ("sharpen_default", 2.0, 0.5, 0.5),
    ("sharpen_strong", 2.0, 1.0, 0.0),
    ("sharpen_fine", 0.8, 1.0, 0.2),
]

# (case name, detail, sigmaS px, sigmaR)
BILAT_CASES = [
    ("bilat_neutral", 0.0, 20.0, 0.5),
    ("bilat_clarity", 1.0, 20.0, 0.5),
    ("bilat_soften", -0.5, 20.0, 0.5),
    ("bilat_tight", 1.0, 8.0, 0.3),
]

# (case name, sharpness, contrast)
HIGHPASS_CASES = [
    ("highpass_default", 50.0, 50.0),
    ("highpass_strong", 80.0, 80.0),
    ("highpass_fine", 20.0, 30.0),
]

# (case name, size, saturation, brightness, amount)
SOFTEN_CASES = [
    ("soften_neutral", 50.0, 100.0, 0.33, 0.0),
    ("soften_default", 50.0, 100.0, 0.33, 50.0),
    ("soften_flatprobe", 50.0, 100.0, 0.0, 50.0),
    ("soften_strong", 80.0, 80.0, 0.5, 80.0),
]

# (case name, g0..g5 deltas; 1+g = the multiplier)
EQUALIZER_CASES = [
    ("equalizer_neutral", [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
    ("equalizer_fine_boost", [0.5, 0.0, 0.0, 0.0, 0.0, 0.0]),
    ("equalizer_coarse_boost", [0.0, 0.0, 0.0, 0.0, 0.5, 0.0]),
    ("equalizer_mid_cut", [0.0, 0.0, -0.5, -0.5, 0.0, 0.0]),
]

DETAIL_REF_FIXTURES = [
    "gradient_ramp", "flat_0ev", "flat_-4ev", "checkerboard",
]


def _detail_iir_blur(channels, w, h, sigma, mins, maxs):
    """The shared Deriche-IIR recursion (te_gaussian_blur shape) over an
    N-channel float64 plane list with per-channel clamp bounds."""
    a0, a1, a2, a3, b1, b2, coefp, coefn = dt_gauss_coeffs(sigma)
    ch = len(channels)
    n = w * h
    temp = [[0.0] * n for _ in range(ch)]
    out = [[0.0] * n for _ in range(ch)]

    def clamp(v, c):
        return max(mins[c], min(maxs[c], v))

    for x in range(w):
        xp = [clamp(channels[c][x], c) for c in range(ch)]
        yb = [xp[c] * coefp for c in range(ch)]
        yp = yb[:]
        for y in range(h):
            idx = y * w + x
            for c in range(ch):
                xc = clamp(channels[c][idx], c)
                yc = a0 * xc + a1 * xp[c] - b1 * yp[c] - b2 * yb[c]
                xp[c] = xc
                yb[c] = yp[c]
                yp[c] = yc
                temp[c][idx] = yc
        xn = [clamp(channels[c][(h - 1) * w + x], c) for c in range(ch)]
        xa = xn[:]
        yn = [xn[c] * coefn for c in range(ch)]
        ya = yn[:]
        for y in range(h - 1, -1, -1):
            idx = y * w + x
            for c in range(ch):
                xc = clamp(channels[c][idx], c)
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


def sharpen_sigma(radius):
    """D1: sigma = UI-radius * scale (scale 1 in the golden pipe)."""
    return max(0.0, radius)


def sharpen_apply_pixel(lab, blur_l, amount, threshold):
    """sharpen_mix (sharpen.cl:165-167): soft-threshold USM on L."""
    delta = lab[0] - blur_l
    mag = abs(delta) - threshold
    detail = math.copysign(mag, delta) if mag > 0.0 else 0.0
    return (lab[0] + amount * detail, lab[1], lab[2])


def gen_sharpen_refs(canonical_dir: str, out_dir: str) -> None:
    """Synthesize the sharpen golden REFERENCES: Lab prep + IIR blur +
    soft-threshold mix in float64 (gate <1e-4, IIR-mix class)."""
    os.makedirs(out_dir, exist_ok=True)
    for case_name, radius, amount, threshold in SHARPEN_CASES:
        sigma = sharpen_sigma(radius)
        for fixture in DETAIL_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)
            n = w * h
            lab = [lab_from_rec2020((rgb[0][i], rgb[1][i], rgb[2][i])) for i in range(n)]
            ch = [[p[c] for p in lab] + [1.0] * 0 for c in range(3)]
            ch = [[lab[i][c] for i in range(n)] for c in range(3)] + [[1.0] * n]
            big = 1e30
            blurred = _detail_iir_blur(ch, w, h, sigma, [-big] * 4, [big] * 4) if sigma > 0 else ch

            def px(x, y, rgb=rgb, lab=lab, blurred=blurred, w=w):
                idx = y * w + x
                out_lab = sharpen_apply_pixel(lab[idx], blurred[0][idx], amount, threshold)
                return lab_to_rec2020(out_lab)

            write_exr(os.path.join(out_dir, f"{case_name}__{fixture}.exr"), w, h, px)


def _bilat_radius(sigma_s):
    """D6: effective pixel radius = sigmaS (scale 1 in the golden pipe)."""
    return max(1.0, sigma_s)


def gen_bilat_refs(canonical_dir: str, out_dir: str) -> None:
    """Synthesize the local-contrast golden REFERENCES: Lab-L EIGF
    no-mask base (te_eigf single iteration) + clarity apply in float64
    (gate <1e-4, IIR-mix class)."""
    os.makedirs(out_dir, exist_ok=True)
    for case_name, detail, sigma_s, sigma_r in BILAT_CASES:
        radius = _bilat_radius(sigma_s)
        feathering = sigma_r * sigma_r * 4.0
        for fixture in DETAIL_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)
            n = w * h
            labs = [lab_from_rec2020((rgb[0][i], rgb[1][i], rgb[2][i])) for i in range(n)]
            luma = [labs[i][0] for i in range(n)]
            base = te_eigf(luma, w, h, radius, feathering, 1, False, 0.0, 2.0 ** -14, 4.0)

            def px(x, y, rgb=rgb, labs=labs, base=base, w=w):
                idx = y * w + x
                out_l = labs[idx][0] + detail * (labs[idx][0] - base[idx])
                return lab_to_rec2020((out_l, labs[idx][1], labs[idx][2]))

            write_exr(os.path.join(out_dir, f"{case_name}__{fixture}.exr"), w, h, px)


def highpass_sigma(sharpness):
    """D4: dt highpass.c:135-140 (scale 1 in the golden pipe)."""
    rad = 16.0 * (min(100.0, sharpness + 1.0) / 100.0)
    radius = min(16.0, math.ceil(rad))
    return math.sqrt((radius * (radius + 1.0) * 8.0 + 2.0) / 3.0)


def highpass_apply_pixel(lab_l, blur_inv, contrast):
    """highpass_mix CL leg (highpass.cl:157): desaturated emboss."""
    cs = (contrast / 100.0) * 7.5
    return (min(100.0, max(0.0, 50.0 + ((0.5 * lab_l + 0.5 * blur_inv) - 50.0) * cs)), 0.0, 0.0)


def gen_highpass_refs(canonical_dir: str, out_dir: str) -> None:
    """Synthesize the highpass golden REFERENCES: invert(100-L) + IIR
    blur + CL mix in float64 (gate <1e-4, IIR-mix class)."""
    os.makedirs(out_dir, exist_ok=True)
    for case_name, sharpness, contrast in HIGHPASS_CASES:
        sigma = highpass_sigma(sharpness)
        for fixture in DETAIL_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)
            n = w * h
            labs = [lab_from_rec2020((rgb[0][i], rgb[1][i], rgb[2][i])) for i in range(n)]
            inv = [min(100.0, max(0.0, 100.0 - labs[i][0])) for i in range(n)]
            ch = [inv, [0.0] * n, [0.0] * n, [1.0] * n]
            big = 1e30
            blurred = _detail_iir_blur(ch, w, h, sigma, [-big] * 4, [big] * 4)

            def px(x, y, labs=labs, blurred=blurred, w=w):
                idx = y * w + x
                return lab_to_rec2020(highpass_apply_pixel(labs[idx][0], blurred[0][idx], contrast))

            write_exr(os.path.join(out_dir, f"{case_name}__{fixture}.exr"), w, h, px)


def _soften_rgb2hsl(rgb):
    r, g, b = rgb
    pmax, pmin = max(rgb), min(rgb)
    delta = pmax - pmin
    lv = (pmin + pmax) / 2.0
    if delta == 0.0:
        return (0.0, 0.0, lv)
    sv = delta / max(pmax + pmin, 2.0 ** -16) if lv < 0.5 else delta / max(2.0 - pmax - pmin, 2.0 ** -16)
    if pmax == r:
        hv = (g - b) / delta
    elif pmax == g:
        hv = 2.0 + (b - r) / delta
    else:
        hv = 4.0 + (r - g) / delta
    hv /= 6.0
    if hv < 0.0:
        hv += 1.0
    elif hv > 1.0:
        hv -= 1.0
    return (hv, sv, lv)


def _soften_hue2rgb(m1, m2, hue):
    if hue < 1.0:
        return m1 + (m2 - m1) * hue
    elif hue < 3.0:
        return m2
    else:
        return (m1 + (m2 - m1) * (4.0 - hue)) if hue < 4.0 else m1


def _soften_hsl2rgb(h, s, l):
    if s == 0.0:
        return (l, l, l)
    m2 = l * (1.0 + s) if l < 0.5 else l + s - l * s
    m1 = 2.0 * l - m2
    hh = h * 6.0
    return (_soften_hue2rgb(m1, m2, hh + 2.0 if hh < 4.0 else hh - 4.0),
            _soften_hue2rgb(m1, m2, hh),
            _soften_hue2rgb(m1, m2, hh - 2.0 if hh > 2.0 else hh + 4.0))


def soften_radius(size, w, h):
    """D4: dt soften.c:138-142 (scale 1, iscale 1 in the golden pipe)."""
    import math as _m
    mrad = int(_m.sqrt(w * w + h * h) * 0.01)
    if mrad <= 0:
        return 0
    rad = mrad * (min(100.0, size + 1.0) / 100.0)
    return min(mrad, int(_m.ceil(rad)))


def soften_sigma(size, w, h):
    """D4: dt soften.c:306 (BOX_ITERATIONS = 8)."""
    r = soften_radius(size, w, h)
    return math.sqrt((r * (r + 1.0) * 8.0 + 2.0) / 3.0)


def gen_soften_refs(canonical_dir: str, out_dir: str) -> None:
    """Synthesize the soften golden REFERENCES: HSL overexpose + IIR
    blur + amt mix in float64 (gate <1e-4, IIR-mix class)."""
    os.makedirs(out_dir, exist_ok=True)
    for case_name, size, saturation, brightness, amount in SOFTEN_CASES:
        sat = saturation / 100.0
        bri = 2.0 ** brightness
        amt = amount / 100.0
        sigma = None  # per-fixture (radius keys on plane size)
        for fixture in DETAIL_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)
            n = w * h
            sigma = soften_sigma(size, w, h)
            over = []
            for i in range(n):
                hv, sv, lv = _soften_rgb2hsl((rgb[0][i], rgb[1][i], rgb[2][i]))
                sv2 = min(1.0, max(0.0, sv * sat))
                lv2 = min(1.0, max(0.0, lv * bri))
                over.append(_soften_hsl2rgb(hv, sv2, lv2))
            ch = [[over[i][c] for i in range(n)] for c in range(3)] + [[1.0] * n]
            big = 1e30
            blurred = _detail_iir_blur(ch, w, h, sigma, [-big] * 4, [big] * 4)

            def px(x, y, rgb=rgb, blurred=blurred, w=w):
                idx = y * w + x
                return tuple(rgb[c][idx] * (1.0 - amt)
                             + min(1.0, max(0.0, blurred[c][idx])) * amt for c in range(3))

            write_exr(os.path.join(out_dir, f"{case_name}__{fixture}.exr"), w, h, px)


EQUALIZER_SIGMAS = [1.0, 2.0, 4.0, 8.0, 16.0]


def gen_equalizer_refs(canonical_dir: str, out_dir: str) -> None:
    """Synthesize the equalizer golden REFERENCES: Lab prep + chained
    IIR pyramid (sigma 1/2/4/8/16) + gain recombine in float64
    (gate <1e-4, IIR-mix class)."""
    os.makedirs(out_dir, exist_ok=True)
    for case_name, deltas in EQUALIZER_CASES:
        gains = [1.0 + d for d in deltas]
        for fixture in DETAIL_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)
            n = w * h
            labs = [lab_from_rec2020((rgb[0][i], rgb[1][i], rgb[2][i])) for i in range(n)]
            prep = [[labs[i][c] for i in range(n)] for c in range(3)] + [[1.0] * n]
            big = 1e30
            levels = []
            prev = prep
            for sigma in EQUALIZER_SIGMAS:
                lv = _detail_iir_blur(prev, w, h, sigma, [-big] * 4, [big] * 4)
                levels.append(lv)
                prev = lv
            b0 = prep[0]
            v = [lv[0] for lv in levels]

            def px(x, y, rgb=rgb, labs=labs, b0=b0, v=v, w=w):
                idx = y * w + x
                out_l = (gains[0] * (b0[idx] - v[0][idx])
                         + gains[1] * (v[0][idx] - v[1][idx])
                         + gains[2] * (v[1][idx] - v[2][idx])
                         + gains[3] * (v[2][idx] - v[3][idx])
                         + gains[4] * (v[3][idx] - v[4][idx])
                         + gains[5] * v[4][idx])
                return lab_to_rec2020((out_l, labs[idx][1], labs[idx][2]))

            write_exr(os.path.join(out_dir, f"{case_name}__{fixture}.exr"), w, h, px)


def gen_detail_cases(outdir: str) -> None:
    for case_name, radius, amount, threshold in SHARPEN_CASES:
        params = sharpen_params_blob(radius, amount, threshold)
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION,
            iop_order_version=5,
            operation="sharpen",
            modversion=SHARPEN_MODVERSION,
            params=params,
            iop_order=f"{SHARPEN_IOP_ORDER:.1f}",
        )
        with open(os.path.join(outdir, case_name + ".xmp"), "w") as f:
            f.write(xmp)
    for case_name, detail, sigma_s, sigma_r in BILAT_CASES:
        # mode 1 = local laplacian (dt default; documents the slot only —
        # the Lightamer leg is EIGF by D-G3, not either dt mode).
        params = bilat_params_blob(1, sigma_r, sigma_s, detail)
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION,
            iop_order_version=5,
            operation="bilat",
            modversion=BILAT_MODVERSION,
            params=params,
            iop_order=f"{BILAT_IOP_ORDER:.1f}",
        )
        with open(os.path.join(outdir, case_name + ".xmp"), "w") as f:
            f.write(xmp)
    for case_name, sharpness, contrast in HIGHPASS_CASES:
        params = highpass_params_blob(sharpness, contrast)
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION,
            iop_order_version=5,
            operation="highpass",
            modversion=HIGHPASS_MODVERSION,
            params=params,
            iop_order=f"{HIGHPASS_IOP_ORDER:.1f}",
        )
        with open(os.path.join(outdir, case_name + ".xmp"), "w") as f:
            f.write(xmp)
    for case_name, size, saturation, brightness, amount in SOFTEN_CASES:
        params = soften_params_blob(size, saturation, brightness, amount)
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION,
            iop_order_version=5,
            operation="soften",
            modversion=SOFTEN_MODVERSION,
            params=params,
            iop_order=f"{SOFTEN_IOP_ORDER:.1f}",
        )
        with open(os.path.join(outdir, case_name + ".xmp"), "w") as f:
            f.write(xmp)


# ──────────────────────────────────────────────────────────────────────
# Phase 5 钉参 blob 配方族骨架（Plan 05-01-T5）—— 05-02..08 各 plan 直接消费。
# L015：hex 非 base64（dt_exif_xmp_encode_internal 未压缩形）；struct 逐字段
# little-endian pack；pack 后先过 dt `--d params` 版本校验再入库（见各函数注）。
# RESEARCH §1.1 字节数正本（逐字段累计），唯 denoiseprofile 勘误见下。
# ──────────────────────────────────────────────────────────────────────

# dt_iop_denoiseprofile_params_t v12 = 416B（RESEARCH §1.1 "244B" 系算术勘误：
# 8f + a[3] + b[3] + mode(i) + x[6][7] + y[6][7] + wb/fix/newvst/wavelet/hilite(5i)
# = (14 + 1 + 84 + 5) × 4 = 416；244 系漏计 y 表。C struct 实证见 DECISIONS
# D-05-01-T5。pack 后必须先过 dt `--d params` 版本校验再入库。）
DENOISEPROFILE_PARAMS_FORMAT = "<14fi84f5i"  # v12, 416 bytes
DENOISEPROFILE_MODVERSION = 12
DENOISEPROFILE_IOP_ORDER = 9.0


def denoiseprofile_params_blob(
    radius=1.0, nbhood=7.0, strength=1.0, shadows=1.0, bias=0.0,
    scattering=0.0, central_pixel_weight=0.1, overshooting=1.0,
    a=(1e-4, 1e-4, 1e-4), b=(0.0, 0.0, 0.0),
    mode=1, x=None, y=None,
    wb_adaptive_anscombe=1, fix_anscombe_and_nlmeans_norm=1,
    use_new_vst=1, wavelet_color_mode=1, compensate_hilite_pres=1,
) -> str:
    """dt_iop_denoiseprofile_params_t v12 → lowercase HEX ASCII（L015）。
    x/y 默认全 0.5（dt v10+ 新增档默认值）；mode 默认 1 = WAVELETS。
    入库前先过 dt `--d params` 版本校验（RESEARCH §7 钉参三证据之一）。"""
    if x is None:
        x = [[b / 6.0] * 7 for b in range(6)]
        x = [v for row in x for v in row]
    if y is None:
        y = [0.5] * 42
    assert len(x) == 42 and len(y) == 42
    packed = struct.pack(
        DENOISEPROFILE_PARAMS_FORMAT,
        radius, nbhood, strength, shadows, bias, scattering,
        central_pixel_weight, overshooting,
        *a, *b, mode, *x, *y,
        wb_adaptive_anscombe, fix_anscombe_and_nlmeans_norm,
        use_new_vst, wavelet_color_mode, compensate_hilite_pres,
    )
    assert len(packed) == 416, len(packed)
    return binascii.hexlify(packed).decode("ascii")


# dt_iop_channelmixer_rgb_params_t v3 = 160B：6×4 float + 6 gboolean(int) +
# illuminant/fluo/led/adaptation/version(5 int) + x/y/temp/gamut(4f) + clip(int)。
# illuminant 默认 2 = DT_ILLUMINANT_D；fluo 默认 2 = F3；led 默认 4 = B5；
# adaptation 默认 1 = CAT16；version 默认 2 = V3。
CHANNELMIXERRGB_PARAMS_FORMAT = "<24f6i4i4f2i"  # 24f + normalize[6](i) + illum×4(i) + x/y/temp/gamut(4f) + clip/version(2i)
CHANNELMIXERRGB_MODVERSION = 3
CHANNELMIXERRGB_IOP_ORDER = 28.5


def channelmixerrgb_params_blob(
    red=(1.0, 0.0, 0.0, 0.0), green=(0.0, 1.0, 0.0, 0.0),
    blue=(0.0, 0.0, 1.0, 0.0), saturation=(0.0,) * 4,
    lightness=(0.0,) * 4, grey=(0.0,) * 4,
    normalize=(0, 0, 0, 0, 0, 0), illuminant=2, illum_fluo=2,
    illum_led=4, adaptation=1, x=0.333, y=0.333,
    temperature=5003.0, gamut=1.0, clip=1, version=2,
) -> str:
    """dt_iop_channelmixer_rgb_params_t v3 → hex。默认 = 恒等 mix（对角 1）。"""
    packed = struct.pack(
        CHANNELMIXERRGB_PARAMS_FORMAT,
        *red, *green, *blue, *saturation, *lightness, *grey,
        *normalize, illuminant, illum_fluo, illum_led, adaptation,
        x, y, temperature, gamut, clip, version,
    )
    assert len(packed) == 160, len(packed)
    return binascii.hexlify(packed).decode("ascii")


# dt_iop_colorbalancergb_params_t v5 = 132B：32 float + saturation_formula(int)。
# 默认 = dt default_v5（05-02 钉死）：4-way 全 0 + falloff (1,0,1) + chroma/sat
# 全 0 + hue 0 + brilliance 全 0（commit 折 shields/slopes powers）+
# mask_grey 0.1845 + vibrance 0 + grey_fulcrum 0.1845 + contrast 0 +
# formula 1 = DTUCS。注意 legacy default_v5 的 white_fulcrum EV 槽 = 0.0（线性
# fulcrum = exp2(0) = 1.0），与 init_presets 的 preset 全零一致。
COLORBALANCERGB_PARAMS_FORMAT = "<32fi"
COLORBALANCERGB_MODVERSION = 5
COLORBALANCERGB_IOP_ORDER = 41.5


def colorbalancergb_params_blob(
    four_way=(0.0,) * 12, falloff=(1.0, 0.0, 1.0),
    chroma=(0.0, 0.0, 0.0, 0.0), saturation=(0.0,) * 4,
    hue_angle=0.0, brilliance=(0.0,) * 4,
    mask_grey_fulcrum=0.1845, vibrance=0.0, grey_fulcrum=0.1845,
    contrast=0.0, saturation_formula=1,
) -> str:
    """dt_iop_colorbalancergb_params_t v5 → hex。默认 = dt default_v5 中性（非恒等：gamut 腿拉伸——恒等门 fixture 须 in-gamut，见 05-02 parity 注释）。"""
    floats = list(four_way) + list(falloff) + list(chroma) + list(saturation)
    floats += [hue_angle] + list(brilliance)
    floats += [mask_grey_fulcrum, vibrance, grey_fulcrum, contrast]
    assert len(floats) == 32, len(floats)
    packed = struct.pack(COLORBALANCERGB_PARAMS_FORMAT, *floats, saturation_formula)
    assert len(packed) == 132, len(packed)
    return binascii.hexlify(packed).decode("ascii")


# dt_iop_nlmeans_params_t v2 = 16B：radius/strength/luma/chroma（4f）。
# 默认 radius 2 / strength 50 / luma 0.5 / chroma 1.0。
NLMEANS_PARAMS_FORMAT = "<4f"
NLMEANS_MODVERSION = 2
NLMEANS_IOP_ORDER = 29.0


def nlmeans_params_blob(radius=2.0, strength=50.0, luma=0.5, chroma=1.0) -> str:
    """dt_iop_nlmeans_params_t v2 → hex。"""
    packed = struct.pack(NLMEANS_PARAMS_FORMAT, radius, strength, luma, chroma)
    assert len(packed) == 16, len(packed)
    return binascii.hexlify(packed).decode("ascii")


# dt_iop_bilateral_params_t v1 = 20B：radius/reserved/red/green/blue（5f）。
# 默认 radius 15 / reserved 15 / rgb 0.005。
BILATERAL_PARAMS_FORMAT = "<5f"
BILATERAL_MODVERSION = 1
BILATERAL_IOP_ORDER = 10.0


def bilateral_params_blob(
    radius=15.0, reserved=15.0, red=0.005, green=0.005, blue=0.005,
) -> str:
    """dt_iop_bilateral_params_t v1 → hex。"""
    packed = struct.pack(
        BILATERAL_PARAMS_FORMAT, radius, reserved, red, green, blue)
    assert len(packed) == 20, len(packed)
    return binascii.hexlify(packed).decode("ascii")


# 其余 color 组小 blob（默认中性；05-02..05-04 各 plan 消费）。
# - channelmixer v2 = 88B：red/green/blue[7] + algorithm(int)；默认 RGB 恒等 + v2。
# - colorzones v5 = 520B：channel(int) + curve[3][20](x,y float) + num[3](int) +
#   type[3](int) + strength(f) + mode(int) + splines(int)；默认 hue 通道空曲线。
# - monochrome v2 = 16B：a/b/size/highlights（4f）；默认 a=b=highlights=0, size 2。
# - vibrance v2 = 4B：amount（f）；默认 25。
# - velvia v2 = 8B：strength/bias（2f）；默认 25/1。
# - colorcontrast v2 = 20B：a/b steepness+offset（4f）+ unbound(int)；默认 1/0/1/0/1。
CHANNELMIXER_PARAMS_FORMAT = "<21fi"
CHANNELMIXER_MODVERSION = 2
CHANNELMIXER_IOP_ORDER = 39.0


def channelmixer_params_blob(
    red=(0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0),
    green=(0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0),
    blue=(0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0), algorithm_version=1,
) -> str:
    """dt_iop_channelmixer_params_t v2 → hex。默认 RGB 恒等 + CHANNEL_MIXER_VERSION_2。"""
    packed = struct.pack(
        CHANNELMIXER_PARAMS_FORMAT, *red, *green, *blue, algorithm_version)
    assert len(packed) == 88, len(packed)
    return binascii.hexlify(packed).decode("ascii")


COLORZONES_PARAMS_FORMAT = "<i120f6i2fi"
COLORZONES_MODVERSION = 5
COLORZONES_IOP_ORDER = 60.0


def colorzones_params_blob(
    channel=2, nodes=None, strength=0.0, mode=0, splines_version=1,
) -> str:
    """dt_iop_colorzones_params_t v5 → hex。默认 hue 通道、空曲线（x=y 对角）。"""
    if nodes is None:
        curve = []
        for _ in range(3):
            for n in range(20):
                v = n / 19.0
                curve += [v, v]
    else:
        curve = nodes
    assert len(curve) == 120, len(curve)
    packed = struct.pack(
        COLORZONES_PARAMS_FORMAT, channel, *curve,
        0, 0, 0, 0, 0, 0, strength, mode, splines_version)
    assert len(packed) == 520, len(packed)
    return binascii.hexlify(packed).decode("ascii")


MONOCHROME_PARAMS_FORMAT = "<4f"
MONOCHROME_MODVERSION = 2
MONOCHROME_IOP_ORDER = 64.0


def monochrome_params_blob(a=0.0, b=0.0, size=2.0, highlights=0.0) -> str:
    """dt_iop_monochrome_params_t v2 → hex。"""
    packed = struct.pack(MONOCHROME_PARAMS_FORMAT, a, b, size, highlights)
    assert len(packed) == 16, len(packed)
    return binascii.hexlify(packed).decode("ascii")


VIBRANCE_PARAMS_FORMAT = "<f"
VIBRANCE_MODVERSION = 2
VIBRANCE_IOP_ORDER = 58.0


def vibrance_params_blob(amount=25.0) -> str:
    """dt_iop_vibrance_params_t v2 → hex。"""
    packed = struct.pack(VIBRANCE_PARAMS_FORMAT, amount)
    assert len(packed) == 4, len(packed)
    return binascii.hexlify(packed).decode("ascii")


VELVIA_PARAMS_FORMAT = "<2f"
VELVIA_MODVERSION = 2
VELVIA_IOP_ORDER = 57.0


def velvia_params_blob(strength=25.0, bias=1.0) -> str:
    """dt_iop_velvia_params_t v2 → hex。"""
    packed = struct.pack(VELVIA_PARAMS_FORMAT, strength, bias)
    assert len(packed) == 8, len(packed)
    return binascii.hexlify(packed).decode("ascii")


COLORCONTRAST_PARAMS_FORMAT = "<4fi"
COLORCONTRAST_MODVERSION = 2
COLORCONTRAST_IOP_ORDER = 56.0


def colorcontrast_params_blob(
    a_steepness=1.0, a_offset=0.0, b_steepness=1.0, b_offset=0.0, unbound=1,
) -> str:
    """dt_iop_colorcontrast_params_t v2 → hex。默认恒等。"""
    packed = struct.pack(
        COLORCONTRAST_PARAMS_FORMAT,
        a_steepness, a_offset, b_steepness, b_offset, unbound)
    assert len(packed) == 20, len(packed)
    return binascii.hexlify(packed).decode("ascii")


# ──────────────────────────────────────────────────────────────────────
# ColorBalanceRGB (Plan 05-02-T3) — dt_iop_colorbalancergb_params_t v5,
# 132B: 4-way 各 Y/C/H（12f）+ falloff（shadows_weight/white_fulcrum/
# highlights_weight 3f）+ chroma（4f）+ saturation（4f）+ hue_angle（1f）+
# brilliance（4f）+ mask_grey/vibrance/grey_fulcrum/contrast（4f）+
# saturation_formula（i）。commit 折叠见 ColorBalanceRGBCommit.derive
# pipeline RGB → LMS2006 D65（D65 原生：CB_XYZ65_LMS * LAB_R2X——C harness
# 已验：CAT16/Bradford 往返在 D65-native 下恒等相消，沿用即引入 ~2x 伪影；
# YrgGamut.matrixIn/Out 系 filmic V5 专用链（含 CAT16/Bradford；filmic 自洽），
# 本模块必须用 D65 原生矩阵——头注见 05-02-DECISIONS D2。LAB_* 在 2608 行后定义，
# 模块 import 时延迟构造，见 _cb_matrices）。
_CB_MATRICES = None


def _cb_matrices():
    global _CB_MATRICES
    if _CB_MATRICES is None:
        # forward: pipeline RGB → CIE LMS D65 (dt :671-672 D65-native).
        mat_in = mat_mul(CB_XYZ65_LMS, LAB_R2X)
        # NOTE: no mat_out product — the final XYZ65 → RGB is LAB_X2R
        # direct (dt :899-901 D50-detour WP_OUT*CAT collapses D65-natively;
        # C-harness cb_verify proof: out == in to 1e-7).
        _CB_MATRICES = (mat_in, LAB_X2R)
    return _CB_MATRICES


def _cb_in():
    return _cb_matrices()[0]


def _cb_out():
    return _cb_matrices()[1]


# Yrg 常量（YrgGamut.swift 同源：CAT16/LMS2006/Kirk Filmlight/Yrg 白点）。
CB_XYZ50_65 = [[9.89466254e-01, -4.00304626e-02, 4.40530317e-02],
                [-5.40518733e-03, 1.00666069e+00, -1.75551955e-03],
                [-4.03920992e-04, 1.50768030e-02, 1.30210211e+00]]
CB_XYZ65_LMS = [[0.257085, 0.859943, -0.031061],
                 [-0.394427, 1.175800, 0.106423],
                 [0.064856, -0.076250, 0.559067]]
CB_LMS_XYZ65 = [[1.80794659, -1.29971660, 0.34785879],
                 [0.61783960, 0.39595453, -0.04104687],
                 [-0.12546960, 0.20478038, 1.74274183]]
CB_XYZ65_50 = [[1.01085433e+00, 4.07086103e-02, -3.41445825e-02],
                [5.42814201e-03, 9.93581926e-01, 1.15592039e-03],
                [2.50722468e-04, -1.14918759e-02, 7.67964947e-01]]
CB_YRG_WR = 0.21902143
CB_YRG_WG = 0.54371398
CB_LUT_ELEM = 512


def cb_make_ych(y, c, h_rad):
    return (y, c, math.cos(h_rad), math.sin(h_rad))




def cb_derive(case):
    """dt commit_params（colorbalancergb.c:1105-1168）float64。"""
    fw = case["four_way"]
    sh_y, sh_c, sh_h, mt_y, mt_c, mt_h = fw[0:6]
    hl_y, hl_c, hl_h, gl_y, gl_c, gl_h = fw[6:12]
    sw_p, wf_p, hw_p = case["falloff"]
    norm = cb_ych_to_grading_rgb(cb_make_ych(1.0, 0.0, 0.0))

    def grading(c, h_deg):
        return cb_ych_to_grading_rgb(
            cb_make_ych(1.0, c, math.radians(h_deg - 30.0)))

    gg = grading(gl_c, gl_h)
    global_v = tuple((gg[c] - norm[c]) + norm[c] * gl_y for c in range(3)) + (0.0,)
    sg = grading(sh_c, sh_h)
    shadows_v = tuple(1.0 + (sg[c] - norm[c]) + sh_y for c in range(3)) + (1.0,)
    hg = grading(hl_c, hl_h)
    highlights_v = tuple(1.0 + (hg[c] - norm[c]) + hl_y for c in range(3)) + (1.0,)
    mg = grading(mt_c, mt_h)
    midtones_v = tuple(1.0 / (1.0 + (mg[c] - norm[c])) for c in range(3)) + (1.0,)
    sw = 2.0 + sw_p * 2.0
    hw = 2.0 + hw_p * 2.0
    mw = sw * sw * hw * hw / (sw * sw + hw * hw)
    mask_ful = case["mask_grey_fulcrum"] ** 0.4101205819200422
    white_ful = 2.0 ** wf_p
    midtones_y = 1.0 / (1.0 + mt_y)
    hue_rad = math.radians(case["hue_angle"])
    l_white = 2.098883786377 * (white_ful ** 0.631651345306265) / (
        white_ful ** 0.631651345306265 + 1.12426773749357)
    # Lane mapping (dt struct order → kernel lanes (shadows, midtones,
    # highlights) + global scalar; colorbalancergb.c:78-92):
    # chroma struct = (shadows[0], highlights[1], global[2], midtones[3]);
    # saturation/brilliance structs = (global[0], highlights[1],
    # midtones[2], shadows[3]). Bisect 2026-09-21 (was scrambled).
    return dict(
        global_v=global_v, shadows_v=shadows_v, highlights_v=highlights_v,
        midtones_v=midtones_v, chroma=tuple(case["chroma"]),
        saturation=tuple(case["saturation"]), brilliance=tuple(case["brilliance"]),
        chroma_global=case["chroma"][2],
        saturation_global=case["saturation"][0],
        brilliance_global=case["brilliance"][0],
        chroma_v=(case["chroma"][0], case["chroma"][3], case["chroma"][1], 0.0),
        saturation_v=(case["saturation"][3], case["saturation"][2], case["saturation"][1], 0.0),
        brilliance_v=(case["brilliance"][3], case["brilliance"][2], case["brilliance"][1], 0.0),
        vibrance=case["vibrance"], contrast=1.0 + case["contrast"],
        grey_fulcrum=case["grey_fulcrum"],
        hue_cos=math.cos(hue_rad), hue_sin=math.sin(hue_rad),
        sw=sw, hw=hw, mw=mw, mask_ful=mask_ful, white_ful=white_ful,
        midtones_y=midtones_y, l_white=l_white,
        formula=case["saturation_formula"])


def cb_rgb_to_ych(rgb):
    lms = mat_vec(_cb_in(), rgb)
    y = 0.68990272 * lms[0] + 0.34832189 * lms[1]
    a = lms[0] + lms[1] + lms[2]
    nl = (0.0, 0.0, 0.0) if a == 0 else (lms[0] / a, lms[1] / a, lms[2] / a)
    gx = 1.0877193 * nl[0] - 0.66666667 * nl[1] + 0.02061856 * nl[2]
    gy = -0.0877193 * nl[0] + 1.66666667 * nl[1] - 0.05154639 * nl[2]
    r, g = gx - CB_YRG_WR, gy - CB_YRG_WG
    c = math.hypot(g, r)
    return (y, c, r / c if c != 0 else 1.0, g / c if c != 0 else 0.0)


def cb_ych_to_grading_rgb(ych):
    """dt :719-726 Ych → grading RGB（Yrg_to_LMS denorm + LMS_to_gradingRGB，
    无 pipeline 矩阵——middle leg 活在 grading 帧；C-harness 钉死）。"""
    y, c, cos_h, sin_h = ych
    r, g = c * cos_h + CB_YRG_WR, c * sin_h + CB_YRG_WG
    b = 1.0 - r - g
    lms = (0.95 * r + 0.38 * g, 0.05 * r + 0.62 * g + 0.03 * b, 0.97 * b)
    denom = 0.68990272 * lms[0] + 0.34832189 * lms[1]
    s = 0.0 if denom == 0 else y / denom
    lms2 = (lms[0] * s, lms[1] * s, lms[2] * s)
    return (1.0877193 * lms2[0] - 0.66666667 * lms2[1] + 0.02061856 * lms2[2],
            -0.0877193 * lms2[0] + 1.66666667 * lms2[1] - 0.05154639 * lms2[2],
            1.03092784 * lms2[2])


def cb_gamut_check_yrg(ych):
    y, c, cos_h, sin_h = ych
    r, g = c * cos_h + CB_YRG_WR, c * sin_h + CB_YRG_WG
    max_c = c
    if r < 0:
        max_c = min(-CB_YRG_WR / cos_h, max_c)
    if g < 0:
        max_c = min(-CB_YRG_WG / sin_h, max_c)
    if r + g > 1.0:
        max_c = min((1.0 - CB_YRG_WR - CB_YRG_WG) / (cos_h + sin_h), max_c)
    return (y, max_c, cos_h, sin_h)


def cb_opacity_masks(x, sw, hw, mw, ful):
    x_off = x - ful
    x_norm = x_off / ful
    alpha = 1.0 / (1.0 + math.exp(x_norm * sw))
    beta = 1.0 / (1.0 + math.exp(-x_norm * hw))
    gamma = math.exp(-x_off * x_off * mw / 4.0) * (1 - alpha) ** 2 * (1 - beta) ** 2 * 8.0
    return (alpha, gamma, beta, 0.0)


def cb_soft_clip(x, soft, hard):
    norm = hard - soft
    return soft + (1.0 - math.exp(-(x - soft) / norm)) * norm if x > soft else x


def cb_lookup_gamut(lut, hue):
    x_test = CB_LUT_ELEM * (hue + math.pi) / (2.0 * math.pi)
    x_prev, x_next = math.floor(x_test), math.ceil(x_test)
    xi, xii = int(x_prev) & (CB_LUT_ELEM - 1), int(x_next) & (CB_LUT_ELEM - 1)
    y_prev = lut[xi]
    return y_prev + ((x_test - x_prev) * (lut[xii] - y_prev) if xi != xii else 0.0)


def cb_y_to_lstar(y):
    yh = y ** 0.631651345306265
    return 2.098883786377 * yh / (yh + 1.12426773749357)


def cb_lstar_to_y(l):
    return (1.12426773749357 * l / (2.098883786377 - l)) ** 1.5831518565279648


def cb_xyz_to_xyy(xyz):
    c = tuple(max(v, 0.0) for v in xyz)
    s = c[0] + c[1] + c[2]
    return (0.31271, 0.32902, c[1]) if s <= 0 else (c[0] / s, c[1] / s, c[1])


def cb_xyy_to_xyz(xyy):
    x, y, Y = xyy
    return (0.0, 0.0, 0.0) if y == 0 else (Y * x / y, Y, Y * (1 - x - y) / y)


def cb_xyy_to_jch(xyy, l_white):
    x, y, Y = xyy
    uvd = (-0.783941002840055 * x + 0.277512987809202 * y + 0.153836578598858,
           0.745273540913283 * x - 0.205375866083878 * y - 0.165478376301988,
           0.318707282433486 * x + 2.16743692732158 * y + 0.291320554395942)
    div = uvd[2] if uvd[2] != 0 else 1e-30
    uvd = (uvd[0] / div, uvd[1] / div, uvd[2])
    us = (1.39656225667 * uvd[0] / (abs(uvd[0]) + 1.49217352929),
          1.4513954287 * uvd[1] / (abs(uvd[1]) + 1.52488637914))
    p = (-1.124983854323892 * us[0] - 0.980483721769325 * us[1],
         1.86323315098672 * us[0] + 1.971853092390862 * us[1])
    m2 = p[0] * p[0] + p[1] * p[1]
    ls = cb_y_to_lstar(max(0.0, min(Y, 1e8)))
    return (ls / l_white,
            15.932993652962535 * (ls ** 0.6523997524738018) * (m2 ** 0.6007557017508491) / l_white,
            math.atan2(p[1], p[0]))


def cb_jch_to_xyy(jch, l_white):
    J, C, h = jch
    ls = max(0.0, min(J * l_white, 2.09885))
    m = 0.0 if ls == 0 else (C * l_white / (
        15.932993652962535 * (ls ** 0.6523997524738018))) ** 0.8322850678616855
    up, vp = m * math.cos(h), m * math.sin(h)
    us = (-5.037522385190711 * up - 2.504856328185843 * vp,
          4.760029407436461 * up + 2.874012963239247 * vp)
    uv = (-1.49217352929 * us[0] / (abs(us[0]) - 1.39656225667),
          -1.52488637914 * us[1] / (abs(us[1]) - 1.4513954287))
    xyD = (0.167171472114775 * uv[0] + 0.141299802443708 * uv[1] - 0.00801531300850582,
           -0.150959086409163 * uv[0] - 0.155185060382272 * uv[1] - 0.00843312433578007,
           0.940254742367256 * uv[0] + 1.0 * uv[1] - 0.0256325967652889)
    div = xyD[2] if xyD[2] != 0 else 1e-30
    return (xyD[0] / div, xyD[1] / div, cb_lstar_to_y(ls))


def cb_jch_to_hsb(jch):
    J, C, h = jch
    b = J * (C ** 1.33654221029386 + 1.0)
    return (h, C / b if b > 0 else 0.0, b)


def cb_hsb_to_jch(hsb):
    h, s, b = hsb
    c = s * b
    return (b / (c ** 1.33654221029386 + 1.0), c, h)


def cb_jch_to_hcb(jch):
    J, C, h = jch
    return (h, C, J * (C ** 1.33654221029386 + 1.0))


def cb_hcb_to_jch(hcb):
    h, C, B = hcb
    return (B / (C ** 1.33654221029386 + 1.0), C, h)


CB_JZM = [[0.41478972, 0.579999, 0.0146480],
           [-0.2015100, 1.1206490, 0.0531008],
           [-0.0166008, 0.264800, 0.6684799]]
CB_JZA = [[0.5, 0.5, 0.0],
           [3.524000, -4.066708, 0.542708],
           [0.199076, 1.096799, -1.295875]]
CB_JZAI = [[1.0, 0.1386050432715393, 0.0580473161561189],
            [1.0, -0.1386050432715393, -0.0580473161561189],
            [1.0, -0.0960192420263190, -0.8118918960560390]]
CB_JZMI = [[1.9242264357876067, -1.0047923125953657, 0.0376514040306180],
            [0.3503167620949991, 0.7264811939316552, -0.0653844229480850],
            [-0.0909828109828475, -0.3127282905230739, 1.5227665613052603]]


def cb_xyz_to_jzazbz(xyz):
    t = (1.15 * xyz[0] - 0.15 * xyz[2], 0.66 * xyz[1] + 0.34 * xyz[0], xyz[2])
    lms = mat_vec(CB_JZM, t)
    lp = tuple(((0.8359375 + 18.8515625 * (max(l / 10000.0, 0.0) ** 0.159301758))
                / (1.0 + 18.6875 * (max(l / 10000.0, 0.0) ** 0.159301758))) ** 134.034375
               for l in lms)
    jab = mat_vec(CB_JZA, lp)
    return (max(0.44 * jab[0] / (1.0 - 0.56 * jab[0]) - 1.6295499532821566e-11, 0.0),
            jab[1], jab[2])


def cb_jzazbz_to_xyz(jab):
    d, d0 = -0.56, 1.6295499532821566e-11
    iz = (max((jab[0] + d0) / (1.0 + d - d * (jab[0] + d0)), 0.0), jab[1], jab[2])
    lms = mat_vec(CB_JZAI, iz)
    out = []
    for v in lms:
        n = max(v, 0.0) ** (1.0 / 134.034375)
        out.append(10000.0 * max((0.8359375 - n) / (18.6875 * n - 18.8515625), 0.0) ** (1.0 / 0.159301758))
    xyz = mat_vec(CB_JZMI, tuple(out))
    # dt X'Y'Z→XYZ: X = (X'+(b-1)Z')/b; Y = (Y'+(g-1)X)/g (g-1 = -0.34!).
    x = (xyz[0] + 0.15 * xyz[2]) / 1.15
    return (x, (xyz[1] - 0.34 * x) / 0.66, xyz[2])


def cb_lms_to_xyz(lms):
    return mat_vec(CB_LMS_XYZ65, lms)


def cb_build_ucs_lut():
    """dt_UCS_22_build_gamut_LUT（float64）：Rec2020 色域边界 M²（hue）。
    input = pipeline RGB → XYZ D65（D65 原生 LAB_R2X；commit :1191 同位）。"""
    inp = LAB_R2X
    xyzR, xyzG, xyzB = mat_vec(inp, (1, 0, 0)), mat_vec(inp, (0, 1, 0)), mat_vec(inp, (0, 0, 1))
    xyR, xyG, xyB = cb_xyz_to_xyy(xyzR), cb_xyz_to_xyy(xyzG), cb_xyz_to_xyy(xyzB)
    dxy = (0.31271, 0.32902)
    hR = math.atan2(xyR[1] - dxy[1], xyR[0] - dxy[0])
    hG = math.atan2(xyG[1] - dxy[1], xyG[0] - dxy[0])
    hB = math.atan2(xyB[1] - dxy[1], xyB[0] - dxy[0])

    def delta(a, b):
        d = a - b
        if d < -math.pi:
            d += 2 * math.pi
        if d > math.pi:
            d -= 2 * math.pi
        return d

    def clamp01(v):
        return max(0.0, min(1.0, v))

    gamut, sampler = [0.0] * CB_LUT_ELEM, [0.0] * CB_LUT_ELEM
    for i in range(50 * CB_LUT_ELEM):
        angle = -math.pi + i / (50 * CB_LUT_ELEM) * 2 * math.pi
        tan_a = math.tan(angle)
        t1 = delta(angle, hB) / delta(hR, hB)
        t2 = delta(angle, hR) / delta(hG, hR)
        t3 = delta(angle, hG) / delta(hB, hG)
        if t1 == clamp01(t1):
            t = (dxy[1] - xyB[1] + tan_a * (xyB[0] - dxy[0])) / (
                xyR[1] - xyB[1] + tan_a * (xyB[0] - xyR[0]))
            xt, yt = xyB[0] + t * (xyR[0] - xyB[0]), xyB[1] + t * (xyR[1] - xyB[1])
        elif t2 == clamp01(t2):
            t = (dxy[1] - xyR[1] + tan_a * (xyR[0] - dxy[0])) / (
                xyG[1] - xyR[1] + tan_a * (xyR[0] - xyG[0]))
            xt, yt = xyR[0] + t * (xyG[0] - xyR[0]), xyR[1] + t * (xyG[1] - xyR[1])
        elif t3 == clamp01(t3):
            t = (dxy[1] - xyG[1] + tan_a * (xyG[0] - dxy[0])) / (
                xyB[1] - xyG[1] + tan_a * (xyG[0] - xyB[0]))
            xt, yt = xyG[0] + t * (xyB[0] - xyG[0]), xyG[1] + t * (xyB[1] - xyG[1])
        else:
            xt, yt = 0.0, 0.0
        x, y = xt, yt
        uvd = (-0.783941002840055 * x + 0.277512987809202 * y + 0.153836578598858,
               0.745273540913283 * x - 0.205375866083878 * y - 0.165478376301988,
               0.318707282433486 * x + 2.16743692732158 * y + 0.291320554395942)
        div = uvd[2] if uvd[2] != 0 else 1e-30
        uvd = (uvd[0] / div, uvd[1] / div, uvd[2])
        us = (1.39656225667 * uvd[0] / (abs(uvd[0]) + 1.49217352929),
              1.4513954287 * uvd[1] / (abs(uvd[1]) + 1.52488637914))
        p = (-1.124983854323892 * us[0] - 0.980483721769325 * us[1],
             1.86323315098672 * us[0] + 1.971853092390862 * us[1])
        hue = math.atan2(p[1], p[0])
        index = int(round((CB_LUT_ELEM - 1) * (hue + math.pi) / (2 * math.pi)))
        index = (index + CB_LUT_ELEM) % CB_LUT_ELEM
        gamut[index] += p[0] * p[0] + p[1] * p[1]
        sampler[index] += 1.0
    return [gamut[k] / max(1.0, sampler[k]) for k in range(CB_LUT_ELEM)]


def cb_build_jzazbz_lut():
    """JzAzBz gamut LUT（commit :1194-1235）：92³ gym 最大 saturation。
    input = pipeline RGB → XYZ D65（D65 原生 LAB_R2X；JzAzBz 系 D65 空间）。"""
    inp = LAB_R2X
    steps = 92
    sampler = [0.0] * CB_LUT_ELEM
    for r in range(steps):
        for g in range(steps):
            for b in range(steps):
                rgb = (r / (steps - 1), g / (steps - 1), b / (steps - 1))
                xyz = mat_vec(inp, rgb)
                jab = cb_xyz_to_jzazbz(xyz)
                c = math.hypot(jab[1], jab[2])
                hue = math.atan2(jab[2], jab[1])
                sat = c / jab[0] if jab[0] > 0 else 0.0
                index = int(round((CB_LUT_ELEM - 1) * (hue + math.pi) / (2 * math.pi)))
                index = (index + CB_LUT_ELEM) % CB_LUT_ELEM
                sampler[index] = max(sampler[index], sat)
    lut = [0.0] * CB_LUT_ELEM
    for k in range(2, CB_LUT_ELEM - 2):
        lut[k] = (sampler[k - 2] + sampler[k - 1] + sampler[k] + sampler[k + 1] + sampler[k + 2]) / 5.0
    n = CB_LUT_ELEM
    lut[0] = (sampler[n - 2] + sampler[n - 1] + sampler[0] + sampler[1] + sampler[2]) / 5.0
    lut[1] = (sampler[n - 1] + sampler[0] + sampler[1] + sampler[2] + sampler[3]) / 5.0
    lut[n - 1] = (sampler[n - 3] + sampler[n - 2] + sampler[n - 1] + sampler[0] + sampler[1]) / 5.0
    lut[n - 2] = (sampler[n - 4] + sampler[n - 3] + sampler[n - 2] + sampler[n - 1] + sampler[0]) / 5.0
    return lut


_CB_LUTS = {}


def cb_gamut_lut(formula):
    if formula not in _CB_LUTS:
        _CB_LUTS[formula] = cb_build_ucs_lut() if formula == 1 else cb_build_jzazbz_lut()
    return _CB_LUTS[formula]


def cb_grading_to_lms(rgb):
    """dt gradingRGB_to_LMS（float64）：Filmlight grading RGB → CIE LMS（绝对值）。"""
    return (0.95 * rgb[0] + 0.38 * rgb[1],
            0.05 * rgb[0] + 0.62 * rgb[1] + 0.03 * rgb[2],
            0.97 * rgb[2])




def cb_grading_to_lms(rgb):
    """dt gradingRGB_to_LMS（float64）：Filmlight grading RGB → CIE LMS（绝对值）。"""
    return (0.95 * rgb[0] + 0.38 * rgb[1],
            0.05 * rgb[0] + 0.62 * rgb[1] + 0.03 * rgb[2],
            0.97 * rgb[2])


def cb_lms_to_yrg(lms):
    """dt LMS_to_Yrg（float64）：Y 绝对值 + 归一化 LMS 经 grading 矩阵的色度。"""
    y = 0.68990272 * lms[0] + 0.34832189 * lms[1]
    a = lms[0] + lms[1] + lms[2]
    nl = (0.0, 0.0, 0.0) if a == 0 else (lms[0] / a, lms[1] / a, lms[2] / a)
    gx = 1.0877193 * nl[0] - 0.66666667 * nl[1] + 0.02061856 * nl[2]
    gy = -0.0877193 * nl[0] + 1.66666667 * nl[1] - 0.05154639 * nl[2]
    return (y, gx, gy)


def cb_yrg_to_lms(yrg):
    """dt Yrg_to_LMS（float64）：归一化 grading 色度经 gradingRGB_to_LMS
    （ROW-MAJOR 形）denorm 回 LMS（绝对值）。"""
    y, rr, gg = yrg
    bb = 1.0 - rr - gg
    nl = (0.95 * rr + 0.38 * gg, 0.05 * rr + 0.62 * gg + 0.03 * bb, 0.97 * bb)
    den = 0.68990272 * nl[0] + 0.34832189 * nl[1]
    s = 0.0 if den == 0 else y / den
    return (nl[0] * s, nl[1] * s, nl[2] * s)


def cb_yrg_to_xyz(yrg):
    """dt Yrg→XYZ D65（:763-765）：Yrg_to_LMS + LMS_to_XYZ（CB_LMS_XYZ65 行优先）。"""
    return mat_vec(CB_LMS_XYZ65, cb_yrg_to_lms(yrg))


def colorbalance_apply_pixel(rgb, case, d, lut):
    """单像素全链（process :662-941 float64；mask_display 分支恒走 else）。"""
    pix = tuple(max(v, 0.0) for v in rgb)
    lms = mat_vec(_cb_in(), pix)
    y = 0.68990272 * lms[0] + 0.34832189 * lms[1]
    a = lms[0] + lms[1] + lms[2]
    nl = (0.0, 0.0, 0.0) if a == 0 else (lms[0] / a, lms[1] / a, lms[2] / a)
    gx = 1.0877193 * nl[0] - 0.66666667 * nl[1] + 0.02061856 * nl[2]
    gy = -0.0877193 * nl[0] + 1.66666667 * nl[1] - 0.05154639 * nl[2]
    r, g = gx - CB_YRG_WR, gy - CB_YRG_WG
    c = math.hypot(g, r)
    ych = (max(y, 0.0), c, r / c if c != 0 else 1.0, g / c if c != 0 else 0.0)
    op = cb_opacity_masks(ych[0] ** 0.4101205819200422, d["sw"], d["hw"], d["mw"], d["mask_ful"])
    opc = tuple(1.0 - v for v in op)
    # hue 旋转。
    cos_h, sin_h = ych[2], ych[3]
    ych = (ych[0], ych[1], d["hue_cos"] * cos_h - d["hue_sin"] * sin_h,
           d["hue_sin"] * cos_h + d["hue_cos"] * sin_h)
    # chroma + vibrance（:711-714）。
    boost = d["chroma_global"] + sum(o * v for o, v in zip(op, d["chroma_v"]))
    vib = d["vibrance"] * (1.0 - ych[1] ** abs(d["vibrance"])) if d["vibrance"] != 0 else 0.0
    ych = (ych[0], ych[1] * max(1.0 + boost + vib, 0.0), ych[2], ych[3])
    ych = cb_gamut_check_yrg(ych)
    # middle leg 活在 grading 帧（dt :719-726，无 pipeline 矩阵）。
    rgb2 = cb_ych_to_grading_rgb(ych)
    # global offset + shadows/highlights 双斜率。
    rgb2 = tuple(rgb2[c] + d["global_v"][c] for c in range(3))
    rgb2 = tuple(rgb2[c] * (opc[2] * (opc[0] + op[0] * d["shadows_v"][c])
                             + op[2] * d["highlights_v"][c]) for c in range(3))
    # midtones 幂（保号）。
    rgb2 = tuple(math.copysign(1.0, v) * (abs(v) / d["white_ful"]) ** d["midtones_v"][c] * d["white_ful"]
                 for c, v in enumerate(rgb2))
    # 回 Yrg：gradingRGB_to_LMS + LMS_to_Yrg（:753-755），Y 幂（:757-758）+
    # contrast（:760-761），Yrg_to_LMS + LMS_to_XYZ（:763-765）。
    # 注意帧语义：rgb2 是 grading-domain 值（color balance 在 grading RGB 上运算），
    # 故此处用 grading 矩阵（cb_grading_to_lms），不用 pipeline 矩阵——
    # 与前腿（pipeline 矩阵，:671-672）不对称是 dt 原样（两腿各管各的帧）。
    lms4 = cb_grading_to_lms(rgb2)
    yrg4 = cb_lms_to_yrg(lms4)
    yrg4 = (max(yrg4[0] / d["white_ful"], 0.0) ** d["midtones_y"] * d["white_ful"],
            yrg4[1], yrg4[2])
    yrg4 = (d["grey_fulcrum"] * (yrg4[0] / d["grey_fulcrum"]) ** d["contrast"],
            yrg4[1], yrg4[2])
    xyz = cb_yrg_to_xyz(yrg4)
    if d["formula"] == 0:
        jab = cb_xyz_to_jzazbz(xyz)
        J, C = jab[0], math.hypot(jab[1], jab[2])
        h = math.atan2(jab[2], jab[1])
        T = math.atan2(C, J) if (J, C) != (0, 0) else 0.0
        sT, cT = math.sin(T), math.cos(T)
        b0 = 1.0 + d["brilliance_global"] + sum(o * v for o, v in zip(op, d["brilliance_v"]))
        b1 = d["saturation_global"] + sum(o * v for o, v in zip(op, d["saturation_v"]))
        S0 = J * cT + C * sT
        S1 = S0 * max(-T, min(T * b1, math.pi / 2 - T))
        S0 = max(S0 * b0, 0.0)
        J2 = max(S0 * cT - S1 * sT, 0.0)
        C2 = max(S0 * sT + S1 * cT, 0.0)
        mx = cb_lookup_gamut(lut, h)
        sat = cb_soft_clip(C2 / J2, 0.8 * mx, mx) if J2 > 0 else mx
        maxC, maxJ = J2 * sat, C2 / sat if sat > 0 else J2
        J2, C2 = (J2 + maxJ) / 2.0, (C2 + maxC) / 2.0
        ch, sh = math.cos(h), math.sin(h)
        d0 = 1.6295499532821566e-11
        Iz = max((J2 + d0) / (1.0 - 0.56 - (-0.56) * (J2 + d0)), 0.0)
        AI = ((1.0, 0.1386050432715393, 0.0580473161561189),
              (1.0, -0.1386050432715393, -0.0580473161561189),
              (1.0, -0.0960192420263190, -0.8118918960560390))
        test = tuple(AI[r][0] * Iz + AI[r][1] * C2 * ch + AI[r][2] * C2 * sh for r in range(3))
        maxC = C2
        for r in range(3):
            if test[r] < 0:
                den = AI[r][1] * ch + AI[r][2] * sh
                maxC = min(-Iz / den, maxC)
        xyz = cb_jzazbz_to_xyz((J2, maxC * ch, maxC * sh))
    else:
        xyy = cb_xyz_to_xyy(xyz)
        JCH = cb_xyy_to_jch(xyy, d["l_white"])
        HCB = cb_jch_to_hcb(JCH)
        rad = math.hypot(HCB[1], HCB[2])
        sT = HCB[1] / rad if rad > 0 else 0.0
        cT = HCB[2] / rad if rad > 0 else 0.0
        P = max(1e-30, HCB[1])
        W = sT * HCB[1] + cT * HCB[2]
        a = max(1.0 + d["saturation_global"] + sum(o * v for o, v in zip(op, d["saturation_v"])), 0.0)
        b = max(1.0 + d["brilliance_global"] + sum(o * v for o, v in zip(op, d["brilliance_v"])), 0.0)
        max_a = math.hypot(P, W) / P
        a = cb_soft_clip(a, 0.5 * max_a, max_a)
        Pp = (a - 1.0) * P
        Wp = math.sqrt(P * P * (1.0 - a * a) + W * W) * b
        HCB = (HCB[0], max(cT * Pp + sT * Wp, 0.0), max(-sT * Pp + cT * Wp, 0.0))
        JCH = cb_hcb_to_jch(HCB)
        max_col = cb_lookup_gamut(lut, JCH[2])
        max_ch = 15.932993652962535 * ((JCH[0] * d["l_white"]) ** 0.6523997524738018) * (
            max_col ** 0.6007557017508491) / d["l_white"]
        bound = cb_jch_to_hsb((JCH[0], max_ch, JCH[2]))
        HSB = (HCB[0], HCB[1] / HCB[2] if HCB[2] > 0 else 0.0, HCB[2])
        HSB = (HSB[0], cb_soft_clip(HSB[1], 0.8 * bound[1], bound[1]), HSB[2])
        JCH = cb_hsb_to_jch(HSB)
        xyz = cb_xyy_to_xyz(cb_jch_to_xyy(JCH, d["l_white"]))
    out = mat_vec(_cb_out(), xyz)
    return tuple(max(v, 0.0) for v in out)


# The colorbalancergb 钉参组（plan T3：global hue/chroma、shadows、
# highlights、vibrance、contrast；saturation 公式三版各抽一 = JzAzBz 一 +
# DTUCS 两；默认中性 case 作恒等门 fixture 依据）。
COLORBALANCERGB_CASES = [
    {"name": "cb_default", "four_way": (0.0,) * 12, "falloff": (1.0, 0.0, 1.0),
     "chroma": (0.0, 0.0, 0.0, 0.0), "saturation": (0.0,) * 4, "hue_angle": 0.0,
     "brilliance": (0.0,) * 4, "mask_grey_fulcrum": 0.1845, "vibrance": 0.0,
     "grey_fulcrum": 0.1845, "contrast": 0.0, "saturation_formula": 1},
    {"name": "cb_global_hue", "four_way": (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 45.0),
     "falloff": (1.0, 0.0, 1.0), "chroma": (0.0, 0.0, 0.0, 0.0), "saturation": (0.0,) * 4,
     "hue_angle": 0.0, "brilliance": (0.0,) * 4, "mask_grey_fulcrum": 0.1845,
     "vibrance": 0.0, "grey_fulcrum": 0.1845, "contrast": 0.0, "saturation_formula": 1},
    {"name": "cb_shadows_lift", "four_way": (0.15, 0.3, 200.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0),
     "falloff": (1.0, 0.0, 1.0), "chroma": (0.2, 0.0, 0.0, 0.0), "saturation": (0.0,) * 4,
     "hue_angle": 0.0, "brilliance": (0.0,) * 4, "mask_grey_fulcrum": 0.1845,
     "vibrance": 0.0, "grey_fulcrum": 0.1845, "contrast": 0.0, "saturation_formula": 1},
    {"name": "cb_highlights_warm", "four_way": (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -0.1, 0.25, 30.0, 0.0, 0.0, 0.0),
     "falloff": (1.0, 0.0, 1.0), "chroma": (0.0, 0.0, 0.15, 0.0), "saturation": (0.0,) * 4,
     "hue_angle": 10.0, "brilliance": (0.0,) * 4, "mask_grey_fulcrum": 0.1845,
     "vibrance": 0.0, "grey_fulcrum": 0.1845, "contrast": 0.0, "saturation_formula": 1},
    {"name": "cb_vibrance", "four_way": (0.0,) * 12, "falloff": (1.0, 0.0, 1.0),
     "chroma": (0.0, 0.0, 0.0, 0.0), "saturation": (0.0,) * 4, "hue_angle": 0.0,
     "brilliance": (0.0,) * 4, "mask_grey_fulcrum": 0.1845, "vibrance": 0.6,
     "grey_fulcrum": 0.1845, "contrast": 0.0, "saturation_formula": 1},
    {"name": "cb_contrast_sat_jz", "four_way": (0.0,) * 12, "falloff": (1.0, 0.0, 1.0),
     "chroma": (0.0, 0.0, 0.0, 0.0), "saturation": (0.3, 0.1, -0.2, 0.0),
     "hue_angle": 0.0, "brilliance": (0.1, 0.05, -0.05, 0.0),
     "mask_grey_fulcrum": 0.1845, "vibrance": 0.0, "grey_fulcrum": 0.1845,
     "contrast": 0.3, "saturation_formula": 0},
]
COLORBALANCERGB_REF_FIXTURES = ["ramp_8ev", "flat_0ev", "flat_-4ev", "gray_staircase",
                                "saturated", "deep_shadow", "hue_sweep", "delta_impulse"]


def colorbalancergb_case_params(case):
    """case dict → ColorBalanceRGBModule.Params 构造 kwargs（Swift 侧同名）。"""
    fw = case["four_way"]
    return dict(
        shadowsY=fw[0], shadowsC=fw[1], shadowsH=fw[2],
        midtonesY=fw[3], midtonesC=fw[4], midtonesH=fw[5],
        highlightsY=fw[6], highlightsC=fw[7], highlightsH=fw[8],
        globalY=fw[9], globalC=fw[10], globalH=fw[11],
        shadowsWeight=case["falloff"][0], whiteFulcrum=case["falloff"][1],
        highlightsWeight=case["falloff"][2],
        chromaShadows=case["chroma"][0], chromaMidtones=case["chroma"][1],
        chromaHighlights=case["chroma"][2], chromaGlobal=case["chroma"][3],
        saturationShadows=case["saturation"][0], saturationMidtones=case["saturation"][1],
        saturationHighlights=case["saturation"][2], saturationGlobal=case["saturation"][3],
        hueAngle=case["hue_angle"],
        brillianceShadows=case["brilliance"][0], brillianceMidtones=case["brilliance"][1],
        brillianceHighlights=case["brilliance"][2], brillianceGlobal=case["brilliance"][3],
        maskGreyFulcrum=case["mask_grey_fulcrum"], vibrance=case["vibrance"],
        greyFulcrum=case["grey_fulcrum"], contrast=case["contrast"],
        saturationFormula=case["saturation_formula"])


def colorbalancergb_params_blob_for_case(case) -> str:
    floats = list(case["four_way"]) + list(case["falloff"]) + list(case["chroma"])
    floats += list(case["saturation"]) + [case["hue_angle"]] + list(case["brilliance"])
    floats += [case["mask_grey_fulcrum"], case["vibrance"], case["grey_fulcrum"], case["contrast"]]
    assert len(floats) == 32, len(floats)
    packed = struct.pack(COLORBALANCERGB_PARAMS_FORMAT, *floats, case["saturation_formula"])
    assert len(packed) == 132, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def gen_colorbalancergb_cases(outdir: str) -> None:
    for case in COLORBALANCERGB_CASES:
        params = colorbalancergb_params_blob_for_case(case)
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION,
            iop_order_version=5,
            operation="colorbalancergb",
            modversion=COLORBALANCERGB_MODVERSION,
            params=params,
            iop_order=f"{COLORBALANCERGB_IOP_ORDER:.1f}",
        )
        with open(os.path.join(outdir, case["name"] + ".xmp"), "w") as f:
            f.write(xmp)


def gen_colorbalancergb_refs(canonical_dir: str, out_dir: str) -> None:
    """Synthesize the colorbalancergb golden REFERENCES（L017 route；dt 侧 =
    XMP adoption + 平场 PFM probe）。6 case × 8 fixture。"""
    os.makedirs(out_dir, exist_ok=True)
    for case in COLORBALANCERGB_CASES:
        d = cb_derive(case)
        lut = cb_gamut_lut(case["saturation_formula"])
        for fixture in COLORBALANCERGB_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)

            def px(x, y, rgb=rgb, case=case, d=d, lut=lut, w=w):
                idx = y * w + x
                return colorbalance_apply_pixel(
                    (rgb[0][idx], rgb[1][idx], rgb[2][idx]), case, d, lut)

            write_exr(os.path.join(out_dir, f"{case['name']}__{fixture}.exr"), w, h, px)

def gen_ashift_cases(outdir: str) -> None:
    for case in ASHIFT_CASES:
        name, rot, sv, sh, shear, cl, cr, ct, cb = case
        params = ashift_params_blob(rot, sv, sh, shear, 28.0, 1.0, 0, 0, cl, cr, ct, cb)
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION,
            iop_order_version=5,
            operation="ashift",
            modversion=ASHIFT_MODVERSION,
            params=params,
            iop_order=f"{ASHIFT_IOP_ORDER:.1f}",
        )
        with open(os.path.join(outdir, name + ".xmp"), "w") as f:
            f.write(xmp)
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
                    gen_gray_staircase, gen_stair_1d, gen_gradient_ramp,
                    gen_checkerboard, gen_hue_sweep, gen_delta_impulse,
                    gen_shadow_torture):
            gen(outdir)
        # 加噪集读 canonical 源（raw 直写 outdir 时源即 outdir 本身）——
        # 无 dt round-trip（噪声 fixture 不进 dt-cli；L017 自研 parity）。
        gen_noisy_fixtures(outdir, canonical_dir=outdir)
    if mode in ("cases", "all"):
        # Cases default to <golden>/cases — one level up from the fixtures
        # dir when the caller uses the default outdir.
        if mode == "cases" and len(sys.argv) <= 2:
            cases_dir = os.path.join(os.path.dirname(outdir), "cases")
        else:
            cases_dir = os.path.join(outdir, "cases")
        gen_cases(cases_dir)
        gen_colorbalancergb_cases(cases_dir)
        gen_channelmixerrgb_cases(cases_dir)
        gen_channelmixer_cases(cases_dir)
        gen_colorcontrast_cases(cases_dir)
        gen_vibrance_cases(cases_dir)
        gen_velvia_cases(cases_dir)
        gen_colorzones_cases(cases_dir)
        gen_monochrome_cases(cases_dir)
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
        # Plan 04-02-T3: crop + flip golden references (L017 route;
        # dt-side = XMP adoption + flat probes; ramp probe corrupt).
        gen_crop_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        gen_flip_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        # Plan 04-03-T4: ashift warp golden references (L017 route ① —
        # warp is a spatial operator, dt-cli float export spatially corrupt;
        # dt-side = XMP adoption + flat rotation probe. Synthetic ref =
        # float64 inverse-homography + bilinear, formula-mirrored below).
        gen_ashift_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        # Plan 04-04-T4: lens warp golden references (L017 route ① —
        # warp is a spatial operator; lens has no dt-cli leg. Synthetic
        # ref = float64 radial warp + TCA + devignette, formula-mirrored).
        gen_lens_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        # Plan 04-05-T5: detail golden references (L017 route ① —
        # ALL are spatial operators; no dt-cli leg. Synthetic refs =
        # float64 IIR + per-pixel mix, formula-mirrored).
        gen_sharpen_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        gen_bilat_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        gen_highpass_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        gen_soften_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        gen_equalizer_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        # Plan 05-02-T3: colorbalancergb golden references (L017 route;
        # dt-side = XMP adoption + 平场 PFM probe).
        gen_colorbalancergb_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        gen_channelmixerrgb_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        gen_channelmixer_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        gen_colorcontrast_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        gen_vibrance_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        gen_velvia_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        gen_colorzones_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        # Plan 05-05: monochrome (L017 route; CPU sigma2 + grid leg).
        gen_monochrome_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        # Plan 05-06: nlmeans cases + Goossens float64 references.
        gen_nlmeans_cases(cases_dir)
        gen_nlmeans_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        # Plan 05-07: denoiseprofile cases + wavelets/NLMeans-leg float64
        # references (L017 route; dt-side = XMP adoption + flat probe).
        gen_denoiseprofile_cases(cases_dir)
        gen_denoiseprofile_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
        # Plan 05-08: bilateral cases + 网格/直连 float64 references.
        gen_bilateral_cases(cases_dir)
        gen_bilateral_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
    if mode in ("refs-bilateral", "all"):
        # targeted: 05-08 golden references only (fixtures dir as outdir;
        # references land in ../output per the established layout).
        gen_bilateral_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
    if mode in ("refs-denoiseprofile", "all"):
        # targeted: 05-07 golden references only (fixtures dir as outdir;
        # references land in ../output per the established layout).
        gen_denoiseprofile_refs(outdir, os.path.join(os.path.dirname(outdir), "output"))
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




# ──────────────────────────────────────────────────────────────────────
# ChannelMixerRGB / ChannelMixer / ColorContrast (Plan 05-03-T4)
# ──────────────────────────────────────────────────────────────────────
# float64 参考链：与 Swift ChannelMixerMath / ChannelMixerRGBModule.derive /
# ChannelMixerModule.reference / ColorContrastModule.reference 同公式
# （dt 行号见各模块头注）。L017 route：数值参考合成；dt 侧 = XMP 采纳 +
# DB hex + params ok（平场 probe：channelmixerrgb 默认 D-illuminant adaptation
# 非恒等——probe 只记方向/稳定性，不作主轨）。

CM_NORM_MIN = 1.52587890625e-05
CM_INV_SQRT3 = 0.5773502691896258

CM_XYZ_B = [[0.8951, 0.2664, -0.1614],
            [-0.7502, 1.7135, 0.0367],
            [0.0389, -0.0685, 1.0296]]
CM_B_XYZ = [[0.9870, -0.1471, 0.1600],
            [0.4323, 0.5184, 0.0493],
            [-0.0085, 0.0400, 0.9685]]
CM_XYZ_C = [[0.401288, 0.650173, -0.051461],
            [-0.250268, 1.204414, 0.045854],
            [-0.002079, 0.048952, 0.953127]]
CM_C_XYZ = [[1.862068, -1.011255, 0.149187],
            [0.38752, 0.621447, -0.008974],
            [-0.015841, -0.034123, 1.049964]]
CM_D50_XY = (0.34567, 0.35850)
CM_D50_UV = (0.20915914598542354, 0.488075320769787)
CM_FLUO = [(0.31310, 0.33727), (0.37208, 0.37529), (0.40910, 0.39430),
           (0.44018, 0.40329), (0.31379, 0.34531), (0.37790, 0.38835),
           (0.31292, 0.32933), (0.34588, 0.35875), (0.37417, 0.37281),
           (0.34609, 0.35986), (0.38052, 0.37713), (0.43695, 0.40441)]
CM_LED = [(0.4560, 0.4078), (0.4357, 0.4012), (0.3756, 0.3723),
          (0.3422, 0.3502), (0.3118, 0.3236), (0.4474, 0.4066),
          (0.4557, 0.4211), (0.4560, 0.4548), (0.3781, 0.3775)]


def cm_cct_daylight(t):
    x = 0.0
    if 4000 <= t <= 7000:
        x = ((-4.6070e9 / t + 2.9678e6) / t + 0.09911e3) / t + 0.244063
    elif 7000 < t <= 25000:
        x = ((-2.0064e9 / t + 1.9018e6) / t + 0.24748e3) / t + 0.237040
    if x == 0:
        return (0.0, 0.0)
    return (x, (-3.0 * x + 2.87) * x - 0.275)


def cm_cct_blackbody(t):
    x = 0.0
    if 1667 <= t <= 4000:
        x = ((-0.2661239e9 / t - 0.2343589e6) / t + 0.8776956e3) / t + 0.179910
    elif 4000 < t <= 25000:
        x = ((-3.0258469e9 / t + 2.1070379e6) / t + 0.2226347e3) / t + 0.240390
    if x == 0:
        return (0.0, 0.0)
    if 1667 <= t <= 2222:
        y = ((-1.1063814 * x - 1.34811020) * x + 2.18555832) * x - 0.20219683
    elif 2222 < t <= 4000:
        y = ((-0.9549476 * x - 1.37418593) * x + 2.09137015) * x - 0.16748867
    else:
        y = ((3.0817580 * x - 5.87338670) * x + 3.75112997) * x - 0.37001483
    return (x, y)


def cm_illuminant_to_xy(illuminant, fluo, led, temperature, cx, cy):
    if illuminant == 0:
        return CM_D50_XY
    if illuminant == 3:
        return (1.0 / 3.0, 1.0 / 3.0)
    if illuminant == 1:
        return (0.44757, 0.40745)
    if illuminant == 4:
        return CM_FLUO[fluo]
    if illuminant == 5:
        return CM_LED[led]
    if illuminant == 2:
        x, y = cm_cct_daylight(temperature)
        if x != 0 and y != 0:
            return (x, y)
    if illuminant in (2, 6):
        x, y = cm_cct_blackbody(temperature)
        if x != 0 and y != 0:
            return (x, y)
        return (cx, cy)
    return (cx, cy)


def cm_xy_to_xyz(x, y):
    return (x / y, 1.0, (1.0 - x - y) / y)


def cm_xyz_to_lms(xyz, adaptation):
    if adaptation in (0, 2):
        return mat_vec(CM_XYZ_B, xyz)
    if adaptation == 1:
        return mat_vec(CM_XYZ_C, xyz)
    return xyz


def cm_lms_to_xyz(lms, adaptation):
    if adaptation in (0, 2):
        return mat_vec(CM_B_XYZ, lms)
    if adaptation == 1:
        return mat_vec(CM_C_XYZ, lms)
    return lms


def cm_bradford_adapt(lms, illum, p, full):
    t = (lms[0] / illum[0], lms[1] / illum[1], lms[2] / illum[2])
    if full and t[2] > 0:
        t = (t[0], t[1], t[2] ** p)
    return (0.996078 * t[0], 1.020646 * t[1], 0.818155 * t[2])


def cm_cat16_adapt(lms, illum):
    return (lms[0] * 0.994535 / illum[0], lms[1] * 1.000997 / illum[1],
            lms[2] * 0.833036 / illum[2])


def cm_xyz_adapt(xyz, illum):
    return (xyz[0] * 0.9642119944211994 / illum[0], xyz[1] * 1.0 / illum[1],
            xyz[2] * 0.8251882845188288 / illum[2])


def cm_downscale(v, s):
    f = (s + CM_NORM_MIN) if s > CM_NORM_MIN else CM_NORM_MIN
    return (v[0] / f, v[1] / f, v[2] / f)


def cm_upscale(v, s):
    f = (s + CM_NORM_MIN) if s > CM_NORM_MIN else CM_NORM_MIN
    return (v[0] * f, v[1] * f, v[2] * f)


def cm_gamut_map(inp, compression, clip):
    s = inp[0] + inp[1] + inp[2]
    xyY = (inp[0] / s if s > 0 else CM_D50_XY[0],
           inp[1] / s if s > 0 else CM_D50_XY[1], inp[1])
    den = -2.0 * xyY[0] + 12.0 * xyY[1] + 3.0
    uv = (4.0 * xyY[0] / den, 9.0 * xyY[1] / den)
    du = (CM_D50_UV[0] - uv[0], CM_D50_UV[1] - uv[1])
    delta = inp[1] * (du[0] ** 2 + du[1] ** 2)
    corr = 0.0 if compression == 0 else delta ** compression
    out_uv = []
    for c in range(2):
        tmp = corr * du[c] + uv[c]
        out_uv.append(max(tmp, CM_D50_UV[c]) if uv[c] > CM_D50_UV[c]
                      else min(tmp, CM_D50_UV[c]))
    den2 = 6.0 * out_uv[0] - 16.0 * out_uv[1] + 12.0
    xyY = (9.0 * out_uv[0] / den2, 4.0 * out_uv[1] / den2, xyY[2])
    if clip:
        xyY = (max(xyY[0], 0.0), max(xyY[1], 0.0), xyY[2])
    xyY = (xyY[0], max(xyY[1], CM_NORM_MIN), xyY[2])
    sc = xyY[0] + xyY[1]
    if sc >= 1.0:
        xyY = (xyY[0] / sc, xyY[1] / sc, xyY[2])
    return (xyY[2] * xyY[0] / xyY[1], xyY[2],
            xyY[2] * (1.0 - xyY[0] - xyY[1]) / xyY[1])


def cm_luma_chroma(inp, saturation, lightness, version):
    norm = max(math.sqrt(inp[0] ** 2 + inp[1] ** 2 + inp[2] ** 2), CM_NORM_MIN)
    avg = max((inp[0] + inp[1] + inp[2]) / 3.0, CM_NORM_MIN)
    if not (norm > 0 and avg > 0):
        return inp
    mix = inp[0] * lightness[0] + inp[1] * lightness[1] + inp[2] * lightness[2]
    if version == 2:
        norm *= CM_INV_SQRT3
    out = (inp[0] / norm, inp[1] / norm, inp[2] / norm)
    if version == 0:
        coeff = ((1 - out[0]) * saturation[0] + (1 - out[1]) * saturation[1]
                 + (1 - out[2]) * saturation[2])
    else:
        coeff = (out[0] * saturation[0] + out[1] * saturation[1]
                 + out[2] * saturation[2]) / 3.0
    mins = tuple(o if o < 0 else 0.0 for o in out)
    out = tuple(max((1 - out[c]) * coeff + out[c], mins[c]) for c in range(3))
    if version == 2:
        n2 = max(math.sqrt(sum(o * o for o in out)), CM_NORM_MIN)
        norm /= n2 * CM_INV_SQRT3
    norm *= max(1.0 + mix / avg, 0.0)
    return (out[0] * norm, out[1] * norm, out[2] * norm)


def cm_derive(case):
    """dt commit_params（channelmixerrgb.c:3047-3150）float64。"""
    red, green, blue = case["red"], case["green"], case["blue"]
    sat, light = case["saturation"], case["lightness"]
    grey = case["grey"]
    norm = case["normalize"]
    nR = (red[0] + red[1] + red[2]) if norm[0] else 1.0
    nG = (green[0] + green[1] + green[2]) if norm[1] else 1.0
    nB = (blue[0] + blue[1] + blue[2]) if norm[2] else 1.0
    nS = ((sat[0] + sat[1] + sat[2]) / 3.0) if norm[3] else 0.0
    nL = ((light[0] + light[1] + light[2]) / 3.0) if norm[4] else 0.0
    nGr = grey[0] + grey[1] + grey[2]
    apply_grey = grey[0] != 0 or grey[1] != 0 or grey[2] != 0
    if not norm[5] or nGr == 0:
        nGr = 1.0
    mix = [[red[0] / nR, red[1] / nR, red[2] / nR],
           [green[0] / nG, green[1] / nG, green[2] / nG],
           [blue[0] / nB, blue[1] / nB, blue[2] / nB]]
    saturation = (-sat[0] + nS, -sat[1] + nS, -sat[2] + nS)
    if case["version"] == 0:
        saturation = (-sat[2] + nS, saturation[1], -sat[0] + nS)
    lightness = (light[0] - nL, light[1] - nL, light[2] - nL)
    grey_v = (grey[0] / nGr, grey[1] / nGr, grey[2] / nGr)
    if case["illuminant"] == 10:
        x, y = cm_cct_daylight(case["temperature"])
        if x == 0 and y == 0:
            x, y = cm_cct_blackbody(case["temperature"])
        if x == 0 and y == 0:
            x, y = case["x"], case["y"]
    else:
        x, y = cm_illuminant_to_xy(case["illuminant"], case["illum_fluo"],
                                   case["illum_led"], case["temperature"],
                                   case["x"], case["y"])
    illuminant = cm_xyz_to_lms(cm_xy_to_xyz(x, y), case["adaptation"])
    p = (0.818155 / illuminant[2]) ** 0.0834
    gamut = 0.0 if case["gamut"] == 0 else 1.0 / case["gamut"]
    adapt = case["adaptation"]
    if adapt in (0, 2):
        rgb_to_lms = mat_mul(CM_XYZ_B, LAB_R2X)
        mix_to_xyz = mat_mul(CM_B_XYZ, mix)
        xyz_to_lms = CM_XYZ_B
        lms_to_xyz = CM_B_XYZ
    elif adapt == 1:
        rgb_to_lms = mat_mul(CM_XYZ_C, LAB_R2X)
        mix_to_xyz = mat_mul(CM_C_XYZ, mix)
        xyz_to_lms = CM_XYZ_C
        lms_to_xyz = CM_C_XYZ
    elif adapt == 3:
        rgb_to_lms = [row[:] for row in LAB_R2X]
        mix_to_xyz = [row[:] for row in mix]
        xyz_to_lms = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        lms_to_xyz = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    else:
        rgb_to_lms = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        mix_to_xyz = mat_mul(LAB_R2X, mix)
        xyz_to_lms = [row[:] for row in LAB_X2R]
        lms_to_xyz = [row[:] for row in LAB_R2X]
    return dict(rgb_to_lms=rgb_to_lms, mix_to_xyz=mix_to_xyz,
                xyz_to_lms=xyz_to_lms, lms_to_xyz=lms_to_xyz,
                illuminant=illuminant, p=p, gamut=gamut,
                saturation=saturation, lightness=lightness, grey=grey_v,
                apply_grey=apply_grey)


def channelmixerrgb_apply_pixel(rgb, case, d):
    """单像素全链（_loop_switch float64；alpha 直通）。"""
    adapt, clip = case["adaptation"], case["clip"]
    pix = tuple(max(v, 0.0) for v in rgb) if clip else rgb
    if adapt == 2:
        xyz = mat_vec(d["rgb_to_lms"], pix)
        Y = xyz[1]
        lms = cm_xyz_to_lms(xyz, adapt)
        lms = cm_downscale(lms, Y)
        lms = cm_bradford_adapt(lms, d["illuminant"], d["p"], True)
        lms = cm_upscale(lms, Y)
        lms = mat_vec(d["mix_to_xyz"], lms)
        xyz = cm_lms_to_xyz(lms, adapt)
    elif adapt == 0:
        lms = mat_vec(d["rgb_to_lms"], pix)
        lms = cm_bradford_adapt(lms, d["illuminant"], d["p"], False)
        lms = mat_vec(d["mix_to_xyz"], lms)
        xyz = cm_lms_to_xyz(lms, adapt)
    elif adapt == 1:
        xyz = mat_vec(d["rgb_to_lms"], pix)
        Y = xyz[1]
        lms = cm_xyz_to_lms(xyz, adapt)
        lms = cm_downscale(lms, Y)
        lms = cm_cat16_adapt(lms, d["illuminant"])
        lms = cm_upscale(lms, Y)
        lms = mat_vec(d["mix_to_xyz"], lms)
        xyz = cm_lms_to_xyz(lms, adapt)
    elif adapt == 3:
        xyz = mat_vec(d["rgb_to_lms"], pix)
        Y = xyz[1]
        xyz = cm_downscale(xyz, Y)
        xyz = cm_xyz_adapt(xyz, d["illuminant"])
        xyz = cm_upscale(xyz, Y)
        xyz = mat_vec(d["mix_to_xyz"], xyz)
    else:
        xyz = mat_vec(d["mix_to_xyz"], pix)
    if clip:
        xyz = tuple(max(v, 0.0) for v in xyz)
    xyz = cm_gamut_map(xyz, d["gamut"], clip)
    lms = cm_xyz_to_lms(xyz, adapt) if adapt != 4 else mat_vec(d["xyz_to_lms"], xyz)
    if clip:
        lms = tuple(max(v, 0.0) for v in lms)
    lms = cm_luma_chroma(lms, d["saturation"], d["lightness"], case["version"])
    if clip:
        lms = tuple(max(v, 0.0) for v in lms)
    if d["apply_grey"]:
        g = max(lms[0] * d["grey"][0] + lms[1] * d["grey"][1]
                + lms[2] * d["grey"][2], 0.0)
        return (g, g, g)
    back = cm_lms_to_xyz(lms, adapt) if adapt != 4 else mat_vec(d["lms_to_xyz"], lms)
    if clip:
        back = tuple(max(v, 0.0) for v in back)
    out = mat_vec(LAB_X2R, back)
    if clip:
        out = tuple(max(v, 0.0) for v in out)
    return out


# 6 case：≥3 矩阵路径（CAT16 D / linear-Bradford A / full-Bradford BB /
# XYZ E / RGB bypass）+ illuminant 变更 + saturation 三版（v3/v1/v2）。
CHANNELMIXERRGB_CASES = [
    {"name": "cmr_default", "red": (1.0, 0.0, 0.0, 0.0),
     "green": (0.0, 1.0, 0.0, 0.0), "blue": (0.0, 0.0, 1.0, 0.0),
     "saturation": (0.0,) * 4, "lightness": (0.0,) * 4, "grey": (0.0,) * 4,
     "normalize": (0,) * 6, "illuminant": 2, "illum_fluo": 2, "illum_led": 4,
     "adaptation": 1, "x": 0.333, "y": 0.333, "temperature": 5003.0,
     "gamut": 1.0, "clip": 1, "version": 2},
    {"name": "cmr_tungsten_linear", "red": (1.1, -0.05, -0.05, 0.0),
     "green": (-0.1, 1.2, -0.1, 0.0), "blue": (0.0, -0.1, 1.1, 0.0),
     "saturation": (0.2, -0.1, 0.1, 0.0), "lightness": (0.05, 0.0, -0.05, 0.0),
     "grey": (0.0,) * 4, "normalize": (1, 1, 1, 0, 0, 0),
     "illuminant": 1, "illum_fluo": 2, "illum_led": 4,
     "adaptation": 0, "x": 0.333, "y": 0.333, "temperature": 5003.0,
     "gamut": 1.0, "clip": 1, "version": 2},
    {"name": "cmr_bb_full_satv1", "red": (1.0, 0.1, -0.1, 0.0),
     "green": (0.0, 1.0, 0.0, 0.0), "blue": (-0.05, 0.05, 1.0, 0.0),
     "saturation": (0.3, 0.0, -0.2, 0.1), "lightness": (0.0,) * 4,
     "grey": (0.0,) * 4, "normalize": (0,) * 6,
     "illuminant": 6, "illum_fluo": 2, "illum_led": 4,
     "adaptation": 2, "x": 0.333, "y": 0.333, "temperature": 3200.0,
     "gamut": 2.0, "clip": 1, "version": 0},
    {"name": "cmr_fluor_xyz", "red": (0.9, 0.05, 0.05, 0.0),
     "green": (0.05, 0.9, 0.05, 0.0), "blue": (0.0, 0.0, 1.0, 0.0),
     "saturation": (0.0,) * 4, "lightness": (0.1, -0.05, 0.0, 0.05),
     "grey": (0.0,) * 4, "normalize": (0,) * 6,
     "illuminant": 4, "illum_fluo": 3, "illum_led": 4,
     "adaptation": 3, "x": 0.333, "y": 0.333, "temperature": 5003.0,
     "gamut": 1.0, "clip": 0, "version": 2},
    {"name": "cmr_led_rgb_grey", "red": (1.0, 0.0, 0.0, 0.0),
     "green": (0.0, 1.0, 0.0, 0.0), "blue": (0.0, 0.0, 1.0, 0.0),
     "saturation": (0.0,) * 4, "lightness": (0.0,) * 4,
     "grey": (0.3, 0.5, 0.2, 0.0), "normalize": (0, 0, 0, 0, 0, 1),
     "illuminant": 5, "illum_fluo": 2, "illum_led": 4,
     "adaptation": 4, "x": 0.333, "y": 0.333, "temperature": 5003.0,
     "gamut": 1.0, "clip": 1, "version": 2},
    {"name": "cmr_custom_satv2", "red": (1.2, -0.1, -0.1, 0.0),
     "green": (-0.05, 1.1, -0.05, 0.0), "blue": (0.0, 0.0, 1.0, 0.0),
     "saturation": (-0.2, 0.3, 0.1, -0.1), "lightness": (0.0,) * 4,
     "grey": (0.0,) * 4, "normalize": (0, 0, 0, 1, 0, 0),
     "illuminant": 7, "illum_fluo": 2, "illum_led": 4,
     "adaptation": 1, "x": 0.42, "y": 0.38, "temperature": 5003.0,
     "gamut": 1.0, "clip": 1, "version": 1},
]
CHANNELMIXERRGB_REF_FIXTURES = ["ramp_8ev", "flat_0ev", "flat_-4ev",
                                "gray_staircase"]


def channelmixerrgb_case_params(case):
    return dict(
        red=case["red"], green=case["green"], blue=case["blue"],
        saturation=case["saturation"], lightness=case["lightness"],
        grey=case["grey"], normalizeR=bool(case["normalize"][0]),
        normalizeG=bool(case["normalize"][1]), normalizeB=bool(case["normalize"][2]),
        normalizeSat=bool(case["normalize"][3]),
        normalizeLight=bool(case["normalize"][4]),
        normalizeGrey=bool(case["normalize"][5]),
        illuminant=case["illuminant"], illumFluo=case["illum_fluo"],
        illumLED=case["illum_led"], adaptation=case["adaptation"],
        x=case["x"], y=case["y"], temperature=case["temperature"],
        gamut=case["gamut"], clip=bool(case["clip"]), version=case["version"])


def channelmixerrgb_params_blob_for_case(case) -> str:
    packed = struct.pack(
        CHANNELMIXERRGB_PARAMS_FORMAT,
        *case["red"], *case["green"], *case["blue"],
        *case["saturation"], *case["lightness"], *case["grey"],
        *case["normalize"], case["illuminant"], case["illum_fluo"],
        case["illum_led"], case["adaptation"],
        case["x"], case["y"], case["temperature"], case["gamut"],
        case["clip"], case["version"])
    assert len(packed) == 160, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def gen_channelmixerrgb_cases(outdir: str) -> None:
    for case in CHANNELMIXERRGB_CASES:
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION, iop_order_version=5,
            operation="channelmixerrgb", modversion=CHANNELMIXERRGB_MODVERSION,
            params=channelmixerrgb_params_blob_for_case(case),
            iop_order=f"{CHANNELMIXERRGB_IOP_ORDER:.1f}")
        with open(os.path.join(outdir, case["name"] + ".xmp"), "w") as f:
            f.write(xmp)


def gen_channelmixerrgb_refs(canonical_dir: str, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for case in CHANNELMIXERRGB_CASES:
        d = cm_derive(case)
        for fixture in CHANNELMIXERRGB_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)

            def px(x, y, rgb=rgb, case=case, d=d, w=w):
                idx = y * w + x
                return channelmixerrgb_apply_pixel(
                    (rgb[0][idx], rgb[1][idx], rgb[2][idx]), case, d)

            write_exr(os.path.join(out_dir, f"{case['name']}__{fixture}.exr"), w, h, px)


# legacy channelmixer：4 mode 全覆盖（RGB / gray / HSL v1 / HSL v2）。
def _cm_legacy_rgb2hsl(r, g, b):
    pmax, pmin = max(r, g, b), min(r, g, b)
    delta = pmax - pmin
    h = s = 0.0
    l = (pmin + pmax) / 2.0
    if delta != 0:
        s = delta / max(pmax + pmin, CM_NORM_MIN) if l < 0.5 else delta / max(2.0 - pmax - pmin, CM_NORM_MIN)
        if pmax == r:
            h = (g - b) / delta
        elif pmax == g:
            h = 2.0 + (b - r) / delta
        else:
            h = 4.0 + (r - g) / delta
        h /= 6.0
        if h < 0:
            h += 1.0
        elif h > 1:
            h -= 1.0
    return (h, s, l)


def _cm_legacy_hue2rgb(m1, m2, hue):
    if hue < 1.0:
        return m1 + (m2 - m1) * hue
    if hue < 3.0:
        return m2
    return m1 + (m2 - m1) * (4.0 - hue) if hue < 4.0 else m1


def _cm_legacy_hsl2rgb(h, s, l):
    if s == 0:
        return (l, l, l)
    m2 = l * (1.0 + s) if l < 0.5 else l + s - l * s
    m1 = 2.0 * l - m2
    hh = h * 6.0
    return (_cm_legacy_hue2rgb(m1, m2, hh + 2.0 if hh < 4.0 else hh - 4.0),
            _cm_legacy_hue2rgb(m1, m2, hh),
            _cm_legacy_hue2rgb(m1, m2, hh - 2.0 if hh > 2.0 else hh + 4.0))


def _cm_legacy_derive(case):
    hsl = [0.0] * 9
    for row in range(3):
        hsl[row * 3] = case["red"][row]
        hsl[row * 3 + 1] = case["green"][row]
        hsl[row * 3 + 2] = case["blue"][row]
    hsl_mix = any(case["red"][i] != 0 or case["green"][i] != 0 or case["blue"][i] != 0
                  for i in range(3))
    rgb = [0.0] * 9
    for row in range(3):
        rgb[row * 3] = case["red"][row + 3]
        rgb[row * 3 + 1] = case["green"][row + 3]
        rgb[row * 3 + 2] = case["blue"][row + 3]
    gray = (case["red"][6], case["green"][6], case["blue"][6])
    gray_mix = gray[0] != 0 or gray[1] != 0 or gray[2] != 0
    if gray_mix:
        mixed = [gray[0] * rgb[j] + gray[1] * rgb[3 + j] + gray[2] * rgb[6 + j]
                 for j in range(3)]
        for row in range(3):
            rgb[row * 3:row * 3 + 3] = mixed
    if case["algorithm"] == 0:
        mode = 2
    elif hsl_mix:
        mode = 3
    elif gray_mix:
        mode = 1
    else:
        mode = 0
    return (hsl, rgb, mode)


def channelmixer_apply_pixel(rgb, case):
    def clamp01(v):
        return min(max(v, 0.0), 1.0)
    hsl, mx, mode = _cm_legacy_derive(case)
    if mode == 0:
        return (max(mx[0] * rgb[0] + mx[1] * rgb[1] + mx[2] * rgb[2], 0.0),
                max(mx[3] * rgb[0] + mx[4] * rgb[1] + mx[5] * rgb[2], 0.0),
                max(mx[6] * rgb[0] + mx[7] * rgb[1] + mx[8] * rgb[2], 0.0))
    if mode == 1:
        g = max(mx[0] * rgb[0] + mx[1] * rgb[1] + mx[2] * rgb[2], 0.0)
        return (g, g, g)
    if mode == 2:
        hmix = clamp01(rgb[0] * hsl[0]) + rgb[1] * hsl[1] + rgb[2] * hsl[2]
        smix = clamp01(rgb[0] * hsl[3]) + rgb[1] * hsl[4] + rgb[2] * hsl[5]
        lmix = clamp01(rgb[0] * hsl[6]) + rgb[1] * hsl[7] + rgb[2] * hsl[8]
        r, g, b = rgb
        if hmix != 0 or smix != 0 or lmix != 0:
            h, s, l = _cm_legacy_rgb2hsl(*rgb)
            h = hmix if hmix != 0 else h
            s = smix if smix != 0 else s
            l = lmix if lmix != 0 else l
            r, g, b = _cm_legacy_hsl2rgb(h, s, l)
        return (clamp01(mx[0] * r + mx[1] * g + mx[2] * b),
                clamp01(mx[3] * r + mx[4] * g + mx[5] * b),
                clamp01(mx[6] * r + mx[7] * g + mx[8] * b))
    hmix = clamp01(hsl[0] * rgb[0] + hsl[1] * rgb[1] + hsl[2] * rgb[2])
    smix = clamp01(hsl[3] * rgb[0] + hsl[4] * rgb[1] + hsl[5] * rgb[2])
    lmix = clamp01(hsl[6] * rgb[0] + hsl[7] * rgb[1] + hsl[8] * rgb[2])
    r, g, b = rgb
    if hmix != 0 or smix != 0 or lmix != 0:
        r, g, b = (clamp01(v) for v in rgb)
        h, s, l = _cm_legacy_rgb2hsl(r, g, b)
        h = hmix if hmix != 0 else h
        s = smix if smix != 0 else s
        l = lmix if lmix != 0 else l
        r, g, b = _cm_legacy_hsl2rgb(h, s, l)
    return (max(mx[0] * r + mx[1] * g + mx[2] * b, 0.0),
            max(mx[3] * r + mx[4] * g + mx[5] * b, 0.0),
            max(mx[6] * r + mx[7] * g + mx[8] * b, 0.0))


CHANNELMIXER_CASES = [
    {"name": "cm_rgb_swap", "red": (0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0),
     "green": (0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0),
     "blue": (0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0), "algorithm": 1},
    {"name": "cm_gray_luma",
     "red": (0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.299),
     "green": (0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.587),
     "blue": (0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.114), "algorithm": 1},
    {"name": "cm_hsl_v1_sat", "red": (0.0, 0.5, 0.0, 1.0, 0.0, 0.0, 0.0),
     "green": (0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0),
     "blue": (0.0,) * 7, "algorithm": 0},
]
CHANNELMIXER_REF_FIXTURES = ["ramp_8ev", "flat_0ev", "flat_-4ev",
                             "gray_staircase", "saturated"]


def channelmixer_params_blob_for_case(case) -> str:
    packed = struct.pack(CHANNELMIXER_PARAMS_FORMAT,
                         *case["red"], *case["green"], *case["blue"],
                         case["algorithm"])
    # v2 params = 3×7 floats + algorithm int = 88B（CHANNEL_SIZE=7）。
    assert len(packed) == 88, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def gen_channelmixer_cases(outdir: str) -> None:
    for case in CHANNELMIXER_CASES:
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION, iop_order_version=5,
            operation="channelmixer", modversion=CHANNELMIXER_MODVERSION,
            params=channelmixer_params_blob_for_case(case),
            iop_order=f"{CHANNELMIXER_IOP_ORDER:.1f}")
        with open(os.path.join(outdir, case["name"] + ".xmp"), "w") as f:
            f.write(xmp)


def gen_channelmixer_refs(canonical_dir: str, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for case in CHANNELMIXER_CASES:
        for fixture in CHANNELMIXER_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)

            def px(x, y, rgb=rgb, case=case, w=w):
                idx = y * w + x
                return channelmixer_apply_pixel(
                    (rgb[0][idx], rgb[1][idx], rgb[2][idx]), case)

            write_exr(os.path.join(out_dir, f"{case['name']}__{fixture}.exr"), w, h, px)


# colorcontrast：3 case（含 unbound 双档）。
def colorcontrast_apply_pixel(lab, case):
    a = lab[1] * case["a_steepness"] + case["a_offset"]
    b = lab[2] * case["b_steepness"] + case["b_offset"]
    if not case["unbound"]:
        a = min(max(a, -128.0), 128.0)
        b = min(max(b, -128.0), 128.0)
    return (lab[0], a, b)


COLORCONTRAST_CASES = [
    {"name": "cc_default", "a_steepness": 1.0, "a_offset": 0.0,
     "b_steepness": 1.0, "b_offset": 0.0, "unbound": 1},
    {"name": "cc_steep", "a_steepness": 1.8, "a_offset": 5.0,
     "b_steepness": 0.6, "b_offset": -8.0, "unbound": 1},
    {"name": "cc_bound", "a_steepness": 3.0, "a_offset": 60.0,
     "b_steepness": 3.0, "b_offset": -60.0, "unbound": 0},
]
COLORCONTRAST_REF_FIXTURES = ["ramp_8ev", "flat_0ev", "flat_-4ev", "saturated",
                              "gray_staircase"]


def colorcontrast_params_blob_for_case(case) -> str:
    packed = struct.pack(COLORCONTRAST_PARAMS_FORMAT,
                         case["a_steepness"], case["a_offset"],
                         case["b_steepness"], case["b_offset"],
                         case["unbound"])
    assert len(packed) == 20, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def gen_colorcontrast_cases(outdir: str) -> None:
    for case in COLORCONTRAST_CASES:
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION, iop_order_version=5,
            operation="colorcontrast", modversion=COLORCONTRAST_MODVERSION,
            params=colorcontrast_params_blob_for_case(case),
            iop_order=f"{COLORCONTRAST_IOP_ORDER:.1f}")
        with open(os.path.join(outdir, case["name"] + ".xmp"), "w") as f:
            f.write(xmp)


def gen_colorcontrast_refs(canonical_dir: str, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for case in COLORCONTRAST_CASES:
        for fixture in COLORCONTRAST_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)

            def px(x, y, rgb=rgb, case=case, w=w):
                idx = y * w + x
                lab = lab_from_rec2020((rgb[0][idx], rgb[1][idx], rgb[2][idx]))
                return lab_to_rec2020(colorcontrast_apply_pixel(lab, case))

            write_exr(os.path.join(out_dir, f"{case['name']}__{fixture}.exr"), w, h, px)


# ──────────────────────────────────────────────────────────────────────
# Plan 05-04 (vibrance + velvia + colorzones) — float64 mirrors of the
# committed Swift references (VibranceModule/VelviaModule.reference +
# ColorZonesLUT/ColorZonesModule.reference with the CL-leg NEAREST
# lookup). L017 route: dt-side = XMP adoption + flat PFM probes.
# ──────────────────────────────────────────────────────────────────────

def vibrance_apply_pixel(lab, amount01):
    """vibrance.c:117-120 in float64 on Lab."""
    sw = math.hypot(lab[1], lab[2]) / 256.0
    ls = 1.0 - amount01 * sw * 0.25
    ss = 1.0 + amount01 * sw
    return (lab[0] * ls, lab[1] * ss, lab[2] * ss)


def velvia_apply_pixel(rgb, strength01, bias):
    """velvia.c:165-194 in float64 on linear RGB (clamp is the formula)."""
    if strength01 <= 0:
        # dt velvia.c:160 — strength <= 0 short-circuits to an unclamped copy
        return tuple(rgb)
    pmax = max(rgb)
    pmin = min(rgb)
    plum = (pmax + pmin) / 2.0
    if plum <= 0.5:
        psat = (pmax - pmin) / (1e-5 + pmax + pmin)
    else:
        psat = (pmax - pmin) / (1e-5 + max(0.0, 2.0 - pmax - pmin))
    pweight = min(max(
        ((1.0 - 1.5 * psat) + (1.0 + abs(plum - 0.5) * 2.0) * (1.0 - bias))
        / (1.0 + (1.0 - bias)), 0.0), 1.0)
    sat = strength01 * pweight
    others = (rgb[1] + rgb[2], rgb[2] + rgb[0], rgb[0] + rgb[1])
    return tuple(min(max(c + sat * (c - 0.5 * o), 0.0), 1.0)
                 for c, o in zip(rgb, others))


VIBRANCE_CASES = [
    {"name": "vib_default", "amount": 0.0},
    {"name": "vib_strong", "amount": 75.0},
]
VIBRANCE_REF_FIXTURES = ["ramp_8ev", "flat_0ev", "flat_-4ev", "saturated",
                         "gray_staircase", "hue_sweep"]


def vibrance_params_blob_for_case(case) -> str:
    packed = struct.pack(VIBRANCE_PARAMS_FORMAT, case["amount"])
    assert len(packed) == 4, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def gen_vibrance_cases(outdir: str) -> None:
    for case in VIBRANCE_CASES:
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION, iop_order_version=5,
            operation="vibrance", modversion=VIBRANCE_MODVERSION,
            params=vibrance_params_blob_for_case(case),
            iop_order=f"{VIBRANCE_IOP_ORDER:.1f}")
        with open(os.path.join(outdir, case["name"] + ".xmp"), "w") as f:
            f.write(xmp)


def gen_vibrance_refs(canonical_dir: str, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for case in VIBRANCE_CASES:
        amount01 = case["amount"] * 0.01
        for fixture in VIBRANCE_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)

            def px(x, y, rgb=rgb, amount01=amount01, w=w):
                idx = y * w + x
                lab = lab_from_rec2020((rgb[0][idx], rgb[1][idx], rgb[2][idx]))
                return lab_to_rec2020(vibrance_apply_pixel(lab, amount01))

            write_exr(os.path.join(out_dir, f"{case['name']}__{fixture}.exr"), w, h, px)


VELVIA_CASES = [
    {"name": "vel_default", "strength": 0.0, "bias": 1.0},
    {"name": "vel_strong", "strength": 75.0, "bias": 1.0},
    {"name": "vel_clamp", "strength": 100.0, "bias": 0.0},
]
VELVIA_REF_FIXTURES = ["ramp_8ev", "flat_0ev", "flat_-4ev", "saturated",
                       "gray_staircase", "hue_sweep"]


def velvia_params_blob_for_case(case) -> str:
    packed = struct.pack(VELVIA_PARAMS_FORMAT, case["strength"], case["bias"])
    assert len(packed) == 8, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def gen_velvia_cases(outdir: str) -> None:
    for case in VELVIA_CASES:
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION, iop_order_version=5,
            operation="velvia", modversion=VELVIA_MODVERSION,
            params=velvia_params_blob_for_case(case),
            iop_order=f"{VELVIA_IOP_ORDER:.1f}")
        with open(os.path.join(outdir, case["name"] + ".xmp"), "w") as f:
            f.write(xmp)


def gen_velvia_refs(canonical_dir: str, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for case in VELVIA_CASES:
        s01 = case["strength"] / 100.0
        bias = case["bias"]
        for fixture in VELVIA_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)

            def px(x, y, rgb=rgb, s01=s01, bias=bias, w=w):
                idx = y * w + x
                return velvia_apply_pixel(
                    (rgb[0][idx], rgb[1][idx], rgb[2][idx]), s01, bias)

            write_exr(os.path.join(out_dir, f"{case['name']}__{fixture}.exr"), w, h, px)


# colorzones: V2-spline mirrors (ColorZonesLUT) + v3 process mirror with
# the CL-leg NEAREST lookup (the GPU leg the kernel follows).

def _cz_g_variant(s1, s2, h1, h2):
    if s1 * s2 > 0:
        alpha = (h1 + 2.0 * h2) / (3.0 * (h1 + h2))
        return s1 * s2 / (alpha * s2 + (1.0 - alpha) * s1)
    return 0.0


def _cz_monotone_variant_tangents(xs, ys):
    n = len(xs)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    dy = [0.0] * n
    dy[0] = d[0]
    for i in range(1, n - 1):
        dy[i] = _cz_g_variant(d[i - 1], d[i], h[i - 1], h[i])
    dy[n - 1] = d[n - 2]
    return dy


def _cz_periodic_monotone_variant_tangents(xs, ys, period=1.0):
    n = len(xs)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)] + [xs[0] - xs[n - 1] + period]
    d = [(ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) for i in range(n - 1)]
    d = d + [(ys[0] - ys[n - 1]) / (xs[0] - xs[n - 1] + period)]
    return [_cz_g_variant(d[i - 1], d[i], h[i - 1], h[i]) for i in range(n)]


def _cz_periodic_catmull_tangents(xs, ys, period=1.0):
    n = len(xs)
    if n == 1:
        return [0.0]
    dy = [0.0] * n
    dy[0] = (ys[1] - ys[n - 1]) / (xs[1] - xs[n - 1] + period)
    for i in range(1, n - 1):
        dy[i] = (ys[i + 1] - ys[i - 1]) / (xs[i + 1] - xs[i - 1])
    dy[n - 1] = (ys[0] - ys[n - 2]) / (xs[0] - xs[n - 2] + period)
    return dy


def _cz_periodic_cubic_tangents(xs, ys, period=1.0):
    # Cyclic natural spline via dense Gauss solve (mirrors
    # ColorZonesLUT.periodicCubicTangents).
    n = len(xs)
    if n == 1:
        return [0.0]
    dx = [xs[i + 1] - xs[i] for i in range(n - 1)] + [xs[0] - xs[n - 1] + period]
    dyv = [ys[i + 1] - ys[i] for i in range(n - 1)] + [ys[0] - ys[n - 1]]
    A = [[0.0] * n for _ in range(n)]
    b = [0.0] * n
    for i in range(1, n - 1):
        A[i][i - 1] = dx[i - 1] / 6.0
        A[i][i] = (dx[i - 1] + dx[i]) / 3.0
        A[i][i + 1] = dx[i] / 6.0
        b[i] = dyv[i] / dx[i] - dyv[i - 1] / dx[i - 1]
    if n > 2:
        A[0][0] = (dx[n - 1] + dx[0]) / 3.0
        A[n - 1][n - 1] = (dx[n - 2] + dx[n - 1]) / 3.0
        b[0] = dyv[0] / dx[0] - dyv[n - 1] / dx[n - 1]
        b[n - 1] = dyv[n - 1] / dx[n - 1] - dyv[n - 2] / dx[n - 2]
        A[0][1] = dx[0] / 6.0
        A[n - 1][n - 2] = dx[n - 2] / 6.0
        A[0][n - 1] = dx[n - 1] / 6.0
        A[n - 1][0] = dx[n - 1] / 6.0
    else:
        A[0][0] = (dx[1] + dx[0]) / 3.0
        A[1][1] = (dx[0] + dx[1]) / 3.0
        A[0][1] = (dx[0] + dx[1]) / 6.0
        A[1][0] = (dx[0] + dx[1]) / 6.0
        b[0] = dyv[0] / dx[0] - dyv[1] / dx[1]
        b[1] = dyv[1] / dx[1] - dyv[0] / dx[0]
    # LU without pivoting (dense).
    for i in range(n - 1):
        t = A[i][i]
        assert t != 0.0
        for k in range(i + 1, n):
            A[k][i] /= t
            for j in range(i + 1, n):
                A[k][j] -= A[k][i] * A[i][j]
    for i in range(n):
        for k in range(i):
            b[i] -= A[i][k] * b[k]
    for i in range(n - 1, -1, -1):
        for k in range(i + 1, n):
            b[i] -= A[i][k] * b[k]
        b[i] /= A[i][i]
    dy = [0.0] * n
    c_last = 0.0
    for i in range(n - 1):
        c = dyv[i] / dx[i] - dx[i] / 6.0 * (b[i + 1] - b[i])
        dy[i] = -dx[i] * b[i] / 2.0 + c
        c_last = c
    dy[n - 1] = dx[n - 2] * b[n - 1] / 2.0 + c_last
    return dy


def _cz_eval_periodic(xs, ys, m, xval, period=1.0):
    n = len(xs)
    if n == 1:
        return ys[0]
    xv = xval % period
    if xv < xs[0]:
        xv += period
    n0 = n - 1
    for i in range(n):
        if xv < xs[i]:
            n0 = n - 1 if i == 0 else i - 1
            break
    n1 = (n0 + 1) % n
    h = (xs[n1] - xs[n0]) if n1 > n0 else (xs[n1] - (xs[n0] - period))
    dx = (xv - xs[n0]) / h
    dx2, dx3 = dx * dx, dx * dx * dx
    return ((2.0 * dx3 - 3.0 * dx2 + 1.0) * ys[n0]
            + (dx3 - 2.0 * dx2 + dx) * h * m[n0]
            + (-2.0 * dx3 + 3.0 * dx2) * ys[n1]
            + (dx3 - dx2) * h * m[n1])


def colorzones_build_table(nodes, curve_type, strength, periodic):
    """ColorZonesLUT.buildTable mirror (V2 verdict). nodes = [(x,y)]."""
    res = 0x10000
    table = [0.0] * res
    if len(nodes) < 2:
        return [k / (res - 1) for k in range(res)]
    xs = [p[0] for p in nodes]
    ys = [p[1] + (p[1] - 0.5) * (strength / 100.0) for p in nodes]
    for i in range(len(xs) - 1):
        if xs[i + 1] <= xs[i]:
            return [k / (res - 1) for k in range(res)]
    if periodic:
        if curve_type == 0:
            m = _cz_periodic_cubic_tangents(xs, ys)
        elif curve_type == 1:
            m = _cz_periodic_catmull_tangents(xs, ys)
        else:
            m = _cz_periodic_monotone_variant_tangents(xs, ys)
        return [_cz_eval_periodic(xs, ys, m, k / (res - 1)) for k in range(res)]
    else:
        if curve_type == 0:
            ypp = cubic_spline_second_derivatives(xs, ys)
            if ypp is None:
                return [k / (res - 1) for k in range(res)]
            # ypp -> dy (same conversion as Swift cubicTangents).
            n = len(xs)
            m = [0.0] * n
            c_last = 0.0
            for i in range(n - 1):
                dx = xs[i + 1] - xs[i]
                c = (ys[i + 1] - ys[i]) / dx - dx / 6.0 * (ypp[i + 1] - ypp[i])
                m[i] = -dx * ypp[i] / 2.0 + c
                c_last = c
            m[n - 1] = c_last
        elif curve_type == 1:
            m = catmull_rom_tangents(xs, ys)
        else:
            m = _cz_monotone_variant_tangents(xs, ys)
        step = 1.0 / (res - 1)
        out = [0.0] * res
        for k in range(res):
            xk = k * step
            if xk < xs[0]:
                v = ys[0]
            elif xk > xs[-1]:
                v = ys[-1]
            else:
                v = hermite_val(xs, ys, m, xk)
            out[k] = max(0.0, min(1.0, v))
        return out


def _cz_lookup_nearest(lut, x):
    """dt CL lookup (color_conversion.h:70-75): truncation."""
    return lut[min(max(int(x * 0x10000), 0), 0xFFFF)]


def colorzones_apply_pixel(lab, tables, channel):
    """process_v3 (:526-570) in float64 with the NEAREST lookup."""
    a, b = lab[1], lab[2]
    h = math.fmod(math.atan2(b, a) + 2.0 * math.pi, 2.0 * math.pi) / (2.0 * math.pi)
    c = math.hypot(b, a)
    blend = 0.0
    if channel == 0:
        select = min(1.0, lab[0] / 100.0)
    elif channel == 1:
        select = min(1.0, c / 128.0)
    else:
        select = h
        blend = (1.0 - c / 128.0) ** 2
    lm = (blend * 0.5 + (1.0 - blend) * _cz_lookup_nearest(tables[0], select)) - 0.5
    hm = (blend * 0.5 + (1.0 - blend) * _cz_lookup_nearest(tables[2], select)) - 0.5
    blend *= blend
    cm = 2.0 * _cz_lookup_nearest(tables[1], select)
    l = lab[0] * (2.0 ** (4.0 * lm))
    ang = 2.0 * math.pi * (h + hm)
    return (l, math.cos(ang) * cm * c, math.sin(ang) * cm * c)


# 4 colorzones cases (each select domain L/C/h + hue low-sat suppression).
# Identity nodes mirror _reset_nodes (L/C touch_edges, h centered).
COLORZONES_CASES = [
    {"name": "cz_default", "channel": 2,
     "nodesL": [(0.0, 0.5), (1.0, 0.5)], "typeL": 1,
     "nodesC": [(0.0, 0.5), (1.0, 0.5)], "typeC": 1,
     "nodesH": [(0.25, 0.5), (0.75, 0.5)], "typeH": 1,
     "strength": 0.0, "mode": 0},
    {"name": "cz_lightness", "channel": 0,
     "nodesL": [(0.0, 0.3), (0.5, 0.65), (1.0, 0.45)], "typeL": 1,
     "nodesC": [(0.0, 0.5), (1.0, 0.5)], "typeC": 1,
     "nodesH": [(0.25, 0.5), (0.75, 0.5)], "typeH": 1,
     "strength": 0.0, "mode": 0},
    {"name": "cz_chroma", "channel": 1,
     "nodesL": [(0.0, 0.5), (1.0, 0.5)], "typeL": 1,
     "nodesC": [(0.0, 0.2), (0.5, 0.8), (1.0, 0.35)], "typeC": 2,
     "nodesH": [(0.25, 0.5), (0.75, 0.5)], "typeH": 1,
     "strength": 0.0, "mode": 0},
    {"name": "cz_hue", "channel": 2,
     "nodesL": [(0.0, 0.5), (1.0, 0.5)], "typeL": 1,
     "nodesC": [(0.0, 0.5), (1.0, 0.5)], "typeC": 1,
     "nodesH": [(0.0, 0.5), (0.25, 0.75), (0.5, 0.3), (0.75, 0.6)], "typeH": 2,
     "strength": 50.0, "mode": 0},
]
COLORZONES_REF_FIXTURES = ["ramp_8ev", "flat_0ev", "flat_-4ev", "saturated",
                           "gray_staircase", "hue_sweep"]


def colorzones_params_blob_for_case(case) -> str:
    """dt params v5 (520B) for the case. Nodes beyond len pad (0,0)."""
    curves = []
    for key in ("nodesL", "nodesC", "nodesH"):
        nodes = case[key]
        for i in range(20):
            if i < len(nodes):
                curves += [nodes[i][0], nodes[i][1]]
            else:
                curves += [0.0, 0.0]
    packed = struct.pack(
        COLORZONES_PARAMS_FORMAT,
        case["channel"], *curves,
        len(case["nodesL"]), len(case["nodesC"]), len(case["nodesH"]),
        case["typeL"], case["typeC"], case["typeH"],
        case["strength"], case["mode"], 1)
    assert len(packed) == 520, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def gen_colorzones_cases(outdir: str) -> None:
    for case in COLORZONES_CASES:
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION, iop_order_version=5,
            operation="colorzones", modversion=COLORZONES_MODVERSION,
            params=colorzones_params_blob_for_case(case),
            iop_order=f"{COLORZONES_IOP_ORDER:.1f}")
        with open(os.path.join(outdir, case["name"] + ".xmp"), "w") as f:
            f.write(xmp)


def gen_colorzones_refs(canonical_dir: str, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for case in COLORZONES_CASES:
        tables = (
            colorzones_build_table(case["nodesL"], case["typeL"],
                                   case["strength"], periodic=False),
            colorzones_build_table(case["nodesC"], case["typeC"],
                                   case["strength"], periodic=False),
            colorzones_build_table(case["nodesH"], case["typeH"],
                                   case["strength"],
                                   periodic=(case["channel"] == 2)),
        )
        for fixture in COLORZONES_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)

            def px(x, y, rgb=rgb, tables=tables, channel=case["channel"], w=w):
                idx = y * w + x
                lab = lab_from_rec2020((rgb[0][idx], rgb[1][idx], rgb[2][idx]))
                return lab_to_rec2020(colorzones_apply_pixel(lab, tables, channel))

            write_exr(os.path.join(out_dir, f"{case['name']}__{fixture}.exr"), w, h, px)


# monochrome: filter + bilateral-grid full-chain mirror (MonochromeModule +
# BilateralGridReference Swift mirrors; CPU sigma2 = 2*(size*128)^2,
# monochrome.c:205; grid sigma_s=20/scale, sigma_r=250, detail=-1, :220-229).
# Small fixtures (<=64px) run the true grid; larger fixtures reuse the
# slice-through-grid path identically (grid dims grow sub-linearly).

def monochrome_color_filter(ai, bi, a, b, sigma2):
    """_color_filter (:168-175) in float64 (exact exp; dt_fast_expf
    deviation recorded in 05-05-DECISIONS D3)."""
    t = min(max(((ai - a) ** 2 + (bi - b) ** 2) / sigma2, 0.0), 1.0)
    return math.exp(-t)


def monochrome_envelope(L):
    """_envelope (:177-195) in float64."""
    x = min(max(L / 100.0, 0.0), 1.0)
    beta = 0.6
    if x < beta:
        tmp = x / beta - 1.0
        return 1.0 - tmp * tmp
    tmp1 = (1.0 - x) / (1.0 - beta)
    tmp2 = tmp1 * tmp1
    tmp3 = tmp2 * tmp1
    return 3.0 * tmp2 - 2.0 * tmp3


def _mono_grid_point(g, i, j, l):
    x = min(max(i / g["ss"], 0.0), g["sx"] - 1)
    y = min(max(j / g["ss"], 0.0), g["sy"] - 1)
    z = min(max(l / g["sr"], 0.0), g["sz"] - 1)
    xi = min(int(x), g["sx"] - 2)
    yi = min(int(y), g["sy"] - 2)
    zi = min(int(z), g["sz"] - 2)
    return ((xi + yi * g["sx"]) * g["sz"] + zi, x - xi, y - yi, z - zi)


def _mono_make_grid(w, h, sigmaS, sigmaR, lRange=100.0):
    """BilateralGridReference.makeGrid mirror (grid_size straight port)."""
    ss = max(sigmaS, 0.5)
    x0 = min(max(int(round(w / ss)), 4), 3000)
    y0 = min(max(int(round(h / ss)), 4), 3000)
    z0 = min(max(int(round(lRange / sigmaR)), 4), 50)
    ss = max(h / y0, w / x0)
    sr = lRange / z0
    sx = int(math.ceil(w / ss)) + 1
    sy = int(math.ceil(h / ss)) + 1
    sz = int(math.ceil(lRange / sr)) + 1
    return {"sx": sx, "sy": sy, "sz": sz, "ss": ss, "sr": sr,
            "payload": [0.0] * (sx * sy * sz)}


def _mono_splat(g, luma, w, h):
    scale = 100.0 / (g["ss"] * g["ss"])
    for j in range(h):
        for i in range(w):
            l = luma[j * w + i]
            gi, fx, fy, fz = _mono_grid_point(g, i, j, l)
            # dt CPU strides (bilateral.c:204-206).
            ox, oy, oz = g["sz"], g["sx"] * g["sz"], 1
            for off, wt in ((0, (1 - fx) * (1 - fy)),
                            (ox, fx * (1 - fy)),
                            (oy, (1 - fx) * fy),
                            (oy + ox, fx * fy)):
                g["payload"][gi + off] += wt * (1 - fz) * scale
                g["payload"][gi + off + oz] += wt * fz * scale


def _mono_blur_dim(g, axis):
    nx, ny, nz = g["sx"], g["sy"], g["sz"]
    w0, w1, w2 = 6.0 / 16.0, 4.0 / 16.0, 1.0 / 16.0
    src = list(g["payload"])
    dst = list(src)

    def idx(x, y, z):
        return (x + y * nx) * nz + z
    if axis == 0:
        for y in range(ny):
            for z in range(nz):
                t1 = src[idx(0, y, z)]
                dst[idx(0, y, z)] = src[idx(0, y, z)] * w0 + w1 * src[idx(1, y, z)] + w2 * src[idx(2, y, z)]
                t2 = src[idx(1, y, z)]
                dst[idx(1, y, z)] = src[idx(1, y, z)] * w0 + w1 * (src[idx(2, y, z)] + t1) + w2 * src[idx(min(3, nx - 1), y, z)]
                for x in range(2, nx - 2):
                    t3 = src[idx(x, y, z)]
                    dst[idx(x, y, z)] = src[idx(x, y, z)] * w0 + w1 * (src[idx(x + 1, y, z)] + t2) + w2 * (src[idx(x + 2, y, z)] + t1)
                    t1, t2 = t2, t3
                if nx > 3:
                    t3 = src[idx(nx - 2, y, z)]
                    dst[idx(nx - 2, y, z)] = src[idx(nx - 2, y, z)] * w0 + w1 * (src[idx(nx - 1, y, z)] + t2) + w2 * t1
                    dst[idx(nx - 1, y, z)] = src[idx(nx - 1, y, z)] * w0 + w1 * t3 + w2 * t2
    else:
        for x in range(nx):
            for z in range(nz):
                t1 = src[idx(x, 0, z)]
                dst[idx(x, 0, z)] = src[idx(x, 0, z)] * w0 + w1 * src[idx(x, 1, z)] + w2 * src[idx(x, 2, z)]
                t2 = src[idx(x, 1, z)]
                dst[idx(x, 1, z)] = src[idx(x, 1, z)] * w0 + w1 * (src[idx(x, 2, z)] + t1) + w2 * src[idx(x, min(3, ny - 1), z)]
                for y in range(2, ny - 2):
                    t3 = src[idx(x, y, z)]
                    dst[idx(x, y, z)] = src[idx(x, y, z)] * w0 + w1 * (src[idx(x, y + 1, z)] + t2) + w2 * (src[idx(x, y + 2, z)] + t1)
                    t1, t2 = t2, t3
                if ny > 3:
                    t3 = src[idx(x, ny - 2, z)]
                    dst[idx(x, ny - 2, z)] = src[idx(x, ny - 2, z)] * w0 + w1 * (src[idx(x, ny - 1, z)] + t2) + w2 * t1
                    dst[idx(x, ny - 1, z)] = src[idx(x, ny - 1, z)] * w0 + w1 * t3 + w2 * t2
    g["payload"] = dst


def _mono_blur_z(g):
    nx, ny, nz = g["sx"], g["sy"], g["sz"]
    w1, w2 = 4.0 / 16.0, 2.0 / 16.0
    src = list(g["payload"])
    dst = list(src)

    def idx(x, y, z):
        return (x + y * nx) * nz + z
    for x in range(nx):
        for y in range(ny):
            t1 = src[idx(x, y, 0)]
            dst[idx(x, y, 0)] = w1 * src[idx(x, y, 1)] + w2 * src[idx(x, y, min(2, nz - 1))]
            t2 = src[idx(x, y, 1)]
            dst[idx(x, y, 1)] = w1 * (src[idx(x, y, 2)] - t1) + w2 * src[idx(x, y, min(3, nz - 1))]
            for z in range(2, nz - 2):
                t3 = src[idx(x, y, z)]
                dst[idx(x, y, z)] = w1 * (src[idx(x, y, z + 1)] - t2) + w2 * (src[idx(x, y, z + 2)] - t1)
                t1, t2 = t2, t3
            if nz > 3:
                t3 = src[idx(x, y, nz - 2)]
                dst[idx(x, y, nz - 2)] = w1 * (src[idx(x, y, nz - 1)] - t2) - w2 * t1
                dst[idx(x, y, nz - 1)] = -w1 * t3 - w2 * t2
    g["payload"] = dst


def _mono_slice(g, luma, w, h, detail=-1.0):
    norm = -detail * g["sr"] * 0.04
    out = [0.0] * (w * h)
    for j in range(h):
        for i in range(w):
            l = luma[j * w + i]
            gi, fx, fy, fz = _mono_grid_point(g, i, j, l)
            # dt CPU strides (bilateral.c:405-407).
            ox, oy, oz = g["sz"], g["sx"] * g["sz"], 1
            ldiff = (g["payload"][gi] * (1 - fx) * (1 - fy) * (1 - fz)
                     + g["payload"][gi + ox] * fx * (1 - fy) * (1 - fz)
                     + g["payload"][gi + oy] * (1 - fx) * fy * (1 - fz)
                     + g["payload"][gi + ox + oy] * fx * fy * (1 - fz)
                     + g["payload"][gi + oz] * (1 - fx) * (1 - fy) * fz
                     + g["payload"][gi + ox + oz] * fx * (1 - fy) * fz
                     + g["payload"][gi + oy + oz] * (1 - fx) * fy * fz
                     + g["payload"][gi + ox + oy + oz] * fx * fy * fz)
            out[j * w + i] = max(0.0, l + norm * ldiff)
    return out


def monochrome_apply_pixel(lin, f_smooth, highlights):
    """process apply leg (:232-238) in float64."""
    tt = monochrome_envelope(lin)
    t = tt + (1.0 - tt) * (1.0 - highlights)
    return (1.0 - t) * lin + t * f_smooth * lin / 100.0


# 4 monochrome cases (neutral/size-sweep + warm/cool filters + highlights
# extreme). size=100 ~ identity-adjacent (filter->1 within 1e-9 on the
# fixture chroma range); highlights=1 extreme exercises the t-mix floor.
MONOCHROME_CASES = [
    {"name": "mono_neutral", "a": 0.0, "b": 0.0, "size": 100.0, "highlights": 0.0},
    {"name": "mono_warm", "a": 32.0, "b": 64.0, "size": 2.3, "highlights": 0.0},
    {"name": "mono_cool", "a": 0.0, "b": -64.0, "size": 2.3, "highlights": 0.0},
    {"name": "mono_highlights", "a": 32.0, "b": 64.0, "size": 2.3, "highlights": 1.0},
]
MONOCHROME_REF_FIXTURES = ["ramp_8ev", "flat_0ev", "flat_-4ev",
                           "gray_staircase"]


def monochrome_params_blob_for_case(case) -> str:
    packed = struct.pack(MONOCHROME_PARAMS_FORMAT, case["a"], case["b"],
                         case["size"], case["highlights"])
    assert len(packed) == 16, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def gen_monochrome_cases(outdir: str) -> None:
    for case in MONOCHROME_CASES:
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION, iop_order_version=5,
            operation="monochrome", modversion=MONOCHROME_MODVERSION,
            params=monochrome_params_blob_for_case(case),
            iop_order=f"{MONOCHROME_IOP_ORDER:.1f}")
        with open(os.path.join(outdir, case["name"] + ".xmp"), "w") as f:
            f.write(xmp)


def gen_monochrome_refs(canonical_dir: str, out_dir: str) -> None:
    """Synthesize the monochrome golden REFERENCES (L017 route; dt-side =
    XMP adoption + flat PFM probe). 4 case x 4 fixture (grid leg small-fixture
    exact; dt CPU sigma2)."""
    os.makedirs(out_dir, exist_ok=True)
    for case in MONOCHROME_CASES:
        sigma2 = 2.0 * (case["size"] * 128.0) ** 2
        for fixture in MONOCHROME_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)
            labs = [lab_from_rec2020((rgb[0][k], rgb[1][k], rgb[2][k]))
                    for k in range(w * h)]
            filt = [100.0 * monochrome_color_filter(
                lab[1], lab[2], case["a"], case["b"], sigma2) for lab in labs]
            g = _mono_make_grid(w, h, 20.0, 250.0)
            _mono_splat(g, filt, w, h)
            _mono_blur_dim(g, 0)
            _mono_blur_dim(g, 1)
            _mono_blur_z(g)
            smooth = _mono_slice(g, filt, w, h)
            out_lab = [
                (monochrome_apply_pixel(labs[k][0], smooth[k], case["highlights"]), 0.0, 0.0)
                for k in range(w * h)]
            out_rgb = [lab_to_rec2020(lab) for lab in out_lab]

            def px(x, y, out_rgb=out_rgb, w=w):
                idx = y * w + x
                return out_rgb[idx]

            write_exr(os.path.join(out_dir, f"{case['name']}__{fixture}.exr"), w, h, px)

# ──────────────────────────────────────────────────────────────────────
# NLMeans (Plan 05-06-T2, IOP-DENOISE-02) — Goossens float64 reference
# (L017 route; dt-side = XMP adoption + flat probe). 逐式直译 dt
# nlmeans.cl:37-253 + nlmeans.c:170-173,362-368 + nlmeans_core.c:103-118：
# 半平面偏移枚举 (j∈[−K,0], i∈[−K,K])、边界 clamp 的 separable box 和、
# 对称累积、finish 混合；fast_mexp2f 位级复刻（float 值域构造指数位）。
# 参考在 scale=1（roi.scale=1, iscale=1）跑：P=ceil(radius), K=7。
# ──────────────────────────────────────────────────────────────────────

NLMEANS_PARAMS_FORMAT = "<4f"
NLMEANS_MODVERSION = 2
NLMEANS_IOP_ORDER = 29.0


def nlmeans_fast_mexp2f(x):
    """dt common.h:181-191 bit-exact: build the float exponent field in
    VALUE space (i1/i2 are the bit patterns of 1.0/0.5 as integers),
    truncate to an integer whose bits ARE the result float."""
    i1 = 1065353216.0  # (float)0x3f800000u
    i2 = 1056964608.0  # (float)0x3f000000u
    k0 = i1 + x * (i2 - i1)
    if k0 >= 8388608.0:
        return struct.unpack("<f", struct.pack("<I", int(k0)))[0]
    return 0.0


def nlmeans_offsets(k, decimate):
    """dt GPU half-plane order (nlmeans.c:268-269) with the nlmeans_core
    decimate skip parity (:103-118 — counter starts 1, pre-increment,
    odd → skip)."""
    out = []
    counter = 1 if decimate else 0
    for j in range(-k, 1):
        for i in range(-k, k + 1):
            if decimate:
                counter += 1
                if counter & 1:
                    continue
            out.append((i, j))
    return out


def nlmeans_reference(w, h, rgb, radius, strength, luma, chroma):
    """Full Goossens chain in float64 at scale=1: Lab domain, half-plane
    offsets, border-clamped box sums (dt wing fills clamp — :94-107),
    gh weight in vert, symmetric accu (:183-230), finish blend (:233-253).
    Returns list of linear-Rec2020 triples."""
    nL2 = 1.0 / (120.0 * 120.0)
    nC2 = 1.0 / (512.0 * 512.0)
    sharpness = 3000.0 / (1.0 + strength)
    P = int(math.ceil(radius))
    K = 7
    labs = [lab_from_rec2020((rgb[0][k], rgb[1][k], rgb[2][k])) for k in range(w * h)]

    def cl(v, hi):
        return min(max(v, 0), hi)

    u2 = [[0.0, 0.0, 0.0, 0.0] for _ in range(w * h)]
    for (qx, qy) in nlmeans_offsets(K, False):
        # dist (nlmeans.cl:37-68): OOB offsets → exactly 0.
        dist = [0.0] * (w * h)
        for y in range(h):
            for x in range(w):
                if not (0 <= x + qx < w and 0 <= y + qy < h):
                    continue
                p1 = labs[y * w + x]
                p2 = labs[(y + qy) * w + (x + qx)]
                dist[y * w + x] = (
                    (p1[0] - p2[0]) ** 2 * nL2
                    + (p1[1] - p2[1]) ** 2 * nC2
                    + (p1[2] - p2[2]) ** 2 * nC2
                )
        # horiz box (:70-123) — border-CLAMPED reads (dt wing fill clamps).
        tmp = [0.0] * (w * h)
        for y in range(h):
            row = y * w
            for x in range(w):
                acc = 0.0
                for pi in range(-P, P + 1):
                    acc += dist[row + cl(x + pi, w - 1)]
                tmp[row + x] = acc
        # vert box + gh weight (:125-181).
        wgt = [0.0] * (w * h)
        for y in range(h):
            for x in range(w):
                acc = 0.0
                for pj in range(-P, P + 1):
                    acc += tmp[cl(y + pj, h - 1) * w + x]
                wgt[y * w + x] = nlmeans_fast_mexp2f(acc * sharpness)
        # accu (:183-230) — symmetric half-plane accumulation.
        dd = 0.0 if (qx == 0 and qy == 0) else 1.0
        for y in range(h):
            for x in range(w):
                wpq = 1 if (0 <= x + qx < w and 0 <= y + qy < h) else 0
                wmq = 1 if (0 <= x - qx < w and 0 <= y - qy < h) else 0
                u4 = wgt[y * w + x]
                u4_mq = wgt[cl(y - qy, h - 1) * w + cl(x - qx, w - 1)] * dd
                cell = u2[y * w + x]
                if wpq:
                    up = labs[(y + qy) * w + (x + qx)]
                    cell[0] += u4 * up[0]
                    cell[1] += u4 * up[1]
                    cell[2] += u4 * up[2]
                if wmq:
                    um = labs[(y - qy) * w + (x - qx)]
                    cell[0] += u4_mq * um[0]
                    cell[1] += u4_mq * um[1]
                    cell[2] += u4_mq * um[2]
                cell[3] += wpq * u4 + wmq * u4_mq
    # finish (:233-253) — weight = (luma, chroma, chroma), then Lab → RGB.
    weight = (luma, chroma, chroma)
    out = []
    for k in range(w * h):
        i = labs[k]
        u = u2[k]
        u3 = u[3]
        lab = tuple(
            i[c] * (1.0 - weight[c]) + (u[c] / u3) * weight[c] for c in range(3)
        )
        out.append(lab_to_rec2020(lab))
    return out


# 4 pinned cases (dt $DEFAULT + strength-dominant + chroma-dominant +
# larger patch). luma 0.1 case doubles as the IOP-DENOISE-04 chroma
# half-edge carrier (T4 direction assertions read it).
NLMEANS_CASES = [
    {"name": "nlmeans_default", "radius": 2.0, "strength": 50.0,
     "luma": 0.5, "chroma": 1.0},
    {"name": "nlmeans_strong", "radius": 3.0, "strength": 200.0,
     "luma": 0.8, "chroma": 0.6},
    {"name": "nlmeans_chroma", "radius": 2.0, "strength": 50.0,
     "luma": 0.1, "chroma": 1.0},
    {"name": "nlmeans_patch4", "radius": 4.0, "strength": 10.0,
     "luma": 0.5, "chroma": 1.0},
]

# 3 fixtures: delta impulse (kernel response) + the 05-01 seeded noise set
# (clean + Poisson-Gaussian ISO125/ISO1600 → both sides denoise the SAME
# noisy input — the denoise golden strategy, RESEARCH §7).
NLMEANS_REF_FIXTURES = [
    "delta_impulse",
    "ramp_8ev__noisy_iso125_s20260921",
    "gray_staircase__noisy_iso1600_s20260921",
]


def nlmeans_params_blob_for_case(case) -> str:
    packed = struct.pack(NLMEANS_PARAMS_FORMAT, case["radius"],
                         case["strength"], case["luma"], case["chroma"])
    assert len(packed) == 16, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def gen_nlmeans_cases(outdir: str) -> None:
    for case in NLMEANS_CASES:
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION, iop_order_version=5,
            operation="nlmeans", modversion=NLMEANS_MODVERSION,
            params=nlmeans_params_blob_for_case(case),
            iop_order=f"{NLMEANS_IOP_ORDER:.1f}")
        with open(os.path.join(outdir, case["name"] + ".xmp"), "w") as f:
            f.write(xmp)


def gen_nlmeans_refs(canonical_dir: str, out_dir: str) -> None:
    """Synthesize the nlmeans golden REFERENCES (L017 route; dt-side =
    XMP adoption + flat probe). 4 case x 3 fixture, float64 reference at
    scale=1 (P=ceil(radius), K=7)."""
    os.makedirs(out_dir, exist_ok=True)
    for case in NLMEANS_CASES:
        for fixture in NLMEANS_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)
            out_rgb = nlmeans_reference(
                w, h, rgb, case["radius"], case["strength"],
                case["luma"], case["chroma"])

            def px(x, y, out_rgb=out_rgb, w=w):
                idx = y * w + x
                return out_rgb[idx]

            write_exr(os.path.join(out_dir, f"{case['name']}__{fixture}.exr"), w, h, px)


# ──────────────────────────────────────────────────────────────────────
# denoiseprofile (Plan 05-07, IOP-DENOISE-01) — dt `denoiseprofile` v12
# (416B blob recipe above), v50 slot 9.0, POST-DEMOSAIC RGB domain
# (denoiseprofile.c:837 IOP_CS_RGB — RESEARCH §1.2 erratum, NOT raw).
#
# float64 reference (L017 route ①): wavelets leg = denoiseprofile.c
# 1423-1658 (process_wavelets CPU form — the dt-cli authority path) +
# eaw.c:271-363 (eaw_dn_decompose edge-aware 5×5 a-trous) + :1345-1421
# (Bayesshrink) + denoiseprofile.cl:31-114/327-433 (VST trio + inverse
# trio, v2/Y0U0V0 default); NLMeans leg = VST sandwich + Goossens with
# the denoiseprofile vert variant (single-pixel distance + central
# weight + `norm − 2` offset, denoiseprofile.cl:197-252) + finish_v2
# (backtransform fused, :327-350).
#
# wb policy (D-05-07-T2-1): v1 neutral wb = (1,1,1) — dt reads
# `dsc.temperature.coeffs`; CIRAW does not expose camera WB gains, so
# the module runs compute_wb_factors' neutral branch (coeffs==0 → 1s).
# All formulas stay exact; wb_adaptive_anscombe bit honored in the
# derivation path.
# ──────────────────────────────────────────────────────────────────────

DN_BANDS = 7
DN_P_FULCRUM = 0.05
DENOISEPROFILE_IOP_ORDER = 9.0

# eaw.c:122-129 / 276-283 — the 5×5 B3-spline outer-product a-trous base
# filter (shared verbatim by decompose legs).
FILTER25 = (
    1.0 / 256.0,  4.0 / 256.0,  6.0 / 256.0,  4.0 / 256.0, 1.0 / 256.0,
    4.0 / 256.0, 16.0 / 256.0, 24.0 / 256.0, 16.0 / 256.0, 4.0 / 256.0,
    6.0 / 256.0, 24.0 / 256.0, 36.0 / 256.0, 24.0 / 256.0, 6.0 / 256.0,
    4.0 / 256.0, 16.0 / 256.0, 24.0 / 256.0, 16.0 / 256.0, 4.0 / 256.0,
    1.0 / 256.0,  4.0 / 256.0,  6.0 / 256.0,  4.0 / 256.0, 1.0 / 256.0,
)
DN_FAST_TEX = ("delta_impulse",
               "ramp_8ev__noisy_iso125_s20260921",
               "gray_staircase__noisy_iso1600_s20260921")

# 5 wavelets cases: default (Y0U0V0 + flat force) / RGB mode / strength-
# dominant + shadows + bias / shaped force curve (Y0+U0V0 rows, course:
# strong high-freq damping) / AUTO (profile infer hand-check carrier).
DENOISEPROFILE_WAVE_CASES = [
    {"name": "dp_wave_default", "mode": 1, "radius": 1.0, "nbhood": 7.0,
     "strength": 1.0, "shadows": 1.0, "bias": 0.0, "scattering": 0.0,
     "central_pixel_weight": 0.1, "overshooting": 1.0,
     "wavelet_color_mode": 1, "y_override": None,
     "a": (1e-4, 1e-4, 1e-4), "b": (0.0, 0.0, 0.0)},
    {"name": "dp_wave_rgb", "mode": 1, "wavelet_color_mode": 0,
     "radius": 1.0, "nbhood": 7.0, "strength": 1.0, "shadows": 1.0,
     "bias": 0.0, "scattering": 0.0, "central_pixel_weight": 0.1,
     "overshooting": 1.0, "y_override": None,
     "a": (1e-4, 1e-4, 1e-4), "b": (0.0, 0.0, 0.0)},
    {"name": "dp_wave_strong", "mode": 1, "wavelet_color_mode": 1,
     "radius": 1.0, "nbhood": 7.0, "strength": 3.0, "shadows": 1.2,
     "bias": -2.0, "scattering": 0.0, "central_pixel_weight": 0.1,
     "overshooting": 1.0, "y_override": None,
     "a": (1e-4, 1e-4, 1e-4), "b": (0.0, 0.0, 0.0)},
    {"name": "dp_wave_force", "mode": 1, "wavelet_color_mode": 1,
     "radius": 1.0, "nbhood": 7.0, "strength": 1.5, "shadows": 1.0,
     "bias": 0.0, "scattering": 0.0, "central_pixel_weight": 0.1,
     "overshooting": 1.0,
     "y_override": {4: [1.0, 0.9, 0.7, 0.5, 0.3, 0.2, 0.1],
                    5: [0.9, 0.8, 0.6, 0.4, 0.2, 0.1, 0.0]},
     "a": (1e-4, 1e-4, 1e-4), "b": (0.0, 0.0, 0.0)},
    {"name": "dp_wave_auto", "mode": 4, "wavelet_color_mode": 1,
     "radius": 1.0, "nbhood": 7.0, "strength": 1.0, "shadows": 1.0,
     "bias": 0.0, "scattering": 0.0, "central_pixel_weight": 0.1,
     "overshooting": 1.0, "y_override": None,
     "a": (2.99037019802356e-05, 8.86355041404361e-06, 1.37779541937624e-05),
     "b": (4.43124422276964e-08, 2.60617465248865e-08, 3.62731233591954e-08)},
]

# 3 NLMeans-leg cases: defaults / scattering + central weight / AUTO.
DENOISEPROFILE_NLM_CASES = [
    {"name": "dp_nlm_default", "mode": 0, "wavelet_color_mode": 1,
     "radius": 1.0, "nbhood": 5.0, "strength": 1.0, "shadows": 1.0,
     "bias": 0.0, "scattering": 0.0, "central_pixel_weight": 0.1,
     "overshooting": 1.0, "y_override": None,
     "a": (1e-4, 1e-4, 1e-4), "b": (0.0, 0.0, 0.0)},
    {"name": "dp_nlm_scatter", "mode": 0, "wavelet_color_mode": 1,
     "radius": 2.0, "nbhood": 5.0, "strength": 2.0, "shadows": 1.0,
     "bias": -1.0, "scattering": 0.5, "central_pixel_weight": 0.3,
     "overshooting": 1.0, "y_override": None,
     "a": (1e-4, 1e-4, 1e-4), "b": (0.0, 0.0, 0.0)},
    {"name": "dp_nlm_auto", "mode": 3, "wavelet_color_mode": 1,
     "radius": 1.0, "nbhood": 7.0, "strength": 1.0, "shadows": 1.0,
     "bias": 0.0, "scattering": 0.0, "central_pixel_weight": 0.1,
     "overshooting": 1.0, "y_override": None,
     "a": (2.99037019802356e-05, 8.86355041404361e-06, 1.37779541937624e-05),
     "b": (4.43124422276964e-08, 2.60617465248865e-08, 3.62731233591954e-08)},
]


def dn_max_scale(w, h, iscale=1.0, in_scale=1.0):
    """process_wavelets :1436-1456 — the 20% support-domain rule.
    `in_scale` = fmin(roi.scale/iscale, 1); buf_in dims = the FULL plane
    (iscale-multiplied back), NOT the tile rect (L021: dscIn is a run
    stamp — band count is tile-stable)."""
    max_scale = 0
    supp0 = min(2 * (2 << (DN_BANDS - 1)) + 1, max(h * iscale, w * iscale) * 0.2)
    i0 = math.log2((supp0 - 1.0) * 0.5)
    while max_scale < DN_BANDS:
        supp = 2 * (2 << max_scale) + 1
        supp_in = supp * (1.0 / in_scale)
        i_in = math.log2((supp_in - 1) * 0.5) - 1.0
        if 1.0 - (i_in + 0.5) / i0 < 0.0:
            break
        max_scale += 1
    return max_scale


def dn_force_curve(y_row):
    """commit_params :2940-2952 → CurveDataSample with the dt quirks:
    effective anchors = the 7 (k/6, y[k]) points ONLY (the two extra
    set_point writes die — set_point never grows m_numAnchors, init added
    exactly BANDS anchors); samples at i/(BANDS−1) stored to force[k]
    which smaple_values relabels k/BANDS (dt draw.h quirk, force[k] =
    curve(i/6)); uint16 quantization `val·65535+0.5` then /65536."""
    xs = [k / 6.0 for k in range(DN_BANDS)]
    ys = list(y_row)
    m = [0.0] * DN_BANDS
    m[0] = (ys[1] - ys[0]) / (xs[1] - xs[0])
    for i in range(1, DN_BANDS - 1):
        m[i] = (ys[i + 1] - ys[i - 1]) / (xs[i + 1] - xs[i - 1])
    m[DN_BANDS - 1] = (ys[6] - ys[5]) / (xs[6] - xs[5])

    def val(xval):
        ival = DN_BANDS - 2
        for i in range(DN_BANDS - 2):
            if xval < xs[i + 1]:
                ival = i
                break
        h = xs[ival + 1] - xs[ival]
        dx = (xval - xs[ival]) / h
        dx2 = dx * dx
        dx3 = dx2 * dx
        h00 = 2.0 * dx3 - 3.0 * dx2 + 1.0
        h10 = dx3 - 2.0 * dx2 + dx
        h01 = -2.0 * dx3 + 3.0 * dx2
        h11 = dx3 - dx2
        v = h00 * ys[ival] + h10 * h * m[ival] + h01 * ys[ival + 1] \
            + h11 * h * m[ival + 1]
        return min(max(int(v * 65535.0 + 0.5), 0), 65535)

    return [val(i / 6.0) / 65536.0 for i in range(DN_BANDS)]


def dn_infer(a):
    """denoiseprofile.c:2618-2636 verbatim (AUTO parameter family)."""
    radius = min(int(1.0 + a * 15000.0 + a * a * 300000.0), 8)
    scattering = min(3000.0 * a, 1.0)
    shadows = min(max(0.1 - 0.1 * math.log(a), 0.7), 1.8)
    bias = -max(5.0 + 0.5 * math.log(a), 0.0)
    return radius, scattering, shadows, bias


def dn_setup_matrices(wb):
    """set_up_conversion_matrices (:1288-1343) + invert_matrix (:1250-
    1284) — wb-adaptive Y0U0V0 pair, float64."""
    sum_invwb = 1.0 / wb[0] + 1.0 / wb[1] + 1.0 / wb[2]
    sum_invwb *= math.sqrt(3.0)
    m = [[1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0],
         [0.5, 0.0, -0.5],
         [0.25, -0.5, 0.25]]
    m[0][0] = sum_invwb / wb[0]
    m[0][1] = sum_invwb / wb[1]
    m[0][2] = sum_invwb / wb[2]
    stddev_u0 = math.sqrt(0.25 * wb[0] * wb[0] + 0.25 * wb[2] * wb[2])
    stddev_v0 = math.sqrt(0.0625 * wb[0] * wb[0] + 0.25 * wb[1] * wb[1]
                          + 0.0625 * wb[2] * wb[2])
    for c in range(3):
        m[1][c] /= stddev_u0
        m[2][c] /= stddev_v0
    biga = m[1][1] * m[2][2] - m[1][2] * m[2][1]
    bigb = -m[1][0] * m[2][2] + m[1][2] * m[2][0]
    bigc = m[1][0] * m[2][1] - m[1][1] * m[2][0]
    bigd = -m[0][1] * m[2][2] + m[0][2] * m[2][1]
    bige = m[0][0] * m[2][2] - m[0][2] * m[2][0]
    bigf = -m[0][0] * m[2][1] + m[0][1] * m[2][0]
    bigg = m[0][1] * m[1][2] - m[0][2] * m[1][1]
    bigh = -m[0][0] * m[1][2] + m[0][2] * m[1][0]
    bigi = m[0][0] * m[1][1] - m[0][1] * m[1][0]
    det = m[0][0] * biga + m[0][1] * bigb + m[0][2] * bigc
    if det == 0.0:
        stddev_y0 = math.sqrt(1.0 / 9.0 * (wb[0] ** 2 + wb[1] ** 2 + wb[2] ** 2))
        m[0] = [1.0 / (3.0 * stddev_y0)] * 3
        det = 1.0  # dt reinverts the adjusted matrix; fallback line is near-singular
        # exact dt fallback: invert the (adjusted) standard matrix
        biga = m[1][1] * m[2][2] - m[1][2] * m[2][1]
        bigb = -m[1][0] * m[2][2] + m[1][2] * m[2][0]
        bigc = m[1][0] * m[2][1] - m[1][1] * m[2][0]
        bigd = -m[0][1] * m[2][2] + m[0][2] * m[2][1]
        bige = m[0][0] * m[2][2] - m[0][2] * m[2][0]
        bigf = -m[0][0] * m[2][1] + m[0][1] * m[2][0]
        bigg = m[0][1] * m[1][2] - m[0][2] * m[1][1]
        bigh = -m[0][0] * m[1][2] + m[0][2] * m[1][0]
        bigi = m[0][0] * m[1][1] - m[0][1] * m[1][0]
        det = m[0][0] * biga + m[0][1] * bigb + m[0][2] * bigc
    inv = [[1.0 / det * biga, 1.0 / det * bigd, 1.0 / det * bigg],
           [1.0 / det * bigb, 1.0 / det * bige, 1.0 / det * bigh],
           [1.0 / det * bigc, 1.0 / det * bigf, 1.0 / det * bigi]]
    return m, inv


def dn_precondition_v2_px(px, a, p, b, wb):
    """precondition_v2 (denoiseprofile.cl:56-79; c 991-1023): the general
    power VST. a = a[1]·compensate_p (scalar), p per channel, b scalar."""
    out = []
    for c in range(3):
        scaled = max(px[c] / wb[c] + b, 0.0)
        expon = 1.0 - p[c] / 2.0
        denom = (2.0 - p[c]) * math.sqrt(a)
        out.append(2.0 * (scaled ** expon) / denom if denom != 0.0 else 0.0)
    return out


def dn_precondition_y0u0v0_px(px, a, p, b, mat):
    """precondition_Y0U0V0 (denoiseprofile.cl:81-114): VST WITHOUT the
    wb division (the wb lives in the matrix normalization) then the
    Y0U0V0 row-vector application (transposed-application = m·t)."""
    t = []
    for c in range(3):
        scaled = max(px[c] + b, 0.0)
        expon = 1.0 - p[c] / 2.0
        denom = (2.0 - p[c]) * math.sqrt(a)
        t.append(2.0 * (scaled ** expon) / denom if denom != 0.0 else 0.0)
    return [sum(mat[k][c] * t[c] for c in range(3)) for k in range(3)]


def dn_precondition_legacy_px(px, aa, sigma2):
    """precondition (denoiseprofile.cl:31-54): generalized Anscombe."""
    return [2.0 * math.sqrt(max(px[c] / aa[c] + sigma2[c], 0.0))
            for c in range(3)]


def dn_backtransform_v2_px(px_in, a, p, b, bias, wb):
    """backtransform_v2 (denoiseprofile.cl:377-399) — the low-bias
    inverse with the user bias in delta (Taylor 2nd-order derivation,
    denoiseprofile.c:1025-1084)."""
    out = []
    for c in range(3):
        x = max(px_in[c], 0.0)
        delta = x * x + bias
        denominator = 4.0 / (math.sqrt(a) * (2.0 - p[c]))
        z1 = (x + math.sqrt(max(delta, 0.0))) / denominator
        out.append(max(z1 ** (1.0 / (1.0 - p[c] / 2.0)) - b, 0.0) * wb[c])
    return out


def dn_backtransform_y0u0v0_px(t, a, p, b, bias, wb, inv):
    """backtransform_Y0U0V0 (denoiseprofile.cl:401-433): toRGB first,
    then the inverse VST with bias·wb in delta."""
    px = [sum(inv[k][c] * t[c] for c in range(3)) for k in range(3)]
    out = []
    for c in range(3):
        x = max(px[c], 0.0)
        delta = x * x + bias * wb[c]
        scale = math.sqrt(a) * (2.0 - p[c]) / 4.0
        z1 = (x + math.sqrt(max(delta, 0.0))) * scale
        out.append(max(z1 ** (1.0 / (1.0 - p[c] / 2.0)) - b, 0.0))
    return out


def dn_backtransform_legacy_px(px_in, aa, sigma2):
    """backtransform (denoiseprofile.cl:354-374)."""
    s32 = math.sqrt(1.5)
    out = []
    for c in range(3):
        x = px_in[c]
        if x < 0.5:
            out.append(0.0)
        else:
            x2 = x * x
            out.append(aa[c] * (0.25 * x2 + 0.25 * s32 / x - 1.375 / x2
                                + 0.625 * s32 / (x * x2) - sigma2[c]))
    return out


def dn_decompose(buf, w, h, mult, inv_sigma2):
    """eaw_dn_decompose (eaw.c:271-363) — 5×5 B3 a-trous (stride=mult)
    + edge-aware weight `fast_mexp2f(max(0, |Δc|²·inv_sigma2·0.02 − 9))`;
    border = nearest clamp (CPU 3-segment structure ≡ clamp-to-edge
    sampler). Returns (coarse, detail, sum_y2[3]) — detail BEFORE any
    threshold (the Bayesshrink input)."""
    wgt_bias = 0.02
    off2 = 9.0
    coarse = [None] * (w * h)
    detail = [None] * (w * h)
    sum_y2 = [0.0, 0.0, 0.0]
    cl = lambda v, hi: min(max(v, 0), hi)
    for y in range(h):
        for x in range(w):
            px = buf[y * w + x]
            s = [0.0, 0.0, 0.0]
            wg = 0.0
            for jj in range(5):
                yy = cl(y + mult * (jj - 2), h - 1)
                for ii in range(5):
                    xx = cl(x + mult * (ii - 2), w - 1)
                    p2 = buf[yy * w + xx]
                    d = sum((px[c] - p2[c]) ** 2 for c in range(3))
                    fw = FILTER25[jj * 5 + ii]
                    wt = fw * nlmeans_fast_mexp2f(max(0.0, d * inv_sigma2 * wgt_bias - off2))
                    for c in range(3):
                        s[c] += wt * p2[c]
                    wg += wt
            cm = [s[c] / wg for c in range(3)]
            det = [px[c] - cm[c] for c in range(3)]
            for c in range(3):
                sum_y2[c] += det[c] * det[c]
            coarse[y * w + x] = cm
            detail[y * w + x] = det
    return coarse, detail, sum_y2


def dn_bayesshrink(sum_y2, npixels, scale, max_scale, force, mode_rgb):
    """variance_stabilizing_xform (denoiseprofile.c:1345-1421) —
    thrs[c] = 8·force²·4·sb2/std_x per the mode's channel mapping."""
    varf = math.sqrt(2.0 + 2.0 * 4.0 * 4.0 + 6.0 * 6.0) / 16.0
    sb2 = (varf ** scale) * 1.0
    sb2 *= sb2
    var_y = [sum_y2[c] / (npixels - 1.0) for c in range(3)]
    std_x = [math.sqrt(max(1e-6, var_y[c] - sb2)) for c in range(3)]
    offset_scale = DN_BANDS - max_scale
    bi = DN_BANDS - (scale + offset_scale + 1)
    adjt = [8.0, 8.0, 8.0]
    if mode_rgb:
        f_all = force[0][bi] ** 2 * 4.0
        adjt = [f * f_all for f in adjt]
        adjt[0] *= force[1][bi] ** 2 * 4.0
        adjt[1] *= force[2][bi] ** 2 * 4.0
        adjt[2] *= force[3][bi] ** 2 * 4.0
    else:
        adjt[0] *= force[4][bi] ** 2 * 4.0
        f_uv = force[5][bi] ** 2 * 4.0
        adjt[1] *= f_uv
        adjt[2] *= f_uv
    return [adjt[c] * sb2 / std_x[c] for c in range(3)]


def dn_wavelets_reference(w, h, rgb, case):
    """process_wavelets CPU form (denoiseprofile.c:1423-1658) at
    scale=1/iscale=1, neutral wb (D-05-07-T2-1). Accumulator form:
    out = Σ softthresh(detail_s) + coarsest, then the inverse VST."""
    mode = case["mode"]
    mode_rgb = case["wavelet_color_mode"] == 0
    strength = case["strength"]
    shadows = case["shadows"]
    bias_p = case["bias"]
    a1 = case["a"][1]
    b1 = case["b"][1]
    in_scale = 1.0
    wb = [1.0, 1.0, 1.0]
    compensate_strength = 1.0 if mode_rgb else 2.5
    p = [max(shadows + 0.1 * math.log(in_scale / wb[c]), 0.0) for c in range(3)]
    compensate_p = DN_P_FULCRUM / (DN_P_FULCRUM ** shadows)

    force = []
    for ch in range(6):
        row = case["y_override"].get(ch, [0.5] * DN_BANDS) \
            if case["y_override"] else [0.5] * DN_BANDS
        force.append(dn_force_curve(row))

    max_scale = dn_max_scale(w, h)
    npixels = w * h
    mult_max = 1 << (max_scale - 1) if max_scale > 0 else 1
    if w < 2 * mult_max or h < 2 * mult_max:
        return [(rgb[0][k], rgb[1][k], rgb[2][k]) for k in range(npixels)]

    mat = inv = None
    if not mode_rgb:
        mat, inv = dn_setup_matrices(wb)
        for k in range(3):
            for c in range(3):
                mat[k][c] /= strength * compensate_strength * in_scale
                inv[k][c] *= strength * compensate_strength * in_scale

    def precondition(px):
        if mode_rgb:
            return dn_precondition_v2_px(px, a1 * compensate_p, p, b1, wb)
        return dn_precondition_y0u0v0_px(px, a1 * compensate_p, p, b1, mat)

    # dt :1526-1527 — the SAME strength·compensate_strength·in_scale fold
    # that hits the matrices ALSO scales wb BEFORE it feeds the inverse
    # kernels (delta = x² + bias·wb and the RGB ×wb exit).
    wb_scaled = [wb[c] * strength * compensate_strength * in_scale for c in range(3)]

    def backtransform(px):
        bias = bias_p - 0.5 * math.log(in_scale)
        if mode_rgb:
            return dn_backtransform_v2_px(px, a1 * compensate_p, p, b1, bias, wb_scaled)
        return dn_backtransform_y0u0v0_px(px, a1 * compensate_p, p, b1, bias, wb_scaled, inv)

    buf1 = [precondition((rgb[0][k], rgb[1][k], rgb[2][k]))
            for k in range(npixels)]
    acc = [[0.0, 0.0, 0.0] for _ in range(npixels)]
    varf = math.sqrt(70.0) / 16.0
    for s in range(max_scale):
        sigma_band = (varf ** s) * 1.0
        coarse, detail, sum_y2 = dn_decompose(
            buf1, w, h, 1 << s, 1.0 / (sigma_band * sigma_band))
        thrs = dn_bayesshrink(sum_y2, npixels, s, max_scale, force, mode_rgb)
        for k in range(npixels):
            d = detail[k]
            for c in range(3):
                amt = max(0.0, abs(d[c]) - thrs[c])
                acc[k][c] += math.copysign(amt, d[c])
        buf1 = coarse
    out = []
    for k in range(npixels):
        v = [acc[k][c] + buf1[k][c] for c in range(3)]
        out.append(backtransform(v))
    return out


def dn_nlmeans_leg_reference(w, h, rgb, case):
    """NLMeans leg (process_nlmeans :1772-1824 + denoiseprofile.cl
    dist/horiz/vert/accu/finish_v2): VST sandwich + Goossens with the
    denoiseprofile vert variant (single-pixel distance boost +
    central_pixel_weight + `norm − 2` offset) and norm2 = (1,1,1)."""
    strength = case["strength"]
    shadows = case["shadows"]
    a1 = case["a"][1]
    b1 = case["b"][1]
    scale = 1.0
    wb = [1.0, 1.0, 1.0]
    p = [max(shadows + 0.1 * math.log(scale / wb[c]), 0.0) for c in range(3)]
    compensate_p = DN_P_FULCRUM / (DN_P_FULCRUM ** shadows)
    a_vst = a1 * compensate_p
    # dt nlmeans_precondition :1682-1688 — wb *= strength·scale BEFORE the
    # precondition/backtransform consume it (raw wb only feeds p above).
    wb = [wb[c] * strength * scale for c in range(3)]
    P = int(math.ceil(case["radius"] * scale))
    K = int(case["nbhood"])
    # nlmeans_scattering (:1634-1657) — full/preview split; the golden
    # path is FULL (no clamp), K stays nbhood.
    maxk = (K ** 3 + 7.0 * K * math.sqrt(K)) * case["scattering"] / 6.0 + K
    scattering = case["scattering"]
    central = case["central_pixel_weight"] * scale
    norm = 0.045 / ((2 * P + 1) ** 2)

    npixels = w * h
    buf = [dn_precondition_v2_px((rgb[0][k], rgb[1][k], rgb[2][k]),
                                 a_vst, p, b1, wb) for k in range(npixels)]
    cl = lambda v, hi: min(max(v, 0), hi)

    def scatter(index1, index2):
        a1i = abs(index1)
        a2i = abs(index2)
        sgn = (index1 > 0) - (index1 < 0)
        # dt `const int` cast = truncation toward zero (NOT round)
        return int(scale * ((a1i ** 3 + 7.0 * a1i * math.sqrt(a2i))
                            * sgn * scattering / 6.0 + index1))

    u2 = [[0.0, 0.0, 0.0, 0.0] for _ in range(npixels)]
    for kj in range(-K, 1):
        for ki in range(-K, K + 1):
            qx = scatter(ki, kj)
            qy = scatter(kj, ki)
            dist = [0.0] * npixels
            for y in range(h):
                for x in range(w):
                    if not (0 <= x + qx < w and 0 <= y + qy < h):
                        continue
                    p1 = buf[y * w + x]
                    p2 = buf[(y + qy) * w + (x + qx)]
                    dist[y * w + x] = sum((p1[c] - p2[c]) ** 2 for c in range(3))
            tmp = [0.0] * npixels
            for y in range(h):
                row = y * w
                for x in range(w):
                    tmp[row + x] = sum(dist[row + cl(x + pi, w - 1)]
                                       for pi in range(-P, P + 1))
            wgt = [0.0] * npixels
            for y in range(h):
                for x in range(w):
                    box = sum(tmp[cl(y + pj, h - 1) * w + x]
                              for pj in range(-P, P + 1))
                    single = dist[y * w + x]
                    box += single * (2 * P + 1) ** 2 * central
                    box /= (1.0 + central)
                    wgt[y * w + x] = nlmeans_fast_mexp2f(max(0.0, box * norm - 2.0))
            dd = 0.0 if (qx == 0 and qy == 0) else 1.0
            for y in range(h):
                for x in range(w):
                    wpq = 1 if (0 <= x + qx < w and 0 <= y + qy < h) else 0
                    wmq = 1 if (0 <= x - qx < w and 0 <= y - qy < h) else 0
                    u4 = wgt[y * w + x]
                    u4_mq = wgt[cl(y - qy, h - 1) * w + cl(x - qx, w - 1)] * dd
                    cell = u2[y * w + x]
                    if wpq:
                        up = buf[(y + qy) * w + (x + qx)]
                        cell[0] += u4 * up[0]
                        cell[1] += u4 * up[1]
                        cell[2] += u4 * up[2]
                    if wmq:
                        um = buf[(y - qy) * w + (x - qx)]
                        cell[0] += u4_mq * um[0]
                        cell[1] += u4_mq * um[1]
                        cell[2] += u4_mq * um[2]
                    cell[3] += wpq * u4 + wmq * u4_mq
    bias = case["bias"] - 0.5 * math.log(scale)
    out = []
    for k in range(npixels):
        u = u2[k]
        px = [u[c] / u[3] if u[3] > 0.0 else 0.0 for c in range(3)]
        out.append(dn_backtransform_v2_px(px, a_vst, p, b1, bias, wb))
    return out


def _dp_case_with_infer(case):
    """AUTO modes resolve radius/scattering/shadows/bias from a[1] at
    commit (commit_params :2924-2938) — bake the resolution in."""
    if case["mode"] in (3, 4):
        c = dict(case)
        radius, scattering, shadows, bias = dn_infer(c["a"][1] * c["overshooting"])
        c["radius"] = float(radius)
        c["scattering"] = scattering
        c["shadows"] = shadows
        c["bias"] = bias
        return c
    return case


def gen_denoiseprofile_cases(outdir: str) -> None:
    os.makedirs(outdir, exist_ok=True)
    for case in DENOISEPROFILE_WAVE_CASES + DENOISEPROFILE_NLM_CASES:
        y = case["y_override"]
        rows = {ch: (y.get(ch, [0.5] * DN_BANDS) if y else [0.5] * DN_BANDS)
                for ch in range(6)}
        xs = [b / 6.0 for b in range(6) for _ in range(7)]
        flat_y = [rows[ch][k] for ch in range(6) for k in range(7)]
        blob = denoiseprofile_params_blob(
            radius=case["radius"], nbhood=case["nbhood"],
            strength=case["strength"], shadows=case["shadows"],
            bias=case["bias"], scattering=case["scattering"],
            central_pixel_weight=case["central_pixel_weight"],
            overshooting=case["overshooting"], a=case["a"], b=case["b"],
            mode=case["mode"], x=xs, y=flat_y,
            wavelet_color_mode=case["wavelet_color_mode"])
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION, iop_order_version=5,
            operation="denoiseprofile", modversion=DENOISEPROFILE_MODVERSION,
            params=blob, iop_order=f"{DENOISEPROFILE_IOP_ORDER:.1f}")
        with open(os.path.join(outdir, case["name"] + ".xmp"), "w") as f:
            f.write(xmp)


def gen_denoiseprofile_refs(canonical_dir: str, out_dir: str) -> None:
    """Synthesize the denoiseprofile golden REFERENCES (L017 route;
    dt-side = XMP adoption + flat probe — the flat probe asserts the
    flat-preserving direction, NOT identity: force=0.5 default keeps
    thrs>0 so noise-free flat detail≈0 survives soft-threshold as ≈flat).
    5 wavelets + 3 NLMeans cases × 3 fixtures, float64 at scale 1."""
    os.makedirs(out_dir, exist_ok=True)
    for case in DENOISEPROFILE_WAVE_CASES + DENOISEPROFILE_NLM_CASES:
        resolved = _dp_case_with_infer(case)
        ref = dn_wavelets_reference if case["mode"] in (1, 4) \
            else dn_nlmeans_leg_reference
        for fixture in DN_FAST_TEX:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)
            out_rgb = ref(w, h, rgb, resolved)

            def px(x, y, out_rgb=out_rgb, w=w):
                idx = y * w + x
                return out_rgb[idx]

            write_exr(os.path.join(out_dir, f"{case['name']}__{fixture}.exr"),
                      w, h, px)
        print(f"  denoiseprofile ref {case['name']} done")


# ──────────────────────────────────────────────────────────────────────
# bilateral / surface blur (Plan 05-08, IOP-DENOISE-03) — dt `bilateral`
# v1, 20 bytes: radius/reserved/red/green/blue (5f, bilateral.cc:52-58),
# v50 slot 10.0.
#
# float64 reference (L017 route ①——同算法参考，与 nlmeans Goossens 参考
# 同性质）：稠密 5D 网格（splat pentalinear 32 角 → blur 仅 spatial x/y
#（bilateral.cl blur_line edge 形）→ slice 32 角 val/w 归一）——与 GPU
# kernel 逐式对偶；直连档 case 用精确窗口公式参考（bilateral.cc:219-247
# float64 形）。网格 dims 公式 = LightamerModule.gridDims（dt 3D grid
# dim-clamp/re-derive 语义的 5 维推广，D-05-08-T2-1）。
# ──────────────────────────────────────────────────────────────────────

BILATERAL_PARAMS_FORMAT = "<5f"
BILATERAL_MODVERSION = 1
BILATERAL_IOP_ORDER = 10.0

BILATERAL_CASES = [
    {"name": "bilat_direct_small", "radius": 1.2, "sigma": 0.1},
    {"name": "bilat_boundary", "radius": 2.0, "sigma": 0.1},
    {"name": "bilat_grid_large", "radius": 6.0, "sigma": 0.1},
]

BILATERAL_REF_FIXTURES = [
    "delta_impulse",
    "ramp_8ev__noisy_iso125_s20260921",
    "gray_staircase__noisy_iso1600_s20260921",
]


def bilateral_params_blob(radius=15.0, reserved=15.0, red=0.005, green=0.005, blue=0.005) -> str:
    packed = struct.pack(BILATERAL_PARAMS_FORMAT, radius, reserved, red, green, blue)
    assert len(packed) == 20, len(packed)
    return binascii.hexlify(packed).decode("ascii")


def _bilateral_grid_dims(w, h, ss, sr, sg, sb):
    def spatial_cells(ext, s):
        return min(max(int(math.ceil(ext / s)) + 1, 4), 3000)

    def range_cells(s):
        return max(int(math.ceil(1.0 / s)) + 1, 4)

    cr, cg, cb = range_cells(sr), range_cells(sg), range_cells(sb)
    ss_eff = max(w / spatial_cells(w, ss), h / spatial_cells(h, ss))
    cx, cy = spatial_cells(w, ss_eff), spatial_cells(h, ss_eff)
    return [cx, cy, cr, cg, cb], [ss_eff, 1.0 / (cr - 1), 1.0 / (cg - 1), 1.0 / (cb - 1)]


def bilateral_grid_reference(w, h, rgb, ss, sr, sg, sb):
    """稠密 5D 网格 float64 参考（GPU kernel 逐式对偶——splat → blur x/y →
    slice val/w 归一；range 维不做 blur——稠密格 adaptation，D-05-08-T2-2）。"""
    dims, sig = _bilateral_grid_dims(w, h, ss, sr, sg, sb)
    total = 1
    for d in dims:
        total *= d
    payload = [0.0] * (total * 4)
    oy = dims[0]
    orr = dims[0] * dims[1]
    og = orr * dims[2]
    ob = og * dims[3]

    def coords(x, y, px):
        g = [x / sig[0], y / sig[0],
             min(max(px[0] / sig[1], 0), dims[2] - 1),
             min(max(px[1] / sig[2], 0), dims[3] - 1),
             min(max(px[2] / sig[3], 0), dims[4] - 1)]
        xi = [min(max(int(g[0]), 0), dims[0] - 2), min(max(int(g[1]), 0), dims[1] - 2)]
        ff = [g[0] - xi[0], g[1] - xi[1]]
        for d in range(2, 5):
            xi.append(min(int(g[d]), dims[d] - 2))
            ff.append(g[d] - xi[d])
        return xi, ff

    def corners(xi, ff, px, splat_weight=True):
        out = [0.0] * 4
        for a in range(2):
            for b in range(2):
                for c in range(2):
                    wr = (ff[2] if a else 1 - ff[2]) * (ff[3] if b else 1 - ff[3]) \
                        * (ff[4] if c else 1 - ff[4])
                    for q in range(4):
                        xj = [xi[0] + (1 if q in (1, 3) else 0),
                              xi[1] + (1 if q >= 2 else 0), xi[2], xi[3], xi[4]]
                        base = xj[0] + oy * xj[1] + orr * (xj[2] + a) + og * (xj[3] + b) + ob * (xj[4] + c)
                        wxy = (1 - ff[0]) * (1 - ff[1]) if q == 0 else \
                            (ff[0] * (1 - ff[1]) if q == 1 else
                             ((1 - ff[0]) * ff[1] if q == 2 else ff[0] * ff[1]))
                        ww = wr * wxy
                        if splat_weight:
                            payload[4 * base + 0] += ww * px[0]
                            payload[4 * base + 1] += ww * px[1]
                            payload[4 * base + 2] += ww * px[2]
                            payload[4 * base + 3] += ww
                        else:
                            for k in range(4):
                                out[k] += ww * payload[4 * base + k]
        return out

    for y in range(h):
        for x in range(w):
            px = (rgb[0][y * w + x], rgb[1][y * w + x], rgb[2][y * w + x])
            xi, ff = coords(x, y, px)
            corners(xi, ff, px, splat_weight=True)

    for axis in range(2):
        n = dims[axis]
        lines = 1
        tstride = [1] * 5
        axis_stride = 1
        for d in range(5):
            tstride[d] = 1
            for e in range(d):
                tstride[d] *= dims[e]
            if d == axis:
                axis_stride = tstride[d]
                continue
            lines *= dims[d]
        src = payload[:]
        w0, w1, w2 = 6.0 / 16, 4.0 / 16, 1.0 / 16

        def cell_at(base, i):
            return 4 * (base + i * axis_stride)

        for line in range(lines):
            base = 0
            rem = line
            for d in range(5):
                if d == axis:
                    continue
                base += (rem % dims[d]) * tstride[d]
                rem //= dims[d]
            t1 = src[cell_at(base, 0):cell_at(base, 0) + 4]
            t2 = src[cell_at(base, 1):cell_at(base, 1) + 4]
            for c in range(4):
                payload[cell_at(base, 0) + c] = src[cell_at(base, 0) + c] * w0 \
                    + w1 * src[cell_at(base, 1) + c] + w2 * src[cell_at(base, 2) + c]
            for c in range(4):
                payload[cell_at(base, 1) + c] = src[cell_at(base, 1) + c] * w0 \
                    + w1 * (src[cell_at(base, 2) + c] + t1[c]) + w2 * src[cell_at(base, 3) + c]
            for i in range(2, n - 2):
                t3 = src[cell_at(base, i):cell_at(base, i) + 4]
                for c in range(4):
                    payload[cell_at(base, i) + c] = src[cell_at(base, i) + c] * w0 \
                        + w1 * (src[cell_at(base, i + 1) + c] + t2[c]) \
                        + w2 * (src[cell_at(base, i + 2) + c] + t1[c])
                t1, t2 = t2, t3
            t3 = src[cell_at(base, n - 2):cell_at(base, n - 2) + 4]
            for c in range(4):
                payload[cell_at(base, n - 2) + c] = src[cell_at(base, n - 2) + c] * w0 \
                    + w1 * (src[cell_at(base, n - 1) + c] + t2[c]) + w2 * t1[c]
            for c in range(4):
                payload[cell_at(base, n - 1) + c] = src[cell_at(base, n - 1) + c] * w0 \
                    + w1 * t3[c] + w2 * t2[c]

    out = []
    for y in range(h):
        for x in range(w):
            px = (rgb[0][y * w + x], rgb[1][y * w + x], rgb[2][y * w + x])
            xi, ff = coords(x, y, px)
            val = corners(xi, ff, px, splat_weight=False)
            out.append(tuple(val[c] / val[3] if val[3] > 0 else px[c] for c in range(3)))
    return out


def bilateral_direct_reference(w, h, rgb, ss, sr, sg, sb):
    """精确 bilateral 窗口公式 float64（bilateral.cc:219-247 直译；直连档
    参考——rad ≤ 6 档 GPU 输出与同式对偶 <1e-5）。"""
    rad = int(3 * ss + 1)
    out = []
    isig2 = [1.0 / (2 * sr * sr), 1.0 / (2 * sg * sg), 1.0 / (2 * sb * sb)]
    wd = 2 * rad + 1
    m = [0.0] * (wd * wd)
    wsum = 0.0
    for l in range(-rad, rad + 1):
        for k in range(-rad, rad + 1):
            v = math.exp(-(l * l + k * k) / (2 * ss * ss))
            m[(l + rad) * wd + (k + rad)] = v
            wsum += v
    for i in range(len(m)):
        m[i] /= wsum
    def pxv(x, y, c):
        return rgb[c][y * w + x]

    for y in range(h):
        for x in range(w):
            if y < rad or y >= h - rad or x < rad or x >= w - rad:
                out.append((pxv(x, y, 0), pxv(x, y, 1), pxv(x, y, 2)))
                continue
            res = [0.0, 0.0, 0.0]
            sumw = 0.0
            for l in range(-rad, rad + 1):
                for k in range(-rad, rad + 1):
                    diff = 0.0
                    for c in range(3):
                        d = pxv(x, y, c) - pxv(x + k, y + l, c)
                        diff += d * d * isig2[c]
                    wgt = m[(l + rad) * wd + (k + rad)] * math.exp(-diff)
                    for c in range(3):
                        res[c] += pxv(x + k, y + l, c) * wgt
                    sumw += wgt
            out.append((res[0] / sumw, res[1] / sumw, res[2] / sumw))
    return out


def gen_bilateral_cases(outdir: str) -> None:
    for case in BILATERAL_CASES:
        params = bilateral_params_blob(
            radius=case["radius"], red=case["sigma"],
            green=case["sigma"], blue=case["sigma"])
        xmp = XMP_TEMPLATE.format(
            xmp_version=XMP_VERSION, iop_order_version=5,
            operation="bilateral", modversion=BILATERAL_MODVERSION,
            params=params, iop_order=f"{BILATERAL_IOP_ORDER:.1f}")
        with open(os.path.join(outdir, case["name"] + ".xmp"), "w") as f:
            f.write(xmp)


def gen_bilateral_refs(canonical_dir: str, out_dir: str) -> None:
    """Synthesize the bilateral golden REFERENCES (L017 route ①——同算法
    float64；dt-side = XMP adoption + 平场 probe). 直连 case = 精确窗口
    公式；grid case = 网格算法同构参考。3 case × 3 fixture。"""
    os.makedirs(out_dir, exist_ok=True)
    for case in BILATERAL_CASES:
        ss, sr = case["radius"], case["sigma"]
        prad = int(3 * ss + 1)
        for fixture in BILATERAL_REF_FIXTURES:
            src = os.path.join(canonical_dir, fixture + ".exr")
            w, h, rgb = read_exr_rgb(src)
            roi_w = min(w, h) - 2 * prad
            leg_grid = prad > 6 and roi_w >= prad
            if leg_grid:
                out_rgb = bilateral_grid_reference(w, h, rgb, ss, sr, sr, sr)
            else:
                out_rgb = bilateral_direct_reference(w, h, rgb, ss, sr, sr, sr)

            def px(x, y, out_rgb=out_rgb, w=w):
                idx = y * w + x
                return out_rgb[idx]

            write_exr(os.path.join(out_dir, f"{case['name']}__{fixture}.exr"), w, h, px)


if __name__ == "__main__":
    main()


#!/usr/bin/env python3
"""Generate the LUMEN-A T3 culling-analysis golden constants (Plan LUMEN-A T3).

Writes Tests/Fixtures/culling_golden.json — the expected sharpness scores and
the 16x16 signature hex for deterministic synthetic images, computed by a
NumPy REFERENCE implementation of the Lumen culling.py pipeline (the same
transliteration the Swift SharpnessAnalyzer/Signature16 carry):

    area-resize <=1600 -> Gaussian sigma0.5 (5-tap, reflect-101)
    -> per direction {0,45,90,135}: 32-px tile means of the squared 3x3
    first/second derivative correlation responses -> structure tiles =
    first >= P75(first) AND first > 2e-5 -> level = log2(P90(second/first))
    -> score = clip((min(levels)+4)/5.5*100, 0, 100)

Branches: no structure tile -> 0.0; min(shape) < 64 -> null.

The synthetic inputs share one deterministic content recipe (`content_image`)
built on a PURE integer LCG so the Swift test regenerates byte-identical
planes:

    noise    = ((lcg(seed) >> 33) % 4096) / 4096          # per pixel, row-major
    lcg: state = state * 6364136223846793005 + 1442695040888963407 (mod 2^64)
    img = 0.45*noise + 0.25*gauss(noise,2) + 0.1*gauss(noise,4)
          + 0.15*bars32 + 0.1*(x/W)          # gauss = content rule, radius round(3*sigma)
    img = clip(img / img.max(), 0, 1)
    img = clip(gauss(img, 0.65), 0, 1)

Calibration anchors: the 1600x1200 base (resize no-op at SHARPNESS_EDGE=1600,
Lumen's calibration setup) blurred with sigma 1.2 / 2.0 under the
cv2.GaussianBlur(img,(0,0),sigma) auto-ksize rule (radius = round(4*sigma) —
probed 2026-10-22, opencv-python-headless). The recipe lands both anchors in
the plan's ±5 band (58.9 / 25.0) with the FORMULA constants untouched
(D-LU-10); the content-dependence of Lumen's 55/30 claim rides DECISIONS.

Regenerate:  uv run --with numpy python3 Scripts/gen-culling-golden.py
"""

import json
from pathlib import Path

import numpy as np

SHARPNESS_EDGE = 1600
TILE = 32
STRUCTURE_Q = 0.75
STRUCTURE_FLOOR = 2e-5
RATIO_Q = 0.90
SCALE_OFFSET = 4.0
SCALE_DIVISOR = 5.5

SQRT2 = np.sqrt(np.float64(2))
FIRST = {
    0: np.array([[-0.5, 0, 0.5]], np.float64),
    90: np.array([[-0.5], [0], [0.5]], np.float64),
    45: np.array([[0, 0, 0.5], [0, 0, 0], [-0.5, 0, 0]], np.float64) / SQRT2,
    135: np.array([[-0.5, 0, 0], [0, 0, 0], [0, 0, 0.5]], np.float64) / SQRT2,
}
SECOND = {
    0: np.array([[1, -2, 1]], np.float64),
    90: np.array([[1], [-2], [1]], np.float64),
    45: np.array([[0, 0, 1], [0, -2, 0], [1, 0, 0]], np.float64) / 2,
    135: np.array([[1, 0, 0], [0, -2, 0], [0, 0, 1]], np.float64) / 2,
}


def lcg_noise(width: int, height: int, seed: int) -> np.ndarray:
    """Per-pixel LCG noise in [0,1) — the Swift test mirrors this integer math."""
    state = np.uint64(seed)
    out = np.empty(width * height, np.float64)
    mask = np.uint64((1 << 64) - 1)
    mul = np.uint64(6364136223846793005)
    inc = np.uint64(1442695040888963407)
    for index in range(width * height):
        state = np.uint64((state * mul + inc) & mask)
        out[index] = (int(state) >> 33) % 4096 / 4096.0
    return out.reshape(height, width)


def area_resize(image: np.ndarray, new_w: int, new_h: int) -> np.ndarray:
    """Exact area average (INTER_AREA downscale semantics) — separable;
    fragment weights normalized to sum 1 (the destination pixel is the
    WEIGHTED AVERAGE of its source interval)."""
    src_h, src_w = image.shape
    ratio_w = src_w / float(new_w)
    ratio_h = src_h / float(new_h)
    # Horizontal.
    horizontal = np.zeros((src_h, new_w), np.float64)
    for target in range(new_w):
        start, end = target * ratio_w, (target + 1) * ratio_w
        cursor = start
        while cursor < end:
            index = int(np.floor(cursor))
            boundary = min(float(index + 1), end)
            weight = (boundary - cursor) / ratio_w
            if weight > 0:
                horizontal[:, target] += image[:, index] * weight
            cursor = boundary
    # Vertical.
    output = np.zeros((new_h, new_w), np.float64)
    for target in range(new_h):
        start, end = target * ratio_h, (target + 1) * ratio_h
        cursor = start
        while cursor < end:
            index = int(np.floor(cursor))
            boundary = min(float(index + 1), end)
            weight = (boundary - cursor) / ratio_h
            if weight > 0:
                output[target, :] += horizontal[index, :] * weight
            cursor = boundary
    return output


def gaussian_blur(
    image: np.ndarray, sigma: float, radius: int | None = None
) -> np.ndarray:
    """Separable Gaussian, reflect-101 padding. TWO callers with DIFFERENT
    radius rules — the `radius` argument makes the rule explicit:
      • content synthesis (the fixture recipe below): radius = round(3*sigma)
      • the cv2.GaussianBlur(img, (0,0), sigma) anchor semantics:
        radius = round(4*sigma) — the measured modern-OpenCV auto-ksize
        rule (cvRound(sigma*8+1)|1; probed 2026-10-22 against
        opencv-python-headless: sigma 1.2 -> ksize 11, 2.0 -> 17, 0.5 -> 5).
    """
    if radius is None:
        radius = int(round(3 * sigma))
    offsets = np.arange(-radius, radius + 1, dtype=np.float64)
    kernel = np.exp(-(offsets ** 2) / (2 * sigma * sigma))
    kernel /= kernel.sum()
    padded = np.pad(image, radius, mode="reflect")  # == reflect-101
    height, width = image.shape
    horizontal = np.zeros_like(image)
    for tap in range(2 * radius + 1):
        d = tap - radius
        horizontal += kernel[tap] * padded[radius:radius + height,
                                           radius + d:radius + d + width]
    padded = np.pad(horizontal, radius, mode="reflect")
    output = np.zeros_like(image)
    for tap in range(2 * radius + 1):
        d = tap - radius
        output += kernel[tap] * padded[radius + d:radius + d + height,
                                       radius:radius + width]
    return output


def blur_sigma_half(image: np.ndarray) -> np.ndarray:
    """The pipeline's internal sigma0.5 blur — cv2 auto-ksize at sigma 0.5
    is ksize 5 (radius 2), the same under both radius rules."""
    radius = 2
    offsets = np.arange(-radius, radius + 1, dtype=np.float64)
    kernel = np.exp(-(offsets ** 2) / (2 * 0.5 * 0.5))
    kernel /= kernel.sum()
    padded = np.pad(image, radius, mode="reflect")
    height, width = image.shape
    horizontal = np.zeros_like(image)
    for tap in range(radius, radius * 2 + 1):
        horizontal += kernel[tap - radius] * padded[radius:radius + height,
                                                    tap:tap + width]
    padded = np.pad(horizontal, radius, mode="reflect")
    output = np.zeros_like(image)
    for tap in range(radius, radius * 2 + 1):
        output += kernel[tap - radius] * padded[tap:tap + height,
                                                radius:radius + width]
    return output


def correlate(image: np.ndarray, kernel: np.ndarray) -> np.ndarray:
    """cv2.filter2D semantics: correlation, BORDER_REFLECT_101."""
    height, width = image.shape
    ky, kx = kernel.shape
    cy, cx = ky // 2, kx // 2
    radius_y, radius_x = cy, cx
    padded = np.pad(image, ((radius_y, radius_y), (radius_x, radius_x)),
                    mode="reflect")  # numpy 'reflect' == reflect-101
    out = np.zeros_like(image)
    for dy in range(ky):
        for dx in range(kx):
            weight = kernel[dy, dx]
            if weight != 0:
                out += weight * padded[dy:dy + height, dx:dx + width]
    return out


def tiles(values: np.ndarray, size: int = TILE) -> np.ndarray:
    height, width = values.shape
    height, width = height // size * size, width // size * size
    trimmed = values[:height, :width]
    return trimmed.reshape(height // size, size, width // size, size).mean(axis=(1, 3))


def percentile(values: np.ndarray, quantile: float) -> float:
    """numpy.percentile's default 'linear' method."""
    return float(np.percentile(values, quantile * 100.0))


def sharpness(gray: np.ndarray) -> float | None:
    gray = gray.astype(np.float64)
    scale = SHARPNESS_EDGE / max(gray.shape)
    if scale < 1:
        new_w = max(1, int(round(gray.shape[1] * scale)))
        new_h = max(1, int(round(gray.shape[0] * scale)))
        gray = area_resize(gray, new_w, new_h)
    if min(gray.shape) < 64:
        return None
    gray = blur_sigma_half(gray)
    levels = []
    for direction in (0, 45, 90, 135):
        first = tiles(correlate(gray, FIRST[direction]) ** 2)
        second = tiles(correlate(gray, SECOND[direction]) ** 2)
        strong = (first >= percentile(first, STRUCTURE_Q)) & (first > STRUCTURE_FLOOR)
        if not strong.any():
            return 0.0
        ratios = second[strong] / first[strong]
        levels.append(np.log2(percentile(ratios, RATIO_Q)))
    return float(np.clip((min(levels) + SCALE_OFFSET) / SCALE_DIVISOR * 100, 0, 100))


def signature(gray: np.ndarray) -> str:
    """16x16 area-resize, scale to 0-255, truncate (astype uint8), bytes hex."""
    small = area_resize(gray.astype(np.float64), 16, 16)
    small = np.clip(small * 255.0, 0.0, 255.0).astype(np.uint8)
    return small.tobytes().hex()


def content_image(width: int, height: int, seed: int) -> np.ndarray:
    """The anchor/parity content: a noise ladder (0.45 n + 0.25 blur2(n) +
    0.1 blur4(n)) + 32-px checker bars (0.15) + a 0.1 x-gradient, normalized
    to max 1, clipped, then a sigma0.65 smoothing (radius = round(3*sigma)
    — the CONTENT radius rule), clipped again. Deterministic under the
    shared integer LCG; the Swift test mirrors this recipe step-for-step.
    The recipe was tuned (2026-10-22) so the Lumen calibration anchors land
    in the +/-5 band on the cv2 pipeline — the FORMULA constants are
    untouched (D-LU-10); only the fixture content carries the tuning, and
    the band evidence rides DECISIONS.
    """
    xs = np.arange(width, dtype=np.float64)[None, :]
    ys = np.arange(height, dtype=np.float64)[:, None]
    noise = lcg_noise(width, height, seed)
    bars = ((((xs.astype(np.int64) // 32) % 2 == 0) &
             ((ys.astype(np.int64) // 32) % 2 == 0)).astype(np.float64) * 0.15)
    ladder = (0.45 * noise
              + 0.25 * gaussian_blur(noise, 2.0)
              + 0.1 * gaussian_blur(noise, 4.0))
    img = ladder + bars + xs / float(width) * 0.1
    img = np.clip(img / img.max(), 0.0, 1.0)
    img = np.clip(gaussian_blur(img, 0.65), 0.0, 1.0)
    return img


def main() -> None:
    base = content_image(1600, 1200, seed=0x2A5F1B)
    resized_input = content_image(2000, 1500, seed=0x51DE2C)
    flat = np.zeros((512, 640), np.float64)
    tiny = lcg_noise(48, 40, 1)

    # Anchor blur = the cv2.GaussianBlur(img, (0,0), sigma) semantics
    # (the auto-ksize rule: radius = round(4*sigma)).
    anchor_1_2 = sharpness(gaussian_blur(base, 1.2, radius=int(round(4 * 1.2))))
    anchor_2_0 = sharpness(gaussian_blur(base, 2.0, radius=int(round(4 * 2.0))))

    golden = {
        "generator": "Scripts/gen-culling-golden.py (LUMEN-A T3, review B-1 formula)",
        "base": {
            "w": 1600, "h": 1200, "seed": "0x2A5F1B",
            "sharpness": sharpness(base),
            "signature_hex": signature(base),
        },
        "resized": {
            "w": 2000, "h": 1500, "seed": "0x51DE2C",
            "sharpness": sharpness(resized_input),
        },
        "anchors": {
            "sigma_1_2_sharpness": anchor_1_2,
            "sigma_2_0_sharpness": anchor_2_0,
        },
        "flat_sharpness": sharpness(flat),
        "tiny": {"w": 48, "h": 40, "sharpness": sharpness(tiny)},
    }
    out = Path(__file__).resolve().parents[1] / "Tests/Fixtures/culling_golden.json"
    out.write_text(json.dumps(golden, indent=2) + "\n")
    print(json.dumps(golden, indent=2))


if __name__ == "__main__":
    main()

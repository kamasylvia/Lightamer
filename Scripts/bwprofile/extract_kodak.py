#!/usr/bin/env python3
"""extract_kodak.py — vector-path extraction of the Kodak BW datasheets (M9-2 T1).

Kodak F-4017 (TRI-X) and F-4016 (T-Max 100) carry their charts as PDF vector
paths: coordinates carry the plotter's full precision and the only error
source is the axis calibration (tick-label centers -> affine map).

Chart inventory (verified 2026-10-27 against the downloaded PDFs):
  F-4017 p7  spectral sensitivity (2 curves: D+0.3 / D+1.0 over gross fog)
  F-4017 p8  characteristic curves, 400TX 35mm LARGE TANK (6/8/10/12 min)
  F-4016 p8  spectral sensitivity (2 curves) + D-76 small-tank char family
"""
from __future__ import annotations

import json
import sys
from dataclasses import dataclass

import pdfplumber


@dataclass
class Axis:
    """A 1-D affine calibration: value = a * px + b (least squares over ticks)."""
    a: float
    b: float
    residual: float

    @staticmethod
    def from_ticks(pairs: list[tuple[float, float]]) -> "Axis":
        # pairs: (px, value); fit value = a*px + b
        n = len(pairs)
        sx = sum(p[0] for p in pairs)
        sy = sum(p[1] for p in pairs)
        sxx = sum(p[0] * p[0] for p in pairs)
        sxy = sum(p[0] * p[1] for p in pairs)
        a = (n * sxy - sx * sy) / (n * sxx - sx * sx)
        b = (sy - a * sx) / n
        resid = max(abs(a * p[0] + b - p[1]) for p in pairs)
        return Axis(a=a, b=b, residual=resid)


def word_center(w) -> tuple[float, float]:
    return ((w["x0"] + w["x1"]) / 2.0, (w["top"] + w["bottom"]) / 2.0)


def tick_axis(words, labels: list[tuple[str, float]], vertical: bool,
              y_window: tuple[float, float] | None = None,
              x_window: tuple[float, float] | None = None):
    """Match label text -> numeric value, at the label's pixel center."""
    pairs = []
    for text, value in labels:
        target = text.replace("-", "")
        for w in words:
            if w["text"] != target:
                continue
            cx, cy = word_center(w)
            if y_window and not (y_window[0] <= cy <= y_window[1]):
                continue
            if x_window and not (x_window[0] <= cx <= x_window[1]):
                continue
            pairs.append((cx if not vertical else cy, value))
            break
    if len(pairs) < 2:
        raise ValueError(f"ticks not found: {labels} (got {pairs})")
    return Axis.from_ticks(pairs)


def row_axis(words, row_y: tuple[float, float], values: list[float],
             min_x: float = 0.0, max_x: float = 1e9):
    """Calibrate a horizontal tick-label ROW (Kodak log-exposure rows whose
    minus signs are lost in extraction): collect the numeric words inside
    the row band, sort by x, and pair them positionally with `values`
    (ascending). The "0.0" word anchors the sequence — no text-value
    matching, so the duplicate "1.0" (−1 and +1) disambiguates by seat.
    `min_x` keeps the perpendicular axis's edge labels out of the band."""
    row = []
    for w in words:
        t = w["text"].replace("-", "").rstrip(".0") or w["text"]
        cy = (w["top"] + w["bottom"]) / 2.0
        cx = (w["x0"] + w["x1"]) / 2.0
        if not (row_y[0] <= cy <= row_y[1]) or cx < min_x or cx > max_x:
            continue
        if not w["text"].replace(".", "").replace("-", "").isdigit():
            continue
        row.append((cx, w["text"]))
    row.sort()
    if len(row) != len(values):
        raise ValueError(f"row has {len(row)} labels, expected {len(values)}: "
                         f"{[t for _, t in row]}")
    return Axis.from_ticks([(x, v) for (x, _), v in zip(row, values)])


def col_axis(words, col_x: tuple[float, float], y_range: tuple[float, float],
             values: list[float]):
    """Calibrate a vertical tick-label COLUMN: numeric words inside the
    column band and y-range, sorted by y (top→bottom), paired with
    `values` (descending — Kodak density axes run 4 at top)."""
    col = []
    for w in words:
        cx = (w["x0"] + w["x1"]) / 2.0
        if not (col_x[0] <= cx <= col_x[1]):
            continue
        cy = (w["top"] + w["bottom"]) / 2.0
        if not (y_range[0] <= cy <= y_range[1]):
            continue
        if not w["text"].replace(".", "").replace("-", "").isdigit():
            continue
        col.append((cy, w["text"]))
    col.sort()
    if len(col) != len(values):
        raise ValueError(f"col has {len(col)} labels, expected {len(values)}: "
                         f"{[t for _, t in col]}")
    return Axis.from_ticks([(y, v) for (y, _), v in zip(col, values)])


def curve_points(page, index: int) -> list[tuple[float, float]]:
    c = page.curves[index]
    return [(p[0], p[1]) for p in (c.get("pts") or [])]


def curve_end_y(page, index: int) -> float:
    pts = curve_points(page, index)
    last = max(pts, key=lambda p: p[0])
    return last[1]


def resample(points: list[tuple[float, float]], x_axis: Axis, y_axis: Axis,
             x_targets: list[float], max_dx: float = 2.5):
    """Linear interpolation of the polyline onto x_targets (px-domain)."""
    mapped = [(x_axis.a * x + x_axis.b, y_axis.a * y + y_axis.b)
              for (x, y) in points]
    mapped.sort(key=lambda p: p[0])
    out = []
    j = 0
    for xt in x_targets:
        while j < len(mapped) - 2 and mapped[j + 1][0] < xt:
            j += 1
        x0, y0 = mapped[j]
        x1, y1 = mapped[j + 1]
        if abs(x1 - x0) < 1e-9:
            out.append((xt, y0))
            continue
        t = (xt - x0) / (x1 - x0)
        if t < -max_dx or t > 1 + max_dx:
            out.append((xt, None))
            continue
        t = min(max(t, 0.0), 1.0)
        out.append((xt, y0 + t * (y1 - y0)))
    return out


def extract_spectral(pdf_path: str, page_no: int,
                     x_labels, y_labels, curve_idx: int,
                     x_window, y_window, wavelengths):
    with pdfplumber.open(pdf_path) as pdf:
        page = pdf.pages[page_no - 1]
        words = page.extract_words()
        xa = tick_axis(words, x_labels, vertical=False, y_window=y_window)
        ya = tick_axis(words, y_labels, vertical=True, x_window=x_window)
        pts = curve_points(page, curve_idx)
        rows = resample(pts, xa, ya, wavelengths)
        return {
            "x_axis": {"a": xa.a, "b": xa.b, "residual_px": xa.residual},
            "y_axis": {"a": ya.a, "b": ya.b, "residual_px": ya.residual},
            "curve_index": curve_idx,
            "points": rows,
        }


def extract_char(pdf_path: str, page_no: int, curve_indices: list[int],
                 x_row_y: tuple[float, float], x_values_axis: list[float],
                 y_col_x: tuple[float, float], y_range: tuple[float, float],
                 y_values_axis: list[float],
                 x_values: list[float], label_y_for_curve: dict[int, float],
                 x_row_window: tuple[float, float] = (70, 300)):
    """Extract one characteristic-curve family with ROW/COLUMN positional
    axis calibration (the minus-sign-proof path); attach dev-time labels by
    matching each curve's right-end y to the annotation y position."""
    with pdfplumber.open(pdf_path) as pdf:
        page = pdf.pages[page_no - 1]
        words = page.extract_words()
        xa = row_axis(words, x_row_y, x_values_axis,
                      min_x=x_row_window[0], max_x=x_row_window[1])
        ya = col_axis(words, y_col_x, y_range, y_values_axis)
        curves = {}
        for idx in curve_indices:
            pts = curve_points(page, idx)
            rows = resample(pts, xa, ya, x_values)
            curves[idx] = {
                "end_y": curve_end_y(page, idx),
                "label_y": label_y_for_curve.get(idx),
                "points": rows,
            }
        return {
            "x_axis": {"a": xa.a, "b": xa.b, "residual_px": xa.residual},
            "y_axis": {"a": ya.a, "b": ya.b, "residual_px": ya.residual},
            "curves": curves,
        }


# ── F-4017 TRI-X ─────────────────────────────────────────────────────────────

TRIX_SPECTRAL_X = [("250", 250), ("300", 300), ("350", 350), ("400", 400),
                   ("450", 450), ("500", 500), ("550", 550), ("600", 600),
                   ("650", 650), ("700", 700), ("750", 750)]
TRIX_SPECTRAL_Y = [("0.0", 0.0), ("1.0", 1.0), ("2.0", 2.0),
                   ("3.0", 3.0), ("4.0", 4.0)]

TRIX_CHAR_X = [("4.0", -4.0), ("3.0", -3.0), ("2.0", -2.0), ("1.0", -1.0),
               ("0.0", 0.0), ("1.0", 1.0)]   # first five carry a lost minus
TRIX_CHAR_Y = [("4.0", 4.0), ("3.0", 3.0), ("2.0", 2.0),
               ("1.0", 1.0), ("0.0", 0.0)]

WL_5NM = list(range(380, 781, 5))          # 81 points, the profile axis
LOGE_GRID = [round(-3.9 + 0.03 * i, 3) for i in range(256)]  # probe grid


def main():
    src = sys.argv[1]
    target = sys.argv[2] if len(sys.argv) > 2 else "trix"
    if target == "trix":
        out = main_trix(src)
    elif target == "tmax":
        out = main_tmax(src)
    else:
        raise SystemExit(f"unknown target {target}")
    json.dump(out, sys.stdout, indent=1)


def main_trix(src: str) -> dict:
    out = {}
    # spectral: p7 curve2 = D+0.3 (upper); curve3 = D+1.0 (lower)
    out["trix_spectral_d03"] = extract_spectral(
        src, 7, TRIX_SPECTRAL_X, TRIX_SPECTRAL_Y, 2,
        x_window=(40, 100), y_window=(430, 460), wavelengths=WL_5NM)
    out["trix_spectral_d10"] = extract_spectral(
        src, 7, TRIX_SPECTRAL_X, TRIX_SPECTRAL_Y, 3,
        x_window=(40, 100), y_window=(430, 460), wavelengths=WL_5NM)
    # characteristic: p8 TOP-LEFT chart (400TX 35mm, D-76, large tank).
    # Axis calibration is positional (row/col bands — minus-sign-proof):
    #   x row y∈(250,262), x∈[70,300]: 6 labels sorted by x = logE −4..+1
    #   y col x∈(60,78), y∈(40,250): 5 labels sorted by y = density 4..0
    # Curves 1..4 with end_y px 121.2 / 168.3 / 151.7 / 136.3; dev-time
    # legend 12@122 / 10@130 / 8@139 / 6@147 -> by density order the
    # mapping is c1=12min, c4=10min, c3=8min, c2=6min (DECISIONS note).
    out["trix_char_35mm_largetank"] = extract_char(
        src, 8, [1, 2, 3, 4],
        x_row_y=(250, 262), x_values_axis=[-4, -3, -2, -1, 0, 1],
        y_col_x=(60, 78), y_range=(40, 250), y_values_axis=[4, 3, 2, 1, 0],
        x_values=LOGE_GRID,
        label_y_for_curve={1: 122, 4: 130, 3: 139, 2: 147})
    out["trix_granularity_rms_48um_d100"] = 17
    return out


def main_tmax(src: str) -> dict:
    """F-4016 T-Max 100 — p8 carries both charts: bottom-left spectral
    sensitivity (c6 = 0.3 / c7 = 1.0 greater than D-min; y = LOG
    SENSITIVITY 2..−2 with the bottom labels' minus signs lost; x =
    wavelength row 250..750 @y≈660) and right characteristic family
    (c18/c19/c20/c21; x row y≈486 = logE −4..+1; y col = density 3..0;
    dev legend 12/10/7/6 min @x≈510). Image-structure table granularity
    = 8 (RMS, 48 µm aperture, net diffuse density 1.0, 12X)."""
    out = {}
    with pdfplumber.open(src) as pdf:
        page = pdf.pages[7]
        words = page.extract_words()
        # y axis: positional col (duplicate "1.0"/"2.0" labels, minus lost)
        col = []
        for w in words:
            cx = (w["x0"] + w["x1"]) / 2.0
            cy = (w["top"] + w["bottom"]) / 2.0
            if 60 <= cx <= 80 and 480 <= cy <= 655 \
                    and w["text"].replace(".", "").isdigit():
                col.append((cy, w["text"]))
        col.sort()
        if len(col) != 5:
            raise ValueError(f"tmax spectral y col: {col}")
        ya = Axis.from_ticks([(y, v) for (y, _), v
                              in zip(col, [2.0, 1.0, 0.0, -1.0, -2.0])])
        xa = row_axis(words, (650, 668),
                      [250, 300, 350, 400, 450, 500, 550, 600, 650, 700, 750],
                      min_x=70, max_x=290)
        for name, idx in (("tmax_spectral_d03", 6), ("tmax_spectral_d10", 7)):
            rows = resample(curve_points(page, idx), xa, ya, WL_5NM)
            out[name] = {
                "x_axis": {"a": xa.a, "b": xa.b, "residual_px": xa.residual},
                "y_axis": {"a": ya.a, "b": ya.b, "residual_px": ya.residual},
                "curve_index": idx,
                "points": rows,
            }
    out["tmax_char_d76_smalltank"] = extract_char(
        src, 8, [18, 19, 20, 21],
        x_row_y=(478, 492), x_values_axis=[-4, -3, -2, -1, 0, 1],
        y_col_x=(332, 352), y_range=(500, 712), y_values_axis=[3, 2, 1, 0],
        x_values=LOGE_GRID,
        label_y_for_curve={18: 653, 19: 662, 20: 670, 21: 678},
        x_row_window=(330, 560))
    out["tmax_granularity_rms_48um_d100"] = 8
    return out


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""trace_driver.py — trace the BW raster charts (M9-2 T1) onto JSON anchors.

Each chart gets a bespoke calibration (gridline px anchors -> values,
derived from the gridline survey + the vision-read tick labels) and a
trace spec (polarity, ink threshold, curve selection). Output:
/tmp/<name>_trace.json with (value_x, value_y) samples.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

BASE = Path(__file__).resolve().parent.parent.parent / \
    ".work/gsd/phases/m9-2-bwspectral/evidence/t1/native_images"


def affine_anchors(pairs):
    """(px, value) anchors -> (a, b, residual) with value = a*px + b."""
    n = len(pairs)
    sx = sum(p for p, _ in pairs); sy = sum(v for _, v in pairs)
    sxx = sum(p * p for p, _ in pairs)
    sxy = sum(p * v for p, v in pairs)
    a = (n * sxy - sx * sy) / (n * sxx - sx * sx)
    b = (sy - a * sx) / n
    resid = max(abs(a * p + b - v) for p, v in pairs)
    return a, b, resid


def load(name):
    img = Image.open(BASE / f"{name}.png").convert("RGB")
    return np.asarray(img).astype(float)


def ink_map(arr, polarity):
    gray = arr.mean(axis=2)
    return (255.0 - gray) if polarity == "dark-on-light" else gray


def trace_single(arr, polarity, xa, xb, ya, yb, x_targets,
                 thresh=120, band=None, exclude_bands=()):
    """Per-column subpixel centroid of ink pixels (single curve)."""
    ink = ink_map(arr, polarity)
    h, w = ink.shape
    out = []
    for xt in x_targets:
        px = (xt - xb) / xa
        c0, c1 = int(px) - 1, int(px) + 2
        vals = []
        for c in range(max(0, c0), min(w, c1)):
            ys = np.where(ink[:, c] > thresh)[0]
            if band:
                ys = np.array([y for y in ys if band[0] <= y <= band[1]])
            ys = np.array([y for y in ys
                           if not any(lo <= y <= hi for lo, hi in exclude_bands)])
            if len(ys) == 0:
                continue
            wts = ink[ys, c]
            cy = float(np.average(ys, weights=wts))
            vals.append(ya * cy + yb)
        if not vals:
            out.append([xt, None])
        else:
            out.append([xt, round(float(np.mean(vals)), 4)])
    return out


# ── Acros II p3 i7: CHARACTERISTIC CURVE (normal dev), dark-on-light ────────

def trace_acros_char():
    arr = load("acros2_p3_i7_874x609")
    xa, xb, xr = affine_anchors([(106, -4), (256, -3), (408, -2),
                                 (560.5, -1), (710.5, 0), (862, 1)])
    ya, yb, yr = affine_anchors([(60, 3), (211, 2), (362, 1), (514, 0)])
    assert xr < 1.0 and yr < 1.0, (xr, yr)
    xs = [round(-3.9 + 0.03 * i, 3) for i in range(256)]
    pts = trace_single(arr, "dark-on-light", xa, xb, ya, yb, xs,
                       thresh=170, band=(55, 590))
    return {"chart": "acros_char_std_dev", "x_axis": {"a": xa, "b": xb, "resid": xr},
            "y_axis": {"a": ya, "b": yb, "resid": yr}, "points": pts}


# ── Acros II p3 i8: SPECTRAL SENSITIVITY, dark-on-light (light grids) ───────

def trace_acros_spectral():
    arr = load("acros2_p3_i8_808x769")
    ink = ink_map(arr, "dark-on-light")
    # survey with lower threshold to find the light gridlines
    m = ink > 60
    rows = m.sum(axis=1); cols = m.sum(axis=0)
    def merged(counts, frac, gap=6):
        hits = [i for i, c in enumerate(counts) if c > frac * len(counts)]
        out = []
        for i in hits:
            if out and i - out[-1][-1] <= gap: out[-1].append(i)
            else: out.append([i])
        return [round(float(np.mean(g)), 1) for g in out]
    hl = merged(rows, 0.45); vl = merged(cols, 0.45)
    return {"chart": "acros_spectral_survey", "hlines": hl, "vlines": vl}


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    results = {}
    if which in ("all", "acros_char"):
        results["acros_char"] = trace_acros_char()
    if which in ("all", "acros_spectral"):
        results["acros_spectral"] = trace_acros_spectral()
    json.dump(results, sys.stdout, indent=1)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""trace_raster.py — raster chart tracing for the BW datasheets (M9-2 T1).

The Fuji/Ilford datasheets embed their charts as raster images (native
resolutions ~400-2100 px, decoded to native_images/). This tool:

  1. finds the axis gridlines (long straight runs of axis-colored pixels),
  2. maps them to values via a per-chart grid spec (values assigned to the
     detected line positions in order),
  3. traces the data curve by color/brightness segmentation with a
     per-column subpixel weighted centroid,
  4. resamples onto the requested output grid.

Two chart video polarities exist: dark-on-light (Acros p3 i7/i8) and
light-on-dark (Acros i9/i10 — black-background Fuji style).

Usage: uv run python3 trace_raster.py <config-name>   (see CONFIGS)
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

BASE = Path(__file__).resolve().parent.parent / \
    ".work/gsd/phases/m9-2-bwspectral/evidence/t1/native_images"


def find_lines(dark_or_bright: np.ndarray, axis: int, frac: float, min_gap: int = 4):
    """Long runs along an axis: rows (axis=0) or cols (axis=1) whose
    run-count exceeds frac of the span; merged when closer than min_gap."""
    counts = dark_or_bright.sum(axis=axis)
    n = dark_or_bright.shape[1 - axis]
    hits = [i for i, c in enumerate(counts) if c > frac * n]
    merged = []
    for i in hits:
        if merged and i - merged[-1][-1] <= min_gap:
            merged[-1].append(i)
        else:
            merged.append([i])
    return [float(np.mean(g)) for g in merged]


def affine(grid_px: list[float], grid_vals: list[float]):
    """Least-squares px -> value over the matched grid anchors."""
    n = len(grid_px)
    sx = sum(grid_px); sy = sum(grid_vals)
    sxx = sum(p * p for p in grid_px); sxy = sum(p * v for p, v in zip(grid_px, grid_vals))
    a = (n * sxy - sx * sy) / (n * sxx - sx * sx)
    b = (sy - a * sx) / n
    resid = max(abs(a * p + b - v) for p, v in zip(grid_px, grid_vals))
    return a, b, resid


def trace(image: np.ndarray, mask: np.ndarray, x_a, x_b, y_a, y_b,
          x_targets: list[float]):
    """Subpixel per-column centroid of the masked curve pixels."""
    h, w = mask.shape
    out = []
    cols = np.arange(w)
    xs = x_a * cols + x_b
    for xt in x_targets:
        # columns near the target x
        sel = np.where(np.abs(xs - xt) < 1.5)[0]
        if len(sel) == 0:
            out.append([xt, None]); continue
        best = []
        for c in sel:
            ys_px = np.where(mask[:, c])[0]
            if len(ys_px) == 0:
                continue
            wts = mask[ys_px, c].astype(float)
            cy = float(np.average(ys_px, weights=wts))
            best.append((y_a * cy + y_b, float(wts.sum())))
        if not best:
            out.append([xt, None]); continue
        val = sum(v * w for v, w in best) / sum(w for _, w in best)
        out.append([xt, round(float(val), 4)])
    return out


def load(name: str, polarity: str):
    img = Image.open(BASE / f"{name}.png").convert("RGB")
    arr = np.asarray(img).astype(float)
    gray = arr.mean(axis=2)
    if polarity == "dark-on-light":
        ink = 255.0 - gray
    else:
        ink = gray
    return arr, ink


def curve_mask_color(arr, ink, rgb_target, tol, polarity):
    """Mask by color proximity (the curve's ink color), any polarity."""
    dist = np.sqrt(((arr - np.array(rgb_target)) ** 2).sum(axis=2))
    m = dist < tol
    return m


CONFIGS = {}


def register(name):
    def deco(fn):
        CONFIGS[name] = fn
        return fn
    return deco


def run_config(name):
    cfg = CONFIGS[name]
    arr, ink = load(cfg["image"], cfg["polarity"])
    # gridlines
    axis_ink = ink > cfg["line_thresh"]
    hl = find_lines(axis_ink, axis=1, frac=cfg.get("line_frac", 0.5))
    vl = find_lines(axis_ink, axis=0, frac=cfg.get("line_frac", 0.5))
    return cfg, arr, ink, hl, vl


if __name__ == "__main__":
    print("import this module from a per-chart driver; see trace_driver.py")

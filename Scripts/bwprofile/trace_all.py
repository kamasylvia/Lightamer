#!/usr/bin/env python3
"""trace_all.py — final raster trace of all BW charts (M9-2 T1).

Calibrations below come from the pixel gridline/tick surveys plus the
vision-read tick labels (each chart's anchors are documented inline).
Curves are traced per-column by ink segmentation with gridline masking;
multi-curve charts (Acros char, MG grades) are split by run clustering
with continuity stitching. Output: /tmp/raster_traces.json
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

BASE = Path(__file__).resolve().parent.parent.parent / \
    ".work/gsd/phases/m9-2-bwspectral/evidence/t1/render_charts"


def affine_anchors(pairs):
    n = len(pairs)
    sx = sum(p for p, _ in pairs); sy = sum(v for _, v in pairs)
    sxx = sum(p * p for p, _ in pairs); sxy = sum(p * v for p, v in pairs)
    a = (n * sxy - sx * sy) / (n * sxx - sx * sx)
    b = (sy - a * sx) / n
    resid = max(abs(a * p + b - v) for p, v in pairs)
    return a, b, resid


def load_ink(name):
    arr = np.asarray(Image.open(BASE / f"{name}.png").convert("L")).astype(float)
    return 255.0 - arr


def column_runs(ink, col, thresh, mask_rows, mask_cols):
    """Ink runs in one column with gridline rows masked out; returns
    [(y0, y1, weight_sum)] per contiguous run."""
    ys = np.where(ink[:, col] > thresh)[0]
    ys = np.array([y for y in ys
                   if not any(abs(y - mr) <= 2 for mr in mask_rows)])
    if len(ys) == 0:
        return []
    runs = []
    start = prev = ys[0]
    for y in ys[1:]:
        if y - prev > 3:
            runs.append((start, prev))
            start = y
        prev = y
    runs.append((start, prev))
    out = []
    for y0, y1 in runs:
        if abs(y1 - y0) > 12:   # text blobs / axis caption junk
            continue
        wsum = float(ink[y0:y1 + 1, col].sum())
        cy = float(np.average(range(y0, y1 + 1),
                              weights=ink[y0:y1 + 1, col]))
        out.append((cy, wsum))
    return out


def trace_curves(name, thresh, hgrid, vgrid, x_a, x_b, y_a, y_b,
                 x_targets, band, ncurves=1, min_weight=300):
    """Column-run segmentation + slope-aware walking stitcher. The walker
    steps column by column (skipping empty ones), predicts the next y from
    the recent slope, and accepts the nearest run within a slope-scaled
    tolerance — this crosses the near-vertical rise segments that defeat
    plain nearest-continuity."""
    ink = load_ink(name)
    h, w = ink.shape
    cols_runs = {}
    lo, hi = int(min(vgrid)) + 1, int(max(vgrid)) - 1   # plot interior only
    for c in range(max(0, lo), min(w, hi + 1)):
        if any(abs(c - vc) <= 2 for vc in vgrid):
            continue
        rs = column_runs(ink, c, thresh, hgrid, vgrid)
        rs = [(cy, ws) for cy, ws in rs
              if band[0] <= cy <= band[1] and ws >= min_weight]
        if rs:
            cols_runs[c] = rs
    if not cols_runs:
        return []

    def separation(runs):
        ys = sorted(r[0] for r in runs)
        gaps = [b - a for a, b in zip(ys, ys[1:])]
        return min(gaps) if gaps else 0.0
    candidates = [(c, separation(rs)) for c, rs in cols_runs.items()
                  if len(rs) >= ncurves]
    if candidates:
        best_c = max(candidates, key=lambda t: (t[1] > 12, t[1]))[0]
    else:
        best_c = max(cols_runs, key=lambda c: len(cols_runs[c]))
    seeds = sorted(cols_runs[best_c], key=lambda r: r[0])[:ncurves]
    tracks = [[(best_c, cy)] for cy, _ in seeds]

    def walk_parallel(direction):
        # per-column single-claim assignment: a run already taken by a
        # track at this column is invisible to the others.
        claims = {c: set() for c in cols_runs}
        active = list(range(len(tracks)))
        while active:
            progressed = []
            for ti in active:
                tr = tracks[ti]
                last_c, cy = tr[-1]
                if len(tr) >= 3:
                    d = (tr[-1][1] - tr[-3][1]) / (tr[-1][0] - tr[-3][0] + 1e-9)
                else:
                    d = 0.0
                for step in range(1, 60):
                    c = last_c + direction * step
                    if c not in cols_runs:
                        continue
                    pred = cy + d * direction * step
                    tol = 22 + 1.6 * abs(d) * step
                    free = [(abs(r[0] - pred), r[0]) for r in cols_runs[c]
                            if r not in claims[c]]
                    free.sort()
                    if free and free[0][0] < tol:
                        claimed_run = next(r for r in cols_runs[c]
                                           if r[0] == free[0][1])
                        claims[c].add(claimed_run)
                        tr.append((c, free[0][1]))
                        progressed.append(ti)
                        break
            active = progressed

    walk_parallel(+1)
    walk_parallel(-1)

    curves = []
    for tr in tracks:
        pts = [(x_a * c + x_b, y_a * cy + y_b) for c, cy in tr]
        pts.sort()
        curves.append(pts)
    # drop near-duplicate tracks (>80% shared columns with same y)
    uniq = []
    for c in curves:
        dup = False
        for u in uniq:
            shared = sum(1 for p in c if any(abs(p[0]-q[0]) < 0.6 and abs(p[1]-q[1]) < 0.05 for q in u))
            if shared > 0.8 * min(len(c), len(u)) and \
                   all(abs(p[1]-q[1]) < 0.3 for p in c for q in u if abs(p[0]-q[0]) < 0.6):
                dup = True; break
        if not dup and len(c) >= 5:
            uniq.append(c)
    return uniq


def resample_curve(pts, xs):
    out = []
    for xt in xs:
        near = [(px, py) for px, py in pts if abs(px - xt) < 1.2]
        if not near:
            out.append([xt, None]); continue
        out.append([xt, round(float(np.mean([py for _, py in near])), 4)])
    return out


def main():
    results = {}

    # ── Acros II characteristic (render acros2_p3_i7) ────────────────────
    # grids: x −4..+1 at vlines 106..862 (151.2 px/dec); y D 3..0 at hlines
    # 60/211/362/514 (150.86 px/1.0D). TWO curves on this chart.
    xa, xb, _ = affine_anchors([(106, -4), (256, -3), (408, -2), (560.5, -1), (710.5, 0), (862, 1)])
    ya, yb, _ = affine_anchors([(60, 3), (211, 2), (362, 1), (514, 0)])
    xs = [round(-3.9 + 0.03 * i, 3) for i in range(256)]
    curves = trace_curves("acros2_p3_i7", 170,
                          hgrid=[21.1, 60, 135.5, 211, 286.5, 362, 438, 514, 583],
                          vgrid=[106, 256, 408, 560.5, 710.5, 862],
                          x_a=xa, x_b=xb, y_a=ya, y_b=yb,
                          x_targets=xs, band=(45, 510), ncurves=2)
    results["acros_char"] = {
        "axes": {"x": [xa, xb], "y": [ya, yb]},
        "curves": [resample_curve(c, xs) for c in curves],
    }

    # ── Acros II spectral (render acros2_p3_i10; i8 cross-check) ────────
    # i10: y +2..−4 at hlines 106.5..562 (75.92 px/1.0); x 250..750 at
    # vlines 114.5..871.5 (75.7 px/50 nm)
    xa, xb, _ = affine_anchors([(114.5, 250), (189.5, 300), (265.5, 350), (340.5, 400),
                                (416.5, 450), (493, 500), (568.5, 550), (644, 600),
                                (719.5, 650), (795.5, 700), (871.5, 750)])
    ya, yb, _ = affine_anchors([(106.5, 2), (182.5, 1), (258.5, 0), (335, -1),
                                (411, -2), (486.5, -3), (562, -4)])
    wl = list(range(380, 781, 5))
    curves = trace_curves("acros2_p3_i10", 170,
                          hgrid=[106.5, 182.5, 258.5, 335, 411, 486.5, 562],
                          vgrid=[114.5, 189.5, 265.5, 340.5, 416.5, 493, 568.5, 644, 719.5, 795.5, 871.5],
                          x_a=xa, x_b=xb, y_a=ya, y_b=yb,
                          x_targets=wl, band=(90, 580), ncurves=1)
    results["acros_spectral"] = {
        "axes": {"x": [xa, xb], "y": [ya, yb]},
        "curves": [resample_curve(c, wl) for c in curves],
    }

    # ── HP5 spectral (render hp5_p1_i2) ──────────────────────────────────
    # frame x 400..700 (32.5..847.5), ticks 450..700; y log decades 100 at
    # top frame 29.5 to 0.1 at bottom 380.5 (ticks at 151.5=10, 265.5=1).
    xa, xb, _ = affine_anchors([(151.5, 450), (266.5, 500), (382.5, 550),
                                (497.5, 600), (612.5, 650), (728.5, 700)])
    ya, yb, _ = affine_anchors([(29.5, 2), (151.5, 1), (265.5, 0), (380.5, -1)])  # log10
    wl = list(range(380, 781, 5))
    curves = trace_curves("hp5_p1_i2", 150,
                          hgrid=[29.5, 151.5, 265.5, 380.5],
                          vgrid=[151.5, 266.5, 382.5, 497.5, 612.5, 728.5, 32.5, 847.5],
                          x_a=xa, x_b=xb, y_a=ya, y_b=yb,
                          x_targets=wl, band=(24, 384), ncurves=1, min_weight=150)
    results["hp5_spectral"] = {
        "axes": {"x": [xa, xb], "y": [ya, yb]},
        "curves": [resample_curve(c, wl) for c in curves],
    }

    # ── HP5 characteristic (render hp5_p2_i0) ────────────────────────────
    # x −4..+1 half-steps at vlines 214.5..893.5; y D 3..0 at hlines
    # 51.5..534.5. Family of dev curves — trace the dominant 4.
    xa, xb, _ = affine_anchors([(214.5, -4), (282.5, -3.5), (348.5, -3), (416.5, -2.5),
                                (485.5, -2), (553.5, -1.5), (621.5, -1), (689.5, -0.5),
                                (757.5, 0), (825.5, 0.5), (893.5, 1)])
    ya, yb, _ = affine_anchors([(51.5, 3), (131.5, 2.5), (211.5, 2), (291.5, 1.5),
                                (371.5, 1), (451.5, 0.5), (534.5, 0)])
    xs = [round(-3.9 + 0.03 * i, 3) for i in range(256)]
    curves = trace_curves("hp5_p2_i0", 150,
                          hgrid=[51.5, 131.5, 211.5, 291.5, 371.5, 451.5, 534.5],
                          vgrid=[214.5, 282.5, 348.5, 416.5, 485.5, 553.5, 621.5, 689.5, 757.5, 825.5, 893.5],
                          x_a=xa, x_b=xb, y_a=ya, y_b=yb,
                          x_targets=xs, band=(40, 540), ncurves=4)
    results["hp5_char"] = {
        "axes": {"x": [xa, xb], "y": [ya, yb]},
        "curves": [resample_curve(c, xs) for c in curves],
    }

    # ── Multigrade IV spectral (render multigrade4_p1_i1) ────────────────
    # frame x 350..700 (23.5..928.5), bottom ticks 400..650 @129.3 px/50nm;
    # y log +2 (top frame 17.5) .. −2 (bottom frame 406). THREE emulsion
    # curves, grayscale — split by run clustering.
    xa, xb, _ = affine_anchors([(152.5, 400), (281.5, 450), (411.5, 500),
                                (540.5, 550), (669.5, 600), (799, 650)])
    ya, yb, _ = affine_anchors([(17.5, 2), (406, -2)])
    wl = list(range(380, 781, 5))
    curves = trace_curves("multigrade4_p1_i1", 150,
                          hgrid=[17.5, 406],
                          vgrid=[152.5, 281.5, 411.5, 540.5, 669.5, 799, 23.5, 928.5],
                          x_a=xa, x_b=xb, y_a=ya, y_b=yb,
                          x_targets=wl, band=(12, 410), ncurves=3, min_weight=120)
    results["mg_spectral"] = {
        "axes": {"x": [xa, xb], "y": [ya, yb]},
        "curves": [resample_curve(c, wl) for c in curves],
    }

    # ── Multigrade IV characteristic (renders p3_i0 + p3_i1) ─────────────
    # Both: y D 2.5..0 at 6 hlines (94 px/0.5); x −4..+0.5 at 10 vlines.
    # Grade families (legend unreadable at this resolution — separated as
    # distinct curves, labeled by trace order; DECISIONS note).
    for key, fname, hgrid, vgrid in (
        ("mg_char_a", "multigrade4_p3_i0",
         [21.5, 115.5, 209.5, 303.5, 397.5, 492],
         [23.5, 117.5, 211.5, 305.5, 399.5, 493.5, 587.5, 682, 776.5, 870.5]),
        ("mg_char_b", "multigrade4_p3_i1",
         [21.5, 116.5, 211, 305.5, 400.5, 495.5],
         [22.5, 117.5, 212, 306.5, 401.5, 496.5, 591.5, 686.5, 781.5, 875.5]),
    ):
        xa, xb, _ = affine_anchors(list(zip(vgrid, [-4, -3.5, -3, -2.5, -2, -1.5, -1, -0.5, 0, 0.5])))
        ya, yb, _ = affine_anchors(list(zip(hgrid, [2.5, 2, 1.5, 1, 0.5, 0])))
        xs = [round(-3.9 + 0.03 * i, 3) for i in range(256)]
        curves = trace_curves(fname, 150,
                              hgrid=hgrid, vgrid=vgrid,
                              x_a=xa, x_b=xb, y_a=ya, y_b=yb,
                              x_targets=xs, band=(12, 500), ncurves=4, min_weight=150)
        results[key] = {
            "axes": {"x": [xa, xb], "y": [ya, yb]},
            "curves": [resample_curve(c, xs) for c in curves],
        }

    json.dump(results, sys.stdout, indent=1)


if __name__ == "__main__":
    main()

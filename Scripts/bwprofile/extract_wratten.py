#!/usr/bin/env python3
"""extract_wratten.py — Kodak WRATTEN 2 per-filter spectral-density PDFs (M9-2 T1).

Each one-page PDF carries a vector curve drawn as MULTIPLE path segments:
where the filter's density exceeds the chart ceiling (D>3, T<0.1%) the path
leaves the plot box or breaks, and Kodak draws flat D=0 tails where the
filter is fully transparent. We merge every in-window segment onto
(λ, D), convert to transmission T = 10**(-D), and resample onto the B-3
grid (400..700 nm @ 10 nm) for the dual-source cross-check. B-3 remains
the source of record (X-M92-1); W2 is the official cross-check.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pdfplumber

from extract_kodak import Axis, tick_axis


def axis_value(axis: Axis, px: float) -> float:
    return axis.a * px + axis.b


def extract(pdf_path: str):
    with pdfplumber.open(pdf_path) as pdf:
        page = pdf.pages[0]
        words = page.extract_words()
        xa = tick_axis(
            words,
            [(str(v), float(v)) for v in (300, 400, 500, 600, 700, 800, 900)],
            vertical=False)
        ya = tick_axis(
            words,
            [("0.0", 0.0), ("1.0", 1.0), ("2.0", 2.0), ("3.0", 3.0)],
            vertical=True)
        # Merge every drawable segment (curves AND long polylines stored as
        # lines) into (nm, density) samples, then sort. Short 5-pt dips are
        # chart markers — keep them (they are part of the trace where they
        # fall inside the window).
        samples: list[tuple[float, float]] = []
        for c in page.curves:
            for x, y in (c.get("pts") or []):
                nm, d = axis_value(xa, x), axis_value(ya, y)
                if 350.0 <= nm <= 760.0 and -0.3 <= d <= 3.6:
                    samples.append((nm, d))
        samples.sort()
        # Resample onto the B-3 grid by local linear interpolation of the
        # nearest samples within 6 nm (beyond a segment edge = None: the
        # curve is off-chart there, cross-check has no second opinion).
        rows = []
        for wl in range(400, 701, 10):
            near = [(nm, d) for nm, d in samples if abs(nm - wl) <= 6.0]
            if not near:
                rows.append([float(wl), None])
                continue
            num = sum(d for _, d in near)
            rows.append([float(wl), round(num / len(near), 4)])
        return {
            "x_axis": {"a": xa.a, "b": xa.b, "residual_px": xa.residual},
            "y_axis": {"a": ya.a, "b": ya.b, "residual_px": ya.residual},
            "samples": len(samples),
            "density_points": rows,
        }


def main():
    srcdir = Path(sys.argv[1])
    files = {
        "w8": "Basic-Color-Filters-w2-8.pdf",
        "w12": "Basic-Color-Filters-W2-12.pdf",
        "w15": "Basic-Color-Filters-W2-15.pdf",
        "w21": "Special-Dye-Color-Filters-W2-21.pdf",
        "w25": "Basic-Color-Filters-W2-25.pdf",
        "w47": "Basic-Color-Filters-W2-47.pdf",
        "w58": "Basic-Color-Filters-W2-58.pdf",
    }
    out = {}
    for name, fname in files.items():
        p = srcdir / fname
        if not p.exists():
            continue
        out[name] = extract(str(p))
    json.dump(out, sys.stdout, indent=1)


if __name__ == "__main__":
    main()

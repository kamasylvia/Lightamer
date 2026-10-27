#!/usr/bin/env python3
"""build_wratten.py — assemble camera_filters.json (M9-2 T1).

DUAL-SOURCE policy (plan T1 item 4: 交叉取一致值；分歧值 DECISIONS 登记 +
取官方源): the official Kodak WRATTEN 2 vector curves are the ASSET BASE
(current-production filters — same generation as the published filter-factor
tables the T3 gate cross-checks against); the B-3 table transcription
(b3_transcription.md, dash-audited; No.25 verbatim from the Repacholi 1992
text transcription of the same B-3) is the INDEPENDENT CROSS-CHECK and the
sole source where no W2 PDF exists (No.11 — W2-11 retired, 404).

The two sources disagree systematically in the cutoff bands (B-3 vintage
formulation vs W2 current, direction varying per filter) — a per-point
hybrid would produce broken curves (seam cliffs), so the whole curve takes
one source; every divergence point is listed in the cross-check report for
DECISIONS.

Domain: 380..780 @ 5 nm (81 samples), log-space linear interpolation of the
10 nm anchors; <400 linear extrapolation in log space (slope of the first
two anchors, clamped to the floor); >700 held (upstream processing rule,
copied verbatim per X-M92-1). Dashes / off-chart (D>3) map to the log-floor
(0.001 %) — an explicit sub-print-floor constant, NOT a fabricated read.
"""
from __future__ import annotations

import json
import math
import re
import sys
from pathlib import Path

FLOOR_PCT = 0.001
DOMAIN = list(range(380, 781, 5))   # 81 samples

FILTERS = {
    "w8":  "Wratten 8 (K2 yellow)",
    "w11": "Wratten 11 (yellowish green)",
    "w12": "Wratten 12 (deep yellow)",
    "w15": "Wratten 15 (G deep yellow)",
    "w21": "Wratten 21 (orange)",
    "w25": "Wratten 25 (A red)",
    "w47": "Wratten 47 (tricolor blue)",
    "w58": "Wratten 58 (tricolor green)",
}

W58_FACTOR_NOTE = (
    "factor_check_note: the Tri-X F-4017 published filter factors "
    "(p1 table) verify to within 0.21 stop for 6/7 filters; No.58 reads "
    "~0.67 stop off (D-M92-8) — kept with note, see M9-2 DECISIONS."
)


def parse_transcription(path: Path):
    cols = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        m = re.match(r"^(w\d+)\s*=\s*(.+)$", line)
        if not m:
            continue
        name, body = m.group(1), m.group(2)
        if name in cols:
            continue  # first authoritative line wins (audit notes follow)
        vals = []
        for tok in body.split(","):
            tok = tok.strip()
            vals.append(None if tok in ("n", "dash", "--") else float(tok))
        assert len(vals) == 31, (name, len(vals))
        cols[name] = vals
    missing = [k for k in FILTERS if k not in cols]
    assert not missing, f"missing B-3 columns: {missing}"
    return cols


def pct_axis(values10, floor=FLOOR_PCT):
    """31 values (pct or None) -> log10 axis, floors applied."""
    return [math.log10(max(v, floor)) if v is not None else math.log10(floor)
            for v in values10]


def resample_log(axis10):
    """10 nm log anchors (400..700) -> 81 samples on DOMAIN with the
    <400 extrapolation / >700 hold rule."""
    xs = [400 + 10 * i for i in range(31)]
    out = []
    for wl in DOMAIN:
        if wl <= xs[0]:
            # linear extrapolation in log space from the first two anchors
            slope = (axis10[1] - axis10[0]) / (xs[1] - xs[0])
            y = axis10[0] + slope * (wl - xs[0])
            y = min(y, axis10[0])   # never rise above the first anchor
        elif wl >= xs[-1]:
            y = axis10[-1]          # >700 hold
        else:
            i = max(j for j, x in enumerate(xs) if x <= wl)
            x0, x1, y0, y1 = xs[i], xs[i + 1], axis10[i], axis10[i + 1]
            y = y0 + (y1 - y0) * (wl - x0) / (x1 - x0)
        out.append(round(10 ** y, 6))
    return out


def load_w2(path: Path):
    """W2 density rows -> pct anchors (None where off-chart)."""
    w2 = json.loads(path.read_text())
    cols = {}
    for name, v in w2.items():
        vals = []
        for _wl, dens in v["density_points"]:
            vals.append(None if dens is None else 100 * 10 ** (-dens))
        cols[name] = vals
    return cols


def cross_check(b3, w2):
    """Divergence table for DECISIONS: |abs diff| > 2 percentage points."""
    report = {}
    for name in sorted(FILTERS):
        if name not in w2:
            report[name] = {"shared": 0, "divergent": [],
                            "note": "B-3 only (no W2 PDF — retired filter)"}
            continue
        divs, shared = [], 0
        for i, (a, b) in enumerate(zip(b3[name], w2[name])):
            if a is None or b is None:
                continue
            shared += 1
            if abs(a - b) > 2.0:
                divs.append({"wl": 400 + 10 * i,
                             "b3_pct": round(a, 2), "w2_pct": round(b, 2)})
        report[name] = {"shared": shared, "divergent": divs,
                        "note": f"{len(divs)} pts |abs|>2pp"}
    return report


def main():
    tdir = Path(sys.argv[1])          # evidence/t1
    b3 = parse_transcription(tdir / "b3_transcription.md")
    w2 = load_w2(Path("/tmp/w2_raw.json"))
    report = cross_check(b3, w2)

    filters = {}
    for name, desc in FILTERS.items():
        if name in w2:
            source = "kodak_wratten2"
            anchors = w2[name]
            # where W2 is off-chart but B-3 prints a value above floor,
            # keep the B-3 value (W2 has no opinion there).
            anchors = [w if w is not None else b
                       for w, b in zip(anchors, b3[name])]
            base = "W2 vector curve; B-3 fills off-chart cells"
        else:
            source = "kodak_b3_transcription"
            anchors = b3[name]
            base = "B-3 table transcription (single source)"
        entry = {
            "name": desc,
            "source": source,
            "source_basis": base,
            "cross_check": {
                "second_source": "kodak_b3_transcription" if name in w2
                                 else "none (unavailable)",
                "shared_points": report[name]["shared"],
                "divergent_points_over_2pp": len(report[name]["divergent"]),
            },
            "wavelengths_nm": DOMAIN,
            "transmittance_pct": resample_log(pct_axis(anchors)),
            "dash_or_offchart_cells_pct": [400 + 10 * i
                                           for i, v in enumerate(anchors)
                                           if v is None],
        }
        if name == "w58":
            entry["factor_check_note"] = W58_FACTOR_NOTE
        filters[name] = entry

    doc = {
        "schemaVersion": 1,
        "domain_nm": [380, 780, 5],
        "floor_pct_for_dashes": FLOOR_PCT,
        "resampling": "log-space linear between 10 nm anchors; <400 log-linear extrapolation (capped at first anchor); >700 hold",
        "source_policy": "Kodak WRATTEN 2 official curves are the asset base; Kodak B-3 transcription is the independent cross-check (and the sole source for No.11 — W2 PDF retired)",
        "filters": filters,
    }
    (tdir / "camera_filters.json").write_text(json.dumps(doc, indent=1))
    (tdir / "wratten_crosscheck.json").write_text(json.dumps(report, indent=1))

    print(f"camera_filters.json: {len(filters)} filters x {len(DOMAIN)} samples")
    for name in sorted(FILTERS):
        r = report[name]
        print(f"  {name}: {r['note']} ({r['shared']} shared)")


if __name__ == "__main__":
    main()

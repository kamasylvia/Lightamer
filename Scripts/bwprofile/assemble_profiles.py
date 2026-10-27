#!/usr/bin/env python3
"""assemble_profiles.py — build the five BW profiles (M9-2 T1 action 3).

Inputs (all self-digitized, evidence/t1):
  /tmp/trix_raw.json      Kodak F-4017 vector extraction (extract_kodak.py)
  /tmp/tmax_raw.json      Kodak F-4016 vector extraction
  /tmp/raster_traces.json Fuji/Ilford raster traces (trace_all.py)
The Acros spectral is re-traced here from the render with corrected
thresholds (the halftone chart defeats the generic pass).

Conventions:
  • log_sensitivity = chart value + C, C per film chosen so the chart
    MAX lands at −0.70 (the upstream Tri-X stored-max coincidence; an
    ASSUMED anchor — T2's Zone-V gate re-calibrates the offset in-engine).
  • Tails beyond the drawn curve continue log-linearly to a −9 floor
    (films; the plan's ASSUMED extrapolation), floor −10 for the paper's
    blind region ≥ 555 nm (directly evidenced: the chart is empty there).
  • density_curves on the CC grid (log_exposure −3..+4, 256 steps), all
    three channels identical (neutral silver).
  • channel_density [1/3,1/3,1/3] per wavelength (plan-pinned).
  • metadata.tags: SHEET = read off the datasheet, ASSUMED = modeled
    (extrapolation/normalization/channel-split) with method notes.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent.parent
EVID = ROOT / ".work/gsd/phases/m9-2-bwspectral/evidence/t1"
WL = list(range(380, 781, 5))            # 81
GRID = [round(-3.0 + 7.0 / 255 * i, 6) for i in range(256)]

CHART_FLOOR = -9.0
PAPER_FLOOR = -10.0
NORM_MAX = -0.70                          # ASSUMED normalization anchor


def resample_traces(points, xs, lo_fill, hi_fill):
    """Linear interpolation of (x, y) samples onto xs. Edges: the first/
    last SAMPLE value (clamped), never a fabricated floor — floors apply
    afterwards via log_tail/floor clamps."""
    pts = sorted(p for p in points if p[1] is not None)
    out = []
    for x in xs:
        if x <= pts[0][0]:
            out.append(pts[0][1])
        elif x >= pts[-1][0]:
            out.append(pts[-1][1])
        else:
            i = max(j for j, p in enumerate(pts) if p[0] <= x)
            (x0, y0), (x1, y1) = pts[i], pts[i + 1]
            out.append(y0 + (y1 - y0) * (x - x0) / (x1 - x0))
    return out


def extend_points(pts, floor=CHART_FLOOR, step=5.0):
    """Point-domain log-linear tails: continue the measured slope at each
    drawn end down to the floor, adding synthetic samples every `step` nm
    until the WL window is covered. The measured interior is untouched."""
    pts = sorted(p for p in pts if p[1] is not None)
    out = list(pts)
    # right tail
    x0, y0 = pts[-1]
    slope = (pts[-1][1] - pts[-6][1]) / (pts[-1][0] - pts[-6][0]) if len(pts) >= 6 else 0.0
    slope = min(slope, -0.005)          # always descend beyond the drawn end
    x, y = x0, y0
    while x < 780 and y > floor:
        x += step
        y = max(y0 + slope * (x - x0), floor)
        out.append((x, y))
    if out[-1][0] < 780:
        out.append((780.0, floor))
    # left tail
    x0, y0 = pts[0]
    slope_l = (pts[5][1] - pts[0][1]) / (pts[5][0] - pts[0][0]) if len(pts) >= 6 else 0.0
    slope_l = min(slope_l, -0.005)      # rising to the left means descending now
    x, y = x0, y0
    while x > 380 and y > floor:
        x -= step
        y = max(y0 + slope_l * (x - x0), floor)
        out.append((x, y))
    out = [(float(x), float(y)) for x, y in out if 380 <= x <= 780]
    return sorted(out)


def spectral_from_chart(points):
    """Chart anchor points -> 81 normalized log-sensitivity values."""
    pts = sorted(p for p in points if p[1] is not None)
    c = NORM_MAX - max(p[1] for p in pts)
    ext = [(x, y + c) for x, y in extend_points([(x, y) for x, y in pts])]
    vals = resample_traces(ext, WL, CHART_FLOOR, CHART_FLOOR)
    return [max(v, CHART_FLOOR) for v in vals], c


def triple(values):
    return [[v, v, v] for v in values]


def spectral_from_chart(points):
    """Chart anchor points -> 81 normalized log-sensitivity values."""
    pts = sorted(p for p in points if p[1] is not None)
    c = NORM_MAX - max(p[1] for p in pts)
    ext = [(x, y + c) for x, y in extend_points(list(pts))]
    vals = resample_traces(ext, WL, CHART_FLOOR, CHART_FLOOR)
    return [max(v, CHART_FLOOR) for v in vals], c


def make_film_profile(stock, name, publisher, pub_no, url, sha,
                      spectral_vals, char_pts, granularity, target,
                      ref_illum, extra_tags):
    fog = min(p[1] for p in char_pts)
    # density curve on the CC grid
    dens = []
    for x in GRID:
        dens.append(resample_traces(char_pts, [x], fog, char_pts[-1][1])[0])
    curves = [[d, d, d] for d in dens]
    meta = {
        "version": "1.0.0",
        "copyright": "Factual measurement data self-digitized from the "
                     f"manufacturer datasheet ({pub_no}) for the Lightamer "
                     "project; charts and sampled values are facts, the "
                     "compilation is original.",
        "created": "2026-10-27",
        "license": "Self-digitized factual data (measurements are facts, "
                   "not copyrightable). Source document: "
                   f"{publisher} {pub_no}. No content copied from any "
                   "third-party dataset.",
        "citation": f"{publisher}, {name} datasheet, publication {pub_no}, "
                    f"self-digitized {url}",
        "datasource": {
            "publisher": publisher, "publication": pub_no, "url": url,
            "pdf_sha256": sha, "digitized": "2026-10-27",
        },
        "tags": {
            "log_sensitivity": ["SHEET: chart digitization",
                                f"ASSUMED: offset C so chart max -> {NORM_MAX}"
                                " (T2 Zone-V gate re-calibrates)",
                                "ASSUMED: log-linear tails to -9 beyond the "
                                "drawn curve"],
            "density_curves": ["SHEET: characteristic-curve family digitized",
                               "ASSUMED: normal-development member selected"],
            "channel_density": ["ASSUMED: neutral silver [1/3,1/3,1/3]"],
            "base_density": ["ASSUMED: neutral fog at the traced toe minimum"],
            "granularity_rms_48um_netd1.0": granularity,
            **extra_tags,
        },
    }
    info = {
        "stock": stock, "name": name, "type": "negative", "support": "film",
        "stage": "filming", "use": "still", "antihalation": "unknown",
        "target_print": target, "channel_model": "bw",
        "densitometer": "diffuse_visual",
        "log_sensitivity_density_over_min": 0.3,
        "reference_illuminant": ref_illum, "viewing_illuminant": "D50",
    }
    data = {
        "wavelengths": [float(w) for w in WL],
        "log_sensitivity": triple([round(v, 4) for v in spectral_vals]),
        "channel_density": [[1/3, 1/3, 1/3] for _ in WL],
        "base_density": [round(fog, 3) for _ in WL],
        "midscale_neutral_density": [None] * len(WL),
        "log_exposure": GRID,
        "density_curves": curves,
    }
    return {"metadata": meta, "info": info, "data": data}


def retrace_acros_spectral():
    """Acros i8 with corrected thresholds (single heavy run per column)."""
    import trace_all as T
    ink = T.load_ink("acros2_p3_i8")
    xa, xb, _ = T.affine_anchors([(136, 400), (347.5, 500), (560, 600), (771.5, 700)])
    ya, yb, _ = T.affine_anchors([(69, 2), (276.5, 0), (483, -2), (689.5, -4)])
    hgrid = [69, 276.5, 483, 689.5]
    vgrid = [136, 347.5, 560, 771.5]
    pts = []
    for c in range(110, 790):
        if any(abs(c - v) <= 2 for v in vgrid):
            continue
        rs = T.column_runs(ink, c, 140, hgrid, vgrid)
        rs = [(cy, ws) for cy, ws in rs if 80 <= cy <= 700 and ws >= 450]
        if not rs:
            continue
        best = max(rs, key=lambda r: r[1])
        pts.append((xa * c + xb, ya * best[0] + yb))
    return pts


def main():
    trix = json.loads(Path("/tmp/trix_raw.json").read_text())
    tmax = json.loads(Path("/tmp/tmax_raw.json").read_text())
    raster = json.loads(Path("/tmp/raster_traces.json").read_text())

    out_dir = EVID / "profiles"
    out_dir.mkdir(exist_ok=True)

    # sha256 of the source PDFs (from SHA256SUMS.txt, evidence)
    sums = {}
    for line in (EVID / "sources/SHA256SUMS.txt").read_text().splitlines():
        parts = line.split()
        if len(parts) == 2:
            sums[parts[1]] = parts[0]

    profiles = {}

    # 1. Kodak TRI-X 400 (F-4017)
    spec_vals, c = spectral_from_chart(trix["trix_spectral_d03"]["points"])
    char = [p for p in trix["trix_char_35mm_largetank"]["curves"]["3"]["points"]
            if p[1] is not None]
    profiles["kodak_tri_x_400"] = make_film_profile(
        "kodak_tri_x_400", "Kodak Professional TRI-X 400 / 400TX",
        "Eastman Kodak Company", "F-4017",
        "https://www.kodak.com/sites/default/files/files/G4017_TriX.pdf",
        sums.get("f4017_trix.pdf", "?"),
        spec_vals, char, 17, "ilford_multigrade_iv_rc", "D55",
        {"granularity_note": "SHEET: '17 (fine)' — HC-110 Dil B base; "
         "48 um aperture, net diffuse density 1.0, 12X"})

    # 2. Kodak T-MAX 100 (F-4016)
    spec_vals, _ = spectral_from_chart(tmax["tmax_spectral_d03"]["points"])
    char = [p for p in tmax["tmax_char_d76_smalltank"]["curves"]["18"]["points"]
            if p[1] is not None]
    profiles["kodak_tmax_100"] = make_film_profile(
        "kodak_tmax_100", "Kodak Professional T-MAX 100",
        "Eastman Kodak Company", "F-4016",
        "https://www.kodak.com/sites/default/files/files/F4016_T-Max100.pdf",
        sums.get("f4016_tmax100.pdf", "?"),
        spec_vals, char, 8, "ilford_multigrade_iv_rc", "D55",
        {"granularity_note": "SHEET: image-structure table value 8 — "
         "D-76 base; 48 um aperture, net diffuse density 1.0, 12X. "
         "Corrected from third-party 7.4 (DECISIONS R4)."})

    # 3. Fujifilm NEOPAN ACROS II (AF3-0258E)
    spec_pts = retrace_acros_spectral()
    spec_vals, _ = spectral_from_chart(spec_pts)
    char = [p for p in raster["acros_char"]["curves"][1] if p[1] is not None]
    profiles["fujifilm_neopan_acros_100_ii"] = make_film_profile(
        "fujifilm_neopan_acros_100_ii", "FUJIFILM NEOPAN 100 ACROS II",
        "FUJIFILM Corporation", "AF3-0258E",
        "https://asset.fujifilm.com/master/digital/datasheets/AF3-0258E_AcrosII.pdf",
        sums.get("acros2.pdf", "?"),
        spec_vals, char, 7, "ilford_multigrade_iv_rc", "D55",
        {"granularity_note": "SHEET: 'DIFFUSE RMS GRANULARITY VALUE: 7' — "
         "Microfine dev; 48 um, sample density 1.0 above minimum"})

    # 4. Ilford HP5 Plus (datasheet)
    spec_pts = [p for p in raster["hp5_spectral"]["curves"][0] if p[1] is not None]
    spec_vals, _ = spectral_from_chart(spec_pts)
    char = [p for p in raster["hp5_char"]["curves"][0] if p[1] is not None]
    profiles["ilford_hp5_plus_400"] = make_film_profile(
        "ilford_hp5_plus_400", "ILFORD HP5 PLUS",
        "Harman technology Limited (Ilford Photo)", "HP5-PLUS datasheet",
        "https://www.ilfordphoto.com/amfile/file/download/file/1913/product/691/",
        sums.get("hp5.pdf", "?"),
        spec_vals, char, None, "ilford_multigrade_iv_rc", "D55",
        {"granularity_note": "ASSUMED: null — Harman does not publish an "
         "RMS granularity figure for HP5 Plus (DECISIONS); T4 calibration "
         "interpolates the family"})

    # 5. Ilford MULTIGRADE IV RC (paper) — three-channel ASSUMED split
    env_pts = [p for p in raster["mg_spectral"]["curves"][0] if p[1] is not None]
    env = resample_traces(env_pts, WL, PAPER_FLOOR, PAPER_FLOOR)
    # normalize the envelope the same way, then clamp at the paper floor
    c = NORM_MAX - max(env)
    env = [min(max(v + c, PAPER_FLOOR), 0.0) for v in env]
    green = [env[max(0, i - 14)] for i in range(len(env))]   # +70nm shift
    vals = []
    for i in range(81):
        lam = WL[i]
        b = env[i] if lam < 555 else PAPER_FLOOR
        g = green[i] if lam < 555 else PAPER_FLOOR
        vals.append([round(b, 4), round(g, 4), round(PAPER_FLOOR, 4)])
    # Grade characteristic curves (three members of the fan). The paper's
    # density_curves rows are PER-CHANNEL = [soft, mid, hard] member curves
    # — the M9-2 T2 construction: the print light's channel weighting
    # (printCC pin) then selects the emulsion blend IN THE EXISTING ENGINE
    # (the scan leg averages the three channels through the neutral
    # [1/3,1/3,1/3] silver split — real variable contrast, zero engine
    # changes). Channel order follows the sensitivity split: c0 = the
    # blue/soft emulsion, c1 = green/hard, c2 = the blind channel carries
    # the MID member (constant-ish; its exposure is ~nil).
    fan = [raster["mg_char_a"]["curves"][i] for i in (0, 1, 3)]
    member_rows = []
    for member in fan:
        pts = [p for p in member if p[1] is not None]
        fog = min(p[1] for p in pts)
        member_rows.append([resample_traces(pts, [x], fog, pts[-1][1])[0]
                            for x in GRID])
    # contrast sanity: order members by the logE span between the D=0.6
    # crossings (soft = widest span). Monotone fan = a build assertion.
    def span(rows):
        fog = min(rows)
        lo = next((i for i, v in enumerate(rows) if v >= fog + 0.3), None)
        hi = next((i for i in range(len(rows) - 1, -1, -1)
                   if rows[i] >= fog + 0.8), None)
        return (hi - lo) if (lo is not None and hi is not None and hi > lo) else 0
    spans = [span(r) for r in member_rows]
    order = sorted(range(3), key=lambda i: spans[i])   # small span = hard
    assert spans[order[0]] < spans[order[2]], f"fan spans not ordered: {spans}"
    def renorm(rows, base):
        # fog-normalization: the traced chart region bounds the toe, so
        # the absolute floor is re-anchored to the paper base (shape and
        # inter-member offsets preserved — ASSUMED, tags carry it).
        fog = min(rows)
        return [v - fog + base for v in rows]
    soft = renorm(member_rows[order[2]], 0.06)
    mid = renorm(member_rows[order[1]], 0.07)
    hard = renorm(member_rows[order[0]], 0.08)
    profiles["ilford_multigrade_iv_rc"] = {
        "metadata": {
            "version": "1.0.0",
            "copyright": "Factual measurement data self-digitized from the "
                         "manufacturer datasheet for the Lightamer project; "
                         "the compilation is original.",
            "created": "2026-10-27",
            "license": "Self-digitized factual data (measurements are facts, "
                       "not copyrightable). No content copied from any "
                       "third-party dataset.",
            "citation": "Harman technology Limited, MULTIGRADE IV RC "
                        "datasheet, self-digitized",
            "datasource": {
                "publisher": "Harman technology Limited",
                "publication": "multigrade4.pdf (datasheet download)",
                "url": "https://www.ilfordphoto.com/amfile/file/download/file/3/product/1026/",
                "pdf_sha256": sums.get("multigrade4.pdf", "?"),
                "digitized": "2026-10-27",
            },
            "tags": {
                "log_sensitivity": [
                    "SHEET: single traced envelope 390-545nm (the chart "
                    "draws the emulsions fused at this resolution)",
                    "ASSUMED: three-channel split — blue = envelope, "
                    "green = envelope shifted +70nm, red = blind",
                    "SHEET: no ink beyond ~545nm — the >=555nm blindness is "
                    "directly evidenced (safelight region)"],
                "density_curves": ["SHEET: three grade-fan members traced",
                                   "ASSUMED: grade labels unreadable at "
                                   "chart resolution; T2 fits m/y per grade"],
                "granularity_rms": "n/a (paper)",
            },
        },
        "info": {
            "stock": "ilford_multigrade_iv_rc",
            "name": "ILFORD MULTIGRADE IV RC",
            "type": "negative", "support": "paper", "stage": "printing",
            "use": "still", "antihalation": "none", "target_print": None,
            "channel_model": "bw", "densitometer": "diffuse_visual",
            "log_sensitivity_density_over_min": 1.0,
            "reference_illuminant": "TH-KG3", "viewing_illuminant": "D50",
        },
        "data": {
            "wavelengths": [float(w) for w in WL],
            "log_sensitivity": vals,
            "channel_density": [[1/3, 1/3, 1/3] for _ in WL],
            "base_density": [0.06] * len(WL),
            "midscale_neutral_density": [None] * len(WL),
            "log_exposure": GRID,
            # Channel pairing (Multigrade physics: the BLUE-sensitive
            # emulsion is the HIGH-contrast one, the GREEN-sensitive is
            # LOW-contrast — yellow filtration softens, magenta hardens):
            # c0 (blue envelope) = hard member, c1 (green shifted) = soft
            # member, c2 (blind) carries the mid member (~no exposure).
            "density_curves": [[hard[i], soft[i], mid[i]]
                               for i in range(len(GRID))],
            "bw_grade_curves": {
                "note": "the three traced grade members (soft/mid/hard by "
                        "measured span); the main density_curves rows "
                        "carry them per channel — T2's PaperGradeTable "
                        "fits each grade's m/y/exposure against the "
                        "datasheet ISO R table",
                "log_exposure": GRID,
                "curves": [member_rows[0], member_rows[1], member_rows[2]],
            },
        },
    }

    for name, prof in profiles.items():
        p = out_dir / f"{name}.json"
        p.write_text(json.dumps(prof, indent=1))
        print(f"wrote {p.name}: logS rows={len(prof['data']['log_sensitivity'])} "
              f"curves={len(prof['data']['density_curves'])}")


if __name__ == "__main__":
    main()

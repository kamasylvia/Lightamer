#!/usr/bin/env python3
"""Issue #24 experience-speed runner.

Cold  : one OS process per measurement (process start + Metal/CIContext init included).
Hot   : one process, N reps, CIContext.clearCaches() between reps (device/context retained).
M2    : the edit (exposure +0.5 EV) is applied to the retained decoded image and the
        preview is re-rendered; self-proof = bitmap hash must change.

Usage: benchrun.py --root <spike root> --out <csv path> [--quick]
"""
import argparse
import json
import os
import statistics
import subprocess
import sys
import time

FIT = "2560"
ROWS = []


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=isinstance(cmd, str), capture_output=True, text=True, **kw)


def parse(line):
    out = {}
    for tok in line.split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            out[k] = v
    return out


def cold(cmd, n=10, warm=3):
    """n timed runs, each a fresh process.

    The parent wall clock covers spawn -> exit, which includes the verification
    hash (computed outside the in-process timed window). We subtract that hash
    cost so the headline is "user action -> bitmap ready", process start
    included. Returns (median, min, p90, parsed) of the corrected wall.
    """
    walls, parsed = [], None
    for i in range(n + warm):
        t0 = time.monotonic()
        p = subprocess.run(cmd, capture_output=True, text=True)
        wall = (time.monotonic() - t0) * 1000.0
        if p.returncode != 0:
            raise SystemExit(f"FAILED {cmd}: {p.stderr[-400:]}")
        if i >= warm:
            parsed = parse(p.stdout.strip().splitlines()[-1])
            hash_ms = float(parsed.get("hash_ms", 0) or 0)
            walls.append(max(0.0, wall - hash_ms))
    walls.sort()
    return statistics.median(walls), walls[0], walls[min(len(walls) - 1, int(len(walls) * 0.9))], parsed


def hot(cmd, reps=10, clear=True):
    args = cmd + ["--reps", str(reps)] + (["--clear"] if clear else [])
    p = subprocess.run(args, capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit(f"FAILED {cmd}: {p.stderr[-400:]}")
    d = parse(p.stdout.strip().splitlines()[-1])
    med = d.get("med_e2e_ms") or d.get("edit_to_bitmap_ms")
    return float(med), float(d.get("min_e2e_ms", med)), float(d.get("p90_e2e_ms", med)), d


def record(row, path, kind, n, med, mn, p90, d, note=""):
    ROWS.append(dict(row=row, path=path, kind=kind, n=n, median_ms=round(med, 1),
                     min_ms=round(mn, 1), p90_ms=round(p90, 1),
                     open_ms=d.get("open_ms", ""), render_ms=d.get("render_ms", ""),
                     hash=d.get("hash", ""), note=note))
    print(f"{row:<42} {kind:<5} n={n:<3} median={med:8.1f}ms  min={mn:8.1f}  p90={p90:8.1f}  {note}")


def libraw_row(root, label, path, extra, n=10):
    cmd = [f"{root}/bin/lrbench", path] + extra
    total, proc = [], []
    for i in range(n + 3):
        p = subprocess.run(cmd, capture_output=True, text=True)
        if p.returncode != 0:
            raise SystemExit(f"FAILED {cmd}: {p.stderr[-300:]}")
        d = parse(p.stdout.strip().splitlines()[-1])
        if i >= 3:
            total.append(float(d["total_ms"]))
            proc.append(float(d["process_ms"]))
    total.sort(); proc.sort()
    med = statistics.median(total)
    record(label, os.path.basename(path), "cold", n, med, total[0],
           total[min(len(total) - 1, int(len(total) * 0.9))],
           {"open_ms": f"{float(d['open_ms']) + float(d['unpack_ms']):.2f}",
            "render_ms": f"{statistics.median(proc):.2f}", "hash": d["hash"]},
           note=f"LibRaw stand-in {' '.join(extra)}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--quick", action="store_true")
    a = ap.parse_args()
    root = a.root
    bench = f"{root}/bin/bench"
    benchlive = f"{root}/bin/benchlive"
    camxml = f"{root}/rawspeed/data/cameras.xml"
    n = 5 if a.quick else 10
    warm = 1 if a.quick else 3

    arw = f"{root}/samples/7RM5-LosslessCompressedLarge.ARW"
    dng = {ds: f"{root}/work/a7r5-ds{ds}.dng" for ds in (0, 1, 2)}
    env_info = {
        "date": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "machine": sh("sysctl -n machdep.cpu.brand_string").stdout.strip(),
        "os": sh("sw_vers -productVersion").stdout.strip(),
        "xcode": sh("xcodebuild -version").stdout.splitlines()[0] if sh("which xcodebuild").returncode == 0 else "",
        "mem_gb": round(int(sh("sysctl -n hw.memsize").stdout.strip()) / 2**30),
        "memory_pressure": sh("memory_pressure").stdout.strip().splitlines()[-1] if sh("which memory_pressure").returncode == 0 else "",
        "heavy_procs": (sh("pgrep -l 'xcodebuild|test-direct|swift-build|cmake|ninja'").stdout.strip()[:400] or "none"),
    }
    print(json.dumps(env_info, ensure_ascii=False, indent=1))

    # ---- M1 cold: open -> preview bitmap ----
    for label, cmd in [
        ("P0 CIRAW v8 A7R5 fit", [bench, "raw", arw, "--target", "fit", "--decoder", "v8"]),
        ("P0 CIRAW v8 A7R5 full", [bench, "raw", arw, "--target", "full", "--decoder", "v8"]),
        ("P1a live ds0 fit (decode+DNG+CI)", [benchlive, camxml, arw, "--target", "fit"]),
        ("P1a live ds0 full", [benchlive, camxml, arw, "--target", "full"]),
        ("P1a live ds1 fit", [benchlive, camxml, arw, "--target", "fit", "--downsample", "1"]),
        ("P1a live ds2 fit", [benchlive, camxml, arw, "--target", "fit", "--downsample", "2"]),
        ("P1b cached-DNG ds0 fit", [bench, "dng", dng[0], "--target", "fit", "--decoder", "v8dng"]),
        ("P1b cached-DNG ds0 full", [bench, "dng", dng[0], "--target", "full", "--decoder", "v8dng"]),
        ("P1b cached-DNG ds1 fit", [bench, "dng", dng[1], "--target", "fit", "--decoder", "v8dng"]),
        ("P1b cached-DNG ds2 fit", [bench, "dng", dng[2], "--target", "fit", "--decoder", "v8dng"]),
        ("P0 CIRAW v8 1280 long edge", [bench, "raw", arw, "--target", "fit", "--long-edge", "1280", "--decoder", "v8"]),
        ("P0 CIRAW v8 640 long edge", [bench, "raw", arw, "--target", "fit", "--long-edge", "640", "--decoder", "v8"]),
    ]:
        med, mn, p90, d = cold(cmd, n, warm)
        record(label, "M1-cold", "cold", n, med, mn, p90, d)

    # RAW 9 via DNG: expensive (model prep) — fewer reps
    med, mn, p90, d = cold([benchlive, camxml, arw, "--target", "fit", "--decoder", "v9dng"],
                           max(3, n // 2), 2)
    record("P1a live ds0 v9DNG fit (RAW9)", "M1-cold", "cold", max(3, n // 2), med, mn, p90, d,
           note="RAW 9 demosaic+denoise via DNG")

    # ---- M1 hot ----
    for label, cmd in [
        ("P0 CIRAW v8 A7R5 fit", [bench, "raw", arw, "--target", "fit", "--decoder", "v8"]),
        ("P0 CIRAW v8 A7R5 full", [bench, "raw", arw, "--target", "full", "--decoder", "v8"]),
        ("P1b cached-DNG ds0 fit", [bench, "dng", dng[0], "--target", "fit", "--decoder", "v8dng"]),
        ("P1b cached-DNG ds0 full", [bench, "dng", dng[0], "--target", "full", "--decoder", "v8dng"]),
        ("P1b cached-DNG ds1 fit", [bench, "dng", dng[1], "--target", "fit", "--decoder", "v8dng"]),
    ]:
        med, mn, p90, d = hot(cmd, n)
        record(label, "M1-hot", "hot", n, med, mn, p90, d, note="clearCaches between re-opens")

    # ---- M2: edit -> preview updated ----
    for label, cmd in [
        ("P0 CIRAW v8 fit", [bench, "edit", arw, "--target", "fit", "--decoder", "v8"]),
        ("P0 CIRAW v8 100% ROI", [bench, "edit", arw, "--target", "roi", "--decoder", "v8"]),
        ("P1 cached-DNG ds0 fit", [bench, "edit", dng[0], "--target", "fit", "--decoder", "v8dng", "--dng"]),
        ("P1 cached-DNG ds0 100% ROI", [bench, "edit", dng[0], "--target", "roi", "--decoder", "v8dng", "--dng"]),
    ]:
        # M2 keeps the natural design's caches (the decoded image + context): no clearCaches.
        med, mn, p90, d = hot(cmd, n, clear=False)
        record(label, "M2", "hot", n, med, mn, p90, d,
               note="exposure +0.5EV -> bitmap; caches retained (no clearCaches)")

    # ---- P2 stand-in: LibRaw CPU demosaic ----
    libraw_row(root, "P2 LibRaw full linear", arw, ["--qual", "0"], n)
    libraw_row(root, "P2 LibRaw full AMaZE", arw, ["--qual", "11"], n)
    libraw_row(root, "P2 LibRaw half linear", arw, ["--qual", "0", "--half"], n)
    libraw_row(root, "P2 LibRaw half AMaZE", arw, ["--qual", "11", "--half"], n)

    # ---- write CSV ----
    keys = ["row", "path", "kind", "n", "median_ms", "min_ms", "p90_ms", "open_ms", "render_ms", "hash", "note"]
    with open(a.out, "w") as f:
        f.write(",".join(keys) + "\n")
        for r in ROWS:
            f.write(",".join('"' + str(r.get(k, "")).replace('"', "'") + '"' for k in keys) + "\n")
    print(f"\nCSV -> {a.out}")


if __name__ == "__main__":
    main()

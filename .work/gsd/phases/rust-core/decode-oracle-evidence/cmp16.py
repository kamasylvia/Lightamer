#!/usr/bin/env python3
"""cmp16.py — compare two images at full bit depth (8/16-bit PNG/TIFF).

usage: uv run --with opencv-python-headless --with numpy cmp16.py A B [--tol T] [--shift]
  T = tolerance in normalized [0,1] units (default 1/255).
  --shift: also try +/-1px x/y shifts of B, report best (for geometric modules).
Reads via cv2.IMREAD_UNCHANGED (Pillow truncates 16-bit RGB to 8-bit).
Outputs: shape/dtype, mean/max abs diff (normalized + LSB of A),
in-tolerance pixel fraction, per-channel means.
"""
import sys
import numpy as np

try:
    import cv2
except ImportError:
    raise SystemExit("need opencv: uv run --with opencv-python-headless --with numpy cmp16.py ...")


def load(path):
    a = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    if a is None:
        raise SystemExit(f"cannot read {path}")
    if a.dtype == np.uint8:
        scale = 255.0
    elif a.dtype == np.uint16:
        scale = 65535.0
    else:
        raise SystemExit(f"unsupported dtype {a.dtype} for {path}")
    return a, a.astype(np.float64) / scale, scale


def stats(fa, fb, scale, tag):
    d = np.abs(fa - fb)
    mean = float(d.mean())
    mx = float(d.max())
    return mean, mx


def main():
    args = []
    tol = 1.0 / 255.0
    shift = False
    it = iter(sys.argv[1:])
    for a in it:
        if a == "--tol":
            tol = float(next(it))
        elif a.startswith("--tol="):
            tol = float(a.split("=", 1)[1])
        elif a == "--shift":
            shift = True
        else:
            args.append(a)
    if len(args) != 2:
        raise SystemExit("usage: cmp16.py A B [--tol T] [--shift]")
    pa, pb = args
    rawa, fa, sa = load(pa)
    rawb, fb, sb = load(pb)
    print(f"A={pa} shape={rawa.shape} dtype={rawa.dtype}")
    print(f"B={pb} shape={rawb.shape} dtype={rawb.dtype}")
    if rawa.shape != rawb.shape:
        raise SystemExit(f"shape mismatch: {rawa.shape} vs {rawb.shape}")
    mean, mx = stats(fa, fb, sa, "")
    d = np.abs(fa - fb)
    frac = float((d <= tol).mean())
    print(f"tol={tol:.6g} (= {tol * sa:.3g} LSB of A)")
    print(f"mean_abs_diff={mean:.8f} (= {mean * sa:.4f} LSB)")
    print(f"max_abs_diff={mx:.8f} (= {mx * sa:.4f} LSB)")
    print(f"in_tol_fraction={frac:.8f}")
    ch = fa.shape[-1] if fa.ndim == 3 else 1
    print(f"mean_ch_A={fa.reshape(-1, ch).mean(axis=0)}")
    print(f"mean_ch_B={fb.reshape(-1, ch).mean(axis=0)}")
    if shift:
        best = (mean, 0, 0)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                g = np.roll(np.roll(fb, dy, 0), dx, 1)[1:-1, 1:-1]
                h = fa[1:-1, 1:-1]
                m = float(np.abs(g - h).mean())
                if m < best[0]:
                    best = (m, dy, dx)
        print(f"best_shift dy={best[1]} dx={best[2]} mean={best[0]:.8f} (= {best[0] * sa:.4f} LSB)")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""cmp_images.py — compare two images: mean/max abs diff + in-tolerance fraction.

usage: uv run --with pillow --with numpy cmp_images.py A B [--tol T]
  T = tolerance in normalized [0,1] units (default 1/255).
  Images are read with PIL, converted to float64 normalized by dtype max
  (uint8 -> /255, uint16 -> /65535). Must match in size and channels
  (RGB/RGBA handled by common prefix; alpha ignored unless both RGBA... actually
  compared on shared channels, alpha included if both have it).
"""
import sys
import numpy as np
from PIL import Image


def load(path):
    im = Image.open(path)
    a = np.asarray(im)
    if a.dtype == np.uint8:
        scale = 255.0
    elif a.dtype == np.uint16:
        scale = 65535.0
    else:
        raise SystemExit(f"unsupported dtype {a.dtype} for {path}")
    return a, a.astype(np.float64) / scale, str(a.dtype)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--tol")]
    tol = 1.0 / 255.0
    for a in sys.argv[1:]:
        if a.startswith("--tol"):
            tol = float(a.split("=", 1)[1] if "=" in a else sys.argv[sys.argv.index(a) + 1])
    if len(args) != 2:
        raise SystemExit("usage: cmp_images.py A B [--tol T]")
    pa, pb = args
    rawa, fa, da = load(pa)
    rawb, fb, db = load(pb)
    print(f"A={pa} shape={rawa.shape} dtype={da}")
    print(f"B={pb} shape={rawb.shape} dtype={db}")
    if rawa.shape != rawb.shape:
        raise SystemExit(f"shape mismatch: {rawa.shape} vs {rawb.shape}")
    d = np.abs(fa - fb)
    mean = float(d.mean())
    mx = float(d.max())
    frac = float((d <= tol).mean())
    # mean in LSB of A
    lsb = 255.0 if da == "uint8" else 65535.0
    print(f"tol={tol:.6g} (= {tol * lsb:.3g} LSB of A)")
    print(f"mean_abs_diff={mean:.8f} (= {mean * lsb:.4f} LSB)")
    print(f"max_abs_diff={mx:.8f} (= {mx * lsb:.4f} LSB)")
    print(f"in_tol_fraction={frac:.8f}")
    print(f"mean_rgb_A={fa.reshape(-1, fa.shape[-1]).mean(axis=0)}")
    print(f"mean_rgb_B={fb.reshape(-1, fb.shape[-1]).mean(axis=0)}")


if __name__ == "__main__":
    main()

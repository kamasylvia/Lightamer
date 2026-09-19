#!/usr/bin/env python3
"""Generate the RAW-03 float32 test fixtures (Plan 02-06-06).

Creates two 64×64 grayscale float32 images with KNOWN extreme pixel values
pinned at fixed coordinates:

    (8,  8)  = 0.0        (deep black)
    (16, 16) = 0.5        (mid gray)
    (24, 24) = 1.0        (SDR white)
    (32, 32) = 2.0        (HDR — above SDR white; MUST survive, D-COL4)
    (40, 40) = 65504.0    (float16 max — the extreme HDR probe)

Everything else is a horizontal linear gradient (0→2) so generic pipeline
breakage is visible at a glance. Values are channel-equal GRAY: gray stays
numerically identical under any white-point-preserving linear RGB→RGB
conversion, so the exact values survive the pixelpipe's Rec2020 input leg
regardless of how the (untagged) file's colorspace is interpreted.

Files (committed, tracked):
    Resources/TestFixtures/float32-gradient.tif   — float32 TIFF (tifffile)
    Resources/TestFixtures/float32-gradient.exr   — half/float EXR (OpenEXR)

Regenerate:  uv run --with numpy --with tifffile --with OpenEXR python3 Scripts/gen-float-fixtures.py
"""

from pathlib import Path

import numpy as np
import OpenEXR
import Imath
import tifffile

W = H = 64
COORDS = [(8, 8, 0.0), (16, 16, 0.5), (24, 24, 1.0), (32, 32, 2.0), (40, 40, 65504.0)]


def build() -> np.ndarray:
    # Horizontal gradient 0→2, channel-equal gray (H, W, 3).
    ramp = np.linspace(0.0, 2.0, W, dtype=np.float32)
    img = np.stack([ramp] * 3, axis=-1)
    img = np.broadcast_to(ramp[None, :, None], (H, W, 3)).copy()
    for x, y, v in COORDS:
        img[y, x, :] = np.float32(v)
    return img


def write_tiff(path: Path, img: np.ndarray) -> None:
    # SampleFormat=3 (IEEE float), 32 bits/component, 3 samples/px.
    tifffile.imwrite(path, img, photometric="rgb", planarconfig="contig")


def write_exr(path: Path, img: np.ndarray) -> None:
    # OpenEXR core classic API (OutputFile + Imath.Channel, FLOAT32 pixels).
    header = OpenEXR.Header(W, H)
    header["channels"] = {
        c: Imath.Channel(Imath.PixelType(Imath.PixelType.FLOAT)) for c in "RGB"
    }
    out = OpenEXR.OutputFile(str(path), header)
    out.writePixels(
        {
            "R": img[:, :, 0].copy(),
            "G": img[:, :, 1].copy(),
            "B": img[:, :, 2].copy(),
        }
    )
    out.close()


def main() -> None:
    root = Path(__file__).resolve().parent.parent / "Resources" / "TestFixtures"
    root.mkdir(parents=True, exist_ok=True)
    img = build()
    write_tiff(root / "float32-gradient.tif", img)
    write_exr(root / "float32-gradient.exr", img)
    for x, y, v in COORDS:
        print(f"pinned ({x:2},{y:2}) = {v}")
    print(f"written: {root}/float32-gradient.{{tif,exr}}")


if __name__ == "__main__":
    main()

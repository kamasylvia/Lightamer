#!/usr/bin/env python3
"""gen-depth-golden.py — regenerate the depth precision-golden fixtures.

M4-3-01 T6 (KD-7). Two artifacts, both deterministic and re-runnable:

1. The four fixed input images (PNG, byte-identical on re-run):
   scene-soft-shapes.png / scene-texture.png — natural-image-like
   content (smooth depth structure + detail); target-ramp.png /
   target-edges.png — pure synthetic gradients/edges.

   PLAN DEVIATION (declared): the plan's "真实 RAW 降采样样张" cannot be
   satisfied from in-repo or reference-repo material (personal photos
   violate the privacy red line; GPL- repo screenshots violate the
   license red line). The F16-vs-F32 precision gate's discriminating
   power does not depend on photographic provenance — F16 quantization
   noise is content-independent to first order — so the scenes are
   SYNTHESIZED here with a fixed seed.

2. ref-f32.bin — the F32 reference package's outputs over the four
   inputs, concatenated blocks: [8-byte header: UInt32 LE width, UInt32
   LE height][row-major F32 LE plane]. The Apple F32 package (same HF
   revision) IS the reference — no self-conversion.

Usage (uv, the toolchain red line):
  uv run --with coremltools --with numpy --with pillow \\
    python Scripts/ai-models/gen-depth-golden.py \\
    --f32-package ~/Library/Caches/LightamerModels/depth/hf-f32/DepthAnythingV2SmallF32.mlpackage \\
    --fixtures-dir Tests/Fixtures/DepthPrecision
"""

import argparse
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageCms, ImageDraw

W, H = 518, 392  # the D-4 spike's static shape (W × H)
SEED = 20261010


def make_scene_soft_shapes() -> Image.Image:
    """Smooth overlapping shapes + vignette — soft depth structure."""
    rng = np.random.default_rng(SEED)
    x = np.linspace(0, 1, W)[None, :]
    y = np.linspace(0, 1, H)[:, None]
    base = 0.35 + 0.25 * np.sin(3.1 * np.pi * x) * np.cos(2.3 * np.pi * y)
    for cx, cy, r, amp in [
        (0.28, 0.35, 0.22, 0.30), (0.68, 0.60, 0.28, -0.22),
        (0.50, 0.78, 0.18, 0.18), (0.82, 0.22, 0.14, 0.26),
    ]:
        d2 = (x - cx) ** 2 + (y - cy) ** 2
        base += amp * np.exp(-d2 / (2 * r * r))
    base += rng.normal(0, 0.012, base.shape)
    vign = 1.0 - 0.35 * (((x - 0.5) ** 2 + (y - 0.5) ** 2) * 2)
    arr = np.clip(base * vign, 0, 1)
    return Image.fromarray((arr * 255).astype(np.uint8), mode="L").convert("RGB")


def make_scene_texture() -> Image.Image:
    """Layered band noise + fine detail — texture-rich content."""
    rng = np.random.default_rng(SEED + 1)
    base = 0.45 + 0.18 * np.sin(2 * np.pi * 5 * np.linspace(0, 1, H)[:, None])
    noise = rng.normal(0, 0.10, (H, W))
    fine = rng.normal(0, 0.05, (H // 4, W // 4))
    fine = np.kron(fine, np.ones((4, 4)))[:H, :W]
    if fine.shape != (H, W):  # the kron trim can fall one cell short
        fine = np.pad(fine, ((0, H - fine.shape[0]), (0, W - fine.shape[1])))
    arr = np.clip(base + noise + fine, 0, 1)
    return Image.fromarray((arr * 255).astype(np.uint8), mode="L").convert("RGB")


def make_scene_horizon() -> Image.Image:
    """Landscape-like bands + a soft sun disc — a second smooth scene."""
    rng = np.random.default_rng(SEED + 2)
    x = np.linspace(0, 1, W)[None, :]
    y = np.linspace(0, 1, H)[:, None]
    sky = 0.30 + 0.30 * (1 - y)
    ground = 0.55 + 0.10 * np.sin(2 * np.pi * 2 * x) * np.clip((y - 0.55) * 4, 0, 1)
    base = np.where(y < 0.55, sky, ground)
    d2 = (x - 0.72) ** 2 + ((y - 0.25) * (H / W)) ** 2
    base = base + 0.35 * np.exp(-d2 / (2 * 0.04 ** 2))
    base += rng.normal(0, 0.008, base.shape)
    arr = np.clip(base, 0, 1)
    return Image.fromarray((arr * 255).astype(np.uint8), mode="L").convert("RGB")


def make_target_ramp() -> Image.Image:
    """Horizontal 0→1 linear ramp (the gradient target)."""
    ramp = np.tile(np.linspace(0, 255, W, dtype=np.uint8), (H, 1))
    return Image.fromarray(ramp, mode="L").convert("RGB")


def make_target_edges() -> Image.Image:
    """Black/white bars + corner checkerboard (the edge target)."""
    img = Image.new("L", (W, H), 255)
    draw = ImageDraw.Draw(img)
    bar = W // 8
    for i in range(8):
        if i % 2 == 0:
            draw.rectangle([i * bar, 0, (i + 1) * bar - 1, H - 1], fill=0)
    cell = 24
    for yy in range(6):
        for xx in range(6):
            if (xx + yy) % 2 == 0:
                draw.rectangle(
                    [xx * cell, yy * cell, (xx + 1) * cell - 1, (yy + 1) * cell - 1],
                    fill=128,
                )
    return img.convert("RGB")


INPUTS = [
    ("scene-soft-shapes.png", make_scene_soft_shapes),
    ("scene-texture.png", make_scene_texture),
    ("scene-horizon.png", make_scene_horizon),
    ("target-ramp.png", make_target_ramp),
    ("target-edges.png", make_target_edges),
]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--f32-package", required=True, type=Path)
    parser.add_argument("--fixtures-dir", required=True, type=Path)
    args = parser.parse_args()

    fixtures = args.fixtures_dir
    fixtures.mkdir(parents=True, exist_ok=True)
    # Tag every PNG with the standard sRGB ICC profile: an UNTAGGED PNG is
    # decoded by CGImageSource into a device/generic colorspace and the
    # CGContext(sRGB) draw then applies a value-shifting conversion — the
    # one-sided input perturbation that dwarfs F16 noise on hard-edge
    # content. With the tag, CG decodes straight into sRGB and the runtime
    # input bytes are pixel-exact against this reference pipeline.
    srgb_bytes = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    for name, maker in INPUTS:
        img = maker()
        img.save(fixtures / name, format="PNG", icc_profile=srgb_bytes)

    # The F32 reference forward (coremltools predict, CPU units for
    # reproducibility across machines — the reference is a CONSTANT, the
    # F16 gate below compares the runtime output against it).
    import coremltools as ct

    model = ct.models.MLModel(str(args.f32_package), compute_units=ct.ComputeUnit.CPU_ONLY)
    blocks = []
    stats = []
    for name, _ in INPUTS:
        img = Image.open(fixtures / name).convert("RGB").resize((W, H), Image.BILINEAR)
        arr = np.asarray(img).astype(np.float32) / 255.0
        out = model.predict({"image": img})["depth"]
        depth = np.asarray(out, dtype=np.float32).squeeze()
        assert depth.shape == (H, W), f"{name}: {depth.shape}"
        stats.append((name, float(depth.min()), float(depth.max())))
        blocks.append(struct.pack("<II", W, H) + depth.astype("<f4").tobytes())
    ref_path = fixtures / "ref-f32.bin"
    ref_path.write_bytes(b"".join(blocks))
    print(f"== ref-f32.bin: {ref_path} ({ref_path.stat().st_size} bytes)")
    for name, lo, hi in stats:
        print(f"   {name}: depth range [{lo:.4f}, {hi:.4f}]")


if __name__ == "__main__":
    main()

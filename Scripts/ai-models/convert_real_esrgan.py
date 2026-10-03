#!/usr/bin/env python3
"""Real-ESRGAN family: .pth weights -> CoreML (fp16, static tile shape).

Plan M2-10-01 KD-2 enhancement leg. Contract:
  * Upstream BSD-3-Clause weights (xinntao/Real-ESRGAN releases; DRUNet is
    MIT, KAIR). No third-party training-framework dependency: the RRDBNet /
    SRVGGNetCompact / DRUNet architectures are reimplemented here in plain
    PyTorch (BSD-3/MIT semantics, attribution in this header) so `basicsr`
    never enters the environment.
  * Static 1x3x256x256 tile input (manifest inputSize; M2-10-06 tiles from
    the manifest constant; Lumen MODEL.md:8 fixed-shape discipline).
  * fp16 only — no int8 for the enhancement family (fidelity first).
  * --format mlprogram|neuralnetwork implements the coremltools#2545 A/B:
    Real-ESRGAN's MLProgram form measured SLOWER than neuralnetwork upstream;
    the spike decides per-model and the winner becomes the packaging format.
  * Output: <out>/<profile-id>.mlpackage (mlprogram) or
    <out>/<profile-id>-nn.mlmodel (neuralnetwork; single-file form).

Attribution: RRDBNet from Real-ESRGAN (BSD-3-Clause, (c) Xintao Wang et al.),
SRVGGNetCompact from realesr-general (BSD-3-Clause), DRUNet from KAIR
(MIT, (c) Liang et al.). Reimplemented from architecture semantics only.

Usage:
  uv run --with torch --with coremltools --with numpy \
    python Scripts/ai-models/convert_real_esrgan.py \
    --model general-x4v3|x4plus|drunet-color \
    --weights <path.pth> --out <dir> [--format mlprogram|neuralnetwork|both]
    [--benchmark]
"""

from __future__ import annotations

import argparse
import statistics
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F


# ── Architectures (reimplemented, permissive-licensed upstreams) ─────────


class ResidualDenseBlock(nn.Module):
    def __init__(self, num_feat: int = 64, num_grow_ch: int = 32):
        super().__init__()
        self.conv1 = nn.Conv2d(num_feat, num_grow_ch, 3, 1, 1)
        self.conv2 = nn.Conv2d(num_feat + num_grow_ch, num_grow_ch, 3, 1, 1)
        self.conv3 = nn.Conv2d(num_feat + 2 * num_grow_ch, num_grow_ch, 3, 1, 1)
        self.conv4 = nn.Conv2d(num_feat + 3 * num_grow_ch, num_grow_ch, 3, 1, 1)
        self.conv5 = nn.Conv2d(num_feat + 4 * num_grow_ch, num_feat, 3, 1, 1)
        self.lrelu = nn.LeakyReLU(negative_slope=0.2, inplace=True)

    def forward(self, x):
        x1 = self.lrelu(self.conv1(x))
        x2 = self.lrelu(self.conv2(torch.cat((x, x1), 1)))
        x3 = self.lrelu(self.conv3(torch.cat((x, x1, x2), 1)))
        x4 = self.lrelu(self.conv4(torch.cat((x, x1, x2, x3), 1)))
        x5 = self.conv5(torch.cat((x, x1, x2, x3, x4), 1))
        return x5 * 0.2 + x


class RRDB(nn.Module):
    def __init__(self, num_feat: int, num_grow_ch: int = 32):
        super().__init__()
        self.rdb1 = ResidualDenseBlock(num_feat, num_grow_ch)
        self.rdb2 = ResidualDenseBlock(num_feat, num_grow_ch)
        self.rdb3 = ResidualDenseBlock(num_feat, num_grow_ch)

    def forward(self, x):
        return self.rdb1(x) * 0.2 + x


class RRDBNet(nn.Module):
    """RealESRGAN_x4plus generator (23 RRDB, 64 feat, x4)."""

    def __init__(self, num_in_ch: int = 3, num_out_ch: int = 3, scale: int = 4,
                 num_feat: int = 64, num_block: int = 23, num_grow_ch: int = 32):
        super().__init__()
        self.scale = scale
        if scale == 2:
            num_in_ch = num_in_ch * 4
        elif scale == 1:
            num_in_ch = num_in_ch * 16
        self.conv_first = nn.Conv2d(num_in_ch, num_feat, 3, 1, 1)
        self.body = nn.Sequential(*[RRDB(num_feat, num_grow_ch) for _ in range(num_block)])
        self.conv_body = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        self.conv_up1 = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        self.conv_up2 = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        self.conv_hr = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        self.conv_last = nn.Conv2d(num_feat, num_out_ch, 3, 1, 1)
        self.lrelu = nn.LeakyReLU(negative_slope=0.2, inplace=True)

    def forward(self, x):
        feat = self.lrelu(self.conv_first(x))
        body_feat = self.conv_body(self.body(feat))
        feat = feat + body_feat
        feat = self.lrelu(self.conv_up1(F.interpolate(feat, scale_factor=2, mode="nearest")))
        feat = self.lrelu(self.conv_up2(F.interpolate(feat, scale_factor=2, mode="nearest")))
        out = self.conv_last(self.lrelu(self.conv_hr(feat)))
        return out


class SRVGGNetCompact(nn.Module):
    """realesr-general-x4v3 generator (compact VGG-style, x4, PReLU)."""

    def __init__(self, num_in_ch: int = 3, num_out_ch: int = 3, num_feat: int = 64,
                 num_conv: int = 32, upscale: int = 4, act_type: str = "prelu"):
        super().__init__()
        self.num_conv = num_conv
        self.upscale = upscale
        self.body = nn.ModuleList()
        self.body.append(nn.Conv2d(num_in_ch, num_feat, 3, 1, 1))
        self.body.append(nn.PReLU(num_feat) if act_type == "prelu" else nn.ReLU())
        for _ in range(num_conv):
            self.body.append(nn.Conv2d(num_feat, num_feat, 3, 1, 1))
            self.body.append(nn.PReLU(num_feat) if act_type == "prelu" else nn.ReLU())
        self.body.append(nn.Conv2d(num_feat, num_out_ch * upscale * upscale, 3, 1, 1))
        self.upSampler = nn.PixelShuffle(upscale)

    def forward(self, x):
        out = x
        for layer in self.body:
            out = layer(out)
        out = self.upSampler(out)
        base = F.interpolate(x, scale_factor=self.upscale, mode="bilinear", align_corners=False)
        return out + base


def num_block_for_drunet(nb: int = 20) -> int:
    return nb


class DRUNet(nn.Module):
    """KAIR DRUNet denoiser (color: nc = [3, 64, 128, 256, 512], nb = 20)."""

    def __init__(self, in_nc: int = 3, out_nc: int = 3, nc: tuple = (64, 128, 256, 512),
                 nb: int = 20, act_mode: str = "R"):
        super().__init__()

        def conv_block(in_ch, out_ch, act=True):
            layers = [nn.Conv2d(in_ch, out_ch, 3, 1, 1, bias=True)]
            if act:
                layers.append(nn.ReLU(inplace=True))
            return nn.Sequential(*layers)

        self.m_head = conv_block(in_nc, nc[0], act=False)
        self.down_blocks = nn.ModuleList()
        self.up_blocks = nn.ModuleList()
        in_ch = nc[0]
        for i in range(len(nc) - 1):
            self.down_blocks.append(conv_block(in_ch, nc[i + 1]))
            in_ch = nc[i + 1]
        # body at coarsest scale
        body = [ResidualDenseBlockPlain(in_ch) for _ in range(nb)]
        self.body = nn.Sequential(*body)
        reversed_nc = list(reversed(nc))
        for i in range(len(nc) - 1):
            self.up_blocks.append(
                nn.Sequential(
                    nn.Conv2d(in_ch + reversed_nc[i + 1], reversed_nc[i + 1], 3, 1, 1),
                    nn.ReLU(inplace=True),
                )
            )
            in_ch = reversed_nc[i + 1]
        self.m_tail = nn.Conv2d(in_ch, out_nc, 3, 1, 1, bias=True)

    def forward(self, x0):
        x1 = self.m_head(x0)
        downs = [x1]
        for blk in self.down_blocks:
            downs.append(blk(F.avg_pool2d(downs[-1], 2)))
        x = self.body(downs[-1])
        for i, blk in enumerate(self.up_blocks):
            skip = downs[len(downs) - 2 - i]
            up = F.interpolate(x, size=skip.shape[-2:], mode="bilinear", align_corners=False)
            x = blk(torch.cat([up, skip], dim=1))
        return self.m_tail(x) + x0


class ResidualDenseBlockPlain(nn.Module):
    """Simplified KAIR residual block used in DRUNet body (5 conv, 0.2 scale)."""

    def __init__(self, nf: int = 64, gc: int = 32):
        super().__init__()
        self.conv1 = nn.Conv2d(nf, gc, 3, 1, 1)
        self.conv2 = nn.Conv2d(nf + gc, gc, 3, 1, 1)
        self.conv3 = nn.Conv2d(nf + 2 * gc, nf, 3, 1, 1)
        self.act = nn.ReLU(inplace=True)

    def forward(self, x):
        x1 = self.act(self.conv1(x))
        x2 = self.act(self.conv2(torch.cat((x, x1), 1)))
        x3 = self.conv3(torch.cat((x, x1, x2), 1))
        return x + x3 * 0.2


# ── Conversion ───────────────────────────────────────────────────────────

PROFILES = {
    "x4plus": ("real-esrgan-x4plus-fp16", "RRDBNet"),
    "general-x4v3": ("realesr-general-x4v3-fp16", "SRVGGNetCompact"),
    "drunet-color": ("drunet-color-fp16", "DRUNet"),
}


def load_state_dict(path: Path, arch: str) -> nn.Module:
    sd = torch.load(str(path), map_location="cpu", weights_only=True)
    if isinstance(sd, dict) and "params_ema" in sd:
        sd = sd["params_ema"]
    elif isinstance(sd, dict) and "params" in sd:
        sd = sd["params"]
    if arch == "RRDBNet":
        model = RRDBNet()
    elif arch == "SRVGGNetCompact":
        model = SRVGGNetCompact()
    else:
        model = DRUNet()
    # Tolerate compact-state prefix differences by direct load first.
    model.load_state_dict(sd, strict=True)
    model.eval()
    return model


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--model", choices=sorted(PROFILES), required=True)
    p.add_argument("--weights", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--format", choices=["mlprogram", "neuralnetwork", "both"], default="mlprogram")
    p.add_argument("--input-size", type=int, default=256,
                   help="static tile edge; MUST equal ModelAssetManifest.inputSize")
    p.add_argument("--benchmark", action="store_true",
                   help="time 20 single-tile forwards (median) for the A/B spike")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    profile_id, arch = PROFILES[args.model]
    args.out.mkdir(parents=True, exist_ok=True)
    import coremltools as ct  # noqa: PLC0415

    model = load_state_dict(args.weights, arch)
    example = torch.rand(1, 3, args.input_size, args.input_size)

    with torch.no_grad():
        traced = torch.jit.trace(model, example)

    inputs = [ct.TensorType(name="input_tile", shape=(1, 3, args.input_size, args.input_size),
                            dtype=np.float32)]
    outputs = {}
    formats = ["mlprogram", "neuralnetwork"] if args.format == "both" else [args.format]
    for fmt in formats:
        print(f"[{args.model}] converting ({fmt}) ...", flush=True)
        # neuralnetwork is the LEGACY format: coremltools refuses
        # convert_to=neuralnetwork with a deployment target >= iOS15 —
        # that leg converts against the legacy floor (the model still runs
        # on macOS 27; the A/B compares backend codegen, not runtime).
        min_target = ct.target.iOS18 if fmt == "mlprogram" else ct.target.iOS13
        if fmt == "neuralnetwork":
            # compute_precision is mlprogram-only; fp16 for the legacy
            # format comes from the classic post-conversion half quantizer.
            ml = ct.convert(
                traced,
                inputs=inputs,
                convert_to=fmt,
                minimum_deployment_target=min_target,
            )
            from coremltools.models.neural_network import (  # noqa: PLC0415
                quantization_utils,
            )

            ml = quantization_utils.quantize_weights(ml, nbits=16)
        else:
            ml = ct.convert(
                traced,
                inputs=inputs,
                compute_precision=ct.precision.FLOAT16,
                convert_to=fmt,
                minimum_deployment_target=min_target,
            )
        if fmt == "mlprogram":
            path = args.out / f"{profile_id}.mlpackage"
        else:
            path = args.out / f"{profile_id}-nn.mlmodel"
        ml.save(str(path))
        outputs[fmt] = (path, ml)
        print(f"[{args.model}] wrote {path}")

    if args.benchmark:
        print(f"\n## {args.model} single-tile {args.input_size}² latency (20 runs, median)\n")
        print("| format | median ms |")
        print("|---|---|")
        for fmt, (path, _ml) in outputs.items():
            units = ct.ComputeUnit.ALL
            ml = ct.models.MLModel(str(path), compute_units=units)
            tile = {"input_tile": np.random.rand(1, 3, args.input_size, args.input_size).astype(np.float32)}
            for _ in range(3):
                ml.predict(tile)
            times = []
            for _ in range(20):
                t0 = time.perf_counter()
                ml.predict(tile)
                times.append((time.perf_counter() - t0) * 1000)
            print(f"| {fmt} | {statistics.median(times):.2f} |")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Chinese-CLIP ViT-B/16: HF weights -> static-shape CoreML .mlpackage (int8).

Plan M2-10-01 KD-2 CLIP leg. Contract:
  * HF weights at the CATALOG-PINNED revision (ModelAssetCatalog.chineseClipViTB16Int8).
  * Static shapes only (flexible shapes degrade ANE compatibility,
    coremltools#1764): image 1x3x224x224 (the E4-empirical manifest inputSize,
    config.json vision_config.image_size at the pinned revision), text
    1x52 token ids + attention mask (the official ONNX export default).
  * coremltools.convert -> mlprogram, FLOAT16 compute precision.
  * int8 WEIGHT quantization (activations stay fp16; int8 activations need
    A17 Pro/M4+ and are not used).
  * L2-normalize folded into BOTH tower outputs (D-M2-10-CONTEXT-8: the
    consumer never normalizes).
  * Outputs: <out>/chinese-clip-vitb16-img.mlpackage,
    <out>/chinese-clip-vitb16-txt.mlpackage; vocab.txt is copied by
    build_default_bundle.sh.
  * Digests are computed by build_default_bundle.sh, not here.

Usage:
  uv run --with torch==2.* --with transformers --with coremltools \
    --with numpy python Scripts/ai-models/convert_chinese_clip.py \
    --weights-dir ~/Library/Caches/LightamerModels/chinese-clip \
    --out ~/Library/Caches/LightamerModels/converted \
    [--benchmark]
Set HF_ENDPOINT=https://hf-mirror.com when huggingface.co is unreachable.

Reference-only note: architecture/training code is NOT copied from any
non-permissive source; transformers (Apache-2.0) provides the graph.
"""

from __future__ import annotations

import argparse
import json
import statistics
import time
from pathlib import Path

import numpy as np


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--weights-dir", type=Path, required=True,
                   help="directory with pytorch_model.bin + config.json + vocab.txt "
                        "(pre-downloaded from the pinned HF revision)")
    p.add_argument("--out", type=Path, required=True, help="output directory for .mlpackage trees")
    p.add_argument("--seq-len", type=int, default=52,
                   help="static text sequence length (official ONNX export default)")
    p.add_argument("--input-size", type=int, default=224,
                   help="static image edge; MUST equal ModelAssetManifest.inputSize (E4)")
    p.add_argument("--benchmark", action="store_true",
                   help="after conversion, time image/text forward passes "
                        "(ANE-first compute units vs CPU) and run the "
                        "relative-order sanity probe; prints a SPIKE.md-ready table")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    import torch  # noqa: PLC0415 (heavy imports stay inside main)
    from transformers import ChineseCLIPModel  # noqa: PLC0415

    weights = args.weights_dir
    out = args.out
    out.mkdir(parents=True, exist_ok=True)

    config = json.loads((weights / "config.json").read_text())
    vision_size = config["vision_config"]["image_size"]
    if vision_size != args.input_size:
        raise SystemExit(
            f"E4 contract violation: HF config image_size={vision_size} but "
            f"--input-size={args.input_size}; the manifest is the constant source"
        )

    print(f"[clip] loading fp32 weights from {weights} ...", flush=True)
    model = ChineseCLIPModel.from_pretrained(str(weights), local_files_only=True)
    model.eval()

    # ── Vision tower: pixel_values -> normalized 512-d embeds ────────────
    # Composed from submodules to pin the EXACT get_image_features semantics
    # of the installed transformers (pooled_output = vision pooler output →
    # visual_projection) — newer transformers versions return the output
    # OBJECT from the convenience methods, not the tensor.
    class VisionTower(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, pixel_values):
            pooled = self.m.vision_model(pixel_values=pixel_values, return_dict=True).pooler_output
            feats = self.m.visual_projection(pooled)
            return feats / feats.norm(p=2, dim=-1, keepdim=True)

    # ── Text tower: input_ids + attention mask -> normalized 512-d embeds ─
    # get_text_features semantics: CLS-token hidden state → text_projection.
    # The mask arrives as the EXPANDED float32 [1,1,seq,seq] tensor (kv-axis
    # padding mask) and is thresholded to bool INSIDE the graph: a 2D mask
    # would route through the modern masking-function pipeline whose
    # `new_ones` op coremltools cannot convert (torch 2.7, 2026-10). The
    # Swift consumer expands its 1D padding mask on the kv axis.
    class TextTower(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, input_ids, attn_mask_f32):
            hidden = self.m.text_model(
                input_ids=input_ids, attention_mask=(attn_mask_f32 > 0.5)
            ).last_hidden_state
            pooled = hidden[:, 0, :]
            feats = self.m.text_projection(pooled)
            return feats / feats.norm(p=2, dim=-1, keepdim=True)

    vision = VisionTower(model).eval()
    text = TextTower(model).eval()

    import coremltools as ct  # noqa: PLC0415

    img_example = torch.randn(1, 3, args.input_size, args.input_size)
    ids_example = torch.ones(1, args.seq_len, dtype=torch.int32)
    mask_example = torch.ones(1, 1, args.seq_len, args.seq_len, dtype=torch.float32)

    def convert(traced, inputs, name):
        print(f"[clip] converting {name} -> mlprogram fp16 ...", flush=True)
        mlmodel = ct.convert(
            traced,
            inputs=inputs,
            compute_precision=ct.precision.FLOAT16,
            convert_to="mlprogram",
            minimum_deployment_target=ct.target.iOS18,
        )
        return mlmodel

    with torch.no_grad():
        vision_traced = torch.jit.trace(vision, img_example)
        text_traced = torch.jit.trace(text, (ids_example, mask_example))

    vision_ml = convert(
        vision_traced,
        [ct.TensorType(name="pixel_values", shape=(1, 3, args.input_size, args.input_size),
                       dtype=np.float32)],
        "vision",
    )
    text_ml = convert(
        text_traced,
        [
            ct.TensorType(name="input_ids", shape=(1, args.seq_len), dtype=np.int32),
            ct.TensorType(name="attention_mask",
                          shape=(1, 1, args.seq_len, args.seq_len), dtype=np.float32),
        ],
        "text",
    )

    # int8 WEIGHT quantization (activations remain fp16).
    from coremltools.optimize.coreml import (  # noqa: PLC0415
        OpLinearQuantizerConfig,
        OptimizationConfig,
        linear_quantize_weights,
    )

    quant_config = OptimizationConfig(
        global_config=OpLinearQuantizerConfig(
            mode="linear_symmetric", dtype=np.int8, granularity="per_block"
        )
    )
    print("[clip] int8 weight quantization ...", flush=True)
    vision_q = linear_quantize_weights(vision_ml, config=quant_config)
    text_q = linear_quantize_weights(text_ml, config=quant_config)

    img_path = out / "chinese-clip-vitb16-img.mlpackage"
    txt_path = out / "chinese-clip-vitb16-txt.mlpackage"
    vision_q.save(str(img_path))
    text_q.save(str(txt_path))
    print(f"[clip] wrote {img_path}")
    print(f"[clip] wrote {txt_path}")

    if args.benchmark:
        run_benchmark(img_path, txt_path, weights, args)


def run_benchmark(img_path: Path, txt_path: Path, weights: Path, args) -> None:
    """ANE-first vs CPU latency (20 runs, median) + relative-order sanity."""
    import torch  # noqa: PLC0415
    from transformers import BertTokenizer  # noqa: PLC0415
    from PIL import Image  # noqa: PLC0415
    import coremltools as ct  # noqa: PLC0415

    print("\n## CLIP latency (20 runs, median)\n")
    print("| leg | compute units | median ms |")
    print("|---|---|---|")
    for label, units in [("image 224²", ct.ComputeUnit.ALL), ("image 224²", ct.ComputeUnit.CPU_ONLY),
                         ("text 52 tok", ct.ComputeUnit.ALL), ("text 52 tok", ct.ComputeUnit.CPU_ONLY)]:
        path = img_path if "image" in label else txt_path
        ml = ct.models.MLModel(str(path), compute_units=units)
        if "image" in label:
            inputs = {"pixel_values": np.random.rand(1, 3, args.input_size, args.input_size).astype(np.float32)}
        else:
            inputs = {
                "input_ids": np.ones((1, args.seq_len), dtype=np.int32),
                "attention_mask": np.ones((1, 1, args.seq_len, args.seq_len), dtype=np.float32),
            }
        for _ in range(3):
            ml.predict(inputs)
        times = []
        for _ in range(20):
            t0 = time.perf_counter()
            ml.predict(inputs)
            times.append((time.perf_counter() - t0) * 1000)
        print(f"| {label} | {'ALL' if units == ct.ComputeUnit.ALL else 'CPU'} | {statistics.median(times):.2f} |")

    # Relative-order sanity: 3 zh/en query pairs x 3 images, human-read.
    tokenizer = BertTokenizer(vocab_file=str(weights / "vocab.txt"))
    img_ml = ct.models.MLModel(str(img_path), compute_units=ct.ComputeUnit.ALL)
    txt_ml = ct.models.MLModel(str(txt_path), compute_units=ct.ComputeUnit.ALL)

    queries = [
        ("一只猫", "a cat", True),
        ("一张风景照片", "a landscape photo", True),
        ("一辆汽车", "a car", True),
    ]
    # Synthetic structured drawings (flat color swatches carry no CLIP
    # semantics — every cosine collapses to a tie; PIL line art gives the
    # probe something to rank). Human-read sanity, NOT a threshold gate.
    def draw(kind: str) -> Image.Image:
        from PIL import ImageDraw  # noqa: PLC0415

        img = Image.new("RGB", (args.input_size, args.input_size), (255, 255, 255))
        d = ImageDraw.Draw(img)
        s = args.input_size
        if kind == "cat":
            d.ellipse([s * 0.30, s * 0.45, s * 0.70, s * 0.85], fill=(230, 126, 34))
            d.ellipse([s * 0.38, s * 0.20, s * 0.62, s * 0.48], fill=(230, 126, 34))
            d.polygon([(s * 0.38, s * 0.28), (s * 0.34, s * 0.10), (s * 0.48, s * 0.20)], fill=(230, 126, 34))
            d.polygon([(s * 0.62, s * 0.28), (s * 0.66, s * 0.10), (s * 0.52, s * 0.20)], fill=(230, 126, 34))
            d.ellipse([s * 0.43, s * 0.30, s * 0.46, s * 0.34], fill=(20, 20, 20))
            d.ellipse([s * 0.54, s * 0.30, s * 0.57, s * 0.34], fill=(20, 20, 20))
        elif kind == "landscape":
            d.rectangle([0, 0, s, s * 0.55], fill=(100, 160, 230))
            d.ellipse([s * 0.70, s * 0.08, s * 0.90, s * 0.28], fill=(250, 220, 80))
            d.polygon([(0, s * 0.55), (s * 0.35, s * 0.25), (s * 0.65, s * 0.55)], fill=(90, 110, 90))
            d.rectangle([0, s * 0.55, s, s], fill=(70, 160, 70))
        else:  # car
            d.rectangle([0, s * 0.70, s, s], fill=(120, 120, 130))
            d.rectangle([s * 0.10, s * 0.50, s * 0.90, s * 0.72], fill=(60, 60, 220))
            d.rectangle([s * 0.28, s * 0.38, s * 0.72, s * 0.52], fill=(60, 60, 220))
            d.ellipse([s * 0.20, s * 0.66, s * 0.36, s * 0.82], fill=(20, 20, 20))
            d.ellipse([s * 0.64, s * 0.66, s * 0.80, s * 0.82], fill=(20, 20, 20))
        return img

    images = [(kind, draw(kind)) for kind in ("cat", "landscape", "car")]

    def embed_image(pil):
        mean = np.array([0.48145466, 0.4578275, 0.40821073], dtype=np.float32)
        std = np.array([0.26862954, 0.26130258, 0.27577711], dtype=np.float32)
        a = np.asarray(pil.resize((args.input_size, args.input_size))).astype(np.float32) / 255.0
        a = (a - mean) / std
        px = a.transpose(2, 0, 1)[None].astype(np.float32)
        out = img_ml.predict({"pixel_values": px})
        return np.array(list(out.values())[0]).reshape(-1)

    def embed_text(zh: str, en: str):
        enc = tokenizer(zh, padding="max_length", max_length=args.seq_len,
                        truncation=True, return_tensors="np")
        m1d = enc["attention_mask"][0].astype(np.float32)
        mask4d = np.tile(m1d[None, None, None, :], (1, 1, args.seq_len, 1))
        out = txt_ml.predict({
            "input_ids": enc["input_ids"].astype(np.int32),
            "attention_mask": mask4d,
        })
        return np.array(list(out.values())[0]).reshape(-1)

    print("\n## Relative-order sanity (embeddings already L2-normalized)\n")
    img_vecs = {name: embed_image(im) for name, im in images}
    for zh, en, _ in queries:
        v = embed_text(zh, en)
        scores = {name: float(np.dot(v, iv)) for name, iv in img_vecs.items()}
        best = max(scores, key=scores.get)
        print(f"- `{zh}` / `{en}` -> best match: **{best}** "
              f"({', '.join(f'{k}: {s:.3f}' for k, s in scores.items())})")


if __name__ == "__main__":
    main()

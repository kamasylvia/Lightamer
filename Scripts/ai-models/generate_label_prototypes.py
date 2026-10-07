#!/usr/bin/env python3
"""Generate the factory label-query prototype embeddings (M2-10-03 KD-1).

SOURCE OF TRUTH: LightamerCore/Sources/AI/LabelQueries.swift — this script
PARSES the factory catalog out of the Swift source (strict one-line
`LabelQueryEntry(label: "…", queryZH: "…", queryEN: "…"),` entries; the file
header pins the format). Each label's ENGLISH query is embedded through the
PINNED-REVISION Chinese-CLIP text tower, L2-normalized, quantized to fp16
little-endian, and written next to the model packages:

  <profile-dir>/label-prototypes/prototypes.json
      {"revision": <catalog pin>, "dim": 512, "count": N,
       "labels": [{"label": …, "offset": <vector index>}, …]}
  <profile-dir>/label-prototypes/prototypes.bin
      N * dim * 2 bytes, fp16 LE, catalog/index order

The prototypes ride the model revision and die with it
(D-M2-10-CONTEXT-7); LabelPrototypeSet.load refuses a revision mismatch.

Usage (mirrors convert_chinese_clip.py's environment):
  uv run --with "torch==2.7.*" --with "transformers<5" --with numpy \
    python Scripts/ai-models/generate_label_prototypes.py \
    --weights-dir ~/Library/Caches/LightamerModels/chinese-clip \
    --profile-dir Resources/AIModels/chinese-clip-vitb16-int8 \
    --catalog   LightamerCore/Sources/AI/LabelQueries.swift \
    --manifest  LightamerCore/Sources/AI/ModelAssetCatalog.swift

transformers is pinned <5: 5.x silently loads only the special tokens from
a bare vocab_file (M2-10-02 tokenizer lesson).
Set HF_ENDPOINT=https://hf-mirror.com when huggingface.co is unreachable.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ENTRY_RE = re.compile(
    r'LabelQueryEntry\(label: "([^"]+)", queryZH: "([^"]*)", queryEN: "([^"]*)"\),'
)
REVISION_BLOCK_RE = re.compile(
    r"chineseClipViTB16Int8\s*=\s*ModelAssetManifest\(.*?\)", re.DOTALL
)
REVISION_RE = re.compile(r'revision:\s*"([^"]+)"')


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--weights-dir", type=Path, required=True,
                   help="directory with pytorch_model.bin + vocab.txt (the pinned HF revision)")
    p.add_argument("--profile-dir", type=Path, required=True,
                   help="the bundle profile directory; label-prototypes/ is written inside")
    p.add_argument("--catalog", type=Path, required=True,
                   help="LabelQueries.swift (the parsed source of truth)")
    p.add_argument("--manifest", type=Path, required=True,
                   help="ModelAssetCatalog.swift (the revision pin is parsed from it)")
    p.add_argument("--seq-len", type=int, default=52,
                   help="static text sequence length (the conversion contract)")
    return p.parse_args()


def parse_catalog(path: Path) -> list[tuple[str, str, str]]:
    text = path.read_text(encoding="utf-8")
    entries = [
        e for e in ENTRY_RE.findall(text)
        if "…" not in e[0] and "…" not in e[1] and "…" not in e[2]
    ]
    if not entries:
        raise SystemExit(f"no LabelQueryEntry lines parsed from {path}")
    labels = [e[0] for e in entries]
    if len(set(labels)) != len(labels):
        raise SystemExit("duplicate labels in the factory catalog")
    return entries


def parse_revision(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    block = REVISION_BLOCK_RE.search(text)
    if not block:
        raise SystemExit(f"chineseClipViTB16Int8 manifest block not found in {path}")
    rev = REVISION_RE.search(block.group(0))
    if not rev:
        raise SystemExit("revision pin not found inside the manifest block")
    return rev.group(1)


def main() -> None:
    args = parse_args()
    entries = parse_catalog(args.catalog)
    revision = parse_revision(args.manifest)
    print(f"[prototypes] catalog labels: {len(entries)}; revision: {revision[:12]}…",
          flush=True)

    import numpy as np  # noqa: PLC0415
    import torch  # noqa: PLC0415
    from transformers import BertTokenizer, ChineseCLIPModel  # noqa: PLC0415

    model = ChineseCLIPModel.from_pretrained(
        str(args.weights_dir), local_files_only=True)
    model.eval()
    tokenizer = BertTokenizer(vocab_file=str(args.weights_dir / "vocab.txt"))

    @torch.no_grad()
    def embed(query: str) -> np.ndarray:
        enc = tokenizer(query, padding="max_length", max_length=args.seq_len,
                        truncation=True, return_tensors="pt")
        # get_text_features semantics via submodules (newer transformers
        # returns the output OBJECT from the convenience methods — the same
        # conversion-script lesson): CLS hidden state → text_projection.
        hidden = model.text_model(
            input_ids=enc["input_ids"],
            attention_mask=enc["attention_mask"],
        ).last_hidden_state
        feats = model.text_projection(hidden[:, 0, :])
        feats = feats / feats.norm(p=2, dim=-1, keepdim=True)
        return feats.squeeze(0).numpy().astype("<f2")

    out_dir = args.profile_dir / "label-prototypes"
    out_dir.mkdir(parents=True, exist_ok=True)
    payload = bytearray()
    labels = []
    for index, (label, _zh, en) in enumerate(entries):
        vector = embed(en)
        if vector.shape[0] != 512:
            raise SystemExit(f"unexpected width {vector.shape[0]} for {label}")
        payload.extend(vector.tobytes())
        labels.append({"label": label, "offset": index})
        if (index + 1) % 40 == 0 or index + 1 == len(entries):
            print(f"[prototypes] embedded {index + 1}/{len(entries)}", flush=True)

    index_json = {
        "revision": revision,
        "dim": 512,
        "count": len(entries),
        "labels": labels,
    }
    (out_dir / "prototypes.json").write_text(
        json.dumps(index_json, ensure_ascii=False, indent=1) + "\n",
        encoding="utf-8")
    (out_dir / "prototypes.bin").write_bytes(bytes(payload))
    print(f"[prototypes] wrote {out_dir}/prototypes.{{json,bin}} "
          f"({len(payload)} bytes payload)", flush=True)


if __name__ == "__main__":
    main()

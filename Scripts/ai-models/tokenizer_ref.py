#!/usr/bin/env python3
# tokenizer_ref.py — WordPiece golden fixture generator (Plan M2-10-02 T1,
# KD-3's anti-hand-copy mechanism; checker E2 registered artifact).
#
# Runs the reference `transformers` BertTokenizer (do_lower_case=True, the
# Chinese-BERT convention the Swift implementation mirrors) against the
# SHIPPED vocab.txt at the pinned revision, tokenizes twelve fixed sentences
# (zh / en / mixed / digits / accents / katakana / subword / over-100-char
# truncation / whitespace normalization), and writes
# Tests/Fixtures/tokenizer_golden.json.
#
# The fixture LOCKS the vocab revision: `revision` is stamped into the JSON
# and must equal ModelAssetCatalog.chineseClipViTB16Int8.revision. Regenerate
# ONLY when the asset revision moves (and expect the Swift golden tests to
# verify byte-for-byte against the new reference).
#
# transformers 5.x BROKE slow-tokenizer vocab_file loading (silently loads
# special tokens only — vocab_size 5) — pin the 4.x line:
#
# Usage (from the repo root):
#   uv run --with "transformers<5" python3 Scripts/ai-models/tokenizer_ref.py \
#     --vocab Resources/AIModels/chinese-clip-vitb16-int8/vocab.txt \
#     --revision 36e679e65c2a2fead755ae21162091293ad37834 \
#     --out Tests/Fixtures/tokenizer_golden.json
#
# The fixture is <=10KB and COMMITTED; tests run without the model assets
# (they rebuild a reduced vocab from the fixture's own token inventory —
# the CI face has no network and no AIModels directory).

import argparse
import json
import sys

MAX_LENGTH = 52  # the static shape (M2-10-01 export contract)

CASES = [
    # 1. plain English
    "a photo of a golden retriever playing on the beach",
    # 2. plain Chinese
    "海边奔跑的金毛犬照片",
    # 3. mixed digits + punctuation + Chinese
    "一张2024年6月在海边拍摄的f/2.8照片",
    # 4. English with punctuation
    "sunset over the mountains, HDR photography",
    # 5. accents (NFD strip + lowercase)
    "Café Résumé Naïve",
    # 6. katakana (outside the BERT CJK ranges — per-char WordPiece)
    "パノラマ写真",
    # 7. standalone EXIF-ish numbers
    "ISO 1600 f2.8 35mm",
    # 8. one long subword-decomposable word
    "supercalifragilisticexpialidocious",
    # 9. over-100-char word -> [UNK]
    "x" * 120 + " photo",
    # 10. mixed Chinese + English
    "城市夜景与霓虹灯 City nightscape",
    # 11. whitespace normalization
    "  multiple   spaces\tand\nnewlines  ",
    # 12. the sanity-search query leg (real-model end-to-end)
    "a clear blue sky",
]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vocab", required=True, help="path to vocab.txt")
    parser.add_argument("--revision", required=True, help="upstream revision pin")
    parser.add_argument("--out", required=True, help="fixture output path")
    args = parser.parse_args()

    from transformers import BertTokenizer

    tokenizer = BertTokenizer(
        vocab_file=args.vocab, do_lower_case=True, model_max_length=MAX_LENGTH
    )

    cases = []
    for text in CASES:
        encoded = tokenizer(
            text, padding="max_length", truncation=True, max_length=MAX_LENGTH
        )
        ids = encoded["input_ids"]
        mask = encoded["attention_mask"]
        tokens = tokenizer.convert_ids_to_tokens(ids)
        assert len(ids) == MAX_LENGTH and len(mask) == MAX_LENGTH
        # Trim the trailing [PAD] run from `tokens` (the padded id/mask rows
        # stay full-length; the Swift golden test reconstructs the pads).
        end = len(tokens)
        while end > 0 and tokens[end - 1] == "[PAD]":
            end -= 1
        cases.append({
            "text": text,
            "tokens": tokens[:end],
            "ids": ids,
            "mask": mask,
        })

    fixture = {
        "revision": args.revision,
        "vocab_source": args.vocab,
        "max_tokens": MAX_LENGTH,
        "do_lower_case": True,
        "cases": cases,
    }
    # Compact separators: the fixture budget is <=10KB in-repo.
    payload = json.dumps(fixture, ensure_ascii=False, separators=(",", ":")) + "\n"
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write(payload)
    size = len(payload.encode("utf-8"))
    print(f"wrote {args.out}: {len(cases)} cases, {size} bytes")
    if size > 10 * 1024:
        print("FIXTURE EXCEEDS THE 10KB BUDGET", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

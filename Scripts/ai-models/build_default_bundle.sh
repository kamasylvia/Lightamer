#!/bin/zsh
# build_default_bundle.sh — rebuild the bundled AI model assets end to end.
#
# Plan M2-10-01 KD-2/KD-4. Chain: convert Chinese-CLIP ViT-B/16 (int8) +
# realesr-general-x4v3 (fp16, A/B-winning format) -> assemble the repo-root
# Resources/AIModels folder reference (E1; model bytes are gitignored —
# volume red line: nothing under Resources/AIModels except .keep is tracked)
# -> compute SHA-256 over the FINAL DISTRIBUTION BYTES in place ->
# rewrite the `= nil` sentinel lines in ModelAssetDigests.generated.swift.
#
# Usage:
#   Scripts/ai-models/build_default_bundle.sh [--skip-convert] [--skip-digests]
#
# Prerequisites:
#   ~/Library/Caches/LightamerModels/chinese-clip/  (pinned-revision HF files)
#   ~/Library/Caches/LightamerModels/realesrgan/    (upstream release .pth)
# All python execution goes through `uv run` (global toolchain red line:
# no bare python3).

set -euo pipefail

ROOT="${0:A:h:h:h}"                       # repo root
CACHE="$HOME/Library/Caches/LightamerModels"
CONVERTED="$CACHE/converted"
BUNDLE_DIR="$ROOT/Resources/AIModels"
DIGESTS_SWIFT="$ROOT/LightamerCore/Sources/AI/ModelAssetDigests.generated.swift"

CLIP_W="$CACHE/chinese-clip"
ESRGAN_W="$CACHE/realesrgan"

SKIP_CONVERT=0
SKIP_DIGESTS=0
for arg in "$@"; do
  case "$arg" in
    --skip-convert) SKIP_CONVERT=1 ;;
    --skip-digests) SKIP_DIGESTS=1 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

mkdir -p "$CONVERTED"

# ── 1. Convert ───────────────────────────────────────────────────────────
if [[ $SKIP_CONVERT -eq 0 ]]; then
  echo "==> convert_chinese_clip.py (int8, static 224²/52tok)"
  uv run --with "torch==2.7.*" --with transformers --with coremltools --with numpy --with pillow \
    python "$ROOT/Scripts/ai-models/convert_chinese_clip.py" \
    --weights-dir "$CLIP_W" --out "$CONVERTED" --benchmark

  echo "==> convert_real_esrgan.py x4plus A/B (mlprogram vs neuralnetwork, #2545)"
  uv run --with "torch==2.7.*" --with coremltools --with numpy \
    python "$ROOT/Scripts/ai-models/convert_real_esrgan.py" \
    --model x4plus --weights "$ESRGAN_W/RealESRGAN_x4plus.pth" \
    --out "$CONVERTED" --format both --benchmark

  echo "==> convert_real_esrgan.py general-x4v3 (winner format)"
  uv run --with "torch==2.7.*" --with coremltools --with numpy \
    python "$ROOT/Scripts/ai-models/convert_real_esrgan.py" \
    --model general-x4v3 --weights "$ESRGAN_W/realesr-general-x4v3.pth" \
    --out "$CONVERTED" --format mlprogram --benchmark
fi

# ── 2. Assemble the bundle folder reference ─────────────────────────────
echo "==> assembling $BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/chinese-clip-vitb16-int8" "$BUNDLE_DIR/realesr-general-x4v3-fp16"
rm -rf "$BUNDLE_DIR/chinese-clip-vitb16-int8/chinese-clip-vitb16-img.mlpackage" \
       "$BUNDLE_DIR/chinese-clip-vitb16-int8/chinese-clip-vitb16-txt.mlpackage" \
       "$BUNDLE_DIR/realesr-general-x4v3-fp16/realesr-general-x4v3-fp16.mlpackage"
cp -R "$CONVERTED/chinese-clip-vitb16-img.mlpackage" "$BUNDLE_DIR/chinese-clip-vitb16-int8/"
cp -R "$CONVERTED/chinese-clip-vitb16-txt.mlpackage" "$BUNDLE_DIR/chinese-clip-vitb16-int8/"
cp "$CLIP_W/vocab.txt" "$BUNDLE_DIR/chinese-clip-vitb16-int8/vocab.txt"
cp -R "$CONVERTED/realesr-general-x4v3-fp16.mlpackage" "$BUNDLE_DIR/realesr-general-x4v3-fp16/"

# Label-prototype placeholder (M2-10-03 ships the real prototype embeddings;
# they ride WITH the model revision and never enter the user library/git).
mkdir -p "$BUNDLE_DIR/chinese-clip-vitb16-int8/prototypes"
cat > "$BUNDLE_DIR/chinese-clip-vitb16-int8/prototypes/README.txt" <<'EOF'
Label query prototype embeddings (M2-10-03) ship here.
They are generated from the SAME model revision as the sibling .mlpackage
files and die with it (D-M2-10-CONTEXT-7). Never copied into the user library.
EOF

# ── 3. Digests (SHA-256 over the final in-bundle distribution bytes) ────
if [[ $SKIP_DIGESTS -eq 0 ]]; then
  echo "==> rewriting ModelAssetDigests.generated.swift"
  uv run python - "$DIGESTS_SWIFT" "$BUNDLE_DIR" <<'PYEOF'
import hashlib
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def artifact_digest(path: Path):
    """(sha256, byteCount) for a file, or a canonical tree hash for a dir.

    Tree hash: sorted relative paths; one line per file
    "<relpath> <size> <sha256>\\n"; SHA-256 over the concatenated UTF-8
    lines. The Swift verifier (ModelAssetStore) implements the same rule.
    """
    if path.is_file():
        return sha256_file(path), path.stat().st_size
    lines = []
    total = 0
    files = sorted(
        (p for p in path.rglob("*") if p.is_file()),
        key=lambda p: p.relative_to(path).as_posix(),
    )
    for f in files:
        size = f.stat().st_size
        total += size
        lines.append(f"{f.relative_to(path).as_posix()} {size} {sha256_file(f)}\n")
    h = hashlib.sha256()
    for line in lines:
        h.update(line.encode("utf-8"))
    return h.hexdigest(), total

swift_path = Path(sys.argv[1])
bundle_dir = Path(sys.argv[2])

# profile_id -> (primary artifact, [(name, artifact)]) — all read from the
# assembled bundle, so the digests pin exactly the shipped bytes.
clip_profile = bundle_dir / "chinese-clip-vitb16-int8"
# profile_id -> (swift sentinel name, primary artifact, [(name, artifact)])
PROFILES = {
    "chinese-clip-vitb16-int8": (
        "chineseClipViTB16Int8",
        clip_profile / "chinese-clip-vitb16-img.mlpackage",
        [
            ("chinese-clip-vitb16-txt.mlpackage",
             clip_profile / "chinese-clip-vitb16-txt.mlpackage"),
            ("vocab.txt", clip_profile / "vocab.txt"),
        ],
    ),
    "realesr-general-x4v3-fp16": (
        "realesrGeneralX4V3FP16",
        bundle_dir / "realesr-general-x4v3-fp16" / "realesr-general-x4v3-fp16.mlpackage",
        [],
    ),
}

generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
text = swift_path.read_text()
for profile, (sentinel, primary, aux) in PROFILES.items():
    if not primary.exists():
        print(f"!! primary artifact missing for {profile}: {primary} — leaving digest nil")
        continue
    sha, count = artifact_digest(primary)
    aux_literal = ""
    if aux:
        entries = []
        for name, artifact in aux:
            if not artifact.exists():
                raise SystemExit(f"auxiliary missing for {profile}: {artifact}")
            asha, acount = artifact_digest(artifact)
            entries.append(
                '            .init(fileName: "%s", sha256Hex: "%s", byteCount: %d)'
                % (name, asha, acount)
            )
        aux_literal = "\n" + ",\n".join(entries) + "\n        "
    literal = (
        "ModelAssetDigestEntry(sha256Hex: \"%s\", byteCount: %d, "
        "auxiliaryFiles: [%s], generatedAt: \"%s\")" % (sha, count, aux_literal, generated_at)
    )
    # Match the WHOLE declaration value (nil sentinel OR a previously
    # rewritten literal, which may span lines until the blank line) so the
    # chain is re-runnable — e.g. M2-10-06 re-converts after overturning the
    # format ruling, and the sentinels are already non-nil then.
    pattern = re.compile(
        r"private static let %s: ModelAssetDigestEntry\? = .*?(?=\n\n)" % sentinel,
        re.DOTALL,
    )
    text, n = pattern.subn(
        lambda m: "private static let %s: ModelAssetDigestEntry? = %s" % (sentinel, literal),
        text,
    )
    if n != 1:
        raise SystemExit(f"sentinel not found (or not unique) for {profile}")
    print(f"== {profile}: {count} bytes sha256={sha[:16]}... aux={len(aux)}")

swift_path.write_text(text)
print("== digests rewritten")
PYEOF
fi

# ── 4. Git hygiene check (model bytes must stay ignored) ────────────────
echo "==> git hygiene check"
DIRTY=$(git -C "$ROOT" status --porcelain Resources/AIModels | grep -v '\.keep' || true)
if [[ -n "$DIRTY" ]]; then
  echo "!! non-.keep paths under Resources/AIModels visible to git — check .gitignore" >&2
  echo "$DIRTY" >&2
  exit 1
fi

echo "OK: bundle assembled at $BUNDLE_DIR"
du -sh "$BUNDLE_DIR"/* 2>/dev/null || true
